# Task 3 報告：`BookImportService` 介面與 `BookImportServiceImpl` 匯入管線

## 實作內容

依 `.superpowers/sdd/task-3-brief.md` 的 Step 1–7 逐步完成：

1. `app/lib/library/book_import_service.dart`：抽象介面 `BookImportService`，含 `importFiles(uris, {folderName})` 與 `importFolder(folderUri, {autoGroupByFolderName})`。
2. `app/test/library/book_import_service_test.dart`：9 個測試案例（詳見下方測試結果），實際使用 `SqliteLibraryRepository.open(inMemoryDatabasePath)`（in-memory sqflite ffi），只 mock 原生 `elinkbook/book_metadata` channel（`TestDefaultBinaryMessengerBinding`），未使用任何手寫假 repository。
3. `app/lib/library/book_import_service_impl.dart`：`BookImportServiceImpl` 具體實作，以及頂層函式 `detectBookFileFormat`/`titleFromFileName`。管線邏輯：
   - `content://` URI 先呼叫 `takePersistableUriPermission`；`PlatformException` 時整檔略過（不寫入資料庫）。
   - 依副檔名（percent-decode 後取最後路徑片段）判斷格式；未知副檔名整檔略過。
   - TXT：不呼叫 `extractMetadata`，改用 Task 2 的 `generateTxtCover(fallbackTitle)` 產生封面。
   - EPUB/PDF：呼叫 `extractMetadata(uri, format)`；標題為空/null 時降級用檔名；`PlatformException` 時整批不中斷，該筆降級為「檔名標題、無封面」但仍寫入資料庫。
   - 封面 PNG 落地至 `coversDirectory ?? getApplicationDocumentsDirectory()/covers`。
   - `folderName` 非 null 時先 `upsertGroup`，寫入的 `Book.groupName` 對應該資料夾名稱；否則歸入 `BookGroup.uncategorized`。
   - `importFolder` 直接拋出 `UnimplementedError`（Issue 8 範圍）。

### 與 brief 的一處落差（已修正）

brief 原始程式碼（介面/實作/測試三檔）皆 `import 'dart:typed_data'`，但 `Uint8List` 已透過 `package:flutter/services.dart` 透傳，`flutter analyze` 對此兩處各回報一則 `unnecessary_import`（info）。專案 `CLAUDE.md` 與本 brief Step 6 都明確要求 `flutter analyze` 需為 `No issues found!`，因此移除了 `book_import_service_impl.dart` 與 `book_import_service_test.dart` 中多餘的 `dart:typed_data` import（`Uint8List` 用法不變，仍透過 `flutter/services.dart` 取得）。此為本任務唯一偏離 brief 逐字程式碼之處，且不影響任何行為或測試結果。

## 測試結果

### RED（Step 3，實作檔案不存在時）

```
00:00 +0: loading .../test/library/book_import_service_test.dart
test/library/book_import_service_test.dart:7:8: Error: Error when reading 'lib/library/book_import_service_impl.dart': 系統找不到指定的檔案。
import 'package:elinkbook/library/book_import_service_impl.dart';
       ^
test/library/book_import_service_test.dart:23:8: Error: 'BookImportServiceImpl' isn't a type.
  late BookImportServiceImpl service;
       ^^^^^^^^^^^^^^^^^^^^^
test/library/book_import_service_test.dart:29:9: Error: Method not found: 'BookImportServiceImpl'.
        BookImportServiceImpl(repository: repository, coversDirectory: coversDir);
        ^^^^^^^^^^^^^^^^^^^^^
00:00 +0 -1: loading .../test/library/book_import_service_test.dart [E]
  Failed to load "...book_import_service_test.dart":
  Compilation failed for testPath=...book_import_service_test.dart: ...
00:00 +0 -1: Some tests failed.
```

### GREEN（Step 5，實作完成後，含 import 清理後的最終版本）

```
00:00 +0: loading .../test/library/book_import_service_test.dart
00:00 +0: (setUpAll)
00:00 +0: 匯入 EPUB 檔案呼叫 extractMetadata(format: epub) 並寫入正確詮釋資料
00:00 +1: 匯入 PDF 檔案呼叫 extractMetadata(format: pdf)，詮釋資料無標題時降級為檔名
00:00 +2: 匯入 TXT 檔案不呼叫 extractMetadata，改用 Dart 端動態產生封面
00:00 +3: 詮釋資料提取失敗時降級寫入：標題=檔名、coverPath=null，不中斷整批匯入
00:00 +4: 匯入成功的書籍 source 為 local，filePath 存放原始 URI（未被複製）
00:00 +5: 不支援的副檔名略過該檔案，不中斷整批匯入
00:00 +6: takePersistableUriPermission 失敗時略過該檔案，不寫入資料庫、不中斷整批匯入
00:00 +7: 指定 folderName 時自動建立分類並歸入，書籍 groupName 對應資料夾名稱
00:00 +8: importFolder 尚未實作，呼叫時拋出 UnimplementedError
00:00 +9: (tearDownAll)
00:00 +9: All tests passed!
```

### 完整測試套件（Step 6）

```
00:00 +0: loading .../test/library/book_import_service_test.dart
00:00 +0: (setUpAll)
00:00 +0: .../test/library/models/book_test.dart: Book toMap/fromMap 往返後所有欄位值不變
00:00 +1..+8: .../test/library/book_import_service_test.dart 9 個測試案例全數通過
00:00 +8: .../test/library/sqlite_library_repository_test.dart: (setUpAll)
00:00 +11..+32: sqlite_library_repository_test.dart 各項測試（insertBook/listBooks 排序與篩選/群組管理等）全數通過
00:01 +20..+31: txt_cover_generator_test.dart 各項測試全數通過
00:01 +32..+38: navigation_test.dart 全數通過
00:03 +39: library_screen_test.dart 通過
00:03 +40: reader_screen_test.dart 通過
00:03 +41: settings_screen_test.dart 通過
00:03 +42: All tests passed!
```

### `flutter analyze`（Step 6）

修正 `unnecessary_import` 前：
```
Analyzing app...
   info - The import of 'dart:typed_data' is unnecessary ... - lib\library\book_import_service_impl.dart:2:8 - unnecessary_import
   info - The import of 'dart:typed_data' is unnecessary ... - test\library\book_import_service_test.dart:2:8 - unnecessary_import
2 issues found. (ran in 2.4s)
```

修正後：
```
Analyzing app...
No issues found! (ran in 2.4s)
```

## 變更檔案

- `app/lib/library/book_import_service.dart`（新增）
- `app/lib/library/book_import_service_impl.dart`（新增）
- `app/test/library/book_import_service_test.dart`（新增）

## Commit

`fd052a2` — `Add BookImportService with importFiles pipeline (EPUB/PDF/TXT)`

## 自我審查

- **完整性**：9 項測試案例（EPUB 詮釋資料、PDF 詮釋資料+標題降級、TXT 不呼叫原生、詮釋資料失敗降級寫入、source=local/filePath=原始URI、不支援副檔名略過、權限失敗略過、folderName 自動分類、importFolder 拋出 UnimplementedError）全數存在且通過。
- **品質**：`_importSingleFile` 對「略過」（回傳 `null`：格式未知、`takePersistableUriPermission` 失敗）與「降級寫入」（仍回傳 `Book`：`extractMetadata` 的 `PlatformException`）的區分正確——分別對應「不可假裝成功寫入可能失效的 filePath」與「單檔詮釋資料失敗不應中斷整批匯入」兩種不同語意。
- **紀律**：`BookImportServiceImpl` 未匯入或呼叫 `file_picker`；未修改任何 Issue 1/2/3 已合併檔案（`library_repository.dart`、`sqlite_library_repository.dart`、`models/*.dart`、`txt_cover_generator.dart` 均維持原樣，僅新增三個檔案）。
- **測試方式**：測試使用真實 `SqliteLibraryRepository.open(inMemoryDatabasePath)`（sqflite_common_ffi in-memory），僅透過 `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler` mock 原生 `elinkbook/book_metadata` channel，未使用手寫假 repository。

## 疑慮

無重大疑慮。唯一偏離 brief 逐字程式碼之處是移除兩個檔案中多餘的 `dart:typed_data` import（見上方「與 brief 的一處落差」），純為滿足 `flutter analyze` 的 `No issues found!` 要求，不影響任何行為。

另外附註：本 worktree 內 `.superpowers/sdd/task-3-report.md` 原本存放的是一份與本任務無關的舊內容（看起來是另一個 epic/task 編號重複使用同一路徑所留下的殘留檔案，內容為「閱讀器直橫排排版與邊距微調面板」），已依本次任務要求覆寫為此份報告；`task-4-report.md` 也存在類似看似不相關的殘留檔案，但本任務未觸碰該檔案，僅供留意。
