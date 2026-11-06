import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/desktop_key_deduper.dart';
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/foliate_bridge_handlers.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/local_book_server.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/screens/annotation_toolbar.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/windows/window_fullscreen_controller.dart';
import 'package:elinkbook/windows/window_fullscreen_shortcuts.dart';

import '../support/fake_inappwebview_platform.dart';
import '../support/fake_reader_feature_dependencies.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_reader_surface.dart';
import '../support/fake_search_repository.dart';

class FakeWindowFullscreenController implements WindowFullscreenController {
  bool _fullscreen;
  final List<bool> history = [];

  FakeWindowFullscreenController({bool initialFullscreen = false})
      : _fullscreen = initialFullscreen;

  @override
  bool get isFullscreenNow => _fullscreen;

  @override
  Future<bool> isFullscreen() async => _fullscreen;

  @override
  Future<void> setFullscreen(bool isFullscreen) async {
    _fullscreen = isFullscreen;
    history.add(isFullscreen);
  }
}

void main() {
  late Future<String?> Function(String, String) originalCacheBookForServing;

  setUpAll(() {
    InAppWebViewPlatform.instance = FakeInAppWebViewPlatform();
    originalCacheBookForServing = cacheBookForServing;
    cacheBookForServing = (filePath, instanceId) async =>
        '/fake/cache/dir/current.epub';
  });

  tearDownAll(() {
    cacheBookForServing = originalCacheBookForServing;
  });

  setUp(() {
    pdfrxInitialize();
    desktopKeyDeduper.reset();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('elinkbook/volume_key'),
      (call) async => null,
    );
  });

  group('FoliateReaderView 鍵盤整合（方案 B）', () {
    test('buildFoliateReaderIndexUri 在 Windows 帶 desktopKeys=1、非 Windows 不帶',
        () {
      final widget = FoliateReaderView(
        filePath: 'test/fixtures/sample.epub',
        onPageRendered: () {},
        onError: (_) {},
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final winUri = buildFoliateReaderIndexUri(widget);
        expect(winUri.queryParameters['desktopKeys'], '1',
            reason: 'Windows 下必須帶 desktopKeys=1 啟用 main.js 鍵盤轉送');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }

      final defaultUri = buildFoliateReaderIndexUri(widget);
      expect(defaultUri.queryParameters['desktopKeys'], isNull,
          reason: '非 Windows（Android 等）不應帶 desktopKeys');
    });

    test('FoliateBridgeHandlers.onDesktopKey 常數定義存在', () {
      expect(FoliateBridgeHandlers.onDesktopKey, 'onDesktopKey');
    });

    test('main.js 內含 desktopKeys 與 onDesktopKey 轉送邏輯', () {
      final mainJsFile =
          File('android/app/src/main/assets/foliate/main.js');
      expect(mainJsFile.existsSync(), isTrue);
      final content = mainJsFile.readAsStringSync();

      expect(content, contains("desktopKeys"));
      expect(content, contains("'onDesktopKey'"));
    });

    testWidgets(
        'ReaderScreen 透過 onDesktopKey 收到按鍵轉送：ArrowRight 翻頁、F11 切換全螢幕、Esc 處理',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final fakeFullscreen =
          FakeWindowFullscreenController(initialFullscreen: false);
      activeWindowFullscreenController = fakeFullscreen;
      addTearDown(() => activeWindowFullscreenController = null);

      try {
        final surface = FakeReaderSurface.foliate();
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
            builder: (context, child) => WindowFullscreenShortcuts(
              controller: fakeFullscreen,
              child: child!,
            ),
            home: ReaderScreen(
              filePath: 'test/fixtures/sample.epub',
              bookId: 'b_foliate_keyboard',
              dependencies: fakeReaderFeatureDependencies(
                prefsManager: FakeReaderPrefsManager(),
                readerSurfaceFactory: (_) => surface,
                searchRepository: FakeSearchRepository(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();

        final foliateView = tester.widget<FoliateReaderView>(
          find.byType(FoliateReaderView),
        );
        foliateView.onPageRendered();
        await tester.pump();
        await tester.runAsync(() => LocalBookServer.instance.close());

        expect(foliateView.onDesktopKey, isNotNull,
            reason: 'Windows 下 ReaderScreen 應向 FoliateReaderView 傳入 onDesktopKey 回呼');

        // 1. ArrowRight 翻下一頁
        surface.calls.clear();
        foliateView.onDesktopKey!(
          'ArrowRight',
          shift: false,
          control: false,
          alt: false,
          meta: false,
        );
        await tester.pump();
        expect(surface.calls, ['nextPage']);

        // 2. F11 切換視窗全螢幕
        foliateView.onDesktopKey!(
          'F11',
          shift: false,
          control: false,
          alt: false,
          meta: false,
        );
        await tester.pump();
        expect(fakeFullscreen.isFullscreenNow, isTrue);

        // 3. 有文字選取時按 Esc：清除選取，不退出視窗全螢幕
        foliateView.onSelectionChanged?.call(
          const EpubSelectionInfo(
            locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
            progression: 0.1,
            rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
          ),
        );
        await tester.pump();
        expect(find.byType(AnnotationToolbar), findsOneWidget);

        surface.calls.clear();
        foliateView.onDesktopKey!(
          'Escape',
          shift: false,
          control: false,
          alt: false,
          meta: false,
        );
        await tester.pump();
        expect(find.byType(AnnotationToolbar), findsNothing);
        expect(surface.calls, contains('clearSelection'));
        expect(fakeFullscreen.isFullscreenNow, isTrue,
            reason: '有選取時 Esc 只關閉選取工具列，全螢幕維持');

        // 4. 無選取時按 Esc：退出視窗全螢幕
        foliateView.onDesktopKey!(
          'Escape',
          shift: false,
          control: false,
          alt: false,
          meta: false,
        );
        await tester.pump();
        expect(fakeFullscreen.isFullscreenNow, isFalse,
            reason: '無選取且為全螢幕時 Esc 退出全螢幕');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('onDesktopKey 修飾鍵阻斷：alt: true 的 ArrowLeft 不翻頁', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final surface = FakeReaderSurface.foliate();
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ReaderScreen(
              filePath: 'test/fixtures/sample.epub',
              bookId: 'b_foliate_mod',
              dependencies: fakeReaderFeatureDependencies(
                prefsManager: FakeReaderPrefsManager(),
                readerSurfaceFactory: (_) => surface,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();

        final foliateView = tester.widget<FoliateReaderView>(
          find.byType(FoliateReaderView),
        );
        foliateView.onPageRendered();
        await tester.pump();
        await tester.runAsync(() => LocalBookServer.instance.close());

        surface.calls.clear();
        foliateView.onDesktopKey!(
          'ArrowLeft',
          shift: false,
          control: false,
          alt: true,
          meta: false,
        );
        await tester.pump();
        expect(surface.calls, isEmpty, reason: '帶 Alt 修飾鍵之翻頁鍵應被阻斷');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
        '雙重交付去重：同一按鍵先由 Flutter 處理，50ms 內又由 onDesktopKey 收到，只翻一頁、F11 只切換一次',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final fakeFullscreen =
          FakeWindowFullscreenController(initialFullscreen: false);
      activeWindowFullscreenController = fakeFullscreen;
      addTearDown(() => activeWindowFullscreenController = null);

      try {
        final surface = FakeReaderSurface.foliate();
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => WindowFullscreenShortcuts(
              controller: fakeFullscreen,
              child: child!,
            ),
            home: ReaderScreen(
              filePath: 'test/fixtures/sample.epub',
              bookId: 'b_foliate_dedup',
              dependencies: fakeReaderFeatureDependencies(
                prefsManager: FakeReaderPrefsManager(),
                readerSurfaceFactory: (_) => surface,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();

        final foliateView = tester.widget<FoliateReaderView>(
          find.byType(FoliateReaderView),
        );
        foliateView.onPageRendered();
        await tester.pump();
        await tester.runAsync(() => LocalBookServer.instance.close());

        // 1. 翻頁去重
        surface.calls.clear();
        // Flutter 端先收到
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(surface.calls, ['nextPage']);

        // Web 端緊接著（50ms 內）也轉送過來
        foliateView.onDesktopKey!(
          'ArrowRight',
          shift: false,
          control: false,
          alt: false,
          meta: false,
        );
        await tester.pump();
        expect(surface.calls, ['nextPage'], reason: '50ms 內重複收到的 web 轉送應被去重過濾');

        // 2. F11 去重
        expect(fakeFullscreen.history, isEmpty);
        // Flutter 端先收到 F11
        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        await tester.pump();
        expect(fakeFullscreen.history, [true]);

        // Web 端 50ms 內也轉送 F11
        foliateView.onDesktopKey!(
          'F11',
          shift: false,
          control: false,
          alt: false,
          meta: false,
        );
        await tester.pump();
        expect(fakeFullscreen.history, [true],
            reason: '50ms 內重複收到的 F11 應被去重過濾，不重複切換');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
