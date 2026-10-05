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
- `main()` 在 `AudioService.init` 之前還有多個 `await`（`pdfrxFlutterInitialize`、讀偏好、開資料庫、`webViewMajorVersionFuture`〔最長等 3 秒〕、`downloadableFontStore.prepare()`、`AudioSession.configure` 等）。這些不在本 Issue 範圍，但表示「冷啟動到書架」的總時間有本來就存在的底噪，量測必須用對照組（見 Task 0）。
- `ReaderScreen.dispose`（約第 752 行）目前**無條件** `widget.ttsAudioHandler?.detachController()`。`TtsAudioHandler` 是單一實例、`attachController` 會先 detach 前一個；閱讀器→單書搜尋→回閱讀器時會有兩個 `ReaderScreen` 同時存活。晚到注入讓「誰 attach、誰 detach」更容易交錯，見 Task 3 與 Review Focus 7。
- **規格更新（取代 `issues.md` Issue 2 原文）**：因採參數合併，`elinkbook_app_wiring_test`、`reader_screen_route_test` 等串接測試須改為斷言 holder 貫穿，不再是「不改而通過」；`tts_audio_handler_startup_test` 則是新增案例、既有案例不改。`issues.md` 已同步修正。
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
7. **兩個 `ReaderScreen` 並存時，handler 被錯誤的畫面綁住或被先關閉的畫面解綁。** → Task 3：`ReaderScreen` 記錄自己 attach 的 handler 與 controller；`dispose` 只在「handler 目前綁的就是自己的 controller」時才 detach；測試兩個畫面並存、先關後建立者／先關先建立者，handler 最終狀態正確。
8. **handler 晚到時使用者已在朗讀，系統通知狀態沒同步。** → Task 3 測 controller 已播放時晚到 attach，`playbackState.playing` 為 true。

## Task 0：量測基準（暫時除錯程式碼，不提交）

冷啟動本來就有其他 `await` 的底噪（見「已知事實」），所以必須量兩組、看差距，不能只量單一組絕對值。

- [ ] 暫時修改 `main.dart`（不提交）：在 `main()` 開頭記 `Stopwatch`；在 `runApp` 之後以 `addPostFrameCallback` 於首幀印出 `[T0-a4f2] first frame <ms>`（程式內計時，不靠截圖）。
- [ ] **對照組 A**：正常程式（真實 `AudioService.init`、不注入延遲），冷啟動 3 次，記首幀毫秒。
- [ ] **注入組 B**：在 `AudioService.init` 呼叫前加 `await Future.delayed(const Duration(seconds: 10))` 再照常呼叫真實 `init`（模擬「綁定拖了 10 秒才完成」），冷啟動 3 次。
- [ ] 記錄 A、B 與差距（B − A）到 `epic.md`。修復前預期差距約 10 秒；若不是，先弄清楚原因再往下做。
- [ ] 以 `grep "T0-a4f2"` 確認標記，`git checkout` 還原 `main.dart`，`git diff` 為空。

## Task 1：`TtsAudioHandlerHolder` 與背景啟動函式

**檔案：** `lib/reader/tts_audio_handler_startup.dart`、`test/reader/tts_audio_handler_startup_test.dart`（新增案例）。

- [ ] 規範建構子語意（三個命名建構子，測試與一般呼叫端依意圖選用）：
  - `TtsAudioHandlerHolder.ready(handler)`：handler 已就緒，不降級。
  - `TtsAudioHandlerHolder.degraded()`：handler 為 null，降級、提示待顯示。
  - `TtsAudioHandlerHolder.unavailable()`：handler 為 null，**未降級、不提示**（供只是需要傳一個依賴的一般測試最小改動使用，不會意外觸發提示）。
  - 背景啟動函式建立的 holder 初始為 `unavailable()` 狀態，init 結束後才變成 ready 或降級。
- [ ] 把 `test/reader/tts_degraded_notice_test.dart` 的案例（降級時 consume 第一次 true、之後 false；未降級恆 false）搬進 `tts_audio_handler_startup_test.dart`，改以 holder 的 `consumeDegradedNotice()` 表達。
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
- [ ] 移除 `TtsDegradedNotice` 類別，並**刪除** `test/reader/tts_degraded_notice_test.dart`（案例已在 Task 1 搬到 `tts_audio_handler_startup_test.dart`）。
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
  - 兩個 `ReaderScreen` 並存（閱讀器→單書搜尋→回閱讀器）：先關後建立者不會把前者的綁定拆掉；先關先建立者會解綁；最終 handler 狀態與實際存活的畫面一致。
  - controller 已在播放時 handler 晚到 → attach 後 `playbackState.playing` 為 true。
  - 降級提示在兩個畫面並存時只顯示一次。
- [ ] 實作：
  - `_ReaderScreenState` 記錄 `_attachedAudioHandler`；只在「controller 存在、handler 非 null、尚未 attach 過這個 handler」時 attach，避免通知多次造成重複 attach。
  - `dispose`：只在 handler 目前綁定的 controller 就是本畫面的 `_ttsController` 時才 detach。為此 `TtsAudioHandler` 新增 `detachController({TtsController? only})`（`only` 非 null 時，目前綁定的不是它就什麼都不做；不帶參數時行為與現在相同，既有 `tts_audio_handler_test` 不改）。
  - 降級提示收斂成單一方法 `_checkShowDegradedNotice()`：內含 `addPostFrameCallback`，post-frame 內先判 `!mounted` 再 `consumeDegradedNotice()` 再顯示；`initState` 與 holder 通知回呼都呼叫它。
  - `initState` 加 listener、`dispose` 移除。
- [ ] 跑觸及的測試檔；變異檢查：拿掉晚到 attach → 對應案例失敗。

## Task 4：`main()` 不再等待

- [ ] `main.dart`：`final ttsAudio = startTtsAudioHandlerInBackground(() => AudioService.init(...));`，不 `await`，直接傳給 `ElinkBookApp`。更新註解（失敗後不可重試、晚到注入）。
- [ ] `flutter analyze` 乾淨；`elinkbook_app_wiring_test` 通過。

## Task 5：驗證、審查、PR

- [ ] 完整 `flutter test`（`app/`，背景執行）。
- [ ] 真機（電子紙）：重複 Task 0 的 A、B 兩組（同一份暫時除錯程式碼），驗收標準：**B − A 差距在 0.5 秒內**（修復前約 10 秒）；再用故障 manifest 驗證降級提示仍出現（在書架等 init 失敗後進閱讀器，提示出現一次）；正常版媒體通知照常。驗證完還原。
- [ ] 同步更新 `issues.md` Issue 2 的狀態與測試要求（若實作時又有調整）。
- [ ] 獨立程式審查（報告存 `reviews/`），依意見修訂，記錄進 `epic.md`。
- [ ] 推送、開 PR；合併後更新 `epics.md`、`issues.md`、`epic.md`。F2 仍在，epic-61 不歸檔，除非人類決定放棄 F2。

## 人類已決定（2026-10-05）

1. **參數合併**：把 `ttsAudioHandler` 與 `ttsDegradedNotice` 合成一個 `TtsAudioHandlerHolder`（要改約 16 處既有測試，換來只需同步一個物件）。
2. **閱讀器已開啟時才降級**：立即補顯示提示一次。

## 計畫審查修訂記錄（2026-10-05，`reviews/review-plan-issue-2.md`）

- **已採納**：I-1（三個命名建構子，`unavailable()` 為不降級）、I-2（舊 notice 測試搬遷並在 Task 2 刪除）、I-3（規格更新註記並同步 `issues.md`）、M-1（`_attachedAudioHandler`）、M-2（單一 `_checkShowDegradedNotice()`）、M-4（晚到時已在播放的測試）。
- **不採納 M-3**（holder 覆寫 `dispose` 防護）：holder 在 `main()` 建立、隨 App 存活，不會被 dispose；ReaderScreen 只移除自己的 listener，不 dispose holder。為不會發生的情況加防護屬過度設計，若日後 holder 有了 dispose 時機再處理。
- **本人另外查證後加入**：Review Focus 7（`dispose` 無條件 detach 與多畫面並存，讀碼確認 `reader_screen.dart:752`）；Task 0 改為 A／B 兩組對照＋程式內計時（讀碼確認 `main()` 在 init 前有其他 `await`，單組絕對值有底噪）。
- **備註**：本報告檔在我收到代理摘要之後被改寫過（檔案時間晚於代理完成），其嚴重度統計（0／3／4）與代理回報的摘要（1／6／5）不一致。以上述兩項為我自己讀碼查證的結果；其餘依現存檔案內容處理。

