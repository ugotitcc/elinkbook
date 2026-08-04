# Epic 8 — 雲端同步 Issue 8：`integration_test/sync_engine_test.dart` sqflite `:memory:` 裝置隔離失敗（bug）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 `integration_test/sync_engine_test.dart` 用兩個 `SqliteLibraryRepository.open(inMemoryDatabasePath)` 模擬「兩台獨立裝置」時，第二次呼叫實際上會回傳跟第一次完全相同的底層資料庫連線的問題，讓整份測試檔（不加 `--plain-name` 篩選）能在真機上完整跑完。

**根本原因（已用最小重現案例實測確認，見下方「與 issues.md 的落差說明」）：** `sqflite`/`sqflite_common` 的 `openDatabase()` 有一個具名參數 `singleInstance`，**預設為 `true`**——官方文件明載：「當 `singleInstance` 為 `true`（預設值）時，對同一個路徑會回傳同一個資料庫實例，後續用相同路徑呼叫 `openDatabase()` 會回傳同一個實例，並捨棄該次呼叫的其他所有參數（例如 callback）」（`sqflite_common-2.5.8/lib/sqflite.dart` `openDatabase()` doc comment）。這個快取（`sqflite_common-2.5.8/lib/src/factory_mixin.dart:47,94-97` 的 `databaseOpenHelpers` map）是以**字面路徑字串**為 key，`":memory:"`（`inMemoryDatabasePath` 常數的值）對所有呼叫端都是同一個字串。`integration_test/sync_engine_test.dart` 的 `deviceA`／`deviceB` 兩次呼叫都用同一個 `inMemoryDatabasePath` 常數、都沒有明確傳入 `singleInstance: false`，因此第二次呼叫（`deviceB = await SqliteLibraryRepository.open(inMemoryDatabasePath)`）會直接**回傳 `deviceA` 那個 `Database` 物件本身**（非新建的獨立資料庫），導致 `deviceB.insertBook(bookA)`（`bookA.id` 與已經插入 `deviceA` 的那筆相同）撞到 `UNIQUE constraint failed: books.id`。

**Architecture：** 兩處變更，皆為既有程式的最小追加：(1) `SqliteLibraryRepository.open()` 新增可選具名參數 `singleInstance`（預設 `true`，與 sqflite 本身預設一致，對既有的 83 個呼叫點零回歸），讓呼叫端可以明確要求「這次開啟不要共用任何快取的連線」；(2) `integration_test/sync_engine_test.dart` 既有的 4 個 `SqliteLibraryRepository.open(inMemoryDatabasePath)` 呼叫點（兩個測試各自的 `deviceA`／`deviceB`）皆加上 `singleInstance: false`，讓每個「模擬裝置」都是真正獨立的記憶體內資料庫。

**Tech Stack：** Flutter／Dart，`sqflite`（`app/lib/library/sqlite_library_repository.dart` 既有）、`sqflite_common_ffi`（`integration_test` 既有，用於在真機上以 FFI 後端模擬多台裝置的獨立本機資料庫）。

## Global Constraints

- 所有新增/修改的程式碼註解、文件、commit message 一律使用正體中文（專案 `CLAUDE.md` 規定）。
- 每個 Task 完成後 `flutter analyze`（於 `app/` 目錄下執行）必須維持乾淨（"No issues found!"）。
- **`SqliteLibraryRepository.open()` 新增的 `singleInstance` 參數必須是可選具名參數、預設值為 `true`**——專案內現有 83 個呼叫點（`grep -rn "SqliteLibraryRepository.open("`，涵蓋 `lib/main.dart` 正式啟動流程、`test/`、`integration_test/`）皆不得因本次修改而改變行為，這是本 Issue「獨立 bug 修復，不阻擋 Issue 5/6」的前提。
- **Task 2 的最終驗證必須在真實 Android 裝置/模擬器上執行**（`flutter test integration_test/sync_engine_test.dart -d <device-id>`，不加 `--plain-name` 篩選，執行完整檔案），比照本專案兩層測試架構慣例（`integration_test/` 涉及需要真機驗證的行為；本次雖非 `PlatformView` 渲染問題，但既有 bug 報告本身就是「僅在真機上重現」，且測試本身呼叫真實 PocketBase 測試實例 `pbdev.jigong.org`，純本機模擬環境無法完整重現與驗證）。

---

### Task 1：`SqliteLibraryRepository.open()` 新增 `singleInstance` 具名參數

**Files：**
- Modify: `app/lib/library/sqlite_library_repository.dart:25`（`open()` 方法簽章與內部 `openDatabase(...)` 呼叫）
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces：**
- Consumes：無（`SqliteLibraryRepository` 既有建構子與內部方法皆不變）。
- Produces：`SqliteLibraryRepository.open(String path, {bool singleInstance = true})`——這是 Task 2 唯一需要知道的介面：呼叫端可傳入 `singleInstance: false` 取得一個不與任何既有快取連線共用的全新資料庫連線。

現況：`app/lib/library/sqlite_library_repository.dart` 第 25 行起，`open()` 呼叫 `openDatabase(path, version: 18, ...)` 時完全沒有傳遞 `singleInstance`，因此永遠採用 sqflite 的預設值 `true`。

- [x] **Step 1：在 `sqlite_library_repository_test.dart` 寫一個會失敗（編譯錯誤）的測試**

在 `app/test/library/sqlite_library_repository_test.dart` 檔案最後一個 `test(...)` 區塊（「既有 version 17 裝置升級到 version 18，正確新增 sync_remote_ids／sync_pending_records 兩張表」，第 2607-2637 行）結束的 `});` 之後、`main()` 收尾的 `}`（第 2638 行）之前插入：

```dart

  test(
      'open() 傳入 singleInstance:false 時，兩次呼叫相同的 inMemoryDatabasePath '
      '是彼此獨立的資料庫，不會共用同一個底層連線（epic-8-sync Issue 8）', () async {
    final deviceA = await SqliteLibraryRepository.open(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    addTearDown(() => deviceA.close());
    await deviceA.insertBook(_book('shared-id'));

    final deviceB = await SqliteLibraryRepository.open(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    addTearDown(() => deviceB.close());
    // sqflite 的 openDatabase() 預設 singleInstance:true：對同一個字面路徑
    // 字串（":memory:"）第二次呼叫 open() 會直接回傳第一次那個 Database
    // 物件（sqflite_common factory_mixin.dart 的 databaseOpenHelpers[path]
    // 快取，只在 options.singleInstance == false 時才略過）。若這裡沒有
    // 正確傳遞 singleInstance:false，deviceB 事實上會是 deviceA 同一個
    // 資料庫，這一行會因為重複插入相同 id 撞到 UNIQUE constraint 而拋出
    // DatabaseException。
    await deviceB.insertBook(_book('shared-id'));

    final booksInA = await deviceA.listBooks();
    expect(booksInA, hasLength(1),
        reason: 'deviceA 應只看到自己插入的那一筆，看不到 deviceB 插入的另一筆'
            '同 id 資料（若上一行 insertBook 沒有拋出例外，代表兩者仍是同一個'
            '資料庫但剛好沒有觸發 UNIQUE constraint，這個斷言會抓到這種情況）');
  });
```

- [x] **Step 2：執行測試，確認目前會失敗**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart --plain-name "singleInstance"`

Expected: FAIL——編譯錯誤，`SqliteLibraryRepository.open()` 目前沒有 `singleInstance` 具名參數（`The named parameter 'singleInstance' isn't defined`）。

- [x] **Step 3：實作**

修改 `app/lib/library/sqlite_library_repository.dart` 第 25-28 行，原本：

```dart
  static Future<SqliteLibraryRepository> open(String path) async {
    final db = await openDatabase(
      path,
      version: 18,
```

改為：

```dart
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
      version: 18,
      singleInstance: singleInstance,
```

（第 28 行 `version: 18,` 之後緊接新增 `singleInstance: singleInstance,` 這一行，`openDatabase(...)` 呼叫其餘既有具名參數 `onConfigure`／`onCreate`／`onUpgrade`／`onOpen` 完全不動。）

- [x] **Step 4：執行測試，確認通過**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart --plain-name "singleInstance"`

Expected: PASS。

- [x] **Step 5：執行整份 `sqlite_library_repository_test.dart`，確認無回歸**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart`

Expected: 全數 PASS（新參數預設值 `true` 與既有行為相同，其餘既有測試皆未傳入 `singleInstance`，不受影響）。

- [x] **Step 6：執行 `flutter test`（全專案），確認無回歸**

Run: `cd app && flutter test`

Expected: 全數 PASS（`SqliteLibraryRepository.open()` 專案內既有的 83 個呼叫點皆未傳入 `singleInstance`，維持預設值 `true`，行為零變更；Task 1 本身只修改方法簽章與新增一個測試，不觸碰任何既有呼叫點的原始碼）。

- [x] **Step 7：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`

Expected: `No issues found!`

- [x] **Step 8：Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "fix(epic-8-sync): Issue 8 Task 1 — SqliteLibraryRepository.open() 新增 singleInstance 參數"
```

---

### Task 2：修正 `integration_test/sync_engine_test.dart` 的裝置模擬呼叫點

**Files：**
- Modify: `app/integration_test/sync_engine_test.dart`（4 個 `SqliteLibraryRepository.open(inMemoryDatabasePath)` 呼叫點）

**Interfaces：**
- Consumes：`SqliteLibraryRepository.open(String path, {bool singleInstance = true})`（Task 1 產出）。
- Produces：無新增公開介面，純測試檔案內部修正。

現況：`app/integration_test/sync_engine_test.dart` 有 4 處 `SqliteLibraryRepository.open(inMemoryDatabasePath)` 呼叫（第 57、91、138、173 行，分別是第一個測試的 `deviceA`／`deviceB`、第二個測試的 `deviceA`／`deviceB`），4 處呼叫的原始碼文字完全相同、皆未傳入 `singleInstance`。

- [x] **Step 1：修正 4 個呼叫點**

在 `app/integration_test/sync_engine_test.dart` 中，將全部 4 處（`replace_all`）：

```dart
    final deviceA = await SqliteLibraryRepository.open(inMemoryDatabasePath);
```

改為：

```dart
    final deviceA = await SqliteLibraryRepository.open(
      inMemoryDatabasePath,
      singleInstance: false,
    );
```

以及全部（`replace_all`）：

```dart
    final deviceB = await SqliteLibraryRepository.open(inMemoryDatabasePath);
```

改為：

```dart
    final deviceB = await SqliteLibraryRepository.open(
      inMemoryDatabasePath,
      singleInstance: false,
    );
```

（`deviceA`/`deviceB` 各自的原始文字在檔案中各出現 2 次——分屬第一個與第二個 `testWidgets`——兩次的替換內容完全相同，用 `replace_all: true` 一次處理。修改後 4 處呼叫點皆帶有 `singleInstance: false`，讓每個「模擬裝置」都是真正獨立的記憶體內資料庫，不會透過 sqflite 的 Dart 層路徑快取互相共用。）

- [x] **Step 2：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`

Expected: `No issues found!`

- [x] **Step 3：真機驗證整份 `integration_test/sync_engine_test.dart`（不加 `--plain-name` 篩選）**

Run: `cd app && flutter devices` 確認至少一台已連接的 Android 裝置/模擬器，取得 `<device-id>`，接著：

Run: `cd app && flutter test integration_test/sync_engine_test.dart -d <device-id>`

Expected: 3 個測試全數 PASS——

1. 「端到端 checkpoint：推送本機新增的書籤，真的透過 PocketBase Batch API 寫入，並於下一次 checkpoint 下載回另一個模擬裝置」（Issue 4 既有測試，本 Issue 要修的崩潰點）：`deviceB.insertBook(bookA)` 不再拋出 `UNIQUE constraint failed: books.id`。
2. 「雙裝置閱讀位置衝突：...」（Issue 5 Task 6 測試）：確認不需要 `--plain-name` 隔離也能通過。
3. 「sync_reading_positions unique index：...」（Issue 9 測試，不使用 `SqliteLibraryRepository`，本次修改預期不受影響）。

若裝置環境暫時無法取得（例如目前工作階段沒有連接的 Android 裝置），此步驟必須交由有真機/模擬器存取權的後續階段執行，不可用純 `flutter test`（無 `-d`）替代驗證——本 Issue 的驗收標準明確要求真機確認。

**實測結果**（2026-08-04，真機 `3CEF42ECD491687`，`flutter test integration_test/sync_engine_test.dart -d 3CEF42ECD491687`，不加 `--plain-name` 篩選）：`00:40 +3: All tests passed!`——3 個測試全數 PASS，確認本 Issue 要修的崩潰點（`deviceB.insertBook(bookA)` 撞到 `UNIQUE constraint failed: books.id`）已解決，且 Issue 5 Task 6 的雙裝置測試不再需要 `--plain-name` 隔離即可通過。`/superpowers:requesting-code-review` 審查報告（`review-report-code-issue-8.md`）指出的唯一 Important 問題（真機驗證缺口）至此已補齊。

- [x] **Step 4：Commit**

```bash
git add app/integration_test/sync_engine_test.dart
git commit -m "fix(epic-8-sync): Issue 8 Task 2 — 修正 integration_test/sync_engine_test.dart 裝置模擬呼叫點加上 singleInstance:false"
```

---

## 與 issues.md 的落差說明

1. **根本原因與 issues.md 原文「尚待查證」的兩個猜測皆不成立，已用實測排除**：issues.md 原本猜測（a）`sqflite_common_ffi` 底層背景 isolate 在快速連續開啟多個 `:memory:` 連線時的 race condition，或（b）鎖定版本（`2.4.0+3`）已知的套件 bug、可能後續版本已修正。經對照本專案實際鎖定的原始碼（`sqflite_common-2.5.8/lib/src/factory_mixin.dart`、`sqflite_common-2.5.8/lib/sqflite.dart`、`sqflite_common_ffi-2.4.0+3/lib/src/sqflite_ffi_impl_io.dart`）並用一個獨立的最小重現案例實測（`openDatabase(inMemoryDatabasePath)` 呼叫兩次，`identical(dbA, dbB)` 回傳 `true`；改用 `singleInstance: false` 後兩者才是真正獨立的資料庫），確認根本原因是 sqflite 套件本身**文件明載、非 bug 的預設行為**（`openDatabase()` 的 `singleInstance` 預設 `true`，快取以字面路徑字串為 key），不是 race condition、也不是特定版本的缺陷——因此「升級 `sqflite_common_ffi` 版本」這個候選修法對本問題無效，不予採用。
2. **採用的修法是 issues.md「建議做法」兩個候選之外的第三個選項**：issues.md 原文建議「改用具名的 in-memory URI 讓兩個『裝置』使用不同路徑字串（file:deviceA?mode=memory 等）」或「升級 sqflite_common_ffi 版本」。本計畫改採 `singleInstance: false`——這是 sqflite 官方文件本身針對這個情境的建議做法（`usage_recommendations.md`「Isolates」一節），且不需要讓 `openDatabase()` 內部走 URI 解析分支（該分支會額外對檔案系統做 `File.exists()`／`Directory(dirname(path)).create()` 防禦性檢查，在真機上執行這些呼叫屬不必要的副作用），是更直接、更貼近 sqflite 既有設計意圖的修法，且完全不需要新增 production 端的 URI 組裝邏輯。
3. **Task 1 修改的是 production 程式碼（`SqliteLibraryRepository.open()`），而非只在測試檔內處理**：因為 `SqliteLibraryRepository.open()` 目前沒有任何管道可以讓呼叫端傳入 `singleInstance`，若要在 `integration_test` 呼叫點使用 `singleInstance: false`，必須先讓這個既有的 static factory 方法支援這個參數。新參數為可選、預設值維持 `true`，對其餘既有呼叫點零回歸（見 Global Constraints）。
