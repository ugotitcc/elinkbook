import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/reader/custom_fonts_repository.dart';
import 'package:elinkbook/reader/downloadable_font_store.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:elinkbook/reader/notes_repository.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/reader/tts_audio_focus_source.dart';
import 'package:elinkbook/reader/tts_audio_handler_startup.dart';
import 'package:elinkbook/reader/tts_provider.dart';
import 'package:elinkbook/screens/reader_feature_dependencies.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';
import 'package:elinkbook/search/search_repository.dart';
import 'package:elinkbook/stats/reading_stats_repository.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';

import 'fake_book_import_service.dart';
import 'fake_book_reader_prefs_repository.dart';
import 'fake_bookmarks_repository.dart';
import 'fake_custom_fonts_repository.dart';
import 'fake_downloadable_font_store.dart';
import 'fake_full_text_search_settings_repository.dart';
import 'fake_highlights_repository.dart';
import 'fake_layout_preset_repository.dart';
import 'fake_library_repository.dart';
import 'fake_notes_repository.dart';
import 'fake_reader_prefs_manager.dart';
import 'fake_reading_stats_repository.dart';
import 'fake_search_repository.dart';
import 'fake_tts_audio_focus_source.dart';
import 'fake_tts_provider.dart';

/// 預設全 fake 的閱讀器功能依賴組（ADR 0037）。只覆寫情境需要的欄位，其餘用
/// 各自獨立的 fake 實例；每次呼叫都建新實例，測試之間不共用狀態。
ReaderFeatureDependencies fakeReaderFeatureDependencies({
  ReaderPrefsManager? prefsManager,
  LibraryRepository? libraryRepository,
  BookImportService? bookImportService,
  BookmarksRepository? bookmarksRepository,
  HighlightsRepository? highlightsRepository,
  NotesRepository? notesRepository,
  CustomFontsRepository? customFontsRepository,
  DownloadableFontStore? downloadableFontStore,
  LayoutPresetRepository? layoutPresetRepository,
  BookReaderPrefsRepository? bookReaderPrefsRepository,
  SearchRepository? searchRepository,
  bool isFullTextSearchAvailable = true,
  FullTextSearchSettingsRepository? fullTextSearchSettingsRepository,
  ReadingStatsRepository? readingStatsRepository,
  ReaderActivityTracker? readerActivityTracker,
  SyncCheckpointTrigger? syncCheckpointTrigger,
  TtsProvider? ttsProvider,
  TtsAudioHandlerHolder? ttsAudio,
  TtsAudioFocusSource? ttsAudioFocusSource,
}) {
  return ReaderFeatureDependencies(
    prefsManager: prefsManager ?? FakeReaderPrefsManager(),
    libraryRepository: libraryRepository ?? FakeLibraryRepository(),
    bookImportService: bookImportService ?? FakeBookImportService(),
    bookmarksRepository: bookmarksRepository ?? FakeBookmarksRepository(),
    highlightsRepository: highlightsRepository ?? FakeHighlightsRepository(),
    notesRepository: notesRepository ?? FakeNotesRepository(),
    customFontsRepository: customFontsRepository ?? FakeCustomFontsRepository(),
    downloadableFontStore:
        downloadableFontStore ?? FakeDownloadableFontStore.forPlatform(),
    layoutPresetRepository:
        layoutPresetRepository ?? FakeLayoutPresetRepository(),
    bookReaderPrefsRepository:
        bookReaderPrefsRepository ?? FakeBookReaderPrefsRepository(),
    searchRepository: searchRepository ?? FakeSearchRepository(),
    isFullTextSearchAvailable: isFullTextSearchAvailable,
    fullTextSearchSettingsRepository:
        fullTextSearchSettingsRepository ??
        FakeFullTextSearchSettingsRepository(),
    readingStatsRepository:
        readingStatsRepository ?? FakeReadingStatsRepository(),
    readerActivityTracker: readerActivityTracker ?? ReaderActivityTracker(),
    syncCheckpointTrigger:
        syncCheckpointTrigger ?? _noopSyncCheckpointTrigger(),
    ttsProvider: ttsProvider ?? FakeTtsProvider(),
    ttsAudio: ttsAudio ?? TtsAudioHandlerHolder.unavailable(),
    ttsAudioFocusSource: ttsAudioFocusSource ?? FakeTtsAudioFocusSource(),
  );
}

SyncCheckpointTrigger _noopSyncCheckpointTrigger() => SyncCheckpointTrigger(
  runCheckpoint: () async => SyncCheckpointResult.notLoggedIn,
);
