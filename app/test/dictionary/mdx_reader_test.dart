// MdxReader 薄封裝測試（epic-63 Issue 6a Task 3）。
//
// 測試資料全部是自製 fixture（app/test/fixtures/mdx/），由
// app/tool/make_test_mdx.py 產生；唯一例外是 tmp/dictionary/ 的真實字典，
// 檔案不存在時跳過（不進版控）。
import 'dart:io';
import 'dart:typed_data';

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

    test('StripKey=Yes：含空白與連字號的片語（I-4）', () async {
      // 檔內順序依「去空白標點、轉小寫」排序：ab < abomb < alacarte < apple，
      // 與原字串順序（a b < a la carte < a-bomb < apple）不同。
      final phrases = await MdxReader.open('$_fixtures/strip-phrases.mdx');
      addTearDown(phrases.close);

      for (final query in [
        'a la carte',
        'A LA CARTE',
        'alacarte',
        'a-bomb',
        'abomb',
        'apple',
        'a b',
        'ab',
      ]) {
        expect(
          await phrases.lookupAll(query),
          hasLength(1),
          reason: '查詢 "$query" 應命中一筆',
        );
      }
      expect((await phrases.lookupAll('a la carte')).single, contains('照菜單'));
      expect((await phrases.lookupAll('a-bomb')).single, contains('原子彈'));
      expect(await phrases.lookupAll('a lac'), isEmpty);
    });

    test('多鍵區塊：每一把鍵都查得到，重複鍵跨區塊全部回傳（I-5）', () async {
      final multi = await MdxReader.open('$_fixtures/multi-block.mdx');
      addTearDown(multi.close);

      expect(multi.meta.entryCount, 300);
      for (final i in [0, 1, 17, 119, 120, 121, 238, 239]) {
        final key = 'k${i.toString().padLeft(4, '0')}';
        final hits = await multi.lookupAll(key);
        expect(hits, ['<p>entry $i</p>'], reason: key);
      }
      // 大小寫折疊：K0100 等同 k0100。
      expect(await multi.lookupAll('K0100'), ['<p>entry 100</p>']);

      // 60 筆重複鍵跨好幾個鍵區塊與記錄區塊，順序與內容都要完整。
      final dups = await multi.lookupAll('dupkey');
      expect(dups, [
        for (var i = 0; i < 60; i++) '<p>dup-${i.toString().padLeft(3, '0')}</p>',
      ]);

      expect(await multi.lookupAll('k0240'), isEmpty);
      expect(await multi.lookupAll('zzz'), isEmpty);
      expect(await multi.lookupAll('a'), isEmpty);
    });

    test('多鍵區塊：sampleEntryBodies 依序跨記錄區塊取樣（I-5）', () async {
      final multi = await MdxReader.open('$_fixtures/multi-block.mdx');
      addTearDown(multi.close);

      // 排序後 dupkey 排在 k 開頭之前（'d' < 'k'），所以前 60 筆是 dup。
      final bodies = await multi.sampleEntryBodies(limit: 300);
      expect(bodies, hasLength(300));
      expect(bodies.first, '<p>dup-000</p>');
      expect(bodies[59], '<p>dup-059</p>');
      expect(bodies[60], '<p>entry 0</p>');
      expect(bodies.last, '<p>entry 239</p>');
    });
  });

  group('Encrypted 解析（I-2）', () {
    test('Encrypted="Yes" 視為記錄區塊加密 → encryptedRecords', () async {
      await expectLater(
        MdxReader.open('$_fixtures/encrypted-yes.mdx'),
        throwsA(_exceptionOfKind(MdxErrorKind.encryptedRecords)),
      );
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

    test('v1（1.2 版）字典通過，進度最後一筆 done == total（I-1）', () async {
      final reader = await MdxReader.open('$_fixtures/v1.mdx');
      addTearDown(reader.close);

      expect(reader.meta.entryCount, 50);
      final progress = <(int, int)>[];
      await reader.validateBlocks(
        onProgress: (done, total) => progress.add((done, total)),
      );
      expect(progress, isNotEmpty);
      expect(progress.last.$1, progress.last.$2);
      expect(await reader.lookupAll('相濡以沫'), hasLength(1));
    });

    test('v1 字典記錄區塊被截掉 → corrupt（I-1）', () async {
      final dir = Directory.systemTemp.createTempSync('mdx_v1_cut_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bytes = File('$_fixtures/v1.mdx').readAsBytesSync();
      final cut = File('${dir.path}/v1-cut.mdx')
        ..writeAsBytesSync(bytes.sublist(0, bytes.length - 80));

      final reader = await MdxReader.open(cut.path);
      addTearDown(reader.close);
      await expectLater(
        reader.validateBlocks(),
        throwsA(_exceptionOfKind(MdxErrorKind.corrupt)),
      );
    });

    test('v1 字典記錄區塊數亂掉 → corrupt，不做超大讀取（I-1）', () async {
      final dir = Directory.systemTemp.createTempSync('mdx_v1_count_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bytes = File('$_fixtures/v1.mdx').readAsBytesSync();
      final file = File('${dir.path}/v1-count.mdx')..writeAsBytesSync(bytes);

      final reader = await MdxReader.open(file.path);
      addTearDown(reader.close);

      // v1 版面：檔頭長度(4)＋檔頭＋checksum(4)＝鍵區開頭；鍵區標頭 4 個
      // 4 位元組數字，第 3、4 個是資訊大小與鍵區塊大小。
      final view = ByteData.sublistView(bytes);
      final keyOffset = view.getUint32(0) + 8;
      final recordOffset =
          keyOffset +
          16 +
          view.getUint32(keyOffset + 8) +
          view.getUint32(keyOffset + 12);
      // 記錄區塊數改成 0x7fffffff。
      final patched = Uint8List.fromList(bytes);
      ByteData.sublistView(patched).setUint32(recordOffset, 0x7fffffff);
      file.writeAsBytesSync(patched);

      await expectLater(
        reader.validateBlocks(),
        throwsA(_exceptionOfKind(MdxErrorKind.corrupt)),
      );
    });

    test('v2 字典記錄區塊數為 2^60 → corrupt，不做超大讀取', () async {
      final dir = Directory.systemTemp.createTempSync('mdx_v2_count_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bytes = File('$_fixtures/zlib.mdx').readAsBytesSync();
      final file = File('${dir.path}/v2-count.mdx')..writeAsBytesSync(bytes);

      final reader = await MdxReader.open(file.path);
      addTearDown(reader.close);

      // v2 版面：鍵區標頭 5 個 8 位元組數字＋4 位元組 checksum；
      // 第 4、5 個是資訊大小與鍵區塊大小。
      final view = ByteData.sublistView(bytes);
      final keyOffset = view.getUint32(0) + 8;
      final recordOffset =
          keyOffset +
          44 +
          view.getUint64(keyOffset + 24) +
          view.getUint64(keyOffset + 32);
      final patched = Uint8List.fromList(bytes);
      ByteData.sublistView(patched).setUint64(recordOffset, 1 << 60);
      file.writeAsBytesSync(patched);

      await expectLater(
        reader.validateBlocks(),
        throwsA(_exceptionOfKind(MdxErrorKind.corrupt)),
      );
    });

    test('多區塊字典逐塊通過（I-5）', () async {
      final reader = await MdxReader.open('$_fixtures/multi-block.mdx');
      addTearDown(reader.close);

      var lastTotal = 0;
      await reader.validateBlocks(onProgress: (done, total) => lastTotal = total);
      expect(lastTotal, greaterThan(5));
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

  group('readResource', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mdx_images_test_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    void copyFixture(String name, [String? targetName]) {
      final bytes = File('$_fixtures/$name').readAsBytesSync();
      final target = File('${tempDir.path}/${targetName ?? name}');
      target.writeAsBytesSync(bytes);
    }

    test('fixture 的圖片是肉眼看得到的尺寸（至少 32×32），不是 1×1', () async {
      copyFixture('images.mdx');
      copyFixture('images.mdd');

      final reader = await MdxReader.open('${tempDir.path}/images.mdx');
      addTearDown(reader.close);

      for (final path in ['pic/a%20b.png', 'pic/sub/c.png']) {
        final res = await reader.readResource('https://dict.local/$path');
        expect(res, isNotNull, reason: path);
        // PNG 的 IHDR 在第 16 到 23 位元組：寬、高各 4 位元組（大端序）。
        final data = ByteData.sublistView(res!.bytes);
        expect(data.getUint32(16), greaterThanOrEqualTo(32), reason: '$path 寬度');
        expect(data.getUint32(20), greaterThanOrEqualTo(32), reason: '$path 高度');
      }
    });

    test('讀到圖片與子目錄', () async {
      copyFixture('images.mdx');
      copyFixture('images.mdd');

      final reader = await MdxReader.open('${tempDir.path}/images.mdx');
      addTearDown(reader.close);

      final res1 = await reader.readResource('https://dict.local/pic/a%20b.png');
      expect(res1, isNotNull);
      expect(res1!.contentType, 'image/png');
      expect(
        res1.bytes.sublist(0, 8),
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      );

      final res2 = await reader.readResource('https://dict.local/pic/sub/c.png');
      expect(res2, isNotNull);
      expect(res2!.contentType, 'image/png');
      expect(
        res2.bytes.sublist(0, 8),
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      );
    });

    test('找不到回 null', () async {
      copyFixture('images.mdx');
      copyFixture('images.mdd');

      final reader = await MdxReader.open('${tempDir.path}/images.mdx');
      addTearDown(reader.close);

      expect(
        await reader.readResource('https://dict.local/pic/none.png'),
        isNull,
      );
    });

    test('不支援的副檔名回 null', () async {
      copyFixture('images.mdx');
      copyFixture('images.mdd');

      final reader = await MdxReader.open('${tempDir.path}/images.mdx');
      addTearDown(reader.close);

      expect(
        await reader.readResource('https://dict.local/snd/x.mp3'),
        isNull,
      );
    });

    test('沒有 mdd 的字典：readResource 回 null，lookupAll 照常', () async {
      copyFixture('images.mdx');

      final reader = await MdxReader.open('${tempDir.path}/images.mdx');
      addTearDown(reader.close);

      expect(
        await reader.readResource('https://dict.local/pic/a%20b.png'),
        isNull,
      );
      final hits = await reader.lookupAll('pic');
      expect(hits, hasLength(1));
    });

    test('mdd 壞檔不讓字典失敗：open 仍成功、readResource 回 null', () async {
      copyFixture('images.mdx');
      final mddBytes = File('$_fixtures/images.mdd').readAsBytesSync();
      File('${tempDir.path}/images.mdd')
          .writeAsBytesSync(mddBytes.sublist(0, mddBytes.length ~/ 2));

      final reader = await MdxReader.open('${tempDir.path}/images.mdx');
      addTearDown(reader.close);

      expect(
        await reader.readResource('https://dict.local/pic/a%20b.png'),
        isNull,
      );
      expect(await reader.lookupAll('pic'), hasLength(1));
    });

    test('主檔名不分大小寫配對：Images.MDD 配 images.mdx', () async {
      copyFixture('images.mdx');
      copyFixture('images.mdd', 'Images.MDD');

      final reader = await MdxReader.open('${tempDir.path}/images.mdx');
      addTearDown(reader.close);

      final res = await reader.readResource('https://dict.local/pic/a%20b.png');
      expect(res, isNotNull);
      expect(res!.contentType, 'image/png');
    });

    test('超過上限回 null，未超過時可讀取', () async {
      copyFixture('images.mdx');
      copyFixture('images.mdd');

      final reader = await MdxReader.open('${tempDir.path}/images.mdx');
      addTearDown(reader.close);

      final resLimit = await reader.readResource(
        'https://dict.local/pic/a%20b.png',
        maxBytes: 1,
      );
      expect(resLimit, isNull);

      final resNormal = await reader.readResource(
        'https://dict.local/pic/a%20b.png',
      );
      expect(resNormal, isNotNull);
    });

    test('close 之後 readResource 回 null、不丟例外', () async {
      copyFixture('images.mdx');
      copyFixture('images.mdd');

      final reader = await MdxReader.open('${tempDir.path}/images.mdx');
      await reader.close();

      expect(
        await reader.readResource('https://dict.local/pic/a%20b.png'),
        isNull,
      );
    });
  });
}
