# PDF 匯入封面產生管線卡住——現況診斷（`/diagnose`）

**日期：** 2026-08-02
**性質：** 確認既有技術債（`docs/epics.md` 舊 Backlog 列）是否已被 `epic-18-reader-device-qa` 或 `epic-20-fxl-foliate-migration` 順帶修復。查證結論：**沒有**，兩個 Epic 皆未觸及匯入/封面產生管線，此技術債仍原封不動，正式立案為本 Epic。

---

## 原始問題（`epic-4-pdf-enhance` Issue 7 收尾驗證時發現，2026-07-14）

真實「匯入書籍」UI 流程匯入既有測試共用的極簡 PDF fixture（`app/test/fixtures/sample.pdf`，345 bytes、`MediaBox [0 0 200 200]`、無任何內容流的空白頁）後，書架卡片永久停在 0% 進度、無法完成匯入（等待 15 秒以上、App 程序仍存活、logcat 無例外訊息）。

## 本次查證過程

1. **文件面搜尋**：`epic-18-reader-device-qa/issues.md`、`epic-20-fxl-foliate-migration/issues.md` 全文搜尋「PDF」「封面」「cover」「匯入」「import」「timeout」「卡住」等關鍵字，兩者範圍完全是「閱讀器 UI 精修」與「FXL 渲染引擎遷移到 foliate-js」，沒有任何 Issue 觸及匯入流程或封面產生管線。少數關鍵字命中皆為與本問題無關的誤判（例如 Issue 8 大型 EPUB OOM 的 `TimeoutException` 是 `integration_test` 逾時，非本問題）。
2. **程式碼面核對**：
   - `app/lib/library/book_import_service_impl.dart`（匯入流程）的 `git log` 只有 `epic-17`／`epic-19` 的 commits，`epic-18`／`epic-20` 完全沒有改動過。
   - 原生封面產生程式碼 `BookMetadataChannel.kt` 的 `extractPdfMetadata()`（第 327-379 行）的 `git log` 同樣沒有任何 `epic-18`／`epic-20` commit，仍是原始寫法，沒有加上逾時或無內容流的防呆處理。

## 現況程式碼指認（供後續 Discovery 起點，非正式根因）

- **Dart 端**：`app/lib/library/book_import_service_impl.dart:247-266`——`_channel.invokeMapMethod('extractMetadata', ...)` 對原生 MethodChannel 呼叫沒有任何逾時（`Future.timeout()` 等）保護，只 catch `PlatformException`。若原生端 `result.success()`／`result.error()` 永遠不被呼叫，這個 `await` 會無限期卡住，且不會拋出任何例外——與回報現象（無 logcat 例外、App 程序存活、UI 永久停在 0%）完全吻合。
- **原生端**：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt:327-379`（`extractPdfMetadata()`）——`PdfRenderer(pfd)` → `renderer.openPage(0)` → `page.render(...)` 已包在 `withContext(Dispatchers.IO)` 內，理論上不會阻塞主執行緒，但若這幾步當中有任何一步對「有 `MediaBox` 但無內容流」的畸形 PDF 真的掛住不返回（尚未實測證實，只是程式碼閱讀後的假設），Dart 端就會如上一點所述永遠等不到回應。

## 待後續 Discovery 確認的開放問題（已於下方 `/grill-with-docs` 階段收斂完成）

1. 卡住的確切位置：是 `PdfRenderer` 建構／`openPage`／`render` 三者之一真的掛起，還是別的環節（例如 `takePersistableUriPermission` 或 `_copyToLocalStorage`）？需要用插樁或除錯器實測 `sample.pdf` fixture 重現後定位。
2. 修復方向：Dart 端加 `Future.timeout()` 保護＋降級為「無封面」（比照既有 `on PlatformException` 降級模式），或原生端本身補上逾時／例外處理，或兩者皆做。

---

# 第二階段：`/grill-with-docs` 真機重現與根因收斂（2026-08-02）

## Phase 1：建立重現迴圈

環境確認：無真機連接，但 `emulator -list-avds` 找到 `Pixel_5`／`Medium_Tablet` 兩個可用 AVD；隨後使用者接上真機 `9491G`（`3CEF42ECD491687`，Android 15/API 35，即原始回報所用同一台裝置），改用真機驗證。

**第一輪（純檔案路徑 + `content://` URI，皆自動化）：**

1. 既有 `book_metadata_channel_test.dart` 的「PDF 詮釋資料提取回傳非空的 coverBytes」測試（純檔案路徑）在真機上執行：**<1 秒完全通過**，`coverBytes` 非空。
2. 新增 `pdf_content_uri_metadata_test.dart`（比照 `content_uri_acceptance_test.dart` 對 EPUB 的做法，用 `FileProvider` 自我授權模擬真正 `content://` URI，呼叫 `extractMetadata` 時包 `.timeout(Duration(seconds: 20))` 防止測試本身卡死）：同樣 **<1 秒完全通過**。

結論：純檔案路徑與 `content://` URI 兩條分支，`extractPdfMetadata()` 本身都沒有問題——原始假設「`PdfRenderer` 對無內容流 PDF 缺乏逾時處理」在自動化重現中不成立。

## Phase 2：真機完整重現（比照原始「真實匯入書籍 UI 流程」）

既有 `manual_import_acceptance_test.dart` 檔頭註記：透過 `flutter test`（Android Instrumentation）啟動時，系統檔案選擇器不會正常回應，須改用 `flutter run`。依此指示：

1. `adb push` `sample.pdf` 至 `/sdcard/Download/sample.pdf`。
2. `flutter run -d 3CEF42ECD491687 --debug` 啟動正式 App（非測試 harness，就是真實生產程式碼）。
3. 全自動化操作：`adb shell input tap` 點擊書架空狀態的「匯入書籍」按鈕（`library_empty_import_button`）→ 系統檔案選擇器（SAF）開啟 → `adb shell input text` 搜尋 `sample.pdf` → 點擊該檔案。過程用 `adb exec-out screencap` 搭配 Read 工具（可讀圖片）逐步視覺確認每一步畫面。
4. **完整重現原始回報畫面**：書架出現一張「sample」卡片，顯示「0%」，無可見封面縮圖——與原始回報「書架卡片永久停在 0% 進度」的敘述完全一致，且在畫面停留 40+ 秒後狀態不變（排除純粹是短暫載入中的可能）。

## Phase 3：插樁定位（`DIAG21` 標記，已於結案前完整移除）

在真實生產程式碼路徑插入暫時性 logcat／`print` 插樁（`BookMetadataChannel.kt` 的 `extractPdfMetadata`／`takePersistableUriPermission`／`openParcelFileDescriptor`；`book_import_service_impl.dart` 的 `_importSingleFile`），重複 Phase 2 的真機操作，logcat 完整時間軸如下：

```
06:32:51.488 takePersistableUriPermission ENTER
06:32:51.490 takePersistableUriPermission SUCCESS
06:32:51.497 Dart: before invokeMapMethod extractMetadata
06:32:51.498 extractPdfMetadata ENTER
06:32:51.626 IO-block start
06:32:51.635 openParcelFileDescriptor branch=content
06:32:51.662 openParcelFileDescriptor returned, null? false
06:32:51.713 PdfRenderer created
06:32:51.728 openPage(0) done, w=200 h=200
06:32:51.734 page.render() done
06:32:51.738 bitmapToPngBytes done, size=263
06:32:51.753 IO-block returned, pngBytes null? false
06:32:51.753 result.success() called
06:32:51.761 Dart: after invokeMapMethod, metadata keys=(title, author, coverBytes)
06:32:51.813 Dart: before insertBook
06:32:51.833 Dart: insertBook done
```

**全程僅 345 毫秒，完全成功，無任何例外、無任何卡住。** 這直接推翻了「封面產生管線卡住」的原始假設。

## Phase 4：找出視覺上「看起來像卡住」的真正原因

用 `adb shell run-as cc.ugotit.elinkbook cat <covers 目錄下的 png> | adb exec-out ...`（注意：透過 `adb shell ... > file` 重導向會被 Windows/Git Bash 的文字模式轉換損壞二進位內容，NUL/LF 位元組被竄改；必須改用 `adb exec-out run-as ... cat ... > file` 避免 shell PTY 的文字轉譯）把裝置上實際產生的封面檔案（263 bytes）抓下來檢視：**是一張完全純白的 200×200 PNG**。

根因結論（三個因素疊加造成「看起來卡住」的視覺錯覺）：

1. `sample.pdf` 頁面本身無 `/Contents`（PDF 規格上合法的空白頁），`PdfRenderer` 渲染出的封面自然是純白畫面。
2. `_BookCover`（`app/lib/screens/library_screen.dart:970-984`）用 `Image.file()` 顯示封面，純白圖片在 App 淺色主題背景下完全融入背景、肉眼不可見（`ColoredBox` 灰底格式圖示佔位邏輯只在「沒有 `coverPath` 或檔案不存在」時才會用到，本案例封面檔案確實存在且合法，不會走到佔位分支）。
3. 書架只有這一本書時，`SliverGridDelegateWithFixedCrossAxisCount`（`childAspectRatio: 0.62`）算出的單格高度很高，書名／進度文字因此被推到畫面中段（非緊接在工具列下方），加深「畫面空白」的錯覺。
4. 匯入成功當下完全沒有任何提示（`_showDuplicateSkippedSnackBar` 只在有重複跳過時才顯示），使用者無從得知「其實已經匯入成功了」。

## 結論

原始回報並非真實 bug，`docs/epics/epic-21-pdf-import-cover-fix/issues.md` Issue 1 已改列 wontfix 並記錄完整根因；意外發現的「匯入成功缺乏正面回饋」UX 缺口另立 Issue 2 追蹤。插樁已於結案前完整移除（`git diff` 確認兩個原始檔案與 `main` 完全一致）；新增的 `app/integration_test/pdf_content_uri_metadata_test.dart` 保留作為永久回歸測試（填補「PDF + 真正 `content://` URI」原本的測試空白）。
