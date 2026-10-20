// app/test/dictionary/dictionary_manager_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:elinkbook/dictionary/dictionary_file_store.dart';
import 'package:elinkbook/dictionary/dictionary_manager.dart';
import 'package:elinkbook/dictionary/dictionary_service.dart';
import 'package:elinkbook/dictionary/importers/cedict_importer.dart';
import 'package:elinkbook/dictionary/importers/dictionary_importer.dart';
import 'package:elinkbook/dictionary/importers/json_csv_importer.dart';
import 'package:elinkbook/dictionary/mdx_companion_files.dart';
import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/dictionary_source.dart';
import 'package:elinkbook/dictionary/storage/dictionary_database.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 刪目錄時依旗標丟例外的檔案倉庫。
class _FlakyFileStore extends DictionaryFileStore {
  _FlakyFileStore(super.root);

  bool failDelete = false;

  @override
  Future<void> deleteAll(String sourceId) {
    if (failDelete) throw const FileSystemException('刪不掉');
    return super.deleteAll(sourceId);
  }
}

DictionarySource _source(
  String id, {
  int priority = 0,
  DictionaryFormat format = DictionaryFormat.jsonCsv,
}) =>
    DictionarySource(
      id: id,
      name: '字典 $id',
      format: format,
      sourceLang: 'zh',
      targetLang: 'zh-Hant',
      priority: priority,
      enabled: true,
      storagePath: '',
      entryCount: 0,
      licenseNote: '',
      importedAt: DateTime.utc(2026, 10, 19),
    );

void main() {
  late Database db;
  late DictionaryStore store;
  late Directory tmp;
  late _FlakyFileStore files;
  late DictionaryStoreProvider provider;
  late DictionaryManager manager;

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
    tmp = await Directory.systemTemp.createTemp('dict_mgr_test');
    files = _FlakyFileStore(Directory('${tmp.path}/dicts'));
    provider = DictionaryStoreProvider(() async => store);
    manager = DictionaryManager(
      store: provider,
      files: files,
      importerFactories: [
        (s) => JsonCsvImporter(store: s),
        (s) => CedictImporter(store: s),
      ],
    );
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// 在暫存目錄建一個「使用者選到的」檔案。
  Future<PickedFile> picked(String name, [String content = 'x']) async {
    final f = File('${tmp.path}/src_$name');
    await f.writeAsString(content);
    return PickedFile(path: f.path, name: name, size: content.length);
  }

  Future<void> addWithEntry(
    String id,
    String headword, {
    int priority = 0,
  }) async {
    await store.insertSource(_source(id, priority: priority));
    await store.insertEntries([
      DictionaryEntry(
        sourceId: id,
        headword: headword,
        body: '釋義',
        bodyKind: EntryBodyKind.plainText,
      ),
    ]);
  }

  test('list() 依優先順序回傳', () async {
    await store.insertSource(_source('b', priority: 1));
    await store.insertSource(_source('a', priority: 0));

    final items = await manager.list();

    expect(items.map((i) => i.source.id), ['a', 'b']);
  });

  test('MDX 缺 css 列在 missingCss，addCompanions 補上後為空', () async {
    await store.insertSource(_source('m', format: DictionaryFormat.mdx));
    await store.setReferencedCss('m', ['ghychyz.css']);
    expect((await manager.list()).single.missingCss, ['ghychyz.css']);

    await manager.addCompanions('m', [await picked('GHYCHYZ.CSS')]);

    expect((await manager.list()).single.missingCss, isEmpty);
  });

  test('非 MDX 來源的 missingCss 恆為空', () async {
    await store.insertSource(_source('j'));
    await store.setReferencedCss('j', ['a.css']);
    expect((await manager.list()).single.missingCss, isEmpty);
  });

  test('delete：來源、詞條、私有目錄都消失', () async {
    await addWithEntry('a', '天地');
    await manager.addCompanions('a', [await picked('s.css')]);
    expect(files.dirFor('a').existsSync(), isTrue);

    await manager.delete('a');

    expect(await manager.list(), isEmpty);
    expect(await store.lookup('a', '天地'), isEmpty);
    expect(files.dirFor('a').existsSync(), isFalse);
  });

  test('delete 目錄刪除失敗：例外往上傳，來源列與詞條還在，之後可重試', () async {
    await addWithEntry('a', '天地');
    files.failDelete = true;

    await expectLater(manager.delete('a'), throwsA(isA<FileSystemException>()));

    expect((await manager.list()).map((i) => i.source.id), ['a']);
    expect(await store.lookup('a', '天地'), isNotEmpty);

    files.failDelete = false;
    await manager.delete('a');
    expect(await manager.list(), isEmpty);
  });

  test('reorder 後 DictionaryService.lookup 的 outcomes 順序跟著變', () async {
    await addWithEntry('a', '天地', priority: 0);
    await addWithEntry('b', '天地', priority: 1);
    final service = DictionaryService.fromProvider(provider);

    Future<List<String>> order() async {
      final r = await service.lookup('天地') as LookupCompleted;
      return r.result.outcomes.map((o) => o.providerId).toList();
    }

    final before = await order();
    await manager.reorder(['b', 'a']);
    final after = await order();

    expect(before.length, 2);
    expect(after, before.reversed.toList());
  });

  test('setEnabled 會寫入', () async {
    await addWithEntry('a', '天地');
    await manager.setEnabled('a', false);
    expect((await manager.list()).single.source.enabled, isFalse);
  });

  test('addCompanions 忽略 .txt；同名 .css 覆蓋', () async {
    await store.insertSource(_source('m', format: DictionaryFormat.mdx));
    await manager.addCompanions('m', [
      await picked('n.txt'),
      await picked('s.css', 'old'),
    ]);
    expect(await files.listFiles('m'), ['s.css']);

    await manager.addCompanions('m', [await picked('s.css', 'newer')]);

    expect(await files.listFiles('m'), ['s.css']);
    expect(
      await File('${files.dirFor('m').path}/s.css').readAsString(),
      'newer',
    );
  });

  test('canImport：json 為真、mdx 為假', () async {
    expect(await manager.canImport('a.json'), isTrue);
    expect(await manager.canImport('a.mdx'), isFalse);
  });

  group('真實匯入路徑（JsonCsvImporter）', () {
    /// 寫一個小 JSON 字典並回傳「使用者選到的」檔案。
    Future<PickedFile> pickedJson() {
      final content = jsonEncode({
        'name': '小字典',
        'entries': [
          {'headword': 'apple', 'definition': '蘋果'},
          {'headword': 'run', 'definition': '跑'},
        ],
      });
      return picked('d.json', content);
    }

    ImportRequest requestFor(PickedFile f, {bool replace = false}) =>
        ImportRequest(
          filePath: f.path,
          fileName: f.name,
          sourceLang: 'en',
          targetLang: 'zh-Hant',
          replaceExisting: replace,
        );

    /// 跑完整個 stream，回傳最後一筆進度。
    Future<ImportProgress> runToEnd(PickedFile f, {bool replace = false}) async {
      ImportProgress? last;
      await for (final p in manager.import(
        f,
        requestFor(f, replace: replace),
        cancel: CancelToken(),
      )) {
        last = p;
      }
      return last!;
    }

    test('readHints → import 跑完後 list() 出現新字典，名稱與筆數正確', () async {
      final file = await pickedJson();

      final hints = await manager.readHints(file);
      expect(hints.name, '小字典');

      final last = await runToEnd(file);
      expect(last.stage, ImportStage.done);

      final items = await manager.list();
      expect(items, hasLength(1));
      expect(items.single.source.name, '小字典');
      expect(items.single.source.entryCount, 2);
      expect(items.single.source.id, last.summary!.sourceId);
    });

    test('重複匯入丟 DuplicateDictionaryException；replaceExisting 沿用 priority 與 enabled',
        () async {
      await addWithEntry('other', '天地', priority: 0);
      final file = await pickedJson();
      final first = await runToEnd(file);
      final importedId = first.summary!.sourceId;

      // 製造非預設值：停用、並排到最前面（priority 0）。
      await manager.setEnabled(importedId, false);
      await manager.reorder([importedId, 'other']);
      final before = (await manager.list())
          .firstWhere((i) => i.source.id == importedId)
          .source;
      expect(before.priority, 0);
      expect(before.enabled, isFalse);

      await expectLater(
        runToEnd(file),
        throwsA(isA<DuplicateDictionaryException>()),
      );

      final replaced = await runToEnd(file, replace: true);
      expect(replaced.stage, ImportStage.done);

      final items = await manager.list();
      expect(items, hasLength(2));
      final after = items.firstWhere((i) => i.source.id == importedId).source;
      expect(after.priority, before.priority);
      expect(after.enabled, isFalse);
    });

    test('匯入時取消訂閱不會留下半成品字典', () async {
      final file = await pickedJson();
      final done = Completer<void>();
      late StreamSubscription<ImportProgress> sub;
      // 收到第一個進度事件（解析階段，尚未寫入）就取消訂閱。
      sub = manager.import(file, requestFor(file), cancel: CancelToken()).listen(
        (_) {
          sub.cancel();
          done.complete();
        },
      );
      await done.future;
      // 給背景流程足夠時間；若它誤寫入，字典會出現在清單中。
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(await manager.list(), isEmpty);
    });
  });
}
