import 'package:flutter/material.dart';

/// 重複匯入確認彈窗（epic-29-cloud-import Issue 5，完整比照
/// `remote_catalog_screen.dart` 的 `_showDuplicateConfirmDialog` 既有
/// 設計）：選檔前置（Layer 1，[CloudBrowserScreen]）與下載後指紋比對
/// （Layer 2，[CloudDownloadQueueController]）兩層檢查共用同一個確認
/// UI，只有提示文字不同——精確比對命中不代表強制阻擋，使用者可選擇仍要
/// 建立新副本。刻意宣告為公開頂層函式（獨立於原本掛在
/// `cloud_download_queue_dialog.dart` 底下的寫法，視覺還原 Visual
/// Accuracy Mode 把下載佇列改成常駐、不再是 Dialog 之後，這個確認彈窗
/// 本身仍是需要 `BuildContext` 的一次性 UI，獨立成檔更清楚）。
Future<bool> showCloudDuplicateConfirmDialog(
  BuildContext context,
  String message,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('cloud_duplicate_dialog'),
      title: const Text('重複的書籍'),
      content: Text(message),
      actions: [
        TextButton(
          key: const Key('cloud_duplicate_dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('cloud_duplicate_dialog_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('仍要建立'),
        ),
      ],
    ),
  );
  return result ?? false;
}
