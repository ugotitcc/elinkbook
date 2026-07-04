# Review 報告：Issue 3 實作審查（複審通過）

本報告針對 `worktree-epic-1-issue-3-content-uri-contract` 分支上，`EpubReaderView`/`PdfReaderView` content URI 契約擴充（ADR 0002）的實作進行複審與記錄。

- **專案名稱**：elinkBook
- **工作區路徑**：`docs/epics/epic-1-library/reviews/review-issue-3.md`
- **對應計畫**：[plan-issue-3.md](../plans/plan-issue-3.md)（含其審查回應紀錄）
- **審查 Git 範圍**：`3adbb68`（merge-base）到 `bfb3ebc`
- **提交序列**：
  - `773bff6` Extend EpubReaderView to accept content/file URI paths (ADR 0002)
  - `48f4a75` Extend PdfReaderView to accept content/file URI paths (ADR 0002)
  - `bfb3ebc` docs: note the contains("://") heuristic's edge-case limitation

---

## 複審結論

### 1. 優點 (Strengths)
- **清晰且具體的 Edge Case 限制註解 (Minor #2 修正)**：
  - 開發者在提交 `bfb3ebc` 中，已於 [EpubReaderView.kt](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt) 的 `resolveAbsoluteUrl` 與 [PdfReaderView.kt](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt) 的 `openParcelFileDescriptor` 中，精確地補充了關於 `contains("://")` 啟發式判斷的限制說明。註釋清楚指出若檔案系統路徑本身恰好含有該字串（例如 `/sdcard/downloads/http://book.epub`）會觸發誤判，並在 Android 環境的脈絡下評估此風險在正常使用情境下可忽略。這為未來維護者提供了極佳的上下文脈絡。
- **合理的防禦性程式設計保留 (Minor #1)**：
  - 開發者選擇保留 [PdfReaderView.kt](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt) 中的 `pfd == null` 檢查。這是一項合理的防禦性決策。雖然目前的 `openParcelFileDescriptor` 在找不到檔案時會直接拋出異常，但保留該 null 檢查有助於未來進行方法重構（例如調整為條件式回傳 null 而非丟出異常時），能在不影響執行效率的情況下提升代碼的穩健度 (Robustness)。
- **高度契合 ADR 與實作計劃的架構設計**：
  - 完美遵守了 ADR 0002 與實作計劃的約束。在 [EpubReaderView.kt](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt) 與 [PdfReaderView.kt](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt) 中各自獨立實作了 URI 解析與處理邏輯（`resolveAbsoluteUrl` 與 `openParcelFileDescriptor`），避免在平行工單之間引入不必要的程式碼依賴與實作順序耦合。
- **嚴謹的原生資源釋放與防禦性錯誤處理**：
  - [PdfReaderView.kt](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt) 的 `openBook` 實作中，使用 `finally` 區塊以逆序方式（`page` -> `renderer` -> `pfd`）釋放 Android 原生資源。這能徹底防止因 PDF 格式損毀、加密或 OOM 等例外狀況導致的 `ParcelFileDescriptor` 與 `PdfRenderer` 洩漏，設計非常具有防禦性。
- **測試設計精準且注重環境清理**：
  - 測試案例利用 `file://` 驗證原生端的 URI 分支邏輯，並針對不存在的 `content://` 驗證 `onError` 流程，兼顧了測試效率與邊界條件。
  - 每個新增的測試都透過 `addTearDown` 刪除在暫存目錄中產生的測試檔案（`sample_uri.epub` / `sample_uri.pdf`），避免了測試多次執行後模擬器暫存空間被無效佔用的問題。

### 2. 發現的問題 (Issues)

#### Critical (Must Fix)
- 無

#### Important (Should Fix)
- 無

#### Minor (Nice to Have)
- 無（先前指出的 Minor 項目均已完成合適的修改或給予合理的防禦性設計理由，無遺留問題）。

---

## 改進建議 (Recommendations)
1. **未來重構建議**：
   目前原生端將 `path.contains("://")` 做為判斷 URI 的依據。雖然在 Android 原生端為了平行開發且避免耦合，各自獨立實作了此邏輯，但如果在更廣泛的專案範圍中（例如 Issue 2 的 `BookMetadataChannel`）都使用了相同的字串比對，未來若要更改 URI 判斷規則，可以考慮在專案架構穩定後，將此比對邏輯在 Native 端的公用 Utils 中進行適度收攏。

---

## 最終評估 (Assessment)

**Ready to merge: Yes**

**評估說明**：
本次複審確認開發者已妥善處理前次 Review 的所有 Minor 反饋，By Design 的限制已獲得清晰且完整的註解標記，防禦性 null 檢查之保留亦十分合理。實作完全符合實作計劃，程式碼品質極佳，建議直接合併。
