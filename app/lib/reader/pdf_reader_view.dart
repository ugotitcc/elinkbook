import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pdf_annotation_decoration.dart';
import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
import 'pdf_fit_mode.dart';
import 'pdf_page_info.dart';
import 'pdf_selection_info.dart';
import 'percent_rect.dart';
import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
import 'zone_action.dart';
import 'zone_hit_test.dart';

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
  final ValueChanged<PdfPageInfo>? onPageChanged;
  final PdfFitMode? fitMode;
  final double? contrast;
  final double? brightness;
  final double? boldStrength;
  final PdfCropMode? cropMode;
  final PdfCropRect? cropRect;
  final ValueChanged<PdfCropRect>? onCropRectComputed;
  final bool cropEditModeActive;
  final ValueChanged<PdfCropRect>? onCropRectSelected;
  final DualPageMode dualPageMode;
  final bool dualPageCoverAlone;
  final DualPageDirection dualPageDirection;
  final bool isLandscape;

  /// 開書起始頁索引（0-indexed，epic-5-toc-pagination Issue 2）。`null`
  /// 代表無既有位置記錄，固定從頭開始——與其餘偏好參數不同，這是「一次性
  /// 開書起始值」，只在 `openBook` 當下送出一次，不參與
  /// [didUpdateWidget] 的偏好設定 diff 邏輯（見 Global Constraints）。
  final int? initialPageIndex;

  /// 使用者長按拖曳框選劃線範圍完成時觸發（epic-6-annotations Issue 3，
  /// ADR 0008）。呼叫端負責顯示 `AnnotationToolbar` 供選色/畫底線/加備註。
  final ValueChanged<PdfSelectionInfo>? onSelectionRectComputed;

  /// 框選狀態被原生端取消時觸發（縮放/平移手勢開始、或觸發翻頁/跳頁，
  /// 見 plan-issue-3.md Global Constraints）。呼叫端負責收起浮動工具列。
  final VoidCallback? onSelectionCanceled;

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
    this.dualPageMode = DualPageMode.auto,
    this.dualPageCoverAlone = true,
    this.dualPageDirection = DualPageDirection.rtl,
    this.isLandscape = false,
    this.initialPageIndex,
    this.onSelectionRectComputed,
    this.onSelectionCanceled,
    this.navZoneActions = const [
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ],
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
  });

  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();

  /// 供外部（`ReaderScreen`）安全呼叫 [_PdfReaderViewState.jumpToPage] 的
  /// 強型別 static helper（審查修正，`/superpowers:requesting-code-review`）：
  /// 不使用 `as dynamic` 跨越 State 的 private 邊界——本專案目前完全沒有
  /// 在 `--obfuscate` release 建置下驗證過 `dynamic` 呼叫私有類別方法的
  /// 行為，`dynamic` 呼叫搭配 tree-shaking／混淆是 Flutter 社群已知的潛在
  /// 崩潰風險類別（method 只被 dynamic 呼叫連結時，可能被視為未使用而被
  /// tree-shaking 移除，或在混淆重新命名後找不到對應符號）。[key] 對應的
  /// State 若尚未掛載或型別不符（例如原生 View 尚未建立），靜默忽略，比照
  /// `nextPage()`/`previousPage()` 既有的 fire-and-forget 慣例。
  static void jumpToPage(GlobalKey<State<PdfReaderView>> key, int pageIndex) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state.jumpToPage(pageIndex);
    }
  }

  /// 供外部（`ReaderScreen._handleZoneAction`，epic-7-interaction Issue 4）
  /// 安全呼叫 [_PdfReaderViewState.nextPage] 的強型別 static helper，比照
  /// [jumpToPage] 既有模式。[key] 對應的 State 若尚未掛載，靜默忽略。
  static void nextPage(GlobalKey<State<PdfReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state.nextPage();
    }
  }

  /// 供外部（`ReaderScreen._handleZoneAction`，epic-7-interaction Issue 4）
  /// 安全呼叫 [_PdfReaderViewState.previousPage] 的強型別 static helper，
  /// 比照 [jumpToPage] 既有模式。[key] 對應的 State 若尚未掛載，靜默忽略。
  static void previousPage(GlobalKey<State<PdfReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state.previousPage();
    }
  }

  /// 把目前應顯示的完整標記清單一次性送給原生端（比照 EPUB
  /// `EpubReaderView.setDecorations` 整組送出慣例，非增量 diff），供原生
  /// 端重繪 Bitmap 快取上的劃線/備註疊加。呼叫時機：初次載入既有標記、
  /// 以及任何劃線/備註 CRUD 完成後。
  static void refreshAnnotations(
    GlobalKey<State<PdfReaderView>> key,
    List<PdfAnnotationDecoration> annotations,
  ) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._channel?.invokeMethod('refreshAnnotations', {
        'annotations': annotations.map((a) => a.toWire()).toList(),
      });
    }
  }
}

class _PdfReaderViewState extends State<PdfReaderView> {
  MethodChannel? _channel;

  // 長按拖曳框選手勢的相對定位/多指偵測狀態（epic-6-annotations Issue 3；
  // 審查修正，見 plan-issue-3.md Global Constraints「長按/拖曳的手勢辨識
  // 改由 Flutter 端 GestureDetector 主導」）。
  Size? _lastMeasuredSize;
  int _activeAnnotationPointerCount = 0;

  // 【偏離 task-2-brief.md Step 3 逐字碼，實作階段發現並修正，見
  // review-issue-4.md／task-2-report.md】9 格熱區點擊改由本區塊的
  // Listener 手動座標比對判讀，不能只靠 GestureDetector.onTapUp
  // （見下方 build() 中仍保留的 onTapUp: _handleZoneTap，理由見那裡的
  // 註解）：實測（含最小可重現案例，純 GestureDetector 包 AndroidView，
  // 無 Stack/IgnorePointer 涉入）證實 Flutter 的
  // GestureArenaManager.sweep()「若無人在放開前主動 accept/reject，仲裁
  // 給第一個加入手勢競技場的成員」預設規則，會讓 AndroidView 內建、永遠
  // 被動不主動 accept 的 _PlatformViewGestureRecognizer（因為 AndroidView
  // 在畫面樹中比本 GestureDetector 更深，其 handleEvent 一定先被呼叫、先
  // 加入競技場）100% 贏得每一次「純點擊、無明顯移動」手勢，導致
  // onTapUp 永遠不會觸發——這與 spec.md 審查修正（第 34 行）「PDF 原生層
  // 沒有任何觸控監聽，沒有『搶手勢競技場』的對象」的假設不符：AndroidView
  // 是否贏得競技場，是 Flutter 框架本身的 PlatformView 整合機制決定，與
  // 內嵌的原生 View 本身有沒有自訂觸控監聽無關。相較之下，既有
  // onLongPressStart／onHorizontalDragEnd（已於本 issue 移除，ADR 0010）
  // 之所以先前運作正常，是因為 LongPress／Drag 這類手勢辨識器會在放開前
  // 主動呼叫 `resolve(accepted)`（分別在長按逾時、或移動超過門檻時）搶先
  // 決議，不需要仰賴 sweep() 的預設仲裁規則。
  //
  // 修正做法：改用本檔案既有的外層 [Listener]（`_handleAnnotationPointerDown`
  // ／`_handleAnnotationPointerUp`）手動比對按下/放開座標判斷是否為點擊。
  // Listener 是原始指標監聽器、不參與手勢競技場仲裁，保證每次按下/放開都
  // 會收到事件、不受上述問題影響；也完全不需要像 EpubReaderView FXL
  // 熱區疊加層那樣，用不透明疊加層整個擋住 AndroidView 換取贏得競技場
  // （見該檔案 build() 的取捨註解）——那個做法會讓 AndroidView 完全收不到
  // 熱區範圍內的任何觸控，与 design.md 決策 #18「PDF 新增 GestureDetector，
  // 與既有長按拖曳框選共存於同一手勢競技場」的設計意圖（維持與
  // AndroidView 正常共存，而非整個蓋住它）不符。
  Offset? _tapDownPosition;
  bool _longPressActive = false;

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    channel.invokeMethod('openBook', {
      'path': widget.filePath,
      'initialPreferences': _buildPreferencesMap(),
      if (widget.initialPageIndex != null)
        'initialPageIndex': widget.initialPageIndex,
    });
  }

  @override
  void didUpdateWidget(covariant PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fitMode != oldWidget.fitMode ||
        widget.contrast != oldWidget.contrast ||
        widget.brightness != oldWidget.brightness ||
        widget.boldStrength != oldWidget.boldStrength ||
        widget.cropMode != oldWidget.cropMode ||
        widget.dualPageMode != oldWidget.dualPageMode ||
        widget.dualPageCoverAlone != oldWidget.dualPageCoverAlone ||
        widget.dualPageDirection != oldWidget.dualPageDirection ||
        widget.isLandscape != oldWidget.isLandscape) {
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
    // 以下 4 個欄位由 ReaderScreen 解析為非 null 值後才會建構本 widget（見
    // docs/epics/epic-16-dual-page/spec.md「Null 預設值解析」），一律無
    // 條件放入 map，不比照上方其餘可選欄位的 null 判斷模式。
    map['dualPageMode'] = widget.dualPageMode.name;
    map['dualPageCoverAlone'] = widget.dualPageCoverAlone;
    map['dualPageDirection'] = widget.dualPageDirection.name;
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
      case 'onPageChanged':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onPageChanged?.call(PdfPageInfo(
          pageIndex: args['pageIndex'] as int,
          totalPages: args['totalPages'] as int,
        ));
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
      case 'onSelectionRectComputed':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onSelectionRectComputed?.call(PdfSelectionInfo(
          pageIndex: args['pageIndex'] as int,
          rect: PercentRect(
            left: (args['left'] as num).toDouble(),
            top: (args['top'] as num).toDouble(),
            right: (args['right'] as num).toDouble(),
            bottom: (args['bottom'] as num).toDouble(),
          ),
          // widget* 系列為相對整個 View（含 letterbox 留白）的百分比矩形，
          // 僅供浮動工具列定位使用，見 PdfSelectionInfo 的 widgetRect 說明。
          widgetRect: PercentRect(
            left: (args['widgetLeft'] as num).toDouble(),
            top: (args['widgetTop'] as num).toDouble(),
            right: (args['widgetRight'] as num).toDouble(),
            bottom: (args['widgetBottom'] as num).toDouble(),
          ),
        ));
        break;
      case 'onSelectionCanceled':
        widget.onSelectionCanceled?.call();
        break;
    }
  }

  /// 導航至下一頁
  void nextPage() => _channel?.invokeMethod('nextPage');

  /// 導航至上一頁
  void previousPage() => _channel?.invokeMethod('previousPage');

  /// 跳轉至指定頁碼（0-indexed，Epic 5 Issue 1，FR-23）。呼叫端（見
  /// ReaderScreen）負責把 ReaderFooter 的 1-indexed 使用者輸入轉換為
  /// 0-indexed 後才呼叫本方法。外部呼叫請一律透過 [PdfReaderView.jumpToPage]
  /// 這個強型別 static helper，不要用 `as dynamic` 直接呼叫本實例方法
  /// （審查修正，見 Global Constraints）。
  void jumpToPage(int pageIndex) => _channel?.invokeMethod('jumpToPage', pageIndex);

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handleAnnotationPointerDown,
      onPointerUp: _handleAnnotationPointerUp,
      onPointerCancel: _handleAnnotationPointerUp,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _lastMeasuredSize = constraints.biggest;
          return GestureDetector(
            onTapUp: _handleZoneTap,
            onLongPressStart: _handleLongPressStart,
            onLongPressMoveUpdate: _handleLongPressMoveUpdate,
            onLongPressEnd: _handleLongPressEnd,
            child: Stack(
              children: [
                AndroidView(
                  viewType: 'cc.ugotit.elinkbook/pdf_reader_view',
                  onPlatformViewCreated: _onPlatformViewCreated,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: _buildNavZoneOverlay(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 3×3 導航熱區疊加層——純視覺標記／除錯輔助線，永遠不攔截觸控（外層
  /// 包了 [IgnorePointer]），實際點擊判讀由 [_handleAnnotationPointerUp]
  /// 透過 [_dispatchZoneAction]（內部呼叫 [hitTestZoneIndex]）對座標運算
  /// 完成，兩者共用同一份 3×3 格線定義。`showNavZoneDebugOverlay == false`
  /// 時格子仍存在（供 widget test 以 `Key('nav_zone_$index')` 尋址並透過
  /// `tester.tap()` 觸發外層 [Listener] 的 `onPointerUp`），只是不顯示邊框
  /// 與文字標籤。
  Widget _buildNavZoneOverlay() {
    return GridView.count(
      crossAxisCount: 3,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(9, (index) {
        return Container(
          key: Key('nav_zone_$index'),
          decoration: widget.showNavZoneDebugOverlay
              ? BoxDecoration(border: Border.all(color: Colors.white24))
              : null,
          alignment: Alignment.center,
          child: widget.showNavZoneDebugOverlay
              ? Text(
                  _zoneActionLabel(widget.navZoneActions[index]),
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                )
              : null,
        );
      }),
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

  /// 掛在 [GestureDetector] 的 `onTapUp`，保留以符合 task-2-brief.md／
  /// spec.md 描述的「9 格 onTap 與既有長按拖曳框選共存於同一個
  /// GestureDetector」意圖，惟實測手勢競技場預設仲裁規則會讓 AndroidView
  /// 贏得每一次點擊（見上方 [_tapDownPosition] 欄位註解的完整說明），
  /// 因此本回呼在實機/測試上皆不會真的觸發；實際點擊判讀請見
  /// [_handleAnnotationPointerUp] 透過 [_dispatchZoneAction] 完成。
  void _handleZoneTap(TapUpDetails details) {
    _dispatchZoneAction(details.localPosition);
  }

  /// 依座標查表換算並觸發 [ZoneAction]，供 [_handleZoneTap]（GestureDetector
  /// 路徑，理論上不會被呼叫）與 [_handleAnnotationPointerUp]（實際生效的
  /// Listener 手動點擊判讀路徑）共用同一份邏輯。
  void _dispatchZoneAction(Offset localPosition) {
    final size = _lastMeasuredSize;
    if (size == null) return;
    final index = hitTestZoneIndex(
      dx: localPosition.dx,
      dy: localPosition.dy,
      width: size.width,
      height: size.height,
    );
    widget.onZoneAction?.call(widget.navZoneActions[index]);
  }

  /// 長按拖曳框選劃線範圍的手勢辨識（epic-6-annotations Issue 3，ADR
  /// 0008；審查修正 1.1）：與既有 9 格熱區點擊（`onTapUp`，epic-7-interaction
  /// Issue 4）掛在同一個 `GestureDetector`，由 Flutter 的手勢競技場自行
  /// 裁決「這根手指是要長按還是要點擊」，原生端不再自己監聽 `rootView`
  /// 觸控、也不需要猜測——這正是 Flutter 手勢框架設計來解決這種同一觸點
  /// 多種可能手勢的機制。三個回呼把觸點位置換算成相對本 widget 自身尺寸
  /// （[_lastMeasuredSize]，由外層 `LayoutBuilder` 提供）的百分比後送給
  /// 原生端；原生端收到後再自行換算為相對 bitmap 內容範圍的最終座標
  /// （見 plan-issue-3.md Global Constraints「PDF 座標協定」的兩段式
  /// 換算說明），本端不需要知道、也沒有管道取得 letterbox 換算所需的
  /// bitmap 實際像素尺寸。是否真的允許框選（`fitMode`／裁切/雙頁狀態）
  /// 一律交由原生端這個唯一權威來源判斷，本端無條件送出事件。
  ///
  /// [_longPressActive] 於此設為 true，供 [_handleAnnotationPointerUp] 的
  /// 手動點擊判讀邏輯判斷「這次放開是長按框選的放開，不是點擊」，避免
  /// 兩者重複觸發（見 [_tapDownPosition] 欄位註解的完整說明）。
  void _handleLongPressStart(LongPressStartDetails details) {
    _longPressActive = true;
    final size = _lastMeasuredSize;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    _channel?.invokeMethod('beginAnnotationSelection', {
      'xPct': details.localPosition.dx / size.width,
      'yPct': details.localPosition.dy / size.height,
    });
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final size = _lastMeasuredSize;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    _channel?.invokeMethod('updateAnnotationSelection', {
      'xPct': details.localPosition.dx / size.width,
      'yPct': details.localPosition.dy / size.height,
    });
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _longPressActive = false;
    _channel?.invokeMethod('endAnnotationSelection');
  }

  /// 多指偵測（design.md 決策 #15、spec.md 審查修正 1.3；審查修正 1.1
  /// 後改由 Dart 端負責，見 Global Constraints）：原生端不再持有觸控
  /// 序列，無法自行偵測第二指觸碰，改由本 widget 用 [Listener] 追蹤目前
  /// 螢幕上的觸點數，偵測到超過一指時通知原生端取消目前框選狀態。
  /// [_handleAnnotationPointerUp] 同時作為 `onPointerUp`／`onPointerCancel`
  /// 的處理函式（Dart 函式參數型別逆變允許以 `PointerEvent` 版本同時
  /// 賦值給 `PointerUpListener`／`PointerCancelListener` 兩種型別的參數，
  /// 不需要分別宣告兩份幾乎相同的方法）。
  ///
  /// 【epic-7-interaction Issue 4 新增】同時記錄本次手勢第一指的按下座標
  /// （[_tapDownPosition]），供 [_handleAnnotationPointerUp] 判讀是否為
  /// 點擊——完整理由見該欄位宣告處的註解（GestureDetector.onTapUp 因手勢
  /// 競技場與 AndroidView 內建 recognizer 的預設仲裁規則而實際上不會觸發）。
  /// 第二指（含）以後按下視為多指手勢，清空 [_tapDownPosition] 使其不被
  /// 誤判為點擊，與既有「多指觸碰取消框選」邏輯一致。
  void _handleAnnotationPointerDown(PointerDownEvent event) {
    _activeAnnotationPointerCount++;
    if (_activeAnnotationPointerCount > 1) {
      _channel?.invokeMethod('cancelAnnotationSelection');
      _tapDownPosition = null;
    } else {
      _tapDownPosition = event.localPosition;
      _longPressActive = false;
    }
  }

  /// 【epic-7-interaction Issue 4 新增】在既有多指計數遞減之前，判斷這次
  /// 放開是否構成一次點擊：必須是最後一指放開（`_activeAnnotationPointerCount
  /// == 1`）、事件本身是 [PointerUpEvent]（非 [PointerCancelEvent]）、期間
  /// 沒有觸發長按框選（`!_longPressActive`），且放開位置與按下位置的位移
  /// 沒有超過 [kTouchSlop]（Flutter 標準點擊位移容許誤差）。符合則呼叫
  /// [_dispatchZoneAction] 觸發對應熱區的 [ZoneAction]。
  void _handleAnnotationPointerUp(PointerEvent event) {
    final downPosition = _tapDownPosition;
    if (_activeAnnotationPointerCount == 1 &&
        event is PointerUpEvent &&
        !_longPressActive &&
        downPosition != null &&
        (event.localPosition - downPosition).distance <= kTouchSlop) {
      _dispatchZoneAction(event.localPosition);
    }
    if (_activeAnnotationPointerCount > 0) _activeAnnotationPointerCount--;
    _tapDownPosition = null;
  }
}
