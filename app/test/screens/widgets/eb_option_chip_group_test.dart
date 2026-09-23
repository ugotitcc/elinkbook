import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/widgets/eb_option_chip_group.dart';

void main() {
  List<EBOptionChipItem<String>> buildItems({VoidCallback? onManualTap}) {
    return [
      EBOptionChipItem<String>(
        itemKey: const Key('chip_a'),
        value: 'A',
        icon: Icons.crop_portrait,
        label: '甲',
        tooltip: '選項甲',
      ),
      EBOptionChipItem<String>(
        itemKey: const Key('chip_b'),
        value: 'B',
        icon: Icons.crop_landscape,
        label: '乙',
        tooltip: '選項乙',
      ),
      EBOptionChipItem<String>(
        itemKey: const Key('chip_c'),
        value: 'C',
        icon: Icons.crop_square,
        label: '丙',
        tooltip: '選項丙',
      ),
      if (onManualTap != null)
        EBOptionChipItem<String>(
          itemKey: const Key('chip_action'),
          value: 'C', // 故意跟丙相同值，驗證 onTap 項目不受 groupValue 比對影響
          icon: Icons.touch_app,
          label: '動作',
          tooltip: '動作項目',
          onTap: onManualTap,
        ),
    ];
  }

  Widget buildGroup({
    required double width,
    String groupValue = 'A',
    ValueChanged<String>? onSelected,
    VoidCallback? onManualTap,
  }) {
    return MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: EBOptionChipGroup<String>(
            items: buildItems(onManualTap: onManualTap),
            groupValue: groupValue,
            onSelected: onSelected ?? (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('寬度充足（>=360）時，圖示為 20sp、文字為 13sp', (tester) async {
    await tester.pumpWidget(buildGroup(width: 400));

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('chip_a')),
        matching: find.byType(Icon),
      ),
    );
    final label = tester.widget<Text>(find.text('甲'));
    expect(icon.size, 20);
    expect(label.style?.fontSize, 13);
  });

  testWidgets('點擊 chip 觸發 onSelected 並帶入該 chip 的 value', (tester) async {
    String? selected;
    await tester.pumpWidget(
      buildGroup(width: 400, onSelected: (v) => selected = v),
    );

    await tester.tap(find.byKey(const Key('chip_b')));

    expect(selected, 'B');
  });

  testWidgets('寬度極小（<=240）時，圖示為 16sp、文字為 11sp', (tester) async {
    await tester.pumpWidget(buildGroup(width: 240));

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('chip_a')),
        matching: find.byType(Icon),
      ),
    );
    final label = tester.widget<Text>(find.text('甲'));
    expect(icon.size, 16);
    expect(label.style?.fontSize, 11);
  });

  testWidgets('寬度介於門檻之間時，尺寸線性介於上下限之間', (tester) async {
    await tester.pumpWidget(buildGroup(width: 300)); // (300-240)/(360-240) = 0.5

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('chip_a')),
        matching: find.byType(Icon),
      ),
    );
    expect(icon.size, greaterThan(16));
    expect(icon.size, lessThan(20));
  });

  testWidgets('寬度低於 200 時，不顯示 label 文字，只留圖示', (tester) async {
    await tester.pumpWidget(buildGroup(width: 150));

    expect(find.text('甲'), findsNothing);
    expect(find.text('乙'), findsNothing);
    expect(find.text('丙'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('chip_a')),
        matching: find.byType(Icon),
      ),
      findsOneWidget,
    );
  });

  testWidgets('6 個項目的群組在常規手機寬度（約 328dp）下不會因為除以項目數而隱藏 label'
      '（回歸保護：審查發現原「maxWidth / items.length」公式在此寬度會誤判過窄）',
      (tester) async {
    final sixItems = List.generate(
      6,
      (i) => EBOptionChipItem<int>(
        itemKey: Key('six_$i'),
        value: i,
        icon: Icons.circle,
        label: '選$i',
        tooltip: '選項 $i',
      ),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 328,
          child: EBOptionChipGroup<int>(
            items: sixItems,
            groupValue: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    ));

    for (var i = 0; i < 6; i++) {
      expect(find.text('選$i'), findsOneWidget);
    }
  });

  testWidgets('item.onTap 非 null 時，點擊觸發 onTap 而非 onSelected', (tester) async {
    var manualTapped = false;
    String? selected;
    await tester.pumpWidget(buildGroup(
      width: 400,
      groupValue: 'C', // 與 chip_action 的 value 相同
      onSelected: (v) => selected = v,
      onManualTap: () => manualTapped = true,
    ));

    await tester.tap(find.byKey(const Key('chip_action')));

    expect(manualTapped, isTrue);
    expect(selected, isNull);
  });

  testWidgets('item.onTap 非 null 時，該 chip 恆為未選中樣式（即使 value == groupValue）',
      (tester) async {
    await tester.pumpWidget(buildGroup(
      width: 400,
      groupValue: 'C', // 與 chip_action 的 value 相同、也與 chip_c 相同
      onManualTap: () {},
    ));

    final actionTile =
        tester.widget<Container>(find.byKey(const Key('chip_action')));
    final normalTile = tester.widget<Container>(find.byKey(const Key('chip_c')));
    final actionDecoration = actionTile.decoration as BoxDecoration;
    final normalDecoration = normalTile.decoration as BoxDecoration;
    // chip_c 的 value 與 groupValue 相同，應呈現選中樣式；chip_action 的
    // value 雖然也相同，但 onTap 非 null 應強制未選中，兩者底色應不同。
    expect(actionDecoration.color, isNot(normalDecoration.color));
  });

  testWidgets('T 為 nullable 型別（WritingMode?）且選項值含 null 時，選中比對正確',
      (tester) async {
    WritingMode? selected = WritingMode.horizontal;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: EBOptionChipGroup<WritingMode?>(
              items: const [
                EBOptionChipItem<WritingMode?>(
                  itemKey: Key('writing_mode_book'),
                  value: null,
                  icon: Icons.auto_stories,
                  label: '書籍',
                  tooltip: '採用書籍排版',
                ),
                EBOptionChipItem<WritingMode?>(
                  itemKey: Key('writing_mode_vertical'),
                  value: WritingMode.vertical,
                  icon: Icons.text_rotate_vertical,
                  label: '直排',
                  tooltip: '強制直排',
                ),
              ],
              groupValue: selected,
              onSelected: (v) => setState(() => selected = v),
            ),
          ),
        ),
      ),
    ));

    // 初始 groupValue 是 WritingMode.horizontal，兩個選項皆不相符，兩者
    // 都應呈現未選中樣式（不應有任何一個誤判為選中）。
    final bookTile =
        tester.widget<Container>(find.byKey(const Key('writing_mode_book')));
    final verticalTile = tester.widget<Container>(
        find.byKey(const Key('writing_mode_vertical')));
    expect(
      (bookTile.decoration as BoxDecoration).color,
      (verticalTile.decoration as BoxDecoration).color,
    );

    // 點擊「書籍」（value: null）應正確觸發 onSelected(null)。
    await tester.tap(find.byKey(const Key('writing_mode_book')));
    await tester.pump();
    expect(selected, isNull);

    // groupValue 變成 null 後，「書籍」這個 value 同為 null 的選項應正確
    // 判定為選中（與「直排」呈現不同底色）。
    final bookTileAfter =
        tester.widget<Container>(find.byKey(const Key('writing_mode_book')));
    final verticalTileAfter = tester.widget<Container>(
        find.byKey(const Key('writing_mode_vertical')));
    expect(
        (bookTileAfter.decoration as BoxDecoration).color,
        isNot((verticalTileAfter.decoration as BoxDecoration).color),
    );
  });

  testWidgets('支援自訂 iconWidget 替代預設 IconData', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: EBOptionChipGroup<String>(
          items: [
            EBOptionChipItem<String>(
              itemKey: const Key('custom_widget_chip'),
              value: 'custom',
              iconWidget: const Text('自訂圖示', key: Key('custom_icon_text')),
              label: '標籤',
              tooltip: '提示',
            ),
          ],
          groupValue: 'custom',
          onSelected: (_) {},
        ),
      ),
    ));

    expect(find.byKey(const Key('custom_icon_text')), findsOneWidget);
    expect(find.text('標籤'), findsOneWidget);
  });
}
