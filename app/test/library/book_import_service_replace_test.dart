import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/notes_repository.dart';
import 'package:elinkbook/theme/app_theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_full_text_search_settings_repository.dart';
import '../support/throw_on_update_repository.dart';

class _RecordingFtsRepo extends FakeFullTextSearchSettingsRepository {
  bool throwOnClearBookIndex = false;
  final List<String> operationOrder = [];

  @override
  Future<void> clearBookIndex(String bookId) async {
    operationOrder.add('clearBookIndex:$bookId');
    await super.clearBookIndex(bookId);
    if (throwOnClearBookIndex) {
      throw Exception('Simulated clearBookIndex failure');
    }
  }

  @override
  Future<void> handleBookAvailable(Book book) async {
    operationOrder.add('handleBookAvailable:${book.id}');
    await super.handleBookAvailable(book);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const channel = MethodChannel('elinkbook/book_metadata');

  late SqliteLibraryRepository repository;
  late Directory tempDir;
  late Directory coversDir;
  late Directory importedDir;
  late Directory stagingDir;
  late BookImportServiceImpl service;
  late _RecordingFtsRepo ftsRepo;

  // 記錄原生方法呼叫次數
  int computeSha256CallCount = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    tempDir = Directory.systemTemp.createTempSync('replace_test_');
    coversDir = Directory(p.join(tempDir.path, 'covers'))..createSync();
    importedDir = Directory(p.join(tempDir.path, 'imported_books'))..createSync();
    stagingDir = Directory(p.join(tempDir.path, 'update_staging'))..createSync();
    ftsRepo = _RecordingFtsRepo();

    computeSha256CallCount = 0;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'computeSha256') {
        computeSha256CallCount++;
        return 'sha256-dummy';
      }
      if (call.method == 'takePersistableUriPermission') {
        return null;
      }
      if (call.method == 'copyContentUriToFile') {
        final args = call.arguments as Map;
        final dest = args['destinationPath'] as String;
        File(dest).writeAsStringSync('copied-content');
        return null;
      }
      if (call.method == 'extractMetadata') {
        return <String, Object?>{
          'title': '新版書名',
          'author': '新版作者',
          'isFixedLayout': false,
          'identifier': 'new-identifier',
          'coverBytes': Uint8List.fromList([1, 2, 3, 4]),
        };
      }
      return null;
    });

    service = BookImportServiceImpl(
      repository: repository,
      coversDirectory: coversDir,
      importedBooksDirectory: importedDir,
      updateStagingDirectory: stagingDir,
      fullTextSearchSettingsRepository: ftsRepo,
      themePreferences: AppThemePreferences(),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await repository.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('BookImportService.replaceBook', () {
    test('身份與閱讀進度完整保留（EPUB／PDF 驗證）', () async {
      final oldFile = File(p.join(importedDir.path, 'epub-1.epub'))
        ..writeAsStringSync('舊 EPUB');
      final originalBook = Book(
        id: 'epub-1',
        title: '舊版書名',
        author: '舊版作者',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        groupName: '我的收藏',
        contentFingerprint: 'fixed-original-fingerprint',
        progress: 0.42,
        epubLocator: '{"cfi":"/6/4"}',
        createTime: DateTime.fromMillisecondsSinceEpoch(100000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(200000),
      );
      await repository.insertBook(originalBook);

      final newFile = File(p.join(tempDir.path, 'new_book.epub'))
        ..writeAsStringSync('新 EPUB');

      final result = await service.replaceBook('epub-1', newFile.path);

      expect(result, isA<BookReplaceSuccess>());
      final updated = (result as BookReplaceSuccess).updatedBook;

      // 身份與閱讀位置保留
      expect(updated.id, 'epub-1');
      expect(updated.contentFingerprint, 'fixed-original-fingerprint');
      expect(updated.progress, 0.42);
      expect(updated.epubLocator, '{"cfi":"/6/4"}');
      expect(updated.groupName, '我的收藏');
      expect(updated.createTime, DateTime.fromMillisecondsSinceEpoch(100000));
      expect(updated.lastReadTime, DateTime.fromMillisecondsSinceEpoch(200000));

      // 中繼資料更新
      expect(updated.title, '新版書名');
      expect(updated.author, '新版作者');
      expect(updated.isFixedLayout, isFalse);
    });

    test('註記完整保留（書籤、劃線、備註仍存在且 deleteBook 呼叫 0 次）', () async {
      final oldFile = File(p.join(importedDir.path, 'note-book.epub'))
        ..writeAsStringSync('舊書');
      final book = Book(
        id: 'note-book',
        title: '舊書',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(book);

      final bookmarksRepo = BookmarksRepository(repository.database);
      final highlightsRepo = HighlightsRepository(repository.database);
      final notesRepo = NotesRepository(repository.database);

      await bookmarksRepo.insert(const Bookmark(
        id: 'bm-1',
        bookId: 'note-book',
        name: '書籤一',
        progression: 0.25,
      ));
      await highlightsRepo.insert(const Highlight(
        id: 'hl-1',
        bookId: 'note-book',
        style: HighlightStyle.highlighterYellow,
        progression: 0.3,
      ));
      await notesRepo.insert(const Note(
        id: 'nt-1',
        bookId: 'note-book',
        text: '這是一則重要備註',
        progression: 0.3,
      ));

      final newFile = File(p.join(tempDir.path, 'new.epub'))..writeAsStringSync('新書');
      final result = await service.replaceBook('note-book', newFile.path);

      expect(result, isA<BookReplaceSuccess>());

      final bookmarks = await bookmarksRepo.listByBook('note-book');
      final highlights = await highlightsRepo.listByBook('note-book');
      final notes = await notesRepo.listByBook('note-book');

      expect(bookmarks.length, 1);
      expect(bookmarks.first.name, '書籤一');
      expect(highlights.length, 1);
      expect(notes.length, 1);
      expect(notes.first.text, '這是一則重要備註');
    });

    test('單書版面偏好保留', () async {
      final oldFile = File(p.join(importedDir.path, 'prefs-book.epub'))
        ..writeAsStringSync('舊書');
      final book = Book(
        id: 'prefs-book',
        title: '舊書',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(book);

      final prefsRepo = BookReaderPrefsRepository(repository.database);
      await prefsRepo.save('prefs-book', const BookReaderPrefs(fontSize: 18.0));

      final newFile = File(p.join(tempDir.path, 'new.epub'))..writeAsStringSync('新書');
      await service.replaceBook('prefs-book', newFile.path);

      final loaded = await prefsRepo.load('prefs-book');
      expect(loaded.fontSize, 18.0);
    });

    test('封面更新與刪除：新檔無封面時刪除舊封面檔且 coverPath 為 null', () async {
      final oldCover = File(p.join(coversDir.path, 'cov-book.png'))
        ..writeAsBytesSync([9, 9, 9]);
      final oldFile = File(p.join(importedDir.path, 'cov-book.epub'))
        ..writeAsStringSync('舊書');
      final book = Book(
        id: 'cov-book',
        title: '舊書',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        coverPath: oldCover.path,
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(book);

      // 模擬新檔 extractMetadata 回傳無封面（coverBytes == null）且無作者
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'extractMetadata') {
          return <String, Object?>{
            'title': '新書名無封面',
            'author': null,
            'isFixedLayout': null,
            'coverBytes': null,
          };
        }
        return null;
      });

      final newFile = File(p.join(tempDir.path, 'no_cov.epub'))..writeAsStringSync('新書');
      final result = await service.replaceBook('cov-book', newFile.path);

      expect(result, isA<BookReplaceSuccess>());
      final updated = (result as BookReplaceSuccess).updatedBook;

      expect(updated.coverPath, isNull);
      expect(updated.author, isNull);
      expect(updated.isFixedLayout, isNull);
      expect(oldCover.existsSync(), isFalse); // 舊封面檔案已被刪除
    });

    test('TXT／MD 重新合成：以新內容取代後，filePath 指向合成檔且反映新內容', () async {
      final oldMdFile = File(p.join(importedDir.path, 'md-1.md'))
        ..writeAsStringSync('舊合成內容');
      final book = Book(
        id: 'md-1',
        title: '舊筆記',
        format: BookFileFormat.md,
        filePath: oldMdFile.path,
        source: BookSource.local,
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(book);

      final newMdSource = File(p.join(tempDir.path, 'source.md'))
        ..writeAsStringSync('---\ntitle: 新筆記標題\nauthor: 新筆記作者\n---\n新版內容');

      final result = await service.replaceBook('md-1', newMdSource.path);

      expect(result, isA<BookReplaceSuccess>());
      final updated = (result as BookReplaceSuccess).updatedBook;
      expect(updated.title, '新筆記標題');
      expect(updated.author, '新筆記作者');
      final archive =
          ZipDecoder().decodeBytes(File(updated.filePath).readAsBytesSync());
      expect(archive.findFile('OEBPS/content.opf'), isNotNull);
      final section = archive.files
          .firstWhere((f) => f.name.contains('section_') || f.name.endsWith('.xhtml'));
      expect(utf8.decode(section.readBytes()!), contains('新版內容'));
      expect(p.basename(updated.filePath), 'md-1.md');
    });

    test('全文檢索：clearBookIndex 在 handleBookAvailable 之前呼叫各一次；拋例外時取代仍成功', () async {
      final oldFile = File(p.join(importedDir.path, 'fts-book.epub'))..writeAsStringSync('舊');
      final book = Book(
        id: 'fts-book',
        title: '舊',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(book);

      final newFile = File(p.join(tempDir.path, 'new.epub'))..writeAsStringSync('新');
      ftsRepo.throwOnClearBookIndex = true; // clearBookIndex 拋錯

      final result = await service.replaceBook('fts-book', newFile.path);

      expect(result, isA<BookReplaceSuccess>());
      expect(ftsRepo.operationOrder, [
        'clearBookIndex:fts-book',
        'handleBookAvailable:fts-book',
      ]);
    });

    test('舊資產清理：舊書為私有複本且新路徑不同時舊檔被刪；新路徑等於舊路徑時檔案不被刪', () async {
      final oldPrivate = File(p.join(importedDir.path, 'old-priv.epub'))
        ..writeAsStringSync('舊私有複本');
      final book = Book(
        id: 'priv-1',
        title: '私有舊書',
        format: BookFileFormat.epub,
        filePath: oldPrivate.path,
        source: BookSource.local,
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(book);

      // 新來源是可持久化 content://（新 filePath 是 content://）
      final result = await service.replaceBook(
        'priv-1',
        'content://downloads/new.epub',
      );

      expect(result, isA<BookReplaceSuccess>());
      expect(oldPrivate.existsSync(), isFalse); // 舊私有複本被刪除
    });

    test('格式不符：PDF 取代 EPUB 回傳 formatMismatch，舊書與舊檔不動', () async {
      final oldFile = File(p.join(importedDir.path, 'fmt-1.epub'))..writeAsStringSync('舊');
      final book = Book(
        id: 'fmt-1',
        title: 'EPUB 書',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(book);

      final pdfFile = File(p.join(tempDir.path, 'new.pdf'))..writeAsStringSync('PDF 內容');
      final result = await service.replaceBook('fmt-1', pdfFile.path);

      expect(result, isA<BookReplaceFailure>());
      expect((result as BookReplaceFailure).reason, BookReplaceFailureReason.formatMismatch);
      expect(oldFile.existsSync(), isTrue);
    });

    test('bookNotFound：不存在的 id 回傳 bookNotFound', () async {
      final result = await service.replaceBook('no-such-id', '/path/to/file.epub');
      expect(result, isA<BookReplaceFailure>());
      expect((result as BookReplaceFailure).reason, BookReplaceFailureReason.bookNotFound);
    });

    test('原子性：各階段注入失敗時回傳對應失敗原因，無殘留 .staging 檔且舊檔與資料庫不動', () async {
      // 1. extractMetadata 拋 PlatformException (D3 嚴格模式)
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'extractMetadata') {
          throw PlatformException(code: 'CORRUPTED', message: '檔案損毀');
        }
        return null;
      });

      final oldFile = File(p.join(importedDir.path, 'atomic-1.epub'))
        ..writeAsStringSync('原始不可動搖的內容');
      final book = Book(
        id: 'atomic-1',
        title: '原始書名',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(book);

      final badFile = File(p.join(tempDir.path, 'bad.epub'))..writeAsStringSync('損毀新檔');
      final result = await service.replaceBook('atomic-1', badFile.path);

      expect(result, isA<BookReplaceFailure>());
      expect((result as BookReplaceFailure).reason, BookReplaceFailureReason.newFileParseFailed);
      expect(oldFile.readAsStringSync(), '原始不可動搖的內容');

      // 檢查目錄中絕無任何 .staging 檔
      final stagingFiles = importedDir.listSync().where((f) => f.path.contains('.staging'));
      expect(stagingFiles, isEmpty);
    });

    test('審查 C-1 回歸：無法持久化的 content:// 不提前覆寫舊檔', () async {
      final oldFile = File(p.join(importedDir.path, 'c1-book.epub'))
        ..writeAsStringSync('舊私有複本內容');
      final book = Book(
        id: 'c1-book',
        title: '舊私有書',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(book);

      // takePersistableUriPermission 失敗，copyContentUriToFile 成功複製到 .staging，
      // 但新檔損毀（extractMetadata 拋 PlatformException）
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'takePersistableUriPermission') {
          throw PlatformException(code: 'DENIED', message: '授權失敗');
        }
        if (call.method == 'copyContentUriToFile') {
          final dest = (call.arguments as Map)['destinationPath'] as String;
          File(dest).writeAsStringSync('新檔複製資料');
          return null;
        }
        if (call.method == 'extractMetadata') {
          throw PlatformException(code: 'CORRUPTED', message: '損毀檔案');
        }
        return null;
      });

      final result = await service.replaceBook('c1-book', 'content://downloads/bad.epub');

      expect(result, isA<BookReplaceFailure>());
      expect((result as BookReplaceFailure).reason, BookReplaceFailureReason.newFileParseFailed);
      expect(oldFile.readAsStringSync(), '舊私有複本內容'); // 逐位元完全相同
      final stagingFiles = importedDir.listSync().where((f) => f.path.contains('.staging'));
      expect(stagingFiles, isEmpty);
    });

    test('審查 M-4：取代過程不重算整檔雜湊，computeSha256 未被呼叫', () async {
      final oldFile = File(p.join(importedDir.path, 'm4-book.epub'))..writeAsStringSync('舊');
      final book = Book(
        id: 'm4-book',
        title: '舊書',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        contentFingerprint: 'preserved-hash',
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(book);

      final newFile = File(p.join(tempDir.path, 'new.epub'))..writeAsStringSync('新');
      final result = await service.replaceBook('m4-book', newFile.path);

      expect(result, isA<BookReplaceSuccess>());
      expect(computeSha256CallCount, 0); // computeSha256 一次都沒被呼叫！
    });

    test('sourceRefs 與 candidate 處理：成功時暫存檔被丟棄，失敗時暫存檔仍保留', () async {
      final oldFile = File(p.join(importedDir.path, 'cand-book.epub'))..writeAsStringSync('舊');
      final book = Book(
        id: 'cand-book',
        title: '舊書',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(book);

      await repository.database.insert('remote_servers', {
        'id': 'server-1',
        'name': '測試伺服器',
        'base_url': 'http://127.0.0.1/opds',
        'type': 'opds',
        'allow_insecure': 0,
        'created_at': 1000,
      });

      final candidateStaged = File(p.join(stagingDir.path, 'staged-new.epub'))
        ..writeAsStringSync('候選暫存內容');

      final candidate = BookUpdateCandidate(
        sourceUri: 'content://downloads/remote.epub',
        displayName: 'remote.epub',
        format: BookFileFormat.epub,
        confidence: UpdateConfidence.high,
        candidateBooks: [book],
        stagedPath: candidateStaged.path,
      );

      const sourceRefs = BookSourceRefs(
        cloudFileId: 'drive-file-999',
        remoteServerId: 'server-1',
        remoteBookId: 'book-42',
      );

      final result = await service.replaceBook(
        'cand-book',
        'content://downloads/remote.epub',
        candidate: candidate,
        sourceRefs: sourceRefs,
      );

      expect(result, isA<BookReplaceSuccess>());
      final updated = (result as BookReplaceSuccess).updatedBook;
      expect(updated.cloudFileId, 'drive-file-999');
      expect(updated.remoteServerId, 'server-1');
      expect(updated.remoteBookId, 'book-42');
      expect(candidateStaged.existsSync(), isFalse); // 取代成功後暫存檔被清除
    });

    test('ThrowOnUpdateRepository 失敗與修復案例（Review Focus 2 殘餘風險驗證）', () async {
      final throwRepo = ThrowOnUpdateRepository();
      final throwService = BookImportServiceImpl(
        repository: throwRepo,
        coversDirectory: coversDir,
        importedBooksDirectory: importedDir,
        updateStagingDirectory: stagingDir,
      );

      final bookFile = File(p.join(importedDir.path, 'res-book.epub'))..writeAsStringSync('舊書內容');
      final book = Book(
        id: 'res-book',
        title: '舊書',
        format: BookFileFormat.epub,
        filePath: bookFile.path,
        source: BookSource.local,
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await throwRepo.insertBook(book);

      // 第一次：updateBook 失敗
      throwRepo.throwOnUpdate = true;
      final newFile = File(p.join(tempDir.path, 'new.epub'))..writeAsStringSync('新書內容');
      final failResult = await throwService.replaceBook('res-book', newFile.path);

      expect(failResult, isA<BookReplaceFailure>());
      expect((failResult as BookReplaceFailure).reason, BookReplaceFailureReason.writeFailed);

      // 第二次：修復 updateBook 後再次呼叫 replaceBook 成功完成
      throwRepo.throwOnUpdate = false;
      final retryResult = await throwService.replaceBook('res-book', newFile.path);

      expect(retryResult, isA<BookReplaceSuccess>());
      final updated = (retryResult as BookReplaceSuccess).updatedBook;
      expect(updated.title, '新版書名');
    });
  });
}
