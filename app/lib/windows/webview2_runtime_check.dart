import 'dart:async';

/// 微軟官方 Edge WebView2 Runtime 下載頁面。
const String kWebView2DownloadUrl =
    'https://developer.microsoft.com/microsoft-edge/webview2/';

/// WebView2 Runtime 檢查狀態。
enum WebView2CheckStatus {
  /// 偵測到 Runtime 且環境建立成功，可正常開書。
  ready,

  /// 偵測不到 Runtime（未安裝或版本為空）。
  missing,

  /// 偵測時拋出例外、環境建立失敗或逾時。
  failed,
}

/// WebView2 啟動檢查結果。
class WebView2CheckResult {
  const WebView2CheckResult.ready(String this.version)
      : status = WebView2CheckStatus.ready,
        detail = null;

  const WebView2CheckResult.missing()
      : status = WebView2CheckStatus.missing,
        version = null,
        detail = null;

  const WebView2CheckResult.failed(String this.detail)
      : status = WebView2CheckStatus.failed,
        version = null;

  final WebView2CheckStatus status;
  final String? version;
  final String? detail;

  bool get isReady => status == WebView2CheckStatus.ready;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebView2CheckResult &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          version == other.version &&
          detail == other.detail;

  @override
  int get hashCode => Object.hash(status, version, detail);

  @override
  String toString() =>
      'WebView2CheckResult(status: $status, version: $version, detail: $detail)';
}

/// 探測本機 WebView2 版本的函式型別。
typedef WebView2VersionProbe = Future<String?> Function();

/// 建立 WebView2 執行環境的函式型別。
typedef WebView2EnvironmentCreator = Future<void> Function();

/// 啟動檢查與環境建立純邏輯。
///
/// 1. 呼叫 [probe] 探測 Runtime 版本：
///    - 若拋出例外，轉為 [WebView2CheckResult.failed]；
///    - 若回傳 null、空字串或純空白，視為未安裝，回傳 [WebView2CheckResult.missing]，
///      且不呼叫 [createEnvironment]；
/// 2. 若探測到有效版本，呼叫 [createEnvironment] 建立環境：
///    - 逾時（預設 60 秒）或拋出例外時轉為 [WebView2CheckResult.failed]；
///    - 成功完成時回傳 [WebView2CheckResult.ready]。
Future<WebView2CheckResult> checkAndInitWebView2({
  required WebView2VersionProbe probe,
  required WebView2EnvironmentCreator createEnvironment,
  Duration createTimeout = const Duration(seconds: 60),
}) async {
  final String? rawVersion;
  try {
    rawVersion = await probe();
  } catch (e) {
    return WebView2CheckResult.failed(e.toString());
  }

  if (rawVersion == null || rawVersion.trim().isEmpty) {
    return const WebView2CheckResult.missing();
  }

  final version = rawVersion.trim();
  final envFuture = createEnvironment();

  try {
    await envFuture.timeout(createTimeout);
  } on TimeoutException {
    // Ruling 3: 避免逾時後背景的延遲非同步例外冒泡成未處理例外
    envFuture.catchError((_) {});
    // 技術識別訊息（英文），畫面上由 l10n 標籤「錯誤詳情」包裝
    return WebView2CheckResult.failed(
      'WebView2 environment creation timed out after ${createTimeout.inSeconds}s',
    );
  } catch (e) {
    return WebView2CheckResult.failed(e.toString());
  }

  return WebView2CheckResult.ready(version);
}
