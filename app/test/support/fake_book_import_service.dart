import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/book.dart';

/// 供 widget test 使用的 [BookImportService] 假實作。Widget test 只驗證匯入
/// 按鈕存在（見 docs/epics/epic-1-library/spec.md「測試決策」：widget test
/// 不需真實裝置），不會實際呼叫這兩個方法，因此回傳空清單即可。
class FakeBookImportService implements BookImportService {
  @override
  Future<List<Book>> importFiles(
    List<String> uris, {
    String? folderName,
  }) async =>
      [];

  @override
  Future<List<Book>> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  }) async =>
      [];
}
