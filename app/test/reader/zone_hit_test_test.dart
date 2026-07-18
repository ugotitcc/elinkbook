import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/zone_hit_test.dart';

void main() {
  group('hitTestZoneIndex()', () {
    const width = 300.0;
    const height = 300.0;

    test('左上角 (0,0) 回傳格子 0', () {
      expect(hitTestZoneIndex(dx: 0, dy: 0, width: width, height: height), 0);
    });

    test('正中心回傳格子 4', () {
      expect(
        hitTestZoneIndex(dx: 150, dy: 150, width: width, height: height),
        4,
      );
    });

    test('右上角（寬度邊界內）回傳格子 2', () {
      expect(
        hitTestZoneIndex(dx: 299, dy: 0, width: width, height: height),
        2,
      );
    });

    test('左下角（高度邊界內）回傳格子 6', () {
      expect(
        hitTestZoneIndex(dx: 0, dy: 299, width: width, height: height),
        6,
      );
    });

    test('右下角（寬高邊界內）回傳格子 8', () {
      expect(
        hitTestZoneIndex(dx: 299, dy: 299, width: width, height: height),
        8,
      );
    });

    test('dx 恰好等於 width（浮點邊界）仍 clamp 在格子 2，不產生 index 9', () {
      expect(
        hitTestZoneIndex(dx: 300, dy: 0, width: width, height: height),
        2,
      );
    });

    test('dy 恰好等於 height（浮點邊界）仍 clamp 在格子 6，不產生超界', () {
      expect(
        hitTestZoneIndex(dx: 0, dy: 300, width: width, height: height),
        6,
      );
    });

    test('第一條格線正上方座標 (dx=100) 歸屬 col 1', () {
      expect(
        hitTestZoneIndex(dx: 100, dy: 150, width: width, height: height),
        4,
      );
    });

    test('第二條格線正上方座標 (dx=200) 歸屬 col 2', () {
      expect(
        hitTestZoneIndex(dx: 200, dy: 150, width: width, height: height),
        5,
      );
    });

    test(
        'width 或 height 為 0 或負數時，安全回傳格子 4，不拋出例外'
        '（審查修正：避免除以 0 產生 NaN/Infinity 導致 .floor() 拋出 UnsupportedError）',
        () {
      expect(hitTestZoneIndex(dx: 10, dy: 10, width: 0, height: 300), 4);
      expect(hitTestZoneIndex(dx: 10, dy: 10, width: 300, height: 0), 4);
      expect(hitTestZoneIndex(dx: 10, dy: 10, width: -1, height: 300), 4);
      expect(hitTestZoneIndex(dx: 10, dy: 10, width: 300, height: -1), 4);
    });
  });
}
