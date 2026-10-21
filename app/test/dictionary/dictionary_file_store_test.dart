// DictionaryFileStore 的檔名安全與搬移測試（epic-63 Issue 6a Task 5）。
import 'dart:io';

import 'package:elinkbook/dictionary/dictionary_file_store.dart';
import 'package:elinkbook/dictionary/mdx_companion_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late DictionaryFileStore files;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dict_file_store_test');
    files = DictionaryFileStore(Directory('${tmp.path}/dicts'));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  var seq = 0;

  Future<PickedFile> source(String name, [String content = 'x']) async {
    // 實際路徑用序號：`name` 可能含 `../` 或路徑分隔字元，直接拿來建檔在
    // Windows 上會因為結尾的點被吃掉而失敗。危險檔名只放在 PickedFile.name。
    final file = File('${tmp.path}/src_${seq++}');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return PickedFile(path: file.path, name: name, size: content.length);
  }

  group('檔名清理', () {
    test('../x 只留 basename，不會寫到目錄外', () async {
      final picked = await source('../evil.txt');
      await files.copyInto('s', picked);

      expect(File('${files.dirFor('s').path}/evil.txt').existsSync(), isTrue);
      expect(File('${tmp.path}/evil.txt').existsSync(), isFalse);
    });

    test('a/b.css 只留 b.css', () async {
      final picked = await source('a/b.css');
      await files.copyInto('s', picked);

      expect(File('${files.dirFor('s').path}/b.css').existsSync(), isTrue);
    });

    test('空檔名丟 ArgumentError', () async {
      final picked = await source('');
      await expectLater(
        files.copyInto('s', picked),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('.. 丟 ArgumentError', () async {
      final picked = await source('..');
      await expectLater(
        files.copyInto('s', picked),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('moveInto', () {
    test('跨目錄搬移：目的檔存在、來源檔消失', () async {
      final picked = await source('book.mdx', 'MDX');

      await files.moveInto('s', picked.path, 'book.mdx');

      final moved = File('${files.dirFor('s').path}/book.mdx');
      expect(moved.existsSync(), isTrue);
      expect(await moved.readAsString(), 'MDX');
      expect(File(picked.path).existsSync(), isFalse);
    });

    test('目的檔已存在時覆蓋', () async {
      final dir = files.dirFor('s');
      await dir.create(recursive: true);
      await File('${dir.path}/book.mdx').writeAsString('OLD');

      final picked = await source('book2.mdx', 'NEW');
      await files.moveInto('s', picked.path, 'book.mdx');

      expect(await File('${dir.path}/book.mdx').readAsString(), 'NEW');
    });

    test('空檔名與 .. 丟 ArgumentError', () async {
      final picked = await source('x.mdx');
      await expectLater(
        files.moveInto('s', picked.path, ''),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        files.moveInto('s', picked.path, '..'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
