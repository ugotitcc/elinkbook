# Epic 19 — 書架與閱讀體驗強化（全螢幕模式/刪除書籍/分類拼貼）：Discovery

## 背景

2026-07-28，使用者提出 3 項新需求：① 閱讀畫面的全螢幕選項（隱藏系統狀態列/導覽列）、② 刪除書籍與分類的功能、③ 書架分類顯示方式改為內嵌書籍清單的 2×2 拼貼格、取消現有分類 Chip 列。三項皆為**新功能**，不屬於任何既有 Epic 的既定範圍——`epic-18-reader-device-qa` 明確定位是「既有功能的真機 UI 缺陷與精修」，不適用；比照 `docs/epics.md`「任務分類」既有慣例（新功能/重構 → 建立新 Epic），另立本 Epic 統一追蹤。三項雖分屬閱讀體驗（①）與圖書庫管理（②③）兩個面向，但同一批討論、彼此無強相依，經人類確認合併為同一個 Epic（`/grill-with-docs` Discovery session 逐項釐清，見下方）。

## 使用者提出的 3 項需求（原文摘要）

1. 提供全螢幕閱讀選項——開啟此選項時，不留 topbar 與 bottom bar（上下工具列或狀態列）。
2. 提供刪除書籍、分類的功能。
3. 分類顯示應直接內嵌於書籍清單中，一個分類佔一格、格內以 2×2 拼貼顯示該分類前 4 本書封面；同時取消現有分類列的顯示（分類已同步顯示在書架畫面本身）。

## 調查結論（Discovery 階段查證的關鍵事實）

- **全螢幕（①）**：`reader_screen.dart:156` 已有 `_chromeVisible`（`CONTEXT.md` 稱「沉浸模式」），由九宮格中央「選單」熱區觸發，僅隱藏 App 自己的 AppBar/Footer/FXL 懸浮按鈕，**從未真正隱藏 Android 系統狀態列/導覽列**（全專案 grep 不到 `SystemChrome.setEnabledSystemUIMode`/`SystemUiMode` 任何用法）。PRD FR-42「固定版面全螢幕顯示開關」是另一個範圍更窄（僅 FXL）、尚未開工的獨立設定項（`epic-14-system-settings`）。三種排版格式（EPUB 流式/PDF/FXL）分屬三個獨立的每本書設定面板：`reader_settings_sheet.dart`、`pdf_settings_sheet.dart`、`fxl_settings_sheet.dart`；後兩者目前分別只有 `showFooter`、完全沒有 header/footer 欄位（FXL 用懸浮按鈕，非頁首/頁尾列）。
- **刪除書籍/分類（②）**：`LibraryRepository.deleteBook()`（`library_repository.dart:10`，實作於 `sqlite_library_repository.dart:459`）早已存在，但**全專案沒有任何 UI 呼叫它**——使用者目前完全無法從畫面上刪除書籍。反之「刪除分類」（`deleteGroup`）已有完整 UI（`library_group_management_dialog.dart`，經「管理分類」進入），此次不用重做。資料庫層 `book_reader_prefs`/`bookmarks`/`highlights`/`notes` 皆已對 `books` 設定 `ON DELETE CASCADE`（`sqlite_library_repository.dart:192,296,313,332`），刪除書籍列會自動級聯清除，不需額外寫級聯邏輯。`books` 表的 `filePath`（`sqlite_library_repository.dart:49`）**不一定**是 App 私有複本——只有在持久化 URI 權限授權失敗、或原始 URI 沒有可辨識副檔名時（`book_import_service_impl.dart:190-194`），才會呼叫 `_copyToLocalStorage()` 落地成本機複本；其餘常見情況下 `filePath` 維持原始 `content://` URI（指向使用者原始檔案位置，非複本）。`coverPath`（`sqlite_library_repository.dart:51`）不受影響，永遠是 `_landCover()` 產生的本機複本（`book_import_service_impl.dart:207,225`）。刪除書籍時，只要沿用既有的 `File(path).existsSync()` 防護模式（`_BookCover` widget 已有此模式）判斷才刪除，`content://` 字串永遠不會被 `dart:io File` 判定為存在的本機路徑——這個防護對兩種 `filePath` 來源都安全：本機複本會被正確刪除回收空間，`content://` 參照會被安全跳過、不觸碰使用者原始檔案，實作端不需要額外分辨是哪一種來源。`library_screen.dart` 已有長按進入的批次選取模式（`_selectedBookIds`、`_inSelectionMode`），選取工具列（`_buildSelectionAppBar()`）目前僅有「移動到分類」一顆動作。
- **分類拼貼格（③）**：`main.dart:119` 的 `MaterialApp.home` 直接指向 `LibraryScreen`——**全 App 只有這一個書架/主畫面**，沒有獨立的 home screen；使用者所稱「主畫面」即書架畫面本身。現有分類顯示是 `_buildGroupTabs()`（`library_screen.dart:520-562`）：水平捲動的 `ChoiceChip` 列（含「全部」與「管理分類」`ActionChip`），身兼「顯示分類」與「點擊篩選」兩個功能，渲染於書籍格狀/列表清單上方，與書籍清單本身的 `GridView.builder`（`crossAxisCount` 3/4，`_buildBookList`）是兩個獨立元件。`LibraryRepository.listGroups()` 已依 `name ASC` 排序（`sqlite_library_repository.dart:492`），`listBooks({groupFilter})` 已支援依分類篩選查詢。

## 決策（人類已確認，`/grill-with-docs` 逐項釐清）

### ① 全螢幕模式

1. 獨立於「沉浸模式」的全新開關，語意完全分離、互不干涉。
2. 只控制 Android 系統狀態列＋導覽列（`SystemUiMode.immersiveSticky` 或等效 API），與 App 自己的 AppBar/Footer/頁首/頁尾/懸浮按鈕完全脫鉤——後者永遠只受既有的「沉浸模式」與 `showHeader`/`showFooter` 控制，全螢幕模式開啟與否不改變它們的行為。
3. 進入點：加進三個既有的每本書排版設定面板（`reader_settings_sheet.dart`／`pdf_settings_sheet.dart`／`fxl_settings_sheet.dart`），三種格式（EPUB 流式/PDF/FXL）皆要有。
4. 持久化：存成 `BookReaderPrefs` 的新欄位，逐本記憶，比照 `showHeader`/`showFooter` 既有機制（無全域預設層）。
5. 離開 `ReaderScreen`（`dispose()`）時強制還原系統列為正常顯示，不依賴使用者手動關閉開關。

### ② 刪除書籍（刪除分類已存在，不在本 Epic 範圍）

1. 「刪除分類」已有完整 UI，此次不動；範圍收斂為只新增「刪除書籍」。
2. 入口：統一走既有長按進入的選取模式，選取工具列新增「刪除」按鈕（與既有「移動到分類」並列），可對已勾選的 1 本或多本書執行；不新增其他手勢（不做 swipe-to-delete、不做單本快速刪除）。
3. 刪除前彈出確認對話框，明確提示「將一併刪除已勾選書籍的書籤、劃線與備註，此操作無法復原」。
4. 實作內容：刪除 `books` 資料列（`book_reader_prefs`/`bookmarks`/`highlights`/`notes` 既有 `ON DELETE CASCADE` 自動連動清除），並對 `filePath`＋`coverPath` 各自呼叫 `File(path).existsSync()` 判斷後才刪除（見上方調查結論——`content://` 來源的 `filePath` 會被安全跳過，不需分辨來源）。

### ③ 分類 2×2 拼貼格，取消現有分類 Chip 列

1. 現有水平分類 Chip 列（`_buildGroupTabs()`）整個移除，**不放搜尋 BAR 或任何替代物**——書名/作者關鍵字搜尋整個延後到獨立的 `epic-10-search`（全文檢索），本 Epic 不做。
2. 每個分類顯示成一格：2×2 拼貼該分類前 4 本書封面＋下方顯示「分類名稱＋書籍總數」；書量不足 4 本時，其餘格子顯示空白佔位（不拉伸/不重複既有封面）。
3. 分類格固定排在書籍清單「最前面」，書籍維持原排序邏輯（最後閱讀/建立時間/作者/書名）排在分類格之後；分類格順序沿用既有 `listGroups()` 的 `name ASC`，但「未分類」固定排最後一格，且只有非空才顯示。
4. 格狀檢視／列表檢視都要顯示分類格；列表檢視改用「橫向 4 張小縮圖＋名稱＋數量」的列表列樣式，不強行塞入方形拼貼。
5. 點擊拼貼格 → 重用既有 `LibraryScreen`（新增可選建構參數 `groupFilter`），該狀態下不顯示分類拼貼格區塊、AppBar 顯示分類名稱＋返回鍵，排序/檢視模式切換/長按多選/刪除（見②）等既有功能原樣沿用。
6. 分類格排除在既有長按多選機制之外（不能被勾選、不參與批次刪除/移動——批次動作僅適用於書籍項目）。
7. 「管理分類」入口搬到書架畫面 AppBar 的選單/圖示按鈕，開啟同一既有對話框，功能不變。

## 範圍界定

- 不做 `epic-10-search`（書名/作者/書內全文檢索）——搜尋 BAR 需求整個延後，統一併入該 Epic 立案時處理。
- 不修改既有「刪除分類」（`deleteGroup`／`library_group_management_dialog.dart`）流程本身。
- 不修改 FXL／`EpubReaderView`／Readium 的 `pageMargins` 傳遞路徑或既有版面設定邏輯（與本 Epic ①③ 皆無關）。
- 全螢幕模式（①）不影響、不覆寫 `_chromeVisible`（沉浸模式）與 `showHeader`/`showFooter` 既有語意，三套機制各自獨立疊加。
- 分類拼貼格（③）不新增分類本身的長按操作選單（改名/刪除分類仍統一走「管理分類」對話框，不在拼貼格上做快捷操作）。

## 詞彙紀錄（已寫入 `CONTEXT.md`）

新增「全螢幕模式（Fullscreen Mode）」詞條，與既有「沉浸模式（Immersive Mode）」詞條互相參照、明確區分兩者範圍差異（見 `CONTEXT.md` 對應段落）。

## ADR

三項功能皆未同時滿足「難以回頭＋沒有前情提要會很意外＋真正的權衡取捨」三個門檻（比照 `epic-18-reader-device-qa` 既有判斷慣例），故不另開 ADR。

**【後續更新，撰寫 `plan-issue-1.md` 前發現】**：全螢幕模式的系統列隱藏機制，原規劃的純 Dart `SystemChrome.setEnabledSystemUIMode()` 經查證在本專案目前的 `targetSdk`（36，Flutter SDK 3.41.9 預設值）下確認無效（Flutter 官方文件明載 API 36+ 一律強制 `edgeToEdge`、無退出方法）。改採原生 `WindowInsetsControllerCompat` 方案，此變動符合三個門檻（難以回頭：需新增原生 Kotlin 程式碼；意外：表面上應該用 Flutter 內建 API 卻改用原生方案；真權衡：曾考慮調降全專案 `targetSdk` 但影響範圍過大而排除），已新增 **ADR 0015**（`docs/adr/0015-fullscreen-native-window-insets-controller.md`），詳見 `spec.md`「功能 ① 全螢幕模式」。

## 後續

依 SDD 流程進入 Architecting 階段——若確認上述決策無架構層級異動需要記錄，直接撰寫 `spec.md` 定義三項功能的核心介面/型別，再由 Scrum Master 階段拆解為 `issues.md` 的細粒度工單。
