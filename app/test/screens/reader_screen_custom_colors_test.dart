import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/book_search_screen.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/screens/reader_settings_sheet.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/theme/reader_color_preferences.dart';
import 'package:elinkbook/theme/reader_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_inappwebview_platform.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_search_repository.dart';
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
      // ThemeData 必須與佈景原值逐項相同：自訂色只能影響閱讀器頁面，不能改到全域主題
      // （審查 I-3-5：原本只比對「不等於 #123456」，幾乎恆真）。
      final original = resolveThemeData(theme: AppTheme.light, isEinkMode: false);
      expect(theme.scaffoldBackgroundColor, equals(original.scaffoldBackgroundColor));
      expect(theme.colorScheme.surface, equals(original.colorScheme.surface));
      expect(theme.colorScheme.onSurface, equals(original.colorScheme.onSurface));

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

    testWidgets('Scaffold 背景跟著自訂背景色（避免狀態列／手勢列色帶）；PDF 與 E-Ink 維持佈景原色（審查 I-2）', (tester) async {
      Future<Color?> scaffoldColor(
        WidgetTester tester, {
        required String filePath,
        required String bookId,
        bool isEinkMode = false,
      }) async {
        await tester.pumpWidget(
          wrapWithTheme(
            ReaderScreen(
              filePath: filePath,
              bookId: bookId,
              appTheme: AppTheme.light,
              isEinkMode: isEinkMode,
              dependencies: fakeReaderFeatureDependencies(prefsManager: FakeReaderPrefsManager()),
            ),
            theme: AppTheme.light,
            isEinkMode: isEinkMode,
          ),
        );
        await pumpAndSettleColors(tester);
        final scaffold = tester.widget<Scaffold>(
          find.descendant(of: find.byType(ReaderScreen), matching: find.byType(Scaffold)).first,
        );
        return scaffold.backgroundColor;
      }

      SharedPreferences.setMockInitialValues({
        'reader_color_light_background': '#112233',
      });
      expect(
        await scaffoldColor(tester, filePath: 'test/fixtures/sample.epub', bookId: 'b_scaffold_epub'),
        equals(const Color(0xFF112233)),
      );

      final original = resolveThemeData(theme: AppTheme.light, isEinkMode: false);
      await tester.pumpWidget(const SizedBox());
      expect(
        await scaffoldColor(tester, filePath: 'test/fixtures/sample.pdf', bookId: 'b_scaffold_pdf'),
        isNull,
        reason: 'PDF 的 _themedBackgroundColor 為 null，Scaffold 用佈景預設底色',
      );
      expect(original.scaffoldBackgroundColor, isNot(equals(const Color(0xFF112233))));

      await tester.pumpWidget(const SizedBox());
      final eink = resolveThemeData(theme: AppTheme.light, isEinkMode: true);
      expect(
        await scaffoldColor(
          tester,
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_scaffold_eink',
          isEinkMode: true,
        ),
        equals(eink.scaffoldBackgroundColor),
        reason: 'E-Ink 不套用自訂色',
      );
    });

    testWidgets('閱讀器→單書搜尋：推入的 BookSearchScreen 轉傳 ReaderScreen 的 appTheme（審查 I-3-1）', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_search_theme',
            appTheme: AppTheme.dark,
            isEinkMode: false,
            dependencies: fakeReaderFeatureDependencies(
              prefsManager: FakeReaderPrefsManager(),
              searchRepository: FakeSearchRepository(),
              libraryRepository: FakeLibraryRepository(),
            ),
          ),
          theme: AppTheme.dark,
        ),
      );
      await pumpAndSettleColors(tester);

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pumpAndSettle();

      final pushed = tester.widget<BookSearchScreen>(find.byType(BookSearchScreen));
      expect(pushed.appTheme, equals(AppTheme.dark));
    });

    testWidgets('較早發出、較晚完成的載入結果不會蓋掉使用者剛改的顏色（審查 M-1）', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final gate = Completer<ReaderColors>();
      final deps = fakeReaderFeatureDependencies(
        prefsManager: FakeReaderPrefsManager(),
        readerColorPreferences: _GatedReaderColorPreferences(gate.future),
      );

      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_load_generation',
            appTheme: AppTheme.light,
            isEinkMode: false,
            dependencies: deps,
          ),
          theme: AppTheme.light,
        ),
      );
      await tester.pump();

      // 載入還沒回來（gate 未放行）就先開面板並改色。
      final reflowableView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      reflowableView.onPageRendered();
      reflowableView.onLayoutResolved?.call(
        const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, '佈景'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reader_colors_background_hex')), '#334455');
      await tester.pump();

      // 舊的載入現在才完成，帶著舊值：不得蓋掉使用者剛改的新色。
      gate.complete(const ReaderColors(background: Color(0xFF112233)));
      await tester.pump();
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      expect(foliateView.backgroundColor, equals(const Color(0xFF334455)));
    });

    testWidgets('開面板改背景色 → FoliateReaderView.backgroundColor 立刻更新且偏好已寫入', (tester) async {
      SharedPreferences.setMockInitialValues({});

      final prefsManager = FakeReaderPrefsManager();
      await tester.pumpWidget(
        wrapWithTheme(
          ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_live_color_update',
            appTheme: AppTheme.light,
            isEinkMode: false,
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
          theme: AppTheme.light,
        ),
      );
      await pumpAndSettleColors(tester);

      final reflowableView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      reflowableView.onPageRendered();
      reflowableView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSettingsSheet), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, '佈景'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('reader_colors_background_hex')), '#334455');
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      expect(foliateView.backgroundColor, equals(const Color(0xFF334455)));

      final loadedPrefs = await const ReaderColorPreferences().load(AppTheme.light);
      expect(loadedPrefs.background, equals(const Color(0xFF334455)));
    });
  });
}

/// 載入結果由測試手動放行的偏好，用來重現「較早發出、較晚完成」的競態。
class _GatedReaderColorPreferences extends ReaderColorPreferences {
  const _GatedReaderColorPreferences(this._result);
  final Future<ReaderColors> _result;

  @override
  Future<ReaderColors> load(AppTheme theme) => _result;
}
