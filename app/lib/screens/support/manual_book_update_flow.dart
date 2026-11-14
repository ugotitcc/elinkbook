import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../library/book_file_format.dart';
import '../../library/book_import_service.dart';
import '../../library/book_update_models.dart';
import '../../library/models/book.dart';
import 'book_import_picker_helper.dart';
import 'book_update_resolver.dart' show BookUpdateApplyResult, evictCoverImageCache;

/// 手動更新單本書籍的結果。
enum ManualBookUpdateOutcome {
  cancelled,
  formatMismatch,
  replaced,
  failed,
}

/// 執行單本書籍手動更新流程（epic-67 Issue 3）。
///
/// 1. 開啟單檔選擇器（副檔名限定原書格式）。
/// 2. 比對副檔名與格式，不符時提示 SnackBar 並返回 [ManualBookUpdateOutcome.formatMismatch]。
/// 3. 顯示確認對話框，使用者確認後在對話框內等待 [BookImportService.replaceBook]。
/// 4. 成功時更新封面快取並顯示結果 SnackBar；失敗時顯示失敗 SnackBar。
///
/// 整個流程保證不拋例外。
Future<ManualBookUpdateOutcome> runManualBookUpdate(
  BuildContext context, {
  required Book book,
  required BookImportService importService,
  required SingleBookFilePicker pickFile,
  bool isEinkMode = false,
  void Function(String coverPath) onCoverChanged = evictCoverImageCache,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context)!;

  final picked = await pickFile([book.format.name]);
  if (!context.mounted || picked == null) {
    return ManualBookUpdateOutcome.cancelled;
  }

  final format = detectImportFileFormat(picked.uri, picked.displayName);
  if (format != book.format) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.bookManualUpdateFormatMismatch)),
      );
    return ManualBookUpdateOutcome.formatMismatch;
  }

  final replaceResult = await showDialog<BookReplaceResult>(
    context: context,
    barrierDismissible: false,
    animationStyle: isEinkMode ? AnimationStyle.noAnimation : null,
    builder: (dialogContext) => _ManualBookUpdateDialog(
      book: book,
      picked: picked,
      importService: importService,
    ),
  );

  if (replaceResult == null) {
    return ManualBookUpdateOutcome.cancelled;
  }

  switch (replaceResult) {
    case BookReplaceSuccess(:final updatedBook):
      final coversToEvict = <String>{
        if (book.coverPath != null) book.coverPath!,
        if (updatedBook.coverPath != null) updatedBook.coverPath!,
      };
      for (final cover in coversToEvict) {
        try {
          onCoverChanged(cover);
        } catch (_) {}
      }
      showBookUpdateResultSnackBarWith(
        messenger,
        l10n,
        const BookUpdateApplyResult(replaced: 1),
      );
      return ManualBookUpdateOutcome.replaced;

    case BookReplaceFailure():
      showBookUpdateResultSnackBarWith(
        messenger,
        l10n,
        const BookUpdateApplyResult(failed: 1),
      );
      return ManualBookUpdateOutcome.failed;
  }
}

class _ManualBookUpdateDialog extends StatefulWidget {
  final Book book;
  final ({String uri, String? displayName}) picked;
  final BookImportService importService;

  const _ManualBookUpdateDialog({
    required this.book,
    required this.picked,
    required this.importService,
  });

  @override
  State<_ManualBookUpdateDialog> createState() => _ManualBookUpdateDialogState();
}

class _ManualBookUpdateDialogState extends State<_ManualBookUpdateDialog> {
  bool _isUpdating = false;

  Future<void> _handleConfirm() async {
    setState(() => _isUpdating = true);
    BookReplaceResult outcome;
    try {
      outcome = await widget.importService.replaceBook(
        widget.book.id,
        widget.picked.uri,
        displayName: widget.picked.displayName,
      );
    } catch (_) {
      outcome = const BookReplaceFailure(BookReplaceFailureReason.writeFailed);
    }
    if (mounted) {
      Navigator.of(context).pop(outcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displayName = widget.picked.displayName ?? widget.picked.uri;

    return PopScope(
      canPop: !_isUpdating,
      child: AlertDialog(
        key: const Key('book_manual_update_dialog'),
        title: Text(l10n.bookActionUpdateBook),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.bookManualUpdateConfirmMessage(
                displayName,
                widget.book.title,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.bookUpdateReplaceNotice,
              key: const Key('book_manual_update_notice'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (_isUpdating) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.bookUpdateApplying,
                    key: const Key('book_manual_update_applying'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: const Key('book_manual_update_cancel'),
            onPressed:
                _isUpdating ? null : () => Navigator.of(context).pop(null),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('book_manual_update_confirm'),
            onPressed: _isUpdating ? null : _handleConfirm,
            child: Text(l10n.bookManualUpdateConfirmButton),
          ),
        ],
      ),
    );
  }
}
