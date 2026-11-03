import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/navigation_degraded_reason.dart';
import '../test/support/pump_localized_widget.dart';

/// epic-67 Issue 5：定位失效時的降級，必須在真實 WebView 驗證（一般 widget test
/// 的 WebView 是假的，觀察不到 JS 行為）。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('開書時 CFI 章節索引超界：不卡死、回報 readingPosition 降級', (tester) async {
    final path = await _stageAssetAsFile('test/fixtures/sample.epub', 'degrade_open.epub');
    addTearDown(() async {
      final f = File(path);
      if (await f.exists()) await f.delete();
    });

    final rendered = Completer<void>();
    final degraded = Completer<NavigationDegradedReason>();
    String? errorMessage;

    await pumpLocalizedWidget(
      tester,
      FoliateReaderView(
        filePath: path,
        initialLocatorJson: 'epubcfi(/6/400!/4/2)', // 章節索引遠超過 sample.epub 的章數
        initialProgression: 0.5,
        onPageRendered: () {
          if (!rendered.isCompleted) rendered.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!rendered.isCompleted) rendered.complete();
        },
        onNavigationDegraded: (reason) {
          if (!degraded.isCompleted) degraded.complete(reason);
        },
      ),
    );

    await rendered.future.timeout(const Duration(seconds: 15));
    expect(errorMessage, isNull, reason: '不得因定位失效而載入失敗：$errorMessage');
    expect(
      await degraded.future.timeout(const Duration(seconds: 5)),
      NavigationDegradedReason.readingPosition,
    );
  });

  testWidgets('開書後跳轉到失效 CFI：回報 annotation 降級', (tester) async {
    final path = await _stageAssetAsFile('test/fixtures/sample.epub', 'degrade_jump.epub');
    addTearDown(() async {
      final f = File(path);
      if (await f.exists()) await f.delete();
    });

    final key = GlobalKey<State<FoliateReaderView>>();
    final rendered = Completer<void>();
    final degraded = Completer<NavigationDegradedReason>();

    await pumpLocalizedWidget(
      tester,
      FoliateReaderView(
        key: key,
        filePath: path,
        onPageRendered: () {
          if (!rendered.isCompleted) rendered.complete();
        },
        onError: (_) {},
        onNavigationDegraded: (reason) {
          if (!degraded.isCompleted) degraded.complete(reason);
        },
      ),
    );
    await rendered.future.timeout(const Duration(seconds: 15));

    FoliateReaderView.jumpToLocator(
      key,
      'epubcfi(/6/400!/4/2)',
      fallbackProgression: 0.5,
    );

    expect(
      await degraded.future.timeout(const Duration(seconds: 5)),
      NavigationDegradedReason.annotation,
    );
  });
}
