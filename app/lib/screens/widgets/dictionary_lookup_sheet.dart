import 'package:flutter/material.dart';

import '../../dictionary/dictionary_service.dart';
import '../../dictionary/lookup_text_normalizer.dart';
import '../../dictionary/models/dictionary_entry.dart';
import '../../dictionary/models/lookup_result.dart';
import '../../dictionary/pinyin_tone_marks.dart';
import '../../l10n/app_localizations.dart';
import 'eb_sheet_shell.dart';
import 'mdx_entry_view.dart';

/// 字典查詢面板（epic-63 Issue 4）：顯示 [DictionaryService.lookup] 的結果。
///
/// 純 Flutter，HTML 詞條交給注入的 [MdxEntryViewBuilder]（預設
/// [MdxEntryView]）顯示；`EntryBodyKind.plainText` 維持原本的卡片列表。
/// 面板收到一個 `Future<DictionaryLookupResponse>`，依回傳型別分派到各狀態
/// 畫面；分段切換只改 `setState`，不重新查詢。
///
/// MDX 詞條內的 `entry://` 連結會用 [lookupInSource] 查同一本字典，成功時
/// 把目前詞條推入返回堆疊；查無只顯示提示、不推入。堆疊非空時查詢詞標題列
/// 左側出現返回鈕，系統返回鍵也會先回退詞條（見 [PopScope]）。
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
    this.mdxEntryViewBuilder,
    this.lookupInSource,
  });

  /// 這次查詢的選取文字（原字串；去標點與長度判斷由服務負責）。
  final String selectedText;

  /// 面板的查詢結果。由呼叫端先發查詢再傳進來，面板本身只等結果。
  final Future<DictionaryLookupResponse> response;

  final bool isEinkMode;

  /// 「前往字典設定」入口；`null` 時不顯示連結（設定畫面是 Issue 5）。
  final VoidCallback? onOpenSettings;

  /// MDX 詞條顯示元件的建構函式；`null` 時建 [MdxEntryView]。測試注入假
  /// 元件，才能在不建 WebView 的情況下驗證版面與返回堆疊。
  final MdxEntryViewBuilder? mdxEntryViewBuilder;

  /// 交叉參照用的單一來源查詢（[DictionaryService.lookupInSource]）。
  /// `null` 時詞條連結不會有反應。
  final Future<List<DictionaryEntry>> Function(String sourceId, String word)?
      lookupInSource;

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
        // 面板只需要 service 的這一個方法；`show` 組好再傳入，呼叫端不必
        // 重複接線（Issue 6a Task 7）。
        lookupInSource: service.lookupInSource,
      ),
    );
  }

  @override
  State<DictionaryLookupSheet> createState() => _DictionaryLookupSheetState();
}

class _DictionaryLookupSheetState extends State<DictionaryLookupSheet> {
  /// 使用者選的分段；`null` 時用預設規則（第一個 `found`，都沒有就第一個）。
  String? _selectedProviderId;

  /// 目前顯示的 MDX 詞條（`null` 表示還在看這次查詢的原始詞條）。
  _MdxFrame? _mdxFrame;

  /// 返回堆疊：每一層記錄「跳走之前正在看的詞條」。
  final List<_MdxFrame> _mdxStack = [];

  /// 交叉參照查無詞條的提示；下一次成功跳轉、返回或切換分段時清除。
  bool _linkNotFound = false;

  /// 讓晚到的交叉參照結果失效：返回或切換分段後，先前送出的查詢不能把
  /// 詞條推回堆疊。
  int _navigationRequest = 0;

  /// 查詢詞標題列顯示的詞：跳轉後顯示新詞，返回後回到上一層。
  String get _currentWord => _mdxFrame?.word ?? widget.selectedText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<DictionaryLookupResponse>(
      future: widget.response,
      builder: (context, snapshot) {
        // 查詢的詞固定釘在面板頂端（不分狀態）：使用者從選取叫出面板後，
        // 捲動詞條或來回切換分段時仍看得到自己在查哪個詞（spec §3.6）。
        //
        // 系統返回（審查 M-4）：堆疊非空時先回退詞條，空了才讓路由 pop。
        return PopScope(
          canPop: _mdxStack.isEmpty,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _popMdxFrame();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _queryWordHeader(l10n),
              if (_linkNotFound) _linkNotFoundHint(l10n),
              Flexible(child: _content(snapshot, l10n)),
            ],
          ),
        );
      },
    );
  }

  Widget _queryWordHeader(AppLocalizations l10n) {
    final canGoBack = _mdxStack.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(canGoBack ? 4 : 16, 4, 16, 8),
      child: Row(
        children: [
          if (canGoBack)
            IconButton(
              key: const Key('dictionary_lookup_back'),
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.dictionaryLookupBack,
              onPressed: _popMdxFrame,
            ),
          Expanded(
            child: Text(
              _currentWord,
              key: const Key('dictionary_lookup_query_word'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkNotFoundHint(AppLocalizations l10n) {
    return Padding(
      key: const Key('dictionary_lookup_link_not_found'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        l10n.dictionaryLookupLinkNotFound,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
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
    // HTML 詞條獨佔面板剩餘高度（spec §3.6）；純文字沿用可捲動的卡片列表。
    final mdxView = _mdxEntryView(outcome);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (outcomes.length > 1) ...[
          const SizedBox(height: 4),
          _segmentBar(outcomes, selectedId, l10n),
        ],
        if (mdxView != null)
          Expanded(child: mdxView)
        else
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

  /// 這個分段是不是 MDX（HTML）詞條；是的話回傳要放的元件。
  ///
  /// 同一個詞頭可能有多筆記錄（多個義項），合成一份文件後仍只建一個
  /// WebView——面板一次最多一個 `InAppWebView`。
  Widget? _mdxEntryView(ProviderOutcome outcome) {
    if (outcome.status != OutcomeStatus.found || outcome.entries.isEmpty) {
      return null;
    }
    if (outcome.entries.first.bodyKind != EntryBodyKind.html) return null;

    final html = _mdxFrame?.html ?? _mergeEntryHtml(outcome.entries);
    final builder = widget.mdxEntryViewBuilder ?? _buildDefaultMdxEntryView;
    // 以分段的 providerId 當 key：切換到另一本 MDX 時丟棄舊 WebView、建立新的
    // （spec §3.6），不沿用舊的捲動位置與導覽歷史。
    return KeyedSubtree(
      key: ValueKey(outcome.providerId),
      child: builder(
        context,
        MdxEntryViewConfig(
          sourceId: outcome.providerId,
          html: html,
          onEntryLink: (word) => _followEntryLink(
            sourceId: outcome.providerId,
            word: word,
            currentHtml: html,
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultMdxEntryView(
    BuildContext context,
    MdxEntryViewConfig config,
  ) =>
      MdxEntryView(config: config);

  String _mergeEntryHtml(List<DictionaryEntry> entries) {
    if (entries.length == 1) return entries.first.body;
    // 多個義項用 `<hr>` 分隔；`prepareEntryHtml` 之後才是完整文件。
    return entries.map((entry) => entry.body).join('\n<hr>\n');
  }

  /// 詞條內的交叉參照：查同一本字典，成功就把目前詞條推入堆疊。
  Future<void> _followEntryLink({
    required String sourceId,
    required String word,
    required String currentHtml,
  }) async {
    final lookup = widget.lookupInSource;
    if (lookup == null) return;

    final request = ++_navigationRequest;
    List<DictionaryEntry> entries;
    try {
      entries = await lookup(sourceId, word);
    } on Object {
      // 交叉參照失敗不讓整個面板崩掉；比照查無詞條顯示提示。
      entries = const [];
    }
    // 等待期間使用者可能已返回或切換分段：丟掉這筆結果。
    if (!mounted || request != _navigationRequest) return;

    if (entries.isEmpty) {
      setState(() => _linkNotFound = true);
      return;
    }

    final html = _mergeEntryHtml(entries);
    setState(() {
      _mdxStack.add(_MdxFrame(word: _currentWord, html: currentHtml));
      _mdxFrame = _MdxFrame(word: word, html: html);
      _linkNotFound = false;
    });
  }

  /// 返回上一層詞條；堆疊空了就回到這次查詢的原始詞條。
  void _popMdxFrame() {
    if (_mdxStack.isEmpty) return;
    _navigationRequest++;
    setState(() {
      final previous = _mdxStack.removeLast();
      // 堆疊空了代表已經回到最初那一筆：`_mdxFrame` 設回 null，改用
      // 查詢結果本身的 HTML 與 `selectedText`，不必另外留一份快照。
      _mdxFrame = _mdxStack.isEmpty ? null : previous;
      _linkNotFound = false;
    });
  }

  void _resetMdxNavigation() {
    _navigationRequest++;
    _mdxStack.clear();
    _mdxFrame = null;
    _linkNotFound = false;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // 每個標籤最多佔面板寬度的 45%，且 N 個分段加上按鈕內距與外側邊距
        // 要放得進面板（兩個分段時不必橫向捲動）；至少留 96dp 避免標籤太窄。
        const barPadding = 32.0;
        const segmentChrome = 32.0;
        final fitWidth =
            (constraints.maxWidth - barPadding) / outcomes.length -
                segmentChrome;
        final maxLabelWidth =
            fitWidth.clamp(96.0, constraints.maxWidth * 0.45).toDouble();
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
                    maxWidth: maxLabelWidth,
                  ),
                ),
            ],
            selected: {selectedId},
            onSelectionChanged: (selection) {
              setState(() {
                _selectedProviderId = selection.first;
                // 切換分段就丟棄上一個 WebView 與它的返回堆疊，不同時保留兩個。
                _resetMdxNavigation();
              });
            },
            // 這裡刻意不設 `style.side`：`SegmentedButton` 只把它套在外框與
            // 分段之間的垂直分隔線，選中分段自己的邊框不會被畫出來（【final
            // review I-2】）。E-Ink 的「選中」改由標籤外框呈現。
          ),
        );
      },
    );
  }

  /// E-Ink 用邊框標示選中的分段（陰影在電子紙上會殘影）；其餘情況回傳純
  /// 文字，讓 `SegmentedButton` 維持自身預設的選中樣式。
  ///
  /// 名稱過長時只截斷名稱（單行、省略號），狀態後綴固定可見；長按顯示含
  /// 後綴的完整名稱。
  Widget _segmentLabelWidget(
    ProviderOutcome outcome, {
    required bool isSelected,
    required AppLocalizations l10n,
    required ColorScheme colorScheme,
    required double maxWidth,
  }) {
    final suffix = _segmentSuffix(outcome, l10n);
    final label = Tooltip(
      message: '${outcome.displayName}$suffix',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                outcome.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
            if (suffix.isNotEmpty) Text(suffix, maxLines: 1, softWrap: false),
          ],
        ),
      ),
    );
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
  String _segmentSuffix(ProviderOutcome outcome, AppLocalizations l10n) =>
      switch (outcome.status) {
        OutcomeStatus.found => '',
        OutcomeStatus.notFound => l10n.dictionaryLookupSegmentNotFound,
        OutcomeStatus.skipped => l10n.dictionaryLookupSegmentSkipped,
        OutcomeStatus.failed => l10n.dictionaryLookupSegmentFailed,
      };

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
          _failedMessageFor(outcome.errorCode, l10n),
        );
    }
  }

  /// 線上分段的失敗訊息依錯誤碼細分（spec §3.7 三段式）；本機或其他未知
  /// 錯誤維持原本的通用訊息。
  String _failedMessageFor(String? errorCode, AppLocalizations l10n) =>
      switch (errorCode) {
        'unparseable' => l10n.dictionaryLookupOnlineUnparseable,
        'timeout' ||
        'network' ||
        'httpError' ||
        'offline' ||
        'insecureUrl' =>
          l10n.dictionaryLookupOnlineFailed,
        _ => l10n.dictionaryLookupFailed,
      };

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
            // 只有純文字詞條會走到這裡；HTML 詞條由 `_mdxEntryView` 交給
            // WebView（Issue 6a）。可選取方便使用者複製。
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

/// 返回堆疊的一層：跳走之前正在看的詞條（詞與當下的 HTML）。
class _MdxFrame {
  const _MdxFrame({required this.word, required this.html});

  final String word;
  final String html;
}
