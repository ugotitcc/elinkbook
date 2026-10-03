// app/test/stats/daily_reading_stats_schema_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';

Book _book(String id, {String title = '書名'}) => Book(
      id: id,
      title: title,
      format: BookFileFormat.epub,
      filePath: '/books/$id',
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );

/// `daily_reading_stats` 資料表的 schema 測試（epic-9-stats Issue 2，DB v27）。
/// 只用原生 SQL 驗證資料表本身，不依賴 `SqliteReadingStatsRepository`。
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('全新安裝：version 28，資料表與日期索引存在，主鍵為（date, book_id）', () async {
    final library = await SqliteLibraryRepository.open(inMemoryDatabasePath,
        singleInstance: false);
    addTearDown(library.close);
    final db = library.database;

    expect(await db.getVersion(), 28);

    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='daily_reading_stats'");
    expect(tables, hasLength(1));

    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_daily_reading_stats_date'");
    expect(indexes, hasLength(1));

    // 主鍵欄位（pk > 0）依主鍵順序為 date、book_id
    final columns = await db.rawQuery('PRAGMA table_info(daily_reading_stats)');
    final pk = columns.where((c) => (c['pk'] as int) > 0).toList()
      ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
    expect(pk.map((c) => c['name']).toList(), ['date', 'book_id']);
  });

  test('沒有任何外鍵；刪除書籍後統計列仍在，刪書本身不受影響', () async {
    final library = await SqliteLibraryRepository.open(inMemoryDatabasePath,
        singleInstance: false);
    addTearDown(library.close);
    final db = library.database;

    expect(await db.rawQuery('PRAGMA foreign_key_list(daily_reading_stats)'),
        isEmpty,
        reason: '嚴禁對 book_id 宣告外鍵：連線全程 foreign_keys = ON，'
            'RESTRICT 會讓刪書失敗、CASCADE 會抹掉歷史時數');

    await library.insertBook(_book('b1', title: '會被刪除的書'));
    await db.insert('daily_reading_stats', {
      'date': '2026-09-29',
      'book_id': 'b1',
      'book_title': '會被刪除的書',
      'reading_seconds': 600,
      'updated_at': 1000,
    });

    await library.deleteBook('b1'); // 不得拋例外

    expect(await library.listBooks(), isEmpty);
    final rows = await db.query('daily_reading_stats');
    expect(rows.single['book_title'], '會被刪除的書');
    expect(rows.single['reading_seconds'], 600);
  });

  test('既有 version 26 裝置升級到 27：既有資料完整保留，新表建立且為空，重開不重建',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v26_to_v27_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 26,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('CREATE TABLE books (id TEXT PRIMARY KEY)');
          await db.insert('books', {'id': 'legacy-book'});
        },
      ),
    );
    await oldDb.close();

    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    // 升級一路走到目前最新版本（28），不是只升到 27
    expect(await upgraded.database.getVersion(), 28);
    final legacy = await upgraded.database.query('books');
    expect(legacy.single['id'], 'legacy-book', reason: '升級不得動到既有資料');
    expect(await upgraded.database.query('daily_reading_stats'), isEmpty);

    await upgraded.database.insert('daily_reading_stats', {
      'date': '2026-09-29',
      'book_id': 'b1',
      'book_title': '書',
      'reading_seconds': 30,
      'updated_at': 1000,
    });

    // 重新開啟（不觸發 onUpgrade）：資料仍在、不會因重複建表而拋例外
    await upgraded.close();
    final reopened = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => reopened.close());
    final rows = await reopened.database.query('daily_reading_stats');
    expect(rows.single['reading_seconds'], 30);
  });
}
