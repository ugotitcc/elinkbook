import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';
import 'package:elinkbook/sync/sync_engine.dart';
import 'package:elinkbook/sync/sync_metadata_repository.dart';
import 'package:elinkbook/sync/sync_reading_position.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 與 integration_test/sync_account_test.dart 使用同一個持續運作的測試
  // 實例／帳號（見 pocketbase-self-hosting.md「已知部署細節」）。
  const testBaseUrl = 'http://pbdev.jigong.org';
  const testEmail = 'epic8-issue2-test@example.com';
  const testPassword = 'epic8-test-password-123';
  const testCollections = [
    'sync_bookmarks',
    'sync_highlights',
    'sync_notes',
    'sync_reading_positions',
  ];

  Future<void> clearRemoteData(PocketBase pb) async {
    for (final name in testCollections) {
      final records = await pb.collection(name).getFullList();
      for (final record in records) {
        await pb.collection(name).delete(record.id);
      }
    }
  }

  testWidgets('端到端 checkpoint：推送本機新增的書籤，真的透過 PocketBase Batch API 寫入，並於下一次 checkpoint 下載回另一個模擬裝置',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final accountRepository = SyncAccountRepository();
    await accountRepository.clearCredentials();
    final client = SyncClient(accountRepository: accountRepository);
    final loginSuccess = await client.testConnection(testBaseUrl, testEmail, testPassword);
    expect(loginSuccess, isTrue);

    final pb = PocketBase(testBaseUrl);
    await pb.collection('users').authWithPassword(testEmail, testPassword);
    await clearRemoteData(pb);
    addTearDown(() => clearRemoteData(pb));

    // 裝置 A：新增一筆書籤並推送。
    final deviceA = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => deviceA.close());
    final bookA = Book(
      id: 'book-a',
      title: '整合測試書',
      format: BookFileFormat.epub,
      filePath: 'content://example/book-a',
      source: BookSource.local,
      contentFingerprint: 'integration-test-fingerprint-${DateTime.now().microsecondsSinceEpoch}',
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    );
    await deviceA.insertBook(bookA);
    final bookmarksA = BookmarksRepository(deviceA.database);
    await bookmarksA.insert(
      const Bookmark(id: 'integration-bm-1', bookId: 'book-a', name: '真機測試書籤', progression: 0.42),
    );
    final engineA = SyncEngine(
      db: deviceA.database,
      accountRepository: accountRepository,
      metadataRepository: SyncMetadataRepository(deviceA.database),
    );

    await engineA.runCheckpoint();

    final remoteRecords = await pb.collection('sync_bookmarks').getFullList(
          filter: 'client_id = "integration-bm-1"',
        );
    expect(remoteRecords, hasLength(1));
    expect(remoteRecords.single.data['name'], '真機測試書籤');
    expect(remoteRecords.single.data['book_fingerprint'], bookA.contentFingerprint);

    // 裝置 B：同一個帳號、同一本書（指紋相同），執行 checkpoint 應下載到
    // 裝置 A 剛才推送的書籤。
    final deviceB = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => deviceB.close());
    // 注意：`Book.copyWith()` 刻意不含 `contentFingerprint`（見 book.dart
    // 既有註解），若在這裡呼叫 `bookA.copyWith()` 會把指紋重置為 null、
    // 破壞本測試「兩個裝置算出相同指紋」的前提。改為直接把同一個
    // `bookA` 物件（含指紋）插入裝置 B 的資料庫，模擬「裝置 B 也匯入了
    // 同一本書、算出相同指紋」的情境——兩個裝置是各自獨立的記憶體內
    // 資料庫，用同一個 id/物件插入不會互相干擾。
    await deviceB.insertBook(bookA);
    final engineB = SyncEngine(
      db: deviceB.database,
      accountRepository: accountRepository,
      metadataRepository: SyncMetadataRepository(deviceB.database),
    );

    await engineB.runCheckpoint();

    final bookmarksB = BookmarksRepository(deviceB.database);
    final downloaded = await bookmarksB.listByBook('book-a');
    expect(downloaded, hasLength(1));
    expect(downloaded.single.id, 'integration-bm-1');
    expect(downloaded.single.name, '真機測試書籤');

    await client.logout();
  });

  testWidgets(
      '雙裝置閱讀位置衝突：裝置 A 推送位置後，裝置 B 也異動同一本書位置並嘗試推送，'
      '正確觸發衝突回呼且不靜默覆蓋任一邊', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final accountRepository = SyncAccountRepository();
    await accountRepository.clearCredentials();
    final client = SyncClient(accountRepository: accountRepository);
    final loginSuccess = await client.testConnection(testBaseUrl, testEmail, testPassword);
    expect(loginSuccess, isTrue);

    final pb = PocketBase(testBaseUrl);
    await pb.collection('users').authWithPassword(testEmail, testPassword);
    await clearRemoteData(pb);
    addTearDown(() => clearRemoteData(pb));

    final sharedFingerprint =
        'integration-test-position-fingerprint-${DateTime.now().microsecondsSinceEpoch}';

    // 裝置 A：開這本書、讀到第 10 頁，checkpoint 推送。
    final deviceA = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => deviceA.close());
    final bookA = Book(
      id: 'book-position-a',
      title: '雙裝置位置測試書',
      format: BookFileFormat.pdf,
      filePath: 'content://example/book-position-a',
      source: BookSource.local,
      contentFingerprint: sharedFingerprint,
      pdfPageIndex: 9,
      progress: 0.3,
      positionUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    );
    await deviceA.insertBook(bookA);
    final engineA = SyncEngine(
      db: deviceA.database,
      accountRepository: accountRepository,
      metadataRepository: SyncMetadataRepository(deviceA.database),
    );
    await engineA.runCheckpoint();

    final remoteAfterA = await pb.collection('sync_reading_positions').getList(
          filter: 'book_fingerprint = "$sharedFingerprint"',
          perPage: 1,
        );
    expect(remoteAfterA.items, hasLength(1));
    expect((remoteAfterA.items.single.data['pdf_page_index'] as num).toInt(), 9);

    // 裝置 B：獨立的本機資料庫，同一本書（相同指紋），但本機從未同步過
    // 這本書的位置（position_synced_server_updated_at 為 null）——先讀到
    // 第 20 頁、本機異動待推送，checkpoint 時應偵測到衝突（遠端已有裝置
    // A 剛推送的紀錄，本機快取為 null，依 resolveReadingPositionAction()
    // 的定義視為衝突，見 plan-issue-5.md Task 3）。
    final deviceB = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => deviceB.close());
    final bookB = Book(
      id: 'book-position-b',
      title: '雙裝置位置測試書',
      format: BookFileFormat.pdf,
      filePath: 'content://example/book-position-b',
      source: BookSource.local,
      contentFingerprint: sharedFingerprint,
      pdfPageIndex: 19,
      progress: 0.6,
      positionUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    );
    await deviceB.insertBook(bookB);

    ReadingPositionConflict? capturedConflict;
    final engineB = SyncEngine(
      db: deviceB.database,
      accountRepository: accountRepository,
      metadataRepository: SyncMetadataRepository(deviceB.database),
      onReadingPositionConflict: (conflict) async {
        capturedConflict = conflict;
        return ReadingPositionChoice.keepLocal;
      },
    );
    await engineB.runCheckpoint();

    expect(capturedConflict, isNotNull, reason: '應正確偵測到衝突並觸發回呼');
    expect(capturedConflict!.local.pdfPageIndex, 19);
    expect(capturedConflict!.remote.pdfPageIndex, 9);

    // 裝置 B 選擇保留本機，雲端最終應是裝置 B 的版本（第 20 頁）。
    final remoteAfterB = await pb.collection('sync_reading_positions').getList(
          filter: 'book_fingerprint = "$sharedFingerprint"',
          perPage: 1,
        );
    expect((remoteAfterB.items.single.data['pdf_page_index'] as num).toInt(), 19);

    await client.logout();
  });
}
