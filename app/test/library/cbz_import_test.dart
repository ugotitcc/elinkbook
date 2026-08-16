import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/cbz_import.dart';

void main() {
  group('compareNaturalOrder', () {
    test('非零填補檔名依數值排出正確頁序（Issue 1 Spike 已查證的既有缺陷情境）', () {
      final names = ['2.jpg', '10.jpg', '1.jpg'];
      names.sort(compareNaturalOrder);
      expect(names, ['1.jpg', '2.jpg', '10.jpg']);
    });

    test('零填補檔名維持原有正確順序（字典序與自然序結果一致的情境）', () {
      final names = ['003.jpg', '001.jpg', '002.jpg'];
      names.sort(compareNaturalOrder);
      expect(names, ['001.jpg', '002.jpg', '003.jpg']);
    });

    test('相同前綴、數字不同的檔名依數值比較，不受字典序位數影響', () {
      final names = ['page10.png', 'page2.png', 'page1.png'];
      names.sort(compareNaturalOrder);
      expect(names, ['page1.png', 'page2.png', 'page10.png']);
    });

    test('完全非數字的檔名退回字典序比較', () {
      final names = ['cover.jpg', 'back.jpg', 'front.jpg'];
      names.sort(compareNaturalOrder);
      expect(names, ['back.jpg', 'cover.jpg', 'front.jpg']);
    });

    test('非數字片段忽略大小寫比較（審查修正：混用大小寫檔名仍依數字正確排序）', () {
      final names = ['Page2.jpg', 'page1.jpg', 'PAGE10.jpg'];
      names.sort(compareNaturalOrder);
      expect(names, ['page1.jpg', 'Page2.jpg', 'PAGE10.jpg']);
    });
  });
}
