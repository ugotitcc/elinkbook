import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/zone_action.dart';

void main() {
  setUp(() => pdfrxInitialize());

  Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
    return tester.runAsync(() async {
      for (var i = 0; i < 30 && rendered() == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

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
    await waitRendered(tester, () => renderedCount);

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
    await waitRendered(tester, () => renderedCount);

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
    await waitRendered(tester, () => renderedCount);
    await tester.pump();

    expect(find.text('選單'), findsNothing);
  });

  testWidgets('showNavZoneDebugOverlay 為 true 時顯示動作文字標籤', (tester) async {
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
    await waitRendered(tester, () => renderedCount);
    await tester.pump();

    expect(find.text('選單'), findsOneWidget);
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
    await waitRendered(tester, () => renderedCount);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pdf_reader_nav_zone_4'))),
    );
    await tester.pump(const Duration(milliseconds: 600));
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
    await waitRendered(tester, () => renderedCount);

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
}
