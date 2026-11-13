import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 回傳 [source] 中「直接取用文件資料夾」的行號（1 起算）。
///
/// 抓兩類寫法（比對單字邊界，所以函式參照、別名前綴、呼叫括號換行都抓得到）：
/// - `getApplicationDocumentsDirectory`（path_provider 的高階函式）
/// - `getApplicationDocumentsPath`（`PathProviderPlatform.instance` 的低階方法）
///
/// 註解不算：先把區塊註解換成等量換行（保留行號），再略過以 `//` 開頭（含 `///`）的整行。
/// 行尾註解與字串常值內的名稱會被當成違規——寧可誤報也不漏報。
List<int> findDirectDocumentsUsages(String source) {
  final stripped = source.replaceAllMapped(
    RegExp(r'/\*[\s\S]*?\*/'),
    (m) => '\n' * '\n'.allMatches(m[0]!).length,
  );
  final pattern = RegExp(r'\bgetApplicationDocuments(Directory|Path)\b');
  final lines = stripped.split('\n');
  final hits = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith('//')) continue;
    if (pattern.hasMatch(lines[i])) hits.add(i + 1);
  }
  return hits;
}

void main() {
  group('findDirectDocumentsUsages（掃描器本身要抓得到）', () {
    test('一般呼叫、別名前綴、不帶括號的函式參照、低階 PathProviderPlatform 呼叫都抓得到', () {
      const source = '''
final a = await getApplicationDocumentsDirectory();
final b = await pp.getApplicationDocumentsDirectory();
final c = getApplicationDocumentsDirectory;
final d = await PathProviderPlatform.instance.getApplicationDocumentsPath();
''';
      expect(findDirectDocumentsUsages(source), equals([1, 2, 3, 4]));
    });

    test('呼叫括號換行也抓得到（名稱本身在同一行）', () {
      const source = 'final a = await getApplicationDocumentsDirectory\n    ();\n';
      expect(findDirectDocumentsUsages(source), equals([1]));
    });

    test('行註解、文件註解、區塊註解內的名稱不算，且行號不位移', () {
      const source = '''
// getApplicationDocumentsDirectory
/// 說明 getApplicationDocumentsDirectory()
/* 區塊註解
   getApplicationDocumentsDirectory()
*/
final x = await getApplicationDocumentsDirectory();
''';
      expect(findDirectDocumentsUsages(source), equals([6]));
    });

    test('名稱相近但不同的識別字不算', () {
      const source = 'final a = myGetApplicationDocumentsDirectoryHelper();\n';
      expect(findDirectDocumentsUsages(source), isEmpty);
    });
  });

  // lib/ 與 third_party/ 內只有 app_paths.dart 與 Android 專用的 foliate_native_bridge.dart
  // 可以直接取用文件資料夾（Windows 版的資料位置規則見 ADR 0044）。
  test(
    'lib/ 與 third_party/ 內只有 app_paths.dart 與 Android 專用的 foliate_native_bridge.dart 可以直接取用文件資料夾',
    () {
      const allowedFiles = <String>{
        'lib/platform/app_paths.dart',
        'lib/reader/foliate_native_bridge.dart',
      };

      final roots = [Directory('lib'), Directory('third_party')];
      expect(roots.first.existsSync(), isTrue, reason: '工作目錄必須是 app/ 以便掃描 lib/');

      final violations = <String>[];
      for (final root in roots.where((d) => d.existsSync())) {
        final dartFiles = root
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final file in dartFiles) {
          final normalizedPath = file.path.replaceAll('\\', '/');
          if (allowedFiles.contains(normalizedPath)) continue;
          for (final line in findDirectDocumentsUsages(file.readAsStringSync())) {
            violations.add('$normalizedPath:$line');
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

  // foliate_native_bridge.dart 是整檔豁免的：它取用文件資料夾的那一處只在 Android 路徑執行。
  // 為了避免日後有人在同一檔案的 Windows 分支新增呼叫而不被掃描測試擋下，這裡釘住兩件事：
  // 只有一處，而且位在「if (isWindowsPlatform) { … return }」之後。
  test('foliate_native_bridge.dart 的豁免只涵蓋一處 Android 專用呼叫，且在 Windows 提前返回之後', () {
    final source = File('lib/reader/foliate_native_bridge.dart').readAsStringSync();
    final uses = findDirectDocumentsUsages(source);
    expect(uses, hasLength(1), reason: '豁免檔案內不得新增第二處直接取用文件資料夾');

    final lines = source.split('\n');
    final guardIndex = source.indexOf(
      'if (isWindowsPlatform) {',
      source.indexOf('_defaultCacheBookForServing'),
    );
    final useOffset = lines.take(uses.single - 1).join('\n').length;
    expect(guardIndex, greaterThan(0), reason: '找不到 Windows 提前返回的區塊');
    expect(useOffset, greaterThan(guardIndex), reason: '呼叫必須在 Windows 提前返回之後');
  });
}
