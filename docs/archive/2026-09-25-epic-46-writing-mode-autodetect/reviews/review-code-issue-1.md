# 程式審查報告：epic-46 Issue 1（plan-issue-1）

- 審查日期：2026-09-25
- 分支：`epic-46/writing-mode-autodetect-issue1`
- Base：`6b73aa199f09767e4ae3d221111ad9ecdd518cca`
- Head：`4dc8f1ff46a37b47cffd3c84d54dc9e02158294a`
- 審查範圍：2 個 commit，共 6 個檔案
  - 程式：`main.js`（+92/-17）
  - 測試：新增 `scenario-writing-mode-autodetect.mjs`
  - 文件：harness `README.md`、`docs/epics.md`、`epic.md`、`docs/prd.md`

**實際跑過的驗證**：都在暫存 worktree 中執行，跑完已移除，主工作區沒有動到。

| 指令 | 結果 |
|---|---|
| `node scenario-writing-mode-autodetect.mjs` | 7/7 PASS，案例 A 的診斷值為 `html=vertical-rl body=vertical-rl .main=vertical-rl columnWidth=528px` |
| 變異驗證：把 `main.js:1048` 的預掃呼叫註解掉後重跑 | A～D-2 共 6 個案例 FAIL，E 仍 PASS，與計畫 Step 6 預期一致，場景確實能抓到回歸 |
| `node run-all.mjs` | 7 個場景全部 PASS |
| `node tool/check_foliate_es_compat.js` | 乾淨，沒有新增警告 |
| 自寫探針：manifest 列了某個 CSS，但 zip 裡沒有這個檔案，後面還有一個直排 CSS | 回報 `horizontal`（**錯誤**，應為 `vertical`），見 I-1 |
| 自寫探針：大書開書時間（40 章×400KB、300 章×30KB），有預掃和沒預掃各跑一次 | 桌面 Chromium 上差異落在雜訊範圍內（約 ±250ms），看不出變慢。E-Ink 真機要等 Task 4 Step 4 實測 |

沒有跑 `flutter analyze`／`flutter test`：這次沒有改任何 Dart 程式碼，符合計畫的 Global Constraints。

## 優點

- **完全照計畫走**：Task 1～3 的內容都做到了，程式碼跟計畫 Task 2 Step 1／3／4 的片段幾乎逐字一致。計畫審查採納的 I-1～I-3、M-1～M-4 都有落實：
  - OPF meta 同時支援 `name` 和 `property` 兩種寫法
  - `style` 屬性依引號種類分成兩個分支
  - spine 先依 mediaType 過濾
  - 去除註解時換成一個空白
  - mediaType 先轉小寫再比較
- **沒有碰 vendor 程式**：只用了 `book.resources.*` 和 `book.loadText`。經查證，`book.loadText` 就是 zip loader 的原始讀取函式（`epub.js:1165`、`view.js:41`），不經過 `Loader`，所以：
  - 不會觸發 transformTarget 的 `data` 事件（回應計畫 Review Focus 2）
  - 不會建立 blob URL，沒有洩漏問題
- **KF8 和 CBZ 的回退正確**：`mobi.js`／`comic-book.js` 產生的 book 都沒有 `resources`，會回傳 null，行為跟修改前一樣。
- **索引模式有略過預掃**：全文索引不會增加成本。
- **場景品質好**：
  - 在記憶體中組合成 EPUB，沒有提交二進位檔
  - 明確傳入 `writingMode: null`，確實模擬「採用書籍排版」
  - 變異驗證證實拿掉修正就會紅燈
  - 有 E 這個反例
- **正規表達式的邊界語意維持不變**，不會誤認 `-ms-`。沒有使用 `matchAll`／`replaceAll`。

## 問題

### Critical（必須修正）

無。

### Important（應修正）

**I-1　`main.js:1010`、`main.js:1027`：`book.loadText(...)` 遇到缺檔時會同步回傳 `null`，不是 Promise，`.catch` 直接丟出 TypeError，整個預掃中斷，靜默退回舊的「第一個 CSS」行為**

- **問題**：
  - `view.js:39-41` 的 `load = f => (name) => map.has(name) ? f(...) : null`，找不到 zip 內的檔案時同步回傳 `null`。
  - 因此 `null.catch(...)` 會丟出 TypeError，`detectBookWritingMode` 被 reject。
  - `main.js:1048` 的 `.catch(() => null)` 接住例外，於是 `detectedBookWritingMode = null`，改走 transformTarget 回退路徑，也就是本 Epic 要修掉的舊行為。
  - 我用探針實測重現了：manifest 裡有一個缺檔的 `missing.css`，後面接著 `v.css{writing-mode:vertical-rl}`，結果回報 `horizontal`。
- **為何重要**：
  - 「manifest 列了但 zip 裡沒有這個檔案」在真實 EPUB 中並不少見。
  - 這時結果又會隨閱讀位置改變，直接違反 `CONTEXT.md:24` 的不變式「同一本書每次開啟結果必須相同」。
  - 逐項 `.catch(() => null)` 的原意是「單項失敗就跳過」，現在形同虛設。
  - 開書本身不會失敗，所以不算 Critical。
- **建議修正**：
  - 兩處都改成 `await Promise.resolve().then(() => book.loadText(item.href)).catch(() => null)`，或包成一個小 helper `safeLoadText`。
  - 在場景中新增一個「缺檔 CSS 排在直排 CSS 之前」的案例（F），預期為 `vertical`。

**I-2　`epic.md:40`、`epic.md:54`：開發記錄格式錯誤，內容也已經過時**

- **問題**：
  - 第 40 行把新條目的粗體標題 `**2026-09-24 Task 1 — …**` 直接接在上一段句尾，少了換行和空行。
  - 第 54 行還寫著「下一步：執行 Task 2」，但 Task 2、Task 3 都已經 commit。
  - Task 2 Step 6 的變異驗證、Step 7 的 run-all／ES 相容性結果都沒有記錄。
- **為何重要**：`epic.md` 是 SDD 流程中的進度紀錄，後續真機驗證（Task 4）和歸檔都會依它判斷目前進度。
- **建議修正**：
  - 補上換行。
  - 把「下一步」改成「Task 4 真機驗證」。
  - 補一行 Task 2 Step 5～7 的結果。

### Minor（建議）

**M-1　`epic.md:50-52`：診斷數值的解讀跟數字本身不符**

- 修改前後的 `columnWidth` 都是 `528px`，我實測也一樣。
- 所以「Paginator 用橫排的欄寬（528px）去排直排內容」以及修改後「以直排的欄寬排版」這兩句，都沒有這組數字支撐。真正有差別的只有 `html`／`body` 的 writing-mode。
- 建議改寫解讀文字，或者改量其他指標，例如 `renderer` 的 vertical 狀態或 scroll 方向。

**M-2　計畫本身「需人類確認的設計決定」#2 的理由有誤（這是計畫的問題，不是實作的問題）**

- `foliate_reader_view.dart:123-125` 在有覆寫時，會把覆寫值寫進 `initialPrefs.writingMode`。
- `main.js:1092` 的 `onPageRendered` 回傳的是 `initialPrefs.writingMode ?? detected`，也就是覆寫值；Dart 端的 `reader_screen.dart:1897` 也把這個值存成 `_autoDetectedWritingMode`。
- 因此「使用者已手動覆寫時仍照常預掃」算出來的結果**從未傳到 Dart**，純屬多餘成本，也沒有達到「切回採用書籍排版時有偵測值可用」的目的。
- 建議擇一處理：
  - 有覆寫時略過預掃
  - 或者保留現狀，但更正計畫文字
- 「切回採用書籍排版時拿到的是覆寫值」這件事本身是既有行為，見下方「未判定項目」。

**M-3　`main.js:1017`：`INLINE_STYLE_RE` 的 `\sstyle\s*=` 也會比對到正文文字**

- 例如英文正文「… style = "…"」會被當成樣式來判讀。
- 誤判的前提是引號內剛好有直排宣告，機率極低，列出來僅供參考。

**M-4　正規表達式 `tb(?:-rl)?\b` 也會比對到 `tb-lr` 的前綴 `tb`**

- `tb-lr` 在 CSS 中不是合法值，實務影響可以忽略。

**M-5　`README.md` 的新增行把原本檔案結尾的空行吃掉了**

- 純格式問題。
- 另外，計畫檔的 checkbox 沒有勾選。

## 建議

1. 優先修 I-1。改動很小（兩行加一個測試案例），而且直接關係到本 Epic 核心不變式「結果與閱讀位置無關」。
2. 真機驗證（Task 4 Step 4）建議在 `detectBookWritingMode` 前後加上暫時性的 `performance.now()` 記錄，拿到 E-Ink 裝置上的實際毫秒數：
   - 橫排書每次開書都會掃完全部 CSS，外加最多 20 章 XHTML。
   - TXT 合成書每塊最多 400KB（`kTxtChunkMaxBytes`），最壞情況要在主執行緒解壓約 8MB。
   - 桌面上量不出差異，不代表真機也沒有差異。

## 未判定項目（Declined to judge）

- 「全書任一處宣告直排即為直排」會讓只有 `.poem` 使用直排的橫排書被判成直排：Discovery 已接受這項取捨，也已寫進 `CONTEXT.md`／`epic.md`（計畫 Review Focus 1）。
- 內嵌樣式只掃前 20 章，所以宣告只出現在第 21 章以後的書會被判成橫排：計畫決定 #1 經人類確認，結果仍具決定性。
- 覆寫狀態下切回「採用書籍排版」，拿到的是覆寫值而不是偵測值：這是既有行為（Dart 端 `_autoDetectedWritingMode` 的來源），不是這次改動造成的，只在 M-2 順帶說明。
- `-epub-writing-mode` 在目前的 Chromium 是否仍然有效：既有的正規表達式本來就支援，這次沒有改動這部分。
- KF8 不做全書預掃：計畫 Review Focus 3 明確列為範圍外。
- FXL EPUB 也會跑預掃（成本很小，對版面沒有影響）：計畫沒有要求區分，影響可以忽略。
- 與 PR #272 預讀過時排版修復之間的互動：預掃在 `view.open` 之前完成，不改變任何渲染時序；run-all 中的 `scenario-preload-stale-layout.mjs` 也 PASS，所以沒有深入追查。

## 結論

**是否可合併？** 修正後可合併

**理由：** 主要路徑正確，測試確實能抓到回歸，也完全照計畫走。但 I-1 是一個實測可重現的缺陷：`loadText` 對缺檔同步回傳 `null`，會讓整個預掃靜默退回舊行為，破壞本 Epic 的核心不變式。修正後補一個缺檔案例，同時整理 `epic.md`（I-2），就可以合併。
