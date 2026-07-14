/// [PdfReaderView] 頁碼變動時（開書完成、翻頁、跳頁）一次性回報的頁碼資訊，
/// 皆為 0-indexed（比照專案既有慣例）。
class PdfPageInfo {
  final int pageIndex;
  final int totalPages;

  const PdfPageInfo({
    required this.pageIndex,
    required this.totalPages,
  });

  @override
  bool operator ==(Object other) =>
      other is PdfPageInfo &&
      other.pageIndex == pageIndex &&
      other.totalPages == totalPages;

  @override
  int get hashCode => Object.hash(pageIndex, totalPages);

  @override
  String toString() => 'PdfPageInfo(pageIndex: $pageIndex, totalPages: $totalPages)';
}
