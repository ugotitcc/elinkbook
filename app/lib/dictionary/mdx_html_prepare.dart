// MDX 詞條 HTML 前處理（epic-63 Issue 6a Task 4）。
//
// 只做三件事，順序固定：
// 1. `href="entry://#x"` → `href="#x"`（單雙引號、屬性大小寫皆可）。
// 2. `sound://` 連結移除 `href`、保留文字（Phase 1 不支援音訊）。
// 3. 沒有 `<html>` 外殼時補上完整文件與必要的 meta。
//
// 刻意不處理 `<link>`／CSS／配色：那些屬於 Issue 6b。

const String _metaTags =
    '<meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">';

final RegExp _entryFragmentHref = RegExp(
  r'''(href\s*=\s*)(["'])entry://#([^"']*)\2''',
  caseSensitive: false,
);

final RegExp _soundHref = RegExp(
  r'''\s+href\s*=\s*(["'])sound://[^"']*\1''',
  caseSensitive: false,
);

final RegExp _htmlTag = RegExp(r'<html(?:\s|>)', caseSensitive: false);
final RegExp _headOpenTag = RegExp(r'<head[^>]*>', caseSensitive: false);
final RegExp _htmlOpenTag = RegExp(r'<html[^>]*>', caseSensitive: false);
final RegExp _charsetMeta = RegExp(
  r'<meta[^>]+charset\s*=',
  caseSensitive: false,
);

/// 把 MDX 詞條 HTML 整理成可直接放進 WebView 的文件。
///
/// 輸入可以是片段或完整文件；輸出一定是完整文件。空字串也會得到有效的
/// 空文件，呼叫端不必特判。
String prepareEntryHtml(String html) {
  var out = html.replaceAllMapped(
    _entryFragmentHref,
    (match) =>
        '${match.group(1)}${match.group(2)}#${match.group(3)}'
        '${match.group(2)}',
  );

  // 連同前面的空白一起移除，避免留下 `<a  >`。
  out = out.replaceAll(_soundHref, '');

  if (!_htmlTag.hasMatch(out)) {
    return '<!DOCTYPE html><html><head>$_metaTags</head>'
        '<body>$out</body></html>';
  }

  // 已經是完整文件：內容不動，只在缺少 charset meta 時補進 head。
  if (!_charsetMeta.hasMatch(out)) {
    final head = _headOpenTag.firstMatch(out);
    if (head != null) {
      out = out.replaceRange(head.end, head.end, _metaTags);
    } else {
      final htmlTag = _htmlOpenTag.firstMatch(out);
      final insertAt = htmlTag?.end ?? 0;
      out = out.replaceRange(insertAt, insertAt, '<head>$_metaTags</head>');
    }
  }
  return out;
}
