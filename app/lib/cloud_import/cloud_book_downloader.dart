import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../remote/opds_client.dart' show fileExtensionFor;
import 'cloud_storage_client.dart';

/// 把一筆雲端硬碟項目下載到 App 暫存目錄（epic-29-cloud-import Issue 3，
/// spec.md「暫存於專屬子目錄，UUID 命名，非平行下載」）。**不含例外
/// 清理**：[CloudStorageClient.downloadFile] 已依介面契約在下載失敗／
/// 使用者取消時自行刪除目的檔案，這裡重複清理是死碼，故意不做（比照
/// `remote/remote_book_downloader.dart` 的 `downloadToTempFile()` 既定
/// 設計）。
Future<String> downloadCloudFileToTempFile({
  required CloudStorageClient client,
  required CloudFileEntry entry,
  void Function(int received, int total)? onProgress,
  CloudDownloadCancellationToken? cancellationToken,
}) async {
  final tempDir = await getTemporaryDirectory();
  final downloadDir =
      Directory(p.join(tempDir.path, 'cloud_import_download_temp'));
  if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
  final fileName = '${const Uuid().v4()}.${fileExtensionFor(entry.format!)}';
  final tempPath = p.join(downloadDir.path, fileName);

  await client.downloadFile(
    entry,
    tempPath,
    onProgress: onProgress,
    cancellationToken: cancellationToken,
  );

  return tempPath;
}

/// 把 [tempPath] 指向的暫存檔複製到 App 永久文件目錄的
/// `cloud_import_books/` 子目錄（與 `epic-30-calibre-remote-library` 的
/// `remote_books/` 目錄語意上完全獨立——`CONTEXT.md`「雲端匯入來源帳號」
/// 與「遠端書庫」是兩個不同概念，不共用落地目錄），成功後刪除暫存檔，
/// 回傳永久檔案的絕對路徑。任何例外皆確保不留孤兒/半成品檔案，比照
/// `remote/remote_book_downloader.dart` 的 `promoteToPermanent()` 既定
/// 設計（區分「複製本身失敗」與「複製成功、只有刪暫存檔失敗」兩種失敗
/// 窗口，避免誤刪已下載成功的檔案）。
Future<String> promoteCloudFileToPermanent(String tempPath) async {
  final fileName = p.basename(tempPath);
  final docsDir = await getApplicationDocumentsDirectory();
  final permanentDir = Directory(p.join(docsDir.path, 'cloud_import_books'));
  if (!await permanentDir.exists()) await permanentDir.create(recursive: true);
  final permanentPath = p.join(permanentDir.path, fileName);
  final tempFile = File(tempPath);
  var copied = false;
  try {
    await tempFile.copy(permanentPath);
    copied = true;
    await tempFile.delete();
    return permanentPath;
  } catch (_) {
    if (!copied) {
      final leftoverPerm = File(permanentPath);
      if (await leftoverPerm.exists()) await leftoverPerm.delete();
    }
    final leftoverTemp = File(tempPath);
    if (await leftoverTemp.exists()) await leftoverTemp.delete();
    rethrow;
  }
}
