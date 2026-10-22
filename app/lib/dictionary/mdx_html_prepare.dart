// MDX 詞條 HTML 前處理（epic-63 Issue 6a Task 4 / Issue 6b Task 4）。
//
// 只做下列幾件事，順序固定：
// 1. `href="entry://#x"` → `href="#x"`（單雙引號、屬性大小寫皆可）。
// 2. `sound://` 連結移除 `href`、保留文字（Phase 1 不支援音訊）。
// 3. 移除會在使用者沒操作時自動跳轉或預先連線的標籤：
//    `<meta http-equiv="refresh">`、`<link rel="dns-prefetch|preconnect|
//    prefetch|prerender">`，以及 `<a ping>` 屬性（審查 I-7）。
// 4. 沒有 `<html>` 外殼時補上完整文件與必要的 meta。
//
// `<link>`／CSS 樣式內聯由 `mdx_css_inline.dart` 處理（Issue 6b Task 2）；
// 配色覆寫由 `mdx_theme_override.dart` 產生並透過 [prepareEntryHtml] 的 [overrideCss] 參數注入（Issue 6b Task 4）。

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

final RegExp _metaTagPattern = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
final RegExp _httpEquivRefresh = RegExp(
  r'''http-equiv\s*=\s*["']?\s*refresh\b''',
  caseSensitive: false,
);

final RegExp _linkTagPattern = RegExp(r'<link\b[^>]*>', caseSensitive: false);
final RegExp _relAttr = RegExp(
  r'''\brel\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))''',
  caseSensitive: false,
);
const Set<String> _preconnectRels = {
  'dns-prefetch',
  'preconnect',
  'prefetch',
  'prerender',
};

final RegExp _anchorTagPattern = RegExp(r'<a\b[^>]*>', caseSensitive: false);
final RegExp _pingAttr = RegExp(
  r'''\s+ping\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>"']+)''',
  caseSensitive: false,
);

final RegExp _htmlTag = RegExp(r'<html(?:\s|>)', caseSensitive: false);
final RegExp _headOpenTag = RegExp(r'<head[^>]*>', caseSensitive: false);
final RegExp _headCloseTag = RegExp(r'</head\s*>', caseSensitive: false);
final RegExp _bodyOpenTag = RegExp(r'<body(?:\s|>|$)', caseSensitive: false);
final RegExp _htmlOpenTag = RegExp(r'<html[^>]*>', caseSensitive: false);
final RegExp _charsetMeta = RegExp(
  r'<meta[^>]+charset\s*=',
  caseSensitive: false,
);

/// 把 MDX 詞條 HTML 整理成可直接放進 WebView 的文件。
///
/// 輸入可以是片段或完整文件；輸出一定是完整文件。空字串也會得到有效的
/// 空文件，呼叫端不必特判。
///
/// 若提供 [overrideCss]，會以 `<style>` 標籤注入至 `<head>` 尾端（在字典
/// 自身樣式之後），作為深色與 E-Ink 模式的配色覆寫。
String prepareEntryHtml(String html, {String? overrideCss}) {
  var out = html.replaceAllMapped(
    _entryFragmentHref,
    (match) =>
        '${match.group(1)}${match.group(2)}#${match.group(3)}'
        '${match.group(2)}',
  );

  // 連同前面的空白一起移除，避免留下 `<a  >`。
  out = out.replaceAll(_soundHref, '');

  out = _stripAutoNavigation(out);

  if (!_htmlTag.hasMatch(out)) {
    final styleTag =
        overrideCss != null ? '<style>$overrideCss</style>' : '';
    return '<!DOCTYPE html><html><head>$_metaTags$styleTag</head>'
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

  if (overrideCss != null) {
    final styleTag = '<style>$overrideCss</style>';
    final headClose = _headCloseTag.firstMatch(out);
    if (headClose != null) {
      out = out.replaceRange(headClose.start, headClose.start, styleTag);
    } else {
      final headOpen = _headOpenTag.firstMatch(out);
      if (headOpen != null) {
        final bodyOpen = _bodyOpenTag.firstMatch(out);
        if (bodyOpen != null) {
          out = out.replaceRange(
            bodyOpen.start,
            bodyOpen.start,
            '$styleTag</head>',
          );
        } else {
          out = '$out$styleTag</head>';
        }
      } else {
        final htmlTag = _htmlOpenTag.firstMatch(out);
        final insertAt = htmlTag?.end ?? 0;
        out = out.replaceRange(insertAt, insertAt, '<head>$styleTag</head>');
      }
    }
  }

  return out;
}

/// 移除自動跳轉與預先連線的標籤（WebView 設定與請求攔截之外的第二道防線）。
String _stripAutoNavigation(String html) {
  var out = html.replaceAllMapped(
    _metaTagPattern,
    (match) => _httpEquivRefresh.hasMatch(match.group(0)!) ? '' : match.group(0)!,
  );
  out = out.replaceAllMapped(_linkTagPattern, (match) {
    final tag = match.group(0)!;
    final rel = _relAttr.firstMatch(tag);
    if (rel == null) return tag;
    final value = rel.group(1) ?? rel.group(2) ?? rel.group(3) ?? '';
    final tokens = value.toLowerCase().split(RegExp(r'\s+'));
    return tokens.any(_preconnectRels.contains) ? '' : tag;
  });
  return out.replaceAllMapped(
    _anchorTagPattern,
    (match) => match.group(0)!.replaceAll(_pingAttr, ''),
  );
}
