import 'package:flutter/material.dart';

import '../cloud_import/cloud_book_downloader.dart';
import '../cloud_import/cloud_storage_client.dart';
import '../library/book_import_service.dart';
import '../library/models/library_enums.dart';

enum CloudDownloadItemStatus { pending, downloading, done, failed, cancelled }

/// 序列下載佇列對話框（epic-29-cloud-import Issue 3，spec.md「確認匯入後，
/// 多選檔案循序下載...並顯示逐項狀態」）：一本下完才下一本，逐項顯示等待
/// 中/下載中/完成/失敗/已取消狀態；下載失敗可針對單一檔案手動重試（不
/// 自動重試）；全部處理完後，把所有成功下載的檔案一次呼叫
/// [BookImportService.importFiles] 匯入圖書庫。結構比照
/// `remote_catalog_screen.dart` 的私有 `_DownloadQueueDialog`，但刻意
/// 公開（非私有）供 Issue 4（OneDrive）沿用同一個對話框、只需傳入不同的
/// [source]；刻意不含重複匯入偵測（Issue 5 的範圍）。
class CloudDownloadQueueDialog extends StatefulWidget {
  final List<CloudFileEntry> entries;
  final CloudStorageClient client;
  final BookImportService importService;
  final BookSource source;
  final String? folderName;

  const CloudDownloadQueueDialog({
    super.key,
    required this.entries,
    required this.client,
    required this.importService,
    required this.source,
    this.folderName,
  });

  @override
  State<CloudDownloadQueueDialog> createState() => _CloudDownloadQueueDialogState();
}

class _CloudDownloadQueueDialogState extends State<CloudDownloadQueueDialog> {
  late List<CloudDownloadItemStatus> _statuses;
  late List<String?> _permanentPaths;
  late List<CloudDownloadCancellationToken?> _tokens;
  bool _allSettled = false;

  @override
  void initState() {
    super.initState();
    _statuses = List.filled(widget.entries.length, CloudDownloadItemStatus.pending);
    _permanentPaths = List.filled(widget.entries.length, null);
    _tokens = List.filled(widget.entries.length, null);
    _runQueue();
  }

  Future<void> _runQueue() async {
    for (var i = 0; i < widget.entries.length; i++) {
      await _downloadOne(i);
    }
    await _importSuccessful();
    if (!mounted) return;
    setState(() => _allSettled = true);
  }

  Future<void> _downloadOne(int index) async {
    if (!mounted) return;
    setState(() => _statuses[index] = CloudDownloadItemStatus.downloading);
    final entry = widget.entries[index];
    final token = CloudDownloadCancellationToken();
    _tokens[index] = token;
    try {
      final tempPath = await downloadCloudFileToTempFile(
        client: widget.client,
        entry: entry,
        cancellationToken: token,
      );
      final permanentPath = await promoteCloudFileToPermanent(tempPath);
      if (!mounted) return;
      setState(() {
        _permanentPaths[index] = permanentPath;
        _statuses[index] = CloudDownloadItemStatus.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statuses[index] = token.isCancelled
            ? CloudDownloadItemStatus.cancelled
            : CloudDownloadItemStatus.failed;
      });
    }
  }

  Future<void> _importSuccessful() async {
    final paths = <String>[];
    final cloudFileIds = <String, String>{};
    for (var i = 0; i < widget.entries.length; i++) {
      final path = _permanentPaths[i];
      if (path == null) continue;
      paths.add(path);
      cloudFileIds[path] = widget.entries[i].id;
    }
    if (paths.isEmpty) return;
    await widget.importService.importFiles(
      paths,
      folderName: widget.folderName,
      source: widget.source,
      cloudFileIds: cloudFileIds,
    );
  }

  Future<void> _retry(int index) async {
    // 【審查 review-plan-issue-3.md Minor #1 採納】整批下載已完成時
    // _allSettled 為 true（「完成」按鈕已啟用）；若此時對單一失敗項目
    // 按重試，重試期間必須暫時關閉「完成」按鈕，避免使用者在這段窗口
    // 誤觸關閉對話框、看不到這次重試的最終結果。
    setState(() => _allSettled = false);
    await _downloadOne(index);
    if (mounted) setState(() => _allSettled = true);
    if (_statuses[index] != CloudDownloadItemStatus.done) return;
    final path = _permanentPaths[index]!;
    final entry = widget.entries[index];
    await widget.importService.importFiles(
      [path],
      folderName: widget.folderName,
      source: widget.source,
      cloudFileIds: {path: entry.id},
    );
  }

  void _cancel(int index) {
    _tokens[index]?.cancel();
  }

  String _statusLabel(CloudDownloadItemStatus status) {
    switch (status) {
      case CloudDownloadItemStatus.pending:
        return '等待中';
      case CloudDownloadItemStatus.downloading:
        return '下載中';
      case CloudDownloadItemStatus.done:
        return '完成';
      case CloudDownloadItemStatus.failed:
        return '失敗';
      case CloudDownloadItemStatus.cancelled:
        return '已取消';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('cloud_download_queue_dialog'),
      title: const Text('下載進度'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.entries.length,
          itemBuilder: (context, index) {
            final entry = widget.entries[index];
            final status = _statuses[index];
            final canRetry = status == CloudDownloadItemStatus.failed ||
                status == CloudDownloadItemStatus.cancelled;
            return ListTile(
              key: Key('cloud_download_queue_item_${entry.id}'),
              title: Text(entry.name),
              subtitle: Text(_statusLabel(status)),
              trailing: status == CloudDownloadItemStatus.downloading
                  ? IconButton(
                      key: Key('cloud_download_queue_cancel_${entry.id}'),
                      icon: const Icon(Icons.close),
                      tooltip: '取消',
                      onPressed: () => _cancel(index),
                    )
                  : canRetry
                      ? IconButton(
                          key: Key('cloud_download_queue_retry_${entry.id}'),
                          icon: const Icon(Icons.refresh),
                          tooltip: '重試',
                          onPressed: () => _retry(index),
                        )
                      : null,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cloud_download_queue_done_button'),
          onPressed: _allSettled ? () => Navigator.of(context).pop() : null,
          child: const Text('完成'),
        ),
      ],
    );
  }
}

/// 重複匯入確認彈窗（epic-29-cloud-import Issue 5，完整比照
/// `remote_catalog_screen.dart` 的 `_showDuplicateConfirmDialog` 既有
/// 設計）：選檔前置（Layer 1，[CloudBrowserScreen]）與下載後指紋比對
/// （Layer 2，本檔案的 [CloudDownloadQueueDialog]）兩層檢查共用同一個
/// 確認 UI，只有提示文字不同——精確比對命中不代表強制阻擋，使用者可選擇
/// 仍要建立新副本。刻意宣告為公開（非私有）頂層函式而非私有於單一檔案，
/// 因為 Layer 1 與 Layer 2 分屬 `cloud_browser_screen.dart`／
/// `cloud_download_queue_dialog.dart` 兩個不同檔案（不像 epic-30 兩層都在
/// 同一個檔案內，可以用私有函式）。
Future<bool> showCloudDuplicateConfirmDialog(BuildContext context, String message) async {
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
