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
import 'pdf_image_filters.dart';
import 'pdf_filter_debounce.dart';
import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
import 'pdf_toc_item.dart';
import 'pdf_selection_geometry.dart';
import 'pdf_selection_info.dart';
import 'pdf_search_match.dart';
import 'pdf_search_geometry.dart';
import 'percent_rect.dart';
import 'tap_zone_detector.dart';
import 'zone_action.dart';

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
  static const _resourceChannel = MethodChannel('elinkbook/reader_resources');
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

  bool get _dualPageEnabled =>
      widget.pdfCropMode == PdfCropMode.none &&
      isDualPageEnabled(
        mode: widget.dualPageMode,
        isLandscape: widget.isLandscape,
      );

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
      setState(() => _error = e);
      widget.onError(e.toString());
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
        oldWidget.pdfCropRect != widget.pdfCropRect;
    if (!changed) return;

    // 切換前的錨點頁必須先記下來：relayout 後 pdfrx 會依自己的邏輯推一
    // 個目前頁，未必落在原本的 spread 上。
    final anchorBefore = _controller.isReady
        ? (_controller.pageNumber ?? 1) - 1
        : (widget.initialPageIndex ?? 0);

    if (!_dualPageEnabled) {
      _spreadLayout = null; // 停用雙頁後不得再用舊的 spread 矩形導航。
    }
    _cachedLayoutKey = null;
    _cachedPdfLayout = null;
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
    final layout = _activeSpreadLayout;
    if (layout == null) {
      _controller.goToPage(pageNumber: pageIndex + 1); // Issue 1 原邏輯。
      return;
    }
    _goToSpread(layout.spreadIndexOf(pageIndex), layout);
  }

  void _nextPage() {
    if (widget.cropEditModeActive) return;
    if (!_controller.isReady) return;
    final layout = _activeSpreadLayout;
    if (layout == null) {
      final current = _controller.pageNumber ?? 1; // Issue 1 原邏輯。
      if (current >= _controller.pageCount) return;
      _controller.goToPage(pageNumber: current + 1);
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
    final layout = _activeSpreadLayout;
    if (layout == null) {
      final current = _controller.pageNumber ?? 1; // Issue 1 原邏輯。
      if (current <= 1) return;
      _controller.goToPage(pageNumber: current - 1);
      return;
    }
    final currentIndex = (_controller.pageNumber ?? 1) - 1;
    final prev = layout.previousSpreadAnchor(currentIndex);
    if (prev == null) return; // 已在封面 spread。
    _goToSpread(layout.spreadIndexOf(prev), layout);
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
    unawaited(_controller.goToArea(
      rect: layout.spreadRects[spreadIndex],
      anchor: PdfPageAnchor.all,
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
    final viewer = PdfViewer(
      PdfDocumentRefDirect(document, autoDispose: false),
      controller: _controller,
      initialPageNumber: (widget.initialPageIndex ?? 0) + 1,
      params: PdfViewerParams(
        layoutPages: _cropEnabled
            ? _layoutCroppedPages
            : (_dualPageEnabled ? _layoutSpreadPages : null),
        calculateCurrentPageNumber:
            _dualPageEnabled ? _calculateSpreadAnchorPageNumber : null,
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
          child: colorFiltered,
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
                        // 原始未校準值——是否需要比照 epic-25 Issue 1
                        // 真機診斷調整，追蹤於 Epic 26 Issue 3，本次收斂
                        // 刻意不變更數值本身。
                        nowMs: () => clock.now().millisecondsSinceEpoch,
                        tapMaxDurationMs: 400,
                        tapSlop: 18.0,
                        onTap: () => widget.onZoneAction?.call(action),
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.white24))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _pdfZoneActionLabel(action),
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

  String _pdfZoneActionLabel(ZoneAction action) {
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

  Widget _buildDragIndicator(_PdfSelectionDragState drag) {
    final rect = Rect.fromPoints(drag.start, drag.current);
    return Positioned.fromRect(
      key: const Key('pdf_reader_selection_drag_indicator'),
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.yellow.withValues(alpha: 0.3),
          border: Border.all(color: Colors.orange, width: 1.5),
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
            const Positioned(
              right: -6,
              top: -6,
              child: Icon(Icons.push_pin, size: 16, color: Colors.black87),
            ),
        ],
      ),
    );
  }

  /// 搜尋符合結果的高亮 widget，畫法比照 [_buildDecorationWidget]
  /// （同樣的 `PercentRect`→像素換算），[isCurrent] 為 true（目前使用者
  /// 正在檢視的符合結果）時額外疊加外框（審查修正，
  /// review-plan-issue-6.md Minor #3）：純粹用半透明橙色／黃色區分在
  /// E-Ink 灰階顯示或高對比主題下辨識度不足，外框在灰階轉換後仍能維持
  /// 明顯的邊界對比，不依賴色相差異。
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
    return Positioned.fromRect(
      // key 須同時包含 pageIndex 與 matchIndex（matchIndex 是在
      // _searchMatches 整份清單中的全域索引，非同頁內重新歸零的計數）——
      // 理由與 _buildDecorationWidget 的既有註解相同：同一頁可能有多筆
      // 符合結果，只用 pageIndex 當 key 會產生重複 key。
      key: Key('pdf_reader_search_highlight_${pageIndex}_$matchIndex'),
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: (isCurrent ? Colors.orange : Colors.yellow).withValues(alpha: 0.4),
          border: isCurrent
              ? Border.all(color: Colors.deepOrange, width: 1.5)
              : null,
        ),
      ),
    );
  }

  Widget _buildSelectionGestureLayer(int pageIndex, Rect pageRectInViewer) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (details) {
          if (widget.cropEditModeActive) return;
          setState(() {
            _selectionDrag = _PdfSelectionDragState(
              pageIndex: pageIndex,
              areaSize: pageRectInViewer.size,
              pageOffsetInViewer: pageRectInViewer.topLeft,
              start: details.localPosition,
            );
          });
        },
        onLongPressMoveUpdate: (details) {
          final drag = _selectionDrag;
          if (drag == null || drag.pageIndex != pageIndex) return;
          setState(() => drag.current = details.localPosition);
        },
        onLongPressEnd: (details) => _finishSelectionDrag(),
        onLongPressCancel: () => _cancelSelectionDrag(),
      ),
    );
  }

  void _finishSelectionDrag() {
    final drag = _selectionDrag;
    if (drag == null) return;
    setState(() => _selectionDrag = null);
    final pageRelativeRect = percentRectFromDrag(
      start: drag.start,
      end: drag.current,
      areaSize: drag.areaSize,
    );
    if (pageRelativeRect == null) return; // 退化選取，等同取消。
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
    widget.onSelectionRectComputed?.call(PdfSelectionInfo(
      pageIndex: drag.pageIndex,
      rect: originalRect,
      widgetRect: widgetRect,
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
