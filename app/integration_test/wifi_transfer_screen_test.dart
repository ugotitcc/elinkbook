import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:elinkbook/screens/wifi_transfer_screen.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';

import '../test/support/fake_book_import_service.dart';
import '../test/support/fake_library_repository.dart';
import '../test/support/fake_fingerprint_computer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '真機：伺服器成功綁定 socket，GET / 可取得首頁 HTML（Issue 1 骨架驗證，'
      '裝置須已連上 WiFi 或已開啟手機熱點）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WifiTransferScreen(
          libraryRepository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          checkNetworkAvailability: checkNetworkAvailability,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證伺服器啟動；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }

    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final url = ipTextWidget.data!;

    final response = await http.get(Uri.parse(url));
    expect(response.statusCode, 200);
    expect(response.body, contains('elinkBook WiFi 傳書'));
  });
}
