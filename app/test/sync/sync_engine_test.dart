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

  test('下載端把遠端新增的書籤正確合併進本機（書籍已匯入、指紋對得上）', () async {
    await libraryRepository.insertBook(_testBook('b4', contentFingerprint: 'fp-4'));

    final mockClient = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/collections/sync_bookmarks/records') {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'pb-remote-1',
                'client_id': 'bm-remote-1',
                'book_fingerprint': 'fp-4',
                'deleted_at': 0,
                'name': '遠端書籤',
                'epub_locator_json': '',
                'progression': 0.3,
                'pdf_page_index': 0,
                'updated': '2026-08-03 00:00:00.000Z',
              },
            ],
            'page': 1,
            'perPage': 1000,
            'totalItems': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/batch') {
        return http.Response(jsonEncode([]), 200,
            headers: {'content-type': 'application/json'});
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

    final bookmarks = await bookmarksRepository.listByBook('b4');
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.id, 'bm-remote-1');
    expect(bookmarks.single.name, '遠端書籤');
    expect(
      await metadataRepository.loadPulledCursor(SyncCollection.bookmarks),
      '2026-08-03 00:00:00.000Z',
    );
    expect(
      await metadataRepository.loadRemoteIds(SyncCollection.bookmarks),
      {'bm-remote-1': 'pb-remote-1'},
    );
    expect(await metadataRepository.loadLastPushCompletedAt(), isNotNull);
  });

  test('下載端遇到 book_fingerprint 查無對應本機書籍時，暫緩合併、寫入待處理佇列，不建立空殼書籍',
      () async {
    final mockClient = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/collections/sync_bookmarks/records') {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'pb-remote-2',
                'client_id': 'bm-remote-2',
                'book_fingerprint': 'fp-unimported',
                'deleted_at': 0,
                'name': '尚未匯入書籍的書籤',
                'epub_locator_json': '',
                'progression': 0.1,
                'pdf_page_index': 0,
                'updated': '2026-08-03 00:00:00.000Z',
              },
            ],
            'page': 1,
            'perPage': 1000,
            'totalItems': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/batch') {
        return http.Response(jsonEncode([]), 200,
            headers: {'content-type': 'application/json'});
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

    final booksCount =
        (await libraryRepository.database.query('books')).length;
    expect(booksCount, 0, reason: '不應為了承接同步資料而建立空殼書籍');

    final pending = await metadataRepository.listPendingRecords();
    expect(pending, hasLength(1));
    expect(pending.single.clientId, 'bm-remote-2');
    expect(pending.single.bookFingerprint, 'fp-unimported');
  });

  test('待處理佇列中的紀錄，在對應書籍匯入（指紋比對上）後的下一次 checkpoint 正確解析落地',
      () async {
    await metadataRepository.savePendingRecord(
      collection: SyncCollection.bookmarks,
      clientId: 'bm-pending-1',
      bookFingerprint: 'fp-later',
      remoteId: 'pb-pending-1',
      deletedAt: null,
      fields: const {
        'name': '延遲解析的書籤',
        'epub_locator_json': null,
        'progression': 0.5,
        'pdf_page_index': null,
      },
    );
    await libraryRepository.insertBook(_testBook('b5', contentFingerprint: 'fp-later'));

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/batch') {
        return http.Response(jsonEncode([]), 200,
            headers: {'content-type': 'application/json'});
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

    final bookmarks = await bookmarksRepository.listByBook('b5');
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.id, 'bm-pending-1');
    expect(bookmarks.single.name, '延遲解析的書籤');
    expect(await metadataRepository.listPendingRecords(), isEmpty);
  });

  test('本機墓碑清理：checkpoint 成功完成後，超過 30 天的軟刪除紀錄被真正清除', () async {
    await libraryRepository.insertBook(_testBook('b6', contentFingerprint: 'fp-6'));
    await bookmarksRepository.insert(
      const Bookmark(id: 'bm-old', bookId: 'b6', name: 'X', progression: 0.1),
    );
    await bookmarksRepository.delete('bm-old');
    final old31DaysAgo =
        DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch;
    await libraryRepository.database.update(
      'bookmarks',
      {'deleted_at': old31DaysAgo, 'updated_at': old31DaysAgo},
      where: 'id = ?',
      whereArgs: ['bm-old'],
    );

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/batch') {
        // 推送階段會把軟刪除的 bm-old（updated_at 舊值、lastPushCompletedAt
        // 為 null 所以算 dirty）送進 batch，mock 回應長度需與操作筆數一致。
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final count = (body['requests'] as List).length;
        return http.Response(
          jsonEncode([
            for (var i = 0; i < count; i++)
              {
                'status': 200,
                'body': {'id': 'pb-$i', 'client_id': 'bm-old'},
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

    final rawRows = await libraryRepository.database
        .query('bookmarks', where: 'id = ?', whereArgs: ['bm-old']);
    expect(rawRows, isEmpty, reason: '超過 30 天的墓碑應被真正 DELETE');
  });

  test(
      '下載階段失敗（HTTP 錯誤）時，即使推送階段已成功，也不執行墓碑清理、'
      '不寫入 lastPushCompletedAt／任何下載游標', () async {
    await libraryRepository.insertBook(_testBook('b7', contentFingerprint: 'fp-7'));
    await bookmarksRepository.insert(
      const Bookmark(id: 'bm-should-survive', bookId: 'b7', name: 'X', progression: 0.1),
    );
    await bookmarksRepository.delete('bm-should-survive');
    final old31DaysAgo =
        DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch;
    await libraryRepository.database.update(
      'bookmarks',
      {'deleted_at': old31DaysAgo, 'updated_at': old31DaysAgo},
      where: 'id = ?',
      whereArgs: ['bm-should-survive'],
    );

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/batch') {
        return http.Response(
          jsonEncode([
            {
              'status': 200,
              'body': {'id': 'pb-should-survive', 'client_id': 'bm-should-survive'},
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
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

    final rawRows = await libraryRepository.database
        .query('bookmarks', where: 'id = ?', whereArgs: ['bm-should-survive']);
    expect(rawRows, hasLength(1), reason: '下載失敗時不應執行墓碑清理');

    expect(await metadataRepository.loadLastPushCompletedAt(), isNull);
    expect(await metadataRepository.loadPulledCursor(SyncCollection.bookmarks), isNull);
    expect(
      await metadataRepository.loadRemoteIds(SyncCollection.bookmarks),
      {'bm-should-survive': 'pb-should-survive'},
    );
  });
}
