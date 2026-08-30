# Epic 33 foliate-js 上游持續同步：工單清單審查報告 (Issues Review Report)

**審查對象：** [`docs/epics/epic-33-foliate-js-vendor-sync/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-33-foliate-js-vendor-sync/issues.md)  
**對應工單：** `epic-33-foliate-js-vendor-sync`（新 Epic）  
**對照基準：**
1. 設計文件：[`docs/epics/epic-33-foliate-js-vendor-sync/design.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-33-foliate-js-vendor-sync/design.md)
2. 設計審查報告：[`docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-design.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-33-foliate-js-vendor-sync/reviews/review-design.md)
3. 同步 SOP：[`docs/research/foliate_js_sync_update_strategy.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/research/foliate_js_sync_update_strategy.md)
4. 先前工單先例：[`docs/epics/epic-32-foliate-js-paginator-sync/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-32-foliate-js-paginator-sync/issues.md)

**審查日期：** 2026-08-26  
**審查性質：** 工單架構、設計溯源與驗收標準審查（Issues Specification Review）  

---

## 1. 總結評估（Executive Summary）

**整體評價：Approved（正式核准，工單規格完整，可直接推進至實作計畫 Plan 撰寫階段）**

`epic-33-foliate-js-vendor-sync/issues.md` 嚴格且精準地繼承了 `design.md`（含 `review-design.md` 複審意見）的所有架構約束、資產同步範圍與三層驗證防護網。工單拆分為 2 個線性依賴的工作項目（Issue 1 與 Issue 2），邊界清晰、依賴明確、驗收標準客觀可驗證，並具備明確的 2 小時快速停損機制與 [ADR 0011](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0011-readium-vendoring-and-customization-boundary.md) / [ADR 0017](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0017-fxl-migrate-to-foliate-js.md) 合規性。

---

## 2. 審查維度詳細檢驗（Review Dimensions Analysis）

### 維度 1：設計溯源與完整性（Traceability & Completeness）—— ✅ 100% 覆蓋
- **資產同步覆蓋**：Issue 1 完整列出 7 個需覆蓋的 vendored 檔案清單（`paginator.js`、`epub.js`、`fixed-layout.js`、`view.js`、`overlayer.js`、`epubcfi.js`、`comic-book.js`），並明確標示其餘 5 個檔案零變動不處理。
- **非目標約束貫徹**：
  - 明確排除 4 個上游新檔案（`footnotes.js`、`pdf.js`、`tts.js`、`opds.js`）。
  - 對 `cf9829d`、`887a0ae`、`68d54b1` 3 個 WebKit 相關 commit 註記隨檔案帶入、不額外耗費時間在 Android 上測試。
  - 禁止啟用 `fixed-layout.js` 之 `scroll-direction` 與 `paginator.js` 之 sub-pixel scroll offset 新能力。
  - 嚴守 ADR 0011（純淨覆蓋、不手動修改 vendored 原始碼）。
- **三層防護網落實**：
  - **第一層（靜態與單元）**：納入 `check_foliate_es_compat.js` Regex 掃描限制說明（無法攔截 Parse Time `SyntaxError`，由真機把關）及 Polyfill 硬性撰寫規範（ES5/ES2020 相容）。
  - **第二層（觸控 Harness 自動化）**：明確納入 `node app/tool/foliate_touch_harness/run-all.mjs` 4 個情境全過，並將 `fd91451` 高頻 `relocate` 對 `onLocatorChanged` 通訊與 `ReadingPositionRepository` 寫入負載列入重點觀察。
  - **第三層（真機深度驗收）**：完整移植 `design.md` 的 8 項真機矩陣（3 歷史修法 + 2 直排核心 + 3 固定版面）。

### 維度 2：工單切片合理性（Slicing & Dependency）—— ✅ 結構精確、職責分明
- **切分顆粒度**：
  - **Issue 1（資產升級與第一/二層自動化測試）**：聚焦於代碼替換、靜態掃描、Polyfill 補齊、Bridge 簽章對齊與 Harness 自動化。
  - **Issue 2（真機深度驗收與文檔收尾）**：聚焦於 8 項真機 QA、2 小時停損判斷、`strategy.md` 與 `epics.md` 版本收尾。
- **依賴管理**：
  - Issue 1 依賴為無（`epic-31` Issue 3 已於 commit `8a9be2cd` 合併，排期依賴完全解除），Status 標記為 `ready-for-agent`。
  - Issue 2 線性依賴 Issue 1，無任何環狀相依或模糊交集。

### 維度 3：驗收標準與停損防線（Acceptance & Contingency）—— ✅ 客觀、無歧義
- **驗收標準**：各項要求皆有明確的命令執行結束碼（如 ES 掃描 exit 0、Harness 4 情境 PASS、`flutter analyze` 乾淨）或客觀行為標準（如 5 次連續往返回到原始錨點）。
- **停損防線（Contingency Plan）**：Issue 2 明確訂定快速停損指標——若直排對稱翻頁失敗或出現 Chromium 83–91 機型 `SyntaxError` 且無法於 **2 小時內** 排除，立即執行 `git revert` 退回 `6c6a491`，避免陷入無限調試。

### 維度 4：專案規格與格式一致性（Conventions & Consistency）—— ✅ 符合標準
- **欄位齊全度**：每個 Issue 皆包含 `Status`、`依賴`、`來源`、`背景／需求`、`設計要點`、`測試要求`、`驗收標準`，與 `epic-32/issues.md` 及專案工單追蹤規範完全一致。
- **路徑與契約一致**：正確參照已重構之路徑 `app/lib/reader/foliate_reader_view.dart`，未出現過時命名。

---

## 3. 核心優點（Strengths）

1. **架構溯源極其嚴密**：完全對齊 `design.md` 與 `review-design.md`，審查修訂的重點（Harness 測試、高頻 relocate 負載、Parse Time 語法說明、8 項真機矩陣）全數精準無誤地體現在工單中。
2. **實作邊界非常乾淨**：清晰區分「整份替換 vendored 檔案」與「禁止啟用新屬性/禁止修改上游檔案」，防止開發過程產生範圍蔓延（Scope Creep）。
3. **測試層級具備可操作性**：將測試拆解為循序漸進的三層，由 CI 可執行的靜態與 Harness 先行攔截 90% 基礎錯誤，最後由 8 項真機矩陣守住直排與 E-Ink 體驗的核心底線。

---

## 4. 發現問題（Issues）

- **Critical（嚴重阻礙）：** 0 項
- **Important（重要缺失）：** 0 項
- **Minor（微小建議）：** 0 項

*工單定義明確且完整，無需要修正之技術瑕疵。*

---

## 5. 實作階段建議（Recommendations）

1. **實作計畫（Plan）撰寫**：
   - Issue 1 撰寫實作計畫時，建議將「下載 7 個檔案」以單一腳本或 curl 指令清單條列，確保下載來源 SHA 統一為 `c09f06d`。
2. **真機測試記錄規格**：
   - Issue 2 在執行真機測試時，建議於 `reviews/review-issue-2.md` 中採用結構化表格，依 8 項驗證點逐一記錄測試裝置型號（含舊版 WebView 的 E-Ink 機型與主流機型）與測試結果，維持高品質追蹤紀錄。

---

## 6. 結論與下一步（Conclusion & Next Steps）

- [x] **工單清單審查正式通過（Approved）**
- **下一步：** 撰寫 `docs/epics/epic-33-foliate-js-vendor-sync/plans/plan-issue-1.md` 實作計畫並啟動開發。
