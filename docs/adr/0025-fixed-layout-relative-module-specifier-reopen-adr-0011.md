# ADR 0025：`fixed-layout.js` 的 `construct-style-sheets-polyfill` import 改用相對路徑（重新開放 ADR 0011 取捨）

## 狀態

已採納

## 背景

`fixed-layout.js`（vendored，`readest/foliate-js`）第 1 行的上游原始碼是裸模組匯入（bare specifier）：`import 'construct-style-sheets-polyfill'`。本專案的 `index.html`（`app/android/app/src/main/assets/foliate/`）沒有宣告 import map，也沒有引入任何 Node.js/npm 打包工具鏈（ADR 0011／ADR 0013 皆明訂：vendored 檔案直接複製進版控、不經建置）。瀏覽器原生 ES Module（`InAppWebView` 執行環境）解析裸模組匯入時，需要 import map 或打包工具轉譯路徑才能 resolve，否則會直接拋出 `Failed to resolve module specifier` 例外，讓整個 `fixed-layout.js` 模組載入失敗（FXL／CBZ 書籍完全無法開啟）。

`epic-33-foliate-js-vendor-sync` Issue 1 程式碼審查（`reviews/review-code-issue-1.md` Important #1）發現：這個相對路徑改寫其實**早於本次同步就已存在**於釘定檔案中，但從未被任何 ADR 或設計文件正式記錄——`epic-32`／`epic-33` 的同步 SOP 都只知道要保留 ADR 0024 那兩段 patch，完全不知道 `fixed-layout.js` 第 1 行也需要手動修正，Issue 1 Task 1 整份覆蓋時因此意外把它蓋回上游的裸模組寫法，得靠審查／人工比對逐位元組 diff 才發現並修回（commit `08b3ccf8`）。

## 決策

- **正式重新開放 ADR 0011 的第二項例外**：`fixed-layout.js` 第 1 行的 `import 'construct-style-sheets-polyfill'` 手動改為 `import './construct-style-sheets-polyfill.js'`（相對路徑，指向同目錄下已釘定的 `construct-style-sheets-polyfill.js`）。除此之外，`fixed-layout.js` 其餘內容仍是上游逐位元組副本，不做其他修改。
- **未來每次「整份覆蓋同步」`fixed-layout.js` 時，須在下載完成後立即補上這一行修正**，比照 ADR 0024 兩段 patch 的處理方式，列為同步 SOP 的固定檢查項目，不能只知道要處理 ADR 0024。
- 不引入 import map 或打包工具鏈來解決根本問題——那會擴大整個 vendoring 邊界的複雜度，且目前只有這一處裸模組匯入受影響，改一行相對路徑成本最低。

## 後果

- `fixed-layout.js` 連同 `paginator.js`／`view.js`（ADR 0024）成為第三個「非逐位元組上游副本」的釘定檔案，同步 SOP／未來同步工單的「唯一例外」清單需要一併更新，涵蓋這一項。
- 若未來上游把這行改成別的寫法（例如改成別的套件名稱、或上游自己也改成相對路徑），下次同步時需要重新核對這個修正是否還適用，不能盲目套用同一行文字。
- 這個修正目前無法被本專案任何自動化測試層覆蓋（觸控 Harness 目前 4 個情境的 fixture 皆為 reflowable EPUB，不觸發 `fixed-layout.js` 的動態載入路徑），正確性仰賴真機開啟 FXL／CBZ 書籍驗證。

## 曾考慮的替代方案

- **新增 import map**：可以讓裸模組匯入正常運作，不需要每次同步手動修正，但會增加 `index.html` 的複雜度、且只為了這一個套件不成比例，予以排除。
- **引入打包工具鏈把 vendored 檔案重新打包**：徹底違反 ADR 0011／0013「vendored 檔案直接複製、不經建置」的核心原則，予以排除。
