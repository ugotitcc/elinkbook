// app/test/dictionary/dictionary_store_test.dart
import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/dictionary_source.dart';
import 'package:elinkbook/dictionary/storage/dictionary_database.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DictionarySource _source(
  String id, {
  int priority = 0,
  bool enabled = true,
  DateTime? importedAt,
}) =>
    DictionarySource(
      id: id,
      name: '字典 $id',
      format: DictionaryFormat.jsonCsv,
      sourceLang: 'en',
      targetLang: 'zh-Hant',
      priority: priority,
      enabled: enabled,
      storagePath: '',
      entryCount: 3,
      licenseNote: 'CC BY-SA 4.0',
      importedAt: importedAt ?? DateTime.utc(2026, 10, 19, 8),
    );

DictionaryEntry _entry(String sourceId, String headword, {String body = '釋義'}) =>
    DictionaryEntry(
      sourceId: sourceId,
      headword: headword,
      body: body,
      bodyKind: EntryBodyKind.plainText,
    );

void main() {
  late Database db;
  late DictionaryStore store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await DictionaryDatabase.open(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    store = DictionaryStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> entryRowCount() async {
    final rows = await db.rawQuery('SELECT count(*) AS c FROM dictionary_entries');
    return rows.single['c'] as int;
  }

  group('來源', () {
    test('寫入來源後可完整讀回', () async {
      final source = DictionarySource(
        id: 'a',
        name: '英漢字典',
        format: DictionaryFormat.cedict,
        sourceLang: 'zh',
        targetLang: 'en',
        priority: 5,
        enabled: false,
        storagePath: '/data/a.mdx',
        entryCount: 42,
        licenseNote: '自用',
        importedAt: DateTime.utc(2026, 10, 19, 8, 30),
      );
      await store.insertSource(source);

      final read = await store.getSource('a');
      expect(read, isNotNull);
      expect(read!.name, '英漢字典');
      expect(read.format, DictionaryFormat.cedict);
      expect(read.sourceLang, 'zh');
      expect(read.targetLang, 'en');
      expect(read.priority, 5);
      expect(read.enabled, isFalse);
      expect(read.storagePath, '/data/a.mdx');
      expect(read.entryCount, 42);
      expect(read.licenseNote, '自用');
      expect(read.importedAt.isAtSameMomentAs(source.importedAt), isTrue);
    });

    test('本地時區的 importedAt 讀回後是同一時刻且為 UTC', () async {
      final local = DateTime.now();
      await store.insertSource(_source('a', importedAt: local));

      final read = await store.getSource('a');
      expect(read!.importedAt.isUtc, isTrue);
      // 儲存精度為毫秒（見下一個測試），所以比對毫秒。
      expect(
        read.importedAt.millisecondsSinceEpoch,
        local.millisecondsSinceEpoch,
      );
    });

    test('imported_at 固定存成毫秒精度，文字排序才與時間順序一致', () async {
      // 微秒不為 0 時 toIso8601String 會輸出 6 位小數，與 3 位小數的字串
      // 混在一起做文字排序會反（".123Z" 排在 ".123456Z" 之後）。
      await store.insertSource(
        _source('a', importedAt: DateTime.utc(2026, 10, 19, 8, 0, 0, 123, 456)),
      );

      final rows = await db.query('dictionary_sources', columns: ['imported_at']);
      expect(
        rows.single['imported_at'],
        matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$')),
      );
    });

    test('資料庫中 storage_path 與 license_note 為 NULL 時讀回空字串', () async {
      await db.insert('dictionary_sources', {
        'id': 'raw',
        'name': '裸資料',
        'format': 'jsonCsv',
        'source_lang': 'en',
        'target_lang': 'zh-Hant',
        'priority': 0,
        'imported_at': DateTime.utc(2026, 10, 19).toIso8601String(),
      });

      final read = await store.getSource('raw');
      expect(read!.storagePath, '');
      expect(read.licenseNote, '');
    });

    test('getSource 找得到回傳來源，找不到回傳 null', () async {
      await store.insertSource(_source('a'));
      expect((await store.getSource('a'))!.id, 'a');
      expect(await store.getSource('missing'), isNull);
    });

    test('依優先順序列出，數字小者在前，相同時依匯入時間再依 id', () async {
      await store.insertSource(_source('c', priority: 3));
      await store.insertSource(_source('a', priority: 1));
      await store.insertSource(_source('b', priority: 2));
      await store.insertSource(
        _source('e', priority: 2, importedAt: DateTime.utc(2026, 10, 19, 9)),
      );
      await store.insertSource(_source('d', priority: 2));

      final ids = (await store.listSources()).map((s) => s.id).toList();
      expect(ids, ['a', 'b', 'd', 'e', 'c']);
    });

    test('enabledOnly 只回傳啟用的來源', () async {
      await store.insertSource(_source('on'));
      await store.insertSource(_source('off', enabled: false));

      expect(
        (await store.listSources(enabledOnly: true)).map((s) => s.id),
        ['on'],
      );
      expect((await store.listSources()).length, 2);
    });

    test('setEnabled 與 setPriority 會更新並影響排序', () async {
      await store.insertSource(_source('a', priority: 1));
      await store.insertSource(_source('b', priority: 2));

      await store.setPriority('b', 0);
      await store.setEnabled('a', false);

      expect((await store.listSources()).map((s) => s.id), ['b', 'a']);
      expect((await store.getSource('a'))!.enabled, isFalse);
      expect(
        (await store.listSources(enabledOnly: true)).map((s) => s.id),
        ['b'],
      );
    });

    test('重複的來源 id 寫入失敗，且不留下半筆', () async {
      await store.insertSource(_source('a'));

      await expectLater(
        store.insertSource(_source('a', priority: 9)),
        throwsA(isA<DatabaseException>()),
      );

      final sources = await store.listSources();
      expect(sources.length, 1);
      expect(sources.single.priority, 0);
    });
  });

  group('詞條', () {
    setUp(() async {
      await store.insertSource(_source('s1'));
      await store.insertSource(_source('s2'));
    });

    test('寫入詞條並以 headword_norm 查詢，保留原詞頭', () async {
      await store.insertEntries([_entry('s1', 'Run')]);

      for (final query in ['run', 'RUN', 'Run']) {
        final hits = await store.lookup('s1', query);
        expect(hits.length, 1, reason: query);
        expect(hits.single.headword, 'Run');
      }
    });

    test('查詢詞有前後空白也命中', () async {
      await store.insertEntries([_entry('s1', 'Run')]);
      expect((await store.lookup('s1', ' Run ')).length, 1);
    });

    test('同一 headword_norm 多筆全回傳，依 id 排序', () async {
      await store.insertEntries([
        _entry('s1', 'IT', body: '資訊科技'),
        _entry('s1', 'it', body: '它'),
      ]);

      final hits = await store.lookup('s1', 'it');
      expect(hits.map((e) => e.headword), ['IT', 'it']);
      expect(hits.map((e) => e.body), ['資訊科技', '它']);
    });

    test('只查指定來源', () async {
      await store.insertEntries([
        _entry('s1', 'run', body: '甲'),
        _entry('s2', 'run', body: '乙'),
      ]);

      final hits = await store.lookup('s2', 'run');
      expect(hits.single.body, '乙');
    });

    test('空字串與純空白查詢回傳空清單', () async {
      await store.insertEntries([_entry('s1', 'run'), _entry('s1', 'ran')]);

      expect(await store.lookup('s1', ''), isEmpty);
      expect(await store.lookup('s1', '   '), isEmpty);
    });

    test('可選欄位 pronunciation 與 partOfSpeech 原樣存取', () async {
      await store.insertEntries([
        const DictionaryEntry(
          sourceId: 's1',
          headword: '繁體',
          pronunciation: 'pin1 yin1',
          partOfSpeech: 'n.',
          body: '<b>釋義</b>',
          bodyKind: EntryBodyKind.html,
        ),
      ]);

      final hit = (await store.lookup('s1', '繁體')).single;
      expect(hit.pronunciation, 'pin1 yin1');
      expect(hit.partOfSpeech, 'n.');
      expect(hit.bodyKind, EntryBodyKind.html);
    });

    test('SQL 特殊字元、CJK 與超大詞條原樣存取', () async {
      const evil = "'; DROP TABLE dictionary_entries;--";
      final big = 'x' * 1000000;
      await store.insertEntries([
        _entry('s1', evil),
        _entry('s1', '相濡以沫', body: big),
      ]);

      expect((await store.lookup('s1', evil)).single.headword, evil);
      expect((await store.lookup('s1', '相濡以沫')).single.body, big);
      expect(await entryRowCount(), 2);
    });

    test('寫入詞條給不存在的來源會失敗（外鍵生效）', () async {
      await expectLater(
        store.insertEntries([_entry('missing', 'x')]),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('刪除', () {
    test('刪除來源會連帶刪除詞條', () async {
      await store.insertSource(_source('s1'));
      await store.insertEntries([_entry('s1', 'run'), _entry('s1', 'ran')]);

      await store.deleteSource('s1');

      expect(await store.lookup('s1', 'run'), isEmpty);
      expect(await entryRowCount(), 0);
      expect(await store.getSource('s1'), isNull);
    });

    test('刪除一本不影響另一本的詞條', () async {
      await store.insertSource(_source('s1'));
      await store.insertSource(_source('s2'));
      await store.insertEntries([_entry('s1', 'run'), _entry('s2', 'run')]);

      await store.deleteSource('s1');

      expect((await store.lookup('s2', 'run')).length, 1);
    });

    test('刪除不存在的來源不丟例外，也不影響既有資料', () async {
      await store.insertSource(_source('s1'));
      await store.insertEntries([_entry('s1', 'run')]);

      await store.deleteSource('missing');

      expect((await store.listSources()).map((s) => s.id), ['s1']);
      expect((await store.lookup('s1', 'run')).length, 1);
    });
  });

  group('交易', () {
    test('transaction 內的寫入在 action 丟例外時整批回復', () async {
      await expectLater(
        store.transaction((txnStore) async {
          await txnStore.insertSource(_source('s1'));
          await txnStore.insertEntries([_entry('s1', 'run')]);
          throw StateError('使用者取消匯入');
        }),
        throwsStateError,
      );

      expect(await store.listSources(), isEmpty);
      expect(await entryRowCount(), 0);
    });

    test('transaction 正常結束時寫入生效，並可回傳值', () async {
      final result = await store.transaction((txnStore) async {
        await txnStore.insertSource(_source('s1'));
        await txnStore.insertEntries([_entry('s1', 'run')]);
        return 'done';
      });

      expect(result, 'done');
      expect((await store.lookup('s1', 'run')).length, 1);
    });
  });

  group('content_id', () {
    test('寫入時帶 contentId，可用它找回來源 id', () async {
      await store.insertSource(_source('a'), contentId: 'cid-1');
      expect(await store.findSourceIdByContentId('cid-1'), 'a');
    });

    test('找不到 contentId 回傳 null；沒帶 contentId 的來源不會被找到', () async {
      await store.insertSource(_source('a'));
      expect(await store.findSourceIdByContentId('cid-1'), isNull);
      expect(await store.findSourceIdByContentId(''), isNull);
    });

    test('刪除來源後，同一個 contentId 找不到', () async {
      await store.insertSource(_source('a'), contentId: 'cid-1');
      await store.deleteSource('a');
      expect(await store.findSourceIdByContentId('cid-1'), isNull);
    });
  });

  group('補強（Issue 5）', () {
    test('setReferencedCss 寫入後 getSource 讀得回 referencedCss', () async {
      await store.insertSource(_source('a'));
      expect((await store.getSource('a'))!.referencedCss, isEmpty);

      await store.setReferencedCss('a', ['x.css', 'y.css']);

      expect((await store.getSource('a'))!.referencedCss, ['x.css', 'y.css']);
    });

    test('reorderSources 重寫成 0..n-1，listSources 依新順序', () async {
      await store.insertSource(_source('a', priority: 5));
      await store.insertSource(_source('b', priority: 1));
      await store.insertSource(_source('c', priority: 9));

      await store.reorderSources(['c', 'a', 'ghost', 'b']);

      final sources = await store.listSources();
      expect(sources.map((s) => s.id), ['c', 'a', 'b']);
      expect(sources.map((s) => s.priority), [0, 1, 3]);
    });

    test('reorderSources 不在清單內的來源不動', () async {
      await store.insertSource(_source('a', priority: 5));
      await store.insertSource(_source('b', priority: 7));

      await store.reorderSources(['b']);

      expect((await store.getSource('a'))!.priority, 5);
      expect((await store.getSource('b'))!.priority, 0);
    });

    test('listSources 略過 format 無法辨識的列，其餘照常回傳', () async {
      await store.insertSource(_source('a'));
      await db.rawInsert(
        "INSERT INTO dictionary_sources (id, name, format, source_lang, "
        "target_lang, priority, enabled, entry_count, imported_at) "
        "VALUES ('bad', '未知', 'stardict', 'en', 'zh-Hant', 0, 1, 0, "
        "'2026-10-19T08:00:00.000Z')",
      );

      final sources = await store.listSources();

      expect(sources.map((s) => s.id), ['a']);
    });
  });
}
