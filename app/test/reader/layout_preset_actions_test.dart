import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/layout_preset_actions.dart';

void main() {
  group('layoutPresetTargetsCurrentBookOnly', () {
    test('targetBookIds 恰為 [currentBookId] 時回傳 true', () {
      expect(layoutPresetTargetsCurrentBookOnly(['b1'], 'b1'), isTrue);
    });

    test('targetBookIds 有多本書時回傳 false（即使包含 currentBookId）', () {
      expect(layoutPresetTargetsCurrentBookOnly(['b1', 'b2'], 'b1'), isFalse);
    });

    test('targetBookIds 恰有 1 本但不是 currentBookId 時回傳 false', () {
      expect(layoutPresetTargetsCurrentBookOnly(['b2'], 'b1'), isFalse);
    });

    test('targetBookIds 為空清單時回傳 false', () {
      expect(layoutPresetTargetsCurrentBookOnly([], 'b1'), isFalse);
    });
  });
}
