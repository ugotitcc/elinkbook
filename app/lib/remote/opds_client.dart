import 'dart:io';

import 'opds_types.dart';
import 'remote_server_profile.dart';

/// 下載中途取消的輕量信號（epic-30-calibre-remote-library Issue 1，
/// spec.md「OPDS 瀏覽與下載」）：本專案僅有 `http` 套件、無 `dio`，故不
/// 採用 `dio` 的 `CancelToken` 型別，自訂一個語意等價的輕量取消信號。
class OpdsDownloadCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// 單一共用介面，涵蓋測試連線／目錄瀏覽／下載，是整個遠端書庫瀏覽＋
/// 下載＋站點管理 UX 唯一依賴的邊界（spec.md「OPDS 瀏覽與下載：
/// OpdsClient」，seam 已與使用者確認）。
abstract class OpdsClient {
  /// 內部實作應直接嘗試 [fetchFeed] 該站點根目錄並捕捉例外，成功回傳
  /// `true`、任何網路/認證/解析錯誤回傳 `false`（不需要細分錯誤類型，
  /// UI 統一顯示「連線失敗，請檢查網址/帳密/憑證設定」）。
  Future<bool> testConnection(RemoteServerProfile server, {String? password});

  /// [feedUrl] 為 `null` 時載入 [server.baseUrl]（站點根目錄）；非 `null`
  /// 時載入指定的分類/分頁 Feed（通常來自前一次呼叫回傳的
  /// [OpdsFeed.nextUrl]/[OpdsNavigationLink.href]）。回傳的
  /// [OpdsFeed] 內所有 URL 皆保證為絕對路徑。
  Future<OpdsFeed> fetchFeed(RemoteServerProfile server, {String? password, String? feedUrl});

  /// 下載 [acquisition] 指定的檔案到 [destinationPath]。[onProgress] 於
  /// 每個資料區塊到達時回呼 `(received, total)`，`total` 為 0 代表伺服器
  /// 未提供 Content-Length。[cancellationToken] 於下載中途被
  /// `cancel()` 時中斷連線並清除已寫入的部分檔案。
  Future<File> downloadBook(
    RemoteServerProfile server,
    OpdsAcquisition acquisition,
    String destinationPath, {
    String? password,
    void Function(int received, int total)? onProgress,
    OpdsDownloadCancellationToken? cancellationToken,
  });
}
