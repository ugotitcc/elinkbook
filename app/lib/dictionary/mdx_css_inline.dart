// app/lib/dictionary/mdx_css_inline.dart
import 'mdx_companion_files.dart';

final _styleTagPattern = RegExp(
  r'(<style\b[^>]*>)([\s\S]*?)(</style>)',
  caseSensitive: false,
);

final _importRulePattern = RegExp(
  r'@import\b[^;{}<]*;?\s*',
  caseSensitive: false,
);

final _closingStylePattern = RegExp(r'</style', caseSensitive: false);

/// 移除 CSS 內容中的 `@import` 規則。
String _stripImportRules(String css) =>
    css.replaceAll(_importRulePattern, '');

/// 將 HTML 中引用的外部 CSS 依檔名內嵌為 `<style>` 標籤，
/// 或在找不到對應檔案時將 `<link>` 移除。
///
/// 規格：
/// 1. 僅處理副檔名為 `.css` 的 `<link>` 標籤；非 `.css` 標籤（如圖示）原樣保留。
/// 2. 比對一律以最後路徑區段的檔名（小寫、去除查詢字串與錨點）為準。
/// 3. 若 [cssByLowerName] 有對應內容，轉為 `<style>...</style>`，並移除 `@import`、
///    轉義 `</style`；若無對應檔案則直接移除該 `<link>`。
/// 4. 詞條原有的 `<style>` 區塊內的 `@import` 亦一併移除。
String inlineLinkedCss(String html, Map<String, String> cssByLowerName) {
  // 1. 詞條自己的 <style> 區塊：移除 @import
  var result = html.replaceAllMapped(_styleTagPattern, (match) {
    final open = match.group(1)!;
    final content = match.group(2)!;
    final close = match.group(3)!;
    return '$open${_stripImportRules(content)}$close';
  });

  // 2. <link> 標籤：只處理 .css 結尾者；依檔名內嵌或移除
  result = result.replaceAllMapped(linkTagPattern, (match) {
    final tag = match.group(0)!;
    final hrefMatch = hrefAttrPattern.firstMatch(tag);
    if (hrefMatch == null) return tag;

    final rawHref =
        hrefMatch.group(1) ?? hrefMatch.group(2) ?? hrefMatch.group(3) ?? '';
    final fileName = extractFileNameFromHref(rawHref);
    if (!fileName.endsWith('.css')) return tag;

    final cssContent = cssByLowerName[fileName];
    if (cssContent == null) return '';

    final cleanCss = _stripImportRules(cssContent)
        .replaceAll(_closingStylePattern, r'<\/style');
    return '<style>$cleanCss</style>';
  });

  return result;
}
