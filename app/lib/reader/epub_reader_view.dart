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

  /// 固定版面（FXL）中間熱區觸發，切換 ReaderScreen 懸浮控制項的顯示/隱藏。
  final VoidCallback? onToggleFixedLayoutControls;

  /// 固定版面（FXL）左/右熱區換頁時觸發，讓 ReaderScreen 自動收起懸浮控制項
  ///（更沉浸的閱讀體驗）。與 [onToggleFixedLayoutControls] 刻意不同：這裡不論
  /// 收起前是顯示或隱藏，一律強制收起（非切換語意）。
  final VoidCallback? onFixedLayoutPageTurn;

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
    this.onToggleFixedLayoutControls,
    this.onFixedLayoutPageTurn,
  });

  @override
  State<EpubReaderView> createState() => _EpubReaderViewState();
}

class _EpubReaderViewState extends State<EpubReaderView> {
  MethodChannel? _channel;
  bool _isFixedLayout = false;

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
        final info = EpubLayoutInfo(
          isFixedLayout: args['isFixedLayout'] as bool,
          writingMode: (args['writingMode'] as String) == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        );
        setState(() => _isFixedLayout = info.isFixedLayout);
        widget.onLayoutResolved?.call(info);
        break;
    }
  }

  /// 導航至下一頁／spread（僅 FXL 三欄熱區呼叫，見 build()）。換頁後一併觸發
  /// [EpubReaderView.onFixedLayoutPageTurn]，讓呼叫端（ReaderScreen）自動收起
  /// 懸浮控制項——這與中間熱區的 [EpubReaderView.onToggleFixedLayoutControls]
  /// 是切換語意（toggle）刻意不同，換頁一律「收起」，不論收起前是顯示或隱藏。
  void nextPage() {
    _channel?.invokeMethod('nextPage');
    widget.onFixedLayoutPageTurn?.call();
  }

  /// 導航至上一頁／spread，同上一併觸發 [EpubReaderView.onFixedLayoutPageTurn]。
  void previousPage() {
    _channel?.invokeMethod('previousPage');
    widget.onFixedLayoutPageTurn?.call();
  }

  @override
  Widget build(BuildContext context) {
    // 【重要，審查修正】AndroidView 必須永遠是 Stack 的第一個子節點，不可依
    // _isFixedLayout 條件式地整個切換 build() 的根 widget 型別（例如
    // `if (!_isFixedLayout) return androidView; return Stack(...)`）——
    // Flutter 的 widget 比對是看同一位置的 widget runtimeType 是否相同，
    // 一旦根 widget 從 AndroidView 變成 Stack，Flutter 會直接 unmount 舊的
    // AndroidView element、mount 一個全新的，導致底層原生 EpubReaderView.kt
    // 實例被銷毀重建、重新 openBook()（重新解析整本書、畫面閃爍）。改成
    // AndroidView 永遠留在 Stack 的第一個子節點位置，熱區疊加層只作為
    // 「條件式存在的第二個子節點」，讓 AndroidView 在 _isFixedLayout
    // 由 false 變 true（或反過來）時都能被 Flutter 複用、不重建。
    //
    // 【已知取捨，記錄於此供未來維護者知悉】三欄熱區疊加層覆蓋整個
    // AndroidView 範圍，會擋住底層 Readium WebView 的所有觸控事件——若 FXL
    // 書籍內嵌超連結或其他 HTML 互動元素，這些功能在熱區生效期間會失效。
    // 目前鎖定的使用情境（FXL 漫畫）通常沒有這類互動元素，此為刻意接受的
    // 暫代方案限制，非本 issue 需要解決的問題。
    return Stack(
      children: [
        AndroidView(
          viewType: 'cc.ugotit.elinkbook/epub_reader_view',
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
        if (_isFixedLayout)
          // FXL 專屬的三欄點擊熱區（暫代版，見 CONTEXT.md「FXL 換頁熱區
          // （暫代版）」／docs/epics/epic-16-dual-page/issues.md Issue 9）：
          // 取代原生滑動手勢換頁，避免 E-Ink 裝置動畫殘影，並繞開 Android
          // WebView 對尚未可視的預載頁面延後渲染造成的縮放跳動（Readium
          // kotlin-toolkit 已知問題，非本專案可控）。流式 EPUB
          // （_isFixedLayout == false）完全不受影響，維持原生手勢。
          //
          // 每個熱區同時提供 onTap 與（no-op 的）onHorizontalDragStart/
          // onVerticalDragStart——沒有後兩者的話，一段「越過臨界距離的拖曳」
          // 手勢會被 Flutter 的手勢競技場判定不是點擊，讓底層原生
          // AndroidView 有機會接手（等於滑動手勢還是繞過我們直接落到
          // Readium 的 WebView，觸發它自己的滑動換頁，等於沒解決問題）。
          // 加上這兩個 no-op 回呼，讓我們的 GestureDetector 對任何觸控
          // 序列（不論最終是否判定為點擊）都搶到手勢競技場的勝利，原生層
          // 完全收不到觸控事件。（雙指縮放/pinch-to-zoom 刻意不攔截，見
          // Task 2 Step 3 之後的「待確認事項」。）
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    key: const Key('epub_fxl_tap_zone_previous'),
                    behavior: HitTestBehavior.opaque,
                    onTap: previousPage,
                    onHorizontalDragStart: (_) {},
                    onVerticalDragStart: (_) {},
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    key: const Key('epub_fxl_tap_zone_toggle_controls'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onToggleFixedLayoutControls?.call(),
                    onHorizontalDragStart: (_) {},
                    onVerticalDragStart: (_) {},
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    key: const Key('epub_fxl_tap_zone_next'),
                    behavior: HitTestBehavior.opaque,
                    onTap: nextPage,
                    onHorizontalDragStart: (_) {},
                    onVerticalDragStart: (_) {},
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
