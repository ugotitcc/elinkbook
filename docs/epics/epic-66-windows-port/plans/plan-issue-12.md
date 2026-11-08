# Issue 12：Android 預設改用 foliate-js 讀 EPUB metadata（階段一）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android 讀 EPUB 的書名、作者、識別碼、是否固定版面、封面，改成預設用 foliate-js（與 Windows 同一支 `metadata-probe.js`），Readium 保留作為「foliate-js 失敗時的退路」。先用 App 書庫內的真實書在手機上逐本對比兩邊結果，通過才把預設切到 foliate-js。**本 Issue 不移除 Readium**（移除另立 Issue 18）。

**Architecture:** 目前 Android 的 `BookMetadataChannel.kt` 用 Readium 讀 EPUB；Windows 用 `HeadlessInAppWebView` 載入 `metadata-probe.js`、只讀必要的位元組區段，輸出五個欄位（`title`、`author`、`identifier`、`isFixedLayout`、`coverBytes`），與 Android 的輸出契約相同。Issue 2 已用 13 份人工 fixture 對比過兩邊：0 個不一致，但真實出版社 EPUB 沒比過。做法：（1）Android 補上「讀書檔區段」（含 `content://`）；（2）新增 Android 版探針，沿用索引器已有的 Android 背景 WebView 寫法；（3）新增派送函式 `extractAndroidBookMetadata`，旗標 `kAndroidMetadataFoliateFirst` 預設 `false`（行為與現在完全相同）；（4）寫唯讀的書庫對比測試，在手機上對每本 EPUB 各跑兩邊並印出差異；（5）對比通過、使用者同意後才把旗標改成 `true`。

**Tech Stack:** Flutter 3.47.9、`flutter_inappwebview`（`HeadlessInAppWebView`）、foliate-js（`app/android/app/src/main/assets/foliate/metadata-probe.js`）、Kotlin（Android 通道）、Readium 3.3.0（保留）。

**Spec:** `docs/epics/epic-66-windows-port/issues.md` 的「Issue 12 範圍／過關條件／單元測試要求」；`epic.md` 決策 27(e)；`issue-2-report.md`（13 份 fixture 對比與已知限制）。

## 診斷與決策（2026-11-08，已實測，計畫的依據）

| 項目 | 事實 |
|---|---|
| Readium 的用處 | 只在 `BookMetadataChannel.kt` 的三處：`extractEpubMetadata`（書名、第一作者、識別碼、版面、封面）、`detectEpubLayout`（既有書籍補判斷是否固定版面）、封面（`publication.cover()` 加 `findFallbackCoverBitmap` 退路）。其他原生功能（PDF 封面、`takePersistableUriPermission`、`copyContentUriToFile`、`listFolderContents`、`createTestContentUri`、SHA-256）與 Readium 無關，一律保留 |
| Dart 端的呼叫點 | `BookImportServiceImpl` 已有可注入的 `_metadataExtractor`（Windows 傳入 `extractWindowsBookMetadata`，Android 為 `null` 時走 `kBookMetadataChannel` 的 `extractMetadata`）；重新選取檔案也走同一個注入點；`sqlite_library_repository.dart` 約第 1265 行呼叫 `detectEpubLayout`（回填既有書籍，本階段**不改**） |
| Windows 探針 | `windows_epub_metadata.dart`：`HeadlessInAppWebView` 載入 `https://foliate-metadata.local/probe.html`，頁面 `import { readBookMetadataByRange } from '/assets/foliate/metadata-probe.js'`，書檔區段以 `/book/current.epub?start=&end=` 由 `shouldInterceptRequest` 回應；Windows 只接受本機路徑，遇到 `://` 會丟 `PlatformException` |
| Android 背景 WebView 先例 | `FoliateContentIndexer` 已在 Android 上用 `HeadlessInAppWebView`：`initialSize: Size(800, 1280)`、`useShouldInterceptRequest: true`、`/assets/foliate/` 由 `loadAndroidAsset(relative)` 回應、`initialUserScripts` 注入 `esCompatPolyfillJs` 與 `globalErrorCaptureJs`（舊 WebView 缺 ES2021+ API 的 polyfill） |
| Android 原生通道現況 | `ReaderResourceChannel.kt` 有 `readAndroidAsset`、`readContentUriAll`（整本讀入）、`probeUriAccess`、`cacheBookForServing` 等，**沒有「讀區段」也沒有「取 content:// 長度」**；Android 的書常是 `content://`，所以要補 |
| `metadata-probe.js` | 匯出 `readBookMetadata(file)` 與 `readBookMetadataByRange(size, fetchRange, name)`；註明採保守 ES 語法，Windows 以外尚未在舊 WebView 實測 |
| Issue 2 已知限制 | 只比過 13 份人工 fixture（0 不一致）；真實出版社書籍（EPUB 2、更多樣的 `dc:identifier`、非標準 OPF）、Readium 與 foliate-js 的版本差異、不同 Android WebView 版本的影響都沒驗證；`identifier` 兩端不一致會讓同步把同一本書當成兩本（`book_content_fingerprint.dart` 優先用 `identifier` 當指紋） |
| 可用裝置 | **WAVE**（`TCE70P24B2202374`，Android 12，`armeabi-v7a`，WebView 91.0.4472.114，E-Ink，書庫 8 本，部分是測試書）；**BooksPad**（`B78CW2508006423`，同 WebView 91，書庫 100 多本；`adb` 時快時慢，先前曾每指令約 24 秒）。兩者今天是否連線以實際為準 |
| 這台電腦 | 常見資料夾沒有任何 `.epub`，所以對比用的書改取 App 書庫內的書（使用者決定） |
| 使用者決定（2026-11-08） | 對比用 **App 書庫內的書**（先在 WAVE 驗證流程，再請使用者在 BooksPad 跑）；**分兩階段**：階段一（本 Issue）預設 foliate-js、Readium 留作退路；階段二（Issue 18）才移除 Readium |

## Global Constraints

- Flutter 3.47.9，`flutter analyze` 乾淨；不得使用此版本沒有的 API。
- `kAndroidMetadataFoliateFirst` 預設 `false`；在 Task 6 之前，Android 的匯入與重新選取行為必須與現況**完全相同**（foliate-js 路徑不會被執行）。
- 不得移除 Readium 相依、`extractEpubMetadata`、`detectEpubLayout`；不改 `windows_epub_metadata.dart`（Windows 已實測可用，重複的探針樣板在 Android 檔案複製一份，之後要合併另案）。
- 不新增、不修改任何 ARB 字串。
- 不得 commit：`app/windows/flutter/generated_plugin_registrant.cc`、`generated_plugin_registrant.h`、`generated_plugins.cmake`、`pubspec.lock` 的任何變動（本 Issue 不新增相依）；`git add` 一律明確列檔。
- **手機操作的保護規則：** 絕不解除安裝 App；動手前先備份 `app_flutter/library.db`、`dictionary.db`、`shared_prefs`（`adb exec-out run-as cc.ugotit.elinkbook tar cf - …`，**只列實際存在的檔**，否則錯誤訊息會混進輸出讓 tar 損毀；備份後解開驗證 SQLite 檔頭）；安裝一律 `adb install -r`；用 `uiautomator dump` 讀畫面上的書名定位，不用固定座標；備份放 scratchpad，用完刪除。
- 書庫對比測試是**唯讀**的：用 `openReadOnlyDatabase` 開 `library.db`，不得經 `LibraryRepository`；測試前後 `library.db` 的大小與修改時間必須相同。
- `flutter test integration_test/… -d <裝置>` 會在手機上裝入「測試殼層」版本的 App（同套件、資料保留），結束後必須用 `flutter install --debug`（或 `adb install -r` 正常 debug APK）裝回正常版本。
- 實驗腳本與暫存輸出放 scratchpad，不放進專案。
- Windows 建置（若需要）：PowerShell，`$env:Path += ';C:\Users\huthief\bin'`（放尾端）。

## Review Focus

1. 旗標為 `false` 時，Android 匯入、重新選取、回填的行為與現況完全相同，foliate-js 探針根本不啟動。（Task 3）
2. `content://` 與 `file://` 區段讀取：讀到檔尾、起點不小於長度、長度為 0 的檔案、權限被收回、取不到長度（`statSize` 為 -1 時要補查 `OpenableColumns.SIZE`）都不能崩潰也不能整本讀入；`file://` 不能被送進 `ContentResolver`；每次呼叫都要關閉 `ParcelFileDescriptor`（批次比對 100 多本不能耗盡檔案描述元）；書檔區段讀取失敗要讓探針**快速**失敗（回 404、不拋例外、不乾等逾時），再由派送函式改走 Readium。（Task 1、2、3）
3. 舊 WebView（91）上探針能跑：`esCompatPolyfillJs` 與 `globalErrorCaptureJs` 要注入；**`onError` handler 必須註冊**（`globalErrorCaptureJs` 用它回報載入階段的 JS 錯誤，沒人接就仍會乾等 30 秒）；探針頁面的 `<script type="module">` 在 91 可用。（Task 2、5）
4. 退路不能掩蓋 foliate-js 的問題：派送函式每次退回 Readium 都要 `debugPrint` 原因；對比測試**直接呼叫** foliate-js 路徑，不經派送函式。（Task 3、4）
5. `identifier` 只要有 1 本不一致，就視為對比不通過（會讓同步把同一本書當成兩本）。（Task 4、5、6）
6. 對比測試必須唯讀：不碰書庫內容、不寫檔案；跑完 `library.db` 大小與時間不變。（Task 4、5）
7. 壞書不能拖垮匯入：foliate-js 逾時（30 秒）後退回 Readium，探針序列化執行；匯入 100 多本時總時間不能比 Readium 明顯變長（對比測試要量每本耗時）。（Task 2、4、5）
8. 這一階段 Readium 仍在：不得因為「已通過」就在本 Issue 刪 Readium；階段二另立 Issue 18。（Task 6）
9. 書庫對比不能假綠：書庫裡沒有任何 EPUB 時，對比測試必須失敗，不能因為「0 差異、0 失敗」而通過。（Task 4）
10. Readium 退路的通道引數必須與 Kotlin 一致：`extractMetadata` 讀的是 `uri` 與 `format`（寫成 `path` 會讓退路 100% 回 `invalid_arguments`）；用 mock 通道斷言引數鍵。（Task 3）

---

### Task 1：Android 讀書檔區段（含 `content://`）

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ByteRange.kt`、`app/android/app/src/test/kotlin/cc/ugotit/elinkbook/ByteRangeTest.kt`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`（新增兩個方法 `contentUriLength`、`readContentUriRange`）
- Create: `app/lib/library/book_range_reader.dart`
- Test: `app/test/library/book_range_reader_test.dart`

**Interfaces:**
- Produces（Kotlin）：`fun clampByteRange(start: Long, end: Long, length: Long, maxBytes: Long): LongRange?`——檢查順序與 Windows 的 `readFileRange` 相同：**先用呼叫端傳入的原始值**檢查，`start < 0`、`end <= start`、`end - start > maxBytes` 任一成立回傳 `null`；再用長度檢查，`start >= length` 回傳 `null`；最後 `end` 超過 `length` 夾回 `length`；回傳 `start until end`。
- Produces（Kotlin 通道，`elinkbook/reader_resources_cache`）：`contentUriLength(uri)` → `Long?`（先看 `statSize`，小於 0 時補查 `OpenableColumns.SIZE`，仍取不到才回傳 `null`）；`readContentUriRange(uri, start, end)` → `ByteArray?`（越界或超過上限回傳 `null`）。上限 4 MB（與 Windows 的 `kMaxBookRangeBytes` 一致）。兩個方法都用 `pfd.use { … }` 關閉 `ParcelFileDescriptor`，不得跨呼叫持有。
- Produces（Dart）：`Future<int?> bookLength(String uri)`、`Future<Uint8List?> readBookRange(String uri, int start, int end)`：以 `uri.startsWith('content://')` 分流（與 repo 內其他地方一致）：`content://` 走上述通道；`file://` 以 `Uri.parse(uri).toFilePath()` 轉成本機路徑；其餘當本機路徑，本機路徑一律沿用 `windows_epub_metadata.dart` 的 `readFileRange`。兩者都接受可注入的通道，方便測試。`readBookRange`／`bookLength` 遇到通道例外直接往外拋，由呼叫端決定怎麼處理（見 Task 2）。

- [x] **Step 1: 寫失敗測試。**
  - Kotlin `ByteRangeTest`：`clampByteRange` 正常區段、`end` 超過長度被夾回、`start` 為負回傳 `null`、`start >= length` 回傳 `null`、`end <= start` 回傳 `null`、區段超過 `maxBytes` 回傳 `null`、`start=0, end=5 MB, length=1 MB, maxBytes=4 MB` 回傳 `null`（先檢查原始區段大小，與 Windows 同序）、`start=0, end=3 MB, length=1 MB` 回傳 `0 until 1 MB`。
  - Dart `book_range_reader_test.dart`：本機路徑讀 `[start, end)` 與檔案內容一致；`end` 超過長度被夾回；`start` 不小於長度回傳 `null`；`content://` 走通道並帶入正確參數、通道回傳 `null` 時回傳 `null`；通道丟 `PlatformException` 時 `readBookRange` 把例外往外拋；`bookLength` 本機路徑與 `content://` 各一；`file:///…` 網址轉成本機路徑讀取、不走通道。
- [x] **Step 2: 執行確認失敗。** `flutter test test/library/book_range_reader_test.dart`（預期編譯失敗）；`cd app/android && .\gradlew.bat testDebugUnitTest --tests "cc.ugotit.elinkbook.ByteRangeTest"`（預期編譯失敗）。
- [x] **Step 3: 實作。** Kotlin：`ByteRange.kt` 的純函式；`ReaderResourceChannel.kt` 兩個方法用 `contentResolver.openFileDescriptor(uri, "r")`，長度先用 `statSize`，小於 0 時改查 `OpenableColumns.SIZE`，都取不到才為 `null`，每個方法都用 `pfd.use { … }` 關閉 `ParcelFileDescriptor`；讀取用 `FileInputStream.channel.position(start)` 加固定大小緩衝，**不整本讀入**，在背景佇列執行（比照既有 `readContentUriAll` 的做法）；讀取例外轉成 `result.error`。Dart：`book_range_reader.dart`。程式註解用中文。
- [x] **Step 4: 執行確認通過。** 同 Step 2 兩個指令，預期全過；`flutter analyze lib/library/book_range_reader.dart test/library/book_range_reader_test.dart` 乾淨。
- [x] **Step 5: Commit。**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ByteRange.kt app/android/app/src/test/kotlin/cc/ugotit/elinkbook/ByteRangeTest.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt app/lib/library/book_range_reader.dart app/test/library/book_range_reader_test.dart
git commit -m "feat(android): 讀書檔區段（含 content://）（epic-66 Issue 12 Task 1）"
```

---

### Task 2：Android 版 foliate-js 探針

**Files:**
- Create: `app/lib/library/android_epub_metadata.dart`
- Test: `app/test/library/android_epub_metadata_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `bookLength`、`readBookRange`；`windows_epub_metadata.dart` 的 `parseBookRange`、`kMaxBookRangeBytes`（只 import，不改）；`foliate_native_bridge.dart` 的 `loadAndroidAsset`；`esCompatPolyfillJs`、`globalErrorCaptureJs`（索引器用的同一組）。
- Produces: `Future<Map<String, Object?>> readEpubMetadataOnAndroid(String uri, {Duration timeout = const Duration(seconds: 30)})`：回傳鍵為 `title`、`author`、`identifier`、`isFixedLayout`、`coverBytes`；逾時拋 `TimeoutException`，探針或檔案錯誤拋 `StateError`；`Map<String, Object?> mapProbeResult(String json)`（純函式，供測試）；`String androidProbeHtml(int size)`（純函式）；`Future<WebResourceResponse?> interceptBookRange(Uri url, {required Future<Uint8List?> Function(int start, int end) readRange})`：讀取成功回傳 200 與資料；**缺少 `start`／`end`、讀取回傳 `null`、讀取丟例外（`debugPrint` 原因）一律回傳明確的 404**（`WebResourceResponse(statusCode: 404, reasonPhrase: 'Not Found', headers: const {}, data: Uint8List(0))`），**絕不回傳 `null`**：`null` 的意思是「讓 WebView 照常上網」，會把請求送去網路而不是快速失敗。

- [x] **Step 1: 寫失敗測試（純函式部分）。** `android_epub_metadata_test.dart`：`mapProbeResult` 在有封面（base64）時回傳位元組、沒封面時 `coverBytes` 為 `null`、壞掉的 base64 時 `coverBytes` 為 `null` 而不拋例外、缺 `isFixedLayout` 時預設 `false`、`title`／`author`／`identifier` 缺漏時為 `null`；`androidProbeHtml(1234)` 含 `1234`、含 `metadataResult` 與 `metadataError` 兩個 handler 名稱、含 `/assets/foliate/metadata-probe.js`；`interceptBookRange`：讀取成功回傳資料、`readRange` 回傳 `null` 回 404、`readRange` 丟例外回 404（不往外拋）、缺少 `start` 或 `end` 回 404（且從未呼叫 `readRange`）。
- [x] **Step 2: 執行確認失敗。** `flutter test test/library/android_epub_metadata_test.dart`（預期編譯失敗）。
- [x] **Step 3: 實作。** `readEpubMetadataOnAndroid`：先 `bookLength` 取大小（取不到就丟 `StateError`）；`HeadlessInAppWebView`，`initialSize: Size(800, 1280)`、`useShouldInterceptRequest: true`、`initialUserScripts` 注入兩段 polyfill（比照 `FoliateContentIndexer`）；`shouldInterceptRequest` 回應 `/probe.html`（`androidProbeHtml`）、`/assets/foliate/…`（`loadAndroidAsset`，JS 用 `text/javascript`）、`/book/current.epub?start=&end=`（交給 `interceptBookRange`，絕不整本回傳）；結果由 `metadataResult`／`metadataError` 兩個 JS handler 回傳，**另註冊 `onError` handler**（`globalErrorCaptureJs` 用它回報載入階段的 JS 錯誤與未處理的 Promise 例外），收到時立刻 `completer.completeError(StateError(...))`，不等逾時；`bookLength` 失敗在啟動 WebView 之前就丟例外（讓派送函式快速退回 Readium）；`finally` 一律 `dispose`。探針 HTML 樣板複製自 Windows 檔案（不改它）。**不要**在這個 Task 接進匯入流程。
- [x] **Step 4: 執行確認通過。** 同 Step 2 指令全過；`flutter analyze` 該兩檔乾淨。真正載入 WebView 的行為留到 Task 5 在手機上驗證（`flutter test` 沒有 WebView）。
- [x] **Step 5: Commit。**

```bash
git add app/lib/library/android_epub_metadata.dart app/test/library/android_epub_metadata_test.dart
git commit -m "feat(android): foliate-js 背景探針讀 EPUB metadata（epic-66 Issue 12 Task 2）"
```

---

### Task 3：派送函式與旗標（預設關閉）

**Files:**
- Create: `app/lib/library/android_book_metadata.dart`
- Modify: `app/lib/main.dart`（`metadataExtractor` 的決定處，約第 252 行）
- Test: `app/test/library/android_book_metadata_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `readEpubMetadataOnAndroid`；既有的 `BookMetadataExtractor` 型別與 `kBookMetadataChannel`。
- Consumes（另）: `runSerialized`（`windows_book_metadata.dart` 的同一個佇列，只 import、不修改）。
- Produces: `const bool kAndroidMetadataFoliateFirst = false;`；`Future<Map<String, Object?>?> extractAndroidBookMetadata(String uri, String format, {bool foliateFirst = kAndroidMetadataFoliateFirst, Future<Map<String, Object?>> Function(String uri)? foliateReader, Future<Map<String, Object?>?> Function(String uri, String format)? readiumReader})`。

- [ ] **Step 1: 寫失敗測試（假讀取函式注入）。** `foliateFirst: false`：只呼叫 Readium，foliate 從未呼叫；`foliateFirst: true` 且格式為 `epub`、foliate 成功：回傳 foliate 結果，Readium 從未呼叫；`foliateFirst: true`、foliate 丟例外：改呼叫 Readium 並回傳其結果（並確認有輸出退回原因的日誌，用 `debugPrint` 攔截）；`foliateFirst: true` 但格式為 `pdf`：只呼叫 Readium 通道（PDF 一律走原生）；兩邊都失敗：把 Readium 的例外往外拋（不吞掉）；兩次同時呼叫 foliate 路徑時**依序執行**（第二次在第一次完成後才開始，用 `Completer` 擋住第一次來驗證）；Readium 退路呼叫通道時，用 mock 通道斷言引數鍵為 `uri` 與 `format`（不是 `path`）。
- [ ] **Step 2: 執行確認失敗。** `flutter test test/library/android_book_metadata_test.dart`（預期編譯失敗）。
- [ ] **Step 3: 實作與接線。** `android_book_metadata.dart` 預設的 `readiumReader` 呼叫 `kBookMetadataChannel.invokeMapMethod('extractMetadata', {'uri': uri, 'format': format})`（Kotlin 的 `onMethodCall` 讀的是 `uri`，`book_import_service_impl.dart` 約第 894、955、1332 行現行呼叫也都是 `'uri'`；寫成 `path` 會讓退路 100% 回 `invalid_arguments`）；foliate 路徑一律包在 `runSerialized` 內，確保同一時間只有一個背景探針 WebView（EPUB 一口氣匯入 50 本時不會同時開數十個 WebView）；Readium 退路不排隊，維持現行行為；`main.dart` 改為 `isWindowsPlatform ? extractWindowsBookMetadata : (isAndroidPlatform ? extractAndroidBookMetadata : null)`。旗標維持 `false`。
- [ ] **Step 4: 執行確認通過。** 同 Step 2 指令全過；跑 `flutter test test/library test/screens/library_screen_test.dart` 確認既有匯入相關測試不受影響；`flutter analyze` 乾淨。
- [ ] **Step 5: Commit。**

```bash
git add app/lib/library/android_book_metadata.dart app/lib/main.dart app/test/library/android_book_metadata_test.dart
git commit -m "feat(android): metadata 派送函式（旗標預設關閉，Readium 為退路）（epic-66 Issue 12 Task 3）"
```

---

### Task 4：書庫對比測試（唯讀）

**Files:**
- Create: `app/lib/library/metadata_comparison.dart`（純函式，供測試與對比測試共用）
- Test: `app/test/library/metadata_comparison_test.dart`
- Create: `app/integration_test/library_metadata_comparison_test.dart`

**Interfaces:**
- Produces: `List<String> diffBookMetadata(Map<String, Object?> readium, Map<String, Object?> foliate)`——回傳不一致的欄位名稱。規則：`title`、`author`、`identifier` 比較前各自 `trim()`，兩邊都是 `null` 或空字串視為相同；`isFixedLayout` 嚴格相等；封面只比「有沒有」（兩邊位元組不同是預期的，Readium 重新編成 PNG）；「有封面」＝位元組非 `null` 且長度大於 0。

- [ ] **Step 1: 寫失敗測試。** `metadata_comparison_test.dart`：完全相同 → 空清單；`title` 不同 → `['title']`；`title` 只差前後空白 → 空清單；`author` 一邊 `null` 一邊空字串 → 空清單；`identifier` 不同 → `['identifier']`；`isFixedLayout` 不同 → `['isFixedLayout']`；一邊有封面一邊沒有 → `['cover']`；兩邊封面位元組不同但都有 → 空清單；一邊空位元組陣列、一邊 `null` → 空清單；一邊空位元組陣列、一邊有封面 → `['cover']`。
- [ ] **Step 2: 執行確認失敗。** `flutter test test/library/metadata_comparison_test.dart`（預期編譯失敗）。
- [ ] **Step 3: 實作純函式。** `metadata_comparison.dart`。
- [ ] **Step 4: 執行確認通過。** 同 Step 2 指令全過。
- [ ] **Step 5: 寫書庫對比整合測試。** `library_metadata_comparison_test.dart`（在手機上執行）：用 `openReadOnlyDatabase` 開 `getApplicationDocumentsDirectory()` 底下的 `library.db`，只查 EPUB 書籍（路徑、書名），查完書單後立刻 `await db.close()`，並**斷言 EPUB 本數大於 0**（書庫沒有 EPUB 時測試失敗，避免假綠）；記下 `library.db` 的大小與修改時間；對每本書各跑一次 Readium 通道的 `extractMetadata` 與 `readEpubMetadataOnAndroid`（**直接呼叫，不經派送函式**），量各自耗時；用 `diffBookMetadata` 比；每本印一行 `[library_comparison] {json}`（書名、路徑末段、兩邊耗時、差異欄位、兩邊是否失敗）；最後印彙總：總數、兩邊都成功且一致、有差異（依欄位）、只有 foliate 失敗、只有 Readium 失敗、兩邊都失敗（例如權限已收回，不算不一致）、兩邊耗時總和與中位數。結束時再讀一次 `library.db` 的大小與修改時間，**斷言與開始時相同**。測試通過條件：沒有差異且沒有「只有 foliate 失敗」；否則測試失敗並在訊息列出是哪幾本、哪些欄位。
- [ ] **Step 6: 靜態檢查與 Commit。** `flutter analyze` 乾淨；`node tool/check_integration_keys.js`、`node tool/check_l10n_hardcoded_strings.js` 通過。

```bash
git add app/lib/library/metadata_comparison.dart app/test/library/metadata_comparison_test.dart app/integration_test/library_metadata_comparison_test.dart
git commit -m "test(android): 書庫 EPUB 的 Readium 與 foliate-js metadata 對比（epic-66 Issue 12 Task 4）"
```

---

### Task 5：在 WAVE 上執行對比（需要手機連線）

**Files:**
- 無專案檔案異動；結果寫入報告。

- [ ] **Step 1: 確認裝置與備份。** `flutter devices` 確認 WAVE（`TCE70P24B2202374`）在線；依 Global Constraints 備份 `library.db`、`dictionary.db`、`shared_prefs` 並驗證；記下 `library.db` 的大小與時間。
- [ ] **Step 2: 執行對比。** 在 `app/` 執行 `flutter test integration_test/library_metadata_comparison_test.dart -d TCE70P24B2202374`，輸出存 scratchpad；擷取所有 `[library_comparison]` 行與彙總。
- [ ] **Step 3: 還原正常版本。** `flutter install --debug -d TCE70P24B2202374`（或 `adb install -r` 正常 debug APK），確認 `library.db` 大小與時間與 Step 1 相同、App 能正常啟動到書架。
- [ ] **Step 4: 判讀。** 全部一致且沒有「只有 foliate 失敗」才算過；有差異或失敗，逐本記錄原因（讀該書 OPF 看是 Readium 還是 foliate-js 的取值問題），**不要**為了讓測試過而改比較規則；若是 foliate-js 端的錯，停下來回報，由使用者決定要修 `metadata-probe.js` 還是記為已知差異。把結果寫進 `issue-12-report.md`（先建檔，Task 6 收尾）。

---

### Task 6：關卡、切換預設、報告與文件（需要使用者決定；BooksPad 需要使用者連線）

**Files:**
- Modify: `app/lib/library/android_book_metadata.dart`（旗標改為 `true`，僅在使用者同意後）
- Test: `app/test/library/android_book_metadata_test.dart`
- Create: `docs/epics/epic-66-windows-port/issue-12-report.md`
- Modify: `docs/epics/epic-66-windows-port/issues.md`（Issue 12 狀態；新增 Issue 18）、`docs/epics/epic-66-windows-port/epic.md`（新增決策 29）、本檔（勾選步驟）

- [ ] **Step 1: 請使用者在 BooksPad 跑同一支對比（可選，視裝置是否連線）。** 提供指令與保護規則（備份、`-r`、跑完還原正常版本）；`adb` 若很慢，先用 `adb devices` 與一個簡單指令量延遲，延遲過高就回報、由使用者決定是否仍要跑。BooksPad 的結果同樣寫進報告。
- [ ] **Step 2: 關卡（停下來問使用者）。** 把 WAVE（與 BooksPad，如有）的對比結果給使用者看：總數、一致數、差異欄位、foliate 失敗數、耗時比較。**使用者明確同意**才進 Step 3；否則旗標維持 `false`，報告記「對比未過／未切換」與原因，Task 6 的其餘文件照做。
- [ ] **Step 3: 切換預設（只在同意後）。** 旗標改為 `true`；測試改為斷言預設值，並補一個 `foliateFirst` 預設為 `true` 時 EPUB 先走 foliate-js 的測試；跑 `flutter test test/library`、`flutter analyze`。
- [ ] **Step 4: 切換後的手機冒煙（需要使用者）。** 在 WAVE 裝入新版，請使用者匯入 1～2 本 EPUB（含 1 本有封面、1 本版面特殊的），回報書架上書名、作者、封面是否正確；我用日誌確認走的是 foliate-js 而非退回 Readium。
- [ ] **Step 5: 寫 `issue-12-report.md`、新增決策 29、登記 Issue 18。** 報告：診斷與決策表、各 Task 結果、對比結果（每台裝置的總數與差異、耗時）、旗標狀態、保護規則執行紀錄（備份、`-r`、還原）、未驗證與已知限制。`epic.md` 決策 29：階段一做法、使用者選擇、旗標、退路。`issues.md`：Issue 12 狀態；新增 **Issue 18**（階段二：移除 Readium 相依與 `extractEpubMetadata`、把 `detectEpubLayout` 回填改走 foliate-js、清理 `third_party_licenses`，需先觀察一個版本；不排程）。
- [ ] **Step 6: 同步文件並勾選。** 本檔已完成步驟 `- [ ]` 改 `- [x]`。
- [ ] **Step 7: Commit。**

```bash
git add app/lib/library/android_book_metadata.dart app/test/library/android_book_metadata_test.dart docs/epics/epic-66-windows-port/issue-12-report.md docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/epic.md docs/epics/epic-66-windows-port/plans/plan-issue-12.md
git commit -m "feat(android): metadata 預設改用 foliate-js，Readium 留作退路（epic-66 Issue 12）"
```

（旗標未切換時，`git add` 不含 `android_book_metadata.dart` 與其測試，commit 訊息改為「docs: Issue 12 對比結果與報告」。）

---

## 審查處理紀錄（2026-11-08，`reviews/review-plan-issue-12.md`，外部審查，逐項對照程式碼後處理）

| 編號 | 查證結果 | 處理 |
|---|---|---|
| C1 通道引數 `path` 應為 `uri` | **屬實**：`BookMetadataChannel.kt` 第 83 行讀 `uri`，`book_import_service_impl.dart` 三處現行呼叫皆為 `'uri'`；我原本寫成 `path` | 已修（Task 3 Step 3），並新增 mock 通道斷言引數鍵的測試與 Review Focus 10 |
| C2 `readBookRange` 例外與攔截回呼 | **方向屬實、細節不同**：審查說「回傳 `null` 即 HTTP 404」不正確——`null` 是「讓 WebView 照常上網」（日誌裡未攔截的外部網址就會出現 `HOST_LOOKUP net::ERR_INTERNET_DISCONNECTED`）；`WebResourceResponse` 支援 `statusCode`／`reasonPhrase`，可明確回 404。「拋例外會讓探針乾等 30 秒」無法在沒有手機的情況下驗證，但防禦做法成本很低 | 部分採納：`readBookRange`／`bookLength` 維持往外拋（`bookLength` 在啟動 WebView 前拋出，讓派送函式快速退回 Readium）；攔截回呼改用 `interceptBookRange`，失敗一律回**明確的 404**、不拋、不回 `null`（Task 2） |
| I1 漏註冊 `onError` handler | **屬實**：`globalErrorCaptureJs` 呼叫 `callHandler('onError', …)`，原 Task 2 只註冊兩個 handler | 已修（Task 2 Step 3、Review Focus 3） |
| I2 `contains('://')` 誤判 `file://` | **屬實**：`Book.filePath` 可為 `file://`；repo 內多處以 `startsWith('content://')` 分流 | 已修（Task 1：`content://` 走通道、`file://` 轉本機路徑），新增測試 |
| I3 `ParcelFileDescriptor` 未 `use` | 成立（批次比對 100 多本時才會顯現；Android 慣例） | 已修（Task 1 Step 3、Review Focus 2） |
| I4 `runSerialized` 未落地 | **屬實**：Review Focus 承諾了序列化，Task 步驟沒寫 | 已修（Task 3：foliate 路徑包在 `runSerialized`，新增「依序執行」測試） |
| I5 書庫 0 本 EPUB 假綠 | 成立 | 已修（Task 4 Step 5 斷言本數大於 0、Review Focus 9） |
| M1 `maxBytes` 檢查次序 | 成立；Windows 的 `readFileRange` 是先用原始參數檢查 | 已修（Task 1 規格與兩個邊界測試） |
| M2 先 `close` 資料庫再比檔案狀態 | 成立 | 已修（Task 4 Step 5） |
| M3 `OpenableColumns.SIZE` 退路 | 成立（成本低，可減少不必要的退回 Readium） | 已修（Task 1） |
| M4 空位元組封面判斷 | 成立 | 已修（Task 4 Interfaces 與測試） |

## 已知風險

- `content://` 區段讀取、舊 WebView 91 上的探針都是新程式，只靠 Task 5 的手機實測驗證；WAVE 書庫只有 8 本且部分是測試書，真實書的樣本偏少（BooksPad 100 多本才是主要樣本）。
- BooksPad 的 `adb` 速度不穩；若連不上，階段一只有 WAVE 的結果，切換預設由使用者決定。
- 對比測試只比五個欄位，不比封面位元組；封面「有沒有」一致不代表兩邊挑到同一張圖，這點只能靠 Task 6 Step 4 的人工目視。
- 階段一旗標改為 `true` 後，每本 EPUB 匯入都多一個背景 WebView；匯入 100 多本時的總時間是否可接受，要看對比測試量到的耗時。
- `detectEpubLayout` 回填仍走 Readium，階段二（Issue 18）才處理。
- 沒有 release 版驗證，所有手機測試都是 debug 版。
