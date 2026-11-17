import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'pdf_crop_rect.dart';

/// 四矩形色帶遮罩繪製器：以四個不重疊矩形（上/下/左/右）繪製外部半透明
/// 暗色遮罩，並繪製雙層高對比邊框（外黑 3px ＋ 內白 1.5px）。
///
/// 【效能考量】原案採 `Path.combine(PathOperation.difference, ...)` 布林運算，
/// 但裁切框拖曳互動下每個觸控影格都會重繪——四矩形運算量遠低於 Path 布林運算，
/// 對 E-Ink／低效能裝置更友善（epic-27 Issue 7 Important #2）。
class CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  final Size canvasSize;
  CropOverlayPainter({required this.cropRect, required this.canvasSize});

  @override
  void paint(Canvas canvas, Size size) {
    // 外部半透明遮罩：上/下/左/右四個不重疊色帶
    final maskPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawRect(
        Rect.fromLTRB(0, 0, size.width, cropRect.top), maskPaint);
    canvas.drawRect(
        Rect.fromLTRB(0, cropRect.bottom, size.width, size.height), maskPaint);
    canvas.drawRect(
        Rect.fromLTRB(0, cropRect.top, cropRect.left, cropRect.bottom),
        maskPaint);
    canvas.drawRect(
        Rect.fromLTRB(cropRect.right, cropRect.top, size.width, cropRect.bottom),
        maskPaint);

    // 雙層高對比邊框（外黑 3.0px，內白 1.5px）
    final outerBorder = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    final innerBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRect(cropRect, outerBorder);
    canvas.drawRect(cropRect, innerBorder);
  }

  @override
  bool shouldRepaint(covariant CropOverlayPainter oldDelegate) =>
      cropRect != oldDelegate.cropRect || canvasSize != oldDelegate.canvasSize;
}

/// 手動裁切框選 UI：全螢幕疊加層，使用者以手指直接拖拉出要保留的範圍
/// （epic-58-pdf-crop-drag-select，取代 epic-24 Issue 3 的四角圓點縮放）。
/// 確認/取消由呼叫端（`ReaderScreen`）決定後續動作（本 widget 不直接持有
/// `PdfReaderView` 或持久化邏輯，維持既有單向資料流慣例，比照 `PdfSettingsSheet`）。
///
/// 互動規則：
/// - 進入時不顯示框，只顯示提示文字；確認鈕停用。
/// - 手指按下為一個角、拖到對角；放開後框固定。再拖拉一次就取代舊框，
///   不提供移動／縮放既有框的控制點。
/// - 任一邊小於 [_minSize]（比例）的選取視為無效（含輕點），保留上一個框。
/// - 座標限制在畫布範圍內。
///
/// 座標系統：內部以「相對於本 widget 佔滿的可用空間」的比例（0.0-1.0）
/// 追蹤裁切框，與 [PdfCropRect] 語意一致——呼叫端須把本 widget 疊在與
/// `PdfReaderView` 完全同尺寸的區域上，兩者的相對座標系統才會對齊。
class PdfCropFrameOverlay extends StatefulWidget {
  const PdfCropFrameOverlay({
    super.key,
    required this.onConfirm,
    required this.onCancel,
  });

  final ValueChanged<PdfCropRect> onConfirm;
  final VoidCallback onCancel;

  @override
  State<PdfCropFrameOverlay> createState() => _PdfCropFrameOverlayState();
}

class _PdfCropFrameOverlayState extends State<PdfCropFrameOverlay> {
  static const _minSize = 0.05;

  /// 多指並行追蹤（Issue 44）：WAVE 觸控驅動會把一次連續拖拉拆成多個
  /// pointer，且常**同時**存在兩條座標流——一條卡住落後、一條跟著真手指
  /// （真機記錄 `repro/issue-44-wave-pointer-log*.txt`）。另有只按下／放開、
  /// 不會移動的幽靈第二指（距離 125～558px）。
  /// - 新 pointer 落在目前位置 [_relayRadius] 內：直接升格，視為接力。
  /// - 放開後的 [_relayGrace] 寬限期內，新 pointer 不論距離都是接力：手指快速
  ///   拖拉時 68ms 內可移動 300px（真機 id=16→id=17），用距離判斷會把它當成
  ///   新的一框、重設起點。
  /// - 追蹤中更遠的先當候選，持續移動累積位移達 [_promoteDistance] 才升格；
  ///   只抖動或不動的幽靈永遠不升格。
  /// - 已升格的 pointer 各自更新目前位置，但**座標沒變的移動事件不算**
  ///   （卡住的落後者會重複回報同一座標），因此最近真正在動的那條為準。
  /// - 所有已升格 pointer 都放開後，等 [_relayGrace] 才定案。
  /// - 兩條座標流同時存在時，**最新的那根是領頭**（靠近按下的新 pointer 要等它
  ///   第一次真的移動才接手，不動的幽靈不搶領頭），只有領頭更新框的角落；
  ///   舊流快放開，位置會倒退，誰動誰更新會讓角落在兩條流之間來回跳（真機
  ///   id=49／id=50）。領頭閒置超過 [_leaderIdle]（例如它其實是不動的幽靈）
  ///   時，別根真正在動的手指接手。
  static const _relayRadius = 150.0; // 邏輯像素
  static const _promoteDistance = 8.0; // 邏輯像素
  static const _relayGrace = Duration(milliseconds: 250);
  static const _leaderIdle = Duration(milliseconds: 150);
  Timer? _finalizeTimer;

  /// 已確定（手指放開且有效）的裁切框；null 代表尚未畫過
  PdfCropRect? _rect;

  /// 拖拉進行中的兩個對角點（比例座標）；非拖拉中為 null
  Offset? _dragStart;
  Offset? _dragCurrent;

  /// 畫面上目前的所有手指（含尚未升格的候選）
  final Map<int, _CropPointer> _pointers = {};

  bool get _hasPromotedPointer => _pointers.values.any((p) => p.promoted);

  /// 目前的領頭 pointer，與它最後一次「座標真的變了」的時間
  int? _leaderId;
  DateTime _leaderActiveAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _promotionCounter = 0;

  /// 升格 [pointer] 並讓它成為領頭
  void _promote(int id, _CropPointer pointer, {bool lead = true}) {
    pointer.promoted = true;
    pointer.promotedSeq = ++_promotionCounter;
    if (!lead) return;
    _leaderId = id;
    _leaderActiveAt = clock.now();
  }

  /// 手指按下後是否真的移動過；輕點（沒移動）不繪製任何東西，
  /// 避免 0x0 的框讓上下遮罩蓋滿整個畫面造成閃爍（E-Ink 會殘影）
  bool get _moved => _dragStart != null && _dragCurrent != _dragStart;

  @override
  void dispose() {
    _finalizeTimer?.cancel();
    super.dispose();
  }

  /// 把像素座標轉成 0~1 比例並限制在畫布內
  Offset _toRatio(Offset local, Size size) => Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      );

  /// 由兩個對角點正規化出 left<right、top<bottom 的矩形
  PdfCropRect _rectFrom(Offset a, Offset b) => PdfCropRect(
        left: a.dx < b.dx ? a.dx : b.dx,
        top: a.dy < b.dy ? a.dy : b.dy,
        right: a.dx < b.dx ? b.dx : a.dx,
        bottom: a.dy < b.dy ? b.dy : a.dy,
      );

  void _beginDrag(PointerDownEvent e, Size size) {
    final current = _dragCurrent;
    final pointer = _CropPointer(e.localPosition);
    if (_dragStart != null && current != null) {
      final near =
          (e.localPosition -
                  Offset(current.dx * size.width, current.dy * size.height))
              .distance <=
          _relayRadius;
      final waiting = _finalizeTimer?.isActive == true && !_hasPromotedPointer;
      if (near || waiting) {
        // 接力：沿用起點。已有領頭時，新 pointer 要等第一次移動才接手
        final hasLeader = _leaderId != null && _pointers.containsKey(_leaderId);
        _promote(e.pointer, pointer, lead: !hasLeader);
        _finalizeTimer?.cancel();
      } else if (!_hasPromotedPointer) {
        // 沒有寬限期卻沒有任何追蹤中的 pointer：視為新的一次框選
        _commitPending();
        _promote(e.pointer, pointer);
        _dragStart = _dragCurrent = _toRatio(e.localPosition, size);
      }
      // 否則：追蹤中遠處按下，先當候選，移動夠多才升格
    } else {
      _promote(e.pointer, pointer);
      _dragStart = _dragCurrent = _toRatio(e.localPosition, size);
    }
    _pointers[e.pointer] = pointer;
  }

  void _moveDrag(PointerMoveEvent e, Size size) {
    final pointer = _pointers[e.pointer];
    if (pointer == null) return;
    final changed = e.localPosition != pointer.position;
    final firstMove = !pointer.moved && changed;
    pointer.moved = pointer.moved || changed;
    pointer.position = e.localPosition;
    if (!pointer.promoted) {
      if ((e.localPosition - pointer.downPosition).distance <
          _promoteDistance) {
        return;
      }
      _promote(e.pointer, pointer); // 持續移動，是真手指，成為領頭
      _finalizeTimer?.cancel();
    } else if (_leaderId != e.pointer) {
      final leader = _pointers[_leaderId];
      if (firstMove &&
          (leader == null || pointer.promotedSeq > leader.promotedSeq)) {
        // 比領頭新的 pointer 第一次真的移動：它才是真手指，接手領頭
        _leaderId = e.pointer;
      } else {
        // 不是領頭：領頭還在動就忽略（舊流倒退的位置不能更新框）；領頭閒置超過
        // [_leaderIdle] 才由這根接手
        if (clock.now().difference(_leaderActiveAt) < _leaderIdle) return;
        if (!changed) return;
        _leaderId = e.pointer;
      }
    }
    if (!changed) return; // 卡住的落後者重複回報同一座標：不算
    _leaderActiveAt = clock.now();
    setState(() => _dragCurrent = _toRatio(e.localPosition, size));
  }

  /// 手指放開：所有已升格的 pointer 都放開後，等 [_relayGrace] 才定案
  void _endPointer(PointerUpEvent e) {
    final removed = _pointers.remove(e.pointer);
    if (removed == null || !removed.promoted) return;
    if (_leaderId == e.pointer) _electLeader();
    if (_hasPromotedPointer || _dragStart == null) return;
    _finalizeTimer?.cancel();
    _finalizeTimer = Timer(_relayGrace, _commitPending);
    setState(() {}); // 重畫，讓確認鈕在等待定案期間仍可點
  }

  /// 領頭放開後，由最新升格、仍在畫面上的 pointer 接任（沒有就清空）
  void _electLeader() {
    int? best;
    var bestSeq = -1;
    _pointers.forEach((id, p) {
      if (p.promoted && p.promotedSeq > bestSeq) {
        best = id;
        bestSeq = p.promotedSeq;
      }
    });
    _leaderId = best;
    _leaderActiveAt = clock.now();
  }

  /// 把進行中的拖拉定案；任一邊太小（含輕點）視為無效，保留上一個框
  void _commitPending() {
    _finalizeTimer?.cancel();
    final start = _dragStart;
    final current = _dragCurrent;
    if (start == null || current == null || !mounted) return;
    setState(() {
      final r = _rectFrom(start, current);
      if (r.right - r.left >= _minSize && r.bottom - r.top >= _minSize) {
        _rect = r;
      }
      _dragStart = null;
      _dragCurrent = null;
      _leaderId = null;
    });
  }

  /// 拖拉被系統中斷（邊緣手勢、防誤觸等）：放棄這次選取，保留上一個框。
  /// 只有最後一根已升格的 pointer 被中斷才算；其餘 pointer 的中斷只是移除它
  void _cancelPointer(PointerCancelEvent e) {
    final removed = _pointers.remove(e.pointer);
    if (removed != null && _leaderId == e.pointer) _electLeader();
    if (removed == null || !removed.promoted || _hasPromotedPointer) return;
    _finalizeTimer?.cancel();
    if (_dragStart == null) return;
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // 手指移動中顯示即時框，否則顯示已確定的框
        final moved = _moved;
        final shown = moved ? _rectFrom(_dragStart!, _dragCurrent!) : _rect;
        final confirmEnabled = _rect != null;
        return Stack(
          children: [
            // 整面指標層：直接處理原始指標事件，才能分辨「手指放開」與
            // 「被系統中斷（cancel）」——後者須放棄這次選取而非提交
            Positioned.fill(
              child: Listener(
                key: const Key('pdf_crop_frame_gesture_layer'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _beginDrag(e, size),
                onPointerMove: (e) => _moveDrag(e, size),
                onPointerUp: _endPointer,
                onPointerCancel: _cancelPointer,
              ),
            ),
            // 半透明遮罩＋雙層高對比邊框：只在有框時繪製；不攔截手勢
            if (shown != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: CropOverlayPainter(
                      cropRect: Rect.fromLTRB(
                        shown.left * size.width,
                        shown.top * size.height,
                        shown.right * size.width,
                        shown.bottom * size.height,
                      ),
                      canvasSize: size,
                    ),
                  ),
                ),
              ),
            if (_rect == null && !moved)
              Positioned(
                top: 64,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Material(
                      key: const Key('pdf_crop_frame_hint'),
                      color: const Color(0xFF2A2A2E),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Text(
                          l10n.readerPdfCropDragHint,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Material(
                    elevation: 6,
                    shape: const CircleBorder(
                        side: BorderSide(color: Colors.white, width: 1.5)),
                    color: const Color(0xFF2A2A2E),
                    child: InkWell(
                      key: const Key('pdf_crop_frame_cancel'),
                      customBorder: const CircleBorder(),
                      onTap: widget.onCancel,
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Icon(Icons.close, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                  Material(
                    elevation: 6,
                    shape: const CircleBorder(
                        side: BorderSide(color: Colors.white, width: 1.5)),
                    // 尚未畫框時確認鈕停用（灰底、不可點）
                    color: confirmEnabled
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF6B6B70),
                    child: InkWell(
                      key: const Key('pdf_crop_frame_confirm'),
                      customBorder: const CircleBorder(),
                      // 等待定案期間也可按：先定案再回傳
                      onTap: confirmEnabled || _finalizeTimer?.isActive == true
                          ? () {
                              _commitPending();
                              final r = _rect;
                              if (r != null) widget.onConfirm(r);
                            }
                          : null,
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Icon(Icons.check, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 畫面上的一根手指（Issue 44）。[promoted] 為 true 才算數：新 pointer 若在目前
/// 位置附近就直接升格；遠處的先當候選，持續移動夠遠才升格。
class _CropPointer {
  _CropPointer(Offset down) : downPosition = down, position = down;

  final Offset downPosition;
  Offset position;
  bool promoted = false;

  /// 按下後座標是否真的變過（靠近按下的新 pointer 要等第一次移動才接手領頭）
  bool moved = false;

  /// 升格順序（越大越新），領頭放開時用來挑接任者
  int promotedSeq = 0;
}
