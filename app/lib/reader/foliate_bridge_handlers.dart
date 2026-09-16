/// JS→Dart `callHandler()` 的 handler name 常數（Epic 43 Issue 4）。
/// main.js 端呼叫 callHandler() 時的字串字面值本身不受此常數約束
/// （vendor 檔案，不改動），僅收斂 Dart 端 register()/request()/
/// addJavaScriptHandler() 的重複字串常值。
abstract final class FoliateBridgeHandlers {
  static const onTableOfContentsReady = 'onTableOfContentsReady';
  static const onTtsSegmentsReady = 'onTtsSegmentsReady';
  static const onTtsSegmentIndexReady = 'onTtsSegmentIndexReady';
  static const onPageRendered = 'onPageRendered';
  static const onError = 'onError';
  static const onTtsHighlightOutOfSafeWindow =
      'onTtsHighlightOutOfSafeWindow';
  static const onSelectionCleared = 'onSelectionCleared';
  static const onSectionCountReady = 'onSectionCountReady';
  // I-1（審查修訂）：原稿遺漏的 3 個 handler。
  static const onSegmentsForSectionReady = 'onSegmentsForSectionReady';
  static const onLocatorChanged = 'onLocatorChanged';
  static const onSelectionChanged = 'onSelectionChanged';
}
