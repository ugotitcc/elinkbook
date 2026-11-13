# Issue 24：雙欄一般翻頁的「目前章節」判定 Plan（輕量）

**Goal：** 流式 EPUB 在雙欄（兩欄同時可見）時，一般翻頁後的「目前章節」改為把**先被讀到的那一欄**當成單欄的那一頁，取該欄範圍內最後一個目錄項（**規則 B**），而不是「兩欄範圍內最後一個目錄項」；單欄與目錄跳轉的行為不變。

> 修訂記錄（2026-11-12，依 `reviews/review-plan-issue-24.md`）：更正 Task 3 的索引來源（relocate 事件沒有頂層 `index`，改用現有的 `chapterIndex = section?.current`）；補防禦性寫法與回退；Task 4 補頁首章名斷言（需 `showHeader` 且工具列隱藏）與具體翻頁方式、單欄多錨點回歸案例；更正「`columnCount` 沒有公開讀取方法」的錯誤陳述並調整 Task 1 候選順序；Task 5 補執行路徑與 l10n 檢查。

## 已定共識（2026-11-12 grilling，Q1～Q6）
- **規則（最終：規則 B，人類 2026-11-13）：** 雙欄時目前章節＝**第一欄範圍內最後一個目錄項**（橫排為左欄；直排雙欄是沿垂直方向的上下兩欄，先讀上欄——原先寫「直排為右欄」是錯的，已更正）。取代現行「兩欄範圍內最後一個」。單欄規則不變。
- **規則決定的經過：** 最初選了「規則 A＝可視範圍起點」（人類 2026-11-13 同意），實作後 Windows 子集跑測發現 2 個回歸（開書第一頁標到上層項導致既有「開書位於第一節」測試失敗；錨點跳轉後標題不在第一欄最上方時標成前一節導致 `foliate_toc_footer_test` 失敗），人類改選規則 B 並指定**不改 vendor、在 `main.js` 自己算**（選項 1）。
- **單欄不動：** 手機等單欄維持現行「該頁最後一個目錄項」，不在本 Issue 範圍。
- **實作層：** `app/android/app/src/main/assets/foliate/main.js` 的 relocate 處理：用 `view.renderer` 公開的 `start`／`size`／`columnCount` 算第一欄邊界，找出第一欄最後一個字，把 range 的結尾截到那裡，再交給現成的 `view.getProgressOf(section.current, 截短 range)` 重算 `tocItemId`。**不改釘定 vendor（`progress.js`／`view.js`／`paginator.js`）、不改 Dart 契約**（`tocItemId` 仍是同一個欄位；Dart 端 `toc_jump_override.dart`、`reader_screen.dart` 不動）。動到 vendor 或契約一律先停下回報人類。
- **`TocJumpOverride` 維持原樣：** 目錄跳轉後 paginator 會把前一節補進第一欄，第一欄範圍內最後一個目錄項在那種情況下會是前一節，所以覆寫仍需要（它管「目錄面板跳轉」，新規則管「一般翻頁」）。
- **其他跳轉不納入修復：** 書籤、劃線、搜尋跳轉只在驗證時順便觀察並記錄。
- **驗證：** Windows 1280x800 整合測試加 `foliate_touch_harness` 場景；BooksPad 橫向若實際顯示雙欄就驗證一次，否則報告寫明「Android 橫向平板未驗證」。
- 詞彙表 `CONTEXT.md` 已新增「目前章節（Current Chapter）」（本分支，已定義單欄／雙欄規則）。

## Task 1 診斷結果與規則決定（2026-11-13）
- **雙欄偵測：採 (c) `view.renderer?.columnCount > 1`。** 1280x800 自動欄數（橫排、直排）為 2；400x800 自動欄數為 1；1280x800 強制單欄為 1。「章節尾頁只有一欄有內容」時的值未驗證。
- **重現（1280x800 雙欄，`sample_single_spine_multi_anchor.epub`，ids：0 單檔範例、1 第一節、2 第二節、3 第三節）：** 翻頁 1（左欄起點第 1 節第 30 段、右欄尾端第二節標題）現行判定 2，起點判定 1；翻頁 3（起點第 2 節第 33 段、右欄含第三節標題）現行判定 3，起點判定 2。直排同樣偏（現行比起點多一節）。
- **規則 A 的失敗證據（2026-11-13，Windows 子集跑測，`assets/issue-24-windows-subset.log`）：** `epub_toc_test` 單 spine 多錨點案例（Windows 預設視窗 800x600 就是雙欄）「開書位於第一節」失敗——第一頁左欄含上層標題與第一節標題，起點規則標到上層項；`foliate_toc_footer_test`「跳到第三節後 tocItemId 應為 3，實際為 2」失敗——標題不在第一欄最上方時標成前一節。BooksPad 直立時 CSS 寬約 749（`ceil(749/720)=2`）也是雙欄，所以主力裝置直接受影響。
- **規則 B 的座標依據（harness 實測）：** 橫排 1280x800：`renderer.start`／`size` 為 0／1223、1223／1223…；第一欄 x∈[start, start+size/2)，第二欄文字 x 約 start+612 起。直排 1280x800：`size` 800（沿 y 軸），第一欄 y∈[start, start+400)。第一欄邊界＝`renderer.start + renderer.size / renderer.columnCount`，字的起點座標（橫排 `left`、直排 `top`）小於邊界即屬第一欄。
- **已知限制（人類接受）：** 第二欄才出現的標題要翻頁後才反映；錨點跳轉後若標題落在第二欄，JS 層回報的是前一節（TOC 面板跳轉由 Dart 端 `TocJumpOverride` 處理，其他跳轉類只記錄觀察）；水平 RTL 書、第一欄切不出（任何例外）時退回現行判定。
- relocate 的 range 只涵蓋主要區段（primary section）：跨 spine 的補欄內容（例如左欄是前一章尾、右欄是下一章頭）不在 range 內，所以該情境現行判定本來就是以主要區段為準；本 Issue 實際修的是**同一個 spine 內多個目錄錨點橫跨兩欄**的情況。

## 現況與已查證的事實
- 「目前章節」的使用者可見處都來自同一個函式 `reader_screen.dart` 的 `_currentEpubTocPath()`：目錄面板高亮與展開、頁首章名（`.first`，頂層章）、書籤預設名稱與劃線筆記章名（`.last`）。所以只改判定來源，這幾處一起正確。
- `view.js` 的 `#onRelocate` 以 relocate 的 `index`、`range` 呼叫 `TOCProgress.getProgress(index, range)`（`progress.js:42`）：逐一檢查該 spine 內目錄錨點，回傳「最後一個仍落在 range 內或之前的目錄項」。雙欄時 range 涵蓋兩欄，等於取右欄最後一個（Issue 20 報告已更正：原先誤以為是左欄）。
- `view.getProgressOf(index, range)`（`view.js` 約第 575 行）是公開方法，回傳 `{ tocItem, pageItem }`；`main.js` 目前在 relocate 處理（約第 1419～1445 行）用 `e.detail.tocItem?.id` 填 `tocItemId`。
- （歷史）規則 A 的行為：把 range 收成起點（`cloneRange()` 後 `collapse(true)`）再呼叫 `getProgressOf`，回傳「起點之前最後一個目錄項」。已因 2 個回歸捨棄，改採規則 B（見上）。
- **欄數：** `paginator.js` 裡 `View` 類別的 `#columnCount` 是私有欄位，但 paginator 元素本身（`view.renderer`）有**公開屬性 `columnCount`**（`paginator.js:2348` 捲動／單欄時設 1、`:2366` 設為依寬度算出的欄數），`main.js` 可直接讀 `view.renderer?.columnCount`。（先前計畫誤寫成「沒有公開讀取方法」，已更正。）它代表版面欄數，**不保證等於「目前畫面上實際有內容的欄數」**（例如章節尾頁只有一欄有內容時），要在 Task 1 驗證。
- **relocate 事件沒有頂層 `index`：** `view.js` 的 `#onRelocate` 把 `index` 傳給 `SectionProgress.getProgress`，產出的 `e.detail` 只含 `fraction`、`section: { current, total }`、`location`、`time`、`tocItem`、`pageItem`、`cfi`、`range`；`main.js` 現有程式用 `chapterIndex = section?.current ?? 0`。呼叫 `getProgressOf` 要用它，不是 `e.detail.index`（那會是 `undefined`，`TOCProgress.getProgress` 會回 `null`）。
- Issue 20 診斷過：雙欄跳轉會連續回報兩次（第二次約 260 ms 後，補欄完成），規則在兩次回報上都必須穩定。

## Tasks
- [x] **Task 1：診斷（拋棄式，不進 commit）。** 用 `foliate_touch_harness`（Puppeteer；Windows 上先 `export PATH="$PNPM_HOME:$PATH"`）載入 `app/test/fixtures/sample_multi_chapter.epub`（及需要時其他既有 fixture），雙欄視窗（約 1280x800）逐頁翻頁，記錄每次 relocate 的 `section.current`、`range` 起迄、`tocItem` 與「起點版 `getProgressOf` 的結果」，找出一頁雙欄**橫跨章節交界**的位置，重現「現行判定標成右欄章節」。同時**決定雙欄偵測方式**（不動 vendor），候選依序：(c) 讀 `view.renderer?.columnCount`（公開屬性、零開銷，**優先量**，要確認單欄／雙欄／直排下值是否符合預期，以及章節尾頁只有一欄有內容時的值）；(a) 比較 range 起點與終點的 client rect 是否落在不同欄（會觸發強制排版）；(b) 讀 iframe 文件 `documentElement` 的 `column-width`／`column-gap` 與可視寬度推算。**量出結果後回報人類選擇再實作。**
- [x] **Task 2：先寫會失敗的測試。** harness 新增 `app/tool/foliate_touch_harness/scenario-dual-column-toc-item.mjs`，fixture `sample_single_spine_multi_anchor.epub`。**預期值不手寫**：以獨立的 DOM 座標當標準答案（標題 `h2#s1／s2／s3` 各對應目錄 id 1／2／3，開頭到 s1 之前為 0；第一欄邊界＝`renderer.start + size / columnCount`，座標小於邊界的標題中最後一個），逐頁比對 relocate 回報的 `tocItemId`，並斷言「涵蓋 1、2、3」避免空轉；另加錨點跳轉（用目錄項真實 href）。案例：雙欄橫排 1280x800（7 頁）、雙欄直排 1280x800（6 頁）、單欄 400x800（13 頁）、強制單欄 1280x800（9 頁，單欄回歸防護）。修前舊規則雙欄 4 項失敗、單欄全過；規則 B 20 項全過。
- [x] **Task 3：實作（規則 B）。** `main.js` 新增 `firstColumnRange(view, range, columnCount)`（以 `renderer.start`／`size`／`columnCount` 算第一欄邊界，從 range 起點所在文字節點往後走，找最後一個字的起點座標小於邊界的位置，二分搜尋跨界節點；range 沒有任何行落在第二欄、水平 RTL、找不到文字或任何例外時回傳 null）與 `resolveFlowableTocItemId(view, detail)`（雙欄且切得出第一欄時呼叫 `view.getProgressOf(section.current, 第一欄 range)`；否則回退 `detail.tocItem`）。流式分支改用它；FXL／CBZ 分支、vendor、Dart 都不動；絕不拋出，避免中斷後面的 `onLocatorChanged` 回報。
- [x] **Task 4：Windows 整合測試。** `app/integration_test/epub_toc_test.dart` 新增桌面寬度（1280x800）一般翻頁案例：
  - **翻頁方式：** 用 `ReaderScreen.triggerZoneAction(readerKey, ZoneAction.nextPage)`（`foliate_cbz_test.dart` 已有範例，用 `GlobalKey<State<ReaderScreen>>`）；**不要點螢幕中央熱區**（會喚出工具列、中斷沉浸模式）。每次翻頁後等排版沉澱／位置回報穩定（雙欄補欄會連續回報兩次，約 260 ms）。
  - **頁首章名斷言（審查 I-2）：** 頁首章名（`Key('reader_foliate_header_text')`）只在 `showHeader` 為真且工具列隱藏（`!_chromeVisible`）時顯示；開著目錄面板時看不到。所以測試書籍要先把 `showHeader` 設為 true（經 `prefsManager`），翻到章節交界後**先**斷言頁首章名文字等於起點所在章，**之後**才用 `_openToc(tester)`（Issue 21 的檔案級輔助函式，不得退回只看 `onPressed`）斷言目錄面板的目前章節與高亮。
  - **回歸防護：** 原 400x800 手機版案例、Issue 20 的目錄跳轉案例，以及 Test 3（`sample_single_spine_multi_anchor.epub` 單 spine 多錨點）必須仍通過。
- [x] **Task 5：驗證。** harness 全套：`cd app/tool/foliate_touch_harness && node run-all.mjs`（需先 `export PATH="$PNPM_HOME:$PATH"`；已知 `scenario-cross-mechanism-tap-boundary` 偶發失敗見 Issue 26，不算回歸，須註明）；在 `app/` 下 `node tool/check_foliate_es_compat.js`、`node tool/check_integration_keys.js`、`node tool/check_l10n_hardcoded_strings.js`；`epub_toc_test` 在 Windows 單檔連跑多次；BooksPad 橫向：若實際顯示雙欄就跑同一組檢查（沿用 Issue 21 的 Android 實機規矩：螢幕常亮、`adb install -r`、絕不 `flutter install`、跑完還原一般 debug APK 與 `stay_on_while_plugged_in 0`、檔間停 Gradle daemon），否則寫明未驗證。`flutter analyze`；整份完成才跑全套 `flutter test`。
- [x] **Task 6：報告與收尾。** 寫 `issue-24-report.md`：重現證據、偵測方式選擇與依據、修法、各環境驗證結果與限制、書籤／劃線／搜尋跳轉的觀察記錄；更新 `issues.md` 第 24 列；更新 Issue 20 報告「已知限制」中對應的註記。

## 過關條件
1. 雙欄一般翻頁時，目前章節是第一欄範圍內最後一個目錄項（有 harness 獨立座標標準答案、Windows 整合測試，修前失敗、修後通過）；開書第一頁與單欄一致（`epub_toc_test`「開書位於第一節」、`foliate_toc_footer_test` 不得回歸）。
2. 單欄行為不變（harness 單欄案例、原 400x800 `epub_toc_test`、既有 harness 場景皆通過）。
3. 目錄跳轉行為不變（Issue 20 的桌面寬度跳轉案例仍通過）。
4. 直排（vertical-rl）下規則正確（harness 直排案例）。
5. 未改釘定 vendor 與 Dart 契約；`check_foliate_es_compat.js` 乾淨；`flutter analyze` 乾淨。
6. 報告誠實記載驗證環境與限制（Android 橫向平板是否驗證、書籤／劃線／搜尋跳轉未處理）。

## Review Focus
1. **單欄不得被誤判成雙欄：** 單欄一頁內有多個目錄錨點時，必須仍回傳「最後一個」；雙欄偵測的誤判會悄悄改變手機行為。要有針對單欄多錨點頁的測試。
2. **補欄的兩次回報都要穩定：** 目錄跳轉後第二次回報（補欄後）不得讓 `TocJumpOverride` 的判斷失靈；Issue 20 的跳轉案例必須仍通過。
3. **第一欄切不出或沒有目錄錨點：** `firstColumnRange` 回傳 null（range 沒跨到第二欄、水平 RTL、找不到文字、例外）時必須回退現行判定；`getProgressOf` 回傳前一區段的項目（`prev`）或 `null`／`undefined` 時，`null` 的行為不得比現行更差；`section.current` 不是數字、`range` 為空或操作 range 丟例外時，也必須回退而不是讓後面的 `onLocatorChanged` 回報中斷（否則進度追蹤整個凍結）。
4. **直排與 RTL：** 直排雙欄是沿垂直方向的上下兩欄，座標軸用 `top`（橫排用 `left`），harness 已有直排案例；水平 RTL 書（阿拉伯文等，非本專案主要目標）第一欄在右側，座標判斷相反，程式碼退回現行判定，報告要註明未處理。
5. **範圍邊界：** 只動流式分支；FXL／CBZ 分支（`view.isFixedLayout`）維持原樣；不動 `locatorJson`（會持久化並跨裝置同步），只動第 2 參數 position 內的 `tocItemId`。
6. **效能：** relocate 頻繁，額外一次 `getProgressOf`（內含 DOM 查詢）要確認不造成翻頁卡頓（至少在 harness 量測前後耗時）。
7. **同一來源的其他呈現：** 頁首章名、書籤預設名稱、筆記章名會隨之改變；要實際看到至少頁首章名在雙欄交界翻頁時符合新規則，而不只驗目錄面板。
8. **跳轉類的觀察不得變成承諾：** 書籤／劃線／搜尋跳轉只記錄，報告不得宣稱已修或已驗證沒問題。

## 待人類確認
1. Task 1 的雙欄偵測方式要等診斷後由你選（優先量公開屬性 `view.renderer.columnCount`），計畫是否同意這個順序（先診斷、回報、再實作）？
2. BooksPad 橫向是否顯示雙欄尚未知；若顯示，Task 5 會佔用平板約 30～60 分鐘（比照 Issue 21 的流程），是否同意？
