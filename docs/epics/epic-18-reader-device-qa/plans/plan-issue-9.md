# Issue 9：裝置旋轉/視窗尺寸變化時重新呼叫 `applyPreferences()` 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 讓「雙欄」欄數模式的 `max-inline-size` 動態閾值，在裝置旋轉/視窗尺寸變化後自動重新計算，而不是停留在 `applyPreferences()` 呼叫當下的一次性快照。

**架構：** 在 `main.js` 新增一個模組級變數 `lastAppliedPrefs`，於每次 `window.applyPreferences(prefs)` 執行時同步更新為最新值；另外對 `view.renderer`（`readest/foliate-js` 的 `foliate-paginator` 自訂元素）掛上**本專案自建**的 `ResizeObserver`（與 `paginator.js:1163` 既有內部 observer 是兩個互不干擾的獨立實例，不修改 vendored `paginator.js`，比照 ADR 0011），resize 時 debounce 後呼叫 `window.applyPreferences(lastAppliedPrefs)`，讓整組偏好（含「雙欄」的 `targetSize` 計算）依當下真實尺寸重新套用一次。

**Tech Stack：** 純 Vanilla JS（ES module），無框架、無建置流程，`file://`/`WebViewAssetLoader` 虛擬 origin 下直接被 `<script type="module" src="./main.js">` 載入。

## Global Constraints

- 不可修改 `paginator.js`（vendored，ADR 0011）——所有新增邏輯只能寫在 `main.js`。
- `main.js` 的 `setAttribute`/`ResizeObserver` 呼叫本身**無 JS 單元測試**（比照 Issue 4/5/6/7 既有慣例），驗收依賴真機 `integration_test` 與人工視覺確認；每個 Task 仍須執行既有的 `flutter test`（回歸確認 Dart 端測試套件未受影響）與 `flutter analyze`。
- **不特例只挑「雙欄」模式才重算**——`window.applyPreferences(lastAppliedPrefs)` 每次都整包套用完整偏好，其餘欄位（字級/邊距/CSS 覆蓋/`max-column-count`）重算是 idempotent、無副作用，不加「只有 double 才重算」的特例判斷。
- debounce 間隔起始值 200ms，為起始建議值，非最終規格——真機測試若手感不佳（例如旋轉動畫途中觸發多次不必要的重排）可在 Task 2 內調整。
- 真機驗收裝置固定為 `3CEF42ECD491687`（本 Epic既有測試裝置）。

---

## 檔案結構

本計劃只修改單一檔案：

- **修改：** `app/android/app/src/main/assets/foliate/main.js`
  - 新增模組級變數 `lastAppliedPrefs`（追蹤最新一次套用的完整偏好物件）
  - `window.applyPreferences(prefs)` 函式開頭新增一行同步更新 `lastAppliedPrefs`
  - `openBook()` 內 `await view.open(book)` 之後新增 `ResizeObserver` 註冊與 debounce 邏輯

不涉及 Dart 端（`foliate_epub_reader_view.dart`／`reader_screen.dart`）——本 Issue 的机制完全是 JS 端自行偵測尺寸變化並重新套用已知偏好，不需要 Dart 端主動推播新事件。

---

### Task 1：新增 `lastAppliedPrefs` 追蹤變數

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js:43`（`currentWritingMode` 宣告之後）、`main.js:110`（`window.applyPreferences` 函式開頭）

**Interfaces:**
- Produces: 模組級可變變數 `lastAppliedPrefs`（型別與 `prefs` 參數相同的物件，例如 `{writingMode, fontSize, columnMode, columnSize, ...}`），供 Task 2 的 `ResizeObserver` callback 讀取最新值。

- [ ] **Step 1: 確認現況**

執行：
```bash
grep -n "currentWritingMode\|window.applyPreferences" app/android/app/src/main/assets/foliate/main.js
```

預期看到 `let currentWritingMode = 'horizontal'`（約第 43 行）與 `window.applyPreferences = function (prefs) {`（約第 110 行），且目前**沒有** `lastAppliedPrefs` 任何蹤跡（`grep -n "lastAppliedPrefs" app/android/app/src/main/assets/foliate/main.js` 應為空）。

- [ ] **Step 2: 在 `currentWritingMode` 宣告之後新增 `lastAppliedPrefs`**

在 `main.js` 第 43 行 `let currentWritingMode = 'horizontal'` 之後，新增：

```js
// Issue 9：裝置旋轉/視窗尺寸變化時重新呼叫 applyPreferences() 需要知道
// 「最後一次完整套用過的偏好物件」是什麼，見下方 window.applyPreferences()
// 開頭賦值處與 openBook() 內的 ResizeObserver 註冊。初始值設為 initialPrefs，
// 涵蓋「開書當下第一次 relocate 事件觸發 applyPreferences() 之前」若恰好
// 發生一次 resize 的邊界情況（此時仍能拿到開書時傳入的完整偏好，而非
// undefined）。
let lastAppliedPrefs = initialPrefs
```

- [ ] **Step 3: 在 `window.applyPreferences(prefs)` 函式開頭同步賦值**

找到 `main.js:110` 附近的：

```js
window.applyPreferences = function (prefs) {
  if (prefs.pageTurnMode) {
```

改為：

```js
window.applyPreferences = function (prefs) {
  // Issue 9：每次套用偏好都同步記錄下來，供 openBook() 內的
  // ResizeObserver debounce callback 在裝置旋轉/視窗尺寸變化後，能重新
  // 呼叫本函式並拿到「使用者最後一次實際設定的完整偏好」，而不是只拿到
  // 旋轉當下手邊剛好有的局部資料。
  lastAppliedPrefs = prefs
  if (prefs.pageTurnMode) {
```

- [ ] **Step 4: 靜態檢查與既有測試回歸**

執行：
```bash
cd app && flutter analyze
```
預期：`No issues found!`（本步驟未變動任何 Dart 檔案，純粹確認 Task 1 未意外破壞其他東西）。

```bash
cd app && flutter test
```
預期：全數通過（本步驟未新增/修改任何 Dart 測試，測試數與 Task 1 執行前的既有基準一致）。

- [ ] **Step 5: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(epic-18): Issue 9 新增 lastAppliedPrefs 追蹤最後套用偏好"
```

---

### Task 2：新增 `ResizeObserver` + debounce 重新套用偏好

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js:511`（`await view.open(book)` 之後）

**Interfaces:**
- Consumes: Task 1 產生的模組級變數 `lastAppliedPrefs`；`window.applyPreferences`（既有函式，Task 1 已在其內新增 `lastAppliedPrefs = prefs` 賦值，本 Task 直接呼叫它，不需要新增任何函式簽章）。
- Produces: 無新的對外可呼叫函式（本 Task 是純內部自動觸發機制，Dart 端無需新增/修改任何呼叫）。

- [ ] **Step 1: 確認 `view.renderer` 的建立時機**

執行：
```bash
grep -n "view.open(book)\|view.renderer\|await view.init" app/android/app/src/main/assets/foliate/main.js
```

預期看到 `openBook()` 函式內：
```js
await view.open(book)
view.renderer.setAttribute(
  'flow',
  initialPrefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
)
await view.init(initialCfi ? { lastLocation: initialCfi } : {})
```

`view.renderer` 是 `readest/foliate-js` 的 `view.js`（`View` 類別 `open()` 方法內，見 `view.js:258-269`）在 `view.open(book)` **當下同步建立**的 `<foliate-paginator>` 自訂元素（附掛到 `view` 的 shadow root）——換言之，`view.renderer` 只有在 `await view.open(book)` **之後**才保證存在，本 Task 的 `ResizeObserver` 註冊必須放在這一行之後、`view.init()` 之前或之後皆可（`view.init()` 才會觸發首次 `relocate`／`applyPreferences`，`ResizeObserver` 註冊本身不依賴 `view.init()` 是否已完成）。

- [ ] **Step 2: 在 `await view.open(book)` 之後新增 debounced resize 監聽**

找到 `main.js:511` 附近的：

```js
    await view.open(book)
    view.renderer.setAttribute(
      'flow',
      initialPrefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
    await view.init(initialCfi ? { lastLocation: initialCfi } : {})
```

改為：

```js
    await view.open(book)
    view.renderer.setAttribute(
      'flow',
      initialPrefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
    // Issue 9：裝置旋轉/視窗尺寸變化時重新呼叫 applyPreferences()。
    // 根因（見 ADR 0012「已知限制」段）：「雙欄」欄數模式的
    // max-inline-size（targetSize = Math.ceil(hostSize / 2)，見上方
    // window.applyPreferences() 的 columnMode === 'double' 分支）是呼叫
    // applyPreferences() 當下 getBoundingClientRect() 的一次性快照，寫死後
    // 不會再變動。paginator.js 自己的 ResizeObserver（paginator.js:1367，
    // 觀察內部私有 #container）在裝置旋轉/視窗尺寸變化後只會重新計算
    // divisor（用「當下真實 hostSize」對比「呼叫當下算出、此後不變的
    // max-inline-size」），不會觸發 applyPreferences() 重新執行、也不會
    // 重新計算 targetSize。
    // 這裡新增一個本專案自建、完全獨立的 ResizeObserver（觀察
    // view.renderer 這個 <foliate-paginator> 自訂元素本身的 box 尺寸——與
    // window.applyPreferences() 的 columnMode === 'double' 分支算 hostSize
    // 時用的是同一個元素的 getBoundingClientRect()，語意一致），debounce
    // 200ms（起始建議值，避免旋轉動畫過程中連續觸發多次不必要的重排）後
    // 呼叫 window.applyPreferences(lastAppliedPrefs)，讓「雙欄」模式的
    // targetSize 依當下真實尺寸重新計算。不特例只挑 columnMode ===
    // 'double' 才重算——整包 lastAppliedPrefs 重新套用一次，其餘欄位
    // （字級/邊距/CSS 覆蓋/max-column-count）重算是 idempotent、無副作用
    // （見 Global Constraints）。
    let resizeDebounceTimer = null
    new ResizeObserver(() => {
      if (resizeDebounceTimer) clearTimeout(resizeDebounceTimer)
      resizeDebounceTimer = setTimeout(() => {
        window.applyPreferences(lastAppliedPrefs)
      }, 200)
    }).observe(view.renderer)
    await view.init(initialCfi ? { lastLocation: initialCfi } : {})
```

- [ ] **Step 3: 靜態檢查與既有測試回歸**

執行：
```bash
cd app && flutter analyze
```
預期：`No issues found!`

```bash
cd app && flutter test
```
預期：全數通過，測試數與 Task 1 完成後的基準一致（本 Task 未新增/修改任何 Dart 檔案或測試）。

- [ ] **Step 4: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(epic-18): Issue 9 新增 ResizeObserver 於旋轉/尺寸變化時重新套用偏好"
```

---

### Task 3：真機驗收

**Files:** 無程式碼異動（本 Task 純真機人工驗證）。

**Interfaces:**
- Consumes: Task 1／Task 2 完成後的 `main.js`（含 `lastAppliedPrefs` 與 `ResizeObserver`）。
- Produces: 驗收結果記錄（供合併前的程式碼審查／`issues.md` Issue 9 狀態更新引用）。

- [ ] **Step 1: 安裝最新 debug APK 至真機 `3CEF42ECD491687`**

```bash
cd app && flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: 「雙欄」模式旋轉驗證**

1. 開啟一本直排 EPUB（`app/test/fixtures/sample.epub` 或既有測試書籍）。
2. 於「版面設定」將「欄數」切換為「雙欄」。
3. 直向（portrait）狀態下，用 `showNavZoneDebugOverlay`（若既有 debug overlay 機制可顯示目前 `max-inline-size`/欄寬）或肉眼比對目前欄寬。
4. 旋轉裝置至橫向（landscape），等待 debounce（約 200ms 以上）後，確認欄寬**重新計算**為新 `hostSize`（旋轉後的寬或高，依 `currentWritingMode` 而定）的一半，而非停留在旋轉前算出的舊數值。
5. 記錄：是否觀察到欄寬正確隨旋轉重算（Pass/Fail + 截圖佐證）。

- [ ] **Step 3: 位置不跳動驗證**

1. 在「雙欄」模式下翻到書本中段任一頁，記錄目前頁碼/進度文字（`Key('reader_foliate_progress_text')`）。
2. 旋轉裝置。
3. 確認旋轉後目前頁碼/進度文字**未跳動**（`paginator.js` 的 CFI-based relocate 理論上會保留閱讀位置，需真機驗證此假設在 `ResizeObserver` 重新套用偏好後依然成立）。
4. 記錄：Pass/Fail。

- [ ] **Step 4: 「單欄」／「自動」模式不受影響驗證**

1. 將「欄數」切換為「單欄」，旋轉裝置，確認畫面仍維持單欄（不因新增的 `ResizeObserver` 意外跑出多欄）。
2. 將「欄數」切換為「自動」，旋轉裝置，確認欄數變化行為與 Issue 9 修正前一致（`columnSize` 是使用者設定的固定常數，不隨 `hostSize` 變動，`ResizeObserver` 重新套用偏好對這兩態應為 no-op 等效行為）。
3. 記錄：Pass/Fail。

- [ ] **Step 5: 記錄驗收結果**

將 Step 2-4 的 Pass/Fail 結果與截圖整理，供後續程式碼審查（`superpowers:requesting-code-review`）與 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 9 狀態更新引用。若任一項 Fail，回頭調整 Task 2 的 debounce 間隔或觀察目標元素（`view.renderer` vs `view`），重新執行本 Task。

---

## 相關佐證

- ADR 0012（`docs/adr/0012-column-mode-replaces-single-column.md`）「已知限制」段——本 Issue 的根因描述出處。
- `docs/epics/epic-18-reader-device-qa/design.md`「第二輪真機使用回報」項目 5。
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 6（`columnMode`/`columnSize` 機制本身的既有實作）。
