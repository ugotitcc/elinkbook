import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/pump_localized_widget.dart';
import '../support/fake_reader_feature_dependencies.dart';
import '../support/fake_sync_dependencies.dart';

const _appInfoChannel = MethodChannel('elinkbook/app_info');

void main() {
  group('SettingsScaffold 代表性字串跨語言渲染', () {
    late FlutterSecureStoragePlatform originalPlatform;

    setUp(() {
      // 沿用 settings_scaffold_test.dart 既有安全網：SettingsScaffold 內部
      // 四分區以 IndexedStack 長駐掛載，即使本測試只看「外觀」分區，其餘
      // 分區（關於／同步與帳號）仍會在 pumpWidget() 當下一併掛載並讀取這些
      // 平台依賴。
      PackageInfo.setMockInitialValues(
        appName: 'elinkBook',
        packageName: 'cc.ugotit.elinkbook',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_appInfoChannel, (call) async => null);
      SharedPreferences.setMockInitialValues({});
      originalPlatform = FlutterSecureStoragePlatform.instance;
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
        {},
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_appInfoChannel, null);
      FlutterSecureStoragePlatform.instance = originalPlatform;
    });

    testWidgets('zh_TW locale（預設）下標題與外觀分區正確以正體中文渲染', (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          readerFeatures: fakeReaderFeatureDependencies(
            prefsManager: FakeReaderPrefsManager(),
          ),
          sync: fakeSyncDependencies(),
        ),
      );

      expect(find.text('設定'), findsOneWidget);
      expect(find.text('外觀'), findsOneWidget);
    });

    testWidgets('zh_CN locale 下標題與外觀分區正確以簡體中文渲染', (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          readerFeatures: fakeReaderFeatureDependencies(
            prefsManager: FakeReaderPrefsManager(),
          ),
          sync: fakeSyncDependencies(),
        ),
        locale: const Locale('zh', 'CN'),
      );

      expect(find.text('设定'), findsOneWidget);
      expect(find.text('外观'), findsOneWidget);
    });

    testWidgets('en locale 下標題與外觀分區正確以英文渲染', (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          readerFeatures: fakeReaderFeatureDependencies(
            prefsManager: FakeReaderPrefsManager(),
          ),
          sync: fakeSyncDependencies(),
        ),
        locale: const Locale('en'),
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
    });
  });

  group('LibraryScreen 代表性字串跨語言渲染', () {
    setUp(() {
      // LibraryScreen.initState() 會呼叫 SharedPreferences.getInstance()，
      // 純 Dart widget test 環境需要官方測試替身（沿用 library_screen_test.dart
      // 既有慣例）。
      SharedPreferences.setMockInitialValues({});
    });

    LibraryScreen buildScreen() => LibraryScreen(
      dependencies: fakeReaderFeatureDependencies(
        libraryRepository: FakeLibraryRepository(),
        bookImportService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(
          globalPrefs: const GlobalReaderPrefs.initial().copyWith(
            // 避免 openLastBookOnLaunch 預設 true 導致自動導覽到
            // ReaderScreen，干擾本測試對書架空狀態文字的斷言（沿用
            // library_screen_test.dart 既有慣例）。
            reading: const ReadingDefaults(openLastBookOnLaunch: false),
          ),
        ),
      ),
    );

    testWidgets('zh_TW locale（預設）下書架標題與空狀態文字正確以正體中文渲染', (tester) async {
      await pumpLocalizedWidget(tester, buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('書架'), findsOneWidget);
      expect(find.text('尚未匯入書籍'), findsOneWidget);
    });

    testWidgets('zh_CN locale 下書架標題與空狀態文字正確以簡體中文渲染', (tester) async {
      await pumpLocalizedWidget(
        tester,
        buildScreen(),
        locale: const Locale('zh', 'CN'),
      );
      await tester.pumpAndSettle();

      expect(find.text('书架'), findsOneWidget);
      expect(find.text('尚未导入书籍'), findsOneWidget);
    });

    testWidgets('en locale 下書架標題與空狀態文字正確以英文渲染', (tester) async {
      await pumpLocalizedWidget(
        tester,
        buildScreen(),
        locale: const Locale('en'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('No books imported yet'), findsOneWidget);
    });
  });
}
