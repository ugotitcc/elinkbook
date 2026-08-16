/// 書籍檔案格式，依副檔名偵測。
enum BookFormat { epub, pdf, azw3, cbz, unknown }

/// 依檔案路徑的副檔名判斷書籍格式（不分大小寫）。無法識別的副檔名（含無副
/// 檔名、空字串）一律回傳 [BookFormat.unknown]，絕不拋出例外。
BookFormat detectBookFormat(String path) {
  final lowerPath = path.toLowerCase();
  if (lowerPath.endsWith('.epub')) return BookFormat.epub;
  if (lowerPath.endsWith('.pdf')) return BookFormat.pdf;
  if (lowerPath.endsWith('.azw3')) return BookFormat.azw3;
  if (lowerPath.endsWith('.cbz')) return BookFormat.cbz;
  return BookFormat.unknown;
}

/// 是否為經由 [FoliateReaderView]（`foliate-js`）渲染的格式——與
/// [BookFormat.pdf] 互斥，[BookFormat.unknown] 兩者皆非。`reader_screen.dart`
/// 內所有「這是不是走 Foliate 流式管線」的判斷皆應呼叫本函式，而非逐一列舉
/// 格式，避免未來新增格式（TXT/MD）時遺漏更新（epic-11-multi-format-reader
/// Issue 3，spec.md「格式偵測與渲染分派」）。
bool isFoliateFormat(BookFormat format) =>
    format == BookFormat.epub ||
    format == BookFormat.azw3 ||
    format == BookFormat.cbz;
