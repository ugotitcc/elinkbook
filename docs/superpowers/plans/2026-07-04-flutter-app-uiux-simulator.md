# 全能電子書閱讀器 Flutter APP 互動 UIUX 模擬器實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用單一 HTML/CSS/JS 檔案在專案根目錄的 `prototype/index.html` 建立一個高度互動、視覺精美的 Flutter APP UIUX 模擬器，展示直排繁體中文排版、3x3 鏡像點擊熱區、365天活躍度貢獻圖與同步衝突解決等 PRD 核心亮點。

**Architecture:** 整個模擬器採單頁應用 (SPA) 架構。左側為 CSS 繪製的手機裝置外框 (Device Frame)，內嵌 APP 狀態渲染器；右側為控制台 (Control Panel) 用以模擬外部事件。APP 內部設有「自我測試套件 (Self-Test Suite)」，可用於驗證所有互動邏輯是否正常運作。

**Tech Stack:** Native HTML5, Vanilla CSS3 (CSS Variables, Grid, Flexbox), Native JavaScript (ES6+), Google Fonts (Inter, Outfit).

## Global Constraints

- 所有的使用者介面文字與說明必須一律使用「正體中文 (zh-TW)」。
- CSS 變數必須統一定義在 `:root` 中，以方便一鍵切換 Sepia、Dark、Light 與 E-Ink 四大主題。
- 書籍封面網格必須在書架模式下精準呈現每列 6 本封面之排版。
- 專案程式碼與自我測試必須保存在 `prototype/index.html` 中，實現雙擊即可運作之獨立性。

---

### Task 1: 專案初始化、裝置外框與底層頁面路由器 (Scaffolding & Router)

**Files:**
- Create: `prototype/index.html`

**Interfaces:**
- Consumes: None
- Produces:
  - `AppState` (全域狀態物件，管理當前頁面與主題)
  - `switchPage(pageName)` (切換 APP 當前畫面)
  - `runTest(testName, testFn)` (測試核心註冊器)

- [ ] **Step 1: 撰寫初始 HTML 骨架與自我測試核心**
  在 `prototype/index.html` 中定義基礎的 DOM 結構、CSS 變數、手機外殼（含側邊音量鍵），並在 JS 中實作 `runTest` 測試架構：
  ```html
  <!DOCTYPE html>
  <html lang="zh-TW">
  <head>
    <meta charset="UTF-8">
    <title>elinkBook Flutter APP UIUX 模擬器</title>
    <style>
      :root {
        --phone-width: 390px;
        --phone-height: 844px;
        --bg-color: #F8F9FA;
        --text-color: #1A1A1A;
        --primary-color: #6200EE;
      }
      body { display: flex; font-family: 'Outfit', 'Inter', sans-serif; background: #121214; color: #fff; margin: 0; padding: 20px; justify-content: center; }
      .device-container { position: relative; width: var(--phone-width); height: var(--phone-height); border: 12px solid #333; border-radius: 40px; overflow: hidden; background: var(--bg-color); color: var(--text-color); box-shadow: 0 20px 40px rgba(0,0,0,0.5); }
      .volume-btn { position: absolute; left: -16px; width: 6px; height: 50px; background: #555; border-radius: 3px; cursor: pointer; }
      .volume-up { top: 120px; }
      .volume-down { top: 180px; }
      .app-content { height: calc(100% - 100px); overflow-y: auto; padding: 15px; }
      .bottom-nav { height: 60px; display: flex; border-top: 1px solid #ddd; background: rgba(255,255,255,0.9); position: absolute; bottom: 0; width: 100%; }
      .nav-item { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; font-size: 12px; cursor: pointer; }
      .control-panel { margin-left: 40px; width: 400px; background: #222; border-radius: 12px; padding: 20px; }
      .test-suite { border-top: 1px solid #44px; margin-top: 20px; padding-top: 10px; }
      .test-item { display: flex; justify-content: space-between; padding: 5px 0; border-bottom: 1px dashed #333; font-size: 13px; }
      .test-pass { color: #4CAF50; }
      .test-fail { color: #F44336; }
    </style>
  </head>
  <body>
    <div class="volume-btn volume-up" onclick="triggerVolumeKey('up')"></div>
    <div class="volume-btn volume-down" onclick="triggerVolumeKey('down')"></div>
    <div class="device-container">
      <div id="status-bar" style="height:40px; background:#e0e0e0; display:flex; justify-content:space-between; align-items:center; padding:0 20px; font-size:12px;">
        <span id="status-time">08:26</span>
        <span>📶 🔋 98%</span>
      </div>
      <div id="app" class="app-content"></div>
      <div class="bottom-nav">
        <div class="nav-item" onclick="switchPage('shelf')">📚<span>書架</span></div>
        <div class="nav-item" onclick="switchPage('reader')">📖<span>閱讀器</span></div>
        <div class="nav-item" onclick="switchPage('stats')">📊<span>統計</span></div>
      </div>
    </div>
    <div class="control-panel">
      <h2>控制台面板</h2>
      <button onclick="runAllTests()">運行自我測試</button>
      <div class="test-suite" id="test-results"></div>
    </div>
    <script>
      const AppState = {
        currentPage: 'shelf',
        theme: 'light',
        books: [
          { id: '1', title: '紅樓夢 (直排範本)', author: '曹雪芹', progress: 45, format: 'EPUB' },
          { id: '2', title: '三國演義', author: '羅貫中', progress: 12, format: 'TXT' }
        ]
      };
      
      const tests = [];
      function runTest(name, fn) {
        tests.push({ name, fn });
      }
      
      function switchPage(page) {
        AppState.currentPage = page;
        renderApp();
      }
      
      function renderApp() {
        const appDiv = document.getElementById('app');
        if (AppState.currentPage === 'shelf') {
          appDiv.innerHTML = `<h3>我的書架</h3><div id='shelf-content'></div>`;
        } else if (AppState.currentPage === 'reader') {
          appDiv.innerHTML = `<h3>閱讀器核心</h3>`;
        } else if (AppState.currentPage === 'stats') {
          appDiv.innerHTML = `<h3>閱讀統計</h3>`;
        }
      }
      
      function triggerVolumeKey(direction) {
        console.log('Volume Key:', direction);
      }
      
      function runAllTests() {
        const resultsDiv = document.getElementById('test-results');
        resultsDiv.innerHTML = '';
        tests.forEach(t => {
          try {
            t.fn();
            resultsDiv.innerHTML += `<div class="test-item"><span>${t.name}</span><span class="test-pass">PASS</span></div>`;
          } catch (e) {
            resultsDiv.innerHTML += `<div class="test-item"><span>${t.name}</span><span class="test-fail">FAIL: ${e.message}</span></div>`;
          }
        });
      }
      
      // 註冊第一個測試：路由切換驗證
      runTest('驗證切換路由狀態變更', () => {
        switchPage('stats');
        if (AppState.currentPage !== 'stats') throw new Error('路由未能成功切換至 stats');
        switchPage('shelf');
      });
      
      renderApp();
    </script>
  </body>
  </html>
  ```

- [ ] **Step 2: 載入原型網頁，手動測試驗證基本切換**
  開啟瀏覽器載入 `prototype/index.html`，點選底部「統計」與「書架」，並點擊「運行自我測試」，預期能看到 `驗證切換路由狀態變更 PASS`。

- [ ] **Step 3: 提交變更**
  ```bash
  git add prototype/index.html
  git commit -m "feat: init prototype structure and page router with self-test suite"
  ```

---

### Task 2: 書架頁面（每列 6 本書籍封面）與全文檢索 (Shelf & Fulltext Search)

**Files:**
- Modify: `prototype/index.html`

**Interfaces:**
- Consumes: Task 1 (AppState)
- Produces:
  - `renderShelf()` (渲染書架網格與列表視圖)
  - `searchBooks(query)` (搜尋核心，區分書名/內容)

- [ ] **Step 1: 實作書籍搜尋與封面顯示**
  修改 JS 部分以支援書架的「網格/列表」切換、每列顯示 6 本封面的 Grid CSS，以及 500ms debounce 搜尋：
  ```javascript
  // 在 AppState 中加入檢視模式與搜尋參數
  AppState.viewMode = localStorage.getItem('viewMode') || 'grid';
  AppState.searchQuery = '';
  
  // 書籍全文模擬資料庫
  const BookDatabase = {
    '1': [
      { chapter: '第一回', content: '黛玉進賈府，見過外祖母。林黛玉自幼喪母，極受憐愛。' },
      { chapter: '第二回', content: '賈寶玉銜玉而生，性情頑劣。花謝花飛花滿天，紅消香斷有誰憐？' }
    ],
    '2': [
      { chapter: '第一回', content: '宴桃園豪傑三結義，斬黃巾英雄首立功。話說天下大勢，分久必合，合久必分。' }
    ]
  };

  function toggleViewMode() {
    AppState.viewMode = AppState.viewMode === 'grid' ? 'list' : 'grid';
    localStorage.setItem('viewMode', AppState.viewMode);
    renderApp();
  }

  function searchBooks(query) {
    AppState.searchQuery = query;
    if (!query) return { titleMatches: [], contentMatches: [] };
    
    const titleMatches = AppState.books.filter(b => b.title.includes(query) || b.author.includes(query));
    const contentMatches = [];
    
    Object.keys(BookDatabase).forEach(bookId => {
      const book = AppState.books.find(b => b.id === bookId);
      BookDatabase[bookId].forEach(section => {
        if (section.content.includes(query)) {
          contentMatches.push({
            bookId,
            bookTitle: book.title,
            chapter: section.chapter,
            snippet: section.content.replace(query, `<mark>${query}</mark>`)
          });
        }
      });
    });
    
    return { titleMatches, contentMatches };
  }
  ```
  並修改 HTML CSS：
  ```css
  .shelf-grid { display: grid; grid-template-columns: repeat(6, 1fr); gap: 5px; padding: 10px 0; }
  .book-cover { width: 100%; aspect-ratio: 2/3; background: linear-gradient(135deg, #6200ee, #03dac6); color: white; border-radius: 4px; display: flex; align-items: center; justify-content: center; font-size: 8px; font-weight: bold; text-align: center; box-shadow: 0 4px 6px rgba(0,0,0,0.1); position: relative; }
  .book-progress { position: absolute; bottom: 2px; right: 2px; background: rgba(0,0,0,0.6); color: white; font-size: 6px; padding: 1px 3px; border-radius: 3px; }
  .shelf-list { display: flex; flex-direction: column; gap: 10px; }
  .list-item { display: flex; align-items: center; gap: 10px; border-bottom: 1px solid #eee; padding-bottom: 10px; }
  .list-item .book-cover { width: 40px; }
  ```

- [ ] **Step 2: 撰寫搜尋單元自我測試**
  註冊測試，確認搜尋「黛玉」時，能夠分別回傳正確的書名匹配與全文內容匹配：
  ```javascript
  runTest('驗證全文檢索與分類匹配', () => {
    const results = searchBooks('黛玉');
    if (results.contentMatches.length === 0) throw new Error('未能搜尋到內文中的黛玉');
    if (results.contentMatches[0].bookId !== '1') throw new Error('搜尋匹配書籍ID不正確');
  });
  ```

- [ ] **Step 3: 執行測試並驗證**
  在瀏覽器控制台手動修改 AppState.searchQuery，點選自我測試，確認 `驗證全文檢索與分類匹配` 顯示 PASS。

- [ ] **Step 4: 提交變更**
  ```bash
  git add prototype/index.html
  git commit -m "feat: add book shelf view modes and debounced search with keyword highlights"
  ```

---

### Task 3: 閱讀器直橫排排版與邊距微調面板 (Vertical Writing & Page Styles)

**Files:**
- Modify: `prototype/index.html`

**Interfaces:**
- Consumes: Task 2
- Produces:
  - `AppState.layout` (版面參數，包含行距、段落間距、邊距)
  - `toggleWritingMode()` (直橫排排版切換)
  - `changeLayoutParam(param, delta)` (調整版面參數)

- [ ] **Step 1: 實作直排排版、避頭尾與參數微調**
  在 CSS 中加入直排排版類別 `.writing-vertical`：
  ```css
  .writing-vertical {
    writing-mode: vertical-rl;
    text-orientation: mixed;
    line-break: strict;
    word-break: keep-all;
    height: 480px;
    column-fill: auto;
  }
  .writing-vertical img, .writing-vertical h3 {
    break-inside: avoid;
  }
  /* 標點符號置中微調 */
  .writing-vertical p {
    text-align: justify;
  }
  ```
  在控制面板中加入 +/- 按鈕及滑桿：
  ```javascript
  AppState.layout = {
    fontSize: 16,
    lineHeight: 1.5,
    paraSpacing: 10,
    marginRight: 15,
    marginLeft: 15,
    marginTop: 15,
    marginBottom: 15
  };
  
  function changeLayoutParam(param, delta) {
    const val = AppState.layout[param] + delta;
    if (param === 'fontSize' && (val < 12 || val > 40)) return;
    if (param.startsWith('margin') && (val < 0 || val > 50)) return;
    AppState.layout[param] = val;
    renderApp();
  }
  ```

- [ ] **Step 2: 註冊排版極限參數自我測試**
  驗證當字體大小微調小於 12px 時，是否會自動被截斷限制，以保證排版不崩潰：
  ```javascript
  runTest('驗證字體大小微調限制範圍', () => {
    AppState.layout.fontSize = 13;
    changeLayoutParam('fontSize', -5); // 應該停在 12px
    if (AppState.layout.fontSize !== 12) throw new Error('字體大小未能限制於最小值 12px');
  });
  ```

- [ ] **Step 3: 驗證測試 PASS**
  載入瀏覽器點擊運行測試，預期獲得 PASS。

- [ ] **Step 4: 提交變更**
  ```bash
  git add prototype/index.html
  git commit -m "feat: implement vertical writing mode and layout customizer with min/max bounds"
  ```

---

### Task 4: 3x3 點擊導航九宮格與直排 RTL 左右鏡像 (Navigation Zones)

**Files:**
- Modify: `prototype/index.html`

**Interfaces:**
- Consumes: Task 3
- Produces:
  - `AppState.writingMode` ('horizontal' | 'vertical')
  - `handleZoneClick(zoneIndex)` (處理 3x3 區域點擊動作)

- [ ] **Step 1: 實作 3x3 熱區覆蓋與鏡像邏輯**
  在閱讀介面覆蓋一層透明的 grid 熱區，定義 0-8 代表九宮格位置：
  ```html
  <!-- 3x3 點擊導航熱區 -->
  <div class="nav-zones-grid">
    <div onclick="handleZoneClick(0)"></div>
    <div onclick="handleZoneClick(1)"></div>
    <div onclick="handleZoneClick(2)"></div>
    <div onclick="handleZoneClick(3)"></div>
    <div onclick="handleZoneClick(4)"></div>
    <div onclick="handleZoneClick(5)"></div>
    <div onclick="handleZoneClick(6)"></div>
    <div onclick="handleZoneClick(7)"></div>
    <div onclick="handleZoneClick(8)"></div>
  </div>
  ```
  ```css
  .nav-zones-grid {
    position: absolute; top: 40px; left: 0; width: 100%; height: calc(100% - 100px);
    display: grid; grid-template-columns: repeat(3, 1fr); grid-template-rows: repeat(3, 1fr);
    z-index: 10; pointer-events: auto;
  }
  .nav-zones-grid div { border: 1px dashed rgba(0,0,0,0.03); cursor: pointer; }
  ```
  ```javascript
  AppState.writingMode = 'horizontal'; // 'horizontal' | 'vertical'
  AppState.currentPageNumber = 1;
  
  function handleZoneClick(index) {
    // 4 為中央格，永遠是觸發選單
    if (index === 4) {
      toggleReaderMenu();
      return;
    }
    
    // 判斷是否為左半部 (0, 3, 6) 或 右半部 (2, 5, 8)
    const isLeft = [0, 3, 6].includes(index);
    const isRight = [2, 5, 8].includes(index);
    
    if (AppState.writingMode === 'horizontal') {
      if (isLeft) prevPage();
      if (isRight) nextPage();
    } else {
      // 直排 (Vertical RTL) 右開書：左滑為下一頁，右滑為上一頁 (左右鏡像)
      if (isLeft) nextPage();
      if (isRight) prevPage();
    }
  }
  
  function nextPage() { AppState.currentPageNumber++; renderApp(); }
  function prevPage() { AppState.currentPageNumber = Math.max(1, AppState.currentPageNumber - 1); renderApp(); }
  ```

- [ ] **Step 2: 註冊熱區鏡像翻轉測試**
  寫入測試以模擬在直排和橫排模式下點擊同一個區域（例如左邊格 3），驗證換頁方向：
  ```javascript
  runTest('驗證九宮格點擊於直橫排下的翻頁鏡像映射', () => {
    AppState.currentPageNumber = 10;
    AppState.writingMode = 'horizontal';
    handleZoneClick(3); // 橫排點左邊：上一頁
    if (AppState.currentPageNumber !== 9) throw new Error('橫排點擊左邊未觸發上一頁');
    
    AppState.writingMode = 'vertical';
    handleZoneClick(3); // 直排點左邊：下一頁 (鏡像)
    if (AppState.currentPageNumber !== 10) throw new Error('直排點擊左邊未觸發下一頁');
  });
  ```

- [ ] **Step 3: 執行測試**
  點擊運行測試，驗證九宮格點擊鏡像邏輯正常。

- [ ] **Step 4: 提交變更**
  ```bash
  git add prototype/index.html
  git commit -m "feat: add 3x3 navigation hotspot zones with RTL mirroring"
  ```

---

### Task 5: 劃線、備註管理與 Markdown 導出 (Annotations & Markdown Export)

**Files:**
- Modify: `prototype/index.html`

**Interfaces:**
- Consumes: Task 3
- Produces:
  - `addAnnotation(text, type, color, comment)` (新增劃線或備註)
  - `deleteAnnotation(id)` (刪除指定劃線/備註)
  - `exportMarkdown()` (導出 Markdown 檔案)

- [ ] **Step 1: 實作選取文字選單與 Markdown 格式化**
  在 APP 內文段落上監聽選取事件：
  ```javascript
  AppState.annotations = [];
  
  function addAnnotation(text, type, color, comment = '') {
    const id = Date.now().toString();
    AppState.annotations.push({ id, text, type, color, comment });
    renderApp();
    return id;
  }
  
  function deleteAnnotation(id) {
    AppState.annotations = AppState.annotations.filter(a => a.id !== id);
    renderApp();
  }
  
  function exportMarkdown() {
    let md = `# 閱讀筆記：《紅樓夢》\n\n`;
    md += `## 劃線與個人備註\n\n`;
    AppState.annotations.forEach(a => {
      md += `*   > ${a.text}\n`;
      if (a.comment) md += `    *   *個人備註*：${a.comment}\n`;
    });
    return md;
  }
  ```

- [ ] **Step 2: 註冊劃線備註 CRUD 自我測試**
  模擬使用者劃線與備註，驗證其是否被正確新增，並檢查 Markdown 格式匯出內容：
  ```javascript
  runTest('驗證劃線與個人備註的新增與導出功能', () => {
    AppState.annotations = [];
    const id = addAnnotation('花謝花飛花滿天', 'highlight', 'pink', '黛玉名句');
    if (AppState.annotations.length !== 1) throw new Error('新增註記失敗');
    
    const md = exportMarkdown();
    if (!md.includes('花謝花飛花滿天') || !md.includes('黛玉名句')) {
      throw new Error('Markdown 導出格式不符合規格');
    }
    
    deleteAnnotation(id);
    if (AppState.annotations.length !== 0) throw new Error('刪除註記失敗');
  });
  ```

- [ ] **Step 3: 執行測試**
  開啟網頁點選運行測試，預期獲得 PASS。

- [ ] **Step 4: 提交變更**
  ```bash
  git add prototype/index.html
  git commit -m "feat: implement highlights, note dialogs, list management, and markdown export"
  ```

---

### Task 6: 365天閱讀活躍度熱點圖與閒置計時器 (Heatmap & Activity Timer)

**Files:**
- Modify: `prototype/index.html`

**Interfaces:**
- Consumes: Task 1
- Produces:
  - `renderHeatmap()` (繪製 365 天網格)
  - `startReadingTimer()` (開啟智慧計時器)
  - `stopReadingTimer()` (暫停計時器)

- [ ] **Step 1: 實作活躍度網格與智慧計時**
  在統計頁面實作 GitHub 貢獻圖風格的 SVG/CSS Grid 網格，並在閱讀器中監聽翻頁/滾動事件：
  ```javascript
  AppState.stats = {
    heatmapData: {}, // 'YYYY-MM-DD': minutes
    lastActivity: Date.now()
  };
  
  function triggerActivity() {
    AppState.stats.lastActivity = Date.now();
    if (!AppState.readingTimerActive) {
      AppState.readingTimerActive = true;
      console.log('偵測到活動，重啟計時器');
    }
  }
  
  function checkIdleState() {
    // 若超過 10 秒沒有互動，自動暫停計時器
    if (Date.now() - AppState.stats.lastActivity > 10000) {
      AppState.readingTimerActive = false;
      console.log('閒置超時，暫停閱讀計時');
    }
  }
  setInterval(checkIdleState, 2000);
  ```

- [ ] **Step 2: 註冊閒置超時計時器測試**
  ```javascript
  runTest('驗證超過10秒無活動自動判定為閒置', () => {
    AppState.stats.lastActivity = Date.now() - 12000; // 模擬 12 秒前是最後一次活動
    checkIdleState();
    if (AppState.readingTimerActive === true) {
      throw new Error('閒置計時器未能正常暫停');
    }
  });
  ```

- [ ] **Step 3: 執行測試並驗證**
  執行自我測試，預期 PASS。

- [ ] **Step 4: 提交變更**
  ```bash
  git add prototype/index.html
  git commit -m "feat: implement 365-day contribution heatmap and activity-based idle timer"
  ```

---

### Task 7: 雲端進度同步與進度衝突對話框 (Cloud Sync & Sync Conflict Dialog)

**Files:**
- Modify: `prototype/index.html`

**Interfaces:**
- Consumes: Task 1, 3
- Produces:
  - `triggerSyncConflict()` (在控制面板中手動製造同步衝突)
  - `checkSyncProgress()` (檢查並彈窗提示衝突)

- [ ] **Step 1: 實作同步衝突邏輯與 Flutter 對話框**
  ```javascript
  AppState.localProgress = 30; // 本地進度 %
  AppState.cloudProgress = 30; // 模擬雲端進度 %
  AppState.showConflictDialog = false;

  function triggerSyncConflict() {
    // 模擬別的裝置把進度讀到 85% 寫入雲端
    AppState.cloudProgress = 85;
    alert('已成功模擬雲端進度被推至 85% (本地為 30%)，請在 APP 書架點選書籍進入閱讀器以觸發衝突對話框。');
  }

  function enterBook() {
    if (AppState.cloudProgress !== AppState.localProgress) {
      AppState.showConflictDialog = true;
      renderApp();
    } else {
      switchPage('reader');
    }
  }
  
  function resolveConflict(useCloud) {
    if (useCloud) {
      AppState.localProgress = AppState.cloudProgress;
    } else {
      AppState.cloudProgress = AppState.localProgress;
    }
    AppState.showConflictDialog = false;
    switchPage('reader');
  }
  ```
  在 HTML 中繪製 Flutter Material 3 風格的 Dialog 覆蓋層。

- [ ] **Step 2: 註冊衝突對話框彈窗自我測試**
  驗證當進度不一致時，點擊進入書籍是否會彈出對話框：
  ```javascript
  runTest('驗證雲端與本地進度不一致時正確彈窗詢問', () => {
    AppState.localProgress = 30;
    AppState.cloudProgress = 85;
    AppState.showConflictDialog = false;
    enterBook();
    if (!AppState.showConflictDialog) {
      throw new Error('未能在進度衝突時彈出詢問對話框');
    }
    resolveConflict(false); // 點選保留本地
    if (AppState.showConflictDialog) {
      throw new Error('關閉對話框失敗');
    }
  });
  ```

- [ ] **Step 3: 執行測試**
  點選運行測試，預期獲得 PASS。

- [ ] **Step 4: 提交變更**
  ```bash
  git add prototype/index.html
  git commit -m "feat: implement cloud sync mock and progress conflict resolution dialog"
  ```
