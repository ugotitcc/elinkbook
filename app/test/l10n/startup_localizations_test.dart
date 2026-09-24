import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/l10n/startup_localizations.dart';

void main() {
  group('resolveStartupLocalizations（無 BuildContext 的啟動階段取得 AppLocalizations）', () {
    test('使用者明確覆寫語言時，優先採用覆寫（不看裝置語言）', () {
      final l10n = resolveStartupLocalizations(
        localeOverride: AppLocale.zhCN,
        deviceLocales: const [Locale('en', 'US')],
      );
      expect(l10n.ttsNotificationChannelName, '朗读播放中');
    });

    test('未覆寫時跟隨裝置語言：英文', () {
      final l10n = resolveStartupLocalizations(
        deviceLocales: const [Locale('en', 'US')],
      );
      expect(l10n.ttsNotificationChannelName, 'Reading aloud');
    });

    test('未覆寫時跟隨裝置語言：簡體中文（zh_Hans_CN）', () {
      final l10n = resolveStartupLocalizations(
        deviceLocales: const [
          Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
        ],
      );
      expect(l10n.ttsNotificationChannelName, '朗读播放中');
    });

    test('未覆寫時跟隨裝置語言：正體中文（zh_TW）', () {
      final l10n = resolveStartupLocalizations(
        deviceLocales: const [Locale('zh', 'TW')],
      );
      expect(l10n.ttsNotificationChannelName, '朗讀播放中');
    });

    test('裝置語言清單為 null 或為不支援的語言時，fallback 正體中文', () {
      expect(
        resolveStartupLocalizations().ttsNotificationChannelName,
        '朗讀播放中',
      );
      expect(
        resolveStartupLocalizations(deviceLocales: const [Locale('ja', 'JP')])
            .ttsNotificationChannelName,
        '朗讀播放中',
      );
    });

    test('與 MaterialApp 的 localeListResolutionCallback 走同一套解析：'
        '首選不支援、次要偏好為英文時採用英文', () {
      final l10n = resolveStartupLocalizations(
        deviceLocales: const [Locale('ja', 'JP'), Locale('en', 'GB')],
      );
      expect(l10n.ttsNotificationChannelName, 'Reading aloud');
    });
  });
}
