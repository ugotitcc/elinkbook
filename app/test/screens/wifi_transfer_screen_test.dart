import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:wakelock_plus/wakelock_plus.dart'
    show wakelockPlusPlatformInstance;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import 'package:elinkbook/screens/wifi_transfer_screen.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_wakelock_plus_platform.dart';

void main() {
  late FakeWakelockPlusPlatform fakeWakelock;
  late WakelockPlusPlatformInterface originalWakelockPlatform;

  setUp(() {
    fakeWakelock = FakeWakelockPlusPlatform();
    originalWakelockPlatform = wakelockPlusPlatformInstance;
    wakelockPlusPlatformInstance = fakeWakelock;
  });

  tearDown(() {
    wakelockPlusPlatformInstance = originalWakelockPlatform;
  });

  Widget buildScreen({
    required CheckNetworkAvailability checkNetworkAvailability,
    ValueListenable<int>? activeTransfersNotifierOverride,
    Locale locale = const Locale('zh', 'TW'),
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WifiTransferScreen(
        libraryRepository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        computeFingerprint: FakeFingerprintComputer().call,
        checkNetworkAvailability: checkNetworkAvailability,
        activeTransfersNotifierOverride:
            activeTransfersNotifierOverride ?? ValueNotifier<int>(0),
      ),
    );
  }

  testWidgets('wifiClient：顯示 IP 文字與 QR Code', (tester) async {
    await tester.pumpWidget(
      buildScreen(
        checkNetworkAvailability: () async => const NetworkAvailability(
          kind: NetworkAvailabilityKind.wifiClient,
          ipAddress: '192.168.1.5',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wifi_transfer_ip_text')), findsOneWidget);
    expect(find.text('http://192.168.1.5:8080'), findsOneWidget);
    expect(find.byKey(const Key('wifi_transfer_qr_code')), findsOneWidget);
  });

  testWidgets('hotspot：顯示 IP 文字與 QR Code', (tester) async {
    await tester.pumpWidget(
      buildScreen(
        checkNetworkAvailability: () async => const NetworkAvailability(
          kind: NetworkAvailabilityKind.hotspot,
          ipAddress: '192.168.43.1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wifi_transfer_ip_text')), findsOneWidget);
    expect(find.text('http://192.168.43.1:8080'), findsOneWidget);
    expect(find.byKey(const Key('wifi_transfer_qr_code')), findsOneWidget);
  });

  testWidgets('unavailable：停用文案與手動覆寫按鈕，無 IP/QR', (tester) async {
    await tester.pumpWidget(
      buildScreen(
        checkNetworkAvailability: () async => const NetworkAvailability(
          kind: NetworkAvailabilityKind.unavailable,
          allCandidates: [
            NetworkInterfaceCandidate(
              interfaceName: 'rmnet0',
              ipAddress: '10.0.0.1',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wifi_transfer_ip_text')), findsNothing);
    expect(find.byKey(const Key('wifi_transfer_qr_code')), findsNothing);
    expect(find.text('請連線至 WiFi 或開啟手機熱點'), findsOneWidget);
    expect(
      find.byKey(const Key('wifi_transfer_manual_override_button')),
      findsOneWidget,
    );
  });

  testWidgets(
    'unavailable 按下手動覆寫按鈕後列出 allCandidates，點擊候選項後切換為顯示該 IP 網址與 QR Code（M-1）',
    (tester) async {
      await tester.pumpWidget(
        buildScreen(
          checkNetworkAvailability: () async => const NetworkAvailability(
            kind: NetworkAvailabilityKind.unavailable,
            allCandidates: [
              NetworkInterfaceCandidate(
                interfaceName: 'rmnet0',
                ipAddress: '10.0.0.1',
              ),
              NetworkInterfaceCandidate(
                interfaceName: 'wlan0',
                ipAddress: '192.168.1.9',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('wifi_transfer_manual_override_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('wifi_transfer_candidate_rmnet0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('wifi_transfer_candidate_wlan0')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('wifi_transfer_candidate_wlan0')));
      await tester.pumpAndSettle();

      expect(find.text('http://192.168.1.9:8080'), findsOneWidget);
      expect(find.byKey(const Key('wifi_transfer_qr_code')), findsOneWidget);
    },
  );

  testWidgets('unavailable 且 allCandidates 為空時顯示對應提示', (tester) async {
    await tester.pumpWidget(
      buildScreen(
        checkNetworkAvailability: () async => const NetworkAvailability(
          kind: NetworkAvailabilityKind.unavailable,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('wifi_transfer_manual_override_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('找不到任何可用網路介面'), findsOneWidget);
  });

  testWidgets('activeTransfersNotifierOverride > 0 時返回跳出確認對話框，按下確定離開後對話框關閉', (
    tester,
  ) async {
    final notifier = ValueNotifier<int>(1);
    await tester.pumpWidget(
      buildScreen(
        checkNetworkAvailability: () async => const NetworkAvailability(
          kind: NetworkAvailabilityKind.wifiClient,
          ipAddress: '192.168.1.5',
        ),
        activeTransfersNotifierOverride: notifier,
      ),
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('目前尚有檔案正在傳輸'), findsOneWidget);

    await tester.tap(find.text('確定離開'));
    await tester.pumpAndSettle();

    expect(find.text('目前尚有檔案正在傳輸'), findsNothing);
  });

  testWidgets('activeTransfersNotifierOverride == 0 時返回直接放行不跳對話框', (
    tester,
  ) async {
    final notifier = ValueNotifier<int>(0);
    await tester.pumpWidget(
      buildScreen(
        checkNetworkAvailability: () async => const NetworkAvailability(
          kind: NetworkAvailabilityKind.wifiClient,
          ipAddress: '192.168.1.5',
        ),
        activeTransfersNotifierOverride: notifier,
      ),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('目前尚有檔案正在傳輸'), findsNothing);
  });

  testWidgets('initState 呼叫 WakelockPlus.enable()，dispose 呼叫 disable()', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScreen(
        checkNetworkAvailability: () async => const NetworkAvailability(
          kind: NetworkAvailabilityKind.unavailable,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fakeWakelock.toggleCalls, [true]);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(fakeWakelock.toggleCalls, [true, false]);
  });

  testWidgets(
    'checkNetworkAvailability() 拋出例外時降級為 unavailable，不會因 snapshot.data! 崩潰（I-3）',
    (tester) async {
      await tester.pumpWidget(
        buildScreen(
          checkNetworkAvailability: () async => throw StateError('模擬平台呼叫失敗'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('請連線至 WiFi 或開啟手機熱點'), findsOneWidget);
    },
  );

  testWidgets('activeTransfersNotifier 狀態變化：activeCount 為 0 時不顯示傳輸中橫幅，'
      '大於 0 時即時顯示傳輸中橫幅與檔案數量（Issue 4）', (tester) async {
    final activeNotifier = ValueNotifier<int>(0);
    await tester.pumpWidget(
      buildScreen(
        checkNetworkAvailability: () async => const NetworkAvailability(
          kind: NetworkAvailabilityKind.wifiClient,
          ipAddress: '192.168.1.5',
        ),
        activeTransfersNotifierOverride: activeNotifier,
      ),
    );
    await tester.pumpAndSettle();

    // 初始 activeCount 為 0，不顯示橫幅
    expect(
      find.byKey(const Key('wifi_transfer_active_transfers_banner')),
      findsNothing,
    );

    // activeCount 變為 2，顯示橫幅與數量
    activeNotifier.value = 2;
    await tester.pump();

    expect(
      find.byKey(const Key('wifi_transfer_active_transfers_banner')),
      findsOneWidget,
    );
    expect(find.text('正在傳輸中（2 個檔案）…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // activeCount 歸 0，橫幅自動隱藏
    activeNotifier.value = 0;
    await tester.pump();

    expect(
      find.byKey(const Key('wifi_transfer_active_transfers_banner')),
      findsNothing,
    );
  });

  testWidgets(
    'activeTransfersNotifier 在 E-Ink 高對比主題下正常渲染黑白指示條（Issue 4 / I-1）',
    (tester) async {
      final activeNotifier = ValueNotifier<int>(1);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.black),
            scaffoldBackgroundColor: Colors.white,
          ),
          home: WifiTransferScreen(
            libraryRepository: FakeLibraryRepository(),
            importService: FakeBookImportService(),
            computeFingerprint: FakeFingerprintComputer().call,
            checkNetworkAvailability: () async => const NetworkAvailability(
              kind: NetworkAvailabilityKind.wifiClient,
              ipAddress: '192.168.1.5',
            ),
            activeTransfersNotifierOverride: activeNotifier,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('wifi_transfer_active_transfers_banner')),
        findsOneWidget,
      );
      expect(find.text('正在傳輸中（1 個檔案）…'), findsOneWidget);
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.color, Colors.black);
    },
  );

  testWidgets('英文介面下傳輸中橫幅單複數皆正確顯示', (tester) async {
    final activeNotifier = ValueNotifier<int>(1);
    await tester.pumpWidget(
      buildScreen(
        checkNetworkAvailability: () async => const NetworkAvailability(
          kind: NetworkAvailabilityKind.wifiClient,
          ipAddress: '192.168.1.5',
        ),
        activeTransfersNotifierOverride: activeNotifier,
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    expect(find.text('Transferring (1 file)…'), findsOneWidget);

    activeNotifier.value = 3;
    await tester.pump();
    expect(find.text('Transferring (3 files)…'), findsOneWidget);
  });

  testWidgets('英文介面下離開確認對話框文字正確', (tester) async {
    final notifier = ValueNotifier<int>(1);
    await tester.pumpWidget(
      buildScreen(
        checkNetworkAvailability: () async => const NetworkAvailability(
          kind: NetworkAvailabilityKind.wifiClient,
          ipAddress: '192.168.1.5',
        ),
        activeTransfersNotifierOverride: notifier,
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Files are still transferring'), findsOneWidget);
    await tester.tap(find.text('Leave Anyway'));
    await tester.pumpAndSettle();
    expect(find.text('Files are still transferring'), findsNothing);
  });
}
