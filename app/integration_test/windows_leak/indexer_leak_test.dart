// 全文索引器整本回傳記憶體驗證（epic-66 Issue 3 Task 3）。
//
// 在同一 App 程序內重複對 224 MB 大檔 EPUB 執行全文索引，
// 觀察私有記憶體（Private Bytes）與 WebView2 子程序記憶體變化。
//
// 執行方式（Windows）：
// cd app; flutter test integration_test/windows_leak/indexer_leak_test.dart -d windows

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/search/foliate_content_indexer.dart';
import 'package:elinkbook/windows/windows_webview_environment.dart';

import '../../test/windows_leak/leak_verdict.dart';
import 'leak_meter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Windows FoliateContentIndexer 重複索引大檔記憶體驗證',
    (tester) async {
      if (!File(kLargeEpubPath).existsSync()) {
        // ignore: avoid_print
        print('[leak] 找不到 $kLargeEpubPath，略過');
        return;
      }

      final appSupport = await getApplicationSupportDirectory();
      await initAppWebViewEnvironment(userDataFolder: appSupport.path);

      final book = Book(
        id: 'leak-test-indexer',
        title: 'AI世界的底層邏輯與生存法則',
        format: BookFileFormat.epub,
        filePath: kLargeEpubPath,
        source: BookSource.local,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );

      // 暖身（iter = 0）：排除首次初始化雜訊，作為後續增量比較之基線
      final sample0Before = await sampleMemory();
      logLeak('indexer', 0, 'before', sample0Before);

      final warmupSegments =
          await const FoliateContentIndexer().indexBook(book).toList();
      expect(warmupSegments, isNotEmpty, reason: '暖身索引應取得區段');

      final sample0AfterRun = await sampleMemory();
      logLeak('indexer', 0, 'after_run', sample0AfterRun);

      await Future<void>.delayed(const Duration(seconds: kSettleSeconds));
      final sample0AfterWait = await sampleMemory();
      logLeak('indexer', 0, 'after_wait', sample0AfterWait);

      final privateMbList = <double>[sample0AfterWait.privateMb];

      // 正式量測（iter = 1 ～ kIterations）
      for (var i = 1; i <= kIterations; i++) {
        final sampleBefore = await sampleMemory();
        logLeak('indexer', i, 'before', sampleBefore);

        final segments =
            await const FoliateContentIndexer().indexBook(book).toList();
        expect(segments, isNotEmpty, reason: '第 $i 次索引應取得區段');

        final sampleAfterRun = await sampleMemory();
        logLeak('indexer', i, 'after_run', sampleAfterRun);

        await Future<void>.delayed(const Duration(seconds: kSettleSeconds));
        final sampleAfterWait = await sampleMemory();
        logLeak('indexer', i, 'after_wait', sampleAfterWait);

        privateMbList.add(sampleAfterWait.privateMb);
      }

      // 計算洩漏判定
      final bookMb = bookSizeMb();
      final verdict = evaluateLeak(
        privateMb: privateMbList,
        bookMb: bookMb,
        thresholdRatio: 0.05,
      );

      // ignore: avoid_print
      print(
        '[leak-verdict] path=indexer leaked=${verdict.leaked} ratcheting=${verdict.ratcheting} deltas=${verdict.deltas} exceeded=${verdict.exceededIterations} threshold_mb=${verdict.thresholdMb.toStringAsFixed(2)}',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
