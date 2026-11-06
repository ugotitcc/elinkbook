import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/foliate_bridge_handlers.dart';
import 'package:elinkbook/search/foliate_content_indexer.dart';

void main() {
  // M-4（審查修訂）：純靜態分析無法檢驗字串值本身有沒有筆誤（例如把
  // 'onPageRendered' 手滑打成 'onPageRenderd'），這是全專案唯一會實際
  // 比對這些字串內容的測試——main.js 端呼叫 callHandler('...') 的對應
  // 字串必須與這裡逐字相符，任一邊筆誤都只會在執行期靜默逾時（見
  // js_bridge_gateway.dart 既有註解），型別系統攔不到。
  test('每個常數值皆與預期字串完全相符', () {
    const expected = <String, String>{
      'onTableOfContentsReady': 'onTableOfContentsReady',
      'onTtsSegmentsReady': 'onTtsSegmentsReady',
      'onTtsSegmentIndexReady': 'onTtsSegmentIndexReady',
      'onPageRendered': 'onPageRendered',
      'onError': 'onError',
      'onTtsHighlightOutOfSafeWindow': 'onTtsHighlightOutOfSafeWindow',
      'onSelectionCleared': 'onSelectionCleared',
      'onSectionCountReady': 'onSectionCountReady',
      'onSegmentsForSectionReady': 'onSegmentsForSectionReady',
      'onLocatorChanged': 'onLocatorChanged',
      'onSelectionChanged': 'onSelectionChanged',
      'onNavigationDegraded': 'onNavigationDegraded',
      'onDesktopKey': 'onDesktopKey',
    };
    const actual = <String, String>{
      'onTableOfContentsReady': FoliateBridgeHandlers.onTableOfContentsReady,
      'onTtsSegmentsReady': FoliateBridgeHandlers.onTtsSegmentsReady,
      'onTtsSegmentIndexReady': FoliateBridgeHandlers.onTtsSegmentIndexReady,
      'onPageRendered': FoliateBridgeHandlers.onPageRendered,
      'onError': FoliateBridgeHandlers.onError,
      'onTtsHighlightOutOfSafeWindow':
          FoliateBridgeHandlers.onTtsHighlightOutOfSafeWindow,
      'onSelectionCleared': FoliateBridgeHandlers.onSelectionCleared,
      'onSectionCountReady': FoliateBridgeHandlers.onSectionCountReady,
      'onSegmentsForSectionReady':
          FoliateBridgeHandlers.onSegmentsForSectionReady,
      'onLocatorChanged': FoliateBridgeHandlers.onLocatorChanged,
      'onSelectionChanged': FoliateBridgeHandlers.onSelectionChanged,
      'onNavigationDegraded': FoliateBridgeHandlers.onNavigationDegraded,
      'onDesktopKey': FoliateBridgeHandlers.onDesktopKey,
    };

    expect(actual, expected);
  });

  test('13 個常數對應到 13 個相異字串，無重複值（防止複製貼上時誤用同一個字串）', () {
    const values = <String>{
      FoliateBridgeHandlers.onTableOfContentsReady,
      FoliateBridgeHandlers.onTtsSegmentsReady,
      FoliateBridgeHandlers.onTtsSegmentIndexReady,
      FoliateBridgeHandlers.onPageRendered,
      FoliateBridgeHandlers.onError,
      FoliateBridgeHandlers.onTtsHighlightOutOfSafeWindow,
      FoliateBridgeHandlers.onSelectionCleared,
      FoliateBridgeHandlers.onSectionCountReady,
      FoliateBridgeHandlers.onSegmentsForSectionReady,
      FoliateBridgeHandlers.onLocatorChanged,
      FoliateBridgeHandlers.onSelectionChanged,
      FoliateBridgeHandlers.onNavigationDegraded,
      FoliateBridgeHandlers.onDesktopKey,
    };

    expect(values, hasLength(13));
  });

  // epic-66 Issue 8：Windows 外掛在 JS 呼叫「Dart 端沒登錄的處理器」時會直接
  // 結束整個 App 程序（Android 不會）。main.js 呼叫的每個處理器名稱都必須在
  // [FoliateBridgeHandlers.all]，新增呼叫卻忘了登錄就會讓此測試變紅。
  test('FoliateBridgeHandlers.all 等於 main.js 實際呼叫的處理器名稱集合', () {
    final js = File('android/app/src/main/assets/foliate/main.js')
        .readAsStringSync();
    final called = RegExp(r'''callHandler\(\s*['"](\w+)['"]''')
        .allMatches(js)
        .map((m) => m.group(1)!)
        .toSet();
    expect(called, isNotEmpty);
    expect(FoliateBridgeHandlers.all.toSet(), called);
    expect(FoliateBridgeHandlers.all.length, called.length,
        reason: 'all 不可有重複名稱');
  });

  // epic-66 Issue 8：索引器自己處理的 4 個之外，其餘都要登錄空處理器。
  test('索引器的空處理器名稱 = all 扣掉索引器自己處理的 4 個', () {
    final noop = foliateIndexerNoopHandlerNames();
    expect(noop.toSet().intersection(foliateIndexerHandledHandlerNames),
        isEmpty);
    expect(noop.toSet().union(foliateIndexerHandledHandlerNames),
        FoliateBridgeHandlers.all.toSet());
    expect(noop, contains(FoliateBridgeHandlers.onLocatorChanged),
        reason: '實測漏登錄 onLocatorChanged 會讓 Windows App 消失');
  });
}
