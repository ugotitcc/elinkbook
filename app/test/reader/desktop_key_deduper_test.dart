import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/desktop_key_deduper.dart';

void main() {
  group('DesktopKeyDeduper', () {
    test('同一鍵不同來源在 50ms 內第二次被擋；超過 50ms 則放行', () {
      var currentMs = 1000;
      final deduper = DesktopKeyDeduper(nowMs: () => currentMs);

      // 來源 1: flutter
      expect(deduper.shouldHandle('arrowright', DesktopKeySource.flutter), isTrue);

      // 30ms 後來自來源 2: web -> 應被擋
      currentMs = 1030;
      expect(deduper.shouldHandle('arrowright', DesktopKeySource.web), isFalse);

      // 51ms 後 (1000 + 51) 來自來源 2: web -> 應放行
      currentMs = 1051;
      expect(deduper.shouldHandle('arrowright', DesktopKeySource.web), isTrue);
    });

    test('同一來源連續按鍵（按住不放／連發）永遠放行', () {
      var currentMs = 1000;
      final deduper = DesktopKeyDeduper(nowMs: () => currentMs);

      expect(deduper.shouldHandle('arrowright', DesktopKeySource.web), isTrue);

      currentMs = 1010;
      expect(deduper.shouldHandle('arrowright', DesktopKeySource.web), isTrue);

      currentMs = 1020;
      expect(deduper.shouldHandle('arrowright', DesktopKeySource.web), isTrue);
    });

    test('不同按鍵互不影響', () {
      var currentMs = 1000;
      final deduper = DesktopKeyDeduper(nowMs: () => currentMs);

      expect(deduper.shouldHandle('arrowright', DesktopKeySource.flutter), isTrue);

      // 10ms 後另一個鍵來自 web -> 應放行
      currentMs = 1010;
      expect(deduper.shouldHandle('arrowleft', DesktopKeySource.web), isTrue);
    });
  });

  group('logicalKeyForWebKey 與 canonicalKeyId', () {
    test('標準按鍵映射驗證', () {
      expect(logicalKeyForWebKey('ArrowLeft'), LogicalKeyboardKey.arrowLeft);
      expect(logicalKeyForWebKey('ArrowRight'), LogicalKeyboardKey.arrowRight);
      expect(logicalKeyForWebKey('ArrowUp'), LogicalKeyboardKey.arrowUp);
      expect(logicalKeyForWebKey('ArrowDown'), LogicalKeyboardKey.arrowDown);
      expect(logicalKeyForWebKey('PageUp'), LogicalKeyboardKey.pageUp);
      expect(logicalKeyForWebKey('PageDown'), LogicalKeyboardKey.pageDown);
      expect(logicalKeyForWebKey(' '), LogicalKeyboardKey.space);
      expect(logicalKeyForWebKey('Home'), LogicalKeyboardKey.home);
      expect(logicalKeyForWebKey('End'), LogicalKeyboardKey.end);
      expect(logicalKeyForWebKey('F11'), LogicalKeyboardKey.f11);
      expect(logicalKeyForWebKey('Escape'), LogicalKeyboardKey.escape);
    });

    test('f 與 F 兩者皆映射為 keyF（CapsLock 支援）', () {
      expect(logicalKeyForWebKey('f'), LogicalKeyboardKey.keyF);
      expect(logicalKeyForWebKey('F'), LogicalKeyboardKey.keyF);
    });

    test('未知鍵回傳 null', () {
      expect(logicalKeyForWebKey('UnknownKey'), isNull);
      expect(logicalKeyForWebKey('Enter'), isNull);
      expect(logicalKeyForWebKey('a'), isNull);
    });

    test('canonicalKeyId 對相同 LogicalKeyboardKey 產出一致字串', () {
      expect(canonicalKeyId(LogicalKeyboardKey.arrowRight),
          canonicalKeyId(logicalKeyForWebKey('ArrowRight')!));
      expect(canonicalKeyId(LogicalKeyboardKey.keyF),
          canonicalKeyId(logicalKeyForWebKey('F')!));
    });
  });
}
