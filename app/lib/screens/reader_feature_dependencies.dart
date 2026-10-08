import 'package:flutter/foundation.dart';

import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/bookmarks_repository.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/downloadable_font_store.dart';
import '../reader/highlights_repository.dart';
import '../reader/layout_preset_repository.dart';
import '../reader/notes_repository.dart';
import '../reader/reader_activity_tracker.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/tts_audio_focus_source.dart';
import '../reader/tts_audio_handler_startup.dart';
import '../reader/tts_provider.dart';
import '../search/full_text_search_settings_repository.dart';
import '../search/search_repository.dart';
import '../stats/reading_stats_repository.dart';
import '../sync/sync_checkpoint_trigger.dart';

/// 閱讀器功能依賴組（ADR 0037）：`ReaderScreen` 與 `BookSearchScreen` 各自只
/// 接收這一個物件，取代逐欄傳遞。「閱讀器→單書搜尋→閱讀器」整組轉傳同一個
/// 實例，不再手動逐欄重建。
///
/// 全部 non-null、required：`main.dart` 啟動時全部都會建好，缺依賴是編譯錯誤，
/// 不是執行期靜默失效。`syncCheckpointTrigger` 同時也屬於同步依賴組，由
/// `AppDependencies` 建構一次、同一實例放進各組（Issue 13）。
///
/// 依書本才能建構的 `readingStatsTracker` 與純為 widget test 注入的
/// `pickSingleBookFile` **不在這裡**，留在 `ReaderScreen` 建構子上。
@immutable
class ReaderFeatureDependencies {
  final ReaderPrefsManager prefsManager;
  final LibraryRepository libraryRepository;
  final BookImportService bookImportService;
  final BookmarksRepository bookmarksRepository;
  final HighlightsRepository highlightsRepository;
  final NotesRepository notesRepository;
  final CustomFontsRepository customFontsRepository;
  final DownloadableFontStore downloadableFontStore;
  final LayoutPresetRepository layoutPresetRepository;
  final BookReaderPrefsRepository bookReaderPrefsRepository;
  final SearchRepository searchRepository;

  /// 本裝置系統 SQLite 是否有 FTS5 模組可用；`false` 時單書搜尋顯示降級提示。
  final bool isFullTextSearchAvailable;

  /// 「啟用全文檢索」設定；書架重新下載後補索引、全庫搜尋與設定頁開關使用，
  /// 閱讀器本身不用。
  final FullTextSearchSettingsRepository fullTextSearchSettingsRepository;
  final ReadingStatsRepository readingStatsRepository;
  final ReaderActivityTracker readerActivityTracker;
  final SyncCheckpointTrigger syncCheckpointTrigger;
  final TtsProvider ttsProvider;

  /// 啟動階段 TTS 音訊服務 holder；服務不可用時為 `TtsAudioHandlerHolder.unavailable()`
  /// 或 `.degraded()`，不是 null。
  final TtsAudioHandlerHolder ttsAudio;
  final TtsAudioFocusSource ttsAudioFocusSource;

  const ReaderFeatureDependencies({
    required this.prefsManager,
    required this.libraryRepository,
    required this.bookImportService,
    required this.bookmarksRepository,
    required this.highlightsRepository,
    required this.notesRepository,
    required this.customFontsRepository,
    required this.downloadableFontStore,
    required this.layoutPresetRepository,
    required this.bookReaderPrefsRepository,
    required this.searchRepository,
    required this.isFullTextSearchAvailable,
    required this.fullTextSearchSettingsRepository,
    required this.readingStatsRepository,
    required this.readerActivityTracker,
    required this.syncCheckpointTrigger,
    required this.ttsProvider,
    required this.ttsAudio,
    required this.ttsAudioFocusSource,
  });
}
