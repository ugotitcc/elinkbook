import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'window_fullscreen_controller.dart';
import '../reader/desktop_key_deduper.dart';

/// 內層畫面（例如閱讀器）註冊的 Esc 消費者：回傳 `true` 代表已處理這次 Esc
/// （例如清除文字選取、吞掉裁切模式中的 Esc），外層就不再退出視窗全螢幕。
///
/// 消費者必須**自己**判斷「我現在是不是最上層、有沒有事可做」，沒事就回傳
/// `false`；這樣閱讀器被別的頁面（搜尋畫面等）蓋住時，不會讓 Esc 失效。
typedef EscInnerConsumer = bool Function();

final List<EscInnerConsumer> _escInnerConsumers = [];

/// 註冊一個內層 Esc 消費者，回傳取消註冊的函式（`dispose` 時務必呼叫）。
VoidCallback registerEscInnerConsumer(EscInnerConsumer consumer) {
  _escInnerConsumers.add(consumer);
  return () => _escInnerConsumers.remove(consumer);
}

/// 焦點所在處是否有「Esc 可以關掉」的浮層。
///
/// 1. 焦點所在路由的 `barrierDismissible` 為真（可關閉的對話框、底部面板、彈出
///    選單）——與 `_DismissModalAction.isEnabled` 同一個判斷。一般頁面路由為
///    false，所以疊上來的搜尋畫面、設定頁**不算**浮層。
/// 2. 最近的 `DismissIntent` 動作是 [DismissAction] 的子類且啟用（側欄抽屜、
///    MenuAnchor 選單）。
///
/// **不能**只看「最近的 `DismissIntent` 動作是否啟用」：`EditableText`（只要有
/// 輸入框取得焦點）會自行註冊一個永遠啟用的 `CallbackAction<DismissIntent>`
/// 來收起文字選取工具列，那不是浮層；若把它當成浮層，搜尋畫面這類輸入框開著的
/// 頁面按 Esc 就永遠退不出全螢幕。所以第 2 點只認 [DismissAction] 子類。
bool _hasDismissibleOverlay(BuildContext? focusContext) {
  if (focusContext == null) return false;
  final route = ModalRoute.of(focusContext);
  if (route != null && route.barrierDismissible) return true;
  final action = Actions.maybeFind<DismissIntent>(focusContext);
  return action is DismissAction && action.isEnabled(const DismissIntent());
}

/// Esc 的唯一決策點（鍵盤處理器與 WebView 轉送的 Esc 共用），優先序：
/// 1. 焦點所在路由有「啟用中」的 [DismissIntent]（可關閉的對話框、底部面板等）
///    → 回傳 `false`，放行讓焦點樹把它關掉，全螢幕維持。
/// 2. 內層消費者（見 [registerEscInnerConsumer]）有人處理 → 回傳 `true`。
/// 3. 目前是視窗全螢幕 → 退出全螢幕並回傳 `true`。
/// 4. 其他 → 回傳 `false`（不消費；閱讀器也**不會**因此返回書架）。
///
/// 為什麼不用 `MaterialApp.builder` 層的 `Actions` 覆寫 `DismissIntent`：
/// 每個 `ModalRoute`（包含一般頁面路由）都在內容外包一層自己的
/// `Actions({DismissIntent: _DismissModalAction})`（`routes.dart`），頁面路由的
/// `barrierDismissible` 為 false，該動作永遠未啟用；而 `Shortcuts` 派發時只取
/// 「最近一層」有 `DismissIntent` 的 `Actions`，即使未啟用也不會繼續往外層找，
/// 所以外層的覆寫永遠輪不到。也不能用 `Focus(onKeyEvent:)` 手動攔截：它位於
/// `WidgetsApp` 把 Esc 轉成 `DismissIntent` 的 `Shortcuts` 之內，會搶先吃掉 Esc。
///
/// 已知邊界：不可關閉的對話框（`barrierDismissible: false`）開著時，上面第 1 點
/// 不成立，Esc 會落到第 2、3 點；若閱讀器在其下，消費者因「不是最上層」回傳
/// `false`，最終退出視窗全螢幕。
bool handleWindowEscape(WindowFullscreenController controller) {
  if (_hasDismissibleOverlay(FocusManager.instance.primaryFocus?.context)) {
    return false;
  }

  // 複製一份再走訪：消費者處理過程可能觸發 setState／路由變動而改變註冊清單
  for (final consumer in List<EscInnerConsumer>.of(_escInnerConsumers)) {
    if (consumer()) return true;
  }

  if (controller.isFullscreenNow) {
    exitWindowFullscreenIfActive(controller);
    return true;
  }
  return false;
}

/// 在 Windows 平台上提供 F11 切換視窗全螢幕與 Esc 的外層包裝元件，掛在
/// `MaterialApp.builder`。
///
/// - **F11**：全域 [HardwareKeyboard] 處理器（不依賴焦點），只處理無修飾鍵的
///   [KeyDownEvent]，忽略 [KeyRepeatEvent]，觸發 [toggleWindowFullscreen]。
/// - **Esc**：交給 [handleWindowEscape] 決定。
///
/// 非 Windows（或控制器為 `null`）時 `build` 直接回傳 [child]，不註冊任何處理器、
/// 不插入任何 widget。
class WindowFullscreenShortcuts extends StatefulWidget {
  /// 指定使用的視窗全螢幕控制器。若為 null 則取全域的 [activeWindowFullscreenController]。
  final WindowFullscreenController? controller;

  /// 子元件樹。
  final Widget child;

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

    final isF11 = event.logicalKey == LogicalKeyboardKey.f11;
    final isEscape = event.logicalKey == LogicalKeyboardKey.escape;
    if (!isF11 && !isEscape) {
      return false;
    }

    final canonicalId = canonicalKeyId(event.logicalKey);
    if (!desktopKeyDeduper.shouldHandle(
      canonicalId,
      DesktopKeySource.flutter,
    )) {
      return true;
    }

    if (isF11) {
      toggleWindowFullscreen(controller);
      return true;
    }
    return handleWindowEscape(controller);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
