import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<String> stagePath(String fileName) =>
      _stageAssetAsFile('test/fixtures/sample_dual_page.pdf', fileName);

  /// 建構 [PdfReaderView] 並等待 onPageRendered（原生端非同步開書完成），
  /// 把每次 onPageChanged 回報值收進 [pageChanges]。
  Future<void> pumpAndWaitRendered(
    WidgetTester tester,
    String path,
    List<int> pageChanges, {
    DualPageMode dualPageMode = DualPageMode.auto,
    bool dualPageCoverAlone = true,
    DualPageDirection dualPageDirection = DualPageDirection.ltr,
    bool isLandscape = false,
  }) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: path,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) => fail('不應觸發 onError：$message'),
          onPageChanged: pageChanges.add,
          dualPageMode: dualPageMode,
          dualPageCoverAlone: dualPageCoverAlone,
          dualPageDirection: dualPageDirection,
          isLandscape: isLandscape,
        ),
      ),
    );
    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('auto 模式橫向：預設封面獨立＋ltr 配對，往後翻步進符合 0→[1,2]→[3,4]',
      (tester) async {
    final path = await stagePath('sample_dual_page_auto.pdf');
    final pageChanges = <int>[];
    await pumpAndWaitRendered(tester, path, pageChanges, isLandscape: true);

    // 第 0 頁封面 -> 往後翻步進 1 到 [1,2]
    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1]);

    // [1,2] -> 再往後翻步進 2 到 [3,4]
    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1, 3]);
  });

  testWidgets('auto 模式橫向：從 [1,2] 往回翻正確回到封面（C-4 對稱規則，不崩潰）',
      (tester) async {
    final path = await stagePath('sample_dual_page_back.pdf');
    final pageChanges = <int>[];
    await pumpAndWaitRendered(tester, path, pageChanges, isLandscape: true);

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1]);

    // 從 [1,2] 往回翻 -> 回到封面 index 0
    await tester.drag(find.byType(PdfReaderView), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1, 0]);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('auto 模式橫向：最後一個 spread 落單時，繼續往後翻不越界、不崩潰',
      (tester) async {
    // sample_dual_page.pdf 共 6 頁：封面(0) -> [1,2] -> [3,4] -> [5] 落單
    // （另一側白色背景留白，見 Step 1「為何選 6 頁」說明）。
    final path = await stagePath('sample_dual_page_dangle.pdf');
    final pageChanges = <int>[];
    await pumpAndWaitRendered(tester, path, pageChanges, isLandscape: true);

    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
      await tester.pumpAndSettle();
    }
    expect(pageChanges, [1, 3, 5]); // 最後落在 index 5（落單）

    // 已達最後一個 spread，再往後翻應為 no-op（不越界、不再觸發 onPageChanged）
    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1, 3, 5]);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('always 模式：即使裝置為直向，仍一律雙頁（步進規則與橫向 auto 相同）',
      (tester) async {
    final path = await stagePath('sample_dual_page_always.pdf');
    final pageChanges = <int>[];
    await pumpAndWaitRendered(
      tester,
      path,
      pageChanges,
      dualPageMode: DualPageMode.always,
      isLandscape: false, // 直向，但 always 仍應強制雙頁
    );

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1]); // 封面 -> 步進 1，證明雙頁已生效

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1, 3]); // 步進 2，確認雙頁持續生效
  });

  testWidgets('never 模式：即使裝置為橫向，仍一律單頁（步進恆為 1）',
      (tester) async {
    final path = await stagePath('sample_dual_page_never.pdf');
    final pageChanges = <int>[];
    await pumpAndWaitRendered(
      tester,
      path,
      pageChanges,
      dualPageMode: DualPageMode.never,
      isLandscape: true, // 橫向，但 never 仍應強制單頁
    );

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1]);

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1, 2]); // 步進恆為 1，而非雙頁的 2
  });

  testWidgets(
      'auto 模式：裝置從橫向轉回直向時，恢復單頁步進（不觸發 onError，preferences 正確傳遞）',
      (tester) async {
    final path = await stagePath('sample_dual_page_rotate.pdf');
    final pageChanges = <int>[];
    final errors = <String>[];
    final completer = Completer<void>();

    Widget buildView(bool isLandscape) => MaterialApp(
          home: PdfReaderView(
            filePath: path,
            onPageRendered: () {
              if (!completer.isCompleted) completer.complete();
            },
            onError: errors.add,
            onPageChanged: pageChanges.add,
            dualPageMode: DualPageMode.auto,
            isLandscape: isLandscape,
          ),
        );

    await tester.pumpWidget(buildView(true)); // 橫向開書
    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1]); // 橫向：雙頁生效，封面步進 1

    // 轉回直向：isLandscape 由 true 變 false，透過 didUpdateWidget 觸發
    // setPdfPreferences。
    await tester.pumpWidget(buildView(false));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1, 2]); // 直向：單頁步進恢復為 1（index1 -> index2）

    expect(errors, isEmpty,
        reason: '旋轉切換不應觸發 onError；PlatformView 是否因旋轉重建屬 '
            'Issue 7 的真機視覺驗證範圍，本測試只驗證 preferences 傳遞路徑不出錯');
  });
}
