# Epic 32 foliate-js paginator.js 上游同步：設計文件審查報告 (Design Review Report)

**審查對象：** [`docs/epics/epic-32-foliate-js-paginator-sync/design.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-32-foliate-js-paginator-sync/design.md)  
**對應工單：** `epic-32-foliate-js-paginator-sync`（新 Epic）  
**診斷依據：** [`docs/research/foliate_js_sync_update_strategy.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/research/foliate_js_sync_update_strategy.md) 既有同步 SOP ＋ 上游 commit `dd71f2b...6c6a491` diff 分析  
**審查日期：** 2026-08-25（初審：12:23，複審核准：12:28）  
**審查性質：** 架構、範圍與實作可行性設計審查（Design Spec Review）  

---

## 1. 總結評估（Executive Summary）

**整體評價：Approved（正式核准，可直接推進至 Issues 拆解與 Implementation Plan 階段）**

設計文件已針對初審提出的所有關鍵架構、時序與測試防護事項（`turn-gesture-left-inset` 預設行為確認、ES Polyfill 向下相容語法約束、直排往返對稱翻頁客觀判準）完成精準修訂。

修訂後的規格清晰、實作風險完全收斂，嚴格遵守 [ADR 0011](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0011-readium-vendoring-and-customization-boundary.md)（純淨替換、不手動修改 vendored 原始碼），正式予以複審核准通過。

---

## 2. 審查意見修訂對照（Review Findings Resolution）

| 項目 | 級別 | 初審意見摘要 | 修訂狀況與技術確認 | 狀態 |
|:---|:---|:---|:---|:---:|
| **1. `turn-gesture-left-inset` 屬性行為確認** | Important | 新增之 `turn-gesture-left-inset` 屬性需確認在直排/橫排未設定狀態下是否會干擾熱區或與 `no-swipe` 衝突。 | 已於第 41 行完成 diff 溯源確認：程式碼為 `Number(this.getAttribute('turn-gesture-left-inset')) \|\| 0`，未設定時為 `0`，預設不保留任何區域，不干擾熱區亦不與 `no-swipe` 衝突，Bridge 檢查僅需確認未設定即可。 | **Resolved** |
| **2. ES Polyfill 向下相容語法約束** | Important | 若掃描出需補齊之 Polyfill，其自身實作需防範引入 ES2021+ 語法導致舊版 WebView 語法解析失敗。 | 已於第 51–55 行明確訂定硬性規範：僅在 `if (!TargetAPI)` 缺席時定義，且本體嚴禁使用 `??=`、`?.` 等 ES2021+ 語法，維持 ES5/ES2020 相容以確保 Chromium 83 正常解析。 | **Resolved** |
| **3. 直排連續翻頁的 Smoke Test 判準** | Minor | 真機 Smoke QA 應使用客觀的往返對稱性檢驗。 | 已於第 63 行明確採納為「連續往前翻 5 頁再反向翻 5 頁，比對是否精確回到原始文字錨點無偏移」。 | **Resolved** |

---

## 3. 核心保留優點（Strengths to Preserve）

1. **及時調整時序的高槓桿架構決策**：
   - 避免在過時的 `paginator.js` 觸控實作上構建 Epic 31 `TouchIntentClassifier`，防止未來升級時再度面臨底層觸控邏輯巨變引發的架構撕裂與重複驗證。
2. **克制且精準的同步範圍控制**：
   - 僅同步至 `6c6a491`，不盲目追隨 HEAD（避開未使用的 `footnotes.js` / `pdf.js` / `tts.js` / `opds.js` 與大幅修改的 `fixed-layout.js`），極大化降低變更面與真機回歸風險。
3. **先決條件識別清晰**：
   - 準確抓出 `check_foliate_es_compat.js` 歷史檔名漂移（`foliate_epub_reader_view.dart` → `foliate_reader_view.dart`）問題並列為先決任務，確保 SOP 測試鏈條完整暢通。
4. **健全的真機驗收與 Rollback 停損機制**：
   - 將 3 個依賴 `paginator.js` 內部的歷史修法（Epic 18 Issue 47、Epic 25 Issue 1、Epic 27 Issue 9）列為真機必測清單，並制定「若遇不可調和回歸則 `git revert dd71f2b`」的清晰退場防線。

---

## 4. 結論與下一步（Conclusion & Next Steps）

設計文件所有審查意見均已圓滿修訂並通過複審。

- [x] **設計文件審查正式通過（Approved）**
- **下一步：** 建立 `docs/epics/epic-32-foliate-js-paginator-sync/issues.md` 工單清單並推進至實作計畫（Plan）撰寫階段。
