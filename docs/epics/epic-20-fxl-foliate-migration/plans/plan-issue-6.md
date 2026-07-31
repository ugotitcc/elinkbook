# Epic 20 Issue 6 — FXL 書籤驗證（沿用既有 CFI locator 持久化機制） 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 驗證 FXL 書籍在單頁／雙頁模式下的書籤新增/刪除/跳轉/清單顯示是否正常運作，與既有流式書籍書籤功能行為一致。本工單**純驗證性質，不預先假設需要程式碼修正**（ADR 0017 決策 6：書籤沿用既有 CFI locator 持久化機制，`epic-17` Issue 6 已為 reflowable 建立，風險低、無視覺 overlay）。

**依賴：** Issue 3（已合併，`main`，雙頁模式）、Issue 5（已合併，`main`，`EpubReaderView.kt`／`readium-navigator` 已移除）。

**架構（ADR 0017 決策 5/6）：** 書籤機制（`BookmarksRepository`、`Bookmark.epubLocatorJson`、`_toggleBookmark()`/`_bookmarkAtCurrentPosition`/`_loadFxlBookmarks()`，見 `reader_screen.dart:601-649`）自 `epic-6-annotations` Issue 4 起即支援 FXL，且已有大量既有 widget test 覆蓋（`test/screens/reader_screen_test.dart:2304-2650` 一帶，「Epic 6 Issue 4：FXL 書籤支援」）。這些既有測試皆以**單頁**情境驗證按鈕狀態機／清單渲染／跳轉呼叫分派，**完全沒有涵蓋雙頁模式下的行為**——這正是本工單要補的驗證缺口，且雙頁模式（Issue 3）與書籤機制之間沒有程式碼互動（`_toggleBookmark()`/`_bookmarkAtCurrentPosition` 不讀取 `dualPageMode`/`isLandscape`/`_isFixedLayout` 以外的任何雙頁狀態），理論上不需要新程式碼——本工單的任務是**用真機驗證這個理論成立**，而非預先實作。

**已查證的關鍵技術事實（避免計劃內容基於臆測，皆已對照現況逐行確認）：**

- `_bookmarkAtCurrentPosition`（`reader_screen.dart:618-625`）比對 `_epubPositionInfo?.locatorJson` 與 `_fxlBookmarks` 內每筆 `Bookmark.epubLocatorJson` 是否**完全相同字串**。雙頁模式下 `FoliateEpubReaderView` 的 `onLocatorChanged` 回報的 `locatorJson` 具體會是「當前顯示中兩頁的哪一頁」（左頁或右頁，或某種聯集/中點表示法）目前**未經查證**——這是本次驗證要釐清的第一個具體問題：雙頁模式下新增書籤，記下的究竟是左頁還是右頁的定位，會不會因為畫面上顯示兩頁、使用者直覺認知模糊，導致「書籤圖示狀態」與「使用者以為記的位置」不一致。
- `_jumpToEpubLocator()`（`reader_screen.dart:660-663`）無條件呼叫 `FoliateEpubReaderView.jumpToLocator(_foliateEpubReaderViewKey, locatorJson)`，不區分目前是否為雙頁模式——跳轉後畫面是否正確以「該筆定位所在的頁面配對」重新排版成雙頁（而非只顯示單頁、或雙頁配對錯位），需真機觀察確認，程式碼本身沒有特殊處理，行為完全由 `fixed-layout.js`／`view.js` 既有的 `goTo`/`relocate` 機制決定。
- **既有 widget test 覆蓋範圍**（`test/screens/reader_screen_test.dart:2304-2650`）：新增/移除書籤按鈕狀態切換、Bottom Sheet 書籤分頁清單渲染、書籤點選跳轉呼叫分派——皆是 mock 掉 `onLocatorChanged`/`jumpToLocator` 的 Dart 端邏輯驗證，不涉及真實 `fixed-layout.js` 渲染，雙頁配對正確性/CFI 定位精確度不在其驗證範圍內，本工單的真機驗證與既有測試互補、不重複。
- **測試素材沿用 `tmp/一弦定音.epub`**（Issue 1 Spike／Issue 2/3/4 已驗證的同一本真實橫向漫畫書，`page-progression-direction="rtl"`，202 個 spine items），真機固定使用 `3CEF42ECD491687`（已確認連線中）。
- **既有 FXL 書籍書籤資料視為失效**（ADR 0017 決策 5，Readium Locator 與 foliate-js CFI 無法互轉）——驗證時應使用全新匯入的書籍或全新新增的書籤，不應假設裝置上殘留的舊書籤資料仍然有效；若裝置上有本 Epic 遷移前建立的 FXL 書籤，驗證前應先確認其狀態（預期已無法正確跳轉，這是已知且可接受的行為，非本工單要修的缺陷）。

## Global Constraints

- 純驗證性質，**不預先撰寫或修改任何 `.dart`／`.kt` 程式碼**——若真機驗證發現異常，先如實記錄具體現象（畫面截圖＋文字描述），評估是否需要另立子工單修正，不在本計劃內直接修（比照 `issues.md` Issue 6 原始描述「視實際發現情況另開子工單，不預先假設有問題」）。
- 若驗證結果全數正常，不需新增任何測試（純驗證性質，`issues.md` Issue 6 原始描述已明文）。
- 驗證過程中發現的、與書籤無關的其他既有缺陷（例如程式碼審查/文件落差類問題），比照本 Epic 一貫做法：記錄但不在本工單內處理，另行提出。

---

## 檔案結構

- Modify（僅限驗證完成後的紀錄性更新）：`docs/epics/epic-20-fxl-foliate-migration/design.md`、`issues.md`、本計畫檔
- **不修改任何 `app/` 底下的程式碼／測試檔**（除非驗證發現異常且經評估後決定修正，屆時需回頭修訂本計劃並重新走一輪規劃/審查流程，不在本輪範圍內）

---

### Task 1：真機驗證——單頁模式書籤基本行為（回歸基準）

**Files:** 無（純真機操作，不改動任何檔案）

**Interfaces:**
- Consumes：`tmp/一弦定音.epub`、裝置 `3CEF42ECD491687`
- Produces：單頁模式下書籤新增/刪除/跳轉/清單行為的真機觀察紀錄

- [ ] **Step 1：建置並安裝最新 `main` APK 至真機**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2：裝置轉直向，匯入／開啟 `tmp/一弦定音.epub`，確認單頁模式**

`adb shell settings put system user_rotation 0`，確認 `dualPageMode` 未強制（預設 `auto`）情況下直向即為單頁。

- [ ] **Step 3：新增書籤，確認懸浮書籤按鈕圖示切換（🔖 outline → filled 或既有慣例的視覺區分）**

- [ ] **Step 4：開啟筆記 Bottom Sheet「🔖 書籤」分頁，確認剛新增的書籤出現在清單，名稱/位置描述合理**

- [ ] **Step 5：翻到不同頁，點選清單中的書籤，確認正確跳轉回原本新增書籤的那一頁（畫面內容比對，非只看頁碼數字）**

- [ ] **Step 6：刪除該書籤（懸浮按鈕再次點擊，或清單內滑動刪除，依既有 UI 慣例），確認按鈕圖示與清單同步更新**

（此 Task 為既有 `epic-6-annotations` 功能的回歸基準確認，預期全數正常——若此處就出現異常，代表問題與雙頁模式無關，是更基礎的既有缺陷，應優先處理並重新評估本工單範圍。）

---

### Task 2：真機驗證——雙頁模式書籤行為（本工單核心）

**Files:** 無（純真機操作，不改動任何檔案）

**Interfaces:**
- Consumes：Task 1 確認單頁模式基準正常
- Produces：雙頁模式下書籤新增/刪除/跳轉/清單行為的真機觀察紀錄，含「已查證的關鍵技術事實」點出的兩個具體疑點的結論

- [ ] **Step 1：裝置轉橫向，確認 `tmp/一弦定音.epub` 進入雙頁模式（兩頁並排）**

`adb shell settings put system user_rotation 1`（或對應橫向值，比照 Issue 3 驗證慣例）。

- [ ] **Step 2：在雙頁並排畫面中新增書籤，明確記錄畫面當下顯示的左右兩頁內容（截圖）**

- [ ] **Step 3：確認懸浮書籤按鈕圖示切換，並開啟書籤清單，確認新增的書籤出現，比對名稱/位置描述是否讓使用者能辨識出「是哪一頁」（呼應「已查證的關鍵技術事實」第一點的疑慮）**

- [ ] **Step 4：翻到書中其他位置（不同頁/不同雙頁配對），點選清單中該筆書籤，確認跳轉後畫面正確顯示回 Step 2 截圖記錄的那組雙頁配對（左右頁內容一致，非只有其中一頁對、另一頁錯位，呼應「已查證的關鍵技術事實」第二點的疑慮）**

- [ ] **Step 5：刪除該書籤，確認雙頁模式下按鈕圖示與清單同步更新行為與單頁模式（Task 1 Step 6）一致**

- [ ] **Step 6：跨模式一致性——在雙頁模式新增一筆書籤後，裝置轉回直向（單頁），確認該書籤仍正確出現在清單中且可正常跳轉（CFI locator 不因版面模式切換而失效）；反向（單頁新增、轉橫向雙頁確認）也驗證一次**

- [ ] **Step 7：若 Step 1-6 全數正常，額外用 `tmp/膽大黨10.epub`（另一本真實 FXL 漫畫，Issue 8 已知因檔案過大〔217MB〕可能無法開啟）視情況做一次抽樣確認——若因 Issue 8 的 OOM 問題無法開啟，記錄並跳過，不視為本工單失敗（Issue 8 是獨立已知問題，不阻塞本工單）**

---

### Task 3：文件更新、送出 PR

**Files:**
- Modify：`docs/epics/epic-20-fxl-foliate-migration/design.md`、`issues.md`、`docs/epics.md`、本計畫檔

**Interfaces:**
- Consumes：Task 1-2 驗證結果
- Produces：Issue 6 結案紀錄（或若發現異常，記錄具體現象並建議後續子工單方向，比照 Issue 8/9 的處理模式）

- [ ] **Step 1：依 Task 1-2 實際觀察結果，如實記錄於 `design.md`「Issue 6 實作完成紀錄」**——若全數正常，明確寫「純驗證，無程式碼異動」；若發現任何異常，具體描述現象（不得只寫「有問題」），並說明是否已另立 Issue／子工單追蹤。

- [ ] **Step 2：更新 `issues.md` Issue 6 Status 為 ✅ 或視發現結果調整（例如若有異常則保留 `needs-triage` 並補充發現內容）**

- [ ] **Step 3：更新 `docs/epics.md`（若 Epic 整體狀態因此有變動）**

- [ ] **Step 4：本計畫檔 Task 1-3 所有 Step 依實際完成進度勾選**

- [ ] **Step 5：Commit（比照 Issue 2-5 branch 命名慣例 `feature/epic-20-issue-6-*`，若無任何程式碼異動，允許本工單只有文件 commit，不強制建立空的程式碼變更）**

- [ ] **Step 6：送出 code review（`superpowers:requesting-code-review`），依審查結果修正後開 PR**

---

## 相關佐證

- `docs/epics/epic-20-fxl-foliate-migration/issues.md` Issue 6 原始描述
- `docs/adr/0017-fxl-migrate-to-foliate-js.md` 決策 5／6
- `app/lib/screens/reader_screen.dart:601-663`（`_loadFxlBookmarks`／`_bookmarkAtCurrentPosition`／`_toggleBookmark`／`_jumpToEpubLocator`）
- `app/test/screens/reader_screen_test.dart:2304-2650`（既有 `epic-6-annotations` Issue 4 FXL 書籤 widget test 覆蓋範圍，本工單與其互補）
- `docs/epics/epic-20-fxl-foliate-migration/plans/plan-issue-3.md` Task 4（真機驗證方法論參考，含裝置旋轉指令、截圖存檔慣例 `tmp/epic-20/`）
