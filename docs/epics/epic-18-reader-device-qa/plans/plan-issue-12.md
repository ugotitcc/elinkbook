# Issue 12：進度/跳頁浮動按鈕移除 `showFooter` 額外限制 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 讓流式 EPUB 的「進度/跳頁」浮動按鈕（`reader_foliate_progress_button`）比照其餘 5 顆浮動功能按鈕，只依 `_chromeVisible`（沉浸模式）決定顯示/隱藏，移除目前額外要求 `showFooter` 為 `true` 才顯示的限制。

**架構：** 移除 `reader_screen.dart` 中該按鈕 `Positioned` 顯示條件裡的 `(_resolved?.showFooter ?? true)` 子句，其餘邏輯（含按鈕本身的 `onPressed`／圖示／位置）完全不變。

**Tech Stack：** Flutter/Dart，`flutter_test` widget test（純 Dart，不需裝置）。

## Global Constraints

- 本 Issue **推翻** Issue 7 計畫階段的原始設計（「看不到進度就不該讓使用者以為能跳頁」的一致性考量）——這是使用者實際使用後明確要求的方向調整，已於 `design.md`「第三輪真機使用回報」記錄決策，不需要在實作階段重新確認。
- 只調整 `reader_foliate_progress_button` 這一顆按鈕的顯示條件，`reader_foliate_progress_text`（進度**文字**）的顯示條件維持不變（仍然受 `showFooter` 控制）——本 Issue 只處理「功能按鈕」，不處理「資訊顯示」（資訊顯示的沉浸模式脫鉤留待 Issue 13 處理）。
- 真機驗收裝置固定為 `3CEF42ECD491687`。

---

## 檔案結構

本計劃只修改單一檔案：

- **修改：** `app/lib/screens/reader_screen.dart`（`reader_foliate_progress_button` 的 `Positioned` 區塊，約第 1618-1636 行）

---

### Task 1：移除 `showFooter` 限制

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1618-1636`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: 既有 `_resolved`（`ResolvedPreferences?`）、`_chromeVisible`（`bool`）、`_dispatchedIsFixedLayout`（`bool?`）、`_openFoliateProgressSheet()`（既有方法，不修改簽章）。
- Produces: 無新的對外可呼叫函式，純顯示條件調整。

- [ ] **Step 1: 確認現況**

執行：
```bash
grep -n "reader_foliate_progress_button" -B 5 app/lib/screens/reader_screen.dart
```

預期看到（約第 1618-1636 行）：
```dart
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _chromeVisible &&
                (_resolved?.showFooter ?? true))
              Positioned(
                top: 240,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_progress_button'),
                      icon: const Icon(Icons.swap_vert, color: Colors.white),
                      tooltip: '跳頁',
                      onPressed: _openFoliateProgressSheet,
                    ),
                  ),
                ),
              ),
```

- [ ] **Step 2: 修改既有測試，確認新斷言先失敗**

在 `app/test/screens/reader_screen_test.dart` 找到既有測試「流式 EPUB：`showFooter=false` 時進度文字與進度/跳頁按鈕皆不顯示（Issue 7）」（`grep -n "showFooter=false 時進度文字與進度/跳頁按鈕皆不顯示" app/test/screens/reader_screen_test.dart` 確認行號），把測試標題與內容改為：

```dart
  testWidgets(
    '流式 EPUB：showFooter=false 時進度文字不顯示，但進度/跳頁按鈕仍顯示且可點擊（Issue 12）',
    (tester) async {
      await prefsManager.saveBookPrefs(
        'b_foliate_progress_off',
        const BookReaderPrefs(showFooter: false),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_progress_off',
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
          pageIndex: 0,
          totalPages: 10,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('reader_foliate_progress_text')),
        findsNothing,
        reason: 'showFooter=false 時進度文字（資訊顯示）仍不應顯示',
      );

      final buttonFinder = find.byKey(
        const Key('reader_foliate_progress_button'),
      );
      expect(
        buttonFinder,
        findsOneWidget,
        reason: '進度/跳頁按鈕（功能操作）不應被 showFooter 額外限制',
      );

      await tester.tap(buttonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const Key('reader_footer_jump_slider')),
        findsOneWidget,
        reason: '點擊按鈕仍可正常開啟跳頁 Bottom Sheet',
      );
    },
  );
```

- [ ] **Step 3: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/screens/reader_screen_test.dart --plain-name "showFooter=false 時進度文字不顯示，但進度/跳頁按鈕仍顯示且可點擊"
```
預期：FAIL——`buttonFinder` 為 `findsNothing`（目前 `showFooter: false` 會讓按鈕整個不顯示）。

- [ ] **Step 4: 實作修正**

修改 `reader_screen.dart:1618-1636`，移除 `(_resolved?.showFooter ?? true)` 這一項：

```dart
            if (format == BookFormat.epub &&
                _dispatchedIsFixedLayout == false &&
                _chromeVisible)
              Positioned(
                top: 240,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_progress_button'),
                      icon: const Icon(Icons.swap_vert, color: Colors.white),
                      tooltip: '跳頁',
                      onPressed: _openFoliateProgressSheet,
                    ),
                  ),
                ),
              ),
```

- [ ] **Step 5: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/screens/reader_screen_test.dart --plain-name "showFooter=false 時進度文字不顯示，但進度/跳頁按鈕仍顯示且可點擊"
```
預期：PASS。

- [ ] **Step 6: 執行全部既有測試回歸**

執行：
```bash
cd app && flutter analyze
cd app && flutter test
```
預期：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過。

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-18): Issue 12 進度/跳頁按鈕移除 showFooter 額外限制"
```

---

### Task 2：真機驗收

**Files:** 無程式碼異動（純真機人工驗證）。

**Interfaces:**
- Consumes: Task 1 完成後的 `reader_screen.dart`。
- Produces: 驗收結果記錄（供合併前的程式碼審查／`issues.md` Issue 12 狀態更新引用）。

- [ ] **Step 1: 安裝最新 debug APK 至真機 `3CEF42ECD491687`**

```bash
cd app && flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: 驗證按鈕顯示條件**

1. 開啟一本流式 EPUB，於「版面設定」關閉「顯示進度」（`showFooter`）。
2. 確認進度/跳頁浮動按鈕仍與其餘 5 顆按鈕一起顯示（不再因 `showFooter` 關閉而消失）。
3. 點擊該按鈕，確認仍可正常開啟跳頁 Bottom Sheet。
4. 切換沉浸模式（點擊選單熱區）收起選單，確認該按鈕跟其餘 5 顆按鈕一起收合。
5. 記錄：Pass/Fail + 截圖佐證。

- [ ] **Step 3: 記錄驗收結果**

供後續程式碼審查與 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 12 狀態更新引用。

---

## 相關佐證

- `design.md`「第三輪真機使用回報」項目 2
- `issues.md` Issue 7（本 Issue 修正的原始設計決策出處）
