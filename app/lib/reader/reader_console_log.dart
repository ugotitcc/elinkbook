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
///
/// 每一筆都會在開頭自動加上手機時鐘的時間戳（`HH:mm:ss.SSS `），讓使用者回報
/// 「幾點幾分出現異常」時，可以直接對應到日誌中的事件與先後順序（2026-09-24
/// 追查「換章節偶爾變雙欄」的競爭條件時，缺少時間就無法把畫面現象對回事件順序）。
/// 所有來源（WebView console、TTS、PDF、閱讀器）都經過 [add]，一處加上即全部生效，
/// 呼叫端與 JS 端都不需要各自處理時間。
class ReaderConsoleLog {
  ReaderConsoleLog._();

  static const int _maxEntries = 500;

  /// 取得目前時間的來源；測試可替換成固定時間以取得可預期的字串。
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static final ValueNotifier<List<String>> entries =
      ValueNotifier<List<String>>(const []);

  static void add(String message) {
    final updated = List<String>.of(entries.value)
      ..add('${_timestamp(clock())} $message');
    if (updated.length > _maxEntries) {
      updated.removeRange(0, updated.length - _maxEntries);
    }
    entries.value = updated;
  }

  static void clear() {
    entries.value = const [];
  }

  /// `HH:mm:ss.SSS`（24 小時制、含毫秒），毫秒精度足以分辨同一秒內的事件先後。
  static String _timestamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$ms';
  }
}
