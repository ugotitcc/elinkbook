import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';

void main() {
  group('resolveZoneActions()', () {
    test('leftFlip 模板回傳與常數表逐格一致的 9 格陣列', () {
      expect(
        resolveZoneActions(NavZoneMode.leftFlip, const []),
        const [
          ZoneAction.nextPage, ZoneAction.menu, ZoneAction.previousPage,
          ZoneAction.nextPage, ZoneAction.menu, ZoneAction.previousPage,
          ZoneAction.nextPage, ZoneAction.menu, ZoneAction.previousPage,
        ],
      );
    });

    test('rightFlip 模板回傳與常數表逐格一致的 9 格陣列', () {
      expect(
        resolveZoneActions(NavZoneMode.rightFlip, const []),
        const [
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
        ],
      );
    });

    test('oneHand 模板回傳與常數表逐格一致的 9 格陣列', () {
      expect(
        resolveZoneActions(NavZoneMode.oneHand, const []),
        const [
          ZoneAction.menu, ZoneAction.none, ZoneAction.menu,
          ZoneAction.previousPage, ZoneAction.none, ZoneAction.previousPage,
          ZoneAction.nextPage, ZoneAction.none, ZoneAction.nextPage,
        ],
      );
    });

    test('custom 模式回傳傳入陣列原樣（同一個參考，不重新排序/轉換）', () {
      const customActions = [
        ZoneAction.none, ZoneAction.menu, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
      ];
      expect(
        resolveZoneActions(NavZoneMode.custom, customActions),
        same(customActions),
      );
    });
  });

  test('rightFlipZoneTemplate 常數本身與 rightFlip 模板一致', () {
    expect(
      rightFlipZoneTemplate,
      resolveZoneActions(NavZoneMode.rightFlip, const []),
    );
  });
}
