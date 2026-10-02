import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_auth_classifier.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';

void main() {
  group('isRefreshTokenRejected', () {
    test('400 與 401 代表授權已被撤銷', () {
      expect(isRefreshTokenRejected(400), isTrue);
      expect(isRefreshTokenRejected(401), isTrue);
    });

    test('403、429、500、503 屬權限或暫時性限制，不算撤銷', () {
      expect(isRefreshTokenRejected(403), isFalse);
      expect(isRefreshTokenRejected(429), isFalse);
      expect(isRefreshTokenRejected(500), isFalse);
      expect(isRefreshTokenRejected(503), isFalse);
    });

    test('200 不算撤銷', () {
      expect(isRefreshTokenRejected(200), isFalse);
    });
  });

  group('throwCloudApiStatusError', () {
    test('401 拋出 CloudAuthRequiredException', () {
      expect(
        () => throwCloudApiStatusError('目錄讀取失敗', 401),
        throwsA(isA<CloudAuthRequiredException>()),
      );
    });

    test('403 與 500 拋出一般例外，訊息帶狀態碼，且不是 CloudAuthRequiredException', () {
      for (final code in [403, 500]) {
        expect(
          () => throwCloudApiStatusError('目錄讀取失敗', code),
          throwsA(
            predicate(
              (e) =>
                  e is Exception &&
                  e is! CloudAuthRequiredException &&
                  e.toString().contains('目錄讀取失敗（HTTP $code）'),
            ),
          ),
        );
      }
    });
  });
}
