import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/library_enums.dart';

/// 依書籍格式取得對應佔位圖示。
IconData bookFormatIcon(BookFileFormat format) {
  switch (format) {
    case BookFileFormat.epub:
      return Icons.menu_book;
    case BookFileFormat.pdf:
      return Icons.picture_as_pdf;
    case BookFileFormat.txt:
      return Icons.article;
  }
}

/// 書籍封面：有 `coverPath` 且檔案存在時顯示圖片，否則以格式圖示佔位。
/// `existsSync()` 只是一次本機 stat 呼叫，成本低，不需要 FutureBuilder。
class BookCover extends StatelessWidget {
  final Book book;

  const BookCover({
    super.key,
    required this.book,
  });

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return Image.file(File(coverPath), fit: BoxFit.cover);
    }
    return ColoredBox(
      color: Colors.grey.shade300,
      child: Center(child: Icon(bookFormatIcon(book.format), size: 32)),
    );
  }
}
