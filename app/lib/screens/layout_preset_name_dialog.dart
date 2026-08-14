import 'package:flutter/material.dart';

import '../reader/layout_preset.dart';

/// 版面設定預設集命名輸入 Dialog（epic-28-reader-settings-enhancements
/// Issue 3），比照 `note_edit_dialog.dart` 的既有 controller 生命週期
/// 慣例（`TextEditingController` 綁定在 Dialog 自己的 State，避免退場
/// 動畫尚未跑完就被呼叫端提早 `dispose()`）。回傳通過
/// [validateLayoutPresetName] 驗證、已 trim 的名稱；取消或驗證失敗
/// （trim 後為空字串）回傳 `null`。長度上限 20 字元由 `TextField.maxLength`
/// 原生截斷（spec.md「命名驗證」允許的兩種處理方式之一，`validateLayoutPresetName`
/// 本身也會截斷，雙重保險）。
Future<String?> showLayoutPresetNameDialog(
  BuildContext context, {
  String initialText = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) =>
        _LayoutPresetNameDialog(initialText: initialText),
  );
}

class _LayoutPresetNameDialog extends StatefulWidget {
  final String initialText;
  const _LayoutPresetNameDialog({required this.initialText});

  @override
  State<_LayoutPresetNameDialog> createState() =>
      _LayoutPresetNameDialogState();
}

class _LayoutPresetNameDialogState extends State<_LayoutPresetNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('為預設集命名'),
      content: TextField(
        key: const Key('layout_preset_name_dialog_field'),
        controller: _controller,
        autofocus: true,
        maxLength: 20,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('layout_preset_name_dialog_confirm'),
          onPressed: () {
            final name = validateLayoutPresetName(_controller.text);
            Navigator.of(context).pop(name);
          },
          child: const Text('儲存'),
        ),
      ],
    );
  }
}
