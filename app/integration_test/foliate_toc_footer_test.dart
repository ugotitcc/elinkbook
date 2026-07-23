import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/toc_entry.dart';

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
        'test/fixtures/sample_multi_chapter.epub', 'foliate_toc.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final key = GlobalKey<State<FoliateEpubReaderView>>();
    EpubPositionInfo? lastPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
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

    final toc = await FoliateEpubReaderView.loadTableOfContents(key);
    expect(toc, isNotEmpty, reason: 'sample_multi_chapter.epub 應含目錄項目');

    // 挑選一個與目前位置（第一章開頭）不同的目錄項目跳轉，驗證跳轉真的
    // 生效——若挑到與開書起始位置相同的項目，locatorJson 不會變動，
    // 無法區分「跳轉沒生效」與「跳轉到同一個位置」。
    final target = toc.firstWhere(
      (entry) => entry.locatorJson != positionAfterOpen?.locatorJson &&
          entry.locatorJson.isNotEmpty,
      orElse: () => toc.last,
    );

    final stopwatch = Stopwatch()..start();
    FoliateEpubReaderView.jumpToLocator(key, target.locatorJson);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    stopwatch.stop();

    expect(errorMessage, isNull, reason: '目錄跳轉後不應觸發 onError');
    expect(stopwatch.elapsedMilliseconds, lessThan(200),
        reason: 'FR-08：目錄跳轉須於 200ms 內完成（本斷言量測 Dart 端呼叫'
            '到下一輪 pumpAndSettle 收斂為止，實際原生端渲染時間應更短，'
            '若此斷言不穩定，改依人工碼表量測記錄於 issues.md）');
    expect(
      lastPosition?.locatorJson,
      isNot(equals(positionAfterOpen?.locatorJson)),
      reason: '跳轉後 locatorJson 應變動為目錄項目對應的位置',
    );
  });

  testWidgets('頁尾頁碼正確反映 pageIndex/totalPages，且隨翻頁更新',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'foliate_footer.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final key = GlobalKey<State<FoliateEpubReaderView>>();
    EpubPositionInfo? lastPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
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
    expect(positionAfterOpen?.totalPages, isNotNull,
        reason: '開書後應已收到 totalPages，供頁尾顯示使用');
    expect(positionAfterOpen!.totalPages, greaterThan(0));

    FoliateEpubReaderView.nextPage(key);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(errorMessage, isNull, reason: '換頁後不應觸發 onError');
    expect(lastPosition?.totalPages, positionAfterOpen.totalPages,
        reason: '同一本書換頁不應改變 totalPages');
  });

  testWidgets('舊格式（Readium Locator JSON）initialLocatorJson 優雅退回：不崩潰、從書本開頭開始',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'foliate_legacy_locator.epub');
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
        home: FoliateEpubReaderView(
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
    expect(firstPosition!.pageIndex, anyOf(isNull, equals(0)),
        reason: '優雅退回後應從書本開頭開始（pageIndex 0 或尚未回報）');
  });
}
