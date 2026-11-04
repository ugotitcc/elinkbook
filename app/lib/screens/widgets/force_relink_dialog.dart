import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 重新選取檔案內容不符時詢問是否「強制重新連結」的對話框（epic-67 Issue 3）。
/// 使用者按「強制重新連結」回傳 `true`；按「取消」、點外部或返回鍵一律回傳 `false`。
/// [isEinkMode] 為 true 時使用 [AnimationStyle.noAnimation] 抑制殘影。
Future<bool> showForceRelinkDialog(
  BuildContext context, {
  bool isEinkMode = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    animationStyle: isEinkMode ? AnimationStyle.noAnimation : null,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      return AlertDialog(
        key: const Key('force_relink_dialog'),
        title: Text(l10n.readerForceRelinkTitle),
        content: Text(l10n.readerForceRelinkMessage),
        actions: [
          TextButton(
            key: const Key('force_relink_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('force_relink_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.readerForceRelinkConfirm),
          ),
        ],
      );
    },
  );
  return result == true;
}
