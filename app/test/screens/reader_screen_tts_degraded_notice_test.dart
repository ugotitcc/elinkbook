import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/tts_audio_handler_startup.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_reader_prefs_manager.dart';

// epic-61 Issue 1（F3）：TTS 音訊服務初始化失敗降級後，進入閱讀器時提示一次。
// 用「不支援格式」分支即可：提示在 initState 之後觸發，與渲染路徑無關。
const _snackbarKey = Key('reader_tts_degraded_snackbar');

Widget _app(FakeReaderPrefsManager prefs, {TtsDegradedNotice? notice}) {
  return MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
    home: ReaderScreen(
      filePath: 'test/fixtures/sample.unknown',
      bookId: 'b_tts_degraded',
      prefsManager: prefs,
      ttsDegradedNotice: notice,
    ),
  );
}

void main() {
  late FakeReaderPrefsManager prefs;

  setUp(() {
    prefs = FakeReaderPrefsManager();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (call) async => null,
    );
  });

  testWidgets('降級時進入閱讀器顯示一次提示', (tester) async {
    await tester.pumpWidget(_app(prefs, notice: TtsDegradedNotice(degraded: true)));
    await tester.pump();

    expect(find.byKey(_snackbarKey), findsOneWidget);
    expect(find.text('本次沒有媒體通知與鎖屏控制，朗讀仍可使用'), findsOneWidget);
  });

  testWidgets('同一個 notice 已顯示過，再次進入閱讀器不重複顯示', (tester) async {
    final notice = TtsDegradedNotice(degraded: true);

    await tester.pumpWidget(_app(prefs, notice: notice));
    await tester.pump();
    expect(find.byKey(_snackbarKey), findsOneWidget);

    // 換掉整棵樹（等同離開再重新進入閱讀器），State 重新建立。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(prefs, notice: notice));
    await tester.pump();

    expect(find.byKey(_snackbarKey), findsNothing);
  });

  testWidgets('沒有降級時不顯示提示', (tester) async {
    await tester.pumpWidget(_app(prefs, notice: TtsDegradedNotice(degraded: false)));
    await tester.pump();

    expect(find.byKey(_snackbarKey), findsNothing);
  });

  testWidgets('未傳 notice（既有呼叫端）時不顯示提示', (tester) async {
    await tester.pumpWidget(_app(prefs));
    await tester.pump();

    expect(find.byKey(_snackbarKey), findsNothing);
  });
}
