import 'dart:convert';

/// 常見中文章節標題格式（「第 X 章/回/卷/節/集」，X 可為阿拉伯數字或中文
/// 數字）與英文 `Chapter N` 格式（spec.md「TXT 章節/目錄」）。`^` 搭配
/// `multiLine: true` 確保只匹配行首（容許前導空白/定位字元），避免內文
/// 中提及「第一章」字樣被誤判為標題（見對應測試案例）。標題文字擷取到
/// 該行結尾（不含換行符）。`caseSensitive: false`（審查修正，見
/// reviews/review-issue-4-plan.md Minor #1）讓 `CHAPTER 1`／`chapter 1`
/// 等大小寫變體皆可辨識，不影響中文分支（中文字元無大小寫之分）。
final _chapterHeadingRegex = RegExp(
  r'^[ \t]*(第[0-9零一二三四五六七八九十百千萬两兩]+[章回卷節集][^\n]*|Chapter\s+\d+[^\n]*)',
  multiLine: true,
  caseSensitive: false,
);

class TxtChapter {
  /// `null` 代表沒有偵測到章節標題（整份檔案找不到任何章節標記時的單一
  /// 章節退回情境，見 [splitIntoChapters]）。
  final String? title;
  final String content;
  const TxtChapter({this.title, required this.content});
}

/// 依 [_chapterHeadingRegex] 掃描章節標題行，切出章節清單；找不到任何
/// 標題時回傳單一涵蓋全文的章節（`title: null`）。標題行本身保留在該
/// 章節 `content` 開頭（與內文一起顯示，非額外抽離成獨立欄位），比照多數
/// TXT 轉 EPUB 工具的既有慣例。
List<TxtChapter> splitIntoChapters(String text) {
  final matches = _chapterHeadingRegex.allMatches(text).toList();
  if (matches.isEmpty) {
    return [TxtChapter(content: text)];
  }
  final chapters = <TxtChapter>[];
  if (matches.first.start > 0) {
    chapters.add(TxtChapter(content: text.substring(0, matches.first.start)));
  }
  for (var i = 0; i < matches.length; i++) {
    final start = matches[i].start;
    final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
    final title = matches[i].group(0)!.trim();
    chapters.add(TxtChapter(title: title, content: text.substring(start, end)));
  }
  return chapters;
}

/// spec.md「TXT 雙重分塊防護」建議區間 300~500KB，取中間值。
const int kTxtChunkMaxBytes = 400000;

/// 若 [content] 的 UTF-8 位元組長度超過 [maxBytes]，依行邊界切成多個子
/// 區塊，每個子區塊不超過門檻（單一行本身超過門檻時，該行獨立成一個
/// 區塊，不會再往下切字——避免切斷多位元組字元或產生無意義的極短區塊）。
/// 未超過門檻時原樣回傳單一元素清單。
List<String> chunkByByteSize(String content, {int maxBytes = kTxtChunkMaxBytes}) {
  if (utf8.encode(content).length <= maxBytes) return [content];
  final lines = content.split(RegExp(r'\r\n|\r|\n'));
  final chunks = <String>[];
  final current = StringBuffer();
  var currentBytes = 0;
  for (final line in lines) {
    final lineBytes = utf8.encode(line).length + 1; // +1 約略計入換行符
    if (currentBytes + lineBytes > maxBytes && current.isNotEmpty) {
      chunks.add(current.toString());
      current.clear();
      currentBytes = 0;
    }
    current.writeln(line);
    currentBytes += lineBytes;
  }
  if (current.isNotEmpty) chunks.add(current.toString());
  return chunks;
}
