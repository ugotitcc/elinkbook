# Issue 43 實作計畫：開書時並行檢查雲端閱讀位置（PRD FR-19）

## 背景與根因

PRD FR-19：「開啟書籍時若偵測到雲端進度與本機當前位置不一致，須彈窗詢問使用者，不得靜默覆蓋」。
實作從未涵蓋「開書時」：衝突詢問只存在 `SyncEngine._syncReadingPositions()`（推送階段），且只處理本機 dirty 的書；checkpoint 只在 App 背景化、離開閱讀畫面、每 5 分鐘觸發（Epic 8 Issue 6 的測試甚至寫死「開書當下不應觸發 checkpoint」）。因此使用者要到離開書才被問到。

新機器場景加重：`position_synced_server_updated_at` 為 null，且 `_downloadReadingPositions()` 對「尚未匯入的書」略過但仍推進 cursor（本 Issue **不處理**，另列後續項目）。

## 設計決定（2026-11-16，使用者確認）

1. **並行**：開書不等檢查；檢查（含對話框）在背景進行。
2. **逾時 2 秒**，只涵蓋網路請求，不含使用者看對話框的時間；逾時視為「這次不檢查」，留給之後的 checkpoint。
3. **選保留雲端後**：引擎已把雲端位置寫入資料庫；因為並行、閱讀器已開在舊位置，`ReaderScreen` 須重讀位置並透過 `_surface.jumpTo` 跳轉（審查 I-1：不直接呼叫 `PdfReaderView`／`FoliateReaderView` 的 static 方法，降級邏輯已在 surface 內）。
   - **時序（審查 C-1）**：真機上渲染常需數秒，使用者可能在閱讀器渲染完成前就選了保留雲端，此時底層 View 會靜默丟棄跳轉（`PdfReaderView._jumpToPage` 在 `!isReady` 直接 return false；Foliate 在 controller 為 null 時忽略）。因此：`await prefsManager.load` 後先檢查 `mounted`；`_openBookFlow.isRendered` 為真才立即跳，否則暫存於 `_pendingCloudJumpPosition`，在 `_handlePageRendered()` 補跳並清除。
4. 帶 `initialJumpTarget`（搜尋結果、書籤開書）**不檢查**（**仍待使用者確認**，審查 M-1 提出，不自行定案）：使用者明確指定了位置，跳轉會推翻他的意圖。
5. 選保留本機：記下已確認的雲端時間戳並標成待推送，否則下載階段會靜默蓋掉本機。
6. 兩邊位置相同時不彈窗，只記時間戳。

## 已知風險（不在本 Issue 處理）

- 對話框尚未回答時使用者就離開閱讀畫面，`close()` 觸發的 checkpoint 推送階段可能對同一本書再問一次。
- 並行下使用者可能已翻了幾頁才選「保留雲端」，會被跳回雲端位置（符合使用者選擇，但體感需真機確認）。

## Tasks

- [x] **Task 1（紅→綠，引擎）**：`test/sync/sync_engine_open_check_test.dart` 起初 6 個測試（含審查 I-2 補的保留本機、位置相同兩個，現共 9 個，不含 Task 2 逾時測試時為 8 個）；實作 `SyncEngine.checkReadingPositionOnOpen()`。
- [x] **Task 2（紅）**：`SyncEngine.networkTimeout`（預設 2 秒）：`test/sync/sync_engine_open_check_test.dart` 逾時測試。
- [x] **Task 3（綠）**：`_refreshAuthToken` 與 `getList` **包在同一個 `.timeout(networkTimeout)` 內**（審查 I-3：兩段各自套用總長會翻倍到 4 秒；且不得涵蓋 `await resolver(...)`，使用者看對話框的時間不計）；`catch` 補 `on TimeoutException` 回傳 null。
  - **不採納** 審查建議的 `on SocketException`／`on http.ClientException`：pocketbase 0.24.0 `client.dart:348` 已把傳輸層例外一律包成 `ClientException`，現有 `on ClientException` 已涵蓋；只需補自己加的 `.timeout` 所拋的 `TimeoutException`。
- [x] **Task 4（綠）**：`SyncCheckpointTrigger.checkOnOpen`（注入、吞例外、未注入回 null）：`test/sync/sync_checkpoint_trigger_open_check_test.dart` 3 個通過。
- [x] **Task 5（紅）**：`test/reader/reading_session_open_check_test.dart`：`start()` 並行檢查、帶跳轉目標不檢查、僅保留雲端才通知、已離開不通知、無 trigger 不拋例外。
- [x] **Task 6（綠）**：`ReadingSession.start()` 呼叫 `checkOnOpen`，結果為 `keepCloud` 且尚未 `close()` 時呼叫 `onCloudPositionAccepted`。
- [x] **Task 7（紅）**：`test/screens/reader_screen_open_check_test.dart`（改用 `FakeReaderSurface` 觀察 `jumpTo`）：開書檢查一次、不阻擋顯示、帶跳轉目標不檢查、已渲染後保留雲端跳轉、**C-1 未渲染前保留雲端須等渲染完成才補跳**、保留本機／null 不跳、畫面已關閉不拋例外。
- [x] **Task 8（綠）**：`ReaderScreen` 傳入 `onCloudPositionAccepted`：`await prefsManager.load(bookId)` → `if (!mounted) return` → 更新 `_session.onPrefsLoaded(initialProgress: pos.progress)` → 取得雲端位置組成 `ReaderJumpTarget(cfi: epubLocatorJson, progression: progress, pdfPageIndex: pdfPageIndex)`；`_openBookFlow.isRendered` 為真就 `_surface.jumpTo(...)`，否則存入 `_pendingCloudJumpTarget`，於 `_handlePageRendered()` 補跳後清除。
- [x] **Task 9**：`main.dart` 把 `syncEngine.checkReadingPositionOnOpen` 注入 `SyncCheckpointTrigger`；`elinkbook_app_wiring_test.dart` 守衛：同一個 trigger 實例仍貫穿，且開書會呼叫到檢查。
- [x] **Task 10**：跑異動檔案測試、`flutter analyze`、`node tool/check_l10n_hardcoded_strings.js`；最後一個 Task 完成後跑一次完整 `flutter test`。
- [ ] **Task 11（真機）**：兩台裝置，A 讀到 X 並同步，B（或新機器）開同一本書：進書後出現對話框；選雲端跳到 X；選本機維持；離線開書不卡。

## 程式審查修正紀錄（2026-11-17，`reviews/review-code-issue-43.md`）

- **I-1**（並行續期競爭）：先寫 `與進行中的 checkpoint 並行` 兩個測試並確認修正前紅燈（開書檢查被略過／checkpoint 被誤判 `notLoggedIn`），再把 `checkReadingPositionOnOpen` 改為直接用已存 token 做唯讀查詢，不呼叫 `_refreshAuthToken`。token 過期時 401 由 `ClientException` 吞掉，過期提示仍交 checkpoint。
- **M-1**：刪除 `networkTimeout` 過時 TODO。
- **M-2**：`_handleCloudPositionAccepted` 對 `prefsManager.load` 加 `try/catch`＋`debugPrint`（先有紅燈測試）。
- **M-4**：確認 PDF `initialPageIndex` 只在 View `initState` 讀一次、Foliate 只在開書當下組參數，未渲染路徑更新 `_initialPosition` 無效且可能重複導覽，已移除，只留暫存補跳；加測「補跳只發生一次」。
- **M-5**：補 EPUB（Foliate）層級測試：已渲染／未渲染兩種時序，驗證 `cfi`、`progression` 組成。
- **未處理**：M-3（`onPrefsLoaded` 重建儲存器，影響小，維持現狀）、M-6（引擎註解「絕不拋例外」靠 `checkOnOpen` 兜底，維持現狀）。

## 測試限制

`reader_screen_open_check_test.dart` 以 `FakeReaderSurface` 驗證「ReaderScreen 下了正確的跳轉指令、時機正確」，但看不到底層 View 是否真的捲動，實際跳轉須 Task 11 真機確認；Task 11 須刻意測「剛開大檔書、尚未渲染完成就點保留雲端」（EPUB 與 PDF 兩端）。

## 後續項目（未處理）

- `_downloadReadingPositions()` 略過未匯入書籍卻推進 cursor，之後匯入的書永遠收不到雲端位置。
