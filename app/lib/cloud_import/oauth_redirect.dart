// OAuth 重新導向設定（epic-66 Issue 31）。
//
// Android：沿用自訂 scheme（Google 反向用戶端 ID、OneDrive `msal<id>://auth`）。
// Windows：自訂 scheme 無法使用，改走「系統瀏覽器＋本機 loopback」——
// `http://localhost:{埠}`，並關閉 flutter_web_auth_2 預設的內嵌 WebView
//（Google 政策禁止在內嵌 WebView 登入）。redirect_uri 在授權請求與換 token
// 請求必須一致，所以由呼叫端把同一個結果用在兩處。

import 'dart:io';

import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../platform/platform_support.dart';

class OAuthRedirect {
  const OAuthRedirect({
    required this.redirectUri,
    required this.callbackUrlScheme,
    required this.options,
  });

  /// 帶進授權請求與換 token 請求的 `redirect_uri`。
  final String redirectUri;

  /// 傳給 [FlutterWebAuth2.authenticate] 的 `callbackUrlScheme`。
  final String callbackUrlScheme;

  /// 傳給 [FlutterWebAuth2.authenticate] 的 `options`。
  final FlutterWebAuth2Options options;
}

/// 向系統要一個目前可用的本機埠（綁 127.0.0.1:0 後立即關閉）。
Future<int> pickFreeLoopbackPort() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close();
  return port;
}

/// 依平台決定 OAuth 重新導向方式。[pickPort] 供測試注入。
Future<OAuthRedirect> resolveOAuthRedirect({
  required String mobileRedirectUri,
  required String mobileScheme,
  Future<int> Function()? pickPort,
}) async {
  if (!isWindowsPlatform) {
    return OAuthRedirect(
      redirectUri: mobileRedirectUri,
      callbackUrlScheme: mobileScheme,
      options: const FlutterWebAuth2Options(),
    );
  }
  final port = await (pickPort ?? pickFreeLoopbackPort)();
  final loopback = 'http://localhost:$port';
  return OAuthRedirect(
    redirectUri: loopback,
    callbackUrlScheme: loopback,
    options: const FlutterWebAuth2Options(useWebview: false),
  );
}
