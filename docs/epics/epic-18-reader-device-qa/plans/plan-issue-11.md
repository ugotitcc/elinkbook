# Issue 11：流式 EPUB 進度/跳頁 Bottom Sheet 補上 `SafeArea` 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 讓流式 EPUB 的「進度/跳頁」浮動按鈕開啟的 Bottom Sheet，比照同檔案內其餘 Bottom Sheet（`ReaderSettingsSheet`／`TocBottomSheet`）補上 `SafeArea`，避免內容被系統手勢列/三鍵導覽列蓋住。

**架構：** `_openFoliateProgressSheet()`（`app/lib/screens/reader_screen.dart`）的 `showModalBottomSheet` `builder` 回傳值外層包一層 `SafeArea`，其餘邏輯不變。

**Tech Stack：** Flutter/Dart，`flutter_test` widget test（純 Dart，不需裝置）。

## Global Constraints

- 只修改 `builder` 的回傳值本身，不動 `_buildFoliateEpubFooter()`／`ReaderFooter` 任何既有邏輯。
- `SafeArea` 使用預設參數（`top`/`bottom` 皆為 `true`）即可，不需要額外指定 `top: false`——那是 `_buildBody()` 主畫面 `Scaffold` 才需要的特例（避免 AppBar 顯示/隱藏觸發 PlatformView resize，見 `reader_screen.dart:1697-1709` 既有註解），Bottom Sheet 是獨立路由，不受那個限制影響。
- 真機驗收裝置固定為 `3CEF42ECD491687`。

---

## 檔案結構

本計劃只修改單一檔案：

- **修改：** `app/lib/screens/reader_screen.dart`（`_openFoliateProgressSheet()` 方法，約第 1836-1845 行）

---

### Task 1：`_openFoliateProgressSheet()` 補上 `SafeArea`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1836-1845`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: 既有 `_buildFoliateEpubFooter(EpubPositionInfo positionInfo)`（回傳 `ReaderFooter` widget，不修改其簽章）。
- Produces: 無新的對外可呼叫函式，純內部 widget 樹調整。

- [x] **Step 1: 確認現況**

執行：
```bash
grep -n "_openFoliateProgressSheet" -A 10 app/lib/screens/reader_screen.dart
```

預期看到：
```dart
void _openFoliateProgressSheet() {
  final positionInfo = _epubPositionInfo;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => positionInfo == null
        ? const SizedBox.shrink()
        : _buildFoliateEpubFooter(positionInfo),
  );
}
```

- [x] **Step 2: 撰寫會失敗的測試**

在 `app/test/screens/reader_screen_test.dart` 找到既有測試「流式 EPUB：點擊浮動進度/跳頁按鈕開啟內含 ReaderFooter 的 Bottom Sheet，舊 in-flow 頁尾不再存在（Issue 7）」（`grep -n "點擊浮動進度/跳頁按鈕開啟內含 ReaderFooter" app/test/screens/reader_screen_test.dart` 確認行號），在同一個 `describe`/檔案範圍內、緊接該測試之後新增：

```dart
  testWidgets(
    '流式 EPUB：進度/跳頁 Bottom Sheet 內容包在 SafeArea 內，避免被系統工具列蓋住（Issue 11）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            // 模擬有系統手勢列/三鍵導覽列的裝置：viewPadding.bottom > 0。
            data: const MediaQueryData(
              viewPadding: EdgeInsets.only(bottom: 48),
            ),
            child: ReaderScreen(
              filePath: 'test/fixtures/sample.epub',
              bookId: 'b_foliate_progress_safearea',
              prefsManager: prefsManager,
              isFixedLayout: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          pageIndex: 0,
          totalPages: 10,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_foliate_progress_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final sliderFinder = find.byKey(const Key('reader_footer_jump_slider'));
      expect(sliderFinder, findsOneWidget);
      expect(
        find.ancestor(of: sliderFinder, matching: find.byType(SafeArea)),
        findsOneWidget,
        reason: '跳頁滑桿須包在 SafeArea 內，避免被系統工具列（viewPadding.bottom）蓋住',
      );
    },
  );
```

- [x] **Step 3: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/screens/reader_screen_test.dart --plain-name "進度/跳頁 Bottom Sheet 內容包在 SafeArea 內"
```
預期：FAIL——`find.ancestor(... matching: find.byType(SafeArea))` 找不到 `SafeArea`（`findsNothing`，因為目前 `builder` 沒有包 `SafeArea`）。

- [x] **Step 4: 實作修正**

修改 `reader_screen.dart:1836-1845`：

```dart
  void _openFoliateProgressSheet() {
    final positionInfo = _epubPositionInfo;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: positionInfo == null
            ? const SizedBox.shrink()
            : _buildFoliateEpubFooter(positionInfo),
      ),
    );
  }
```

- [x] **Step 5: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/screens/reader_screen_test.dart --plain-name "進度/跳頁 Bottom Sheet 內容包在 SafeArea 內"
```
預期：PASS。

- [x] **Step 6: 執行全部既有測試回歸**

執行：
```bash
cd app && flutter analyze
cd app && flutter test
```
預期：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過（含既有「點擊浮動進度/跳頁按鈕開啟內含 ReaderFooter 的 Bottom Sheet」等測試，純外層包裝、不改變其行為）。

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-18): Issue 11 進度/跳頁 Bottom Sheet 補上 SafeArea"
```

---

### Task 2：真機驗收

**Files:** 無程式碼異動（純真機人工驗證）。

**Interfaces:**
- Consumes: Task 1 完成後的 `reader_screen.dart`。
- Produces: 驗收結果記錄（供合併前的程式碼審查／`issues.md` Issue 11 狀態更新引用）。

- [ ] **Step 1: 安裝最新 debug APK 至真機 `3CEF42ECD491687`**

```bash
cd app && flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: 驗證進度/跳頁 Bottom Sheet 不被系統工具列蓋住**

1. 開啟一本流式 EPUB。
2. 點擊進度/跳頁浮動按鈕（`reader_foliate_progress_button`）開啟 Bottom Sheet。
3. 確認跳頁捲軸與輸入框完整顯示在系統工具列（若裝置有手勢列/三鍵導覽列）上方，可正常拖曳互動、不被遮擋。
4. 記錄：Pass/Fail + 截圖佐證。

- [ ] **Step 3: 記錄驗收結果**

供後續程式碼審查與 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 11 狀態更新引用。

---

## 相關佐證

- `design.md`「第三輪真機使用回報」項目 1
