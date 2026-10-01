import 'models/book.dart';
import 'models/library_enums.dart';

/// 一次匯入呼叫（[BookImportService.importFiles]／[importFolder]）的結果：
/// 成功寫入的書籍清單，以及因來源 URI 與圖書庫既有書籍重複而被跳過的檔案數
/// 量（【診斷修正】見 book_import_service_impl.dart「_importSingleFile 前的
/// 重複偵測」說明——判定依據是來源 URI/路徑是否與現有書籍的 filePath 相同，
/// 不比對書名/作者）。呼叫端（`LibraryScreen`）用 [skippedDuplicateCount]
/// 決定是否顯示「N 本已存在，已跳過」提示。
/// 一次匯入「整體失敗」的原因（目前只有資料夾匯入會失敗）。單檔匯入失敗仍是
/// 該檔被略過、不影響其他檔案，不屬於這裡。
enum ImportFailure {
  /// 無法取得資料夾的持久化授權（見 CONTEXT.md「持久化授權」），沒有授權就
  /// 無法列舉內容。
  folderAccessDenied,

  /// 已有授權，但列舉資料夾內容失敗（原生端拋例外或沒有回傳內容）。
  folderListingFailed,
}

class ImportResult {
  final List<Book> importedBooks;
  final int skippedDuplicateCount;

  /// 非 null 代表整次匯入失敗（此時 [importedBooks] 為空）。「資料夾裡本來
  /// 就沒有可匯入的書」不是失敗，維持 null。
  final ImportFailure? failure;

  const ImportResult({
    required this.importedBooks,
    this.skippedDuplicateCount = 0,
    this.failure,
  });
}

/// epic-15-storage-permission Issue 2：[BookImportService.relinkBook] 的結果。
/// 用 sealed class 而非純列舉：成功時呼叫端需要知道最終生效的檔案路徑
/// （可能是落地複本的本機路徑，不一定是選取的 URI），必須帶出更新後的
/// [Book]。
sealed class BookRelinkResult {
  const BookRelinkResult();
}

/// 重新連結成功；[updatedBook] 是已寫入資料庫的最新記錄。
final class BookRelinkSuccess extends BookRelinkResult {
  final Book updatedBook;
  const BookRelinkSuccess(this.updatedBook);
}

/// 重新連結失敗的原因（使用者可見文字由呼叫端在地化）。
enum BookRelinkFailureReason {
  /// 選取的檔案格式與原書不同。
  formatMismatch,

  /// 內容指紋不同：選到的不是同一本書。
  contentMismatch,

  /// 選取的檔案已經是書庫中另一本書的來源。
  alreadyInLibrary,

  /// 讀取或寫入失敗，也包含找不到該 id 的書籍記錄、不支援重新連結的格式。
  failed,
}

/// 重新連結失敗；原本的書籍記錄完全不動。
final class BookRelinkFailure extends BookRelinkResult {
  final BookRelinkFailureReason reason;
  const BookRelinkFailure(this.reason);
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
  /// [source]、[remoteServerId]、[remoteBookIds] 與 [remoteDownloadUrls] 供遠端
  /// 書架（如 Calibre OPDS）下載落地時寫入對應的伺服器與遠端書籍參照資料。
  /// [cloudFileIds]（path 對應雲端原始檔案 ID）供雲端匯入（Google Drive／
  /// OneDrive）下載落地時寫入 [Book.cloudFileId]，與 [remoteBookIds] 是
  /// 概念上完全獨立的參數（見 `CONTEXT.md`「雲端匯入來源帳號」／「遠端
  /// 書庫」的既定區分），可與 [source]／[remoteServerId] 等既有參數並存
  /// 但實務上不會同時使用。
  Future<ImportResult> importFiles(
    List<String> uris, {
    List<String?>? displayNames,
    String? folderName,
    BookSource source = BookSource.local,
    String? remoteServerId,
    Map<String, String>? remoteBookIds,
    Map<String, String>? remoteDownloadUrls,
    Map<String, String>? cloudFileIds,
  });

  /// 匯入整個資料夾；[autoGroupByFolderName] 對應 FR-34 開關（預設 true）。
  /// 與 [importFiles] 相同，來源 URI 與既有書籍重複的檔案會被跳過。
  Future<ImportResult> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  });

  /// epic-15-storage-permission Issue 2：把書籍 [bookId] 的檔案位置原地換成
  /// 使用者重新選取的 [newUri]（[displayName] 為選擇器提供的真實檔名，
  /// 供 URI 不含副檔名時判斷格式）。先驗證格式、重複、內容指紋，全部通過
  /// 後才持久化授權或落地複本，最後以 `updateBook` 原地更新——`id`、
  /// 閱讀位置、劃線、書籤全部保留。任何驗證失敗都不修改記錄、不持久化
  /// 授權、不留下檔案。處理順序見 epic-15 spec.md「Re-link 服務」。
  Future<BookRelinkResult> relinkBook(
    String bookId,
    String newUri, {
    String? displayName,
  });
}
