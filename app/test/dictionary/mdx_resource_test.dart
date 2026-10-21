// MDD 資源鍵轉換與型別測試（epic-63 Issue 6b Task 1）。
import 'dart:typed_data';

import 'package:elinkbook/dictionary/mdx_resource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kMdxResourceMaxBytes', () {
    test('單一資源上限為 8MB', () {
      expect(kMdxResourceMaxBytes, 8 * 1024 * 1024);
    });
  });

  group('MdxResource', () {
    test('可 const 建構且包含 bytes 與 contentType', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final res = MdxResource(bytes: bytes, contentType: 'image/png');
      expect(res.bytes, bytes);
      expect(res.contentType, 'image/png');
    });
  });

  group('mddKeysForUrl', () {
    test('空白與子目錄：轉成雙反斜線與單反斜線兩組鍵值', () {
      expect(
        mddKeysForUrl('https://dict.local/pic/a%20b.png'),
        [r'\pic\a b.png', r'pic\a b.png'],
      );
    });

    test('中文與 %25：正確解碼', () {
      final keys = mddKeysForUrl('https://dict.local/%E5%9C%96/50%25.png');
      expect(keys, [r'\圖\50%.png', r'圖\50%.png']);
    });

    test('查詢字串與錨點被去掉', () {
      final keys = mddKeysForUrl('https://dict.local/pic/a.png?v=1#x');
      expect(keys, [r'\pic\a.png', r'pic\a.png']);
    });

    test('不在 baseUrl 底下回空清單', () {
      expect(mddKeysForUrl('https://evil.example/a.png'), isEmpty);
      expect(mddKeysForUrl('file:///a.png'), isEmpty);
      expect(mddKeysForUrl('data:image/png;base64,AA=='), isEmpty);
      expect(mddKeysForUrl('https://dict.local:8080/a.png'), isEmpty);
    });

    test('壞的百分比編碼回空清單，不丟例外', () {
      expect(mddKeysForUrl('https://dict.local/%E0%A4%A.png'), isEmpty);
    });

    test('根路徑與純查詢字串回空清單，不會出現 [r"\\", ""]', () {
      expect(mddKeysForUrl('https://dict.local/'), isEmpty);
      expect(mddKeysForUrl('https://dict.local/?v=1'), isEmpty);
      expect(mddKeysForUrl('https://dict.local/#x'), isEmpty);
    });

    test('favicon 不特判', () {
      expect(
        mddKeysForUrl('https://dict.local/favicon.ico'),
        [r'\favicon.ico', r'favicon.ico'],
      );
    });

    test('單層檔名路徑回傳含開頭反斜線與不含開頭反斜線兩組鍵值', () {
      expect(
        mddKeysForUrl('https://dict.local/test.png'),
        [r'\test.png', r'test.png'],
      );
    });
  });

  group('imageContentTypeForKey', () {
    test('只認 spec 列的五種圖片格式，副檔名不分大小寫', () {
      expect(imageContentTypeForKey(r'\pic\photo.jpg'), 'image/jpeg');
      expect(imageContentTypeForKey(r'pic\photo.jpeg'), 'image/jpeg');
      expect(imageContentTypeForKey(r'\pic\PHOTO.JPEG'), 'image/jpeg');
      expect(imageContentTypeForKey(r'\pic\image.PNG'), 'image/png');
      expect(imageContentTypeForKey(r'image.png'), 'image/png');
      expect(imageContentTypeForKey(r'\anim.gif'), 'image/gif');
      expect(imageContentTypeForKey(r'\ANIM.GIF'), 'image/gif');
      expect(imageContentTypeForKey(r'\photo.webp'), 'image/webp');
      expect(imageContentTypeForKey(r'vector.svg'), 'image/svg+xml');
      expect(imageContentTypeForKey(r'VECTOR.SVG'), 'image/svg+xml');
    });

    test('非圖片格式或無副檔名回 null', () {
      expect(imageContentTypeForKey(r'\audio\sound.mp3'), isNull);
      expect(imageContentTypeForKey(r'\style.css'), isNull);
      expect(imageContentTypeForKey(r'\script.js'), isNull);
      expect(imageContentTypeForKey(r'\no_extension'), isNull);
      expect(imageContentTypeForKey(''), isNull);
      expect(imageContentTypeForKey(r'\favicon.ico'), isNull);
    });
  });
}
