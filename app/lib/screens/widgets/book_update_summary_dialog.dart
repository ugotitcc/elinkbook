import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../library/book_import_service.dart';
import '../../library/book_update_models.dart';
import '../support/book_update_resolver.dart';

/// 顯示書籍更新版彙整清單對話框，回傳套用結果。
///
/// 取消、返回鍵或全部跳過都會確保先丟棄候選暫存檔再回傳計數結果。
Future<BookUpdateApplyResult> showBookUpdateSummaryDialog(
  BuildContext context, {
  required BookImportService importService,
  required List<BookUpdateCandidate> candidates,
  bool isEinkMode = false,
}) async {
  final result = await showDialog<BookUpdateApplyResult>(
    context: context,
    barrierDismissible: false,
    animationStyle: isEinkMode ? AnimationStyle.noAnimation : null,
    builder: (dialogContext) => _BookUpdateSummaryDialog(
      importService: importService,
      candidates: candidates,
    ),
  );

  if (result != null) {
    return result;
  }

  // 保底：若對話框因非預期途徑被關閉，全數丟棄暫存檔
  return applyBookUpdateChoices(
    importService,
    candidates.map((c) => BookUpdateDecision(c, const SkipChoice())).toList(),
  );
}

class _BookUpdateSummaryDialog extends StatefulWidget {
  final BookImportService importService;
  final List<BookUpdateCandidate> candidates;

  const _BookUpdateSummaryDialog({
    required this.importService,
    required this.candidates,
  });

  @override
  State<_BookUpdateSummaryDialog> createState() =>
      _BookUpdateSummaryDialogState();
}

class _BookUpdateSummaryDialogState extends State<_BookUpdateSummaryDialog> {
  late List<BookUpdateChoice> _choices;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    // Issue 1 契約：更新候選至少有一本候選書。
    assert(
      widget.candidates.every((c) => c.candidateBooks.isNotEmpty),
      '更新候選的 candidateBooks 不得為空',
    );
    // 預設每筆候選選擇第一本候選書之取代選項（spec 故事 9）
    _choices = <BookUpdateChoice>[
      for (final c in widget.candidates)
        ReplaceChoice(c.candidateBooks.first.id),
    ];
  }

  String _candidateName(BookUpdateCandidate candidate) {
    if (candidate.displayName != null && candidate.displayName!.isNotEmpty) {
      return candidate.displayName!;
    }
    final uri = candidate.sourceUri;
    final normalized = uri.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isNotEmpty ? segments.last : normalized;
  }

  void _selectAllReplace() {
    setState(() {
      for (var i = 0; i < widget.candidates.length; i++) {
        _choices[i] = ReplaceChoice(widget.candidates[i].candidateBooks.first.id);
      }
    });
  }

  void _selectAllSkip() {
    setState(() {
      for (var i = 0; i < widget.candidates.length; i++) {
        _choices[i] = const SkipChoice();
      }
    });
  }

  Future<void> _onApply() async {
    if (_applying) return;
    setState(() => _applying = true);

    final decisions = List.generate(
      widget.candidates.length,
      (i) => BookUpdateDecision(widget.candidates[i], _choices[i]),
    );

    final result = await applyBookUpdateChoices(
      widget.importService,
      decisions,
    );

    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _onCancel() async {
    if (_applying) return;
    setState(() => _applying = true);

    final decisions = widget.candidates
        .map((c) => BookUpdateDecision(c, const SkipChoice()))
        .toList();

    final result = await applyBookUpdateChoices(
      widget.importService,
      decisions,
    );

    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasAnyReplace = _choices.any((c) => c is ReplaceChoice);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_applying) {
          _onCancel();
        }
      },
      child: AlertDialog(
        title: Text(l10n.bookUpdateSummaryTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  l10n.bookUpdateSummaryIntro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: widget.candidates.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 24),
                    itemBuilder: (context, index) =>
                        _buildCandidateRow(context, l10n, index),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 快捷操作列
              Row(
                children: [
                  TextButton(
                    key: const Key('book_update_replace_all'),
                    onPressed: _applying ? null : _selectAllReplace,
                    child: Text(l10n.bookUpdateReplaceAll),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: const Key('book_update_skip_all'),
                    onPressed: _applying ? null : _selectAllSkip,
                    child: Text(l10n.bookUpdateSkipAll),
                  ),
                ],
              ),
              // 偏移提示：只要有任何一列選了取代即顯示
              if (hasAnyReplace)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.bookUpdateReplaceNotice,
                    key: const Key('book_update_replace_notice'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_applying) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.bookUpdateApplying,
                      key: const Key('book_update_applying'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('book_update_cancel'),
            onPressed: _applying ? null : _onCancel,
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('book_update_apply'),
            onPressed: _applying ? null : _onApply,
            child: Text(l10n.bookUpdateApply),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateRow(
    BuildContext context,
    AppLocalizations l10n,
    int index,
  ) {
    final candidate = widget.candidates[index];
    final currentChoice = _choices[index];
    final confidenceText = candidate.confidence == UpdateConfidence.high
        ? l10n.bookUpdateConfidenceHigh
        : l10n.bookUpdateConfidenceSuspected;

    // 檢查舊檔是否讀不到且當前選取了該書
    String? unreadableBookTitle;
    if (currentChoice is ReplaceChoice &&
        candidate.unreadableCandidateBookIds.contains(currentChoice.bookId)) {
      unreadableBookTitle = candidate.candidateBooks
          .where((b) => b.id == currentChoice.bookId)
          .firstOrNull
          ?.title;
    }

    return RadioGroup<BookUpdateChoice>(
      key: Key('book_update_row_$index'),
      groupValue: currentChoice,
      onChanged: (value) {
        if (_applying || value == null) return;
        setState(() => _choices[index] = value);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 檔案名稱
          Text(
            _candidateName(candidate),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          // 信心等級標籤
          Text(
            confidenceText,
            key: Key('book_update_confidence_$index'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 6),
          // 選項列表
          for (final book in candidate.candidateBooks)
            RadioListTile<BookUpdateChoice>(
              key: Key('book_update_option_replace_${index}_${book.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.bookUpdateOptionReplace(book.title)),
              value: ReplaceChoice(book.id),
            ),
          RadioListTile<BookUpdateChoice>(
            key: Key('book_update_option_coexist_$index'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.bookUpdateOptionCoexist),
            value: const CoexistChoice(),
          ),
          RadioListTile<BookUpdateChoice>(
            key: Key('book_update_option_skip_$index'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.bookUpdateOptionSkip),
            value: const SkipChoice(),
          ),
          if (unreadableBookTitle != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.bookUpdateOldFileUnreadable(unreadableBookTitle),
              key: Key('book_update_unreadable_$index'),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
