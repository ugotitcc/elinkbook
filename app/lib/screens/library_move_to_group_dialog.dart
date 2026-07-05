import 'package:flutter/material.dart';

import '../library/models/book_group.dart';

/// 「移動到分類」目的地選擇對話框（Issue 10）：列出目前所有分類（含
/// 「未分類」），點擊即以該分類名稱關閉對話框。不提供新增/重新命名/刪除
/// ——群組本身的管理屬於 Issue 7 的 [LibraryGroupManagementDialog]，本對話
/// 框只負責「從既有分類中選一個」。
class LibraryMoveToGroupDialog extends StatelessWidget {
  final List<BookGroup> groups;

  const LibraryMoveToGroupDialog({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('移動到分類'),
      children: [
        for (final group in groups)
          SimpleDialogOption(
            key: Key('library_move_to_group_option_${group.name}'),
            onPressed: () => Navigator.of(context).pop(group.name),
            child: Text(group.name),
          ),
        SimpleDialogOption(
          key: const Key('library_move_to_group_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
