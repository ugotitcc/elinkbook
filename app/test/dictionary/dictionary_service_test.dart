// app/test/dictionary/dictionary_service_test.dart
import 'dart:async';

import 'package:elinkbook/dictionary/dictionary_service.dart';
import 'package:elinkbook/dictionary/dictionary_settings_repository.dart';
import 'package:elinkbook/dictionary/lookup_text_normalizer.dart';
import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/dictionary_source.dart';
import 'package:elinkbook/dictionary/models/lookup_request.dart';
import 'package:elinkbook/dictionary/models/lookup_result.dart';
import 'package:elinkbook/dictionary/providers/moedict_provider.dart';
import 'package:elinkbook/dictionary/providers/online_dictionary_provider.dart';
import 'package:elinkbook/dictionary/storage/dictionary_database.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store_provider.dart';
import 'package:elinkbook/dictionary/storage/mdx_reader_pool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_dictionary_settings_repository.dart';

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

/// 計數用的線上 provider：可指定回應、丟例外或永遠不完成（證明沒被呼叫）。
class _CountingOnlineProvider implements OnlineDictionaryProvider {
  final List<LookupRequest> requests = [];
  ProviderOutcome? outcome;
  Object? error;
  Completer<ProviderOutcome>? hang;

  @override
  String get id => 'moedict';

  @override
  String get displayName => '萌典';

  @override
  Future<ProviderOutcome> lookup(LookupRequest request) {
    requests.add(request);
    final pending = hang;
    if (pending != null) return pending.future;
    final failure = error;
    if (failure != null) return Future.error(failure);
    return Future.value(
      outcome ??
          ProviderOutcome(
            providerId: id,
            displayName: displayName,
            status: OutcomeStatus.found,
            entries: [
              DictionaryEntry(
                sourceId: id,
                headword: request.word,
                body: '線上釋義',
                bodyKind: EntryBodyKind.plainText,
              ),
            ],
            attribution: '來源標示',
          ),
    );
  }
}

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

  group('DictionaryService.lazy（延遲開啟）', () {
    test('建構時不開啟；第一次 lookup 才開，之後重用同一個 store', () async {
      var opened = 0;
      final lazy = DictionaryService.lazy(() async {
        opened++;
        return store;
      });
      expect(opened, 0);

      await lazy.lookup('天地');
      await lazy.lookup('天地');

      expect(opened, 1);
    });

    test('開啟失敗：lookup 丟出例外，下一次 lookup 會重試', () async {
      var attempts = 0;
      final lazy = DictionaryService.lazy(() async {
        attempts++;
        if (attempts == 1) throw StateError('開檔失敗');
        return store;
      });

      await expectLater(lazy.lookup('天地'), throwsStateError);
      final response = await lazy.lookup('天地');

      expect(response, isA<LookupCompleted>());
      expect(attempts, 2);
    });

    test('選取無效時不開啟字典資料庫', () async {
      var opened = 0;
      final lazy = DictionaryService.lazy(() async {
        opened++;
        return store;
      });

      await lazy.lookup('，');

      expect(opened, 0);
    });
  });

  test('fromProvider：兩個 service 共用同一個 provider 只開啟一次', () async {
    var opened = 0;
    final provider = DictionaryStoreProvider(() async {
      opened++;
      return store;
    });
    final a = DictionaryService.fromProvider(provider);
    final b = DictionaryService.fromProvider(provider);

    await a.lookup('天地');
    await b.lookup('天地');

    expect(opened, 1);
  });

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

  group('Issue 6a：MDX 來源', () {
    late MdxReaderPool pool;

    setUp(() {
      pool = MdxReaderPool();
    });

    tearDown(() => pool.closeAll());

    DictionarySource mdxSource(
      String id, {
      int priority = 0,
      String sourceLang = 'en',
      String file = 'zlib.mdx',
    }) =>
        DictionarySource(
          id: id,
          name: 'MDX $id',
          format: DictionaryFormat.mdx,
          sourceLang: sourceLang,
          targetLang: 'zh-Hant',
          priority: priority,
          enabled: true,
          storagePath: 'test/fixtures/mdx/$file',
          entryCount: 0,
          licenseNote: '',
          importedAt: DateTime.utc(2026, 10, 19),
        );

    test('JSON 與 MDX 來源各一段，依 priority 排序', () async {
      await addSource('json1', 'en', ['apple'], priority: 0);
      await store.insertSource(mdxSource('mdx1', priority: 1));
      final mdxService = DictionaryService(store: store, mdxPool: pool);

      final result = completed(await mdxService.lookup('apple'));

      expect(result.outcomes.map((o) => o.providerId), ['json1', 'mdx1']);
      expect(result.outcomes.map((o) => o.status), [
        OutcomeStatus.found,
        OutcomeStatus.found,
      ]);
      expect(result.outcomes.last.entries.first.bodyKind, EntryBodyKind.html);
    });

    test('未提供 pool：MDX 來源 failed，errorCode 為 mdxUnavailable', () async {
      await store.insertSource(mdxSource('mdx1'));

      final result = completed(await service.lookup('apple'));

      expect(result.outcomes.single.status, OutcomeStatus.failed);
      expect(result.outcomes.single.errorCode, 'mdxUnavailable');
      expect(result.outcomes.single.entries, isEmpty);
    });

    test('lookupInSource 只查指定來源，且不做語言過濾', () async {
      // 來源語言是 zh，查的卻是拉丁詞：一般 lookup 會被方向挑選略過，
      // 交叉參照必須照查。
      await store.insertSource(mdxSource('mdx-zh', sourceLang: 'zh'));
      final mdxService = DictionaryService(store: store, mdxPool: pool);

      final entries = await mdxService.lookupInSource('mdx-zh', 'apple');

      expect(entries, hasLength(2));
      expect(entries.first.bodyKind, EntryBodyKind.html);
    });

    test('lookupInSource 查無或來源不存在 → 空清單', () async {
      await addSource('en1', 'en', ['apple']);
      await store.insertSource(mdxSource('mdx1'));

      expect(await service.lookupInSource('en1', 'zzzz'), isEmpty);
      expect(await service.lookupInSource('missing', 'apple'), isEmpty);
    });
  });

  group('線上分段', () {
    DateTime consent() => DateTime.utc(2026, 10, 21, 8);

    DictionaryService withOnline({
      required OnlineDictionaryProvider online,
      DictionarySettingsRepository? settings,
      Future<bool> Function()? isNetworkAvailable,
    }) =>
        DictionaryService(
          store: store,
          onlineProvider: online,
          settings: settings ?? FakeDictionarySettingsRepository(),
          isNetworkAvailable: isNetworkAvailable,
        );

    FakeDictionarySettingsRepository notConsented() =>
        FakeDictionarySettingsRepository();

    FakeDictionarySettingsRepository consented() =>
        FakeDictionarySettingsRepository(consentAt: consent());

    test('未同意：純中文選字回 skipped，網路呼叫 0', () async {
      await addSource('zh1', 'zh', ['相濡以沫']);
      final online = _CountingOnlineProvider();
      final settings = notConsented();

      final result = completed(
        await withOnline(online: online, settings: settings).lookup('相濡以沫'),
      );

      expect(result.outcomes.map((o) => o.providerId), ['zh1', 'moedict']);
      expect(result.outcomes.last.status, OutcomeStatus.skipped);
      expect(result.outcomes.last.displayName, '萌典');
      expect(online.requests, isEmpty);
      expect(settings.loadCount, 1);
    });

    test('未同意：中英混合選字同樣 skipped，呼叫 0', () async {
      await addSource('zh1', 'zh', ['iPhone 手機']);
      final online = _CountingOnlineProvider();

      final result = completed(
        await withOnline(online: online).lookup('iPhone 手機'),
      );

      expect(result.outcomes.last.providerId, 'moedict');
      expect(result.outcomes.last.status, OutcomeStatus.skipped);
      expect(online.requests, isEmpty);
    });

    test('未同意：純拉丁選字沒有線上分段', () async {
      await addSource('en1', 'en', ['run']);
      final online = _CountingOnlineProvider();
      final settings = notConsented();

      final result = completed(
        await withOnline(online: online, settings: settings).lookup('run'),
      );

      expect(result.outcomes.map((o) => o.providerId), ['en1']);
      expect(online.requests, isEmpty);
      expect(settings.loadCount, 0);
    });

    test('已同意：線上分段排在本機之後', () async {
      await addSource('zh0', 'zh', ['相濡以沫'], priority: 0);
      await addSource('zh1', 'zh', ['相濡以沫'], priority: 1);
      final online = _CountingOnlineProvider();

      final result = completed(
        await withOnline(online: online, settings: consented())
            .lookup('相濡以沫'),
      );

      expect(result.outcomes.map((o) => o.providerId), [
        'zh0',
        'zh1',
        'moedict',
      ]);
      expect(result.outcomes.last.status, OutcomeStatus.found);
    });

    test('送出的是 normalizeLookupSelection 後的字串', () async {
      final online = _CountingOnlineProvider();
      final service = withOnline(online: online, settings: consented());

      await service.lookup('「相濡以沫」');
      expect(online.requests.single.word, '相濡以沫');

      await service.lookup('ran');
      expect(online.requests, hasLength(1));
    });

    test('不送候選詞：中文選字時線上 provider 只被呼叫一次', () async {
      await addSource('zh1', 'zh', ['相濡以沫']);
      final online = _CountingOnlineProvider();

      await withOnline(online: online, settings: consented()).lookup('相濡以沫');

      expect(online.requests, hasLength(1));
      expect(online.requests.single.word, '相濡以沫');
    });

    test('撤回後立即生效：不需要重建 service', () async {
      await addSource('zh1', 'zh', ['相濡以沫']);
      final online = _CountingOnlineProvider();
      final settings = consented();
      final service = withOnline(online: online, settings: settings);

      await service.lookup('相濡以沫');
      expect(online.requests, hasLength(1));

      settings.consentAt = null;
      final result = completed(await service.lookup('相濡以沫'));

      expect(online.requests, hasLength(1));
      expect(result.outcomes.last.status, OutcomeStatus.skipped);
    });

    test('讀不到同意狀態：視為未同意，不丟例外、不連網，本機結果照常', () async {
      await addSource('zh1', 'zh', ['相濡以沫']);
      final online = _CountingOnlineProvider();
      final settings = consented()..failOnLoad = true;

      final result = completed(
        await withOnline(online: online, settings: settings).lookup('相濡以沫'),
      );

      expect(result.outcomes.map((o) => o.providerId), ['zh1', 'moedict']);
      expect(result.outcomes.first.status, OutcomeStatus.found);
      expect(result.outcomes.last.status, OutcomeStatus.skipped);
      expect(online.requests, isEmpty);
    });

    test('連線狀態判斷丟例外：不擋，照樣呼叫 provider', () async {
      await addSource('zh1', 'zh', ['相濡以沫']);
      final online = _CountingOnlineProvider();

      await withOnline(
        online: online,
        settings: consented(),
        isNetworkAvailable: () async => throw StateError('無法判斷'),
      ).lookup('相濡以沫');

      expect(online.requests, hasLength(1));
    });

    test('離線：不呼叫 provider，回 failed／offline 且不拖慢本機', () async {
      await addSource('zh1', 'zh', ['相濡以沫']);
      final online = _CountingOnlineProvider()..hang = Completer();
      final watch = Stopwatch()..start();

      final result = completed(
        await withOnline(
          online: online,
          settings: consented(),
          isNetworkAvailable: () async => false,
        ).lookup('相濡以沫'),
      );
      watch.stop();

      expect(result.outcomes.first.status, OutcomeStatus.found);
      expect(result.outcomes.last.status, OutcomeStatus.failed);
      expect(result.outcomes.last.errorCode, 'offline');
      expect(online.requests, isEmpty);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('本機與線上互不影響：線上丟例外', () async {
      await addSource('zh1', 'zh', ['相濡以沫']);
      final online = _CountingOnlineProvider()..error = StateError('壞了');

      final result = completed(
        await withOnline(online: online, settings: consented())
            .lookup('相濡以沫'),
      );

      expect(result.outcomes.first.status, OutcomeStatus.found);
      expect(result.outcomes.last.status, OutcomeStatus.failed);
      expect(result.outcomes.last.errorCode, 'network');
    });

    test('本機與線上互不影響：本機丟例外', () async {
      await addSource('zh1', 'zh', ['相濡以沫']);
      store.failingSourceId = 'zh1';

      final result = completed(
        await withOnline(
          online: _CountingOnlineProvider(),
          settings: consented(),
        ).lookup('相濡以沫'),
      );

      expect(result.outcomes.first.status, OutcomeStatus.failed);
      expect(result.outcomes.last.status, OutcomeStatus.found);
    });

    test('選取無效時不查線上', () async {
      final online = _CountingOnlineProvider();
      final settings = consented();

      final response = await withOnline(online: online, settings: settings)
          .lookup('天地，玄黃');

      expect(response, isA<LookupRejected>());
      expect(online.requests, isEmpty);
      expect(settings.loadCount, 0);
    });

    test('沒有本機字典但已同意：outcomes 只有 moedict', () async {
      final response = await withOnline(
        online: _CountingOnlineProvider(),
        settings: consented(),
      ).lookup('相濡以沫');

      final completedResponse = response as LookupCompleted;
      expect(completedResponse.hasEnabledDictionary, isFalse);
      expect(
        completedResponse.result.outcomes.map((o) => o.providerId),
        ['moedict'],
      );
    });

    test('沒有本機字典且未同意：不附 skipped', () async {
      final online = _CountingOnlineProvider();

      final response = await withOnline(online: online).lookup('相濡以沫');

      final completedResponse = response as LookupCompleted;
      expect(completedResponse.hasEnabledDictionary, isFalse);
      expect(completedResponse.result.outcomes, isEmpty);
      expect(online.requests, isEmpty);
    });

    test('有本機字典且未同意：附 skipped', () async {
      await addSource('zh1', 'zh', ['相濡以沫']);

      final result = completed(
        await withOnline(online: _CountingOnlineProvider()).lookup('相濡以沫'),
      );

      expect(result.outcomes.last.providerId, 'moedict');
      expect(result.outcomes.last.status, OutcomeStatus.skipped);
    });

    test('未同意：真 MoedictProvider 不發出任何 HTTP 請求', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      });
      final service = DictionaryService(
        store: store,
        onlineProvider: MoedictProvider(client: client),
        settings: notConsented(),
      );

      await service.lookup('相濡以沫');

      expect(calls, 0);
    });
  });
}
