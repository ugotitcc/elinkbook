import 'dart:io';

import 'package:path/path.dart' as p;

import '../../library/book_import_service.dart';
import '../../library/book_update_models.dart';
import '../../library/models/book.dart';

/// 拖入路徑分類結果（epic-66 Issue 5 Task 5）。
typedef DroppedPaths = ({List<String> files, List<String> folders});

/// 將拖入的本機路徑清單去重（保持首次出現順序），並以
/// [FileSystemEntity.isDirectorySync] 分出資料夾與檔案（不存在的路徑視為檔案）。
DroppedPaths classifyDroppedPaths(List<String> paths) {
  final seen = <String>{};
  final files = <String>[];
  final folders = <String>[];
  for (final path in paths) {
    if (!seen.add(path)) continue;
    if (FileSystemEntity.isDirectorySync(path)) {
      folders.add(path);
    } else {
      files.add(path);
    }
  }
  return (files: files, folders: folders);
}

/// 匯入拖入的本機路徑清單（epic-66 Issue 5 Task 5）。
///
/// - [paths] 為空時直接回傳 `null`。
/// - 含資料夾時先呼叫一次 [confirmAutoGroup]；若回傳 `null` 代表使用者取消確認框，
///   整批（含同次拖入的單檔）皆不匯入並回傳 `null`。
/// - 檔案批次呼叫一次 [BookImportService.importFiles]，各資料夾逐一呼叫
///   [BookImportService.importFolder]，最後合併結果。
Future<ImportResult?> importDroppedPaths(
  BookImportService importService,
  List<String> paths, {
  required Future<bool?> Function() confirmAutoGroup,
}) async {
  final classified = classifyDroppedPaths(paths);
  if (classified.files.isEmpty && classified.folders.isEmpty) {
    return null;
  }

  bool autoGroup = true;
  if (classified.folders.isNotEmpty) {
    final confirmed = await confirmAutoGroup();
    if (confirmed == null) return null;
    autoGroup = confirmed;
  }

  ImportResult? filesResult;
  if (classified.files.isNotEmpty) {
    final displayNames = classified.files.map(p.basename).toList();
    filesResult = await importService.importFiles(
      classified.files,
      displayNames: displayNames,
    );
  }

  final folderResults = <ImportResult>[];
  for (final folderPath in classified.folders) {
    final folderResult = await importService.importFolder(
      folderPath,
      autoGroupByFolderName: autoGroup,
    );
    folderResults.add(folderResult);
  }

  return _mergeResults(filesResult: filesResult, folderResults: folderResults);
}

ImportResult _mergeResults({
  required ImportResult? filesResult,
  required List<ImportResult> folderResults,
}) {
  final importedBooks = <Book>[];
  final updateCandidates = <BookUpdateCandidate>[];
  var skippedDuplicateCount = 0;
  var skippedUnsupportedCount = 0;

  if (filesResult != null) {
    importedBooks.addAll(filesResult.importedBooks);
    updateCandidates.addAll(filesResult.updateCandidates);
    skippedDuplicateCount += filesResult.skippedDuplicateCount;
    skippedUnsupportedCount += filesResult.skippedUnsupportedCount;
  }

  for (final r in folderResults) {
    importedBooks.addAll(r.importedBooks);
    updateCandidates.addAll(r.updateCandidates);
    skippedDuplicateCount += r.skippedDuplicateCount;
    skippedUnsupportedCount += r.skippedUnsupportedCount;
  }

  final allFoldersFailed =
      folderResults.isNotEmpty && folderResults.every((r) => r.failure != null);
  final failure = (filesResult == null && allFoldersFailed)
      ? folderResults.first.failure
      : null;

  return ImportResult(
    importedBooks: importedBooks,
    skippedDuplicateCount: skippedDuplicateCount,
    skippedUnsupportedCount: skippedUnsupportedCount,
    updateCandidates: updateCandidates,
    failure: failure,
  );
}
