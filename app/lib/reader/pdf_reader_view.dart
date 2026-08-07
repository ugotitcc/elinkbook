import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
import 'pdf_spread_layout.dart';
import 'pdf_annotation_decoration.dart';
import 'pdf_page_info.dart';

/// 以 pdfrx（PDFium + Dart FFI）為底層的 PDF 閱讀 widget
/// （epic-24-pdf-engine-rebuild Issue 1），取代現行以
/// android.graphics.pdf.PdfRenderer 為底層、透過 AndroidView PlatformView
/// 渲染的既有實作（ADR 0022）。本工單範圍限定「單頁顯示＋頁碼＋跳頁」，
/// 雙頁/影像濾鏡/劃線/目錄/搜尋/縮圖/FAB 工具列皆為後續獨立工單，
/// 尚未實作。
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

  /// 【epic-24 Issue 1 暫時性 no-op】劃線/備註疊圖刷新——新引擎尚未實作
  /// 標註渲染（Issue 4 範圍），本工單只保留方法簽章讓既有呼叫端
  /// （reader_screen.dart 的 _refreshPdfAnnotations）不必修改呼叫點即可
  /// 編譯通過，呼叫本方法目前無任何效果。
  static void refreshAnnotations(
    GlobalKey<State<PdfReaderView>> key,
    List<PdfAnnotationDecoration> annotations,
  ) {
    // 見上方 docstring：Issue 4 落地前刻意無行為。
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

  bool get _dualPageEnabled => isDualPageEnabled(
        mode: widget.dualPageMode,
        isLandscape: widget.isLandscape,
      );

  @override
  void initState() {
    super.initState();
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
    final changed = oldWidget.dualPageMode != widget.dualPageMode ||
        oldWidget.dualPageCoverAlone != widget.dualPageCoverAlone ||
        oldWidget.dualPageDirection != widget.dualPageDirection ||
        oldWidget.isLandscape != widget.isLandscape;
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

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      // 已透過 widget.onError 通知呼叫端；呼叫端（ReaderScreen）會切換到
      // 自己的錯誤畫面並把本 widget 從樹上移除，這裡回傳空白佔位即可。
      return const SizedBox.shrink();
    }
    final document = _document;
    if (document == null) {
      return const SizedBox.shrink();
    }
    return PdfViewer(
      PdfDocumentRefDirect(document, autoDispose: false),
      controller: _controller,
      initialPageNumber: (widget.initialPageIndex ?? 0) + 1,
      params: PdfViewerParams(
        // 單頁模式一律傳 null，沿用 pdfrx 內建版面推算——PdfViewerParams
        // 與 Issue 1 逐欄位相同，這是零回歸的構造性保證（不是靠測試
        // 事後證明）。
        layoutPages: _dualPageEnabled ? _layoutSpreadPages : null,
        calculateCurrentPageNumber:
            _dualPageEnabled ? _calculateSpreadAnchorPageNumber : null,
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
  }
}
