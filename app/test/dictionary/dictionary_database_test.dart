// app/test/dictionary/dictionary_database_test.dart
import 'dart:io';

import 'package:elinkbook/dictionary/storage/dictionary_database.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 一筆最小合法的來源列（欄位照 spec §4）。
Map<String, Object?> _sourceRow(String id) => {
      'id': id,
      'name': '測試字典',
      'format': 'jsonCsv',
      'source_lang': 'en',
      'target_lang': 'zh-Hant',
      'priority': 0,
      'imported_at': DateTime.utc(2026, 10, 19).toIso8601String(),
    };

Map<String, Object?> _entryRow(String sourceId, String headword) => {
      'source_id': sourceId,
      'headword': headword,
      'headword_norm': headword.toLowerCase(),
      'body': '釋義',
      'body_kind': 'plainText',
    };

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dictionary_db_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('建立兩張表與查詢索引', () async {
    final db = await DictionaryDatabase.open(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    addTearDown(db.close);

    final rows = await db.query('sqlite_master', columns: ['name']);
    final names = rows.map((r) => r['name']).toSet();
    expect(
      names,
      containsAll(<String>[
        'dictionary_sources',
        'dictionary_entries',
        'idx_entries_lookup',
      ]),
    );
  });

  test('版本為 1', () async {
    final db = await DictionaryDatabase.open(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    addTearDown(db.close);

    expect(await db.getVersion(), 1);
  });

  test('每次開啟連線，外鍵都是開啟的', () async {
    final path = p.join(tempDir.path, 'dictionary.db');

    // 第一次開啟：寫入一本字典與兩筆詞條後關閉。
    final first = await DictionaryDatabase.open(path, singleInstance: false);
    await first.insert('dictionary_sources', _sourceRow('s1'));
    await first.insert('dictionary_entries', _entryRow('s1', 'run'));
    await first.insert('dictionary_entries', _entryRow('s1', 'ran'));
    await first.close();

    // 第二次開啟同一個檔案：onCreate 不會再跑，外鍵設定必須來自 onConfigure。
    final second = await DictionaryDatabase.open(path, singleInstance: false);
    addTearDown(second.close);

    final pragma = await second.rawQuery('PRAGMA foreign_keys');
    expect(pragma.single.values.single, 1);

    await second.delete('dictionary_sources', where: 'id = ?', whereArgs: ['s1']);
    final remaining = await second.rawQuery(
      'SELECT count(*) AS c FROM dictionary_entries',
    );
    expect(remaining.single['c'], 0);
  });

  test('主資料庫版本仍為 28', () async {
    final repo = await SqliteLibraryRepository.open(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    addTearDown(repo.close);

    expect(await repo.database.getVersion(), 28);
  });

  test('dictionary.db 與主庫是不同檔案，主庫沒有字典表', () async {
    final main = await SqliteLibraryRepository.open(
      p.join(tempDir.path, 'library.db'),
      singleInstance: false,
    );
    addTearDown(main.close);
    final dict = await DictionaryDatabase.open(
      p.join(tempDir.path, 'dictionary.db'),
      singleInstance: false,
    );
    addTearDown(dict.close);

    final mainTables = await main.database.query(
      'sqlite_master',
      where: 'name = ?',
      whereArgs: ['dictionary_sources'],
    );
    expect(mainTables, isEmpty);
    expect(File(p.join(tempDir.path, 'dictionary.db')).existsSync(), isTrue);
  });
}
