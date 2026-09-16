import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/foliate_bridge_handlers.dart';

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
    };

    expect(actual, expected);
  });

  test('11 個常數對應到 11 個相異字串，無重複值（防止複製貼上時誤用同一個字串）', () {
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
    };

    expect(values, hasLength(11));
  });
}
