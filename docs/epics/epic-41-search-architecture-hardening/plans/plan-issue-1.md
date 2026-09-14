# Epic 41 Issue 1：收斂 ReaderScreen 組裝為一個工廠函式（`buildReaderScreen()`）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `buildReaderScreen()` 工廠函式，取代 `library_screen.dart`／`library_search_screen.dart`／`book_search_screen.dart` 三處各自手抄約 20 個具名參數建構 `ReaderScreen` 的重複程式碼，`ReaderScreen` 對外介面與既有行為完全不變。

**Architecture:** 新增純函式模組 `app/lib/screens/reader_screen_route.dart`，接收已存在的 `LibraryReaderFeatureRepositories`／`LibrarySyncDependencies` 兩個 bundle（`epic-26-architecture-hardening` Issue 7 產物）＋少量個別欄位，展開後回傳一個具體型別 `ReaderScreen` 實例（不是抽象 `Widget`，維持強型別測試能力）；三個呼叫點的 `MaterialPageRoute(builder: ...)` 這層維持不動，只把 `builder` 內部從展開 20 個具名參數改為呼叫這個工廠函式。

**Tech Stack:** Flutter/Dart，`flutter_test`（純 Dart 單元測試，不需要 `testWidgets`／pump，因為 `buildReaderScreen()` 本身不依賴 `BuildContext`）。

**Spec:** `docs/epics/epic-41-search-architecture-hardening/issues.md`（Issue 1 段落，已依 `reviews/review-epic-and-issues.md` I-3 修訂——回傳具體型別 `ReaderScreen`、函式命名 `buildReaderScreen` 而非 `buildReaderScreenRoute`）。

## Global Constraints

- 所有新增/修改的程式碼註解與本計畫文件一律使用正體中文（zh-TW），不得使用簡體中文（使用者全域 CLAUDE.md 規則）。
- `buildReaderScreen()` 回傳型別必須是具體型別 `ReaderScreen`，不是 `Widget`——單元測試需要不轉型直接存取欄位（審查意見 I-3）。
- 不改動 `ReaderScreen` 建構子本身的簽章／既有測試——本 Issue 純粹收斂「呼叫端怎麼組裝」這一層。
- `MaterialPageRoute(builder: ...)` 這層維持留在三個呼叫端，`buildReaderScreen()` 只負責組裝 `ReaderScreen` widget 本身，不吃掉導覽這層。
- 每個 Task 只跑「這次異動實際觸及」的測試檔，不需要每個 Task 都重跑全套 `flutter test`；只在**最後一個 Task**（Task 4）跑一次完整 `flutter test` 作最終確認（專案 `CLAUDE.md`「測試執行範圍」既有慣例）。
- 三個呼叫點原本各自 `import 'reader_screen.dart';`，改用 `buildReaderScreen()` 後皆不再直接引用 `ReaderScreen` 型別（已查證這三個檔案內沒有任何 `ReaderScreen.xxx` 靜態成員呼叫，也沒有其他地方需要 `ReaderScreen` 這個型別名稱），此 import 在三個檔案內皆變成本次改動造成的無用 import，須移除並改為 `import 'reader_screen_route.dart';`。
- Git commit 訊息結尾需附加下列兩行（本次 session 的固定 attribution，見系統提示）：
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
  ```

---

### Task 1: 新增 `buildReaderScreen()` 工廠函式

**Files:**
- Create: `app/lib/screens/reader_screen_route.dart`
- Test: `app/test/screens/reader_screen_route_test.dart`

**Interfaces:**
- Consumes：既有型別 `Book`（`package:elinkbook/library/models/book.dart`）、`ReaderPrefsManager`（`package:elinkbook/reader/reader_prefs_manager.dart`）、`LibraryRepository`（`package:elinkbook/library/library_repository.dart`）、`ReaderJumpTarget`（`package:elinkbook/reader/reader_jump_target.dart`）、`LibraryReaderFeatureRepositories`／`LibrarySyncDependencies`（`package:elinkbook/screens/library_screen_dependencies.dart`）、`ReaderScreen`（`package:elinkbook/screens/reader_screen.dart`，其建構子目前完整簽章見下方 Step 3 程式碼，欄位皆已存在、本 Task 不新增/修改）。
- Produces：`ReaderScreen buildReaderScreen({required Book book, required ReaderPrefsManager prefsManager, required LibraryReaderFeatureRepositories features, required LibrarySyncDependencies sync, required LibraryRepository libraryRepository, required bool isEinkMode, ReaderJumpTarget? initialJumpTarget})`——供 Task 2/3/4 呼叫。

- [ ] **Step 1: 寫失敗測試（欄位對帳，審查修正 I-1：`features` 12 個欄位全數給非空值並逐一斷言，不留 `null == null` 的虛假綠燈）**

建立 `app/test/screens/reader_screen_route_test.dart`：

```dart
// app/test/screens/reader_screen_route_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/reader/tts_audio_handler.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/reader_screen_route.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';

import '../support/fake_book_reader_prefs_repository.dart';
import '../support/fake_bookmarks_repository.dart';
import '../support/fake_custom_fonts_repository.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_notes_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_search_repository.dart';
import '../support/fake_tts_audio_focus_source.dart';
import '../support/fake_tts_provider.dart';

Book _testBook() {
  return Book(
    id: 'b1',
    title: '測試書',
    author: '作者',
    format: BookFileFormat.epub,
    filePath: 'content://example/b1.epub',
    source: BookSource.local,
    groupName: BookGroup.uncategorized,
    createTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    progress: 0.42,
    isFixedLayout: true,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('buildReaderScreen', () {
    // 【審查修正 I-1】`LayoutPresetRepository` 沒有現成的 Fake（`test/support/`
    // 內查證只有 `FakeBookReaderPrefsRepository`，沒有
    // `FakeLayoutPresetRepository`），比照 `test/reader/layout_preset_repository_test.dart`
    // 既有慣例，用真實 in-memory sqflite 建構它——只有這一個欄位需要真實
    // Database，其餘 11 個欄位皆有現成 Fake 或可直接無參數建構的真實類別。
    late SqliteLibraryRepository dbRepository;

    setUp(() async {
      dbRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    });

    tearDown(() async {
      await dbRepository.close();
    });

    test(
        '欄位對帳：features 12 個欄位＋book／sync／isEinkMode 皆給非空值，'
        '逐一斷言正確帶入 ReaderScreen，不遺漏任何一個具名參數', () {
      final book = _testBook();
      final prefsManager = FakeReaderPrefsManager();
      final libraryRepository = FakeLibraryRepository();
      final bookmarksRepository = FakeBookmarksRepository();
      final highlightsRepository = FakeHighlightsRepository();
      final notesRepository = FakeNotesRepository();
      final customFontsRepository = FakeCustomFontsRepository();
      final layoutPresetRepository =
          LayoutPresetRepository(dbRepository.database);
      final bookReaderPrefsRepository = FakeBookReaderPrefsRepository();
      final ttsProvider = FakeTtsProvider();
      final ttsAudioHandler = TtsAudioHandler();
      final ttsAudioFocusSource = FakeTtsAudioFocusSource();
      final readerActivityTracker = ReaderActivityTracker();
      final searchRepository = FakeSearchRepository();
      final syncCheckpointTrigger = SyncCheckpointTrigger(
        isLoggedIn: () async => false,
        runCheckpoint: () async {},
      );
      final features = LibraryReaderFeatureRepositories(
        bookmarksRepository: bookmarksRepository,
        highlightsRepository: highlightsRepository,
        notesRepository: notesRepository,
        customFontsRepository: customFontsRepository,
        layoutPresetRepository: layoutPresetRepository,
        bookReaderPrefsRepository: bookReaderPrefsRepository,
        ttsProvider: ttsProvider,
        ttsAudioHandler: ttsAudioHandler,
        ttsAudioFocusSource: ttsAudioFocusSource,
        readerActivityTracker: readerActivityTracker,
        searchRepository: searchRepository,
        isFullTextSearchAvailable: false,
      );
      final sync = LibrarySyncDependencies(
        syncCheckpointTrigger: syncCheckpointTrigger,
      );

      final screen = buildReaderScreen(
        book: book,
        prefsManager: prefsManager,
        features: features,
        sync: sync,
        libraryRepository: libraryRepository,
        isEinkMode: true,
      );

      expect(screen.filePath, book.filePath);
      expect(screen.bookId, book.id);
      expect(screen.prefsManager, same(prefsManager));
      expect(screen.bookTitle, book.title);
      expect(screen.bookAuthor, book.author);
      expect(screen.bookProgress, book.progress);
      expect(screen.isFixedLayout, book.isFixedLayout);
      expect(screen.libraryRepository, same(libraryRepository));
      expect(screen.bookmarksRepository, same(bookmarksRepository));
      expect(screen.highlightsRepository, same(highlightsRepository));
      expect(screen.notesRepository, same(notesRepository));
      expect(screen.customFontsRepository, same(customFontsRepository));
      expect(screen.layoutPresetRepository, same(layoutPresetRepository));
      expect(
          screen.bookReaderPrefsRepository, same(bookReaderPrefsRepository));
      expect(screen.ttsProvider, same(ttsProvider));
      expect(screen.ttsAudioHandler, same(ttsAudioHandler));
      expect(screen.ttsAudioFocusSource, same(ttsAudioFocusSource));
      expect(screen.readerActivityTracker, same(readerActivityTracker));
      expect(screen.searchRepository, same(searchRepository));
      expect(screen.syncCheckpointTrigger, same(syncCheckpointTrigger));
      expect(screen.isFullTextSearchAvailable, false);
      expect(screen.isEinkMode, true);
      expect(screen.initialJumpTarget, isNull);
    });

    test('initialJumpTarget 有值時正確帶入 ReaderScreen', () {
      const jumpTarget = ReaderJumpTarget(cfi: 'epubcfi(/6/4!/4/2)');

      final screen = buildReaderScreen(
        book: _testBook(),
        prefsManager: FakeReaderPrefsManager(),
        features: const LibraryReaderFeatureRepositories(),
        sync: const LibrarySyncDependencies(),
        libraryRepository: FakeLibraryRepository(),
        isEinkMode: false,
        initialJumpTarget: jumpTarget,
      );

      expect(screen.initialJumpTarget, jumpTarget);
    });

    test('initialJumpTarget 未帶入時 ReaderScreen 收到 null（一般開書路徑，零回歸）', () {
      final screen = buildReaderScreen(
        book: _testBook(),
        prefsManager: FakeReaderPrefsManager(),
        features: const LibraryReaderFeatureRepositories(),
        sync: const LibrarySyncDependencies(),
        libraryRepository: FakeLibraryRepository(),
        isEinkMode: false,
      );

      expect(screen.initialJumpTarget, isNull);
    });
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_route_test.dart`
Expected: FAIL（編譯錯誤，`package:elinkbook/screens/reader_screen_route.dart` 不存在／`buildReaderScreen` 未定義）

- [ ] **Step 3: 寫最小實作**

建立 `app/lib/screens/reader_screen_route.dart`：

```dart
// app/lib/screens/reader_screen_route.dart
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../reader/reader_jump_target.dart';
import '../reader/reader_prefs_manager.dart';
import 'library_screen_dependencies.dart';
import 'reader_screen.dart';

/// 收斂 `library_screen.dart`／`library_search_screen.dart`／
/// `book_search_screen.dart` 三處建構 `ReaderScreen` 的重複程式碼
/// （epic-41-search-architecture-hardening Issue 1）。三個呼叫點原本各自
/// 手抄約 20 個具名參數，只有 [book]／[libraryRepository]／[isEinkMode]／
/// [initialJumpTarget] 這幾個欄位的來源不同，其餘全部來自
/// [features]／[sync] 這兩個既有 bundle（`epic-26-architecture-hardening`
/// Issue 7 產物）。回傳具體型別 [ReaderScreen]（不是 `Widget`），讓呼叫端
/// 與測試都能不轉型直接存取欄位（`reviews/review-epic-and-issues.md` I-3）。
/// 不改變 `ReaderScreen` 建構子本身的任何既有語意，純粹是組裝這一層。
ReaderScreen buildReaderScreen({
  required Book book,
  required ReaderPrefsManager prefsManager,
  required LibraryReaderFeatureRepositories features,
  required LibrarySyncDependencies sync,
  required LibraryRepository libraryRepository,
  required bool isEinkMode,
  ReaderJumpTarget? initialJumpTarget,
}) {
  return ReaderScreen(
    filePath: book.filePath,
    bookId: book.id,
    prefsManager: prefsManager,
    bookmarksRepository: features.bookmarksRepository,
    highlightsRepository: features.highlightsRepository,
    notesRepository: features.notesRepository,
    bookTitle: book.title,
    bookAuthor: book.author,
    bookProgress: book.progress,
    isFixedLayout: book.isFixedLayout,
    libraryRepository: libraryRepository,
    customFontsRepository: features.customFontsRepository,
    layoutPresetRepository: features.layoutPresetRepository,
    bookReaderPrefsRepository: features.bookReaderPrefsRepository,
    syncCheckpointTrigger: sync.syncCheckpointTrigger,
    ttsProvider: features.ttsProvider,
    ttsAudioHandler: features.ttsAudioHandler,
    ttsAudioFocusSource: features.ttsAudioFocusSource,
    isEinkMode: isEinkMode,
    readerActivityTracker: features.readerActivityTracker,
    searchRepository: features.searchRepository,
    isFullTextSearchAvailable: features.isFullTextSearchAvailable,
    initialJumpTarget: initialJumpTarget,
  );
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_route_test.dart`
Expected: PASS（3 個測試案例全數通過）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/reader_screen_route.dart test/screens/reader_screen_route_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen_route.dart app/test/screens/reader_screen_route_test.dart
git commit -m "$(cat <<'EOF'
feat(reader): 新增 buildReaderScreen() 工廠函式收斂 ReaderScreen 組裝（epic-41 Issue 1 Task 1）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

---

### Task 2: `library_screen.dart._openBook()` 改用 `buildReaderScreen()`

**Files:**
- Modify: `app/lib/screens/library_screen.dart:32`（import）、`:431-469`（`_openBook()`）
- Test: `app/test/screens/library_screen_test.dart`（既有測試，不新增案例）

**Interfaces:**
- Consumes：Task 1 產出的 `buildReaderScreen()`。

- [ ] **Step 1: 修改 import**

在 `app/lib/screens/library_screen.dart:32`，把：

```dart
import 'reader_screen.dart';
```

改為：

```dart
import 'reader_screen_route.dart';
```

（已查證 `library_screen.dart` 內沒有任何 `ReaderScreen.xxx` 靜態成員呼叫，只有兩處純文字註解提到「ReaderScreen」，移除此 import 不影響其他程式碼。）

- [ ] **Step 2: 改寫 `_openBook()`**

在 `app/lib/screens/library_screen.dart:431-469`，原本：

```dart
  void _openBook(Book book) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ReaderScreen(
              filePath: book.filePath,
              bookId: book.id,
              prefsManager: widget.prefsManager,
              bookmarksRepository:
                  widget.readerFeatureRepositories.bookmarksRepository,
              highlightsRepository:
                  widget.readerFeatureRepositories.highlightsRepository,
              notesRepository: widget.readerFeatureRepositories.notesRepository,
              bookTitle: book.title,
              bookAuthor: book.author,
              bookProgress: book.progress,
              isFixedLayout: book.isFixedLayout,
              libraryRepository: widget.repository,
              customFontsRepository:
                  widget.readerFeatureRepositories.customFontsRepository,
              layoutPresetRepository:
                  widget.readerFeatureRepositories.layoutPresetRepository,
              bookReaderPrefsRepository:
                  widget.readerFeatureRepositories.bookReaderPrefsRepository,
              syncCheckpointTrigger:
                  widget.syncDependencies.syncCheckpointTrigger,
              ttsProvider: widget.readerFeatureRepositories.ttsProvider,
              ttsAudioHandler: widget.readerFeatureRepositories.ttsAudioHandler,
              ttsAudioFocusSource:
                  widget.readerFeatureRepositories.ttsAudioFocusSource,
              isEinkMode: widget.themeDependencies.isEinkMode,
              readerActivityTracker:
                  widget.readerFeatureRepositories.readerActivityTracker,
              searchRepository:
                  widget.readerFeatureRepositories.searchRepository,
              isFullTextSearchAvailable:
                  widget.readerFeatureRepositories.isFullTextSearchAvailable,
            ),
          ),
        )
        .then((_) {
```

改為：

```dart
  void _openBook(Book book) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => buildReaderScreen(
              book: book,
              prefsManager: widget.prefsManager,
              features: widget.readerFeatureRepositories,
              sync: widget.syncDependencies,
              libraryRepository: widget.repository,
              isEinkMode: widget.themeDependencies.isEinkMode,
            ),
          ),
        )
        .then((_) {
```

`.then((_) { ... })` 內容（既有的重新載入書籍清單邏輯）維持完全不動，只有 `builder:` 那一段改變。

- [ ] **Step 3: 執行既有回歸測試**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: PASS（全數通過，含 `:1930` 起「LibraryScreen 點開一本書後，ReaderScreen 收到的 ttsAudioHandler／...」這個逐欄位斷言的關鍵回歸測試）

- [ ] **Step 4: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/library_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/library_screen.dart
git commit -m "$(cat <<'EOF'
refactor(reader): library_screen.dart 改用 buildReaderScreen() 組裝（epic-41 Issue 1 Task 2）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

---

### Task 3: `library_search_screen.dart._openBook()` 改用 `buildReaderScreen()`

**Files:**
- Modify: `app/lib/screens/library_search_screen.dart:17`（import）、`:146-192`（`_openBook()`）
- Test: `app/test/screens/library_search_screen_test.dart`（既有測試，不新增案例）

**Interfaces:**
- Consumes：Task 1 產出的 `buildReaderScreen()`。

- [ ] **Step 1: 修改 import**

在 `app/lib/screens/library_search_screen.dart:17`，把：

```dart
import 'reader_screen.dart';
```

改為：

```dart
import 'reader_screen_route.dart';
```

（已查證 `library_search_screen.dart` 內沒有任何 `ReaderScreen.xxx` 靜態成員呼叫，只有一處純文字註解提到「ReaderScreen」，移除此 import 不影響其他程式碼。）

- [ ] **Step 2: 改寫 `_openBook()`**

在 `app/lib/screens/library_search_screen.dart:146-192`，原本：

```dart
  void _openBook(Book book, {ReaderJumpTarget? jumpTarget}) {
    // 進入閱讀畫面（ReaderScreen）前收起搜尋輸入框焦點與軟鍵盤（IME），
    // 避免部分 Android E-Ink 裝置在未收起鍵盤下 push 新頁面時，因 IME 異步
    // 退場重算 Window Insets 與 setPreferredOrientations([]) 交互誤觸發螢幕旋轉。
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          filePath: book.filePath,
          bookId: book.id,
          prefsManager: widget.prefsManager,
          bookmarksRepository:
              widget.readerFeatureRepositories.bookmarksRepository,
          highlightsRepository:
              widget.readerFeatureRepositories.highlightsRepository,
          notesRepository: widget.readerFeatureRepositories.notesRepository,
          bookTitle: book.title,
          bookAuthor: book.author,
          bookProgress: book.progress,
          isFixedLayout: book.isFixedLayout,
          libraryRepository: widget.libraryRepository,
          customFontsRepository:
              widget.readerFeatureRepositories.customFontsRepository,
          layoutPresetRepository:
              widget.readerFeatureRepositories.layoutPresetRepository,
          bookReaderPrefsRepository:
              widget.readerFeatureRepositories.bookReaderPrefsRepository,
          syncCheckpointTrigger: widget.syncDependencies.syncCheckpointTrigger,
          ttsProvider: widget.readerFeatureRepositories.ttsProvider,
          ttsAudioHandler: widget.readerFeatureRepositories.ttsAudioHandler,
          ttsAudioFocusSource:
              widget.readerFeatureRepositories.ttsAudioFocusSource,
          isEinkMode: widget.isEinkMode,
          readerActivityTracker:
              widget.readerFeatureRepositories.readerActivityTracker,
          searchRepository: widget.readerFeatureRepositories.searchRepository,
          isFullTextSearchAvailable:
              widget.readerFeatureRepositories.isFullTextSearchAvailable,
          // epic-10-search Issue 5：只有內容匹配片段的點擊會帶入
          // jumpTarget（見下方 _buildContentGroupCard 呼叫端），書名/作者
          // 匹配結果維持一般開書路徑（jumpTarget 預設 null）。
          initialJumpTarget: jumpTarget,
        ),
      ),
    );
  }
```

改為：

```dart
  void _openBook(Book book, {ReaderJumpTarget? jumpTarget}) {
    // 進入閱讀畫面（ReaderScreen）前收起搜尋輸入框焦點與軟鍵盤（IME），
    // 避免部分 Android E-Ink 裝置在未收起鍵盤下 push 新頁面時，因 IME 異步
    // 退場重算 Window Insets 與 setPreferredOrientations([]) 交互誤觸發螢幕旋轉。
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => buildReaderScreen(
          book: book,
          prefsManager: widget.prefsManager,
          features: widget.readerFeatureRepositories,
          sync: widget.syncDependencies,
          libraryRepository: widget.libraryRepository,
          isEinkMode: widget.isEinkMode,
          // epic-10-search Issue 5：只有內容匹配片段的點擊會帶入
          // jumpTarget（見下方 _buildContentGroupCard 呼叫端），書名/作者
          // 匹配結果維持一般開書路徑（jumpTarget 預設 null）。
          initialJumpTarget: jumpTarget,
        ),
      ),
    );
  }
```

- [ ] **Step 3: 執行既有回歸測試**

Run: `cd app && flutter test test/screens/library_search_screen_test.dart`
Expected: PASS（全數通過，含 `:365` 「點擊書名/作者匹配結果會開啟 ReaderScreen」、`:385` 「點擊內容匹配片段會開啟 ReaderScreen」、`:558` 「點擊書名/作者匹配結果開書時，不帶 initialJumpTarget」三個關鍵回歸測試）

- [ ] **Step 4: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/library_search_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/library_search_screen.dart
git commit -m "$(cat <<'EOF'
refactor(reader): library_search_screen.dart 改用 buildReaderScreen() 組裝（epic-41 Issue 1 Task 3）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

---

### Task 4: `book_search_screen.dart._handleSnippetTap()` 改用 `buildReaderScreen()`，並跑全套驗證收尾

**Files:**
- Modify: `app/lib/screens/book_search_screen.dart:14`（import）、`:146-185`（`_handleSnippetTap()` 推入 `ReaderScreen` 那段）
- Test: `app/test/screens/book_search_screen_test.dart`（既有測試，不新增案例）

**Interfaces:**
- Consumes：Task 1 產出的 `buildReaderScreen()`。

- [ ] **Step 1: 修改 import**

在 `app/lib/screens/book_search_screen.dart:14`，把：

```dart
import 'reader_screen.dart';
```

改為：

```dart
import 'reader_screen_route.dart';
```

（已查證 `book_search_screen.dart` 內沒有任何 `ReaderScreen.xxx` 靜態成員呼叫，只有兩處純文字註解提到「ReaderScreen」，移除此 import 不影響其他程式碼。）

- [ ] **Step 2: 改寫 `_handleSnippetTap()` 推入 `ReaderScreen` 那段**

在 `app/lib/screens/book_search_screen.dart:146-185`（`if (widget.fromReader) { ... }` 之後的推入路徑），原本：

```dart
    // 從全庫搜尋推入：開啟 ReaderScreen。
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          filePath: widget.book.filePath,
          bookId: widget.book.id,
          prefsManager: widget.prefsManager,
          bookmarksRepository:
              widget.readerFeatureRepositories.bookmarksRepository,
          highlightsRepository:
              widget.readerFeatureRepositories.highlightsRepository,
          notesRepository: widget.readerFeatureRepositories.notesRepository,
          bookTitle: widget.book.title,
          bookAuthor: widget.book.author,
          bookProgress: widget.book.progress,
          isFixedLayout: widget.book.isFixedLayout,
          libraryRepository: widget.libraryRepository,
          customFontsRepository:
              widget.readerFeatureRepositories.customFontsRepository,
          layoutPresetRepository:
              widget.readerFeatureRepositories.layoutPresetRepository,
          bookReaderPrefsRepository:
              widget.readerFeatureRepositories.bookReaderPrefsRepository,
          syncCheckpointTrigger:
              widget.syncDependencies.syncCheckpointTrigger,
          ttsProvider: widget.readerFeatureRepositories.ttsProvider,
          ttsAudioHandler: widget.readerFeatureRepositories.ttsAudioHandler,
          ttsAudioFocusSource:
              widget.readerFeatureRepositories.ttsAudioFocusSource,
          isEinkMode: widget.isEinkMode,
          readerActivityTracker:
              widget.readerFeatureRepositories.readerActivityTracker,
          searchRepository: widget.readerFeatureRepositories.searchRepository,
          isFullTextSearchAvailable:
              widget.readerFeatureRepositories.isFullTextSearchAvailable,
          initialJumpTarget: jumpTarget,
        ),
      ),
    );
  }
```

改為：

```dart
    // 從全庫搜尋推入：開啟 ReaderScreen。
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => buildReaderScreen(
          book: widget.book,
          prefsManager: widget.prefsManager,
          features: widget.readerFeatureRepositories,
          sync: widget.syncDependencies,
          libraryRepository: widget.libraryRepository,
          isEinkMode: widget.isEinkMode,
          initialJumpTarget: jumpTarget,
        ),
      ),
    );
  }
```

- [ ] **Step 3: 執行既有回歸測試**

Run: `cd app && flutter test test/screens/book_search_screen_test.dart`
Expected: PASS（全數通過，含 `:253` 「fromReader=false 時點擊片段推入 ReaderScreen」）

- [ ] **Step 4: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/book_search_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: 跑完整 `flutter analyze`／`flutter test` 作最終確認**

本 Issue 三個 Task 皆完成，依專案慣例在最後一個 Task 跑一次全套驗證：

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數通過（比對 `docs/epics/epic-10-search/epic.md` 記錄的既有基準 `+2339 ~1 -2`——2 個 `adaptive_shell_scaffold_test.dart` 既有失敗案例已知與本次改動無關，見 `docs/superpowers/plans/2026-09-13-split-global-reader-prefs.md` 驗證紀錄；新增 3 個 `reader_screen_route_test.dart` 測試案例後，總數應為既有基準 +3，失敗數維持 2 且必須是同樣兩個既有案例，不可出現新的失敗）。

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/book_search_screen.dart
git commit -m "$(cat <<'EOF'
refactor(reader): book_search_screen.dart 改用 buildReaderScreen() 組裝（epic-41 Issue 1 Task 4）

三個呼叫點（library_screen.dart／library_search_screen.dart／
book_search_screen.dart）皆已收斂為呼叫同一個 buildReaderScreen()
工廠函式，不再各自手抄約 20 個具名參數。ReaderScreen 對外介面與既有
行為完全不變，全專案 flutter test 零回歸。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

- [ ] **Step 7: 更新工單狀態**

在 `docs/epics/epic-41-search-architecture-hardening/issues.md` 的 Issue 1 段落，依專案既有看板慣例（見 `docs/epics/epic-10-search/issues.md` Issue 0：`**Status:** completed（...）`），把 `**Status:** ready-for-agent` 改為：

```
**Status:** completed（`plans/plan-issue-1.md` 4 個 Task 全數完成，新增 `buildReaderScreen()`，三個呼叫點〔`library_screen.dart`／`library_search_screen.dart`／`book_search_screen.dart`〕皆已改用，`flutter analyze`/`flutter test` 全數通過零回歸）
```

同步在 `epic.md` 的開發記錄追加一句「Issue 1 已完成」。
