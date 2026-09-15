import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
import 'package:elinkbook/screens/reading_defaults_screen.dart';
import '../support/fake_reader_prefs_manager.dart';

void main() {
  testWidgets('載入完成前顯示載入指示器，載入完成後顯示四項控制項與既有 GlobalReaderPrefs 初始值',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          volumeKeyEnabled: false,
          pageTurnMode: PageTurnMode.scroll,
          screenOrientation: ScreenOrientationSetting.lock90,
          fullscreen: true,
          textConversion: TextConversionMode.toSimplified,
        ),
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

    final scrollTile = tester.widget<RadioListTile<PageTurnMode>>(
      find.byKey(const Key('reading_defaults_page_turn_mode_scroll')),
    );
    expect(scrollTile.value, PageTurnMode.scroll);

    expect(
      find.byKey(const Key('reading_defaults_screen_orientation_lock90')),
      findsOneWidget,
    );

    final simplifiedFinder =
        find.byKey(const Key('reading_defaults_text_conversion_simplified'));
    await tester.scrollUntilVisible(simplifiedFinder, 100);
    // RadioListTile.checked 已在 Flutter 3.32 棄用，改檢查外層 RadioGroup 的 groupValue
    final simplifiedGroup = tester.widget<RadioGroup<TextConversionMode>>(
      find.ancestor(
        of: simplifiedFinder,
        matching: find.byType(RadioGroup<TextConversionMode>),
      ),
    );
    expect(simplifiedGroup.groupValue, TextConversionMode.toSimplified);

    final fullscreenFinder =
        find.byKey(const Key('reading_defaults_fullscreen_switch'));
    await tester.scrollUntilVisible(fullscreenFinder, 100);
    final fullscreenSwitch = tester.widget<SwitchListTile>(fullscreenFinder);
    expect(fullscreenSwitch.value, isTrue);
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
    expect(fakeManager.savedGlobalPrefsCalls.last.reading.volumeKeyEnabled, isFalse);
  });

  testWidgets('切換全螢幕模式開關立即呼叫 saveGlobalPrefs 並反映新值', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    // Fullscreen switch is at the bottom of the list, need to ensure visible
    final fullscreenFinder = find.byKey(const Key('reading_defaults_fullscreen_switch'));
    await tester.scrollUntilVisible(fullscreenFinder, 100);
    await tester.pumpAndSettle();
    await tester.tap(fullscreenFinder);
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls.last.reading.fullscreen, isTrue);
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
      fakeManager.savedGlobalPrefsCalls.last.reading.pageTurnMode,
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
      fakeManager.savedGlobalPrefsCalls.last.reading.screenOrientation,
      ScreenOrientationSetting.lock180,
    );
  });

  testWidgets('點選簡繁轉換選項立即呼叫 saveGlobalPrefs 更新為對應模式，且重新載入後反映新值',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final traditionalFinder =
        find.byKey(const Key('reading_defaults_text_conversion_traditional'));
    await tester.scrollUntilVisible(traditionalFinder, 100);
    await tester.pumpAndSettle();
    await tester.tap(traditionalFinder);
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.reading.textConversion,
      TextConversionMode.toTraditional,
    );

    // 重新載入持久化（issues.md:50 規定）：以同一個 fakeManager 重建畫面，
    // 驗證剛才儲存的值會反映在選中狀態。
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final reloadedFinder =
        find.byKey(const Key('reading_defaults_text_conversion_traditional'));
    await tester.scrollUntilVisible(reloadedFinder, 100);
    final reloadedGroup = tester.widget<RadioGroup<TextConversionMode>>(
      find.ancestor(
        of: reloadedFinder,
        matching: find.byType(RadioGroup<TextConversionMode>),
      ),
    );
    expect(reloadedGroup.groupValue, TextConversionMode.toTraditional);
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
          .copyWith(reading: const ReadingDefaults(openLastBookOnLaunch: false)),
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
      fakeManager.savedGlobalPrefsCalls.last.reading.openLastBookOnLaunch,
      isFalse,
    );
  });

  testWidgets('顯示頁首/頁尾開關反映既有 GlobalReaderPrefs 初始值', (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
          reading: const ReadingDefaults(showHeader: true, showFooter: false)),
    );
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final headerSwitchFinder =
        find.byKey(const Key('reading_defaults_show_header_switch'));
    await tester.scrollUntilVisible(headerSwitchFinder, 100);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(headerSwitchFinder).value, isTrue);

    final footerSwitchFinder =
        find.byKey(const Key('reading_defaults_show_footer_switch'));
    await tester.scrollUntilVisible(footerSwitchFinder, 100);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(footerSwitchFinder).value, isFalse);
  });

  testWidgets('切換顯示頁首開關立即呼叫 saveGlobalPrefs 並反映新值', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final switchFinder =
        find.byKey(const Key('reading_defaults_show_header_switch'));
    await tester.scrollUntilVisible(switchFinder, 100);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls.last.reading.showHeader, isTrue);
  });

  testWidgets('切換顯示頁尾開關立即呼叫 saveGlobalPrefs 並反映新值', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final switchFinder =
        find.byKey(const Key('reading_defaults_show_footer_switch'));
    await tester.scrollUntilVisible(switchFinder, 100);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls.last.reading.showFooter, isTrue);
  });
}
