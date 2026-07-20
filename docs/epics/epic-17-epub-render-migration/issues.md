# Epic 17 — EPUB 渲染引擎遷移評估：工單清單 (Issues)

依 `design.md`（`tmp/epic-17/reviews/design-review.md` 審查修正）拆解出的工單。本 Epic 本次 Discovery 範圍僅止於一個前置技術驗證 Spike（不做完整遷移架構設計，見 `design.md`「明確排除」段落），故只有單一工單，不做多層垂直切片——比照 `epic-7-interaction` Issue 1／Issue 9 先例（一次性研究/驗證性質工單）。

---

## Issue 1：Spike——`readest/foliate-js` 真機直排分頁穩定性驗證

**Status:** ✅ 已完成。依 `plans/plan-issue-1.md` Task 1-5 完成 Harness 建置、真機插樁量測與判準分類，結論寫入 `reviews/spike-foliate-js-vertical.md`。以釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`（2026-07-19）打包的 `readest/foliate-js`，在真機 Android WebView（`3CEF42ECD491687`，Android 15／API 35）上對 `issue9_vertical_pagejump.epub` 正文段落連續觸發 3 次「下一頁」+ 3 次「上一頁」：6 次觸發皆可視內容無縫銜接、內部 `fraction` 皆為預期單步變化（無多步跳躍、無 0 步被吃掉），且往返路徑以截圖逐位元組比對（`prev-1≡next-2`、`prev-2≡next-1`、`prev-3≡start`）證實完全對稱。依 `design.md`「判準」表分類為**通過**，構成 **GO** 訊號。**下一步進入 Architecting 階段**，撰寫 `spec.md`，並重新逐項確認 `foliate-js-migration-feasibility-assessment.md` 既有的 6 項共識決策。Harness throwaway 專案已從裝置解除安裝，過程中的暫時性素材（截圖、logcat、Harness Android 專案）皆位於 `tmp/`（已 gitignore），未進版控。

**依賴：** 無（起始工單，可立即開始）

**描述：**

`design.md` 已確認「直排繁體中文上下翻頁跳頁」是 Readium 生態系已知、且官方已擱置的缺口（`readium/kotlin-toolkit#458`、`readium/css#141`），非本專案整合問題。`foliate-js`（`readest/foliate-js` fork）是候選替代方案，但是否值得投入完整遷移，取決於它在真機 Android WebView 上能否穩定處理直排分頁——這正是本工單要驗證的唯一問題。

本工單為一次性研究/驗證工作，產出是一份判定報告與明確的 GO/NO-GO 結論，不是長期功能程式碼：

- **Harness 建置**：新建一個獨立、throwaway 的最小 Android 專案（單一 `Activity` + 單一 `android.webkit.WebView`），不屬於 `app/`、不修改 `app/` 下任何檔案。
  - 打包 `readest/foliate-js` 的必要 JS/CSS assets 與一個最小 HTML 載入頁面（比照 `foliate-js-migration-feasibility-assessment.md` 3.1 節設想的靜態資源打包方式）。
  - 釘定 `readest/foliate-js` 特定 Git commit SHA 打包，不追蹤 main 分支最新狀態，確保結果可重複驗證。
  - 配置 `WebViewAssetLoader` 或啟用 `setAllowFileAccessFromFileURLs(true)`（僅限本 throwaway spike），避免 `file://` 同源政策擋下動態 `import()`/`fetch()` 讀取的 EPUB 內容（zip 內字型/圖片/XHTML/CSS）。
  - Harness 需能：載入本機 EPUB 檔案、切換為 `vertical-rl` 排版、提供「上一頁」/「下一頁」兩個可程式化觸發的操作（畫面按鈕或可由 `adb shell input tap` 觸發的固定座標元件即可）。
- **重現素材**：沿用 `app/test/fixtures/issue9_vertical_pagejump.epub`（與 `epic-7-interaction` Issue 9 spike 同一份素材，確保可與既有 Readium 基準直接比較）。
- **觸發量測**：排版方向固定 `vertical-rl`；選擇有正文內容的章節頁面；至少連續 3 次「下一頁」+ 至少連續 3 次「上一頁」單次觸發，每次觸發間隔足夠時間讓畫面穩定。每次觸發前後記錄：(a) 可視內容是否連續——操作型定義為「翻頁前畫面最後一個字/詞，是否與翻頁後畫面第一個字/詞無縫銜接」；(b) `foliate-js` 內部分頁進度指標（`Paginator`/`View` 暴露的頁碼或位置狀態）前後值。
- **判準**（見 `design.md`「Spike 驗證方法與判準」）：
  - **通過**：所有觸發皆內容連續、內部分頁位置皆單步變化 → GO 訊號。
  - **計數器層級抖動（不算失敗）**：內容連續，但周邊計數器（頁碼標籤/總頁數）不同步 → 仍視為 GO 訊號，但記錄為已知殘留風險。
  - **失敗**：任一次觸發內容真正跳過/重複、或內部分頁位置多步跳躍、或觸發被吃掉（0 步變化） → NO-GO 訊號。
- **GO/NO-GO 決策路徑**：
  - GO（通過或計數器抖動）：於 `design.md` 記錄 Spike 結果，進入 Architecting 階段（撰寫 `spec.md`），本工單即算完成，不在本工單內展開架構設計。
  - NO-GO（失敗）：記錄具體失敗證據於本 Epic `reviews/`，`design.md` 補上「已評估並否決」的結論與理由，ADR 0001 維持現狀不變，Epic 標記完成並歸檔。

**單元測試要求：** 無（研究/驗證性質，比照 `epic-7-interaction` Issue 1／Issue 9 先例；過程中若產生暫時性程式碼或素材，驗證後需清理，不留在版本控制中）

**驗收標準：**
- 4 種組合中實際只需要「直排 × 上一頁」「直排 × 下一頁」兩類觸發（本 Spike 只驗證 `vertical-rl` 這個維度，見 `design.md` 決策 #1／範圍外段落），至少 3+3 次觸發皆有明確數據與結論。
- 明確依判準表分類（通過／計數器抖動／失敗），並附具體證據（截圖、DOM 文字比對、`Paginator`/`View` 前後狀態值），寫入驗證報告（建議路徑：`docs/epics/epic-17-epub-render-migration/reviews/spike-foliate-js-vertical.md`）。
- 依 GO/NO-GO 結果更新 `design.md` 對應段落；若 NO-GO，一併確認 ADR 0001 是否需要註記。
- Harness 打包的 `readest/foliate-js` commit SHA 已記錄於報告中，供未來重現。
- 過程中的暫時性程式碼/素材已清理，`git status` 乾淨（不含本 Epic 目錄下的正式文件更新）。
