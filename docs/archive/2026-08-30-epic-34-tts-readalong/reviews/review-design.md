# Epic 34 TTS 語音朗讀與同步高亮（Read-along）：設計文件審查報告 (Design Review Report)

**審查對象：** [`docs/epics/epic-34-tts-readalong/design.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/design.md)  
**對應工單：** `epic-34-tts-readalong`（新 Epic）  
**診斷依據：** 
- [`docs/research/tts_integration_architecture_research.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/research/tts_integration_architecture_research.md)（Foliate 格式篇——EPUB／KF8／CBZ／TXT／MD 架構研究）
- [`docs/research/pdf_tts_integration_architecture_research.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/research/pdf_tts_integration_architecture_research.md)（PDF 篇——PDF 專屬定位/高亮差異）
- [`docs/adr/0026-tts-highlight-ephemeral-not-persisted.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0026-tts-highlight-ephemeral-not-persisted.md)（TTS 朗讀高亮採暫態 UI 狀態不持久化）
- `/grill-with-docs` Discovery 訪談決策紀錄（4 輪、12 題共識）
- [`docs/prd.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/prd.md) FR-45（TTS）／FR-46（Read-along 同步高亮）／FR-47（PDF TTS）／FR-48（簡繁轉換聯動）  
**審查日期：** 2026-08-26（初審：17:19，複審核准：19:38）  
**審查性質：** 架構完整性、資料流邊界、跨格式相容性與實作可行性設計審查（Design Spec Review）  

---

## 1. 總結評估（Executive Summary）

**整體評價：Approved（正式核准，可直接推進至 Architecting／`spec.md` 與 Issues 拆解階段）**

設計文件已針對初審提出的所有架構細節、反向索引契約、前景/背景生命週期同步與快取策略完成 100% 完整修訂。

修訂後的設計文件具備以下關鍵特質：
1. **堅持重用既有基礎設施（Maximum Reuse）**：Foliate 端完全重用 `overlayer.js`／`epubcfi.js` 與既有 `view.addAnnotation()` 管道，PDF 端重用 `pdfrx.loadStructuredText()` 與 `pageOverlaysBuilder`，堅決不另建平行機制、絕不篡改 DOM、嚴格遵守 [ADR 0011](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0011-readium-vendoring-and-customization-boundary.md) 與 [ADR 0013](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0013-flutter-inappwebview-for-foliate-selection.md)。
2. **資料模型邊界清晰（Domain Boundary Isolation）**：明確遵循 [ADR 0026](file:///U:/MyDeveloper/AI/elinkBook/docs/adr/0026-tts-highlight-ephemeral-not-persisted.md)，將 TTS 高亮嚴格界定為暫態 UI 狀態，杜絕了污染持久化 `highlights` 資料表與引發同步風暴的架構陷阱。
3. **管線統一與生命週期防護（Unified Pipeline & Lifecycle Resilience）**：拍板所有 Provider 統一走 `synthesizeToFile()` 檔案管線，並明確定義手動導覽反向索引與 App 回到前景時的主動高亮同步協議。

所有審查意見均已圓滿收斂，正式予以複審核准通過。

---

## 2. 審查意見修訂對照表（Review Findings Resolution）

| 項目編號 | 類別 | 初審審查意見摘要 | 修訂狀況與技術確認 | 複審結果 |
|---|---|---|---|:---:|
| **Important 1** | 音訊管線 | 需拍板 `SystemTtsProvider` 是否走檔案合成管線以統一播放器與 `audio_service` 控制 | 已於「已拍板決策」新增第 9 點（Line 34）明確拍板：所有 Provider 一律回傳 `audioFilePath`，`flutter_tts` 走 `synthesizeToFile()` 產生暫存檔，統一交由 `just_audio`/`audioplayers` 播放；並於「待決事項」（Line 85）列入延遲與暫存檔清理實測。 | **✅ Resolved** |
| **Important 2** | 索引契約 | 手動翻頁後「由畫面新位置起讀」需要可視位置反查 Segment 之反向索引契約 | 已於「待決事項」（Line 86）明確規範：`TtsTimeline`／`SentenceCfiIndexer` 於 `spec.md` 階段必須補上 `lookupSegmentByCfi(visibleCfi)` 與 PDF 端 `lookupSegmentByPage(pageIndex)` 介面契約。 | **✅ Resolved** |
| **Important 3** | 背景同步 | Android 背景 WebView 節流導致前景恢復時畫面高亮可能滯後 | 已於「待決事項」（Line 87）明確補齊背景/前景同步協議：規範當 App 收到 `AppLifecycleState.resumed` 時，`TtsController` 主動向 WebView 重送最新播放位置之高亮與翻頁指令。 | **✅ Resolved** |
| **Minor 1** | 快取管理 | 需預留 Phase 2 音訊快取上限與 LRU 清理策略 | 已於 Phase 2 藍圖（Line 66）明確加入 `TtsCacheManager` 含快取上限與 LRU 淘汰策略。 | **✅ Resolved** |
| **Minor 2** | E-Ink 連動 | 跨頁自動翻頁時需確認 E-Ink 刷新與高亮靜態化之協同 | 已於測試策略（Line 78）明確澄清：專案採 `isEinkMode` 旗標 + 靜態渲染，確認跨頁自動翻頁正常繪製且句級高亮切換不觸發全螢幕閃爍。 | **✅ Resolved** |

---

## 3. 核心保留優點（Strengths to Preserve）

1. **架構分層與抽象極具擴充性（Clean Architecture）**：
   - 採納「三合一融合架構」：Provider 抽象層（多語音來源）＋ 伴隨快取/播放系統（`audio_service` 背景播放）＋ 排版無損高亮（既有 `Overlayer`）。
   - 將 Foliate 格式（EPUB/KF8/TXT/MD）與 PDF 格式在底層引擎之差異收斂於適配層，上層 Mini Player、鎖定畫面控制與 Provider 選擇達成 100% 共用。
2. **座標系與時間軸解耦設計精確**：
   - 徹底杜絕「在 50ms 音訊 tick 中解析 CFI 或搜尋 DOM」的效能反模式，採用「章節載入時建立 Segment→CFI 索引，播放時以二分搜尋定位，僅在 Segment 切換時才轉換 Range 繪製」的事件驅動模型。
3. **E-Ink 電子墨水螢幕友善性**：
   - 納入句級靜態高亮、停用漸變動畫、安全視窗（Safe Zone Viewport, 20%~80%）滾動/翻頁機制，充分體現 elinkBook 作為專業 E-Ink 閱讀器的核心價值。
4. **互動邊界定義精確（Deterministic UX State Machine）**：
   - 明確定義手動導覽（翻頁/跳章）時「自動暫停」與恢復播放時「由目前可視畫面新位置起讀」的行為，避免音訊與畫面長期不同步或回跳舊位置的使用者困惑。
5. **分期策略務實漸進（Pragmatic Phasing）**：
   - Phase 0（相依性驗證）→ Phase 1（系統原生 Foliate MVP）→ Phase 2（雲端與快取）→ Phase 3（端側神經 Stretch Goal）→ Phase 4（PDF 擴充），切片清晰，每階段皆具備獨立可交付性。

---

## 4. 結論與下一步（Conclusion & Next Steps）

設計文件所有審查意見均已圓滿修訂並通過複審。

- [x] **設計文件審查正式通過（Approved）**
- **下一步：** 推進至 Architecting 階段，撰寫詳細技術規格 [`docs/epics/epic-34-tts-readalong/spec.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/spec.md)，並隨後進行工單拆解（`issues.md`）。
