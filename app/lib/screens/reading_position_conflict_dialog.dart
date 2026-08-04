import 'package:flutter/material.dart';

import '../library/models/library_enums.dart';
import '../sync/sync_reading_position.dart';

/// 把單一版本的閱讀位置快照轉成人類可讀的描述，供 [showReadingPositionConflictDialog]
/// 顯示——PDF 額外顯示頁碼（1-indexed，[ReadingPositionSnapshot.pdfPageIndex]
/// 本身是 0-indexed），EPUB 僅顯示進度百分比（CFI 定位字串本身無法簡單
/// 轉成人類可讀文字）。
String _describeReadingPosition(
  ReadingPositionSnapshot snapshot,
  BookFileFormat format,
) {
  final percent = (snapshot.progress * 100).round();
  if (format == BookFileFormat.pdf && snapshot.pdfPageIndex != null) {
    return '第 ${snapshot.pdfPageIndex! + 1} 頁（進度 $percent%）';
  }
  return '進度 $percent%';
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
    builder: (dialogContext) => AlertDialog(
      title: Text('「${conflict.bookTitle}」的閱讀進度不一致'),
      content: Text(
        '偵測到另一台裝置也更新過這本書的閱讀進度，請選擇要保留哪一邊：\n\n'
        '本機：${_describeReadingPosition(conflict.local, conflict.format)}\n'
        '雲端：${_describeReadingPosition(conflict.remote, conflict.format)}',
      ),
      actions: [
        TextButton(
          key: const Key('reading_position_conflict_keep_cloud'),
          onPressed: () =>
              Navigator.of(dialogContext).pop(ReadingPositionChoice.keepCloud),
          child: const Text('保留雲端'),
        ),
        TextButton(
          key: const Key('reading_position_conflict_keep_local'),
          onPressed: () =>
              Navigator.of(dialogContext).pop(ReadingPositionChoice.keepLocal),
          child: const Text('保留本機'),
        ),
      ],
    ),
  );
}
