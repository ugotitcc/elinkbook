// app/lib/screens/reader_screen_route.dart
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../reader/reader_jump_target.dart';
import '../reader/reader_prefs_manager.dart';
import 'library_screen_dependencies.dart';
import 'reader_feature_dependencies.dart';
import 'reader_screen.dart';

/// 【過渡用，Issue 12 移除】把尚未遷移的外層畫面（`LibraryScreen`）持有的舊 bundle
/// 組裝成新的 [ReaderFeatureDependencies]（ADR 0037 §6）。舊 bundle 欄位是
/// nullable，新組是 non-null：遇到 null 就丟 [StateError]，訊息含欄位名——正式環境
/// `main.dart` 全部傳值，不會觸發；測試需用 `completeLegacyReaderFeatures()` 補齊。
ReaderFeatureDependencies readerFeatureDependenciesFromLegacy({
  required ReaderPrefsManager prefsManager,
  required LibraryReaderFeatureRepositories features,
  required LibrarySyncDependencies sync,
  required LibraryRepository libraryRepository,
}) {
  T need<T>(T? value, String name) {
    if (value == null) {
      throw StateError('ReaderFeatureDependencies 缺少 $name');
    }
    return value;
  }

  return ReaderFeatureDependencies(
    prefsManager: prefsManager,
    libraryRepository: libraryRepository,
    bookImportService: need(features.bookImportService, 'bookImportService'),
    bookmarksRepository: need(
      features.bookmarksRepository,
      'bookmarksRepository',
    ),
    highlightsRepository: need(
      features.highlightsRepository,
      'highlightsRepository',
    ),
    notesRepository: need(features.notesRepository, 'notesRepository'),
    customFontsRepository: need(
      features.customFontsRepository,
      'customFontsRepository',
    ),
    downloadableFontStore: need(
      features.downloadableFontStore,
      'downloadableFontStore',
    ),
    layoutPresetRepository: need(
      features.layoutPresetRepository,
      'layoutPresetRepository',
    ),
    bookReaderPrefsRepository: need(
      features.bookReaderPrefsRepository,
      'bookReaderPrefsRepository',
    ),
    searchRepository: need(features.searchRepository, 'searchRepository'),
    isFullTextSearchAvailable: features.isFullTextSearchAvailable,
    fullTextSearchSettingsRepository: need(
      features.fullTextSearchSettingsRepository,
      'fullTextSearchSettingsRepository',
    ),
    readingStatsRepository: need(
      features.readingStatsRepository,
      'readingStatsRepository',
    ),
    readerActivityTracker: need(
      features.readerActivityTracker,
      'readerActivityTracker',
    ),
    syncCheckpointTrigger: need(
      sync.syncCheckpointTrigger,
      'syncCheckpointTrigger',
    ),
    ttsProvider: need(features.ttsProvider, 'ttsProvider'),
    ttsAudio: need(features.ttsAudio, 'ttsAudio'),
    ttsAudioFocusSource: need(
      features.ttsAudioFocusSource,
      'ttsAudioFocusSource',
    ),
  );
}

/// 三處開書路徑（書架、全庫搜尋、單書搜尋）共用的 `ReaderScreen` 組裝點
/// （epic-41 Issue 1）。書本欄位由 [book] 帶入，其餘依賴整組由 [dependencies]
/// 帶入。回傳具體型別 [ReaderScreen]，讓呼叫端與測試不轉型直接存取欄位。
ReaderScreen buildReaderScreen({
  required Book book,
  required ReaderFeatureDependencies dependencies,
  required bool isEinkMode,
  ReaderJumpTarget? initialJumpTarget,
}) {
  return ReaderScreen(
    filePath: book.filePath,
    bookId: book.id,
    dependencies: dependencies,
    bookTitle: book.title,
    bookAuthor: book.author,
    bookProgress: book.progress,
    isFixedLayout: book.isFixedLayout,
    isEinkMode: isEinkMode,
    initialJumpTarget: initialJumpTarget,
  );
}
