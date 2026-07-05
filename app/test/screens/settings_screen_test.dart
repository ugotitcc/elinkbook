import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:elinkbook/screens/settings_screen.dart';

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
        .setMockMethodCallHandler(_appInfoChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, null);
  });

  testWidgets('SettingsScreen 顯示設定標題與「關於」入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('設定'), findsOneWidget);
    expect(find.byKey(const Key('settings_about_button')), findsOneWidget);
  });

  testWidgets('點擊「關於」導航至 AboutScreen，可返回 SettingsScreen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.tap(find.byKey(const Key('settings_about_button')));
    await tester.pumpAndSettle();

    expect(find.text('關於'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('設定'), findsOneWidget);
  });
}
