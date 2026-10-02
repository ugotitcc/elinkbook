import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/about_screen.dart';

const _appInfoChannel = MethodChannel('elinkbook/app_info');

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'elinkBook',
      packageName: 'cc.ugotit.elinkbook',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, (call) async {
      if (call.method == 'getSystemWebViewVersion') return '120.0.6099.43';
      if (call.method == 'getBuildTime') return '2026-07-10 13:00:00';
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, null);
  });

  testWidgets('AboutScreen 正確渲染版本號、編譯時間與 WebView 版本', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('關於'), findsOneWidget);
    expect(
      find.byKey(const Key('about_screen_version_text')),
      findsOneWidget,
    );
    expect(find.text('1.0.0 (build 1)'), findsOneWidget);
    expect(
      find.byKey(const Key('about_screen_build_time_text')),
      findsOneWidget,
    );
    expect(find.text('2026-07-10 13:00:00'), findsOneWidget);
    expect(
      find.byKey(const Key('about_screen_webview_version_text')),
      findsOneWidget,
    );
    expect(find.text('120.0.6099.43'), findsOneWidget);
    expect(
      find.byKey(const Key('about_screen_view_licenses_button')),
      findsOneWidget,
    );
    expect(find.text('開源授權清單'), findsOneWidget);
  });

  testWidgets('getBuildTime 呼叫失敗時降級顯示「無法取得」', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, (call) async {
      if (call.method == 'getSystemWebViewVersion') return '120.0.6099.43';
      if (call.method == 'getBuildTime') {
        throw PlatformException(code: 'unavailable');
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final buildTimeText = tester.widget<Text>(
      find.byKey(const Key('about_screen_build_time_text')),
    );
    expect(buildTimeText.data, '無法取得');
  });

  testWidgets('英文介面下標題/項目標題/授權清單按鈕正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('Build Time'), findsOneWidget);
    expect(find.text('System WebView Version'), findsOneWidget);
    expect(find.text('Open Source Licenses'), findsOneWidget);
  });

  testWidgets('點開授權頁：頁首顯示依語系的開源元件說明（zh_TW）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('about_screen_view_licenses_button')));
    await tester.pumpAndSettle();

    expect(find.text('本 App 使用下列開源元件，各元件的版權與授權條款如下。'), findsOneWidget);
  });

  testWidgets('點開授權頁：頁首顯示依語系的開源元件說明（en）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('about_screen_view_licenses_button')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This app uses the open-source components listed below. '
        'Their copyright notices and license terms follow.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('英文介面下 getBuildTime 呼叫失敗時降級顯示英文 Unavailable',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, (call) async {
      if (call.method == 'getSystemWebViewVersion') return '120.0.6099.43';
      if (call.method == 'getBuildTime') {
        throw PlatformException(code: 'unavailable');
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final buildTimeText = tester.widget<Text>(
      find.byKey(const Key('about_screen_build_time_text')),
    );
    expect(buildTimeText.data, 'Unavailable');
  });
}
