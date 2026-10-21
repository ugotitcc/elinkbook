// app/lib/dictionary/storage/dictionary_store.dart
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/dictionary_entry.dart';
import '../models/dictionary_source.dart';

/// `dictionary.db` 的來源與詞條讀寫。
///
/// 持有 [DatabaseExecutor]（`Database` 或 `Transaction` 皆可），讓 [transaction]
/// 內的寫入跟著同一個交易。Issue 3 取消匯入時，整批寫入要能一起回復。
///
/// `headword_norm` 的公式只存在 [headwordNorm] 一處：寫入與查詢都呼叫它。
class DictionaryStore {
  DictionaryStore(this._db);

  final DatabaseExecutor _db;

  /// 在單一交易內執行 [action]；[action] 丟出例外時整個交易回復。
  /// 已經在交易內時直接執行，不巢狀開交易。
  ///
  /// **[action] 內只能使用參數給的 `store`。** 誤用外層的 store 會等不到交易
  /// 釋放連線而永遠卡住（sqflite 會把同一連線上的操作排隊）。
  Future<T> transaction<T>(Future<T> Function(DictionaryStore store) action) {
    final db = _db;
    if (db is Database) {
      return db.transaction((txn) => action(DictionaryStore(txn)));
    }
    return action(this);
  }

  /// [contentId] 是重複匯入偵測用的內容指紋，不屬於模型，只在這裡存取。
  Future<void> insertSource(DictionarySource source, {String? contentId}) async {
    await _db.insert(
      'dictionary_sources',
      {..._sourceToRow(source), 'content_id': contentId},
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// 以內容指紋找來源 id；找不到回傳 `null`。
  Future<String?> findSourceIdByContentId(String contentId) async {
    final rows = await _db.query(
      'dictionary_sources',
      columns: ['id'],
      where: 'content_id = ?',
      whereArgs: [contentId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  /// 找不到回傳 `null`。
  Future<DictionarySource?> getSource(String sourceId) async {
    final rows = await _db.query(
      'dictionary_sources',
      where: 'id = ?',
      whereArgs: [sourceId],
    );
    return rows.isEmpty ? null : _rowToSource(rows.single);
  }

  /// 依優先順序列出：數字小者在前，相同時依匯入時間再依 id。
  Future<List<DictionarySource>> listSources({bool enabledOnly = false}) async {
    final rows = await _db.query(
      'dictionary_sources',
      where: enabledOnly ? 'enabled = 1' : null,
      orderBy: 'priority ASC, imported_at ASC, id ASC',
    );
    final sources = <DictionarySource>[];
    for (final row in rows) {
      final source = _tryRowToSource(row);
      if (source != null) sources.add(source);
    }
    return sources;
  }

  Future<void> setEnabled(String sourceId, bool enabled) async {
    await _db.update(
      'dictionary_sources',
      {'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [sourceId],
    );
  }

  Future<void> setPriority(String sourceId, int priority) async {
    await _db.update(
      'dictionary_sources',
      {'priority': priority},
      where: 'id = ?',
      whereArgs: [sourceId],
    );
  }

  /// 以 JSON 陣列存入 `referenced_css`。
  Future<void> setReferencedCss(String sourceId, List<String> names) async {
    await _db.update(
      'dictionary_sources',
      {'referenced_css': jsonEncode(names)},
      where: 'id = ?',
      whereArgs: [sourceId],
    );
  }

  /// 在同一個交易內把 `priority` 重寫成 `0..n-1`（依 [orderedIds] 順序）。
  /// 不在清單內的來源不動；清單內不存在的 id 忽略且不佔序號。
  Future<void> reorderSources(List<String> orderedIds) {
    return transaction((store) async {
      // 只替真的更新到列的 id 編號，不存在的 id 不佔序號，避免留空號。
      var next = 0;
      for (final id in orderedIds) {
        final updated = await store._db.update(
          'dictionary_sources',
          {'priority': next},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (updated > 0) next++;
      }
    });
  }

  /// 刪除來源列；詞條由外鍵 `ON DELETE CASCADE` 連帶刪除。
  /// 來源不存在時不丟例外。
  Future<void> deleteSource(String sourceId) async {
    await _db.delete(
      'dictionary_sources',
      where: 'id = ?',
      whereArgs: [sourceId],
    );
  }

  /// 一次寫入多筆詞條，並計算 `headword_norm`。
  Future<void> insertEntries(List<DictionaryEntry> entries) async {
    final batch = _db.batch();
    for (final entry in entries) {
      batch.insert('dictionary_entries', _entryToRow(entry));
    }
    await batch.commit(noResult: true);
  }

  /// 查指定字典。查詢詞先套 [headwordNorm]，同一個詞頭多筆全回傳，依 id 排序。
  /// 去空白後為空字串時回傳空清單。
  Future<List<DictionaryEntry>> lookup(String sourceId, String word) async {
    final norm = headwordNorm(word);
    if (norm.isEmpty) return const [];
    final rows = await _db.query(
      'dictionary_entries',
      where: 'source_id = ? AND headword_norm = ?',
      whereArgs: [sourceId, norm],
      orderBy: 'id ASC',
    );
    return rows.map(_rowToEntry).toList();
  }

  Map<String, Object?> _sourceToRow(DictionarySource source) => {
        'id': source.id,
        'name': source.name,
        'format': source.format.name,
        'source_lang': source.sourceLang,
        'target_lang': source.targetLang,
        'priority': source.priority,
        'enabled': source.enabled ? 1 : 0,
        'storage_path': source.storagePath,
        'entry_count': source.entryCount,
        'license_note': source.licenseNote,
        // 截到毫秒：toIso8601String 在微秒不為 0 時會輸出 6 位小數，與 3 位
        // 小數的字串混在一起做文字排序會反。固定 3 位小數才能讓 ORDER BY 正確。
        'imported_at': DateTime.fromMillisecondsSinceEpoch(
          source.importedAt.millisecondsSinceEpoch,
          isUtc: true,
        ).toIso8601String(),
      };

  /// `format` 無法辨識（例如未來版本寫入的格式）回傳 `null`，由呼叫端略過。
  DictionarySource? _tryRowToSource(Map<String, Object?> row) {
    final format = DictionaryFormat.values.asNameMap()[row['format']];
    return format == null ? null : _rowToSource(row, format);
  }

  DictionarySource _rowToSource(Map<String, Object?> row,
          [DictionaryFormat? format]) =>
      DictionarySource(
        id: row['id'] as String,
        name: row['name'] as String,
        format: format ??
            DictionaryFormat.values.byName(row['format'] as String),
        sourceLang: row['source_lang'] as String,
        targetLang: row['target_lang'] as String,
        priority: row['priority'] as int,
        enabled: (row['enabled'] as int) == 1,
        storagePath: (row['storage_path'] as String?) ?? '',
        entryCount: row['entry_count'] as int,
        licenseNote: (row['license_note'] as String?) ?? '',
        importedAt: DateTime.parse(row['imported_at'] as String),
        referencedCss: _decodeCssNames(row['referenced_css']),
      );

  /// 空、`null`、壞 JSON、非陣列或含非字串元素 → 空清單。
  ///
  /// `referenced_css` 只是輔助資訊，壞掉不該讓整本字典讀不出來。
  List<String> _decodeCssNames(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    final names = <String>[];
    for (final item in decoded) {
      if (item is! String) return const [];
      names.add(item);
    }
    return names;
  }

  Map<String, Object?> _entryToRow(DictionaryEntry entry) => {
        'source_id': entry.sourceId,
        'headword': entry.headword,
        'headword_norm': headwordNorm(entry.headword),
        'pronunciation': entry.pronunciation,
        'part_of_speech': entry.partOfSpeech,
        'body': entry.body,
        'body_kind': entry.bodyKind.name,
      };

  DictionaryEntry _rowToEntry(Map<String, Object?> row) => DictionaryEntry(
        sourceId: row['source_id'] as String,
        headword: row['headword'] as String,
        pronunciation: row['pronunciation'] as String?,
        partOfSpeech: row['part_of_speech'] as String?,
        body: row['body'] as String,
        bodyKind: EntryBodyKind.values.byName(row['body_kind'] as String),
      );
}
