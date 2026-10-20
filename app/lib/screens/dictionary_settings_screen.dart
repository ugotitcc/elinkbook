import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../dictionary/dictionary_manager.dart';
import '../dictionary/importers/dictionary_importer.dart';
import '../dictionary/mdx_companion_files.dart';
import '../dictionary/models/dictionary_source.dart';
import '../l10n/app_localizations.dart';
import 'widgets/dictionary_import_dialog.dart';

/// 超過此大小的檔案在匯入對話框顯示大檔提示（50 MB）。
const int _largeFileBytes = 50 * 1024 * 1024;

/// 匯入選檔允許的副檔名（不含點）。
const List<String> _importExtensions = [
  'json',
  'csv',
  'txt',
  'u8',
  'mdx',
  'mdd',
  'css',
];

/// 選檔器簽章：傳入允許的副檔名（不含點），回傳選到的檔案；取消回傳 `null`。
typedef DictionaryFilePicker =
    Future<List<PickedFile>?> Function(List<String> extensions);

/// [DictionaryFilePicker] 的預設實作：`FilePicker` 多選，缺本機路徑的檔案略過。
Future<List<PickedFile>?> pickDictionaryFilesViaFilePicker(
  List<String> extensions,
) async {
  final picked = await FilePicker.pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: extensions,
  );
  if (picked == null) return null;
  return [
    for (final f in picked.files)
      if (f.path != null) PickedFile(path: f.path!, name: f.name, size: f.size),
  ];
}

/// 字典設定畫面：清單、啟用開關、拖曳排序、刪除、MDX 缺檔提醒與補附屬檔案。
///
/// 啟用、刪除、補附屬檔案後一律重新讀取清單；唯獨拖曳排序採樂觀更新
/// （先改本地順序再寫入），避免等寫入完成才更新造成項目彈回原位再跳走，
/// E-Ink 上會多刷新一次。寫入失敗才顯示錯誤並重新讀取以還原。
///
/// 匯入進度直接畫在畫面上（一層擋住點擊的遮罩），不用 `showDialog`，所以匯入中
/// 返回鍵只會到畫面自己的 `PopScope`；匯入結束（完成、取消、失敗、重複）一律先清掉
/// 進度遮罩，再彈出後續對話框，不會疊多個層。
class DictionarySettingsScreen extends StatefulWidget {
  const DictionarySettingsScreen({
    super.key,
    required this.manager,
    required this.isEinkMode,
    this.pickFiles,
  });

  final DictionaryManager manager;

  /// E-Ink 模式：不使用動畫與陰影，改以邊框區分。
  final bool isEinkMode;

  /// 選檔器；`null` 時使用 [pickDictionaryFilesViaFilePicker]，供 widget test 注入。
  final DictionaryFilePicker? pickFiles;

  @override
  State<DictionarySettingsScreen> createState() =>
      _DictionarySettingsScreenState();
}

class _DictionarySettingsScreenState extends State<DictionarySettingsScreen> {
  /// 目前清單；`null` 表示尚未載入完成。
  List<DictionaryListItem>? _items;
  bool _loadFailed = false;

  /// 操作（刪除、排序）失敗時顯示在清單上方的訊息；下一次操作前清除。
  String? _actionError;

  /// 整個匯入流程（含對話框）進行中；用來停用匯入按鈕，避免重複觸發。
  bool _flowRunning = false;

  /// 正在寫入字典（進度遮罩顯示中）；為真時攔截返回。
  bool _importing = false;
  ImportProgress? _importProgress;
  CancelToken? _cancelToken;

  /// 使用者已按取消，等待匯入器回報 [ImportStage.cancelled]。
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    // 離開畫面時中止進行中的匯入，匯入器會回復交易。
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final items = await widget.manager.list();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loadFailed = false;
      });
    } catch (error) {
      debugPrint('Failed to load dictionaries: $error');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _setEnabled(DictionaryListItem item, bool enabled) async {
    try {
      await widget.manager.setEnabled(item.source.id, enabled);
    } catch (error) {
      debugPrint('Failed to toggle dictionary: $error');
    }
    await _reload();
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final current = _items;
    if (current == null) return;
    // ReorderableListView 的 newIndex 是「移除前」的位置，往後移時要減 1。
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final reordered = List<DictionaryListItem>.of(current);
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    setState(() {
      _items = reordered;
      _actionError = null;
    });
    try {
      await widget.manager.reorder([for (final i in reordered) i.source.id]);
    } catch (error) {
      debugPrint('Failed to reorder dictionaries: $error');
      if (!mounted) return;
      setState(() {
        _actionError = AppLocalizations.of(
          context,
        )!.dictionarySettingsReorderFailed;
      });
      await _reload();
    }
  }

  Future<void> _confirmDelete(DictionaryListItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.dictionaryDeleteConfirmTitle),
        content: Text(l10n.dictionaryDeleteConfirmMessage(item.source.name)),
        actions: [
          TextButton(
            key: const Key('dictionary_delete_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('dictionary_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.dictionaryDeleteConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actionError = null);
    try {
      await widget.manager.delete(item.source.id);
    } catch (error) {
      debugPrint('Failed to delete dictionary: $error');
      if (!mounted) return;
      setState(() => _actionError = l10n.dictionarySettingsDeleteFailed);
    }
    await _reload();
  }

  Future<void> _addCompanions(DictionaryListItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final pick = widget.pickFiles ?? pickDictionaryFilesViaFilePicker;
    try {
      final files = await pick(const ['css', 'mdd']);
      if (files == null || files.isEmpty) return;
      if (!mounted) return;
      setState(() => _actionError = null);
      await widget.manager.addCompanions(item.source.id, files);
    } catch (error) {
      debugPrint('Failed to add dictionary companions: $error');
      if (!mounted) return;
      setState(() => _actionError = l10n.dictionarySettingsAddCompanionFailed);
    }
    await _reload();
  }

  /// 匯入流程：選檔 → 分組 → 逐檔（對話框 → 匯入）。結果訊息累積後合成一個對話框，
  /// 避免多檔匯入時連續跳多個。每個 await 後都檢查 `mounted`，離開畫面就停止。
  Future<void> _runImportFlow() async {
    if (_flowRunning) return;
    final pick = widget.pickFiles ?? pickDictionaryFilesViaFilePicker;
    final List<PickedFile>? files;
    try {
      files = await pick(_importExtensions);
    } catch (error) {
      debugPrint('Failed to pick dictionary files: $error');
      return;
    }
    if (files == null || files.isEmpty || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _flowRunning = true;
      _actionError = null;
    });
    // 每則訊息是一組文字行。
    final messages = <List<String>>[];
    try {
      final plan = planCompanions(files);
      var mdxNoticeShown = false;
      // 一般檔案逐檔處理；MDX 組只取主檔，附屬檔案留給 MDX 匯入器。
      final queue = [...plan.others, for (final g in plan.groups) g.mdx];
      for (final file in queue) {
        final isMdx = file.name.toLowerCase().endsWith('.mdx');
        final supported = await widget.manager.canImport(file.name);
        if (!mounted) return;
        if (!supported) {
          if (!isMdx) {
            messages.add([l10n.dictionaryImportUnsupportedFile(file.name)]);
          } else if (!mdxNoticeShown) {
            mdxNoticeShown = true;
            messages.add([l10n.dictionaryImportMdxNotYet]);
          }
          continue;
        }
        final ImportHints hints;
        try {
          hints = await widget.manager.readHints(file);
        } catch (error) {
          debugPrint('Failed to read dictionary hints: $error');
          if (!mounted) return;
          messages.add([file.name, _importErrorMessage(l10n, error)]);
          continue;
        }
        if (!mounted) return;
        final choices = await showDictionaryImportDialog(
          context,
          hints: hints,
          initialDirection: DictionaryDirection.fromLangs(
            hints.sourceLang,
            hints.targetLang,
          ),
          isLargeFile: file.size > _largeFileBytes,
          isEinkMode: widget.isEinkMode,
        );
        if (choices == null) continue;
        if (!mounted) return;
        final keepGoing = await _importOne(file, choices, l10n, messages);
        if (!keepGoing || !mounted) break;
      }
      if (!mounted) return;
      if (plan.unmatchedCompanions.isNotEmpty) {
        messages.add([l10n.dictionaryImportOrphanCompanions]);
      }
      if (messages.isNotEmpty) await _showMessages(messages);
    } finally {
      if (mounted) setState(() => _flowRunning = false);
    }
  }

  /// 匯入一個檔案。回傳 `false` 表示使用者取消或已離開畫面，後面的檔案不再處理。
  Future<bool> _importOne(
    PickedFile file,
    ImportChoices choices,
    AppLocalizations l10n,
    List<List<String>> messages,
  ) async {
    var replace = false;
    while (true) {
      final token = CancelToken();
      ImportSummary? summary;
      Object? error;
      var cancelled = false;
      setState(() {
        _importing = true;
        _importProgress = null;
        _cancelToken = token;
        _cancelling = false;
      });
      try {
        final stream = widget.manager.import(
          file,
          ImportRequest(
            filePath: file.path,
            fileName: file.name,
            sourceLang: choices.direction.sourceLang,
            targetLang: choices.direction.targetLang,
            name: choices.name,
            licenseNote: choices.licenseNote,
            replaceExisting: replace,
          ),
          cancel: token,
        );
        await for (final progress in stream) {
          if (!mounted) return false;
          if (progress.stage == ImportStage.cancelled) {
            cancelled = true;
          } else if (progress.stage == ImportStage.done) {
            summary = progress.summary;
          }
          setState(() => _importProgress = progress);
        }
      } catch (e) {
        error = e;
      } finally {
        // 先清掉進度遮罩，後續的對話框才不會疊在它上面。
        _cancelToken = null;
        if (mounted) {
          setState(() {
            _importing = false;
            _importProgress = null;
            _cancelling = false;
          });
        }
      }
      if (!mounted) return false;
      if (cancelled ||
          (error == null && summary == null && token.isCancelled)) {
        return false;
      }
      if (error is DuplicateDictionaryException) {
        final shouldReplace = await _askReplaceDuplicate(l10n);
        if (!mounted) return false;
        if (!shouldReplace) return true;
        replace = true;
        continue;
      }
      if (error != null) {
        debugPrint('Failed to import dictionary: $error');
        messages.add([file.name, _importErrorMessage(l10n, error)]);
        return true;
      }
      if (summary != null) {
        messages.add(_summaryLines(l10n, choices.name, summary));
        await _reload();
      }
      return true;
    }
  }

  Future<bool> _askReplaceDuplicate(AppLocalizations l10n) async {
    final replace = await showDialog<bool>(
      context: context,
      animationStyle: widget.isEinkMode ? AnimationStyle.noAnimation : null,
      builder: (dialogContext) => AlertDialog(
        key: const Key('dictionary_import_duplicate_dialog'),
        title: Text(l10n.dictionaryImportDuplicateTitle),
        content: Text(l10n.dictionaryImportDuplicateMessage),
        actions: [
          TextButton(
            key: const Key('dictionary_import_duplicate_skip'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.dictionaryImportDuplicateSkip),
          ),
          TextButton(
            key: const Key('dictionary_import_duplicate_replace'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.dictionaryImportDuplicateReplace),
          ),
        ],
      ),
    );
    return replace == true;
  }

  Future<void> _showMessages(List<List<String>> messages) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<void>(
      context: context,
      animationStyle: widget.isEinkMode ? AnimationStyle.noAnimation : null,
      builder: (dialogContext) => AlertDialog(
        key: const Key('dictionary_import_message_dialog'),
        title: Text(l10n.dictionaryImportTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < messages.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  for (final line in messages[i]) Text(line),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('dictionary_import_message_close'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  List<String> _summaryLines(
    AppLocalizations l10n,
    String name,
    ImportSummary summary,
  ) {
    return [
      name,
      l10n.dictionaryImportDone(summary.importedCount),
      if (summary.skippedCount > 0) ...[
        l10n.dictionaryImportSkippedSummary(summary.skippedCount),
        for (final skip in summary.skipSamples)
          l10n.dictionaryImportSkipSample(
            skip.index,
            _skipReasonText(l10n, skip.reason),
          ),
      ],
    ];
  }

  /// 略過原因轉文字；未知原因落到「欄位格式不對」，不顯示原始字串。
  String _skipReasonText(AppLocalizations l10n, String reason) =>
      switch (reason) {
        'missingHeadword' => l10n.dictionaryImportSkipMissingHeadword,
        'missingDefinition' => l10n.dictionaryImportSkipMissingDefinition,
        'definitionTooLong' => l10n.dictionaryImportSkipDefinitionTooLong,
        'malformedLine' => l10n.dictionaryImportSkipMalformedLine,
        _ => l10n.dictionaryImportSkipInvalidField,
      };

  /// 匯入錯誤轉三段式訊息；未知錯誤落到通用訊息，不顯示原始碼或例外內容。
  String _importErrorMessage(AppLocalizations l10n, Object error) {
    if (error is DictionaryImportException) {
      return switch (error.code) {
        'unreadableFile' => l10n.dictionaryImportErrorUnreadableFile,
        'invalidEncoding' => l10n.dictionaryImportErrorInvalidEncoding,
        'invalidFormat' => l10n.dictionaryImportErrorInvalidFormat,
        'noValidEntries' => l10n.dictionaryImportErrorNoValidEntries,
        _ => l10n.dictionaryImportErrorGeneric,
      };
    }
    return l10n.dictionaryImportErrorGeneric;
  }

  void _cancelImport() {
    final token = _cancelToken;
    if (token == null || _cancelling) return;
    token.cancel();
    // 等匯入器回報 cancelled 才收掉遮罩；這段時間取消鈕停用。
    setState(() => _cancelling = true);
  }

  /// 匯入中按返回：確認後才取消匯入並離開。
  Future<void> _confirmLeave() async {
    final l10n = AppLocalizations.of(context)!;
    final leave = await showDialog<bool>(
      context: context,
      animationStyle: widget.isEinkMode ? AnimationStyle.noAnimation : null,
      builder: (dialogContext) => AlertDialog(
        key: const Key('dictionary_import_leave_dialog'),
        title: Text(l10n.dictionaryImportLeaveConfirmTitle),
        content: Text(l10n.dictionaryImportLeaveConfirmMessage),
        actions: [
          TextButton(
            key: const Key('dictionary_import_leave_stay'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('dictionary_import_leave_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.dictionaryImportLeaveConfirmAction),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    _cancelToken?.cancel();
    Navigator.of(context).pop();
  }

  String _directionLabel(AppLocalizations l10n, DictionarySource source) {
    // 只看語言碼第一段，zh-Hant／zh-TW／zh-CN 都算中文。
    String head(String lang) => lang.toLowerCase().split(RegExp(r'[-_]')).first;
    final from = head(source.sourceLang);
    final to = head(source.targetLang);
    if (from == 'en' && to == 'zh') return l10n.dictionaryDirectionEnToZh;
    if (from == 'zh' && to == 'en') return l10n.dictionaryDirectionZhToEn;
    if (from == 'zh' && to == 'zh') return l10n.dictionaryDirectionZhToZh;
    return '${source.sourceLang} → ${source.targetLang}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_importing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.dictionarySettingsTitle),
          actions: [
            IconButton(
              key: const Key('dictionary_settings_import_button'),
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: l10n.dictionaryImportButton,
              onPressed: _flowRunning ? null : _runImportFlow,
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _buildBody(context, l10n)),
            if (_importing) _buildProgressOverlay(context, l10n),
          ],
        ),
      ),
    );
  }

  /// 擋住點擊的進度遮罩；點空白處不會關閉。E-Ink 用邊框、不用陰影。
  Widget _buildProgressOverlay(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final progress = _importProgress;
    final processed = progress?.processed ?? 0;
    final total = progress?.total ?? 0;
    return Positioned.fill(
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false),
          Center(
            child: Card(
              key: const Key('dictionary_import_progress'),
              elevation: widget.isEinkMode ? 0 : null,
              shape: widget.isEinkMode
                  ? RoundedRectangleBorder(
                      side: BorderSide(color: theme.colorScheme.onSurface),
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.dictionaryImportProgress(processed, total)),
                    const SizedBox(height: 12),
                    // 固定為進度值；不用不定長度的轉圈動畫，避免 E-Ink 殘影。
                    LinearProgressIndicator(
                      value: total > 0
                          ? (processed / total).clamp(0.0, 1.0)
                          : 0,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      key: const Key('dictionary_import_progress_cancel'),
                      onPressed: _cancelling ? null : _cancelImport,
                      child: Text(l10n.dictionaryImportCancel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final items = _items;
    if (_loadFailed && items == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.dictionarySettingsLoadFailed,
            key: const Key('dictionary_settings_load_error'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            key: const Key('dictionary_settings_empty'),
            children: [
              Text(
                l10n.dictionarySettingsEmpty,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.dictionarySettingsEmptyHint,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        if (_actionError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              _actionError!,
              key: const Key('dictionary_settings_action_error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: ReorderableListView.builder(
            key: const Key('dictionary_settings_list'),
            buildDefaultDragHandles: false,
            itemCount: items.length,
            onReorder: _onReorder,
            // E-Ink 不用拖曳時的陰影與動畫；但拖曳中的列會被提到 Overlay，
            // 脫離 Scaffold 的 Material，Switch 等元件需要 Material 祖先，
            // 所以仍要包一層透明 Material（無 elevation、無陰影）。
            proxyDecorator: widget.isEinkMode
                ? (child, index, animation) =>
                      Material(type: MaterialType.transparency, child: child)
                : null,
            itemBuilder: (context, index) =>
                _buildItem(context, l10n, items[index], index),
          ),
        ),
      ],
    );
  }

  Widget _buildItem(
    BuildContext context,
    AppLocalizations l10n,
    DictionaryListItem item,
    int index,
  ) {
    final source = item.source;
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableDragStartListener(
            key: Key('dictionary_drag_handle_${source.id}'),
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_handle),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(source.name, style: theme.textTheme.titleMedium),
                Text(
                  '${_directionLabel(l10n, source)} · '
                  '${l10n.dictionaryEntryCount(source.entryCount)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (source.licenseNote.isNotEmpty)
                  Text(source.licenseNote, style: theme.textTheme.bodySmall),
                if (source.format == DictionaryFormat.mdx &&
                    item.missingCss.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.dictionaryMissingCssWarning(
                        item.missingCss.join(l10n.dictionaryListSeparator),
                      ),
                      key: Key('dictionary_missing_css_${source.id}'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (source.format == DictionaryFormat.mdx)
                  TextButton(
                    key: Key('dictionary_add_companion_${source.id}'),
                    onPressed: () => _addCompanions(item),
                    child: Text(l10n.dictionaryAddCompanion),
                  ),
              ],
            ),
          ),
          Switch(
            key: Key('dictionary_enabled_${source.id}'),
            value: source.enabled,
            onChanged: (value) => _setEnabled(item, value),
          ),
          IconButton(
            key: Key('dictionary_delete_${source.id}'),
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.dictionaryDeleteConfirmAction,
            onPressed: () => _confirmDelete(item),
          ),
        ],
      ),
    );
    return Container(
      key: Key('dictionary_item_${source.id}'),
      // E-Ink 以邊框區分各列；一般模式用底線分隔，兩者皆不使用陰影。
      decoration: BoxDecoration(
        border: widget.isEinkMode
            ? Border.all(color: theme.colorScheme.onSurface)
            : Border(bottom: BorderSide(color: theme.dividerColor)),
        color: theme.colorScheme.surface,
      ),
      child: content,
    );
  }
}
