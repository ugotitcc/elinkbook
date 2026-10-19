// app/test/dictionary/local_dictionary_provider_test.dart
import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/dictionary_source.dart';
import 'package:elinkbook/dictionary/models/lookup_request.dart';
import 'package:elinkbook/dictionary/models/lookup_result.dart';
import 'package:elinkbook/dictionary/providers/local_dictionary_provider.dart';
import 'package:elinkbook/dictionary/storage/dictionary_database.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 記錄每次 lookup 的查詢詞，用來驗證「命中就停」與「去重後才查」。
class _RecordingStore extends DictionaryStore {
  _RecordingStore(super.db);

  final List<String> queried = [];

  @override
  Future<List<DictionaryEntry>> lookup(String sourceId, String word) {
    queried.add(word);
    return super.lookup(sourceId, word);
  }
}

DictionarySource _source(
  String id, {
  String sourceLang = 'en',
  String name = '字典',
}) =>
    DictionarySource(
      id: id,
      name: name,
      format: DictionaryFormat.jsonCsv,
      sourceLang: sourceLang,
      targetLang: 'zh-Hant',
      priority: 0,
      enabled: true,
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
  late _RecordingStore store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await DictionaryDatabase.open(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    store = _RecordingStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<LocalDictionaryProvider> providerWith(
    List<String> headwords, {
    String sourceLang = 'en',
  }) async {
    final source = _source('s1', sourceLang: sourceLang, name: '我的字典');
    await store.insertSource(source);
    await store.insertEntries([for (final h in headwords) _entry('s1', h)]);
    return LocalDictionaryProvider(store: store, source: source);
  }

  test('命中第一個候選就停', () async {
    final provider = await providerWith(['ran', 'run']);

    final outcome = await provider.lookup(const LookupRequest('ran'));

    expect(outcome.status, OutcomeStatus.found);
    expect(outcome.entries.single.headword, 'ran');
    expect(store.queried, ['ran']);
  });

  test('ran 能查到只存 run 的字典', () async {
    final provider = await providerWith(['run']);

    final outcome = await provider.lookup(const LookupRequest('ran'));

    expect(outcome.status, OutcomeStatus.found);
    expect(outcome.entries.single.headword, 'run');
  });

  test('候選依序嘗試，後面的候選才命中', () async {
    final provider = await providerWith(['cafe']);

    final outcome = await provider.lookup(const LookupRequest('café'));

    expect(outcome.status, OutcomeStatus.found);
    expect(outcome.entries.single.headword, 'cafe');
  });

  test('全部沒有結果回傳 notFound，entries 為空', () async {
    final provider = await providerWith(['apple']);

    final outcome = await provider.lookup(const LookupRequest('zebra'));

    expect(outcome.status, OutcomeStatus.notFound);
    expect(outcome.entries, isEmpty);
  });

  test('候選依 headword_norm 去重後才查詢', () async {
    final provider = await providerWith(['apple']);

    await provider.lookup(const LookupRequest('Run'));

    // Run／run／RUN 對資料庫是同一個查詢，只查一次。
    expect(store.queried, ['Run']);
  });

  test('中文字典不套用英文詞形還原', () async {
    final zh = await providerWith(['run'], sourceLang: 'zh');
    expect(
      (await zh.lookup(const LookupRequest('ran'))).status,
      OutcomeStatus.notFound,
    );

    await db.delete('dictionary_sources');
    final en = await providerWith(['run'], sourceLang: 'en');
    expect(
      (await en.lookup(const LookupRequest('ran'))).status,
      OutcomeStatus.found,
    );
  });

  test('字典同時有 hop 與 hope：hoped 命中 hope，不是 hop', () async {
    final provider = await providerWith(['hop', 'hope']);

    final outcome = await provider.lookup(const LookupRequest('hoped'));

    expect(outcome.entries.single.headword, 'hope');
  });

  test('EPUB 的彎撇號 don’t 能查到直撇號詞頭', () async {
    final provider = await providerWith(["don't"]);

    final outcome = await provider.lookup(const LookupRequest('don’t'));

    expect(outcome.status, OutcomeStatus.found);
  });

  test('同一詞頭多筆全部回傳', () async {
    final provider = await providerWith(['IT', 'it']);

    final outcome = await provider.lookup(const LookupRequest('it'));

    expect(outcome.entries.map((e) => e.headword), ['IT', 'it']);
  });

  test('id 與 displayName 取自來源', () async {
    final provider = await providerWith(['a']);
    expect(provider.id, 's1');
    final outcome = await provider.lookup(const LookupRequest('a'));
    expect(outcome.providerId, 's1');
    expect(outcome.displayName, '我的字典');
  });
}
