# Task 1 報告：原生測試支援方法 + 真正 `content://` SAF 驗收測試

## 實作內容

依照 `.superpowers/sdd/task-1-brief.md` 的規格，逐字新增以下內容：

1. **`app/android/app/src/main/AndroidManifest.xml`**：在 `<application>` 區塊內、既有 `flutterEmbedding` `<meta-data>` 之後，新增 `FileProvider` 的 `<provider>` 宣告（`android:authorities="${applicationId}.fileprovider"`，`exported="false"`，`grantUriPermissions="true"`）。

2. **`app/android/app/src/main/res/xml/file_paths.xml`**（新檔）：`<cache-path name="cache" path="." />`，涵蓋 `context.cacheDir`（對應 `path_provider` 的 `getTemporaryDirectory()`）。

3. **`app/integration_test/content_uri_acceptance_test.dart`**（新檔）：先寫測試（RED），驗證流程為 `createTestContentUri` → 斷言回傳值以 `content://` 開頭（非 `file://`）→ `takePersistableUriPermission` → 用該 URI 建構 `EpubReaderView` → 斷言觸發 `onPageRendered` 而非 `onError`。

4. **`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`**：
   - import 區塊新增 `android.content.Intent`、`androidx.core.content.FileProvider`。
   - `onMethodCall` 新增兩個分支：
     - `takePersistableUriPermission`：呼叫 `context.contentResolver.takePersistableUriPermission(...)`，缺少 `uri` 參數時回傳 `invalid_arguments` 錯誤，例外時回傳 `permission_failed` 錯誤（中文訊息）。
     - `createTestContentUri`（測試專用）：用 `FileProvider.getUriForFile()` 把裝置上真實檔案路徑轉為 `content://` URI，並自我授予 persistable 權限，模擬 SAF `ACTION_OPEN_DOCUMENT` 原本會提供的授權。缺少 `path` 參數時回傳 `invalid_arguments` 錯誤，例外時回傳 `test_uri_failed` 錯誤（中文訊息）。
   - **未修改**任何既有邏輯：`extractEpubMetadata`、`extractPdfMetadata`、`resolveAbsoluteUrl`、`openParcelFileDescriptor` 逐行維持原樣（見下方 git diff，純新增）。
   - **未觸碰** `EpubReaderView.kt`／`PdfReaderView.kt`（Issue 3 範圍，本工單不涉及）。

`androidx.core.content.FileProvider` 確實已透過既有相依鏈可用，編譯/建置全程無需新增 Gradle 依賴，未觸發 brief 提到的「需要人工確認」情境。

## 測試結果（裝置：`3CEF42ECD491687`，實體機 9491G，Android 15 / API 35）

### Step 4：RED（新增測試，原生方法尚不存在）

```
flutter test integration_test/content_uri_acceptance_test.dart -d 3CEF42ECD491687
```

```
Running Gradle task 'assembleDebug'...                             87.7s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           4.6s
00:00 +0: 真正的 content:// SAF URI（透過 FileProvider 授權）開啟 EPUB 觸發 onPageRendered
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following MissingPluginException was thrown running a test:
MissingPluginException(No implementation found for method createTestContentUri on channel
elinkbook/book_metadata)

When the exception was thrown, this was the stack:
#0      MethodChannel._invokeMethod (package:flutter/src/services/platform_channel.dart:364:7)
<asynchronous suspension>
#1      main.<anonymous closure> (file:///U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-4-book-import-service/app/integration_test/content_uri_acceptance_test.dart:39:24)
<asynchronous suspension>
#2      testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:15)
<asynchronous suspension>
#3      TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1682:5)
<asynchronous suspension>
<asynchronous suspension>
(elided one frame from package:stack_trace)

The test description was:
  真正的 content:// SAF URI（透過 FileProvider 授權）開啟 EPUB 觸發 onPageRendered
════════════════════════════════════════════════════════════════════════════════════════════════════
00:00 +0 -1: 真正的 content:// SAF URI（透過 FileProvider 授權）開啟 EPUB 觸發 onPageRendered [E]
  Test failed. See exception logs above.
  The test description was: 真正的 content:// SAF URI（透過 FileProvider 授權）開啟 EPUB 觸發 onPageRendered
  
00:00 +0 -1: (tearDownAll)
00:01 +0 -1: Some tests failed.
```

符合預期：`MissingPluginException`（`onMethodCall` 尚未有 `createTestContentUri` 分支）。

### Step 6：GREEN（新增兩個原生方法之後）

```
flutter test integration_test/content_uri_acceptance_test.dart -d 3CEF42ECD491687
```

```
Running Gradle task 'assembleDebug'...                             24.5s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...           5.3s
00:00 +0: 真正的 content:// SAF URI（透過 FileProvider 授權）開啟 EPUB 觸發 onPageRendered
00:02 +1: (tearDownAll)
00:02 +1: All tests passed!
```

### Step 7：回歸測試（既有 integration_test，全部在裝置 `3CEF42ECD491687` 上執行）

**`book_metadata_channel_test.dart`**
```
00:00 +0: EPUB 詮釋資料提取回傳非空的 title 與 coverBytes
00:00 +1: PDF 詮釋資料提取回傳非空的 coverBytes
00:00 +2: 不存在的檔案路徑呼叫 extractMetadata 拋出 PlatformException
00:00 +3: 以 file:// URI 表示路徑呼叫 extractMetadata（EPUB）同樣回傳非空結果
00:00 +4: 以 file:// URI 表示路徑呼叫 extractMetadata（PDF）同樣回傳非空結果
00:00 +5: (tearDownAll)
00:01 +5: All tests passed!
```

**`epub_reader_view_test.dart`**
```
00:00 +0: 開啟有效 EPUB 檔案觸發 onPageRendered
00:02 +1: 開啟不存在的檔案路徑觸發 onError
00:02 +2: 開啟內容已損毀的 EPUB 檔案觸發 onError
00:02 +3: 開啟以 file:// URI 表示的有效 EPUB 檔案觸發 onPageRendered
00:02 +4: 開啟指向不存在資源的 content:// URI 觸發 onError
00:03 +5: (tearDownAll)
00:03 +5: All tests passed!
```

**`pdf_reader_view_test.dart`**
```
00:00 +0: 開啟有效 PDF 檔案觸發 onPageRendered
00:01 +1: 開啟不存在的檔案路徑觸發 onError
00:01 +2: 開啟以 file:// URI 表示的有效 PDF 檔案觸發 onPageRendered
00:01 +3: 開啟指向不存在資源的 content:// URI 觸發 onError
00:01 +4: (tearDownAll)
00:02 +4: All tests passed!
```

**`reader_screen_test.dart`**
```
00:00 +0: ReaderScreen 開啟範例 EPUB 檔案，渲染出非空白內容
00:02 +1: ReaderScreen 開啟範例 PDF 檔案，渲染出非空白內容
00:02 +2: (tearDownAll)
00:03 +2: All tests passed!
```

**`library_screen_test.dart`**
```
00:00 +0: 從書架點擊範例 EPUB 項目，導航至 ReaderScreen 且內容成功渲染
00:03 +1: 從書架點擊範例 PDF 項目，導航至 ReaderScreen 且內容成功渲染
00:03 +2: (tearDownAll)
00:04 +2: All tests passed!
```

**`smoke_test.dart`**
```
00:00 +0: LibraryScreen 可在真實裝置/模擬器上渲染（integration_test 基礎設施驗證）
00:01 +1: (tearDownAll)
00:02 +1: All tests passed!
```

全部 6 個既有 integration_test 檔案皆 `All tests passed!`，無回歸。

### Step 8：靜態分析與建置

```
flutter analyze
```
```
Analyzing app...                                                
No issues found! (ran in 4.3s)
```

```
flutter build apk --debug
```
```
Running Gradle task 'assembleDebug'...                             31.4s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
```

## 變更檔案

- `app/android/app/src/main/AndroidManifest.xml`（修改，+9 行：新增 `<provider>`）
- `app/android/app/src/main/res/xml/file_paths.xml`（新檔，4 行）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`（修改，+52 行：2 個 import + 2 個新方法分支）
- `app/integration_test/content_uri_acceptance_test.dart`（新檔，73 行）

Commit：`2bba316` "Add FileProvider + takePersistableUriPermission/createTestContentUri, verify genuine content:// openBook"

## 自我審查結果

- **完整性**：FileProvider manifest 宣告與 `file_paths.xml` 皆已建立；兩個新原生方法皆已加入；新的 integration_test 在真實裝置上通過。
- **品質**：兩個新方法皆有 null 參數檢查（回傳 `invalid_arguments` 錯誤）與 try-catch（分別回傳 `permission_failed`／`test_uri_failed`，訊息皆為中文），風格與既有的 `extractMetadata` 分支一致。
- **紀律**：以 `git diff HEAD~1 HEAD -- BookMetadataChannel.kt` 確認變更為純新增（import + 2 個 `when` 分支），`extractEpubMetadata`/`extractPdfMetadata`/`resolveAbsoluteUrl`/`openParcelFileDescriptor` 逐行未變動；未觸碰 `EpubReaderView.kt`／`PdfReaderView.kt`。
- **測試**：新測試明確斷言 `contentUri!.startsWith('content://')` 為 `true`（而非 `file://`），對應 brief 要求的「真正的 content:// 路徑」驗證目標；6 個既有 integration_test 檔案全數通過，無回歸。

## 問題與疑慮

無。`androidx.core.content.FileProvider` 依 brief 所述透過既有相依鏈可直接解析，編譯與執行皆無異常，未觸發需要人工介入的 Gradle 依賴問題。工作目錄中原有的 `.superpowers/sdd/progress.md`、`task-2-report.md`、`task-3-report.md` 未提交變更（推測為前序任務遺留），本工單未觸碰、未提交，維持原狀供人類/其他工單處理。
