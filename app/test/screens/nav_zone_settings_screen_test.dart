import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/screens/nav_zone_settings_screen.dart';
import '../support/fake_reader_prefs_manager.dart';

void main() {
  testWidgets('載入完成前顯示載入指示器，載入完成後顯示「翻頁方式」二選一與 3 張模板卡片', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));

    expect(
      find.byKey(const Key('nav_zone_settings_loading_indicator')),
      findsOneWidget,
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('nav_zone_settings_loading_indicator')),
      findsNothing,
    );
    expect(find.byKey(const Key('nav_zone_template_toggle')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_leftFlip')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_rightFlip')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_oneHand')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_custom')), findsNothing);
  });

  testWidgets(
      '「單手」模板卡片改為 3 列縮圖，依列顯示選單／上一頁／下一頁圖示，左右欄鏡射相同、中欄留白'
      '（epic-18-reader-device-qa Issue 36，取代 Issue 30 誤導的左右各一顆不同 chevron 設計）',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final icons = tester
        .widgetList<Icon>(find.descendant(
          of: find.byKey(const Key('nav_zone_mode_oneHand')),
          matching: find.byType(Icon),
        ))
        .map((icon) => icon.icon)
        .toList();

    expect(icons.where((icon) => icon == Icons.menu), hasLength(2),
        reason: '上排左右欄對應 oneHandZoneTemplate 的 menu 動作，左右鏡射相同');
    expect(icons.where((icon) => icon == Icons.chevron_left), hasLength(2),
        reason: '中排左右欄對應 previousPage 動作，左右鏡射相同');
    expect(icons.where((icon) => icon == Icons.chevron_right), hasLength(2),
        reason: '下排左右欄對應 nextPage 動作，左右鏡射相同');
    expect(icons, isNot(contains(Icons.touch_app)));
  });

  testWidgets('SegmentedButton 選中狀態正確反映 navZoneMode：簡單模板對應「簡單」，隱藏 9 格編輯器',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(navZoneMode: NavZoneMode.oneHand),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final toggle = tester.widget<SegmentedButton<bool>>(
      find.byKey(const Key('nav_zone_template_toggle')),
    );
    expect(toggle.selected, {false});
    expect(find.byKey(const Key('nav_zone_mode_leftFlip')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsNothing);
  });

  testWidgets('SegmentedButton 選中狀態正確反映 navZoneMode：custom 對應「自訂」，顯示 9 格編輯器',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(navZoneMode: NavZoneMode.custom),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final toggle = tester.widget<SegmentedButton<bool>>(
      find.byKey(const Key('nav_zone_template_toggle')),
    );
    expect(toggle.selected, {true});
    expect(find.byKey(const Key('nav_zone_mode_leftFlip')), findsNothing);
    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsOneWidget);
  });

  testWidgets('點擊「左翻頁」模板卡片觸發 GlobalReaderPrefs 更新為 leftFlip', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_zone_mode_leftFlip')));
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls, isNotEmpty);
    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneMode,
      NavZoneMode.leftFlip,
    );
  });

  testWidgets('點擊「單手」模板卡片觸發 GlobalReaderPrefs 更新為 oneHand', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_zone_mode_oneHand')));
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneMode,
      NavZoneMode.oneHand,
    );
  });

  testWidgets('選中的模板卡片顯示 primary 色外框，未選中則為預設 dividerColor 外框', (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(navZoneMode: NavZoneMode.leftFlip),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NavZoneSettingsScreen));
    final primaryColor = Theme.of(context).colorScheme.primary;
    final dividerColor = Theme.of(context).dividerColor;

    final leftFlipCard = tester.widget<Container>(
      find.byKey(const Key('nav_zone_mode_leftFlip')),
    );
    final leftFlipBorder =
        (leftFlipCard.decoration as BoxDecoration).border as Border;
    expect(leftFlipBorder.top.color, primaryColor);

    final rightFlipCard = tester.widget<Container>(
      find.byKey(const Key('nav_zone_mode_rightFlip')),
    );
    final rightFlipBorder =
        (rightFlipCard.decoration as BoxDecoration).border as Border;
    expect(rightFlipBorder.top.color, dividerColor);
  });

  testWidgets('點擊「自訂」segment，切換為 custom 模式並顯示 9 格編輯器', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自訂'));
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneMode,
      NavZoneMode.custom,
    );
    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsOneWidget);
  });

  testWidgets('在「自訂」模式下點擊「簡單」segment，切換回 rightFlip 模板並隱藏 9 格編輯器',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(navZoneMode: NavZoneMode.custom),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('簡單'));
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneMode,
      NavZoneMode.rightFlip,
    );
    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsNothing);
    expect(find.byKey(const Key('nav_zone_mode_rightFlip')), findsOneWidget);
  });

  testWidgets('模式切換（簡單→自訂→簡單→自訂）不影響既有 navZoneCustomActions 資料', (tester) async {
    const customActions = [
      ZoneAction.menu, ZoneAction.none, ZoneAction.none,
      ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ];
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        navZoneMode: NavZoneMode.custom,
        navZoneCustomActions: customActions,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('簡單'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsNothing);

    await tester.tap(find.text('自訂'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('nav_zone_custom_cell_0')),
        matching: find.text('選單'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('nav_zone_custom_cell_3')),
        matching: find.text('上一頁'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('nav_zone_custom_cell_5')),
        matching: find.text('下一頁'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('切換「顯示熱區輔助線」開關觸發 GlobalReaderPrefs 更新', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('nav_zone_debug_overlay_switch')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('nav_zone_debug_overlay_switch')));
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.showNavZoneDebugOverlay,
      isTrue,
    );
  });

  testWidgets('選到「自訂」後顯示 9 格編輯器，逐格點擊循環切換 4 種動作', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);

    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自訂'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nav_zone_custom_cell_0')), findsOneWidget);
    // rightFlip 預設模板第 0 格為 previousPage。
    expect(find.text('上一頁'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();
    expect(find.text('下一頁'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();
    expect(find.text('選單'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();
    expect(find.text('無動作'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_zone_custom_cell_0')));
    await tester.pump();
    expect(find.text('上一頁'), findsWidgets);
  });

  testWidgets('儲存自訂設定時，全部非 menu 會被擋下（錯誤提示存在、儲存回呼未被觸發）',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);

    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自訂'));
    await tester.pumpAndSettle();
    final savedCallCountAfterModeSwitch =
        fakeManager.savedGlobalPrefsCalls.length;

    // rightFlip 預設模板的 menu 格在 index 1/4/7，各點擊一次轉為 none。
    final cell1 = find.byKey(const Key('nav_zone_custom_cell_1'));
    await tester.ensureVisible(cell1);
    await tester.tap(cell1);
    await tester.pump();

    final cell4 = find.byKey(const Key('nav_zone_custom_cell_4'));
    await tester.ensureVisible(cell4);
    await tester.tap(cell4);
    await tester.pump();

    final cell7 = find.byKey(const Key('nav_zone_custom_cell_7'));
    await tester.ensureVisible(cell7);
    await tester.tap(cell7);
    await tester.pump();

    expect(
      find.byKey(const Key('nav_zone_custom_validation_error')),
      findsNothing,
    );

    final saveButton = find.byKey(const Key('nav_zone_save_custom_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(
      find.byKey(const Key('nav_zone_custom_validation_error')),
      findsOneWidget,
    );
    expect(
      fakeManager.savedGlobalPrefsCalls.length,
      savedCallCountAfterModeSwitch,
    );
  });

  testWidgets('儲存自訂設定時，至少 1 格為 menu 則成功儲存並清除錯誤提示', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);

    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自訂'));
    await tester.pumpAndSettle();

    // 修改第 0 格（原為 previousPage），其餘 menu 格（index 1/4/7）不動，
    // 陣列仍然合法。
    final cell0 = find.byKey(const Key('nav_zone_custom_cell_0'));
    await tester.ensureVisible(cell0);
    await tester.tap(cell0);
    await tester.pump();

    final saveButton = find.byKey(const Key('nav_zone_save_custom_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(
      find.byKey(const Key('nav_zone_custom_validation_error')),
      findsNothing,
    );
    expect(
      fakeManager.savedGlobalPrefsCalls.last.navZoneCustomActions[0],
      ZoneAction.nextPage,
    );
  });

  group('navZoneTemplateIconColor（epic-18-reader-device-qa Issue 44）', () {
    test('chevron_left 恆為紅色', () {
      expect(navZoneTemplateIconColor(Icons.chevron_left), Colors.red.shade100);
    });

    test('chevron_right 恆為藍色', () {
      expect(navZoneTemplateIconColor(Icons.chevron_right), Colors.blue.shade100);
    });

    test('menu 恆為綠色', () {
      expect(navZoneTemplateIconColor(Icons.menu), Colors.green.shade100);
    });
  });

  testWidgets(
      '「左翻頁」與「右翻頁」卡片對同一個圖示（chevron_left／chevron_right）'
      '使用相同顏色（epic-18-reader-device-qa Issue 44，真機使用回報：'
      '兩張卡片原本用欄位位置決定顏色，導致同一個 < 圖示在兩張卡片上顏色'
      '不同）', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    /// 從卡片內找出指定圖示所在色塊 Container 的 color
    Color colorOfIcon(Key cardKey, IconData icon) {
      final containers = tester.widgetList<Container>(find.descendant(
        of: find.byKey(cardKey),
        matching: find.byType(Container),
      ));
      for (final container in containers) {
        if (container.color != null && container.child is Icon) {
          final iconWidget = container.child as Icon;
          if (iconWidget.icon == icon) return container.color!;
        }
      }
      throw StateError('No Container with Icon $icon found in card $cardKey');
    }

    final leftFlipChevronLeftColor =
        colorOfIcon(const Key('nav_zone_mode_leftFlip'), Icons.chevron_left);
    final rightFlipChevronLeftColor =
        colorOfIcon(const Key('nav_zone_mode_rightFlip'), Icons.chevron_left);
    expect(leftFlipChevronLeftColor, rightFlipChevronLeftColor);

    final leftFlipChevronRightColor =
        colorOfIcon(const Key('nav_zone_mode_leftFlip'), Icons.chevron_right);
    final rightFlipChevronRightColor =
        colorOfIcon(const Key('nav_zone_mode_rightFlip'), Icons.chevron_right);
    expect(leftFlipChevronRightColor, rightFlipChevronRightColor);
  });
}
