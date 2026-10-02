import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cloud_storage_client.dart';
import 'cloud_auth_classifier.dart';
import 'onedrive_oauth_client.dart';

/// [CloudStorageClient] 的 Microsoft Graph API v1.0 實作（`issues.md`
/// Issue 4，結構比照 Issue 3 已審查通過的 `GoogleDriveStorageClient`）：
/// 直接呼叫 REST API（`https://graph.microsoft.com/v1.0/me/drive/`），
/// 不使用官方 SDK。每次呼叫皆先經 [OneDriveOAuthClient.ensureValidAccessToken]
/// 取得（必要時靜默續期後的）access token，`null` 時拋出
/// [CloudAuthRequiredException]。
///
/// **格式過濾刻意不使用 Graph OData `$filter`**（例如
/// `endswith(name,'.epub')`）在伺服器端精確篩選——雖然 Graph OData 語法
/// 理論上支援，但無法在實作當下存取真實 Graph API 驗證複合 filter
/// 表達式實際可用，為避免在未經驗證的 API 語法上下注，改採與
/// `GoogleDriveStorageClient` 相同的保守策略：取回資料夾內全部項目，
/// 100% 交給用戶端的 `detectCloudFileFormat()` 過濾。
class OneDriveStorageClient implements CloudStorageClient {
  OneDriveStorageClient({
    required OneDriveOAuthClient oauthClient,
    http.Client? httpClient,
  })  : _oauthClient = oauthClient,
        _httpClient = httpClient ?? http.Client();

  final OneDriveOAuthClient _oauthClient;
  final http.Client _httpClient;

  static const _rootChildrenEndpoint =
      'https://graph.microsoft.com/v1.0/me/drive/root/children';
  static const _itemsEndpoint = 'https://graph.microsoft.com/v1.0/me/drive/items';
  static const _maxEntries = 1000;

  @override
  Future<CloudFolderListing> listFolder({String? folderId}) async {
    final token = await _oauthClient.ensureValidAccessToken();
    if (token == null) throw CloudAuthRequiredException();

    final initialUri = Uri.parse(
      folderId == null ? _rootChildrenEndpoint : '$_itemsEndpoint/$folderId/children',
    ).replace(queryParameters: {
      '\$select': 'id,name,size,file,folder',
      '\$expand': 'thumbnails(\$select=medium)',
      '\$top': '999',
    });

    final entries = <CloudFileEntry>[];
    Uri? nextUri = initialUri;
    var truncated = false;
    do {
      final response =
          await _httpClient.get(nextUri!, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode != 200) {
        throwCloudApiStatusError('OneDrive 目錄讀取失敗', response.statusCode);
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final items = json['value'] as List<dynamic>? ?? const [];
      for (final raw in items) {
        final item = raw as Map<String, dynamic>;
        final name = item['name'] as String? ?? '';
        final isFolder = item['folder'] != null;
        final mimeType = (item['file'] as Map<String, dynamic>?)?['mimeType'] as String?;
        final format = isFolder ? null : detectCloudFileFormat(name, mimeType);
        // 非資料夾且格式判斷不通過：不回傳給呼叫端（比照 Google Drive
        // 既有行為，見上方類別文件說明）。
        if (!isFolder && format == null) continue;
        final thumbnails = item['thumbnails'] as List<dynamic>?;
        String? thumbnailUrl;
        if (thumbnails != null && thumbnails.isNotEmpty) {
          final first = thumbnails.first as Map<String, dynamic>;
          thumbnailUrl = (first['medium'] as Map<String, dynamic>?)?['url'] as String?;
        }
        entries.add(CloudFileEntry(
          id: item['id'] as String,
          name: name,
          isFolder: isFolder,
          format: format,
          thumbnailUrl: thumbnailUrl,
          sizeBytes: item['size'] as int?,
        ));
        if (entries.length >= _maxEntries) {
          truncated = true;
          break;
        }
      }
      // Graph API 的分頁機制是完整絕對 URL 的 @odata.nextLink（不像
      // Google Drive 是不透明的 pageToken），下一頁直接 GET 這個 URL 即可。
      final nextLink = json['@odata.nextLink'] as String?;
      nextUri = truncated ? null : (nextLink != null ? Uri.parse(nextLink) : null);
    } while (nextUri != null);

    return CloudFolderListing(entries: entries, truncated: truncated);
  }

  @override
  Future<File> downloadFile(
    CloudFileEntry entry,
    String destinationPath, {
    void Function(int received, int total)? onProgress,
    CloudDownloadCancellationToken? cancellationToken,
  }) async {
    final token = await _oauthClient.ensureValidAccessToken();
    if (token == null) throw CloudAuthRequiredException();

    final file = File(destinationPath);
    IOSink? sink;
    try {
      final uri = Uri.parse('$_itemsEndpoint/${entry.id}/content');
      final request = http.Request('GET', uri)
        ..headers['Authorization'] = 'Bearer $token';
      final response = await _httpClient.send(request);
      if (response.statusCode != 200) {
        throwCloudApiStatusError('OneDrive 下載失敗', response.statusCode);
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      sink = file.openWrite();
      await for (final chunk in response.stream) {
        if (cancellationToken?.isCancelled ?? false) {
          throw Exception('下載已取消');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.close();
      return file;
    } catch (e) {
      // 無論失敗原因為何，皆確保檔案控制代碼先關閉再刪除（Windows 上無法
      // 刪除仍被開啟的檔案），比照 GoogleDriveStorageClient 既有做法。
      await sink?.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  @override
  Future<Uint8List> fetchThumbnail(String thumbnailUrl) async {
    final token = await _oauthClient.ensureValidAccessToken();
    if (token == null) throw CloudAuthRequiredException();
    final response = await _httpClient.get(
      Uri.parse(thumbnailUrl),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throwCloudApiStatusError('縮圖載入失敗', response.statusCode);
    }
    return response.bodyBytes;
  }
}
