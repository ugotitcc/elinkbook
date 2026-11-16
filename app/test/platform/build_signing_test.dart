// 建置組合（建置模式＋簽章身分）判定的單元測試（epic-54 後續項目）。

import 'package:elinkbook/platform/build_signing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rel = 'a' * 64;
  final upl = 'b' * 64;
  final fingerprints = SigningFingerprints(release: rel, upload: upl);

  group('resolveSigningIdentity', () {
    test('憑證是 debug → debug 金鑰（不看指紋）', () {
      expect(
        resolveSigningIdentity(
            sha256: 'x', isDebugCert: true, fingerprints: fingerprints),
        SigningIdentity.debug,
      );
    });

    test('指紋對得上登錄值 → 對應金鑰，大小寫不拘', () {
      expect(
        resolveSigningIdentity(
            sha256: rel.toUpperCase(),
            isDebugCert: false,
            fingerprints: fingerprints),
        SigningIdentity.release,
      );
      expect(
        resolveSigningIdentity(
            sha256: upl, isDebugCert: false, fingerprints: fingerprints),
        SigningIdentity.upload,
      );
    });

    test('Google Play 簽署金鑰指紋登錄後可辨識', () {
      final withPlay = SigningFingerprints(playSigning: 'c' * 64);
      expect(
        resolveSigningIdentity(
            sha256: 'c' * 64, isDebugCert: false, fingerprints: withPlay),
        SigningIdentity.playSigning,
      );
    });

    test('指紋未登錄或對不上 → 未知金鑰；空白登錄值不會誤判', () {
      expect(
        resolveSigningIdentity(
            sha256: 'd' * 64, isDebugCert: false, fingerprints: fingerprints),
        SigningIdentity.unknown,
      );
      expect(
        resolveSigningIdentity(
            sha256: '',
            isDebugCert: false,
            fingerprints: const SigningFingerprints()),
        SigningIdentity.unknown,
      );
      expect(
        resolveSigningIdentity(
            sha256: null, isDebugCert: false, fingerprints: fingerprints),
        SigningIdentity.unknown,
      );
    });
  });

  group('buildCombinationNeedsWarning', () {
    test('release＋debug 金鑰、任何模式＋未知金鑰 → 要警告', () {
      expect(
          buildCombinationNeedsWarning(BuildMode.release, SigningIdentity.debug),
          isTrue);
      expect(
          buildCombinationNeedsWarning(
              BuildMode.release, SigningIdentity.unknown),
          isTrue);
      expect(
          buildCombinationNeedsWarning(BuildMode.debug, SigningIdentity.unknown),
          isTrue);
    });

    test('debug＋debug、release＋發佈／上傳／Play 簽署 → 不警告', () {
      expect(
          buildCombinationNeedsWarning(BuildMode.debug, SigningIdentity.debug),
          isFalse);
      for (final id in [
        SigningIdentity.release,
        SigningIdentity.upload,
        SigningIdentity.playSigning,
      ]) {
        expect(buildCombinationNeedsWarning(BuildMode.release, id), isFalse);
      }
    });
  });

  test('SigningFingerprints.fromJson 容忍壞資料並轉小寫', () {
    final ok = SigningFingerprints.fromJson(
        '{"_說明":"x","release":"ABCD","upload":"","playSigning":""}');
    expect(ok.release, 'abcd');
    expect(SigningFingerprints.fromJson('not json').release, '');
    expect(SigningFingerprints.fromJson('[]').release, '');
  });
}
