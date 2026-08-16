/// 自然排序比較器：先切割成「連續數字」與「連續非數字」交錯的片段，數字
/// 片段以數值比較、其餘片段忽略大小寫比較（審查修正，見
/// reviews/review-issue-3-plan.md Minor #2：漫畫壓縮檔常見由不同掃圖/
/// 壓製來源合併，檔名大小寫可能不一致，例如「Page1.jpg」與「page2.jpg」
/// 混用——若依原始大小寫比較，ASCII 'P'(0x50) < 'p'(0x70) 會讓
/// 「Page2.jpg」排到「page1.jpg」之前，產生違反直覺的錯誤頁序；忽略大小寫
/// 後兩者依數字片段 1 < 2 正確排序）。`comic-book.js` 的 `makeComicBook()`
/// 對圖片檔名僅用純字典序 `.sort()`（見 issues.md Issue 1 Spike 查證：
/// 「1.jpg」「10.jpg」「2.jpg」會被排成「1,10,2,3...」），須在 Dart 端匯入
/// 階段以本比較器排出正確頁序後，重新命名為零填補檔名（見
/// [prepareCbzForImport]），讓 comic-book.js 自己的字典序排序也能得到相同
/// 結果，不依賴其內建排序。
int compareNaturalOrder(String a, String b) {
  final chunksA = _splitIntoChunks(a);
  final chunksB = _splitIntoChunks(b);
  final len = chunksA.length < chunksB.length ? chunksA.length : chunksB.length;
  for (var i = 0; i < len; i++) {
    final numA = int.tryParse(chunksA[i]);
    final numB = int.tryParse(chunksB[i]);
    final cmp = (numA != null && numB != null)
        ? numA.compareTo(numB)
        : chunksA[i].toLowerCase().compareTo(chunksB[i].toLowerCase());
    if (cmp != 0) return cmp;
  }
  return chunksA.length.compareTo(chunksB.length);
}

List<String> _splitIntoChunks(String value) {
  final chunks = <String>[];
  final buffer = StringBuffer();
  bool? lastWasDigit;
  for (final rune in value.runes) {
    final isDigit = rune >= 0x30 && rune <= 0x39; // '0'-'9'
    if (lastWasDigit != null && isDigit != lastWasDigit) {
      chunks.add(buffer.toString());
      buffer.clear();
    }
    buffer.writeCharCode(rune);
    lastWasDigit = isDigit;
  }
  if (buffer.isNotEmpty) chunks.add(buffer.toString());
  return chunks;
}
