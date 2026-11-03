// BookImportServiceImpl 注入 BookMetadataExtractor 測試（epic-66 Issue 2 Task 5）。
//
// 驗證：
// - 注入自訂 metadataExtractor 時，匯入 EPUB 優先呼叫該解析器；
// - 欄位 title, author, isFixedLayout, coverPath, contentFingerprint 正確對應；
// - 解析器拋出 PlatformException 時降級為檔名與無封面；
// - 未注入時走既有 kBookMetadataChannel 通道；
// - 非 EPUB/PDF（如 TXT）不呼叫解析器；
// - relinkBook 亦經由 metadataExtractor 取得 identifier 進行指紋比對。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/library_repository.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository repository;
  late Directory coversDir;
  late Directory importedBooksDir;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    coversDir = Directory.systemTemp.createTempSync('book_import_extractor_covers');
    importedBooksDir =
        Directory.systemTemp.createTempSync('book_import_extractor_imported');
    tempDir = Directory.systemTemp.createTempSync('book_import_extractor_src');
  });

  tearDown(() async {
    await repository.close();
    for (final dir in [coversDir, importedBooksDir, tempDir]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  test('注入假解析器：EPUB 匯入時接收 (路徑, epub)，且所有欄位正確寫入 Book', () async {
    final epubFile = File(p.join(tempDir.path, 'sample.epub'));
    await File('test/fixtures/sample.epub').copy(epubFile.path);

    String? receivedUri;
    String? receivedFormat;
    final dummyCover = Uint8List.fromList([1, 2, 3, 4]);

    final service = BookImportServiceImpl(
      repository: repository,
      coversDirectory: coversDir,
      importedBooksDirectory: importedBooksDir,
      metadataExtractor: (uri, format) async {
        receivedUri = uri;
        receivedFormat = format;
        return {
          'title': '解析書名',
          'author': '解析作者',
          'identifier': ' urn:uuid:custom-id ',
          'isFixedLayout': true,
          'coverBytes': dummyCover,
        };
      },
    );

    final result = await service.importFiles([epubFile.path]);
    expect(result.failure, isNull);
    expect(result.importedBooks, hasLength(1));

    expect(receivedUri, epubFile.path);
    expect(receivedFormat, 'epub');

    final book = result.importedBooks.single;
    expect(book.title, '解析書名');
    expect(book.author, '解析作者');
    expect(book.isFixedLayout, isTrue);
    expect(book.contentFingerprint, 'urn:uuid:custom-id', reason: '指紋應優先採用 trimmed identifier');
    expect(book.coverPath, isNotNull);
    expect(book.coverPath!.endsWith('${book.id}.png'), isTrue);
    expect(await File(book.coverPath!).readAsBytes(), equals(dummyCover));
  });

  test('假解析器丟 PlatformException：匯入不中斷，標題退回檔名、無封面', () async {
    final epubFile = File(p.join(tempDir.path, 'fallback.epub'));
    await File('test/fixtures/sample.epub').copy(epubFile.path);

    final service = BookImportServiceImpl(
      repository: repository,
      coversDirectory: coversDir,
      importedBooksDirectory: importedBooksDir,
      metadataExtractor: (uri, format) async {
        throw PlatformException(code: 'extraction_failed', message: 'error');
      },
    );

    final result = await service.importFiles([epubFile.path]);
    expect(result.failure, isNull);
    expect(result.importedBooks, hasLength(1));

    final book = result.importedBooks.single;
    expect(book.title, 'fallback');
    expect(book.author, isNull);
    expect(book.coverPath, isNull);
    expect(coversDir.listSync(), isEmpty);
  });

  test('未注入解析器（null）：走 kBookMetadataChannel 通道（Android 路徑）', () async {
    final epubFile = File(p.join(tempDir.path, 'android_channel.epub'));
    await File('test/fixtures/sample.epub').copy(epubFile.path);

    var channelCalled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kBookMetadataChannel, (call) async {
      if (call.method == 'extractMetadata') {
        channelCalled = true;
        return {
          'title': 'Android 書名',
          'author': 'Android 作者',
          'identifier': 'urn:uuid:android-id',
          'isFixedLayout': false,
          'coverBytes': null,
        };
      }
      return null;
    });

    try {
      final service = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
        importedBooksDirectory: importedBooksDir,
        metadataExtractor: null,
      );

      final result = await service.importFiles([epubFile.path]);
      expect(result.importedBooks, hasLength(1));
      expect(channelCalled, isTrue);
      expect(result.importedBooks.single.title, 'Android 書名');
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kBookMetadataChannel, null);
    }
  });

  test('匯入 TXT：自訂 metadataExtractor 不被呼叫', () async {
    final txtFile = File(p.join(tempDir.path, 'test.txt'));
    await File('test/fixtures/sample_synth.txt').copy(txtFile.path);

    var extractorCalled = false;
    final service = BookImportServiceImpl(
      repository: repository,
      coversDirectory: coversDir,
      importedBooksDirectory: importedBooksDir,
      metadataExtractor: (uri, format) async {
        extractorCalled = true;
        return null;
      },
    );

    await service.importFiles([txtFile.path]);
    expect(extractorCalled, isFalse);
  });

  test('relinkBook：透過 metadataExtractor 取得 identifier，成功比對同一本書；不同書回傳 contentMismatch', () async {
    final epub1 = File(p.join(tempDir.path, 'orig.epub'));
    await File('test/fixtures/sample.epub').copy(epub1.path);

    final epub2Same = File(p.join(tempDir.path, 'moved_same.epub'));
    await File('test/fixtures/sample.epub').copy(epub2Same.path);

    final epub3Diff = File(p.join(tempDir.path, 'moved_diff.epub'));
    await File('test/fixtures/sample.epub').copy(epub3Diff.path);

    final service = BookImportServiceImpl(
      repository: repository,
      coversDirectory: coversDir,
      importedBooksDirectory: importedBooksDir,
      metadataExtractor: (uri, format) async {
        if (uri.contains('moved_diff')) {
          return {
            'title': '不同書',
            'author': null,
            'identifier': 'urn:uuid:different-book',
            'isFixedLayout': false,
            'coverBytes': null,
          };
        }
        return {
          'title': '原書',
          'author': null,
          'identifier': 'urn:uuid:same-book',
          'isFixedLayout': false,
          'coverBytes': null,
        };
      },
    );

    final importRes = await service.importFiles([epub1.path]);
    final bookId = importRes.importedBooks.single.id;

    // 重新連結同一本書（identifier 相等）
    final relinkSame = await service.relinkBook(bookId, epub2Same.path);
    expect(relinkSame, isA<BookRelinkSuccess>());

    // 重新連結不同本書（identifier 相異）
    final relinkDiff = await service.relinkBook(bookId, epub3Diff.path);
    expect(relinkDiff, isA<BookRelinkFailure>());
    expect((relinkDiff as BookRelinkFailure).reason, BookRelinkFailureReason.contentMismatch);
  });
}
