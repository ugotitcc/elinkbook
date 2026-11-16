// 建置組合判定（epic-54 後續項目）。
//
// 「建置組合」＝建置模式（debug／profile／release）＋簽章身分（實際被哪一把金鑰簽的）。
// 目標是任何一個裝在裝置上的版本，都能在「關於」頁一眼看出它是哪一種組合。
// 簽章身分以 APK 實際的簽章憑證判定（原生端讀取），不是建置時的宣告；對照用的公開
// 指紋放在 app/config/signing_fingerprints.json（見該檔說明）。

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 目前這份 App 的建置模式。
enum BuildMode { debug, profile, release }

BuildMode get currentBuildMode => kReleaseMode
    ? BuildMode.release
    : kProfileMode
        ? BuildMode.profile
        : BuildMode.debug;

/// APK 實際的簽章身分。
enum SigningIdentity { debug, release, upload, playSigning, unknown }

/// 各金鑰憑證的 SHA-256 指紋（小寫十六進位、不含冒號）。空字串代表尚未登錄。
@immutable
class SigningFingerprints {
  final String release;
  final String upload;
  final String playSigning;

  const SigningFingerprints({
    this.release = '',
    this.upload = '',
    this.playSigning = '',
  });

  /// 容忍壞資料：解析失敗或格式不符一律回傳全空（顯示為未知金鑰），不拋例外。
  factory SigningFingerprints.fromJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return const SigningFingerprints();
      String read(String key) {
        final value = decoded[key];
        return value is String ? value.trim().toLowerCase() : '';
      }

      return SigningFingerprints(
        release: read('release'),
        upload: read('upload'),
        playSigning: read('playSigning'),
      );
    } catch (_) {
      return const SigningFingerprints();
    }
  }
}

/// 憑證 → 簽章身分。debug 憑證優先判定（各開發機的 debug 金鑰不同，不登錄指紋）；
/// 其餘比對登錄的指紋。空白登錄值絕不拿來比對。
SigningIdentity resolveSigningIdentity({
  required String? sha256,
  required bool isDebugCert,
  required SigningFingerprints fingerprints,
}) {
  if (isDebugCert) return SigningIdentity.debug;
  final actual = (sha256 ?? '').toLowerCase();
  if (actual.isEmpty) return SigningIdentity.unknown;
  if (actual == fingerprints.release && fingerprints.release.isNotEmpty) {
    return SigningIdentity.release;
  }
  if (actual == fingerprints.upload && fingerprints.upload.isNotEmpty) {
    return SigningIdentity.upload;
  }
  if (actual == fingerprints.playSigning &&
      fingerprints.playSigning.isNotEmpty) {
    return SigningIdentity.playSigning;
  }
  return SigningIdentity.unknown;
}

/// 這個組合是否需要在畫面上加警示：release 模式卻用 debug 金鑰（不能上架、無法覆蓋
/// 正式版），或簽章身分不明。
bool buildCombinationNeedsWarning(BuildMode mode, SigningIdentity identity) {
  if (identity == SigningIdentity.unknown) return true;
  return mode == BuildMode.release && identity == SigningIdentity.debug;
}
