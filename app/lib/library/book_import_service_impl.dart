import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../search/full_text_search_settings_repository.dart';
import '../storage/storage_permission.dart';
import '../theme/app_theme_preferences.dart';
import 'book_content_fingerprint.dart';
import 'book_import_service.dart';
import 'cbz_import.dart';
import 'kf8_metadata.dart';
import 'library_repository.dart';
import 'models/book.dart';
import 'models/book_group.dart';
import 'models/library_enums.dart';
import 'md_epub_synthesizer.dart';
import 'txt_cover_generator.dart';
import 'txt_epub_synthesizer.dart';

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
    AppThemePreferences? themePreferences,
    FullTextSearchSettingsRepository? fullTextSearchSettingsRepository,
    BookMetadataExtractor? metadataExtractor,
  })  : _repository = repository,
        _coversDirectory = coversDirectory,
        _importedBooksDirectory = importedBooksDirectory,
        _themePreferences = themePreferences ?? AppThemePreferences(),
        _fullTextSearchSettingsRepository = fullTextSearchSettingsRepository,
        _metadataExtractor = metadataExtractor;

  // 使用 kBookMetadataChannel（library_repository.dart）作為共用通道名稱。

  final LibraryRepository _repository;
  final Directory? _coversDirectory;
  final Directory? _importedBooksDirectory;
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

    // 【診斷修正】見下方 _importSingleFile 前的重複偵測說明。
    final seenUris = await _existingFilePaths();
    final imported = <Book>[];
    var skippedDuplicateCount = 0;
    for (var i = 0; i < uris.length; i++) {
      final uri = uris[i];
      if (!seenUris.add(uri)) {
        skippedDuplicateCount++;
        continue;
      }
      final displayName =
          (displayNames != null && i < displayNames.length) ? displayNames[i] : null;
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
      if (book != null) imported.add(book);
    }
    return ImportResult(
      importedBooks: imported,
      skippedDuplicateCount: skippedDuplicateCount,
    );
  }

  @override
  Future<ImportResult> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  }) async {
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

    final folderName = contents['folderName'] as String?;
    final fileUris =
        (contents['fileUris'] as List?)?.cast<String>() ?? const [];

    final groupName =
        autoGroupByFolderName && folderName != null && folderName.isNotEmpty
            ? folderName
            : null;

    if (groupName != null) {
      await _repository.upsertGroup(groupName);
    }

    // 【診斷修正】見下方 _importSingleFile 前的重複偵測說明。
    final seenUris = await _existingFilePaths();
    final imported = <Book>[];
    var skippedDuplicateCount = 0;
    for (final uri in fileUris) {
      if (!seenUris.add(uri)) {
        skippedDuplicateCount++;
        continue;
      }
      final book = await _importSingleFile(
        uri,
        folderName: groupName,
        takePermission: false,
      );
      if (book != null) imported.add(book);
    }
    return ImportResult(
      importedBooks: imported,
      skippedDuplicateCount: skippedDuplicateCount,
    );
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

      // 4. 利用選擇器核發的暫時讀取授權計算指紋——此時尚未持久化授權，
      //    選錯檔案不會白白消耗系統的持久化授權配額。
      //    算法必須與第一次匯入完全一致：EPUB 先取 OPF identifier（取不到才
      //    退回 SHA-256），其餘格式直接取 SHA-256。若跳過 extractMetadata，
      //    EPUB 會算出 SHA-256，和資料庫裡存的 identifier 永遠對不上。
      final epubIdentifier = format == BookFileFormat.epub
          ? await _readEpubIdentifier(newUri)
          : null;
      final fingerprint = await computeBookContentFingerprint(
        newUri,
        format!,
        epubIdentifier: epubIdentifier,
      );

      // 5. 比對指紋；原書沒有指紋時略過，稍後補寫。
      final originalFingerprint = book.contentFingerprint;
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

      // 6. 確認是同一本書後才持久化授權或落地複本（規則與第一次匯入共用）。
      final resolvedPath =
          await _persistPermissionOrLandCopy(newUri, book.id, format);
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

  /// 【診斷修正——真機回報「同一本書可以重複匯入」】圖書庫既有書籍的
  /// `filePath` 集合，供匯入前判斷來源 URI 是否重複。比對依據是「來源檔案
  /// URI/路徑是否相同」，不比對書名/作者（避免同名但內容不同的書被誤判為
  /// 重複）——對大多數情況成立：`filePath` 只有在持久化 URI 權限授權失敗、
  /// 或原始 URI 沒有可辨識副檔名時才會落地成本機複本（每次落地會產生新的
  /// 隨機檔名），故此防護對「使用者重新選取同一份原始檔案」這個實際回報的
  /// 情境有效；對「先前已落地成本機複本、之後又重新選取同一份原始檔案」
  /// 這種較罕見的邊界情況無效（本機複本檔名與原始 URI 不同，比對不到），
  /// 屬已知、可接受的限制。這個集合在同一次批次匯入呼叫（`importFiles`／
  /// `importFolder`）期間會持續更新，故同一批次內重複選取同一個 URI 兩次
  /// 也會被正確擋下第二次。
  Future<Set<String>> _existingFilePaths() async {
    final books = await _repository.listBooks();
    return books.map((b) => b.filePath).toSet();
  }

  Future<Book?> _importSingleFile(
    String uri, {
    String? displayName,
    String? folderName,
    bool takePermission = true,
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
    if (takePermission) {
      final persisted = await _persistPermissionOrLandCopy(uri, id, format);
      if (persisted == null) return null;
      resolvedUri = persisted;
    }

    final fallbackTitle = titleFromFileName(displayName ?? uri);
    final now = DateTime.now();

    final parts = await _prepareBookParts(
      originalUri: uri,
      resolvedUri: resolvedUri,
      format: format,
      id: id,
      fallbackTitle: fallbackTitle,
      landSuffix: '',
      strict: false,
      computeFingerprint: true,
    );
    if (parts == null) return null;

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

    final insertedBook = await _repository.insertBook(book);
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
      (displayName != null ? detectBookFileFormat(displayName) : null) ??
          detectBookFileFormat(uri);

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
  }) async {
    var title = fallbackTitle;
    String? author;
    String? coverPath;
    bool? isFixedLayout;
    String? epubIdentifier;
    var bookFilePath = resolvedUri;
    final stagedFiles = <String>[];

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

