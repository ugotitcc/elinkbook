import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
import 'pdf_spread_layout.dart';
import 'pdf_annotation_decoration.dart';
import 'pdf_page_info.dart';
import 'pdf_page_turn_animation.dart';
import 'pdf_page_turn_mode.dart';
import 'pdf_image_filters.dart';
import 'pdf_paginated_rules.dart';
import 'pdf_filter_debounce.dart';
import 'pdf_fit_mode.dart';
import 'pdf_fit_size_delegate.dart';
import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
import 'pdf_toc_item.dart';
import 'pdf_selection_geometry.dart';
import 'pdf_selection_info.dart';
import 'pdf_search_match.dart';
import 'pdf_search_geometry.dart';
import 'bounce_tolerant_long_press_detector.dart';
import 'percent_rect.dart';
import 'reader_console_log.dart';
import 'tap_zone_detector.dart';
import 'zone_action.dart';
import '../l10n/app_localizations.dart';
import '../theme/elink_tokens.dart';

/// 以 pdfrx（PDFium + Dart FFI）為底層的 PDF 閱讀 widget
/// （epic-24-pdf-engine-rebuild Issue 1），取代現行以
/// android.graphics.pdf.PdfRenderer 為底層、透過 AndroidView PlatformView
/// 渲染的既有實作（ADR 0022）。單頁顯示＋頁碼＋跳頁（Issue 1）與雙頁並列
/// （Issue 2）已實作；影像濾鏡/劃線/目錄/搜尋/縮圖/FAB 工具列皆為後續獨立
/// 工單，尚未實作。
///
/// 頁碼慣例：pdfrx 的 PdfViewerController 使用 1-indexed pageNumber，本
/// widget 對外一律維持本專案既有的 0-indexed pageIndex 慣例，換算只發生
/// 在本檔案內部與 pdfrx API 的交界處。
class PdfReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final int? initialPageIndex;
  final ValueChanged<PdfPageInfo>? onPageChanged;

  // ── epic-24-pdf-engine-rebuild Issue 2 新增 ──
  /// 三態雙頁模式。**widget 層預設刻意為 [DualPageMode.never]**（不是
  /// 產品預設值 auto）：未傳此參數的既有呼叫端（Issue 1 既有測試）行為
  /// 與 Issue 1 逐位元相同。產品預設 auto 由 ResolvedPreferences 提供，
  /// 經 reader_screen.dart 明確傳入（見 Task 8）。
  final DualPageMode dualPageMode;
  final bool dualPageCoverAlone;
  final DualPageDirection dualPageDirection;
  /// 螢幕是否為橫向。由 ReaderScreen 既有的 isLandscape 傳入（與 EPUB
  /// FXL 分支同源），本 widget 不自行偵測方向。
  final bool isLandscape;

  // ── epic-24-pdf-engine-rebuild Issue 11 新增 ──
  /// PDF 換頁動畫，預設 [PdfPageTurnAnimation.slide]（現行既有 200ms 動畫，
  /// 未傳此參數的既有呼叫端行為不變）。
  final PdfPageTurnAnimation pdfPageTurnAnimation;

  /// PDF 翻頁模式（epic-56 Issue 2）。**widget 層預設刻意為連續捲動**（不是
  /// 產品預設的逐頁）：保護既有大量 `PdfReaderView` 測試；產品預設由
  /// `ReaderScreen` 以解析後的偏好明確傳入，比照 `dualPageMode`。**本 Issue
  /// 尚未讀取此參數**，逐頁渲染在 Issue 4 實作。
  final PdfPageTurnMode pdfPageTurnMode;

  /// Fit 模式（Page-fit／Fit Width／真實比例，epic-56 Issue 1）。`null`＝
  /// 不干預，沿用 pdfrx 現有的預設縮放行為（widget 層預設保守，保護既有
  /// 測試；產品預設由 `ReaderScreen` 傳入解析後的值，比照 `dualPageMode`）。
  final PdfFitMode? pdfFitMode;

  // ── epic-24-pdf-engine-rebuild Issue 3 新增 ──
  /// 對比度 -100..100、亮度 -100..100，皆預設 0（無調整）。
  final double pdfContrast;
  final double pdfBrightness;
  /// 0..1，0=不加粗（預設）。
  final double pdfBoldStrength;
  /// 三態裁切模式，預設 `PdfCropMode.none`。
  final PdfCropMode pdfCropMode;
  /// `pdfCropMode != none` 時才有意義；null 代表尚未有快取矩形。
  final PdfCropRect? pdfCropRect;
  /// 智慧自動裁切首次計算出矩形時觸發。
  final ValueChanged<PdfCropRect>? onCropRectComputed;
  /// 手動裁切互動模式是否啟用中，預設 false。
  final bool cropEditModeActive;

  // ── epic-24-pdf-engine-rebuild Issue 4 新增 ──
  /// 使用者長按拖曳框選完成（且非退化選取）時觸發，回報的座標已换算為
  /// 相對原始整頁（裁切啟用時已反向換算，見 pdf_selection_geometry.dart）。
  final ValueChanged<PdfSelectionInfo>? onSelectionRectComputed;
  /// 選取被取消時觸發（例如多指觸控介入，見 Task 3）。
  final VoidCallback? onSelectionCanceled;

  // ── epic-24-pdf-engine-rebuild Issue 8 新增 ──
  /// 3×3 導覽熱區設定，索引 0-8 對應左上→右下（design.md 決策 #8）。預設
  /// 全部 [ZoneAction.none]（比照 [FoliateEpubReaderView] 既有預設值），
  /// 實際產品預設由 ReaderScreen 透過 ResolvedPreferences.navZoneActions
  /// 明確傳入。
  final List<ZoneAction> navZoneActions;
  /// 使用者點擊熱區格子時觸發，帶入該格設定的 [ZoneAction]（包含
  /// [ZoneAction.none]，呼叫端自行決定是否忽略）。
  final ValueChanged<ZoneAction>? onZoneAction;
  /// 除錯用：顯示 9 宮格邊框與動作文字，預設 false。
  final bool showNavZoneDebugOverlay;

  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.initialPageIndex,
    this.onPageChanged,
    this.dualPageMode = DualPageMode.never,
    this.dualPageCoverAlone = true,
    this.dualPageDirection = DualPageDirection.rtl,
    this.isLandscape = false,
    this.pdfPageTurnAnimation = PdfPageTurnAnimation.slide,
    this.pdfPageTurnMode = PdfPageTurnMode.scroll,
    this.pdfFitMode,
    this.pdfContrast = 0,
    this.pdfBrightness = 0,
    this.pdfBoldStrength = 0,
    this.pdfCropMode = PdfCropMode.none,
    this.pdfCropRect,
    this.onCropRectComputed,
    this.cropEditModeActive = false,
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

  /// 跳轉至指定頁碼（0-indexed）。[key] 對應的 State 若尚未掛載或尚未
  /// 就緒，靜默忽略，比照現行 PdfReaderView 既有的 fire-and-forget 慣例。
  static void jumpToPage(GlobalKey<State<PdfReaderView>> key, int pageIndex) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._jumpToPage(pageIndex);
    }
  }

  /// 中止進行中的長按拖曳框選（若有），不影響已完成的選取（呼叫端另有
  /// `onSelectionCanceled` 回呼機制，見既有 `_cancelSelectionDrag()` 語意）
  /// （Epic 24 Issue 10 審查修正）：換頁事件（例如音量鍵，與觸控手勢是
  /// 完全獨立的輸入通道）可能在使用者長按拖曳框選進行中、尚未放開手指時
  /// 觸發，此時拖曳狀態內快照的頁碼/座標系仍是換頁前的舊頁面，若不主動
  /// 中止，使用者稍後放開手指仍會用這組過時快照算出矩形、對應到已經翻
  /// 過去的舊頁面重新彈出 AnnotationToolbar。[key] 對應的 State 若尚未
  /// 掛載，或本來就沒有進行中的拖曳，靜默忽略（比照 `_cancelSelectionDrag`
  /// 既有的空手勢防呆）。
  static void cancelActiveSelectionDrag(GlobalKey<State<PdfReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._cancelSelectionDrag();
    }
  }

  /// 導航至下一頁。
  static void nextPage(GlobalKey<State<PdfReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._nextPage();
    }
  }

  /// 導航至上一頁。
  static void previousPage(GlobalKey<State<PdfReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._previousPage();
    }
  }

  /// 一次性送出目前應顯示的完整標記清單（非增量 diff，比照 EPUB
  /// `EpubDecoration`／`setDecorations` 整組送出慣例）——epic-24 Issue 4
  /// 落地，取代 Issue 1 暫時性 no-op。[key] 對應的 State 若尚未掛載，
  /// 靜默忽略。
  static void refreshAnnotations(
    GlobalKey<State<PdfReaderView>> key,
    List<PdfAnnotationDecoration> annotations,
  ) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._setAnnotations(annotations);
    }
  }

  /// 在目前已開啟的文件內搜尋 [query]（大小寫不敏感），回傳所有符合位置
  /// （epic-24-pdf-engine-rebuild Issue 6）。文件尚未開啟完成或 [key]
  /// 尚未掛載時回傳空清單，比照既有靜態 helper 的靜默忽略慣例。
  static Future<List<PdfSearchMatch>> search(
    GlobalKey<State<PdfReaderView>> key,
    String query,
  ) async {
    final state = key.currentState;
    if (state is! _PdfReaderViewState) return const [];
    return state._search(query);
  }

  /// 一次性送出目前應高亮顯示的完整符合結果清單（非增量 diff，比照
  /// [refreshAnnotations] 整組送出慣例）。[currentIndex] 是 [matches]
  /// 清單中「目前使用者正在檢視」的索引，用不同顏色標示；`null` 代表尚無
  /// 目前選取的符合結果。
  static void setSearchHighlights(
    GlobalKey<State<PdfReaderView>> key,
    List<PdfSearchMatch> matches, {
    required int? currentIndex,
  }) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._setSearchHighlights(matches, currentIndex);
    }
  }

  /// 顯示搜尋跳轉的暫態高亮（epic-10-search Issue 5，spec.md §6）：
  /// [pageIndex] 為 0-indexed 目標頁碼，[rect] 為頁內精確座標。全程只會有
  /// 一個暫態高亮存在（與 [setSearchHighlights] 可能同時存在多筆符合
  /// 結果的既有 PDF 內文搜尋是完全獨立的概念，見本計畫 Global
  /// Constraints）。生命週期由呼叫端（[ReaderScreen]）的 Dart 端 Timer
  /// 主導，本方法本身不會自動清除，需搭配 [clearTemporaryHighlight]
  /// 呼叫。[key] 對應的 State 若尚未掛載，靜默忽略。
  static void showTemporaryHighlight(
    GlobalKey<State<PdfReaderView>> key,
    int pageIndex,
    PercentRect rect,
  ) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._setJumpHighlight(pageIndex, rect);
    }
  }

  /// 清除目前顯示中的搜尋跳轉暫態高亮（若有）。[key] 對應的 State 若尚未
  /// 掛載，靜默忽略。
  static void clearTemporaryHighlight(GlobalKey<State<PdfReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._setJumpHighlight(null, null);
    }
  }

  /// 解析 PDF 內建大綱（Outline／Bookmark），一次性轉換為 [PdfTocItem]
  /// 樹狀結構（epic-24-pdf-engine-rebuild Issue 5）。文件尚未開啟完成
  /// （State 的 `_document` 為 null）或 [key] 尚未掛載時回傳空清單，比照
  /// [jumpToPage] 等既有靜態 helper 的靜默忽略慣例。
  static Future<List<PdfTocItem>> loadTableOfContents(
    GlobalKey<State<PdfReaderView>> key,
  ) async {
    final state = key.currentState;
    if (state is! _PdfReaderViewState) return const [];
    return state._loadTableOfContents();
  }

  /// 產生第 [pageIndex] 頁（0-indexed）的縮圖，寬度縮放至 [maxWidth]、
  /// 高度依頁面原始長寬比等比例換算（epic-24-pdf-engine-rebuild
  /// Issue 7）。文件尚未開啟完成、[pageIndex] 超出範圍、或 [key] 尚未掛載
  /// 時回傳 `null`，比照 [search]／[loadTableOfContents] 等既有靜態
  /// helper 的靜默忽略慣例。呼叫端負責在使用完畢後釋放回傳影像（
  /// `dispose()`）——[PdfThumbnailPanel] 透過 `PdfThumbnailCache` 管理
  /// 生命週期，見 `pdf_thumbnail_cache.dart`／`pdf_thumbnail_panel.dart`。
  static Future<ui.Image?> renderThumbnail(
    GlobalKey<State<PdfReaderView>> key,
    int pageIndex, {
    required double maxWidth,
  }) async {
    final state = key.currentState;
    if (state is! _PdfReaderViewState) return null;
    return state._renderThumbnail(pageIndex, maxWidth);
  }
}

class _PdfReaderViewState extends State<PdfReaderView> {
  final _controller = PdfViewerController();
  PdfDocument? _document;
  Object? _error;
  bool _renderedNotified = false;
  static const _resourceChannel = MethodChannel('elinkbook/reader_resources_cache');
  String? _contentUriTmpPath;

  /// 最近一次雙頁版面計算結果，由 [_layoutSpreadPages] 在 build 期間寫入
  /// （純快取，不 setState）。單頁模式下為 null。刻意不改用
  /// `PdfViewerController.layout`：該 getter 在版面尚未建立時會擲
  /// null-check error，且只回傳合併後的頁面矩形，拿不到 spread 分組
  /// 資訊。
  PdfSpreadLayout? _spreadLayout;

  /// computeSpreadLayout 的 memo 鍵——**必須涵蓋所有會影響版面計算結果的
  /// 輸入**（頁數、封面獨立、配對方向、margin），不能只用頁數：若只用頁
  /// 數當鍵，快取正確性就會完全依賴呼叫端（Task 7 的 `didUpdateWidget`）
  /// 手動清空快取這個外部協調，屬脆弱耦合——日後若有人修改
  /// `didUpdateWidget` 的變更偵測邏輯卻忘記同步處理快取，會靜默沿用過期
  /// 版面（例如翻頁座標與實際畫面不符）。用完整輸入當鍵，讓
  /// `_layoutSpreadPages` 自身就具備正確性，不依賴外部協調。
  ///
  /// 輸入未變時直接回傳同一個 `PdfPageLayout` 實例，讓 pdfrx 的版面變更
  /// 比對可以走 `identical()` 快速路徑。
  ({int pageCount, bool coverAlone, DualPageDirection direction, double margin})?
      _cachedLayoutKey;
  PdfPageLayout? _cachedPdfLayout;

  /// pdfrx 頁邊距。同時傳給 `PdfViewerParams.margin` 與 Fit 縮放計算，兩處
  /// 必須同值（pdfrx 預設即為 8.0）。
  static const double _pdfPageMargin = 8.0;

  /// Fit 縮放的「單元」矩形：雙頁模式為頁面所屬 spread 的合併矩形，否則為
  /// 該頁（裁切時 pdfrx 版面本身已是裁切後尺寸）。以 State 方法 tear-off 傳給
  /// [PdfFitSizeDelegateProvider]，tear-off 具備穩定的 == 語意。
  Rect _unitRectFor(PdfPageLayout layout, int pageNumber) {
    final paged = _paginated ? _paged : null;
    if (paged != null && paged.pageToUnit.length == layout.pageLayouts.length) {
      return paged.unitRects[paged.pageToUnit[pageNumber - 1]];
    }    final spread = _dualPageEnabled ? _spreadLayout : null;
    if (spread == null) return layout.pageLayouts[pageNumber - 1];
    // _spreadLayout 由 _layoutSpreadPages 在 pdfrx 每次排版時更新，而 pdfrx 在
    // 同一次 _updateLayout 中先排版、再算縮放指標，所以此處讀到的 spread 與
    // 傳入的 layout 一致。spreadIndexOf 對超界與空陣列會 clamp／回 0，不需要
    // 再自行防呆。
    return spread.spreadRects[spread.spreadIndexOf(pageNumber - 1)];
  }

  // ── epic-56 Issue 4：逐頁（paginated）──

  bool get _paginated => widget.pdfPageTurnMode == PdfPageTurnMode.paginated;

  /// 逐頁一律需要 Fit 模式；widget 層沒傳（null）時以 Page-fit 運作。產品端由
  /// `ReaderScreen` 一律傳入解析後的值。
  PdfFitMode get _effectiveFitMode => widget.pdfFitMode ?? PdfFitMode.pageFit;

  /// 外層 `LayoutBuilder` 記下的可視尺寸。pdfrx 的 `layoutPages` 閉包拿不到視窗
  /// 尺寸，而逐頁間距依視窗尺寸計算（Issue 3 spike：同一輪內閉包讀到的尺寸與
  /// 控制器一致）。
  Size _viewSize = Size.zero;

  /// 目前單元的錨點頁（0-based）。逐頁下「目前顯示哪個單元」的單一事實來源：
  /// 導覽時先更新它再 `goToPosition`；`calculateCurrentPageNumber`、
  /// `normalizeMatrix`、Fit 基準都以它為準，與可視矩形的頁內偏移無關（規則 10）。
  int _pagedAnchorPage = 0;

  /// 最近一次逐頁版面（含單元矩形與頁→單元對照），由 [_layoutPaginatedPages]
  /// 寫入（純快取，不 setState）。
  PaginatedLayout? _paged;
  ({
    int pageCount,
    bool dual,
    bool coverAlone,
    DualPageDirection direction,
    double margin,
    PdfCropRect? crop,
    PdfFitMode fit,
    Size viewSize,
  })? _pagedCacheKey;
  PdfPageLayout? _pagedPdfLayout;

  /// 版面變更前的逐頁版面：視窗只有高度改變（軟鍵盤）時，用它換算「頁內相對位置」，
  /// 在新版面中保留（最終審查 I-1）。
  PaginatedLayout? _prevPaged;

  bool get _pagedActive => _paginated && _paged != null;

  /// 目前單元索引；尚無版面（或空文件）時回傳 null。
  int? _currentPagedUnit() {
    final paged = _paged;
    if (paged == null || paged.pageToUnit.isEmpty) return null;
    return paged.pageToUnit[_pagedAnchorPage.clamp(0, paged.pageToUnit.length - 1)];
  }

  /// 逐頁版面：先取既有版面（裁切／雙頁／單頁堆疊），再依 spec「幾何隔離」把各單元
  /// 縱向拉開。以完整輸入當 memo 鍵（比照 [_layoutSpreadPages]），輸入不變時回傳
  /// 同一個 [PdfPageLayout] 實例；pdfrx 每次 LayoutBuilder 重建都會呼叫它，不能
  /// 每次都重算整份文件。
  PdfPageLayout _layoutPaginatedPages(List<PdfPage> pages, PdfViewerParams params) {
    final key = (
      pageCount: pages.length,
      dual: _dualPageEnabled,
      coverAlone: widget.dualPageCoverAlone,
      direction: widget.dualPageDirection,
      margin: params.margin,
      crop: _cropEnabled ? widget.pdfCropRect : null,
      fit: _effectiveFitMode,
      viewSize: _viewSize,
    );
    final cached = _pagedPdfLayout;
    if (_pagedCacheKey == key && cached != null) return cached;

    final List<Rect> baseRects;
    final List<Rect> baseUnits;
    final List<int> pageToUnit;
    final Size baseSize;
    if (_cropEnabled) {
      final base = _layoutCroppedPages(pages, params);
      baseRects = base.pageLayouts;
      baseUnits = base.pageLayouts; // 裁切：每頁一個單元，單元矩形即裁切後頁面矩形
      baseSize = base.documentSize;
      pageToUnit = [for (var i = 0; i < pages.length; i++) i];
    } else if (_dualPageEnabled) {
      final base = _layoutSpreadPages(pages, params); // 同時更新 _spreadLayout
      baseRects = base.pageLayouts;
      // 單元矩形必須取 spreadRects（寬度已正規化為文件內容寬）：單頁 spread（封面獨立、
      // 收尾單頁）才會與雙頁 spread 有同一個縮放基準，翻頁時頁面大小不跳動（C-1）。
      baseUnits = _spreadLayout!.spreadRects;
      baseSize = base.documentSize;
      pageToUnit = _spreadLayout!.pageToSpread;
    } else {
      final stacked = stackPageRects(
        pageSizes: [for (final p in pages) Size(p.width, p.height)],
        margin: params.margin,
      );
      baseRects = stacked.rects;
      baseUnits = stacked.rects;
      baseSize = stacked.documentSize;
      pageToUnit = [for (var i = 0; i < pages.length; i++) i];
    }

    final paged = isolatePaginatedUnits(
      pageRects: baseRects,
      pageToUnit: pageToUnit,
      baseUnitRects: baseUnits,
      documentSize: baseSize,
      margin: params.margin,
      mode: _effectiveFitMode,
      viewSize: _viewSize,
      maxZoom: kPdfFitMaxZoom,
    );
    _prevPaged = _paged;
    _paged = paged;
    _pagedCacheKey = key;
    return _pagedPdfLayout = PdfPageLayout(
      pageLayouts: paged.pageRects,
      documentSize: paged.documentSize,
    );
  }

  /// 逐頁的頁碼：目前單元的錨點頁（1-indexed），與可視矩形無關（規則 10）。
  int? _calculatePagedPageNumber(
    Rect visibleRect,
    List<Rect> pageRects,
    PdfViewerController controller,
  ) {
    final paged = _paged;
    final unit = _currentPagedUnit();
    if (paged == null || unit == null || paged.pageRects.length != pageRects.length) {
      return controller.pageNumber;
    }
    return paged.unitAnchorPages[unit] + 1;
  }

  /// 單元的 Fit 基準縮放（含頁邊距、夾在上限內）。
  double? _pagedBaseZoom(Rect unitRect, Size viewSize) => fitZoomForUnit(
        mode: _effectiveFitMode,
        unitRect: unitRect,
        pageMargin: _pdfPageMargin,
        viewSize: viewSize,
        maxZoom: kPdfFitMaxZoom,
      );

  /// pdfrx 的 `normalizeMatrix`：逐頁下把縮放夾在單元基準之上、把平移鎖在目前單元
  /// 內（含置中與溢出規則）。矩陣由候選的縮放與可視左上角重新組出（見計畫「查證
  /// 過的 pdfrx 事實」）。尚無版面、版面頁數與 pdfrx 不一致（切換的暫態）、或
  /// 候選矩陣不可用時原樣放行。
  Matrix4 _normalizePagedMatrix(
    Matrix4 matrix,
    Size viewSize,
    PdfPageLayout layout,
    PdfViewerController? controller,
  ) {
    final paged = _paged;
    final unit = _currentPagedUnit();
    if (paged == null ||
        unit == null ||
        paged.pageRects.length != layout.pageLayouts.length) {
      return matrix;
    }
    final unitRect = paged.unitRects[unit];
    final base = _pagedBaseZoom(unitRect, viewSize);
    final zoom = matrix.storage[0];
    if (base == null || !zoom.isFinite || zoom <= 0) return matrix;
    final viewport = clampPagedViewport(
      unitContent: unitRect.inflate(_pdfPageMargin),
      viewSize: viewSize,
      baseZoom: base,
      maxZoom: kPdfFitMaxZoom,
      zoom: zoom,
      candidateTopLeft: Offset(-matrix.storage[12] / zoom, -matrix.storage[13] / zoom),
      direction: widget.dualPageDirection,
    );
    return _matrixForViewport(viewport);
  }

  /// 與 pdfrx `goToPosition` 相同的矩陣組法：縮放 [PagedViewport.zoom]、可視左上角
  /// 為 [PagedViewport.topLeft]。
  Matrix4 _matrixForViewport(PagedViewport v) => Matrix4.identity()
    ..setEntry(0, 0, v.zoom)
    ..setEntry(1, 1, v.zoom)
    ..setEntry(2, 2, v.zoom)
    ..setTranslationRaw(-v.topLeft.dx * v.zoom, -v.topLeft.dy * v.zoom, 0);

  /// 把 [unit] 帶到可視範圍：更新錨點頁、落在單元頂端（橫向依閱讀起始側）、基準縮放，
  /// 一律瞬間完成（`Duration.zero`），不繼承先前的頁內偏移與縮放（規則 6）。
  void _goToPagedUnit(int unit) {
    final paged = _paged;
    if (paged == null || unit < 0 || unit >= paged.unitCount) return;
    // 以外層 LayoutBuilder 記下的 _viewSize 為唯一來源：controller.viewSize 內部是
    // `_state._viewSize!`，版面尚未量測時會拋 null-check 例外（I-3）。
    final viewSize = _viewSize;
    if (!viewSize.isFinite || viewSize.width <= 0 || viewSize.height <= 0) return;
    final unitRect = paged.unitRects[unit];
    final base = _pagedBaseZoom(unitRect, viewSize);
    if (base == null) return;
    _pagedAnchorPage = paged.unitAnchorPages[unit];
    final viewport = clampPagedViewport(
      unitContent: unitRect.inflate(_pdfPageMargin),
      viewSize: viewSize,
      baseZoom: base,
      maxZoom: kPdfFitMaxZoom,
      zoom: base,
      direction: widget.dualPageDirection,
    );
    unawaited(_controller.goToPosition(
      documentOffset: viewport.topLeft,
      zoom: viewport.zoom,
      duration: Duration.zero,
    ));
  }


  bool get _dualPageEnabled =>
      widget.pdfCropMode == PdfCropMode.none &&
      isDualPageEnabled(
        mode: widget.dualPageMode,
        isLandscape: widget.isLandscape,
      );

  /// [pdfPageTurnAnimation] 對應的實際 [Duration]，供全部 4 處導頁呼叫
  /// （_jumpToPage/_nextPage/_previousPage/_goToSpread）共用單一定義來源。
  /// pdfrx 的 goToPage()/goToArea() 對 Duration.zero 有專門的同步捷徑（見
  /// pdfrx-2.4.7 pdf_viewer.dart `_goTo()` 的 `if (duration == Duration.zero)`
  /// 分支），瞬間跳頁不會跑動畫 ticker。逐頁（epic-56）一律零時長，忽略
  /// [PdfReaderView.pdfPageTurnAnimation]。
  Duration get _pageTurnDuration =>
      (_paginated || widget.pdfPageTurnAnimation == PdfPageTurnAnimation.none)
          ? Duration.zero
          : const Duration(milliseconds: 200);

  bool get _cropEnabled =>
      widget.pdfCropMode != PdfCropMode.none && widget.pdfCropRect != null;

  // ── Issue 3: 濾鏡/裁切狀態 ──
  static const _maxCachedOverlayImages = 6;
  final _boldOverlayImages = <int, ui.Image>{};
  final _overlayCacheKey = <int, ({PdfCropRect? crop, double bold})>{};
  var _committedBoldStrength = 0.0;
  final _boldDebouncer =
      PdfFilterDebouncer(delay: const Duration(milliseconds: 300));
  bool _cropDetectionInFlight = false;

  // ── Issue 4: 長按拖曳框選 ──

  /// 進行中的框選追蹤：非 null 代表使用者正在某一頁上長按拖曳。記錄手勢
  /// 開始時所在的頁碼與該頁當下的 `pageRectInViewer`（拖曳過程中頁面
  /// 理論上不會移動——長按辨識成功後 `pdfrx` 內建平移已經輸掉競技場，
  /// 見上方「手勢架構決策」），以及拖曳起點/目前終點的局部座標。
  _PdfSelectionDragState? _selectionDrag;
  // epic-27-reader-device-compat Issue 11：_finishSelectionDrag() 改為
  // 非同步（需要 await page.loadStructuredText() 萃取選取文字）後，任何
  // 會開始新框選手勢的地方都遞增這個世代編號；_finishSelectionDrag()
  // 在 await 之前先記下當下的編號，await 完成後比對編號是否仍相同，不同
  // 就代表使用者已經開始了下一次框選，這次的萃取結果是過期資料，直接
  // 丟棄不送出（比照既有 _searchSessionId 世代編號慣例，見 _search()）。
  int _selectionDragGenerationId = 0;

  int _activePointerCount = 0;

  List<PdfAnnotationDecoration> _annotations = const [];

  void _setAnnotations(List<PdfAnnotationDecoration> annotations) {
    if (!mounted) return;
    setState(() => _annotations = annotations);
  }

  List<PdfSearchMatch> _searchMatches = const [];
  int? _currentSearchMatchIndex;
  int _searchSessionId = 0;

  void _setSearchHighlights(List<PdfSearchMatch> matches, int? currentIndex) {
    setState(() {
      _searchMatches = matches;
      _currentSearchMatchIndex = currentIndex;
    });
  }

  // epic-10-search Issue 5：搜尋跳轉的暫態高亮，全程只會有一個存在。
  int? _jumpHighlightPageIndex;
  PercentRect? _jumpHighlightRect;

  // 【審查修正 M-3】加上 mounted 防護——雖然既有 _setSearchHighlights()
  // 沒有這道防護（呼叫鏈全程同步、key.currentState 非 null 已隱含當下
  // 仍是 mounted，理論上不需要），但 _setAnnotations() 已有這個慣例，
  // 補上不影響行為、多一層保險。
  void _setJumpHighlight(int? pageIndex, PercentRect? rect) {
    if (!mounted) return;
    setState(() {
      _jumpHighlightPageIndex = pageIndex;
      _jumpHighlightRect = rect;
    });
  }

  /// 直接對 [_document] 逐頁呼叫 `loadStructuredText()`／`allMatches()`，
  /// 不透過 `PdfViewer`／`PdfViewerController`（見 Global Constraints「不
  /// 使用 PdfTextSearcher」）。[_searchSessionId] 是簡易的搜尋世代編號
  /// （比照 `PdfTextSearcher._searchSession` 既有設計精神），避免使用者
  /// 快速輸入導致前一次尚未完成的搜尋，在完成時覆蓋掉更新一次搜尋已經
  /// 寫入的結果——每次呼叫先遞增世代編號，逐頁掃描過程中若世代編號已被
  /// 後續呼叫超車就提早回傳空清單，呼叫端（`ReaderScreen`）以最後一次
  /// 真正跑完的呼叫結果為準。
  Future<List<PdfSearchMatch>> _search(String query) async {
    final sessionId = ++_searchSessionId;
    final document = _document;
    if (document == null) return const [];
    final matches = <PdfSearchMatch>[];
    for (final page in document.pages) {
      if (sessionId != _searchSessionId) return const [];
      final text = await page.loadStructuredText();
      if (sessionId != _searchSessionId) return const [];
      await for (final m in text.allMatches(query, caseInsensitive: true)) {
        matches.add(PdfSearchMatch(
          pageIndex: page.pageNumber - 1,
          text: m.text,
          rect: pdfRectToPercentRect(
            rect: m.bounds,
            pageWidth: page.width,
            pageHeight: page.height,
          ),
        ));
      }
    }
    return matches;
  }

  /// 不使用 Isolate——`page.render()` 本身透過 pdfrx FFI 非同步呼叫取得
  /// 指定尺寸的頁面圖片，不涉及額外的純 Dart 像素運算（與 Issue 3
  /// `_detectCropRect`／`_recomputeOverlay` 呼叫 `page.render()` 的既有
  /// 模式相同，兩者皆未用 Isolate 包裹這個呼叫本身，見 Global
  /// Constraints）。[maxWidth] 是縮圖目標寬度（邏輯像素），高度依頁面
  /// 原始長寬比等比例換算，避免縮圖影像變形。
  Future<ui.Image?> _renderThumbnail(int pageIndex, double maxWidth) async {
    final document = _document;
    if (document == null) return null;
    if (pageIndex < 0 || pageIndex >= document.pages.length) return null;
    final page = document.pages[pageIndex];
    final scale = maxWidth / page.width;
    final rendered = await page.render(
      fullWidth: maxWidth,
      fullHeight: page.height * scale,
    );
    if (rendered == null) return null;
    try {
      return await rendered.createImage();
    } finally {
      rendered.dispose();
    }
  }

  /// `PdfOutlineNode.dest?.pageNumber` 是 1-indexed（已查證
  /// `pdfrx_engine-0.4.5` 原始碼：`pdf_viewer.dart` 內部一律以
  /// `dest.pageNumber - 1` 索引 `document.pages[]`），換算為本專案既有的
  /// 0-indexed `pageIndex` 慣例。`stableId` 用遞增計數器（前序走訪順序）
  /// 產生，保證整棵樹唯一，不依賴頁碼或標題（大綱可能有多個節點指向
  /// 同一頁）——計數器刻意宣告為本方法內的區域變數（透過巢狀函式
  /// `convert` 閉包捕捉），不放在 State 欄位：若放在 State 欄位，
  /// `loadTableOfContents` 這個 public static API 被短時間內重入呼叫時
  /// （例如測試或未來呼叫端不慎重複觸發），後一次呼叫的重置會汙染前一次
  /// 呼叫尚在進行中的走訪計數，導致 `stableId` 不再保證唯一（審查修正，
  /// review-plan-issue-5.md Important #1）。改為區域變數後，每次呼叫都有
  /// 各自獨立的計數器，天生具備重入安全性。
  Future<List<PdfTocItem>> _loadTableOfContents() async {
    final document = _document;
    if (document == null) return const [];
    final outline = await document.loadOutline();
    var tocIdCounter = 0;

    List<PdfTocItem> convert(List<PdfOutlineNode> nodes) {
      return [
        for (final node in nodes)
          PdfTocItem(
            title: node.title,
            pageIndex: (node.dest == null || node.dest!.pageNumber <= 0) ? null : node.dest!.pageNumber - 1,
            stableId: 'pdf_toc_${tocIdCounter++}',
            children: convert(node.children),
          ),
      ];
    }

    return convert(outline);
  }

  /// contrast/brightness 皆為預設值時回傳 null，讓 build() 省略
  /// ColorFiltered 包裝。
  ColorFilter? get _colorFilter {
    if (widget.pdfContrast == 0 && widget.pdfBrightness == 0) return null;
    return ColorFilter.matrix(
      contrastBrightnessColorMatrix(
        contrast: widget.pdfContrast,
        brightness: widget.pdfBrightness,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _committedBoldStrength = widget.pdfBoldStrength;
    _pagedAnchorPage = widget.initialPageIndex ?? 0;
    _openDocument();
  }

  Future<void> _openDocument() async {
    try {
      final document = widget.filePath.contains('://')
          ? await _openContentUriDocument()
          : await PdfDocument.openFile(widget.filePath);
      if (!mounted) {
        await document.dispose();
        return;
      }
      setState(() => _document = document);
    } catch (e) {
      if (!mounted) return;
      ReaderConsoleLog.add('[PdfReaderView] _openDocument 失敗: $e');
      setState(() => _error = e);
      widget.onError(AppLocalizations.of(context)!.readerFailedToLoadBookMessage);
    }
  }

  /// content:// URI 開書（epic-24-pdf-engine-rebuild Issue 2）：
  /// pdfrx 的 PdfDocument.openCustom 雖然宣告 read callback 為 FutureOr(int)，
  /// 但內部 PDFium FFI 實作是在 native 執行緒同步呼叫該 callback，無法等待
  /// MethodChannel 回傳的 Future（已知技術風險，見 plan-issue-1 Task 2）。
  /// 因此改為：原生端透過串流複製將 content:// URI 寫入 App 快取目錄的暫存
  /// 檔，回傳路徑字串，Dart 端直接以 PdfDocument.openFile() 開啟。避免 Dart 端
  /// 一次性載入全部位元組（readBytes + writeAsBytes 雙倍記憶體壓力）。
  Future<PdfDocument> _openContentUriDocument() async {
    // 1. 透過平台通道取得 content:// URI 串流複製後的暫存檔路徑。
    final tmpPath = await _resourceChannel.invokeMethod<String>(
      'readContentUriAll',
      {'uri': widget.filePath},
    );
    if (tmpPath == null || tmpPath.isEmpty) {
      throw StateError('無法讀取檔案：${widget.filePath}');
    }
    // 2. 直接以 openFile() 開啟——PDFium FFI 在 native 執行緒同步讀取檔案，
    //    不涉及非同步 read callback。暫存檔在 dispose() 時清理。
    _contentUriTmpPath = tmpPath;
    return PdfDocument.openFile(tmpPath);
  }

  /// 待版面重算後要重新對齊的 spread 錨點頁（0-indexed）。
  int? _pendingReanchorPageIndex;

  @override
  void didUpdateWidget(covariant PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Fit 模式切換（epic-56 Issue 1）：pdfrx 更換 sizeDelegateProvider 只會重建
    // delegate，不會重算最小縮放也不會重新套用縮放，須明確處理。
    // 與下方雙頁／裁切變更的 reanchor 同時發生時，兩者都排兩層 postFrameCallback，
    // 依註冊順序先執行本處的縮放、再執行 reanchor 的跳頁；Fit 模式啟用時跳頁
    // 一律以該單元的 Fit 基準縮放定位（見 _goToUnitAtFitZoom），不會改掉基準。
    if (oldWidget.pdfFitMode != widget.pdfFitMode) {
      _scheduleRefit();
    }

    // 加粗強度 debounce：300ms 沉澱後才更新 _committedBoldStrength。
    if (oldWidget.pdfBoldStrength != widget.pdfBoldStrength) {
      _boldDebouncer.schedule(() {
        if (!mounted) return;
        setState(() => _committedBoldStrength = widget.pdfBoldStrength);
      });
    }

    final changed = oldWidget.dualPageMode != widget.dualPageMode ||
        oldWidget.dualPageCoverAlone != widget.dualPageCoverAlone ||
        oldWidget.dualPageDirection != widget.dualPageDirection ||
        oldWidget.isLandscape != widget.isLandscape ||
        oldWidget.pdfCropMode != widget.pdfCropMode ||
        oldWidget.pdfCropRect != widget.pdfCropRect ||
        oldWidget.pdfPageTurnMode != widget.pdfPageTurnMode;
    if (!changed) return;

    // 切換前的錨點頁必須先記下來：relayout 後 pdfrx 會依自己的邏輯推一
    // 個目前頁，未必落在原本的 spread 上。
    // 切換前若是逐頁，錨點頁以 _pagedAnchorPage 為準（單一事實來源）：
    // controller.pageNumber 由 pdfrx 在矩陣變動後才更新，可能晚一幀。
    final anchorBefore =
        oldWidget.pdfPageTurnMode == PdfPageTurnMode.paginated
            ? _pagedAnchorPage
            : (_controller.isReady
                ? (_controller.pageNumber ?? 1) - 1
                : (widget.initialPageIndex ?? 0));

    if (!_dualPageEnabled) {
      _spreadLayout = null; // 停用雙頁後不得再用舊的 spread 矩形導航。
    }
    _cachedLayoutKey = null;
    _cachedPdfLayout = null;
    _pagedCacheKey = null;
    _pagedPdfLayout = null;
    _paged = null; // 版面重算前不使用舊的逐頁版面導航。
    if (_paginated) {
      // 切換前的錨點頁就是逐頁的目前單元錨點（reanchor 之後會重新對齊到單元）。
      _pagedAnchorPage = anchorBefore;
    }
    _pendingReanchorPageIndex = anchorBefore;

    // 【與 isReady 防呆同等重要】invalidate() 內部是 `_state._invalidate()`
    // ——`_state` getter 用 `!` 強制解包，若文件仍在非同步開啟中
    // （PdfViewer 尚未建構、controller 尚未 attach，`_controller.isReady`
    // 為 false），呼叫 invalidate() 會直接擲出 null-check 例外導致當機。
    // 未 ready 時不需要 invalidate：文件開完後 layoutPages/
    // calculateCurrentPageNumber 本來就會用當下最新的 widget 值全新計算，
    // 不需要手動觸發。
    if (_controller.isReady) {
      _controller.invalidate();
    }

    // 【時序注意，非顯而易見】invalidate() 觸發的 relayout（無論是走本
    // widget 的 _layoutSpreadPages，還是切回單頁模式時 pdfrx 內建的預設
    // 版面函式）並非在本次 didUpdateWidget 所屬的這一幀內同步完成——
    // invalidate() 是透過 pdfrx 內部的 BehaviorSubject（Stream）通知，
    // Stream 的監聽者（觸發 pdfrx 內部 rebuild 的 StreamBuilder）是在
    // microtask 才收到事件，而 microtask 要等本幀的
    // WidgetsBinding.drawFrame() 整個同步呼叫（含本幀所有
    // postFrameCallback）都返回事件迴圈後才會執行，也就是說實際 relayout
    // 要等到「下一幀」才會發生。若只註冊單層 addPostFrameCallback，會在
    // relayout 真正完成「之前」就先觸發，讀到的仍是切換前的舊版面/舊
    // 頁碼推算結果（尤其從雙頁切回單頁時，_layoutSpreadPages 根本不會
    // 再被呼叫，改用 pdfrx 內建版面，一樣要等下一幀才計算好）。因此改用
    // 兩層巢狀 addPostFrameCallback：第一層只是讓本幀先結束、把
    // microtask 排到的下一幀真正跑起來，第二層才是在那次 relayout
    // 完成之後才執行 reanchor，兩個方向（切入/切出雙頁模式）都適用，不
    // 需要依賴 _layoutSpreadPages 是否會被呼叫。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyPendingReanchor());
    });
  }

  void _applyPendingReanchor() {
    final pageIndex = _pendingReanchorPageIndex;
    _pendingReanchorPageIndex = null;
    if (pageIndex == null || !mounted || !_controller.isReady) return;
    _jumpToPage(pageIndex); // 走既有的單/雙頁分派邏輯。
  }

  /// 讓 pdfrx 重新排版（重算最小縮放），再於後續幀把縮放設為新模式的基準。
  /// 未就緒時不需處理：文件開完後 delegate 會依最新的 [PdfReaderView.pdfFitMode]
  /// 套用初始縮放。兩層 postFrameCallback 的原因同 [didUpdateWidget] 中
  /// reanchor 的說明（invalidate 的重排要等到下一幀才完成）。
  void _scheduleRefit() {
    if (!_controller.isReady) return;
    _controller.invalidate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyFitZoom());
    });
  }

  /// 把目前頁（雙頁為目前 spread）以新 Fit 模式的基準縮放顯示；使用者先前
  /// 手動放大的縮放會被重設為基準。以 goToPosition 設定，不受舊最小縮放夾制。
  void _applyFitZoom() {
    if (_paginated) {
      final unit = _currentPagedUnit();
      if (mounted && _controller.isReady && unit != null) _goToPagedUnit(unit);
      return;
    }
    final mode = widget.pdfFitMode;
    if (mode == null || !mounted || !_controller.isReady) return;
    final layout = _controller.layout;
    final pageNumber = _controller.pageNumber;
    // 與 delegate 的 _zoomFor 同樣防呆：頁碼暫時推算不出來（null）、版面為空或
    // 頁碼超界時不處理，避免重排尚未完成的暫態拋出 RangeError，或把使用者帶
    // 到第 1 頁。
    if (pageNumber == null ||
        pageNumber < 1 ||
        pageNumber > layout.pageLayouts.length) {
      return;
    }
    final unit = _unitRectFor(layout, pageNumber);
    final zoom = fitZoomForUnit(
      mode: mode,
      unitRect: unit,
      pageMargin: _pdfPageMargin,
      viewSize: _controller.viewSize,
      maxZoom: kPdfFitMaxZoom,
    );
    if (zoom == null) return;
    unawaited(_controller.goToPosition(
      documentOffset: unit.inflate(_pdfPageMargin).topLeft,
      zoom: zoom,
    ));
  }

  @override
  void dispose() {
    _boldDebouncer.dispose();
    for (final image in _boldOverlayImages.values) {
      image.dispose();
    }
    _document?.dispose();
    final tmpPath = _contentUriTmpPath;
    if (tmpPath != null) {
      unawaited(_cleanupTmpFile(tmpPath));
    }
    super.dispose();
  }

  /// 嘗試刪除暫存檔及其暫存目錄（若為空）。非空時 delete 抛出例外，忽略
  /// 即可——其他 PdfReaderView 實例可能仍在使用同一目錄下的不同暫存檔。
  Future<void> _cleanupTmpFile(String path) async {
    try {
      final tmpFile = File(path);
      await tmpFile.delete();
      try {
        await tmpFile.parent.delete();
      } catch (_) {}
    } catch (_) {}
  }

  void _jumpToPage(int pageIndex) {
    if (widget.cropEditModeActive) return;
    if (!_controller.isReady) return;
    if (pageIndex < 0 || pageIndex >= _controller.pageCount) return;
    if (_paginated) {
      // 以 _paginated（而非 _pagedActive）阻絕一切向連續捲動路徑的穿透：版面重算的暫態
      // （_paged 暫為 null）不得把逐頁使用者導向 goToPage／goToArea 的動畫路徑（I-2）。
      // 先記錄錨點頁：版面就緒後 normalizeMatrix 與頁碼推算都以它為準。
      // 規則 6：目錄、書籤、頁碼輸入、縮圖、全文搜尋面板、朗讀換頁、搜尋跳轉都經由這裡，
      // 一律落在目標單元（spread 取所屬單元）頂端、基準縮放，瞬間完成。
      _pagedAnchorPage = pageIndex;
      final paged = _paged;
      if (paged != null) _goToPagedUnit(paged.pageToUnit[pageIndex]);
      return;
    }
    final layout = _activeSpreadLayout;
    if (layout == null) {
      _goToSinglePage(pageIndex + 1);
      return;
    }
    _goToSpread(layout.spreadIndexOf(pageIndex), layout);
  }

  void _nextPage() {
    if (widget.cropEditModeActive) return;
    if (!_controller.isReady) return;
    if (_paginated) {
      // 同 _jumpToPage：逐頁一律不穿透到連續捲動路徑；版面暫態（_paged 為 null）時
      // _stepPagedUnit 內部直接無動作（I-2）。
      _stepPagedUnit(forward: true);
      return;
    }
    final layout = _activeSpreadLayout;
    if (layout == null) {
      final current = _controller.pageNumber ?? 1; // Issue 1 原邏輯。
      if (current >= _controller.pageCount) return;
      _goToSinglePage(current + 1);
      return;
    }
    final currentIndex = (_controller.pageNumber ?? 1) - 1;
    final next = layout.nextSpreadAnchor(currentIndex);
    if (next == null) return; // 已在最後一個 spread。
    _goToSpread(layout.spreadIndexOf(next), layout);
  }

  void _previousPage() {
    if (widget.cropEditModeActive) return;
    if (!_controller.isReady) return;
    if (_paginated) {
      _stepPagedUnit(forward: false);
      return;
    }
    final layout = _activeSpreadLayout;
    if (layout == null) {
      final current = _controller.pageNumber ?? 1; // Issue 1 原邏輯。
      if (current <= 1) return;
      _goToSinglePage(current - 1);
      return;
    }
    final currentIndex = (_controller.pageNumber ?? 1) - 1;
    final prev = layout.previousSpreadAnchor(currentIndex);
    if (prev == null) return; // 已在封面 spread。
    _goToSpread(layout.spreadIndexOf(prev), layout);
  }

  /// 逐頁的相對步進（熱區、音量鍵）。Issue 4 只有 Page-fit 子集：直接換到相鄰單元、
  /// 落在新單元頂端；單元縱向溢出時也一樣（暫態降級，頁內逐屏步進與「上一頁落在
  /// 上一單元底端」見 Issue 5）。第一／最後單元再往外＝無動作。
  void _stepPagedUnit({required bool forward}) {
    final paged = _paged;
    final current = _currentPagedUnit();
    if (paged == null || current == null) return;
    final target = pagedAdjacentUnit(
      currentUnit: current,
      unitCount: paged.unitCount,
      forward: forward,
    );
    if (target == null) return;
    _goToPagedUnit(target);
  }

  bool? _onPagedKey(
    PdfViewerKeyHandlerParams params,
    LogicalKeyboardKey key,
    bool isRealKeyPress,
  ) {
    if (widget.cropEditModeActive || !_controller.isReady) return null;
    if (key == LogicalKeyboardKey.pageDown) {
      _stepPagedUnit(forward: true);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _stepPagedUnit(forward: false);
    } else if (key == LogicalKeyboardKey.space) {
      _stepPagedUnit(forward: !HardwareKeyboard.instance.isShiftPressed);
    } else if (key == LogicalKeyboardKey.home) {
      _jumpToPage(0);
    } else if (key == LogicalKeyboardKey.end) {
      _jumpToPage(_controller.pageCount - 1);
    } else {
      return null;
    }
    return true;
  }

  void _handlePageChanged(int? pageNumber) {
    if (pageNumber == null || !_controller.isReady) return;
    widget.onPageChanged?.call(PdfPageInfo(
      pageIndex: pageNumber - 1,
      totalPages: _controller.pageCount,
    ));
  }

  /// PdfPageLayoutFunction 實作。以 instance method tear-off 形式傳給
  /// PdfViewerParams（見 build()）——同一個 State 的 tear-off 具備穩定的
  /// == 語意；設定值（coverAlone/direction）在呼叫當下讀 widget.xxx，
  /// 設定變更會反映到新算出的 PdfPageLayout 上。
  PdfPageLayout _layoutSpreadPages(List<PdfPage> pages, PdfViewerParams params) {
    final key = (
      pageCount: pages.length,
      coverAlone: widget.dualPageCoverAlone,
      direction: widget.dualPageDirection,
      margin: params.margin,
    );
    if (_cachedLayoutKey == key && _cachedPdfLayout != null) {
      return _cachedPdfLayout!;
    }
    final layout = computeSpreadLayout(
      pageSizes: [for (final p in pages) Size(p.width, p.height)],
      margin: params.margin,
      coverAlone: widget.dualPageCoverAlone,
      direction: widget.dualPageDirection,
    );
    _spreadLayout = layout;
    _cachedLayoutKey = key;
    return _cachedPdfLayout = PdfPageLayout(
      pageLayouts: layout.pageRects, // pdfrx 契約：index i 對應第 i+1 頁。
      documentSize: layout.documentSize,
    );
  }

  /// 覆寫 pdfrx 的目前頁碼推算：雙頁模式下一律回報「可視區域內佔比最大
  /// 的那一頁所屬 spread 的錨點頁」，而非該頁本身。這讓
  /// controller.pageNumber 在雙頁模式下恆為 spread 錨點，於是
  /// onPageChanged 回報的 PdfPageInfo.pageIndex、閱讀位置持久化、
  /// _nextPage/_previousPage 的步進基準三者共用同一個定義（沿用已刪除
  /// 的舊 Kotlin currentPageIndex 語意）。
  ///
  /// 回傳為 pdfrx 慣例的 1-indexed pageNumber。
  int? _calculateSpreadAnchorPageNumber(
    Rect visibleRect,
    List<Rect> pageRects,
    PdfViewerController controller,
  ) {
    final layout = _spreadLayout;
    if (layout == null) return controller.pageNumber;

    var bestIndex = -1;
    var bestArea = 0.0;
    for (var i = 0; i < pageRects.length; i++) {
      final inter = pageRects[i].intersect(visibleRect);
      if (inter.isEmpty) continue;
      final area = inter.width * inter.height;
      // 嚴格 > 比較：面積相等（平手）時保留先遍歷到的較小 pageIndex，
      // 即該 spread 的錨點頁——這是刻意利用「較小 index 較早被遍歷」
      // 這件事維持錨點頁語意，不是巧合，不要改成 >=（那會讓平手時保留
      // 後遍歷到的較大 index，可能回報非錨點頁）。
      if (area > bestArea) {
        bestArea = area;
        bestIndex = i;
      }
    }
    if (bestIndex < 0) return controller.pageNumber; // 完全捲出版面外。
    return layout.anchorPageOf(layout.spreadIndexOf(bestIndex)) + 1;
  }

  /// 雙頁模式下的統一導航：把整個 spread 帶入視野。用 goToArea 而非
  /// goToPage：goToPage 只 fit 單一頁面矩形（會把 spread 的另一半推出
  /// 畫面），且其內部會直接 _setCurrentPageNumber(目標頁)，繞過
  /// calculateCurrentPageNumber，造成頁碼有兩個來源。goToArea 不設定
  /// 頁碼，頁碼一律由 _calculateSpreadAnchorPageNumber 於動畫過程中
  /// 推導，維持單一事實來源。
  void _goToSpread(int spreadIndex, PdfSpreadLayout layout) {
    if (spreadIndex < 0 || spreadIndex >= layout.spreadCount) return;
    if (widget.pdfFitMode != null) {
      _goToUnitAtFitZoom(layout.spreadRects[spreadIndex]);
      return;
    }
    unawaited(_controller.goToArea(
      rect: layout.spreadRects[spreadIndex],
      anchor: PdfPageAnchor.all,
      duration: _pageTurnDuration,
    ));
  }

  /// 單頁模式的導航。[PdfReaderView.pdfFitMode] 為 null 時走 pdfrx 原本的
  /// goToPage（零回歸）；否則以該頁的 Fit 基準縮放定位（見
  /// [_goToUnitAtFitZoom]）。
  void _goToSinglePage(int pageNumber) {
    if (widget.pdfFitMode == null) {
      _controller.goToPage(
        pageNumber: pageNumber,
        duration: _pageTurnDuration,
      );
      return;
    }
    final rects = _controller.layout.pageLayouts;
    if (pageNumber < 1 || pageNumber > rects.length) return;
    _goToUnitAtFitZoom(rects[pageNumber - 1]);
  }

  /// Fit 模式啟用時的導航（epic-56 Issue 1 程式審查 I-1／I-2）：把單元
  /// （一頁或一個 spread）以 Fit 基準縮放帶到可視範圍起點，換頁後縮放回到
  /// 基準。不用 pdfrx 的 goToPage／goToArea：goToPage 的縮放取「目前縮放」與
  /// 「頁寬 fit」較小者（真實比例 1.0 遇到比螢幕寬的頁會被縮成頁寬），
  /// goToArea(anchor: all) 一律把整個矩形放進螢幕（Fit Width 與真實比例會
  /// 失效）。goToPosition 不會設定頁碼，頁碼仍由 pdfrx 依可視範圍推導
  /// （雙頁為 [_calculateSpreadAnchorPageNumber]），維持單一事實來源。
  void _goToUnitAtFitZoom(Rect unitRect) {
    final mode = widget.pdfFitMode;
    if (mode == null) return;
    final zoom = fitZoomForUnit(
      mode: mode,
      unitRect: unitRect,
      pageMargin: _pdfPageMargin,
      viewSize: _controller.viewSize,
      maxZoom: kPdfFitMaxZoom,
    );
    if (zoom == null) return;
    unawaited(_controller.goToPosition(
      documentOffset: unitRect.inflate(_pdfPageMargin).topLeft,
      zoom: zoom,
      duration: _pageTurnDuration,
    ));
  }

  /// 雙頁啟用且版面已算好時回傳版面，否則回傳 null（→ 導航方法走
  /// Issue 1 原路徑）。
  PdfSpreadLayout? get _activeSpreadLayout =>
      _dualPageEnabled ? _spreadLayout : null;

  // ── Issue 3: 裁切偵測 ──

  void _maybeDetectCropRect(PdfPage page, double devicePixelRatio) {
    if (widget.pdfCropMode != PdfCropMode.autoDetect) return;
    if (widget.pdfCropRect != null) return;
    if (_cropDetectionInFlight) return;
    if (page.pageNumber != 1) return;
    _cropDetectionInFlight = true;
    unawaited(_detectCropRect(page, devicePixelRatio));
  }

  Future<void> _detectCropRect(PdfPage page, double devicePixelRatio) async {
    final scale = pageRenderScale(devicePixelRatio);
    final rendered = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (rendered == null) {
      _cropDetectionInFlight = false;
      return;
    }
    try {
      final rect = await _isolateDetectCropRect(
        pixels: rendered.pixels,
        width: rendered.width,
        height: rendered.height,
      );
      if (mounted) {
        widget.onCropRectComputed?.call(rect);
      }
    } finally {
      rendered.dispose();
      _cropDetectionInFlight = false;
    }
  }

  // ── Issue 3: 覆蓋圖快取 ──

  ui.Image? _touchOverlayCache(int pageNumber) {
    final image = _boldOverlayImages.remove(pageNumber);
    if (image == null) return null;
    _boldOverlayImages[pageNumber] = image;
    return image;
  }

  void _putOverlayCache(int pageNumber, ui.Image image) {
    _boldOverlayImages.remove(pageNumber)?.dispose();
    if (_boldOverlayImages.length >= _maxCachedOverlayImages) {
      final oldestKey = _boldOverlayImages.keys.first;
      _boldOverlayImages.remove(oldestKey)?.dispose();
      _overlayCacheKey.remove(oldestKey);
    }
    _boldOverlayImages[pageNumber] = image;
  }

  // ── Issue 3: 合併管線（裁切先、加粗後） ──

  List<Widget> _buildProcessedOverlay(
    BuildContext context,
    Rect pageRectInViewer,
    PdfPage page,
  ) {
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    _maybeDetectCropRect(page, devicePixelRatio);
    final pageIndex = page.pageNumber - 1;
    final widgets = <Widget>[];

    if (_cropEnabled || _committedBoldStrength > 0) {
      final cacheKey = (crop: widget.pdfCropRect, bold: _committedBoldStrength);
      if (_overlayCacheKey[page.pageNumber] != cacheKey) {
        unawaited(_recomputeOverlay(page, cacheKey, devicePixelRatio)
            .catchError((e) {
          debugPrint('pdf_reader_view: overlay recompute failed: $e');
        }));
      } else {
        final image = _touchOverlayCache(page.pageNumber);
        if (image != null) widgets.add(RawImage(image: image, fit: BoxFit.fill));
      }
    }

    // 渲染既有標記（Issue 4）。
    var decorationIndex = 0;
    for (final decoration in _annotations) {
      if (decoration.pageIndex != pageIndex) continue;
      final visibleRect = _cropEnabled
          ? originalToCropRelativePercent(rect: decoration.rect, cropRect: widget.pdfCropRect)
          : decoration.rect;
      if (visibleRect == null) continue; // 完全落在裁切範圍外。
      widgets.add(_buildDecorationWidget(
        pageIndex,
        decorationIndex++,
        decoration,
        visibleRect,
        pageRectInViewer.size,
      ));
    }

    final drag = _selectionDrag;
    if (drag != null && drag.pageIndex == pageIndex) {
      widgets.add(_buildDragIndicator(drag));
    }

    // 渲染搜尋符合結果高亮（Issue 6）。
    for (var i = 0; i < _searchMatches.length; i++) {
      final match = _searchMatches[i];
      if (match.pageIndex != pageIndex) continue;
      final visibleRect = _cropEnabled
          ? originalToCropRelativePercent(rect: match.rect, cropRect: widget.pdfCropRect)
          : match.rect;
      if (visibleRect == null) continue; // 完全落在裁切範圍外。
      widgets.add(_buildSearchHighlightWidget(
        pageIndex,
        i,
        visibleRect,
        pageRectInViewer.size,
        isCurrent: i == _currentSearchMatchIndex,
      ));
    }

    // 渲染搜尋跳轉暫態高亮（epic-10-search Issue 5）。
    if (_jumpHighlightPageIndex == pageIndex && _jumpHighlightRect != null) {
      final visibleRect = _cropEnabled
          ? originalToCropRelativePercent(
              rect: _jumpHighlightRect!, cropRect: widget.pdfCropRect)
          : _jumpHighlightRect;
      if (visibleRect != null) {
        widgets.add(_buildJumpHighlightWidget(
          pageIndex,
          visibleRect,
          pageRectInViewer.size,
        ));
      }
    }

    widgets.add(_buildSelectionGestureLayer(pageIndex, pageRectInViewer));

    return widgets;
  }

  Future<void> _recomputeOverlay(
    PdfPage page,
    ({PdfCropRect? crop, double bold}) cacheKey,
    double devicePixelRatio,
  ) async {
    final scale = pageRenderScale(devicePixelRatio);
    final rendered = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (rendered == null || !mounted) return;
    try {
      final processed = await _isolateProcessOverlayPixels(
        pixels: rendered.pixels,
        width: rendered.width,
        height: rendered.height,
        cropRect: cacheKey.crop,
        boldStrength: cacheKey.bold,
      );
      final currentDesiredKey =
          (crop: widget.pdfCropRect, bold: _committedBoldStrength);
      if (!mounted || currentDesiredKey != cacheKey) return;
      final processedImage = PdfImage.createFromBgraData(
        processed.pixels,
        width: processed.width,
        height: processed.height,
      );
      final uiImage = await processedImage.createImage();
      if (!mounted || currentDesiredKey != cacheKey) {
        uiImage.dispose();
        return;
      }
      setState(() {
        _putOverlayCache(page.pageNumber, uiImage);
        _overlayCacheKey[page.pageNumber] = cacheKey;
      });
    } finally {
      rendered.dispose();
    }
  }

  // ── Issue 3: 裁切版面 ──

  PdfPageLayout _layoutCroppedPages(
      List<PdfPage> pages, PdfViewerParams params) {
    final cropRect = widget.pdfCropRect!;
    final margin = params.margin;
    var y = margin;
    final rects = <Rect>[];
    var maxWidth = 0.0;
    for (final page in pages) {
      final w = page.width * (cropRect.right - cropRect.left);
      final h = page.height * (cropRect.bottom - cropRect.top);
      rects.add(Rect.fromLTWH(margin, y, w, h));
      if (w > maxWidth) maxWidth = w;
      y += h + margin;
    }
    return PdfPageLayout(
        pageLayouts: rects, documentSize: Size(maxWidth + margin * 2, y));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const SizedBox.shrink();
    }
    final document = _document;
    if (document == null) {
      return const SizedBox.shrink();
    }
    // epic-35-design-system-tokens Issue 7：3×3 導覽熱區除錯疊層（見下方
    // showNavZoneDebugOverlay 分支）原本寫死 Colors.white24／white70，
    // 換主題／開啟 E-Ink 模式時不會跟著換；改讀 colorScheme.onSurface，
    // 呼應 nav_zone_settings_screen.dart（epic-35 Issue 5）同一組熱區格線
    // 已採用的同一個角色，維持同一功能兩處視覺語彙一致。
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    final viewer = PdfViewer(
      PdfDocumentRefDirect(document, autoDispose: false),
      controller: _controller,
      initialPageNumber: (widget.initialPageIndex ?? 0) + 1,
      params: PdfViewerParams(
        margin: _pdfPageMargin,
        sizeDelegateProvider: (widget.pdfFitMode == null && !_paginated)
            ? null
            : PdfFitSizeDelegateProvider(
                fitMode: _effectiveFitMode,
                unitRectOf: _unitRectFor,
                pageMargin: _pdfPageMargin,
                strictMinScale: _paginated,
              ),
        layoutPages: _paginated
            ? _layoutPaginatedPages
            : (_cropEnabled
                ? _layoutCroppedPages
                : (_dualPageEnabled ? _layoutSpreadPages : null)),
        calculateCurrentPageNumber: _paginated
            ? _calculatePagedPageNumber
            : (_dualPageEnabled ? _calculateSpreadAnchorPageNumber : null),
        normalizeMatrix: _paginated ? _normalizePagedMatrix : null,
        pageOverlaysBuilder: _buildProcessedOverlay,
        // Epic 24 Issue 9：pdfrx 的 PdfViewer 內部用 Listener（不參與手勢
        // 競技場）驅動平移/縮放，與 _buildSelectionGestureLayer 的長按
        // 拖曳框選 GestureDetector 會同時、無條件收到同一組原始 pointer
        // 事件，導致長按拖曳劃線時頁面內容跟著平移/縮放亂跳（真機回報，
        // 見 docs/epics/epic-24-pdf-engine-rebuild/issues.md Issue 9）。
        // 框選拖曳進行中（_selectionDrag != null）暫時關閉底層平移/縮放，
        // 放開/取消後（_selectionDrag 變回 null）恢復。
        panEnabled: _selectionDrag == null,
        scaleEnabled: _selectionDrag == null,
        onViewerReady: (doc, controller) {
          // 逐頁：delegate 嚴格模式不介入初始定位，由此把初始單元帶到起點。
          if (_pagedActive) {
            final unit = _currentPagedUnit();
            if (unit != null) _goToPagedUnit(unit);
          }
          if (!_renderedNotified) {
            _renderedNotified = true;
            widget.onPageRendered();
          }
          widget.onPageChanged?.call(PdfPageInfo(
            pageIndex: (controller.pageNumber ?? 1) - 1,
            totalPages: controller.pageCount,
          ));
        },
        onPageChanged: _handlePageChanged,
        // 逐頁：視窗尺寸改變（旋轉、摺疊）後維持同一單元、依新尺寸重算基準、偏移回到
        // 頂端（spec「導覽入口對應」）。Issue 3 spike：旋轉後 pdfrx 保留原縮放與位置、
        // 不會自動重新 Page-fit，所以必須在這裡明確重新定位。
        onViewSizeChanged: (viewSize, oldViewSize, controller) {
          // 開書初次排版 pdfrx 也會以 oldViewSize == null 呼叫；初始定位已由
          // onViewerReady 完成，這裡只處理執行期尺寸改變（I-1）。
          if (!_pagedActive || oldViewSize == null || oldViewSize == viewSize) {
            return;
          }
          final unit = _currentPagedUnit();
          if (unit == null) return;
          // 只有高度改變（例如軟鍵盤彈出／收起）：保留縮放與頁內相對位置，不跳回頂端
          // （最終審查 I-1）；寬度改變（旋轉、摺疊）才依 spec 回到單元頂端與基準縮放。
          final prev = _prevPaged;
          final now = _paged;
          if (viewSize.width == oldViewSize.width &&
              prev != null &&
              now != null &&
              prev.unitCount == now.unitCount) {
            final oldBox = prev.unitRects[unit].inflate(_pdfPageMargin);
            final newBox = now.unitRects[unit].inflate(_pdfPageMargin);
            final visible = controller.visibleRect;
            unawaited(controller.goToPosition(
              documentOffset: newBox.topLeft + (visible.topLeft - oldBox.topLeft),
              zoom: controller.currentZoom,
              duration: Duration.zero,
            ));
            return;
          }
          _goToPagedUnit(unit);
        },
        // 逐頁：pdfrx 內建的 PageUp／PageDown／Space／Home／End 會走 goToPage（100ms
        // 動畫、不認單元），被 normalizeMatrix 夾回後畫面不動卻送出錯誤頁碼（最終審查
        // I-2）。改以單元為單位接管；其他鍵（方向鍵等）沿用 pdfrx，仍受單元鎖定。
        onKey: _paginated ? _onPagedKey : null,
      ),
    );
    final colorFilter = _colorFilter;
    final colorFiltered = colorFilter == null
        ? viewer
        : ColorFiltered(colorFilter: colorFilter, child: viewer);
    return Stack(
      children: [
        Listener(
          onPointerDown: (_) {
            _activePointerCount++;
            if (_activePointerCount >= 2) _cancelSelectionDrag();
          },
          onPointerUp: (_) =>
              _activePointerCount = (_activePointerCount - 1).clamp(0, 999),
          onPointerCancel: (_) =>
              _activePointerCount = (_activePointerCount - 1).clamp(0, 999),
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewSize = constraints.biggest;
              return colorFiltered;
            },
          ),
        ),
        // epic-24-pdf-engine-rebuild Issue 8：3×3 導覽熱區，比照
        // FoliateEpubReaderView 既有的 _ZoneOverlay 版面（Column of Row of
        // Expanded），疊加在 PdfViewer 之上。用 Listener（共用
        // TapZoneDetector，見 epic-26-architecture-hardening Issue 2）
        // 而非 GestureDetector，故不會攔截 PdfViewer 自身的 pan/pinch/長按選取
        // 手勢。
        Positioned.fill(
          child: Column(
            children: List.generate(3, (row) {
              return Expanded(
                child: Row(
                  children: List.generate(3, (col) {
                    final index = row * 3 + col;
                    final action = widget.navZoneActions[index];
                    return Expanded(
                      child: TapZoneDetector(
                        key: Key('pdf_reader_nav_zone_$index'),
                        // epic-31-touch-intent-unification Issue 3：對齊
                        // EPUB 端 700ms——刻意決定、未經真機驗證（見
                        // TapZoneDetector class doc），若之後真機回報
                        // PDF 長按判斷變遲鈍，需另立工單依真機資料重新
                        // 校準，不可逕自沿用這裡的數值。
                        // tapSlop／tapDebounceMs 改用建構子預設值
                        // （kTapZoneSlop／kTapZoneDebounceMs，同一 Issue
                        // 常數收斂），不再各自宣告字面值。
                        nowMs: () => clock.now().millisecondsSinceEpoch,
                        tapMaxDurationMs: 700,
                        // Epic 26 Issue 3 暫時性真機診斷插樁：僅 PDF 端接上
                        // onDebugEvent，EPUB 端（foliate_reader_view.dart）
                        // 不接、不受影響。診斷結束後需整段移除（grep
                        // "DEBUG-e26i3" 確認清除乾淨）。
                        onDebugEvent: (message) =>
                            ReaderConsoleLog.add('$message zone=$index'),
                        onTap: () => widget.onZoneAction?.call(action),
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(
                                      color: onSurfaceColor.withValues(
                                          alpha: 0.24)))
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

  Widget _buildDragIndicator(_PdfSelectionDragState drag) {
    final rect = Rect.fromPoints(drag.start, drag.current);
    // epic-35-design-system-tokens Issue 7：框選進行中尚未決定標記顏色，
    // 改用 primary（App 既有「操作中／選取中」語彙）取代原本寫死的
    // Colors.yellow／orange，換主題／開啟 E-Ink 模式時能正確跟著換。
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Positioned.fromRect(
      key: const Key('pdf_reader_selection_drag_indicator'),
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.3),
          border: Border.all(color: primaryColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildDecorationWidget(
    int pageIndex,
    int decorationIndex,
    PdfAnnotationDecoration decoration,
    PercentRect visibleRect,
    Size areaSize,
  ) {
    final rect = Rect.fromLTRB(
      visibleRect.left * areaSize.width,
      visibleRect.top * areaSize.height,
      visibleRect.right * areaSize.width,
      visibleRect.bottom * areaSize.height,
    );
    final color = Color(decoration.tint);
    return Positioned.fromRect(
      // key 須同時包含 pageIndex 與 decorationIndex——同一頁可能有多筆
      // 標記，只用 pageIndex 當 key 在同頁多筆標記時會產生重複 key。
      key: Key('pdf_reader_decoration_${pageIndex}_$decorationIndex'),
      rect: rect,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (decoration.isUnderline)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(height: 2, color: color),
            )
          else
            Container(color: color),
          if (decoration.isNoteOnly)
            Positioned(
              right: -6,
              top: -6,
              child: Icon(Icons.push_pin,
                  size: 16, color: Theme.of(context).colorScheme.onSurface),
            ),
        ],
      ),
    );
  }

  /// 搜尋符合結果的高亮 widget，畫法比照 [_buildDecorationWidget]
  /// （同樣的 `PercentRect`→像素換算），[isCurrent] 為 true（目前使用者
  /// 正在檢視的符合結果）時額外疊加外框（審查修正，
  /// review-plan-issue-6.md Minor #3）：純粹用半透明的
  /// `ElinkTokens.highlightGreen`／`highlightYellow` 區分在 E-Ink 灰階顯示
  /// 或高對比主題下辨識度不足，外框在灰階轉換後仍能維持明顯的邊界對比，
  /// 不依賴色相差異（epic-35-design-system-tokens Issue 7：色彩角色來源
  /// 已從寫死的 Colors.orange／Colors.yellow 改為上述 ElinkTokens 角色，
  /// 這段設計原則本身不變）。
  Widget _buildSearchHighlightWidget(
    int pageIndex,
    int matchIndex,
    PercentRect visibleRect,
    Size areaSize, {
    required bool isCurrent,
  }) {
    final rect = Rect.fromLTRB(
      visibleRect.left * areaSize.width,
      visibleRect.top * areaSize.height,
      visibleRect.right * areaSize.width,
      visibleRect.bottom * areaSize.height,
    );
    // epic-35-design-system-tokens Issue 7：搜尋高亮概念上就是「標示出
    // 文字位置」，沿用既有劃線語意色 ElinkTokens.highlightYellow／
    // highlightGreen 取代原本寫死的 Colors.yellow／orange；isCurrent 外框
    // 改讀 colorScheme.primary 取代 Colors.deepOrange——維持原設計「外框
    // 存在與否（而非色相）才是可辨識度依據」的既有原則不變（見上方
    // _buildSearchHighlightWidget 註解），只換掉色彩角色的來源。
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fromRect(
      // key 須同時包含 pageIndex 與 matchIndex（matchIndex 是在
      // _searchMatches 整份清單中的全域索引，非同頁內重新歸零的計數）——
      // 理由與 _buildDecorationWidget 的既有註解相同：同一頁可能有多筆
      // 符合結果，只用 pageIndex 當 key 會產生重複 key。
      key: Key('pdf_reader_search_highlight_${pageIndex}_$matchIndex'),
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: (isCurrent ? tokens.highlightGreen : tokens.highlightYellow)
              .withValues(alpha: 0.4),
          border: isCurrent
              ? Border.all(color: colorScheme.primary, width: 1.5)
              : null,
        ),
      ),
    );
  }

  /// 搜尋跳轉暫態高亮的視覺樣式（epic-10-search Issue 5）：比照
  /// [_buildSearchHighlightWidget] 的 `isCurrent` 樣式（半透明色塊＋外框）
  /// ——兩者概念相同，都是「標示出目前應注意的文字位置」，差別只在生命
  /// 週期（本高亮 3 秒後自動消失，PDF 內文搜尋符合結果由使用者手動關閉
  /// 搜尋面板才消失）；刻意不共用程式碼，因為兩者的資料來源
  /// （[_jumpHighlightRect] vs [_searchMatches]）完全獨立，由不同呼叫端
  /// （[ReaderScreen] vs `PdfSearchPanel`）驅動。
  Widget _buildJumpHighlightWidget(
    int pageIndex,
    PercentRect visibleRect,
    Size areaSize,
  ) {
    final rect = Rect.fromLTRB(
      visibleRect.left * areaSize.width,
      visibleRect.top * areaSize.height,
      visibleRect.right * areaSize.width,
      visibleRect.bottom * areaSize.height,
    );
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fromRect(
      key: Key('pdf_reader_jump_highlight_$pageIndex'),
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.highlightGreen.withValues(alpha: 0.4),
          border: Border.all(color: colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildSelectionGestureLayer(int pageIndex, Rect pageRectInViewer) {
    return Positioned.fill(
      child: BounceTolerantLongPressDetector(
        onLongPressStart: (position) {
          if (widget.cropEditModeActive) return;
          _selectionDragGenerationId++;
          setState(() {
            _selectionDrag = _PdfSelectionDragState(
              pageIndex: pageIndex,
              areaSize: pageRectInViewer.size,
              pageOffsetInViewer: pageRectInViewer.topLeft,
              start: position,
            );
          });
        },
        onLongPressMoveUpdate: (position) {
          final drag = _selectionDrag;
          if (drag == null || drag.pageIndex != pageIndex) return;
          setState(() => drag.current = position);
        },
        onLongPressEnd: () => _finishSelectionDrag(),
        onLongPressCancel: () => _cancelSelectionDrag(),
        child: const SizedBox.shrink(),
      ),
    );
  }

  /// 框選矩形內文字萃取（epic-27-reader-device-compat Issue 11）：把框選
  /// 的 [rect]（PercentRect，同一套換算慣例見 percent_rect.dart）換算回
  /// PDF points 座標，找出落在這個矩形內的字元，組成文字供「複製」按鈕
  /// 使用。座標系換算必須用 percentRectToPdfRect（見審查報告 Important
  /// #1）——PercentRect 是左上角原點、Y 軸向下，PdfRect 是左下角原點、
  /// Y 軸向上，方向相反，不能直接相乘頁面尺寸後原樣塞進 PdfRect。
  Future<String> _extractTextInRect(int pageIndex, PercentRect rect) async {
    final document = _document;
    if (document == null) return '';
    if (pageIndex < 0 || pageIndex >= document.pages.length) return '';
    final page = document.pages[pageIndex];
    final pageText = await page.loadStructuredText();
    final targetRect = percentRectToPdfRect(
      rect: rect,
      pageWidth: page.width,
      pageHeight: page.height,
    );
    final buffer = StringBuffer();
    for (var i = 0; i < pageText.charRects.length; i++) {
      if (pageText.charRects[i].overlaps(targetRect)) {
        buffer.write(pageText.fullText[i]);
      }
    }
    return buffer.toString();
  }

  Future<void> _finishSelectionDrag() async {
    final drag = _selectionDrag;
    if (drag == null) return;
    setState(() => _selectionDrag = null);
    // epic-25-annotation-interaction-qa Issue 6：退化選取（長按沒有明顯
    // 拖曳位移）不再整個吞掉——改用長按落點本身（drag.start，固定不隨拖曳
    // 終點飄移）換算出一個零面積的點矩形送出，讓 ReaderScreen 有機會判斷
    // 這次操作是否命中既有劃線/備註（resolvePdfExistingAnnotation()）。
    // 是否顯示工具列的決定權完全交給 ReaderScreen，這裡不判斷、也不需要
    // 認識 Highlight/Note（見 plan-issue-6.md Global Constraints）。
    final pageRelativeRect = percentRectFromDrag(
          start: drag.start,
          end: drag.current,
          areaSize: drag.areaSize,
        ) ??
        pointPercentRect(point: drag.start, areaSize: drag.areaSize);
    final originalRect = cropRelativeToOriginalPercent(
      rect: pageRelativeRect,
      cropRect: _cropEnabled ? widget.pdfCropRect : null,
    );
    final viewerSize = context.size;
    final widgetRect = viewerSize == null || viewerSize.isEmpty
        ? pageRelativeRect
        : percentRectFromDrag(
            start: drag.pageOffsetInViewer +
                Offset(drag.start.dx, drag.start.dy),
            end: drag.pageOffsetInViewer + Offset(drag.current.dx, drag.current.dy),
            areaSize: viewerSize,
            minFraction: 0,
          )!;
    // epic-27-reader-device-compat Issue 11（審查報告 Important #2）：
    // page.loadStructuredText() 是真實 FFI 呼叫，可能耗時；這段 await
    // 期間使用者可能離開畫面或開始下一次框選，過期結果不能覆蓋新狀態。
    final generationId = _selectionDragGenerationId;
    final text = await _extractTextInRect(drag.pageIndex, originalRect);
    if (!mounted || generationId != _selectionDragGenerationId) return;
    widget.onSelectionRectComputed?.call(PdfSelectionInfo(
      pageIndex: drag.pageIndex,
      rect: originalRect,
      widgetRect: widgetRect,
      text: text,
    ));
  }

  void _cancelSelectionDrag() {
    if (_selectionDrag == null) return;
    setState(() => _selectionDrag = null);
    widget.onSelectionCanceled?.call();
  }
}

// ── Issue 3: Isolate.run() 專用的頂層輔助函式 ──
//
// 【真機/測試環境實測重現並排除法確認的根因，非臆測】刻意獨立於
// `_PdfReaderViewState` 的任何方法之外、頂層宣告、參數只接受單純可跨
// isolate 傳遞的型別（Uint8List／int／double／PdfCropRect 值物件）——
// 早期實作把 Isolate.run() 的 closure 直接寫在 `_recomputeOverlay`／
// `_detectCropRect` 方法內部，即使 closure 本身只讀取幾個已經取出的區域
// 變數（`sourcePixels`/`sourceWidth`/`sourceHeight`/`cropRect`），實測仍
// 會在執行期擲出：
//   Illegal argument in isolate message: object is unsendable
//   - Library:'package:rxdart/.../behavior_subject.dart' Class: BehaviorSubject
//   <- permissions in _PdfDocumentPdfium <- bbLeft in _PdfPagePdfium
//   <- Context num_variables: 8 <- Closure: () => (...)
// 這條鏈證實 closure 的 Context 物件把整個 `_recomputeOverlay`/
// `_detectCropRect` 方法作用域內的 8 個變數（含 `page: PdfPage` 這個
// 參數）一併打包，即使 closure 本身從未讀取 `page`——`page` 內部持有
// pdfrx 的 `_PdfDocumentPdfium`（其 `permissions` 欄位是 rxdart
// `BehaviorSubject`，不可跨 isolate 傳遞），只要 `page` 曾經是「與該
// closure 同一個詞法作用域內存在的變數」，就可能被同一個 Context 物件
// 牽連打包，與 closure 本身有沒有真的用到它無關。改成獨立的頂層函式後，
// 呼叫端只傳入已經取出的原始資料，這裡的詞法作用域內從頭到尾都不存在
// `PdfPage`/`PdfDocument`/`_PdfReaderViewState`，Context 物件不可能牽連
// 到任何不可傳遞的物件。

Future<PdfCropRect> _isolateDetectCropRect({
  required Uint8List pixels,
  required int width,
  required int height,
}) {
  return Isolate.run(
    () => detectCropRectFromBgraPixels(pixels, width: width, height: height),
  );
}

Future<({Uint8List pixels, int width, int height})> _isolateProcessOverlayPixels({
  required Uint8List pixels,
  required int width,
  required int height,
  required PdfCropRect? cropRect,
  required double boldStrength,
}) {
  return Isolate.run(() {
    var outPixels = pixels;
    var outWidth = width;
    var outHeight = height;
    if (cropRect != null) {
      final targetWidth =
          ((cropRect.right - cropRect.left) * outWidth).round().clamp(1, outWidth);
      final targetHeight =
          ((cropRect.bottom - cropRect.top) * outHeight).round().clamp(1, outHeight);
      outPixels = cropBgraPixels(
        outPixels,
        width: outWidth,
        height: outHeight,
        rect: cropRect,
        outWidth: targetWidth,
        outHeight: targetHeight,
      );
      outWidth = targetWidth;
      outHeight = targetHeight;
    }
    if (boldStrength > 0) {
      final radius = (boldStrength * 3).round().clamp(1, 3);
      outPixels =
          dilateBgraPixels(outPixels, width: outWidth, height: outHeight, radius: radius);
    }
    return (pixels: outPixels, width: outWidth, height: outHeight);
  });
}

/// [_PdfReaderViewState] 內部使用的框選追蹤狀態，不對外暴露。
class _PdfSelectionDragState {
  _PdfSelectionDragState({
    required this.pageIndex,
    required this.areaSize,
    required this.pageOffsetInViewer,
    required this.start,
  }) : current = start;

  final int pageIndex;
  final Size areaSize;
  final Offset pageOffsetInViewer;
  final Offset start;
  Offset current;
}
