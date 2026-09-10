import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

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

  /// 開啟（或建立）圖書庫資料庫。
  ///
  /// [singleInstance] 預設 `true`（與 sqflite 套件本身預設一致）：對同一個
  /// 字面路徑字串重複呼叫本方法會回傳同一個底層連線，正式環境下這是正確
  /// 且需要的行為（避免對同一個真實檔案開出多條連線）。**但若要在同一個
  /// process 內用相同的 [inMemoryDatabasePath]（`":memory:"`）開出多個彼此
  /// 獨立的記憶體內資料庫（例如整合測試中模擬「多台裝置各自的本機資料
  /// 庫」），必須明確傳入 `singleInstance: false`**——sqflite 的 Dart 層快取
  /// （`databaseOpenHelpers`，見 `sqflite_common` `factory_mixin.dart`）是以
  /// 字面路徑字串為 key，不會因為路徑是 `:memory:` 就自動視為獨立（
  /// epic-8-sync Issue 8 實測驗證，見 `plans/plan-issue-8.md`）。
  static Future<SqliteLibraryRepository> open(
    String path, {
    bool singleInstance = true,
  }) async {
    final db = await openDatabase(
      path,
      version: 24,
      singleInstance: singleInstance,
      onConfigure: (db) async {
        // book_reader_prefs 的 ON DELETE CASCADE 需要外鍵約束真正生效，
        // SQLite 預設不強制外鍵，須逐連線手動開啟（見 epic-3 plan-issue-1）。
        //
        // epic-8-sync Issue 1（spec 審查修正 Critical 1，見
        // tmp/epic-8/plan-issue-1-review.md）：sqflite 的 onUpgrade 回呼
        // 整段跑在它自動包住的一個交易內（見 sqflite_common
        // database_mixin.dart `doOpen()` 的
        // `await transaction((txn) async { ... await options.onUpgrade!(...); ... })`，
        // 已對照本專案實際鎖定的 sqflite_common 2.5.8 原始碼確認），而
        // SQLite 官方規定 PRAGMA foreign_keys 在交易開啟期間無法切換
        // （靜默 no-op，不報錯但也不生效）。因此**不能**在 onUpgrade
        // 內部切換這個 pragma——改在交易外的 onConfigure（此處）判斷
        // 「是否即將觸發 Issue 1 的 bookmarks/highlights/notes 主鍵
        // UUID 遷移」並提前關閉外鍵檢查；遷移過程中的中繼狀態（例如
        // highlights 表被 rename 又重建期間，notes 表的外鍵暫時指向
        // 不存在的目標）因此不會被擋下。遷移完成後由下方 onOpen（同樣
        // 在交易外）恢復開啟。
        final currentVersion = await db.getVersion();
        final upgradingPastAnnotationUuidMigration =
            currentVersion > 0 && currentVersion < 17;
        await db.execute(
          'PRAGMA foreign_keys = ${upgradingPastAnnotationUuidMigration ? 'OFF' : 'ON'}',
        );
        await db.execute('PRAGMA recursive_triggers = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE groups (
            name TEXT PRIMARY KEY
          )
        ''');
        await db.insert('groups', {'name': BookGroup.uncategorized});
        await _createRemoteServersTable(db);
        // 【epic-26-architecture-hardening Issue 5】totalCharacterCount 欄位
        // 自 Issue 5 起不再被任何 Dart 程式碼讀寫（Book 模型已移除對應欄位）
        // ——刻意保留於 schema 中不刪除，因 ALTER TABLE DROP COLUMN 需要
        // SQLite 3.35+，本專案 minSdk=24 對應的系統內建 SQLite 版本無法
        // 保證支援，見 plan-issue-5.md Global Constraints。
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
            groupName TEXT NOT NULL DEFAULT '${BookGroup.uncategorized}',
            createTime INTEGER NOT NULL,
            lastReadTime INTEGER NOT NULL,
            content_fingerprint TEXT,
            position_updated_at INTEGER,
            position_synced_server_updated_at TEXT,
            remote_server_id TEXT REFERENCES remote_servers(id) ON DELETE SET NULL,
            remote_book_id TEXT,
            remote_download_url TEXT,
            is_downloaded INTEGER NOT NULL DEFAULT 1,
            cloud_file_id TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_books_remote_lookup ON books(remote_server_id, remote_book_id)');
        await db.execute(
            'CREATE INDEX idx_books_content_fingerprint ON books(content_fingerprint)');
        await db.execute(
            'CREATE INDEX idx_books_cloud_file_id ON books(cloud_file_id)');
        await _createBookReaderPrefsTable(db);
        await _createBookmarksTable(db);
        await _createHighlightsTable(db);
        await _createNotesTable(db);
        await _createCustomFontsTable(db);
        await _createSyncMetadataTable(db);
        await _createSyncRemoteIdsTable(db);
        await _createSyncPendingRecordsTable(db);
        await _createLayoutPresetTable(db);
        await _createContentIndexStatusTable(db);
        await _createBookContentIndexTable(db);
        await _createBookContentFtsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 舊裝置從未有過 book_reader_prefs 表，_createBookReaderPrefsTable
          // 目前的 CREATE TABLE 已包含全部欄位（含 PDF、雙頁），一步到位，
          // 不需要再跑後續的 ALTER TABLE（該表在這之前根本不存在）。
          await _createBookReaderPrefsTable(db);
        } else {
          // 【審查修正】原本此處用「if (oldVersion < 2) { ...; return; }」
          // 提前結束整個 onUpgrade，這對 book_reader_prefs 表本身是對的
          // （表剛建好、不需要再 ALTER），但會連帶跳過下方 books 表的
          // oldVersion < 5 遷移——version 1 裝置跳級升級到 version 5 時，
          // books 表會缺少 epubLocator/pdfPageIndex 欄位，實際讀寫時拋出
          // `no such column` 崩潰（`/superpowers:requesting-code-review`
          // 審查報告 Critical 1 發現）。改為 if/else：只有當
          // book_reader_prefs 表已存在（oldVersion >= 2）時，才需要用
          // ALTER TABLE 逐步補上該表後續版本新增的欄位；books 表的遷移
          // 移到 if/else 區塊外、不受此分支影響，確保任何 oldVersion 都會
          // 執行到。
          if (oldVersion < 3) {
            await _addPdfReaderPrefsColumns(db);
          }
          if (oldVersion < 4) {
            await _addDualPageColumns(db);
          }
          if (oldVersion < 7) {
            // epic-5-toc-pagination Issue 5：頁首/頁尾顯示切換新增的 2 個
            // 欄位，補追加到既有（version 2 起已存在）的 book_reader_prefs
            // 表。放在 else 分支內（oldVersion >= 2）——因為 oldVersion < 2
            // 時 _createBookReaderPrefsTable 已一步到位建表含
            // show_header/show_footer，不需要再 ALTER TABLE。
            await _addHeaderFooterColumns(db);
          }
          if (oldVersion < 12) {
            // epic-18-reader-device-qa Issue 5：強制單欄版面偏好新增的 1
            // 個欄位，補追加到既有（version 2 起已存在）的
            // book_reader_prefs 表。必須放在 else 分支內（oldVersion >= 2）
            // ——理由同上：oldVersion < 2 時 _createBookReaderPrefsTable
            // 已一步到位建表含 single_column，若在 else 分支外無條件執行
            // ALTER TABLE，oldVersion == 1 的裝置會對剛建好、已有該欄位的
            // 表重複 ALTER TABLE，拋出 duplicate column name 例外。
            await _addSingleColumnColumn(db);
          }
          if (oldVersion < 13) {
            // epic-18-reader-device-qa Issue 6：欄數/欄位大小新增的 2 個欄位。
            // 必須放在 else 分支內（oldVersion >= 2）——理由同 _addSingleColumnColumn：
            // oldVersion < 2 時 _createBookReaderPrefsTable 已一步到位建表含 column_mode/column_size，
            // 若在 else 分支外無條件執行 ALTER TABLE，oldVersion == 1 的裝置會重複 ALTER TABLE 拋出崩潰。
            await _addColumnModeColumns(db);
          }
          if (oldVersion < 14) {
            // epic-18-reader-device-qa Issue 14：邊距 4 個獨立欄位。必須
            // 放在 else 分支內（oldVersion >= 2）——理由同
            // _addColumnModeColumns：oldVersion < 2 時
            // _createBookReaderPrefsTable 已一步到位建表含這 4 個欄位，若
            // 在 else 分支外無條件執行 ALTER TABLE，oldVersion == 1 的
            // 裝置會重複 ALTER TABLE 拋出崩潰。既有 page_margins 欄位不
            // 受影響、不做任何遷移（見 ADR 0014）。
            await _addMarginColumns(db);
          }
          if (oldVersion < 15) {
            // epic-19-shelf-reading-enhance Issue 1：全螢幕模式開關新增的
            // 1 個欄位。必須放在 else 分支內（oldVersion >= 2）——理由同
            // _addMarginColumns：oldVersion < 2 時 _createBookReaderPrefsTable
            // 已一步到位建表含 fullscreen，若在 else 分支外無條件執行
            // ALTER TABLE，oldVersion == 1 的裝置會重複 ALTER TABLE 拋出
            // 崩潰。
            await _addFullscreenColumn(db);
          }
          if (oldVersion < 16) {
            // epic-14-system-settings Issue 1：font_family 型別由 AppFont
            // 封閉列舉字串改為任意 family name 字串（決策 2），既有 5
            // 種列舉值資料需逐筆轉換。必須放在 else 分支內（oldVersion
            // >= 2，即 book_reader_prefs 表已存在）——oldVersion < 2 時
            // 該表剛由 _createBookReaderPrefsTable 全新建立，不會有任何
            // 舊格式資料需要轉換。
            await _migrateFontFamilyValues(db);
          }
          if (oldVersion < 19) {
            // epic-28-reader-settings-enhancements Issue 1：字距新增的 1
            // 個欄位。必須放在 else 分支內（oldVersion >= 2）——理由同
            // _migrateFontFamilyValues：oldVersion < 2 時
            // _createBookReaderPrefsTable 已一步到位建表含
            // letter_spacing，若在 else 分支外無條件執行 ALTER TABLE，
            // oldVersion == 1 的裝置會重複 ALTER TABLE 拋出崩潰。
            await _addLetterSpacingColumn(db);
          }
          if (oldVersion < 20) {
            // epic-24-pdf-engine-rebuild Issue 11：PDF 換頁動畫新增的 1
            // 個欄位。必須放在 else 分支內（oldVersion >= 2）——理由同
            // _addLetterSpacingColumn：oldVersion < 2 時
            // _createBookReaderPrefsTable 已一步到位建表含
            // pdf_page_turn_animation，若在 else 分支外無條件執行
            // ALTER TABLE，oldVersion == 1 的裝置會重複 ALTER TABLE 拋出
            // 崩潰。
            await _addPdfPageTurnAnimationColumn(db);
          }
        }
        if (oldVersion < 5) {
          // epic-5-toc-pagination Issue 2：本機閱讀位置記憶新增的 2 個
          // 欄位，補追加到既有（version 1 起已存在）的 books 表。刻意放在
          // 上方 if/else 之外、無條件檢查——books 表與 book_reader_prefs
          // 是兩張獨立的表，此欄位遷移不論裝置目前處於哪個舊版本，只要
          // oldVersion < 5 就必須執行，不能被 book_reader_prefs 表的建立
          // /升級分支影響。
          await _addReadingPositionColumns(db);
        }
        if (oldVersion < 6) {
          // epic-5-toc-pagination Issue 3：全書字元數快取欄位，補追加到
          // 既有（version 1 起已存在）的 books 表。刻意放在上方 if/else
          // 之外、無條件檢查，比照 oldVersion < 5 區塊的既有原則——不論
          // 裝置目前處於哪個舊版本，只要 oldVersion < 6 就必須執行。
          await _addTotalCharacterCountColumn(db);
        }
        if (oldVersion < 8) {
          // epic-6-annotations Issue 1：書籤功能新增的全新資料表。與上方
          // books 表遷移刻意放在同一層級（onUpgrade 頂層、無條件檢查）——
          // bookmarks 是全新的獨立表（非既有表新增欄位），任何 oldVersion
          // < 8 的裝置都必然還沒有這張表，直接無條件建立即可，不像
          // book_reader_prefs 表那樣需要判斷「表是否已存在」（那是因為
          // book_reader_prefs 有 CREATE／ALTER 兩條分歧路徑，bookmarks
          // 只有一條路徑）。
          await _createBookmarksTable(db);
        }
        if (oldVersion < 9) {
          // epic-6-annotations Issue 2：劃線／備註功能新增的兩張全新
          // 資料表。與 bookmarks 表（oldVersion < 8）比照同一原則——
          // 任何 oldVersion < 9 的裝置都必然還沒有這兩張表，無條件建立
          // 即可，不需要判斷「表是否已存在」。順序先建 highlights 再建
          // notes（notes.highlight_id 參照 highlights，見 spec.md「資料
          // 模型關聯」審查修正 1.1 的程式碼可讀性慣例）。_createHighlightsTable／
          // _createNotesTable 已是 version 10 的最終欄位組合（含 Issue 3
          // 的 PDF 欄位），一步到位，故此分支之後不需要再跑
          // _addPdfAnnotationColumns（否則會對剛建好、已有該欄位的表
          // ALTER TABLE，拋出 duplicate column name 例外）。
          await _createHighlightsTable(db);
          await _createNotesTable(db);
        } else if (oldVersion < 10) {
          // epic-6-annotations Issue 3：oldVersion 為 9 的裝置，
          // highlights／notes 表已存在（上方 if 分支已處理過），但欄位
          // 版本停留在 Issue 2（無 PDF 欄位），僅需 ALTER TABLE 補上。
          await _addPdfAnnotationColumns(db);
        }
        if (oldVersion < 11) {
          // epic-17-epub-render-migration Issue 2：EPUB FXL/流式判斷快取
          // 欄位，補追加到既有（version 1 起已存在）的 books 表，見
          // docs/epics/epic-17-epub-render-migration/spec.md「資料模型」。
          // 刻意放在上方 if/else 之外、無條件檢查，比照 oldVersion < 5/6
          // 區塊的既有原則。
          await _addEpubLayoutColumn(db);
        }
        if (oldVersion < 16) {
          // epic-14-system-settings Issue 1：自訂字型清單新增的全新資料表。
          // 【審查修正，見 tmp/epic-14/review-issue-1.md Critical 1】原本
          // 誤放在上方 if/else 的 else 分支內（oldVersion >= 2 才會執行），
          // 導致停留在 version 1 的裝置跳級升級到 16 時，這張表完全不會
          // 被建立——與 bookmarks（oldVersion < 8）／highlights／notes
          // （oldVersion < 9）比照同一原則，custom_fonts 是全新的獨立表
          // （非既有表新增欄位），任何 oldVersion < 16 的裝置都必然還沒有
          // 這張表，應與上方 books 表遷移／bookmarks／highlights／notes
          // 同一層級（onUpgrade 頂層、無條件檢查），不受 book_reader_prefs
          // 表是否已存在影響。
        await _createCustomFontsTable(db);
        }
        if (oldVersion < 17) {
          // epic-8-sync Issue 1：雲端同步新增的欄位與主鍵型別變更（見
          // docs/epics/epic-8-sync/spec.md「本機 Schema 變更」／
          // 「Migration」）。刻意放在 onUpgrade 頂層、無條件檢查，比照
          // oldVersion < 5/6/8/9/11/16 既有原則——books 表新增欄位與
          // bookmarks/highlights/notes 主鍵遷移皆與 book_reader_prefs
          // 表是否已存在無關。**外鍵約束的暫停/恢復不在這裡處理**——
          // onUpgrade 整段跑在 sqflite 自動包住的交易內，PRAGMA
          // foreign_keys 在交易開啟期間無法切換（SQLite 官方規定，
          // spec 審查修正 Critical 1，見 tmp/epic-8/plan-issue-1-review.md），
          // 已改在上方 onConfigure（交易外）判斷並提前關閉、下方 onOpen
          // （同樣交易外）之後恢復。
          await db.execute(
              'ALTER TABLE books ADD COLUMN content_fingerprint TEXT');
          await db.execute(
              'ALTER TABLE books ADD COLUMN position_updated_at INTEGER');
          await db.execute(
              'ALTER TABLE books ADD COLUMN position_synced_server_updated_at TEXT');
          await _migrateAnnotationTablesToUuid(db);
          await _createSyncMetadataTable(db);
        }
        if (oldVersion < 18) {
          // epic-8-sync Issue 4：推送 create/update 判斷所需的本機 remote id
          // 對照表，以及 book_fingerprint 查無對應本機書籍時的待處理佇列
          // （見 spec.md「跨裝置參照設計」／plan-issue-4.md「與 issues.md／
          // spec.md 的落差說明」）。兩者皆是全新的獨立表（非既有表新增
          // 欄位），比照 oldVersion < 8/9/16 既有原則，同一層級、無條件
          // 檢查即可。
          await _createSyncRemoteIdsTable(db);
          await _createSyncPendingRecordsTable(db);
        }
        if (oldVersion < 21) {
          // epic-28-reader-settings-enhancements Issue 3：版面設定預設集
          // 新增的全新獨立資料表（非既有表新增欄位）。與 bookmarks
          // （oldVersion < 8）／custom_fonts（oldVersion < 16）比照同一
          // 原則——任何 oldVersion < 21 的裝置都必然還沒有這張表，直接
          // 無條件建立即可，不需要放在 book_reader_prefs 表是否已存在的
          // if/else 分支內。
          await _createLayoutPresetTable(db);
        }
        if (oldVersion < 22) {
          // epic-30-calibre-remote-library Issue 0：Calibre／OPDS 遠端書架
          // 站點表，以及 books 表新增的 4 個欄位（見 spec.md「資料模型與
          // Schema」）。remote_servers 是全新獨立表，比照 bookmarks
          // （oldVersion < 8）／custom_fonts（oldVersion < 16）既有原則，
          // 無條件建立即可；books 表 4 個新欄位皆為 nullable 或有預設值，
          // 既有資料升級後自動補上預設值，不影響既有資料。
          //
          // remote_server_id 內聯宣告 REFERENCES remote_servers(id) ON
          // DELETE SET NULL：實測確認 sqflite 底層 SQLite 版本支援
          // ALTER TABLE ADD COLUMN 搭配 REFERENCES 子句（本欄位為
          // nullable、無 NOT NULL 約束，符合 SQLite 官方文件對 ADD
          // COLUMN 搭配 REFERENCES 的唯一限制）。若未來 sqflite/SQLite
          // 版本升級後這個假設不再成立，改為移除此處的 REFERENCES 子句、
          // 只留 `remote_server_id TEXT`，並在 Issue 1 的
          // `RemoteServerRepository.deleteServer()` 內改為應用層手動
          // `UPDATE books SET remote_server_id = NULL WHERE remote_server_id = ?`
          // 達成同等行為（見 spec.md「技術風險與備援方案」）。
          await _createRemoteServersTable(db);
          await db.execute(
              'ALTER TABLE books ADD COLUMN remote_server_id TEXT REFERENCES remote_servers(id) ON DELETE SET NULL');
          await db.execute(
              'ALTER TABLE books ADD COLUMN remote_book_id TEXT');
          await db.execute(
              'ALTER TABLE books ADD COLUMN remote_download_url TEXT');
          await db.execute(
              'ALTER TABLE books ADD COLUMN is_downloaded INTEGER NOT NULL DEFAULT 1');
          await db.execute(
              'CREATE INDEX idx_books_remote_lookup ON books(remote_server_id, remote_book_id)');
        }
        if (oldVersion < 23) {
          // epic-29-cloud-import Issue 0：雲端匯入（Google Drive／OneDrive）
          // 選檔前置重複偵測所需的 books 表新增欄位，見 spec.md「資料模型與
          // Schema」。cloud_file_id 為 nullable，既有資料升級後自動為
          // NULL，不影響既有資料。同一次 migration 一併補上
          // content_fingerprint 的索引——經核對此欄位自 epic-8-sync Issue 3
          // 引入以來從未建過索引，雲端匯入的下載後指紋比對（Issue 5）與
          // 既有同步引擎的指紋比對皆是高頻查詢，值得藉這次 migration 一併
          // 補上，避免書籍量大時全表掃描（spec.md 審查 Important #3）。
          await db.execute('ALTER TABLE books ADD COLUMN cloud_file_id TEXT');
          await db.execute(
              'CREATE INDEX idx_books_cloud_file_id ON books(cloud_file_id)');
          await db.execute(
              'CREATE INDEX idx_books_content_fingerprint ON books(content_fingerprint)');
        }
        if (oldVersion < 24) {
          // epic-10-search Issue 0：全文檢索三張新表，皆為全新獨立表
          // （非既有表新增欄位），比照 bookmarks（oldVersion < 8）／
          // custom_fonts（oldVersion < 16）等既有原則，無條件建立即可。
          await _createContentIndexStatusTable(db);
          await _createBookContentIndexTable(db);
          await _createBookContentFtsTable(db);
        }
      },
      onOpen: (db) async {
        // epic-8-sync Issue 1（spec 審查修正 Critical 1）：onConfigure
        // 可能因為即將進行 Issue 1 的主鍵遷移而暫時關閉外鍵約束，
        // onOpen 在 sqflite 的自動交易之外執行（見上方 onConfigure
        // 註解），無條件恢復開啟，確保遷移完成後**同一個連線、同一次
        // App 啟動**的剩餘期間（不是要等到下一次重開 App）外鍵約束不會
        // 停留在關閉狀態、影響既有的 CASCADE／SET NULL 行為。對沒有
        // 觸發遷移的一般情況（onConfigure 已經是 ON）這裡只是無害的
        // 重複開啟。
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    return SqliteLibraryRepository._(db);
  }

  static Future<void> _createBookReaderPrefsTable(Database db) async {
    // 單書版面偏好設定（epic-3-fonts-layout FR-09/FR-10、epic-4-pdf-enhance
    // FR-11、epic-16-dual-page FR-41），與 books 表 1:1 關聯；所有欄位皆為
    // nullable，null 代表未覆寫，見 docs/epics/epic-4-pdf-enhance/spec.md
    // 「資料模型」與 docs/epics/epic-16-dual-page/spec.md「資料模型」。
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
        margin_right REAL,
        fullscreen INTEGER,
        letter_spacing REAL,
        pdf_page_turn_animation TEXT
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

  static Future<void> _addDualPageColumns(Database db) async {
    // 橫向雙頁顯示（epic-16-dual-page FR-41）新增的 3 個欄位，補追加到
    // 既有（version 3 起已存在）的 book_reader_prefs 表，見
    // docs/epics/epic-16-dual-page/spec.md「資料模型」。
    await db.execute(
        'ALTER TABLE book_reader_prefs ADD COLUMN dual_page_mode TEXT');
    await db.execute(
        'ALTER TABLE book_reader_prefs ADD COLUMN dual_page_cover_alone INTEGER');
    await db.execute(
        'ALTER TABLE book_reader_prefs ADD COLUMN dual_page_direction TEXT');
  }

  static Future<void> _addReadingPositionColumns(Database db) async {
    // 本機閱讀位置記憶（epic-5-toc-pagination Issue 2）新增的 2 個欄位，
    // 補追加到既有（version 1 起已存在）的 books 表，見
    // docs/epics/epic-5-toc-pagination/spec.md「本機閱讀位置記憶」。
    await db.execute('ALTER TABLE books ADD COLUMN epubLocator TEXT');
    await db.execute('ALTER TABLE books ADD COLUMN pdfPageIndex INTEGER');
  }

  static Future<void> _addTotalCharacterCountColumn(Database db) async {
    // 全書字元數快取（epic-5-toc-pagination Issue 3）新增的 1 個欄位，
    // 補追加到既有（version 1 起已存在）的 books 表，見
    // docs/epics/epic-5-toc-pagination/spec.md「分頁估算模組」決策 #16。
    await db.execute('ALTER TABLE books ADD COLUMN totalCharacterCount INTEGER');
  }

  static Future<void> _addHeaderFooterColumns(Database db) async {
    // 頁首/頁尾顯示切換（epic-5-toc-pagination Issue 5）新增的 2 個欄位，
    // 補追加到既有（version 2 起已存在）的 book_reader_prefs 表，見
    // docs/epics/epic-5-toc-pagination/spec.md「頁首/頁尾顯示切換」。
    // 僅在表已存在時才執行 ALTER TABLE（某些測試情境下 oldVersion >= 2
    // 但 book_reader_prefs 表可能不存在，見 v5→v6 升級測試）。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN show_header INTEGER');
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN show_footer INTEGER');
    }
  }

  static Future<void> _createBookmarksTable(Database db) async {
    // 書籤（epic-6-annotations Issue 1，spec.md「書籤模組」），與 books
    // 表以 book_id 外鍵關聯（比照 book_reader_prefs 既有關聯模式，見
    // docs/epics/epic-6-annotations/spec.md「資料模型關聯」）。與
    // book_reader_prefs 不同，一本書可以有多筆書籤，故不用 book_id 當
    // PRIMARY KEY，改用獨立的 UUID 識別碼（epic-8-sync Issue 1）。
    // updated_at／deleted_at 供雲端同步使用（見 docs/epics/epic-8-sync/
    // spec.md「本機 Schema 變更」）：每次本機新增/修改時寫入目前時間戳記
    // （由 BookmarksRepository 負責維護，非本函式或 Bookmark 模型本身
    // 的職責），deleted_at 目前恆為 NULL（軟刪除轉換是 Issue 4 的範圍，
    // 本 Issue 的 delete() 仍是真正的 DELETE FROM，見 plan-issue-1.md
    // 審查修正紀錄）。
    await db.execute('''
      CREATE TABLE bookmarks (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        pdf_page_index INTEGER,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');
  }

  static Future<void> _createHighlightsTable(Database db) async {
    // 劃線（epic-6-annotations Issue 2/3，spec.md「劃線與備註模組」），與
    // books 表以 book_id 外鍵關聯（比照 bookmarks 既有關聯模式）。
    // pdf_page_index／pdf_rect_json（Issue 3 新增）與
    // epub_locator_json／progression（Issue 2）互斥，依書籍格式擇一填入。
    // epic-8-sync Issue 1：主鍵改為 UUID TEXT，updated_at／deleted_at
    // 供雲端同步使用（見 _createBookmarksTable 同一段說明）。
    await db.execute('''
      CREATE TABLE highlights (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        style TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        pdf_page_index INTEGER,
        pdf_rect_json TEXT,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');
  }

  static Future<void> _createNotesTable(Database db) async {
    // 備註（epic-6-annotations Issue 2/3，spec.md「資料模型關聯」）：
    // highlight_id 為可空外鍵，ON DELETE SET NULL——批次刪除劃線後，
    // 依附的備註自動退化為純備註（highlight_id 變 null），不需應用層
    // 判斷邏輯。建表順序刻意晚於 _createHighlightsTable（程式碼可讀性
    // 慣例，非技術硬性要求，見 spec.md 審查修正 1.1）。
    // epic-8-sync Issue 1：主鍵改為 UUID TEXT，highlight_id 改為 TEXT，
    // updated_at／deleted_at 供雲端同步使用（見 _createBookmarksTable
    // 同一段說明）。
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        highlight_id TEXT REFERENCES highlights(id) ON DELETE SET NULL,
        pdf_page_index INTEGER,
        pdf_rect_json TEXT,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');
  }

  static Future<void> _addPdfAnnotationColumns(Database db) async {
    // epic-6-annotations Issue 3：PDF 專屬的劃線/備註定位欄位，補追加到
    // 既有（version 9 起已存在）的 highlights／notes 兩張表。只有
    // oldVersion == 9（表已存在但無這兩欄位）的裝置會走到這個函式，見
    // onUpgrade 的 if/else 互斥結構。
    await db.execute('ALTER TABLE highlights ADD COLUMN pdf_page_index INTEGER');
    await db.execute('ALTER TABLE highlights ADD COLUMN pdf_rect_json TEXT');
    await db.execute('ALTER TABLE notes ADD COLUMN pdf_page_index INTEGER');
    await db.execute('ALTER TABLE notes ADD COLUMN pdf_rect_json TEXT');
  }

  static Future<void> _addEpubLayoutColumn(Database db) async {
    // EPUB FXL/流式判斷快取（epic-17-epub-render-migration Issue 2），補
    // 追加到既有（version 1 起已存在）的 books 表，見
    // docs/epics/epic-17-epub-render-migration/spec.md「資料模型」。
    // nullable：NULL=尚未判斷、0=流式、1=FXL。比照 _addHeaderFooterColumns
    // 既有慣例，僅在表已存在時才執行 ALTER TABLE。
    final tables = await db
        .rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='books'");
    if (tables.isNotEmpty) {
      await db.execute('ALTER TABLE books ADD COLUMN is_fixed_layout INTEGER');
    }
  }

  static Future<void> _addSingleColumnColumn(Database db) async {
    // 強制單欄版面偏好（epic-18-reader-device-qa Issue 5），補追加到既有
    // （version 2 起已存在）的 book_reader_prefs 表，見
    // docs/epics/epic-18-reader-device-qa/spec.md「singleColumn 偏好」。
    // nullable：NULL=未覆寫（交由 foliate-js 內建 --_max-column-count: 2
    // 自動判斷）、0=false、1=true。比照 _addHeaderFooterColumns／
    // _addEpubLayoutColumn 既有慣例，僅在表已存在時才執行 ALTER TABLE。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN single_column INTEGER');
    }
  }

  static Future<void> _addColumnModeColumns(Database db) async {
    // epic-18-reader-device-qa Issue 6：欄數/欄位大小新增的 2 個欄位，
    // 補追加到既有（version 2 起已存在）的 book_reader_prefs 表。
    // issues.md 明確要求：既有 single_column 欄位所有值遷移為 NULL（等同自動）。
    // 比照 _addHeaderFooterColumns 既有慣例，僅在表已存在時才執行 ALTER TABLE。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN column_mode TEXT');
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN column_size REAL');
      // issues.md 明確要求：既有 single_column 欄位所有值遷移為 NULL（等同自動）
      await db.execute('UPDATE book_reader_prefs SET single_column = NULL');
    }
  }

  static Future<void> _addMarginColumns(Database db) async {
    // epic-18-reader-device-qa Issue 14：上/下/左/右邊距 4 個獨立欄位，
    // 補追加到既有（version 2 起已存在）的 book_reader_prefs 表。既有
    // page_margins 欄位不受影響、不遷移既有值（見 ADR 0014，本次新欄位
    // 僅供流式 EPUB 使用，page_margins 繼續供 EpubReaderView／FXL 使用）。
    // 比照 _addColumnModeColumns 既有慣例，僅在表已存在時才執行
    // ALTER TABLE。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN margin_top REAL');
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN margin_bottom REAL');
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN margin_left REAL');
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN margin_right REAL');
    }
  }

  static Future<void> _addFullscreenColumn(Database db) async {
    // epic-19-shelf-reading-enhance Issue 1：全螢幕模式開關欄位，補追加到
    // 既有（version 2 起已存在）的 book_reader_prefs 表。比照
    // _addMarginColumns 既有慣例，僅在表已存在時才執行 ALTER TABLE。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN fullscreen INTEGER');
    }
  }

  static Future<void> _addLetterSpacingColumn(Database db) async {
    // epic-28-reader-settings-enhancements Issue 1：字距欄位，補追加到既有
    // （version 2 起已存在）的 book_reader_prefs 表。比照 _addFullscreenColumn
    // 既有慣例，僅在表已存在時才執行 ALTER TABLE。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN letter_spacing REAL');
    }
  }

  static Future<void> _addPdfPageTurnAnimationColumn(Database db) async {
    // epic-24-pdf-engine-rebuild Issue 11：PDF 換頁動畫欄位，補追加到既有
    // （version 2 起已存在）的 book_reader_prefs 表。比照 _addLetterSpacingColumn
    // 既有慣例，僅在表已存在時才執行 ALTER TABLE。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN pdf_page_turn_animation TEXT');
    }
  }

  static Future<void> _createCustomFontsTable(Database db) async {
    // 自訂字型清單（epic-14-system-settings FR-35），見
    // docs/epics/epic-14-system-settings/spec.md「字型管理模組」。字型檔案
    // 本身不落地複本（ADR 0021），font_uri 存 content:// URI。
    await db.execute('''
      CREATE TABLE custom_fonts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        display_name TEXT NOT NULL,
        family_name TEXT NOT NULL UNIQUE,
        font_uri TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _migrateFontFamilyValues(Database db) async {
    // book_reader_prefs.font_family 型別由 AppFont 封閉列舉字串改為任意
    // family name 字串（epic-14-system-settings 決策 2），既有 5 種列舉
    // 值資料需逐筆轉換為對應的實際 family name（取自 app_font.dart 現行
    // AppFontFamilyName.familyName），NULL 不受影響。僅在表與欄位皆存在
    // 時才執行——真實裝置 oldVersion >= 2 時 book_reader_prefs 表與
    // font_family 欄位必然存在（該欄位自 version 2 起就一直存在，從未
    // 透過 ALTER TABLE 後補），但本測試檔內多個既有、與本次無關的舊版
    // 資料庫測試 fixture（例如「既有 version 4/5/9/10 裝置升級」等測試）
    // 為了只聚焦驗證 books 表遷移，刻意省略建立 book_reader_prefs 表，
    // 此防禦查詢是為了不讓這些既有測試因此拋出 `no such table`／
    // `no such column` 例外而失敗（曾嘗試移除、經 `flutter test` 實測
    // 證實會連帶打壞 4 個既有測試，見 tmp/epic-14/review-issue-1.md
    // Minor 3 的簡化建議在此專案的既有測試現況下不成立，予以保留）。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isEmpty) return;
    final columns = await db.rawQuery("PRAGMA table_info(book_reader_prefs)");
    final hasFontFamily = columns.any((c) => c['name'] == 'font_family');
    if (!hasFontFamily) return;
    const legacyToFamilyName = {
      'sourceHanSans': 'SourceHanSansTC',
      'sourceHanSerif': 'SourceHanSerifTC',
      'guanKiapTsingKhai': 'GuanKiapTsingKhai',
      'taiwanPearl': 'TaiwanPearl',
      'genRyuMinTW': 'GenRyuMinTW',
    };
    for (final entry in legacyToFamilyName.entries) {
      await db.update(
        'book_reader_prefs',
        {'font_family': entry.value},
        where: 'font_family = ?',
        whereArgs: [entry.key],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // epic-8-sync Issue 1：雲端同步所需的私有遷移方法
  // ---------------------------------------------------------------------------

  static Future<void> _createSyncMetadataTable(Database db) async {
    // 同步中繼資料（epic-8-sync，spec.md「本機 Schema 變更」）：單列表
    // （id 恆為 1，CHECK 約束防止意外插入第二列）。
    // last_push_completed_at 為純本機時鐘（dirty 判斷用，只跟自己過去
    // 的寫入比較，不受其他裝置時鐘影響）；4 個
    // last_pulled_server_updated_at_<collection> 為 PocketBase 伺服器
    // 蓋章時間戳記字串（下載游標），刻意不用本機時鐘產生，用來規避
    // 裝置時鐘偏差問題（spec.md 審查修正）。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_metadata (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_push_completed_at INTEGER,
        last_pulled_server_updated_at_bookmarks TEXT,
        last_pulled_server_updated_at_highlights TEXT,
        last_pulled_server_updated_at_notes TEXT,
        last_pulled_server_updated_at_reading_positions TEXT
      )
    ''');
    // conflictAlgorithm: ignore 是防禦性寫法：本函式在 onCreate（全新
    // 安裝）與 onUpgrade 的 if (oldVersion < 17) 分支（既有裝置升級）
    // 各被呼叫一次，兩者互斥，理論上不會有既存 id=1 列衝突；加上
    // ignore 是零成本的保險。
    await db.insert(
      'sync_metadata',
      {'id': 1},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> _createSyncRemoteIdsTable(Database db) async {
    // client_id -> PocketBase 該筆紀錄真正 id 的對照表（epic-8-sync
    // Issue 4，spec.md「跨裝置參照設計」；精確理由見
    // docs/epics/epic-8-sync/plans/plan-issue-4.md Task 1）：PocketBase
    // 自己的 id 系統欄位不接受本專案 UUID（含連字號）格式，且 App 端
    // 完全不比對它，因此需要本機自己維護這份對照，供推送時判斷該送
    // create（查無對照）還是 update（查到對照，帶入該 id）。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_remote_ids (
        collection TEXT NOT NULL,
        client_id TEXT NOT NULL,
        remote_id TEXT NOT NULL,
        PRIMARY KEY (collection, client_id)
      )
    ''');
  }

  static Future<void> _createSyncPendingRecordsTable(Database db) async {
    // 下載時 book_fingerprint 查無對應本機書籍的待處理佇列（epic-8-sync
    // Issue 4，spec.md「跨裝置參照設計」：「該筆同步紀錄暫緩合併、留在
    // 待處理佇列」；精確理由見 plan-issue-4.md Task 1）。payload_json
    // 存放該筆遠端紀錄的原始欄位（未經格式判斷正規化，見
    // sync_table_specs.dart），待對應書籍匯入後才正規化並落地。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_pending_records (
        collection TEXT NOT NULL,
        client_id TEXT NOT NULL,
        book_fingerprint TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (collection, client_id)
      )
    ''');
  }

  static Future<void> _createLayoutPresetTable(Database db) async {
    // 版面設定預設集（epic-28-reader-settings-enhancements Issue 3），見
    // spec.md「儲存格式」——prefs_json 為過濾後 BookReaderPrefs 的 JSON
    // 序列化結果，非逐欄位對應，理由見 LayoutPresetRepository 類別文件。
    await db.execute('''
      CREATE TABLE layout_preset (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        prefs_json TEXT NOT NULL
      )
    ''');
  }

  /// 每本書的全文檢索索引進度狀態，含背景排程的續跑游標
  /// （epic-10-search Issue 0，見 spec.md §1）。
  static Future<void> _createContentIndexStatusTable(Database db) async {
    await db.execute('''
      CREATE TABLE content_index_status (
        book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
        status TEXT NOT NULL DEFAULT 'pending',
        last_chapter_index INTEGER,
        updated_at INTEGER NOT NULL,
        error_message TEXT
      )
    ''');
  }

  /// 內容索引明細——一列 = 一個可跳轉的精確定位片段（epic-10-search
  /// Issue 0，見 spec.md §1）。[locator] 是 Foliate 的 CFI 字串或 PDF 的
  /// JSON `{"page":int,"rect":PercentRect}`；[token_text] 是 [raw_text]
  /// 逐字層級 token 化後的可搜尋文字（見 `cjk_tokenizer.dart`）。
  static Future<void> _createBookContentIndexTable(Database db) async {
    await db.execute('''
      CREATE TABLE book_content_index (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        chapter_index INTEGER NOT NULL,
        locator TEXT NOT NULL,
        raw_text TEXT NOT NULL,
        token_text TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_book_content_index_book_id ON book_content_index(book_id)');
  }

  /// FTS5 external-content 虛擬表＋同步 trigger（epic-10-search Issue 0，
  /// 見 spec.md §1）。只索引 `token_text`，實際文字以 [book_content_index]
  /// 為準。**務必**搭配 `onConfigure` 的 `PRAGMA recursive_triggers = ON`
  /// ——書籍刪除時 [book_content_index] 的列會被外鍵 `ON DELETE CASCADE`
  /// 級聯刪除，但依 SQLite 官方規範，級聯刪除預設「不會」觸發子表的
  /// `AFTER DELETE` trigger（需 `recursive_triggers = ON` 才會），少了這個
  /// PRAGMA，下面這三個 trigger 對級聯刪除完全不會執行，
  /// `book_content_fts` 將殘留指向不存在 rowid 的孤兒索引
  /// （review-spec.md C-1，本檔案 Task 1 Step 8-11 有專門的回歸測試鎖住
  /// 這個行為）。不加 `tokenize=` 參數，使用 FTS5 預設的 `unicode61`
  /// （ADR 0027：排除 `trigram`，Android 11 系統 SQLite 3.28.0 不支援）。
  static Future<void> _createBookContentFtsTable(Database db) async {
    await db.execute('''
      CREATE VIRTUAL TABLE book_content_fts USING fts5(
        token_text,
        content='book_content_index',
        content_rowid='rowid'
      )
    ''');
    await db.execute('''
      CREATE TRIGGER book_content_index_ai AFTER INSERT ON book_content_index BEGIN
        INSERT INTO book_content_fts(rowid, token_text) VALUES (new.rowid, new.token_text);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER book_content_index_ad AFTER DELETE ON book_content_index BEGIN
        INSERT INTO book_content_fts(book_content_fts, rowid, token_text) VALUES('delete', old.rowid, old.token_text);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER book_content_index_au AFTER UPDATE ON book_content_index BEGIN
        INSERT INTO book_content_fts(book_content_fts, rowid, token_text) VALUES('delete', old.rowid, old.token_text);
        INSERT INTO book_content_fts(rowid, token_text) VALUES (new.rowid, new.token_text);
      END
    ''');
  }

  static Future<void> _createRemoteServersTable(Database db) async {
    // Calibre／OPDS 遠端書架站點（epic-30-calibre-remote-library
    // Issue 0），見 spec.md「站點管理：RemoteServerRepository」。密碼
    // 獨立存 flutter_secure_storage（Issue 1），此表只存非敏感設定。
    await db.execute('''
      CREATE TABLE remote_servers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        type TEXT NOT NULL,
        username TEXT,
        allow_insecure INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        last_accessed_at INTEGER
      )
    ''');
  }

  /// 將 bookmarks / highlights / notes 三張表的主鍵從 INTEGER AUTOINCREMENT
  /// 遷移為 UUID TEXT PRIMARY KEY（見 spec.md「本機 Schema 變更」／
  /// 「Migration」）。
  ///
  /// **外鍵約束已由上方 onConfigure 暫時關閉**（PRAGMA foreign_keys = OFF），
  /// 因為遷移過程中的中繼狀態（例如 notes.highlight_id 在 highlights 表
  /// 被 rename 重建期間指向不存在的目標）會被 SQLite 擋下。遷移完成後
  /// 由 onOpen 恢復開啟。
  ///
  /// SQLite 的 ALTER TABLE 只支援 RENAME TABLE / ADD COLUMN / RENAME COLUMN，
  /// 不支援修改欄位型別或移除欄位，因此只能用「建新表 → 搬資料 →
  /// 刪舊表 → RENAME 新表」的方式重寫。
  static Future<void> _migrateAnnotationTablesToUuid(Database db) async {
    // 檢查 bookmarks 表是否仍使用舊版 INTEGER 主鍵——若已遷移過（例如
    // 裝置已跑過 16→17 升級）則跳過整個流程，避免重複遷移造成資料遺失。
    final bookmarksInfo = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='bookmarks'");
    if (bookmarksInfo.isEmpty) return;
    final createSql = bookmarksInfo.first['sql'] as String;
    if (!createSql.contains('INTEGER PRIMARY KEY AUTOINCREMENT')) return;

    final uuid = const Uuid();

    // --- Bookmarks ---
    // 舊表資料備份（用於後續搬遷）
    final bookmarks = await db.query('bookmarks');

    await db.execute('DROP TABLE IF EXISTS bookmarks');
    await _createBookmarksTable(db);
    final migrationTimestamp = DateTime.now().millisecondsSinceEpoch;
    for (final row in bookmarks) {
      final newId = uuid.v4();
      await db.insert('bookmarks', {
        'id': newId,
        'book_id': row['book_id'],
        'name': row['name'],
        'epub_locator_json': row['epub_locator_json'],
        'progression': row['progression'],
        'pdf_page_index': row['pdf_page_index'],
        'updated_at': migrationTimestamp,
        'deleted_at': null,
      });
    }

    // --- Highlights ---
    final highlights = await db.query('highlights');

    await db.execute('DROP TABLE IF EXISTS highlights');
    await _createHighlightsTable(db);
    // 舊 highlights 的 INTEGER id → 新 UUID id 對照表，供 notes.highlight_id 遷移
    final highlightIdMap = <int, String>{};
    for (final row in highlights) {
      final newId = uuid.v4();
      highlightIdMap[row['id'] as int] = newId;
      await db.insert('highlights', {
        'id': newId,
        'book_id': row['book_id'],
        'style': row['style'],
        'epub_locator_json': row['epub_locator_json'],
        'progression': row['progression'],
        'pdf_page_index': row['pdf_page_index'],
        'pdf_rect_json': row['pdf_rect_json'],
        'updated_at': migrationTimestamp,
        'deleted_at': null,
      });
    }

    // --- Notes ---
    final notes = await db.query('notes');

    await db.execute('DROP TABLE IF EXISTS notes');
    await _createNotesTable(db);
    for (final row in notes) {
      final newId = uuid.v4();
      // 將舊的 INTEGER highlight_id 轉換為新的 UUID highlight_id
      final oldHighlightId = row['highlight_id'] as int?;
      final newHighlightId =
          oldHighlightId != null ? highlightIdMap[oldHighlightId] : null;
      await db.insert('notes', {
        'id': newId,
        'book_id': row['book_id'],
        'text': row['text'],
        'epub_locator_json': row['epub_locator_json'],
        'progression': row['progression'],
        'highlight_id': newHighlightId,
        'pdf_page_index': row['pdf_page_index'],
        'pdf_rect_json': row['pdf_rect_json'],
        'updated_at': migrationTimestamp,
        'deleted_at': null,
      });
    }
  }

  /// 供 [BookReaderPrefsRepository] 等後續 repository 共用同一個資料庫連線
  /// （`book_reader_prefs` 的外鍵約束要求與 `books` 表在同一個資料庫檔案內）。
  Database get database => _db;

  Future<void> close() => _db.close();

  @override
  Future<List<Book>> listReflowableEpubBooks({String? excludeBookId}) async {
    final where = StringBuffer(
        "filePath LIKE '%.epub' AND (is_fixed_layout IS NULL OR is_fixed_layout != 1)");
    final whereArgs = <Object?>[];
    if (excludeBookId != null) {
      where.write(' AND id != ?');
      whereArgs.add(excludeBookId);
    }
    final rows = await _db.query(
      'books',
      where: where.toString(),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'title ASC',
    );
    return rows.map(Book.fromMap).toList();
  }

  @override
  Future<Book?> findByRemoteBookId(String serverId, String remoteBookId) async {
    final rows = await _db.query(
      'books',
      where: 'remote_server_id = ? AND remote_book_id = ?',
      whereArgs: [serverId, remoteBookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }

  @override
  Future<Book?> findByContentFingerprint(String fingerprint) async {
    final rows = await _db.query(
      'books',
      where: 'content_fingerprint = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }

  @override
  Future<Book?> findByCloudFileId(BookSource provider, String cloudFileId) async {
    final rows = await _db.query(
      'books',
      where: 'source = ? AND cloud_file_id = ?',
      whereArgs: [provider.name, cloudFileId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }

  @override
  Future<List<Book>> listUndownloadedBooksForRemoteServer(String serverId) async {
    final rows = await _db.query(
      'books',
      where: 'remote_server_id = ? AND is_downloaded = 0',
      whereArgs: [serverId],
    );
    return rows.map(Book.fromMap).toList();
  }

  @override
  Future<bool> detectAndCacheEpubLayout(String bookId, String filePath) async {
    final response = await kBookMetadataChannel.invokeMapMethod<String, Object?>(
      'detectEpubLayout',
      {'uri': filePath},
    );
    final isFixedLayout = response?['isFixedLayout'] as bool? ?? false;
    await _db.update(
      'books',
      {'is_fixed_layout': isFixedLayout ? 1 : 0},
      where: 'id = ?',
      whereArgs: [bookId],
    );
    return isFixedLayout;
  }

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
