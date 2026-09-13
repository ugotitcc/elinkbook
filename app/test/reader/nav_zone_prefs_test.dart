import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/nav_zone_prefs.dart';
import 'package:elinkbook/reader/zone_action.dart';

void main() {
  test('NavZonePrefs.initial() 回傳 rightFlip 模板、debug overlay 關閉', () {
    const prefs = NavZonePrefs.initial();
    expect(prefs.navZoneMode, NavZoneMode.rightFlip);
    expect(prefs.navZoneCustomActions, rightFlipZoneTemplate);
    expect(prefs.showNavZoneDebugOverlay, isFalse);
  });

  test('copyWith 只更新指定欄位，其餘欄位保留原值', () {
    const original = NavZonePrefs.initial();
    final updated = original.copyWith(navZoneMode: NavZoneMode.oneHand);
    expect(updated.navZoneMode, NavZoneMode.oneHand);
    expect(updated.navZoneCustomActions, rightFlipZoneTemplate);
    expect(updated.showNavZoneDebugOverlay, isFalse);
  });

  test('copyWith 可個別更新 navZoneCustomActions／showNavZoneDebugOverlay', () {
    const original = NavZonePrefs.initial();
    const customActions = [
      ZoneAction.menu, ZoneAction.none, ZoneAction.none,
      ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ];
    final updated = original.copyWith(
      navZoneMode: NavZoneMode.custom,
      navZoneCustomActions: customActions,
      showNavZoneDebugOverlay: true,
    );
    expect(updated.navZoneMode, NavZoneMode.custom);
    expect(updated.navZoneCustomActions, customActions);
    expect(updated.showNavZoneDebugOverlay, isTrue);
  });

  test('三個欄位值皆相同的 NavZonePrefs 視為相等', () {
    const a = NavZonePrefs(
      navZoneMode: NavZoneMode.oneHand,
      navZoneCustomActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: true,
    );
    const b = NavZonePrefs(
      navZoneMode: NavZoneMode.oneHand,
      navZoneCustomActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: true,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('navZoneCustomActions 內容不同時視為不相等', () {
    const a = NavZonePrefs(
      navZoneMode: NavZoneMode.custom,
      navZoneCustomActions: [
        ZoneAction.menu, ZoneAction.none, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ],
      showNavZoneDebugOverlay: false,
    );
    const b = NavZonePrefs(
      navZoneMode: NavZoneMode.custom,
      navZoneCustomActions: [
        ZoneAction.none, ZoneAction.none, ZoneAction.menu,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ],
      showNavZoneDebugOverlay: false,
    );
    expect(a == b, isFalse);
  });
}
