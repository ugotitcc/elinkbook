# Epic 7 Issue 9 — Spike：直排／橫排翻頁跳頁問題診斷報告

**驗證日期：** 2026-07-20
**驗證裝置：** `3CEF42ECD491687`（TCL 9491G，Android 15／API 35，螢幕 1600×2400）
**測試素材：** `app/test/fixtures/issue9_vertical_pagejump.epub`（流式 reflowable EPUB，UI 估算 148 頁；Readium 內部 locator position 約 124 個）
**分支：** `worktree-epic-7-issue-9`
**量測方法：** 真機插樁（比照 Issue 1 spike），在 `EpubReaderView.kt` 的 TAP（`InputListener.onTap()`）與 CHANNEL（`onMethodCall` 的 `nextPage`/`previousPage`）兩條路徑、以及 `currentLocator` 訂閱處各插一筆 `Log.i`，記錄每次觸發前的 `totalProgression` 與觸發後 emit 的 `href`／`position`／`totalProgression`。插樁已於本 Task 還原（`git checkout --`）。

---

## 無插樁基準重現（Task 1）

| 組合 | 觀察 | 是否與人類原始回報一致 |
|---|---|---|
| 橫排 × 熱區 | 頁碼標籤「第 1/148 頁」不動，但畫面內容確有變化 | 部分：未直接觀察到「跳兩頁」，反而是頁碼凍結 |
| 橫排 × 音量鍵 | 頁碼標籤不動，畫面內容在第 2 次觸發起僅重新排版、未真正翻頁 | 部分：呈現「觸發被吃掉」而非跳頁 |
| 直排 × 熱區 | 單次點擊乾淨推進 1 頁（1→2） | 一致（熱區在直排下實測正常） |
| 直排 × 音量鍵 | 單次音量鍵從第 2 頁跳到第 4 頁（+2） | 一致：重現「直排每次跳好幾頁」 |

基準階段即顯示：直排／橫排、熱區／音量鍵四種組合的失效型態**並不相同**，不是單一症狀。

---

## 橫排量測（Task 3，`spike9-h-logcat.txt` 共 13 筆）

每次觸發皆穩定對應**恰好 1 筆** `LOCATOR_EMIT`（無 0 筆、無多筆），全程 6 次觸發 UI 頁碼標籤凍結在「第 1/148 頁」。

### 橫排 × 熱區（3 次：前進、前進、後退）

| 觸發 | LOCATOR_EMIT 筆數 | position 變化 | progression 變化 | 是否真正翻頁 |
|---|---|---|---|---|
| ① TAP FORWARD | 1 | 1→1（不變） | 0.0→0.0 | ❌ 被吃掉（僅 re-layout） |
| ② TAP FORWARD | 1 | 1→2 | 0.0→0.00813 | ✅ |
| ③ TAP BACKWARD | 1 | 2→1 | 0.00813→0.0 | ✅ |

### 橫排 × 音量鍵（3 次：下、下、上）

| 觸發 | LOCATOR_EMIT 筆數 | position 變化 | progression 變化 | 是否真正翻頁 |
|---|---|---|---|---|
| ④ CHANNEL FORWARD | 1 | 1→2 | 0.0→0.00813 | ✅ |
| ⑤ CHANNEL FORWARD | 1 | 2→2（不變） | 0.00813→0.00813 | ❌ 被吃掉 |
| ⑥ CHANNEL BACKWARD | 1 | 2→2（不變） | 0.00813→0.00813 | ❌ 被吃掉（該退未退） |

**橫排失效模式：觸發被靜默吃掉。** `TRIGGER` log 證明 `goForward()`/`goBackward()` 每次都有被呼叫，但 6 次中有 3 次 Readium 底層 `position` 完全沒有移動（`currentLocator` 仍會重新 emit 一次舊值，故 `LOCATOR_EMIT` 筆數仍是 1）。位移只在書本最開頭 0～0.8% 之間來回，`progression` 從未超過 0.00813。

---

## 直排量測（Task 4，`spike9-v-logcat.txt` 共 12 筆）

每次觸發同樣穩定對應**恰好 1 筆** `LOCATOR_EMIT`。反推公式 `progression = (position − 1) / 123`（全書約 124 個 locator）驗證 6 組配對狀態完全連續、無遺漏。

### 直排 × 熱區（3 次：前進、前進、後退）

| 觸發 | before position | after position | position 變化 | 是否單步 |
|---|---|---|---|---|
| ① TAP FORWARD | 2 | 3 | **+1** | ✅ 乾淨單步 |
| ② TAP FORWARD | 3 | 4 | **+1** | ✅ 乾淨單步 |
| ③ TAP BACKWARD | 4 | 3 | **−1** | ✅ 乾淨單步 |

### 直排 × 音量鍵（3 次：下、下、上）

| 觸發 | before position | after position | position 變化 | 是否單步 |
|---|---|---|---|---|
| ④ CHANNEL FORWARD | 3 | 5 | **+2** | ❌ 多步 |
| ⑤ CHANNEL FORWARD | 5 | 8 | **+3** | ❌ 多步 |
| ⑥ CHANNEL BACKWARD | 8 | 6 | **−2** | ❌ 多步 |

**直排失效模式：觸發被放大（多步）。** 與橫排的「被吃掉」方向相反。關鍵是這是 Readium 底層 `currentLocator.position` 本身真的移動了 2～3 步（不是 UI 顯示問題）——單次 `goForward()`/`goBackward()` 呼叫使 Navigator 真正推進了超過 1 個 locator。且直排下 **TAP 路徑是乾淨的**（3 次皆 ±1），只有 **CHANNEL（音量鍵）路徑多步**。

### UI 頁碼（第 N/148 頁）vs. Readium position（out of ~124）

| 觸發 | UI 頁碼變化 | Readium position 變化 |
|---|---|---|
| 直排 TAP② | 2→4（+2，跳過 3） | 3→4（+1） |
| 直排 TAP③ | 4→2（−2，跳過 3） | 4→3（−1） |
| 直排 CHANNEL① | 2→5（+3） | 3→5（+2） |

UI 頁碼在 position 只動 1 步時仍可能跳 2 頁——這是**與 Readium 導航無關的獨立現象**（見下方根因判定第 2 點）。

---

## 根因判定

閱讀原始碼後（`EpubReaderView.kt`、`MainActivity.kt`、`ReaderScreen.dart`、`EpubPageEstimator.dart`），本次觀察到的異常拆解為**兩個彼此獨立的層次**，並非單一根因：

### 第 1 層（真正的「跳頁／被吃」導航異常）— 判定為 Readium 內部行為，非 App 層 bug → 退回

**證據鏈：兩條觸發路徑最終呼叫的是「完全相同」的 Readium API，App 層無任何放大／節流／迴圈。**

- **TAP 路徑**：Readium `InputListener.onTap()`（`EpubReaderView.kt` 第 996-1021 行）→ `ZoneAction.NEXT_PAGE`/`PREVIOUS_PAGE` 分支 → `navigatorFragment?.goForward(animated = false)` / `goBackward(animated = false)`。同步在 Readium 自己的手勢回呼內執行。
- **CHANNEL 路徑**：`MainActivity.dispatchKeyEvent()`（第 87-101 行，**僅 `ACTION_DOWN` 轉發、`ACTION_UP` 消費**，一次實體按鍵 = 恰好一次 `onVolumeKey`）→ Dart `_handleVolumeKeyCall`（`reader_screen.dart` 第 1506 行）→ `_handleZoneAction()` → `EpubReaderView.nextPage()`（Dart static helper，**一次 `invokeMethod('nextPage')`**）→ 回到原生 `onMethodCall("nextPage")`（第 229 行）→ **同一個** `navigatorFragment?.goForward(animated = false)`。

兩條路徑的差別**只在呼叫的時機與上下文**（TAP 在 Readium 手勢管線內同步觸發；CHANNEL 經過「原生按鍵 → Flutter platform channel → Dart → method channel 折返原生」的非同步繞行），最終落在同一行 Readium 呼叫。App 端不存在任何可能「把 1 次觸發變成多步」或「把 1 次觸發吃掉」的迴圈、計數器、防抖鎖或共用狀態變數——逐行讀過確認。

因此「橫排被吃掉」與「直排 CHANNEL 多步」都**不是 App 翻譯層的缺陷**，而是 Readium 的 reflowable Navigator：`goForward(animated=false)` 實際推進的 locator 數量會隨 WebView 分頁／re-layout 狀態與呼叫上下文而變動（同步的 TAP 落在 WebView 穩定態、乾淨推進 1 步；非同步折返的 CHANNEL 落在不同的 WebView 生命週期時點，於直排欄式版面下一次推進多步、於橫排書首邊界則被判定為無位移而吃掉）。這對應 Issue 9 原假設「Readium `OverflowableNavigator` 對直排文字的分頁計算有誤差」——本次量測部分證實該方向，並補上更精確的觀察：**問題與觸發來源的呼叫時序高度相關（TAP 乾淨、CHANNEL 異常），不是純靜態的欄寬整除誤差。**

修法需要更動與 Readium 互動的方式（例如改用 Readium 其他等效 API、或在呼叫前確保 WebView 分頁狀態穩定、或升級／繞過 Readium 版本），屬架構層級變動、風險不可控 → **不在本 issue 內強行修正。**

### 第 2 層（UI 頁碼「第 N/148 頁」跳號／橫排凍結）— 判定為 App 端估算器捨入假象，非導航問題

`ReaderScreen._buildEpubFooter()`（`reader_screen.dart` 第 1392-1418 行）的頁碼**並非**取自 Readium `position`，而是 `EpubPageEstimator` 依「全書字元數 ÷ 每螢幕字元數」估算：`estimateCurrentPage = (progression * totalPages).round().clamp(1, totalPages)`（`epub_page_estimator.dart` 第 63-70 行）。

- **148 vs 124 兩套計數系統**：`totalPages`（148）來自字元數估算，Readium `position`（~124）來自 positions service，兩者非等比。
- **直排 UI 跳號是 `.round()` 假象**：直排 TAP② position 3→4，progression 0.01626→0.02439，`round(0.01626×148)=2`、`round(0.02439×148)=4`——真實只動 1 步，四捨五入卻在 148 頁刻度上跨過「3」顯示 2→4。屬 lossy 估算的固有行為，非導航錯誤。
- **橫排「凍結在第 1/148 頁」並非未訂閱**：footer 每次 `build()` 都重新讀 `_epubPositionInfo.progression`。橫排全程 progression 只在 0～0.00813 之間（因為前進觸發被 Readium 吃掉、實際停在書首），`round(0.00813×148)=round(1.20)=1`，故正確地一直顯示「第 1 頁」。這推翻了 Task 3 當下「UI 頁碼未訂閱 currentLocator」的臨時假設——真正原因是導航根本沒推進，加上書首低解析度估算捨入到 1。

此層為估算器的先天精度限制，**本身不是「跳頁 bug」**，可不修；若要改善，屬獨立的 UI 精度議題。

**證據引用：** `spike9-h-logcat.txt`（橫排 6 觸發，3 筆 position 未動）、`spike9-v-logcat.txt`（直排 CHANNEL ④⑤⑥ position +2/+3/−2）、`spike9-v-tap-p0~p3-prev.png`（直排 TAP 乾淨 ±1）、`spike9-h-key-p1~p3-prev.png`（橫排音量鍵被吃）。以上檔案位於 `tmp/epic-7/reviews/`（`.gitignore` 排除）。

---

## 對 Issue 9 驗收標準的回應

- **4 種組合的「單次觸發→實際頁面推進量」皆有明確數據與結論**：✅ 見上方橫排／直排兩節逐次表格（position 前後值＋progression＋LOCATOR_EMIT 筆數）。
- **明確判定根因**：✅ 拆為兩層——(1) 真正導航異常（被吃／多步）源於 Readium reflowable Navigator `goForward(animated=false)` 在不同呼叫時序下推進量不穩定，App 層兩條路徑最終呼叫完全相同、無放大；(2) UI 頁碼跳號／凍結為 App 端 `EpubPageEstimator` 的 `.round()` 捨入假象，非導航問題。排除「觸發端重複呼叫」（每觸發恰 1 筆 `LOCATOR_EMIT`、音量鍵僅 `ACTION_DOWN` 轉發）。
- **過時註解已修正**：✅ `EpubReaderView.kt` `"nextPage"` case 註解由「僅供 FXL 三欄熱區使用」改為反映 Issue 7 後所有 EPUB 格式共用此路徑的實際用途。
- **是否直接修正 vs 退回**：**退回。** 第 1 層根因在 Readium 內部、修法有架構影響且風險不可控，不在本 spike 內強行修正。**建議退回方案／後續實作工單方向**：
  1. **優先**：讓 CHANNEL（音量鍵）翻頁不再走「method channel 折返原生」的非同步繞行，改為在原生端直接觸發與 TAP 相同的同步呼叫路徑（實測 TAP 在直排下乾淨 ±1），以消除呼叫時序差異。這是最貼近「低風險、對齊已知正常路徑」的方向，值得另立工單優先驗證。
  2. **次選**：在呼叫 `goForward/goBackward(animated=false)` 前，確認／等待 Readium WebView 分頁狀態穩定（避免落在 re-layout 時點），或評估改用 Readium 的 `go(Locator)` 依明確目標 locator 導航，取代相對式的 `goForward/goBackward`。
  3. **橫排「被吃」**：與升級 Readium `kotlin-toolkit` 版本後的行為變化一併評估（可能為特定版本在書首邊界的既有 bug）。
  4. **UI 頁碼精度（第 2 層）**：獨立、低優先，若要消除跳號可考慮讓頁碼直接映射 Readium `position` 而非字元數估算，屬 UI 議題另議。
- **暫時性插樁已清理**：✅ `git checkout --` 還原，`git status` 僅剩本報告、issues.md 與 `EpubReaderView.kt` 的正式註解修正。

---

## 附記：驗證方式說明（為何退回而非修正）

本 spike 的核心結論建立在「兩條觸發路徑逐行讀過、最終落在同一個 Readium 呼叫、App 層無放大」這個程式碼事實上——這是排除 App 層根因、將問題定位到 Readium 內部的直接證據，無需再對 App 程式碼做修改性實驗即可判定。由於未做 App 層修正（僅改註解），不需要重跑真機量測驗證修正效果；本報告記錄的是「診斷結論＋退回方案」，實際修法留待後續工單依上述方向實作並各自驗證。
