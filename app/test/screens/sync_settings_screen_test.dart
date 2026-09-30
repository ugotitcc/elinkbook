import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/sync_settings_screen.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
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

  // 「立即同步」按鈕與最後同步時間不牽涉的既有測試共用這兩個假 closure
  // （2026-09-08 /grill-with-docs 使用者需求引入 SyncSettingsScreen 新
  // 建構參數後，既有測試補上這兩個必要參數）——onManualSync 直接拋出例外
  // 代表這些測試不應該真的觸發同步。
  Future<SyncCheckpointResult> Function() throwingManualSync() =>
      () async => throw StateError('本測試不應該真的觸發同步');
  Future<int?> Function() noLastSyncedAt() => () async => null;

  testWidgets('未登入時，載入完成後顯示三個輸入欄位與「連線／登入」按鈕，不顯示登出按鈕',
      (tester) async {
    final client = buildClient(MockClient((request) async {
      throw StateError('本測試不應該真的發出網路請求');
    }));

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
        onManualSync: throwingManualSync(),
        loadLastSyncedAt: noLastSyncedAt(),
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
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
        onManualSync: throwingManualSync(),
        loadLastSyncedAt: noLastSyncedAt(),
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
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
        onManualSync: throwingManualSync(),
        loadLastSyncedAt: noLastSyncedAt(),
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
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
        onManualSync: throwingManualSync(),
        loadLastSyncedAt: noLastSyncedAt(),
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
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
        onManualSync: throwingManualSync(),
        loadLastSyncedAt: noLastSyncedAt(),
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
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
        onManualSync: throwingManualSync(),
        loadLastSyncedAt: noLastSyncedAt(),
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

  group('手動同步（2026-09-08 /grill-with-docs 使用者需求）', () {
    setUp(() async {
      await accountRepository.saveCredentials(
        authToken: 'token-abc',
        userId: 'user-123',
        email: 'reader@example.com',
      );
    });

    SyncClient neverCalledClient() => buildClient(MockClient((request) async {
          throw StateError('本測試不應該真的發出網路請求');
        }));

    testWidgets('已登入且尚未同步過時，顯示「立即同步」按鈕與「尚未同步過」',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SyncSettingsScreen(
          accountRepository: accountRepository,
          syncClient: neverCalledClient(),
          onManualSync: throwingManualSync(),
          loadLastSyncedAt: () async => null,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sync_settings_manual_sync_button')),
          findsOneWidget);
      expect(find.text('尚未同步過'), findsOneWidget);
    });

    testWidgets('已同步過時，顯示絕對日期時間格式的最後同步時間', (tester) async {
      final syncedAt = DateTime(2026, 9, 8, 14, 32);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SyncSettingsScreen(
          accountRepository: accountRepository,
          syncClient: neverCalledClient(),
          onManualSync: throwingManualSync(),
          loadLastSyncedAt: () async => syncedAt.millisecondsSinceEpoch,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('2026/9/8 14:32'), findsOneWidget);
    });

    testWidgets('點擊「立即同步」按鈕，成功後重新載入並顯示更新後的最後同步時間',
        (tester) async {
      var callCount = 0;
      final syncedAt = DateTime(2026, 9, 8, 15, 0);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SyncSettingsScreen(
          accountRepository: accountRepository,
          syncClient: neverCalledClient(),
          onManualSync: () async {
            callCount++;
            return SyncCheckpointResult.synced;
          },
          loadLastSyncedAt: () async =>
              callCount == 0 ? null : syncedAt.millisecondsSinceEpoch,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('尚未同步過'), findsOneWidget);

      await tester.tap(find.byKey(const Key('sync_settings_manual_sync_button')));
      await tester.pumpAndSettle();

      expect(callCount, 1);
      expect(find.textContaining('2026/9/8 15:00'), findsOneWidget);
    });

    testWidgets('點擊「立即同步」按鈕，失敗時顯示 SnackBar「同步失敗，請確認網路連線」，且不更新最後同步時間顯示',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SyncSettingsScreen(
          accountRepository: accountRepository,
          syncClient: neverCalledClient(),
          onManualSync: () async => SyncCheckpointResult.failed,
          loadLastSyncedAt: () async => null,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sync_settings_manual_sync_button')));
      await tester.pumpAndSettle();

      expect(find.text('同步失敗，請確認網路連線'), findsOneWidget);
      expect(find.text('尚未同步過'), findsOneWidget,
          reason: '失敗時不應更新最後同步時間顯示。');
    });

    testWidgets('點擊「立即同步」時 token 已過期（同步引擎清除 token）：切回登入表單、預填 email、顯示「登入已過期」（epic-50）',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SyncSettingsScreen(
          accountRepository: accountRepository,
          syncClient: neverCalledClient(),
          // 模擬 SyncEngine.runCheckpoint() 的 authRefresh 收到 401：
          // 清除 token（保留 email）並回報 sessionExpired。
          onManualSync: () async {
            await accountRepository.clearAuthToken();
            return SyncCheckpointResult.sessionExpired;
          },
          loadLastSyncedAt: () async => null,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sync_settings_manual_sync_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sync_settings_password_field')), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('sync_settings_email_field'))).controller!.text,
        'reader@example.com',
      );
      expect(find.text('登入已過期，請重新輸入密碼登入'), findsOneWidget);
      expect(find.text('同步失敗，請確認網路連線'), findsNothing,
          reason: '已明確是登入過期，不應再顯示籠統的網路錯誤提示。');
    });

    testWidgets('點擊「立即同步」期間使用者已登出（email 一併清除）：不顯示「登入已過期」與空白 email，也不顯示同步失敗（epic-53）',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SyncSettingsScreen(
          accountRepository: accountRepository,
          syncClient: neverCalledClient(),
          // 模擬同步進行中使用者主動登出：credentials（含 email）全部清除。
          onManualSync: () async {
            await accountRepository.clearCredentials();
            return SyncCheckpointResult.notLoggedIn;
          },
          loadLastSyncedAt: () async => null,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sync_settings_manual_sync_button')));
      await tester.pumpAndSettle();

      expect(find.text('登入已過期，請重新輸入密碼登入'), findsNothing);
      expect(find.text('同步失敗，請確認網路連線'), findsNothing);
    });

    testWidgets('點擊「立即同步」時另一輪同步進行中（alreadyRunning）：不顯示同步失敗，按鈕恢復可按（epic-53）',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SyncSettingsScreen(
          accountRepository: accountRepository,
          syncClient: neverCalledClient(),
          onManualSync: () async => SyncCheckpointResult.alreadyRunning,
          loadLastSyncedAt: () async => null,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sync_settings_manual_sync_button')));
      await tester.pumpAndSettle();

      expect(find.text('同步失敗，請確認網路連線'), findsNothing);
      expect(find.text('登入已過期，請重新輸入密碼登入'), findsNothing);
      expect(
        tester.widget<ElevatedButton>(find.byKey(const Key('sync_settings_manual_sync_button'))).onPressed,
        isNotNull,
        reason: '同步結束後按鈕應恢復可按。',
      );
    });

    testWidgets('開啟畫面時 token 已被自動同步清除但 email 仍在：顯示登入表單、預填 email、顯示「登入已過期」（epic-50）',
        (tester) async {
      await accountRepository.clearAuthToken();

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SyncSettingsScreen(
          accountRepository: accountRepository,
          syncClient: neverCalledClient(),
          onManualSync: throwingManualSync(),
          loadLastSyncedAt: () async => null,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sync_settings_password_field')), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('sync_settings_email_field'))).controller!.text,
        'reader@example.com',
      );
      expect(find.text('登入已過期，請重新輸入密碼登入'), findsOneWidget);
    });

    testWidgets('英文介面下已登入畫面文字正確以英文渲染，最後同步時間為英文日期格式',
        (tester) async {
      await accountRepository.saveCredentials(
        authToken: 'token-abc',
        userId: 'user-123',
        email: 'user@example.com',
      );
      final client = buildClient(MockClient((request) async {
        throw StateError('本測試不應該真的發出網路請求');
      }));

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SyncSettingsScreen(
          accountRepository: accountRepository,
          syncClient: client,
          onManualSync: throwingManualSync(),
          loadLastSyncedAt: () async =>
              DateTime(2026, 3, 15, 14, 30).millisecondsSinceEpoch,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Signed in as: user@example.com'), findsOneWidget);
      expect(find.textContaining('Last synced: 3/15/2026'), findsOneWidget);
      expect(find.text('Sync Now'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
    });
  });
}
