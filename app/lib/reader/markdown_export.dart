import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'annotation_list_item.dart';
import 'bookmark.dart';
import 'bookmark_position_context.dart';
import 'highlight_style.dart';

/// 產生本書的 Markdown 筆記匯出內容（epic-6-annotations Issue 5，
/// spec.md／`prototype/index.html` `exportMarkdown()` 格式骨架）。純函式，
/// 不涉及檔案 I/O、不依賴 `BuildContext`——呼叫端（`NotesBottomSheet`）負責
/// 解析 [l10n]、寫檔與觸發分享（epic-45-interface-i18n Issue 8：[l10n] 用於
/// 在地化系統結構文字，書名/作者本身與 [Bookmark.defaultName] 產出的位置
/// 標籤維持不譯，見 spec.md §7）。
///
/// 與原型格式的刻意差異：本專案 [Highlight]／[Note] 從未儲存被選取的
/// 原文文字，劃線/備註條目改顯示「樣式標籤＋位置標籤」而非引用原文；
/// 位置標籤直接複用 [Bookmark.defaultName]（`chapterTitle` 留空，天然
/// 回退為進度百分比／頁碼），見 plan-issue-5.md Global Constraints。
String generateMarkdownExport({
  required AppLocalizations l10n,
  required String bookTitle,
  String? bookAuthor,
  required double progress,
  required DateTime exportTime,
  required List<Bookmark> bookmarks,
  required List<AnnotationListItem> annotations,
}) {
  final buffer = StringBuffer();
  buffer.writeln(l10n.markdownExportTitle(bookTitle));
  buffer.writeln(
    l10n.markdownExportAuthorLabel(bookAuthor ?? l10n.markdownExportUnknownAuthor),
  );
  buffer.writeln(l10n.markdownExportProgressLabel((progress * 100).round()));
  buffer.writeln(l10n.markdownExportTimeLabel(_formatDate(exportTime, l10n)));
  buffer.writeln();

  buffer.writeln(l10n.markdownExportBookmarksSection(bookmarks.length));
  if (bookmarks.isEmpty) {
    buffer.writeln(l10n.markdownExportNoBookmarks);
    buffer.writeln();
  } else {
    for (final bookmark in bookmarks) {
      buffer.writeln('*   ${bookmark.name}');
    }
    buffer.writeln();
  }

  buffer.writeln(l10n.markdownExportAnnotationsSection(annotations.length));
  if (annotations.isEmpty) {
    buffer.writeln(l10n.markdownExportNoAnnotations);
  } else {
    for (final item in annotations) {
      final highlight = item.highlight;
      final label = highlight != null
          ? _highlightStyleLabel(highlight.style, l10n)
          : l10n.readerNotesSheetNoteLabel;
      buffer.writeln(
        l10n.markdownExportAnnotationHeading(label, _positionLabel(item, l10n)),
      );
      final note = item.note;
      if (note != null) {
        buffer.writeln('> ${note.text}');
      }
      buffer.writeln();
    }
  }

  return buffer.toString();
}

/// 供匯出檔名使用，移除 Android 檔案系統不接受的字元；清理後為空字串時
/// 回退為 `book`，避免產生副檔名前無主檔名的檔案（例如 `.md`）。
String sanitizeMarkdownFileName(String title) {
  final sanitized = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return sanitized.isEmpty || RegExp(r'^_+$').hasMatch(sanitized)
      ? 'book'
      : sanitized;
}

/// 【私有，本檔案唯一消費端】劃線樣式的顯示標籤，委派給與
/// `notes_bottom_sheet.dart` 內部同名私有函式**相同**的 ARB key
/// （`readerHighlightStyleYellow` 等，epic-45-interface-i18n Issue 4 既有）
/// ——兩個檔案仍各自維持獨立的 Dart 函式（不抽出共用），沿用
/// `notes_bottom_sheet.dart` 既有 KDoc 記載的「純 UI 顯示標籤不放在領域
/// 模型檔案、收斂在消費端自己的私有函式」設計原則，本檔案延續同一原則、
/// 對稱處理；但底層翻譯文字改指向同一組全域 ARB key，避免兩處各自維護
/// 一份意義相同的翻譯字典（Issue 8 修訂，見 plan-issue-8.md）。
String _highlightStyleLabel(HighlightStyle style, AppLocalizations l10n) {
  switch (style) {
    case HighlightStyle.highlighterYellow:
      return l10n.readerHighlightStyleYellow;
    case HighlightStyle.highlighterPink:
      return l10n.readerHighlightStylePink;
    case HighlightStyle.highlighterBlue:
      return l10n.readerHighlightStyleBlue;
    case HighlightStyle.underline:
      return l10n.readerHighlightStyleUnderline;
  }
}

/// 複用 [Bookmark.defaultName] 換算劃線/備註的位置標籤——`pdfPageIndex`／
/// `progression` 與 [Bookmark]／[Highlight]／[Note] 三者欄位語意/命名完全
/// 一致，直接透傳即可，不重新實作換算邏輯。`chapterTitle` 刻意留空：
/// 逐筆劃線/備註即時反查所在章節需要額外貫穿 `TocEntry` 清單，超出本工單
/// 範疇，`Bookmark.defaultName` 對 `chapterTitle == null` 已有既定、已測試
/// 的百分比／頁碼回退行為（見 `bookmark.dart`）。位置標籤文字依 [l10n] 產生
/// （epic-45-interface-i18n Issue 10：[Bookmark.defaultName] 已本地化，取代
/// 原 spec.md §7 的排除）。
String _positionLabel(AnnotationListItem item, AppLocalizations l10n) {
  final pdfPageIndex = item.highlight?.pdfPageIndex ?? item.note?.pdfPageIndex;
  final progression = item.highlight?.progression ?? item.note?.progression;
  return Bookmark.defaultName(
    BookmarkPositionContext(
      pdfPageIndex: pdfPageIndex,
      progression: progression,
    ),
    l10n,
  );
}

/// 依目前介面語言格式化導出時間（epic-45-interface-i18n Issue 8，
/// `spec.md` §7：改用 `DateFormat.yMd(l10n.localeName)` 取代原本固定的
/// `y-m-d` 手動拼接）。本函式不依賴 `BuildContext`，用 [l10n] 的
/// `localeName`（已是 `Intl.canonicalizedLocale()` 正規化後的格式，例如
/// `zh_TW`）取得目前語言，比照 `sync_settings_screen.dart._formatLastSyncedAt()`
/// 既有的 `DateFormat.yMd(locale)` 模式，唯一差異是那裡用
/// `Localizations.localeOf(context)`（有 context 可用），這裡沒有 context。
String _formatDate(DateTime date, AppLocalizations l10n) {
  return DateFormat.yMd(l10n.localeName).format(date);
}
