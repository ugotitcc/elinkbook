import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_localizations.dart';
import '../platform/build_signing.dart';
import '../platform/platform_support.dart';

const _appInfoChannel = MethodChannel('elinkbook/app_info');

/// 應用程式「關於」頁面（FR-29）：顯示版本號、開源授權清單入口、Android
/// 系統 WebView 版本（因 Readium 內部走 WebView，供除錯用）。獨立畫面，
/// 不涉及 books/groups 資料表（見 docs/epics/epic-1-library/spec.md）。
class AboutScreen extends StatefulWidget {
  /// 載入簽章指紋對照表；預設讀 `config/signing_fingerprints.json` 資產，
  /// 測試可注入替身。
  final Future<SigningFingerprints> Function()? loadFingerprints;

  const AboutScreen({super.key, this.loadFingerprints});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

enum _AsyncTextStatus { loading, error }

/// 原生端回報的實際簽章身分與打包進去的 OAuth Client ID 前綴。
class _BuildSigning {
  final SigningIdentity identity;
  final String oauthPrefix;
  const _BuildSigning(this.identity, this.oauthPrefix);
}

Future<SigningFingerprints> _loadFingerprintsAsset() async {
  try {
    return SigningFingerprints.fromJson(
      await rootBundle.loadString('config/signing_fingerprints.json'),
    );
  } catch (_) {
    return const SigningFingerprints();
  }
}

class _AboutScreenState extends State<AboutScreen> {
  Object _versionInfo = _AsyncTextStatus.loading;
  String? _versionForLicensePage;
  Object _webViewVersionInfo = _AsyncTextStatus.loading;
  Object _buildTimeInfo = _AsyncTextStatus.loading;
  Object _buildSigning = _AsyncTextStatus.loading;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadWebViewVersion();
    _loadBuildTime();
    // 簽章資訊只有 Android 有（Windows 沒有簽章金鑰，只顯示建置模式）。
    if (isAndroidPlatform) _loadBuildSigning();
  }

  Future<void> _loadBuildSigning() async {
    try {
      final raw = await _appInfoChannel.invokeMapMethod<String, Object?>(
        'getBuildSigningInfo',
      );
      if (raw == null) throw StateError('no signing info');
      final fingerprints =
          await (widget.loadFingerprints ?? _loadFingerprintsAsset)();
      final identity = resolveSigningIdentity(
        sha256: raw['signingSha256'] as String?,
        isDebugCert: raw['isDebugCert'] == true,
        fingerprints: fingerprints,
      );
      if (!mounted) return;
      setState(
        () => _buildSigning = _BuildSigning(
          identity,
          (raw['googleClientIdPrefix'] as String?) ?? '',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _buildSigning = _AsyncTextStatus.error);
    }
  }

  String _signingLabel(SigningIdentity identity, AppLocalizations l10n) {
    return switch (identity) {
      SigningIdentity.debug => l10n.aboutSigningDebug,
      SigningIdentity.release => l10n.aboutSigningRelease,
      SigningIdentity.upload => l10n.aboutSigningUpload,
      SigningIdentity.playSigning => l10n.aboutSigningPlay,
      SigningIdentity.unknown => l10n.aboutSigningUnknown,
    };
  }

  /// 「建置資訊」列的顯示文字：Android 為「模式｜簽章：身分」（需警示時尾端加 ⚠），
  /// 其他平台只有模式。
  String _buildInfoText(AppLocalizations l10n) {
    final mode = currentBuildMode.name;
    if (!isAndroidPlatform) return mode;
    final value = _buildSigning;
    if (value is _BuildSigning) {
      final text = l10n.aboutScreenBuildInfoValue(
        mode,
        _signingLabel(value.identity, l10n),
      );
      return buildCombinationNeedsWarning(currentBuildMode, value.identity)
          ? '$text ⚠'
          : text;
    }
    return _resolveAsyncText(value, l10n);
  }

  String _oauthText(AppLocalizations l10n) {
    final value = _buildSigning;
    if (value is _BuildSigning) {
      return l10n.aboutScreenOAuthValue(value.oauthPrefix);
    }
    return _resolveAsyncText(value, l10n);
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionInfo = '${info.version} (build ${info.buildNumber})';
        _versionForLicensePage = info.version;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionInfo = _AsyncTextStatus.error);
    }
  }

  Future<void> _loadBuildTime() async {
    try {
      final buildTime = await _appInfoChannel.invokeMethod<String>(
        'getBuildTime',
      );
      if (!mounted) return;
      setState(
        () => _buildTimeInfo = buildTime ?? _AsyncTextStatus.error,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _buildTimeInfo = _AsyncTextStatus.error);
    }
  }

  Future<void> _loadWebViewVersion() async {
    try {
      final version = await _appInfoChannel.invokeMethod<String>(
        'getSystemWebViewVersion',
      );
      if (!mounted) return;
      setState(
        () => _webViewVersionInfo = version ?? _AsyncTextStatus.error,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _webViewVersionInfo = _AsyncTextStatus.error);
    }
  }

  /// 只在 `build()` 執行期間呼叫，把非同步查詢的原始結果狀態
  /// （[_AsyncTextStatus.loading]／[_AsyncTextStatus.error]／實際載入成功
  /// 的 `String`）轉譯成目前介面語言的顯示文字。
  String _resolveAsyncText(Object value, AppLocalizations l10n) {
    if (value is String) return value;
    return switch (value as _AsyncTextStatus) {
      _AsyncTextStatus.loading => l10n.aboutScreenLoadingText,
      _AsyncTextStatus.error => l10n.aboutScreenUnavailableText,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final versionText = _versionInfo == _AsyncTextStatus.error
        ? l10n.aboutScreenFailedToLoadVersionMessage
        : _resolveAsyncText(_versionInfo, l10n);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutScreenTitle)),
      body: ListView(
        children: [
          ListTile(
            title: Text(l10n.aboutScreenVersionLabel),
            subtitle: Text(
              versionText,
              key: const Key('about_screen_version_text'),
            ),
          ),
          ListTile(
            title: Text(l10n.aboutScreenBuildTimeLabel),
            subtitle: Text(
              _resolveAsyncText(_buildTimeInfo, l10n),
              key: const Key('about_screen_build_time_text'),
            ),
          ),
          ListTile(
            title: Text(l10n.aboutScreenBuildInfoLabel),
            subtitle: Text(
              _buildInfoText(l10n),
              key: const Key('about_screen_build_info_text'),
            ),
          ),
          if (isAndroidPlatform)
            ListTile(
              title: Text(l10n.aboutScreenOAuthLabel),
              subtitle: Text(
                _oauthText(l10n),
                key: const Key('about_screen_oauth_text'),
              ),
            ),
          ListTile(
            title: Text(l10n.aboutScreenWebViewVersionLabel),
            subtitle: Text(
              _resolveAsyncText(_webViewVersionInfo, l10n),
              key: const Key('about_screen_webview_version_text'),
            ),
          ),
          ListTile(
            key: const Key('about_screen_view_licenses_button'),
            title: Text(l10n.aboutScreenViewLicensesButton),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'elinkBook',
                applicationVersion: _versionForLicensePage,
                applicationLegalese: l10n.aboutScreenLicensesLegalese,
              );
            },
          ),
        ],
      ),
    );
  }
}
