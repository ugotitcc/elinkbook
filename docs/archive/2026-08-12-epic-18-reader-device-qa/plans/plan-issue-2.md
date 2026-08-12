# Epic 18 Issue 2 — 閱讀畫面上下工具列瘦身（AppBar 高度 + 頁尾合併單行） Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把閱讀畫面的 `AppBar` 高度從預設 `kToolbarHeight`（56dp）縮減至 `20dp`（現有高度約 1/3，`design.md` 決策 #2），並把 `ReaderFooter` 從「進度文字＋跳頁互動」兩列合併為單一 Row，兩者皆須同步收斂內部子元件尺寸避免溢出，讓上下工具列總共佔用的垂直空間明顯縮短。

**Architecture:** `ReaderFooter.build()` 目前是 `Container > Column(mainAxisSize.min) > [進度文字 Text, Row(跳頁輸入框+滑桿)]` 兩個子項；改為 `Container > Column(mainAxisSize.min) > [Row(進度文字+跳頁輸入框+滑桿)]`——**只有一個子項**（合併後的 Row），外層 `Column(mainAxisSize.min)` 刻意保留（原因見下方 Global Constraints「Slider 高度陷阱」，這是實測發現的必要防護，非殘留寫法）。進度文字格式從「進度 YY% ｜ 第 XXX/OOO 頁」簡化為「XXX/OOO」，原本的 `YY%` 資訊改由 `Slider` 的 `label` 參數（拖曳時顯示）呈現。`reader_screen.dart` 的 `AppBar` 新增 `toolbarHeight: 20`，並同步把 `_buildAppBarActions()` 的三個 `IconButton`（`reader_toc_button`／`reader_layout_settings_button`／`reader_notes_button`）透過 `style: IconButton.styleFrom(...)` 收斂 `minimumSize`/`tapTargetSize`/`padding`/圖示大小（見下方 Global Constraints「IconButton 尺寸收斂機制」，Material 3 的 `IconButton` 不能只靠建構子的 `padding`/`constraints` 參數縮小，這兩者在此 Flutter 版本下對實際渲染尺寸無效，已實測確認），`_buildAppBarTitle()` 的兩種標題文字收斂字級。

**Tech Stack:** Flutter/Dart（`app/lib/screens/reader_footer.dart`／`app/lib/screens/reader_screen.dart`），`flutter_test`（widget test，本 Issue 全數變更皆可用 `flutter test` 驗證），驗收另需真機人工確認既有功能可正常點擊操作（見 Task 3）。

## Global Constraints

- **所有指令皆在 `app/` 目錄下執行**（`cd "U:/MyDeveloper/AI/elinkBook/app"`），使用 POSIX 相容 Bash（Git Bash），非 PowerShell。
- **`flutter analyze` 必須保持乾淨**（"No issues found!"）——每個 Task 完成程式碼異動後都要跑一次。
- **`ReaderFooter` 的公開建構參數不變**：`currentPage`／`totalPages`／`onPageChanged` 三者的型別與語意完全不動（`app/lib/screens/reader_footer.dart:18-28`），`reader_screen.dart` 三處既有 `ReaderFooter(...)` 建構呼叫（`_buildEpubFooter()`／`_buildFoliateEpubFooter()`／`_buildBody()` 內的 PDF 分支）**不需要修改**——本 Issue 只動 `ReaderFooter` 內部版面，不動它對外的介面契約。
- **Slider 高度陷阱（撰寫本計劃時已實測確認，務必依此设计，不可自行簡化）**：`ReaderFooter.build()` 目前用 `Container > Column(mainAxisSize.min) > [...]` 包住內容，而不是讓 `Container` 直接回傳一個 `Row`。實測發現：若拿掉這層 `Column(mainAxisSize.min)`、讓 `Row` 直接當作 `Container` 的 `child`，一旦 `ReaderFooter` 被放在「會給予有限（bounded）但寬鬆高度上限」的容器下（例如 `app/test/screens/reader_footer_test.dart` 既有的 `Scaffold(body: ReaderFooter(...))` pump 慣例——`Scaffold.body` 直接給其子項一個有限的 `maxHeight`），`Row` 內 `Expanded(child: Slider(...))` 的 `Slider` 會直接撐滿到那個有限的高度上限（`Slider` 在「有界但寬鬆」約束下會直接填滿，而非退回自然高度，這是 Flutter 已知行為），導致頁尾意外變成佔滿整個測試視窗（實測數字：`Scaffold(body: Row(...))` 量到 `600.0`）。包一層 `Column(mainAxisSize.min)` 能讓 `Row` 收到「無界（unbounded）」高度上限（`Flex`／`Column` 對「非 flexible 子項」在主軸方向一律給無界 `maxHeight` 的既有行為），此時 `Slider` 才會退回自然高度（~48px）。這個機制在真實 `ReaderScreen`（`ReaderFooter` 是外層 `Column(children: [Expanded(body), ReaderFooter])` 的非 flex 子項，外層 Column 本身就已經給無界高度）與既有測試的裸 `Scaffold.body` pump 慣例下，**都必須維持正確**——故 Task 1 的實作**保留** `Column(mainAxisSize.min)` 包一層，只把裡面的兩個子項（原本的 `Text` + `Row`）合併成一個子項（合併後的單一 `Row`）。
- **既有高度快照（撰寫本計劃時已實測記錄，Task 1 的回歸測試依此設定門檻）**：在 `app/test/screens/reader_footer_test.dart` 既有的 `Scaffold(body: ReaderFooter(currentPage: 5, totalPages: 20, onPageChanged: (_) {}))` pump 方式、預設 `MaterialApp` 主題、800×600 測試視窗下——**合併前**（現行程式碼）`tester.getSize(find.byKey(Key('reader_footer'))).height` 為 `84.0`；**合併後**（本計劃 Task 1 實作完成後，同一份 pump 方式）為 `64.0`。Task 1 的高度回歸測試以 `lessThan(84.0)` 為門檻（不用寫死比較 `64.0` 本身，避免字型細微差異造成不必要的脆弱測試，但門檻本身必須嚴格小於合併前的 `84.0`，確保是有意義的紅燈測試）。
- **既有字串斷言需同步更新的完整清單**（已用 `grep -rn "進度.*第.*頁" app/test/` 重新確認，共 9 處，非僅 `reader_footer_test.dart`）：
  - `app/test/screens/reader_footer_test.dart:17`（`currentPage: 5, totalPages: 20` → 新字串 `'5/20'`）
  - `app/test/screens/reader_footer_test.dart:138`（`currentPage: 8, totalPages: 20` → 新字串 `'8/20'`）
  - `app/test/screens/reader_screen_test.dart:963`（`currentPage: 1, totalPages: 12` → 新字串 `'1/12'`）
  - `app/test/screens/reader_screen_test.dart:1068`（`currentPage: 1, totalPages: 10` → 新字串 `'1/10'`）
  - `app/test/screens/reader_screen_test.dart:1098`（`currentPage: 5, totalPages: 10` → 新字串 `'5/10'`）
  - `app/test/screens/reader_screen_test.dart:1151`（`currentPage: 1, totalPages: 10` → 新字串 `'1/10'`）
  - `app/test/screens/reader_screen_test.dart:1179`（`currentPage: 1, totalPages: 40` → 新字串 `'1/40'`）
  - `app/test/screens/reader_screen_test.dart:1201`（`currentPage: 1, totalPages: 12` → 新字串 `'1/12'`）
  - `app/test/screens/reader_screen_test.dart:2764`（`currentPage: 10, totalPages: 100` → 新字串 `'10/100'`）
- **進度百分比的新落點**：原本獨立一行的「進度 YY%」文字，改由 `Slider` 的 `label` 參數（`'$progressPercent%'`）呈現（issues.md Issue 2「具體取捨留待實作階段決定」的實作決定），只在使用者拖曳滑桿時顯示，不再是永久可見的文字列——這是本計劃對 issues.md 開放式描述做出的具體落地決定，不是額外可選功能。
- **AppBar 收斂數值（issues.md Issue 2 審查修正指定的起始建議值，非最終規格，Task 3 真機確認後可再調整，但本計劃須先落地成具體數字，不得留空）**：`toolbarHeight: 20.0`、`IconButton` 觸控寬度 `32.0`、圖示 `size: 18.0`、標題文字 `fontSize: 13.0`。
- **IconButton 尺寸收斂機制（撰寫本計劃時已實測確認，務必依此設計，不可改回單純的建構子參數）**：本專案 Flutter 版本（`3.41.9`，Material 3 預設）的 `IconButton` **不會**因為建構子的 `padding`/`constraints` 參數而改變實際渲染尺寸——實測（於 `AppBar(actions: [...])` 情境下）`IconButton(padding: EdgeInsets.zero, constraints: BoxConstraints(minWidth: 32, minHeight: 32))` 渲染出來的實際 `Rect` 仍是 Material 3 預設的 `48×20`（寬度完全不受 `constraints` 影響，高度則被下一點「AppBar 高度上限」鎖死在 `20`，與 `constraints` 給的數值無關）；必須改用 `style: IconButton.styleFrom(minimumSize: Size(32, toolbarHeight 常數), tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: EdgeInsets.zero)` 才能讓寬度真正收斂為 `32`（已實測確認：套用 `style` 後渲染 `Rect` 為 `32×20`）。Task 2 Step 5 的程式碼依此撰寫，**不使用**建構子的 `padding`/`constraints` 參數。
- **AppBar 會把動作按鈕的高度無條件鎖死在 `toolbarHeight`（撰寫本計劃時已實測確認，審查報告對此有誤判，見下方說明）**：實測發現，`AppBar.actions` 內的 `IconButton`，無論其 `minimumSize`/`constraints` 的高度要求是 `20`／`24`／`32`／`48`，實際渲染高度**恆等於** `toolbarHeight`（本 Issue 為 `20`）——`AppBar` 對其 `actions` Row 的高度是有界（bounded）約束，任何子項的高度需求都會被強制夾在這個上限內，不會如某些 Flutter 版本/情境下的「無裁切、允許溢出」，也不存在按鈕視覺上突出 AppBar 邊界、進而侵入狀態列的風險——**這與 `tmp/epic-18/reviews/review-plan-issue-2.md` Minor 建議「IconButton 可能超出 AppBar 邊界各 6dp、需確認是否與狀態列重疊」的技術前提不符，已用 widget test 實測推翻**（`minHeight` 分別設為 `20`／`24`／`32`／`48` 四種數值，渲染高度皆為 `20`，無一例外），故本計劃**不採用**該建議的「必要時降為 `minHeight: 24`」備援方案——那個備援方案本身無意義（`24` 與 `32` 效果相同，皆會被夾到 `20`），Task 3 不需要為此另闢驗證/備援步驟。
- **不處理 `SafeArea`／狀態列額外調整**：`reader_screen.dart` 現有的 `extendBodyBehindAppBar: true` + `_buildBody()` 內 `Padding(padding: EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top))` 機制已經讓 body 內容不受 AppBar 顯示/隱藏影響（見 `reader_screen.dart:1192-1204` 既有註解），且 Flutter `AppBar`（`primary: true` 預設值）本身就會在 `toolbarHeight` 之外自動疊加狀態列高度，不需要本 Issue 額外處理——`toolbarHeight: 20` 只影響 AppBar 內容區本身的高度，不影響狀態列。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/lib/screens/reader_footer.dart` | 修改（`build()`，現行第 87-138 行；類別頂端文件註解，現行第 4-17 行） | 合併為單一 `Row`（保留外層 `Column(mainAxisSize.min)`），進度文字格式改為「頁碼/總頁數」，`Slider` 新增 `label` |
| `app/test/screens/reader_footer_test.dart` | 修改（更新 2 處既有字串斷言 + 新增高度回歸測試 + 新增 `Slider.label` 測試） | 鎖定合併後的行為與新格式 |
| `app/test/screens/reader_screen_test.dart` | 修改（更新 7 處既有字串斷言；新增 AppBar `toolbarHeight`／`IconButton` 收斂測試） | 確認頁尾格式變更不影響既有頁尾顯示邏輯；鎖定 AppBar 瘦身後的具體數值 |
| `app/lib/screens/reader_screen.dart` | 修改（`build()` 內 `AppBar(...)` 建構，現行第 1207-1210 行；`_buildAppBarTitle()`，現行第 1224-1239 行；`_buildAppBarActions()`，現行第 1241-1313 行；新增 4 個 `static const`） | AppBar `toolbarHeight` 瘦身 + `IconButton`/標題文字尺寸收斂 |

---

### Task 1：`ReaderFooter` 合併為單一 Row

**Files:**
- Modify: `app/lib/screens/reader_footer.dart:4-17`（類別頂端文件註解）、`:87-138`（`build()`）
- Test: `app/test/screens/reader_footer_test.dart`（更新第 17、138 行既有斷言；新增 2 個測試）
- Test: `app/test/screens/reader_screen_test.dart`（更新第 963、1068、1098、1151、1179、1201、2764 行既有斷言）

**Interfaces:**
- Consumes：`ReaderFooter` 既有公開建構參數 `currentPage`／`totalPages`／`onPageChanged`（不變）
- Produces：`Key('reader_footer_progress_text')` 顯示格式改為 `'$currentPage/$totalPages'`（例如 `'5/20'`）；`Key('reader_footer_jump_input')`／`Key('reader_footer_jump_slider')` 兩個既有 Key 的元件型別與互動行為不變；`Slider.label` 新增為 `'$progressPercent%'`

- [x] **Step 1：撰寫失敗測試——更新 `reader_footer_test.dart` 既有斷言 + 新增 2 個測試**

把 `app/test/screens/reader_footer_test.dart` 第 17 行：

```dart
    expect(find.text('進度 25% ｜ 第 5/20 頁'), findsOneWidget);
```

改為：

```dart
    expect(find.text('5/20'), findsOneWidget);
```

把第 138 行：

```dart
    expect(find.text('進度 40% ｜ 第 8/20 頁'), findsOneWidget);
```

改為：

```dart
    expect(find.text('8/20'), findsOneWidget);
```

在檔案最後一個 `testWidgets` 區塊（`'總頁數只有 1 頁時，滑桿停用（onChanged 為 null）'`，結尾在第 158 行 `});`）之後、`main()` 的收尾 `}`（第 159 行）之前，新增以下兩個測試：

```dart
  testWidgets('合併為單行後，頁尾高度明顯低於合併前的既有高度快照（84.0）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderFooter(
          currentPage: 5,
          totalPages: 20,
          onPageChanged: (_) {},
        ),
      ),
    ));

    final height = tester.getSize(find.byKey(const Key('reader_footer'))).height;
    // 合併前（Column 內「進度文字」+「跳頁 Row」兩個子項）在同一份預設
    // MaterialApp 主題、同一個 800x600 測試視窗下，既有高度快照為 84.0
    // （撰寫本計劃時已實測記錄，見 plan-issue-2.md Global Constraints）；
    // 合併為單一 Row 後應明顯縮短。
    expect(height, lessThan(84.0));
  });

  testWidgets('滑桿 label 帶入正確的進度百分比字串', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderFooter(
          currentPage: 5,
          totalPages: 20,
          onPageChanged: (_) {},
        ),
      ),
    ));

    final slider =
        tester.widget<Slider>(find.byKey(const Key('reader_footer_jump_slider')));
    expect(slider.label, '25%');
  });
```

同時把 `app/test/screens/reader_screen_test.dart` 下列 7 處既有斷言依序改為新格式（皆為單一行替換，前後文其餘程式碼不動）：

第 963 行，`'進度 8% ｜ 第 1/12 頁'` 改為 `'1/12'`：

```dart
    expect(find.text('1/12'), findsOneWidget);
```

第 1068 行，`'進度 10% ｜ 第 1/10 頁'` 改為 `'1/10'`：

```dart
    expect(find.text('1/10'), findsOneWidget);
```

第 1098 行，`'進度 50% ｜ 第 5/10 頁'` 改為 `'5/10'`：

```dart
    expect(find.text('5/10'), findsOneWidget);
```

第 1151 行，`'進度 10% ｜ 第 1/10 頁'` 改為 `'1/10'`：

```dart
    expect(find.text('1/10'), findsOneWidget);
```

第 1179 行，`'進度 3% ｜ 第 1/40 頁'` 改為 `'1/40'`：

```dart
    expect(find.text('1/40'), findsOneWidget);
```

第 1201 行，`'進度 8% ｜ 第 1/12 頁'` 改為 `'1/12'`：

```dart
    expect(find.text('1/12'), findsOneWidget);
```

第 2764 行，`'進度 10% ｜ 第 10/100 頁'` 改為 `'10/100'`：

```dart
    expect(find.text('10/100'), findsOneWidget);
```

- [x] **Step 2：執行測試，確認全部失敗（既有格式尚未變更）**

```bash
flutter test test/screens/reader_footer_test.dart test/screens/reader_screen_test.dart
```

Expected：Step 1 修改/新增的所有斷言 FAIL——目前 `reader_footer.dart` 仍輸出舊格式「進度 YY% ｜ 第 XXX/OOO 頁」，`find.text('5/20')` 等新格式字串與高度回歸測試（現行 `84.0` 不小於 `84.0`）皆找不到/不成立；`Slider.label` 目前為 `null`（現行程式碼未設定），不等於 `'25%'`。未修改的既有測試維持 PASS。

- [x] **Step 3：修改 `reader_footer.dart` 的類別頂端文件註解**

把第 4-17 行：

```dart
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
```

改為：

```dart
/// 閱讀畫面頁尾（Epic 5 Issue 1，FR-22/23/40；Epic 18 Issue 2 瘦身為單一
/// 列）：單一 Row 內同時顯示「目前頁碼／總頁數」文字、跳頁輸入框，與可
/// 拖曳的進度滑桿（拖曳時的 label 顯示進度百分比），提供跳頁互動（輸入框
/// + 滑桿雙向同步）。
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
/// 浮動疊加層——本 widget 本身不處理佈局位置，只負責自身內容。內部仍以
/// `Column(mainAxisSize: MainAxisSize.min)` 包住單一 `Row`（而非直接把
/// `Row` 當作 `build()` 回傳值）：實測發現若拿掉這層 `Column`，一旦本
/// widget 被直接放在會給予「有限（bounded）但寬鬆」高度上限的容器下
/// （例如既有測試的 `Scaffold(body: ReaderFooter(...))` pump 慣例），內部
/// `Expanded(child: Slider)` 的 `Slider` 會直接撐滿到那個高度上限（`Slider`
/// 在有界但寬鬆的約束下會填滿，不會退回自然高度，是 Flutter 已知行為），
/// 導致頁尾意外變成佔滿整個畫面。包一層 `Column(mainAxisSize.min)` 能讓
/// `Row` 收到「無界（unbounded）」高度上限（`Flex` 對非 flexible 子項在
/// 主軸方向一律給無界上限的既有行為），此時 `Slider` 才會退回自然高度，
/// 在真實 `ReaderScreen`（外層 `Column` 的非 flex 子項）與既有測試的裸
/// `Scaffold.body` 兩種父層情境下都能穩定保持緊湊。
```

- [x] **Step 4：修改 `reader_footer.dart` 的 `build()`**

把第 87-138 行：

```dart
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
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    final progressPercent =
        widget.totalPages > 0 ? (widget.currentPage / widget.totalPages * 100).round() : 0;
    return Container(
      key: const Key('reader_footer'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        // 見上方類別文件註解「Slider 高度陷阱」完整原因說明——刻意保留，
        // 不是多餘的殘留寫法。
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  key: const Key('reader_footer_progress_text'),
                  '${widget.currentPage}/${widget.totalPages}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
                  // 原本獨立一列的「進度 YY%」文字併入單行版面後，改以
                  // Slider 拖曳時顯示的 label 呈現（issues.md Issue 2）。
                  label: '$progressPercent%',
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
```

- [x] **Step 5：執行測試，確認全部通過**

```bash
flutter test test/screens/reader_footer_test.dart test/screens/reader_screen_test.dart
```

Expected：全部 PASS，包含 Step 1 更新/新增的所有斷言，以及既有全部測試不受影響。

- [x] **Step 6：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 7：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/lib/screens/reader_footer.dart app/test/screens/reader_footer_test.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-18): ReaderFooter 合併為單一 Row，縮短頁尾佔用高度"
```

---

### Task 2：`AppBar` 瘦身（`toolbarHeight` + 動作按鈕/標題收斂）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1207-1210`（`build()` 內 `AppBar(...)`）、`:1224-1239`（`_buildAppBarTitle()`）、`:1241-1313`（`_buildAppBarActions()`）
- Test: `app/test/screens/reader_screen_test.dart`（新增 2 個測試）

**Interfaces:**
- Consumes：`_isFixedLayout`／`_chromeVisible`／`_resolved`／`_autoDetectedWritingMode`／`_tocLoaded`／`_epubPositionInfo`／`_state`／`_tocEntries`（既有欄位，不變）
- Produces：新增 4 個 `static const`（`_appBarToolbarHeight = 20.0`、`_appBarButtonMinWidth = 32.0`、`_appBarIconSize = 18.0`、`_appBarTitleFontSize = 13.0`），供 Task 3 真機驗收與未來微調參考

- [x] **Step 1：撰寫失敗測試——擴充 `reader_screen_test.dart`**

在第 1430 行（`'PDF 開書後，AppBar 標題恆為靜態「閱讀器」文字（頁首概念僅限 EPUB）'` 測試結尾的 `});`）之後、下一個 `testWidgets`（第 1432 行）之前，插入以下兩個測試：

```dart
  testWidgets('AppBar 顯示時，toolbarHeight 瘦身為 20（Issue 2）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_appbar_toolbar_height',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.preferredSize.height, 20.0);
  });

  testWidgets('AppBar 動作按鈕已收斂實際渲染寬度與圖示大小（Issue 2）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_appbar_action_size',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 斷言實際渲染的 Rect，而非只檢查建構子的 constraints/padding 欄位——
    // Material 3 的 IconButton 不會因建構子的 padding/constraints 參數而
    // 改變實際渲染尺寸（撰寫本計劃時已實測確認，見 Global Constraints
    // 「IconButton 尺寸收斂機制」），只檢查欄位值會造成「測試通過但實際
    // 尺寸沒變」的假陽性。
    final buttonRect = tester.getRect(
      find.byKey(const Key('reader_layout_settings_button')),
    );
    expect(buttonRect.width, 32.0);
    expect(buttonRect.height, 20.0, reason: '高度恆等於 toolbarHeight，見 Global Constraints 說明');

    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader_layout_settings_button')),
    );
    expect((button.icon as Icon).size, 18.0);
  });
```

- [x] **Step 2：執行測試，確認新增測試失敗**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：新增的兩個測試 FAIL——現行 `AppBar` 沒有設定 `toolbarHeight`，`preferredSize.height` 目前是預設的 `56.0`，不等於 `20.0`；現行 `IconButton` 也沒有設定 `style`，實際渲染 `Rect` 目前是 Material 3 預設寬度（`48.0`，不等於 `32.0`），`icon` 沒有 `size`（`null`／預設值），與斷言不符。既有測試維持 PASS。

- [x] **Step 3：修改 `build()` 內的 `AppBar(...)`**

把第 1207-1210 行：

```dart
            : AppBar(
                title: _buildAppBarTitle(format),
                actions: _buildAppBarActions(format),
              ),
```

改為：

```dart
            : AppBar(
                toolbarHeight: _appBarToolbarHeight,
                title: _buildAppBarTitle(format),
                actions: _buildAppBarActions(format),
              ),
```

- [x] **Step 4：修改 `_buildAppBarTitle()`**

把第 1224-1239 行：

```dart
  Widget _buildAppBarTitle(BookFormat format) {
    final showHeader = format == BookFormat.epub && (_resolved?.showHeader ?? true);
    if (!showHeader) {
      return const Text('閱讀器', key: Key('reader_appbar_static_title'));
    }
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final chapterTitle = currentPath.isEmpty ? '閱讀器' : currentPath.last.title;
    return InkWell(
      key: const Key('reader_appbar_chapter_title'),
      onTap: (_autoDetectedWritingMode == null || !_tocLoaded) ? null : _openToc,
      child: Text(chapterTitle, overflow: TextOverflow.ellipsis),
    );
  }
```

改為：

```dart
  Widget _buildAppBarTitle(BookFormat format) {
    final showHeader = format == BookFormat.epub && (_resolved?.showHeader ?? true);
    if (!showHeader) {
      return const Text(
        '閱讀器',
        key: Key('reader_appbar_static_title'),
        style: TextStyle(fontSize: _appBarTitleFontSize),
      );
    }
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final chapterTitle = currentPath.isEmpty ? '閱讀器' : currentPath.last.title;
    return InkWell(
      key: const Key('reader_appbar_chapter_title'),
      onTap: (_autoDetectedWritingMode == null || !_tocLoaded) ? null : _openToc,
      child: Text(
        chapterTitle,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: _appBarTitleFontSize),
      ),
    );
  }

  // AppBar 瘦身（Epic 18 Issue 2，design.md 決策 #2：縮減至約現有高度
  // 1/3）：只設定 toolbarHeight 不夠——IconButton 預設觸控寬度 48dp、
  // 預設圖示 24dp，title 文字預設字級，在 20dp 高的 AppBar 內都會偏擠，
  // 故同步收斂三者。以下數值為起始建議值，真機測試（Task 3）後可再調整
  // （issues.md Issue 2 審查修正）。
  //
  // 【實測發現，記錄供未來維護者知悉】_buildAppBarActions() 的
  // IconButton 一律透過 `style: IconButton.styleFrom(...)` 收斂尺寸，
  // 不使用建構子的 `padding`/`constraints` 參數——Material 3 的
  // IconButton 在本專案 Flutter 版本（3.41.9）下，`padding`/`constraints`
  // 這兩個建構子參數對實際渲染尺寸完全無效（實測仍是 48dp 預設寬度），
  // 必須透過 `style` 才能真正生效。另外，AppBar.actions 內的按鈕實際
  // 渲染高度無論如何設定都會被鎖死在 toolbarHeight（本例為 20），故這裡
  // 只需要一個「最小寬度」常數，不需要（也無法生效）獨立的「最小高度」
  // 常數——`_appBarButtonMinWidth` 只控制寬度，高度直接沿用
  // `_appBarToolbarHeight`。
  static const _appBarToolbarHeight = 20.0;
  static const _appBarButtonMinWidth = 32.0;
  static const _appBarIconSize = 18.0;
  static const _appBarTitleFontSize = 13.0;
```

- [x] **Step 5：修改 `_buildAppBarActions()`**

把第 1241-1313 行：

```dart
  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (_isFixedLayout) return null;
    switch (format) {
      case BookFormat.epub:
        return [
          IconButton(
            key: const Key('reader_toc_button'),
            icon: const Icon(Icons.menu_book),
            tooltip: '目錄',
            // 沿用與「⚙️版面」按鈕一致的啟用條件（_autoDetectedWritingMode
            // 非 null 代表 onLayoutResolved 已觸發，書本已成功開啟），並
            // 額外要求 _tocLoaded（審查修正）——避免使用者在背景抓取
            // 完成前點擊，開啟一個無法與「本書真的沒有目錄」區分的空白
            // Bottom Sheet。
            onPressed: (_autoDetectedWritingMode == null || !_tocLoaded)
                ? null
                : _openToc,
          ),
          IconButton(
            key: const Key('reader_layout_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '版面設定',
            // _autoDetectedWritingMode 非 null 代表 onLayoutResolved 已觸發，
            // 書本已成功開啟、navigatorFragment 已存在，此時開啟版面設定並
            // 呼叫 setPreferences 才有意義（見 EpubReaderView.kt 的靜默忽略
            // 邏輯說明）。
            onPressed:
                _autoDetectedWritingMode == null ? null : _openLayoutSettings,
          ),
          if (widget.bookmarksRepository != null)
            IconButton(
              key: const Key('reader_notes_button'),
              icon: const Icon(Icons.bookmarks),
              tooltip: '筆記',
              // 除了 _autoDetectedWritingMode（onLayoutResolved 已觸發）之外，
              // 額外要求 _epubPositionInfo 非 null（審查修正）——這兩個回呼
              // 來自原生端兩條各自獨立、無先後順序保證的非同步路徑
              // （onLayoutResolved／onLocatorChanged），若只檢查前者，使用者
              // 可能在 onLocatorChanged 尚未觸發過任何一次的極短窗口內點擊
              // 「新增書籤」，寫入一筆 epubLocatorJson/progression 皆為 null
              // 的壞書籤（之後永遠無法被跳轉、判定為已加書籤或移除）。比照
              // 目錄按鈕 _tocLoaded 的既有防呆模式（見上方 reader_toc_button
              // 註解），同一種競速問題、不同欄位。
              onPressed: (_autoDetectedWritingMode == null || _epubPositionInfo == null)
                  ? null
                  : () => _openNotesSheet(format),
            ),
        ];
      case BookFormat.pdf:
        return [
          IconButton(
            key: const Key('reader_layout_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '版面設定',
            // _state == rendered 代表 onPageRendered 已觸發，PDF 已成功
            // 開啟，此時開啟版面設定並呼叫 setPdfPreferences 才有意義，比照
            // EPUB 分支的既有判斷原則。
            onPressed: _state == _RenderState.rendered ? _openPdfSettings : null,
          ),
          if (widget.bookmarksRepository != null)
            IconButton(
              key: const Key('reader_notes_button'),
              icon: const Icon(Icons.bookmarks),
              tooltip: '筆記',
              onPressed: _state == _RenderState.rendered
                  ? () => _openNotesSheet(format)
                  : null,
            ),
        ];
      case BookFormat.unknown:
        return null;
    }
  }
```

改為：

```dart
  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (_isFixedLayout) return null;
    switch (format) {
      case BookFormat.epub:
        return [
          IconButton(
            key: const Key('reader_toc_button'),
            icon: const Icon(Icons.menu_book, size: _appBarIconSize),
            tooltip: '目錄',
            style: IconButton.styleFrom(
              minimumSize: const Size(_appBarButtonMinWidth, _appBarToolbarHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            ),
            // 沿用與「⚙️版面」按鈕一致的啟用條件（_autoDetectedWritingMode
            // 非 null 代表 onLayoutResolved 已觸發，書本已成功開啟），並
            // 額外要求 _tocLoaded（審查修正）——避免使用者在背景抓取
            // 完成前點擊，開啟一個無法與「本書真的沒有目錄」區分的空白
            // Bottom Sheet。
            onPressed: (_autoDetectedWritingMode == null || !_tocLoaded)
                ? null
                : _openToc,
          ),
          IconButton(
            key: const Key('reader_layout_settings_button'),
            icon: const Icon(Icons.settings, size: _appBarIconSize),
            tooltip: '版面設定',
            style: IconButton.styleFrom(
              minimumSize: const Size(_appBarButtonMinWidth, _appBarToolbarHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            ),
            // _autoDetectedWritingMode 非 null 代表 onLayoutResolved 已觸發，
            // 書本已成功開啟、navigatorFragment 已存在，此時開啟版面設定並
            // 呼叫 setPreferences 才有意義（見 EpubReaderView.kt 的靜默忽略
            // 邏輯說明）。
            onPressed:
                _autoDetectedWritingMode == null ? null : _openLayoutSettings,
          ),
          if (widget.bookmarksRepository != null)
            IconButton(
              key: const Key('reader_notes_button'),
              icon: const Icon(Icons.bookmarks, size: _appBarIconSize),
              tooltip: '筆記',
              style: IconButton.styleFrom(
                minimumSize: const Size(_appBarButtonMinWidth, _appBarToolbarHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
              // 除了 _autoDetectedWritingMode（onLayoutResolved 已觸發）之外，
              // 額外要求 _epubPositionInfo 非 null（審查修正）——這兩個回呼
              // 來自原生端兩條各自獨立、無先後順序保證的非同步路徑
              // （onLayoutResolved／onLocatorChanged），若只檢查前者，使用者
              // 可能在 onLocatorChanged 尚未觸發過任何一次的極短窗口內點擊
              // 「新增書籤」，寫入一筆 epubLocatorJson/progression 皆為 null
              // 的壞書籤（之後永遠無法被跳轉、判定為已加書籤或移除）。比照
              // 目錄按鈕 _tocLoaded 的既有防呆模式（見上方 reader_toc_button
              // 註解），同一種競速問題、不同欄位。
              onPressed: (_autoDetectedWritingMode == null || _epubPositionInfo == null)
                  ? null
                  : () => _openNotesSheet(format),
            ),
        ];
      case BookFormat.pdf:
        return [
          IconButton(
            key: const Key('reader_layout_settings_button'),
            icon: const Icon(Icons.settings, size: _appBarIconSize),
            tooltip: '版面設定',
            style: IconButton.styleFrom(
              minimumSize: const Size(_appBarButtonMinWidth, _appBarToolbarHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            ),
            // _state == rendered 代表 onPageRendered 已觸發，PDF 已成功
            // 開啟，此時開啟版面設定並呼叫 setPdfPreferences 才有意義，比照
            // EPUB 分支的既有判斷原則。
            onPressed: _state == _RenderState.rendered ? _openPdfSettings : null,
          ),
          if (widget.bookmarksRepository != null)
            IconButton(
              key: const Key('reader_notes_button'),
              icon: const Icon(Icons.bookmarks, size: _appBarIconSize),
              tooltip: '筆記',
              style: IconButton.styleFrom(
                minimumSize: const Size(_appBarButtonMinWidth, _appBarToolbarHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
              onPressed: _state == _RenderState.rendered
                  ? () => _openNotesSheet(format)
                  : null,
            ),
        ];
      case BookFormat.unknown:
        return null;
    }
  }
```

- [x] **Step 6：執行測試，確認全部通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：全部 PASS，包含 Step 1 新增的兩個測試，以及既有全部測試不受影響（特別留意：`test/screens/reader_screen_test.dart:2333-2343` 比較 `PdfReaderView` 尺寸是否因 AppBar 顯示/隱藏而改變的既有測試，本 Task 未改動 `extendBodyBehindAppBar`/`_buildBody()` 機制，應維持通過）。

- [x] **Step 7：全專案回歸測試 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：`flutter test` 全數 PASS（含 Task 1、Task 2 新增/修改的所有測試，以及既有全部測試不受影響）；`flutter analyze` "No issues found!"。

- [x] **Step 8：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-18): AppBar 瘦身為 toolbarHeight 20，同步收斂動作按鈕與標題尺寸"
```

---

### Task 3：真機驗收——AppBar／頁尾縮短後既有功能仍可正常操作

**Files:** 無程式碼異動（純驗收，`issues.md` Issue 2 驗收標準要求的真機確認）

**Interfaces:**
- Consumes：Task 1／Task 2 已 commit 的 `ReaderFooter` 合併版面與 `AppBar` 瘦身設定
- Produces：驗收結論（記錄於本計劃 Step 2 的核對表，供人類決定是否合併；若 Step 2 發現任一項尺寸不理想，記錄具體建議調整值，交由人類決定是否回頭調整 Task 2 的起始建議值）

- [x] **Step 1：建置並安裝 debug APK 到真機**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
adb devices -l
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected：`adb devices -l` 列出 `3CEF42ECD491687`；建置與安裝皆成功（`Success`）。

- [x] **Step 2：逐一確認 AppBar／頁尾縮短後既有功能可正常點擊操作**

開啟一本流式 EPUB，依序確認：
- AppBar 明顯變薄（相較修改前的 56dp，肉眼可辨識高度縮減），標題文字可正常閱讀不被裁切。
- 點擊 AppBar 上的「目錄」「版面設定」「筆記」三個按鈕，確認皆能正確觸發（不因觸控寬度縮小為 32dp、高度鎖定為 20dp 而難以點擊或誤觸）。**不需要**特別檢查按鈕是否視覺上突出 AppBar 邊界或與狀態列重疊——已於撰寫本計劃時實測確認 `AppBar.actions` 內的按鈕高度無論如何設定都會被鎖死在 `toolbarHeight`（20dp），不會有這類溢出（見 Global Constraints「AppBar 會把動作按鈕的高度無條件鎖死在 toolbarHeight」，該段落已具體回應並推翻 `tmp/epic-18/reviews/review-plan-issue-2.md` 對此的 Minor 疑慮）；真機驗收重點應放在「20dp／32dp 這麼小的觸控目標，實際手指操作是否好按」這個純粹的人因（ergonomics）問題，而非版面溢出問題。
- 頁尾（`ReaderFooter`）確認合併為單一列，肉眼可見比修改前明顯變矮；點擊跳頁輸入框輸入頁碼、拖曳進度捲軸，確認皆正常運作，且拖曳時可看到 `label` 顯示的百分比。

開啟一本 PDF，重複確認 AppBar 上的「版面設定」「筆記」按鈕與頁尾跳頁互動皆正常。

Expected：以上互動皆正確無誤，無按鈕因觸控目標過小而難以點擊、無文字被裁切。若發現按鈕在真機上因觸控目標太小而不好按（人因問題，非版面溢出問題），記錄具體觀察與建議調整值，交由人類決定是否回頭調整 Task 2 的 `_appBarButtonMinWidth`/`_appBarIconSize`/`_appBarTitleFontSize` 起始建議值（`toolbarHeight`／按鈕高度 20dp 本身已是 `design.md` 決策 #2 的既定取捨，不在本 Task 的調整範圍內）。

無需 commit（本 Task 純驗收，不變更任何檔案，除非 Step 2 發現需要調整起始建議值並經人類確認後才回頭修改 Task 2 程式碼）。

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：`issues.md` Issue 2 的兩個修改點（AppBar 高度 + 頁尾合併單行）分別對應 Task 2 與 Task 1；單元測試要求的四類（頁尾既有 Key 行為不變、頁尾高度回歸、AppBar `preferredSize.height`、既有字串斷言 2+7 處同步更新）分別對應 Task 1 Step 1（既有 Key 行為由既有測試延續驗證＋新增高度/label 測試）與 Task 2 Step 1（`preferredSize.height`）；驗收標準的真機功能操作確認對應 Task 3。
- **實測優先於猜測**：撰寫本計劃時已實際建立探測用 widget test（測試完畢即刪除，未進版控）量測「合併前 84.0／合併後 64.0」的真實高度數字，以及驗證「拿掉 `Column(mainAxisSize.min)` 會讓 `Slider` 在特定父層情境下撐滿至 600」的具體機制，兩者皆已寫入 Global Constraints 與程式碼註解，不是憑空假設的數字或行為。
- **無佔位符掃描**：所有 Task 皆附完整可執行的程式碼（`build()`／文件註解完整 before/after、測試完整程式碼、`adb`/`flutter` 完整指令），無 "TODO"/"視情況" 字樣；issues.md 原文刻意留給實作階段決定的兩處開放式描述（頁尾進度文字要不要保留完整「進度 YY%」、頁尾下邊距是否需要動態公式——後者屬於 Issue 4 範圍不在本計劃）皆已在 Global Constraints 中做出具體、可執行的落地決定（百分比併入 Slider label；頁碼格式為 `currentPage/totalPages`）。
- **型別/介面一致性**：`ReaderFooter` 對外建構參數（`currentPage`／`totalPages`／`onPageChanged`）在 Task 1 前後完全一致，`reader_screen.dart` 三處既有呼叫點不需要修改；Task 2 新增的 4 個 `static const`（`_appBarToolbarHeight`／`_appBarButtonMinWidth`／`_appBarIconSize`／`_appBarTitleFontSize`）在 `_buildAppBarTitle()`／`_buildAppBarActions()`／`build()` 三處引用時命名完全一致。
- **Task 執行順序的依賴關係**：Task 1（`ReaderFooter`）與 Task 2（`AppBar`）互不依賴、可任意順序或平行進行（分屬不同檔案、不同 widget）；Task 3（真機驗收）必須在 Task 1、Task 2 皆已 commit 之後才進行（依賴兩者建置進最終 APK）。
- **對 `tmp/epic-18/reviews/review-plan-issue-2.md` 審查意見的回應**：
  1. **不採納，已用 widget test 實測推翻**：審查提出的 Minor 疑慮「`IconButton` 在 `toolbarHeight: 20` 的 `AppBar` 內因 `minHeight: 32` 而垂直溢出 6dp、可能與狀態列重疊」，實測不成立——`AppBar.actions` 內的按鈕實際渲染高度無論 `minimumSize`/`constraints` 要求多高（實測 `20`／`24`／`32`／`48` 四種數值），一律被鎖死在 `toolbarHeight` 本身，不存在溢出或裁切問題，故未採納其建議的「必要時降為 `minHeight: 24`」備援方案（該方案本身無意義，`24` 與原本的 `32` 效果相同，皆會被夾到 `20`）。已把驗證結論與具體實測數字寫入 Global Constraints，Task 3 的驗收重點相應調整為「觸控目標大小的人因問題」而非「版面溢出問題」。
  2. **審查未發現、但驗證審查意見過程中額外發現的較嚴重問題，已修正**：驗證上述疑慮時發現，原計劃 Task 2 Step 5 寫的 `IconButton(padding: EdgeInsets.zero, constraints: BoxConstraints(minWidth: 32, minHeight: 32))` 在本專案 Flutter 版本（`3.41.9`，Material 3 預設 `IconButton`）下，`padding`/`constraints` 這兩個建構子參數對實際渲染尺寸完全無效（實測仍是 Material 3 預設寬度 `48.0`），必須改用 `style: IconButton.styleFrom(minimumSize: ..., tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: ...)` 才能讓寬度真正收斂為 `32`（已實測確認）。原計劃 Task 2 Step 1 的測試（`expect(button.constraints, const BoxConstraints(minWidth: 32, minHeight: 32))`）只檢查建構子欄位值，即使程式碼完全沒有收斂效果也會通過，是會製造假陽性的弱測試——已改為直接斷言 `tester.getRect(...)` 的實際渲染寬高，兩處問題已一併修正於 Task 2 Step 1、Step 4、Step 5。
