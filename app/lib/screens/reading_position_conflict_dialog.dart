import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../library/models/library_enums.dart';
import '../sync/sync_reading_position.dart';

/// 把單一版本的閱讀位置快照轉成人類可讀的描述，供 [showReadingPositionConflictDialog]
/// 顯示——PDF 額外顯示頁碼（1-indexed，[ReadingPositionSnapshot.pdfPageIndex]
/// 本身是 0-indexed），EPUB 僅顯示進度百分比（CFI 定位字串本身無法簡單
/// 轉成人類可讀文字）。
String _describeReadingPosition(
  ReadingPositionSnapshot snapshot,
  BookFileFormat format,
  AppLocalizations l10n,
) {
  final percent = (snapshot.progress * 100).round();
  if (format == BookFileFormat.pdf && snapshot.pdfPageIndex != null) {
    return l10n.readerPositionConflictPdfLocation(
      snapshot.pdfPageIndex! + 1,
      percent,
    );
  }
  return l10n.readerPositionConflictEpubLocation(percent);
}

/// 閱讀位置衝突對話框（epic-8-sync Issue 5，FR-19：「若開啟書籍時雲端
/// 同步的位置與本機位置不一致，須先詢問使用者確認才跳轉——絕不可靜默
/// 覆蓋」）。回傳使用者的選擇；使用者關閉對話框（例如點擊外部區域）
/// 未做選擇時回傳 `null`，符合 `ReadingPositionConflictResolver` 的
/// 契約（`SyncEngine` 收到 `null` 時會跳過這本書、留待下次 checkpoint
/// 重試，不靜默覆蓋任一邊）。
Future<ReadingPositionChoice?> showReadingPositionConflictDialog(
  BuildContext context,
  ReadingPositionConflict conflict,
) {
  return showDialog<ReadingPositionChoice>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      return AlertDialog(
        title: Text(l10n.readerPositionConflictTitle(conflict.bookTitle)),
        content: Text(
          l10n.readerPositionConflictMessage(
            _describeReadingPosition(conflict.local, conflict.format, l10n),
            _describeReadingPosition(conflict.remote, conflict.format, l10n),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('reading_position_conflict_keep_cloud'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(ReadingPositionChoice.keepCloud),
            child: Text(l10n.readerPositionConflictKeepCloud),
          ),
          TextButton(
            key: const Key('reading_position_conflict_keep_local'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(ReadingPositionChoice.keepLocal),
            child: Text(l10n.readerPositionConflictKeepLocal),
          ),
        ],
      );
    },
  );
}
