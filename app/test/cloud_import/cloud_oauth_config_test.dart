import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_oauth_config.dart';

void main() {
  test('googleClientId 未提供 --dart-define 時回退為樣板 placeholder 值', () {
    expect(
      CloudOAuthConfig.googleClientId,
      'YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com',
    );
  });

  test('googleRedirectScheme 由 googleClientId 正確推導出反向網域格式', () {
    expect(
      CloudOAuthConfig.googleRedirectScheme,
      'com.googleusercontent.apps.YOUR_GOOGLE_OAUTH_CLIENT_ID',
    );
  });

  test('googleRedirectUri 由 googleRedirectScheme 正確組成', () {
    expect(
      CloudOAuthConfig.googleRedirectUri,
      'com.googleusercontent.apps.YOUR_GOOGLE_OAUTH_CLIENT_ID:/oauth2redirect',
    );
  });

  test('oneDriveClientId 未提供 --dart-define 時回退為樣板 placeholder 值', () {
    expect(CloudOAuthConfig.oneDriveClientId, 'YOUR_ONEDRIVE_OAUTH_CLIENT_ID');
  });

  test('oneDriveRedirectScheme 由 oneDriveClientId 正確推導出 MSAL 格式', () {
    expect(
      CloudOAuthConfig.oneDriveRedirectScheme,
      'msalYOUR_ONEDRIVE_OAUTH_CLIENT_ID',
    );
  });

  test('oneDriveRedirectUri 由 oneDriveRedirectScheme 正確組成', () {
    expect(
      CloudOAuthConfig.oneDriveRedirectUri,
      'msalYOUR_ONEDRIVE_OAUTH_CLIENT_ID://auth',
    );
  });
}
