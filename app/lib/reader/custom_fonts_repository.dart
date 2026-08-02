import 'package:sqflite/sqflite.dart';

import 'custom_font.dart';

/// `custom_fonts` 表的存取層（epic-14-system-settings Issue 2，spec.md
/// 「字型管理模組」）。與 [SqliteLibraryRepository] 共用同一個 [Database]
/// 連線，比照既有 `BookmarksRepository`／`HighlightsRepository` 模式。
class CustomFontsRepository {
  final Database _db;

  const CustomFontsRepository(this._db);

  Future<List<CustomFont>> listAll() async {
    final rows = await _db.query('custom_fonts', orderBy: 'display_name ASC');
    return rows.map(CustomFont.fromMap).toList();
  }

  Future<bool> familyNameExists(String familyName) async {
    final rows = await _db.query(
      'custom_fonts',
      where: 'family_name = ?',
      whereArgs: [familyName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 回傳 SQLite 自動指派的 rowid。呼叫端須先以 [familyNameExists] 確認
  /// 不重複——本方法本身不做重複檢查，交由 `family_name UNIQUE` 約束
  /// 兜底（重複時拋出 [DatabaseException]）。
  Future<int> insert(CustomFont font) {
    return _db.insert('custom_fonts', font.toMap());
  }

  Future<void> rename(int id, String newDisplayName) {
    return _db.update(
      'custom_fonts',
      {'display_name': newDisplayName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 統計 `book_reader_prefs` 中目前使用中 [familyName] 的書籍數量，供刪除
  /// 前的確認對話框文案使用。
  Future<int> countBooksUsing(String familyName) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM book_reader_prefs WHERE font_family = ?',
      [familyName],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// 刪除字型並把所有使用中書籍的 `font_family` 重置為 `NULL`（FR-09 規則：
  /// 刪除使用中字型時自動退回預設字型），於同一交易內完成避免中途失敗留下
  /// 不一致狀態。
  Future<void> deleteAndResetUsage(int id, String familyName) async {
    await _db.transaction((txn) async {
      await txn.delete('custom_fonts', where: 'id = ?', whereArgs: [id]);
      await txn.update(
        'book_reader_prefs',
        {'font_family': null},
        where: 'font_family = ?',
        whereArgs: [familyName],
      );
    });
  }
}
