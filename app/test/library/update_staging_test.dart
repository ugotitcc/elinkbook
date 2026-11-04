import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:elinkbook/library/update_staging.dart';

void main() {
  group('update_staging', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('update_staging_test_');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('常數名稱為 update_staging', () {
      expect(kUpdateStagingFolderName, 'update_staging');
    });

    test('清掃：目錄含 3 個檔案與 1 個含檔案的子目錄，清掃後目錄內為空且目錄仍存在', () async {
      final stagingDir = Directory(p.join(tempRoot.path, kUpdateStagingFolderName));
      await stagingDir.create();

      final file1 = File(p.join(stagingDir.path, 'f1.tmp'))..writeAsStringSync('1');
      final file2 = File(p.join(stagingDir.path, 'f2.tmp'))..writeAsStringSync('2');
      final file3 = File(p.join(stagingDir.path, 'f3.tmp'))..writeAsStringSync('3');

      final subDir = Directory(p.join(stagingDir.path, 'sub'))..createSync();
      final subFile = File(p.join(subDir.path, 'sub.tmp'))..writeAsStringSync('sub');

      expect(stagingDir.listSync(), hasLength(4));

      await sweepUpdateStaging(tempRoot);

      expect(await file1.exists(), isFalse);
      expect(await file2.exists(), isFalse);
      expect(await file3.exists(), isFalse);
      expect(await subFile.exists(), isFalse);
      expect(await subDir.exists(), isFalse);
      expect(stagingDir.listSync(), isEmpty);
    });

    test('目錄不存在：不拋例外且不建立目錄', () async {
      final stagingDir = Directory(p.join(tempRoot.path, kUpdateStagingFolderName));
      expect(await stagingDir.exists(), isFalse);

      await expectLater(sweepUpdateStaging(tempRoot), completes);
      expect(await stagingDir.exists(), isFalse);
    });

    test('空目錄：不拋例外且目錄保持為空', () async {
      final stagingDir = Directory(p.join(tempRoot.path, kUpdateStagingFolderName));
      await stagingDir.create();

      await expectLater(sweepUpdateStaging(tempRoot), completes);
      expect(await stagingDir.exists(), isTrue);
      expect(stagingDir.listSync(), isEmpty);
    });

    test('路徑存在但為一般檔案而非目錄：不拋例外且檔案不被刪除（Review Focus 7）', () async {
      final stagingFile = File(p.join(tempRoot.path, kUpdateStagingFolderName));
      await stagingFile.writeAsString('not a directory');

      await expectLater(sweepUpdateStaging(tempRoot), completes);
      expect(await stagingFile.exists(), isTrue);
      expect(await stagingFile.readAsString(), 'not a directory');
    });
  });
}
