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
import '../support/fake_downloadable_font_store.dart';
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
        '欄位對帳：features 13 個欄位＋book／sync／isEinkMode 皆給非空值，'
        '逐一斷言正確帶入 ReaderScreen，不遺漏任何一個具名參數', () {
      final book = _testBook();
      final prefsManager = FakeReaderPrefsManager();
      final libraryRepository = FakeLibraryRepository();
      final bookmarksRepository = FakeBookmarksRepository();
      final highlightsRepository = FakeHighlightsRepository();
      final notesRepository = FakeNotesRepository();
      final customFontsRepository = FakeCustomFontsRepository();
      final downloadableFontStore = FakeDownloadableFontStore();
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
        downloadableFontStore: downloadableFontStore,
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
      expect(screen.downloadableFontStore, same(downloadableFontStore));
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
