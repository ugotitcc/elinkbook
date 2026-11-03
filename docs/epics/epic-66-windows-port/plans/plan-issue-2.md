# Epic 66 Issue 2：Windows Metadata 背景解析 實作計畫

> **給執行計畫的代理：** 必須使用 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans 逐 Task 執行。步驟用 `- [ ]` 追蹤。

**Goal：** Windows 匯入 EPUB／PDF 時讀出書名、作者、`identifier`、是否固定版面、封面，格式與 Android 的 `extractMetadata` 相同，並與 Android Readium 逐本對比。

**Architecture：** EPUB 用 `HeadlessInAppWebView` 載入 foliate-js 的新模組 `metadata-probe.js`；PDF 用 `pdfrx` 渲染第 0 頁。兩者由 `extractWindowsBookMetadata()` 依格式分派，透過新的建構子參數 `metadataExtractor` 注入 `BookImportServiceImpl` 與 `SyncEngine`（匯入、重新連結、同步指紋回填三處都要用同一個解析器）；不注入（Android）就走原本的 channel，行為不變。

**Tech Stack：** Dart／Flutter、`flutter_inappwebview`（Windows WebView2）、`pdfrx`、foliate-js（Puppeteer 測試台）。

**Spec：** 沒有獨立 spec。權威依據是 `docs/epics/epic-66-windows-port/epic.md`（決策 7、15）與 `issues.md` 的「Issue 2 過關條件」「Issue 2 單元測試要求」。

## Global Constraints

- **語言：** 文件、註解、測試名稱一律正體中文；程式碼命名維持英文慣例。
- **Android 行為不變：** `BookImportServiceImpl` 新參數預設 `null`，`null` 時走原本 `kBookMetadataChannel` 路徑，逐字不變。
- **回傳契約（與 Android `extractMetadata` 相同）：** `Map<String, Object?>`，鍵為 `title`、`author`、`coverBytes`（`Uint8List?`）、`isFixedLayout`、`identifier`。PDF 只有 `title`（`null`）、`author`（`null`）、`coverBytes`。
- **PDF 封面：** PNG，最長邊不超過 600 px，不放大。
- **不改的檔案：** `main.js`、`app/android/**` 的原生程式（`app/android/app/src/main/assets/foliate/` 底下可新增檔案）。
- **Windows 環境：** 多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔；不要對整個既有檔案跑 `dart format`；`git add` 一律明確列檔。
- **Node：** 用 PowerShell 工具，先 `$env:PATH = "$env:PNPM_HOME;$env:PATH"`。Bash 工具的 Node 是 nvm 空殼。
- **Windows 整合測試：** 一次只跑一個檔，用 Bash 工具：`cd app && export MSYS2_ENV_CONV_EXCL=CL CL=/utf-8 PATH="/c/Users/huthief/bin:$PATH" && flutter test integration_test/windows_metadata/<檔名> -d windows`。
- **ES 相容：** 新增的 foliate JS 檔要通過 `node tool/check_foliate_es_compat.js`，不用 `Object.groupBy`、`Array.prototype.at()` 等新 API。
- **測試範圍（`CLAUDE.md`）：** 單一 Task 只跑異動觸及的測試檔；完整 `flutter test` 只在 Task 7 跑一次，`run_in_background`。
- **提交前：** `flutter analyze` 必須 `No issues found!`。
- **Commit：** 不加 `Co-Authored-By`；每個 Task 一個 commit。

## Review Focus

1. **作者與書名的形態：** foliate-js 的作者在 `metadata.author`（不是 `creator`），可能是字串、`{name, role}` 物件、或陣列；書名可能是語系物件（如 `{"zh-TW":"繁中書名"}`）。都要取「第一位／第一個」的純文字。→ Task 2。
2. **多筆 `dc:identifier`，以及指紋的三個呼叫點：** 取哪一筆決定同步指紋。Windows 取 foliate-js 的值（`unique-identifier` 指向的那筆），要與 Readium 對比；而且匯入、重新連結（`relinkBook` 的 `_readEpubIdentifier`）、同步回填（`SyncEngine._backfillFingerprintForBook`）三處都必須用同一個解析器，否則同一本書的指紋對不上。→ Task 2 釘住 foliate 的值，Task 5 接三處，Task 6 對比。
3. **損毀 EPUB、逾時、WebView 沒釋放：** 失敗要丟 `PlatformException`（匯入端既有降級），且 headless WebView 一定要釋放（之後再解析仍成功）。→ Task 4、5。
4. **同時多次匯入：** 不可同時開多個 headless WebView。`extractWindowsBookMetadata` 的 `epub` 分支必須用 `runSerialized` 包住整個解析。→ Task 4。
5. **224 MB EPUB 讀 metadata 的尖峰記憶體：** 要把整本讀進 WebView，可能與開書同量級（約 3.8 GB）。→ Task 7 量測並記錄。

---

## 檔案結構

| 檔案 | 動作 | 職責 |
|---|---|---|
| `app/tool/make_metadata_fixtures.mjs` | 建立 | 產生 8 份 metadata 測試 EPUB |
| `app/test/fixtures/metadata/*.epub`（8 份） | 建立 | 測試 fixture |
| `app/pubspec.yaml` | 修改 | 宣告 8 份 fixture 為 asset |
| `app/android/app/src/main/assets/foliate/metadata-probe.js` | 建立 | `readBookMetadata(file)` |
| `app/tool/foliate_touch_harness/scenario-metadata-probe.mjs` | 建立 | `metadata-probe.js` 的 Puppeteer 測試 |
| `app/lib/library/windows_pdf_cover.dart` | 建立 | `renderPdfCover()` |
| `app/lib/library/windows_epub_metadata.dart` | 建立 | `readEpubMetadataInWebView()`（headless 主機） |
| `app/lib/library/windows_book_metadata.dart` | 建立 | `extractWindowsBookMetadata()`、`runSerialized()` |
| `app/lib/library/book_import_service_impl.dart` | 修改 | `BookMetadataExtractor` 型別、建構子參數、else 分支、`_readEpubIdentifier` |
| `app/lib/sync/sync_engine.dart` | 修改 | 建構子參數 `metadataExtractor`、`_backfillFingerprintForBook` |
| `app/lib/main.dart` | 修改 | Windows 對 `BookImportServiceImpl` 與 `SyncEngine` 注入解析器 |
| `app/test/sync/sync_engine_test.dart` | 修改 | 指紋回填使用注入解析器的測試 |
| `app/integration_test/windows_metadata/pdf_cover_test.dart`、`epub_metadata_test.dart` | 建立 | Windows 實機測試 |
| `app/integration_test/metadata_comparison_test.dart` | 建立 | Android 端 Readium 輸出傾印 |
| `docs/epics/epic-66-windows-port/issue-2-report.md` | 建立 | 對比表、記憶體數字、結論 |

---

### Task 1：Metadata 測試 fixture

**Files：**
- Create：`app/tool/make_metadata_fixtures.mjs`、`app/test/fixtures/metadata/` 下 8 份 `.epub`
- Modify：`app/pubspec.yaml`

**Interfaces：**
- Produces：8 份 fixture，檔名與期望值如下表。Task 2、4、5、6 都以此表為準。`buildStoredZip` 取自 `tool/foliate_touch_harness/lib/harness.mjs`。

| 檔名 | OPF 特徵 | `title` | `author` | `identifier` | `isFixedLayout` | 有封面 |
|---|---|---|---|---|---|---|
| `meta_basic.epub` | 單一 `dc:creator`「王小明」（無角色）；`properties="cover-image"` 封面 | `基本書名` | `王小明` | `urn:uuid:meta-basic` | `false` | 是 |
| `meta_multi_identifier.epub` | 兩筆 `dc:identifier`：`id="isbn"`（`9789860000001`）在前、`id="pub-id"`（`urn:uuid:meta-multi-second`）在後；`unique-identifier="pub-id"` | `多識別碼` | `null` | `urn:uuid:meta-multi-second` | `false` | 否 |
| `meta_lang_titles_two_creators.epub` | 兩個 `dc:title`（`xml:lang="zh-TW"`「繁中書名」、`en`「English Title」）；兩位無角色 `dc:creator`（王小明、李小華） | `繁中書名` | `王小明` | `urn:uuid:meta-lang` | `false` | 否 |
| `meta_creator_role.epub` | 作者「張三」以 `refines` 宣告 `role=aut`；另一位「李四」`role=trl` | `角色作者` | `張三` | `urn:uuid:meta-role` | `false` | 否 |
| `meta_epub2_cover.epub` | EPUB2 式 `<meta name="cover" content="cover-img"/>`，manifest 的 `cover-img` 無 `properties` | `EPUB2 封面` | `null` | `urn:uuid:meta-epub2` | `false` | 是 |
| `meta_no_cover.epub` | **zip 內沒有任何圖片檔** | `無封面` | `null` | `urn:uuid:meta-nocover` | `false` | 否 |
| `meta_fixed_layout.epub` | `<meta property="rendition:layout">pre-paginated</meta>`，無封面 | `固定版面` | `null` | `urn:uuid:meta-fxl` | `true` | 否 |
| `meta_no_identifier.epub` | 沒有 `dc:identifier`，`<package>` 無 `unique-identifier` | `無識別碼` | `null` | `null` | `false` | 否 |

另兩份既有 fixture 一併納入對比：`sample.epub`（`identifier` `urn:uuid:00000000-0000-0000-0000-000000000001`，有封面）、`sample_fxl_svg_cover.epub`（固定版面，封面僅透過 alternates 可達，實測 foliate-js 讀得到封面）。

- [ ] **Step 1：實作 `make_metadata_fixtures.mjs`**

每份 fixture 是最小合法 EPUB3（`mimetype`、`META-INF/container.xml`、`OEBPS/content.opf`、`nav.xhtml`、一個章節）。有封面的用 1×1 PNG（`iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==`）。輸出到 `test/fixtures/metadata/`。結構比照 `scenario-writing-mode-autodetect.mjs` 的 `buildEpub`。

- [ ] **Step 2：執行並確認可重現**

Run（PowerShell，在 `app/`）：`$env:PATH = "$env:PNPM_HOME;$env:PATH"; node tool/make_metadata_fixtures.mjs` 兩次，比較第二次前後各檔 SHA-256。
Expected：8 個檔案存在；兩次 SHA-256 相同。

- [ ] **Step 3：在 `pubspec.yaml` 的 `flutter: assets:` 加 8 行**

格式 `    - test/fixtures/metadata/<檔名>`，緊接 `test/fixtures/sample.epub` 之後。Run：`flutter pub get`。Expected：無錯誤。

- [ ] **Step 4：Commit**

```bash
git add app/tool/make_metadata_fixtures.mjs app/test/fixtures/metadata app/pubspec.yaml
git commit -m "test(windows): 新增 metadata 解析測試 fixture（epic-66 Issue 2）"
```

---

### Task 2：`metadata-probe.js`

**Files：**
- Create：`app/android/app/src/main/assets/foliate/metadata-probe.js`
- Create：`app/tool/foliate_touch_harness/scenario-metadata-probe.mjs`

**Interfaces：**
- Consumes：Task 1 的 fixture 與期望表；`./view.js` 的 `makeBook(file)`（必須用相對路徑：Windows 端這個模組由 `/assets/foliate/metadata-probe.js` 載入，相對路徑才會解析成 `/assets/foliate/view.js` 而命中 Dart 的資產攔截；寫 `/view.js` 會 404。測試台把 foliate 目錄掛在根目錄，兩種寫法都會過，所以測試抓不到這個錯）。
- Produces：`export async function readBookMetadata(file: File): Promise<{title: string|null, author: string|null, identifier: string|null, isFixedLayout: boolean, coverBase64: string|null, coverType: string|null}>`，從 `/assets/foliate/metadata-probe.js`（Windows 端）取得。解析失敗時 reject。

- [ ] **Step 1：寫失敗的測試 `scenario-metadata-probe.mjs`**

用 `launchHarnessPage({ fixtureFileName: 'sample.epub' })` 開頁，再在頁面內 `await import('/metadata-probe.js')`，把每份 fixture（`test/fixtures/metadata/*.epub` 加 `sample.epub`、`sample_fxl_svg_cover.epub`）以 base64 傳入、組成 `File` 後呼叫 `readBookMetadata`。用 `report()` 輸出：

- Task 1 表格每列的 `title`、`author`、`identifier`、`isFixedLayout`，以及「有封面」（`coverBase64 !== null` 且 `coverType` 以 `image/` 開頭）與表中一致。
- `meta_no_cover.epub`：`coverBase64` 為 `null`。
- `sample_fxl_svg_cover.epub`：有封面、`isFixedLayout` 為 `true`。
- 隨機 1 KB 位元組組成的 `File`：`readBookMetadata` reject。

- [ ] **Step 2：執行並確認失敗**

Run（PowerShell，在 `app/tool/foliate_touch_harness/`）：`$env:PATH = "$env:PNPM_HOME;$env:PATH"; node scenario-metadata-probe.mjs`
Expected：FAIL（`/metadata-probe.js` 載入失敗）。

- [ ] **Step 3：實作 `metadata-probe.js`**

規則（ES 保守寫法，無 `Object.groupBy`、`.at()`）：

- `firstText(v)`：字串 → `trim()` 後非空才回傳；陣列 → 取第一個元素遞迴；物件有 `name` → 對 `name` 遞迴；其餘物件（語系物件）→ 取 `Object.values(v)[0]` 遞迴；其餘回 `null`。
- `title = firstText(book.metadata.title)`；`author = firstText(book.metadata.author)`。
- `identifier`：`book.metadata.identifier` 是字串且 `trim()` 非空才回傳 `trim()` 後的值，否則 `null`。
- `isFixedLayout = book.rendition?.layout === 'pre-paginated'`。
- 封面：`try { await book.getCover() }`，失敗或 `null` 都回 `coverBase64: null`；有值則以 `FileReader.readAsDataURL` 取逗號後的 base64，`coverType` 取 `blob.type`。
- 用相對路徑 `import { makeBook } from './view.js'`（理由見 Interfaces）。
- 讀完封面、組好回傳物件之後，在 `finally` 呼叫 `try { book?.destroy() } catch (_) {}` 釋放 ZipReader 快取（`epub.js` 的 `destroy()`）；`book` 建立前就失敗時略過。

- [ ] **Step 4：執行並確認通過**

Run（PowerShell）：在 `app/tool/foliate_touch_harness/` 執行 `$env:PATH = "$env:PNPM_HOME;$env:PATH"; node scenario-metadata-probe.mjs`；再在 `app/` 執行 `$env:PATH = "$env:PNPM_HOME;$env:PATH"; node tool/check_foliate_es_compat.js`。
Expected：全部 `[PASS]`；ES 相容掃描通過。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/assets/foliate/metadata-probe.js app/tool/foliate_touch_harness/scenario-metadata-probe.mjs
git commit -m "feat(foliate): 新增 metadata-probe 讀書名、作者、識別碼、封面（epic-66 Issue 2）"
```

---

### Task 3：PDF 封面

**Files：**
- Create：`app/lib/library/windows_pdf_cover.dart`
- Test：`app/integration_test/windows_metadata/pdf_cover_test.dart`

**Interfaces：**
- Produces：`Future<Uint8List?> renderPdfCover(String path, {int maxDimension = 600})`。檔案不存在或沒有任何頁面回 `null`；檔案損毀時 `pdfrx` 的例外直接往外丟。

- [ ] **Step 1：寫失敗的整合測試**

先 `await pdfrxFlutterInitialize()`。用 `test/fixtures/sample_multi_page.pdf`（複製到暫存檔）斷言：回傳的位元組開頭是 `89 50 4E 47`；用 `ui.instantiateImageCodec` 解出的寬、高都 ≤ 600 且至少一邊 > 0；不存在的路徑回 `null`。

- [ ] **Step 2：執行並確認失敗**

Run：`flutter test integration_test/windows_metadata/pdf_cover_test.dart -d windows`
Expected：FAIL（`renderPdfCover` 未定義，編譯錯誤）。

- [ ] **Step 3：實作 `renderPdfCover`**

比照 `integration_test/windows_spike/pdf_cover_test.dart` 的渲染流程：`PdfDocument.openFile` → 第 0 頁 → `scale = min(maxDimension / width, maxDimension / height, 1)`，寬高至少 1 → `render()` → `createImage()` → `toByteData(format: png)`。`finally` 釋放 `image`、`rendered`、`document`。先確認 `File(path).exists()`，不存在回 `null`；`openFile` 成功後若 `document.pages.isEmpty`，`dispose()` 並回 `null`，不可直接取 `pages[0]`（會丟 `RangeError`）。沒有零頁 PDF 的 fixture，這條靠審查把關，不寫測試。

- [ ] **Step 4：執行並確認通過**

Run：同 Step 2。Expected：PASS。

- [ ] **Step 5：Commit**

```bash
git add app/lib/library/windows_pdf_cover.dart app/integration_test/windows_metadata/pdf_cover_test.dart
git commit -m "feat(library): Windows 以 pdfrx 產生 PDF 封面（epic-66 Issue 2）"
```

---

### Task 4：EPUB headless 解析與分派

**Files：**
- Create：`app/lib/library/windows_epub_metadata.dart`、`app/lib/library/windows_book_metadata.dart`
- Test：`app/test/library/windows_book_metadata_test.dart`、`app/integration_test/windows_metadata/epub_metadata_test.dart`

**Interfaces：**
- Consumes：Task 2 的 `readBookMetadata`；Task 3 的 `renderPdfCover`；`loadWindowsFoliateAsset`、`loadWindowsFileBytes`、`windowsBookContentType`（`windows_reader_resources.dart`）；`windowsFoliateAssetRoot`（`foliate_native_bridge.dart`）；`appWebViewEnvironment`（`windows_webview_environment.dart`）。
- Produces：
  - `Future<Map<String, Object?>> readEpubMetadataInWebView(String epubPath, {Duration timeout = const Duration(seconds: 60)})`：回傳 `title`、`author`、`identifier`、`isFixedLayout`、`coverBytes`（`Uint8List?`）。逾時丟 `TimeoutException`；JS 錯誤丟 `StateError`。
  - `Future<T> runSerialized<T>(Future<T> Function() task)`：同時呼叫時依序執行；前一個失敗不影響下一個。
  - `Future<Map<String, Object?>?> extractWindowsBookMetadata(String uri, String format, {Future<Map<String, Object?>> Function(String)? epubReader, Future<Uint8List?> Function(String)? pdfRenderer})`。簽名與 Task 5 的 `BookMetadataExtractor` 相容。`epub` 分支必須把 `epubReader` 的整個呼叫包在 `runSerialized` 裡，全 App 同一時間只會有一個 headless WebView。

- [ ] **Step 1：寫失敗的單元測試 `windows_book_metadata_test.dart`**

注入假的 `epubReader`／`pdfRenderer`，斷言：

- `format` 為 `'epub'` 時呼叫 `epubReader` 並原樣回傳其結果。
- `format` 為 `'pdf'` 時回 `{'title': null, 'author': null, 'coverBytes': <渲染結果>}`。
- `format` 為 `'pdf'` 且 `pdfRenderer` 回 `null`，丟 `PlatformException(code: 'extraction_failed')`。
- `format` 為 `'txt'`、`'cbz'` 回 `null`，且兩個注入函式都沒被呼叫。
- `epubReader` 丟 `StateError`、`pdfRenderer` 丟 `Exception` 時，都被包成 `PlatformException(code: 'extraction_failed')`。
- `uri` 含 `://` 時丟 `PlatformException`（Windows 只收本機路徑）。
- `runSerialized`：同時啟動兩個以 `Completer` 控制的任務，第二個在第一個完成前不開始；第一個丟例外後第二個仍會執行。
- 同時呼叫兩次 `extractWindowsBookMetadata('a.epub', 'epub', epubReader: 假)`：第二次的 `epubReader` 在第一次完成前不開始（證明 `epub` 分支真的用了 `runSerialized`）。

- [ ] **Step 2：執行並確認失敗**

Run：`flutter test test/library/windows_book_metadata_test.dart`
Expected：FAIL（編譯錯誤）。

- [ ] **Step 3：實作 `windows_book_metadata.dart`**

依 Interfaces 與上列斷言實作。錯誤包裝時保留原例外的 `toString()` 當 `message`。

- [ ] **Step 4：執行並確認單元測試通過**

Run：同 Step 2。Expected：PASS。

- [ ] **Step 5：寫失敗的 Windows 整合測試 `epub_metadata_test.dart`**

先 `initAppWebViewEnvironment(userDataFolder: (await getApplicationSupportDirectory()).path)`。把 Task 1 表的 8 份加 `sample.epub`、`sample_fxl_svg_cover.epub` 從 `rootBundle` 複製到暫存檔，呼叫 `extractWindowsBookMetadata(path, 'epub')`，斷言每份的 `title`、`author`、`identifier`、`isFixedLayout`、有無封面與 Task 1 表一致；每份印一行 `[metadata_comparison] <檔名> <JSON>`（鍵為 `title`、`author`、`identifier`、`isFixedLayout`、`coverBytes` 改為 `coverSize`），供 Task 6 對比。另外：

- 隨機位元組組成的 `.epub`：丟 `PlatformException`。
- `readEpubMetadataInWebView(path, timeout: Duration(milliseconds: 1))`：丟 `TimeoutException`。
- 不存在的路徑：`extractWindowsBookMetadata` 丟 `PlatformException`。
- 逾時案例之後，再對 `meta_basic.epub` 呼叫一次仍成功（前一個 headless WebView 已釋放）。

- [ ] **Step 6：實作 `windows_epub_metadata.dart`**

- 先確認 `File(epubPath).existsSync()`，不存在丟 `StateError`。**不複製書檔**：Windows 的書本來就是本機路徑，直接讀原檔，避免 224 MB 大檔多一次磁碟複製與暫存清理。
- `HeadlessInAppWebView`：`webViewEnvironment: appWebViewEnvironment`，`useShouldInterceptRequest: true`。入口頁用固定網域（如 `https://foliate-metadata.local/probe.html`），內容由攔截回呼從 Dart 字串提供，是一段 `<script type="module">`：`import { readBookMetadata } from '/assets/foliate/metadata-probe.js'`，`fetch('/book/current.epub')` 組成 `File`，成功時 `callHandler('metadataResult', JSON.stringify(...))`，失敗時 `callHandler('metadataError', String(e))`。
- 攔截：`/assets/foliate/*` → `loadWindowsFoliateAsset(..., assetRoot: windowsFoliateAssetRoot)`；`/book/current.epub` → `loadWindowsFileBytes(epubPath)` 加 `windowsBookContentType('current.epub')`。比照 `integration_test/windows_spike/headless_metadata_test.dart`。
- `coverBase64` 轉 `Uint8List`（`base64Decode`）放進 `coverBytes`。
- `finally`：`dispose()` headless（不論成功、失敗、逾時）。

- [ ] **Step 7：執行並確認整合測試通過**

Run：`flutter test integration_test/windows_metadata/epub_metadata_test.dart -d windows`
Expected：PASS，並印出 10 行 `[metadata_comparison]`。

- [ ] **Step 8：Commit**

```bash
git add app/lib/library/windows_epub_metadata.dart app/lib/library/windows_book_metadata.dart app/test/library/windows_book_metadata_test.dart app/integration_test/windows_metadata/epub_metadata_test.dart
git commit -m "feat(library): Windows 以 headless foliate-js 解析 EPUB metadata（epic-66 Issue 2）"
```

---

### Task 5：接進匯入服務與同步引擎

**Files：**
- Modify：`app/lib/library/book_import_service_impl.dart`、`app/lib/sync/sync_engine.dart`、`app/lib/main.dart`、`app/test/sync/sync_engine_test.dart`
- Test：`app/test/library/book_import_service_metadata_extractor_test.dart`

**Interfaces：**
- Consumes：Task 4 的 `extractWindowsBookMetadata`。
- Produces：`typedef BookMetadataExtractor = Future<Map<String, Object?>?> Function(String uri, String format);`（放在 `book_import_service_impl.dart` 頂層）；`BookImportServiceImpl({..., BookMetadataExtractor? metadataExtractor})`、`SyncEngine({..., BookMetadataExtractor? metadataExtractor})`。

- [ ] **Step 1：寫失敗的測試**

`setUp` 比照 `test/library/book_import_service_missing_channel_test.dart`（假 repository、暫存封面目錄、匯入目錄）。注入假 `metadataExtractor`，匯入一個 `.epub` 檔，斷言：

- 假解析器收到 `(<路徑>, 'epub')`。
- 回傳 `{'title': '書名', 'author': '作者', 'identifier': ' urn:uuid:x ', 'isFixedLayout': true, 'coverBytes': <位元組>}` 時：`Book.title`、`author`、`isFixedLayout` 對應；`coverPath` 以 `<bookId>.png` 結尾且檔案內容等於 `coverBytes`；`contentFingerprint` 等於 `urn:uuid:x`（已 `trim()`）。
- 假解析器丟 `PlatformException`：書仍匯入，標題為檔名、`coverPath` 為 `null`、封面目錄沒有檔案。
- 不注入（`null`）：改用 mock 的 `elinkbook/book_metadata` channel，`extractMetadata` 被呼叫一次（Android 路徑不變）。
- 匯入 `.txt`：假解析器沒被呼叫。
- `relinkBook`（呼叫方式比照 `test/library/book_import_service_test.dart` 既有案例）：先用假解析器（回 `identifier` `urn:uuid:x`）匯入一本 EPUB，再重新連結同一本 → 成功（證明 `_readEpubIdentifier` 走解析器）；重新連結 `identifier` 不同的另一本 → `BookRelinkFailure(contentMismatch)`。
- `test/sync/sync_engine_test.dart`（比照第 257 行「書籍尚無指紋時，即時補算並回填後才推送」）：注入回 `identifier` 的假解析器，回填的 `content_fingerprint` 等於該 `identifier`；解析器丟 `MissingPluginException` 時不中斷，改用整檔 SHA-256。

- [ ] **Step 2：執行並確認失敗**

Run：`flutter test test/library/book_import_service_metadata_extractor_test.dart`
Expected：FAIL（編譯錯誤，`metadataExtractor` 參數不存在）。

- [ ] **Step 3：實作**

- 在 `book_import_service_impl.dart` 加 `typedef` 與建構子參數、欄位 `_metadataExtractor`。
- 修改 `else` 分支（`format` 為 `epub` 或 `pdf`）取得 `metadata` 的那一行：`_metadataExtractor != null` 時 `await _metadataExtractor!(resolvedUri, format.name)`，否則原本的 `kBookMetadataChannel.invokeMapMethod(...)`。其後的欄位讀取與既有 `on PlatformException`、`on MissingPluginException` 區塊不動。
- `_readEpubIdentifier(uri)`（`relinkBook` 用，約 297 行）：同樣 `_metadataExtractor != null` 時用 `await _metadataExtractor!(uri, 'epub')`，否則原 channel；既有 `PlatformException`、`MissingPluginException` 捕捉不動。少了這條，Windows 重新連結 EPUB 會因指紋（identifier 對整檔 SHA-256）對不上而必定失敗。
- `SyncEngine`：建構子新增 `BookMetadataExtractor? metadataExtractor`；`_backfillFingerprintForBook`（約 317 行）取 identifier 時同上，並多接 `on MissingPluginException`（取不到就退回整檔 SHA-256）。
- `main.dart`：在建構 `BookImportServiceImpl`（約 241 行）之前宣告 `final metadataExtractor = isWindowsPlatform ? extractWindowsBookMetadata : null;`，同時傳給 `BookImportServiceImpl` 與約 323 行的 `SyncEngine`，並加對應 import。

- [ ] **Step 4：執行並確認通過**

Run：`flutter test test/library/book_import_service_metadata_extractor_test.dart test/library/book_import_service_test.dart test/library/book_import_service_missing_channel_test.dart test/sync/sync_engine_test.dart test/elinkbook_app_wiring_test.dart`，再 `flutter analyze`。
Expected：全綠；`No issues found!`。

- [ ] **Step 5：Commit**

```bash
git add app/lib/library/book_import_service_impl.dart app/lib/sync/sync_engine.dart app/lib/main.dart app/test/library/book_import_service_metadata_extractor_test.dart app/test/sync/sync_engine_test.dart
git commit -m "feat(import): Windows 匯入、重新連結與同步回填使用 foliate-js／pdfrx 解析 metadata（epic-66 Issue 2）"
```

---

### Task 6：Readium 與 foliate-js 對比

**Files：**
- Create：`app/integration_test/metadata_comparison_test.dart`、`docs/epics/epic-66-windows-port/issue-2-report.md`

**Interfaces：**
- Consumes：Task 1 的 10 份 fixture（8 份新的加 `sample.epub`、`sample_fxl_svg_cover.epub`）；Task 4 印出的 `[metadata_comparison] <檔名> <JSON>`。
- Produces：對比表，供決策 7 修訂。

**注意：** 這個 Task 會在 BooksPad（`B78CW2508006423`）重新安裝本分支的 debug 版，蓋掉裝置上目前的 App。若「二次開書逾時」的偵測版（`debug/capture-logs`）還要用，做完後要重裝。Android 建置需 JDK 17：這台機器的 `flutter` 會選到 JDK 25 而失敗。執行前先問使用者是否同意改全域設定 `flutter config --jdk-dir="C:/Program Files/Microsoft/jdk-17.0.21.21-hotspot"`，做完用 `flutter config --jdk-dir=` 還原；使用者不同意就停下來，請使用者自行在 JDK 17 環境執行 Step 2 並貼回輸出。

- [ ] **Step 1：寫 Android 端傾印測試**

`metadata_comparison_test.dart`：對 10 份 fixture 各自複製成暫存檔，呼叫 `elinkbook/book_metadata` 的 `extractMetadata`（`format: 'epub'`），每份印一行 `[metadata_comparison] <檔名> <JSON>`，鍵與 Task 4 一致（`coverBytes` 換成 `coverSize`）。只斷言不丟例外。比照 `integration_test/book_metadata_channel_test.dart` 的 `_stageAssetAsFile`。

- [ ] **Step 2：在 BooksPad 執行**

Run：`cd app && flutter test integration_test/metadata_comparison_test.dart -d B78CW2508006423`
Expected：通過，印出 10 行（Readium 輸出）。

- [ ] **Step 3：寫對比報告 `issue-2-report.md`**

一張表：每份 fixture 一列，欄位為 `title`、`author`、`identifier`、`isFixedLayout`、`coverSize`，每欄顯示 Readium 值、foliate-js 值、是否一致。表後列出所有不一致，並為 `identifier` 不一致者說明同步風險（`book_content_fingerprint.dart` 優先用它當指紋）。

- [ ] **Step 4：Commit**

```bash
git add app/integration_test/metadata_comparison_test.dart docs/epics/epic-66-windows-port/issue-2-report.md
git commit -m "docs(epic-66): Issue 2 Readium 與 foliate-js metadata 對比（epic-66 Issue 2）"
```

---

### Task 7：大檔記憶體、文件修訂與收尾

**Files：**
- Modify：`docs/epics/epic-66-windows-port/issue-2-report.md`、`spike-report.md`、`epic.md`、`issues.md`

- [ ] **Step 1：量 224 MB EPUB 讀 metadata 的尖峰記憶體**

建置 release：`flutter build windows --release`（環境變數同 Global Constraints）。啟動 `build\windows\x64\runner\Release\elinkbook.exe`，用 PowerShell 取樣腳本（只計入 `elinkbook.exe` 及其子孫程序，每 0.1 秒讀工作集，每 2 秒重掃新程序）。匯入使用者提供的 224 MB EPUB，記下匯入期間 App 與 WebView2 的基準、尖峰、回落值，寫進 `issue-2-report.md`，並與 Issue 1 開書的 3.8 GB 比較。使用者沒有提供書就停下來向使用者要。

- [ ] **Step 2：修正 Issue 1 報告的錯誤**

`spike-report.md` 結論 2 的欄位備忘寫 `metadata.creator`，實測作者欄位是 `metadata.author`（字串、`{name, role}` 物件或陣列）；書名可能是語系物件。改正該段，並註明 Issue 1 探針因讀 `creator` 而作者恆為 `null`。`epic.md` 決策 7 的「作者欄位尚未實證」改為 Issue 2 的結論。

- [ ] **Step 3：依對比結果修訂決策 7**

在 `epic.md` 決策 7 補【Issue 2 結果】：列出 `identifier` 是否一致、是否可統一；不一致時寫明 Windows 單獨用 foliate-js、並指出同步風險。

- [ ] **Step 4：更新 `issues.md`**

Issue 2 狀態改為「🟡 驗證完成，待審查」。

- [ ] **Step 5：品質檢查**

Run（`app/`，PowerShell，每次先 `$env:PATH = "$env:PNPM_HOME;$env:PATH"`）：`node tool/check_foliate_es_compat.js`、`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`、`flutter analyze`；再跑一次完整 `flutter test`（`run_in_background`，只跑一個）。
Expected：腳本 exit 0；`No issues found!`；測試全綠。有失敗先判斷是否本 Issue 造成，不是就記為既有問題。

- [ ] **Step 6：Commit**

```bash
git add docs/epics/epic-66-windows-port
git commit -m "docs(epic-66): Issue 2 驗證報告與決策 7 修訂"
```

---

## 自我檢查

- **過關條件覆蓋：** 1（EPUB 欄位）→ Task 2、4；2（PDF 封面）→ Task 3；3（失敗降級、WebView 釋放）→ Task 4、5；4（Android 不變）→ Task 5；7（重新連結與同步回填）→ Task 5；5（對比表）→ Task 6；6（224 MB 記憶體）→ Task 7。
- **單元測試要求覆蓋：** `readBookMetadata` → Task 2；`renderPdfCover` → Task 3；`extractWindowsBookMetadata`（含逾時釋放）→ Task 4；`BookImportServiceImpl` 注入與 `relinkBook`、`SyncEngine` 回填 → Task 5。
- **型別一致：** `readBookMetadata` 的 `coverBase64`／`coverType`（Task 2）→ Task 4 轉 `coverBytes`；`extractWindowsBookMetadata` 簽名與 `BookMetadataExtractor`（Task 5）相容；回傳鍵與 Android 契約一致。
- **風險：** Task 6 需要實機與 JDK 17；Task 7 需要使用者的 224 MB 書。兩者缺了就停下來要。
