import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore_for_file: use_null_aware_elements  // 此 lint 對 map literal 的 if-in 運算式產生誤判，null-aware `?` 不支援 map literal
import 'package:http/http.dart' as http;

import 'cloud_storage_client.dart';
import 'cloud_auth_classifier.dart';
import 'google_drive_oauth_client.dart';

/// [CloudStorageClient] 的 Google Drive API v3 實作（spec.md「雲端瀏覽與
/// 下載」）：直接呼叫 REST API（`https://www.googleapis.com/drive/v3/`），
/// 不使用官方 SDK（本專案其餘雲端整合皆是直接呼叫 REST API，比照
/// `OpdsHttpClient`／`GoogleDriveOAuthClient` 既有慣例）。每次呼叫皆先
/// 經 [GoogleDriveOAuthClient.ensureValidAccessToken] 取得（必要時靜默
/// 續期後的）access token，`null` 時拋出 [CloudAuthRequiredException]。
/// API 回 401 同樣拋出 [CloudAuthRequiredException]（見 `cloud_auth_classifier.dart`）。
class GoogleDriveStorageClient implements CloudStorageClient {
  GoogleDriveStorageClient({
    required GoogleDriveOAuthClient oauthClient,
    http.Client? httpClient,
  })  : _oauthClient = oauthClient,
        _httpClient = httpClient ?? http.Client();

  final GoogleDriveOAuthClient _oauthClient;
  final http.Client _httpClient;

  static const _filesEndpoint = 'https://www.googleapis.com/drive/v3/files';
  static const _maxEntries = 1000;

  @override
  Future<CloudFolderListing> listFolder({String? folderId}) async {
    final token = await _oauthClient.ensureValidAccessToken();
    if (token == null) throw CloudAuthRequiredException();

    final parent = folderId ?? 'root';
    // 伺服器端粗篩：資料夾恆納入（供逐層導覽）；EPUB/PDF/TXT 有廣泛認可
    // 的標準 MIME type，直接比對；AZW3/CBZ/MD 沒有標準 MIME type，用
    // name contains 先做粗略篩選縮小結果集（Drive API 的 `contains` 是
    // 子字串比對、非嚴格副檔名比對，可能有極少數誤判，例如
    // `notes.mdx`），精確判斷交給 detectCloudFileFormat() 做最終過濾
    // （spec.md「格式過濾」：伺服器端 MIME type 過濾 EPUB/PDF/TXT ＋
    // 用戶端副檔名過濾 AZW3/CBZ/MD）。
    final query = "'$parent' in parents and trashed = false and ("
        "mimeType = 'application/vnd.google-apps.folder' or "
        "mimeType = 'application/epub+zip' or "
        "mimeType = 'application/pdf' or "
        "mimeType = 'text/plain' or "
        "name contains '.azw3' or "
        "name contains '.cbz' or "
        "name contains '.md')";

    final entries = <CloudFileEntry>[];
    String? pageToken;
    var truncated = false;
    do {
      final uri = Uri.parse(_filesEndpoint).replace(queryParameters: {
        'q': query,
        'fields': 'nextPageToken,files(id,name,mimeType,thumbnailLink,size)',
        'pageSize': '1000',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final response =
          await _httpClient.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode != 200) {
        throwCloudApiStatusError('Google Drive 目錄讀取失敗', response.statusCode);
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final files = json['files'] as List<dynamic>? ?? const [];
      for (final raw in files) {
        final file = raw as Map<String, dynamic>;
        final mimeType = file['mimeType'] as String?;
        final name = file['name'] as String? ?? '';
        final isFolder = mimeType == 'application/vnd.google-apps.folder';
        final format = isFolder ? null : detectCloudFileFormat(name, mimeType);
        // 非資料夾且格式判斷不通過：伺服器端粗篩的誤判，精確過濾掉、不
        // 回傳給呼叫端（見上方 query 註解）。
        if (!isFolder && format == null) continue;
        entries.add(CloudFileEntry(
          id: file['id'] as String,
          name: name,
          isFolder: isFolder,
          format: format,
          thumbnailUrl: file['thumbnailLink'] as String?,
          sizeBytes:
              file['size'] != null ? int.tryParse(file['size'] as String) : null,
        ));
        if (entries.length >= _maxEntries) {
          truncated = true;
          break;
        }
      }
      pageToken = truncated ? null : json['nextPageToken'] as String?;
    } while (pageToken != null);

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
      final uri = Uri.parse('$_filesEndpoint/${entry.id}')
          .replace(queryParameters: {'alt': 'media'});
      final request = http.Request('GET', uri)
        ..headers['Authorization'] = 'Bearer $token';
      final response = await _httpClient.send(request);
      if (response.statusCode != 200) {
        throwCloudApiStatusError('Google Drive 下載失敗', response.statusCode);
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
      // 刪除仍被開啟的檔案），不留孤兒/半成品檔案。
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
