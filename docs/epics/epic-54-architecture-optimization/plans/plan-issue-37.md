# Issue 37 實作計畫：書籍格式能力收攏

設計決策見 `epic.md`「Issue 37 設計決策」。本計畫只列施工步驟。

## 現況（2026-11-14 讀碼確認）

- 兩個 enum：`BookFormat { epub, pdf, azw3, cbz, txt, md, unknown }`（`reader/book_format.dart`）與持久化的 `BookFileFormat { epub, pdf, txt, azw3, cbz, md }`（`library/models/library_enums.dart`，經 `values.byName` 寫進資料庫與同步，**成員名稱不可改**）。
- 偵測副檔名／MIME 的實作：`detectBookFormat`、`detectBookFileFormat`（`book_import_service_impl.dart:39`）、`detectCloudFileFormat`（`cloud_storage_client.dart:108`）、`OpdsFeedParser._detectFormat`／`_formatFromMimeType`（`opds_feed_parser.dart:185`）、`fileExtensionFor`（`opds_client.dart:33`）、Drive 查詢字串（`google_drive_storage_client.dart:45`）、選檔器 `['epub',…]`（`book_import_picker_helper.dart:35`）、暫存掃除 `['epub',…]`（`book_import_service_impl.dart:704`）。
- 落地複本條件 `epub||pdf||azw3` 在 `book_import_service_impl.dart` 寫 4 次（`_relinkableFormats` :318、:515、:844、:992）。
- `BookFormat`／`isFoliateFormat` 在 `lib/` 共 110 處引用（`reader_screen.dart` 78、`reading_position_saver.dart` 8、`engine_dispatch.dart` 8、`reader_surface_factory.dart` 5、其餘 11）。`reader_screen.dart:1478 _toBookFileFormat` 手動橋接兩個 enum。

## 目標 interface（`app/lib/library/book_file_format.dart`）

```dart
enum BookEngine { pdf, foliate }
enum LocatorKind { cfi, pdfPage }

/// 偵測：副檔名（取最後一段路徑、percent-decode、不分大小寫）；認不出回 null。
BookFileFormat? detectBookFileFormat(String uriOrPath);
/// 雲端／OPDS：副檔名優先，副檔名認不出才看 MIME。
BookFileFormat? detectBookFileFormatByNameAndMime(String name, String? mimeType);

extension BookFileFormatCapabilities on BookFileFormat {   // 窮舉 switch
  BookEngine get engine;
  LocatorKind get locatorKind;
  bool get landsLocalCopy;     // epub／pdf／azw3：可維持原位址或落地私有複本
  bool get isRelinkable;       // 同 landsLocalCopy
  bool get synthesizesEpub;    // txt／md
  String get fileExtension;    // 取代 fileExtensionFor
}
extension BookFileFormatNullable on BookFileFormat? {      // null＝不支援／尚未偵測
  bool get usesFoliate;        // 取代 isFoliateFormat
  bool get isPdf;
}
const List<String> kSupportedBookExtensions;               // 選檔器與暫存掃除共用
```

`BookFormat` 整個移除；原本傳 `BookFormat` 的地方改傳 `BookFileFormat?`，`unknown` 換成 `null`。

## Task 1：格式能力 module（TDD）

- [x] 1.1 寫 `test/library/book_file_format_test.dart`（紅）：6 格式副檔名偵測（大小寫、`content://` 帶百分比編碼檔名、`.mdx` 不誤判、無副檔名／空字串回 null）；MIME 偵測（含 `text/markdown`、cbz 兩種 MIME、azw3 兩種 MIME）；**副檔名優先於 MIME**：`notes.md`＋`text/plain` → md、`a.epub`＋`text/plain` → epub、無副檔名＋`text/plain` → txt；能力表（每格式的 engine／locatorKind／landsLocalCopy／synthesizesEpub／fileExtension）；一致性：遍歷 `BookFileFormat.values`，`detect('x.${f.fileExtension}') == f`、`kSupportedBookExtensions` 含全部 `fileExtension`、能力不拋例外。
- [x] 1.2 實作 `book_file_format.dart`（綠）。
- [x] 1.3 驗證：`flutter test test/library/book_file_format_test.dart`

## Task 2：偵測與雲端／OPDS／選檔器消費者

- [x] 2.1 `book_import_service_impl.dart`：`detectBookFileFormat` 搬走並由新 module 提供（保留 `detectImportFileFormat`，改呼叫新 module）；`_lastPathComponent` 隨偵測搬入；`book_file_format_detection.dart` 空殼刪除並更新 import；`_sweepStagingFiles` 與選檔器清單改用 `kSupportedBookExtensions`。
- [x] 2.2 `cloud_storage_client.dart` 的 `detectCloudFileFormat` 改為呼叫 `detectBookFileFormatByNameAndMime`（保留函式名稱供既有呼叫端，避免擴大異動）；`OpdsFeedParser._detectFormat` 同樣改用，路徑取自 `Uri.tryParse(href)?.path`；`fileExtensionFor` 改為 `format.fileExtension`。
- [x] 2.3 `google_drive_storage_client.dart`：伺服器端篩選不再靠 MIME 才列 `.txt`——查詢字串由副檔名 `name contains '.xxx'`（全部支援副檔名）加資料夾與標準 MIME 組成（由新 module 的副檔名清單生成）。
- [x] 2.4 刪除或改寫被取代的舊偵測測試（`book_import_service_test.dart` 的偵測部分、`cloud_storage_client_test.dart` 的偵測部分）；其有價值的案例搬進 Task 1 的測試。
- [x] 2.5 驗證：`flutter test test/library test/cloud_import test/remote test/wifi_transfer test/screens/support`

## Task 3：讀者端改用 `BookFileFormat?`

- [x] 3.1 `engine_dispatch.dart`、`reading_position_saver.dart`、`reader_surface_factory.dart`、`reading_session.dart`、`reader_jump_target.dart`、`toc_bottom_sheet.dart` 的 `BookFormat` 改為 `BookFileFormat?`；`unknown` 分支改 `null`；窮舉 `switch` 保留。
- [x] 3.2 `reader_screen.dart`：`detectBookFormat(path)` → `detectBookFileFormat(path)`；`isFoliateFormat(f)` → `f.usesFoliate`；`f == BookFormat.pdf` → `f.isPdf`；刪除 `_toBookFileFormat`；`:1620 [format.name]` 改為 `[format!.fileExtension]`（原註解指明只有 epub／pdf／azw3 會走到，名稱即副檔名，行為不變）。
- [x] 3.3 刪除 `reader/book_format.dart` 與 `test/reader/book_format_test.dart`（案例已搬進 Task 1），修正全部受影響的測試（`engine_dispatch_test`、`reading_position_saver_test`、`reader_surface_factory_test` 等）。
- [x] 3.4 驗證：`flutter test test/reader test/screens/reader_screen_test.dart`

## Task 4：落地複本與 relink 改用能力

- [x] 4.1 `book_import_service_impl.dart`：`_relinkableFormats` 與 :515、:844、:992 三處 `epub||pdf||azw3` 改為 `format.landsLocalCopy`／`format.isRelinkable`；`_prepareBookParts` 內判斷 txt／md 的地方可用 `synthesizesEpub`，但**不重構分支梯**（屬候選 4，另案）。
- [x] 4.2 驗證：`flutter test test/library/book_import_service_test.dart test/library/book_relink_test.dart`（以實際檔名為準）

## Task 5：收尾（整張計畫最後一個 Task）

- [x] 5.1 `flutter analyze` 乾淨；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`。
- [x] 5.2 完整 `flutter test`（無參數）。
- [x] 5.3 更新 `epic.md` 開發記錄、`issues.md` Issue 37 狀態。

## 實作時與原計畫的差異

- 能力 `landsLocalCopy`／`isRelinkable` 兩者在讀碼後確認是同一個集合（epic-15 以來的 `epic／pdf／azw3`），合併為單一 `keepsOriginalSource`（原始檔本身就是閱讀用檔案），避免兩個同義 getter。
- `detectCloudFileFormat`、`fileExtensionFor` 不保留 wrapper，直接移除，呼叫端改用 `detectBookFileFormatByNameAndMime`／`format.fileExtension`。
- `detectImportFileFormat` 與公開的 `lastPathComponentOfUri`（供 `titleFromFileName` 使用）一併搬進新 module；`book_file_format_detection.dart` 空殼刪除。
- WiFi 傳書的 `bookFileFormatForFileName` 改為直接呼叫 `detectBookFileFormat`（原本反查 `fileExtensionFor`，不另維護白名單的意圖不變）。
- Drive 查詢：保留標準 MIME 子句，另外加上全部支援副檔名的 `name contains`（聯集，只會多列、不會少列）。
- `lib/l10n/app_zh_TW.arb` 與產生檔 `app_localizations.dart` 的一則說明文字仍提到 `BookFormat.unknown`；那是 l10n 描述字串，改動需重新產生，未動。

## 範圍外（見 `epic.md`）

`sync_table_specs.dart` 與 SQL 內 `'pdf'`／`'cbz'` 字串；固定版面執行期判定（候選 3）；`_prepareBookParts` 分支梯（候選 4）；`local_book_server.dart` 的內容 MIME（`windows_reader_resources.dart` 的那份已於 Issue 36 刪除）。

## 風險

- 行為變更：雲端／OPDS 改「副檔名優先」，`notes.md`（MIME `text/plain`）由 txt 變 md；Drive 的 `.txt` 不再因 MIME 為 `application/octet-stream` 而漏列。
- `BookFileFormat` 成員名稱與順序都不動，資料庫與同步不受影響。
- 110 處引用的機械式改型別；以 `flutter analyze` 與兩輪測試把關。
