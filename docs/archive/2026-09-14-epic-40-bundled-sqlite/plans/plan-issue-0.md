# Epic 40 Issue 0：改用自帶編譯的 sqlite3（含 FTS5）取代系統內建版本 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal：** 讓 Android 正式建置與真機整合測試改用 `sqflite_common_ffi` 直連 `sqlite3`（Native Assets 建置掛鉤自帶、保證含 FTS5 的原生函式庫），取代目前依賴 Android 系統內建 SQLite（部分裝置／客製化 ROM 完全沒有編譯 FTS5 模組，導致全文檢索永久不可用）的做法；並新增 DB version 24→25 遷移，讓原本因缺 FTS5 而跳過建表的既有裝置，換引擎後下次開啟時能成功補建 `book_content_fts`。

**Architecture：** `SqliteLibraryRepository.open()`（`app/lib/library/sqlite_library_repository.dart`）是全專案唯一呼叫 `openDatabase()` 的地方，回傳的 `Database` 由 `main.dart` 逐層傳給其餘 12+ 個 repository；這些 repository 只認 `sqflite_common` 的 `Database`/`Batch`/`Transaction` 型別，不各自開連線。因此換底層引擎只需要在 App 啟動最早期（`main()`，第一次 `openDatabase()` 之前）把全域 `databaseFactory` 換成 `databaseFactoryFfi`，不需要更動任何一個 repository。既有裝置遷移採 DB version 24→25：新增的 `onUpgrade` 分支呼叫既有的 `_createBookContentFtsTableIfSupported()`（`epic-10-search` Issue 6 既有優雅降級 helper，不修改），但**必須先查 `sqlite_master` 確認 `book_content_fts` 表尚不存在才呼叫**——因為現行 `CREATE VIRTUAL TABLE` 沒有 `IF NOT EXISTS` 防護，對系統版本本來就有 FTS5、已成功建表的裝置（多數裝置）若無條件重跑會拋出「table already exists」。

**Tech Stack：** Flutter/Dart、`sqflite_common_ffi`（正式 Android 建置路徑，本工單起與桌面測試環境共用）、`sqlite3`（`sqflite_common_ffi` 遞移解析，3.5.0，Dart Native Assets 建置掛鉤自動打包含 FTS5 的原生函式庫）。

**Spec：** [`docs/epics/epic-40-bundled-sqlite/spec.md`](../spec.md)（本 Epic 唯一事實來源，全文適用本 Issue）；[ADR 0028](../../adr/0028-bundled-sqlite3-for-fts5.md)（架構決策）；工單條目 [`issues.md`](../issues.md) Issue 0。

> **本計畫檔案存放路徑覆寫說明**：比照 `epic-10-search` `plan-issue-0.md`／`plan-issue-6.md` 先例，`superpowers:writing-plans` 技能預設把計畫存到 `docs/superpowers/plans/`，本專案 SDD 工作流程（`docs/agents/issue-tracker.md`）明訂存放於 `docs/epics/<epic-name>/plans/plan-issue-<N>.md`，本計畫依專案慣例存放於此。

## Global Constraints

- **只處理 Android 正式建置路徑**：桌面測試環境（`sqflite_common_ffi` 本來就依賴開發機系統既有 sqlite3，一律含 FTS5）與 iOS（`epic-13-ios` 尚未啟動）皆維持現狀不動，不在本計畫範圍內新增任何平台判斷邏輯。
- **不新增 `sqlite3_flutter_libs`**：這個套件僅適用於已淘汰、標記 `0.6.0+eol` 且無任何實體檔案的 `sqlite3` 2.x 世代；現行 `sqlite3` 3.5.0 起改用 Dart 官方 Native Assets 建置掛鉤，`flutter build apk`／`flutter run` 建置時會自動處理。
- **不新增任何索引回補程式碼**：既有裝置換引擎後若 `book_content_fts` 是空的，依賴 `epic-10-search` Issue 3 既有的「重建索引」按鈕（`FullTextSearchSettingsRepository.rebuildIndex()`）由使用者手動觸發，本計畫不新增背景自動重建或提示 UI。
- **不修改 `_createBookContentFtsTableIfSupported()`（Issue 6 既有優雅降級機制）本身**：只在 `onUpgrade` 新增一個呼叫點，呼叫前先做存在性檢查；該函式的內部實作（try/catch 比對「no such module: fts5」訊息）維持不動，作為零成本縱深防禦。
- **不修改 `cjk_tokenizer.dart`／tokenizer 方案**：ADR 0028 決策 5 已重新評估並維持排除 FTS5 `trigram`，本計畫不涉及任何 tokenizer 程式碼。
- **既有裝置升級測試一律用真實暫存檔（`Directory.systemTemp.createTemp(...)`），不能用 `inMemoryDatabasePath`**：`onUpgrade` 只在重新開啟既有檔案時觸發，`inMemoryDatabasePath` 每次開啟都是全新資料庫、永遠只會走 `onCreate`（比照 `sqlite_library_repository_test.dart` 既有「既有 version 23 裝置升級到 version 24」測試寫法）。
- 涉及 `inMemoryDatabasePath` 且需要獨立於 `setUp()` 共用 `repository` 的測試，一律傳入 `singleInstance: false`（`SqliteLibraryRepository.open()` 既有 doc comment 已記錄的陷阱：對同一個 `':memory:'` 字面路徑重複呼叫預設會拿回同一條快取連線）。本計畫的新測試若能重用 `setUp()` 已建好的共用 `repository`，優先重用，不另開連線。
- 所有新增程式碼註解使用正體中文（zh-TW），比照全專案既有慣例。
- **測試執行範圍**（比照 `CLAUDE.md`「測試執行範圍」段落）：Task 1-5 的 TDD 步驟與修復驗證，一律只跑 `app/test/library/sqlite_library_repository_test.dart` 這一個異動觸及的測試檔，不需要每步都重跑全套；完整 `flutter test`（無參數）只在本計畫最後一個 Task（Task 6）執行一次。
- **真機重新驗證**（`issues.md` 驗收標準第 3 點）不寫自動化測試，也不屬於本計畫任何一個 Task 的完成條件——留在 Task 6 末尾以文件形式記錄給人類收尾執行。

---

## 檔案結構總覽

- **Modify：** `app/pubspec.yaml` — `sqflite_common_ffi` 從 `dev_dependencies` 移至 `dependencies`。
- **Modify：** `app/lib/main.dart` — `main()` 最前面新增 `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`。
- **Modify：** `app/integration_test/flutter_test_config.dart` — `testExecutable()` 內同步新增相同的 FFI 初始化。
- **Modify：** `app/lib/library/sqlite_library_repository.dart` — `openDatabase(..., version: 24, ...)` 改為 `version: 25`；`onUpgrade` 新增 `if (oldVersion < 25)` 分支（含 `sqlite_master` 存在性檢查）。
- **Modify：** `app/test/library/sqlite_library_repository_test.dart` — 新增 `epic-40-bundled-sqlite Issue 0：DB version 24→25 遷移` 測試群組（三個情境：Issue 6 場景補建表／已有表不可重複建表／全新安裝零回歸）。

無新增檔案。

---

### Task 1：`pubspec.yaml` 依賴類別調整

**Files：**
- Modify: `app/pubspec.yaml`

**Interfaces：**
- Consumes：無（純建置設定變更）。
- Produces：`sqflite_common_ffi` 成為正式 `dependencies`，供 Task 2／3 的 `import 'package:sqflite_common_ffi/sqflite_ffi.dart';` 在正式建置路徑（非僅測試）下可用。

- [ ] **Step 1：把 `sqflite_common_ffi` 從 `dev_dependencies` 移到 `dependencies`**

【審查修正 I-2】原指示與程式碼片段皆包含前後既有的 `sqflite:`／`path:` 兩行做為定位錨點，若照字面插入會產生重複鍵宣告。改為精準指示：在 `sqflite: ^2.4.2+1`（第 50 行）與 `path: ^1.9.1`（第 51 行）**之間**插入，程式碼片段只保留真正要新增的內容：

```yaml
  # epic-40-bundled-sqlite（ADR 0028）：從 dev_dependencies 移至此，
  # 同時服務正式 Android 建置（透過 databaseFactoryFfi，見 main.dart）與
  # 既有桌面測試環境。其遞移解析的 sqlite3（3.5.0）自 3.x 起改用 Dart
  # 官方 Native Assets 建置掛鉤，建置時自動下載/編譯含 FTS5 的原生函式
  # 庫，取代依賴 Android 系統內建 SQLite（部分裝置系統版本缺 FTS5
  # 模組，見 epic-10-search Issue 6）。不新增 sqlite3_flutter_libs——
  # 該套件僅適用於已淘汰的 sqlite3 2.x 世代。
  sqflite_common_ffi: ^2.4.0+3
```

插入後 `dependencies:` 區塊該段落應為：

```yaml
  sqflite: ^2.4.2+1
  # epic-40-bundled-sqlite（ADR 0028）：從 dev_dependencies 移至此，
  # 同時服務正式 Android 建置（透過 databaseFactoryFfi，見 main.dart）與
  # 既有桌面測試環境。其遞移解析的 sqlite3（3.5.0）自 3.x 起改用 Dart
  # 官方 Native Assets 建置掛鉤，建置時自動下載/編譯含 FTS5 的原生函式
  # 庫，取代依賴 Android 系統內建 SQLite（部分裝置系統版本缺 FTS5
  # 模組，見 epic-10-search Issue 6）。不新增 sqlite3_flutter_libs——
  # 該套件僅適用於已淘汰的 sqlite3 2.x 世代。
  sqflite_common_ffi: ^2.4.0+3
  path: ^1.9.1
```

在 `dev_dependencies:` 區塊中刪除原本的這一行（第 128 行）：

```yaml
  sqflite_common_ffi: ^2.4.0+3
```

（`dev_dependencies` 區塊移除此行後，`flutter_lints: ^6.0.0` 與 `path_provider_platform_interface: ^2.1.0` 直接相鄰。）

- [ ] **Step 2：`flutter pub get` 驗證解析成功**

於 `app/` 目錄執行：

```bash
flutter pub get
```

Expected：指令成功結束（exit code 0），無版本衝突錯誤。`pubspec.lock` 中 `sqflite_common_ffi` 一節的 `dependency:` 欄位應變為 `"direct main"`（原本是 `"direct dev"`）。

- [ ] **Step 3：Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock
git commit -m "build(deps): sqflite_common_ffi 提升為正式依賴（epic-40-bundled-sqlite）"
```

---

### Task 2：`main.dart` 初始化 FFI factory

**Files：**
- Modify: `app/lib/main.dart`

**Interfaces：**
- Consumes：Task 1 的 `sqflite_common_ffi` 正式依賴。
- Produces：App 正式啟動路徑下，全域 `databaseFactory` 在第一次 `openDatabase()`（`SqliteLibraryRepository.open()`，`main.dart:84`）之前已切換為 `databaseFactoryFfi`，供 Task 4 的資料庫遷移程式碼透過這個 factory 開啟。

- [ ] **Step 1：新增 import 與初始化呼叫**

在 `app/lib/main.dart` 檔案最上方 import 區塊（`import 'dart:io';` 之後、`import 'package:connectivity_plus/connectivity_plus.dart';` 之前，依現有 import 排序習慣即可，不需嚴格字母排序——比照既有檔案排序方式）新增：

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
```

在 `Future<void> main() async {` 函式本體最前面（`WidgetsFlutterBinding.ensureInitialized();` 之後、`await pdfrxFlutterInitialize();` 之前）新增：

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // epic-40-bundled-sqlite（ADR 0028）：改用 sqlite3 Native Assets 建置
  // 掛鉤自帶編譯、保證含 FTS5 的 sqlite3，取代依賴 Android 系統內建
  // SQLite（部分裝置系統版本缺 FTS5 模組，見 epic-10-search Issue 6）。
  // 必須在任何 openDatabase() 呼叫（下方 SqliteLibraryRepository.open()）
  // 之前完成。
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // pdfrx（PDFium FFI）初始化，epic-24-pdf-engine-rebuild：Flutter App
  // 執行期一律呼叫 pdfrxFlutterInitialize()（而非 pdfrxInitialize()，後者
  // 用於純 Dart、無 Flutter 環境），須在任何 PDF 開書呼叫之前完成。
  await pdfrxFlutterInitialize();
```

（`pdfrxFlutterInitialize()` 那段既有註解與呼叫本身不變，只是在它之前插入新的兩行初始化。）

- [ ] **Step 2：`flutter analyze` 驗證**

```bash
flutter analyze
```

Expected：`No issues found!`（`main.dart` 沒有未使用的 import 或型別錯誤）。

- [ ] **Step 3：Commit**

```bash
git add app/lib/main.dart
git commit -m "feat(db): main.dart 初始化 sqflite FFI factory（epic-40-bundled-sqlite）"
```

---

### Task 3：`flutter_test_config.dart` 同步初始化 FFI factory

**Files：**
- Modify: `app/integration_test/flutter_test_config.dart`

**Interfaces：**
- Consumes：Task 1 的 `sqflite_common_ffi` 正式依賴。
- Produces：`app/integration_test/` 下所有測試檔（包含目前未各自呼叫 `sqfliteFfiInit()` 的既有測試檔）在 Android 真機上執行時，一律使用自帶 SQLite 引擎，與 `main.dart` 的正式執行路徑一致。

- [ ] **Step 1：新增 import 與初始化呼叫**

把 `app/integration_test/flutter_test_config.dart` 整份檔案改為：

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Issue 9 根因修復：`IntegrationTestWidgetsFlutterBinding`
/// （繼承自 `LiveTestWidgetsFlutterBinding`）預設 `framePolicy` 是
/// `fadePointers`——這個模式下，`setState()` 之後不會自動畫下一格，除非
/// 測試明確呼叫 `tester.pump()` 或有指標活動觸發（見 Flutter SDK
/// `flutter_test/lib/src/binding.dart` 的 `handleBeginFrame`）。
///
/// `FoliateReaderView`（Issue 8 起）在 `initState()` 內非同步完成
/// `_cacheBook()` 後才 `setState()` 掛載 `InAppWebView`；既有整合測試多半
/// 是 `pumpWidget()` 後直接 `await` 一個 completer，中間沒有任何
/// `pump()`，導致該次 `setState()` 永遠等不到畫面重繪、`InAppWebView`
/// 從未掛載，最終測試逾時（`docs/epics/epic-20-fxl-foliate-migration/
/// issues.md` Issue 9 記錄的其中一種失敗模式）。改為 `fullyLive`
/// 讓所有非同步等待期間都能正常畫格，符合實機執行 App 時的真實行為。
///
/// 這是 Flutter 標準的全域整合測試設定機制（此檔案名稱與位置為框架
/// 慣例，`flutter test integration_test/` 執行任何測試前都會先跑這裡的
/// `testExecutable`），對 `integration_test/` 目錄下所有測試檔案生效，
/// 不需要在每個測試檔案各自重複設定。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // epic-40-bundled-sqlite（ADR 0028）：真機整合測試在 Android 上執行時
  // 不經過 lib/main.dart 的 main()，需在這裡同步初始化 FFI factory，
  // 否則會回退到系統平台 channel（可能缺 FTS5），與正式 App 執行路徑
  // 不一致。
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  await testMain();
}
```

- [ ] **Step 2：`flutter analyze` 驗證**

```bash
flutter analyze
```

Expected：`No issues found!`。

- [ ] **Step 3：Commit**

```bash
git add app/integration_test/flutter_test_config.dart
git commit -m "test(integration): flutter_test_config 初始化 sqflite FFI factory（epic-40-bundled-sqlite）"
```

---

### Task 4：DB version 24→25 遷移＋`sqlite_master` 存在性防護（單一 Task，兩個情境同時驅動）

**Files：**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces：**
- Consumes：既有 `SqliteLibraryRepository.open(String path, {bool singleInstance = true})`（僅內部實作改動，對外公開簽章不變）；既有頂層可覆寫函式變數 `createBookContentFtsTable`（`epic-10-search` Issue 6 既有機制，本 Task 不覆寫它，因為要測的是「這次真的能成功建表」與「已有表不可重複建表」，不是「FTS5 缺失」）；既有私有 helper `_createBookContentFtsTableIfSupported(Database db)`（不修改其內部實作，只新增一個呼叫點）。
- Produces：`SqliteLibraryRepository.open()` 的 `openDatabase()` 呼叫改為 `version: 25`；`onUpgrade` 新增 `if (oldVersion < 25)` 分支，**從一開始就包含 `sqlite_master` 存在性檢查**——這是本工單唯一容易出錯的細節（`issues.md` 明文強調），必須逐字依 `spec.md` §3 實作。

> **【審查修正 I-1】**：原計畫把「先寫最小實作」與「補存在性檢查」拆成 Task 4／Task 5 兩個階段，但 `onUpgrade` 的多個 `if (oldVersion < N)` 分支是**累進執行**的——既有測試「既有 version 23 裝置升級到 version 24」（`sqlite_library_repository_test.dart:3830`）以 `oldVersion=23` 觸發時，`if (oldVersion < 24)` 與 `if (oldVersion < 25)` 會在同一次 `onUpgrade` 呼叫中依序執行：前者成功建立 `book_content_fts` 後，若後者沒有存在性檢查就無條件再呼叫一次 `_createBookContentFtsTableIfSupported(db)`，會拋出「table already exists」，導致這個既有測試在「先寫最小實作」那個中間狀態必然崩潰，且會產出一個測試處於紅燈狀態的破壞性 commit。因此改為單一 Task：兩個情境（表不存在／表已存在）的測試一次寫齊、直接實作完整帶存在性檢查的版本，確保任何一次 commit 都是全綠的。

- [ ] **Step 1：寫兩個會失敗的遷移測試——情境 1（`book_content_fts` 不存在，Issue 6 場景）與情境 2（`book_content_fts` 已存在）**

在 `app/test/library/sqlite_library_repository_test.dart`，找到既有的 `group('epic-10-search Issue 6：FTS5 模組可用性偵測與優雅降級', () { ... });` 區塊**結束的大括號**（`});`），這是全檔案目前最後一個 `group`，其後緊接著 `main()` 函式本身的收尾大括號 `}`（【審查修正 M-3】單獨一個右大括號，無括號與分號，Dart 檔案頂層 `void main() { ... }` 的收尾寫法——原文誤寫為 `});`）。在這個 `group` 收尾與 `main()` 收尾之間插入新的測試群組：

```dart
  group('epic-40-bundled-sqlite Issue 0：DB version 24→25 遷移（改用自帶 SQLite）', () {
    test(
        '既有 version 24 裝置，book_content_fts 不存在（Issue 6 場景，系統版本當初缺 FTS5）'
        '升級到 version 25：不拋例外，isFullTextSearchAvailable 變為 true，'
        'book_content_fts 表與三個同步 trigger（AI/AD/AU）皆已建立，'
        '對 book_content_index 執行 INSERT/UPDATE/DELETE 皆正確同步', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('elinkbook_migration_v24_to_v25_fts_missing_test');
      addTearDown(() => tempDir.delete(recursive: true));
      final dbPath = p.join(tempDir.path, 'test.db');

      final oldDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 24,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
            await db.execute('PRAGMA recursive_triggers = ON');
          },
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
            await db.insert('groups', {'name': '未分類'});
            await db.execute('CREATE TABLE books (id TEXT PRIMARY KEY)');
            await db.insert('books', {'id': 'book1'});
            await db.execute('''
              CREATE TABLE content_index_status (
                book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
                status TEXT NOT NULL DEFAULT 'pending',
                last_chapter_index INTEGER,
                updated_at INTEGER NOT NULL,
                error_message TEXT
              )
            ''');
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
            // 刻意不建立 book_content_fts 與其三個同步 trigger——模擬
            // Issue 6 場景：系統版本當初缺 FTS5，
            // _createBookContentFtsTableIfSupported() 靜默跳過建表。
          },
        ),
      );
      await oldDb.close();

      final upgraded = await SqliteLibraryRepository.open(dbPath);
      addTearDown(() => upgraded.close());

      expect(upgraded.isFullTextSearchAvailable, isTrue);

      final ftsTable = await upgraded.database.query(
        'sqlite_master',
        columns: ['name'],
        where: "type = 'table' AND name = 'book_content_fts'",
      );
      expect(ftsTable, hasLength(1));

      final triggerNames = await upgraded.database.query(
        'sqlite_master',
        columns: ['name'],
        where: "type = 'trigger' AND name IN (?, ?, ?)",
        whereArgs: [
          'book_content_index_ai',
          'book_content_index_ad',
          'book_content_index_au',
        ],
      );
      expect(
        triggerNames.map((row) => row['name']).toSet(),
        {
          'book_content_index_ai',
          'book_content_index_ad',
          'book_content_index_au',
        },
      );

      // AFTER INSERT
      await upgraded.database.insert('book_content_index', {
        'id': 'seg-1',
        'book_id': 'book1',
        'chapter_index': 0,
        'locator': 'epubcfi(/6/2!/4/2/1:0)',
        'raw_text': '這是一句測試內容',
        'token_text': '這 是 一 句 測 試 內 容',
        'created_at': 1000,
      });
      final afterInsert = await upgraded.database.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '測 試'");
      expect(afterInsert, hasLength(1),
          reason: 'AFTER INSERT trigger 應同步寫入 book_content_fts');

      // AFTER UPDATE：舊 token 應被移除，新 token 應可查到
      await upgraded.database.update(
        'book_content_index',
        {'token_text': '改 過 的 內 容'},
        where: 'id = ?',
        whereArgs: ['seg-1'],
      );
      final afterUpdateOldToken = await upgraded.database.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '測 試'");
      expect(afterUpdateOldToken, isEmpty,
          reason: 'AFTER UPDATE trigger 應先移除舊 token_text 的索引');
      final afterUpdateNewToken = await upgraded.database.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '改 過'");
      expect(afterUpdateNewToken, hasLength(1),
          reason: 'AFTER UPDATE trigger 應寫入新 token_text 的索引');

      // AFTER DELETE
      await upgraded.database.delete(
        'book_content_index',
        where: 'id = ?',
        whereArgs: ['seg-1'],
      );
      final afterDelete = await upgraded.database.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '改 過'");
      expect(afterDelete, isEmpty,
          reason: 'AFTER DELETE trigger 應同步清空 book_content_fts');

      // 【審查採納 M-1】isFullTextSearchAvailable 是每次 open() 當下查詢
      // sqlite_master 得出的結果，不是遷移過程暫存的旗標；關閉並重新開啟
      // （version 已經是 25，不會再觸發 onUpgrade）驗證這個判斷邏輯本身
      // 對「已遷移完成」的資料庫依然正確。
      await upgraded.close();
      final reopened = await SqliteLibraryRepository.open(dbPath);
      addTearDown(() => reopened.close());
      expect(reopened.isFullTextSearchAvailable, isTrue,
          reason: '遷移至 v25 後常規重開（不觸發 onUpgrade），'
              'isFullTextSearchAvailable 仍須為 true');
    });

    test(
        '既有 version 24 裝置，book_content_fts 已存在（系統版本本來就有 FTS5，'
        '已成功建表，且已有歷史索引資料）升級到 version 25：不拋例外，'
        'isFullTextSearchAvailable 仍為 true，且既有索引資料未被清空',
        () async {
      final tempDir = await Directory.systemTemp
          .createTemp('elinkbook_migration_v24_to_v25_fts_exists_test');
      addTearDown(() => tempDir.delete(recursive: true));
      final dbPath = p.join(tempDir.path, 'test.db');

      final oldDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 24,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
            await db.execute('PRAGMA recursive_triggers = ON');
          },
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
            await db.insert('groups', {'name': '未分類'});
            await db.execute('CREATE TABLE books (id TEXT PRIMARY KEY)');
            await db.execute('''
              CREATE TABLE content_index_status (
                book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
                status TEXT NOT NULL DEFAULT 'pending',
                last_chapter_index INTEGER,
                updated_at INTEGER NOT NULL,
                error_message TEXT
              )
            ''');
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
            // 【審查採納 M-2】升級前先植入一筆歷史索引資料，確保之後的
            // 存在性檢查邏輯只是「跳過重複建表」，不會意外連帶清空既有
            // 索引（例如未來有人誤寫成 DROP TABLE IF EXISTS 重建）。
            await db.insert('books', {'id': 'book1'});
            await db.insert('book_content_index', {
              'id': 'legacy-seg-1',
              'book_id': 'book1',
              'chapter_index': 0,
              'locator': 'epubcfi(/6/2!/4/2/1:0)',
              'raw_text': '既有裝置升級前就存在的歷史內容',
              'token_text': '既 有 裝 置 升 級 前 就 存 在 的 歷 史 內 容',
              'created_at': 1000,
            });
          },
        ),
      );
      await oldDb.close();

      final upgraded = await SqliteLibraryRepository.open(dbPath);
      addTearDown(() => upgraded.close());

      expect(upgraded.isFullTextSearchAvailable, isTrue);

      // 【審查採納 M-2】升級後歷史索引資料應完整保留、可被 MATCH 查到。
      final legacyMatch = await upgraded.database.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '歷 史'");
      expect(legacyMatch, hasLength(1),
          reason: '升級前既有的歷史全文檢索索引資料，升級後必須完整保留，'
              '不可被存在性檢查邏輯意外清空');

      // 【審查採納 M-1】關閉並重新開啟（不觸發 onUpgrade），驗證
      // isFullTextSearchAvailable 的判斷邏輯對「本來就有表」的裝置同樣
      // 正確。
      await upgraded.close();
      final reopened = await SqliteLibraryRepository.open(dbPath);
      addTearDown(() => reopened.close());
      expect(reopened.isFullTextSearchAvailable, isTrue,
          reason: '遷移至 v25 後常規重開（不觸發 onUpgrade），'
              'isFullTextSearchAvailable 仍須為 true');
    });
  });
```

- [ ] **Step 2：執行測試，確認兩個新測試皆失敗**

```bash
flutter test test/library/sqlite_library_repository_test.dart --plain-name "既有 version 24 裝置"
```

Expected：兩個測試皆 FAIL——`SqliteLibraryRepository.open()` 目前仍是 `version: 24`，對這兩個已經是 `oldVersion == newVersion == 24` 的資料庫，`openDatabase()` 根本不會呼叫 `onUpgrade`：
- 情境 1（`book_content_fts` 不存在）：`book_content_fts` 永遠不會被補建，`expect(upgraded.isFullTextSearchAvailable, isTrue)` 斷言失敗（實際為 `false`）。
- 情境 2（`book_content_fts` 已存在）：`isFullTextSearchAvailable` 本身可能已經是 `true`（表本來就存在，`open()` 的存在性查詢不受影響），但後段的冷重開（`reopened`）與歷史資料保留（`legacyMatch`）斷言此時尚無對應程式碼保護；若實測發現這個情境在完全未改動程式碼時就已經整段通過，屬於正常現象（因為它本來就沒有牽涉遷移分支），不影響下一步驟繼續實作。

- [ ] **Step 3：實作完整版本——version 24→25，`onUpgrade` 新增分支＋`sqlite_master` 存在性檢查（一次到位，不分階段）**

在 `app/lib/library/sqlite_library_repository.dart`，把第 55 行：

```dart
      version: 24,
```

改為：

```dart
      version: 25,
```

在 `onUpgrade` 內既有的 `if (oldVersion < 24) { ... }` 分支（第 391-400 行）之後、`onUpgrade` 收尾 `}` 之前，新增：

```dart
        if (oldVersion < 25) {
          // epic-40-bundled-sqlite：資料庫引擎換成自帶編譯的 sqlite3
          // （見 ADR 0028）後，原本因系統 SQLite 缺 FTS5 模組而被
          // _createBookContentFtsTableIfSupported() 跳過建表的裝置，這次
          // 應該能成功建表。但 CREATE VIRTUAL TABLE 沒有 IF NOT EXISTS
          // 防護，對系統版本本來就有 FTS5、已成功建表的裝置（多數裝置，
          // oldVersion 已經 >= 24 且當初建表成功）若無條件重跑會拋出
          // 「table already exists」，因此必須先查 sqlite_master 確認表
          // 尚不存在才嘗試建立。
          final existing = await db.query(
            'sqlite_master',
            columns: ['name'],
            where: "type = 'table' AND name = 'book_content_fts'",
            limit: 1,
          );
          if (existing.isEmpty) {
            await _createBookContentFtsTableIfSupported(db);
          }
        }
```

同時把 `open()` 方法內、`openDatabase()` 呼叫結束後的既有註解（第 414-420 行）中的版本號更新，避免文件與實際行為不一致：

```dart
    // 【epic-10-search Issue 6】onCreate／onUpgrade 兩處都可能因為 FTS5
    // 模組不存在而略過建立 book_content_fts（見
    // _createBookContentFtsTableIfSupported 說明）；且一般開啟既有裝置
    // （沒有觸發任何遷移，version 已經是 25）時，onCreate／onUpgrade
    // 兩者皆不會被呼叫。查詢 sqlite_master 是唯一能對「這一次開啟」
    // 正確反映目前實際狀態的作法，不論是全新安裝、既有裝置升級、還是
    // 單純重新開啟都適用同一條判斷邏輯。
```

（只有「version 已經是 24」→「version 已經是 25」這一處文字改動，其餘註解文字不變。）

- [ ] **Step 4：執行測試，確認兩個新測試皆通過**

```bash
flutter test test/library/sqlite_library_repository_test.dart --plain-name "既有 version 24 裝置"
```

Expected：兩個測試皆 PASS。

- [ ] **Step 5：跑整個測試檔，確認既有測試（含 `既有 version 23 裝置升級到 version 24`）沒有被破壞**

```bash
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：全數 PASS。**特別關注** `既有 version 23 裝置升級到 version 24` 這個既有測試（`sqlite_library_repository_test.dart:3830`）——`oldVersion=23` 會在同一次 `onUpgrade` 呼叫中依序觸發 `if (oldVersion < 24)` 與 `if (oldVersion < 25)` 兩個分支，本 Task 的存在性檢查必須讓後者在前者剛成功建表之後正確判斷「表已存在」而跳過，不重複建表、不拋例外。

- [ ] **Step 6：Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(db): DB version 24→25，含 sqlite_master 存在性防護，補建/保留 FTS5 表（epic-40-bundled-sqlite）"
```

---

### Task 5：全新安裝零回歸鎖定測試

**Files：**
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces：**
- Consumes：`setUp()` 既有共用的 `repository`（`await SqliteLibraryRepository.open(inMemoryDatabasePath)`，每個 test 各自全新建立，走 `onCreate` 直接建到最新版本）。
- Produces：無新程式碼——本 Task 純粹補一個顯式測試鎖定「全新安裝走 `onCreate` 直接建到 version 25」這條路徑的行為，供未來若有人不慎改動 `onCreate` 時能立即發現回歸。

- [ ] **Step 1：新增測試**

在 Task 4 新增的第二個 test 之後（仍在同一個 `group('epic-40-bundled-sqlite Issue 0：DB version 24→25 遷移（改用自帶 SQLite）', () { ... });` 區塊內），追加：

```dart
    test('全新安裝（onCreate 直接建到 version 25）：isFullTextSearchAvailable 為 true，'
        '行為與現行版本一致（零回歸）', () async {
      expect(repository.isFullTextSearchAvailable, isTrue);
      expect(await repository.database.getVersion(), 25);
    });
```

（重用 `setUp()` 已經建好的共用 `repository`，不另開連線——這正是「全新安裝」情境本身，每個 test 的 `repository` 都是透過 `onCreate` 全新建立。）

- [ ] **Step 2：執行測試，確認通過**

```bash
flutter test test/library/sqlite_library_repository_test.dart --plain-name "全新安裝（onCreate 直接建到 version 25）"
```

Expected：PASS（`onCreate` 路徑不受本計畫改動影響，`_createBookContentFtsTableIfSupported(db)` 呼叫點與 Task 4 之前完全相同，這條路徑本來就是綠的——本步驟的目的是把這個事實鎖進測試，不是驅動新程式碼）。

- [ ] **Step 3：Commit**

```bash
git add app/test/library/sqlite_library_repository_test.dart
git commit -m "test(db): 鎖定全新安裝直接建到 version 25 的零回歸行為（epic-40-bundled-sqlite）"
```

---

### Task 6：完整回歸驗證＋人工真機收尾（本計畫最後一個 Task）

**Files：**
- 無新增修改（純驗證）。

**Interfaces：**
- Consumes：Task 1-5 的全部變更。
- Produces：`issues.md` Issue 0 驗收標準第 1、2 點的自動化證明；第 3 點（真機重新驗證）以文件形式記錄給人類收尾執行。

- [ ] **Step 1：`flutter analyze` 全專案乾淨**

```bash
flutter analyze
```

Expected：`No issues found!`。

- [ ] **Step 2：完整 `flutter test`（本計畫唯一一次，比照 `CLAUDE.md`「測試執行範圍」約定，於整張計畫最後一個 Task 執行）**

```bash
flutter test
```

Expected：全數 PASS，含既有 `epic-10-search` Issue 0／Issue 6 測試套件（`sqlite_library_repository_test.dart` 全檔案）與本計畫新增的三個遷移測試，零回歸。

- [ ] **Step 3：（人類／執行者手動）真機重新驗證——`issues.md` 驗收標準第 3 點，無法自動化**

需要一台已知系統 SQLite 缺 FTS5 模組的真實裝置（本 Epic 根因記錄使用的裝置：`9491G`／`Hera_Vis_WIFI`，MediaTek 客製化 E-Ink ROM，Android 15）。

> **【審查修正 I-3】**：原本「先全新安裝新版 → 再裝舊版 → 最後覆蓋安裝新版」的順序在 Android 上不可行——步驟 1 全新安裝新版後，本機資料庫已經是 `onCreate` 直接建到的 version 25；接著安裝舊版 APK 時，Android 系統會因為 `versionCode` 較低直接以 `INSTALL_FAILED_VERSION_DOWNGRADE` 拒絕安裝；即使強行降級安裝，舊版程式碼只認得 version 24，開啟 version 25 資料庫時會直接崩潰，完全無法重現「version 24 且無 `book_content_fts`」的 Issue 6 場景，最後一步覆蓋安裝新版時面對的也不是真正的舊版資料庫，等於沒有驗證到 `onUpgrade` 遷移路徑。改為以下「先舊後新」的兩階段驗證，兩階段之間都先徹底解除安裝、互不污染：

**階段 A（升級遷移驗證，對應 Issue 6 場景）：**
1. 徹底解除安裝裝置上的 App：`adb uninstall cc.ugotit.elinkbook`。
2. 安裝換引擎前的舊版 APK（需要本計畫合併前、`main` 分支上的舊版建置產物）：`adb install <old_app.apk>`。開啟 App 後確認為 version 24 且無 `book_content_fts`（可用 `adb logcat` 或全文檢索畫面顯示「本裝置不支援」佐證）。
3. 以 `adb install -r <new_app.apk>`（**必須帶 `-r` 覆蓋安裝**、保留 App 資料；不可用 `flutter run` 或不帶 `-r` 的安裝方式，否則可能誤觸解除安裝重裝、清空本機資料庫，測不到 version 24→25 的 `onUpgrade` 遷移路徑）升級安裝在本分支上建置的新版 APK（`flutter build apk --debug`），確認既有裝置升級路徑成功走 `onUpgrade`、`isFullTextSearchAvailable` 變為 `true`、全文檢索畫面不再顯示「本裝置不支援」，且不崩潰。

**階段 B（全新安裝驗證）：**
4. 再次徹底解除安裝 App：`adb uninstall cc.ugotit.elinkbook`。
5. 全新安裝新版 APK：`adb install <new_app.apk>`。開啟 App 後確認 `onCreate` 直接建到 version 25、`isFullTextSearchAvailable=true`、全文檢索功能正常。

本步驟不寫自動化測試、不阻擋前面 5 個 Task 的程式碼合併，但屬於 `issues.md` Issue 0 完整驗收標準的一部分，需要人類在有實體裝置的環境下執行後才能將該工單標記為完成。

- [ ] **Step 4：（無需 commit）**

本 Task 純驗證，若 Step 1／Step 2 過程中發現任何問題，回到對應 Task 修正並重新提交；Step 3 是人工收尾動作，不產生程式碼變更。

---

## Self-Review 記錄

- **Spec 覆蓋**：`spec.md` §1（依賴變更）→ Task 1；§2（`main.dart` 初始化）→ Task 2；§2 真機整合測試同步初始化 → Task 3；§3（DB 遷移 version 24→25＋存在性檢查）→ Task 4；§4（不新增索引回補）→ Global Constraints 明文排除，無對應 Task；§5（Issue 6 機制不修改）→ Global Constraints 明文排除；§6（tokenizer 不修改）→ Global Constraints 明文排除；§7 三種遷移測試情境 → Task 4（情境 1＋2）／Task 5（情境 3）；§7 真機重新驗證 → Task 6 Step 3。`issues.md` 驗收標準三點分別對應 Task 6 Step 1（`flutter analyze`）、Step 2（遷移測試）、Step 3（真機）。
- **Placeholder 掃描**：全計畫無 TBD／「之後補」／「加適當的錯誤處理」等字樣，每個程式碼步驟皆含完整可執行片段。
- **型別/簽章一致性**：`_createBookContentFtsTableIfSupported(Database db)`、`createBookContentFtsTable`、`isFullTextSearchAvailable` 三者在 Task 4／5 中的呼叫方式與既有原始碼（`sqlite_library_repository.dart:937-950`、`:1265-1266`、`:31`）完全一致，未新增或更名任何公開介面。
- **審查回應總結（`reviews/review-plan-issue-0.md`）**：I-1（Task 4／5 合併為單一遷移 Task，兩個情境測試同時先紅後綠，避免既有 v23→v24 測試在中間狀態崩潰並產出破壞性 commit）、I-2（`pubspec.yaml` 插入指示改為明確的「兩行之間插入」，程式碼片段不再重複既有的 `sqflite:`／`path:` 兩行）、I-3（Task 6 Step 3 真機驗收順序改為「舊版安裝→覆蓋升級→（重新安裝）全新安裝」兩階段，避免 Android 降級安裝阻擋）皆已查證屬實並修訂；M-1（遷移測試補齊冷重開斷言）、M-2（「已有表」情境測試補齊升級前植入歷史資料＋升級後 MATCH 驗證）、M-3（`main()` 收尾大括號筆誤校正為 `}`）皆已採納。
