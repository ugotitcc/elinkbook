import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import 'reader_screen.dart';
import 'sample_books.dart';
import 'settings_screen.dart';

/// 書架佔位畫面：真正的圖書庫管理邏輯屬於 epic-1-library；本畫面目前顯示
/// 固定的範例書籍清單（一本 EPUB、一本 PDF，見 sample_books.dart），點擊項目
/// 會把對應範例檔案複製為裝置真實檔案後導航至 ReaderScreen，讓「從書架點開
/// 一本書、看到內容渲染出來」成為從 App 正常入口即可觸及的真實使用者流程。
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('書架'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          for (final book in sampleBooks)
            ListTile(
              key: Key('sample_book_${book.fileName}'),
              leading: Icon(
                book.format == BookFormat.epub
                    ? Icons.menu_book
                    : Icons.picture_as_pdf,
              ),
              title: Text(book.title),
              onTap: () => _openSampleBook(context, book),
            ),
        ],
      ),
    );
  }

  Future<void> _openSampleBook(BuildContext context, SampleBook book) async {
    final filePath = await stageSampleBookFile(book);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ReaderScreen(filePath: filePath)),
    );
  }
}
