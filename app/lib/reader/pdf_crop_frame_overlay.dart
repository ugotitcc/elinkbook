import 'package:flutter/material.dart';

import 'pdf_crop_rect.dart';

/// 手動裁切框選 UI（epic-24-pdf-engine-rebuild Issue 3）：全螢幕疊加層，
/// 顯示一個可拖曳右下角控制點縮放的矩形框，確認/取消由呼叫端
/// （`ReaderScreen`）決定後續動作（本 widget 不直接持有 `PdfReaderView`
/// 或持久化邏輯，維持既有單向資料流慣例，比照 `PdfSettingsSheet`）。
///
/// 座標系統：內部以「相對於本 widget 佔滿的可用空間」的比例（0.0-1.0）
/// 追蹤裁切框，與 [PdfCropRect] 語意一致——呼叫端須把本 widget 疊在與
/// `PdfReaderView` 完全同尺寸的區域上，兩者的相對座標系統才會對齊。
class PdfCropFrameOverlay extends StatefulWidget {
  const PdfCropFrameOverlay({
    super.key,
    required this.initialRect,
    required this.onConfirm,
    required this.onCancel,
  });

  final PdfCropRect initialRect;
  final ValueChanged<PdfCropRect> onConfirm;
  final VoidCallback onCancel;

  @override
  State<PdfCropFrameOverlay> createState() => _PdfCropFrameOverlayState();
}

class _PdfCropFrameOverlayState extends State<PdfCropFrameOverlay> {
  static const _minSize = 0.05;

  late double _left = widget.initialRect.left;
  late double _top = widget.initialRect.top;
  late double _right = widget.initialRect.right;
  late double _bottom = widget.initialRect.bottom;

  /// 四個角落控制點共用的拖曳處理：[movesLeft]/[movesTop] 決定這次拖曳
  /// 調整的是哪一組邊界（例如左上角控制點 movesLeft=true, movesTop=true，
  /// 只動 `_left`/`_top`，`_right`/`_bottom` 維持不動當錨點）——這是
  /// 【審查修正 Important 1】的核心：早期版本不論拖哪個控制點都只動
  /// `_right`/`_bottom`，導致使用者永遠無法收窄 `top`/`left`。
  void _dragHandle({
    required Offset delta,
    required Size size,
    required bool movesLeft,
    required bool movesTop,
  }) {
    setState(() {
      if (movesLeft) {
        _left = (_left + delta.dx / size.width).clamp(0.0, _right - _minSize);
      } else {
        _right = (_right + delta.dx / size.width).clamp(_left + _minSize, 1.0);
      }
      if (movesTop) {
        _top = (_top + delta.dy / size.height).clamp(0.0, _bottom - _minSize);
      } else {
        _bottom = (_bottom + delta.dy / size.height).clamp(_top + _minSize, 1.0);
      }
    });
  }

  Widget _buildHandle({
    required Key key,
    required double cornerLeft,
    required double cornerTop,
    required Size size,
    required bool movesLeft,
    required bool movesTop,
  }) {
    return Positioned(
      left: cornerLeft - 16,
      top: cornerTop - 16,
      child: GestureDetector(
        key: key,
        onPanUpdate: (details) => _dragHandle(
          delta: details.delta,
          size: size,
          movesLeft: movesLeft,
          movesTop: movesTop,
        ),
        child: Container(width: 32, height: 32, color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final frameRect = Rect.fromLTRB(
          _left * size.width,
          _top * size.height,
          _right * size.width,
          _bottom * size.height,
        );
        return Stack(
          children: [
            Positioned.fromRect(
              rect: frameRect,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
            _buildHandle(
              key: const Key('pdf_crop_frame_handle_top_left'),
              cornerLeft: frameRect.left,
              cornerTop: frameRect.top,
              size: size,
              movesLeft: true,
              movesTop: true,
            ),
            _buildHandle(
              key: const Key('pdf_crop_frame_handle_top_right'),
              cornerLeft: frameRect.right,
              cornerTop: frameRect.top,
              size: size,
              movesLeft: false,
              movesTop: true,
            ),
            _buildHandle(
              key: const Key('pdf_crop_frame_handle_bottom_left'),
              cornerLeft: frameRect.left,
              cornerTop: frameRect.bottom,
              size: size,
              movesLeft: true,
              movesTop: false,
            ),
            _buildHandle(
              key: const Key('pdf_crop_frame_handle_bottom_right'),
              cornerLeft: frameRect.right,
              cornerTop: frameRect.bottom,
              size: size,
              movesLeft: false,
              movesTop: false,
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const Key('pdf_crop_frame_cancel'),
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: widget.onCancel,
                  ),
                  const SizedBox(width: 32),
                  IconButton(
                    key: const Key('pdf_crop_frame_confirm'),
                    icon: const Icon(Icons.check, color: Colors.white),
                    onPressed: () => widget.onConfirm(
                      PdfCropRect(left: _left, top: _top, right: _right, bottom: _bottom),
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
