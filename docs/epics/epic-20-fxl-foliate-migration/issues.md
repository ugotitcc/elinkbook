# Epic 20 — FXL 渲染引擎遷移評估：Issue 追蹤

## Issue 1：Spike——`readest/foliate-js` 的 `fixed-layout.js` 能否正確處理 FXL 漫畫橫向雙頁/RTL/封面獨立顯示

**Status:** ✅ 已完成，**結論 GO**（2026-07-31，真機以真實問題書籍《一弦定音！(11)》驗證，4 項核心判準全數通過，完整證據見 `reviews/spike-issue1-fxl-foliate.md`）。過程中曾有兩輪驗證嘗試因證據與結論矛盾／測試素材誤用而被獨立覆核判定不成立（見報告內「本報告狀態說明」），第三輪由執行者本人直接操作真機、使用真實問題書籍取得最終結論。`epic-18` Issue 20/21 已由本 Issue 取代，不再執行。

**依賴：** 無（起始工單）。

**背景：** 見 `design.md`「問題陳述」。已查證我們現有 vendored `readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`）的 `view.js` 已有偵測 FXL 並動態 `import('./fixed-layout.js')` 的潛伏邏輯，`epub.js` 已在解析 `page-spread-*` metadata，但 `fixed-layout.js` 本身當初（ADR 0011 Phase 1）未被 vendored 進來。人類提供的兩份外部分析報告（Anx Reader／Readest 皆用 foliate-js 處理 FXL 漫畫且效果良好）觸發本次評估。

**驗證範圍：**

1. **主要驗證**：獨立 throwaway Android 測試專案（比照 `epic-17` Issue 1 既有 harness 設計），打包釘定 commit 的 `readest/foliate-js`（額外補上 `fixed-layout.js`），真機開啟已知會被誤判為流式的漫畫 EPUB（RTL、多頁，沿用 `epic-18` Issue 15/17/18/19 一路使用的同一本），裝置橫向、雙頁模式下驗證：
   - 橫向雙頁排版是否正確顯示兩頁並排。
   - 封面是否獨立成頁，第二頁起是否正確兩兩配對（`1,3-2,5-4`）。
   - RTL 頁序是否正確（`[3｜2]`／`[5｜4]`）。
   - 連續翻頁 3 次以上內容是否連續無跳過/重複。
2. **觀察性質（不影響 GO/NO-GO）**：大尺寸漫畫圖片頁的載入效能/記憶體表現；1px 白縫等視覺細節。

**明確不在本 Issue 範圍**：完整遷移架構設計（`EpubReaderView.kt`/Readium FXL 路徑是否退場、既有資料轉換、劃線/備註/書籤對接）——這些留待 GO 之後的 Architecting 階段（`spec.md`）。

**GO/NO-GO 決策路徑：**
- **GO**（判準表 4 項核心項目皆通過，見 `design.md`「Spike 驗證方法與判準」）：記錄結果，進入 Architecting 階段，`epic-18` Issue 20/21 正式標記為「被本 Epic 取代，不再執行」。
- **NO-GO**（任一核心項目失敗，或效能/記憶體有無法接受的明顯問題）：記錄具體失敗證據，本 Epic 結束，`epic-18` Issue 20/21 恢復依原計畫執行。

**單元測試要求：** 無（研究/驗證性質，比照 `epic-17` Issue 1、`epic-18` Issue 8/17/18 先例）。過程中產生的 harness 專案與素材（截圖/log）驗證後需清理，不進版控（放 `tmp/`，已 gitignore）。

**驗收標準：**
- 真機以已知問題漫畫書驗證，明確記錄 GO/NO-GO 判定與依據（截圖或 log 佐證）。
- 依結果更新 `design.md`／`issues.md` 對應狀態，以及 `epic-18` Issue 20/21 的狀態。

**相關佐證：**
- `docs/epics/epic-20-fxl-foliate-migration/design.md`「問題陳述」「Spike 驗證方法與判準」
- `docs/archive/2026-07-24-epic-17-epub-render-migration/plans/plan-issue-1.md`（Spike harness 既有先例，方法論參考）
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 16-21
- `docs/epics/epic-18-reader-device-qa/reviews/readest_foliate_fxl_spread_analysis.md`／`anx_reader_foliate_fxl_spread_analysis.md`
- `app/android/app/src/main/assets/foliate/view.js:255-257`、`epub.js:1091-1095`
