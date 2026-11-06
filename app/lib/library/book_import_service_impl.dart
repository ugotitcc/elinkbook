import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../search/full_text_search_settings_repository.dart';
import '../storage/storage_permission.dart';
import '../theme/app_theme_preferences.dart';
import 'book_content_fingerprint.dart';
import 'book_import_service.dart';
import 'book_update_models.dart';
import 'cbz_import.dart';
import 'content_uri_reader.dart';
import 'kf8_metadata.dart';
import 'library_repository.dart';
import 'md_frontmatter.dart';
import 'models/book.dart';
import 'models/book_group.dart';
import 'models/library_enums.dart';
import 'md_epub_synthesizer.dart';
import 'txt_cover_generator.dart';
import 'txt_epub_synthesizer.dart';
import 'update_staging.dart';

/// 跨平台書籍詮釋資料解析器函式簽名（epic-66 Issue 2 Task 5）。
///
/// 依給定檔案 URI／路徑與格式（如 `'epub'`、`'pdf'`）非同步取得詮釋資料 map，
/// 格式相容於 Android `kBookMetadataChannel` 的 `extractMetadata` 契約。
typedef BookMetadataExtractor = Future<Map<String, Object?>?> Function(
  String uri,
  String format,
);

/// 依 URI/路徑字串最後一段（已對 percent-encoding 解碼）判斷書籍格式。
/// 只依副檔名判斷，僅適用於本機檔案匯入（file_picker/SAF 對本機檔案提供者
/// 通常會在 URI 中保留可辨識的原始檔名+副檔名）；不適用於雲端服務自訂的
/// 不透明文件 ID（雲端匯入本身不在本 epic 範圍內）。
BookFileFormat? detectBookFileFormat(String uriOrPath) {
  final name = _lastPathComponent(uriOrPath).toLowerCase();
  if (name.endsWith('.epub')) return BookFileFormat.epub;
  if (name.endsWith('.pdf')) return BookFileFormat.pdf;
  if (name.endsWith('.txt')) return BookFileFormat.txt;
  if (name.endsWith('.azw3')) return BookFileFormat.azw3;
  if (name.endsWith('.cbz')) return BookFileFormat.cbz;
  if (name.endsWith('.md')) return BookFileFormat.md;
  return null;
}

/// 依檔案 URI 與顯示名稱判定書籍格式（displayName 優先、無法辨識時退回 URI）。
/// epic-67 Issue 3 抽出為頂層公開函式供手動更新流程與服務內部共用。
BookFileFormat? detectImportFileFormat(String uri, String? displayName) =>
    (displayName != null && displayName.isNotEmpty
        ? detectBookFileFormat(displayName)
        : null) ??
    detectBookFileFormat(uri);

/// 從 URI/路徑字串取出檔名（去除副檔名），供詮釋資料提取失敗時的降級標題、
/// 以及 TXT 格式的封面文字使用。
String titleFromFileName(String uriOrPath) {
  final name = _lastPathComponent(uriOrPath);
  final dotIndex = name.lastIndexOf('.');
  return dotIndex > 0 ? name.substring(0, dotIndex) : name;
}

String _lastPathComponent(String uriOrPath) {
  // displayName 可能是未經 percent-encoding 的原始檔名（例如 file_picker 的
  // PlatformFile.name，見呼叫端註解），Uri.decodeFull 對這類不含合法
  // percent-encoding 序列的字串會拋出 FormatException（即使字串本身完全
  // 沒有 '%' 字元）；此時視為不需解碼，直接使用原字串。
  String decoded;
  try {
    decoded = Uri.decodeFull(uriOrPath);
  } on ArgumentError {
    decoded = uriOrPath;
  }
  final normalized = decoded.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isNotEmpty ? segments.last : normalized;
}

class BookImportServiceImpl implements BookImportService {
  BookImportServiceImpl({
    required LibraryRepository repository,
    Directory? coversDirectory,
    Directory? importedBooksDirectory,
    Directory? updateStagingDirectory,
    AppThemePreferences? themePreferences,
    FullTextSearchSettingsRepository? fullTextSearchSettingsRepository,
    BookMetadataExtractor? metadataExtractor,
  })  : _repository = repository,
        _coversDirectory = coversDirectory,
        _importedBooksDirectory = importedBooksDirectory,
        _updateStagingDirectory = updateStagingDirectory,
        _themePreferences = themePreferences ?? AppThemePreferences(),
        _fullTextSearchSettingsRepository = fullTextSearchSettingsRepository,
        _metadataExtractor = metadataExtractor;

  // 使用 kBookMetadataChannel（library_repository.dart）作為共用通道名稱。

  final LibraryRepository _repository;
  final Directory? _coversDirectory;
  final Directory? _importedBooksDirectory;
  final Directory? _updateStagingDirectory;
  final AppThemePreferences _themePreferences;
  final BookMetadataExtractor? _metadataExtractor;

  /// epic-10-search Issue 2（spec.md §7）：新書匯入成功後連動全文檢索
  /// 索引狀態（CBZ 標記 unsupported；其餘格式依開關狀態決定是否插入
  /// pending）。`null` 時（例如既有測試未提供）完全略過，行為與本工單
  /// 之前完全一致。
  final FullTextSearchSettingsRepository? _fullTextSearchSettingsRepository;

  @override
  Future<ImportResult> importFiles(
    List<String> uris, {
    List<String?>? displayNames,
    String? folderName,
    BookSource source = BookSource.local,
    String? remoteServerId,
    Map<String, String>? remoteBookIds,
    Map<String, String>? remoteDownloadUrls,
    Map<String, String>? cloudFileIds,
  }) async {
    if (folderName != null) {
      await _repository.upsertGroup(folderName);
    }

    final existingBooks = await _repository.listBooks();
    final seenUris = existingBooks.map((b) => b.filePath).toSet();
    final imported = <Book>[];
    final updateCandidates = <BookUpdateCandidate>[];
    var skippedDuplicateCount = 0;
    var skippedUnsupportedCount = 0;
    for (var i = 0; i < uris.length; i++) {
      final uri = uris[i];
      final displayName = (displayNames != null && i < displayNames.length)
          ? displayNames[i]
          : null;
      if (_detectImportFormat(uri, displayName) == null) {
        skippedUnsupportedCount++;
        continue;
      }
      if (!seenUris.add(uri)) {
        skippedDuplicateCount++;
        continue;
      }

      final detection = await _detectBookUpdateInternal(
        uri,
        displayName: displayName,
        existingBooks: existingBooks,
      );

      if (detection is DetectedDuplicate) {
        skippedDuplicateCount++;
        continue;
      } else if (detection is DetectedUpdate &&
          detection.candidate.stagedPath != null) {
        updateCandidates.add(detection.candidate);
        continue;
      }
      // 更新版但暫存複製失敗（stagedPath 為 null）：不讓使用者的檔案無聲消失，
      // 退回當成新書匯入，使用者之後可自行處理重複。

      final book = await _importSingleFile(
        uri,
        displayName: displayName,
        folderName: folderName,
        source: source,
        remoteServerId: remoteServerId,
        remoteBookId: remoteBookIds?[uri],
        remoteDownloadUrl: remoteDownloadUrls?[uri],
        cloudFileId: cloudFileIds?[uri],
      );
      if (book != null) {
        imported.add(book);
        existingBooks.add(book);
      }
    }
    return ImportResult(
      importedBooks: imported,
      skippedDuplicateCount: skippedDuplicateCount,
      skippedUnsupportedCount: skippedUnsupportedCount,
      updateCandidates: updateCandidates,
    );
  }

  @override
  Future<ImportResult> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  }) async {
    String? folderName;
    List<String> fileUris;
    if (folderUri.startsWith('content://')) {
      // 資料夾沒有持久化授權就無法列舉：整次匯入失敗，並讓畫面告知使用者原因。
    if (!await persistReadAccess(folderUri)) {
      return const ImportResult(
        importedBooks: [],
        failure: ImportFailure.folderAccessDenied,
      );
    }

    Map<Object?, Object?>? contents;
    try {
      contents = await kBookMetadataChannel.invokeMapMethod<Object?, Object?>(
        'listFolderContents',
        {'uri': folderUri},
      );
    } on PlatformException {
      return const ImportResult(
        importedBooks: [],
        failure: ImportFailure.folderListingFailed,
      );
    }
    if (contents == null) {
      return const ImportResult(
        importedBooks: [],
        failure: ImportFailure.folderListingFailed,
      );
    }

      folderName = contents['folderName'] as String?;
      fileUris =
          (contents['fileUris'] as List?)?.cast<String>() ?? const [];
    } else {
      final localContents = await _listLocalFolder(folderUri);
      if (localContents == null) {
        return const ImportResult(
          importedBooks: [],
          failure: ImportFailure.folderListingFailed,
        );
      }
      folderName = localContents.folderName;
      fileUris = localContents.fileUris;
    }

    final groupName =
        autoGroupByFolderName && folderName != null && folderName.isNotEmpty
            ? folderName
            : null;

    if (groupName != null) {
      await _repository.upsertGroup(groupName);
    }

    final existingBooks = await _repository.listBooks();
    final seenUris = existingBooks.map((b) => b.filePath).toSet();
    final imported = <Book>[];
    final updateCandidates = <BookUpdateCandidate>[];
    var skippedDuplicateCount = 0;
    var skippedUnsupportedCount = 0;
    for (final uri in fileUris) {
      if (_detectImportFormat(uri, null) == null) {
        skippedUnsupportedCount++;
        continue;
      }
      if (!seenUris.add(uri)) {
        skippedDuplicateCount++;
        continue;
      }
      final detection = await _detectBookUpdateInternal(
        uri,
        existingBooks: existingBooks,
      );
      if (detection is DetectedDuplicate) {
        skippedDuplicateCount++;
        continue;
      } else if (detection is DetectedUpdate &&
          detection.candidate.stagedPath != null) {
        updateCandidates.add(detection.candidate);
        continue;
      }
      // 更新版但暫存複製失敗（stagedPath 為 null）：不讓使用者的檔案無聲消失，
      // 退回當成新書匯入，使用者之後可自行處理重複。
      final book = await _importSingleFile(
        uri,
        folderName: groupName,
        takePermission: false,
      );
      if (book != null) {
        imported.add(book);
        existingBooks.add(book);
      }
    }
    return ImportResult(
      importedBooks: imported,
      skippedDuplicateCount: skippedDuplicateCount,
      skippedUnsupportedCount: skippedUnsupportedCount,
      updateCandidates: updateCandidates,
    );
  }

  Future<({String folderName, List<String> fileUris})?> _listLocalFolder(
    String path,
  ) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return null;
      final filePaths = <String>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          filePaths.add(entity.path);
        }
      }
      filePaths.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
      return (folderName: p.basename(path), fileUris: filePaths);
    } on FileSystemException {
      return null;
    }
  }

  /// epic-15-storage-permission Issue 2：可能維持 `content://` 的格式。
  /// TXT／MD 匯入時已合成 EPUB 並落地、CBZ 匯入時已重建並落地，
  /// `filePath` 指向落地檔；若換成原始檔 URI，閱讀器會把原始檔當合成結果
  /// 開啟，整本書壞掉（spec.md「受影響範圍」）。
  static const _relinkableFormats = {
    BookFileFormat.epub,
    BookFileFormat.pdf,
    BookFileFormat.azw3,
  };

  @override
  Future<BookRelinkResult> relinkBook(
    String bookId,
    String newUri, {
    String? displayName,
    bool force = false,
  }) async {
    try {
      // 1. 讀取最新記錄：由服務自行讀取而非由呼叫端傳入 Book 快照，避免
      //    updateBook 整列覆寫時把閱讀位置等欄位蓋回舊值。
      final book = await _repository.findBookById(bookId);
      if (book == null || !_relinkableFormats.contains(book.format)) {
        return const BookRelinkFailure(BookRelinkFailureReason.failed);
      }

      // 2. 格式必須與原書相同（規則與第一次匯入共用）。
      final format = _detectImportFormat(newUri, displayName);
      if (format != book.format) {
        return const BookRelinkFailure(BookRelinkFailureReason.formatMismatch);
      }

      // 3. 新 URI 不可是另一本書的來源；等於原書自己的 filePath 則放行
      //    （撤銷授權後重新選取同一個檔案，是本功能的主要情境）。
      final books = await _repository.listBooks();
      if (books.any((b) => b.id != book.id && b.filePath == newUri)) {
        return const BookRelinkFailure(
            BookRelinkFailureReason.alreadyInLibrary);
      }

      final originalFingerprint = book.contentFingerprint;
      String? fingerprint;

      // 4. 利用選擇器核發的暫時讀取授權計算指紋——此時尚未持久化授權，
      //    選錯檔案不會白白消耗系統的持久化授權配額。
      //    算法必須與第一次匯入完全一致：EPUB 先取 OPF identifier（取不到才
      //    退回 SHA-256），其餘格式直接取 SHA-256。若跳過 extractMetadata，
      //    EPUB 會算出 SHA-256，和資料庫裡存的 identifier 永遠對不上。
      //    epic-67 Issue 3：原書已有指紋且 force == true 時，略過計算與比對；
      //    原書沒有指紋時仍需計算以補寫指紋。
      if (!force || originalFingerprint == null) {
        final epubIdentifier = format == BookFileFormat.epub
            ? await _readEpubIdentifier(newUri)
            : null;
        fingerprint = await computeBookContentFingerprint(
          newUri,
          format!,
          epubIdentifier: epubIdentifier,
        );

        // 5. 比對指紋；原書沒有指紋時略過，稍後補寫。
        if (originalFingerprint != null && originalFingerprint != fingerprint) {
          // 程式審查 M-3：匯入當下若 extractMetadata 失敗，資料庫存的是整檔
          // SHA-256；這次讀得到 identifier 就會永遠對不上，同一本書只能刪除
          // 重新匯入。指紋是以 identifier 算出時，再以 SHA-256 比對一次。
          // 反過來（資料庫存 identifier、這次讀不到）無從補救，仍回傳
          // contentMismatch，屬已知限制。
          final usedIdentifier = fingerprint == epubIdentifier?.trim();
          final sha256 = usedIdentifier
              ? await computeBookContentFingerprint(newUri, format)
              : null;
          if (sha256 != originalFingerprint) {
            return const BookRelinkFailure(
                BookRelinkFailureReason.contentMismatch);
          }
        }
      }

      // 6. 確認是同一本書後才持久化授權或落地複本（規則與第一次匯入共用）。
      final resolvedPath =
          await _persistPermissionOrLandCopy(newUri, book.id, format!);
      if (resolvedPath == null) {
        return const BookRelinkFailure(BookRelinkFailureReason.failed);
      }

      // 7. 原地更新：只改 filePath 與補寫的指紋，其餘欄位沿用最新記錄。
      //    已知限制（程式審查 M-4）：這一步寫入失敗時，第 6 步已持久化的
      //    授權與落地複本不會回收——原生端沒有釋放授權的方法；複本檔名
      //    固定為 `<bookId>.<格式>`，重試時會直接覆寫，不會越積越多。
      final updated = book.copyWith(
        filePath: resolvedPath,
        contentFingerprint: originalFingerprint ?? fingerprint,
      );
      await _repository.updateBook(updated);
      return BookRelinkSuccess(updated);
    } catch (_) {
      // 指紋計算失敗（computeSha256 回傳 null 會拋出 StateError）、資料庫
      // 讀寫失敗等，一律視為 failed：本方法保證不拋出例外，呼叫端只需
      // 依結果顯示對應 SnackBar。
      return const BookRelinkFailure(BookRelinkFailureReason.failed);
    }
  }

  @override
  Future<BookDetectionResult> detectBookUpdate(
    String uri, {
    String? displayName,
  }) async {
    final existingBooks = await _repository.listBooks();
    return _detectBookUpdateInternal(
      uri,
      displayName: displayName,
      existingBooks: existingBooks,
    );
  }

  @override
  Future<void> discardUpdateCandidate(BookUpdateCandidate candidate) async {
    final stagedPath = candidate.stagedPath;
    if (stagedPath == null) return;
    try {
      final file = File(stagedPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 靜默成功，永不拋出例外
    }
  }

  /// 以 [newUri]（或 [candidate.stagedPath]）取代書籍 [bookId] 的檔案內容。
  /// 見 spec「取代的語意」與 ADR 0040。
  ///
  /// 已知殘餘風險（Review Focus 2）：若暫存檔已改名為正式檔名但後續資料庫
  /// [updateBook] 寫入失敗，檔案內容與資料庫中繼資料會產生短暫不一致。
  /// 此時再次呼叫本方法取代同本書籍即可修復。永不拋例外。
  /// 依決策 D1 沿用原書指紋（已知限制：PDF／AZW3 取代後指紋為舊內容雜湊，
  /// 之後 relinkBook 會回 contentMismatch，由「強制重新連結」處理），依決策 D3
  /// 嚴格模式解析新檔。同一本書的呼叫會序列化執行。
  @override
  Future<BookReplaceResult> replaceBook(
    String bookId,
    String newUri, {
    String? displayName,
    BookUpdateCandidate? candidate,
    BookSourceRefs? sourceRefs,
  }) async {
    // 同一本書的取代序列化執行：暫存檔名由 bookId 決定，並行呼叫會互相覆寫／誤刪。
    final previous = _replaceTails[bookId] ?? Future<void>.value();
    final done = Completer<void>();
    _replaceTails[bookId] = done.future;
    try {
      await previous;
      return await _replaceBookLocked(
        bookId,
        newUri,
        displayName: displayName,
        candidate: candidate,
        sourceRefs: sourceRefs,
      );
    } finally {
      done.complete();
      if (identical(_replaceTails[bookId], done.future)) {
        _replaceTails.remove(bookId);
      }
    }
  }

  final Map<String, Future<void>> _replaceTails = {};

  Future<BookReplaceResult> _replaceBookLocked(
    String bookId,
    String newUri, {
    String? displayName,
    BookUpdateCandidate? candidate,
    BookSourceRefs? sourceRefs,
  }) async {
    // 1. findBookById；null → bookNotFound。
    final book = await _repository.findBookById(bookId);
    if (book == null) {
      return const BookReplaceFailure(BookReplaceFailureReason.bookNotFound);
    }

    // 2. format = _detectImportFormat(newUri, displayName)；!= book.format → formatMismatch。允許所有格式。
    final format = _detectImportFormat(newUri, displayName);
    if (format == null || format != book.format) {
      return const BookReplaceFailure(BookReplaceFailureReason.formatMismatch);
    }

    // 3. 決定處理來源 source = candidate?.stagedPath ?? newUri
    final source = candidate?.stagedPath ?? newUri;

    // 4. 準備階段（只寫暫存名稱 .staging，不碰正式檔名與資料庫）
    final stagedFiles = <String>[];
    String finalBookFilePath;
    String resolvedUri;

    try {
      if (format == BookFileFormat.epub ||
          format == BookFileFormat.pdf ||
          format == BookFileFormat.azw3) {
        if (candidate?.stagedPath != null) {
          final importedDir = await _resolveImportedBooksDirectory();
          final stagingPath =
              p.join(importedDir.path, '$bookId.${format.name}.staging');
          await File(candidate!.stagedPath!).copy(stagingPath);
          stagedFiles.add(stagingPath);
          resolvedUri = stagingPath;
          finalBookFilePath = p.join(importedDir.path, '$bookId.${format.name}');
        } else if (source.startsWith('content://')) {
          final persisted = await _persistPermissionOrLandCopy(
            source,
            bookId,
            format,
            landSuffix: '.staging',
          );
          if (persisted == null) {
            await _sweepStagingFiles(bookId);
            return const BookReplaceFailure(BookReplaceFailureReason.writeFailed);
          }
          if (persisted.endsWith('.staging')) {
            stagedFiles.add(persisted);
            resolvedUri = persisted;
            finalBookFilePath = p.join(
              (await _resolveImportedBooksDirectory()).path,
              '$bookId.${format.name}',
            );
          } else {
            resolvedUri = persisted;
            finalBookFilePath = persisted;
          }
        } else {
          resolvedUri = source;
          finalBookFilePath = source;
        }
      } else {
        resolvedUri = source;
        final importedDir = await _resolveImportedBooksDirectory();
        finalBookFilePath = p.join(importedDir.path, '$bookId.${format.name}');
      }

      final fallbackTitle = titleFromFileName(displayName ?? newUri);
      final parts = await _prepareBookParts(
        originalUri: source,
        resolvedUri: resolvedUri,
        format: format,
        id: bookId,
        fallbackTitle: fallbackTitle,
        landSuffix: '.staging',
        strict: true,
        computeFingerprint: false,
        stagedOut: stagedFiles,
      );
      if (parts == null) {
        await _sweepStagingFiles(bookId);
        return const BookReplaceFailure(
            BookReplaceFailureReason.newFileParseFailed);
      }

      // 5. 換名階段：File.rename 本身即原子覆蓋既有檔，不可先刪目標（否則換名失敗會遺失舊檔）
      for (final stagedPath in List.of(stagedFiles)) {
        if (!stagedPath.endsWith('.staging')) continue;
        final targetPath =
            stagedPath.substring(0, stagedPath.length - '.staging'.length);
        final stagingFile = File(stagedPath);
        if (await stagingFile.exists()) {
          await stagingFile.rename(targetPath);
        }
      }
      String? finalCoverPath;
      final stagedCover = parts.coverPath;
      if (stagedCover != null) {
        finalCoverPath = stagedCover.endsWith('.staging')
            ? stagedCover.substring(0, stagedCover.length - '.staging'.length)
            : stagedCover;
      }

      // 6. 資料庫階段
      final updatedBook = book.copyWith(
        title: parts.title,
        author: parts.author,
        clearAuthor: parts.author == null,
        filePath: finalBookFilePath,
        coverPath: finalCoverPath,
        clearCoverPath: finalCoverPath == null,
        isFixedLayout: parts.isFixedLayout,
        clearIsFixedLayout: parts.isFixedLayout == null,
        source: sourceRefs?.source ?? book.source,
        cloudFileId: sourceRefs?.cloudFileId ?? book.cloudFileId,
        remoteServerId: sourceRefs?.remoteServerId ?? book.remoteServerId,
        remoteBookId: sourceRefs?.remoteBookId ?? book.remoteBookId,
        remoteDownloadUrl:
            sourceRefs?.remoteDownloadUrl ?? book.remoteDownloadUrl,
      );

      await _repository.updateBook(updatedBook);

      // 7. 收尾（失敗一律吞掉，不影響成功結果）
      // 新版沒有封面 → 資料庫已不再指向舊封面，才刪除舊封面檔
      if (finalCoverPath == null && book.coverPath != null) {
        try {
          final oldCoverFile = File(book.coverPath!);
          if (await oldCoverFile.exists()) {
            await oldCoverFile.delete();
          }
        } catch (_) {}
      }
      try {
        final importedDir = await _resolveImportedBooksDirectory();
        if (book.filePath != updatedBook.filePath &&
            p.isWithin(importedDir.path, book.filePath)) {
          final oldFile = File(book.filePath);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        }
      } catch (_) {}

      try {
        await _fullTextSearchSettingsRepository?.clearBookIndex(bookId);
      } catch (_) {}
      try {
        await _fullTextSearchSettingsRepository
            ?.handleBookAvailable(updatedBook);
      } catch (_) {}

      if (candidate != null) {
        await discardUpdateCandidate(candidate);
      }

      return BookReplaceSuccess(updatedBook);
    } on _NewFileParseException {
      await _sweepStagingFiles(bookId);
      return const BookReplaceFailure(
          BookReplaceFailureReason.newFileParseFailed);
    } catch (_) {
      await _sweepStagingFiles(bookId);
      return const BookReplaceFailure(BookReplaceFailureReason.writeFailed);
    }
  }

  @override
  Future<Book?> importCandidateAsNewBook(
    BookUpdateCandidate candidate, {
    String? folderName,
    BookSourceRefs? sourceRefs,
  }) async {
    try {
      final source = candidate.stagedPath ?? candidate.sourceUri;
      final book = await _importSingleFile(
        source,
        displayName: candidate.displayName,
        // stagedPath 的檔名是時間戳記，書名退路改用原始來源的檔名
        fallbackName: candidate.displayName ?? candidate.sourceUri,
        folderName: folderName,
        source: sourceRefs?.source ?? BookSource.local,
        remoteServerId: sourceRefs?.remoteServerId,
        remoteBookId: sourceRefs?.remoteBookId,
        remoteDownloadUrl: sourceRefs?.remoteDownloadUrl,
        cloudFileId: sourceRefs?.cloudFileId,
        landLocalCopy: true,
      );
      return book;
    } catch (_) {
      return null;
    } finally {
      await discardUpdateCandidate(candidate);
    }
  }

  /// 取代失敗時依 [bookId] 掃除所有可能的暫存名稱檔（含寫到一半的半成品）。
  Future<void> _sweepStagingFiles(String bookId) async {
    final paths = <String>[];
    try {
      final importedDir = await _resolveImportedBooksDirectory();
      for (final ext in const ['epub', 'pdf', 'azw3', 'cbz', 'txt', 'md']) {
        paths.add(p.join(importedDir.path, '$bookId.$ext.staging'));
      }
      final coversDir = await _resolveCoversDirectory();
      paths.add(p.join(coversDir.path, '$bookId.png.staging'));
    } catch (_) {}
    await _cleanStagedFiles(paths);
  }

  Future<void> _cleanStagedFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  /// 把新檔複製到更新暫存目錄（content:// 呼叫 copyContentUriToFile；本機路徑用 File.copy），
  /// 檔名 `<微秒時間戳>-<uri.hashCode>.<副檔名>`，失敗回傳 null（並清掉半成品）。
  Future<String?> _stageNewFile(String uri, BookFileFormat format) async {
    String? destinationPath;
    try {
      final stagingDir = await _resolveUpdateStagingDirectory();
      final filename =
          '${DateTime.now().microsecondsSinceEpoch}-${uri.hashCode}.${format.name}';
      destinationPath = p.join(stagingDir.path, filename);
      if (uri.startsWith('content://')) {
        await kBookMetadataChannel.invokeMethod<void>(
          'copyContentUriToFile',
          {'uri': uri, 'destinationPath': destinationPath},
        );
      } else {
        await File(uri).copy(destinationPath);
      }
      return destinationPath;
    } catch (_) {
      if (destinationPath != null) {
        try {
          final file = File(destinationPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
      return null;
    }
  }

  /// 內部更新版偵測邏輯，接收預讀的 [existingBooks] 供批次迴圈重用（審查 M-2）。
  Future<BookDetectionResult> _detectBookUpdateInternal(
    String uri, {
    String? displayName,
    required List<Book> existingBooks,
  }) async {
    // 1. 格式判斷；未知格式回傳 DetectedUnsupported
    final format = _detectImportFormat(uri, displayName);
    if (format == null) {
      return const DetectedUnsupported();
    }

    // 2. 前置短路：若書庫內沒有同格式書籍，直接回傳 DetectedNewBook（不讀新檔）
    final sameFormatBooks =
        existingBooks.where((b) => b.format == format).toList();
    if (sameFormatBooks.isEmpty) {
      return const DetectedNewBook();
    }

    // 3. 取得新檔身份（偵測階段永不拋例外）
    final identity = await _peekIdentity(uri, format, displayName);

    // 4. 候選比對：
    // 第一層（僅 EPUB）：identifier 相同
    final firstLayerMatches = <Book>[];
    final trimmedNewId = identity.epubIdentifier?.trim();
    if (format == BookFileFormat.epub &&
        trimmedNewId != null &&
        trimmedNewId.isNotEmpty) {
      for (final book in sameFormatBooks) {
        if (book.contentFingerprint == trimmedNewId) {
          firstLayerMatches.add(book);
        }
      }
    }

    // 第二層（所有格式）：書名＋作者經正規化後完全相同；作者為空不進入此層
    final secondLayerMatches = <Book>[];
    final normTitle = normalizeBookKey(identity.title);
    final normAuthor = normalizeBookKey(identity.author);
    if (normTitle != null && normAuthor != null) {
      for (final book in sameFormatBooks) {
        final bookNormTitle = normalizeBookKey(book.title);
        final bookNormAuthor = normalizeBookKey(book.author);
        if (bookNormTitle == normTitle && bookNormAuthor == normAuthor) {
          if (!firstLayerMatches.any((b) => b.id == book.id)) {
            secondLayerMatches.add(book);
          }
        }
      }
    }

    final candidateBooks = [...firstLayerMatches, ...secondLayerMatches];
    if (candidateBooks.isEmpty) {
      return const DetectedNewBook();
    }

    // 審查 M-3：只要有任何一本識別碼命中即為 high，否則為 suspected
    final confidence = firstLayerMatches.isNotEmpty
        ? UpdateConfidence.high
        : UpdateConfidence.suspected;

    // 5. 重複 vs 更新版（決策 D1）：
    // 算新檔整檔 SHA-256（不傳 identifier，強制整檔雜湊）
    String? newHash;
    try {
      newHash = await computeBookContentFingerprint(uri, format);
    } catch (_) {
      // 算不出新檔雜湊時視為無法比對重複，回 DetectedUpdate
      final stagedPath = await _stageNewFile(uri, format);
      return DetectedUpdate(
        BookUpdateCandidate(
          sourceUri: uri,
          displayName: displayName,
          format: format,
          confidence: confidence,
          candidateBooks: candidateBooks,
          unreadableCandidateBookIds: const {},
          stagedPath: stagedPath,
        ),
      );
    }

    final unreadableCandidateBookIds = <String>{};
    Book? duplicateBook;

    for (final candidate in candidateBooks) {
      String? oldHash;
      if (format == BookFileFormat.epub ||
          format == BookFileFormat.pdf ||
          format == BookFileFormat.azw3) {
        try {
          oldHash =
              await computeBookContentFingerprint(candidate.filePath, format);
        } catch (_) {
          unreadableCandidateBookIds.add(candidate.id);
          continue;
        }
      } else {
        // TXT／MD／CBZ：使用資料庫中儲存的原始檔指紋（決策 D1）
        oldHash = candidate.contentFingerprint;
      }

      if (duplicateBook == null && oldHash != null && oldHash == newHash) {
        duplicateBook = candidate;
      }
    }

    if (duplicateBook != null) {
      return DetectedDuplicate(duplicateBook);
    }

    final stagedPath = await _stageNewFile(uri, format);
    return DetectedUpdate(
      BookUpdateCandidate(
        sourceUri: uri,
        displayName: displayName,
        format: format,
        confidence: confidence,
        candidateBooks: candidateBooks,
        unreadableCandidateBookIds: unreadableCandidateBookIds,
        stagedPath: stagedPath,
      ),
    );
  }

  /// 快速讀取新檔身份（title, author, epubIdentifier），偵測階段永不拋出例外。
  Future<({String title, String? author, String? epubIdentifier})>
      _peekIdentity(
    String uri,
    BookFileFormat format,
    String? displayName,
  ) async {
    final fallback = titleFromFileName(displayName ?? uri);
    if (format == BookFileFormat.epub) {
      try {
        final metadata = _metadataExtractor != null
            ? await _metadataExtractor(uri, format.name)
            : await kBookMetadataChannel.invokeMapMethod<String, Object?>(
                'extractMetadata',
                {'uri': uri, 'format': format.name},
              );
        final extractedTitle = metadata?['title'] as String?;
        final title = (extractedTitle != null && extractedTitle.isNotEmpty)
            ? extractedTitle
            : fallback;
        final author = metadata?['author'] as String?;
        final identifier = metadata?['identifier'] as String?;
        return (title: title, author: author, epubIdentifier: identifier);
      } catch (_) {
        return (title: fallback, author: null, epubIdentifier: null);
      }
    } else if (format == BookFileFormat.azw3) {
      try {
        final metadata = await extractKf8Metadata(uri);
        final extractedTitle = metadata['title'] as String?;
        final title = (extractedTitle != null && extractedTitle.isNotEmpty)
            ? extractedTitle
            : fallback;
        final author = metadata['author'] as String?;
        return (title: title, author: author, epubIdentifier: null);
      } catch (_) {
        return (title: fallback, author: null, epubIdentifier: null);
      }
    } else if (format == BookFileFormat.md) {
      try {
        final bytes = uri.contains('://')
            ? await readContentUriBytes(uri,
                tempFilePrefix: 'md_probe', tempFileExtension: '.md')
            : await File(uri).readAsBytes();
        final rawContent = utf8.decode(bytes, allowMalformed: true);
        final parsedDoc = parseMdFrontmatter(rawContent);
        final title = (parsedDoc.frontmatter.title != null &&
                parsedDoc.frontmatter.title!.isNotEmpty)
            ? parsedDoc.frontmatter.title!
            : fallback;
        final author = parsedDoc.frontmatter.author;
        return (title: title, author: author, epubIdentifier: null);
      } catch (_) {
        return (title: fallback, author: null, epubIdentifier: null);
      }
    } else {
      // PDF, TXT, CBZ：審查 I-3，PDF 永不發送原生 extractMetadata（避免渲染封面），
      // 直接回傳檔名標題且作者為 null
      return (title: fallback, author: null, epubIdentifier: null);
    }
  }

  /// epic-15-storage-permission Issue 2：以 `extractMetadata` 讀取重新選取的
  /// EPUB 的 OPF identifier，供指紋計算使用。提取失敗時回傳 null，比照匯入
  /// 退回整檔 SHA-256。
  Future<String?> _readEpubIdentifier(String uri) async {
    try {
      final metadata = _metadataExtractor != null
          ? await _metadataExtractor(uri, BookFileFormat.epub.name)
          : await kBookMetadataChannel.invokeMapMethod<String, Object?>(
              'extractMetadata',
              {'uri': uri, 'format': BookFileFormat.epub.name},
            );
      return metadata?['identifier'] as String?;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // epic-66 Issue 1 Task 8：Windows 沒有 `elinkbook/book_metadata`
      // 原生端，降級與 PlatformException 相同（取不到 identifier，
      // 指紋退回整檔 SHA-256）。Android 不會觸發此例外，行為不變。
      return null;
    }
  }

  Future<Book?> _importSingleFile(
    String uri, {
    String? displayName,
    String? fallbackName,
    String? folderName,
    bool takePermission = true,
    bool landLocalCopy = false,
    BookSource source = BookSource.local,
    String? remoteServerId,
    String? remoteBookId,
    String? remoteDownloadUrl,
    String? cloudFileId,
  }) async {
    final format = _detectImportFormat(uri, displayName);
    if (format == null) return null;

    final id = '${DateTime.now().microsecondsSinceEpoch}-${uri.hashCode}';

    // 持久化授權／落地複本規則見 _persistPermissionOrLandCopy。資料夾批次
    // 匯入（importFolder）的子檔案 URI 共用資料夾層級已取得的權限，呼叫時
    // 傳入 takePermission: false 跳過這一步。
    var resolvedUri = uri;
    String? landedCopy; // 並存時落地的私有複本；失敗時須清掉
    if (landLocalCopy &&
        (format == BookFileFormat.epub ||
            format == BookFileFormat.pdf ||
            format == BookFileFormat.azw3) &&
        !uri.startsWith('content://')) {
      final importedDir = await _resolveImportedBooksDirectory();
      final destinationPath = p.join(importedDir.path, '$id.${format.name}');
      await File(uri).copy(destinationPath);
      landedCopy = destinationPath;
      resolvedUri = destinationPath;
    } else if (takePermission) {
      final persisted = await _persistPermissionOrLandCopy(uri, id, format);
      if (persisted == null) return null;
      resolvedUri = persisted;
    }

    final fallbackTitle = titleFromFileName(fallbackName ?? displayName ?? uri);
    final now = DateTime.now();

    final _BookParts? parts;
    try {
      parts = await _prepareBookParts(
        originalUri: uri,
        resolvedUri: resolvedUri,
        format: format,
        id: id,
        fallbackTitle: fallbackTitle,
        landSuffix: '',
        strict: false,
        computeFingerprint: true,
      );
    } catch (_) {
      if (landedCopy != null) await _cleanStagedFiles([landedCopy]);
      rethrow;
    }
    if (parts == null) {
      if (landedCopy != null) await _cleanStagedFiles([landedCopy]);
      return null;
    }

    final book = Book(
      id: id,
      title: parts.title,
      author: parts.author,
      format: format,
      filePath: parts.bookFilePath,
      source: source,
      coverPath: parts.coverPath,
      isFixedLayout: parts.isFixedLayout,
      contentFingerprint: parts.contentFingerprint,
      remoteServerId: remoteServerId,
      remoteBookId: remoteBookId,
      remoteDownloadUrl: remoteDownloadUrl,
      isDownloaded: true,
      cloudFileId: cloudFileId,
      groupName: folderName ?? BookGroup.uncategorized,
      createTime: now,
      // 【診斷修正，epic-18-reader-device-qa Issue 29】剛匯入、從未打開過
      // 的書不該視為「剛讀過」——用 epoch 0 表示「尚未讀過」的哨兵值，
      // 讓「最後閱讀」排序／自動開書永遠把它排在任何真正被讀過的書之後。
      // `lastReadTime` 欄位為 `NOT NULL`，改回 nullable 需要 schema
      // migration，用哨兵值比新增可為 null 的欄位改動範圍更小。真正的
      // 「最後閱讀時間」由 ReadingPositionRepository.save() 於使用者實際
      // 閱讀、位置有異動時統一維護。
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );

    final Book insertedBook;
    try {
      insertedBook = await _repository.insertBook(book);
    } catch (_) {
      if (landedCopy != null) await _cleanStagedFiles([landedCopy]);
      rethrow;
    }
    // epic-10-search Issue 2（spec.md §7，review-plan-issue-2.md C-2）：
    // _importSingleFile() 是全專案所有新書匯入與雲端/遠端首次下載的唯一
    // 收斂點（本機檔案/資料夾選取、Google Drive、OneDrive、Calibre/OPDS
    // 皆經由 BookImportService.importFiles() 呼叫到這裡）。統一呼叫
    // handleBookAvailable()（不只 CBZ）讓所有格式都能在已啟用全文檢索的
    // 情況下正確被排入 pending 佇列並喚醒排程器。search-index 只是衍生
    // 資料，寫入失敗不應讓原本已成功的書籍匯入被判定失敗
    // （review-plan-issue-2.md M-1）。
    try {
      await _fullTextSearchSettingsRepository?.handleBookAvailable(
        insertedBook,
      );
    } catch (_) {
      // 靜默略過——書籍記錄已成功建立，全文檢索索引狀態可日後透過
      // 「重建索引」補上，不應讓整筆匯入被視為失敗。
    }
    return insertedBook;
  }

  /// 判斷匯入／重新連結檔案的格式：優先用呼叫端提供的真實檔名，URI 當退路。
  /// 部分文件提供者（例如媒體庫文件提供者 com.android.providers.media.documents，
  /// 使用者透過系統選擇器的「最近」／媒體索引視圖選檔時常見）回傳的 URI
  /// 只帶不透明數字文件 ID（例如 .../document/document%3A1000001716），
  /// 完全不含檔名／副檔名——只看 URI 判斷格式在這種情況下必定回傳 null
  /// （真機驗證發現的實際症狀：選檔正確返回、匯入沒有拋出任何例外，但
  /// 書架永遠是空的）。資料夾匯入（importFolder）目前仍只有 URI 可用
  /// （DocumentFile 的 uri 路徑對 externalstorage 這類本機提供者通常仍
  /// 保留可辨識檔名），沒有另外提供 displayName 時退回只看 URI。
  /// epic-15-storage-permission Issue 2 起由 [relinkBook] 共用。
  BookFileFormat? _detectImportFormat(String uri, String? displayName) =>
      detectImportFileFormat(uri, displayName);

  /// 對 `content://` URI 持久化讀取授權，回傳最終要寫進 `Book.filePath` 的
  /// 路徑；非 `content://` 輸入原樣回傳。
  ///
  /// 只對 content:// scheme 持久化權限（file_picker 在 Android 上一定回傳
  /// content:// URI；此判斷主要防禦測試/除錯情境誤傳純路徑）。部分文件
  /// 提供者（例如媒體庫文件提供者 com.android.providers.media.documents，
  /// 相對於標準的外部儲存文件提供者）在某些裝置/Android 版本上不保證核發
  /// 可持久化授權，`takePersistableUriPermission` 會拋出 PlatformException；
  /// 此時不能直接放棄（先前版本的行為——真機驗證發現這會讓匯入功能在部分
  /// 裝置上整個無法使用），改為退而求其次：把檔案內容複製一份到 App 私有
  /// 儲存空間，改用這份本機複本的真實檔案路徑，不再依賴來源 content:// URI
  /// 在下次啟動後是否還能讀取——複製也失敗才回傳 null。
  ///
  /// 即使權限持久化成功，若來源 URI 本身不含可辨識副檔名（例如媒體庫文件
  /// 提供者的不透明數字 ID），ReaderScreen 開啟時仍是依 filePath 的副檔名
  /// 判斷格式（detectBookFormat，與匯入時的格式判斷各自獨立運作）——
  /// filePath 若維持原始 URI，開啟時會判定為不支援的格式。因此只要 URI
  /// 本身沒有可辨識副檔名，就一律複製一份到本機、以正確副檔名命名，讓
  /// 匯入與開啟兩處的格式判斷全程一致。
  ///
  /// epic-15-storage-permission Issue 2 起由 [relinkBook] 共用，確保重新
  /// 連結與第一次匯入的行為一致。
  Future<String?> _persistPermissionOrLandCopy(
    String uri,
    String id,
    BookFileFormat format, {
    String landSuffix = '',
  }) async {
    if (!uri.startsWith('content://')) return uri;
    final permissionGranted = await persistReadAccess(uri);
    if (!permissionGranted || detectBookFileFormat(uri) == null) {
      return _copyToLocalStorage(uri, id, format, landSuffix: landSuffix);
    }
    return uri;
  }

  /// [takePersistableUriPermission] 失敗時的退路：把 [uri] 的內容複製一份到
  /// App 私有文件目錄下的 `imported_books/` 子目錄，回傳複本的真實檔案路徑；
  /// 複製失敗（例如來源 URI 這次連暫時讀取都失敗）回傳 null。
  /// [landSuffix] 供取代時寫入暫存檔名（如 `.staging`），審查 C-1。
  Future<String?> _copyToLocalStorage(
    String uri,
    String id,
    BookFileFormat format, {
    String landSuffix = '',
  }) async {
    final importedDir = await _resolveImportedBooksDirectory();
    final destinationPath =
        p.join(importedDir.path, '$id.${format.name}$landSuffix');
    try {
      await kBookMetadataChannel.invokeMethod<void>(
        'copyContentUriToFile',
        {'uri': uri, 'destinationPath': destinationPath},
      );
      return destinationPath;
    } on PlatformException {
      return null;
    }
  }

  Future<String> _landCover(
    Uint8List bytes,
    String bookId, {
    String landSuffix = '',
  }) async {
    final dir = await _resolveCoversDirectory();
    final file = File(p.join(dir.path, '$bookId.png$landSuffix'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 將重建後的 CBZ 壓縮檔位元組寫入 `imported_books/` 目錄，回傳完整路徑。
  /// 檔名帶 `.cbz` 副檔名，確保 `detectBookFormat` 偵測正確。
  Future<String> _landCbzArchive(
    Uint8List bytes,
    String bookId, {
    String landSuffix = '',
  }) async {
    final importedDir = await _resolveImportedBooksDirectory();
    final file = File(p.join(importedDir.path, '$bookId.cbz$landSuffix'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 落地 TXT 合成的 EPUB 壓縮檔位元組（epic-11-multi-format-reader
  /// Issue 4），比照 [_landCover]／[_landCbzArchive] 既有的「以 book id
  /// 為鍵、獨立子目錄」慣例，重用既有 `imported_books/` 目錄。**檔名副
  /// 檔名須維持 `.txt`**（Global Constraints 已查證事實 #1：`BookFormat.txt`
  /// 的分派依 `Book.filePath` 副檔名判斷，不可改為 `.epub`）。
  Future<String> _landTxtEpub(
    Uint8List bytes,
    String bookId, {
    String landSuffix = '',
  }) async {
    final dir = await _resolveImportedBooksDirectory();
    final file = File(p.join(dir.path, '$bookId.txt$landSuffix'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 落地 MD 合成的 EPUB 壓縮檔位元組（epic-11-multi-format-reader
  /// Issue 5），比照 [_landTxtEpub] 既有的「以 book id 為鍵、獨立子目錄」
  /// 慣例，重用既有 `imported_books/` 目錄。**檔名副檔名須維持 `.md`**
  /// （理由同 `_landTxtEpub` 對 `.txt` 的既有限制）。
  Future<String> _landMdEpub(
    Uint8List bytes,
    String bookId, {
    String landSuffix = '',
  }) async {
    final dir = await _resolveImportedBooksDirectory();
    final file = File(p.join(dir.path, '$bookId.md$landSuffix'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 逐格式處理新檔案的內容、中繼資料、封面與指紋（Task 2 抽取，供第一次匯入與取代共用）。
  Future<_BookParts?> _prepareBookParts({
    required String originalUri,
    required String resolvedUri,
    required BookFileFormat format,
    required String id,
    required String fallbackTitle,
    String landSuffix = '',
    bool strict = false,
    bool computeFingerprint = true,
    List<String>? stagedOut,
  }) async {
    var title = fallbackTitle;
    String? author;
    String? coverPath;
    bool? isFixedLayout;
    String? epubIdentifier;
    var bookFilePath = resolvedUri;
    final stagedFiles = stagedOut ?? <String>[];

    if (format == BookFileFormat.txt) {
      TxtSynthesisResult synthesis;
      try {
        synthesis = await synthesizeTxtBook(resolvedUri, id, fallbackTitle);
      } on EmptyTxtException {
        if (strict) throw _NewFileParseException();
        return null;
      }
      isFixedLayout = false;
      bookFilePath =
          await _landTxtEpub(synthesis.epubBytes, id, landSuffix: landSuffix);
      if (landSuffix.isNotEmpty) stagedFiles.add(bookFilePath);
      final isEinkMode = await _themePreferences.loadEinkMode();
      final coverBytes =
          await generateTxtCover(fallbackTitle, isEinkMode: isEinkMode);
      coverPath = await _landCover(coverBytes, id, landSuffix: landSuffix);
      if (landSuffix.isNotEmpty) stagedFiles.add(coverPath);
    } else if (format == BookFileFormat.azw3) {
      try {
        final metadata = await extractKf8Metadata(resolvedUri);
        final extractedTitle = metadata['title'] as String?;
        if (extractedTitle != null && extractedTitle.isNotEmpty) {
          title = extractedTitle;
        }
        author = metadata['author'] as String?;
        isFixedLayout = metadata['isFixedLayout'] as bool?;
        final coverBytes = metadata['coverBytes'] as Uint8List?;
        if (coverBytes != null) {
          coverPath = await _landCover(coverBytes, id, landSuffix: landSuffix);
          if (landSuffix.isNotEmpty) stagedFiles.add(coverPath);
        }
      } on DrmProtectedException {
        if (strict) throw _NewFileParseException();
        return null;
      } catch (_) {
        if (strict) throw _NewFileParseException();
      }
    } else if (format == BookFileFormat.cbz) {
      isFixedLayout = true;
      try {
        final result = await prepareCbzForImport(resolvedUri);
        bookFilePath = await _landCbzArchive(result.rebuiltArchiveBytes, id,
            landSuffix: landSuffix);
        if (landSuffix.isNotEmpty) stagedFiles.add(bookFilePath);
        coverPath =
            await _landCover(result.coverBytes, id, landSuffix: landSuffix);
        if (landSuffix.isNotEmpty) stagedFiles.add(coverPath);
      } on NoComicPagesException {
        if (strict) throw _NewFileParseException();
        return null;
      } catch (_) {
        if (strict) throw _NewFileParseException();
      }
    } else if (format == BookFileFormat.md) {
      MdSynthesisResult synthesis;
      try {
        synthesis = await synthesizeMdBook(resolvedUri, id, fallbackTitle);
      } on EmptyMdException {
        if (strict) throw _NewFileParseException();
        return null;
      }
      isFixedLayout = false;
      bookFilePath =
          await _landMdEpub(synthesis.epubBytes, id, landSuffix: landSuffix);
      if (landSuffix.isNotEmpty) stagedFiles.add(bookFilePath);
      if (synthesis.frontmatterTitle != null &&
          synthesis.frontmatterTitle!.isNotEmpty) {
        title = synthesis.frontmatterTitle!;
      }
      author = synthesis.frontmatterAuthor;
      final coverBytes = synthesis.frontmatterCoverBytes ??
          await generateTxtCover(
            title,
            isEinkMode: await _themePreferences.loadEinkMode(),
          );
      coverPath = await _landCover(coverBytes, id, landSuffix: landSuffix);
      if (landSuffix.isNotEmpty) stagedFiles.add(coverPath);
    } else {
      try {
        final metadata = _metadataExtractor != null
            ? await _metadataExtractor(resolvedUri, format.name)
            : await kBookMetadataChannel.invokeMapMethod<String, Object?>(
                'extractMetadata',
                {'uri': resolvedUri, 'format': format.name},
              );
        final extractedTitle = metadata?['title'] as String?;
        if (extractedTitle != null && extractedTitle.isNotEmpty) {
          title = extractedTitle;
        }
        author = metadata?['author'] as String?;
        isFixedLayout = metadata?['isFixedLayout'] as bool?;
        epubIdentifier = metadata?['identifier'] as String?;
        final coverBytes = metadata?['coverBytes'] as Uint8List?;
        if (coverBytes != null) {
          coverPath = await _landCover(coverBytes, id, landSuffix: landSuffix);
          if (landSuffix.isNotEmpty) stagedFiles.add(coverPath);
        }
      } on PlatformException {
        if (strict) throw _NewFileParseException();
      } on MissingPluginException {
        // Windows 沒有 elinkbook/book_metadata 原生端，降級維持檔名為標題、無封面，strict 模式亦然
      }
    }

    String? contentFingerprint;
    if (computeFingerprint) {
      try {
        contentFingerprint = await computeBookContentFingerprint(
          resolvedUri,
          format,
          epubIdentifier: epubIdentifier,
        );
      } catch (_) {
        // 指紋計算失敗降級為 null
      }
    }

    return _BookParts(
      title: title,
      author: author,
      bookFilePath: bookFilePath,
      coverPath: coverPath,
      isFixedLayout: isFixedLayout,
      contentFingerprint: contentFingerprint,
      stagedFiles: stagedFiles,
    );
  }

  Future<Directory> _resolveCoversDirectory() async {
    if (_coversDirectory != null) return _coversDirectory;
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'covers'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _resolveImportedBooksDirectory() async {
    final dir = _importedBooksDirectory ??
        Directory(
          p.join(
            (await getApplicationDocumentsDirectory()).path,
            'imported_books',
          ),
        );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _resolveUpdateStagingDirectory() async {
    final dir = _updateStagingDirectory ??
        Directory(
          p.join(
            (await getApplicationDocumentsDirectory()).path,
            kUpdateStagingFolderName,
          ),
        );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}

/// 逐格式處理的結果（尚未寫入資料庫，Task 2）。
class _BookParts {
  final String title;
  final String? author;
  final String bookFilePath;
  final String? coverPath;
  final bool? isFixedLayout;
  final String? contentFingerprint;
  final List<String> stagedFiles;

  const _BookParts({
    required this.title,
    this.author,
    required this.bookFilePath,
    this.coverPath,
    this.isFixedLayout,
    this.contentFingerprint,
    this.stagedFiles = const [],
  });
}

/// 例外：嚴格模式下新檔無法解析（D3）。
class _NewFileParseException implements Exception {}

