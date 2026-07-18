import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/screens/nav_zone_settings_screen.dart';
import '../support/fake_reader_prefs_manager.dart';

void main() {
  testWidgets('載入完成前顯示載入指示器，載入完成後顯示四選一模板', (tester) async {
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
    expect(find.byKey(const Key('nav_zone_mode_leftFlip')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_rightFlip')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_oneHand')), findsOneWidget);
    expect(find.byKey(const Key('nav_zone_mode_custom')), findsOneWidget);
  });

  testWidgets('點擊「左翻頁」模板觸發 GlobalReaderPrefs 更新為 leftFlip', (tester) async {
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

  testWidgets('點擊「單手」模板觸發 GlobalReaderPrefs 更新為 oneHand', (tester) async {
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

    await tester.tap(find.byKey(const Key('nav_zone_mode_custom')));
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

    await tester.tap(find.byKey(const Key('nav_zone_mode_custom')));
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

    await tester.tap(find.byKey(const Key('nav_zone_mode_custom')));
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
}
