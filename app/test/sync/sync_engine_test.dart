import 'dart:convert';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_engine.dart';
import 'package:elinkbook/sync/sync_metadata_repository.dart';
import 'package:elinkbook/sync/sync_models.dart';
import 'package:elinkbook/reader/highlight_style.dart';

Book _testBook(String id, {String? contentFingerprint}) {
  return Book(
    id: id,
    title: '測試書',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    contentFingerprint: contentFingerprint,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  late FlutterSecureStoragePlatform originalPlatform;
  late SqliteLibraryRepository libraryRepository;
  late BookmarksRepository bookmarksRepository;
  late SyncAccountRepository accountRepository;
  late SyncMetadataRepository metadataRepository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    bookmarksRepository = BookmarksRepository(libraryRepository.database);
    metadataRepository = SyncMetadataRepository(libraryRepository.database);

    SharedPreferences.setMockInitialValues({});
    originalPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
    accountRepository = SyncAccountRepository();
    await accountRepository.saveBaseUrl('http://127.0.0.1:8090');
    await accountRepository.saveCredentials(
      authToken: 'test-token',
      userId: 'user-1',
      email: 'reader@example.com',
    );
  });

  tearDown(() async {
    await libraryRepository.close();
    FlutterSecureStoragePlatform.instance = originalPlatform;
  });

  test('未登入時 runCheckpoint 直接早退，不發出任何網路請求', () async {
    await accountRepository.clearCredentials();
    var requestSent = false;
    final mockClient = MockClient((request) async {
      requestSent = true;
      return http.Response('{}', 200);
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    expect(requestSent, isFalse);
  });

  test('有指紋的書籍新增一筆書籤：推送 create（remoteId 未知），成功後寫入 sync_remote_ids',
      () async {
    await libraryRepository.insertBook(_testBook('b1', contentFingerprint: 'fp-1'));
    await bookmarksRepository.insert(
      const Bookmark(id: 'bm1', bookId: 'b1', name: '第一章', progression: 0.1),
    );

    Map<String, dynamic>? capturedRequest;
    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/batch') {
        expect(request.headers['Authorization'], 'test-token');
        capturedRequest = jsonDecode(request.body) as Map<String, dynamic>;
        final subRequests = capturedRequest!['requests'] as List;
        expect(subRequests, hasLength(1));
        expect(subRequests.single['method'], 'POST');
        return http.Response(
          jsonEncode([
            {
              'status': 200,
              'body': {
                'id': 'pb-created-1',
                'client_id': 'bm1',
                'updated': '2026-08-03 00:00:00.000Z',
              },
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'items': [], 'page': 1, 'perPage': 1000, 'totalItems': 0}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    final pushBody =
        (capturedRequest!['requests'] as List).single['body'] as Map<String, dynamic>;
    expect(pushBody['user'], 'user-1');
    expect(pushBody['client_id'], 'bm1');
    expect(pushBody['book_fingerprint'], 'fp-1');
    expect(pushBody['name'], '第一章');

    expect(
      await metadataRepository.loadRemoteIds(SyncCollection.bookmarks),
      {'bm1': 'pb-created-1'},
    );
  });

  test('書籍尚無指紋（content_fingerprint 為 null）時，即時補算並回填後才推送', () async {
    final book = Book(
      id: 'b2',
      title: '測試書',
      format: BookFileFormat.pdf,
      filePath: 'test/fixtures/sample.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await libraryRepository.insertBook(book);
    final highlightsRepository = HighlightsRepository(libraryRepository.database);
    await highlightsRepository.insert(
      const Highlight(id: 'h1', bookId: 'b2', style: HighlightStyle.underline, pdfPageIndex: 3),
    );

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/batch') {
        return http.Response(
          jsonEncode([
            {'status': 200, 'body': {'id': 'pb-h1'}},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'items': [], 'page': 1, 'perPage': 1000, 'totalItems': 0}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    final bookRows = await libraryRepository.database
        .query('books', where: 'id = ?', whereArgs: ['b2']);
    expect(bookRows.single['content_fingerprint'], isNotNull);
  });

  test('推送批次失敗（HTTP 錯誤）時，不更新 lastPushCompletedAt，也不寫入 sync_remote_ids',
      () async {
    await libraryRepository.insertBook(_testBook('b3', contentFingerprint: 'fp-3'));
    await bookmarksRepository.insert(
      const Bookmark(id: 'bm3', bookId: 'b3', name: 'X', progression: 0.1),
    );

    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'Something went wrong.'}),
        500,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    await engine.runCheckpoint();

    expect(await metadataRepository.loadLastPushCompletedAt(), isNull);
    expect(await metadataRepository.loadRemoteIds(SyncCollection.bookmarks), isEmpty);
  });
}
