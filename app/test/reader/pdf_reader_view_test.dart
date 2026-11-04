import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/pdf_page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/navigation_degraded_reason.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_console_log.dart';
import '../support/pump_localized_widget.dart';
import '../support/pump_until_pdf_ready.dart';

void main() {
  setUp(() => pdfrxInitialize());

  test('widget 層預設翻頁模式為連續捲動（保護既有 PdfReaderView 測試；產品預設由 ReaderScreen 傳入）', () {
    final view = PdfReaderView(
      filePath: 'test/fixtures/sample.pdf',
      onPageRendered: () {},
      onError: (_) {},
    );

    expect(view.pdfPageTurnMode, PdfPageTurnMode.scroll);
  });

  testWidgets('本機路徑開書成功，觸發 onPageRendered，不觸發 onError',
      (tester) async {
    var renderedCount = 0;
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (msg) => errorMessage = msg,
        ),
      ),
    );

    // pdfrx 開書為非同步流程，須讓多輪 microtask/frame 有機會完成。
    await pumpUntilPdfReady(
      tester,
      condition: () => renderedCount != 0 || errorMessage != null,
    );

    expect(renderedCount, 1);
    expect(errorMessage, isNull);
  });

  testWidgets(
      '開啟不存在的檔案，觸發 onError（固定在地化訊息，不含原始例外文字）、'
      '不觸發 onPageRendered，例外細節寫入 Console Log', (tester) async {
    ReaderConsoleLog.clear();
    var renderedCount = 0;
    String? errorMessage;

    await pumpLocalizedWidget(
      tester,
      PdfReaderView(
        filePath: 'test/fixtures/does_not_exist.pdf',
        onPageRendered: () => renderedCount++,
        onError: (msg) => errorMessage = msg,
      ),
    );

    await pumpUntilPdfReady(
      tester,
      condition: () => renderedCount != 0 || errorMessage != null,
    );

    expect(errorMessage, '無法載入書籍');
    expect(renderedCount, 0);
    expect(
      ReaderConsoleLog.entries.value.last,
      contains('_openDocument 失敗'),
    );
  });

  testWidgets('英文介面下，開檔失敗顯示英文固定訊息', (tester) async {
    var renderedCount = 0;
    String? errorMessage;

    await pumpLocalizedWidget(
      tester,
      PdfReaderView(
        filePath: 'test/fixtures/does_not_exist.pdf',
        onPageRendered: () => renderedCount++,
        onError: (msg) => errorMessage = msg,
      ),
      locale: const Locale('en'),
    );

    await pumpUntilPdfReady(
      tester,
      condition: () => renderedCount != 0 || errorMessage != null,
    );

    expect(errorMessage, 'Failed to load book');
  });

  testWidgets('pageCount／jumpToPage 正確運作，超界跳頁夾到最後一頁', (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final degraded = <NavigationDegradedReason>[];
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
          onNavigationDegraded: degraded.add,
        ),
      ),
    );

    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
    expect(renderedCount, 1);
    expect(lastPageInfo?.totalPages, 5);
    expect(lastPageInfo?.pageIndex, 0);

    // 跳到最後一頁（0-indexed 第 4 頁 = fixture 第 5 頁）。
    PdfReaderView.jumpToPage(key, 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 4);
    expect(degraded, isEmpty);

    // 超界跳頁夾到最後一頁，不拋例外，通知一次 annotation。
    PdfReaderView.jumpToPage(key, 999);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 4);
    expect(degraded, [NavigationDegradedReason.annotation]);
  });

  group('PDF 降級（Issue 6）', () {
    testWidgets('開書初始頁碼超出總頁數：開在最後一頁並通知一次 readingPosition', (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final degraded = <NavigationDegradedReason>[];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            initialPageIndex: 99,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
            onNavigationDegraded: degraded.add,
          ),
        ),
      );

      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(lastPageInfo?.pageIndex, 4);
      expect(degraded, [NavigationDegradedReason.readingPosition]);
    });

    testWidgets('開書初始頁碼剛好等於總頁數（off-by-one）：視為超界降級', (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final degraded = <NavigationDegradedReason>[];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            initialPageIndex: 5,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
            onNavigationDegraded: degraded.add,
          ),
        ),
      );

      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      await tester.pump();
      expect(lastPageInfo?.pageIndex, 4);
      expect(degraded, [NavigationDegradedReason.readingPosition]);
    });

    testWidgets('開書初始頁碼為最後一頁或 0 或未提供：不降級、不通知', (tester) async {
      for (final initialIndex in [4, 0, null]) {
        var renderedCount = 0;
        final degraded = <NavigationDegradedReason>[];

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PdfReaderView(
              filePath: 'test/fixtures/sample_multi_page.pdf',
              initialPageIndex: initialIndex,
              onPageRendered: () => renderedCount++,
              onError: (_) {},
              onNavigationDegraded: degraded.add,
            ),
          ),
        );

        await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
        await tester.pump();
        expect(degraded, isEmpty, reason: 'initialPageIndex: $initialIndex 不應觸發降級');
      }
    });

    testWidgets('跳頁超界：夾到最後一頁、跳頁並通知一次 annotation', (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final degraded = <NavigationDegradedReason>[];
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
            onNavigationDegraded: degraded.add,
          ),
        ),
      );

      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      PdfReaderView.jumpToPage(key, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastPageInfo?.pageIndex, 1);
      expect(degraded, isEmpty);

      PdfReaderView.jumpToPage(key, 999);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastPageInfo?.pageIndex, 4);
      expect(degraded, [NavigationDegradedReason.annotation]);
    });

    testWidgets('跳頁頁碼剛好等於總頁數：降級；等於最後一頁：不降級', (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final degraded = <NavigationDegradedReason>[];
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
            onNavigationDegraded: degraded.add,
          ),
        ),
      );

      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

      // 跳到第 4 頁（最後一頁）：不降級
      PdfReaderView.jumpToPage(key, 4);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastPageInfo?.pageIndex, 4);
      expect(degraded, isEmpty);

      // 跳到第 5 頁（等於總頁數）：降級
      PdfReaderView.jumpToPage(key, 5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastPageInfo?.pageIndex, 4);
      expect(degraded, [NavigationDegradedReason.annotation]);
    });

    testWidgets('跳頁負數：靜默忽略，頁碼不變、不通知', (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final degraded = <NavigationDegradedReason>[];
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
            onNavigationDegraded: degraded.add,
          ),
        ),
      );

      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      expect(lastPageInfo?.pageIndex, 0);

      PdfReaderView.jumpToPage(key, -1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastPageInfo?.pageIndex, 0);
      expect(degraded, isEmpty);
    });

    testWidgets('跳頁有效頁碼：不通知', (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final degraded = <NavigationDegradedReason>[];
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
            onNavigationDegraded: degraded.add,
          ),
        ),
      );

      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

      PdfReaderView.jumpToPage(key, 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastPageInfo?.pageIndex, 2);
      expect(degraded, isEmpty);
    });

    testWidgets('jumpToPageAtRect 超界：跳到最後一頁、通知 annotation、不拋例外', (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final degraded = <NavigationDegradedReason>[];
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
            onNavigationDegraded: degraded.add,
          ),
        ),
      );

      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

      PdfReaderView.jumpToPageAtRect(
        key,
        999,
        const PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.5),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(lastPageInfo?.pageIndex, 4);
      expect(degraded, [NavigationDegradedReason.annotation]);
    });

    testWidgets('開書尚未完成時 didUpdateWidget 觸發重新錨定（超界初始頁碼）：整個開書只通知一次', (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final degraded = <NavigationDegradedReason>[];

      Widget build(DualPageMode mode) => MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PdfReaderView(
              filePath: 'test/fixtures/sample_multi_page.pdf',
              initialPageIndex: 99,
              dualPageMode: mode,
              onPageRendered: () => renderedCount++,
              onError: (_) {},
              onPageChanged: (info) => lastPageInfo = info,
              onNavigationDegraded: degraded.add,
            ),
          );

      await tester.pumpWidget(build(DualPageMode.never));
      // 文件尚未開完就切換雙頁，觸發 didUpdateWidget 的重新錨定
      await tester.pumpWidget(build(DualPageMode.always));

      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // 回歸守護：內部重新錨定不得額外發出 annotation 降級
      expect(degraded, [NavigationDegradedReason.readingPosition]);
      expect(lastPageInfo?.totalPages, 5);
    });

    testWidgets('開書初始頁碼為負數：開在第 0 頁、不通知、不拋例外', (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final degraded = <NavigationDegradedReason>[];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            initialPageIndex: -3,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
            onNavigationDegraded: degraded.add,
          ),
        ),
      );

      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(lastPageInfo?.pageIndex, 0);
      expect(degraded, isEmpty);
    });

    testWidgets('開書降級後再翻頁：不重複通知（只通知一次）', (tester) async {
      var renderedCount = 0;
      final degraded = <NavigationDegradedReason>[];
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            initialPageIndex: 99,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onNavigationDegraded: degraded.add,
          ),
        ),
      );

      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      await tester.pump();
      PdfReaderView.jumpToPage(key, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(degraded, [NavigationDegradedReason.readingPosition]);
    });

    testWidgets('降級通知排程後畫面被卸載：不呼叫回呼、不拋例外', (tester) async {
      var renderedCount = 0;
      final degraded = <NavigationDegradedReason>[];
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onNavigationDegraded: degraded.add,
          ),
        ),
      );

      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

      // 跳頁後在 postFrameCallback 執行前立刻卸載畫面
      PdfReaderView.jumpToPage(key, 999);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(degraded, isEmpty);
    });
  });

  testWidgets('content:// URI 路徑觸發 openCustom 分支（無 mock channel 時安全失敗，不當成本機路徑處理）',
      (tester) async {
    var renderedCount = 0;
    String? errorMessage;

    await pumpLocalizedWidget(
      tester,
      PdfReaderView(
        filePath: 'content://com.example.provider/document/42',
        onPageRendered: () => renderedCount++,
        onError: (msg) => errorMessage = msg,
      ),
    );

    await pumpUntilPdfReady(
      tester,
      condition: () => renderedCount != 0 || errorMessage != null,
    );

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

    const channel = MethodChannel('elinkbook/reader_resources_cache');
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          filePath: 'content://com.example.provider/document/42',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );

    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
