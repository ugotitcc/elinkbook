# foliate-js 上游持續同步（設計文件）

**狀態：** 待人類審閱
**對應工單：** `epic-33-foliate-js-vendor-sync`（新 Epic，見 `docs/epics/epic-33-foliate-js-vendor-sync/issues.md`）
**排期依賴：** ~~`epic-31-touch-intent-unification` Issue 3（`TapZoneDetector` 常數收斂＋PDF 門檻對齊）已在開發中，本 Epic 待其完成後才啟動實作~~——**已解除**：`epic-31` Issue 3 已完成並合併回 `main`（commit `8a9be2cd`），本 Epic 可立即進入 Issue 拆解與實作，理由見下方「背景」。
**診斷依據：** `docs/research/foliate_js_sync_update_strategy.md`（既有同步 SOP）＋ `epic-32-foliate-js-paginator-sync/design.md`（前次同步先例）＋本次 Discovery 階段對上游 diff 的實測分析（`readest/foliate-js` commit `6c6a491`→`c09f06d`，22 個 commit）

## 背景

`epic-32-foliate-js-paginator-sync` 完成後，本專案的 vendored `paginator.js` 已同步至上游 commit `6c6a491`（2026-07-25）。Discovery 階段調查發現，上游到目前為止（2026-08-25）又累積了 **22 個新 commit**，其中 17 個觸及本專案已釘定使用的 vendored 檔案，累計改動最大的是 `paginator.js`（7 個 commit，+156/-20，多為觸控／捲動相關修法，與 `epic-32` 同一批風險，其中 3 個明確與 WebKit 行為有關）與 `fixed-layout.js`（2 個 commit，+248/-77，含新的水平捲動模式與 RTL／標註刷新修正，本專案 CBZ 漫畫依賴此檔）。

`epic-31` 當時只剩 Issue 3 未完成，範圍是 Dart 端 `TapZoneDetector` 常數收斂，與 `paginator.js` 內部行為無直接依賴（不像 `epic-32` 當時直接卡住 `epic-31` 的 `main.js` 觸控重構）。**`epic-31` Issue 3 現已完成並合併回 `main`（commit `8a9be2cd`），排期依賴已解除**，本 Epic 可立即進入 Issue 拆解與實作；比照上次的判斷邏輯——`paginator.js` 觸控相關 commit 持續累積，越晚同步、之後真機重測的範圍只會越大，故優先於其他新 Epic 處理。

## 目標

1. 同步以下 7 個已釘定 vendored 檔案至上游 commit `c09f06d`（2026-08-25，Discovery 階段查證之最新 HEAD）：`paginator.js`／`epub.js`／`fixed-layout.js`／`view.js`／`overlayer.js`／`epubcfi.js`／`comic-book.js`。範圍確認方式與細節見下方「資產盤點表」。
2. 依既有 SOP（`docs/research/foliate_js_sync_update_strategy.md`）完成 ES 相容性掃描、`app/tool/foliate_touch_harness/run-all.mjs` 觸控 Harness 自動化回歸、Bridge 對齊檢查（逐一核對 `main.js` 呼叫到的公開方法簽章與 `relocate` 事件 payload 是否不變）、`flutter analyze`／`flutter test` 基準線驗證。
3. 真機重測共 8 項，逐項記錄（完整分類與細節見下方「測試策略」第三層）：既有 3 個歷史修法（Epic 18 Issue 47／Epic 25 Issue 1／Epic 27 Issue 9）、直排核心 2 項（連續往返翻頁對稱、橫直排即時切換錨點維持）、固定版面 3 項（CBZ／FXL RTL 頁序、FXL 橫向雙頁跨頁排版、劃線標註縮放後刷新）。
4. 更新版本紀錄文件（`docs/research/foliate_js_sync_update_strategy.md` 的「當前 Pinned Commit」、`docs/epics.md`）。

## 非目標

- **不引入上游新增的 4 個功能檔案**（`footnotes.js`／`pdf.js`／`tts.js`／`opds.js`）——本次 Discovery 已盤點清楚各自變動範圍（見下方資產盤點表），但「要不要採用」是完全獨立的未來產品決策，不在本次同步範圍內。特別注意：`opds.js` 與本專案自建的 OPDS 遠端書庫功能（`epic-30-calibre-remote-library`）同名不同物，兩者完全無關。
- **不特別分析／測試 WebKit 專屬修法**——本次範圍內有 3 個 commit（`cf9829d`／`887a0ae`／`68d54b1`）明確與 WebKit（Safari）行為有關，但本專案目前只有 Android（Chromium System WebView）執行環境，`epic-13-ios` 尚未啟動、無法驗證。這些 commit 會隨所在檔案（皆為 `paginator.js`）整份同步進來，但不額外花時間分析或測試其 WebKit 專屬行為，留待 `epic-13-ios` 啟動時再評估。
- **不啟用上游新暴露的能力**——例如 `fixed-layout.js` 的水平捲動模式（`scroll-direction` 屬性）、`paginator.js` 的 sub-pixel scroll offset。程式碼隨整份同步進來，但 `main.js` 不主動設定新屬性、不呼叫新 API，只求相容不擴充行為（比照 `epic-32` 對 `turn-gesture-left-inset` 屬性的處理方式）。
- **不修改任何 vendored 檔案內容**（只整份替換，不手動修改其原始碼），符合 ADR 0011。
- **不順便驗證 `epic-31` Issue 3 的 PDF 700ms 門檻**——該工單已知「未經真機驗證」，但 PDF 閱讀走 `pdfrx`、不吃 `paginator.js`，跟本次同步是不同子系統，刻意分開追蹤，避免兩件事的驗收標準混在一起難以追溯。
- **不建立固定週期的上游同步機制**——本次是繼 `epic-32` 之後第二次「上游落後卡住其他 Epic」才臨時發起的同步，資料點仍太少，暫不制度化，維持「卡到才發起」。

## 整體機制

### 資產盤點表（含 `epic-32` 對照）

下表涵蓋上游 `readest/foliate-js` 全部釘定/相關檔案，逐一標明本專案是否使用、`epic-32` 與本次（`epic-33`）是否同步。「範圍內 commit」統計區間為 `6c6a491`（`epic-32` 已同步版本）到 `c09f06d`（本次 Discovery 查得之最新 HEAD）。

| 檔案 | 類別 | 本專案是否使用 | `epic-32` 是否同步 | `epic-33`（本次）是否同步 | 備註 |
|---|---|:---:|:---:|:---:|---|
| `paginator.js` | Vendored（上游） | ✅ 分頁核心／觸控手勢 | ✅ 已同步（`6c6a491`，觸控核心重寫 +338/-55） | ✅ 同步（7 個新 commit，+156/-20） | 兩次同步都是變動最集中的檔案，含 3 個 WebKit 相關 commit（隨檔案整份帶入，不額外測試） |
| `fixed-layout.js` | Vendored（上游） | ✅ CBZ／FXL 固定版面 | ⬜ 未變動，不需同步 | ✅ 同步（2 個 commit，+248/-77） | 新增水平捲動模式（不啟用）＋ RTL／標註刷新修正（新增真機驗證項目） |
| `epub.js` | Vendored（上游） | ✅ EPUB 容器解構 | ⬜ 未變動 | ✅ 同步（4 個 commit，+58/-5） | |
| `view.js` | Vendored（上游） | ✅ `foliate-view` 元件 | ⬜ 未變動 | ✅ 同步（1 個 commit，+8/-0） | |
| `overlayer.js` | Vendored（上游） | ✅ 劃線／螢光筆渲染 | ⬜ 未變動 | ✅ 同步（1 個 commit，+8/-0） | |
| `epubcfi.js` | Vendored（上游） | ✅ CFI 定位 | ⬜ 未變動 | ✅ 同步（1 個 commit，+2/-2） | |
| `comic-book.js` | Vendored（上游） | ✅ CBZ 讀取 | ⬜ 未變動 | ✅ 同步（1 個 commit，+15/-1） | |
| `progress.js` | Vendored（上游） | ✅ 章節進度估算 | ⬜ 未變動 | ⬜ 未變動，不需同步 | |
| `text-walker.js` | Vendored（上游） | ✅ DOM 文字遍歷 | ⬜ 未變動 | ⬜ 未變動 | |
| `mobi.js` | Vendored（上游） | ✅ KF8／AZW3 讀取 | ⬜ 未變動 | ⬜ 未變動 | |
| `vendor/zip.js` | Vendored（上游） | ✅ Zip 解壓縮 | ⬜ 未變動 | ⬜ 未變動 | |
| `construct-style-sheets-polyfill.js` | Vendored（上游） | ✅ CSSStyleSheet Polyfill | ⬜ 未變動 | ⬜ 未變動 | |
| `footnotes.js` | 上游新檔案（未釘定） | ❌ 未使用 | ➖ 當時尚未出現於範圍內 | ❌ 不同步（僅盤點） | 範圍內 1 個 commit（+54/-1）。是否採用留待未來獨立產品決策 |
| `pdf.js` | 上游新檔案（未釘定） | ❌ 未使用（本專案 PDF 走 `pdfrx`） | ➖ 同上 | ❌ 不同步（僅盤點） | 範圍內 5 個 commit（含一次 PDF.js 6 依賴升級，`package.json`/`package-lock.json` +287/-808） |
| `tts.js` | 上游新檔案（未釘定） | ❌ 未使用 | ➖ 同上 | ❌ 不同步（僅盤點） | 範圍內 1 個 commit（+10/-2） |
| `opds.js` | 上游新檔案（未釘定） | ❌ 未使用 | ➖ 同上 | ❌ 不同步（僅盤點） | 範圍內 1 個 commit（+2/-2）。與本專案自建 OPDS 遠端書庫功能同名不同物，完全無關 |

> `main.js`（本專案自建橋接層，非上游檔案）與 `index.html` 不在此表列範圍內，本次同步不觸碰。

### `paginator.js` 7 個新 commit 摘要（供 Bridge 對齊檢查參考）

`4088d28`（letterbox duokan 全螢幕封面）、`f6bce4c`（無 client rects 時的捲動邊界處理）、`cf9829d`（避免在 Safari 17 之前的 WebKit 呼叫 `document.fonts.ready`，避免字型載入觸發崩潰，WebKit 相關）、`fd91451`（連續捲動時定期發射 `relocate` 事件）、`887a0ae`（WebKit 捲動位置被夾住時重新套用，WebKit 相關）、`68d54b1`（sub-pixel scroll offset，跨引擎議題但明確引用 WebKit 行為，不啟用此新能力）、`2b6ea0a`（容器捲動離開錨點時保留錨點）——皆為觸控／捲動內部行為調整，公開方法簽章與 `relocate` 事件 payload 欄位需比照 `epic-32` 的檢查方式逐一核對是否不變。

**`fd91451`（連續捲動時定期發射 `relocate`）對 Bridge 的連動影響**：`main.js` 透過 `onLocatorChanged` handler 把每次 `relocate` 事件轉譯後送給 Dart 端（`foliate_bridge_codec.dart`），若發射頻率提高，需確認快速連續翻頁／捲動時橋接通訊仍流暢無卡頓、`ReadingPositionRepository` 沒有被異常高頻寫入（納入下方測試策略「第二層」的觀察項目）。

### `fixed-layout.js` 2 個 commit 詳情

- `663e630`（+242/-76）：新增以 `scroll-direction` 屬性驅動的水平捲動排版模式（本次不啟用）；修正 RTL 水平捲動時 `direction: rtl` 應設在 host 而非子層 div，否則錨點會跳位；修正滾輪事件相關 bug。
- `9fde61a`（+6/-1）：修正縮放（zoom）後標註（劃線／螢光筆）overlay 未刷新的問題（`onZoom` 回傳 Promise 時需等待 resolve 後才刷新 overlayer）。

## 測試策略

依審查意見（`reviews/review-design.md`）將驗證分為三層，前一層通過才進入下一層：

### 第一層：靜態與單元測試

- **基準線**：`flutter analyze` 需為「No issues found!」，`flutter test` 全數通過。
- **ES 相容性掃描**：`node app/tool/check_foliate_es_compat.js` 結束碼須為 0；若非 0，依 `epic-32` 已確立的硬性規範在 `_esCompatPolyfillJs`（`foliate_reader_view.dart`）補齊 polyfill（僅在原生實作缺席時定義、嚴禁 ES2021+ 語法糖）。
- **語法解析期（Parse Time）防護說明**：`check_foliate_es_compat.js` 本質是針對已知清單的 Regex 掃描，只能攔截「執行期呼叫某個較新 API」這類問題；它**無法**攔截「舊版 WebView 對某段語法本身直接拋出 `SyntaxError`」（例如可選鏈 `?.`、`??=`、私有欄位語法）——這類錯誤發生在腳本執行前，Polyfill 完全無法補救，且是本專案已知的歷史失敗模式（見 `docs/research/foliate_js_sync_update_strategy.md` 3.1 節、Issue 38/41 紀錄）。因此掃描結束碼為 0 不代表萬無一失，仍須在下方第三層真機驗收中實際確認舊版 WebView（Mobiscribe WAVE／iReader Ocean 4 Plus 等 Chromium 83-91 機型）能正常開書，作為語法層級問題的最終把關。

### 第二層：觸控 Harness 自動化

- 執行 `node app/tool/foliate_touch_harness/run-all.mjs`（`epic-31` Issue 1 建立的 4 個觸控意圖情境回歸測試），作為上真機前攔截 `TouchIntentClassifier`（`epic-31` Issue 2 成果）與上游觸控／捲動邏輯衝突的自動化防線，4 個情境須全數 PASS。
- 觀察快速連續翻頁／捲動時 `onLocatorChanged` 橋接通訊是否流暢無卡頓（呼應上方 `fd91451` 的高頻 `relocate` 說明）。

### 第三層：真機深度驗收（GO/NO-GO 判準，逐項記錄於該 Issue 的 review 報告）

- **歷史修法（3 項，比照 `epic-32`）**：
  - Epic 18 Issue 47：長按選字前幾影格畫面不暴跳。
  - Epic 25 Issue 1：畫線選取已確立時不誤觸跳頁。
  - Epic 27 Issue 9：`no-swipe` 屬性正確阻止滑動。
- **直排核心（2 項）**：
  - 直排 EPUB 連續往前翻頁 5 次、再反向翻頁 5 次，精確回到原始文字錨點。
  - **新增**：繁中流式 EPUB 閱讀中即時切換橫排／直排，閱讀位置（錨點）精確維持（對應 `2b6ea0a` 錨點保留邏輯變動，呼應 Epic 18 Issue 45 歷史修法）。
- **固定版面（3 項）**：
  - CBZ／FXL 漫畫 RTL 頁序正確。
  - **新增**：FXL 橫向雙頁跨頁排版與封面單頁顯示正常（對應 `663e630` 對 host／RTL 樣式的改動，呼應 Epic 18 Issue 19 歷史修法）。
  - 劃線標註縮放後正確刷新（不需手動觸發其他操作即可看到刷新後的正確位置）。

## 已知風險

- 上游持續有新 commit（Discovery 期間 HEAD 從 `2b6ea0a` 又往前跑到 `c09f06d`），本次鎖定 `c09f06d` 為準，之後若繼續落後，另立新的同步 Epic 處理，SOP 本來就支援逐次鎖定新 commit。
- `paginator.js` 觸控相關改動仍在持續累積，本次同步後下一輪很可能又是同一批檔案，真機重測負擔預期會是常態性成本，不是一次性的。
- **快速停損指標**：若真機重測中「直排對稱翻頁」失敗，或出現舊版 WebView `SyntaxError` 且無法透過 Dart 端 Polyfill 在 **2 小時內**排除，直接 `git revert` 這次同步的 commit，退回 `6c6a491`，不在時間壓力下硬修。

## 預計工單切片方向（供下階段 Scrum Master 參考）

比照 `epic-32` 拆解模式，本 Epic 不需要「修復掃描工具」這類先決條件工單（`epic-32` 已修好），預期拆為 2 個工單：

1. **Issue 1**：資產整份替換（7 個檔案）＋第一層靜態/單元測試＋第二層觸控 Harness 自動化＋Bridge 對齊檢查。
2. **Issue 2**：第三層真機深度驗收（8 項）＋版本紀錄與看板文件收尾。

正式拆解仍以 `issues.md` 為準，此處僅為方向預告。
