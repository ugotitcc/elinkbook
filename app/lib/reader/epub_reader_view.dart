import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_font.dart';
import 'dual_page_mode.dart';
import 'epub_decoration.dart';
import 'epub_position_info.dart';
import 'epub_selection_info.dart';
import 'epub_text_align.dart';
import 'toc_entry.dart';
import 'page_turn_mode.dart';
import 'percent_rect.dart';
import 'writing_mode.dart';
import 'zone_action.dart';

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

  /// 開書起始定位（序列化後的 Readium Locator，epic-5-toc-pagination
  /// Issue 2）。`null` 代表無既有位置記錄，固定從書本開頭開始——與其餘
  /// 偏好參數不同，這是「一次性開書起始值」，只在 `openBook` 當下送出
  /// 一次，不參與 [didUpdateWidget] 的偏好設定 diff 邏輯（見 Global
  /// Constraints）。
  final String? initialLocatorJson;

  /// 目前定位變動時觸發（開書、翻頁、目錄跳轉），供呼叫端（ReaderScreen）
  /// 快取最新定位，於離開/背景時寫入資料庫。
  final ValueChanged<EpubPositionInfo>? onLocatorChanged;

  /// 3×3 導航熱區的動作對照表（epic-7-interaction Issue 2/4），長度固定
  /// 9，索引慣例見 `zone_hit_test.dart`（0-indexed、列優先）。點擊時查表
  /// 決定觸發哪個 [ZoneAction]。預設全部 [ZoneAction.none]（非 `required`
  /// ——比照 [dualPageMode] 等既有欄位的預設值慣例，避免既有大量測試呼叫
  /// 端需要逐一補上這個參數）。
  final List<ZoneAction> navZoneActions;

  /// 點擊熱區換算出動作後觸發，呼叫端（`ReaderScreen`）負責分派實際行為
  /// （換頁／切換沉浸模式，見 `ReaderScreen._handleZoneAction`）。比照
  /// [onCropRectComputed] 等既有回呼欄位，刻意為可選參數。
  final ValueChanged<ZoneAction>? onZoneAction;

  /// 是否疊加顯示熱區輔助線（邊框＋動作文字標籤），供使用者於設定畫面
  /// 開啟除錯用途（epic-7-interaction Issue 2/3 `showNavZoneDebugOverlay`）。
  final bool showNavZoneDebugOverlay;

  /// 全書字元數快取（epic-5-toc-pagination Issue 3）。`null` 代表尚未計算過，
  /// 原生端會觸發背景計算；非 `null` 則直接沿用快取值，不重新走訪全書。
  final int? totalCharacterCount;

  /// 原生端背景字元數計算完成時觸發（epic-5-toc-pagination Issue 3），
  /// 傳回全書字元數。供呼叫端（ReaderScreen）寫入快取。
  final ValueChanged<int>? onCharacterCountReady;

  /// 使用者原生選字手勢建立/變動選取範圍時觸發（epic-6-annotations
  /// Issue 2），供呼叫端顯示浮動工具列。
  final ValueChanged<EpubSelectionInfo>? onSelectionChanged;

  /// 選取範圍被清除時觸發（原生端 ActionMode 銷毀，例如使用者點擊選取
  /// 範圍以外的地方），供呼叫端收起浮動工具列。
  final VoidCallback? onSelectionCleared;

  /// 使用者點擊既有劃線/備註標記時觸發，傳回該筆標記的 id 字串（見
  /// `EpubDecoration` 的 id 編碼慣例 `"highlight:<id>"`／`"note:<id>"`），
  /// 供呼叫端開啟編輯/刪除 Dialog。
  final ValueChanged<String>? onAnnotationActivated;

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
    this.initialLocatorJson,
    this.onLocatorChanged,
    this.navZoneActions = const [
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ],
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
    this.totalCharacterCount,
    this.onCharacterCountReady,
    this.onSelectionChanged,
    this.onSelectionCleared,
    this.onAnnotationActivated,
  });

  /// 跳轉到指定全書進度比例（0.0-1.0），由 Dart 端 EpubPageEstimator
  /// 估算目標頁碼後換算。強型別 static helper，比照 PdfReaderView.jumpToPage
  /// 模式（見 Global Constraints「跨 State 私有邊界呼叫」）。
  static void jumpToProgression(
      GlobalKey<State<EpubReaderView>> key, double progression) {
    final state = key.currentState;
    if (state is _EpubReaderViewState) {
      state._channel?.invokeMethod('jumpToProgression', {
        'progression': progression,
      });
    }
  }

  /// 讀取全書目錄樹狀結構（epic-5-toc-pagination Issue 4）。與
  /// [jumpToProgression] 不同，這是請求/回應語意（回傳 `Future`），非
  /// fire-and-forget；`ReaderScreen` 於書本開啟後（`onLayoutResolved`
  /// 回報非固定版面時）預先呼叫一次並快取結果，樹狀結構本身不隨版面設定
  /// 變動而改變，不需重新抓取。原生端呼叫失敗或本 State 尚未掛載（例如
  /// 純 `flutter_test` 環境下 `_channel` 恆為 `null`，AndroidView 未真正
  /// 建立）時回傳空清單，不拋出例外。
  static Future<List<TocEntry>> loadTableOfContents(
    GlobalKey<State<EpubReaderView>> key,
  ) async {
    final state = key.currentState;
    if (state is! _EpubReaderViewState) return const [];
    final raw = await state._channel
        ?.invokeMethod<List<Object?>>('getTableOfContents');
    if (raw == null) return const [];
    return raw
        .map((e) => TocEntry.fromWire(e as Map<Object?, Object?>))
        .toList();
  }

  /// 依目錄項目的序列化 Locator 跳轉（epic-5-toc-pagination Issue 4），比照
  /// [jumpToProgression] 的強型別 static helper 模式，不使用 `as dynamic`
  /// 跨越 State 的 private 邊界。
  static void jumpToLocator(
    GlobalKey<State<EpubReaderView>> key,
    String locatorJson,
  ) {
    final state = key.currentState;
    if (state is _EpubReaderViewState) {
      state._channel?.invokeMethod('jumpToLocator', {
        'locatorJson': locatorJson,
      });
    }
  }

  /// 供外部（`ReaderScreen._handleZoneAction`，epic-7-interaction Issue 4）
  /// 供 `ReaderScreen._handleZoneAction` 呼叫下一頁／spread（僅 FXL 熱區使用；
  /// 流式 EPUB 的換頁完全由原生 Kotlin `InputListener` 自主處理，不經過這裡，
  /// 見 epic-7-interaction Issue 6）。強型別 static helper，比照
  /// `PdfReaderView.nextPage` 既有模式（epic-7 Issue 4），直接呼叫原生端
  /// Method Channel，不經過 State instance method。
  static void nextPage(GlobalKey<State<EpubReaderView>> key) {
    final state = key.currentState;
    if (state is _EpubReaderViewState) {
      state._channel?.invokeMethod('nextPage');
    }
  }

  /// 供 `ReaderScreen._handleZoneAction` 呼叫上一頁／spread，同上僅 FXL 熱區
  /// 使用。強型別 static helper，比照 `PdfReaderView.previousPage`。
  static void previousPage(GlobalKey<State<EpubReaderView>> key) {
    final state = key.currentState;
    if (state is _EpubReaderViewState) {
      state._channel?.invokeMethod('previousPage');
    }
  }

  /// 把目前應顯示的完整標記清單一次性送給原生端（比照既有
  /// `setPreferences` 整組送出慣例，非增量 diff），供 Readium
  /// `applyDecorations` 疊加視覺樣式。
  static void setDecorations(
    GlobalKey<State<EpubReaderView>> key,
    List<EpubDecoration> decorations,
  ) {
    final state = key.currentState;
    if (state is _EpubReaderViewState) {
      state._channel?.invokeMethod('setDecorations', {
        'decorations': decorations.map((d) => d.toWire()).toList(),
      });
    }
  }

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
      if (widget.initialLocatorJson != null)
        'initialLocatorJson': widget.initialLocatorJson,
      if (widget.totalCharacterCount != null)
        'totalCharacterCount': widget.totalCharacterCount,
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
      case 'onLocatorChanged':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onLocatorChanged?.call(EpubPositionInfo(
          locatorJson: args['locatorJson'] as String,
          progression: (args['progression'] as num?)?.toDouble(),
        ));
        break;
      case 'onCharacterCountReady':
        widget.onCharacterCountReady?.call(call.arguments as int);
        break;
      case 'onSelectionChanged':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onSelectionChanged?.call(EpubSelectionInfo(
          locatorJson: args['locatorJson'] as String,
          progression: (args['progression'] as num?)?.toDouble(),
          rect: PercentRect(
            left: (args['leftPct'] as num).toDouble(),
            top: (args['topPct'] as num).toDouble(),
            right: (args['rightPct'] as num).toDouble(),
            bottom: (args['bottomPct'] as num).toDouble(),
          ),
        ));
        break;
      case 'onSelectionCleared':
        widget.onSelectionCleared?.call();
        break;
      case 'onAnnotationActivated':
        widget.onAnnotationActivated?.call(call.arguments as String);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AndroidView(
          viewType: 'cc.ugotit.elinkbook/epub_reader_view',
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
        if (_isFixedLayout)
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
