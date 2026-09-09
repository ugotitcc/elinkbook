import 'package:flutter/material.dart';

import '../../cloud_import/cloud_download_queue_controller.dart';
import 'eb_field_card.dart';
import 'eb_section_header.dart';

/// 「來源」畫面常駐的下載佇列區塊（視覺還原，`docs/research/uiux/reference/
/// 來源.png`）：訂閱 [CloudDownloadQueueController]，逐項顯示確定式進度條
/// （`DESIGN.md` §16.2「確定式進度條取代連續旋轉的 ProgressIndicator」），
/// 沒有任何項目時整個區塊（含分區標題）不渲染。
class CloudDownloadQueuePanel extends StatelessWidget {
  final CloudDownloadQueueController controller;

  const CloudDownloadQueuePanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.items;
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EBSectionHeader(title: '下載佇列'),
            for (final item in items)
              EBFieldCard(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: _QueueItemRow(item: item, controller: controller),
              ),
          ],
        );
      },
    );
  }
}

class _QueueItemRow extends StatelessWidget {
  final CloudDownloadQueueItem item;
  final CloudDownloadQueueController controller;

  const _QueueItemRow({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final inProgress =
        item.status == CloudDownloadItemStatus.pending ||
        item.status == CloudDownloadItemStatus.downloading ||
        item.status == CloudDownloadItemStatus.checkingDuplicate;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                key: Key('sources_download_queue_item_${item.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              if (inProgress)
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          key: Key(
                            'sources_download_queue_progress_${item.id}',
                          ),
                          value: item.progress ?? 0.0,
                          minHeight: 8,
                          backgroundColor: colorScheme.outline.withValues(
                            alpha: 0.3,
                          ),
                          valueColor: AlwaysStoppedAnimation(
                            colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_statusLabel(item), style: TextStyle(fontSize: 12)),
                  ],
                )
              else
                Row(
                  children: [
                    Icon(_statusIcon(item.status), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _statusLabel(item),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),
        ),
        _trailingAction(context),
      ],
    );
  }

  Widget _trailingAction(BuildContext context) {
    switch (item.status) {
      case CloudDownloadItemStatus.downloading:
        return IconButton(
          key: Key('sources_download_queue_cancel_${item.id}'),
          icon: const Icon(Icons.close),
          tooltip: '取消',
          onPressed: () => controller.cancel(item.id),
        );
      case CloudDownloadItemStatus.failed:
      case CloudDownloadItemStatus.cancelled:
        return IconButton(
          key: Key('sources_download_queue_retry_${item.id}'),
          icon: const Icon(Icons.refresh),
          tooltip: '重試',
          onPressed: () => controller.retry(item.id),
        );
      case CloudDownloadItemStatus.done:
      case CloudDownloadItemStatus.duplicateSkipped:
        return IconButton(
          key: Key('sources_download_queue_dismiss_${item.id}'),
          icon: const Icon(Icons.close),
          tooltip: '從清單移除',
          onPressed: () => controller.dismiss(item.id),
        );
      case CloudDownloadItemStatus.pending:
      case CloudDownloadItemStatus.checkingDuplicate:
        return const SizedBox(width: 48);
    }
  }

  IconData _statusIcon(CloudDownloadItemStatus status) {
    switch (status) {
      case CloudDownloadItemStatus.done:
        return Icons.check_circle;
      case CloudDownloadItemStatus.duplicateSkipped:
        return Icons.block;
      case CloudDownloadItemStatus.failed:
        return Icons.error_outline;
      case CloudDownloadItemStatus.cancelled:
        return Icons.cancel_outlined;
      case CloudDownloadItemStatus.pending:
      case CloudDownloadItemStatus.downloading:
      case CloudDownloadItemStatus.checkingDuplicate:
        return Icons.hourglass_empty;
    }
  }

  String _statusLabel(CloudDownloadQueueItem item) {
    switch (item.status) {
      case CloudDownloadItemStatus.pending:
        return '待機';
      case CloudDownloadItemStatus.downloading:
        final progress = item.progress;
        return progress == null ? '下載中' : '${(progress * 100).round()}%';
      case CloudDownloadItemStatus.checkingDuplicate:
        return '比對中';
      case CloudDownloadItemStatus.done:
        return '完成';
      case CloudDownloadItemStatus.duplicateSkipped:
        return '重複已略過';
      case CloudDownloadItemStatus.failed:
        return '失敗';
      case CloudDownloadItemStatus.cancelled:
        return '已取消';
    }
  }
}
