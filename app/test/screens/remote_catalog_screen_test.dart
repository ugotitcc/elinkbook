import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/opds_types.dart';
import 'package:elinkbook/screens/remote_catalog_screen.dart';

import '../support/fake_book_import_service.dart';
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

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeOpdsClient opdsClient,
    FakeRemoteServerRepository? repository,
    String? feedUrl,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteCatalogScreen(
        server: server,
        repository: repository ?? FakeRemoteServerRepository(),
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
    await tester.pump();
    expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
    await tester.pump();
    expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsNothing);

    // entry2 完全沒有支援格式，點擊不應該有任何反應。
    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-2')));
    await tester.pump();
    expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-2')), findsNothing);
  });

  testWidgets('載入失敗時顯示錯誤文字', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: const {});
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.byKey(const Key('remote_catalog_error_text')), findsOneWidget);
  });

  group('下載與匯入', () {
    late Directory tempRoot;
    late PathProviderPlatform originalPathProvider;

    setUpAll(() {
      // sqfliteFfiInit 已不需要——整合測試改用 FakeBookImportService，
      // 不再使用真實 SqliteLibraryRepository。
    });

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

    testWidgets('整合驗證：FakeBookImportService 正確收到 remoteServerId/remoteBookIds/remoteDownloadUrls',
        (tester) async {
      final importService = FakeBookImportService();

      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
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
  });
}
