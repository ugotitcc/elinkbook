// 閱讀器開書整本回傳記憶體驗證（epic-66 Issue 3 Task 4）。
//
// 在同一 App 程序內重複以 FoliateReaderView 開啟 224 MB 大檔 EPUB，
// 關閉時卸載 Widget 並等待 6 秒回落，
// 觀察私有記憶體（Private Bytes）與 WebView2 子程序記憶體變化，
// 並確認 dispose 快取清理確實執行。
//
// 執行方式（Windows 桌面互動工作階段）：
// cd app; flutter test integration_test/windows_leak/reader_leak_test.dart -d windows

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/windows/windows_webview_environment.dart';

import '../../test/support/pump_localized_widget.dart';
import '../../test/windows_leak/leak_verdict.dart';
import 'leak_meter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Windows FoliateReaderView 重複開關大檔記憶體驗證',
    (tester) async {
      if (!File(kLargeEpubPath).existsSync()) {
        // ignore: avoid_print
        print('[leak] 找不到 $kLargeEpubPath，略過');
        return;
      }

      // 初始化 WebView2 環境（指定使用者資料夾至 %APPDATA%）
      final appSupport = await getApplicationSupportDirectory();
      await initAppWebViewEnvironment(userDataFolder: appSupport.path);

      final tempDir = await getTemporaryDirectory();
      final bookCacheDir = Directory(p.join(tempDir.path, 'book_cache'));

      // 輔助函式：掛載閱讀器、等待渲染完成、卸載、確認快取清理
      Future<void> runReaderCycle() async {
        final renderedCompleter = Completer<void>();

        await pumpLocalizedWidget(
          tester,
          FoliateReaderView(
            filePath: kLargeEpubPath,
            onPageRendered: () {
              if (!renderedCompleter.isCompleted) {
                renderedCompleter.complete();
              }
            },
            onError: (error) {
              if (!renderedCompleter.isCompleted) {
                renderedCompleter.completeError(
                  StateError('FoliateReaderView 開書失敗: $error'),
                );
              }
            },
          ),
        );

        // 等待 onPageRendered 被呼叫（上限 120 秒）
        await renderedCompleter.future.timeout(
          const Duration(seconds: 120),
          onTimeout: () => throw TimeoutException('等待 onPageRendered 超過 120 秒'),
        );

        // 卸載閱讀器 Widget
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        // 驗證 dispose 確實刪除本實例之快取子目錄
        if (bookCacheDir.existsSync()) {
          final entries = bookCacheDir.listSync();
          expect(
            entries,
            isEmpty,
            reason: '閱讀器卸載後 book_cache 子目錄應被完全清理',
          );
        }
      }

      // 暖身（iter = 0）：排除首次初始化雜訊，作為基線
      final sample0Before = await sampleMemory();
      logLeak('reader', 0, 'before', sample0Before);

      await runReaderCycle();

      final sample0AfterRun = await sampleMemory();
      logLeak('reader', 0, 'after_run', sample0AfterRun);

      await Future<void>.delayed(const Duration(seconds: kSettleSeconds));
      final sample0AfterWait = await sampleMemory();
      logLeak('reader', 0, 'after_wait', sample0AfterWait);

      final privateMbList = <double>[sample0AfterWait.privateMb];

      // 正式量測（iter = 1 ～ kIterations）
      for (var i = 1; i <= kIterations; i++) {
        final sampleBefore = await sampleMemory();
        logLeak('reader', i, 'before', sampleBefore);

        await runReaderCycle();

        final sampleAfterRun = await sampleMemory();
        logLeak('reader', i, 'after_run', sampleAfterRun);

        await Future<void>.delayed(const Duration(seconds: kSettleSeconds));
        final sampleAfterWait = await sampleMemory();
        logLeak('reader', i, 'after_wait', sampleAfterWait);

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
        '[leak-verdict] path=reader leaked=${verdict.leaked} ratcheting=${verdict.ratcheting} deltas=${verdict.deltas} exceeded=${verdict.exceededIterations} threshold_mb=${verdict.thresholdMb.toStringAsFixed(2)}',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
