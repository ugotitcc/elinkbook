import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/pdf_settings_sheet.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../support/fake_reader_prefs_manager.dart';

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
}
