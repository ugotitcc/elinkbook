import 'dart:io';

import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/library_enums.dart';

/// 一次上傳單一檔案的處理結果（epic-44-wifi-book-transfer spec.md
/// 「`wifi_transfer_service.dart`」，Issue 3 填入 [WifiTransferService.handleUploadedFile]
/// 實作時對應的四種結果）。
enum UploadOutcome { imported, duplicateSkipped, unsupportedFormat, failed }

class UploadResult {
  final String originalFileName;
  final UploadOutcome outcome;
  const UploadResult({required this.originalFileName, required this.outcome});
}

/// `GET /api/books` 下載清單的單一項目（Issue 2 填入
/// [WifiTransferService.listDownloadableBooks] 實作時使用）。[sizeBytes]
/// 對 `content://` 來源或本機檔案已不存在時恆為 `null`（清單階段嚴禁觸發
/// 材質化）。
class DownloadableBook {
  final String id;
  final String title;
  final BookFileFormat format;
  final int? sizeBytes;
  const DownloadableBook({
    required this.id,
    required this.title,
    required this.format,
    this.sizeBytes,
  });
}

/// 下載時實際要串流的來源資訊（Issue 2 填入
/// [WifiTransferService.resolveDownloadSource] 實作時使用）。
/// [resolvedPath] 一律是可直接 `File.openRead()` 的本機路徑（`content://`
/// 已由呼叫端材質化為暫存檔）；[downloadFileName] 已套用「TXT/MD 來源
/// 書籍誠實回傳 .epub」規則。[isTemporaryFile] 為 `true` 時，HTTP 回應
/// 完成/斷線後呼叫端須刪除 [resolvedPath]。
class DownloadSource {
  final String resolvedPath;
  final String downloadFileName;
  final bool isTemporaryFile;
  const DownloadSource({
    required this.resolvedPath,
    required this.downloadFileName,
    required this.isTemporaryFile,
  });
}

/// 純邏輯層，建構子全部依賴皆可注入假實作，供 `flutter test` 驗證業務
/// 規則（格式白名單、去重、下載清單過濾）而不需要真實 sqflite/原生呼叫/
/// socket。比照 `RemoteCatalogDependencies`／`ComputeRemoteFingerprint`
/// 既有的依賴注入慣例。
///
/// 本 Issue（Issue 1）只建立骨架——三個業務方法先 `throw
/// UnimplementedError()`，讓 [WifiTransferHttpServer]（Task 4）的建構子
/// 型別依賴可以編譯通過；Issue 2 填入 [listDownloadableBooks]／
/// [resolveDownloadSource]，Issue 3 填入 [handleUploadedFile]。
class WifiTransferService {
  final LibraryRepository libraryRepository;
  final BookImportService importService;
  final ComputeRemoteFingerprint computeFingerprint;

  /// 材質化 `content://` URI 為本機暫存檔（Issue 0 修正後的
  /// `readContentUriAll` 頂層函式變數，走背景佇列 channel）。失敗時回傳
  /// `null`。
  final Future<String?> Function(String contentUri) materializeContentUri;

  /// 刪除一個檔案路徑（生產環境為 `File(path).delete()`）。
  final Future<void> Function(String path) deleteFile;

  const WifiTransferService({
    required this.libraryRepository,
    required this.importService,
    required this.computeFingerprint,
    required this.materializeContentUri,
    required this.deleteFile,
  });

  /// Issue 3 實作：對落地檔案算內容指紋 → 查重複 → 匯入或略過，詳見
  /// spec.md「`wifi_transfer_service.dart`」。
  Future<UploadResult> handleUploadedFile({
    required String landedPath,
    required String originalFileName,
    required BookFileFormat format,
  }) async {
    throw UnimplementedError('Issue 3 實作：上傳落地/去重/匯入邏輯');
  }

  /// 對應「下載清單僅列出 isDownloaded == true」決策（spec.md
  /// 「`wifi_transfer_service.dart`」）。[DownloadableBook.sizeBytes] 只對
  /// 非 `content://` 的本機實體檔案計算，且須先 `await file.exists()`
  /// 防呆——書籍記錄可能因使用者在系統層級手動搬移/刪除本機檔案而失效，
  /// 直接呼叫 `.length()` 會拋 `FileSystemException` 中斷整個清單查詢；
  /// `content://` 或檔案不存在時 sizeBytes 恆為 null，清單建立階段嚴禁
  /// 呼叫 [materializeContentUri] 觸發材質化（會讓瀏覽清單時就把整個書架
  /// 複製一份到快取目錄）。
  Future<List<DownloadableBook>> listDownloadableBooks() async {
    final books = await libraryRepository.listBooks();
    final result = <DownloadableBook>[];
    for (final book in books) {
      if (!book.isDownloaded) continue;
      result.add(DownloadableBook(
        id: book.id,
        title: book.title,
        format: book.format,
        sizeBytes: await _localSizeBytes(book),
      ));
    }
    return result;
  }

  Future<int?> _localSizeBytes(Book book) async {
    if (book.filePath.contains('://')) return null;
    // 【`/receiving-code-review` 審查修正，review-plan-issue-2.md I-5】
    // await file.exists() 與 file.length() 之間仍有極短暫的 TOCTOU
    // 間隙（檔案在這中間被外部刪除/權限被收回），用 try-catch 兜底，
    // 讓單一一本書的檔案系統例外不會打垮整支 /api/books 清單查詢。
    try {
      final file = File(book.filePath);
      if (!await file.exists()) return null;
      return await file.length();
    } catch (_) {
      return null;
    }
  }

  /// Issue 2 實作：`findBookById(bookId)` → `content://` 材質化 →
  /// TXT/MD 副檔名改寫，詳見 spec.md「`wifi_transfer_service.dart`」。
  Future<DownloadSource?> resolveDownloadSource(String bookId) async {
    throw UnimplementedError('Issue 2 實作：下載來源解析');
  }
}
