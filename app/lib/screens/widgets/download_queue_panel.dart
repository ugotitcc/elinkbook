import 'package:flutter/material.dart';

import '../../downloads/download_queue_controller.dart';
import '../../l10n/app_localizations.dart';
import 'eb_field_card.dart';
import 'eb_section_header.dart';

/// 「來源」畫面常駐的下載佇列區塊（視覺還原，`docs/research/uiux/reference/
/// 來源.png`）：訂閱 [DownloadQueueController]（不分下載來源，雲端硬碟／
/// OPDS 遠端書庫共用同一份清單），逐項顯示確定式進度條（`DESIGN.md` §16.2
/// 「確定式進度條取代連續旋轉的 ProgressIndicator」），沒有任何項目時
/// 整個區塊（含分區標題）不渲染。
class DownloadQueuePanel extends StatelessWidget {
  final DownloadQueueController controller;

  const DownloadQueuePanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.items;
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EBSectionHeader(title: l10n.downloadQueueTitle),
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
  final DownloadQueueItem item;
  final DownloadQueueController controller;

  const _QueueItemRow({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final inProgress =
        item.status == DownloadItemStatus.pending ||
        item.status == DownloadItemStatus.downloading ||
        item.status == DownloadItemStatus.checkingDuplicate;

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
                    Text(_statusLabel(l10n, item), style: TextStyle(fontSize: 12)),
                  ],
                )
              else
                Row(
                  children: [
                    Icon(_statusIcon(item.status), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _statusLabel(l10n, item),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),
        ),
        _trailingAction(context, l10n),
      ],
    );
  }

  Widget _trailingAction(BuildContext context, AppLocalizations l10n) {
    switch (item.status) {
      case DownloadItemStatus.downloading:
        return IconButton(
          key: Key('sources_download_queue_cancel_${item.id}'),
          icon: const Icon(Icons.close),
          tooltip: l10n.downloadQueueCancelTooltip,
          onPressed: () => controller.cancel(item.id),
        );
      case DownloadItemStatus.failed:
      case DownloadItemStatus.cancelled:
        return IconButton(
          key: Key('sources_download_queue_retry_${item.id}'),
          icon: const Icon(Icons.refresh),
          tooltip: l10n.downloadQueueRetryTooltip,
          onPressed: () => controller.retry(item.id),
        );
      case DownloadItemStatus.done:
      case DownloadItemStatus.duplicateSkipped:
        return IconButton(
          key: Key('sources_download_queue_dismiss_${item.id}'),
          icon: const Icon(Icons.close),
          tooltip: l10n.downloadQueueDismissTooltip,
          onPressed: () => controller.dismiss(item.id),
        );
      case DownloadItemStatus.pending:
      case DownloadItemStatus.checkingDuplicate:
        return const SizedBox(width: 48);
    }
  }

  IconData _statusIcon(DownloadItemStatus status) {
    switch (status) {
      case DownloadItemStatus.done:
        return Icons.check_circle;
      case DownloadItemStatus.duplicateSkipped:
        return Icons.block;
      case DownloadItemStatus.failed:
        return Icons.error_outline;
      case DownloadItemStatus.cancelled:
        return Icons.cancel_outlined;
      case DownloadItemStatus.pending:
      case DownloadItemStatus.downloading:
      case DownloadItemStatus.checkingDuplicate:
        return Icons.hourglass_empty;
    }
  }

  String _statusLabel(AppLocalizations l10n, DownloadQueueItem item) {
    switch (item.status) {
      case DownloadItemStatus.pending:
        return l10n.downloadQueueStatusPending;
      case DownloadItemStatus.downloading:
        final progress = item.progress;
        return progress == null
            ? l10n.downloadQueueStatusDownloading
            : '${(progress * 100).round()}%';
      case DownloadItemStatus.checkingDuplicate:
        return l10n.downloadQueueStatusCheckingDuplicate;
      case DownloadItemStatus.done:
        return l10n.downloadQueueStatusDone;
      case DownloadItemStatus.duplicateSkipped:
        return l10n.downloadQueueStatusDuplicateSkipped;
      case DownloadItemStatus.failed:
        return l10n.downloadQueueStatusFailed;
      case DownloadItemStatus.cancelled:
        return l10n.downloadQueueStatusCancelled;
    }
  }
}
