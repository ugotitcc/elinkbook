import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 包裝原生 Android PdfReaderView 的 Flutter widget，透過 AndroidView
/// （PlatformView）嵌入畫面。給定 PDF 檔案的裝置端絕對路徑，通知原生端
/// 渲染第 1 頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// 支援手勢翻頁：左右滑動可切換頁面，透過 [onNextPage]／[onPreviousPage]
/// 回調通知呼叫端；原生端頁面變更時會觸發 [onPageChanged]。
class PdfReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final VoidCallback? onNextPage;
  final VoidCallback? onPreviousPage;
  final ValueChanged<int>? onPageChanged;

  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onNextPage,
    this.onPreviousPage,
    this.onPageChanged,
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
    channel.invokeMethod('openBook', {'path': widget.filePath});
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
