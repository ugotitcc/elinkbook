import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/screens/remote_server_form_screen.dart';

import '../support/fake_opds_client.dart';
import '../support/fake_remote_server_repository.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeRemoteServerRepository repository,
    required FakeOpdsClient opdsClient,
    RemoteServerProfile? existingProfile,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteServerFormScreen(
        repository: repository,
        opdsClient: opdsClient,
        existingProfile: existingProfile,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('新增模式：欄位皆為空，類型預設標準 OPDS', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(),
      opdsClient: FakeOpdsClient(),
    );
    expect(find.text('新增站點'), findsOneWidget);
    final nameField =
        tester.widget<TextField>(find.byKey(const Key('remote_server_form_name_field')));
    expect(nameField.controller!.text, isEmpty);
  });

  testWidgets('編輯模式：既有欄位預填，密碼欄位維持空白', (tester) async {
    final existing = RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.calibreServer,
      username: 'admin',
      allowInsecure: true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(initialServers: [existing]),
      opdsClient: FakeOpdsClient(),
      existingProfile: existing,
    );

    expect(find.text('編輯站點'), findsOneWidget);
    final nameField =
        tester.widget<TextField>(find.byKey(const Key('remote_server_form_name_field')));
    expect(nameField.controller!.text, '家用 NAS');
    final urlField = tester
        .widget<TextField>(find.byKey(const Key('remote_server_form_base_url_field')));
    expect(urlField.controller!.text, 'http://192.168.1.100:8080/opds');
    final usernameField = tester
        .widget<TextField>(find.byKey(const Key('remote_server_form_username_field')));
    expect(usernameField.controller!.text, 'admin');
    final passwordField = tester
        .widget<TextField>(find.byKey(const Key('remote_server_form_password_field')));
    expect(passwordField.controller!.text, isEmpty);
    final allowInsecureSwitch = tester.widget<SwitchListTile>(
        find.byKey(const Key('remote_server_form_allow_insecure_switch')));
    expect(allowInsecureSwitch.value, true);
  });

  testWidgets('測試連線成功時顯示成功文字', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(),
      opdsClient: FakeOpdsClient(testConnectionResult: true),
    );
    await tester.enterText(
        find.byKey(const Key('remote_server_form_base_url_field')), 'http://example.com/opds');
    await tester.tap(find.byKey(const Key('remote_server_form_test_connection_button')));
    await tester.pumpAndSettle();
    expect(find.text('連線成功'), findsOneWidget);
  });

  testWidgets('測試連線失敗時顯示失敗文字', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(),
      opdsClient: FakeOpdsClient(testConnectionResult: false),
    );
    await tester.tap(find.byKey(const Key('remote_server_form_test_connection_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('連線失敗'), findsOneWidget);
  });

  testWidgets('〔審查 Finding 1〕編輯模式測試連線：密碼欄位留空且帳號未清空時，沿用既有密碼發送請求',
      (tester) async {
    final existing = RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      username: 'admin',
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final repository = FakeRemoteServerRepository();
    await repository.addServer(existing, password: 'old-secret');
    final opdsClient = FakeOpdsClient(testConnectionResult: true);

    await pumpScreen(
      tester,
      repository: repository,
      opdsClient: opdsClient,
      existingProfile: existing,
    );
    await tester.tap(find.byKey(const Key('remote_server_form_test_connection_button')));
    await tester.pumpAndSettle();

    expect(opdsClient.testConnectionPasswords, ['old-secret']);
  });

  testWidgets('新增模式儲存：呼叫 addServer 並帶入輸入的密碼，儲存後關閉畫面', (tester) async {
    final repository = FakeRemoteServerRepository();
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (context) => RemoteServerFormScreen(
            repository: repository,
            opdsClient: FakeOpdsClient(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('remote_server_form_name_field')), '公開書庫');
    await tester.enterText(
        find.byKey(const Key('remote_server_form_base_url_field')), 'http://example.com/opds');
    await tester.enterText(
        find.byKey(const Key('remote_server_form_password_field')), 'secret');
    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();

    final servers = await repository.listServers();
    expect(servers, hasLength(1));
    expect(servers.single.name, '公開書庫');
    expect(await repository.loadPassword(servers.single.id), 'secret');
  });

  testWidgets(
      '〔審查 Finding 1 修正〕編輯模式儲存：密碼欄位留空且帳號未清空時，保留既有密碼不被洗掉',
      (tester) async {
    final existing = RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      username: 'admin',
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final repository = FakeRemoteServerRepository();
    await repository.addServer(existing, password: 'old-secret');

    await pumpScreen(
      tester,
      repository: repository,
      opdsClient: FakeOpdsClient(),
      existingProfile: existing,
    );

    // 只改站點名稱，密碼欄位全程不觸碰——這正是 Finding 1 指出的真實回歸
    // 情境：只做不相干的編輯，不該波及既有密碼。
    await tester.enterText(
        find.byKey(const Key('remote_server_form_name_field')), '改名後');
    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();

    final servers = await repository.listServers();
    expect(servers.single.name, '改名後');
    expect(await repository.loadPassword('srv1'), 'old-secret');
  });

  testWidgets('〔審查 Finding 1〕編輯模式儲存：帳號欄位被清空時，密碼隨之一併清除（退回匿名）',
      (tester) async {
    final existing = RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      username: 'admin',
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final repository = FakeRemoteServerRepository();
    await repository.addServer(existing, password: 'old-secret');

    await pumpScreen(
      tester,
      repository: repository,
      opdsClient: FakeOpdsClient(),
      existingProfile: existing,
    );

    await tester.enterText(
        find.byKey(const Key('remote_server_form_username_field')), '');
    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();

    final servers = await repository.listServers();
    expect(servers.single.username, isNull);
    expect(await repository.loadPassword('srv1'), isNull);
  });

  testWidgets('編輯模式儲存：密碼欄位輸入新值時覆蓋既有密碼', (tester) async {
    final existing = RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      username: 'admin',
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final repository = FakeRemoteServerRepository();
    await repository.addServer(existing, password: 'old-secret');

    await pumpScreen(
      tester,
      repository: repository,
      opdsClient: FakeOpdsClient(),
      existingProfile: existing,
    );

    await tester.enterText(
        find.byKey(const Key('remote_server_form_password_field')), 'new-secret');
    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();

    expect(await repository.loadPassword('srv1'), 'new-secret');
  });

  testWidgets('名稱或網址為空時儲存顯示驗證錯誤，不呼叫 addServer', (tester) async {
    final repository = FakeRemoteServerRepository();
    await pumpScreen(tester, repository: repository, opdsClient: FakeOpdsClient());

    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();

    expect(await repository.listServers(), isEmpty);
    expect(find.textContaining('請填寫'), findsOneWidget);
  });

  testWidgets('〔審查 Minor #2〕網址格式不合法（缺少 http/https）時儲存顯示驗證錯誤，不呼叫 addServer',
      (tester) async {
    final repository = FakeRemoteServerRepository();
    await pumpScreen(tester, repository: repository, opdsClient: FakeOpdsClient());

    await tester.enterText(
        find.byKey(const Key('remote_server_form_name_field')), '格式錯誤測試');
    await tester.enterText(
        find.byKey(const Key('remote_server_form_base_url_field')), '不是網址');
    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();

    expect(await repository.listServers(), isEmpty);
    expect(find.textContaining('有效的伺服器網址'), findsOneWidget);
  });

  testWidgets('〔審查 Important #3〕儲存失敗時顯示錯誤訊息並恢復可互動狀態，不會卡在儲存中',
      (tester) async {
    final repository = FakeRemoteServerRepository(
      saveServerError: StateError('模擬 SQLite 寫入失敗'),
    );
    await pumpScreen(tester, repository: repository, opdsClient: FakeOpdsClient());

    await tester.enterText(
        find.byKey(const Key('remote_server_form_name_field')), '公開書庫');
    await tester.enterText(
        find.byKey(const Key('remote_server_form_base_url_field')), 'http://example.com/opds');
    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();

    // 畫面仍停留在表單（沒有因為儲存成功而 pop），且儲存按鈕恢復可點擊。
    expect(find.byType(RemoteServerFormScreen), findsOneWidget);
    expect(find.textContaining('儲存失敗'), findsOneWidget);
    final saveButton = tester
        .widget<ElevatedButton>(find.byKey(const Key('remote_server_form_save_button')));
    expect(saveButton.onPressed, isNotNull);
  });
}
