import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  })  : _repository = repository,
        _coversDirectory = coversDirectory,
        _importedBooksDirectory = importedBooksDirectory;

  // 使用 kBookMetadataChannel（library_repository.dart）作為共用通道名稱。

  final LibraryRepository _repository;
  final Directory? _coversDirectory;
  final Directory? _importedBooksDirectory;

  @override
  Future<ImportResult> importFiles(
    List<String> uris, {
    List<String?>? displayNames,
    String? folderName,
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
    try {
      await kBookMetadataChannel.invokeMethod<void>(
        'takePersistableUriPermission',
        {'uri': folderUri},
      );
    } on PlatformException {
      return const ImportResult(importedBooks: []);
    }

    Map<Object?, Object?>? contents;
    try {
      contents = await kBookMetadataChannel.invokeMapMethod<Object?, Object?>(
        'listFolderContents',
        {'uri': folderUri},
      );
    } on PlatformException {
      return const ImportResult(importedBooks: []);
    }
    if (contents == null) return const ImportResult(importedBooks: []);

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
  }) async {
    // 優先用呼叫端提供的真實檔名（例如 file_picker 的 PlatformFile.name）
    // 判斷格式，URI 本身當退路。部分文件提供者（例如媒體庫文件提供者
    // com.android.providers.media.documents，使用者透過系統選擇器的
    // 「最近」／媒體索引視圖選檔時常見）回傳的 URI 只帶不透明數字文件 ID
    // （例如 .../document/document%3A1000001716），完全不含檔名／副檔名
    // ——只看 URI 判斷格式在這種情況下必定回傳 null，導致整個檔案在最前面
    // 就被靜默跳過（真機驗證發現的實際症狀：選檔正確返回、匯入沒有拋出
    // 任何例外，但書架永遠是空的）。資料夾匯入（importFolder）目前仍只有
    // URI 可用（DocumentFile 的 uri 路徑對 externalstorage 這類本機提供者
    // 通常仍保留可辨識檔名），沒有另外提供 displayName 時退回原本行為。
    final format =
        (displayName != null ? detectBookFileFormat(displayName) : null) ??
            detectBookFileFormat(uri);
    if (format == null) return null;

    final id = '${DateTime.now().microsecondsSinceEpoch}-${uri.hashCode}';

    // 只對 content:// scheme 持久化權限（file_picker 在 Android 上一定回傳
    // content:// URI；此判斷主要防禦測試/除錯情境誤傳純路徑）。部分文件
    // 提供者（例如媒體庫文件提供者 com.android.providers.media.documents，
    // 相對於標準的外部儲存文件提供者）在某些裝置/Android 版本上不保證核發
    // 可持久化授權，`takePersistableUriPermission` 會拋出 PlatformException；
    // 此時不能直接放棄匯入（先前版本的行為——真機驗證發現這會讓匯入功能
    // 在部分裝置上整個無法使用），改為退而求其次：把檔案內容複製一份到
    // App 私有儲存空間，改用這份本機複本的真實檔案路徑，不再依賴來源
    // content:// URI 在下次啟動後是否還能讀取——複製失敗才視為這個檔案
    // 匯入失敗並略過。資料夾批次匯入（importFolder）的子檔案 URI 共用
    // 資料夾層級已取得的權限，呼叫時傳入 takePermission: false 跳過這一步。
    var resolvedUri = uri;
    if (takePermission && uri.startsWith('content://')) {
      var permissionGranted = true;
      try {
        await kBookMetadataChannel.invokeMethod<void>(
          'takePersistableUriPermission',
          {'uri': uri},
        );
      } on PlatformException {
        permissionGranted = false;
      }
      // 即使權限持久化成功，若來源 URI 本身不含可辨識副檔名（例如媒體庫
      // 文件提供者的不透明數字 ID），ReaderScreen 開啟時仍是依 filePath
      // 的副檔名判斷格式（detectBookFormat，與這裡的 format 判斷各自獨立
      // 運作）——filePath 若維持原始 URI，開啟時會判定為不支援的格式。
      // 因此只要 URI 本身沒有可辨識副檔名，就一律複製一份到本機、以正確
      // 副檔名命名，讓匯入與開啟兩處的格式判斷全程一致。
      if (!permissionGranted || detectBookFileFormat(uri) == null) {
        final localPath = await _copyToLocalStorage(uri, id, format);
        if (localPath == null) return null;
        resolvedUri = localPath;
      }
    }

    final fallbackTitle = titleFromFileName(displayName ?? uri);
    final now = DateTime.now();

    var title = fallbackTitle;
    String? author;
    String? coverPath;
    bool? isFixedLayout;
    String? epubIdentifier;
    // CBZ 專屬：重建後檔案的落地路徑，與 resolvedUri（原始來源，指紋計算
    // 依據）分離維護，見上方說明。其餘格式維持沿用 resolvedUri 本身。
    var bookFilePath = resolvedUri;

    if (format == BookFileFormat.txt) {
      // 封面產生（dart:ui）與 EPUB 合成（純 Dart，Isolate.run() 背景執行）
      // 是兩個獨立步驟，不可合併——dart:ui 綁定在裸 spawn 的 isolate 內
      // 不可用，見 txt_epub_synthesizer.dart Task 6 開頭「背景」說明。
      // 審查修正（reviews/review-issue-4-plan.md Important #1）：合成
      // 必須先於封面產生執行——若先落地封面才發現內容為空而中止匯入，
      // 會在磁碟留下孤兒封面檔案（沒有對應 Book 記錄，日後刪除書籍的
      // 既有清理邏輯是依附在 Book 記錄上運作，永遠碰不到它）。
      TxtSynthesisResult synthesis;
      try {
        synthesis = await synthesizeTxtBook(resolvedUri, id, fallbackTitle);
      } on EmptyTxtException {
        // 沒有可用內容的 TXT 本質上無法開啟，比照 CBZ 的
        // NoComicPagesException 既有處置慣例，中止匯入、不建立 Book 記錄
        // ——此時尚未呼叫 generateTxtCover()，磁碟上不會留下任何殘留檔案。
        return null;
      }
      isFixedLayout = false;
      bookFilePath = await _landTxtEpub(synthesis.epubBytes, id);
      final coverBytes = await generateTxtCover(fallbackTitle);
      coverPath = await _landCover(coverBytes, id);
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
          coverPath = await _landCover(coverBytes, id);
        }
      } on DrmProtectedException {
        // DRM 加密：明確不支援，不可比照下方 PlatformException 分支降級為
        // 「無封面/檔名為標題」繼續建立書籍記錄——中止本書匯入
        // （spec.md「KF8 (AZW3) 支援」）。
        return null;
      } catch (_) {
        // 其餘解析失敗（非 DRM，例如檔案損毀）：降級為「檔名為標題、無封面」，
        // 比照既有 PlatformException 分支慣例，不中斷整批匯入。
      }
    } else if (format == BookFileFormat.cbz) {
      // CBZ 自然排序重建與封面擷取（epic-11-multi-format-reader Issue 3）。
      // 像 azw3 分支一樣做 try/catch 降級，不中斷整批匯入。
      isFixedLayout = true; // CBZ 恆為定樣式（見 ADR 0023）
      try {
        final result = await prepareCbzForImport(resolvedUri);
        // 重建後的壓縮檔需要落地到本機，讓 ReaderScreen 開啟時有正確
        // 的 .cbz 副檔名（觸發 CBZ 分派路徑，見 detectBookFormat）。
        bookFilePath = await _landCbzArchive(result.rebuiltArchiveBytes, id);
        coverPath = await _landCover(result.coverBytes, id);
      } on NoComicPagesException {
        // CBZ 內不含任何圖片頁面（空封存或僅含非圖片檔案），中止本書匯入
        // （spec.md「CBZ 支援」）。
        return null;
      } catch (_) {
        // 其餘解析失敗（例如檔案損毀）：降級為「檔名為標題、無封面」，
        // 比照既有 PlatformException 分支慣例，不中斷整批匯入。
      }
    } else if (format == BookFileFormat.md) {
      // 合成必須先於封面產生執行——比照 Issue 4 Important #1 審查修正的
      // 既有教訓，避免中止匯入時在磁碟留下孤兒封面檔案。
      MdSynthesisResult synthesis;
      try {
        synthesis = await synthesizeMdBook(resolvedUri, id, fallbackTitle);
      } on EmptyMdException {
        return null;
      }
      isFixedLayout = false;
      bookFilePath = await _landMdEpub(synthesis.epubBytes, id);
      if (synthesis.frontmatterTitle != null && synthesis.frontmatterTitle!.isNotEmpty) {
        title = synthesis.frontmatterTitle!;
      }
      author = synthesis.frontmatterAuthor;
      // Frontmatter 未指定封面（或指定值無法解析，見 md_frontmatter.dart
      // 文件註解）時，退回比照 TXT 既有的「依書名文字動態生成封面」機制
      // （spec.md「TXT／Markdown 合成書籍結構」對 MD 的既定要求）。
      final coverBytes = synthesis.frontmatterCoverBytes ?? await generateTxtCover(title);
      coverPath = await _landCover(coverBytes, id);
    } else {
      try {
        final metadata = await kBookMetadataChannel.invokeMapMethod<String, Object?>(
          'extractMetadata',
          {'uri': resolvedUri, 'format': format.name},
        );
        final extractedTitle = metadata?['title'] as String?;
        if (extractedTitle != null && extractedTitle.isNotEmpty) {
          title = extractedTitle;
        }
        author = metadata?['author'] as String?;
        // PDF 的 extractMetadata 回傳 map 沒有這個鍵，cast 結果自然為 null，
        // 不需要另外依 format 分支判斷（見
        // docs/epics/epic-17-epub-render-migration/spec.md「模組」）。
        isFixedLayout = metadata?['isFixedLayout'] as bool?;
        // epic-8-sync Issue 3：同一次 extractMetadata 回應一併取得，PDF
        // 呼叫時這個鍵不存在，cast 結果自然為 null，不需要另外依 format
        // 分支判斷（比照 isFixedLayout 既有處理方式）。
        epubIdentifier = metadata?['identifier'] as String?;
        final coverBytes = metadata?['coverBytes'] as Uint8List?;
        if (coverBytes != null) {
          coverPath = await _landCover(coverBytes, id);
        }
      } on PlatformException {
        // 詮釋資料提取失敗：降級為「檔名為標題、無封面」，不中斷整批匯入。
        // 指紋計算與詮釋資料提取彼此獨立（見下方），此處失敗不影響指紋
        // 計算仍會嘗試執行。
      }
    }

    // 重建後的 CBZ（bookFilePath ≠ resolvedUri）：指紋仍依原始來源計算，
    // 跨裝置比對依原始來源內容而非重建後檔案，兩者內容等價但二進位不同，
    // 不應因為排序重建而改變指紋值。
    String? contentFingerprint;
    try {
      contentFingerprint = await computeBookContentFingerprint(
        resolvedUri,
        format,
        epubIdentifier: epubIdentifier,
      );
    } catch (_) {
      // 指紋計算失敗（原生端例外／檔案讀取失敗）：降級為 null，不中斷
      // 整批匯入——這本書在補算前不參與跨裝置比對，比照 epic-17
      // detectAndCacheEpubLayout() 的一次性補判斷模式（回填時機留待
      // Issue 4 決定，見 issues.md）。
    }

    final book = Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: bookFilePath,
      source: BookSource.local,
      coverPath: coverPath,
      isFixedLayout: isFixedLayout,
      contentFingerprint: contentFingerprint,
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

    return _repository.insertBook(book);
  }

  /// [takePersistableUriPermission] 失敗時的退路：把 [uri] 的內容複製一份到
  /// App 私有文件目錄下的 `imported_books/` 子目錄，回傳複本的真實檔案路徑；
  /// 複製失敗（例如來源 URI 這次連暫時讀取都失敗）回傳 null。
  Future<String?> _copyToLocalStorage(
    String uri,
    String id,
    BookFileFormat format,
  ) async {
    final importedDir = await _resolveImportedBooksDirectory();
    final destinationPath = p.join(importedDir.path, '$id.${format.name}');
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

  Future<String> _landCover(Uint8List bytes, String bookId) async {
    final dir = await _resolveCoversDirectory();
    final file = File(p.join(dir.path, '$bookId.png'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 將重建後的 CBZ 壓縮檔位元組寫入 `imported_books/` 目錄，回傳完整路徑。
  /// 檔名帶 `.cbz` 副檔名，確保 `detectBookFormat` 偵測正確。
  Future<String> _landCbzArchive(Uint8List bytes, String bookId) async {
    final importedDir = await _resolveImportedBooksDirectory();
    final file = File(p.join(importedDir.path, '$bookId.cbz'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 落地 TXT 合成的 EPUB 壓縮檔位元組（epic-11-multi-format-reader
  /// Issue 4），比照 [_landCover]／[_landCbzArchive] 既有的「以 book id
  /// 為鍵、獨立子目錄」慣例，重用既有 `imported_books/` 目錄。**檔名副
  /// 檔名須維持 `.txt`**（Global Constraints 已查證事實 #1：`BookFormat.txt`
  /// 的分派依 `Book.filePath` 副檔名判斷，不可改為 `.epub`）。
  Future<String> _landTxtEpub(Uint8List bytes, String bookId) async {
    final dir = await _resolveImportedBooksDirectory();
    final file = File(p.join(dir.path, '$bookId.txt'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 落地 MD 合成的 EPUB 壓縮檔位元組（epic-11-multi-format-reader
  /// Issue 5），比照 [_landTxtEpub] 既有的「以 book id 為鍵、獨立子目錄」
  /// 慣例，重用既有 `imported_books/` 目錄。**檔名副檔名須維持 `.md`**
  /// （理由同 `_landTxtEpub` 對 `.txt` 的既有限制）。
  Future<String> _landMdEpub(Uint8List bytes, String bookId) async {
    final dir = await _resolveImportedBooksDirectory();
    final file = File(p.join(dir.path, '$bookId.md'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
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
