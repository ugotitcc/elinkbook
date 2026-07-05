import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository repository;
  late Directory coversDir;
  late BookImportServiceImpl service;

  setUp(() async {
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    coversDir = Directory.systemTemp.createTempSync('book_import_test_covers');
    service =
        BookImportServiceImpl(repository: repository, coversDirectory: coversDir);
  });

  tearDown(() async {
    await repository.close();
    if (coversDir.existsSync()) coversDir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, handler);
  }

  test('匯入 EPUB 檔案呼叫 extractMetadata(format: epub) 並寫入正確詮釋資料',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        expect((call.arguments as Map)['format'], 'epub');
        return {
          'title': '紅樓夢',
          'author': '曹雪芹',
          'coverBytes': Uint8List.fromList([1, 2, 3]),
        };
      }
      return null;
    });

    final books = await service.importFiles(['content://example/book.epub']);

    expect(books, hasLength(1));
    expect(books.single.title, '紅樓夢');
    expect(books.single.author, '曹雪芹');
    expect(books.single.format, BookFileFormat.epub);
    expect(books.single.coverPath, isNotNull);
  });

  test('匯入 PDF 檔案呼叫 extractMetadata(format: pdf)，詮釋資料無標題時降級為檔名',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        expect((call.arguments as Map)['format'], 'pdf');
        return {
          'title': null,
          'author': null,
          'coverBytes': Uint8List.fromList([4, 5, 6]),
        };
      }
      return null;
    });

    final books = await service.importFiles(['content://example/report.pdf']);

    expect(books, hasLength(1));
    expect(books.single.format, BookFileFormat.pdf);
    expect(books.single.title, 'report');
    expect(books.single.coverPath, isNotNull);
  });

  test('匯入 TXT 檔案不呼叫 extractMetadata，改用 Dart 端動態產生封面', () async {
    var extractMetadataCalled = false;
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        extractMetadataCalled = true;
      }
      return null;
    });

    final books = await service.importFiles(['content://example/notes.txt']);

    expect(extractMetadataCalled, isFalse);
    expect(books, hasLength(1));
    expect(books.single.format, BookFileFormat.txt);
    expect(books.single.title, 'notes');
    expect(books.single.coverPath, isNotNull);
  });

  test('詮釋資料提取失敗時降級寫入：標題=檔名、coverPath=null，不中斷整批匯入',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        throw PlatformException(code: 'extraction_failed', message: '模擬失敗');
      }
      return null;
    });

    final books = await service.importFiles([
      'content://example/broken.epub',
      'content://example/another.pdf',
    ]);

    expect(books, hasLength(2));
    expect(books[0].title, 'broken');
    expect(books[0].coverPath, isNull);
    expect(books[1].title, 'another');
    expect(books[1].coverPath, isNull);
  });

  test('匯入成功的書籍 source 為 local，filePath 存放原始 URI（未被複製）',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    const uri =
        'content://com.android.externalstorage.documents/document/primary%3ADownload%2Fmybook.pdf';
    final books = await service.importFiles([uri]);

    expect(books.single.source, BookSource.local);
    expect(books.single.filePath, uri);
  });

  test('不支援的副檔名略過該檔案，不中斷整批匯入', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      return {'title': '有效書籍', 'author': null, 'coverBytes': null};
    });

    final books = await service.importFiles([
      'content://example/document.docx',
      'content://example/valid.epub',
    ]);

    expect(books, hasLength(1));
    expect(books.single.title, '有效書籍');
  });

  test('takePersistableUriPermission 失敗時略過該檔案，不寫入資料庫、不中斷整批匯入',
      () async {
    mockChannel((call) async {
      final args = call.arguments as Map;
      if (call.method == 'takePersistableUriPermission') {
        if ((args['uri'] as String).contains('no_permission')) {
          throw PlatformException(
              code: 'permission_failed', message: '模擬權限持久化失敗');
        }
        return null;
      }
      return {'title': '有效書籍', 'author': null, 'coverBytes': null};
    });

    final books = await service.importFiles([
      'content://example/no_permission.epub',
      'content://example/valid.pdf',
    ]);

    expect(books, hasLength(1));
    expect(books.single.title, '有效書籍');
  });

  test('指定 folderName 時自動建立分類並歸入，書籍 groupName 對應資料夾名稱',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final books = await service.importFiles(
      ['content://example/book.epub'],
      folderName: '古典奇幻',
    );

    expect(books.single.groupName, '古典奇幻');
    final groups = await repository.listGroups();
    expect(groups.map((g) => g.name), contains('古典奇幻'));
  });

  test('批次匯入資料夾內多個檔案，皆正確寫入 LibraryRepository', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'listFolderContents') {
        return {
          'folderName': '歷史小說',
          'fileUris': [
            'content://example/tree/folder/document/book1.epub',
            'content://example/tree/folder/document/book2.pdf',
          ],
        };
      }
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final books = await service.importFolder('content://example/tree/folder');

    expect(books, hasLength(2));
    final savedBooks = await repository.listBooks();
    expect(savedBooks, hasLength(2));
  });

  test('autoGroupByFolderName=true 且群組不存在時，自動建立同名群組並歸入', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'listFolderContents') {
        return {
          'folderName': '歷史小說',
          'fileUris': ['content://example/tree/folder/document/book1.epub'],
        };
      }
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final books = await service.importFolder(
      'content://example/tree/folder',
      autoGroupByFolderName: true,
    );

    expect(books.single.groupName, '歷史小說');
    final groups = await repository.listGroups();
    expect(groups.map((g) => g.name), contains('歷史小說'));
  });

  test('autoGroupByFolderName=true 且群組已存在時，直接歸入既有群組、不重複建立',
      () async {
    await repository.upsertGroup('歷史小說');
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'listFolderContents') {
        return {
          'folderName': '歷史小說',
          'fileUris': ['content://example/tree/folder/document/book1.epub'],
        };
      }
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    await service.importFolder('content://example/tree/folder');

    final groups = await repository.listGroups();
    expect(groups.where((g) => g.name == '歷史小說'), hasLength(1));
  });

  test('autoGroupByFolderName=false 時，匯入書籍歸入預設「未分類」', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'listFolderContents') {
        return {
          'folderName': '歷史小說',
          'fileUris': ['content://example/tree/folder/document/book1.epub'],
        };
      }
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final books = await service.importFolder(
      'content://example/tree/folder',
      autoGroupByFolderName: false,
    );

    expect(books.single.groupName, BookGroup.uncategorized);
  });
}
