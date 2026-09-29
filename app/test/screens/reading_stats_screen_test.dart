import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reading_stats_screen.dart';
import 'package:elinkbook/screens/widgets/reading_heatmap.dart';
import 'package:elinkbook/stats/daily_book_reading_stat.dart';
import 'package:elinkbook/stats/reading_stats_repository.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

import '../support/fake_reading_stats_repository.dart';
import '../support/pump_localized_widget.dart';

/// 固定「今天」為 2026-09-29（週二），網格為 2025-09-30 ～ 2026-09-29。
final _now = DateTime(2026, 9, 29, 10, 30);

DailyBookReadingStat _stat(String id, String title, int seconds) =>
    DailyBookReadingStat(bookId: id, bookTitle: title, readingSeconds: seconds);

Finder _cell(String date) => find.byKey(Key('heatmap_cell_$date'));
Finder _byKey(String key) => find.byKey(Key(key));

HeatmapCellPainter _painterOf(WidgetTester tester, String date) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: _cell(date), matching: find.byType(CustomPaint)),
  );
  return paint.painter! as HeatmapCellPainter;
}

ScrollController _scrollController(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(_byKey('reading_stats_heatmap'))
    .controller!;

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(_byKey(key)).data!;

Future<void> _pumpScreen(
  WidgetTester tester,
  ReadingStatsRepository repository, {
  Locale locale = const Locale('zh', 'TW'),
  AppTheme theme = AppTheme.light,
  bool isEinkMode = false,
}) async {
  // 加高視窗，讓清除按鈕在不捲動的情況下就看得到
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await pumpLocalizedWidget(
    tester,
    ReadingStatsScreen(repository: repository, nowProvider: () => _now),
    locale: locale,
    theme: theme,
    isEinkMode: isEinkMode,
  );
  await tester.pumpAndSettle();
}

/// 包一層，讓測試能卡住特定日期的詳情查詢，製造「先點的較晚回來」的競態。
class _GatedRepository implements ReadingStatsRepository {
  _GatedRepository(this.inner);
  final FakeReadingStatsRepository inner;
  final Map<String, Completer<void>> gates = {};

  @override
  Future<List<DailyBookReadingStat>> getBookStatsForDate(String date) async {
    final gate = gates[date];
    if (gate != null) await gate.future;
    return inner.getBookStatsForDate(date);
  }

  @override
  Future<void> addReadingSeconds({
    required String date,
    required String bookId,
    required String bookTitle,
    required int seconds,
  }) =>
      inner.addReadingSeconds(
          date: date, bookId: bookId, bookTitle: bookTitle, seconds: seconds);

  @override
  Future<Map<String, int>> getDailyTotals({
    required String startDate,
    required String endDate,
  }) =>
      inner.getDailyTotals(startDate: startDate, endDate: endDate);

  @override
  Future<int> getTotalReadingSeconds() => inner.getTotalReadingSeconds();

  @override
  Future<void> clearAllStats() => inner.clearAllStats();

  @override
  Stream<void> get onCleared => inner.onCleared;
}

void main() {
  testWidgets('載入完成後顯示貢獻圖；預設選中今天，今天沒有紀錄顯示說明', (tester) async {
    await _pumpScreen(tester, FakeReadingStatsRepository());

    expect(_byKey('reading_stats_loading'), findsNothing);
    expect(_byKey('reading_stats_heatmap'), findsOneWidget);
    // 外框疊在今天的方格上
    expect(tester.getTopLeft(_byKey('heatmap_selection_outline')),
        tester.getTopLeft(_cell('2026-09-29')));
    expect(_byKey('reading_stats_detail_empty'), findsOneWidget);
    expect(_textOf(tester, 'reading_stats_detail_title'), contains('2026'));
  });

  testWidgets('今天有多本書：詳情依時數由多到少，已刪除的書顯示書名快照', (tester) async {
    final repo = FakeReadingStatsRepository(initialStats: {
      '2026-09-29': [
        _stat('a', '紅樓夢', 600),
        _stat('gone', '已刪除的書（快照）', 3900),
        _stat('b', '三體', 1800),
      ],
    });
    await _pumpScreen(tester, repo);

    expect(_byKey('reading_stats_detail_empty'), findsNothing);
    final ys = [
      for (final id in ['gone', 'b', 'a'])
        tester.getTopLeft(_byKey('reading_stats_detail_row_$id')).dy,
    ];
    expect(ys[0], lessThan(ys[1]));
    expect(ys[1], lessThan(ys[2]));
    expect(
      find.descendant(
          of: _byKey('reading_stats_detail_row_gone'),
          matching: find.text('已刪除的書（快照）')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: _byKey('reading_stats_detail_row_gone'),
          matching: find.text('1 小時 5 分鐘')),
      findsOneWidget,
    );
  });

  testWidgets('點選其他方格：外框移動、詳情切換成該日', (tester) async {
    final repo = FakeReadingStatsRepository(initialStats: {
      '2026-09-29': [_stat('a', '今天的書', 600)],
      '2025-09-30': [_stat('old', '一年前的書', 1200)],
    });
    await _pumpScreen(tester, repo);
    expect(_byKey('reading_stats_detail_row_a'), findsOneWidget);

    _scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(_cell('2025-09-30'));
    await tester.pumpAndSettle();

    expect(_byKey('reading_stats_detail_row_old'), findsOneWidget);
    expect(_byKey('reading_stats_detail_row_a'), findsNothing);
    expect(tester.getTopLeft(_byKey('heatmap_selection_outline')),
        tester.getTopLeft(_cell('2025-09-30')));
    expect(_textOf(tester, 'reading_stats_detail_title'), contains('2025'));

    // 點沒有紀錄的日子 → 顯示說明
    await tester.tap(_cell('2025-10-01'));
    await tester.pumpAndSettle();
    expect(_byKey('reading_stats_detail_empty'), findsOneWidget);
  });

  testWidgets('進入畫面預設捲到最右側，星期欄不隨捲動移動', (tester) async {
    await _pumpScreen(tester, FakeReadingStatsRepository());
    final controller = _scrollController(tester);
    expect(controller.position.maxScrollExtent, greaterThan(0));
    expect(controller.offset, controller.position.maxScrollExtent);

    final columnBefore = tester.getTopLeft(_byKey('heatmap_weekday_column'));
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_byKey('heatmap_weekday_column')), columnBefore);
  });

  testWidgets('貢獻圖分級以當日全部書籍總時數判定', (tester) async {
    final repo = FakeReadingStatsRepository(initialStats: {
      // 兩本各 10 分鐘 → 合計 20 分鐘 → 第 2 級（不是各自的第 1 級）
      '2026-09-28': [_stat('a', 'A', 600), _stat('b', 'B', 600)],
      '2026-09-29': [_stat('a', 'A', 3600)],
    });
    await _pumpScreen(tester, repo);
    expect(_painterOf(tester, '2026-09-28').level, 2);
    expect(_painterOf(tester, '2026-09-29').level, 4);
    expect(_painterOf(tester, '2026-09-27').level, 0);
  });

  testWidgets('累計總時數＝全部紀錄加總，含一年以前（貢獻圖之外）的舊紀錄', (tester) async {
    final repo = FakeReadingStatsRepository(initialStats: {
      '2025-01-01': [_stat('old', '很久以前', 3600)], // 視窗外
      '2026-09-29': [_stat('a', 'A', 1800)],
    });
    await _pumpScreen(tester, repo);

    expect(_textOf(tester, 'reading_stats_total_text'), '1 小時 30 分鐘');
    expect(_cell('2025-01-01'), findsNothing); // 視窗外沒有對應方格
    expect(_painterOf(tester, '2026-09-29').level, 3);
  });

  testWidgets('全新安裝（沒有任何紀錄）：正常顯示、總時數 0 分鐘、方格全為第 0 級', (tester) async {
    await _pumpScreen(tester, FakeReadingStatsRepository());
    expect(tester.takeException(), isNull);
    expect(_textOf(tester, 'reading_stats_total_text'), '0 分鐘');
    expect(_painterOf(tester, '2026-09-29').level, 0);
    expect(_painterOf(tester, '2025-09-30').level, 0);
    expect(_byKey('reading_stats_detail_empty'), findsOneWidget);
  });

  testWidgets('超長書名在詳情中自動換行、不溢位', (tester) async {
    final longTitle = List.filled(200, '長').join();
    final repo = FakeReadingStatsRepository(initialStats: {
      '2026-09-29': [_stat('long', longTitle, 600)],
    });
    await _pumpScreen(tester, repo);
    expect(tester.takeException(), isNull);
    expect(_byKey('reading_stats_detail_row_long'), findsOneWidget);
  });

  testWidgets('書名快照為空白時退回書籍 id，不出現空白列', (tester) async {
    final repo = FakeReadingStatsRepository(initialStats: {
      '2026-09-29': [_stat('book-42', '   ', 600)],
    });
    await _pumpScreen(tester, repo);
    expect(
      find.descendant(
          of: _byKey('reading_stats_detail_row_book-42'),
          matching: find.text('book-42')),
      findsOneWidget,
    );
  });

  testWidgets('快速連點兩個方格：先點的查詢較晚回來，不會蓋掉後點的結果', (tester) async {
    final inner = FakeReadingStatsRepository(initialStats: {
      '2026-09-21': [_stat('a', 'A 書', 600)],
      '2026-09-22': [_stat('b', 'B 書', 600)],
    });
    final repo = _GatedRepository(inner);
    await _pumpScreen(tester, repo);

    repo.gates['2026-09-21'] = Completer<void>(); // 卡住 A 的詳情查詢
    await tester.tap(_cell('2026-09-21')); // 點 A（查詢卡住）
    await tester.pump();
    await tester.tap(_cell('2026-09-22')); // 再點 B（立即回來）
    await tester.pumpAndSettle();
    expect(_byKey('reading_stats_detail_row_b'), findsOneWidget);

    repo.gates['2026-09-21']!.complete(); // 最後才放行 A
    await tester.pumpAndSettle();

    expect(_byKey('reading_stats_detail_row_b'), findsOneWidget);
    expect(_byKey('reading_stats_detail_row_a'), findsNothing);
    expect(tester.getTopLeft(_byKey('heatmap_selection_outline')),
        tester.getTopLeft(_cell('2026-09-22')));
  });

  group('清除全部統計', () {
    FakeReadingStatsRepository seeded() => FakeReadingStatsRepository(
          initialStats: {
            '2026-09-29': [_stat('a', 'A', 1800)],
          },
        );

    testWidgets('按下清除只會先出確認對話框，取消則資料與畫面不變', (tester) async {
      final repo = seeded();
      await _pumpScreen(tester, repo);

      await tester.tap(_byKey('reading_stats_clear_all_button'));
      await tester.pumpAndSettle();
      expect(_byKey('reading_stats_clear_all_dialog'), findsOneWidget);
      expect(await repo.getTotalReadingSeconds(), 1800); // 尚未清除

      await tester.tap(_byKey('reading_stats_clear_all_cancel_button'));
      await tester.pumpAndSettle();

      expect(_byKey('reading_stats_clear_all_dialog'), findsNothing);
      expect(await repo.getTotalReadingSeconds(), 1800);
      expect(_textOf(tester, 'reading_stats_total_text'), '30 分鐘');
      expect(_byKey('reading_stats_detail_row_a'), findsOneWidget);
      expect(_byKey('reading_stats_clear_success_snackbar'), findsNothing);
    });

    testWidgets('確認後資料清空、畫面回到空白狀態並提示', (tester) async {
      final repo = seeded();
      await _pumpScreen(tester, repo);

      await tester.tap(_byKey('reading_stats_clear_all_button'));
      await tester.pumpAndSettle();
      await tester.tap(_byKey('reading_stats_clear_all_confirm_button'));
      await tester.pumpAndSettle();

      expect(await repo.getTotalReadingSeconds(), 0);
      expect(_textOf(tester, 'reading_stats_total_text'), '0 分鐘');
      expect(_byKey('reading_stats_detail_empty'), findsOneWidget);
      expect(_byKey('reading_stats_detail_row_a'), findsNothing);
      expect(_painterOf(tester, '2026-09-29').level, 0);
      expect(_byKey('reading_stats_clear_success_snackbar'), findsOneWidget);
    });

    testWidgets('先選了過去的日期再清除：清除後選取日回到今天', (tester) async {
      final repo = FakeReadingStatsRepository(initialStats: {
        '2026-09-28': [_stat('a', 'A', 600)],
        '2026-09-29': [_stat('a', 'A', 1800)],
      });
      await _pumpScreen(tester, repo);

      await tester.tap(_cell('2026-09-28')); // 選昨天
      await tester.pumpAndSettle();
      expect(_textOf(tester, 'reading_stats_detail_title'), contains('9/28'));

      await tester.tap(_byKey('reading_stats_clear_all_button'));
      await tester.pumpAndSettle();
      await tester.tap(_byKey('reading_stats_clear_all_confirm_button'));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(_byKey('heatmap_selection_outline')),
          tester.getTopLeft(_cell('2026-09-29')));
      expect(_textOf(tester, 'reading_stats_detail_title'), contains('9/29'));
      expect(_byKey('reading_stats_detail_empty'), findsOneWidget);
    });

    testWidgets('E-Ink 下對話框可正常開啟與確認', (tester) async {
      final repo = seeded();
      await _pumpScreen(tester, repo, isEinkMode: true);

      await tester.tap(_byKey('reading_stats_clear_all_button'));
      await tester.pump(); // 無動畫：一次 pump 就該出現
      expect(_byKey('reading_stats_clear_all_dialog'), findsOneWidget);

      await tester.tap(_byKey('reading_stats_clear_all_confirm_button'));
      await tester.pumpAndSettle();
      expect(await repo.getTotalReadingSeconds(), 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('主題與 E-Ink', () {
    testWidgets('Light／Dark／Sepia 皆能渲染，方格底色取自 Token', (tester) async {
      for (final theme in AppTheme.values) {
        final repo = FakeReadingStatsRepository(initialStats: {
          '2026-09-29': [_stat('a', 'A', 3600)],
        });
        await _pumpScreen(tester, repo, theme: theme);
        expect(tester.takeException(), isNull);
        final tokens = Theme.of(tester.element(find.byType(ReadingStatsScreen)))
            .extension<ElinkTokens>()!;
        expect(_painterOf(tester, '2026-09-29').fillColor, tokens.heatmapLevel4);
        expect(_painterOf(tester, '2026-09-28').fillColor, tokens.heatmapLevel0);
      }
    });

    testWidgets('E-Ink：五級可區分（灰階＋紋理），不依賴色相', (tester) async {
      final repo = FakeReadingStatsRepository(initialStats: {
        '2026-09-25': [_stat('a', 'A', 60)],
        '2026-09-26': [_stat('a', 'A', 900)],
        '2026-09-27': [_stat('a', 'A', 1800)],
        '2026-09-28': [_stat('a', 'A', 3600)],
      });
      await _pumpScreen(tester, repo, isEinkMode: true);

      final painters = [
        for (final d in [
          '2026-09-24', // 第 0 級
          '2026-09-25',
          '2026-09-26',
          '2026-09-27',
          '2026-09-28',
        ])
          _painterOf(tester, d),
      ];
      expect(painters.map((p) => p.level), [0, 1, 2, 3, 4]);
      expect(painters.every((p) => p.isEink), isTrue);
      expect(painters.map((p) => p.texture).toSet().length, 5);
      expect(painters.map((p) => p.fillColor).toSet().length, 5);
    });
  });

  group('介面語言', () {
    testWidgets('正體中文', (tester) async {
      await _pumpScreen(tester, FakeReadingStatsRepository());
      expect(find.text('閱讀統計'), findsOneWidget);
      expect(find.text('累計閱讀時數'), findsOneWidget);
      expect(find.text('當日無閱讀記錄'), findsOneWidget);
      expect(find.text('清除全部統計'), findsOneWidget);
    });

    testWidgets('簡體中文', (tester) async {
      await _pumpScreen(tester, FakeReadingStatsRepository(),
          locale: const Locale('zh', 'CN'));
      expect(find.text('阅读统计'), findsOneWidget);
      expect(find.text('累计阅读时长'), findsOneWidget);
      expect(find.text('当日无阅读记录'), findsOneWidget);
      expect(find.text('清除全部统计'), findsOneWidget);
    });

    testWidgets('英文', (tester) async {
      await _pumpScreen(tester, FakeReadingStatsRepository(),
          locale: const Locale('en'));
      expect(tester.takeException(), isNull);
      expect(find.text('Reading Stats'), findsOneWidget);
      expect(find.text('Total Reading Time'), findsOneWidget);
      expect(find.text('No reading on this day'), findsOneWidget);
      expect(find.text('Clear All Stats'), findsOneWidget);
    });
  });
}
