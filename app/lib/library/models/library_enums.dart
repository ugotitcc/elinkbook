/// 圖書庫書籍的檔案格式。獨立於 `reader/book_format.dart` 的 `BookFormat`——
/// 後者只服務 `ReaderScreen` 的原生渲染分派（目前僅 epub/pdf 有對應原生
/// 視圖）；圖書庫資料層需要完整表達 FR-01 的三種支援格式（含尚未有渲染
/// 引擎的 TXT，由 epic-11-txt-engine 補上），因此另外定義、不與其共用。
enum BookFileFormat { epub, pdf, txt }

/// 書籍的匯入來源。本 epic（epic-1-library）僅會產生 [local]；
/// [googleDrive]/[oneDrive] 為後續雲端匯入 Epic 預留的欄位。
enum BookSource { local, googleDrive, oneDrive }

/// 書架排序方式（FR-26）。
enum LibrarySortBy { lastRead, createTime, author, title }

/// 書架檢視模式（FR-03）。切換按鈕與畫面渲染分支屬於本 issue（Issue 5）；
/// 選擇的持久化（`SharedPreferences`，App 重啟後記住上次選擇）屬於 Issue 6。
enum LibraryViewMode { grid, list }
