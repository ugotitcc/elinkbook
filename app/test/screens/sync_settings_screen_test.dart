import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/screens/sync_settings_screen.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';

void main() {
  late FlutterSecureStoragePlatform originalPlatform;
  late SyncAccountRepository accountRepository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform({});
    accountRepository = SyncAccountRepository();
  });

  tearDown(() {
    FlutterSecureStoragePlatform.instance = originalPlatform;
  });

  SyncClient buildClient(MockClient mockClient) => SyncClient(
        accountRepository: accountRepository,
        clientFactory: (baseUrl) =>
            PocketBase(baseUrl, httpClientFactory: () => mockClient),
      );

  testWidgets('未登入時，載入完成後顯示三個輸入欄位與「連線／登入」按鈕，不顯示登出按鈕',
      (tester) async {
    final client = buildClient(MockClient((request) async {
      throw StateError('本測試不應該真的發出網路請求');
    }));

    await tester.pumpWidget(MaterialApp(
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync_settings_base_url_field')),
        findsOneWidget);
    expect(
        find.byKey(const Key('sync_settings_email_field')), findsOneWidget);
    expect(find.byKey(const Key('sync_settings_password_field')),
        findsOneWidget);
    expect(find.byKey(const Key('sync_settings_connect_button')),
        findsOneWidget);
    expect(
        find.byKey(const Key('sync_settings_logout_button')), findsNothing);
  });

  testWidgets('密碼欄位預設遮蔽，點擊眼睛圖示可切換顯示/隱藏', (tester) async {
    final client = buildClient(MockClient((request) async {
      throw StateError('本測試不應該真的發出網路請求');
    }));

    await tester.pumpWidget(MaterialApp(
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
      ),
    ));
    await tester.pumpAndSettle();

    TextField passwordField() =>
        tester.widget<TextField>(find.byKey(const Key('sync_settings_password_field')));
    expect(passwordField().obscureText, isTrue);

    await tester.tap(find.byKey(const Key('sync_settings_password_visibility_toggle')));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);

    await tester.tap(find.byKey(const Key('sync_settings_password_visibility_toggle')));
    await tester.pump();
    expect(passwordField().obscureText, isTrue);
  });

  testWidgets('已登入時，載入完成後顯示登入中的 email 與登出按鈕，不顯示輸入欄位',
      (tester) async {
    await accountRepository.saveCredentials(
      authToken: 'token-abc',
      userId: 'user-123',
      email: 'reader@example.com',
    );
    final client = buildClient(MockClient((request) async {
      throw StateError('本測試不應該真的發出網路請求');
    }));

    await tester.pumpWidget(MaterialApp(
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('已登入：reader@example.com'), findsOneWidget);
    expect(
        find.byKey(const Key('sync_settings_logout_button')), findsOneWidget);
    expect(
        find.byKey(const Key('sync_settings_email_field')), findsNothing);
  });

  testWidgets('點擊「連線／登入」成功後，畫面切換為已登入檢視', (tester) async {
    final client = buildClient(MockClient((request) async {
      return http.Response(
        jsonEncode({
          'token': 'token-abc',
          'record': {'id': 'user-123'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

    await tester.pumpWidget(MaterialApp(
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('sync_settings_base_url_field')),
      'http://127.0.0.1:8090',
    );
    await tester.enterText(
      find.byKey(const Key('sync_settings_email_field')),
      'reader@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('sync_settings_password_field')),
      'correct-password',
    );
    await tester.tap(find.byKey(const Key('sync_settings_connect_button')));
    await tester.pumpAndSettle();

    expect(find.text('已登入：reader@example.com'), findsOneWidget);
    expect(
        find.byKey(const Key('sync_settings_logout_button')), findsOneWidget);
  });

  testWidgets('點擊「連線／登入」失敗時，顯示錯誤文字，畫面維持在登入表單', (tester) async {
    final client = buildClient(MockClient((request) async {
      return http.Response(
        jsonEncode({'status': 400, 'message': 'Failed to authenticate.'}),
        400,
        headers: {'content-type': 'application/json'},
      );
    }));

    await tester.pumpWidget(MaterialApp(
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('sync_settings_email_field')),
      'reader@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('sync_settings_password_field')),
      'wrong-password',
    );
    await tester.tap(find.byKey(const Key('sync_settings_connect_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync_settings_error_text')), findsOneWidget);
    expect(find.byKey(const Key('sync_settings_email_field')),
        findsOneWidget);
  });

  testWidgets('點擊「登出」後，畫面切換回登入表單', (tester) async {
    await accountRepository.saveCredentials(
      authToken: 'token-abc',
      userId: 'user-123',
      email: 'reader@example.com',
    );
    final client = buildClient(MockClient((request) async {
      throw StateError('本測試不應該真的發出網路請求');
    }));

    await tester.pumpWidget(MaterialApp(
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync_settings_logout_button')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('sync_settings_email_field')), findsOneWidget);
    expect(
        find.byKey(const Key('sync_settings_logout_button')), findsNothing);
  });
}
