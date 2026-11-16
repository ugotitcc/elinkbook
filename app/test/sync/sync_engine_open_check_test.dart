import 'dart:convert';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_engine.dart';
import 'package:elinkbook/sync/sync_metadata_repository.dart';
import 'package:elinkbook/sync/sync_reading_position.dart';

import 'pocketbase_test_helpers.dart';

/// 重現測試：開書時沒有檢查雲端閱讀位置（PRD FR-19、方案 A）。
///
/// 症狀：新機器設定同步並同步過一次後，開啟已同步過的書，進書時不會詢問
/// 「用本機還是雲端」，要等離開該書、checkpoint 跑推送階段才會問。
/// 根因：衝突詢問只存在於 `SyncEngine._syncReadingPositions()`（推送階段），
/// 而 checkpoint 只在「App 背景化／離開閱讀畫面／每 5 分鐘」觸發，開書當下不觸發。
///
/// 這裡用 `SyncEngine.checkReadingPositionOnOpen(bookId)` 描述期望的開書行為。
Book _book(
  String id, {
  required String fingerprint,
  String? syncedServerUpdatedAt,
  double progress = 0,
  int? positionUpdatedAt,
}) {
  return Book(
    id: id,
    title: '測試書',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    contentFingerprint: fingerprint,
    positionUpdatedAt: positionUpdatedAt,
    positionSyncedServerUpdatedAt: syncedServerUpdatedAt,
    epubLocator: '{"href":"/local.xhtml"}',
    progress: progress,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

/// 假伺服器：對 sync_reading_positions 查詢回傳 [remoteItems]；
/// [failWith] 非 null 時改回傳該 HTTP 狀態碼（模擬離線／伺服器錯誤）。
http.Client _server(
  List<Map<String, dynamic>> remoteItems, {
  int? failWith,
  void Function(http.Request)? onRequest,
}) {
  return mockPocketBase((request) async {
    onRequest?.call(request);
    if (failWith != null) return http.Response('{}', failWith);
    return http.Response(
      jsonEncode({
        'items': remoteItems,
        'page': 1,
        'perPage': 1,
        'totalItems': remoteItems.length,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

Map<String, dynamic> _remote({
  required String fingerprint,
  required String updated,
  required double progress,
}) =>
    {
      'id': 'pb-pos-1',
      'book_fingerprint': fingerprint,
      'epub_locator': '{"href":"/remote.xhtml"}',
      'pdf_page_index': null,
      'progress': progress,
      'updated': updated,
    };

void main() {
  late FlutterSecureStoragePlatform originalPlatform;
  late SqliteLibraryRepository libraryRepository;
  late SyncAccountRepository accountRepository;
  late SyncMetadataRepository metadataRepository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
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

  SyncEngine buildEngine(
    http.Client client,
    List<ReadingPositionConflict> conflicts, {
    ReadingPositionChoice? choice,
    Duration networkTimeout = const Duration(seconds: 2),
  }) {
    return SyncEngine(
      networkTimeout: networkTimeout,
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => client),
      onReadingPositionConflict: (conflict) async {
        conflicts.add(conflict);
        return choice;
      },
    );
  }

  group('開書時檢查雲端閱讀位置（FR-19）', () {
    test('已同步過、之後其他裝置又更新了位置：開書時詢問使用者（本機未異動）', () async {
      // 本機：上次同步時伺服器時間 T1，之後沒有任何本機異動（非 dirty）
      await libraryRepository.insertBook(_book(
        'b1',
        fingerprint: 'fp-1',
        syncedServerUpdatedAt: '2026-11-01 00:00:00.000Z',
        progress: 0.3,
      ));
      final conflicts = <ReadingPositionConflict>[];
      final engine = buildEngine(
        _server([_remote(fingerprint: 'fp-1', updated: '2026-11-10 00:00:00.000Z', progress: 0.9)]),
        conflicts,
      );

      await engine.checkReadingPositionOnOpen('b1');

      expect(conflicts, hasLength(1), reason: '開書時應詢問，而不是等離開書才問');
      expect(conflicts.single.bookId, 'b1');
      expect(conflicts.single.local.progress, 0.3);
      expect(conflicts.single.remote.progress, 0.9);
    });

    test('新機器：本機從未確認過遠端現況（position_synced_server_updated_at 為 null）、遠端已有進度：開書時詢問',
        () async {
      await libraryRepository.insertBook(_book('b2', fingerprint: 'fp-2', progress: 0));
      final conflicts = <ReadingPositionConflict>[];
      final engine = buildEngine(
        _server([_remote(fingerprint: 'fp-2', updated: '2026-11-10 00:00:00.000Z', progress: 0.7)]),
        conflicts,
      );

      await engine.checkReadingPositionOnOpen('b2');

      expect(conflicts, hasLength(1));
      expect(conflicts.single.remote.progress, 0.7);
    });

    test('遠端 updated 與本機快取相同（沒有其他裝置動過）：不詢問', () async {
      await libraryRepository.insertBook(_book(
        'b3',
        fingerprint: 'fp-3',
        syncedServerUpdatedAt: '2026-11-10 00:00:00.000Z',
        progress: 0.5,
      ));
      final conflicts = <ReadingPositionConflict>[];
      final engine = buildEngine(
        _server([_remote(fingerprint: 'fp-3', updated: '2026-11-10 00:00:00.000Z', progress: 0.5)]),
        conflicts,
      );

      await engine.checkReadingPositionOnOpen('b3');

      expect(conflicts, isEmpty);
    });

    test('雲端沒有這本書的紀錄：不詢問', () async {
      await libraryRepository.insertBook(_book('b4', fingerprint: 'fp-4'));
      final conflicts = <ReadingPositionConflict>[];
      final engine = buildEngine(_server([]), conflicts);

      await engine.checkReadingPositionOnOpen('b4');

      expect(conflicts, isEmpty);
    });

    test('使用者選「保留雲端」：本機位置被雲端覆寫，且不會被視為待推送的本機異動', () async {
      await libraryRepository.insertBook(_book(
        'b5',
        fingerprint: 'fp-5',
        syncedServerUpdatedAt: '2026-11-01 00:00:00.000Z',
        progress: 0.3,
      ));
      final conflicts = <ReadingPositionConflict>[];
      final engine = buildEngine(
        _server([_remote(fingerprint: 'fp-5', updated: '2026-11-10 00:00:00.000Z', progress: 0.9)]),
        conflicts,
        choice: ReadingPositionChoice.keepCloud,
      );

      final result = await engine.checkReadingPositionOnOpen('b5');

      expect(result, ReadingPositionChoice.keepCloud);
      final row = (await libraryRepository.database
              .query('books', where: 'id = ?', whereArgs: ['b5']))
          .single;
      expect(row['progress'], 0.9);
      expect(row['epubLocator'], '{"href":"/remote.xhtml"}');
      expect(row['position_synced_server_updated_at'], '2026-11-10 00:00:00.000Z');
    });

    test('使用者選「保留本機」：本機位置不變、記下雲端時間戳，並標成待推送（否則下載階段會靜默蓋掉本機）', () async {
      await libraryRepository.insertBook(_book(
        'b8',
        fingerprint: 'fp-8',
        syncedServerUpdatedAt: '2026-11-01 00:00:00.000Z',
        progress: 0.3,
      ));
      await metadataRepository.saveLastPushCompletedAt(5000);
      final conflicts = <ReadingPositionConflict>[];
      final engine = buildEngine(
        _server([_remote(fingerprint: 'fp-8', updated: '2026-11-10 00:00:00.000Z', progress: 0.9)]),
        conflicts,
        choice: ReadingPositionChoice.keepLocal,
      );

      final result = await engine.checkReadingPositionOnOpen('b8');

      expect(result, ReadingPositionChoice.keepLocal);
      final row = (await libraryRepository.database
              .query('books', where: 'id = ?', whereArgs: ['b8']))
          .single;
      expect(row['progress'], 0.3, reason: '本機位置不變');
      expect(row['epubLocator'], '{"href":"/local.xhtml"}');
      expect(row['position_synced_server_updated_at'], '2026-11-10 00:00:00.000Z');
      expect(row['position_updated_at'] as int, greaterThan(5000),
          reason: '須大於 lastPushCompletedAt 才會被下次 checkpoint 當成待推送');
    });

    test('兩邊位置相同但雲端 updated 較新：不詢問，只記下雲端時間戳（避免離開書時又被判成衝突）', () async {
      await libraryRepository.insertBook(_book(
        'b9',
        fingerprint: 'fp-9',
        syncedServerUpdatedAt: '2026-11-01 00:00:00.000Z',
        progress: 0.5,
      ));
      final conflicts = <ReadingPositionConflict>[];
      final remote =
          _remote(fingerprint: 'fp-9', updated: '2026-11-10 00:00:00.000Z', progress: 0.5);
      remote['epub_locator'] = '{"href":"/local.xhtml"}'; // 與本機相同
      final engine = buildEngine(_server([remote]), conflicts);

      final result = await engine.checkReadingPositionOnOpen('b9');

      expect(result, isNull);
      expect(conflicts, isEmpty);
      final row = (await libraryRepository.database
              .query('books', where: 'id = ?', whereArgs: ['b9']))
          .single;
      expect(row['position_synced_server_updated_at'], '2026-11-10 00:00:00.000Z');
    });

    test('請求失敗（離線／伺服器錯誤）：不拋例外、不詢問，不阻擋開書', () async {
      await libraryRepository.insertBook(_book('b6', fingerprint: 'fp-6'));
      final conflicts = <ReadingPositionConflict>[];
      final engine = buildEngine(_server([], failWith: 500), conflicts);

      final result = await engine.checkReadingPositionOnOpen('b6');

      expect(result, isNull);
      expect(conflicts, isEmpty);
    });

    test('網路逾時（伺服器遲遲不回應）：到時間就放棄，回傳 null、不詢問，不阻擋開書', () async {
      await libraryRepository.insertBook(_book('b7', fingerprint: 'fp-7'));
      final conflicts = <ReadingPositionConflict>[];
      // 伺服器 2 秒後才回應；逾時設 50ms
      final slow = mockPocketBase((request) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return http.Response(
          jsonEncode({
            'items': [
              _remote(fingerprint: 'fp-7', updated: '2026-11-10 00:00:00.000Z', progress: 0.9),
            ],
            'page': 1,
            'perPage': 1,
            'totalItems': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final engine = buildEngine(slow, conflicts,
          networkTimeout: const Duration(milliseconds: 50));

      final stopwatch = Stopwatch()..start();
      final result = await engine.checkReadingPositionOnOpen('b7');

      expect(result, isNull);
      expect(conflicts, isEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000),
          reason: '應在逾時後立刻放棄，不等伺服器');
    });
  });
}
