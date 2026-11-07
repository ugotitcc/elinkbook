import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_locale.dart';
import '../l10n/app_localizations.dart';
import 'webview2_runtime_check.dart';

/// Windows 缺少 WebView2 Runtime 或環境建立失敗時的獨立說明畫面應用程式。
///
/// 自帶獨立的 [MaterialApp]，完全不依賴 `AppDependencies`，避免在 Runtime 缺失
/// 時提前載入任何 WebView 相關元件。
class WebView2MissingApp extends StatefulWidget {
  const WebView2MissingApp({
    super.key,
    required this.initialResult,
    required this.recheck,
    required this.onReady,
    this.openUrl,
    this.localeOverride,
  });

  /// 首次啟動探測的結果（[WebView2CheckStatus.missing] 或 [WebView2CheckStatus.failed]）。
  final WebView2CheckResult initialResult;

  /// 重新檢查回呼。成功時回傳 [WebView2CheckStatus.ready]。
  final Future<WebView2CheckResult> Function() recheck;

  /// 當檢查通過就緒時的通知回呼（通常呼叫 `runApp(ElinkBookApp(...))` 進入主畫面）。
  final VoidCallback onReady;

  /// 開啟下載網址的回呼。預設呼叫 `url_launcher` 的 [launchUrl]。
  final Future<bool> Function(Uri url)? openUrl;

  /// 語言手動覆寫設定。若為 null 則跟隨系統語言解析。
  final Locale? localeOverride;

  @override
  State<WebView2MissingApp> createState() => _WebView2MissingAppState();
}

class _WebView2MissingAppState extends State<WebView2MissingApp> {
  late WebView2CheckResult _currentResult;
  bool _checking = false;
  bool _hasRechecked = false;

  @override
  void initState() {
    super.initState();
    _currentResult = widget.initialResult;
  }

  Future<void> _handleOpenUrl() async {
    final url = Uri.parse(kWebView2DownloadUrl);
    try {
      final launcher = widget.openUrl ??
          (u) => launchUrl(u, mode: LaunchMode.externalApplication);
      await launcher(url);
    } catch (_) {
      // 保持靜默，網址已在畫面上以 SelectableText 顯示供手動複製
    }
  }

  Future<void> _handleRecheck() async {
    if (_checking) return;
    setState(() => _checking = true);

    try {
      final result = await widget.recheck();
      if (!mounted) return;

      if (result.isReady) {
        // Ruling 4: 成功進入就緒狀態：立即呼叫 onReady，且保持 _checking == true，
        // 絕不重新啟用按鈕，靜待 runApp 替換根樹。
        widget.onReady();
        return;
      }

      setState(() {
        _currentResult = result;
        _hasRechecked = true;
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentResult = WebView2CheckResult.failed(e.toString());
        _hasRechecked = true;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: widget.localeOverride,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: (deviceLocales, _) =>
          resolveMaterialAppLocale(deviceLocales),
      // 跟隨系統深／淺色；顏色一律取自 colorScheme，不寫死色票
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.system_update,
                        size: 64,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.webview2MissingTitle,
                        key: const Key('webview2_missing_title'),
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _currentResult.status == WebView2CheckStatus.failed
                            ? l10n.webview2FailedBody
                            : l10n.webview2MissingBody,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      if (_currentResult.status == WebView2CheckStatus.failed &&
                          _currentResult.detail != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.webview2DetailLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                _currentResult.detail!,
                                key: const Key('webview2_detail_text'),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: scheme.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_hasRechecked && !_currentResult.isReady) ...[
                        const SizedBox(height: 16),
                        Text(
                          l10n.webview2StillMissing,
                          key: const Key('webview2_still_missing_text'),
                          style: TextStyle(
                            color: scheme.tertiary,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 28),
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            key: const Key('webview2_download_button'),
                            onPressed: _handleOpenUrl,
                            icon: const Icon(Icons.open_in_browser),
                            label: Text(l10n.webview2DownloadButton),
                          ),
                          ElevatedButton.icon(
                            key: const Key('webview2_recheck_button'),
                            onPressed: _checking ? null : _handleRecheck,
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.webview2RecheckButton),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: SelectableText(
                          kWebView2DownloadUrl,
                          key: const Key('webview2_url_text'),
                          style: TextStyle(
                            color: scheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
