// MdxReaderPool 測試（epic-63 Issue 6a Task 6）。
//
// 全部注入假 opener，不碰真實檔案；關閉行為由假 reader 計數。
import 'dart:async';

import 'package:elinkbook/dictionary/mdx_resource.dart';
import 'package:elinkbook/dictionary/storage/mdx_reader.dart';
import 'package:elinkbook/dictionary/storage/mdx_reader_pool.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeReader implements MdxReader {
  _FakeReader(this.path);

  final String path;
  int closed = 0;

  @override
  final MdxMeta meta = const MdxMeta(
    title: '',
    description: null,
    keyCaseSensitive: true,
    stripKey: false,
    encrypted: 0,
    entryCount: 0,
  );

  @override
  String displayName(String fileName) => fileName;

  @override
  Future<List<String>> lookupAll(String key) async => const [];

  @override
  Future<List<String>> sampleEntryBodies({int limit = 200}) async => const [];

  @override
  Future<void> validateBlocks({
    void Function(int done, int total)? onProgress,
  }) async {}

  @override
  Future<MdxResource?> readResource(
    String url, {
    int maxBytes = kMdxResourceMaxBytes,
  }) async =>
      null;

  @override
  Future<void> close() async => closed++;
}

/// 記錄每次開啟，可設定下一次失敗。
class _Opener {
  final List<String> opened = [];
  final Map<String, _FakeReader> readers = {};
  bool failNext = false;

  Future<MdxReader> open(String path) async {
    opened.add(path);
    if (failNext) {
      failNext = false;
      throw const MdxException(MdxErrorKind.notFound);
    }
    return readers[path] = _FakeReader(path);
  }
}

void main() {
  late _Opener opener;
  late MdxReaderPool pool;

  setUp(() {
    opener = _Opener();
    pool = MdxReaderPool(opener: opener.open);
  });

  tearDown(() => pool.closeAll());

  test('同一來源重複 acquire 只開一次，回傳同一個 reader', () async {
    final first = await pool.acquire('a', 'a.mdx');
    final second = await pool.acquire('a', 'a.mdx');

    expect(identical(first, second), isTrue);
    expect(opener.opened, ['a.mdx']);
  });

  test('並發 acquire 同一來源也只開一次', () async {
    final results = await Future.wait([
      pool.acquire('a', 'a.mdx'),
      pool.acquire('a', 'a.mdx'),
    ]);

    expect(identical(results[0], results[1]), isTrue);
    expect(opener.opened, ['a.mdx']);
  });

  test('超過 maxOpen 時關閉最久未用的 reader', () async {
    await pool.acquire('a', 'a.mdx');
    await pool.acquire('b', 'b.mdx');
    // 再碰一次 a，讓 b 成為最久未用。
    await pool.acquire('a', 'a.mdx');
    await pool.acquire('c', 'c.mdx');

    expect(opener.readers['b.mdx']!.closed, 1);
    expect(opener.readers['a.mdx']!.closed, 0);
    expect(opener.readers['c.mdx']!.closed, 0);
  });

  test('evict 關閉並移除；之後再 acquire 會重開', () async {
    await pool.acquire('a', 'a.mdx');

    await pool.evict('a');

    expect(opener.readers['a.mdx']!.closed, 1);
    await pool.acquire('a', 'a.mdx');
    expect(opener.opened, ['a.mdx', 'a.mdx']);
  });

  test('evict 不存在的來源不丟例外', () async {
    await pool.evict('nope');
  });

  test('closeAll 全部關閉，之後 acquire 會重開', () async {
    await pool.acquire('a', 'a.mdx');
    await pool.acquire('b', 'b.mdx');

    await pool.closeAll();

    expect(opener.readers['a.mdx']!.closed, 1);
    expect(opener.readers['b.mdx']!.closed, 1);

    await pool.acquire('a', 'a.mdx');
    expect(opener.opened, ['a.mdx', 'b.mdx', 'a.mdx']);
  });

  test('開啟失敗不記住，下一次 acquire 會重試', () async {
    opener.failNext = true;

    await expectLater(
      pool.acquire('a', 'a.mdx'),
      throwsA(isA<MdxException>()),
    );

    final reader = await pool.acquire('a', 'a.mdx');
    expect(reader, isA<_FakeReader>());
    expect(opener.opened, ['a.mdx', 'a.mdx']);
  });

  test('查詢進行中 evict 會等查詢結束才關檔', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final using = pool.use('a', 'a.mdx', (reader) async {
      started.complete();
      await gate.future;
      return reader;
    });
    await started.future;

    final fake = opener.readers['a.mdx']!;
    var evicted = false;
    final evicting = pool.evict('a').then((_) => evicted = true);
    await Future<void>.delayed(Duration.zero);

    expect(evicted, isFalse, reason: '查詢還在跑，不該先關檔');
    expect(fake.closed, 0);

    gate.complete();
    await using;
    await evicting;

    expect(fake.closed, 1);
  });

  test('LRU 淘汰也不會關掉正在查詢的 reader', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final using = pool.use('a', 'a.mdx', (reader) async {
      started.complete();
      await gate.future;
      return reader;
    });
    await started.future;
    await pool.acquire('b', 'b.mdx');

    // 開啟 c 會觸發 trim；a 雖然最久沒用，但正在查詢，只能等。
    final openingC = pool.acquire('c', 'c.mdx');
    await Future<void>.delayed(Duration.zero);
    expect(opener.readers['a.mdx']!.closed, 0);

    gate.complete();
    await using;
    await openingC;

    expect(opener.readers['a.mdx']!.closed, 1);
    expect(opener.readers['c.mdx']!.closed, 0);
  });
}
