import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/search/cjk_tokenizer.dart';

void main() {
  group('tokenizeForIndex', () {
    test('純中文逐字以空白分隔', () {
      expect(tokenizeForIndex('我喜歡貓'), '我 喜 歡 貓');
    });

    test('純英文維持原樣（不逐字拆）', () {
      expect(tokenizeForIndex('hello world'), 'hello world');
    });

    test('中英混合：中文逐字拆、英文單字維持完整', () {
      expect(tokenizeForIndex('我愛Flutter'), '我 愛 Flutter');
    });

    test('空字串回傳空字串', () {
      expect(tokenizeForIndex(''), '');
    });

    test('連續中文與數字混合：數字視為非 CJK 維持原樣', () {
      expect(tokenizeForIndex('第123章節'), '第 123 章 節');
    });

    test('前後與連續空白收斂為單一空白', () {
      expect(tokenizeForIndex('  hello   world  '), 'hello world');
      expect(tokenizeForIndex('  我  愛  貓  '), '我 愛 貓');
    });

    test('純空白字串回傳空字串', () {
      expect(tokenizeForIndex('   '), '');
      expect(tokenizeForQuery('   '), '');
    });

    test('英文在前中文在後維持邊界空格', () {
      expect(tokenizeForIndex('Flutter我愛'), 'Flutter 我 愛');
    });

    test('全形空白與 Tab 收斂為單一半形空白', () {
      expect(tokenizeForIndex('　我　愛　'), '我 愛');
      expect(tokenizeForIndex('hello\tworld'), 'hello world');
    });
  });

  group('tokenizeForQuery', () {
    test('包裝為 FTS5 phrase query（雙引號包住轉換後字串）', () {
      expect(tokenizeForQuery('我愛貓'), '"我 愛 貓"');
    });

    test('空字串輸入回傳空字串（呼叫端不應送出查詢）', () {
      expect(tokenizeForQuery(''), '');
    });

    test('內部雙引號跳脫為兩個雙引號', () {
      expect(tokenizeForQuery('a"b'), '"a""b"');
    });
  });
}
