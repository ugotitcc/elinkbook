import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'page_turn_mode.dart';
import 'writing_mode.dart';

/// 包裝原生 Android EpubReaderView（Readium kotlin-toolkit）的 Flutter widget，
/// 透過 AndroidView（PlatformView）嵌入畫面。給定 EPUB 檔案的裝置端絕對路徑，通知
/// 原生端渲染起始頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// [writingMode] 為 null 時，開書當下不覆寫橫直排設定，交由 Readium 依書本
/// 語言／閱讀方向自動判斷（判斷結果透過 [onLayoutResolved] 回報一次）；設定
/// 為非 null 且與前次不同時，會即時呼叫原生端切換，不重新開書（見
/// docs/adr/0003-epub-reader-writing-mode-contract.md）。
///
/// [pageTurnMode] 語意與 [writingMode] 對稱：為 null 時不覆寫換頁模式，
/// 沿用 Readium 預設值（分頁）；為非 null 且與前次不同時，即時呼叫原生端
/// 切換為分頁或捲動渲染（見 docs/adr/0004-epub-reader-page-turn-mode-contract.md）。
/// 捲動模式是 Issue 3 驗證過、用於規避直排分頁欄位裁切風險的暫行方案。
///
/// 【刻意的設計，非疏漏】即使首次建構時 [writingMode] 就已是非 null，開書當下
/// 仍一律忽略它、交由自動判斷決定初始模式——[writingMode] 只用於開書後的後續
/// 切換（透過 [didUpdateWidget] 偵測變動）。目前唯一的呼叫端 `ReaderScreen`
/// 也一律等 [onLayoutResolved] 回報後才可能變更 [writingMode]，因此這個限制
/// 現階段不影響任何實際情境。
class EpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final WritingMode? writingMode;
  final PageTurnMode? pageTurnMode;
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;

  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.writingMode,
    this.pageTurnMode,
    this.onLayoutResolved,
  });

  @override
  State<EpubReaderView> createState() => _EpubReaderViewState();
}

class _EpubReaderViewState extends State<EpubReaderView> {
  MethodChannel? _channel;

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    channel.invokeMethod('openBook', {'path': widget.filePath});
  }

  @override
  void didUpdateWidget(covariant EpubReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newMode = widget.writingMode;
    if (newMode != null && newMode != oldWidget.writingMode) {
      _channel?.invokeMethod('setWritingMode', {
        'mode': newMode == WritingMode.vertical ? 'vertical' : 'horizontal',
      });
    }
    final newPageTurnMode = widget.pageTurnMode;
    if (newPageTurnMode != null && newPageTurnMode != oldWidget.pageTurnMode) {
      _channel?.invokeMethod('setPageTurnMode', {
        'mode': newPageTurnMode == PageTurnMode.scroll ? 'scroll' : 'paginated',
      });
    }
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
        widget.onLayoutResolved?.call(EpubLayoutInfo(
          isFixedLayout: args['isFixedLayout'] as bool,
          writingMode: (args['writingMode'] as String) == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        ));
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
