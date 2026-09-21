import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../library/models/book_group.dart';

/// 「移動到分類」目的地選擇對話框（Issue 10）：列出目前所有分類（含
/// 「未分類」），點擊即以該分類名稱關閉對話框。不提供新增/重新命名/刪除
/// ——群組本身的管理屬於 Issue 7 的 [LibraryGroupManagementDialog]，本對話
/// 框只負責「從既有分類中選一個」。系統保留分類名稱依目前介面語言轉譯顯示
/// （epic-45-interface-i18n Issue 2），使用者自訂分類原樣顯示。
class LibraryMoveToGroupDialog extends StatelessWidget {
  final List<BookGroup> groups;

  const LibraryMoveToGroupDialog({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SimpleDialog(
      title: Text(l10n.libraryMoveToGroupTitle),
      children: [
        for (final group in groups)
          SimpleDialogOption(
            key: Key('library_move_to_group_option_${group.name}'),
            onPressed: () => Navigator.of(context).pop(group.name),
            child: Text(group.displayName(l10n)),
          ),
        SimpleDialogOption(
          key: const Key('library_move_to_group_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
