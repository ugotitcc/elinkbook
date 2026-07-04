import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/screens/library_screen.dart';

/// 持續 pump，直到 [condition] 成立或逾時。與 Issue 5 的
/// integration_test/reader_screen_test.dart 採用相同的手法：ReaderScreen
/// 對外只有 filePath 一個建構參數，onPageRendered/onError 是內部實作細節，
/// 因此用 Key 觀察渲染狀態是否轉換，而非直接掛 callback。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時（$timeout）：條件未成立');
    }
    await tester.pump(step);
  }
}

bool _loadingIndicatorGone() =>
    find.byKey(const Key('reader_loading_indicator')).evaluate().isEmpty;

/// 刪除 LibraryScreen 點擊範例書籍時，由 stageSampleBookFile() 複製到裝置
/// 暫存目錄中的檔案，避免測試殘留累積。
Future<void> _deleteStagedFile(String fileName) async {
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  if (await file.exists()) await file.delete();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('從書架點擊範例 EPUB 項目，導航至 ReaderScreen 且內容成功渲染',
      (tester) async {
    addTearDown(() => _deleteStagedFile('sample.epub'));

    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    await tester.tap(find.byKey(const Key('sample_book_sample.epub')));
    await tester.pumpAndSettle();

    expect(find.text('閱讀器'), findsOneWidget);

    // 與 Issue 5 的 reader_screen_test.dart 不同：這裡在檢查載入指示器前，
    // 多了一次 MaterialPageRoute 轉場的 pumpAndSettle()。實測發現在這台裝置
    // 上，範例 fixture 夠小、原生渲染夠快，pumpAndSettle() 有時會連同轉場
    // 動畫一起把非同步渲染也等完，導致「載入指示器仍存在」這個前置斷言在
    // 轉場完成後已經不成立（找到 0 個，而非預期的 1 個）——這是轉場+渲染
    // 兩段非同步工作疊加造成的真實時間競態，不是竄改測試放水。改為直接進入
    // 「等待載入指示器消失」，若指示器已消失（代表 pumpAndSettle 期間已經
    // 渲染完成）則迴圈條件從一開始就成立、不需要真的等待；若尚未渲染完成則
    // 正常等待。無論哪一種情況，若原生渲染真的完全沒有觸發（onPageRendered
    // 與 onError 皆未觸發），10 秒逾時後 _pumpUntil 仍會呼叫 fail()，測試依然
    // 會正確失敗——防止假陽性通過的保護仍然有效。
    //
    // 10 秒逾時：Readium 需非同步解析 EPUB 套件結構並啟動 WebView 導覽器，
    // 與 Issue 4/5 的整合測試採用相同的逾時時間。
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），'
            '但畫面顯示了錯誤');
  });

  testWidgets('從書架點擊範例 PDF 項目，導航至 ReaderScreen 且內容成功渲染',
      (tester) async {
    addTearDown(() => _deleteStagedFile('sample.pdf'));

    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    await tester.tap(find.byKey(const Key('sample_book_sample.pdf')));
    await tester.pumpAndSettle();

    expect(find.text('閱讀器'), findsOneWidget);

    // 見上一項測試的說明：轉場 pumpAndSettle() 可能已連同渲染一起等完，故
    // 不在此斷言載入指示器仍存在；逾時保護（見下方）足以捕捉「完全沒有
    // 觸發渲染」的情況。
    //
    // 5 秒逾時：PdfRenderer 為同步點陣圖渲染，與 Issue 3/5 的整合測試採用
    // 相同的逾時時間。
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 5),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），'
            '但畫面顯示了錯誤');
  });
}
