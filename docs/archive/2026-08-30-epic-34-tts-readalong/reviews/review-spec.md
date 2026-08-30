# Epic 34 TTS 語音朗讀與同步高亮（Read-along）：規格文件審查報告 (Spec Review Report)

**審查對象：** [`docs/epics/epic-34-tts-readalong/spec.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/spec.md)  
**對應工單：** `epic-34-tts-readalong`（新 Epic）  
**診斷依據：** 
- [`docs/epics/epic-34-tts-readalong/design.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/design.md)（Discovery 決策與複審核准文件）
- [`docs/adr/0026-tts-highlight-ephemeral-not-persisted.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0026-tts-highlight-ephemeral-not-persisted.md)（TTS 朗讀高亮採暫態 UI 狀態不持久化）
- [`docs/research/tts_integration_architecture_research.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/research/tts_integration_architecture_research.md)（Foliate 篇架構研究）
- [`docs/research/pdf_tts_integration_architecture_research.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/research/pdf_tts_integration_architecture_research.md)（PDF 篇架構研究）
- [`docs/prd.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md) FR-45～FR-48  
**審查日期：** 2026-08-26（初審：19:49，複審核准：19:54）  
**審查性質：** 規格完備性、領域模型一致性、狀態機邊界與測試縫隙可行性審查（Technical Spec Review）  

---

## 1. 總結評估（Executive Summary）

**整體評價：Approved（正式核准，可直接推進至 Scrum Master 工單拆解 `issues.md` 階段）**

本規格文件（`spec.md`）已針對初審提出的所有架構實作細節（Phase 1 暫存檔覆寫與生命週期清理、跨 DOM 標籤分句 CFI 測試、Audio Focus 狀態機、Mini Player 層級連動、執行期即時變速模式）完成 100% 精準修訂。

修訂後的規格文件具備以下關鍵特質：
1. **全面覆蓋使用者情境（Comprehensive User Stories）**：涵蓋 28 條使用者故事，從基礎播放、系統整合（背景播放/線控/通知欄）、同步高亮、手動導覽自動暫停，到注音/Ruby 過濾、簡繁轉換聯動與前景恢復同步，邊界極其完整。
2. **領域模型與管線收斂（Unified Architecture Pipeline）**：堅決落實「音訊合成一律走檔案管線」架構決策，使 Phase 1（系統原生）、Phase 2（雲端 API）與 Phase 3（端側 ONNX）共用完全同一套播放器、`TtsTimeline` 與 `audio_service` 控制流；並完整補齊了手動導覽「反向索引（CFI/Page 反查 Segment）」與「前景恢復主動重送高亮」之契約。
3. **資料模型嚴格隔離（Zero DB Pollution）**：嚴格遵循 [ADR 0026](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0026-tts-highlight-ephemeral-not-persisted.md)，高亮完全在 UI / Overlayer 暫態層處理；Phase 2 的 `TtsCacheManager` 使用獨立 SQLite 資料表，杜絕污染持久化劃線表。
4. **測試縫隙劃分清晰（Crisp Test Boundaries）**：精準區分 Widget 測試（Fake ReaderView 回呼斷言）、純 Dart 單元測試（記憶體 DB、Fake Provider、跨標籤切句 CFI 驗證、邊界查找）與真機整合測試（MediaSession、通知欄、背景節流實測）。

所有審查意見均已圓滿收斂，正式予以複審核准通過。

---

## 2. 審查意見修訂對照表（Review Findings Resolution）

| 項目編號 | 類別 | 初審審查意見摘要 | 修訂狀況與技術確認 | 複審結果 |
|---|---|---|---|:---:|
| **Important 1** | 暫存管理 | Phase 1 暫存音訊檔需規範命名空間與生命週期清理，避免孤立檔案堆積 | 已於第 107 行補齊：Phase 1 採固定命名空間＋朗讀段索引覆寫機制（不逐段累積），並將清理時機明確綁定 `TtsController` 生命週期（`dispose()`、切換書籍、播放結束即清除）。 | **✅ Resolved** |
| **Important 2** | 跨標籤切句 | Foliate 跨 DOM 標籤（含 `<em>`/`<ruby>`）分句需驗證 CFI 產生與 Range 還原 | 已於測試決策第 153 行明確規定：將跨多個 DOM 節點（含 `<em>`、`<span>`、`<ruby>`/`<rt>`）之章節樣本納入核心單元測試，驗證切句 CFI 能正確還原為合法 DOM Range 並被 `Overlayer` 渲染。 | **✅ Resolved** |
| **Important 3** | 音訊焦點 | 需定義 Android Audio Focus（暫時/永久遺失）之狀態機轉換政策 | 已於第 113–116 行明確規範：暫時失去焦點（`AUDIOFOCUS_LOSS_TRANSIENT`）暫停並於焦點恢復時自動續播；永久失去焦點（`AUDIOFOCUS_LOSS`）暫停並釋放音訊硬體、不自動續播。 | **✅ Resolved** |
| **Minor 1** | UI 層級 | Mini Player 需與 Reader 既有底部工具列/目錄選單連動 | 已於第 131 行明確補上：Mini Player 掛載於底部工具列體系，並與導覽列/目錄側邊欄之展開/隱藏連動，避免畫面元素互相遮擋。 | **✅ Resolved** |
| **Minor 2** | 語速變更 | 語速調整宜採用播放器執行期變速以達零延遲響應 | 已於第 109 行明確釐清契約：播放中段落直接以播放器執行期變速（`player.setSpeed()`）達成零延遲生效，下一段尚未合成之段落才以新語速傳入 `synthesize()`。 | **✅ Resolved** |

---

## 3. 核心架構優點（Strengths to Preserve）

1. **唯一事實來源（Single Source of Truth）定位清晰**：
   - 明確宣示本規格為核心介面/型別的唯一基準，消除後續實作計畫與研究文件敘述分歧的風險。
2. **前後台與系統生命週期防禦完備**：
   - 充分考慮 Android 系統對背景 WebView JS 的節流機制，在 `TtsController` 明確納入 `AppLifecycleState.resumed` 前景恢復時主動重送高亮與翻頁指令的防禦機制（User Story 28）。
3. **手動導覽雙向索引設計健全**：
   - `TtsTimeline` 正向（時間→段落）與反向（可視 CFI / Page 座標→段落）查找契約完整，確保手動翻頁/跳章自動暫停後，按下播放時能精確從當前可視畫面起讀。
4. **效能約束與既有 NFR 防護**：
   - PDF 端規劃 `PdfPageTextCache`，採用純 Dart LRU 快取與 Lazy 擷取策略，確保 100MB+ PDF <2 秒開啟之硬性指標不受 TTS 影響。
5. **依賴注入與既有測試解耦**：
   - `ReaderScreen` 採用可選（nullable）注入模式，維持既有 Widget 測試不受破壞，並比照既有工具列/FAB 模式疊加 Mini Player。

---

## 4. 結論與下一步（Conclusion & Next Steps）

規格文件所有審查意見均已圓滿修訂並通過複審。

- [x] **規格文件審查正式通過（Approved）**
- **下一步：** 推進至 **Scrum Master 階段**，於 [`docs/epics/epic-34-tts-readalong/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/issues.md) 建立垂直切片工單清單，隨後按 Issue 撰寫實作計畫（Plan）。
