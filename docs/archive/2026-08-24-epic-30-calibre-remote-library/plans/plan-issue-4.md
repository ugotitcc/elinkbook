# Epic 30 Issue 4：圖書庫整合與快取生命週期 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `isDownloaded == false`（僅雲端紀錄）的書籍在書架上可辨識（雲朵角標），提供「移除本機快取」批次操作（刪除實體檔案、保留書籍紀錄與所有標註資料），並讓點擊「待下載」書籍時觸發確認＋重新下載流程（重用既有 `remoteDownloadUrl`，不重新瀏覽目錄）。

**Architecture:** 三個獨立但循序相依的變更：(1) `Book.copyWith()` 擴充 `filePath`／`isDownloaded` 兩個新具名參數（Issue 0 當時刻意不開放，因為當時沒有呼叫端需要真的異動這兩個欄位；本 Issue 是第一個需要的）＋ `BookCover` 疊加雲朵角標；(2) `LibraryScreen` 既有的批次選取工具列（`_buildSelectionAppBar()`）新增「移除本機快取」，比照既有 `_forceFixedLayoutForSelectedBooks()` 的「一律顯示、迴圈內逐筆過濾不符資格的書籍」既定模式；(3) 點擊「待下載」書籍時攔截原本會開啟 `ReaderScreen` 的路徑，改為確認對話框＋直接呼叫 `OpdsClient.downloadBook()`，複用 Issue 2 已驗證的「暫存目錄→複製到永久 `remote_books/` 目錄→刪除暫存」兩段式落地模式。

**Tech Stack:** Flutter widget、既有 `LibraryRepository`／`RemoteServerRepository`／`OpdsClient` 介面、新增 `connectivity_plus` 依賴（偵測行動數據連線，`epic-29-cloud-import` 的 `design.md`/`spec.md` 也已規劃使用同一套件供其 Issue 6 行動數據下載警示——本 Issue 先落地，`epic-29` 之後可直接沿用，比照 `spec.md`「與 `epic-29-cloud-import` 的順序無關性」既定原則的延伸適用）。

**Spec:** `docs/epics/epic-30-calibre-remote-library/spec.md`（「下載與快取生命週期」小節）、`docs/epics/epic-30-calibre-remote-library/issues.md`（「Issue 4：圖書庫整合與快取生命週期」）。

## Global Constraints

- 移除本機快取後，`filePath` 字串本身、`coverPath`、劃線／書籤／閱讀進度等其餘欄位完全不變——只有實體檔案被刪除、`isDownloaded` 變 `false`。
- 重新下載直接重用該書 `remoteDownloadUrl`（上次下載成功時已存的絕對 URL），**不**透過重新 `fetchFeed()` 反查目錄。若該 URL 失效（例如伺服器回傳 403/404），比照一般下載失敗處理——顯示錯誤訊息，不做自動復原嘗試。
- 下載完成後更新該書 `filePath`／`isDownloaded=true`，**不建立新的 `Book` 記錄**（沿用既有 `id`，透過 `LibraryRepository.updateBook()`）。
- 「移除本機快取」選項僅對 `source == BookSource.calibreOpds` 的書籍生效——本機/雲端硬碟來源的書沒有「重新下載」能力。
- 兩層檢查（重複匯入偵測）與本 Issue 無關，維持 Issue 3 既有行為不變。

---

## Task 1：`Book.copyWith()` 擴充 `filePath`／`isDownloaded` ＋ `BookCover` 雲朵角標

**Files:**
- Modify: `app/lib/library/models/book.dart:185-215`
- Modify: `app/lib/library/widgets/book_cover.dart`
- Test: `app/test/library/models/book_test.dart`
- Test: `app/test/library/widgets/book_cover_test.dart`（新建）

**Interfaces:**
- Produces：`Book.copyWith({String? groupName, bool? isFixedLayout, String? filePath, bool? isDownloaded})`——新增的兩個具名參數供 Task 2（`isDownloaded: false`）與 Task 3（`filePath: ..., isDownloaded: true`）使用。`BookCover` 對外建構參數不變（仍只有 `book`），內部依 `book.isDownloaded` 疊加角標。

- [ ] **Step 1: 寫失敗測試（`Book.copyWith()`）**

在 `app/test/library/models/book_test.dart` 檔案結尾（`copyWith 保留 contentFingerprint／...` 測試之後，`}` 之前）新增：

```dart
  test('copyWith(isDownloaded: false) 只改變 isDownloaded，filePath 等其餘欄位保持不變', () {
    final book = Book(
      id: 'b18',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: '/storage/remote_books/b18.epub',
      source: BookSource.calibreOpds,
      remoteServerId: 'srv1',
      remoteBookId: 'remote-18',
      remoteDownloadUrl: 'http://example.com/download/18.epub',
      isDownloaded: true,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final removed = book.copyWith(isDownloaded: false);

    expect(removed.isDownloaded, isFalse);
    expect(removed.filePath, '/storage/remote_books/b18.epub');
    expect(removed.remoteServerId, 'srv1');
    expect(removed.remoteBookId, 'remote-18');
    expect(removed.remoteDownloadUrl, 'http://example.com/download/18.epub');
  });

  test('copyWith(filePath: ..., isDownloaded: true) 同時更新兩個欄位，remoteDownloadUrl 等其餘欄位保持不變',
      () {
    final book = Book(
      id: 'b19',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: '/storage/remote_books/b19.epub',
      source: BookSource.calibreOpds,
      remoteServerId: 'srv1',
      remoteBookId: 'remote-19',
      remoteDownloadUrl: 'http://example.com/download/19.epub',
      isDownloaded: false,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final redownloaded = book.copyWith(
      filePath: '/storage/remote_books/b19-new.epub',
      isDownloaded: true,
    );

    expect(redownloaded.filePath, '/storage/remote_books/b19-new.epub');
    expect(redownloaded.isDownloaded, isTrue);
    expect(redownloaded.remoteDownloadUrl, 'http://example.com/download/19.epub');
    expect(redownloaded.remoteServerId, 'srv1');
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/library/models/book_test.dart`
Expected: FAIL——`copyWith()` 沒有 `filePath`／`isDownloaded` 具名參數（編譯錯誤）。

- [ ] **Step 3: 修改 `Book.copyWith()`**

修改 `app/lib/library/models/book.dart` 第 185-215 行（`copyWith()` 方法本體與其文件註解）：

```dart
  /// 回傳欄位值與自身相同的新物件，僅覆寫明確傳入的參數。[groupName] 供
  /// Issue 10 的批次分類異動使用；[isFixedLayout] 供本 Issue 的 EPUB 版面
  /// 判斷/回填流程使用；[filePath]／[isDownloaded] 供
  /// epic-30-calibre-remote-library Issue 4 的「移除本機快取」（僅傳
  /// `isDownloaded: false`）／「重新下載」（`filePath` 與
  /// `isDownloaded: true` 一併傳入）使用——Issue 0 當時刻意不開放這兩個
  /// 欄位為具名參數（YAGNI，當時沒有呼叫端需要真的異動它們），本 Issue
  /// 是第一個需要的呼叫端。
  /// **⚠️ `remoteServerId`／`remoteBookId`／`remoteDownloadUrl` 仍不開放
  /// 為具名參數（本 Issue的兩個流程皆不需要異動這三者），但必須原樣帶入
  /// 新物件以避免靜默清空**。
  Book copyWith({
    String? groupName,
    bool? isFixedLayout,
    String? filePath,
    bool? isDownloaded,
  }) {
    return Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: filePath ?? this.filePath,
      source: source,
      coverPath: coverPath,
      progress: progress,
      epubLocator: epubLocator,
      pdfPageIndex: pdfPageIndex,
      totalCharacterCount: totalCharacterCount,
      contentFingerprint: contentFingerprint,
      positionUpdatedAt: positionUpdatedAt,
      positionSyncedServerUpdatedAt: positionSyncedServerUpdatedAt,
      remoteServerId: remoteServerId,
      remoteBookId: remoteBookId,
      remoteDownloadUrl: remoteDownloadUrl,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      isFixedLayout: isFixedLayout ?? this.isFixedLayout,
      groupName: groupName ?? this.groupName,
      createTime: createTime,
      lastReadTime: lastReadTime,
    );
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/library/models/book_test.dart`
Expected: PASS，全部測試（含既有測試＋本 Task 新增的 2 項）通過。

- [ ] **Step 5: 寫失敗測試（`BookCover` 雲朵角標）**

新建 `app/test/library/widgets/book_cover_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/widgets/book_cover.dart';

Book _book({required bool isDownloaded}) {
  return Book(
    id: 'b1',
    title: '測試書',
    format: BookFileFormat.epub,
    filePath: '/books/b1.epub',
    source: BookSource.calibreOpds,
    isDownloaded: isDownloaded,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  testWidgets('isDownloaded 為 false 時疊加雲朵角標', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BookCover(book: _book(isDownloaded: false)),
    ));

    expect(find.byKey(const Key('book_cover_cloud_badge')), findsOneWidget);
  });

  testWidgets('isDownloaded 為 true 時不顯示雲朵角標', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BookCover(book: _book(isDownloaded: true)),
    ));

    expect(find.byKey(const Key('book_cover_cloud_badge')), findsNothing);
  });
}
```

- [ ] **Step 6: 執行測試確認失敗**

Run: `flutter test test/library/widgets/book_cover_test.dart`
Expected: FAIL——找不到 `Key('book_cover_cloud_badge')`。

- [ ] **Step 7: 修改 `BookCover`**

修改 `app/lib/library/widgets/book_cover.dart`，把 `build()` 方法改為疊加角標：

```dart
  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    final cover = coverPath != null && File(coverPath).existsSync()
        ? Image.file(File(coverPath), fit: BoxFit.cover)
        : ColoredBox(
            color: Colors.grey.shade300,
            child: Center(child: Icon(bookFormatIcon(book.format), size: 32)),
          );
    if (book.isDownloaded) return cover;
    return Stack(
      fit: StackFit.expand,
      children: [
        cover,
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            key: const Key('book_cover_cloud_badge'),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cloud_outlined, size: 16, color: Colors.white),
          ),
        ),
      ],
    );
  }
```

- [ ] **Step 8: 執行測試確認通過**

Run: `flutter test test/library/widgets/book_cover_test.dart`
Expected: PASS，2 項測試皆通過。

- [ ] **Step 9: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨；`flutter test` 全數通過，零回歸。

- [ ] **Step 10: Commit**

```bash
git add app/lib/library/models/book.dart app/lib/library/widgets/book_cover.dart app/test/library/models/book_test.dart app/test/library/widgets/book_cover_test.dart
git commit -m "feat(epic-30): Issue 4 Task 1 - Book.copyWith 擴充 filePath/isDownloaded 與 BookCover 雲朵角標"
```

---

## Task 2：「移除本機快取」批次操作

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `Book.copyWith(isDownloaded: false)`。
- Produces：`_LibraryScreenState._removeLocalCacheForSelectedBooks()`（無回傳值，內部呼叫 `widget.repository.updateBook()`），新增 AppBar 按鈕 `Key('library_remove_local_cache_button')`。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/screens/library_screen_test.dart` 找一個既有的批次操作測試（例如「強制 FXL」相關測試）附近，新增以下測試（沿用該處已有的 `Book`/`FakeLibraryRepository`／`FakeBookmarksRepository`／`FakeHighlightsRepository` 建構慣例，若這些 Fake 尚未在檔案頂部 import，補上對應 import）：

```dart
  testWidgets('選取 Calibre 來源已下載書籍後點擊「移除本機快取」，刪除實體檔案、isDownloaded 變 false，劃線/書籤/進度不受影響',
      (tester) async {
    // 〔比照 library_screen.dart _deleteSelectedBooks() 既有註解說明〕
    // widget test 的 fake zone 無法完成真實 I/O 的 Future，一律使用
    // *Sync() 系列同步呼叫，不需要 tester.runAsync()。
    final tempDir = Directory.systemTemp.createTempSync('library_remove_cache_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final bookFile = File('${tempDir.path}/remote_book.epub')..writeAsStringSync('dummy');

    final book = Book(
      id: 'b1',
      title: '遠端書',
      format: BookFileFormat.epub,
      filePath: bookFile.path,
      source: BookSource.calibreOpds,
      remoteServerId: 'srv1',
      remoteBookId: 'remote-1',
      remoteDownloadUrl: 'http://example.com/download/1.epub',
      isDownloaded: true,
      epubLocator: 'locator-json',
      progress: 0.5,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);
    final bookmarksRepository = FakeBookmarksRepository();
    await bookmarksRepository.insert(
      const Bookmark(id: 'bm1', bookId: 'b1', name: '第一章'),
    );

    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
        bookmarksRepository: bookmarksRepository,
      ),
    ));
    await tester.pumpAndSettle();

    // 長按（_onBookLongPress → _enterSelectionMode）已經把這本書放進
    // _selectedBookIds（見 library_screen.dart:295-297），不需要再多點一次
    // ——選取模式下再點一次同一本書會呼叫 _toggleBookSelection() 把它
    // 取消選取，反而導致 count == 0、下方按鈕被停用。
    await tester.longPress(find.byKey(const Key('book_item_b1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_remove_local_cache_button')));
    await tester.pumpAndSettle();

    final updated = (await repository.listBooks()).single;
    expect(updated.isDownloaded, isFalse);
    expect(updated.filePath, bookFile.path);
    expect(bookFile.existsSync(), isFalse);
    expect(updated.epubLocator, 'locator-json');
    expect(updated.progress, 0.5);
    expect(await bookmarksRepository.listByBook('b1'), hasLength(1));
  });

  testWidgets('選取非 Calibre 來源（本機匯入）書籍時，點擊「移除本機快取」不影響該書', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('library_remove_cache_local_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final bookFile = File('${tempDir.path}/local_book.epub')..writeAsStringSync('dummy');

    final book = Book(
      id: 'b2',
      title: '本機書',
      format: BookFileFormat.epub,
      filePath: bookFile.path,
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_b2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_remove_local_cache_button')));
    await tester.pumpAndSettle();

    final unchanged = (await repository.listBooks()).single;
    expect(unchanged.isDownloaded, isTrue);
    expect(bookFile.existsSync(), isTrue);
  });
```

`app/test/screens/library_screen_test.dart` 開頭需新增 import（若尚未存在）：

```dart
import 'package:elinkbook/reader/bookmark.dart';

import '../support/fake_bookmarks_repository.dart';
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: FAIL——找不到 `Key('library_remove_local_cache_button')`。

- [ ] **Step 3: 修改 `LibraryScreen`**

修改 `app/lib/screens/library_screen.dart`，在 `_deleteSelectedBooks()`（第 414-457 行）之後新增新方法：

```dart
  /// 「移除本機快取」批次操作（epic-30-calibre-remote-library Issue 4，
  /// spec.md「下載與快取生命週期」）：僅對 `source ==
  /// BookSource.calibreOpds` 且 `isDownloaded == true` 的已選書籍生效，
  /// 其餘（本機/雲端硬碟來源、或已經是待下載狀態）靜默略過——比照既有
  /// `_forceFixedLayoutForSelectedBooks()`／`_restoreAutoLayoutForSelectedBooks()`
  /// 的「按鈕一律顯示、迴圈內逐筆過濾不符資格書籍」既定模式，不額外隱藏
  /// 按鈕本身。刪除實體檔案後只更新 `isDownloaded`，`filePath` 字串本身、
  /// `coverPath`、劃線／書籤／閱讀進度等其餘欄位完全不變——不是「刪除
  /// 這本書」，是「這本書的本機檔案暫時不在了」。不跳確認對話框：這個
  /// 動作可逆（重新下載，見 Task 3），與 `_deleteSelectedBooks()` 那種
  /// 不可逆刪除（含連帶刪除劃線/書籤/備註）性質不同。
  Future<void> _removeLocalCacheForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.source != BookSource.calibreOpds || !book.isDownloaded) continue;
      try {
        if (File(book.filePath).existsSync()) {
          File(book.filePath).deleteSync();
        }
      } catch (_) {
        // 檔案刪除失敗時仍繼續更新資料庫狀態（比照 _deleteSelectedBooks()
        // 既有慣例）——使用者最關心的「書架上標示為待下載」已能達成，
        // 殘留的實體檔案不影響功能正確性。
      }
      await widget.repository.updateBook(book.copyWith(isDownloaded: false));
    }
    await _loadBooks();
  }
```

修改 `_buildSelectionAppBar()`（第 717-755 行），在「刪除」按鈕之前新增一個按鈕：

```dart
        IconButton(
          key: const Key('library_remove_local_cache_button'),
          icon: const Icon(Icons.cloud_off_outlined),
          tooltip: '移除本機快取',
          onPressed: count == 0 ? null : _removeLocalCacheForSelectedBooks,
        ),
        IconButton(
          key: const Key('library_delete_books_button'),
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASS，全部測試（含既有測試＋本 Task 新增的 2 項）通過。

- [ ] **Step 5: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨；`flutter test` 全數通過，零回歸。

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-30): Issue 4 Task 2 - 移除本機快取批次操作"
```

---

## Task 3：「待下載」書籍點擊重新下載流程

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/remote/opds_client.dart`
- Modify: `app/lib/screens/remote_catalog_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `Book.copyWith(filePath: ..., isDownloaded: true)`；既有 `OpdsClient.downloadBook()`／`RemoteServerRepository.listServers()`／`loadPassword()`。
- Produces：`opds_client.dart` 新增共用函式 `String fileExtensionFor(BookFileFormat format)`；`LibraryScreen` 新增可選建構參數 `Future<bool> Function()? isMobileDataConnection`；`main.dart` 提供生產環境預設值（`connectivity_plus`）。

**背景（行動數據偵測依賴選型）**：`spec.md`「重新下載」要求「偵測目前是否為行動數據連線，是則額外強調流量提示」，`docs/epics/epic-29-cloud-import` 的 `spec.md` 已規劃為其 Issue 6 的同類需求引入 `connectivity_plus` 套件（尚未實際加入 `pubspec.yaml`，`epic-29` 目前仍是文件階段）——本 Issue 是兩個 Epic 中先落地此依賴的一方，比照 `epic-30` 自身 `spec.md`「順序無關性」小節對 `findByContentFingerprint()` 等既有共用觸點的處理原則：先落地的一方新增，之後 `epic-29` 落地時檢查依賴是否已存在、直接沿用即可。

- [ ] **Step 1: 新增 `connectivity_plus` 依賴**

```bash
cd app
flutter pub add connectivity_plus
```

Expected：`pubspec.yaml` 的 `dependencies:` 區塊新增一行 `connectivity_plus: ^<pub 解析出的版本>`，`pubspec.lock` 同步更新。執行 `flutter pub get` 確認無版本衝突（`connectivity_plus` 不依賴 Google Play Services，NFR-6 的無 GMS 裝置相容性不受影響）。

- [ ] **Step 2: 抽出共用的 `fileExtensionFor()`，供 Task 3 與既有 `RemoteCatalogScreen` 共用**

修改 `app/lib/remote/opds_client.dart`，開頭新增 import：

```dart
import '../library/models/library_enums.dart';
```

在 `buildOpdsAuthHeaders()` 函式之後新增：

```dart
/// [BookFileFormat] 對應的檔案副檔名（不含句點），供下載暫存檔命名使用
/// （epic-30-calibre-remote-library Issue 2 的 `RemoteCatalogScreen`
/// 下載佇列，以及 Issue 4 的「重新下載」流程共用同一份對應表，避免各自
/// 重寫一次 switch）。
String fileExtensionFor(BookFileFormat format) {
  switch (format) {
    case BookFileFormat.epub:
      return 'epub';
    case BookFileFormat.pdf:
      return 'pdf';
    case BookFileFormat.txt:
      return 'txt';
    case BookFileFormat.azw3:
      return 'azw3';
    case BookFileFormat.cbz:
      return 'cbz';
    case BookFileFormat.md:
      return 'md';
  }
}
```

修改 `app/lib/screens/remote_catalog_screen.dart`：刪除 `_DownloadQueueDialogState` 內的私有 `_extensionFor()` 方法（原本的 `switch` 本體，第 410-425 行附近），並把 `_downloadOne()` 內唯一的呼叫點 `_extensionFor(item.acquisition.format!)` 改為 `fileExtensionFor(item.acquisition.format!)`（此函式已由 `opds_client.dart` 匯入，該檔案開頭已 `import '../remote/opds_client.dart';`，不需要新增 import）。

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: PASS，全數通過（純重構，行為不變）。

- [ ] **Step 3: 寫失敗測試（重新下載流程）**

在 `app/test/screens/library_screen_test.dart` 開頭新增 import（若尚未存在）：

```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/remote/opds_types.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';

import '../support/fake_opds_client.dart';
import '../support/fake_path_provider_platform.dart';
import '../support/fake_remote_server_repository.dart';
```

在檔案結尾（`}` 之前）新增一個新的 `group`：

```dart
group('Issue 4：待下載書籍重新下載', () {
    late Directory tempRoot;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('library_redownload_test');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = FakePathProviderPlatform(tempRoot.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    final server = RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    Book pendingBook() => Book(
          id: 'b1',
          title: '待下載的書',
          format: BookFileFormat.epub,
          filePath: '/no/longer/exists.epub',
          source: BookSource.calibreOpds,
          remoteServerId: 'srv1',
          remoteBookId: 'remote-1',
          remoteDownloadUrl: 'http://192.168.1.100:8080/opds/download/1.epub',
          isDownloaded: false,
          createTime: DateTime.fromMillisecondsSinceEpoch(1000),
          lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
        );

    testWidgets('點擊待下載書籍先跳出確認對話框，取消則不觸發下載', (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      final opdsClient = FakeOpdsClient();
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
          createOpdsClient: () => opdsClient,
          isMobileDataConnection: () async => false,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('library_redownload_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('library_redownload_cancel_button')));
      await tester.pumpAndSettle();

      expect(opdsClient.downloadBookCalls, isEmpty);
    });

    testWidgets('偵測到行動數據連線時，確認對話框額外顯示流量提示文字', (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
          createOpdsClient: () => FakeOpdsClient(),
          isMobileDataConnection: () async => true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('行動數據'), findsOneWidget);
    });

    testWidgets('確認後成功重新下載，更新 filePath/isDownloaded，不建立新的 Book 記錄', (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      final opdsClient = FakeOpdsClient();
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
          createOpdsClient: () => opdsClient,
          isMobileDataConnection: () async => false,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_redownload_confirm_button')));
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      final books = await repository.listBooks();
      expect(books, hasLength(1));
      expect(books.single.id, 'b1');
      expect(books.single.isDownloaded, isTrue);
      expect(books.single.filePath, isNot('/no/longer/exists.epub'));
      expect(File(books.single.filePath).existsSync(), isTrue);
      expect(opdsClient.downloadBookCalls, ['http://192.168.1.100:8080/opds/download/1.epub']);
    });

    testWidgets('下載失敗時顯示錯誤訊息，書籍狀態不變', (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      final opdsClient = FakeOpdsClient(downloadError: StateError('模擬下載失敗'));
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
          createOpdsClient: () => opdsClient,
          isMobileDataConnection: () async => false,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_redownload_confirm_button')));
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('重新下載失敗，請稍後再試'), findsOneWidget);
      final books = await repository.listBooks();
      expect(books.single.isDownloaded, isFalse);
      expect(books.single.filePath, '/no/longer/exists.epub');
    });
  });
```

- [ ] **Step 4: 執行測試確認失敗**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: FAIL——`LibraryScreen` 沒有 `isMobileDataConnection` 具名參數（編譯錯誤）；`connectivity_plus` import 若未安裝會找不到套件（Step 1 應已完成，此處不應再失敗於此）。

- [ ] **Step 5: 修改 `LibraryScreen`**

修改 `app/lib/screens/library_screen.dart` 開頭 import 區塊，新增：

```dart
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../remote/opds_types.dart';
import '../remote/remote_server_profile.dart';
```

（`dart:io` 已存在，不需重複新增。）

修改 `LibraryScreen` 類別欄位與建構子，於 `createOpdsClient` 之後新增：

```dart
  final OpdsClient Function()? createOpdsClient;
  final Future<bool> Function()? isMobileDataConnection;
```

```dart
    this.createOpdsClient,
    this.isMobileDataConnection,
```

修改 `_LibraryScreenState`，新增重入防護欄位（緊接在 `_isImporting` 之後）：

```dart
  bool _isImporting = false;
  // 〔比照 epic-30 Issue 3 review-issue-3.md 既定的重入防護模式〕避免
  // 使用者在重新下載進行中又快速連點同一本「待下載」書籍，重複觸發兩次
  // 下載/確認流程。
  final Set<String> _redownloadingBookIds = {};
```

修改 `_onBookTap()`（第 315-321 行）：

```dart
  void _onBookTap(Book book) {
    if (_inSelectionMode) {
      _toggleBookSelection(book.id);
    } else if (!book.isDownloaded) {
      _handleRedownload(book);
    } else {
      _openBook(book);
    }
  }
```

在 `_openBook()` 方法之後新增：

```dart
  Future<bool?> _confirmRedownload(Book book, bool isMobileData) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('library_redownload_dialog'),
        title: const Text('重新下載'),
        content: Text(
          isMobileData
              ? '即將重新下載「${book.title}」，目前使用行動數據連線，可能產生流量費用，確定要繼續嗎？'
              : '即將重新下載「${book.title}」，確定要繼續嗎？',
        ),
        actions: [
          TextButton(
            key: const Key('library_redownload_cancel_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('library_redownload_confirm_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('重新下載'),
          ),
        ],
      ),
    );
  }

  /// 「待下載」書籍點擊重新下載（epic-30-calibre-remote-library Issue 4，
  /// spec.md「下載與快取生命週期」「重新下載」）：直接重用該書
  /// [Book.remoteDownloadUrl]（上次下載成功時已存的絕對 URL），不重新
  /// `fetchFeed()` 反查目錄——OPDS 協議不保證支援依 ID 反查單一條目。
  /// 下載暫存/永久落地兩段式流程比照 Issue 2 `RemoteCatalogScreen`
  /// `_DownloadQueueDialogState._downloadOne()` 既有模式（暫存目錄→複製
  /// 到永久 `remote_books/` 目錄→刪除暫存），避免把永久 `filePath` 指向
  /// OS 可回收的暫存路徑。
  Future<void> _handleRedownload(Book book) async {
    final remoteServerRepository = widget.remoteServerRepository;
    final createOpdsClient = widget.createOpdsClient;
    final remoteServerId = book.remoteServerId;
    final remoteDownloadUrl = book.remoteDownloadUrl;
    if (remoteServerRepository == null ||
        createOpdsClient == null ||
        remoteServerId == null ||
        remoteDownloadUrl == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('遠端書庫功能未啟用，無法重新下載')));
      return;
    }
    if (_redownloadingBookIds.contains(book.id)) return;

    final isMobileData = await (widget.isMobileDataConnection?.call() ?? Future.value(false));
    if (!mounted) return;
    final confirmed = await _confirmRedownload(book, isMobileData);
    if (confirmed != true) return;

    _redownloadingBookIds.add(book.id);
    // 〔審查 review-plan-issue-4.md Minor 採納〕宣告在 try 外，讓 catch
    // 區塊也能存取，用於下方「copy 到永久目錄中途失敗」時的暫存檔清理
    // ——比照 Issue 2 `_DownloadQueueDialogState._downloadOne()` 既有的
    // 同一防禦手法（`review-plan-issue-2.md` Finding 3）。
    String? tempPath;
    try {
      final servers = await remoteServerRepository.listServers();
      RemoteServerProfile? server;
      for (final s in servers) {
        if (s.id == remoteServerId) {
          server = s;
          break;
        }
      }
      if (server == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('找不到對應的遠端書庫站點')));
        return;
      }
      final password = await remoteServerRepository.loadPassword(remoteServerId);
      final client = createOpdsClient();

      final tempDir = await getTemporaryDirectory();
      final downloadDir = Directory(p.join(tempDir.path, 'remote_download_temp'));
      if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
      final fileName = '${const Uuid().v4()}.${fileExtensionFor(book.format)}';
      tempPath = p.join(downloadDir.path, fileName);

      await client.downloadBook(
        server,
        OpdsAcquisition(href: remoteDownloadUrl, format: book.format),
        tempPath,
        password: password,
      );

      final docsDir = await getApplicationDocumentsDirectory();
      final permanentDir = Directory(p.join(docsDir.path, 'remote_books'));
      if (!await permanentDir.exists()) await permanentDir.create(recursive: true);
      final permanentPath = p.join(permanentDir.path, fileName);
      final tempFile = File(tempPath);
      await tempFile.copy(permanentPath);
      await tempFile.delete();

      await widget.repository
          .updateBook(book.copyWith(filePath: permanentPath, isDownloaded: true));
      if (!mounted) return;
      await _loadBooks();
    } catch (_) {
      // 〔審查 review-plan-issue-4.md Minor 採納〕downloadBook() 本身
      // 失敗/取消時已經自行清過暫存檔（見 OpdsHttpClient 文件），但
      // copy() 到永久目錄這一步若中途失敗（例如磁碟空間不足），暫存檔
      // 仍會殘留在 remote_download_temp/ 底下——防禦性再清一次，確保
      // 任何例外路徑都不留孤兒檔案。
      if (tempPath != null) {
        final leftover = File(tempPath);
        if (await leftover.exists()) await leftover.delete();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('重新下載失敗，請稍後再試')));
    } finally {
      _redownloadingBookIds.remove(book.id);
    }
  }
```

- [ ] **Step 6: 執行測試確認通過**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASS，全部測試（含既有測試＋本 Task 新增的 4 項）通過。

- [ ] **Step 7: 接線 `main.dart`（生產環境 `connectivity_plus` 實作）**

修改 `app/lib/main.dart` 開頭 import 區塊，新增：

```dart
import 'package:connectivity_plus/connectivity_plus.dart';
```

在 `main()` 函式之前新增頂層函式：

```dart
/// [LibraryScreen.isMobileDataConnection] 生產環境實作
/// （epic-30-calibre-remote-library Issue 4）：`connectivity_plus` 6.x
/// 起 `checkConnectivity()` 回傳 `List<ConnectivityResult>`（支援同時
/// 存在多種連線，例如 VPN 疊加 Wi-Fi），只要清單內含
/// [ConnectivityResult.mobile] 即視為「目前為行動數據連線」，即使同時
/// 也有 Wi-Fi——寧可誤判為需要提示，也不要漏掉真正的行動數據情境。
Future<bool> _isMobileDataConnection() async {
  final results = await Connectivity().checkConnectivity();
  return results.contains(ConnectivityResult.mobile);
}
```

在 `ElinkBookApp` 類別（欄位與建構子，緊接在 `createOpdsClient` 之後）新增：

```dart
  final OpdsClient Function()? createOpdsClient;
  final Future<bool> Function()? isMobileDataConnection;
```

```dart
    this.createOpdsClient,
    this.isMobileDataConnection,
```

在 `_ElinkBookAppState.build()` 中建構 `LibraryScreen` 處，找到既有的這兩行（不動）：

```dart
        remoteServerRepository: widget.remoteServerRepository,
        createOpdsClient: widget.createOpdsClient,
```

在其後新增一行：

```dart
        remoteServerRepository: widget.remoteServerRepository,
        createOpdsClient: widget.createOpdsClient,
        isMobileDataConnection: widget.isMobileDataConnection,
```

在 `main()` 函式建構 `ElinkBookApp(...)` 處，於 `createOpdsClient: () => OpdsHttpClient(),` 之後新增：

```dart
      createOpdsClient: () => OpdsHttpClient(),
      isMobileDataConnection: _isMobileDataConnection,
```

- [ ] **Step 8: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨；`flutter test` 全數通過，零回歸。

- [ ] **Step 9: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/remote/opds_client.dart app/lib/screens/remote_catalog_screen.dart app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-30): Issue 4 Task 3 - 待下載書籍點擊重新下載流程"
```

---

## Self-Review（撰寫計畫時的自我檢查）

**Spec 涵蓋度**：`spec.md`「下載與快取生命週期」3 個條列點——(1) 移除本機快取→Task 2；(2) 待下載狀態呈現（雲朵角標）→Task 1；(3) 重新下載（含行動數據警示、重用 `remoteDownloadUrl`、不建立新 Book 記錄、失敗處理）→Task 3。「站點刪除防護」該小節第 4 點明確指向「見上方站點管理小節」，屬於 Issue 1 既有範圍，本 Issue 不重複處理。`issues.md` Issue 4 的單元測試要求（移除快取後 isDownloaded/實體檔案/劃線書籤進度、僅 Calibre 來源顯示、確認對話框顯示與取消、行動數據情境提示、下載成功/失敗）全數對應到 Task 2/3 的測試。

**型別一致性**：`fileExtensionFor(BookFileFormat)` 在 Task 3 Step 2 定義後，`remote_catalog_screen.dart`（既有呼叫點改用）與 Task 3 Step 5（`_handleRedownload` 新呼叫點）簽章一致。`isMobileDataConnection` 型別 `Future<bool> Function()?` 在 `LibraryScreen`／`ElinkBookApp`／`main.dart` 三處一致。`Book.copyWith()` 新參數 `filePath`／`isDownloaded` 命名與既有欄位名稱一致，Task 2／Task 3 呼叫處用法一致（Task 2 只傳 `isDownloaded`，Task 3 兩者皆傳）。

**佔位符掃描**：全文無 TBD／implement later／"add appropriate error handling" 等字樣；所有程式碼步驟皆附完整可執行程式碼。Task 2 Step 1 提到「若 `FakeBookmarksRepository` 沒有 `seed()` 方法，改用建構子 `initialBookmarks`」——這不是逃避具體實作，而是因為該 Fake 檔案的確切既有 API 需要實作者開工時當場核對（兩個選項皆已明確給出，不是模糊描述）。
