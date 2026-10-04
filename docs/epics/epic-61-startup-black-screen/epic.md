# `epic-61-startup-black-screen` （缺陷）安裝新版後第一次啟動黑屏：`AudioService.init` 例外未接住，`runApp` 未執行

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-61-startup-black-screen/`
**關聯 PRD 章節：** 無（啟動穩定性）；來源：`epic-59-pdf-overlay-recompute-storm` 電子紙真機驗證的附帶觀察

## 背景

2026-10-04 在電子紙（Mobiscribe WAVE，Android 12，4GB）用 `adb install -r` 安裝 debug 版後第一次啟動，畫面停在全黑，約 1 分鐘仍不變。強制停止後重開即正常進入書架。

## 已知事實（來自 logcat）

- 啟動時 `main.dart:219` 的 `AudioService.init(...)` 丟出：
  `PlatformException(Unable to bind to AudioService. Please ensure you have declared a <service> element as described in the README., null, null, null)`，並成為 `Unhandled Exception`。
- 同一次啟動另有 `Failed to read WebView version: TimeoutException after 0:00:03.000000`，顯示當時系統忙碌。
- 例外未被接住，`main()` 在此中斷，`runApp` 沒有執行 → 黑屏。
- 強制停止重開後不再發生；AndroidManifest 的 `<service>` 宣告在其他次啟動可正常綁定，所以較像「安裝後系統忙碌造成的一次性綁定失敗」。（推測，尚未驗證）
- 只重現過 1 次。

## 目標（待 `/diagnose` 確認）

不論 `AudioService.init` 因何失敗，App 都應能進入書架；朗讀（TTS）功能降級為不可用即可，不可讓整個 App 黑屏。需先確認 `ttsAudioHandler` 在下游的使用方式，決定失敗時的降級做法。

## 處理方式

缺陷修復，先以 `/diagnose` 嘗試重現（例如安裝後立即啟動、或模擬 `AudioService.init` 丟例外的 widget／啟動測試），再直接 TDD，不寫 `plan-issue-N.md`；保留程式審查（報告存 `reviews/`，不進版控）。

## 開發記錄

**2026-10-04** 登錄 Epic，根因尚未查。

**2026-10-04 補充：同一台電子紙再次重現，且比預期頑固**

- 第 2 次：23:31 `adb install -r` 後第一次啟動 → 黑屏、同一個 `AudioService` 例外；強制停止後立刻重開（23:32）→ **仍黑屏**（log 3 次例外）；再強制停止重開 3 次 → 3 次都正常。
- 兩次都發生在「安裝新 APK 後」，且之後連續失敗不只 1 次，所以不是單純「一次性」。
- 例外位置：`AudioServicePlugin.java:465`（`IllegalStateException: Unable to bind to AudioService`）。manifest 已宣告 `<service android:name="com.ryanheise.audioservice.AudioService" ... foregroundServiceType="mediaPlayback">`（`AndroidManifest.xml:64`），所以不是漏宣告。
- 推測（未驗證）：安裝覆蓋後，系統對舊行程／舊服務的清理尚未完成，`bindService` 暫時回傳 false。是否與這台裝置（Mobiscribe WAVE，Android 12）的廠商節電機制有關，需要再試。
- 影響：黑屏期間 App 完全不可用，使用者只看到黑畫面，且沒有任何錯誤提示。

**2026-10-05 診斷（`/diagnosing-bugs`，未改任何程式）**

回饋迴圈：`adb install -r` → 啟動 → 檢查 logcat 是否出現 `Unable to bind to AudioService`（腳本在 scratchpad，不進版控）。

| 條件 | 紅燈／次數 |
|---|---|
| 安裝同一個 APK 後立刻啟動（含最初 4 次） | 1／10 |
| 安裝後立刻啟動 ×6 | 0／6 |
| 無負載冷啟動 ×3 | 0／3 |
| **CPU 滿載（系統 CPU 約 370%，已驗證生效）冷啟動 ×4** | **0／4** |

- 重現率低（約 10%），自然發生的 2 次都在「安裝新建置的 APK 後」。

**機制（已證實）**

- 失敗不是「找不到 service」。`AudioServicePlugin.java:251` 的 `onConnectionFailed` 在 `MediaBrowserCompat` 連線未完成時觸發；失敗那次 log：`Connecting to a MediaBrowserService` 23:51:52.620 → 錯誤 23:52:02.854，**相隔約 10.2 秒**，與 `MediaBrowserCompat` 的 10 秒連線逾時相符（逾時秒數為推測，未讀 androidx 原始碼）。
- 錯誤由 `AudioService.init` 丟出 `PlatformException`，`main.dart:219` 沒有 try/catch → `main()` 中斷，`runApp` 不會執行 → 黑屏。

**假設檢驗**

- H2「App 自己啟動時太忙」：**否定**。CPU 滿載下 0／4 紅燈。
- 單純 CPU 吃緊：**否定**（同上）。
- H1「安裝後系統忙（dex 編譯／套件驗證／IO）使 service 綁定超過 10 秒」：**未證實也未否定**。無法穩定重現，尚缺能製造「安裝後狀態」的可控手段。
- H3「廠商凍結機制干擾」：**未證實**。紅燈那幾次 log 內沒有 `while frozen` 訊息（只在較早的 `ntx.tools` 事件出現過）。

**結論：觸發條件未明，但缺陷本身（例外無人接住 → 整個 App 黑屏）與觸發條件無關，可以獨立修。**

**修法方向（待人類確認）**

- 下游已全面支援 `TtsAudioHandler?`（`main.dart:372`、`library_screen_dependencies.dart:52`、`reader_screen.dart:206`；使用處皆為 `?.`）。
- 在 `main()` 以 try/catch 包住 `AudioService.init`，失敗時 `debugPrint` 並傳 `null`，朗讀降級為本次執行不可用，App 照常進書架。
- 為了可測，抽出一個小函式（以 `Future<TtsAudioHandler> Function()` 注入）→ 單元測試「init 丟 `PlatformException` → 回傳 null、不丟例外；成功 → 回傳 handler」。`main()` 本身無法單元測試，這是刻意選的 seam。
- **已知限制**：失敗時 `AudioService.init` 要等滿約 10 秒才丟例外，所以降級後 App 仍會在黑屏約 10 秒後才出現。要消除需把 init 改成不阻塞啟動，範圍較大，建議另案。

**2026-10-05 實作（直接 TDD，人類選方案 1：接住例外、降級為無朗讀）**

- 紅燈：新增 `app/test/reader/tts_audio_handler_startup_test.dart`（4 案例：成功回 handler、`PlatformException` 回 null、其他例外回 null、同步丟例外回 null）。編譯即失敗（函式不存在）。
- 實作：新增 `app/lib/reader/tts_audio_handler_startup.dart` 的 `initTtsAudioHandlerSafely(init)`——try/catch 接住所有例外、`debugPrint` 後回傳 null；`main.dart` 改以它包住 `AudioService.init(...)`。`main()` 本身無法單元測試，故抽出小函式並以 `init` 注入作為測試 seam。
- 變異檢查：移除 try/catch → 3 個失敗案例；還原後 4 項全過。（第一次變異腳本沒套用成功、顯示 0 失敗，已發現並以正規表示式重做，不採信第一次結果。）

**真機驗證（可控重現）**：自然重現率僅約 10%，改用「暫時把 manifest 的 `<service>` 類別名改成不存在的 `AudioServiceBROKEN`」製造穩定綁定失敗（`adb shell pm disable` 因 `Shell cannot change component state` 被系統拒絕）。同一台電子紙（WAVE）：

| 程式 | 結果 |
|---|---|
| 舊（修復前）＋故障 manifest | **黑屏**，截圖 36KB，`Unable to bind` 未處理例外 1 筆 |
| 新（修復後）＋故障 manifest | **進入書架**，截圖 1.4MB，`TTS 音訊服務初始化失敗` log 1 筆、未處理例外 0 |

故障 manifest 已還原（`BROKEN` 殘留 0、`git diff -- app/android` 為空），裝置已重裝正常版。

**驗證**：`flutter analyze` 乾淨；全套 `flutter test` 3645 通過、1 略過、0 失敗；l10n 雙檢查 PASS。程式審查尚未執行。

**未解決（如實記錄）**

- 觸發條件仍未知（自然重現約 1／10，安裝後偶發）；本次只修「例外未接住 → 整個 App 黑屏」。
- 失敗時 `AudioService.init` 仍要等滿約 10 秒才丟例外，降級後 App 仍會**黑屏約 10 秒**才出現（故障 manifest 情境下綁定立即失敗，沒有量到這 10 秒）。要消除需把初始化改成不阻塞啟動，另案。
- 降級後本次執行朗讀不可用；使用者目前看不到任何提示（只有 debug log）。

**2026-10-05 程式審查修訂**（`reviews/review-code.md`：0 Critical／0 Important／4 Minor，結論可合併）

- **M-1 成立，已更正（含本檔先前的錯誤陳述）**：上文「朗讀降級為不可用」「降級後本次執行朗讀不可用」**不正確**。審查代理讀碼確認：`ttsAudioHandler` 為 null 時，朗讀按鈕仍可按、`TtsController` 照常建立並朗讀（建立不依賴 handler）；少掉的只有系統媒體通知、鎖屏控制、背景朗讀時的前景服務保護。降級後的實際影響比先前記載輕。已同步更正 `tts_audio_handler_startup.dart` 的說明註解與 `debugPrint` 訊息（改為「沒有媒體通知／鎖屏控制」）。（此點由審查代理確認，本人未獨立複驗。）
- **M-2 成立，已補註解**：`main.dart` 註解補「失敗後也不可重試」；函式說明補充兩點——`AudioService.init` 以 `assert(_cacheManager == null)` 擋重複初始化（僅 debug 生效），失敗時 `_cacheManager` 已設定；此函式會接住所有例外（含 `builder` 內的程式錯誤），啟動路徑上寧可降級也不黑屏。目前只在 `main()` 呼叫一次，現況無風險。
- **M-3 不改，只記錄**：測試的 `PlatformException(code: ...)` 字串其實是錯誤訊息文字，真實 code 可能不同（`catch` 不看 code，不影響結果）；未涵蓋「`init` 回傳之後才拋出的非同步錯誤」（`AudioService.init` 之後的 `_observe*` 若出錯屬 unhandled async error，不在本函式保護範圍，範圍外）。
- **M-4 不改，只記錄**：專案 `debugPrint` 多為英文，本次為中文，風格不一致，非缺陷。
- 附帶推測（未驗證）：逾時後原生端若晚些才綁定完成，會留下沒人驅動的 service，是否有殘留通知等副作用無法驗證。
- 驗證：`flutter analyze` 乾淨；`tts_audio_handler_startup_test`＋`elinkbook_app_wiring_test` 通過；l10n 雙檢查 PASS。全套 `flutter test` 於審查前已跑（3645 通過、1 略過、0 失敗），審查修訂只動註解、log 字串與文件。

**2026-10-05 PR 合併**

- PR #323（`epic-61/startup-no-black-screen` → `main`）已合併，合併 commit `e913749d`。實作、真機驗證與程式審查全數完成，待歸檔。
- 留給後續的未解事項：(1) 綁定逾時的觸發條件仍未明（自然重現約 1／10）；(2) 失敗時仍有約 10 秒黑屏，需把 `AudioService.init` 改成不阻塞啟動才能消除；(3) 降級後使用者看不到提示。皆尚未另立 Epic。

## 後續項目（併入本 Epic，不另開 Epic）

2026-10-05 人類決定：同一條問題線的後續工作不為每個小問題各開一個 Epic，併在本 Epic 以「後續項目」追蹤。

| # | 項目 | 狀態 | 備註 |
|---|---|---|---|
| F1 | 失敗時約 10 秒黑屏：把 `AudioService.init` 改成不阻塞啟動（背景進行，完成後再注入 handler） | 未開始 | 範圍較大：handler 已被 `LibraryScreen`／`ReaderScreen` 以建構子參數往下傳，需改為可晚到注入。需先量實際失敗時的黑屏時間（需可控的「綁定逾時」而非立即失敗的故障 manifest） |
| F2 | 綁定逾時的觸發條件 | 未開始 | 自然重現約 1／10，CPU 滿載無法重現；「安裝後系統忙」「廠商凍結機制」未證實 |
| F3 | 降級後讓使用者知道（例如一次性提示） | 未開始 | 需要新增字串（4 個 arb） |

F1、F3 已拆成 Issue，見 `issues.md`（F3＝Issue 1、F1＝Issue 2）；F2 是調查，不開 Issue，留在此表。

本 Epic 的歸檔條件：F1～F3 完成，或人類明確決定放棄其中某項。
