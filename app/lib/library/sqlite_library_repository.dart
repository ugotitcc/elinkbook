import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'library_repository.dart';
import 'models/book.dart';
import 'models/book_group.dart';
import 'models/library_enums.dart';

/// 圖書庫在真實裝置上資料庫檔案的預設路徑（App 文件目錄下的
/// `library.db`）。僅供正式執行時使用；單元測試改用
/// `sqflite_common_ffi` 的 `inMemoryDatabasePath`，不會呼叫到這個函式
/// （`path_provider` 需要平台 channel，無法在純 Dart 測試環境執行）。
Future<String> defaultLibraryDatabasePath() async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'library.db');
}

class SqliteLibraryRepository implements LibraryRepository {
  final Database _db;

  SqliteLibraryRepository._(this._db);

  static Future<SqliteLibraryRepository> open(String path) async {
    final db = await openDatabase(
      path,
      version: 3,
      onConfigure: (db) async {
        // book_reader_prefs 的 ON DELETE CASCADE 需要外鍵約束真正生效，
        // SQLite 預設不強制外鍵，須逐連線手動開啟（見 epic-3 plan-issue-1）。
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE groups (
            name TEXT PRIMARY KEY
          )
        ''');
        await db.insert('groups', {'name': BookGroup.uncategorized});
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
            groupName TEXT NOT NULL DEFAULT '${BookGroup.uncategorized}',
            createTime INTEGER NOT NULL,
            lastReadTime INTEGER NOT NULL
          )
        ''');
        await _createBookReaderPrefsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 舊裝置從未有過 book_reader_prefs 表，_createBookReaderPrefsTable
          // 目前的 CREATE TABLE 已包含全部欄位（含 PDF），一步到位，不需要
          // 額外再跑 _addPdfReaderPrefsColumns（該表根本還不存在，ALTER TABLE
          // 會找不到表而失敗）。
          await _createBookReaderPrefsTable(db);
        } else if (oldVersion < 3) {
          // 裝置已經是 version 2：book_reader_prefs 表已存在但缺少 PDF
          // 欄位，只能用 ALTER TABLE 補上，不能重新 CREATE TABLE（會因
          // 表已存在而拋出例外）。
          await _addPdfReaderPrefsColumns(db);
        }
      },
    );
    return SqliteLibraryRepository._(db);
  }

  static Future<void> _createBookReaderPrefsTable(Database db) async {
    // 單書版面偏好設定（epic-3-fonts-layout FR-09/FR-10、epic-4-pdf-enhance
    // FR-11），與 books 表 1:1 關聯；所有欄位皆為 nullable，null 代表未
    // 覆寫，見 docs/epics/epic-4-pdf-enhance/spec.md「資料模型」。
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
  }

  static Future<void> _addPdfReaderPrefsColumns(Database db) async {
    // PDF 專業增強（epic-4-pdf-enhance FR-11）新增的 6 個欄位，補追加到
    // 既有（version 2 起已存在）的 book_reader_prefs 表，見
    // docs/epics/epic-4-pdf-enhance/spec.md「資料模型」。SQLite 的
    // ALTER TABLE ADD COLUMN 一次只能新增一欄，需逐一執行。
    await db
        .execute('ALTER TABLE book_reader_prefs ADD COLUMN pdf_fit_mode TEXT');
    await db
        .execute('ALTER TABLE book_reader_prefs ADD COLUMN pdf_contrast REAL');
    await db.execute(
        'ALTER TABLE book_reader_prefs ADD COLUMN pdf_brightness REAL');
    await db.execute(
        'ALTER TABLE book_reader_prefs ADD COLUMN pdf_bold_strength REAL');
    await db
        .execute('ALTER TABLE book_reader_prefs ADD COLUMN pdf_crop_mode TEXT');
    await db
        .execute('ALTER TABLE book_reader_prefs ADD COLUMN pdf_crop_rect TEXT');
  }

  /// 供 [BookReaderPrefsRepository] 等後續 repository 共用同一個資料庫連線
  /// （`book_reader_prefs` 的外鍵約束要求與 `books` 表在同一個資料庫檔案內）。
  Database get database => _db;

  Future<void> close() => _db.close();

  @override
  Future<Book> insertBook(Book book) async {
    await _db.insert('books', book.toMap());
    return book;
  }

  @override
  Future<void> updateBook(Book book) async {
    await _db.update(
      'books',
      book.toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  @override
  Future<void> deleteBook(String id) async {
    await _db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<Book>> listBooks({
    LibrarySortBy sortBy = LibrarySortBy.lastRead,
    String? groupFilter,
  }) async {
    final rows = await _db.query(
      'books',
      where: groupFilter != null ? 'groupName = ?' : null,
      whereArgs: groupFilter != null ? [groupFilter] : null,
      orderBy: _orderByClause(sortBy),
    );
    return rows.map(Book.fromMap).toList();
  }

  String _orderByClause(LibrarySortBy sortBy) {
    switch (sortBy) {
      case LibrarySortBy.lastRead:
        return 'lastReadTime DESC';
      case LibrarySortBy.createTime:
        return 'createTime DESC';
      case LibrarySortBy.author:
        return 'author ASC';
      case LibrarySortBy.title:
        return 'title ASC';
    }
  }

  @override
  Future<List<BookGroup>> listGroups() async {
    final rows = await _db.query('groups', orderBy: 'name ASC');
    return rows.map(BookGroup.fromMap).toList();
  }

  @override
  Future<void> upsertGroup(String name) async {
    await _db.insert(
      'groups',
      {'name': name},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> renameGroup(String oldName, String newName) async {
    if (oldName == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可重新命名');
    }
    await _db.transaction((txn) async {
      final existing =
          await txn.query('groups', where: 'name = ?', whereArgs: [newName]);
      if (existing.isNotEmpty) {
        throw LibraryRepositoryException('分類「$newName」已存在');
      }
      await txn.insert('groups', {'name': newName});
      await txn.update(
        'books',
        {'groupName': newName},
        where: 'groupName = ?',
        whereArgs: [oldName],
      );
      await txn.delete('groups', where: 'name = ?', whereArgs: [oldName]);
    });
  }

  @override
  Future<void> deleteGroup(String name) async {
    if (name == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可刪除');
    }
    await _db.transaction((txn) async {
      await txn.update(
        'books',
        {'groupName': BookGroup.uncategorized},
        where: 'groupName = ?',
        whereArgs: [name],
      );
      await txn.delete('groups', where: 'name = ?', whereArgs: [name]);
    });
  }
}
