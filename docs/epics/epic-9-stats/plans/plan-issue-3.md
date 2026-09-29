# Epic 9 Issue 3：`ReadingStatsTracker`——純 Dart 計時器 — 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `ReadingStatsTracker`：每本書一個的會話級純 Dart 計時器，把「翻頁、捲動、長按劃線、TTS 播放」等閱讀活動事件，轉成「已確認的閱讀秒數」，並透過注入的寫入回呼交給儲存層。不依賴 Flutter、資料庫或 WebView，時鐘可注入。

**Architecture:**
- 單一檔案 `app/lib/stats/reading_stats_tracker.dart`。內部只保存一個「錨點」（最後一次活動或確認點）與一個「已確認緩衝」（每個日期一筆 `Duration`）；**錨點之後的時間永遠只是暫態，不進緩衝**，只有「後續活動、合法退出、TTS 播放中」三種情況才把錨點到現在的區間確認進緩衝。
- 30 秒週期計時器只在 `active` 時存在：每次觸發都寫入已確認緩衝，並兼任閒置看門狗；寫入以「串接 Future」序列化，避免上一批尚未完成時重複送出。
- 背景與 TTS 是獨立的一塊（Task 2）：Task 1 先完成不含背景／TTS 的完整核心，Task 2 再以小幅修改加入。

**Tech Stack:** Dart 3（純 Dart，不 import Flutter）、`package:clock`、`fake_async`＋`flutter_test`（測試）。

**Spec:** [`../spec.md`](../spec.md)（「核心介面」「閱讀活動事件」「計時狀態機」「背景與 TTS」「時鐘防護與日期切分」「寫入策略」「清除全部統計」，以及「測試決策」seam 1）、[`../issues.md`](../issues.md) Issue 3

## Global Constraints

- 介面簽章逐字照 spec「核心介面」：`typedef ReadingStatsFlush = Future<void> Function(String date, String bookId, String bookTitle, int seconds)`；`ReadingStatsTracker({required String bookId, required String bookTitle, required ReadingStatsFlush onFlush, Stream<void>? onCleared, Clock? clock})`；`recordActivity()`、`onEnteredBackground()`、`onReturnedToForeground()`、`onTtsPlayingChanged(bool)`、`Future<void> flushAndClose()`、`void dispose()`。日期為 `YYYY-MM-DD` 本地日期字串。
- 純 Dart：只可 import `dart:async`、`dart:developer`、`package:clock`；**嚴禁** import `package:flutter/*`。
- 閒置門檻 2 分鐘、寫入週期 30 秒，皆為常數（`kReadingIdleThreshold`、`kReadingFlushInterval`），不開放設定。
- 「不超過門檻」用 `<=`（活動、退出的確認條件）；閒置看門狗用 `>=`（spec「已達門檻」）。
- 暫態時間**絕不寫入**；超過門檻的空檔**整段丟棄**（不是截到門檻）。
- 內部一律以 `Duration` 累加；寫入時只取整數秒，未滿 1 秒的餘額留在緩衝。
- 時鐘防護：時間差小於 0 視為 0；倒撥跨日只終止前段、不向過去日期寫入；單次計量不超過門檻。
- `dispose()` 是同步方法，只取消訂閱與計時器，**不得**在其中寫入；`flushAndClose()` 完成後再呼叫 `dispose()` 不得再寫入或拋例外。
- 寫入回呼失敗時，該批秒數保留在緩衝、下次再試；失敗只記錄診斷資訊（`dart:developer` 的 `log`），不向外拋出。
- 計時器按需啟動、結束即取消，測試結束時不得殘留 Timer。
- 本計畫**不接** `ReaderScreen`／`main.dart`（那是 Issue 4）。
- 程式碼註解一律使用正體中文；提交前 `flutter analyze` 須乾淨。

## Review Focus

以下是 spec 隱含、但主要驗收條件沒有直接涵蓋，最可能讓使用者踩到的情況（最可能的在前）：

1. **寫入回呼很慢、與下一次 30 秒觸發重疊**：同一批秒數不得送出兩次、也不得漏掉。→ Task 1「寫入重疊時依序送出，不重複也不遺漏」。
2. **清除統計當下，有一批寫入正在途中**：在途的舊批次完成後，不得從清除後新累積的緩衝再扣一次（否則秒數變負、之後的閱讀時數遺失）。→ Task 1「清除當下有寫入在途」。
3. **快速連續滑動（同一毫秒多次活動）**：不崩潰、不產生負值或多算。→ Task 1「同一時刻大量活動」。
4. **來電、通知欄下拉造成的「進背景又立刻回前景」**：回來後第一次活動不得回溯採計進背景前的暫態，也不得重複結算。→ Task 2「回前景後第一次活動不回溯」。
5. **TTS 狀態重複回報 `playing=true`**（播放器常對同一狀態重複通知）：不得重複啟動計時或多算。→ Task 2「重複回報 playing=true」（行為鎖定測試，見 Task 3 Step 4 說明）。

已知限制（不修，計畫內明說）：`clearAllStats()` 在資料庫刪除完成後才發 `onCleared`；若此刻已有一批寫入「已經送進資料庫佇列」，該批（至多 30 秒的時數）仍會落地。tracker 無法取消已送出的寫入，只保證清除後新累積的秒數不受影響。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/stats/reading_stats_tracker.dart` | 新增（Task 1）、修改（Task 2） | 計時核心 |
| `app/test/stats/reading_stats_tracker_harness.dart` | 新增 | 測試共用工具：假時鐘、寫入紀錄、可注入失敗／延遲（不是測試檔） |
| `app/test/stats/reading_stats_tracker_test.dart` | 新增 | 狀態機、寫入、時鐘、跨午夜、清除、生命週期 |
| `app/test/stats/reading_stats_tracker_background_test.dart` | 新增 | 背景與 TTS（與上一檔共用 harness；issues.md 只指定第一個檔名，這裡多拆一個讓每個檔案聚焦） |

以下所有指令都在 `app/` 目錄下執行。

---

### Task 1：計時核心（不含背景／TTS）

**Files:**
- Create: `app/lib/stats/reading_stats_tracker.dart`
- Create: `app/test/stats/reading_stats_tracker_harness.dart`
- Test: `app/test/stats/reading_stats_tracker_test.dart`

**Interfaces:**
- Consumes: 無（寫入回呼與 `onCleared` 由呼叫端注入）。
- Produces（Task 2 與 Issue 4 依賴，名稱與簽章固定）：
  - `typedef ReadingStatsFlush = Future<void> Function(String date, String bookId, String bookTitle, int seconds)`
  - `const Duration kReadingIdleThreshold`、`const Duration kReadingFlushInterval`
  - `class ReadingStatsTracker`：`recordActivity()`、`Future<void> flushAndClose()`、`void dispose()`（Task 2 再加入 `onEnteredBackground()`、`onReturnedToForeground()`、`onTtsPlayingChanged(bool)`）
  - 測試工具 `TrackerHarness(FakeAsync async, {DateTime? startTime})`：`tracker`、`writes`（`List<FlushCall>`）、`flushAttempts`、`flushError`、`flushGate`、`cleared`（`StreamController<void>`）、`elapse(Duration)`、`elapseSeconds(int)`、`jumpTo(DateTime)`、`total([String? date])`、`closeAndSettle()`、`dispose()`

- [ ] **Step 1: 建立測試工具與測試**

建立 `app/test/stats/reading_stats_tracker_harness.dart`：

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:elinkbook/stats/reading_stats_tracker.dart';
import 'package:fake_async/fake_async.dart';

/// 一次寫入回呼的紀錄。
class FlushCall {
  const FlushCall(this.date, this.bookId, this.bookTitle, this.seconds);

  final String date;
  final String bookId;
  final String bookTitle;
  final int seconds;

  @override
  String toString() => '$date/$bookId/$bookTitle/$seconds 秒';
}

/// tracker 測試共用工具：
/// - 時鐘 = 起始時間 + fakeAsync 已經過時間 + 可手動設定的偏移（模擬倒撥／快轉）。
/// - 寫入回呼把成功的寫入記在 [writes]；可注入失敗（[flushError]）或延遲（[flushGate]）。
class TrackerHarness {
  TrackerHarness(this.async, {DateTime? startTime})
      : start = startTime ?? DateTime(2026, 9, 29, 10) {
    tracker = ReadingStatsTracker(
      bookId: 'book-1',
      bookTitle: '測試書',
      onFlush: _onFlush,
      onCleared: cleared.stream,
      clock: Clock(_now),
    );
  }

  final FakeAsync async;
  final DateTime start;

  /// 手動時鐘偏移；正值為快轉，負值為倒撥。
  Duration skew = Duration.zero;

  final List<FlushCall> writes = [];

  /// 寫入回呼被呼叫的次數（含失敗）。
  int flushAttempts = 0;

  /// 非 null 時，寫入回呼拋出它。
  Object? flushError;

  /// 非 null 時，寫入回呼會先等它完成（模擬很慢的資料庫）。
  Completer<void>? flushGate;

  final StreamController<void> cleared = StreamController<void>.broadcast(sync: true);

  late final ReadingStatsTracker tracker;

  DateTime _now() => start.add(async.elapsed).add(skew);

  /// 目前（含偏移）的假時鐘時間。
  DateTime get now => _now();

  /// 把時鐘直接撥到指定時間（不推進 fakeAsync 的計時器）。
  void jumpTo(DateTime target) {
    skew = target.difference(start.add(async.elapsed));
  }

  Future<void> _onFlush(String date, String bookId, String bookTitle, int seconds) async {
    flushAttempts++;
    final gate = flushGate;
    if (gate != null) await gate.future;
    final error = flushError;
    if (error != null) throw error;
    writes.add(FlushCall(date, bookId, bookTitle, seconds));
  }

  /// 推進時間並讓所有微任務（含非同步寫入）跑完。
  void elapse(Duration duration) {
    async.elapse(duration);
    async.flushMicrotasks();
  }

  void elapseSeconds(int seconds) => elapse(Duration(seconds: seconds));

  /// 指定日期（省略則全部）已成功寫入的總秒數。
  int total([String? date]) => writes
      .where((w) => date == null || w.date == date)
      .fold(0, (sum, w) => sum + w.seconds);

  /// 呼叫 flushAndClose 並跑完微任務；回傳它是否已完成。
  bool closeAndSettle() {
    var done = false;
    tracker.flushAndClose().then((_) => done = true);
    async.flushMicrotasks();
    return done;
  }

  void dispose() {
    tracker.dispose();
    cleared.close();
  }
}
```

建立 `app/test/stats/reading_stats_tracker_test.dart`：

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reading_stats_tracker_harness.dart';

void main() {
  group('回溯採計與退出結算', () {
    test('開書後 90 秒才翻頁再讀 80 秒退出，共記 170 秒', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.elapseSeconds(90);
        h.tracker.recordActivity();
        h.elapseSeconds(80);
        expect(h.closeAndSettle(), isTrue);
        expect(h.total(), 170);
        h.dispose();
      });
    });

    test('開書後從未有活動就退出，記 0 秒', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.elapseSeconds(60);
        expect(h.closeAndSettle(), isTrue);
        expect(h.writes, isEmpty);
        h.dispose();
      });
    });

    test('首次活動距開書超過門檻：不回溯，從該次活動起算', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.elapseSeconds(300);
        h.tracker.recordActivity();
        h.elapseSeconds(60);
        h.closeAndSettle();
        expect(h.total(), 60);
        h.dispose();
      });
    });

    test('首次活動剛好在門檻上（120 秒）仍回溯採計', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.elapseSeconds(120);
        h.tracker.recordActivity();
        h.closeAndSettle();
        expect(h.total(), 120);
        h.dispose();
      });
    });

    test('退出時距最後一次活動仍在門檻內：尾段計入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(100);
        h.closeAndSettle();
        expect(h.total(), 100);
        h.dispose();
      });
    });

    test('退出時距最後一次活動已超過門檻：尾段整段丟棄', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 確認 30 秒
        h.elapseSeconds(200);
        h.closeAndSettle();
        expect(h.total(), 30);
        h.dispose();
      });
    });
  });

  group('閒置與暫態時間', () {
    test('放下手機發呆：寫入總量為 0、計時器已取消、之後不再寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(600);
        expect(h.total(), 0);
        expect(async.pendingTimers, isEmpty);
        final attempts = h.flushAttempts;
        h.elapseSeconds(600);
        expect(h.flushAttempts, attempts);
        h.dispose();
      });
    });

    test('閒置前已被後續活動確認的部分保留，其後的空檔不寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(60);
        h.tracker.recordActivity(); // 確認 60 秒
        h.elapseSeconds(600);
        expect(h.total(), 60);
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('超過門檻的空檔整段丟棄，不是只截到門檻長度', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(60);
        h.tracker.recordActivity(); // 確認 60 秒
        h.elapseSeconds(300); // 中途已轉為 idle
        h.tracker.recordActivity(); // 重新起算，這 300 秒不計
        h.closeAndSettle();
        expect(h.total(), 60);
        h.dispose();
      });
    });

    test('閒置後再次活動：回到計時中並重新建立計時器', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(600);
        expect(async.pendingTimers, isEmpty);
        h.tracker.recordActivity();
        expect(async.pendingTimers, isNotEmpty);
        h.elapseSeconds(20);
        h.closeAndSettle();
        expect(h.total(), 20);
        h.dispose();
      });
    });
  });

  group('寫入節流與計時器', () {
    test('每 30 秒把已確認的秒數寫入一次並歸零', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 20 秒
        h.elapseSeconds(10); // 第 30 秒：寫入 20
        expect(h.writes.map((w) => w.seconds), [20]);
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 30 秒（第 20～50 秒）
        h.elapseSeconds(10); // 第 60 秒：寫入 30
        expect(h.writes.map((w) => w.seconds), [20, 30]);
        expect(h.writes.first.bookId, 'book-1');
        expect(h.writes.first.bookTitle, '測試書');
        h.dispose();
      });
    });

    test('尚未被確認的暫態時間不會被 30 秒定時器寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(90); // 期間沒有任何活動：全是暫態
        expect(h.writes, isEmpty);
        h.tracker.recordActivity(); // 這時才確認 90 秒
        h.elapseSeconds(30);
        expect(h.total(), 90);
        h.dispose();
      });
    });

    test('計時器按需啟動：開書未活動時不存在，活動後才建立，結束即釋放', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        expect(async.pendingTimers, isEmpty);
        h.tracker.recordActivity();
        expect(async.pendingTimers, isNotEmpty);
        h.closeAndSettle();
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('寫入回呼失敗：秒數保留，下次成功時一併寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.flushError = StateError('database is locked');
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 20 秒
        h.elapseSeconds(10); // 第 30 秒：寫入失敗
        expect(h.flushAttempts, 1);
        expect(h.writes, isEmpty);
        h.flushError = null;
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 再確認 30 秒，合計 50
        h.elapseSeconds(10); // 第 60 秒：成功
        expect(h.writes.map((w) => w.seconds), [50]);
        h.dispose();
      });
    });

    test('寫入重疊時依序送出，不重複也不遺漏', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 20 秒
        final gate = Completer<void>();
        h.flushGate = gate;
        h.elapseSeconds(10); // 第 30 秒：送出 20 秒，卡在資料庫
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 再確認 30 秒
        h.elapseSeconds(10); // 第 60 秒：上一批還沒完成
        expect(h.flushAttempts, 1);
        h.flushGate = null;
        gate.complete();
        async.flushMicrotasks();
        expect(h.writes.map((w) => w.seconds), [20, 30]);
        h.dispose();
      });
    });
  });

  group('子秒精度', () {
    test('連續五次間隔 400 毫秒的活動，餘額累積後共 2 秒', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        for (var i = 0; i < 5; i++) {
          h.elapse(const Duration(milliseconds: 400));
          h.tracker.recordActivity();
        }
        h.closeAndSettle();
        expect(h.total(), 2);
        h.dispose();
      });
    });

    test('不滿整秒的餘額不寫入（1.2 秒只寫 1 秒）', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        for (var i = 0; i < 3; i++) {
          h.elapse(const Duration(milliseconds: 400));
          h.tracker.recordActivity();
        }
        h.closeAndSettle();
        expect(h.total(), 1);
        h.dispose();
      });
    });

    test('同一時刻大量活動：不崩潰、不多算', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        for (var i = 0; i < 100; i++) {
          h.tracker.recordActivity();
        }
        h.closeAndSettle();
        expect(h.total(), 0);
        h.dispose();
      });
    });
  });

  group('時鐘防護', () {
    test('時鐘倒撥：不產生負值，之後從倒撥後的時間重新累計', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(10);
        h.skew = const Duration(hours: -1); // 倒撥一小時
        h.tracker.recordActivity(); // 倒撥：這一段不計，重新起算
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 確認 30 秒
        h.closeAndSettle();
        expect(h.total(), 30);
        expect(h.writes.every((w) => w.seconds > 0), isTrue);
        h.dispose();
      });
    });

    test('時鐘快轉一天：這一段整段丟棄，不產生巨量秒數', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.skew = const Duration(days: 1);
        h.tracker.recordActivity();
        h.closeAndSettle();
        expect(h.total(), 0);
        h.dispose();
      });
    });

    test('倒撥跨日：只終止前段，不向過去的日期寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async, startTime: DateTime(2026, 9, 29, 23, 59));
        h.tracker.recordActivity();
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 9/29 確認 30 秒
        h.jumpTo(DateTime(2026, 9, 28, 12)); // 倒撥到前一天
        h.tracker.recordActivity();
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 落在 9/28：不寫
        h.closeAndSettle();
        expect(h.total('2026-09-28'), 0);
        expect(h.total('2026-09-29'), 30);
        h.dispose();
      });
    });
  });

  group('跨午夜', () {
    test('確認區間跨越午夜：以本地午夜切成前後兩天', () {
      fakeAsync((async) {
        final h = TrackerHarness(async, startTime: DateTime(2026, 9, 29, 23, 59, 30));
        h.tracker.recordActivity();
        h.elapseSeconds(60);
        h.tracker.recordActivity(); // 23:59:30 → 00:00:30
        h.closeAndSettle();
        expect(h.total('2026-09-29'), 30);
        expect(h.total('2026-09-30'), 30);
        expect(h.writes.every((w) => w.bookId == 'book-1'), isTrue);
        h.dispose();
      });
    });

    test('間隔超過門檻的跨午夜：不切分，直接丟棄', () {
      fakeAsync((async) {
        final h = TrackerHarness(async, startTime: DateTime(2026, 9, 29, 23, 58));
        h.tracker.recordActivity();
        h.elapseSeconds(300);
        h.tracker.recordActivity();
        h.closeAndSettle();
        expect(h.writes, isEmpty);
        h.dispose();
      });
    });

    test('退出的尾段跨越午夜：一樣切成兩天', () {
      fakeAsync((async) {
        final h = TrackerHarness(async, startTime: DateTime(2026, 9, 29, 23, 59, 50));
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.closeAndSettle();
        expect(h.total('2026-09-29'), 10);
        expect(h.total('2026-09-30'), 10);
        h.dispose();
      });
    });
  });

  group('清除統計', () {
    test('收到 onCleared 後，清除前的確認與暫態秒數全部丟棄', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 20 秒（尚未被 30 秒定時器寫入）
        h.cleared.add(null);
        h.elapseSeconds(10); // 清除後才讀的 10 秒
        h.closeAndSettle();
        expect(h.total(), 10);
        h.dispose();
      });
    });

    test('清除當下有寫入在途：在途批次完成後不會扣到清除後新累積的秒數', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 20 秒
        final gate = Completer<void>();
        h.flushGate = gate;
        h.elapseSeconds(10); // 第 30 秒：送出 20 秒，卡在資料庫
        h.elapseSeconds(5);
        h.cleared.add(null); // 清除：緩衝丟棄
        h.elapseSeconds(10);
        h.tracker.recordActivity(); // 清除後確認 10 秒
        h.flushGate = null;
        gate.complete(); // 在途的舊批次（已在資料庫佇列，已知限制）完成
        async.flushMicrotasks();
        h.closeAndSettle();
        expect(h.writes.last.seconds, 10);
        expect(h.writes.every((w) => w.seconds > 0), isTrue);
        h.dispose();
      });
    });
  });

  group('生命週期', () {
    test('flushAndClose 完成後尾段已寫入、計時器已釋放；其後 dispose 與再次活動都不會寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity();
        expect(h.closeAndSettle(), isTrue);
        expect(h.total(), 20);
        expect(async.pendingTimers, isEmpty);
        final count = h.writes.length;
        h.tracker.dispose();
        h.tracker.recordActivity();
        expect(h.closeAndSettle(), isTrue); // 重複呼叫也安全
        h.elapseSeconds(600);
        expect(h.writes.length, count);
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('dispose 是同步的，且不會把未寫入的秒數寫出去', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(20);
        h.tracker.recordActivity(); // 確認 20 秒，尚未寫入
        h.tracker.dispose();
        expect(async.pendingTimers, isEmpty);
        h.elapseSeconds(600);
        expect(h.flushAttempts, 0);
        h.dispose();
      });
    });
  });
}
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/stats/reading_stats_tracker_test.dart`
Expected: 編譯失敗，`Target of URI doesn't exist: 'package:elinkbook/stats/reading_stats_tracker.dart'`。

- [ ] **Step 3: 實作計時核心**

建立 `app/lib/stats/reading_stats_tracker.dart`：

```dart
import 'dart:async';
import 'dart:developer' as developer;

import 'package:clock/clock.dart';

/// 把「已確認」的閱讀秒數寫入儲存層的回呼。
/// 回呼拋出例外時，該批秒數會保留在緩衝，下次再試。
typedef ReadingStatsFlush = Future<void> Function(
  String date,
  String bookId,
  String bookTitle,
  int seconds,
);

/// 閒置門檻：距最後一次活動超過這段時間，視為沒在讀。
const Duration kReadingIdleThreshold = Duration(minutes: 2);

/// 計時中的寫入週期，同時是閒置看門狗的檢查週期。
const Duration kReadingFlushInterval = Duration(seconds: 30);

enum _TrackerState {
  /// 剛開書、尚無活動。
  unverified,

  /// 閱讀中。
  active,

  /// 已閒置、凍結（不計時、沒有計時器）。
  idle,
}

/// 閱讀計時器：每本書一個的會話級實例，純 Dart。
///
/// 核心概念：
/// - 「錨點」是最後一次活動（或上次確認）的時間；錨點之後的時間只是暫態，
///   **不進緩衝、不寫入**。
/// - 只有後續活動（且距錨點不超過門檻）、合法退出、TTS 播放中，
///   才把「錨點 → 現在」確認進緩衝。
/// - 超過門檻的空檔整段丟棄。
class ReadingStatsTracker {
  ReadingStatsTracker({
    required this.bookId,
    required this.bookTitle,
    required ReadingStatsFlush onFlush,
    Stream<void>? onCleared,
    Clock? clock,
  })  : _onFlush = onFlush,
        _clock = clock {
    _setAnchor(_now());
    _clearedSubscription = onCleared?.listen((_) => _handleCleared());
  }

  final String bookId;
  final String bookTitle;
  final ReadingStatsFlush _onFlush;
  final Clock? _clock;

  _TrackerState _state = _TrackerState.unverified;

  /// 最後一次活動（或上次確認）的時間；開書時為開書時間。
  late DateTime _anchor;

  /// 目前已見過的最晚日期。早於它的日期一律不寫入（倒撥跨日防護）。
  String? _floorDate;

  /// 已確認、尚未成功寫入的時間，依本地日期分組；以 [Duration] 保留子秒精度。
  final Map<String, Duration> _confirmed = {};

  Timer? _timer;
  StreamSubscription<void>? _clearedSubscription;

  /// 寫入的串接：上一批完成後才處理下一批，避免重複送出。
  Future<void> _flushChain = Future<void>.value();

  /// 每次清除加一；寫入在途期間若發生清除，完成後不再扣減緩衝。
  int _clearEpoch = 0;

  bool _closed = false;

  /// 翻頁、捲動、長按劃線等閱讀活動。
  void recordActivity() {
    if (_closed) return;
    final now = _now();
    if (_state != _TrackerState.idle) {
      final gap = now.difference(_anchor);
      // 倒撥（gap 為負）或空檔超過門檻：這一段不計，直接從現在重新起算。
      if (!gap.isNegative && gap <= kReadingIdleThreshold) {
        _confirmSpan(_anchor, now);
      }
    }
    _state = _TrackerState.active;
    _setAnchor(now);
    _ensureTimer();
  }

  /// 退出閱讀器：結算尾段、寫入已確認的秒數並釋放資源。
  /// 重複呼叫，或在 [dispose] 之後呼叫，都不會再寫入。
  Future<void> flushAndClose() async {
    if (_closed) {
      await _flushChain;
      return;
    }
    _settleTail(_now());
    _shutdown();
    await _flush();
  }

  /// 同步釋放：取消訂閱與計時器。不寫入任何資料（要寫入請用 [flushAndClose]）。
  void dispose() => _shutdown();

  DateTime _now() => (_clock ?? clock).now().toLocal();

  static String _dateOf(DateTime t) {
    final month = t.month.toString().padLeft(2, '0');
    final day = t.day.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}-$month-$day';
  }

  void _setAnchor(DateTime t) {
    _anchor = t;
    final date = _dateOf(t);
    final floor = _floorDate;
    if (floor == null || date.compareTo(floor) > 0) _floorDate = date;
  }

  /// 把 [from, to] 確認進緩衝；跨越本地午夜時切成前後兩天。
  /// 呼叫端保證 to - from 不超過閒置門檻，因此最多跨越一個午夜。
  void _confirmSpan(DateTime from, DateTime to) {
    if (!to.isAfter(from)) return;
    final fromDate = _dateOf(from);
    final toDate = _dateOf(to);
    if (fromDate == toDate) {
      _credit(toDate, to.difference(from));
      return;
    }
    final midnight = DateTime(to.year, to.month, to.day);
    _credit(fromDate, midnight.difference(from));
    _credit(toDate, to.difference(midnight));
  }

  void _credit(String date, Duration amount) {
    if (amount <= Duration.zero) return;
    final floor = _floorDate;
    if (floor != null && date.compareTo(floor) < 0) return;
    _confirmed[date] = (_confirmed[date] ?? Duration.zero) + amount;
  }

  /// 結算尾段：只有計時中、且距錨點未超過門檻時才確認。
  /// 剛開書尚無活動（unverified）或已閒置（idle）時直接返回，計 0 秒。
  void _settleTail(DateTime now) {
    if (_state != _TrackerState.active) return;
    final gap = now.difference(_anchor);
    if (!gap.isNegative && gap <= kReadingIdleThreshold) {
      _confirmSpan(_anchor, now);
    }
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(kReadingFlushInterval, (_) => _onTick());
  }

  void _goIdle() {
    _state = _TrackerState.idle;
    _timer?.cancel();
    _timer = null;
  }

  /// 30 秒觸發：閒置看門狗＋寫入。
  void _onTick() {
    final now = _now();
    if (_state == _TrackerState.active) {
      final gap = now.difference(_anchor);
      if (gap.isNegative) {
        _setAnchor(now); // 倒撥：重新起算
      } else if (gap >= kReadingIdleThreshold) {
        _goIdle(); // 已閒置：丟棄暫態、取消計時器
      }
    }
    unawaited(_flush());
  }

  void _handleCleared() {
    _confirmed.clear();
    _clearEpoch++;
    // 暫態時間也丟棄：從清除當下重新起算。
    if (_state != _TrackerState.idle) _setAnchor(_now());
  }

  void _shutdown() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _clearedSubscription?.cancel();
    _clearedSubscription = null;
  }

  Future<void> _flush() {
    _flushChain = _flushChain.then((_) => _drain());
    return _flushChain;
  }

  /// 把緩衝內的整數秒逐日寫出；失敗的日期保留，成功的扣掉已寫出的整數秒。
  Future<void> _drain() async {
    final epoch = _clearEpoch;
    final dates = _confirmed.keys.toList()..sort();
    for (final date in dates) {
      final whole = (_confirmed[date] ?? Duration.zero).inSeconds;
      if (whole <= 0) continue;
      try {
        await _onFlush(date, bookId, bookTitle, whole);
      } catch (error, stackTrace) {
        developer.log(
          '閱讀統計寫入失敗（$date，$whole 秒），秒數保留待下次重試',
          name: 'ReadingStatsTracker',
          error: error,
          stackTrace: stackTrace,
        );
        continue;
      }
      // 寫入期間發生清除：緩衝已被清空，不能再扣。
      if (epoch != _clearEpoch) return;
      final remain = (_confirmed[date] ?? Duration.zero) - Duration(seconds: whole);
      if (remain <= Duration.zero) {
        _confirmed.remove(date);
      } else {
        _confirmed[date] = remain;
      }
    }
  }
}
```

- [ ] **Step 4: 執行測試，確認全部通過**

Run: `flutter test test/stats/reading_stats_tracker_test.dart`
Expected: 全部通過（All tests passed）。

- [ ] **Step 5: 靜態分析**

Run: `flutter analyze lib/stats test/stats`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/stats/reading_stats_tracker.dart app/test/stats/reading_stats_tracker_harness.dart app/test/stats/reading_stats_tracker_test.dart
git commit -m "feat(stats): epic-9 Issue 3 ReadingStatsTracker 計時核心（狀態機、寫入節流、時鐘防護、跨午夜、清除）"
```

---

### Task 2：背景與 TTS

**Files:**
- Modify: `app/lib/stats/reading_stats_tracker.dart`
- Test: `app/test/stats/reading_stats_tracker_background_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `ReadingStatsTracker`（私有的 `_state`、`_anchor`、`_confirmSpan`、`_setAnchor`、`_goIdle`、`_flush`、`_settleTail`、`_onTick`）與 `TrackerHarness`。
- Produces（Issue 4 依賴）：`void onEnteredBackground()`、`void onReturnedToForeground()`、`void onTtsPlayingChanged(bool isPlaying)`。

- [ ] **Step 1: 撰寫背景與 TTS 測試**

建立 `app/test/stats/reading_stats_tracker_background_test.dart`：

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reading_stats_tracker_harness.dart';

void main() {
  group('進入背景（TTS 非播放中）', () {
    test('立即結算並寫入，計時器釋放', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 確認 30 秒
        h.elapseSeconds(20);
        h.tracker.onEnteredBackground(); // 尾段 20 秒確認並寫入
        async.flushMicrotasks();
        expect(h.total(), 50);
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('回前景後第一次活動不回溯，也不重複結算', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.elapseSeconds(30);
        h.tracker.recordActivity(); // 確認 30 秒
        h.elapseSeconds(20);
        h.tracker.onEnteredBackground(); // 共 50 秒
        h.elapseSeconds(5);
        h.tracker.onReturnedToForeground();
        h.elapseSeconds(60);
        h.tracker.recordActivity(); // 進背景前後的空檔一律不計
        h.elapseSeconds(10);
        h.closeAndSettle();
        expect(h.total(), 60);
        h.dispose();
      });
    });

    test('開書後尚無活動就進背景：不採計任何時間', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.elapseSeconds(10);
        h.tracker.onEnteredBackground();
        h.tracker.onReturnedToForeground();
        h.elapseSeconds(10);
        h.tracker.recordActivity(); // 開書當下的回溯已作廢
        h.closeAndSettle();
        expect(h.total(), 0);
        h.dispose();
      });
    });
  });

  group('背景 TTS', () {
    test('TTS 播放中進背景：持續計時，TTS 結束時結算並寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(10);
        h.tracker.onEnteredBackground();
        h.elapseSeconds(290); // 第 300 秒；遠超過閒置門檻，仍持續計時
        expect(h.total(), 300);
        h.elapseSeconds(10);
        h.tracker.onTtsPlayingChanged(false); // 睡眠定時器到期、耳機暫停等
        async.flushMicrotasks();
        expect(h.total(), 310);
        expect(async.pendingTimers, isEmpty);
        h.elapseSeconds(600);
        expect(h.total(), 310);
        h.dispose();
      });
    });

    test('resumed 且 TTS 仍在播放：無縫延續，不重複結算', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(10);
        h.tracker.onEnteredBackground();
        h.elapseSeconds(40);
        h.tracker.onReturnedToForeground();
        h.elapseSeconds(50);
        h.tracker.onTtsPlayingChanged(false); // 前景停止
        h.closeAndSettle();
        expect(h.total(), 100);
        h.dispose();
      });
    });
  });

  group('前景 TTS', () {
    test('TTS 播放中沒有活動事件，30 秒定時器仍持續確認並寫入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(95);
        expect(h.total(), 90); // 第 30、60、90 秒各寫 30 秒
        h.closeAndSettle();
        expect(h.total(), 95); // 退出時尾段 5 秒也計入
        h.dispose();
      });
    });

    test('TTS 播放 10 分鐘不會被閒置看門狗切掉', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(600);
        expect(h.total(), 600);
        expect(async.pendingTimers, isNotEmpty);
        h.tracker.onTtsPlayingChanged(false);
        h.closeAndSettle();
        expect(h.total(), 600);
        h.dispose();
      });
    });

    test('TTS 開始播放本身算活動：開書 10 秒後開始朗讀，回溯採計', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.elapseSeconds(10);
        h.tracker.onTtsPlayingChanged(true); // 回溯 10 秒
        h.elapseSeconds(20);
        h.tracker.onTtsPlayingChanged(false); // 再 20 秒
        h.closeAndSettle();
        expect(h.total(), 30);
        h.dispose();
      });
    });

    test('重複回報 playing=true：不重複啟動計時或多算', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(20);
        h.tracker.onTtsPlayingChanged(false);
        h.tracker.onTtsPlayingChanged(false);
        h.closeAndSettle();
        expect(h.total(), 20);
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });

    test('TTS 播放中退出：尾段計入', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(45);
        h.closeAndSettle();
        expect(h.total(), 45);
        h.dispose();
      });
    });

    test('TTS 播放中時鐘快轉一天：單次計量不超過閒置門檻', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.skew = const Duration(days: 1);
        h.elapseSeconds(30); // 第 30 秒的定時器觸發，計量被鉗位
        expect(h.writes.first.seconds, 120);
        expect(h.writes.every((w) => w.seconds <= 120), isTrue);
        h.dispose();
      });
    });

    test('TTS 停止後回到一般閒置規則：之後沒有活動就轉為閒置、計時器取消', () {
      fakeAsync((async) {
        final h = TrackerHarness(async);
        h.tracker.recordActivity();
        h.tracker.onTtsPlayingChanged(true);
        h.elapseSeconds(60);
        h.tracker.onTtsPlayingChanged(false);
        h.elapseSeconds(300);
        expect(h.total(), 60);
        expect(async.pendingTimers, isEmpty);
        h.dispose();
      });
    });
  });
}
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/stats/reading_stats_tracker_background_test.dart`
Expected: 編譯失敗，`The method 'onEnteredBackground' isn't defined for the type 'ReadingStatsTracker'`（`onReturnedToForeground`、`onTtsPlayingChanged` 同理）。

- [ ] **Step 3: 實作背景與 TTS**

修改 `app/lib/stats/reading_stats_tracker.dart`，共四處。

(a) 加入兩個狀態欄位：

尋找：

```dart
  /// 每次清除加一；寫入在途期間若發生清除，完成後不再扣減緩衝。
  int _clearEpoch = 0;

  bool _closed = false;
```

改為：

```dart
  /// 每次清除加一；寫入在途期間若發生清除，完成後不再扣減緩衝。
  int _clearEpoch = 0;

  bool _closed = false;

  /// TTS 是否正在播放（由 ReaderScreen 轉譯後回報）。
  bool _ttsPlaying = false;

  /// App 是否在背景（由 ReaderScreen 轉譯 paused／resumed 後回報）。
  bool _inBackground = false;
```

(b) 加入三個公開方法與 `_confirmThrough`：

尋找：

```dart
  /// 退出閱讀器：結算尾段、寫入已確認的秒數並釋放資源。
```

改為：

```dart
  /// App 進入背景（paused）。TTS 未播放：立即結算並寫入，結束這一段；
  /// TTS 播放中：不結束，進入背景計時，直到 TTS 停止。
  void onEnteredBackground() {
    if (_closed) return;
    _inBackground = true;
    if (_ttsPlaying) return;
    _settleTail(_now());
    _goIdle();
    unawaited(_flush());
  }

  /// App 回到前景（resumed）。TTS 仍在播放時無縫延續，不需要任何結算。
  void onReturnedToForeground() {
    if (_closed) return;
    _inBackground = false;
  }

  /// TTS 播放狀態變化。開始播放本身算一次活動；停止時先把播放期間確認完；
  /// 若此時 App 在背景，結束這一段並寫入。重複回報相同狀態不做任何事。
  void onTtsPlayingChanged(bool isPlaying) {
    if (_closed || isPlaying == _ttsPlaying) return;
    if (isPlaying) {
      recordActivity();
      _ttsPlaying = true;
      return;
    }
    if (_state == _TrackerState.active) _confirmThrough(_now());
    _ttsPlaying = false;
    if (_inBackground) {
      _goIdle();
      unawaited(_flush());
    }
  }

  /// 退出閱讀器：結算尾段、寫入已確認的秒數並釋放資源。
```

(c) 尾段結算加入 TTS 分支，並新增 `_confirmThrough`：

尋找：

```dart
  /// 結算尾段：只有計時中、且距錨點未超過門檻時才確認。
  /// 剛開書尚無活動（unverified）或已閒置（idle）時直接返回，計 0 秒。
  void _settleTail(DateTime now) {
    if (_state != _TrackerState.active) return;
    final gap = now.difference(_anchor);
    if (!gap.isNegative && gap <= kReadingIdleThreshold) {
      _confirmSpan(_anchor, now);
    }
  }
```

改為：

```dart
  /// 結算尾段：TTS 播放中，朗讀本身就是連續活動，直接確認到現在；
  /// 否則只有距錨點未超過門檻時才確認。
  /// 剛開書尚無活動（unverified）或已閒置（idle）時直接返回，計 0 秒。
  void _settleTail(DateTime now) {
    if (_state != _TrackerState.active) return;
    if (_ttsPlaying) {
      _confirmThrough(now);
      return;
    }
    final gap = now.difference(_anchor);
    if (!gap.isNegative && gap <= kReadingIdleThreshold) {
      _confirmSpan(_anchor, now);
    }
  }

  /// TTS 播放中：把「錨點 → 現在」確認進緩衝並前移錨點。
  /// 單次計量不超過閒置門檻（擋時鐘快轉）；倒撥則不計並重新起算。
  void _confirmThrough(DateTime now) {
    final gap = now.difference(_anchor);
    if (gap.isNegative) {
      _setAnchor(now);
      return;
    }
    final counted = gap > kReadingIdleThreshold ? kReadingIdleThreshold : gap;
    _confirmSpan(now.subtract(counted), now);
    _setAnchor(now);
  }
```

(d) 看門狗對 TTS 播放中豁免（改為持續確認）：

尋找：

```dart
    if (_state == _TrackerState.active) {
      final gap = now.difference(_anchor);
      if (gap.isNegative) {
        _setAnchor(now); // 倒撥：重新起算
      } else if (gap >= kReadingIdleThreshold) {
        _goIdle(); // 已閒置：丟棄暫態、取消計時器
      }
    }
    unawaited(_flush());
```

改為：

```dart
    if (_state == _TrackerState.active) {
      if (_ttsPlaying) {
        _confirmThrough(now); // TTS 播放中沒有活動事件：由定時器持續確認
      } else {
        final gap = now.difference(_anchor);
        if (gap.isNegative) {
          _setAnchor(now); // 倒撥：重新起算
        } else if (gap >= kReadingIdleThreshold) {
          _goIdle(); // 已閒置：丟棄暫態、取消計時器
        }
      }
    }
    unawaited(_flush());
```

- [ ] **Step 4: 執行兩個 tracker 測試檔，確認全部通過**

Run: `flutter test test/stats/reading_stats_tracker_test.dart test/stats/reading_stats_tracker_background_test.dart`
Expected: 全部通過（Task 1 的測試不受影響）。

- [ ] **Step 5: 靜態分析**

Run: `flutter analyze lib/stats test/stats`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/stats/reading_stats_tracker.dart app/test/stats/reading_stats_tracker_background_test.dart
git commit -m "feat(stats): epic-9 Issue 3 ReadingStatsTracker 背景與 TTS 規則"
```

---

### Task 3：最終驗證

**Files:**
- 無新增或修改（只驗證；若失敗才回頭修對應 Task）。

- [ ] **Step 1: 確認 tracker 沒有依賴 Flutter**

Run: `grep -n "package:flutter" lib/stats/reading_stats_tracker.dart`
Expected: 無任何輸出（結束碼 1）。

- [ ] **Step 2: 靜態分析（整個專案）**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 完整測試**

Run: `flutter test`
Expected: 全部通過、0 失敗（既有 1 個略過為已知既有測試）。記下通過／略過數與分支 HEAD，供 PR 說明使用。

- [ ] **Step 4: 突變驗證（證明測試抓得到錯）**

逐一在 `reading_stats_tracker.dart` 套用下列修改，執行 `flutter test test/stats/reading_stats_tracker_test.dart test/stats/reading_stats_tracker_background_test.dart`，**必須出現失敗**；確認後以 `git checkout -- lib/stats/reading_stats_tracker.dart` 還原，再做下一個：

1. 空檔超過門檻改成只截到門檻：`recordActivity()` 的條件改為 `if (!gap.isNegative) _confirmSpan(_anchor, gap <= kReadingIdleThreshold ? now : _anchor.add(kReadingIdleThreshold));`
2. 30 秒定時器連暫態時間一起寫：`_onTick()` 開頭先呼叫 `_settleTail(now)`。
3. 把 `_flush()` 改成不串接：`Future<void> _flush() => _drain();`
4. 拿掉 `_drain()` 內的 `if (epoch != _clearEpoch) return;`
5. 拿掉 `_credit()` 內對 `_floorDate` 的檢查。
6. `_confirmSpan()` 拿掉午夜切分（一律 `_credit(toDate, to.difference(from))`）。
7. `onTtsPlayingChanged()` 的停止分支拿掉 `if (_state == _TrackerState.active) _confirmThrough(_now());`。
8. `_onTick()` 拿掉 `_ttsPlaying` 分支（改成 `if (false) {`）。

Expected: 8 個突變各至少有一個測試失敗。

說明：`onTtsPlayingChanged()` 開頭「重複回報相同狀態就提早返回」的保護是純防禦——拿掉後行為完全相同（重複的 `true` 再走一次 `recordActivity()`，但錨點剛被定時器推進過，確認量一樣），所以「重複回報 playing=true」那個測試是行為鎖定，**不會**被突變抓到，這是預期的，不要為了讓它被抓到而改測試。

- [ ] **Step 5: 回報**

在最終回報列出：tracker 兩個測試檔的通過數、完整 `flutter test` 結果（含 HEAD）、8 個突變的驗證結果。
