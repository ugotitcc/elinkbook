// Windows WebView2 環境的單元測試（epic-66 Issue 1 Task 4）。
//
// 真正建立 WebViewEnvironment 需要原生外掛與 WebView2 Runtime，單元測試
// 測不到；這裡只測平台分流（非 Windows 不建立）與使用者資料夾的組合規則。

import 'package:elinkbook/windows/windows_webview_environment.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('非 Windows：init 後 appWebViewEnvironment 仍是 null', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await initAppWebViewEnvironment(userDataFolder: p.join('C:', 'appdata'));

    expect(appWebViewEnvironment, isNull);
  });

  test('windowsWebViewUserDataFolder：以 appSupportPath 為根的 webview_data', () {
    final appSupportPath = p.join('C:', 'Users', '王小明', 'AppData', 'Roaming');

    expect(
      windowsWebViewUserDataFolder(appSupportPath),
      p.join(appSupportPath, 'webview_data'),
    );
  });
}
