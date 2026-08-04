# Epic 21：PDF 匯入封面產生管線卡住修復（技術債）——工單清單

## Issue 1：匯入極簡/無內容流 PDF 導致書架卡片永久停在 0% 進度

**Status:** 🚫 不予處理（wontfix，2026-08-02 `/grill-with-docs` 真機重現後結案）。**經真機確鑿證據證實原始回報並非真實 bug**——完整根因與證據見下方「結案結論」，與最初標題「匯入封面產生管線卡住」描述的問題不存在。因這次調查意外發現的真實 UX 缺口（匯入成功缺乏任何使用者可見的正面回饋）已另立 **Issue 2** 追蹤。

**依賴：** 無。

**背景：** `epic-4-pdf-enhance` Issue 7 收尾驗證時發現（2026-07-14），原記錄於 `docs/epics.md` 獨立 Backlog 列。2026-08-02 `/diagnose` 確認 `epic-18-reader-device-qa`／`epic-20-fxl-foliate-migration` 皆未涵蓋此問題，正式立案獨立追蹤；同日以 `/grill-with-docs` 搭配真機重現完整查明根因（詳細過程見 `reviews/bugfix-repro.md`）。

**原始描述：** 真實「匯入書籍」UI 流程匯入既有測試共用的極簡 PDF fixture（`app/test/fixtures/sample.pdf`，345 bytes、`MediaBox [0 0 200 200]`、無任何內容流的空白頁）後，書架卡片永久停在 0% 進度、無法完成匯入（等待 15 秒以上、App 程序仍存活、logcat 無例外訊息）。疑似封面產生管線對無內容流 PDF 缺乏逾時/錯誤處理。

**結案結論（真機重現 + logcat 插樁確鑿證據）：**

1. **自動化測試排除「純檔案路徑」與「`content://` URI」兩條路徑本身有問題**：既有 `book_metadata_channel_test.dart` 直接呼叫 `extractMetadata`（純檔案路徑）對 `sample.pdf` 不到 1 秒即成功；新增的 `pdf_content_uri_metadata_test.dart`（比照 `content_uri_acceptance_test.dart` 用 `FileProvider` 自我授權模擬真正 `content://` URI，含 20 秒逾時保護防止測試本身卡死）同樣不到 1 秒成功——**本 Issue 新增這個測試檔並保留為永久回歸覆蓋**，填補了「PDF + 真正 `content://` URI」原本完全沒有測試涵蓋的空白。
2. **在真機（`3CEF42ECD491687`）上以 `flutter run` 啟動正式 App，用 `adb input tap`／`screencap` 全自動操作真實系統檔案選擇器（SAF），選取 `/sdcard/Download/sample.pdf`，完整重現了「書架卡片顯示『sample / 0%』」的畫面**——與原始回報描述一致。
3. **同時對 `BookMetadataChannel.kt`（`extractPdfMetadata`／`takePersistableUriPermission`／`openParcelFileDescriptor`）與 `book_import_service_impl.dart`（`_importSingleFile`）插入暫時性 `DIAG21` 標記的 logcat／`print` 插樁（已於結案前完整移除，`git diff` 確認兩檔案與 `main` 完全一致），量測到整條真實匯入管線（`takePersistableUriPermission` → `extractMetadata` → `PdfRenderer` 開檔/渲染 → `insertBook`）**全程僅耗時約 345 毫秒、完全成功、無任何例外**。
4. **真正原因是視覺錯覺，不是功能缺陷**：`sample.pdf` 頁面本身無 `/Contents`（合法的空白頁），`PdfRenderer` 渲染出的封面因此是一張純白 200×200 PNG（已從裝置抓下確認）。`_BookCover`（`app/lib/screens/library_screen.dart:970-984`）用 `Image.file()` 顯示這張圖時，純白封面在 App 淺色主題背景下完全融入背景、肉眼不可見；加上書架只有這一本書時，`SliverGridDelegateWithFixedCrossAxisCount`（`childAspectRatio: 0.62`）算出的單格高度很高，書名／進度文字因此被推到畫面中段而非緊接在工具列下方。使用者看到的「畫面空白、什麼都沒發生」其實是「匯入已成功完成，只是封面恰好是白的、標籤位置不顯眼」，且**匯入成功當下完全沒有任何提示**（`_showDuplicateSkippedSnackBar` 只在有重複跳過時才顯示）——三者疊加造成「看起來像卡住」的誤判，原始回報者很可能是在快速走查中做出此結論。

**單元測試要求（已完成）：** `app/integration_test/pdf_content_uri_metadata_test.dart` 已新增並保留，涵蓋「PDF + 真正 `content://` URI」呼叫 `extractMetadata` 的正常成功路徑（含逾時保護）。

**相關佐證：**
- `docs/epics/epic-21-pdf-import-cover-fix/reviews/bugfix-repro.md`（完整 `/diagnose` + `/grill-with-docs` 查證過程，含 logcat 原始輸出）
- `app/integration_test/pdf_content_uri_metadata_test.dart`（新增的永久回歸測試）
- `docs/archive/2026-07-14-epic-4-pdf-enhance/`（原始發現脈絡）

---

## Issue 2：匯入成功後缺乏任何使用者可見的正面回饋

**Status:** ✅ 已完成（2026-08-02）。`flutter analyze` 乾淨、`flutter test`（全專案）721/721 通過（含本 Issue 新增的 2 項 widget test）。

**依賴：** 無。

**背景：** 調查 Issue 1（見上）過程中發現：`library_screen.dart` 的 `_pickAndImportFiles()`／`_pickAndImportFolder()` 目前只在「有檔案因重複來源 URI 被跳過」時顯示 `_showDuplicateSkippedSnackBar()`；**匯入成功本身完全沒有任何 SnackBar／Toast／動畫等正面提示**，使用者只能靠「書架上多了一張卡片」自行注意到匯入結果。當新書封面恰好視覺上不明顯（例如本次 Issue 1 的全白封面案例，或未來其他導致封面內容與背景色接近的情況）、或使用者匯入後畫面沒有明顯捲動/刷新提示時，容易誤判為「匯入沒有反應／卡住」。

**決策（`/grill-with-docs` 確認）：** 提示形式選擇「合併成一則訊息」——不新增獨立的成功 SnackBar 與既有重複跳過 SnackBar 並存，避免使用者連續看到兩則提示；改把 `_showDuplicateSkippedSnackBar(int)` 重構為 `_showImportResultSnackBar(ImportResult)`，依 `importedBooks.length`／`skippedDuplicateCount` 組合决定單一訊息文字：
- 兩者皆為 0（例如選檔後全數格式不支援）：不顯示，維持既有行為。
- 只有成功、無重複：「已匯入 N 本書」。
- 只有重複、無成功：「N 本已存在，已跳過」（沿用既有文字，向後相容）。
- 兩者皆非 0：「已匯入 N 本，M 本已存在，已跳過」。

**實作：** `app/lib/screens/library_screen.dart` `_pickAndImportFiles()`／`_pickAndImportFolder()` 呼叫點改叫新的 `_showImportResultSnackBar(result)`；未額外新增視覺強調（自動捲動/高亮）——`/grill-with-docs` 決策範圍僅止於合併訊息本身，維持最小改動。

**單元測試要求（已完成）：** `app/test/screens/library_screen_test.dart` 新增 2 個 widget test（成功無重複時顯示「已匯入 N 本書」；成功且有重複時顯示合併訊息，並確認舊的單獨重複訊息不再出現），既有的「有重複被跳過時顯示提示」測試維持不動且仍通過（驗證向後相容文字）。

**驗收標準：** 匯入成功（無論有無重複跳過）皆會顯示對應的 SnackBar 提示；兩者皆為 0 時不顯示；`flutter analyze`／`flutter test` 全數通過。

**相關佐證：**
- `app/lib/screens/library_screen.dart:129-197`（`_pickAndImportFiles()`／`_pickAndImportFolder()`／`_showImportResultSnackBar()`）
- `app/test/screens/library_screen_test.dart`（新增的 2 項測試，緊接在既有重複跳過測試之後）
- `docs/epics/epic-21-pdf-import-cover-fix/reviews/bugfix-repro.md`（Issue 1 調查過程中發現此缺口的完整脈絡）
