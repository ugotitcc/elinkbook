# ADR 0007：`ReaderScreen` 新增 `bookId` 必要參數與 `BookReaderPrefsRepository` 依賴注入

## 狀態

已採納

## 背景

`ReaderScreen` 自 `epic-0-skeleton` 起的公開建構參數只有 `filePath: String`（見 `CLAUDE.md`「唯一的閱讀器 seam」）——原生渲染引擎需要真實的裝置檔案系統路徑，此前沒有任何功能需要知道「這是圖書庫裡的哪一本書」，也不需要存取任何資料庫。

`epic-3-fonts-layout` Issue 3 需要透過 `BookReaderPrefsRepository.load(bookId)`/`save(bookId, prefs)` 讀寫單書版面偏好設定（`book_reader_prefs` 表以 `book_id` 為主鍵，見 Issue 1 `spec.md`「資料模型」），這帶出兩個 `spec.md` 撰寫時沒有交代清楚、撰寫 Issue 3 實作計劃時才發現的缺口：

1. `ReaderScreen` 不知道 `bookId`。
2. `ReaderScreen` 沒有任何管道取得 `BookReaderPrefsRepository`（進而沒有 `Database`）——App 目前的相依性管理慣例是在 `main.dart`（composition root）建構具象的 `SqliteLibraryRepository`，透過建構子參數逐層往下傳（`ElinkBookApp(repository: ...)` → `LibraryScreen(repository: ...)`），沒有 service locator；但 `LibraryScreen`／`ElinkBookApp` 型別上持有的是抽象介面 `LibraryRepository`，這個介面本身沒有暴露 `Database`（只有具象類別 `SqliteLibraryRepository` 有 `Database get database`）。

## 決策

- `ReaderScreen` 建構參數擴充為 `ReaderScreen({required String filePath, required String bookId, required BookReaderPrefsRepository prefsRepository})`。
- `main.dart` 在建構 `SqliteLibraryRepository`（具象型別，尚未收窄為 `LibraryRepository` 介面）之後，立即用其 `.database` 建構 `BookReaderPrefsRepository(repository.database)`；這個實例作為**與 `repository`/`importService`平行的獨立建構子參數**，逐層傳遞：`ElinkBookApp(prefsRepository: ...)` → `LibraryScreen(prefsRepository: ...)` → `ReaderScreen(prefsRepository: ...)`。`LibraryRepository` 抽象介面不受影響、不新增任何成員。
- 唯一呼叫端 `LibraryScreen._openBook(Book book)` 已持有完整的 `Book` 物件，直接傳入 `book.id` 作為 `bookId`。

## 曾考慮的替代方案

- **維持 `ReaderScreen(filePath: String)` 不變，內部以 `filePath` 反查 `book_id`**：需要 `ReaderScreen` 額外依賴 `SqliteLibraryRepository`，且必須假設 `filePath` 在 `books` 表中全域唯一（目前 schema 沒有這個唯一性約束）。比起直接傳遞已知的 `book.id`，這個方案引入不必要的耦合與一個未經驗證的假設，予以排除。
- **在 `LibraryRepository` 抽象介面上新增 `Database get database`**：實作簡單，但讓一個本來與儲存技術無關的圖書庫介面洩漏 SQL 專屬型別，破壞抽象目的（即使目前唯一實作是 SQLite）。予以排除，改用與 `repository`/`importService` 一致的「平行建構子參數」既有慣例。

## 後果

- `ReaderScreen` 的公開契約從 1 個必要參數擴充為 3 個；`CLAUDE.md`「唯一的閱讀器 seam」段落需同步更新描述。
- `main.dart`／`ElinkBookApp`／`LibraryScreen`／`LibraryScreen._openBook` 皆需同步新增/傳遞 `prefsRepository` 參數。
- 既有的 `app/test/screens/reader_screen_test.dart`／`app/integration_test/reader_screen_test.dart` 中所有 `ReaderScreen(filePath: ...)` 呼叫都需要補上 `bookId:`／`prefsRepository:` 參數，即使測試情境本身不涉及版面偏好設定的讀寫（例如「不支援格式」測試案例）；測試中的 `prefsRepository` 可用 `sqflite_common_ffi` 的記憶體資料庫建構一個真實但空的 `BookReaderPrefsRepository` 實例，不需要 mock。
