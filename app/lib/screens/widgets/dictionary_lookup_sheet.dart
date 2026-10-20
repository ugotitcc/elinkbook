import 'package:flutter/material.dart';

import '../../dictionary/dictionary_service.dart';
import '../../dictionary/lookup_text_normalizer.dart';
import '../../dictionary/models/dictionary_entry.dart';
import '../../dictionary/models/lookup_result.dart';
import '../../dictionary/pinyin_tone_marks.dart';
import '../../l10n/app_localizations.dart';
import 'eb_sheet_shell.dart';

/// 字典查詢面板（epic-63 Issue 4）：顯示 [DictionaryService.lookup] 的結果。
///
/// 純 Flutter，不碰 `InAppWebView`（HTML 詞條是 Issue 6a）：`EntryBodyKind.html`
/// 在此一律當純文字顯示。面板收到一個 `Future<DictionaryLookupResponse>`，
/// 依回傳型別分派到各狀態畫面；分段切換只改 `setState`，不重新查詢。
///
/// 關閉面板只 `Navigator.pop`，不動閱讀器的選取狀態——使用者關掉面板後仍可
/// 接著劃線。面板內沒有任何 `AnimatedXxx`：E-Ink 模式下 `EBSheetShell.show`
/// 已用 `AnimationStyle.noAnimation`，等待中也用靜態文字取代旋轉指示。
class DictionaryLookupSheet extends StatefulWidget {
  const DictionaryLookupSheet({
    super.key,
    required this.selectedText,
    required this.response,
    required this.isEinkMode,
    this.onOpenSettings,
  });

  /// 這次查詢的選取文字（原字串；去標點與長度判斷由服務負責）。
  final String selectedText;

  /// 面板的查詢結果。由呼叫端先發查詢再傳進來，面板本身只等結果。
  final Future<DictionaryLookupResponse> response;

  final bool isEinkMode;

  /// 「前往字典設定」入口；`null` 時不顯示連結（設定畫面是 Issue 5）。
  final VoidCallback? onOpenSettings;

  /// 開啟面板。查詢在這裡發一次，`builder` 重建不會重查。
  ///
  /// 遮罩參考 `ReaderScreen._showThemedModalBottomSheet`，但規則略有不同：
  /// 深色主題（書頁背景已很深，再疊 54% 黑遮罩會逼近全黑）與 E-Ink 一律
  /// 完全透明。E-Ink 在面板不撐滿時，上方露出的遮罩會在電子紙上抖動成
  /// 一片黑。
  static Future<void> show(
    BuildContext context, {
    required String selectedText,
    required DictionaryService service,
    required bool isEinkMode,
    VoidCallback? onOpenSettings,
  }) async {
    final title = AppLocalizations.of(context)!.dictionaryLookupTitle;
    final barrierColor = isEinkMode ||
            Theme.of(context).brightness == Brightness.dark
        ? Colors.transparent
        : null;
    final response = service.lookup(selectedText);
    // 面板建出來之前就失敗（例如字典資料庫開不起來）時，不要變成未處理錯誤；
    // FutureBuilder 稍後訂閱時仍會收到同一個錯誤並顯示失敗訊息。
    response.ignore();
    await EBSheetShell.show<void>(
      context,
      title: title,
      isEinkMode: isEinkMode,
      barrierColor: barrierColor,
      builder: (context) => DictionaryLookupSheet(
        selectedText: selectedText,
        response: response,
        isEinkMode: isEinkMode,
        onOpenSettings: onOpenSettings,
      ),
    );
  }

  @override
  State<DictionaryLookupSheet> createState() => _DictionaryLookupSheetState();
}

class _DictionaryLookupSheetState extends State<DictionaryLookupSheet> {
  /// 使用者選的分段；`null` 時用預設規則（第一個 `found`，都沒有就第一個）。
  String? _selectedProviderId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<DictionaryLookupResponse>(
      future: widget.response,
      builder: (context, snapshot) {
        // 查詢的詞固定釘在面板頂端（不分狀態）：使用者從選取叫出面板後，
        // 捲動詞條或來回切換分段時仍看得到自己在查哪個詞（spec §3.6）。
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _queryWordHeader(),
            Flexible(child: _content(snapshot, l10n)),
          ],
        );
      },
    );
  }

  Widget _queryWordHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        widget.selectedText,
        key: const Key('dictionary_lookup_query_word'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }

  Widget _content(
    AsyncSnapshot<DictionaryLookupResponse> snapshot,
    AppLocalizations l10n,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return _loading(l10n);
    }
    if (snapshot.hasError) {
      return _message(
        const Key('dictionary_lookup_failed'),
        l10n.dictionaryLookupFailed,
      );
    }
    final response = snapshot.data!;
    if (response is LookupRejected) {
      return _rejected(response.problem, l10n);
    }
    return _completed(response as LookupCompleted, l10n);
  }

  Widget _loading(AppLocalizations l10n) {
    return Padding(
      key: const Key('dictionary_lookup_loading'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 旋轉指示在電子紙上會持續局刷、留下殘影，E-Ink 改用靜態文字。
          widget.isEinkMode
              ? Text(l10n.dictionaryLookupLoading)
              : const CircularProgressIndicator(),
        ],
      ),
    );
  }

  Widget _rejected(SelectionProblem problem, AppLocalizations l10n) {
    final text = switch (problem) {
      SelectionProblem.invalidSelection => l10n.dictionaryLookupInvalidSelection,
      SelectionProblem.tooLong => l10n.dictionaryLookupTooLong,
    };
    return _message(const Key('dictionary_lookup_rejected'), text);
  }

  Widget _completed(LookupCompleted completed, AppLocalizations l10n) {
    final outcomes = completed.result.outcomes;
    if (outcomes.isEmpty) {
      return completed.hasEnabledDictionary
          ? _message(
              const Key('dictionary_lookup_empty_no_match'),
              l10n.dictionaryLookupNoMatchingDictionary,
            )
          : _message(
              const Key('dictionary_lookup_empty_no_dictionary'),
              l10n.dictionaryLookupNoDictionary,
              showSettings: true,
            );
    }

    final selectedId = _effectiveSelectedId(outcomes);
    final outcome = outcomes.firstWhere((o) => o.providerId == selectedId);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (outcomes.length > 1) ...[
          const SizedBox(height: 4),
          _segmentBar(outcomes, selectedId, l10n),
        ],
        // 內容少時貼合內容高度；內容多時最高到 `EBSheetShell` 的 85% 上限並可
        // 捲動。`Flexible` 讓 Column 維持 `min`，不會把短內容撐滿。
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [_outcomeBody(outcome, l10n)],
          ),
        ),
        _footer(outcome),
      ],
    );
  }

  String _effectiveSelectedId(List<ProviderOutcome> outcomes) {
    final requested = _selectedProviderId;
    if (requested != null &&
        outcomes.any((o) => o.providerId == requested)) {
      return requested;
    }
    final found = outcomes.where((o) => o.status == OutcomeStatus.found);
    return found.isNotEmpty
        ? found.first.providerId
        : outcomes.first.providerId;
  }

  Widget _segmentBar(
    List<ProviderOutcome> outcomes,
    String selectedId,
    AppLocalizations l10n,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<String>(
        key: const Key('dictionary_lookup_segments'),
        showSelectedIcon: false,
        segments: [
          for (final outcome in outcomes)
            ButtonSegment<String>(
              value: outcome.providerId,
              label: _segmentLabelWidget(
                outcome,
                isSelected: outcome.providerId == selectedId,
                l10n: l10n,
                colorScheme: colorScheme,
              ),
            ),
        ],
        selected: {selectedId},
        onSelectionChanged: (selection) {
          setState(() => _selectedProviderId = selection.first);
        },
        // 這裡刻意不設 `style.side`：`SegmentedButton` 只把它套在外框與
        // 分段之間的垂直分隔線，選中分段自己的邊框不會被畫出來（【final
        // review I-2】）。E-Ink 的「選中」改由標籤外框呈現。
      ),
    );
  }

  /// E-Ink 用邊框標示選中的分段（陰影在電子紙上會殘影）；其餘情況回傳純
  /// 文字，讓 `SegmentedButton` 維持自身預設的選中樣式。
  Widget _segmentLabelWidget(
    ProviderOutcome outcome, {
    required bool isSelected,
    required AppLocalizations l10n,
    required ColorScheme colorScheme,
  }) {
    final label = Text(_segmentLabel(outcome, l10n));
    if (!widget.isEinkMode || !isSelected) return label;
    return Container(
      key: Key('dictionary_lookup_segment_selected_${outcome.providerId}'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outline, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: label,
    );
  }

  /// 每個分段標籤都帶狀態後綴，不只選中的那個：使用者要先看到哪本字典
  /// 沒查到，才知道要不要切過去。
  String _segmentLabel(ProviderOutcome outcome, AppLocalizations l10n) {
    final suffix = switch (outcome.status) {
      OutcomeStatus.found => '',
      OutcomeStatus.notFound => l10n.dictionaryLookupSegmentNotFound,
      OutcomeStatus.skipped => l10n.dictionaryLookupSegmentSkipped,
      OutcomeStatus.failed => l10n.dictionaryLookupSegmentFailed,
    };
    return '${outcome.displayName}$suffix';
  }

  Widget _outcomeBody(ProviderOutcome outcome, AppLocalizations l10n) {
    switch (outcome.status) {
      case OutcomeStatus.found:
        if (outcome.entries.isEmpty) {
          return _message(
            const Key('dictionary_lookup_not_found'),
            l10n.dictionaryLookupNotFound,
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < outcome.entries.length; i++)
              _entryCard(i, outcome.entries[i]),
          ],
        );
      case OutcomeStatus.notFound:
        return _message(
          const Key('dictionary_lookup_not_found'),
          l10n.dictionaryLookupNotFound,
        );
      case OutcomeStatus.skipped:
        return _message(
          const Key('dictionary_lookup_skipped'),
          l10n.dictionaryLookupOnlineDisabled,
          showSettings: true,
        );
      case OutcomeStatus.failed:
        return _message(
          const Key('dictionary_lookup_failed'),
          l10n.dictionaryLookupFailed,
        );
    }
  }

  Widget _entryCard(int index, DictionaryEntry entry) {
    final theme = Theme.of(context);
    final pronunciation = entry.pronunciation;
    final partOfSpeech = entry.partOfSpeech;
    return Card(
      key: Key('dictionary_lookup_entry_$index'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(entry.headword, style: theme.textTheme.titleMedium),
            if (pronunciation != null && pronunciation.isNotEmpty)
              Text(pinyinToneMarks(pronunciation)),
            if (partOfSpeech != null && partOfSpeech.isNotEmpty)
              Text(partOfSpeech),
            const SizedBox(height: 4),
            // HTML 詞條（Issue 6a）之前一律當純文字；可選取方便使用者複製。
            SelectableText(entry.body),
          ],
        ),
      ),
    );
  }

  Widget _footer(ProviderOutcome outcome) {
    final attribution = outcome.attribution;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Text(
        attribution == null || attribution.isEmpty
            ? outcome.displayName
            : '${outcome.displayName} · $attribution',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _message(Key key, String text, {bool showSettings = false}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (showSettings && widget.onOpenSettings != null) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('dictionary_lookup_open_settings'),
              onPressed: widget.onOpenSettings,
              child: Text(
                AppLocalizations.of(context)!.dictionaryLookupOpenSettings,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
