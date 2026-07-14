import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
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

  testWidgets('固定版面 EPUB 開書後出現三欄熱區，點擊左/右/中皆不崩潰',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_fxl_tap_zone.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    var toggleCount = 0;

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
          onToggleFixedLayoutControls: () => toggleCount++,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');

    expect(find.byKey(const Key('epub_fxl_tap_zone_previous')), findsOneWidget,
        reason: '固定版面書籍應已回報 isFixedLayout=true，三欄熱區應已疊加');
    expect(find.byKey(const Key('epub_fxl_tap_zone_next')), findsOneWidget);
    expect(
      find.byKey(const Key('epub_fxl_tap_zone_toggle_controls')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_next')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊右熱區換頁後不應觸發 onError');

    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_previous')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊左熱區換頁後不應觸發 onError');

    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_toggle_controls')));
    await tester.pump();
    expect(toggleCount, 1, reason: '點擊中間熱區應觸發 onToggleFixedLayoutControls');
  });
}
