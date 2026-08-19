import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/screens/cloud_account_settings_screen.dart';

import '../support/fake_cloud_account_repository.dart';

void main() {
  testWidgets('未連結時顯示「未連結」與「連結」按鈕，不顯示 email', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await tester.pumpWidget(MaterialApp(
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
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
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
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
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
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
}
