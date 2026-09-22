import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/cloud_account_settings_screen.dart';

import '../support/fake_cloud_account_repository.dart';

void main() {
  testWidgets('未連結時顯示「未連結」與「連結」按鈕，不顯示 email', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('cloud_account_settings_google_drive_unlinked_text')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cloud_account_settings_google_drive_link_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cloud_account_settings_google_drive_linked_email')),
      findsNothing,
    );
  });

  testWidgets('已連結時顯示帳號 email 與「解除連結」按鈕', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('已連結：reader@example.com'), findsOneWidget);
    expect(
      find.byKey(const Key('cloud_account_settings_google_drive_unlink_button')),
      findsOneWidget,
    );
  });

  testWidgets('點擊「解除連結」後畫面更新為未連結狀態', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud_account_settings_google_drive_unlink_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('cloud_account_settings_google_drive_unlinked_text')),
      findsOneWidget,
    );
    expect(await accountRepository.isLinked(CloudProvider.googleDrive), false);
  });

  testWidgets('未連結時 OneDrive 區塊顯示「未連結」與「連結」按鈕，不顯示 email', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('cloud_account_settings_onedrive_unlinked_text')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cloud_account_settings_onedrive_link_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cloud_account_settings_onedrive_linked_email')),
      findsNothing,
    );
  });

  testWidgets('已連結時 OneDrive 區塊顯示帳號 email 與「解除連結」按鈕', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.oneDrive,
      CloudAccountTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        email: 'reader@outlook.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('已連結：reader@outlook.com'), findsOneWidget);
    expect(
      find.byKey(const Key('cloud_account_settings_onedrive_unlink_button')),
      findsOneWidget,
    );
  });

  testWidgets('點擊 OneDrive「解除連結」後畫面更新為未連結狀態，Google Drive 區塊不受影響', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'gd-access-1',
        refreshToken: 'gd-refresh-1',
        email: 'reader@gmail.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await accountRepository.link(
      CloudProvider.oneDrive,
      CloudAccountTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        email: 'reader@outlook.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud_account_settings_onedrive_unlink_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('cloud_account_settings_onedrive_unlinked_text')),
      findsOneWidget,
    );
    expect(await accountRepository.isLinked(CloudProvider.oneDrive), false);
    // Google Drive 區塊維持已連結狀態，證明兩個 provider 的狀態彼此獨立。
    expect(find.text('已連結：reader@gmail.com'), findsOneWidget);
    expect(await accountRepository.isLinked(CloudProvider.googleDrive), true);
  });

  testWidgets('英文介面下已連結/未連結狀態文字正確以英文渲染', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        email: 'user@gmail.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Linked Cloud Import Accounts'), findsOneWidget);
    expect(find.text('Linked: user@gmail.com'), findsOneWidget);
    expect(find.text('Unlink'), findsOneWidget);
    expect(find.text('Not linked'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
  });
}
