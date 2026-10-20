// MDX 詞條 HTML 前處理（epic-63 Issue 6a Task 4）。
import 'package:elinkbook/dictionary/mdx_html_prepare.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('entry:// 錨點改寫', () {
    test('entry://#top → #top（雙引號）', () {
      expect(
        prepareEntryHtml('<a href="entry://#top">top</a>'),
        contains('<a href="#top">top</a>'),
      );
    });

    test('entry://#top → #top（單引號）', () {
      expect(
        prepareEntryHtml("<a href='entry://#top'>top</a>"),
        contains("<a href='#top'>top</a>"),
      );
    });

    test('屬性名大小寫與空白不影響比對', () {
      final out = prepareEntryHtml('<a HREF = "entry://#n1">n</a>');
      // 只要求改寫成功，不要求把屬性名轉成小寫。
      expect(out.toLowerCase(), contains('href = "#n1"'));
    });

    test('entry://詞 不動', () {
      final html = '<a href="entry://apple">apple</a>';
      expect(prepareEntryHtml(html), contains(html));
    });
  });

  group('sound:// 連結', () {
    test('移除 href、保留文字', () {
      final out = prepareEntryHtml('<a href="sound://a.mp3">發音</a>');
      expect(out, isNot(contains('sound://')));
      expect(out, contains('發音'));
      expect(out, contains('<a>發音</a>'));
    });

    test('單引號版本也移除', () {
      final out = prepareEntryHtml("<a href='sound://a.mp3'>發音</a>");
      expect(out, isNot(contains('sound://')));
      expect(out, contains('<a>發音</a>'));
    });
  });

  group('文件外殼與 meta', () {
    test('<link> 原樣保留（本 Issue 不處理 CSS）', () {
      const link = '<link rel="stylesheet" href="ghychyz.css">';
      expect(prepareEntryHtml(link), contains(link));
    });

    test('片段會包上完整文件與 meta', () {
      final out = prepareEntryHtml('<b>apple</b> 蘋果');
      expect(out, contains('<html'));
      expect(out, contains('</html>'));
      expect(out, contains('<meta charset="utf-8">'));
      expect(out, contains('width=device-width'));
      expect(out, contains('<b>apple</b> 蘋果'));
    });

    test('完整文件保留原內容並補上 meta', () {
      const doc =
          '<html><head><title>x</title></head>'
          '<body><p>內容</p></body></html>';
      final out = prepareEntryHtml(doc);
      expect(out, contains('<title>x</title>'));
      expect(out, contains('<p>內容</p>'));
      expect(out, contains('<meta charset="utf-8">'));
      expect(out, contains('width=device-width'));
      // 不得重複包一層 html。
      expect('<html'.allMatches(out.toLowerCase()).length, 1);
    });

    test('空字串回傳有效文件', () {
      final out = prepareEntryHtml('');
      expect(out, contains('<html'));
      expect(out, contains('</html>'));
      expect(out, contains('<meta charset="utf-8">'));
      expect(out, contains('<body>'));
    });
  });
}
