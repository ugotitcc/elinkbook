import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_content_fingerprint.dart';
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';
import 'package:elinkbook/theme/app_theme_preferences.dart';

import '../support/fake_path_provider_platform.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository repository;
  late Directory coversDir;
  late Directory importedBooksDir;
  late Directory kf8TempDir;
  late PathProviderPlatform originalPathProvider;
  late BookImportServiceImpl service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    coversDir = Directory.systemTemp.createTempSync('book_import_test_covers');
    importedBooksDir = Directory.systemTemp.createTempSync(
      'book_import_test_imported',
    );
    // extractKf8Metadata() 對 content:// URI 呼叫 getTemporaryDirectory()
    // 複製暫存檔（見 kf8_metadata.dart）；`flutter test` 無真實裝置，需以
    // FakePathProviderPlatform 替身讓其回傳真實可寫入目錄（比照既有
    // notes_bottom_sheet_test.dart 的既有慣例）。
    kf8TempDir = Directory.systemTemp.createTempSync('book_import_test_kf8_tmp');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(kf8TempDir.path);
    service = BookImportServiceImpl(
      repository: repository,
      coversDirectory: coversDir,
      importedBooksDirectory: importedBooksDir,
    );
  });

  tearDown(() async {
    await repository.close();
    if (coversDir.existsSync()) coversDir.deleteSync(recursive: true);
    if (importedBooksDir.existsSync()) {
      importedBooksDir.deleteSync(recursive: true);
    }
    PathProviderPlatform.instance = originalPathProvider;
    if (kf8TempDir.existsSync()) kf8TempDir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, handler);
  }

  test('匯入 EPUB 檔案呼叫 extractMetadata(format: epub) 並寫入正確詮釋資料', () async {
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

    final result = await service.importFiles(['content://example/book.epub']);
    final books = result.importedBooks;

    expect(books, hasLength(1));
    expect(books.single.title, '紅樓夢');
    expect(books.single.author, '曹雪芹');
    expect(books.single.format, BookFileFormat.epub);
    expect(books.single.coverPath, isNotNull);
  });

  test(
      '匯入的書籍 lastReadTime 為「尚未讀過」哨兵值（epoch 0），非匯入當下時間'
      '（epic-18-reader-device-qa Issue 29：剛匯入、從未打開過的書不該被誤判為'
      '「最後閱讀」蓋過真正最近在讀的書）', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        return {'title': '剛匯入的書'};
      }
      return null;
    });

    final result = await service.importFiles(['content://example/book.epub']);
    final book = result.importedBooks.single;

    expect(book.lastReadTime, DateTime.fromMillisecondsSinceEpoch(0));
    expect(book.createTime, isNot(DateTime.fromMillisecondsSinceEpoch(0)),
        reason: 'createTime 仍應正確記錄實際匯入時間，只有 lastReadTime 改用哨兵值');
  });

  test('匯入 EPUB 檔案時，extractMetadata 回傳的 isFixedLayout 正確寫入 Book', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        return {
          'title': '定樣式漫畫',
          'author': null,
          'coverBytes': null,
          'isFixedLayout': true,
        };
      }
      return null;
    });

    final result = await service.importFiles(['content://example/comic.epub']);
    final books = result.importedBooks;

    expect(books.single.isFixedLayout, isTrue);
  });

  test('匯入流式 EPUB（isFixedLayout: false）時正確寫入 Book', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        return {
          'title': '流式小說',
          'author': null,
          'coverBytes': null,
          'isFixedLayout': false,
        };
      }
      return null;
    });

    final result = await service.importFiles(['content://example/novel.epub']);
    final books = result.importedBooks;

    expect(books.single.isFixedLayout, isFalse);
  });

  test('匯入 PDF 檔案時，isFixedLayout 維持 null（extractMetadata 回傳無此欄位）', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        return {'title': null, 'author': null, 'coverBytes': null};
      }
      return null;
    });

    final result = await service.importFiles(['content://example/report.pdf']);
    final books = result.importedBooks;

    expect(books.single.isFixedLayout, isNull);
  });

  test('匯入 TXT 檔案時，isFixedLayout 為 false（流式排版，不呼叫 extractMetadata）', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'copyContentUriToFile') {
        final args = call.arguments as Map;
        await File(args['destinationPath'] as String).writeAsString('第一章 測試\n內容');
        return null;
      }
      return null;
    });

    final result = await service.importFiles(['content://example/notes.txt']);
    final books = result.importedBooks;

    expect(books.single.isFixedLayout, isFalse);
  });

  test('匯入 PDF 檔案呼叫 extractMetadata(format: pdf)，詮釋資料無標題時降級為檔名', () async {
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

    final result = await service.importFiles(['content://example/report.pdf']);
    final books = result.importedBooks;

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
      if (call.method == 'copyContentUriToFile') {
        final args = call.arguments as Map;
        await File(args['destinationPath'] as String).writeAsString('第一章 測試\n內容');
        return null;
      }
      return null;
    });

    final result = await service.importFiles(['content://example/notes.txt']);
    final books = result.importedBooks;

    expect(extractMetadataCalled, isFalse);
    expect(books, hasLength(1));
    expect(books.single.format, BookFileFormat.txt);
    expect(books.single.title, 'notes');
    expect(books.single.coverPath, isNotNull);
  });

  test('詮釋資料提取失敗時降級寫入：標題=檔名、coverPath=null，不中斷整批匯入', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        throw PlatformException(code: 'extraction_failed', message: '模擬失敗');
      }
      return null;
    });

    final result = await service.importFiles([
      'content://example/broken.epub',
      'content://example/another.pdf',
    ]);
    final books = result.importedBooks;

    expect(books, hasLength(2));
    expect(books[0].title, 'broken');
    expect(books[0].coverPath, isNull);
    expect(books[1].title, 'another');
    expect(books[1].coverPath, isNull);
  });

  test('匯入成功的書籍 source 為 local，filePath 存放原始 URI（未被複製）', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    const uri =
        'content://com.android.externalstorage.documents/document/primary%3ADownload%2Fmybook.pdf';
    final result = await service.importFiles([uri]);
    final books = result.importedBooks;

    expect(books.single.source, BookSource.local);
    expect(books.single.filePath, uri);
  });

  test('不支援的副檔名略過該檔案，不中斷整批匯入', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      return {'title': '有效書籍', 'author': null, 'coverBytes': null};
    });

    final result = await service.importFiles([
      'content://example/document.docx',
      'content://example/valid.epub',
    ]);
    final books = result.importedBooks;

    expect(books, hasLength(1));
    expect(books.single.title, '有效書籍');
  });

  test('takePersistableUriPermission 失敗但複製到本機儲存成功時，'
      '改用本機複本路徑繼續完成匯入（不再直接略過）', () async {
    mockChannel((call) async {
      final args = call.arguments as Map;
      if (call.method == 'takePersistableUriPermission') {
        if ((args['uri'] as String).contains('no_permission')) {
          throw PlatformException(
            code: 'permission_failed',
            message: '模擬權限持久化失敗',
          );
        }
        return null;
      }
      if (call.method == 'copyContentUriToFile') return null; // 模擬複製成功
      return {'title': '有效書籍', 'author': null, 'coverBytes': null};
    });

    final result = await service.importFiles([
      'content://example/no_permission.epub',
      'content://example/valid.pdf',
    ]);
    final books = result.importedBooks;

    expect(books, hasLength(2));
    expect(
      books[0].filePath,
      isNot(startsWith('content://')),
      reason: '權限持久化失敗後應改存本機複本路徑，不是原始 content:// URI',
    );
  });

  test('takePersistableUriPermission 與複製到本機儲存都失敗時，'
      '真的略過該檔案，不寫入資料庫、不中斷整批匯入', () async {
    mockChannel((call) async {
      final args = call.arguments as Map;
      if (call.method == 'takePersistableUriPermission') {
        if ((args['uri'] as String).contains('no_permission')) {
          throw PlatformException(
            code: 'permission_failed',
            message: '模擬權限持久化失敗',
          );
        }
        return null;
      }
      if (call.method == 'copyContentUriToFile') {
        throw PlatformException(code: 'copy_failed', message: '模擬複製失敗');
      }
      return {'title': '有效書籍', 'author': null, 'coverBytes': null};
    });

    final result = await service.importFiles([
      'content://example/no_permission.epub',
      'content://example/valid.pdf',
    ]);
    final books = result.importedBooks;

    expect(books, hasLength(1));
    expect(books.single.title, '有效書籍');
  });

  test('URI 為不透明文件 ID（不含可辨識副檔名，例如媒體庫文件提供者）時，'
      '改用 displayNames 判斷格式仍能成功匯入', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        expect((call.arguments as Map)['format'], 'epub');
        return {'title': '葬送的芙莉蓮', 'author': null, 'coverBytes': null};
      }
      return null;
    });

    // 真機驗證發現的實際情境：content:// 最後一段是不透明數字 ID，完全不含
    // 副檔名（見 book_import_service_impl.dart 對
    // com.android.providers.media.documents 的說明）；若只看 URI，
    // detectBookFileFormat 必定回傳 null，整個檔案會在最前面就被靜默跳過。
    const opaqueUri =
        'content://com.android.providers.media.documents/document/document%3A1000001716';
    final result = await service.importFiles(
      [opaqueUri],
      displayNames: ['葬送的芙莉蓮 11.epub'],
    );
    final books = result.importedBooks;

    expect(books, hasLength(1));
    expect(books.single.format, BookFileFormat.epub);
    expect(books.single.title, '葬送的芙莉蓮');
  });

  test('displayNames 為 null（未提供）時退回只看 URI 判斷格式，行為與先前版本一致', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final result = await service.importFiles(['content://example/book.epub']);
    final books = result.importedBooks;

    expect(books, hasLength(1));
    expect(books.single.format, BookFileFormat.epub);
  });

  test('指定 folderName 時自動建立分類並歸入，書籍 groupName 對應資料夾名稱', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final result = await service.importFiles([
      'content://example/book.epub',
    ], folderName: '古典奇幻');
    final books = result.importedBooks;

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

    final result = await service.importFolder('content://example/tree/folder');
    final books = result.importedBooks;

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

    final result = await service.importFolder(
      'content://example/tree/folder',
      autoGroupByFolderName: true,
    );
    final books = result.importedBooks;

    expect(books.single.groupName, '歷史小說');
    final groups = await repository.listGroups();
    expect(groups.map((g) => g.name), contains('歷史小說'));
  });

  test('autoGroupByFolderName=true 且群組已存在時，直接歸入既有群組、不重複建立', () async {
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

    final result = await service.importFolder(
      'content://example/tree/folder',
      autoGroupByFolderName: false,
    );
    final books = result.importedBooks;

    expect(books.single.groupName, BookGroup.uncategorized);
  });

  group('重複匯入偵測（診斷修正：同一本書可以重複匯入）', () {
    test('來源 URI 與圖書庫既有書籍相同時，跳過不新增，並回報 skippedDuplicateCount',
        () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        return {'title': '既有書籍', 'author': null, 'coverBytes': null};
      });

      const uri = 'content://example/existing.epub';
      final firstImport = await service.importFiles([uri]);
      expect(firstImport.importedBooks, hasLength(1));
      expect(firstImport.skippedDuplicateCount, 0);

      final secondImport = await service.importFiles([uri]);

      expect(secondImport.importedBooks, isEmpty);
      expect(secondImport.skippedDuplicateCount, 1);
      final allBooks = await repository.listBooks();
      expect(allBooks, hasLength(1),
          reason: '重複匯入不應該在資料庫多寫入第二筆同一份來源檔案的書籍列');
    });

    test('同一批次內重複選取同一個 URI 兩次，只匯入一次，第二次視為重複跳過',
        () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        return {'title': '書籍', 'author': null, 'coverBytes': null};
      });

      const uri = 'content://example/duplicate_in_same_batch.epub';
      final result = await service.importFiles([uri, uri]);

      expect(result.importedBooks, hasLength(1));
      expect(result.skippedDuplicateCount, 1);
      final allBooks = await repository.listBooks();
      expect(allBooks, hasLength(1));
    });

    test('不同來源 URI 的書籍（即使書名相同）不會被誤判為重複而跳過', () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        return {'title': '同名書', 'author': null, 'coverBytes': null};
      });

      final result = await service.importFiles([
        'content://example/copy_a.epub',
        'content://example/copy_b.epub',
      ]);

      expect(result.importedBooks, hasLength(2));
      expect(result.skippedDuplicateCount, 0);
    });

    test('importFolder 內含與圖書庫既有書籍相同來源 URI 的檔案時，同樣跳過並回報',
        () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'listFolderContents') {
          return {
            'folderName': '歷史小說',
            'fileUris': [
              'content://example/tree/folder/document/existing.epub',
              'content://example/tree/folder/document/new.epub',
            ],
          };
        }
        return {'title': '書籍', 'author': null, 'coverBytes': null};
      });

      await service.importFiles(
        ['content://example/tree/folder/document/existing.epub'],
      );

      final result = await service.importFolder('content://example/tree/folder');

      expect(result.importedBooks, hasLength(1));
      expect(result.importedBooks.single.filePath,
          'content://example/tree/folder/document/new.epub');
      expect(result.skippedDuplicateCount, 1);
    });
  });

  group('content_fingerprint（epic-8-sync Issue 3）', () {
    test('EPUB 匯入時，extractMetadata 回傳的 identifier 優先寫入 content_fingerprint，不呼叫 computeSha256',
        () async {
      var computeSha256Called = false;
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {
            'title': '書名',
            'author': null,
            'coverBytes': null,
            'identifier': 'urn:uuid:00000000-0000-0000-0000-000000000099',
          };
        }
        if (call.method == 'computeSha256') {
          computeSha256Called = true;
          return 'should-not-be-used';
        }
        return null;
      });

      final result = await service.importFiles(['content://example/book.epub']);

      expect(result.importedBooks.single.contentFingerprint,
          'urn:uuid:00000000-0000-0000-0000-000000000099');
      expect(computeSha256Called, isFalse);
    });

    test('EPUB 匯入時，identifier 缺漏則呼叫 computeSha256，結果寫入 content_fingerprint',
        () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '書名', 'author': null, 'coverBytes': null};
        }
        if (call.method == 'computeSha256') {
          expect((call.arguments as Map)['uri'], 'content://example/book2.epub');
          return 'fallback-hash-abc';
        }
        return null;
      });

      final result =
          await service.importFiles(['content://example/book2.epub']);

      expect(
          result.importedBooks.single.contentFingerprint, 'fallback-hash-abc');
    });

    test('PDF 匯入時，呼叫 computeSha256 並寫入 content_fingerprint', () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': null, 'author': null, 'coverBytes': null};
        }
        if (call.method == 'computeSha256') return 'pdf-hash-xyz';
        return null;
      });

      final result = await service.importFiles(['content://example/report.pdf']);

      expect(result.importedBooks.single.contentFingerprint, 'pdf-hash-xyz');
    });

    test('TXT 匯入時，呼叫 computeSha256 並寫入 content_fingerprint', () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'copyContentUriToFile') {
          final args = call.arguments as Map;
          await File(args['destinationPath'] as String).writeAsString('第一章 測試\n內容');
          return null;
        }
        if (call.method == 'computeSha256') return 'txt-hash-123';
        return null;
      });

      final result = await service.importFiles(['content://example/notes.txt']);

      expect(result.importedBooks.single.contentFingerprint, 'txt-hash-123');
    });

    test('computeSha256 失敗（回傳 null）時，content_fingerprint 降級為 null，不中斷匯入',
        () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '書名', 'author': null, 'coverBytes': null};
        }
        return null; // computeSha256 未被特別處理，落到這裡回傳 null
      });

      final result = await service.importFiles(['content://example/book3.epub']);

      expect(result.importedBooks, hasLength(1));
      expect(result.importedBooks.single.contentFingerprint, isNull);
    });

    test('extractMetadata 拋出例外時，content_fingerprint 仍嘗試計算（兩者互相獨立）',
        () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          throw PlatformException(code: 'extraction_failed', message: '模擬失敗');
        }
        if (call.method == 'computeSha256') return 'still-computed-hash';
        return null;
      });

      final result = await service.importFiles(['content://example/book4.epub']);

      expect(result.importedBooks.single.title, 'book4');
      expect(result.importedBooks.single.contentFingerprint,
          'still-computed-hash');
    });
  });

  group('KF8 (AZW3) 匯入', () {
    test('匯入 AZW3：title/coverPath 正確寫入 Book', () async {
      final result = await service.importFiles(
        ['test/fixtures/sample.azw3'],
        displayNames: ['sample.azw3'],
      );

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.first;
      expect(book.title, contains('Time Machine'));
      expect(book.format, BookFileFormat.azw3);
      expect(book.coverPath, isNotNull);
      expect(File(book.coverPath!).existsSync(), isTrue);
    });

    test('匯入受 DRM 保護的 AZW3：不建立 Book 記錄', () async {
      final bytes = Uint8List(78 + 8 + 132);
      bytes.setRange(60, 64, 'BOOK'.codeUnits);
      bytes.setRange(64, 68, 'MOBI'.codeUnits);
      ByteData.sublistView(bytes, 76, 78).setUint16(0, 1, Endian.big);
      ByteData.sublistView(bytes, 78, 82).setUint32(0, 86, Endian.big);
      bytes.setRange(86 + 16, 86 + 20, 'MOBI'.codeUnits);
      ByteData.sublistView(bytes, 86 + 12, 86 + 14).setUint16(0, 2, Endian.big);
      final drmFile = File('${Directory.systemTemp.path}/import_test_drm.azw3');
      await drmFile.writeAsBytes(bytes);
      addTearDown(() => drmFile.delete());

      final result = await service.importFiles(
        [drmFile.path],
        displayNames: ['drm_sample.azw3'],
      );

      expect(result.importedBooks, isEmpty);
    });

    test(
      '匯入 AZW3（content:// URI，權限授予成功且副檔名可辨識——標準 Android '
      '檔案選擇器匯入的常見情況）：title/coverPath 正確寫入 Book'
      '（epic-11 Issue 2 程式碼審查 C1 迴歸測試）',
      () async {
        mockChannel((call) async {
          if (call.method == 'takePersistableUriPermission') return null;
          if (call.method == 'copyContentUriToFile') {
            final args = call.arguments as Map;
            final bytes = await File('test/fixtures/sample.azw3').readAsBytes();
            await File(args['destinationPath'] as String).writeAsBytes(bytes);
            return null;
          }
          return null;
        });

        final result = await service.importFiles(
          ['content://example/sample.azw3'],
          displayNames: ['sample.azw3'],
        );

        expect(result.importedBooks, hasLength(1));
        final book = result.importedBooks.first;
        expect(book.title, contains('Time Machine'));
        expect(book.coverPath, isNotNull);
        expect(File(book.coverPath!).existsSync(), isTrue);
      },
    );

    test(
      '匯入受 DRM 保護的 AZW3（content:// URI）：不建立 Book 記錄'
      '（epic-11 Issue 2 程式碼審查 C1 迴歸測試）',
      () async {
        final bytes = Uint8List(78 + 8 + 132);
        bytes.setRange(60, 64, 'BOOK'.codeUnits);
        bytes.setRange(64, 68, 'MOBI'.codeUnits);
        ByteData.sublistView(bytes, 76, 78).setUint16(0, 1, Endian.big);
        ByteData.sublistView(bytes, 78, 82).setUint32(0, 86, Endian.big);
        bytes.setRange(86 + 16, 86 + 20, 'MOBI'.codeUnits);
        ByteData.sublistView(bytes, 86 + 12, 86 + 14).setUint16(0, 2, Endian.big);

        mockChannel((call) async {
          if (call.method == 'takePersistableUriPermission') return null;
          if (call.method == 'copyContentUriToFile') {
            final args = call.arguments as Map;
            await File(args['destinationPath'] as String).writeAsBytes(bytes);
            return null;
          }
          return null;
        });

        final result = await service.importFiles(
          ['content://example/drm_sample.azw3'],
          displayNames: ['drm_sample.azw3'],
        );

        expect(result.importedBooks, isEmpty);
      },
    );
  });

  group('CBZ 匯入', () {
    // prepareCbzForImport 是純 Dart，需要真實 .cbz 檔案才能運作——不走
    // kBookMetadataChannel mock。以下測試用隨機產生的有效 CBZ 封存檔，
    // 比照 azw3 分支的「在 setUp 建好 service、mock channel」模式。

    /// 產生一份內含一張 PNG 漫畫頁面的有效 CBZ 封存檔位元組。
    Uint8List makeValidCbz() {
      // 最小有效 PNG（1x1 灰色像素），避免壓縮空檔案產生「無圖片頁面」。
      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, // PNG signature
        0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, // IHDR
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
        0xde, 0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41, // IDAT
        0x54, 0x08, 0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
        0x00, 0x00, 0x02, 0x00, 0x01, 0xe2, 0x21, 0xbc,
        0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, // IEND
        0x44, 0xae, 0x42, 0x60, 0x82,
      ]);
      final archive = Archive();
      archive.addFile(ArchiveFile('page_001.jpg', pngBytes.length, pngBytes));
      return Uint8List.fromList(
        ZipEncoder().encode(archive),
      );
    }

    /// 產生一份空的 CBZ 封存檔（無圖片頁面）。
    Uint8List makeEmptyCbz() {
      final archive = Archive();
      archive.addFile(
        ArchiveFile('readme.txt', 5, Uint8List.fromList('hello'.codeUnits)),
      );
      return Uint8List.fromList(
        ZipEncoder().encode(archive),
      );
    }

    test('匯入有效 CBZ：format=cbz 且封面落地', () async {
      final cbzBytes = makeValidCbz();
      final cbzFile = File('${Directory.systemTemp.path}/import_test.cbz');
      await cbzFile.writeAsBytes(cbzBytes);
      addTearDown(() => cbzFile.deleteSync());

      // 不 mock extractMetadata（CBZ 不走原生詮釋資料提取），只 mock
      // copyContentUriToFile（content:// URI 降級複製到本機的場景）。
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'copyContentUriToFile') {
          final args = call.arguments as Map;
          await File(args['destinationPath'] as String)
              .writeAsBytes(cbzBytes);
          return null;
        }
        return null;
      });

      // 用 content:// URI + displayName 模擬從系統選擇器匯入 CBZ。
      final result = await service.importFiles(
        ['content://example/comics.cbz'],
        displayNames: ['comics.cbz'],
      );

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.first;
      expect(book.format, BookFileFormat.cbz);
      expect(book.coverPath, isNotNull);
      expect(File(book.coverPath!).existsSync(), isTrue);
      // filePath 必須是重建後的 .cbz（本機路徑），不是原始 content:// URI。
      expect(book.filePath, endsWith('.cbz'));
      expect(book.filePath, isNot(startsWith('content://')));
      // CBZ 恆為固定版面（spec.md「CBZ 支援」）——epic-11 Issue 3 程式碼
      // 審查 Important #4：這正是 c7da43f 真實修復過的回歸類型（匯入
      // 分支曾遺漏 isFixedLayout = true），先前測試群完全沒有斷言這個
      // 欄位，只能靠慢的真機 integration_test 抓到。
      expect(book.isFixedLayout, isTrue);
    });

    test(
      'contentFingerprint 對原始 content:// URI 計算，非重建後的本機 .cbz 檔案'
      '（epic-11 Issue 3 程式碼審查 Important #4）',
      () async {
        final cbzBytes = makeValidCbz();
        const originalUri = 'content://example/fingerprint_comics.cbz';
        String? capturedFingerprintUri;

        mockChannel((call) async {
          if (call.method == 'takePersistableUriPermission') return null;
          if (call.method == 'copyContentUriToFile') {
            final args = call.arguments as Map;
            await File(args['destinationPath'] as String)
                .writeAsBytes(cbzBytes);
            return null;
          }
          if (call.method == 'computeSha256') {
            final args = call.arguments as Map;
            capturedFingerprintUri = args['uri'] as String;
            return 'cbz-original-file-hash';
          }
          return null;
        });

        final result = await service.importFiles(
          [originalUri],
          displayNames: ['fingerprint_comics.cbz'],
        );

        expect(result.importedBooks, hasLength(1));
        final book = result.importedBooks.first;
        // computeSha256 必須是對「原始 content:// URI」呼叫，而非重建後
        // 落地的本機 .cbz 檔案路徑——若計算依據誤植為重建後檔案，不同
        // 裝置/重建時機產出的壓縮檔在 zip 內部結構層面存在非決定性差異
        // （zip 內部檔案順序等），會讓同一本書在跨裝置比對時被誤判為
        // 不同書（spec.md「TXT／Markdown 合成書籍結構」contentFingerprint
        // 計算順序原則，同一原則套用於 CBZ 的重建步驟）。
        expect(capturedFingerprintUri, originalUri);
        expect(book.contentFingerprint, 'cbz-original-file-hash');
        // 佐證 filePath 確實已指向重建後的本機檔案（與計算指紋所用的
        // originalUri 不同），排除「兩者剛好相同因而測試恆真」的可能性。
        expect(book.filePath, isNot(originalUri));
        expect(book.filePath, endsWith('.cbz'));
      },
    );

    test('匯入空 CBZ（無圖片頁面）：不建立 Book 記錄', () async {
      final emptyCbzBytes = makeEmptyCbz();
      final cbzFile = File('${Directory.systemTemp.path}/import_empty.cbz');
      await cbzFile.writeAsBytes(emptyCbzBytes);
      addTearDown(() => cbzFile.deleteSync());

      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'copyContentUriToFile') {
          final args = call.arguments as Map;
          await File(args['destinationPath'] as String)
              .writeAsBytes(emptyCbzBytes);
          return null;
        }
        return null;
      });

      final result = await service.importFiles(
        ['content://example/empty_comics.cbz'],
        displayNames: ['empty_comics.cbz'],
      );

      expect(result.importedBooks, isEmpty);
    });

    test('匯入本機路徑 CBZ（file:// URI）：不呼叫 takePersistableUriPermission', () async {
      final cbzBytes = makeValidCbz();
      final cbzFile = File('${Directory.systemTemp.path}/import_local.cbz');
      await cbzFile.writeAsBytes(cbzBytes);
      addTearDown(() => cbzFile.deleteSync());

      var takePermissionCalled = false;
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') {
          takePermissionCalled = true;
          return null;
        }
        return null;
      });

      final result = await service.importFiles([cbzFile.path]);

      expect(takePermissionCalled, isFalse);
      expect(result.importedBooks, hasLength(1));
      expect(result.importedBooks.first.format, BookFileFormat.cbz);
    });

    test(
        'CBZ 匯入成功後，content_index_status 標記為 unsupported'
        '（epic-10-search Issue 2）', () async {
      final fullTextSearchSettingsRepository =
          SqliteFullTextSearchSettingsRepository(
        database: repository.database,
        requestProcessing: () {},
      );
      final serviceWithSearch = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
        importedBooksDirectory: importedBooksDir,
        fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      );
      final cbzBytes = makeValidCbz();
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'copyContentUriToFile') {
          final args = call.arguments as Map;
          await File(args['destinationPath'] as String)
              .writeAsBytes(cbzBytes);
          return null;
        }
        return null;
      });

      final result = await serviceWithSearch.importFiles(
        ['content://example/unsupported_comics.cbz'],
        displayNames: ['unsupported_comics.cbz'],
      );

      expect(result.importedBooks, hasLength(1));
      final rows = await repository.database.query(
        'content_index_status',
        where: 'book_id = ?',
        whereArgs: [result.importedBooks.first.id],
      );
      expect(rows, hasLength(1));
      expect(rows.single['status'], 'unsupported');
    });

    test(
        '未提供 fullTextSearchSettingsRepository（null）時，CBZ 匯入結果不受影響，'
        '也不寫入 content_index_status', () async {
      final cbzBytes = makeValidCbz();
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'copyContentUriToFile') {
          final args = call.arguments as Map;
          await File(args['destinationPath'] as String)
              .writeAsBytes(cbzBytes);
          return null;
        }
        return null;
      });

      final result = await service.importFiles(
        ['content://example/no_search_comics.cbz'],
        displayNames: ['no_search_comics.cbz'],
      );

      expect(result.importedBooks, hasLength(1));
      final rows = await repository.database.query(
        'content_index_status',
        where: 'book_id = ?',
        whereArgs: [result.importedBooks.first.id],
      );
      expect(rows, isEmpty);
    });
  });

  group('epic-10-search Issue 2：新匯入書籍全文檢索狀態連動（非 CBZ 格式）', () {
    test('EPUB 匯入時若 foliate 分類已啟用，寫入 pending 並喚醒排程器',
        () async {
      var requestProcessingCallCount = 0;
      final fullTextSearchSettingsRepository =
          SqliteFullTextSearchSettingsRepository(
        database: repository.database,
        requestProcessing: () => requestProcessingCallCount++,
      );
      await fullTextSearchSettingsRepository.setEnabled(
        ContentIndexCategory.foliate,
        true,
      );
      // setEnabled(true) 本身的批次回填也會呼叫一次，重置計數只驗證匯入
      // 這一步觸發的喚醒次數。
      requestProcessingCallCount = 0;
      final serviceWithSearch = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
        importedBooksDirectory: importedBooksDir,
        fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      );
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '測試書'};
        }
        return null;
      });

      final result = await serviceWithSearch.importFiles(
        ['content://example/new_book.epub'],
      );

      expect(result.importedBooks, hasLength(1));
      final rows = await repository.database.query(
        'content_index_status',
        where: 'book_id = ?',
        whereArgs: [result.importedBooks.first.id],
      );
      expect(rows, hasLength(1));
      expect(rows.single['status'], 'pending');
      expect(requestProcessingCallCount, 1);
    });

    test('EPUB 匯入時若 foliate 分類未啟用，不寫入 content_index_status',
        () async {
      final fullTextSearchSettingsRepository =
          SqliteFullTextSearchSettingsRepository(
        database: repository.database,
        requestProcessing: () {},
      );
      final serviceWithSearch = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
        importedBooksDirectory: importedBooksDir,
        fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      );
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '測試書'};
        }
        return null;
      });

      final result = await serviceWithSearch.importFiles(
        ['content://example/new_book_disabled.epub'],
      );

      expect(result.importedBooks, hasLength(1));
      final rows = await repository.database.query(
        'content_index_status',
        where: 'book_id = ?',
        whereArgs: [result.importedBooks.first.id],
      );
      expect(rows, isEmpty);
    });
  });

  group('TXT 匯入', () {
    test('匯入有效 TXT：format=txt、isFixedLayout=false、filePath 指向合成後的 .txt 檔案', () async {
      final txtFile = File('${Directory.systemTemp.path}/import_test.txt');
      await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文內容'));
      addTearDown(() => txtFile.delete());

      final result = await service.importFiles([txtFile.path], displayNames: ['novel.txt']);

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.first;
      expect(book.format, BookFileFormat.txt);
      expect(book.isFixedLayout, isFalse);
      expect(book.filePath, isNot(txtFile.path));
      expect(book.filePath, endsWith('.txt'));
      expect(File(book.filePath).existsSync(), isTrue);
      // 合成後的檔案內容須是合法 zip（EPUB），非原始純文字。
      final archive = ZipDecoder().decodeBytes(await File(book.filePath).readAsBytes());
      expect(archive.findFile('OEBPS/content.opf'), isNotNull);
    });

    test('封面仍由 generateTxtCover() 依書名產生（TXT 無內嵌封面/首頁可渲染）', () async {
      final txtFile = File('${Directory.systemTemp.path}/import_test_cover.txt');
      await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文'));
      addTearDown(() => txtFile.delete());

      final result = await service.importFiles([txtFile.path], displayNames: ['novel.txt']);

      final book = result.importedBooks.first;
      expect(book.coverPath, isNotNull);
      expect(File(book.coverPath!).existsSync(), isTrue);
    });

    test('contentFingerprint 對原始檔案計算，非合成後的 .txt 檔案', () async {
      final txtFile = File('${Directory.systemTemp.path}/import_test_fingerprint.txt');
      await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文'));
      addTearDown(() => txtFile.delete());

      final result = await service.importFiles([txtFile.path], displayNames: ['novel.txt']);

      final book = result.importedBooks.first;
      final expectedFingerprint =
          await computeBookContentFingerprint(txtFile.path, BookFileFormat.txt);
      expect(book.contentFingerprint, expectedFingerprint);
    });

    test(
      '空白 TXT 檔案不建立 Book 記錄，且不留下孤兒封面檔案'
      '（epic-11 Issue 4 程式碼審查 Important #1 迴歸測試：修復前會先落地封面'
      '才發現內容為空而中止，導致 covers/ 目錄殘留無主檔案）',
      () async {
        final txtFile = File('${Directory.systemTemp.path}/import_test_empty.txt');
        await txtFile.writeAsBytes(utf8.encode('   \n\n   '));
        addTearDown(() => txtFile.delete());

        final result = await service.importFiles([txtFile.path], displayNames: ['empty.txt']);

        expect(result.importedBooks, isEmpty);
        // coversDir 由頂層 setUp() 提供（見既有 service 建構），空匯入不應
        // 在其中留下任何檔案。
        expect(coversDir.listSync(), isEmpty);
      },
    );

    test('Big5 編碼 TXT 正確匯入（解碼於合成階段完成，匯入結果與 UTF-8 無異）', () async {
      // 「測試」的 Big5 位元組為 0xB4FA 0xB8D5（見
      // txt_charset_detection_test.dart 已交叉驗證的已知值）；前綴一個
      // ASCII 字元涵蓋「非純中文開頭」的較真實檔案內容型態。
      final big5Bytes = Uint8List.fromList([
        0x41, // 'A'
        0xB4, 0xFA, 0xB8, 0xD5, // 測試
      ]);
      final txtFile = File('${Directory.systemTemp.path}/import_test_big5.txt');
      await txtFile.writeAsBytes(big5Bytes);
      addTearDown(() => txtFile.delete());

      final result = await service.importFiles([txtFile.path], displayNames: ['big5_novel.txt']);

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.first;
      final archive = ZipDecoder().decodeBytes(await File(book.filePath).readAsBytes());
      final chapterContent = utf8.decode(archive.findFile('OEBPS/text/chap0001.xhtml')!.readBytes()!);
      expect(chapterContent, contains('測試'));
    });
  });

  group('MD 匯入', () {
    test('匯入有效 MD：format=md、isFixedLayout=false、filePath 指向合成後的 .md 檔案', () async {
      final mdFile = File('${Directory.systemTemp.path}/import_test.md');
      await mdFile.writeAsBytes(utf8.encode('# 第一章\n內容'));
      addTearDown(() => mdFile.delete());

      final result = await service.importFiles([mdFile.path], displayNames: ['notes.md']);

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.first;
      expect(book.format, BookFileFormat.md);
      expect(book.isFixedLayout, isFalse);
      expect(book.filePath, isNot(mdFile.path));
      expect(book.filePath, endsWith('.md'));
      expect(File(book.filePath).existsSync(), isTrue);
      final archive = ZipDecoder().decodeBytes(await File(book.filePath).readAsBytes());
      expect(archive.findFile('OEBPS/content.opf'), isNotNull);
    });

    test('Frontmatter 標題/作者正確寫入 Book，無 Frontmatter 時使用檔名標題', () async {
      final mdFile = File('${Directory.systemTemp.path}/import_test_fm.md');
      await mdFile.writeAsBytes(
        utf8.encode('---\ntitle: 我的筆記\nauthor: 作者甲\n---\n# 內容\n正文'),
      );
      addTearDown(() => mdFile.delete());

      final result = await service.importFiles([mdFile.path], displayNames: ['notes_fm.md']);

      final book = result.importedBooks.first;
      expect(book.title, '我的筆記');
      expect(book.author, '作者甲');
    });

    test('無 Frontmatter 封面時，封面退回依書名文字動態產生（比照 TXT 既有機制）', () async {
      final mdFile = File('${Directory.systemTemp.path}/import_test_cover_fallback.md');
      await mdFile.writeAsBytes(utf8.encode('# 內容\n正文'));
      addTearDown(() => mdFile.delete());

      final result = await service.importFiles([mdFile.path], displayNames: ['notes_cover.md']);

      final book = result.importedBooks.first;
      expect(book.coverPath, isNotNull);
      expect(File(book.coverPath!).existsSync(), isTrue);
    });

    test('Frontmatter 指定 data: URI 封面時，優先使用該封面而非動態產生', () async {
      final pngBytes = [0x89, 0x50, 0x4E, 0x47];
      final base64Data = base64Encode(pngBytes);
      final mdFile = File('${Directory.systemTemp.path}/import_test_cover_fm.md');
      await mdFile.writeAsBytes(
        utf8.encode('---\ntitle: 有封面\ncover: data:image/png;base64,$base64Data\n---\n# 內容\n正文'),
      );
      addTearDown(() => mdFile.delete());

      final result = await service.importFiles([mdFile.path], displayNames: ['notes_cover_fm.md']);

      final book = result.importedBooks.first;
      expect(await File(book.coverPath!).readAsBytes(), pngBytes);
    });

    test('contentFingerprint 對原始檔案計算，非合成後的 .md 檔案', () async {
      final mdFile = File('${Directory.systemTemp.path}/import_test_fingerprint.md');
      await mdFile.writeAsBytes(utf8.encode('# 內容\n正文'));
      addTearDown(() => mdFile.delete());

      final result = await service.importFiles([mdFile.path], displayNames: ['notes_fp.md']);

      final book = result.importedBooks.first;
      final expectedFingerprint =
          await computeBookContentFingerprint(mdFile.path, BookFileFormat.md);
      expect(book.contentFingerprint, expectedFingerprint);
    });

    test('空白 MD 檔案不建立 Book 記錄，且不留下孤兒封面檔案', () async {
      final mdFile = File('${Directory.systemTemp.path}/import_test_empty.md');
      await mdFile.writeAsBytes(utf8.encode('---\ntitle: 空內容\n---\n   \n\n   '));
      addTearDown(() => mdFile.delete());

      final result = await service.importFiles([mdFile.path], displayNames: ['empty.md']);

      expect(result.importedBooks, isEmpty);
      expect(coversDir.listSync(), isEmpty);
    });
  });

  group('E-Ink 模式封面（Issue 8）', () {
    test('E-Ink 模式開啟時，TXT 匯入封面為白底黑框', () async {
      SharedPreferences.setMockInitialValues({'app_eink_mode': true});
      final txtFile =
          File('${Directory.systemTemp.path}/import_test_eink_txt.txt');
      await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文'));
      addTearDown(() => txtFile.delete());

      final result =
          await service.importFiles([txtFile.path], displayNames: ['eink_novel.txt']);
      final book = result.importedBooks.first;
      final coverBytes = await File(book.coverPath!).readAsBytes();

      expect(await _pixelColor(coverBytes, 2, 2), const ui.Color(0xFF000000),
          reason: 'E-Ink 模式封面左上角應為黑色邊框');
    });

    test('E-Ink 模式開啟時，MD 匯入封面（無 Frontmatter 封面）同樣為白底黑框', () async {
      SharedPreferences.setMockInitialValues({'app_eink_mode': true});
      final mdFile =
          File('${Directory.systemTemp.path}/import_test_eink_md.md');
      await mdFile.writeAsBytes(utf8.encode('# 內容\n正文'));
      addTearDown(() => mdFile.delete());

      final result =
          await service.importFiles([mdFile.path], displayNames: ['eink_notes.md']);
      final book = result.importedBooks.first;
      final coverBytes = await File(book.coverPath!).readAsBytes();

      expect(await _pixelColor(coverBytes, 2, 2), const ui.Color(0xFF000000),
          reason: 'E-Ink 模式封面左上角應為黑色邊框');
    });

    test('E-Ink 模式關閉（預設）時，TXT 匯入封面維持既有 6 色輪替＋白字行為', () async {
      // 不設定 app_eink_mode，AppThemePreferences.loadEinkMode() 依既有邏輯
      // 預設回傳 false。
      final txtFile =
          File('${Directory.systemTemp.path}/import_test_noeink_txt.txt');
      await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文'));
      addTearDown(() => txtFile.delete());

      final result =
          await service.importFiles([txtFile.path], displayNames: ['novel.txt']);
      final book = result.importedBooks.first;
      final coverBytes = await File(book.coverPath!).readAsBytes();

      expect(
        await _pixelColor(coverBytes, 2, 2),
        isNot(const ui.Color(0xFF000000)),
        reason: '非 E-Ink 模式不應出現 E-Ink 分支才有的黑色邊框',
      );
    });

    test(
        'BookImportServiceImpl 建構子接收自訂 themePreferences 時，'
        '匯入確實使用該實例的 loadEinkMode()（而非忽略參數改建構預設實例）', () async {
      // 審查修正 I1：不設定 app_eink_mode（全域 SharedPreferences 維持預設
      // false），改用 _FixedEinkModePreferences（見下方 1c）固定回傳 true。
      // 若 BookImportServiceImpl 建構子筆誤忽略傳入的 themePreferences、
      // 改用預設 AppThemePreferences() 讀取全域設定，這裡會讀到 false，
      // 封面就不會是 E-Ink 樣式——這則測試才會抓到那個回歸；純靠
      // SharedPreferences.setMockInitialValues() 無法區分兩者（見
      // reviews/review-plan-issue-8.md I1）。
      final customService = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
        importedBooksDirectory: importedBooksDir,
        themePreferences: _FixedEinkModePreferences(true),
      );
      final txtFile =
          File('${Directory.systemTemp.path}/import_test_custom_prefs.txt');
      await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文'));
      addTearDown(() => txtFile.delete());

      final result = await customService.importFiles(
        [txtFile.path],
        displayNames: ['custom_prefs.txt'],
      );
      final book = result.importedBooks.first;
      final coverBytes = await File(book.coverPath!).readAsBytes();

      expect(await _pixelColor(coverBytes, 2, 2), const ui.Color(0xFF000000),
          reason: '注入的 themePreferences 固定回傳 true，封面應為 E-Ink 黑框樣式');
    });
  });

  group('遠端書架參數擴充（epic-30）', () {
    test('傳入 source/remoteServerId/remoteBookIds/remoteDownloadUrls 時正確落地',
        () async {
      await repository.database.insert('remote_servers', {
        'id': 'srv1',
        'name': '家用 NAS',
        'base_url': 'http://192.168.1.100:8080/opds',
        'type': 'opds',
        'allow_insecure': 0,
        'created_at': 1000,
      });

      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '遠端書'};
        }
        return null;
      });

      final result = await service.importFiles(
        ['content://example/remote_book.epub'],
        source: BookSource.calibreOpds,
        remoteServerId: 'srv1',
        remoteBookIds: {'content://example/remote_book.epub': 'remote-book-1'},
        remoteDownloadUrls: {
          'content://example/remote_book.epub':
              'http://192.168.1.100:8080/opds/download/1.epub',
        },
      );

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.source, BookSource.calibreOpds);
      expect(book.remoteServerId, 'srv1');
      expect(book.remoteBookId, 'remote-book-1');
      expect(book.remoteDownloadUrl,
          'http://192.168.1.100:8080/opds/download/1.epub');
      expect(book.isDownloaded, true);
    });

    test('未傳入新參數時（既有本機匯入情境），行為與現行完全一致', () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '本機書'};
        }
        return null;
      });

      final result =
          await service.importFiles(['content://example/local_book.epub']);

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.source, BookSource.local);
      expect(book.remoteServerId, isNull);
      expect(book.remoteBookId, isNull);
      expect(book.remoteDownloadUrl, isNull);
      expect(book.isDownloaded, true);
    });

    // 〔審查 review-issue-2.md Important #1 核實後補上〕上面兩個測試皆用
    // `content://` URI，未涵蓋 OPDS 遠端書架下載佇列（epic-30 Issue 2）
    // 實際會傳入的情境——下載完成後搬移到永久位置的檔案是**一般本機路徑
    // （非 content://）**，`_importSingleFile()` 對這種路徑計算指紋時走
    // `computeBookContentFingerprint()` 的 `Isolate.run()` 分支（見
    // book_content_fingerprint.dart），與 `content://` 分支（走 mock
    // method channel）是完全不同的程式碼路徑，先前完全沒有測試覆蓋過。
    // 本測試直接餵入一個真實存在的本機檔案（不透過 testWidgets，plain
    // `test()` 沒有 fake zone 限制，Isolate.run() 可以正常完成），驗證
    // 欄位持久化與檔案本身確實存活（不是被 _importSingleFile 意外清除或
    // 忽略）。
    test('傳入非 content:// 的一般本機路徑（比照 OPDS 下載佇列實際落地情境）時，指紋計算走 Isolate.run() 分支且正確落地',
        () async {
      await repository.database.insert('remote_servers', {
        'id': 'srv1',
        'name': '家用 NAS',
        'base_url': 'http://192.168.1.100:8080/opds',
        'type': 'opds',
        'allow_insecure': 0,
        'created_at': 1000,
      });

      final remoteBooksDir =
          Directory('${importedBooksDir.path}/remote_books_fixture');
      remoteBooksDir.createSync(recursive: true);
      final localFile = File('${remoteBooksDir.path}/remote_book.epub');
      localFile.writeAsBytesSync([1, 2, 3]);

      mockChannel((call) async {
        if (call.method == 'extractMetadata') {
          return {'title': '遠端書（本機路徑）'};
        }
        return null;
      });

      final result = await service.importFiles(
        [localFile.path],
        source: BookSource.calibreOpds,
        remoteServerId: 'srv1',
        remoteBookIds: {localFile.path: 'remote-book-2'},
        remoteDownloadUrls: {
          localFile.path: 'http://192.168.1.100:8080/opds/download/2.epub',
        },
      );

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.source, BookSource.calibreOpds);
      expect(book.remoteServerId, 'srv1');
      expect(book.remoteBookId, 'remote-book-2');
      expect(book.remoteDownloadUrl,
          'http://192.168.1.100:8080/opds/download/2.epub');
      expect(book.isDownloaded, true);
      // 指紋計算成功（非 null）代表 Isolate.run() 分支確實跑完，不是被
      // _importSingleFile 既有的 try/catch 靜默吞掉降級成 null。
      expect(book.contentFingerprint, isNotNull);
      // _importSingleFile 對一般本機路徑不會另外搬移檔案，filePath 應
      // 原樣沿用傳入的路徑，檔案本身仍存在於原處。
      expect(book.filePath, localFile.path);
      expect(localFile.existsSync(), true);
    });
  });

  group('雲端匯入參數擴充（epic-29 Issue 0）', () {
    test('傳入 source/cloudFileIds 時正確落地', () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '雲端書'};
        }
        return null;
      });

      final result = await service.importFiles(
        ['content://example/cloud_book.epub'],
        source: BookSource.googleDrive,
        cloudFileIds: {'content://example/cloud_book.epub': 'gdrive-file-1'},
      );

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.source, BookSource.googleDrive);
      expect(book.cloudFileId, 'gdrive-file-1');
    });

    test('未傳入 cloudFileIds 時（既有本機/OPDS 匯入情境），行為與現行完全一致', () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '本機書'};
        }
        return null;
      });

      final result =
          await service.importFiles(['content://example/local_book2.epub']);

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.source, BookSource.local);
      expect(book.cloudFileId, isNull);
    });
  });

  group('relinkBook（epic-15-storage-permission Issue 2）', () {
    const oldPdfUri = 'content://example/old/book.pdf';
    const newPdfUri = 'content://example/new/book.pdf';
    const oldEpubUri = 'content://example/old/book.epub';
    const newEpubUri = 'content://example/new/book.epub';

    late List<MethodCall> calls;

    /// 模擬原生端：extractMetadata 回傳 [epubIdentifier]、computeSha256 回傳
    /// [sha256]（null 模擬計算失敗）、持久化授權依 [failPermission] 成功或失敗、
    /// 落地複本依 [failCopy] 成功或失敗。所有呼叫記錄在 [calls]。
    void mockRelinkChannel({
      String? epubIdentifier,
      String? sha256 = 'sha-same',
      bool failPermission = false,
      bool failCopy = false,
    }) {
      calls = [];
      mockChannel((call) async {
        calls.add(call);
        switch (call.method) {
          case 'extractMetadata':
            return {'title': '新選取的檔案', 'identifier': epubIdentifier};
          case 'computeSha256':
            return sha256;
          case 'takePersistableUriPermission':
            if (failPermission) {
              throw PlatformException(code: 'permission_failed');
            }
            return null;
          case 'copyContentUriToFile':
            if (failCopy) throw PlatformException(code: 'copy_failed');
            return null;
        }
        return null;
      });
    }

    bool wasCalled(String method) => calls.any((c) => c.method == method);

    Future<Book> seedBook({
      String id = 'b1',
      BookFileFormat format = BookFileFormat.pdf,
      String filePath = oldPdfUri,
      String? contentFingerprint = 'sha-same',
    }) {
      final time = DateTime.fromMillisecondsSinceEpoch(1000);
      return repository.insertBook(Book(
        id: id,
        title: '原書 $id',
        author: '原作者',
        format: format,
        filePath: filePath,
        source: BookSource.local,
        coverPath: '/covers/$id.png',
        contentFingerprint: contentFingerprint,
        createTime: time,
        lastReadTime: time,
      ));
    }

    /// 驗證前 5 步失敗時的共同保證：沒有持久化授權、沒有落地複本、
    /// 記錄的 filePath 維持原值。
    Future<void> expectUntouched(String bookId, String originalPath) async {
      expect(wasCalled('takePersistableUriPermission'), isFalse);
      expect(wasCalled('copyContentUriToFile'), isFalse);
      expect(importedBooksDir.listSync(), isEmpty);
      expect((await repository.findBookById(bookId))!.filePath, originalPath);
    }

    test('PDF 指紋相同：持久化新 URI 授權後原地更新 filePath，id 不變', () async {
      await seedBook();
      mockRelinkChannel();

      final result = await service.relinkBook('b1', newPdfUri,
          displayName: 'book.pdf');

      expect(result, isA<BookRelinkSuccess>());
      final updated = (result as BookRelinkSuccess).updatedBook;
      expect(updated.id, 'b1');
      expect(updated.filePath, newPdfUri);
      expect((await repository.findBookById('b1'))!.filePath, newPdfUri);
      final permissionCall =
          calls.singleWhere((c) => c.method == 'takePersistableUriPermission');
      expect((permissionCall.arguments as Map)['uri'], newPdfUri);
    });

    test('EPUB 以 extractMetadata 取得的 OPF identifier 比對，與資料庫中的 '
        'identifier 相同時判定為同一本書（回歸：不可改算 SHA-256）', () async {
      await seedBook(
        format: BookFileFormat.epub,
        filePath: oldEpubUri,
        contentFingerprint: 'urn:uuid:same-book',
      );
      mockRelinkChannel(
          epubIdentifier: 'urn:uuid:same-book', sha256: 'sha-would-mismatch');

      final result = await service.relinkBook('b1', newEpubUri);

      expect(result, isA<BookRelinkSuccess>());
      expect(wasCalled('computeSha256'), isFalse);
      final metadataCall =
          calls.singleWhere((c) => c.method == 'extractMetadata');
      expect((metadataCall.arguments as Map)['uri'], newEpubUri);
    });

    test('EPUB 匯入時沒取得 identifier（資料庫存的是 SHA-256），重新連結時讀得到 '
        'identifier：以 SHA-256 再比對一次，判定為同一本書（程式審查 M-3）', () async {
      await seedBook(
        format: BookFileFormat.epub,
        filePath: oldEpubUri,
        contentFingerprint: 'sha-same',
      );
      mockRelinkChannel(epubIdentifier: 'urn:uuid:now-readable');

      final result = await service.relinkBook('b1', newEpubUri);

      expect(result, isA<BookRelinkSuccess>());
      // 原本的指紋保留，不改成 identifier，避免與其他裝置的同步比對不一致。
      expect((await repository.findBookById('b1'))!.contentFingerprint,
          'sha-same');
    });

    test('EPUB identifier 與 SHA-256 都和原書指紋不同時，仍回傳 contentMismatch '
        '（程式審查 M-3）', () async {
      await seedBook(
        format: BookFileFormat.epub,
        filePath: oldEpubUri,
        contentFingerprint: 'urn:uuid:original-book',
      );
      mockRelinkChannel(
          epubIdentifier: 'urn:uuid:another-book', sha256: 'sha-another-book');

      final result = await service.relinkBook('b1', newEpubUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.contentMismatch);
      await expectUntouched('b1', oldEpubUri);
    });

    test('選取的 URI 等於原書自己的 filePath（撤銷後重新授權同一個檔案）時，'
        '不判定為 alreadyInLibrary，正常完成', () async {
      await seedBook();
      mockRelinkChannel();

      final result = await service.relinkBook('b1', oldPdfUri);

      expect(result, isA<BookRelinkSuccess>());
      expect((result as BookRelinkSuccess).updatedBook.filePath, oldPdfUri);
      expect(wasCalled('takePersistableUriPermission'), isTrue);
    });

    test('格式不同回傳 formatMismatch，不持久化、不落地、不改記錄', () async {
      await seedBook(format: BookFileFormat.epub, filePath: oldEpubUri);
      mockRelinkChannel();

      final result = await service.relinkBook('b1', newPdfUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.formatMismatch);
      await expectUntouched('b1', oldEpubUri);
    });

    test('新 URI 已是另一本書的來源時回傳 alreadyInLibrary，不持久化、不落地、'
        '不改記錄', () async {
      await seedBook();
      await seedBook(id: 'b2', filePath: newPdfUri);
      mockRelinkChannel();

      final result = await service.relinkBook('b1', newPdfUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.alreadyInLibrary);
      await expectUntouched('b1', oldPdfUri);
    });

    test('內容指紋不同回傳 contentMismatch，不持久化、不落地、不改記錄', () async {
      await seedBook(contentFingerprint: 'sha-original');
      mockRelinkChannel(sha256: 'sha-another-book');

      final result = await service.relinkBook('b1', newPdfUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.contentMismatch);
      await expectUntouched('b1', oldPdfUri);
    });

    test('找不到書籍 id 時回傳 failed', () async {
      mockRelinkChannel();

      final result = await service.relinkBook('no-such-book', newPdfUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.failed);
      expect(calls, isEmpty);
    });

    test('指紋計算失敗（computeSha256 回傳 null）時回傳 failed，不持久化、'
        '不落地、不改記錄', () async {
      await seedBook();
      mockRelinkChannel(sha256: null);

      final result = await service.relinkBook('b1', newPdfUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.failed);
      await expectUntouched('b1', oldPdfUri);
    });

    test('TXT 書籍（filePath 是匯入時合成的落地檔）不支援重新連結，回傳 failed '
        '且不呼叫任何原生方法', () async {
      final localTxt = p.join(importedBooksDir.path, 'synth.txt');
      await seedBook(format: BookFileFormat.txt, filePath: localTxt);
      mockRelinkChannel();

      final result = await service.relinkBook(
          'b1', 'content://example/new/book.txt');

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.failed);
      expect(calls, isEmpty);
      expect((await repository.findBookById('b1'))!.filePath, localTxt);
    });

    test('原書沒有指紋時略過比對，並把新算出的指紋寫回', () async {
      await seedBook(contentFingerprint: null);
      mockRelinkChannel(sha256: 'sha-new');

      final result = await service.relinkBook('b1', newPdfUri);

      expect(result, isA<BookRelinkSuccess>());
      expect((await repository.findBookById('b1'))!.contentFingerprint,
          'sha-new');
    });

    test('驗證通過後持久化授權失敗：改存落地複本，回傳帶本機路徑的成功結果',
        () async {
      await seedBook();
      mockRelinkChannel(failPermission: true);

      final result = await service.relinkBook('b1', newPdfUri);

      final expectedPath = p.join(importedBooksDir.path, 'b1.pdf');
      expect((result as BookRelinkSuccess).updatedBook.filePath, expectedPath);
      expect((await repository.findBookById('b1'))!.filePath, expectedPath);
      final copyCall = calls.singleWhere((c) => c.method == 'copyContentUriToFile');
      expect((copyCall.arguments as Map)['uri'], newPdfUri);
      expect((copyCall.arguments as Map)['destinationPath'], expectedPath);
    });

    test('URI 不含副檔名（媒體庫不透明 ID）時以 displayName 判斷格式，並改存'
        '落地複本', () async {
      await seedBook();
      mockRelinkChannel();
      const opaqueUri =
          'content://com.android.providers.media.documents/document/document%3A42';

      final result = await service.relinkBook('b1', opaqueUri,
          displayName: '原書.pdf');

      expect((result as BookRelinkSuccess).updatedBook.filePath,
          p.join(importedBooksDir.path, 'b1.pdf'));
      expect(wasCalled('copyContentUriToFile'), isTrue);
    });

    test('持久化授權與落地複本都失敗時回傳 failed，記錄不變', () async {
      await seedBook();
      mockRelinkChannel(failPermission: true, failCopy: true);

      final result = await service.relinkBook('b1', newPdfUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.failed);
      expect((await repository.findBookById('b1'))!.filePath, oldPdfUri);
    });

    test('以 findBookById 的最新記錄為基礎：閱讀位置、書名、封面、作者全部保留',
        () async {
      final seeded = await seedBook();
      // 模擬匯入之後使用者讀過這本書，閱讀位置寫回資料庫。
      await repository.updateBook(
          seeded.copyWith(progress: 0.42, pdfPageIndex: 17));
      mockRelinkChannel();

      await service.relinkBook('b1', newPdfUri);

      final stored = (await repository.findBookById('b1'))!;
      expect(stored.filePath, newPdfUri);
      expect(stored.progress, 0.42);
      expect(stored.pdfPageIndex, 17);
      expect(stored.title, '原書 b1');
      expect(stored.author, '原作者');
      expect(stored.coverPath, '/covers/b1.png');
    });
  });
}

/// 解碼 PNG bytes 並取出 (x, y) 位置的像素顏色。用途與寫法比照
/// txt_cover_generator_test.dart 的同名 private helper（各測試檔自成一體，
/// 不跨檔案共用這個小型私有函式）。
Future<ui.Color> _pixelColor(Uint8List pngBytes, int x, int y) async {
  final codec = await ui.instantiateImageCodec(pngBytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = byteData!.buffer.asUint8List();
  final offset = (y * image.width + x) * 4;
  return ui.Color.fromARGB(
    bytes[offset + 3],
    bytes[offset],
    bytes[offset + 1],
    bytes[offset + 2],
  );
}

/// 供上方 I1 修正測試使用：固定回傳 [_value] 的 `AppThemePreferences` 子類別，
/// 用來證明 `BookImportServiceImpl` 真的把建構子收到的 `themePreferences`
/// 存起來使用，而不是忽略參數、內部自行改建構一個預設實例（後者剛好也會
/// 讀到同一份全域 `SharedPreferences` 模擬狀態，單純用
/// `SharedPreferences.setMockInitialValues()` 測不出兩者差異）。
class _FixedEinkModePreferences extends AppThemePreferences {
  _FixedEinkModePreferences(this._value);
  final bool _value;

  @override
  Future<bool> loadEinkMode() async => _value;
}

