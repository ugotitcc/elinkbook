import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_service.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_fingerprint_computer.dart';

Book _bookWith({
  required String id,
  required String filePath,
  bool isDownloaded = true,
  BookFileFormat format = BookFileFormat.epub,
  String title = '書名',
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return Book(
    id: id,
    title: title,
    format: format,
    filePath: filePath,
    source: BookSource.local,
    isDownloaded: isDownloaded,
    createTime: now,
    lastReadTime: now,
  );
}

void main() {
  WifiTransferService buildService({
    List<Book> initialBooks = const [],
    Future<String?> Function(String uri)? materializeContentUri,
  }) {
    final fingerprintComputer = FakeFingerprintComputer();
    return WifiTransferService(
      libraryRepository: FakeLibraryRepository(initialBooks: initialBooks),
      importService: FakeBookImportService(),
      computeFingerprint: fingerprintComputer.call,
      materializeContentUri: materializeContentUri ?? (uri) async => null,
      deleteFile: (path) async {},
    );
  }

  test('handleUploadedFile 尚未實作，呼叫時明確拋出 UnimplementedError（Issue 3 填入前的契約）',
      () async {
    final service = buildService();

    await expectLater(
      service.handleUploadedFile(
        landedPath: '/tmp/a.epub',
        originalFileName: 'a.epub',
        format: BookFileFormat.epub,
      ),
      throwsA(isA<UnimplementedError>()),
    );
  });

  group('listDownloadableBooks', () {
    test('只列出 isDownloaded == true 的書，且欄位對應正確', () async {
      final downloaded =
          _bookWith(id: 'b1', filePath: 'test/fixtures/sample.pdf', title: '已下載');
      final notDownloaded = _bookWith(
          id: 'b2', filePath: 'test/fixtures/sample.epub', isDownloaded: false);
      final service = buildService(initialBooks: [downloaded, notDownloaded]);

      final result = await service.listDownloadableBooks();

      expect(result, hasLength(1));
      expect(result.single.id, 'b1');
      expect(result.single.title, '已下載');
      expect(result.single.format, BookFileFormat.epub);
    });

    test('本機路徑且檔案存在：sizeBytes 為真實檔案大小', () async {
      final book = _bookWith(id: 'b1', filePath: 'test/fixtures/sample.pdf');
      final service = buildService(initialBooks: [book]);

      final result = await service.listDownloadableBooks();

      final expectedSize = await File('test/fixtures/sample.pdf').length();
      expect(result.single.sizeBytes, expectedSize);
    });

    test(
        'content:// 來源：sizeBytes 恆為 null，且不觸發 materializeContentUri'
        '（清單階段嚴禁材質化）', () async {
      final calls = <String>[];
      final book = _bookWith(
          id: 'b1', filePath: 'content://com.example.provider/document/42');
      final service = buildService(
        initialBooks: [book],
        materializeContentUri: (uri) async {
          calls.add(uri);
          return '/tmp/should-not-be-called.pdf';
        },
      );

      final result = await service.listDownloadableBooks();

      expect(result.single.sizeBytes, isNull);
      expect(calls, isEmpty);
    });

    test('記錄存在但本機檔案已被外部刪除：sizeBytes 為 null，不拋出例外中斷整個查詢',
        () async {
      final missing =
          _bookWith(id: 'b1', filePath: 'test/fixtures/does_not_exist_book.pdf');
      final present = _bookWith(id: 'b2', filePath: 'test/fixtures/sample.pdf');
      final service = buildService(initialBooks: [missing, present]);

      final result = await service.listDownloadableBooks();

      expect(result, hasLength(2));
      expect(result.firstWhere((b) => b.id == 'b1').sizeBytes, isNull);
      expect(result.firstWhere((b) => b.id == 'b2').sizeBytes, isNotNull);
    });
  });

  group('resolveDownloadSource', () {
    test('找不到書籍：回傳 null（呼叫端回 404）', () async {
      final service = buildService();

      expect(await service.resolveDownloadSource('missing'), isNull);
    });

    test('書籍存在但 isDownloaded == false：回傳 null', () async {
      final book = _bookWith(
          id: 'b1', filePath: 'test/fixtures/sample.pdf', isDownloaded: false);
      final service = buildService(initialBooks: [book]);

      expect(await service.resolveDownloadSource('b1'), isNull);
    });

    test(
        '圖書庫有多本書時，依 bookId 精確比對出正確的那一本（確實呼叫'
        ' findBookById，而非誤用 listBooks() 取第一筆）', () async {
      final first =
          _bookWith(id: 'b1', filePath: 'test/fixtures/sample.epub', title: '第一本');
      final second = _bookWith(
          id: 'b2',
          filePath: 'test/fixtures/sample.pdf',
          format: BookFileFormat.pdf,
          title: '第二本');
      final service = buildService(initialBooks: [first, second]);

      final source = await service.resolveDownloadSource('b2');

      expect(source!.resolvedPath, 'test/fixtures/sample.pdf');
      expect(source.downloadFileName, '第二本.pdf');
    });

    test('本機路徑來源：resolvedPath 為原始 filePath、isTemporaryFile 為 false、'
        '副檔名維持原格式', () async {
      final book = _bookWith(
        id: 'b1',
        filePath: 'test/fixtures/sample.pdf',
        format: BookFileFormat.pdf,
        title: '測試書',
      );
      final service = buildService(initialBooks: [book]);

      final source = await service.resolveDownloadSource('b1');

      expect(source, isNotNull);
      expect(source!.resolvedPath, 'test/fixtures/sample.pdf');
      expect(source.downloadFileName, '測試書.pdf');
      expect(source.isTemporaryFile, isFalse);
    });

    test(
        '本機路徑但檔案已被外部刪除：回傳 null（呼叫端回 404，而非因'
        ' file.length() 拋出 FileSystemException 回 500——審查修正 I-4）',
        () async {
      final book = _bookWith(
          id: 'b1', filePath: 'test/fixtures/does_not_exist_book.pdf');
      final service = buildService(initialBooks: [book]);

      expect(await service.resolveDownloadSource('b1'), isNull);
    });

    test('content:// 來源：呼叫 materializeContentUri 並回傳其結果、'
        'isTemporaryFile 為 true', () async {
      final book = _bookWith(
        id: 'b1',
        filePath: 'content://com.example.provider/document/42',
        title: '測試書',
      );
      final calls = <String>[];
      final service = buildService(
        initialBooks: [book],
        materializeContentUri: (uri) async {
          calls.add(uri);
          return '/tmp/materialized.epub';
        },
      );

      final source = await service.resolveDownloadSource('b1');

      expect(calls, ['content://com.example.provider/document/42']);
      expect(source!.resolvedPath, '/tmp/materialized.epub');
      expect(source.isTemporaryFile, isTrue);
    });

    test('content:// 材質化失敗（回傳 null）：整體回傳 null', () async {
      final book = _bookWith(
          id: 'b1', filePath: 'content://com.example.provider/document/42');
      final service = buildService(initialBooks: [book]);

      expect(await service.resolveDownloadSource('b1'), isNull);
    });

    test('TXT 來源書籍：downloadFileName 誠實改寫為 .epub', () async {
      final book = _bookWith(
        id: 'b1',
        filePath: 'test/fixtures/sample.pdf',
        format: BookFileFormat.txt,
        title: '我的筆記',
      );
      final service = buildService(initialBooks: [book]);

      final source = await service.resolveDownloadSource('b1');

      expect(source!.downloadFileName, '我的筆記.epub');
    });

    test('MD 來源書籍：downloadFileName 誠實改寫為 .epub', () async {
      final book = _bookWith(
        id: 'b1',
        filePath: 'test/fixtures/sample.pdf',
        format: BookFileFormat.md,
        title: '我的筆記',
      );
      final service = buildService(initialBooks: [book]);

      final source = await service.resolveDownloadSource('b1');

      expect(source!.downloadFileName, '我的筆記.epub');
    });
  });
}
