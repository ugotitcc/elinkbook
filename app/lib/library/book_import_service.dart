import 'models/book.dart';

/// 圖書庫匯入服務的抽象介面（見 docs/epics/epic-1-library/spec.md
/// 「BookImportService」章節，為唯一事實來源）。
abstract class BookImportService {
  /// 匯入單一或多個已由呼叫端（例如 file_picker）選取的檔案 URI；
  /// [displayNames] 為與 [uris] 一一對應（同索引）的真實檔名，供格式偵測在
  /// URI 本身不含可辨識副檔名時當退路（例如部分文件提供者的 URI 只帶不透明
  /// 數字文件 ID，見 book_import_service_impl.dart 的說明），長度可短於
  /// [uris] 或為 `null`（該索引/整體視為沒有檔名可用，退回只看 URI）；
  /// [folderName] 標記來源資料夾名稱供 FR-34 自動分類判斷，單檔/多檔匯入
  /// （非資料夾匯入）時為 `null`。
  Future<List<Book>> importFiles(
    List<String> uris, {
    List<String?>? displayNames,
    String? folderName,
  });

  /// 匯入整個資料夾；[autoGroupByFolderName] 對應 FR-34 開關（預設 true）。
  Future<List<Book>> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  });
}
