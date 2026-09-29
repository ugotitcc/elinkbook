# Epic 9 Issue 2：資料層——每日閱讀統計儲存 — 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增每日閱讀統計的本機儲存：SQLite schema v27 的 `daily_reading_stats` 表、`ReadingStatsRepository` 抽象介面與 SQLite 實作、共用測試替身 `FakeReadingStatsRepository`，以及清除完成事件 `onCleared`。

**Architecture:**
- 新增 `app/lib/stats/` 目錄。抽象介面與模型不依賴 SQLite；SQLite 實作直接對 `Database` 下 SQL（比照 `SqliteSearchRepository`），不經 `LibraryRepository`。
- 資料表以 `(date, book_id)` 為主鍵、**不設任何外鍵**（連線全程 `PRAGMA foreign_keys = ON`，外鍵會讓刪書失敗或抹掉歷史時數）；寫入用 upsert 累加並覆寫書名快照；所有查詢不 JOIN `books`。
- 正式實作與測試替身共用**同一組契約測試**，確保 Issue 4、5 用替身驗證的結果與真實資料庫一致。

**Tech Stack:** Flutter／Dart 3、`sqflite`（正式）與 `sqflite_common_ffi`（測試）、`package:clock`、`flutter_test`。

**Spec:** [`../spec.md`](../spec.md)（「核心介面」「資料表（schema v27）」「清除全部統計」三段）、[`../issues.md`](../issues.md) Issue 2

## Global Constraints

- 介面簽章逐字照 spec「核心介面」：`DailyBookReadingStat`（`bookId`、`bookTitle`、`readingSeconds`）、`ReadingStatsRepository`（`addReadingSeconds`、`getDailyTotals`、`getBookStatsForDate`、`getTotalReadingSeconds`、`clearAllStats`、`Stream<void> get onCleared`）。日期一律為 `YYYY-MM-DD` 本地日期字串。
- 資料表 DDL 逐字照 spec：`daily_reading_stats(date TEXT NOT NULL, book_id TEXT NOT NULL, book_title TEXT NOT NULL, reading_seconds INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL, PRIMARY KEY (date, book_id))`，另建索引 `idx_daily_reading_stats_date ON daily_reading_stats(date)`。**嚴禁宣告外鍵。**
- 「當日詳情」與「累計總時數」的查詢**不得 JOIN `books`**，直接讀本表。
- upsert：主鍵衝突時 `reading_seconds` 累加、`book_title` 以最新值覆寫、`updated_at` 更新。
- `getDailyTotals` 回傳的 Map，鍵依日期由早到晚排列（SQLite 以 `ORDER BY date ASC`，Fake 以排序保證），兩種實作遍歷順序一致。
- `FakeReadingStatsRepository` 提供 `Object? addReadingSecondsError`：非 null 時 `addReadingSeconds` 拋出它，供 Issue 4 驗證「寫入失敗不影響閱讀」。
- `onCleared` 為廣播 Stream，可有多個監聽者；每次 `clearAllStats()` 完成後發出一次事件（沒有資料時也發）。
- 本計畫補充兩項 spec 未明說的決定：`seconds` 小於等於 0 時 `addReadingSeconds` 不做任何事（統計只增不減）；`getBookStatsForDate` 秒數相同時依書名再依書籍 id 由小到大排序，讓結果固定。
- schema 升級遵守既有 `onUpgrade` 慣例：全新獨立表無條件建立（`if (oldVersion < 27)`）；不得動到既有資料。
- 本計畫**不接** `main.dart`、`LibraryReaderFeatureRepositories` 或 `ReaderScreen`（那是 Issue 4）。
- 程式碼註解一律使用正體中文；提交前 `flutter analyze` 須乾淨。

## Review Focus

以下是 spec 隱含、但主要驗收條件沒有直接涵蓋，最可能讓使用者踩到的情況（最可能的在前）：

1. **同一筆同時多次累加**（計時器 flush 重疊）：秒數不遺失。→ 契約測試「同一筆同時多次累加」。
2. **書名含單引號、雙引號、emoji、SQL 關鍵字**：原樣存取，不被當成 SQL。→ 契約測試「書名含單引號…」。
3. **區間查詢跨月、跨年**：字串比較與日曆先後一致。→ 契約測試「區間查詢跨月、跨年」。
4. **清除事件送達時資料已清空**：監聽者（各書的計時器）收到事件時若立刻讀資料，不能讀到舊資料。→ 契約測試「onCleared 事件送達時…」。
5. **秒數為 0 或負數**：不建立紀錄、不倒扣。→ 契約測試「秒數為 0 或負數」。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/stats/daily_book_reading_stat.dart` | 新增 | 單日單書統計的資料模型 |
| `app/lib/stats/reading_stats_repository.dart` | 新增 | 抽象介面（Issue 3～5 依賴的唯一契約） |
| `app/lib/stats/sqlite_reading_stats_repository.dart` | 新增 | SQLite 正式實作 |
| `app/lib/library/sqlite_library_repository.dart` | 修改 | schema 升為 v27：`onCreate`／`onUpgrade` 建立 `daily_reading_stats` |
| `app/test/support/fake_reading_stats_repository.dart` | 新增 | 記憶體內測試替身，供 Issue 4、5 共用 |
| `app/test/support/fake_reading_stats_repository_test.dart` | 新增 | 替身跑共用契約測試 |
| `app/test/stats/reading_stats_repository_contract.dart` | 新增 | 共用契約測試（不是獨立測試檔，由上下兩個測試檔呼叫） |
| `app/test/stats/daily_reading_stats_schema_test.dart` | 新增 | 資料表 schema、無外鍵、升級遷移（只用原生 SQL） |
| `app/test/stats/sqlite_reading_stats_repository_test.dart` | 新增 | SQLite 實作跑共用契約測試＋專屬行為 |
| `app/test/library/sqlite_library_repository_test.dart` | 修改 | 兩處版本號斷言 26 → 27 |

以下所有指令都在 `app/` 目錄下執行。

---

### Task 1：資料模型、抽象介面、測試替身與共用契約測試

**Files:**
- Create: `app/lib/stats/daily_book_reading_stat.dart`
- Create: `app/lib/stats/reading_stats_repository.dart`
- Create: `app/test/stats/reading_stats_repository_contract.dart`
- Create: `app/test/support/fake_reading_stats_repository.dart`
- Test: `app/test/support/fake_reading_stats_repository_test.dart`

**Interfaces:**
- Consumes: 無。
- Produces（Task 2、3 與 Issue 3～5 依賴，名稱與簽章固定）：
  - `class DailyBookReadingStat { final String bookId; final String bookTitle; final int readingSeconds; const DailyBookReadingStat({required ...}); }`（有 `==`／`hashCode`）
  - `abstract class ReadingStatsRepository`：`Future<void> addReadingSeconds({required String date, required String bookId, required String bookTitle, required int seconds})`、`Future<Map<String, int>> getDailyTotals({required String startDate, required String endDate})`、`Future<List<DailyBookReadingStat>> getBookStatsForDate(String date)`、`Future<int> getTotalReadingSeconds()`、`Future<void> clearAllStats()`、`Stream<void> get onCleared`
  - `void runReadingStatsRepositoryContract(String label, Future<ReadingStatsRepository> Function() create)`
  - `class FakeReadingStatsRepository implements ReadingStatsRepository`（建構子選用參數 `Map<String, List<DailyBookReadingStat>> initialStats`）

- [ ] **Step 1: 建立資料模型與抽象介面**

建立 `app/lib/stats/daily_book_reading_stat.dart`：

```dart
// app/lib/stats/daily_book_reading_stat.dart

/// 某一天、某一本書的累計閱讀秒數（epic-9-stats，見 spec.md「核心介面」）。
///
/// [bookTitle] 是寫入當下的書名快照：書被刪除後這筆統計仍保留，詳情畫面
/// 直接顯示這個快照，不回頭查 `books` 表。
class DailyBookReadingStat {
  final String bookId;
  final String bookTitle;
  final int readingSeconds;

  const DailyBookReadingStat({
    required this.bookId,
    required this.bookTitle,
    required this.readingSeconds,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyBookReadingStat &&
          other.bookId == bookId &&
          other.bookTitle == bookTitle &&
          other.readingSeconds == readingSeconds;

  @override
  int get hashCode => Object.hash(bookId, bookTitle, readingSeconds);

  @override
  String toString() =>
      'DailyBookReadingStat($bookId, $bookTitle, $readingSeconds)';
}
```

建立 `app/lib/stats/reading_stats_repository.dart`：

```dart
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
```

Run: `flutter analyze lib/stats`
Expected: `No issues found!`

- [ ] **Step 2: 寫共用契約測試與替身的測試檔（此時替身還不存在）**

建立 `app/test/stats/reading_stats_repository_contract.dart`（共用契約，不是獨立測試檔）：

```dart
// app/test/stats/reading_stats_repository_contract.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/stats/daily_book_reading_stat.dart';
import 'package:elinkbook/stats/reading_stats_repository.dart';

/// [ReadingStatsRepository] 的共用契約測試（epic-9-stats Issue 2）。
///
/// 正式實作（SQLite）與測試替身（Fake）都必須通過同一組案例，確保 Issue 4、
/// Issue 5 用替身驗證的結果，與真實資料庫的行為一致。
void runReadingStatsRepositoryContract(
  String label,
  Future<ReadingStatsRepository> Function() create,
) {
  group('ReadingStatsRepository 契約（$label）', () {
    late ReadingStatsRepository repo;

    setUp(() async {
      repo = await create();
    });

    test('同日同書多次累加：秒數相加', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 60);
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 90);

      expect(await repo.getBookStatsForDate('2026-09-29'), [
        const DailyBookReadingStat(
            bookId: 'b1', bookTitle: '書', readingSeconds: 150),
      ]);
    });

    test('不同書、不同日各自獨立累計', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: 'A', seconds: 10);
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b2', bookTitle: 'B', seconds: 20);
      await repo.addReadingSeconds(
          date: '2026-09-30', bookId: 'b1', bookTitle: 'A', seconds: 30);

      expect(await repo.getDailyTotals(
              startDate: '2026-09-29', endDate: '2026-09-30'),
          {'2026-09-29': 30, '2026-09-30': 30});
    });

    test('書名快照以最新一次寫入為準', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '舊書名', seconds: 60);
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '新書名', seconds: 60);

      final stats = await repo.getBookStatsForDate('2026-09-29');
      expect(stats.single.bookTitle, '新書名');
      expect(stats.single.readingSeconds, 120);
    });

    test('秒數為 0 或負數：不建立紀錄、也不倒扣既有紀錄', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 0);
      expect(await repo.getBookStatsForDate('2026-09-29'), isEmpty);

      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 100);
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: -40);
      expect((await repo.getBookStatsForDate('2026-09-29')).single.readingSeconds,
          100);
    });

    test('getDailyTotals：含起訖日、只回傳有紀錄的日期、同日多本書加總', () async {
      Future<void> add(String d, String b, int s) => repo.addReadingSeconds(
          date: d, bookId: b, bookTitle: b, seconds: s);
      await add('2026-09-27', 'b1', 5); // 區間外（起日之前）
      await add('2026-09-28', 'b1', 10); // 起日
      await add('2026-09-28', 'b2', 20); // 同日另一本
      await add('2026-09-30', 'b1', 40); // 訖日
      await add('2026-10-01', 'b1', 80); // 區間外（訖日之後）

      expect(
        await repo.getDailyTotals(startDate: '2026-09-28', endDate: '2026-09-30'),
        {'2026-09-28': 30, '2026-09-30': 40},
      );
    });

    test('getDailyTotals：鍵依日期由早到晚排列，與寫入順序無關', () async {
      Future<void> add(String d) => repo.addReadingSeconds(
          date: d, bookId: 'b1', bookTitle: '書', seconds: 10);
      await add('2026-09-30'); // 故意由新到舊寫入
      await add('2026-09-28');
      await add('2026-09-29');

      final totals = await repo.getDailyTotals(
          startDate: '2026-09-01', endDate: '2026-09-30');
      expect(totals.keys.toList(), ['2026-09-28', '2026-09-29', '2026-09-30']);
    });

    test('getDailyTotals：起日晚於訖日時回傳空 Map', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 10);
      expect(
        await repo.getDailyTotals(startDate: '2026-09-30', endDate: '2026-09-28'),
        isEmpty,
      );
    });

    test('getBookStatsForDate：依秒數由大到小，同秒數依書名再依 id', () async {
      Future<void> add(String id, String title, int s) => repo.addReadingSeconds(
          date: '2026-09-29', bookId: id, bookTitle: title, seconds: s);
      await add('b3', 'C', 50);
      await add('b1', 'B', 100);
      await add('b2', 'A', 100);
      await add('b0', 'A', 100); // 書名與 b2 相同，依 id 排在 b2 之前

      final stats = await repo.getBookStatsForDate('2026-09-29');
      expect(stats.map((s) => s.bookId).toList(), ['b0', 'b2', 'b1', 'b3']);
    });

    test('getBookStatsForDate：該日沒有紀錄時回傳空清單', () async {
      expect(await repo.getBookStatsForDate('2026-01-01'), isEmpty);
    });

    test('getTotalReadingSeconds：全部紀錄加總；沒有紀錄為 0', () async {
      expect(await repo.getTotalReadingSeconds(), 0);
      await repo.addReadingSeconds(
          date: '2026-09-28', bookId: 'b1', bookTitle: 'A', seconds: 100);
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b2', bookTitle: 'B', seconds: 250);
      expect(await repo.getTotalReadingSeconds(), 350);
    });

    test('clearAllStats：清空全部資料，之後仍可再累加', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 60);
      await repo.clearAllStats();

      expect(await repo.getTotalReadingSeconds(), 0);
      expect(await repo.getBookStatsForDate('2026-09-29'), isEmpty);

      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 5);
      expect(await repo.getTotalReadingSeconds(), 5);
    });

    test('onCleared：每次清除發出一次事件，多個監聽者都收到', () async {
      var first = 0;
      var second = 0;
      final sub1 = repo.onCleared.listen((_) => first++);
      final sub2 = repo.onCleared.listen((_) => second++);
      addTearDown(sub1.cancel);
      addTearDown(sub2.cancel);

      await repo.clearAllStats();
      await pumpEventQueue();
      expect((first, second), (1, 1));

      await repo.clearAllStats(); // 沒有資料時清除也要發出事件
      await pumpEventQueue();
      expect((first, second), (2, 2));
    });

    test('onCleared：沒有監聽者時清除不拋例外', () async {
      await repo.clearAllStats();
    });

    // ---- 審查重點：規格沒明說、但使用者最可能碰到的輸入 ----

    test('區間查詢跨月、跨年：日期字串比較與日曆先後一致', () async {
      Future<void> add(String d) => repo.addReadingSeconds(
          date: d, bookId: 'b1', bookTitle: '書', seconds: 10);
      await add('2025-12-31');
      await add('2026-01-01');
      await add('2026-01-31');
      await add('2026-02-01');

      expect(
        await repo.getDailyTotals(startDate: '2025-12-30', endDate: '2026-01-02'),
        {'2025-12-31': 10, '2026-01-01': 10},
      );
      expect(
        await repo.getDailyTotals(startDate: '2026-01-01', endDate: '2026-01-31'),
        {'2026-01-01': 10, '2026-01-31': 10},
      );
    });

    test('書名含單引號、雙引號、emoji 與 SQL 關鍵字：原樣存取，不被當成 SQL', () async {
      const title = "O'Brien \"書\"; DROP TABLE daily_reading_stats; -- 😀";
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: title, seconds: 60);

      final stats = await repo.getBookStatsForDate('2026-09-29');
      expect(stats.single.bookTitle, title);
      expect(await repo.getTotalReadingSeconds(), 60);
    });

    test('同一筆同時多次累加（例如計時器 flush 重疊）：秒數不遺失', () async {
      await Future.wait([
        for (var i = 0; i < 20; i++)
          repo.addReadingSeconds(
              date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 5),
      ]);

      expect(await repo.getTotalReadingSeconds(), 100);
    });

    test('onCleared 事件送達時，資料已經清空（監聽者不會讀到舊資料）', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 60);

      final totalSeenByListener = <int>[];
      final sub = repo.onCleared.listen((_) {
        repo.getTotalReadingSeconds().then(totalSeenByListener.add);
      });
      addTearDown(sub.cancel);

      await repo.clearAllStats();
      await pumpEventQueue();

      expect(totalSeenByListener, [0]);
    });
  });
}
```

建立 `app/test/support/fake_reading_stats_repository_test.dart`：

```dart
// app/test/support/fake_reading_stats_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/stats/daily_book_reading_stat.dart';

import '../stats/reading_stats_repository_contract.dart';
import 'fake_reading_stats_repository.dart';

void main() {
  runReadingStatsRepositoryContract(
    'FakeReadingStatsRepository',
    () async => FakeReadingStatsRepository(),
  );

  group('FakeReadingStatsRepository 輔助功能', () {
    test('initialStats 預先填入的資料可被查詢', () async {
      final repo = FakeReadingStatsRepository(initialStats: {
        '2026-09-29': [
          const DailyBookReadingStat(
              bookId: 'b1', bookTitle: '書', readingSeconds: 300),
        ],
      });
      expect(await repo.getTotalReadingSeconds(), 300);
      expect((await repo.getBookStatsForDate('2026-09-29')).single.bookId, 'b1');
    });

    test('addReadingSecondsError 非 null 時 addReadingSeconds 拋出它且不寫入；清除後恢復正常',
        () async {
      final repo = FakeReadingStatsRepository()
        ..addReadingSecondsError = StateError('模擬寫入失敗');

      await expectLater(
        repo.addReadingSeconds(
            date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 60),
        throwsA(isA<StateError>()),
      );
      expect(await repo.getTotalReadingSeconds(), 0);

      repo.addReadingSecondsError = null;
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 60);
      expect(await repo.getTotalReadingSeconds(), 60);
    });
  });
}
```

- [ ] **Step 3: 執行測試確認失敗**

Run: `flutter test test/support/fake_reading_stats_repository_test.dart`
Expected: 編譯失敗，訊息含 `fake_reading_stats_repository.dart` 找不到（`Target of URI doesn't exist`）。

- [ ] **Step 4: 實作測試替身**

建立 `app/test/support/fake_reading_stats_repository.dart`：

```dart
// app/test/support/fake_reading_stats_repository.dart
import 'dart:async';

import 'package:elinkbook/stats/daily_book_reading_stat.dart';
import 'package:elinkbook/stats/reading_stats_repository.dart';

/// 供 widget／單元測試使用的記憶體內 [ReadingStatsRepository] 假實作
/// （epic-9-stats Issue 2），行為與 `SqliteReadingStatsRepository` 一致，
/// 兩者共用同一組契約測試（`reading_stats_repository_contract.dart`）。
class FakeReadingStatsRepository implements ReadingStatsRepository {
  /// [initialStats]：預先填入的資料，`date -> 該日書籍統計清單`。
  FakeReadingStatsRepository({
    Map<String, List<DailyBookReadingStat>> initialStats = const {},
  }) {
    initialStats.forEach((date, list) {
      for (final s in list) {
        _rows[(date, s.bookId)] = s;
      }
    });
  }

  final Map<(String, String), DailyBookReadingStat> _rows = {};
  final StreamController<void> _clearedController =
      StreamController<void>.broadcast();

  /// 測試用：非 null 時 [addReadingSeconds] 會拋出它，模擬資料庫寫入失敗
  /// （供 Issue 4 驗證 ReaderScreen 寫入失敗時不崩潰、不中斷閱讀）。
  Object? addReadingSecondsError;

  @override
  Future<void> addReadingSeconds({
    required String date,
    required String bookId,
    required String bookTitle,
    required int seconds,
  }) async {
    if (addReadingSecondsError != null) throw addReadingSecondsError!;
    if (seconds <= 0) return;
    final existing = _rows[(date, bookId)];
    _rows[(date, bookId)] = DailyBookReadingStat(
      bookId: bookId,
      bookTitle: bookTitle,
      readingSeconds: (existing?.readingSeconds ?? 0) + seconds,
    );
  }

  @override
  Future<Map<String, int>> getDailyTotals({
    required String startDate,
    required String endDate,
  }) async {
    final totals = <String, int>{};
    _rows.forEach((key, stat) {
      final date = key.$1;
      if (date.compareTo(startDate) >= 0 && date.compareTo(endDate) <= 0) {
        totals[date] = (totals[date] ?? 0) + stat.readingSeconds;
      }
    });
    // 與 SQLite 實作一致：鍵依日期由早到晚排列
    final sortedDates = totals.keys.toList()..sort();
    return {for (final d in sortedDates) d: totals[d]!};
  }

  @override
  Future<List<DailyBookReadingStat>> getBookStatsForDate(String date) async {
    final list = [
      for (final e in _rows.entries)
        if (e.key.$1 == date) e.value,
    ];
    list.sort((a, b) {
      final bySeconds = b.readingSeconds.compareTo(a.readingSeconds);
      if (bySeconds != 0) return bySeconds;
      final byTitle = a.bookTitle.compareTo(b.bookTitle);
      if (byTitle != 0) return byTitle;
      return a.bookId.compareTo(b.bookId);
    });
    return list;
  }

  @override
  Future<int> getTotalReadingSeconds() async =>
      _rows.values.fold<int>(0, (sum, s) => sum + s.readingSeconds);

  @override
  Future<void> clearAllStats() async {
    _rows.clear();
    _clearedController.add(null);
  }

  @override
  Stream<void> get onCleared => _clearedController.stream;
}
```

- [ ] **Step 5: 執行測試確認通過**

Run: `flutter test test/support/fake_reading_stats_repository_test.dart`
Expected: `All tests passed!`，共 19 個測試（契約 17 個＋替身輔助 2 個）。

- [ ] **Step 6: 靜態分析並提交**

Run: `flutter analyze lib/stats test/stats test/support`
Expected: `No issues found!`

```bash
git add lib/stats/daily_book_reading_stat.dart lib/stats/reading_stats_repository.dart test/stats/reading_stats_repository_contract.dart test/support/fake_reading_stats_repository.dart test/support/fake_reading_stats_repository_test.dart
git commit -m "feat(stats): epic-9 Issue 2 閱讀統計資料模型、介面、測試替身與共用契約測試"
```

---

### Task 2：SQLite schema 升為 v27（`daily_reading_stats` 資料表）

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`（`version: 26` → `27`、`onCreate`、`onUpgrade`、新增建表函式）
- Modify: `app/test/library/sqlite_library_repository_test.dart`（兩處版本號斷言）
- Test: `app/test/stats/daily_reading_stats_schema_test.dart`

**Interfaces:**
- Consumes: 無（本 Task 只用原生 SQL 驗證資料表，不依賴 Task 3 的類別）。
- Produces: 資料表 `daily_reading_stats`（欄位與索引見 Global Constraints）；`SqliteLibraryRepository.open()` 開出的資料庫 `version` 為 27。

- [ ] **Step 1: 寫 schema 測試，並更新既有的版本號斷言**

建立 `app/test/stats/daily_reading_stats_schema_test.dart`：

```dart
// app/test/stats/daily_reading_stats_schema_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';

Book _book(String id, {String title = '書名'}) => Book(
      id: id,
      title: title,
      format: BookFileFormat.epub,
      filePath: '/books/$id',
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );

/// `daily_reading_stats` 資料表的 schema 測試（epic-9-stats Issue 2，DB v27）。
/// 只用原生 SQL 驗證資料表本身，不依賴 `SqliteReadingStatsRepository`。
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('全新安裝：version 27，資料表與日期索引存在，主鍵為（date, book_id）', () async {
    final library = await SqliteLibraryRepository.open(inMemoryDatabasePath,
        singleInstance: false);
    addTearDown(library.close);
    final db = library.database;

    expect(await db.getVersion(), 27);

    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='daily_reading_stats'");
    expect(tables, hasLength(1));

    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_daily_reading_stats_date'");
    expect(indexes, hasLength(1));

    // 主鍵欄位（pk > 0）依主鍵順序為 date、book_id
    final columns = await db.rawQuery('PRAGMA table_info(daily_reading_stats)');
    final pk = columns.where((c) => (c['pk'] as int) > 0).toList()
      ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
    expect(pk.map((c) => c['name']).toList(), ['date', 'book_id']);
  });

  test('沒有任何外鍵；刪除書籍後統計列仍在，刪書本身不受影響', () async {
    final library = await SqliteLibraryRepository.open(inMemoryDatabasePath,
        singleInstance: false);
    addTearDown(library.close);
    final db = library.database;

    expect(await db.rawQuery('PRAGMA foreign_key_list(daily_reading_stats)'),
        isEmpty,
        reason: '嚴禁對 book_id 宣告外鍵：連線全程 foreign_keys = ON，'
            'RESTRICT 會讓刪書失敗、CASCADE 會抹掉歷史時數');

    await library.insertBook(_book('b1', title: '會被刪除的書'));
    await db.insert('daily_reading_stats', {
      'date': '2026-09-29',
      'book_id': 'b1',
      'book_title': '會被刪除的書',
      'reading_seconds': 600,
      'updated_at': 1000,
    });

    await library.deleteBook('b1'); // 不得拋例外

    expect(await library.listBooks(), isEmpty);
    final rows = await db.query('daily_reading_stats');
    expect(rows.single['book_title'], '會被刪除的書');
    expect(rows.single['reading_seconds'], 600);
  });

  test('既有 version 26 裝置升級到 27：既有資料完整保留，新表建立且為空，重開不重建',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v26_to_v27_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 26,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('CREATE TABLE books (id TEXT PRIMARY KEY)');
          await db.insert('books', {'id': 'legacy-book'});
        },
      ),
    );
    await oldDb.close();

    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    expect(await upgraded.database.getVersion(), 27);
    final legacy = await upgraded.database.query('books');
    expect(legacy.single['id'], 'legacy-book', reason: '升級不得動到既有資料');
    expect(await upgraded.database.query('daily_reading_stats'), isEmpty);

    await upgraded.database.insert('daily_reading_stats', {
      'date': '2026-09-29',
      'book_id': 'b1',
      'book_title': '書',
      'reading_seconds': 30,
      'updated_at': 1000,
    });

    // 重新開啟（不觸發 onUpgrade）：資料仍在、不會因重複建表而拋例外
    await upgraded.close();
    final reopened = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => reopened.close());
    final rows = await reopened.database.query('daily_reading_stats');
    expect(rows.single['reading_seconds'], 30);
  });
}
```

在 `app/test/library/sqlite_library_repository_test.dart` 檔案最後一個測試，把兩處 `26` 改成 `27`：

```dart
    test('全新安裝（onCreate 直接建到 version 27）：isFullTextSearchAvailable 為 true，'
        '行為與現行版本一致（零回歸）', () async {
      expect(repository.isFullTextSearchAvailable, isTrue);
      expect(await repository.database.getVersion(), 27);
    });
```

（原本是 `version 26` 與 `getVersion(), 26`，只改這兩處。）

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/stats/daily_reading_stats_schema_test.dart test/library/sqlite_library_repository_test.dart`
Expected: FAIL：`daily_reading_stats_schema_test` 三個案例都失敗（版本仍是 26、資料表不存在）；`sqlite_library_repository_test` 最後一個案例失敗（`Expected: <27> Actual: <26>`）。

- [ ] **Step 3: 修改 `sqlite_library_repository.dart`（共四處）**

注意：工作目錄的 `.dart` 檔案是 CRLF（`core.autocrlf=true`）。用 Edit 工具時若多行 `old_string` 比對失敗，改成逐行編輯。

**(a)** 把 `openDatabase` 的版本號改為 27。`old_string`：

```dart
      version: 26,
```

`new_string`：

```dart
      version: 27,
```

**(b)** `onCreate` 尾端加入建表。`old_string`（唯一，緊接著是 `onUpgrade`）：

```dart
        await _createBookContentFtsTableIfSupported(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
```

`new_string`：

```dart
        await _createBookContentFtsTableIfSupported(db);
        await _createDailyReadingStatsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
```

**(c)** `onUpgrade` 尾端加入 v27 分支。`old_string`：

```dart
          if (existing.isEmpty) {
            await _createBookContentFtsTableIfSupported(db);
          }
        }
      },
      onOpen: (db) async {
```

`new_string`：

```dart
          if (existing.isEmpty) {
            await _createBookContentFtsTableIfSupported(db);
          }
        }
        if (oldVersion < 27) {
          // epic-9-stats Issue 2：每日閱讀統計，全新獨立表（非既有表新增
          // 欄位），比照 bookmarks（oldVersion < 8）／custom_fonts
          // （oldVersion < 16）既有原則，無條件建立即可。
          await _createDailyReadingStatsTable(db);
        }
      },
      onOpen: (db) async {
```

**(d)** 新增建表函式，放在 `_createContentIndexStatusTable` 的文件註解之前。`old_string`：

```dart
  /// 每本書的全文檢索索引進度狀態，含背景排程的續跑游標
```

`new_string`：

```dart
  /// 每日閱讀統計（epic-9-stats Issue 2，見 spec.md「資料表（schema v27）」）。
  ///
  /// **刻意不宣告任何外鍵**：連線全程開著 PRAGMA foreign_keys = ON，若
  /// book_id 參照 books(id)，RESTRICT 會讓刪書失敗、CASCADE 會抹掉「書被
  /// 刪除後仍保留時數」的歷史。book_id 只是弱關聯的文字欄位，書名快照
  /// （book_title）讓已刪除的書仍能顯示名稱。
  static Future<void> _createDailyReadingStatsTable(Database db) async {
    await db.execute('''
      CREATE TABLE daily_reading_stats (
        date TEXT NOT NULL,
        book_id TEXT NOT NULL,
        book_title TEXT NOT NULL,
        reading_seconds INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (date, book_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_daily_reading_stats_date ON daily_reading_stats(date)');
  }

  /// 每本書的全文檢索索引進度狀態，含背景排程的續跑游標
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/stats/daily_reading_stats_schema_test.dart test/library/sqlite_library_repository_test.dart`
Expected: `All tests passed!`（schema 3 個＋既有 `sqlite_library_repository_test` 全部通過，沒有回歸）。

- [ ] **Step 5: 靜態分析並提交**

Run: `flutter analyze lib/library/sqlite_library_repository.dart test/stats test/library/sqlite_library_repository_test.dart`
Expected: `No issues found!`

```bash
git add lib/library/sqlite_library_repository.dart test/library/sqlite_library_repository_test.dart test/stats/daily_reading_stats_schema_test.dart
git commit -m "feat(stats): epic-9 Issue 2 SQLite schema 升為 v27，新增 daily_reading_stats 資料表"
```

---

### Task 3：`SqliteReadingStatsRepository` 正式實作

**Files:**
- Create: `app/lib/stats/sqlite_reading_stats_repository.dart`
- Test: `app/test/stats/sqlite_reading_stats_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `ReadingStatsRepository`、`DailyBookReadingStat`、`runReadingStatsRepositoryContract`；Task 2 的資料表。
- Produces: `class SqliteReadingStatsRepository implements ReadingStatsRepository`，建構子 `SqliteReadingStatsRepository({required Database database})`（`Database` 來自 `package:sqflite/sqflite.dart`，正式環境傳入 `SqliteLibraryRepository.database`）。Issue 4 在 `main.dart` 用它建立實例。

- [ ] **Step 1: 寫 SQLite 實作的測試（呼叫共用契約，此時實作還不存在）**

建立 `app/test/stats/sqlite_reading_stats_repository_test.dart`：

```dart
// app/test/stats/sqlite_reading_stats_repository_test.dart
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/stats/sqlite_reading_stats_repository.dart';

import 'reading_stats_repository_contract.dart';

Book _book(String id, {String title = '書名'}) => Book(
      id: id,
      title: title,
      format: BookFileFormat.epub,
      filePath: '/books/$id',
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // 每個案例各開一個全新的記憶體資料庫（singleInstance: false，避免共用連線）
  final opened = <SqliteLibraryRepository>[];
  tearDown(() async {
    for (final r in opened) {
      await r.close();
    }
    opened.clear();
  });

  Future<SqliteLibraryRepository> openLibrary() async {
    final r = await SqliteLibraryRepository.open(inMemoryDatabasePath,
        singleInstance: false);
    opened.add(r);
    return r;
  }

  runReadingStatsRepositoryContract('SqliteReadingStatsRepository', () async {
    final library = await openLibrary();
    return SqliteReadingStatsRepository(database: library.database);
  });

  group('SqliteReadingStatsRepository 專屬行為', () {
    test('刪除書籍後：統計時數與書名快照仍可透過 repository 查到', () async {
      final library = await openLibrary();
      final stats = SqliteReadingStatsRepository(database: library.database);
      await library.insertBook(_book('b1', title: '會被刪除的書'));
      await stats.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '會被刪除的書', seconds: 600);

      await library.deleteBook('b1');

      expect(await stats.getTotalReadingSeconds(), 600);
      final detail = await stats.getBookStatsForDate('2026-09-29');
      expect(detail.single.bookTitle, '會被刪除的書');
      expect(detail.single.readingSeconds, 600);
    });

    test('updated_at 取自注入的時鐘，每次累加都會更新', () async {
      final library = await openLibrary();
      final stats = SqliteReadingStatsRepository(database: library.database);

      await withClock(
          Clock.fixed(DateTime.fromMillisecondsSinceEpoch(1000)),
          () => stats.addReadingSeconds(
              date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 10));
      await withClock(
          Clock.fixed(DateTime.fromMillisecondsSinceEpoch(2000)),
          () => stats.addReadingSeconds(
              date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 10));

      final rows = await library.database.query('daily_reading_stats');
      expect(rows.single['updated_at'], 2000);
      expect(rows.single['reading_seconds'], 20);
    });
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/stats/sqlite_reading_stats_repository_test.dart`
Expected: 編譯失敗，訊息含 `sqlite_reading_stats_repository.dart` 找不到（`Target of URI doesn't exist`）。

- [ ] **Step 3: 實作 SQLite repository**

建立 `app/lib/stats/sqlite_reading_stats_repository.dart`：

```dart
// app/lib/stats/sqlite_reading_stats_repository.dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:sqflite/sqflite.dart';

import 'daily_book_reading_stat.dart';
import 'reading_stats_repository.dart';

/// [ReadingStatsRepository] 正式實作：直接對 [Database] 下 SQL（比照
/// `SqliteSearchRepository` 既有慣例，不經 `LibraryRepository`）。
///
/// 查詢**一律不 JOIN `books`**：書被刪除後統計仍保留，書名只讀
/// `daily_reading_stats.book_title` 的快照。
class SqliteReadingStatsRepository implements ReadingStatsRepository {
  SqliteReadingStatsRepository({required Database database})
      : _database = database;

  final Database _database;
  final StreamController<void> _clearedController =
      StreamController<void>.broadcast();

  @override
  Future<void> addReadingSeconds({
    required String date,
    required String bookId,
    required String bookTitle,
    required int seconds,
  }) async {
    if (seconds <= 0) return;
    // upsert：主鍵衝突時累加秒數，並以最新書名覆寫快照。
    await _database.rawInsert('''
      INSERT INTO daily_reading_stats
        (date, book_id, book_title, reading_seconds, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(date, book_id) DO UPDATE SET
        reading_seconds = daily_reading_stats.reading_seconds + excluded.reading_seconds,
        book_title = excluded.book_title,
        updated_at = excluded.updated_at
    ''', [date, bookId, bookTitle, seconds, clock.now().millisecondsSinceEpoch]);
  }

  @override
  Future<Map<String, int>> getDailyTotals({
    required String startDate,
    required String endDate,
  }) async {
    final rows = await _database.rawQuery('''
      SELECT date, SUM(reading_seconds) AS total
      FROM daily_reading_stats
      WHERE date >= ? AND date <= ?
      GROUP BY date
      ORDER BY date ASC
    ''', [startDate, endDate]);
    return {
      for (final row in rows) row['date'] as String: row['total'] as int,
    };
  }

  @override
  Future<List<DailyBookReadingStat>> getBookStatsForDate(String date) async {
    final rows = await _database.query(
      'daily_reading_stats',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'reading_seconds DESC, book_title ASC, book_id ASC',
    );
    return [
      for (final row in rows)
        DailyBookReadingStat(
          bookId: row['book_id'] as String,
          bookTitle: row['book_title'] as String,
          readingSeconds: row['reading_seconds'] as int,
        ),
    ];
  }

  @override
  Future<int> getTotalReadingSeconds() async {
    final rows = await _database.rawQuery(
        'SELECT COALESCE(SUM(reading_seconds), 0) AS total FROM daily_reading_stats');
    return rows.first['total'] as int;
  }

  @override
  Future<void> clearAllStats() async {
    await _database.delete('daily_reading_stats');
    _clearedController.add(null);
  }

  @override
  Stream<void> get onCleared => _clearedController.stream;
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/stats test/support/fake_reading_stats_repository_test.dart`
Expected: `All tests passed!`，共 41 個測試（SQLite 契約 17＋專屬 2、schema 3、替身契約 17＋輔助 2）。

- [ ] **Step 5: 靜態分析**

Run: `flutter analyze lib/stats lib/library/sqlite_library_repository.dart test/stats test/support`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/stats/sqlite_reading_stats_repository.dart test/stats/sqlite_reading_stats_repository_test.dart
git commit -m "feat(stats): epic-9 Issue 2 SqliteReadingStatsRepository，通過共用契約測試"
```

- [ ] **Step 7: 完整測試（這是整張計畫的最後一個 Task）**

Run: `flutter test`
Expected: 全部通過（全專案約 1,800 個以上案例，約需 5 分鐘）。失敗時先確認是否為本 Issue 造成：本 Issue 只動 `sqlite_library_repository.dart` 的 schema 版本與新增資料表，任何與資料庫版本號有關的既有測試都可能受影響。

---

## Self-Review

**Spec coverage（對照 `issues.md` Issue 2 驗收標準）：**
- 同日同書多次累加、書名以最新為準 → Task 1 契約（Task 3 對 SQLite 實際驗證）。
- 區間查詢只回傳有紀錄日期、含起訖日；單日各書依秒數排序 → 契約。
- 刪書後時數與書名快照仍在、刪書本身不受影響 → Task 2 schema 測試（原生 SQL）與 Task 3 專屬行為測試（透過 repository）。
- `clearAllStats()` 清空並發出 `onCleared`，多個監聽者皆收到 → 契約。
- v26 升 v27 既有資料完整；全新安裝直接 v27 → Task 2。
- `FakeReadingStatsRepository` 完整實作介面行為並可獨立使用 → Task 1（與 SQLite 共用同一組契約）。
- 檔案位置（`app/lib/stats/`、`app/test/support/`、`app/test/stats/`）→ 檔案結構表。
- 當日詳情與累計總和不 JOIN `books` → Task 3 實作（只查 `daily_reading_stats`）＋刪書測試佐證。

**Placeholder 掃描：** 無 TBD／TODO；所有程式碼區塊皆為實際跑過並通過的完整檔案內容。

**型別一致性：** `ReadingStatsRepository` 六個成員在介面（Task 1）、Fake（Task 1）、SQLite 實作（Task 3）、契約測試呼叫處的名稱與參數（`date`／`bookId`／`bookTitle`／`seconds`、`startDate`／`endDate`）逐一相符；`SqliteReadingStatsRepository` 的建構子 `database:` 與 Task 3 測試呼叫相符；schema 欄位名（`date`、`book_id`、`book_title`、`reading_seconds`、`updated_at`）在 Task 2 的 DDL、schema 測試與 Task 3 的 SQL 中一致。

**Review Focus：** 五項各有對應的契約測試（見上方列表），且同時對 Fake 與 SQLite 兩種實作執行。

**驗證紀錄：** 本計畫中的所有程式碼與測試，已在暫時的 worktree 實際執行：`flutter analyze` 乾淨；`flutter test test/stats test/support/fake_reading_stats_repository_test.dart` 共 41 個測試全過；既有的 `sqlite_library_repository_test.dart` 在版本號斷言改為 27 後全數通過；另以「暫時對 `book_id` 加上外鍵」確認測試會失敗（資料表 schema 測試與契約測試皆抓得到）。
