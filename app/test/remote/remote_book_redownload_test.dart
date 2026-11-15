import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/remote_book_redownload.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';

import '../support/fake_full_text_search_settings_repository.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_path_provider_platform.dart';
import '../support/fake_remote_server_repository.dart';

void main() {
  late Directory tempRoot;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('remote_book_redownload_test');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempRoot.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  final server = RemoteServerProfile(
    id: 'srv1',
    name: '家用 NAS',
    baseUrl: 'http://192.168.1.100:8080/opds',
    type: RemoteServerType.opds,
    allowInsecure: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );

  Book pendingBook({String? remoteServerId = 'srv1', String? remoteDownloadUrl = 'http://192.168.1.100:8080/opds/download/1.epub'}) => Book(
        id: 'b1',
        title: '待下載的書',
        format: BookFileFormat.epub,
        filePath: '/no/longer/exists.epub',
        source: BookSource.calibreOpds,
        remoteServerId: remoteServerId,
        remoteBookId: 'remote-1',
        remoteDownloadUrl: remoteDownloadUrl,
        isDownloaded: false,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
      );

  // 這個 module 是純 Dart：不接收 BuildContext，畫面離開與否與它無關。
  // 成功路徑（測試 1）因此同時釘住了「離開畫面後書庫仍會被更新」。
  test('成功：回傳 succeeded，更新 filePath 為 remote_books 下的檔案且 isDownloaded 為 true，書庫仍只有 1 本', () async {
    final library = FakeLibraryRepository(initialBooks: [pendingBook()]);

    final outcome = await redownloadBook(
      book: pendingBook(),
      remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
      libraryRepository: library,
      fullTextSearchSettingsRepository: FakeFullTextSearchSettingsRepository(),
      createOpdsClient: () => FakeOpdsClient(),
    );

    expect(outcome, RedownloadOutcome.succeeded);
    final books = await library.listBooks();
    expect(books, hasLength(1));
    final updated = books.single;
    expect(updated.isDownloaded, isTrue);
    expect(p.basename(p.dirname(updated.filePath)), 'remote_books');
    expect(File(updated.filePath).existsSync(), isTrue);
  });

  test('成功：把伺服器密碼傳給 client.downloadBook', () async {
    final servers = FakeRemoteServerRepository();
    await servers.addServer(server, password: 'secret');
    final client = FakeOpdsClient();

    await redownloadBook(
      book: pendingBook(),
      remoteServerRepository: servers,
      libraryRepository: FakeLibraryRepository(initialBooks: [pendingBook()]),
      fullTextSearchSettingsRepository: FakeFullTextSearchSettingsRepository(),
      createOpdsClient: () => client,
    );

    expect(client.downloadBookPasswords, ['secret']);
  });

  test('成功：呼叫 handleBookAvailable，參數是更新後的書', () async {
    final fts = FakeFullTextSearchSettingsRepository();

    await redownloadBook(
      book: pendingBook(),
      remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
      libraryRepository: FakeLibraryRepository(initialBooks: [pendingBook()]),
      fullTextSearchSettingsRepository: fts,
      createOpdsClient: () => FakeOpdsClient(),
    );

    expect(fts.handleBookAvailableCalls, hasLength(1));
    expect(fts.handleBookAvailableCalls.single.isDownloaded, isTrue);
  });

  test('handleBookAvailable 丟例外：仍回 succeeded，書已更新', () async {
    final library = FakeLibraryRepository(initialBooks: [pendingBook()]);

    final outcome = await redownloadBook(
      book: pendingBook(),
      remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
      libraryRepository: library,
      fullTextSearchSettingsRepository:
          FakeFullTextSearchSettingsRepository(handleBookAvailableError: Exception('index boom')),
      createOpdsClient: () => FakeOpdsClient(),
    );

    expect(outcome, RedownloadOutcome.succeeded);
    expect((await library.listBooks()).single.isDownloaded, isTrue);
  });

  test('下載失敗：回傳 failed，書的 filePath／isDownloaded 不變', () async {
    final library = FakeLibraryRepository(initialBooks: [pendingBook()]);

    final outcome = await redownloadBook(
      book: pendingBook(),
      remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
      libraryRepository: library,
      fullTextSearchSettingsRepository: FakeFullTextSearchSettingsRepository(),
      createOpdsClient: () => FakeOpdsClient(downloadError: Exception('boom')),
    );

    expect(outcome, RedownloadOutcome.failed);
    final book = (await library.listBooks()).single;
    expect(book.isDownloaded, isFalse);
    expect(book.filePath, '/no/longer/exists.epub');
  });

  test('缺 remoteDownloadUrl：回傳 notRemoteBook，且不呼叫 createOpdsClient', () async {
    var createCalls = 0;

    final outcome = await redownloadBook(
      book: pendingBook(remoteDownloadUrl: null),
      remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
      libraryRepository: FakeLibraryRepository(),
      fullTextSearchSettingsRepository: FakeFullTextSearchSettingsRepository(),
      createOpdsClient: () {
        createCalls++;
        return FakeOpdsClient();
      },
    );

    expect(outcome, RedownloadOutcome.notRemoteBook);
    expect(createCalls, 0);
  });

  test('缺 remoteServerId、但有 remoteDownloadUrl：回傳 notRemoteBook（不是 serverNotFound），且不呼叫 createOpdsClient', () async {
    var createCalls = 0;

    final outcome = await redownloadBook(
      book: pendingBook(remoteServerId: null),
      remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
      libraryRepository: FakeLibraryRepository(),
      fullTextSearchSettingsRepository: FakeFullTextSearchSettingsRepository(),
      createOpdsClient: () {
        createCalls++;
        return FakeOpdsClient();
      },
    );

    expect(outcome, RedownloadOutcome.notRemoteBook);
    expect(createCalls, 0);
  });

  test('remoteServerId 指向不存在的站點：回傳 serverNotFound', () async {
    final outcome = await redownloadBook(
      book: pendingBook(remoteServerId: 'missing'),
      remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
      libraryRepository: FakeLibraryRepository(),
      fullTextSearchSettingsRepository: FakeFullTextSearchSettingsRepository(),
      createOpdsClient: () => FakeOpdsClient(),
    );

    expect(outcome, RedownloadOutcome.serverNotFound);
  });

  test('isRedownloadable：remoteServerId 或 remoteDownloadUrl 任一為 null 時為 false，皆非 null 時為 true', () {
    expect(isRedownloadable(pendingBook()), isTrue);
    expect(isRedownloadable(pendingBook(remoteServerId: null)), isFalse);
    expect(isRedownloadable(pendingBook(remoteDownloadUrl: null)), isFalse);
  });
}
