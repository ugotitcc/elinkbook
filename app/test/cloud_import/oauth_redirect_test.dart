import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/oauth_redirect.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('非 Windows：沿用手機慣例的 redirect URI 與 scheme，不開本機埠', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final r = await resolveOAuthRedirect(
      mobileRedirectUri: 'msalabc://auth',
      mobileScheme: 'msalabc',
      pickPort: () async => fail('非 Windows 不應該挑埠'),
    );
    expect(r.redirectUri, 'msalabc://auth');
    expect(r.callbackUrlScheme, 'msalabc');
    expect(r.options.useWebview, isTrue);
  });

  test('Windows：改走 http://localhost:{埠} 並關閉內嵌 WebView', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final r = await resolveOAuthRedirect(
      mobileRedirectUri: 'msalabc://auth',
      mobileScheme: 'msalabc',
      pickPort: () async => 50123,
    );
    expect(r.redirectUri, 'http://localhost:50123');
    expect(r.callbackUrlScheme, 'http://localhost:50123');
    expect(r.options.useWebview, isFalse);
  });

  test('預設挑埠：回傳可用的本機埠（非 0）', () async {
    final port = await pickFreeLoopbackPort();
    expect(port, greaterThan(0));
  });
}
