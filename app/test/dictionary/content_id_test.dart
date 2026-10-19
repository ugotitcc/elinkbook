// app/test/dictionary/content_id_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:elinkbook/dictionary/content_id.dart';
import 'package:elinkbook/dictionary/importers/dictionary_importer.dart';
import 'package:flutter_test/flutter_test.dart';

const _kb = 1024;

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('content_id_test');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  /// 寫出 [size] 位元組的檔案，內容為 0..255 循環。
  String writeFile(String name, int size, {Map<int, int> patch = const {}}) {
    final bytes = Uint8List(size);
    for (var i = 0; i < size; i++) {
      bytes[i] = i % 256;
    }
    patch.forEach((i, v) => bytes[i] = v);
    final f = File('${dir.path}/$name')..writeAsBytesSync(bytes);
    return f.path;
  }

  Future<String> idOf(String path, String name) =>
      computeContentId(filePath: path, fileName: name);

  test('相同內容與檔名，兩次計算結果相同', () async {
    final p = writeFile('a.json', 1000);
    expect(await idOf(p, 'a.json'), await idOf(p, 'a.json'));
  });

  test('內容不同，ID 不同', () async {
    final a = writeFile('a.json', 1000);
    final b = writeFile('b.json', 1000, patch: {10: 99});
    expect(await idOf(a, 'x.json'), isNot(await idOf(b, 'x.json')));
  });

  test('檔名不同，ID 不同', () async {
    final p = writeFile('a.json', 1000);
    expect(await idOf(p, 'a.json'), isNot(await idOf(p, 'b.json')));
  });

  test('大小相同、只差中間一個位元組的大檔案，ID 相同', () async {
    // spec 刻意的取捨：大檔案只看頭尾各 64 KB 與大小，換取不必讀完整個檔案。
    final a = writeFile('a.mdx', 200 * _kb);
    final b = writeFile('b.mdx', 200 * _kb, patch: {100000: 7});
    expect(await idOf(a, 'x.mdx'), await idOf(b, 'x.mdx'));
  });

  test('改動頭 64 KB 或尾 64 KB 內的位元組，ID 不同', () async {
    final base = writeFile('a.mdx', 200 * _kb);
    final head = writeFile('h.mdx', 200 * _kb, patch: {5: 7});
    final tail = writeFile('t.mdx', 200 * _kb, patch: {200 * _kb - 5: 7});
    final baseId = await idOf(base, 'x.mdx');
    expect(await idOf(head, 'x.mdx'), isNot(baseId));
    expect(await idOf(tail, 'x.mdx'), isNot(baseId));
  });

  test('小於 128 KB 的檔案改動任一位元組，ID 都不同', () async {
    final base = writeFile('a.json', 100 * _kb);
    final mid = writeFile('m.json', 100 * _kb, patch: {50000: 7});
    expect(await idOf(mid, 'x.json'), isNot(await idOf(base, 'x.json')));
  });

  test('空檔案可計算', () async {
    final p = writeFile('e.json', 0);
    expect(await idOf(p, 'e.json'), isNotEmpty);
  });

  test('檔案不存在丟 DictionaryImportException(unreadableFile)', () async {
    await expectLater(
      idOf('${dir.path}/missing.json', 'missing.json'),
      throwsA(
        isA<DictionaryImportException>()
            .having((e) => e.code, 'code', 'unreadableFile'),
      ),
    );
  });
}
