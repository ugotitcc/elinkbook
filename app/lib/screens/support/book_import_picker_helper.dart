import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../library/book_import_service.dart';

const _folderPickerChannel = MethodChannel('elinkbook/folder_picker');

/// 挑選一或多個檔案並匯入圖書庫；使用者取消選擇、或選取結果不含可用 URI
/// 時回傳 `null`（呼叫端不需要顯示任何提示）。呼叫端負責後續 UI 回饋
/// （loading 狀態、SnackBar、重新整理書單），本函式不觸碰任何 widget
/// 狀態——原本 `_LibraryScreenState._pickAndImportFiles()` 的邏輯搬遷至此
/// （見 epic-36-adaptive-shelf-navigation spec.md §功能①、審查報告
/// review-spec.md I-5：挑選輔助函式須放在展示層，不可放進純 Dart 的
/// `book_import_service.dart`）。
Future<ImportResult?> pickAndImportFiles(BookImportService importService) async {
  try {
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf', 'txt', 'cbz', 'azw3', 'md'],
    );
    if (picked == null || picked.files.isEmpty) return null;
    // uris／displayNames 必須用同一次過濾（f.identifier != null）建立，保持
    // 逐一對應——分開各自 map 再各自過濾會在有檔案 identifier 為 null 時
    // 位移量不同，導致 displayNames[i] 對應到錯誤的 uris[i]。
    final pickedWithUri =
        picked.files.where((f) => f.identifier != null).toList();
    final uris = pickedWithUri.map((f) => f.identifier!).toList();
    if (uris.isEmpty) return null;
    final displayNames = pickedWithUri.map((f) => f.name).toList();
    return await importService.importFiles(uris, displayNames: displayNames);
  } catch (_) {
    // 原 `_LibraryScreenState._pickAndImportFiles()` 既有的靜默吞例外行為
    // （`FilePicker` 在 Android 遭遇權限拒絕/取消/特定 SAF Provider 錯誤時
    // 會拋出 `PlatformException`），搬遷後維持不變（審查報告 I-2 採納）。
    return null;
  }
}

/// 挑選一個資料夾並匯入圖書庫；使用者取消選擇資料夾、或取消「是否依資料夾
/// 名稱自動建立分類」確認對話框時回傳 `null`。[confirmAutoGroup] 由呼叫端
/// 提供（負責彈出確認對話框並自行檢查 `context.mounted`——原本
/// `_LibraryScreenState` 在資料夾選擇器等待期間的 `if (!mounted) return;`
/// 保護，現在由呼叫端的閉包自行負責）。
Future<ImportResult?> pickAndImportFolder(
  BookImportService importService, {
  required Future<bool?> Function() confirmAutoGroup,
}) async {
  try {
    final folderUri =
        await _folderPickerChannel.invokeMethod<String>('pickFolder');
    if (folderUri == null) return null;
    final autoGroup = await confirmAutoGroup();
    if (autoGroup == null) return null;
    return await importService.importFolder(
      folderUri,
      autoGroupByFolderName: autoGroup,
    );
  } catch (_) {
    // 同上，維持原 `_pickAndImportFolder()` 既有的靜默吞例外行為
    // （審查報告 I-2 採納）。
    return null;
  }
}

/// 「是否依資料夾名稱自動建立分類」確認對話框（原
/// `_LibraryScreenState._confirmAutoGroupByFolderName()`，逐字搬遷）。
Future<bool?> confirmAutoGroupByFolderName(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  var autoGroup = true;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(l10n.libraryImportFolderDialogTitle),
        content: CheckboxListTile(
          key: const Key('library_import_folder_auto_group_checkbox'),
          value: autoGroup,
          onChanged: (value) => setDialogState(() => autoGroup = value ?? true),
          title: Text(l10n.libraryImportFolderAutoGroupLabel),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('library_import_folder_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(autoGroup),
            child: Text(l10n.libraryImportFolderConfirmButton),
          ),
        ],
      ),
    ),
  );
}

/// 匯入完成後顯示單一合併提示：成功匯入本數與（若有）因來源 URI 與既有
/// 書籍重複而被跳過的本數。兩者皆為 0 時不顯示任何提示（原
/// `_LibraryScreenState._showImportResultSnackBar()`，逐字搬遷）。
void showImportResultSnackBar(BuildContext context, ImportResult result) {
  final importedCount = result.importedBooks.length;
  final skippedCount = result.skippedDuplicateCount;
  if (importedCount <= 0 && skippedCount <= 0) return;
  final l10n = AppLocalizations.of(context)!;
  final message = importedCount > 0
      ? (skippedCount > 0
          ? l10n.libraryImportResultBothMessage(
              importedCount,
              skippedCount,
            )
          : l10n.libraryImportResultImportedOnlyMessage(importedCount))
      : l10n.libraryImportResultSkippedOnlyMessage(skippedCount);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
