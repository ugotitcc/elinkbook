import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/writing_mode.dart';

/// 供 `reader_screen_test.dart` 使用的假 [ReaderPrefsManager]：`load`／
/// `save*` 皆為純記憶體內操作；`resolve` 直接委派給
/// [ReaderPrefsManagerImpl.resolve]（純函式、無 I/O，不需要另外假造）以
/// 確保測試驗證的合併邏輯與正式實作完全一致。
class FakeReaderPrefsManager implements ReaderPrefsManager {
  final Map<String, BookReaderPrefs> bookPrefsByBookId;
  GlobalReaderPrefs globalPrefs;
  final List<String> savedBookPrefsCalls = [];
  final List<GlobalReaderPrefs> savedGlobalPrefsCalls = [];

  FakeReaderPrefsManager({
    Map<String, BookReaderPrefs>? bookPrefsByBookId,
    this.globalPrefs = const GlobalReaderPrefs.initial(),
  }) : bookPrefsByBookId = bookPrefsByBookId ?? {};

  final _delegate = ReaderPrefsManagerImpl(null as dynamic);

  @override
  Future<LoadedPrefs> load(String bookId) async {
    return LoadedPrefs(
      bookPrefs: bookPrefsByBookId[bookId] ?? BookReaderPrefs.empty,
      globalPrefs: globalPrefs,
    );
  }

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
  ResolvedPreferences resolve(
    LoadedPrefs loaded, {
    WritingMode? autoDetectedWritingMode,
  }) =>
      _delegate.resolve(loaded, autoDetectedWritingMode: autoDetectedWritingMode);
}
