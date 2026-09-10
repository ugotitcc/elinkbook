// app/lib/search/pdf_content_indexer.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../library/models/book.dart';
import '../reader/pdf_search_geometry.dart';
import 'content_indexer.dart';

/// PDF 格式的內容擷取器（epic-10-search Issue 1，見 spec.md §3.2）。直接
/// `PdfDocument.openFile()`＋逐頁 `page.loadStructuredText()`（與
/// `pdf_reader_view.dart` 既有 `_search()` 邏輯同源），不需要 Widget、不需要
/// 額外 Isolate（`pdfrx` 底層已透過 `BackgroundWorker` 背景執行，比照既有
/// 「縮圖不需額外 Isolate」結論）。
///
/// 切片粒度為 [PdfPageTextFragment]（`pdfrx_engine` 既有型別，通常對應
/// PDF 內部一個連續文字排版區塊，例如一行），而非整頁一筆——比整頁粗略
/// 位置更精確，符合 design.md「精確位置級跳轉」目標。
///
/// 【review-plan-issue-1.md C-1 修正】`book.filePath` 依 ADR 0002 可能是
/// `content://` URI（SAF 匯入/資料夾匯入書籍）——PDFium FFI 的
/// `PdfDocument.openFile()` 底層是 C 標準檔案系統呼叫，完全無法解析
/// `content://`，必須先比照既有 `PdfReaderView._openContentUriDocument()`
/// （`pdf_reader_view.dart:470-483`）串流複製成本機暫存檔再開啟，並在處理
/// 完畢後刪除暫存檔。[readContentUriAll] 頂層函式變數（非固定函式宣告）
/// 比照 `foliate_native_bridge.dart` 的 `cacheBookForServing` 既有慣例，
/// 讓測試環境可以覆寫此變數完全繞過原生 MethodChannel 呼叫。
class PdfContentIndexer implements ContentIndexer {
  const PdfContentIndexer();

  @override
  Stream<IndexedSegment> indexBook(
    Book book, {
    int? resumeFromChapter,
  }) async* {
    final isContentUri = book.filePath.contains('://');
    final openPath = isContentUri
        ? await readContentUriAll(book.filePath)
        : book.filePath;
    if (openPath == null) {
      throw StateError('無法讀取 PDF 檔案：${book.filePath}');
    }

    final document = await PdfDocument.openFile(openPath);
    try {
      final startPage = resumeFromChapter ?? 0;
      for (var pageIndex = startPage;
          pageIndex < document.pages.length;
          pageIndex++) {
        final page = document.pages[pageIndex];
        final pageText = await page.loadStructuredText();
        for (final fragment in pageText.fragments) {
          final text = fragment.text.trim();
          if (text.isEmpty) continue;
          final rect = pdfRectToPercentRect(
            rect: fragment.bounds,
            pageWidth: page.width,
            pageHeight: page.height,
          );
          yield IndexedSegment(
            chapterIndex: pageIndex,
            locator: jsonEncode({
              'page': pageIndex,
              'rect': {
                'left': rect.left,
                'top': rect.top,
                'right': rect.right,
                'bottom': rect.bottom,
              },
            }),
            rawText: text,
          );
        }
      }
    } finally {
      await document.dispose();
      if (isContentUri) {
        final tmpFile = File(openPath);
        if (tmpFile.existsSync()) {
          try {
            tmpFile.deleteSync();
          } catch (_) {
            // 比照 pdf_reader_view.dart 既有 _cleanupTmpFile() 慣例：刪除
            // 失敗（例如檔案已被其他流程清空目錄）不應讓索引流程整體失敗。
          }
        }
      }
    }
  }
}

const _resourceChannel = MethodChannel('elinkbook/reader_resources');

/// 串流複製 `content://` URI 為本機暫存檔，回傳暫存檔路徑（失敗回傳
/// null）。與 `PdfReaderView._openContentUriDocument()` 呼叫同一條既有原生
/// 通道／方法（`elinkbook/reader_resources` 的 `readContentUriAll`），不
/// 新增原生端程式碼。頂層函式變數寫法（非固定函式宣告）比照
/// `foliate_native_bridge.dart` 的 `cacheBookForServing`，供測試覆寫。
Future<String?> Function(String uri) readContentUriAll =
    _defaultReadContentUriAll;

Future<String?> _defaultReadContentUriAll(String uri) {
  return _resourceChannel.invokeMethod<String>('readContentUriAll', {'uri': uri});
}
