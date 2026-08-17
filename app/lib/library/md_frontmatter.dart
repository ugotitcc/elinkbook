import 'dart:convert';
import 'dart:typed_data';

import 'package:yaml/yaml.dart';

/// Markdown Frontmatter 解析後的 metadata 資料
class MdFrontmatter {
  /// 書名 / 文章標題
  final String? title;

  /// 作者
  final String? author;

  /// 封面圖位元組（若 Frontmatter 的 cover 為 base64 data URI）
  final Uint8List? coverBytes;

  const MdFrontmatter({this.title, this.author, this.coverBytes});
}

/// 解析後的 Markdown 文件（包含 Frontmatter 與正文）
class MdParsedDocument {
  /// 解析出的 Frontmatter metadata
  final MdFrontmatter frontmatter;

  /// 剝離 Frontmatter 後的 Markdown 正文
  final String body;

  const MdParsedDocument({required this.frontmatter, required this.body});
}

/// 解析 Markdown 內容中的 YAML Frontmatter
///
/// 若開頭包含 `---` 與結尾 `---`，則抽取其中的 YAML key-value（如 title、author、cover）；
/// 若無 Frontmatter 或格式不合法，則優雅降級。
MdParsedDocument parseMdFrontmatter(String content) {
  // 處理 UTF-8 BOM 開頭
  final cleanContent = content.startsWith('\uFEFF') ? content.substring(1) : content;
  final lines = cleanContent.split(RegExp(r'\r\n|\r|\n'));
  if (lines.isEmpty || lines.first.trim() != '---') {
    return MdParsedDocument(frontmatter: const MdFrontmatter(), body: content);
  }
  var endIndex = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      endIndex = i;
      break;
    }
  }
  if (endIndex == -1) {
    return MdParsedDocument(frontmatter: const MdFrontmatter(), body: content);
  }

  final yamlText = lines.sublist(1, endIndex).join('\n');
  final body = lines.sublist(endIndex + 1).join('\n');

  try {
    final doc = loadYaml(yamlText);
    if (doc is! YamlMap) {
      return MdParsedDocument(frontmatter: const MdFrontmatter(), body: body);
    }
    final title = doc['title']?.toString();
    final author = doc['author']?.toString();
    final coverValue = doc['cover']?.toString();
    final coverBytes =
        coverValue != null && coverValue.startsWith('data:') ? _decodeDataUri(coverValue) : null;
    return MdParsedDocument(
      frontmatter: MdFrontmatter(title: title, author: author, coverBytes: coverBytes),
      body: body,
    );
  } on YamlException {
    return MdParsedDocument(frontmatter: const MdFrontmatter(), body: body);
  }
}

/// 解碼 data:image/...;base64,... 格式之 Data URI 為二進位資料
Uint8List? _decodeDataUri(String value) {
  if (!value.startsWith('data:')) return null;
  final commaIndex = value.indexOf(',');
  if (commaIndex <= 'data:'.length) return null;
  final meta = value.substring('data:'.length, commaIndex);
  if (!meta.contains('base64')) return null;
  try {
    return base64Decode(value.substring(commaIndex + 1));
  } on FormatException {
    return null;
  }
}
