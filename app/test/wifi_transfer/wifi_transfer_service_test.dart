import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/book_import_service.dart';
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
  String? contentFingerprint,
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return Book(
    id: id,
    title: title,
    format: format,
    filePath: filePath,
    source: BookSource.local,
    isDownloaded: isDownloaded,
    contentFingerprint: contentFingerprint,
    createTime: now,
    lastReadTime: now,
  );
}

// 以 Future.error 直接模擬匯入失敗，避免 Completer 同步 completeError 的
// 未處理例外空窗（見上方說明）。
class _ThrowingImportService implements BookImportService {
  ImportCallRecord? lastImportCall;
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
  }) {
    lastImportCall = ImportCallRecord(
      uris: uris,
      displayNames: displayNames,
      source: source,
      remoteServerId: remoteServerId,
      remoteBookIds: remoteBookIds,
      remoteDownloadUrls: remoteDownloadUrls,
      cloudFileIds: cloudFileIds,
    );
    return Future.error(StateError('模擬匯入失敗'));
  }

  @override
  Future<ImportResult> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  }) =>
      Future.value(const ImportResult(importedBooks: []));

  // epic-15-storage-permission Issue 2：介面新增方法，本測試不使用。
  @override
  Future<BookRelinkResult> relinkBook(
    String bookId,
    String newUri, {
    String? displayName,
  }) =>
      Future.value(const BookRelinkFailure(BookRelinkFailureReason.failed));
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

  group('handleUploadedFile', () {
    test('沒有重複、匯入成功：回傳 imported，落地檔案不會被刪除，displayNames '
        '正確帶入原始檔名', () async {
      final fingerprintComputer = FakeFingerprintComputer();
      final importService = FakeBookImportService()
        ..pendingCompleter = (Completer<ImportResult>()
          ..complete(ImportResult(
            importedBooks: [_bookWith(id: 'new-1', filePath: '/tmp/landed.epub')],
          )));
      final deleteCalls = <String>[];
      final service = WifiTransferService(
        libraryRepository: FakeLibraryRepository(),
        importService: importService,
        computeFingerprint: fingerprintComputer.call,
        materializeContentUri: (uri) async => null,
        deleteFile: (path) async => deleteCalls.add(path),
      );

      final result = await service.handleUploadedFile(
        landedPath: '/tmp/landed.epub',
        originalFileName: '我的書.epub',
        format: BookFileFormat.epub,
      );

      expect(result.outcome, UploadOutcome.imported);
      expect(result.originalFileName, '我的書.epub');
      expect(deleteCalls, isEmpty);
      expect(importService.lastImportCall!.uris, ['/tmp/landed.epub']);
      expect(importService.lastImportCall!.displayNames, ['我的書.epub']);
    });

    test('內容指紋命中圖書庫既有書籍：回傳 duplicateSkipped，刪除落地檔案，'
        '且不呼叫 importFiles', () async {
      final fingerprintComputer = FakeFingerprintComputer()
        ..nextFingerprint = 'shared-fingerprint';
      final existing = _bookWith(
        id: 'existing-1',
        filePath: '/tmp/existing.epub',
        contentFingerprint: 'shared-fingerprint',
      );
      final importService = FakeBookImportService();
      final deleteCalls = <String>[];
      final service = WifiTransferService(
        libraryRepository: FakeLibraryRepository(initialBooks: [existing]),
        importService: importService,
        computeFingerprint: fingerprintComputer.call,
        materializeContentUri: (uri) async => null,
        deleteFile: (path) async => deleteCalls.add(path),
      );

      final result = await service.handleUploadedFile(
        landedPath: '/tmp/landed.epub',
        originalFileName: '重複的書.epub',
        format: BookFileFormat.epub,
      );

      expect(result.outcome, UploadOutcome.duplicateSkipped);
      expect(deleteCalls, ['/tmp/landed.epub']);
      expect(importService.lastImportCall, isNull);
    });

    test('importFiles 回傳空清單（模擬損毀/空內容檔案）：回傳 failed，刪除落地檔案',
        () async {
      final fingerprintComputer = FakeFingerprintComputer();
      final deleteCalls = <String>[];
      final service = WifiTransferService(
        libraryRepository: FakeLibraryRepository(),
        importService: FakeBookImportService(), // 預設回傳空清單
        computeFingerprint: fingerprintComputer.call,
        materializeContentUri: (uri) async => null,
        deleteFile: (path) async => deleteCalls.add(path),
      );

      final result = await service.handleUploadedFile(
        landedPath: '/tmp/landed.pdf',
        originalFileName: '損毀的書.pdf',
        format: BookFileFormat.pdf,
      );

      expect(result.outcome, UploadOutcome.failed);
      expect(deleteCalls, ['/tmp/landed.pdf']);
    });

    test('importFiles 拋出例外：回傳 failed，刪除落地檔案，例外不會冒出中斷上傳請求',
        () async {
      final fingerprintComputer = FakeFingerprintComputer();
      // 直接以 Future.error 模擬失敗，避免 Completer 同步 completeError 與
      // 錯誤處理器掛載之間的空窗被測試 zone 視為未處理例外。
      final importService = _ThrowingImportService();
      final deleteCalls = <String>[];
      final service = WifiTransferService(
        libraryRepository: FakeLibraryRepository(),
        importService: importService,
        computeFingerprint: fingerprintComputer.call,
        materializeContentUri: (uri) async => null,
        deleteFile: (path) async => deleteCalls.add(path),
      );

      final result = await service.handleUploadedFile(
        landedPath: '/tmp/landed.epub',
        originalFileName: '例外的書.epub',
        format: BookFileFormat.epub,
      );

      expect(result.outcome, UploadOutcome.failed);
      expect(deleteCalls, ['/tmp/landed.epub']);
    });

    test('computeFingerprint 本身拋出例外：回傳 failed，刪除落地檔案', () async {
      final deleteCalls = <String>[];
      final service = WifiTransferService(
        libraryRepository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        computeFingerprint: (path, format) async =>
            throw StateError('模擬指紋計算失敗'),
        materializeContentUri: (uri) async => null,
        deleteFile: (path) async => deleteCalls.add(path),
      );

      final result = await service.handleUploadedFile(
        landedPath: '/tmp/landed.epub',
        originalFileName: '無法計算指紋的書.epub',
        format: BookFileFormat.epub,
      );

      expect(result.outcome, UploadOutcome.failed);
      expect(deleteCalls, ['/tmp/landed.epub']);
    });

    test(
        'importFiles 拋出例外，且清理落地檔案時 deleteFile 本身也拋出例外：'
        '仍回傳 failed，例外不會冒出（`review-plan-issue-3.md` I-1 回歸測試）',
        () async {
      final fingerprintComputer = FakeFingerprintComputer();
      final importService = _ThrowingImportService();
      final service = WifiTransferService(
        libraryRepository: FakeLibraryRepository(),
        importService: importService,
        computeFingerprint: fingerprintComputer.call,
        materializeContentUri: (uri) async => null,
        deleteFile: (path) async => throw FileSystemException('模擬清理失敗'),
      );

      final result = await service.handleUploadedFile(
        landedPath: '/tmp/landed.epub',
        originalFileName: '清理也失敗的書.epub',
        format: BookFileFormat.epub,
      );

      expect(result.outcome, UploadOutcome.failed);
    });
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
