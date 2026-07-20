import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 只比對 locator 的 href／progression 核心欄位，忽略 Readium 可能非同步
/// 補齊的 title/position/totalProgression 等中繼資料差異（真機驗證發現：
/// 同一位置的 locator 在導覽事件後續會被非同步豐富化，完整 JSON 字串相等
/// 比對會誤判為位置變動）。
bool _locatorCoreEquals(String? a, String? b) {
  if (a == null || b == null) return a == b;
  final decodedA = jsonDecode(a) as Map<String, dynamic>;
  final decodedB = jsonDecode(b) as Map<String, dynamic>;
  final locationsA = decodedA['locations'] as Map<String, dynamic>?;
  final locationsB = decodedB['locations'] as Map<String, dynamic>?;
  return decodedA['href'] == decodedB['href'] &&
      locationsA?['progression'] == locationsB?['progression'];
}

/// 與 [_locatorCoreEquals] 互補：判斷兩個 locator 的核心欄位（href／
/// progression）是否確實不同，而非僅是整串 JSON 位元組不同——避免 Readium
/// 非同步補齊中繼資料造成的「JSON 有差異」誤判為「位置真的變動」（同一份
/// locator 若只有 title/position/totalProgression 被非同步補齊，href／
/// progression 仍相同，不應視為換頁成功）。
bool _locatorPositionChanged(String? a, String? b) => !_locatorCoreEquals(a, b);

/// Epic 7 Issue 6：EPUB 流式熱區導覽（原生 InputListener）——真機整合測試。
///
/// 【本檔案與 PDF（epic-7-interaction Issue 4，pdf_nav_zone_test.dart）的
/// 差異】PDF 熱區疊加層曾經包住 AndroidView 的 GestureDetector，因 Flutter
/// 手勢競技場「先加入者贏」的仲裁規則導致 onTapUp 永遠不會觸發（見
/// issues.md Issue 4），該檔案因此完全放棄 tester.tap 模擬、改用
/// ReaderScreen.triggerZoneAction 繞開手勢模擬，實際熱區點擊改交由人工
/// 驗證。流式 EPUB 熱區完全由原生 Kotlin InputListener 處理（見
/// EpubReaderView.kt），Flutter 端沒有任何 GestureDetector 包住 AndroidView，
/// 不會遇到 PDF 那種特定的手勢競技場仲裁問題，因此本檔案改為直接嘗試
/// tester.tapAt() 對 AndroidView 所在螢幕座標送出真實觸控事件，觀察是否能
/// 觸達原生 InputListener（Issue 1 spike 已用 `adb shell input tap` 這種
/// OS 層級的觸控注入方式驗證過 InputListener 本身可靠攔截，但 Flutter
/// `tester.tapAt()` 屬於測試框架層級的觸控合成，是否對 Hybrid Composition
/// 下的 AndroidView 同樣可靠並未事先驗證，須靠本檔案的真機執行結果確認）。
///
/// 【若 tester.tapAt() 證實不可靠，改用以下人工驗證清單】比照
/// pdf_nav_zone_test.dart 既有先例，若下方任一測試在真機執行時斷言失敗
/// （locatorJson 未變動／onZoneTapped 未觸發），改用 Issue 1 spike 已驗證
/// 可靠的 `adb shell input tap <x> <y>` 直接對真機螢幕座標注入觸控（座標
/// 算法：畫面左 1/6 處＝上一頁、正中央＝選單、右 5/6 處＝下一頁，y 任取
/// 畫面垂直中點即可，見 reviews/spike-epub-inputlistener.md 座標換算方式），
/// 人工確認：
///   1. 依序點擊左/中/右三個位置，確認換頁與沉浸模式切換行為與
///      navZoneActions（本檔案採用預設 rightFlip 模板）一致。
///   2. 捲動翻頁模式（pageTurnMode=scroll）下，左右熱區點擊不應換頁，
///      中間選單熱區仍可正常觸發。
/// 並記錄實際觀察結果於 issues.md Issue 6 段落，比照 issues.md Issue 4
/// 「待辦」記錄慣例，不阻塞本 issue 合併。
///
/// 【實測結果記錄】本檔案已在真機（3CEF42ECD491687，Android 15/API 35）
/// 執行並通過 2/2：tester.tapAt() 對此原生 InputListener 路徑（無 Flutter
/// GestureDetector 包裹 AndroidView）確認可靠，上述人工驗證清單並未被觸發
/// 使用，保留於此僅供未來若真機環境改變、此技術不再可靠時的備援參考。
///
/// 【已知未涵蓋風險，待人工真機驗證，不阻塞本 issue 合併】本檔案與 Issue 1
/// spike 皆只用無註記（highlight/note）、無內部連結的純文字書驗證熱區點擊，
/// 未驗證「點擊既有劃線／備註標記」或「點擊 EPUB 內部連結（例如註腳）」時，
/// `EpubReaderView.kt` 的 `InputListener.onTap()` 是否會與 Readium 既有的
/// `DecorableNavigator.onDecorationActivated`／連結導覽事件同時觸發，造成
/// 「開啟標記編輯 Dialog／連結跳轉」與「翻頁」雙重動作。比照
/// epub_highlights_notes_test.dart 檔頭既有慣例（「點擊既有標記觸發
/// onAnnotationActivated」本來就已列為該檔案的真機人工驗證項目、非本 issue
/// 新增的缺口），此項一併列入人工驗證清單：開啟一本含既有劃線/備註/內部
/// 連結的流式 EPUB，分別點擊標記本身與連結，確認只觸發對應的單一動作
/// （標記編輯 Dialog 或連結跳轉），不應同時觸發熱區翻頁/選單切換；若發現
/// 雙重觸發，需在 `onTap()` 內先判斷該點是否落在 decoration/連結範圍，是則
/// `return false` 交由 Readium 自行處理。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '流式 EPUB 開書後，點擊左/右熱區真的換頁，點擊中間熱區觸發 onZoneTapped',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'epub_stream_nav_zone.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final capturedZoneTaps = <int>[];
    EpubPositionInfo? lastPosition;

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
          onLocatorChanged: (info) => lastPosition = info,
          // rightFlip 模板：左欄＝上一頁、中欄＝選單、右欄＝下一頁
          // （design.md 決策 #5），逐列重複 3 次填滿 9 格。
          navZoneActions: const [
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ],
          onZoneTapped: capturedZoneTaps.add,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');

    final topLeft = tester.getTopLeft(find.byType(EpubReaderView));
    final size = tester.getSize(find.byType(EpubReaderView));
    final rightZone = topLeft + Offset(size.width * 5 / 6, size.height / 2);
    final leftZone = topLeft + Offset(size.width / 6, size.height / 2);
    final menuZone = topLeft + Offset(size.width / 2, size.height / 2);

    final positionAfterOpen = lastPosition;
    expect(positionAfterOpen, isNotNull,
        reason: '開書後應已收到至少一次 onLocatorChanged，否則後續「位置有變動」'
            '斷言會在缺少真實基準值的情況下（_locatorPositionChanged 對 null '
            '基準恆回傳 true）產生假陽性');

    await tester.tapAt(rightZone);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊下一頁熱區後不應觸發 onError');
    expect(
      _locatorPositionChanged(
          lastPosition?.locatorJson, positionAfterOpen?.locatorJson),
      isTrue,
      reason: '點擊右側熱區應透過原生 InputListener 觸發 goForward()，'
          'href／progression 應變動；若本斷言失敗，代表 tester.tapAt() 對此原生 '
          'InputListener 路徑不可靠，需改依本檔案標頭註解的人工驗證清單改用 '
          'adb shell input tap 驗證，並記錄實際觀察結果於 issues.md。',
    );

    final positionAfterNext = lastPosition;

    await tester.tapAt(leftZone);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '點擊上一頁熱區後不應觸發 onError');
    expect(
      _locatorPositionChanged(
          lastPosition?.locatorJson, positionAfterNext?.locatorJson),
      isTrue,
      reason: '點擊左側熱區應觸發 goBackward()，href／progression 應變動',
    );

    await tester.tapAt(menuZone);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      capturedZoneTaps,
      contains(4),
      reason: '點擊螢幕正中央應落在九宮格中間列（非頂列），即 index 4，'
          '應透過 onZoneTapped(cellIndex: 4) 回呼通知 Dart 端',
    );
  });

  testWidgets(
      '捲動翻頁模式（pageTurnMode=scroll）下，左右熱區失效但選單格仍可用'
      '（design.md 決策 #15）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub',
        'epub_stream_nav_zone_scroll.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final capturedZoneTaps = <int>[];
    EpubPositionInfo? lastPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          pageTurnMode: PageTurnMode.scroll,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          onLocatorChanged: (info) => lastPosition = info,
          navZoneActions: const [
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ],
          onZoneTapped: capturedZoneTaps.add,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');

    final topLeft = tester.getTopLeft(find.byType(EpubReaderView));
    final size = tester.getSize(find.byType(EpubReaderView));
    final rightZone = topLeft + Offset(size.width * 5 / 6, size.height / 2);
    final menuZone = topLeft + Offset(size.width / 2, size.height / 2);

    final positionAfterOpen = lastPosition;

    await tester.tapAt(rightZone);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(errorMessage, isNull, reason: '捲動模式下點擊右側熱區不應觸發 onError');
    expect(
      _locatorCoreEquals(lastPosition?.locatorJson, positionAfterOpen?.locatorJson),
      isTrue,
      reason: '捲動翻頁模式下右側熱區（下一頁）應失效，href／progression 不應變動'
          '（design.md 決策 #15；Readium 可能非同步補齊 title/position/'
          'totalProgression 等中繼資料，故不比對完整 JSON 字串相等）',
    );

    await tester.tapAt(menuZone);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      capturedZoneTaps,
      contains(4),
      reason: '點擊螢幕正中央應落在九宮格中間列（非頂列），即 index 4，'
          '捲動模式下選單格仍應正常觸發 onZoneTapped(cellIndex: 4)'
          '（design.md 決策 #15）',
    );
  });
}
