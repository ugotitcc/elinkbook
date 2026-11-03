# `epic-66-windows-port` Windows 版移植

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-66-windows-port/`
**關聯 PRD 章節：** NFR-7（Windows 支援）、§3.2（Windows 第一版不含的功能）；決策見 ADR 0041。

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
2. **程式碼**：同一個 `app/` 加 `windows/`，平台判斷分流（ADR 0041）。
3. **操作**：保留 3×3 熱區（滑鼠當觸控），加鍵盤快捷鍵（方向鍵、PageUp／PageDown、Ctrl+F）與 F11 全螢幕（新增 `window_manager`，只在 Windows 啟用）。桌面專用版面（側欄、面板）不在本 Epic。
4. **最低版本**：Windows 10 1809。WebView2 沒裝時顯示說明與下載連結，不打包執行環境。
5. **匯入**：複製書檔到 `%APPDATA%` 下的 App 資料夾，與 Android 行為一致。
6. **送書給 WebView**：預設用本機 `shelf` 伺服器（`127.0.0.1`、隨機埠、一次性權杖、只服務目前開著的書）。驗證 Issue 同時實測 WebView2 有沒有請求攔截或虛擬網域對應；有就用，沒有就用伺服器。**【2026-11-03 驗證結果】WebView2 有請求攔截，已用於實際開書，不需要 `shelf` 伺服器**（見決策 15 與 `spike-report.md` 結論 1）。
7. **Metadata 解析**：目標是 Android 與 Windows 統一改用 foliate-js 的背景 WebView。前提是逐本對比 Readium 與 foliate-js 的結果（書名、作者、`identifier`、版面、封面）一致；`book_content_fingerprint.dart` 優先使用 `identifier`，不一致會讓同步把舊書當新書。不一致時 Android 保留 Readium，Windows 單獨用 foliate-js。**【2026-11-03 驗證結果】** Windows 上 `HeadlessInAppWebView` 載入 foliate-js 能讀出書名、`identifier`、封面（作者欄位因 `sample.epub` 本身無 `dc:creator`，尚未實證）；欄位型別見 `spike-report.md` 結論 2。**Readium 與 foliate-js 的逐本對比尚未做**，留給後續 Issue，本決策的「是否統一」仍待該對比結果。
8. **WebView 套件**：先用上游 `flutter_inappwebview` 6.1.5。只有驗證證明不夠用，才考慮 fork。
9. **測試**：`flutter test` 照舊；`integration_test` 加 `-d windows` 目標，每種格式一支冒煙測試（開書、翻頁、劃線）。不建 CI。
10. **發佈**：先自用，打包成免安裝 zip。MSIX 與程式碼簽章等有對外發佈需求再議。
11. **詞彙**：`CONTEXT.md` 新增「平台專屬功能」「本機內容伺服器」「背景解析」。
12. **ADR**：現在只寫 ADR 0041。送書方式與 metadata 統一等驗證完成後再各寫一份。
13. **PRD**：新增 NFR-7 與 §3.2 的 Windows 例外項（已完成）。
14. **流程**：一個 Issue 一個分支、一個 PR，計畫與實作同分支同 PR。

## 審查修訂（`reviews/review-epic-and-issues.md`，2026-11-03）

審查結論：Ready with fixes。6 項重要意見已對照程式碼查證，全部成立。決策如下。

15. **Issue 1 攔截優先，伺服器備案**（2026-11-03 修訂）：計畫階段讀 `flutter_inappwebview_windows` 0.6.0 的 C++ 原始碼（`in_app_webview.cpp:827-899`），WebView2 的 `WebResourceRequested` 已實作 `shouldInterceptRequest`。所以 Windows 沿用 Android 的攔截模式，在 Dart 端提供 foliate 資源與書檔，網址不變，`main.js` 不改。Issue 1 在 Windows 實測攔截；只有失敗才加做最小 `shelf` 伺服器原型。原版本是「Issue 1 一定做 `shelf` 原型」，已被取代。這同樣解除「過關條件 1 要開書、送書卻排在後面」的循環依賴。**【2026-11-03 驗證結果】攔截實測成功**：3 個 fixture 與 224 MB EPUB 皆經攔截供應並成功開啟，`shelf` 備案不啟動。**已知代價：** 現行 `readWindowsBookBytes` 整檔讀進記憶體，224 MB 書開書瞬間 App 與 WebView2 合計尖峰約 3.8 GB（release 版，持續約 3 秒後回落）。判定為可接受，改善（分段服務）留給後續 Issue；數據與限制見 `spike-report.md` 結論 1。
16. **啟動鏈平台防護**：`main.dart:253` 之後無條件呼叫 `AudioSession` 與 `AudioService.init()`，兩者在 Windows 沒有平台實作，啟動會直接丟 `MissingPluginException`。Windows 要跳過這兩段。跳過後 `TtsAudioHandlerHolder` 的狀態已定案（2026-11-03）：在 `TtsAudioHandlerStatus` 新增「此平台不需要」狀態，Windows 使用它。不沿用 `.unavailable()`——它代表「初始化中」，原為測試用，永久使用語意不符。（計畫審查查證：`lib/` 目前沒有任何地方依 `status` 分支，「一直轉圈」沒有證據；新增狀態是為了語意清楚，不是為了修轉圈。）新狀態的建構子與 UI 行為寫進 `plans/plan-issue-1.md`。
17. **foliate-js 資源跨平台**：資源現在只放在 `app/android/app/src/main/assets/foliate/`，`pubspec.yaml` 沒宣告，Windows 建置不會打包。需要改成 Flutter 通用資產或由 CMake 複製。放置方式由 Issue 1 實測後決定，不在此預設。
18. **消除寫死網域**：`https://appassets.androidplatform.net` 出現在 `main.js:1177`、`foliate_reader_view.dart:666`、`foliate_content_indexer.dart:217`、`foliate_native_bridge.dart:55`、`:60`（字型網址）。Windows 改用伺服器後，這五處都要改成由平台決定的 base URL。Android 的值不能變。
19. **WebView 內容有兩個消費者**：`FoliateReaderView`（開書）與 `FoliateContentIndexer`（背景全文檢索，由 `main.dart:216` 常駐啟動）。送書方式抽換時，兩者要同步。
20. **PDF 的 metadata 與封面**：Android 用 `PdfRenderer` 算第 1 頁。Windows 用已在專案內的 `pdfrx` 開檔，第 0 頁算圖輸出 PNG，純 Dart，不新增原生 channel。foliate-js 不處理 PDF，所以決策 7 的對比只涵蓋 EPUB。
21. **選檔器與資料夾**：`book_import_picker_helper.dart:29,148` 只收 `f.identifier != null` 的檔案。`identifier` 在 Android 是 `content://` URI，Windows 沒有，實體路徑在 `f.path`。Windows 要改取 `f.identifier ?? f.path`。資料夾選取用 `FilePicker.platform.getDirectoryPath()`，列舉用 `dart:io`，不寫 Windows 原生 channel。
22. **Windows 的 `Book.filePath`**：一律存標準本機路徑（例如 `C:\Users\...`），不存 `file:///`。`book_content_fingerprint.dart:58` 以 `contains('://')` 判斷是否走原生 channel，`file:///` 會被誤判。
23. **WebView2 使用者資料夾**：`WebViewEnvironmentSettings.userDataFolder` 明確指定到 `%APPDATA%` 下的 App 資料夾。預設會建在執行檔旁，免安裝 zip 若解壓到唯讀位置會初始化失敗。
24. **`window_manager` 的 `win32` 相容**：`pubspec.lock` 的 `win32` 是 5.15.0。加入 `window_manager` 前，先確認它要求的 `win32` 區間，不可造成 pub 衝突（見 ADR 0041「後果」）。版本號在實際解析時確認，這裡不預先鎖定。

## 範圍外

- 雲端匯入（Google Drive／OneDrive）。
- MSIX 打包、程式碼簽章、自動更新。
- 桌面專用版面。
- macOS、Linux。
