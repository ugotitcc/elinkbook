# Issue 34：直排欄間隔與頁高不一致（舊 WebView）補償實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 在 Chrome 91 這類舊 WebView 上，直排分頁模式的「欄間隔」回到等於「頁高」，翻頁不再累積錯位，畫面不再出現「上一頁尾巴＋下一頁開頭」的上下兩欄。新版 WebView 完全不受影響。

**Architecture：** 新增零 DOM 依賴的純函式模組 `column-pitch.js`（量測、算下一個 `max-height`、迭代驅動，可用 Node 直接測）。`main.js` 在每個章節文件載入時對根元素 `style` 屬性掛 `MutationObserver`，被 `paginator.js` 改寫後重新量測並補償。不改任何 vendored 檔案。

**Tech Stack：** 原生 ES module（WebView 內，Chromium 83 語法下限）、Node 純邏輯測試腳本、Puppeteer 測試台（Chromium 156 模擬舊引擎）、adb 真機驗證。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 34 設計決策」（決策 1～10）與「開發記錄」2026-10-25 Issue 34 診斷。詞彙「頁高」「欄間隔」見 `CONTEXT.md`。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **不改 vendored 檔案**（決策 2）：`paginator.js`、`view.js`、`progress.js`、`fixed-layout.js` 等一行都不動；Task 5 以 `git diff main -- app/android/app/src/main/assets/foliate/{paginator,view,progress,fixed-layout,epub,epubcfi,overlayer,comic-book,mobi,text-walker,section-chunks}.js` 為空來確認。
- **目標值**：`target = renderer.size / (renderer.columnCount || 1)`；容許誤差 `PITCH_TOLERANCE = 1.5`（CSS px）；最多調整 `MAX_COMPENSATION_ITERATIONS = 4` 次。
- **調整方式**（決策 3）：只改根元素 `max-height`，一律 `setProperty(..., 'important')`；放棄時還原成 `none`（同樣 `important`）。新值 = `base − 誤差`：第一次的 `base` = `min(根元素高度, 欄長)`（舊引擎單欄兩者相等 → 927.5；舊引擎雙欄欄長 499.7 → 427.7，真機已驗證都 1 步收斂）；之後的 `base` = 上一次實際設定的值（`max-height` 與欄間隔斜率為 1，用來修正第一次的偏差，例如新版引擎模擬時第一次會多扣內距 72，第二次補回）。決策 3 原寫「目前根元素高度 − 誤差」，雙欄實測會失效，以本條為準，並已回寫 `epic.md`。
- **範圍**（決策 5）：只處理「直排（computed `writing-mode` 以 `vertical` 開頭）＋ 分頁（`renderer.scrolled` 為 false）＋ 非固定版面（`view.isFixedLayout` 為 false）」。橫排、捲動模式、固定版面（FXL／CBZ）、少於 2 個欄矩形的章節一律不動作。固定版面必須明確排除：同步後的 `fixed-layout.js` 也有 `scrolled`、`columnCount` 成員（`scrolled` 可為 `false`），不能靠「該成員不存在」來排除（審查 I-1）。
- **數值守衛**（審查 I-2、I-3）：`measureColumnPitch` 取相鄰差的絕對值，`pitch <= 0` 回 `null`；新的 `max-height` 必須通過 `isValidMaxHeight`（有限且大於 0），否則視為無法收斂。`nextMaxHeight` 回 `null` 只代表「誤差在容許內」，不可兼作「數值無效」。
- **警告**（決策 6）：放棄時 `console.warn` 同一次載入只一次（模組層級旗標）。
- **JS 語法下限 Chromium 83**：`main.js` 與 `column-pitch.js` 禁用 `??=`、`||=`、`&&=`、`.at()`、`.replaceAll()`、`Object.hasOwn()`、`structuredClone`。`?.` 與 `??` 可用（`main.js` 既有）。
- **Node 執行**：Bash 工具的 PATH 沒有 Node；跑 Node 一律用 PowerShell 工具，先 `$env:PATH = "$env:PNPM_HOME;$env:PATH"`。
- **Windows**：多數原始檔是 CRLF；Edit 的定位字串不要含換行；`python` 編輯以位元組讀寫、先數 `\r\n` 與 `\n` 的多寡再決定換行符，不要整份重寫。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑被觸及的測試；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，只跑一個）。
- **Commit**：不加 `Co-Authored-By`；結尾加 `Claude-Session: https://claude.ai/code/session_019bmfxQJ1gaKoHGoWH7gJwD`。每個 Task 一個 commit。
- **分支**：沿用 `epic-54/issue-34-column-pitch`（已含設計文件提交 `2e369c5d`）；計畫與實作同分支同 PR。

## Review Focus

1. **新版引擎被誤動。** 欄間隔已等於頁高時，不得寫入任何 `max-height`。→ Task 1 案例 b、Task 2 步驟 1。
2. **單頁章節。** 只有 1 個欄矩形，無法量測；不得丟例外、不得寫入樣式。→ Task 1 案例 a。
3. **雙欄／自動欄數。** 目標是 `size / columnCount`，不是 `size`；且第一次的 base 必須用欄長而不是根元素高度。→ Task 1 案例 c2（用真機量到的 571.7／499.7，預期 427.7）與 c3。
4. **被 `paginator.js` 重排覆寫後無法再補償，或造成無窮迴圈。** 重排會把 `max-height` 重設為 `none`。→ Task 2 步驟 3（重排後再次補償）與 style 變動次數上限。
5. **無法收斂或數值無效。** 4 次後仍超出容許誤差、量測消失、或算出非正數的 `max-height` 時，要還原 `none` 並只警告一次，不能留下半調整狀態，也不能把根元素壓成 0 高度。→ Task 1 案例 d、e、h。
6. **固定版面與已銷毀的文件。** FXL／CBZ 不得掛補償；觀察者回呼執行時 iframe 可能已被移除（`doc.defaultView` 為 `null`），不得丟例外。→ Task 2 步驟 3 的前置條件與回呼首行守衛，Task 4 步驟 5 回歸 CBZ／FXL。

---

### Task 1：`column-pitch.js` 純函式與 Node 測試

**Files：**
- Create: `app/android/app/src/main/assets/foliate/column-pitch.js`
- Create: `app/tool/test_column_pitch.mjs`
- Modify: `app/tool/README.md`（工具清單加一行）

**Interfaces：**
- Produces（Task 2 的 `main.js` 依賴）：
  - `export const PITCH_TOLERANCE = 1.5`、`export const MAX_COMPENSATION_ITERATIONS = 4`
  - `export function measureColumnPitch(rects: Array<{top:number,left:number,height:number,width:number}>, vertical: boolean): { pitch: number, columnLength: number } | null` — 直排取相鄰兩矩形 `top` 差的絕對值與第一個的 `height`；橫排取 `left` 差的絕對值與 `width`（橫排 RTL 的 `left` 會遞減）；少於 2 個矩形、或 `pitch <= 0` 回 `null`。
  - `export function isValidMaxHeight(px: number): boolean` — `Number.isFinite(px) && px > 0`。
  - `export function nextMaxHeight(args: { pitch: number, target: number, base: number }): number | null` — `|pitch - target| < PITCH_TOLERANCE` 回 `null`；否則回 `base - (pitch - target)`。
  - `export function compensateColumnPitch(args: { target: number, measure: () => {pitch:number,columnLength:number}|null, getBoxHeight: () => number, setMaxHeight: (px:number) => void, resetMaxHeight: () => void }): { status: 'skipped' | 'ok' | 'compensated' | 'gave-up', iterations: number }`

- [ ] **步驟 1：寫失敗測試 `app/tool/test_column_pitch.mjs`**（比照 `test_tts_safe_window.mjs`：`node:assert/strict`、零依賴、結束碼 0／非 0）。案例（名稱用正體中文，斷言用下列數值）：
  - **a 單頁章節**：`measure` 回 `null` → `status === 'skipped'`、`setMaxHeight` 呼叫 0 次、`resetMaxHeight` 呼叫 0 次。
  - **b 新版引擎**：`measure` 回 `{pitch: 999.5, columnLength: 927.5}`、`target = 999.5` → `status === 'ok'`、`iterations === 0`、`setMaxHeight` 0 次。
  - **c 單欄舊引擎一步收斂**：`target = 999.5`、`getBoxHeight() = 999.5`；`measure` 第 1 次回 `{pitch: 1071.5, columnLength: 999.5}`，`setMaxHeight` 被呼叫後改回 `{pitch: 999.5, columnLength: 927.5}` → `setMaxHeight` 收到 `927.5`、`status === 'compensated'`、`iterations === 1`。
  - **c2 雙欄舊引擎一步收斂**：`target = 499.7`、`getBoxHeight() = 999.5`、第 1 次 `{pitch: 571.7, columnLength: 499.7}` → `setMaxHeight` 收到 `427.7`（用 `min(999.5, 499.7)` 當 base，不是 `927.5`）；之後模擬 `measure` 回 `pitch: 499.7` → `status === 'compensated'`、`iterations === 1`。
  - **c3 新版引擎被模擬成誤差（需兩次）**：`target = 999.5`、`getBoxHeight() = 999.5`、第 1 次 `{pitch: 1071.5, columnLength: 927.5}` → 第 1 次 `setMaxHeight` 收到 `855.5`；模擬量測改回 `pitch: 927.5`（斜率 1：`pitch = max-height + 72`）→ 第 2 次 `setMaxHeight` 收到 `927.5`（base 是上一次設定的 `855.5`，不是欄長）；再量 `pitch: 999.5` → `status === 'compensated'`、`iterations === 2`。
  - **d 無法收斂**：`measure` 永遠回 `{pitch: 1071.5, ...}` → `setMaxHeight` 恰好 4 次、`resetMaxHeight` 恰好 1 次、`status === 'gave-up'`。
  - **e 調整後無法再量測**：第 1 次回 `pitch = 1071.5`，`setMaxHeight` 之後 `measure` 回 `null` → `resetMaxHeight` 1 次、`status === 'gave-up'`。
  - **f 量測函式**：直排兩矩形 `top` 為 `0`、`1071.5`，`height` 為 `999.5` → `{pitch: 1071.5, columnLength: 999.5}`；橫排改用 `left`／`width`；只有 1 個矩形 → `null`。
  - **f2 量測的邊界**：橫排 RTL，兩矩形 `left` 為 `1000`、`500`（遞減）→ `pitch === 500`（取絕對值）；兩矩形 `top` 相同 → `null`（`pitch` 為 0）。
  - **g `nextMaxHeight`**：`{pitch: 1000, target: 999.5, base: 999.5}`（誤差 0.5）→ `null`；誤差正好 1.5 → 回數值（容許邊界不含）。
  - **h 算出非正數的高度**：`target = 999.5`、`getBoxHeight() = 50`、`measure` 回 `{pitch: 1071.5, columnLength: 50}`（算得 `50 − 72 = −22`）→ `setMaxHeight` 0 次、`resetMaxHeight` 恰好 1 次、`status === 'gave-up'`。另測 `isValidMaxHeight(0)`、`isValidMaxHeight(-22)`、`isValidMaxHeight(NaN)` 為 `false`，`isValidMaxHeight(927.5)` 為 `true`。
- [ ] **步驟 2：執行確認失敗**：PowerShell `node app/tool/test_column_pitch.mjs`，預期因找不到 `column-pitch.js` 而失敗（結束碼非 0）。
- [ ] **步驟 3：實作 `column-pitch.js`**。迭代規則：迴圈最多 `MAX_COMPENSATION_ITERATIONS` 輪；每輪先 `measure()`（第一輪回 `null` → `skipped`；之後回 `null` → 還原並 `gave-up`），再 `nextMaxHeight`（`base` = 上一次 `setMaxHeight` 的值；第一次調整前用 `Math.min(getBoxHeight(), columnLength)`）；為 `null` 即結束（第一輪結束為 `ok`，之後為 `compensated`，`iterations` = 已呼叫 `setMaxHeight` 的次數）；算出的值未通過 `isValidMaxHeight` 立即 `resetMaxHeight()` 並回 `gave-up`（不呼叫 `setMaxHeight`）；否則 `setMaxHeight`。調整滿 4 次後再量一次，仍超出容許誤差就 `resetMaxHeight()` 並回 `gave-up`。檔案開頭註解寫明：零 DOM 依賴、用途、與 `CONTEXT.md`「頁高／欄間隔」對應。
- [ ] **步驟 4：執行確認通過**：同指令，預期結束碼 0，輸出「全數通過」。
- [ ] **步驟 5：`app/tool/README.md` 加上 `test_column_pitch.mjs` 一行**（用途與用法，格式比照既有條目）。
- [ ] **步驟 6：Commit**：`git add app/android/app/src/main/assets/foliate/column-pitch.js app/tool/test_column_pitch.mjs app/tool/README.md`，訊息 `feat(foliate): 欄間隔補償純函式與測試（epic-54 Issue 34 Task 1）`。

---

### Task 2：測試台情境（先紅）＋ `main.js` 接線（轉綠）

**Files：**
- Create: `app/tool/foliate_touch_harness/scenario-column-pitch-compensation.mjs`
- Modify: `app/android/app/src/main/assets/foliate/main.js`（第 1～10 行 import 區加一行；`view.addEventListener('load', ...)` 約 1358 行附近呼叫掛接函式；檔尾前新增函式）

**Interfaces：**
- Consumes：Task 1 的 `compensateColumnPitch`、`PITCH_TOLERANCE`（`import` 自 `./column-pitch.js`）。
- Produces：`main.js` 內部函式 `attachColumnPitchCompensation(doc: Document): void`（不對外匯出；由 `'load'` 事件處理器呼叫，索引模式 `isIndexMode` 不呼叫）。

- [ ] **步驟 1：寫測試台情境（會失敗）**。`launchHarnessPage` 載入記憶體組的單章直排 EPUB（160 個段落，章節內以 `html{writing-mode:vertical-rl}` 宣告直排，比照 `scratchpad/diag/pitch.mjs` 的作法）、`viewport: { width: 749, height: 999 }`、`prefs: { fontSize: 1.75, marginTop: 32, marginBottom: 16, marginLeft: 24, marginRight: 24, columnMode: 'single' }`。檔案開頭註解寫明：Chromium 156 無法重現 Chrome 91 的誤差，改以 `column-gap` 加大 72 模擬同樣的欄間隔誤差（決策 8）。`report()` 檢查項（名稱用正體中文）：
  1. **前提**：未模擬誤差時，`body.getClientRects()` 相鄰欄起點差與 `renderer.size` 相差小於 1.5，且根元素 inline `max-height` 為 `none`（新版引擎不動作，Review Focus 1）。
  2. **模擬舊引擎**：對根元素 `style.setProperty('column-gap', '144px', 'important')`，等 800 ms，欄起點差與 `renderer.size` 相差小於 1.5，且 `max-height` 是小於頁高的 px 值（補償生效）。
  3. **重排後可再次補償**（Review Focus 4）：呼叫 `window.applyPreferences({ ...PREFS, writingMode: 'vertical', fontSize: 2.0 })`（paginator 會把 `max-height` 重設為 `none`、`column-gap` 回 72），等 800 ms，欄間隔等於頁高；再次注入 `column-gap: 144px`，等 800 ms，欄間隔仍等於頁高。
  4. **無窮迴圈防護**：補償完成後掛一個計數用 `MutationObserver` 觀察根元素 `style` 屬性 1500 ms，變動次數小於 10。
  5. **無未捕捉例外**：`pageErrors.length === 0`。
- [ ] **步驟 2：執行確認失敗**：PowerShell 在 `app/tool/foliate_touch_harness` 執行 `node scenario-column-pitch-compensation.mjs`，預期檢查項 2、3 FAIL（尚未接線）。
- [ ] **步驟 3：`main.js` 實作 `attachColumnPitchCompensation(doc)`**：
  - 前置條件不符就不掛觀察者、不量測：`view.isFixedLayout` 為真（FXL／CBZ，審查 I-1）、橫排、捲動、`renderer.size` 不大於 0。`vertical` 以 `doc.defaultView.getComputedStyle(doc.documentElement).writingMode` 判斷；分頁以 `view.renderer.scrolled === false` 判斷。
  - 觀察者回呼首行：`doc.defaultView`、`doc.documentElement`、`doc.body` 任一為 `null`（iframe 已被移除）就直接 `return`（審查 M-2）。
  - `compensateColumnPitch` 的 `measure` 用 `Array.from(doc.body.getClientRects())` 傳給 `measureColumnPitch`；`getBoxHeight` 用 `doc.documentElement.getBoundingClientRect().height`；`setMaxHeight`／`resetMaxHeight` 用 `documentElement.style.setProperty('max-height', ..., 'important')`。
  - 掛 `new MutationObserver(...)`，只觀察 `documentElement` 的 `style` 屬性；回呼內用 `busy` 旗標避免重入，執行完以 `observer.takeRecords()` 丟掉自己造成的變動。章節文件載入後也主動執行一次。
  - 結果為 `gave-up` 時 `console.warn('[column-pitch] 補償失敗，維持原排版')`，模組層級旗標確保只警告一次。
  - 變數與函式註解用正體中文，說明「為何」：Chrome 91 直排多欄把欄長排成頁高、忽略上下內距。
- [ ] **步驟 4：執行確認通過**：同步驟 2 指令，預期全部 PASS。
- [ ] **步驟 5：回歸**：PowerShell 在 `app/tool/foliate_touch_harness` 執行 `node run-all.mjs`，預期結尾「整體結果：全部 PASS」（`run-all.mjs` 會自動納入新情境）。
- [ ] **步驟 6：Commit**：`git add app/android/app/src/main/assets/foliate/main.js app/tool/foliate_touch_harness/scenario-column-pitch-compensation.mjs`，訊息 `fix(foliate): 舊 WebView 直排欄間隔與頁高不一致的補償（epic-54 Issue 34 Task 2）`。

---

### Task 3：ES 相容性與 Flutter 側回歸

**Files：** 不新增；只驗證。

- [ ] **步驟 1：ES 相容性掃描**：PowerShell `node app/tool/check_foliate_es_compat.js`，預期結束碼 0。若 `column-pitch.js` 或 `main.js` 新增的語法被掃出，改寫而不是加 polyfill。
- [ ] **步驟 2：既有純邏輯測試**：`node app/tool/test_section_progress_density.mjs`、`node app/tool/test_tts_safe_window.mjs`、`node app/tool/test_column_pitch.mjs`，預期各自結束碼 0。
- [ ] **步驟 3：Dart 端**：`cd app` 後 `flutter analyze`（預期 No issues found）；`flutter test test/reader/foliate_reader_view_test.dart test/reader/foliate_bridge_codec_test.dart`，預期全綠。
- [ ] **步驟 4：確認沒碰 vendored**：`git diff main --stat -- app/android/app/src/main/assets/foliate` 只應列出 `main.js`、`column-pitch.js`。
- [ ] **步驟 5：不需 commit**（無檔案變動）；結果留待 Task 4 一併記錄。

---

### Task 4：WAVE 真機驗證與兩欄偵測工具

**Files：**
- Create: `app/tool/detect_two_column_gap.py`
- Modify: `app/tool/README.md`

**Interfaces：**
- Produces：`python app/tool/detect_two_column_gap.py <png>...`，每張圖印一行 `<檔名> maxBlankBand=<像素> BUG|ok`，或 `<檔名> INVALID frac=<值>`（全黑、全白、載入中）；任一張為 `BUG` 時結束碼 1。判定：內容區（略過頂部 100、底部 60、左 80、右 40 像素）內整列無墨（灰階 < 128 的像素數為 0）的連續空帶超過 80 像素為 `BUG`；有墨比例大於 0.5 或小於 0.03 為 `INVALID`。

- [ ] **步驟 1：實作 `detect_two_column_gap.py`**（依上述判定；使用 PIL 與 numpy；檔案開頭註解寫明這是為 Issue 34 的 176 像素空帶而設）。驗證用的截圖**不進版控**，一律放在暫存目錄：在步驟 2 安裝新版**之前**，裝置上還是有問題的版本，先截一張問題圖 `adb -s TCE70P24B2202374 exec-out screencap -p > <暫存目錄>/wave_bug.png`（預期偵測 `maxBlankBand=176 BUG`）；正常圖用任一正常頁（例如開橫排範例書）截取（預期 `ok`）。README 加一行。（審查 M-3）
- [ ] **步驟 2：建置安裝**：`cd app`，`flutter build apk --debug`，`MSYS_NO_PATHCONV=1 adb -s TCE70P24B2202374 install -r build/app/outputs/flutter-apk/app-debug.apk`。
- [ ] **步驟 3：重現迴圈轉綠**：裝置資料庫維持使用者原狀（會自動續讀最後一本「早安」，位置在章節第 4 頁）。`adb shell am force-stop cc.ugotit.elinkbook` → `am start -n cc.ugotit.elinkbook/.MainActivity`，等日誌出現「已渲染」後再等 6 秒，用 `adb -s TCE70P24B2202374 exec-out screencap -p > <暫存目錄>/wave_N.png` 截圖（Git Bash 內做，不要經 PowerShell 轉向，會損毀二進位；審查 M-1），再執行 `python app/tool/detect_two_column_gap.py <暫存目錄>/wave_N.png`；連續 3 次，預期全為 `ok`（修復前 5／5 為 `BUG`、`maxBlankBand=176`）。
- [ ] **步驟 4：連翻對稱**：同一本書點右側熱區（1200,936）5 次、再點左側熱區（200,936）5 次，每次等 3.5 秒；預期每次都換頁、最後畫面與起點相同。
- [ ] **步驟 5：回歸三本書**：CBZ、定樣式 EPUB、橫排多章節範例各開一次，預期都能顯示；橫排書不受補償影響。
- [ ] **步驟 6：還原裝置狀態**：確認不留下被改過的資料庫；若測試中動過閱讀位置，用進度條調回約 23%。
- [ ] **步驟 7：Commit**：`git add app/tool/detect_two_column_gap.py app/tool/README.md`，訊息 `test(tool): 直排兩欄偵測腳本（epic-54 Issue 34 Task 4）`。

---

### Task 5：文件、完整測試與 PR

**Files：**
- Modify: `docs/epics/epic-54-architecture-optimization/epic.md`（開發記錄）、`docs/epics/epic-54-architecture-optimization/issues.md`、`docs/epics.md`

- [ ] **步驟 1：完整測試**：`cd app`，`flutter test`（`run_in_background`，只跑一個），預期全綠；失敗就修，不要重跑第二份。
- [ ] **步驟 2：開發記錄**：`epic.md` 新增「2026-10-25 Issue 34 實作完成」，寫入：測試台案例數、`test_column_pitch.mjs` 案例數、真機 3 次冷啟動結果（修復前後 `maxBlankBand` 對比）、連翻對稱結果、已知限制（上邊距貼頁頂、頁底多一個 `column-gap`）、`flutter test` 通過數。
- [ ] **步驟 3：狀態**：`issues.md` Issue 34 狀態改為「🟡 PR 待合併」（合併後再改 ✅）；`docs/epics.md` 同步。**換行符**：先數 `\r\n` 與 `\n` 的多寡，再以位元組插入單一行，`git diff --stat` 必須只有預期的行數。
- [ ] **步驟 4：Commit**：`docs(epic-54): Issue 34 實作完成與驗證記錄（Task 5）`。
- [ ] **步驟 5：推送並開 PR**：推 `epic-54/issue-34-column-pitch`；用 Gitea API 開 PR（token 在 `C:\Users\huthief\.gitea_token`，不要輸出）；PR 描述寫根因、補償做法、驗證結果、未做項目與已知限制。

---

## 自我檢查紀錄

- **規格涵蓋**：決策 1（量測）→ Task 1；決策 2（只改 `main.js`）→ Task 2、Task 3 步驟 4；決策 3（演算法）→ Task 1；決策 4（`MutationObserver`）→ Task 2；決策 5（範圍）→ Task 2；決策 6（安全閥）→ Task 1 案例 d／e；決策 7（上邊距限制）→ Task 5 步驟 2；決策 8（測試）→ Task 1、2、4；決策 9（詞彙）→ 已在 `2e369c5d` 完成；決策 10（不寫 ADR）→ 無任務。
- **型別一致**：`measureColumnPitch` 回傳 `{pitch, columnLength}`，`compensateColumnPitch` 的 `measure` 型別相同；`nextMaxHeight` 簽章在 Task 1 定義後只在 `compensateColumnPitch` 內使用。
- **已確認的現況**：`renderer.scrolled`、`renderer.size`、`renderer.columnCount` 都是 `paginator.js` 既有成員；`run-all.mjs` 自動納入 `scenario-*.mjs`；測試台會服務 `assets/foliate` 內所有檔案，所以新模組不需另外註冊。
