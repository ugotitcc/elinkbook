// app/test/screens/reader_screen_route_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/reader/tts_audio_handler.dart';
import 'package:elinkbook/reader/tts_audio_handler_startup.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/reader_screen_route.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_book_reader_prefs_repository.dart';
import '../support/fake_bookmarks_repository.dart';
import '../support/fake_custom_fonts_repository.dart';
import '../support/fake_downloadable_font_store.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_layout_preset_repository.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_notes_repository.dart';
import '../support/fake_reader_feature_dependencies.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_reading_stats_repository.dart';
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
  group('buildReaderScreen', () {
    test('欄位對帳：dependencies 18 個欄位逐一同一實例，書本欄位來自 book', () {
      final book = _testBook();
      final prefsManager = FakeReaderPrefsManager();
      final libraryRepository = FakeLibraryRepository();
      final bookmarksRepository = FakeBookmarksRepository();
      final highlightsRepository = FakeHighlightsRepository();
      final notesRepository = FakeNotesRepository();
      final customFontsRepository = FakeCustomFontsRepository();
      final downloadableFontStore = FakeDownloadableFontStore();
      final layoutPresetRepository = FakeLayoutPresetRepository();
      final bookReaderPrefsRepository = FakeBookReaderPrefsRepository();
      final ttsProvider = FakeTtsProvider();
      final ttsAudio = TtsAudioHandlerHolder.ready(TtsAudioHandler());
      final ttsAudioFocusSource = FakeTtsAudioFocusSource();
      final readerActivityTracker = ReaderActivityTracker();
      final searchRepository = FakeSearchRepository();
      final importService = FakeBookImportService();
      final readingStatsRepository = FakeReadingStatsRepository();
      final syncCheckpointTrigger = SyncCheckpointTrigger(
        runCheckpoint: () async => SyncCheckpointResult.notLoggedIn,
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
        ttsAudio: ttsAudio,
        ttsAudioFocusSource: ttsAudioFocusSource,
        readerActivityTracker: readerActivityTracker,
        searchRepository: searchRepository,
        isFullTextSearchAvailable: false,
        bookImportService: importService,
        readingStatsRepository: readingStatsRepository,
      );
      final sync = LibrarySyncDependencies(
        syncCheckpointTrigger: syncCheckpointTrigger,
      );
      final dependencies = readerFeatureDependenciesFromLegacy(
        prefsManager: prefsManager,
        features: features,
        sync: sync,
        libraryRepository: libraryRepository,
      );

      final screen = buildReaderScreen(
        book: book,
        dependencies: dependencies,
        isEinkMode: true,
      );

      expect(screen.dependencies, same(dependencies));
      expect(screen.filePath, book.filePath);
      expect(screen.bookId, book.id);
      expect(screen.bookTitle, book.title);
      expect(screen.bookAuthor, book.author);
      expect(screen.bookProgress, book.progress);
      expect(screen.isFixedLayout, book.isFixedLayout);
      expect(dependencies.prefsManager, same(prefsManager));
      expect(dependencies.libraryRepository, same(libraryRepository));
      expect(dependencies.bookImportService, same(importService));
      expect(dependencies.bookmarksRepository, same(bookmarksRepository));
      expect(dependencies.highlightsRepository, same(highlightsRepository));
      expect(dependencies.notesRepository, same(notesRepository));
      expect(dependencies.customFontsRepository, same(customFontsRepository));
      expect(dependencies.downloadableFontStore, same(downloadableFontStore));
      expect(dependencies.layoutPresetRepository, same(layoutPresetRepository));
      expect(dependencies.bookReaderPrefsRepository,
          same(bookReaderPrefsRepository));
      expect(dependencies.searchRepository, same(searchRepository));
      expect(dependencies.isFullTextSearchAvailable, isFalse);
      expect(dependencies.readingStatsRepository,
          same(readingStatsRepository));
      expect(dependencies.readerActivityTracker, same(readerActivityTracker));
      expect(dependencies.syncCheckpointTrigger, same(syncCheckpointTrigger));
      expect(dependencies.ttsProvider, same(ttsProvider));
      expect(dependencies.ttsAudio, same(ttsAudio));
      expect(dependencies.ttsAudioFocusSource, same(ttsAudioFocusSource));
      expect(screen.isEinkMode, isTrue);
      expect(screen.initialJumpTarget, isNull);
    });

    test('initialJumpTarget 有值時正確帶入 ReaderScreen', () {
      const jumpTarget = ReaderJumpTarget(cfi: 'epubcfi(/6/4!/4/2)');

      final screen = buildReaderScreen(
        book: _testBook(),
        dependencies: fakeReaderFeatureDependencies(),
        isEinkMode: false,
        initialJumpTarget: jumpTarget,
      );

      expect(screen.initialJumpTarget, jumpTarget);
    });

    test('initialJumpTarget 未帶入時 ReaderScreen 收到 null（一般開書路徑，零回歸）', () {
      final screen = buildReaderScreen(
        book: _testBook(),
        dependencies: fakeReaderFeatureDependencies(),
        isEinkMode: false,
      );

      expect(screen.initialJumpTarget, isNull);
    });
  });

  group('readerFeatureDependenciesFromLegacy', () {
    // 以完整舊 bundle 為底，將單一欄位置 null，轉換必須丟 StateError 且訊息含欄位名。
    LibraryReaderFeatureRepositories legacyWithNull(String field) {
      final full = completeLegacyReaderFeatures();
      switch (field) {
        case 'bookmarksRepository':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: null,
            highlightsRepository: full.highlightsRepository,
            notesRepository: full.notesRepository,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: full.ttsProvider,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: full.searchRepository,
            bookImportService: full.bookImportService,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'highlightsRepository':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: null,
            notesRepository: full.notesRepository,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: full.ttsProvider,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: full.searchRepository,
            bookImportService: full.bookImportService,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'notesRepository':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: full.highlightsRepository,
            notesRepository: null,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: full.ttsProvider,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: full.searchRepository,
            bookImportService: full.bookImportService,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'customFontsRepository':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: full.highlightsRepository,
            notesRepository: full.notesRepository,
            customFontsRepository: null,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: full.ttsProvider,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: full.searchRepository,
            bookImportService: full.bookImportService,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'downloadableFontStore':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: full.highlightsRepository,
            notesRepository: full.notesRepository,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: null,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: full.ttsProvider,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: full.searchRepository,
            bookImportService: full.bookImportService,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'layoutPresetRepository':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: full.highlightsRepository,
            notesRepository: full.notesRepository,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: null,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: full.ttsProvider,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: full.searchRepository,
            bookImportService: full.bookImportService,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'bookReaderPrefsRepository':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: full.highlightsRepository,
            notesRepository: full.notesRepository,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: null,
            ttsProvider: full.ttsProvider,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: full.searchRepository,
            bookImportService: full.bookImportService,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'ttsProvider':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: full.highlightsRepository,
            notesRepository: full.notesRepository,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: null,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: full.searchRepository,
            bookImportService: full.bookImportService,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'ttsAudio':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: full.highlightsRepository,
            notesRepository: full.notesRepository,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: full.ttsProvider,
            ttsAudio: null,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: full.searchRepository,
            bookImportService: full.bookImportService,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'ttsAudioFocusSource':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: full.highlightsRepository,
            notesRepository: full.notesRepository,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: full.ttsProvider,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: null,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: full.searchRepository,
            bookImportService: full.bookImportService,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'readerActivityTracker':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: full.highlightsRepository,
            notesRepository: full.notesRepository,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: full.ttsProvider,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: null,
            searchRepository: full.searchRepository,
            bookImportService: full.bookImportService,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'searchRepository':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: full.highlightsRepository,
            notesRepository: full.notesRepository,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: full.ttsProvider,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: null,
            bookImportService: full.bookImportService,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'bookImportService':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: full.highlightsRepository,
            notesRepository: full.notesRepository,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: full.ttsProvider,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: full.searchRepository,
            bookImportService: null,
            readingStatsRepository: full.readingStatsRepository,
          );
        case 'readingStatsRepository':
          return LibraryReaderFeatureRepositories(
            bookmarksRepository: full.bookmarksRepository,
            highlightsRepository: full.highlightsRepository,
            notesRepository: full.notesRepository,
            customFontsRepository: full.customFontsRepository,
            downloadableFontStore: full.downloadableFontStore,
            layoutPresetRepository: full.layoutPresetRepository,
            bookReaderPrefsRepository: full.bookReaderPrefsRepository,
            ttsProvider: full.ttsProvider,
            ttsAudio: full.ttsAudio,
            ttsAudioFocusSource: full.ttsAudioFocusSource,
            readerActivityTracker: full.readerActivityTracker,
            searchRepository: full.searchRepository,
            bookImportService: full.bookImportService,
            readingStatsRepository: null,
          );
        default:
          throw ArgumentError('未知的欄位名：$field');
      }
    }

    const nullFields = [
      'bookmarksRepository',
      'highlightsRepository',
      'notesRepository',
      'customFontsRepository',
      'downloadableFontStore',
      'layoutPresetRepository',
      'bookReaderPrefsRepository',
      'ttsProvider',
      'ttsAudio',
      'ttsAudioFocusSource',
      'readerActivityTracker',
      'searchRepository',
      'bookImportService',
      'readingStatsRepository',
    ];

    for (final field in nullFields) {
      test('$field 為 null 時丟 StateError，訊息含欄位名', () {
        expect(
          () => readerFeatureDependenciesFromLegacy(
            prefsManager: FakeReaderPrefsManager(),
            features: legacyWithNull(field),
            sync: completeLegacySyncDependencies(),
            libraryRepository: FakeLibraryRepository(),
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(field),
          )),
        );
      });
    }

    test('sync.syncCheckpointTrigger 為 null 時丟 StateError，訊息含欄位名', () {
      expect(
        () => readerFeatureDependenciesFromLegacy(
          prefsManager: FakeReaderPrefsManager(),
          features: completeLegacyReaderFeatures(),
          sync: const LibrarySyncDependencies(),
          libraryRepository: FakeLibraryRepository(),
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('syncCheckpointTrigger'),
        )),
      );
    });

    test('舊 bundle 完整時轉換成功，18 個欄位皆非 null', () {
      final dependencies = readerFeatureDependenciesFromLegacy(
        prefsManager: FakeReaderPrefsManager(),
        features: completeLegacyReaderFeatures(),
        sync: completeLegacySyncDependencies(),
        libraryRepository: FakeLibraryRepository(),
      );

      expect(dependencies.prefsManager, isNotNull);
      expect(dependencies.libraryRepository, isNotNull);
      expect(dependencies.bookImportService, isNotNull);
      expect(dependencies.bookmarksRepository, isNotNull);
      expect(dependencies.highlightsRepository, isNotNull);
      expect(dependencies.notesRepository, isNotNull);
      expect(dependencies.customFontsRepository, isNotNull);
      expect(dependencies.downloadableFontStore, isNotNull);
      expect(dependencies.layoutPresetRepository, isNotNull);
      expect(dependencies.bookReaderPrefsRepository, isNotNull);
      expect(dependencies.searchRepository, isNotNull);
      expect(dependencies.readingStatsRepository, isNotNull);
      expect(dependencies.readerActivityTracker, isNotNull);
      expect(dependencies.syncCheckpointTrigger, isNotNull);
      expect(dependencies.ttsProvider, isNotNull);
      expect(dependencies.ttsAudio, isNotNull);
      expect(dependencies.ttsAudioFocusSource, isNotNull);
      expect(dependencies.isFullTextSearchAvailable, isTrue);
    });
  });
}
