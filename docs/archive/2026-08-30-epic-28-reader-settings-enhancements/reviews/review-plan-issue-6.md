# Epic 28 Issue 6 — 「選擇書籍」畫面優化 實作計畫審查報告

- **評估日期**：2026-08-15
- **審查對象**：[`docs/epics/epic-28-reader-settings-enhancements/plans/plan-issue-6.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-28-reader-settings-enhancements/plans/plan-issue-6.md)
- **審查專家**：系統架構師 & 測試工程審查專家
- **當前評估結論**：**準備好開始實作 (Ready to implement)**

---

## 1. 優點與亮點 (Strengths)

1. **務實的架構權衡與重構範圍收斂 (Architecture Decision)**：
   - 計畫深入評估了「抽離 `LibraryScreen._BookCover`」的利弊：
     - 若抽離共用，需改動龐大的 `library_screen.dart` 及其複雜的既有測試，大幅增加跨模組回歸風險。
     - 本畫面之書籍已由資料庫層 `LibraryRepository.listReflowableEpubBooks()` 嚴格過濾為流式 EPUB，不需要 `LibraryScreen._BookCover` 針對不同副檔名挑選圖示的完整邏輯，固定以 `Icons.menu_book` 佔位即可。
     - 在本檔案就地實作精簡版 `_BookCover` 與 `_BookGridItem`（約 40 行），以極小代價達成視覺統一且零跨模組副作用，決策非常明智。
2. **徹底消除單選誤觸風險，單選/多選機制高度統一 (Task 1)**：
   - 徹底移除過往單選模式下點擊 `ListTile` 即直接 `pop` 覆寫的誤觸隱患。
   - 單選模式採用清晰的 Radio 語意（點擊新項目清空先前選取），右上角「確定」按鈕在未選取時停用、選取後啟用；多選模式維持 Checkbox 語意。兩者共用同一套右上角半透明選取指示圖示（`check_circle`／`radio_button_unchecked`），互動模型一致且防呆。
3. **返回與取消之空值契約防禦完備 (Task 1)**：
   - 嚴格保障使用者未點擊「確定」、直接按返回鍵或系統手勢時一律回傳 `null`。
   - 測試案例精確覆蓋了「單選直接返回回傳 null」與「多選即使已有勾選、直接返回仍回傳 null」兩種邊界情境，確保呼叫端安全退出。
4. **搜尋狀態保持與軟體鍵盤適配設計周延 (Task 2)**：
   - 搜尋過濾為純記憶體比對書名與作者，不污染原始書籍清單與 `_selected` Set。
   - 特別編寫了「多選模式下，已選取項目被搜尋篩選隱藏後，清空搜尋詞時選取狀態仍保留」的高價值防禦測試。
   - `GridView` 外層使用 `Expanded` 包裹於 `Column` 內，結合 Flutter `Scaffold.resizeToAvoidBottomInset` 預設機制，軟體鍵盤彈出時自動伸縮高度，有效預防 `RenderFlex overflowed`。
5. **跨測試檔（`reader_screen_test.dart`）依賴排查精準 (Task 3)**：
   - 精確排查了 `reader_screen_test.dart` 中真正渲染本畫面的測試案例，鎖定單選複製測試需要補上「點擊確定按鈕」的步驟，確保全專案測試無縫通過。

---

## 2. 問題與疑慮 (Issues)

### Critical (必須修正)
*無。*

---

### Important (應該修正)
*無。*

---

### Minor (建議優化 / 注意事項)

#### 1. 搜尋輸入框一鍵清除（Clear Button）小建議
- **說明**：
  - 目前 `TextField` 提供了基本的搜尋輸入功能。若使用者輸入較長關鍵字後欲清空搜尋詞，需手動逐字刪除。
  - **建議**：實作時可在 `InputDecoration` 依 `_searchQuery.isNotEmpty` 條件加上 `suffixIcon: IconButton(icon: Icon(Icons.clear), onPressed: () => setState(() { _searchController.clear(); _searchQuery = ''; }))`，提升小螢幕或 E-Ink 設備上的操作流暢度（非阻塞，可作為實作時之細節優化）。

#### 2. 即時搜尋的大小寫轉換效能
- **說明**：
  - `_filteredBooks` 在每次 `build()` 時進行子字串包含比對。流式 EPUB 書庫在一般設備上通常為數十至數百本，記憶體篩選耗時小於 1ms，效能完全無虞。

---

## 3. 評估結論 (Assessment)

- **是否已準備好開始實作 (Ready to implement)？**：**準備好開始實作 (Ready to implement)**。
- **評估理由**：實作計畫切片簡潔有力（Task 1 格線與單選/多選統一 → Task 2 搜尋與鍵盤適配 → Task 3 跨檔案測試修正），架構決策務實安全，TDD 測試案例完整覆蓋 Radio 單選、Checkbox 複選、返回取消、搜尋狀態保留與鍵盤彈出適配，無任何阻擋實作之架構缺陷。
