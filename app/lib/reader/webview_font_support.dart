import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 系統 WebView 能載入的網頁字型大小（epic-49 Issue 7）。
///
/// Chromium 的 `web_font_decoder.cc` 會拒絕超過上限的網頁字型，console 訊息為
/// `OTS parsing error: Web font size more than 30MB`，畫面退回系統字型。上限在
/// Chromium commit 3c603c19be（Cr-Commit-Position #1040311，落在 M107）由 30MB
/// 放寬為 128MB。Issue 5 真機驗證：WebView 91 拒絕思源宋體（57.1MB），WebView 154 正常。

/// 上限放寬為 128MB 的第一個 Chromium 主版本。
const int kWebViewLargeFontMinMajorVersion = 107;

/// WebView 106 以前的網頁字型上限。
const int kLegacyWebFontSizeLimitBytes = 30 * 1024 * 1024;

/// WebView 107 起的網頁字型上限。
const int kWebFontSizeLimitBytes = 128 * 1024 * 1024;

/// 從 WebView 的預設 User-Agent 取出 `Chrome/NN` 的 Chromium 主版本號；找不到時回傳 null。
///
/// 刻意不用 WebView 套件的 versionName：部分廠商 WebView（例如沒有 Google 服務的
/// 華為裝置上的 com.huawei.webview）用自己的版本編號，第一段不是 Chromium 版本，
/// 會把新 WebView 誤判成舊的（程式審查 I-1）。UA 的 Chrome/NN 才是真正的核心版本。
int? parseChromeMajorVersion(String? userAgent) {
  if (userAgent == null) return null;
  final match = RegExp(r'Chrome/(\d+)').firstMatch(userAgent);
  return match == null ? null : int.parse(match.group(1)!);
}

/// 這個 WebView 能不能載入 [fontSizeBytes] 大小的字型。
///
/// [webViewMajorVersion] 為 null（讀不到版本）時視同支援：讀不到多半是平台呼叫失敗，
/// 不代表 WebView 舊；視同支援最壞只是回到 Issue 7 之前的行為（計畫決定 2）。
/// Chromium 以「大於上限」才拒絕，所以剛好等於上限可以載入。
bool webViewCanLoadFont({
  required int? webViewMajorVersion,
  required int fontSizeBytes,
}) {
  if (webViewMajorVersion == null) return true;
  final limit = webViewMajorVersion >= kWebViewLargeFontMinMajorVersion
      ? kWebFontSizeLimitBytes
      : kLegacyWebFontSizeLimitBytes;
  return fontSizeBytes <= limit;
}

/// 從系統 WebView 的預設 User-Agent 讀取 Chromium 主版本號。任何失敗（沒有平台實作、
/// 例外、逾時）都回傳 null，不往外拋：這在 App 啟動時呼叫，不能擋住啟動。
/// [readUserAgent] 只供測試注入。
Future<int?> readWebViewMajorVersion({
  Future<String?> Function()? readUserAgent,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final read = readUserAgent ?? InAppWebViewController.getDefaultUserAgent;
  try {
    return parseChromeMajorVersion(await read().timeout(timeout));
  } catch (e) {
    debugPrint('Failed to read WebView version: $e');
    return null;
  }
}
