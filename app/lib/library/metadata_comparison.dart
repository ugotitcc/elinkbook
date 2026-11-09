// 圖書詮釋資料比對純函式（epic-66 Issue 12 Task 4）。

import 'dart:typed_data';

/// 規範化文字欄位：去除前後空白，若為空字串或 null 統一視為 null。
String? _normalizeText(Object? value) {
  if (value == null) return null;
  final str = value.toString().trim();
  return str.isEmpty ? null : str;
}

/// 判定是否有封面資料：非 null 且位元組長度大於 0。
bool _hasCover(Object? value) {
  if (value == null) return false;
  if (value is Uint8List) return value.isNotEmpty;
  if (value is List) return value.isNotEmpty;
  return false;
}

/// 比較 Readium 與 foliate-js 兩端解析的詮釋資料，回傳不一致的欄位清單。
///
/// 比對規則：
/// - `title`、`author`、`identifier`：去除前後空白後比對，兩邊皆為 null 或空字串視為相同；
/// - `isFixedLayout`：嚴格布林值相等；
/// - 封面：只比「有沒有封面」（位元組非 null 且長度大於 0），兩邊位元組內容不同是預期的。
List<String> diffBookMetadata(
  Map<String, Object?> readium,
  Map<String, Object?> foliate,
) {
  final diffs = <String>[];

  if (_normalizeText(readium['title']) != _normalizeText(foliate['title'])) {
    diffs.add('title');
  }

  if (_normalizeText(readium['author']) != _normalizeText(foliate['author'])) {
    diffs.add('author');
  }

  if (_normalizeText(readium['identifier']) != _normalizeText(foliate['identifier'])) {
    diffs.add('identifier');
  }

  final rFixed = (readium['isFixedLayout'] as bool?) ?? false;
  final fFixed = (foliate['isFixedLayout'] as bool?) ?? false;
  if (rFixed != fFixed) {
    diffs.add('isFixedLayout');
  }

  if (_hasCover(readium['coverBytes']) != _hasCover(foliate['coverBytes'])) {
    diffs.add('cover');
  }

  return diffs;
}
