import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/screens/remote_server_form_screen.dart';
import 'package:elinkbook/screens/remote_server_list_screen.dart';

import '../support/fake_opds_client.dart';
import '../support/fake_remote_server_repository.dart';

Book _fakeBook(String id, String title) {
  return Book(
    id: id,
    title: title,
    format: BookFileFormat.epub,
    filePath: '/books/$id.epub',
    source: BookSource.calibreOpds,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    isDownloaded: false,
  );
}

void main() {
  RemoteServerProfile profile(String id, {String name = '家用 NAS'}) {
    return RemoteServerProfile(
      id: id,
      name: name,
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeRemoteServerRepository repository,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteServerListScreen(
        repository: repository,
        opdsClient: FakeOpdsClient(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('沒有任何站點時顯示空狀態文字', (tester) async {
    await pumpScreen(tester, repository: FakeRemoteServerRepository());
    expect(find.byKey(const Key('remote_server_list_empty_state')), findsOneWidget);
  });

  testWidgets('已有站點時顯示名稱與網址', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(initialServers: [profile('srv1')]),
    );
    expect(find.text('家用 NAS'), findsOneWidget);
    expect(find.text('http://192.168.1.100:8080/opds'), findsOneWidget);
    expect(find.byKey(const Key('remote_server_list_empty_state')), findsNothing);
  });

  testWidgets('點擊新增按鈕導向 RemoteServerFormScreen（新增模式）', (tester) async {
    await pumpScreen(tester, repository: FakeRemoteServerRepository());
    await tester.tap(find.byKey(const Key('remote_server_list_add_button')));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteServerFormScreen), findsOneWidget);
    expect(find.text('新增站點'), findsOneWidget);
  });

  testWidgets('點擊編輯按鈕導向 RemoteServerFormScreen（編輯模式）', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(initialServers: [profile('srv1')]),
    );
    await tester.tap(find.byKey(const Key('remote_server_item_edit_srv1')));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteServerFormScreen), findsOneWidget);
    expect(find.text('編輯站點'), findsOneWidget);
  });

  testWidgets('刪除沒有阻擋的站點後，該站點從清單消失', (tester) async {
    final repository = FakeRemoteServerRepository(initialServers: [profile('srv1')]);
    await pumpScreen(tester, repository: repository);

    await tester.tap(find.byKey(const Key('remote_server_item_delete_srv1')));
    await tester.pumpAndSettle();

    expect(repository.deleteServerCalls, ['srv1']);
    expect(find.byKey(const Key('remote_server_list_empty_state')), findsOneWidget);
  });

  testWidgets('刪除被擋下的站點時顯示示警對話框，站點仍留在清單', (tester) async {
    final blockingBook = _fakeBook('book1', '待下載的書');
    final repository = FakeRemoteServerRepository(
      initialServers: [profile('srv1')],
      blockedDeletions: {'srv1': [blockingBook]},
    );
    await pumpScreen(tester, repository: repository);

    await tester.tap(find.byKey(const Key('remote_server_item_delete_srv1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('remote_server_delete_blocked_dialog')), findsOneWidget);
    expect(find.textContaining('待下載的書'), findsOneWidget);
    expect(find.text('家用 NAS'), findsOneWidget);
  });
}
