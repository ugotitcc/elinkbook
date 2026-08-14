import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'book_reader_prefs.dart';
import 'layout_preset.dart';

/// `layout_preset` 表的存取層（epic-28-reader-settings-enhancements
/// Issue 3），比照 `BookReaderPrefsRepository` 既有模式，與其共用同一個
/// `Database` 連線（`main.dart` 建構時注入）。
///
/// **`prefs_json` 儲存格式（非逐欄位對應）**：`BookReaderPrefs` 未來每
/// 新增一個欄位，逐欄位設計都需要同步維護「book_reader_prefs」與
/// 「layout_preset」兩張表的 migration，容易遺漏其中一邊；JSON blob
/// 設計下本表結構完全不受 `BookReaderPrefs` 欄位增減影響，只需要
/// `toMap()`/`fromMap()` 序列化邏輯保持正確即可（見 spec.md「儲存
/// 格式」）。代價是無法對個別欄位下 SQL `WHERE` 查詢，但本表的存取模式
/// （列出全部 3 組、依 id 存取單一組）完全不需要這種查詢能力。
///
/// 本類別**不**負責欄位過濾（`reflowableEpubFields()`）——過濾責任在
/// 寫入端（`ReaderScreen`），`insert()`/`replace()` 原樣序列化傳入的
/// `preset.prefs`，見 `BookReaderPrefs.reflowableEpubFields()` 文件。
class LayoutPresetRepository {
  const LayoutPresetRepository(this._db);
  final Database _db;

  /// 依 `id ASC`（插入順序）排序，見 [LayoutPreset] 類別文件「一旦指定
  /// 後...」——不隨 `updatedAt` 重新排序，避免使用者覆蓋某一組後畫面上
  /// 卡片位置無預警互換造成困惑。
  Future<List<LayoutPreset>> listAll() async {
    final rows = await _db.query('layout_preset', orderBy: 'id ASC');
    return rows.map(_fromRow).toList();
  }

  /// [preset.id]／`createdAt`／`updatedAt` 皆被忽略——`id` 由資料庫自動
  /// 指派（`AUTOINCREMENT`），`created_at`/`updated_at` 皆設為呼叫當下的
  /// 時間。
  Future<void> insert(LayoutPreset preset) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert('layout_preset', {
      'name': preset.name,
      'created_at': now,
      'updated_at': now,
      'prefs_json': _encodePrefs(preset.prefs),
    });
  }

  /// 覆蓋既有一組（存滿 3 組時）：[id]／既有 `created_at` 不變，
  /// `updated_at` 更新為呼叫當下的時間。[preset] 自帶的 `id`／
  /// `createdAt`／`updatedAt` 皆被忽略，一律以參數 [id] 與資料庫既有
  /// `created_at`、呼叫當下時間為準，避免呼叫端誤傳不一致的值。[id]
  /// 對應的列不存在時靜默不做任何事。
  Future<void> replace(int id, LayoutPreset preset) async {
    final existing =
        await _db.query('layout_preset', where: 'id = ?', whereArgs: [id]);
    if (existing.isEmpty) return;
    final createdAt = existing.single['created_at'] as int;
    await _db.update(
      'layout_preset',
      {
        'name': preset.name,
        'created_at': createdAt,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'prefs_json': _encodePrefs(preset.prefs),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) async {
    await _db.delete('layout_preset', where: 'id = ?', whereArgs: [id]);
  }

  String _encodePrefs(BookReaderPrefs prefs) {
    final map = prefs.toMap('')..remove('book_id');
    return jsonEncode(map);
  }

  LayoutPreset _fromRow(Map<String, Object?> row) {
    final prefsMap =
        (jsonDecode(row['prefs_json'] as String) as Map).cast<String, Object?>();
    return LayoutPreset(
      id: row['id'] as int,
      name: row['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      prefs: BookReaderPrefs.fromMap(prefsMap),
    );
  }
}
