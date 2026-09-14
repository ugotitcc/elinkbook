// app/test/search/highlight_segments_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/search/highlight_segments.dart';

void main() {
  group('splitHighlightSegments', () {
    test('query 為空字串時，回傳單一非命中片段，內容為整段原文', () {
      final segments = splitHighlightSegments('第1章含有搜尋關鍵字的文本片段', '');

      expect(segments, [
        const HighlightSegment('第1章含有搜尋關鍵字的文本片段', false),
      ]);
    });

    test('text 為空字串時，回傳單一非命中片段，內容為空字串', () {
      final segments = splitHighlightSegments('', '關鍵字');

      expect(segments, [const HighlightSegment('', false)]);
    });

    test('找不到任何命中時，回傳單一非命中片段，內容為整段原文', () {
      final segments = splitHighlightSegments('這段文字完全沒有目標', '關鍵字');

      expect(segments, [const HighlightSegment('這段文字完全沒有目標', false)]);
    });

    test('大小寫不敏感比對：query 為大寫，text 為小寫仍應命中', () {
      final segments = splitHighlightSegments('hello world', 'WORLD');

      expect(segments, [
        const HighlightSegment('hello ', false),
        const HighlightSegment('world', true),
      ]);
    });

    test('命中位置在字串開頭：不產生開頭的空白非命中片段', () {
      final segments = splitHighlightSegments('關鍵字出現在最前面', '關鍵字');

      expect(segments, [
        const HighlightSegment('關鍵字', true),
        const HighlightSegment('出現在最前面', false),
      ]);
    });

    test('命中位置在字串結尾：不產生結尾的空白非命中片段', () {
      final segments = splitHighlightSegments('最後面出現關鍵字', '關鍵字');

      expect(segments, [
        const HighlightSegment('最後面出現', false),
        const HighlightSegment('關鍵字', true),
      ]);
    });

    test('整段文字剛好等於 query 時，回傳單一命中片段', () {
      final segments = splitHighlightSegments('關鍵字', '關鍵字');

      expect(segments, [const HighlightSegment('關鍵字', true)]);
    });

    test('多個命中：命中之間夾雜非命中片段', () {
      final segments = splitHighlightSegments('關鍵字A普通文字關鍵字B', '關鍵字');

      expect(segments, [
        const HighlightSegment('關鍵字', true),
        const HighlightSegment('A普通文字', false),
        const HighlightSegment('關鍵字', true),
        const HighlightSegment('B', false),
      ]);
    });

    test('命中緊鄰邊界：連續兩次命中之間沒有非命中片段', () {
      final segments = splitHighlightSegments('aaaa', 'aa');

      expect(segments, [
        const HighlightSegment('aa', true),
        const HighlightSegment('aa', true),
      ]);
    });

    test('大小寫混合比對：text 為大寫，query 為小寫時仍應命中並保留原文大小寫', () {
      final segments = splitHighlightSegments('EPUB 規範說明', 'epub');

      expect(segments, [
        const HighlightSegment('EPUB', true),
        const HighlightSegment(' 規範說明', false),
      ]);
    });
  });

  group('HighlightSegment', () {
    test('支援值相等性與 hashCode（防止實作漏比欄位或漏寫 hashCode）', () {
      const seg1 = HighlightSegment('文字', true);
      const seg2 = HighlightSegment('文字', true);
      const segDiffMatch = HighlightSegment('文字', false);
      const segDiffText = HighlightSegment('其他', true);

      expect(seg1, equals(seg2));
      expect(seg1.hashCode, equals(seg2.hashCode));
      expect(seg1, isNot(equals(segDiffMatch)));
      expect(seg1, isNot(equals(segDiffText)));
      // 避免 `equal_elements_in_set` lint：用動態加入而非字面量同時放入兩個相等元素
      final segmentSet = <HighlightSegment>{seg1};
      segmentSet.add(seg2);
      expect(segmentSet.length, 1);
    });
  });
}
