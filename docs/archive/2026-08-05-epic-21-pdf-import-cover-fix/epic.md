# `epic-21-pdf-import-cover-fix` PDF 匯入封面產生管線卡住修復（技術債）

**狀態：** 🟢 已歸檔 (Archived)
**存放路徑：** `docs/archive/2026-08-05-epic-21-pdf-import-cover-fix/`
**關聯 PRD 章節：** FR-01

## 開發記錄

原記錄於本表獨立 Backlog 列，`epic-4-pdf-enhance` Issue 7 收尾驗證時發現（2026-07-14）：真實「匯入書籍」UI 流程匯入既有測試共用的極簡 PDF fixture（`app/test/fixtures/sample.pdf`）後，書架卡片永久停在 0% 進度，疑似封面產生管線對無內容流 PDF 缺乏逾時/錯誤處理。2026-08-02 `/diagnose` 確認 `epic-18-reader-device-qa`／`epic-20-fxl-foliate-migration` 皆未涵蓋此問題，正式立案獨立追蹤；同日以 `/grill-with-docs` 在真機（`3CEF42ECD491687`）用 `adb` 全自動操作真實系統檔案選擇器完整重現原始回報畫面，並以暫時性 logcat 插樁（結案前已完整移除，`git diff` 確認乾淨）精確量測整條真實匯入管線僅耗時 345 毫秒、完全成功、無任何卡住或例外——**Issue 1 結案為 wontfix：並非真實 bug**，真正原因是 `sample.pdf` 空白頁渲染出的封面恰為純白 PNG、在淺色主題背景下視覺上不可見，疊加單書書架格高過高、匯入成功缺乏任何提示，三者共同造成「看起來像卡住」的錯覺（完整證據見 `reviews/bugfix-repro.md`）；意外發現「匯入成功缺乏使用者可見正面回饋」的真實 UX 缺口另立 **Issue 2**，並已於同日完成實作：`library_screen.dart` 的 `_showDuplicateSkippedSnackBar` 重構為 `_showImportResultSnackBar(ImportResult)`，依成功/重複本數組合顯示單一合併提示（例如「已匯入 3 本，2 本已存在，已跳過」），新增 2 項 widget test，`flutter analyze` 乾淨、`flutter test` 721/721 通過；過程中新增 `app/integration_test/pdf_content_uri_metadata_test.dart` 並保留為永久回歸測試，填補「PDF + 真正 `content://` URI」原本的測試空白。**Epic 21 兩個 Issue（Issue 1 wontfix／Issue 2 完成）皆已結案**，已於 2026-08-05 由人類指定歸檔至 `docs/archive/2026-08-05-epic-21-pdf-import-cover-fix/`
