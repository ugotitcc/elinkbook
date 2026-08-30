# Epic 33 foliate-js 上游持續同步：設計文件審查報告 (Design Review Report)

**審查對象：** [`docs/epics/epic-33-foliate-js-vendor-sync/design.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-33-foliate-js-vendor-sync/design.md)  
**對應工單：** `epic-33-foliate-js-vendor-sync`（新 Epic）  
**診斷依據：** [`docs/research/foliate_js_sync_update_strategy.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/research/foliate_js_sync_update_strategy.md) 既有同步 SOP ＋ `readest/foliate-js` commit `6c6a491...c09f06d`（22 個 commit）diff 分析 ＋ `epic-32` 同步先例  
**審查日期：** 2026-08-26（初審：00:03，複審核准：00:14）  
**審查性質：** 架構、邊界控制與測試防護網設計審查（Design Spec Review）  

---

## 1. 總結評估（Executive Summary）

**整體評價：Approved（正式核准，可直接推進至 Issues 拆解與實作階段）**

設計文件已針對初審提出的所有架構、測試防護與邊界事項（觸控 Harness 自動化防線、ES 語法解析期防護、`relocate` 高頻發射連動分析、真機深度驗收 8 項矩陣、2 小時停損指標）完成 100% 完整且精準的修訂。

修訂後的規格清晰、實作風險完全收斂，並已解除 `epic-31` Issue 3 的排期依賴（commit `8a9be2cd` 已合併），嚴格遵守 [ADR 0011](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0011-readium-vendoring-and-customization-boundary.md)（純淨替換、不手動修改 vendored 原始碼）與 [ADR 0017](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0017-fxl-migrate-to-foliate-js.md)，正式予以複審核准通過。

---

## 2. 審查意見修訂對照表（Review Findings Resolution）

| 項目編號 | 類別 | 初審審查意見摘要 | 修訂狀況與技術確認 | 複審結果 |
|---|---|---|---|:---:|
| **Important 1** | 測試防線 | 遺漏 `epic-31` 剛建立的觸控 Harness 自動化測試（`app/tool/foliate_touch_harness/run-all.mjs`） | 已於目標第 2 項（Line 17）與測試策略新增「第二層：觸控 Harness 自動化」（Line 78–82），明確要求執行 `run-all.mjs`，4 個情境須全數 PASS 方可上真機。 | **✅ Resolved** |
| **Important 2** | 相容防護 | ES 相容性檢查缺乏語法解析期（Parse Time / SyntaxError）防護說明 | 測試策略第一層新增「語法解析期防護說明」（Line 76），深入剖析 Regex 掃描限制與 Polyfill 無法修復 Parse Time SyntaxError 的原理，明訂以 Chromium 83–91 真機開書為最終把關。 | **✅ Resolved** |
| **Important 3** | 橋接架構 | `relocate` 事件高頻發射（commit `fd91451`）對 Bridge 與 SQLite 寫入之負載需納入觀察 | 在 `paginator.js` commit 摘要（Line 61）與第二層測試（Line 81）明確加入快速連續翻頁/捲動時 `onLocatorChanged` 通訊流暢度與 `ReadingPositionRepository` 負載觀察。 | **✅ Resolved** |
| **Important 4** | 驗收矩陣 | 真機驗收矩陣缺少「橫直排動態切換」與「FXL 雙頁跨頁」核心能力 | 第三層真機深度驗收（Line 83–96）擴充為 8 項，補齊「繁中流式即時切換橫直排錨點精準維持」與「FXL 橫向雙頁跨頁與封面單頁正常排版」。 | **✅ Resolved** |
| **Minor 1** | 文檔慣例 | 版本紀錄更新清單對齊專案慣例 | 目標第 4 項（Line 19）與預計工單切片 Issue 2（Line 108）已完整涵蓋版本紀錄與看板文件收尾。 | **✅ Resolved** |
| **Minor 2** | 文檔一致 | WebKit commit 數量與摘要前後一致性 | 全文一致列出 3 個 WebKit 相關 commit（`cf9829d`、`887a0ae`、`68d54b1`），並在 Line 59 摘要中逐一補齊其行為說明與在 Android 上不額外測試之理由。 | **✅ Resolved** |
| **Minor 3** | 工單拆解 | 補充預計工單切片結構方向 | 文件尾端新增「預計工單切片方向」（Line 103–110），明確規劃為 Issue 1（資產替換 + 第一/二層驗證）與 Issue 2（第三層真機驗收 + 文檔收尾）。 | **✅ Resolved** |
| **停損指標** | 風險控管 | 明確訂定 2 小時內排除失敗即 revert 的快速停損標準 | 已知風險章節（Line 101）明確訂定：若直排對稱翻頁失敗或出現 SyntaxError 且無法於 2 小時內排除，立即 `git revert` 退回 `6c6a491`。 | **✅ Resolved** |

---

## 3. 核心保留優點（Strengths to Preserve）

1. **三層測試管線（Three-tier Verification Pipeline）極具工程嚴謹度**：
   - **第一層（靜態與單元）**：以 `flutter analyze`、`flutter test` 及 `check_foliate_es_compat.js` 快速過濾低級錯誤。
   - **第二層（觸控 Harness 自動化）**：以 Puppeteer 端對端觸控模擬，在不依賴真機的情況下秒級攔截 `TouchIntentClassifier` 與上游手勢衝突。
   - **第三層（真機深度驗收）**：涵蓋 3 項歷史修法、2 項直排核心與 3 項固定版面能力，構成 8 項不可妥協的 GO/NO-GO 門檻。
2. **邊界控制維持一貫高標準**：
   - 堅守 ADR 0011（不手動修改 vendored 檔案原始碼，純粹整份覆蓋）。
   - 對 4 個上游新檔案（`footnotes.js`、`pdf.js`、`tts.js`、`opds.js`）與新暴露屬性（`scroll-direction`、sub-pixel scroll offset）採取明確的 Non-Goals 與隔離策略。
3. **即時反映排期狀態**：
   - 準確標記 `epic-31` Issue 3 已於 commit `8a9be2cd` 完成合併，排期依賴順利解除，可無縫銜接。

---

## 4. 結論與下一步（Conclusion & Next Steps）

設計文件所有初審意見均已圓滿修訂並通過複審。

- [x] **設計文件審查正式通過（Approved）**
- **下一步：** 建立 `docs/epics/epic-33-foliate-js-vendor-sync/issues.md` 工單清單並推進至實作計畫（Plan）撰寫階段。
