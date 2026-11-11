// foliate-js 詮釋資料探針（metadata-probe.js）回傳 JSON 的解析（epic-66 Issue 25）。
//
// Android 與 Windows 共用同一支探針、同一種 JSON 結構，解析邏輯只留這一份，
// 避免兩個平台的封面檢查再次分歧。原本在 android_epub_metadata.dart。

import 'dart:convert';
import 'dart:typed_data';

/// 解析探針回傳的 JSON 字串，轉換為詮釋資料 Map。
///
/// 當 `coverType` 非空且不以 `image/` 開頭時（例如 foliate `getCover()` 退回 XHTML 頁），
/// 拒收封面（`coverBytes` 為 `null`）；`coverType` 缺漏或空字串時維持相容解碼。
Map<String, Object?> mapProbeResult(String json) {
  final raw = jsonDecode(json) as Map<String, dynamic>;

  final coverType = raw['coverType'] as String?;
  final isRejectedCoverType =
      coverType != null && coverType.isNotEmpty && !coverType.startsWith('image/');

  Uint8List? coverBytes;
  final coverBase64 = raw['coverBase64'] as String?;
  if (!isRejectedCoverType && coverBase64 != null && coverBase64.isNotEmpty) {
    try {
      coverBytes = base64Decode(coverBase64);
    } catch (_) {
      coverBytes = null;
    }
  }

  return <String, Object?>{
    'title': raw['title'] as String?,
    'author': raw['author'] as String?,
    'identifier': raw['identifier'] as String?,
    'isFixedLayout': raw['isFixedLayout'] as bool? ?? false,
    'coverBytes': coverBytes,
    'coverType': coverType,
  };
}
