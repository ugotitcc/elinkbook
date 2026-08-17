import 'package:markdown/markdown.dart' as md;

class MdHeading {
  final int level;
  final String text;
  final String anchorId;
  final int sectionIndex;
  const MdHeading({
    required this.level,
    required this.text,
    required this.anchorId,
    required this.sectionIndex,
  });
}

class MdSection {
  /// `null` 代表這是唯一一個 section 且文件內完全沒有偵測到標題（見
  /// [parseMdIntoSections] 文件註解），或是第一個標題之前的前言 section
  /// （比照 `txt_chapter_splitter.dart` 對前言的既有處置慣例：獨立成一個
  /// title 為 null 的章節，不與第一個標題章節合併）。
  final String? title;
  final List<md.Node> nodes;
  const MdSection({this.title, required this.nodes});
}

class MdParseResult {
  final List<MdSection> sections;
  final List<MdHeading> headings;
  const MdParseResult({required this.sections, required this.headings});
}

int? _headingLevel(String tag) {
  if (tag.length != 2 || tag[0] != 'h') return null;
  final n = int.tryParse(tag[1]);
  return (n != null && n >= 1 && n <= 6) ? n : null;
}

String _unescapeHtml(String text) => text
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");

String _textContent(md.Node node) {
  String extract(md.Node n) {
    if (n is md.Text) return n.text;
    if (n is md.Element) {
      return (n.children ?? const <md.Node>[]).map(extract).join();
    }
    return '';
  }

  return _unescapeHtml(extract(node));
}

/// 解析 [markdownBody]（**不含** Frontmatter，呼叫端須先用
/// `parseMdFrontmatter()` 剝離）為 AST，依「文件內出現過的最淺標題層級」
/// 把頂層區塊節點切分成多個 [MdSection]（例如文件只用 H2 起始各段落時，
/// 切分基準是 H2，非強制 H1，見 Global Constraints 已查證事實 #4——頂層
/// 節點清單本身即為切分依據，不需遞迴）；完全沒有標題時回傳單一
/// section（`title: null`）。每個標題（含巢狀於 section 內、非切分層級
/// 的子標題）皆依文件出現順序指派唯一 `anchorId`（`heading_0001` 起算，
/// 見 Global Constraints 已查證事實 #3 對捨棄內建 slug id 機制的理由），
/// 並直接寫入該標題 Element 的 `attributes['id']`（同時清空
/// `generatedId`，避免渲染時重複輸出兩個 `id` 屬性）。
MdParseResult parseMdIntoSections(String markdownBody) {
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubWeb);
  final topLevelNodes = document.parse(markdownBody);

  final topLevelLevels = topLevelNodes
      .map((n) => n is md.Element ? _headingLevel(n.tag) : null)
      .toList();
  int? minLevel;
  for (final level in topLevelLevels) {
    if (level == null) continue;
    if (minLevel == null || level < minLevel) minLevel = level;
  }

  final headings = <MdHeading>[];
  var headingCounter = 0;

  void assignHeadingIds(md.Node node, int sectionIndex) {
    if (node is md.Element) {
      final level = _headingLevel(node.tag);
      if (level != null) {
        headingCounter++;
        final id = 'heading_${headingCounter.toString().padLeft(4, '0')}';
        node.generatedId = null;
        node.attributes['id'] = id;
        headings.add(MdHeading(
          level: level,
          text: _textContent(node),
          anchorId: id,
          sectionIndex: sectionIndex,
        ));
      }
      for (final child in node.children ?? const <md.Node>[]) {
        assignHeadingIds(child, sectionIndex);
      }
    }
  }

  final sections = <MdSection>[];
  var currentNodes = <md.Node>[];
  String? currentTitle;
  var sectionIndex = -1;

  void flushSection() {
    if (currentNodes.isNotEmpty) {
      sections.add(MdSection(title: currentTitle, nodes: currentNodes));
    }
  }

  for (var i = 0; i < topLevelNodes.length; i++) {
    final node = topLevelNodes[i];
    final level = topLevelLevels[i];
    if (minLevel != null && level == minLevel) {
      flushSection();
      sectionIndex++;
      currentNodes = [node];
      currentTitle = _textContent(node);
    } else {
      if (sectionIndex == -1) sectionIndex = 0;
      currentNodes.add(node);
    }
    assignHeadingIds(node, sectionIndex);
  }
  flushSection();

  if (sections.isEmpty) {
    sections.add(MdSection(nodes: topLevelNodes));
  }

  return MdParseResult(sections: sections, headings: headings);
}
