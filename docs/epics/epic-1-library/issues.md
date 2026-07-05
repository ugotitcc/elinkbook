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

**Status:** ✅ 已完成並合併回 `main`（PR #12，merge commit `bdc578c`）。2 個任務皆完成，`flutter test` 55/55 通過，`flutter analyze` 乾淨；App 重啟後排序/檢視模式維持選擇已於真實裝置手動確認。實作計畫經過一輪審查修正（byName 防呆 fallback、`_loadBooks()` 競態守衛、排序測試改用 widget 樹順序比對），完整審查報告見 `reviews/`（本機保留，依本 repo 慣例未提交版本控制），實作計畫見 `plans/plan-issue-6.md`。

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

**Status:** ✅ 已完成並合併回 `main`（PR #13，merge commit `873a465`）。2 個任務皆完成，`flutter test` 62/62 通過，`flutter analyze` 乾淨。整分支審查（Opus）結論為 Ready to merge: Yes；已依審查建議修正圖示重複與邊界情況註解 2 項 Minor，另 2 項（重新命名目前篩選分類時是否跟隨新名稱、新增重複分類名稱提示）評估後不採納（超出規格範圍的 UX 加強）。完整審查報告見 `reviews/review-issue-7.md`（本機保留，依本 repo 慣例未提交版本控制），實作計畫見 `plans/plan-issue-7.md`。

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

**Status:** ✅ 已完成並合併回 `main`（PR #14，merge commit `4b1ec43`）。2 個任務皆完成，`flutter test` 66/66 通過，`flutter analyze` 乾淨；真實裝置手動驗證通過（真實資料夾含 2 個真實檔案，匯入後依資料夾名稱建立分類且書籍歸位正確）。整分支審查結論為 Ready to merge: Yes，已依建議修正 mounted 檢查與文件落差 2 項 Minor，另 2 項（匯入 UI 視覺反饋、`BookMetadataChannel` CoroutineScope 生命週期管理）評估後不採納（前者屬跨匯入路徑的範疇外加強，後者為 Issue 2 遺留技術債非本工單範疇）。完整審查報告見 `reviews/review-issue-8.md`（本機保留，依本 repo 慣例未提交版本控制），實作計畫見 `plans/plan-issue-8.md`。

**依賴：** Issue 4、7

**描述：**
擴充 `BookImportService`，新增 `importFolder(folderUri, {autoGroupByFolderName = true})`：選擇整個資料夾（Android SAF 目錄選擇；經對照 `file_picker` 套件實際原生原始碼確認其 `getDirectoryPath()` 在 Android 上不會回傳真正的 `content://` tree URI，改用獨立的原生 `folder_picker` channel + AndroidX `ActivityResultContracts.OpenDocumentTree()` 取得真正的 tree URI），批次對資料夾內每個支援格式的檔案執行 Issue 4 的單檔匯入邏輯。若 `autoGroupByFolderName` 開啟（預設開，UI 提供開關），依資料夾名稱建立/歸入對應群組；資料夾名稱與既有群組同名時直接歸入、不重複建立。

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

**Status:** ✅ 已完成並合併回 `main`（PR #15，merge commit `b97e328`）。唯一 1 個任務完成，`flutter test` 68/68 通過，`flutter analyze` 乾淨；額外在開發過程中臨時連線的真實裝置上執行了真機 `integration_test`，確認原生變更未破壞既有建置與啟動流程。task-scoped review 與 whole-branch review（Opus）皆為 0 Critical/0 Important（whole-branch review 另有 3 項 Minor，皆不阻擋）。合併後另有一份獨立審查（`reviews/review-issue-9.md`，本次例外提交版本控制）同為 0 Critical/0 Important/0 Minor，其中 1 項「建議」（呼叫 WebView 版本查詢前以 `Platform.isAndroid` 判斷平台）評估後不採納：專案目前無 `ios/` 目錄、iOS 尚未列入任何開發階段，且既有原生 channel 呼叫（`epub_reader_view.dart`/`pdf_reader_view.dart`）皆未使用此類平台防呆、一致仰賴 try-catch 優雅降級，加入會造成風格不一致的 YAGNI 違規。實作計畫見 `plans/plan-issue-9.md`。

**依賴：** 無（可獨立平行進行）

**描述：**
新增 `AboutScreen`，從設定畫面新增入口。顯示版本號（`package_info_plus`）、授權條款文字、Android 系統 WebView 版本偵測（供除錯 Readium 內部 WebView 用）。獨立畫面，不涉及 `books`/`groups` 資料表。

**單元測試要求：**
- Widget test：`AboutScreen` 正確渲染版本號與授權條款文字
- Widget test：從設定畫面可導航至 `AboutScreen` 並可返回

**驗收標準：**
- 上述測試皆通過
- 手動驗證：於真實裝置上開啟關於頁面，WebView 版本欄位顯示非空值

---

## Issue 10：已匯入書籍批次變更分類歸屬

**Status:** ✅ 已完成並合併回 `main`（PR #16，merge commit `df855a4`）。3 個任務皆完成，`flutter test` 78/78 通過，`flutter analyze` 乾淨。實作計畫經過一輪審查修正（`_moveSelectedBooksToGroup()` 提前於寫入迴圈前呼叫 `_exitSelectionMode()` 避免重複觸發、選取模式下停用分類 tab 切換以避免可見書籍集合中途改變）。實作過程中發現 Task 1 的 implementer commit 一度誤植於 `main`（推測是 subagent session 期間 shell 工作目錄被重置所致），已由 controller cherry-pick 到正確分支並清乾淨 `main`，不影響最終結果。task-scoped review 與 whole-branch review（Opus）皆為 0 Critical/0 Important（whole-branch review 另有 2 項極輕微 Minor，審查者認為皆不成立/不影響）。本次執行環境無實體 Android 裝置，驗證方式改以 `flutter test` 模擬測試與程式碼審查把關，「手動驗證」章節（見下方驗收標準）尚待實機補做。實作計畫見 `plans/plan-issue-10.md`。

**背景：** Epic 1 歸檔前的 `/grill-with-docs` 訪談中發現的功能缺口——`LibraryRepository.updateBook()`（Issue 1）與 `Book.groupName` 欄位已支援修改一本書所屬分類，但 `LibraryScreen`（Issue 5-8）沒有任何 UI 入口能觸發它。`prototype/index.html` 本身也未曾設計過這個互動（書架卡片 `onclick` 只導覽進閱讀器），故此為原型與 PRD 皆未定義過的新增需求，經人類確認後追加為 Epic 1 的第 10 張工單。

**依賴：** Issue 1、5、6、7（`LibraryRepository.updateBook()`、書架/列表雙檢視、分類群組管理對話框）

**描述：**
在 `LibraryScreen` 新增「長按書籍卡片進入多選模式」的批次分類異動功能：
- 長按任一書籍卡片（書架格狀檢視與列表檢視皆須支援）→ 進入選取模式，且該本書自動成為已勾選狀態（Android 原生慣例：長按進入多選 + 自動選取當下項目）。
- 選取模式下，點擊其他書籍卡片繼續加選/取消選；此模式下點擊卡片的行為從「導覽進閱讀器」暫時改為「勾選/取消勾選」。
- App Bar 於選取模式下改為顯示「已選取 N 本」與左側「✕ 取消」（退出選取模式，回到一般瀏覽狀態；系統返回鍵亦可退出）。
- App Bar 右側（或底部）提供「移動到分類」按鈕，點擊後彈出分類清單（沿用 Issue 7「管理分類」對話框已有的分類清單，含「未分類」），選定目的地後對所有已勾選書籍呼叫 `LibraryRepository.updateBook()` 逐一更新 `groupName`。
- **範圍明確排除批次刪除書籍**——批次刪除是完全不同風險等級的操作（資料刪除 vs. 純分類異動），未經要求不多做（YAGNI）；已記錄為後續待辦（見下方「已知後續需求」），屆時可重用本工單建立的多選模式骨架。

**已知後續需求（不在本工單範圍內，留給後續工單）：**
- 批次刪除已選取的書籍。

**單元測試要求：**
- Widget test：長按書籍卡片後進入選取模式，且該卡片顯示為已選取狀態
- Widget test：選取模式下點擊其他卡片可加選/取消選；點擊卡片不再導覽進閱讀器
- Widget test：選取模式下點擊「✕ 取消」後恢復一般瀏覽狀態（不再顯示勾選框），且卡片點擊恢復導覽進閱讀器
- Widget test：選取多本書後點擊「移動到分類」，選擇目的分類後，所有已勾選書籍的 `groupName` 皆更新為該分類；書架/列表依目前篩選條件重新渲染
- Widget test：書架（grid）與列表兩種檢視皆能觸發長按進入選取模式並完成批次移動

**驗收標準：**
- 上述測試皆通過
- 手動驗證：長按選取多本書、移動到既有分類後，該分類 tab 篩選下能看到這些書籍；移動到「未分類」也正確生效

---

## Issue 11：匯入流程新增處理中狀態回饋

**Status:** ✅ 已完成並合併回 `main`（PR #17，merge commit `441a1e8`）。1 個任務完成，`flutter test` 81/81 通過，`flutter analyze` 乾淨。實作計畫審查與程式碼審查各提出一次「覆蓋層需包 `AbsorbPointer` 才能阻擋手勢穿透」的建議，兩次皆評估後不採納：對照 Flutter SDK 原始碼查證，`ColoredBox` 的 render object 天生為 `HitTestBehavior.opaque`，`Stack` 的 hit-test 機制會在最上層命中後即停止往下測試；程式碼審查階段另外寫了一個一次性診斷測試實測驗證——匯入中觸發覆蓋層顯示後對底下書籍卡片長按，`flutter_test` 本身即回報該卡片「無法接收指標事件」，且選取模式確實未被進入，證實現有寫法已完全阻擋手勢穿透，無需額外元件。本次執行環境無實體 Android 裝置，驗證方式改以 `flutter test` 模擬測試與程式碼審查把關，「手動驗證」章節（見下方驗收標準）尚待實機補做。實作計畫見 `plans/plan-issue-11.md`。

**背景：** Epic 1 歸檔前的 `/grill-with-docs` 訪談中，針對「漫畫類 EPUB3 封面無法正確取得」的回報進行實機重現時發現：原生封面抽取邏輯本身完全正常（已用真實裝置與真實漫畫檔案驗證），真正原因是 `LibraryScreen._pickAndImportFiles()`（`library_screen.dart:102-118`，Issue 5）與 `_pickAndImportFolder()`（`library_screen.dart:120-139`，Issue 8）呼叫 `importService.importFiles()`/`importFolder()` 時，**完全沒有顯示任何處理中的 UI 回饋**（無 spinner、無進度提示、觸發按鈕也未停用）。小檔案幾乎感覺不到，但透過真實系統檔案選擇器匯入 100MB 以上的大檔案（例如漫畫類 EPUB）時，處理可能耗時數十秒甚至超過一分鐘，這段期間畫面完全無變化，使用者會誤以為 App 當機或匯入失敗。

**依賴：** Issue 5、8（現有的 `_pickAndImportFiles()`／`_pickAndImportFolder()` 匯入流程）

**描述：**
在 `LibraryScreen` 的匯入相關操作進行期間新增可視的處理中狀態：
- 觸發匯入（單檔/多檔選取按鈕、資料夾匯入按鈕）後，在 `importService.importFiles()`/`importFolder()` 等待期間，畫面顯示明確的「匯入中...」提示（例如覆蓋層 + `CircularProgressIndicator`，或觸發按鈕本身轉為 loading 狀態並停用），避免使用者誤判 App 已無回應。
- 處理中狀態應同時停用其他匯入觸發點（避免使用者重複點擊，觸發並行的多次匯入）。
- 匯入完成（成功或失敗皆算完成）後，處理中狀態解除，恢復一般可互動畫面；既有的「匯入失敗時靜默吞掉例外」行為維持不變（本工單只新增處理中期間的視覺回饋，不改動錯誤處理邏輯）。

**單元測試要求：**
- Widget test：觸發單檔/多檔匯入後、`importFiles()` 尚未完成前，畫面顯示處理中狀態（可用可控制完成時機的 fake `BookImportService` 讓 `importFiles()` 保持 pending）
- Widget test：觸發資料夾匯入後、`importFolder()` 尚未完成前，畫面同樣顯示處理中狀態
- Widget test：處理中狀態下，匯入觸發按鈕/入口為停用狀態（無法重複觸發）
- Widget test：`importFiles()`/`importFolder()` 完成（含拋出例外的情況）後，處理中狀態正確解除，畫面恢復正常

**驗收標準：**
- 上述測試皆通過
- 手動驗證：匯入一個 100MB 以上的大檔案（例如漫畫類 EPUB），處理期間畫面明確顯示「匯入中」，完成後才恢復正常並顯示該書籍與封面
