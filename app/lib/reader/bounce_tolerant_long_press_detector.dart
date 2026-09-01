import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/widgets.dart';
import 'tap_zone_detector.dart' show kTapZoneSlop, kTapZoneDebounceMs;

/// PDF 長按拖曳框選劃線/備註專用的手勢偵測器（Epic 25 Issue 5），取代
/// Flutter 內建 `GestureDetector`／`LongPressGestureRecognizer`——後者完全
/// 不知道「觸控彈跳」這件事：同一根手指持續按住不放，只要硬體回報成一連串
/// 極短暫的獨立 down/up 事件，內建元件的內部計時器每次遇到新的 down 就會
/// 歸零，導致長按永遠無法累積到啟動所需的時長（真機資料證實：裝置 2 整段
/// 操作 48 次按壓、0 次成功啟動，見
/// `docs/epics/epic-25-annotation-interaction-qa/issues.md` Issue 5）。
///
/// 比照 `TapZoneDetector`（見 `tap_zone_detector.dart`）同一套架構：用
/// [Listener]（不參與手勢競技場）直接觀察原始 pointer 事件，不註冊
/// `GestureRecognizer`，讓底層 `PdfViewer` 的原生觸控轉發不受影響。
///
/// **彈跳合併判定**（[mergeGapMs]／[mergeSlop]，預設沿用 `TapZoneDetector`
/// 既有真機校準值 [kTapZoneDebounceMs]／[kTapZoneSlop]）：新的 `down` 若與
/// 上一筆事件時間差 <= [mergeGapMs] 且與「最近一次已知位置」的位移
/// <= [mergeSlop]，視為同一次按壓的延續，不重置按壓起點/計時。這裡刻意用
/// **滑動比對**（跟最近一次已知位置比，不是跟最早的起點比）——真機資料顯示
/// 單一次彈跳爆發期間，位置會緩慢累積飄移，若跟固定起點比對，飄移超過
/// [mergeSlop] 後會被誤判成兩次獨立按壓，反而讓合併失效。
///
/// **長按判定前的位移取消**（[_handleMove] 尚未啟動長按時）則刻意改成跟
/// **固定起點**比對，比照原生 `LongPressGestureRecognizer` 行為——這段位移
/// 來自單一連續觸控的 move 事件（不是彈跳造成的離散 down 事件），沒有雜訊
/// 問題，用固定起點才能正確判定「這其實是一次滑動手勢，不是長按」。
///
/// **已進入拖曳階段後**（`_isActive == true`）收到的任何新 `down`，一律視為
/// 同一次手勢的延續、直接更新位置，不再套用位移門檻——拖曳階段本來就預期
/// 大幅移動，也避免在未通知 [onLongPressEnd]/[onLongPressCancel] 的情況下
/// 把使用中的按壓狀態靜默重置，導致下游 `_selectionDrag` 卡住殘留（規劃階段
/// 審查 Critical #2）。
///
/// **多指觸控防禦**：內部以 [_activePointers] 追蹤目前螢幕上有幾根手指。
/// 只要超過一指同時存在，立刻拒絕/取消目前追蹤中的按壓（不論是否已啟動長
/// 按），避免與 `PdfViewer` 的縮放/平移手勢衝突，也避免把第二指的觸碰誤判
/// 成新的長按起點；直到所有手指都放開才解除拒絕狀態（規劃階段審查
/// Critical #1）。
///
/// **幽靈觸發防禦**：長按判定時長的計時器觸發當下，若螢幕上剛好沒有任何
/// 手指（彈跳空隙、或使用者已經真正放開），**不會**立即啟動長按——真正放開
/// 太久會由 [_scheduleFinalizeCheck] 正確判定為取消；若只是短暫彈跳空隙、
/// 很快又按下，下一次 [_handleDown] 會在「累積時長其實已達標」時立即補上
/// 啟動，不會遺漏。這同時解決兩個問題：快速點兩下不會在背景幽靈觸發一次
/// 長按，介於 [mergeGapMs] 與 [longPressDurationMs] 之間的正常短按（例如
/// 300ms）也不會被誤判成長按（規劃階段審查 Critical #3）。
///
/// [onLongPressStart] 收到的座標固定為整串延續裡「最早那次 `down`」的
/// 位置，不會因雜訊本身的位置飄移而跳動。
class BounceTolerantLongPressDetector extends StatefulWidget {
  final Widget child;
  final void Function(Offset position) onLongPressStart;
  final void Function(Offset position) onLongPressMoveUpdate;
  final VoidCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;
  final int? longPressDurationMs;
  final int mergeGapMs;
  final double mergeSlop;

  const BounceTolerantLongPressDetector({
    super.key,
    required this.child,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
    this.longPressDurationMs,
    this.mergeGapMs = kTapZoneDebounceMs,
    this.mergeSlop = kTapZoneSlop,
  });

  @override
  State<BounceTolerantLongPressDetector> createState() =>
      _BounceTolerantLongPressDetectorState();
}

class _BounceTolerantLongPressDetectorState
    extends State<BounceTolerantLongPressDetector> {
  Offset? _anchorPosition;
  int? _anchorTimeMs;
  int? _lastActivityTimeMs;
  Offset? _lastKnownPosition;
  bool _isActive = false;
  Timer? _durationTimer;
  Timer? _finalizeTimer;

  // Critical #1（多指觸控防禦）：追蹤目前螢幕上有幾根手指，與「一次長按的
  // 邏輯狀態」（_anchorTimeMs 等）刻意分開管理，不因邏輯狀態被重置而跟著
  // 清空——必須忠實反映實體手指數量，才能正確判斷「是否所有手指都放開」。
  final Set<int> _activePointers = {};
  bool _isRejectedForMultiTouch = false;

  int _nowMs() => clock.now().millisecondsSinceEpoch;

  // Critical Finding 1（第二輪審查）：kLongPressTimeout.inMilliseconds 是
  // 執行期 getter、不是編譯期常數，不能直接當建構子可選參數的預設值（會是
  // const_eval_property_access 編譯錯誤，規劃階段已用 `dart analyze` 實測
  // 確認）。改成 widget.longPressDurationMs 宣告為 int?（預設 null），內部
  // 一律透過這個 getter 取得有效值。
  int get _effectiveDurationMs =>
      widget.longPressDurationMs ?? kLongPressTimeout.inMilliseconds;

  @override
  void dispose() {
    _durationTimer?.cancel();
    _finalizeTimer?.cancel();
    super.dispose();
  }

  void _resetState() {
    _anchorPosition = null;
    _anchorTimeMs = null;
    _lastActivityTimeMs = null;
    _lastKnownPosition = null;
    _isActive = false;
  }

  void _scheduleDurationTimer() {
    _durationTimer?.cancel();
    final observedAnchorTimeMs = _anchorTimeMs;
    _durationTimer =
        Timer(Duration(milliseconds: _effectiveDurationMs), () {
      if (!mounted) return;
      if (_anchorTimeMs != observedAnchorTimeMs) return;
      if (_isActive) return;
      if (_activePointers.isEmpty) {
        // Critical #3（幽靈觸發防禦）：手指目前剛好不在螢幕上（彈跳空隙或
        // 已經放開）。不要現在觸發——若使用者其實已放開太久，
        // _scheduleFinalizeCheck 會在稍後正確判定取消；若只是短暫彈跳
        // 空隙、馬上又按下，_handleDown 的存活時長檢查會立即補上啟動，
        // 不會漏掉。
        return;
      }
      _isActive = true;
      widget.onLongPressStart(_anchorPosition!);
      if (_lastKnownPosition != null &&
          _lastKnownPosition != _anchorPosition) {
        widget.onLongPressMoveUpdate(_lastKnownPosition!);
      }
    });
  }

  void _scheduleFinalizeCheck() {
    _finalizeTimer?.cancel();
    final observedAnchorTimeMs = _anchorTimeMs;
    final observedActivityTimeMs = _lastActivityTimeMs;
    _finalizeTimer = Timer(Duration(milliseconds: widget.mergeGapMs), () {
      if (!mounted) return;
      if (_anchorTimeMs != observedAnchorTimeMs) return;
      if (_lastActivityTimeMs != observedActivityTimeMs) return;
      _durationTimer?.cancel();
      final wasActive = _isActive;
      _resetState();
      if (wasActive) {
        widget.onLongPressEnd();
      } else {
        widget.onLongPressCancel();
      }
    });
  }

  void _rejectForMultiTouch() {
    _isRejectedForMultiTouch = true;
    _durationTimer?.cancel();
    _finalizeTimer?.cancel();
    final hadTracking = _anchorTimeMs != null;
    _resetState();
    if (hadTracking) widget.onLongPressCancel();
  }

  void _handleDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      // Critical #1：偵測到第二指，立刻拒絕，不論目前是否已啟動長按。
      _rejectForMultiTouch();
      return;
    }
    if (_isRejectedForMultiTouch) return; // 上一輪多指還沒完全放開，忽略。

    final now = _nowMs();

    if (_isActive) {
      // Critical #2：已在拖曳階段，任何後續 down（不論位移多大）都視為
      // 同一次手勢的延續，不套用位移門檻、也不會重置狀態。
      _finalizeTimer?.cancel();
      _finalizeTimer = null;
      _lastActivityTimeMs = now;
      _lastKnownPosition = event.localPosition;
      widget.onLongPressMoveUpdate(_lastKnownPosition!);
      return;
    }

    final isContinuation = _anchorTimeMs != null &&
        _lastActivityTimeMs != null &&
        _lastKnownPosition != null &&
        (now - _lastActivityTimeMs!) <= widget.mergeGapMs &&
        (_lastKnownPosition! - event.localPosition).distance <=
            widget.mergeSlop;
    if (isContinuation) {
      _finalizeTimer?.cancel();
      _finalizeTimer = null;
      _lastActivityTimeMs = now;
      _lastKnownPosition = event.localPosition;
      // Critical #3：彈跳空隙期間，若累積時長其實已經跨過門檻（因為
      // duration timer 觸發當下手指剛好不在螢幕上，被上方存活檢查擋
      // 下），這次重新按下就立即補上啟動，不必等下一個計時循環。
      if (now - _anchorTimeMs! >= _effectiveDurationMs) {
        _durationTimer?.cancel();
        _isActive = true;
        widget.onLongPressStart(_anchorPosition!);
        if (_lastKnownPosition != _anchorPosition) {
          widget.onLongPressMoveUpdate(_lastKnownPosition!);
        }
      }
    } else {
      _durationTimer?.cancel();
      _finalizeTimer?.cancel();
      if (_anchorTimeMs != null) {
        // Critical #2：前一次按壓尚未真正結束（pending 中）就被新的、不
        // 相關的按壓取代，須先通知這次 pending 嘗試已作廢，不能靜默丟棄。
        widget.onLongPressCancel();
      }
      _resetState();
      _anchorPosition = event.localPosition;
      _anchorTimeMs = now;
      _lastActivityTimeMs = now;
      _lastKnownPosition = event.localPosition;
      _scheduleDurationTimer();
    }
  }

  void _handleMove(PointerMoveEvent event) {
    if (_anchorTimeMs == null) return;
    if (!_isActive) {
      final distanceFromAnchor =
          (_anchorPosition! - event.localPosition).distance;
      if (distanceFromAnchor > widget.mergeSlop) {
        _durationTimer?.cancel();
        _finalizeTimer?.cancel();
        _resetState();
        widget.onLongPressCancel();
        return;
      }
    }
    _lastActivityTimeMs = _nowMs();
    _lastKnownPosition = event.localPosition;
    if (_isActive) {
      widget.onLongPressMoveUpdate(_lastKnownPosition!);
    }
  }

  void _handleUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) _isRejectedForMultiTouch = false;
    if (_anchorTimeMs == null) return;
    _lastActivityTimeMs = _nowMs();
    _scheduleFinalizeCheck();
  }

  void _handleCancel(PointerCancelEvent event) {
    // Important #1：系統手勢接管（例如邊緣滑動觸發系統返回）代表這根手指
    // 的整個手勢已被平台強制作廢，不可能有「彈跳延續」，不套用彈跳合併的
    // 寬限期，立即清除狀態。
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) _isRejectedForMultiTouch = false;
    if (_anchorTimeMs == null) return;
    _durationTimer?.cancel();
    _finalizeTimer?.cancel();
    _resetState();
    widget.onLongPressCancel();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: _handleCancel,
      child: widget.child,
    );
  }
}
