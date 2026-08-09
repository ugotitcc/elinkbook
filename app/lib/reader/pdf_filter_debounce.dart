import 'dart:async';

/// 可取消的防手震延遲排程器：[schedule] 在延遲時間內被再次呼叫時，取消
/// 前一次尚未執行的排程，只保留最後一次（epic-24-pdf-engine-rebuild
/// Issue 3，加粗強度 Slider 連續拖曳時避免對每個中間值都觸發一次 Isolate
/// 運算）。
class PdfFilterDebouncer {
  PdfFilterDebouncer({required this.delay});

  final Duration delay;
  Timer? _timer;

  void schedule(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
