// app/test/search/pdf_content_indexer_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/search/pdf_content_indexer.dart';

/// 測試用最小 [Book]，只有 [PdfContentIndexer] 實際用到的 [filePath] 有意義，
/// 其餘欄位填入合法但無意義的預設值（比照專案既有測試慣例）。
Book _pdfBook({required String filePath}) {
  return Book(
    id: 'pdf-book-1',
    title: '測試 PDF',
    format: BookFileFormat.pdf,
    filePath: filePath,
    source: BookSource.local,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: DateTime(2026, 1, 1),
  );
}

void main() {
  setUp(() => pdfrxInitialize());

  group('PdfContentIndexer.indexBook', () {
    test(
        '對 5 頁 PDF（test/fixtures/sample_multi_page.pdf，見 pdf_reader_view_search_test.dart 既有驗證：每頁皆含 "Page" 字樣）逐頁擷取為 IndexedSegment',
        () async {
      const indexer = PdfContentIndexer();
      final book = _pdfBook(filePath: 'test/fixtures/sample_multi_page.pdf');

      final segments = await indexer.indexBook(book).toList();

      expect(segments, isNotEmpty);
      expect(segments.map((s) => s.chapterIndex).toSet(), {0, 1, 2, 3, 4},
          reason: 'chapterIndex 即頁碼（0-indexed），5 頁應涵蓋 0-4 全部頁碼');

      // 每頁至少一個 fragment 的文字包含 "Page"（大小寫不敏感，比照
      // pdf_reader_view_search_test.dart 對同一份 fixture 已驗證過的內容）。
      final textByPage = <int, StringBuffer>{};
      for (final segment in segments) {
        textByPage
            .putIfAbsent(segment.chapterIndex, () => StringBuffer())
            .write(segment.rawText);
      }
      for (var page = 0; page < 5; page++) {
        expect(textByPage[page].toString().toLowerCase(), contains('page'),
            reason: '第 $page 頁組合文字應包含 "Page" 字樣');
      }

      final first = segments.first;
      expect(first.rawText.trim(), isNotEmpty);
      final locator = jsonDecode(first.locator) as Map<String, dynamic>;
      expect(locator['page'], 0);
      final rect = locator['rect'] as Map<String, dynamic>;
      final left = (rect['left'] as num).toDouble();
      final top = (rect['top'] as num).toDouble();
      final right = (rect['right'] as num).toDouble();
      final bottom = (rect['bottom'] as num).toDouble();
      expect(left, inInclusiveRange(0.0, 1.0));
      expect(right, inInclusiveRange(0.0, 1.0));
      expect(top, lessThan(bottom), reason: '比照 PercentRect 慣例，top<=bottom（左上角原點）');
    });

    test('resumeFromChapter 只從指定頁碼（含）開始擷取', () async {
      const indexer = PdfContentIndexer();
      final book = _pdfBook(filePath: 'test/fixtures/sample_multi_page.pdf');

      final segments =
          await indexer.indexBook(book, resumeFromChapter: 3).toList();

      expect(segments, isNotEmpty);
      expect(segments.map((s) => s.chapterIndex).toSet(), {3, 4});
    });

    test('空白/純空格文字片段不產生 IndexedSegment', () async {
      const indexer = PdfContentIndexer();
      final book = _pdfBook(filePath: 'test/fixtures/sample_multi_page.pdf');

      final segments = await indexer.indexBook(book).toList();

      for (final segment in segments) {
        expect(segment.rawText.trim(), isNotEmpty);
      }
    });

    // 【review-plan-issue-1.md C-1】content:// URI 書籍必須先串流複製為
    // 本機暫存檔才能被 PdfDocument.openFile() 開啟，覆寫 readContentUriAll
    // 頂層函式變數繞過真正的原生 MethodChannel 呼叫（測試環境無法呼叫
    // 原生端），驗證：(1) filePath 含 "://" 時確實呼叫這個 resolver 而非
    // 直接把 content:// 字串傳給 PdfDocument.openFile()；(2) 解析出的暫存
    // 檔路徑正確被拿去開啟；(3) 處理完畢後暫存檔被刪除。
    //
    // 【review-issue-0.md Minor #1 修正】mock 必須回傳「真正的暫存檔複本」，
    // 不可直接回傳共用 fixture 本身的路徑——production 端的 finally 區塊
    // 會把 content:// 解析出來的路徑當作自己擁有的暫存檔無條件刪除
    // （pdf_content_indexer.dart 的 indexBook()），若 mock 回傳 fixture
    // 本體，會把版本控制中的共用測試檔案一併刪除。比照
    // pdf_reader_view_test.dart 既有「複製位元組到 Directory.systemTemp
    // 再回傳該路徑」的既定寫法。
    test('content:// URI 書籍透過 readContentUriAll 解析為暫存檔後開啟，處理完畢後刪除暫存檔',
        () async {
      final original = readContentUriAll;
      addTearDown(() => readContentUriAll = original);

      final tmpFile = File(
          '${Directory.systemTemp.path}/pdf_content_indexer_test_${DateTime.now().microsecondsSinceEpoch}.pdf');
      await tmpFile.writeAsBytes(
          await File('test/fixtures/sample_multi_page.pdf').readAsBytes());

      var resolvedUri = '';
      readContentUriAll = (uri) async {
        resolvedUri = uri;
        return tmpFile.path;
      };

      const indexer = PdfContentIndexer();
      final book = _pdfBook(filePath: 'content://com.example.provider/doc123');

      final segments = await indexer.indexBook(book).toList();

      expect(resolvedUri, 'content://com.example.provider/doc123');
      expect(segments, isNotEmpty);
      expect(segments.map((s) => s.chapterIndex).toSet(), {0, 1, 2, 3, 4});
      expect(File('test/fixtures/sample_multi_page.pdf').existsSync(), isTrue,
          reason: '共用測試 fixture 不應被 indexBook() 的暫存檔清理邏輯誤刪');
      expect(tmpFile.existsSync(), isFalse,
          reason: 'indexBook() 應刪除它自己材質化出來的暫存檔複本（驗證清理邏輯本身仍正確運作）');
    });

    test('readContentUriAll 回傳 null 時拋出明確例外（而非讓 PdfDocument.openFile 收到 null）',
        () async {
      final original = readContentUriAll;
      addTearDown(() => readContentUriAll = original);
      readContentUriAll = (uri) async => null;

      const indexer = PdfContentIndexer();
      final book = _pdfBook(filePath: 'content://com.example.provider/missing');

      expect(
        () => indexer.indexBook(book).toList(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
