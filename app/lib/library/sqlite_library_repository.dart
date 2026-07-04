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
      version: 1,
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
      },
    );
    return SqliteLibraryRepository._(db);
  }

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
