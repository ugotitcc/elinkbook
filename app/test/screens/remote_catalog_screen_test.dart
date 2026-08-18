import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/opds_types.dart';
import 'package:elinkbook/screens/remote_catalog_screen.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_server_repository.dart';

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
}
