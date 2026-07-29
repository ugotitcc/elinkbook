import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'book_import_service.dart';
import 'library_repository.dart';
import 'models/book.dart';
import 'models/book_group.dart';
import 'models/library_enums.dart';
import 'txt_cover_generator.dart';

/// 依 URI/路徑字串最後一段（已對 percent-encoding 解碼）判斷書籍格式。
/// 只依副檔名判斷，僅適用於本機檔案匯入（file_picker/SAF 對本機檔案提供者
/// 通常會在 URI 中保留可辨識的原始檔名+副檔名）；不適用於雲端服務自訂的
/// 不透明文件 ID（雲端匯入本身不在本 epic 範圍內）。
BookFileFormat? detectBookFileFormat(String uriOrPath) {
  final name = _lastPathComponent(uriOrPath).toLowerCase();
  if (name.endsWith('.epub')) return BookFileFormat.epub;
  if (name.endsWith('.pdf')) return BookFileFormat.pdf;
  if (name.endsWith('.txt')) return BookFileFormat.txt;
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

  static const _channel = MethodChannel('elinkbook/book_metadata');

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
      await _channel.invokeMethod<void>(
        'takePersistableUriPermission',
        {'uri': folderUri},
      );
    } on PlatformException {
      return const ImportResult(importedBooks: []);
    }

    Map<Object?, Object?>? contents;
    try {
      contents = await _channel.invokeMapMethod<Object?, Object?>(
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
        await _channel.invokeMethod<void>(
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

    if (format == BookFileFormat.txt) {
      final coverBytes = await generateTxtCover(fallbackTitle);
      coverPath = await _landCover(coverBytes, id);
    } else {
      try {
        final metadata = await _channel.invokeMapMethod<String, Object?>(
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
        final coverBytes = metadata?['coverBytes'] as Uint8List?;
        if (coverBytes != null) {
          coverPath = await _landCover(coverBytes, id);
        }
      } on PlatformException {
        // 詮釋資料提取失敗：降級為「檔名為標題、無封面」，不中斷整批匯入。
      }
    }

    final book = Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: resolvedUri,
      source: BookSource.local,
      coverPath: coverPath,
      isFixedLayout: isFixedLayout,
      groupName: folderName ?? BookGroup.uncategorized,
      createTime: now,
      lastReadTime: now,
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
      await _channel.invokeMethod<void>(
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
