import 'models/book.dart';

/// 圖書庫匯入服務的抽象介面（見 docs/epics/epic-1-library/spec.md
/// 「BookImportService」章節，為唯一事實來源）。
abstract class BookImportService {
  /// 匯入單一或多個已由呼叫端（例如 file_picker）選取的檔案 URI；
  /// [folderName] 標記來源資料夾名稱供 FR-34 自動分類判斷，單檔/多檔匯入
  /// （非資料夾匯入）時為 `null`。
  Future<List<Book>> importFiles(List<String> uris, {String? folderName});

  /// 匯入整個資料夾；[autoGroupByFolderName] 對應 FR-34 開關（預設 true）。
  Future<List<Book>> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  });
}
