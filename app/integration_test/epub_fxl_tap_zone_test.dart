import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('固定版面 EPUB 開書後出現九宮格熱區，點擊皆不崩潰',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_fxl_tap_zone.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final capturedActions = <ZoneAction>[];

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          navZoneActions: const [
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ],
          onZoneAction: capturedActions.add,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');

    for (var i = 0; i < 9; i++) {
      expect(find.byKey(Key('nav_zone_$i')), findsOneWidget,
          reason: '固定版面書籍應已回報 isFixedLayout=true，九宮格熱區應已疊加');
    }

    await tester.tap(find.byKey(const Key('nav_zone_2'))); // nextPage
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊熱區換頁後不應觸發 onError');

    await tester.tap(find.byKey(const Key('nav_zone_0'))); // previousPage
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊熱區換頁後不應觸發 onError');

    await tester.tap(find.byKey(const Key('nav_zone_1'))); // menu
    await tester.pump();
    expect(capturedActions.contains(ZoneAction.menu), isTrue);
  });
}
