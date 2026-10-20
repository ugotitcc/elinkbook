import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../dictionary/dictionary_manager.dart';
import '../dictionary/mdx_companion_files.dart';
import '../dictionary/models/dictionary_source.dart';
import '../l10n/app_localizations.dart';

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

  @override
  void initState() {
    super.initState();
    _reload();
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dictionarySettingsTitle)),
      body: _buildBody(context, l10n),
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
            // E-Ink 不用拖曳時的陰影與動畫，直接回傳原 Widget。
            proxyDecorator: widget.isEinkMode
                ? (child, index, animation) => child
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
    final separator = Localizations.localeOf(context).languageCode == 'zh'
        ? '、'
        : ', ';
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
                        item.missingCss.join(separator),
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
