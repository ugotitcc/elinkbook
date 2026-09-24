import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/tts_provider.dart';
import 'package:elinkbook/screens/tts_defaults_screen.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_tts_provider.dart';

/// 【review-plan-issue-5.md I-2】模擬「裝置具備 TTS 引擎，但尚未安裝任何
/// 語言包/可用語音」的情境——`FakeTtsProvider` 固定回傳
/// `[TtsVoice.systemDefault]`，無法模擬空清單，改用這個最小 ad-hoc 實作，
/// 不修改共用的 `FakeTtsProvider`（避免影響其他既有測試檔案）。
class _EmptyVoicesTtsProvider implements TtsProvider {
  @override
  Future<List<TtsVoice>> getAvailableVoices() async => const [];

  @override
  Future<int?> getMaxInputLength() async => null;

  @override
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('ttsProvider 為 null 時顯示不可用提示，不崩潰，且無語音選項', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TtsDefaultsScreen(prefsManager: FakeReaderPrefsManager()),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('tts_defaults_voice_unavailable_hint')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('tts_defaults_voice_${TtsVoice.systemDefault.id}')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ttsProvider 存在時列出 getAvailableVoices() 回傳的語音', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TtsDefaultsScreen(
        prefsManager: FakeReaderPrefsManager(),
        ttsProvider: FakeTtsProvider(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('tts_defaults_voice_${TtsVoice.systemDefault.id}')),
      findsOneWidget,
    );
    expect(find.text(TtsVoice.systemDefault.displayName), findsOneWidget);
  });

  testWidgets(
      'ttsProvider 存在但 getAvailableVoices() 回傳空清單時，顯示不可用提示而非空白區塊'
      '（review-plan-issue-5.md I-2）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TtsDefaultsScreen(
        prefsManager: FakeReaderPrefsManager(),
        ttsProvider: _EmptyVoicesTtsProvider(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('tts_defaults_voice_unavailable_hint')),
      findsOneWidget,
    );
  });

  testWidgets('點選語音選項立即呼叫 saveGlobalPrefs 更新 ttsVoiceId', (tester) async {
    // 初始值必須跟 target voice 不同，否则 RadioGroup 已選中同一個值，
    // 點擊不會觸發 onChanged。
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial()
          .copyWith(tts: const TtsDefaults(ttsVoiceId: 'other-voice')),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TtsDefaultsScreen(
        prefsManager: fakeManager,
        ttsProvider: FakeTtsProvider(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(Key('tts_defaults_voice_${TtsVoice.systemDefault.id}')),
    );
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.tts.ttsVoiceId,
      TtsVoice.systemDefault.id,
    );
  });

  testWidgets(
      '非 E-Ink 模式顯示語速 Slider（無 divisions，改在 onChanged 內吸附至 0.1 步進），'
      '拖曳後呼叫 saveGlobalPrefs 更新 defaultTtsSpeed 且結果精確對齊 0.1 格'
      '（review-plan-issue-5.md I-1/I-3：divisions: 13 會漏掉 1.0x 基準格，'
      '改為連續 Slider＋onChanged 內四捨五入至 0.1，兩種互動路徑〔Slider／'
      'E-Ink +/- 按鈕〕產生的可達值集合一致）', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TtsDefaultsScreen(prefsManager: fakeManager, isEinkMode: false),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tts_defaults_speed_slider')), findsOneWidget);
    expect(find.byKey(const Key('tts_defaults_speed_value')), findsNothing);
    final slider =
        tester.widget<Slider>(find.byKey(const Key('tts_defaults_speed_slider')));
    expect(slider.divisions, isNull, reason: '改為連續 Slider，不使用 divisions 離散刻度');

    await tester.drag(
      find.byKey(const Key('tts_defaults_speed_slider')),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls, isNotEmpty);
    final result = fakeManager.savedGlobalPrefsCalls.last.tts.defaultTtsSpeed;
    expect(result, greaterThan(1.0));
    expect(result, lessThanOrEqualTo(2.0));
    // 結果須精確落在 0.1 的整數倍格點上（容許浮點誤差），驗證 onChanged
    // 內的吸附邏輯確實生效，而非任意連續值。
    // 【review-plan-issue-5.md C-3】原寫法 `(result - 0.75) * 10` 有誤：
    // result 恆為 0.1 的整數倍（設 result = k * 0.1，k 為整數），代入後
    // 得 (k*0.1 - 0.75) * 10 = k - 7.5，對任何整數 k 恆為 X.5 半整數，
    // roundToDouble() 後與原值必定恰差 0.5，斷言 100% 失敗。直接驗證
    // 「result 本身是否為 0.1 的倍數」不需要減去 0.75 這個偏移量。
    final steps = result * 10;
    expect(steps.roundToDouble(), closeTo(steps, 1e-6));
  });

  testWidgets(
      '非 E-Ink 模式下 Slider 拖曳到最底可以選到規格下限 0.75x（不會卡在 0.8x）'
      '（review-issue-5.md Important 2 回歸測試：v 貼近下限時，(v*10).round()/10 '
      '對 v=0.75 仍四捨五入成 0.8，導致拖曳永遠選不到 0.75x）', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TtsDefaultsScreen(prefsManager: fakeManager, isEinkMode: false),
    ));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('tts_defaults_speed_slider')),
      const Offset(-2000, 0),
    );
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls, isNotEmpty);
    expect(
      fakeManager.savedGlobalPrefsCalls.last.tts.defaultTtsSpeed,
      closeTo(0.75, 1e-9),
    );
  });

  testWidgets('E-Ink 模式隱藏 Slider，改用 +/- 按鈕以 0.1x 步進調整語速', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TtsDefaultsScreen(prefsManager: fakeManager, isEinkMode: true),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tts_defaults_speed_slider')), findsNothing);
    expect(find.byKey(const Key('tts_defaults_speed_value')), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tts_defaults_speed_increment')));
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls.last.tts.defaultTtsSpeed, 1.1);
    expect(find.text('1.1x'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tts_defaults_speed_decrement')));
    await tester.pumpAndSettle();

    expect(fakeManager.savedGlobalPrefsCalls.last.tts.defaultTtsSpeed, 1.0);
  });

  testWidgets('語速已達上限 2.0x 時，+按鈕停用；已達下限 0.75x 時，-按鈕停用', (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial()
          .copyWith(tts: const TtsDefaults(defaultTtsSpeed: 2.0)),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TtsDefaultsScreen(prefsManager: fakeManager, isEinkMode: true),
    ));
    await tester.pumpAndSettle();

    final incrementButton = tester.widget<IconButton>(
      find.byKey(const Key('tts_defaults_speed_increment')),
    );
    expect(incrementButton.onPressed, isNull);

    await tester.tap(find.byKey(const Key('tts_defaults_speed_decrement')));
    await tester.pumpAndSettle();
    // 2.0 -> 1.9，仍未到下限，- 按鈕應仍可用
    final decrementButton = tester.widget<IconButton>(
      find.byKey(const Key('tts_defaults_speed_decrement')),
    );
    expect(decrementButton.onPressed, isNotNull);
  });

  testWidgets(
      '從預設 1.0x 連續點擊減號至 0.75x（不會卡在 0.8x），到達 0.75x 後減號按鈕停用'
      '（review-plan-issue-5.md C-1 核心回歸測試：停用判斷須看「目前值」而非'
      '「預判扣除後的值」，否則 1.0→0.9→0.8 時，0.8-0.1=0.7<0.75 會讓按鈕在'
      '0.8x 就被錯誤停用，永遠到不了規格下限 0.75x）', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TtsDefaultsScreen(prefsManager: fakeManager, isEinkMode: true),
    ));
    await tester.pumpAndSettle();

    final decrementFinder = find.byKey(const Key('tts_defaults_speed_decrement'));

    // 1.0 -> 0.9 -> 0.8：每次點擊前按鈕都必須是可用的。
    for (final expected in [0.9, 0.8]) {
      expect(tester.widget<IconButton>(decrementFinder).onPressed, isNotNull);
      await tester.tap(decrementFinder);
      await tester.pumpAndSettle();
      expect(fakeManager.savedGlobalPrefsCalls.last.tts.defaultTtsSpeed,
          closeTo(expected, 1e-9));
    }

    // 關鍵一步：目前為 0.8x，按鈕必須仍可用，點擊後正確 clamp 至 0.75x。
    expect(tester.widget<IconButton>(decrementFinder).onPressed, isNotNull);
    await tester.tap(decrementFinder);
    await tester.pumpAndSettle();
    expect(fakeManager.savedGlobalPrefsCalls.last.tts.defaultTtsSpeed,
        closeTo(0.75, 1e-9));
    // 0.75.toStringAsFixed(1) 會四捨五入誤顯示為 "0.8"，須特判
    // （review-issue-5.md Important 1 回歸測試）。
    expect(find.text('0.8x'), findsNothing);
    expect(find.text('0.75x'), findsOneWidget);

    // 已達 0.75x 下限，減號按鈕停用。
    expect(tester.widget<IconButton>(decrementFinder).onPressed, isNull);
  });

  testWidgets('簡體中文與英文介面下，語音清單的內建「系統預設語音」依語言顯示', (tester) async {
    for (final (locale, expected) in [
      (const Locale('zh', 'CN'), '系统默认语音'),
      (const Locale('en'), 'System default voice'),
    ]) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TtsDefaultsScreen(
          prefsManager: FakeReaderPrefsManager(),
          ttsProvider: FakeTtsProvider(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(Key('tts_defaults_voice_${TtsVoice.systemDefault.id}')),
          matching: find.text(expected),
        ),
        findsOneWidget,
        reason: '$locale 介面下應顯示「$expected」',
      );
      expect(find.text('系統預設語音'), findsNothing);
    }
  });

  testWidgets('英文介面下標題與分區標題正確以英文渲染', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TtsDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Read-Aloud Voice & Speed'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('No voice is installed or supported on this device'),
        findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
  });
}
