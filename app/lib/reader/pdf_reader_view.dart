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
            onLongPressStart: _handleLongPressStart,
            onLongPressMoveUpdate: _handleLongPressMoveUpdate,
            onLongPressEnd: _handleLongPressEnd,
            child: AndroidView(
              viewType: 'cc.ugotit.elinkbook/pdf_reader_view',
              onPlatformViewCreated: _onPlatformViewCreated,
            ),
          );
        },
      ),
    );
  }

  /// 長按拖曳框選劃線範圍的手勢辨識（epic-6-annotations Issue 3，ADR
  /// 0008；審查修正 1.1）：與既有 `onHorizontalDragEnd` 掛在同一個
  /// `GestureDetector`，由 Flutter 的手勢競技場自行裁決「這根手指是要
  /// 長按還是要水平滑動翻頁」，原生端不再自己監聽 `rootView` 觸控、也不
  /// 需要猜測——這正是 Flutter 手勢框架設計來解決這種同一觸點多種可能
  /// 手勢的機制。三個回呼把觸點位置換算成相對本 widget 自身尺寸
  /// （[_lastMeasuredSize]，由外層 `LayoutBuilder` 提供）的百分比後送給
  /// 原生端；原生端收到後再自行換算為相對 bitmap 內容範圍的最終座標
  /// （見 plan-issue-3.md Global Constraints「PDF 座標協定」的兩段式
  /// 換算說明），本端不需要知道、也沒有管道取得 letterbox 換算所需的
  /// bitmap 實際像素尺寸。是否真的允許框選（`fitMode`／裁切/雙頁狀態）
  /// 一律交由原生端這個唯一權威來源判斷，本端無條件送出事件。
  void _handleLongPressStart(LongPressStartDetails details) {
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
  void _handleAnnotationPointerDown(PointerDownEvent event) {
    _activeAnnotationPointerCount++;
    if (_activeAnnotationPointerCount > 1) {
      _channel?.invokeMethod('cancelAnnotationSelection');
    }
  }

  void _handleAnnotationPointerUp(PointerEvent event) {
    if (_activeAnnotationPointerCount > 0) _activeAnnotationPointerCount--;
  }
}
