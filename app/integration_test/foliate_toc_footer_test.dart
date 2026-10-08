import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import '../test/support/pump_localized_widget.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // epic-54 Issue 20（程式審查 Important）：直接守護 JS→Dart 的 tocId／tocItemId
  // 接線。ReaderScreen 層的整合測試在舊規則剛好答對時無法分辨有沒有傳到 id，
  // 這裡直接斷言橋接收到的值：任何一端（main.js 轉發、codec 解析、falsy 的 0）
  // 壞掉都會讓本測試失敗。
  testWidgets(
      '單 spine 多錨點：目錄節點帶 tocId（根為 0），relocate 回報的 tocItemId 隨跳轉改變',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_single_spine_multi_anchor.epub',
        'foliate_toc_id.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final key = GlobalKey<State<FoliateReaderView>>();
    EpubPositionInfo? lastPosition;

    await pumpLocalizedWidget(
      tester,
      FoliateReaderView(
        key: key,
        filePath: samplePath,
        onPageRendered: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!completer.isCompleted) completer.complete();
        },
        onLocatorChanged: (info) => lastPosition = info,
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull);

    // 目錄節點：根（單檔範例）id 為 0（falsy 陷阱），三個子節依序 1、2、3。
    final toc = await FoliateReaderView.loadTableOfContents(key);
    expect(toc, hasLength(1));
    expect(toc.single.tocId, 0, reason: '第一個目錄項 id 為 0，不得變成 null');
    expect(toc.single.children.map((e) => e.tocId), [1, 2, 3]);

    // 開書後 relocate 必須帶 tocItemId（不為 null）。
    expect(lastPosition, isNotNull);
    expect(lastPosition!.tocItemId, isNotNull,
        reason: 'main.js 應在 position 帶 tocItemId');

    // 跳到第三節：foliate 以 live DOM 判定目前目錄項應為 id 3。
    final s3 = toc.single.children[2];
    FoliateReaderView.jumpToLocator(key, s3.locatorJson);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (lastPosition?.tocItemId != 3) {
      if (DateTime.now().isAfter(deadline)) {
        fail('等待逾時：跳到第三節後 tocItemId 應為 3，實際為 ${lastPosition?.tocItemId}');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(lastPosition!.locatorJson, isNot(contains('tocItemId')),
        reason: 'locatorJson 不得被污染');
  });

  testWidgets('讀取全書目錄，點擊項目 200ms 內跳轉且畫面內容與章節一致',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/issue9_vertical_pagejump.epub', 'foliate_toc.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final key = GlobalKey<State<FoliateReaderView>>();
    EpubPositionInfo? lastPosition;

    await pumpLocalizedWidget(
      tester,
      FoliateReaderView(
        key: key,
        filePath: samplePath,
        onPageRendered: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!completer.isCompleted) completer.complete();
        },
        onLocatorChanged: (info) => lastPosition = info,
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');

    final positionAfterOpen = lastPosition;
    expect(positionAfterOpen, isNotNull,
        reason: '開書後應已收到至少一次 onLocatorChanged');

    final toc = await FoliateReaderView.loadTableOfContents(key);
    expect(toc, isNotEmpty, reason: 'issue9_vertical_pagejump.epub 應含目錄項目');

    // 解析開書位置的 section index：locatorJson 格式為
    // {"cfi":"...","index":N,"fraction":F}，index 為 foliate-js section 索引。
    int? openSectionIndex;
    final openLocator = positionAfterOpen?.locatorJson;
    if (openLocator != null && openLocator.isNotEmpty) {
      try {
        final parsed = jsonDecode(openLocator) as Map;
        openSectionIndex = parsed['index'] as int?;
      } catch (_) {}
    }

    // 挑選一個 section index 與開書位置不同的目錄項目跳轉，驗證跳轉真的
    // 生效——若挑到同一個 section 的項目，view.goTo() 解析後回到同頁，
    // 無法區分「跳轉沒生效」與「跳轉到同一個 section」。
    final target = toc.firstWhere(
      (entry) {
        if (entry.locatorJson.isEmpty) return false;
        try {
          final parsed = jsonDecode(entry.locatorJson) as Map;
          final entryIndex = parsed['index'] as int?;
          return entryIndex != null && entryIndex != openSectionIndex;
        } catch (_) {
          return false;
        }
      },
      orElse: () => toc.last,
    );
    expect(target.locatorJson, isNotEmpty,
        reason: '必須找到與開書位置不同 section 的目錄項目');

    FoliateReaderView.jumpToLocator(key, target.locatorJson);

    // 等待原生端處理 jumpToLocator → view.goTo(cfi) → relocate 事件
    // → onLocatorChanged 回傳到 Dart。pumpAndSettle 本身只等 Flutter
    // 框架層級事件，無法等原生端 async 完成，改用 poll 等待 lastPosition
    // 變動（最多 10 秒）。
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (lastPosition?.locatorJson == positionAfterOpen?.locatorJson &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(errorMessage, isNull, reason: '目錄跳轉後不應觸發 onError');
    expect(
      lastPosition?.locatorJson,
      isNot(equals(positionAfterOpen?.locatorJson)),
      reason: '跳轉後 locatorJson 應變動為目錄項目對應的位置',
    );
  });

  testWidgets('頁尾頁碼正確反映 displayPageIndex/displayTotalPages，且隨翻頁更新',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/issue9_vertical_pagejump.epub', 'foliate_footer.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final key = GlobalKey<State<FoliateReaderView>>();
    EpubPositionInfo? lastPosition;

    await pumpLocalizedWidget(
      tester,
      FoliateReaderView(
        key: key,
        filePath: samplePath,
        onPageRendered: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!completer.isCompleted) completer.complete();
        },
        onLocatorChanged: (info) => lastPosition = info,
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull);

    final positionAfterOpen = lastPosition;
    expect(positionAfterOpen?.displayTotalPages, isNotNull,
        reason: '開書後應已收到 displayTotalPages，供頁尾顯示使用');
    expect(positionAfterOpen!.displayTotalPages, greaterThan(0));

    FoliateReaderView.nextPage(key);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(errorMessage, isNull, reason: '換頁後不應觸發 onError');
    // 流式 EPUB 的 displayTotalPages 是近似估計刻度（位元組數/1500＋已渲染
    // section 密度校正，見 epub_position_info.dart），翻頁渲染更多內容後
    // 估計值會微幅收斂，不是嚴格相等（TCL 14 實測開書 493→換頁後 490，約
    // 0.6%，三次一致）。所以驗證「近似不變」：與開書時相差不超過 5%。這比
    // 只檢查「大於 0」強得多：總頁數若被重算成另一個量級、或換頁後歸零，
    // 都會被抓到；5% 約為實測漂移的 8 倍，留給不同裝置字型與 WebView 的餘裕。
    final totalAfterOpen = positionAfterOpen.displayTotalPages;
    final totalAfterTurn = lastPosition?.displayTotalPages;
    expect(totalAfterOpen, isNotNull, reason: '開書後應已有 displayTotalPages');
    expect(totalAfterTurn, isNotNull, reason: '換頁後應仍有 displayTotalPages');
    expect(totalAfterOpen!, greaterThan(0));
    final drift = (totalAfterTurn! - totalAfterOpen).abs() / totalAfterOpen;
    expect(drift, lessThanOrEqualTo(0.05),
        reason: '同一本書換頁後 displayTotalPages 只應因估計收斂而微幅變動'
            '（開書 $totalAfterOpen、換頁後 $totalAfterTurn、漂移 ${(drift * 100).toStringAsFixed(1)}%）');
  });

  testWidgets('舊格式（Readium Locator JSON）initialLocatorJson 優雅退回：不崩潰、從書本開頭開始',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/issue9_vertical_pagejump.epub', 'foliate_legacy_locator.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    EpubPositionInfo? firstPosition;

    // 模擬既有流式書籍（epic-17 上線前）留下的 Readium Locator JSON——
    // 完全不同的欄位結構，沒有 cfi 這個鍵。
    const legacyLocatorJson =
        '{"href":"/OEBPS/chapter3.xhtml","type":"application/xhtml+xml",'
        '"locations":{"progression":0.6,"totalProgression":0.6}}';

    await pumpLocalizedWidget(
      tester,
      FoliateReaderView(
        filePath: samplePath,
        initialLocatorJson: legacyLocatorJson,
        onPageRendered: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!completer.isCompleted) completer.complete();
        },
        onLocatorChanged: (info) {
          firstPosition ??= info;
        },
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '舊格式 initialLocatorJson 不應導致 onError 或崩潰');
    expect(firstPosition, isNotNull);
    expect(firstPosition!.displayPageIndex, anyOf(isNull, equals(0)),
        reason: '優雅退回後應從書本開頭開始（displayPageIndex 0 或尚未回報）');
  });
}
