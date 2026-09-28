# Epic 45 Issue 10 — 防遺漏稽核腳本 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `app/tool/check_l10n_hardcoded_strings.js`，自動偵測 `app/lib/` 中「Widget 字串參數位置」上未經 `AppLocalizations` 包裝的硬編碼中文字串，防止既有畫面遺漏與日後新增畫面忘記包裝；並修正稽核實跑時發現的真陽性漏網字串，最後把 Issue 3-9 完成後的最終稽核結果記錄進 `epic.md`。

**Architecture:** 純 Node 內建模組（`fs`／`path`，免 `npm install`，比照 `check_foliate_es_compat.js`）。核心是一個「字串感知」的 Dart 詞法掃描器：邊掃邊分辨目前在字串還是註解（含 `${ ... }` 插值內的巢狀字串），抹除註解後，只對「緊接在 Widget 字串參數關鍵字或 `Text(` 之後」的含中文字面值判定違規；例外機制為整檔略過清單、專有名詞值清單、行內 `// l10n-ignore: <理由>`。掃描邏輯以 `module.exports` 匯出純函式，單元測試腳本（`.mjs`）直接呼叫，不需 Dart／Flutter。

**Tech Stack:** Node.js（`node:assert/strict`、`node:child_process`）、Flutter `gen-l10n`（ARB）、Flutter widget test（`flutter_test`）。

**Spec:** `docs/epics/epic-45-interface-i18n/spec.md` §9（防遺漏稽核腳本契約）；`docs/epics/epic-45-interface-i18n/design.md`「稽核腳本」與「排除清單」條目（`/receiving-code-review` M-2 修正）。

## 審查修訂紀錄（`reviews/review-plan-issue-10.md`，Approved with Revisions，0 Critical／2 Important／3 Minor）

- **I-1（採納）**：`UI_POSITION` 未放行 Dart 原始字串前綴 `r`，`Text(r'中文')` 會整個逃逸稽核（已實測重現：修正前回傳 `[]`）。腳本兩處結尾補 `r?`，測試新增 4 個原始字串案例，變異驗證新增第 4 項，Review Focus 新增 #9。修正後於草稿上驗證：舊腳本＋新測試失敗、新腳本＋新測試通過，對真實 `app/lib/` 仍恰好 1 處警報。
- **I-2（採納，但失敗機制與審查描述不同）**：Task 3 Step 1 原為 Bash 專用語法（`mktemp`／`cp -r`／`printf`），在 PowerShell 下確實無法執行；但審查所稱「MSYS `/tmp` 路徑使 Node 拋 `ENOENT`」在 Git Bash 下**不成立**（Git Bash 會自動轉換傳給原生程式的路徑，原指令已在 Git Bash 實測通過）。仍採納改為純 Node 單行指令，並刻意**不採用審查建議的版本**（內含 `\"`／`\\n` 巢狀跳脫，在 PowerShell 下脆弱），改以 `String.fromCharCode` 組字串避開所有巢狀引號；已於 Bash 與 PowerShell 兩邊實測輸出一致（`zz_planted.dart:2`、`exit=1`）。
- **M-1（採納）**：Task 2 Step 5 的 `for` 迴圈改為 Node 內 `forEach`，Bash／PowerShell 皆已實測輸出四行 `549`（執行 Task 2 後為 `550`）。
- **M-2（不採納）**：審查稱巢狀 `readString()` 返回後外層 `while` 可能跳過結尾判斷，需補 `if (i >= n) break;`。查證外層迴圈條件 `while (i < n && depth > 0)` 每次迭代都會重新檢查 `i < n`，且 `readString()` 每次呼叫必然推進 `i`，不存在跳過或無窮迴圈的路徑；實測 `Text('${ 'x`、`Text('${a{'`、`'${` 三種未閉合輸入皆立即結束（0 ms）、不拋例外。補上重複的邊界判斷只會增加雜訊，故不修改。
- **M-3（採納）**：`AGENTS.md` 存在且有 `## Commands` 小節（僅列 `flutter` 指令），Task 3 Step 4 一併新增。註：審查稱該小節「已明載 `check_foliate_es_compat.js`」不精確——該腳本記載在 `## Architecture` 而非 `## Commands`，不影響結論。

## Global Constraints

以下逐字取自 `spec.md` §9，各 Task 隱含遵守：

- 新增 `app/tool/check_l10n_hardcoded_strings.js`（Node，比照既有 `app/tool/check_foliate_es_compat.js` 執行方式與慣例）。
- 掃描範圍：`app/lib/**/*.dart`（不含 `app/lib/l10n/**` 產生檔與 ARB 字典本身）。
- 規則：偵測 Widget 建構式常見字串參數位置（`Text('...')`、`title:`/`subtitle:`/`label:`/`hintText:`/`content:` 等關鍵字後的字串字面值）中出現中文字元（Unicode 範圍 U+4E00–U+9FFF，CJK Unified Ideographs）且未透過 `AppLocalizations`/`l10n.` 存取。**掃描前須先剝離 `//` 單行與 `/* ... */` 多行註解內容再比對**（`/receiving-code-review` M-4 修正）——本專案 Dart 原始碼註解一律使用正體中文，若不先剝離，註解文字會被誤判為未包裝字串。
- 排除清單至少涵蓋：`BookGroup.uncategorized` 等系統保留 Sentinel 常數定義所在檔案（`book_group.dart`）；內建字型品牌名所在檔案；`epic-42-text-conversion` 簡繁字典檔案；`app/test/**`（腳本只掃 `app/lib/`，測試本來就不在掃描範圍）。
- 是否接入 CI／`flutter analyze` 前置檢查，依專案既有 CI 設定方式決定。**本計畫定案：不接入**——查證 repo 根目錄不存在 `.github/`／`.gitea/` 等 CI 設定，`app/tool/README.md` 亦明載「這個 repo 尚未設定任何 CI pipeline」，與 `check_foliate_es_compat.js` 現況一致；改由 `CLAUDE.md`「常用指令」、`AGENTS.md`「Commands」與 `app/tool/README.md` 記載執行時機（Task 3）。

**專案硬性規範（`CLAUDE.md`）：**

- 所有註解、文件、commit 訊息一律正體中文；程式碼命名維持原生語言慣例。
- `flutter analyze` 提交前必須 `No issues found!`。
- 測試執行範圍：每個 Task 只跑觸及的測試檔；完整 `flutter test`／`flutter analyze` 僅在最後一個 Task（Task 3）執行一次。
- 不修改與本 Issue 無關的既有程式碼；`app/lib/` 內只動 Task 2 列出的檔案。

## 稽核實測基礎（本計畫撰寫時對 `app/lib/` 的實際盤點）

撰寫本計畫時，以與腳本同一套「字串感知掃描」對 `app/lib/`（排除 `l10n/`）盤點**所有**含中文字元的字串字面值：38 個檔案、14,992 個字面值，其中 `reader/text_conversion_dict.dart` 一檔就占 14,894 個（簡繁字典，整檔略過），其餘 **37 個檔案、98 個字面值**分類如下——這是排除清單與規則範圍的實證依據：

| 類別 | 數量 | 內容 | 稽核腳本是否報警 |
|---|---|---|---|
| **A 真漏網（Issue 3-9 遺漏）** | 3 | `reader_settings_sheet.dart:590-591` 欄數「單欄」×2（ARB key `readerSettingsColumnSingleLabel` 早已存在，該處 tuple 漏換）；`:671` `const Text('字型', ...)`（ARB 無對應 key） | 只報 `:671`（`'單欄'` 位於 record 位置參數，見 Review Focus #1） |
| **B 合法（專有名詞／資料／範本）** | 23 | 內建字型品牌名 10（`font_management_screen.dart` 5、`reader_settings_sheet.dart` 5）、`book_group.dart` Sentinel 3、`text_conversion_icon.dart` 簡／繁字形 4、`txt_chapter_splitter.dart` 章節正則 1、合成 EPUB 的 XHTML 範本 3、`foliate_native_bridge.dart` JS polyfill 1、`eb_sheet_shell.dart` 刻意保留的「關閉」fallback 1 | 不報警（不在 Widget 字串參數位置，或屬專有名詞值清單） |
| **C 開發者診斷（不涵蓋）** | 63 | `throw`／`Exception`／`assert`／`debugPrint`／`ReaderConsoleLog.add` 等診斷訊息；`design.md` 明訂「Console Log／診斷內容翻譯」不在本 Epic 範圍，Issue 7 已定調例外訊息不顯示給使用者 | 不報警 |
| **D 使用者可見、但不在 Widget 字串參數位置** | 9 | `reader/bookmark.dart` `Bookmark.defaultName()`「第 N 頁」／「N% 處」／「書籤」×3（`spec.md` §7 明文排除、屬既有機制）；`main.dart:179` Android 通知頻道名稱「朗讀播放中」；`reader/tts_provider.dart:37` `TtsVoice.systemDefault.displayName`「系統預設語音」（`reader_screen.dart`／`tts_defaults_screen.dart` 以 `Text(voice.displayName)` 顯示）；`remote/opds_feed_parser.dart`「未命名分類」×2／「未知書名」×1（遠端目錄缺 `<title>` 時的 fallback，顯示於書庫畫面）；`wifi_transfer_http_server.dart:303`「(未知檔名)」 | **不報警，且不在本 Issue 修正**（見「需人類確認的設計決定」#3） |

## 需人類確認的設計決定

計畫審查時請確認以下四點（每點皆已在計畫內給出建議做法，覆寫任一點只需調整對應 Task）：

1. **規則範圍維持 spec §9 的「Widget 字串參數位置」，不擴大成「所有中文字串字面值」。** 實測擴大範圍會把 C 類 63 處診斷訊息全部報成警報，必須另建一套「例外／`assert`／`debugPrint` 上下文辨識」才能壓假警報，複雜度與誤判風險遠高於收益；而 spec 規則實測對 `app/lib/` 產生 0 假警報。代價是 Review Focus #1／#2 的已知盲區，由 Task 2／3 的人工盤點補足。
2. **Task 2 在本 Issue 內修正 A 類 3 處真漏網。** 驗收標準要求「對 `app/lib/` 執行腳本零警報」，而 `:671` 的 `'字型'` 是真陽性，只能修、不能用 `// l10n-ignore` 掩蓋；同檔同性質、ARB key 早已存在的 `'單欄'` ×2 一併修正（零新增 key）。這是計畫唯一會動 production 程式碼與 ARB 的地方（新增 1 個 key）。
3. **D 類 9 處不在本 Issue 修正，只記錄於 `epic.md` 最終稽核結果並建議後續處理。** 它們需要各自的設計決定（例如書籤預設名稱是「建立當下語言固化」還是「顯示時動態產生」，`spec.md` §7 已明文排除；通知頻道名稱無 `BuildContext`；`TtsVoice`／OPDS 屬 model 層字串），超出「稽核腳本」範疇。建議另立 Issue 11（或後續 Epic）處理，是否立案由人類決定。
4. **在 `CLAUDE.md`「常用指令」與 `AGENTS.md`「Commands」各新增一行稽核腳本指令（Task 3 Step 4）。** 因為不接 CI，腳本若沒有被寫進每個開發者與 Agent 必讀的指令清單，就會被遺忘、失去「防止日後新增畫面忘記包裝」的目的；`AGENTS.md` 是 Antigravity CLI 等其他實作角色的根指南（`review-plan-issue-10.md` M-3）。若認為不該動這兩份指引檔，刪除該 Step 即可，其餘不受影響。

## Review Focus

以下是 spec 隱含、但沒有任何 Task 測試能完全涵蓋、最可能咬到使用者（這裡指開發者）的情境，依可能性排序；每條註明由哪個測試或流程負責：

1. **`record`／位置參數中的中文字串掃不到**（例如 `reader_settings_sheet.dart:590` 的 `(ColumnMode.single, 'single', Icons.crop_portrait, '單欄', '單欄')`）。開發者預期「任何畫面上的中文都會被抓到」，實際不會。→ 已知盲區，於 README「已知限制」明載；本 Issue 的人工盤點（`稽核實測基礎`表）已補抓現有的一處；Task 1 測試以「非關鍵字位置不觸發」案例釘住此行為，避免有人誤把規則放寬造成 C 類假警報。
2. **`?? '中文'` fallback 與 model 層字串（D 類）掃不到。** → 同上，README 明載；D 類 9 處記錄於 `epic.md`。
3. **字串插值 `${ ... }` 內含同種引號的巢狀字串**（例如 `'${m['x']}'`）若處理錯誤，會讓掃描器的「在字串內／外」狀態錯位，**其後整個檔案的判定全部失準**（漏報或大量假警報）。→ Task 1 測試：巢狀插值後緊接的下一行仍能正確判定；且以變異驗證（Task 1 Step 6）確認關掉巢狀處理時測試會失敗。
4. **註解夾在關鍵字與字串之間**（`title: // 標題` 換行後才是字串）。→ Task 1 測試 + 變異驗證。
5. **Windows 工作樹的 CRLF 行尾**（本 repo 在 Windows 開發，`git` 會提示 LF↔CRLF 轉換）：`\r` 不可影響行號、註解結束判定與 `\s*` 位置匹配。→ Task 1 CRLF 測試案例。
6. **字串內含 `//`（URL）不可被當成註解**，否則同一行後面的真違規會被吞掉。→ Task 1 測試。
7. **相鄰字串串接**（`Text('a'\n '中文')`，Dart 會自動串接）：第二段沒有緊接關鍵字，須沿用前一段的位置判斷。→ Task 1 測試。
8. **行內例外標記沒寫理由不可生效**（避免有人用空的 `// l10n-ignore:` 靜音警報）；且只涵蓋所在行與下一行。→ Task 1 測試。
9. **Dart 原始字串 `r'…'`／`r"…"`**：掃描器以「引號」為字面值起點，前綴 `r` 會殘留在「引號之前的程式碼」尾端，若位置正則不放行，`Text(r'中文')` 會整個逃逸稽核（`review-plan-issue-10.md` I-1，已實測重現）。→ Task 1 測試（含 `Text(r'…')`／`Text(r"…")`／`Text(const r'…')`／`title: r'…'` 四個案例）＋ Step 6 第 4 項變異驗證。

---

### Task 1：稽核腳本與單元測試

**Files:**
- Create: `app/tool/test_check_l10n_hardcoded_strings.mjs`
- Create: `app/tool/check_l10n_hardcoded_strings.js`

**Interfaces:**
- Produces（`module.exports`，供測試與 Task 2／3 使用）：
  - `findViolations(src: string): { line: number, text: string }[]`——單一 Dart 原始碼字串的違規清單（`line` 為 1-based）。
  - `scanLibDir(libDir: string): { file: string, line: number, text: string }[]`——掃描整個目錄，`file` 為相對 `libDir`、以 `/` 分隔的路徑；自動略過 `l10n/` 與 `SKIP_FILES`。
  - CLI：`node tool/check_l10n_hardcoded_strings.js [--lib-dir <目錄>]`，預設掃描 `app/lib/`（以腳本位置推算，與目前工作目錄無關）；結束碼 `0` 乾淨／`1` 有違規；違規輸出到 stderr，格式 `  lib/<相對路徑>:<行號>  <字面值前 60 字>`。
- Consumes：無（純新增，不依賴其他 Task）。

- [ ] **Step 1：撰寫測試腳本（紅燈階段）**

建立 `app/tool/test_check_l10n_hardcoded_strings.mjs`：

```javascript
// epic-45-interface-i18n Issue 10：check_l10n_hardcoded_strings.js 行為驗證。
// 零外部依賴，可直接用 Node.js 執行（比照 test_text_offset_map.mjs 既有慣例）。
//
// 用法：node app/tool/test_check_l10n_hardcoded_strings.mjs

import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'
import checker from './check_l10n_hardcoded_strings.js'

const { findViolations, scanLibDir } = checker
const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'check_l10n_hardcoded_strings.js')

// 以「行」組合 Dart 片段（JS 字串用雙引號，Dart 的單引號與 ${} 才不必跳脫）
const dart = (...lines) => lines.join('\n')
const lines = (src) => findViolations(src).map((v) => v.line)

// ---- 應該觸發 ----

// Text 位置參數
assert.deepEqual(lines(dart("Text('確定');")), [1])
assert.deepEqual(lines(dart("const Text('確定');")), [1])
assert.deepEqual(lines(dart("SelectableText('內文');")), [1])
assert.deepEqual(lines(dart("child: const Text(", "  '確定',", ");")), [2])

// 具名參數關鍵字（含換行、const）
assert.deepEqual(lines(dart("AppBar(title: '設定');")), [1])
assert.deepEqual(lines(dart("IconButton(tooltip: '關閉');")), [1])
assert.deepEqual(lines(dart("InputDecoration(hintText: '搜尋', labelText: '書名');")), [1, 1])
assert.deepEqual(lines(dart("ListTile(", "  subtitle:", "    '說明',", ");")), [3])
assert.deepEqual(lines(dart("SnackBar(content: const Text('已儲存'));")), [1])
assert.deepEqual(lines(dart("Foo(label: const '標籤');")), [1])

// 含插值、含跳脫引號、三引號
assert.deepEqual(lines(dart("Text('第 $n 頁');")), [1])
assert.deepEqual(lines(dart("Text('不要\\'中\\'');")), [1])
assert.deepEqual(lines(dart("Text('''第一行", "第二行''');")), [1])

// Dart 原始字串（r 前綴）：前綴不可讓位置判斷失效
assert.deepEqual(lines(dart("Text(r'原始中文字串');")), [1])
assert.deepEqual(lines(dart('Text(r"原始中文字串");')), [1])
assert.deepEqual(lines(dart("Text(const r'原始中文字串');")), [1])
assert.deepEqual(lines(dart("AppBar(title: r'原始中文字串');")), [1])

// 相鄰字串串接：後段含中文，沿用前段的位置判斷
assert.deepEqual(lines(dart("Text('abc'", "  '中文');")), [2])

// 關鍵字與字串之間夾著註解，仍屬 Widget 字串參數位置
assert.deepEqual(lines(dart("AppBar(title: // 標題", "  '設定');")), [2])

// 字串插值內含同種引號的巢狀字串，不可讓後續解析錯位
assert.deepEqual(lines(dart("Text('${m['x']}確定');")), [1])
assert.deepEqual(lines(dart("final s = '${m['x']}';", "Text('確定');")), [2])

// CRLF 行尾（Windows 工作樹）
const crlf = (...ls) => ls.join('\r\n')
assert.deepEqual(lines(crlf("Text('中');", "Text('文');")), [1, 2])
assert.deepEqual(lines(crlf("AppBar(title:", "  '設定');")), [2])
assert.deepEqual(lines(crlf("// Text('註解') 按鈕", "Text('確定');")), [2])

// 行號正確（多行來源）
assert.deepEqual(lines(dart("a();", "b();", "Text('中');", "c();", "Text('文');")), [3, 5])

// ---- 不應該觸發 ----

// 已在地化 / 無中文
assert.deepEqual(lines(dart("Text(l10n.confirm);")), [])
assert.deepEqual(lines(dart("Text('OK');")), [])
assert.deepEqual(lines(dart("AppBar(title: Text(l10n.settingsTitle));")), [])

// 註解（本專案註解一律為中文，是最大宗誤報來源）
assert.deepEqual(lines(dart("// Text('確定') 按鈕")), [])
assert.deepEqual(lines(dart("/* title: '設定' */")), [])
assert.deepEqual(lines(dart("/* 外層 /* 巢狀 Text('確定') */ 仍在註解內 Text('確定') */")), [])
assert.deepEqual(lines(dart("/// 文件註解 tooltip: '關閉'")), [])
assert.deepEqual(lines(dart("final s = '${m['x']}'; // Text('註解中文')")), [])

// 字串內的 // 不是註解：其後同一行的真違規仍要抓到
assert.deepEqual(lines(dart("final u = 'http://x.com'; Text('確定');")), [1])

// 非 Widget 字串參數位置：例外 / 診斷 / assert / 資料 / fallback
assert.deepEqual(lines(dart("throw Exception('下載失敗');")), [])
assert.deepEqual(lines(dart("debugPrint('載入失敗');")), [])
assert.deepEqual(lines(dart("assert(x > 0, '必須為正整數');")), [])
assert.deepEqual(lines(dart("const kName = '未分類';")), [])
assert.deepEqual(lines(dart("final t = l10n?.close ?? '關閉';")), [])
assert.deepEqual(lines(dart("final r = RegExp(r'^第[章回]');")), [])
// 關鍵字必須是完整識別字，context: 不是 text:
assert.deepEqual(lines(dart("Foo(context: '中文');")), [])

// 專有名詞（內建字型品牌名）
assert.deepEqual(lines(dart("Text('思源黑體');")), [])
assert.deepEqual(lines(dart("Text('思源黑體 Bold');")), [1]) // 只有「完全等於」品牌名才放行

// ---- 行內例外標記 ----
assert.deepEqual(lines(dart("Text('確定'); // l10n-ignore: 測試用")), [])
assert.deepEqual(lines(dart("// l10n-ignore: 測試用", "Text('確定');")), [])
assert.deepEqual(lines(dart("// l10n-ignore: 測試用", "a();", "Text('確定');")), [3]) // 只涵蓋下一行
assert.deepEqual(lines(dart("Text('確定'); // l10n-ignore:")), [1]) // 沒寫理由不算數

// ---- 目錄掃描與 CLI ----
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'l10n-audit-'))
try {
  const write = (rel, content) => {
    const full = path.join(tmp, rel)
    fs.mkdirSync(path.dirname(full), { recursive: true })
    fs.writeFileSync(full, content)
  }
  write('screens/clean.dart', "Text('OK'); Text(l10n.x);")
  write('l10n/app_localizations_zh.dart', "Text('確定');") // gen-l10n 產生檔，須略過
  write('library/models/book_group.dart', "Foo(title: '未分類');") // SKIP_FILES
  write('reader/text_conversion_dict.dart', "Foo(text: '內存');") // SKIP_FILES

  assert.deepEqual(scanLibDir(tmp), [])
  assert.equal(spawnSync('node', [SCRIPT, '--lib-dir', tmp]).status, 0)

  // 人為植入一個硬編碼字串：必須被抓到，且結束碼為 1、輸出含檔案與行號
  write('screens/planted.dart', dart('a();', "Text('植入的硬編碼');"))
  const found = scanLibDir(tmp)
  assert.equal(found.length, 1)
  assert.equal(found[0].file, 'screens/planted.dart')
  assert.equal(found[0].line, 2)
  const run = spawnSync('node', [SCRIPT, '--lib-dir', tmp], { encoding: 'utf8' })
  assert.equal(run.status, 1)
  assert.match(run.stderr, /lib\/screens\/planted\.dart:2/)
} finally {
  fs.rmSync(tmp, { recursive: true, force: true })
}

console.log('check_l10n_hardcoded_strings：全部測試通過')
```

- [ ] **Step 2：執行測試，確認因腳本尚未存在而失敗**

Run（於 `app/` 目錄下）：`node tool/test_check_l10n_hardcoded_strings.mjs`
Expected：FAIL，錯誤為 `Cannot find module` 指向 `check_l10n_hardcoded_strings.js`（`ERR_MODULE_NOT_FOUND`）。

- [ ] **Step 3：撰寫稽核腳本**

建立 `app/tool/check_l10n_hardcoded_strings.js`：

```javascript
// epic-45-interface-i18n Issue 10：防遺漏稽核腳本。
//
// 掃描 app/lib/**/*.dart，找出「Widget 字串參數位置」上未經 AppLocalizations
// 包裝、含中文字元的字串字面值，避免既有畫面遺漏、以及日後新增畫面忘記包裝。
// 規則契約見 docs/epics/epic-45-interface-i18n/spec.md §9，
// 執行方式與慣例比照 check_foliate_es_compat.js（純 Node 內建模組、免 npm install）。
//
// 用法：
//   node app/tool/check_l10n_hardcoded_strings.js
//   node app/tool/check_l10n_hardcoded_strings.js --lib-dir <目錄>   # 測試／驗收用
//
// 結束碼 0：乾淨；1：找到至少一處未包裝的硬編碼中文字串。

const fs = require('fs');
const path = require('path');

// CJK Unified Ideographs（spec §9：U+4E00–U+9FFF）
const CJK = /[一-鿿]/;

// 「接收顯示文字」的具名參數。依 app/lib 內實際接收 l10n 字串的參數統計
// （tooltip／label／title／text／labelText／hintText／message／subtitle），
// 再補上 spec §9 列出的 content 與 Flutter 常見的同類參數。
const UI_KEYWORDS = [
  'tooltip', 'label', 'title', 'subtitle', 'text', 'labelText', 'hintText',
  'helperText', 'errorText', 'counterText', 'prefixText', 'suffixText',
  'content', 'message', 'semanticLabel', 'semanticsLabel',
];

// 「字串字面值緊接在這些位置之後」才視為 Widget 字串參數：
//   1. `<keyword>: [const] '...'`
//   2. `Text(` ／ `SelectableText(` 的第一個位置參數
// 結尾的 `r?` 是 Dart 原始字串前綴：字面值的起點是引號本身，前綴 `r` 會留在
// 「引號之前的程式碼」尾端，若不在此放行，`Text(r'中文')` 會整個逃逸稽核。
const UI_POSITION = new RegExp(
  '(?:\\b(?:' + UI_KEYWORDS.join('|') + ')\\s*:\\s*(?:const\\s+)?r?' +
    '|\\b(?:Text|SelectableText)\\s*\\(\\s*(?:const\\s+)?r?)$',
);

// 整檔略過（相對 app/lib，以 / 分隔）。每一項都要寫明理由。
const SKIP_FILES = new Map([
  ['reader/text_conversion_dict.dart', 'epic-42 簡繁轉換字典資料檔，全檔皆為刻意的中文資料'],
  ['library/models/book_group.dart', '系統保留分類 Sentinel（「未分類」／「未分类」），見 spec §6'],
]);

// 字面值本身就是專有名詞、不翻譯（design.md：內建字型品牌名）。
const ALLOWED_LITERAL_VALUES = new Set([
  '思源黑體', '思源宋體', '原俠正楷', '台灣圓體', '源流明體',
]);

// 行內例外標記：`// l10n-ignore: <理由>`，涵蓋標記所在行與下一行。
const IGNORE_MARKER = /\/\/\s*l10n-ignore:\s*\S/;

const BACKSLASH = String.fromCharCode(92);

/**
 * 掃描 Dart 原始碼，回傳字串字面值清單與「註解已被抹除」的程式碼副本。
 *
 * 之所以不用單純的正則剝除註解：本專案註解一律是中文（例如 `// Text('確定') 按鈕`），
 * 而字串內也可能出現 `//`（例如 'http://…'），必須「邊掃邊分辨目前在字串還是註解」，
 * 才不會把註解誤判為字串、或把 URL 後半段誤當成註解。
 * 字串插值 `${ ... }` 內可再出現同種引號的巢狀字串，也在此一併處理。
 */
function tokenize(src) {
  const literals = [];
  const ignoreLines = new Set();
  const code = src.split(''); // 註解會被空白抹除（保留換行以維持行號）
  const n = src.length;
  let line = 1;

  function blank(from, to) {
    for (let k = from; k < to; k++) if (code[k] !== '\n') code[k] = ' ';
  }

  // i 位於開頭引號；回傳結束引號之後的索引。會遞迴處理 ${ ... } 內的巢狀字串。
  function readString(i) {
    const quote = src[i];
    const isRaw = i > 0 && src[i - 1] === 'r' && !/\w/.test(src[i - 2] || ' ');
    const triple = src.startsWith(quote.repeat(3), i);
    const q = triple ? quote.repeat(3) : quote;
    const start = i;
    const startLine = line;
    i += q.length;
    while (i < n) {
      const c = src[i];
      if (!isRaw && c === BACKSLASH) { i += 2; continue; }
      if (src.startsWith(q, i)) { i += q.length; break; }
      if (c === '\n') { line++; if (!triple) break; }
      if (!isRaw && c === '$' && src[i + 1] === '{') {
        i += 2;
        let depth = 1;
        while (i < n && depth > 0) {
          const d = src[i];
          if (d === '\n') line++;
          if (d === "'" || d === '"') { i = readString(i); continue; }
          if (d === '{') depth++;
          else if (d === '}') depth--;
          i++;
        }
        continue;
      }
      i++;
    }
    literals.push({ start, end: i, line: startLine, raw: src.slice(start, i) });
    return i;
  }

  let i = 0;
  while (i < n) {
    const c = src[i];
    const c2 = src[i + 1];
    if (c === '\n') { line++; i++; continue; }
    if (c === '/' && c2 === '/') {
      const s = i;
      while (i < n && src[i] !== '\n') i++;
      if (IGNORE_MARKER.test(src.slice(s, i))) { ignoreLines.add(line); ignoreLines.add(line + 1); }
      blank(s, i);
      continue;
    }
    if (c === '/' && c2 === '*') {
      const s = i;
      let depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (src[i] === '\n') line++;
        if (src[i] === '/' && src[i + 1] === '*') { depth++; i += 2; }
        else if (src[i] === '*' && src[i + 1] === '/') { depth--; i += 2; }
        else i++;
      }
      blank(s, i);
      continue;
    }
    if (c === "'" || c === '"') { i = readString(i); continue; }
    i++;
  }
  literals.sort((a, b) => a.start - b.start);
  return { literals, code: code.join(''), ignoreLines };
}

/** 字面值去掉引號後的內容（含 r 前綴與三引號）。 */
function innerText(raw) {
  const m = raw.match(/^r?('''|"""|'|")/);
  const q = m ? m[1] : '';
  return raw.slice(m ? m[0].length : 0, raw.length - (raw.endsWith(q) ? q.length : 0));
}

/**
 * 找出一份 Dart 原始碼中的違規：Widget 字串參數位置、含中文、未被例外。
 * @returns {{line:number, text:string}[]}
 */
function findViolations(src) {
  const { literals, code, ignoreLines } = tokenize(src);
  const violations = [];
  let prev = null; // 前一個字面值（相鄰字串串接時沿用其位置判斷）
  let prevPositional = false;
  for (const lit of literals) {
    // 巢狀（插值內）字面值已被外層字面值涵蓋，不獨立判斷
    if (prev && lit.start < prev.end) continue;
    const before = code.slice(Math.max(0, lit.start - 200), lit.start);
    let inUiPosition = UI_POSITION.test(before);
    // Dart 相鄰字串串接：'a' 'b中'，後段沿用前段的位置
    if (!inUiPosition && prev && /^\s*$/.test(code.slice(prev.end, lit.start))) {
      inUiPosition = prevPositional;
    }
    prev = lit;
    prevPositional = inUiPosition;
    if (!inUiPosition || !CJK.test(lit.raw)) continue;
    if (ALLOWED_LITERAL_VALUES.has(innerText(lit.raw))) continue;
    if (ignoreLines.has(lit.line)) continue;
    violations.push({ line: lit.line, text: lit.raw.replace(/\s+/g, ' ').slice(0, 60) });
  }
  return violations;
}

function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith('.dart')) out.push(full);
  }
}

/** 掃描整個 lib 目錄，回傳 {file, line, text}[]（file 為相對 libDir、以 / 分隔）。 */
function scanLibDir(libDir) {
  const files = [];
  walk(libDir, files);
  const results = [];
  for (const file of files) {
    const rel = path.relative(libDir, file).split(path.sep).join('/');
    if (rel.startsWith('l10n/')) continue; // gen-l10n 產生檔與 ARB 字典本身
    if (SKIP_FILES.has(rel)) continue;
    for (const v of findViolations(fs.readFileSync(file, 'utf8'))) {
      results.push({ file: rel, ...v });
    }
  }
  return results;
}

function main(argv) {
  const i = argv.indexOf('--lib-dir');
  const libDir = i >= 0 ? path.resolve(argv[i + 1]) : path.resolve(__dirname, '..', 'lib');
  const results = scanLibDir(libDir);
  if (results.length === 0) {
    console.log('PASS：未發現未經 AppLocalizations 包裝的硬編碼中文字串');
    return 0;
  }
  console.error(`發現 ${results.length} 處未經 AppLocalizations 包裝的硬編碼中文字串：`);
  for (const r of results) console.error(`  lib/${r.file}:${r.line}  ${r.text}`);
  console.error('\n修法：改用 AppLocalizations（ARB key）；若確屬合法例外，於該行或上一行加 `// l10n-ignore: <理由>`。');
  return 1;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));

module.exports = { findViolations, scanLibDir };
```

- [ ] **Step 4：執行測試，確認全部通過**

Run（於 `app/` 目錄下）：`node tool/test_check_l10n_hardcoded_strings.mjs`
Expected：輸出 `check_l10n_hardcoded_strings：全部測試通過`，exit code 0。

- [ ] **Step 5：Commit（於 repo 根目錄執行）**

```bash
git add app/tool/check_l10n_hardcoded_strings.js app/tool/test_check_l10n_hardcoded_strings.mjs
git commit -m "feat(epic-45): 新增 check_l10n_hardcoded_strings.js 防遺漏稽核腳本與單元測試"
```

- [ ] **Step 6：變異驗證——確認測試不是空轉（做完立即還原，不 commit）**

對已 commit 的 `check_l10n_hardcoded_strings.js` 依序做下列四種破壞性修改，**每次改完跑 Step 4 指令，必須看到 `AssertionError`（測試失敗）**，確認後執行 `git checkout -- app/tool/check_l10n_hardcoded_strings.js` 還原，再做下一項：

1. 把 `readString()` 內處理 `${` 的整個 `if (!isRaw && c === '$' && src[i + 1] === '{') { ... }` 條件改成 `if (false) {`（關掉插值巢狀處理）→ 預期「字串插值內含同種引號」測試失敗（Review Focus #3）。
2. 把 `findViolations()` 內 `inUiPosition = prevPositional;` 改成 `inUiPosition = false;`（關掉相鄰字串沿用）→ 預期「相鄰字串串接」測試失敗（Review Focus #7）。
3. 把 `tokenize()` 內兩處 `blank(s, i);` 都改成註解掉（不抹除註解）→ 預期「關鍵字與字串之間夾著註解」測試失敗（Review Focus #4）。
4. 把 `UI_POSITION` 兩處結尾的 `r?` 都拿掉（例如 `(?:const\s+)?r?' +` 改成 `(?:const\s+)?' +`，`(?:const\s+)?r?)$` 改成 `(?:const\s+)?)$`）→ 預期「Dart 原始字串（r 前綴）」測試失敗（Review Focus #9）。

全部還原後，`git status` 應顯示工作樹乾淨，再跑一次 Step 4 指令確認回到全綠。

---

### Task 2：對真實 `app/lib/` 稽核並修正真陽性漏網字串

**Files:**
- Modify: `app/lib/l10n/app_zh_TW.arb`（新增 1 個 key，含 `@` 描述）
- Modify: `app/lib/l10n/app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`（各新增 1 個 key，無 `@` 描述）
- Modify: `app/lib/l10n/app_localizations.dart`／`app_localizations_en.dart`／`app_localizations_zh.dart`（`flutter gen-l10n` 產生，不手改）
- Modify: `app/lib/screens/reader_settings_sheet.dart:590-591`、`:671`
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes：Task 1 的 CLI（`node tool/check_l10n_hardcoded_strings.js`）；既有 ARB key `readerSettingsColumnSingleLabel`（`單欄`／`单栏`／`Single`）與既有測試 helper `_pumpSheet(..., locale:)`、`switchToTab(tester, tabLabel)`（皆在 `reader_settings_sheet_test.dart` 內，`switchToTab` 為頂層函式）。
- Produces：新 ARB key `readerSettingsFontFamilyLabel`（`字型`／`字体`／`Font`），供 `AppLocalizations.of(context)!.readerSettingsFontFamilyLabel` 使用。

**背景**：Task 1 完成後對真實 `app/lib/` 執行腳本，預期恰好報出 1 處真陽性 `reader_settings_sheet.dart:671`（`字型` 下拉選單左側標籤，Issue 4 抽字串時遺漏）。同一檔案 `:590-591` 的欄數「單欄」選項因位於 record 位置參數而未被腳本抓到（Review Focus #1），但經稽核實測基礎盤點確認為同性質遺漏，且 ARB key 早已存在，順手修正。**ARB 現況**：四份 ARB 皆為 549 個 key、完全同步（撰寫本計畫時以 Node 逐檔計數驗證）；`app_zh.arb` 內容與 `app_zh_TW.arb` 的值相同、不含 `@key` 描述（同 `plan-issue-7.md`／`plan-issue-8.md` 既有作法）。

- [ ] **Step 1：對真實 `app/lib/` 執行稽核腳本，確認基準**

Run（於 `app/` 目錄下）：`node tool/check_l10n_hardcoded_strings.js`
Expected：exit code 1，輸出**恰好** 1 處：`lib/screens/reader_settings_sheet.dart:671  '字型'`。
若出現其他警報：**停下來**，逐一對照上方「稽核實測基礎」表判斷是真漏網（回報人類、比照本 Task 修正）還是假警報（回頭修 Task 1 的腳本或補排除清單），不可直接加 `// l10n-ignore` 掩蓋。

- [ ] **Step 2：撰寫失敗的 widget 測試（紅燈）**

在 `app/test/screens/reader_settings_sheet_test.dart` 的 `main()` 結尾（緊接在 `'英文介面下四個分頁籤標題與版面設定標題正確以英文渲染'` 測試之後、`main()` 的結尾 `}` 之前）新增三個測試：

```dart
  testWidgets('正體中文介面下字型標籤與欄數「單欄」選項正確渲染', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    expect(find.text('字型'), findsOneWidget);

    await switchToTab(tester, '呈現');
    expect(
      find.descendant(
        of: find.byKey(const Key('reader_settings_column_mode_single')),
        matching: find.text('單欄'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('簡體中文介面下字型標籤與欄數「单栏」選項正確以簡體渲染', (tester) async {
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      locale: const Locale('zh', 'CN'),
    );

    expect(find.text('字体'), findsOneWidget);
    expect(find.text('字型'), findsNothing);

    await switchToTab(tester, '呈现');
    expect(
      find.descendant(
        of: find.byKey(const Key('reader_settings_column_mode_single')),
        matching: find.text('单栏'),
      ),
      findsOneWidget,
    );
    expect(find.text('單欄'), findsNothing);
  });

  testWidgets('英文介面下字型標籤與欄數「Single」選項正確以英文渲染', (tester) async {
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      locale: const Locale('en'),
    );

    expect(find.text('Font'), findsOneWidget);
    expect(find.text('字型'), findsNothing);

    await switchToTab(tester, 'Display');
    expect(
      find.descendant(
        of: find.byKey(const Key('reader_settings_column_mode_single')),
        matching: find.text('Single'),
      ),
      findsOneWidget,
    );
    expect(find.text('單欄'), findsNothing);
  });
```

- [ ] **Step 3：執行測試，確認新增的三個測試中，簡體與英文兩個失敗**

Run（於 `app/` 目錄下）：`flutter test test/screens/reader_settings_sheet_test.dart --plain-name "介面下字型標籤與欄數"`
Expected：正體中文測試 PASS（現況硬編碼恰好是正體）；簡體中文與英文測試 FAIL（找不到 `字体`／`Font`，或仍找到 `字型`／`單欄`）。

- [ ] **Step 4：新增 ARB key（四份檔案）**

`app/lib/l10n/app_zh_TW.arb`：找到既有的 `readerSettingsUseBookFontLabel` 條目（含其 `@` 描述區塊）：

```json
  "readerSettingsUseBookFontLabel": "使用書本內建字型",
  "@readerSettingsUseBookFontLabel": {
    "description": "字型下拉選單「使用書本內建字型」選項（不指定自訂字型）"
  },
```

在其**正下方**（`readerSettingsColumnCountLabel` 之前）插入：

```json
  "readerSettingsFontFamilyLabel": "字型",
  "@readerSettingsFontFamilyLabel": {
    "description": "版面設定「文字」分頁中字型下拉選單左側的標籤"
  },
```

`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`（皆無 `@` 描述區塊，`readerSettingsUseBookFontLabel` 位於第 270 行）：在該行**正下方**分別插入一行：

```json
  "readerSettingsFontFamilyLabel": "字体",
```
（`app_zh_CN.arb`）

```json
  "readerSettingsFontFamilyLabel": "Font",
```
（`app_en.arb`）

```json
  "readerSettingsFontFamilyLabel": "字型",
```
（`app_zh.arb`）

- [ ] **Step 5：重新產生 `AppLocalizations` 並驗證 key 數量同步**

Run（於 `app/` 目錄下）：`flutter gen-l10n`
Expected：無錯誤；`git status` 顯示 `app/lib/l10n/app_localizations.dart`／`app_localizations_en.dart`／`app_localizations_zh.dart` 有異動。

Run（於 `app/` 目錄下）：
```bash
node -e "['zh_TW','zh_CN','en','zh'].forEach(f=>{const d=JSON.parse(require('fs').readFileSync('lib/l10n/app_'+f+'.arb','utf8'));console.log(f,Object.keys(d).filter(k=>!k.startsWith('@')).length)})"
```
Expected：四行皆為 `550`（549 + 1）。

- [ ] **Step 6：修正 `reader_settings_sheet.dart` 的三處硬編碼**

`app/lib/screens/reader_settings_sheet.dart:586-592`（`_buildColumnModeRow()` 內 `ColumnMode.single` 那筆 record，tuple 最後兩個欄位分別是 tooltip 與 label，兩者同字串，比照相鄰 `auto`／`double` 兩筆的寫法）：

```dart
// 修改前
                  (
                    ColumnMode.single,
                    'single',
                    Icons.crop_portrait,
                    '單欄',
                    '單欄',
                  ),

// 修改後
                  (ColumnMode.single, 'single', Icons.crop_portrait, l10n.readerSettingsColumnSingleLabel, l10n.readerSettingsColumnSingleLabel),
```

`app/lib/screens/reader_settings_sheet.dart:671`（`_buildFontFamilyDropdown()`，該方法開頭已宣告 `final l10n = AppLocalizations.of(context)!;`）：

```dart
// 修改前
          const Text('字型', style: TextStyle(fontWeight: FontWeight.bold)),

// 修改後
          Text(l10n.readerSettingsFontFamilyLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
```

- [ ] **Step 7：執行測試與靜態分析，確認全數通過**

Run（於 `app/` 目錄下）：`flutter test test/screens/reader_settings_sheet_test.dart test/l10n`
Expected：全數 PASS（含 Step 2 新增的 3 個測試；既有 `'單欄'`／`'雙欄'` 斷言仍通過，因為 zh_TW 譯文與原硬編碼相同）。

Run（於 `app/` 目錄下）：`flutter analyze`
Expected：`No issues found!`

Run（於 `app/` 目錄下）：`node tool/check_l10n_hardcoded_strings.js`
Expected：輸出 `PASS：未發現未經 AppLocalizations 包裝的硬編碼中文字串`，exit code 0。

- [ ] **Step 8：Commit（於 repo 根目錄執行）**

```bash
git add app/lib/l10n app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "fix(epic-45): 稽核發現版面設定「字型」標籤與欄數「單欄」選項漏網，補齊三語言"
```

---

### Task 3：驗收與文件收尾

**Files:**
- Modify: `app/tool/README.md`（新增稽核腳本章節）
- Modify: `CLAUDE.md`（「常用指令」新增一行；見「需人類確認的設計決定」#4，可依審查意見刪除）
- Modify: `AGENTS.md`（「Commands」新增一行；同上）
- Modify: `docs/epics/epic-45-interface-i18n/issues.md`（Issue 10 標記 `completed`，補記實際執行範圍）
- Modify: `docs/epics/epic-45-interface-i18n/epic.md`（新增開發記錄與最終稽核結果）
- Modify: `docs/epics.md`（Epic 46 備註）

**Interfaces:**
- Consumes：Task 1／2 全部異動。
- Produces：無（本 Issue 最後一個 Task）。

- [ ] **Step 1：驗收——人為植入一個硬編碼字串必須被抓到（在 `lib` 副本上進行，不動真實原始碼）**

Run（於 `app/` 目錄下；純 Node 單行指令，Bash 與 PowerShell 皆可直接貼上執行，不依賴 `mktemp`／`cp`／`printf`；植入檔只寫在系統暫存目錄的 `lib` 副本，用完自動刪除）：
```bash
node -e "const fs=require('fs'),path=require('path'),os=require('os'),cp=require('child_process');const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'planted-'));const lib=path.join(tmp,'lib');fs.cpSync('lib',lib,{recursive:true});const Q=String.fromCharCode(39),NL=String.fromCharCode(10);fs.writeFileSync(path.join(lib,'screens','zz_planted.dart'),['a();','Widget w() => const Text('+Q+'人為植入的硬編碼字串'+Q+');'].join(NL));const r=cp.spawnSync(process.execPath,['tool/check_l10n_hardcoded_strings.js','--lib-dir',lib],{encoding:'utf8'});console.log(r.stderr.trim());console.log('exit='+r.status);fs.rmSync(tmp,{recursive:true,force:true})"
```
Expected：stderr 輸出 `發現 1 處未經 AppLocalizations 包裝的硬編碼中文字串：` 與 `  lib/screens/zz_planted.dart:2  '人為植入的硬編碼字串'` 形式的一行，`exit=1`。

- [ ] **Step 2：完整驗證（本 Issue 唯一一次完整 `flutter test`）**

Run（於 `app/` 目錄下）：`node tool/test_check_l10n_hardcoded_strings.mjs`
Expected：`check_l10n_hardcoded_strings：全部測試通過`

Run（於 `app/` 目錄下）：`node tool/check_l10n_hardcoded_strings.js`
Expected：`PASS：未發現未經 AppLocalizations 包裝的硬編碼中文字串`，exit 0。

Run（於 `app/` 目錄下）：`flutter analyze`
Expected：`No issues found!`

Run（於 `app/` 目錄下）：`flutter test`
Expected：全數 PASS（與 Issue 9 合併後基準 `+2763 ~1` 比對，僅新增 Task 2 的 3 個測試；若 `download_queue_controller_test.dart` 在並行執行下偶發失敗，單獨重跑確認通過即可，該項已於 Issue 9 記錄為既有 flaky，非本 Issue 引入）。

- [ ] **Step 3：`app/tool/README.md` 新增稽核腳本章節**

在檔案第一個 `##` 章節（`check_foliate_es_compat.js`）之前新增：

````markdown
## `check_l10n_hardcoded_strings.js`

掃描 `app/lib/**/*.dart`，找出「Widget 字串參數位置」上**含中文字元且未經
`AppLocalizations` 包裝**的字串字面值（`Text('確定')`、`title: '設定'`、
`tooltip:`／`label:`／`hintText:` 等），防止畫面遺漏在地化與日後新增畫面忘記
包裝（`epic-45-interface-i18n` Issue 10，規則契約見該 Epic `spec.md` §9）。

### 何時該執行

- **新增或修改任何畫面字串（Widget 樹內的文字）的 Issue，提交前**跑一次。
- 目前**沒有接進 CI**（這個 repo 尚未設定任何 CI pipeline，與
  `check_foliate_es_compat.js` 現況一致）。之後若要接進 CI，直接把下面的執行
  指令包進 workflow 步驟即可。

### 執行方式

不需要 `npm install`，只用 Node.js 內建模組：

```bash
node app/tool/check_l10n_hardcoded_strings.js
# 測試／驗收時可指定其他目錄：
node app/tool/check_l10n_hardcoded_strings.js --lib-dir <目錄>
```

- 結束碼 `0`：乾淨。
- 結束碼 `1`：至少一處未包裝，會印出 `lib/<檔案>:<行號>  <字串>`。

單元測試：`node app/tool/test_check_l10n_hardcoded_strings.mjs`。

### 找到問題時怎麼修

1. 在 `app/lib/l10n/app_zh_TW.arb`（模板，含 `@` 描述）與 `app_zh_CN.arb`／
   `app_en.arb`／`app_zh.arb` 新增對應 key（四份 key 集合必須一致），執行
   `cd app && flutter gen-l10n`。
2. 該處改用 `AppLocalizations.of(context)!.<key>`，並補上 zh_CN／en 兩個
   locale 的 widget test。
3. 若確屬合法例外（不需翻譯的專有名詞、資料、刻意的 fallback），在該行或上一
   行加 `// l10n-ignore: <理由>`（**必須寫理由**，空標記無效）；整檔例外或專有
   名詞值則加進腳本的 `SKIP_FILES`／`ALLOWED_LITERAL_VALUES` 並註明理由。

### 已知限制

只偵測 spec §9 定義的「Widget 字串參數位置」：`Text(`／`SelectableText(` 的第
一個位置參數，以及 `tooltip`／`label`／`title`／`subtitle`／`text`／
`labelText`／`hintText`／`helperText`／`errorText`／`counterText`／
`prefixText`／`suffixText`／`content`／`message`／`semanticLabel`／
`semanticsLabel` 等具名參數後**直接緊接**的字串字面值（含 Dart 相鄰字串串接）。
**掃不到**：

- `record`／位置參數中的字串（例如 `(ColumnMode.single, 'single', icon, '單欄')`）。
- `?? '中文'` fallback，以及 model 層字串（例如 `TtsVoice.displayName`、
  `Bookmark.defaultName()`、OPDS 解析失敗的預設標題）。
- 例外訊息、`assert`、`debugPrint` 等開發者診斷字串（設計上刻意不涵蓋，見
  `design.md`「Console Log／診斷內容翻譯」）。

這類遺漏仍需靠 code review 與人工盤點；本腳本只保證「最常見的 Widget 字串參數
位置」不會再漏。
````

- [ ] **Step 4：`CLAUDE.md`「常用指令」與 `AGENTS.md`「Commands」各新增一行（見「需人類確認的設計決定」#4，可依審查意見刪除）**

在 `CLAUDE.md`「常用指令」小節的 `flutter analyze` 那一組（`# 提交前必須乾淨（"No issues found!"）` 與 `flutter analyze`）之後新增：

```bash

# 新增/修改畫面字串後，提交前跑一次：偵測 Widget 字串參數位置上未經 AppLocalizations
# 包裝的硬編碼中文字串（純 Node，免安裝；見 app/tool/README.md）
node tool/check_l10n_hardcoded_strings.js
```

`AGENTS.md`「Commands」小節（第 90 行起的 bash 程式碼區塊，每行以 `#` 對齊註解）在 `flutter analyze` 那一行之後新增一行：

```bash
node tool/check_l10n_hardcoded_strings.js       # 新增/修改畫面字串後、提交前：偵測未經 AppLocalizations 包裝的硬編碼中文字串
```

- [ ] **Step 5：更新 `issues.md` Issue 10 段落**

在 `docs/epics/epic-45-interface-i18n/issues.md` 的 `## Issue 10：防遺漏稽核腳本` 段落，把 `**Status:** ready-for-agent` 改為 `**Status:** completed`，並在「依賴」之後、「背景」之前插入：

```markdown
**實際執行範圍修正記錄（2026-09-24 認領時對 `app/lib/` 實跑掃描盤點）**：以字串感知掃描盤點 `app/lib/`（排除 `l10n/`）共 38 個檔案 14,992 個含中文字面值，其中 `reader/text_conversion_dict.dart` 占 14,894 個（整檔略過），其餘 37 個檔案 98 個字面值分類為：A 真漏網 3（本 Issue 修正）、B 合法 23、C 開發者診斷 63、D 使用者可見但不在 Widget 字串參數位置 9（見 `epic.md` 最終稽核結果，另案處理）。規則維持 `spec.md` §9 的「Widget 字串參數位置」而未擴大；排除機制實作為 `SKIP_FILES`（`text_conversion_dict.dart`、`book_group.dart`）＋`ALLOWED_LITERAL_VALUES`（5 款內建字型品牌名）＋行內 `// l10n-ignore: <理由>`；**不接入 CI**（repo 無任何 CI 設定），改由 `CLAUDE.md`「常用指令」、`AGENTS.md`「Commands」與 `app/tool/README.md` 記載執行時機。稽核實跑報出 1 處真陽性 `reader_settings_sheet.dart:671`「字型」標籤（新增 ARB key `readerSettingsFontFamilyLabel`，四份 ARB 549→550），並人工盤點另發現同檔 `:590-591`「單欄」×2 漏換（既有 key `readerSettingsColumnSingleLabel`），一併修正。
```

- [ ] **Step 6：更新 `epic.md`（最終稽核結果）**

在 `docs/epics/epic-45-interface-i18n/epic.md` 末尾新增一則開發記錄段落：

```markdown

**2026-09-24 完成 Issue 10 實作（`plans/plan-issue-10.md` 3 個 Task 全數落地）**：防遺漏稽核腳本——新增 `app/tool/check_l10n_hardcoded_strings.js`（字串感知詞法掃描，含 `${}` 巢狀插值、註解抹除、相鄰字串串接、CRLF；例外機制為 `SKIP_FILES`／`ALLOWED_LITERAL_VALUES`／行內 `// l10n-ignore: <理由>`）與 `app/tool/test_check_l10n_hardcoded_strings.mjs`（單元測試含 4 項變異驗證確認測試非空轉，含計畫審查抓到的 Dart 原始字串 `r'…'` 漏檢死角；人為植入字串驗收於 `lib` 副本，確認被抓到且 exit 1）；不接 CI（repo 無 CI 設定），執行時機記於 `app/tool/README.md`、`CLAUDE.md`「常用指令」與 `AGENTS.md`「Commands」。**本 Epic 全部既有畫面字串抽取工作於 Issue 3-9 完成後的最終稽核結果**（對 `app/lib/` 排除 `l10n/` 與字典檔，共 37 個檔案 98 個含中文字面值）：**A 真漏網 3 處已於本 Issue 修正**（`reader_settings_sheet.dart`「字型」標籤，新增 ARB key `readerSettingsFontFamilyLabel`；「單欄」×2，既有 key `readerSettingsColumnSingleLabel`）；**B 合法 23 處**（內建字型品牌名 10、`BookGroup` Sentinel 3、簡繁字形 4、章節正則 1、合成 EPUB XHTML 範本 3、JS polyfill 1、`eb_sheet_shell.dart` 刻意保留的「關閉」fallback 1）；**C 開發者診斷 63 處**（例外／`assert`／`debugPrint`／`ReaderConsoleLog`，`design.md` 明訂不涵蓋）；**D 使用者可見但不在 Widget 字串參數位置、稽核腳本掃不到、本 Epic 未處理 9 處**：`Bookmark.defaultName()`「第 N 頁」／「N% 處」／「書籤」×3（`spec.md` §7 明文排除）、`main.dart:179` Android 通知頻道名稱「朗讀播放中」、`tts_provider.dart:37` `TtsVoice.systemDefault.displayName`「系統預設語音」（顯示於 TTS 語音選單）、`opds_feed_parser.dart`「未命名分類」×2／「未知書名」×1（遠端目錄缺 `<title>` 的 fallback）、`wifi_transfer_http_server.dart:303`「(未知檔名)」。D 類各自需要獨立設計決定（固化 vs 動態產生、無 `BuildContext`、model 層字串），建議另立 Issue／後續 Epic 處理，是否立案由人類決定。驗證：`flutter analyze` 乾淨、全套 `flutter test` 通過、稽核腳本對 `app/lib/` 零警報。下一步：本 Epic Issue 0-10 全數完成，待人類決定 D 類是否立案，之後歸檔。
```

- [ ] **Step 7：更新 `docs/epics.md` 備註**

`docs/epics.md` 中 Epic 46（`epic-45-interface-i18n`）該列備註由 `Issue 0-9 已完成，待認領 Issue 10` 改為 `全數完成，待歸檔`。

- [ ] **Step 8：Commit（於 repo 根目錄執行）**

```bash
git add app/tool/README.md CLAUDE.md AGENTS.md docs/epics/epic-45-interface-i18n/issues.md docs/epics/epic-45-interface-i18n/epic.md docs/epics.md
git commit -m "docs(epic-45): 標記 Issue 10 為 completed，記錄最終稽核結果並更新 epic.md"
```
