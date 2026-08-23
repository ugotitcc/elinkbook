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
}