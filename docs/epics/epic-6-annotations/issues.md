# Epic 6 — 註記與知識管理：工單清單 (Issues)

依 `spec.md`（搭配 `design.md`、`/grill-with-docs` Discovery + `/superpowers:requesting-code-review` 審查修正，另見 [ADR 0008](../../adr/0008-pdf-annotation-long-press-gesture.md)）拆解出的細粒度垂直切片工單。Issue 1（書籤 + 統一筆記入口）可立即開始；Issue 2（EPUB 劃線與備註）依賴 Issue 1；Issue 3（PDF 劃線與備註）依賴 Issue 2；Issue 4（FXL 書籤支援）依賴 Issue 1；Issue 5（Markdown 導出）依賴 Issue 1、Issue 2。

---

## Issue 1：書籤管理 + 統一「筆記」入口（Bottom Sheet 外殼）

**Status:** ✅ 已完成並合併（PR #49，`feat/epic6-issue1-bookmarks-notes-entry` → `main`）——依 `plans/plan-issue-1.md` 8 個 Task 實作：`bookmarks` 表與累加式 v7→v8 schema migration（`onCreate`／`onUpgrade` 皆呼叫 `_createBookmarksTable`）、`BookmarksRepository`（CRUD，`COALESCE(pdf_page_index, progression)` 跨格式排序）、`Bookmark`／`BookmarkPositionContext`／`defaultName` 純函式（EPUB 用章節名稱＋進度百分比、PDF 用「第 N 頁」、FXL 因副檔名是 `.epub` 且無法取頁碼而退回進度百分比）、`NotesBottomSheet`（雙分頁籤外殼，「🔖 書籤」完整可用＋「✏️ 劃線與備註」空狀態佔位符）、書籤 toggle／重新命名／單筆刪除／批次刪除（確認對話框）、`ReaderScreen` 接線「📚 筆記」AppBar 入口，`bookmarksRepository` 以可選具名參數貫穿 `LibraryScreen`／`main.dart`，零回歸（既有 43＋27＋5 處呼叫端不受影響）。經 8 個 Task 逐一審查（僅 Task 7 有 2 項 ⚠️ 由 controller 自行釐清，非缺陷）與最終整體分支審查（Important：EPUB 📚 筆記按鈕加上 `_epubPositionInfo` 就緒判斷，避免 `onLayoutResolved`／`onLocatorChanged` 兩條獨立非同步回呼順序不保證時寫入無定位資訊的壞書籤，比照既有 `_tocLoaded` 防呆模式；Minor：`NotesBottomSheet` 的 `TextEditingController` 洩漏，改由 State 生命週期管理）一輪修正；`flutter test`（全專案 386 個）全過、`flutter analyze` 乾淨。**真機整合測試（`integration_test/notes_bookmark_test.dart`，涵蓋 EPUB／PDF）已撰寫但尚未於實機執行**——因合併當下無 Android 裝置可用，Step 2（`-d <device-id>` 真機執行）延後，待裝置就緒後補做。

**依賴：** 無（起始工單）

**What to build：**

新增 `bookmarks` 表（`book_id` 外鍵關聯至 `books`，比照 `book_reader_prefs` 既有關聯模式；欄位含定位資訊〔EPUB：CFI；PDF/FXL：頁碼〕、名稱）與累加式 schema migration（`sqlite_library_repository.dart` 版本遞增，`if (oldVersion < N)` 慣例），以及對應的 `BookmarksRepository`（比照既有 `BookReaderPrefsRepository`／`ReadingPositionRepository` 模式，含新增/查詢/重新命名/單筆刪除/批次刪除全部）。**全新安裝防禦（審查修正，見 `tmp/epic-6/reviews/issues_review.md` 1.1）**：`bookmarks` 是全新的表（非既有表新增欄位），須比照 `book_reader_prefs` 表當初新增時的既有慣例——新增一個 `_createBookmarksTable(db)` 共用建表函式，`onCreate` 與 `onUpgrade` 的 `if (oldVersion < N)` 分支都必須呼叫它，確保全新安裝（走 `onCreate`）與既有裝置升級（走 `onUpgrade`）兩條路徑都會建立此表，否則全新安裝的裝置會在查詢書籤時拋出 `no such table` 例外。

`ReaderScreen` 為流式 EPUB／PDF 新增單一「📚 筆記」AppBar 按鈕（依格式動態顯示，沿用既有 `_buildAppBarActions(format)` 機制）。新建 `NotesBottomSheet`（暫名）：帶「🔖 書籤」／「✏️ 劃線與備註」兩分頁籤的 Bottom Sheet 外殼。本工單只完整實作「🔖 書籤」分頁——清單依書中位置順序排序（EPUB 用 `progression` 比例、PDF 用頁碼）、點選 200ms 內跳轉並關閉 Bottom Sheet、單筆重新命名（Dialog 輸入新名稱）、單筆刪除、批次「刪除該書所有書籤」（標準 `AlertDialog` 確認，顯示筆數）。「✏️ 劃線與備註」分頁本工單僅顯示空狀態佔位符（真正內容由 Issue 2 建立）。

書籤新增/移除的 toggle 入口**不**額外新增 AppBar 按鈕（避免 AppBar 過度擁擠，見 `design.md` 決策 #6），改為「🔖 書籤」分頁內部頂端一顆反映目前頁/位置書籤狀態的二態按鈕（例如「☆ 加入此頁書籤」／「★ 已加入此頁書籤（點擊移除）」），toggle 語意：同一頁/位置最多一筆。預設名稱：EPUB 用「目前章節名稱＋全書進度百分比」（例如「第二章 (35%)」，沿用 `epic-5-toc-pagination` 既有的 `TocNavigator` 目前章節判定邏輯，避免同章節多筆書籤預設名稱無法辨識），PDF 用「第 N 頁」。**位置上下文傳遞（審查修正，見 `tmp/epic-6/reviews/issues_review.md` 1.2）**：`ReaderScreen` 開啟 `NotesBottomSheet` 時，須把目前定位資訊（EPUB：CFI／PDF：頁碼）、目前章節名稱（`TocNavigator.findCurrentPath()` 算出，EPUB 適用）與全書進度百分比一併傳入，供二態按鈕判斷目前頁/位置是否已有書籤、以及新增書籤時計算預設名稱。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - `bookmarks` 表 schema migration：全新安裝（`onCreate` 路徑）與既有裝置跳級升級（`onUpgrade` 路徑）皆須個別驗證表格存在、既有資料不受影響，比照既有 `sqlite_library_repository_test.dart` 的既有先例撰寫（審查修正 1.1）。
  - `BookmarksRepository` CRUD：新增、依 `book_id` 查詢、依位置排序、重新命名、單筆刪除、批次刪除全部。
  - `NotesBottomSheet` 開啟／關閉、兩分頁籤切換。
  - 「🔖 書籤」分頁：清單正確顯示（含排序）、點選項目觸發跳轉呼叫並關閉 Bottom Sheet、重新命名對話框正確更新清單、單筆刪除即時生效。
  - 書籤 toggle 按鈕二態顯示正確反映目前頁/位置是否已有書籤；點擊後正確新增/移除。
  - 批次刪除確認對話框：顯示正確筆數、取消不刪除、確認後清單清空。
  - 「✏️ 劃線與備註」分頁顯示空狀態佔位符（本工單尚未實作真正內容）。
  - PDF 格式下「📚 筆記」按鈕行為與 EPUB 一致（書籤模組本身格式無關）。
- integration_test（真機）：開啟 EPUB／PDF 各一本，新增書籤、從清單點選後驗證 200ms 內確實跳轉至正確位置。

**驗收標準：**

- [x] `bookmarks` 表與累加式 migration 正確建立：`onCreate`（全新安裝）與 `onUpgrade`（既有裝置升級）皆會建表，兩條路徑皆不拋出 `no such table`
- [x] `BookmarksRepository` CRUD 正確運作
- [x] AppBar 新增「📚 筆記」按鈕（流式 EPUB／PDF），開啟帶兩分頁籤的 Bottom Sheet
- [x] 「🔖 書籤」分頁完整可用：清單依位置排序、200ms 內跳轉、重新命名、單筆刪除、批次刪除（需確認）
- [x] 書籤新增/移除為 toggle 語意，同頁/位置最多一筆，二態按鈕正確反映狀態
- [x] EPUB 預設書籤名稱含章節名稱＋進度百分比；PDF 預設名稱為「第 N 頁」
- [x] 「✏️ 劃線與備註」分頁顯示空狀態佔位符
- [x] 上述測試皆通過，`flutter analyze` 乾淨
- [ ] 真機整合測試涵蓋 EPUB／PDF 書籤新增與跳轉的端到端流程（測試檔已撰寫，尚待裝置就緒後實際執行）

**Blocked by：** None - can start immediately

---

## Issue 2：EPUB 劃線與備註

**Status:** ready-for-agent

**依賴：** Issue 1（「✏️ 劃線與備註」分頁的 Bottom Sheet 外殼已存在，本工單填入真正內容）

**What to build：**

新增 `highlights` 表（`book_id` 外鍵、樣式〔螢光筆/底線〕、顏色、選取範圍定位資訊）與 `notes` 表（`book_id` 外鍵、自由文字內容、選取範圍定位資訊、可為空的 `highlight_id` 欄位 `REFERENCES highlights(id) ON DELETE SET NULL`），累加式 schema migration（先建 `highlights` 再建 `notes`，見 `spec.md`「資料模型關聯」）。`PRAGMA foreign_keys = ON` 已於既有 `onConfigure` 設定、對新表自動生效，不需額外宣告。新增對應的 `HighlightsRepository`／`NotesRepository`。

`EpubReaderView.kt`／`.dart` 新增：原生 WebView 選字手勢觸發後，回報選取範圍資訊給 Dart 端，浮出浮動工具列（螢光筆黃/粉/藍、底線、備註四個按鈕）；建立劃線時透過 Readium Decorator API 疊加對應視覺樣式；建立純備註（無劃線）時疊加固定樣式（淡灰底＋行內小圖示）。

`NotesBottomSheet` 的「✏️ 劃線與備註」分頁正式生效（EPUB 適用）：依書中位置順序排序，同一選取範圍的劃線+備註合併顯示成一筆（同時顯示劃線樣式與備註摘要），點選 200ms 內跳轉。單筆刪除（劃線+備註一併刪除）；編輯備註文字獨立入口。批次「刪除該書所有劃線」／「刪除該書所有備註」各自獨立（皆需確認對話框）——批次刪除劃線後，原本依附的備註若仍有內容，因 `highlight_id` 外鍵 `ON DELETE SET NULL` 自動退化為 `highlight_id = null`，UI 據此自動改套用純備註畫面指示，不需額外應用層判斷邏輯。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - `highlights`／`notes` 表 schema migration（全新安裝、既有裝置跳級升級皆驗證，含 `highlight_id` 外鍵欄位正確存在）。
  - `HighlightsRepository`／`NotesRepository` CRUD。
  - **FK 退化行為**：建立一筆劃線+備註，批次刪除全部劃線後，直接查詢資料庫確認該筆備註的 `highlight_id` 確實變為 `null`、備註內容本身未被刪除。
  - 側邊欄清單合併顯示的純函式邏輯：給定 `highlights`＋`notes` 清單，依位置排序並正確合併同範圍項目成一筆；`highlight_id IS NULL` 正確判斷為純備註。
  - 「✏️ 劃線與備註」分頁：清單顯示（含排序、合併顯示）、點選跳轉、編輯備註文字、單筆刪除（劃線+備註一併刪除）。
  - 批次刪除確認對話框（劃線／備註各自獨立）：顯示正確筆數、取消不刪除、確認後對應項目消失、另一類型不受影響。
- integration_test（真機）：
  - 開啟含真實可選取內容的 EPUB，驗證原生選字手勢確實觸發浮動工具列。
  - 分別建立螢光筆（三色各一次）、底線、純備註，驗證 Decorator 疊加視覺樣式與資料庫寫入一致。
  - 驗證直排/橫排切換後，既有劃線視覺仍正確跟隨文字位置（`design.md` 已知風險的基本可用性驗證，非像素級保證）。

**驗收標準：**

- [ ] `highlights`／`notes` 表與累加式 migration 正確建立（含 `highlight_id` FK）
- [ ] EPUB 原生選字手勢正確觸發浮動工具列（螢光筆三色、底線、備註）
- [ ] 劃線與備註可獨立建立，純備註有固定樣式的畫面指示
- [ ] 批次刪除劃線後，依附備註正確退化為純備註（FK `ON DELETE SET NULL` 驗證）
- [ ] 「✏️ 劃線與備註」分頁完整可用：合併顯示、依位置排序、200ms 內跳轉、編輯備註、單筆刪除、批次刪除（劃線/備註各自獨立，需確認）
- [ ] 直排/橫排切換下劃線視覺基本一致（真機驗證）
- [ ] 上述測試皆通過，`flutter analyze` 乾淨
- [ ] 真機整合測試涵蓋 EPUB 選字建立劃線/備註、視覺渲染、直橫排切換的端到端流程

**Blocked by：** Issue 1

---

## Issue 3：PDF 劃線與備註

**Status:** ✅ 已完成，待合併（分支 `worktree-epic6-issue3-pdf-highlights`，尚未合併回 `main`）——依 `plans/plan-issue-3.md` 11 個 Task 以 Subagent-Driven Development 實作：長按拖曳框選手勢改由 Flutter 端 `GestureDetector`（`onLongPressStart`／`onLongPressMoveUpdate`／`onLongPressEnd`，與既有 `onHorizontalDragEnd` 共用同一手勢競技場）主導辨識，原生端 `PdfReaderView.kt` 僅被動接收 `beginAnnotationSelection`／`updateAnnotationSelection`／`endAnnotationSelection`／`cancelAnnotationSelection` 四個 method call（此為審查修正，原設計由原生端無條件攔截 `ACTION_DOWN` 會讓既有滑動翻頁手勢失效，見 `plan-issue-3.md` Global Constraints）；`highlights`／`notes` 表新增 PDF 欄位並完成 v9→v10 schema migration（if/else 互斥、避免跳版升級時 duplicate column 例外）；`HighlightSelectionOverlayView`／`computeFitCenterContentBounds` 共用座標數學；`refreshAnnotations()` 原生端 Bitmap 疊加渲染（螢光筆/底線依 `scale` 而非畫面 DP 密度縮放，純備註改用手繪黑白向量圖釘取代系統 Emoji，E-Ink 對比度考量）；`ReaderScreen`／`NotesBottomSheet` 完整接上 PDF 分支，複用 Issue 2 邏輯零回歸。11 個 Task 逐一經 task-scoped 審查（3 個 Task 由實作者發現並修正計劃書本身的真實錯誤——FIT_CENTER 測試期望值算式、Kotlin 可見性洩漏、跨 Task 型別前向參照——皆經 controller 獨立驗證後回頭修正 `plan-issue-3.md`），加上最終全分支審查（發現 1 項 Important：PDF 浮動工具列在 letterbox 情境下座標基準誤用整個 widget 尺寸而非內容範圍，導致定位偏移，已新增 `widgetRect` 欄位修正並複審通過）。`flutter test`（全專案 466 個）全過、`flutter analyze` 乾淨、Kotlin JVM 測試（73 個）全過、`flutter build apk --debug` 建置成功。**真機驗證現況**：`integration_test/pdf_highlights_notes_test.dart`（repository 驅動的端到端流程——清單顯示、跳轉、單筆刪除）已於真機（Android 15 / API 35）實際執行並通過；原生長按框選手勢本身觸發、與既有滑動翻頁/雙頁縮放平移手勢的優先權、Bitmap 疊加視覺渲染、多指取消、裝置旋轉/裁切後座標基準，這 5 類項目屬於 Flutter `integration_test` 無法模擬 `PlatformView` 內部觸控事件的已知限制，仍待人工於真機操作逐項驗證（詳見該測試檔案開頭的「真機人工驗證清單」7 項）。**待人工決定**：分支尚未合併/推送，需人工決定合併方式（本地合併／推送建 PR／維持現狀）。

**依賴：** Issue 2（複用 Dart 端資料模型／Repository／Bottom Sheet 清單 UI，本工單只新增 PDF 專屬的原生框選建立路徑）

**What to build：**

`PdfReaderView.kt` 新增長按頁面直接觸發拖曳框選矩形手勢（見 [ADR 0008](../../adr/0008-pdf-annotation-long-press-gesture.md)），矩形繪製元件沿用/延伸 `epic-4-pdf-enhance` 的 `CropOverlayView.kt`。選取完成後，座標須相對於 `computeContentBounds()` 既有的 letterbox-aware 頁面內容範圍換算成百分比值（**不是**相對於整個原生 View 容器寬高，見 `spec.md` 審查修正），透過 method channel 回傳給 Dart 端；Dart 端以 `Overlay` 將浮動工具列定位於選取矩形上方（與 Issue 2 的 EPUB 浮動工具列共用同一組 Widget）。框選進行中若使用者縮放或平移畫面，直接取消目前選取狀態、收起浮動工具列。**觸發時機（審查修正，見 `tmp/epic-6/reviews/issues_review.md` 1.3）**：原生端須在偵測到多指觸控事件（`event.pointerCount > 1`，代表縮放或平移手勢開始）、或收到來自 Method Channel 的翻頁/跳頁指令（`nextPage`／`previousPage`／`jumpToPage`）時，主動取消目前框選狀態，並透過 method channel 回報 Dart 端關閉浮動工具列。

劃線/備註疊加渲染於 PDF 頁面 Bitmap 之上（螢光筆三色、底線、純備註三種樣式，視覺對應 Issue 2 已定義的樣式規則）。新增 `refreshAnnotations()` method channel 指令：Dart 端完成劃線/備註的新增/編輯/刪除後主動呼叫，通知原生端重新讀取目前頁面的標記資料並重繪 Bitmap 快取。

PDF 書籍開啟「✏️ 劃線與備註」分頁時，資料層與 UI 完全複用 Issue 2 已建立的清單/合併顯示/批次刪除邏輯，不需另外開發。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - 模擬原生端透過 method channel 回傳框選座標事件後，Dart 端正確觸發浮動工具列並定位。
  - 座標換算純函式（給定 `computeContentBounds` 對應的內容範圍與原始百分比座標，正確換算回目前 View 座標系）。
- integration_test（真機）：
  - 開啟 PDF，驗證長按頁面確實觸發拖曳框選矩形手勢，且不與既有九宮格熱區（單擊翻頁）、雙頁模式下的縮放/平移手勢互相誤觸發（手勢競技場驗證，`design.md` 已知風險）。
  - 框選進行中執行縮放/平移，驗證選取狀態正確取消、浮動工具列收起。
  - 建立劃線/備註後，驗證原生端 Bitmap 正確疊加渲染；刪除後驗證 `refreshAnnotations()` 確實觸發重繪、無殘留。
  - 裝置旋轉後，驗證既有劃線座標仍正確對應頁面實際內容（letterbox-aware 座標基準驗證）。

**驗收標準：**

- [ ] PDF 長按頁面直接觸發拖曳框選矩形手勢，不需先進入獨立模式（ADR 0008）——程式碼已實作（Flutter `GestureDetector` 長按辨識＋原生端狀態機），尚待真機人工驗證實際手勢觸發體感
- [ ] 框選座標相對頁面內容範圍（非整個 View）計算，裝置旋轉後仍正確——letterbox-aware 座標數學已實作並經 JVM 單元測試涵蓋，「裝置旋轉後仍正確」屬真機專屬驗證項目，尚待人工執行
- [ ] 框選中縮放/平移直接取消選取——Dart 端多指偵測邏輯已有 widget test 驗證（模擬真實雙指觸點），原生端接收與真實硬體多指手勢尚待真機人工驗證
- [ ] 劃線/備註正確疊加渲染於 PDF Bitmap，變更後原生端正確重繪（`refreshAnnotations()`）——資料解析與疊加繪製邏輯已實作並經 JVM 單元測試涵蓋，實際視覺渲染效果尚待真機人工驗證
- [ ] 長按框選與既有九宮格熱區/雙頁縮放平移手勢無衝突（真機驗證）——架構上已透過「手勢辨識完全交由 Flutter GestureDetector 主導、原生端不再攔截觸控」解決此風險（見 `plan-issue-3.md` Global Constraints 審查修正），但仍屬明確標註「真機驗證」的項目，尚待人工於真機操作確認
- [x] PDF 書籍的「✏️ 劃線與備註」分頁完整可用（複用 Issue 2 邏輯）——`integration_test/pdf_highlights_notes_test.dart` 已於真機（Android 15 / API 35）實際執行並通過，驗證合併清單顯示、跳轉、單筆刪除
- [x] 上述測試皆通過，`flutter analyze` 乾淨——`flutter test` 466/466、Kotlin JVM 測試 73/73、`flutter analyze` 乾淨、`flutter build apk --debug` 建置成功
- [ ] 真機整合測試涵蓋 PDF 長按框選建立劃線/備註、原生重繪、手勢優先權、裝置旋轉座標正確性的端到端流程——repository 驅動的端到端流程（清單顯示、跳轉、刪除）已於真機執行並通過；原生長按框選本身建立劃線/備註、手勢優先權、裝置旋轉座標正確性仍屬人工真機驗證清單範圍，尚待執行（見 `pdf_highlights_notes_test.dart` 檔案開頭「真機人工驗證清單」7 項）

**Blocked by：** Issue 2

---

## Issue 4：FXL（固定版面）書籤支援

**Status:** ready-for-agent

**依賴：** Issue 1（書籤資料模型與 Bottom Sheet 外殼已存在，本工單新增 FXL 專屬的懸浮入口）

**What to build：**

`ReaderScreen` 於 FXL 既有懸浮控制按鈕群組（左上返回鍵、右上設定鍵，`epic-16-dual-page` Issue 9 建立）之外，新增兩顆懸浮按鈕（皆為 `Positioned` + 半透明圓形按鈕樣式，跟隨相同的三欄熱區收合顯示/隱藏邏輯）：

1. 🔖 書籤 toggle 按鈕：快速新增/移除目前頁書籤，二態顯示，預設名稱為「第 N 頁」（無章節概念）。
2. 📚 筆記按鈕：開啟與非 FXL 相同的 `NotesBottomSheet`——「🔖 書籤」分頁功能完整（複用 Issue 1 邏輯），「✏️ 劃線與備註」分頁顯示空狀態且不可互動（FXL 不支援劃線/備註，Readium 對 FXL 無可選取文字層）。

**跳轉後控制面板收合（審查修正，見 `tmp/epic-6/reviews/issues_review.md` 1.4）**：於 FXL 情境下，從 Bottom Sheet 點選書籤跳轉成功後，除了關閉 Bottom Sheet，須比照既有 `onFixedLayoutPageTurn` 慣例（`epic-16-dual-page` Issue 9 建立：換頁一律強制收合懸浮控制項、非切換語意），把 `_fixedLayoutControlsVisible` 設為 `false`——書籤跳轉概念上等同換頁，套用同一套既有沉浸式閱讀慣例，不是另立新規則。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - FXL 開書後，畫面出現 🔖／📚 兩顆懸浮按鈕（連同既有返回鍵/設定鍵）。
  - 🔖 按鈕 toggle 行為與 Issue 1 的書籤邏輯一致（複用同一 Repository）。
  - 📚 按鈕開啟 Bottom Sheet，「書籤」分頁正常可用，「劃線與備註」分頁顯示空狀態且點選/互動皆無效果。
  - 三欄熱區收合顯示/隱藏時，新增的兩顆按鈕與既有按鈕行為一致（一併收合）。
  - 從書籤清單點選跳轉後，`_fixedLayoutControlsVisible` 正確變為 `false`，懸浮控制項收合。
  - 既有 FXL 相關測試（`epub_reader_view_test.dart`／`reader_screen_test.dart` FXL 案例）維持全數通過，確認未影響既有懸浮控制系統。
- integration_test（真機）：開啟一本 FXL（漫畫）EPUB，驗證書籤新增、清單查看、重新命名、跳轉的端到端流程。

**驗收標準：**

- [ ] FXL 懸浮控制按鈕群組新增 🔖 書籤 toggle、📚 筆記兩顆按鈕
- [ ] FXL 書籤功能與非 FXL 共用同一套資料模型與清單 UI（複用 Issue 1）
- [ ] FXL 情境下「劃線與備註」分頁顯示空狀態、不可互動
- [ ] 新增按鈕跟隨既有三欄熱區收合顯示/隱藏邏輯
- [ ] 書籤跳轉後懸浮控制面板自動收合（比照既有 `onFixedLayoutPageTurn` 慣例）
- [ ] 既有 FXL 測試全數通過，無回歸
- [ ] 上述測試皆通過，`flutter analyze` 乾淨
- [ ] 真機整合測試涵蓋 FXL 書籤新增/查看/跳轉的端到端流程

**Blocked by：** Issue 1

---

## Issue 5：Markdown 導出

**Status:** ready-for-agent

**依賴：** Issue 1（書籤資料）、Issue 2（劃線/備註資料；PDF 資料需 Issue 3 才有真實內容可匯出，但匯出邏輯本身不技術依賴 Issue 3）

**What to build：**

新增 Markdown 內容產生邏輯（純函式，比照 `prototype/index.html` `exportMarkdown()` 已定義的格式骨架）：依序輸出「🔖 書籤清單」「✏️ 劃線與個人備註」兩大段落，範圍固定為目前這一本書。

`NotesBottomSheet` 新增「導出為 Markdown」按鈕：產生內容後寫入 App 私有暫存目錄（`path_provider` 的 `getTemporaryDirectory()`，本專案既有依賴，不需申請任何外部儲存權限），透過新增的 `share_plus` 套件依賴呼叫 `Share.shareXFiles` 觸發 Android 系統分享。

**`FileProvider` 衝突風險（審查修正，見 `tmp/epic-6/reviews/issues_review.md` 1.5）**：查證 `app/android/app/src/main/AndroidManifest.xml` 已宣告本專案自己的 `FileProvider`（authority `${applicationId}.fileprovider`，路徑設定於 `@xml/file_paths`）；`share_plus` 通常會在其套件 manifest 內自動註冊另一個預設 `FileProvider`。加入 `share_plus` 依賴後須確認：(a) 兩個 `FileProvider` 的 authority 不衝突（manifest merge 是否成功建置）；(b) 實際負責分享 `.md` 檔案的 provider，其 `provider_paths`／`file_paths` 設定確實涵蓋 `getTemporaryDirectory()` 對應的路徑，避免接收端 App 收到 `content://` URI 後回報無權限讀取。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - Markdown 內容產生純函式：涵蓋「有書籤+有劃線+有備註」「只有書籤」「只有劃線無備註」「只有純備註」「全部皆空」等組合，驗證輸出格式正確。
  - 「導出為 Markdown」按鈕觸發後，正確呼叫檔案寫入與 `Share.shareXFiles`（可驗證呼叫參數，`share_plus` 為 Dart 套件而非本專案原生 method channel，不受既有「`app/test/` 不 mock 原生 channel」慣例限制）。
- integration_test（真機）：觸發導出後，驗證檔案確實寫入暫存目錄且內容正確、Android 系統分享面板確實喚起（不強求斷言分享後續由作業系統接管的畫面）；若接收端 App（例如另一個筆記 App）回報無權限讀取分享的檔案，須檢查 `AndroidManifest.xml` 是否與 `share_plus` 自動註冊的 `FileProvider` 發生宣告衝突，見上方「`FileProvider` 衝突風險」。

**驗收標準：**

- [ ] Markdown 內容正確涵蓋書籤清單與劃線/備註清單，格式符合既有骨架
- [ ] 導出範圍固定為目前這一本書
- [ ] 存檔至 App 私有暫存目錄，不需額外儲存權限
- [ ] 透過 `share_plus` 觸發 Android 系統分享
- [ ] `share_plus` 與本專案既有 `FileProvider` 無 manifest 衝突，分享的暫存檔案路徑確實被涵蓋、接收端可正常讀取
- [ ] 上述測試皆通過，`flutter analyze` 乾淨
- [ ] 真機整合測試涵蓋導出→存檔→分享的端到端流程
