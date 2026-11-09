import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/windows_skip.dart';

void main() {
  group('skipOnWindows helper', () {
    test('在當前平台回傳與 Platform.isWindows 一致的布林值', () {
      expect(skipOnWindows('有原因的略過測試'), equals(Platform.isWindows));
    });

    test('傳入空字串或純空白原因時觸發 AssertionError', () {
      expect(() => skipOnWindows(''), throwsA(isA<AssertionError>()));
      expect(() => skipOnWindows('   '), throwsA(isA<AssertionError>()));
    });
  });

  group('integration_test/ 平台守門靜態檢查', () {
    test('所有 integration_test 中的 skip 必須透過 skipOnWindows 且帶有非空原因，禁止裸 Platform.isWindows', () {
      final integrationTestDir = Directory('integration_test');
      if (!integrationTestDir.existsSync()) {
        // 若在非 app 根目錄執行，嘗試修正路徑
        final fallbackDir = Directory('app/integration_test');
        expect(fallbackDir.existsSync(), isTrue, reason: '找不到 integration_test 目錄');
      }

      final dir = integrationTestDir.existsSync()
          ? integrationTestDir
          : Directory('app/integration_test');

      final dartFiles = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final nakedSkipPattern = RegExp(r'skip:\s*Platform\.isWindows');
      final skipOnWindowsPattern = RegExp(r"skipOnWindows\(\s*(['\x22])(.*?)\1\s*\)");

      int totalSkipOnWindowsCalls = 0;

      for (final file in dartFiles) {
        final content = file.readAsStringSync();

        // 1. 禁止出現裸 skip: Platform.isWindows
        expect(
          nakedSkipPattern.hasMatch(content),
          isFalse,
          reason: '${file.path} 包含裸 skip: Platform.isWindows，必須使用 skipOnWindows 附帶原因',
        );

        // 2. 檢查所有的 skipOnWindows 呼叫
        final matches = skipOnWindowsPattern.allMatches(content);
        for (final match in matches) {
          totalSkipOnWindowsCalls++;
          final reason = match.group(2) ?? '';
          expect(
            reason.trim().isNotEmpty,
            isTrue,
            reason: '${file.path} 的 skipOnWindows 原因不得為空字串',
          );
        }
      }

      // 至少 library_screen_test.dart 有使用
      expect(
        totalSkipOnWindowsCalls,
        greaterThanOrEqualTo(3),
        reason: '至少應有 library_screen_test.dart 的 3 個測試使用 skipOnWindows',
      );
    });
  });
}
