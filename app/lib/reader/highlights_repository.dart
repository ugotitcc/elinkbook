import 'package:sqflite/sqflite.dart';

import 'highlight.dart';

/// `highlights` 表的存取層（epic-6-annotations Issue 2，spec.md「劃線
/// 與備註模組」）。比照既有 `BookmarksRepository` 模式。
class HighlightsRepository {
  final Database _db;

  const HighlightsRepository(this._db);

  /// `updated_at`（epic-8-sync Issue 1，供雲端同步 dirty 判定使用，見
  /// `sqlite_library_repository.dart` `_createHighlightsTable`）由本層
  /// 補上目前時間戳記，不放進 [Highlight] 模型本身。
  Future<void> insert(Highlight highlight) {
    return _db.insert('highlights', {
      ...highlight.toMap(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 依書中位置順序排序：EPUB 用 `progression` 比例、PDF 用
  /// `pdf_page_index`（Issue 3 新增），兩者互斥、一本書只會用到其中一組
  /// （比照 `BookmarksRepository.listByBook` 既有的 `COALESCE` 慣例）。
  /// `deleted_at IS NULL` 排除已（軟）刪除的紀錄（epic-8-sync Issue 4）。
  Future<List<Highlight>> listByBook(String bookId) async {
    final rows = await _db.query(
      'highlights',
      where: 'book_id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Highlight.fromMap).toList();
  }

  /// epic-8-sync Issue 4：改為軟刪除（`UPDATE ... SET deleted_at = ?`），
  /// 供雲端同步的墓碑清理使用（見 spec.md「墓碑清理」）。原本
  /// `notes.highlight_id REFERENCES highlights(id) ON DELETE SET NULL`
  /// 這條外鍵約束只在**真正的** `DELETE FROM` 時觸發，改為軟刪除後不會
  /// 再自動生效，因此這裡手動複製同一段退化邏輯——依附這筆劃線的備註
  /// 一併退化為純備註（`highlight_id` 設為 `null`），行為與改動前完全
  /// 一致（見 plan-issue-4.md「與 issues.md／spec.md 的落差說明」第 2 點）。
  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'notes',
      {'highlight_id': null, 'updated_at': now},
      where: 'highlight_id = ?',
      whereArgs: [id],
    );
    await _db.update(
      'highlights',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 批次版本，同樣手動複製 FK 退化邏輯（見 [delete]）。**改用子查詢**
  /// 而非「先查出全部 id 清單、再組 `IN (?,?,?...)` 佔位符」——後者對單本
  /// 書籍持有大量劃線（超過 SQLite 單一陳述式的變數上限）時會拋出
  /// `too many SQL variables` 而崩潰（審查意見 Important #1，2026-08-04
  /// `/superpowers:requesting-code-review` 發現，見文末「審查修正
  /// 紀錄」）；子查詢完全不受此限制，且不需要先做一次額外的 `SELECT`。
  Future<void> deleteAllForBook(String bookId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'notes',
      {'highlight_id': null, 'updated_at': now},
      where: 'highlight_id IN '
          '(SELECT id FROM highlights WHERE book_id = ? AND deleted_at IS NULL)',
      whereArgs: [bookId],
    );
    await _db.update(
      'highlights',
      {'deleted_at': now, 'updated_at': now},
      where: 'book_id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
    );
  }
}
