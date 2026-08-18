import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'opds_client.dart';
import 'remote_server_profile.dart';

/// OPDS 目錄縮圖的雙層快取（epic-30-calibre-remote-library Issue 5，
/// design.md「E-Ink 與後續優化」）：記憶體 LRU＋本機磁碟，減少使用者
/// 在同一瀏覽 session 或跨 App 啟動重複下載同一張縮圖。
abstract class RemoteThumbnailCache {
  Future<Uint8List> fetch(RemoteServerProfile server, String url, Map<String, String> headers);
}

/// [RemoteThumbnailCacheImpl] 的網路擷取函式型別，注入而非直接呼叫
/// [fetchThumbnailBytesOverHttp]——單元測試需要能替換成不觸碰真實網路
/// 的假函式（比照本 Epic 既有 `createOpdsClient`／`ComputeRemoteFingerprint`
/// 的注入先例），真實網路擷取路徑本身比照 `OpdsHttpClient` 既定範圍不做
/// 自動化測試。
typedef ThumbnailNetworkFetcher = Future<Uint8List> Function(
  RemoteServerProfile server,
  String url,
  Map<String, String> headers,
);

/// [ThumbnailNetworkFetcher] 的生產環境預設實作：透過 [createOpdsHttpClient]
/// 取得依 [server.allowInsecure] 決定是否放行憑證錯誤的 client，逾時比照
/// `OpdsHttpClient` 既有的 10 秒設定。
Future<Uint8List> fetchThumbnailBytesOverHttp(
  RemoteServerProfile server,
  String url,
  Map<String, String> headers,
) async {
  final client = createOpdsHttpClient(server);
  try {
    final response =
        await client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('縮圖下載失敗：HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    return response.bodyBytes;
  } finally {
    client.close();
  }
}

/// [RemoteThumbnailCache] 的真實實作。記憶體層用 `Map`（Dart 預設實作為
/// 插入順序穩定的 `LinkedHashMap`）的插入順序語意做 LRU——命中時移除後
/// 重新插入視為「最近使用」，超過 [memoryMaxSize] 時淘汰 `keys.first`
/// （最舊項目），比照 `pdf_thumbnail_cache.dart` 的 `PdfThumbnailCache`
/// 既有設計精神；鍵為縮圖 URL 字串（非頁碼整數），故非直接重用該類別、
/// 獨立實作。磁碟層以 URL 的 SHA-256 雜湊做檔名（URL 本身含斜線/問號等
/// 不適合直接當檔名的字元），落地於 [cacheDir]（呼叫端提供，生產環境
/// 由 `main.dart` 透過 `getApplicationCacheDirectory()` 取得——語意上是
/// 可被 OS 回收的快取，與 Issue 2/4 用 `getApplicationDocumentsDirectory()`
/// 的永久書籍檔案是不同目錄、不同生命週期保證）。
///
/// **已知取捨（刻意，非疏漏）**：同一個 URL 在第一次擷取完成前又被重複
/// `fetch()`（例如畫面因其他原因 `setState()` 重建、GridView 對同一張
/// 縮圖再次呼叫 `_buildThumbnail()`），兩次呼叫可能並行各自觸發一次真實
/// 網路請求——沒有做「同一個 URL 進行中的 Future 去重」。縮圖網格的請求
/// 量與重複機率低，最終兩次都會成功並各自寫入相同內容的磁碟快取，不是
/// 正確性問題，只是輕微浪費；為了避免這個低機率情境新增第三層快取
/// （in-flight Future 去重表）複雜度不划算。
class RemoteThumbnailCacheImpl implements RemoteThumbnailCache {
  RemoteThumbnailCacheImpl({
    required Directory cacheDir,
    this.memoryMaxSize = 100,
    ThumbnailNetworkFetcher fetchOverNetwork = fetchThumbnailBytesOverHttp,
  })  : _cacheDir = cacheDir,
        _fetchOverNetwork = fetchOverNetwork;

  final Directory _cacheDir;
  final int memoryMaxSize;
  final ThumbnailNetworkFetcher _fetchOverNetwork;
  final _memory = <String, Uint8List>{};

  Uint8List? _memoryGet(String key) {
    final value = _memory.remove(key);
    if (value == null) return null;
    _memory[key] = value;
    return value;
  }

  void _memoryPut(String key, Uint8List value) {
    _memory.remove(key);
    _memory[key] = value;
    if (_memory.length > memoryMaxSize) {
      _memory.remove(_memory.keys.first);
    }
  }

  String _diskKeyFor(String url) => sha256.convert(utf8.encode(url)).toString();

  @override
  Future<Uint8List> fetch(RemoteServerProfile server, String url, Map<String, String> headers) async {
    final memHit = _memoryGet(url);
    if (memHit != null) return memHit;

    final diskFile = File(p.join(_cacheDir.path, _diskKeyFor(url)));
    if (await diskFile.exists()) {
      final bytes = await diskFile.readAsBytes();
      _memoryPut(url, bytes);
      return bytes;
    }

    final bytes = await _fetchOverNetwork(server, url, headers);
    if (!await _cacheDir.exists()) await _cacheDir.create(recursive: true);
    await diskFile.writeAsBytes(bytes);
    _memoryPut(url, bytes);
    return bytes;
  }
}
