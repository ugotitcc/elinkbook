import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_inappwebview_platform.dart';
import '../support/fake_reader_feature_dependencies.dart';
import '../support/fake_reader_prefs_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final Future<String?> Function(String filePath, String instanceId) originalCacheBookForServing;

  setUpAll(() {
    InAppWebViewPlatform.instance = FakeInAppWebViewPlatform();
    originalCacheBookForServing = cacheBookForServing;
    cacheBookForServing = (filePath, instanceId) async {
      return '/fake/cache/dir/current.epub';
    };
  });

  tearDownAll(() {
    cacheBookForServing = originalCacheBookForServing;
  });

  setUp(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('elinkbook/volume_key'),
      (call) async => null,
    );
  });

  Widget wrapWithTheme(
    Widget child, {
    AppTheme theme = AppTheme.light,
    bool isEinkMode = false,
  }) {
    return MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: resolveThemeData(theme: theme, isEinkMode: isEinkMode),
      home: child,
    );
  }

  Future<void> pumpAndSettleColors(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
  }

  group('ReaderScreen 自訂閱讀顏色套用', () {
    testWidgets('預設載入自訂背景色與文字色並傳遞給 FoliateReaderView', (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_color_light_background': '#112233',
        'reader_color_light_text': '#AABBCC',
      });

      final prefsManager = FakeReaderPrefsManager();
      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_custom_colors_1',
            appTheme: AppTheme.light,
            isEinkMode: false,
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
          theme: AppTheme.light,
        ),
      );
      await pumpAndSettleColors(tester);

      final foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      expect(foliateView.backgroundColor, equals(const Color(0xFF112233)));
      expect(foliateView.textColor, equals(const Color(0xFFAABBCC)));

      final placeholder = tester.widget<ColoredBox>(
        find.byKey(const Key('reader_render_placeholder_background')),
      );
      expect(placeholder.color, equals(const Color(0xFF112233)));
    });

    testWidgets('只設定背景色時，文字色維持 Theme.colorScheme.onSurface', (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_color_light_background': '#FFFFFF',
      });

      final prefsManager = FakeReaderPrefsManager();
      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_custom_colors_bg_only',
            appTheme: AppTheme.light,
            isEinkMode: false,
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
          theme: AppTheme.light,
        ),
      );
      await pumpAndSettleColors(tester);

      final foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      expect(foliateView.backgroundColor, equals(const Color(0xFFFFFFFF)));
      final expectedTextColor = Theme.of(tester.element(find.byType(ReaderScreen))).colorScheme.onSurface;
      expect(foliateView.textColor, equals(expectedTextColor));
    });

    testWidgets('appTheme 為深色時不套用淺色自訂色，各自隔離', (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_color_light_background': '#FFFFFF',
        'reader_color_dark_background': '#050505',
        'reader_color_dark_text': '#E0E0E0',
      });

      final prefsManager = FakeReaderPrefsManager();
      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_custom_colors_dark',
            appTheme: AppTheme.dark,
            isEinkMode: false,
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
          theme: AppTheme.dark,
        ),
      );
      await pumpAndSettleColors(tester);

      final foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      expect(foliateView.backgroundColor, equals(const Color(0xFF050505)));
      expect(foliateView.textColor, equals(const Color(0xFFE0E0E0)));
    });

    testWidgets('isEinkMode: true 時不套用自訂色，維持 E-Ink 主題原色', (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_color_light_background': '#112233',
        'reader_color_light_text': '#AABBCC',
      });

      final prefsManager = FakeReaderPrefsManager();
      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_custom_colors_eink',
            appTheme: AppTheme.light,
            isEinkMode: true,
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
          theme: AppTheme.light,
          isEinkMode: true,
        ),
      );
      await pumpAndSettleColors(tester);

      final foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      final theme = Theme.of(tester.element(find.byType(ReaderScreen)));
      expect(foliateView.backgroundColor, equals(theme.scaffoldBackgroundColor));
      expect(foliateView.textColor, equals(theme.colorScheme.onSurface));

      final placeholder = tester.widget<ColoredBox>(
        find.byKey(const Key('reader_render_placeholder_background')),
      );
      expect(placeholder.color, equals(theme.scaffoldBackgroundColor));
    });

    testWidgets('isFixedLayout: true 時 FoliateReaderView 收到 null', (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_color_light_background': '#112233',
        'reader_color_light_text': '#AABBCC',
      });

      final prefsManager = FakeReaderPrefsManager();
      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_custom_colors_fxl',
            isFixedLayout: true,
            appTheme: AppTheme.light,
            isEinkMode: false,
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
          theme: AppTheme.light,
        ),
      );
      await pumpAndSettleColors(tester);

      final foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      expect(foliateView.backgroundColor, isNull);
      expect(foliateView.textColor, isNull);
    });

    testWidgets('頁首與頁尾文字跟隨自訂文字色', (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_color_light_text': '#123456',
      });

      final prefsManager = FakeReaderPrefsManager();
      await prefsManager.saveBookPrefs(
        'b_custom_colors_header_footer',
        const BookReaderPrefs(showHeader: true, showFooter: true),
      );

      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_custom_colors_header_footer',
            isFixedLayout: false,
            appTheme: AppTheme.light,
            isEinkMode: false,
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
          theme: AppTheme.light,
        ),
      );
      await pumpAndSettleColors(tester);

      final foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          locationIndex: 1,
          locationTotal: 10,
        ),
      );
      await tester.pump();

      // 觸發熱區切換沉浸模式讓頁首顯示
      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      final headerFinder = find.descendant(
        of: find.byKey(const Key('reader_foliate_header_text')),
        matching: find.byType(Text),
      );
      expect(headerFinder, findsOneWidget);
      final headerText = tester.widget<Text>(headerFinder);
      expect(headerText.style?.color, equals(const Color(0xFF123456)));

      final progressFinder = find.descendant(
        of: find.byKey(const Key('reader_foliate_progress_text')),
        matching: find.byType(Text),
      );
      expect(progressFinder, findsOneWidget);
      final progressText = tester.widget<Text>(progressFinder);
      expect(progressText.style?.color, equals(const Color(0xFF123456)));
    });

    testWidgets('自訂閱讀顏色不污染全域 ThemeData / scaffoldBackgroundColor', (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_color_light_background': '#123456',
      });

      final prefsManager = FakeReaderPrefsManager();
      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_theme_not_polluted',
            appTheme: AppTheme.light,
            isEinkMode: false,
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
          theme: AppTheme.light,
        ),
      );
      await pumpAndSettleColors(tester);

      final theme = Theme.of(tester.element(find.byType(ReaderScreen)));
      // light 主題的 scaffoldBackgroundColor 應維持原始預設值，不被改為 #123456
      expect(theme.scaffoldBackgroundColor, isNot(equals(const Color(0xFF123456))));
    });

    testWidgets('開啟 PDF 時載入遮罩維持 scaffoldBackgroundColor，不被 Foliate 自訂色污染（Ruling I-4）', (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_color_light_background': '#123456',
      });

      final prefsManager = FakeReaderPrefsManager();
      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b_pdf_not_polluted',
            appTheme: AppTheme.light,
            isEinkMode: false,
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
          theme: AppTheme.light,
        ),
      );
      await pumpAndSettleColors(tester);

      final placeholder = tester.widget<ColoredBox>(
        find.byKey(const Key('reader_render_placeholder_background')),
      );
      final expectedColor = Theme.of(tester.element(find.byType(ReaderScreen))).scaffoldBackgroundColor;
      expect(placeholder.color, equals(expectedColor));
      expect(placeholder.color, isNot(equals(const Color(0xFF123456))));
    });

    testWidgets('didUpdateWidget：appTheme 變更時重新載入對應佈景的自訂色（Ruling M-4）', (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_color_light_background': '#112233',
        'reader_color_dark_background': '#445566',
      });

      final prefsManager = FakeReaderPrefsManager();
      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_theme_switch',
            appTheme: AppTheme.light,
            isEinkMode: false,
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
          theme: AppTheme.light,
        ),
      );
      await pumpAndSettleColors(tester);

      var foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      expect(foliateView.backgroundColor, equals(const Color(0xFF112233)));

      // 重建切換為 dark 主題
      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_theme_switch',
            appTheme: AppTheme.dark,
            isEinkMode: false,
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
          theme: AppTheme.dark,
        ),
      );
      await pumpAndSettleColors(tester);

      foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      expect(foliateView.backgroundColor, equals(const Color(0xFF445566)));
    });
  });
}
