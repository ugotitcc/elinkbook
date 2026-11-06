import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面視窗全螢幕控制器的抽象介面。
///
/// 與實作（如 `window_manager` 外掛或測試替身）解耦，
/// 供全域快捷鍵與各畫面控制 Windows 視窗的全螢幕切換。
abstract class WindowFullscreenController {
  /// 當前全螢幕狀態的同步快取值。
  ///
  /// 用於 `_ExitFullscreenDismissAction.isEnabled` 等需要同步判斷的場景，
  /// 避免非同步呼叫在焦點樹評估時造成的延遲或不確定性。
  bool get isFullscreenNow;

  /// 非同步向視窗查詢真實全螢幕狀態，查到後同步更新快取 [isFullscreenNow]。
  Future<bool> isFullscreen();

  /// 設定視窗全螢幕模式，並同步更新 [isFullscreenNow]。
  Future<void> setFullscreen(bool isFullscreen);
}

/// 基於 `window_manager` 套件的正式 Windows 全螢幕控制器。
class WindowManagerFullscreenController
    with WindowListener
    implements WindowFullscreenController {
  bool _isFullscreen = false;

  /// 建構控制器並監聽視窗事件以維持同步快取。
  WindowManagerFullscreenController() {
    windowManager.addListener(this);
  }

  @override
  void onWindowEnterFullScreen() {
    _isFullscreen = true;
  }

  @override
  void onWindowLeaveFullScreen() {
    _isFullscreen = false;
  }

  @override
  bool get isFullscreenNow => _isFullscreen;

  @override
  Future<bool> isFullscreen() async {
    final status = await windowManager.isFullScreen();
    _isFullscreen = status;
    return status;
  }

  @override
  Future<void> setFullscreen(bool isFullscreen) async {
    await windowManager.setFullScreen(isFullscreen);
    _isFullscreen = isFullscreen;
  }
}

/// 當前運作中的全螢幕控制器實例。
///
/// 在 Windows 平台上於 `main()` 初始化後賦值；在非 Windows 平台或未初始化前為 `null`。
WindowFullscreenController? activeWindowFullscreenController;

bool _isToggling = false;

/// 切換視窗全螢幕狀態。
///
/// 讀取 `await controller.isFullscreen()` 後設為相反值。
/// 內建防重入旗標，在非同步切換尚未完成前直接忽略後續連按請求；
/// 控制器丟例外時吞掉（`debugPrint`），確保旗標在 `finally` 還原。
Future<void> toggleWindowFullscreen(
  WindowFullscreenController controller,
) async {
  if (_isToggling) return;
  _isToggling = true;
  try {
    final current = await controller.isFullscreen();
    await controller.setFullscreen(!current);
  } catch (e, st) {
    debugPrint('切換視窗全螢幕失敗: $e\n$st');
  } finally {
    _isToggling = false;
  }
}

/// 若當前處於全螢幕模式，則退出全螢幕。
///
/// - `controller.isFullscreenNow` 為 `false` 時回傳 `false` 且不呼叫 `setFullscreen`。
/// - 為 `true` 時受同一個進行中旗標保護呼叫 `setFullscreen(false)` 並回傳 `true`。
/// - 例外同樣吞掉（`debugPrint`）。
Future<bool> exitWindowFullscreenIfActive(
  WindowFullscreenController controller,
) async {
  if (_isToggling) return false;
  if (!controller.isFullscreenNow) {
    return false;
  }
  _isToggling = true;
  try {
    await controller.setFullscreen(false);
    return true;
  } catch (e, st) {
    debugPrint('退出視窗全螢幕失敗: $e\n$st');
    return false;
  } finally {
    _isToggling = false;
  }
}
