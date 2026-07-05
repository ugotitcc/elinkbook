# Epic 1 — 圖書庫基礎：工單清單 (Issues)

依 `spec.md`（搭配 `design.md`、`docs/adr/0002-content-uri-reader-contract.md`）拆解出的細粒度垂直切片工單。Issue 1、2、3 彼此獨立可平行進行，其餘依標示的依賴順序執行。

---

## Issue 1：LibraryRepository 資料層（sqflite CRUD）

**Status:** ✅ 已完成並合併回 `main`（PR #8，merge commit `3adbb68`）。4 個任務皆完成，`flutter test` 29/29 通過，`flutter analyze` 乾淨；整分支審查後另依 `reviews/review-issue-1.md` 修正 `renameGroup` 重複名稱檢查的 TOCTOU 風險（commit `d987e9f`）。完整審查報告見 `reviews/review-issue-1.md`。

**依賴：** 無（起始工單，可與 Issue 2、3 平行）

**描述：**
建立本機 sqflite 資料庫 `library.db`，包含 `books` 與 `groups` 兩張表（欄位定義見 `spec.md`「資料模型」章節），並實作 `LibraryRepository` 介面（`insertBook`/`updateBook`/`deleteBook`/`listBooks(sortBy, groupFilter)`/`listGroups`/`upsertGroup`/`renameGroup`/`deleteGroup`）。`未分類` 為系統保留群組。

**單元測試要求：**
- 純 Dart 單元測試（in-memory sqflite，不需模擬器）：`insertBook`/`updateBook`/`deleteBook` 基本 CRUD
- 單元測試：`listBooks` 依 `LibrarySortBy`（最後閱讀/建立時間/作者/書名）四種排序皆回傳正確順序
- 單元測試：`listBooks(groupFilter: ...)` 只回傳指定群組的書籍；`groupFilter` 為 `null` 時回傳全部
- 單元測試：`deleteGroup(name)` 後，原本歸屬該群組的書籍 `groupName` 皆變為 `未分類`
- 單元測試：`deleteGroup('未分類')` 拋出例外
- 單元測試：`renameGroup` 對重複名稱、對 `未分類` 重新命名的行為皆有明確定義並被測試涵蓋

**驗收標準：**
- 所有上述測試以 `flutter test` 通過，不需真實裝置/模擬器
- `flutter analyze` 乾淨

---

## Issue 2：原生 `book_metadata` MethodChannel（EPUB/PDF 詮釋資料+封面提取）

**Status:** ✅ 已完成並合併回 `main`（PR #9，merge commit `b85c8a9`）。2 個任務皆完成，新增的 5 項 `book_metadata_channel_test.dart` 測試與既有 5 項回歸測試皆於真實 Android 裝置上通過。整分支審查發現 PDF/EPUB 封面處理在主執行緒執行的 Important 問題，已修正（commit `bbf1dd7`）並複審通過。完整審查報告見 `reviews/review-issue-2.md`。

**依賴：** 無（可與 Issue 1、3 平行）

**描述：**
新增原生 Android `MethodChannel`（`elinkbook/book_metadata`），實作 `extractMetadata(uri, format) -> { title, author, coverBytes }`：EPUB 用 Readium `Publication.open(Uri)` 讀取 OPF 詮釋資料與內嵌封面；PDF 用 `ContentResolver.openFileDescriptor` 取得 fd 交給 `PdfRenderer` 渲染第 1 頁為封面（`title`/`author` 可為 `null`）。此 channel 與既有 `openBook`/`onPageRendered`/`onError`（`PlatformView` 渲染契約）分開、獨立呼叫。

**單元測試要求：**
- Flutter `integration_test`（真實 Android 模擬器/裝置）：對 `test/fixtures/sample.epub` 呼叫 `extractMetadata`，斷言回傳非空的 `title` 與非空的 `coverBytes`
- `integration_test`：對 `test/fixtures/sample.pdf` 呼叫 `extractMetadata`，斷言回傳非空的 `coverBytes`
- `integration_test`：對不存在或損毀的 URI 呼叫 `extractMetadata`，斷言拋出可辨識的例外/錯誤（而非未預期崩潰）

**驗收標準：**
- 三項 `integration_test` 皆通過

---

## Issue 3：`EpubReaderView`/`PdfReaderView` content URI 契約擴充（ADR 0002）

**Status:** ✅ 已完成並合併回 `main`（PR #10，merge commit `9412e14`）。2 個任務皆完成，`flutter test` 通過，且新增 `file://` 與 `content://` URI 測試已於真實 Android 裝置上通過。完整審查與複審報告見 `reviews/review-issue-3.md`。

**依賴：** 無（可與 Issue 1、2 平行）

**描述：**
依 `docs/adr/0002-content-uri-reader-contract.md`，把既有 `openBook(path)` 契約擴充為同時接受檔案系統路徑或 `content://` URI 字串：EPUB 端 Readium `Publication.open()` 改用 `Uri`；PDF 端改用 `ContentResolver.openFileDescriptor` 取得 `ParcelFileDescriptor` 餵給 `PdfRenderer`。匯入時透過 SAF 取得的 URI 需呼叫 `takePersistableUriPermission()`。原本檔案路徑的呼叫方式必須保持完全相容（回歸測試涵蓋）。

**單元測試要求：**
- `integration_test`：對 `test/fixtures/sample.epub`/`sample.pdf` 的**檔案系統路徑**呼叫 `openBook`，確認原有行為未被破壞（回歸測試，斷言 `onPageRendered` 觸發）
- `integration_test`：把 `test/fixtures/sample.epub`/`sample.pdf` 透過 `FileProvider` 或等效方式轉為 `content://` URI 後呼叫 `openBook`，斷言 `onPageRendered` 觸發（而非 `onError`）
- `integration_test`：對已撤銷權限或無效的 URI 呼叫 `openBook`，斷言 `onError` 被觸發

**驗收標準：**
- 上述回歸與新增測試皆通過
- `EpubReaderView.kt`/`PdfReaderView.kt` 兩者皆同時支援檔案路徑與 content URI 兩種輸入

---

## Issue 4：`BookImportService` — 本機單檔/多檔匯入

**Status:** ✅ 已完成並合併回 `main`（本機合併，merge commit `bf4ebec`）。4 個任務皆完成，`flutter test` 42/42 通過，`flutter analyze` 乾淨；真正 `content://` URI 的 `integration_test` 與手動端到端驗證皆已在真實裝置上通過（3 個真實檔案匯入成功寫入 `library.db`）。整分支審查發現的 Important 問題（Windows Kotlin 增量編譯 workaround 影響範圍過廣）已修正為僅限 Windows 生效。完整審查報告見 `reviews/`，實作計畫見 `plans/plan-issue-4.md`。

**依賴：** Issue 1、2、3

**描述：**
實作 `BookImportService.importFiles(uris, {folderName})`：用 `file_picker`（設定為回傳原始 SAF URI）選擇單一或多個檔案 → 對每個 URI 呼叫 `takePersistableUriPermission` → 依副檔名/MIME 判斷格式 → 呼叫 Issue 2 的 `book_metadata` channel 取得詮釋資料 → 落地封面 PNG（TXT 格式不呼叫原生 channel，改由 Dart 端依書名文字動態產生封面）→ 寫入 Issue 1 的 `LibraryRepository`。單一檔案的詮釋資料提取失敗時，該筆以「檔名為標題、無封面」降級寫入，不中斷整批匯入。

**單元測試要求：**
- 純 Dart 單元測試：`book_metadata` channel 以 mock `MethodChannel` 驅動，驗證 EPUB/PDF/TXT 三種格式分別走對的提取路徑
- 單元測試：詮釋資料提取失敗時的降級寫入行為（標題=檔名、`coverPath=null`）
- 單元測試：匯入成功的書籍 `source` 欄位為 `local`，`filePath` 存放原始 URI 字串（未被複製）
- **`integration_test`（強制，不可用 `file://` 替代）**：用真正的 `content://` URI（例如透過 `androidx.core.content.FileProvider` 或等效機制，取得一個由 ContentProvider 服務、且已呼叫 `takePersistableUriPermission` 授權的 URI，而非 `Uri.file(...)` 產生的 `file://`）呼叫 Issue 3 擴充後的 `openBook`，斷言 `onPageRendered` 觸發。理由：Issue 3 的整分支審查（`docs/epics/epic-1-library/reviews/`）指出，`AssetRetriever`/`ContentResolver` 對 `file://` 與 `content://` 內部走的是不同程式碼路徑（一個直接開檔、一個經 ContentProvider），Issue 3 只驗證了前者；本工單必須補上後者的真實驗證，不可讓 `file://` 替代測試被無聲繼承下去。

**驗收標準：**
- 上述測試以 `flutter test` 通過
- 上述 `content://` `integration_test` 在真實裝置/模擬器上通過
- 手動驗證：從裝置選取一個真實 EPUB/PDF 檔案，匯入後資料庫確實新增一筆對應記錄

---

## Issue 5：`LibraryScreen` 串接真實圖書庫

**Status:** ✅ 已完成並合併回 `main`（PR #11，merge commit `5850f36`）。3 個任務皆完成，`flutter test` 45/45 通過，`flutter analyze` 乾淨；真實裝置 `integration_test` 透過真正的 `content://` URI（Issue 4 的 `createTestContentUri`）匯入書籍後點擊可正常導航並渲染。整分支審查（Opus）結論為 Ready to merge: Yes，僅有 Minor 建議未阻擋合併。完整審查報告見 `reviews/review-issue-5.md`（本機保留，依本 repo 慣例未提交版本控制），實作計畫見 `plans/plan-issue-5.md`。

**依賴：** Issue 1、4

**描述：**
把 `LibraryScreen` 從目前顯示固定範例書籍清單（`sample_books.dart`/`stageSampleBookFile()`）改為讀取 `LibraryRepository` 的真實資料：新增匯入按鈕（觸發 Issue 4 的 `BookImportService`）、書架 grid（每列 6 本，僅封面+標題+進度）與列表兩種呈現（封面+標題/作者+進度）、空清單狀態（「尚未匯入書籍」提示）、點擊書籍項目導航至既有 `ReaderScreen(filePath: ...)`（`filePath` 為資料庫中的 URI 或路徑字串，走 Issue 3 擴充後的契約）。移除 `sample_books.dart`／`stageSampleBookFile()` 遺留程式碼；`test/fixtures/sample.epub`/`sample.pdf` 保留供測試 fixture 匯入輔助流程使用。

**單元測試要求：**
- Widget test：空清單狀態正確顯示「尚未匯入書籍」提示與匯入按鈕
- Widget test：有書籍時，書架 grid（標題、封面、進度固定顯示 0%）與列表（標題、作者、封面、進度固定顯示 0%）兩種呈現皆能正確渲染書籍項目
- `integration_test`：從書架點擊一本透過 Issue 4 匯入的真實書籍項目，斷言導航至 `ReaderScreen` 且內容成功渲染（`onPageRendered` 觸發）

**驗收標準：**
- 上述測試皆通過
- 端到端可展示：使用者從書架匯入一本書 → 該書出現在書架 → 點擊後能正常閱讀
- `sample_books.dart`/`stageSampleBookFile()` 已從程式碼庫移除

---

## Issue 6：排序 + 檢視模式記憶

**Status:** ready-for-agent

**依賴：** Issue 5

**描述：**
在 `LibraryScreen` 新增排序下拉選單（`最後閱讀` 預設／`建立時間`／`作者`／`書名`，呼叫 `LibraryRepository.listBooks(sortBy: ...)`）與書架⇄列表切換鈕；兩者選擇存 `SharedPreferences`，App 重啟後記住使用者上次選擇。

**單元測試要求：**
- Widget test：切換排序選單後，書籍清單順序隨之改變
- Widget test：切換書架/列表檢視模式後畫面呈現隨之改變
- 單元測試：`SharedPreferences` 中排序/檢視模式的讀寫邏輯（重啟後應恢復上次選擇）

**驗收標準：**
- 上述測試皆通過
- 手動驗證：切換檢視模式後關閉並重新開啟 App，畫面維持上次選擇的模式

---

## Issue 7：書籍分類群組管理

**Status:** ready-for-agent

**依賴：** Issue 1、5

**描述：**
在 `LibraryScreen` 新增分類群組列（橫向可捲動 tab：「全部」+ 各群組 + 「管理分類」入口）與管理對話框，支援新增/重新命名/刪除群組（呼叫 Issue 1 的 `LibraryRepository` 群組方法；刪除需二次確認對話框）。點擊群組 tab 依 `groupFilter` 篩選書架/列表顯示的書籍。

**單元測試要求：**
- Widget test：點擊群組 tab 後，畫面只顯示該群組的書籍；點擊「全部」顯示所有書籍
- Widget test：新增分類後，新分類出現在 tab 列
- Widget test：刪除分類前彈出確認對話框；確認後該分類下書籍改顯示於「未分類」篩選
- Widget test：嘗試刪除「未分類」時操作被禁止（UI 層面不可觸發或提示不可刪除）

**驗收標準：**
- 上述測試皆通過

---

## Issue 8：資料夾批次匯入 + 匯入自動分類

**Status:** ready-for-agent

**依賴：** Issue 4、7

**描述：**
擴充 `BookImportService`，新增 `importFolder(folderUri, {autoGroupByFolderName = true})`：用 `file_picker` 選擇整個資料夾（Android SAF 目錄選擇），批次對資料夾內每個支援格式的檔案執行 Issue 4 的單檔匯入邏輯。若 `autoGroupByFolderName` 開啟（預設開，UI 提供開關），依資料夾名稱建立/歸入對應群組；資料夾名稱與既有群組同名時直接歸入、不重複建立。

**單元測試要求：**
- 純 Dart 單元測試：批次匯入資料夾內多個檔案，皆正確寫入 `LibraryRepository`
- 單元測試：`autoGroupByFolderName=true` 且群組不存在時，自動建立同名群組並歸入
- 單元測試：`autoGroupByFolderName=true` 且群組已存在時，直接歸入既有群組、不重複建立
- 單元測試：`autoGroupByFolderName=false` 時，匯入書籍歸入預設「未分類」

**驗收標準：**
- 上述測試皆通過
- 手動驗證：選擇一個含多本書籍的真實資料夾匯入後，書架上依資料夾名稱出現對應分類且書籍歸位正確

---

## Issue 9：應用程式「關於」頁面

**Status:** ready-for-agent

**依賴：** 無（可獨立平行進行）

**描述：**
新增 `AboutScreen`，從設定畫面新增入口。顯示版本號（`package_info_plus`）、授權條款文字、Android 系統 WebView 版本偵測（供除錯 Readium 內部 WebView 用）。獨立畫面，不涉及 `books`/`groups` 資料表。

**單元測試要求：**
- Widget test：`AboutScreen` 正確渲染版本號與授權條款文字
- Widget test：從設定畫面可導航至 `AboutScreen` 並可返回

**驗收標準：**
- 上述測試皆通過
- 手動驗證：於真實裝置上開啟關於頁面，WebView 版本欄位顯示非空值
