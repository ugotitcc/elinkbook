// app/lib/dictionary/storage/dictionary_database.dart
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 字典資料庫在真實裝置上的預設路徑（App 文件目錄下的 `dictionary.db`）。
/// 僅供正式執行時使用；單元測試改用 `sqflite_common_ffi` 的
/// `inMemoryDatabasePath` 或暫存目錄，不會呼叫到這個函式
/// （`path_provider` 需要平台 channel，無法在純 Dart 測試環境執行）。
Future<String> defaultDictionaryDatabasePath() async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'dictionary.db');
}

/// `dictionary.db`：與主庫（`library.db`）分開，自帶版本號。
///
/// 表結構逐字照 `spec.md` §4。不登錄 `sync_table_specs.dart`，字典資料不進同步。
abstract final class DictionaryDatabase {
  static const int version = 1;

  /// 開啟（或建立）字典資料庫。
  ///
  /// [singleInstance] 預設 `true`，與 `SqliteLibraryRepository.open` 一致；
  /// 測試要在同一個 process 開多個 `:memory:` 或重開同一個檔案時傳 `false`。
  static Future<Database> open(
    String path, {
    bool singleInstance = true,
  }) {
    return openDatabase(
      path,
      version: version,
      singleInstance: singleInstance,
      // 外鍵是連線層級設定，每次開啟都要設。只放 onCreate 的話，後續開啟時
      // ON DELETE CASCADE 會失效（做法同 sqlite_library_repository.dart）。
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE dictionary_sources (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            format TEXT NOT NULL,
            source_lang TEXT NOT NULL,
            target_lang TEXT NOT NULL,
            priority INTEGER NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            storage_path TEXT,
            content_id TEXT,
            referenced_css TEXT,
            entry_count INTEGER NOT NULL DEFAULT 0,
            license_note TEXT,
            imported_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE dictionary_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_id TEXT NOT NULL REFERENCES dictionary_sources(id) ON DELETE CASCADE,
            headword TEXT NOT NULL,
            headword_norm TEXT NOT NULL,
            pronunciation TEXT,
            part_of_speech TEXT,
            body TEXT NOT NULL,
            body_kind TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_entries_lookup ON dictionary_entries(source_id, headword_norm)',
        );
      },
    );
  }
}
