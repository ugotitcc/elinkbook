import 'annotation_list_item.dart';
import 'bookmark.dart';
import 'bookmark_position_context.dart';
import 'highlight_style.dart';

/// 產生本書的 Markdown 筆記匯出內容（epic-6-annotations Issue 5，
/// spec.md／`prototype/index.html` `exportMarkdown()` 格式骨架）。純函式，
/// 不涉及檔案 I/O——呼叫端（`NotesBottomSheet`）負責寫檔與觸發分享。
///
/// 與原型格式的刻意差異：本專案 [Highlight]／[Note] 從未儲存被選取的
/// 原文文字，劃線/備註條目改顯示「樣式標籤＋位置標籤」而非引用原文；
/// 位置標籤直接複用 [Bookmark.defaultName]（`chapterTitle` 留空，天然
/// 回退為進度百分比／頁碼），見 plan-issue-5.md Global Constraints。
String generateMarkdownExport({
  required String bookTitle,
  String? bookAuthor,
  required double progress,
  required DateTime exportTime,
  required List<Bookmark> bookmarks,
  required List<AnnotationListItem> annotations,
}) {
  final buffer = StringBuffer();
  buffer.writeln('# 閱讀筆記：《$bookTitle》');
  buffer.writeln('*   **作者**：${bookAuthor ?? '未知作者'}');
  buffer.writeln('*   **閱讀進度**：${(progress * 100).round()}%');
  buffer.writeln('*   **導出時間**：${_formatDate(exportTime)}');
  buffer.writeln();

  buffer.writeln('## 🔖 書籤清單 (${bookmarks.length})');
  if (bookmarks.isEmpty) {
    buffer.writeln('*(尚未加入書籤)*');
    buffer.writeln();
  } else {
    for (final bookmark in bookmarks) {
      buffer.writeln('*   ${bookmark.name}');
    }
    buffer.writeln();
  }

  buffer.writeln('## ✏️ 劃線與個人備註 (${annotations.length})');
  if (annotations.isEmpty) {
    buffer.writeln('*(尚未加入任何劃線或備註)*');
  } else {
    for (final item in annotations) {
      final highlight = item.highlight;
      final label =
          highlight != null ? _highlightStyleLabel(highlight.style) : '備註';
      buffer.writeln('### 📌 $label（位置：${_positionLabel(item)}）');
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

/// 【私有，本檔案唯一消費端】劃線樣式的中文顯示標籤。刻意與
/// `notes_bottom_sheet.dart` 內部同名私有函式重複，而非抽出共用——兩者
/// 皆為各自檔案的唯一消費端，且 `notes_bottom_sheet.dart` 的既有 KDoc
/// 已明確記載「純 UI 顯示標籤不放在領域模型檔案、收斂在消費端自己的私有
/// 函式」設計原則（見該檔案 Task 7 說明），本檔案延續同一原則、對稱處理，
/// 不回頭修改已審查穩定的既有檔案。
String _highlightStyleLabel(HighlightStyle style) {
  switch (style) {
    case HighlightStyle.highlighterYellow:
      return '螢光筆（黃）';
    case HighlightStyle.highlighterPink:
      return '螢光筆（粉）';
    case HighlightStyle.highlighterBlue:
      return '螢光筆（藍）';
    case HighlightStyle.underline:
      return '底線';
  }
}

/// 複用 [Bookmark.defaultName] 換算劃線/備註的位置標籤——`pdfPageIndex`／
/// `progression` 與 [Bookmark]／[Highlight]／[Note] 三者欄位語意/命名完全
/// 一致，直接透傳即可，不重新實作換算邏輯。`chapterTitle` 刻意留空：
/// 逐筆劃線/備註即時反查所在章節需要額外貫穿 `TocEntry` 清單，超出本工單
/// 範疇，`Bookmark.defaultName` 對 `chapterTitle == null` 已有既定、已測試
/// 的百分比／頁碼回退行為（見 `bookmark.dart`）。
String _positionLabel(AnnotationListItem item) {
  final pdfPageIndex = item.highlight?.pdfPageIndex ?? item.note?.pdfPageIndex;
  final progression = item.highlight?.progression ?? item.note?.progression;
  return Bookmark.defaultName(BookmarkPositionContext(
    pdfPageIndex: pdfPageIndex,
    progression: progression,
  ));
}

String _formatDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
