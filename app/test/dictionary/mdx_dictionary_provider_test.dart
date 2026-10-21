// MdxDictionaryProvider 測試（epic-63 Issue 6a Task 6）。
import 'dart:convert';
import 'dart:io';

import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/dictionary_source.dart';
import 'package:elinkbook/dictionary/models/lookup_request.dart';
import 'package:elinkbook/dictionary/models/lookup_result.dart';
import 'package:elinkbook/dictionary/providers/mdx_dictionary_provider.dart';
import 'package:elinkbook/dictionary/storage/mdx_reader_pool.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtures = 'test/fixtures/mdx';

DictionarySource _source(String fileName, {String sourceLang = 'en'}) =>
    DictionarySource(
      id: 'mdx-$fileName',
      name: 'MDX $fileName',
      format: DictionaryFormat.mdx,
      sourceLang: sourceLang,
      targetLang: 'zh-Hant',
      priority: 0,
      enabled: true,
      storagePath: '$_fixtures/$fileName',
      entryCount: 0,
      licenseNote: '',
      importedAt: DateTime.utc(2026, 10, 19),
    );

void main() {
  late MdxReaderPool pool;

  setUp(() {
    pool = MdxReaderPool();
  });

  tearDown(() => pool.closeAll());

  MdxDictionaryProvider provider(String fileName, {String lang = 'en'}) =>
      MdxDictionaryProvider(
        pool: pool,
        source: _source(fileName, sourceLang: lang),
      );

  test('查得到：found、bodyKind 為 html、詞頭是命中的候選', () async {
    final outcome = await provider('zlib.mdx').lookup(
      const LookupRequest('apple'),
    );

    expect(outcome.status, OutcomeStatus.found);
    expect(outcome.providerId, 'mdx-zlib.mdx');
    expect(outcome.entries, isNotEmpty);
    expect(outcome.entries.first.bodyKind, EntryBodyKind.html);
    expect(outcome.entries.first.headword, 'apple');
    expect(outcome.entries.first.sourceId, 'mdx-zlib.mdx');
  });

  test('英文候選鏈：大寫與變音符號仍命中', () async {
    final outcome = await provider('zlib.mdx').lookup(
      const LookupRequest('CAFÉ'),
    );

    expect(outcome.status, OutcomeStatus.found);
    // KeyCaseSensitive=No 時第一個候選（原樣大寫）就會命中。
    expect(outcome.entries.single.headword, 'CAFÉ');
    expect(outcome.entries.single.body, contains('café'));
  });

  test('查無 → notFound', () async {
    final outcome = await provider('zlib.mdx').lookup(
      const LookupRequest('zzzznotfound'),
    );

    expect(outcome.status, OutcomeStatus.notFound);
    expect(outcome.entries, isEmpty);
    expect(outcome.errorCode, isNull);
  });

  test('不支援的壓縮 → failed，不丟例外', () async {
    final outcome = await provider('fake-lzo.mdx').lookup(
      const LookupRequest('apple'),
    );

    expect(outcome.status, OutcomeStatus.failed);
    expect(outcome.errorCode, 'unsupportedCompression');
    expect(outcome.entries, isEmpty);
  });

  test('同一把鍵的多筆記錄全部回傳', () async {
    // zlib.mdx 的 apple 與 Apple 在 KeyCaseSensitive=No 下是同一把鍵。
    final outcome = await provider('zlib.mdx').lookup(
      const LookupRequest('apple'),
    );

    expect(outcome.entries, hasLength(2));
    expect(
      outcome.entries.map((e) => e.body),
      containsAll([contains('蘋果'), contains('蘋果公司')]),
    );
  });

  test('KeyCaseSensitive=Yes 時保留大小寫候選：Apple 仍命中小寫 apple', () async {
    final source = _source('case-sensitive.mdx');
    expect(source.id, 'mdx-case-sensitive.mdx');
    final outcome = await MdxDictionaryProvider(pool: pool, source: source)
        .lookup(const LookupRequest('Apple'));

    expect(outcome.status, OutcomeStatus.found);
    expect(outcome.entries.single.headword, 'apple');
  });

  group('CSS 內嵌整合測試', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('elinkbook_mdx_prov_');
    });

    tearDown(() async {
      await pool.closeAll();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('在暫存目錄有 .css 時，詞條 entry.body 內嵌該 CSS', () async {
      await File('$_fixtures/html.mdx').copy('${tempDir.path}/html.mdx');
      await File('${tempDir.path}/ghychyz.css')
          .writeAsString('body { color: #111; }');

      final source = DictionarySource(
        id: 'mdx-html',
        name: 'MDX HTML',
        format: DictionaryFormat.mdx,
        sourceLang: 'en',
        targetLang: 'zh-Hant',
        priority: 0,
        enabled: true,
        storagePath: '${tempDir.path}/html.mdx',
        entryCount: 3,
        licenseNote: '',
        importedAt: DateTime.utc(2026, 10, 19),
      );

      final p = MdxDictionaryProvider(pool: pool, source: source);
      final outcome = await p.lookup(const LookupRequest('apple'));

      expect(outcome.status, OutcomeStatus.found);
      expect(outcome.entries, isNotEmpty);
      final body = outcome.entries.first.body;
      expect(body, contains('<style>body { color: #111; }</style>'));
      expect(body, isNot(contains('<link')));
    });

    test('目錄沒有 .css 時 <link> 被移除、查詢仍 found', () async {
      await File('$_fixtures/html.mdx').copy('${tempDir.path}/html.mdx');

      final source = DictionarySource(
        id: 'mdx-html',
        name: 'MDX HTML',
        format: DictionaryFormat.mdx,
        sourceLang: 'en',
        targetLang: 'zh-Hant',
        priority: 0,
        enabled: true,
        storagePath: '${tempDir.path}/html.mdx',
        entryCount: 3,
        licenseNote: '',
        importedAt: DateTime.utc(2026, 10, 19),
      );

      final p = MdxDictionaryProvider(pool: pool, source: source);
      final outcome = await p.lookup(const LookupRequest('apple'));

      expect(outcome.status, OutcomeStatus.found);
      expect(outcome.entries, isNotEmpty);
      final body = outcome.entries.first.body;
      expect(body, isNot(contains('<link')));
      expect(body, isNot(contains('<style>body { color: #111; }</style>')));
    });

    test('非 UTF-8 的 css 不中斷查詢（Big5／GBK 位元組），查詢仍 found', () async {
      await File('$_fixtures/html.mdx').copy('${tempDir.path}/html.mdx');
      await File('${tempDir.path}/ghychyz.css').writeAsBytes([
        ...utf8.encode('body { content: "'),
        0xb4,
        0xfa,
        0xb8,
        0xd5,
        ...utf8.encode('"; }'),
      ]);

      final source = DictionarySource(
        id: 'mdx-html',
        name: 'MDX HTML',
        format: DictionaryFormat.mdx,
        sourceLang: 'en',
        targetLang: 'zh-Hant',
        priority: 0,
        enabled: true,
        storagePath: '${tempDir.path}/html.mdx',
        entryCount: 3,
        licenseNote: '',
        importedAt: DateTime.utc(2026, 10, 19),
      );

      final p = MdxDictionaryProvider(pool: pool, source: source);
      final outcome = await p.lookup(const LookupRequest('apple'));

      expect(outcome.status, OutcomeStatus.found);
      expect(outcome.entries, isNotEmpty);
      final body = outcome.entries.first.body;
      expect(body, contains('<style>'));
      expect(body, isNot(contains('<link')));
    });
  });
}
