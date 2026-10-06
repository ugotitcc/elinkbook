# Issue 17：integration 測試遷移到 Epic 38 後的介面 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 把 Issue 16 真機驗證後仍失敗的 18 個 `integration_test/` 檔案，遷移到 Epic 38 之後的閱讀器介面，並加上「過期 key 守衛」，讓這批測試不會再無聲壞掉。

**Architecture：** 先加一支 Node 守衛腳本（比照 Issue 15 的 `check_l10n_hardcoded_strings.js`），自動找出 integration 測試引用但 `lib/` 已不存在的 `Key`。再依失敗性質分五組遷移：頁碼文字、頁首／AppBar、筆記與書籤、設定面板與進度、行為待判斷。每組先查現行介面、再改測試、最後在 `TCL 14` 真機驗證。**只改測試與 `tool/`，不改 `lib/`。** 遇到「過期還是行為真的改變」，一律先停下來問使用者。

**Tech Stack：** Flutter／Dart、`integration_test`、Node（守衛腳本與其單元測試）、`adb`。指令一律在 `app/` 目錄下執行（除非另有標明）。

**Spec：** 沒有獨立 `spec.md`。缺陷描述與分類表見 `docs/epics/epic-54-architecture-optimization/issues.md` Issue 17 與 `epic.md`「Issue 16 實作完成與真機驗證結果」；前一張工單的做法見 `plans/plan-issue-16.md`；Epic 38 的介面設計見 `docs/archive/` 內 `epic-38-reader-chrome-tts-redesign`。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **不改 `lib/`**：任何需要改 `lib/` 才能讓測試通過的情況，一律停下來回報（見「過期或真缺陷」判定規則）。
- **不放寬測試**：不得為了通過而刪斷言、加 `skip`、把 `findsOneWidget` 改成 `findsWidgets`、把等式改成「非 null」。舊斷言對應的新介面存在時，換成**同等強度**的新斷言。
- **逾時秒數不調大**：Issue 16 已證明等待時間不是根因（H1 不成立）。
- **真機**：`TCL 14`（序號 `3CEF42ECD491687`，Android 15）。第一次執行前先確認 adb 延遲（見 Task 0），並向使用者確認可清除該裝置上的 `cc.ugotit.elinkbook` 資料。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試。完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，`run_in_background`，必須在 `app/` 下）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：用 Bash 工具（Git Bash）。`python` 不可用。多數原始檔是 CRLF，`Edit` 的定位字串不要含換行；批次替換用 `sed -i` 或 Node。一次性腳本放 worktree 根目錄 `.scratch/`（untracked）。提交一律用明確路徑 `git add`，不用 `git add -A`。Git Bash 會把 `/data/...` 轉成 Windows 路徑，adb 指令前先 `export MSYS_NO_PATHCONV=1`。
- **adb**：若 `adb shell echo hi` 超過 1 秒，先 `adb kill-server` 再 `adb start-server`（Issue 16 發現舊 adb 服務會讓每個指令多等 12～23 秒、推送降到 0.1 MB/s）。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：計畫先審查再動手；程式審查先出報告（存於 `reviews/`，gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。

## 現行介面對照表（Issue 17 的事實基礎，已對照 `lib/` 查證）

| 舊參照（integration 測試仍在用） | 現行介面 | 出處 |
|---|---|---|
| `find.byType(AppBar)`、`reader_appbar_*` | 沒有 `AppBar`。頂部列是 `ReaderChromeTopBar`（不是 `Scaffold.appBar`）；工具列可見時有 `reader_chrome_back_button`，標題 `reader_chrome_title` 因 `chapterTitle` 恆為空字串而**不會出現** | `lib/screens/reader_chrome_top_bar.dart`、`reader_screen.dart:2386` |
| `reader_appbar_chapter_title`（EPUB 頁首章節名） | `reader_foliate_header_text`（顯示條件與 `showHeader` 偏好有關，見 `reader_screen.dart:2880` 附近） | `reader_screen.dart:3016` |
| `reader_appbar_static_title`（「閱讀器」靜態標題） | 無對應 | — |
| 頁尾文字 `進度 N% ｜ 第 x/y 頁` | `reader_chrome_page_info_text`，格式 `'$current / $total · $percent%'`，例如 `1 / 6 · 17%`（PDF 與 Foliate 同格式） | `reader_screen.dart:2283`、`reader_chrome_bottom_bar.dart:147` |
| `reader_footer_progress_text` | 仍存在，格式 `'4/6'`（無百分比） | `reader_footer.dart:119` |
| `reader_foliate_progress_text` | 仍存在，格式 `'4/6'`（角落浮動文字） | `reader_screen.dart:3044` |
| `reader_foliate_progress_button` | **已刪除**（只剩一行過期註解）；`reader_footer`、`reader_footer_jump_input`、`reader_footer_jump_slider` 仍在 | `reader_footer.dart` |
| `reader_fixed_layout_back_button` | `reader_chrome_back_button` | `reader_chrome_top_bar.dart:108` |
| `reader_fixed_layout_notes_button`、`reader_pdf_notes_button` | `reader_chrome_annotations_button` | `reader_chrome_bottom_bar.dart:195` |
| `reader_pdf_settings_button` | `reader_chrome_layout_button`（FXL 與 PDF 皆走 `onLayoutTap`） | `reader_chrome_bottom_bar.dart:206` |
| `tester.widget<TextButton>(notes_sheet_export_markdown)` | 該元件是 `IconButton` | `notes_bottom_sheet.dart:208` |
| `tester.widget<IconButton>(reader_settings_column_mode_*)` 等 | key 仍在，格式 `reader_settings_column_mode_$keySuffix`（`auto`／`single`／`double`），但元件改為 `EBOptionChipGroup` 的 `EBOptionChipItem` | `reader_settings_sheet.dart:622`、`screens/widgets/eb_option_chip_group.dart` |
| `notes_sheet_annotation_delete_h<高亮id>_n<筆記id>` | key 組成沒變（`item.key = 'h${highlight?.id}_n${note?.id}'`），**元件存在**。底部工具列的 `reader_chrome_annotations_button` 開面板時傳 `initialTabIndex: 1`（開在「劃線與備註」分頁，`reader_screen.dart:2440,2870`），所以清單就在眼前；`NotesBottomSheet` 建構子預設值 `0`（書籤）只在其他呼叫端生效。失敗原因待查（Task 4 Step 4） | `notes_bottom_sheet.dart:100,514`、`reader_screen.dart:2440` |
| `notes_sheet_bookmark_toggle` | 元件存在（`OutlinedButton.icon`），但在「書籤」分頁；工具列開面板預設停在「劃線與備註」分頁，所以點它之前**必須先點 `notes_sheet_tab_bookmarks`** | `notes_bottom_sheet.dart:223,259`、`reader_screen.dart:2440` |
| `find.text('閱讀器')`（`library_screen_test.dart:128`，進入閱讀器後的靜態標題） | 無對應；進入閱讀器後可用 `reader_chrome_back_button` 判斷閱讀器頂部列已出現 | `reader_chrome_top_bar.dart:108` |
| `find.byType(AppBar)`（`volume_key_test.dart:135`） | 同上，`reader_chrome_back_button` | `reader_chrome_top_bar.dart:108` |
| `find.textContaining('第 N/')`、`_pumpUntilTextFound(tester, '第 N/')`（`volume_key_test.dart:114,131,133,138,140`） | 頁碼格式改為 `'N / total · pct%'`，改以 `pageInfoText()` 判斷 | `reader_screen.dart:2283` |

動態 key 不是過期：`nav_zone_$index`、`reader_settings_*_$keySuffix`、`notes_sheet_annotation_delete_${item.key}` 等，守衛腳本會用範本比對，不會誤報。

## 「過期或真缺陷」判定規則（每個失敗都要走一遍）

1. 失敗訊息指向的 key／文字／元件型別，在 `lib/` 找得到對應 → **過期**，換成同等強度的新斷言。
2. 找不到對應，但 `lib/` 有明確註解或 Epic 38 設計說明該功能已搬到別處 → **過期**，換成新位置的斷言。
3. 找不到對應，**也沒有說明** → **停止，回報使用者**，列出：舊斷言在驗證什麼、新介面是否仍有這個行為、建議（刪、改、或視為產品缺陷）。
4. 舊斷言換成新斷言後**強度變弱**（例如「文字等於 X」變成「元件不存在」）→ **停止，回報使用者**。
5. 懷疑產品缺陷（行為與舊測試、設計文件都不符）→ **停止，回報使用者**，不改 `lib/`，不改斷言。

## Review Focus

最可能咬到使用者的情況，依可能性排序：

1. **換成更弱的斷言讓測試變綠，掩蓋真缺陷。** → 判定規則第 4 條；每個 Task 的最後一步列出「斷言強度變化」。
2. **新 key 找得到，但元件在工具列收合時不存在，測試偶爾過、偶爾不過。** → `reader_chrome_*` 只在 `_chromeVisible` 為真時存在（預設為真）。凡是「點過 `ZoneAction.menu`」或 FXL 換頁（會強制收合）之後再找工具列 key 的測試，Task 2～5 都明確標示並在步驟裡處理。
3. **守衛腳本誤報動態 key，或被 lib/ 內無關的字串範本癱瘓、漏掉真的過期 key（對現況永遠 PASS）。** → Task 1：單元測試涵蓋動態範本、`keyPrefix`、雙引號、測試檔自建 key、測試端迴圈 key，並有專門案例餵入多語系產生檔那種 `$_temp0` 與 `${x}%` 之類的萬用範本，要求仍然抓得到過期 key；Step 5 要求對現況**剛好**回報 7 個 key、22 處，輸出 `PASS` 即視為守衛失效。
4. **只在 `TCL 14` 通過，換裝置就失敗。** → 本 Issue 的驗收裝置只有 `TCL 14`，結果寫進 `epic.md` 時註明裝置與 WebView 版本；不宣稱其他裝置通過。
5. **為了讓檔案過關而改了等待上限。** → Global Constraints 明令不調逾時。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/tool/check_integration_keys.js` | 新增 | 守衛：找出 `integration_test/` 引用但 `lib/` 不存在的 `Key` |
| `app/tool/test_check_integration_keys.mjs` | 新增 | 守衛的單元測試 |
| `app/tool/README.md` | 修改 | 文件化守衛 |
| `app/test/support/reader_chrome_finders.dart` | 新增 | 共用的頁碼文字讀取函式 `pageInfoText()`，供 3 個 integration 測試使用 |
| `app/integration_test/*.dart`（18 個） | 修改 | 遷移到現行介面 |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 結果與狀態 |

## 18 個檔案與分組

| 組 | Task | 檔案 | Issue 16 基準失敗 |
|---|---|---|---|
| A 頁碼文字 | 2 | `reader_footer_test`、`reading_position_test`、`volume_key_test` | 找不到 `進度 N% ｜ 第 x/y 頁`／`第 1/` |
| B 頁首／AppBar | 3 | `pdf_nav_zone_test`、`reader_header_footer_toggle_test` | 找不到 `AppBar`、`reader_appbar_*` |
| C 筆記與書籤 | 4 | `epub_highlights_notes_test`、`pdf_highlights_notes_test`、`notes_bookmark_test`、`markdown_export_test`、`fxl_bookmarks_test` | 面板分頁、舊 key、`TextButton` 轉型 |
| D 設定面板與進度 | 5 | `foliate_single_column_test`、`reader_screen_test`、`epub_pagination_test` | `IconButton` 轉型、設定面板 key、`reader_foliate_progress_button` |
| E 行為待判斷 | 6 | `epub_toc_test`、`epub_fxl_tap_zone_test`、`foliate_toc_footer_test`、`foliate_epub_reader_view_test` | 斷言與實際行為不符 |
| F 既存 | 7 | `library_screen_test` | 找不到 `book_item_…`（base 同樣失敗） |

---

### Task 0：提交計畫、建立 worktree、確認裝置

**Files：**
- Commit：本計畫檔（在 `main`，純文件）
- 建立 worktree：`.worktrees/epic-54-issue-17-integration-migrate`

- [x] **Step 1：提交計畫（在 `main`）**

```bash
git add docs/epics/epic-54-architecture-optimization/plans/plan-issue-17.md
git commit -m "docs(epic-54): Issue 17 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [x] **Step 2：建立 worktree 與分支**

```bash
git worktree add .worktrees/epic-54-issue-17-integration-migrate -b epic-54/issue-17-integration-migrate
mkdir -p .worktrees/epic-54-issue-17-integration-migrate/.scratch/baseline
cd .worktrees/epic-54-issue-17-integration-migrate/app && flutter pub get
```

之後所有指令都在這個 worktree 的 `app/` 下執行。

- [x] **Step 3：確認裝置與 adb 延遲**

```bash
export MSYS_NO_PATHCONV=1
adb devices -l
time adb -s 3CEF42ECD491687 shell echo hi
```

序號後面必須是 `device`。`echo hi` 超過 1 秒就執行 `adb kill-server && adb start-server`，重新授權後再量一次，直到小於 1 秒。**向使用者確認：** 可以清除 `TCL 14` 上既有的 `cc.ugotit.elinkbook` 資料嗎？得到明確回答前，不得執行任何 `flutter test integration_test/…`。

- [x] **Step 4：記錄基準**

```bash
OUT=../.scratch/baseline; : > $OUT/summary.txt
for n in epub_toc_test epub_highlights_notes_test pdf_highlights_notes_test notes_bookmark_test markdown_export_test fxl_bookmarks_test foliate_single_column_test reader_screen_test epub_pagination_test reader_footer_test reading_position_test volume_key_test pdf_nav_zone_test reader_header_footer_toggle_test epub_fxl_tap_zone_test foliate_toc_footer_test foliate_epub_reader_view_test library_screen_test; do
  timeout 500 flutter test integration_test/$n.dart -d 3CEF42ECD491687 > $OUT/$n.log 2>&1
  echo "== $n exit=$? $(grep -E '^[0-9:]+ \+[0-9]+( -[0-9]+)?:' $OUT/$n.log | tail -1 | grep -oE '\+[0-9]+( -[0-9]+)?')" >> $OUT/summary.txt
done
cat $OUT/summary.txt
```

預期（Issue 17 規劃時在同一台裝置量到的結果）：18 個檔案全部 `exit=1`，`+通過 -失敗` 為 `epub_toc +0 -1`、`epub_highlights_notes +0 -1`、`pdf_highlights_notes +0 -1`、`notes_bookmark +0 -2`、`markdown_export +0 -1`、`fxl_bookmarks +0 -1`、`foliate_single_column +1 -1`、`reader_screen +6 -13`、`epub_pagination +0 -2`、`reader_footer +0 -1`、`reading_position +0 -2`、`volume_key +0 -1`、`pdf_nav_zone +0 -2`、`reader_header_footer_toggle +0 -4`、`epub_fxl_tap_zone +0 -1`、`foliate_toc_footer +2 -1`、`foliate_epub_reader_view +8 -2`、`library_screen +0 -3`。數字不同就先查明原因（有人改過 `lib/` 或測試），並更新本計畫。

---

### Task 1：過期 key 守衛腳本

**Files：**
- Create：`app/tool/check_integration_keys.js`
- Create：`app/tool/test_check_integration_keys.mjs`
- Modify：`app/tool/README.md`

**Interfaces：**
- Produces：`findStaleKeys(libSources: string[], integrationFiles: {file: string, src: string}[]) → {file, line, key}[]`；`collectDartFiles(dir, { skipDirs?: string[] }) → string[]`；CLI 旗標 `--lib-dir <目錄>`、`--integration-dir <目錄>`，結束碼 0 乾淨／1 有過期 key／2 設定錯誤或掃到 0 個檔案。

**比對規則：** integration 測試裡 `Key('x')`／`ValueKey('x')` 的字串 `x`，滿足下列任一條件就算「存在」：(a) 等於 `lib/` 內某個不含 `$` 的字串字面值；(b) 符合 `lib/` 內某個 **`Key(…)`／`ValueKey(…)`／`itemKey: Key(…)` 的參數範本**（`$ident` 或 `${…}` 視為 `.+`，且第一個 `$` 之前至少有 4 個固定字元）；(c) 以 `lib/` 內某個 `keyPrefix: '…'` 的值加 `_` 開頭；(d) 測試檔自己用 `key: Key('x')` 建立（測試自建的 widget）。測試端含 `$` 的 key（迴圈變數組成）無法靜態解析，跳過。單、雙引號都支援。掃描 `lib/` 時排除 `l10n/`（產生出來的多語系檔）。

**為什麼範本只能從 `Key(…)` 取：** 計畫審查實測，若對 `lib/` 內所有字串取範本，`"$_temp0"`（多語系產生檔）、`'${x}%'`、`'h${highlight?.id}_n${note?.id}'` 等會變成 `^.+$` 這類萬用正則，讓守衛對任何 key 都回報「存在」，永遠 PASS。`lib/` 內這類近乎萬用的範本（固定字元少於 4 個的）共 149 個（`l10n/` 84 個、其他目錄 65 個），所以只排除 `l10n/` 不夠。單元測試有專門的案例擋這個失敗模式。

- [x] **Step 1：寫失敗測試**

用 Write 工具建立 `app/tool/test_check_integration_keys.mjs`：

```js
// epic-54 Issue 17：check_integration_keys.js 行為驗證。
// 零外部依賴，可直接用 Node.js 執行（比照 test_check_l10n_hardcoded_strings.mjs 既有慣例）。
//
// 用法：node app/tool/test_check_integration_keys.mjs

import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'
import checker from './check_integration_keys.js'

const { findStaleKeys } = checker
const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'check_integration_keys.js')

const stale = (lib, tests) =>
  findStaleKeys(lib, tests.map((src, i) => ({ file: `t${i}.dart`, src }))).map((v) => v.key)

// ---- 存在的 key：不報 ----
assert.deepEqual(stale(["const Key('reader_chrome_back_button')"], ["find.byKey(const Key('reader_chrome_back_button'))"]), [])

// 動態範本：$index 與 ${...} 都視為萬用（Key 建構子內的範本）
assert.deepEqual(stale(["Key('nav_zone_$index')"], ["find.byKey(const Key('nav_zone_3'))"]), [])
assert.deepEqual(stale(["Key('notes_sheet_annotation_delete_${item.key}')"], ["Key('notes_sheet_annotation_delete_hh_1_n1')"]), [])
assert.deepEqual(stale(["itemKey: Key('reader_settings_column_mode_$keySuffix'),"], ["Key('reader_settings_column_mode_single')"]), [])

// keyPrefix：前綴＋底線
assert.deepEqual(stale(["keyPrefix: 'reader_settings_font_size',"], ["Key('reader_settings_font_size_increment')"]), [])

// 測試自己建立的 widget key
assert.deepEqual(stale([], ["ElevatedButton(key: const Key('manual_import_button'), onPressed: null)"]), [])
assert.deepEqual(stale([], ["ElevatedButton(key: Key('manual_import_button'))"]), [])

// 雙引號（Key("x")、ValueKey("x")）
assert.deepEqual(stale([`const Key("dq_present_key")`], [`find.byKey(const Key("dq_present_key"))`]), [])
assert.deepEqual(stale([`const Key('x_present_key')`], [`find.byKey(const Key("dq_gone_key"))`, `find.byKey(ValueKey("dq_gone_key2"))`]), ['dq_gone_key', 'dq_gone_key2'])

// 測試端含 $ 的 key（迴圈變數）無法靜態解析，跳過，不當成過期
assert.deepEqual(stale(["const Key('pdf_settings_tab_filters')"], ["tester.tap(find.byKey(Key('pdf_settings_$keySuffix')))"]), [])

// ---- 過期 key：要報 ----
assert.deepEqual(stale(["const Key('reader_chrome_toc_button')"], ["find.byKey(const Key('reader_toc_button'))"]), ['reader_toc_button'])

// 前綴相同但不是「前綴＋底線」不算存在
assert.deepEqual(stale(["keyPrefix: 'reader_settings_font_size',"], ["Key('reader_settings_font_sizeX')"]), ['reader_settings_font_sizeX'])

// ValueKey 也檢查；同一個 key 出現多次要各報一次，附正確行號
const result = findStaleKeys(
  ["const Key('a_present')"],
  [{ file: 'x.dart', src: ["find.byKey(const Key('a_present'));", "tap(find.byKey(ValueKey('gone_1')));", "tap(find.byKey(const Key('gone_1')));"].join('\n') }],
)
assert.deepEqual(result.map((v) => [v.file, v.line, v.key]), [['x.dart', 2, 'gone_1'], ['x.dart', 3, 'gone_1']])

// ---- 守衛不能被 lib/ 內的非 Key 字串範本癱瘓（Issue 17 計畫審查 C-1）----
// 多語系產生檔的 "$_temp0"、'${x}%'、'h${a}_n${b}' 轉成正規表示式會是萬用；不是 Key 建構子的參數，必須忽略。
const wildcardLib = [
  `return "$_temp0";`,
  `final s = '\${(progress * 100).round()}%';`,
  `String get key => 'h\${highlight?.id}_n\${note?.id}';`,
]
assert.deepEqual(stale(wildcardLib, ["find.byKey(const Key('reader_toc_button'))"]), ['reader_toc_button'])

// Key 範本若第一個 $ 之前固定字元太少（過寬），也不採用
assert.deepEqual(stale(["Key('${prefix}_x')"], ["find.byKey(const Key('reader_toc_button'))"]), ['reader_toc_button'])
assert.deepEqual(stale(["Key('ab$c')"], ["find.byKey(const Key('abzzz'))"]), ['abzzz'])

// ---- CLI ----
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'chk-int-keys-'))
try {
  const libDir = path.join(tmp, 'lib')
  const itDir = path.join(tmp, 'it')
  const emptyDir = path.join(tmp, 'empty')
  fs.mkdirSync(libDir); fs.mkdirSync(itDir); fs.mkdirSync(emptyDir)
  fs.writeFileSync(path.join(libDir, 'a.dart'), "const Key('present_key');\n")
  fs.writeFileSync(path.join(itDir, 'ok_test.dart'), "find.byKey(const Key('present_key'));\n")
  const cli = (...args) => spawnSync('node', [SCRIPT, ...args], { encoding: 'utf8' })

  assert.equal(cli('--lib-dir', libDir, '--integration-dir', itDir).status, 0)

  fs.writeFileSync(path.join(itDir, 'bad_test.dart'), "line1;\nfind.byKey(const Key('gone_key'));\n")
  const bad = cli('--lib-dir', libDir, '--integration-dir', itDir)
  assert.equal(bad.status, 1)
  assert.match(bad.stdout + bad.stderr, /bad_test\.dart:2/)
  assert.match(bad.stdout + bad.stderr, /gone_key/)

  // lib/l10n/ 是產生檔，不參與 key 比對：就算裡面有同名字串也不能讓過期 key 變成存在
  fs.mkdirSync(path.join(libDir, 'l10n'))
  fs.writeFileSync(path.join(libDir, 'l10n', 'app_localizations_zh.dart'), `String get x => 'gone_key';\nreturn "$_temp0";\n`)
  assert.equal(cli('--lib-dir', libDir, '--integration-dir', itDir).status, 1)

  // 掃到 0 個檔案必須失敗，不能當成乾淨
  assert.equal(cli('--lib-dir', libDir, '--integration-dir', emptyDir).status, 2)
  assert.equal(cli('--lib-dir', emptyDir, '--integration-dir', itDir).status, 2)
  assert.equal(cli('--lib-dir', path.join(tmp, 'nope'), '--integration-dir', itDir).status, 2)
  assert.equal(cli('--bogus').status, 2)
} finally {
  fs.rmSync(tmp, { recursive: true, force: true })
}

console.log('全部測試通過')
```

- [x] **Step 2：執行，確認失敗**

Run：`node tool/test_check_integration_keys.mjs`
Expected：FAIL，`Cannot find module './check_integration_keys.js'`。

- [x] **Step 3：寫實作**

用 Write 工具建立 `app/tool/check_integration_keys.js`：

```js
#!/usr/bin/env node
// epic-54 Issue 17：過期 key 守衛。
// integration_test/ 長期沒在真機執行，Epic 38 改了工具列 key 後，測試仍引用舊 key，
// 沒有任何機制發現。本腳本找出「integration 測試引用、但 lib/ 找不到」的 Key。
//
// 用法：node tool/check_integration_keys.js [--lib-dir <目錄>] [--integration-dir <目錄>]
// 結束碼：0 乾淨；1 有過期 key；2 設定錯誤或掃到 0 個檔案。

const fs = require('fs');
const path = require('path');

// 測試端：Key('x')／ValueKey('x')（單、雙引號皆可）
const KEY_RE = /(?:Value)?Key\(\s*(['"])([^'"\n]+)\1\s*\)/g;
// 測試檔自己建立的 widget：key: Key('x')
const SELF_KEY_RE = /\bkey:\s*(?:const\s+)?(?:Value)?Key\(\s*(['"])([^'"\n]+)\1\s*\)/g;
// lib 端的範本只從 Key 建構子取（含 $ 的字串）。不能對所有字串取範本：
// lib/ 內有大量 "$_temp0"、'${x}%'、'h${a}_n${b}' 這類與 Key 無關的字串，
// 轉成正規表示式會變成萬用（^.+$），讓守衛永遠 PASS。
const LIB_KEY_TEMPLATE_RE = /(?:Value)?Key\(\s*(['"])([^'"\n]*\$[^'"\n]*)\1\s*\)/g;
const PREFIX_RE = /keyPrefix:\s*(['"])([^'"\n]+)\1/g;
const STRING_RE = /'([^'\n]*)'|"([^"\n]*)"/g;
// 範本在第一個 $ 之前至少要有這麼多個固定字元，否則視為過寬而丟棄
const MIN_TEMPLATE_PREFIX = 4;

function collectDartFiles(dir, { skipDirs = [] } = {}) {
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) return [];
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (skipDirs.includes(entry.name)) continue;
      out.push(...collectDartFiles(full, { skipDirs }));
    } else if (entry.name.endsWith('.dart')) out.push(full);
  }
  return out;
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// 把含 $ 的 Key 範本轉成正規表示式：${...} 與 $ident 皆視為 .+。
// 第一個 $ 之前的固定字元少於 MIN_TEMPLATE_PREFIX 個時回傳 null（太寬，不採用）。
function templateToRegExp(template) {
  const firstDollar = template.indexOf('$');
  if (firstDollar < MIN_TEMPLATE_PREFIX) return null;
  let pattern = '';
  let i = 0;
  while (i < template.length) {
    if (template[i] === '$') {
      if (template[i + 1] === '{') {
        const end = template.indexOf('}', i);
        i = end === -1 ? template.length : end + 1;
      } else {
        i += 1;
        while (i < template.length && /[A-Za-z0-9_]/.test(template[i])) i += 1;
      }
      pattern += '.+';
    } else {
      pattern += escapeRegExp(template[i]);
      i += 1;
    }
  }
  return new RegExp(`^${pattern}$`);
}

function buildLibIndex(libSources) {
  const literals = new Set();
  const templates = [];
  const prefixes = [];
  for (const src of libSources) {
    for (const m of src.matchAll(STRING_RE)) {
      const text = m[1] ?? m[2];
      if (text && !text.includes('$')) literals.add(text);
    }
    for (const m of src.matchAll(LIB_KEY_TEMPLATE_RE)) {
      const re = templateToRegExp(m[2]);
      if (re) templates.push(re);
    }
    for (const m of src.matchAll(PREFIX_RE)) prefixes.push(m[2]);
  }
  return { literals, templates, prefixes };
}

function isPresent(key, index, selfKeys) {
  if (selfKeys.has(key)) return true;
  if (index.literals.has(key)) return true;
  if (index.templates.some((re) => re.test(key))) return true;
  return index.prefixes.some((p) => key.startsWith(`${p}_`));
}

/**
 * @param {string[]} libSources lib/ 內各 .dart 檔的內容
 * @param {{file: string, src: string}[]} integrationFiles
 * @returns {{file: string, line: number, key: string}[]}
 */
function findStaleKeys(libSources, integrationFiles) {
  const index = buildLibIndex(libSources);
  const result = [];
  for (const { file, src } of integrationFiles) {
    const selfKeys = new Set([...src.matchAll(SELF_KEY_RE)].map((m) => m[2]));
    src.split('\n').forEach((text, i) => {
      for (const m of text.matchAll(KEY_RE)) {
        // 測試端含 $ 的 key（例如迴圈內的 Key('pdf_settings_$keySuffix')）無法靜態解析，跳過
        if (m[2].includes('$')) continue;
        if (!isPresent(m[2], index, selfKeys)) result.push({ file, line: i + 1, key: m[2] });
      }
    });
  }
  return result;
}

function parseArgs(argv) {
  const opts = {
    libDir: path.join(__dirname, '..', 'lib'),
    integrationDir: path.join(__dirname, '..', 'integration_test'),
  };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--lib-dir') opts.libDir = argv[++i];
    else if (argv[i] === '--integration-dir') opts.integrationDir = argv[++i];
    else return { error: `不認得的參數：${argv[i]}` };
  }
  return opts;
}

function main(argv) {
  const opts = parseArgs(argv);
  if (opts.error) {
    console.error(`錯誤：${opts.error}。可用參數：--lib-dir <目錄>、--integration-dir <目錄>。`);
    return 2;
  }
  // lib/l10n/ 是產生出來的多語系檔，只有翻譯字串，不含 Widget 的 Key
  const libFiles = collectDartFiles(opts.libDir, { skipDirs: ['l10n'] });
  const itFiles = collectDartFiles(opts.integrationDir);
  if (libFiles.length === 0 || itFiles.length === 0) {
    console.error(
      `錯誤：掃描範圍內沒有 .dart 檔（lib：${libFiles.length} 個、integration：${itFiles.length} 個）。` +
        '目錄可能指錯。請確認 --lib-dir／--integration-dir，或在 app/ 目錄下執行。',
    );
    return 2;
  }
  const stale = findStaleKeys(
    libFiles.map((f) => fs.readFileSync(f, 'utf8')),
    itFiles.map((f) => ({
      file: path.relative(path.join(opts.integrationDir, '..'), f).replace(/\\/g, '/'),
      src: fs.readFileSync(f, 'utf8'),
    })),
  );
  if (stale.length === 0) {
    console.log(`PASS：掃描 ${itFiles.length} 個 integration 測試檔，所有 Key 在 lib/ 都找得到對應`);
    return 0;
  }
  for (const v of stale) console.log(`${v.file}:${v.line}: lib/ 找不到 Key('${v.key}')`);
  console.error(
    `\nFAIL：${stale.length} 處 integration 測試引用的 Key 在 lib/ 已不存在。` +
      '請到 lib/ 找現行的對應 key（見 plans/plan-issue-17.md 的對照表），不要為了讓檢查通過而刪斷言。',
  );
  return 1;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));

module.exports = { findStaleKeys, collectDartFiles };
```

- [x] **Step 4：執行測試，確認通過**

Run：`node tool/test_check_integration_keys.mjs`
Expected：印出「全部測試通過」。

- [x] **Step 5：對現況執行，確認抓得到已知的過期 key**

Run：`node tool/check_integration_keys.js; echo "exit=$?"`
Expected：`exit=1`，並**剛好**列出這 7 個 key、共 22 處引用（計畫審查時在 `main` `e978b5fe` 實測）：`reader_appbar_chapter_title`、`reader_appbar_static_title`、`reader_fixed_layout_back_button`、`reader_fixed_layout_notes_button`、`reader_foliate_progress_button`、`reader_pdf_notes_button`、`reader_pdf_settings_button`。

```bash
node tool/check_integration_keys.js | grep -c "找不到 Key"                       # 預期 22
node tool/check_integration_keys.js | grep -o "Key('[a-z_]*')" | sort -u | wc -l # 預期 7
```

**不得**列出 `nav_zone_*`、`reader_settings_*`、`pdf_settings_*`、`notes_sheet_annotation_delete_*`、`manual_import_*`（動態 key 或測試自建 widget，列出代表比對規則有錯，先修腳本）。**若輸出是 `PASS` 且 `exit=0`，代表守衛被癱瘓了**（計畫審查發現的 C-1 失敗模式），不得往下做，先檢查 `templates` 是不是混進了萬用範本。

- [x] **Step 6：更新 `README.md`**

在 `app/tool/README.md` 的 `check_l10n_hardcoded_strings.js` 段落之前，新增一段（用 Edit，定位字串用 `## \`check_l10n_hardcoded_strings.js\``）：

```markdown
## `check_integration_keys.js`

找出 `app/integration_test/` 引用、但 `app/lib/` 已不存在的 `Key`。`integration_test/` 只能在真機執行，
平常的 `flutter test` 不會跑，介面改版後測試仍引用舊 key 也不會有人發現（epic-54 Issue 16／17）。

### 何時該執行

改了 `lib/` 內任何 `Key(...)`、或新增／修改 `integration_test/` 之後，提交前執行。

### 執行方式

```bash
cd app
node tool/check_integration_keys.js
node tool/test_check_integration_keys.mjs   # 守衛本身的單元測試
```

結束碼：0 乾淨；1 有過期 key；2 設定錯誤或掃到 0 個檔案（目錄指錯時不會被當成乾淨）。

### 比對規則

`Key('x')`（單、雙引號皆可）的 `x` 只要符合其一就算存在：等於 `lib/` 內某個不含 `$` 的字串字面值；
符合 `lib/` 內某個 `Key(…)` 參數的範本（`nav_zone_$index` 這類動態 key，第一個 `$` 之前至少 4 個固定字元）；
以 `keyPrefix: '…'` 加底線開頭；或是測試檔自己用 `key: Key('x')` 建立。掃描 `lib/` 時排除 `l10n/`。
範本只從 `Key(…)` 取，不從所有字串取：否則 `"$_temp0"` 這類字串會變成萬用正則，讓守衛永遠通過。

### 已知限制

只檢查字串字面值的 `Key`；測試端含 `$` 的 key（迴圈變數組成，例如 `Key('pdf_settings_$keySuffix')`）無法靜態解析，跳過；
`find.text(...)`、`find.byType(...)`、元件型別轉型（例如 `tester.widget<TextButton>`）不在範圍內，
這類過期仍須靠真機執行才看得到。
```

- [x] **Step 7：Commit**

```bash
git add tool/check_integration_keys.js tool/test_check_integration_keys.mjs tool/README.md
git commit -m "feat(epic-54): 新增 integration 測試過期 key 守衛腳本（Issue 17）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

注意：此時守衛對現況會回報 `exit=1`（正是要靠後面的 Task 清掉）。**不要**把它納入任何自動流程，直到 Task 7 全部清完。

---

### Task 2：A 組——頁碼文字與 `volume_key_test` 的 `AppBar`（3 檔）

**Files：**
- Create：`app/test/support/reader_chrome_finders.dart`
- Modify：`app/integration_test/reader_footer_test.dart:65-66`、`reading_position_test.dart:88,109`、`volume_key_test.dart`（helper `_pumpUntilTextFound`、第 114／131／133／135／138／140 行，見 Step 4）

**Interfaces：**
- Produces：`String pageInfoText(WidgetTester tester)`：回傳 `reader_chrome_page_info_text` 的文字（找不到時丟 `TestFailure`，訊息說明工具列可能已收合）。

- [x] **Step 1：建立共用函式**

用 Write 工具建立 `app/test/support/reader_chrome_finders.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 讀取閱讀器底部工具列的頁碼文字（`reader_chrome_page_info_text`），格式
/// `'$current / $total · $percent%'`，例如 `1 / 6 · 17%`（epic-38 Issue 1，
/// `ReaderScreen._pageProgressText`）。
///
/// 這個 widget 只在工具列可見時存在（`_chromeVisible` 預設為 true；觸發
/// `ZoneAction.menu` 或 FXL 換頁後會收合），找不到時請先確認工具列沒被收合。
String pageInfoText(WidgetTester tester) {
  final finder = find.byKey(const Key('reader_chrome_page_info_text'));
  if (finder.evaluate().isEmpty) {
    fail('找不到 reader_chrome_page_info_text：工具列可能已收合，或位置資訊尚未載入');
  }
  return tester.widget<Text>(finder).data ?? '';
}
```

- [x] **Step 2：改 `reader_footer_test.dart`**

在 import 區加 `import '../test/support/reader_chrome_finders.dart';`（接在 `pump_localized_widget.dart` 那行之後）。把第 65～66 行：

```dart
    expect(find.text('進度 17% ｜ 第 1/6 頁'), findsOneWidget,
        reason: 'sample_dual_page.pdf 共 6 頁');
```

換成：

```dart
    expect(pageInfoText(tester), '1 / 6 · 17%',
        reason: 'sample_dual_page.pdf 共 6 頁');
```

同檔後面若還有 `進度 N% ｜ 第 x/y 頁` 斷言，用同樣方式換（先 `grep -n "進度 " integration_test/reader_footer_test.dart` 列出全部）。百分比算法是 `(current / total * 100).round()`：1/6→17、2/6→33、3/6→50、4/6→67、5/6→83、6/6→100。

- [x] **Step 3：改 `reading_position_test.dart`**

加同樣的 import。把第 88 行 `expect(find.text('進度 67% ｜ 第 4/6 頁'), findsOneWidget);` 換成 `expect(pageInfoText(tester), '4 / 6 · 67%');`。把第 109～110 行：

```dart
    expect(find.text('進度 67% ｜ 第 4/6 頁'), findsOneWidget,
        reason: '重新開啟同一本書應自動回到離開前的頁碼');
```

換成：

```dart
    expect(pageInfoText(tester), '4 / 6 · 67%',
        reason: '重新開啟同一本書應自動回到離開前的頁碼');
```

- [x] **Step 4：改 `volume_key_test.dart`**

這個檔案有**三種**過期參照，計畫審查實測列出（`grep -n "_pumpUntilTextFound\|AppBar\|第 [0-9]/" integration_test/volume_key_test.dart`）：第 36 行的 helper `_pumpUntilTextFound`、第 114／133／140 行的 `find.textContaining('第 N/')`、第 135 行的 `find.byType(AppBar)`。只改斷言、不改 helper，測試會卡在第 131 行逾時 15 秒。

加同樣的 import（`../test/support/reader_chrome_finders.dart`）。

1. **helper：** 把第 36～44 行的 `_pumpUntilTextFound` 換成以頁碼元件輪詢的版本（逾時秒數 15 秒**不變**）：

```dart
/// 等到頁碼元件（reader_chrome_page_info_text）的文字以 [prefix] 開頭，例如 '2 / '。
Future<void> _pumpUntilPageInfoStartsWith(WidgetTester tester, String prefix) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (true) {
    final finder = find.byKey(const Key('reader_chrome_page_info_text'));
    if (finder.evaluate().isNotEmpty &&
        (tester.widget<Text>(finder).data ?? '').startsWith(prefix)) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：頁碼文字未以「$prefix」開頭，目前為「${finder.evaluate().isEmpty ? '（元件不存在）' : pageInfoText(tester)}」');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}
```

2. **呼叫與斷言：**

| 舊（行號為 Issue 17 規劃時） | 新 |
|---|---|
| 114：`expect(find.textContaining('第 1/'), findsOneWidget, reason: '初始應在第 1 頁');` | `expect(pageInfoText(tester), startsWith('1 / '), reason: '初始應在第 1 頁');` |
| 131：`await _pumpUntilTextFound(tester, '第 2/');` | `await _pumpUntilPageInfoStartsWith(tester, '2 / ');` |
| 133～134：`expect(find.textContaining('第 2/'), findsOneWidget, reason: …)` | `expect(pageInfoText(tester), startsWith('2 / '), reason: '模擬 onVolumeKey(down) 後應換到第 2 頁');` |
| 135：`expect(find.byType(AppBar), findsOneWidget, reason: '音量鍵翻頁不應影響沉浸模式');` | `expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget, reason: '音量鍵翻頁不應影響沉浸模式（頂部工具列仍在）');` |
| 138：`await _pumpUntilTextFound(tester, '第 1/');` | `await _pumpUntilPageInfoStartsWith(tester, '1 / ');` |
| 140～141：`expect(find.textContaining('第 1/'), findsOneWidget, reason: …)` | `expect(pageInfoText(tester), startsWith('1 / '), reason: '模擬 onVolumeKey(up) 後應換回第 1 頁');` |

第 135 行的 `reader_chrome_back_button` 只在工具列可見（`_chromeVisible` 為真）時存在，語意正好對應舊的「AppBar 還在＝沒進入沉浸模式」；Task 3 不需再處理這個檔案。

- [x] **Step 5：在真機執行並確認**

```bash
for n in reader_footer_test reading_position_test volume_key_test; do
  flutter test integration_test/$n.dart -d 3CEF42ECD491687 2>&1 | tail -n 4 | cut -c1-160
done
```

Expected：三個檔案各自 `All tests passed!`。

若失敗：看第一個例外。`找不到 reader_chrome_page_info_text` 代表工具列在該步驟已收合或位置資訊未載入（例如 `volume_key_test` 翻頁後）→ 依判定規則處理，**不得**把斷言改成 `findsNothing` 或刪掉。文字格式不符（例如 PDF 實際顯示不是 `4 / 6 · 67%`）→ 印出 `pageInfoText(tester)` 的實際值，對照 `reader_screen.dart:2283` 的公式；若程式與註解不符，停止回報。

- [x] **Step 6：斷言強度檢查與 Commit**

列出「舊斷言 → 新斷言」逐條比對：舊的是「畫面含某段文字」，新的是「頁碼元件文字**完全等於**某值」，強度**提高**（`reading_position_test` 同時驗證百分比）；`volume_key_test` 的 `startsWith('N / ')` 與舊的 `textContaining('第 N/')` 等強。

```bash
flutter analyze && node tool/check_l10n_hardcoded_strings.js
git add test/support/reader_chrome_finders.dart integration_test/reader_footer_test.dart integration_test/reading_position_test.dart integration_test/volume_key_test.dart
git commit -m "test(epic-54): 頁碼文字斷言改讀 reader_chrome_page_info_text（Issue 17 A 組）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：B 組——頁首／AppBar（2 檔）

**Files：**
- Modify：`app/integration_test/pdf_nav_zone_test.dart`（`find.byType(AppBar)` 全部）、`reader_header_footer_toggle_test.dart`（`reader_appbar_*` 全部）
- 注意：`volume_key_test.dart:135` 也有 `find.byType(AppBar)`，已在 Task 2 Step 4 與該檔其他修改一起處理（同一檔案、同一個 commit，否則該檔在 Task 2 驗證時會失敗）。

**背景：** 舊介面用 `Scaffold.appBar`，現在是 `ReaderChromeTopBar`（`Padding` 內的普通 widget）。**`showHeader`／`showFooter` 偏好的現行語意**（`reader_screen.dart` 約 2880、2899、2848 行）：`showHeader` 控制 Foliate 格式的角落頁首文字 `reader_foliate_header_text`；`showFooter` 只控制 Foliate 格式的角落進度文字 `reader_foliate_progress_text`。**PDF 的 `ReaderFooter`（`reader_footer`）與兩個偏好都無關**，只在 `format == BookFormat.pdf && _chromeVisible` 時隨底部工具列建構。因此 `reader_header_footer_toggle_test` 裡「`showFooter=false` 時 `reader_footer` 應 `findsNothing`」的斷言（第 221、282 行）在 PDF 上已不成立，且 Foliate 的 `reader_footer`（`_buildFoliateEpubFooter`）也是由底部工具列內的 `ReaderFooter` 提供、不受 `showFooter` 控制。這幾條是**行為改變**，要依判定規則第 3 條處理，不是換 key 就好。`ZoneAction.menu` 會切換 `_chromeVisible`（`reader_screen.dart:3463`）。工具列收合且沒有標題、沒有 TTS 圖示時，頂部列整個回傳 `SizedBox.shrink()`，所以 `reader_chrome_back_button` 消失。

- [x] **Step 1：列出所有要改的地方**

```bash
grep -n "AppBar\|reader_appbar" integration_test/pdf_nav_zone_test.dart integration_test/reader_header_footer_toggle_test.dart
```

- [x] **Step 2：改 `pdf_nav_zone_test.dart`**

`find.byType(AppBar)` 的語意是「頂部工具列是否顯示」。換成 `find.byKey(const Key('reader_chrome_back_button'))`：`findsOneWidget` 與 `findsNothing` 的位置**照舊**。例如第 119、125 行：

```dart
    expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);
    ...
    expect(find.byKey(const Key('reader_chrome_back_button')), findsNothing);
```

若同檔有 `reason:` 提到 AppBar，把文字改成「頂部工具列」。

- [x] **Step 3：改 `reader_header_footer_toggle_test.dart`**

對照（先讀 `reader_screen.dart` 約 2880 行，確認 `reader_foliate_header_text` 的顯示條件）：

| 舊斷言 | 新斷言 | 說明 |
|---|---|---|
| EPUB、`showHeader=true`：`reader_appbar_chapter_title` `findsOneWidget`（第 90、224 行） | `reader_foliate_header_text` `findsOneWidget` | 頁首章節名稱現在是角落文字 |
| EPUB、`showHeader=true`：`reader_appbar_static_title` `findsNothing`（第 92 行） | **刪除這一條**，並在 commit 訊息與 `epic.md` 註明 | 該 key 已無對應，「不出現靜態標題」這個行為不再成立 |
| EPUB、`showHeader=false`：`reader_appbar_static_title` `findsOneWidget`、`find.text('閱讀器')` `findsOneWidget`（第 155～157 行） | `reader_foliate_header_text` `findsNothing` | 舊行為「關閉頁首後標題退回靜態文字」已不存在；新行為是頁首文字不出現 |
| EPUB、`showHeader=false`：`reader_appbar_chapter_title` `findsNothing`（第 159 行） | 併入上一條（同一個斷言） | — |
| PDF：`reader_appbar_static_title` `findsOneWidget`（第 285 行） | `reader_foliate_header_text` `findsNothing` | PDF 不走 Foliate 頁首文字 |

**停止條件（判定規則第 4 條）：** 上表第 3、5 列把「某文字存在」換成「某元件不存在」，強度變弱。執行前向使用者回報這兩條，說明新舊差異，等使用者決定「照這樣改」或「刪掉這兩個測試」。其餘列照做。

另外，`頁尾` 相關斷言（`reader_footer` `findsOneWidget`／`findsNothing`，第 95、162、221、282 行）的 key 仍存在，**不用改**，但要確認結果：`reader_footer` 現在位於底部工具列內，工具列收合時會消失。

- [x] **Step 4：在真機執行並確認**

```bash
for n in pdf_nav_zone_test reader_header_footer_toggle_test; do
  flutter test integration_test/$n.dart -d 3CEF42ECD491687 2>&1 | tail -n 4 | cut -c1-160
done
```

Expected：兩個檔案各自 `All tests passed!`。若 `reader_header_footer_toggle_test` 因 `reader_footer` 斷言失敗（`showFooter=false` 時預期 `findsNothing`，但現在 `reader_footer` 恆在底部工具列內），這是行為改變，依判定規則第 3 條停止回報，**不要**改成永遠成立的斷言。

- [x] **Step 5：Commit**

```bash
flutter analyze && node tool/check_l10n_hardcoded_strings.js && node tool/check_integration_keys.js | grep -c "reader_appbar"
git add integration_test/pdf_nav_zone_test.dart integration_test/reader_header_footer_toggle_test.dart
git commit -m "test(epic-54): AppBar／reader_appbar_* 斷言遷移到 ReaderChromeTopBar（Issue 17 B 組）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

預期 `grep -c "reader_appbar"` 輸出 `0`。

---

### Task 4：C 組——筆記與書籤（5 檔）

**Files：**
- Modify：`app/integration_test/markdown_export_test.dart:114`、`epub_highlights_notes_test.dart`、`pdf_highlights_notes_test.dart`、`notes_bookmark_test.dart`、`fxl_bookmarks_test.dart`

- [x] **Step 1：`markdown_export_test.dart`（型別轉型）**

`notes_sheet_export_markdown` 現在是 `IconButton`（`notes_bottom_sheet.dart:208`）。把第 113～116 行：

```dart
    expect(
      tester.widget<TextButton>(exportButtonFinder).onPressed,
      isNotNull,
    );
```

換成：

```dart
    expect(
      tester.widget<IconButton>(exportButtonFinder).onPressed,
      isNotNull,
    );
```

斷言強度不變。

- [x] **Step 2：`pdf_highlights_notes_test.dart` 與 `notes_bookmark_test.dart`（舊 key）**

```bash
sed -i "s/'reader_pdf_notes_button'/'reader_chrome_annotations_button'/g" integration_test/pdf_highlights_notes_test.dart integration_test/notes_bookmark_test.dart
grep -n "reader_pdf_notes_button\|_pumpUntilNotesButtonEnabled" integration_test/pdf_highlights_notes_test.dart integration_test/notes_bookmark_test.dart | head
```

`pdf_highlights_notes_test` 的 `_pumpUntilNotesButtonEnabled`（第 45～60 行附近）是在等筆記按鈕「可點擊」。Issue 16 基準失敗原因就是它在找 `reader_pdf_notes_button`。換 key 後按鈕的啟用條件是 `_openBookFlow.isRendered`（`reader_screen.dart:2868`），PDF 載入完成即啟用。

- [x] **Step 3：`fxl_bookmarks_test.dart`（舊 key）**

```bash
sed -i -e "s/'reader_fixed_layout_notes_button'/'reader_chrome_annotations_button'/g" -e "s/'reader_fixed_layout_back_button'/'reader_chrome_back_button'/g" integration_test/fxl_bookmarks_test.dart
```

**注意 FXL 換頁會強制收合工具列**（`reader_screen.dart:1530`：書籤跳轉後 `_chromeVisible = false`）。若測試在跳轉後再找 `reader_chrome_*`，要先讓工具列重新出現。重新出現的方式用測試既有的 `ReaderScreen.triggerZoneAction(key, ZoneAction.menu)`（`pdf_nav_zone_test.dart` 已在用，需要 `ReaderScreen` 帶 `key: GlobalKey<ReaderScreenState>`）。**不要**去點畫面中央猜位置。

- [x] **Step 4：`notes_bookmark_test.dart` 與 `epub_highlights_notes_test.dart`（筆記面板分頁）**

**事實（計畫審查指正，已對照 `reader_screen.dart:2440,2870`）：** 底部工具列的 `reader_chrome_annotations_button` 開面板時傳 `initialTabIndex: 1`，所以面板**開在「劃線與備註」分頁**；「書籤」分頁的內容（`notes_sheet_bookmark_toggle`、`notes_sheet_bookmark_list`）在切換之前不在 widget 樹內（`TabBarView` 只建構目前分頁）。

**`notes_bookmark_test.dart`（原因已確定）：** 第 109 行點 `notes_sheet_bookmark_toggle` 前，要先切到書籤分頁。在第 108 行（`expect(find.byType(NotesBottomSheet), findsOneWidget);`）之後插入：

```dart
    await tester.tap(find.byKey(const Key('notes_sheet_tab_bookmarks')));
    await tester.pumpAndSettle();
```

第 117 行重新開啟面板後，一樣停在「劃線與備註」分頁，而第 119 行起要找 `notes_sheet_bookmark_list`，所以在第 118 行（`await tester.pumpAndSettle();`）之後也插入同樣兩行。同檔其他「開面板後找書籤相關 key」的位置（`grep -n "notes_sheet_bookmark\|reader_chrome_annotations_button" integration_test/notes_bookmark_test.dart`）逐一確認前面都有切到書籤分頁。

**`epub_highlights_notes_test.dart`（原因未定，要診斷）：** 這個測試**已經**在每次開面板後先點 `notes_sheet_tab_annotations`（第 156、180、195 行），所以「沒切分頁」不是原因。失敗在第 196 行：找 `notes_sheet_annotation_delete_hh_epub_1_n1` 找不到（key 由 `AnnotationListItem.key = 'h${highlight?.id}_n${note?.id}'` 組成，測試用 `h${highlightId}_n1`）。要查的是清單裡實際有哪些 key：在第 196 行之前暫時插入：

```dart
    // ignore: avoid_print
    print('[診斷] 清單項目 key：' +
        find.byWidgetPredicate((w) => w.key.toString().contains('notes_sheet_annotation_'))
            .evaluate().map((e) => e.widget.key.toString()).toList().toString());
```

依輸出走：

- 清單裡有 `notes_sheet_annotation_delete_h<某id>_n<別的數字>` → 筆記 id 不是 1（資料庫自動遞增或預先寫入的筆記數量改變），測試硬寫 `_n1`。改成由 `notesRepository` 查出該劃線對應的筆記 id 再組 key，**不得**改成 `findsWidgets` 或前綴比對。
- 清單裡完全沒有 `notes_sheet_annotation_` 項目 → 前面第 168～172 行「點選合併項目」之後的流程改變了資料（例如點選同時刪除了項目）。對照該段註解「跳轉本身……既定限制」，若與 `lib/` 行為不符，依判定規則第 3 條停止。
- 清單有項目但 key 格式不同 → 對照 `notes_bottom_sheet.dart:514` 修正。

**診斷碼在 Step 6 提交前必須移除。**

- [x] **Step 5：在真機執行並確認**

```bash
for n in markdown_export_test pdf_highlights_notes_test notes_bookmark_test fxl_bookmarks_test epub_highlights_notes_test; do
  echo "== $n"; flutter test integration_test/$n.dart -d 3CEF42ECD491687 2>&1 | grep -E "^[0-9:]+ \+[0-9]+( -[0-9]+)?:|The following|Expected|等待逾時|The finder" | tail -n 4 | cut -c1-170
done
```

Expected：五個檔案全部 `All tests passed!`。每個失敗依「過期或真缺陷」判定規則處理，逐檔記錄「舊斷言、新斷言、強度變化」。同一個檔案換完 key 之後若又冒出下一個過期參照，繼續按規則換，直到該檔通過或遇到停止條件。

- [x] **Step 6：Commit**

```bash
grep -rn "診斷" integration_test/ | head   # 預期無輸出
flutter analyze && node tool/check_l10n_hardcoded_strings.js && node tool/check_integration_keys.js | grep -E "reader_pdf_notes_button|reader_fixed_layout" | wc -l   # 預期 0
git add integration_test/markdown_export_test.dart integration_test/pdf_highlights_notes_test.dart integration_test/notes_bookmark_test.dart integration_test/fxl_bookmarks_test.dart integration_test/epub_highlights_notes_test.dart
git commit -m "test(epic-54): 筆記與書籤測試遷移到現行工具列與筆記面板（Issue 17 C 組）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5：D 組——設定面板與進度（3 檔）

**Files：**
- Modify：`app/integration_test/foliate_single_column_test.dart:223`、`reader_screen_test.dart`、`epub_pagination_test.dart`

- [x] **Step 1：`foliate_single_column_test.dart`（元件型別）**

設定面板的欄數選項現在是 `EBOptionChipGroup` 的 `EBOptionChipItem`，渲染成 `ReaderOptionTile`。`itemKey` 掛在帶 `BoxDecoration` 的 `Container` 上（`lib/screens/widgets/reader_option_tile.dart` 約 107～125 行，註解寫明這是為了讓測試可以 `tester.widget<Container>(find.byKey(...))` 直接取得），選取狀態的背景色在非 E-Ink 主題下是 `theme.colorScheme.primary`（第 51～53 行）。所以第 223 行的 `tester.widget<IconButton>(...)` 丟 `Bad state: No element`。**確切的修法**（同等強度：仍然精確比對「已選取等於主題 primary 色」）：

```dart
    final singleBtnFinder = find.byKey(const Key('reader_settings_column_mode_single'));
    final singleChip = tester.widget<Container>(singleBtnFinder);
    final primaryColor = Theme.of(tester.element(singleBtnFinder)).colorScheme.primary;
    expect((singleChip.decoration as BoxDecoration).color, primaryColor,
        reason: '已持久化 columnMode=single 時單欄按鈕應反映為選取狀態（背景色等於主題 primary 色）');
```

同檔其他 `tester.widget<IconButton>(find.byKey(Key('reader_settings_…')))`（先 `grep -n "widget<IconButton>" integration_test/foliate_single_column_test.dart` 列出）比照辦理。若某處驗證的是 `onPressed`（可點擊與否）而不是顏色：`ReaderOptionTile` 的結構是 `InkWell(onTap: …, child: Container(key: itemKey, …))`，`InkWell` 在 `Container` 的**祖先**，所以用 `tester.widget<InkWell>(find.ancestor(of: finder, matching: find.byType(InkWell)).first).onTap`。若找不到可讀取的屬性 → 停止，回報使用者（判定規則第 3 條）。

另外該檔還有 `reader_settings_column_mode_auto` 等 key，動態 key，守衛會視為存在，不用改。

- [x] **Step 2：`reader_screen_test.dart`（13 個失敗）**

基準：`+6 -13`，主要失敗是 10 秒條件逾時（`_pumpUntil`，第 195 行）與 `database_closed` 連帶錯誤。這個檔案很大（約 1033 行），先依下列步驟縮小：

```bash
flutter test integration_test/reader_screen_test.dart -d 3CEF42ECD491687 > ../.scratch/rs.log 2>&1
grep -n "^[0-9:]* +[0-9]* -[0-9]*: .*\[E\]" ../.scratch/rs.log | cut -c1-150
grep -B1 -A3 "^The following TestFailure\|^The following assertion" ../.scratch/rs.log | grep -v "^--" | head -60 | cut -c1-170
```

用上面的輸出列出 13 個失敗的**測試名稱**與各自第一個例外。`database_closed` 與 `inTest is not true` 是前一個失敗的連帶錯誤，不單獨處理。對每個失敗：

1. 例外是「找不到某 key／文字」→ 對照「現行介面對照表」。
2. 例外是「等待逾時：條件未成立」→ 看該測試 `_pumpUntil` 的條件（例如等 `reader_chrome_layout_button` 可點擊、等 `reader_settings_*` 出現）；用 `grep -n "reader_settings_\|pdf_settings_\|reader_pdf_settings" integration_test/reader_screen_test.dart` 找過期 key（守衛腳本已知的過期項：`reader_pdf_settings_button`→`reader_chrome_layout_button`；`pdf_settings_bold_strength_increment`、`pdf_settings_crop_mode_auto`、`reader_settings_font_size_increment` 要對照 `lib/screens/pdf_settings_sheet.dart` 與 `reader_settings_sheet.dart` 的 `keyPrefix`／`itemKey` 實際值）。
3. 遇到判定規則第 3～5 條 → 停止回報。

這個檔案是本 Issue 工作量最大的一個，**分批提交**：每修好一組（例如 PDF 設定面板相關的測試）就跑一次該檔案、提交一次，commit 訊息註明修好哪幾個測試名稱。

- [x] **Step 3：`epub_pagination_test.dart`（`reader_foliate_progress_button` 已刪除）**

基準失敗：`_pumpUntilProgressVisible` 等不到 `reader_foliate_progress_text`（第 47 行）。`reader_foliate_progress_text` 仍存在（`reader_screen.dart:3044`，角落浮動文字 `'$currentPage/$totalPages'`），但顯示條件要查：

```bash
grep -n "_buildFoliateProgressText()\|reader_foliate_progress" lib/screens/reader_screen.dart | head
sed -n 2870,2890p lib/screens/reader_screen.dart | cut -c1-130
```

`reader_foliate_progress_button`（第 145 行 `tester.tap`）在 `lib/` 已不存在。舊流程是「點浮動進度按鈕 → 開 Bottom Sheet → 輸入框跳頁」，現在跳頁輸入框 `reader_footer_jump_input` 直接在底部工具列的 `reader_footer`。把「點按鈕開 Sheet」那一步**刪除**，直接 `enterText(find.byKey(Key('reader_footer_jump_input')), …)`，其餘斷言（跳頁後頁碼變更）保留。這是流程簡化而非斷言變弱，但仍要在 commit 訊息註明「刪除開 Sheet 步驟，原因：`reader_foliate_progress_button` 已不存在於 `lib/`，跳頁輸入框改在底部工具列的 `reader_footer`」，並用 `git log --oneline -S"reader_foliate_progress_button" -- lib` 找出移除它的 commit 一併寫上；若查不到取代依據，依判定規則第 3 條停止。

- [x] **Step 4：在真機執行並確認**

```bash
for n in foliate_single_column_test epub_pagination_test reader_screen_test; do
  echo "== $n"; flutter test integration_test/$n.dart -d 3CEF42ECD491687 2>&1 | grep -E "^[0-9:]+ \+[0-9]+( -[0-9]+)?:" | tail -n 1 | cut -c1-80
done
```

Expected：`foliate_single_column_test`、`epub_pagination_test` 全過；`reader_screen_test` 全過，或剩下的失敗已依判定規則逐一記錄並回報。

- [x] **Step 5：Commit**

```bash
flutter analyze && node tool/check_l10n_hardcoded_strings.js
git add integration_test/foliate_single_column_test.dart integration_test/epub_pagination_test.dart integration_test/reader_screen_test.dart
git commit -m "test(epic-54): 設定面板與進度測試遷移到現行介面（Issue 17 D 組）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6：E 組——行為待判斷（4 檔）

這組的失敗**不是 key 過期**，是斷言與實際行為不符。每一個都必須先查清楚原因，再決定。**這組不預先寫修法**，因為在查明原因前任何修法都是猜測。

**Files：** `app/integration_test/epub_toc_test.dart:140`、`epub_fxl_tap_zone_test.dart:98`、`foliate_toc_footer_test.dart:160`、`foliate_epub_reader_view_test.dart:206,455`

- [x] **Step 1：`epub_toc_test`——點目錄後「第一節」為何仍在**

基準：第 140 行預期 `find.text('第一節')` `findsNothing`（目錄 Sheet 關閉後章節名不該再出現），實際仍有 1 個。先讀測試第 125～145 行，確認它在驗證什麼：

```bash
sed -n 125,150p integration_test/epub_toc_test.dart
grep -n "reader_foliate_header_text\|findCurrentPath" lib/screens/reader_screen.dart | head -5
```

假設與驗證：頁首章節文字 `reader_foliate_header_text`（`_buildFoliateHeaderText`）會顯示目前章節名。若跳到第二章後頁首顯示的是「第二節」，則「第一節」仍在的原因是**目錄 Sheet 還沒關閉**（`tester.pumpAndSettle` 未等 Sheet 動畫）或**畫面其他位置仍顯示第一節**。在第 140 行前暫時印出 `find.text('第一節')` 命中的 widget 祖先（`tester.widget` 的 `toStringDeep` 或 `find.ancestor`）確認它在哪裡。

- 位於已關閉的 Sheet 內（動畫未完成）→ 測試時序問題，補 `await tester.pumpAndSettle()`（這是等動畫完成，不是調大逾時）。
- 位於頁首文字 → 設計上頁首顯示的是「目前章節」，`第一節` 若是跳轉前的章節，表示跳轉未生效 → 疑似真缺陷，**停止回報**。

- [x] **Step 2：`foliate_toc_footer_test`——493 與 490**

基準：第 160 行 `displayTotalPages` 預期 493，實際 490，訊息「同一本書換頁不應改變 displayTotalPages」。**先重跑 3 次**，確認 490 是否穩定：

```bash
for i in 1 2 3; do flutter test integration_test/foliate_toc_footer_test.dart -d 3CEF42ECD491687 2>&1 | grep -E "Expected|Actual" | head -2; done
```

- 3 次皆 490、且測試其他地方曾以 493 為預期 → 頁數估計隨裝置字型／WebView 版本變動（Issue 16 規劃時觀察到是 `TCL 14`，WebView 154），查測試 493 當初是在哪個裝置定的（`git log -S493 -- integration_test/foliate_toc_footer_test.dart`）。**不得**把 493 直接改成 490；若頁數取決於裝置，改成「同一本書換頁前後 `displayTotalPages` 相等」這種不依賴絕對值的斷言（測試名稱本來就是這個語意），並回報使用者確認。
- 結果不穩定（490、493 隨機）→ 疑似真缺陷（換頁時總頁數變動），**停止回報**。

- [x] **Step 3：`foliate_epub_reader_view_test`——錯誤訊息文字**

基準：第 206 行預期錯誤訊息 `'無法快取書籍檔案'`，實際 `'無法載入書籍'`；第 455 行 `Expected: true Actual: false`。

```bash
grep -rn "無法快取書籍檔案\|無法載入書籍" lib/ | cut -c1-140
git log --oneline -3 -S"無法快取書籍檔案" -- lib | cat
```

若 `lib/` 內兩個字串都存在（對應不同錯誤路徑），確認該測試觸發的是哪條路徑，依實際路徑修正預期字串；若 `無法快取書籍檔案` 已從 `lib/` 移除，改為現行字串，commit 訊息註明移除的 commit。第 455 行先讀測試意圖再判斷，不得直接改成 `isFalse`。

- [x] **Step 4：`epub_fxl_tap_zone_test`——位置沒變**

基準：第 98 行預期點擊熱區後位置 JSON「不等於」`{"cfi":"epubcfi(/6/2)","index":0,"fraction":1}`，實際相等（沒換頁）。先讀測試第 70～100 行，確認點擊哪個熱區、預期翻頁方向；再查熱區 key `nav_zone_$index`（`foliate_reader_view.dart:877`）與 `kTapZoneSlop`、`kTapZoneDebounceMs`、`tapMaxDurationMs`（CLAUDE.md「不可逆的技術決策」）：真機上點擊時長是否超過 700 ms 被視為長按（TCL 14 載入慢時有可能）。**熱區點擊門檻是真機校準值，不得沿用或自行調整**，若懷疑是門檻問題 → 停止回報，建議另立校準工單。

- [x] **Step 5：Commit（只提交已查明且合理的修改）**

```bash
grep -rn "診斷" integration_test/ | head   # 預期無輸出
flutter analyze && node tool/check_l10n_hardcoded_strings.js
git add integration_test/epub_toc_test.dart integration_test/foliate_toc_footer_test.dart integration_test/foliate_epub_reader_view_test.dart integration_test/epub_fxl_tap_zone_test.dart
git commit -m "test(epic-54): 行為不符的 integration 測試依查證結果修正（Issue 17 E 組）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

沒有改的檔案不要 `git add`。每個「停止回報」的案例在 Task 8 寫進 `epic.md`。

---

### Task 7：F 組——`library_screen_test`，並啟用守衛

**Files：** `app/integration_test/library_screen_test.dart`

- [x] **Step 1：查 `book_item_…` 為何不在書架**

基準：第 124 行 `find.byKey(Key('book_item_${importedBook.id}'))` 找不到（Issue 16 已在 base `bdff826c` 同機確認同樣失敗）。測試流程是：用 `importService.importFiles([contentUri])` 匯入 → `pumpWidget(LibraryScreen)` → `pumpAndSettle` → 點書。先確認匯入結果與書架內容：

```bash
sed -n 80,125p integration_test/library_screen_test.dart
grep -n "book_item_" lib/screens/library_screen.dart | head -5
```

在第 124 行前暫時印出 `repository.listBooks`（用 `grep -n "Future<List<Book>>" lib/library/library_repository.dart` 確認方法名）的筆數、`importedBook.id`、以及畫面上 `book_item_` 開頭的 key 數量（`find.byWidgetPredicate((w) => w.key is Key && w.key.toString().contains('book_item_'))`）：

- 資料庫有書、畫面沒有 → 書架顯示條件問題（排序、分類、預設分頁、載入未完成）。
- 資料庫沒書 → `importFiles` 在真機失敗（`content://` URI 來源、權限）。
- 資料庫有書且畫面也有、但 key 不同 → `book_item_$id` 格式變更，改測試。

依結果處理；屬於產品行為問題 → 停止回報，不改 `lib/`。

**另一個過期斷言（計畫審查指出）：** 點進閱讀器後，第 128 行還有 `expect(find.text('閱讀器'), findsOneWidget);`。舊介面進入閱讀器後 `AppBar` 有靜態標題「閱讀器」，現在頂部列沒有（見「現行介面對照表」）。即使書架點擊修好，測試也會卡在這裡。換成：

```dart
      expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget,
          reason: '點書後應進入閱讀器（頂部工具列出現）');
```

計畫審查原本說有 3 處（第 128、225、309 行）。Issue 17 規劃時用 `grep -n "閱讀器" integration_test/library_screen_test.dart` 實測，**只有第 128 行是斷言**，第 111、204、294 行是註解（Issue 16 補的「進入閱讀器需要完整的閱讀器功能依賴」）。執行時再 grep 一次確認；若另外兩個測試有類似的「進入閱讀器」斷言（例如 `find.byType(ReaderScreen)`），那些不是過期，不要改。

- [x] **Step 2：在真機執行並確認**

```bash
flutter test integration_test/library_screen_test.dart -d 3CEF42ECD491687 2>&1 | grep -E "^[0-9:]+ \+[0-9]+( -[0-9]+)?:" | tail -n 1 | cut -c1-80
```

- [x] **Step 3：啟用守衛並確認全清**

```bash
node tool/check_integration_keys.js; echo "exit=$?"
```

Expected：`PASS：…`、`exit=0`。若仍有項目，逐一處理（回到對應 Task 的規則）。清零後，把這條指令加進 `CLAUDE.md`「常用指令」區塊，緊接在 `node tool/check_l10n_hardcoded_strings.js` 之後：

```bash
# 修改 lib/ 內任何 Key 或 integration_test/ 後，提交前跑一次：找出 integration 測試引用、
# 但 lib/ 已不存在的 Key（純 Node，免安裝；見 app/tool/README.md）
node tool/check_integration_keys.js
```

- [x] **Step 4：Commit**

```bash
git add integration_test/library_screen_test.dart ../CLAUDE.md
git commit -m "test(epic-54): library_screen_test 查證與守衛納入常用指令（Issue 17 F 組）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8：全量真機驗證與收尾

**Files：** `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md`

- [x] **Step 1：全量真機執行（32 檔）**

```bash
OUT=../.scratch/final; mkdir -p $OUT; : > $OUT/summary.txt
for f in $(grep -l "pumpLocalizedWidget" integration_test/*.dart | sort); do
  n=$(basename $f .dart); [ "$n" = "manual_import_acceptance_test" ] && continue
  timeout 600 flutter test $f -d 3CEF42ECD491687 > $OUT/$n.log 2>&1
  echo "$n exit=$? $(grep -E '^[0-9:]+ \+[0-9]+( -[0-9]+)?:' $OUT/$n.log | tail -1 | grep -oE '\+[0-9]+( -[0-9]+)?')" >> $OUT/summary.txt
done
grep -vc "exit=0" $OUT/summary.txt; cat $OUT/summary.txt
```

用 `run_in_background`（約 30～40 分鐘）。Expected：Issue 16 的 14 個通過檔案仍通過（無回歸）；本 Issue 的 18 個檔案通過，或剩下的失敗已逐一依判定規則記錄。

- [x] **Step 2：完整 `flutter test`（只在這裡跑一次）**

```bash
flutter test > ../.scratch/full_test.log 2>&1; echo "exit=$?"
grep -E "^[0-9:]+ \+[0-9]+ (~[0-9]+ )?-[0-9]+" ../.scratch/full_test.log | tail -1 | cut -c1-60
```

Expected：只有既存的 `pdf_reader_view_filters_test`（bold overlay 多頁案例）失敗。出現其他失敗就是本 Issue 造成，必須查。

- [x] **Step 3：`flutter analyze`、檢查腳本、守衛**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
node tool/check_integration_keys.js
node tool/test_check_integration_keys.mjs
```

Expected：No issues found!；三項 PASS；守衛 `exit=0`；單元測試「全部測試通過」。

- [x] **Step 4：更新文件**

在 `epic.md` 新增「Issue 17 實作完成與真機驗證結果」段落：裝置與 WebView 版本、18 個檔案各自的結果（通過／仍失敗＋原因）、每個「舊斷言 → 新斷言」的強度變化（特別是 Task 3 刪除的斷言）、依判定規則**停止回報**的案例與使用者的決定、守衛腳本說明。`issues.md` Issue 17 狀態改為「🟡 實作完成，待程式審查」。`docs/epics.md` 備註只寫「Issue 17 已完成」。

- [x] **Step 5：Commit 文件並請求程式審查**

```bash
git add ../docs/epics/epic-54-architecture-optimization/epic.md ../docs/epics/epic-54-architecture-optimization/issues.md ../docs/epics.md
git commit -m "docs(epic-54): Issue 17 真機驗證結果與狀態同步

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

程式審查報告存 `docs/epics/epic-54-architecture-optimization/reviews/review-issue-17.md`（gitignore，不進版控）。審查者先出報告，不直接改程式。

---

## 自我審查

**Spec 對照（Issue 17 工單文字）：** 約 17 個檔案遷移（Task 2～7，實際 18 檔，含 Issue 16 基準的全部失敗檔）；`notes_sheet_*`、`reader_fixed_layout_notes_button`、`reader_appbar_chapter_title`、頁尾文字、`AppBar`、`TextButton`→`IconButton` 各有對應步驟（Task 4、4、3、2、3、4）；「過期或行為真的改變」的案例有判定規則與 Task 6；`library_screen_test` 既存問題為 Task 7；首要對象的 7 個檔案分布於 Task 4、5、6，且 Task 8 Step 1 全量驗證；真機驗收為每個 Task 的執行步驟。另外補了工單沒要求、但 Issue 16 審查揭露的根因：守衛腳本（Task 1）。

**已知缺口（刻意保留，不是佔位符）：** Task 4 Step 4（`epub_highlights_notes_test`）、Task 5 Step 2、Task 6 的修法取決於查明原因，計畫給了**查證指令、判斷依據與停止條件**而不是猜測的程式碼。這些案例的程式碼在本計畫寫成時無法確定（需要在真機看畫面狀態）。Task 3 有兩條斷言強度變弱，已明列為「需使用者決定」。

**佔位符掃描：** 沒有「TBD」「之後補」之類的空白。Task 1 的守衛與其測試給了完整程式碼；Task 2 的替換給了逐行前後對照；真機序號 `3CEF42ECD491687` 為已知值。需要依真機查證結果決定的步驟（見「已知缺口」）都附有查證指令與停止條件。

**型別一致性：** `pageInfoText(WidgetTester)` 在 Task 2 定義，Task 2 內三個檔案使用，其他 Task 不引用。`findStaleKeys`／`collectDartFiles` 在 Task 1 測試與實作的簽章一致。

## 修訂紀錄

**2026-10-06 依 `reviews/review-plan-issue-17.md` 修訂**（Critical 1、Important 4、Minor 2；皆已對照程式碼查證）：

- **C-1（屬實，且比審查說的更廣）：** 實測計畫原本的守衛對現況回報 `PASS`、`exit=0`，7 個過期 key 一個都抓不到。審查建議「排除 `lib/l10n/`」不夠：近乎萬用的範本在 `l10n/` 有 84 個，在其他目錄還有 65 個（例如 `h${highlight?.id}_n${note?.id}`、`'${x}%'`）。改為：lib 端範本只從 `Key(…)`／`ValueKey(…)` 的參數取，且第一個 `$` 之前至少 4 個固定字元；掃描時再排除 `l10n/`。修正版對現況剛好回報 7 個 key、22 處；新單元測試對舊版守衛會失敗（證明測試擋得住這個失敗模式）。
- **I-4（屬實）：** `KEY_RE`、`SELF_KEY_RE` 改為支援單、雙引號。另補一個審查沒提到、實測發現的問題：測試端迴圈組成的 `Key('pdf_settings_$keySuffix')` 無法靜態解析，守衛跳過並列為已知限制，否則會誤報 `reader_screen_test.dart:660`。
- **I-1（屬實）：** `volume_key_test.dart` 還有 helper `_pumpUntilTextFound`（第 131、138 行）與 `find.byType(AppBar)`（第 135 行）。Task 2 Step 4 改為完整的 helper 與逐行對照表，`AppBar` 一併在 Task 2 處理（同檔同 commit，否則 Task 2 驗證會失敗）；Task 3 註明。
- **I-2（屬實，我原本的分析顛倒）：** 工具列按鈕開面板傳 `initialTabIndex: 1`，面板開在「劃線與備註」分頁。`notes_bookmark_test` 的原因是沒切到書籤分頁（已確定，並補第 117 行之後也要切）。**連帶更正：** `epub_highlights_notes_test` 已經會先點 `notes_sheet_tab_annotations`，我原本寫的「要先切分頁」修法是錯的，改成診斷步驟（印出清單實際 key）。對照表同步修正。
- **I-3（部分屬實）：** `library_screen_test.dart` 的 `find.text('閱讀器')` 只有第 128 行 1 處是斷言；第 111、204、294 行是註解，不是審查所說的 3 處斷言。已把第 128 行加進 Task 7 並註明，要求執行時再 grep 確認。
- **M-1（屬實）：** `ReaderOptionTile` 的 `itemKey` 掛在帶 `BoxDecoration` 的 `Container` 上，Task 5 Step 1 改為確切修法（同等強度比對 `primary` 色）。
- **M-2（屬實）：** PDF 的 `ReaderFooter` 只受 `_chromeVisible` 控制，與 `showFooter` 偏好無關；`showFooter` 只控制 Foliate 的角落進度文字。Task 3 背景補上，並把 `reader_footer` 的 `findsNothing` 斷言明列為行為改變。
