// app/lib/screens/dictionary_online_consent_dialog.dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 開啟線上查詞前的同意對話框（epic-63 Issue 7，spec §3.4、§7）。
///
/// 隱私上這是必要的一步：同意之前不發出任何網路請求。同意與開啟合成一個
/// 狀態——按「同意並開啟」回 `true`；取消、點外面或系統返回一律回 `false`，
/// 呼叫端維持關閉。
///
/// E-Ink 模式用 [AnimationStyle.noAnimation]：電子紙上的淡入淡出會留下殘影
/// （比照 `dictionary_import_dialog.dart`）。
Future<bool> showDictionaryOnlineConsentDialog(
  BuildContext context, {
  required bool isEinkMode,
}) async {
  final result = await showDialog<bool>(
    context: context,
    animationStyle: isEinkMode ? AnimationStyle.noAnimation : null,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      return AlertDialog(
        key: const Key('dictionary_online_consent_dialog'),
        title: Text(l10n.dictionaryOnlineConsentTitle),
        // 四行說明各自成行；測試以 `textContaining` 檢查關鍵段落。
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(l10n.dictionaryOnlineConsentBody),
        ),
        actions: [
          TextButton(
            key: const Key('dictionary_online_consent_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.dictionaryOnlineConsentCancel),
          ),
          TextButton(
            key: const Key('dictionary_online_consent_agree'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.dictionaryOnlineConsentAgree),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
