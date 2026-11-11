import 'package:elinkbook/reader/toc_jump_override.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TocJumpOverride', () {
    var clock = DateTime(2026, 1, 1);
    DateTime now() => clock;
    TocJumpOverride make() => TocJumpOverride(now: now);
    setUp(() => clock = DateTime(2026, 1, 1));

    test('尚未跳轉時沒有覆寫', () {
      final o = make();
      expect(o.tocId, isNull);
      o.onPosition('a');
      expect(o.tocId, isNull);
    });

    test('跳轉後落地的位置回報期間維持覆寫（含重複回報）', () {
      final o = make()..begin(tocId: 4, currentKey: 'before');
      expect(o.tocId, 4);
      o.onPosition('before'); // 舊位置的殘留回報
      expect(o.tocId, 4);
      o.onPosition('landed'); // 跳轉落地
      expect(o.tocId, 4);
      o.onPosition('landed'); // 同一位置重複回報
      expect(o.tocId, 4);
    });

    test('落地後排版穩定期內位置改變（雙欄補欄的第二次回報）維持覆寫', () {
      final o = make()..begin(tocId: 4, currentKey: 'before');
      o.onPosition('landed');
      clock = clock.add(const Duration(milliseconds: 260));
      o.onPosition('settled-with-filler');
      expect(o.tocId, 4);
    });

    test('度過排版穩定期後位置改變（使用者翻頁）就解除覆寫', () {
      final o = make()..begin(tocId: 4, currentKey: 'before');
      o.onPosition('landed');
      clock = clock.add(const Duration(seconds: 2));
      o.onPosition('next-page');
      expect(o.tocId, isNull);
    });

    test('tocId 為 0 是合法覆寫', () {
      final o = make()..begin(tocId: 0, currentKey: 'x');
      expect(o.tocId, 0);
    });

    test('節點沒有 tocId 時不覆寫', () {
      final o = make()..begin(tocId: null, currentKey: 'x');
      o.onPosition('y');
      expect(o.tocId, isNull);
    });

    test('再次跳轉會重新開始', () {
      final o = make()..begin(tocId: 4, currentKey: 'a');
      o.onPosition('b');
      o.begin(tocId: 1, currentKey: 'b');
      expect(o.tocId, 1);
      o.onPosition('c');
      expect(o.tocId, 1);
    });
  });
}
