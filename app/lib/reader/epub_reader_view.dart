import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 包裝原生 Android EpubReaderView（Readium kotlin-toolkit）的 Flutter widget，
/// 透過 AndroidView（PlatformView）嵌入畫面。給定 EPUB 檔案的裝置端絕對路徑，通知
/// 原生端渲染起始頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
class EpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;

  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
  });

  @override
  State<EpubReaderView> createState() => _EpubReaderViewState();
}

class _EpubReaderViewState extends State<EpubReaderView> {
  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'cc.ugotit.elinkbook/epub_reader_view',
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}
