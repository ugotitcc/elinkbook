import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/remote_server_repository.dart';
import 'package:elinkbook/remote/sqlite_remote_server_repository.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository libraryRepo;
  late SqliteRemoteServerRepository repo;
  late FlutterSecureStoragePlatform originalPlatform;

  setUp(() async {
    libraryRepo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    originalPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
    repo = SqliteRemoteServerRepository(
      database: libraryRepo.database,
      libraryRepository: libraryRepo,
    );
  });

  tearDown(() async {
    await libraryRepo.close();
    FlutterSecureStoragePlatform.instance = originalPlatform;
  });

  RemoteServerProfile profile(String id, {String? username, bool allowInsecure = false}) {
    return RemoteServerProfile(
      id: id,
      name: '測試站點',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      username: username,
      allowInsecure: allowInsecure,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  test('addServer 後 listServers 可以查到，密碼可透過 loadPassword 讀回', () async {
    await repo.addServer(profile('srv1', username: 'admin'), password: 'secret');

    final servers = await repo.listServers();
    expect(servers, hasLength(1));
    expect(servers.single.id, 'srv1');
    expect(servers.single.username, 'admin');
    expect(await repo.loadPassword('srv1'), 'secret');
  });

  test('addServer 未帶密碼時，loadPassword 回傳 null（匿名連線）', () async {
    await repo.addServer(profile('srv1'));
    expect(await repo.loadPassword('srv1'), isNull);
  });

  test('updateServer 帶新密碼時覆蓋舊密碼', () async {
    await repo.addServer(profile('srv1'), password: 'old-secret');
    await repo.updateServer(profile('srv1', username: 'admin'), password: 'new-secret');
    expect(await repo.loadPassword('srv1'), 'new-secret');
  });

  test('updateServer 未帶密碼時清除既有密碼（退回匿名）', () async {
    await repo.addServer(profile('srv1'), password: 'old-secret');
    await repo.updateServer(profile('srv1'));
    expect(await repo.loadPassword('srv1'), isNull);
  });

  test('updateServer 更新 allowInsecure／baseUrl 等欄位後 listServers 反映最新值', () async {
    await repo.addServer(profile('srv1'));
    await repo.updateServer(RemoteServerProfile(
      id: 'srv1',
      name: '改名後',
      baseUrl: 'https://192.168.1.100:8443/opds',
      type: RemoteServerType.opds,
      allowInsecure: true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    ));
    final updated = (await repo.listServers()).single;
    expect(updated.name, '改名後');
    expect(updated.allowInsecure, true);
  });

  test('deleteServer：沒有僅雲端紀錄書籍時，成功刪除站點與密碼', () async {
    await repo.addServer(profile('srv1'), password: 'secret');
    await repo.deleteServer('srv1');
    expect(await repo.listServers(), isEmpty);
    expect(await repo.loadPassword('srv1'), isNull);
  });

  test('deleteServer：有僅雲端紀錄（isDownloaded=false）書籍時，拋出例外並保留站點', () async {
    await repo.addServer(profile('srv1'));
    await libraryRepo.insertBook(Book(
      id: 'book1',
      title: '待下載的書',
      format: BookFileFormat.epub,
      filePath: '/books/book1.epub',
      source: BookSource.calibreOpds,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      remoteServerId: 'srv1',
      remoteBookId: 'remote-book-1',
      isDownloaded: false,
    ));

    await expectLater(
      () => repo.deleteServer('srv1'),
      throwsA(isA<RemoteServerDeletionBlockedException>().having(
        (e) => e.blockingBooks.map((b) => b.id),
        'blockingBooks',
        ['book1'],
      )),
    );
    expect(await repo.listServers(), hasLength(1));
  });

  test('deleteServer：已下載完成的書籍不阻擋刪除，其 remoteServerId 隨站點刪除自動變為 NULL', () async {
    await repo.addServer(profile('srv1'));
    await libraryRepo.insertBook(Book(
      id: 'book1',
      title: '已下載的書',
      format: BookFileFormat.epub,
      filePath: '/books/book1.epub',
      source: BookSource.calibreOpds,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      remoteServerId: 'srv1',
      remoteBookId: 'remote-book-1',
      isDownloaded: true,
    ));

    await repo.deleteServer('srv1');

    expect(await repo.listServers(), isEmpty);
    final books = await libraryRepo.listBooks();
    expect(books.single.remoteServerId, isNull);
  });
}
