import 'package:flutter_test/flutter_test.dart';

import 'arb_consistency_helpers.dart';

void main() {
  group('messagesOf', () {
    test('略過 @@locale 與所有 @key 中繼資料，只留鍵與字串', () {
      final result = messagesOf({
        '@@locale': 'en',
        'cancel': 'Cancel',
        '@cancel': {'description': '取消按鈕'},
        'close': 'Close',
      });

      expect(result, {'cancel': 'Cancel', 'close': 'Close'});
    });
  });

  group('placeholderNames', () {
    test('單純的 {name} 取出名稱', () {
      expect(placeholderNames('第 {chapter} 章'), {'chapter'});
    });

    test('多個 placeholder 都取出', () {
      expect(placeholderNames('{a} 與 {b}'), {'a', 'b'});
    });

    test('ICU plural 的計數參數與巢狀分支內的 {count} 只算一個名稱，分支文字不誤判', () {
      expect(
        placeholderNames('{count, plural, =1{1 本} other{{count} 本}}'),
        {'count'},
      );
    });

    test('沒有 placeholder 時回傳空集合', () {
      expect(placeholderNames('取消'), isEmpty);
    });
  });

  group('keySetViolations', () {
    test('鍵集合相同：沒有違規', () {
      expect(keySetViolations('en', {'a': '甲', 'b': '乙'}, {'a': 'A', 'b': 'B'}), isEmpty);
    });

    test('other 缺鍵：列出缺的鍵（排序）', () {
      expect(
        keySetViolations('en', {'a': '甲', 'b': '乙', 'c': '丙'}, {'a': 'A'}),
        ['[en] 缺鍵：b, c'],
      );
    });

    test('other 多鍵：列出多的鍵', () {
      expect(
        keySetViolations('zh_CN', {'a': '甲'}, {'a': '甲', 'x': '叉'}),
        ['[zh_CN] 多鍵：x'],
      );
    });

    test('同時缺鍵與多鍵：兩則訊息', () {
      expect(
        keySetViolations('en', {'a': '甲', 'b': '乙'}, {'a': 'A', 'x': 'X'}),
        ['[en] 缺鍵：b', '[en] 多鍵：x'],
      );
    });
  });

  group('placeholderViolations', () {
    test('placeholder 名稱集合相同：沒有違規', () {
      expect(
        placeholderViolations('en', {'k': '{count} 本'}, {'k': '{count} books'}),
        isEmpty,
      );
    });

    test('other 少一個 placeholder：抓出並顯示兩邊集合', () {
      expect(
        placeholderViolations('en', {'k': '{count} 本，共 {total}'}, {'k': 'books'}),
        ['[en] 鍵 k 的 placeholder 不一致：zh_TW={count, total}，en={}'],
      );
    });

    test('other 多一個 template 沒有的 placeholder：抓出', () {
      expect(
        placeholderViolations('zh_CN', {'k': '{count} 本'}, {'k': '{count} 本 {x}'}),
        ['[zh_CN] 鍵 k 的 placeholder 不一致：zh_TW={count}，zh_CN={count, x}'],
      );
    });

    test('只存在於一邊的鍵不在此檢查（交給 keySetViolations）', () {
      expect(placeholderViolations('en', {'a': '{n}'}, {'b': '{m}'}), isEmpty);
    });
  });

  group('zhMirrorViolations', () {
    test('zh 與 zh_TW 逐字相同：沒有違規', () {
      expect(zhMirrorViolations({'a': '取消'}, {'a': '取消'}), isEmpty);
    });

    test('zh 偏離 zh_TW：列出偏離的鍵', () {
      expect(
        zhMirrorViolations({'a': '取消', 'b': '確定'}, {'a': '取消', 'b': '确定'}),
        ['[zh] 與 zh_TW 文字不同的鍵：b'],
      );
    });

    test('zh 缺鍵：不在此重複回報（交給 keySetViolations）', () {
      expect(
        zhMirrorViolations({'a': '取消', 'b': '確定'}, {'a': '取消'}),
        isEmpty,
      );
    });
  });

  group('enUntranslatedViolations', () {
    test('en 有翻譯：沒有違規', () {
      expect(enUntranslatedViolations({'a': '取消'}, {'a': 'Cancel'}, {}), isEmpty);
    });

    test('en 與 zh_TW 相同：視為漏翻', () {
      expect(
        enUntranslatedViolations({'a': '取消'}, {'a': '取消'}, {}),
        ['[en] 疑似漏翻（與 zh_TW 相同或含中文字元）：a'],
      );
    });

    test('en 與 zh_TW 不同但含中文字元：視為漏翻', () {
      expect(
        enUntranslatedViolations({'a': 'A'}, {'a': '取消 Cancel'}, {}),
        ['[en] 疑似漏翻（與 zh_TW 相同或含中文字元）：a'],
      );
    });

    test('列入白名單的鍵不算漏翻', () {
      expect(
        enUntranslatedViolations(
          {'a': '正體中文'},
          {'a': '正體中文'},
          {'a': '語言自稱，刻意不翻譯'},
        ),
        isEmpty,
      );
    });

    test('白名單項目不再命中（en 已有翻譯）：視為過期', () {
      expect(
        enUntranslatedViolations(
          {'a': '取消'},
          {'a': 'Cancel'},
          {'a': '舊的理由'},
        ),
        ['[en] 白名單已過期（不再與 zh_TW 相同、也不含中文字元，或鍵已不存在）：a'],
      );
    });

    test('白名單的鍵在 en 已不存在：視為過期', () {
      expect(
        enUntranslatedViolations({'a': '取消'}, {'a': 'Cancel'}, {'gone': '已刪除的鍵'}),
        ['[en] 白名單已過期（不再與 zh_TW 相同、也不含中文字元，或鍵已不存在）：gone'],
      );
    });
  });
}
