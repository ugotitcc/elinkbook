// app/lib/library/md_epub_synthesizer.dart
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:markdown/markdown.dart' as md;

import 'content_uri_reader.dart';
import 'epub_container_builder.dart';
import 'md_frontmatter.dart';
import 'md_toc_builder.dart';

/// Markdown 檔案解碼後找不到任何非空白內容時拋出——沒有內容的書本質上
/// 無法開啟，呼叫端（book_import_service_impl.dart）應中止匯入、不建立
/// Book 記錄，比照 `EmptyTxtException`（epic-11 Issue 4）既有處置慣例。
class EmptyMdException implements Exception {
  final String message;
  const EmptyMdException(this.message);
  @override
  String toString() => 'EmptyMdException: $message';
}

class MdSynthesisResult {
  /// 合成後的 EPUB 壓縮檔完整位元組內容，供呼叫端落地為 `Book.filePath`
  /// 指向的衍生檔案（**檔名副檔名須維持 `.md`**，比照 Issue 4 TXT 的既有
  /// 限制理由：`BookFormat.md` 的分派依 `Book.filePath` 副檔名判斷）。
  final Uint8List epubBytes;

  /// Frontmatter 解析結果，供呼叫端決定書名/作者/封面（`null` 代表該欄位
  /// 未於 Frontmatter 指定，呼叫端應使用既有退回機制）。
  final String? frontmatterTitle;
  final String? frontmatterAuthor;
  final Uint8List? frontmatterCoverBytes;

  const MdSynthesisResult({
    required this.epubBytes,
    this.frontmatterTitle,
    this.frontmatterAuthor,
    this.frontmatterCoverBytes,
  });
}

/// 強制程式碼區塊與表格在直排模式下維持橫排、可橫向捲動（spec.md
/// 「TXT／Markdown 合成書籍結構」對 MD 的既有要求）——寫在每個章節 XHTML
/// 自己的 `<head>`，不依賴本專案既有的全域 `buildOverrideCss()` 機制
/// （後者由使用者版面設定驅動，此處是格式本身固有的排版規則，兩者概念
/// 不同，不應混用同一套注入路徑）。
const String _kCodeTableCss = '<style>'
    'pre, code, table { writing-mode: horizontal-tb; direction: ltr; } '
    'pre, table { overflow-x: auto; display: block; max-width: 100%; } '
    // GFM 表格在無邊框 CSS 時於部分 WebView 預設無格線可辨識（審查建議，
    // 見 reviews/review-issue-5-plan.md Minor #1），補上基礎格線樣式。
    'table { border-collapse: collapse; } '
    'th, td { border: 1px solid currentColor; padding: 4px 8px; }'
    '</style>';

class _TocNode {
  final MdHeading? heading;
  final List<_TocNode> children = [];
  _TocNode([this.heading]);
}

_TocNode _buildTocTree(List<MdHeading> headings) {
  final root = _TocNode();
  final stack = <_TocNode>[root];
  final levels = <int>[0];
  for (final heading in headings) {
    while (levels.last >= heading.level) {
      stack.removeLast();
      levels.removeLast();
    }
    final node = _TocNode(heading);
    stack.last.children.add(node);
    stack.add(node);
    levels.add(heading.level);
  }
  return root;
}

/// 遞迴渲染 [node] 的子節點為 `<li>` 序列（不含最外層 `<ol>`——最外層由
/// `buildEpubNavXhtml()` 既有模板提供，見呼叫處）；子節點自身若還有更深
/// 層的子節點，則巢狀輸出一層 `<ol>`。
String _renderTocChildren(_TocNode node, List<String> sectionHrefs) {
  final buffer = StringBuffer();
  for (final child in node.children) {
    final heading = child.heading!;
    final href = '${sectionHrefs[heading.sectionIndex]}#${heading.anchorId}';
    buffer.write('<li><a href="$href">${escapeXml(heading.text)}</a>');
    if (child.children.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('<ol>');
      buffer.write(_renderTocChildren(child, sectionHrefs));
      buffer.writeln('</ol>');
    }
    buffer.writeln('</li>');
  }
  return buffer.toString();
}

String _sectionXhtml(List<md.Node> nodes) => '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>內容</title>
$_kCodeTableCss
</head>
<body>
${md.renderToHtml(nodes)}
</body>
</html>
''';

/// 純 CPU 運算（Frontmatter／Markdown 解析＋章節切分＋EPUB 結構產生），
/// 外包至 `Isolate.run()` 背景執行（見呼叫處 [synthesizeMdBook] 註解，
/// 比照 Issue 4 `_decodeAndSynthesize()` 既有作法）。頂層純函式、僅接受
/// 可跨 isolate 傳遞的 [Uint8List]／[String] 參數。
MdSynthesisResult _decodeAndSynthesize(Uint8List bytes, String bookId, String fallbackTitle) {
  final rawContent = utf8.decode(bytes, allowMalformed: true);
  final parsedDoc = parseMdFrontmatter(rawContent);
  final parseResult = parseMdIntoSections(parsedDoc.body);

  final hasContent = parseResult.sections.any((s) => s.nodes.isNotEmpty);
  if (!hasContent) {
    throw const EmptyMdException('Markdown 檔案內容為空');
  }

  final archive = Archive();
  archive.addFile(
    ArchiveFile.bytes('mimetype', utf8.encode('application/epub+zip'))
      ..compression = CompressionType.none,
  );
  archive.addFile(ArchiveFile.bytes('META-INF/container.xml', utf8.encode(kEpubContainerXml)));

  final sectionHrefs = <String>[];
  final manifestItems = StringBuffer();
  final spineItems = StringBuffer();

  for (var i = 0; i < parseResult.sections.length; i++) {
    final id = 'sec${(i + 1).toString().padLeft(4, '0')}';
    final href = 'text/$id.xhtml';
    sectionHrefs.add(href);
    archive.addFile(
      ArchiveFile.bytes('OEBPS/$href', utf8.encode(_sectionXhtml(parseResult.sections[i].nodes))),
    );
    manifestItems.writeln('<item id="$id" href="$href" media-type="application/xhtml+xml"/>');
    spineItems.writeln('<itemref idref="$id"/>');
  }

  final tocTree = _buildTocTree(parseResult.headings);
  final navItems = _renderTocChildren(tocTree, sectionHrefs);
  archive.addFile(ArchiveFile.bytes('OEBPS/nav.xhtml', utf8.encode(buildEpubNavXhtml(navItems))));

  final title = parsedDoc.frontmatter.title ?? fallbackTitle;
  archive.addFile(ArchiveFile.bytes(
    'OEBPS/content.opf',
    utf8.encode(buildEpubContentOpf(
      identifier: 'elinkbook-md-$bookId',
      title: title,
      manifestItems: manifestItems.toString(),
      spineItems: spineItems.toString(),
    )),
  ));

  return MdSynthesisResult(
    epubBytes: ZipEncoder().encodeBytes(archive),
    frontmatterTitle: parsedDoc.frontmatter.title,
    frontmatterAuthor: parsedDoc.frontmatter.author,
    frontmatterCoverBytes: parsedDoc.frontmatter.coverBytes,
  );
}

/// 讀取 [filePath]（本機路徑或 `content://` URI）指向的 Markdown 檔案，
/// 解析 Frontmatter 與標題階層，合成一份最小合法 EPUB3 壓縮檔。[bookId]
/// 用於 OPF `dc:identifier`，[fallbackTitle] 於 Frontmatter 未指定標題時
/// 使用（呼叫端傳入依檔名推導的既有慣例，比照 Issue 4
/// `titleFromFileName()` 用法）。**MD 內容一律假設 UTF-8 編碼**（寬鬆解碼，
/// 不拋出例外）——不比照 TXT 的多編碼偵測梯隊，因 Markdown 是與現代
/// UTF-8-centric 工具鏈緊密綁定的格式，Big5 等舊編碼的 Markdown 檔案
/// 在實務上極為罕見，issues.md Issue 5 範圍本身也未要求此能力（YAGNI）。
/// CPU 密集運算外包至 `Isolate.run()`。
Future<MdSynthesisResult> synthesizeMdBook(
  String filePath,
  String bookId,
  String fallbackTitle,
) async {
  final bytes = filePath.contains('://')
      ? await readContentUriBytes(filePath, tempFilePrefix: 'md_probe', tempFileExtension: '.md')
      : await File(filePath).readAsBytes();
  return Isolate.run(() => _decodeAndSynthesize(bytes, bookId, fallbackTitle));
}
