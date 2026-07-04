import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/epub_reader_view.dart';
import '../reader/pdf_reader_view.dart';

/// 唯一的閱讀器顯示接縫（seam）：給定書籍檔案路徑，依偵測到的格式分派到
/// 對應的原生渲染視圖（EpubReaderView／PdfReaderView），畫面上會渲染出該
/// 書第 1 頁。公開建構參數僅有 [filePath]（見 spec.md 的 seam 定義）——載入
/// 中／錯誤狀態皆為內部實作細節，透過固定的 Key（`reader_loading_indicator`
/// ／`reader_error_text`）暴露給 integration_test 觀察，而非另外新增公開
/// callback 參數，避免違反 spec.md 定義的唯一對外契約。
///
/// AppBar 沿用與 LibraryScreen/SettingsScreen 一致的寫法（純 `AppBar(title:
/// ...)`，不自訂 leading）：Flutter 會依 `Navigator.canPop()` 自動決定是否
/// 顯示返回鍵，且點擊時使用安全的 `Navigator.maybePop()`，不需要手動處理。
class ReaderScreen extends StatefulWidget {
  final String filePath;

  const ReaderScreen({super.key, required this.filePath});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

enum _RenderState { loading, rendered, error }

class _ReaderScreenState extends State<ReaderScreen> {
  _RenderState _state = _RenderState.loading;
  String? _errorMessage;

  void _handlePageRendered() {
    setState(() => _state = _RenderState.rendered);
  }

  void _handleError(String message) {
    setState(() {
      _state = _RenderState.error;
      _errorMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final format = detectBookFormat(widget.filePath);
    return Scaffold(
      appBar: AppBar(
        title: const Text('閱讀器'),
      ),
      body: _buildBody(format),
    );
  }

  Widget _buildBody(BookFormat format) {
    if (format == BookFormat.unknown) {
      return const Center(child: Text('不支援的檔案格式'));
    }
    if (_state == _RenderState.error) {
      // 渲染失敗時直接以錯誤文字取代原生視圖（而非疊加在 Stack 上層），讓
      // 已失敗的 EpubReaderView/PdfReaderView 提早從 widget tree 移除、
      // 觸發其 dispose() 清理原生資源，不讓一個已知失敗的 PlatformView
      // 繼續留在畫面底層。
      return Center(
        child: Text(
          _errorMessage ?? '無法載入書籍',
          key: const Key('reader_error_text'),
        ),
      );
    }
    return Stack(
      children: [
        _buildNativeView(format),
        if (_state == _RenderState.loading)
          const Center(
            key: Key('reader_loading_indicator'),
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildNativeView(BookFormat format) {
    switch (format) {
      case BookFormat.epub:
        return EpubReaderView(
          filePath: widget.filePath,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
        );
      case BookFormat.pdf:
        return PdfReaderView(
          filePath: widget.filePath,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
        );
      case BookFormat.unknown:
        return const SizedBox.shrink();
    }
  }
}
