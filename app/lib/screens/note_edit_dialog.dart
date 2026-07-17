import 'package:flutter/material.dart';

/// 備註文字輸入/編輯共用 Dialog（epic-6-annotations Issue 2，design.md
/// 使用者流程步驟 2／3）：`ReaderScreen` 新增備註與 `NotesBottomSheet`
/// 編輯既有備註文字共用同一個函式。回傳使用者輸入且已 trim 的文字；
/// 取消或空白輸入回傳 `null`。
///
/// 【TextEditingController 生命週期】刻意把輸入框包成獨立的
/// `_NoteTextDialog` StatefulWidget，讓 controller 綁定在這個 Dialog
/// 自己的 State——Flutter 只會在這個 Dialog 的 Element 真正從 widget
/// tree 移除（退場轉場動畫跑完）時才呼叫其 `dispose()`，時機天生正確，
/// 不會重蹈 `NotesBottomSheet._renameController` 當初「showDialog 的
/// Future 提早於退場動畫完成前解析、若在此時同步 dispose 控制器會讓底下
/// TextField 在後續幾個 frame 重新 build 時拋出例外」的覆轍（那個問題
/// 之所以發生，是因為 controller 綁定在呼叫端 State、而非 Dialog 自己
/// 的 State）。
Future<String?> showNoteTextDialog(
  BuildContext context, {
  String initialText = '',
  String title = '備註',
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _NoteTextDialog(initialText: initialText, title: title),
  );
}

class _NoteTextDialog extends StatefulWidget {
  final String initialText;
  final String title;

  const _NoteTextDialog({required this.initialText, required this.title});

  @override
  State<_NoteTextDialog> createState() => _NoteTextDialogState();
}

class _NoteTextDialogState extends State<_NoteTextDialog> {
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
      title: Text(widget.title),
      content: TextField(
        key: const Key('note_edit_dialog_field'),
        controller: _controller,
        autofocus: true,
        maxLines: 4,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('note_edit_dialog_confirm'),
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.of(context).pop(text.isEmpty ? null : text);
          },
          child: const Text('儲存'),
        ),
      ],
    );
  }
}
