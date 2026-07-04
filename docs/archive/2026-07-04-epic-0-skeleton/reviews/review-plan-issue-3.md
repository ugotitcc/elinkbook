# 文件審查報告：plan-issue-3.md (Issue 3 實作計劃) - 複審通過

本報告為針對 `plan-issue-3.md` 計劃文件的複審記錄。使用者已依據前次審查意見完成修正。

- **審查對象**：[plan-issue-3.md](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-0-skeleton/plans/plan-issue-3.md)
- **報告路徑**：`docs/epics/epic-0-skeleton/reviews/review-plan-issue-3.md`
- **複審狀態**：複審通過，計劃文件更新完備，無殘留問題。

---

## 複審意見回覆紀錄與變更核對

### 1. 原生資源釋放與 Exception 捕獲缺口 (Kotlin 端)
- **審查建議**：原有設計在發生 Exception 時無法確保關閉 `page`/`renderer`/`pfd` 造成資源洩漏；另外，`catch (e: Exception)` 無法捕獲 `OutOfMemoryError` 導致 App 崩潰。
- **核對結果**：**已修正 (優化實作)**。
  - 計劃中已改用 `finally` 區塊，依序對 `page`、`renderer`、`pfd` 呼叫 `close()` 確保資源釋放。
  - 分開捕獲 `OutOfMemoryError` 與 `Exception`。
  - **設計決策調整**：使用者未採用審查報告中建議的直接 `catch (t: Throwable)`，而是選擇分開明確捕獲 `OutOfMemoryError` 與 `Exception`。其理由非常成立——如果捕獲了所有的 `Throwable`，會導致例如 `AssertionError`、`LinkageError` 等屬於系統或程式本身極其嚴重的問題也被靜默吞噬。分開捕獲能精準解決 OOM 點陣圖解碼風險，同時維持了對其他重大 Error 的正確崩潰與回報機制。這是一個深思熟慮且正確的調整。
  - **YAGNI 理由成立**：另外，對於審查意見中建議新增的 `renderer.pageCount == 0` 檢查，使用者決定不採用。因為當 `pageCount` 為 0 時，呼叫 `openPage(0)` 本身就會拋出合理的例外並被既有 `catch` 捕獲回報 `onError`，不需特地擴充規格之外的防禦，符合 YAGNI 原則。

### 2. Integration Test 的非同步等待機制 (Dart 端)
- **審查建議**：誤用 `pumpAndSettle(const Duration(seconds: 3))` 的 `duration` 參數，每次重繪會強制停頓 3 秒，嚴重拖慢測試。建議改用 `Completer` 等待 callback。
- **核對結果**：**已修正**。
  - 計劃中 `pdf_reader_view_test.dart` 的測試已改用 `Completer` 機制，在 `onPageRendered`/`onError` 觸發時 complete，並設定 `completer.future.timeout(const Duration(seconds: 5))`。
  - `pumpAndSettle()` 移除了不正確的參數，保留合理的預設值。
  - 修正符合預期。

### 3. AndroidView 本地檔案描述符設計
- **審查建議**：原計劃中使用 `_stageAssetAsFile` 將 assets 複製到真實檔案系統暫存目錄，以提供 `PdfRenderer` 可尋址的檔案路徑。審查確認該設計正確。
- **核對結果**：確認該優良設計已保留。

---

## 最終評估 (Assessment)

**Ready to implement: Yes**

**評估說明**：
計劃文件已針對前次審查意見做出了非常高水準的修訂。除了修正 `pumpAndSettle` 參數問題外，在 Kotlin 端的錯誤捕獲與資源釋放設計上，採取了更為嚴謹的「分開捕獲 OOM 與 Exception」策略，避免了寬泛捕獲 `Throwable` 所帶來的副作用，展現了極佳的技術考量。本計劃內容已完全完備，隨時可以安全交付實作。
