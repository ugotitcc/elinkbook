import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../library/library_repository.dart';
import '../library/models/book_group.dart';

/// 分類群組管理對話框（FR-33）：支援新增/重新命名/刪除群組。「未分類」
/// 為系統保留群組，UI 層面不提供重新命名/刪除按鈕（見
/// docs/epics/epic-1-library/issues.md Issue 7 驗收標準）。刪除前必須經過
/// 二次確認對話框。呼叫端（LibraryScreen）於對話框關閉後一律重新載入群組
/// 與書籍清單，不論使用者實際上是否做了任何變更。新增/重新命名時會先經
/// [isReservedGroupName] 前端攔截三語言任一保留字（epic-45-interface-i18n
/// Issue 2），避免使用者建立出切換語言後與系統保留分類撞名的分類。
class LibraryGroupManagementDialog extends StatefulWidget {
  final LibraryRepository repository;
  final List<BookGroup> initialGroups;

  const LibraryGroupManagementDialog({
    super.key,
    required this.repository,
    required this.initialGroups,
  });

  @override
  State<LibraryGroupManagementDialog> createState() =>
      _LibraryGroupManagementDialogState();
}

class _LibraryGroupManagementDialogState
    extends State<LibraryGroupManagementDialog> {
  late List<BookGroup> _groups;
  final _addController = TextEditingController();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _groups = List.of(widget.initialGroups);
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _reloadGroups() async {
    final groups = await widget.repository.listGroups();
    if (!mounted) return;
    setState(() => _groups = groups);
  }

  Future<void> _addGroup() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _addController.text.trim();
    if (name.isEmpty) return;
    if (isReservedGroupName(name)) {
      setState(() => _errorMessage = l10n.libraryGroupReservedNameError(name));
      return;
    }
    try {
      await widget.repository.upsertGroup(name);
      if (!mounted) return;
      _addController.clear();
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = l10n.errorOperationFailed);
    }
  }

  Future<void> _renameGroup(String oldName) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final dialogL10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(dialogL10n.libraryGroupRenameTitle),
          content: TextField(
            key: const Key('library_group_rename_field'),
            controller: controller,
            onSubmitted: (val) => Navigator.of(dialogContext).pop(val.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(dialogL10n.cancel),
            ),
            TextButton(
              key: const Key('library_group_rename_confirm'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(dialogL10n.confirm),
            ),
          ],
        );
      },
    );
    // 延遲 dispose 以避免在 dialog widget 樹仍在 teardown 時存取已釋放的
    // TextEditingController。使用 addPostFrameCallback() 確保整個 frame cycle
    // 完成後再進行清理。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    if (newName == null || newName.isEmpty || newName == oldName) return;
    if (isReservedGroupName(newName)) {
      if (!mounted) return;
      setState(
        () => _errorMessage = l10n.libraryGroupReservedNameError(newName),
      );
      return;
    }
    try {
      await widget.repository.renameGroup(oldName, newName);
      if (!mounted) return;
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = l10n.errorOperationFailed);
    }
  }

  Future<void> _confirmDeleteGroup(String name) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogL10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(dialogL10n.libraryGroupDeleteTitle),
          content: Text(
            dialogL10n.libraryGroupDeleteConfirmMessage(
              name,
              dialogL10n.groupUncategorized,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogL10n.cancel),
            ),
            TextButton(
              key: const Key('library_group_delete_confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogL10n.libraryGroupDeleteButton),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteGroup(name);
      if (!mounted) return;
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = l10n.errorOperationFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.libraryGroupManageTitle),
      content: SizedBox(
        width: double.maxFinite,
        // 【診斷修正，見 tmp/epic-18/分類異常.jpg】分類數量較多時，下方的
        // 「新增分類名稱」欄位取得焦點、系統鍵盤彈出後，AlertDialog 可用
        // 高度會被 MediaQuery.viewInsets.bottom 壓縮，但這個 Column 本身
        // 不會跟著收縮（分類清單固定用 maxHeight: 240 的 ConstrainedBox），
        // 導致底部溢位（真機回報 BOTTOM OVERFLOWED BY 21 PIXELS）。改用
        // SingleChildScrollView 包住整個內容，鍵盤把可用高度壓縮到不足時
        // 改為讓整個對話框內容可捲動，而不是讓 RenderFlex 溢位（比照既有
        // pdf_settings_sheet.dart 處理類似鍵盤/視窗高度不足情境的既有寫法）。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  key: const Key('library_group_manage_list'),
                  shrinkWrap: true,
                  itemCount: _groups.length,
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    final isProtected = group.name == BookGroup.uncategorized;
                    return ListTile(
                      key: Key('library_group_manage_item_${group.name}'),
                      title: Text(group.displayName(l10n)),
                      trailing: isProtected
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: Key(
                                    'library_group_rename_button_${group.name}',
                                  ),
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () => _renameGroup(group.name),
                                ),
                                IconButton(
                                  key: Key(
                                    'library_group_delete_button_${group.name}',
                                  ),
                                  icon: const Icon(Icons.delete, size: 20),
                                  onPressed: () =>
                                      _confirmDeleteGroup(group.name),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('library_group_add_field'),
                controller: _addController,
                decoration: InputDecoration(
                  labelText: l10n.libraryGroupAddFieldLabel,
                ),
                onSubmitted: (_) => _addGroup(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('library_group_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
        TextButton(
          key: const Key('library_group_add_button'),
          onPressed: _addGroup,
          child: Text(l10n.libraryGroupAddButton),
        ),
      ],
    );
  }
}
