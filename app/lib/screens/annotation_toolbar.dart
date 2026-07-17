import 'package:flutter/material.dart';

import '../reader/highlight_style.dart';

/// 選字/框選後浮現的浮動工具列（design.md「使用者流程」步驟 1-2；
/// EPUB（本 Issue）與 PDF（issues.md Issue 3）共用同一組 Widget）：
/// 螢光筆三色、底線、備註共 5 個按鈕。點擊螢光筆/底線立即觸發
/// [onStyleSelected]（呼叫端負責建立劃線，並保持選取狀態存在讓使用者
/// 能接著點備註，見 design.md 使用者流程「若同時已選色/底線，備註與
/// 劃線共存於同一筆記錄」）；點擊備註觸發 [onNotePressed]（呼叫端負責
/// 另外呼叫 `showNoteTextDialog` 開啟輸入 Dialog，本 Widget 不含 Dialog
/// 邏輯，維持單一職責）。
class AnnotationToolbar extends StatelessWidget {
  final ValueChanged<HighlightStyle> onStyleSelected;
  final VoidCallback onNotePressed;

  const AnnotationToolbar({
    super.key,
    required this.onStyleSelected,
    required this.onNotePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _colorButton(
              key: const Key('annotation_toolbar_highlighter_yellow'),
              color: highlighterYellowTint,
              onTap: () => onStyleSelected(HighlightStyle.highlighterYellow),
            ),
            _colorButton(
              key: const Key('annotation_toolbar_highlighter_pink'),
              color: highlighterPinkTint,
              onTap: () => onStyleSelected(HighlightStyle.highlighterPink),
            ),
            _colorButton(
              key: const Key('annotation_toolbar_highlighter_blue'),
              color: highlighterBlueTint,
              onTap: () => onStyleSelected(HighlightStyle.highlighterBlue),
            ),
            IconButton(
              key: const Key('annotation_toolbar_underline'),
              icon: const Icon(Icons.format_underline),
              tooltip: '底線',
              onPressed: () => onStyleSelected(HighlightStyle.underline),
            ),
            IconButton(
              key: const Key('annotation_toolbar_note'),
              icon: const Icon(Icons.edit_note),
              tooltip: '備註',
              onPressed: onNotePressed,
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorButton({
    required Key key,
    required Color color,
    required VoidCallback onTap,
  }) {
    return IconButton(
      key: key,
      icon: Icon(Icons.circle, color: color),
      onPressed: onTap,
    );
  }
}
