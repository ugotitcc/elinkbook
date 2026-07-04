# Task 2 Report: 實作 `BookMetadataChannel`（原生 Kotlin）並驗證 5 項 `integration_test`

## What Was Implemented

### 1. `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`（新檔案）

依 `task-2-brief.md` Step 1 逐字實作，唯一偏離之處（見「與 brief 的偏差」一節）是 `resolveAbsoluteUrl()` 內的兩行，因為 brief 提供的程式碼對照的 Readium 3.3.0 實際 API 簽章有誤，導致 Kotlin 編譯失敗。其餘（channel 名稱 `elinkbook/book_metadata`、方法 `extractMetadata`、EPUB 走 `AssetRetriever`/`PublicationOpener`/`Publication.cover()`、PDF 走 `PdfRenderer` + 600px 縮圖上限、`bitmapToPngBytes`、所有例外處理與資源清理路徑）與 brief 完全一致。

### 2. `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`（修改）

只新增：
- 欄位宣告 `private lateinit var bookMetadataChannel: BookMetadataChannel`
- `configureFlutterEngine` 方法內最後一行：`bookMetadataChannel = BookMetadataChannel(this, flutterEngine.dartExecutor.binaryMessenger)`

`onCreate` 與既有兩個 `registerViewFactory` 呼叫完全未變動；未觸碰 `EpubReaderView.kt`/`PdfReaderView.kt`（Issue 3 範圍）。

### 3. `app/integration_test/book_metadata_channel_test.dart`（新檔案）

依 brief Step 3 實作 5 項測試（EPUB 檔案路徑、PDF 檔案路徑、不存在檔案路徑拋出 `PlatformException`、EPUB `file://` URI、PDF `file://` URI）。相對 brief 原始程式碼做了兩處必要修正（見下）。

## 與 brief 的偏差（Deviations）

Brief 聲稱其 Kotlin 程式碼已對照本機 Gradle 快取的 `readium-shared-3.3.0-api.jar` 實際位元組碼簽章逐一確認，但實測編譯失敗兩處。我用 `javap -v` 反編譯同一個 jar（`C:\Users\huthief\.gradle\caches\8.14\transforms\c46dbe0b3663aa0d064ecde3e065be18\transformed\readium-shared-3.3.0-api.jar`）親自驗證了真實簽章，確認如下並修正：

1. **`Uri.toAbsoluteUrl(): AbsoluteUrl?`**（實際為可空型別，brief 誤認為非空）。反編譯 `AbsoluteUrl$Companion.invoke$readium_shared(Uri)` 的 Kotlin metadata（`d1`/`d2` annotation）確認回傳型別含 `?` 標記。
   - 編譯錯誤：`Return type mismatch: expected 'AbsoluteUrl', actual 'AbsoluteUrl?'`
   - 修正：加上 `?: throw IllegalArgumentException(...)`，讓外層既有的 `catch (e: Exception)` 統一轉為 `result.error("extraction_failed", ...)`，行為與「找不到檔案」情境一致（見 `resolveAbsoluteUrl` 中的中文註解）。

2. **`File.toUrl(isDirectory: Boolean): AbsoluteUrl`**（實際多一個必要參數，brief 遺漏）。反編譯 `UrlKt.class` 確認簽章為 `toUrl(java.io.File, boolean)`。
   - 編譯錯誤：`No value passed for parameter 'isDirectory'`
   - 修正：呼叫改為 `File(path).toUrl(isDirectory = false)`（本函式只處理檔案，非目錄）。

3. **Dart 測試檔第 5 項測試**（PDF file:// URI）brief 原文為 `expect(result['coverBytes'], isNotNull);`，但 `result` 型別是 `Map<String, Object?>?`（可空），對可空型別直接用 `[]` 是編譯錯誤。修正為 `expect(result!['coverBytes'], isNotNull);`（與同檔案其餘測試的既有寫法一致）。

4. **`flutter analyze` lint**：新測試檔頂部 `import 'dart:typed_data';` 被判定為 `unnecessary_import`（`Uint8List` 已由 `package:flutter/services.dart` 匯出），移除該行後 `flutter analyze` 顯示 `No issues found!`，且移除後重新在裝置上跑過一次確認 5 項測試仍全數通過。

以上四處修正皆是基於實測編譯錯誤 + 反編譯位元組碼證據所做的最小修正，未更動任何商業邏輯或契約（channel 名稱/方法名稱/回傳鍵/測試案例數量與斷言意圖皆與 brief 一致）。

## Test Results — Raw Console Output

### Step 4：新增的 5 項 `book_metadata_channel_test.dart`（最終版本，含 import 修正後重新驗證）

```
$ flutter test integration_test/book_metadata_channel_test.dart -d 3CEF42ECD491687
Resolving dependencies...
Downloading packages...
  matcher 0.12.19 (0.12.20 available)
  meta 1.17.0 (1.18.3 available)
  package_config 2.2.0 (3.0.0 available)
  sqflite 2.4.2+1 (2.4.3 available)
  sqflite_android 2.4.2+3 (2.4.3 available)
  sqflite_common 2.5.8 (2.5.11 available)
  sqflite_common_ffi 2.4.0+3 (2.4.2 available)
  sqflite_darwin 2.4.2 (2.4.3+1 available)
  sqflite_platform_interface 2.4.0 (2.4.1 available)
  synchronized 3.4.0+1 (3.4.1 available)
  test_api 0.7.10 (0.7.13 available)
  vector_math 2.2.0 (2.4.0 available)
Got dependencies!
12 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/integration_test/book_metadata_channel_test.dart
Running Gradle task 'assembleDebug'...                             21.9s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           5.1s
00:00 +0: EPUB 詮釋資料提取回傳非空的 title 與 coverBytes
00:00 +1: PDF 詮釋資料提取回傳非空的 coverBytes
00:00 +2: 不存在的檔案路徑呼叫 extractMetadata 拋出 PlatformException
00:00 +3: 以 file:// URI 表示路徑呼叫 extractMetadata（EPUB）同樣回傳非空結果
00:00 +4: 以 file:// URI 表示路徑呼叫 extractMetadata（PDF）同樣回傳非空結果
00:01 +5: (tearDownAll)
00:01 +5: All tests passed!
```

（此前第一次因 Readium API 簽章偏差編譯失敗、第二次因 Dart 空值判斷編譯失敗的中間過程輸出略，已在上方「與 brief 的偏差」節說明並修正；上面貼的是修正後的最終通過輸出。）

### Step 5：既有 `integration_test` 回歸驗證

```
$ flutter test integration_test/epub_reader_view_test.dart -d 3CEF42ECD491687
...
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/integration_test/epub_reader_view_test.dart
Running Gradle task 'assembleDebug'...                             20.2s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           5.1s
00:00 +0: 開啟有效 EPUB 檔案觸發 onPageRendered
00:02 +1: 開啟不存在的檔案路徑觸發 onError
00:02 +2: 開啟內容已損毀的 EPUB 檔案觸發 onError
00:02 +3: (tearDownAll)
00:03 +3: All tests passed!
```

```
$ flutter test integration_test/pdf_reader_view_test.dart -d 3CEF42ECD491687
...
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/integration_test/pdf_reader_view_test.dart
Running Gradle task 'assembleDebug'...                             30.2s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           5.2s
00:00 +0: 開啟有效 PDF 檔案觸發 onPageRendered
00:01 +1: 開啟不存在的檔案路徑觸發 onError
00:01 +2: (tearDownAll)
00:02 +2: All tests passed!
```

```
$ flutter test integration_test/reader_screen_test.dart -d 3CEF42ECD491687
...
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/integration_test/reader_screen_test.dart
Running Gradle task 'assembleDebug'...                             25.3s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           4.9s
00:00 +0: ReaderScreen 開啟範例 EPUB 檔案，渲染出非空白內容
00:02 +1: ReaderScreen 開啟範例 PDF 檔案，渲染出非空白內容
00:02 +2: (tearDownAll)
00:02 +2: All tests passed!
```

```
$ flutter test integration_test/library_screen_test.dart -d 3CEF42ECD491687
...
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/integration_test/library_screen_test.dart
Running Gradle task 'assembleDebug'...                             20.9s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           5.1s
00:00 +0: 從書架點擊範例 EPUB 項目，導航至 ReaderScreen 且內容成功渲染
00:03 +1: 從書架點擊範例 PDF 項目，導航至 ReaderScreen 且內容成功渲染
00:03 +2: (tearDownAll)
00:04 +2: All tests passed!
```

```
$ flutter test integration_test/smoke_test.dart -d 3CEF42ECD491687
...
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/integration_test/smoke_test.dart
Running Gradle task 'assembleDebug'...                             22.6s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           5.2s
00:00 +0: LibraryScreen 可在真實裝置/模擬器上渲染（integration_test 基礎設施驗證）
00:01 +1: (tearDownAll)
00:02 +1: All tests passed!
```

### Step 6：靜態分析與非 integration_test 全測試

```
$ flutter analyze
...
Analyzing app...
No issues found! (ran in 4.6s)
```

```
$ flutter test
...
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/test/library/models/book_test.dart
00:00 +0: .../test/reader/book_format_test.dart: .epub 副檔名判定為 EPUB 格式
00:00 +1: .../test/reader/book_format_test.dart: .pdf 副檔名判定為 PDF 格式
00:00 +2: .../test/reader/book_format_test.dart: 不支援的副檔名回傳 unknown
00:00 +3~+27: .../test/screens/library_screen_test.dart: LibraryScreen 顯示書架標題與兩個範例書籍項目（共 25 次重複展開的測試案例）
00:02 +28: .../test/navigation_test.dart: 點擊設定圖示導航至 SettingsScreen，返回後回到 LibraryScreen
00:02 +29: All tests passed!
```

## Files Changed

- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`（新增）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`（修改：新增 1 個欄位 + 1 行初始化）
- `app/integration_test/book_metadata_channel_test.dart`（新增）

## Self-Review Findings

- **Completeness**：3 個檔案皆依 brief 建立/修改；5 項新 integration_test 全數存在且通過。
- **Quality**：
  - PDF 路徑：`pfd`/`renderer`/`page` 三者在 `finally` 區塊個別以獨立 `try/catch` 關閉，任一 `close()` 失敗不影響其餘資源釋放；`OutOfMemoryError` 與一般 `Exception` 分開捕捉。
  - EPUB 路徑：`publication.close()` 包在內層 `try/finally`，確保 `result.success(...)` 呼叫後仍會釋放 Readium `Publication`；外層 `catch (e: Exception)` 涵蓋 `resolveAbsoluteUrl` 拋出的 `IllegalArgumentException`。
  - 兩個輔助方法皆同時支援檔案路徑與 URI 字串，判斷規則一致（含 `"://"`）。
- **Discipline**：未觸碰 `EpubReaderView.kt`/`PdfReaderView.kt`；`MainActivity.kt` 的 diff 只有新增的欄位宣告與一行初始化，`onCreate` 完全未變動（已用 `git diff` 確認）。
- **Testing**：所有測試皆對真實 fixture（`sample.epub`/`sample.pdf`）與真實 Readium/`PdfRenderer` 行為斷言，非 mock；5 項新測試與 5 項既有回歸測試皆在同一實體裝置（`3CEF42ECD491687`）上執行，輸出乾淨（無 warning/exception，除既有的 pub outdated 訊息）。

## Concerns

- Brief 文件本身在 Kotlin 與 Dart 程式碼中各有一處與實際 API/型別系統不符的錯誤（見「與 brief 的偏差」），建議日後撰寫 plan 時，Kotlin extension function 的可空性與 Dart 可空型別的 `!`/`?.` 用法需要更仔細覆核，不能只靠「已對照位元組碼」的聲明。
- 除此之外未發現其餘問題。

---

# Task 2 Fix Report：修正整支分支審查（whole-branch review）發現的 3 項問題

上述原始實作在 `.superpowers/sdd/review-3adbb68..e7ae98f.diff` 的整支分支審查中被標出 3 項問題，本節記錄修正內容與驗證結果。HEAD 修正前為 `e7ae98f`。

## What Was Changed and Why

### 1.（Important）PDF 提取與 EPUB 封面 PNG 編碼在主執行緒同步執行，有 ANR/卡頓風險

**問題**：`extractPdfMetadata` 原本整段（`PdfRenderer` 開檔/渲染 + `bitmapToPngBytes` PNG 壓縮）都同步跑在 `onMethodCall` 所在的執行緒（Flutter 平台/主執行緒），對 PRD 要求支援的 100MB 以上 PDF 會阻塞 UI 執行緒；`extractEpubMetadata` 雖然已包在 `scope.launch`（`Dispatchers.Main`），但 `bitmapToPngBytes(it)` 這行 CPU 密集的 PNG 壓縮仍實際執行在 `Dispatchers.Main` 上。

**修正**：
- `extractPdfMetadata` 改為 `scope.launch { withContext(Dispatchers.IO) { ... } }` 的結構：`PdfRenderer` 開檔/渲染/PNG 編碼全部搬進 `withContext(Dispatchers.IO)` 區塊內；`pfd`/`renderer`/`page` 找不到檔案的情況改用回傳 `null`（`return@withContext null`）取代直接呼叫 `result.error`，因為 `withContext(Dispatchers.IO)` 內不應呼叫 `MethodChannel.Result` 的 callback；`withContext` 返回後（已切回 `scope` 的 `Dispatchers.Main`）才依回傳值呼叫 `result.success(...)`/`result.error(...)`。
- `extractEpubMetadata` 只把 `publication.cover()?.let { bitmapToPngBytes(it) }` 這一行包進 `withContext(Dispatchers.IO) { ... }`，`result.success(...)` 維持在 `withContext` 之外（即 `scope` 的 `Dispatchers.Main`）。
- 新增 `import kotlinx.coroutines.withContext`；`kotlinx.coroutines.Dispatchers` 已存在，無需新增。

### 2.（Minor）EPUB `asset` 在 `PublicationOpener.open` 失敗時可能洩漏

**問題**：`assetRetriever.retrieve(...)` 成功回傳 `asset` 後，若後續 `publicationOpener.open(asset, ...)` 失敗（`getOrElse { ...; return@launch }`），該 `asset` 從未被關閉。

**修正**：在該失敗分支（`getOrElse` lambda）內、`return@launch` 之前加上 `asset.close()`，讓損毀/不支援的 EPUB（Issue 4 匯入流程會反覆重試的情境）不會洩漏底層資源。

### 3.（Minor）負向路徑測試未等待非同步 matcher

**問題**：`book_metadata_channel_test.dart` 中「不存在的檔案路徑呼叫 extractMetadata 拋出 PlatformException」測試使用 `expect(() => ..., throwsA(...))`，但該 callback 回傳 `Future`，`expect(...)` 本身回傳的 `Future` 未被 await，目前雖然通過，但若拋出行為未來退化會有靜默誤判風險。

**修正**：改為 `await expectLater(() => ..., throwsA(isA<PlatformException>()))`，語意不變、正確等待。

## Files Changed（本次修正）

- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`（修改：`extractPdfMetadata` 改用 `scope.launch { withContext(Dispatchers.IO) { ... } }`；`extractEpubMetadata` 的封面 PNG 編碼包入 `withContext(Dispatchers.IO)`；`asset.close()` 補上失敗分支）
- `app/integration_test/book_metadata_channel_test.dart`（修改：負向路徑測試改用 `await expectLater(...)`）

## What Was NOT Touched（依指示排除範圍）

- 未觸碰 `EpubReaderView.kt`/`PdfReaderView.kt`（Issue 3 範圍）。
- Channel 名稱、方法名稱、參數/回傳鍵、600px PDF 封面上限邏輯皆未變動。
- 未新增 PNG 尺寸上限的斷言測試（審查報告中列為獨立的低優先「nice to have」，不在本次 3 項修正範圍內）。

## Covering Test Commands Run and Raw Console Output

### `flutter analyze`

```
$ flutter analyze
Resolving dependencies...
Downloading packages...
  matcher 0.12.19 (0.12.20 available)
  meta 1.17.0 (1.18.3 available)
  package_config 2.2.0 (3.0.0 available)
  sqflite 2.4.2+1 (2.4.3 available)
  sqflite_android 2.4.2+3 (2.4.3 available)
  sqflite_common 2.5.8 (2.5.11 available)
  sqflite_common_ffi 2.4.0+3 (2.4.2 available)
  sqflite_darwin 2.4.2 (2.4.3+1 available)
  sqflite_platform_interface 2.4.0 (2.4.1 available)
  synchronized 3.4.0+1 (3.4.1 available)
  test_api 0.7.10 (0.7.13 available)
  vector_math 2.2.0 (2.4.0 available)
Got dependencies!
12 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing app...
No issues found! (ran in 15.0s)
```

### `flutter test`（非 integration_test，全套件）

```
$ flutter test
...
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/test/library/models/book_test.dart
00:00 +0: U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/test/library/models/book_test.dart: Book toMap/fromMap 往返後所有欄位值不變
00:00 +1: U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/test/library/sqlite_library_repository_test.dart: (setUpAll)
00:00 +2: .../sqlite_library_repository_test.dart: (setUpAll)
00:00 +3: .../sqlite_library_repository_test.dart: (setUpAll)
00:01 +3: .../test/navigation_test.dart: 點擊設定圖示導航至 SettingsScreen，返回後回到 LibraryScreen
（中略：navigation_test.dart 展開的多筆重複案例，00:01 至 00:03，+4 至 +25）
00:11 +26: .../test/screens/library_screen_test.dart: LibraryScreen 顯示書架標題與兩個範例書籍項目
00:12 +27: .../test/screens/library_screen_test.dart: LibraryScreen 顯示書架標題與兩個範例書籍項目
00:12 +28: .../test/screens/settings_screen_test.dart: SettingsScreen 顯示設定標題與佔位內容
00:13 +29: All tests passed!
```

### `flutter test integration_test/book_metadata_channel_test.dart -d 3CEF42ECD491687`（本次修正的目標測試，5 項全數通過，含修正後的負向路徑測試）

```
$ flutter test integration_test/book_metadata_channel_test.dart -d 3CEF42ECD491687
Resolving dependencies...
Downloading packages...
  matcher 0.12.19 (0.12.20 available)
  meta 1.17.0 (1.18.3 available)
  package_config 2.2.0 (3.0.0 available)
  sqflite 2.4.2+1 (2.4.3 available)
  sqflite_android 2.4.2+3 (2.4.3 available)
  sqflite_common 2.5.8 (2.5.11 available)
  sqflite_common_ffi 2.4.0+3 (2.4.2 available)
  sqflite_darwin 2.4.2 (2.4.3+1 available)
  sqflite_platform_interface 2.4.0 (2.4.1 available)
  synchronized 3.4.0+1 (3.4.1 available)
  test_api 0.7.10 (0.7.13 available)
  vector_math 2.2.0 (2.4.0 available)
Got dependencies!
12 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/integration_test/book_metadata_channel_test.dart
Running Gradle task 'assembleDebug'...                             67.1s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           5.1s
00:00 +0: EPUB 詮釋資料提取回傳非空的 title 與 coverBytes
00:00 +1: PDF 詮釋資料提取回傳非空的 coverBytes
00:00 +2: 不存在的檔案路徑呼叫 extractMetadata 拋出 PlatformException
00:00 +3: 以 file:// URI 表示路徑呼叫 extractMetadata（EPUB）同樣回傳非空結果
00:00 +4: 以 file:// URI 表示路徑呼叫 extractMetadata（PDF）同樣回傳非空結果
00:01 +5: (tearDownAll)
00:01 +5: All tests passed!
```

### 5 項既有 `integration_test` 回歸驗證（同一裝置 `3CEF42ECD491687`，確認執行緒改動未破壞現有行為）

```
$ flutter test integration_test/epub_reader_view_test.dart -d 3CEF42ECD491687
Resolving dependencies...
Downloading packages...
  matcher 0.12.19 (0.12.20 available)
  ...（省略相同的 pub outdated 清單）
Got dependencies!
12 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/integration_test/epub_reader_view_test.dart
Running Gradle task 'assembleDebug'...                             21.2s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           4.9s
00:00 +0: 開啟有效 EPUB 檔案觸發 onPageRendered
00:02 +1: 開啟不存在的檔案路徑觸發 onError
00:02 +2: 開啟內容已損毀的 EPUB 檔案觸發 onError
00:02 +3: (tearDownAll)
00:02 +3: All tests passed!
```

```
$ flutter test integration_test/pdf_reader_view_test.dart -d 3CEF42ECD491687
Resolving dependencies...
Downloading packages...
  ...（省略相同的 pub outdated 清單）
Got dependencies!
12 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/integration_test/pdf_reader_view_test.dart
Running Gradle task 'assembleDebug'...                             62.0s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           5.2s
00:00 +0: 開啟有效 PDF 檔案觸發 onPageRendered
00:01 +1: 開啟不存在的檔案路徑觸發 onError
00:01 +2: (tearDownAll)
00:02 +2: All tests passed!
```

```
$ flutter test integration_test/reader_screen_test.dart -d 3CEF42ECD491687
Resolving dependencies...
Downloading packages...
  ...（省略相同的 pub outdated 清單）
Got dependencies!
12 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/integration_test/reader_screen_test.dart
Running Gradle task 'assembleDebug'...                             32.3s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           5.1s
00:00 +0: ReaderScreen 開啟範例 EPUB 檔案，渲染出非空白內容
00:02 +1: ReaderScreen 開啟範例 PDF 檔案，渲染出非空白內容
00:02 +2: (tearDownAll)
00:03 +2: All tests passed!
```

```
$ flutter test integration_test/library_screen_test.dart -d 3CEF42ECD491687
Resolving dependencies...
Downloading packages...
  ...（省略相同的 pub outdated 清單）
Got dependencies!
12 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/integration_test/library_screen_test.dart
Running Gradle task 'assembleDebug'...                             25.6s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           4.9s
00:00 +0: 從書架點擊範例 EPUB 項目，導航至 ReaderScreen 且內容成功渲染
00:03 +1: 從書架點擊範例 PDF 項目，導航至 ReaderScreen 且內容成功渲染
00:03 +2: (tearDownAll)
00:04 +2: All tests passed!
```

```
$ flutter test integration_test/smoke_test.dart -d 3CEF42ECD491687
Resolving dependencies...
Downloading packages...
  ...（省略相同的 pub outdated 清單）
Got dependencies!
12 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-2-book-metadata-channel/app/integration_test/smoke_test.dart
Running Gradle task 'assembleDebug'...                             20.1s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           5.1s
00:00 +0: LibraryScreen 可在真實裝置/模擬器上渲染（integration_test 基礎設施驗證）
00:01 +1: (tearDownAll)
00:02 +1: All tests passed!
```

## Fix Self-Review

- **Completeness**：審查報告中列出的 3 項問題（1 項 Important + 2 項 Minor）皆已修正；未擴大範圍。
- **Quality**：`extractPdfMetadata`/`extractEpubMetadata` 的 `result.success(...)`/`result.error(...)` 呼叫皆確認發生在 `withContext(Dispatchers.IO)` 區塊之外（即 `scope` 的 `Dispatchers.Main`），符合 `MethodChannel.Result` 必須在平台/主執行緒呼叫的限制；PDF 找不到檔案的情況原本直接 `result.error` 後 `return`，改為 `withContext` 回傳 `null` 再於外層判斷，語意不變。
- **Discipline**：未觸碰 `EpubReaderView.kt`/`PdfReaderView.kt`；channel 名稱/方法名稱/回傳鍵/600px 上限邏輯皆未變動；未新增審查報告中標註為「nice to have」的 PNG 尺寸斷言測試。
- **Testing**：6 個 integration_test 檔案（含本次修正的 `book_metadata_channel_test.dart`）皆在同一實體裝置 `3CEF42ECD491687` 上重新執行並全數通過；`flutter analyze` 與 `flutter test`（非 integration）皆乾淨通過。

## Concerns

無新增疑慮。
