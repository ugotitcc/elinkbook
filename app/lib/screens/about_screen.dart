import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _appInfoChannel = MethodChannel('elinkbook/app_info');

/// 應用程式「關於」頁面（FR-29）：顯示版本號、開源授權清單入口、Android
/// 系統 WebView 版本（因 Readium 內部走 WebView，供除錯用）。獨立畫面，
/// 不涉及 books/groups 資料表（見 docs/epics/epic-1-library/spec.md）。
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _versionText = '讀取中...';
  String? _versionForLicensePage;
  String _webViewVersion = '讀取中...';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadWebViewVersion();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionText = '${info.version} (build ${info.buildNumber})';
        _versionForLicensePage = info.version;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionText = '無法取得版本號');
    }
  }

  Future<void> _loadWebViewVersion() async {
    try {
      final version = await _appInfoChannel.invokeMethod<String>(
        'getSystemWebViewVersion',
      );
      if (!mounted) return;
      setState(() => _webViewVersion = version ?? '無法取得');
    } catch (_) {
      if (!mounted) return;
      setState(() => _webViewVersion = '無法取得');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('關於')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('版本'),
            subtitle: Text(
              _versionText,
              key: const Key('about_screen_version_text'),
            ),
          ),
          ListTile(
            title: const Text('系統 WebView 版本'),
            subtitle: Text(
              _webViewVersion,
              key: const Key('about_screen_webview_version_text'),
            ),
          ),
          ListTile(
            key: const Key('about_screen_view_licenses_button'),
            title: const Text('開源授權清單'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'elinkBook',
                applicationVersion: _versionForLicensePage,
              );
            },
          ),
        ],
      ),
    );
  }
}
