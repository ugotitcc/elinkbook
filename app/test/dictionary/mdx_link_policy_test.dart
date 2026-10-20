// MDX 連結政策（epic-63 Issue 6a Task 4）。
import 'package:elinkbook/dictionary/mdx_link_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MdxEntryLink', () {
    test('entry:// 與 bword:// 都視為詞條連結', () {
      final entry = classifyLink('entry://apple');
      expect(entry, isA<MdxEntryLink>());
      expect((entry as MdxEntryLink).word, 'apple');

      final bword = classifyLink('bword://apple');
      expect(bword, isA<MdxEntryLink>());
      expect((bword as MdxEntryLink).word, 'apple');
    });

    test('URL 解碼並去掉結尾斜線', () {
      final action = classifyLink('entry://%E5%A4%A9%E5%9C%B0/');
      expect(action, isA<MdxEntryLink>());
      expect((action as MdxEntryLink).word, '天地');
    });

    test('保留詞內空白與大小寫', () {
      final action = classifyLink('entry://New York');
      expect((action as MdxEntryLink).word, 'New York');
    });

    test('scheme 大小寫不影響', () {
      final action = classifyLink('ENTRY://apple');
      expect(action, isA<MdxEntryLink>());
      expect((action as MdxEntryLink).word, 'apple');
    });
  });

  group('MdxAnchorLink', () {
    test('純錨點', () {
      expect(classifyLink('#x'), isA<MdxAnchorLink>());
      expect(classifyLink('#'), isA<MdxAnchorLink>());
    });

    test('dict.local 的錨點不攔截', () {
      expect(classifyLink('https://dict.local/#x'), isA<MdxAnchorLink>());
    });

    test('entry://#x 是錨點，不是詞條', () {
      expect(classifyLink('entry://#x'), isA<MdxAnchorLink>());
    });
  });

  group('MdxBlockedLink', () {
    test('外部與危險 scheme 一律封鎖', () {
      for (final url in [
        'https://example.com',
        'http://dict.local/x',
        'http://example.com',
        'file:///x',
        'sound://a',
        'javascript:alert(1)',
        'data:text/html,x',
        'mailto:a@example.com',
        'ghychyz.css',
        '',
      ]) {
        expect(classifyLink(url), isA<MdxBlockedLink>(), reason: '$url 應被封鎖');
      }
    });
  });

  test('baseUrl 固定為 dict.local', () {
    expect(kMdxBaseUrl, 'https://dict.local/');
  });
}
