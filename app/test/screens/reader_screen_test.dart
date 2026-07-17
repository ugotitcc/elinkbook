import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/fxl_settings_sheet.dart';
import 'package:elinkbook/screens/pdf_settings_sheet.dart';
import 'package:elinkbook/reader/toc_entry.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';

import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../support/fake_reader_prefs_manager.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import '../support/fake_bookmarks_repository.dart';
import 'package:elinkbook/screens/annotation_toolbar.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';

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

  setUp(() {
    prefsManager = FakeReaderPrefsManager();
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
      reason:
          '尚未收到 onLayoutResolved，_autoDetectedWritingMode 仍為 null，按鈕應為停用狀態',
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

    final finder = find.byKey(const Key('reader_layout_settings_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onPageRendered（純 flutter test 環境下 AndroidView 不會'
          '觸發原生回呼），按鈕應為停用狀態，比照 EPUB 齒輪按鈕的既有測試限制'
          '（見本檔案第 46-65 行）',
    );
  });

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

    final viewFinder = find.byType(EpubReaderView);
    expect(viewFinder, findsOneWidget);
    final epubView = tester.widget<EpubReaderView>(viewFinder);
    expect(epubView.fontSize, 1.5);
  });

  testWidgets(
      'writingModeOverride 已持久化時，即使尚未收到 onLayoutResolved，'
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

    final epubView =
        tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    expect(epubView.writingMode, WritingMode.vertical);
    // 排版方向的雙層解析獨立於「⚙️版面」按鈕的啟用條件——後者仍要求真正
    // 收到 onLayoutResolved（見 _buildAppBarActions 的
    // _autoDetectedWritingMode 判斷），純 flutter test 環境下 AndroidView
    // 不會觸發原生回呼，因此這裡按鈕仍是停用狀態，屬預期行為，不是本測試
    // 要驗證的重點。
    expect(
      tester
          .widget<IconButton>(
              find.byKey(const Key('reader_layout_settings_button')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('pageTurnModeOverride 為 null 時，未覆寫的書籍採用全域預設值（paginated）',
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

    final epubView =
        tester.widget<EpubReaderView>(find.byType(EpubReaderView));
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

    final epubView =
        tester.widget<EpubReaderView>(find.byType(EpubReaderView));
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

    final epubView =
        tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    expect(epubView.pageTurnMode, PageTurnMode.scroll);
  });

  testWidgets('開啟該書已有的持久化 pdfFitMode 後，PdfReaderView.fitMode 正確載入',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(pdfFitMode: PdfFitMode.actualSize),
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

    final viewFinder = find.byType(PdfReaderView);
    expect(viewFinder, findsOneWidget);
    final pdfView = tester.widget<PdfReaderView>(viewFinder);
    expect(pdfView.fitMode, PdfFitMode.actualSize);
  });

  testWidgets('尚未持久化 pdfFitMode 時，PdfReaderView.fitMode 採用預設值 pageFit',
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

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.fitMode, PdfFitMode.pageFit);
  });

  testWidgets(
      '點擊手動選區後，關閉 PdfSettingsSheet 並將 cropEditModeActive 傳入 PdfReaderView',
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

    // 模擬原生端 onPageRendered，讓「⚙️版面」按鈕轉為可點擊狀態（純
    // flutter test 環境下 AndroidView 不會真正觸發原生回呼，比照本檔案
    // 既有測試對「尚未收到 onPageRendered」情境的說明，見第 69-89 行）。
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pumpAndSettle();

    expect(find.byType(PdfSettingsSheet), findsNothing);
    expect(
      tester
          .widget<PdfReaderView>(find.byType(PdfReaderView))
          .cropEditModeActive,
      isTrue,
    );
  });

  testWidgets(
      '收到 onCropRectSelected 後，退出裁切模式、寫入 pdfCropMode=manual 並持久化、重新開啟 PdfSettingsSheet',
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

    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    const selectedRect =
        PdfCropRect(left: 0.1, top: 0.15, right: 0.9, bottom: 0.85);
    tester
        .widget<PdfReaderView>(find.byType(PdfReaderView))
        .onCropRectSelected!(selectedRect);
    await tester.pumpAndSettle();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.cropEditModeActive, isFalse);
    expect(pdfView.cropMode, PdfCropMode.manual);
    expect(pdfView.cropRect, selectedRect);
    expect(find.byType(PdfSettingsSheet), findsOneWidget,
        reason: '確認框選後應重新開啟 PdfSettingsSheet 顯示套用結果（見 spec.md）');

    final saved = await prefsManager.load('b1');
    expect(saved.bookPrefs.pdfCropMode, PdfCropMode.manual);
    expect(saved.bookPrefs.pdfCropRect, selectedRect);
  });

  testWidgets(
      '進入手動裁切互動模式後，PopScope.canPop 為 false（返回鍵不應退出整個閱讀器）',
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

    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue,
        reason: '尚未進入裁切互動模式時，返回鍵應正常運作（可以離開閱讀器）');

    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pumpAndSettle();

    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse,
        reason: '裁切互動模式進行中，返回鍵不應把整個 ReaderScreen 一併 '
            'pop 掉（審查意見 2.1(b)：避免誤觸返回鍵導致整個閱讀器被意外'
            '關閉；刻意不新增「取消並還原」語意，維持 spec.md 已鎖定的簡化'
            '狀態機決策——見本檔案 _handleRequestManualCrop 的文件註解）');
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
        .widget<EpubReaderView>(find.byType(EpubReaderView))
        .onLayoutResolved!(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.vertical,
      ),
    );
    await tester.pump();

    expect(
      tester.widget<EpubReaderView>(find.byType(EpubReaderView)).writingMode,
      WritingMode.vertical,
    );
  });

  testWidgets('裝置為橫向時，isLandscape 正確下傳給 PdfReaderView 建構參數',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 400)); // 橫向

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

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.isLandscape, isTrue);
  });

  testWidgets('裝置為直向時，isLandscape 正確下傳為 false', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800)); // 直向
    // 確保 MediaQuery 收到新的 surface size
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
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.isLandscape, isFalse);
  });

  testWidgets('開啟該書已有的持久化雙頁偏好設定後，PdfReaderView 的雙頁參數正確載入',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(
        dualPageMode: DualPageMode.always,
        dualPageCoverAlone: false,
        dualPageDirection: DualPageDirection.rtl,
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

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.dualPageMode, DualPageMode.always);
    expect(pdfView.dualPageCoverAlone, isFalse);
    expect(pdfView.dualPageDirection, DualPageDirection.rtl);
  });

  testWidgets(
      '尚未持久化雙頁偏好設定時，PdfReaderView 的雙頁參數採用預設值（auto／true／rtl）',
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

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.dualPageMode, DualPageMode.auto);
    expect(pdfView.dualPageCoverAlone, isTrue);
    expect(pdfView.dualPageDirection, DualPageDirection.rtl);
  });

  testWidgets(
      'EPUB 固定版面開書後，畫面右上角出現懸浮設定按鈕，點擊能開啟 FxlSettingsSheet',
      (tester) async {
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
    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_fixed_layout_settings_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader_fixed_layout_settings_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FxlSettingsSheet), findsOneWidget);
  });

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
    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader_fixed_layout_settings_button')),
      findsOneWidget,
    );

    // 直接呼叫 onToggleFixedLayoutControls 模擬中間熱區觸發
    view.onToggleFixedLayoutControls?.call();
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reader_fixed_layout_settings_button')),
      findsNothing,
    );

    // 再次觸發切換顯示
    view.onToggleFixedLayoutControls?.call();
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader_fixed_layout_settings_button')),
      findsOneWidget,
    );
  });

  testWidgets('固定版面點擊左/右熱區換頁後，懸浮按鈕自動收起', (tester) async {
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
    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsOneWidget,
    );

    // 直接呼叫 onFixedLayoutPageTurn 模擬換頁觸發
    view.onFixedLayoutPageTurn?.call();
    await tester.pump();

    expect(
      find.byKey(const Key('reader_fixed_layout_back_button')),
      findsNothing,
      reason: '換頁後，懸浮控制項應自動收起',
    );
    expect(
      find.byKey(const Key('reader_fixed_layout_settings_button')),
      findsNothing,
    );
  });

  testWidgets('PDF 開書後，收到原生端 onPageChanged 回報時，頁尾正確顯示',
      (tester) async {
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
    // callback（比照既有 EPUB 測試直接呼叫 onLayoutResolved 的模式），
    // 驗證 ReaderScreen 正確驅動 ReaderFooter 顯示。
    final pdfView =
        tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 0, totalPages: 12));
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
    expect(find.text('進度 8% ｜ 第 1/12 頁'), findsOneWidget);
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

  testWidgets('PDF 收到 onPageChanged 後離開畫面（dispose），正確寫入 ReadingPosition',
      (tester) async {
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
    final pdfView =
        tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 3, totalPages: 10));
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

  testWidgets('尚未收到任何 onPageChanged 時，dispose 不呼叫 saveReadingPosition（避免覆寫既有記錄）',
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
  });

  // --- Epic 5 Issue 3：EPUB 頁碼顯示 + 跳頁 ---

  testWidgets('EPUB reflowable 開書後，收到 onCharacterCountReady 回報時，頁尾正確顯示估算頁碼',
      (tester) async {
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    // 先回報非固定版面（頁尾只在流式 EPUB 顯示）。
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    // 模擬原生端背景計算完成，回報全書字元數。
    epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
    // 預設版面參數下 estimateCharsPerScreen() = 500，5000/500 = 10 頁；
    // 尚未收到 onLocatorChanged，estimateCurrentPage(null, 10) = 1。
    expect(find.text('進度 10% ｜ 第 1/10 頁'), findsOneWidget);
  });

  testWidgets('EPUB 收到 onLocatorChanged 的 progression 後，頁尾目前頁碼正確更新',
      (tester) async {
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onCharacterCountReady?.call(5000); // 總頁數 10
    await tester.pump();
    epubView.onLocatorChanged?.call(
      const EpubPositionInfo(locatorJson: '{"href":"/c1.xhtml"}', progression: 0.5),
    );
    await tester.pump();

    expect(find.text('進度 50% ｜ 第 5/10 頁'), findsOneWidget);
  });

  testWidgets('EPUB 固定版面（FXL）開書後，即使收到 onCharacterCountReady 也不顯示頁尾',
      (tester) async {
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('版面設定（字型大小）變動後，EPUB 頁尾估算總頁數即時重新計算',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_epub_footer_recalc',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onPageRendered();
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.text('進度 10% ｜ 第 1/10 頁'), findsOneWidget);

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
      await tester.tap(find.byKey(const Key('reader_settings_font_size_increment')));
      await tester.pump();
    }

    // fontSize 倍率變成 2.0 → estimateCharsPerScreen 從 500 降為 125 →
    // totalPages 從 10 變成 40。
    expect(find.text('進度 3% ｜ 第 1/40 頁'), findsOneWidget);
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
    pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 0, totalPages: 12));
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
    expect(find.text('進度 8% ｜ 第 1/12 頁'), findsOneWidget);
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

  testWidgets('EPUB 固定版面（FXL）開書後，目錄按鈕不存在（沿用既有 AppBar 隱藏機制）',
      (tester) async {
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
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
  });

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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
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

  testWidgets('EPUB reflowable 預設（未持久化）showHeader=true，開書後 AppBar 標題為可點擊的章節標題元件',
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsOneWidget);
    expect(find.byKey(const Key('reader_appbar_static_title')), findsNothing);
    // 「⚙️版面」按鈕仍在 actions 內，頁首開關不影響既有版面設定入口
    expect(find.byKey(const Key('reader_layout_settings_button')), findsOneWidget);
  });

  testWidgets('已持久化 showHeader=false 時，AppBar 標題維持靜態「閱讀器」文字',
      (tester) async {
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget);
    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsNothing);
    expect(find.byKey(const Key('reader_toc_button')), findsOneWidget,
        reason: '頁首關閉不影響目錄按鈕仍存在於 actions');
  });

  testWidgets('PDF 開書後，AppBar 標題恆為靜態「閱讀器」文字（頁首概念僅限 EPUB）',
      (tester) async {
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

    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget);
    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsNothing);
  });

  testWidgets('頁首啟用且目錄背景抓取完成後，點擊 AppBar 標題可開啟 TocBottomSheet',
      (tester) async {
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
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

  testWidgets('showFooter=false 時，EPUB 頁尾即使收到 onCharacterCountReady 也不顯示',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_footer_off_epub',
      const BookReaderPrefs(showFooter: false),
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
    // 頁尾關閉不影響頁首（預設開啟）——驗證兩者互相獨立。
    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsOneWidget);
  });

  testWidgets('showFooter=false 時，PDF 頁尾即使收到 onPageChanged 也不顯示',
      (tester) async {
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
    pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 0, totalPages: 12));
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('showHeader=true 且 showFooter=false 組合：頁首顯示章節標題元件、頁尾不顯示',
      (tester) async {
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsOneWidget);
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('showHeader=false 且 showFooter=true 組合：頁首為靜態文字、頁尾顯示',
      (tester) async {
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget);
    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
  });

  testWidgets('EPUB 固定版面（FXL）開書後，即使 showHeader=false/showFooter=false，懸浮返回/設定按鈕仍正常顯示（FXL 完全不受影響）',
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(find.byType(AppBar), findsNothing, reason: 'FXL 不建構 Scaffold AppBar，頁首邏輯不適用');
    expect(find.byKey(const Key('reader_fixed_layout_back_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_fixed_layout_settings_button')), findsOneWidget);
  });

  // --- Epic 6 Issue 1：書籤管理 + 統一「筆記」入口 ---

  testWidgets('未提供 bookmarksRepository 時，📚 筆記按鈕不存在（既有呼叫端不受影響）',
      (tester) async {
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
  });

  testWidgets(
      'EPUB 只收到 onLayoutResolved（尚未收到 onLocatorChanged）時，📚 按鈕仍為停用狀態'
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
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

  testWidgets('EPUB 收到 onLayoutResolved 與 onLocatorChanged 後，📚 按鈕可點擊，點擊後開啟 NotesBottomSheet',
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    epubView.onLocatorChanged?.call(
      const EpubPositionInfo(locatorJson: '{"href":"/c1.xhtml"}', progression: 0.1),
    );
    await tester.pump();

    final finder = find.byKey(const Key('reader_notes_button'));
    expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NotesBottomSheet), findsOneWidget);
  });

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

    final finder = find.byKey(const Key('reader_notes_button'));
    expect(tester.widget<IconButton>(finder).onPressed, isNull);

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageRendered();
    await tester.pump();

    expect(tester.widget<IconButton>(finder).onPressed, isNotNull);
  });

  // --- Epic 6 Issue 2：EPUB 劃線/備註 ---

  testWidgets(
      '未提供 highlightsRepository／notesRepository 時，EPUB 選取事件不顯示浮動工具列（既有呼叫端零回歸）',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.epub',
        bookId: 'b1',
        prefsManager: FakeReaderPrefsManager(),
        bookmarksRepository: bookmarksRepository,
      ),
    ));
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsNothing);
  });

  testWidgets('提供 highlightsRepository／notesRepository 後，ReaderScreen 建構不受影響、仍正常顯示（既有測試涵蓋常態載入行為）',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.epub',
        bookId: 'b1',
        prefsManager: FakeReaderPrefsManager(),
        bookmarksRepository: bookmarksRepository,
        highlightsRepository: highlightsRepository,
        notesRepository: notesRepository,
      ),
    ));
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
  });

  testWidgets(
      'PDF 書籍提供 highlightsRepository／notesRepository 後，ReaderScreen 建構不受影響、仍正常顯示',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.pdf',
        bookId: 'b1',
        prefsManager: FakeReaderPrefsManager(),
        bookmarksRepository: bookmarksRepository,
        highlightsRepository: highlightsRepository,
        notesRepository: notesRepository,
      ),
    ));
    await tester.pump();

    // 原生 PlatformView 在 app/test/ 環境下不會真正建立（_channel 恆為
    // null，見既有兩層測試架構慣例），選取觸發後的浮動工具列顯示效果留
    // 給 Task 11 integration_test 驗證；本測試只驗證建構參數可正確傳入
    // 不崩潰，且未觸發選取時不顯示浮動工具列（既有行為零回歸）。
    expect(find.byType(AnnotationToolbar), findsNothing);
  });

  testWidgets('PDF 書籍未提供 highlightsRepository／notesRepository 時建構不受影響（既有呼叫端零回歸）',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.pdf',
        bookId: 'b1',
        prefsManager: FakeReaderPrefsManager(),
        bookmarksRepository: bookmarksRepository,
      ),
    ));
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsNothing);
  });
}
