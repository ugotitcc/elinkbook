import 'models/book.dart';

/// 一次匯入呼叫（[BookImportService.importFiles]／[importFolder]）的結果：
/// 成功寫入的書籍清單，以及因來源 URI 與圖書庫既有書籍重複而被跳過的檔案數
/// 量（【診斷修正】見 book_import_service_impl.dart「_importSingleFile 前的
/// 重複偵測」說明——判定依據是來源 URI/路徑是否與現有書籍的 filePath 相同，
/// 不比對書名/作者）。呼叫端（`LibraryScreen`）用 [skippedDuplicateCount]
/// 決定是否顯示「N 本已存在，已跳過」提示。
class ImportResult {
  final List<Book> importedBooks;
  final int skippedDuplicateCount;

  const ImportResult({
    required this.importedBooks,
    this.skippedDuplicateCount = 0,
  });
}

/// 圖書庫匯入服務的抽象介面（見 docs/epics/epic-1-library/spec.md
/// 「BookImportService」章節，為唯一事實來源）。
abstract class BookImportService {
  /// 匯入單一或多個已由呼叫端（例如 file_picker）選取的檔案 URI；
  /// [displayNames] 為與 [uris] 一一對應（同索引）的真實檔名，供格式偵測在
  /// URI 本身不含可辨識副檔名時當退路（例如部分文件提供者的 URI 只帶不透明
  /// 數字文件 ID，見 book_import_service_impl.dart 的說明），長度可短於
  /// [uris] 或為 `null`（該索引/整體視為沒有檔名可用，退回只看 URI）；
  /// [folderName] 標記來源資料夾名稱供 FR-34 自動分類判斷，單檔/多檔匯入
  /// （非資料夾匯入）時為 `null`。與圖書庫既有書籍來源 URI 相同的檔案會被
  /// 跳過，不會重複匯入（見 [ImportResult.skippedDuplicateCount]）。
  Future<ImportResult> importFiles(
    List<String> uris, {
    List<String?>? displayNames,
    String? folderName,
  });

  /// 匯入整個資料夾；[autoGroupByFolderName] 對應 FR-34 開關（預設 true）。
  /// 與 [importFiles] 相同，來源 URI 與既有書籍重複的檔案會被跳過。
  Future<ImportResult> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  });
}
