import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/screens/reading_defaults_screen.dart';
import '../support/fake_reader_prefs_manager.dart';

void main() {
  testWidgets('載入完成前顯示載入指示器，載入完成後顯示四項控制項與既有 GlobalReaderPrefs 初始值',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        volumeKeyEnabled: false,
        pageTurnMode: PageTurnMode.scroll,
        screenOrientation: ScreenOrientationSetting.lock90,
        fullscreen: true,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));

    expect(
      find.byKey(const Key('reading_defaults_loading_indicator')),
      findsOneWidget,
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reading_defaults_loading_indicator')),
      findsNothing,
    );

    final volumeSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('reading_defaults_volume_key_switch')),
    );
    expect(volumeSwitch.value, isFalse);

    final fullscreenSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('reading_defaults_fullscreen_switch')),
    );
    expect(fullscreenSwitch.value, isTrue);

    final scrollTile = tester.widget<RadioListTile<PageTurnMode>>(
      find.byKey(const Key('reading_defaults_page_turn_mode_scroll')),
    );
    expect(scrollTile.value, PageTurnMode.scroll);

    expect(
      find.byKey(const Key('reading_defaults_screen_orientation_lock90')),
      findsOneWidget,
    );
  });

  testWidgets('切換音量鍵翻頁開關立即呼叫 saveGlobalPrefs 並反映新值', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('reading_defaults_volume_key_switch')));
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls, isNotEmpty);
    expect(fakeManager.savedGlobalPrefsCalls.last.volumeKeyEnabled, isFalse);
  });

  testWidgets('切換全螢幕模式開關立即呼叫 saveGlobalPrefs 並反映新值', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    // Fullscreen switch is at the bottom of the list, need to ensure visible
    final fullscreenFinder = find.byKey(const Key('reading_defaults_fullscreen_switch'));
    await tester.ensureVisible(fullscreenFinder);
    await tester.pumpAndSettle();
    await tester.tap(fullscreenFinder);
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls.last.fullscreen, isTrue);
  });

  testWidgets('點選翻頁模式選項立即呼叫 saveGlobalPrefs 更新為對應模式', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('reading_defaults_page_turn_mode_scroll')),
    );
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.pageTurnMode,
      PageTurnMode.scroll,
    );
  });

  testWidgets('點選螢幕方向選項立即呼叫 saveGlobalPrefs 更新為對應設定', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('reading_defaults_screen_orientation_lock180')),
    );
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.screenOrientation,
      ScreenOrientationSetting.lock180,
    );
  });

  testWidgets('畫面上不存在任何「儲存」按鈕', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.text('儲存'), findsNothing);
  });

  testWidgets('啟動時開啟最後閱讀的那本書開關反映既有 GlobalReaderPrefs 初始值',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial()
          .copyWith(openLastBookOnLaunch: false),
    );
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final switchFinder =
        find.byKey(const Key('reading_defaults_open_last_book_switch'));
    await tester.scrollUntilVisible(switchFinder, 100);
    await tester.pumpAndSettle();

    final openLastBookSwitch = tester.widget<SwitchListTile>(switchFinder);
    expect(openLastBookSwitch.value, isFalse);
  });

  testWidgets(
      '開關文字為「啟動時開啟最後閱讀的那本書」（epic-18-reader-device-qa '
      'Issue 35，原文字「最後一本書」易誤解為書架排序意義上的最後一本）',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final textFinder = find.text('啟動時開啟最後閱讀的那本書');
    await tester.scrollUntilVisible(textFinder, 100);
    await tester.pumpAndSettle();

    expect(textFinder, findsOneWidget);
    expect(find.text('啟動時開啟最後一本書'), findsNothing);
  });

  testWidgets('切換啟動時開啟最後閱讀的那本書開關立即呼叫 saveGlobalPrefs 並反映新值',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final switchFinder =
        find.byKey(const Key('reading_defaults_open_last_book_switch'));
    await tester.scrollUntilVisible(switchFinder, 100);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.openLastBookOnLaunch,
      isFalse,
    );
  });
}
