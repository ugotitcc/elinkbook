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
  // epic-67 Issue 5：精確定位（CFI）失效、已改用概略進度時回報。
  static const onNavigationDegraded = 'onNavigationDegraded';
  // epic-66 Issue 7：Windows WebView2 鍵盤事件轉送。
  static const onDesktopKey = 'onDesktopKey';

  /// main.js 會呼叫的全部處理器名稱。
  ///
  /// epic-66 Issue 8：Windows 外掛在 JS 呼叫 Dart 端沒登錄的處理器時，會直接
  /// 結束整個 App 程序（Android 不會）。新增常數時必須同時加進這份清單；
  /// `foliate_bridge_handlers_test.dart` 會對照 main.js 的實際呼叫。
  static const List<String> all = [
    onTableOfContentsReady,
    onTtsSegmentsReady,
    onTtsSegmentIndexReady,
    onPageRendered,
    onError,
    onTtsHighlightOutOfSafeWindow,
    onSelectionCleared,
    onSectionCountReady,
    onSegmentsForSectionReady,
    onLocatorChanged,
    onSelectionChanged,
    onNavigationDegraded,
    onDesktopKey,
  ];
}
