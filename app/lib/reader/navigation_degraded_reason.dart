/// 精確定位（CFI）失效、已降級為概略進度的原因（epic-67 Issue 5）。
enum NavigationDegradedReason {
  /// 開書時，儲存的閱讀位置失效。
  readingPosition,

  /// 點擊書籤、劃線或備註跳轉時，其記錄的位置失效。
  annotation,
}

/// 解析 JS `onNavigationDegraded` handler 的參數；無法辨識時回傳 `null`，
/// 不拋例外（比照 `extractCfi()` 等橋接解析函式的優雅退回原則）。
NavigationDegradedReason? parseNavigationDegradedReason(List<dynamic> args) {
  if (args.isEmpty || args[0] is! String) return null;
  switch (args[0] as String) {
    case 'readingPosition':
      return NavigationDegradedReason.readingPosition;
    case 'annotation':
      return NavigationDegradedReason.annotation;
    default:
      return null;
  }
}
