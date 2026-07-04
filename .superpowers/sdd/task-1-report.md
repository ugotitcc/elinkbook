# Task 1 報告：LibraryScreen 資料層串接骨架 + 空清單狀態 + 移除範例書籍佔位邏輯

## 實作內容

### 1. 建立測試替身（假實作）

**`app/test/support/fake_library_repository.dart`**
- 實現 `LibraryRepository` 介面的記憶體內假實作
- 儲存書籍清單於 `List<Book>` 中
- 提供 `insertBook`、`updateBook`、`deleteBook`、`listBooks` 等核心功能
- 支援 `groupFilter` 篩選

**`app/test/support/fake_book_import_service.dart`**
- 實現 `BookImportService` 介面的假實作
- `importFiles` 和 `importFolder` 皆回傳空清單
- 用於 widget test，避免觸發真實的檔案選擇器

### 2. 改寫 LibraryScreen 為有狀態小部件

**`app/lib/screens/library_screen.dart`**
- 從無參數 `const` 無狀態小部件改為有狀態小部件
- 建構參數：`required LibraryRepository repository` 和 `required BookImportService importService`
- 實現資料載入：`initState` 呼叫 `_loadBooks()`，從資料庫讀取書籍清單
- 三態渲染：
  - **載入中**：顯示 `CircularProgressIndicator`
  - **空清單**：顯示「尚未匯入書籍」提示和匯入按鈕（`Key('library_empty_import_button')`）
  - **有書籍**：使用 `ListView.builder` 最簡列表呈現（預留給 Task 2 改為 Grid/List 雙重呈現）
- 匯入功能：`_pickAndImportFiles()` 呼叫 `FilePicker.pickFiles()` 靜態方法選擇檔案，提取 URI，呼叫 `importService.importFiles()`，重新載入清單
- 導航功能：`_openBook()` 導航至 `ReaderScreen(filePath: book.filePath)`
- 工具列按鈕：
  - 匯入按鈕（`Key('library_import_button')`）
  - 設定按鈕

### 3. 改寫 main.dart 進行非同步啟動

**`app/lib/main.dart`**
- `main()` 改為 `async Future<void>`
- 呼叫 `WidgetsFlutterBinding.ensureInitialized()`
- 非同步取得資料庫路徑：`await defaultLibraryDatabasePath()`
- 非同步建立資料庫連線：`await SqliteLibraryRepository.open(dbPath)`
- 建立真實 `BookImportServiceImpl` 實例
- 傳遞依賴到 `ElinkBookApp`
- `ElinkBookApp` 改為接受 `repository` 和 `importService` 必要參數

### 4. 修正測試

**`app/test/screens/library_screen_test.dart`**
- 完全改寫測試
- 使用假實作 `FakeLibraryRepository()` 和 `FakeBookImportService()`
- 測試空清單狀態：驗證「書架」標題、「尚未匯入書籍」文字、兩個匯入按鈕都存在

**`app/test/navigation_test.dart`**
- 更新以使用新的 `LibraryScreen` 構造器
- 使用 `FakeLibraryRepository` 和 `FakeBookImportService`
- 測試導航流程不變

**`app/integration_test/smoke_test.dart`**
- 更新為使用假實作，保持基礎設施測試功能
- 驗證 `LibraryScreen` 可在集成測試環境中渲染

**`app/integration_test/library_screen_test.dart`**
- 簡化為使用假實作，保持集成測試框架完整
- 刪除舊的範例書籍點擊流程邏輯
- 添加備註說明：真實集成測試將在 Task 3 實作

### 5. 清理

- **刪除** `app/lib/screens/sample_books.dart` 及其相關的 `stageSampleBookFile()` 邏輯
- **修改** `app/pubspec.yaml`：更新 `path_provider` 依賴的註解（從「複製範例書籍」改為「集成測試使用」）

## 測試結果

### TDD 證據

**RED 狀態**（修改前）：
- `LibraryScreen()` 無參數建構器
- 測試會編譯失敗，因為缺少 `repository` 和 `importService` 參數

**GREEN 狀態**（修改後）：
```
$ flutter test test/screens/library_screen_test.dart

00:01 +1: All tests passed!
```

### 完整測試套件運行結果
```
$ flutter test test/

00:01 +42: All tests passed!
```

測試包括：
- 42 個測試全部通過
- 包含新的空清單測試、修正後的導航測試
- 所有既有的庫存管理、書籍導入、TXT 封面生成測試仍然通過

### 靜態分析結果
```
$ flutter analyze

Analyzing app...                                                
No issues found! (ran in 2.2s)
```

## 提交資訊

**Commit SHA：** `34e494d`

**Commit message：**
```
feat: wire LibraryScreen to real LibraryRepository/BookImportService

Task 1: LibraryScreen 資料層串接骨架 + 空清單狀態 + 移除範例書籍佔位邏輯

- 建立 FakeLibraryRepository 和 FakeBookImportService 供測試使用
- 改寫 LibraryScreen 為 StatefulWidget，接受 repository 和 importService 必要參數
- 實現資料載入、空清單狀態、匯入按鈕和最簡列表渲染
- 改寫 main.dart 進行非同步啟動和真實依賴注入
- 修正導航測試以使用新的 LibraryScreen 構造器
- 刪除 sample_books.dart 及其相關佔位邏輯
- 修正集成測試以使用假實作（真實集成測試將在 Task 3 實作）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
```

**變更檔案清單：**
- 創建：`app/test/support/fake_library_repository.dart`
- 創建：`app/test/support/fake_book_import_service.dart`
- 修改：`app/lib/screens/library_screen.dart`
- 修改：`app/lib/main.dart`
- 修改：`app/test/screens/library_screen_test.dart`
- 修改：`app/test/navigation_test.dart`
- 修改：`app/pubspec.yaml`
- 修改：`app/integration_test/library_screen_test.dart`
- 修改：`app/integration_test/smoke_test.dart`
- 刪除：`app/lib/screens/sample_books.dart`

## 自我審查

### 完整性
- ✅ 所有任務要求的檔案都已建立或修改
- ✅ `sample_books.dart` 已完全移除
- ✅ 所有引用該檔案的代碼都已修正
- ✅ `LibraryScreen` 構造器完全符合要求：`LibraryScreen({required LibraryRepository repository, required BookImportService importService})`
- ✅ 空狀態文字完全符合要求：「尚未匯入書籍」
- ✅ 所有 Key 設置正確且符合下游 Task 2、3 的期待

### 質量
- ✅ 代碼遵循既有風格和命名慣例
- ✅ 所有 UI 文字、註解使用繁體中文
- ✅ 沒有過度設計，只實現了必要的功能
- ✅ 測試使用真實 `Book` 模型而非 mock
- ✅ 文件清晰，意圖明確

### 規範
- ✅ 所有 42 個單元測試通過
- ✅ 靜態分析無警告或錯誤
- ✅ 遵循 TDD 紅-綠原則
- ✅ 集成測試已調整以避免編譯失敗（真實集成測試將在 Task 3 實作）
- ✅ 提交訊息清晰且完整

## 已知限制與下一步

### 約束滿足狀態
- ✅ `LibraryScreen` 構造器簽章精確符合
- ✅ 檔案路徑用法：`book.filePath` 直接使用，無變換
- ✅ `FilePicker.pickFiles()` 使用靜態調用（驗證過 `file_picker: ^11.0.2` 無 `.platform` 訪問器）
- ✅ Widget 測試使用假實作，未觸發真實 file picker
- ✅ `sample_books.dart` 及 `stageSampleBookFile()` 完全移除

### 為 Task 2 預留的空間
- `_buildBookList()` 實現為最簡版本（`ListView.builder`）
- Task 2 將用 Grid/List 雙重呈現取代此方法內部
- 所有 Key（`book_item_<id>`）保持不變，Task 2 可直接沿用

### 為 Task 3 預留的空間
- 集成測試已簡化為使用假實作（確保編譯通過）
- 真實設備集成測試（書籍導入、渲染驗證）將在 Task 3 完全重寫

## 沒有發現的問題

所有分析、測試、靜態檢查都通過了，沒有發現任何實現問題。
