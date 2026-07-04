# 任務報告：Task 2: Shelf Page with Grid/List View & Search Functionality

## 實作細節與項目

本階段對 `prototype/index.html` 進行了全面的功能擴充，核心變更點如下：

1. **書架網格 (Grid) / 列表 (List) 視圖切換與持久化**：
   - 預設視圖透過 `localStorage.getItem('viewMode') || 'grid'` 初始化。
   - 新增視圖切換控制 UI（點擊「切換視圖」可在 Grid 與 List 間往復）。
   - 在 CSS 中整合優雅的 `.shelf-list` 佈局樣式，透過層級選擇器覆寫 `book-card` 的 Flex 排版，將原先縱向佈局橫向拉伸並顯示作者名稱與進度列。
   - 切換視圖狀態會自動透過 `localStorage.setItem('viewMode', AppState.viewMode)` 進行記憶持久化。

2. **書籍列表排序功能與持久化**：
   - 在書架上方配置了精美的 `<select>` 排序選擇器，支援「最後閱讀優先」、「最近新增優先」、「按作者排序」與「按書名排序」。
   - 為 `AppState.books` 中的每本書籍項目擴充 `lastReadTime` 與 `createTime` 屬性戳記。當使用者進入某本書籍閱讀時，系統將動態更新 `lastReadTime = Date.now()` 以便動態排序。
   - 排序變更後，會自動寫入 `localStorage.setItem('sortBy', mode)` 進行持久化。

3. **500ms Debounced 全文檢索與跳轉**：
   - 於書架頂部配置搜尋輸入框，輸入事件透過 `500ms` 的 `setTimeout` 實作防抖（Debounce）查詢，避免高頻渲染。
   - 搜尋邏輯（`searchBooks()`）完美區分「書名/作者匹配（`titleMatches`）」與「內容全文匹配（`contentMatches`）」。
   - 全文檢索的內容區塊中使用 `<mark>` 標籤將關鍵字進行醒目突顯（Highlight）。
   - 當使用者在搜尋結果中點擊任意內容匹配時，會記錄目標章節為 `AppState.selectedChapter`，並呼叫 `selectBookAndContent()` 跳轉至閱讀器頁面，使閱讀器得以動態載入並顯示被搜尋到的特定章節內容，實現精準定位。
   - **游標保護技術**：實作了 `activeElement` 焦點及游標位置（`selectionStart/End`）的記憶與重置，確保在 Vanilla JS 的 `innerHTML` 全頁重新渲染下，搜尋框依舊保持輸入焦點且游標不會跳躍跑焦，UX 體驗流暢。

4. **單元自我測試套件 (Self-Test Suite) 擴展**：
   - 保留原有的測試 1-3，新註冊了 3 個全面的測試項目：
     - **測試 4 (驗證全文檢索與分類匹配)**：驗證搜尋「黛玉」時，能夠分別回傳正確的書名匹配與全文內容匹配。
     - **測試 5 (驗證排序功能與持久化)**：驗證排序切換、localStorage 狀態持久化以及按書名升序字串排序的準確性。
     - **測試 6 (驗證視圖切換與持久化)**：驗證 Layout Toggle 及 localStorage 對檢視模式的持久化邏輯。

---

## 自我測試執行結果

- **測試 1：驗證切換路由狀態變更** - **PASS**
- **測試 2：驗證主題切換與 Class 變更** - **PASS**
- **測試 3：驗證音量鍵閱讀翻頁邏輯** - **PASS**
- **測試 4：驗證全文檢索與分類匹配** - **PASS**
- **測試 5：驗證排序功能與持久化** - **PASS**
- **測試 6：驗證視圖切換與持久化** - **PASS**

**自我測試套件彙整結果：6 PASS / 0 FAIL**

---

## Task 2 缺陷修復說明 (依據審查意見修復)

針對 Task 2 審查中發現的缺陷，已完成以下修復：

1. **刪除殘留的舊版 `selectBook` 函式**：安全地刪除了 `prototype/index.html` 後半段 (原 line 1610-1613 處) 殘留的舊版 `selectBook(id)` 定義，確保前半段 (line 1349) 的新版 `selectBook`（包含時間戳與章節重置邏輯）正常運作。
2. **實作搜尋輸入框的焦點與游標位置還原**：於 `renderApp()` 函式的最尾端加入焦點還原邏輯。透過先前記錄的 `isSearchFocused` 與 `selectionStart/End` 游標位置，在重新渲染後完美還原 `#search-input` 的焦點與游標位置，解決了全文檢索時輸入框失去焦點的問題。

---

## 提交資訊

- **Commit SHA**: `5c6a0fe3b59cc9f28e7b09143be668b663f87adc`
- **Commit 說明**: `fix(prototype): remove stale selectBook function and restore search input focus`
- **變更檔案**: [prototype/index.html](file:///U:/MyDeveloper/AI/elinkBook/prototype/index.html), [.superpowers/sdd/task-2-report.md](file:///U:/MyDeveloper/AI/elinkBook/.superpowers/sdd/task-2-report.md)
