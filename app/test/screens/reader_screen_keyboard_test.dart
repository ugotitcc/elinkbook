import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/local_book_server.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/reader/pdf_crop_frame_overlay.dart';
import 'package:elinkbook/screens/annotation_toolbar.dart';
import 'package:elinkbook/screens/book_search_screen.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_inappwebview_platform.dart';
import '../support/fake_reader_feature_dependencies.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_reader_surface.dart';
import '../support/fake_search_repository.dart';
import '../support/pump_until_pdf_ready.dart';

void main() {
  late Future<String?> Function(String, String) originalCacheBookForServing;

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
    pdfrxInitialize();
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    binaryMessenger.setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (call) async => null,
    );
    binaryMessenger.setMockMethodCallHandler(
      const MethodChannel('elinkbook/volume_key'),
      (call) async => null,
    );
  });

  tearDown(() async {
    await LocalBookServer.instance.close();
  });

  Future<GlobalKey<State<ReaderScreen>>> pumpEpubReader(
    WidgetTester tester, {
    required FakeReaderSurface surface,
    FakeReaderPrefsManager? prefsManager,
    bool markRendered = true,
    ReaderJumpTarget? initialJumpTarget,
    Widget? overlayWidget,
  }) async {
    final key = GlobalKey<State<ReaderScreen>>();
    final effectivePrefsManager = prefsManager ?? FakeReaderPrefsManager();
    final reader = ReaderScreen(
      key: key,
      filePath: 'test/fixtures/sample.epub',
      bookId: 'b_keyboard_epub',
      initialJumpTarget: initialJumpTarget,
      dependencies: fakeReaderFeatureDependencies(
        prefsManager: effectivePrefsManager,
        readerSurfaceFactory: (_) => surface,
        searchRepository: FakeSearchRepository(),
      ),
    );

    final home = overlayWidget == null
        ? reader
        : Stack(
            children: [
              reader,
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Material(child: overlayWidget),
              ),
            ],
          );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: home,
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    if (markRendered) {
      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      await tester.pump();
    }
    await tester.runAsync(() => LocalBookServer.instance.close());
    return key;
  }

  Future<GlobalKey<State<ReaderScreen>>> pumpPdfReader(
    WidgetTester tester, {
    required FakeReaderSurface surface,
    FakeReaderPrefsManager? prefsManager,
    bool waitForReady = true,
    ReaderJumpTarget? initialJumpTarget,
  }) async {
    final key = GlobalKey<State<ReaderScreen>>();
    final effectivePrefsManager = prefsManager ?? FakeReaderPrefsManager();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_keyboard_pdf',
          initialJumpTarget: initialJumpTarget,
          dependencies: fakeReaderFeatureDependencies(
            prefsManager: effectivePrefsManager,
            readerSurfaceFactory: (_) => surface,
            searchRepository: FakeSearchRepository(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    if (waitForReady) {
      await pumpUntilPdfReady(
        tester,
        condition: () =>
            find.byKey(const Key('reader_loading_indicator')).evaluate().isEmpty,
      );
    }
    return key;
  }

  group('ReaderScreen 鍵盤快捷鍵（Windows）', () {
    testWidgets('橫排：→ 呼叫 nextPage、← 呼叫 previousPage', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final surface = FakeReaderSurface.foliate();
        await pumpEpubReader(tester, surface: surface);
        surface.calls.clear();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(surface.calls, ['nextPage']);

        surface.calls.clear();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(surface.calls, ['previousPage']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('直排：← 為下一頁、→ 為上一頁', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final surface = FakeReaderSurface.foliate();
        final prefsManager = FakeReaderPrefsManager(
          bookPrefsByBookId: {
            'b_keyboard_epub': const BookReaderPrefs(
              writingModeOverride: WritingMode.vertical,
            ),
          },
        );
        await pumpEpubReader(tester, surface: surface, prefsManager: prefsManager);
        surface.calls.clear();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(surface.calls, ['nextPage']);

        surface.calls.clear();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(surface.calls, ['previousPage']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Space 為下一頁、Shift+Space 為上一頁、PageDown／PageUp／↓／↑ 照對應',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final surface = FakeReaderSurface.foliate();
        await pumpEpubReader(tester, surface: surface);

        final expectations = [
          (LogicalKeyboardKey.space, false, 'nextPage'),
          (LogicalKeyboardKey.pageDown, false, 'nextPage'),
          (LogicalKeyboardKey.arrowDown, false, 'nextPage'),
          (LogicalKeyboardKey.pageUp, false, 'previousPage'),
          (LogicalKeyboardKey.arrowUp, false, 'previousPage'),
        ];

        for (final (key, _, expectedCall) in expectations) {
          surface.calls.clear();
          await tester.sendKeyEvent(key);
          await tester.pump();
          expect(surface.calls, [expectedCall], reason: '按鍵 $key 應觸發 $expectedCall');
        }

        // Shift+Space
        surface.calls.clear();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(surface.calls, ['previousPage'], reason: 'Shift+Space 應上一頁');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
        'Home 呼叫 jumpTo(progression: 0.0)、End 為 1.0（EPUB）；PDF 為 pdfPageIndex 0 與最後一頁；PDF 頁數資訊尚未就緒時忽略',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        // 1. EPUB 測試
        final foliateSurface = FakeReaderSurface.foliate();
        await pumpEpubReader(tester, surface: foliateSurface);

        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        expect(foliateSurface.calls, contains('jumpTo'));
        expect(foliateSurface.jumpTargets.last.progression, 0.0);

        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump();
        expect(foliateSurface.jumpTargets.last.progression, 1.0);

        // 2. PDF 就緒測試（sample_multi_page.pdf 共 5 頁，index 0..4）
        final pdfSurface = FakeReaderSurface.pdf();
        await pumpPdfReader(tester, surface: pdfSurface, waitForReady: true);

        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        expect(pdfSurface.calls, contains('jumpTo'));
        expect(pdfSurface.jumpTargets.last.pdfPageIndex, 0);

        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump();
        expect(pdfSurface.jumpTargets.last.pdfPageIndex, 4);

        // 3. PDF 頁數資訊尚未就緒時忽略（不 waitForReady，且 _pdfPageInfo 為 null）
        final pdfSurfaceNotReady = FakeReaderSurface.pdf();
        await pumpPdfReader(tester,
            surface: pdfSurfaceNotReady, waitForReady: false);
        // 模擬直接呼叫 onPageRendered 使 _openBookFlow 轉為 rendered，但 _pdfPageInfo 仍為 null
        tester
            .widget<PdfReaderView>(find.byType(PdfReaderView))
            .onPageRendered();
        await tester.pump();

        pdfSurfaceNotReady.calls.clear();
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump();
        expect(pdfSurfaceNotReady.calls, isNot(contains('jumpTo')));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Home／End 會清除搜尋跳轉高亮並記錄閱讀活動（與 _handleZoneAction 一致）',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final surface = FakeReaderSurface.pdf(showsTransientHighlight: true);
        await pumpPdfReader(
          tester,
          surface: surface,
          initialJumpTarget: const ReaderJumpTarget(
            pdfPageIndex: 0,
            pdfRect:
                PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
          ),
        );

        surface.calls.clear();
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();

        expect(surface.calls, contains('clearTransientHighlight'));
        expect(surface.calls, contains('jumpTo'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Ctrl+F 開啟書內搜尋（push BookSearchScreen）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final surface = FakeReaderSurface.foliate();
        await pumpEpubReader(tester, surface: surface);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        expect(find.byType(BookSearchScreen), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('按住不放（KeyRepeatEvent）持續翻頁、不丟例外 (Review Focus 1)',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final surface = FakeReaderSurface.foliate();
        await pumpEpubReader(tester, surface: surface);
        surface.calls.clear();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();

        expect(surface.calls, ['nextPage', 'nextPage', 'nextPage']);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
        '書籍載入中、載入失敗：翻頁、Home／End、Ctrl+F 都被忽略、不開搜尋頁、不崩潰；PDF 手動裁切模式：同樣被忽略 (Review Focus 3)',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        // 1. 載入中
        final loadingSurface = FakeReaderSurface.foliate();
        await pumpEpubReader(tester,
            surface: loadingSurface, markRendered: false);
        loadingSurface.calls.clear();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        expect(loadingSurface.calls, isEmpty);
        expect(find.byType(BookSearchScreen), findsNothing);

        // 2. 手動裁切模式
        final pdfSurface = FakeReaderSurface.pdf();
        await pumpPdfReader(tester, surface: pdfSurface);

        // 進入裁切模式
        tester
            .widget<IconButton>(
              find.byKey(const Key('reader_chrome_layout_button')),
            )
            .onPressed!();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
        await tester.pumpAndSettle();
        expect(find.byType(PdfCropFrameOverlay), findsOneWidget);

        pdfSurface.calls.clear();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        expect(pdfSurface.calls, isEmpty);
        expect(find.byType(BookSearchScreen), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('路由被疊上（showDialog）時按 →：不翻頁；文字輸入框有焦點時按 →、Space、Home：不翻頁',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        // 1. 文字輸入框獲得焦點
        final focusNode = FocusNode();
        final surfaceInput = FakeReaderSurface.foliate();
        await pumpEpubReader(
          tester,
          surface: surfaceInput,
          overlayWidget: TextField(
            key: const Key('test_input_field'),
            focusNode: focusNode,
          ),
        );
        surfaceInput.calls.clear();

        focusNode.requestFocus();
        await tester.pump();
        expect(focusNode.hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        expect(surfaceInput.calls, isEmpty, reason: '輸入框有焦點時快捷鍵應被阻斷');

        // 2. 路由被疊上（showDialog）
        final surfaceDialog = FakeReaderSurface.foliate();
        final key = await pumpEpubReader(tester, surface: surfaceDialog);
        surfaceDialog.calls.clear();

        final context = key.currentContext!;
        unawaited(showDialog(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text('Dialog'),
          ),
        ));
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(surfaceDialog.calls, isEmpty, reason: '路由被疊上時快捷鍵應被阻斷');

        // 關閉 Dialog 後恢復
        Navigator.of(context).pop();
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(surfaceDialog.calls, ['nextPage']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Alt+←、Ctrl+→：不翻頁', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final surface = FakeReaderSurface.foliate();
        await pumpEpubReader(tester, surface: surface);
        surface.calls.clear();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        expect(surface.calls, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
        'Esc：有文字選取時清除選取並消費；PDF 裁切模式時被吞掉且裁切模式維持；兩者皆無時不消費 (Review Focus 6)',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        // 1. 有文字選取時
        final foliateSurface = FakeReaderSurface.foliate();
        await pumpEpubReader(tester, surface: foliateSurface);

        final foliateView = tester.widget<FoliateReaderView>(
          find.byType(FoliateReaderView),
        );
        foliateView.onSelectionChanged?.call(
          const EpubSelectionInfo(
            locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
            progression: 0.1,
            rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
          ),
        );
        await tester.pump();
        expect(find.byType(AnnotationToolbar), findsOneWidget);

        foliateSurface.calls.clear();
        final handledWithSelection =
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        expect(find.byType(AnnotationToolbar), findsNothing,
            reason: 'Esc 應關閉 AnnotationToolbar');
        expect(foliateSurface.calls, contains('clearSelection'),
            reason: 'Esc 應呼叫 clearSelection');
        expect(handledWithSelection, isTrue, reason: '選取存在時 Esc 應被消費');

        // 2. 兩者皆無時
        final handledClean =
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(handledClean, isFalse, reason: '無選取且無裁切時 Esc 不應被消費');

        // 3. PDF 裁切模式時
        final pdfSurface = FakeReaderSurface.pdf();
        await pumpPdfReader(tester, surface: pdfSurface);

        tester
            .widget<IconButton>(
              find.byKey(const Key('reader_chrome_layout_button')),
            )
            .onPressed!();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
        await tester.pumpAndSettle();
        expect(find.byType(PdfCropFrameOverlay), findsOneWidget);

        final handledCrop =
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        expect(find.byType(PdfCropFrameOverlay), findsOneWidget,
            reason: '裁切模式下 Esc 應吞掉、裁切模式維持');
        expect(handledCrop, isTrue, reason: '裁切模式下 Esc 應被消費');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
        '離開閱讀器（pop）後按 →：surface 沒有被呼叫；再開一次書後按 → 只翻一頁（不是兩頁） (Review Focus 4)',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final surface1 = FakeReaderSurface.foliate();
        final surface2 = FakeReaderSurface.foliate();

        Widget buildHost() {
          return MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReaderScreen(
                          filePath: 'test/fixtures/sample.epub',
                          bookId: 'b1',
                          dependencies: fakeReaderFeatureDependencies(
                            readerSurfaceFactory: (_) => surface1,
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Book 1'),
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(buildHost());
        await tester.tap(find.text('Open Book 1'));
        await tester.pump();
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();

        tester
            .widget<FoliateReaderView>(find.byType(FoliateReaderView))
            .onPageRendered();
        await tester.pump();

        // 第一次開書按 →
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(surface1.calls, ['nextPage']);

        // Pop 離開
        Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(ReaderScreen), findsNothing);

        // 離開後按 →：surface1 不應增加呼叫
        surface1.calls.clear();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(surface1.calls, isEmpty);

        // 再次開啟（使用 surface2）
        final navContext = tester.element(find.text('Open Book 1'));
        Navigator.of(navContext).push(
          MaterialPageRoute(
            builder: (_) => ReaderScreen(
              filePath: 'test/fixtures/sample.epub',
              bookId: 'b2',
              dependencies: fakeReaderFeatureDependencies(
                readerSurfaceFactory: (_) => surface2,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();
        tester
            .widget<FoliateReaderView>(find.byType(FoliateReaderView))
            .onPageRendered();
        await tester.pump();

        // 按 →：surface2 應只收到 1 次 nextPage
        surface2.calls.clear();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(surface2.calls, ['nextPage']);

        await tester.runAsync(() => LocalBookServer.instance.close());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('非 Windows 平台：按 →、Esc 都不處理', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final surface = FakeReaderSurface.foliate();
        await pumpEpubReader(tester, surface: surface);
        surface.calls.clear();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(surface.calls, isEmpty);

        final handled = await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(handled, isFalse, reason: '非 Windows 下 Esc 不由 ReaderScreen 攔截');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
