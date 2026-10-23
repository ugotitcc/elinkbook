import 'package:flutter/material.dart';

import '../../dictionary/importers/dictionary_importer.dart';
import '../../l10n/app_localizations.dart';

/// 字典查詢方向（三個固定選項，使用者必選）。
enum DictionaryDirection {
  enToZh('en', 'zh-Hant'),
  zhToEn('zh', 'en'),
  zhToZh('zh', 'zh-Hant');

  const DictionaryDirection(this.sourceLang, this.targetLang);

  /// 儲存用的固定來源語言碼。
  final String sourceLang;

  /// 儲存用的固定目標語言碼（中文目標一律存 `zh-Hant`）。
  final String targetLang;

  /// 依檔案提示的語言碼推測方向；對不上回傳 `null`。
  ///
  /// 寬容比對：轉小寫、只看第一段（`-`／`_` 之前），所以 `zh-TW`、`zh-CN`、
  /// `zh_HK` 都算中文。
  static DictionaryDirection? fromLangs(String? source, String? target) {
    if (source == null || target == null) return null;
    String head(String lang) =>
        lang.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    final from = head(source);
    final to = head(target);
    if (from == 'en' && to == 'zh') return enToZh;
    if (from == 'zh' && to == 'en') return zhToEn;
    if (from == 'zh' && to == 'zh') return zhToZh;
    return null;
  }

  String label(AppLocalizations l10n) => switch (this) {
    enToZh => l10n.dictionaryDirectionEnToZh,
    zhToEn => l10n.dictionaryDirectionZhToEn,
    zhToZh => l10n.dictionaryDirectionZhToZh,
  };
}

/// 匯入對話框確認後的使用者選擇。
typedef ImportChoices = ({
  String name,
  DictionaryDirection direction,
  String licenseNote,
});

/// 匯入前的確認對話框：名稱與授權預填 [hints]、方向必選。取消回傳 `null`。
Future<ImportChoices?> showDictionaryImportDialog(
  BuildContext context, {
  required ImportHints hints,
  required DictionaryDirection? initialDirection,
  required bool isLargeFile,
  required bool isEinkMode,
}) {
  return showDialog<ImportChoices>(
    context: context,
    // E-Ink 模式不淡入淡出，避免殘影。
    animationStyle: isEinkMode ? AnimationStyle.noAnimation : null,
    builder: (_) => _DictionaryImportDialog(
      hints: hints,
      initialDirection: initialDirection,
      isLargeFile: isLargeFile,
    ),
  );
}

class _DictionaryImportDialog extends StatefulWidget {
  const _DictionaryImportDialog({
    required this.hints,
    required this.initialDirection,
    required this.isLargeFile,
  });

  final ImportHints hints;
  final DictionaryDirection? initialDirection;
  final bool isLargeFile;

  @override
  State<_DictionaryImportDialog> createState() =>
      _DictionaryImportDialogState();
}

class _DictionaryImportDialogState extends State<_DictionaryImportDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.hints.name,
  );
  late final TextEditingController _license = TextEditingController(
    text: widget.hints.licenseNote ?? '',
  );
  late DictionaryDirection? _direction = widget.initialDirection;

  @override
  void dispose() {
    _name.dispose();
    _license.dispose();
    super.dispose();
  }

  void _confirm() {
    final direction = _direction;
    if (direction == null) return;
    final name = _name.text.trim();
    Navigator.of(context).pop((
      // 名稱留空時退回檔案提示的名稱，避免存出空白名稱。
      name: name.isEmpty ? widget.hints.name : name,
      direction: direction,
      licenseNote: _license.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      key: const Key('dictionary_import_dialog'),
      title: Text(l10n.dictionaryImportTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isLargeFile)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    l10n.dictionaryImportLargeFileHint,
                    key: const Key('dictionary_import_large_file_hint'),
                  ),
                ),
              TextField(
                key: const Key('dictionary_import_name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: l10n.dictionaryImportNameLabel,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.dictionaryImportDirectionLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in DictionaryDirection.values)
                    ChoiceChip(
                      key: Key('dictionary_import_direction_${d.name}'),
                      label: Text(d.label(l10n)),
                      selected: _direction == d,
                      onSelected: (_) => setState(() => _direction = d),
                    ),
                ],
              ),
              // 方向未選時「匯入」鈕是灰的，用一行字說明原因，不然使用者會以為卡住。
              if (_direction == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.dictionaryImportDirectionRequiredHint,
                    key: const Key('dictionary_import_direction_hint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('dictionary_import_license'),
                controller: _license,
                decoration: InputDecoration(
                  labelText: l10n.dictionaryImportLicenseLabel,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('dictionary_import_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.dictionaryImportCancel),
        ),
        FilledButton(
          key: const Key('dictionary_import_confirm'),
          // 方向未選時不能送出。
          onPressed: _direction == null ? null : _confirm,
          child: Text(l10n.dictionaryImportConfirm),
        ),
      ],
    );
  }
}
