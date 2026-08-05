import 'package:flutter/foundation.dart';

/// 閱讀器 WebView 診斷用 Console Log 緩衝區（epic-18-reader-device-qa
/// Issue 33，真機使用回報：iReader Ocean 4 Plus 開啟書籍時畫面永遠停在
/// 轉圈圈，這台裝置的 WebView 建置沒有開啟 `setWebContentsDebuggingEnabled`，
/// 無法透過 `chrome://inspect` 遠端除錯）。捕捉 `InAppWebView` 的
/// `onConsoleMessage`，供使用者從「設定」畫面檢視／截圖回報。
///
/// 純記憶體內緩衝區，App 程序存活期間有效，不落地持久化——這是即時診斷
/// 工具，不是長期日誌系統。上限 [_maxEntries] 筆，超過時捨棄最舊的，
/// 避免長時間閱讀後無限制佔用記憶體。
class ReaderConsoleLog {
  ReaderConsoleLog._();

  static const int _maxEntries = 500;

  static final ValueNotifier<List<String>> entries =
      ValueNotifier<List<String>>(const []);

  static void add(String message) {
    final updated = List<String>.of(entries.value)..add(message);
    if (updated.length > _maxEntries) {
      updated.removeRange(0, updated.length - _maxEntries);
    }
    entries.value = updated;
  }

  static void clear() {
    entries.value = const [];
  }
}
