// app/test/dictionary/dictionary_service_test.dart
import 'package:elinkbook/dictionary/dictionary_service.dart';
import 'package:elinkbook/dictionary/lookup_text_normalizer.dart';
import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/dictionary_source.dart';
import 'package:elinkbook/dictionary/models/lookup_result.dart';
import 'package:elinkbook/dictionary/storage/dictionary_database.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 計數 lookup 次數；[failingSourceId] 指定的來源會丟例外。
class _TestStore extends DictionaryStore {
  _TestStore(super.db);

  int lookupCount = 0;
  String? failingSourceId;

  @override
  Future<List<DictionaryEntry>> lookup(String sourceId, String word) {
    lookupCount++;
    if (sourceId == failingSourceId) throw StateError('壞掉的來源');
    return super.lookup(sourceId, word);
  }
}

DictionarySource _source(
  String id, {
  required String sourceLang,
  int priority = 0,
  bool enabled = true,
}) =>
    DictionarySource(
      id: id,
      name: '字典 $id',
      format: DictionaryFormat.jsonCsv,
      sourceLang: sourceLang,
      targetLang: 'zh-Hant',
      priority: priority,
      enabled: enabled,
      storagePath: '',
      entryCount: 0,
      licenseNote: '',
      importedAt: DateTime.utc(2026, 10, 19),
    );

DictionaryEntry _entry(String sourceId, String headword) => DictionaryEntry(
      sourceId: sourceId,
      headword: headword,
      body: '釋義 $headword',
      bodyKind: EntryBodyKind.plainText,
    );

void main() {
  late Database db;
  late _TestStore store;
  late DictionaryService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await DictionaryDatabase.open(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    store = _TestStore(db);
    service = DictionaryService(store: store);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> addSource(
    String id,
    String sourceLang,
    List<String> headwords, {
    int priority = 0,
    bool enabled = true,
  }) async {
    await store.insertSource(
      _source(id, sourceLang: sourceLang, priority: priority, enabled: enabled),
    );
    await store.insertEntries([for (final h in headwords) _entry(id, h)]);
  }

  LookupResult completed(DictionaryLookupResponse r) {
    expect(r, isA<LookupCompleted>());
    return (r as LookupCompleted).result;
  }

  test('無效選取回傳 LookupRejected，且不查任何字典', () async {
    await addSource('zh1', 'zh', ['天地']);

    final bad = await service.lookup('天地，玄黃');
    final long = await service.lookup('一二三四五六七八九');

    expect((bad as LookupRejected).problem, SelectionProblem.invalidSelection);
    expect((long as LookupRejected).problem, SelectionProblem.tooLong);
    expect(store.lookupCount, 0);
  });

  test('「相濡以沫」去標點後查詢', () async {
    await addSource('zh1', 'zh', ['相濡以沫']);

    final result = completed(await service.lookup('「相濡以沫」'));

    expect(result.outcomes.single.status, OutcomeStatus.found);
  });

  test('方向挑選：拉丁只查 en 字典', () async {
    await addSource('en1', 'en', ['apple']);
    await addSource('zh1', 'zh', ['apple']);

    final result = completed(await service.lookup('apple'));

    expect(result.outcomes.map((o) => o.providerId), ['en1']);
  });

  test('方向挑選：CJK 只查 zh 字典', () async {
    await addSource('en1', 'en', ['蘋果']);
    await addSource('zh1', 'zh', ['蘋果']);

    final result = completed(await service.lookup('蘋果'));

    expect(result.outcomes.map((o) => o.providerId), ['zh1']);
  });

  test('方向挑選：混合文字兩種字典都查', () async {
    await addSource('en1', 'en', ['iphone手機'], priority: 0);
    await addSource('zh1', 'zh', ['iphone手機'], priority: 1);

    final result = completed(await service.lookup('iPhone手機'));

    expect(result.outcomes.map((o) => o.providerId), ['en1', 'zh1']);
  });

  test('語言碼只看第一段：zh-Hant、en-US', () async {
    await addSource('en1', 'en-US', ['apple']);
    await addSource('zh1', 'zh-Hant', ['蘋果']);

    expect(
      completed(await service.lookup('apple')).outcomes.map((o) => o.providerId),
      ['en1'],
    );
    expect(
      completed(await service.lookup('蘋果')).outcomes.map((o) => o.providerId),
      ['zh1'],
    );
  });

  test('停用的字典不查；outcomes 依 priority 排序', () async {
    await addSource('a', 'en', ['run'], priority: 2);
    await addSource('b', 'en', ['run'], priority: 1);
    await addSource('c', 'en', ['run'], priority: 0, enabled: false);

    final result = completed(await service.lookup('run'));

    expect(result.outcomes.map((o) => o.providerId), ['b', 'a']);
  });

  test('沒有符合方向的字典：LookupCompleted 且 outcomes 為空', () async {
    await addSource('zh1', 'zh', ['蘋果']);

    final result = completed(await service.lookup('apple'));

    expect(result.outcomes, isEmpty);
  });

  test('沒有任何啟用字典：outcomes 為空且 hasEnabledDictionary 為 false', () async {
    final response = await service.lookup('apple');

    expect(response, isA<LookupCompleted>());
    final completedResponse = response as LookupCompleted;
    expect(completedResponse.result.outcomes, isEmpty);
    expect(completedResponse.hasEnabledDictionary, isFalse);
  });

  test('有英文字典、選中文：outcomes 為空但 hasEnabledDictionary 為 true', () async {
    await addSource('en1', 'en', ['apple']);

    final response = await service.lookup('蘋果');

    final completedResponse = response as LookupCompleted;
    expect(completedResponse.result.outcomes, isEmpty);
    expect(completedResponse.hasEnabledDictionary, isTrue);
  });

  test('有符合的字典：hasEnabledDictionary 為 true', () async {
    await addSource('zh1', 'zh', ['蘋果']);

    final response = await service.lookup('蘋果');

    final completedResponse = response as LookupCompleted;
    expect(completedResponse.result.outcomes.single.status, OutcomeStatus.found);
    expect(completedResponse.hasEnabledDictionary, isTrue);
  });

  test('一本字典丟例外：該分段 failed，其他分段照常', () async {
    await addSource('bad', 'en', ['run'], priority: 0);
    await addSource('good', 'en', ['run'], priority: 1);
    store.failingSourceId = 'bad';

    final result = completed(await service.lookup('run'));

    expect(result.outcomes.map((o) => o.status), [
      OutcomeStatus.failed,
      OutcomeStatus.found,
    ]);
    expect(result.outcomes.first.errorCode, 'localLookupFailed');
    expect(result.outcomes.first.providerId, 'bad');
  });

  test('跨行片語整理後整串查詢', () async {
    await addSource('en1', 'en', ['kick the bucket']);

    final result = completed(await service.lookup('kick  the\nbucket'));

    expect(result.outcomes.single.status, OutcomeStatus.found);
    expect(result.outcomes.single.entries.single.headword, 'kick the bucket');
  });

  test('LookupRequest 帶處理後的文字', () async {
    final result = completed(await service.lookup('「apple」'));
    expect(result.request.word, 'apple');
  });

  test(
    '本機查詢 p95 小於 300 ms（含候選鏈）',
    () async {
      // 開發機基準；真機量測屬 Issue 8。
      String name(int i) {
        var n = i;
        final buffer = StringBuffer('x');
        do {
          buffer.writeCharCode(97 + n % 26);
          n ~/= 26;
        } while (n > 0);
        return buffer.toString();
      }

      await store.insertSource(_source('big', sourceLang: 'en'));
      for (var start = 0; start < 100000; start += 5000) {
        await store.insertEntries([
          for (var i = start; i < start + 5000; i++) _entry('big', name(i)),
        ]);
      }

      final elapsed = <int>[];
      final watch = Stopwatch();
      for (var i = 0; i < 200; i++) {
        // `<名稱>ing` 要靠詞形還原回到 `<名稱>`，等於走完整條候選鏈。
        final word = '${name(i * 450)}ing';
        watch
          ..reset()
          ..start();
        final result = completed(await service.lookup(word));
        watch.stop();
        expect(result.outcomes.single.status, OutcomeStatus.found, reason: word);
        elapsed.add(watch.elapsedMilliseconds);
      }
      elapsed.sort();
      expect(elapsed[189], lessThan(300));
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
