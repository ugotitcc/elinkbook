// app/test/dictionary/json_csv_importer_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:elinkbook/dictionary/importers/dictionary_importer.dart';
import 'package:elinkbook/dictionary/importers/json_csv_importer.dart';
import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/storage/dictionary_database.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late DictionaryStore store;
  late JsonCsvImporter importer;
  late Directory dir;

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
    importer = JsonCsvImporter(store: store);
    dir = Directory.systemTemp.createTempSync('json_csv_importer_test');
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  String writeText(String name, String text) {
    final f = File('${dir.path}/$name')..writeAsStringSync(text);
    return f.path;
  }

  String writeBytes(String name, List<int> bytes) {
    final f = File('${dir.path}/$name')..writeAsBytesSync(bytes);
    return f.path;
  }

  String writeJson(String name, Object json) =>
      writeText(name, jsonEncode(json));

  ImportRequest requestFor(
    String path, {
    bool replace = false,
    String? name,
    String licenseNote = '',
  }) =>
      ImportRequest(
        filePath: path,
        fileName: path.split(RegExp(r'[\\/]')).last,
        sourceLang: 'en',
        targetLang: 'zh-Hant',
        name: name,
        licenseNote: licenseNote,
        replaceExisting: replace,
      );

  Stream<ImportProgress> start(
    String path, {
    CancelToken? cancel,
    bool replace = false,
    String? name,
    String licenseNote = '',
  }) =>
      importer.import(
        requestFor(path, replace: replace, name: name, licenseNote: licenseNote),
        cancel: cancel ?? CancelToken(),
      );

  Future<ImportProgress> runImport(
    String path, {
    CancelToken? cancel,
    bool replace = false,
    String? name,
    String licenseNote = '',
  }) async {
    final events = await start(
      path,
      cancel: cancel,
      replace: replace,
      name: name,
      licenseNote: licenseNote,
    ).toList();
    return events.last;
  }

  /// 收到第 [nth] 個 writing 事件時取消，回傳全部事件。
  Future<List<ImportProgress>> runAndCancelAtWrite(
    String path,
    int nth, {
    bool replace = false,
  }) {
    final token = CancelToken();
    final events = <ImportProgress>[];
    final done = Completer<List<ImportProgress>>();
    var writes = 0;
    start(path, cancel: token, replace: replace).listen(
      (e) {
        events.add(e);
        if (e.stage == ImportStage.writing && ++writes == nth) token.cancel();
      },
      onError: done.completeError,
      onDone: () => done.complete(events),
    );
    return done.future;
  }

  List<Map<String, Object?>> entriesJson(int n) => [
        for (var i = 0; i < n; i++)
          {'headword': 'word$i', 'definition': '釋義$i'},
      ];

  Future<int> count(String table) async {
    final rows = await db.rawQuery('SELECT count(*) AS c FROM $table');
    return rows.single['c'] as int;
  }

  Matcher importError(String code) => throwsA(
        isA<DictionaryImportException>().having((e) => e.code, 'code', code),
      );

  test('canHandle 依副檔名判斷，不分大小寫', () {
    expect(importer.canHandle('a.json'), isTrue);
    expect(importer.canHandle('A.CSV'), isTrue);
    expect(importer.canHandle('a.mdx'), isFalse);
    expect(importer.canHandle('json'), isFalse);
  });

  test('正常 JSON：寫入來源與詞條，進度最後為 done 並帶摘要', () async {
    final path = writeJson('d.json', {
      'name': '我的字典',
      'licenseNote': 'CC BY-SA 4.0',
      'entries': [
        {'headword': 'apple', 'pronunciation': 'ap', 'pos': 'n.', 'definition': '蘋果'},
        {'headword': 'run', 'definition': '跑'},
      ],
    });

    final last = await runImport(path);

    expect(last.stage, ImportStage.done);
    expect(last.summary!.importedCount, 2);
    expect(last.summary!.skippedCount, 0);
    final source = (await store.getSource(last.summary!.sourceId))!;
    expect(source.name, '我的字典');
    expect(source.sourceLang, 'en');
    expect(source.targetLang, 'zh-Hant');
    expect(source.licenseNote, 'CC BY-SA 4.0');
    expect(source.entryCount, 2);
    final hit = (await store.lookup(source.id, 'APPLE')).single;
    expect(hit.pronunciation, 'ap');
    expect(hit.partOfSpeech, 'n.');
    expect(hit.bodyKind, EntryBodyKind.plainText);
  });

  test('名稱優先序：request.name → 檔內 name → 去副檔名的檔名', () async {
    final withName = writeJson('a.json', {
      'name': '檔內',
      'entries': entriesJson(1),
    });
    final noName = writeJson('b.json', {'entries': entriesJson(1)});

    final a = await runImport(withName, name: '指定');
    final b = await runImport(noName);

    expect((await store.getSource(a.summary!.sourceId))!.name, '指定');
    expect((await store.getSource(b.summary!.sourceId))!.name, 'b');
  });

  test('正常 CSV', () async {
    final path = writeText(
      'd.csv',
      'headword,definition,pronunciation,pos\napple,蘋果,ap,n.\nrun,跑,,\n',
    );

    final last = await runImport(path);

    expect(last.summary!.importedCount, 2);
    final hit = (await store.lookup(last.summary!.sourceId, 'apple')).single;
    expect(hit.body, '蘋果');
    expect(hit.partOfSpeech, 'n.');
  });

  test('Excel 匯出的 CSV：UTF-8 BOM、CRLF、引號內有逗號與換行', () async {
    final text = '﻿headword,definition\r\n'
        'apple,"紅色, 圓的\n水果"\r\n';
    final path = writeText('x.csv', text);

    final last = await runImport(path);

    final hit = (await store.lookup(last.summary!.sourceId, 'apple')).single;
    expect(hit.body, '紅色, 圓的\n水果');
  });

  test('JSON 開頭有 BOM 也能解析', () async {
    final path = writeText(
      'bom.json',
      '﻿${jsonEncode({'entries': entriesJson(1)})}',
    );
    expect((await runImport(path)).summary!.importedCount, 1);
  });

  test('CSV 欄名不分大小寫與前後空白', () async {
    final path = writeText('c.csv', ' Headword , DEFINITION \napple,蘋果\n');
    expect((await runImport(path)).summary!.importedCount, 1);
  });

  test('缺 definition 欄的 CSV 丟 invalidFormat', () async {
    final path = writeText('c.csv', 'headword,pos\napple,n.\n');
    await expectLater(start(path).toList(), importError('invalidFormat'));
  });

  test('JSON 頂層不是物件或 entries 不是陣列丟 invalidFormat', () async {
    final list = writeText('l.json', '[]');
    final notArray = writeJson('n.json', {'entries': 'x'});
    await expectLater(start(list).toList(), importError('invalidFormat'));
    await expectLater(start(notArray).toList(), importError('invalidFormat'));
  });

  test('壞編碼丟 invalidEncoding', () async {
    final path = writeBytes('bad.json', [0xC3, 0x28]);
    await expectLater(start(path).toList(), importError('invalidEncoding'));
  });

  test('缺必填欄的列略過並計數，摘要帶前 5 筆原因', () async {
    final path = writeJson('s.json', {
      'entries': [
        {'headword': 'ok', 'definition': '好'},
        {'headword': ' ', 'definition': 'x'},
        {'headword': 'a', 'definition': ''},
        {'definition': 'x'},
        {'headword': 'b'},
        {'headword': '', 'definition': 'x'},
        {'headword': 'c', 'definition': '   '},
      ],
    });

    final last = await runImport(path);

    expect(last.summary!.importedCount, 1);
    expect(last.summary!.skippedCount, 6);
    final samples = last.summary!.skipSamples;
    expect(samples.length, 5);
    expect(samples.map((s) => s.index), [2, 3, 4, 5, 6]);
    expect(samples.map((s) => s.reason), [
      'missingHeadword',
      'missingDefinition',
      'missingHeadword',
      'missingDefinition',
      'missingHeadword',
    ]);
  });

  test('超過 64 KB 的 definition 略過', () async {
    final path = writeJson('big.json', {
      'entries': [
        {'headword': 'ok', 'definition': 'x' * 65536},
        {'headword': 'tooBig', 'definition': 'x' * 65537},
        {'headword': 'zhBig', 'definition': '字' * 21846}, // 65,538 位元組
      ],
    });

    final last = await runImport(path);

    expect(last.summary!.importedCount, 1);
    expect(last.summary!.skipSamples.map((s) => s.reason), [
      'definitionTooLong',
      'definitionTooLong',
    ]);
  });

  test('沒有任何有效筆數丟 noValidEntries，且不建立來源', () async {
    final empty = writeJson('e.json', {'entries': <Object>[]});
    final allBad = writeJson('b.json', {
      'entries': [
        {'headword': 'a'},
        {'definition': 'b'},
      ],
    });

    await expectLater(start(empty).toList(), importError('noValidEntries'));
    await expectLater(start(allBad).toList(), importError('noValidEntries'));
    expect(await store.listSources(), isEmpty);
  });

  test('重複匯入同一檔案丟 DuplicateDictionaryException，帶既有來源 id', () async {
    final path = writeJson('d.json', {'entries': entriesJson(2)});
    final first = await runImport(path);

    await expectLater(
      start(path).toList(),
      throwsA(
        isA<DuplicateDictionaryException>().having(
          (e) => e.existingSourceId,
          'existingSourceId',
          first.summary!.sourceId,
        ),
      ),
    );
    expect((await store.listSources()).length, 1);
  });

  test('replaceExisting 在同一交易內取代舊字典', () async {
    final path = writeJson('d.json', {'entries': entriesJson(3)});
    final first = await runImport(path);

    final second = await runImport(path, replace: true);

    expect(second.stage, ImportStage.done);
    expect((await store.listSources()).length, 1);
    expect(await count('dictionary_entries'), 3);
    expect(
      (await store.lookup(second.summary!.sourceId, 'word0')).length,
      1,
    );
    expect(second.summary!.sourceId, first.summary!.sourceId);
  });

  test('replaceExisting 取代中途取消：舊字典與詞條仍在', () async {
    final path = writeJson('d.json', {'entries': entriesJson(5000)});
    final first = await runImport(path);

    final events = await runAndCancelAtWrite(path, 1, replace: true);

    expect(events.last.stage, ImportStage.cancelled);
    final sources = await store.listSources();
    expect(sources.map((s) => s.id), [first.summary!.sourceId]);
    expect(await count('dictionary_entries'), 5000);
  });

  test('replaceExisting 保留舊字典的 id、優先順序與啟用狀態', () async {
    final a = writeJson('a.json', {'entries': entriesJson(2)});
    final b = writeJson('b.json', {'entries': entriesJson(3)});
    final first = await runImport(a);
    await runImport(b);
    await store.setEnabled(first.summary!.sourceId, false);
    await store.setPriority(first.summary!.sourceId, 7);

    final replaced = await runImport(a, replace: true);

    expect(replaced.summary!.sourceId, first.summary!.sourceId);
    final source = (await store.getSource(first.summary!.sourceId))!;
    expect(source.priority, 7);
    expect(source.enabled, isFalse);
    expect((await store.listSources()).length, 2);
  });

  test('replaceExisting 但沒有舊字典時等同新匯入', () async {
    final path = writeJson('d.json', {'entries': entriesJson(2)});
    final last = await runImport(path, replace: true);
    expect(last.summary!.importedCount, 2);
    expect((await store.listSources()).length, 1);
  });

  test('新字典優先順序排在最後', () async {
    final a = await runImport(writeJson('a.json', {'entries': entriesJson(1)}));
    final b = await runImport(writeJson('b.json', {'entries': entriesJson(2)}));

    final sourceA = (await store.getSource(a.summary!.sourceId))!;
    final sourceB = (await store.getSource(b.summary!.sourceId))!;
    expect(sourceB.priority, sourceA.priority + 1);
  });

  test('詞條的 sourceId 在解析時就已正確，寫入不發生外鍵錯誤', () async {
    final path = writeJson('d.json', {'entries': entriesJson(3)});

    final last = await runImport(path);

    expect(
      (await store.lookup(last.summary!.sourceId, 'word1')).single.sourceId,
      last.summary!.sourceId,
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('取消：解析前就取消，資料庫無來源與詞條', () async {
    final path = writeJson('d.json', {'entries': entriesJson(10)});
    final token = CancelToken()..cancel();

    final events = await start(path, cancel: token).toList();

    expect(events.last.stage, ImportStage.cancelled);
    expect(await store.listSources(), isEmpty);
    expect(await count('dictionary_entries'), 0);
  });

  test('取消：寫入中途取消，整個交易回復', () async {
    final path = writeJson('d.json', {'entries': entriesJson(5000)});

    final events = await runAndCancelAtWrite(path, 1);

    expect(events.last.stage, ImportStage.cancelled);
    expect(await store.listSources(), isEmpty);
    expect(await count('dictionary_entries'), 0);
  });

  test('readHints 回傳 JSON 內的名稱與語言；沒有就用檔名', () async {
    final full = writeJson('full.json', {
      'name': '我的字典',
      'sourceLang': 'en',
      'targetLang': 'zh-Hant',
      'licenseNote': 'CC BY-SA 4.0',
      'entries': entriesJson(1),
    });
    final bare = writeJson('bare.json', {'entries': entriesJson(1)});
    final csv = writeText('table.csv', 'headword,definition\na,b\n');

    final f = await importer.readHints(full, 'full.json');
    expect(f.name, '我的字典');
    expect(f.sourceLang, 'en');
    expect(f.targetLang, 'zh-Hant');
    expect(f.licenseNote, 'CC BY-SA 4.0');

    final b = await importer.readHints(bare, 'bare.json');
    expect(b.name, 'bare');
    expect(b.sourceLang, isNull);

    expect((await importer.readHints(csv, 'table.csv')).name, 'table');
  });

  test(
    '匯入 10 萬筆：有多個進度事件，完成後可查詢',
    () async {
      final path = writeJson('big.json', {'entries': entriesJson(100000)});

      final events = await start(path).toList();

      expect(events.length, greaterThan(10));
      expect(events.last.stage, ImportStage.done);
      expect(events.last.summary!.importedCount, 100000);
      expect(
        (await store.lookup(events.last.summary!.sourceId, 'word99999'))
            .length,
        1,
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test(
    '匯入 10 萬筆可在中途取消',
    () async {
      final path = writeJson('big.json', {'entries': entriesJson(100000)});

      final events = await runAndCancelAtWrite(path, 3);

      expect(events.last.stage, ImportStage.cancelled);
      expect(await store.listSources(), isEmpty);
      expect(await count('dictionary_entries'), 0);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
