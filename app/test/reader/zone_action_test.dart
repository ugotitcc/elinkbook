import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/zone_action.dart';

void main() {
  group('isValidCustomZoneConfig()', () {
    test('9 格皆非 menu 時回傳 false', () {
      final actions = List<ZoneAction>.filled(9, ZoneAction.none);
      expect(isValidCustomZoneConfig(actions), isFalse);
    });

    test('恰好 1 格為 menu 時回傳 true', () {
      final actions = List<ZoneAction>.filled(9, ZoneAction.none);
      actions[4] = ZoneAction.menu;
      expect(isValidCustomZoneConfig(actions), isTrue);
    });

    test('多格為 menu 時回傳 true', () {
      final actions = List<ZoneAction>.filled(9, ZoneAction.previousPage);
      actions[0] = ZoneAction.menu;
      actions[8] = ZoneAction.menu;
      expect(isValidCustomZoneConfig(actions), isTrue);
    });

    test('長度不為 9 時回傳 false（即使含 menu）', () {
      final actions = [ZoneAction.menu, ZoneAction.previousPage];
      expect(isValidCustomZoneConfig(actions), isFalse);
    });

    test('長度為 9 但全部為 previousPage/nextPage/none 混合時回傳 false', () {
      final actions = [
        ZoneAction.previousPage, ZoneAction.nextPage, ZoneAction.none,
        ZoneAction.previousPage, ZoneAction.nextPage, ZoneAction.none,
        ZoneAction.previousPage, ZoneAction.nextPage, ZoneAction.none,
      ];
      expect(isValidCustomZoneConfig(actions), isFalse);
    });
  });
}
