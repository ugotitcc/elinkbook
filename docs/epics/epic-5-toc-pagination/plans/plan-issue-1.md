# Epic 5 Issue 1：PDF 頁碼顯示 + 跳頁 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐 Task 執行本計劃。每個 Step 用 checkbox（`- [ ]`）追蹤，完成後即時勾選為 `[x]`（見 CLAUDE.md SDD 生命週期第 6 步）。

**Goal:** 在 PDF 閱讀畫面新增頁尾（進度百分比 + 目前頁碼／總頁數）與跳頁互動元件（輸入框 + 滑桿雙向同步），並建立可被 Issue 3（EPUB）直接複用的格式無關頁尾元件。

**Architecture:** 原生端（`PdfReaderView.kt`）擴充既有的 `onPageChanged` 回報，從單純的頁碼索引改為同時攜帶總頁數，並新增 `jumpToPage` method channel case；Dart 端新增 `PdfPageInfo` 值物件承接這個回報，`PdfReaderView`（Dart）的私有 State 新增 `jumpToPage(int)` 實例方法（比照既有 `nextPage()`/`previousPage()` 命名慣例），並在 `PdfReaderView` 這個公開 Widget 類別上新增**強型別的 `static jumpToPage(GlobalKey<State<PdfReaderView>>, int)` helper**（審查修正：production code 不使用 `as dynamic` 跨越 private State 邊界呼叫——本專案目前完全沒有在 `--obfuscate` release 建置下驗證過 `as dynamic` 動態呼叫私有類別方法的行為，且 `dynamic` 呼叫搭配 tree-shaking／混淆是 Flutter 社群已知的潛在崩潰風險類別；`as dynamic` 僅保留在既有整合測試技巧中，測試碼不會被編進 release APK，風險不適用），供 `ReaderScreen` 透過強型別 static helper 呼叫；新建格式無關的 `ReaderFooter` widget（只接收 `currentPage`／`totalPages`／`onPageChanged` 三個屬性，不含任何 PDF 專屬邏輯，供 Issue 3 直接複用於 EPUB）；`ReaderScreen._buildBody()` 從純 `Stack` 改為 `Column`（`Expanded` 包住既有 Stack，頁尾另外佔一列並擠壓閱讀區域高度，比照 `prototype/index.html` 的 `.reader-footer` 既有版面配置慣例，而非浮動疊加）。

**Tech Stack:** Flutter（Dart）、Kotlin、`integration_test`（真機）。

## Global Constraints

- 所有程式碼註解與說明使用正體中文（CLAUDE.md）。
- 本 issue **只處理 PDF**。EPUB 讀取畫面本 issue 完全不動，頁尾元件本身雖為格式無關可複用設計，但本 issue 只在 `ReaderScreen` 接線給 PDF；`_isFixedLayout == true`（EPUB 固定版面/漫畫）分支完全不受影響。
- 頁尾此階段**一律顯示**，不提供顯示/隱藏開關——開關留給 Issue 5（`BookReaderPrefs.showFooter`），本 issue 不得提前引入該欄位或任何開關 UI。
- **頁碼顯示慣例**：`PdfReaderView.kt` 內部與既有 method channel 契約全程維持 0-indexed（`currentPageIndex`，比照專案既有慣例）；`ReaderFooter` widget 對外（顯示文字、輸入框、滑桿）一律使用 **1-indexed**（自然的人類頁碼直覺，「第 1 頁」而非「第 0 頁」），0↔1 轉換的職責在 `ReaderScreen`（呼叫 `ReaderFooter` 與呼叫原生 `jumpToPage` 的兩個邊界上），`ReaderFooter` 元件本身不知道底層是 0-indexed。
- **跳頁與雙頁模式的已知限制（本 issue 不處理，記錄於此供未來參考）**：`jumpToPage(pageIndex)` 直接把 `currentPageIndex` 設為目標值，交給既有的 `renderCurrentSpread()` 依目前 `dualPageDirection` 重新配對——若雙頁模式生效中，跳頁後的新 anchor 可能與書籍原本的 spread 邊界不同步（例如跳到原本應是某個 spread 右頁的 index，會被當成新 anchor 重新配對）。這不是本 issue 要解決的問題（spec.md／issues.md 皆未列入范圍），如實記錄為已知限制，不在本 issue 內另尋 spread 對齊演算法。
- 每個 Task 完成後皆需確認既有 `app/test/reader/pdf_reader_view_test.dart`（現有 20 個測試）、`app/test/screens/reader_screen_test.dart` 維持全數通過，確保既有 PDF 濾鏡/裁切/雙頁功能零回歸。

---

### Task 1：原生端（Kotlin）—— `onPageChanged` 攜帶總頁數 + 新增 `jumpToPage`

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`

**Interfaces:**
- Produces：PDF method channel（`cc.ugotit.elinkbook/pdf_reader_view_$id`）的 `"onPageChanged"` 事件，wire 格式從單純 `Int` 改為 `Map<String, Int>`（`{"pageIndex": Int, "totalPages": Int}`）；新增 `"jumpToPage"` method channel case，接收 `Int` 參數。

- [x] **Step 1：新增共用的 `onPageChanged` 發送 helper**

找到 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt` 的 `nextPage()`／`previousPage()`（約第 792-812 行）：

```kotlin
    private fun nextPage() {
        if (cropEditModeActive) return
        val step = nextPageStep(currentPageIndex, dualPageEnabled, dualPageCoverAlone)
        val newIndex = currentPageIndex + step
        if (newIndex < totalPages) {
            currentPageIndex = newIndex
            renderCurrentSpread()
            channel.invokeMethod("onPageChanged", currentPageIndex)
        }
    }

    private fun previousPage() {
        if (cropEditModeActive) return
        val step = previousPageStep(currentPageIndex, dualPageEnabled, dualPageCoverAlone)
        val newIndex = currentPageIndex - step
        if (newIndex >= 0) {
            currentPageIndex = newIndex
            renderCurrentSpread()
            channel.invokeMethod("onPageChanged", currentPageIndex)
        }
    }
```

改為（新增 `notifyPageChanged()` helper 並替換三處呼叫點——`nextPage()`／`previousPage()` 各一處，`jumpToPage()` 一處於 Step 3 新增）：

```kotlin
    private fun nextPage() {
        if (cropEditModeActive) return
        val step = nextPageStep(currentPageIndex, dualPageEnabled, dualPageCoverAlone)
        val newIndex = currentPageIndex + step
        if (newIndex < totalPages) {
            currentPageIndex = newIndex
            renderCurrentSpread()
            notifyPageChanged()
        }
    }

    private fun previousPage() {
        if (cropEditModeActive) return
        val step = previousPageStep(currentPageIndex, dualPageEnabled, dualPageCoverAlone)
        val newIndex = currentPageIndex - step
        if (newIndex >= 0) {
            currentPageIndex = newIndex
            renderCurrentSpread()
            notifyPageChanged()
        }
    }

    /**
     * 統一的 onPageChanged 回報 helper（Epic 5 Issue 1 新增）：把目前頁碼與
     * 總頁數一併送給 Dart 端，供 ReaderFooter 顯示「第 N/M 頁」。原本只送
     * 單純 Int 頁碼，Dart 端無法得知總頁數，Issue 1 之前從未被 ReaderScreen
     * 實際消費過（僅有的呼叫端 PdfReaderView.dart 定義了回呼但整條鏈路沒人
     * 接線），故變更 wire 格式不影響任何既有生效功能。
     */
    private fun notifyPageChanged() {
        channel.invokeMethod(
            "onPageChanged",
            mapOf("pageIndex" to currentPageIndex, "totalPages" to totalPages),
        )
    }
```

- [x] **Step 2：開書完成後立即送出一次初始頁碼狀態**

找到 `openBook()`（約第 417-450 行）內的：

```kotlin
            renderer = PdfRenderer(pfd)
            totalPages = renderer!!.pageCount
            currentPageIndex = 0
            renderCurrentSpread()
            channel.invokeMethod("onPageRendered", null)
```

改為：

```kotlin
            renderer = PdfRenderer(pfd)
            totalPages = renderer!!.pageCount
            currentPageIndex = 0
            renderCurrentSpread()
            channel.invokeMethod("onPageRendered", null)
            // Epic 5 Issue 1：開書完成當下立即回報一次初始頁碼狀態，讓
            // Dart 端（ReaderFooter）不需要等到第一次翻頁才知道總頁數。
            notifyPageChanged()
```

- [x] **Step 3：新增 `jumpToPage` 私有方法與 method channel case**

在 `previousPage()` 之後（Step 1 修改完的位置）新增：

```kotlin
    /**
     * 跳轉至指定頁碼（Epic 5 Issue 1，FR-23）。目標超出 `0 until totalPages`
     * 範圍時靜默忽略（Dart 端 ReaderFooter 已先做過範圍箝制，這裡是原生端
     * 的最後一道防線，比照既有 nextPage()/previousPage() 邊界檢查風格）。
     * 裁切編輯模式中忽略跳頁請求，比照既有 nextPage()/previousPage() 的
     * cropEditModeActive 守衛。已知限制：雙頁模式生效中跳頁不做 spread
     * 邊界對齊，見 plan-issue-1.md Global Constraints。
     */
    private fun jumpToPage(pageIndex: Int) {
        if (cropEditModeActive) return
        if (pageIndex !in 0 until totalPages) return
        if (pageIndex == currentPageIndex) return
        currentPageIndex = pageIndex
        renderCurrentSpread()
        notifyPageChanged()
    }
```

找到 `onMethodCall()` 的 `when (call.method)`（約第 284-317 行）：

```kotlin
            "previousPage" -> {
                previousPage()
                result.success(null)
            }
            "enterCropEditMode" -> {
```

改為：

```kotlin
            "previousPage" -> {
                previousPage()
                result.success(null)
            }
            "jumpToPage" -> {
                (call.arguments as? Int)?.let { jumpToPage(it) }
                result.success(null)
            }
            "enterCropEditMode" -> {
```

- [x] **Step 4：編譯確認**

```bash
cd app/android
./gradlew :app:compileDebugKotlin
```

Expected: `BUILD SUCCESSFUL`。

- [x] **Step 5：既有回歸測試**

```bash
cd ../../app
flutter analyze
```

Expected: `No issues found!`（本 Task 只異動 Kotlin，Dart 端尚未跟進解析新 wire 格式，`flutter analyze` 此時不會發現問題；真正的整合驗證留給 Task 2 完成後）。

- [x] **Step 6：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt
git commit -m "feat(epic-5): PdfReaderView.kt onPageChanged 攜帶總頁數 + 新增 jumpToPage method channel"
```

---

### Task 2：Dart `PdfReaderView` —— `PdfPageInfo` 值物件、`onPageChanged` 簽章變更、`jumpToPage()`

**Files:**
- Create: `app/lib/reader/pdf_page_info.dart`
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/test/reader/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `"onPageChanged"` 新 wire 格式（`{"pageIndex": int, "totalPages": int}`）、新增的 `"jumpToPage"` method channel。
- Produces：`PdfPageInfo` 值物件（`pageIndex`／`totalPages`，皆 0-indexed／實際總數）；`PdfReaderView.onPageChanged` 簽章由 `ValueChanged<int>?` 改為 `ValueChanged<PdfPageInfo>?`；`_PdfReaderViewState` 新增實例方法 `jumpToPage(int pageIndex)`（0-indexed，比照既有 `nextPage()`/`previousPage()` 命名慣例）；`PdfReaderView`（公開 Widget 類別）新增**強型別 static helper** `static void jumpToPage(GlobalKey<State<PdfReaderView>> key, int pageIndex)`（審查修正，供 Task 4 的 `ReaderScreen` 安全呼叫，不使用 `as dynamic`）。

- [ ] **Step 1：新建 `PdfPageInfo` 值物件**

建立 `app/lib/reader/pdf_page_info.dart`（比照既有 `EpubLayoutInfo`——`app/lib/reader/writing_mode.dart`——的既有樣式，純記憶體內回呼用值物件，不需要 JSON 序列化）：

```dart
/// [PdfReaderView] 頁碼變動時（開書完成、翻頁、跳頁）一次性回報的頁碼資訊，
/// 皆為 0-indexed（比照專案既有慣例）。
class PdfPageInfo {
  final int pageIndex;
  final int totalPages;

  const PdfPageInfo({
    required this.pageIndex,
    required this.totalPages,
  });

  @override
  bool operator ==(Object other) =>
      other is PdfPageInfo &&
      other.pageIndex == pageIndex &&
      other.totalPages == totalPages;

  @override
  int get hashCode => Object.hash(pageIndex, totalPages);

  @override
  String toString() => 'PdfPageInfo(pageIndex: $pageIndex, totalPages: $totalPages)';
}
```

- [ ] **Step 2：`PdfReaderView` 建構參數簽章變更**

在 `app/lib/reader/pdf_reader_view.dart` 新增 import：

```dart
import 'pdf_page_info.dart';
```

找到欄位宣告：

```dart
  final ValueChanged<int>? onPageChanged;
```

改為：

```dart
  final ValueChanged<PdfPageInfo>? onPageChanged;
```

- [ ] **Step 3：`_handleMethodCall` 解析新 wire 格式**

找到 `_handleMethodCall()` 內：

```dart
      case 'onPageChanged':
        final pageIndex = call.arguments as int;
        widget.onPageChanged?.call(pageIndex);
        break;
```

改為：

```dart
      case 'onPageChanged':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onPageChanged?.call(PdfPageInfo(
          pageIndex: args['pageIndex'] as int,
          totalPages: args['totalPages'] as int,
        ));
        break;
```

- [ ] **Step 4：新增 `jumpToPage()` 實例方法 + 強型別 static helper（審查修正）**

找到既有的：

```dart
  /// 導航至下一頁
  void nextPage() => _channel?.invokeMethod('nextPage');

  /// 導航至上一頁
  void previousPage() => _channel?.invokeMethod('previousPage');
```

改為：

```dart
  /// 導航至下一頁
  void nextPage() => _channel?.invokeMethod('nextPage');

  /// 導航至上一頁
  void previousPage() => _channel?.invokeMethod('previousPage');

  /// 跳轉至指定頁碼（0-indexed，Epic 5 Issue 1，FR-23）。呼叫端（見
  /// ReaderScreen）負責把 ReaderFooter 的 1-indexed 使用者輸入轉換為
  /// 0-indexed 後才呼叫本方法。外部呼叫請一律透過 [PdfReaderView.jumpToPage]
  /// 這個強型別 static helper，不要用 `as dynamic` 直接呼叫本實例方法
  /// （審查修正，見 Global Constraints）。
  void jumpToPage(int pageIndex) => _channel?.invokeMethod('jumpToPage', pageIndex);
```

找到 `class PdfReaderView extends StatefulWidget` 的建構子與 `createState()`：

```dart
  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();
}
```

改為（在 `createState()` 之後新增 static helper，此為公開 Widget 類別，同檔案內可存取 private 的 `_PdfReaderViewState`）：

```dart
  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();

  /// 供外部（`ReaderScreen`）安全呼叫 [_PdfReaderViewState.jumpToPage] 的
  /// 強型別 static helper（審查修正，`/superpowers:requesting-code-review`）：
  /// 不使用 `as dynamic` 跨越 State 的 private 邊界——本專案目前完全沒有
  /// 在 `--obfuscate` release 建置下驗證過 `dynamic` 呼叫私有類別方法的
  /// 行為，`dynamic` 呼叫搭配 tree-shaking／混淆是 Flutter 社群已知的潛在
  /// 崩潰風險類別（method 只被 dynamic 呼叫連結時，可能被視為未使用而被
  /// tree-shaking 移除，或在混淆重新命名後找不到對應符號）。[key] 對應的
  /// State 若尚未掛載或型別不符（例如原生 View 尚未建立），靜默忽略，比照
  /// `nextPage()`/`previousPage()` 既有的 fire-and-forget 慣例。
  static void jumpToPage(GlobalKey<State<PdfReaderView>> key, int pageIndex) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state.jumpToPage(pageIndex);
    }
  }
}
```

- [ ] **Step 5：撰寫 widget test**

在 `app/test/reader/pdf_reader_view_test.dart` 新增 import：

```dart
import 'package:elinkbook/reader/pdf_page_info.dart';
```

在既有測試最後一個 `testWidgets` 之後、`}`（`main()` 結尾）之前新增：

```dart
  testWidgets('開書完成後，收到原生端 onPageChanged 事件時正確解析 PdfPageInfo',
      (tester) async {
    PdfPageInfo? received;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        onPageChanged: (info) => received = info,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onPageChanged', {
      'pageIndex': 3,
      'totalPages': 20,
    }));
    await binaryMessenger.handlePlatformMessage(
        instanceChannel!.name, data, (_) {});

    expect(received, const PdfPageInfo(pageIndex: 3, totalPages: 20));
  });

  testWidgets(
      'PdfReaderView.jumpToPage()（強型別 static helper）呼叫原生端 jumpToPage method channel',
      (tester) async {
    // 審查修正：測試改為驅動真正的公開 API（static helper + GlobalKey），
    // 而非只測 private State 的 `as dynamic` 呼叫——production code
    // （ReaderScreen）實際上會呼叫的是這個 static helper，測試應驗證這條
    // 真正會被使用的路徑。
    final key = GlobalKey<State<PdfReaderView>>();
    final calls = await _pumpPdfReaderView(
      tester,
      PdfReaderView(
        key: key,
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );
    calls.clear();

    PdfReaderView.jumpToPage(key, 7);
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'jumpToPage');
    expect(calls.single.arguments, 7);
  });
```

- [ ] **Step 6：執行測試**

```bash
cd app
flutter test test/reader/pdf_reader_view_test.dart
flutter analyze
```

Expected: 22 個測試（既有 20 個 + 新增 2 個）全數通過；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 7：Commit**

```bash
git add app/lib/reader/pdf_page_info.dart app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_test.dart
git commit -m "feat(epic-5): PdfReaderView(Dart) 新增 PdfPageInfo、onPageChanged 攜帶總頁數、jumpToPage()"
```

---

### Task 3：新建 `ReaderFooter` widget（格式無關，可被 Issue 3 複用）

**Files:**
- Create: `app/lib/screens/reader_footer.dart`
- Create: `app/test/screens/reader_footer_test.dart`

**Interfaces:**
- Consumes：無（純展示元件，不依賴任何格式特定型別）。
- Produces：`ReaderFooter` widget，建構參數 `currentPage`（int，**1-indexed**）、`totalPages`（int）、`onPageChanged`（`ValueChanged<int>`，回呼值同樣 **1-indexed**）——依審查修正的介面契約，不接收任何 PDF/EPUB 專屬的 controller 或底層讀取器物件。新增 `Key`：`reader_footer`（根節點）、`reader_footer_progress_text`（進度/頁碼文字）、`reader_footer_jump_input`（輸入框）、`reader_footer_jump_slider`（滑桿）。

- [ ] **Step 1：撰寫 widget 實作**

建立 `app/lib/screens/reader_footer.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 閱讀畫面頁尾（Epic 5 Issue 1，FR-22/23/40）：顯示閱讀進度百分比與
/// 「目前頁碼／總頁數」，並提供跳頁互動（輸入框 + 滑桿雙向同步）。
///
/// 格式無關——只接收 [currentPage]／[totalPages]／[onPageChanged] 三個
/// 與格式無關的屬性（`/superpowers:requesting-code-review` 審查修正的
/// 介面契約），不含任何 PDF 或 EPUB 專屬邏輯，供 Issue 3 直接複用於
/// EPUB（EPUB 端的估算頁碼與精確度差異由呼叫端負責，本元件不需知道）。
///
/// [currentPage]／[totalPages] 皆為 **1-indexed**（自然的人類頁碼直覺），
/// 呼叫端負責與底層 0-indexed 的原生頁碼互相轉換（見 ReaderScreen）。
///
/// 版面配置比照 `prototype/index.html` 的 `.reader-footer` 既有設計：佔用
/// 固定版面空間的實體列（由呼叫端以 Column 排版擠壓閱讀區域高度），非
/// 浮動疊加層——本 widget 本身不處理佈局位置，只負責自身內容。
class ReaderFooter extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const ReaderFooter({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  State<ReaderFooter> createState() => _ReaderFooterState();
}

class _ReaderFooterState extends State<ReaderFooter> {
  late TextEditingController _inputController;
  late double _sliderValue;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController(text: '${widget.currentPage}');
    _sliderValue = widget.currentPage.toDouble();
  }

  @override
  void didUpdateWidget(covariant ReaderFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（原生端翻頁回報）造成 currentPage 變動時，同步輸入框與滑桿；
    // 避免使用者正在輸入時被外部狀態打斷，只在數字真的不同時才更新。
    if (widget.currentPage != oldWidget.currentPage) {
      _inputController.text = '${widget.currentPage}';
      _sliderValue = widget.currentPage.toDouble();
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  /// 把使用者輸入/拖曳的值箝制在合法範圍 [1, totalPages] 內。
  int _clamp(int page) => page.clamp(1, widget.totalPages);

  void _handleSliderChangeEnd(double value) {
    final clamped = _clamp(value.round());
    setState(() {
      _sliderValue = clamped.toDouble();
      _inputController.text = '$clamped';
    });
    widget.onPageChanged(clamped);
  }

  void _handleInputSubmitted(String value) {
    final parsed = int.tryParse(value);
    final clamped = _clamp(parsed ?? widget.currentPage);
    setState(() {
      _inputController.text = '$clamped';
      _sliderValue = clamped.toDouble();
    });
    widget.onPageChanged(clamped);
    // 審查修正：跳頁完成後主動收起鍵盤與輸入框焦點，避免鍵盤持續佔用畫面
    // 遮擋閱讀內容。
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final progressPercent =
        widget.totalPages > 0 ? (widget.currentPage / widget.totalPages * 100).round() : 0;
    return Container(
      key: const Key('reader_footer'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            key: const Key('reader_footer_progress_text'),
            '進度 $progressPercent% ｜ 第 ${widget.currentPage}/${widget.totalPages} 頁',
          ),
          Row(
            children: [
              SizedBox(
                width: 56,
                child: TextField(
                  key: const Key('reader_footer_jump_input'),
                  controller: _inputController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  onSubmitted: _handleInputSubmitted,
                ),
              ),
              Expanded(
                child: Slider(
                  key: const Key('reader_footer_jump_slider'),
                  value: _sliderValue.clamp(1, widget.totalPages.toDouble()),
                  min: 1,
                  max: widget.totalPages > 1 ? widget.totalPages.toDouble() : 2,
                  divisions: widget.totalPages > 1 ? widget.totalPages - 1 : 1,
                  // 審查修正：總頁數只有 1 頁時，拖曳滑桿沒有實際意義（無處
                  // 可跳），停用（onChanged/onChangeEnd 皆傳 null）讓 Slider
                  // 視覺上呈現不可互動狀態，比只靠 max/divisions 防呆更直覺。
                  onChanged: widget.totalPages > 1
                      ? (v) => setState(() {
                            _sliderValue = v;
                            _inputController.text = '${v.round()}';
                          })
                      : null,
                  onChangeEnd: widget.totalPages > 1 ? _handleSliderChangeEnd : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2：撰寫 widget test**

建立 `app/test/screens/reader_footer_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_footer.dart';

void main() {
  testWidgets('顯示進度百分比與目前頁碼／總頁數文字', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderFooter(
        currentPage: 5,
        totalPages: 20,
        onPageChanged: (_) {},
      ),
    ));

    expect(find.text('進度 25% ｜ 第 5/20 頁'), findsOneWidget);
  });

  testWidgets('輸入框輸入合法頁碼並送出後，觸發 onPageChanged', (tester) async {
    int? received;
    await tester.pumpWidget(MaterialApp(
      home: ReaderFooter(
        currentPage: 5,
        totalPages: 20,
        onPageChanged: (page) => received = page,
      ),
    ));

    await tester.enterText(find.byKey(const Key('reader_footer_jump_input')), '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(received, 12);
  });

  testWidgets('輸入框送出跳頁後，主動收起鍵盤/輸入框焦點（審查修正）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderFooter(
        currentPage: 5,
        totalPages: 20,
        onPageChanged: (_) {},
      ),
    ));

    await tester.tap(find.byKey(const Key('reader_footer_jump_input')));
    await tester.pump();
    expect(
      Focus.of(tester.element(find.byKey(const Key('reader_footer_jump_input'))))
          .hasFocus,
      isTrue,
      reason: '點擊輸入框後應先取得焦點，作為稍後驗證「送出後失去焦點」的基準',
    );

    await tester.enterText(find.byKey(const Key('reader_footer_jump_input')), '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(
      Focus.of(tester.element(find.byKey(const Key('reader_footer_jump_input'))))
          .hasFocus,
      isFalse,
      reason: '送出跳頁後應主動收起焦點/鍵盤',
    );
  });

  testWidgets('輸入框輸入超出範圍的頁碼時，箝制在合法範圍內', (tester) async {
    int? received;
    await tester.pumpWidget(MaterialApp(
      home: ReaderFooter(
        currentPage: 5,
        totalPages: 20,
        onPageChanged: (page) => received = page,
      ),
    ));

    await tester.enterText(find.byKey(const Key('reader_footer_jump_input')), '999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(received, 20, reason: '超出總頁數應箝制為總頁數');
    expect(find.text('20'), findsOneWidget, reason: '輸入框顯示值應同步箝制');
  });

  testWidgets('拖曳滑桿結束時觸發 onPageChanged，且輸入框數字即時同步', (tester) async {
    int? received;
    await tester.pumpWidget(MaterialApp(
      home: ReaderFooter(
        currentPage: 5,
        totalPages: 20,
        onPageChanged: (page) => received = page,
      ),
    ));

    final sliderFinder = find.byKey(const Key('reader_footer_jump_slider'));
    await tester.drag(sliderFinder, const Offset(50, 0));
    await tester.pump();

    // 拖曳過程中（尚未放開）已觸發 onChanged，輸入框應即時反映新數字，
    // 但 onPageChanged（跳頁動作）要等到放開（onChangeEnd）才觸發。
    expect(received, isNull,
        reason: '拖曳中不應觸發跳頁動作，只有放開時才觸發');

    await tester.pumpAndSettle();
    expect(received, isNotNull, reason: '拖曳結束後應觸發 onPageChanged');
  });

  testWidgets('外部 currentPage 變動時（例如原生端翻頁回報），輸入框與滑桿同步更新',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderFooter(
        currentPage: 5,
        totalPages: 20,
        onPageChanged: (_) {},
      ),
    ));
    expect(find.text('5'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: ReaderFooter(
        currentPage: 8, // 變動
        totalPages: 20,
        onPageChanged: (_) {},
      ),
    ));
    await tester.pump();

    expect(find.text('8'), findsOneWidget);
    expect(find.text('進度 40% ｜ 第 8/20 頁'), findsOneWidget);
  });

  testWidgets('總頁數只有 1 頁時，滑桿停用（onChanged 為 null）', (tester) async {
    // 審查修正：totalPages <= 1 時拖曳跳頁沒有實際意義，Slider 應停用
    // （視覺上呈現不可互動狀態），而不只是靠 max/divisions 防呆撐住。
    await tester.pumpWidget(MaterialApp(
      home: ReaderFooter(
        currentPage: 1,
        totalPages: 1,
        onPageChanged: (_) {},
      ),
    ));

    final slider =
        tester.widget<Slider>(find.byKey(const Key('reader_footer_jump_slider')));
    expect(slider.onChanged, isNull);
    expect(slider.onChangeEnd, isNull);
  });
}
```

- [ ] **Step 3：執行測試**

```bash
cd app
flutter test test/screens/reader_footer_test.dart
flutter analyze
```

Expected: 7 個測試全數通過；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 4：Commit**

```bash
git add app/lib/screens/reader_footer.dart app/test/screens/reader_footer_test.dart
git commit -m "feat(epic-5): 新建格式無關的 ReaderFooter widget（頁碼顯示 + 輸入框/滑桿雙向同步跳頁）"
```

---

### Task 4：`ReaderScreen` 整合（Column 佈局改造 + PDF 頁尾接線）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `PdfReaderView.onPageChanged`（`ValueChanged<PdfPageInfo>?`）／`jumpToPage(int)`；Task 3 的 `ReaderFooter`。
- Produces：無新增對外介面，純粹是 `ReaderScreen` 內部狀態與版面串接。

- [ ] **Step 1：新增 `_pdfPageInfo` 狀態與 `GlobalKey`**

在 `app/lib/screens/reader_screen.dart` 新增 import：

```dart
import '../reader/pdf_page_info.dart';
import 'reader_footer.dart';
```

在 `class _ReaderScreenState` 找到：

```dart
  BookReaderPrefs _prefs = BookReaderPrefs.empty;
```

之前新增：

```dart
  // PDF 目前頁碼/總頁數狀態，由 PdfReaderView.onPageChanged 回報驅動頁尾
  // 顯示（Epic 5 Issue 1）。EPUB 讀取畫面本 issue 不使用此欄位。
  PdfPageInfo? _pdfPageInfo;
  // 用於呼叫 PdfReaderView.jumpToPage(key, pageIndex) 這個強型別 static
  // helper（審查修正，見 Task 2 Step 4——不使用 as dynamic 跨 State 私有
  // 邊界呼叫，避免 release 混淆／tree-shaking 風險）。
  final _pdfReaderViewKey = GlobalKey<State<PdfReaderView>>();
```

- [ ] **Step 2：`_buildNativeView()` 的 PDF 分支接上 `key` 與 `onPageChanged`**

找到 `_buildNativeView()` 內 `case BookFormat.pdf:` 的 `PdfReaderView(...)` 建構呼叫：

```dart
      case BookFormat.pdf:
        return PdfReaderView(
          filePath: widget.filePath,
```

改為：

```dart
      case BookFormat.pdf:
        return PdfReaderView(
          key: _pdfReaderViewKey,
          filePath: widget.filePath,
```

在同一個 `PdfReaderView(...)` 呼叫的既有參數列末（`isLandscape: isLandscape,` 之後）新增：

```dart
          onPageChanged: (info) {
            if (!mounted) return;
            setState(() => _pdfPageInfo = info);
          },
```

- [ ] **Step 3：`_buildBody()` 改為 `Column`，新增 PDF 頁尾**

找到 `_buildBody()` 現行結尾：

```dart
    return SafeArea(
      child: body,
    );
  }
```

以及緊接在其之前、`body` 變數宣告開頭的 `final body = Stack(`。改為（`Stack` 本身內容不變，只是外層多包一層 `Column`）：

```dart
    return SafeArea(
      child: Column(
        children: [
          Expanded(child: body),
          // 頁尾佔用固定版面空間、擠壓上方閱讀區域高度（比照
          // prototype/index.html 的 .reader-footer 既有設計，非浮動疊加
          // 層）。本 issue 只接 PDF；EPUB 留給 Issue 3。此階段頁尾一律
          // 顯示，顯示/隱藏開關留給 Issue 5（BookReaderPrefs.showFooter
          // 尚未存在）。
          if (format == BookFormat.pdf && _pdfPageInfo != null)
            ReaderFooter(
              currentPage: _pdfPageInfo!.pageIndex + 1,
              totalPages: _pdfPageInfo!.totalPages,
              onPageChanged: (page1Indexed) {
                // 審查修正：透過強型別 static helper 呼叫，不使用 as dynamic。
                PdfReaderView.jumpToPage(_pdfReaderViewKey, page1Indexed - 1);
              },
            ),
        ],
      ),
    );
  }
```

- [ ] **Step 4：撰寫 widget test**

在 `app/test/screens/reader_screen_test.dart` 新增（放在既有 PDF 相關測試之後）：

```dart
  testWidgets('PDF 開書後，畫面出現頁尾，正確顯示頁碼並可透過輸入框跳頁',
      (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample_footer.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late MethodChannel instanceChannel;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
          instanceChannel,
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_footer_test',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 模擬原生端開書完成後送出 onPageChanged（比照既有測試對
    // onLayoutResolved／onCropRectComputed 的模擬手法）。
    final codec = instanceChannel.codec;
    final data = codec.encodeMethodCall(const MethodCall('onPageChanged', {
      'pageIndex': 0,
      'totalPages': 12,
    }));
    await binaryMessenger.handlePlatformMessage(instanceChannel.name, data, (_) {});
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
    expect(find.text('進度 8% ｜ 第 1/12 頁'), findsOneWidget);
    instanceCalls.clear();

    await tester.enterText(
        find.byKey(const Key('reader_footer_jump_input')), '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // 輸入框送出「第 5 頁」（1-indexed），ReaderScreen 須轉換為 0-indexed
    // 後才呼叫原生端 jumpToPage，驗證 0↔1 轉換邊界正確落在 ReaderScreen。
    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'jumpToPage');
    expect(instanceCalls.single.arguments, 4);
  });
```

- [ ] **Step 5：執行測試**

```bash
cd app
flutter test test/screens/reader_screen_test.dart
flutter test test/screens/reader_footer_test.dart
flutter test test/reader/pdf_reader_view_test.dart
flutter analyze
```

Expected: 全數通過；`flutter analyze` 顯示 `No issues found!`；既有 EPUB 相關測試（固定版面、流式）零回歸——特別留意 `Stack` 改 `Column` 後，EPUB 分支（`format != BookFormat.pdf`）的既有版面（AppBar、載入指示器、固定版面懸浮按鈕）視覺結構不變，只是外層多包一層 `Column`／`Expanded`，不影響既有測試斷言。

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-5): ReaderScreen 接上 PDF 頁尾（Column 佈局改造 + GlobalKey 串接 jumpToPage）"
```

---

### Task 5：真機整合測試 + 回歸 + 文件收尾

**Files:**
- Create: `app/integration_test/reader_footer_test.dart`
- Modify: `docs/epics/epic-5-toc-pagination/issues.md`
- Modify: `docs/epics.md`

**Interfaces:** 無（本 Task 為驗收與文件收尾）。

- [ ] **Step 1：撰寫真機整合測試**

建立 `app/integration_test/reader_footer_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/screens/reader_screen.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PDF 開書後頁尾顯示正確頁碼，透過輸入框跳頁後畫面確實顯示目標頁',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
    );
    addTearDown(() => libraryRepository.close());

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_dual_page.pdf', 'reader_footer_integration.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_footer_integration',
          prefsManager: prefsManager,
        ),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
    expect(find.text('進度 17% ｜ 第 1/6 頁'), findsOneWidget,
        reason: 'sample_dual_page.pdf 共 6 頁');

    await tester.enterText(
        find.byKey(const Key('reader_footer_jump_input')), '4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('進度 67% ｜ 第 4/6 頁'), findsOneWidget,
        reason: '輸入框跳頁後頁尾應更新為目標頁');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
```

- [ ] **Step 2：執行整合測試**

```bash
cd app
flutter test integration_test/reader_footer_test.dart -d <device-id>
```

Expected: 1 個測試通過。

- [ ] **Step 3：執行全專案回歸**

```bash
flutter analyze
flutter test
flutter test integration_test/pdf_reader_view_test.dart -d <device-id>
flutter test integration_test/reader_screen_test.dart -d <device-id>
flutter test integration_test/pdf_dual_page_test.dart -d <device-id>
```

Expected: 全數通過，無回歸——特別留意既有 PDF 濾鏡/裁切/雙頁相關 `integration_test` 完全不應受 `Column` 佈局改造影響。

- [ ] **Step 4：更新 `issues.md` Issue 1 狀態**

在 `docs/epics/epic-5-toc-pagination/issues.md` Issue 1 的 `**依賴：**` 之前加入 `**Status:** ✅ 已完成`（取代 `ready-for-agent`），並附簡短完成摘要（Task 1-5 完成情形、測試通過數量）。

- [ ] **Step 5：更新 `docs/epics.md`**

在 `docs/epics.md` 的 `epic-5-toc-pagination` 列備註新增一句，記錄 Issue 1 已完成並合併回 `main`。

- [ ] **Step 6：Commit**

```bash
git add app/integration_test/reader_footer_test.dart \
        docs/epics/epic-5-toc-pagination/issues.md \
        docs/epics.md
git commit -m "test(epic-5): Issue 1 真機整合測試 + issues.md/docs/epics.md 收尾更新"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 1 的驗收標準逐項對應——頁尾顯示（Task 3/4）、跳頁輸入框（Task 3）、跳頁滑桿（Task 3）、雙向同步（Task 3）、可被 Issue 3 複用的介面契約（Task 3 的 `currentPage`／`totalPages`／`onPageChanged` 三參數設計）、既有測試無回歸（每個 Task 的執行測試 Step）、真機整合測試（Task 5）。

**占位符掃描**：全文無 TBD/待補字樣，每個 Step 皆含可直接使用的完整程式碼。Task 4 Step 4 的括號說明是驗收步驟本質使然（真機驗證留給 Task 5），非遺漏程式碼。

**型別一致性**：`PdfPageInfo(pageIndex, totalPages)` 在 Task 2 定義後，Task 4（`_pdfPageInfo!.pageIndex`／`_pdfPageInfo!.totalPages`）引用一致；`ReaderFooter(currentPage, totalPages, onPageChanged)` 在 Task 3 定義後，Task 4 呼叫端逐字相符（含 0↔1 轉換：`pageIndex + 1` 傳入、`page1Indexed - 1` 傳給 `jumpToPage`）；`jumpToPage(int)` 在 Task 1（Kotlin）／Task 2（Dart `_PdfReaderViewState` 實例方法）／Task 4（呼叫端）三處簽章一致（皆 0-indexed）；`PdfReaderView.jumpToPage(GlobalKey<State<PdfReaderView>>, int)` 這個 static helper（審查修正新增）在 Task 2 Step 4 定義、Step 5 測試、Task 4 Step 1（`GlobalKey` 宣告）／Step 3（呼叫）四處型別與呼叫方式一致。

## 審查修正紀錄（`tmp/epic-5/reviews/plan-issue-1-review.md`）

- **Critical（確認屬實，已修正）**：Task 4 原始設計用 `(_pdfReaderViewKey.currentState as dynamic)?.jumpToPage(...)` 跨越 `PdfReaderView` 私有 State 邊界呼叫，在 release 混淆／tree-shaking 建置下有已知的崩潰風險類別（本專案目前完全沒有在 `--obfuscate` 建置下驗證過此模式，且 production code 之前也沒有 `as dynamic` 的既有先例，純粹是把測試技巧誤搬進 production code）。已改為在 `PdfReaderView` 公開類別上新增強型別 `static jumpToPage(GlobalKey<State<PdfReaderView>>, int)` helper（Task 2 Step 4），`ReaderScreen`／測試皆改為呼叫這個型別安全的公開 API，`as dynamic` 只保留在既有整合測試對 `nextPage()`/`previousPage()` 的既有用法（測試碼不編進 release APK，風險不適用，本次未變動）。
- **Important（確認屬實，已修正）**：`ReaderFooter` 輸入框送出跳頁後鍵盤/焦點未收起，會持續遮擋畫面。已於 `_handleInputSubmitted` 補上 `FocusScope.of(context).unfocus()`，並新增對應測試驗證送出後失去焦點。
- **Minor（確認屬實，已修正）**：`totalPages == 1` 時 Slider 的 `divisions`/`max` 防呆值雖不會崩潰，但拖曳沒有實際意義。已改為 `totalPages <= 1` 時 `onChanged`/`onChangeEnd` 皆傳 `null`，讓 Slider 視覺呈現不可互動狀態，並新增對應測試。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-5-toc-pagination/plans/plan-issue-1.md`。兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
