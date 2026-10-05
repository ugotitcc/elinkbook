# Issue 2：AudioService 初始化不阻塞啟動（F1）實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** `main()` 不再 `await` `AudioService.init`，`runApp` 先執行；handler 與「降級提示」改為晚到注入。消除綁定逾時（約 10 秒）時整個 App 黑屏的等待。

**Architecture：** 新增 `TtsAudioHandlerHolder`（`ChangeNotifier`，`tts_audio_handler_startup.dart`），同時承載「handler 是否就緒」與「降級提示是否待顯示」，取代目前分開傳遞的 `ttsAudioHandler` 與 `ttsDegradedNotice` 兩個參數。新增 `startTtsAudioHandlerInBackground(init)`：同步回傳 holder，背景執行 `initTtsAudioHandlerSafely`，完成後寫入 holder 並通知。`ReaderScreen` 監聽 holder：handler 晚到時補 `attachController`；降級在閱讀器已開啟後才發生時，立即顯示提示。

**Tech Stack：** Flutter／Dart、`audio_service` 0.18.19、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 無（見 `epic.md`，已決定不補 `spec.md`）；工單見 `issues.md` Issue 2。

## 已知事實（本計畫的依據）

- `main.dart` 目前 `await initTtsAudioHandlerSafely(() => AudioService.init(...))`（約第 224 行），綁定逾時時要等約 10 秒才失敗，之後才 `runApp`。10 秒是推測值，Task 0 要量測。
- `ttsAudioHandler` 的使用處：`reader_screen.dart` 的 `attachController`（建立 `TtsController` 時，約第 3332 行）與 `dispose` 的 `detachController`（約第 735 行），皆 `?.`；其餘只是往下傳。`TtsController` 的建立不依賴 handler。
- `TtsDegradedNotice`（Issue 1，PR #324）現況：`main()` 在 `runApp` 前依 `handler == null` 決定 `degraded`；`ReaderScreen.initState` 的 post-frame 內 `consume()`。改成非同步後，「是否降級」要等 init 結束才知道。
- 受影響的測試：`library_screen_test.dart`（4 處）、`reader_screen_route_test.dart`（3 處）、`reader_screen_test.dart`（9 處）傳 `ttsAudioHandler:`；Issue 1 的 4 個測試檔傳 `ttsDegradedNotice:`。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **`AudioService.init` 只呼叫一次，失敗後不可重試**（見 `initTtsAudioHandlerSafely` 說明）。背景執行不改變這點。
- **零回歸**：handler 一開始就就緒、或從未傳 holder（既有測試與呼叫端）時，行為與目前相同。
- **不吞掉錯誤**：`initTtsAudioHandlerSafely` 的行為（接住所有例外、`debugPrint`、回傳 null）不變，holder 只是它的外層。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後跑一次，在 `app/` 目錄下用 `run_in_background`。已知 `pdf_reader_view_filters_test.dart`「各頁互不取消」在全套負載下會失敗（基準分支也是，見 `epic.md`），不算本 Issue 的回歸。
- **提交前**：`flutter analyze` 乾淨；`node tool/check_l10n_hardcoded_strings.js`；本 Issue 不新增字串。
- **流程**：計畫先審查再動手；程式審查先出報告，存 `reviews/`（gitignore），審查者不直接改程式。
- **真機驗證**（電子紙，需 `MSYS_NO_PATHCONV=1`）：用暫時的除錯程式碼製造可控的綁定逾時；驗證完必須還原（`git diff` 為空）。SnackBar 約 4 秒，需在裝置端連拍。

## Review Focus

最可能咬到使用者的情況，每條都有對應測試或實測：

1. **handler 在 `TtsController` 建立之後才到，沒有 attach，媒體通知與鎖屏控制整次不出現。** → Task 3 測「先建立 controller、後注入 handler → 被 attach」。
2. **handler 晚到時，目前開著的書是舊 `ReaderScreen`，換書／離開後 handler 還綁著舊 controller。** → Task 3 測 dispose 後 `detachController`，且不再收到 holder 通知（listener 必須移除）。
3. **降級發生在閱讀器已開啟之後：提示永遠不出現，或出現兩次。** → Task 3 測晚到失敗立即提示一次，之後重進不重複。
4. **`ReaderScreen` dispose 後 holder 才通知，對已卸載的 State 呼叫 `setState`／`ScaffoldMessenger`。** → listener 在 `dispose` 移除；回呼內先判 `mounted`。
5. **init 永遠不回來（連逾時都沒有）。** → App 照常使用，handler 維持 null、不提示；Task 1 測。
6. **改參數型別造成既有測試大量修改。** → 保留「直接傳 handler」的便利：holder 提供 `TtsAudioHandlerHolder.ready(handler)`／`.unavailable()` 建構，測試以最小改動換上。

## Task 0：量測基準（不寫產品程式）

- [ ] 暫時修改 `main.dart`（不提交）：在 `AudioService.init` 前 `await Future.delayed(const Duration(seconds: 10))` 再丟 `PlatformException`，模擬綁定逾時。
- [ ] 建置 debug、安裝到電子紙、冷啟動；裝置端每秒截圖，記錄「畫面離開全黑到出現書架」的秒數。重複 3 次，結果寫進 `epic.md`。
- [ ] `git checkout` 還原 `main.dart`，確認 `git diff` 為空。

## Task 1：`TtsAudioHandlerHolder` 與背景啟動函式

**檔案：** `lib/reader/tts_audio_handler_startup.dart`、`test/reader/tts_audio_handler_startup_test.dart`（新增案例）。

- [ ] 先寫測試（紅）：
  - `startTtsAudioHandlerInBackground` 在 init 尚未完成時就同步回傳，holder `handler == null`、尚未降級。
  - init 成功 → holder 有 handler、通知 listener 一次、不降級。
  - init 丟例外 → holder `handler == null`、通知一次、降級待提示。
  - init 永遠不完成 → 不丟例外、不阻塞。
  - `consumeDegradedNotice()`：降級後第一次 true、之後 false（沿用 Issue 1 語意）；未降級恆 false。
  - `ready(handler)`／`unavailable()` 建構的初始狀態。
- [ ] 實作 `TtsAudioHandlerHolder`；保留 `TtsDegradedNotice` 直到 Task 2 換完，最後移除（避免兩套並存）。
- [ ] 跑 `flutter test test/reader/tts_audio_handler_startup_test.dart`；變異檢查：讓 holder 失敗時不通知 → 對應案例失敗。

## Task 2：換掉往下傳的參數

**檔案：** `main.dart`（`ElinkBookApp`）、`library_screen_dependencies.dart`、`reader_screen_route.dart`、`reader_screen.dart` 的建構子與手動重建 bundle 處（約第 1847 行，Issue 1 審查 I-1 的同一處）。

- [ ] 把 `ttsAudioHandler` 與 `ttsDegradedNotice` 兩個欄位換成一個 `TtsAudioHandlerHolder? ttsAudio`；現有測試以 `ready(handler)`／`unavailable()` 最小改動更新。
- [ ] 串接測試（`reader_screen_route_test`、`elinkbook_app_wiring_test`、`reader_screen_test` 的單書搜尋轉送）改為驗證 holder 原樣轉交；變異檢查：拿掉任一轉送行 → 對應測試失敗。
- [ ] 跑觸及的測試檔。

## Task 3：`ReaderScreen` 晚到注入

**檔案：** `reader_screen.dart`、`test/screens/reader_screen_tts_degraded_notice_test.dart`、新增 `test/screens/reader_screen_tts_late_handler_test.dart`。

- [ ] 先寫測試（紅），用記錄呼叫的 `TtsAudioHandler` 子類別：
  - controller 已建立、handler 晚到 → `attachController` 被呼叫一次，書名正確。
  - handler 先到、後建 controller → 行為與現況相同。
  - dispose 後 holder 再通知 → 不例外、不 attach；dispose 時 `detachController` 被呼叫。
  - 閱讀器已開啟後才降級 → 立即顯示提示一次；之後重進不重複；未降級不顯示。
  - 既有 Issue 1 的 4 個案例（初始降級、重進不重複、未降級、未傳 holder）全數保留。
- [ ] 實作：`initState` 加 listener（`dispose` 移除）；建立 controller 時若 handler 已有就 attach；通知時若 controller 已存在且 handler 新到就 attach，若新降級且尚未提示就顯示提示；回呼先判 `mounted`。
- [ ] 跑觸及的測試檔；變異檢查：拿掉晚到 attach → 對應案例失敗。

## Task 4：`main()` 不再等待

- [ ] `main.dart`：`final ttsAudio = startTtsAudioHandlerInBackground(() => AudioService.init(...));`，不 `await`，直接傳給 `ElinkBookApp`。更新註解（失敗後不可重試、晚到注入）。
- [ ] `flutter analyze` 乾淨；`elinkbook_app_wiring_test` 通過。

## Task 5：驗證、審查、PR

- [ ] 完整 `flutter test`（`app/`，背景執行）。
- [ ] 真機（電子紙）：重複 Task 0 的暫時除錯程式碼，量到書架的秒數，目標 2 秒內（數值以 Task 0 基準修正）；再用故障 manifest 驗證降級提示仍出現（在書架等 init 失敗後進閱讀器，提示出現一次）；正常版媒體通知照常。驗證完還原。
- [ ] 獨立程式審查（報告存 `reviews/`），依意見修訂，記錄進 `epic.md`。
- [ ] 推送、開 PR；合併後更新 `epics.md`、`issues.md`、`epic.md`。F2 仍在，epic-61 不歸檔，除非人類決定放棄 F2。

## 人類已決定（2026-10-05）

1. **參數合併**：把 `ttsAudioHandler` 與 `ttsDegradedNotice` 合成一個 `TtsAudioHandlerHolder`（要改約 16 處既有測試，換來只需同步一個物件）。
2. **閱讀器已開啟時才降級**：立即補顯示提示一次。
