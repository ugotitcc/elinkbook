import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/annotation_list_item.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/markdown_export.dart';
import 'package:elinkbook/reader/note.dart';

void main() {
  group('generateMarkdownExport', () {
    test('有書籤、有劃線、有依附備註時，輸出格式包含三個段落與正確筆數', () {
      final result = generateMarkdownExport(
        bookTitle: '紅樓夢',
        bookAuthor: '曹雪芹',
        progress: 0.35,
        exportTime: DateTime(2026, 7, 18),
        bookmarks: const [
          Bookmark(
            bookId: 'b1',
            name: '第二章 (35%)',
            epubLocatorJson: '{}',
            progression: 0.35,
          ),
        ],
        annotations: [
          AnnotationListItem(
            highlight: const Highlight(
              bookId: 'b1',
              style: HighlightStyle.highlighterYellow,
              epubLocatorJson: '{}',
              progression: 0.2,
            ),
            note: const Note(
              bookId: 'b1',
              text: '黛玉名句',
              epubLocatorJson: '{}',
              progression: 0.2,
              highlightId: 1,
            ),
          ),
        ],
      );

      expect(result, contains('# 閱讀筆記：《紅樓夢》'));
      expect(result, contains('**作者**：曹雪芹'));
      expect(result, contains('**閱讀進度**：35%'));
      expect(result, contains('**導出時間**：2026-07-18'));
      expect(result, contains('## 🔖 書籤清單 (1)'));
      expect(result, contains('*   第二章 (35%)'));
      expect(result, contains('## ✏️ 劃線與個人備註 (1)'));
      expect(result, contains('### 📌 螢光筆（黃）（位置：20% 處）'));
      expect(result, contains('> 黛玉名句'));
    });

    test('只有書籤時，劃線與備註段落顯示空狀態文字，作者缺省時顯示「未知作者」', () {
      final result = generateMarkdownExport(
        bookTitle: '書籤書',
        progress: 0.5,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [
          Bookmark(bookId: 'b1', name: '第 3 頁', pdfPageIndex: 2),
        ],
        annotations: const [],
      );

      expect(result, contains('**作者**：未知作者'));
      expect(result, contains('## 🔖 書籤清單 (1)'));
      expect(result, contains('*   第 3 頁'));
      expect(result, contains('## ✏️ 劃線與個人備註 (0)'));
      expect(result, contains('*(尚未加入任何劃線或備註)*'));
    });

    test('只有劃線、無依附備註時，該筆項目不含引言區塊', () {
      final result = generateMarkdownExport(
        bookTitle: '劃線書',
        progress: 0.1,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: [
          AnnotationListItem(
            highlight: const Highlight(
              bookId: 'b1',
              style: HighlightStyle.underline,
              pdfPageIndex: 4,
            ),
          ),
        ],
      );

      expect(result, contains('## 🔖 書籤清單 (0)'));
      expect(result, contains('*(尚未加入書籤)*'));
      expect(result, contains('### 📌 底線（位置：第 5 頁）'));
      expect(result, isNot(contains('> ')));
    });

    test('只有純備註（無劃線）時，標籤顯示「備註」', () {
      final result = generateMarkdownExport(
        bookTitle: '備註書',
        progress: 0.6,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: [
          AnnotationListItem(
            note: const Note(bookId: 'b1', text: '單純心得', progression: 0.6),
          ),
        ],
      );

      expect(result, contains('### 📌 備註（位置：60% 處）'));
      expect(result, contains('> 單純心得'));
    });

    test('書籤與劃線備註皆為空時，兩段落皆顯示空狀態文字', () {
      final result = generateMarkdownExport(
        bookTitle: '空書',
        progress: 0.0,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: const [],
      );

      expect(result, contains('## 🔖 書籤清單 (0)'));
      expect(result, contains('*(尚未加入書籤)*'));
      expect(result, contains('## ✏️ 劃線與個人備註 (0)'));
      expect(result, contains('*(尚未加入任何劃線或備註)*'));
    });
  });

  group('sanitizeMarkdownFileName', () {
    test('移除檔案系統不安全字元', () {
      expect(sanitizeMarkdownFileName('紅樓夢/夢?'), '紅樓夢_夢_');
    });

    test('清理後為空字串時回退為 book', () {
      expect(sanitizeMarkdownFileName('///'), 'book');
    });
  });
}
