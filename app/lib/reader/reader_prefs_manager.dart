import 'book_reader_prefs.dart';
import 'global_reader_prefs.dart';
import 'resolved_preferences.dart';
import 'writing_mode.dart';

/// [ReaderPrefsManager.load] 回傳的「尚未解析」原始資料：單書覆寫值
/// （[BookReaderPrefs]，可能大部分欄位是 null）與全域預設值（
/// [GlobalReaderPrefs]，non-nullable）。呼叫端把這個物件連同（若有）自動
/// 偵測到的排版方向一起交給 [ReaderPrefsManager.resolve]（純同步函式）
/// 求出最終生效值，兩者刻意分離：`load` 是唯一需要 async 的地方，
/// `resolve` 可在任何時機（含原生 layout 解析完成的同步回呼內）重複呼叫
/// 而不必再等一次儲存層 I/O。
class LoadedPrefs {
  final BookReaderPrefs bookPrefs;
  final GlobalReaderPrefs globalPrefs;

  const LoadedPrefs({required this.bookPrefs, required this.globalPrefs});
}

/// 偏好設定的載入／持久化／解析深模組，取代 `ReaderScreen` 原本直接依賴
/// `BookReaderPrefsRepository`（SQLite）與 `GlobalReaderDefaults`
/// （SharedPreferences）兩條路徑的做法。
abstract class ReaderPrefsManager {
  /// 一次載入單書覆寫值與全域預設值（原本 `ReaderScreen.initState` 裡
  /// 3 個平行 Future 中的 2 個，見 Task 3）。
  Future<LoadedPrefs> load(String bookId);

  Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs);
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs);

  /// 純同步合併（單書覆寫 `??` 全域預設／既存安全預設值），不觸發任何
  /// I/O，可在同一個 `setState` 內依需要重複呼叫（例如原生 layout 解析
  /// 完成後才拿到 [autoDetectedWritingMode]，需要重新求值）。
  ResolvedPreferences resolve(
    LoadedPrefs loaded, {
    WritingMode? autoDetectedWritingMode,
  });
}
