import 'package:flutter/material.dart';

import '../reader/book_format.dart';

/// 唯一的閱讀器顯示接縫（seam）：給定書籍檔案路徑，依偵測到的格式顯示對應
/// 內容。本階段（Issue 2）僅分派到佔位視圖；Issue 5 會把佔位視圖換成真正的
/// 原生渲染視圖（EpubReaderView／PdfReaderView），但這個 widget 對外的建構
/// 參數（filePath）不會改變。
///
/// AppBar 沿用與 LibraryScreen/SettingsScreen 一致的寫法（純 `AppBar(title:
/// ...)`，不自訂 leading）：Flutter 會依 `Navigator.canPop()` 自動決定是否
/// 顯示返回鍵，且點擊時使用安全的 `Navigator.maybePop()`，不需要手動處理。
class ReaderScreen extends StatelessWidget {
  final String filePath;

  const ReaderScreen({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    final format = detectBookFormat(filePath);
    return Scaffold(
      appBar: AppBar(
        title: const Text('閱讀器'),
      ),
      body: Center(
        child: Text(_placeholderLabel(format)),
      ),
    );
  }

  String _placeholderLabel(BookFormat format) {
    switch (format) {
      case BookFormat.epub:
        return 'EPUB 佔位畫面（尚未接上 Readium 原生渲染）';
      case BookFormat.pdf:
        return 'PDF 佔位畫面（尚未接上 PdfRenderer 原生渲染）';
      case BookFormat.unknown:
        return '不支援的檔案格式';
    }
  }
}
