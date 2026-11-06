import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempEmptyDir;

  setUpAll(() {
    tempEmptyDir = Directory.systemTemp.createTempSync('wv2_probe_empty_');
  });

  tearDownAll(() {
    if (tempEmptyDir.existsSync()) {
      tempEmptyDir.deleteSync(recursive: true);
    }
  });

  testWidgets('空資料夾：getAvailableVersion 回傳 null', (tester) async {
    final version = await WebViewEnvironment.getAvailableVersion(
      browserExecutableFolder: tempEmptyDir.path,
    );
    expect(version, isNull);
  });

  testWidgets('沒有 browserExecutableFolder：getAvailableVersion 回傳非空版本字串', (
    tester,
  ) async {
    final version = await WebViewEnvironment.getAvailableVersion();
    expect(version, isNotNull);
    expect(version, isNotEmpty);
  });

  testWidgets('空資料夾：create 的行為（記錄用）', (tester) async {
    try {
      final env = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          browserExecutableFolder: tempEmptyDir.path,
        ),
      ).timeout(const Duration(seconds: 20));
      print('[probe] create returned instance: $env');
    } catch (e) {
      print('[probe] create threw: ${e.runtimeType} -> $e');
    }
  });
}
