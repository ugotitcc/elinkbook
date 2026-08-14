import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('本機路徑開書成功，觸發 onPageRendered，不觸發 onError',
      (tester) async {
    var renderedCount = 0;
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (msg) => errorMessage = msg,
        ),
      ),
    );

    // pdfrx 開書為非同步流程，須讓多輪 microtask/frame 有機會完成。
    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0 && errorMessage == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(renderedCount, 1);
    expect(errorMessage, isNull);
  });

  testWidgets('開啟不存在的檔案，觸發 onError、不觸發 onPageRendered',
      (tester) async {
    var renderedCount = 0;
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/does_not_exist.pdf',
          onPageRendered: () => renderedCount++,
          onError: (msg) => errorMessage = msg,
        ),
      ),
    );

    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0 && errorMessage == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(errorMessage, isNotNull);
    expect(renderedCount, 0);
  });

  testWidgets('pageCount／jumpToPage 正確運作，含邊界情況', (tester) async {
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

    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(renderedCount, 1);
    expect(lastPageInfo?.totalPages, 5);
    expect(lastPageInfo?.pageIndex, 0);

    // 跳到最後一頁（0-indexed 第 4 頁 = fixture 第 5 頁）。
    PdfReaderView.jumpToPage(key, 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 4);

    // 跳到超出範圍的頁碼須被安全忽略，不拋出例外、不改變目前頁碼。
    PdfReaderView.jumpToPage(key, 999);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 4);
  });

  testWidgets('content:// URI 路徑觸發 openCustom 分支（無 mock channel 時安全失敗，不當成本機路徑處理）',
      (tester) async {
    var renderedCount = 0;
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'content://com.example.provider/document/42',
          onPageRendered: () => renderedCount++,
          onError: (msg) => errorMessage = msg,
        ),
      ),
    );

    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0 && errorMessage == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(renderedCount, 0);
    expect(errorMessage, isNotNull);
  });

  testWidgets('content:// URI 開書透過平台通道一次性讀取全部位元組',
      (tester) async {
    late List<int> fileBytes;
    await tester.runAsync(() async {
      fileBytes = await File('test/fixtures/sample_multi_page.pdf').readAsBytes();
    });
    var readAllCalled = false;

    const channel = MethodChannel('elinkbook/reader_resources');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readContentUriAll':
          readAllCalled = true;
          // 模擬原生端 readContentUriAll 行為：寫入暫存檔後回傳路徑字串
          final tmpFile = File('${Directory.systemTemp.path}/test_content_uri.pdf');
          await tmpFile.writeAsBytes(fileBytes);
          return tmpFile.path;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    var renderedCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'content://com.example.provider/document/42',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );

    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(renderedCount, 1);
    expect(readAllCalled, isTrue);
  });

  testWidgets(
      'pdfPageTurnAnimation=none 時，jumpToPage 後單一 pump（無經過時間）已立即反映新頁碼',
      (tester) async {
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
          pdfPageTurnAnimation: PdfPageTurnAnimation.none,
        ),
      ),
    );

    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.jumpToPage(key, 4);
    await tester.pump(); // 單一 frame、無經過時間。
    expect(lastPageInfo?.pageIndex, 4);
  });

  testWidgets(
      '預設 pdfPageTurnAnimation（slide）時，jumpToPage 後單一 pump（無經過時間）尚未反映新頁碼，需等待 200ms 動畫',
      (tester) async {
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

    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.jumpToPage(key, 4);
    await tester.pump(); // 單一 frame、無經過時間——動畫尚未跑完。
    expect(lastPageInfo?.pageIndex, 0); // 仍是舊頁碼。

    await tester.pump(const Duration(milliseconds: 300)); // 200ms 動畫跑完。
    expect(lastPageInfo?.pageIndex, 4);
  });

  testWidgets(
      'pdfPageTurnAnimation=none 時，nextPage()／previousPage() 也在單一 pump 後立即反映新頁碼',
      (tester) async {
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
          pdfPageTurnAnimation: PdfPageTurnAnimation.none,
        ),
      ),
    );

    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.nextPage(key);
    await tester.pump();
    expect(lastPageInfo?.pageIndex, 1);

    PdfReaderView.previousPage(key);
    await tester.pump();
    expect(lastPageInfo?.pageIndex, 0);
  });

  testWidgets(
      'dualPageMode=always 且 pdfPageTurnAnimation=none 時，跳頁在單一 pump 後立即反映（涵蓋雙頁 _goToSpread／goToArea 路徑）',
      (tester) async {
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
          dualPageMode: DualPageMode.always,
          pdfPageTurnAnimation: PdfPageTurnAnimation.none,
        ),
      ),
    );

    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump(); // 讓雙頁版面計算（_layoutSpreadPages）完成一輪 build。
    final initialIndex = lastPageInfo?.pageIndex;

    PdfReaderView.nextPage(key);
    await tester.pump(); // 單一 frame、無經過時間。
    expect(lastPageInfo?.pageIndex, isNot(initialIndex));
  });
}
