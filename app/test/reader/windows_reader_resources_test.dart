// Windows 讀者資源實作的單元測試（epic-66 Issue 1 Task 6）。

import 'dart:io';
import 'dart:typed_data';

import 'package:elinkbook/reader/windows_reader_resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('win_reader_res_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('loadWindowsFoliateAsset', () {
    test('loadWindowsFoliateAsset：讀得到存在的檔案', () async {
      final assetRoot = Directory(p.join(tempRoot.path, 'data'));
      await Directory(p.join(assetRoot.path, 'foliate')).create(recursive: true);
      final target = File(p.join(assetRoot.path, 'foliate', 'main.js'));
      await target.writeAsString('console.log(1);');

      final bytes = await loadWindowsFoliateAsset(
        'foliate/main.js',
        assetRoot: assetRoot.path,
      );

      expect(bytes, isNotNull);
      expect(String.fromCharCodes(bytes!), 'console.log(1);');
    });

    test('loadWindowsFoliateAsset：不存在回 null', () async {
      final bytes = await loadWindowsFoliateAsset(
        'foliate/missing.js',
        assetRoot: tempRoot.path,
      );

      expect(bytes, isNull);
    });

    test('loadWindowsFoliateAsset：路徑含 .. 回 null', () async {
      final secret = File(p.join(tempRoot.path, 'secret.txt'));
      await secret.writeAsString('secret');

      final bytes = await loadWindowsFoliateAsset(
        '../secret.txt',
        assetRoot: tempRoot.path,
      );

      expect(bytes, isNull);
    });
  });

  group('cacheWindowsBook', () {
    test('cacheWindowsBook：路徑含中文與空白也能複製', () async {
      final sourceDir = Directory(p.join(tempRoot.path, '我的 書'));
      await sourceDir.create(recursive: true);
      final source = File(p.join(sourceDir.path, 'a b.epub'));
      final content = List<int>.generate(256, (i) => i % 251);
      await source.writeAsBytes(content);
      final baseDir = Directory(p.join(tempRoot.path, 'cache'));

      final cachedPath = await cacheWindowsBook(
        source.path,
        'instance-1',
        baseDir: baseDir,
      );

      expect(cachedPath, isNotNull);
      expect(p.basename(cachedPath!), 'current.epub');
      expect(await File(cachedPath).readAsBytes(), content);
      expect(p.isWithin(baseDir.path, cachedPath), isTrue);
    });

    test('cacheWindowsBook：同一本書用不同 instanceId 不互相覆蓋', () async {
      final source = File(p.join(tempRoot.path, 'sample.epub'));
      await source.writeAsBytes([1, 2, 3]);
      final baseDir = Directory(p.join(tempRoot.path, 'cache'));

      final first = await cacheWindowsBook(source.path, 'instance-1',
          baseDir: baseDir);
      final second = await cacheWindowsBook(source.path, 'instance-2',
          baseDir: baseDir);

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first, isNot(second));
      expect(await File(first!).readAsBytes(), [1, 2, 3]);
      expect(await File(second!).readAsBytes(), [1, 2, 3]);
    });

    test('cacheWindowsBook：來源不存在回 null', () async {
      final baseDir = Directory(p.join(tempRoot.path, 'cache'));

      final cachedPath = await cacheWindowsBook(
        p.join(tempRoot.path, 'missing.epub'),
        'instance-1',
        baseDir: baseDir,
      );

      expect(cachedPath, isNull);
    });
  });

  group('readWindowsBookBytes', () {
    test('readWindowsBookBytes：讀得到 /book/current.epub', () async {
      final bookDir = Directory(p.join(tempRoot.path, 'book'));
      await bookDir.create(recursive: true);
      await File(p.join(bookDir.path, 'current.epub')).writeAsBytes([7, 7]);

      final bytes = await readWindowsBookBytes('/book/current.epub', bookDir.path);

      expect(bytes, equals(Uint8List.fromList([7, 7])));
    });

    test('readWindowsBookBytes：/assets/foliate/main.js 回 null', () async {
      final bookDir = Directory(p.join(tempRoot.path, 'book'));
      await bookDir.create(recursive: true);

      final bytes = await readWindowsBookBytes(
        '/assets/foliate/main.js',
        bookDir.path,
      );

      expect(bytes, isNull);
    });

    test('readWindowsBookBytes：/book/../secret.txt 回 null', () async {
      final bookDir = Directory(p.join(tempRoot.path, 'book'));
      await bookDir.create(recursive: true);
      final secret = File(p.join(tempRoot.path, 'secret.txt'));
      await secret.writeAsString('secret');

      final bytes =
          await readWindowsBookBytes('/book/../secret.txt', bookDir.path);

      expect(bytes, isNull);
    });
  });

  group('windowsBookContentType', () {
    test('windowsBookContentType：.epub 與 .cbz 與未知副檔名各一個斷言', () {
      expect(windowsBookContentType('a.epub'), 'application/epub+zip');
      expect(windowsBookContentType('b.cbz'), 'application/vnd.comicbook+zip');
      expect(windowsBookContentType('c.xyz'), 'application/octet-stream');
    });
  });
}
