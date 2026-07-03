# Epic 0 — 技術骨架：工單清單 (Issues)

依 `spec.md` 拆解出的細粒度垂直切片工單，依序執行（每個工單建立在前一個之上）。每個工單皆為獨立可測試的交付項目。

---

## Issue 1：Flutter 專案初始化 + 最小導航殼

**Status:** ✅ 已完成並合併回 `main`（PR #1，merge commit `38c93a0`）。5 個任務全數通過個別審查與最終整分支審查；額外收到的 code review 報告（`reviews/review-issue-1.md`）中 1 項 Minor（app label 大小寫）已修正（commit `5d5282a`）。分支 `worktree-epic-0-issue-1` 與其 worktree 已完成階段性任務，保留於 `.claude/worktrees/epic-0-issue-1/`。

**依賴：** 無（起始工單）

**描述：**
建立針對 Android 的 Flutter 專案。實作最小導航殼：一個書架/圖書庫佔位畫面（顯示固定的範例書籍清單，暫不含真實圖書庫管理邏輯——那是 `epic-1-library` 的範圍）與一個設定頁佔位畫面，兩者可互相導航。

**單元測試要求：**
- Widget test：驗證書架畫面與設定頁畫面皆能渲染
- Widget test：驗證從書架畫面可導航至設定頁，並可返回

**驗收標準：**
- `flutter run` 可在 Android 模擬器/裝置上啟動 App，顯示書架佔位畫面
- 兩個畫面間的導航可正常運作且有對應測試涵蓋

---

## Issue 2：`ReaderScreen` 格式偵測邏輯

**Status:** ✅ 已完成實作，待人工合併（PR #2：https://git.jigong.org/huthief/elinkBook/pulls/2）。2 個任務皆通過 TDD 流程，`flutter test` 12/12 通過、`flutter analyze` 乾淨。分支 `worktree-epic-0-issue-2`，worktree 保留於 `.claude/worktrees/epic-0-issue-2/`。

**依賴：** Issue 1

**描述：**
實作 `ReaderScreen` widget 的格式偵測部分：給定檔案路徑，依副檔名/魔數判斷是 EPUB 還是 PDF。此階段先分派到暫時的佔位視圖（尚未接上真正的原生渲染），把「偵測邏輯」與「原生渲染整合」這兩件事分開測試。

**單元測試要求：**
- 純 Dart 單元測試（不需模擬器）：`.epub` 副檔名判定為 EPUB 格式
- 純 Dart 單元測試：`.pdf` 副檔名判定為 PDF 格式
- 純 Dart 單元測試：不支援或無副檔名的路徑，回傳明確的「未知格式」結果（不可拋出未預期例外）

**驗收標準：**
- 格式偵測邏輯可在不啟動模擬器的情況下用 `flutter test` 跑過
- `ReaderScreen` 依偵測結果分派到對應的佔位視圖

---

## Issue 3：原生 Android 模組 — `PdfReaderView`（`PdfRenderer`）

**Status:** ✅ 已完成實作與驗證，待人工建立 PR/合併。2 個任務皆通過 TDD 流程，`flutter analyze` 乾淨，`flutter test` 12/12 通過；兩項驗收用 `integration_test`（有效 PDF 觸發 `onPageRendered`、不存在路徑觸發 `onError`）與 Task 1 的 smoke test 皆已在真實裝置（9491G，Android 15 / API 35）上執行並通過。分支 `worktree-epic-0-issue-3-pdf-reader-view`，worktree 保留於 `.claude/worktrees/epic-0-issue-3-pdf-reader-view/`。

**依賴：** Issue 1

**描述：**
建立包裝 `android.graphics.pdf.PdfRenderer` 的原生 Android 模組，實作為 `PdfReaderView`，透過 `PlatformView` 暴露給 Flutter。實作 `spec.md` 定義的 platform channel 契約：`openBook(path)`、`onPageRendered()`、`onError(message)`。

**單元測試要求：**
- Flutter `integration_test`（真實 Android 模擬器/裝置）：對已提交版本控制的範例 PDF 測試檔呼叫 `openBook`，斷言 `onPageRendered` 被觸發（而非 `onError`）
- Flutter `integration_test`：對一個不存在或損毀的檔案路徑呼叫 `openBook`，斷言 `onError` 被觸發（而非 `onPageRendered` 或未預期崩潰）

**驗收標準：**
- 範例 PDF 測試檔已提交至版本控制（例如 `test/fixtures/sample.pdf`）
- 兩項 `integration_test` 皆通過

---

## Issue 4：原生 Android 模組 — `EpubReaderView`（Readium Kotlin toolkit）

**Status:** ready-for-agent

**依賴：** Issue 1

**描述：**
整合 Readium 的 `readium-kotlin-toolkit`，建立包裝它的原生 Android 模組，實作為 `EpubReaderView`，透過 `PlatformView` 暴露給 Flutter。實作與 Issue 3 相同的 platform channel 契約：`openBook(path)`、`onPageRendered()`、`onError(message)`。

**單元測試要求：**
- Flutter `integration_test`（真實 Android 模擬器/裝置）：對已提交版本控制的範例 EPUB 測試檔呼叫 `openBook`，斷言 `onPageRendered` 被觸發（而非 `onError`）
- Flutter `integration_test`：對一個不存在或損毀的檔案路徑呼叫 `openBook`，斷言 `onError` 被觸發

**驗收標準：**
- 範例 EPUB 測試檔已提交至版本控制（例如 `test/fixtures/sample.epub`）
- 兩項 `integration_test` 皆通過

---

## Issue 5：`ReaderScreen` 端到端整合（唯一 seam 完整驗證）

**Status:** ready-for-agent

**依賴：** Issue 2、Issue 3、Issue 4

**描述：**
把 Issue 2 建立的格式偵測邏輯，從「分派到佔位視圖」改為「分派到 Issue 3/4 建立的真正原生視圖」（`PdfReaderView`/`EpubReaderView`）。這一步完成後，`ReaderScreen` 就是 `spec.md` 定義的完整 seam：給定任一檔案路徑，畫面上會渲染出該書第 1 頁。

**單元測試要求：**
- Flutter `integration_test`：對範例 EPUB 檔案路徑呼叫 `ReaderScreen(filePath)`，斷言畫面渲染出非空白內容（`onPageRendered` 觸發）
- Flutter `integration_test`：對範例 PDF 檔案路徑呼叫 `ReaderScreen(filePath)`，斷言畫面渲染出非空白內容（`onPageRendered` 觸發）

**驗收標準：**
- 同一個 `ReaderScreen` seam 用兩個測試案例（EPUB、PDF）驗證，皆通過
- 這是 `spec.md`「測試決策」章節描述的驗證方式，此工單完成即代表該驗證方式已落實

---

## Issue 6：書架畫面串接「開啟書籍」流程

**Status:** ready-for-agent

**依賴：** Issue 1、Issue 5

**描述：**
把 Issue 1 的書架佔位畫面，串接到 Issue 5 完成的 `ReaderScreen`：點擊書架上的範例書籍項目（一個 EPUB、一個 PDF），導航至 `ReaderScreen` 並顯示該書內容。這讓「從書架點開一本書、看到內容渲染出來」成為一個從 App 正常入口即可觸及的真實使用者流程，而非測試專用的硬編碼呼叫。

**單元測試要求：**
- Flutter `integration_test`：從書架畫面點擊範例 EPUB 項目，斷言導航至 `ReaderScreen` 且內容成功渲染
- Flutter `integration_test`：從書架畫面點擊範例 PDF 項目，斷言導航至 `ReaderScreen` 且內容成功渲染

**驗收標準：**
- 兩項 `integration_test` 皆通過
- 此工單完成後，`epic-0-skeleton` 的目標（Flutter + Android + EPUB(Readium) + PDF 端到端）即達成，可準備歸檔
