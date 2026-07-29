import 'package:flutter/services.dart';
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

  static const _metadataChannel = MethodChannel('elinkbook/book_metadata');

  SqliteLibraryRepository._(this._db);

  static Future<SqliteLibraryRepository> open(String path) async {
    final db = await openDatabase(
      path,
      version: 15,
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
            epubLocator TEXT,
            pdfPageIndex INTEGER,
            totalCharacterCount INTEGER,
            is_fixed_layout INTEGER,
            groupName TEXT NOT NULL DEFAULT '${BookGroup.uncategorized}',
            createTime INTEGER NOT NULL,
            lastReadTime INTEGER NOT NULL
          )
        ''');
        await _createBookReaderPrefsTable(db);
        await _createBookmarksTable(db);
        await _createHighlightsTable(db);
        await _createNotesTable(db);
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
        fullscreen INTEGER
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
    // PRIMARY KEY，改用獨立的自動遞增 id。
    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        pdf_page_index INTEGER
      )
    ''');
  }

  static Future<void> _createHighlightsTable(Database db) async {
    // 劃線（epic-6-annotations Issue 2/3，spec.md「劃線與備註模組」），與
    // books 表以 book_id 外鍵關聯（比照 bookmarks 既有關聯模式）。
    // pdf_page_index／pdf_rect_json（Issue 3 新增）與
    // epub_locator_json／progression（Issue 2）互斥，依書籍格式擇一填入。
    await db.execute('''
      CREATE TABLE highlights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        style TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        pdf_page_index INTEGER,
        pdf_rect_json TEXT
      )
    ''');
  }

  static Future<void> _createNotesTable(Database db) async {
    // 備註（epic-6-annotations Issue 2/3，spec.md「資料模型關聯」）：
    // highlight_id 為可空外鍵，ON DELETE SET NULL——批次刪除劃線後，
    // 依附的備註自動退化為純備註（highlight_id 變 null），不需應用層
    // 判斷邏輯。建表順序刻意晚於 _createHighlightsTable（程式碼可讀性
    // 慣例，非技術硬性要求，見 spec.md 審查修正 1.1）。
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        highlight_id INTEGER REFERENCES highlights(id) ON DELETE SET NULL,
        pdf_page_index INTEGER,
        pdf_rect_json TEXT
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

  /// 供 [BookReaderPrefsRepository] 等後續 repository 共用同一個資料庫連線
  /// （`book_reader_prefs` 的外鍵約束要求與 `books` 表在同一個資料庫檔案內）。
  Database get database => _db;

  Future<void> close() => _db.close();

  @override
  Future<bool> detectAndCacheEpubLayout(String bookId, String filePath) async {
    final response = await _metadataChannel.invokeMapMethod<String, Object?>(
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
