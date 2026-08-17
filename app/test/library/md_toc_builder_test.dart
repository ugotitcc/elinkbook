import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/md_toc_builder.dart';

void main() {
  group('parseMdIntoSections：章節切分', () {
    test('無標題時回傳單一 section，title 為 null，headings 為空', () {
      final result = parseMdIntoSections('這是一段沒有標題的內容。\n\n第二段。');
      expect(result.sections, hasLength(1));
      expect(result.sections.single.title, isNull);
      expect(result.headings, isEmpty);
    });

    test('多個 H1 依序切分為多個 section', () {
      final result = parseMdIntoSections('# 第一章\n內容一\n\n# 第二章\n內容二');
      expect(result.sections, hasLength(2));
      expect(result.sections[0].title, '第一章');
      expect(result.sections[1].title, '第二章');
    });

    test('第一個標題之前的內容獨立為前言 section (Ruling 1)', () {
      final result = parseMdIntoSections('前言內容\n\n# 第一章\n內容一');
      expect(result.sections, hasLength(2));
      expect(result.sections[0].title, isNull);
      expect(result.sections[1].title, '第一章');
      expect(result.headings.single.sectionIndex, 1);
    });

    test('文件只用 H2 起始各段落時，切分基準是 H2（最淺標題層級），非強制 H1', () {
      final result = parseMdIntoSections('## 段落 A\n內容 A\n\n## 段落 B\n內容 B');
      expect(result.sections, hasLength(2));
      expect(result.sections[0].title, '段落 A');
      expect(result.sections[1].title, '段落 B');
    });

    test('H2/H3 巢狀於 H1 之下時不獨立成 section，仍在同一個 section 內', () {
      final result = parseMdIntoSections('# 第一章\n## 子章節 A\n內容\n## 子章節 B\n內容');
      expect(result.sections, hasLength(1));
      expect(result.sections.single.title, '第一章');
    });
  });

  group('parseMdIntoSections：標題階層與 id', () {
    test('每個標題皆取得唯一、依序編號的 anchorId', () {
      final result = parseMdIntoSections('# A\n## B\n# C');
      expect(result.headings.map((h) => h.anchorId).toSet(), hasLength(3));
      expect(result.headings.map((h) => h.anchorId), ['heading_0001', 'heading_0002', 'heading_0003']);
    });

    test('重複標題文字仍各自取得不同 anchorId（不依賴內建 slug 去重機制）', () {
      final result = parseMdIntoSections('# 概述\n內容一\n\n# 概述\n內容二');
      final ids = result.headings.map((h) => h.anchorId).toList();
      expect(ids[0], isNot(ids[1]));
      expect(result.headings[0].text, '概述');
      expect(result.headings[1].text, '概述');
    });

    test('標題層級（level）正確對應 H1-H6', () {
      final result = parseMdIntoSections('# H1\n## H2\n### H3\n#### H4\n##### H5\n###### H6');
      expect(result.headings.map((h) => h.level), [1, 2, 3, 4, 5, 6]);
    });

    test('標題所屬 sectionIndex 正確——巢狀子標題與其所屬頂層標題同一個 index', () {
      final result = parseMdIntoSections('# 第一章\n## 子章節\n# 第二章');
      expect(result.headings, hasLength(3));
      expect(result.headings[0].sectionIndex, 0); // 第一章
      expect(result.headings[1].sectionIndex, 0); // 子章節（仍在第一章的 section）
      expect(result.headings[2].sectionIndex, 1); // 第二章
    });
  });

  group('parseMdIntoSections：內容保留', () {
    test('每個 section 的 nodes 皆非空（切分後不遺漏內容節點）', () {
      final result = parseMdIntoSections('# 第一章\n第一段\n\n第二段\n\n# 第二章\n第三段');
      for (final section in result.sections) {
        expect(section.nodes, isNotEmpty);
      }
    });
  });
}
