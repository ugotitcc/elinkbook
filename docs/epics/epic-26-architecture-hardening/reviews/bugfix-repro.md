# Bug 修復重現報告 — Issue 1：流式 EPUB 書籤 toggle 快取未載入誤判無書籤

**日期**：2026-08-13
**方法**：`/diagnose`
**來源**：`docs/research/architecture-review-test-suite-epub-pdf.md` 候選 1（強度 Strong，「現存 bug，非假設性風險」）

## Phase 1-2：feedback loop 與重現

種子：`app/test/screens/reader_screen_test.dart` 既有測試「流式 EPUB：點擊浮動書籤 toggle 按鈕可新增/移除目前頁書籤」（line 3681）已證明的呼叫路徑與測試 seam（`FakeBookmarksRepository`＋`FoliateEpubReaderView.onLocatorChanged`＋`Key('reader_foliate_bookmark_toggle_button')`）。

重現測試（暫時性，診斷確認後已刪除，未保留於測試套件）：

```dart
testWidgets(
  '[DEBUG-e26c1] 流式 EPUB 重新開啟已在目前位置有書籤的書，第一次點擊書籤按鈕不應誤新增重複書籤',
  (tester) async {
    const locatorJson = '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}';
    final bookmarksRepository = FakeBookmarksRepository();
    // 模擬「先前已在此位置加過書籤」：重開書時 repository 已有一筆。
    await bookmarksRepository.insert(Bookmark(
      id: 'existing-bookmark',
      bookId: 'b_repro',
      name: '既有書籤',
      epubLocatorJson: locatorJson,
      progression: 0.1,
    ));

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.epub',
        bookId: 'b_repro',
        prefsManager: prefsManager,
        bookmarksRepository: bookmarksRepository,
        isFixedLayout: false,
      ),
    ));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(const EpubPositionInfo(
      locatorJson: locatorJson,
      progression: 0.1,
      pageIndex: 0,
      totalPages: 10,
    ));
    await tester.pump();

    // 開書流程中從未主動呼叫過 _loadFxlBookmarks()——沒開過
    // NotesBottomSheet，也沒手動 toggle 過一次。
    final finder = find.byKey(const Key('reader_foliate_bookmark_toggle_button'));
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final afterTap = await bookmarksRepository.listByBook('b_repro');
    expect(afterTap, hasLength(0)); // 正確預期：應是「刪除既有書籤」
  },
);
```

**實際執行結果（`flutter test`，2026-08-13）**：

```
Expected: an object with length of <0>
  Actual: [
            Bookmark:Bookmark(id: existing-bookmark, ..., epubLocatorJson: {"cfi":"epubcfi(/6/4)",...
            Bookmark:Bookmark(id: bddce11d-..., ..., name: 10% 處, epubLocatorJson: {"cfi":"epubcfi(/6/4)",...
          ]
   Which: has length of <2>
```

第一次點擊不但沒有刪除既有書籤，反而**新增了一筆重複書籤**（repository 從 1 筆變成 2 筆）——確認重現候選 1 描述的症狀。

## Phase 3：假說（單一假說，已由原始碼交叉核對，非臆測）

**假說**：`_toggleBookmark()`（`reader_screen.dart:736`）的存在性判斷依賴 `_bookmarkAtCurrentPosition` getter（`:714`），該 getter 只讀記憶體快取 `_fxlBookmarks`（初始值 `[]`）、不查 repository。EPUB 開書流程中沒有任何一處會在使用者第一次點擊書籤按鈕**之前**把既有書籤預先載入這個快取——`_loadFxlBookmarks()` 只在下列時機被呼叫：`_toggleBookmark()`／`_togglePdfBookmark()` 自己執行完 insert/delete **之後**（:755、:786）、Notes 面板關閉時但條件限定 `_isFixedLayout || format == pdf`（:1002，**純流式 EPUB 被排除在外**）、以及 PDF 開書流程（:1040，EPUB 沒有對應呼叫）。因此純流式 EPUB 重新開啟後，只要使用者在**尚未打開過 Notes 面板**的情況下第一次點擊書籤按鈕，`_fxlBookmarks` 必然是空陣列，`_bookmarkAtCurrentPosition` 必然回傳 `null`，即使 repository 裡该位置已有書籤也會被誤判為「無書籤」而執行新增，造成重複。

驗證（falsifiable）：若假說成立，把 `_toggleBookmark()` 的判斷邏輯改為比照 `_togglePdfBookmark()` 直接查 `repository.listByBook()`（不依賴 `_fxlBookmarks`），重跑上述測試應變為 PASS。已用程式碼比對確認 `_togglePdfBookmark()`（`:762-787`，epic-24-pdf-engine-rebuild 該工單已明確記錄「直接查詢 repository 而非依賴 _fxlBookmarks 快取，避免快取尚未載入時導致重複新增」）正是同一個 bug 在 PDF 端已修過的版本，EPUB 端從未收到這個修復——與候選 1 文件描述完全一致，只有這一個假說，未發現其他競爭假說。

## Phase 4：不需額外插樁

問題根因已由靜態程式碼交叉比對（`_bookmarkAtCurrentPosition` vs `_pdfBookmarkAtCurrentPosition`／`_toggleBookmark` vs `_togglePdfBookmark`）＋上方測試斷言直接證實，不需要額外 log 插樁。

## 結論與後續

此為真實可重現的正確性缺陷，已轉為 `docs/epics/epic-26-architecture-hardening/issues.md` Issue 1，交由後續 `/plan-issue` 走完整 SDD 流程實作修復（候選 1 建議方案：抽出共用 `BookmarkToggle` module，EPUB／PDF 皆改用直查 repository 版本，一次修復兩邊）。修復時應把上方重現測試轉為永久回歸測試（seam 已驗證可用，非假設性）。
