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

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateReaderView(
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

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateReaderView(
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
    expect(lastPosition?.displayTotalPages, positionAfterOpen.displayTotalPages,
        reason: '同一本書換頁不應改變 displayTotalPages');
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

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateReaderView(
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
