import 'dart:async';

/// 暫態高亮的自動清除計時器（epic-54 Issue 28）。
///
/// 只管計時：建構時捕捉 [Zone.current]，之後不論 [start] 在哪個 Zone 被呼叫，
/// 預設都在建構當下的 Zone 建立 [Timer]——測試的 `tester.runAsync` 會暫時離開
/// fake-async Zone，計時器若建在真實 Zone，`tester.pump` 就推不動。
///
/// 刻意使用裸 `Timer` 加 Zone 捕捉，不引入 `package:clock`：測試靠 fake-async
/// Zone 推進時間，不需要另一套可注入的時鐘。
///
/// 不碰 `ReaderSurface`：到期後要清除什麼，由呼叫端在 [start] 的 `onExpire`
/// 決定。
class TransientHighlightTimer {
  TransientHighlightTimer({
    this.duration = const Duration(seconds: 3),
    Timer Function(Duration duration, void Function() callback)? timerFactory,
  }) : _timerFactory = timerFactory ?? _zoneBoundFactory(Zone.current);

  final Duration duration;
  final Timer Function(Duration, void Function()) _timerFactory;
  Timer? _timer;

  /// 已啟動，且尚未取消、尚未到期。
  ///
  /// 與 [Timer.isActive] 不同的是：到期回呼 `onExpire` 執行當下已是 `false`，
  /// 所以到期路徑要直接做清除，不能再用本欄位判斷。
  bool get isActive => _timer != null;

  /// 重新計時：先取消舊的。到期時先把自己標成未啟動，再呼叫 [onExpire]。
  void start(void Function() onExpire) {
    _timer?.cancel();
    _timer = _timerFactory(duration, () {
      _timer = null;
      onExpire();
    });
  }

  /// 取消計時；沒有啟動時是無動作。
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  static Timer Function(Duration, void Function()) _zoneBoundFactory(
    Zone zone,
  ) =>
      (duration, callback) => zone.run(() => Timer(duration, callback));
}
