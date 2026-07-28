import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/library_repository.dart';

Book _book(
  String id, {
  String title = '書名',
  String? author,
  BookFileFormat format = BookFileFormat.epub,
  double progress = 0,
  String groupName = '未分類',
  int createTime = 1000,
  int lastReadTime = 1000,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: format,
    filePath: 'content://example/$id',
    source: BookSource.local,
    progress: progress,
    groupName: groupName,
    createTime: DateTime.fromMillisecondsSinceEpoch(createTime),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(lastReadTime),
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository repository;

  setUp(() async {
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
  });

  tearDown(() async {
    await repository.close();
  });

  test('insertBook/updateBook 正確保存 epubLocator／pdfPageIndex，listBooks 讀回相同值',
      () async {
    await repository.insertBook(_book('b1'));

    await repository.updateBook(_book('b1').copyWith());
    // Book.copyWith 不支援覆寫 epubLocator/pdfPageIndex（見 Task 1 Step 1
    // 說明），改用完整建構子組出待寫入的 Book。
    final withPosition = Book(
      id: 'b1',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://example/b1',
      source: BookSource.local,
      progress: 0.42,
      epubLocator: '{"href":"/chap1.xhtml","locations":{"totalProgression":0.42}}',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await repository.updateBook(withPosition);

    final books = await repository.listBooks();
    expect(books.single.progress, 0.42);
    expect(books.single.epubLocator,
        '{"href":"/chap1.xhtml","locations":{"totalProgression":0.42}}');
    expect(books.single.pdfPageIndex, isNull);
  });

  test('全新安裝的 book_reader_prefs 表包含 PDF 欄位（version 3 起 onCreate 已含括）',
      () async {
    // 直接查詢 sqlite_master 的欄位清單，避免依賴 BookReaderPrefsRepository
    // （schema 是否正確就緒是本測試檔的職責，CRUD 邏輯正確性由
    // book_reader_prefs_repository_test.dart 負責）。
    final columns =
        await repository.database.rawQuery('PRAGMA table_info(book_reader_prefs)');
    final columnNames = columns.map((c) => c['name'] as String).toSet();

    expect(columnNames, containsAll([
      'pdf_fit_mode',
      'pdf_contrast',
      'pdf_brightness',
      'pdf_bold_strength',
      'pdf_crop_mode',
      'pdf_crop_rect',
      'dual_page_mode',
      'dual_page_cover_alone',
      'dual_page_direction',
      'column_mode',
      'column_size',
    ]));
  });

  test('insertBook 後可用 listBooks 取回', () async {
    await repository.insertBook(_book('b1', title: '紅樓夢'));

    final books = await repository.listBooks();

    expect(books, hasLength(1));
    expect(books.single.title, '紅樓夢');
  });

  test('updateBook 更新既有書籍的欄位', () async {
    await repository.insertBook(_book('b1', title: '舊書名'));

    await repository.updateBook(_book('b1', title: '新書名'));

    final books = await repository.listBooks();
    expect(books.single.title, '新書名');
  });

  test('deleteBook 移除指定書籍', () async {
    await repository.insertBook(_book('b1'));
    await repository.insertBook(_book('b2'));

    await repository.deleteBook('b1');

    final books = await repository.listBooks();
    expect(books.map((b) => b.id), ['b2']);
  });

  group('listBooks 排序', () {
    setUp(() async {
      await repository.insertBook(_book(
        'b1',
        title: '西遊記',
        author: '吳承恩',
        createTime: 3000,
        lastReadTime: 1000,
      ));
      await repository.insertBook(_book(
        'b2',
        title: '三國演義',
        author: '羅貫中',
        createTime: 1000,
        lastReadTime: 3000,
      ));
      await repository.insertBook(_book(
        'b3',
        title: '水滸傳',
        author: '施耐庵',
        createTime: 2000,
        lastReadTime: 2000,
      ));
    });

    test('lastRead：最近閱讀優先', () async {
      final books = await repository.listBooks(sortBy: LibrarySortBy.lastRead);
      expect(books.map((b) => b.id).toList(), ['b2', 'b3', 'b1']);
    });

    test('createTime：最近建立優先', () async {
      final books =
          await repository.listBooks(sortBy: LibrarySortBy.createTime);
      expect(books.map((b) => b.id).toList(), ['b1', 'b3', 'b2']);
    });

    test('author：依作者排序', () async {
      final books = await repository.listBooks(sortBy: LibrarySortBy.author);
      expect(books.map((b) => b.author).toList(), ['吳承恩', '施耐庵', '羅貫中']);
    });

    test('title：依書名排序', () async {
      final books = await repository.listBooks(sortBy: LibrarySortBy.title);
      expect(books.map((b) => b.title).toList(), ['三國演義', '水滸傳', '西遊記']);
    });
  });

  test('listBooks 依 groupFilter 篩選', () async {
    await repository.insertBook(_book('b1', groupName: '經典名著'));
    await repository.insertBook(_book('b2', groupName: '古典奇幻'));

    final books = await repository.listBooks(groupFilter: '經典名著');

    expect(books.map((b) => b.id).toList(), ['b1']);
  });

  test('listBooks 不指定 groupFilter 時回傳全部', () async {
    await repository.insertBook(_book('b1', groupName: '經典名著'));
    await repository.insertBook(_book('b2', groupName: '古典奇幻'));

    final books = await repository.listBooks();

    expect(books, hasLength(2));
  });

  group('群組管理', () {
    test('upsertGroup 新增群組後出現在 listGroups', () async {
      await repository.upsertGroup('古典奇幻');

      final groups = await repository.listGroups();

      expect(groups.map((g) => g.name), containsAll(['未分類', '古典奇幻']));
    });

    test('upsertGroup 對已存在的名稱不重複新增', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.upsertGroup('古典奇幻');

      final groups = await repository.listGroups();

      expect(groups.where((g) => g.name == '古典奇幻'), hasLength(1));
    });

    test('deleteGroup 後，該群組下書籍改歸「未分類」', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.insertBook(_book('b1', groupName: '古典奇幻'));

      await repository.deleteGroup('古典奇幻');

      final books = await repository.listBooks();
      expect(books.single.groupName, '未分類');
      final groups = await repository.listGroups();
      expect(groups.map((g) => g.name), isNot(contains('古典奇幻')));
    });

    test('deleteGroup 對「未分類」拋出例外', () async {
      expect(
        () => repository.deleteGroup('未分類'),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });

    test('renameGroup 成功後，書籍歸屬同步更新為新名稱', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.insertBook(_book('b1', groupName: '古典奇幻'));

      await repository.renameGroup('古典奇幻', '奇幻小說');

      final books = await repository.listBooks();
      expect(books.single.groupName, '奇幻小說');
      final groups = await repository.listGroups();
      expect(groups.map((g) => g.name), contains('奇幻小說'));
      expect(groups.map((g) => g.name), isNot(contains('古典奇幻')));
    });

    test('renameGroup 對「未分類」拋出例外', () async {
      expect(
        () => repository.renameGroup('未分類', '新名稱'),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });

    test('renameGroup 目標名稱已存在時拋出例外', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.upsertGroup('文言經典');

      expect(
        () => repository.renameGroup('古典奇幻', '文言經典'),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });
  });

  group('book_reader_prefs schema', () {
    test('新安裝資料庫已包含 book_reader_prefs 表，且外鍵約束會在刪除書籍時連動清除',
        () async {
      await repository.insertBook(_book('b1'));
      await repository.database.insert('book_reader_prefs', {
        'book_id': 'b1',
        'font_size': 18.0,
      });

      await repository.deleteBook('b1');

      final rows = await repository.database.query(
        'book_reader_prefs',
        where: 'book_id = ?',
        whereArgs: ['b1'],
      );
      expect(rows, isEmpty);
    });
  });
  test('既有 version 1 裝置（無 book_reader_prefs 表）跳級升級到 version 5，兩張表皆正確補齊',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v1_to_v5_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 1」的最原始資料庫：只有 groups/books 兩張
    // 表，完全沒有 book_reader_prefs 表，books 表也不含
    // epubLocator/pdfPageIndex 欄位。這是 onUpgrade 分支結構最容易出錯
    // 的起點（見 Critical 1 審查修正）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '最早期書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=1 →
    // newVersion=5）。若 Critical 1 的 `return` 缺陷仍存在，
    // _addReadingPositionColumns 不會被執行，下方對 epubLocator 的
    // UPDATE 會直接拋出 `no such column` 例外，測試失敗。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    // book_reader_prefs 表須存在且已是最終版 schema（一步到位）。
    final prefsColumns = await upgraded.database
        .rawQuery('PRAGMA table_info(book_reader_prefs)');
    expect(
      prefsColumns.map((c) => c['name'] as String).toSet(),
      containsAll(['pdf_fit_mode', 'dual_page_mode']),
    );

    // books 表須正確補上位置欄位，且既有書籍資料不受影響。
    final books = await upgraded.listBooks();
    expect(books.single.title, '最早期書籍');
    expect(books.single.epubLocator, isNull);
    expect(books.single.pdfPageIndex, isNull);

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'books',
      {'epubLocator': '{"href":"/c1.xhtml"}'},
      where: 'id = ?',
      whereArgs: ['b1'],
    );
    final updated = await upgraded.listBooks();
    expect(updated.single.epubLocator, '{"href":"/c1.xhtml"}');
  });

  test('既有 version 2 裝置升級後，book_reader_prefs 新增 PDF 欄位且既有資料不受影響',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('elinkbook_migration_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 2」的舊資料庫：手動以 version 2 當時的
    // schema（不含 PDF 欄位）建立，不透過 SqliteLibraryRepository.open()
    // （該方法目前的 onCreate 已經是 version 3 的最終 schema，無法用來
    // 重現「舊裝置」情境）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'font_size': 18.0,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=2 →
    // newVersion=3），驗證既有 EPUB 資料不受影響、且新欄位可用。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['font_size'], 18.0); // 既有 EPUB 資料不受影響
    expect(row['pdf_fit_mode'], isNull); // 新欄位存在且預設 NULL

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'pdf_fit_mode': 'fitWidth'},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['pdf_fit_mode'], 'fitWidth');
  });

  test('既有 version 3 裝置升級後，book_reader_prefs 新增雙頁欄位且既有 PDF 資料不受影響',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('elinkbook_migration_v3_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 3」的舊資料庫：手動以 version 3 當時的
    // schema（含 PDF 欄位、不含雙頁欄位）建立。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT,
              pdf_fit_mode TEXT,
              pdf_contrast REAL,
              pdf_brightness REAL,
              pdf_bold_strength REAL,
              pdf_crop_mode TEXT,
              pdf_crop_rect TEXT
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'pdf',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'pdf_fit_mode': 'fitWidth',
      'pdf_contrast': 10.0,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=3 →
    // newVersion=4），驗證既有 PDF 資料不受影響、且雙頁新欄位可用。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['pdf_fit_mode'], 'fitWidth'); // 既有 PDF 資料不受影響
    expect(row['pdf_contrast'], 10.0);
    expect(row['dual_page_mode'], isNull); // 新欄位存在且預設 NULL

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'dual_page_mode': 'always', 'dual_page_cover_alone': 0},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['dual_page_mode'], 'always');
    expect(updated['dual_page_cover_alone'], 0);
  });

  test('既有 version 4 裝置升級後，books 表新增位置欄位且既有書籍資料不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v4_to_v5_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 4」的舊資料庫：手動以 version 4 當時的
    // schema（books 表不含 epubLocator/pdfPageIndex）建立，不透過
    // SqliteLibraryRepository.open()（該方法目前的 onCreate 已經是
    // version 5 的最終 schema，無法用來重現「舊裝置」情境）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_size REAL,
              pdf_fit_mode TEXT,
              dual_page_mode TEXT
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=4 →
    // newVersion=5），驗證既有書籍資料不受影響、且新欄位可用。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final books = await upgraded.listBooks();
    expect(books.single.title, '既有書籍'); // 既有資料不受影響
    expect(books.single.epubLocator, isNull); // 新欄位存在且預設 NULL
    expect(books.single.pdfPageIndex, isNull);

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'books',
      {'epubLocator': '{"href":"/c1.xhtml"}'},
      where: 'id = ?',
      whereArgs: ['b1'],
    );
    final updated = await upgraded.listBooks();
    expect(updated.single.epubLocator, '{"href":"/c1.xhtml"}');
  });

  test('既有 version 2 裝置直接升級到 version 4，PDF 欄位與雙頁欄位皆補齊（累加式 onUpgrade 驗證）',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v2_to_v4_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 2」的舊資料庫：手動以 version 2 當時的
    // schema（不含 PDF 欄位、不含雙頁欄位）建立。這是本測試存在的理由——
    // 驗證 onUpgrade 從互斥的 if/else if 改為累加式 if 之後，oldVersion=2
    // 跳級到 newVersion=4 時，PDF 欄位遷移（oldVersion<3）與雙頁欄位遷移
    // （oldVersion<4）兩段都會執行，不會因為只命中其中一個分支而漏掉。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('book_reader_prefs', {'book_id': 'b1', 'font_size': 18.0});
    await oldDb.close();

    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final columns = await upgraded.database
        .rawQuery('PRAGMA table_info(book_reader_prefs)');
    final columnNames = columns.map((c) => c['name'] as String).toSet();
    expect(
      columnNames,
      containsAll(['pdf_fit_mode', 'dual_page_mode', 'dual_page_cover_alone']),
    );

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['font_size'], 18.0); // 既有 EPUB 資料不受影響
  });

  test('全新安裝的 books 表包含 totalCharacterCount 欄位（version 6 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_char_count').copyWith());
    await repository.database.update(
      'books',
      {'totalCharacterCount': 55000},
      where: 'id = ?',
      whereArgs: ['b_char_count'],
    );

    final books = await repository.listBooks();
    expect(books.single.totalCharacterCount, 55000);
  });

  test('既有 version 5 裝置升級到 version 6，totalCharacterCount 欄位正確補上、既有資料不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v5_to_v6_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 5」的舊資料庫：手動以 version 5 當時的
    // schema（books 表不含 totalCharacterCount）建立，不透過
    // SqliteLibraryRepository.open()（該方法目前的 onCreate 已經是
    // version 6 的最終 schema，無法用來重現「舊裝置」情境）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.insert('books', {
            'id': 'b1',
            'title': 'Version 5 既有書籍',
            'format': 'epub',
            'filePath': 'content://example/b1',
            'source': 'local',
            'progress': 0.3,
            'groupName': '未分類',
            'createTime': 1000,
            'lastReadTime': 1000,
          });
        },
      ),
    );
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=5 →
    // newVersion=6），驗證既有書籍資料不受影響、且新欄位可用。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final books = await upgraded.listBooks();
    expect(books.single.title, 'Version 5 既有書籍'); // 既有資料不受影響
    expect(books.single.progress, 0.3);
    expect(books.single.totalCharacterCount, isNull); // 新欄位存在且預設 NULL

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'books',
      {'totalCharacterCount': 88888},
      where: 'id = ?',
      whereArgs: ['b1'],
    );
    final updated = await upgraded.listBooks();
    expect(updated.single.totalCharacterCount, 88888);
  });

  test('既有 version 1 裝置跳級升級到 version 6，全部遷移依序執行、既有資料不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v1_to_v6_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 1」的最原始資料庫：只有 groups/books 兩張
    // 表，完全沒有 book_reader_prefs 表，books 表也不含
    // epubLocator/pdfPageIndex/totalCharacterCount 欄位。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.insert('books', {
            'id': 'b1',
            'title': '最早期書籍',
            'format': 'epub',
            'filePath': 'content://example/b1',
            'source': 'local',
            'progress': 0,
            'groupName': '未分類',
            'createTime': 1000,
            'lastReadTime': 1000,
          });
        },
      ),
    );
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=1 →
    // newVersion=6）。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final books = await upgraded.listBooks();
    expect(books.single.title, '最早期書籍');
    expect(books.single.epubLocator, isNull);
    expect(books.single.pdfPageIndex, isNull);
    expect(books.single.totalCharacterCount, isNull);

    await upgraded.database.update(
      'books',
      {'totalCharacterCount': 12345},
      where: 'id = ?',
      whereArgs: ['b1'],
    );
    final updated = await upgraded.listBooks();
    expect(updated.single.totalCharacterCount, 12345);
  });

  test('既有 version 6 裝置升級到 version 7，book_reader_prefs 新增頁首/頁尾欄位且既有資料不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v6_to_v7_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 6」的舊資料庫：手動以 version 6 當時的完整
    // schema（book_reader_prefs 不含 show_header/show_footer）建立，不透過
    // SqliteLibraryRepository.open()（該方法目前的 onCreate 已經是
    // version 7 的最終 schema，無法用來重現「舊裝置」情境）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT,
              pdf_fit_mode TEXT,
              pdf_contrast REAL,
              pdf_brightness REAL,
              pdf_bold_strength REAL,
              pdf_crop_mode TEXT,
              pdf_crop_rect TEXT,
              dual_page_mode TEXT,
              dual_page_cover_alone INTEGER,
              dual_page_direction TEXT
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'font_size': 18.0,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=6 →
    // newVersion=7），驗證既有資料不受影響、且頁首/頁尾新欄位可用。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['font_size'], 18.0); // 既有資料不受影響
    expect(row['show_header'], isNull); // 新欄位存在且預設 NULL
    expect(row['show_footer'], isNull);

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'show_header': 0, 'show_footer': 1},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['show_header'], 0);
    expect(updated['show_footer'], 1);
  });

  test('全新安裝的 book_reader_prefs 表包含 show_header/show_footer 欄位（version 7 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_header_footer'));
    await repository.database.insert('book_reader_prefs', {
      'book_id': 'b_header_footer',
      'show_header': 0,
      'show_footer': 1,
    });

    final row = (await repository.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b_header_footer']))
        .single;
    expect(row['show_header'], 0);
    expect(row['show_footer'], 1);
  });

  test('全新安裝的 bookmarks 表可用（version 8 起 onCreate 已含括）', () async {
    await repository.insertBook(_book('b_bookmark'));
    final id = await repository.database.insert('bookmarks', {
      'book_id': 'b_bookmark',
      'name': '第一章',
      'epub_locator_json': '{"href":"/c1.xhtml"}',
      'progression': 0.1,
      'pdf_page_index': null,
    });
    expect(id, greaterThan(0));

    final rows = await repository.database
        .query('bookmarks', where: 'book_id = ?', whereArgs: ['b_bookmark']);
    expect(rows.single['name'], '第一章');
  });

  test('既有 version 7 裝置升級到 version 8，bookmarks 表正確建立', () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v7_to_v8_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 7」的舊資料庫：手動以 version 7 當時的完整
    // schema（books/book_reader_prefs 皆為 version 7 最終樣貌，不含
    // bookmarks 表）建立，不透過 SqliteLibraryRepository.open()（該方法
    // 目前的 onCreate 已經是 version 8 的最終 schema，無法用來重現「舊
    // 裝置」情境）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 7,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT,
              pdf_fit_mode TEXT,
              pdf_contrast REAL,
              pdf_brightness REAL,
              pdf_bold_strength REAL,
              pdf_crop_mode TEXT,
              pdf_crop_rect TEXT,
              dual_page_mode TEXT,
              dual_page_cover_alone INTEGER,
              dual_page_direction TEXT,
              show_header INTEGER,
              show_footer INTEGER
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=7 →
    // newVersion=8），驗證 bookmarks 表確實建立且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final id = await upgraded.database.insert('bookmarks', {
      'book_id': 'b1',
      'name': '測試書籤',
      'epub_locator_json': null,
      'progression': null,
      'pdf_page_index': 3,
    });
    expect(id, greaterThan(0));

    final rows = await upgraded.database
        .query('bookmarks', where: 'book_id = ?', whereArgs: ['b1']);
    expect(rows.single['name'], '測試書籤');

    // 既有書籍資料不受影響。
    final books = await upgraded.listBooks();
    expect(books.single.title, '既有書籍');
  });

  test('全新安裝的 highlights／notes 表可用（version 9 起 onCreate 已含括）', () async {
    await repository.insertBook(_book('b_highlight'));
    final highlightId = await repository.database.insert('highlights', {
      'book_id': 'b_highlight',
      'style': 'underline',
      'epub_locator_json': '{"href":"/c1.xhtml"}',
      'progression': 0.1,
    });
    expect(highlightId, greaterThan(0));

    final noteId = await repository.database.insert('notes', {
      'book_id': 'b_highlight',
      'text': '心得',
      'epub_locator_json': '{"href":"/c1.xhtml"}',
      'progression': 0.1,
      'highlight_id': highlightId,
    });
    expect(noteId, greaterThan(0));

    final rows = await repository.database
        .query('notes', where: 'book_id = ?', whereArgs: ['b_highlight']);
    expect(rows.single['highlight_id'], highlightId);
  });

  test('既有 version 8 裝置升級到 version 9，highlights／notes 表正確建立', () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v8_to_v9_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 8」的舊資料庫：手動以 version 8 當時的完整
    // schema（books/book_reader_prefs/bookmarks 皆為 version 8 最終樣貌，
    // 不含 highlights/notes）建立，不透過 SqliteLibraryRepository.open()
    // （該方法目前的 onCreate 已經是 version 9 的最終 schema，無法用來
    // 重現「舊裝置」情境，比照 v7→v8 遷移測試既有寫法）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 8,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT,
              pdf_fit_mode TEXT,
              pdf_contrast REAL,
              pdf_brightness REAL,
              pdf_bold_strength REAL,
              pdf_crop_mode TEXT,
              pdf_crop_rect TEXT,
              dual_page_mode TEXT,
              dual_page_cover_alone INTEGER,
              dual_page_direction TEXT,
              show_header INTEGER,
              show_footer INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE bookmarks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              name TEXT NOT NULL,
              epub_locator_json TEXT,
              progression REAL,
              pdf_page_index INTEGER
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=8 →
    // newVersion=9），驗證 highlights／notes 表確實建立且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final highlightId = await upgraded.database.insert('highlights', {
      'book_id': 'b1',
      'style': 'highlighterYellow',
      'epub_locator_json': null,
      'progression': 0.3,
    });
    expect(highlightId, greaterThan(0));

    final noteId = await upgraded.database.insert('notes', {
      'book_id': 'b1',
      'text': '升級後新增的備註',
      'epub_locator_json': null,
      'progression': 0.3,
      'highlight_id': null,
    });
    expect(noteId, greaterThan(0));

    // 既有書籍資料不受影響。
    final books = await upgraded.listBooks();
    expect(books.single.title, '既有書籍');
  });

  test('全新安裝的 highlights／notes 表含 PDF 欄位（version 10 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_pdf_highlight'));
    final highlightId = await repository.database.insert('highlights', {
      'book_id': 'b_pdf_highlight',
      'style': 'underline',
      'pdf_page_index': 2,
      'pdf_rect_json': '{"left":0.1,"top":0.2,"right":0.3,"bottom":0.4}',
    });
    expect(highlightId, greaterThan(0));

    final noteId = await repository.database.insert('notes', {
      'book_id': 'b_pdf_highlight',
      'text': '心得',
      'pdf_page_index': 2,
      'pdf_rect_json': '{"left":0.1,"top":0.2,"right":0.3,"bottom":0.4}',
      'highlight_id': highlightId,
    });
    expect(noteId, greaterThan(0));
  });

  test('既有 version 9 裝置升級到 version 10，highlights／notes 表正確補上 PDF 欄位（ALTER TABLE 路徑）',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v9_to_v10_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 9」的舊資料庫：手動以 version 9 當時的完整
    // schema 建立（highlights/notes 已存在但無 PDF 欄位），不透過
    // SqliteLibraryRepository.open()（該方法目前的 onCreate 已經是
    // version 10 的最終 schema），比照 v8→v9 遷移測試既有寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 9,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE highlights (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              style TEXT NOT NULL,
              epub_locator_json TEXT,
              progression REAL
            )
          ''');
          await db.execute('''
            CREATE TABLE notes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              text TEXT NOT NULL,
              epub_locator_json TEXT,
              progression REAL,
              highlight_id INTEGER REFERENCES highlights(id) ON DELETE SET NULL
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'pdf',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    final existingHighlightId = await oldDb.insert('highlights', {
      'book_id': 'b1',
      'style': 'underline',
      'epub_locator_json': null,
      'progression': 0.1,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=9 →
    // newVersion=10），驗證 highlights／notes 表確實補上 PDF 欄位、既有
    // 資料列不受影響、且新欄位可正常寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final existingRows = await upgraded.database
        .query('highlights', where: 'id = ?', whereArgs: [existingHighlightId]);
    expect(existingRows.single['progression'], 0.1);
    expect(existingRows.single['pdf_page_index'], isNull);

    final newHighlightId = await upgraded.database.insert('highlights', {
      'book_id': 'b1',
      'style': 'highlighterYellow',
      'pdf_page_index': 5,
      'pdf_rect_json': '{"left":0,"top":0,"right":1,"bottom":1}',
    });
    expect(newHighlightId, greaterThan(0));

    final newNoteId = await upgraded.database.insert('notes', {
      'book_id': 'b1',
      'text': '升級後新增的 PDF 備註',
      'pdf_page_index': 5,
      'pdf_rect_json': '{"left":0,"top":0,"right":1,"bottom":1}',
      'highlight_id': null,
    });
    expect(newNoteId, greaterThan(0));
  });

  test('全新安裝的 books 表包含 is_fixed_layout 欄位（version 11 起 onCreate 已含括）',
      () async {
    await repository.insertBook(
        _book('b_layout').copyWith(isFixedLayout: true));

    final books = await repository.listBooks();
    expect(books.single.isFixedLayout, isTrue);
  });

  test('既有 version 10 裝置升級到 version 11，books 表正確補上 is_fixed_layout 欄位（ALTER TABLE 路徑）',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v10_to_v11_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 10」的舊資料庫：手動以 version 10 當時的完整
    // books 表 schema（無 is_fixed_layout 欄位）建立，不透過
    // SqliteLibraryRepository.open()（該方法目前的 onCreate 已經是
    // version 11 的最終 schema），比照既有 v9→v10 遷移測試寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 10,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=10 →
    // newVersion=11），驗證既有書籍資料不受影響、新欄位預設為 NULL、且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final books = await upgraded.listBooks();
    expect(books.single.title, '既有書籍'); // 既有資料不受影響
    expect(books.single.isFixedLayout, isNull); // 新欄位存在且預設 NULL

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'books',
      {'is_fixed_layout': 0},
      where: 'id = ?',
      whereArgs: ['b1'],
    );
    final updated = await upgraded.listBooks();
    expect(updated.single.isFixedLayout, isFalse);
  });

  test('全新安裝的 book_reader_prefs 表包含 column_mode/column_size 欄位（version 13 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_column_mode'));
    await repository.database.insert('book_reader_prefs', {
      'book_id': 'b_column_mode',
      'column_mode': 'single',
      'column_size': 800.0,
    });

    final row = (await repository.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b_column_mode']))
        .single;
    expect(row['column_mode'], 'single');
    expect(row['column_size'], 800.0);
  });

  test('既有 version 11 裝置升級到目前版本（v13），book_reader_prefs 表正確補上 single_column 欄位（ALTER TABLE 路徑）',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v11_to_v12_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 11」的舊資料庫：手動以 version 11 當時的完整
    // schema（books 表含 is_fixed_layout；book_reader_prefs 表不含
    // single_column）建立，不透過 SqliteLibraryRepository.open()（該方法
    // 目前的 onCreate 已經是 version 12 的最終 schema，無法用來重現「舊
    // 裝置」情境），比照既有 v10→v11 遷移測試寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 11,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              is_fixed_layout INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT,
              pdf_fit_mode TEXT,
              pdf_contrast REAL,
              pdf_brightness REAL,
              pdf_bold_strength REAL,
              pdf_crop_mode TEXT,
              pdf_crop_rect TEXT,
              dual_page_mode TEXT,
              dual_page_cover_alone INTEGER,
              dual_page_direction TEXT,
              show_header INTEGER,
              show_footer INTEGER
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'font_size': 18.0,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=11 →
    // newVersion=13，一次跳級經過 v12 single_column 與 v13 column_mode/
    // column_size 兩段遷移），驗證既有資料不受影響、single_column 欄位
    // 存在且預設 NULL、且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['font_size'], 18.0); // 既有資料不受影響
    expect(row['single_column'], isNull); // 新欄位存在且預設 NULL

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'single_column': 1},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['single_column'], 1);
  });

  test('既有 version 12 裝置升級到 version 13，book_reader_prefs 新增 column_mode/column_size 且 single_column 舊值清零',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v12_to_v13_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 12」的舊資料庫：手動以 version 12 當時的完整
    // schema（book_reader_prefs 含 single_column、不含 column_mode/column_size）
    // 建立，不透過 SqliteLibraryRepository.open()（該方法目前的 onCreate
    // 已經是 version 13 的最終 schema），比照既有 v11→v12 遷移測試寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 12,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              is_fixed_layout INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT,
              pdf_fit_mode TEXT,
              pdf_contrast REAL,
              pdf_brightness REAL,
              pdf_bold_strength REAL,
              pdf_crop_mode TEXT,
              pdf_crop_rect TEXT,
              dual_page_mode TEXT,
              dual_page_cover_alone INTEGER,
              dual_page_direction TEXT,
              show_header INTEGER,
              show_footer INTEGER,
              single_column INTEGER
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    // 寫入帶有 single_column 舊值的資料（issues.md 要求遷移為 NULL）
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'font_size': 18.0,
      'single_column': 1,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=12 →
    // newVersion=13），驗證 single_column 舊值清零、column_mode/column_size
    // 新欄位存在且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['font_size'], 18.0); // 既有資料不受影響
    expect(row['single_column'], isNull); // issues.md 要求：single_column 舊值遷移為 NULL
    expect(row['column_mode'], isNull); // 新欄位存在且預設 NULL
    expect(row['column_size'], isNull);

    // 證明新欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'column_mode': 'single', 'column_size': 800.0},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['column_mode'], 'single');
    expect(updated['column_size'], 800.0);
  });

  test('全新安裝的 book_reader_prefs 表包含邊距 4 個欄位（version 14 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_margins'));
    await repository.database.insert('book_reader_prefs', {
      'book_id': 'b_margins',
      'margin_top': 72.0,
      'margin_bottom': 20.0,
      'margin_left': 30.0,
      'margin_right': 30.0,
    });

    final row = (await repository.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b_margins']))
        .single;
    expect(row['margin_top'], 72.0);
    expect(row['margin_bottom'], 20.0);
    expect(row['margin_left'], 30.0);
    expect(row['margin_right'], 30.0);
  });

  test('全新安裝的 book_reader_prefs 表包含 fullscreen 欄位（version 15 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_fullscreen'));
    await repository.database.insert('book_reader_prefs', {
      'book_id': 'b_fullscreen',
      'fullscreen': 1,
    });

    final row = (await repository.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b_fullscreen']))
        .single;
    expect(row['fullscreen'], 1);
  });

  test('既有 version 13 裝置升級到 version 14，book_reader_prefs 新增邊距 4 個欄位，既有 page_margins 值不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v13_to_v14_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 13」的舊資料庫：手動以 version 13 當時的完整
    // schema（book_reader_prefs 含 column_mode/column_size、不含邊距 4
    // 個欄位）建立，不透過 SqliteLibraryRepository.open()（該方法目前的
    // onCreate 已經是 version 14 的最終 schema），比照既有 v12→v13
    // 遷移測試寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 13,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              is_fixed_layout INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT,
              pdf_fit_mode TEXT,
              pdf_contrast REAL,
              pdf_brightness REAL,
              pdf_bold_strength REAL,
              pdf_crop_mode TEXT,
              pdf_crop_rect TEXT,
              dual_page_mode TEXT,
              dual_page_cover_alone INTEGER,
              dual_page_direction TEXT,
              show_header INTEGER,
              show_footer INTEGER,
              column_mode TEXT,
              column_size REAL
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'page_margins': 1.5,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=13 →
    // newVersion=14），驗證既有 page_margins 值不受影響、邊距 4 個新
    // 欄位存在且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['page_margins'], 1.5); // 既有資料不受影響
    expect(row['margin_top'], isNull); // 新欄位存在且預設 NULL
    expect(row['margin_bottom'], isNull);
    expect(row['margin_left'], isNull);
    expect(row['margin_right'], isNull);

    // 證明新欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'margin_top': 72.0, 'margin_left': 30.0},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['margin_top'], 72.0);
    expect(updated['margin_left'], 30.0);
  });

  test('既有 version 14 裝置升級到 version 15，book_reader_prefs 新增 fullscreen 欄位，既有 margin_top 值不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v14_to_v15_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 14」的舊資料庫：手動以 version 14 當時的完整
    // schema（book_reader_prefs 含邊距 4 個欄位、不含 fullscreen）建立，
    // 不透過 SqliteLibraryRepository.open()（該方法目前的 onCreate 已經是
    // version 15 的最終 schema），比照既有 v13→v14 遷移測試寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 14,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              is_fixed_layout INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT,
              pdf_fit_mode TEXT,
              pdf_contrast REAL,
              pdf_brightness REAL,
              pdf_bold_strength REAL,
              pdf_crop_mode TEXT,
              pdf_crop_rect TEXT,
              dual_page_mode TEXT,
              dual_page_cover_alone INTEGER,
              dual_page_direction TEXT,
              show_header INTEGER,
              show_footer INTEGER,
              column_mode TEXT,
              column_size REAL,
              margin_top REAL,
              margin_bottom REAL,
              margin_left REAL,
              margin_right REAL
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'margin_top': 72.0,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=14 →
    // newVersion=15），驗證既有 margin_top 值不受影響、fullscreen 新欄位
    // 存在且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['margin_top'], 72.0); // 既有資料不受影響
    expect(row['fullscreen'], isNull); // 新欄位存在且預設 NULL

    // 證明新欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'fullscreen': 1},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['fullscreen'], 1);
  });

  group('detectAndCacheEpubLayout', () {
    const channel = MethodChannel('elinkbook/book_metadata');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('呼叫 detectEpubLayout method channel 後，正確寫回資料庫並回傳結果',
        () async {
      await repository.insertBook(_book('b_detect'));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'detectEpubLayout');
        expect((call.arguments as Map)['uri'], 'content://example/b_detect');
        return {'isFixedLayout': true};
      });

      final result = await repository.detectAndCacheEpubLayout(
          'b_detect', 'content://example/b_detect');

      expect(result, isTrue);
      final books = await repository.listBooks();
      expect(books.single.isFixedLayout, isTrue);
    });

    test('判斷結果為流式（false）時，正確寫回資料庫', () async {
      await repository.insertBook(_book('b_detect_reflowable'));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        return {'isFixedLayout': false};
      });

      final result = await repository.detectAndCacheEpubLayout(
          'b_detect_reflowable', 'content://example/b_detect_reflowable');

      expect(result, isFalse);
      final books = await repository.listBooks();
      expect(
        books.firstWhere((b) => b.id == 'b_detect_reflowable').isFixedLayout,
        isFalse,
      );
    });
  });
}
