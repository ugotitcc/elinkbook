/// 書籍檔案格式，依副檔名偵測。
enum BookFormat { epub, pdf, unknown }

/// 依檔案路徑的副檔名判斷書籍格式（不分大小寫）。無法識別的副檔名（含無副
/// 檔名、空字串）一律回傳 [BookFormat.unknown]，絕不拋出例外。
BookFormat detectBookFormat(String path) {
  final lowerPath = path.toLowerCase();
  if (lowerPath.endsWith('.epub')) return BookFormat.epub;
  if (lowerPath.endsWith('.pdf')) return BookFormat.pdf;
  return BookFormat.unknown;
}
