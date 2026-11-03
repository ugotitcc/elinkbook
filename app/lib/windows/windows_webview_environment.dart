// Windows 的 WebView2 環境建立與全域存取（epic-66 Issue 1 Task 4）。
//
// `flutter_inappwebview` 的 Windows 實作（`flutter_inappwebview_windows`
// 0.6.0）在建立 WebView2 環境時可用 [WebViewEnvironmentSettings.userDataFolder]
// 指定使用者資料夾；不指定時 WebView2 會把預設資料夾放在可執行檔旁，
// 而 `flutter build` 的產物目錄可能被清理，導致 Cookie／快取遺失。
//
// 建立需要原生外掛與 WebView2 Runtime，因此只能在執行期（真機／Windows
// 桌面）呼叫；單元測試只驗證平台分流與資料夾組合（見
// `test/windows/windows_webview_environment_test.dart`）。

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import '../platform/platform_support.dart';

/// App 全域共用的 WebView2 環境；未建立（非 Windows 平台或尚未初始化）
/// 時為 `null`。由 [initAppWebViewEnvironment] 在 `runApp` 之前設定，
/// 供 `InAppWebView`／`HeadlessInAppWebView` 以 `webViewEnvironment` 傳入。
WebViewEnvironment? appWebViewEnvironment;

/// WebView2 使用者資料夾：`<appSupportPath>/webview_data`。
///
/// 抽成獨立函式是為了讓單元測試不必真的建立 WebView 環境就能驗證組合規則
/// （根目錄以 `%APPDATA%` 下的 App 資料夾為準，由呼叫端傳入）。
String windowsWebViewUserDataFolder(String appSupportPath) =>
    p.join(appSupportPath, 'webview_data');

/// 建立 Windows 的 WebView2 環境並存入 [appWebViewEnvironment]。
///
/// [userDataFolder] 是 App 資料夾根目錄（`getApplicationSupportDirectory()`
/// 的路徑），實際使用者資料夾由 [windowsWebViewUserDataFolder] 組合。
/// 非 Windows 平台呼叫時什麼都不做，[appWebViewEnvironment] 保持 `null`——
/// 平台判斷走 `defaultTargetPlatform`，不用 `dart:io` 的 `Platform`。
Future<void> initAppWebViewEnvironment({required String userDataFolder}) async {
  if (!isWindowsPlatform) return;
  appWebViewEnvironment = await WebViewEnvironment.create(
    settings: WebViewEnvironmentSettings(
      userDataFolder: windowsWebViewUserDataFolder(userDataFolder),
    ),
  );
}
