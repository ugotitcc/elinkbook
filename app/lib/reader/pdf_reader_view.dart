import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
class PdfReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final int? initialPageIndex;
  final ValueChanged<PdfPageInfo>? onPageChanged;

  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.initialPageIndex,
    this.onPageChanged,
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
