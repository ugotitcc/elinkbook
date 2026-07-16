import 'package:sqflite/sqflite.dart';

/// `books` 表 `totalCharacterCount` 欄位的存取層（epic-5-toc-pagination
/// Issue 3，spec.md「分頁估算模組」決策 #16）。與 [ReadingPositionRepository]
/// 刻意分離成獨立的小型 repository，而非併入同一個類別——`totalCharacterCount`
/// 是「全書字元數計算結果的快取」，與 [ReadingPositionRepository] 明確
/// scoped 的「本機閱讀位置」欄位（epubLocator/pdfPageIndex/progress）是
/// 各自獨立、寫入時機也不同的關注點（位置在離開/背景時寫入；字元數快取在
/// 背景計算完成當下寫入），分開後才能各自做 partial UPDATE 而不互相
/// 覆蓋對方欄位，只是恰好存放在同一張 `books` 表裡。
class EpubCharacterCountRepository {
  final Database _db;

  const EpubCharacterCountRepository(this._db);

  /// 無對應書籍列或尚未計算過時回傳 `null`（代表尚無快取值，呼叫端據此
  /// 決定是否觸發原生端背景計算，見 spec.md「執行緒與快取」）。
  Future<int?> load(String bookId) async {
    final rows = await _db.query(
      'books',
      columns: ['totalCharacterCount'],
      where: 'id = ?',
      whereArgs: [bookId],
    );
    if (rows.isEmpty) return null;
    return rows.single['totalCharacterCount'] as int?;
  }

  /// Partial update：只更新這 1 個欄位，不影響書籍的其餘欄位，比照
  /// [ReadingPositionRepository.save] 的既有模式。
  Future<void> save(String bookId, int totalCharacterCount) async {
    await _db.update(
      'books',
      {'totalCharacterCount': totalCharacterCount},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }
}
