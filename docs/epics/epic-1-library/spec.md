# Epic 1 — 圖書庫基礎：規格 (Spec)

這是實作 `epic-1-library` 的唯一事實來源。問題/解法的完整敘述請見 `design.md`，原生讀取契約擴充的完整理由請見 `docs/adr/0002-content-uri-reader-contract.md`。

## 模組 (Modules)

- **`LibraryScreen`**（Dart，取代現有佔位版本）—— 圖書庫主畫面：匯入入口、分類群組列、排序/檢視模式列、書架/列表兩種呈現。
- **`LibraryRepository`**（Dart）—— 封裝 sqflite 存取，`books`/`groups` 兩張表的唯一存取入口。
- **`BookImportService`**（Dart）—— 協調 `file_picker` 選檔/選資料夾、呼叫原生 `book_metadata` channel、寫入 `LibraryRepository`。
- **原生 `book_metadata` MethodChannel**（Android，新增）—— 一次性呼叫，供匯入流程提取詮釋資料（標題/作者/封面 bytes），與既有 `openBook`/`onPageRendered`/`onError` 這組 `PlatformView` 渲染契約分開。
- **`EpubReaderView`/`PdfReaderView` 原生擴充**（Android，異動既有模組）—— `openBook(path)` 依 ADR 0002 同時接受檔案系統路徑或 `content://` URI。
- **`AboutScreen`**（Dart，新增）—— FR-29 應用程式資訊頁，獨立於圖書庫資料模型。

`sample_books.dart`／`stageSampleBookFile()`（epic-0 遺留的範例書籍佔位邏輯）予以移除。

## 介面 (Interfaces)

### 資料模型

```dart
class Book {
  final String id;
  final String title;
  final String? author;
  final BookFileFormat format; // 見下方 BookFileFormat 說明
  final String filePath;   // 檔案系統路徑或 content:// URI 字串（見 ADR 0002）
  final BookSource source; // local | googleDrive | oneDrive（本 epic 僅產生 local）
  final String? coverPath; // 本機 PNG 路徑，null 表示尚未產生/產生失敗
  final double progress;   // 本 epic 固定為 0
  final String groupName;  // 預設 '未分類'
  final DateTime createTime;
  final DateTime lastReadTime;
}

class BookGroup {
  final String name; // PK；'未分類' 為系統保留、不可重新命名或刪除
}

// 獨立於 reader/book_format.dart 的 BookFormat（epub/pdf/unknown，服務
// ReaderScreen 的原生渲染分派，目前只有 epub/pdf 有對應原生視圖）。圖書庫
// 資料層需要完整表達 FR-01 的三種支援格式（含尚未有渲染引擎的 TXT，由
// epic-11-txt-engine 補上），因此另外定義、刻意不與 BookFormat 共用——
// ReaderScreen 依 filePath 自行呼叫 detectBookFormat() 判斷格式，不吃
// Book.format，因此兩個列舉之間不需要互相轉換。
enum BookFileFormat { epub, pdf, txt }
enum BookSource { local, googleDrive, oneDrive }
enum LibrarySortBy { lastRead, createTime, author, title }
enum LibraryViewMode { grid, list }
```

### `LibraryRepository`

```dart
abstract class LibraryRepository {
  Future<Book> insertBook(Book book);
  Future<void> updateBook(Book book);
  Future<void> deleteBook(String id);
  Future<List<Book>> listBooks({LibrarySortBy sortBy, String? groupFilter});

  Future<List<BookGroup>> listGroups();
  Future<void> upsertGroup(String name);
  Future<void> renameGroup(String oldName, String newName);
  Future<void> deleteGroup(String name); // 該群組下書籍 groupName 一併改為 '未分類'
}
```

- `deleteGroup('未分類')` 必須拋出例外（系統保留群組不可刪除）。
- `listBooks` 的 `groupFilter` 為 `null` 或省略時代表「全部」。

### `BookImportService`

```dart
abstract class BookImportService {
  /// 匯入單一或多個檔案；importedFrom 標記來源資料夾名稱供 FR-34 自動分類判斷，
  /// 單檔/多檔匯入（非資料夾匯入）時為 null。
  Future<List<Book>> importFiles(List<String> uris, {String? folderName});

  /// 匯入整個資料夾；autoGroupByFolderName 對應 FR-34 開關（預設 true）。
  Future<List<Book>> importFolder(String folderUri, {bool autoGroupByFolderName = true});
}
```

- 匯入流程內部依序：取得 `takePersistableUriPermission` → 依副檔名/MIME 判斷格式 → 呼叫 `book_metadata` channel 取得詮釋資料 → 落地封面 PNG → 寫入 `LibraryRepository`。
- TXT 格式不呼叫原生 channel，由 Dart 端依書名文字動態產生封面。

### 原生 `book_metadata` MethodChannel 契約

- `extractMetadata(uri: String, format: String) -> { title: String?, author: String?, coverBytes: Uint8List? }`
  - EPUB：內部以 Readium `Publication.open(Uri)` 讀取 OPF 詮釋資料與內嵌封面。
  - PDF：內部以 `ContentResolver.openFileDescriptor(uri, "r")` 取得 fd，交給 `PdfRenderer` 渲染第 1 頁為 `coverBytes`；`title`/`author` 通常回傳 `null`。
  - 失敗時拋出 `PlatformException`，由 `BookImportService` 捕捉並讓該筆匯入以「檔名為標題、無封面」的方式降級寫入（不中斷整批匯入）。

### `EpubReaderView`/`PdfReaderView` 契約異動（ADR 0002）

- `openBook(path: String) -> void`：`path` 語意由「檔案系統路徑」擴充為「檔案系統路徑或 `content://` URI 字串」。
- `onPageRendered()`/`onError(message: String)` 回呼行為不變。
- `ReaderScreen(filePath: String)`、`detectBookFormat()` 對外簽章不變。

## 架構決策（源自 ADR 0002，於此 Epic 範圍內重述）

- 本機匯入採「不複製、直接引用原始檔案」；封面圖片例外，永遠複製產生落地存放。
- 雲端匯入（Google Drive/OneDrive）留給後續 Epic，屆時因需先下載到本機，`source` 會是 `googleDrive`/`oneDrive` 且 `filePath` 指向下載後的本機複本路徑（沿用既有檔案路徑分支，不需再異動契約）。
- 閱讀進度（`progress`）在本 Epic 固定為 `0`，真實回寫與同步屬於 `epic-8-sync`。

## 測試決策 (Testing Decisions)

- **`LibraryRepository`**：純 Dart unit test，使用 in-memory sqflite（`databaseFactory` 指向 `sqflite_common_ffi` 或等效方案）驗證 CRUD、排序、分類篩選、刪除群組時書籍歸位邏輯。
- **`LibraryScreen`**：widget test 驗證空清單/有書清單呈現、grid↔list 切換、分類 tab 篩選、排序切換（皆可用假的 `LibraryRepository` 實作驅動，不需真實裝置）。
- **`book_metadata` channel 與 content URI 版 `openBook`**：`integration_test/`，需真實裝置/模擬器。沿用 epic-0 建立的「等待 `Key('reader_loading_indicator')` 消失且無 `Key('reader_error_text')`」斷言方式驗證 content URI 路徑能渲染成功；另外驗證 `extractMetadata` 對 `test/fixtures/sample.epub`/`sample.pdf` 能取出非空的封面 bytes。
- **`BookImportService`**：純 Dart unit test，`book_metadata` channel 以假的 `MethodChannel` mock 驅動，驗證 FR-34 自動分類邏輯（資料夾名稱建立/歸入既有群組）與單一檔案匯入失敗時的降級行為。

## 範圍外 (Out of Scope)

- Google Drive／OneDrive 雲端匯入的實際串接（FR-02 雲端部分）——資料模型已預留 `BookSource.googleDrive`/`oneDrive`，邏輯留給後續 Epic。
- 真實閱讀進度回寫、位置同步 —— `epic-8-sync`。
- FR-04 全文檢索、書架搜尋框 —— `epic-10-search`。
- 書籍內容渲染本身（沿用 `epic-0-skeleton` 已完成的 `ReaderScreen`/`EpubReaderView`/`PdfReaderView`，本 Epic 只擴充其 `openBook` 契約以支援 content URI）。
- 版面客製化、直排/橫排切換 —— `epic-2`/`epic-3`。
- 註記、書籤 —— `epic-6-annotations`。

## 補充說明 (Further Notes)

本規格核准後的下一步：Scrum Master 階段——拆解為細粒度的垂直切片工單，寫入 `issues.md`，每個工單皆須附上所需的單元測試要求。
