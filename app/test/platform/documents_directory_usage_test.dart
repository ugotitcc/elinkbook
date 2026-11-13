import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'lib/ 內只有 app_paths.dart 與 Android 專用的 foliate_native_bridge.dart 可以直接呼叫 getApplicationDocumentsDirectory',
    () {
      const allowedFiles = <String>{
        'lib/platform/app_paths.dart',
        'lib/reader/foliate_native_bridge.dart',
      };

      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: '工作目錄必須是 app/ 以便掃描 lib/');

      final violations = <String>[];
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in dartFiles) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        if (allowedFiles.contains(normalizedPath)) continue;

        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('getApplicationDocumentsDirectory(')) {
            violations.add('$normalizedPath:${i + 1}');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Windows 上必須呼叫 appDocumentsDirectory()，違規位置：\n${violations.join('\n')}',
      );
    },
  );
}
