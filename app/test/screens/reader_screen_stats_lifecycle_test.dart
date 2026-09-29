import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/stats/reading_stats_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reader_screen_stats_harness.dart';

/// 記錄寫入的 tracker 包裝。時鐘用預設的 `package:clock`，在 testWidgets 的
/// fake async 下隨 `tester.pump(duration)` 推進。
class _StatsRecorder {
  final List<int> seconds = [];

  late final ReadingStatsTracker tracker = ReadingStatsTracker(
    bookId: kStatsTestBookId,
    bookTitle: kStatsTestBookTitle,
    onFlush: (date, bookId, bookTitle, s) async => seconds.add(s),
  );

  int get total => seconds.fold(0, (sum, s) => sum + s);
}

void main() {
  registerReaderStatsTestEnvironment();

  testWidgets('paused 轉為進入背景：結算尾段並立即寫入', (tester) async {
    final recorder = _StatsRecorder();
    await pumpStatsReader(tester, readingStatsTracker: recorder.tracker);

    recorder.tracker.recordActivity();
    await tester.pump(const Duration(seconds: 20));
    moveAppToBackground(tester);
    await tester.pump();

    expect(recorder.total, 20);

    await disposeStatsReader(tester);
  });

  testWidgets('resumed 轉為回到前景：背景期間的活動被忽略，回前景後才重新計時',
      (tester) async {
    final recorder = _StatsRecorder();
    await pumpStatsReader(tester, readingStatsTracker: recorder.tracker);

    recorder.tracker.recordActivity();
    await tester.pump(const Duration(seconds: 20));
    moveAppToBackground(tester);
    await tester.pump();
    expect(recorder.total, 20);

    await tester.pump(const Duration(seconds: 10));
    moveAppToForeground(tester);
    await tester.pump();
    recorder.tracker.recordActivity(); // 回前景後第一次活動：不回溯背景空檔
    await tester.pump(const Duration(seconds: 10));

    await disposeStatsReader(tester); // 尾段 10 秒
    expect(recorder.total, 30);
  });

  testWidgets('離開閱讀器：結算尾段並寫入，之後 tracker 已關閉不再計時', (tester) async {
    final recorder = _StatsRecorder();
    await pumpStatsReader(tester, readingStatsTracker: recorder.tracker);

    recorder.tracker.recordActivity();
    await tester.pump(const Duration(seconds: 20));

    await disposeStatsReader(tester);
    expect(recorder.total, 20);

    recorder.tracker.recordActivity();
    await tester.pump(const Duration(seconds: 600));
    expect(recorder.total, 20);
  });

  testWidgets('TTS 播放中進背景：不結算，TTS 停止才寫入', (tester) async {
    final recorder = _StatsRecorder();
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpStatsReader(
      tester,
      readingStatsTracker: recorder.tracker,
      readerKey: key,
    );

    recorder.tracker.recordActivity();
    ReaderScreen.reportTtsPlayingForTest(key, true);
    await tester.pump(const Duration(seconds: 10));
    moveAppToBackground(tester);
    await tester.pump();
    expect(recorder.total, 0, reason: '背景 TTS 播放中不應立即結算');

    await tester.pump(const Duration(seconds: 5));
    expect(recorder.total, 0);

    ReaderScreen.reportTtsPlayingForTest(key, false); // 睡眠定時器、耳機暫停等
    await tester.pump();
    expect(recorder.total, 15);

    await disposeStatsReader(tester);
  });

  testWidgets('兩個統計參數皆未提供：進出背景與離開閱讀器都正常，行為與現況相同',
      (tester) async {
    await pumpStatsReader(tester);

    moveAppToBackground(tester);
    await tester.pump();
    moveAppToForeground(tester);
    await tester.pump();

    await disposeStatsReader(tester);
    expect(tester.takeException(), isNull);
  });
}
