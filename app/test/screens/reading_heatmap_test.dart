import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/widgets/reading_heatmap.dart';
import 'package:elinkbook/stats/heatmap_grid.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

import '../support/pump_localized_widget.dart';

final _grid = buildHeatmapGrid(DateTime(2026, 9, 29));

Finder _cell(String date) => find.byKey(Key('heatmap_cell_$date'));

HeatmapCellPainter _painterOf(WidgetTester tester, String date) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: _cell(date), matching: find.byType(CustomPaint)),
  );
  return paint.painter! as HeatmapCellPainter;
}

Finder get _allCells => find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> && k.value.startsWith('heatmap_cell_');
    });

// 透明佔位以 `heatmap_placeholder_<week>_<row>` 座標鍵唯一標識（全域單一 Key
// 會因同 Column 重複而觸發 duplicate-keys 斷言），測試以此前綴定位。
Finder get _placeholders => find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> &&
          k.value.startsWith('heatmap_placeholder');
    });

Future<ScrollController> _pump(
  WidgetTester tester, {
  Map<String, int> totals = const {},
  String? selected,
  ValueChanged<String>? onSelect,
  bool isEink = false,
  AppTheme theme = AppTheme.light,
  Locale locale = const Locale('zh', 'TW'),
}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await pumpLocalizedWidget(
    tester,
    Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ReadingHeatmap(
              grid: _grid,
              dailyTotals: totals,
              selectedDate: selected,
              onSelectDate: onSelect ?? (_) {},
              scrollController: controller,
            ),
            const ReadingHeatmapLegend(),
          ],
        ),
      ),
    ),
    isEinkMode: isEink,
    theme: theme,
    locale: locale,
  );
  // 同一 testWidgets 內換主題重 pump 時，MaterialApp 的 AnimatedTheme 需要
  // 走完 200ms 才切換完成；用 pumpAndSettle 確保 Theme.of 讀到當次主題，
  // 否則第二次 pump 讀到的仍是上一次的主題（outline 粗細／Token 色驗證會錯）。
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('365 個有效方格與 6 個透明佔位', (tester) async {
    await _pump(tester);
    expect(_allCells, findsNWidgets(365));
    expect(_placeholders, findsNWidgets(6));
  });

  testWidgets('一週從週一開始：同週同欄、列距 19、上週在左一欄', (tester) async {
    await _pump(tester);
    final mon = tester.getTopLeft(_cell('2026-09-28')); // 週一 row 0
    final tue = tester.getTopLeft(_cell('2026-09-29')); // 週二 row 1
    final prevSun = tester.getTopLeft(_cell('2026-09-27')); // 上週日 row 6
    expect(tue.dx, mon.dx);
    expect(tue.dy - mon.dy, kHeatmapPitch);
    expect(prevSun.dx, mon.dx - kHeatmapPitch);
    expect(prevSun.dy - mon.dy, 6 * kHeatmapPitch);
  });

  testWidgets('五級分級邊界對應正確的方格級別', (tester) async {
    await _pump(tester, totals: {
      '2026-09-21': 1,
      '2026-09-22': 899,
      '2026-09-23': 900,
      '2026-09-24': 1799,
      '2026-09-25': 1800,
      '2026-09-26': 3599,
      '2026-09-27': 3600,
      // 2026-09-28 沒有紀錄
    });
    final levels = [
      for (final d in [
        '2026-09-21',
        '2026-09-22',
        '2026-09-23',
        '2026-09-24',
        '2026-09-25',
        '2026-09-26',
        '2026-09-27',
        '2026-09-28',
      ])
        _painterOf(tester, d).level,
    ];
    expect(levels, [1, 1, 2, 2, 3, 3, 4, 0]);
  });

  testWidgets('星期欄不隨水平捲動移動，且標籤與同列方格頂端對齊', (tester) async {
    final controller = await _pump(tester);
    final before = tester.getTopLeft(find.byKey(const Key('heatmap_weekday_column')));

    controller.jumpTo(0);
    await tester.pump();
    final atStart = tester.getTopLeft(find.byKey(const Key('heatmap_weekday_column')));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    final atEnd = tester.getTopLeft(find.byKey(const Key('heatmap_weekday_column')));

    expect(atStart, before);
    expect(atEnd, before);
    expect(controller.position.maxScrollExtent, greaterThan(0));

    // 週一標籤（第 0 列）與週一方格頂端同高；週三、週五分別是第 2、4 列
    final monY = tester.getTopLeft(_cell('2026-09-28')).dy;
    expect(tester.getTopLeft(find.byKey(const Key('heatmap_weekday_label_mon'))).dy, monY);
    expect(tester.getTopLeft(find.byKey(const Key('heatmap_weekday_label_wed'))).dy,
        monY + 2 * kHeatmapPitch);
    expect(tester.getTopLeft(find.byKey(const Key('heatmap_weekday_label_fri'))).dy,
        monY + 4 * kHeatmapPitch);
  });

  testWidgets('選取外框疊在被選方格上；E-Ink 外框較粗；未選取時不畫', (tester) async {
    await _pump(tester, selected: '2026-09-29');
    final outline = find.byKey(const Key('heatmap_selection_outline'));
    expect(outline, findsOneWidget);
    expect(tester.getTopLeft(outline), tester.getTopLeft(_cell('2026-09-29')));
    final normal = tester.widget<CustomPaint>(outline).painter!
        as HeatmapSelectionOutlinePainter;
    expect(normal.strokeWidth, 2);

    await _pump(tester, selected: '2026-09-29', isEink: true);
    final eink = tester.widget<CustomPaint>(find.byKey(const Key('heatmap_selection_outline')))
        .painter! as HeatmapSelectionOutlinePainter;
    expect(eink.strokeWidth, 3);

    await _pump(tester, selected: null);
    expect(find.byKey(const Key('heatmap_selection_outline')), findsNothing);
  });

  testWidgets('選取外框在捲動範圍內留有 4dp 以上的餘裕（外框外擴不被裁掉）', (tester) async {
    Rect scrollRect() =>
        tester.getRect(find.byKey(const Key('reading_stats_heatmap')));
    Rect outlineRect() =>
        tester.getRect(find.byKey(const Key('heatmap_selection_outline')));

    // 最下列（週日）：下緣要有留白
    var c = await _pump(tester, isEink: true, selected: '2026-09-27');
    c.jumpTo(c.position.maxScrollExtent);
    await tester.pump();
    expect(scrollRect().bottom - outlineRect().bottom, greaterThanOrEqualTo(4));

    // 最左欄（網格第一天）：捲到最左時左緣要有留白
    c = await _pump(tester, isEink: true, selected: _grid.startDate);
    c.jumpTo(0);
    await tester.pump();
    expect(outlineRect().left - scrollRect().left, greaterThanOrEqualTo(4));

    // 最右欄（今天）：捲到最右時右緣要有留白
    c = await _pump(tester, isEink: true, selected: _grid.endDate);
    c.jumpTo(c.position.maxScrollExtent);
    await tester.pump();
    expect(scrollRect().right - outlineRect().right, greaterThanOrEqualTo(4));
  });

  testWidgets('點方格回呼該日期；透明佔位不可點', (tester) async {
    final tapped = <String>[];
    final controller = await _pump(tester, onSelect: tapped.add);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    await tester.tap(_cell('2026-09-28'));
    expect(tapped, ['2026-09-28']);

    await tester.tap(_placeholders.first,
        warnIfMissed: false);
    expect(tapped, ['2026-09-28']);
  });

  group('E-Ink 呈現', () {
    testWidgets('五級紋理各不相同：留白、網點、單向斜線、交叉線、實心', (tester) async {
      await _pump(tester, isEink: true, totals: {
        '2026-09-22': 1,
        '2026-09-23': 900,
        '2026-09-24': 1800,
        '2026-09-25': 3600,
      });
      final textures = [
        for (final d in [
          '2026-09-21', // 無紀錄
          '2026-09-22',
          '2026-09-23',
          '2026-09-24',
          '2026-09-25',
        ])
          _painterOf(tester, d).texture,
      ];
      expect(textures, [
        HeatmapTexture.none,
        HeatmapTexture.dots,
        HeatmapTexture.diagonal,
        HeatmapTexture.cross,
        HeatmapTexture.solid,
      ]);
      expect(textures.toSet().length, 5);
    });

    testWidgets('網點級畫圓點、斜線級畫直線（實際有畫出紋理）', (tester) async {
      await _pump(tester, isEink: true, totals: {
        '2026-09-22': 1,
        '2026-09-23': 900,
      });
      RenderObject renderOf(String d) => tester.renderObject(
          find.descendant(of: _cell(d), matching: find.byType(CustomPaint)));
      expect(renderOf('2026-09-22'), paints..circle());
      expect(renderOf('2026-09-23'), paints..line());
    });

    testWidgets('紋理（網點／斜線／交叉線）繪製前先裁切在方格內縮 1px 的範圍', (tester) async {
      await _pump(tester, isEink: true, totals: {
        '2026-09-22': 1, // 第 1 級：網點
        '2026-09-23': 900, // 第 2 級：斜線
        '2026-09-24': 1800, // 第 3 級：交叉線
      });
      // 斜線端點本來就會超出方格；沒有 clipRect 就會畫進格間縫隙與鄰格
      const clip =
          Rect.fromLTWH(1, 1, kHeatmapCellSize - 2, kHeatmapCellSize - 2);
      RenderObject renderOf(String d) => tester.renderObject(
          find.descendant(of: _cell(d), matching: find.byType(CustomPaint)));
      expect(renderOf('2026-09-22'), paints..clipRect(rect: clip)..circle());
      expect(renderOf('2026-09-23'), paints..clipRect(rect: clip)..line());
      expect(renderOf('2026-09-24'), paints..clipRect(rect: clip)..line());
    });

    testWidgets('非 E-Ink 主題不畫紋理，底色取自 Token', (tester) async {
      for (final theme in AppTheme.values) {
        await _pump(tester, theme: theme, totals: {'2026-09-25': 3600});
        final tokens = Theme.of(tester.element(find.byType(ReadingHeatmap)))
            .extension<ElinkTokens>()!;
        final p = _painterOf(tester, '2026-09-25');
        expect(p.isEink, isFalse);
        expect(p.texture, HeatmapTexture.none);
        expect(p.fillColor, tokens.heatmapLevel4);
        expect(_painterOf(tester, '2026-09-21').fillColor, tokens.heatmapLevel0);
      }
    });
  });

  testWidgets('英文介面：星期標籤單行不溢位、與正體中文版對齊一致', (tester) async {
    await _pump(tester, locale: const Locale('en'));
    expect(tester.takeException(), isNull);
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Wed'), findsOneWidget);
    expect(find.text('Fri'), findsOneWidget);
    final monY = tester.getTopLeft(_cell('2026-09-28')).dy;
    expect(tester.getTopLeft(find.byKey(const Key('heatmap_weekday_label_mon'))).dy, monY);
    // 標籤欄要寬到放得下「Mon」而不擠壓到方格區
    final columnRight =
        tester.getTopRight(find.byKey(const Key('heatmap_weekday_column'))).dx;
    final scrollLeft =
        tester.getTopLeft(find.byKey(const Key('reading_stats_heatmap'))).dx;
    expect(columnRight, lessThanOrEqualTo(scrollLeft));
  });

  testWidgets('圖例顯示「較少」「較多」與五個級別方格', (tester) async {
    await _pump(tester);
    final legend = find.byKey(const Key('reading_stats_legend'));
    expect(legend, findsOneWidget);
    expect(find.descendant(of: legend, matching: find.byType(CustomPaint)),
        findsNWidgets(5));
    expect(find.text('較少'), findsOneWidget);
    expect(find.text('較多'), findsOneWidget);
  });
}
