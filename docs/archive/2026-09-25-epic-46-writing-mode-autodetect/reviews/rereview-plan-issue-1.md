# Epic 46 Issue 1 — 排版方向自動偵測改為全書預掃 計畫複審報告

> **複審日期：** 2026-09-24  
> **複審對象：** `docs/epics/epic-46-writing-mode-autodetect/plans/plan-issue-1.md`  
> **前次審查：** `docs/epics/epic-46-writing-mode-autodetect/reviews/review-plan-issue-1.md`（Critical: 0 | Important: 3 | Minor: 4）  
> **複審結論：** 🟢 通過（Approved，可立即進入實作）  
> **當前問題統計：** Critical: 0 | Important: 0 | Minor: 0

---

## 複審摘要

針對 2026-09-24 初審報告所列之 3 項 Important 與 4 項 Minor 意見，作者已於 `plan-issue-1.md` 完整完成修訂與技術推敲：
- **Important 3 項**：OPF metadata 雙語法查詢、正則未閉合引號回溯防範與內嵌單引號支援、spine MIME 類型過濾，均已**全數妥善採納並補齊對應測試案例（新增 C-2、D-2，共 7 個案例）**。
- **Minor 4 項**：去註解空白替換、大小寫防禦、Chromium 實際渲染判準、紅燈失敗原因說明，亦已**全數修正與釐清**。

經全面技術複驗，所有修訂程式碼語法嚴謹、時序正確、ES 相容性無虞，未引入任何新副作用或遺漏，計畫狀態正式批准，建議立即進入實作。

---

## 前次審查意見處置覆核

| 編號 | 級別 | 項目 | 處置結論 | 覆核說明 |
|:---|:---|:---|:---|:---|
| **I-1** | Important | OPF `primary-writing-mode` 漏判 EPUB 3 property 語法 | **ADDRESSED** | 選擇器已擴充為 `meta[name="..."], meta[property="..."]`，且取值時採 `content || textContent` 雙層回退；Task 1 新增案例 D-2 驗證，處理完善。 |
| **I-2** | Important | `INLINE_STYLE_RE` 長文回溯風險與缺少 `style=""` 測試 | **ADDRESSED** | 正則改採引號分支 `(?:"([^"]*)"\|'([^']*)')`，徹底杜絕跨行標籤邊界回溯，且完美相容雙引號內包單引號之字型設定；Task 1 新增案例 C-2 驗證，處置精確。 |
| **I-3** | Important | spine 走訪未過濾 MIME Type 導致非文字資源消耗配額 | **ADDRESSED** | 於 `scanned++` 之前增加 `mediaType` 是否為 `application/xhtml+xml` 或 `text/html` 之過濾，避免 SVG/圖片等二進位或非 (X)HTML 項目佔用上限。 |
| **M-1** | Minor | CSS 去註解替換為空字串可能導致相鄰 token 黏連 | **ADDRESSED** | 已修訂為替換為單一空格 `' '`，符合 CSS 分詞語意。 |
| **M-2** | Minor | `item.mediaType` 建議增加大小寫防禦 | **ADDRESSED** | 已在外部 CSS 遍歷與 spine 遍歷全面加入 `?.toLowerCase()`。 |
| **M-3** | Minor | 註解中排除 `-ms-` 與支援 `tb-rl` 的意圖一致性 | **ADDRESSED** | 確立以「與 Chromium WebView 實際渲染結果一致」為客觀判準，明確記錄 `-ms-` 在 Chromium 上無作用故刻意排除，註解已調和一致。 |
| **M-4** | Minor | Task 1 Step 2 紅燈預期行為說明 | **ADDRESSED** | 已補充說明 A～D-2 為「漏判」、E 為「舊代碼誤判」，消弭實作者觀測紅燈時的疑慮。 |

---

## 最終結論

本實作計畫之設計目標、時序邊界、防禦機制與測試驗證均已達到專案高標準要求，無殘留待決技術問題。**批准通過，可啟動實作。**
