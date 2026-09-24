# `epic-47-resize-observer-false-error` （缺陷）全域 JS 錯誤捕捉把良性 ResizeObserver 警告誤報為開書失敗

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-47-resize-observer-false-error/`
**關聯 PRD 章節：** 無直接對應 FR（診斷與開書流程的穩定性）

## 背景

2026-09-25 epic-46 真機驗證時（AiPaper Reader C，Android 16，WebView Chrome 152），診斷日誌出現兩筆「openBook 失敗: JS Error: ResizeObserver loop completed with undelivered notifications」，其中一筆發生在使用者手動覆寫排版方向、不會預掃的情況，確認與 epic-46 無關。

`foliate_native_bridge.dart` 的 `globalErrorCaptureJs`（epic-18 Issue 33 為診斷舊版 WebView 開書卡住而加入，於 `AT_DOCUMENT_START` 注入）以 `window.onerror` 捕捉所有 ErrorEvent 並轉成 `onError`。Chromium 的 ResizeObserver loop 警告只是告知一輪 resize callback 沒能在同一 frame 內處理完，不是錯誤，但同樣會派送到 `window.onerror`。

影響：

- **閱讀器**：`reader_screen.dart` 的 `_handleError()` 只在載入中才切到錯誤畫面。書已顯示後觸發只會多一行誤導性日誌；載入完成前觸發則會把正常開啟的書誤判為開啟失敗。
- **全文索引**：`foliate_content_indexer.dart` 共用同一段腳本，準備完成前觸發時 `readyCompleter.completeError`，導致該書的全文索引失敗（Discovery 時追加發現，Backlog 登錄時未記載）。

## 開發記錄

**2026-09-25 `/diagnosing-bugs` 診斷**。流程依使用者選擇採直接 TDD：不另寫 `plans/plan-issue-N.md` 與計畫審查，也不做真機驗證（Puppeteer 場景已直接驅動同一份腳本與真實的 ResizeObserver 警告）。

- **回饋迴圈**：新增 `app/tool/foliate_touch_harness/scenario-resize-observer-false-error.mjs`，從 Dart 原始碼抽出 `globalErrorCaptureJs` 注入頁面，觸發真實的 ResizeObserver loop（callback 內改變被觀察元素自身尺寸）。
  - A：開書流程早期（DOMContentLoaded，尚未收到 `onPageRendered`）觸發，斷言沒有 `onError`
  - B：開書後觸發，斷言沒有 `onError`
  - C／D：頁面內真正的未捕捉例外、未處理的 Promise rejection 仍須回報（正向對照）
  - 另以 `addEventListener('error')` 記錄警告是否真的發生，作為前提檢查，避免空轉通過。
- **修正前**：A、B 穩定 FAIL（連跑 3 次），C、D PASS。
- **建構迴圈時的兩個陷阱**：`page.evaluate()` 注入的程式屬於另一個 script 來源，其例外會被 Chromium 遮蔽成「Script error.」，C／D 須改由頁面內 `<script>` 觸發；ResizeObserver 警告跨多個 frame 陸續送達，須等警告發生後再多等一段，否則會漏到下一個案例。
- **確認的原因**：`window.onerror` 沒有過濾任何訊息。
- **修正**：`globalErrorCaptureJs` 的 `window.onerror` 開頭，訊息含 `ResizeObserver loop` 就直接 return。以共同前綴比對，同時涵蓋新版「completed with undelivered notifications」與舊版「limit exceeded」。WebView 仍會把警告鏡射成 console `[ERROR]`，診斷線索不會消失。不修根源：警告來自 paginator／`main.js` 的 ResizeObserver，屬良性行為，改動 vendor 風險高。
- **修正後**：場景 6/6 PASS；`run-all.mjs` 全部 PASS；`flutter test test/reader/foliate_reader_view_test.dart test/screens/reader_screen_test.dart test/search` 全部通過；`flutter analyze` 乾淨；`check_l10n_hardcoded_strings.js` PASS。

**2026-09-25 程式審查修訂**（`reviews/review-code.md`，結論可合併，0 Critical／0 Important／3 Minor，全數採納）

- M-1：過濾條件收緊為 `!error && String(message).indexOf('ResizeObserver loop') === 0`。良性警告的 `error` 為 null、訊息以該前綴開頭；真正的未捕捉例外帶 Error 物件且訊息以 `Uncaught ` 開頭，不會被吞掉。新增正向對照 E：訊息以「ResizeObserver loop」開頭的真正例外仍須回報。
- M-2：場景的 `loadGlobalErrorCaptureJs()` 加上防呆：抽出的原始碼字面含 `\` 或 `$`（可能與 Dart 執行期字串不同）時直接中止。
- M-3：案例 A 在觸發當下記錄是否已收到 `onPageRendered`，新增前提檢查「確實在開書完成前觸發」；README 與本紀錄的用詞同步改為「開書流程早期」。
- 驗證：場景連跑 3 次皆 8/8 PASS。Mutation：改回舊條件（任意位置比對、不看 `error`）時 E FAIL；完全移除過濾時 A、B FAIL。

**2026-09-25 PR #274 已合併進 `main`**（merge commit `5706eb17`）。修正已全數完成。

下一步：依 SDD 流程歸檔。
