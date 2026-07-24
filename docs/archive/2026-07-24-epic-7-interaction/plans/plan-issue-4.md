# Epic 7 Issue 4 — PDF 熱區導覽 + 沉浸模式基礎建設 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `ReaderScreen` 統一的沉浸模式（介面顯示/隱藏）與熱區動作分派機制（`_handleZoneAction`，供 Issue 5/6/7 後續複用），並以 PDF 落地：`PdfReaderView` 新增 3×3 導航熱區點擊判讀，移除既有橫向滑動翻頁手勢（ADR 0010）。

**Architecture:** `ReaderScreen` 既有的 FXL 專屬 `_fixedLayoutControlsVisible` 欄位改名／擴大為格式無關的 `_chromeVisible`，AppBar／`ReaderFooter` 的顯示判斷式一併擴充成同時尊重這個新的通用狀態（純改名+擴大判斷式，FXL 既有行為零回歸）。新增單一分派入口 `_handleZoneAction(ZoneAction action)`：`menu` 切換 `_chromeVisible`、`previousPage`/`nextPage` 呼叫格式對應的既有換頁方法、`none` 不做事。`PdfReaderView` 這邊，熱區的座標判讀（`hitTestZoneIndex()`）與動作查表（`navZoneActions[index]`）完全在 Dart 端完成、不送任何新資料給原生 Kotlin（原生端本 issue 不需修改，見 spec.md「`PdfReaderView.kt`」段落）；判讀出動作後透過新增的 `onZoneAction` 回呼把結果（不是座標，是已經解析好的 `ZoneAction`）回報給 `ReaderScreen`，複用同一個 `_handleZoneAction` 入口。`PdfReaderView` 新增的 3 個建構參數（`navZoneActions`／`onZoneAction`／`showNavZoneDebugOverlay`）刻意設計為**可選、附安全預設值**（比照該檔案既有 `onCropRectComputed`／`dualPageMode` 等欄位慣例），因為 `pdf_reader_view_test.dart` 現有超過 20 處 `PdfReaderView(...)` 建構呼叫點只關心裁切/劃線等既有功能，若把新參數設為 `required` 會逼這些既有測試逐一補參數，屬於不必要的大規模連帶修改。

**Tech Stack:** Flutter（`GestureDetector.onTapUp`／`Stack`＋`IgnorePointer` 疊加層）、既有 `hitTestZoneIndex()`／`ZoneAction`（epic-7 Issue 2 已完成）、`flutter_test`（純 Dart 手勢派發可離線驗證，無需真實裝置）、`integration_test`（真實裝置，驗證原生渲染下的端到端行為與長按框選共存不誤觸發）。

## Global Constraints

- `_fixedLayoutControlsVisible` 全域改名為 `_chromeVisible`（`app/lib/screens/reader_screen.dart`），語意由「FXL 專屬」擴大為「格式無關的介面顯示狀態」，**純改名，FXL 既有行為（三欄/懸浮按鈕收合/展開邏輯）零改變**——只有 AppBar／`ReaderFooter` 的判斷式範圍會擴大（見下）。
- AppBar 判斷式：`(_isFixedLayout || !_chromeVisible) ? null : AppBar(...)`（既有 `_isFixedLayout ? null : AppBar(...)` 基礎上疊加）。
- `ReaderFooter` 顯示條件在既有判斷式之外，統一疊加 `&& _chromeVisible`（PDF／EPUB 兩處判斷式都要加）。
- **審查修正（Critical）**：Scaffold 新增 `extendBodyBehindAppBar: true`，`_buildBody()` 的 `SafeArea` 改為 `top: false` 並改用固定的 `MediaQuery.viewPadding.top`（外層另包一層 `Padding`）——避免 AppBar 顯示/隱藏（沉浸模式切換）連帶改變 `body` 的版面約束、觸發底下 `PlatformView` resize。這段邏輯是 Issue 5/6/7 共用基礎設施，Issue 6（EPUB 流式）若直接沿用未修正版本，AndroidView/WebView 的 resize 會觸發 Readium 整本書重新分頁，是嚴重效能與體驗問題，必須在本 Task 建立共用邏輯時就收斂，細節見 Task 1 內對應區塊。
- 新增 `void _handleZoneAction(ZoneAction action)`：`previousPage`/`nextPage` 呼叫格式對應的既有換頁方法；`menu` 執行 `setState(() => _chromeVisible = !_chromeVisible)`；`none` 不做事。**`previousPage`/`nextPage` 不得變更 `_chromeVisible`**（design.md 決策 #14：翻頁動作不影響沉浸模式）。
- PDF 熱區疊加層**只註冊 `onTap`（本計畫用 `onTapUp` 取得座標），不註冊任何 drag recognizer**——`PdfReaderView.kt` 原生層無任何觸控監聽，不需要搶手勢競技場；與既有長按拖曳框選 `onLongPressStart`/`onLongPressMoveUpdate`/`onLongPressEnd`（`epic-6-annotations` Issue 3）**共存於同一個既有 `GestureDetector`**，不新建第二個 `GestureDetector`（避免兩個獨立手勢偵測器在同一畫面區域競爭手勢競技場）。
- 既有 `onHorizontalDragEnd`（滑動翻頁）整段移除（ADR 0010）。全文檢索確認 `pdf_reader_view_test.dart` **沒有任何既有測試**驗證這個 handler，不需要同步刪除/改寫既有測試。
- `PdfReaderView` 新增的 `navZoneActions`／`onZoneAction`／`showNavZoneDebugOverlay` 三個參數是**純 Dart 端狀態**，不透過 `openBook`/`setPdfPreferences` 送給原生 Kotlin（`PdfReaderView.kt` 本 issue 不需修改，見 spec.md「`PdfReaderView.kt`——本 epic 不需修改」）；不要把它們加進 `initialPreferences`/`setPdfPreferences` 的 method channel payload。
- `navZoneActions` 預設值為全 9 格 `ZoneAction.none`（非 `required`），`onZoneAction` 預設 `null`（非 `required`）——保持既有數十處 `PdfReaderView(...)` 測試呼叫點零破壞。
- 座標轉格子索引一律用既有 `hitTestZoneIndex()`（`app/lib/reader/zone_hit_test.dart`，epic-7 Issue 2），0-indexed、列優先，不要重新發明演算法。
- **`integration_test` 對原生 `AndroidView` 的觸控手勢模擬不可靠**（本專案既有慣例，見 `pdf_highlights_notes_test.dart` 開頭的既定聲明）：本計畫的 `integration_test`（Task 4）自動化部分只驗證「透過 `ReaderScreen.triggerZoneAction` 靜態 helper 直接呼叫 `_handleZoneAction`」這條**分派邏輯**在真機原生渲染下確實生效（例如真的翻到下一頁、真的切換沉浸模式），**不嘗試**用 `tester.tap`/`tester.longPress` 模擬手指實際點在螢幕座標上；「手指實際點擊 9 宮格哪一格對應到哪個動作」與「熱區點擊和長按拖曳劃線交叉操作不誤觸發」兩項改為文件化的人工驗證清單（比照 `pdf_highlights_notes_test.dart` 既有先例）。
- 本 issue 完全不涉及 EPUB（FXL／流式），`_handleZoneAction` 的 `previousPage`/`nextPage` 分支目前只實作 PDF 分支；EPUB FXL 分支由 Issue 5 擴充、EPUB 流式的 `previousPage`/`nextPage` 完全不經過這個方法（由原生 Kotlin `InputListener` 自主處理，見 spec.md，只有 `menu` 動作經 Issue 6 的 `onZoneTapped` 回呼）。
- `flutter analyze` 全程須保持乾淨；Task 1-3 完全不需要真實裝置即可驗收，Task 4 需要真實裝置/模擬器。
- 套件名稱為 `elinkbook`（測試檔 import 一律 `package:elinkbook/...`）。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/lib/screens/reader_screen.dart` | 修改 | `_fixedLayoutControlsVisible` 改名 `_chromeVisible`；AppBar／`ReaderFooter` 判斷式擴大；新增 `_handleZoneAction()`／`ReaderScreen.triggerZoneAction()` 靜態 helper；`_buildNativeView()` 內 `PdfReaderView(...)` 建構補上 3 個新參數 |
| `app/lib/reader/pdf_reader_view.dart` | 修改 | 移除 `onHorizontalDragEnd`；新增 `navZoneActions`／`onZoneAction`／`showNavZoneDebugOverlay` 建構參數；新增 `onTapUp` 熱區判讀＋9 格除錯疊加層；新增 `nextPage`／`previousPage` 靜態 helper |
| `app/test/screens/reader_screen_test.dart` | 修改 | 新增 `_handleZoneAction`／`triggerZoneAction` 相關 widget test（Task 1）；新增熱區點擊端到端 widget test（Task 3） |
| `app/test/reader/pdf_reader_view_test.dart` | 修改 | 新增 9 格熱區 widget test（Task 2） |
| `app/integration_test/pdf_nav_zone_test.dart` | 新增 | 真機驗證：分派邏輯自動化驗證＋人工驗證清單（Task 4） |

---

### Task 1：`ReaderScreen` — `_chromeVisible` 改名擴大 + `_handleZoneAction` 分派入口

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：`ZoneAction`（epic-7 Issue 2，`app/lib/reader/zone_action.dart`）
- Produces：`void _handleZoneAction(ZoneAction action)`（私有方法）；`static void triggerZoneAction(GlobalKey<State<ReaderScreen>> key, ZoneAction action)`（供 widget test 與 Task 3 呼叫的強型別入口，比照既有 `PdfReaderView.jumpToPage` 模式）

- [ ] **Step 1：寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 頂部新增 import：

```dart
import 'package:elinkbook/reader/zone_action.dart';
```

在檔案結尾（第 1963 行 `});` 之後、第 1964 行 `}` 之前）新增 2 個測試：

```dart
  testWidgets('_handleZoneAction(menu) 切換 AppBar／頁尾顯示（PDF）', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 模擬原生端已回報頁碼，讓頁尾判斷式的 _pdfPageInfo != null 成立
    // （比照既有「PDF 開書後，收到原生端 onPageChanged 回報時，頁尾正確
    // 顯示」測試的既定手法，本檔案第 662-687 行）。
    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 0, totalPages: 12));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('reader_footer')), findsOneWidget);

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const Key('reader_footer')), findsNothing);

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
  });

  testWidgets(
      '_handleZoneAction(previousPage/nextPage) 不影響 AppBar 顯示狀態（PDF，design.md 決策 #14）',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);

    ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);

    ReaderScreen.triggerZoneAction(key, ZoneAction.previousPage);
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);

    ReaderScreen.triggerZoneAction(key, ZoneAction.none);
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets(
      'Scaffold 開啟 extendBodyBehindAppBar，PdfReaderView 尺寸不因沉浸模式切換而改變（審查修正：避免 AppBar 顯示/隱藏觸發 PlatformView resize）',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBodyBehindAppBar, isTrue);

    final sizeWithAppBar = tester.getSize(find.byType(PdfReaderView));

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();

    expect(find.byType(AppBar), findsNothing, reason: '沉浸模式已切換，AppBar 應隱藏');
    final sizeWithoutAppBar = tester.getSize(find.byType(PdfReaderView));
    expect(sizeWithoutAppBar, sizeWithAppBar,
        reason: 'PdfReaderView 尺寸不應因 AppBar 顯示/隱藏而改變');
  });
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/reader_screen_test.dart
```

Expected：FAIL（`Error: The method 'triggerZoneAction' isn't defined for the type 'ReaderScreen'`）。

- [ ] **Step 3：實作**

在 `app/lib/screens/reader_screen.dart` 頂部 import 區塊，`import '../reader/writing_mode.dart';` 之後新增：

```dart
import '../reader/zone_action.dart';
```

執行識別字重新命名（純文字替換，共 6 處出現，行為完全不變）：

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
sed -i 's/_fixedLayoutControlsVisible/_chromeVisible/g' lib/screens/reader_screen.dart
```

重新命名後的欄位宣告區塊，原本：

```dart
  // 固定版面（FXL）懸浮控制項（返回鍵／設定鍵）是否顯示，由 EpubReaderView
  // 三欄熱區的中間熱區觸發切換（見 epic-16-dual-page Issue 9）。預設顯示。
  bool _chromeVisible = true;
```

改為：

```dart
  // 介面顯示狀態（AppBar＋頁尾＋FXL 懸浮控制項）是否可見，格式無關
  // （epic-7-interaction Issue 4，原為 FXL 專屬的 _fixedLayoutControlsVisible
  // 欄位改名／擴大適用範圍）。由熱區「選單」動作切換（見
  // _handleZoneAction），EPUB FXL 既有熱區的中間格（epic-16-dual-page
  // Issue 9；epic-7 Issue 5 擴充為九宮格）與新的 PDF 熱區皆共用同一個
  // 狀態。預設顯示。
  bool _chromeVisible = true;
```

**審查修正（Critical）：** Scaffold 的 `appBar` 在 `null` 與 `AppBar(...)` 之間切換時，Scaffold 預設行為會連帶改變 `body` 實際拿到的版面高度（少掉/補回 AppBar 佔用的高度），導致 `body` 底下的 `PdfReaderView`（`AndroidView`）每次切換沉浸模式都會被強制 resize、觸發微幅重繪；這個 `_chromeVisible` 判斷式與 `body` 結構是本 issue 建立的**共用基礎設施**，EPUB 流式（Issue 6）之後會直接沿用同一段程式碼——屆時同樣的 resize 若發生在 Readium WebView 上，會觸發整本書重新分頁（repagination），造成嚴重效能問題與畫面閃爍、甚至跳動閱讀位置，必須在建立這段共用邏輯的當下（本 Task）就避免，不留給 Issue 6 才發現。

修正做法：Scaffold 開啟 `extendBodyBehindAppBar: true`，讓 `body` 的版面約束（LayoutBuilder constraints）恆定、不受 `appBar` 是否顯示影響；但 `extendBodyBehindAppBar` 開啟後，Scaffold 會把 AppBar 佔用的高度改為動態灌進 `MediaQuery.padding.top`（而不是直接砍 `body` 的版面框），若 `_buildBody()` 內的 `SafeArea` 照舊直接消費這個值，`body` 內容仍然會隨沉浸模式切換而改變可用高度，等於完全沒解決問題（已對照 Flutter SDK `scaffold.dart` 原始碼第 960-988 行的 `_BodyBuilder` 邏輯逐行確認：`top = extendBodyBehindAppBar ? max(devicePadding.top, appBarHeight) : devicePadding.top`）。因此 `_buildBody()` 的 `SafeArea` 需要同步改為 `top: false`，並改用不受 `extendBodyBehindAppBar` 影響、只反映裝置實際安全區域的 `MediaQuery.of(context).viewPadding.top`（`viewPadding` 與 Scaffold 動態調整的 `padding` 是兩個獨立欄位，前者恆為系統原始安全區域值，見 `media_query.dart` 第 151-197 行），手動包一層固定 `Padding`。

Scaffold 建構區塊，原本：

```dart
      child: Scaffold(
        appBar: _isFixedLayout
            ? null // 固定版面（如漫畫）隱藏 Scaffold AppBar，改用 Stack 懸浮半透明按鈕，避免裁切大圖
            : AppBar(
                title: _buildAppBarTitle(format),
                actions: _buildAppBarActions(format),
              ),
        body: _buildBody(format, isLandscape),
      ),
```

改為：

```dart
      child: Scaffold(
        // extendBodyBehindAppBar：搭配 _buildBody() 內的 Padding+SafeArea(top:
        // false) 改造（審查修正），讓 body 版面約束恆定，AppBar 顯示/隱藏
        // 只是視覺疊加、不觸發 body 底下 PlatformView 的 resize（PDF 目前
        // 只是微幅重繪，但這段邏輯是 Issue 5/6/7 共用基礎設施，EPUB 流式
        // 若同樣觸發 resize 會造成 Readium 整本書重新分頁，必須在此收斂）。
        extendBodyBehindAppBar: true,
        appBar: (_isFixedLayout || !_chromeVisible)
            ? null // 固定版面（如漫畫）或沉浸模式已收起介面時隱藏 Scaffold AppBar
            : AppBar(
                title: _buildAppBarTitle(format),
                actions: _buildAppBarActions(format),
              ),
        body: _buildBody(format, isLandscape),
      ),
```

`_buildBody()` 方法的 `return` 區塊，原本：

```dart
    return SafeArea(
      child: Column(
        children: [
          Expanded(child: body),
          // 頁尾佔用固定版面空間、擠壓上方閱讀區域高度（比照
          // prototype/index.html 的 .reader-footer 既有設計，非浮動疊加
          // 層）。顯示/隱藏由 showFooter 控制（epic-5-toc-pagination
          // Issue 5），false 時整個 if 條件不成立、完全不佔用版面空間。
          if (format == BookFormat.pdf &&
              _pdfPageInfo != null &&
              (_resolved?.showFooter ?? true))
            ReaderFooter(
              currentPage: _pdfPageInfo!.pageIndex + 1,
              totalPages: _pdfPageInfo!.totalPages,
              onPageChanged: (page1Indexed) {
                // 審查修正：透過強型別 static helper 呼叫，不使用 as dynamic。
                PdfReaderView.jumpToPage(_pdfReaderViewKey, page1Indexed - 1);
              },
            ),
          if (format == BookFormat.epub &&
              !_isFixedLayout &&
              _totalCharacterCount != null &&
              _resolved != null &&
              _resolved!.showFooter)
            _buildEpubFooter(_resolved!, _totalCharacterCount!),
        ],
      ),
    );
  }
```

改為：

```dart
    return Padding(
      // extendBodyBehindAppBar（見上方 Scaffold 建構）開啟後，Scaffold 會
      // 依 AppBar 是否顯示動態調整 MediaQuery.padding.top；若直接讓
      // SafeArea 消費這個值，body 內容仍會隨沉浸模式切換改變可用高度，
      // 等於沒解決 PlatformView resize 問題（審查修正）。改用不受 AppBar
      // 影響、只反映裝置實際安全區域（狀態列/瀏海）的
      // MediaQuery.viewPadding.top，SafeArea 本身關閉頂端判斷（top:
      // false），確保 body 高度真正恆定，AppBar 只是視覺上疊加在最上方。
      padding: EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: body),
            // 頁尾佔用固定版面空間、擠壓上方閱讀區域高度（比照
            // prototype/index.html 的 .reader-footer 既有設計，非浮動疊加
            // 層）。顯示/隱藏由 showFooter 控制（epic-5-toc-pagination
            // Issue 5），false 時整個 if 條件不成立、完全不佔用版面空間。
            if (format == BookFormat.pdf &&
                _pdfPageInfo != null &&
                (_resolved?.showFooter ?? true) &&
                _chromeVisible)
              ReaderFooter(
                currentPage: _pdfPageInfo!.pageIndex + 1,
                totalPages: _pdfPageInfo!.totalPages,
                onPageChanged: (page1Indexed) {
                  // 審查修正：透過強型別 static helper 呼叫，不使用 as dynamic。
                  PdfReaderView.jumpToPage(_pdfReaderViewKey, page1Indexed - 1);
                },
              ),
            if (format == BookFormat.epub &&
                !_isFixedLayout &&
                _totalCharacterCount != null &&
                _resolved != null &&
                _resolved!.showFooter &&
                _chromeVisible)
              _buildEpubFooter(_resolved!, _totalCharacterCount!),
          ],
        ),
      ),
    );
  }
```

（`_buildNativeView()`／FXL 4 個懸浮按鈕使用的是各自獨立、巢狀於 `body` 參數內部的 `Stack`＋`Positioned`，與這裡 `_buildBody()` 外層新增的 `Padding`／`SafeArea(top: false)` 屬於不同層級的容器，不會互相影響——`Positioned` 一律相對它自己最近的祖先 `Stack` 定位，本次改動完全發生在該 `Stack` 的外側。）

檔案結尾（`_buildNativeView()` 方法的 `}` 之後、`_ReaderScreenState` 類別的最後一個 `}` 之前）新增：

```dart

  /// 熱區動作統一分派入口（epic-7-interaction Issue 4）：`previousPage`/
  /// `nextPage` 呼叫目前格式對應的既有換頁方法；`menu` 切換 [_chromeVisible]
  /// （沉浸模式）；`none` 不做事。**`previousPage`/`nextPage` 刻意不影響
  /// [_chromeVisible]**（design.md 決策 #14）。目前只實作 PDF 換頁分支——
  /// EPUB FXL 分支由 Issue 5 擴充，EPUB 流式的 previousPage/nextPage 完全
  /// 不經過這裡（原生 Kotlin `InputListener` 自主處理，只有 `menu` 動作經
  /// Issue 6 的 `onZoneTapped` 回呼）。
  void _handleZoneAction(ZoneAction action) {
    switch (action) {
      case ZoneAction.previousPage:
        if (detectBookFormat(widget.filePath) == BookFormat.pdf) {
          PdfReaderView.previousPage(_pdfReaderViewKey);
        }
        break;
      case ZoneAction.nextPage:
        if (detectBookFormat(widget.filePath) == BookFormat.pdf) {
          PdfReaderView.nextPage(_pdfReaderViewKey);
        }
        break;
      case ZoneAction.menu:
        setState(() => _chromeVisible = !_chromeVisible);
        break;
      case ZoneAction.none:
        break;
    }
  }
}
```

（注意：上面程式碼區塊最後一行的 `}` 是關閉 `_ReaderScreenState` 類別本身——插入位置就是取代檔案原本結尾的那個 `}`，不要重複多加一個。）

在 `class ReaderScreen extends StatefulWidget { ... }` 內、`createState()` 方法之後新增靜態 helper（`ReaderScreen` widget 類別，不是 State 類別）：

```dart
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();

  /// 供測試／`PdfReaderView`／後續 Issue 5-7 的原生回呼安全呼叫
  /// [_ReaderScreenState._handleZoneAction] 的強型別 static helper，比照
  /// `PdfReaderView.jumpToPage` 既有模式：不使用 `as dynamic` 跨越 State
  /// 的 private 邊界。[key] 對應的 State 若尚未掛載，靜默忽略。
  static void triggerZoneAction(
    GlobalKey<State<ReaderScreen>> key,
    ZoneAction action,
  ) {
    final state = key.currentState;
    if (state is _ReaderScreenState) {
      state._handleZoneAction(action);
    }
  }
}
```

（`@override State<ReaderScreen> createState() => _ReaderScreenState();` 那一行已存在，只是把新的 static method 插入在它後面；不要重複貼上該行本身，也不要把它放進 `_ReaderScreenState` 類別內。）

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/reader_screen_test.dart
```

Expected：PASS（含新增的 3 個測試，以及全部既有 FXL 相關測試——證明純改名與 `extendBodyBehindAppBar` 改造沒有造成回歸）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-7): rename _fixedLayoutControlsVisible to _chromeVisible and add zone action dispatch"
```

---

### Task 2：`PdfReaderView` — 移除滑動翻頁，新增 9 格熱區判讀

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Test: `app/test/reader/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes：`ZoneAction`（epic-7 Issue 2）、`hitTestZoneIndex()`（epic-7 Issue 2，`app/lib/reader/zone_hit_test.dart`）
- Produces：`PdfReaderView` 新增建構參數 `List<ZoneAction> navZoneActions`（預設全 9 格 `ZoneAction.none`）、`ValueChanged<ZoneAction>? onZoneAction`（預設 `null`）、`bool showNavZoneDebugOverlay`（預設 `false`）；`static void nextPage(GlobalKey<State<PdfReaderView>> key)`／`static void previousPage(...)`——供 Task 1 的 `_handleZoneAction` 呼叫

- [ ] **Step 1：寫失敗測試**

在 `app/test/reader/pdf_reader_view_test.dart` 頂部新增 import：

```dart
import 'package:elinkbook/reader/zone_action.dart';
```

在檔案結尾（第 1218 行 `});` 之後、第 1219 行 `}` 之前）新增 3 個測試：

```dart
  testWidgets('9 個 Key(nav_zone_\$index) 皆存在，點擊觸發對應 onZoneAction', (tester) async {
    final capturedActions = <ZoneAction>[];
    final calls = await _pumpPdfReaderView(
      tester,
      PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        navZoneActions: const [
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
        ],
        onZoneAction: capturedActions.add,
      ),
    );
    calls.clear();

    for (var index = 0; index < 9; index++) {
      expect(find.byKey(Key('nav_zone_$index')), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('nav_zone_0')));
    await tester.pump();
    expect(capturedActions, [ZoneAction.previousPage]);

    await tester.tap(find.byKey(const Key('nav_zone_4')));
    await tester.pump();
    expect(capturedActions, [ZoneAction.previousPage, ZoneAction.menu]);
  });

  testWidgets('showNavZoneDebugOverlay=true 時，格子顯示對應動作文字標籤', (tester) async {
    await _pumpPdfReaderView(
      tester,
      PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        navZoneActions: const [
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
        ],
        showNavZoneDebugOverlay: true,
      ),
    );

    expect(find.text('上一頁'), findsWidgets);
    expect(find.text('選單'), findsWidgets);
    expect(find.text('下一頁'), findsWidgets);
  });

  testWidgets('build() 不再註冊 onHorizontalDragEnd（ADR 0010，滑動翻頁已移除）',
      (tester) async {
    await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final detector = tester.widget<GestureDetector>(find.byType(GestureDetector));
    expect(detector.onHorizontalDragEnd, isNull);
    expect(detector.onTapUp, isNotNull);
    expect(detector.onLongPressStart, isNotNull);
  });
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/pdf_reader_view_test.dart
```

Expected：FAIL（`Error: No named parameter with the name 'navZoneActions'`）。

- [ ] **Step 3：實作**

在 `app/lib/reader/pdf_reader_view.dart` 頂部 import 區塊尾端（`import 'dual_page_mode.dart';` 之後）新增：

```dart
import 'zone_action.dart';
import 'zone_hit_test.dart';
```

欄位宣告區塊，原本結尾：

```dart
  /// 框選狀態被原生端取消時觸發（縮放/平移手勢開始、或觸發翻頁/跳頁，
  /// 見 plan-issue-3.md Global Constraints）。呼叫端負責收起浮動工具列。
  final VoidCallback? onSelectionCanceled;

  const PdfReaderView({
```

改為：

```dart
  /// 框選狀態被原生端取消時觸發（縮放/平移手勢開始、或觸發翻頁/跳頁，
  /// 見 plan-issue-3.md Global Constraints）。呼叫端負責收起浮動工具列。
  final VoidCallback? onSelectionCanceled;

  /// 3×3 導航熱區的動作對照表（epic-7-interaction Issue 2/4），長度固定
  /// 9，索引慣例見 `zone_hit_test.dart`（0-indexed、列優先）。點擊時查表
  /// 決定觸發哪個 [ZoneAction]。預設全部 [ZoneAction.none]（非 `required`
  /// ——比照 [dualPageMode] 等既有欄位的預設值慣例，避免既有大量測試呼叫
  /// 端需要逐一補上這個參數）。
  final List<ZoneAction> navZoneActions;

  /// 點擊熱區換算出動作後觸發，呼叫端（`ReaderScreen`）負責分派實際行為
  /// （換頁／切換沉浸模式，見 `ReaderScreen._handleZoneAction`）。比照
  /// [onCropRectComputed] 等既有回呼欄位，刻意為可選參數。
  final ValueChanged<ZoneAction>? onZoneAction;

  /// 是否疊加顯示熱區輔助線（邊框＋動作文字標籤），供使用者於設定畫面
  /// 開啟除錯用途（epic-7-interaction Issue 2/3 `showNavZoneDebugOverlay`）。
  final bool showNavZoneDebugOverlay;

  const PdfReaderView({
```

建構子具名參數區塊，原本結尾：

```dart
    this.onSelectionRectComputed,
    this.onSelectionCanceled,
  });
```

改為：

```dart
    this.onSelectionRectComputed,
    this.onSelectionCanceled,
    this.navZoneActions = const [
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ],
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
  });
```

`jumpToPage` static helper（原本第 100-105 行）之後、`refreshAnnotations` 之前，新增 2 個 static helper：

```dart
  /// 供 `ReaderScreen._handleZoneAction` 呼叫下一頁，比照 [jumpToPage] 的
  /// 強型別 static helper 寫法（epic-7-interaction Issue 4）。
  static void nextPage(GlobalKey<State<PdfReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state.nextPage();
    }
  }

  /// 供 `ReaderScreen._handleZoneAction` 呼叫上一頁，比照 [jumpToPage] 的
  /// 強型別 static helper 寫法（epic-7-interaction Issue 4）。
  static void previousPage(GlobalKey<State<PdfReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state.previousPage();
    }
  }
```

`build()` 方法，原本：

```dart
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handleAnnotationPointerDown,
      onPointerUp: _handleAnnotationPointerUp,
      onPointerCancel: _handleAnnotationPointerUp,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _lastMeasuredSize = constraints.biggest;
          return GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;
              if (details.primaryVelocity! < 0) {
                // 向左滑動 → 下一頁
                nextPage();
              } else if (details.primaryVelocity! > 0) {
                // 向右滑動 → 上一頁
                previousPage();
              }
            },
            onLongPressStart: _handleLongPressStart,
            onLongPressMoveUpdate: _handleLongPressMoveUpdate,
            onLongPressEnd: _handleLongPressEnd,
            child: AndroidView(
              viewType: 'cc.ugotit.elinkbook/pdf_reader_view',
              onPlatformViewCreated: _onPlatformViewCreated,
            ),
          );
        },
      ),
    );
  }
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handleAnnotationPointerDown,
      onPointerUp: _handleAnnotationPointerUp,
      onPointerCancel: _handleAnnotationPointerUp,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _lastMeasuredSize = constraints.biggest;
          return GestureDetector(
            onTapUp: _handleZoneTap,
            onLongPressStart: _handleLongPressStart,
            onLongPressMoveUpdate: _handleLongPressMoveUpdate,
            onLongPressEnd: _handleLongPressEnd,
            child: Stack(
              children: [
                AndroidView(
                  viewType: 'cc.ugotit.elinkbook/pdf_reader_view',
                  onPlatformViewCreated: _onPlatformViewCreated,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: _buildNavZoneOverlay(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 3×3 導航熱區疊加層——純視覺標記／除錯輔助線，永遠不攔截觸控（外層
  /// 包了 [IgnorePointer]），實際點擊判讀由 [_handleZoneTap] 透過
  /// [hitTestZoneIndex] 對座標運算完成，兩者共用同一份 3×3 格線定義。
  /// `showNavZoneDebugOverlay == false` 時格子仍存在（供 widget test 以
  /// `Key('nav_zone_$index')` 尋址並透過 `tester.tap()` 觸發底層
  /// [GestureDetector] 的 `onTapUp`），只是不顯示邊框與文字標籤。
  Widget _buildNavZoneOverlay() {
    return GridView.count(
      crossAxisCount: 3,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(9, (index) {
        return Container(
          key: Key('nav_zone_$index'),
          decoration: widget.showNavZoneDebugOverlay
              ? BoxDecoration(border: Border.all(color: Colors.white24))
              : null,
          alignment: Alignment.center,
          child: widget.showNavZoneDebugOverlay
              ? Text(
                  _zoneActionLabel(widget.navZoneActions[index]),
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                )
              : null,
        );
      }),
    );
  }

  String _zoneActionLabel(ZoneAction action) {
    switch (action) {
      case ZoneAction.previousPage:
        return '上一頁';
      case ZoneAction.nextPage:
        return '下一頁';
      case ZoneAction.menu:
        return '選單';
      case ZoneAction.none:
        return '無動作';
    }
  }

  void _handleZoneTap(TapUpDetails details) {
    final size = _lastMeasuredSize;
    if (size == null) return;
    final index = hitTestZoneIndex(
      dx: details.localPosition.dx,
      dy: details.localPosition.dy,
      width: size.width,
      height: size.height,
    );
    widget.onZoneAction?.call(widget.navZoneActions[index]);
  }
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/pdf_reader_view_test.dart
```

Expected：PASS（含新增的 3 個測試，以及全部既有測試——證明新增的可選參數與疊加層沒有破壞既有裁切/劃線/openBook 相關測試）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_test.dart
git commit -m "feat(epic-7): add PDF nav zone hit testing, remove horizontal drag page turn"
```

---

### Task 3：`ReaderScreen` 串接 `PdfReaderView` 熱區參數

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`（`_buildNativeView()` 內 `PdfReaderView(...)` 建構）
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：`PdfReaderView.navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay`（Task 2）、`ResolvedPreferences.navZoneActions`/`showNavZoneDebugOverlay`（epic-7 Issue 2）、`_handleZoneAction`（Task 1）
- Produces：無新增對外介面，純串接既有元件

- [ ] **Step 1：寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 檔案結尾（Task 1 新增的 2 個測試之後、最終 `}` 之前）新增 1 個端到端測試：

```dart
  testWidgets('PDF：真實點擊熱區「選單」格（index 1）觸發沉浸模式切換', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);

    // navZoneMode 預設 rightFlip，index 1（中欄）為 menu
    // （見 app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
  });
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/reader_screen_test.dart
```

Expected：FAIL（點擊 `nav_zone_1` 後 AppBar 仍存在——因為 `_buildNativeView()` 尚未把 `navZoneActions`/`onZoneAction` 接上，`PdfReaderView` 用的是預設全 `none` 陣列，點擊不會觸發任何動作）。

- [ ] **Step 3：實作**

修改 `app/lib/screens/reader_screen.dart` 的 `_buildNativeView()` 方法，原本 `PdfReaderView(...)` 建構結尾：

```dart
          onSelectionRectComputed: _handlePdfSelectionRectComputed,
          onSelectionCanceled: _handlePdfSelectionCanceled,
        );
```

改為：

```dart
          onSelectionRectComputed: _handlePdfSelectionRectComputed,
          onSelectionCanceled: _handlePdfSelectionCanceled,
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
        );
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/reader_screen_test.dart
```

Expected：PASS（含新增的端到端測試，以及 Task 1 的 2 個測試）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-7): wire PdfReaderView nav zone params in ReaderScreen"
```

---

### Task 4：真機驗證——`integration_test`

**Files:**
- Create: `app/integration_test/pdf_nav_zone_test.dart`

**Interfaces:**
- Consumes：`ReaderScreen.triggerZoneAction`（Task 1）、`PdfReaderView`（Task 2/3）
- Produces：無（驗證性質工單）

**⚠️ 已知限制**：`integration_test` 對原生 `AndroidView` 的觸控手勢模擬不可靠（見 Global Constraints、`pdf_highlights_notes_test.dart` 既有先例）。本 Task 的自動化部分只驗證「`ReaderScreen.triggerZoneAction` 分派邏輯在真機原生渲染下確實生效」（不模擬手指觸控座標）；「手指實際點擊 9 宮格哪一格對應到哪個動作」與「與長按拖曳劃線交叉操作不誤觸發」兩項改為人工驗證清單。

- [ ] **Step 1：建立測試檔（自動化部分 + 人工驗證清單）**

建立 `app/integration_test/pdf_nav_zone_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/screens/reader_screen.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 2));
}

/// Epic 7 Issue 4：PDF 熱區導覽 + 沉浸模式——真機整合測試。
///
/// 【真機人工驗證清單，本測試無法自動涵蓋】
/// 比照 epic-6-annotations Issue 2/3 integration_test 既有先例：Flutter
/// integration_test 對原生 View 的觸控事件模擬並不可靠，本專案既有慣例是
/// 原生手勢功能一律另外以真實裝置人工驗證，不嘗試以 tester.tap 模擬手指
/// 點在特定螢幕座標上。以下項目須另外以真實裝置人工驗證：
///   1. 依序點擊畫面上 9 個實體區域（左上/上/右上/左/中/右/左下/下/右下），
///      逐一確認對應到 navZoneActions 陣列中正確的格子（例如預設
///      rightFlip 模板：左欄＝上一頁、中欄＝選單、右欄＝下一頁）。
///   2. 開啟「顯示熱區輔助線」後，畫面上應能看到 9 格邊框與動作文字標籤，
///      且標籤文字與實際點擊行為一致。
///   3. 熱區點擊（單擊）與既有長按拖曳劃線框選手勢實際共存不衝突：短促
///      點擊觸發熱區動作、按住不放並拖曳觸發劃線框選，兩者不互相誤觸發
///      （ADR 0008 已標記的未收斂風險，本 issue 須收斂）。
///   4. 旋轉裝置後，9 格熱區的點擊位置隨畫面重新排版正確對應（不會維持
///      舊的座標網格）。
/// 本檔案自動化的部分改為驗證「分派邏輯」：透過 `ReaderScreen.
/// triggerZoneAction` 直接觸發，確認在真機原生渲染下（`PdfReaderView`
/// 已收到 `initialPreferences`、`_channel` 非 null）翻頁與沉浸模式切換
/// 真的生效——這條路徑不涉及座標模擬，純粹驗證 Dart 分派邏輯 → 原生
/// method channel → 真機渲染結果，是 integration_test 可靠涵蓋的範圍。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('triggerZoneAction(menu) 真機切換沉浸模式（AppBar／頁尾顯示/隱藏）',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'pdf_nav_zone_menu.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_nav_zone_menu',
      title: '熱區沉浸模式測試書',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: samplePath,
          bookId: 'b_nav_zone_menu',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('triggerZoneAction(nextPage/previousPage) 真機正確換頁，且不影響沉浸模式',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'pdf_nav_zone_pageturn.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_nav_zone_pageturn',
      title: '熱區換頁測試書',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: samplePath,
          bookId: 'b_nav_zone_pageturn',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
    expect(find.textContaining('第 1/'), findsOneWidget, reason: '初始應在第 1 頁');

    ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('第 2/'), findsOneWidget, reason: '呼叫 nextPage 後應換到第 2 頁');
    expect(find.byType(AppBar), findsOneWidget, reason: '換頁不應影響沉浸模式（design.md 決策 #14）');

    ReaderScreen.triggerZoneAction(key, ZoneAction.previousPage);
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('第 1/'), findsOneWidget, reason: '呼叫 previousPage 後應換回第 1 頁');
    expect(find.byType(AppBar), findsOneWidget);
  });
}
```

- [ ] **Step 2：確認裝置已連線**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter devices
```

Expected：列出至少 1 台已連線的 Android 真機/模擬器，記下其 `<device-id>`。

- [ ] **Step 3：於真機執行測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test integration_test/pdf_nav_zone_test.dart -d <device-id>
```

（若執行環境確認僅連接一台裝置，`-d <device-id>` 參數可省略。）

Expected：2 個測試皆 PASS。

- [ ] **Step 4：人工驗證清單**

依照測試檔案開頭註解列出的 4 項，在真機上以 App 實際操作逐一確認（點擊 9 宮格各格對應正確動作、除錯輔助線顯示正確、熱區點擊與長按拖曳劃線不誤觸發、旋轉裝置後熱區位置正確對應）。將驗證結果（含任何發現的落差）記錄於本工單完成後的 `docs/epics/epic-7-interaction/issues.md` Issue 4 狀態更新中。

- [ ] **Step 5：Commit**

```bash
git add app/integration_test/pdf_nav_zone_test.dart
git commit -m "test(epic-7): add PDF nav zone integration test"
```

---

### Task 5：全域驗證與收尾

**Files:** 無異動（本 Task 僅執行驗證指令，不修改任何檔案）

**Interfaces:**
- Consumes：Task 1-4 全部產出
- Produces：驗收證據（`flutter analyze`/`flutter test` 輸出），供人類判斷本 issue 是否可合併

- [ ] **Step 1：`flutter analyze` 全專案靜態分析**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 2：`flutter test` 執行全專案測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test
```

Expected：全數 PASS，含本 issue 新增/擴充的 `reader_screen_test.dart`／`pdf_reader_view_test.dart`，無既有測試因 `_chromeVisible` 改名或 `PdfReaderView` 新增參數而回歸失敗。

- [ ] **Step 3：確認 `git status` 乾淨（無未提交變更）**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：無輸出（Task 1-4 皆已個別 commit）。

（本 Task 不修改任何檔案，無需 commit。）

---

## Self-Review 摘要

- **Spec coverage**：`issues.md` Issue 4 描述的兩個模組異動（`ReaderScreen` 沉浸模式與分派機制、`PdfReaderView` 熱區判讀＋滑動翻頁移除）逐一對應 Task 1-3；`integration_test`（真實裝置）驗收標準對應 Task 4；`flutter analyze`／全數測試通過對應 Task 5。`_handleZoneAction` 目前只實作 PDF 分支，EPUB FXL／流式分支明確標註留給 Issue 5／Issue 6，不是遺漏。
- **Placeholder scan**：所有 Task 的程式碼區塊皆為完整可執行內容，無 TBD/待補；`_handleZoneAction` 對 EPUB 格式的「不做事」不是佔位符，是本 issue 刻意的範圍界定（詳見 Global Constraints）。
- **Type consistency**：`ZoneAction`／`hitTestZoneIndex()`／`navZoneActions`／`onZoneAction`／`showNavZoneDebugOverlay` 命名與型別簽章在 Task 1-3 間保持一致，與 epic-7 Issue 2 既有定義逐字相符；`PdfReaderView.nextPage`/`previousPage` 靜態 helper 命名與既有 `jumpToPage` 模式一致。
