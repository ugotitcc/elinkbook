import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../library/library_repository.dart';
import '../reader/app_font.dart';
import '../reader/custom_font.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/font_name_parser.dart';

/// 字型管理畫面（epic-14-system-settings FR-35，spec.md「字型管理模組」）：
/// 顯示內建字型（唯讀）＋使用者上傳的自訂字型（可重新命名／刪除），
/// 支援批次上傳 `.ttf`/`.otf`。
class FontManagementScreen extends StatefulWidget {
  final CustomFontsRepository repository;

  const FontManagementScreen({super.key, required this.repository});

  @override
  State<FontManagementScreen> createState() => _FontManagementScreenState();
}

class _FontManagementScreenState extends State<FontManagementScreen> {
  List<CustomFont> _customFonts = [];
  bool _isUploading = false;
  // 重新命名對話框使用的 TextEditingController，交由本 State 生命週期保管
  // （比照 notes_bottom_sheet.dart 既有先例）：不在 showDialog 呼叫結束後
  // 立即 dispose——showDialog 回傳的 Future 在 Navigator.pop() 當下就完成，
  // 早於 AlertDialog 退場轉場動畫實際跑完，此時其底下的 TextField 仍會在
  // 後續幾個 frame 被重新 build，立即 dispose 會拋出
  // 「TextEditingController used after being disposed」。改為每次重新命名時
  // 若有前一個實例先 dispose，並在 [dispose] 一併清理。
  TextEditingController? _renameController;

  @override
  void initState() {
    super.initState();
    _loadFonts();
  }

  @override
  void dispose() {
    _renameController?.dispose();
    super.dispose();
  }

  Future<void> _loadFonts() async {
    try {
      final fonts = await widget.repository.listAll();
      if (!mounted) return;
      setState(() => _customFonts = fonts);
    } catch (e) {
      debugPrint('Failed to load custom fonts: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.fontManagementTitle),
        actions: [
          IconButton(
            key: const Key('font_management_upload_button'),
            icon: _isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            tooltip: l10n.fontManagementUploadTooltip,
            onPressed: _isUploading ? null : _pickAndUploadFonts,
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(l10n.fontManagementBuiltInSectionLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final font in AppFont.values)
            ListTile(title: Text(font.displayName(l10n))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(l10n.fontManagementCustomSectionLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (_customFonts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l10n.fontManagementNoCustomFontsHint),
            ),
          for (final font in _customFonts)
            ListTile(
              title: Text(font.displayName),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('font_management_rename_button_${font.id}'),
                    icon: const Icon(Icons.edit),
                    tooltip: l10n.fontManagementRenameTooltip,
                    onPressed: () => _renameFont(font),
                  ),
                  IconButton(
                    key: Key('font_management_delete_button_${font.id}'),
                    icon: const Icon(Icons.delete),
                    tooltip: l10n.fontManagementDeleteTooltip,
                    onPressed: () => _deleteFont(font),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadFonts() async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    // identifier 是 Android SAF content:// URI（見 ADR 0021），本專案手機
    // 優先且目前只有 Android 實作，非 Android 平台/桌面測試環境下可能為
    // null，一併過濾避免後續 fontUri 寫入 null。
    final validFiles = picked.files
        .where((f) => f.bytes != null && f.identifier != null)
        .toList();
    if (validFiles.isEmpty) return;

    setState(() => _isUploading = true);
    try {
      final parsedFamilyNames = <String>[];
      for (final file in validFiles) {
        final parsed = parseFontFamilyName(file.bytes!);
        parsedFamilyNames.add(parsed ?? _stripExtension(file.name));
      }

      // 內建 5 款字型的 family name 不存在於 custom_fonts 表（該表只存自訂
      // 字型），必須額外併入重複判定集合——否則上傳一款與內建字型 family
      // name 相同的自訂字型會成功寫入，導致 reader_settings_sheet.dart
      // 的 DropdownButton 出現兩個相同 value 的 DropdownMenuItem，觸發
      // Flutter「exactly one item with value」assertion 崩潰（審查發現，
      // 見 tmp/epic-14/review-plan-issue-2.md Critical）。
      final existing = AppFont.values.map((f) => f.familyName).toSet();
      for (final familyName in parsedFamilyNames.toSet()) {
        if (await widget.repository.familyNameExists(familyName)) {
          existing.add(familyName);
        }
      }

      final outcome = resolveUploadOutcome(
        parsedFamilyNames: parsedFamilyNames,
        alreadyExistingFamilyNames: existing,
      );

      for (final index in outcome.toInsertIndexes) {
        final file = validFiles[index];
        final uri = file.identifier!;
        try {
          await kBookMetadataChannel
              .invokeMethod<void>('takePersistableUriPermission', {'uri': uri});
        } on PlatformException {
          // 部分文件提供者不保證核發可持久化授權（比照書籍匯入既有慣例，
          // book_import_service_impl.dart:201-207）；字型檔案本身刻意不做
          // 落地複本退路（ADR 0021），僅盡力而為，不因此中止整批上傳。
        }
        await widget.repository.insert(CustomFont(
          displayName: _stripExtension(file.name),
          familyName: parsedFamilyNames[index],
          fontUri: uri,
        ));
      }

      await _loadFonts();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(buildUploadResultMessage(
          l10n: l10n,
          addedCount: outcome.addedCount,
          skippedCount: outcome.skippedCount,
        )),
      ));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _renameFont(CustomFont font) async {
    _renameController?.dispose();
    final controller = TextEditingController(text: font.displayName);
    _renameController = controller;
    final l10n = AppLocalizations.of(context)!;
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.fontManagementRenameDialogTitle),
        content: TextField(
          key: const Key('font_management_rename_field'),
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('font_management_rename_confirm'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || font.id == null) return;
    await widget.repository.rename(font.id!, newName);
    await _loadFonts();
  }

  Future<void> _deleteFont(CustomFont font) async {
    final usageCount = await widget.repository.countBooksUsing(font.familyName);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.fontManagementDeleteConfirmTitle(font.displayName)),
        content: usageCount > 0
            ? Text(l10n.fontManagementDeleteConfirmMessage(usageCount))
            : null,
        actions: [
          TextButton(
            key: const Key('font_management_delete_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('font_management_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.fontManagementDeleteTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true || font.id == null) return;
    await widget.repository.deleteAndResetUsage(font.id!, font.familyName);
    await _loadFonts();
  }
}

/// 批次上傳結果：哪些索引（對應呼叫端傳入的 [parsedFamilyNames] 順序）
/// 真的要寫入資料庫，以及新增/跳過各自的計數。同一批次內重複的 family
/// name（例如使用者一次選了兩個內容相同的字型檔）只保留第一次出現的索引，
/// 其餘視同重複一併跳過——不能只靠 [alreadyExistingFamilyNames]（那只反映
/// 資料庫既有資料，抓不到「這一批次自己內部重複」的情況）。
class UploadOutcome {
  final List<int> toInsertIndexes;
  final int addedCount;
  final int skippedCount;
  const UploadOutcome({
    required this.toInsertIndexes,
    required this.addedCount,
    required this.skippedCount,
  });
}

UploadOutcome resolveUploadOutcome({
  required List<String> parsedFamilyNames,
  required Set<String> alreadyExistingFamilyNames,
}) {
  final seenInBatch = <String>{};
  final toInsertIndexes = <int>[];
  var skipped = 0;
  for (var i = 0; i < parsedFamilyNames.length; i++) {
    final familyName = parsedFamilyNames[i];
    final isDuplicate = alreadyExistingFamilyNames.contains(familyName) ||
        !seenInBatch.add(familyName);
    if (isDuplicate) {
      skipped++;
    } else {
      toInsertIndexes.add(i);
    }
  }
  return UploadOutcome(
    toInsertIndexes: toInsertIndexes,
    addedCount: toInsertIndexes.length,
    skippedCount: skipped,
  );
}

String buildUploadResultMessage({
  required AppLocalizations l10n,
  required int addedCount,
  required int skippedCount,
}) {
  if (addedCount > 0 && skippedCount > 0) {
    return l10n.fontManagementUploadBothMessage(addedCount, skippedCount);
  }
  if (addedCount > 0) {
    return l10n.fontManagementUploadAddedOnlyMessage(addedCount);
  }
  return l10n.fontManagementUploadSkippedOnlyMessage(skippedCount);
}

/// 字型檔名去除副檔名，供 [parseFontFamilyName] 回傳 `null`（解析失敗）時
/// 的顯示名稱與 family name 退回依據。
String _stripExtension(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
}

