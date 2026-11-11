# Issue 18：Android 移除 Readium 相依與清理（階段二）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android 的 EPUB 詮釋資料與「既有書籍版面回填」全部改走 foliate-js 探針，移除 `readium-shared`／`readium-streamer` 原生相依、`extractEpubMetadata`／`detectEpubLayout` 原生方法、foliate 失敗時退回 Readium 的退路，以及只為 Readium 對比而存在的程式、測試與授權檔。

**Architecture:** 原生通道 `elinkbook/book_metadata` 保留（PDF 詮釋資料、SHA-256、content URI 複製等仍用），只拿掉 EPUB 相關方法。Dart 端 `extractAndroidBookMetadata` 變成「EPUB → foliate 探針（經 `runSerialized`）、其他 → 原生通道」，不再有旗標與退路。「既有書籍版面回填」改由 `SqliteLibraryRepository` 注入的 `epubLayoutDetector` 執行，Android 在 `main.dart` 接上同一支探針。

**Tech Stack:** Flutter 3.47.9／Dart、Kotlin（Android 通道）、`flutter_inappwebview` 背景 WebView 探針（`metadata-probe.js`）、Gradle。

**Spec:** `docs/epics/epic-66-windows-port/issues.md`「Android 移除 Readium 相依與清理（Issue 18）」段落；背景與對比數據見 `issue-12-report.md`、`plans/plan-issue-12.md`；`epic.md` 決策 29。

## 已由人類確認（2026-11-11，三點皆接受建議）

1. **回填路徑要不要接受變慢。** 既有書籍 `is_fixed_layout` 為 `null`（舊版匯入、尚未開過）時，開書前會呼叫 `detectAndCacheEpubLayout`；Readium 版很快，foliate 版要啟動背景 WebView（BooksPad 中位數約 1.7 秒，WAVE 比 Readium 慢約 5 倍，Issue 12 紀錄）。這段期間畫面顯示載入指示器。每本舊書只發生一次（結果寫回資料庫）；批次「重新偵測」會逐本跑。**建議接受**，並在 Task 6 於 WAVE 實測這個時間，超過 10 秒再回頭討論。
2. **回填失敗的行為。** `reader_screen.dart:614` 的 `detectAndCacheEpubLayout(...).then(...)` 沒有錯誤處理：失敗會讓畫面永遠停在載入中（Readium 時代就存在，但 foliate 有 30 秒逾時，更容易遇到）。**建議**失敗時視為流式（`false`）、不寫入資料庫（與 Windows 現行降級一致），讓書能開。
3. **移除退路後，EPUB 探針失敗的匯入結果。** 既有 `_peekIdentity` 等呼叫端已經 `catch` 並改用檔名當書名；移除退路等於「探針失敗就用檔名」。你 2026-11-09 已決議不保留退路，這裡只是確認知悉。

## Global Constraints

- Flutter 3.47.9（Dart 3.13.7），`flutter analyze` 乾淨（"No issues found!"）。
- 不改資料庫 schema（`version: 29` 不動）、不改既有 API route 與 Prompt 參數。
- Android `minSdk` 維持 `24`（移除 Readium 後下限仍由 `integration_test` 外掛決定）。`coreLibraryDesugaring`／`isCoreLibraryDesugaringEnabled` **不動**（是否仍需要未驗證，YAGNI）。
- 真機一律用 `adb install -r`，**禁用 `flutter install`**（會解除安裝並清資料）；Android 整合測試前螢幕必須亮著；`app/android/gradle.properties:5` 寫死 JDK 17 路徑。
- 修改 `lib/` 內 Key 或 `integration_test/` 後跑 `node tool/check_integration_keys.js`；新增或修改畫面字串後跑 `node tool/check_l10n_hardcoded_strings.js`。
- 測試範圍：每個 Task 只跑異動觸及的測試檔；完整 `flutter test` 只在最後一個 Task 與發 PR 前各跑一次。
- 所有文件、註解以正體中文撰寫；不加 `Co-Authored-By`。
- 不處理：Windows 的版面回填行為（維持現狀，不接探針）、`EpubCharacterCounter.kt`／`EpubFxlScaler.kt` 內提到 Readium 的歷史註解（與本 Issue 無關，不動）。

## Review Focus

1. **探針失敗的 EPUB 匯入：** 沒有退路後，探針丟例外時匯入仍須成功（書名退回檔名），不能讓整個匯入中斷。呼叫端有**三處**只攔截 `PlatformException`／`MissingPluginException`：`_peekIdentity`（另有 `catch (_)`）、`_prepareBookParts`（`book_import_service_impl.dart` 約第 1346 行，擊穿會讓整個匯入失敗）、`_readEpubIdentifier`（約第 957 行）。探針實際丟的是 `StateError`／`TimeoutException`，所以 `extractAndroidBookMetadata` 必須比照 Windows（`windows_book_metadata.dart:59-65`）把非 `PlatformException` 包成 `PlatformException(code: 'extraction_failed')`。（Task 2 測試；Task 6 以「損毀 EPUB」實機驗證。）
2. **舊書回填失敗：** `detectAndCacheEpubLayout` 的探針失敗時，閱讀畫面不得永遠卡在載入中。（Task 1 測試 + Task 3 的 `reader_screen` 錯誤處理測試。）
3. **探針併發：** 匯入與回填同時進行時，背景 WebView 不得重疊（兩者都經 `runSerialized`）。（Task 1、Task 2 各一個測試斷言經過序列化。）
4. **PDF 不受影響：** PDF 詮釋資料仍走原生通道，且通道仍回傳封面與頁數相關欄位。（Task 2 測試 + Task 4 的 PDF 整合測試保留。）
5. **非圖片封面：** foliate 的 `getCover()` 備援（例如 `guide` 的封面頁）可能回傳 XHTML Blob（Readest 曾因此存出壞封面，見 readest/foliate-js PR #123、readest PR #6635）。移除 Readium 後沒有第二引擎可比對，Dart 端必須把「`coverType` 不是 `image/*`」視為沒有封面。（Task 2 測試。）
6. **舊 Dart 呼叫誤打 EPUB：** 原生通道收到 `format: epub` 的 `extractMetadata` 必須明確回 `unsupported_format`，不得靜默成功或當機。（Task 4 整合測試。）

---

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/library/android_book_metadata.dart` | 修改 | 移除旗標與 Readium 退路；新增 `detectAndroidEpubLayout` |
| `app/lib/library/android_epub_metadata.dart` | 修改 | `mapProbeResult` 拒收非圖片封面並保留 `coverType` |
| `app/lib/library/sqlite_library_repository.dart` | 修改 | `open()` 新增 `epubLayoutDetector`；`detectAndCacheEpubLayout` 改用它 |
| `app/lib/main.dart` | 修改 | Android 把 `detectAndroidEpubLayout` 傳入 `SqliteLibraryRepository.open` |
| `app/lib/screens/reader_screen.dart` | 修改 | `detectAndCacheEpubLayout` 失敗時降級為流式 |
| `app/android/.../BookMetadataChannel.kt` | 修改 | 移除 EPUB 方法、Readium import、封面退路 |
| `app/android/app/build.gradle.kts` | 修改 | 移除兩個 Readium 相依 |
| `app/lib/library/metadata_comparison.dart` | 刪除（Task 4） | 只為 Readium 對比而存在；`integration_test/` 仍 import，須與對比測試一起刪 |
| `app/lib/licenses/third_party_licenses.dart`、`app/assets/licenses/readium-kotlin-toolkit.txt` | 修改／刪除 | 移除授權項 |
| 測試檔 | 見各 Task | |
| `AGENTS.md`、`CLAUDE.md`、`docs/epics/epic-66-windows-port/{issues,epic,issue-18-report}.md` | 修改／新增 | 文件同步 |

---

### Task 0：基準與開工

**Files:** `docs/epics/epic-66-windows-port/issues.md`（補第 18 列：目前表格缺這一列，只在「後續項目」段落有描述）

- [x] **Step 1: 開分支** `fix/epic-66-issue-18-remove-readium`（同分支放計畫、實作、報告）。
- [x] **Step 2: 在 `issues.md` 表格補上第 18 列**，狀態「🟡 進行中」，連結本計畫。
- [x] **Step 3: 記錄基準。** 在 `app/` 跑 `flutter build apk --release --split-per-abi`（無 `key.properties` 時以 debug 金鑰簽章，可接受），記下各 ABI APK 位元組數，存到 scratchpad，供 Task 6 比對。預期：建置成功；數字記入報告「基準」欄。
- [x] **Step 4: 記錄 Readium 使用面。** `grep -rn "org.readium" app/android/app/src` 預期只出現在 `BookMetadataChannel.kt`（已查證，import 在第 21–30 行、型別使用在 464 行）。

### Task 1：版面回填改用可注入的偵測器

**Files:**
- Modify: `app/lib/library/android_book_metadata.dart`
- Modify: `app/lib/library/sqlite_library_repository.dart`（`open()` 約第 50 行；`detectAndCacheEpubLayout` 約第 1262 行）
- Modify: `app/lib/main.dart`（約第 133 行 `SqliteLibraryRepository.open(dbPath)`）
- Test: `app/test/library/android_book_metadata_test.dart`、`app/test/library/sqlite_library_repository_test.dart`（約第 3149 行）

**Interfaces:**
- Produces: `Future<bool> detectAndroidEpubLayout(String uri, {Future<Map<String, Object?>> Function(String uri)? foliateReader})`——經 `runSerialized` 呼叫探針（預設 `readEpubMetadataOnAndroid`），回傳 `map['isFixedLayout'] as bool? ?? false`；探針例外一律包成 `PlatformException(code: 'detection_failed')`（沿用原生通道舊的錯誤碼；已是 `PlatformException` 則原樣往外拋）。
- Produces: `SqliteLibraryRepository.open(String path, {bool singleInstance = true, Future<bool> Function(String filePath)? epubLayoutDetector})`；`detectAndCacheEpubLayout` 在 detector 為 `null` 時回傳 `false` 且**不寫入資料庫**（取代現行 `MissingPluginException` 分支，行為與 Windows 現況一致）。

- [x] **Step 1: 寫失敗測試。**
  - `android_book_metadata_test.dart`：`detectAndroidEpubLayout 回傳探針的 isFixedLayout`（探針回 `{'isFixedLayout': true}` → `true`；缺欄位 → `false`）；`探針丟 StateError 時包成 PlatformException（code 為 detection_failed）`；`經過 runSerialized`（同時發出兩個呼叫，斷言第二個在第一個完成後才開始）。
  - `sqlite_library_repository_test.dart`：把原本「呼叫 detectEpubLayout method channel」的測試改為「呼叫注入的 detector，結果寫回 `is_fixed_layout`」；新增「detector 為 null 時回傳 false 且資料列 `is_fixed_layout` 維持 null」；「detector 丟例外時例外往外拋、資料列不變」。注意：`setUp` 已用預設的 `open(inMemoryDatabasePath)` 開過資料庫，注入 detector 的案例必須另開並傳入 `singleInstance: false`，否則會命中 sqflite 快取而拿到沒有 detector 的舊實例（該檔第 3479 行附近已有同樣用法可參照）。
- [x] **Step 2: 跑測試確認失敗。** `flutter test test/library/android_book_metadata_test.dart test/library/sqlite_library_repository_test.dart`，預期：新測試因函式／參數不存在而失敗。
- [x] **Step 3: 實作** 上述 Interfaces；`main.dart` 在 `isAndroidPlatform` 時傳入 `detectAndroidEpubLayout`，Windows 與其他平台傳 `null`。
- [x] **Step 4: 跑測試確認通過**（同 Step 2 指令），再 `flutter analyze`。
- [x] **Step 5: Commit** `refactor(library): 版面回填改用可注入的偵測器，Android 接上 foliate 探針（epic-66 Issue 18）`。

### Task 2：移除 Dart 端 Readium 退路與旗標

**Files:**
- Modify: `app/lib/library/android_book_metadata.dart`、`app/lib/library/android_epub_metadata.dart`（`mapProbeResult`，約第 50 行）
- Test: `app/test/library/android_book_metadata_test.dart`、`app/test/library/android_epub_metadata_test.dart`

**Interfaces:**
- Produces（行為）: `mapProbeResult(String json)` 讀取探針回傳的 `coverType`：**非空且不以 `image/` 開頭**時 `coverBytes` 為 `null`；`coverType` 缺漏或空字串時維持原行為（保留既有測試與舊探針相容）。回傳的 Map 另外保留 `'coverType'`（`raw['coverType'] as String?`，供 Task 6 的封面型別掃描使用，既有消費端只讀既有鍵、不受影響）。只改 Android 的 `mapProbeResult`；Windows 的 `windows_epub_metadata.dart` 有同樣的對應程式碼，**本 Issue 不改**，在報告記為後續項目。
- Produces（簽章變更）: `Future<Map<String, Object?>?> extractAndroidBookMetadata(String uri, String format, {Future<Map<String, Object?>> Function(String uri)? foliateReader, Future<Map<String, Object?>?> Function(String uri, String format)? nativeReader})`。`format == 'epub'`（不分大小寫）→ `runSerialized` 內呼叫 foliate 探針，**例外一律包成 `PlatformException(code: 'extraction_failed', message: e.toString())`（已是 `PlatformException` 則原樣往外拋；`StateError`、`TimeoutException` 等都要包）**——這是呼叫端 `_peekIdentity`、`_prepareBookParts`、`_readEpubIdentifier` 的降級合約（見 Review Focus 1）；其他格式 → 原生通道（`nativeReader` 取代原 `readiumReader`，預設呼叫 `kBookMetadataChannel` 的 `extractMetadata`，引數 `uri`、`format`）。刪除 `kAndroidMetadataFoliateFirst` 與 `foliateFirst` 參數。

- [x] **Step 1a: 封面型別測試（`android_epub_metadata_test.dart`）。** 新增：`coverType 為 application/xhtml+xml 時 coverBytes 為 null`、`coverType 為 image/jpeg 時照常解碼`、`coverType 缺漏時照常解碼（相容既有案例）`。
- [x] **Step 1: 改寫測試。** 刪除「foliateFirst 為 false」「foliate 丟例外時退回 Readium」兩個案例與其日誌斷言；保留／改寫：`epub 走 foliate 且原生從未呼叫`、`pdf 走原生通道`、`epub 探針丟 StateError 時包成 PlatformException（code 為 extraction_failed，不退回、不吞掉）`、`探針丟 TimeoutException 同樣被包裝`、`探針丟 PlatformException 時原樣往外拋`、`epub 經過 runSerialized`、`預設原生呼叫引數為 uri 與 format`。
- [x] **Step 2: 跑測試確認失敗**（舊簽章的測試編譯失敗或斷言失敗）。`flutter test test/library/android_book_metadata_test.dart`。
- [x] **Step 3: 實作** 簽章變更與封面型別檢查；`grep -rn "kAndroidMetadataFoliateFirst\|foliateFirst\|readiumReader" app/lib app/test app/integration_test` 預期無殘留（`integration_test` 的殘留於 Task 4 處理；**`metadata_comparison.dart` 此 Task 不刪**，因為 `integration_test/` 仍 import 它，`analysis_options.yaml` 沒有排除該目錄，提早刪除會讓 Step 4 的 `flutter analyze` 失敗）。
- [x] **Step 4: 跑測試確認通過**，`flutter analyze` 乾淨。
- [x] **Step 5: Commit** `refactor(library): 移除 Android EPUB 詮釋資料的 Readium 退路與旗標（epic-66 Issue 18）`。

### Task 3：版面回填失敗時閱讀畫面不卡載入

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`（`_resolveEpubEngineDispatch`，約第 611–618 行）
- Test: `app/test/screens/reader_screen_test.dart`（沿用該檔既有的 fake `libraryRepository` 寫法）

**Interfaces:**
- Consumes: `LibraryRepository.detectAndCacheEpubLayout(String bookId, String filePath) -> Future<bool>`（Task 1，簽章不變）。

- [x] **Step 1: 寫失敗測試。** 名稱：`isFixedLayout 為 null 的 EPUB，版面偵測丟例外時降級為流式並開書，不停在載入中`。斷言：fake repository 的 `detectAndCacheEpubLayout` 丟 `Exception('probe failed')` 後，`Key('reader_loading_indicator')` 消失、無 `Key('reader_error_text')`、且 fake 的資料庫寫入次數為 0。
- [x] **Step 2: 跑測試確認失敗**（目前會有未處理的 Future 錯誤且載入指示器不消失）。`flutter test test/screens/reader_screen_test.dart --plain-name "版面偵測丟例外"`。
- [x] **Step 3: 實作。** 在 `.then(...)` 後加 `.catchError`：以 `debugPrint` 記錄原因，若 `mounted` 則 `setState(() => _dispatchedIsFixedLayout = false)`；不寫資料庫。
- [x] **Step 4: 跑測試確認通過**，再跑該檔全部測試確認無回歸，`flutter analyze`。
- [x] **Step 5: Commit** `fix(reader): 版面回填失敗時降級為流式，不停在載入中（epic-66 Issue 18）`。

### Task 4：移除原生端 Readium 與過時的對比測試

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`
- Modify: `app/android/app/build.gradle.kts`（第 193–194 行兩個 `implementation`）
- Delete: `app/integration_test/library_metadata_comparison_test.dart`、`app/integration_test/metadata_comparison_test.dart`、`app/lib/library/metadata_comparison.dart`、`app/test/library/metadata_comparison_test.dart`（與 Task 2 分開，等所有 import 者都處理完才刪）
- Modify: `app/integration_test/book_metadata_channel_test.dart`、`app/integration_test/content_uri_range_metadata_test.dart`

**Interfaces:**
- Produces: 通道 `extractMetadata` 收到 `format == "epub"` 時 `result.error("unsupported_format", ...)`（與現行 `else` 分支同一個錯誤碼）；`detectEpubLayout` 方法整個移除（落入 `notImplemented`）。

- [x] **Step 1: 改寫整合測試（先於實作）。**
  - `book_metadata_channel_test.dart`：**共 6 個 EPUB 案例**要處理——第 23、43、107、149、166 行的 5 個（提取成功、含 identifier、空字串 identifier、`file://` 路徑等）刪除，由單一新案例 `extractMetadata 收到 epub 格式回 unsupported_format`（斷言 `PlatformException.code == 'unsupported_format'`）取代；第 89 行「不存在的檔案路徑」案例雖然改後仍會因 `unsupported_format` 而過，但是因為錯的原因而過，須把它的 `format` 改成 `'pdf'` 才有意義。PDF 案例（第 71、127、184 行）與 `computeSha256` 案例保留。
  - `content_uri_range_metadata_test.dart`：移除對 Readium 的呼叫與 `diffBookMetadata`，改為斷言經 `content://` 讀取後 foliate 探針回傳的 `title`、`identifier`、`isFixedLayout` 等於已知 fixture 的預期值（寫死在測試內）。
  - 刪除兩個對比測試檔，以及 `lib/library/metadata_comparison.dart`、`test/library/metadata_comparison_test.dart`；`grep -rn "metadata_comparison" app/lib app/test app/integration_test` 預期無殘留，`flutter analyze` 乾淨。**刪除前先保留一份** `library_metadata_comparison_test.dart` 到 scratchpad（`git show HEAD:app/integration_test/library_metadata_comparison_test.dart`），Task 6 Step 2b 要改寫它來掃描封面型別。
- [x] **Step 2: 原生端實作。** 刪除 `extractEpubMetadata`、`detectEpubLayout`、`"detectEpubLayout"` 分支、`findFallbackCoverBitmap`、`resolveAbsoluteUrl`（若 `copyContentUriToFile` 等仍使用則保留，以編譯與 `grep` 為準）、第 21–30 行的 Readium import；`extractMetadata` 的 `"epub"` 分支改為 `unsupported_format`。`bitmapToPngBytes` 仍被 PDF 使用，保留。移除 `build.gradle.kts` 兩行相依。
- [x] **Step 3: 編譯與 JVM 單元測試。** 這台 Windows 機器 `java` 不在 PATH、`JAVA_HOME` 為空，`gradlew.bat` 會先檢查環境變數而直接報 `JAVA_HOME is not set`，所以在 PowerShell 執行：`$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.21.21-hotspot"; cd app/android; ./gradlew.bat :app:compileDebugKotlin :app:testDebugUnitTest`（路徑與 `gradle.properties` 的 `org.gradle.java.home` 相同，已確認存在）。預期成功；`grep -rn "org.readium" app/android/app/src app/android/app/build.gradle.kts` 預期無輸出。
- [x] **Step 4: 整合測試（需 Android 實機，螢幕亮著）。** `flutter test integration_test/book_metadata_channel_test.dart integration_test/content_uri_range_metadata_test.dart -d <device-id>`，預期通過。**無實機時此步不得宣稱通過**，在報告標「未驗證」。
- [x] **Step 5: Commit** `refactor(android): 移除 Readium 相依與 EPUB 原生詮釋資料通道（epic-66 Issue 18）`。

### Task 5：授權檔與文件

**Files:**
- Modify: `app/lib/licenses/third_party_licenses.dart`（約第 40–44 行）、`app/test/licenses/third_party_licenses_test.dart`（第 64、125 行）
- Delete: `app/assets/licenses/readium-kotlin-toolkit.txt`
- Modify: `AGENTS.md`（第 33 行「`BookMetadataChannel.kt`（EPUB metadata 讀取，仍依賴 readium…）」改為 PDF metadata、SHA-256、content URI 複製；第 76、148 行 minSdk 24 的由來改為只剩 `integration_test` 外掛）、`CLAUDE.md`（minSdk 24 由來那句同樣只剩 `integration_test`；「`readium-shared`／`readium-streamer` 保留供 `BookMetadataChannel.kt` 使用，其餘 Readium 依賴已移除」那句）、`docs/epics/epic-66-windows-port/epic.md`（決策 29 狀態）、`issues.md`（第 18 列、後續項目段落）

- [x] **Step 1: 改測試。** `third_party_licenses_test.dart` 移除 `'Readium kotlin-toolkit'` 的清單項與全文斷言。跑 `flutter test test/licenses/third_party_licenses_test.dart`，預期：先失敗（授權項仍在）。
- [x] **Step 2: 移除** 授權項與 asset 檔；確認 `pubspec.yaml` 的 `assets/licenses/` 目錄宣告不需改。測試轉為通過。
- [x] **Step 3: 文件。** `AGENTS.md`、`CLAUDE.md` 依 Files 所列更新（`AGENTS.md` 第 143 行 `fontWeight` 的「Readium 倍率語意」是歷史命名、不是依賴，不動）；`CLAUDE.md` 改為「Android 已完全移除 Readium 依賴」；`epic.md` 決策 29 註明階段二完成；`issues.md` 第 18 列待實測後補完。
- [x] **Step 4: Commit** `docs: 移除 Readium 授權項並同步架構說明（epic-66 Issue 18）`。

### Task 6：Android 實機驗證與報告（需人類配合裝置）

**Files:** Create: `docs/epics/epic-66-windows-port/issue-18-report.md`

- [x] **Step 1: 建置並安裝。** `flutter build apk --debug`，`adb install -r`（**禁用 `flutter install`**）；操作前備份資料庫。
- [x] **Step 2: 匯入驗證（以 BooksPad 替代 WAVE，WAVE 未驗證；人類 2026-11-11 同意）。** 在 WAVE 匯入 2～3 本 EPUB（含有封面、含固定版面各一）：書名、作者、封面正確；日誌無 Readium 字樣。
- [x] **Step 2b: 封面型別掃描（BooksPad，原始輸出未留存，見報告第 5 節）。** 以 Task 4 Step 1 保留的 `library_metadata_comparison_test.dart` 為底，改寫成**拋棄式**唯讀整合測試（不進 commit）：開 `library.db`（`openReadOnlyDatabase`）、對每本 EPUB 呼叫 `readEpubMetadataOnAndroid`，印出每本的 `coverType`（來自 Task 2 保留在 Map 的 `coverType` 欄位）與 `coverBytes` 是否為 null，並統計「被拒收」（`coverType` 非 `image/*`）的筆數與書名；預期全為 `image/*`。有被拒收的書列入報告，並人工確認是否真的沒有圖片封面（Readest 類 bug 的實機檢查，Issue 12 的對比只比「有沒有」封面）。沿用該檔的保護：測試前後 `library.db` 大小與修改時間不變。
- [x] **Step 3: 損毀 EPUB（BooksPad 替代 WAVE）。** 匯入一個損毀的 EPUB：匯入不中斷，書名為檔名（Review Focus 1）。
- [x] **Step 4: 舊書回填計時（BooksPad 實測 17.5 秒，超過 10 秒門檻；人類 2026-11-11 決定接受；WAVE 未量測；只量了成功路徑，回填失敗的實機行為只有 widget 測試）。** 把一本書的 `is_fixed_layout` 設為 `NULL` 後開書，量測載入指示器消失的時間；記錄 WAVE 的實測值（對應「待人類確認」第 1 點，超過 10 秒回報人類）。
- [x] **Step 5: 體積。** 重跑 Task 0 Step 3 的 release 建置，與基準比對各 ABI APK 位元組數，寫入報告。
- [x] **Step 6: 全套測試。** 在 `app/` 跑完整 `flutter test`，預期全過；`flutter analyze`、兩支 Node 檢查腳本通過。
- [x] **Step 7: 報告與帳本。** 寫 `issue-18-report.md`（各步結果、APK 體積差、未驗證項目），更新 `issues.md` 第 18 列；**不外推**：只有 WAVE（與可能的 BooksPad）上的 debug 版結果。

## 過關條件

1. `grep -rn "org.readium" app/android` 與 `build.gradle.kts` 無輸出；`./gradlew :app:compileDebugKotlin :app:testDebugUnitTest` 成功。
2. Dart 端不再有 `kAndroidMetadataFoliateFirst`、`readiumReader`、`detectEpubLayout` method channel 呼叫。
3. WAVE 上匯入 EPUB 的書名、作者、封面正確；損毀 EPUB 匯入不中斷；舊書回填失敗時能開書。（2026-11-11 人類同意以 BooksPad 替代 WAVE；「舊書回填失敗時能開書」只有 `reader_screen_test` 的 widget 測試，無實機驗證。）
4. 新增與改寫的單元測試通過；全套 `flutter test`、`flutter analyze` 通過。
5. 報告含 release APK 體積前後對照，並如實標示未驗證項目。

## 風險與注意

- **探針比 Readium 慢（WAVE 約 5 倍）。** 匯入路徑自 Issue 12 起已經是 foliate 優先，本 Issue 不改變匯入速度；唯一新增的變慢點是舊書回填（見「待人類確認」第 1 點）。
- **移除退路後沒有第二層保險。** 探針失敗的 EPUB 只會得到檔名書名、無封面；這是已決議的取捨。
- **Android 整合測試環境脆弱**（見使用者既有紀錄）：螢幕要亮、JDK 17 路徑寫死、adb 路徑與測試殼層恢復；Task 4 Step 4 與 Task 6 受此限制，失敗時先排除環境因素再判斷程式問題。
- `coreLibraryDesugaring` 是否仍需要未驗證，刻意不動。
- **Windows 的 `mapProbeResult` 對應程式碼有同樣的封面型別盲點**，本 Issue 不改，報告中登記為後續項目。

## 審查修訂紀錄

2026-11-11 依 `reviews/review-plan-issue-18.md` 修訂（逐項對照程式碼驗證後全數採納）：C-1 例外包成 `PlatformException`（並發現第三個呼叫點 `_readEpubIdentifier`）、I-1 `metadata_comparison.dart` 刪除移至 Task 4、I-2 列全 6 個 EPUB 案例並處理第 89 行「因錯的原因而過」、I-3 補 `JAVA_HOME` 指令、M-1 納入 `AGENTS.md`、M-2 `mapProbeResult` 保留 `coverType` 並指明掃描途徑、M-3 `singleInstance: false` 提醒。
