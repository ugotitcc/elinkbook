# Epic 34 Issue 2 實作計畫複審報告 (Plan Re-Review Report)

**審查對象：** [`docs/epics/epic-34-tts-readalong/plans/plan-issue-2.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-2.md)  
**對應工單：** `docs/epics/epic-34-tts-readalong/issues.md` Issue 2：最小朗讀閉環——系統語音逐句朗讀＋手動播放/暫停  
**診斷依據：** 
- [`docs/epics/epic-34-tts-readalong/spec.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/spec.md)「Implementation Decisions」與「Testing Decisions」
- [`docs/epics/epic-34-tts-readalong/design.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/design.md) 決策 9（音訊合成一律走檔案管線）
- [`docs/epics/epic-34-tts-readalong/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/issues.md) Issue 2 驗收標準
- [`docs/epics/epic-34-tts-readalong/dependency-spike-findings.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/dependency-spike-findings.md)（Issue 1 驗證成果）  
**審查日期：** 2026-08-26  
**複審性質：** 實作計畫修訂複審（Implementation Plan Re-Review）  

---

## 1. 總結評估（Executive Summary）

**整體評價：Approved（正式核准，無條件通過，可立即進入執行階段）**

本實作計畫針對前一輪審查提出的 2 項重要防禦建議（Important）與 3 項細部優化（Minor）進行了徹底且精準的修訂。修訂後的計畫不僅修補了邊界非同步競態與例外漏洞，亦同步擴充了完整的單元測試斷言，展現出極高水準的軟體架構品質與防禦性工程思維。

---

## 2. 審查意見修訂覆核清單（Verification of Fixes）

| 項目 | 級別 | 審查問題 | 修訂狀態 | 覆核結果 |
| :--- | :--- | :--- | :--- | :--- |
| 1 | ⚠️ Important | `TtsController._playCurrentSegment` 缺少非同步例外捕獲，合成或 I/O 失敗會導致狀態卡在 `playing` | **已修正** | `_playCurrentSegment()` 加入完整 `try-catch`，捕捉例外時重設 `_status = idle`、`_currentIndex = -1` 並 `notifyListeners()`。同時在 `FakeTtsProvider` 增加 `nextSynthesizeError`，並於 `tts_controller_test.dart` 新增 2 個例外測試。 |
| 2 | ⚠️ Important | `TtsController.play()` 在 `idle` $\to$ `await loadSegments()` 期間無防重入保護，連點會觸發並發競態 | **已修正** | 引入 `_isLoadingSegments` 旗標與 `try-finally` 保護，連點自動攔截。`tts_controller_test.dart` 新增連點防重入單元測試。 |
| 3 | 💡 Minor | `main.js` `buildTtsSegments` 節點比對未考慮 XHTML 小寫標籤問題 | **已修正** | 採用 `node.parentElement.tagName.toUpperCase()` 比對，消除 XML 解析器下的大小寫歧異。 |
| 4 | 💡 Minor | `main.js` 切句 Range 起訖直接使用包含空白字元的索引 | **已修正** | 引入 `while (rangeStart < i && /\s/.test(...)) rangeStart++`，使 Range 起訖精確對齊非空白正文，為 Issue 3 高亮奠定乾淨基底。 |
| 5 | 💡 Minor | `FoliateReaderView._requestTtsSegments` 之 Completer 無逾時保護 | **已修正** | 加入 `.timeout(const Duration(seconds: 5), onTimeout: ...)` 防禦，避免 WebView 異常時呼叫端永久掛死。 |

---

## 3. 核心優點（Strengths）

1. **極高可測性與 TDD 嚴謹度**：
   - 13 個單元測試全面覆蓋 `TtsController` 的所有狀態轉換（`idle`/`playing`/`paused`）、自動接續下一句、最後一句結束、非同步例外自動重設、以及並發連點防重入。
2. **零副作用與格式相容隔離**：
   - `ReaderScreen` 延續 nullable 依賴注入模式；CBZ 格式明確顯示停用圖示（`onPressed: null`）；EPUB FAB 間距與定位計算精確（`top: 296`，56px 階梯式佈局）。
3. **清晰的平台與架構邊界**：
   - Foliate JS 與 Dart 端透過既有 `addJavaScriptHandler` 契約非同步解耦；音訊管線統一透過 `TtsAudioPlayer` 抽象介面包裝 `just_audio`，隔離平台依賴。

---

## 4. 複審結論（Conclusion & Next Steps）

本實作計畫架構完備、邏輯健全、測試覆蓋扎實，無任何阻塞性或重要缺陷，**正式核准通過**。

- [x] **實作計畫複審正式通過（Approved）**
- **下一步：** 請呼叫 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans` 開始執行 `plan-issue-2.md` 中 Task 1 至 Task 7 的具體實作。
