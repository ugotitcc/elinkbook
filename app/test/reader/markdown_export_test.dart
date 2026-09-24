import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/annotation_list_item.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/markdown_export.dart';
import 'package:elinkbook/reader/note.dart';

void main() {
  setUpAll(() async {
    // DateFormat.yMd() 在純 test() 環境（無 MaterialApp/widget pump）下
    // 需要顯式初始化 locale 符號資料，否則拋出 LocaleDataException（見
    // plan-issue-8.md Global Constraints，已實測驗證）。
    await initializeDateFormatting();
  });

  group('generateMarkdownExport', () {
    test('有書籤、有劃線、有依附備註時，輸出格式包含三個段落與正確筆數', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '紅樓夢',
        bookAuthor: '曹雪芹',
        progress: 0.35,
        exportTime: DateTime(2026, 7, 18),
        bookmarks: const [
          Bookmark(
            id: 'bm1',
            bookId: 'b1',
            name: '第二章 (35%)',
            epubLocatorJson: '{}',
            progression: 0.35,
          ),
        ],
        annotations: [
          AnnotationListItem(
            highlight: const Highlight(
              id: 'h1',
              bookId: 'b1',
              style: HighlightStyle.highlighterYellow,
              epubLocatorJson: '{}',
              progression: 0.2,
            ),
            note: const Note(
              id: 'n1',
              bookId: 'b1',
              text: '黛玉名句',
              epubLocatorJson: '{}',
              progression: 0.2,
              highlightId: 'h1',
            ),
          ),
        ],
      );

      expect(result, contains('# 閱讀筆記：《紅樓夢》'));
      expect(result, contains('**作者**：曹雪芹'));
      expect(result, contains('**閱讀進度**：35%'));
      expect(result, contains('**導出時間**：2026/7/18'));
      expect(result, contains('## 🔖 書籤清單 (1)'));
      expect(result, contains('*   第二章 (35%)'));
      expect(result, contains('## ✏️ 劃線與個人備註 (1)'));
      expect(result, contains('### 📌 螢光筆（黃）（位置：20% 處）'));
      expect(result, contains('> 黛玉名句'));
    });

    test('只有書籤時，劃線與備註段落顯示空狀態文字，作者缺省時顯示「未知作者」', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '書籤書',
        progress: 0.5,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [
          Bookmark(id: 'bm2', bookId: 'b1', name: '第 3 頁', pdfPageIndex: 2),
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
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '劃線書',
        progress: 0.1,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: [
          AnnotationListItem(
            highlight: const Highlight(
              id: 'h2',
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
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '備註書',
        progress: 0.6,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: [
          AnnotationListItem(
            note: const Note(id: 'n2', bookId: 'b1', text: '單純心得', progression: 0.6),
          ),
        ],
      );

      expect(result, contains('### 📌 備註（位置：60% 處）'));
      expect(result, contains('> 單純心得'));
    });

    test('書籤與劃線備註皆為空時，兩段落皆顯示空狀態文字', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final result = generateMarkdownExport(
        l10n: l10n,
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

    test('英文介面下，系統結構文字與導出時間格式皆正確切換（書名/作者/位置標籤等使用者資料或既有機制產出文字不受影響）', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '紅樓夢',
        bookAuthor: '曹雪芹',
        progress: 0.35,
        exportTime: DateTime(2026, 7, 18),
        bookmarks: const [
          Bookmark(
            id: 'bm1',
            bookId: 'b1',
            name: '第二章 (35%)',
            epubLocatorJson: '{}',
            progression: 0.35,
          ),
        ],
        annotations: [
          AnnotationListItem(
            highlight: const Highlight(
              id: 'h1',
              bookId: 'b1',
              style: HighlightStyle.highlighterYellow,
              epubLocatorJson: '{}',
              progression: 0.2,
            ),
          ),
        ],
      );

      expect(result, contains('# Reading Notes: 紅樓夢'));
      expect(result, contains('**Author**: 曹雪芹'));
      expect(result, contains('**Reading Progress**: 35%'));
      expect(result, contains('**Export Time**: 7/18/2026'));
      expect(result, contains('## 🔖 Bookmarks (1)'));
      expect(result, contains('*   第二章 (35%)'));
      expect(result, contains('## ✏️ Highlights & Notes (1)'));
      // 位置標籤由 Bookmark.defaultName(context, l10n) 依介面語言產生
      // （epic-45-interface-i18n Issue 10，原 spec.md §7 的排除已取消）。
      expect(result, contains('### 📌 Highlighter (Yellow) (Position: At 20%)'));
    });

    test('英文介面下，作者缺省與書籤/劃線備註皆為空時，回退文字與空狀態文字皆正確切換', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: 'Empty Book',
        progress: 0.0,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: const [],
      );

      expect(result, contains('**Author**: Unknown Author'));
      expect(result, contains('## 🔖 Bookmarks (0)'));
      expect(result, contains('*(No bookmarks yet)*'));
      expect(result, contains('## ✏️ Highlights & Notes (0)'));
      expect(result, contains('*(No highlights or notes yet)*'));
    });

    test('簡體中文介面下，系統結構文字、導出時間格式與純備註標籤皆正確切換', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '红楼梦',
        bookAuthor: '曹雪芹',
        progress: 0.35,
        exportTime: DateTime(2026, 7, 18),
        bookmarks: const [
          Bookmark(
            id: 'bm1',
            bookId: 'b1',
            name: '第二章 (35%)',
            epubLocatorJson: '{}',
            progression: 0.35,
          ),
        ],
        annotations: [
          AnnotationListItem(
            note: const Note(
              id: 'n2',
              bookId: 'b1',
              text: '单纯心得',
              progression: 0.6,
            ),
          ),
        ],
      );

      expect(result, contains('# 阅读笔记：《红楼梦》'));
      expect(result, contains('**作者**：曹雪芹'));
      expect(result, contains('**导出时间**：2026/7/18'));
      expect(result, contains('## 🔖 书签清单 (1)'));
      expect(result, contains('*   第二章 (35%)'));
      expect(result, contains('## ✏️ 划线与个人备注 (1)'));
      // 位置標籤由 Bookmark.defaultName(context, l10n) 依介面語言產生，
      // zh_CN 介面下為簡體「处」（epic-45-interface-i18n Issue 10，
      // 原 spec.md §7 的排除已取消）。
      expect(result, contains('### 📌 备注（位置：60% 处）'));
      expect(result, contains('> 单纯心得'));
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
