import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

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
class PdfxReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final int? initialPageIndex;
  final ValueChanged<PdfPageInfo>? onPageChanged;

  const PdfxReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.initialPageIndex,
    this.onPageChanged,
  });

  @override
  State<PdfxReaderView> createState() => _PdfxReaderViewState();

  /// 跳轉至指定頁碼（0-indexed）。[key] 對應的 State 若尚未掛載或尚未
  /// 就緒，靜默忽略，比照現行 PdfReaderView 既有的 fire-and-forget 慣例。
  static void jumpToPage(GlobalKey<State<PdfxReaderView>> key, int pageIndex) {
    final state = key.currentState;
    if (state is _PdfxReaderViewState) {
      state._jumpToPage(pageIndex);
    }
  }

  /// 導航至下一頁。
  static void nextPage(GlobalKey<State<PdfxReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfxReaderViewState) {
      state._nextPage();
    }
  }

  /// 導航至上一頁。
  static void previousPage(GlobalKey<State<PdfxReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfxReaderViewState) {
      state._previousPage();
    }
  }

  /// 【epic-24 Issue 1 暫時性 no-op】劃線/備註疊圖刷新——新引擎尚未實作
  /// 標註渲染（Issue 4 範圍），本工單只保留方法簽章讓既有呼叫端
  /// （reader_screen.dart 的 _refreshPdfAnnotations）不必修改呼叫點即可
  /// 編譯通過，呼叫本方法目前無任何效果。
  static void refreshAnnotations(
    GlobalKey<State<PdfxReaderView>> key,
    List<PdfAnnotationDecoration> annotations,
  ) {
    // 見上方 docstring：Issue 4 落地前刻意無行為。
  }
}

class _PdfxReaderViewState extends State<PdfxReaderView> {
  final _controller = PdfViewerController();
  PdfDocument? _document;
  Object? _error;
  bool _renderedNotified = false;

  @override
  void initState() {
    super.initState();
    _openDocument();
  }

  Future<void> _openDocument() async {
    try {
      final document = await PdfDocument.openFile(widget.filePath);
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

  @override
  void dispose() {
    _document?.dispose();
    super.dispose();
  }

  void _jumpToPage(int pageIndex) {
    if (!_controller.isReady) return;
    if (pageIndex < 0 || pageIndex >= _controller.pageCount) return;
    _controller.goToPage(pageNumber: pageIndex + 1);
  }

  void _nextPage() {
    if (!_controller.isReady) return;
    final current = _controller.pageNumber ?? 1;
    if (current >= _controller.pageCount) return;
    _controller.goToPage(pageNumber: current + 1);
  }

  void _previousPage() {
    if (!_controller.isReady) return;
    final current = _controller.pageNumber ?? 1;
    if (current <= 1) return;
    _controller.goToPage(pageNumber: current - 1);
  }

  void _handlePageChanged(int? pageNumber) {
    if (pageNumber == null || !_controller.isReady) return;
    widget.onPageChanged?.call(PdfPageInfo(
      pageIndex: pageNumber - 1,
      totalPages: _controller.pageCount,
    ));
  }

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
