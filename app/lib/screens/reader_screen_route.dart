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
    downloadableFontStore: features.downloadableFontStore,
    layoutPresetRepository: features.layoutPresetRepository,
    bookReaderPrefsRepository: features.bookReaderPrefsRepository,
    syncCheckpointTrigger: sync.syncCheckpointTrigger,
    ttsProvider: features.ttsProvider,
    ttsAudio: features.ttsAudio,
    ttsAudioFocusSource: features.ttsAudioFocusSource,
    isEinkMode: isEinkMode,
    readerActivityTracker: features.readerActivityTracker,
    searchRepository: features.searchRepository,
    isFullTextSearchAvailable: features.isFullTextSearchAvailable,
    bookImportService: features.bookImportService,
    readingStatsRepository: features.readingStatsRepository,
    initialJumpTarget: initialJumpTarget,
  );
}
