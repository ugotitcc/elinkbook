import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'window_fullscreen_controller.dart';
import '../reader/desktop_key_deduper.dart';

/// 在 Windows 平台上提供 F11 切換全螢幕與 Esc 退出全螢幕的外層包裝元件。
///
/// 掛載於 `MaterialApp.builder` 層：
/// 1. **F11 全螢幕切換**：透過 [HardwareKeyboard] 監聽全域按鍵事件，
///    在無修飾鍵且為單次按下時觸發 [toggleWindowFullscreen]。
/// 2. **Esc 退出全螢幕**：
///    - 若內層畫面（如 [ReaderScreen]）已透過 [activeEscOverrideCount] 宣告接管 Esc，
///      本元件直接放行（回傳 `false`），由內層自訂 Esc 優先序（如選取清除、PDF 裁切保護、退出全螢幕）。
///    - 若無內層畫面接管，透過 [Actions.maybeFind] 檢查當前焦點節點的 context 是否有已啟用的 [DismissIntent]
///      處理器（如對話框的 `_DismissModalAction` 或抽屜的 `_DismissDrawerAction`）。
///    - 若有已啟用的浮層處理器（`action.isEnabled == true`），放行讓內層對話框優先關閉，
///      全螢幕狀態維持。
///    - 若無任何已啟用的浮層處理器，且當前處於全螢幕狀態（[WindowFullscreenController.isFullscreenNow]），
///      則觸發 [exitWindowFullscreenIfActive] 退出全螢幕並消費按鍵事件。
///    - 若非全螢幕且無浮層，則不消費 Esc 按鍵。
class WindowFullscreenShortcuts extends StatefulWidget {
  /// 指定使用的視窗全螢幕控制器。若為 null 則取全域的 [activeWindowFullscreenController]。
  final WindowFullscreenController? controller;

  /// 子元件樹。
  final Widget child;

  /// 當此計數 > 0 時，表示內層畫面（如 ReaderScreen）已接管 Esc 鍵處理，
  /// [WindowFullscreenShortcuts] 將對 Esc 按鍵放行（回傳 `false`），由內層依自身生命週期消費。
  static int activeEscOverrideCount = 0;

  const WindowFullscreenShortcuts({
    super.key,
    this.controller,
    required this.child,
  });

  @override
  State<WindowFullscreenShortcuts> createState() =>
      _WindowFullscreenShortcutsState();
}

class _WindowFullscreenShortcutsState extends State<WindowFullscreenShortcuts> {
  WindowFullscreenController? get _effectiveController =>
      widget.controller ?? activeWindowFullscreenController;

  bool get _isEnabled =>
      defaultTargetPlatform == TargetPlatform.windows &&
      _effectiveController != null;

  @override
  void initState() {
    super.initState();
    if (_isEnabled) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
  }

  @override
  void dispose() {
    if (_isEnabled) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    // 只處理單次按下（KeyDownEvent），忽略長按重複（KeyRepeatEvent）與釋放
    if (event is! KeyDownEvent) {
      return false;
    }

    // 任何修飾鍵按下時不觸發視窗全螢幕快捷鍵（如 Alt+F11、Ctrl+F11、Shift+Esc）
    final hk = HardwareKeyboard.instance;
    if (hk.isShiftPressed ||
        hk.isControlPressed ||
        hk.isAltPressed ||
        hk.isMetaPressed) {
      return false;
    }

    final controller = _effectiveController;
    if (controller == null) {
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.f11) {
      final canonicalId = canonicalKeyId(event.logicalKey);
      if (!desktopKeyDeduper.shouldHandle(canonicalId, DesktopKeySource.flutter)) {
        return true;
      }
      toggleWindowFullscreen(controller);
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // 若內層畫面（如 ReaderScreen）已接管 Esc，放行讓內層優先處理
      if (WindowFullscreenShortcuts.activeEscOverrideCount > 0) {
        return false;
      }

      final canonicalId = canonicalKeyId(event.logicalKey);
      if (!desktopKeyDeduper.shouldHandle(canonicalId, DesktopKeySource.flutter)) {
        return true;
      }
      // 檢查焦點樹上是否有已啟用的 DismissIntent Action（例如 dismissible 對話框）
      final focusContext = FocusManager.instance.primaryFocus?.context;
      if (focusContext != null) {
        final action = Actions.maybeFind<DismissIntent>(focusContext);
        if (action != null && action.isEnabled(const DismissIntent())) {
          // 有內層浮層可供關閉，放行交由焦點樹原生處理（例如關閉 Modal 對話框）
          return false;
        }
      }

      // 無已啟用的浮層時，若視窗當前處於全螢幕則退出全螢幕並消費按鍵
      if (controller.isFullscreenNow) {
        exitWindowFullscreenIfActive(controller);
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _effectiveController;
    if (!_isEnabled || controller == null) {
      return widget.child;
    }

    return Actions(
      key: const Key('window_fullscreen_dismiss_actions'),
      actions: <Type, Action<Intent>>{
        DismissIntent: _ExitFullscreenDismissAction(controller),
      },
      child: widget.child,
    );
  }
}

/// 接收 [DismissIntent] 並在全螢幕時退出視窗全螢幕的 [Action]。
class _ExitFullscreenDismissAction extends Action<DismissIntent> {
  final WindowFullscreenController controller;

  _ExitFullscreenDismissAction(this.controller);

  @override
  bool isEnabled(DismissIntent intent) {
    return controller.isFullscreenNow;
  }

  @override
  Object? invoke(DismissIntent intent) {
    exitWindowFullscreenIfActive(controller);
    return null;
  }
}
