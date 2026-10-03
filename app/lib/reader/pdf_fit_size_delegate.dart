import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_fit_mode.dart';
import 'pdf_paginated_rules.dart';

/// pdfrx 預設的最大縮放（`PdfViewerSizeDelegateProviderLegacy` 的預設值）。
const double kPdfFitMaxZoom = 8.0;

/// 由 pdfrx 版面與頁碼取得「單元」矩形（一頁，或雙頁模式下一個 spread 的
/// 合併矩形）。矩形為 pdfrx 版面座標，不含頁邊距。
typedef PdfFitUnitRect = Rect Function(PdfPageLayout layout, int pageNumber);

/// 讓 Fit 模式（Page-fit／Fit Width／真實比例）決定 pdfrx 的初始縮放與最小
/// 縮放（epic-56 Issue 1）。
///
/// 提供者必須有穩定的相等性：pdfrx 在 `didUpdateWidget` 以 `!=` 比較新舊
/// provider，相等才不會重建 delegate。[unitRectOf] 請傳 State 方法的
/// tear-off（同一個 State 的 tear-off 相等）。
class PdfFitSizeDelegateProvider extends PdfViewerSizeDelegateProvider {
  const PdfFitSizeDelegateProvider({
    required this.fitMode,
    required this.unitRectOf,
    required this.pageMargin,
  });

  final PdfFitMode fitMode;
  final PdfFitUnitRect unitRectOf;

  /// 必須與 `PdfViewerParams.margin` 相同。
  final double pageMargin;

  @override
  PdfViewerSizeDelegate create() => PdfFitSizeDelegate(
        fitMode: fitMode,
        unitRectOf: unitRectOf,
        pageMargin: pageMargin,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfFitSizeDelegateProvider &&
          fitMode == other.fitMode &&
          unitRectOf == other.unitRectOf &&
          pageMargin == other.pageMargin;

  @override
  int get hashCode => Object.hash(fitMode, unitRectOf, pageMargin);
}

/// 繼承 pdfrx 公開的 Legacy delegate，只覆寫兩處：
/// 1. 最小縮放＝目前頁（或 spread）的 Fit 基準，使用者可放大、不可縮到基準以下；
/// 2. 開書初始縮放＝初始頁的 Fit 基準。
/// 旋轉／版面變更時保留閱讀位置等行為沿用 Legacy（其
/// `onLayoutUpdate` 在「目前縮放等於舊最小縮放」時會跟著新最小縮放走，所以
/// 停在基準的使用者旋轉螢幕後會自動套用新基準）。
class PdfFitSizeDelegate extends PdfViewerSizeDelegateLegacy {
  PdfFitSizeDelegate({
    required this.fitMode,
    required this.unitRectOf,
    required this.pageMargin,
  }) : super(
          maxScale: kPdfFitMaxZoom,
          minScale: 0.1,
          useAlternativeFitScaleAsMinScale: true,
          onePassRenderingScaleThreshold: 200 / 72,
          calculateInitialZoom: null,
        );

  final PdfFitMode fitMode;
  final PdfFitUnitRect unitRectOf;
  final double pageMargin;

  PdfViewerController? _fitController;

  @override
  void init(PdfViewerController controller) {
    super.init(controller);
    _fitController = controller;
  }

  @override
  void dispose() {
    _fitController = null;
    super.dispose();
  }

  /// 版面不可用或算不出有效縮放時回傳 null（呼叫端沿用 pdfrx 原本的指標）。
  double? _zoomFor(PdfPageLayout? layout, int? pageNumber, Size viewSize) {
    if (layout == null ||
        pageNumber == null ||
        pageNumber < 1 ||
        pageNumber > layout.pageLayouts.length) {
      return null;
    }
    return fitZoomForUnit(
      mode: fitMode,
      unitRect: unitRectOf(layout, pageNumber),
      pageMargin: pageMargin,
      viewSize: viewSize,
      maxZoom: kPdfFitMaxZoom,
    );
  }

  @override
  PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required PdfPageLayout? layout,
    required int? pageNumber,
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  }) {
    final metrics = super.calculateMetrics(
      viewSize: viewSize,
      layout: layout,
      pageNumber: pageNumber,
      pageMargin: pageMargin,
      boundaryMargin: boundaryMargin,
    );
    final zoom = _zoomFor(layout, pageNumber, viewSize);
    if (zoom == null) return metrics;
    return PdfViewerLayoutMetrics(
      minScale: zoom,
      maxScale: metrics.maxScale,
      coverScale: metrics.coverScale,
      alternativeFitScale: metrics.alternativeFitScale,
    );
  }

  @override
  void onLayoutInitialized({
    required PdfViewerLayoutSnapshot state,
    required int initialPageNumber,
    required double coverScale,
    required double? alternativeFitScale,
    required PdfPageLayout layout,
    required PdfDocument document,
  }) {
    final controller = _fitController;
    final zoom = _zoomFor(layout, initialPageNumber, state.viewSize);
    if (controller == null || zoom == null) {
      super.onLayoutInitialized(
        state: state,
        initialPageNumber: initialPageNumber,
        coverScale: coverScale,
        alternativeFitScale: alternativeFitScale,
        layout: layout,
        document: document,
      );
      return;
    }
    // 與 Legacy 相同的套用方式：以文件原點為中心設定縮放、不播動畫；之後
    // pdfrx 會再把初始頁帶進視野。
    unawaited(controller.setZoom(Offset.zero, zoom, duration: Duration.zero));
    // pdfrx 緊接著會 `_goToPage` 把初始頁帶進視野，其縮放取「頁面錨定矩形
    // 的 fit 值」與「目前縮放」較小者：基準小於等於該 fit（Page-fit／Fit
    // Width）時基準保留；基準更大（真實比例 1.0 且頁比可視範圍寬）時會被
    // 縮小。因此排一個 microtask（同一個 microtask 佇列，一定排在 pdfrx
    // 那次 `_goToPage` 之後執行）在基準縮放下重新定位到單元起點。下一幀繪
    // 製前就會完成，不會閃爍；dispose 後 _fitController 已清空則跳過。
    final unitTopLeft =
        unitRectOf(layout, initialPageNumber).inflate(pageMargin).topLeft;
    scheduleMicrotask(() {
      final c = _fitController;
      if (c == null || !c.isReady) return;
      unawaited(c.goToPosition(documentOffset: unitTopLeft, zoom: zoom));
    });
  }
}
