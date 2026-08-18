import 'dart:convert';
import 'dart:typed_data';

import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/remote_thumbnail_cache.dart';

/// 供 widget test 使用的 [RemoteThumbnailCache] 假實作，避免測試環境
/// 觸碰真實網路／磁碟 I/O（比照本 Epic 既有 `FakeOpdsClient` 命名與
/// 設計慣例）。預設回傳一張最小合法的 1x1 透明 PNG（讓 `Image.memory()`
/// 能成功解碼、不觸發 `errorBuilder`）——沿用 `library_screen_test.dart`
/// 既有測試（`Key('cover.png')` 附近）已驗證可用的同一組 base64 位元組，
/// 不重新手key一份新的 PNG 二進位內容以避免自行手誤產生無效檔案，
/// [error] 非 `null` 時改為拋出例外，供測試驗證錯誤狀態呈現。
class FakeRemoteThumbnailCache implements RemoteThumbnailCache {
  FakeRemoteThumbnailCache({this.error});

  final Object? error;
  final List<String> fetchCalls = [];

  static final Uint8List minimalPngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
    '42YAAAAASUVORK5CYII=',
  );

  @override
  Future<Uint8List> fetch(RemoteServerProfile server, String url, Map<String, String> headers) async {
    fetchCalls.add(url);
    if (error != null) throw error!;
    return minimalPngBytes;
  }
}
