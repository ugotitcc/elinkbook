import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_font.dart';
import 'dual_page_mode.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'writing_mode.dart';

/// 包裝原生 Android EpubReaderView（Readium kotlin-toolkit）的 Flutter widget，
/// 透過 AndroidView（PlatformView）嵌入畫面。給定 EPUB 檔案的裝置端絕對路徑，通知
/// 原生端渲染起始頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// 全部 10 個偏好參數（[writingMode]／[pageTurnMode] 與本類別新增的 8 個版面
/// 偏好參數）語意一致：呼叫端傳入的皆是「已解析好的最終生效值」，`null` 代表
/// 不覆寫、使用 Readium 預設。首次建構時，所有非 null 的偏好參數會組成一個
/// map 隨 `openBook` 一併送出（`initialPreferences`）；之後任一偏好參數變動
/// （[didUpdateWidget] 偵測），會把當下所有非 null 的偏好參數（不只是變動的
/// 那個）重新組成一個 map，透過單一 `setPreferences` 呼叫送出——原生端
/// `currentPreferences.plus()` 本身就是合併語意，送出完整目前狀態比只送變動
/// 欄位更不容易遺漏邊界情況（見 docs/adr/0006-epub-reader-batch-preferences-contract.md）。
///
/// 【刻意的設計，非疏漏】即使首次建構時任一偏好參數就已是非 null，開書當下
/// 仍會透過 `initialPreferences` 一併送出——這與先前版本「開書當下一律忽略
/// writingMode／等到 didUpdateWidget 才生效」的行為不同，是 ADR 0006 明確要
/// 解決的缺口（持久化設定在開書當下真正套用）。
class EpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final WritingMode? writingMode;
  final PageTurnMode? pageTurnMode;
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;
  final AppFont? fontFamily;
  final double? fontSize;
  final double? fontWeight; // 已是 Readium 倍率語意（1.0 = normal），非 CSS 300-900 原始值
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? pageMargins;
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;
  final DualPageMode dualPageMode;
  final bool isLandscape;

  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.writingMode,
    this.pageTurnMode,
    this.onLayoutResolved,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
    this.dualPageMode = DualPageMode.auto,
    this.isLandscape = false,
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
    channel.invokeMethod('openBook', {
      'path': widget.filePath,
      'initialPreferences': _buildPreferencesMap(),
    });
  }

  @override
  void didUpdateWidget(covariant EpubReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_preferencesChanged(oldWidget)) {
      _channel?.invokeMethod('setPreferences', _buildPreferencesMap());
    }
  }

  bool _preferencesChanged(EpubReaderView oldWidget) {
    return widget.writingMode != oldWidget.writingMode ||
        widget.pageTurnMode != oldWidget.pageTurnMode ||
        widget.fontFamily != oldWidget.fontFamily ||
        widget.fontSize != oldWidget.fontSize ||
        widget.fontWeight != oldWidget.fontWeight ||
        widget.lineHeight != oldWidget.lineHeight ||
        widget.paragraphSpacing != oldWidget.paragraphSpacing ||
        widget.pageMargins != oldWidget.pageMargins ||
        widget.textAlign != oldWidget.textAlign ||
        widget.publisherStyles != oldWidget.publisherStyles ||
        widget.dualPageMode != oldWidget.dualPageMode ||
        widget.isLandscape != oldWidget.isLandscape;
  }

  /// 把目前所有非 null 的偏好參數組成一個 map，key 名稱與原生端契約一致
  /// （見 docs/epics/epic-3-fonts-layout/spec.md「原生 method channel 契約
  /// 異動」）。`null` 值的欄位完全不出現在 map 中（而非以 `null` 出現），
  /// 讓原生端可以直接用「key 是否存在」判斷是否覆寫。
  Map<String, Object?> _buildPreferencesMap() {
    final map = <String, Object?>{};
    if (widget.writingMode != null) {
      map['writingMode'] =
          widget.writingMode == WritingMode.vertical ? 'vertical' : 'horizontal';
    }
    if (widget.pageTurnMode != null) {
      map['pageTurnMode'] =
          widget.pageTurnMode == PageTurnMode.scroll ? 'scroll' : 'paginated';
    }
    if (widget.fontFamily != null) {
      map['fontFamily'] = widget.fontFamily!.familyName;
    }
    if (widget.fontSize != null) map['fontSize'] = widget.fontSize;
    if (widget.fontWeight != null) map['fontWeight'] = widget.fontWeight;
    if (widget.lineHeight != null) map['lineHeight'] = widget.lineHeight;
    if (widget.paragraphSpacing != null) {
      map['paragraphSpacing'] = widget.paragraphSpacing;
    }
    if (widget.pageMargins != null) map['pageMargins'] = widget.pageMargins;
    if (widget.textAlign != null) map['textAlign'] = widget.textAlign!.name;
    if (widget.publisherStyles != null) {
      map['publisherStyles'] = widget.publisherStyles;
    }
    map['dualPageMode'] = widget.dualPageMode.name;
    map['isLandscape'] = widget.isLandscape;
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
