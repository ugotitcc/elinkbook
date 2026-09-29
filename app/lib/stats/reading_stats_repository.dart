// app/lib/stats/reading_stats_repository.dart
import 'daily_book_reading_stat.dart';

/// 每日閱讀統計的存取介面（epic-9-stats，見 spec.md「核心介面」）。
///
/// 日期一律是裝置本地日期字串 `YYYY-MM-DD`（字串比較即等同日期先後比較）。
/// 本介面刻意不提供依書籍查詢：統計畫面只需要「每日總計」、「某日各書」與
/// 「累計總和」三種讀法。
abstract class ReadingStatsRepository {
  /// 把 [seconds] 累加到 [date]、[bookId] 這一筆，並以 [bookTitle] 覆寫該筆
  /// 的書名快照（書被改名後，仍保留的統計顯示最新書名）。
  ///
  /// [seconds] 小於等於 0 時不做任何事：統計只增不減，任何呼叫端的計算錯誤
  /// 都不能讓已累計的時數被倒扣。
  Future<void> addReadingSeconds({
    required String date,
    required String bookId,
    required String bookTitle,
    required int seconds,
  });

  /// 日期區間（含起訖日）內每一天的總秒數（該日全部書籍加總），key 為
  /// `YYYY-MM-DD`。沒有紀錄的日期不會出現在結果中。結果的鍵依日期由早到晚
  /// 排列（遍歷時順序固定，不因實作而異）。[startDate] 晚於 [endDate] 時回傳
  /// 空 Map。
  Future<Map<String, int>> getDailyTotals({
    required String startDate,
    required String endDate,
  });

  /// [date] 這一天各書的閱讀秒數，依秒數由大到小排序；秒數相同時依書名、
  /// 再依書籍 id 由小到大，讓結果固定。該日沒有紀錄時回傳空清單。
  Future<List<DailyBookReadingStat>> getBookStatsForDate(String date);

  /// 全部紀錄的秒數總和；沒有任何紀錄時為 0。
  Future<int> getTotalReadingSeconds();

  /// 清除全部統計，完成後透過 [onCleared] 通知。
  Future<void> clearAllStats();

  /// 每次 [clearAllStats] 完成後發出一次事件。廣播 Stream，可有多個監聽者
  /// （例如正在閱讀中的每一本書各有一個計時器），沒有監聽者時事件直接丟棄。
  Stream<void> get onCleared;
}
