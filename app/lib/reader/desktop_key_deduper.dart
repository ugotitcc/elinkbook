import 'package:clock/clock.dart';
import 'package:flutter/services.dart';

/// 鍵盤事件來源：Flutter 原生鍵盤事件或 WebView2 (web) 轉送事件。
enum DesktopKeySource { flutter, web }

/// 桌面端按鍵去重器（epic-66 Issue 7 方案 B）。
///
/// 當 WebView2 與 Flutter 端同時交付鍵盤事件時，同一個按鍵在 50ms 內由另一個
/// 來源送達時將被擋下（去重），避免例如翻兩頁或全螢幕切換兩次的情況。同一來源的
/// 連續呼叫（如使用者按住按鍵不放產生的 key repeat）則永遠放行。
class DesktopKeyDeduper {
  DesktopKeyDeduper({int Function()? nowMs})
      : _nowMs = nowMs ?? _defaultNowMs;

  int Function() _nowMs;

  static int _defaultNowMs() => clock.now().millisecondsSinceEpoch;

  String? _lastKeyId;
  DesktopKeySource? _lastSource;
  int? _lastHandledAtMs;

  /// 同一個 [keyId] 若在 50 毫秒內已由另一個 [source] 處理過就回傳 `false`；
  /// 同一 [source] 的連續呼叫（按住不放／連續點擊）永遠回傳 `true`；
  /// 回傳 `true` 時記錄 `(keyId, source, 時間)`。
  bool shouldHandle(String keyId, DesktopKeySource source) {
    final now = _nowMs();
    if (_lastKeyId == keyId &&
        _lastSource != null &&
        _lastSource != source &&
        _lastHandledAtMs != null &&
        (now - _lastHandledAtMs!) < 50) {
      return false;
    }
    _lastKeyId = keyId;
    _lastSource = source;
    _lastHandledAtMs = now;
    return true;
  }

  void reset({int Function()? nowMs}) {
    _lastKeyId = null;
    _lastSource = null;
    _lastHandledAtMs = null;
    _nowMs = nowMs ?? _defaultNowMs;
  }
}

/// 全域共用的鍵盤去重器實例。
final DesktopKeyDeduper desktopKeyDeduper = DesktopKeyDeduper();

/// 將 [LogicalKeyboardKey] 轉換為規範化字串表示（供去重器比對）。
String canonicalKeyId(LogicalKeyboardKey key) => key.keyId.toString();

/// 將瀏覽器 KeyboardEvent.key 字串映射至 Flutter [LogicalKeyboardKey]。
///
/// 支援箭頭鍵、翻頁鍵、空白鍵、Home/End、F11、Escape，以及不分大小寫的 'f'/'F'
/// （以容納 CapsLock 啟動時的 Ctrl+F）。其餘未知按鍵回傳 null。
LogicalKeyboardKey? logicalKeyForWebKey(String key) {
  switch (key) {
    case 'ArrowLeft':
      return LogicalKeyboardKey.arrowLeft;
    case 'ArrowRight':
      return LogicalKeyboardKey.arrowRight;
    case 'ArrowUp':
      return LogicalKeyboardKey.arrowUp;
    case 'ArrowDown':
      return LogicalKeyboardKey.arrowDown;
    case 'PageUp':
      return LogicalKeyboardKey.pageUp;
    case 'PageDown':
      return LogicalKeyboardKey.pageDown;
    case ' ':
      return LogicalKeyboardKey.space;
    case 'Home':
      return LogicalKeyboardKey.home;
    case 'End':
      return LogicalKeyboardKey.end;
    case 'F11':
      return LogicalKeyboardKey.f11;
    case 'Escape':
      return LogicalKeyboardKey.escape;
    case 'f':
    case 'F':
      return LogicalKeyboardKey.keyF;
    default:
      return null;
  }
}
