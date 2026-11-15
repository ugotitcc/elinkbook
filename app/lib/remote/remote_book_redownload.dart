import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../search/full_text_search_settings_repository.dart';
import 'opds_client.dart';
import 'opds_types.dart';
import 'remote_book_downloader.dart';
import 'remote_server_profile.dart';
import 'remote_server_repository.dart';

/// 重新下載一本「僅雲端紀錄」遠端書的結果（epic-54 Issue 38）。
///
/// 畫面把它對應到提示文字；module 本身不含任何 l10n 字串，也不丟例外。
enum RedownloadOutcome {
  /// 檔案已下載並寫回書庫。
  succeeded,

  /// 這本書缺少遠端資訊（`remoteServerId` 或 `remoteDownloadUrl` 為 null）。
  notRemoteBook,

  /// `remoteServerId` 指向的站點已不存在。
  serverNotFound,

  /// 下載、升格或寫書庫任一步失敗；書庫中的這本書維持原狀。
  failed,
}

/// 這本書是否具備重新下載所需的遠端資訊。
///
/// 畫面在跳確認對話框**之前**用它判斷，維持「缺資訊就立刻提示」的既有
/// 行為；[redownloadBook] 也用同一個判斷，條件只有這一份。
bool isRedownloadable(Book book) =>
    book.remoteServerId != null && book.remoteDownloadUrl != null;

/// 把 [book] 重新下載到本機，成功後更新 `filePath`／`isDownloaded`
/// （不建立新的 Book 記錄）並標記全文索引。
///
/// 純 Dart：不接收 `BuildContext`，畫面中途離開不影響下載完成與寫庫。
/// 下載與升格沿用 [downloadToTempFile]／[promoteToPermanent]，兩者失敗時
/// 各自已清除暫存檔，這裡不再重複清理。
Future<RedownloadOutcome> redownloadBook({
  required Book book,
  required RemoteServerRepository remoteServerRepository,
  required LibraryRepository libraryRepository,
  required FullTextSearchSettingsRepository fullTextSearchSettingsRepository,
  required OpdsClient Function() createOpdsClient,
}) async {
  if (!isRedownloadable(book)) return RedownloadOutcome.notRemoteBook;
  final remoteServerId = book.remoteServerId!;
  final remoteDownloadUrl = book.remoteDownloadUrl!;

  try {
    RemoteServerProfile? server;
    for (final s in await remoteServerRepository.listServers()) {
      if (s.id == remoteServerId) {
        server = s;
        break;
      }
    }
    if (server == null) return RedownloadOutcome.serverNotFound;

    final password = await remoteServerRepository.loadPassword(remoteServerId);
    final client = createOpdsClient();

    final tempPath = await downloadToTempFile(
      client: client,
      server: server,
      acquisition: OpdsAcquisition(href: remoteDownloadUrl, format: book.format),
      format: book.format,
      password: password,
    );
    final permanentPath = await promoteToPermanent(tempPath);

    final updatedBook = book.copyWith(filePath: permanentPath, isDownloaded: true);
    await libraryRepository.updateBook(updatedBook);

    try {
      await fullTextSearchSettingsRepository.handleBookAvailable(updatedBook);
    } catch (_) {
      // 刻意靜默：索引為衍生資料，可日後由「重建索引」補上；檔案已下載並寫庫，
      // 不該因此讓使用者看到「重新下載失敗」。
    }
    return RedownloadOutcome.succeeded;
  } catch (_) {
    return RedownloadOutcome.failed;
  }
}
