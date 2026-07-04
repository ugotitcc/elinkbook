# epic-1-library 圖書庫基礎 —— Design（Discovery 階段產出）

## 對應 PRD 需求

FR-01（多格式支援）、FR-02（檔案匯入，本 epic 僅涵蓋本機部分）、FR-03（書架/列表檢視模式記憶）、FR-26（排序）、FR-27（智慧封面策略）、FR-28（進度視覺化，本 epic 為 stub）、FR-29（應用程式資訊頁）、FR-33（書籍分類群組）、FR-34（匯入自動分類）。

## 目標

把目前 `LibraryScreen` 顯示固定範例書籍清單（`sample_books.dart`）的佔位行為，換成真正的圖書庫管理：使用者可從本機匯入 ePub/PDF/TXT 書籍（單檔、多檔、整個資料夾），系統自動產生封面、記錄詮釋資料、支援分類群組與多維度排序，並記住使用者上次選擇的檢視模式。

## 範圍與排除項目

**本 epic 涵蓋：**
- 本機檔案匯入（單檔/多檔/資料夾批次）
- 書架資料的本地持久化（sqflite）
- 書架視圖（書架/列表模式）+ 排序 + 分類群組篩選
- 匯入時自動產生封面、提取標題/作者詮釋資料
- 書籍分類群組 CRUD（FR-33）與匯入自動分類（FR-34）
- 應用程式「關於」頁面（FR-29）
- 為達成「不複製、直接引用原始檔案」，擴充 epic-0 既定的原生讀取契約以支援 `content://` URI

**明確排除，留給後續 Epic：**
- Google Drive／OneDrive 雲端匯入的實際實作（FR-02 雲端部分）——僅在資料模型預留 `source` 欄位與 UI 顯示位，邏輯留給後續 epic
- 真實閱讀進度回寫／位置同步——`epic-8-sync` 範疇，本 epic 書架上的進度百分比固定顯示 0%
- FR-04 全文檢索（`epic-10-search`），本 epic 書架不含搜尋框
- 書籍內容渲染本身（沿用 epic-0 已完成的 `ReaderScreen`/`EpubReaderView`/`PdfReaderView`）

## 架構異動：原生讀取契約支援 content URI（跨 epic-0 seam）

epic-0 建立的 `EpubReaderView`/`PdfReaderView` 原生契約中，`openBook(path)` 目前只接受真實檔案系統路徑。為了達成「匯入本機檔案時不複製一份到 App 私有目錄、直接引用原始檔案」，本 epic 需要把這個契約擴充為同時接受檔案系統路徑或 `content://` URI 字串：

- **EPUB**：原生端 Readium 的 `Publication.open()` 改用 Android `Uri` 開啟（Readium 原生支援）。
- **PDF**：原生端改用 `ContentResolver.openFileDescriptor(uri, "r")` 取得 `ParcelFileDescriptor`，餵給既有的 `android.graphics.pdf.PdfRenderer`。
- Dart 端 `filePath` 參數語意由「檔案系統路徑」擴充為「檔案系統路徑或 content URI 字串」；`detectBookFormat()` 判斷格式的邏輯不變（仍依副檔名/MIME）。
- 匯入時透過 SAF 選檔取得的 URI，需在原生端呼叫 `ContentResolver.takePersistableUriPermission()`，讓權限跨越 App 重啟仍然有效。

此異動屬於架構層級改動，需在 Architecting 階段（`spec.md`）補一份 ADR 記錄這個「原生讀取契約由檔案路徑擴充為檔案路徑或 content URI」的決定與理由。

## 資料模型（sqflite）

新增本機資料庫 `library.db`，包含兩張表：

**`books` 表**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | TEXT PK | UUID |
| `title` | TEXT | 匯入時由詮釋資料提取；TXT 用檔名當標題 |
| `author` | TEXT nullable | PDF/TXT 常缺此欄位，允許為空 |
| `format` | TEXT | `epub` / `pdf` / `txt` |
| `filePath` | TEXT | 檔案系統路徑或 `content://` URI（見上方架構異動） |
| `source` | TEXT | `local` / `google_drive` / `onedrive`；本 epic 僅會產生 `local` |
| `coverPath` | TEXT nullable | 產生後封面圖檔的本機路徑（PNG，存於 App 私有目錄，封面永遠是複製產生的圖片，不受「不複製原檔」影響） |
| `progress` | REAL | 固定 stub 為 `0`（見「範圍與排除項目」） |
| `groupName` | TEXT | 對應 FR-33 分類群組，預設 `未分類` |
| `createTime` | INTEGER | epoch ms，匯入時間 |
| `lastReadTime` | INTEGER | epoch ms，預設等於 `createTime`；本 epic 不實作「開啟閱讀器後更新」邏輯外的其他來源 |

**`groups` 表**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `name` | TEXT PK | 群組名稱；`未分類` 為系統保留、不可刪除 |

刪除群組時，該群組下所有書籍的 `groupName` 一併改回 `未分類`（需確認對話框）。

## 匯入流程

1. 使用者從 `LibraryScreen` 的匯入按鈕選擇「選擇檔案（可多選）」或「選擇資料夾」。
2. `file_picker` 設定為回傳原始 SAF URI（而非套件預設的快取複本路徑）。
3. 原生端對取得的 URI 呼叫 `takePersistableUriPermission()`。
4. 依副檔名分派呼叫新增的原生 `MethodChannel`（`elinkbook/book_metadata`）：`extractMetadata(uri, format)` →
   - EPUB：Readium `Publication` API 讀出 title/author/內嵌封面圖 bytes
   - PDF：`PdfRenderer` 渲染第 1 頁為點陣圖當封面；標題/作者通常缺失，缺省用檔名
   - TXT：不呼叫原生，Dart 端依書名文字動態產生封面圖（背景色+書名首字）
5. 封面 bytes 存成 PNG 落地於 App 私有目錄，路徑寫入 `coverPath`。
6. 寫入一筆 `books` 記錄：`filePath` 存原始 URI 字串、`source='local'`。
7. **資料夾批次匯入 + FR-34 自動分類**：若「依資料夾名稱自動建立分類」開關開啟（預設開），批次匯入時以來源資料夾名稱建立/歸入對應 `groups` 項目；資料夾名稱與既有群組同名則直接歸入、不重複建立。

**失效處理**：若日後開啟書籍時，原始 URI 權限已失效（檔案被移動/刪除），`ReaderScreen` 走既有的 `Key('reader_error_text')` 錯誤路徑；書架列表項目在此情況下顯示「檔案無法存取，請重新匯入」提示。

## 書架 UI 與互動

- **匯入入口**：`LibraryScreen` AppBar 新增匯入按鈕（單檔/多檔/資料夾三選項）。
- **分類群組列**：橫向可捲動 tab（「全部」+ 各群組 + 「管理分類」入口），參考 `prototype/index.html` 既有視覺呈現；「管理分類」對話框支援新增/重新命名/刪除（刪除需確認對話框）。
- **排序與檢視模式列**：排序下拉選單（`最後閱讀` 預設／`建立時間`／`作者`／`書名`）+ 書架⇄列表切換鈕；兩者選擇存 `SharedPreferences`，重啟後記住上次選擇。
- **書架模式**：每列 6 本封面 grid。**列表模式**：封面縮圖 + 標題/作者 + 進度百分比（固定顯示 0%）+ 來源圖示（本地/雲端，本 epic 只會出現本地圖示）。
- 點擊書籍項目導航至既有 `ReaderScreen(filePath: ...)`，`filePath` 來自資料庫欄位（URI 或路徑字串）。
- **空清單狀態**：尚無書籍時顯示「尚未匯入書籍」提示 + 匯入按鈕。

## 移除範例書籍佔位邏輯

`sample_books.dart`／`stageSampleBookFile()` 這組 epic-0 遺留的展示用程式碼予以移除。`app/test/fixtures/sample.epub`/`sample.pdf` 仍保留、繼續供 widget/integration test 使用，但透過測試專用的匯入輔助流程（非 App 正常入口的假資料）建立測試情境；細節留給後續 issue 規劃/實作階段決定，不在此設計文件鎖死。

## 應用程式「關於」頁面（FR-29）

從設定畫面新增入口，顯示版本號（`package_info_plus`）、授權條款文字、Android 系統 WebView 版本（因 Readium 內部走 WebView，供除錯用）。獨立畫面，不涉及 `books`/`groups` 資料表。

## 測試策略

- **單元/widget test**（`app/test/`，不需裝置）：
  - sqflite repository 的 CRUD、排序、分類篩選邏輯（使用 in-memory sqflite）
  - `LibraryScreen` 空清單/有書清單、grid↔list 切換、分類 tab 篩選的 widget test
  - 分類群組 CRUD（新增/重新命名/刪除+書籍歸位）邏輯測試
- **整合測試**（`app/integration_test/`，需真實裝置/模擬器）：
  - 驗證原生 `extractMetadata` MethodChannel 對 `test/fixtures/sample.epub`/`sample.pdf` 真的能取出標題/封面
  - 驗證擴充後的 content URI 版 `openBook` 真的能讓 `EpubReaderView`/`PdfReaderView` 渲染成功（沿用既有「等待 loading 消失、無 error」斷言方式）

## 未決事項（留給 Architecting／Scrum Master 階段處理）

- `extractMetadata` MethodChannel 與既有 `openBook` method channel 的確切訊息格式與錯誤碼定義，留給 `spec.md` 定案。
- 測試 fixture 的匯入輔助流程細節（見「移除範例書籍佔位邏輯」一節）。
- 是否需要 ADR 記錄「原生讀取契約擴充支援 content URI」——**是**，將在 Architecting 階段補上。
