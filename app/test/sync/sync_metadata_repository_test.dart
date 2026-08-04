import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/sync/sync_metadata_repository.dart';
import 'package:elinkbook/sync/sync_models.dart';

void main() {
  late SqliteLibraryRepository libraryRepository;
  late SyncMetadataRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = SyncMetadataRepository(libraryRepository.database);
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('loadLastPushCompletedAt 初始為 null，saveLastPushCompletedAt 後可讀回', () async {
    expect(await repository.loadLastPushCompletedAt(), isNull);

    await repository.saveLastPushCompletedAt(1000);

    expect(await repository.loadLastPushCompletedAt(), 1000);
  });

  test('loadPulledCursor 初始為 null，savePulledCursor 後可讀回，且各 collection 互不干擾',
      () async {
    expect(await repository.loadPulledCursor(SyncCollection.bookmarks), isNull);

    await repository.savePulledCursor(SyncCollection.bookmarks, '2026-08-01 00:00:00.000Z');

    expect(
      await repository.loadPulledCursor(SyncCollection.bookmarks),
      '2026-08-01 00:00:00.000Z',
    );
    expect(await repository.loadPulledCursor(SyncCollection.highlights), isNull);
  });

  test('loadRemoteIds 初始為空，saveRemoteId 後可讀回，且依 collection 區分', () async {
    expect(await repository.loadRemoteIds(SyncCollection.bookmarks), isEmpty);

    await repository.saveRemoteId(SyncCollection.bookmarks, 'bm1', 'pb-abc');
    await repository.saveRemoteId(SyncCollection.highlights, 'bm1', 'pb-xyz');

    expect(await repository.loadRemoteIds(SyncCollection.bookmarks), {'bm1': 'pb-abc'});
    expect(await repository.loadRemoteIds(SyncCollection.highlights), {'bm1': 'pb-xyz'});
  });

  test('saveRemoteId 對同一個 (collection, client_id) 重複寫入時覆蓋舊值', () async {
    await repository.saveRemoteId(SyncCollection.bookmarks, 'bm1', 'pb-old');
    await repository.saveRemoteId(SyncCollection.bookmarks, 'bm1', 'pb-new');

    expect(await repository.loadRemoteIds(SyncCollection.bookmarks), {'bm1': 'pb-new'});
  });

  test('savePendingRecord 寫入後 listPendingRecords 可讀回完整內容', () async {
    await repository.savePendingRecord(
      collection: SyncCollection.bookmarks,
      clientId: 'bm1',
      bookFingerprint: 'fp-1',
      remoteId: 'pb-1',
      deletedAt: null,
      fields: {'name': '第一章'},
    );

    final pending = await repository.listPendingRecords();

    expect(pending, hasLength(1));
    expect(pending.single.collection, SyncCollection.bookmarks);
    expect(pending.single.clientId, 'bm1');
    expect(pending.single.bookFingerprint, 'fp-1');
    expect(pending.single.remoteId, 'pb-1');
    expect(pending.single.deletedAt, isNull);
    expect(pending.single.fields, {'name': '第一章'});
  });

  test('deletePendingRecord 移除指定紀錄，其餘不受影響', () async {
    await repository.savePendingRecord(
      collection: SyncCollection.bookmarks,
      clientId: 'bm1',
      bookFingerprint: 'fp-1',
      remoteId: 'pb-1',
      deletedAt: null,
      fields: const {},
    );
    await repository.savePendingRecord(
      collection: SyncCollection.bookmarks,
      clientId: 'bm2',
      bookFingerprint: 'fp-2',
      remoteId: 'pb-2',
      deletedAt: null,
      fields: const {},
    );

    await repository.deletePendingRecord(SyncCollection.bookmarks, 'bm1');

    final pending = await repository.listPendingRecords();
    expect(pending, hasLength(1));
    expect(pending.single.clientId, 'bm2');
  });

  test('loadReadingPositionsCursor 初始為 null，saveReadingPositionsCursor 後可讀回（epic-8-sync Issue 5）',
      () async {
    expect(await repository.loadReadingPositionsCursor(), isNull);

    await repository.saveReadingPositionsCursor('2026-08-04 00:00:00.000Z');

    expect(
      await repository.loadReadingPositionsCursor(),
      '2026-08-04 00:00:00.000Z',
    );
  });

  test('saveReadingPositionsCursor 不影響其他 collection 的游標', () async {
    await repository.savePulledCursor(SyncCollection.bookmarks, '2026-08-01 00:00:00.000Z');

    await repository.saveReadingPositionsCursor('2026-08-04 00:00:00.000Z');

    expect(
      await repository.loadPulledCursor(SyncCollection.bookmarks),
      '2026-08-01 00:00:00.000Z',
    );
  });
}
