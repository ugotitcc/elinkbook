import 'book_reader_prefs.dart';
import 'global_reader_prefs.dart';
import 'reading_position.dart';
import 'resolved_preferences.dart';
import 'writing_mode.dart';

/// [ReaderPrefsManager.load] 回傳的「尚未解析」原始資料：單書覆寫值
/// （[BookReaderPrefs]，可能大部分欄位是 null）、全域預設值（
/// [GlobalReaderPrefs]，non-nullable）與本機閱讀位置（[readingPosition]，
/// epic-5-toc-pagination Issue 2 新增，non-nullable——無記錄時為
/// `ReadingPosition()` 預設值）。呼叫端把這個物件連同（若有）自動偵測到
/// 的排版方向一起交給 [ReaderPrefsManager.resolve]（純同步函式）求出最終
/// 生效值，兩者刻意分離：`load` 是唯一需要 async 的地方，`resolve` 可在
/// 任何時機（含原生 layout 解析完成的同步回呼內）重複呼叫而不必再等一次
/// 儲存層 I/O。
class LoadedPrefs {
  final BookReaderPrefs bookPrefs;
  final GlobalReaderPrefs globalPrefs;
  final ReadingPosition readingPosition;
  final int? totalCharacterCount;

  const LoadedPrefs({
    required this.bookPrefs,
    required this.globalPrefs,
    this.readingPosition = const ReadingPosition(),
    this.totalCharacterCount,
  });
}

/// 偏好設定與本機閱讀位置的載入／持久化／解析深模組，取代 `ReaderScreen`
/// 原本直接依賴 `BookReaderPrefsRepository`（SQLite）與 `GlobalReaderDefaults`
/// （SharedPreferences）兩條路徑的做法。
abstract class ReaderPrefsManager {
  /// 一次載入單書覆寫值、全域預設值與本機閱讀位置（原本 `ReaderScreen.initState`
  /// 裡 3 個平行 Future 中的 2 個，見 Task 3；epic-5-toc-pagination Issue 2
  /// 新增第 3 個平行讀取）。
  Future<LoadedPrefs> load(String bookId);

  Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs);
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs);

  /// 寫入本機閱讀位置（epic-5-toc-pagination Issue 2）。呼叫時機固定為
  /// `ReaderScreen.dispose()` 與 App 進入背景時各一次，不逐次翻頁/捲動
  /// 呼叫（見 docs/epics/epic-5-toc-pagination/spec.md「本機閱讀位置
  /// 記憶」）。
  Future<void> saveReadingPosition(String bookId, ReadingPosition position);

  /// 寫入全書字元數快取（epic-5-toc-pagination Issue 3）。呼叫時機為原生端
  /// 背景計算完成、透過 EpubReaderView.onCharacterCountReady 回報之後，
  /// 只在該書尚無快取值時觸發一次（見 spec.md「執行緒與快取」）。
  Future<void> saveTotalCharacterCount(String bookId, int totalCharacterCount);

  /// 純同步合併（單書覆寫 `??` 全域預設／既存安全預設值），不觸發任何
  /// I/O，可在同一個 `setState` 內依需要重複呼叫（例如原生 layout 解析
  /// 完成後才拿到 [autoDetectedWritingMode]，需要重新求值）。
  ResolvedPreferences resolve(
    LoadedPrefs loaded, {
    WritingMode? autoDetectedWritingMode,
  });
}
