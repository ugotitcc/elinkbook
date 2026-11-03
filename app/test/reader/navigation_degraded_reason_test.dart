import 'package:elinkbook/reader/navigation_degraded_reason.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseNavigationDegradedReason', () {
    test('readingPosition 與 annotation 各自對應', () {
      expect(parseNavigationDegradedReason(['readingPosition']),
          NavigationDegradedReason.readingPosition);
      expect(parseNavigationDegradedReason(['annotation']),
          NavigationDegradedReason.annotation);
    });

    test('空參數、非字串、未知字串都回傳 null 且不拋例外', () {
      expect(parseNavigationDegradedReason(const []), isNull);
      expect(parseNavigationDegradedReason([42]), isNull);
      expect(parseNavigationDegradedReason([null]), isNull);
      expect(parseNavigationDegradedReason(['somethingElse']), isNull);
    });
  });
}
