# Issue 13：流式 EPUB 頁首/進度文字從沉浸模式拆出、跟內文常駐顯示 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 讓流式 EPUB 的頁首文字（`reader_foliate_header_text`）與進度文字（`reader_foliate_progress_text`）改為只依 `showHeader`/`showFooter` 開關決定顯示，不再受 `_chromeVisible`（沉浸模式）切換影響；6 顆浮動**功能按鈕**（含 Issue 12 修正後的進度/跳頁鈕）維持跟隨 `_chromeVisible` 不變。

**架構：** 移除 `reader_screen.dart` 中頁首文字與進度文字兩個 `Positioned` 區塊顯示條件裡的 `_chromeVisible` 子句，其餘邏輯（內容換算、位置、`RotatedBox` 直排處理）完全不變。6 顆浮動按鈕的既有顯示條件不動。

**Tech Stack：** Flutter/Dart，`flutter_test` widget test（純 Dart，不需裝置）。

## Global Constraints

- **範圍僅限流式 EPUB**（`format == BookFormat.epub && _dispatchedIsFixedLayout == false`）。FXL（本無頁首/頁尾文字，只有按鈕）與 PDF（in-flow 頁尾，牽動既有 resize 限制）不受本 Issue 影響、不修改任何 FXL/PDF 相關程式碼。
- 6 顆浮動功能按鈕（`reader_foliate_back_button`／`reader_foliate_toc_button`／`reader_foliate_settings_button`／`reader_foliate_bookmark_toggle_button`／`reader_foliate_notes_button`／`reader_foliate_progress_button`）的既有顯示條件**不變動**，繼續跟隨 `_chromeVisible`——本 Issue 只拆分「資訊顯示」，不動「功能操作」的既有沉浸模式行為。
- 真機驗收裝置固定為 `3CEF42ECD491687`。

---

## 檔案結構

本計劃只修改單一檔案：

- **修改：** `app/lib/screens/reader_screen.dart`（頁首文字 `Positioned` 約第 1637-1646 行、進度文字 `Positioned` 約第 1647-1666 行）

---

### Task 1：頁首文字脫離 `_chromeVisible`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1637-1646`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: 既有 `_resolved`（`ResolvedPreferences?`）、`_buildFoliateHeaderText()`（既有方法，不修改簽章）。
- Produces: 無新的對外可呼叫函式，純顯示條件調整。

- [ ] **Step 1: 確認現況**

執行：
```bash
grep -n "reader_foliate_header_text" -B 8 app/lib/screens/reader_screen.dart | head -12
```

預期看到（約第 1637-1646 行）：
```dart
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _chromeVisible &&
                (_resolved?.showHeader ?? true))
              Positioned(
                top: 16,
                left: 72,
                right: 72,
                child: Center(child: _buildFoliateHeaderText()),
              ),
```

- [ ] **Step 2: 撰寫會失敗的測試**

在 `app/test/screens/reader_screen_test.dart` 找到既有測試「流式 EPUB：頁眉純顯示章節名稱、不可點擊，`showHeader=false` 時不顯示（Issue 7）」（`grep -n "頁眉純顯示章節名稱" app/test/screens/reader_screen_test.dart` 確認行號），在其後新增：

```dart
  testWidgets(
    '流式 EPUB：沉浸模式收起選單（_chromeVisible=false）時，頁首文字仍常駐顯示、6 顆浮動按鈕正確收合（Issue 13）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_header_immersive',
            prefsManager: prefsManager,
            isFixedLayout: false,
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
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();

      // navZoneMode 預設 rightFlip，index 1（中欄）為 menu（見
      // app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_foliate_back_button')),
        findsNothing,
        reason: '沉浸模式收起後，浮動功能按鈕應收合',
      );
      expect(
        find.byKey(const Key('reader_foliate_header_text')),
        findsOneWidget,
        reason: '頁首文字（資訊顯示）不受沉浸模式影響，應常駐顯示',
      );
    },
  );
```

- [ ] **Step 3: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/screens/reader_screen_test.dart --plain-name "頁首文字仍常駐顯示、6 顆浮動按鈕正確收合"
```
預期：FAIL——`find.byKey(const Key('reader_foliate_header_text'))` 為 `findsNothing`（目前頁首文字仍受 `_chromeVisible` 控制，收起選單後一併消失）。

- [ ] **Step 4: 實作修正**

修改 `reader_screen.dart:1637-1646`，移除 `_chromeVisible` 子句：

```dart
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                (_resolved?.showHeader ?? true))
              Positioned(
                top: 16,
                left: 72,
                right: 72,
                child: Center(child: _buildFoliateHeaderText()),
              ),
```

- [ ] **Step 5: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/screens/reader_screen_test.dart --plain-name "頁首文字仍常駐顯示、6 顆浮動按鈕正確收合"
```
預期：PASS。

- [ ] **Step 6: 執行既有頁首相關測試回歸**

執行：
```bash
cd app && flutter test test/screens/reader_screen_test.dart --plain-name "頁眉"
```
預期：既有「頁眉純顯示章節名稱、不可點擊，`showHeader=false` 時不顯示」與「`showHeader=false` 時頁眉不顯示」兩項測試皆維持 PASS（本步驟只移除 `_chromeVisible` 這一項判斷，`showHeader` 判斷邏輯不變）。

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-18): Issue 13 Task 1 頁首文字脫離沉浸模式，跟內文常駐顯示"
```

---

### Task 2：進度文字脫離 `_chromeVisible`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1647-1666`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: 既有 `_resolved`（`ResolvedPreferences?`）、`_epubPositionInfo`（`EpubPositionInfo?`）、`_buildFoliateProgressText()`（既有方法，不修改簽章）。
- Produces: 無新的對外可呼叫函式，純顯示條件調整。

- [ ] **Step 1: 確認現況**

執行：
```bash
grep -n "reader_foliate_progress_text" -B 5 -A 15 app/lib/screens/reader_screen.dart | head -25
```

預期看到（約第 1647-1666 行）：
```dart
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _chromeVisible &&
                (_resolved?.showFooter ?? true) &&
                (_epubPositionInfo?.totalPages ?? 0) > 0)
              (_resolved?.writingMode == WritingMode.vertical)
                  ? Positioned(
                      left: 16,
                      bottom: 16,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: _buildFoliateProgressText(),
                      ),
                    )
                  : Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(child: _buildFoliateProgressText()),
                    ),
```

- [ ] **Step 2: 撰寫會失敗的測試**

在 `app/test/screens/reader_screen_test.dart` 新增（緊接 Task 1 新增的測試之後）：

```dart
  testWidgets(
    '流式 EPUB：沉浸模式收起選單（_chromeVisible=false）時，進度文字仍常駐顯示（Issue 13）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_progress_immersive',
            prefsManager: prefsManager,
            isFixedLayout: false,
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
          pageIndex: 167,
          totalPages: 197,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_foliate_progress_button')),
        findsNothing,
        reason: '沉浸模式收起後，浮動功能按鈕應收合',
      );
      expect(
        find.byKey(const Key('reader_foliate_progress_text')),
        findsOneWidget,
        reason: '進度文字（資訊顯示）不受沉浸模式影響，應常駐顯示',
      );
      expect(find.text('168/197'), findsOneWidget);
    },
  );
```

- [ ] **Step 3: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/screens/reader_screen_test.dart --plain-name "進度文字仍常駐顯示（Issue 13）"
```
預期：FAIL——`find.byKey(const Key('reader_foliate_progress_text'))` 為 `findsNothing`（目前進度文字仍受 `_chromeVisible` 控制）。

- [ ] **Step 4: 實作修正**

修改 `reader_screen.dart:1647-1666`，移除 `_chromeVisible` 子句：

```dart
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                (_resolved?.showFooter ?? true) &&
                (_epubPositionInfo?.totalPages ?? 0) > 0)
              (_resolved?.writingMode == WritingMode.vertical)
                  ? Positioned(
                      left: 16,
                      bottom: 16,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: _buildFoliateProgressText(),
                      ),
                    )
                  : Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(child: _buildFoliateProgressText()),
                    ),
```

- [ ] **Step 5: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/screens/reader_screen_test.dart --plain-name "進度文字仍常駐顯示（Issue 13）"
```
預期：PASS。

- [ ] **Step 6: 執行既有進度文字相關測試回歸**

執行：
```bash
cd app && flutter test test/screens/reader_screen_test.dart --plain-name "進度"
cd app && flutter analyze
cd app && flutter test
```
預期：既有「進度為純顯示、橫排時置於下方置中且不含手勢 widget」「直排時進度以 `RotatedBox` 顯示於左下角」「`showFooter=false` 時進度文字不顯示，但進度/跳頁按鈕仍顯示且可點擊（Issue 12 已改寫）」等測試皆維持 PASS；`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過。

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-18): Issue 13 Task 2 進度文字脫離沉浸模式，跟內文常駐顯示"
```

---

### Task 3：真機驗收

**Files:** 無程式碼異動（純真機人工驗證）。

**Interfaces:**
- Consumes: Task 1／Task 2 完成後的 `reader_screen.dart`。
- Produces: 驗收結果記錄（供合併前的程式碼審查／`issues.md` Issue 13 狀態更新引用）。

- [ ] **Step 1: 安裝最新 debug APK 至真機 `3CEF42ECD491687`**

```bash
cd app && flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: 驗證頁首/進度文字常駐顯示**

1. 開啟一本流式 EPUB，確認「顯示頁首」「顯示進度」皆為開啟。
2. 點擊選單熱區收起浮動按鈕（沉浸模式）。
3. 確認頁首文字（章節名稱）與進度文字（頁碼）仍常駐顯示，只有 6 顆浮動按鈕收合。
4. 再次點擊選單熱區叫出浮動按鈕，確認按鈕正常出現、不與常駐的頁首/進度文字重疊或衝突。
5. 分別關閉「顯示頁首」/「顯示進度」，確認對應文字仍會正確隱藏（不受本次改動影響）。
6. 記錄：Pass/Fail + 截圖佐證。

- [ ] **Step 3: FXL／PDF 回歸確認**

1. 開啟一本 FXL（固定版面）EPUB，確認既有沉浸模式行為（4 顆浮動按鈕跟隨收合/顯示）未受影響。
2. 開啟一本 PDF，確認既有 AppBar／頁尾沉浸模式行為未受影響。
3. 記錄：Pass/Fail。

- [ ] **Step 4: 記錄驗收結果**

供後續程式碼審查與 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 13 狀態更新引用。

---

## 相關佐證

- `design.md`「第三輪真機使用回報」項目 3
- `design.md` 第一輪「決策」#14（`_chromeVisible` 沉浸模式原始設計）
