// MdxReader 薄封裝測試（epic-63 Issue 6a Task 3）。
//
// 測試資料全部是自製 fixture（app/test/fixtures/mdx/），由
// app/tool/make_test_mdx.py 產生；唯一例外是 tmp/dictionary/ 的真實字典，
// 檔案不存在時跳過（不進版控）。
import 'dart:io';

import 'package:elinkbook/dictionary/storage/mdx_reader.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtures = 'test/fixtures/mdx';

Matcher _exceptionOfKind(MdxErrorKind kind) =>
    isA<MdxException>().having((e) => e.kind, 'kind', kind);

void main() {
  group('open 與 meta', () {
    test('正常檔：entryCount 與標頭欄位', () async {
      final reader = await MdxReader.open('$_fixtures/zlib.mdx');
      addTearDown(reader.close);

      expect(reader.meta.entryCount, 50);
      expect(reader.meta.title, 'Test fixture');
      expect(reader.meta.description, isNotNull);
      expect(reader.meta.keyCaseSensitive, isFalse);
      expect(reader.meta.stripKey, isFalse);
      expect(reader.meta.encrypted, 0);
    });

    test('StripKey 與 KeyCaseSensitive 旗標如實反映標頭', () async {
      final strip = await MdxReader.open('$_fixtures/strip-key.mdx');
      addTearDown(strip.close);
      expect(strip.meta.stripKey, isTrue);

      final caseSensitive = await MdxReader.open(
        '$_fixtures/case-sensitive.mdx',
      );
      addTearDown(caseSensitive.close);
      expect(caseSensitive.meta.keyCaseSensitive, isTrue);
    });

    test('檔案不存在 → notFound', () async {
      await expectLater(
        MdxReader.open('$_fixtures/does-not-exist.mdx'),
        throwsA(_exceptionOfKind(MdxErrorKind.notFound)),
      );
    });

    test('截斷檔在 10 秒內 → corrupt，且之後仍可開啟好檔', () async {
      await expectLater(
        MdxReader.open(
          '$_fixtures/truncated.mdx',
        ).timeout(const Duration(seconds: 10)),
        throwsA(_exceptionOfKind(MdxErrorKind.corrupt)),
      );

      // 失敗的 open 不得留下半初始化狀態或佔住檔案。
      final reader = await MdxReader.open('$_fixtures/zlib.mdx');
      addTearDown(reader.close);
      expect(reader.meta.entryCount, 50);
    });
  });

  group('lookupAll', () {
    late MdxReader reader;

    setUp(() async {
      reader = await MdxReader.open('$_fixtures/zlib.mdx');
    });

    tearDown(() async {
      await reader.close();
    });

    test('命中回傳 HTML；查無回傳空清單', () async {
      final hits = await reader.lookupAll('相濡以沫');
      expect(hits, hasLength(1));
      expect(hits.single, contains('相濡以沫'));
      expect(hits.single, contains('比喻同處困境'));

      expect(await reader.lookupAll('nope'), isEmpty);
    });

    test('空字串與純空白不丟例外', () async {
      expect(await reader.lookupAll(''), isEmpty);
      expect(await reader.lookupAll('   '), isEmpty);
      expect(await reader.lookupAll('\t\n'), isEmpty);
    });

    test('KeyCaseSensitive=No：APPLE 查得到 apple 的兩筆記錄', () async {
      final hits = await reader.lookupAll('APPLE');
      expect(hits, hasLength(2));
      expect(hits.join(), contains('蘋果公司'));

      final exact = await reader.lookupAll('apple');
      expect(exact, hasLength(2));
    });

    test('KeyCaseSensitive=Yes：APPLE 查不到 apple', () async {
      final caseSensitive = await MdxReader.open(
        '$_fixtures/case-sensitive.mdx',
      );
      addTearDown(caseSensitive.close);

      expect(await caseSensitive.lookupAll('APPLE'), isEmpty);
      expect(await caseSensitive.lookupAll('apple'), hasLength(1));
    });

    test('StripKey=Yes：去空白與標點後查得到', () async {
      final strip = await MdxReader.open('$_fixtures/strip-key.mdx');
      addTearDown(strip.close);

      expect(await strip.lookupAll(' 一 '), hasLength(1));
      expect(await strip.lookupAll('一，'), hasLength(1));
      expect(await strip.lookupAll('一'), hasLength(1));
      // 去除後為空字串，不是查「空白鍵」。
      expect(await strip.lookupAll(' ， 。 '), isEmpty);
    });
  });

  group('displayName', () {
    test('正常 Title 原樣回傳', () async {
      final reader = await MdxReader.open('$_fixtures/zlib.mdx');
      addTearDown(reader.close);
      expect(reader.displayName('隨便的檔名.mdx'), 'Test fixture');
    });

    test('佔位 Title → Description 第一行（去標籤）', () async {
      final reader = await MdxReader.open('$_fixtures/placeholder-title.mdx');
      addTearDown(reader.close);

      expect(reader.meta.title, 'Title (No HTML code allowed)');
      expect(reader.displayName('ignored.mdx'), '測試辭典');
    });

    test('Description 也空 → 檔名不含副檔名', () async {
      final reader = await MdxReader.open(
        '$_fixtures/placeholder-title-empty.mdx',
      );
      addTearDown(reader.close);

      expect(reader.displayName('a/b/未命名字典.mdx'), '未命名字典');
    });
  });

  group('validateBlocks', () {
    test('zlib.mdx 通過，進度回報最後一筆 done == total', () async {
      final reader = await MdxReader.open('$_fixtures/zlib.mdx');
      addTearDown(reader.close);

      final progress = <(int, int)>[];
      await reader.validateBlocks(
        onProgress: (done, total) => progress.add((done, total)),
      );

      expect(progress, isNotEmpty);
      expect(progress.last.$1, progress.last.$2);
      expect(progress.last.$2, greaterThan(0));
      // 進度必須單調遞增且不超過總數。
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i].$1, greaterThan(progress[i - 1].$1));
        expect(progress[i].$1, lessThanOrEqualTo(progress[i].$2));
      }
    });

    test('假 LZO 區塊 → unsupportedCompression', () async {
      final reader = await MdxReader.open('$_fixtures/fake-lzo.mdx');
      addTearDown(reader.close);

      await expectLater(
        reader.validateBlocks(),
        throwsA(_exceptionOfKind(MdxErrorKind.unsupportedCompression)),
      );
    });

    test('記錄區塊被截掉 → corrupt（open 仍成功）', () async {
      final reader = await MdxReader.open('$_fixtures/cut-records.mdx');
      addTearDown(reader.close);

      await expectLater(
        reader.validateBlocks(),
        throwsA(_exceptionOfKind(MdxErrorKind.corrupt)),
      );
    });
  });

  group('真實字典（檔案不存在時跳過）', () {
    const real = '../tmp/dictionary/教育部重編國語辭典.mdx';

    test('Encrypted=2 可開啟並查詢', () async {
      if (!File(real).existsSync()) {
        markTestSkipped('找不到 $real');
        return;
      }
      final reader = await MdxReader.open(real);
      addTearDown(reader.close);

      expect(reader.meta.encrypted, 2);
      expect(reader.meta.entryCount, 163085);
      final hits = await reader.lookupAll('相濡以沫');
      expect(hits, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
