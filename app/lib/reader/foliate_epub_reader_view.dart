import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_font.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'writing_mode.dart';
import 'zone_action.dart';

/// 包裝原生 FoliateEpubReaderView（readest/foliate-js，釘定 commit
/// dd71f2be356563c16a23272686189fcfb45d0b82）的 Flutter widget，供流式
/// （reflowable）EPUB 使用，透過 AndroidView（PlatformView）嵌入畫面。
/// 給定 EPUB 檔案的裝置端絕對路徑或 content:// URI，通知原生端渲染起始
/// 頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// 本 Widget（epic-17-epub-render-migration Issue 4/5）新增 9 項版面偏好
/// 建構參數，與既有 [EpubReaderView] 對稱參數同名同型別（不含 `dualPageMode`／
/// `isLandscape`——reflowable 流式書籍不適用「雙頁」）。Issue 5 新增
/// `navZoneActions`/`onZoneAction`/`showNavZoneDebugOverlay` 三個建構參數
/// 與 `nextPage`/`previousPage`/`jumpToProgression` static helper，3×3
/// 導航熱區完全由 Dart 端 Stack 疊加層處理、不送給原生端。
/// [writingMode] 是「呼叫端要求套用的方向」（可寫），與 [onLayoutResolved]
/// 回報的 [EpubLayoutInfo.writingMode]（原生端判斷/回報的唯讀值）是兩個
/// 不同方向的資料流，比照 [EpubReaderView] 既有模式。
///
/// 排版設定以外的目錄／劃線備註參數留待 Issue 6-8 補上。
class FoliateEpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;
  final WritingMode? writingMode;
  final PageTurnMode? pageTurnMode;
  final AppFont? fontFamily;
  final double? fontSize;
  final double? fontWeight; // Readium 倍率語意（1.0 = normal），比照 EpubReaderView
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? pageMargins;
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;

  /// 3×3 導航熱區的動作對照表（epic-17-epub-render-migration Issue 5，
  /// 對稱 epic-7-interaction 為 EpubReaderView FXL 分支建立的既有模式，
  /// 見 zone_hit_test.dart 索引慣例：0-indexed、列優先）。與
  /// EpubReaderView 不同，這個陣列**只在 Dart 端使用**，不會送給原生端
  /// （見 Global Constraints「不在原生端判讀」）。
  final List<ZoneAction> navZoneActions;

  /// 點擊熱區換算出動作後觸發，呼叫端（ReaderScreen）負責分派實際行為
  /// （換頁／切換沉浸模式）。
  final ValueChanged<ZoneAction>? onZoneAction;

  /// 是否疊加顯示熱區輔助線（邊框＋動作文字標籤），供設定畫面開啟除錯
  /// 用途。
  final bool showNavZoneDebugOverlay;

  const FoliateEpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onLayoutResolved,
    this.writingMode,
    this.pageTurnMode,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
    this.navZoneActions = const [
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ],
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
  });

  /// 呼叫原生端 view.next()，換頁不觸發任何回呼（強型別 static helper，
  /// 比照既有 EpubReaderView.nextPage 模式，不使用 `as dynamic` 跨越
  /// State 的 private 邊界）。[key] 對應的 State 若尚未掛載（例如純
  /// flutter_test 環境下 AndroidView 尚未建立），靜默忽略。
  static void nextPage(GlobalKey<State<FoliateEpubReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._channel?.invokeMethod('nextPage');
    }
  }

  /// 呼叫原生端 view.prev()，同上僅換頁方向相反。
  static void previousPage(GlobalKey<State<FoliateEpubReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._channel?.invokeMethod('previousPage');
    }
  }

  /// 跳轉到指定全書進度比例（0.0-1.0），原生端呼叫 view.goToFraction()。
  static void jumpToProgression(
    GlobalKey<State<FoliateEpubReaderView>> key,
    double progression,
  ) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._channel?.invokeMethod('jumpToProgression', {
        'progression': progression,
      });
    }
  }

  @override
  State<FoliateEpubReaderView> createState() => _FoliateEpubReaderViewState();
}

class _FoliateEpubReaderViewState extends State<FoliateEpubReaderView> {
  MethodChannel? _channel;

  void _onPlatformViewCreated(int id) {
    final channel =
        MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    channel.invokeMethod('openBook', {
      'path': widget.filePath,
      'initialPreferences': _buildPreferencesMap(),
    });
  }

  @override
  void didUpdateWidget(covariant FoliateEpubReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_preferencesChanged(oldWidget)) {
      _channel?.invokeMethod('setPreferences', _buildPreferencesMap());
    }
  }

  bool _preferencesChanged(FoliateEpubReaderView oldWidget) {
    return widget.writingMode != oldWidget.writingMode ||
        widget.pageTurnMode != oldWidget.pageTurnMode ||
        widget.fontFamily != oldWidget.fontFamily ||
        widget.fontSize != oldWidget.fontSize ||
        widget.fontWeight != oldWidget.fontWeight ||
        widget.lineHeight != oldWidget.lineHeight ||
        widget.paragraphSpacing != oldWidget.paragraphSpacing ||
        widget.pageMargins != oldWidget.pageMargins ||
        widget.textAlign != oldWidget.textAlign ||
        widget.publisherStyles != oldWidget.publisherStyles;
  }

  /// 把目前所有非 null 的偏好參數組成一個 map，key 名稱與原生端契約一致
  /// （見 docs/epics/epic-17-epub-render-migration/plans/plan-issue-4.md
  /// Global Constraints）。`null` 值的欄位完全不出現在 map 中，比照
  /// `EpubReaderView._buildPreferencesMap()` 既有慣例。
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
        widget.onLayoutResolved?.call(info);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AndroidView(
          viewType: 'cc.ugotit.elinkbook/foliate_epub_reader_view',
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
        Positioned.fill(
          child: Column(
            children: List.generate(3, (row) {
              return Expanded(
                child: Row(
                  children: List.generate(3, (col) {
                    final index = row * 3 + col;
                    final action = widget.navZoneActions[index];
                    return Expanded(
                      child: GestureDetector(
                        key: Key('nav_zone_$index'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onZoneAction?.call(action),
                        onHorizontalDragStart: (_) {},
                        onVerticalDragStart: (_) {},
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.white24))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _zoneActionLabel(action),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                )
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  String _zoneActionLabel(ZoneAction action) {
    switch (action) {
      case ZoneAction.previousPage:
        return '上一頁';
      case ZoneAction.nextPage:
        return '下一頁';
      case ZoneAction.menu:
        return '選單';
      case ZoneAction.none:
        return '無動作';
    }
  }
}
