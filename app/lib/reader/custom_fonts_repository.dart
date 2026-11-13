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

  /// 只更新該字型的 `font_uri`（epic-15-storage-permission Issue 3：字型檔案
  /// 授權失效後重新連結）。單一 UPDATE 敘述，不需要交易；顯示名稱、家族名稱
  /// 都不動，所以以家族名稱引用這款字型的書籍偏好不需要遷移。
  Future<void> updateUri(int id, String fontUri) {
    return _db.update(
      'custom_fonts',
      {'font_uri': fontUri},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 統計 `book_reader_prefs` 中「主字型或標題字型」使用 [familyName] 的書籍
  /// 數量（每本書只算一次，兩欄都用也只算一本；epic-68 起涵蓋標題字型），
  /// 供刪除前的確認對話框文案使用。
  Future<int> countBooksUsing(String familyName) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM book_reader_prefs '
      'WHERE font_family = ? OR heading_font_family = ?',
      [familyName, familyName],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// 刪除字型並把所有使用中書籍的 `font_family`（主字型）與
  /// `heading_font_family`（標題字型）中命中該字型的欄位各自重置為 `NULL`
  /// （FR-09 規則：刪除使用中字型時自動退回預設字型；標題字型 `NULL` 即跟隨
  /// 主字型），於同一交易內完成避免中途失敗留下不一致狀態。兩欄各自條件式
  /// 更新，只清命中的欄位。
  Future<void> deleteAndResetUsage(int id, String familyName) async {
    await _db.transaction((txn) async {
      await txn.delete('custom_fonts', where: 'id = ?', whereArgs: [id]);
      await txn.update(
        'book_reader_prefs',
        {'font_family': null},
        where: 'font_family = ?',
        whereArgs: [familyName],
      );
      // epic-68：標題字型同樣在該字型被刪除時重置為 NULL（跟隨主字型）。
      // 與上一條刻意分開、各自只比對自己的欄位：兩條合併成一條「同時清兩欄」會把
      // 「主字型用另一款字型」的書的主字型一併清掉（spec §5、D16）。
      await txn.update(
        'book_reader_prefs',
        {'heading_font_family': null},
        where: 'heading_font_family = ?',
        whereArgs: [familyName],
      );
    });
  }
}
