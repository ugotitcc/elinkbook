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
