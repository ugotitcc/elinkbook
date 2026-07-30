# Epic 20 — FXL 渲染引擎遷移評估（foliate-js Phase 2）：設計 (Design)

> 本文件由 `/grill-with-docs` 2026-07-30 逐項確認產生。

## 問題陳述

`ADR 0011`（`epic-17-epub-render-migration`，已歸檔）Phase 1 把**流式（reflowable）EPUB** 的渲染引擎由 Readium 換成 `readest/foliate-js`，**固定版面（FXL）EPUB 刻意留在 Readium**，該 ADR 明文預留伏筆：「本 ADR 只涵蓋 Phase 1（流式 EPUB）；FXL 遷移...留待未來視 Phase 1 上線後的實際狀況另立 ADR 或 Epic 評估」。

`epic-18-reader-device-qa` Issue 15-21 這一連串工單（強制 FXL 誤判、橫向雙頁退化成單頁、進度條/頁尾 UI 缺失、封面獨立顯示/頁碼配對）暴露出 FXL 留在 Readium 這條路徑的深層限制：Readium 官方元件（`EpubNavigatorFragment`）對 metadata 的判讀、spread 配對、`positions()`/`servicesBuilder` 服務層皆是本專案無法完全控制的黑盒，Issue 16-21 一路都是在這些邊界內打補丁（`Publication.Builder` 重建、`readingOrder` 索引、`Properties.add()` 覆寫嘗試）。

人類提供兩份外部分析報告，比較 Anx Reader（`anxcye/anx-reader`，Flutter + upstream `johnfactotum/foliate-js`）與 Readest（`readest/readest`，Tauri + `readest/foliate-js` fork）如何處理 FXL 漫畫的橫向雙頁、RTL 頁序（`3-2, 5-4`）、封面獨立顯示與零縫隙拼接——兩者都做得很好。經查證，我們自己專案已經 vendored 的 `readest/foliate-js`（本專案 production 使用的同一個 fork，釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`）：

1. **`view.js:255-257` 已內建 FXL 判斷與動態載入邏輯**：`this.isFixedLayout = this.book.rendition?.layout === 'pre-paginated'`，成立時 `await import('./fixed-layout.js')`——這個能力是**潛伏（latent）**的，只是 `fixed-layout.js` 這個檔案當初 ADR 0011 Phase 1 刻意沒有 vendored 進來（Phase 1 明確排除 FXL 範圍）。
2. **`epub.js:1091-1095` 已在解析 `page-spread-left`/`page-spread-right`/`page-spread-center`**（RTL／封面獨立顯示的原始 EPUB metadata），這正是 Issue 21 Spike 想在 Readium 那邊硬湊、但查證 Readium 官方 API 不存在的東西。
3. 對照 GitHub 確認 `fixed-layout.js` **確實存在於我們現有釘定的同一個 commit**（`dd71f2be356563c16a23272686189fcfb45d0b82`），不是版本落差問題；該檔案只依賴一個外部 polyfill（`construct-style-sheets-polyfill`），`computeSpreadInlineMargins`／`computeSpreadSpineOverlap` 等函式皆在檔案內自足定義，不需要額外拉其他上游檔案。

技術根因與 ADR 0011 當初的邏輯一致：FXL 若繼續留在 Readium，就持續受限於一個本專案無法完全控制的官方元件黑盒；`foliate-js` 這邊不僅原生支援這些能力，且是我們已經深度整合、production 穩定運作中的同一套技術棧（reflowable 路徑已用了一整個 Epic 17 的份量驗證過）。

## 範圍界定

### 包含範圍

本次 Discovery **不**對「是否把 FXL 遷移到 foliate-js」做最終 GO/NO-GO 決定，比照 `epic-17` Issue 1 先例。範圍僅止於：

- 記錄動機與已查證的證據（上方問題陳述）。
- 定義一個**前置技術驗證 Spike** 的方法與判準——用完全獨立、不影響現有 `app/` 的方式，直接在真機驗證 `readest/foliate-js` 的 `fixed-layout.js` 能否正確處理已知問題漫畫書的橫向雙頁、RTL 頁序、封面獨立顯示。
- 定義 Spike 結果如何導向後續流程（GO → 進入 Architecting，比照 ADR 0011 的分階段遷移模式；NO-GO → 記錄理由，`epic-18` Issue 20/21 恢復依原計劃執行）。

### 明確排除

- **完整遷移架構設計**（`EpubReaderView.kt`/Readium FXL 路徑是否完全退場、劃線/備註/書籤資料格式轉換、既有 FXL 使用者資料是否比照 ADR 0011「視為失效不遷移」的先例、`MainActivity` 是否還需要 `FlutterFragmentActivity`）：留待 Spike 判定 GO 之後，於 Architecting 階段（`spec.md`）正式化。
- **1px 白縫（zero-gap seam）視覺細節**：外部報告提到的 `computeSpreadSpineOverlap` 屬於錦上添花的視覺打磨，不列入本次 Spike 的 GO/NO-GO 門檻，僅記錄觀察。
- **對現有 `app/` 程式碼的任何改動**：Spike 用完全獨立的 throwaway Android 專案，不建立、不修改 Flutter/`app/` 下任何檔案（比照 `epic-17` Issue 1 先例）。
- **`epic-18` Issue 20（進度條/頁尾 UI）／Issue 21（封面獨立顯示 Spike）**：兩者皆已完成 Discovery、寫好計畫，但**暫停執行**，待本 Epic Issue 1 的 GO/NO-GO 結果出爐後再決定是否恢復（GO 則兩者的 Readium 路徑修補工作大多變成不需要；NO-GO 則依原計畫繼續）。

## 決策紀錄（Discovery 逐項確認）

| # | 決策點 | 採用結果 |
|---|---|---|
| 1 | 本次 Discovery 是否直接下 GO/NO-GO | **否**。已查證的證據（vendored `view.js` 已有潛伏偵測邏輯、`fixed-layout.js` 在同一釘定 commit 存在、外部報告佐證 Anx Reader／Readest 皆有良好成果）方向正面，但 FXL 漫畫的實際渲染行為（雙頁配對、RTL、大尺寸圖片效能）仍需要真機驗證才能下決定，比照本專案「先 Spike 降低風險再承諾」一貫慣例（`epic-16-dual-page` Issue 1、`epic-7-interaction` Issue 1、`epic-17` Issue 1 皆為先例） |
| 2 | Epic 結構 | 另開新 Epic（`epic-20-fxl-foliate-migration`），不放進 `epic-18`——本提案規模相當於重新啟動 ADR 0011 預留的「FXL 遷移」評估，與 `epic-18`「真機 UI 精修」的定位不同；`epic-17` 本身已於 2026-07-24 歸檔，比照該 ADR 原文「另立 Epic」的字面意思 |
| 3 | 與 `epic-18` Issue 20/21 的執行順序 | **暫停** Issue 20/21（兩者皆已完成 Discovery、寫好實作/Spike 計畫，但尚未開始實作），優先執行本 Epic Issue 1 的核心可行性 Spike——若 GO，Issue 20/21 針對 Readium 路徑的修補工作大多會被取代，現在投入實作有很高機率白費；先確認可行性再決定後續投資方向較合理 |
| 4 | Spike Harness 承載方式 | 完全獨立的 throwaway Android 專案（比照 `epic-17` Issue 1 先例），不碰現有 `app/` 程式碼，用 `WebViewAssetLoader` 載入釘定 commit 的 `readest/foliate-js`（含補上的 `fixed-layout.js`） |
| 5 | Spike 驗證的 `foliate-js` 版本 | 與現有 production 完全一致的釘定 commit（`dd71f2be356563c16a23272686189fcfb45d0b82`），不追蹤上游最新狀態——已查證 `fixed-layout.js` 在此 commit 就存在，不需要升版 |
| 6 | 是否驗證 1px 白縫等視覺細節 | 不列入 GO/NO-GO 門檻，僅記錄觀察——核心問題是「能不能正確渲染」，不是「渲染得多完美」，比照本專案一貫的 Spike 範圍收斂原則 |

## Spike 驗證方法與判準（Issue 1）

### Harness 設計

- 新建一個獨立、throwaway 的最小 Android 專案（單一 `Activity` + 單一 `android.webkit.WebView`），不屬於 `app/`，比照 `epic-17` Issue 1 既有 harness 設計（`WebViewAssetLoader` 虛擬 host 載入方式）。
- 打包釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82` 的 `readest/foliate-js`，在現有 8 個檔案基礎上額外補上 `fixed-layout.js`（同一 commit，已查證存在）。
- 測試素材：沿用 `epic-18` Issue 15/17/18/19 一路使用的同一本已知會被誤判為流式的漫畫 EPUB（RTL、多頁）。

### 判準表

| 驗證項目 | 通過標準 |
|---|---|
| 橫向雙頁排版 | 裝置橫向、雙頁模式下正確顯示兩頁並排，非單頁 |
| 封面獨立顯示 | 第一頁（封面）獨立成頁，第二頁起正確兩兩配對（`1,3-2,5-4`，非 `1-2,3-4`） |
| RTL 頁序 | 右開書籍雙頁配對順序為 `[3｜2]`／`[5｜4]`（右側為序號較前的頁），非 LTR 順序 |
| 連續翻頁穩定性 | 連續觸發「下一頁」/「上一頁」3 次以上，內容連續無跳過/重複（比照 `epic-17` Issue 1 判準表） |
| 效能／記憶體 | 漫畫常見的大尺寸圖片頁載入無明顯卡頓或記憶體錯誤（觀察性質，非量化門檻） |

**GO**：上述前 4 項核心判準皆通過。
**NO-GO**：任一核心判準失敗，或效能/記憶體出現無法接受的明顯問題。

### GO 之後的下一步（不在本次 Discovery 範圍，僅記錄方向）

比照 ADR 0011 的分階段遷移模式：Architecting 階段需正式化 FXL 是否完全退出 Readium、既有 FXL 使用者資料（書籤/劃線/備註）是否比照 ADR 0011「視為失效不遷移」的先例、劃線/備註對接 `overlayer.js`（已於 reflowable 路徑驗證過，`epic-17` Issue 7/8）、3×3 導航熱區沿用既有 Dart 端 `GestureDetector` 模式（已與 reflowable 路徑一致）。

### Spike 結果（2026-07-31）：GO ✅

真機以真實問題書籍（《一弦定音！(11)》，`tmp/一弦定音.epub`，202 頁 RTL 漫畫）驗證，4 項核心判準與效能/記憶體觀察項目全數通過：橫向雙頁排版（並排接縫可見）、封面獨立顯示（單頁全寬）、RTL 頁序（目錄置右、後續章節頁置左）、連續翻頁穩定性（4 次 next + 3 次 prev，來回路徑截圖逐位元組對稱）。完整證據見 `reviews/spike-issue1-fxl-foliate.md`。

**過程記錄（供未來查閱）**：本次驗證前歷經兩輪失敗的驗證嘗試——第一輪（2026-07-30）截圖與 logcat 證據與聲稱的 GO 結論矛盾（獨立覆核判定 GO 不成立，見 `tmp/epic-20/spike-issue1-execution-review.md`）；第二輪重跑（2026-07-31 早先）誤用單頁合成測試書取代真實問題書，結構上無法驗證任何判準，且報告內截圖比對表格引用了磁碟上不存在的檔案數據（獨立覆核判定同樣不成立，見 `tmp/epic-20/spike-issue1-rerun-review.md`）。第三輪由執行者本人直接操作真機、使用真實問題書籍、每次觸發後立即核對證據，取得上述 GO 結論。

**下一步**：進入 Architecting 階段（見上方「GO 之後的下一步」段落）；`epic-18` Issue 20/21 正式標記為由本 Epic 取代、不再執行。

## 相關佐證

- `docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md`（Phase 1，本次評估的 Phase 2 起點）
- `docs/archive/2026-07-24-epic-17-epub-render-migration/`（Phase 1 完整歷程，Spike 方法論比照對象）
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 16-21（FXL 留在 Readium 這條路徑一路暴露的深層限制）
- `docs/epics/epic-18-reader-device-qa/reviews/readest_foliate_fxl_spread_analysis.md`
- `docs/epics/epic-18-reader-device-qa/reviews/anx_reader_foliate_fxl_spread_analysis.md`（兩份外部分析報告，本次 Discovery 觸發點）
- `app/android/app/src/main/assets/foliate/view.js:255-257`（既有潛伏偵測邏輯）
- `app/android/app/src/main/assets/foliate/epub.js:1091-1095`（既有 `page-spread-*` metadata 解析）
- Readest `foliate-js` fork（`https://github.com/readest/foliate-js`），釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`
