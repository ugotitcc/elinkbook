// app/test/search/search_query_variants_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/search/search_query_variants.dart';

void main() {
  group('queryVariants', () {
    test('回傳原文／簡轉繁／繁轉簡三個變體，原文恆為第一個元素', () {
      final variants = queryVariants('国电脑');
      expect(variants.first, '国电脑');
      expect(variants, containsAll(['国电脑', '國電腦']));
    });

    test('轉換後與原文相同時自動去重（例如英數字查詢不受簡繁轉換影響）', () {
      expect(queryVariants('Dune'), ['Dune']);
    });

    test('空字串輸入回傳單一空字串變體，不拋出例外', () {
      expect(queryVariants(''), ['']);
    });
  });

  group('findMatchingVariant', () {
    test('回傳第一個能在文字中以 indexOf 找到的變體', () {
      final result = findMatchingVariant('電腦維修站', ['电脑', '電腦']);
      expect(result, '電腦');
    });

    test('依 variants 清單順序找，第一個找到的優先，不繼續嘗試後面的', () {
      final result = findMatchingVariant('电脑電腦都有', ['电脑', '電腦']);
      expect(result, '电脑');
    });

    test('不分大小寫比對（英數字查詢情境）', () {
      final result = findMatchingVariant('Dune Messiah', ['dune']);
      expect(result, 'dune');
    });

    test('全部變體皆找不到時回傳 null', () {
      final result = findMatchingVariant('完全不相關的內容', ['电脑', '電腦']);
      expect(result, isNull);
    });
  });
}
