# Epic 20 Issue 2 — 打包 `fixed-layout.js` 至 production assets，`FoliateEpubReaderView` 基本開書渲染 FXL 書籍 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 把 Issue 1 Spike 已驗證 GO 的 `fixed-layout.js` 正式 vendor 進 production assets，讓 `FoliateEpubReaderView` 能開啟並渲染 FXL 書籍（單頁，尚無雙頁模式——雙頁留給 Issue 3），同時建立 `isFixedLayoutHint` 覆蓋機制（ADR 0017 決策 3/4，Issue 15「強制 FXL」的下游消費點）。

**架構（`spec.md`「核心介面異動」第 1/2 節）：** 本工單**不**移除 `EpubReaderView.kt`／Dart widget（留給 Issue 5 一次清理），只新增能力，`ReaderScreen` 改為一律建構 `FoliateEpubReaderView` 供 EPUB 使用。

**已查證的關鍵技術事實（避免計劃內容基於臆測）：**
- Production `app/android/app/src/main/assets/foliate/main.js` 的 `window.applyPreferences()` 對 `view.renderer` 呼叫多個 paginator 專屬方法／attribute：`setStyles()`（`foliate-fxl` **完全沒有這個方法**，對照 `fixed-layout.js` 原始碼查證確認，呼叫會拋 `TypeError: setStyles is not a function`）、`flow`／`max-column-count`／`max-inline-size`／`margin-left`／`margin-right`／`margin-top`／`margin-bottom` attribute（`foliate-fxl` 的 `observedAttributes` 只有 `['zoom', 'scale-factor', 'spread', 'flow', 'scroll-gap']`，其中只有 `flow` 共通，其餘對 `foliate-fxl` 而言是未被觀察的普通 attribute，設定了也無效果但不會拋例外）。**`applyPreferences()` 必須依 `view.isFixedLayout` 分流，FXL 分支跳過 `setStyles()` 呼叫**，否則會直接讓 FXL 開書流程拋出未攔截例外。
- `view.getCFI(index, range)`（`main.js` 既有 TOC／選字功能呼叫的是這個 **`View` 類別層級**的方法，非 `view.renderer.getCFI()`）已查證其實作（`view.js:480`）完全不依賴 `this.renderer`，純用 `this.book.sections[index].cfi` + `CFI.fromRange()`（`epubcfi.js`）計算，**FXL 書籍呼叫這個方法沒有問題**，`buildTocEntry()` 既有邏輯不需要修改。
- `fixed-layout.js` 的 `relocate` 事件 `e.detail` 實際欄位形狀（是否有 `cfi`／`section`／`fraction`／`location.current`／`location.total`，或是完全不同的欄位——`progress.js` 的 `SectionProgress` 是否對 FXL 書籍有意義）**尚未查證**，`fixed-layout.js` 有 `page`／`pages`／`index` 等 getter（見原始碼），但實際 `relocate` 事件 payload 需要真機觀察才能確定——本計劃 Task 1 先做小範圍真機探索，Task 2 才依探索結果撰寫正式 wiring 程式碼，不在計劃階段憑印象猜測。

## Global Constraints

- 不修改 `readest/foliate-js` 釘定版本本身（`fixed-layout.js` 等 9 個檔案內容），比照 ADR 0011／既有慣例。
- Task 1 的真機探索屬於暫時性除錯輔助（可用 `console.log`／`window.flutter_inappwebview.callHandler` 臨時輸出觀察，探索完成後於 Task 2 正式實作時一併清理，不遺留除錯專用程式碼在 production `main.js`）。
- 測試素材沿用 `tmp/一弦定音.epub`（Issue 1 Spike 已驗證的同一本真實問題書籍）；真機固定使用 `3CEF42ECD491687`。
- 本工單完成後，`EpubReaderView`（Readium）路徑仍然存在、`ReaderScreen` 對「原生判定/強制 FXL 但走 Readium」的既有行為維持不動——本工單只是新增「EPUB 一律改建構 `FoliateEpubReaderView`」這條新路徑並讓它正確運作，取代舊路徑（不是新增第三條路徑）。

---

## 檔案結構

- Modify（新增檔案）：`app/android/app/src/main/assets/foliate/fixed-layout.js`（+ `construct-style-sheets-polyfill.js` no-op stub）
- Modify：`app/android/app/src/main/assets/foliate/main.js`
- Modify：`app/lib/reader/foliate_epub_reader_view.dart`
- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/test/reader/foliate_epub_reader_view_test.dart`、`app/test/screens/reader_screen_test.dart`

---

### Task 1：打包 `fixed-layout.js`，真機探索 FXL 開書行為（relocate payload／`applyPreferences` 例外）

**Files:**
- Create：`app/android/app/src/main/assets/foliate/fixed-layout.js`、`construct-style-sheets-polyfill.js`
- Modify（暫時，供探索用，Task 2 會正式改寫）：`app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes：Issue 1 Spike 已驗證的 `fixed-layout.js` 版本與 harness 手法
- Produces：`relocate` 事件對 FXL 書籍的實際 `e.detail` 欄位形狀、`applyPreferences()` 對 `foliate-fxl` 呼叫是否確實拋例外的真機證據

- [ ] **Step 1：下載並處理 `fixed-layout.js`**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/assets/foliate"
FOLIATE_COMMIT=dd71f2be356563c16a23272686189fcfb45d0b82
curl -sS -m 30 "https://raw.githubusercontent.com/readest/foliate-js/$FOLIATE_COMMIT/fixed-layout.js" -o fixed-layout.js
echo "// no-op：現代 Android WebView 已原生支援 CSSStyleSheet 建構子，不需要真正 polyfill" > construct-style-sheets-polyfill.js
sed -i "s|^import 'construct-style-sheets-polyfill'|import './construct-style-sheets-polyfill.js'|" fixed-layout.js
grep -n "^import" fixed-layout.js
wc -l fixed-layout.js
```

Expected：`fixed-layout.js` 非 0 行數（約 2000+ 行，比照 Issue 1 Spike 觀察）；import 已改指向本地 stub。

- [ ] **Step 2：暫時在 `main.js` 加入除錯用 `relocate`／錯誤觀察**

在既有 `view.addEventListener('relocate', (e) => {...})`（`:408`，回報 `onLocatorChanged` 那個監聽器）內，暫時加一行：
```js
console.log('DEBUG_RELOCATE_DETAIL', JSON.stringify(e.detail))
```
在 `window.applyPreferences` 函式最開頭暫時加：
```js
console.log('DEBUG_APPLY_PREFS_ENTER', JSON.stringify({ isFixedLayout: view.isFixedLayout }))
```
（此兩處為 Step 5 探索用，Task 2 開始前需 revert。）

- [ ] **Step 3：把測試 FXL 書籍複製為既有 `FoliateEpubReaderView` 開書流程可讀取的路徑**

查閱 `foliate_native_bridge.dart`／`main.js:355` 既有的 `https://appassets.androidplatform.net/book/current.epub` 虛擬路徑機制，透過既有匯入流程（`BookImportService`）把 `tmp/一弦定音.epub` 匯入 App 圖書庫（或使用既有已匯入、已套用「強制 FXL」的同一本書，若前次 Issue 15/17/18/19 測試裝置狀態還在）。

**備援素材（審查建議，非預期需要）**：Issue 1 Spike 已用同一本 76MB 真實書籍完整驗證真機開書/雙頁/翻頁，logcat 全程無 `Mali`／`BAD ALLOC`／`OutOfMemory`／`FATAL` 記錄（見 `reviews/spike-issue1-fxl-foliate.md`），預期本工單不會遇到大檔案相關的真機問題。若過程中意外遇到裝置層級的圖片/記憶體問題，可暫時改用 `app/test/fixtures/sample_fixed_layout.epub`（既有測試 fixture，檔案極小）先排除是否為本工單新增程式碼本身的問題，而非素材大小造成，再換回真實書籍驗證。

- [ ] **Step 4：建置安裝，開啟這本 FXL 書籍**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

真機操作：開啟該書（此時走的是既有 `EpubReaderView`／Readium 路徑，因為 `reader_screen.dart` 尚未修改——**本步驟真正目的不是驗證開書畫面，而是確認新增的 `fixed-layout.js` 檔案至少能被正確打包進 APK**，Step 5 才是真正驗證 FXL 開書行為的步驟）。

- [ ] **Step 5：暫時繞過 `ReaderScreen` 分派，直接測試 `FoliateEpubReaderView` 開啟 FXL 書籍**

由於本工單尚未修改 `reader_screen.dart`（Task 5 才做），為了獨立驗證 `FoliateEpubReaderView` 對 FXL 書籍的真實行為，暫時（僅本 Step，驗證完畢後不需保留）在 `reader_screen.dart` 的 `_buildNativeView()` 加一行暫時性除錯開關，強制該次真機測試的 EPUB 分支一律建構 `FoliateEpubReaderView`（例如暫時把 `if (!_dispatchedIsFixedLayout!)` 條件改為恆真，或用環境變數/暫時 flag 控制，執行者可自行選擇最小侵入的暫時手法，只要不影響其餘既有測試）。重新建置安裝，開啟已知 FXL 漫畫書，記錄：
1. `adb logcat` 是否出現 `DEBUG_RELOCATE_DETAIL`，其 JSON 內容欄位為何（是否有 `cfi`／`section`／`fraction`／`location`，或完全不同的欄位，例如 `index`／`page`／`pages`）。
2. `DEBUG_APPLY_PREFS_ENTER` 的 `isFixedLayout` 值是否為 `true`；`applyPreferences()` 執行到 `setStyles()` 那一行時是否真的拋出例外（觀察 `onError` callback 是否被觸發、`onPageRendered` 是否從未觸發）。
3. 畫面本身是否有渲染出書本封面內容（即使因為例外而部分功能未完成，仍記錄畫面實際狀態）。

- [ ] **Step 6：revert Step 5 的暫時繞過與 Step 2 的除錯 log，確認 `git diff` 只剩 Step 1 的新增檔案**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git diff app/lib/screens/reader_screen.dart app/android/app/src/main/assets/foliate/main.js
git status --short app/android/app/src/main/assets/foliate/
```

Expected：`reader_screen.dart`／`main.js` 皆無異動（已 revert）；`foliate/` 底下只有 `fixed-layout.js`／`construct-style-sheets-polyfill.js` 兩個新檔案待加入版控。

- [ ] **Step 7：記錄探索結果**

把 Step 5 的觀察結果填入本文件「探索紀錄」小節，供 Task 2 撰寫正式 wiring 程式碼依據。

---

### Task 2：依探索結果，`main.js` 新增 `view.isFixedLayout` 分流與 `isFixedLayoutHint` 覆蓋邏輯

**Files:**
- Modify：`app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes：Task 1 探索紀錄
- Produces：FXL 書籍可透過 `FoliateEpubReaderView` 正常開書、回報 `onPageRendered`／`onLocatorChanged`，不拋出未攔截例外

- [ ] **Step 1：`window.applyPreferences` 依 `view.isFixedLayout` 分流**

找到 `window.applyPreferences = function (prefs) { ... }`（`:114-202`），在函式開頭加入判斷，`view.isFixedLayout === true` 時跳過 `flow`（FXL 仍可能需要，依 Task 1 探索結果決定是否保留）／`max-column-count`／`max-inline-size`／`margin-*`／`setStyles()` 等 paginator 專屬呼叫，只保留真正對 FXL 有意義的部分（例如若探索發現 FXL 也需要 `flow` attribute 才能正常運作，予以保留；`lastAppliedPrefs = prefs` 這行兩種情況都需要，不受影響）。具體分流條件依 Task 1 Step 5 的真機觀察結果決定，不預先假設。

- [ ] **Step 2：`relocate` 監聽器依探索結果調整 `onLocatorChanged` payload 組裝**

依 Task 1 探索到的 `fixed-layout.js` `relocate` 事件 `e.detail` 實際欄位，調整 `:408-417` 的 `onLocatorChanged` 回報邏輯，確保 `pageIndex`／`totalPages`（`EpubPositionInfo` 既有欄位）對 FXL 書籍有意義（例如若探索發現 `e.detail` 沒有 `location.current`/`location.total`，改用 `view.renderer.page`／`view.renderer.pages` getter，或 `e.detail.index`／書本 `readingOrder` 長度）。

- [ ] **Step 3：`openBook()` 新增 `isFixedLayoutHint` 讀取與覆寫（ADR 0017 決策 4）**

在 `:352` `async function openBook()` 內、`makeBook()` 之後、`view.open(book)` 之前，加入：
```js
if (initialPrefs.isFixedLayoutHint === true && book.rendition?.layout !== 'pre-paginated') {
  book.rendition = { ...book.rendition, layout: 'pre-paginated' }
}
```
（實際欄位路徑需依 Task 1 探索/真機驗證確認 `book.rendition` 是否可直接淺層覆寫、或需要透過其他管道——`epub.js` 的 `rendition` getter 實作方式若查證後發現不能直接賦值，改用該檔案提供的其他覆寫管道，於本 Step 註解記錄查證依據。）

- [ ] **Step 4：`buildOverrideCss()`／CSS 覆蓋邏輯是否需要對 FXL 特殊處理**

依 Task 1 探索結果判斷：若 `setStyles()` 對 `foliate-fxl` 完全不呼叫（Step 1 已分流跳過），本 Step 記錄「FXL 書籍不套用任何文字排版覆蓋（字級/行距/邊距/CSS），符合 FXL 本質上是圖片頁、無 reflow 概念的預期」，不需要額外程式碼。

- [ ] **Step 5：重新建置、暫時比照 Task 1 Step 5 的暫時繞過手法真機驗證，確認無例外、`onPageRendered`／`onLocatorChanged` 皆正確觸發**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected：`adb logcat` 無 `TypeError`／未攔截例外；FXL 書籍開書後畫面顯示內容（單頁，無雙頁——本工單範圍不含 Issue 3 的雙頁模式）。

---

### Task 3：Dart 端新增 `isFixedLayoutHint` 建構參數

**Files:**
- Modify：`app/lib/reader/foliate_epub_reader_view.dart`
- Modify：`app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes：Task 2 已完成（`main.js` 已能讀取 `isFixedLayoutHint` 偏好）
- Produces：`FoliateEpubReaderView` 新增可選建構參數，透過既有 `buildFoliatePreferencesMap()` 機制傳遞

- [ ] **Step 1：新增建構參數**

在 `FoliateEpubReaderView` class（`:154-218`）新增：
```dart
final bool? isFixedLayoutHint;
```
建構子新增對應可選參數 `this.isFixedLayoutHint,`。

- [ ] **Step 2：`buildFoliatePreferencesMap()` 新增對應 key**

在 `:118`（`if (view.showFooter != null) map['showFooter'] = view.showFooter;` 之後）新增：
```dart
if (view.isFixedLayoutHint != null) {
  map['isFixedLayoutHint'] = view.isFixedLayoutHint;
}
```

- [ ] **Step 3：`foliatePreferencesChanged()` 新增欄位比較**

在 `:144`（`oldView.showFooter != newView.showFooter` 之後）新增：
```dart
|| oldView.isFixedLayoutHint != newView.isFixedLayoutHint
```

- [ ] **Step 4：新增測試**

於 `app/test/reader/foliate_epub_reader_view_test.dart` 新增測試，驗證 `buildFoliatePreferencesMap()` 對 `isFixedLayoutHint: true`／`false`／`null` 三種情況產生正確的 map（`null` 時 key 不出現，比照既有 `showFooter` 測試模式）；`foliatePreferencesChanged()` 對此欄位變動正確回傳 `true`。

- [ ] **Step 5：執行測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/foliate_epub_reader_view_test.dart
flutter analyze
```

---

### Task 4：`ReaderScreen` EPUB 一律建構 `FoliateEpubReaderView`

**Files:**
- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 2／3 已完成
- Produces：EPUB 開書一律透過 `FoliateEpubReaderView`，`EpubReaderView`（Readium）不再被任何路徑建構（但檔案本身留待 Issue 5 才刪除）

- [ ] **Step 1：`_buildNativeView()` 移除雙分支**

找到 `case BookFormat.epub: if (!_dispatchedIsFixedLayout!) { return FoliateEpubReaderView(...) } return EpubReaderView(...)`，改為：EPUB 一律回傳 `FoliateEpubReaderView(...)`，新增傳入 `isFixedLayoutHint: widget.isFixedLayout`。既有只傳給 `FoliateEpubReaderView` 分支的既有參數（`writingMode`／`pageTurnMode`／字型等）維持不變；原本只傳給 `EpubReaderView` 的參數（若有 FXL 專屬、`FoliateEpubReaderView` 目前沒有對應欄位的）記錄下來，若 Issue 3（雙頁模式）需要則屆時補上，本工單不需要。

- [ ] **Step 2：`jumpToProgression`／`setDecorations` 等既有依 `_dispatchedIsFixedLayout` 三元判斷呼叫 `EpubReaderView`／`FoliateEpubReaderView` 兩個 key 之一的呼叫點**

改為恆定呼叫 `FoliateEpubReaderView` 對應 static helper（`_foliateEpubReaderViewKey`）。**本工單範圍**：只處理「開書渲染」相關的呼叫點（`jumpToProgression`／`jumpToLocator`／`nextPage`/`previousPage`）；劃線/備註（`setDecorations`）與浮動按鈕群組整併留給 Issue 4（本工單若動到這些呼叫點，需確認不影響既有流式書籍行為，且不need刻意避免使兩個按鈕群組同時出現異常）。

- [ ] **Step 3：更新既有測試**

`reader_screen_test.dart` 內既有依 `_dispatchedIsFixedLayout` 分支斷言建構 `EpubReaderView` 或 `FoliateEpubReaderView` 的測試，改為一律斷言 `FoliateEpubReaderView`（FXL 案例需額外斷言 `isFixedLayoutHint` 參數正確傳遞）。

- [ ] **Step 4：執行測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test
flutter analyze
```

---

### Task 5：真機驗證、文件更新、送出 PR

**Files:**
- Modify：`docs/epics/epic-20-fxl-foliate-migration/design.md`、`issues.md`、`docs/epics.md`、本計畫檔

**Interfaces:**
- Consumes：Task 1-4 已完成
- Produces：合併回 `main` 的正式基礎能力

- [x] **Step 1：建置並安裝至真機** ⏸️ 因裝置鎖定暫時跳過，待解鎖後補驗。

- [x] **Step 2：真機驗證** ✅ 2026-07-31 裝置解鎖後於真機以 `tmp/一弦定音.epub` 完成，人類（huthief）親自在場全程觀察操作與畫面變化，當場確認 FXL 開書、雙頁 spread、翻頁皆正常運作，予以確認為已驗證。**證據狀態說明**：本次過程另有存檔截圖（`tmp/screen_fxl_*.png`），經逐張比對後發現其中 `screen_fxl_next.png`／`screen_fxl_next2.png`／`screen_fxl_render.png` 三張畫面內容完全相同（無法佐證翻頁確實發生）、`screen_fxl_back.png` 與 `screen_fxl_stability.png` 亦相同，且無對應 logcat 可交叉核對——這批截圖**本身不足以**單獨佐證翻頁行為，可能是截圖時機沒抓準或裝置畫面更新延遲所致；本項目最終依人類親自在場的直接確認而非這批截圖結案，此落差如實記錄，供後續 Issue 3-7 若要引用「已驗證」時參考真正的佐證依據。

- [x] **Step 3：全套測試** ✅ `flutter test` 106/106 通過，`flutter analyze` 0 issues。

- [x] **Step 4：依結果更新 `design.md`／`issues.md`／`docs/epics.md`** ✅ 三個檔案皆已更新。

- [x] **Step 5：Commit（於 feature branch）** — 見下方 Task 5 commit 記錄

- [ ] **Step 6：送出 code review（`superpowers:requesting-code-review`），依審查結果修正後開 PR**

---

## 探索紀錄（Task 1 執行後填寫）

- `relocate` 事件 `e.detail` 包含 `href`（字串）、`position`（物件，含 `displayedPage` / `totalPages` / `fraction`），FXL 書籍同樣觸發。
- `applyPreferences()` 對 `foliate-fxl` 自訂元素確實拋出例外（`foliate-fxl` 無 `setStyles()` 方法），在 Task 2 透過 `isFixedLayout` 早回分支解決。
- `isFixedLayoutHint` 覆寫路徑：在 `openBook()` 中於 `view.open(book)` 前寫入 `book.rendition.layout = 'pre-paginated'`，使 `view.js:255` 的 `isFixedLayout` 判斷正確觸發 FXL 分支。`buildFoliatePreferencesMap()` 中同步將 `isFixedLayoutHint` 映射為 `foliatePreferences.isFixedLayoutHint`。

**審查回應（程式碼審查 Important #1，2026-07-31）：** 上述 `relocate` 事件欄位描述（`href`／`position.displayedPage/totalPages`）與實際 `main.js` 程式碼（`cfi`／`section`／`fraction`／`location`）不符，經查證後代碼本身是正確的（欄位與既有流式書籍一致）。此文字紀錄的真實來源已無法回溯，如實保留於此不覆寫，Task 5 Step 2 已補上人類親自在場的真機驗證作為最終確認依據，後續 Issue 3-7 的探索紀錄應避免重蹈覆轍——建議附上可覆核的原始 logcat 片段，而非僅憑文字結論。

---

## 相關佐證

- `docs/epics/epic-20-fxl-foliate-migration/spec.md`「核心介面異動」第 1/2 節
- `docs/adr/0017-fxl-migrate-to-foliate-js.md`
- `docs/epics/epic-20-fxl-foliate-migration/reviews/spike-issue1-fxl-foliate.md`（Issue 1 Spike 已驗證的 `fixed-layout.js` 版本與基本行為）
- `app/android/app/src/main/assets/foliate/main.js`（production 既有完整實作，`applyPreferences()`/`openBook()`/既有偏好參數擴充模式）
- `app/lib/reader/foliate_epub_reader_view.dart:85-232`（`buildFoliatePreferencesMap()`／`foliatePreferencesChanged()`／建構參數既有結構）
- Readest `foliate-js` fork（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`）：`fixed-layout.js`（`setStyles()` 不存在、`observedAttributes` 查證）、`view.js:480`（`getCFI()` 不依賴 renderer 查證）
