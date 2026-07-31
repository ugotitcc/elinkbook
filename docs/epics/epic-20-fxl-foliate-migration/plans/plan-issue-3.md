# Epic 20 Issue 3 — 雙頁模式（`dualPageMode`／`isLandscape` 參數 + `main.js` spread 邏輯） 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 讓 `FoliateEpubReaderView` 渲染 FXL 書籍時支援橫向雙頁顯示，行為比照舊 `EpubReaderView.kt`（Readium）路徑既有的 `isDualPageEnabled(dualPageMode, isLandscape)` 邏輯，移植成 JS 供 `foliate-fxl` 自訂元素使用。

**依賴：** Issue 2（已合併，`main`，merge commit `904acec`）。

**架構（`spec.md`「核心介面異動」第 1/2 節）：** 不新增資料模型（`DualPageMode` enum、`ResolvedPreferences.dualPageMode` 皆為既有欄位，PDF 路徑已在用）；只新增 `FoliateEpubReaderView` 建構參數與 `main.js` 對應的 spread 分派邏輯。

**已查證的關鍵技術事實（避免計劃內容基於臆測，皆已對照 `fixed-layout.js` 原始碼／既有 Kotlin 實作逐行確認）：**

- `EpubReaderView.kt:149-151` 既有的 `isDualPageEnabled(dualPageMode, isLandscape)` 純函式邏輯：`dualPageMode == ALWAYS || (dualPageMode == AUTO && isLandscape)`。`EpubReaderView.kt:784` 把結果直接摺疊成 Readium 的二值 `Spread.ALWAYS`／`Spread.NEVER`（**不是**傳遞細緻的 landscape/portrait/none 三態），本工單移植時採用完全相同的二值摺疊方式，不引入額外狀態。
- `fixed-layout.js` 的 `foliate-fxl` 自訂元素以 `spread` HTML attribute（`observedAttributes` 已含）驅動版面分頁邏輯，`attributeChangedCallback` case `'spread'` 呼叫 `#respread(value)`（`fixed-layout.js:367-368`）。
- `#spread(mode)`（`fixed-layout.js:1108-1148`）：`this.spread = mode || rendition?.spread`。**只有字面值 `'none'` 會強制單頁**（`this.spread === 'none'` 時每個 section 各自成一個 spread，`fixed-layout.js:1115-1116`）；其餘任何非 `'none'` 值（含未設定、空字串）都會依每個 section 的 `pageSpread`（`page-spread-center`/`left`/`right`，由 `epub.js` 解析，Issue 1 Spike 已驗證正確辨識）與 `book.dir`（RTL/LTR）自動配對——**封面獨立顯示與 RTL 頁序不需要額外程式碼，由 `fixed-layout.js` 既有邏輯自動處理**（Issue 1 Spike 已驗證的兩項判準）。
- `#render()`（`fixed-layout.js:444-457`）另有獨立的容器長寬比啟發式：`height > width * 1.2` 時視為 portrait、強制單頁渲染（即使 `#spread()` 已把兩個 section 配成一組），**除非** `this.spread === 'both'` 或 `this.spread === 'portrait'`，這兩個字面值會略過此啟發式、強制以橫向雙頁樣式渲染。這與 `EpubReaderView.kt:784` 把 `ALWAYS`/`AUTO+isLandscape` 一律摺疊成同一個 `Spread.ALWAYS` 值（不依賴容器長寬比自行判斷）的既有設計完全對應——本工單比照辦理，`isDualPageEnabled` 為真時一律送出 `'both'`（不是只送任意非 `'none'` 值），避免依賴 `fixed-layout.js` 自己的長寬比啟發式在轉場/裝置邊界情況下與 Dart 端計算的 `isLandscape` 不一致而誤判。
- 结論映射：`view.renderer.setAttribute('spread', isDualPageEnabled(dualPageMode, isLandscape) ? 'both' : 'none')`。
- `main.js` 目前完全沒有處理 `dualPageMode`／`isLandscape`（`grep` 確認零匹配）；`applyPreferences()` 的 FXL 分支（Issue 2 新增，`main.js:126-139`）目前只處理 `pageTurnMode`／`writingMode`，是本工單要擴充的位置。
- 專案沒有 Node.js/JS 測試框架（`find` 確認無 `package.json`／`*.test.js`），`main.js` 的 `isDualPageEnabled` 邏輯與既有 FXL 分支程式碼一樣，只能透過程式碼審查 + 真機驗證把關，不強求 JS 單元測試（比照 Issue 2 `applyPreferences()` FXL 分支的既有先例）。

## Global Constraints

- 不修改 `readest/foliate-js` 釘定版本本身（`fixed-layout.js` 等 9 個檔案內容）。
- `isDualPageEnabled` 的 JS 移植版與 `EpubReaderView.kt:149-151` 保持邏輯完全一致（含摺疊成二值 `'both'`/`'none'` 的既有設計），不自行擴充成三態或加入新語意。
- 測試素材沿用 `tmp/一弦定音.epub`（Issue 1 Spike／Issue 2 已驗證的同一本真實橫向漫畫書，`rendition:page-spread-center`／`page-spread-left`／`page-spread-right`／`page-progression-direction="rtl"` 皆已知）；真機固定使用 `3CEF42ECD491687`。
- 本工單只新增雙頁能力，不涉及 `EpubReaderView.kt`／`readium-navigator` 清理（Issue 5 範圍）。

---

## 檔案結構

- Modify：`app/android/app/src/main/assets/foliate/main.js`
- Modify：`app/lib/reader/foliate_epub_reader_view.dart`
- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/test/reader/foliate_epub_reader_view_test.dart`、`app/test/screens/reader_screen_test.dart`

---

### Task 1：`main.js` 新增 `isDualPageEnabled` 移植與 `spread` attribute 分派

**Files:**
- Modify：`app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes：`prefs.dualPageMode`（`'auto'`／`'always'`／`'never'`，比照既有 `prefs.columnMode` 等欄位的字串慣例）、`prefs.isLandscape`（boolean）
- Produces：FXL 書籍橫向雙頁模式下正確顯示兩頁並排，直向/單頁模式維持單頁

- [ ] **Step 1：新增 `isDualPageEnabled` 純函式**

在 `main.js` 頂層（`window.applyPreferences` 定義之前，比照既有 `buildOverrideCss()` 等頂層 helper 函式的位置慣例）新增：

```js
/**
 * 移植自 EpubReaderView.kt（Readium 路徑既有邏輯，:149-151），FXL 雙頁
 * 模式的觸發判斷——ALWAYS 恆真、AUTO 依 isLandscape、NEVER 恆假。
 * 沿用該處把結果摺疊成二值（而非細緻的三態 spread 值）的既有設計，
 * 見 plan-issue-3.md「已查證的關鍵技術事實」。
 */
function isDualPageEnabled(dualPageMode, isLandscape) {
  return dualPageMode === 'always' || (dualPageMode === 'auto' && isLandscape === true)
}
```

- [ ] **Step 2：`applyPreferences()` FXL 分支新增 `spread` attribute 設定**

修改 `main.js:126-139`（Issue 2 新增的 FXL 早回分支），在 `if (prefs.pageTurnMode) { ... }` 之後、`return` 之前新增：

```js
  view.renderer.setAttribute(
    'spread',
    isDualPageEnabled(prefs.dualPageMode, prefs.isLandscape) ? 'both' : 'none',
  )
```

（`'both'`／`'none'` 兩個字面值的選擇理由見「已查證的關鍵技術事實」——`'both'` 同時控制 section 配對與略過容器長寬比啟發式，不是隨意挑選。）

- [ ] **Step 3：確認初次開書套用路徑不需額外修改**

`openBook()` 內 `{once:true}` 的 relocate 監聽器已呼叫 `window.applyPreferences({ ...initialPrefs, writingMode: resolvedWritingMode })`（`main.js:422`），只要 Task 2 把 `dualPageMode`／`isLandscape` 塞進 `initialPrefs`（透過 `_buildIndexUri()` 的 query string，Dart 端 Task 2 負責），Step 2 新增的邏輯會在開書當下自動套用一次，不需要在 `openBook()` 額外呼叫。裝置旋轉時的 `ResizeObserver` debounce callback（`main.js:` 約 588-595）已呼叫 `window.applyPreferences(lastAppliedPrefs)`，同樣自動涵蓋——本 Step 純粹是確認並記錄，不需要新增程式碼，若真機驗證（Task 4）發現不成立才回頭修正。

**審查發現（計劃審查 Important #2，2026-07-31，時序已逐行查證）**：這個時序安排會讓**每一本 FXL 書開啟時都發生一次隱性的「先渲染一次、緊接著立刻依 spread 設定重渲染一次」**，非邊界情況、必然發生：`fixed-layout.js` 的 `open(book)`（:1100-1107）內部無條件呼叫無 mode 參數的 `#spread()`，`view.init()` 觸發的第一次導覽一律先用「未指定 spread」的預設配對完成一次真正渲染（建立 iframe、載入內容）；緊接著本 Step 描述的 relocate 監聽器內才第一次呼叫 `applyPreferences()`，Step 2 新增的 `setAttribute('spread', ...)` 是該 attribute**第一次**被賦值，此時 `this.#index` 已因第一次導覽完成而 `>= 0`，不會被 `#respread()` 的 `this.#index === -1` 防呆擋下，因此會真正重新執行配對、清空快取、重建 iframe——真機上可能表現為開書當下短暫的畫面閃爍/重排。

**已排除的替代方案（勿採用）**：「在 `view.init()` 之前預先設定 `spread` attribute」看似可以避免這個雙重渲染，但已查證對 `fixed-layout.js` 現有實作是無效的 no-op——`view.init()` 呼叫前 `this.#index` 仍是初始值 `-1`，`#respread()` 開頭的防呆會讓這次設定直接不生效（連 `#spread(spreadMode)` 都不會被呼叫）。目前計劃選擇的時序（`view.init()` 完成首次導覽後才呼叫 `applyPreferences()`）是「不修改釘定版本」Global Constraints 下唯一可行的做法，不是考慮不周，**不需要調整實作時序**——本項風險純粹留給 Task 4 的真機驗收判準追蹤。

---

### Task 2：Dart 端 `FoliateEpubReaderView` 新增 `dualPageMode`／`isLandscape` 建構參數

**Files:**
- Modify：`app/lib/reader/foliate_epub_reader_view.dart`

**Interfaces:**
- Consumes：`ResolvedPreferences.dualPageMode`（既有欄位，PDF 路徑已在用）、`ReaderScreen` 計算的 `isLandscape`（既有邏輯，`reader_screen.dart:1226`）
- Produces：`buildFoliatePreferencesMap()` 輸出含 `dualPageMode`／`isLandscape`，`foliatePreferencesChanged()` 正確偵測兩者變動

- [ ] **Step 1：新增建構參數欄位**

**審查修正（計劃審查 Important #1，2026-07-31）**：`dualPageMode`／`isLandscape` 兩者簽章不同，須依 `spec.md`「核心介面異動」第 1 節（本 Epic 唯一事實來源）逐字對齊，不可兩者一律 nullable：

```dart
final DualPageMode? dualPageMode;   // 沿用既有 dual_page_mode.dart 列舉，比照 isFixedLayoutHint 先例維持 nullable
final bool isLandscape;             // 比照舊 EpubReaderView 的必要參數，非 nullable，預設 false
```

`dualPageMode` 比照既有 `isFixedLayoutHint` 欄位的加入方式（Issue 2 先例），optional 具名參數，預設 `null`，讓 `buildFoliatePreferencesMap()`「null 值完全不出現在 map 中」的既有慣例continue適用。`isLandscape` **不**適用此慣例——依 `spec.md` 明文宣告比照舊 `EpubReaderView`（`epub_reader_view.dart:126`：`this.isLandscape = false,`）採非 nullable、預設 `false` 的必要參數寫法，建構子新增 `this.isLandscape = false,`。新增 `import 'dual_page_mode.dart';`。

- [ ] **Step 2：`buildFoliatePreferencesMap()` 擴充**

`dualPageMode` 比照既有 `isFixedLayoutHint` 那行的 nullable 寫法；`isLandscape` 為非 nullable，恆定加入 map（無需 `if` 判斷）：

```dart
if (view.dualPageMode != null) map['dualPageMode'] = view.dualPageMode!.name;
map['isLandscape'] = view.isLandscape;
```

- [ ] **Step 3：`foliatePreferencesChanged()` 擴充**

新增比較條件：

```dart
oldView.dualPageMode != newView.dualPageMode ||
oldView.isLandscape != newView.isLandscape ||
```

- [x] **Step 4：單元測試**

於 `app/test/reader/foliate_epub_reader_view_test.dart` 比照 Issue 2 審查回應新增的 `isFixedLayoutHint` 測試組（`buildFoliatePreferencesMap` group、`foliatePreferencesChanged` group），新增：
- `dualPageMode: DualPageMode.always` 時 map 含 `dualPageMode: 'always'`
- `dualPageMode` 未設定（null）時 map 不含該 key（可併入既有「所有偏好欄位皆為 null」測試案例，或個別新增）
- `isLandscape` 為非 nullable 必要參數，恆定出現在 map 中——新增 `isLandscape: true` 與預設值（未傳入，即 `false`）兩種情況皆驗證 map 含正確的 `isLandscape` 值（不是「未設定時不出現」，與 `dualPageMode` 的測試性質不同）
- `dualPageMode` 變動／`isLandscape` 變動皆使 `foliatePreferencesChanged` 回傳 `true`

**建議追加（計劃審查 Minor #1）**：`isDualPageEnabled` 的判斷邏輯（`always`/`auto+landscape`/`auto+portrait`/`never` 四種組合）目前只能在 JS 端驗證（本 repo 無 JS 測試框架），純靠真機肉眼驗證+程式碼審查把關、無法留下自動化迴歸測試。建議在 Dart 端另補一個邏輯等效的 truth table 測試（例如直接把 `main.js` 的 `isDualPageEnabled` 判斷式抄一份等效邏輯到測試檔案內做四種組合斷言，作為可執行文件），非強制項目。

執行 `flutter test test/reader/foliate_epub_reader_view_test.dart` 確認全部通過。

---

### Task 3：`reader_screen.dart` 傳入 `dualPageMode`／`isLandscape` 給 `FoliateEpubReaderView`

**Files:**
- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 2 新增的建構參數
- Produces：EPUB（FXL）真機橫向雙頁模式下正確顯示兩頁並排，取代舊 `EpubReaderView` 已死的傳遞路徑

- [x] **Step 1：`_buildNativeView()` 的 `FoliateEpubReaderView(...)` 建構新增兩個具名參數**

`reader_screen.dart:1945-1979`（`case BookFormat.epub` 分支）新增：

```dart
dualPageMode: resolved.dualPageMode,
isLandscape: isLandscape,
```

（`resolved`／`isLandscape` 皆為該函式既有可用的區域變數，`PdfReaderView` 分支已在用同名欄位，直接比照複製，不需要新增任何上游計算邏輯。）

- [x] **Step 2：測試更新**

比照 `test/screens/reader_screen_test.dart:684-780` 既有針對 `PdfReaderView.isLandscape`／`PdfReaderView.dualPageMode` 的測試寫法，新增等效的 `FoliateEpubReaderView` 版本（裝置橫向/直向時 `isLandscape` 正確下傳、`dualPageMode` 正確下傳），或視既有 FXL 相關測試案例（`isFixedLayout: true` 那組）擴充追加斷言。

執行 `flutter test test/screens/reader_screen_test.dart` 確認全部通過。

---

### Task 4：真機驗證、文件更新、送出 PR

**Files:**
- Modify：`docs/epics/epic-20-fxl-foliate-migration/design.md`、`issues.md`、`docs/epics.md`、本計畫檔

**Interfaces:**
- Consumes：Task 1-3 已完成
- Produces：合併回 `main` 的雙頁能力

- [x] **Step 1：全套測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
flutter test
```

須為 0 issues／全部通過，且不得比 Issue 2 合併後的基準測試數少（回歸檢查）。

- [x] **Step 2：建置並安裝至真機（`3CEF42ECD491687`）**

```bash
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 3：真機驗證（比照 Issue 1 Spike 已驗證的四項判準，逐一在雙頁模式下重新確認）**

用 `tmp/一弦定音.epub`，於 App 內開啟該書：
1. 橫向雙頁：旋轉裝置至橫向（或 `dualPageMode: always` 設定），確認兩頁並排顯示。
2. 封面獨立顯示：翻到封面／`page-spread-center` 頁，確認即使橫向雙頁模式下仍單獨顯示（不與其他頁並排）——驗證 `#spread()` 既有配對邏輯不受本工單新增的 `'both'` 值影響（`'both'` 只影響長寬比啟發式，不影響 `pageSpread` 配對本身，理論上不受影響，但仍需真機肉眼確認）。
3. RTL 頁序：橫向雙頁模式下確認頁面順序符合右至左（日式漫畫閱讀順序）。
4. 直向/單頁模式（`dualPageMode: never` 或裝置直向且 `dualPageMode: auto`）：確認維持單頁顯示，無回歸。
5. **開書當下的雙重渲染觀察**（計劃審查 Important #2）：任何 FXL 書開啟時，理論上都會先以未指定 spread 的預設配對渲染一次，緊接著才依 `dualPageMode`/`isLandscape` 重新配對渲染——真機肉眼觀察開書當下是否有可感知的畫面閃爍/重排，記錄觀察結果（可接受／不可接受）。若不可接受，記錄為已知限制並另立後續工單評估緩解方案（例如延遲至首次可見前才顯示畫面），本工單**不**因此調整 `main.js` 的 `applyPreferences()` 呼叫時序（已查證「提前設定 `spread` attribute」對 `fixed-layout.js` 現有實作無效，見 Task 1 Step 3）。

- [x] **Step 4：依結果更新 `design.md`／`issues.md`／`docs/epics.md`**

- [ ] **Step 5：Commit（於獨立 feature branch，比照 Issue 2 branch 命名慣例 `feature/epic-20-issue-3-*`）**

- [ ] **Step 6：送出 code review（`superpowers:requesting-code-review`），依審查結果修正後開 PR**

---

## 相關佐證

- `docs/epics/epic-20-fxl-foliate-migration/spec.md`「核心介面異動」第 1/2 節
- `docs/adr/0017-fxl-migrate-to-foliate-js.md`
- `docs/epics/epic-20-fxl-foliate-migration/reviews/spike-issue1-fxl-foliate.md`（Issue 1 Spike 已驗證的封面獨立顯示／RTL 頁序判準）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:149-151`（`isDualPageEnabled` 既有 Kotlin 實作）、`:784`（摺疊成二值 `Spread.ALWAYS`/`Spread.NEVER` 的既有設計）
- Readest `foliate-js` fork（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`）：`fixed-layout.js:188`（`observedAttributes` 含 `spread`）、`:367-368`（`attributeChangedCallback` 分派）、`:1108-1148`（`#spread(mode)` 配對邏輯，`'none'` 特殊值）、`:444-457`（`#render()` 容器長寬比啟發式，`'both'`/`'portrait'` 特殊值）
- `app/lib/reader/dual_page_mode.dart`（`DualPageMode` enum 既有定義）
- `app/lib/reader/epub_reader_view.dart:49-50,125-126,303-304`（Readium 路徑既有 `dualPageMode`/`isLandscape` 參數傳遞慣例，本工單移植對象）
- `app/lib/screens/reader_screen.dart:1226,1996-1999`（`isLandscape` 既有計算邏輯、`PdfReaderView` 既有傳遞慣例）
