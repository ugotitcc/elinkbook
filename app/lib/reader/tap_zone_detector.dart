import 'package:flutter/widgets.dart';

/// 九宮格導覽熱區的單一格子共用偵測器（Epic 26 Issue 2，收斂自
/// `foliate_epub_reader_view.dart` 原 `_NavZoneTapDetector` 與
/// `pdf_reader_view.dart` 原 `_PdfNavZoneTapDetector`——兩者原本刻意各自
/// 獨立實作、逐字幾乎相同，且已各自被獨立審查抓到過幾乎一樣的
/// bug〔PDF 端補過 `onPointerCancel` 防禦性清理、EPUB 端從未收到這個
/// 修復〕，見 `docs/research/architecture-review-test-suite-epub-pdf.md`
/// 候選 2 與 `docs/epics/epic-26-architecture-hardening/issues.md`
/// Issue 2）。
///
/// 取代原本的 `GestureDetector(onTap: ...)`（EPUB 端 /diagnose
/// 2026-07-27 真機診斷發現的根因修正）：`GestureDetector` 的
/// `TapGestureRecognizer` 沒有時長上限——即使按住 800ms 才放開，仍會被
/// 判定為一次有效的 tap。`InAppWebView`（Hybrid Composition 平台視圖）
/// 與這個 `GestureDetector` 在同一個 Stack 位置競爭手勢競技場時，只要有
/// 任何 Flutter 側的手勢辨識器參與競爭，平台視圖自己的原生觸控轉發就會
/// 等待競技場裁定結果——`TapGestureRecognizer` 一路持有到放開才裁定為
/// 「是」，導致 `InAppWebView` 從頭到尾都沒收到這次觸控序列，長按選字的
/// 原生選取 UI（控點）完全不會出現。改用 [Listener] 直接觀察原始
/// pointer 事件、自行判斷「是否為一次快速點擊」（位移在 [tapSlop] 內、
/// 耗時在 [tapMaxDurationMs] 內），完全不註冊 `GestureRecognizer`、不
/// 參與手勢競技場，讓底層原生觸控轉發（`InAppWebView` 或 `PdfViewer`）
/// 不再被攔截，選字/拖曳控點/長按框選/翻頁滑動皆可直接穿透。
///
/// [nowMs] 為計時來源注入參數：EPUB 呼叫端傳入
/// `() => DateTime.now().millisecondsSinceEpoch`，PDF 呼叫端傳入
/// `() => clock.now().millisecondsSinceEpoch`（`package:clock`，讓
/// `flutter_test` 的FakeAsync 能攔截其 Zone 覆寫、隨 `tester.pump()`
/// 正確推進，正式裝置上仍取得真實系統時間；不像先前一度嘗試過的
/// `SchedulerBinding.currentSystemFrameTimeStamp` 只在畫面有新 frame
/// 排程時才更新，長按靜止區域可能整段時間都量不到經過的時間）。兩邊
/// 各自傳入各自現行的計時來源，不強制統一。
///
/// [tapMaxDurationMs]／[tapSlop] 同樣為呼叫端注入參數，刻意不在本
/// module 內設共用預設值/常數——EPUB 現行 700ms（`epic-25` Issue 1
/// 六輪真機診斷校準值）與 PDF 現行 400ms（原始未校準值）已被查證存在
/// 真實差異，兩者適用的正確門檻值可能本來就不同（見 Epic 26 Issue 3，
/// 需真機診斷才能定案 PDF 端數值，不可貿然套用 EPUB 數值），故此次收斂
/// 刻意只共用「偵測機制本身」（含 [onPointerCancel] 防禦性清理），不
/// 共用數值。
class TapZoneDetector extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final int Function() nowMs;
  final int tapMaxDurationMs;
  final double tapSlop;

  const TapZoneDetector({
    super.key,
    required this.onTap,
    required this.child,
    required this.nowMs,
    required this.tapMaxDurationMs,
    required this.tapSlop,
  });

  @override
  State<TapZoneDetector> createState() => _TapZoneDetectorState();
}

class _TapZoneDetectorState extends State<TapZoneDetector> {
  Offset? _downPosition;
  int? _downTimeMs;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _downPosition = event.position;
        _downTimeMs = widget.nowMs();
      },
      onPointerUp: (event) {
        final downPosition = _downPosition;
        final downTimeMs = _downTimeMs;
        if (downPosition == null || downTimeMs == null) return;
        final elapsed = widget.nowMs() - downTimeMs;
        final distance = (event.position - downPosition).distance;
        if (elapsed <= widget.tapMaxDurationMs &&
            distance <= widget.tapSlop) {
          widget.onTap();
        }
      },
      // 系統層級手勢中斷（例如滑出螢幕邊緣觸發 OS 系統手勢）會送出
      // PointerCancelEvent 而非 PointerUpEvent，須主動清除暫存狀態，
      // 避免殘留舊值（Epic 26 Issue 2：PDF 端原本已有這層保護、EPUB 端
      // 原本沒有，本次收斂後兩邊共用同一份，不會再各自漂移）。
      onPointerCancel: (_) {
        _downPosition = null;
        _downTimeMs = null;
      },
      child: widget.child,
    );
  }
}
