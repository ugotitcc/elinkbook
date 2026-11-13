# `epic-53-sync-checkpoint-result` （重構＋缺陷）同步 checkpoint 直接回報結果

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-53-sync-checkpoint-result/`
**關聯 PRD 章節：** 同步（PocketBase）；關聯 ADR 0019／0020、已歸檔 `epic-50-sync-token-refresh`

## 背景

2026-09-30 `/improve-codebase-architecture` 檢視 epic-45／48／49／50／52／15，候選 1（Strong）：`SyncEngine.runCheckpoint()` 回傳 `Future<bool>`，`false` 有 5 種意義（已在同步中、未設定憑證、續期 401、帳號中途變動、網路錯誤）；「登入過期」被編碼成儲存狀態（token 空＋email 有），三個呼叫端各自事後反推：

- `SyncCheckpointTrigger`：checkpoint 後輪詢 `isSessionExpired()`。
- `SyncSettingsScreen._manualSync`：失敗後用 `isLoggedIn()`／`loadEmail()` 反推。
- `SyncSettingsScreen._load`：自己重寫 `!isLoggedIn && email != null`。

已知缺陷：同步中途登出時，`_manualSync` 走到 `_showSessionExpired(email ?? '')`，顯示「登入已過期」與空白 email。

## 設計決策（`/grilling` 定案）

| 決策 | 結論 |
|---|---|
| 結果形狀 | `enum`：`synced`／`alreadyRunning`／`notLoggedIn`／`sessionExpired`／`failed` |
| 持久狀態分工 | 結果型別管「這一次剛發生什麼」；`SyncAccountRepository.isSessionExpired()` 管「先前是否過期」，是唯一解讀「token 空＋email 有」的地方；`SyncSettingsScreen._load` 改呼叫它 |
| `SyncCheckpointTrigger` | 拿掉 `isLoggedIn`／`isSessionExpired` 注入，只留 `runCheckpoint`、`onSessionExpired`；`sessionExpired` 才提示，其餘靜默 |
| 手動同步遇 `alreadyRunning` | 不顯示提示 |
| 帳號中途變動 | 對應 `notLoggedIn`，手動同步不提示 |
| 開發流程 | 直接 TDD：不寫 plan，保留程式審查；只跑異動測試檔，發 PR 前跑一次全套 |

不牴觸任何 ADR，不新增 ADR。CONTEXT.md 新增詞條「登入過期（Session Expired）」。

## 開發記錄

**2026-09-30 登錄 Epic**，分支 `epic-53/sync-checkpoint-result`。

**2026-09-30 實作（直接 TDD）**

- **RED**：先寫測試「點擊立即同步期間使用者已登出（email 一併清除）」，以現行 `bool` 版本執行，確認失敗——畫面出現「登入已過期」（`email ?? ''` 空白預填）。
- 新增 `lib/sync/sync_checkpoint_result.dart`（`SyncCheckpointResult` enum，5 個值）。
- `SyncEngine.runCheckpoint()` 改回傳 enum：併發鎖 → `alreadyRunning`；無憑證／帳號中途變動（含舊請求 401 但 token 已換）→ `notLoggedIn`；續期 401 且清除 token → `sessionExpired`；其餘網路錯誤 → `failed`；整輪成功 → `synced`。
- `SyncCheckpointTrigger`：移除 `isLoggedIn`／`isSessionExpired` 注入，只在 `sessionExpired` 時呼叫 `onSessionExpired`；`main.dart` 對應調整。
- `SyncSettingsScreen`：`_manualSync` 對結果 switch（`alreadyRunning`／`notLoggedIn` 靜默）；`_load` 改用 `SyncAccountRepository.isSessionExpired()`，不再自己重寫判斷。`onManualSync` 型別在 `main.dart`、`library_screen_dependencies.dart`、`settings_scaffold.dart` 同步改為 `Future<SyncCheckpointResult> Function()?`。
- 測試：`sync_checkpoint_trigger_test.dart` 重寫；`sync_engine_test.dart` 斷言改 enum（含帳號中途變動＝`notLoggedIn`）；`sync_settings_screen_test.dart` 新增「中途登出」「alreadyRunning」兩案例；其餘 6 個檔案僅調整 trigger 建構。
- 驗證：`flutter analyze` 乾淨；`test/sync/`、`sync_settings_screen_test`、`settings_scaffold_test`、`app_lifecycle_sync_test`、`elinkbook_app_wiring_test`、`library_screen_dependencies_test`、`reader_screen_route_test` 全數通過；`reader_screen_test`／`library_screen_test` 僅跑同步相關案例通過；`check_l10n_hardcoded_strings.js` PASS。**尚未跑全套 `flutter test`**（發 PR 前執行）。

**2026-09-30 程式審查與修訂**

- 審查報告：`reviews/review-code.md`，0 Critical／1 Important／4 Minor。使用者決定：I-1 選 (a)、M-1 處理；M-2、M-3（隨 I-1(a) 處理）、M-4 依建議。
- **I-1**（token 存在但 userId／baseUrl 缺失被歸為 `notLoggedIn`，手動同步靜默）：先新增兩個引擎測試，修正前皆 FAIL（Expected `failed`、Actual `notLoggedIn`）。引擎改為只在 `token == null` 時回 `notLoggedIn`；有 token 但 `userId`／`baseUrl` 缺失回 `failed`。
- **M-3**：引擎先只讀 token，沒有 token 立即回傳，不再多讀 baseUrl／userId（順帶解決）。
- **M-1**：`_manualSync` 說明文字改為列出各結果的處理；`SyncCheckpointResult` 註解同步更新。
- 驗證：`flutter analyze` 乾淨；同一批異動測試檔共 171 個通過（含新增 2 個）。全套 `flutter test` 尚未執行（發 PR 前）。
- 全套 `flutter test`：3211 個通過（1 個略過），`flutter analyze` 乾淨。準備發 PR。

**2026-09-30 PR 合併**

- PR #301（`epic-53/sync-checkpoint-result` → `main`）已合併。修正全數完成，待歸檔。
