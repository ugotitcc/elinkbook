import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, null);
  });

  testWidgets('AboutScreen 正確渲染版本號與 WebView 版本', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.text('關於'), findsOneWidget);
    expect(
      find.byKey(const Key('about_screen_version_text')),
      findsOneWidget,
    );
    expect(find.text('1.0.0 (build 1)'), findsOneWidget);
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
}
