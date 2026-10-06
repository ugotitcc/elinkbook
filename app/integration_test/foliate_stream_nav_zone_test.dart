import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
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

/// Epic 17 Issue 5：流式 EPUB（FoliateReaderView）3×3 導航熱區——真機
/// 整合測試。
///
/// 【與 epub_fxl_tap_zone_test.dart 的差異】FoliateReaderView 尚未有
/// onLocatorChanged（頁碼/定位回報是 Issue 6 的範圍），本檔案無法比對
/// locatorJson 變動來證實「真的換頁了」，只能驗證：熱區點擊確實觸發正確
/// 的 onZoneAction、換頁呼叫（FoliateReaderView.previousPage/
/// nextPage）送達原生端後不觸發 onError／不崩潰。實際換頁後畫面內容是否
/// 正確變動，留待人工於裝置畫面截圖確認（比照
/// foliate_epub_reader_view_test.dart「手動切換橫排→直排」測試既有的
/// 相同限制記錄慣例）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '流式 EPUB 開書後出現九宮格熱區，點擊各格觸發對應動作、'
      '「無動作」格仍攔截觸控不崩潰，previousPage/nextPage 換頁呼叫不觸發 onError',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub',
        'foliate_stream_nav_zone.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final capturedActions = <ZoneAction>[];
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
        // 涵蓋 previousPage／menu／nextPage／none 四種動作，其中 index 3
        // 為 none（比照 epub_fxl_tap_zone_test.dart 既有先例：無動作格
        // 仍應攔截觸控，只是不做事）。
        navZoneActions: const [
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.none, ZoneAction.menu, ZoneAction.none,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
        ],
        onZoneAction: (action) {
          capturedActions.add(action);
          // 模擬 ReaderScreen._handleZoneAction 的實際分派邏輯（本測試
          // 直接建構 FoliateReaderView，不經過 ReaderScreen，故在此
          // 手動呼叫，讓換頁動作真的送到原生端，而非只驗證回呼有沒有
          // 被呼叫，比照 epub_fxl_tap_zone_test.dart 既有模式）。
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
          reason: 'FoliateReaderView 的九宮格熱區疊加層應恆常顯示');
    }

    await tester.tap(find.byKey(const Key('nav_zone_2'))); // index 2 = nextPage
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊下一頁熱區後不應觸發 onError');
    expect(capturedActions.last, ZoneAction.nextPage);

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
        reason: '無動作格仍應攔截觸控並回報 none（不穿透到底層 WebView——若真的'
            '穿透，onZoneAction 閉包根本不會被呼叫，capturedActions 不會有'
            '新項目）');
  });
}
