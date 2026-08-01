import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'fake_book_reader_prefs_repository.dart';
import 'fake_epub_character_count_repository.dart';
import 'fake_reading_position_repository.dart';

/// 供 `reader_screen_test.dart` 使用的假 [ReaderPrefsManager]：`load`／
/// `save*` 皆為純記憶體內操作；`resolve` 直接委派給
/// [ReaderPrefsManagerImpl.resolve]（純函式、無 I/O，不需要另外假造）以
/// 確保測試驗證的合併邏輯與正式實作完全一致。
class FakeReaderPrefsManager implements ReaderPrefsManager {
  final Map<String, BookReaderPrefs> bookPrefsByBookId;
  final Map<String, ReadingPosition> readingPositionByBookId;
  final Map<String, int> totalCharacterCountByBookId;
  GlobalReaderPrefs globalPrefs;
  final List<String> savedBookPrefsCalls = [];
  final List<GlobalReaderPrefs> savedGlobalPrefsCalls = [];
  final List<MapEntry<String, ReadingPosition>> savedReadingPositionCalls = [];
  final List<MapEntry<String, int>> savedTotalCharacterCountCalls = [];

  FakeReaderPrefsManager({
    Map<String, BookReaderPrefs>? bookPrefsByBookId,
    Map<String, ReadingPosition>? readingPositionByBookId,
    Map<String, int>? totalCharacterCountByBookId,
    this.globalPrefs = const GlobalReaderPrefs.initial(),
  })  : bookPrefsByBookId = bookPrefsByBookId ?? {},
        readingPositionByBookId = readingPositionByBookId ?? {},
        totalCharacterCountByBookId = totalCharacterCountByBookId ?? {};

  /// 預設 BookReaderPrefs：showHeader/showFooter 為 true，避免多數測試
  /// 需要逐一手動傳入（Issue 23 預設值從 true 改為 false 後的測試適配）。
  static const _defaultBookPrefs = BookReaderPrefs(
    showHeader: true,
    showFooter: true,
  );

  final _delegate = ReaderPrefsManagerImpl(
    FakeBookReaderPrefsRepository(),
    FakeReadingPositionRepository(),
    FakeEpubCharacterCountRepository(),
  );

  @override
  Future<LoadedPrefs> load(String bookId) async {
    return LoadedPrefs(
      bookPrefs: bookPrefsByBookId[bookId] ?? _defaultBookPrefs,
      globalPrefs: globalPrefs,
      readingPosition:
          readingPositionByBookId[bookId] ?? const ReadingPosition(),
      totalCharacterCount: totalCharacterCountByBookId[bookId],
    );
  }

  @override
  Future<GlobalReaderPrefs> loadGlobalPrefs() async => globalPrefs;

  @override
  Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs) async {
    bookPrefsByBookId[bookId] = prefs;
    savedBookPrefsCalls.add(bookId);
  }

  @override
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs) async {
    globalPrefs = prefs;
    savedGlobalPrefsCalls.add(prefs);
  }

  @override
  Future<void> saveReadingPosition(String bookId, ReadingPosition position) async {
    readingPositionByBookId[bookId] = position;
    savedReadingPositionCalls.add(MapEntry(bookId, position));
  }

  @override
  Future<void> saveTotalCharacterCount(
      String bookId, int totalCharacterCount) async {
    totalCharacterCountByBookId[bookId] = totalCharacterCount;
    savedTotalCharacterCountCalls.add(MapEntry(bookId, totalCharacterCount));
  }

  @override
  ResolvedPreferences resolve(
    LoadedPrefs loaded, {
    WritingMode? autoDetectedWritingMode,
  }) =>
      _delegate.resolve(loaded, autoDetectedWritingMode: autoDetectedWritingMode);
}
