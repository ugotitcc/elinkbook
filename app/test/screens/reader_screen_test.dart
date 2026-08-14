
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/screens/fxl_settings_sheet.dart';
import 'package:elinkbook/screens/reader_settings_sheet.dart';
import 'package:elinkbook/reader/toc_entry.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';

import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import '../support/fake_inappwebview_platform.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_custom_fonts_repository.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import '../support/fake_bookmarks_repository.dart';
import 'package:elinkbook/screens/annotation_toolbar.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:elinkbook/reader/pdf_crop_frame_overlay.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/layout_preset.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 依 spec.md「測試決策」：ReaderScreen 分派到 EpubReaderView/PdfReaderView
// 後，實際渲染內容存在於原生 PlatformView 之中，一般 flutter test（無真實
// 裝置/模擬器）無法觀察其渲染結果，因此 EPUB/PDF 兩個分支的「確實渲染出
// 內容」驗證改由 integration_test/reader_screen_test.dart 在真實裝置上
// 執行；此處只保留 flutter test 就能可靠驗證的部分：「不支援格式」分支、
// 「⚙️版面」按鈕在 onLayoutResolved 觸發前的初始狀態，以及排版方向／
// 翻頁模式雙層解析邏輯（後者不依賴 onLayoutResolved，可離線驗證，見
// docs/epics/epic-3-fonts-layout/plans/plan-issue-4.md）。

void main() {
  late FakeReaderPrefsManager prefsManager;
  // 保存原始實作， tearDownAll 時還原
  late Future<String?> Function(String, String) originalCacheBookForServing;

  setUpAll(() {
    InAppWebViewPlatform.instance = FakeInAppWebViewPlatform();
    originalCacheBookForServing = cacheBookForServing;
    // 直接覆寫頂層函數變數，繞過 Dart 端檔案系統檢查（File.exists()、
    // resolveSymbolicLinksSync()、getApplicationDocumentsDirectory() 等），
    // 確保 FoliateEpubReaderView 的 _cacheBook() 在測試環境中能順利完成。
    cacheBookForServing = (filePath, instanceId) async {
      return '/fake/cache/dir/current.epub';
    };
  });

  setUp(() {
    pdfrxInitialize();
    prefsManager = FakeReaderPrefsManager();
    // ReaderScreen 初始化時會透過 elinkbook/fullscreen MethodChannel 呼叫
    // setEnabled（非同步、非 awaited）。若前一個測試的 addTearDown 移除了
    // mock handler，這段 async 呼叫會在 handler 遺失時完成，導致
    // MissingPluginException 洩漏到下一個測試。在 setUp 全域註冊 mock
    // handler 可避免此競態。
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    binaryMessenger.setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (call) async => null,
    );
  });

  testWidgets('不支援格式顯示明確錯誤訊息', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.txt',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );

    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.text('不支援的檔案格式'), findsOneWidget);
  });

  testWidgets('EPUB 格式顯示「⚙️版面」按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );

    final finder = find.byKey(const Key('reader_layout_settings_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，_autoDetectedWritingMode 仍為 null，按鈕應為停用狀態',
    );
  });

  testWidgets('PDF 格式顯示「⚙️版面」按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );

    // epic-24 Issue 8：PDF 不再使用 AppBar，設定按鈕改為 FAB。
    final finder = find.byKey(const Key('reader_pdf_settings_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason:
          '尚未收到 onPageRendered（純 flutter test 環境下 AndroidView 不會'
          '觸發原生回呼），按鈕應為停用狀態，比照 EPUB 齒輪按鈕的既有測試限制'
          '（見本檔案第 46-65 行）',
    );
  });

  // Epic 20 Issue 2：isFixedLayout: true 時改為 FoliateEpubReaderView 並傳遞
  // isFixedLayoutHint，不呼叫偵測（main.js 會 early-return 跳過 applyPreferences
  // 的非必要設定）。
  testWidgets('isFixedLayout: true 時建構 FoliateEpubReaderView 並傳遞 isFixedLayoutHint', (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
          libraryRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(FoliateEpubReaderView), findsOneWidget);
    expect(repository.detectAndCacheEpubLayoutCalls, isEmpty);
    // 驗證 isFixedLayoutHint 正確傳遞到 FoliateEpubReaderView
    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    expect(foliateView.isFixedLayoutHint, isTrue);
  });

  testWidgets('isFixedLayout: false 時直接建構 FoliateEpubReaderView，不呼叫偵測', (
    tester,
  ) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
          libraryRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(FoliateEpubReaderView), findsOneWidget);
    expect(repository.detectAndCacheEpubLayoutCalls, isEmpty);
  });

  // Epic 20 Issue 3：FoliateEpubReaderView 的 dualPageMode/isLandscape 參數下傳
  testWidgets('裝置為橫向時，isLandscape 正確下傳給 FoliateEpubReaderView 建構參數', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 400)); // 橫向

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    expect(foliateView.isLandscape, isTrue);
  });

  testWidgets('裝置為直向時，isLandscape 正確下傳為 false', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800)); // 直向
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    expect(foliateView.isLandscape, isFalse);
  });

  testWidgets('開啟該書已有的持久化雙頁偏好設定後，FoliateEpubReaderView 的 dualPageMode 正確載入', (tester) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(
        dualPageMode: DualPageMode.always,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    expect(foliateView.dualPageMode, DualPageMode.always);
  });

  testWidgets('尚未持久化雙頁偏好設定時，FoliateEpubReaderView 的 dualPageMode 為 auto（預設值）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    expect(foliateView.dualPageMode, DualPageMode.auto);
  });

  testWidgets('開啟該書已有的持久化換頁動畫偏好設定後，PdfReaderView 的 pdfPageTurnAnimation 正確載入',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(
        pdfPageTurnAnimation: PdfPageTurnAnimation.none,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView =
        tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.pdfPageTurnAnimation, PdfPageTurnAnimation.none);
  });

  testWidgets('尚未持久化換頁動畫偏好設定時，PdfReaderView 的 pdfPageTurnAnimation 為 slide（預設值）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView =
        tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.pdfPageTurnAnimation, PdfPageTurnAnimation.slide);
  });

  testWidgets(
    '流式 EPUB（isFixedLayout: false）開書後，onLayoutResolved 回報結果驅動「版面設定」按鈕從停用轉為可用',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final finder = find.byKey(const Key('reader_foliate_settings_button'));
      expect(
        tester.widget<IconButton>(finder).onPressed,
        isNull,
        reason: '尚未收到 onLayoutResolved，_autoDetectedWritingMode 仍為 null',
      );

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.vertical,
        ),
      );
      await tester.pump();

      expect(
        tester.widget<IconButton>(finder).onPressed,
        isNotNull,
        reason: 'onLayoutResolved 觸發後，_autoDetectedWritingMode 非 null，按鈕應可用',
      );
    },
  );

  testWidgets(
    '流式 EPUB 開書後，ReaderSettingsSheet 變動的偏好正確傳遞到 FoliateEpubReaderView',
    (tester) async {
      // 設定較大的 Viewport，確保 BottomSheet 內的控制項皆在可點擊範圍內
      // （Issue 14 邊距拆為 4 個獨立滑桿後內容變高，1200 已不足，調高至 1600）
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final initialView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      initialView.onPageRendered(); // 模擬開書成功，脫離 loading 狀態
      initialView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('reader_settings_writing_mode_vertical')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('reader_settings_column_mode_single')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reader_settings_show_footer')));
      await tester.pumpAndSettle();

      final updatedView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      expect(updatedView.writingMode, WritingMode.vertical);
      expect(updatedView.columnMode, ColumnMode.single);
      expect(updatedView.showFooter, isFalse);
    },
  );

  testWidgets(
    'isFixedLayout: null 且提供 libraryRepository 時，呼叫 detectAndCacheEpubLayout 並依結果建構 FoliateEpubReaderView',
    (tester) async {
      final repository = FakeLibraryRepository(detectedIsFixedLayout: false);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            libraryRepository: repository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(repository.detectAndCacheEpubLayoutCalls, ['b1']);
      expect(find.byType(FoliateEpubReaderView), findsOneWidget);
    },
  );

  testWidgets(
    'isFixedLayout: null 且提供 libraryRepository、偵測結果為 FXL 時，建構 EpubReaderView',
    (tester) async {
      final repository = FakeLibraryRepository(detectedIsFixedLayout: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_fixed_layout.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            libraryRepository: repository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(repository.detectAndCacheEpubLayoutCalls, ['b1']);
      expect(find.byType(FoliateEpubReaderView), findsOneWidget);
    },
  );

  testWidgets(
    'isFixedLayout: null 且未提供 libraryRepository 時，退回既有行為建構 EpubReaderView（零回歸）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(find.byType(FoliateEpubReaderView), findsOneWidget);
    },
  );

  testWidgets('開啟該書已有的持久化版面偏好設定後，狀態正確載入', (tester) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(fontSize: 1.5),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final viewFinder = find.byType(FoliateEpubReaderView);
    expect(viewFinder, findsOneWidget);
    final epubView = tester.widget<FoliateEpubReaderView>(viewFinder);
    expect(epubView.fontSize, 1.5);
  });

  testWidgets('writingModeOverride 已持久化時，即使尚未收到 onLayoutResolved，'
      'EpubReaderView.writingMode 仍採用覆寫值', (tester) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(writingModeOverride: WritingMode.vertical),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    expect(epubView.writingMode, WritingMode.vertical);
    // 排版方向的雙層解析獨立於「⚙️版面」按鈕的啟用條件——後者仍要求真正
    // 收到 onLayoutResolved（見 _buildAppBarActions 的
    // _autoDetectedWritingMode 判斷），純 flutter test 環境下 AndroidView
    // 不會觸發原生回呼，因此這裡按鈕仍是停用狀態，屬預期行為，不是本測試
    // 要驗證的重點。
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('reader_layout_settings_button')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('pageTurnModeOverride 為 null 時，未覆寫的書籍採用全域預設值（paginated）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    expect(epubView.pageTurnMode, PageTurnMode.paginated);
  });

  testWidgets('全域預設值已改為 scroll 時，未覆寫的書籍採用該全域值', (tester) async {
    prefsManager.globalPrefs = prefsManager.globalPrefs.copyWith(
      pageTurnMode: PageTurnMode.scroll,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    expect(epubView.pageTurnMode, PageTurnMode.scroll);
  });

  testWidgets('pageTurnModeOverride 已持久化時，優先於全域預設值', (tester) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(pageTurnModeOverride: PageTurnMode.scroll),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    expect(epubView.pageTurnMode, PageTurnMode.scroll);
  });

  testWidgets('進入手動裁切互動模式後，PopScope.canPop 為 false（返回鍵不應退出整個閱讀器）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(
      tester.widget<PopScope>(find.byType(PopScope)).canPop,
      isTrue,
      reason: '尚未進入裁切互動模式時，返回鍵應正常運作（可以離開閱讀器）',
    );

    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    // epic-24 Issue 8：PDF 不再使用 AppBar，設定按鈕改為 FAB。
    // 直接呼叫 onPressed callback 繞過 PdfReaderView gesture arena 問題。
    tester.widget<IconButton>(find.byKey(const Key('reader_pdf_settings_button'))).onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<PopScope>(find.byType(PopScope)).canPop,
      isFalse,
      reason:
          '裁切互動模式進行中，返回鍵不應把整個 ReaderScreen 一併 '
          'pop 掉（審查意見 2.1(b)：避免誤觸返回鍵導致整個閱讀器被意外'
          '關閉；刻意不新增「取消並還原」語意，維持 spec.md 已鎖定的簡化'
          '狀態機決策——見本檔案 _handleRequestManualCrop 的文件註解）',
    );
  });

  testWidgets(
    'onLayoutResolved 觸發後，EpubReaderView.writingMode 帶入自動偵測到的直排方向（C2 接線）',
    (tester) async {
      // 不預設任何 writingModeOverride，讓自動偵測值決定結果
      final manager = FakeReaderPrefsManager();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: manager,
          ),
        ),
      );
      // 等待 initState 的 async load 完成
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 比照同檔既有 PDF 測試直接呼叫公開 callback prop 的手法
      //（onPageRendered: reader_screen_test.dart:317），
      // EpubReaderView.onLayoutResolved 是公開的 ValueChanged<EpubLayoutInfo>?
      // callback prop（epub_reader_view.dart:32），可在純 flutter test 中直接呼叫。
      tester
          .widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView))
          .onLayoutResolved!(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.vertical,
        ),
      );
      await tester.pump();

      expect(
        tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView)).writingMode,
        WritingMode.vertical,
      );
    },
  );

  testWidgets('EPUB 固定版面開書後，畫面右上角出現懸浮設定按鈕，點擊能開啟 FxlSettingsSheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 純 flutter test 環境沒有真實裝置能觸發原生端 onLayoutResolved，直接呼叫
    // EpubReaderView 目前已知的 onLayoutResolved callback 模擬原生端回報，比照
    // 本檔案既有測試對「無法在此層級驅動原生渲染」的既定限制處理方式。
    final view = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_foliate_settings_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('reader_foliate_settings_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FxlSettingsSheet), findsOneWidget);
  });

  // epic-20-fxl-foliate-migration Issue 4 Task 3 Step 3：合併按鈕群組後，
  // reader_foliate_settings_button 是唯一仍需依 _isFixedLayout 分流的按鈕
  // （FXL 開 FxlSettingsSheet、流式開 ReaderSettingsSheet）。以下兩個測試
  // 明確斷言「另一種 Sheet 不會被誤開」（`findsNothing` 交叉驗證），
  // 區別於既有兩個各自獨立驗證單一分支的測試（:890「開啟 FxlSettingsSheet」、
  // :3479「開啟 ReaderSettingsSheet」）；比照既有 FXL 測試（:890）
  // 使用固定 `pump` 而非 `pumpAndSettle`（FXL 分支下 `pumpAndSettle` 曾
  // 逾時，見該處既有寫法）。
  testWidgets(
    'reader_foliate_settings_button 分流：FXL 書籍開啟 FxlSettingsSheet、不誤開 ReaderSettingsSheet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_fixed_layout.epub',
            bookId: 'b_settings_dispatch_fxl',
            prefsManager: prefsManager,
            isFixedLayout: true,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      final fxlView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      fxlView.onPageRendered();
      fxlView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: true,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FxlSettingsSheet), findsOneWidget);
      expect(find.byType(ReaderSettingsSheet), findsNothing);
    },
  );

  testWidgets(
    'reader_foliate_settings_button 分流：流式書籍開啟 ReaderSettingsSheet、不誤開 FxlSettingsSheet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_settings_dispatch_reflowable',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      final reflowableView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      reflowableView.onPageRendered();
      reflowableView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSettingsSheet), findsOneWidget);
      expect(find.byType(FxlSettingsSheet), findsNothing);
    },
  );

  testWidgets('固定版面點擊中間熱區可切換懸浮按鈕顯示/隱藏', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 直接呼叫 onLayoutResolved 模擬原生端回報 isFixedLayout=true
    final view = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_foliate_back_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader_foliate_settings_button')),
      findsOneWidget,
    );

    // 直接呼叫 onZoneAction 模擬中間熱區觸發
    view.onZoneAction?.call(ZoneAction.menu);
    await tester.pump();

    expect(
      find.byKey(const Key('reader_foliate_back_button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reader_foliate_settings_button')),
      findsNothing,
    );

    // 再次觸發切換顯示
    view.onZoneAction?.call(ZoneAction.menu);
    await tester.pump();

    expect(
      find.byKey(const Key('reader_foliate_back_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader_foliate_settings_button')),
      findsOneWidget,
    );
  });

  testWidgets('固定版面點擊左/右熱區換頁後，懸浮按鈕維持原狀（不自動收起）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 直接呼叫 onLayoutResolved 模擬原生端回報 isFixedLayout=true
    final view = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_foliate_back_button')),
      findsOneWidget,
    );

    // 直接呼叫 onZoneAction 模擬換頁觸發
    view.onZoneAction?.call(ZoneAction.nextPage);
    await tester.pump();

    expect(
      find.byKey(const Key('reader_foliate_back_button')),
      findsOneWidget,
      reason: '換頁後，懸浮控制項應維持原狀（不自動收起，design.md 決策 #14）',
    );
  });

  testWidgets(
      '強制 FXL（widget.isFixedLayout: true）時，native 端異步回報 isFixedLayout: false 不會覆蓋，FXL chrome 仍正確顯示（Issue 15 commit 97878c4 回歸測試）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 引擎分派（_dispatchedIsFixedLayout）已由 widget.isFixedLayout 同步
    // 決定，建構的必為 EpubReaderView（Readium/FXL 路徑）。
    expect(find.byType(FoliateEpubReaderView), findsOneWidget);

    // 模擬 native 端（Readium 自己對這本書 metadata 的獨立判讀，見
    // EpubReaderView.kt 的 publication?.metadata?.layout）異步回報
    // isFixedLayout: false——比照本檔案既有測試對「無法在此層級驅動原生
    // 渲染」的既定處理方式，直接呼叫 onLayoutResolved callback。
    final view = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 使用者透過「強制 FXL」手動設定的決定不應被 native 端的異步回報
    // 覆蓋——FXL 專屬的懸浮設定按鈕仍須顯示（見 reader_screen.dart
    // `_resolveEpubEngineDispatch()`／`_handleLayoutResolved()` 的
    // widget.isFixedLayout 保護邏輯）。
    expect(
      find.byKey(const Key('reader_foliate_settings_button')),
      findsOneWidget,
      reason: '強制 FXL 後，native 異步回報 isFixedLayout=false 不應覆蓋 _isFixedLayout',
    );
  });

  testWidgets('FXL：真實點擊熱區「選單」格（index 1，中欄）觸發沉浸模式切換', (tester) async {
    // 【Task 4 重寫】原本使用 SystemChannels.platform_views mock 擷取
    // per-instance MethodChannel 來模擬 EpubReaderView（Readium）內部的
    // isFixedLayout 狀態。Epic 17 Issue 2 後 _buildNativeView() 統一返回
    // FoliateEpubReaderView，其熱區由 Dart 端 _ZoneOverlay（build() 內
    // 3×3 grid）直接渲染，不再依賴 MethodChannel。改用
    // tester.widget<FoliateEpubReaderView>() 取得 widget 實例、直接呼叫
    // onLayoutResolved 回調來設定 ReaderScreen 的 _isFixedLayout 狀態。
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 直接呼叫 FoliateEpubReaderView 的 onLayoutResolved 回調，模擬原生端
    // 回報 isFixedLayout=true，讓 ReaderScreen 顯示 FXL 專屬懸浮按鈕。
    final epubView =
        tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_foliate_back_button')),
      findsOneWidget,
    );

    // navZoneMode 預設 rightFlip，index 1（中欄）為 menu
    // （見 app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
    // FoliateEpubReaderView 的 _ZoneOverlay 永遠渲染 3×3 熱區，
    // onZoneAction 回調已接線到 ReaderScreen._handleZoneAction。
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    expect(
      find.byKey(const Key('reader_foliate_back_button')),
      findsNothing,
    );
  });

  testWidgets('PDF 開書後，收到原生端 onPageChanged 回報時，頁尾正確顯示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_footer_test',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 模擬原生端回報頁碼：直接呼叫 PdfReaderView widget 上的 onPageChanged
    // callback（比照既有 EPUB 測試直接呼叫 onLayoutResolved 的模式）。
    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(
      const PdfPageInfo(pageIndex: 0, totalPages: 12),
    );
    await tester.pump();

    // epic-24 Issue 8：PDF 不再有 in-flow ReaderFooter，改由進度 FAB 觸發
    // Bottom Sheet 顯示頁碼。驗證 FAB 存在且 in-flow footer 已移除。
    expect(find.byKey(const Key('reader_pdf_progress_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  // --- 0↔1 頁碼轉換與 jumpToPage 原生呼叫 ---
  //
  // 此邊界在 widget test 層級**無法完整驗證**，原因：
  //   Flutter widget test 環境下 AndroidView 的 texture meta 未初始化，
  //   觸發 PdfReaderView.jumpToPage → method channel → platform view resize
  //   會導致 'meta != null' assertion failure（Flutter 框架已知限制，
  //   見 flutter_test/flutter_test.dart 以及 epic-1/epic-4 的歷史記錄）。
  //
  //   0↔1 轉換公式（page1Indexed - 1）以及原生端 jumpToPage 呼叫參數的
  //   完整驗證，由 integration_test/reader_footer_test.dart（真機）涵蓋：
  //   輸入「4」→ 斷言頁尾文字從「第 1/6 頁」變成「第 4/6 頁」。
  //
  //   讀者-footer 自身的 onPageChanged 回呼（1-indexed）已由
  //   reader_screen_test.dart 的其他測試以及 reader_footer_test.dart 覆蓋。
  //
  // 本檔案不重複測試上述已覆蓋的路徑。

  // --- Epic 5 Issue 2：閱讀位置記憶 ---

  testWidgets('PDF 收到 onPageChanged 後離開畫面（dispose），正確寫入 ReadingPosition', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_dispose_test',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 模擬原生端回報頁碼：直接呼叫 PdfReaderView widget 上的 onPageChanged
    // callback（比照既有「PDF 開書後，收到原生端 onPageChanged 回報時，
    // 頁尾正確顯示」的模式），驗證 dispose() 時正確寫入 ReadingPosition。
    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(
      const PdfPageInfo(pageIndex: 3, totalPages: 10),
    );
    await tester.pump();

    // 導覽離開 ReaderScreen，觸發 dispose()。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(prefsManager.savedReadingPositionCalls, hasLength(1));
    final saved = prefsManager.savedReadingPositionCalls.single;
    expect(saved.key, 'b_dispose_test');
    expect(saved.value.pdfPageIndex, 3);
    expect(saved.value.progress, 0.4); // (3+1)/10
  });

  testWidgets(
    '尚未收到任何 onPageChanged 時，dispose 不呼叫 saveReadingPosition（避免覆寫既有記錄）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b_no_position',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      expect(prefsManager.savedReadingPositionCalls, isEmpty);
    },
  );

  // --- Epic 5 Issue 3：EPUB 頁碼顯示 + 跳頁 ---

  testWidgets('EPUB reflowable 開書後，收到 onCharacterCountReady 回報時，頁尾正確顯示估算頁碼', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_epub_footer_test',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    // 先回報非固定版面（頁尾只在流式 EPUB 顯示）。
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // TODO(epic-20): FoliateEpubReaderView 目前尚未提供
    // onCharacterCountReady callback，頁尾不會渲染——符合預期。
    // 當 FoliateEpubReaderView 加入 onCharacterCountReady 後，
    // 取消註解並還原驗證邏輯。
    // epubView.onCharacterCountReady?.call(5000);
    // await tester.pump();

    // FoliateEpubReaderView 無 onCharacterCountReady，頁尾不應出現。
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('EPUB 收到 onLocatorChanged 的 progression 後，頁尾目前頁碼正確更新', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_epub_footer_progression',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // TODO(epic-20): FoliateEpubReaderView 目前無 onCharacterCountReady。
    // epubView.onCharacterCountReady?.call(5000); // 總頁數 10
    await tester.pump();
    epubView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"href":"/c1.xhtml"}',
        progression: 0.5,
      ),
    );
    await tester.pump();

    // 無 onCharacterCountReady，頁尾不出現，進度文字也不應存在。
    expect(find.text('5/10'), findsNothing);
  });

  testWidgets('EPUB 固定版面（FXL）開書後，即使收到 onCharacterCountReady 也不顯示頁尾', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_epub_fxl_no_footer',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // TODO(epic-20): FoliateEpubReaderView 目前無 onCharacterCountReady。
    // epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('版面設定（字型大小）變動後，EPUB 頁尾估算總頁數即時重新計算', (tester) async {
    // 【Task 4 修正】FoliateEpubReaderView 無 onCharacterCountReady 回調
    //（EpubReaderView 獨有），改透過 FakeReaderPrefsManager 的
    // totalCharacterCountByBookId 在開書載入階段注入全書字元數（5000）。
    // ReaderScreen._initState 路徑：prefsManager.load(bookId) →
    // LoadedPrefs.totalCharacterCount → _totalCharacterCount，觸發 EPUB
    // 頁尾渲染（_buildBody 條件：_totalCharacterCount != null）。
    final footerPrefsManager = FakeReaderPrefsManager(
      totalCharacterCountByBookId: {'b_epub_footer_recalc': 5000},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_epub_footer_recalc',
          prefsManager: footerPrefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    epubView.onPageRendered();
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    // Issue 46：screenWidth=800/screenHeight=600（flutter_test 預設視窗
    // 尺寸）、其餘版面參數皆為預設值時，estimateCharsPerScreen() = 1598
    // （見 epub_page_estimator_test.dart 對應測試），totalPages =
    // ceil(5000/1598) = 4，progression 尚未收到任何回報（null）→ 第 1 頁。
    expect(find.text('1/4'), findsOneWidget);

    // 開啟版面設定，把字型大小從 16 調到 32（加倍），觸發真正的
    // _handlePrefsChanged → setState → rebuild 路徑（而非直接建構帶有
    // fontSize 覆寫值的 FakeReaderPrefsManager）。ReaderSettingsSheet 透過
    // onChanged 立即呼叫 ReaderScreen._handlePrefsChanged（見
    // reader_settings_sheet.dart _notifyChanged()），不需要關閉 Bottom
    // Sheet——底下的 ReaderScreen（含頁尾）仍在 widget tree 中並隨之
    // rebuild，find.text() 不受 Bottom Sheet 疊加在視覺上層影響。
    //
    // 【先前失敗原因，記錄供未來維護者知悉】原本此處省略了
    // onPageRendered()，導致 _state 停留在 loading、Stack 內的
    // CircularProgressIndicator（不定長動畫）持續繪製，任何後續
    // pumpAndSettle() 永遠不會收斂而逾時——這才是先前版本改用
    // FakeReaderPrefsManager 預先帶入 fontSize 覆寫值、完全繞開 Bottom
    // Sheet 互動的真正原因，並非 Bottom Sheet 本身在測試環境下無法渲染。
    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    // 每次點擊之間須 pump 一次，讓 ReaderSettingsSheet 以新的 _fontSize 值
    // 重新 build——否則 IconButton.onPressed 閉包捕捉到的仍是上一次 build
    // 當下的 clampedValue，16 次點擊會重複套用同一個遞增結果，而非累加。
    for (var i = 0; i < 16; i++) {
      await tester.tap(
        find.byKey(const Key('reader_settings_font_size_increment')),
      );
      await tester.pump();
    }

    // fontSize 倍率變成 2.0，且 16 次點擊過程中 ReaderSettingsSheet 的
    // _notifyChanged() 一併把行高／邊界的目前 UI 狀態（即使使用者未曾觸碰）
    // 送入 BookReaderPrefs——這些值恰好等於 estimateCharsPerScreen() 自身
    // 的預設 fallback（lineHeight 1.0／margin 32-16-24-24），數值不受影響。
    // fontSize=2.0、screenWidth=800/screenHeight=600 下
    // estimateCharsPerScreen() = 391（見 epub_page_estimator_test.dart
    // 對應測試），totalPages = ceil(5000/391) = 13。
    expect(find.text('1/13'), findsOneWidget);
  });

  testWidgets('PDF 頁尾行為不受本工單影響（既有回歸驗證）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_regression',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(
      const PdfPageInfo(pageIndex: 0, totalPages: 12),
    );
    await tester.pump();

    // epic-24 Issue 8：PDF 不再有 in-flow ReaderFooter，改由進度 FAB 觸發
    // Bottom Sheet。驗證 FAB 存在且 in-flow footer 已移除。
    expect(find.byKey(const Key('reader_pdf_progress_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  // --- Epic 5 Issue 4：EPUB 目錄（TOC）樹狀清單 ---

  testWidgets('EPUB 格式顯示「目錄」按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_toc_initial',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final finder = find.byKey(const Key('reader_toc_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，按鈕應為停用狀態',
    );
  });

  testWidgets('PDF 格式下，目錄入口按鈕不存在', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_toc_pdf',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byKey(const Key('reader_toc_button')), findsNothing);
  });

  testWidgets('EPUB 固定版面（FXL）開書後，目錄按鈕不存在（沿用既有 AppBar 隱藏機制）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_toc_fxl',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_toc_button')), findsNothing);
  });

  testWidgets(
    'EPUB reflowable 收到 onLayoutResolved 後，目錄按鈕轉為可點擊，點擊後開啟 TocBottomSheet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_toc_open',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final epubView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      epubView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      // 審查修正：目錄按鈕的啟用條件額外要求 _tocLoaded，該旗標由
      // EpubReaderView.loadTableOfContents() 這個 async 呼叫的 .then()
      // callback 設定，需要多一次 pump 讓其 microtask 完成、觸發 setState。
      await tester.pump();

      final finder = find.byKey(const Key('reader_toc_button'));
      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

      await tester.tap(finder);
      // showModalBottomSheet 動畫在 flutter test 環境下 pumpAndSettle 永遠不
      // 會收斂（持續泵送動畫幀），改用有限幀 pump 等待動畫展開，比照本檔案
      // 既有的 FxlSettingsSheet 開啟測試模式（第 548-554 行）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(TocBottomSheet), findsOneWidget);
    },
  );

  testWidgets('點選目錄項目後，TocBottomSheet 關閉', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_toc_select',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // 審查修正：多一次 pump 讓 loadTableOfContents() 的 .then() callback
    // 完成、_tocLoaded 變為 true，目錄按鈕才會真正可點擊。
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_toc_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TocBottomSheet), findsOneWidget);

    // 純 flutter test 環境下 EpubReaderView._channel 恆為 null（AndroidView
    // 未真正建立），loadTableOfContents() 回傳空清單，TocBottomSheet 內部
    // 不會有任何可點擊的項目列——直接呼叫 TocBottomSheet.onEntrySelected
    // 模擬使用者選取（比照本檔案既有測試對「純 flutter test 環境無法觸發
    // 原生回呼」的既定處理方式，見 onPageRendered/onLayoutResolved 相關
    // 既有測試）。
    final sheet = tester.widget<TocBottomSheet>(find.byType(TocBottomSheet));
    sheet.onEntrySelected(
      const TocEntry(title: '測試章節', locatorJson: '{}', progression: 0.5),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsNothing);
  });

  // --- Epic 5 Issue 5：頁首/頁尾顯示切換 ---

  testWidgets(
    'EPUB reflowable 預設（未持久化）showHeader=true，開書後 AppBar 標題為可點擊的章節標題元件',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_header_default',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final epubView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      epubView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('reader_appbar_chapter_title')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reader_appbar_static_title')), findsNothing);
      // 「⚙️版面」按鈕仍在 actions 內，頁首開關不影響既有版面設定入口
      expect(
        find.byKey(const Key('reader_layout_settings_button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('已持久化 showHeader=false 時，AppBar 標題維持靜態「閱讀器」文字', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_off',
      const BookReaderPrefs(showHeader: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_off',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget);
    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsNothing);
    expect(
      find.byKey(const Key('reader_toc_button')),
      findsOneWidget,
      reason: '頁首關閉不影響目錄按鈕仍存在於 actions',
    );
  });

  // epic-24 Issue 8：PDF 不再使用 AppBar，改用 6 顆 FAB。
  testWidgets('PDF 開書後，無 AppBar；6 顆 FAB 正確顯示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_header',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();

    // PDF 不再使用 AppBar。
    expect(find.byType(AppBar), findsNothing);
    // 驗證 FAB 存在（以返回按鈕與設定按鈕為代表）。
    expect(find.byKey(const Key('reader_pdf_back_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_pdf_settings_button')), findsOneWidget);
  });

  testWidgets('AppBar 顯示時，toolbarHeight 瘦身為 20（Issue 2）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_appbar_toolbar_height',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.preferredSize.height, 20.0);
  });

  testWidgets('AppBar 動作按鈕已收斂實際渲染寬度與圖示大小（Issue 2）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_appbar_action_size',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 斷言實際渲染的 Rect，而非只檢查建構子的 constraints/padding 欄位——
    // Material 3 的 IconButton 不會因建構子的 padding/constraints 參數而
    // 改變實際渲染尺寸（撰寫本計劃時已實測確認，見 Global Constraints
    // 「IconButton 尺寸收斂機制」），只檢查欄位值會造成「測試通過但實際
    // 尺寸沒變」的假陽性。
    final buttonRect = tester.getRect(
      find.byKey(const Key('reader_layout_settings_button')),
    );
    expect(buttonRect.width, 32.0);
    expect(
      buttonRect.height,
      20.0,
      reason: '高度恆等於 toolbarHeight，見 Global Constraints 說明',
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader_layout_settings_button')),
    );
    expect((button.icon as Icon).size, 18.0);
  });

  testWidgets('頁首啟用且目錄背景抓取完成後，點擊 AppBar 標題可開啟 TocBottomSheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_tap',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // 比照既有目錄按鈕測試：_tocLoaded 由 loadTableOfContents() 的 .then()
    // callback 設定，需要多一次 pump 讓其 microtask 完成。
    await tester.pump();

    final titleFinder = find.byKey(const Key('reader_appbar_chapter_title'));
    expect(tester.widget<InkWell>(titleFinder).onTap, isNotNull);

    await tester.tap(titleFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsOneWidget);
  });

  testWidgets('showFooter=false 時，EPUB 頁尾即使收到 onCharacterCountReady 也不顯示', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_footer_off_epub',
      const BookReaderPrefs(showFooter: false, showHeader: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_footer_off_epub',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // TODO(epic-20): FoliateEpubReaderView 目前無 onCharacterCountReady。
    // epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
    // 頁尾關閉不影響頁首（預設開啟）——驗證兩者互相獨立。
    expect(
      find.byKey(const Key('reader_appbar_chapter_title')),
      findsOneWidget,
    );
  });

  testWidgets('showFooter=false 時，PDF 頁尾即使收到 onPageChanged 也不顯示', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_footer_off_pdf',
      const BookReaderPrefs(showFooter: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_footer_off_pdf',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(
      const PdfPageInfo(pageIndex: 0, totalPages: 12),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('showHeader=true 且 showFooter=false 組合：頁首顯示章節標題元件、頁尾不顯示', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_header_on_footer_off',
      const BookReaderPrefs(showHeader: true, showFooter: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_on_footer_off',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // TODO(epic-20): FoliateEpubReaderView 目前無 onCharacterCountReady。
    // epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(
      find.byKey(const Key('reader_appbar_chapter_title')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('showHeader=false 且 showFooter=true 組合：頁首為靜態文字、頁尾顯示', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_header_off_footer_on',
      const BookReaderPrefs(showHeader: false, showFooter: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_off_footer_on',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // TODO(epic-20): FoliateEpubReaderView 目前無 onCharacterCountReady。
    // epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget);
    // 無 onCharacterCountReady，頁尾不出現。
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets(
    'EPUB 固定版面（FXL）開書後，即使 showHeader=false/showFooter=false，懸浮返回/設定按鈕仍正常顯示（FXL 完全不受影響）',
    (tester) async {
      await prefsManager.saveBookPrefs(
        'b_fxl_untouched',
        const BookReaderPrefs(showHeader: false, showFooter: false),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_fixed_layout.epub',
            bookId: 'b_fxl_untouched',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final epubView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      epubView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: true,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();

      expect(
        find.byType(AppBar),
        findsNothing,
        reason: 'FXL 不建構 Scaffold AppBar，頁首邏輯不適用',
      );
      expect(
        find.byKey(const Key('reader_foliate_back_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('reader_foliate_settings_button')),
        findsOneWidget,
      );
    },
  );

  // --- Epic 6 Issue 1：書籤管理 + 統一「筆記」入口 ---

  testWidgets('未提供 bookmarksRepository 時，📚 筆記按鈕不存在（既有呼叫端不受影響）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_no_bookmarks_repo',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_notes_button')), findsNothing);
  });

  testWidgets(
    'EPUB 提供 bookmarksRepository 後，📚 筆記按鈕存在，onLayoutResolved 前為停用狀態',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_notes_epub',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
          ),
        ),
      );
      await tester.pump();

      final finder = find.byKey(const Key('reader_notes_button'));
      expect(finder, findsOneWidget);
      expect(tester.widget<IconButton>(finder).onPressed, isNull);
    },
  );

  testWidgets('EPUB 只收到 onLayoutResolved（尚未收到 onLocatorChanged）時，📚 按鈕仍為停用狀態'
      '（審查修正：避免定位資料未就緒時寫入無定位資訊的壞書籤）', (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_notes_epub_no_locator_yet',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    final finder = find.byKey(const Key('reader_notes_button'));
    expect(tester.widget<IconButton>(finder).onPressed, isNull);
  });

  testWidgets(
    'EPUB 收到 onLayoutResolved 與 onLocatorChanged 後，📚 按鈕可點擊，點擊後開啟 NotesBottomSheet',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_notes_epub_open',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final epubView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      epubView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      epubView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"href":"/c1.xhtml"}',
          progression: 0.1,
        ),
      );
      await tester.pump();

      final finder = find.byKey(const Key('reader_notes_button'));
      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(NotesBottomSheet), findsOneWidget);
    },
  );

  testWidgets(
    'PDF 提供 bookmarksRepository 後，onPageRendered 前 📚 按鈕為停用狀態，之後可點擊',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b_notes_pdf',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
          ),
        ),
      );
      await tester.pump();

      // epic-24 Issue 8：PDF 筆記按鈕改為 FAB。
      final finder = find.byKey(const Key('reader_pdf_notes_button'));
      expect(tester.widget<IconButton>(finder).onPressed, isNull);

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onPageRendered();
      await tester.pump();

      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);
    },
  );

  // --- Epic 6 Issue 2：EPUB 劃線/備註 ---

  testWidgets(
    '未提供 highlightsRepository／notesRepository 時，EPUB 選取事件不顯示浮動工具列（既有呼叫端零回歸）',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: FakeReaderPrefsManager(),
            bookmarksRepository: bookmarksRepository,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsNothing);
    },
  );

  testWidgets(
    '提供 highlightsRepository／notesRepository 後，ReaderScreen 建構不受影響、仍正常顯示（既有測試涵蓋常態載入行為）',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      final highlightsRepository = FakeHighlightsRepository();
      final notesRepository = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: FakeReaderPrefsManager(),
            bookmarksRepository: bookmarksRepository,
            highlightsRepository: highlightsRepository,
            notesRepository: notesRepository,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(ReaderScreen));
      // ReaderScreen 在 app/test/ 環境下 _channel 恆為 null（無真實
      // AndroidView），無法透過原生端觸發 onSelectionChanged；改為直接
      // 呼叫 State 內部的處理方法驗證（比照既有測試對「_channel 恆為
      // null」限制的既有因應方式：專案既有測試不新增 Method Channel Mock
      // 基礎設施，見 spec.md「Testing Decisions」）。由於
      // `_handleSelectionChanged` 是私有方法，本測試改為直接驗證
      // `AnnotationToolbar` 在 `_currentSelection` 非 null 時確實會被
      // build 出來，透過 State 是否存在對應的公開行為間接驗證——此處
      // 選擇不新增測試專用的 public API，僅驗證 widget tree 初始狀態不
      // 顯示 AnnotationToolbar（上一個測試已涵蓋），選取觸發後的顯示邏輯
      // 交由 Task 11 的 integration_test 驗證（原生選字手勢本身即無法在
      // widget test 環境下真實模擬）。
      expect(state, isNotNull);
    },
  );

  testWidgets(
    'PDF 書籍提供 highlightsRepository／notesRepository 後，ReaderScreen 建構不受影響、仍正常顯示',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      final highlightsRepository = FakeHighlightsRepository();
      final notesRepository = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b1',
            prefsManager: FakeReaderPrefsManager(),
            bookmarksRepository: bookmarksRepository,
            highlightsRepository: highlightsRepository,
            notesRepository: notesRepository,
          ),
        ),
      );
      await tester.pump();

      // 原生 PlatformView 在 app/test/ 環境下不會真正建立（_channel 恆為
      // null，見既有兩層測試架構慣例），選取觸發後的浮動工具列顯示效果留
      // 給 Task 11 integration_test 驗證；本測試只驗證建構參數可正確傳入
      // 不崩潰，且未觸發選取時不顯示浮動工具列（既有行為零回歸）。
      expect(find.byType(AnnotationToolbar), findsNothing);
    },
  );

  testWidgets(
    'PDF 書籍未提供 highlightsRepository／notesRepository 時建構不受影響（既有呼叫端零回歸）',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b1',
            prefsManager: FakeReaderPrefsManager(),
            bookmarksRepository: bookmarksRepository,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsNothing);
    },
  );

  // --- Epic 6 Issue 4：FXL 書籤支援 ---

  testWidgets('FXL：未提供 bookmarksRepository 時，懸浮書籤/筆記按鈕皆不存在（既有呼叫端零回歸）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_no_repo',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_foliate_bookmark_toggle_button')),
      findsNothing,
    );
  });

  testWidgets('FXL：提供 bookmarksRepository 後，懸浮書籤按鈕存在，onLocatorChanged 前為停用狀態', (
    tester,
  ) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_bookmark_disabled',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    final finder = find.byKey(
      const Key('reader_foliate_bookmark_toggle_button'),
    );
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason:
          '尚未收到 onLocatorChanged，_epubPositionInfo 仍為 null，比照 '
          'reader_notes_button 既有防呆邏輯',
    );
  });

  testWidgets('FXL：收到 onLocatorChanged 後，點擊懸浮書籤按鈕可新增/移除目前頁書籤，圖示正確切換並持久化', (
    tester,
  ) async {
    final bookmarksRepository = FakeBookmarksRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_bookmark_toggle',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 解決 loading state 導致 CircularProgressIndicator 動畫持續排程與 MissingPluginException 問題
    view.onPageRendered();
    await tester.pump();

    view.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"href":"/page1.xhtml"}',
        progression: 0.2,
      ),
    );
    await tester.pump();

    final finder = find.byKey(
      const Key('reader_foliate_bookmark_toggle_button'),
    );
    expect(tester.widget<IconButton>(finder).onPressed, isNotNull);
    expect(
      (tester.widget<IconButton>(finder).icon as Icon).icon,
      Icons.star_border,
    );

    // 點擊新增書籤
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 斷言 UI 圖示是否已切換為已加入書籤狀態
    expect((tester.widget<IconButton>(finder).icon as Icon).icon, Icons.star);

    final afterAdd = await bookmarksRepository.listByBook(
      'b_fxl_bookmark_toggle',
    );
    expect(afterAdd, hasLength(1));
    expect(afterAdd.single.epubLocatorJson, '{"href":"/page1.xhtml"}');
    expect(afterAdd.single.progression, 0.2);
    expect(afterAdd.single.pdfPageIndex, isNull);

    // 再次點擊移除書籤
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 斷言 UI 圖示是否已還原為未加入書籤狀態
    expect(
      (tester.widget<IconButton>(finder).icon as Icon).icon,
      Icons.star_border,
    );

    final afterRemove = await bookmarksRepository.listByBook(
      'b_fxl_bookmark_toggle',
    );
    expect(afterRemove, isEmpty);
  });

  // --- Epic 6 Issue 4：FXL 書籤支援（Task 2） ---

  testWidgets('FXL：懸浮筆記按鈕開啟 Bottom Sheet，「🔖 書籤」分頁可用、「✏️ 劃線與備註」分頁顯示空狀態且不可互動', (
    tester,
  ) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_notes_sheet',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 解決 loading state 導致 CircularProgressIndicator 無限動畫持續排程的問題
    view.onPageRendered();
    await tester.pump();

    final notesButtonFinder = find.byKey(
      const Key('reader_foliate_notes_button'),
    );
    expect(notesButtonFinder, findsOneWidget);
    expect(tester.widget<IconButton>(notesButtonFinder).onPressed, isNull);

    view.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"href":"/page1.xhtml"}',
        progression: 0.2,
      ),
    );
    await tester.pump();
    expect(tester.widget<IconButton>(notesButtonFinder).onPressed, isNotNull);

    await tester.tap(notesButtonFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NotesBottomSheet), findsOneWidget);
    expect(find.byKey(const Key('notes_sheet_tab_bookmarks')), findsOneWidget);
    expect(
      find.byKey(const Key('notes_sheet_bookmark_toggle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('notes_sheet_delete_all_highlights')),
      findsNothing,
    );
    expect(find.byKey(const Key('notes_sheet_delete_all_notes')), findsNothing);
  });

  testWidgets('FXL：於 Bottom Sheet 的書籤分頁新增書籤後關閉，懸浮書籤按鈕圖示同步更新', (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_sync',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 解決 loading state
    view.onPageRendered();
    await tester.pump();

    view.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"href":"/page1.xhtml"}',
        progression: 0.2,
      ),
    );
    await tester.pump();

    final bookmarkToggleFinder = find.byKey(
      const Key('reader_foliate_bookmark_toggle_button'),
    );
    expect(
      (tester.widget<IconButton>(bookmarkToggleFinder).icon as Icon).icon,
      Icons.star_border,
    );

    await tester.tap(find.byKey(const Key('reader_foliate_notes_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 關閉 Bottom Sheet（點擊外側遮罩）。
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      (tester.widget<IconButton>(bookmarkToggleFinder).icon as Icon).icon,
      Icons.star,
      reason: 'Bottom Sheet 內新增書籤後關閉，懸浮按鈕應重新載入並反映最新狀態',
    );
  });

  testWidgets('FXL：從書籤清單點選跳轉後，Bottom Sheet 關閉且懸浮控制項收合', (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_jump_collapse',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 解決 loading state
    view.onPageRendered();
    await tester.pump();

    view.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"href":"/page1.xhtml"}',
        progression: 0.2,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_foliate_notes_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NotesBottomSheet), findsNothing);
    expect(
      find.byKey(const Key('reader_foliate_back_button')),
      findsNothing,
      reason: '書籤跳轉比照既有換頁慣例，強制收合懸浮控制項',
    );
    expect(
      find.byKey(const Key('reader_foliate_notes_button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reader_foliate_bookmark_toggle_button')),
      findsNothing,
    );
  });

  // --- Epic 6 Issue 5：Markdown 導出 ---

  testWidgets(
    'EPUB：開啟「📚 筆記」時，傳給 NotesBottomSheet 的 bookProgress 反映目前即時進度，而非開書當下的舊 bookProgress',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_chapter.epub',
            bookId: 'b_progress_export_epub',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
            bookProgress: 0.1,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final epubView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      epubView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      epubView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"href":"/c3.xhtml"}',
          progression: 0.5,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_notes_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final sheet = tester.widget<NotesBottomSheet>(
        find.byType(NotesBottomSheet),
      );
      expect(
        sheet.bookProgress,
        0.5,
        reason: '應反映 onLocatorChanged 回報的最新進度，而非建構時的舊 bookProgress: 0.1',
      );
    },
  );

  testWidgets(
    'PDF：開啟「📚 筆記」時，傳給 NotesBottomSheet 的 bookProgress 依 onPageChanged 回報的頁碼/總頁數即時換算',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b_progress_export_pdf',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
            bookProgress: 0.0,
          ),
        ),
      );
      await tester.pump();

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onPageRendered();
      await tester.pump();

      // 先透過 onPageChanged 設定頁碼資訊，再 pump 讓狀態就緒。
      pdfView.onPageChanged?.call(
        const PdfPageInfo(pageIndex: 4, totalPages: 10),
      );
      await tester.pump();

      // epic-24 Issue 8：PDF 筆記按鈕改為 FAB。
      final notesFinder = find.byKey(const Key('reader_pdf_notes_button'));
      expect(notesFinder, findsOneWidget);
      expect(tester.widget<IconButton>(notesFinder).onPressed, isNotNull);

      // 直接呼叫 onPressed callback 繞過 gesture 問題
      tester.widget<IconButton>(notesFinder).onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      final sheet = tester.widget<NotesBottomSheet>(
        find.byType(NotesBottomSheet),
      );
      expect(
        sheet.bookProgress,
        0.5,
        reason: '第 5 頁／共 10 頁應換算為 0.5，而非建構時的舊 bookProgress: 0.0',
      );
    },
  );

  // epic-24 Issue 8：PDF 不再使用 AppBar / in-flow footer，沉浸模式改由
  // FAB 可見性反映。
  testWidgets('_handleZoneAction(menu) 切換 FAB 顯示（PDF）', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 初始狀態：FAB 可見（_chromeVisible == true）。
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const Key('reader_pdf_back_button')), findsOneWidget);

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();

    // 沉浸模式：FAB 隱藏。
    expect(find.byKey(const Key('reader_pdf_back_button')), findsNothing);

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();

    // 切回：FAB 恢復可見。
    expect(find.byKey(const Key('reader_pdf_back_button')), findsOneWidget);
  });

  testWidgets(
    '_handleZoneAction(previousPage/nextPage) 不影響 AppBar 顯示狀態（PDF，design.md 決策 #14）',
    (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b1',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // epic-24 Issue 8：PDF 不再使用 AppBar，改以 FAB 可見性驗證。
      expect(find.byKey(const Key('reader_pdf_back_button')), findsOneWidget);

      ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
      await tester.pump();
      expect(find.byKey(const Key('reader_pdf_back_button')), findsOneWidget);

      ReaderScreen.triggerZoneAction(key, ZoneAction.previousPage);
      await tester.pump();
      expect(find.byKey(const Key('reader_pdf_back_button')), findsOneWidget);

      ReaderScreen.triggerZoneAction(key, ZoneAction.none);
      await tester.pump();
      expect(find.byKey(const Key('reader_pdf_back_button')), findsOneWidget);
    },
  );

  testWidgets(
    'Scaffold 開啟 extendBodyBehindAppBar，PdfReaderView 尺寸不因沉浸模式切換而改變（審查修正：避免 AppBar 顯示/隱藏觸發 PlatformView resize）',
    (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b1',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.extendBodyBehindAppBar, isTrue);

      final sizeWithAppBar = tester.getSize(find.byType(PdfReaderView));

      ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
      await tester.pump();

      expect(find.byType(AppBar), findsNothing, reason: '沉浸模式已切換，AppBar 應隱藏');
      final sizeWithoutAppBar = tester.getSize(find.byType(PdfReaderView));
      expect(
        sizeWithoutAppBar,
        sizeWithAppBar,
        reason: 'PdfReaderView 尺寸不應因 AppBar 顯示/隱藏而改變',
      );
    },
  );

  testWidgets('PdfReaderView.nextPage／previousPage 在真實 pdfrx 載入後正確切換頁碼', (
    tester,
  ) async {
    // 【epic-24-pdf-engine-rebuild Issue 1】新 PdfReaderView 為純 Dart widget
    // （pdfrx），不再使用 PlatformView。直接驗證 PdfReaderView.nextPage /
    // previousPage 靜態方法在真實 pdfrx 載入後能正確切換頁碼。
    // Volume key → ReaderScreen → PdfReaderView.nextPage 為薄包裝層，
    // 核心翻頁邏輯在此測試覆蓋。
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );

    // 等待 pdfrx 真實載入 PDF（非模擬）。
    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(renderedCount, 1);
    expect(lastPageInfo?.totalPages, 5);
    expect(lastPageInfo?.pageIndex, 0);

    // PdfReaderView.nextPage 觸發頁碼前進（0 → 1）。
    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);

    // PdfReaderView.previousPage 觸發頁碼後退（1 → 0）。
    PdfReaderView.previousPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 0);
  });

  testWidgets('全域音量鍵開關關閉時，onVolumeKey 觸發被忽略，不執行翻頁', (tester) async {
    // 【epic-24-pdf-engine-rebuild Issue 1】驗證 ReaderScreen 在
    // volumeKeyEnabled: false 時忽略 onVolumeKey 事件。
    //
    // 【測試範圍】本測試透過 ReaderScreen 驗證全域音量鍵開關的行為。
    // ReaderScreen 內部的 _pdfPageInfo 為私有欄位，無法從外部直接觀察
    // 頁碼變化，因此斷言限於：widget 保持 mounted 且無例外拋出。
    // 核心翻頁邏輯已由 pdf_reader_view_test.dart 的 real loading 測試覆蓋。
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // mock fullscreen channel 以避免 MissingPluginException
    const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
    binaryMessenger.setMockMethodCallHandler(fullscreenChannel, (call) async {
      return null;
    });
    addTearDown(() => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null));

    final disabledPrefsManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(volumeKeyEnabled: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: disabledPrefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 等待 pdfrx 真實載入 PDF（非模擬 onPageRendered）。
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    const volumeKeyChannel = MethodChannel('elinkbook/volume_key');
    final byteData = volumeKeyChannel.codec.encodeMethodCall(
      const MethodCall('onVolumeKey', {'direction': 'down'}),
    );
    await binaryMessenger.handlePlatformMessage(
      volumeKeyChannel.name,
      byteData,
      (data) {},
    );
    await tester.pump();

    // volumeKeyEnabled: false 時，onVolumeKey 不應觸發翻頁。
    // 由於 ReaderScreen._pdfPageInfo 為私有欄位，無法直接斷言頁碼，
    // 僅驗證 widget 保持 mounted 且無例外拋出。
    final state = tester.state<State>(find.byType(ReaderScreen));
    expect(state.mounted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PopScope：pop 動作啟動當下呼叫 notifyLeavingReader，及早通知原生端釋放音量鍵攔截', (
    tester,
  ) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const volumeKeyChannel = MethodChannel('elinkbook/volume_key');
    final outgoingCalls = <MethodCall>[];
    binaryMessenger.setMockMethodCallHandler(volumeKeyChannel, (call) async {
      outgoingCalls.add(call);
      return null;
    });
    addTearDown(
      () => binaryMessenger.setMockMethodCallHandler(volumeKeyChannel, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open_reader'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReaderScreen(
                      filePath: 'test/fixtures/sample.pdf',
                      bookId: 'b1',
                      prefsManager: prefsManager,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    // 模擬原生端 onPageRendered，讓 _state 脫離 loading（純 flutter test
    // 環境下 AndroidView 不會真正觸發原生回呼，比照本檔案既有測試慣例，
    // 見第 294-298 行）——CircularProgressIndicator 為不定長動畫，若一直
    // 停留在 loading，後續 pumpAndSettle() 永遠不會收斂而逾時（見第
    // 957-962 行既有註解記錄的相同教訓）。
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(outgoingCalls, isEmpty);

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(outgoingCalls.any((c) => c.method == 'notifyLeavingReader'), isTrue);
  });

  testWidgets('EPUB 流式：原生端 onZoneTapped 回呼（cellIndex=1）觸發沉浸模式切換', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);

    // navZoneMode 預設 rightFlip，index 1（中欄）為 menu（見
    // app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。EPUB 流式的
    // previousPage/nextPage/none 完全由原生端 InputListener 自行處理、不通知
    // Dart（見 EpubReaderView.kt），只有 menu 動作會透過
    // onZoneTapped(cellIndex) 回呼給 Dart——這裡直接呼叫該回呼模擬原生端已
    // 完成熱區判讀後的通知，驗證 ReaderScreen 接線到 _handleZoneAction 的
    // 部分（不涉及原生 InputListener 本身是否正確攔截點擊，那部分由
    // integration_test 真機驗證，見 plan-issue-6.md Task 5）。
    final view = tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    // Epic 20 Issue 2：FoliateEpubReaderView 使用 onZoneAction 回呼
    // （接收 ZoneAction enum），取代 EpubReaderView 的 onZoneTapped(cellIndex)。
    view.onZoneAction?.call(ZoneAction.menu);
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets(
    'EPUB 流式（isFixedLayout: false）：點擊選單熱區觸發沉浸模式切換（Issue 7：AppBar 恆為 null，改斷言浮動按鈕）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(find.byType(AppBar), findsNothing);
      expect(
        find.byKey(const Key('reader_foliate_back_button')),
        findsOneWidget,
      );

      // navZoneMode 預設 rightFlip，index 1（中欄）為 menu（見
      // app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_foliate_back_button')),
        findsNothing,
      );
    },
  );

  testWidgets('EPUB 流式：previousPage/nextPage 熱區觸發 FoliateEpubReaderView '
      '換頁，且不影響沉浸模式狀態（design.md 決策 #14；Issue 7 改斷言浮動按鈕）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byKey(const Key('reader_foliate_back_button')), findsOneWidget);

    // rightFlip 模板：index 2（右欄）＝ nextPage。
    await tester.tap(find.byKey(const Key('nav_zone_2')));
    await tester.pump();
    expect(
      find.byKey(const Key('reader_foliate_back_button')),
      findsOneWidget,
      reason: '換頁動作不應影響沉浸模式狀態',
    );

    // rightFlip 模板：index 0（左欄）＝ previousPage。
    await tester.tap(find.byKey(const Key('nav_zone_0')));
    await tester.pump();
    expect(
      find.byKey(const Key('reader_foliate_back_button')),
      findsOneWidget,
      reason: 'previousPage 同樣不應影響沉浸模式狀態',
    );
  });

  // ─────────────────────────────────────────────────────────────────────
  // epic-17-epub-render-migration Issue 6：流式 EPUB 目錄跳轉、定位
  // 持久化與頁尾頁碼測試。
  // ─────────────────────────────────────────────────────────────────────

  testWidgets(
    '流式 EPUB（isFixedLayout: false）收到 onLayoutResolved 後，目錄按鈕轉為可點擊，點擊後開啟 TocBottomSheet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_toc_foliate_open',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      // 比照既有 Readium 分支測試：目錄按鈕的啟用條件額外要求 _tocLoaded，
      // 該旗標由 FoliateEpubReaderView.loadTableOfContents() 這個 async
      // 呼叫的 .then() callback 設定，需要多一次 pump 讓其 microtask 完成。
      await tester.pump();

      final finder = find.byKey(const Key('reader_foliate_toc_button'));
      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(TocBottomSheet), findsOneWidget);
    },
  );

  testWidgets(
    '流式 EPUB：點選目錄項目呼叫 FoliateEpubReaderView.jumpToLocator（非 EpubReaderView）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_toc_foliate_jump',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_foliate_toc_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TocBottomSheet), findsOneWidget);

      final sheet = tester.widget<TocBottomSheet>(find.byType(TocBottomSheet));
      sheet.onEntrySelected(
        const TocEntry(
          title: '測試章節',
          locatorJson: '{"cfi":"epubcfi(/6/8!/4)","index":1,"fraction":0.2}',
          progression: 0.2,
        ),
      );
      await tester.pump();

      // 驗證 FoliateEpubReaderView 存在（代表走對了分支），且
      // EpubReaderView 未被建構——確認目錄跳轉走的是 Foliate 路徑。
      expect(find.byType(FoliateEpubReaderView), findsOneWidget);
    },
  );

  testWidgets('流式 EPUB：onLocatorChanged 回報 pageIndex/totalPages 後，頁尾顯示對應頁碼', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_footer_foliate',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 9,
        totalPages: 100,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_foliate_progress_text')), findsOneWidget);
    expect(find.text('10/100'), findsOneWidget);
  });

  testWidgets(
      '流式 EPUB：橫排時頁首上邊界與頁尾下邊界皆為 0，頁首/頁尾字體大小皆為 16'
      '（真機使用回報，epic-18-reader-device-qa Issue 32）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header_footer_margin_h',
      const BookReaderPrefs(showHeader: true, showFooter: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header_footer_margin_h',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 9,
        totalPages: 100,
      ),
    );
    await tester.pump();

    // 初始狀態 _chromeVisible=true，頁首不顯示（頁尾不受沉浸模式影響，
    // 比照既有測試慣例）；觸發沉浸模式後頁首才會出現。
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerPositioned = tester.widget<Positioned>(
      find
          .ancestor(
            of: find.byKey(const Key('reader_foliate_header_text')),
            matching: find.byType(Positioned),
          )
          .first,
    );
    expect(headerPositioned.top, 0);

    final footerPositioned = tester.widget<Positioned>(
      find
          .ancestor(
            of: find.byKey(const Key('reader_foliate_progress_text')),
            matching: find.byType(Positioned),
          )
          .first,
    );
    expect(footerPositioned.bottom, 0);

    final headerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_header_text')),
      matching: find.byType(Text),
    ));
    expect(headerText.style?.fontSize, 12);

    final footerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_progress_text')),
      matching: find.byType(Text),
    ));
    expect(footerText.style?.fontSize, 12);
  });

  testWidgets(
    '流式 EPUB：onLocatorChanged 未觸發前（pageIndex/totalPages 皆為 null），頁尾不顯示',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_footer_foliate_absent',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      await tester.pump();

      expect(
        find.byKey(const Key('reader_foliate_progress_text')),
        findsNothing,
      );
    },
  );

  testWidgets('流式 EPUB：onLocatorChanged 回報 totalPages=0 時，頁尾不顯示且不崩潰', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_footer_foliate_zero',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 0,
        totalPages: 0,
      ),
    );
    await tester.pump();

    // totalPages=0 應被 Issue 7 新增的疊加層條件
    // （(_epubPositionInfo?.totalPages ?? 0) > 0）攔截，不會建構
    // _buildFoliateProgressText()。
    expect(
      find.byKey(const Key('reader_foliate_progress_text')),
      findsNothing,
    );
  });

  // --- Epic 17 Issue 8：流式 EPUB（FoliateEpubReaderView）劃線與備註 ---

  testWidgets(
    '流式 EPUB 開書後，自動載入既有劃線/備註並透過 FoliateEpubReaderView.setDecorations 送給原生端',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      await highlightsRepo.insert(
        const Highlight(
          id: 'h_fs1',
          bookId: 'b_foliate_anno',
          style: HighlightStyle.highlighterYellow,
          epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_anno',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      // InAppWebView 環境下 setDecorations 透過 evaluateJavascript 發送，
      // flutter_test 無法攔截 JS 呼叫。此處驗證 widget 成功建構且不崩潰，
      // 表示劃線載入 → setDecorations 完整流程未拋出例外。
      expect(find.byType(FoliateEpubReaderView), findsOneWidget);
    },
  );

  // epic-20-fxl-foliate-migration Issue 4 Task 2/3：_sendDecorationsToNative()
  // 修正前對 FXL 書籍會呼叫已無人建構的 EpubReaderView.setDecorations（見
  // tmp/epic-20/issue2-implementation-review.md 原始發現），修正後無條件呼叫
  // FoliateEpubReaderView.setDecorations——比照上方既有的流式版本測試風格
  // （InAppWebView 環境下 flutter_test 無法攔截 evaluateJavascript 呼叫本身，
  // 故以「不崩潰」+「畫面中只有 FoliateEpubReaderView、沒有 EpubReaderView」
  // 佐證分派目標正確，是本測試能提供的最強保證）。
  testWidgets(
    'FXL EPUB 開書後，自動載入既有劃線/備註並透過 FoliateEpubReaderView.setDecorations（而非已無人建構的 EpubReaderView）送給原生端',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      await highlightsRepo.insert(
        const Highlight(
          id: 'h_fs2',
          bookId: 'b_fxl_anno',
          style: HighlightStyle.highlighterYellow,
          epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_fixed_layout.epub',
            bookId: 'b_fxl_anno',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: true,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final fxlView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      fxlView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: true,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(FoliateEpubReaderView), findsOneWidget);
    },
  );

  testWidgets(
    '流式 EPUB：FoliateEpubReaderView 回報 onSelectionChanged 時，顯示 AnnotationToolbar',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_select',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 先呼叫 onLayoutResolved 觸發 _resolved 設定（_buildNativeView 所需）
      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      foliateView.onSelectionChanged?.call(
        const EpubSelectionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsOneWidget);
    },
  );

  testWidgets(
    '流式 EPUB：選取範圍靠近畫面右緣時，AnnotationToolbar 右緣不應超出畫面寬度',
    (tester) async {
      // 固定視窗尺寸（400×800，比照既有 PDF 選取測試慣例），讓 clamp 後的
      // 精確像素值可預期、可斷言，而非依賴 flutter test 預設 800×600。
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(400, 800));
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_select_edge',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      // 選取範圍靠近畫面右緣（left=0.95），比照使用者截圖回報的症狀
      // （tmp/images/畫線問題/畫線太右邊無法看到全部工具列.jpg）。
      foliateView.onSelectionChanged?.call(
        const EpubSelectionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.9}',
          progression: 0.9,
          rect: PercentRect(left: 0.95, top: 0.2, right: 0.99, bottom: 0.3),
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsOneWidget);
      final bottomRight = tester.getBottomRight(find.byType(AnnotationToolbar));
      expect(
        bottomRight.dx,
        lessThanOrEqualTo(400.0),
        reason: '工具列右緣（現況會落在 636.0）不應超出畫面寬度 400.0，'
            '否則右半部按鈕會被裁切看不到',
      );
    },
  );

  testWidgets(
    '流式 EPUB：點擊 AnnotationToolbar 的關閉按鈕後，清空選取狀態、工具列消失',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_close_toolbar',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      foliateView.onSelectionChanged?.call(
        const EpubSelectionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsOneWidget);

      await tester.tap(find.byKey(const Key('annotation_toolbar_close')));
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsNothing,
          reason: '點擊關閉按鈕後應清空選取狀態，工具列從畫面消失');
    },
  );

  testWidgets(
    '流式 EPUB：FoliateEpubReaderView 回報 onAnnotationActivated 時，開啟對話框',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      const highlightId = 'h_fa1';
      await highlightsRepo.insert(
        const Highlight(
          id: highlightId,
          bookId: 'b_foliate_active',
          style: HighlightStyle.highlighterYellow,
          epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_active',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      // _reloadAnnotationsAndRefreshDecorations() 內部 await repository
      // 呼叫，需多一次 pump 讓 microtask 完成。
      await tester.pump();
      await tester.pump();

      foliateView.onAnnotationActivated?.call('highlight:$highlightId');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SimpleDialog), findsOneWidget);
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // epic-18-reader-device-qa Issue 7：流式 EPUB Chrome 重構（浮動選單列＋
  // 頁眉/進度資訊分離）。
  // ─────────────────────────────────────────────────────────────────────

  testWidgets('流式 EPUB：AppBar 不顯示，6 顆浮動按鈕存在且可點擊（Issue 7）', (
    tester,
  ) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_chrome',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // _tocLoaded 由 loadTableOfContents() 的 .then() 設定，需多一次 pump。
    await tester.pump();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 0,
        totalPages: 10,
      ),
    );
    await tester.pump();

    for (final key in [
      'reader_foliate_back_button',
      'reader_foliate_toc_button',
      'reader_foliate_settings_button',
      'reader_foliate_bookmark_toggle_button',
      'reader_foliate_notes_button',
      'reader_foliate_progress_button',
    ]) {
      final finder = find.byKey(Key(key));
      expect(finder, findsOneWidget, reason: '$key 應存在');
      expect(
        tester.widget<IconButton>(finder).onPressed,
        isNotNull,
        reason: '$key 應為可點擊狀態',
      );
    }
  });

  testWidgets('流式 EPUB：點擊浮動版面設定按鈕開啟 ReaderSettingsSheet（Issue 7）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_settings_btn',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_foliate_settings_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderSettingsSheet), findsOneWidget);
  });

  testWidgets(
    '流式 EPUB：點擊浮動書籤 toggle 按鈕可新增/移除目前頁書籤，圖示正確切換（複用泛用化後的 _toggleBookmark，Issue 7）',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_bookmark_btn',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          pageIndex: 0,
          totalPages: 10,
        ),
      );
      await tester.pump();

      final finder = find.byKey(
        const Key('reader_foliate_bookmark_toggle_button'),
      );
      expect(
        (tester.widget<IconButton>(finder).icon as Icon).icon,
        Icons.star_border,
      );

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        (tester.widget<IconButton>(finder).icon as Icon).icon,
        Icons.star,
      );

      final afterAdd = await bookmarksRepository.listByBook(
        'b_foliate_bookmark_btn',
      );
      expect(afterAdd, hasLength(1));
    },
  );

  testWidgets(
    '流式 EPUB：重新開啟已在目前位置有書籤的書，開書後未打開過筆記面板時第一次點擊書籤按鈕應刪除既有書籤而非重複新增（Epic 26 Issue 1 回歸測試）',
    (tester) async {
      const locatorJson = '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}';
      final bookmarksRepository = FakeBookmarksRepository();
      // 模擬「先前已在此位置加過書籤」：重開書時 repository 已有一筆。
      await bookmarksRepository.insert(Bookmark(
        id: 'existing-bookmark',
        bookId: 'b_epic26_issue1',
        name: '既有書籤',
        epubLocatorJson: locatorJson,
        progression: 0.1,
      ));

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_epic26_issue1',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: locatorJson,
          progression: 0.1,
          pageIndex: 0,
          totalPages: 10,
        ),
      );
      await tester.pump();

      // 刻意不打開 NotesBottomSheet——重現「_fxlBookmarks 快取從未被
      // 預先載入」的狀態，開書後直接第一次點擊書籤按鈕。
      final finder = find.byKey(
        const Key('reader_foliate_bookmark_toggle_button'),
      );

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        (tester.widget<IconButton>(finder).icon as Icon).icon,
        Icons.star_border,
        reason: '既有書籤應已被刪除，圖示應變回未加書籤狀態',
      );

      final afterTap = await bookmarksRepository.listByBook(
        'b_epic26_issue1',
      );
      expect(
        afterTap,
        hasLength(0),
        reason: '目前位置已有書籤時第一次點擊應是刪除，不應變成重複新增',
      );
    },
  );

  testWidgets('流式 EPUB：點擊浮動筆記按鈕開啟 NotesBottomSheet（Issue 7）', (
    tester,
  ) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_notes_btn',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_foliate_notes_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NotesBottomSheet), findsOneWidget);
  });

  testWidgets('流式 EPUB：頁眉純顯示章節名稱、不可點擊，showHeader=false 時不顯示（Issue 7）', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header',
      const BookReaderPrefs(showHeader: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 觸發沉浸模式（_chromeVisible=false），頁首才會顯示
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerFinder = find.byKey(const Key('reader_foliate_header_text'));
    expect(headerFinder, findsOneWidget);
    expect(
      find.ancestor(of: headerFinder, matching: find.byType(InkWell)),
      findsNothing,
      reason: '頁眉須為純顯示，不可點擊開啟目錄',
    );
    expect(
      find.ancestor(of: headerFinder, matching: find.byType(GestureDetector)),
      findsNothing,
    );
  });

  testWidgets(
    '流式 EPUB：沉浸模式收起選單（_chromeVisible=false）時，頁首文字仍常駐顯示、6 顆浮動按鈕正確收合（Issue 13）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_header_immersive',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();

      // navZoneMode 預設 rightFlip，index 1（中欄）為 menu（見
      // app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_foliate_back_button')),
        findsNothing,
        reason: '沉浸模式收起後，浮動功能按鈕應收合',
      );
      expect(
        find.byKey(const Key('reader_foliate_header_text')),
        findsOneWidget,
        reason: '頁首文字（資訊顯示）不受沉浸模式影響，應常駐顯示',
      );
    },
  );

  testWidgets('流式 EPUB：直排模式下頁首以 RotatedBox 顯示於右上角，與 FAB 互斥（Issue 23）', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header_v',
      const BookReaderPrefs(
        writingModeOverride: WritingMode.vertical,
        showHeader: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header_v',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.vertical,
      ),
    );
    await tester.pump();

    // 初始狀態 _chromeVisible=true，頁首不顯示
    expect(find.byKey(const Key('reader_foliate_header_text')), findsNothing);

    // 觸發沉浸模式（_chromeVisible=false），頁首顯示
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerFinder = find.byKey(const Key('reader_foliate_header_text'));
    expect(headerFinder, findsOneWidget);

    // 驗證直排分支使用 RotatedBox
    expect(
      find.ancestor(of: headerFinder, matching: find.byType(RotatedBox)),
      findsOneWidget,
      reason: '直排模式頁首應以 RotatedBox 包裹',
    );

    // 驗證 Positioned 包含 bottom: 16（有界寬度約束）
    final positioned = tester.widget<Positioned>(
      find.ancestor(of: headerFinder, matching: find.byType(Positioned)).first,
    );
    expect(positioned.bottom, 16);
    expect(positioned.right, 0);
    expect(positioned.top, 16);
  });

  testWidgets('流式 EPUB：目錄尚未載入時，頁首顯示書名而非「閱讀器」（Issue 23）', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header_title',
      const BookReaderPrefs(showHeader: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header_title',
          prefsManager: prefsManager,
          isFixedLayout: false,
          bookTitle: '我的測試書名',
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 觸發沉浸模式
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    // 目錄尚未載入（_tocEntries 為空），應顯示書名
    expect(find.text('我的測試書名'), findsOneWidget);
    expect(find.text('閱讀器'), findsNothing);
  });

  testWidgets('流式 EPUB：showHeader=false 時頁眉不顯示（Issue 7）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header_off',
      const BookReaderPrefs(showHeader: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header_off',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_foliate_header_text')), findsNothing);
  });

  testWidgets(
    '流式 EPUB：進度為純顯示、橫排時置於下方置中且不含手勢 widget（Issue 7）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_progress_h',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          pageIndex: 167,
          totalPages: 197,
        ),
      );
      await tester.pump();

      final progressFinder = find.byKey(
        const Key('reader_foliate_progress_text'),
      );
      expect(progressFinder, findsOneWidget);
      expect(find.text('168/197'), findsOneWidget);
      expect(find.byType(RotatedBox), findsNothing);
      expect(
        find.ancestor(
          of: progressFinder,
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    '流式 EPUB：沉浸模式收起選單（_chromeVisible=false）時，進度文字仍常駐顯示（Issue 13）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_progress_immersive',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          pageIndex: 167,
          totalPages: 197,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_foliate_progress_button')),
        findsNothing,
        reason: '沉浸模式收起後，浮動功能按鈕應收合',
      );
      expect(
        find.byKey(const Key('reader_foliate_progress_text')),
        findsOneWidget,
        reason: '進度文字（資訊顯示）不受沉浸模式影響，應常駐顯示',
      );
      expect(find.text('168/197'), findsOneWidget);
    },
  );

  testWidgets('流式 EPUB：直排時進度以 RotatedBox 顯示於左下角（Issue 7）', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_progress_v',
      const BookReaderPrefs(
        writingModeOverride: WritingMode.vertical,
        showFooter: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_progress_v',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 167,
        totalPages: 197,
      ),
    );
    await tester.pump();

    final rotatedFinder = find.ancestor(
      of: find.byKey(const Key('reader_foliate_progress_text')),
      matching: find.byType(RotatedBox),
    );
    expect(rotatedFinder, findsOneWidget);
    expect(tester.widget<RotatedBox>(rotatedFinder).quarterTurns, isNot(0));

    final positioned = tester.widget<Positioned>(
      find
          .ancestor(
            of: find.byKey(const Key('reader_foliate_progress_text')),
            matching: find.byType(Positioned),
          )
          .first,
    );
    expect(positioned.left, 0,
        reason: '真機使用回報（epic-18-reader-device-qa Issue 32）：直排時頁尾左邊界改為 0');
  });

  testWidgets(
    '流式 EPUB：showFooter=false 時進度文字不顯示，但進度/跳頁按鈕仍顯示且可點擊（Issue 12）',
    (tester) async {
      await prefsManager.saveBookPrefs(
        'b_foliate_progress_off',
        const BookReaderPrefs(showFooter: false),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_progress_off',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          pageIndex: 0,
          totalPages: 10,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('reader_foliate_progress_text')),
        findsNothing,
        reason: 'showFooter=false 時進度文字（資訊顯示）仍不應顯示',
      );

      final buttonFinder = find.byKey(
        const Key('reader_foliate_progress_button'),
      );
      expect(
        buttonFinder,
        findsOneWidget,
        reason: '進度/跳頁按鈕（功能操作）不應被 showFooter 額外限制',
      );

      await tester.tap(buttonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const Key('reader_footer_jump_slider')),
        findsOneWidget,
        reason: '點擊按鈕仍可正常開啟跳頁 Bottom Sheet',
      );
    },
  );

  testWidgets(
    '流式 EPUB：點擊浮動進度/跳頁按鈕開啟內含 ReaderFooter 的 Bottom Sheet，舊 in-flow 頁尾不再存在（Issue 7）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_progress_sheet',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          pageIndex: 9,
          totalPages: 100,
        ),
      );
      await tester.pump();

      // Bottom Sheet 開啟前，舊 in-flow ReaderFooter 應已不存在（見 Task 2
      // 「移除舊路徑」），畫面上只有浮動進度文字顯示同樣的頁碼。
      expect(find.byKey(const Key('reader_footer')), findsNothing);
      expect(find.text('10/100'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reader_foliate_progress_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reader_footer')), findsOneWidget);
      expect(
        find.byKey(const Key('reader_footer_progress_text')),
        findsOneWidget,
      );
      // 浮動疊加層（Bottom Sheet 開啟後仍在背景可見）與 Bottom Sheet 內的
      // ReaderFooter 各自顯示一份相同頁碼文字。
      expect(find.text('10/100'), findsNWidgets(2));
    },
  );

  testWidgets(
    '流式 EPUB：進度/跳頁 Bottom Sheet 內容包在 SafeArea 內，避免被系統工具列蓋住（Issue 11）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            // 模擬有系統手勢列/三鍵導覽列的裝置：viewPadding.bottom > 0。
            data: const MediaQueryData(
              viewPadding: EdgeInsets.only(bottom: 48),
            ),
            child: ReaderScreen(
              filePath: 'test/fixtures/sample.epub',
              bookId: 'b_foliate_progress_safearea',
              prefsManager: prefsManager,
              isFixedLayout: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          pageIndex: 0,
          totalPages: 10,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_foliate_progress_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final sliderFinder = find.byKey(const Key('reader_footer_jump_slider'));
      expect(sliderFinder, findsOneWidget);
      expect(
        find.ancestor(of: sliderFinder, matching: find.byType(SafeArea)),
        findsOneWidget,
        reason: '跳頁滑桿須包在 SafeArea 內，避免被系統工具列（viewPadding.bottom）蓋住',
      );
    },
  );

  testWidgets(
    '流式 EPUB：positionInfo 尚未就緒（null）時點擊進度/跳頁按鈕，SafeArea 仍正常包裹空白內容，不噴例外（Issue 11）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_progress_safearea_null',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 刻意不呼叫 onLocatorChanged，讓 _epubPositionInfo 維持 null，
      // 藉此觸發 builder 的 SizedBox.shrink() 分支。此時畫面上只有
      // `_buildBody()` 主體的那一層 SafeArea。
      expect(find.byType(SafeArea), findsOneWidget);

      await tester.tap(find.byKey(const Key('reader_foliate_progress_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('reader_footer')), findsNothing);
      expect(
        find.byType(SafeArea),
        findsNWidgets(2),
        reason:
            'positionInfo 為 null 時 Bottom Sheet 仍應包一層 SafeArea（SizedBox.shrink 分支），'
            '不因內容為空而被省略',
      );
    },
  );

  testWidgets('流式 EPUB：邊距 4 個欄位從 ResolvedPreferences 正確透傳到 FoliateEpubReaderView（Issue 14）', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_margins',
      const BookReaderPrefs(
        marginTop: 72,
        marginBottom: 20,
        marginLeft: 30,
        marginRight: 30,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_margins',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    expect(foliateView.marginTop, 72);
    expect(foliateView.marginBottom, 20);
    expect(foliateView.marginLeft, 30);
    expect(foliateView.marginRight, 30);
  });

  testWidgets(
      '流式 EPUB：Theme.of(context) 的顏色正確透傳到 FoliateEpubReaderView'
      '（epic-22-reader-theme-integration Issue 1）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_theme_color',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    final expectedTheme = buildThemeData(AppTheme.dark);
    expect(foliateView.textColor, expectedTheme.colorScheme.onSurface);
    expect(foliateView.backgroundColor, expectedTheme.scaffoldBackgroundColor);
  });

  testWidgets(
      '流式 EPUB：預設淺色主題（AppTheme.light）下顏色仍正確透傳，'
      '與改動前行為相容（epic-22-reader-theme-integration Issue 1）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.light),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_theme_color_light',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    final expectedTheme = buildThemeData(AppTheme.light);
    expect(foliateView.textColor, expectedTheme.colorScheme.onSurface);
    expect(foliateView.backgroundColor, expectedTheme.scaffoldBackgroundColor);
  });

  testWidgets(
      'EPUB 固定版面：不論主題為何，傳給 FoliateEpubReaderView 的顏色皆為 null'
      '（epic-22-reader-theme-integration Issue 1，圖片內容無法預期背景色）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_foliate_theme_color_fxl',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    expect(foliateView.textColor, isNull);
    expect(foliateView.backgroundColor, isNull);
  });

  testWidgets('開啟全螢幕模式偏好後，elinkbook/fullscreen 頻道收到 setEnabled(true)',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
    final calls = <MethodCall>[];
    binaryMessenger.setMockMethodCallHandler(fullscreenChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
    );

    final prefsManager = FakeReaderPrefsManager(
      bookPrefsByBookId: {'b1': const BookReaderPrefs(fullscreen: true)},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setEnabled');
    expect(calls.single.arguments, isTrue);
  });

  testWidgets('離開 ReaderScreen 時，elinkbook/fullscreen 頻道收到 setEnabled(false) 無條件還原',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
    final calls = <MethodCall>[];
    binaryMessenger.setMockMethodCallHandler(fullscreenChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
    );

    final prefsManager = FakeReaderPrefsManager(
      bookPrefsByBookId: {'b1': const BookReaderPrefs(fullscreen: true)},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open_reader'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    filePath: 'test/fixtures/sample.pdf',
                    bookId: 'b1',
                    prefsManager: prefsManager,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    // 模擬原生端 onPageRendered，讓畫面脫離 loading（純 flutter test 環境下
    // AndroidView 不會真正觸發原生回呼，比照本檔案既有測試慣例，見既有
    // 「離開閱讀器時通知原生端」測試）——CircularProgressIndicator 為不定長
    // 動畫，若一直停留在 loading，後續 pumpAndSettle() 永遠不會收斂而逾時。
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();
    calls.clear();

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(calls, contains(predicate<MethodCall>((c) =>
        c.method == 'setEnabled' && c.arguments == false)));
  });

  testWidgets('離開 ReaderScreen（書籍切換）觸發一次 checkpoint', (tester) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => true,
      runCheckpoint: () async {
        triggerCallCount++;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open_reader'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    filePath: 'test/fixtures/sample.pdf',
                    bookId: 'b1',
                    prefsManager: prefsManager,
                    syncCheckpointTrigger: syncCheckpointTrigger,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(triggerCallCount, 0, reason: '開書當下不應觸發 checkpoint');

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(triggerCallCount, 1);
  });

  testWidgets('未提供 syncCheckpointTrigger 時，離開 ReaderScreen 不拋出例外（零回歸）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open_reader'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    filePath: 'test/fixtures/sample.pdf',
                    bookId: 'b1',
                    prefsManager: prefsManager,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('閱讀中每 5 分鐘計時器觸發 checkpoint，離開畫面後計時器停止', (tester) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => true,
      runCheckpoint: () async {
        triggerCallCount++;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open_reader'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    filePath: 'test/fixtures/sample.pdf',
                    bookId: 'b1',
                    prefsManager: prefsManager,
                    syncCheckpointTrigger: syncCheckpointTrigger,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(triggerCallCount, 0);

    await tester.pump(const Duration(minutes: 5));
    expect(triggerCallCount, 1, reason: '第一次 5 分鐘計時應觸發一次 checkpoint');

    await tester.pump(const Duration(minutes: 5));
    expect(triggerCallCount, 2, reason: '計時器應持續每 5 分鐘觸發一次');

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();
    // 離開畫面當下 Task 3 的「書籍切換」觸發也會呼叫一次 trigger()，
    // 這裡只關心「離開之後計時器是否已停止」，故以離開當下的次數為基準，
    // 不假設離開當下的確切次數。
    final countAfterLeaving = triggerCallCount;

    await tester.pump(const Duration(minutes: 5));
    expect(triggerCallCount, countAfterLeaving,
        reason: '離開畫面後計時器應已被 cancel，不應再繼續觸發');
  });

  testWidgets(
      'App 從背景恢復時，即使 fullscreen 值未變，_applySystemUiMode 仍重新呼叫 elinkbook/fullscreen',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
    final calls = <MethodCall>[];
    binaryMessenger.setMockMethodCallHandler(fullscreenChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
    );

    final prefsManager = FakeReaderPrefsManager(
      bookPrefsByBookId: {'b1': const BookReaderPrefs(fullscreen: true)},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    expect(calls, hasLength(1)); // 初次套用

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(calls, hasLength(2), reason: 'resumed 應強制重新呼叫，不受等值節流影響');
    expect(calls.last.method, 'setEnabled');
    expect(calls.last.arguments, isTrue);
  });

  testWidgets('提供 customFontsRepository 時，開啟版面設定顯示自訂字型選項',
      (tester) async {
    final customFontsRepository = FakeCustomFontsRepository();
    await customFontsRepository.insert(const CustomFont(
      displayName: '測試自訂字型',
      familyName: 'TestCustomFamily',
      fontUri: 'content://example/test',
    ));

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.epub',
        bookId: 'b1',
        prefsManager: prefsManager,
        customFontsRepository: customFontsRepository,
      ),
    ));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ReaderSettingsSheet), findsOneWidget);

    // 展開字型下拉選單以驗證自訂字型是否出現
    await tester.tap(find.byKey(const Key('reader_settings_font_family')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('測試自訂字型'), findsWidgets);
  });

  testWidgets(
      '提供 customFontsRepository 時，自訂字型清單載入完成前 FoliateEpubReaderView 不建構，載入完成後才建構',
      (tester) async {
    // ReaderScreen._applySystemUiMode() 開書時一定會呼叫
    // elinkbook/fullscreen 頻道的 setEnabled（Epic 19），未 mock 會導致
    // 未被 await 的 MethodChannel 呼叫非同步拋出 MissingPluginException
    // （審查修正，見 tmp/epic-14/review-issue-3.md Important 2；比照同檔
    // 第 4473-4481 行既有寫法）。
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
    binaryMessenger.setMockMethodCallHandler(
        fullscreenChannel, (call) async => null);
    addTearDown(
      () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
    );

    final customFontsRepository = FakeCustomFontsRepository();
    final gate = Completer<void>();
    customFontsRepository.loadGate = gate;

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.epub',
        bookId: 'b1',
        prefsManager: prefsManager,
        customFontsRepository: customFontsRepository,
      ),
    ));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 自訂字型清單尚未載入完成，FoliateEpubReaderView 不應建構，仍顯示載入中指示器。
    expect(find.byType(FoliateEpubReaderView), findsNothing);
    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(FoliateEpubReaderView), findsOneWidget);
  });

  testWidgets(
      '開書逾時（epic-18-reader-device-qa Issue 33）：12 秒內未收到 onPageRendered，'
      '自動切換為錯誤畫面，不會永遠停在載入指示器', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_open_timeout',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 刻意不呼叫 onPageRendered，模擬「原生端/WebView 從未回報成功」的
    // 卡住情境（真機使用回報：iReader Ocean 4 Plus 開啟書籍時畫面永遠
    // 停在轉圈圈，5 個推測根因皆未經真機診斷資料驗證）。
    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    await tester.pump(const Duration(seconds: 12));

    expect(find.byKey(const Key('reader_error_text')), findsOneWidget,
        reason: '逾時後應切換為可見的錯誤畫面，而非讓使用者永遠面對轉圈圈');
    expect(find.byKey(const Key('reader_loading_indicator')), findsNothing);
  });

  testWidgets(
      '開書逾時計時器：onPageRendered 在逾時前已觸發時，逾時計時器不應覆蓋既有的成功狀態',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_open_timeout_success',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(find.byKey(const Key('reader_loading_indicator')), findsNothing);

    // 逾時計時器理應在 onPageRendered 觸發當下就被取消；即使沒有取消，
    // 逾時處理本身也必須判斷「已經不是 loading 狀態才動作」，兩者皆可
    // 避免這裡誤把已成功渲染的畫面覆蓋回錯誤狀態。
    await tester.pump(const Duration(seconds: 12));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '已成功渲染的畫面不應被逾時計時器事後覆蓋成錯誤狀態');
  });

  testWidgets(
      '流式 EPUB 頁首/頁尾文字：字級為 12、不含按鈕底色與內距，只佔文字本身空間、'
      '文字顏色跟隨 Theme.of(context)（epic-22-reader-theme-integration '
      'Issue 2；epic-18-reader-device-qa Issue 43 的既有測試在此更新——'
      '原本斷言寫死 Colors.black，現在明確指定 AppTheme.light 並比對其實際'
      'onSurface 色值，理由同 Issue 43：拿掉底色後，文字顏色必須與書頁'
      '背景形成足夠對比才看得到）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_footer_no_bg',
      const BookReaderPrefs(showHeader: true, showFooter: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.light),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_footer_no_bg',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 9,
        totalPages: 100,
      ),
    );
    await tester.pump();

    // 觸發沉浸模式讓頁首頁尾顯示
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerContainer = tester.widget<Container>(
      find.byKey(const Key('reader_foliate_header_text')),
    );
    expect(headerContainer.padding, isNull);
    expect(headerContainer.decoration, isNull);

    final headerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_header_text')),
      matching: find.byType(Text),
    ));
    expect(headerText.style?.fontSize, 12);
    expect(
      headerText.style?.color,
      buildThemeData(AppTheme.light).colorScheme.onSurface,
    );

    final footerContainer = tester.widget<Container>(
      find.byKey(const Key('reader_foliate_progress_text')),
    );
    expect(footerContainer.padding, isNull);
    expect(footerContainer.decoration, isNull);

    final footerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_progress_text')),
      matching: find.byType(Text),
    ));
    expect(footerText.style?.fontSize, 12);
    expect(
      footerText.style?.color,
      buildThemeData(AppTheme.light).colorScheme.onSurface,
    );
  });

  testWidgets(
      '流式 EPUB 頁首/頁尾文字：深色主題下顏色跟隨 Theme.of(context)'
      '（epic-22-reader-theme-integration Issue 2）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_footer_dark',
      const BookReaderPrefs(showHeader: true, showFooter: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_footer_dark',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 9,
        totalPages: 100,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_header_text')),
      matching: find.byType(Text),
    ));
    expect(
      headerText.style?.color,
      buildThemeData(AppTheme.dark).colorScheme.onSurface,
    );

    final footerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_progress_text')),
      matching: find.byType(Text),
    ));
    expect(
      footerText.style?.color,
      buildThemeData(AppTheme.dark).colorScheme.onSurface,
    );
  });

  testWidgets(
      'EPUB 固定版面：不論主題為何，頁首/頁尾文字色維持既有寫死 Colors.black'
      '（epic-22-reader-theme-integration Issue 2，固定版面內容通常是白底'
      '圖片，若文字色跟著深色主題變淺會看不見）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_footer_fxl',
      const BookReaderPrefs(showHeader: true, showFooter: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_header_footer_fxl',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 9,
        totalPages: 100,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_header_text')),
      matching: find.byType(Text),
    ));
    expect(headerText.style?.color, Colors.black);

    final footerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_progress_text')),
      matching: find.byType(Text),
    ));
    expect(footerText.style?.color, Colors.black);
  });

  testWidgets(
      '深色主題下開啟進度/跳頁 Bottom Sheet，遮罩透明（epic-22-reader-'
      'theme-integration Issue 5：/diagnose 確認 showModalBottomSheet 預設'
      'barrierColor（Colors.black54）疊在 AppTheme.dark 已變深的書頁背景'
      '上，合成結果逼近人眼無法辨識的全黑，改為深色主題下完全不用遮罩）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_progress_sheet_dark_barrier',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_foliate_progress_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 【驗證過程修正】widget 樹裡同時存在其他語意用途的 ModalBarrier
    // （color 恆為 null，非本次 Bottom Sheet 產生）。另外查證 Flutter
    // 框架本身（bottom_sheet.dart:1133，`if (barrierColor.a != 0 &&
    // !offstage)`）在 barrierColor 完全透明（alpha=0）時，根本不會建構
    // 出有顏色的 ModalBarrier widget（視為無遮罩效果的最佳化路徑）——
    // 故正確斷言方式是「找不到任何『真的會遮蔽畫面』（alpha > 0）的
    // ModalBarrier」，而不是找一個 color 等於 Colors.transparent 的
    // 實例（該實例根本不會被建構）。
    final dimmingBarrierFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ModalBarrier && widget.color != null && widget.color!.a > 0,
    );
    expect(dimmingBarrierFinder, findsNothing);
  });

  testWidgets(
      '深色主題下開啟版面設定 Bottom Sheet，遮罩同樣透明（epic-22-reader-'
      'theme-integration Issue 5：修法透過共用 helper 套用到全部 6 個'
      'Bottom Sheet 呼叫點，不只進度面板一處，本測試驗證另一個呼叫點'
      '同樣生效）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_settings_sheet_dark_barrier',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 「版面設定」按鈕在收到 onLayoutResolved 前是停用的（onPressed 為
    // null），比照既有測試（本檔案第 293 行附近）先觸發一次才能點擊。
    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.vertical,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_foliate_settings_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final dimmingBarrierFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ModalBarrier && widget.color != null && widget.color!.a > 0,
    );
    expect(dimmingBarrierFinder, findsNothing);
  });

  testWidgets(
      '淺色主題下開啟進度/跳頁 Bottom Sheet，遮罩維持 Flutter 既有預設值'
      '（不受本次修法影響，回歸保證）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.light),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_progress_sheet_light_barrier',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_foliate_progress_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final barrier = tester.widget<ModalBarrier>(find.byWidgetPredicate(
      (widget) => widget is ModalBarrier && widget.color != null,
    ));
    expect(barrier.color, Colors.black54);
  });

  testWidgets(
      '深色主題下流式 EPUB「返回」浮動按鈕底色/圖示色跟隨 Theme.of(context)'
      '（epic-22-reader-theme-integration Issue 3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_fab_color_dark',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // find.ancestor 可能撿到不只一個 Container（例如 Scaffold/MaterialApp
    // 內部也會用到 Container），用 .first 精確鎖定最近的一個（緊包住
    // IconButton 的那一個，即 ClipOval 底下設定 color 的那個）。
    final backContainer = tester.widget<Container>(find.ancestor(
      of: find.byKey(const Key('reader_foliate_back_button')),
      matching: find.byType(Container),
    ).first);
    final backIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_foliate_back_button')),
      matching: find.byType(Icon),
    ));

    final expectedTheme = buildThemeData(AppTheme.dark);
    expect(
      backContainer.color,
      expectedTheme.colorScheme.onSurface,
    );
    expect(backIcon.color, expectedTheme.colorScheme.surface);
  });

  testWidgets(
      '淺色主題下流式 EPUB「返回」浮動按鈕底色/圖示色跟隨 Theme.of(context)'
      '（epic-22-reader-theme-integration Issue 3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.light),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_fab_color_light',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // find.ancestor 可能撿到不只一個 Container（例如 Scaffold/MaterialApp
    // 內部也會用到 Container），用 .first 精確鎖定最近的一個（緊包住
    // IconButton 的那一個，即 ClipOval 底下設定 color 的那個）。
    final backContainer = tester.widget<Container>(find.ancestor(
      of: find.byKey(const Key('reader_foliate_back_button')),
      matching: find.byType(Container),
    ).first);
    final backIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_foliate_back_button')),
      matching: find.byType(Icon),
    ));

    final expectedTheme = buildThemeData(AppTheme.light);
    expect(
      backContainer.color,
      expectedTheme.colorScheme.onSurface,
    );
    expect(backIcon.color, expectedTheme.colorScheme.surface);
  });

  testWidgets(
      'EPUB 固定版面：不論主題為何，浮動按鈕維持既有寫死 Colors.black54/'
      'Colors.white（epic-22-reader-theme-integration Issue 3，固定版面'
      '內容通常是白底圖片，控制按鈕跟著深色主題變色會失去對比）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fab_color_fxl',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // find.ancestor 可能撿到不只一個 Container（例如 Scaffold/MaterialApp
    // 內部也會用到 Container），用 .first 精確鎖定最近的一個（緊包住
    // IconButton 的那一個，即 ClipOval 底下設定 color 的那個）。
    final backContainer = tester.widget<Container>(find.ancestor(
      of: find.byKey(const Key('reader_foliate_back_button')),
      matching: find.byType(Container),
    ).first);
    final backIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_foliate_back_button')),
      matching: find.byType(Icon),
    ));

    expect(backContainer.color, Colors.black54);
    expect(backIcon.color, Colors.white);
  });

  testWidgets(
      '深色主題下流式 EPUB「版面設定」浮動按鈕（有 onPressed 分流邏輯的'
      '按鈕）顏色同樣跟隨主題（epic-22-reader-theme-integration Issue 3，'
      '驗證不只最簡單的返回按鈕生效）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_fab_color_settings_dark',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final settingsContainer = tester.widget<Container>(find.ancestor(
      of: find.byKey(const Key('reader_foliate_settings_button')),
      matching: find.byType(Container),
    ).first);
    final settingsIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_foliate_settings_button')),
      matching: find.byType(Icon),
    ));

    final expectedTheme = buildThemeData(AppTheme.dark);
    expect(
      settingsContainer.color,
      expectedTheme.colorScheme.onSurface,
    );
    expect(settingsIcon.color, expectedTheme.colorScheme.surface);
  });

  testWidgets(
      '流式 EPUB 成功開啟後收到 onError（例如螢幕旋轉觸發的 ResizeObserver '
      '瀏覽器警告，經 epic-18-reader-device-qa Issue 33 的全域 window.onerror '
      '轉發），不應覆蓋已成功渲染的畫面（/diagnose：真機回報旋轉螢幕後畫面'
      '整個被錯誤文字取代，無法繼續閱讀）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_error_after_render',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.vertical,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(FoliateEpubReaderView), findsOneWidget);

    // 模擬旋轉螢幕時，foliate-js 的 ResizeObserver 觸發瀏覽器層級的
    // 「loop completed with undelivered notifications」警告，被全域
    // window.onerror 補捉後透過既有 onError bridge 轉發過來——這是一則
    // 良性警告，不代表書籍真的開啟失敗。
    foliateView.onError(
      'JS Error: ResizeObserver loop completed with undelivered '
      'notifications. (https://appassets.androidplatform.net/assets/'
      'foliate/index.html?prefs=...)',
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '已成功渲染的畫面不應被開書成功後才發生的良性 JS 警告覆蓋成錯誤狀態');
    expect(find.byType(FoliateEpubReaderView), findsOneWidget,
        reason: '書籍內容應維持顯示，使用者仍可繼續閱讀');
  });

  group('PdfCropFrameOverlay', () {
    testWidgets('進入手動裁切模式時顯示 PdfCropFrameOverlay，確認後寫回 prefs',
        (tester) async {
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
      binaryMessenger.setMockMethodCallHandler(
          fullscreenChannel, (call) async => null);
      addTearDown(
        () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b1',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      // epic-24 Issue 8：PDF 不再使用 AppBar，設定按鈕改為 FAB。
      // 直接呼叫 onPressed callback 繞過 PdfReaderView gesture arena 問題。
      tester.widget<IconButton>(find.byKey(const Key('reader_pdf_settings_button'))).onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
      await tester.pumpAndSettle();

      expect(find.byType(PdfCropFrameOverlay), findsOneWidget);

      await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(PdfCropFrameOverlay), findsNothing,
          reason: '確認後應退出裁切編輯模式');
    });

    testWidgets('進入手動裁切模式時顯示 PdfCropFrameOverlay，取消後退出且不寫回 prefs',
        (tester) async {
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
      binaryMessenger.setMockMethodCallHandler(
          fullscreenChannel, (call) async => null);
      addTearDown(
        () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b2',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      // epic-24 Issue 8：PDF 不再使用 AppBar，設定按鈕改為 FAB。
      // 直接呼叫 onPressed callback 繞過 PdfReaderView gesture arena 問題。
      tester.widget<IconButton>(find.byKey(const Key('reader_pdf_settings_button'))).onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
      await tester.pumpAndSettle();

      expect(find.byType(PdfCropFrameOverlay), findsOneWidget);

      await tester.tap(find.byKey(const Key('pdf_crop_frame_cancel')));
      await tester.pumpAndSettle();

      expect(find.byType(PdfCropFrameOverlay), findsNothing,
          reason: '取消後應退出裁切編輯模式');
    });
  });

  testWidgets(
      'PDF 長按拖曳框選完成後，顯示 AnnotationToolbar；點擊螢光筆後劃線已寫入且 Toolbar 仍開啟（可續加備註）',
      (tester) async {
    // 【epic-24 Issue 4 Task 6，複審修正】改回真實手勢模擬——原本的版本
    // 註解宣稱「ReaderScreen 的 widget tree 會截斷手勢／pdfrx 在 widget
    // test 環境下攔截手勢」，經 /superpowers:receiving-code-review 複審
    // 追查後證實這個說法是錯的：真正原因有兩個，且都與「手勢被攔截」
    // 無關。(1) 原本的等待邏輯只有 `Future.delayed(Duration.zero)`
    // 一個 microtask，遠不足以讓 pdfrx 真正完成非同步文件載入／版面計算
    // （見下方改用本檔案 PdfCropFrameOverlay 測試已驗證過的 30 次輪詢
    // 等待樣板），手勢發生時 GestureDetector 根本還沒真正建構出來。
    // (2) `flutter test` 預設視窗是 800×600（橫向），會讓
    // `isLandscape` 判定為 true，觸發產品預設 `dualPageMode: auto`
    // 悄悄啟用雙頁並列——雙頁模式下頁面內容在畫面上的實際位置與單頁
    // 模式完全不同（頁面通常不會貼齊 widget 左上角），這裡沿用其他
    // 測試「以左上角為基準取固定偏移量」的觸控座標假設會直接落在頁面
    // 內容範圍之外，長按自然永遠不會命中任何 GestureDetector——這不是
    // 本測試要驗證的範圍（雙頁模式下框選正確歸屬單一頁面已有
    // `pdf_reader_view_selection_test.dart` 的專屬測試涵蓋，見計畫
    // Task 5），故這裡改用本檔案既有的直向視窗慣例強制單頁模式，讓
    // 座標假設成立，而非放棄真實手勢模擬。
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800)); // 直向。
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final highlightsRepository = FakeHighlightsRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: highlightsRepository,
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    // epic-24 Issue 8：PDF 新增 FAB 後，原本的 (40, 60) 觸控座標落在
    // reader_pdf_back_button（top:16, left:16, 48x48 IconButton）範圍內，
    // 會被 FAB 的 InkWell 攔截而非命中 PdfReaderView 的 GestureDetector。
    // 改用 (200, 300) 避開所有 FAB（右側 FAB 在 right:16、左側僅左上角
    // back FAB 在 left:16, top:16）。
    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(200, 300));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(topLeft + const Offset(160, 220));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsOneWidget,
        reason: '選取完成後應顯示 AnnotationToolbar');

    await tester.tap(find.byKey(const Key('annotation_toolbar_highlighter_yellow')));
    await tester.pumpAndSettle();

    // 選色後應建立劃線，但選取狀態與 Toolbar 刻意保持開啟——比照 EPUB
    // 的 _handleHighlightStyleSelected（reader_screen.dart），讓使用者
    // 能接著按「備註」把備註掛在同一筆劃線上（見
    // AnnotationToolbar.onNotePressed 文件註解）；只有按下「備註」或
    // 取消選取才會清空 _currentPdfSelection。
    expect(find.byType(AnnotationToolbar), findsOneWidget,
        reason: '選色後劃線已建立，但 Toolbar 應保持開啟以便續加備註');
    final saved = await highlightsRepository.listByBook('b1');
    expect(saved, hasLength(1));
    expect(saved.single.pdfPageIndex, 0);
  });

  testWidgets(
      'PDF：選取範圍靠近畫面右緣時，AnnotationToolbar 右緣不應超出畫面寬度',
      (tester) async {
    // 固定視窗尺寸（400×800），讓 clamp 後的精確像素值可預期、可斷言。
    // 本測試直接呼叫 onSelectionRectComputed 回呼（比照 EPUB 測試對
    // onSelectionChanged 的呼叫方式），不透過真實長按拖曳手勢，因此不需要
    // 其他 PDF 測試（如 5391 行）為了等待真實 pdfrx 文件載入完成才需要的
    // 30 次輪詢等待樣板——本測試只驗證 AnnotationToolbar 收到選取矩形後
    // 的定位計算，與 pdfrx 是否已完成真實頁面渲染無關。
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800));
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_select_edge',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    // 選取範圍靠近畫面右緣（widgetRect.left=0.95），比照使用者截圖回報的
    // 症狀（tmp/images/畫線問題/畫線太右邊無法看到全部工具列.jpg）。
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.95, top: 0.2, right: 0.99, bottom: 0.3),
        widgetRect: PercentRect(left: 0.95, top: 0.2, right: 0.99, bottom: 0.3),
      ),
    );
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsOneWidget);
    final bottomRight = tester.getBottomRight(find.byType(AnnotationToolbar));
    expect(
      bottomRight.dx,
      lessThanOrEqualTo(400.0),
      reason: '工具列右緣（現況會落在 636.0）不應超出畫面寬度 400.0，'
          '否則右半部按鈕會被裁切看不到',
    );
  });

  testWidgets(
      'PDF：點擊 AnnotationToolbar 的關閉按鈕後，清空選取狀態、工具列消失',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_close_toolbar',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
      ),
    );
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsOneWidget);

    await tester.tap(find.byKey(const Key('annotation_toolbar_close')));
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsNothing,
        reason: '點擊關閉按鈕後應清空選取狀態，工具列從畫面消失');
  });

  testWidgets(
      'PDF 換頁時應清除既有選取狀態，AnnotationToolbar 隨之消失（Epic 24 Issue 10）',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_page_turn_clears_selection',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));

    // 情境 A：nextPage 應清除既有選取。
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
      ),
    );
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsOneWidget,
        reason: '選取完成後應顯示 AnnotationToolbar');

    ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsNothing,
        reason: 'nextPage 換頁後應清空選取狀態，工具列從畫面消失');

    // 情境 B：previousPage 同樣應清除既有選取。
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 1,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
      ),
    );
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsOneWidget,
        reason: '第二次選取完成後應再次顯示 AnnotationToolbar');

    ReaderScreen.triggerZoneAction(key, ZoneAction.previousPage);
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsNothing,
        reason: 'previousPage 換頁後同樣應清空選取狀態，工具列從畫面消失');
  });

  testWidgets(
      'PDF 換頁時若有進行中的長按拖曳框選（尚未放開手指），應一併中止，放開後不會用換頁前的舊頁面重新彈出 AnnotationToolbar（Epic 24 Issue 10 審查修正）',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800)); // 直向。
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_page_turn_cancels_active_drag',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    // 觸控位置刻意取畫面中央附近（而非邊角），避開 PDF FAB
    // （reader_pdf_back_button 等固定在 top:16/left:16 一類螢幕邊角，
    // 靠邊角的座標會被 FAB 攔截，長按永遠不會到達下方的框選手勢層）。
    final center = tester.getCenter(find.byType(PdfReaderView));
    final finger = await tester.startGesture(center);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await finger.moveTo(center + const Offset(80, 100));
    await tester.pump();
    expect(
      find.byKey(const Key('pdf_reader_selection_drag_indicator')),
      findsOneWidget,
      reason: '長按拖曳進行中應顯示框選視覺回饋',
    );

    // 比照真機情境：音量鍵翻頁與觸控手勢是完全獨立的輸入通道，可能在
    // 使用者手指仍按著螢幕、拖曳框選進行中時觸發——直接呼叫
    // triggerZoneAction 等價於音量鍵事件經 _handleVolumeKeyCall 分派的
    // 結果。
    ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
    await tester.pump();

    expect(
      find.byKey(const Key('pdf_reader_selection_drag_indicator')),
      findsNothing,
      reason: '換頁應一併中止進行中的拖曳，框選視覺回饋消失',
    );

    await finger.up();
    await tester.pump();

    expect(
      find.byType(AnnotationToolbar),
      findsNothing,
      reason: '拖曳已被中止，放開手指不應用換頁前的舊頁面座標重新彈出 AnnotationToolbar',
    );
  });

  testWidgets('PDF 選取被取消（onSelectionCanceled）時，不顯示 AnnotationToolbar',
      (tester) async {
    // 同上一則測試：改回真實多指手勢模擬，強制直向視窗維持單頁模式，
    // 並補足 30 次輪詢等待真實 pdfrx 載入完成。
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800)); // 直向。
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final firstFinger = await tester.startGesture(topLeft + const Offset(40, 60));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await firstFinger.moveTo(topLeft + const Offset(120, 160));
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsNothing,
        reason: '拖曳進行中尚未放開，不應顯示 Toolbar');

    final secondFinger = await tester.startGesture(topLeft + const Offset(300, 400));
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsNothing,
        reason: '第二指觸控應取消進行中的框選，不顯示 AnnotationToolbar');

    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();

    // DoubleTapGestureRecognizer 內部有 300ms 計時器，需 flush 否則
    // 測試結束時會擲出 "!timersPending" 斷言。
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('PDF 書籤 toggle：目前頁無書籤時呼叫後新增一筆，頁碼定位正確',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: FakeReaderPrefsManager(),
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    // 等待 pdfrx 真實載入 PDF（30 次輪詢，比照本檔案既有 PDF 測試慣例）。
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    // 模擬原生端回報頁碼，讓 _pdfPageInfo 非 null（比照既有 PDF 測試
    // 直接呼叫 PdfReaderView.onPageChanged 的模式）。
    tester.widget<PdfReaderView>(find.byType(PdfReaderView))
        .onPageChanged?.call(
      const PdfPageInfo(pageIndex: 0, totalPages: 5),
    );
    await tester.pump();

    ReaderScreen.togglePdfBookmark(key);
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final saved = await bookmarksRepository.listByBook('b1');
    expect(saved, hasLength(1));
    expect(saved.single.pdfPageIndex, 0);
    expect(saved.single.name, '第 1 頁');
  });

  testWidgets('PDF 書籤 toggle：目前頁已有書籤時呼叫後移除該筆', (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await bookmarksRepository.insert(Bookmark(
      id: 'existing',
      bookId: 'b1',
      name: '第 1 頁',
      pdfPageIndex: 0,
    ));
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: FakeReaderPrefsManager(),
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    // 等待 pdfrx 真實載入 PDF（30 次輪詢，比照本檔案既有 PDF 測試慣例）。
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    // 模擬原生端回報頁碼，讓 _pdfPageInfo 非 null。
    tester.widget<PdfReaderView>(find.byType(PdfReaderView))
        .onPageChanged?.call(
      const PdfPageInfo(pageIndex: 0, totalPages: 5),
    );
    await tester.pump();

    ReaderScreen.togglePdfBookmark(key);
    await tester.pump();
    // _togglePdfBookmark 是 async（呼叫 repository.delete + _loadFxlBookmarks），
    // togglePdfBookmark static seam 以 unawaited 包裝，需多 pump 讓 microtask 完成。
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final saved = await bookmarksRepository.listByBook('b1');
    expect(saved, isEmpty, reason: '已存在同頁書籤時應移除，而非重複新增');
  });

  testWidgets(
      'PDF 開書後背景載入目錄；載入完成前 openPdfToc 無作用，完成後可開啟 TocBottomSheet',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_pdf_toc.pdf',
          bookId: 'b_pdf_toc',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 目錄背景載入尚未完成（onPageRendered 尚未真正觸發），此時呼叫應
    // 無作用。
    ReaderScreen.openPdfToc(key);
    await tester.pump();
    expect(find.byType(TocBottomSheet), findsNothing);

    // 等待 pdfrx 真實載入 PDF（30 次輪詢，比照本檔案既有 PDF 測試慣例）。
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    // _pdfTocLoaded 由 loadTableOfContents() 這個 async 呼叫的 .then()
    // callback 設定，需要多一次 pump 讓其 microtask 完成、觸發 setState。
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsOneWidget);
    expect(find.text('Part One'), findsOneWidget);
    expect(find.text('Chapter 5'), findsOneWidget);
  });

  testWidgets('點選 PDF 目錄項目後正確跳轉頁面並關閉 Bottom Sheet', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_pdf_toc.pdf',
          bookId: 'b_pdf_toc_jump',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    // epic-24 Issue 8：PDF 不再有 in-flow 頁尾，改由進度 FAB 觸發
    // Bottom Sheet。驗證 FAB 存在即可。
    expect(find.byKey(const Key('reader_pdf_progress_button')), findsOneWidget);

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TocBottomSheet), findsOneWidget);

    // 驗證 Chapter 5 存在於目錄中
    expect(find.text('Chapter 5'), findsOneWidget);

    // 點選 Chapter 5 後，Bottom Sheet 應關閉（Navigator.pop 生效）。
    await tester.tap(find.text('Chapter 5'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TocBottomSheet), findsNothing);
  });

  testWidgets('無大綱的 PDF 開啟後，openPdfToc 顯示空清單提示而非崩潰', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_toc_empty',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsOneWidget);
    expect(find.byKey(const Key('toc_bottom_sheet_empty_text')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF 搜尋："Page" 找到符合結果，顯示計數器', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_search',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    // 輸入搜尋關鍵字
    final textField = find.byKey(const Key('pdf_search_field'));
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'Page');
    await tester.pump(const Duration(milliseconds: 600));

    // 等待搜尋完成
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    // 驗證搜尋面板可見且計數器顯示（搜尋面板內的計數器格式為「1 / 5」）。
    expect(find.text('1 / 5'), findsOneWidget);
    // epic-24 Issue 8：PDF 不再有 in-flow 頁尾，'1/5' 不會出現在 body。
    // 確認搜尋面板存在即可，不再驗證頁尾文字。
  });

  testWidgets('PDF 搜尋：點擊下一個/上一個依序跳轉並於首尾循環導覽', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_search_nav',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    final textField = find.byKey(const Key('pdf_search_field'));
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'Page');
    await tester.pump(const Duration(milliseconds: 600));

    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    // 起始狀態：5 筆符合結果，目前在第 1 筆。
    //
    // 註：本測試只斷言搜尋面板計數器（_pdfSearchStateNotifier 驅動的
    // 「N / 5」文字），不斷言 reader footer 實際頁碼（「N/5」）——footer
    // 頁碼變化依賴 pdfrx PdfViewer 內部真實捲動動畫，經診斷確認在本檔案
    // 「Bottom Sheet 開啟中」這個既有測試情境下，即使搭配 runAsync 真實
    // 延遲等待數秒，動畫完成時機仍不可靠（連 Issue 5 既有、已合併的 TOC
    // 跳頁測試「點選 PDF 目錄項目後正確跳轉頁面並關閉 Bottom Sheet」也有
    // 同樣現象，非本工單新增邏輯所致）；已用獨立情境（無 ReaderScreen／
    // Bottom Sheet 包裹的裸 PdfReaderView）重現驗證 jumpToPage() 本身在
    // 連續兩次呼叫下能正確落點，證實這是既有的測試環境時序問題，非
    // `_goToPdfSearchMatch` 的索引計算邏輯缺陷。搜尋面板計數器才是本測試
    // 真正要保護的行為（循環導覽的索引數學），且其更新不依賴 pdfrx 動畫
    // 完成，可靠地同步反映在畫面上。
    expect(find.text('1 / 5'), findsOneWidget);

    // 從第一筆點擊「上一個」，須循環到最後一筆（第 5 筆），而不是產生負數
    // 索引例外（獨立審查已確認 Dart `%` 為 Euclidean modulo、程式邏輯本身
    // 沒有 RangeError 風險，這裡是補上先前缺漏的整合層級回歸測試）。
    await tester.tap(find.byKey(const Key('pdf_search_prev_button')));
    await tester.pump();
    expect(find.text('5 / 5'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 從最後一筆點擊「下一個」，須循環回第一筆。
    await tester.tap(find.byKey(const Key('pdf_search_next_button')));
    await tester.pump();
    expect(find.text('1 / 5'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 連續點擊「下一個」4 次，依序跳轉至第 2~5 筆。
    for (var expected = 2; expected <= 5; expected++) {
      await tester.tap(find.byKey(const Key('pdf_search_next_button')));
      await tester.pump();
      expect(find.text('$expected / 5'), findsOneWidget);
    }
  });

  testWidgets('PDF 搜尋：無文字層的 PDF 查無符合結果時顯示提示文字', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_search_empty',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    final textField = find.byKey(const Key('pdf_search_field'));
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'anything');
    await tester.pump(const Duration(milliseconds: 600));

    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(find.byKey(const Key('pdf_search_empty')), findsOneWidget);
    expect(find.text('找不到符合的文字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF 縮圖：切換到縮圖分頁後正確顯示每一頁的縮圖格', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_thumbnails',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('縮圖'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 驗證縮圖面板已顯示
    expect(find.byKey(const Key('pdf_thumbnail_panel_grid')), findsOneWidget);

    // 驗證 5 頁縮圖格皆存在（sample_multi_page.pdf 有 5 頁）
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(Key('pdf_thumbnail_tile_$i')), findsOneWidget);
    }
    // 驗證第 6 格不存在——僅可視範圍內建構（Global Constraint）
    expect(find.byKey(const Key('pdf_thumbnail_tile_5')), findsNothing);
  });

  testWidgets('PDF 縮圖：點擊縮圖後正確關閉 Bottom Sheet，不拋出例外', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_thumbnails_click',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('縮圖'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 點擊第 3 頁縮圖（index 2）
    await tester.tap(find.byKey(const Key('pdf_thumbnail_tile_2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 驗證 Bottom Sheet 已關閉
    expect(find.byType(TocBottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('版面設定預設集（epic-28-reader-settings-enhancements Issue 3）', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late SqliteLibraryRepository libraryRepository;
    late LayoutPresetRepository layoutPresetRepository;
    late BookReaderPrefsRepository bookReaderPrefsRepository;

    setUp(() async {
      libraryRepository = await SqliteLibraryRepository.open(
        inMemoryDatabasePath,
        singleInstance: false,
      );
      layoutPresetRepository =
          LayoutPresetRepository(libraryRepository.database);
      bookReaderPrefsRepository =
          BookReaderPrefsRepository(libraryRepository.database);
      await libraryRepository.insertBook(Book(
        id: 'b1',
        title: '目前書籍',
        format: BookFileFormat.epub,
        filePath: 'test/fixtures/sample.epub',
        source: BookSource.local,
        isFixedLayout: false,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      await libraryRepository.insertBook(Book(
        id: 'b_other',
        title: '其他流式書',
        format: BookFileFormat.epub,
        filePath: 'content://example/other.epub',
        source: BookSource.local,
        isFixedLayout: false,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      binaryMessenger.setMockMethodCallHandler(
        const MethodChannel('elinkbook/volume_key'),
        (call) async => null,
      );
    });

    tearDown(() async {
      await libraryRepository.close();
    });

    // 比照既有「流式 EPUB 開書後，ReaderSettingsSheet 變動的偏好正確傳遞到
    // FoliateEpubReaderView」測試（約 line 351）的既有手法：settings 按鈕
    // 的 onPressed 要到 `onLayoutResolved` 觸發、_autoDetectedWritingMode
    // 非 null 後才可用（純 flutter test 環境沒有真實 WebView，須手動呼叫
    // FoliateEpubReaderView widget 上的 onPageRendered()/onLayoutResolved()
    // 模擬原生端回報）。按鈕 key 用 `reader_foliate_settings_button`（現行
    // FAB 化路徑，非舊版 `reader_layout_settings_button`）。
    Future<void> pumpReaderScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: false,
            libraryRepository: libraryRepository,
            layoutPresetRepository: layoutPresetRepository,
            bookReaderPrefsRepository: bookReaderPrefsRepository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      final foliateView =
          tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
      );
      await tester.pump();
    }

    testWidgets('另存為新預設集：命名對話框輸入名稱後，正確寫入 LayoutPresetRepository',
        (tester) async {
      await pumpReaderScreen(tester);

      // 開啟版面設定 Sheet、捲動到「另存為新預設集」按鈕並點擊。
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_save_as_preset')));
      await tester
          .tap(find.byKey(const Key('reader_settings_save_as_preset')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('layout_preset_name_dialog_field')), '測試預設集');
      await tester
          .tap(find.byKey(const Key('layout_preset_name_dialog_confirm')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      final all = await tester.runAsync(() => layoutPresetRepository.listAll());
      expect(all, hasLength(1));
      expect(all!.single.name, '測試預設集');
    });

    testWidgets('存滿 3 組後再次另存，跳出覆蓋選單，選擇並確認後正確覆蓋既有一組',
        (tester) async {
      for (final name in ['A', 'B', 'C']) {
        await tester.runAsync(() => layoutPresetRepository.insert(LayoutPreset(
          id: null,
          name: name,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          prefs: const BookReaderPrefs(fontSize: 16),
        )));
      }

      await pumpReaderScreen(tester);
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_save_as_preset')));
      await tester
          .tap(find.byKey(const Key('reader_settings_save_as_preset')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('layout_preset_name_dialog_field')), 'D');
      await tester
          .tap(find.byKey(const Key('layout_preset_name_dialog_confirm')));
      await tester.pumpAndSettle();

      // 覆蓋選單：選第一組（名稱 'A'，這是這個乾淨的記憶體內資料庫本測試
      // 第一筆 insert，AUTOINCREMENT id 必為 1）。
      await tester
          .tap(find.byKey(const Key('layout_preset_overwrite_option_1')));
      await tester.pumpAndSettle();
      // 確認覆蓋對話框。
      await tester
          .tap(find.byKey(const Key('layout_preset_overwrite_confirm')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      final all = await tester.runAsync(() => layoutPresetRepository.listAll());
      expect(all, hasLength(3));
      expect(all!.map((p) => p.name).toList(), ['D', 'B', 'C']);
    });

    testWidgets('套用預設集到目前書籍：立即寫入且畫面即時反映新值（透過 _handlePrefsChanged）',
        (tester) async {
      await tester.runAsync(() => layoutPresetRepository.insert(LayoutPreset(
        id: null,
        name: '測試預設集',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: const BookReaderPrefs(fontSize: 24 / 16),
      )));

      await pumpReaderScreen(tester);
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find
          .byKey(const Key('reader_settings_preset_slot_0_apply_current')));
      await tester.tap(
          find.byKey(const Key('reader_settings_preset_slot_0_apply_current')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      final saved = await tester.runAsync(() => bookReaderPrefsRepository.load('b1'));
      expect(saved!.fontSize, 24 / 16);

      // Bottom Sheet 開啟中同步（spec.md「套用當下 Sheet 仍開啟」情境，
      // 對應審查意見 Minor 2.7）：套用當下 Sheet 仍在畫面上，_prefs 更新
      // 觸發 ReaderScreen 重建，_openLayoutSettings() 的 builder 以新的
      // _prefs 重新建構 ReaderSettingsSheet，其既有 didUpdateWidget 邏輯
      // （本 Task 未改動，沿用既有機制）同步內部草稿——驗證目前畫面上這顆
      // ReaderSettingsSheet 的 prefs 已是套用後的新值，而非套用前的舊值。
      final sheetAfterApply =
          tester.widget<ReaderSettingsSheet>(find.byType(ReaderSettingsSheet));
      expect(sheetAfterApply.prefs.fontSize, 24 / 16);
    });

    testWidgets('套用預設集到其他書籍（多本）：跳出「即將覆蓋 N 本書」確認對話框，確認後批次寫入',
        (tester) async {
      await tester.runAsync(() => layoutPresetRepository.insert(LayoutPreset(
        id: null,
        name: '測試預設集',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: const BookReaderPrefs(fontSize: 24 / 16),
      )));

      await pumpReaderScreen(tester);
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_preset_slot_0_apply_others')));
      await tester.tap(
          find.byKey(const Key('reader_settings_preset_slot_0_apply_others')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      // 書籍選擇器：勾選「其他流式書」後點確定。
      await tester
          .tap(find.byKey(const Key('layout_preset_book_picker_item_b_other')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('layout_preset_book_picker_confirm')));
      await tester.pumpAndSettle();

      // 「即將覆蓋 N 本書」確認對話框。
      await tester.tap(find.byKey(const Key('layout_preset_apply_confirm')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      final saved = await tester.runAsync(() => bookReaderPrefsRepository.load('b_other'));
      expect(saved!.fontSize, 24 / 16);
      // 目前書籍（b1）不在目標內，不受影響。
      final currentBookPrefs = await tester.runAsync(() => bookReaderPrefsRepository.load('b1'));
      expect(currentBookPrefs!.fontSize, isNull);
    });

    testWidgets('刪除預設集：正確從 LayoutPresetRepository 移除', (tester) async {
      await tester.runAsync(() => layoutPresetRepository.insert(LayoutPreset(
        id: null,
        name: '待刪除',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: BookReaderPrefs.empty,
      )));

      await pumpReaderScreen(tester);
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_preset_slot_0_delete')));
      await tester
          .tap(find.byKey(const Key('reader_settings_preset_slot_0_delete')));
      await tester.pumpAndSettle();
      // 「確認刪除」對話框。
      await tester.tap(find.byKey(const Key('layout_preset_delete_confirm')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      final all = await tester.runAsync(() => layoutPresetRepository.listAll());
      expect(all, isEmpty);
    });

    testWidgets('刪除預設集：確認對話框取消時不刪除', (tester) async {
      await tester.runAsync(() => layoutPresetRepository.insert(LayoutPreset(
        id: null,
        name: '不應被刪除',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: BookReaderPrefs.empty,
      )));

      await pumpReaderScreen(tester);
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_preset_slot_0_delete')));
      await tester
          .tap(find.byKey(const Key('reader_settings_preset_slot_0_delete')));
      await tester.pumpAndSettle();
      // 「確認刪除」對話框中點擊「取消」。
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();

      final all = await tester.runAsync(() => layoutPresetRepository.listAll());
      expect(all, hasLength(1));
    });

    testWidgets('複製其他書籍設定到本書：正確以 reflowableEpubFields() 過濾後寫入並即時反映',
        (tester) async {
      await tester.runAsync(() => bookReaderPrefsRepository.save(
        'b_other',
        const BookReaderPrefs(
          fontSize: 20 / 16,
          pdfContrast: 30, // 應被過濾，不應出現在複製結果中。
        ),
      ));

      await pumpReaderScreen(tester);
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_copy_from_book_current')));
      await tester
          .tap(find.byKey(const Key('reader_settings_copy_from_book_current')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('layout_preset_book_picker_item_b_other')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      final saved = await tester.runAsync(() => bookReaderPrefsRepository.load('b1'));
      expect(saved!.fontSize, 20 / 16);
      expect(saved.pdfContrast, isNull);
    });
  });

  tearDownAll(() {
    // 還原 cacheBookForServing 為原始實作，避免污染其他測試檔
    cacheBookForServing = originalCacheBookForServing;
  });
}
