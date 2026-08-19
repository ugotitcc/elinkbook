import 'dart:io';
import 'dart:typed_data';

import '../library/models/library_enums.dart';

/// 雲端匯入來源（Google Drive／OneDrive）瀏覽＋下載共用介面（spec.md
/// 「雲端瀏覽與下載：CloudStorageClient」），是整個雲端匯入瀏覽/下載 UX
/// 唯一依賴的邊界（seam 已與使用者確認）。`GoogleDriveBrowserScreen` 只
/// 認識這個介面，不知道底層是哪個 provider——Issue 4（OneDrive）新增
/// `OneDriveStorageClient` 實作後即可直接沿用同一套瀏覽畫面，不需要重新
/// 設計 UI（比照 `remote/opds_client.dart` 的 `OpdsClient`／
/// `RemoteCatalogScreen` 既有設計原則）。
abstract class CloudStorageClient {
  /// [folderId] 為 `null` 時列出雲端硬碟根目錄的內容。回傳清單只含資料夾
  /// 與 elinkBook 支援格式（EPUB/PDF/TXT/AZW3/CBZ/MD）的檔案——不支援格式
  /// 的檔案已被過濾掉，完全不會出現在清單內（spec.md「格式過濾」）。
  Future<CloudFolderListing> listFolder({String? folderId});

  /// 下載 [entry] 到 [destinationPath]。[onProgress] 於每個資料區塊到達時
  /// 回呼 `(received, total)`，`total` 為 0 代表伺服器未提供
  /// Content-Length。[cancellationToken] 於下載中途被 `cancel()` 時中斷
  /// 連線；下載失敗或被取消時，實作必須自行刪除 [destinationPath] 已寫入
  /// 的部分檔案，不留孤兒/半成品檔案（呼叫端不需要自己再判斷該路徑是否
  /// 還存在，比照 `remote/opds_client.dart` 的 `OpdsClient.downloadBook`
  /// 既定契約）。
  Future<File> downloadFile(
    CloudFileEntry entry,
    String destinationPath, {
    void Function(int received, int total)? onProgress,
    CloudDownloadCancellationToken? cancellationToken,
  });

  /// 取得 [thumbnailUrl] 指向的縮圖圖片位元組（部分 provider 的縮圖網址
  /// 需要與瀏覽/下載相同的授權標頭才能存取，不能直接交給
  /// `Image.network()`，故收斂為介面方法由各實作自行處理授權）。
  Future<Uint8List> fetchThumbnail(String thumbnailUrl);
}

/// 單一資料夾一次列出的結果。[truncated] 為 `true` 代表該資料夾檔案數量
/// 超過 1000 筆上限，[entries] 只包含前 1000 筆，UI 應顯示「這個資料夾
/// 檔案較多，僅顯示前 1000 筆」提示（spec.md「雲端瀏覽與下載」審查
/// Important #4 採納）。
class CloudFolderListing {
  final List<CloudFileEntry> entries;
  final bool truncated;

  const CloudFolderListing({this.entries = const [], this.truncated = false});
}

/// 一筆雲端硬碟項目（資料夾或檔案）。[format] 為 `null` 代表不支援的格式
/// （`listFolder()` 已預先過濾掉，理論上只會在 [isFolder] 為 `false` 的
/// 項目上被檢查）。
class CloudFileEntry {
  final String id;
  final String name;
  final bool isFolder;
  final BookFileFormat? format;
  final String? thumbnailUrl;
  final int? sizeBytes;

  const CloudFileEntry({
    required this.id,
    required this.name,
    required this.isFolder,
    this.format,
    this.thumbnailUrl,
    this.sizeBytes,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudFileEntry &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          isFolder == other.isFolder &&
          format == other.format &&
          thumbnailUrl == other.thumbnailUrl &&
          sizeBytes == other.sizeBytes;

  @override
  int get hashCode =>
      Object.hash(id, name, isFolder, format, thumbnailUrl, sizeBytes);
}

/// 下載中途取消的輕量信號（比照 `remote/opds_client.dart` 的
/// `OpdsDownloadCancellationToken`：本專案僅有 `http` 套件、無 `dio`，故
/// 不採用 `dio` 的 `CancelToken` 型別，自訂一個語意等價的輕量取消信號）。
class CloudDownloadCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// [CloudStorageClient] 的 access token 已過期且靜默續期失敗（例如
/// `GoogleDriveOAuthClient.ensureValidAccessToken()` 回傳 `null`）時拋出，
/// 呼叫端（`GoogleDriveBrowserScreen`）應提示使用者重新連結帳號，與其餘
/// 泛用網路/解析失敗（顯示通用「載入失敗」訊息）區分開來。
class CloudAuthRequiredException implements Exception {}

/// 依副檔名／MIME type 判斷雲端硬碟項目對應的 [BookFileFormat]，回傳
/// `null` 代表不支援的格式。EPUB/PDF/TXT 三種格式有廣泛認可的標準 MIME
/// type（跨 provider 通用，非 Google 專屬），AZW3/CBZ/MD 沒有普遍認可的
/// 標準 MIME type，一律退回副檔名判斷（spec.md「格式過濾」）。供
/// `GoogleDriveStorageClient` 與未來 Issue 4 的 `OneDriveStorageClient`
/// 共用，避免各自重寫一份判斷邏輯。
BookFileFormat? detectCloudFileFormat(String name, String? mimeType) {
  switch (mimeType) {
    case 'application/epub+zip':
      return BookFileFormat.epub;
    case 'application/pdf':
      return BookFileFormat.pdf;
    case 'text/plain':
      return BookFileFormat.txt;
  }
  final lower = name.toLowerCase();
  if (lower.endsWith('.epub')) return BookFileFormat.epub;
  if (lower.endsWith('.pdf')) return BookFileFormat.pdf;
  if (lower.endsWith('.txt')) return BookFileFormat.txt;
  if (lower.endsWith('.azw3')) return BookFileFormat.azw3;
  if (lower.endsWith('.cbz')) return BookFileFormat.cbz;
  if (lower.endsWith('.md')) return BookFileFormat.md;
  return null;
}
