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
- 受影響的測試（grep 的是「行數」，不是測試數）：`library_screen_test.dart`（4 行）、`reader_screen_route_test.dart`（3 行）、`reader_screen_test.dart`（9 行）傳 `ttsAudioHandler:`，合計 16 行，實際約 8 到 10 個測試、約 25 行要改；Issue 1 的測試檔（`tts_degraded_notice_test`、`reader_screen_tts_degraded_notice_test`、`reader_screen_route_test`、`elinkbook_app_wiring_test`、`reader_screen_test` 的單書搜尋轉送）傳 `ttsDegradedNotice:`。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **`AudioService.init` 只呼叫一次，失敗後不可重試**（見 `initTtsAudioHandlerSafely` 說明）。背景執行不改變這點。
- **零回歸**：handler 一開始就就緒、或從未傳 holder（既有測試與呼叫端）時，行為與目前相同。
- **不吞掉錯誤**：`initTtsAudioHandlerSafely` 的行為（接住所有例外、`debugPrint`、回傳 null）不變，holder 只是它的外層。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後跑一次，在 `app/` 目錄下用 `run_in_background`。已知 `pdf_reader_view_filters_test.dart`「各頁互不取消」在全套負載下會失敗（基準分支也是，見 `epic.md`），不算本 Issue 的回歸。
- **提交前**：`flutter analyze` 乾淨；`node tool/check_l10n_hardcoded_strings.js`；本 Issue 不新增字串。
- **分支**：`epic-61/non-blocking-audio-init`（從最新 `main` 開）。沿用本專案前幾個 Issue 的作法，在同一個工作目錄切分支，不另開 git worktree。
- **Commit**：每個 Task 結尾提交一次（Task 0 的暫時除錯程式碼不提交）；訊息以 `feat(epic-61):`／`test(epic-61):`／`docs(epic-61):` 開頭；結尾帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：計畫先審查再動手；程式審查先出報告，存 `reviews/`（gitignore），審查者不直接改程式。
- **真機驗證**（電子紙，需 `MSYS_NO_PATHCONV=1`）：用暫時的除錯程式碼製造可控的綁定逾時；驗證完必須還原（`git diff` 為空）。SnackBar 約 4 秒，需在裝置端連拍。

## Review Focus

最可能咬到使用者的情況，每條都有對應測試或實測：

1. **handler 在 `TtsController` 建立之後才到，沒有 attach，媒體通知與鎖屏控制整次不出現。** → Task 3 測「先建立 controller、後注入 handler → 被 attach」。
2. **handler 晚到時，目前開著的書是舊 `ReaderScreen`，換書／離開後 handler 還綁著舊 controller。** → Task 3 測 dispose 後 `detachController`，且不再收到 holder 通知（listener 必須移除）。
3. **降級發生在閱讀器已開啟之後：提示永遠不出現，或出現兩次。** → Task 3 測晚到失敗立即提示一次，之後重進不重複。
4. **`ReaderScreen` dispose 後 holder 才通知，對已卸載的 State 呼叫 `setState`／`ScaffoldMessenger`。** → listener 在 `dispose` 移除；回呼內先判 `mounted`。
5. **init 永遠不回來（連逾時都沒有）。** → App 照常使用，handler 維持 null、不提示；Task 1 測。
6. **改參數型別造成既有測試大量修改。** → 保留「直接傳 handler」的便利：holder 提供 `ready(handler)`／`degraded()`／`unavailable()` 三個建構子，測試以最小改動換上（語意見 Task 1）。
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

- [x] 介面草稿（`tts_audio_handler_startup.dart`）：

  ```dart
  /// 啟動階段 TTS 音訊服務的狀態。
  enum TtsAudioHandlerStatus { pending, ready, failed }

  class TtsAudioHandlerHolder extends ChangeNotifier {
    TtsAudioHandlerHolder.ready(TtsAudioHandler handler);   // status = ready
    TtsAudioHandlerHolder.degraded();                       // status = failed，提示待顯示
    TtsAudioHandlerHolder.unavailable();                    // status = pending，不提示

    TtsAudioHandlerStatus get status;
    TtsAudioHandler? get handler;        // 只有 ready 時非 null
    bool consumeDegradedNotice();        // 只有 failed 且尚未提示時回 true，並標記已提示
  }

  /// 同步回傳 holder（status = pending），背景跑 init，完成後改成 ready 或 failed 並通知。
  TtsAudioHandlerHolder startTtsAudioHandlerInBackground(
    Future<TtsAudioHandler> Function() init,
  );
  ```
- [x] 規範狀態語意（回應審查：`unavailable()` 不再模糊）：`pending`＝初始化中（或測試中「不關心 TTS」的預設），`failed`＝初始化已失敗，兩者 `handler` 都是 null，但只有 `failed` 會提示。三個建構子的意圖：
  - `TtsAudioHandlerHolder.ready(handler)`：handler 已就緒（`ready`），不降級。
  - `TtsAudioHandlerHolder.degraded()`：handler 為 null，初始化已失敗（`failed`）、提示待顯示。
  - `TtsAudioHandlerHolder.unavailable()`：handler 為 null，初始化中（`pending`），**不提示**（供只是需要傳一個依賴的一般測試最小改動使用，不會意外觸發提示）。
  - 背景啟動函式建立的 holder 初始為 `pending`，init 結束後才變成 `ready` 或 `failed`；狀態只會單向轉移，不會從 `failed` 或 `ready` 回到 `pending`。
- [x] 把 `test/reader/tts_degraded_notice_test.dart` 的案例（降級時 consume 第一次 true、之後 false；未降級恆 false）搬進 `tts_audio_handler_startup_test.dart`，改以 holder 的 `consumeDegradedNotice()` 表達。
- [x] 先寫測試（紅）：
  - `startTtsAudioHandlerInBackground` 在 init 尚未完成時就同步回傳，holder `handler == null`、尚未降級。
  - init 成功 → holder 有 handler、通知 listener 一次、不降級。
  - init 丟例外 → holder `handler == null`、通知一次、降級待提示。
  - init 永遠不完成 → 不丟例外、不阻塞。
  - `consumeDegradedNotice()`：降級後第一次 true、之後 false（沿用 Issue 1 語意）；未降級恆 false。
  - `ready(handler)`／`unavailable()` 建構的初始狀態。
- [x] 實作 `TtsAudioHandlerHolder`；保留 `TtsDegradedNotice` 直到 Task 2 換完，最後移除（避免兩套並存）。
- [x] 跑 `flutter test test/reader/tts_audio_handler_startup_test.dart`；變異檢查：讓 holder 失敗時不通知 → 對應案例失敗。
- [x] 提交（`feat(epic-61): 新增 TtsAudioHandlerHolder 與背景啟動函式`）。

## Task 2：換掉往下傳的參數

**檔案：** `main.dart`（`ElinkBookApp`）、`library_screen_dependencies.dart`、`reader_screen_route.dart`、`reader_screen.dart` 的建構子與手動重建 bundle 處（約第 1847 行，Issue 1 審查 I-1 的同一處）。

- [x] 把 `ttsAudioHandler` 與 `ttsDegradedNotice` 兩個欄位換成一個 `TtsAudioHandlerHolder? ttsAudio`；現有測試以 `ready(handler)`／`unavailable()` 最小改動更新。
- [x] 移除 `TtsDegradedNotice` 類別，並**刪除** `test/reader/tts_degraded_notice_test.dart`（案例已在 Task 1 搬到 `tts_audio_handler_startup_test.dart`）。
- [x] 串接測試（`reader_screen_route_test`、`elinkbook_app_wiring_test`、`reader_screen_test` 的單書搜尋轉送）改為驗證 holder 原樣轉交；變異檢查：拿掉任一轉送行 → 對應測試失敗。
- [x] 跑觸及的測試檔。
- [x] 提交（`refactor(epic-61): ttsAudioHandler／ttsDegradedNotice 合併為 holder 往下傳`）。

## Task 3：`ReaderScreen` 晚到注入

**檔案：** `reader_screen.dart`、`test/screens/reader_screen_tts_degraded_notice_test.dart`、新增 `test/screens/reader_screen_tts_late_handler_test.dart`。

- [x] 先寫測試（紅），用記錄呼叫的 `TtsAudioHandler` 子類別：
  - controller 已建立、handler 晚到 → `attachController` 被呼叫一次，書名正確。
  - handler 先到、後建 controller → 行為與現況相同。
  - dispose 後 holder 再通知 → 不例外、不 attach；dispose 時 `detachController` 被呼叫。
  - 閱讀器已開啟後才降級 → 立即顯示提示一次；之後重進不重複；未降級不顯示。
  - 既有 Issue 1 的 4 個案例（初始降級、重進不重複、未降級、未傳 holder）全數保留。
  - 兩個 `ReaderScreen` 並存（閱讀器→單書搜尋→回閱讀器）：先關後建立者不會把前者的綁定拆掉；先關先建立者會解綁；最終 handler 狀態與實際存活的畫面一致。
  - controller 已在播放時 handler 晚到 → attach 後 `playbackState.playing` 為 true。
  - 降級提示在兩個畫面並存時只顯示一次。
- [x] 實作：
  - `_ReaderScreenState` 記錄 `_attachedAudioHandler`；只在「controller 存在、handler 非 null、尚未 attach 過這個 handler」時 attach，避免通知多次造成重複 attach。
  - `dispose`：只在 handler 目前綁定的 controller 就是本畫面的 `_ttsController` 時才 detach。為此 `TtsAudioHandler` 新增 `detachController({TtsController? only})`（`only` 非 null 時，目前綁定的不是它就什麼都不做；不帶參數時行為與現在相同，既有 `tts_audio_handler_test` 不改）。
  - 降級提示收斂成單一方法 `_checkShowDegradedNotice()`：內含 `addPostFrameCallback`，post-frame 內先判 `!mounted` 再 `consumeDegradedNotice()` 再顯示；`initState` 與 holder 通知回呼都呼叫它。
  - `initState` 加 listener、`dispose` 移除。
- [x] 跑觸及的測試檔；變異檢查：拿掉晚到 attach → 對應案例失敗。
- [x] 提交（`feat(epic-61): ReaderScreen 支援 handler 晚到注入與多畫面並存`）。

## Task 4：`main()` 不再等待

- [ ] `main.dart`：`final ttsAudio = startTtsAudioHandlerInBackground(() => AudioService.init(...));`，不 `await`，直接傳給 `ElinkBookApp`。更新註解（失敗後不可重試、晚到注入）。
- [ ] `flutter analyze` 乾淨；`elinkbook_app_wiring_test` 通過。
- [ ] 提交（`feat(epic-61): main() 不再等待 AudioService.init`）。

## Task 5：驗證、審查、PR

- [ ] 完整 `flutter test`（`app/`，背景執行）。
- [ ] 真機（電子紙）：重複 Task 0 的 A、B 兩組（同一份暫時除錯程式碼），驗收標準：**B − A 差距在 0.5 秒內**（修復前約 10 秒）；再用故障 manifest 驗證降級提示仍出現（在書架等 init 失敗後進閱讀器，提示出現一次）；正常版媒體通知照常。驗證完還原。
- [ ] 同步更新 `issues.md` Issue 2 的狀態與測試要求（若實作時又有調整）。
- [ ] 獨立程式審查（報告存 `reviews/`），依意見修訂，記錄進 `epic.md`。
- [ ] 推送、開 PR；合併後更新 `epics.md`、`issues.md`、`epic.md`。F2 仍在，epic-61 不歸檔，除非人類決定放棄 F2。

## 人類已決定（2026-10-05）

1. **參數合併**：把 `ttsAudioHandler` 與 `ttsDegradedNotice` 合成一個 `TtsAudioHandlerHolder`（要改約 8 到 10 個既有測試，換來只需同步一個物件）。
2. **閱讀器已開啟時才降級**：立即補顯示提示一次。

## 計畫審查修訂記錄（2026-10-05）

審查報告有兩份：`reviews/review-plan-issue-2.md`（現存檔，原報告被改寫過，結論 0／3／4）與 `reviews/review-plan-issue-2v2.md`（依代理完成時的摘要重寫，結論 1／6／5，**原完整報告無法還原**）。人類指示以 v2 為準進行修訂；現存檔的建議若與 v2 不衝突也一併採納。

**v2 的項目與處理：**

- **C-1 多畫面並存**：已加 Review Focus 7、Task 3（`_attachedAudioHandler`、`detachController({only})`、多畫面測試）。
- **Task 0 量測**：改為程式內計時＋A（正常）／B（注入 10 秒 init 延遲）兩組對照，驗收改為 B − A 在 0.5 秒內。
- **holder 狀態語意**：新增 `TtsAudioHandlerStatus`（pending／ready／failed）與介面草稿，`unavailable()`＝pending、`degraded()`＝failed，單向轉移。
- **降級提示時序**：單一方法 `_checkShowDegradedNotice()`（post-frame、先判 `mounted` 再 `consume`），兩畫面並存只顯示一次的測試。
- **測試改動量**：更正為約 8 到 10 個測試、約 25 行（16 是 grep 行數）。
- **`issues.md` 衝突**：計畫標明「取代原文」，`issues.md` 已同步。
- **計畫格式**：補分支名、每個 Task 的提交步驟與 `Co-Authored-By`、holder 介面草稿；不另開 worktree，沿用既有慣例。

**現存檔（0／3／4）的項目：** I-1、I-2、I-3、M-1、M-2、M-4 已採納（與上面重疊或補強）。**不採納 M-3**（holder 覆寫 `dispose` 防護）：holder 在 `main()` 建立、隨 App 存活，不會被 dispose；`ReaderScreen` 只移除自己的 listener。為不會發生的情況加防護屬過度設計，若日後 holder 有了 dispose 時機再處理。

**驗證狀態**：「`dispose` 無條件 detach」（`reader_screen.dart:752`）與「`main()` 在 init 前有其他 `await`」已由本人讀碼確認；其餘為審查代理的讀碼判斷，未實機驗證。
