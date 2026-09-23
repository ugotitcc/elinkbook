import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import '../support/pump_until_pdf_ready.dart';

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('不傳雙頁參數時，行為與 Issue 1 完全相同（零回歸基準）',
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
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    expect(renderedCount, 1);
    expect(lastPageInfo?.totalPages, 5);
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.jumpToPage(key, 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 4);

    PdfReaderView.jumpToPage(key, 999);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 4);
  });

  testWidgets('dualPageMode: never 時，行為與不傳參數完全相同',
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
          dualPageMode: DualPageMode.never,
          isLandscape: true, // never 模式下方向不應影響結果。
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    expect(lastPageInfo?.pageIndex, 0);
    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1); // 步進 1，非雙頁步進。
  });

  testWidgets('dualPageMode: always 時，開書後即套用雙頁版面（錨點頁仍為 0）',
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
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: true,
          dualPageDirection: DualPageDirection.ltr,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    // 封面獨立時第 0 頁本身即為一個完整 spread，錨點頁仍是 0——
    // 與單頁模式的初始狀態在「開書即在第 0 頁」這件事上一致，
    // 差異要到 nextPage（Task 6）才會顯現。
    expect(lastPageInfo?.pageIndex, 0);
  });

  testWidgets('雙頁模式下，跳到 spread 的右頁後，頁碼回報 spread 錨點頁',
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
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: true,
          dualPageDirection: DualPageDirection.ltr,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    // jumpToPage(2)：page 2 屬於 spread [1,2]，錨點頁為 1。
    PdfReaderView.jumpToPage(key, 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1, reason: '回報 spread 錨點頁，不是 2');
  });

  testWidgets('always + 封面獨立：翻頁以 spread 為單位，封面步進 1、之後步進 2',
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
          filePath: 'test/fixtures/sample_multi_page.pdf', // 5 頁。
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: true,
          dualPageDirection: DualPageDirection.ltr,
          isLandscape: false, // 證明 always 模式不看方向。
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 3);

    // 已在最後一個 spread，再次 nextPage 應 safe 忽略。
    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 3);
  });

  testWidgets('always + 封面獨立：previousPage 對稱回到封面', (tester) async {
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
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: true,
          dualPageDirection: DualPageDirection.ltr,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.jumpToPage(key, 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 3);

    PdfReaderView.previousPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);

    PdfReaderView.previousPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.previousPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 0);
  });

  testWidgets('always + 封面不獨立：步進恆為 2（6 頁 fixture）', (tester) async {
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
          filePath: 'test/fixtures/sample_dual_page.pdf', // 6 頁。
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: false,
          dualPageDirection: DualPageDirection.ltr,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
    expect(lastPageInfo?.totalPages, 6);
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 2);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 4);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 4);
  });

  testWidgets('auto + 直向：等同單頁模式，步進為 1', (tester) async {
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
          dualPageMode: DualPageMode.auto,
          isLandscape: false,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);
  });

  testWidgets('auto + 橫向：等同 always，步進與雙頁一致', (tester) async {
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
          dualPageMode: DualPageMode.auto,
          dualPageCoverAlone: true,
          isLandscape: true,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 3);
  });

  testWidgets('總頁數為偶數且封面獨立時，最後一頁單獨成為一個 spread',
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
          filePath: 'test/fixtures/sample_dual_page.pdf', // 6 頁。
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: true,
          dualPageDirection: DualPageDirection.ltr,
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    // spreads == [[0],[1,2],[3,4],[5]]，第 5 頁單獨成一組。
    PdfReaderView.jumpToPage(key, 5);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 5);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 5, reason: '已在最後一個 spread');

    PdfReaderView.previousPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 3);
  });

  testWidgets('RTL 與 LTR 產生鏡像版面，但頁碼回報序列完全相同', (tester) async {
    Future<List<int?>> runSequence(DualPageDirection direction) async {
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
            dualPageMode: DualPageMode.always,
            dualPageCoverAlone: true,
            dualPageDirection: direction,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        ),
      );
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      final sequence = <int?>[lastPageInfo?.pageIndex];
      PdfReaderView.nextPage(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      sequence.add(lastPageInfo?.pageIndex);
      PdfReaderView.nextPage(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      sequence.add(lastPageInfo?.pageIndex);
      return sequence;
    }

    final rtlSequence = await runSequence(DualPageDirection.rtl);
    await tester.pumpWidget(const SizedBox.shrink()); // 清空重來。
    final ltrSequence = await runSequence(DualPageDirection.ltr);

    expect(rtlSequence, [0, 1, 3]);
    expect(ltrSequence, [0, 1, 3]);
  });

  testWidgets('執行期由 always 切到 never，版面與步進回到單頁', (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    Widget buildView(DualPageMode mode) => MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            dualPageMode: mode,
            dualPageCoverAlone: true,
            dualPageDirection: DualPageDirection.ltr,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        );

    await tester.pumpWidget(buildView(DualPageMode.always));
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.jumpToPage(key, 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 3);

    await tester.pumpWidget(buildView(DualPageMode.never));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 兩層巢狀 addPostFrameCallback 需要額外的 frame 才能完成。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 4, reason: '切回單頁後步進應為 1');
  });

  testWidgets('auto 模式下執行期橫直向切換改變雙頁啟用狀態', (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    Widget buildView(bool isLandscape) => MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            dualPageMode: DualPageMode.auto,
            dualPageCoverAlone: true,
            dualPageDirection: DualPageDirection.ltr,
            isLandscape: isLandscape,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        );

    await tester.pumpWidget(buildView(true));
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);

    await tester.pumpWidget(buildView(false)); // 轉為直向。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 兩層巢狀 addPostFrameCallback 需要額外的 frame 才能完成。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 2, reason: '直向後步進應為 1（單頁）');
  });

  testWidgets('執行期切換 dualPageCoverAlone，翻頁配對規則正確反映新設定',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    Widget buildView(bool coverAlone) => MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_dual_page.pdf', // 6 頁。
            dualPageMode: DualPageMode.always,
            dualPageCoverAlone: coverAlone,
            dualPageDirection: DualPageDirection.ltr,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        );

    await tester.pumpWidget(buildView(true));
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1, reason: 'coverAlone=true，封面步進 1');

    await tester.pumpWidget(buildView(false)); // 執行期關閉封面獨立。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 兩層巢狀 addPostFrameCallback 需要額外的 frame 才能完成。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      lastPageInfo?.pageIndex,
      2,
      reason: 'coverAlone=false 後 spreads 變為 [0,1][2,3][4,5]，'
          '從錨點頁 0 出發下一步應到錨點頁 2',
    );
  });

  testWidgets('執行期切換 dualPageDirection，錨點頁步進序列不受影響（僅幾何鏡像）',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    Widget buildView(DualPageDirection direction) => MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            dualPageMode: DualPageMode.always,
            dualPageCoverAlone: true,
            dualPageDirection: direction,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        );

    await tester.pumpWidget(buildView(DualPageDirection.rtl));
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);

    await tester.pumpWidget(buildView(DualPageDirection.ltr)); // 執行期切換方向。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 兩層巢狀 addPostFrameCallback 需要額外的 frame 才能完成。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      lastPageInfo?.pageIndex,
      3,
      reason: '方向切換只影響左右鏡像幾何，錨點頁步進序列不變',
    );
  });

  testWidgets('文件載入完成前變更雙頁設定不會當機（isReady == false 防呆）',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    Widget buildView(bool isLandscape) => MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            dualPageMode: DualPageMode.auto,
            dualPageCoverAlone: true,
            dualPageDirection: DualPageDirection.ltr,
            isLandscape: isLandscape,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (_) {},
          ),
        );

    await tester.pumpWidget(buildView(true));
    // 刻意不呼叫 waitRendered：文件仍在非同步開啟中（_controller.isReady
    // 尚為 false，_document 仍是 null）時就觸發 didUpdateWidget，重現
    // Critical #1 的當機路徑。
    await tester.pumpWidget(buildView(false));
    await tester.pump();

    expect(tester.takeException(), isNull);

    // 讓文件真正開完，確認後續行為仍正常運作（非卡死狀態）。
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
    expect(renderedCount, 1);
  });
}
