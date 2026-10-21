// MDD 資源鍵轉換與型別（epic-63 Issue 6b Task 1）。
//
// 提供 WebView 請求網址轉換為 MDD 內部鍵值、副檔名對應 MIME 型別、
// 以及單一 MDD 資源二進位資料結構之純函式與常數。
import 'dart:typed_data';

import 'package:elinkbook/dictionary/mdx_link_policy.dart';

/// 單一 MDD 資源大小上限（8MB）。
const int kMdxResourceMaxBytes = 8 * 1024 * 1024;

/// MDD 抽出之資源二進位內容與 MIME 型別。
class MdxResource {
  const MdxResource({
    required this.bytes,
    required this.contentType,
  });

  /// 資源二進位資料。
  final Uint8List bytes;

  /// MIME 內容型別（例如 `image/png`）。
  final String contentType;
}

/// 將 WebView 送來的資源網址轉換為 MDD 內部搜尋鍵值。
///
/// MDD 索引內的鍵值多以 `\pic\a b.png` 儲存，部分字典檔不帶開頭反斜線（`pic\a b.png`）。
/// 因此在網址屬於 [kMdxBaseUrl] 且非空時，依序回傳帶開頭反斜線與不帶開頭反斜線之兩組鍵值。
///
/// 若網址不在 [kMdxBaseUrl] 底下、URL 百分比解碼失敗、或路徑為空，一律回傳空清單。
List<String> mddKeysForUrl(String url) {
  if (!url.startsWith(kMdxBaseUrl)) {
    return const [];
  }

  final uri = Uri.tryParse(url);
  if (uri == null) {
    return const [];
  }

  var rawPath = uri.path;
  if (rawPath.startsWith('/')) {
    rawPath = rawPath.substring(1);
  }
  if (rawPath.isEmpty) {
    return const [];
  }

  String decoded;
  try {
    decoded = Uri.decodeComponent(rawPath);
  } on Object {
    return const [];
  }

  if (decoded.isEmpty) {
    return const [];
  }

  final converted = decoded.replaceAll('/', r'\');
  return ['\\$converted', converted];
}

/// 依檔案鍵值之副檔名判斷支援的圖片 MIME 型別。
///
/// 副檔名不分大小寫，只認 spec 列的五種（`.jpg`／`.jpeg`、`.png`、`.gif`、`.webp`、`.svg`）。
/// 其餘格式或無副檔名回傳 `null`。
String? imageContentTypeForKey(String key) {
  final normalizedKey = key.replaceAll('/', r'\');
  final lastSep = normalizedKey.lastIndexOf(r'\');
  final lastDot = normalizedKey.lastIndexOf('.');

  if (lastDot == -1 || lastDot <= lastSep || lastDot == normalizedKey.length - 1) {
    return null;
  }

  final ext = normalizedKey.substring(lastDot).toLowerCase();
  switch (ext) {
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.png':
      return 'image/png';
    case '.gif':
      return 'image/gif';
    case '.webp':
      return 'image/webp';
    case '.svg':
      return 'image/svg+xml';
    default:
      return null;
  }
}
