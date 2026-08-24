import 'package:flutter/material.dart';

import '../reader/highlight_style.dart';

/// 選字/框選後浮現的浮動工具列（design.md「使用者流程」步驟 1-2；
/// EPUB（本 Issue）與 PDF（issues.md Issue 3）共用同一組 Widget）。
///
/// epic-27-reader-device-compat Issue 11 改版為雙列：第一列維持螢光筆
/// 三色＋底線＋關閉；第二列永遠顯示複製，並依這次選取是否命中既有畫線/
/// 備註（呼叫端已用 `resolveEpubExistingAnnotation`/
/// `resolvePdfExistingAnnotation` 算好）決定要不要一併顯示刪除按鈕、以及
/// 備註按鈕要顯示「新增」還是「編輯」。這個改版取代了舊有的
/// `_showAnnotationActionDialog`（原本靠原生 `click` 事件觸發，已被真機
/// log 證實會被瀏覽器原生選字搶走，永遠不會觸發，見
/// docs/superpowers/specs/2026-08-24-epic27-issue11-annotation-toolbar-
/// merge-design.md）。
///
/// 點擊螢光筆/底線立即觸發 [onStyleSelected]（呼叫端負責建立劃線，並保持
/// 選取狀態存在讓使用者能接著點備註）；點擊備註觸發 [onNotePressed]
/// （呼叫端依 [hasExistingNote] 決定要開新增還是編輯對話框，本 Widget
/// 只負責顯示對應文字，不含 Dialog 邏輯）；點擊關閉觸發 [onClosePressed]；
/// 點擊複製觸發 [onCopyPressed]（呼叫端負責把選取文字寫入剪貼簿）；
/// [onDeletePressed] 為 `null` 時不顯示刪除按鈕（代表這次選取沒有命中
/// 既有標記），非 `null` 時顯示，`tooltip` 使用 [deleteButtonLabel]。
class AnnotationToolbar extends StatelessWidget {
  final ValueChanged<HighlightStyle> onStyleSelected;
  final VoidCallback onNotePressed;
  final VoidCallback onClosePressed;
  final VoidCallback onCopyPressed;
  final VoidCallback? onDeletePressed;
  final String? deleteButtonLabel;
  final bool hasExistingNote;

  const AnnotationToolbar({
    super.key,
    required this.onStyleSelected,
    required this.onNotePressed,
    required this.onClosePressed,
    required this.onCopyPressed,
    this.onDeletePressed,
    this.deleteButtonLabel,
    this.hasExistingNote = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
                  key: const Key('annotation_toolbar_close'),
                  icon: const Icon(Icons.close),
                  tooltip: '關閉',
                  onPressed: onClosePressed,
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('annotation_toolbar_copy'),
                  icon: const Icon(Icons.copy),
                  tooltip: '複製',
                  onPressed: onCopyPressed,
                ),
                IconButton(
                  key: const Key('annotation_toolbar_note'),
                  icon: const Icon(Icons.edit_note),
                  tooltip: hasExistingNote ? '編輯備註' : '新增備註',
                  onPressed: onNotePressed,
                ),
                if (onDeletePressed != null)
                  IconButton(
                    key: const Key('annotation_toolbar_delete'),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: deleteButtonLabel,
                    onPressed: onDeletePressed,
                  ),
              ],
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
