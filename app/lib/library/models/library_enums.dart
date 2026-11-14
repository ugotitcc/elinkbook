/// 書籍的檔案格式（FR-01 支援格式，CBZ 由 epic-11 Issue 3 補上）。經
/// `values.byName` 寫進資料庫與同步，**成員名稱不可改**。「不支援／尚未偵測」
/// 以 `null` 表示，不放進這個 enum。偵測與各格式的靜態事實（引擎、座標型別、
/// 副檔名…）見 `library/book_file_format.dart`（epic-54 Issue 37）。
enum BookFileFormat { epub, pdf, txt, azw3, cbz, md }

/// 書籍的匯入來源。本 epic（epic-1-library）僅會產生 [local]；
/// [googleDrive]/[oneDrive] 為後續雲端匯入 Epic 預留的欄位。
enum BookSource { local, googleDrive, oneDrive, calibreOpds }

/// 書架排序方式（FR-26）。
enum LibrarySortBy { lastRead, createTime, author, title }

/// 書架檢視模式（FR-03）。切換按鈕與畫面渲染分支屬於本 issue（Issue 5）；
/// 選擇的持久化（`SharedPreferences`，App 重啟後記住上次選擇）屬於 Issue 6。
enum LibraryViewMode { grid, list }
