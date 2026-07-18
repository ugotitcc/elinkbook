import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
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
}
