# Issue 1：首行縮排實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 版面設定新增「首行縮排」：一個開關加字數滑桿（0～4 字，每次 0.5 字，開啟預設 2 字），套用到 Foliate 流式格式（EPUB／TXT／MD／KF8）的所有段落；單書偏好，含版面預設集。

**Architecture：** 比照既有「段距」欄位走同一條路：`BookReaderPrefs.firstLineIndent`（`double?`，單位 em，`null`＝關閉）→ `ResolvedPreferences` → `FoliateReaderView` 組 map → `main.js` 加 `p { text-indent: Nem !important; }`。SQLite 版本 28→29 新增 `first_line_indent REAL`。「版面預設集」JSON 走同一組 `toMap`／`fromMap`，欄位不存在時讀成 `null`。設定面板「文字」分頁新增開關與滑桿。

**Tech Stack：** Flutter／Dart、`sqflite`、foliate-js（`main.js`）、`flutter_test`、`flutter gen-l10n`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-65-reader-indent-and-colors/epic.md`「Discovery 決策」（決策 1～4、11、12）。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **欄位語意**：`firstLineIndent == null`＝關閉（維持書本原本縮排，不產生任何 CSS）；`>= 0` 的值＝強制 `text-indent: Nem !important`（`0` 會把書本縮排清掉，是合法值）。
- **單位**：em，範圍 0～4，每次 0.5；滑桿與 +/- 按鈕都以 0.5 為步進。
- **只套用 Foliate 流式格式**（EPUB／TXT／MD／KF8）；PDF、固定版面（FXL）、CBZ 不套用、不顯示控制項（FXL／PDF 有各自的設定面板，不加）。
- **套用到所有 `p`**，不排除置中、空白、只含圖片的段落（決策 3）；不受「停用書本 CSS」影響（`!important`）；直排時 `text-indent` 自然往下縮，不分支處理。
- **整列重建的地方都要補欄位**（`epic-57` 教訓）：`BookReaderPrefs.reflowableEpubFields()`、`ReaderSettingsSheet._currentDraft`、`library_screen.dart` 版面覆寫 `_save()` 的 `BookReaderPrefs(...)`、`fxl_settings_sheet.dart` 的 `BookReaderPrefs(...)`。漏補會在儲存時把此欄位靜默清空。
- **資料庫升級**：版本 28→29，升級函式比照 `_addPdfPageTurnModeColumn`（表存在才 `ALTER TABLE`），且放在 `oldVersion >= 2` 的 else 分支內；`_createBookReaderPrefsTable` 一步到位含新欄位；`CLAUDE.md` 內提到的「主庫 `version: 28`」同步改為 29。
- **l10n**：新字串同時加進 4 個 `.arb`（`app_en`、`app_zh`、`app_zh_CN` 簡體、`app_zh_TW`），執行 `flutter gen-l10n`，生成檔進版控；不得硬編碼中文。
- **測試原則**：既有案例全部保留；`test/support/full_book_reader_prefs.dart`（全欄位非 null 範本）要補新欄位。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，只跑一個）。
- **每個 Task／commit 結束都必須可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**。
- **提交前**：`flutter analyze` 必須 "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`（本機 nvm 沒裝 Node 則無法執行，記錄在 `epic.md`；本張新增使用者可見字串，風險要寫清楚）。`main.js` 的 Node 測試台（`app/tool/foliate_touch_harness/`）同樣跑不了，改以 Dart 端字串／map 測試補強並在 WAVE 實測。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔；不要對整個既有檔案跑 `dart format`；`git add` 一律明確列檔，**不得** `git add app`（會夾帶使用者擱置的 `app/android/gradle.properties`）。
- **Commit**：不加 `Co-Authored-By`；結尾加 `Claude-Session: https://claude.ai/code/session_019bmfxQJ1gaKoHGoWH7gJwD`。每個 Task 一個 commit。
- **不要提交** `app/android/gradle.properties`。
- **計畫與實作同分支同 PR**，不另開文件分支。

## Review Focus

1. **整列重建漏欄位。** 四個重建點（見 Global Constraints）任何一個漏掉，儲存時就清空縮排。→ 每個重建點各一個保留欄位的測試。
2. **舊資料相容。** 舊的單書偏好列、舊的版面預設集 JSON 沒有此欄位，必須讀成 `null`，不崩潰。→ 資料庫升級測試與 `fromMap` 缺鍵測試。
3. **資料庫升級重複 `ALTER TABLE`。** 全新安裝（`onCreate`）與 v1 升級路徑不得重複加欄位。→ 比照 `_addPdfPageTurnModeColumn` 與 else 分支寫法，升級測試涵蓋從 v28 與從更舊版本。
4. **`0` 與 `null` 混淆。** `0` 是「縮排 0 字（清掉書本縮排）」，`null` 才是「關閉」。→ `toMap`／`copyWith`／面板各有測試；注意 `copyWith` 的 `newValue ?? this.value` 語意無法把欄位清成 `null`，關閉開關要走整列重建（`_currentDraft`）。
5. **重畫觸發。** `FoliateReaderView.didUpdateWidget` 比較清單沒包含新欄位，改縮排畫面不會更新。→ `foliate_reader_view_test` 補測。
6. **預設集污染。** 固定版面來源書的預設集套用到流式書時，縮排欄位的去留。→ `reflowableEpubFields()` 保留此欄位並有測試。
7. **面板重設。** 「全部重設為書本預設」要把縮排一併關閉，`isActive` 判斷要含縮排。→ 面板測試。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/book_reader_prefs.dart` | 修改 | 新欄位、`toMap`／`fromMap`／`==`／`hashCode`／`copyWith`／`reflowableEpubFields` |
| `app/lib/library/sqlite_library_repository.dart` | 修改 | 版本 29、`_addFirstLineIndentColumn`、建表加欄位 |
| `app/lib/reader/resolved_preferences.dart`、`reader_prefs_manager_impl.dart` | 修改 | `ResolvedPreferences.firstLineIndent` 與 `resolve` |
| `app/lib/reader/foliate_reader_view.dart` | 修改 | widget 欄位、map、`didUpdateWidget` 比較 |
| `app/lib/screens/reader_screen.dart` | 修改 | 傳 `resolved.firstLineIndent` |
| `app/android/app/src/main/assets/foliate/main.js` | 修改 | `text-indent` 規則 |
| `app/lib/screens/reader_settings_sheet.dart` | 修改 | 開關、滑桿、`_currentDraft`、重設 |
| `app/lib/screens/library_screen.dart`、`fxl_settings_sheet.dart` | 修改 | 整列重建補欄位 |
| `app/lib/l10n/*.arb` 與生成檔 | 修改／重新產生 | 新字串 |
| `app/test/...` | 修改 | 見各 Task |
| `CLAUDE.md`、`docs/prd.md` | 修改 | 資料庫版本、版面控制項描述 |
| `CONTEXT.md` | 已更新 | 「首行縮排」詞條已於 Epic 登錄時加入 |

---

### Task 0：提交設計文件與計畫

- [x] **Step 1：** 分支 `epic-65/issue-1-first-line-indent`（已從 `main` 建立）。
- [x] **Step 2：** 提交 Epic 登錄文件（`epic.md`、`issues.md`、`docs/epics.md`、`.gitignore`、`CONTEXT.md`）。
- [x] **Step 3：** 提交本計畫（純文件）。不提交 `app/android/gradle.properties`。

### Task 1：資料層（模型、資料庫、解析）

**Files：** `book_reader_prefs.dart`、`sqlite_library_repository.dart`、`resolved_preferences.dart`、`reader_prefs_manager_impl.dart`、`test/support/full_book_reader_prefs.dart`，以及 `test/reader/book_reader_prefs_test.dart`、`test/library/sqlite_library_repository_test.dart`、`test/reader/resolved_preferences_test.dart`、`test/reader/reader_prefs_manager_test.dart`。

- [ ] **Step 1（紅）：** 先寫測試、確認失敗（編譯失敗即紅燈）：
  - `book_reader_prefs_test`：`firstLineIndent` 往返（有值、`0`、`null`）；`fromMap` 缺 `first_line_indent` 鍵讀成 `null`；`==`／`hashCode` 納入新欄位；`copyWith(firstLineIndent: 1.5)`；`reflowableEpubFields()` 保留新欄位。
  - `sqlite_library_repository_test`：全新安裝建表含 `first_line_indent`；從 v28 升級後既有列保留、新欄位為 `null`；從更舊版本（例如 v2 或 v27）升級不重複加欄位；寫入與讀回單書偏好含縮排。
  - `resolved_preferences_test`／`reader_prefs_manager_test`：`resolve` 把 `book.firstLineIndent` 帶到 `ResolvedPreferences.firstLineIndent`；`null` 維持 `null`。
  - 版面預設集：儲存含縮排的預設集再讀回，欄位保留；舊 JSON（無該鍵）讀成 `null`（找既有預設集測試檔，沿用其寫法）。
- [ ] **Step 2（綠）：** 實作：
  - `BookReaderPrefs`：欄位 `final double? firstLineIndent;`（doc 註解寫明語意與範圍）、建構子、`toMap` 鍵 `first_line_indent`、`fromMap`、`==`、`hashCode`、`copyWith`、`reflowableEpubFields()`。
  - `sqlite_library_repository.dart`：版本 28→29；新增 `_addFirstLineIndentColumn(db)`（比照 `_addPdfPageTurnModeColumn`）；`onUpgrade` 的 else 分支加 `if (oldVersion < 29)`；`_createBookReaderPrefsTable` 加 `first_line_indent REAL`。
  - `ResolvedPreferences` 新欄位與建構子；`ReaderPrefsManagerImpl.resolve` 帶入。
  - `test/support/full_book_reader_prefs.dart` 補新欄位（非 null 範本）。
- [ ] **Step 3：** `flutter analyze`；跑 Step 1 列出的四個測試檔與預設集相關測試檔；commit（明確列檔）。

### Task 2：Foliate 管線（view、reader_screen、main.js）

**Files：** `foliate_reader_view.dart`、`reader_screen.dart`、`main.js`、`test/reader/foliate_reader_view_test.dart`。

- [ ] **Step 1：** 先讀 `main.js` 約 160～260 行與 `foliate_reader_view.dart` 約 150～215 行，確認 `paragraphSpacing` 的加入點與 `didUpdateWidget` 比較清單。
- [ ] **Step 2（紅）：** `foliate_reader_view_test` 補測：`firstLineIndent` 非 null 時 map 含 `firstLineIndent`；`null` 時不含；`didUpdateWidget` 比較在 `firstLineIndent` 改變時視為需要重送偏好（比照段距既有測試）。
- [ ] **Step 3（綠）：** 實作：
  - `FoliateReaderView` 新欄位 `firstLineIndent`、建構子、map 鍵、比較清單。
  - `reader_screen.dart`：`FoliateReaderView(...)` 傳 `firstLineIndent: resolved.firstLineIndent`（緊接 `paragraphSpacing`）。
  - `main.js`：在 `paragraphSpacing` 規則之後加 `if (typeof prefs.firstLineIndent === 'number') { rules.push(`p { text-indent: ${prefs.firstLineIndent}em !important; }`) }`，附註解說明 `0` 的語意、直排自然往下縮、與 `publisherStyles` 無關。
- [ ] **Step 4：** `flutter analyze`；跑 `foliate_reader_view_test.dart`、`reader_screen_test.dart --plain-name` 與偏好相關關鍵字各一次（分次跑）；commit。

### Task 3：設定面板與整列重建點

**Files：** `reader_settings_sheet.dart`、`library_screen.dart`、`fxl_settings_sheet.dart`、4 個 `.arb` 與生成檔、`test/screens/reader_settings_sheet_test.dart`、`test/screens/library_screen_test.dart`、`test/screens/fxl_settings_sheet_test.dart`（找實際存在的檔名）。

- [ ] **Step 1：** l10n。新增字串（4 個 `.arb` 都加，`app_zh_CN` 用簡體）：`readerSettingsFirstLineIndentLabel`（「首行縮排」）、`readerSettingsFirstLineIndentValue`（帶 `{count}` 參數，zh：`{count} 字`；en：`{count} em`）。執行 `flutter gen-l10n`，確認只有預期差異。
- [ ] **Step 2（紅）：** 面板與重建點測試：
  - 面板「文字」分頁有 `Key('reader_settings_first_line_indent_switch')` 開關與 `reader_settings_first_line_indent` 滑桿列；初始 `prefs.firstLineIndent == null` 時開關為關、滑桿停用。
  - 打開開關：`onChanged` 收到 `firstLineIndent == 2.0`；滑桿範圍 0～4、步進 0.5、+/- 按鈕各改 0.5。
  - 滑桿拉到 `0`：`onChanged` 收到 `0.0`（不是 `null`）。
  - 關閉開關：`onChanged` 收到 `firstLineIndent == null`，其他欄位不變。
  - 「全部重設為書本預設」：縮排開著時按下，`firstLineIndent` 變 `null`；`isActive` 判斷含縮排。
  - 其他欄位被修改時，`_currentDraft` 保留既有縮排值。
  - `library_screen` 版面覆寫儲存：既有書籍有縮排時，儲存後縮排保留。
  - `fxl_settings_sheet`：帶縮排值的 prefs 經過它的 `onChanged` 後縮排保留。
  - E-Ink 模式：縮排滑桿列使用步進器（沿用 `_buildSliderRow` 的既有行為，測一次即可）。
- [ ] **Step 3（綠）：** 實作：
  - `reader_settings_sheet.dart`：狀態 `_firstLineIndent`（預設 `2.0`）與 `_firstLineIndentOn`；`initState`／`didUpdateWidget` 由 `widget.prefs.firstLineIndent` 還原；`_currentDraft` 帶入（開關關閉時為 `null`，開啟時為 `_firstLineIndent`）；在段距滑桿之後加 `SwitchListTile`（Key 如上）與 `_buildSliderRow`（`min: 0, max: 4, step: 0.5`，`displayValue` 用 `readerSettingsFirstLineIndentValue`，開關關閉時滑桿列停用或半透明）；「全部重設」把開關關閉。
  - `library_screen.dart` 約 1922 行與 `fxl_settings_sheet.dart` 約 66 行的 `BookReaderPrefs(...)`：補 `firstLineIndent: existing.firstLineIndent` / `widget.prefs.firstLineIndent`。
- [ ] **Step 4：** `flutter analyze`；跑上述測試檔；`reader_screen_test.dart` 整份跑一次；commit。

### Task 4：收尾

- [ ] **Step 1：** `CLAUDE.md` 內主庫版本描述 `version: 28` 改為 `version: 29`；`docs/prd.md` 版面控制項描述補「首行縮排」一項（先讀原句再做最小修改）；`epic.md` 開發記錄；`issues.md` Issue 1 狀態；`docs/epics.md` 備註同步。
- [ ] **Step 2：** 驗收：`grep -rn "firstLineIndent\|first_line_indent" app/lib` 涵蓋模型、資料庫、解析、view、reader_screen、面板、兩個重建點；`git diff main --stat -- app/lib` 沒有預期外的檔案。
- [ ] **Step 3：** `flutter analyze`；兩個 `check_*.js`（沒有 Node 則記錄未執行）；完整 `flutter test`（`run_in_background`，只跑一個）。
- [ ] **Step 4：** 程式審查（報告存 `reviews/review-code-issue-1.md`，不進版控）。
- [ ] **Step 5：** WAVE 真機抽驗：(1) 開一本 EPUB 橫排，版面設定「文字」分頁打開首行縮排，段落首行縮 2 字；(2) 拖滑桿到 0、1、4，縮排即時變化，0 時書本原有縮排消失；(3) 關閉開關，書本恢復原貌；(4) 直排書重做一次，縮排往下；(5) 離開重開，設定保留；(6) 開一本 TXT 重做一次；(7) 開一本有置中段落的書，記錄置中段落是否被縮排（決策 3 的已知取捨，結果寫入 `epic.md`）；(8) 開 PDF，確認沒有縮排控制項。
- [ ] **Step 6：** 開 PR；PR 開出後把 Issue 1 狀態同步。
