import 'dart:io';

import 'package:elinkbook/remote/opds_client.dart';
import 'package:elinkbook/remote/opds_types.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';

/// 供 widget test 使用的 [OpdsClient] 假實作（比照
/// `FakeCloudStorageClient`／`FakeLibraryRepository` 命名與設計慣例）。
class FakeOpdsClient implements OpdsClient {
  FakeOpdsClient({
    this.testConnectionResult = true,
    Map<String, OpdsFeed> feeds = const {},
    this.downloadError,
  }) : _feeds = Map.of(feeds);

  /// [testConnection] 的固定回傳值，測試可依情境覆寫為 `false` 模擬
  /// 連線失敗。
  bool testConnectionResult;

  /// key 為 `fetchFeed` 的 `feedUrl` 參數（`null` 代表根目錄，以
  /// `server.baseUrl` 為 key）。
  final Map<String, OpdsFeed> _feeds;

  /// 非 `null` 時 [downloadBook] 拋出這個例外，模擬下載失敗。
  Object? downloadError;

  final List<String> testConnectionCalls = [];
  // 〔審查 review-plan-issue-1.md Finding 1 採納〕與 testConnectionCalls
  // 同索引對應，供 Task 8 的測試驗證「編輯模式密碼欄位留空時，測試連線
  // 是否正確沿用既有密碼」。
  final List<String?> testConnectionPasswords = [];
  final List<String?> fetchFeedCalls = [];
  final List<String> downloadBookCalls = [];

  @override
  Future<bool> testConnection(RemoteServerProfile server, {String? password}) async {
    testConnectionCalls.add(server.id);
    testConnectionPasswords.add(password);
    return testConnectionResult;
  }

  @override
  Future<OpdsFeed> fetchFeed(RemoteServerProfile server, {String? password, String? feedUrl}) async {
    fetchFeedCalls.add(feedUrl);
    final key = feedUrl ?? server.baseUrl;
    final feed = _feeds[key];
    if (feed == null) {
      throw StateError('FakeOpdsClient: 沒有預先設定 $key 的 OpdsFeed');
    }
    return feed;
  }

  @override
  Future<File> downloadBook(
    RemoteServerProfile server,
    OpdsAcquisition acquisition,
    String destinationPath, {
    String? password,
    void Function(int received, int total)? onProgress,
    OpdsDownloadCancellationToken? cancellationToken,
  }) async {
    downloadBookCalls.add(acquisition.href);
    if (downloadError != null) throw downloadError!;
    onProgress?.call(100, 100);
    final file = File(destinationPath);
    await file.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    return file;
  }
}
