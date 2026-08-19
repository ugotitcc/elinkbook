import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../library/models/library_enums.dart';
import 'opds_client.dart';
import 'opds_types.dart';
import 'remote_server_profile.dart';

/// 把一筆 OPDS acquisition 下載到 App 暫存目錄（epic-30-calibre-remote-library
/// Issue 6，`docs/research/architecture-review-library-remote-screens.md`
/// 候選 1：`LibraryScreen._handleRedownload()`／`RemoteCatalogScreen`
/// `_downloadOne()` 原本各自重複實作同一段邏輯，此處收斂為共用深模組）。
///
/// **不含例外清理**：[OpdsClient.downloadBook]（`OpdsHttpClient` 真實
/// 實作，見 `opds_http_client.dart`）已確認在下載失敗／使用者取消時會
/// 自行刪除目的檔案，這裡重複清理是死碼，故意不做。
Future<String> downloadToTempFile({
  required OpdsClient client,
  required RemoteServerProfile server,
  required OpdsAcquisition acquisition,
  required BookFileFormat format,
  String? password,
  void Function(int received, int total)? onProgress,
  OpdsDownloadCancellationToken? cancellationToken,
}) async {
  final tempDir = await getTemporaryDirectory();
  final downloadDir = Directory(p.join(tempDir.path, 'remote_download_temp'));
  if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
  final fileName = '${const Uuid().v4()}.${fileExtensionFor(format)}';
  final tempPath = p.join(downloadDir.path, fileName);

  await client.downloadBook(
    server,
    acquisition,
    tempPath,
    password: password,
    onProgress: onProgress,
    cancellationToken: cancellationToken,
  );

  return tempPath;
}

/// 把 [tempPath] 指向的暫存檔複製到 App 永久文件目錄的 `remote_books/`
/// 子目錄，成功後刪除暫存檔，回傳永久檔案的絕對路徑。永久檔名沿用暫存
/// 檔名（[p.basename]），與原本兩份實作「temp 檔名與 permanent 檔名相同」
/// 的既有行為一致。
///
/// 任何例外皆確保不留孤兒/半成品檔案，呼叫端不需要自己再判斷 `tempPath`
/// 是否還存在。區分兩種失敗窗口分開處理（**〔審查 review-plan-issue-6.md
/// Finding 3 部分採納，理由見下方〕**）：
/// - `copy()` 本身失敗（例如磁碟空間不足）：`permanentPath` 可能是部分
///   寫入的殘檔，清掉；`tempPath` 原封不動保留（來源檔案本身沒問題）。
/// - `copy()` 已成功、只有隨後的 `delete(tempPath)` 失敗：此時
///   `permanentPath` 是一份完整有效的檔案，**絕不能清掉**——審查原始建議
///   是「catch 區塊一併清理 permanentPath」，但那個寫法沒有區分這兩種
///   失敗窗口，會在「複製已成功、只是刪暫存檔失敗」這個情境下誤刪一份
///   已經下載成功的書籍檔案，逼使用者重新下載一次，比留一個孤兒暫存檔
///   （`remote_download_temp/` 本身是 OS 可回收的暫存語意，見既有
///   `getTemporaryDirectory()` 慣例）更糟——故僅在 `copied == false`
///   （複製本身失敗）時才清 `permanentPath`。
Future<String> promoteToPermanent(String tempPath) async {
  final fileName = p.basename(tempPath);
  final docsDir = await getApplicationDocumentsDirectory();
  final permanentDir = Directory(p.join(docsDir.path, 'remote_books'));
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
