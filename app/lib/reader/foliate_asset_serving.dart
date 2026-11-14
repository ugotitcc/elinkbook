import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'foliate_native_bridge.dart' show loadAndroidAsset;

/// 「Foliate 資源供應」的回應純值（見 `CONTEXT.md`）。
///
/// 只含 MIME 本身、不含 charset（`WebResourceResponse.contentEncoding`
/// 預設即為 utf-8）。
class FoliateAssetResponse {
  /// 200 或 404。
  final int statusCode;
  final String contentType;
  final Uint8List data;

  const FoliateAssetResponse({
    required this.statusCode,
    required this.contentType,
    required this.data,
  });
}

const _foliateAssetsPrefix = '/assets/foliate/';

/// 依副檔名推導 MIME。只有 `.js`、`.css` 需要區分；其餘（含 `.html`）維持
/// 既有的 `text/html`，不在這次擴充別的型別。
String _contentTypeOf(String path) {
  if (path.endsWith('.js')) return 'text/javascript';
  if (path.endsWith('.css')) return 'text/css';
  return 'text/html';
}

/// 把 `/assets/foliate/**` 的請求路徑變成明確回應。
///
/// 閱讀器、全文索引器、Android／Windows EPUB 探針四個 WebView 使用者共用；
/// 各自只保留把回應轉成自家 `WebResourceResponse` 的薄 adapter
/// （[FoliateAssetResponseX.toWebResourceResponse]）。
///
/// - [path] 不在 `/assets/foliate/` 底下 → 回 `null`（不是本 module 的事，
///   字型、`/book/` 等路由由呼叫端自己處理）。
/// - 在底下但讀不到（找不到或讀取拋例外）→ 回明確 404 與空內容，
///   不回 `null`，避免 WebView 走預設行為去連網（與字典 WebView「永不連網」
///   原則一致）。
///
/// [loadAsset] 預設為 [loadAndroidAsset]（Windows 在其內部轉給
/// `loadWindowsFoliateAsset`）；測試可注入替身。
Future<FoliateAssetResponse?> serveFoliateAsset(
  String path, {
  Future<Uint8List?> Function(String relativePath)? loadAsset,
}) async {
  if (!path.startsWith(_foliateAssetsPrefix)) return null;
  final relative = 'foliate/${path.substring(_foliateAssetsPrefix.length)}';
  Uint8List? bytes;
  try {
    bytes = await (loadAsset ?? loadAndroidAsset)(relative);
  } catch (_) {
    bytes = null;
  }
  if (bytes == null) {
    return FoliateAssetResponse(
      statusCode: 404,
      contentType: 'text/plain',
      data: Uint8List(0),
    );
  }
  return FoliateAssetResponse(
    statusCode: 200,
    contentType: _contentTypeOf(path),
    data: bytes,
  );
}

/// 四個 WebView 使用者共用的薄 adapter。
extension FoliateAssetResponseX on FoliateAssetResponse {
  WebResourceResponse toWebResourceResponse() {
    return WebResourceResponse(
      statusCode: statusCode,
      reasonPhrase: statusCode == 200 ? 'OK' : 'Not Found',
      contentType: contentType,
      data: data,
    );
  }
}
