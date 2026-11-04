import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_content_fingerprint.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/models/book.dart';
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
  late Directory tempDir;
  late BookImportServiceImpl service;

  setUp(() async {
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    tempDir = Directory.systemTemp.createTempSync('detect_test_');
    service = BookImportServiceImpl(
      repository: repository,
    );
  });

  tearDown(() async {
    await repository.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, handler);
  }

  Book createTestBook({
    required String id,
    required String title,
    String? author,
    required BookFileFormat format,
    required String filePath,
    String? contentFingerprint,
  }) {
    return Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: filePath,
      source: BookSource.local,
      contentFingerprint: contentFingerprint,
      groupName: BookGroup.uncategorized,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  group('BookImportService.detectBookUpdate', () {
    test('書庫為空時回傳 DetectedNewBook', () async {
      final res = await service.detectBookUpdate('content://test/book.epub');
      expect(res, isA<DetectedNewBook>());
    });

    test('副檔名未知時回傳 DetectedUnsupported', () async {
      final res = await service.detectBookUpdate('content://test/unknown.xyz');
      expect(res, isA<DetectedUnsupported>());
    });

    test('EPUB identifier 相同、整檔雜湊不同 → DetectedUpdate(high)', () async {
      final oldFile = File(p.join(tempDir.path, 'old.epub'))..writeAsStringSync('old-content');
      final book = createTestBook(
        id: 'b1',
        title: '舊版書名',
        author: '作者',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        contentFingerprint: 'urn:isbn:9780001',
      );
      await repository.insertBook(book);

      mockChannel((call) async {
        if (call.method == 'extractMetadata') {
          return {
            'title': '新版書名',
            'author': '作者',
            'identifier': 'urn:isbn:9780001',
          };
        }
        if (call.method == 'computeSha256') {
          return 'hash-new-content';
        }
        return null;
      });

      final newUri = 'content://downloads/new.epub';
      final res = await service.detectBookUpdate(newUri);

      expect(res, isA<DetectedUpdate>());
      final update = res as DetectedUpdate;
      expect(update.candidate.confidence, UpdateConfidence.high);
      expect(update.candidate.candidateBooks.first.id, 'b1');
      expect(update.candidate.unreadableCandidateBookIds, isEmpty);
    });

    test('EPUB identifier 相同、整檔雜湊相同 → DetectedDuplicate', () async {
      final oldFile = File(p.join(tempDir.path, 'old.epub'))..writeAsStringSync('same-content');
      final book = createTestBook(
        id: 'b1',
        title: '同一本書',
        author: '作者',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        contentFingerprint: 'urn:isbn:9780001',
      );
      await repository.insertBook(book);

      mockChannel((call) async {
        if (call.method == 'extractMetadata') {
          return {
            'title': '同一本書',
            'author': '作者',
            'identifier': 'urn:isbn:9780001',
          };
        }
        if (call.method == 'computeSha256') {
          // 模擬新檔雜湊等於舊檔雜湊
          return 'sha256-same-content';
        }
        return null;
      });

      // 由於 oldFile 是本機檔案，computeBookContentFingerprint 會計算其 SHA-256
      // 我們讓 newUri 的 computeSha256 回傳與 oldFile 相同的 SHA
      final actualOldHash = await computeBookContentFingerprint(oldFile.path, BookFileFormat.epub);
      mockChannel((call) async {
        if (call.method == 'extractMetadata') {
          return {'title': '同一本書', 'author': '作者', 'identifier': 'urn:isbn:9780001'};
        }
        if (call.method == 'computeSha256') {
          return actualOldHash;
        }
        return null;
      });

      final res = await service.detectBookUpdate('content://downloads/same.epub');
      expect(res, isA<DetectedDuplicate>());
      expect((res as DetectedDuplicate).existingBook.id, 'b1');
    });

    test('書名＋作者相同、identifier 不同 → DetectedUpdate(suspected)', () async {
      final oldFile = File(p.join(tempDir.path, 'old.epub'))..writeAsStringSync('old-content');
      final book = createTestBook(
        id: 'b2',
        title: '百年孤寂',
        author: '馬奎斯',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        contentFingerprint: 'urn:uuid:old-id',
      );
      await repository.insertBook(book);

      mockChannel((call) async {
        if (call.method == 'extractMetadata') {
          return {
            'title': '百年孤寂',
            'author': '馬奎斯',
            'identifier': 'urn:uuid:new-id',
          };
        }
        if (call.method == 'computeSha256') {
          return 'hash-diff';
        }
        return null;
      });

      final res = await service.detectBookUpdate('content://downloads/update.epub');
      expect(res, isA<DetectedUpdate>());
      final update = res as DetectedUpdate;
      expect(update.candidate.confidence, UpdateConfidence.suspected);
      expect(update.candidate.candidateBooks.first.id, 'b2');
    });

    test('格式先決：PDF 新檔遇到書庫同名同作者 EPUB 回傳 DetectedNewBook', () async {
      final book = createTestBook(
        id: 'b3',
        title: '三體',
        author: '劉慈欣',
        format: BookFileFormat.epub,
        filePath: '/data/b3.epub',
      );
      await repository.insertBook(book);

      final res = await service.detectBookUpdate(
        'content://downloads/three_body.pdf',
        displayName: '三體.pdf',
      );
      expect(res, isA<DetectedNewBook>());
    });

    test('格式先決：TXT 新檔遇到同名 MD 回傳 DetectedNewBook（不互通）', () async {
      final book = createTestBook(
        id: 'b4',
        title: '筆記',
        format: BookFileFormat.md,
        filePath: '/data/b4.md',
      );
      await repository.insertBook(book);

      final res = await service.detectBookUpdate(
        'content://downloads/note.txt',
        displayName: '筆記.txt',
      );
      expect(res, isA<DetectedNewBook>());
    });

    test('作者為空時不進入第二層比對', () async {
      final oldFile = File(p.join(tempDir.path, 'no_author.epub'))..writeAsStringSync('content');
      final book = createTestBook(
        id: 'b5',
        title: '民間故事',
        author: null,
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        contentFingerprint: 'urn:id:1',
      );
      await repository.insertBook(book);

      mockChannel((call) async {
        if (call.method == 'extractMetadata') {
          return {
            'title': '民間故事',
            'author': '   ', // 空白作者
            'identifier': 'urn:id:2',
          };
        }
        return null;
      });

      final res = await service.detectBookUpdate('content://downloads/story.epub');
      expect(res, isA<DetectedNewBook>());
    });

    test('書名與作者正規化：全形半形、大小寫、空白忽略差異', () async {
      final oldFile = File(p.join(tempDir.path, 'norm.epub'))..writeAsStringSync('c1');
      final book = createTestBook(
        id: 'b6',
        title: 'Hello 世界',
        author: 'Alice 123',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        contentFingerprint: 'urn:id:6',
      );
      await repository.insertBook(book);

      mockChannel((call) async {
        if (call.method == 'extractMetadata') {
          return {
            'title': '  ｈｅｌｌｏ 世界  ',
            'author': 'alice　１２３', // 全形空白與全形數字
            'identifier': 'urn:id:other',
          };
        }
        if (call.method == 'computeSha256') return 'hash-norm';
        return null;
      });

      final res = await service.detectBookUpdate('content://downloads/norm.epub');
      expect(res, isA<DetectedUpdate>());
      expect((res as DetectedUpdate).candidate.candidateBooks.first.id, 'b6');
    });

    test('多候選排序：識別碼命中者排第一，且 confidence == high', () async {
      final f1 = File(p.join(tempDir.path, 'f1.epub'))..writeAsStringSync('f1');
      final f2 = File(p.join(tempDir.path, 'f2.epub'))..writeAsStringSync('f2');
      final bAuthorMatch = createTestBook(
        id: 'b-author',
        title: '天龍八部',
        author: '金庸',
        format: BookFileFormat.epub,
        filePath: f1.path,
        contentFingerprint: 'urn:isbn:0001',
      );
      final bIdMatch = createTestBook(
        id: 'b-id',
        title: '天龍八部（修訂版）',
        author: '金庸新',
        format: BookFileFormat.epub,
        filePath: f2.path,
        contentFingerprint: 'urn:isbn:9999',
      );
      await repository.insertBook(bAuthorMatch);
      await repository.insertBook(bIdMatch);

      mockChannel((call) async {
        if (call.method == 'extractMetadata') {
          return {
            'title': '天龍八部',
            'author': '金庸',
            'identifier': 'urn:isbn:9999', // 命中 b-id
          };
        }
        if (call.method == 'computeSha256') return 'new-hash';
        return null;
      });

      final res = await service.detectBookUpdate('content://downloads/tlbb.epub');
      expect(res, isA<DetectedUpdate>());
      final update = res as DetectedUpdate;
      expect(update.candidate.confidence, UpdateConfidence.high);
      expect(update.candidate.candidateBooks.map((b) => b.id).toList(), ['b-id', 'b-author']);
    });

    test('PDF 格式不發送 extractMetadata 原生呼叫（審查 I-3）', () async {
      final book = createTestBook(
        id: 'b-pdf',
        title: '文檔',
        format: BookFileFormat.pdf,
        filePath: '/data/doc.pdf',
      );
      await repository.insertBook(book);

      var extractMetadataCalled = false;
      mockChannel((call) async {
        if (call.method == 'extractMetadata') extractMetadataCalled = true;
        return null;
      });

      final res = await service.detectBookUpdate(
        'content://downloads/doc.pdf',
        displayName: '文檔.pdf',
      );
      expect(extractMetadataCalled, isFalse);
      expect(res, isA<DetectedNewBook>());
    });

    test('舊檔不存在時標記至 unreadableCandidateBookIds', () async {
      final book = createTestBook(
        id: 'b-lost',
        title: '消失的檔案',
        author: '探險家',
        format: BookFileFormat.epub,
        filePath: p.join(tempDir.path, 'non_existent.epub'),
        contentFingerprint: 'urn:lost:1',
      );
      await repository.insertBook(book);

      mockChannel((call) async {
        if (call.method == 'extractMetadata') {
          return {'title': '消失的檔案', 'author': '探險家', 'identifier': 'urn:lost:1'};
        }
        if (call.method == 'computeSha256') return 'new-hash';
        return null;
      });

      final res = await service.detectBookUpdate('content://downloads/recovered.epub');
      expect(res, isA<DetectedUpdate>());
      final update = res as DetectedUpdate;
      expect(update.candidate.unreadableCandidateBookIds, contains('b-lost'));
    });

    test('MD 格式比對 contentFingerprint 判定重複或更新版', () async {
      final mdFile = File(p.join(tempDir.path, 'note.md'))
        ..writeAsStringSync('---\ntitle: 隨筆\nauthor: 我\n---\n內文');
      final mdHash =
          await computeBookContentFingerprint(mdFile.path, BookFileFormat.md);
      final book = createTestBook(
        id: 'b-md',
        title: '隨筆',
        author: '我',
        format: BookFileFormat.md,
        filePath: '/imported/b-md.md',
        contentFingerprint: mdHash,
      );
      await repository.insertBook(book);

      // 指紋相同 → DetectedDuplicate
      final resDup = await service.detectBookUpdate(mdFile.path);
      expect(resDup, isA<DetectedDuplicate>());
      expect((resDup as DetectedDuplicate).existingBook.id, 'b-md');

      // 內容不同（指紋不同）→ DetectedUpdate
      final mdFile2 = File(p.join(tempDir.path, 'note2.md'))
        ..writeAsStringSync('---\ntitle: 隨筆\nauthor: 我\n---\n新版內文');
      final resDiff = await service.detectBookUpdate(mdFile2.path);
      expect(resDiff, isA<DetectedUpdate>());
    });

    test('前置短路：書庫無同格式書籍時，不呼叫任何中繼資料或雜湊原生通道', () async {
      final book = createTestBook(
        id: 'b-epub',
        title: '小說',
        format: BookFileFormat.epub,
        filePath: '/data/b.epub',
      );
      await repository.insertBook(book);

      var channelCalled = false;
      mockChannel((call) async {
        channelCalled = true;
        return null;
      });

      final res = await service.detectBookUpdate(
        'content://downloads/comic.cbz',
        displayName: 'comic.cbz',
      );
      expect(res, isA<DetectedNewBook>());
      expect(channelCalled, isFalse);
    });

    test('無身份命中時不算整檔雜湊', () async {
      final oldFile = File(p.join(tempDir.path, 'novel.epub'))..writeAsStringSync('c');
      final book = createTestBook(
        id: 'b-novel',
        title: '三國演義',
        author: '羅貫中',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        contentFingerprint: 'urn:sanguo',
      );
      await repository.insertBook(book);

      var computeSha256Called = false;
      mockChannel((call) async {
        if (call.method == 'extractMetadata') {
          return {
            'title': '水滸傳',
            'author': '施耐庵',
            'identifier': 'urn:shuihu',
          };
        }
        if (call.method == 'computeSha256') {
          computeSha256Called = true;
          return 'sha';
        }
        return null;
      });

      final res = await service.detectBookUpdate('content://downloads/shuihu.epub');
      expect(res, isA<DetectedNewBook>());
      expect(computeSha256Called, isFalse);
    });

    test('extractMetadata 拋 PlatformException 偵測不拋錯，降級為 DetectedNewBook', () async {
      final book = createTestBook(
        id: 'b7',
        title: '書',
        author: '作者',
        format: BookFileFormat.epub,
        filePath: '/data/b7.epub',
        contentFingerprint: 'urn:id:7',
      );
      await repository.insertBook(book);

      mockChannel((call) async {
        if (call.method == 'extractMetadata') {
          throw PlatformException(code: 'ERROR', message: '無法解析');
        }
        return null;
      });

      final res = await service.detectBookUpdate('content://downloads/corrupt.epub');
      expect(res, isA<DetectedNewBook>());
    });

    test('偵測能力完全不寫入資料庫', () async {
      final book = createTestBook(
        id: 'b-readonly',
        title: '唯讀書本',
        author: '作者',
        format: BookFileFormat.epub,
        filePath: '/data/b.epub',
        contentFingerprint: 'urn:readonly',
      );
      await repository.insertBook(book);

      mockChannel((call) async {
        if (call.method == 'extractMetadata') {
          return {'title': '唯讀書本', 'author': '作者', 'identifier': 'urn:readonly'};
        }
        if (call.method == 'computeSha256') return 'diff';
        return null;
      });

      await service.detectBookUpdate('content://downloads/test.epub');
      final books = await repository.listBooks();
      expect(books.length, 1);
      expect(books.first.id, 'b-readonly');
    });
  });
}
