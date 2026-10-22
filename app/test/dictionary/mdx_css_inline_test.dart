// app/test/dictionary/mdx_css_inline_test.dart
import 'package:elinkbook/dictionary/mdx_css_inline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inlineLinkedCss', () {
    test('依檔名換成 style', () {
      const html = '<link rel="stylesheet" href="css/Ghychyz.CSS">';
      final out = inlineLinkedCss(html, {'ghychyz.css': 'p{color:red}'});
      expect(out, contains('<style>p{color:red}</style>'));
      expect(out, isNot(contains('<link')));
    });

    test('查詢字串與路徑不影響配對', () {
      const html = '<link rel="stylesheet" href="../x/a.css?v=2">';
      final out = inlineLinkedCss(html, {'a.css': 'body{margin:0}'});
      expect(out, contains('<style>body{margin:0}</style>'));
      expect(out, isNot(contains('<link')));
    });

    test('沒有對應檔案的 link 被移除', () {
      const html =
          '<p>hello</p><link rel="stylesheet" href="missing.css"><p>world</p>';
      final out = inlineLinkedCss(html, {'other.css': 'p{color:red}'});
      expect(out, isNot(contains('<link')));
      expect(out, isNot(contains('<style')));
      expect(out, contains('<p>hello</p><p>world</p>'));
    });

    test('@import 被移除：CSS 內容與詞條自帶 style 中的 @import 皆被移除', () {
      const html =
          '<link rel="stylesheet" href="a.css">'
          '<style>@import url(http://evil/x.css); p { font-size: 14px; }</style>';
      final out = inlineLinkedCss(html, {
        'a.css': '@import url("b.css"); p{color:red}',
      });
      expect(out, isNot(contains('@import')));
      expect(out, contains('p{color:red}'));
      expect(out, contains('p { font-size: 14px; }'));
    });

    test('style 結束標籤被轉義', () {
      const html = '<link rel="stylesheet" href="a.css">';
      final out = inlineLinkedCss(html, {
        'a.css': '</style><script>x</script>',
      });
      // 輸出恰好一個 </style>（內嵌的那個）
      expect(
        RegExp(r'</style>', caseSensitive: false).allMatches(out),
        hasLength(1),
      );
      // CSS 內容裡的 </style 變成 <\/style
      expect(out, contains(r'<\/style'));
      // <script> 文字仍在，但位置落在唯一的 <style> 與 </style> 之間
      final styleOpen = out.indexOf('<style>');
      final scriptPos = out.indexOf('<script>x</script>');
      final styleClose = out.indexOf('</style>');
      expect(styleOpen, isNonNegative);
      expect(scriptPos, greaterThan(styleOpen));
      expect(styleClose, greaterThan(scriptPos));
    });

    test('其他 link 不動', () {
      const html = '<link rel="icon" href="x.png">';
      final out = inlineLinkedCss(html, {'x.png.css': 'body{}'});
      expect(out, html);
    });

    test('href="http://evil/x.css" 且檔名剛好是已匯入的 x.css：照檔名配對內嵌', () {
      const html = '<link rel="stylesheet" href="http://evil/x.css">';
      final out = inlineLinkedCss(html, {'x.css': 'body{background:#fff}'});
      expect(out, contains('<style>body{background:#fff}</style>'));
      expect(out, isNot(contains('<link')));
      expect(out, isNot(contains('http://evil/x.css')));
    });
  });
}
