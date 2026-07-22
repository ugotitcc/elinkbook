import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'writing_mode.dart';

/// 包裝原生 FoliateEpubReaderView（readest/foliate-js，釘定 commit
/// dd71f2be356563c16a23272686189fcfb45d0b82）的 Flutter widget，供流式
/// （reflowable）EPUB 使用，透過 AndroidView（PlatformView）嵌入畫面。
/// 給定 EPUB 檔案的裝置端絕對路徑或 content:// URI，通知原生端渲染起始
/// 頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// 本 Issue（epic-17-epub-render-migration Issue 3）僅實作 [filePath]／
/// [onPageRendered]／[onError]／[onLayoutResolved] 四個建構參數，與既有
/// [EpubReaderView]（Readium，處理固定版面 FXL）刻意保持公開介面對稱
/// （見 docs/epics/epic-17-epub-render-migration/spec.md「介面」節）。
/// 排版設定／換頁／目錄／劃線備註是 Issue 4-8 的範圍，屆時會依對稱模式
/// 逐一補上對應建構參數，本檔案不預先放置尚未使用的參數（YAGNI）。
///
/// [onLayoutResolved] 在本 Issue 範圍內固定回傳
/// `EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal)`
/// ——`isFixedLayout` 恆為 false 是本 widget 的既定契約（呼叫端在建構這個
/// widget 之前就已經確定是流式書，見 ReaderScreen 的分派邏輯）；
/// `writingMode` 依書本 CSS 宣告判斷實際值是 Issue 4 的範圍，本 Issue 只
/// 是滿足既有型別簽章的非空要求，暫時固定回報橫排。
class FoliateEpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;

  const FoliateEpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onLayoutResolved,
  });

  @override
  State<FoliateEpubReaderView> createState() => _FoliateEpubReaderViewState();
}

class _FoliateEpubReaderViewState extends State<FoliateEpubReaderView> {
  void _onPlatformViewCreated(int id) {
    final channel =
        MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id');
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
      case 'onLayoutResolved':
        final args = call.arguments as Map<Object?, Object?>;
        final info = EpubLayoutInfo(
          isFixedLayout: args['isFixedLayout'] as bool,
          writingMode: (args['writingMode'] as String) == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        );
        widget.onLayoutResolved?.call(info);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'cc.ugotit.elinkbook/foliate_epub_reader_view',
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}
