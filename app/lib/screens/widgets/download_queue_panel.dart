import 'package:flutter/material.dart';

import '../../downloads/download_queue_controller.dart';
import '../../l10n/app_localizations.dart';
import '../support/book_import_picker_helper.dart';
import '../support/book_update_resolver.dart';
import 'book_update_summary_dialog.dart';
import 'eb_field_card.dart';
import 'eb_section_header.dart';

/// 「來源」畫面常駐的下載佇列區塊（視覺還原，`docs/research/uiux/reference/
/// 來源.png`）：訂閱 [DownloadQueueController]（不分下載來源，雲端硬碟／
/// OPDS 遠端書庫共用同一份清單），逐項顯示確定式進度條（`DESIGN.md` §16.2
/// 「確定式進度條取代連續旋轉的 ProgressIndicator」），沒有任何項目時
/// 整個區塊（含分區標題）不渲染。
class DownloadQueuePanel extends StatelessWidget {
  final DownloadQueueController controller;
  final bool isEinkMode;

  const DownloadQueuePanel({
    super.key,
    required this.controller,
    this.isEinkMode = false,
  });

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
                child: _QueueItemRow(
                  item: item,
                  controller: controller,
                  isEinkMode: isEinkMode,
                ),
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
  final bool isEinkMode;

  const _QueueItemRow({
    required this.item,
    required this.controller,
    this.isEinkMode = false,
  });

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
      case DownloadItemStatus.awaitingUpdateConfirmation:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('sources_download_queue_review_${item.id}'),
              icon: const Icon(Icons.rate_review_outlined),
              tooltip: l10n.downloadQueueUpdateReviewButton,
              onPressed: () => _reviewUpdate(context, item),
            ),
            IconButton(
              key: Key('sources_download_queue_dismiss_${item.id}'),
              icon: const Icon(Icons.close),
              tooltip: l10n.downloadQueueDismissTooltip,
              onPressed: () => controller.dismiss(item.id),
            ),
          ],
        );
      case DownloadItemStatus.pending:
      case DownloadItemStatus.checkingDuplicate:
        return const SizedBox(width: 48);
    }
  }

  Future<void> _reviewUpdate(
    BuildContext context,
    DownloadQueueItem item,
  ) async {
    final candidate = item.updateCandidate;
    if (candidate == null) return;

    final result = await showBookUpdateSummaryDialog(
      context,
      candidates: [candidate],
      discardOnCancel: false,
      isEinkMode: isEinkMode,
      importService: null,
      applier: (choices) async {
        final choice = choices[candidate] ?? const SkipChoice();
        final settleResult = await controller.resolveUpdate(item.id, choice);
        return BookUpdateApplyResult(
          replaced:
              settleResult.outcome == BookUpdateSettleOutcome.replaced ? 1 : 0,
          coexisted:
              settleResult.outcome == BookUpdateSettleOutcome.coexisted ? 1 : 0,
          skipped:
              settleResult.outcome == BookUpdateSettleOutcome.skipped ? 1 : 0,
          failed:
              settleResult.outcome == BookUpdateSettleOutcome.failed ? 1 : 0,
        );
      },
    );

    if (context.mounted &&
        (result.replaced > 0 || result.coexisted > 0 || result.failed > 0)) {
      showBookUpdateResultSnackBar(context, result);
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
      case DownloadItemStatus.awaitingUpdateConfirmation:
        return Icons.update;
      case DownloadItemStatus.pending:
      case DownloadItemStatus.downloading:
      case DownloadItemStatus.checkingDuplicate:
        return Icons.hourglass_empty;
    }
  }

  String _statusLabel(AppLocalizations l10n, DownloadQueueItem item) {
    switch (item.status) {
      case DownloadItemStatus.awaitingUpdateConfirmation:
        return l10n.downloadQueueStatusAwaitingUpdate;
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
        return item.needsReauth
            ? l10n.downloadQueueStatusNeedsReauth
            : l10n.downloadQueueStatusFailed;
      case DownloadItemStatus.cancelled:
        return l10n.downloadQueueStatusCancelled;
    }
  }
}
