import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/opds_types.dart';
import 'package:elinkbook/screens/remote_catalog_screen.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_server_repository.dart';
import '../support/fake_path_provider_platform.dart';

void main() {
  final server = RemoteServerProfile(
    id: 'srv1',
    name: '家用 NAS',
    baseUrl: 'http://192.168.1.100:8080/opds',
    type: RemoteServerType.opds,
    username: 'admin',
    allowInsecure: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );

  const entry1 = OpdsEntry(
    remoteBookId: 'book-1',
    title: '紅樓夢',
    author: '曹雪芹',
    thumbnailUrl: 'http://192.168.1.100:8080/opds/cover/1.jpg',
    acquisitions: [
      OpdsAcquisition(href: 'http://192.168.1.100:8080/opds/download/1.epub', format: BookFileFormat.epub),
    ],
  );
  const entry2 = OpdsEntry(
    remoteBookId: 'book-2',
    title: '不支援格式的書',
    acquisitions: [
      OpdsAcquisition(href: 'http://192.168.1.100:8080/opds/download/2.doc', format: null),
    ],
  );

  Book fakeBookMatchingRemote({
    required String id,
    required String remoteServerId,
    required String remoteBookId,
  }) {
    return Book(
      id: id,
      title: '已匯入的書',
      format: BookFileFormat.epub,
      filePath: '/books/$id.epub',
      source: BookSource.calibreOpds,
      remoteServerId: remoteServerId,
      remoteBookId: remoteBookId,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  Book fakeBookWithFingerprint(String id, String fingerprint) {
    return Book(
      id: id,
      title: '本機已有的書',
      format: BookFileFormat.epub,
      filePath: '/books/$id.epub',
      source: BookSource.local,
      contentFingerprint: fingerprint,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeOpdsClient opdsClient,
    FakeRemoteServerRepository? repository,
    FakeLibraryRepository? libraryRepository,
    FakeFingerprintComputer? fingerprintComputer,
    String? feedUrl,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteCatalogScreen(
        server: server,
        repository: repository ?? FakeRemoteServerRepository(),
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        computeFingerprint: (fingerprintComputer ?? FakeFingerprintComputer()).call,
        createOpdsClient: () => opdsClient,
        importService: FakeBookImportService(),
        feedUrl: feedUrl,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('載入根目錄後顯示分類導覽與書目', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(
        title: '家用 NAS 書庫',
        navigationLinks: [OpdsNavigationLink(title: '作者分類', href: 'http://192.168.1.100:8080/opds/by-author')],
        entries: [entry1, entry2],
      ),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.text('作者分類'), findsOneWidget);
    expect(find.text('紅樓夢'), findsOneWidget);
    expect(find.text('不支援格式的書'), findsOneWidget);
  });

  testWidgets('點擊分類導覽項目時 push 新的 RemoteCatalogScreen 並載入該分類 Feed', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(
        title: '根目錄',
        navigationLinks: [OpdsNavigationLink(title: '作者分類', href: 'http://192.168.1.100:8080/opds/by-author')],
      ),
      'http://192.168.1.100:8080/opds/by-author': const OpdsFeed(
        title: '作者分類',
        entries: [entry1],
      ),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    await tester.tap(find.text('作者分類'));
    await tester.pumpAndSettle();

    expect(find.text('紅樓夢'), findsOneWidget);
    expect(opdsClient.fetchFeedCalls, [null, 'http://192.168.1.100:8080/opds/by-author']);
  });

  testWidgets('有 nextUrl 時顯示載入更多按鈕，點擊後累加下一頁書目', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(
        title: '根目錄',
        nextUrl: 'http://192.168.1.100:8080/opds/page2',
        entries: [entry1],
      ),
      'http://192.168.1.100:8080/opds/page2': const OpdsFeed(
        title: '根目錄',
        entries: [entry2],
      ),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.byKey(const Key('remote_catalog_load_more_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('remote_catalog_load_more_button')));
    await tester.pumpAndSettle();

    expect(find.text('紅樓夢'), findsOneWidget);
    expect(find.text('不支援格式的書'), findsOneWidget);
    expect(find.byKey(const Key('remote_catalog_load_more_button')), findsNothing);
  });

  testWidgets('沒有 nextUrl 時不顯示載入更多按鈕', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.byKey(const Key('remote_catalog_load_more_button')), findsNothing);
  });

  testWidgets('書目縮圖以 Image.network 載入並帶入 Basic Auth header', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    final image = tester.widget<Image>(find.byKey(const Key('remote_catalog_thumbnail_book-1')));
    final provider = image.image as NetworkImage;
    expect(provider.url, entry1.thumbnailUrl);
    expect(provider.headers?['Authorization'], isNotNull);
  });

  testWidgets('沒有縮圖的書目顯示預設圖示佔位符', (tester) async {
    const entryNoCover = OpdsEntry(
      remoteBookId: 'book-3',
      title: '無縮圖的書',
      acquisitions: [OpdsAcquisition(href: 'http://x/3.epub', format: BookFileFormat.epub)],
    );
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entryNoCover]),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.byKey(const Key('remote_catalog_thumbnail_placeholder_book-3')), findsOneWidget);
  });

  testWidgets('點擊書目可勾選/取消勾選，僅有支援格式的書目可勾選', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1, entry2]),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsNothing);

    // entry2 完全沒有支援格式，點擊不應該有任何反應。
    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-2')), findsNothing);
  });

  testWidgets('載入失敗時顯示錯誤文字', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: const {});
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.byKey(const Key('remote_catalog_error_text')), findsOneWidget);
  });

  group('選檔前置重複偵測（Layer 1）', () {
    testWidgets('勾選已存在 remoteServerId/remoteBookId 的書目時彈出重複提示，選擇取消則不勾選', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      final libraryRepository = FakeLibraryRepository(initialBooks: [
        fakeBookMatchingRemote(id: 'local-1', remoteServerId: 'srv1', remoteBookId: 'book-1'),
      ]);
      await pumpScreen(tester, opdsClient: opdsClient, libraryRepository: libraryRepository);

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_duplicate_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('remote_catalog_duplicate_dialog_cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsNothing);
    });

    testWidgets('勾選已存在的書目時彈出重複提示，選擇仍要建立則正常勾選', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      final libraryRepository = FakeLibraryRepository(initialBooks: [
        fakeBookMatchingRemote(id: 'local-1', remoteServerId: 'srv1', remoteBookId: 'book-1'),
      ]);
      await pumpScreen(tester, opdsClient: opdsClient, libraryRepository: libraryRepository);

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_duplicate_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsOneWidget);
    });

    testWidgets('勾選沒有重複紀錄的書目時不彈出提示，直接勾選', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      await pumpScreen(tester, opdsClient: opdsClient);

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_duplicate_dialog')), findsNothing);
      expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsOneWidget);
    });
  });

  group('下載與匯入', () {
    late Directory tempRoot;
    late PathProviderPlatform originalPathProvider;


    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('remote_catalog_test');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = FakePathProviderPlatform(tempRoot.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    testWidgets('勾選單本書下載後呼叫 importFiles，帶入 source/remoteServerId/remoteBookIds/remoteDownloadUrls',
        (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      final importService = FakeBookImportService();
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          computeFingerprint: (path, format) async => 'unused-fingerprint',
          createOpdsClient: () => opdsClient,
          importService: importService,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pump();

      // 交錯 runAsync（提供真實事件迴圈讓 dart:io 完成）與 pump（處理微佇列），
      // 驅動 _downloadOne 中的 getTemporaryDirectory → File.create → writeAsBytes
      // → copy → delete → importFiles → setState 完整鏈。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('download_queue_item_book-1')), findsOneWidget);
      expect(find.text('完成'), findsWidgets);

      await tester.tap(find.byKey(const Key('download_queue_done_button')));
      await tester.pumpAndSettle();

      expect(opdsClient.downloadBookCalls, ['http://192.168.1.100:8080/opds/download/1.epub']);
    });

    testWidgets('同一書目有多個支援格式時彈出 FormatSelectionDialog 讓使用者選擇', (tester) async {
      const multiFormatEntry = OpdsEntry(
        remoteBookId: 'book-multi',
        title: '多格式書',
        acquisitions: [
          OpdsAcquisition(href: 'http://x/m.epub', format: BookFileFormat.epub),
          OpdsAcquisition(href: 'http://x/m.pdf', format: BookFileFormat.pdf),
        ],
      );
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [multiFormatEntry]),
      });
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          computeFingerprint: (path, format) async => 'unused-fingerprint',
          createOpdsClient: () => opdsClient,
          importService: FakeBookImportService(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-multi')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('format_selection_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('format_selection_option_http://x/m.pdf')));
      await tester.pump();

      // 交錯 runAsync 與 pump 驅動 dart:io 完成。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(opdsClient.downloadBookCalls, ['http://x/m.pdf']);
    });

    testWidgets('多選批次下載時逐項序列進行，非平行', (tester) async {
      const entryA = OpdsEntry(
        remoteBookId: 'book-a',
        title: '書 A',
        acquisitions: [OpdsAcquisition(href: 'http://x/a.epub', format: BookFileFormat.epub)],
      );
      const entryB = OpdsEntry(
        remoteBookId: 'book-b',
        title: '書 B',
        acquisitions: [OpdsAcquisition(href: 'http://x/b.epub', format: BookFileFormat.epub)],
      );
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entryA, entryB]),
      });
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          computeFingerprint: (path, format) async => 'unused-fingerprint',
          createOpdsClient: () => opdsClient,
          importService: FakeBookImportService(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-a')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-b')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pump();

      // 交錯 runAsync 與 pump 驅動 dart:io 完成（兩本書序列下載）。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(opdsClient.downloadBookCalls, ['http://x/a.epub', 'http://x/b.epub']);
    });

    testWidgets('下載失敗時顯示失敗狀態並可手動重試', (tester) async {
      final opdsClient = FakeOpdsClient(
        feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        },
        downloadError: StateError('模擬下載失敗'),
      );
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          computeFingerprint: (path, format) async => 'unused-fingerprint',
          createOpdsClient: () => opdsClient,
          importService: FakeBookImportService(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pump();

      // 交錯 runAsync 與 pump 驅動 dart:io 微佇列（下載失敗仍需 pump 處理微佇列）。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('失敗'), findsOneWidget);
      expect(find.byKey(const Key('download_queue_retry_book-1')), findsOneWidget);

      opdsClient.downloadError = null;
      await tester.tap(find.byKey(const Key('download_queue_retry_book-1')));
      await tester.pumpAndSettle();

      expect(find.text('完成'), findsWidgets);
    });

    testWidgets('下載中點擊取消後顯示已取消狀態，暫存檔不殘留', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      opdsClient.downloadPendingCompleter = Completer<void>();
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          computeFingerprint: (path, format) async => 'unused-fingerprint',
          createOpdsClient: () => opdsClient,
          importService: FakeBookImportService(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pump();

      expect(find.byKey(const Key('download_queue_cancel_book-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('download_queue_cancel_book-1')));
      opdsClient.downloadPendingCompleter!.complete();

      // 交錯 runAsync 與 pump 驅動 dart:io 微佇列（取消後仍需處理微佇列）。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('已取消'), findsOneWidget);
    });

    testWidgets(
        '引數驗證：importFiles 被呼叫時正確帶入 source/remoteServerId/remoteBookIds/remoteDownloadUrls（FakeBookImportService）',
        (tester) async {
      final importService = FakeBookImportService();

      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          computeFingerprint: (path, format) async => 'unused-fingerprint',
          createOpdsClient: () => opdsClient,
          importService: importService,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pump();

      // 交錯 runAsync 與 pump 驅動 dart:io 微佇列。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // 驗證 importFiles 被正確呼叫，帶入遠端書籍 metadata
      expect(importService.lastImportCall, isNotNull);
      expect(importService.lastImportCall!.source, BookSource.calibreOpds);
      expect(importService.lastImportCall!.remoteServerId, 'srv1');
      expect(importService.lastImportCall!.remoteBookIds, {
        importService.lastImportCall!.uris.single: 'book-1',
      });
      expect(importService.lastImportCall!.remoteDownloadUrls, {
        importService.lastImportCall!.uris.single: 'http://192.168.1.100:8080/opds/download/1.epub',
      });

      // 驗證 OPDS client 被正確呼叫
      expect(opdsClient.downloadBookCalls, ['http://192.168.1.100:8080/opds/download/1.epub']);
    });

    group('下載後指紋比對（Layer 2）', () {
      testWidgets('下載後偵測到與本機書籍內容指紋相同時彈出提示，選擇不建立新副本則刪除暫存檔並標記為略過',
          (tester) async {
        final opdsClient = FakeOpdsClient(feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        });
        final libraryRepository = FakeLibraryRepository(initialBooks: [
          fakeBookWithFingerprint('local-1', 'dup-fingerprint'),
        ]);
        final fingerprintComputer = FakeFingerprintComputer()..nextFingerprint = 'dup-fingerprint';
        final importService = FakeBookImportService();
        await tester.pumpWidget(MaterialApp(
          home: RemoteCatalogScreen(
            server: server,
            repository: FakeRemoteServerRepository(),
            libraryRepository: libraryRepository,
            computeFingerprint: fingerprintComputer.call,
            createOpdsClient: () => opdsClient,
            importService: importService,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
          if (find.byKey(const Key('remote_catalog_duplicate_dialog')).evaluate().isNotEmpty) break;
        }

        expect(find.byKey(const Key('remote_catalog_duplicate_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('remote_catalog_duplicate_dialog_cancel')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(find.text('重複已略過（未匯入）'), findsOneWidget);
        expect(importService.lastImportCall, isNull);
        expect(
          Directory(p.join(tempRoot.path, 'remote_download_temp')).listSync(),
          isEmpty,
        );
      });

      testWidgets('下載後偵測到重複時選擇仍要建立新副本，正常完成匯入', (tester) async {
        final opdsClient = FakeOpdsClient(feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        });
        final libraryRepository = FakeLibraryRepository(initialBooks: [
          fakeBookWithFingerprint('local-1', 'dup-fingerprint'),
        ]);
        final fingerprintComputer = FakeFingerprintComputer()..nextFingerprint = 'dup-fingerprint';
        final importService = FakeBookImportService();
        await tester.pumpWidget(MaterialApp(
          home: RemoteCatalogScreen(
            server: server,
            repository: FakeRemoteServerRepository(),
            libraryRepository: libraryRepository,
            computeFingerprint: fingerprintComputer.call,
            createOpdsClient: () => opdsClient,
            importService: importService,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
          if (find.byKey(const Key('remote_catalog_duplicate_dialog')).evaluate().isNotEmpty) break;
        }

        await tester.tap(find.byKey(const Key('remote_catalog_duplicate_dialog_confirm')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(find.text('完成'), findsWidgets);
        expect(importService.lastImportCall, isNotNull);
      });

      testWidgets('下載後未偵測到重複時不彈出提示，直接完成', (tester) async {
        final opdsClient = FakeOpdsClient(feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        });
        final importService = FakeBookImportService();
        await tester.pumpWidget(MaterialApp(
          home: RemoteCatalogScreen(
            server: server,
            repository: FakeRemoteServerRepository(),
            libraryRepository: FakeLibraryRepository(),
            computeFingerprint: FakeFingerprintComputer().call,
            createOpdsClient: () => opdsClient,
            importService: importService,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('remote_catalog_duplicate_dialog')), findsNothing);
        expect(find.text('完成'), findsWidgets);
        expect(importService.lastImportCall, isNotNull);
      });
    });

    // 〔審查 review-issue-2.md Important #1 核實後修正做法〕上面的
    // 「引數驗證」測試只證明 importFiles() 被呼叫時傳入了正確的參數，
    // 不證明這些欄位真的正確持久化到資料庫、也不證明下載下來的檔案真的
    // 活過搬移到永久位置這個步驟。原本嘗試在這裡（testWidgets）用真實
    // SqliteLibraryRepository／BookImportServiceImpl 補這項驗證，但
    // 真實 BookImportServiceImpl 對非 content:// 路徑計算指紋時會透過
    // computeBookContentFingerprint() 呼叫 Isolate.run()（見
    // book_content_fingerprint.dart）——這與
    // AutomatedTestWidgetsFlutterBinding 的測試環境有更深層的不相容，
    // 即使把觸發流程整個包進 tester.runAsync()（比照
    // library_screen_test.dart「Markdown 匯出」既有先例）仍會卡在
    // `dart:isolate _RawReceivePort._handleMessage` 直到 10 分鐘逾時
    // ——這個組合（testWidgets + 真實 Isolate.run()）在本專案目前沒有
    // 任何成功先例可循，判斷為環境層級的真實限制，不是可以再調整測試
    // 寫法就解決的問題。改為把這項驗證移到
    // `test/library/book_import_service_test.dart`（plain `test()`，
    // 沒有 testWidgets 的 fake zone 限制，Isolate.run() 可以正常完成）
    // ——見該檔案「遠端書架下載完成後匯入（epic-30 Issue 2）」測試，
    // 直接餵入一個非 content:// 的本機檔案路徑（比照 OPDS 下載佇列實際
    // 產生的檔案型態）驗證欄位持久化與檔案存活。
  });
}
