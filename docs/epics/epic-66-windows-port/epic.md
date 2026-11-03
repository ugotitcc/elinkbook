# `epic-66-windows-port` Windows 版移植

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-66-windows-port/`
**關聯 PRD 章節：** NFR-7（Windows 支援）、§3.2（Windows 第一版不含的功能）；決策見 ADR 0040。

## 背景

使用者要求把目前功能移植到 Windows（2026-11-03）。專案現況：

- `app/` 沒有 `windows/` 資料夾。
- Android 原生部分有 1,159 行 Kotlin、7 個 MethodChannel：`book_metadata`、`reader_resources`、`reader_resources_cache`、`folder_picker`、`volume_key`、`fullscreen`、`app_info`。
- Android 把書送進 WebView 靠原生 `WebViewAssetLoader` 與 `shouldInterceptRequest`（`foliate_reader_view.dart`），兩者都是 Android 專屬 API。
- `flutter_inappwebview`、`pdfrx`、`sqflite_common_ffi` 有 Windows 版；`audio_service` 沒有。

## 參考實作

`anxcye/anx-reader`（MIT）有 Windows 版，同樣用 foliate-js：

- 用 `shelf` 在 `127.0.0.1` 起本機伺服器，把書與資源送進 WebView，各平台共用。
- 匯入時用 `HeadlessInAppWebView` 跑 foliate-js 讀 metadata；Windows 需設 `WebViewEnvironment`。
- 使用自己 fork 的 `flutter_inappwebview` 與 `window_manager`。
- 它的伺服器開 `Access-Control-Allow-Origin: *` 且沒有權杖。本專案要加權杖。

## Discovery 決策（`/grill-with-docs` 定案，2026-11-03）

1. **範圍**：功能對等，但下列例外。
   - 隱藏：音量鍵翻頁、E-Ink 高對比與影像濾鏡、螢幕方向鎖定。
   - 延後：Google Drive／OneDrive 雲端匯入（Windows 的 OAuth 要走本機回呼，且需另外註冊桌面用戶端 ID）。
   - 簡化：TTS 只用 `flutter_tts`，不用 `audio_service`。
   - 保留：WiFi 傳書。
2. **程式碼**：同一個 `app/` 加 `windows/`，平台判斷分流（ADR 0040）。
3. **操作**：保留 3×3 熱區（滑鼠當觸控），加鍵盤快捷鍵（方向鍵、PageUp／PageDown、Ctrl+F）與 F11 全螢幕（新增 `window_manager`，只在 Windows 啟用）。桌面專用版面（側欄、面板）不在本 Epic。
4. **最低版本**：Windows 10 1809。WebView2 沒裝時顯示說明與下載連結，不打包執行環境。
5. **匯入**：複製書檔到 `%APPDATA%` 下的 App 資料夾，與 Android 行為一致。
6. **送書給 WebView**：預設用本機 `shelf` 伺服器（`127.0.0.1`、隨機埠、一次性權杖、只服務目前開著的書）。驗證 Issue 同時實測 WebView2 有沒有請求攔截或虛擬網域對應；有就用，沒有就用伺服器。
7. **Metadata 解析**：目標是 Android 與 Windows 統一改用 foliate-js 的背景 WebView。前提是逐本對比 Readium 與 foliate-js 的結果（書名、作者、`identifier`、版面、封面）一致；`book_content_fingerprint.dart` 優先使用 `identifier`，不一致會讓同步把舊書當新書。不一致時 Android 保留 Readium，Windows 單獨用 foliate-js。
8. **WebView 套件**：先用上游 `flutter_inappwebview` 6.1.5。只有驗證證明不夠用，才考慮 fork。
9. **測試**：`flutter test` 照舊；`integration_test` 加 `-d windows` 目標，每種格式一支冒煙測試（開書、翻頁、劃線）。不建 CI。
10. **發佈**：先自用，打包成免安裝 zip。MSIX 與程式碼簽章等有對外發佈需求再議。
11. **詞彙**：`CONTEXT.md` 新增「平台專屬功能」「本機內容伺服器」「背景解析」。
12. **ADR**：現在只寫 ADR 0040。送書方式與 metadata 統一等驗證完成後再各寫一份。
13. **PRD**：新增 NFR-7 與 §3.2 的 Windows 例外項（已完成）。
14. **流程**：一個 Issue 一個分支、一個 PR，計畫與實作同分支同 PR。

## 範圍外

- 雲端匯入（Google Drive／OneDrive）。
- MSIX 打包、程式碼簽章、自動更新。
- 桌面專用版面。
- macOS、Linux。
