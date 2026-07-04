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
  final decoded = Uri.decodeFull(uriOrPath);
  final normalized = decoded.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isNotEmpty ? segments.last : normalized;
}

class BookImportServiceImpl implements BookImportService {
  BookImportServiceImpl({
    required LibraryRepository repository,
    Directory? coversDirectory,
  })  : _repository = repository,
        _coversDirectory = coversDirectory;

  static const _channel = MethodChannel('elinkbook/book_metadata');

  final LibraryRepository _repository;
  final Directory? _coversDirectory;

  @override
  Future<List<Book>> importFiles(
    List<String> uris, {
    String? folderName,
  }) async {
    if (folderName != null) {
      await _repository.upsertGroup(folderName);
    }

    final imported = <Book>[];
    for (final uri in uris) {
      final book = await _importSingleFile(uri, folderName: folderName);
      if (book != null) imported.add(book);
    }
    return imported;
  }

  @override
  Future<List<Book>> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  }) {
    throw UnimplementedError(
      'importFolder 尚未實作，屬於 epic-1-library Issue 8 的範圍',
    );
  }

  Future<Book?> _importSingleFile(String uri, {String? folderName}) async {
    final format = detectBookFileFormat(uri);
    if (format == null) return null;

    // 只對 content:// scheme 持久化權限（file_picker 在 Android 上一定回傳
    // content:// URI；此判斷主要防禦測試/除錯情境誤傳純路徑）。持久化失敗
    // 時（例如來源 URI 不支援 persistable 權限）視為這個檔案匯入失敗並略過
    // ——不能假裝成功寫入資料庫，因為當次的暫時讀取權限只在本次 App 行程
    // 存活期間有效，寫入的 filePath 極可能在下次啟動後無法讀取，那會是比
    // 略過更糟的靜默壞資料。
    if (uri.startsWith('content://')) {
      try {
        await _channel.invokeMethod<void>(
          'takePersistableUriPermission',
          {'uri': uri},
        );
      } on PlatformException {
        return null;
      }
    }

    final id = '${DateTime.now().microsecondsSinceEpoch}-${uri.hashCode}';
    final fallbackTitle = titleFromFileName(uri);
    final now = DateTime.now();

    var title = fallbackTitle;
    String? author;
    String? coverPath;

    if (format == BookFileFormat.txt) {
      final coverBytes = await generateTxtCover(fallbackTitle);
      coverPath = await _landCover(coverBytes, id);
    } else {
      try {
        final metadata = await _channel.invokeMapMethod<String, Object?>(
          'extractMetadata',
          {'uri': uri, 'format': format.name},
        );
        final extractedTitle = metadata?['title'] as String?;
        if (extractedTitle != null && extractedTitle.isNotEmpty) {
          title = extractedTitle;
        }
        author = metadata?['author'] as String?;
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
      filePath: uri,
      source: BookSource.local,
      coverPath: coverPath,
      groupName: folderName ?? BookGroup.uncategorized,
      createTime: now,
      lastReadTime: now,
    );

    return _repository.insertBook(book);
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
}
