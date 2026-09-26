# `epic-50-sync-token-refresh` （缺陷）同步 token 過期後無法同步，須登出再登入才恢復

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-50-sync-token-refresh/`
**關聯 PRD 章節：** 同步（PocketBase）；關聯 ADR 0019、已歸檔 `epic-8-sync`

## 背景

使用者回報：同步設定好之後可以正常同步，但「更新幾次版本後」就無法同步，連「立即同步」也失敗；登出後重新登入就恢復。

使用者環境：PocketBase 0.39.10，users collection 的 Auth token duration 設為 `432000`（5 天）。最後一次成功同步是 2026-09-22 14:43，2026-09-26 回報時已無法同步。

## 開發記錄

**2026-09-26 `/diagnosing-bugs` 診斷**。流程依使用者選擇採直接 TDD：不另寫 `plans/plan-issue-N.md` 與計畫審查，保留程式審查。

- **回饋迴圈**：以 `MockClient` 假造 PocketBase。`auth-with-password` 發出有效期 7 天的 token，過期 token 對任何 API 一律回 401。流程為登入 → 每天呼叫一次 `SyncEngine.runCheckpoint()` → 登出再登入。
- **修正前**：第 1～6 天回傳 `true`，第 7 天起回傳 `false`，完整重現使用者的症狀。
- **確認的原因**：`SyncClient.testConnection()` 只在登入當下存一次 `authToken`。`SyncEngine` 每次 checkpoint 都直接拿這張 token 送出請求，整個程式庫沒有呼叫 `authRefresh`，spec／ADR 0019 也沒有定義 token 過期要怎麼處理。token 效期從「登入」起算，一到期伺服器就回 401，被 `on ClientException { return false; }` 靜默吞掉，畫面仍顯示「已登入」。
  - 佐證：登出只會清除憑證，不會動同步游標或本機資料，而「登出再登入就恢復」代表問題只出在憑證上。
  - 使用者口中的「更新幾次版本後」只是時間經過的指標，與 App 版本無關。
- **修正方向**（使用者選 A＋B）：
  - A：每次 checkpoint 開頭先呼叫 `authRefresh` 換新 token 並存回。只要在效期內同步過一次，token 就會持續續期。
  - B：`authRefresh` 回 401（token 已過期或失效）時只清除 token、保留 email。同步設定畫面偵測到「沒有 token 但有 email」時切回登入表單，預填 email，並提示「登入已過期」，不再靜默失敗。
- **伺服器端建議**：Auth token duration 可調長，例如 `2592000`（30 天）。修改後須在 App 重新登入一次，新設定才會套用到新發出的 token。

**2026-09-26 修正（直接 TDD）**

- `SyncEngine._runCheckpointBody()` 開頭新增 `_refreshAuthToken()`：以目前 token 呼叫 `users.authRefresh`，新 token 存回 `SyncAccountRepository.saveAuthToken()`，後續請求改用新 token。回 401 時呼叫 `clearAuthToken()`（只清 token、保留 email）並回傳 `false`；其他錯誤維持登入。
- `SyncSettingsScreen`：手動同步失敗後重新檢查登入狀態，已被清除 token 就切回登入表單、預填 email，顯示 `syncSettingsSessionExpiredMessage`，不再顯示籠統的網路錯誤。開啟畫面時若「沒有 token 但有 email」同樣處理。使用者主動登出走 `clearCredentials()`，email 一併清除，不會誤顯示。
- 測試：`test/sync/pocketbase_test_helpers.dart` 新增 `mockPocketBase()`，讓既有假伺服器統一回應 `auth-refresh`。`sync_engine_test.dart` 新增 token 到期情境（有效期 5 天、連續 14 天同步）、401、500、新 token 存回；`sync_account_repository_test.dart` 與 `sync_settings_screen_test.dart` 補上對應測試。
- 驗證：回饋迴圈修正前第 5 天 FAIL、修正後 14 天全部 PASS。全套 `flutter test` 2889 個通過（1 個略過）；`flutter analyze` 乾淨；`check_l10n_hardcoded_strings.js` PASS。另以 `pbdev.jigong.org` 確認真實 PocketBase 的 `auth-refresh` 會換發 `exp` 延後的新 token，無效 token 回 401。
- 程式審查：`reviews/review-code.md`，0 Critical／0 Important／3 Minor。使用者決定處理 M-1、M-2，M-3 不處理。

**2026-09-26 審查修訂**

- M-1（續期與登出／重新登入的競態）：`_refreshAuthToken()` 在續期回應後重新讀取 token，已不是這次拿去續期的那張就不寫回、本輪放棄；401 路徑也同樣確認後才清除，避免清掉新登入的 token。新增兩個測試，修正前都 FAIL。
- M-2（自動同步時過期要打開同步設定才會知道）：使用者選擇「一次性 Toast」。`SyncAccountRepository.isSessionExpired()`（沒有 token 但有 email）；`SyncCheckpointTrigger` 新增可選的 `isSessionExpired`／`onSessionExpired`，自動 checkpoint 後偵測到過期就呼叫一次。過期後登入閘門會略過後續觸發，因此每次過期只提示一次；手動同步不經過 trigger，不會跟畫面內提示重複。`main.dart` 比照衝突對話框透過 `navigatorKey` 顯示 SnackBar（`syncSessionExpiredToast`）。這段接線位於 `main()` 內，沒有測試接縫，與既有 `onReadingPositionConflict` 橋接相同。
- M-3（每次 checkpoint 多一次請求）：不處理。

**2026-09-27 真機測試**

- 使用者在真機完成測試，結果通過。準備發 PR。
