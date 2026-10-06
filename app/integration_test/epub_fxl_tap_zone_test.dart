import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/zone_action.dart';
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

  testWidgets(
      '固定版面 EPUB 開書後出現九宮格熱區，點擊各格觸發對應動作且真的換頁/'
      '「無動作」格仍攔截觸控不崩潰',
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
    EpubPositionInfo? lastPosition;
    final key = GlobalKey<State<FoliateReaderView>>();

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
        // 涵蓋 previousPage／menu／nextPage／none 四種動作，其中 index 3
        // 為 none（design.md 決策 #17：無動作格仍應攔截觸控，只是不做事）。
        navZoneActions: const [
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.none, ZoneAction.menu, ZoneAction.none,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
        ],
        onZoneAction: (action) {
          capturedActions.add(action);
          // 模擬 ReaderScreen._handleZoneAction 的實際分派邏輯（本測試直接
          // 建構 FoliateReaderView，不經過 ReaderScreen，故在此手動呼叫，
          // 讓換頁動作真的觸發原生端渲染，而非只驗證回呼有沒有被呼叫）。
          switch (action) {
            case ZoneAction.previousPage:
              FoliateReaderView.previousPage(key);
              break;
            case ZoneAction.nextPage:
              FoliateReaderView.nextPage(key);
              break;
            case ZoneAction.menu:
            case ZoneAction.none:
              break;
          }
        },
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');

    for (var index = 0; index < 9; index++) {
      expect(find.byKey(Key('nav_zone_$index')), findsOneWidget,
          reason: '固定版面書籍應已回報 isFixedLayout=true，九宮格熱區應已疊加');
    }

    final positionAfterOpen = lastPosition;

    await tester.tap(find.byKey(const Key('nav_zone_2'))); // index 2 = nextPage
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊下一頁熱區後不應觸發 onError');
    expect(capturedActions.last, ZoneAction.nextPage);
    expect(lastPosition?.locatorJson, isNot(equals(positionAfterOpen?.locatorJson)),
        reason: '點擊下一頁熱區應真的觸發原生端換頁，locatorJson 應變動');

    await tester.tap(find.byKey(const Key('nav_zone_0'))); // index 0 = previousPage
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊上一頁熱區後不應觸發 onError');
    expect(capturedActions.last, ZoneAction.previousPage);

    await tester.tap(find.byKey(const Key('nav_zone_1'))); // index 1 = menu
    await tester.pump();
    expect(capturedActions.last, ZoneAction.menu,
        reason: '點擊選單熱區應回報 ZoneAction.menu');

    await tester.tap(find.byKey(const Key('nav_zone_3'))); // index 3 = none
    await tester.pump();
    expect(errorMessage, isNull, reason: '點擊無動作熱區不應觸發 onError 或崩潰');
    expect(capturedActions.last, ZoneAction.none,
        reason: '無動作格仍應攔截觸控並回報 none（並非完全無反應／穿透到底層 '
            'WebView，design.md 決策 #17）');
  });
}
