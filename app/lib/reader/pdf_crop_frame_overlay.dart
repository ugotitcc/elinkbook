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

  /// 已確定（手指放開且有效）的裁切框；null 代表尚未畫過
  PdfCropRect? _rect;

  /// 拖拉進行中的兩個對角點（比例座標）；非拖拉中為 null
  Offset? _dragStart;
  Offset? _dragCurrent;

  /// 目前追蹤的那根手指；其餘手指一律忽略
  int? _pointer;

  /// 手指按下後是否真的移動過；輕點（沒移動）不繪製任何東西，
  /// 避免 0x0 的框讓上下遮罩蓋滿整個畫面造成閃爍（E-Ink 會殘影）
  bool get _moved => _dragStart != null && _dragCurrent != _dragStart;

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
    if (_pointer != null) return;
    _pointer = e.pointer;
    _dragStart = _dragCurrent = _toRatio(e.localPosition, size);
  }

  void _endDrag() {
    _pointer = null;
    final start = _dragStart;
    final current = _dragCurrent;
    setState(() {
      if (start != null && current != null) {
        final r = _rectFrom(start, current);
        // 任一邊太小（含輕點）視為無效，保留上一個框
        if (r.right - r.left >= _minSize && r.bottom - r.top >= _minSize) {
          _rect = r;
        }
      }
      _dragStart = null;
      _dragCurrent = null;
    });
  }

  /// 拖拉被系統中斷（邊緣手勢、防誤觸等）：放棄這次選取，保留上一個框
  void _cancelDrag() {
    _pointer = null;
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
                onPointerMove: (e) {
                  if (e.pointer != _pointer) return;
                  setState(
                      () => _dragCurrent = _toRatio(e.localPosition, size));
                },
                onPointerUp: (e) {
                  if (e.pointer == _pointer) _endDrag();
                },
                onPointerCancel: (e) {
                  if (e.pointer == _pointer) _cancelDrag();
                },
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
                      onTap: confirmEnabled
                          ? () => widget.onConfirm(_rect!)
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
