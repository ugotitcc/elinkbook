import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
import 'pdf_fit_mode.dart';

/// 包裝原生 Android PdfReaderView 的 Flutter widget，透過 AndroidView
/// （PlatformView）嵌入畫面。給定 PDF 檔案的裝置端絕對路徑，通知原生端
/// 渲染第 1 頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// 支援手勢翻頁：左右滑動可切換頁面，透過 [onNextPage]／[onPreviousPage]
/// 回調通知呼叫端；原生端頁面變更時會觸發 [onPageChanged]。
///
/// [fitMode] 是呼叫端已解析好的最終生效值（`null` 代表使用原生端預設
/// `pageFit`，見 docs/epics/epic-4-pdf-enhance/spec.md）。首次建構時，非
/// null 的偏好參數會組成 `initialPreferences` 隨 `openBook` 一併送出；之後
/// [fitMode] 變動（[didUpdateWidget] 偵測），會透過 `setPdfPreferences`
/// 送出，比照 EpubReaderView 的既有模式（見
/// docs/archive/2026-07-10-epic-3-fonts-layout/spec.md）。
class PdfReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final VoidCallback? onNextPage;
  final VoidCallback? onPreviousPage;
  final ValueChanged<int>? onPageChanged;
  final PdfFitMode? fitMode;
  final double? contrast;
  final double? brightness;
  final double? boldStrength;
  final PdfCropMode? cropMode;
  final PdfCropRect? cropRect;
  final ValueChanged<PdfCropRect>? onCropRectComputed;
  final bool cropEditModeActive;
  final ValueChanged<PdfCropRect>? onCropRectSelected;

  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onNextPage,
    this.onPreviousPage,
    this.onPageChanged,
    this.fitMode,
    this.contrast,
    this.brightness,
    this.boldStrength,
    this.cropMode,
    this.cropRect,
    this.onCropRectComputed,
    this.cropEditModeActive = false,
    this.onCropRectSelected,
  });

  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();
}

class _PdfReaderViewState extends State<PdfReaderView> {
  MethodChannel? _channel;

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    channel.invokeMethod('openBook', {
      'path': widget.filePath,
      'initialPreferences': _buildPreferencesMap(),
    });
  }

  @override
  void didUpdateWidget(covariant PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fitMode != oldWidget.fitMode ||
        widget.contrast != oldWidget.contrast ||
        widget.brightness != oldWidget.brightness ||
        widget.boldStrength != oldWidget.boldStrength ||
        widget.cropMode != oldWidget.cropMode) {
      _channel?.invokeMethod('setPdfPreferences', _buildPreferencesMap());
    }
    if (widget.cropEditModeActive != oldWidget.cropEditModeActive) {
      _channel?.invokeMethod(
        widget.cropEditModeActive ? 'enterCropEditMode' : 'exitCropEditMode',
      );
    }
  }

  /// 把目前所有非 null 的偏好參數組成一個 map，`null` 值的欄位完全不出現在
  /// map 中，比照 EpubReaderView 的既有模式。
  Map<String, Object?> _buildPreferencesMap() {
    final map = <String, Object?>{};
    if (widget.fitMode != null) map['fitMode'] = widget.fitMode!.name;
    if (widget.contrast != null) map['contrast'] = widget.contrast;
    if (widget.brightness != null) map['brightness'] = widget.brightness;
    if (widget.boldStrength != null) map['boldStrength'] = widget.boldStrength;
    if (widget.cropMode != null) map['cropMode'] = widget.cropMode!.name;
    if (widget.cropRect != null) {
      map['cropRect'] = {
        'left': widget.cropRect!.left,
        'top': widget.cropRect!.top,
        'right': widget.cropRect!.right,
        'bottom': widget.cropRect!.bottom,
      };
    }
    return map;
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPageRendered':
        widget.onPageRendered();
        break;
      case 'onError':
        widget.onError(call.arguments as String);
        break;
      case 'onPageChanged':
        final pageIndex = call.arguments as int;
        widget.onPageChanged?.call(pageIndex);
        break;
      case 'onCropRectComputed':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onCropRectComputed?.call(PdfCropRect(
          left: (args['left'] as num).toDouble(),
          top: (args['top'] as num).toDouble(),
          right: (args['right'] as num).toDouble(),
          bottom: (args['bottom'] as num).toDouble(),
        ));
        break;
      case 'onCropRectSelected':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onCropRectSelected?.call(PdfCropRect(
          left: (args['left'] as num).toDouble(),
          top: (args['top'] as num).toDouble(),
          right: (args['right'] as num).toDouble(),
          bottom: (args['bottom'] as num).toDouble(),
        ));
        break;
    }
  }

  /// 導航至下一頁
  void nextPage() => _channel?.invokeMethod('nextPage');

  /// 導航至上一頁
  void previousPage() => _channel?.invokeMethod('previousPage');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < 0) {
          // 向左滑動 → 下一頁
          nextPage();
        } else if (details.primaryVelocity! > 0) {
          // 向右滑動 → 上一頁
          previousPage();
        }
      },
      child: AndroidView(
        viewType: 'cc.ugotit.elinkbook/pdf_reader_view',
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }
}
