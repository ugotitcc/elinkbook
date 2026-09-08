import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/widgets/reader_option_tile.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

void main() {
  testWidgets('ReaderOptionTile 在 E-Ink 模式下選中項目呈現黑底白字高對比', (tester) async {
    String selectedValue = 'A';

    await tester.pumpWidget(MaterialApp(
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Row(
            children: [
              ReaderOptionTile<String>(
                itemKey: const Key('tile_a'),
                value: 'A',
                groupValue: selectedValue,
                icon: Icons.crop_portrait,
                tooltip: '選項 A',
                onSelected: (v) => setState(() => selectedValue = v),
              ),
              ReaderOptionTile<String>(
                itemKey: const Key('tile_b'),
                value: 'B',
                groupValue: selectedValue,
                icon: Icons.crop_landscape,
                tooltip: '選項 B',
                onSelected: (v) => setState(() => selectedValue = v),
              ),
            ],
          ),
        ),
      ),
    ));

    // 【審查修正 Important】key 直接掛在帶 BoxDecoration 的 Container 上
    // （見 Task 1 Step 3 實作），不再用 find.descendant(...).first 這種
    // 依賴子樹結構的脆弱寫法（見 reviews/review-plan-issue-5-8.md Issue 6
    // Important #2）。
    final tileA = tester.widget<Container>(find.byKey(const Key('tile_a')));
    final boxDecorationA = tileA.decoration as BoxDecoration;
    expect(boxDecorationA.color, Colors.black);

    final tileB = tester.widget<Container>(find.byKey(const Key('tile_b')));
    final boxDecorationB = tileB.decoration as BoxDecoration;
    expect(boxDecorationB.color, Colors.white);

    // 點擊切換至 B
    await tester.tap(find.byKey(const Key('tile_b')));
    await tester.pumpAndSettle();

    expect(selectedValue, 'B');
  });

  testWidgets('iconSize 覆寫圖示大小，未提供時維持既有預設值 20', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ReaderOptionTile<String>(
              itemKey: const Key('tile_default'),
              value: 'A',
              groupValue: 'A',
              icon: Icons.crop_portrait,
              tooltip: '預設大小',
              onSelected: (_) {},
            ),
            ReaderOptionTile<String>(
              itemKey: const Key('tile_custom'),
              value: 'B',
              groupValue: 'A',
              icon: Icons.crop_landscape,
              tooltip: '自訂大小',
              iconSize: 16,
              onSelected: (_) {},
            ),
          ],
        ),
      ),
    ));

    final defaultIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('tile_default')),
        matching: find.byType(Icon),
      ),
    );
    final customIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('tile_custom')),
        matching: find.byType(Icon),
      ),
    );
    expect(defaultIcon.size, 20);
    expect(customIcon.size, 16);
  });

  testWidgets('labelFontSize 覆寫標籤文字大小，未提供時維持既有預設值 13', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ReaderOptionTile<String>(
              itemKey: const Key('tile_default_label'),
              value: 'A',
              groupValue: 'A',
              icon: Icons.crop_portrait,
              label: '預設',
              tooltip: '預設大小',
              onSelected: (_) {},
            ),
            ReaderOptionTile<String>(
              itemKey: const Key('tile_custom_label'),
              value: 'B',
              groupValue: 'A',
              icon: Icons.crop_landscape,
              label: '自訂',
              tooltip: '自訂大小',
              labelFontSize: 11,
              onSelected: (_) {},
            ),
          ],
        ),
      ),
    ));

    final defaultText = tester.widget<Text>(find.text('預設'));
    final customText = tester.widget<Text>(find.text('自訂'));
    expect(defaultText.style?.fontSize, 13);
    expect(customText.style?.fontSize, 11);
  });

  testWidgets('forceUnselected: true 時，即使 value == groupValue 仍呈現未選中樣式',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: ReaderOptionTile<String>(
          itemKey: const Key('tile_forced'),
          value: 'A',
          groupValue: 'A', // 故意讓 value == groupValue
          icon: Icons.crop,
          tooltip: '動作型項目',
          forceUnselected: true,
          onSelected: (_) {},
        ),
      ),
    ));

    final tile = tester.widget<Container>(find.byKey(const Key('tile_forced')));
    final decoration = tile.decoration as BoxDecoration;
    // E-Ink 主題下未選中樣式底色為白色（見既有 build() 邏輯），
    // 若 forceUnselected 沒有生效，value==groupValue 會被判定為選中、
    // 底色變黑。
    expect(decoration.color, Colors.white);
  });
}