import 'package:flutter/widgets.dart';

/// EPUB／PDF 兩端共用的九宮格熱區點擊容許位移／防彈跳門檻（Epic 31
/// Issue 3：`TapZoneDetector` 常數收斂）。兩端原本各自宣告完全相同的
/// 數值（`tapSlop: 18.0`／`tapDebounceMs: 350`），純粹是宣告位置重複，
/// 收斂成這裡的模組級常數，供下方建構子當作預設值使用，呼叫端不再需要
/// 各自重複宣告，見下方 [TapZoneDetector.tapSlop]／
/// [TapZoneDetector.tapDebounceMs] 說明。
const double kTapZoneSlop = 18.0;
const int kTapZoneDebounceMs = 350;

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
/// [tapMaxDurationMs] 為呼叫端注入參數，刻意不在本 module 內設共用預設
/// 值/常數——EPUB 的 700ms 是 `epic-25` Issue 1 六輪真機診斷校準值，PDF
/// 的 700ms 是 epic-31-touch-intent-unification Issue 3 刻意對齊、未經
/// 真機驗證的決定，兩者數值現在剛好相同，但校準狀態不同，各自明確傳值
/// 才能讓這個差異留在程式碼裡，不被「常數收斂」的動作悄悄合併掉（若之後
/// 真機回報 PDF 端門檻不合適，需另立工單依真機資料重新校準，比照
/// `epic-25` Issue 1／Epic 26 Issue 3 先例，不可逕自沿用 EPUB 數值）。
/// [tapSlop] 已收斂為模組級共用常數 [kTapZoneSlop]（見上方宣告），呼叫端
/// 不再需要各自宣告——EPUB／PDF 兩端這個欄位的數值本來就完全相同（皆為
/// 18.0），純粹是宣告位置重複，不像 [tapMaxDurationMs] 存在真實的校準
/// 狀態差異。
///
/// [onPointerMove] 熔斷（Epic 27 Issue 9）：在觸控移動過程中，若手指位移曾
/// 超過 [tapSlop]，即立刻將按壓狀態作廢（清除 `_downPosition` 與 `_downTimeMs`）。
/// 避免長按選字或劃線手勢中途小幅拖曳後手指移回原點附近放開時，被 [onPointerUp]
/// 誤判為一次快速點擊而誤觸翻頁。
///
/// [tapDebounceMs] 防彈跳（Epic 27 Issue 12）：同一熱區判定為合格點擊後，
/// 記錄該次放開時間。若在 [tapDebounceMs] 毫秒內再次判定為合格點擊，
/// 則直接忽略（吸收觸控面板硬體彈跳雜訊）。
class TapZoneDetector extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final int Function() nowMs;
  final int tapMaxDurationMs;
  final double tapSlop;
  final int tapDebounceMs;

  const TapZoneDetector({
    super.key,
    required this.onTap,
    required this.child,
    required this.nowMs,
    required this.tapMaxDurationMs,
    this.tapSlop = kTapZoneSlop,
    this.tapDebounceMs = kTapZoneDebounceMs,
  });

  @override
  State<TapZoneDetector> createState() => _TapZoneDetectorState();
}

class _TapZoneDetectorState extends State<TapZoneDetector> {
  Offset? _downPosition;
  int? _downTimeMs;
  int? _lastQualifyingTapUpTimeMs;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _downPosition = event.position;
        _downTimeMs = widget.nowMs();
      },
      onPointerMove: (event) {
        final downPosition = _downPosition;
        if (downPosition == null) return;
        final distance = (event.position - downPosition).distance;
        if (distance > widget.tapSlop) {
          // 位移已超過容許範圍，永久作廢本次按壓——即使之後手指移回附近
          // 才放開，onPointerUp 也不會再誤判為一次快速點擊（Epic 27
          // Issue 9）。
          _downPosition = null;
          _downTimeMs = null;
        }
      },
      onPointerUp: (event) {
        final downPosition = _downPosition;
        final downTimeMs = _downTimeMs;
        if (downPosition == null || downTimeMs == null) return;
        final now = widget.nowMs();
        final elapsed = now - downTimeMs;
        final distance = (event.position - downPosition).distance;
        if (elapsed <= widget.tapMaxDurationMs &&
            distance <= widget.tapSlop) {
          final previousTapUpTimeMs = _lastQualifyingTapUpTimeMs;
          _lastQualifyingTapUpTimeMs = now;
          if (previousTapUpTimeMs == null ||
              now - previousTapUpTimeMs >= widget.tapDebounceMs) {
            widget.onTap();
          }
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
