import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('positionKey：只代表「位置」，忽略會抖動的 fraction', () {
    test('同 cfi 與 index、fraction 不同，鍵相同', () {
      const a = EpubPositionInfo(
        locatorJson: '{"cfi":"x","index":2,"fraction":0.10}',
      );
      const b = EpubPositionInfo(
        locatorJson: '{"cfi":"x","index":2,"fraction":0.11}',
      );
      expect(a.positionKey, b.positionKey);
    });

    test('cfi 不同，鍵不同', () {
      const a = EpubPositionInfo(locatorJson: '{"cfi":"x","index":2}');
      const b = EpubPositionInfo(locatorJson: '{"cfi":"y","index":2}');
      expect(a.positionKey, isNot(b.positionKey));
    });

    test('cfi 相同但 index 不同，鍵不同', () {
      const a = EpubPositionInfo(locatorJson: '{"cfi":"x","index":2}');
      const b = EpubPositionInfo(locatorJson: '{"cfi":"x","index":3}');
      expect(a.positionKey, isNot(b.positionKey));
    });

    test('不是合法 JSON 時退回整段字串（字串相同鍵相同、不同鍵不同）', () {
      const a = EpubPositionInfo(locatorJson: 'not json');
      const same = EpubPositionInfo(locatorJson: 'not json');
      const other = EpubPositionInfo(locatorJson: 'other');
      expect(a.positionKey, 'not json');
      expect(a.positionKey, same.positionKey);
      expect(a.positionKey, isNot(other.positionKey));
    });

    test('合法 JSON 但不是物件（例如陣列）時退回整段字串', () {
      const a = EpubPositionInfo(locatorJson: '[1,2]');
      expect(a.positionKey, '[1,2]');
    });

    test('locatorJson 為空字串時退回空字串，不拋例外', () {
      const a = EpubPositionInfo(locatorJson: '');
      expect(a.positionKey, '');
    });

    test('locatorJson 為空物件時鍵為 null|null，且彼此相同', () {
      const a = EpubPositionInfo(locatorJson: '{}');
      const b = EpubPositionInfo(locatorJson: '{}');
      expect(a.positionKey, 'null|null');
      expect(a.positionKey, b.positionKey);
    });
  });
}
