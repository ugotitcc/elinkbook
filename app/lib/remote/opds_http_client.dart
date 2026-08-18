import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'opds_client.dart';
import 'opds_feed_parser.dart';
import 'opds_types.dart';
import 'remote_server_profile.dart';

/// [OpdsClient] 的真實 HTTP 實作（epic-30-calibre-remote-library
/// Issue 1，spec.md「OPDS 瀏覽與下載：OpdsClient」）。
///
/// **生命週期警告**：[_visitedFeedUrls] 是這個實例的內部狀態，語意上
/// 對應「一次瀏覽路徑」（spec.md「review-design.md Minor #1 採納」）。
/// 本 Issue 只透過 [testConnection] 使用（單次 `fetchFeed`，不涉及分頁
/// 鏈），所以 `main.dart` 建構一個全域共用實例是安全的；**Issue 2
/// 建構 `RemoteCatalogScreen` 時，每次使用者進入某個站點的瀏覽 session
/// 都必須建構一個全新的 `OpdsHttpClient()`，用完即捨棄**，不可沿用
/// `main.dart` 注入的全域實例——否則「已造訪過」的判定會錯誤地累積到
/// 跨 session、跨站點，導致合法的重新造訪被誤判為循環而提前結束分頁。
class OpdsHttpClient implements OpdsClient {
  OpdsHttpClient({OpdsFeedParser? parser}) : _parser = parser ?? const OpdsFeedParser();

  final OpdsFeedParser _parser;
  final Set<String> _visitedFeedUrls = {};

  static const _timeout = Duration(seconds: 10);

  /// [server.allowInsecure] 為 `true` 時，回傳的 [http.Client] 透過
  /// `badCertificateCallback` 放行憑證錯誤——**僅這一次呼叫端持有的
  /// client 物件生效**（呼叫端用畢即 `close()`），不會影響其他連線，
  /// 符合「不得全域關閉憑證驗證」的既定原則（Global Constraints）。
  http.Client _clientFor(RemoteServerProfile server) {
    if (!server.allowInsecure) return http.Client();
    final rawClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(rawClient);
  }

  @override
  Future<bool> testConnection(RemoteServerProfile server, {String? password}) async {
    try {
      await fetchFeed(server, password: password);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<OpdsFeed> fetchFeed(
    RemoteServerProfile server, {
    String? password,
    String? feedUrl,
  }) async {
    final url = feedUrl ?? server.baseUrl;
    _visitedFeedUrls.add(url);
    final client = _clientFor(server);
    try {
      final response = await client
          .get(Uri.parse(url), headers: buildOpdsAuthHeaders(server, password))
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('OPDS 伺服器回應 ${response.statusCode}', uri: Uri.parse(url));
      }
      final parsed = _parser.parse(response.body, Uri.parse(url));
      // 分頁循環防護：若 nextUrl 指回已造訪過的 URL（部分不規範伺服器的
      // 已知行為），視為分頁結束，不繼續請求，避免無限遞迴。
      final nextUrl = parsed.nextUrl != null && _visitedFeedUrls.contains(parsed.nextUrl)
          ? null
          : parsed.nextUrl;
      return OpdsFeed(
        title: parsed.title,
        nextUrl: nextUrl,
        prevUrl: parsed.prevUrl,
        navigationLinks: parsed.navigationLinks,
        entries: parsed.entries,
      );
    } finally {
      client.close();
    }
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
    final client = _clientFor(server);
    try {
      final request = http.Request('GET', Uri.parse(acquisition.href))
        ..headers.addAll(buildOpdsAuthHeaders(server, password));
      final streamedResponse = await client.send(request).timeout(_timeout);
      if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
        throw HttpException(
          '下載失敗，伺服器回應 ${streamedResponse.statusCode}',
          uri: Uri.parse(acquisition.href),
        );
      }
      final total = streamedResponse.contentLength ?? acquisition.sizeBytes ?? 0;
      final file = File(destinationPath);
      await file.create(recursive: true);
      final sink = file.openWrite();
      var received = 0;
      var cancelled = false;
      // 〔審查 review-plan-issue-1.md Finding 3 採納〕內層 try/finally
      // 確保 sink 在正常完成／使用者取消（break，非例外）／串流中途拋出
      // 例外（例如網路中斷 SocketException）三種情況下都會被關閉；外層
      // try/catch 專門處理「例外」這條路徑——串流寫入中途失敗時，內層
      // finally 已關閉 sink，這裡刪除殘留的不完整暫存檔後原樣重拋，避免
      // 留下孤兒檔案（spec.md「OPDS 瀏覽與下載」：「使用者取消...或下載
      // 失敗時立即清除暫存檔，不留孤兒檔案」，原設計僅涵蓋取消，未涵蓋
      // 網路中斷等真實下載失敗情境）。
      try {
        try {
          await for (final chunk in streamedResponse.stream) {
            if (cancellationToken?.isCancelled ?? false) {
              cancelled = true;
              break;
            }
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, total);
          }
        } finally {
          await sink.close();
        }
      } catch (_) {
        if (await file.exists()) await file.delete();
        rethrow;
      }
      if (cancelled) {
        if (await file.exists()) await file.delete();
        throw const _DownloadCancelledException();
      }
      return file;
    } finally {
      client.close();
    }
  }
}

class _DownloadCancelledException implements Exception {
  const _DownloadCancelledException();
  @override
  String toString() => '下載已取消';
}
