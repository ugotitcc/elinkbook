# Issue 1：標題字型資料層實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 新增單書偏好欄位 `heading_font_family`（`BookReaderPrefs.headingFontFamily`，`null`＝跟隨主字型），完成 SQLite 29→30 遷移、`ResolvedPreferences` 解析、版面預設集往返，並讓所有「整列重建」`BookReaderPrefs` 的位置帶上新欄位、不會把它靜默清空。本張**不碰渲染、不加 UI、不動 l10n**（Issue 2、3）。

**Architecture：** 完全比照 epic-65 Issue 1 的 `first_line_indent`（同一條路：模型 → 資料庫 → `ResolvedPreferences` → 預設集），差別只在型別是 `String?` 且**沒有全域預設**（`reader_prefs_manager_impl.dart` 直取 `book.headingFontFamily`）。

**Tech Stack：** Flutter 3.47.9／Dart 3.13.7、`sqflite`（測試用 `sqflite_common_ffi`）、`flutter_test`。指令一律在 `C:\Users\fycdc\AI\elinkBook\app` 目錄下執行。

**Spec：** `docs/epics/epic-68-heading-font/spec.md` §1（資料模型）、§6（整列重建守衛清單）；決策背景見 `design.md` D5、D6、D7、D12、D15。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **欄位語意**：`headingFontFamily == null`＝跟隨主字型；非 null＝字型家族名稱字串，語意同 `fontFamily`。位置一律緊接 `fontFamily` 之後。
- **`copyWith` 不引入 sentinel**（spec §1.2）：維持 `newValue ?? this.value`，「改回跟隨主字型」靠 `ReaderSettingsSheet._currentDraft` 整列建構直接傳 `null` 達成。**不要**為了本欄位改 `copyWith` 語意。
- **整列重建的地方都要補欄位**（epic-57 教訓，spec §6）。本張實際查證後的清單（`grep -rn "BookReaderPrefs(" app/lib`）：
  | 位置 | 現況 |
  |---|---|
  | `lib/reader/book_reader_prefs.dart` 建構子／`toMap`（約 146）／`fromMap`（約 187）／`==`（約 253）／`hashCode`（約 291）／`copyWith`（約 332）／`reflowableEpubFields()`（以字串定位） | 逐一補 |
  | `lib/screens/library_screen.dart` `_save()`（約 1944，書架「版面覆寫」） | 補 `headingFontFamily: existing.headingFontFamily` |
  | `lib/screens/fxl_settings_sheet.dart` `_notifyChanged()`（約 67） | 補 `headingFontFamily: widget.prefs.headingFontFamily` |
  | `lib/screens/reader_settings_sheet.dart` `_currentDraft`、`initState`、`didUpdateWidget`、欄位宣告 `late String? _fontFamily;`（行號約 293／144／185／99，一律以字串定位） | 新增 `_headingFontFamily` 狀態並三處同步（**不加 UI**） |
  | `lib/screens/pdf_settings_sheet.dart` | 不整列建構（`grep` 無 `BookReaderPrefs(`，走 `copyWith`），不需改；種子守衛測試自動涵蓋 |
  | `_resetToBookDefault`（`reader_settings_sheet.dart` 約 1779） | 只清 6 個數值欄位，不碰 `fontFamily`，標題字型同理**不清**；本張不改，Step 內以測試鎖定行為 |
- **資料庫升級**：版本 29→30；`_addHeadingFontFamilyColumn` 比照 `_addFirstLineIndentColumn`（`sqlite_library_repository.dart:809`，先查 `sqlite_master` 確認 `book_reader_prefs` 存在才 `ALTER TABLE`），呼叫放在 `oldVersion >= 2` 的 else 分支內、緊接 `if (oldVersion < 29)`（約 261–268 行）之後；`_createBookReaderPrefsTable`（489–533，現以 `first_line_indent REAL` 結尾）一步到位含新欄位。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；本張是 Epic 第一張，**不跑完整 `flutter test`**（Epic 最後一張 Issue 4 才跑）。
- **每個 Task／commit 結束都必須可編譯、`flutter analyze` 乾淨、被觸及的測試全綠。**
- **Windows 換行**：多數原始檔是 CRLF，Edit 的 `old_string` 不要含換行；不要對整個既有檔案跑 `dart format`；`git add` 一律明確列檔，**不得** `git add app` 或 `git add -A`（工作目錄有使用者本機的 `.claude/settings.json` 修改，不可夾帶）。
- **Commit**：訊息用正體中文，**不加 `Co-Authored-By`**；每個 Task 一個 commit；分支 `feat/epic-68-heading-font`（已存在，不新開）；計畫與實作同分支同 PR，不另開文件分支。

## Review Focus

1. **整列重建漏欄位**：`library_screen`、`fxl_settings_sheet`、`reader_settings_sheet` 任何一個漏掉，儲存時就清空標題字型。→ 種子補欄位後既有全欄位守衛自動轉紅，另各加一個明確的「標題字型不被清空」測試。
2. **遷移重複 `ALTER TABLE`**：`oldVersion == 1` 時建表已含新欄位，若在 else 分支外呼叫會拋 `duplicate column name`。→ 1→30 跳級測試。
3. **舊資料相容**：舊單書列、舊版面預設集 `prefs_json` 缺 key 必須讀成 `null`、不崩潰。
4. **`reflowableEpubFields()` 白名單**：必須納入新欄位（D7），否則預設集與「從其他書複製」會丟失標題字型；計數 22→23，12 個過濾欄位不變。
5. **硬編 29**：`grep` 查證後共 5 個測試檔、7 處斷言／名稱（見 Task 1），漏改任何一處該測試會紅。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/book_reader_prefs.dart` | 修改 | 新欄位與 7 個同步點 |
| `app/lib/library/sqlite_library_repository.dart` | 修改 | `version: 30`、建表、`_addHeadingFontFamilyColumn`、`onUpgrade` 呼叫 |
| `app/lib/reader/resolved_preferences.dart`、`reader_prefs_manager_impl.dart` | 修改 | `ResolvedPreferences.headingFontFamily` 與 `resolve()` 直取 |
| `app/lib/screens/library_screen.dart`、`fxl_settings_sheet.dart`、`reader_settings_sheet.dart` | 修改 | 整列重建帶入／草稿同步 |
| `app/test/support/full_book_reader_prefs.dart` | 修改 | 種子補欄位、註解欄位數 |
| `app/test/reader/book_reader_prefs_test.dart` | 修改 | 新欄位測試、計數 22→23、36 |
| `app/test/library/sqlite_library_repository_test.dart`、`app/test/stats/daily_reading_stats_schema_test.dart`、`app/test/dictionary/dictionary_database_test.dart` | 修改 | 版本斷言 29→30、遷移新測試 |
| `app/test/reader/book_reader_prefs_repository_test.dart` | 修改 | 存讀往返、舊列為 null |
| `app/test/reader/resolved_preferences_test.dart`、`reader_prefs_manager_test.dart` | 修改 | 解析測試 |
| `app/test/reader/layout_preset_repository_test.dart`、`layout_preset_test.dart`、`layout_preset_flow_test.dart` | 修改 | 預設集往返、舊 JSON、套用 |
| `app/test/screens/library_screen_test.dart`、`fxl_settings_sheet_test.dart`、`reader_settings_sheet_test.dart` | 修改 | 明確守衛測試；`pdf_settings_sheet_test.dart` 僅更新 group 名稱中的過時欄位數 |
| `CLAUDE.md`、`AGENTS.md` | 修改 | 主庫 `version: 29` → `30`（各一處：`CLAUDE.md:86`、`AGENTS.md:59`） |
| `docs/epics/epic-68-heading-font/issues.md`、`epic.md` | 修改 | 狀態與開發記錄 |

測試種子字串（本計畫統一）：`fullBookReaderPrefsSeed.headingFontFamily = 'TaiwanPearl'`（與 `fontFamily: 'SourceHanSerifTC'` 不同，才能抓到「被主字型覆蓋」的錯誤）。

---

### Task 0：提交本計畫

**Files：** `docs/epics/epic-68-heading-font/plans/plan-issue-1.md`

- [x] **Step 1：** 確認在 `feat/epic-68-heading-font`：`git branch --show-current`。
- [x] **Step 2：** 只提交本計畫（純文件，不夾帶 `.claude/settings.json`）：
  ```bash
  git add docs/epics/epic-68-heading-font/plans/plan-issue-1.md
  git commit -m "docs(epic-68): Issue 1 資料層實作計畫"
  ```

---

### Task 1：主庫 29→30 遷移（先加欄位，模型尚未使用）

> **為什麼遷移排在模型之前（審查 C1）：** `BookReaderPrefsRepository.save` 直接把 `prefs.toMap(bookId)` `insert` 進 `book_reader_prefs`。若先讓 `toMap` 多輸出 `heading_font_family` 鍵、資料庫卻還沒這個欄位，所有走真實 SQLite 的測試會拋 `table book_reader_prefs has no column named heading_font_family`，該 commit 即為紅。先加欄位則模型沒用到也不會壞，因此兩者順序固定為「遷移 → 模型」，每個 commit 皆綠。（不採併成單一 commit：兩者測試面不同，拆開較易審查與回溯。）
>
> 本 Task 只測試資料表層級（直接以 `database.insert/query` 驗欄位），**不引用 `BookReaderPrefs.headingFontFamily`**（尚不存在）；模型層的 `save/load` 往返測試放在 Task 2。

**Files：**
- 修改：`app/lib/library/sqlite_library_repository.dart`
- 修改：`app/test/library/sqlite_library_repository_test.dart`、`app/test/stats/daily_reading_stats_schema_test.dart`、`app/test/dictionary/dictionary_database_test.dart`

**硬編 29 實查結果**（`grep -rn "getVersion()" app/test`＋`grep -rn "version 29" app/test`，已涵蓋全部）：

| 檔案：行 | 內容 | 處理 |
|---|---|---|
| `sqlite_library_repository_test.dart:2748` | v28→29 測試 `expect(getVersion(), 29)` | 改 30，上方補註解「升級一路走到目前最新版本（30）」 |
| `sqlite_library_repository_test.dart:4899、4902` | 測試名稱「onCreate 直接建到 version 29」與 `getVersion(), 29` | 名稱與斷言改 30 |
| `sqlite_library_repository_test.dart:2556、2690、2769` | 標題文字「version 29 起…」「升級到 version 29」「跳級升級到 version 29」 | 這三個是描述 epic-65 當時的歷史事實，**標題不改**；僅 2748 的斷言值改 30（2690 測試名稱保留，因它描述 28→29 的欄位新增；為避免誤導，在斷言旁加註解） |
| `daily_reading_stats_schema_test.dart:30、36` | 名稱「version 29」＋`getVersion(), 29` | 名稱與斷言改 30 |
| `daily_reading_stats_schema_test.dart:108、109` | 註解「（29）」＋`getVersion(), 29` | 註解與斷言改 30 |
| `dictionary_database_test.dart:98、105` | 名稱「主資料庫版本仍為 29」＋`getVersion(), 29` | 名稱與斷言改 30 |
| `docs/adr/0038-…md:23` | 引用「版本仍為 28」 | 歷史紀錄，**不改** |
| `docs/archive/**`、其他 Epic 計畫 | 歷史文件 | 不改 |

- [x] **Step 1（紅，新測試）：**
  - `sqlite_library_repository_test.dart`，緊接「全新安裝的 book_reader_prefs 表包含 first_line_indent 欄位」（約 2567 行）新增 `全新安裝的 book_reader_prefs 表包含 heading_font_family 欄位（version 30 起 onCreate 已含括）`：`insertBook` 後 `database.insert('book_reader_prefs', {'book_id':…, 'heading_font_family': 'TaiwanPearl'})`，讀回 `row['heading_font_family'] == 'TaiwanPearl'`。另一條 `全新安裝時未寫入標題字型的列讀回 NULL`：只插 `book_id`，`row['heading_font_family']` 為 null。
  - 同檔，緊接 v28→29 測試（約 2767 行）之後，仿其寫法新增三個遷移測試（各自 `Directory.systemTemp.createTemp`、`addTearDown` 清理，以 `databaseFactory.openDatabase(version: N)` 建舊庫、關閉後 `SqliteLibraryRepository.open(dbPath)` 升級）：
    1. `既有 version 29 裝置升級到 version 30，book_reader_prefs 新增 heading_font_family 欄位，既有列保留且新欄位為 null`：舊庫 `book_reader_prefs` 欄位含 `font_family TEXT, first_line_indent REAL`，插入一列 `font_family: 'SourceHanSerifTC', first_line_indent: 2.0`；升級後 `getVersion() == 30`、舊欄位值保留、`heading_font_family` 為 null、可 `update` 寫入 `'TaiwanPearl'` 並讀回。
    2. `既有 version 28 裝置跳級升級到 version 30，兩個新欄位都補上且既有列保留`：舊庫欄位含 `font_family TEXT, pdf_page_turn_mode TEXT`；升級後 `first_line_indent`、`heading_font_family` 都存在且為 null、`pdf_page_turn_mode` 保留。
    3. `既有 version 1 裝置（無 book_reader_prefs 表）跳級升級到 version 30，建表含 heading_font_family 且不拋 duplicate column name`：比照 2768 行現有 v1 測試的舊庫建法；升級後插入 `{'book_id':'b1','heading_font_family':'TaiwanPearl'}`，讀回相同（`oldVersion == 1` 走 `_createBookReaderPrefsTable` 一步到位，若新增呼叫誤放在 else 分支外會在此紅）。
- [x] **Step 2（紅，既有斷言同步）：** 依上表把 `sqlite_library_repository_test.dart` 的 `getVersion(), 29` 斷言與「onCreate 直接建到 version 29」測試名稱（以字串定位，約 2748、4899、4902 行）、`daily_reading_stats_schema_test.dart`（約 30、36、108、109 行）、`dictionary_database_test.dart`（約 98、105 行）改為 30。
- [x] **Step 3（確認紅，涵蓋所有會紅的測試檔，審查 I1）：**
  ```bash
  flutter test test/library/sqlite_library_repository_test.dart
  flutter test test/stats/daily_reading_stats_schema_test.dart
  flutter test test/dictionary/dictionary_database_test.dart
  ```
  預期：三個檔案都紅——`sqlite_library_repository_test` 的新 heading 測試與改成 30 的斷言（`no such column: heading_font_family`／`Expected: <30> Actual: <29>`）；`daily_reading_stats_schema_test`、`dictionary_database_test` 只因版本斷言改 30 而紅（`Expected: <30> Actual: <29>`）。
- [x] **Step 4（綠，實作）：** `lib/library/sqlite_library_repository.dart`：
  - 第 58 行 `version: 29,` → `30`。
  - `onUpgrade` 的 `oldVersion >= 2` else 分支內、`if (oldVersion < 29) {…}`（約 261–268）之後新增：
    ```dart
    if (oldVersion < 30) {
      // epic-68-heading-font Issue 1：標題字型欄位。必須放在 else 分支內
      // （oldVersion >= 2）——理由同 _addFirstLineIndentColumn：oldVersion < 2
      // 時 _createBookReaderPrefsTable 已一步到位建表含 heading_font_family，
      // 若在 else 分支外無條件執行 ALTER TABLE，oldVersion == 1 的裝置會
      // 重複 ALTER TABLE 拋出崩潰。
      await _addHeadingFontFamilyColumn(db);
    }
    ```
  - `_createBookReaderPrefsTable`（約 530 行）：`first_line_indent REAL` 後補逗號並新增 `heading_font_family TEXT`（欄位為最後一個，無尾逗號）。
  - 緊接 `_addFirstLineIndentColumn`（約 809–819）之後新增 `_addHeadingFontFamilyColumn(Database db)`，內容比照之：查 `sqlite_master` 確認 `book_reader_prefs` 存在才 `ALTER TABLE book_reader_prefs ADD COLUMN heading_font_family TEXT`，附中文註解。
- [x] **Step 5（確認綠）：**
  ```bash
  flutter test test/library/sqlite_library_repository_test.dart
  flutter test test/stats/daily_reading_stats_schema_test.dart
  flutter test test/dictionary/dictionary_database_test.dart
  flutter test test/reader/book_reader_prefs_repository_test.dart
  flutter test test/reader/reader_prefs_manager_test.dart
  ```
  預期：全綠。後兩個是「模型尚未動、僅 schema 多一欄」的對照，確認新增欄位不影響既有真實 SQLite 的 `BookReaderPrefsRepository` 存讀（`insert` 未帶新欄位時為 NULL）。
- [x] **Step 6：** `flutter analyze`（`No issues found!`）；明確列檔 commit：
  ```bash
  git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart app/test/stats/daily_reading_stats_schema_test.dart app/test/dictionary/dictionary_database_test.dart
  git commit -m "feat(epic-68): 主庫升級至 version 30，新增 heading_font_family 欄位"
  ```

---

### Task 2：`BookReaderPrefs` 欄位、測試種子與整列重建守衛（須在 Task 1 遷移之後）

**Files：**
- 修改：`app/lib/reader/book_reader_prefs.dart`、`app/lib/screens/library_screen.dart`、`app/lib/screens/fxl_settings_sheet.dart`、`app/lib/screens/reader_settings_sheet.dart`
- 修改：`app/test/support/full_book_reader_prefs.dart`、`app/test/reader/book_reader_prefs_test.dart`、`app/test/reader/book_reader_prefs_repository_test.dart`、`app/test/screens/library_screen_test.dart`、`app/test/screens/fxl_settings_sheet_test.dart`、`app/test/screens/pdf_settings_sheet_test.dart`、`app/test/screens/reader_settings_sheet_test.dart`

> 為什麼模型、種子、三個重建點放同一個 Task／commit：種子補欄位（含 `toMap` 多一個 key）會同時影響 `book_reader_prefs_test` 的種子自檢與三張面板的全欄位守衛；拆開會讓中間 commit 紅燈。
>
> **真實 SQLite 受 `toMap` 影響的測試（grep 實查）：** `BookReaderPrefsRepository` 以 `prefs.toMap(bookId)` 寫入 `book_reader_prefs`，下列測試走真實 `SqliteLibraryRepository`（in-memory）＋ `BookReaderPrefsRepository`，Task 1 的 schema 已先備妥，本 Task 結束須全綠：`test/reader/book_reader_prefs_repository_test.dart`、`test/reader/reader_prefs_manager_test.dart`（約 349 行起的真實庫 group）、`test/reader/layout_preset_flow_test.dart`（約 474 行起「真實 sqlite」group）、`test/screens/library_screen_test.dart`（約 3376 行）、`test/screens/reader_screen_test.dart`（約 10397 行起 group）。`LayoutPresetRepository` 是把 `toMap` 轉成 `prefs_json` 文字存入 `layout_preset`（不是 `book_reader_prefs` 欄位），不會因缺欄位而拋錯，但仍一併跑以確認 JSON 往返。

- [x] **Step 1（紅，模型）：** 在 `test/reader/book_reader_prefs_test.dart`，仿 `group('firstLineIndent（epic-65 Issue 1：首行縮排）'`（約 580–639 行）新增 `group('headingFontFamily（epic-68 Issue 1：標題字型）'`，測試名稱與斷言重點：
  - `toMap／fromMap 往返保留字串`：`BookReaderPrefs(headingFontFamily: 'TaiwanPearl')` → `map['heading_font_family'] == 'TaiwanPearl'`，`fromMap(map).headingFontFamily == 'TaiwanPearl'`。
  - `null（跟隨主字型）往返後仍為 null`：`BookReaderPrefs.empty.toMap('b')['heading_font_family']` 為 null 且 `fromMap` 讀回 null。
  - `fromMap 缺少 heading_font_family 鍵（舊資料列／舊預設集 JSON）讀成 null`：`toMap('b')..remove('heading_font_family')` 後 `fromMap` 不拋例外、值為 null。
  - `== 與 hashCode 納入 headingFontFamily`：相同值相等且 hashCode 相等；與不同值、與缺值皆不相等。
  - `copyWith 更新 headingFontFamily 時，其餘欄位保留原值`：`copyWith(headingFontFamily: 'X')` 後 `fontFamily` 不變；另加一條 `copyWith()` 不傳參數時保留原 `headingFontFamily`（鎖定「無 sentinel」語意，spec §1.2）。
  - `reflowableEpubFields() 保留 headingFontFamily`：`BookReaderPrefs(headingFontFamily: 'X').reflowableEpubFields().headingFontFamily == 'X'`。
- [x] **Step 2（紅，既有斷言同步）：** 同檔更新既有斷言（編譯通過後這些才會因欄位數變動而紅，先改好期望值）：
  - 約 687 行測試名稱「共 12 個欄位，其餘 22 個流式 EPUB 欄位保留」→「其餘 23 個」；該測試 `const prefs = BookReaderPrefs(...)`（約 689 行）補 `headingFontFamily: 'TaiwanPearl'`，保留區補 `expect(filtered.headingFontFamily, 'TaiwanPearl');`，註解「// 21 個保留欄位」改為實際計數（原註解已與 22 不符，順手改成 `23 個保留欄位`，12 個清空欄位區塊不變）。
  - 約 774 行 `toMap 的 34 個欄位值全部非 null` → `35 個`；約 786 行 `expect(map.length, 35, reason: '34 個欄位 ＋ book_id')` → `36`、`'35 個欄位 ＋ book_id'`；約 795 行 `copyWith() 不傳參數時與種子相等（34 個欄位皆被帶回）` → `35 個`。
  - 先用 `grep -n "34\|35" test/reader/book_reader_prefs_test.dart` 確認沒有其他欄位數字漏改。
  - `test/reader/book_reader_prefs_repository_test.dart`（此測試需要模型欄位，因此放在本 Task，不放 Task 1），仿 `save 寫入後，load 讀回相同的值` 新增 `save 寫入標題字型後，load 讀回相同的值`（`BookReaderPrefs(fontFamily: 'SourceHanSerifTC', headingFontFamily: 'TaiwanPearl')`，`load` 結果 `==` 原值）與 `未寫入標題字型的列，load 讀回 headingFontFamily 為 null`（`BookReaderPrefs(fontSize: 20)` 存讀後 `headingFontFamily` 為 null）。
- [x] **Step 3（紅，種子與三個明確守衛）：**
  - `test/support/full_book_reader_prefs.dart`：在 `fontFamily: 'SourceHanSerifTC',` 下一行補 `headingFontFamily: 'TaiwanPearl',`；檔頭註解 `/// 34 個欄位全部填滿` 改 `35`（現況 34 個欄位、`toMap` 35 個 key 含 `book_id`；補上後 35 個欄位、36 個 key）。
  - **過時數字／名稱同步（審查 M2，以字串定位，不靠行號）：** 四個測試檔的 group 名稱與註解仍寫「種子 34 欄位」等，種子變 35 後會與事實不符（不影響通過，但要一併更新）：
    - `test/screens/fxl_settings_sheet_test.dart`：group `全欄位保留守衛（Issue 10）：種子 34 欄位，…` → `35 欄位`。
    - `test/screens/pdf_settings_sheet_test.dart`：同名 group（約 1220 行）→ `35 欄位`。
    - `test/screens/library_screen_test.dart`：測試名 `版面覆寫：種子 34 欄位全填，…`（約 5445 行）→ `35 欄位`。
    - `test/screens/reader_settings_sheet_test.dart`：group `…種子 34 欄位，操作一個控制項後，22 個流式欄位只有該欄位改變、…`（約 2702 行）→ `35 欄位`、`23 個流式欄位`；其內註解「種子過濾成流式 EPUB 的 21 個欄位（另 12 個為 null，是設計）」（約 2717 行）→ `23 個欄位`（12 個過濾欄位不變）。
    - 完成後 `grep -n "34 欄位\|22 個流式\|21 個欄位" test/screens test/reader test/support` 應無殘留。
  - `test/screens/library_screen_test.dart`：緊接「版面覆寫：種子 34 欄位全填…」（約 5444–5490 行）之後新增 `testWidgets('版面覆寫儲存：既有書籍的標題字型不被清空（epic-68 Issue 1）')`，流程完全複製該測試（種子存進 `FakeBookReaderPrefsRepository`、開 `book_action_menu_1` → `book_action_layout_override` → 點 `layout_override_save_button`，不改動任何控制項），斷言 `saved.headingFontFamily == 'TaiwanPearl'`。
  - `test/screens/fxl_settings_sheet_test.dart`：在 `_fxlFullFieldGuardTests()`（約 644 行）的 group 內新增 `testWidgets('切換全螢幕後標題字型不被清空（epic-68 Issue 1）')`：`final changed = await _tapAndCapture(tester, 'fxl_settings_fullscreen');` 斷言 `changed!.headingFontFamily == 'TaiwanPearl'`。
  - `test/screens/reader_settings_sheet_test.dart`：在「全欄位保留守衛（Issue 10）」group（約 2702–2747 行）內新增 `testWidgets('切換全螢幕後標題字型不被清空（epic-68 Issue 1）')`：`_pumpSheet(tester, fullBookReaderPrefsSeed, (p) => notified = p)` → `switchToTab(tester, '呈現')` → 點 `reader_settings_fullscreen` → 斷言 `notified!.headingFontFamily == 'TaiwanPearl'`。另加 `testWidgets('「重設為本書原樣式」不清空標題字型（epic-68 Issue 1）')`（審查 I3：**不要用全欄位種子**，種子全填時重設按鈕狀態未經驗證）：緊接既有測試「任一受影響欄位被覆寫時，固定列改顯示套用按鈕，點擊後 onChanged 帶出 5 個欄位皆為 null」（約 1292–1322 行，字串定位）之後，**沿用其完全相同的 prefs**（`fontSize: 18 / 16, fontWeight: 1.5, lineHeight: 2.0, paragraphSpacing: 1.5, letterSpacing: 0.05`）**外加** `headingFontFamily: 'TaiwanPearl'`，流程同其寫法（`switchToTab(tester, '預設集')` → `ensureVisible` → 點 `reader_settings_preset_reset_apply` → `pump`），斷言 `notified!.fontSize` 為 null（確認重設確實生效，非空轉）且 `notified!.headingFontFamily == 'TaiwanPearl'`（鎖定 `_resetToBookDefault` 只清 6 個數值欄位、不碰字型的既有行為）。此測試預期**直接綠**（`_currentDraft` 帶入 `_headingFontFamily` 之後），屬回歸守衛；反向驗證見 Step 7。
- [x] **Step 4（確認紅）：** 先確認紅燈原因正確。`dart analyze` 此時會報 `headingFontFamily` 未定義（編譯失敗即紅）：
  ```bash
  flutter test test/reader/book_reader_prefs_test.dart
  ```
  預期：編譯失敗，訊息含 `The named parameter 'headingFontFamily' isn't defined`。
- [x] **Step 5（綠，模型）：** `lib/reader/book_reader_prefs.dart` 在 `fontFamily` 之後新增，並同步 7 個點（行號為現況，Edit 時以字串定位）：
  - 欄位 `final String? headingFontFamily;`，附中文 doc 註解（`null`＝跟隨主字型；語意同 `fontFamily`；只套用 Foliate 流式格式，無全域預設；epic-68 Issue 1）。
  - 建構子（約 104）`this.headingFontFamily,` 緊接 `this.fontFamily,`。
  - `toMap`（約 146）`'heading_font_family': headingFontFamily,` 緊接 `'font_family'`。
  - `fromMap`（約 187）`headingFontFamily: map['heading_font_family'] as String?,` 緊接 `fontFamily`。
  - `==`（約 253）加 `other.headingFontFamily == headingFontFamily &&`。
  - `hashCode`（約 291）清單加 `headingFontFamily,`。
  - `copyWith`（約 332）加參數 `String? headingFontFamily,` 與 `headingFontFamily: headingFontFamily ?? this.headingFontFamily,`。
  - `reflowableEpubFields()`加 `headingFontFamily: headingFontFamily,`，並把該方法 doc 註解中「22 個欄位」改「23 個」、「其餘 12 個欄位」維持。
- [x] **Step 6（綠，三個重建點）：**
  - `lib/screens/library_screen.dart` `_save()`（約 1944）：`fontFamily: existing.fontFamily,` 下補 `headingFontFamily: existing.headingFontFamily,`。
  - `lib/screens/fxl_settings_sheet.dart` `_notifyChanged()`（約 67）：`fontFamily: widget.prefs.fontFamily,` 下補 `headingFontFamily: widget.prefs.headingFontFamily,`。
  - `lib/screens/reader_settings_sheet.dart`：第 99 行 `late String? _fontFamily;` 下新增 `late String? _headingFontFamily;`（附註解：本張僅帶入草稿，下拉 UI 在 Issue 3）；`initState`（144）`_headingFontFamily = widget.prefs.headingFontFamily;`；`didUpdateWidget` 的 `setState` 內（185）同上；`_currentDraft`（293）`headingFontFamily: _headingFontFamily,` 緊接 `fontFamily: _fontFamily,`。
- [x] **Step 7（確認綠，含真實 SQLite 測試）：** 只跑觸及的測試檔（`reader_settings_sheet_test`、`library_screen_test`、`reader_screen_test` 檔案大，分次跑）：
  ```bash
  flutter test test/reader/book_reader_prefs_test.dart
  flutter test test/reader/book_reader_prefs_repository_test.dart
  flutter test test/reader/reader_prefs_manager_test.dart
  flutter test test/reader/layout_preset_repository_test.dart
  flutter test test/reader/layout_preset_flow_test.dart
  flutter test test/screens/fxl_settings_sheet_test.dart
  flutter test test/screens/pdf_settings_sheet_test.dart
  flutter test test/screens/reader_settings_sheet_test.dart
  flutter test test/screens/library_screen_test.dart
  flutter test test/screens/reader_screen_test.dart
  ```
  預期：全綠（`pdf_settings_sheet_test` 為「不應被打壞」的對照，其全欄位守衛走 `copyWith`，種子補欄位後仍綠；前五個是真實 SQLite／JSON 往返，驗證 Task 1 先加欄位的順序確保 `toMap` 新 key 有對應欄位）。
  反向驗證（暫時修改，不 commit，驗完還原）：
  1. 註解 `library_screen.dart` `_save()` 的 `headingFontFamily: existing.headingFontFamily,` → 新的書架守衛測試與既有「版面覆寫：種子 35 欄位全填…」全欄位守衛紅。
  2. 註解 `fxl_settings_sheet.dart` `_notifyChanged()` 那一行 → `fxl_settings_sheet_test` 新測試與全欄位守衛紅。
  3. 註解 `reader_settings_sheet.dart` `_currentDraft` 的 `headingFontFamily: _headingFontFamily,` → 「切換全螢幕後標題字型不被清空」與「重設為本書原樣式不清空標題字型」皆紅。
- [x] **Step 8：** `flutter analyze` 必須 `No issues found!`；明確列檔 commit：
  ```bash
  git add app/lib/reader/book_reader_prefs.dart app/lib/screens/library_screen.dart app/lib/screens/fxl_settings_sheet.dart app/lib/screens/reader_settings_sheet.dart app/test/support/full_book_reader_prefs.dart app/test/reader/book_reader_prefs_test.dart app/test/reader/book_reader_prefs_repository_test.dart app/test/screens/library_screen_test.dart app/test/screens/fxl_settings_sheet_test.dart app/test/screens/pdf_settings_sheet_test.dart app/test/screens/reader_settings_sheet_test.dart
  git commit -m "feat(epic-68): BookReaderPrefs 新增標題字型欄位並補齊整列重建守衛"
  ```

---

### Task 3：`ResolvedPreferences` 與 `reader_prefs_manager_impl`

**Files：**
- 修改：`app/lib/reader/resolved_preferences.dart`、`app/lib/reader/reader_prefs_manager_impl.dart`
- 修改：`app/test/reader/resolved_preferences_test.dart`、`app/test/reader/reader_prefs_manager_test.dart`

- [x] **Step 1（紅）：**
  - `resolved_preferences_test.dart`：仿 56–93 行新增 `headingFontFamily 未傳入時為 null，傳入值原樣保留（epic-68 Issue 1）`：兩個 `const ResolvedPreferences(...)`（必填欄位照該檔現有寫法），`absent.headingFontFamily` 為 null、`present`（`headingFontFamily: 'TaiwanPearl'`）讀回 `'TaiwanPearl'`。
  - `reader_prefs_manager_test.dart`：在 `resolve()` group 內、緊接「首行縮排：單書覆寫值帶進 ResolvedPreferences…」（約 72 行）新增 `標題字型：直接取單書值，無全域預設；未覆寫時為 null（epic-68 Issue 1）`：`BookReaderPrefs.empty` → `headingFontFamily` 為 null；`BookReaderPrefs(headingFontFamily: 'TaiwanPearl')` → `'TaiwanPearl'`；`BookReaderPrefs(fontFamily: 'SourceHanSerifTC')`（只有主字型）→ `headingFontFamily` 仍為 null（鎖定「不從 `fontFamily` 推導」）。另在 41 行「全部欄位皆未覆寫」測試末尾（約 69 行 `firstLineIndent` 斷言後）補 `expect(resolved.headingFontFamily, isNull);`。
- [x] **Step 2（確認紅）：**
  ```bash
  flutter test test/reader/resolved_preferences_test.dart
  flutter test test/reader/reader_prefs_manager_test.dart
  ```
  預期：編譯失敗（`headingFontFamily` 未定義）。
- [x] **Step 3（綠）：**
  - `resolved_preferences.dart`：`final String? fontFamily;`（30 行）下新增 `final String? headingFontFamily;`（doc 註解：直接取 `book.headingFontFamily`，無全域預設，epic-68 D6；`null`＝跟隨主字型），建構子 `this.fontFamily,`（約 104 行）下補 `this.headingFontFamily,`。
  - `reader_prefs_manager_impl.dart` `resolve()`（195 行）`fontFamily: book.fontFamily,` 下補 `headingFontFamily: book.headingFontFamily,`。
- [x] **Step 4（確認綠）：** 同 Step 2 兩個指令，預期全綠。接著跑受 `ResolvedPreferences` 建構影響的最小集合確認未壞：
  ```bash
  flutter test test/reader/resolve_text_conversion_test.dart
  ```
- [x] **Step 5：** `flutter analyze`；明確列檔 commit：
  ```bash
  git add app/lib/reader/resolved_preferences.dart app/lib/reader/reader_prefs_manager_impl.dart app/test/reader/resolved_preferences_test.dart app/test/reader/reader_prefs_manager_test.dart
  git commit -m "feat(epic-68): ResolvedPreferences 新增標題字型並由單書偏好直取"
  ```

---

### Task 4：版面預設集往返與套用（補回歸守衛，非紅→綠）

> **誠實標明（審查 I2）：** 預設集往返與套用所需的實作，已在 Task 2 的 `toMap／fromMap／reflowableEpubFields` 一併帶出，因此本 Task 的測試**加上去預期直接是綠的**，性質是「補回歸守衛」，不是 TDD 紅→綠。守衛是否有效，改以 Step 2 的反向驗證（暫時破壞實作確認會紅）證明；反向驗證無法讓它變紅的測試必須改寫到會紅為止。

**Files：** `app/test/reader/layout_preset_repository_test.dart`、`app/test/reader/layout_preset_test.dart`、`app/test/reader/layout_preset_flow_test.dart`（**只改測試**；實作已由 Task 2 的 `toMap/fromMap/reflowableEpubFields` 帶出）

- [x] **Step 1（寫測試，預期直接綠；以 Step 2 反向驗證確認有效）：**
  - `layout_preset_repository_test.dart`，仿 145–173 行：
    - `prefs_json 往返保留 headingFontFamily（epic-68 Issue 1）`：`BookReaderPrefs(fontFamily: 'SourceHanSerifTC', headingFontFamily: 'TaiwanPearl')` 經 `repository.insert` → `listAll`，`restored.headingFontFamily == 'TaiwanPearl'` 且 `restored == prefs`。
    - `舊預設集 JSON 沒有 heading_font_family 鍵時讀成 null，不拋出例外`：以 `libraryRepository.database.insert('layout_preset', {…, 'prefs_json': '{"font_family":"SourceHanSerifTC","font_size":18.0}'})` 模擬 epic-68 之前寫入的 JSON，`restored.headingFontFamily` 為 null、`fontFamily == 'SourceHanSerifTC'`。
  - `layout_preset_test.dart`：仿 25–35 行新增 `LayoutPreset 的 prefs 保留 headingFontFamily（epic-68 Issue 1）`。
  - `layout_preset_flow_test.dart`：
    - `saveAsPreset`（假 repository 版 group）：緊接「寫入前以 reflowableEpubFields() 過濾」（以測試名稱字串定位）新增 `另存為預設集：標題字型進入快照`，`flow.saveAsPreset(const BookReaderPrefs(fontSize: 18, headingFontFamily: 'TaiwanPearl', pdfContrast: 30))` 後 `flow.presets.single.prefs.headingFontFamily == 'TaiwanPearl'` 且 `pdfContrast` 為 null。
    - `applyFromBook`（假 repository 版 group）：緊接成功案例新增 `從其他書複製：標題字型一併帶上`，來源書存含 `headingFontFamily: 'TaiwanPearl'` 與 `pdfContrast: 40`，複製後目標 `headingFontFamily == 'TaiwanPearl'`、`pdfContrast` 為 null。
    - `applyPreset`（審查 I2：**放在「LayoutPresetFlow（真實 sqlite）」group，不放假 repository group**）：`applyPreset` 直接寫 `preset.prefs`、不經 `reflowableEpubFields()` 白名單，所以在假 repository 版即使白名單被破壞也不會紅；改放真實 sqlite group（`BookReaderPrefsRepository` → `toMap` → `book_reader_prefs.heading_font_family` → `fromMap`）才會因序列化漏欄位而紅。新增 `套用預設集：標題字型寫入目標書籍（真實 sqlite 往返）`：建構預設集的方式仿該 group 既有的套用測試（先 `grep -n "applyPreset" test/reader/layout_preset_flow_test.dart` 取其寫法），預設集含 `headingFontFamily: 'TaiwanPearl'`，`flow.applyPreset(preset, targetBookIds: ['b1'])` 後 `(await prefsRepo.load('b1')).headingFontFamily == 'TaiwanPearl'`。
- [x] **Step 2（反向驗證：每個測試都必須能紅；暫時破壞、驗完還原、不 commit）：**
  1. 註解掉 `book_reader_prefs.dart` `reflowableEpubFields()` 內 `headingFontFamily: headingFontFamily,`，跑 `flutter test test/reader/layout_preset_flow_test.dart`。預期**紅**：`另存為預設集：標題字型進入快照`、`從其他書複製：標題字型一併帶上`。**預期仍綠**：`套用預設集…（真實 sqlite 往返）`（它不依賴白名單，不要求在此步紅）。還原後再跑預期全綠。
  2. 註解掉 `fromMap` 內的 `headingFontFamily: map['heading_font_family'] as String?,`，跑 `flutter test test/reader/layout_preset_flow_test.dart test/reader/layout_preset_repository_test.dart`。預期**紅**：`套用預設集…（真實 sqlite 往返）`、`prefs_json 往返保留 headingFontFamily`。還原。
  3. 若任一預期會紅的測試沒紅，代表測試沒有守住該行為，**必須改寫**（例如補斷言、改用更貼近的 group）到反向驗證會紅為止，才可進入 Step 3。
  4. `layout_preset_test.dart` 的新測試是純物件 `LayoutPreset` 持有 `prefs` 的結構守衛，不經序列化，註解模型欄位則編譯即失敗；視為文件性測試，不要求反向驗證變紅，其餘往返責任由 `layout_preset_repository_test` 承擔。舊 JSON 缺 key 的測試守的是 `fromMap` 對缺 key 不拋例外的既有行為，若把 `as String?` 改成 `as String` 才會紅，可選擇性驗證。
- [x] **Step 3（綠）：**
  ```bash
  flutter test test/reader/layout_preset_repository_test.dart
  flutter test test/reader/layout_preset_test.dart
  flutter test test/reader/layout_preset_flow_test.dart
  ```
  預期：全綠。
- [x] **Step 4：** `flutter analyze`；明確列檔 commit：
  ```bash
  git add app/test/reader/layout_preset_repository_test.dart app/test/reader/layout_preset_test.dart app/test/reader/layout_preset_flow_test.dart
  git commit -m "test(epic-68): 版面預設集往返與套用涵蓋標題字型"
  ```

---

### Task 5：收尾與驗收

**Files：** `CLAUDE.md`、`AGENTS.md`、`docs/epics/epic-68-heading-font/issues.md`、`docs/epics/epic-68-heading-font/epic.md`

- [x] **Step 1：版本描述同步。** `CLAUDE.md:86` 與 `AGENTS.md:59` 的「不進主庫 `version: 29`」各改為 `version: 30`；以 `git grep -n "version: 29"` 確認沒有遺漏（`docs/epics/epic-66-windows-port/plans/plan-issue-18.md:22` 是歷史計畫文字，不改）。`epic.md` 背景段「主庫 `version` 目前為 29」是 Discovery 時的描述，不改。
- [x] **Step 2：文件狀態。** `issues.md` 表格 Issue 1 狀態改「完成（待 PR）」；`epic.md`「進度」補一行：Issue 1 完成——欄位、遷移 29→30、`ResolvedPreferences`、整列重建守衛；列出被同步更新的既有斷言（`book_reader_prefs_test` 欄位數 36／流式 23、三個 `getVersion` 測試檔 30）。**不動** `docs/epics.md`（Epic 層看板，Epic 結案時才更新）。
- [x] **Step 3：驗收 grep。**
  ```bash
  grep -rn "headingFontFamily\|heading_font_family" app/lib
  ```
  預期涵蓋：`book_reader_prefs.dart`（建構子／欄位／`toMap`／`fromMap`／`==`／`hashCode`／`copyWith`／`reflowableEpubFields`）、`sqlite_library_repository.dart`（建表、遷移、遷移呼叫）、`resolved_preferences.dart`、`reader_prefs_manager_impl.dart`、`library_screen.dart`、`fxl_settings_sheet.dart`、`reader_settings_sheet.dart`（欄位／`initState`／`didUpdateWidget`／`_currentDraft`）。`git diff main --stat -- app/lib` 不得出現上述以外的檔案（特別是不得出現 `foliate_reader_view.dart`、`reader_screen.dart`、`main.js`、`*.arb`——那是 Issue 2、3）。
- [x] **Step 4：靜態檢查。**
  ```bash
  flutter analyze
  ```
  預期 `No issues found!`。本張**不新增／修改任何 `Key`、不新增字串**，`node tool/check_integration_keys.js` 與 `node tool/check_l10n_hardcoded_strings.js` 非必要；若要順手確認，須先在 PowerShell 前置 pnpm 內建 Node（見 memory `reference_windows-node-via-pnpm.md`）：
  ```powershell
  $env:PATH = "$env:PNPM_HOME;$env:PATH"; node --version   # 應為 v24.x
  node tool/check_integration_keys.js
  node tool/check_l10n_hardcoded_strings.js
  ```
  預期兩者 PASS（exit 0）。不得再把它們記成「未執行」，但本張無觸及理由時可不跑，在 `epic.md` 進度中一句話說明「本張未觸及 Key／字串」即可。
- [x] **Step 5：本張觸及測試檔最終彙整再跑一輪**（不是完整 `flutter test`；Epic 最後一張 Issue 4 才跑完整一次）：
  ```bash
  flutter test test/reader/book_reader_prefs_test.dart test/reader/book_reader_prefs_repository_test.dart test/reader/resolved_preferences_test.dart test/reader/reader_prefs_manager_test.dart test/reader/layout_preset_repository_test.dart test/reader/layout_preset_test.dart test/reader/layout_preset_flow_test.dart test/library/sqlite_library_repository_test.dart test/stats/daily_reading_stats_schema_test.dart test/dictionary/dictionary_database_test.dart test/screens/fxl_settings_sheet_test.dart test/screens/pdf_settings_sheet_test.dart
  flutter test test/screens/reader_settings_sheet_test.dart
  flutter test test/screens/library_screen_test.dart
  flutter test test/screens/reader_screen_test.dart
  ```
  預期：全綠（`reader_screen_test` 含真實 SQLite＋`BookReaderPrefsRepository` 的 group，本張雖未改它，仍須確認 `toMap` 新 key 不造成回歸）。
- [x] **Step 6：commit（明確列檔，不含 `.claude/settings.json`）：**
  ```bash
  git add CLAUDE.md AGENTS.md docs/epics/epic-68-heading-font/issues.md docs/epics/epic-68-heading-font/epic.md
  git commit -m "docs(epic-68): Issue 1 收尾，主庫版本描述同步為 30"
  ```
- [ ] **Step 7：** 程式審查（報告存 `docs/epics/epic-68-heading-font/reviews/review-code-issue-1.md`，依專案慣例審查先出報告、不直接修改）。本張無 PR（Epic 全部 Issue 完成後同一個 PR，見 `issues.md`）。

## 完成標準

1. `book_reader_prefs.heading_font_family TEXT` 存在於新裝置與 29→30、28→30、1→30 升級後的資料庫；舊列讀回 `NULL`。
2. `BookReaderPrefs.headingFontFamily` 在 `toMap/fromMap/==/hashCode/copyWith/reflowableEpubFields` 皆有；欄位數：`toMap` 36 個 key（35 欄＋`book_id`）、`reflowableEpubFields()` 保留 23 個。
3. `ResolvedPreferences.headingFontFamily` 由單書偏好直取，無全域預設。
4. 書架版面覆寫儲存、`FxlSettingsSheet`、`ReaderSettingsSheet` 儲存都不清空標題字型；版面預設集往返保留，舊 JSON 讀為 null。
5. `flutter analyze` 乾淨；本張觸及測試檔全綠；未跑完整 `flutter test`（刻意）。

## 審查處理紀錄

依 `docs/epics/epic-68-heading-font/reviews/review-plan-issue-1.md` 修訂。每項意見皆先以 grep／讀檔核實再處理。

| 編號 | 核實結果 | 處理 |
|---|---|---|
| C1（Critical） | 屬實。`BookReaderPrefsRepository.save` 以 `prefs.toMap(bookId)` 直接 `insert`；`toMap` 先多出 `heading_font_family` 鍵而資料表尚無該欄位，會讓走真實 SQLite 的測試拋 `no column named heading_font_family`。 | 採「重排順序」而非併 commit：新 Task 1＝遷移（`version: 30`、建表、`_addHeadingFontFamilyColumn`、硬編 29 測試），新 Task 2＝模型＋種子＋整列重建守衛，模型 commit 時欄位已存在，每個 commit 皆綠。Task 2 Step 7 的測試清單補上實查出的真實 SQLite 測試：`book_reader_prefs_repository_test`、`reader_prefs_manager_test`、`layout_preset_flow_test`（真實 sqlite group）、`library_screen_test`、`reader_screen_test`，另含 `layout_preset_repository_test`。補充查證：`LayoutPresetRepository` 是把 `toMap` 存成 `prefs_json` 文字，不會因缺欄位拋錯，但仍一併跑。 |
| I1 | 屬實。 | 新 Task 1 Step 3 改為三個測試檔都跑（`sqlite_library_repository_test`、`daily_reading_stats_schema_test`、`dictionary_database_test`），並說明各自為何紅。原本放在遷移 Task 的 `book_reader_prefs_repository_test` 標題字型存讀測試，因需模型欄位，移到模型 Task（Task 2）。 |
| I2 | 屬實，且進一步查到 `applyPreset` 直接寫 `preset.prefs`、不經 `reflowableEpubFields()`，註解白名單不會讓它變紅。 | Task 4 標題與說明誠實標為「補回歸守衛（預期直接綠）」。`applyPreset` 測試改放「LayoutPresetFlow（真實 sqlite）」group，使註解 `fromMap` 該行時會紅；Step 2 明列三組反向驗證與各自預期紅／不紅的測試，並規定反向驗證不紅者必須改寫。`layout_preset_test` 的純物件測試明確標為文件性守衛、不要求變紅。 |
| I3 | 屬實。既有測試（約 1292–1322 行）用 5 個覆寫欄位的 prefs 才確認過按鈕可見；全欄位種子情況未經驗證。 | 「重設為本書原樣式」測試改為沿用該既有 prefs 並加 `headingFontFamily: 'TaiwanPearl'`，額外斷言 `fontSize` 為 null 以確認重設確實生效。Task 2 Step 7 補三組反向驗證（含此測試）。 |
| M1 | 屬實（實查 104／146／187／253／291／332，`resolved_preferences` 建構子 104）。 | 行號全改為「約 N」並強調以字串定位。 |
| M2 | 屬實：`fxl_settings_sheet_test`、`pdf_settings_sheet_test`、`library_screen_test` 的「種子 34 欄位」與 `reader_settings_sheet_test` 的「34 欄位／22 個流式欄位」及註解「21 個欄位」。 | 列入新 Task 2 Step 3，並加 grep 殘留檢查；`pdf_settings_sheet_test.dart` 加入 Task 2 的檔案清單與 commit。 |
| M3 | 僅提醒，無需修改。 | 硬編 29 全部在新 Task 1 處理，收尾 Task 5 只做 `CLAUDE.md`／`AGENTS.md` 的文字描述，不重複。 |
| M4 | 無問題。 | 不處理。 |

**新 Task 順序：** Task 0 提交計畫 → Task 1 主庫 29→30 遷移 → Task 2 `BookReaderPrefs` 欄位＋種子＋整列重建守衛 → Task 3 `ResolvedPreferences` → Task 4 預設集往返／套用（補回歸守衛）→ Task 5 收尾與驗收。

本次無不同意的審查意見。
