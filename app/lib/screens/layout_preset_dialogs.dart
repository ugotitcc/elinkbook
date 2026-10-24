import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../reader/layout_preset.dart';
import '../reader/layout_preset_flow.dart';
import 'layout_preset_name_dialog.dart';

/// [LayoutPresetPrompts] 的畫面端實作（epic-54 Issue 26）：把「問使用者的事」
/// 接到真實對話框（取名、覆蓋目標選單、覆蓋／套用／刪除確認）。
///
/// [contextProvider] 回傳 `null` 代表畫面已卸載：顯示對話框**之前**回傳
/// `null` 就直接取消、不呼叫 `showDialog`；對話框**關閉之後**回傳 `null`
/// （對話框開著的期間使用者退出了閱讀器）也一律視為取消。這樣
/// [LayoutPresetFlow] 不需要知道 `mounted`。
class DialogLayoutPresetPrompts implements LayoutPresetPrompts {
  DialogLayoutPresetPrompts({required BuildContext? Function() contextProvider})
      : _contextProvider = contextProvider;

  final BuildContext? Function() _contextProvider;

  /// 統一處理「顯示前後都要確認畫面還在」。
  Future<T?> _show<T>(Future<T?> Function(BuildContext context) show) async {
    final before = _contextProvider();
    if (before == null) return null;
    final result = await show(before);
    if (_contextProvider() == null) return null;
    return result;
  }

  @override
  Future<String?> askName() =>
      _show<String>((context) => showLayoutPresetNameDialog(context));

  @override
  Future<LayoutPreset?> pickOverwriteTarget(List<LayoutPreset> presets) {
    return _show<LayoutPreset>((context) {
      final l10n = AppLocalizations.of(context)!;
      final dateFormat =
          DateFormat.yMd(Localizations.localeOf(context).toString());
      return showDialog<LayoutPreset>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(l10n.readerOverwritePresetPickerTitle),
          children: [
            ...presets.map((preset) => SimpleDialogOption(
                  key: Key('layout_preset_overwrite_option_${preset.id}'),
                  onPressed: () => Navigator.of(dialogContext).pop(preset),
                  child: Text(l10n.readerOverwritePresetOptionLabel(
                    preset.name,
                    dateFormat.format(preset.updatedAt),
                  )),
                )),
            SimpleDialogOption(
              key: const Key('layout_preset_overwrite_cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      );
    });
  }

  @override
  Future<bool> confirmOverwrite(String presetName) async {
    final confirmed = await _show<bool>((context) {
      final l10n = AppLocalizations.of(context)!;
      return showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.readerConfirmOverwriteTitle),
          content: Text(l10n.readerOverwritePresetConfirmMessage(presetName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('layout_preset_overwrite_confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.readerConfirmOverwriteTitle),
            ),
          ],
        ),
      );
    });
    return confirmed ?? false;
  }

  @override
  Future<bool> confirmApplyToOthers(int bookCount) async {
    final confirmed = await _show<bool>((context) {
      final l10n = AppLocalizations.of(context)!;
      return showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.readerConfirmApplyTitle),
          content: Text(l10n.readerApplyToOthersConfirmMessage(bookCount)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('layout_preset_apply_confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.readerConfirmApplyTitle),
            ),
          ],
        ),
      );
    });
    return confirmed ?? false;
  }

  @override
  Future<bool> confirmDelete(String presetName) async {
    final confirmed = await _show<bool>((context) {
      final l10n = AppLocalizations.of(context)!;
      return showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.readerConfirmDeleteTitle),
          content: Text(l10n.readerDeletePresetConfirmMessage(presetName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('layout_preset_delete_confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.readerConfirmDeleteTitle),
            ),
          ],
        ),
      );
    });
    return confirmed ?? false;
  }
}
