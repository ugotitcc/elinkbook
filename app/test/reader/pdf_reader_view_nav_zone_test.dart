import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/reader/reader_console_log.dart';
import '../support/pump_until_pdf_ready.dart';

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('navZoneActions 預設全部為 none 時，點擊格子仍呼叫 onZoneAction 並帶入 none',
      (tester) async {
    var renderedCount = 0;
    ZoneAction? triggered;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onZoneAction: (action) => triggered = action,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_4')));
    await tester.pump();

    expect(triggered, ZoneAction.none);
    // 等待 PdfViewer 內部 DoubleTapGestureRecognizer 的定時器過期，避免測試
    // 結束時拋出 "A Timer is still pending" 斷言。
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('點擊熱區格子時，觸發該索引設定的 ZoneAction', (tester) async {
    var renderedCount = 0;
    ZoneAction? triggered;
    final actions = List<ZoneAction>.filled(9, ZoneAction.none);
    actions[0] = ZoneAction.previousPage;
    actions[2] = ZoneAction.nextPage;
    actions[4] = ZoneAction.menu;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
          onZoneAction: (action) => triggered = action,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_4')));
    await tester.pump();
    expect(triggered, ZoneAction.menu);

    triggered = null;
    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_0')));
    await tester.pump();
    expect(triggered, ZoneAction.previousPage);

    triggered = null;
    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_2')));
    await tester.pump();
    expect(triggered, ZoneAction.nextPage);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('showNavZoneDebugOverlay 預設 false 時不顯示動作文字標籤',
      (tester) async {
    var renderedCount = 0;
    final actions = List<ZoneAction>.filled(9, ZoneAction.none);
    actions[1] = ZoneAction.menu;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
    await tester.pump();

    expect(find.text('選單'), findsNothing);
  });

  testWidgets(
      'showNavZoneDebugOverlay 為 true 時，只顯示格線，不顯示動作文字標籤（使用者需求：'
      '輔助線用途是校準熱區位置，文字標籤會遮擋畫面內容）', (tester) async {
    var renderedCount = 0;
    final actions = List<ZoneAction>.filled(9, ZoneAction.none);
    actions[1] = ZoneAction.menu;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
          showNavZoneDebugOverlay: true,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
    await tester.pump();

    expect(find.text('選單'), findsNothing);
    // 等待 PdfViewer 內部 DoubleTapGestureRecognizer 的定時器過期，避免測試
    // 結束時拋出 "A Timer is still pending" 斷言（比照本檔案既有測試慣例）。
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
      'showNavZoneDebugOverlay 為 true 時，格線改讀 colorScheme.onSurface（'
      'epic-35-design-system-tokens Issue 7：取代原本寫死的 Colors.white24／'
      'white70——這個字面值跟主題無關，換主題／開啟 E-Ink 模式時不會跟著換）',
      (tester) async {
    var renderedCount = 0;
    final actions = List<ZoneAction>.filled(9, ZoneAction.none);
    actions[1] = ZoneAction.menu;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
          showNavZoneDebugOverlay: true,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
    await tester.pump();

    final context =
        tester.element(find.byKey(const Key('pdf_reader_nav_zone_1')));
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;

    final cell = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('pdf_reader_nav_zone_1')),
        matching: find.byType(Container),
      ),
    );
    final border = (cell.decoration as BoxDecoration).border as Border;
    expect(border.top.color, onSurfaceColor.withValues(alpha: 0.24));
    // 等待 PdfViewer 內部 DoubleTapGestureRecognizer 的定時器過期，避免測試
    // 結束時拋出 "A Timer is still pending" 斷言（比照本檔案既有測試慣例）。
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
      '按壓超過快速點擊時長判定門檻不觸發 onZoneAction，避免與長按選取手勢衝突',
      (tester) async {
    var renderedCount = 0;
    ZoneAction? triggered;
    final actions = List<ZoneAction>.filled(9, ZoneAction.menu);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
          onZoneAction: (action) => triggered = action,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pdf_reader_nav_zone_4'))),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.up();
    await tester.pump();

    expect(triggered, isNull);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('onPointerCancel 後清除按壓暫存狀態，取消手勢不觸發 onZoneAction，後續正常點擊仍正確判定',
      (tester) async {
    var renderedCount = 0;
    ZoneAction? triggered;
    final actions = List<ZoneAction>.filled(9, ZoneAction.menu);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
          onZoneAction: (action) => triggered = action,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final cancelledGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pdf_reader_nav_zone_4'))),
    );
    await cancelledGesture.cancel();
    await tester.pump();

    expect(triggered, isNull);

    // 取消手勢後，暫存的按下狀態須確實清除——後續一次正常的快速點擊仍應
    // 正確觸發，證明沒有殘留舊值造成誤判（審查意見 Minor 1）。
    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_4')));
    await tester.pump();
    expect(triggered, ZoneAction.menu);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
      '合格快速點擊時，ReaderConsoleLog 收到帶 zone 索引的 [DEBUG-e26i3] 插樁訊息（Epic 26 Issue 3 暫時性真機診斷插樁）',
      (tester) async {
    ReaderConsoleLog.clear();
    var renderedCount = 0;
    final actions = List<ZoneAction>.filled(9, ZoneAction.menu);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_4')));
    await tester.pump();

    expect(
      ReaderConsoleLog.entries.value.any((line) =>
          line.startsWith('[DEBUG-e26i3] up qualified=true fired=true') &&
          line.endsWith('zone=4')),
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 400));
  });
}
