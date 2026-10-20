// app/test/dictionary/dictionary_store_provider_test.dart
import 'package:elinkbook/dictionary/storage/dictionary_database.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  test('第一次呼叫才開啟，之後回傳同一個 store', () async {
    var opened = 0;
    final provider = DictionaryStoreProvider(() async {
      opened++;
      return store;
    });
    expect(opened, 0);

    final first = await provider();
    final second = await provider();

    expect(opened, 1);
    expect(identical(first, second), isTrue);
  });

  test('開啟失敗不記住：下次呼叫重試', () async {
    var attempts = 0;
    final provider = DictionaryStoreProvider(() async {
      attempts++;
      if (attempts == 1) throw StateError('開檔失敗');
      return store;
    });

    await expectLater(provider(), throwsStateError);
    final result = await provider();

    expect(identical(result, store), isTrue);
    expect(attempts, 2);
  });
}
