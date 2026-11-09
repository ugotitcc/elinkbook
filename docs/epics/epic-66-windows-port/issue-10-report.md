# Issue 10：Windows 隱藏手機專屬功能 驗證報告

- **對應 Issue**：`epic-66` Issue 10
- **實作分支**：`feat/epic-66-issue-10-platform-hiding`
- **計畫**：[plan-issue-10.md](plans/plan-issue-10.md)

## 變更清單

| 項目 | 檔案 |
|---|---|
| 新增旗標 `supportsMobileReaderControls`（Windows 為 `false`） | `app/lib/platform/platform_support.dart` |
| 閱讀預設值畫面隱藏音量鍵、螢幕方向、全螢幕 | `app/lib/screens/reading_defaults_screen.dart` |
| 流式面板隱藏全螢幕與螢幕方向列 | `app/lib/screens/reader_settings_sheet.dart` |
| 固定版面面板隱藏全螢幕 | `app/lib/screens/fxl_settings_sheet.dart` |
| PDF 面板隱藏「濾鏡」分頁（3 → 2 個分頁）與全螢幕 | `app/lib/screens/pdf_settings_sheet.dart` |
| 設定畫面隱藏 E-Ink 開關；`ElinkBookApp` 啟動時忽略殘留的 E-Ink 值 | `app/lib/screens/settings_scaffold.dart`、`app/lib/main.dart` |
| `ReaderScreen` 在 Windows 不呼叫 `elinkbook/volume_key`、`elinkbook/fullscreen`、`SystemChrome` 方向鎖定 | `app/lib/screens/reader_screen.dart` |

沒有新增或修改 ARB 字串。

## Review Focus 對應的測試

| # | 條目 | 測試 |
|---|---|---|
| 1 | Windows 殘留 `eink = true`，啟動仍用一般主題 | `test/theme/theme_test.dart`：Windows 即使本機殘留 E-Ink 模式為開啟，ElinkBookApp 仍套用一般主題 |
| 2 | PDF 面板 2 個分頁，切換與滑動不拋 `RangeError` | `test/screens/pdf_settings_sheet_test.dart`：Windows 只有顯示與裁切兩個分頁，切換不拋例外；Windows 左右滑動分頁不拋例外 |
| 3 | 進出閱讀器 0 次 channel 呼叫 | `test/screens/reader_screen_keyboard_test.dart`：Windows 進出閱讀器不呼叫 volume_key 與 fullscreen channel |
| 4 | 改動其他開關不覆寫被隱藏的值 | `test/screens/reading_defaults_screen_test.dart`：Windows 改動其他開關不覆寫被隱藏的值（防回歸護欄，實作前本來就綠） |
| 5 | Android 對照 | 各 Task 的「預設平台」對照測試 |

「關閉再開」沒有獨立測試：每次開面板都會在 `initState` 重建 `TabController`，風險低，列為已知缺口。

## 驗證結果

- `flutter analyze`：本 Issue 異動的檔案乾淨。全專案另有 2 則 info，不在本 Issue 異動的檔案內，`main` 上本來就有。
- `node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`：通過。
- 全套 `flutter test`：5112 個，2 個失敗，都是 `LocalBookServer`（`串流中途 dispose…`、`透過 HttpClient 讀取整檔…`）。這是 Issue 11 要處理的不穩定測試，`main` 上同一檔案也會失敗，失敗項目每次不同。
- 最終整條分支審查：沒有 Critical 或 Important，3 個 Minor 已記為延後（見下）。

## Windows 實機確認

**已完成（2026-11-09）。** 使用者在 Windows 上依下列清單逐項操作，回報 a～e 全數通過（無逐項紀錄；第 5 項主控台是否有 `MissingPluginException` 無法由本端確認，以使用者回報為準；第 6 項固定版面未回報）。用的是 `main`（HEAD `16862440`）建置的 debug 版（建置需 `CL=/utf-8`、nuget 在 PATH，且 CL 值在 Git Bash 要加 `MSYS_NO_PATHCONV=1`，否則會被轉成路徑而建置失敗）。清單：

1. 設定 → 閱讀預設值：沒有「音量鍵翻頁」、「螢幕方向」區塊、「全螢幕模式」；其餘項目可操作。
2. 設定：沒有「E-Ink 高對比模式」。
3. 開 EPUB → 版面設定 →「呈現」分頁：沒有「全螢幕模式」與「螢幕方向鎖定覆寫」。
4. 開 PDF → 設定：只有「顯示」與「裁切」兩個分頁，來回切換正常；沒有全螢幕開關。
5. 進出閱讀器：主控台沒有 `MissingPluginException`。
6. 固定版面（FXL／CBZ）：若手邊沒有樣本，記為未實測。

## 已知限制（本 Issue 不處理）

- 「關於」頁在 Windows 顯示錯誤文字（`elinkbook/app_info`）。
- TXT 封面產生直接讀 E-Ink 殘留值。
- 資料庫已有的單書 `fullscreen`、`screenOrientationOverride`、`pdfContrast` 等值不清除；單書閱讀偏好不在同步表內，Windows 新安裝沒有這些值。

## 延後的 Minor

- 新加的 `platform_support` import 位置未照原本分組。
- `settings_scaffold_test.dart` 新測試前少一行空白。
- 「關閉再開」無獨立測試。
