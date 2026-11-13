# Issue 4：刪除自訂字型連動 實作計畫（本 Epic 最後一張）

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 讓「刪除自訂字型」同時處理主字型與標題字型：`CustomFontsRepository.countBooksUsing` 改數「主字型**或**標題字型用到該字型的書」（每本只算一次）；`deleteAndResetUsage` 在同一交易內以**兩條各自條件式的 UPDATE** 只清命中的欄位（標題字型用該字型、主字型用另一字型 → 主字型不被清，反之亦然；兩欄都命中則同時清）；刪除確認對話框的書數因此自動涵蓋標題字型使用者。本張同時是 Epic 最後一張：跑完整 `flutter test`（只在此跑一次）、靜態檢查、harness `run-all`，並把 Epic 狀態更新為「全數完成，待歸檔」。**不歸檔（由人類指定）、不改資料層／渲染層／UI（Issue 1～3 已完成）。**

**Architecture：** 純 SQL 與測試的小改動，簽章不變。`countBooksUsing` 的 SQL 由 `WHERE font_family = ?` 改為 `WHERE font_family = ? OR heading_font_family = ?`（單一 `COUNT(*)` 以列為單位，`book_reader_prefs` 一書一列，所以兩欄都命中的書自然只算一次，不可改成兩個 COUNT 相加）。`deleteAndResetUsage` 的交易內多加第二條 `txn.update`，兩條各自 `where` 一個欄位。刪除確認對話框（`font_management_screen.dart` `_deleteFont`）本身不需改：它只顯示 `countBooksUsing` 的回傳值。

**Tech Stack：** Flutter 3.47.9／Dart 3.13.7、`flutter_test`、`sqflite_common_ffi`（既有測試已用）。指令一律在 `C:\Users\fycdc\AI\elinkBook\app` 下執行。

**Spec：** `docs/epics/epic-68-heading-font/spec.md` §5、§6；`design.md` D11、D16；驗收 `issues.md` Issue 4。

## 已實際查證的現況（行號僅供參考，一律以字串定位）

| 位置 | 查證結果 |
|---|---|
| `lib/reader/custom_fonts_repository.dart` `countBooksUsing` | 現為 `rawQuery('SELECT COUNT(*) AS c FROM book_reader_prefs WHERE font_family = ?', [familyName])`，回傳 `(result.first['c'] as int?) ?? 0`；doc comment 寫「統計 … 中目前使用中 [familyName] 的書籍數量，供刪除前的確認對話框文案使用」。 |
| 同檔 `deleteAndResetUsage` | `_db.transaction((txn) async { txn.delete('custom_fonts', where: 'id = ?'…); txn.update('book_reader_prefs', {'font_family': null}, where: 'font_family = ?', whereArgs: [familyName]); })`；doc comment 寫「把所有使用中書籍的 `font_family` 重置為 `NULL`（FR-09 規則…）」。只處理 `font_family`。 |
| 呼叫端（全 repo 搜尋 `deleteAndResetUsage`／`countBooksUsing`） | `lib/` 只有 `font_management_screen.dart` `_deleteFont`（`countBooksUsing` → 對話框 → `deleteAndResetUsage`）與 repository 自身；`test/` 只有 `test/reader/custom_fonts_repository_test.dart` 與 `test/support/fake_custom_fonts_repository.dart`；`integration_test/`、`tool/` 無引用。其餘命中皆為 docs（ADR 0035、已歸檔 Epic、本 Epic 文件）。 |
| 其他讀寫 `font_family` 欄位的程式 | `lib/library/sqlite_library_repository.dart` 只有建表與歷史遷移（約 505、857–887 行，舊版 AppFont 列舉轉家族名稱，與刪除字型無關）；`book_reader_prefs.dart` 的 `toMap`／`fromMap`。**沒有其他處依 `font_family` 篩選或清除**，故刪除連動只需動 `custom_fonts_repository.dart`。 |
| 資料表 | `book_reader_prefs` 以 `book_id` 為鍵一書一列；`heading_font_family TEXT` 已由 Issue 1 加入（建表與遷移）。既有測試直接 `db.insert('book_reader_prefs', {'book_id':…, 'font_family':…})`，不需補其他欄位，新測試可再加 `'heading_font_family'`。 |
| 既有測試 `test/reader/custom_fonts_repository_test.dart` | 檔尾 `group('CustomFontsRepository')`：`setUp` 以 `SqliteLibraryRepository.open(inMemoryDatabasePath)`＋`CustomFontsRepository(libraryRepository.database)`；既有 `countBooksUsing 正確統計 book_reader_prefs 使用中筆數`（約 145–163 行，只用 `font_family`，b1／b2 用 `UsedFamily`、b3 用 `Other`）與 `deleteAndResetUsage 於同一交易內刪除字型並把使用中書籍重置為 NULL`（約 165–190 行，b1 `ToDeleteFamily`、b2 `KeepFamily`，斷言 b1 `font_family` null、b2 保留）。**兩者語意在新行為下仍成立，保留不動**，新增案例放在其後。檔內有 helper `_book(String id)`。 |
| `test/support/fake_custom_fonts_repository.dart` | 不碰資料庫：`countBooksUsing` 回 `usageCounts[familyName] ?? 0`（測試預先手動設定）；`deleteAndResetUsage` 只 `_storage.removeWhere(id)`。Fake 沒有 `book_reader_prefs` 資料可「連動」，其語意本來就是「呼叫端宣告使用數」，**沒有欄位語意需要同步**。只需更新 doc comment 明確寫出「計數口徑涵蓋主字型與標題字型使用者，由測試自行設定 `usageCounts`」，避免日後誤以為 Fake 只算主字型。**不新增邏輯**（見風險）。 |
| 刪除流程與對話框 | `font_management_screen.dart` `_deleteFont`：先 `await repository.countBooksUsing(font.familyName)`，`usageCount > 0` 才顯示 `l10n.fontManagementDeleteConfirmMessage(usageCount)`，確認後 `deleteAndResetUsage(font.id!, font.familyName)` 再 `_loadFonts()`。既有 widget 測試 `刪除使用中的字型：確認對話框文案含使用中書籍數量提示`（`font_management_screen_test.dart` 約 168 行）用 Fake 設 `usageCounts['UsedFamily'] = 3`，斷言文字「目前有 3 本書使用此字型，刪除後將自動改用預設字型」。 |
| 對話框文案（l10n） | `fontManagementDeleteConfirmMessage`（四份 arb 都有，約 464／2104 行）：「目前有 {n} 本書使用此字型，刪除後將自動改用預設字型」（zh_CN「…使用此字体，删除后将自动改用预设字体」；en「N books currently use this font. They will fall back to the default font after deletion.」）。**評估結論：不改文案。** 「N 本書使用此字型」在涵蓋標題字型後仍為真；「改用預設字型」對僅作為標題字型的書略不精確（實際是標題改為跟隨主字型），但語意方向相同（回到非自訂字型），且改文案要動四份 arb＋`gen-l10n`＋產生檔，超出「連動」範圍。列為待人類確認項（見「風險與備註」），本張不動。 |
| 可下載字型刪除（ADR 0035） | `_deleteDownloadedFont`（約 419 行）刻意**不**呼叫 `countBooksUsing`／`deleteAndResetUsage`，不碰書籍偏好（ADR 0035 第 30 行：刪可下載字型保留偏好，字型隨時可重新下載；`effectiveFamily` 退回顯示）。標題字型指向已刪的可下載字型時同樣由 `effectiveFamily` 退回，不改寫偏好。**確認不需處理。** |
| Windows 端 | `font_management_screen.dart` 無 `Platform` 分支（只有一處註解提到 `PlatformFile`）；`main.dart` 只建構一個 `CustomFontsRepository(repository.database)` 傳給各畫面；`lib/` 其他處無字型刪除路徑。Windows 與 Android 走同一條刪除路徑，**無另外的 Windows 刪除實作**。 |
| `CLAUDE.md` | 第 107 行（「版面與排版」內建字型段）結尾為「刪除目前使用中的自訂字型時須自動退回預設字型。」；主庫 `version: 30` 已在 Issue 1 更新（CLAUDE.md 與 AGENTS.md 各一處）。AGENTS.md 無該字型段落。除 107 行外 CLAUDE.md 沒有其他提到字型欄位或字型設定處。 |
| `docs/epics.md` 看板 | 第 79 行 `epic-68-heading-font` 備註仍是「Discovery 已定案（2026-11-14），`design.md` 已寫，尚未拆 Issue」（**已過時**）；狀態 🟡 開發中。 |
| 全套測試不穩定背景 | `docs/archive/2026-09-10-epic-37-test-suite-flakiness/epic.md`：全套規模才出現、單檔重跑皆過的既有不穩定測試，已知集中在 `test/screens/reader_screen_test.dart`（PDF 畫線手勢）、`test/screens/remote_catalog_screen_test.dart`（遠端下載排隊，含 `[E]` did not complete）、`test/reader/pdf_reader_view_test.dart`；`docs/epics.md` epic-66 另記 `pdf_reader_view_filters_test` 偶發失敗（Issue 15）、`reader_screen_test` 在 Windows 整份中斷（Issue 19），以及 `127.0.0.1` 連線約 25% 被重設造成的測試不穩（Issue 11，見記憶）。 |

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **SQL 語意（spec §5、D16）**：計數 `WHERE font_family = ? OR heading_font_family = ?`（單一 `COUNT(*)`）；重置兩條 UPDATE 各自條件式，**不可合併成一條同時清兩欄**，也不可把重置寫成「先 SELECT 再逐列寫回」。
- **不改簽章**：`countBooksUsing(String)`、`deleteAndResetUsage(int, String)` 不變；呼叫端（`font_management_screen.dart`）不改。
- **不改文案、不改 l10n**：見上表評估；因此不需跑 `flutter gen-l10n`。
- **測試範圍（CLAUDE.md）**：Task 1～4 只跑觸及的測試檔；**完整 `flutter test`（無參數）只在 Task 5 跑一次**，該 Task 之後的文件改動不重跑。
- **每個 Task 結束都必須 commit，且該 commit 可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**（紅燈只存在於 Task 內部，不 commit；每個 Task 的測試與對應實作放在同一個 commit）。
- **Windows 環境**：Node 步驟用 PowerShell 工具；`node --version` 可執行即可（pnpm 內建 Node 24，必要時先把它前置於 PATH，見記憶 `reference_windows-node-via-pnpm`）。多數檔案是 CRLF：Edit 的 `old_string` 不要含換行；不對整個既有檔跑 `dart format`。
- **Git**：commit 訊息正體中文、**不加 `Co-Authored-By`**；分支 `feat/epic-68-heading-font`；`git add` 一律明確列檔，**絕不** `git add app`／`-A`／`.`，**絕不**加入 `.claude/settings.json` 或 `app/android/app/src/main/assets/foliate/legacy/` 下任何檔案（工作樹有 LF／CRLF 假 diff，不屬本張）。計畫與實作同分支同 PR，不另開文件分支。

## Review Focus

1. **兩條 UPDATE 各自條件式**：只清命中欄位；兩欄皆命中同時清；不相關書不受影響。→ Task 2 測試 a／b／c，反向驗證。
2. **計數每本只算一次**：主＋標題同字型的書算 1；不可是兩個 COUNT 相加。→ Task 1 測試，反向驗證。
3. **對話框書數涵蓋標題字型使用者**：以真實 repository＋真實 SQLite 的 widget 測試鎖定整條鏈（Fake 的書數是手動設定，無法證明這點）。→ Task 3。
4. **範圍**：`git diff 6b93d023..HEAD --stat -- app/lib` 只應出現 `custom_fonts_repository.dart`，不得出現 `font_management_screen.dart`、arb、資料庫檔。
5. **完整 `flutter test` 失敗的歸因**：只有「觸及檔案」或「Epic 68 新增／修改的測試」失敗才算與本 Epic 相關；其餘依 Task 5 的判斷流程處理。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/custom_fonts_repository.dart` | 修改 | `countBooksUsing` SQL；`deleteAndResetUsage` 第二條 UPDATE；更新兩個 doc comment |
| `app/test/reader/custom_fonts_repository_test.dart` | 修改 | 計數與重置新案例（既有兩案例保留） |
| `app/test/support/fake_custom_fonts_repository.dart` | 修改 | 只更新 doc comment（口徑涵蓋標題字型），不改邏輯 |
| `app/test/screens/font_management_screen_test.dart` | 修改 | 新增真實 repository 的對話框書數測試（標題字型使用者） |
| `docs/epics/epic-68-heading-font/issues.md`、`epic.md`、`docs/epics.md`、`CLAUDE.md` | 修改 | Epic 完成狀態；CLAUDE.md 最小更動 |

測試字串統一：`_book('b1')`…；字型家族 `'TargetFamily'`（被刪）、`'OtherFamily'`（另一款）、`'KeepFamily'`（無關書）。測試名稱末尾標註（epic-68 Issue 4）。

---

### Task 0：提交本計畫

**Files：** `docs/epics/epic-68-heading-font/plans/plan-issue-4.md`

- [x] **Step 1：** `git branch --show-current` 應為 `feat/epic-68-heading-font`。
- [x] **Step 2：** 只提交本計畫：
  ```bash
  git add docs/epics/epic-68-heading-font/plans/plan-issue-4.md
  git commit -m "docs(epic-68): Issue 4 刪除自訂字型連動實作計畫"
  ```

---

### Task 1：`countBooksUsing` 涵蓋主字型與標題字型

**Files：**
- 修改：`app/test/reader/custom_fonts_repository_test.dart`
- 修改：`app/lib/reader/custom_fonts_repository.dart`

- [x] **Step 1（紅，先寫測試）：** 在檔尾 `group('CustomFontsRepository')` 內、既有 `deleteAndResetUsage…` 測試之後新增（以字串定位；helper 沿用 `_book`）：
  1. `countBooksUsing 只有標題字型使用該字型的書也會計入（epic-68 Issue 4）`：b1 `{'font_family': 'OtherFamily', 'heading_font_family': 'TargetFamily'}`；b2 `{'font_family': null, 'heading_font_family': 'TargetFamily'}`；`expect(await repository.countBooksUsing('TargetFamily'), 2)`；`expect(await repository.countBooksUsing('OtherFamily'), 1)`（主字型端仍可正確計數）。
  2. `countBooksUsing 同一本書主字型與標題字型都用該字型只算一次（epic-68 Issue 4）`：b1 兩欄皆 `TargetFamily`；b2 只有主字型 `TargetFamily`；b3 只有標題字型 `TargetFamily`；b4 兩欄皆 `OtherFamily`、b5 兩欄皆 null（無關）；`expect(await repository.countBooksUsing('TargetFamily'), 3)`（不是 4）。
  3. `countBooksUsing 沒有任何書使用時回傳 0，且標題字型為 NULL 的列不被誤算（epic-68 Issue 4）`：b1 兩欄 null；`expect(await repository.countBooksUsing('TargetFamily'), 0)`。
- [x] **Step 2（確認紅）：**
  ```bash
  flutter test test/reader/custom_fonts_repository_test.dart --plain-name "countBooksUsing"
  ```
  預期：測試 1 失敗（得 0／1 而非 2）、測試 2 失敗（得 2 而非 3）；測試 3 與既有 `countBooksUsing 正確統計…` 為綠。
- [x] **Step 3（綠，實作）：** 修改 `custom_fonts_repository.dart` `countBooksUsing`（`old_string` 不含換行）：
  - SQL `'SELECT COUNT(*) AS c FROM book_reader_prefs WHERE font_family = ?'` → `'SELECT COUNT(*) AS c FROM book_reader_prefs WHERE font_family = ? OR heading_font_family = ?'`；`[familyName]` → `[familyName, familyName]`。
  - doc comment 改為：「統計 `book_reader_prefs` 中「主字型或標題字型」使用 [familyName] 的書籍數量（每本書只算一次，兩欄都用也只算一本；epic-68 起涵蓋標題字型），供刪除前的確認對話框文案使用。」
- [x] **Step 4（確認綠）：**
  ```bash
  flutter test test/reader/custom_fonts_repository_test.dart
  flutter analyze
  ```
  預期：整檔全綠（含既有兩個案例不動）；`No issues found!`。
- [x] **Step 5（反向驗證，不 commit）：** (a) 暫時把 SQL 改回只有 `WHERE font_family = ?`（`whereArgs` 同步改回單一）→ 測試 1、2 必紅；還原。(b) 暫時改寫為兩個 COUNT 相加（`(SELECT COUNT(*) … font_family = ?) + (SELECT COUNT(*) … heading_font_family = ?)`）→ 測試 2 必紅（得 4）；還原。`git diff -- app/lib` 確認只剩 Step 3 的改動。
- [x] **Step 6：** commit：
  ```bash
  git add app/lib/reader/custom_fonts_repository.dart app/test/reader/custom_fonts_repository_test.dart
  git commit -m "feat(epic-68): 自訂字型使用中書籍計數涵蓋標題字型，每本只算一次"
  ```

---

### Task 2：`deleteAndResetUsage` 只清命中欄位

**Files：**
- 修改：`app/test/reader/custom_fonts_repository_test.dart`
- 修改：`app/lib/reader/custom_fonts_repository.dart`

- [x] **Step 1（紅，先寫測試）：** 同一 group 內新增（每個測試先 `repository.insert` 一款 `TargetFamily` 字型取得 id，再插入 prefs 列；讀回用 `db.query('book_reader_prefs', where: 'book_id = ?', whereArgs: [...]).single`；可在 group 內加一個小 helper `Future<Map<String, Object?>> row(Database db, String bookId)`）：
  a. `刪除字型時，標題字型用該字型而主字型用另一字型 → 只清標題字型，主字型保留（epic-68 Issue 4）`：b1 `{'font_family': 'OtherFamily', 'heading_font_family': 'TargetFamily'}`；刪除後 `font_family == 'OtherFamily'`、`heading_font_family` isNull。
  b. `刪除字型時，主字型用該字型而標題字型用另一字型 → 只清主字型，標題字型保留（epic-68 Issue 4）`：b1 `{'font_family': 'TargetFamily', 'heading_font_family': 'OtherFamily'}`；刪除後 `font_family` isNull、`heading_font_family == 'OtherFamily'`。
  c. `刪除字型時，主字型與標題字型都用該字型 → 兩欄同時清為 NULL（epic-68 Issue 4）`：b1 兩欄皆 `TargetFamily`；刪除後兩欄皆 null。
  d. `刪除字型連動：多本書混合情境，無關書與其他欄位不受影響（epic-68 Issue 4）`：b1 只標題用 Target；b2 只主字型用 Target；b3 兩欄皆 `KeepFamily`；b4 `{'font_family': 'OtherFamily', 'heading_font_family': 'TargetFamily', 'font_size': 1.25}`（`font_size` 欄位名與型別以 `book_reader_prefs` 實際欄位為準，執行時先 `grep -n "font_size" lib/library/sqlite_library_repository.dart` 確認）；刪除後：b1 標題 null；b2 主字型 null；b3 兩欄仍 `KeepFamily`；b4 標題 null、主字型 `OtherFamily`、`font_size` 不變；`await repository.listAll()` isEmpty（字型已刪）。
  e. `刪除字型後 countBooksUsing 回傳 0（計數與重置口徑一致，epic-68 Issue 4）`：b1 只標題用、b2 只主字型用、b3 兩欄皆用；刪除前計數 3；刪除後 `countBooksUsing('TargetFamily')` 為 0。
- [x] **Step 2（確認紅）：**
  ```bash
  flutter test test/reader/custom_fonts_repository_test.dart --plain-name "deleteAndResetUsage"
  flutter test test/reader/custom_fonts_repository_test.dart --plain-name "刪除字型"
  ```
  預期：a、c、d、e 失敗（標題字型仍是 `TargetFamily`）；b 與既有 `deleteAndResetUsage 於同一交易內…` 為綠（主字型端本來就會清）。
- [x] **Step 3（綠，實作）：** 修改 `deleteAndResetUsage`：在既有主字型 `txn.update` 之後、交易結束前新增第二條（不要動既有那條）：
  ```dart
  // epic-68：標題字型同樣在該字型被刪除時重置為 NULL（跟隨主字型）。
  // 與上一條刻意分開、各自只比對自己的欄位：兩條合併成一條「同時清兩欄」會把
  // 「主字型用另一款字型」的書的主字型一併清掉（spec §5、D16）。
  await txn.update(
    'book_reader_prefs',
    {'heading_font_family': null},
    where: 'heading_font_family = ?',
    whereArgs: [familyName],
  );
  ```
  並把方法 doc comment 改為：「刪除字型並把所有使用中書籍的 `font_family`（主字型）與 `heading_font_family`（標題字型）中命中該字型的欄位各自重置為 `NULL`（FR-09 規則：刪除使用中字型時自動退回預設字型；標題字型 `NULL` 即跟隨主字型），於同一交易內完成避免中途失敗留下不一致狀態。兩欄各自條件式更新，只清命中的欄位。」
- [x] **Step 4（確認綠）：**
  ```bash
  flutter test test/reader/custom_fonts_repository_test.dart
  flutter analyze
  ```
  預期：整檔全綠；`No issues found!`。
- [x] **Step 5（反向驗證，不 commit）：** (a) 暫時把兩條 UPDATE 改成一條 `{'font_family': null, 'heading_font_family': null}` 搭配 `where: 'font_family = ? OR heading_font_family = ?'`、`whereArgs: [familyName, familyName]` → 測試 a、b、d 必紅（無關欄位被一併清掉）；還原。(b) 暫時刪掉第二條 UPDATE → 測試 a、c、d、e 必紅；還原。(c) 暫時把第二條 UPDATE 移到交易外（直接用 `_db.update`）不需驗證。`git diff -- app/lib` 確認只剩 Step 3 的改動。
- [x] **Step 6：** commit：
  ```bash
  git add app/lib/reader/custom_fonts_repository.dart app/test/reader/custom_fonts_repository_test.dart
  git commit -m "feat(epic-68): 刪除自訂字型時以兩條條件式更新分別重置主字型與標題字型"
  ```

---

### Task 3：Fake 口徑註解與對話框書數端到端測試

> Fake 沒有 `book_reader_prefs` 資料，無邏輯可同步，只更新 doc comment。對話框「書數涵蓋標題字型使用者」用**真實 repository＋記憶體 SQLite** 驗證整條鏈（Fake 的書數是測試手動設定，證明不了涵蓋標題字型）。本 Task 不改 `lib/`。

**Files：**
- 修改：`app/test/support/fake_custom_fonts_repository.dart`
- 修改：`app/test/screens/font_management_screen_test.dart`

- [x] **Step 1：Fake doc comment。** 把類別 doc 的「[countBooksUsing] 改由 [usageCounts] 手動設定回傳值」補一句：「計數口徑與真實 repository 相同——涵蓋主字型或標題字型使用該字型的書（每本只算一次，epic-68），Fake 不模擬資料，由測試自行把 `usageCounts` 設為預期的書數；SQL 層的口徑由 `test/reader/custom_fonts_repository_test.dart` 以真實 SQLite 驗證。」`usageCounts` 欄位 doc 同步一句即可。不動任何程式邏輯。（註：issues.md 驗收「fake 同語意」在此解讀為「Fake 的註解口徑同語意」，因 Fake 不碰資料庫、無欄位語意可同步；這是對驗收字面的調整解讀，已於審查處理紀錄與回報明寫，待人類確認。）
- [x] **Step 2（先寫測試）：** 在 `font_management_screen_test.dart` 新增 `group('刪除自訂字型連動標題字型（epic-68 Issue 4，真實 repository）')`：
  - 檔頭補 import：`package:sqflite_common_ffi/sqflite_ffi.dart`、`package:elinkbook/library/sqlite_library_repository.dart`、`package:elinkbook/reader/custom_fonts_repository.dart`、`package:elinkbook/library/models/book.dart`、`package:elinkbook/library/models/library_enums.dart`（只補實際用到者；`flutter analyze` 會抓多餘 import）。group 的 `setUpAll` 呼叫 `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`（比照 `library_screen_test.dart` 的寫法，先 `grep -n "sqfliteFfiInit" test/screens/library_screen_test.dart` 看其初始化位置與 `runAsync` 用法並沿用）。
  - 結構（審查 I-1 修訂，比照 `library_screen_test.dart` 第 72–109 行）：group 內以 `setUp`／`tearDown` 在 `testWidgets` 之外開關 `SqliteLibraryRepository.open(inMemoryDatabasePath)`，並於 `setUp` 預先 insert 字型、兩本書與 prefs 列（`runAsync` 內或 `setUp` 本身為真實非同步皆可，沿用該檔做法）。
  - 測試 `刪除對話框的書數涵蓋只把該字型設為標題字型的書，確認後兩欄命中皆被清除`：預先 `insert` 一款 `CustomFont(displayName: '標題用字型', familyName: 'HeadingOnlyFamily', fontUri: 'content://example/h')`；兩本書（`Book` 欄位比照 `custom_fonts_repository_test.dart` 的 `_book`，複製為檔內 helper）與其 prefs 列：b1 `{'font_family': 'SomeOtherFamily', 'heading_font_family': 'HeadingOnlyFamily'}`、b2 `{'font_family': 'HeadingOnlyFamily', 'heading_font_family': 'HeadingOnlyFamily'}`（共 2 本，其中一本主字型無關）。`pumpWidget` 建構 `FontManagementScreen(repository: realRepo)`（沿用該檔 `pumpScreen` 的 `MaterialApp` 設定，locale zh_TW）。
  - **等待一律用輪詢輔助函式，不用固定 delay**：`Future<void> pumpUntilFound(WidgetTester tester, Finder finder)`，迴圈（上限約 5 秒）`await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20))); await tester.pump();` 直到 `finder` 找到；逾時則 `fail`。`pumpWidget` 之後也要輪詢等 `_loadFonts` 完成（等「標題用字型」文字或 `font_management_delete_button_<id>` 出現），再點刪除鈕；點擊後輪詢等對話框文字 `目前有 2 本書使用此字型，刪除後將自動改用預設字型` 出現並斷言；點 `font_management_delete_confirm` 後輪詢等 `標題用字型` 消失；再以 `tester.runAsync` 讀回 b1、b2 的 prefs 列：b1 `font_family == 'SomeOtherFamily'`（主字型保留）且 `heading_font_family` null；b2 兩欄皆 null。
  - **不得放棄此測試**（審查 I-1）：若真實 SQLite 在 widget test 內確實無法穩定，停下並回報人類原因、取得同意後才可調整；驗收項不得由實作者自行刪除，也不得用 Fake 偽造結果。
- [x] **Step 3（確認）：**
  ```bash
  flutter test test/screens/font_management_screen_test.dart
  flutter test test/reader/custom_fonts_repository_test.dart
  flutter analyze
  ```
  預期：全綠（新測試一加入即應為綠，因 Task 1、2 已完成實作）；`No issues found!`。連跑新 group 3 次確認穩定：`flutter test test/screens/font_management_screen_test.dart --plain-name "標題字型" `重複三次皆過。
- [x] **Step 4（反向驗證，不 commit）：** 暫時把 `countBooksUsing` 的 SQL 改回只比對 `font_family`（Task 1 的反向驗證 (a) 作法）→ 新 widget 測試必紅（對話框書數變 1，找不到「目前有 2 本書…」）；再暫時刪掉 `deleteAndResetUsage` 的第二條 UPDATE → 新測試必紅（b1／b2 標題字型未被清）；還原。`git diff -- app/lib` 為空。
- [x] **Step 5：** commit：
  ```bash
  git add app/test/support/fake_custom_fonts_repository.dart app/test/screens/font_management_screen_test.dart
  git commit -m "test(epic-68): 補刪除自訂字型對話框書數涵蓋標題字型的端到端測試"
  ```

---

### Task 4：靜態檢查與 harness（只跑觸及檔，不跑完整 flutter test）

- [ ] **Step 1：範圍檢查。**
  ```bash
  git log --oneline -12
  git diff 6b93d023..HEAD --stat -- app/lib
  ```
  預期 `app/lib` 只有 `reader/custom_fonts_repository.dart`；不得出現 `font_management_screen.dart`、arb、`app_localizations*`、資料庫檔。
- [ ] **Step 2：靜態與慣例檢查（PowerShell）：**
  ```powershell
  cd C:\Users\fycdc\AI\elinkBook\app
  flutter analyze
  node tool/check_l10n_hardcoded_strings.js
  node tool/check_integration_keys.js
  ```
  預期：`No issues found!`；兩個腳本 PASS／exit 0。若 `check_l10n_hardcoded_strings.js` 抱怨新測試的 `MaterialApp` 缺 locale，補 `locale: const Locale('zh', 'TW')`（新 group 的 `MaterialApp` 已帶 locale，理論上不會出現）。
- [ ] **Step 3：harness 全場景（Epic 結尾回歸；本張未動 `main.js`，確認 Issue 2 的場景仍綠）：**
  ```powershell
  cd C:\Users\fycdc\AI\elinkBook\app\tool\foliate_touch_harness
  node run-all.mjs
  ```
  預期：全部 `[PASS]`，含 `scenario-heading-font.mjs` 的 A1、A2、A3、B、C、C2、D、D2。若環境缺 Chromium 或 puppeteer 導致場景無法啟動，記錄原因，不宣稱通過（與 Issue 2、3 的處理一致）。
- [ ] **Step 4：觸及測試檔彙整：**
  ```bash
  flutter test test/reader/custom_fonts_repository_test.dart test/screens/font_management_screen_test.dart
  ```
  預期全綠；記錄通過數。
- [ ] **Step 5：** 若 Step 2 因補 locale 而改檔，以明確列檔 commit：`fix(epic-68): 補測試 locale 以通過硬編碼字串檢查`；否則本 Task 無 commit。

---

### Task 5：完整 `flutter test`（無參數，Epic 內只跑這一次）

> 全專案測試逾 5,000 個（Epic 66 Issue 11 記錄 5118 個），耗時約 5 分鐘以上。**必須**以 `run_in_background` 執行或把 timeout 設到上限（600000ms），輸出導向檔案，避免截斷（Epic 37 的教訓：只留 `tail -40` 會遺失失敗清單）。

- [ ] **Step 1：** 確認工作樹只剩已知的 `.claude/settings.json` 與 `legacy/` 假 diff（`git status --short`），且 Task 1～4 皆已 commit。
- [ ] **Step 2：跑全套**（PowerShell，背景執行，完整輸出存 scratchpad 完整路徑 `C:\Users\fycdc\AppData\Local\Temp\claude\1b8a1974ed315139\c242f601-bb98-41eb-8e34-2b66cc11fc8f\scratchpad\epic68_full_test.log`，不要只留尾段）：
  ```powershell
  cd C:\Users\fycdc\AI\elinkBook\app
  flutter test --reporter expanded > "C:\Users\fycdc\AppData\Local\Temp\claude\1b8a1974ed315139\c242f601-bb98-41eb-8e34-2b66cc11fc8f\scratchpad\epic68_full_test.log" 2>&1
  ```
  以 `run_in_background: true` 啟動；完成時會收到通知，不輪詢。完成後：
  ```powershell
  Select-String -Path "C:\Users\fycdc\AppData\Local\Temp\claude\1b8a1974ed315139\c242f601-bb98-41eb-8e34-2b66cc11fc8f\scratchpad\epic68_full_test.log" -Pattern "All tests passed|Some tests failed|\[E\]" | Select-Object -Last 20
  ```
  記錄總數、通過數、失敗數與耗時。
- [ ] **Step 3：全數通過** → 把「全套通過、測試數、日期、commit hash」記進執行紀錄，進入 Task 6。
- [ ] **Step 4：有失敗時的判斷流程**（依序，不可跳過、不可直接宣稱不穩定）：
  1. **列出失敗清單**：從完整 log 取所有 `[E]` 測試名稱與所屬檔案（含 `did not complete`）。
  2. **歸屬判斷**：若失敗檔案是本 Epic 觸及的測試（`book_reader_prefs_test`、`sqlite_library_repository_test`、`daily_reading_stats_schema_test`、`dictionary_database_test`、`layout_preset*`、`resolved_preferences_test`、`reader_prefs_manager_test`、`library_screen_test`、`fxl_settings_sheet_test`、`pdf_settings_sheet_test`、`reader_settings_sheet_test`、`foliate_reader_view_test`、`foliate_legacy_assets_test`、`reader_screen_test`、`custom_fonts_repository_test`、`font_management_screen_test`、`arb_consistency_test`）→ **視為與本 Epic 相關**，先單檔重跑；仍失敗就是真問題，需修復（以 `superpowers:systematic-debugging` 查根因，修復後只重跑該檔並補跑受影響範圍；全套不重跑，於執行紀錄說明）。
  3. **單檔重跑**：對每個失敗檔案各單獨 `flutter test <檔案>` 跑 2 次。**單檔皆過**＝全套規模才出現的不穩定，進入第 4 步比對基準；**單檔也失敗**＝真失敗，回到第 2 點。
  4. **與 `main` 基準比對**：已知不穩定名單來自 `docs/archive/2026-09-10-epic-37-test-suite-flakiness/epic.md` 與 `docs/epics.md`（`reader_screen_test`（PDF 畫線手勢；Windows 整份中斷，epic-66 Issue 19）、`remote_catalog_screen_test`（下載排隊、`[E]` did not complete）、`pdf_reader_view_test`、`pdf_reader_view_filters_test`（epic-66 Issue 15）、涉及本機 loopback `127.0.0.1` 連線的測試（epic-66 Issue 11，連線被重設））。失敗**同時**屬於這些已知名單且單檔重跑皆過 → 記為「既有不穩定，與本 Epic 無關」，列出名稱、log 證據與單檔重跑結果。不在名單內的失敗 → 在乾淨的 `main` 基準（`git worktree add` 到暫存目錄，於其 `app/` 先 `flutter pub get` 再跑同一個失敗檔案；跑完 `git worktree remove`）比對：`main` 也失敗＝既有問題，通報並登記；`main` 不失敗而本分支失敗＝迴歸，必須修。
  5. **同一次全套只要還有未歸因的失敗，就不得進入 Task 6。** `reader_screen_test`（本 Epic 觸及）若在 Windows 整份中斷，先單檔重跑確認是否為 Issue 19 既有症狀；單檔重跑通過（326 個，Issue 3 實測）即可歸因，仍須在報告列證據。
  6. 修復後不重跑全套（Epic 規則：全套只跑一次）；以「失敗檔單檔全綠＋analyze 乾淨」作為修復驗證，並在執行紀錄與 PR 說明寫明全套的失敗與歸因結果。
- [ ] **Step 5：** 本 Task 無檔案變更，不 commit（若 Step 4 修復了程式則依該修復另開 commit，訊息 `fix(epic-68): …`）。

---

### Task 6：Epic 完成——文件狀態與 CLAUDE.md

> 狀態只更新為「全數完成，待歸檔」；**歸檔由人類指定，不要搬移目錄、不要改為 🟢**。備註遵守精簡原則（只寫結果與待辦，不寫逐項過程）。

- [ ] **Step 1：`issues.md`。** 表格 Issue 4 狀態改「完成（待 PR）」；並把說明段落中的「三張並非嚴格垂直切片」改為「四張並非嚴格垂直切片」，段落末補一句：「四張皆完成，Epic 全數完成，待歸檔（Issue 3 目視確認未完成，PR 前須人工補）。」
- [ ] **Step 2：`epic.md`。** 「進度」：
  - 把過時的「尚未拆 Issue（下一步：Scrum Master 階段寫 `issues.md`）。」改為「已拆 4 個 Issue（見 `issues.md`）。」
  - 新增一行 Issue 4 完成：「刪除自訂字型連動：`countBooksUsing` 數『主字型或標題字型用到該字型』的書（每本一次）、`deleteAndResetUsage` 兩條條件式 UPDATE 只清命中欄位（反向驗證：合併成一條會讓測試轉紅）、`FakeCustomFontsRepository` 只更新註解、對話框書數端到端測試；對話框文案不改（『改用預設字型』對僅作標題字型的書略不精確，待人類確認是否調整）；可下載字型刪除（ADR 0035）不碰偏好、Windows 同一條路徑，皆無需處理。完整 `flutter test` 結果：（填入 Task 5 結果，含已知不穩定歸因）。」
  - 新增一行總結：「Epic 全數完成，待歸檔。PR 前待辦：Issue 3 目視確認（見 `reports/issue-3-report.md`）。」
  - 頂端「狀態」維持 `🟡 開發中 (Active)`（尚未歸檔）。
- [ ] **Step 3：`docs/epics.md` 看板第 79 行（`epic-68-heading-font`）。** 狀態維持 🟡 開發中，備註由「Discovery 已定案（2026-11-14），`design.md` 已寫，尚未拆 Issue」改為精簡的：「Issue 1～4 全數完成，待歸檔」。其他 Epic 的列不動。
- [ ] **Step 4：`CLAUDE.md`（最小更動）。** 評估結果：Epic 68 新增了「書籍可另選標題字型」這個使用者可見的架構／行為事實，而 CLAUDE.md 第 107 行是唯一談及字型設定與刪除連動之處，且該句「刪除目前使用中的自訂字型時須自動退回預設字型」仍正確但未涵蓋標題字型。僅在該行末尾、緊接該句後補一句（以字串定位，`old_string` 取 `刪除目前使用中的自訂字型時須自動退回預設字型。`）：
  「書籍可另選「標題字型」（預設跟隨主字型，與主字型各自獨立）；刪除自訂字型時，主字型與標題字型各自命中才各自退回預設。」
  `version: 30`（CLAUDE.md、AGENTS.md）已於 Issue 1 完成，**核對即可，不再改**；AGENTS.md 無字型段落，不動。`docs/prd.md` 是否補一條 FR 屬產品文件決策，本張不改，列入待人類確認。
- [ ] **Step 5：commit（明確列檔，不含 `.claude/settings.json`）：**
  ```bash
  git add docs/epics/epic-68-heading-font/issues.md docs/epics/epic-68-heading-font/epic.md docs/epics.md CLAUDE.md
  git commit -m "docs(epic-68): Issue 4 收尾，Epic 全數完成待歸檔"
  ```
  commit 前 `git diff --cached --stat` 確認只有這四個檔，且 `CLAUDE.md` 僅第 107 行有異動、差異只是行尾追加（stat 會顯示該行 1 增 1 刪，屬正常）。
- [ ] **Step 6：** 程式審查（由獨立審查者產出，報告存 `docs/epics/epic-68-heading-font/reviews/review-code-issue-4.md`，依專案慣例審查先出報告、不直接修改；審查範圍建議涵蓋 Issue 4 全部 commit，並對 Epic 整體再做一次 `git diff main..HEAD --stat` 範圍檢查）。

## PR 前最終確認清單（Epic 最後一張；人工事項標註）

1. `git status --short` 只剩 `.claude/settings.json` 與 `legacy/` 假 diff；`git log main..HEAD` 無 `Co-Authored-By`、`.claude/settings.json` 與 `legacy/` 假 diff 檔未進任何 commit。
2. `git diff main..HEAD --stat -- app/lib` 的範圍與 Issue 1～4 預期一致（資料層、渲染層、UI＋l10n、`custom_fonts_repository.dart`；`legacy/main.js` 為 `pnpm build` 結果）。
3. `flutter analyze`：`No issues found!`。
4. `node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`：PASS；`node tool/check_foliate_es_compat.js` 於 Issue 2 已過，PR 前若 `main.js` 無新改動不需重跑。
5. 完整 `flutter test`：Task 5 結果已記錄，失敗（若有）皆已歸因；之後若又改了 `lib/`，僅重跑被觸及檔案，並在 PR 說明寫明。
6. harness `run-all.mjs` 全場景通過。
7. 資料層確認：`version: 30`、遷移 28→30／1→30／29→30 測試綠（Issue 1 已驗證，全套已涵蓋）。
8. **人工事項（無法由實作者代勞）**：(a) Issue 3 目視確認（`reports/issue-3-report.md` 11 項，目前結論為「未完成」）——須在真實 EPUB 上確認選標題字型後章名字形改變、改回「跟隨主字型」恢復、PDF／FXL 面板不出現下拉、兩個下拉左緣不齊是否可接受；(b) 刪除自訂字型後標題字型確實退回（可在目視確認時順便驗 Issue 3 報告第 8 項，Issue 4 完成後預期偏好已被重置）；(c) 對話框文案是否調整的決定；(d) 是否於 `docs/prd.md` 補 FR。
9. PR 說明寫明：全套測試結果與已知不穩定歸因、目視確認狀態、文案未改、Epic 歸檔待人類指定。**不要自行歸檔。**

## 完成標準

1. `countBooksUsing` 涵蓋主字型或標題字型使用者，每本只算一次（測試鎖定，反向驗證通過）。
2. `deleteAndResetUsage` 以兩條條件式 UPDATE 只清命中欄位；兩欄都命中同時清；無關書與其他欄位不受影響（測試鎖定，反向驗證通過）。
3. `FakeCustomFontsRepository` 註解反映新口徑；刪除確認對話框書數涵蓋標題字型使用者（真實 repository 的 widget 測試；或退路下的明載說明）。
4. 可下載字型刪除、Windows 路徑確認無需處理（已查證並記錄）。
5. `flutter analyze` 乾淨；兩支 node 檢查 PASS；harness `run-all` 通過；完整 `flutter test` 已跑且失敗皆歸因。
6. `issues.md`／`epic.md`／`docs/epics.md` 為「全數完成，待歸檔」；`CLAUDE.md` 僅新增一句；未歸檔。
7. 「程式審查」Step 保持未勾選。

## 風險與備註

- **對話框文案「改用預設字型」**：對僅作為標題字型的書略不精確（標題改為跟隨主字型，不是預設字型）。本計畫決定不改（改文案需動四份 arb＋`gen-l10n`＋斷言，且方向一致不致誤導）；列為待人類確認。若人類要求改，另開 commit：新增或調整 `fontManagementDeleteConfirmMessage` 文案於四份 arb（zh 與 zh_TW 須逐字相同、en 為英文），`flutter gen-l10n`，同步更新 `font_management_screen_test.dart` 現有三處文案斷言，並跑 `arb_consistency_test`、`check_l10n_hardcoded_strings.js`。
- **Fake 不模擬資料**：Fake 的計數是手動設定，因此「對話框涵蓋標題字型」只能靠真實 repository 的測試證明。Task 3 的 widget 測試在 widget test 內使用真實 SQLite，需要 `tester.runAsync` 等待；若不穩定，採 Task 3 的退路，不用 Fake 偽造。
- **`COUNT(*)` 與 `OR`**：`book_reader_prefs` 一書一列，`COUNT(*)` 加 `OR` 即為「每本只算一次」；若日後改成多列／多對多，這個前提需重新檢視。
- **`font_size` 欄位名**：Task 2 測試 d 的「其他欄位不受影響」斷言用到的欄位名與型別，執行時以 `book_reader_prefs` 實際建表欄位為準，找不到就改用任一既有的非字型欄位。
- **完整 `flutter test` 耗時與不穩定**：務必背景執行並保留完整 log；失敗的歸因流程見 Task 5 Step 4，不得以「應該是不穩定」帶過。
- **本機 `.claude/settings.json` 與 `legacy/` 假 diff**：工作樹既有，不屬本張，任何 `git add` 都不得包含。

## 審查處理紀錄

依 `reviews/review-plan-issue-4.md`（結論：小幅修訂）套用：
- I-1：Task 3 widget 測試改用 setUp／tearDown 開關記憶體 SQLite（比照 library_screen_test），所有真實 IO 等待（含 `pumpWidget` 後的 `_loadFonts`）改為輪詢輔助函式，不用固定 delay；退路刪除，改為「不得放棄，無法穩定須停下回報」。
- M-1：測試 e 改名含「刪除字型」，使 `--plain-name "刪除字型"` 跑得到。
- M-2：「fake 同語意」僅更新註解，明寫為對驗收字面的調整解讀（Fake 無資料可連動），待人類確認。
- M-3：移除 `<…>` 角括號，直接寫 `6b93d023`。
- M-4：Task 5 log 統一存 scratchpad 完整路徑；main 基準 worktree 補 `flutter pub get`。
- M-5／M-6：CLAUDE.md 追加句縮短，不含欄位名與 epic 引用，只述架構事實；diff 預期改為行尾追加。
- M-7：issues.md「三張」改「四張」。
- docs/epics.md 備註精簡為「Issue 1～4 全數完成，待歸檔」。

## 執行紀錄

（執行時填寫：各 Task 紅燈／綠燈測試數、反向驗證結果、完整 `flutter test` 的總數／失敗數／歸因。）

### 程式審查後處理

（程式審查後填寫。）
