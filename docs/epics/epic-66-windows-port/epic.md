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
   - 延後：Google Drive／OneDrive 雲端匯入（Windows 的 OAuth 要走本機回呼，且需另外註冊桌面用戶端 ID）。**2026-11-14 更新：使用者要求 Windows 也要支援，已登錄為 Issue 31（待規劃）。**
   - 簡化：TTS 只用 `flutter_tts`，不用 `audio_service`。
   - 保留：WiFi 傳書。
2. **程式碼**：同一個 `app/` 加 `windows/`，平台判斷分流（ADR 0041）。
3. **操作**：保留 3×3 熱區（滑鼠當觸控），加鍵盤快捷鍵（方向鍵、PageUp／PageDown、Ctrl+F）與 F11 全螢幕（新增 `window_manager`，只在 Windows 啟用）。桌面專用版面（側欄、面板）不在本 Epic。
4. **最低版本**：Windows 10 1809。WebView2 沒裝時顯示說明與下載連結，不打包執行環境（已於 Issue 9 實作）。
5. **匯入**：~~複製書檔到 `%APPDATA%` 下的 App 資料夾，與 Android 行為一致。~~ **【2026-11-06 修訂，Issue 5 規劃時】改為不複製、`Book.filePath` 維持來源檔案的原路徑**（與決策 22 一致，也與現有 `_persistPermissionOrLandCopy` 對非 `content://` 路徑原樣回傳的行為一致）。原寫法與程式現況矛盾：Android 並非「複製」，而是引用原檔並持久化授權，只有授權失敗才複製。代價是使用者搬動或刪除原檔後該書打不開（走既有的「重新連結」流程），因此 Windows 的「來源」畫面要常駐一行說明文字提醒。
6. **送書給 WebView**：預設用本機 `shelf` 伺服器（`127.0.0.1`、隨機埠、一次性權杖、只服務目前開著的書）。驗證 Issue 同時實測 WebView2 有沒有請求攔截或虛擬網域對應；有就用，沒有就用伺服器。**【2026-11-03 驗證結果】WebView2 有請求攔截，已用於實際開書，不需要 `shelf` 伺服器**（見決策 15 與 `spike-report.md` 結論 1）。**【Issue 3／4 結果】** Issue 3 實測發現 `shouldInterceptRequest` 整本回傳在 Windows 上每次開關 224 MB 大檔造成約 +452 MB 的永久記憶體洩漏，4 次累積 +1808 MB 瀕臨崩潰。Issue 4 依原定伺服器架構落成本機 loopback HTTP 伺服器（`LocalBookServer`，隨機埠、動態權杖、HTTP Range 串流服務），徹底消除洩漏（4 輪累積增量僅 +8.21 MB，`leaked=false`，見 ADR 0042 與 `issue-4-report.md`）。
7. **Metadata 解析**：目標是 Android 與 Windows 統一改用 foliate-js 的背景 WebView。前提是逐本對比 Readium 與 foliate-js 的結果（書名、作者、`identifier`、版面、封面）一致；`book_content_fingerprint.dart` 優先使用 `identifier`，不一致會讓同步把舊書當新書。不一致時 Android 保留 Readium，Windows 單獨用 foliate-js。**【2026-11-03 驗證結果】** Windows 上 `HeadlessInAppWebView` 載入 foliate-js 能讀出書名、`identifier`、封面；欄位型別見 `spike-report.md` 結論 2。**【Issue 2 結果】** 13 份 fixture（多識別碼、多語系書名、角色作者、EPUB2 封面、固定版面、無封面、無識別碼，以及三份邊界：`unique-identifier` 指向不存在的 id、identifier 帶前後空白與換行、identifier 帶 `opf:scheme`）在 BooksPad（Readium）與 Windows（foliate-js）逐欄對比，`title`、`author`、`identifier`、`isFixedLayout`、有無封面**全部一致，不一致 0 份**。**範圍限制：** 只涵蓋這 13 份人工建構的 fixture；真實出版社書籍（含 EPUB 2 套件、更多樣的 `dc:identifier` 寫法）尚未與 Readium 對比，224 MB 的真實書只有 foliate 端的結果。因此「兩端指紋不會分裂」目前是「已測案例無不一致」，不是保證。Windows 現由 foliate-js（EPUB）與 pdfrx（PDF 封面）提供 metadata，Android 保持既有 Readium 通道；是否統一兩端至 foliate-js，建議先補更多真實書籍的對比。
8. **WebView 套件**：先用上游 `flutter_inappwebview` 6.1.5。只有驗證證明不夠用，才考慮 fork。
9. **測試**：`flutter test` 照舊；`integration_test` 加 `-d windows` 目標，每種格式一支冒煙測試（開書、翻頁、劃線）。不建 CI。
10. **發佈**：先自用，打包成免安裝 zip。MSIX 與程式碼簽章等有對外發佈需求再議。**（2026-11-13 更新：已改為對外發佈，安裝程式見決策 32。）**
11. **詞彙**：`CONTEXT.md` 新增「平台專屬功能」「本機內容伺服器」「背景解析」。
12. **ADR**：現在只寫 ADR 0041。送書方式與 metadata 統一等驗證完成後再各寫一份。
13. **PRD**：新增 NFR-7 與 §3.2 的 Windows 例外項（已完成）。
14. **流程**：一個 Issue 一個分支、一個 PR，計畫與實作同分支同 PR。

## 審查修訂（`reviews/review-epic-and-issues.md`，2026-11-03）

審查結論：Ready with fixes。6 項重要意見已對照程式碼查證，全部成立。決策如下。

15. **Issue 1 攔截優先，伺服器備案**（2026-11-03 修訂）：計畫階段讀 `flutter_inappwebview_windows` 0.6.0 的 C++ 原始碼（`in_app_webview.cpp:827-899`），WebView2 的 `WebResourceRequested` 已實作 `shouldInterceptRequest`。所以 Windows 沿用 Android 的攔截模式，在 Dart 端提供 foliate 資源與書檔，網址不變，`main.js` 不改。Issue 1 在 Windows 實測攔截；只有失敗才加做最小 `shelf` 伺服器原型。原版本是「Issue 1 一定做 `shelf` 原型」，已被取代。這同樣解除「過關條件 1 要開書、送書卻排在後面」的循環依賴。**【2026-11-03 驗證結果】攔截實測成功**：3 個 fixture 與 224 MB EPUB 皆經攔截供應並成功開啟，`shelf` 備案不啟動。**已知代價：** 現行 `readWindowsBookBytes` 整檔讀進記憶體，224 MB 書開書瞬間 App 與 WebView2 合計尖峰約 3.8 GB（release 版，持續約 3 秒後回落）。判定為可接受，改善（分段服務）留給後續 Issue；數據與限制見 `spike-report.md` 結論 1。**【Issue 3／4 結果】** Issue 3 實證上述代價非但未回落，更在 `elinkbook.exe` 留下每輪 +452 MB 的永久私有記憶體洩漏；Issue 4 已正式啟動並完成 loopback HTTP 伺服器改接，消除了該通道的階梯式洩漏。
16. **啟動鏈平台防護**：`main.dart:253` 之後無條件呼叫 `AudioSession` 與 `AudioService.init()`，兩者在 Windows 沒有平台實作，啟動會直接丟 `MissingPluginException`。Windows 要跳過這兩段。跳過後 `TtsAudioHandlerHolder` 的狀態已定案（2026-11-03）：在 `TtsAudioHandlerStatus` 新增「此平台不需要」狀態，Windows 使用它。不沿用 `.unavailable()`——它代表「初始化中」，原為測試用，永久使用語意不符。（計畫審查查證：`lib/` 目前沒有任何地方依 `status` 分支，「一直轉圈」沒有證據；新增狀態是為了語意清楚，不是為了修轉圈。）新狀態的建構子與 UI 行為寫進 `plans/plan-issue-1.md`。
17. **foliate-js 資源跨平台**：資源現在只放在 `app/android/app/src/main/assets/foliate/`，`pubspec.yaml` 沒宣告，Windows 建置不會打包。需要改成 Flutter 通用資產或由 CMake 複製。放置方式由 Issue 1 實測後決定，不在此預設。
18. **消除寫死網域**：`https://appassets.androidplatform.net` 出現在 `main.js:1177`、`foliate_reader_view.dart:666`、`foliate_content_indexer.dart:217`、`foliate_native_bridge.dart:55`、`:60`（字型網址）。Windows 改用伺服器後，這五處都要改成由平台決定的 base URL。Android 的值不能變。
19. **WebView 內容有兩個消費者**：`FoliateReaderView`（開書）與 `FoliateContentIndexer`（背景全文檢索，由 `main.dart:216` 常駐啟動）。送書方式抽換時，兩者要同步。
20. **PDF 的 metadata 與封面**：Android 用 `PdfRenderer` 算第 1 頁。Windows 用已在專案內的 `pdfrx` 開檔，第 0 頁算圖輸出 PNG，純 Dart，不新增原生 channel。foliate-js 不處理 PDF，所以決策 7 的對比只涵蓋 EPUB。
21. **選檔器與資料夾**：`book_import_picker_helper.dart:29,148` 只收 `f.identifier != null` 的檔案。`identifier` 在 Android 是 `content://` URI，Windows 沒有，實體路徑在 `f.path`。Windows 要改取 `f.identifier ?? f.path`。資料夾選取用 `FilePicker.platform.getDirectoryPath()`，列舉用 `dart:io`，不寫 Windows 原生 channel。
22. **Windows 的 `Book.filePath`**：一律存標準本機路徑（例如 `C:\Users\...`），不存 `file:///`。`book_content_fingerprint.dart:58` 以 `contains('://')` 判斷是否走原生 channel，`file:///` 會被誤判。
23. **WebView2 使用者資料夾**：`WebViewEnvironmentSettings.userDataFolder` 明確指定到 `%APPDATA%` 下的 App 資料夾。預設會建在執行檔旁，免安裝 zip 若解壓到唯讀位置會初始化失敗。
24. **`window_manager` 的 `win32` 相容**：`pubspec.lock` 的 `win32` 是 5.15.0。加入 `window_manager` 前，先確認它要求的 `win32` 區間，不可造成 pub 衝突（見 ADR 0041「後果」）。版本號在實際解析時確認，這裡不預先鎖定。
25. **Issue 5 匯入設計（2026-11-06 `/grill-with-docs`）**：Windows 支援選檔、選資料夾、拖曳三種匯入方式，都進同一條匯入管線。拖曳只在「書架」與「來源」兩個畫面有效；資料夾只匯入第一層；不支援格式略過並在結果提示說明個數（此計數放在共用服務，Android 一併生效）；拖入資料夾與選資料夾一致會先問是否依資料夾名稱分類；匯入中再拖入一律忽略。拖曳套件用 `desktop_drop` **0.8.4**（0.9.x 要求 Flutter ≥ 3.47.7，與專案固定的 3.41.9 不相容；0.8.4 不依賴 `win32`）。**Flutter 升級另開 Issue**：查證 3.47 支援 Android 24–37（Android 11 沒問題），但牽涉 `onReorder` 棄用、built-in Kotlin／AGP 9、Windows 預設 Impeller，不與匯入功能混在同一個 Issue。詞彙見 `CONTEXT.md`「拖曳匯入」。
26. **Issue 7 鍵盤與 F11 設計（2026-11-06 `/grill-with-docs`）**：快捷鍵固定、不可自訂、無說明畫面，範圍只有翻頁類（←／→、↑／↓、PageUp／PageDown、Space〔Shift 反向〕、Home／End）、Ctrl+F（閱讀器內書內搜尋）、F11。鍵盤是「熱區動作」的另一種入口：直排時 ←／→ 左右鏡像、捲動模式也只對應上一頁／下一頁，不做細微捲動。F11 是新概念「視窗全螢幕」，視窗層級、不寫入偏好、不持久化、任何畫面可用，與「全螢幕模式」「沉浸模式」互不相干；Esc 由單一決策點 `handleWindowEscape` 處理（全域 `HardwareKeyboard` 處理器；**不能**在 `MaterialApp.builder` 層用 `Actions` 覆寫 `DismissIntent`——每個路由自帶的 `DismissIntent` 動作會遮蔽它，已用 Flutter 3.41.9 原始碼查證；也不能在 builder 用 `Focus(onKeyEvent:)` 手動攔截——會搶在 `WidgetsApp` 轉換之前）：先放行可關閉的浮層（路由 `barrierDismissible` 或 `DismissAction` 子類；`EditableText` 自帶的永遠啟用動作不算），再問閱讀器的內層狀態（文字選取、PDF 裁切模式；閱讀器被搜尋畫面等頁面蓋住時不參與），最後才退出視窗全螢幕；閱讀器內不會返回書架。**WebView2 有焦點時 F11／Esc 的行為已由實機驗證：可用**（2026-11-06，使用者以真實鍵盤回報；Task 1 的合成輸入量測結論「兩邊都沒收到」作廢，見 `issue-7-report.md`）。文字輸入框有焦點或浮層疊上時翻頁鍵暫停，F11 永遠有效。**`window_manager` 固定 0.5.2**（`pub add --dry-run` 解析成功；只新增 `screen_retriever` 0.2.2 系列，不依賴 `win32`，`win32` 維持 5.15.0，決策 24 的衝突疑慮解除；0.6.0 要求 Flutter ≥ 3.47 且改用 `nativeapi`，不可用）。EPUB 的按鍵會進 Flutter 還是被 WebView2 吞掉，由 Issue 7 第一個 Task 實測決定。「全螢幕模式」偏好項在 Windows 的隱藏與 Android 原生 channel 的未處理例外，留給「平台專屬功能隱藏」Issue。詞彙見 `CONTEXT.md`「視窗全螢幕」「鍵盤快捷鍵」。
27. **後續 Issue 規劃（2026-11-06 `/grill-with-docs`）**：Epic 做完的定義是功能對等加免安裝 zip 與冒煙測試（決策 1、9、10 都留在本 Epic）。新增 Issue 8～14，預定順序 8 → 9 → 10 → 11 → 6 → 12 → 13 → 14，詳見 `issues.md`。(a) 索引器在 Windows 跑不完會讓全庫全文搜尋失效，違反功能對等，列為 Issue 8，先診斷再修。(b) 決策 4 的「WebView2 沒裝時顯示說明」原本沒有對應 Issue，也沒有程式碼，補為 Issue 9。(c) 分段服務（大檔開書記憶體尖峰）不做，記為已知限制。(d) 測試穩定性（Issue 11）排在 Flutter 升級（Issue 6）前，升級才有乾淨基準；繁中 Windows 需設 `CL=/utf-8` 才能編譯（`connectivity_plus` 的 C4819 警告被當成錯誤），暫時做法是建置時設環境變數，永久修法併進 Issue 6，需先實測 `/utf-8` 設在 runner 能否套到外掛。(e) **Android 統一用 foliate-js 讀 metadata、移除 Readium 為 Issue 12**：決策 7 的目標尚未完成；Issue 2 只對比 13 份人工建構的 fixture，**真實出版社書籍的 Readium 對比尚未做**（`epic-67` 的更新偵測不涵蓋此項），Issue 12 第一步先補對比，不一致則保留 Readium。
28. **Flutter 升級至 3.47.9（2026-11-07，Issue 6）**：這台機器共用的 `C:\tools\flutter` 自 2026-10-23 起其實就是 3.47.4，`CLAUDE.md` 的 3.41.9 已過時，所以 Issue 6 實質上是升到最新 patch。理由：3.47.8 含安全公告 GHSA-frr6-h895-5pxp（Dart 執行環境的 BoringSSL 封鎖被入侵的 eMudhra 中繼 CA 憑證，Android、Windows、Linux 應用應升級後重新建置；本專案有同步、雲端匯入、線上查詞的 HTTPS 連線）；3.47.6 修正 Windows 正式版 App 卡死。使用者決定直接升級共用的 `C:\tools\flutter`（`flutter upgrade --force`，**從專案外的目錄執行**，否則第二階段會把 `pubspec.lock` 整個升級）；回退點是 `9584c6713b`（3.47.4），指令為 `git -C C:\tools\flutter reset --hard 9584c6713b` 再 `flutter doctor`，兩版引擎不同，回退需要網路重新下載引擎；`C:\src\flutter-3.41.9` 保留不刪。`desktop_drop` 維持 0.8.4：0.9.x 要求 `cross_file ^0.4.0`，與 `file_picker`、`share_plus` 等套件（含最新版）的 `cross_file ^0.3.x` 衝突，升級需 vendor 修補三個套件並改寫拖曳匯入，另立 Issue 16，不排程；不做也不會壞任何東西。`pdfrx`、`file_picker`、`window_manager` 的大跳版不在 Issue 6。Windows 建置在 `windows/CMakeLists.txt` 為 MSVC 加 `/utf-8`，不再需要手動設 `CL=/utf-8`（決策 27 提到的繁中字碼頁 950 問題）。Android 建置在 3.47.9 印出警告：Gradle 8.14.0（需 ≥ 9.1.0）與 AGP 8.11.1（需 ≥ 9.0.1）的支援即將移除，目前仍可建置，詳見 `issue-6-report.md`。

29. **Android EPUB 詮釋資料抽取預設改用 foliate-js，Readium 階段一留作退路（2026-11-09，Issue 12）**：在 WAVE（7 本）與 BooksPad（103 本商業實體書）共 110 本真實 EPUB 上以逐欄比較驗證：`title`、`author`、`identifier`、`isFixedLayout`、封面「有沒有」達成 **110 / 110 本 100% 完全相符、0 差異、0 失敗**（兩台的書來自本機檔案，不是 `content://`；封面是否同一張圖未驗證；`content://` 另以 FileProvider URI 在 WAVE 驗證通過，見 issue-12-report 第 9 節）。BooksPad 上兩端中位數耗時為 Readium 1.58s vs Foliate-js 1.70s（相當）；WAVE 上為 0.24s vs 1.24s（foliate-js 約慢 5 倍）。依據實機比對實證與使用者決議（2026-11-09），`kAndroidMetadataFoliateFirst` 預設值切換為 `true`。階段一維持 Readium 作為降級退路，並登錄 Issue 18 由階段二徹底移除 Readium 相依與相關清理。**【Issue 18 結果（階段二完成）】** Android EPUB 詮釋資料與既有書籍版面回填（`detectAndCacheEpubLayout`）已全面改走 foliate-js 探針，拔除 `readium-shared`／`readium-streamer`、原生 `extractEpubMetadata`／`detectEpubLayout`、Readium 退路、對比程式碼與 `readium-kotlin-toolkit.txt` 授權項（見 `issue-18-report.md`）。
30. **Windows 免安裝 zip 打包與 VC++ 執行階段隨附（2026-11-10，Issue 14）**：`elinkbook.exe` 與外掛 DLL 動態依賴 `MSVCP140.dll`、`VCRUNTIME140.dll`、`VCRUNTIME140_1.dll`。未安裝 Visual C++ 可轉散發套件的 Windows 環境會出現缺少 DLL 錯誤。經使用者決定（2026-11-10），採 app-local 部署方式隨附三個 VC DLL（由 VS Build Tools 的 Redist 目錄複製到執行檔同層），並在打包腳本（`app/tool/package_windows_zip.ps1`）透過 `dumpbin /dependents` 做靜態依賴檢查與防禦性斷言，排除非 Windows 內建且非目錄內之缺失依賴。打包時另排除 `dartjni.dll`（**計畫外的偏離**）：`jni` 是 `path_provider_android` 的遞移相依，`lib/` 沒有任何 `jni` 引用，該 DLL 依賴本機沒有的 `jvm.dll`；「Windows 版執行期不載入它」是推論，未以行程監看實證，僅有排除後的 zip 能啟動並存活 20 秒作為佐證。因使用者僅有一台開發機器，乾淨機器（未安裝 VC++ 執行階段）、Windows 10 1809、SmartScreen 行為等範圍明確記錄為「未驗證」，嚴禁外推；自用階段不作程式碼簽章、MSIX 或安裝程式（見 [issue-14-report.md](issue-14-report.md)）。
31. **Windows 圖示與啟動小視窗（2026-11-10，Issue 22）**：圖示由 `app/tool/generate_windows_icons.ps1` 依 `assets/appicon_v2.jpg` 產生（取中央插畫、含少量紙張留白）。Flutter Windows 沒有內建 splash，雙擊後到第一個畫面前（本機約 3 秒）視窗空白，所以在 runner 加原生啟動小視窗（`splash_window.cpp`，Win32 GDI 畫內嵌 BMP，Flutter 第一個畫面回呼時關閉，30 秒保險計時器）。過程中的兩個發現：（1）標題列小圖示曾是警告三角形，原因不是 ICO 格式（PNG 與 DIB 結果相同），獨立程式重現不出來，改在 `win32_window.cpp` 用 `RegisterClassEx` 明確指定 `hIconSm` 後消失（根因未完全查明，只確認此修法有效）；（2）`MainWindowHandle` 會先回傳小視窗，驗證腳本改以視窗類別區分。只在這台機器、125% 縮放、release 版驗證，其他 DPI、乾淨機器未驗證。
32. **Windows 安裝程式（2026-11-13 `/grill-with-docs`，Issue 27）**：Windows 版改為對外發佈，與 Android APK 並列於 GitHub Release。在免安裝 zip 之外新增 Inno Setup 安裝程式（不選 MSIX：沒有受信任簽章就無法雙擊安裝）；不簽章，沿用 SmartScreen「仍要執行」說明；依目前使用者安裝到 `%LOCALAPPDATA%\Programs\elinkBook`，不需管理員；固定 `AppId` 覆蓋升級（GUID 發佈後不可更改）；開始功能表一律建立，桌面捷徑可選且預設勾選；解除安裝跳出詢問是否一併刪除 `%APPDATA%\cc.ugotit\elinkbook`，以及「文件」資料夾內 elinkBook 以固定名稱建立的書庫、字典庫、封面、匯入的書複本等項目（2026-11-13 使用者決定連書庫一併刪除；不動其他檔案，詳見 ADR 0043），預設「否」，靜默模式一律不刪。維持本機打包、不建 CI（Windows 建置依賴 Visual Studio Build Tools 與 WebView2，且 `cloud_oauth.release.json` 不進版控）；上傳 Release 由使用者另行指示。已參考文章 steachs.com/archives/85207，其內容只提到「GitHub Actions 雲端編譯＋Releases 下載」，沒有 Flutter 或安裝程式的打包細節，所以只取「CI 建置」這個做法並判斷暫不採用。決策見 [ADR 0043](../../adr/0043-windows-installer-inno-setup-unsigned-per-user.md)。**實作結果（2026-11-13，Issue 27，見 [issue-27-report.md](issue-27-report.md)）**：介面語言原本打算用 Inno 內建的繁體中文，實測 6.7.3 沒附，經使用者決定改用官方儲存庫 main 的 `ChineseTraditional.isl` 原封複製進專案；打包內容實測發現兩個不該出貨的東西並已修（共用的 `package_windows_zip.ps1`）：build/flutter_assets 殘留的舊字型（14.7 MB）與 pubspec 宣告的整合測試 fixtures（36 MB），不改 pubspec，Android 端是否同樣夾帶另立 Issue 28；使用者回報在另一台電腦安裝、解除安裝（選否、選是）與開書正常（無逐項紀錄，環境未查證）。經獨立審查發現原本只刪 `%APPDATA%` 卻寫成「刪書庫」，使用者決定改為真的連「文件」資料夾內的書庫一併刪除（已實作並以 UI Automation 在假資料夾實測選否、選是，真實路徑下未實跑），並登記 Issue 29（把資料收進單一上層目錄 `elinkbook-data`，取代固定名稱清單）；審查另補強驗證腳本（AppId 獨立釘住、靜默防線、App 執行中拒絕解除安裝、安裝內容逐檔比對）。這台開發機上 release 版畫面空白根因未查明，登記 Issue 30。VC 可轉散發授權對 Build Tools 是否適用未查證，對外發佈前須使用者判斷。
33. **Windows 資料收進 `文件\elinkbook-data`（2026-11-13 `/grill-with-docs`，Issue 29，決策見 [ADR 0044](../../adr/0044-windows-data-under-documents-elinkbook.md)）**：Issue 27 審查發現書庫等資料直接散在使用者「文件」根目錄，沒有上層目錄，使用者看不出屬於哪個 App，解除安裝也只能用通用名稱清單刪除（有誤刪使用者同名資料夾的風險）。決定：只改 Windows，新增集中函式 `appDocumentsDirectory()`（Windows 回傳 `<文件>\elinkbook-data` 並自動建立，其他平台原樣回傳 `getApplicationDocumentsDirectory()`），7 個檔案共 9 處使用點全部改呼叫它；`%APPDATA%\cc.ugotit\elinkbook`（WebView2、已下載字型、字典來源）維持原位；**不遷移舊資料**（Windows 版目前只有作者的兩台電腦有資料，而資料庫存絕對路徑，光搬檔案救不回既有的書；升級後書架為空，需要的書重新匯入，舊項目手動刪除）；解除安裝選「是」改為只刪 `文件\elinkbook-data` 與 `%APPDATA%\cc.ugotit\elinkbook`，移除對「文件」根目錄通用名稱的逐項刪除。**【實作結果（2026-11-13，見 [issue-29-report.md](issue-29-report.md)）】**：已完成實作並加上防散落掃描測試（`documents_directory_usage_test.dart`）；開發機確認新位置建立 `文件\elinkbook-data\library.db` 且根目錄舊項目（11/6 `library.db`、`covers`、`imported_books`）完全未動；`verify_windows_installer.ps1` 29/29 與 `verify_windows_uninstall_data.ps1` 10/10（含多刪 `covers` 變異驗證）通過；改名前的版本曾由使用者在另一台電腦驗證（「1,2,3 都正確無誤」，不能套用到最終版）；最終版（資料夾 `elinkbook-data`）經審查改名後，使用者另外在另一台電腦驗證，回報「測試OK」（無逐項紀錄）。

## 各 Issue 處理紀錄

（自 `docs/epics.md` 備註欄搬入；`docs/epics.md` 只保留最後處理的 Issue。各 Issue 表格狀態見 [issues.md](issues.md)。）

- Discovery 已定案（2026-11-03）
- Issue 1（技術驗證）已合併（PR #381）
- Issue 2（Metadata 背景解析）已合併（PR #384）
- Issue 3（整本回傳記憶體洩漏驗證）已合併（PR #396）
- Issue 4（Windows 書檔改由 loopback HTTP 伺服器服務，消除洩漏）已合併（PR #397）
- Issue 5（Windows 檔案與資料夾匯入：選檔、選資料夾、拖曳）已合併（PR #398）
- Issue 7（Windows 鍵盤快捷鍵與 F11 視窗全螢幕）已合併（PR #399）
- Issue 6（Flutter 升級至 3.47.9）已合併（PR #404，`desktop_drop` 維持 0.8.4；Android 已在 WAVE 真機實測啟動與重複開書，未跑 integration_test）
- Windows 人工操作驗證（Issue 5 拖曳匯入、Issue 7 鍵盤與 F11）已於 2026-11-06 由使用者回報通過（無逐項紀錄），Android 實機尚未補驗
- Issue 8（索引器漏登錄橋接處理器造成 Windows App 消失）已合併（PR #400，大檔索引、背景排程端到端、Android 尚未實測）
- Issue 9（WebView2 缺少時的說明畫面）已合併（PR #401，Windows 實機以空 Runtime 資料夾模擬驗證通過，有 WebView2 時正常啟動已由使用者確認，乾淨機器與重新檢查成功後進入 App 未實測；啟動還原書籍逾時為 `main` 既有問題）
- Issue 10（Windows 隱藏手機專屬功能）已合併（PR #402，Windows 實機確認 a～e 已由使用者於 2026-11-09 回報通過）
- Issue 11（loopback 連線可靠度與測試穩定性）已合併（PR #403，根因是本機 `127.0.0.1` 連線被重設，與程式無關；全套測試 5118 個 0 失敗；開書逾時對照實驗結論為不能確定；`pdf_reader_view_filters_test` 偶發失敗未修，登記為 Issue 15）
- Issue 12（Android 統一 foliate-js metadata）已合併（PR #405，WAVE 書庫 9 本與 BooksPad 資料夾 103 本逐欄一致、封面只比有無，預設切換為 foliate-js，Readium 留作退路；WAVE 上 foliate 慢約 5 倍、只驗 `ExternalStorageProvider` 的 `content://`，全為 debug 版）
- Issue 14（免安裝 zip 打包）已合併（PR #408，本機依賴靜態檢查與唯讀含空格中文路徑驗證通過，使用者開書回報通過但無逐項紀錄，乾淨機器未驗證；見 issue-14-report.md）
- Issue 23（Android 12+ 啟動畫面圖示過小）已合併（PR #410，Android 14 模擬器驗證圖示寬度 19% → 45%，BooksPad、Android 11 以下、真實高效能機器未驗證）
- Issue 22（Windows 版圖示與原生啟動小視窗）已合併（PR #409，只在這台機器 125% 縮放、release 版驗證，其他 DPI 與乾淨機器未驗證）
- 後續已登錄 Issue 15～21（PDF 加粗覆蓋圖偶發失敗查根因、`desktop_drop` 0.9 與 `cross_file` 0.4 遷移、Android Gradle／AGP 升級（Issue 17：Gradle 9.3.1／AGP 9.1.0 升級與本地修補已合併（PR #440），release 真機抽測／驗簽／U: 機建置待補驗）、Android 移除 Readium 相依階段二、`reader_screen_test` 在 Windows 整份中斷診斷、桌面寬度 TOC 目前章節判定、Android 數支整合測試失敗查原因；Android 僅一台 BooksPad 部分驗證）
- 決策見 ADR 0041、0042
- Issue 27（Windows 安裝程式，Inno Setup）已完成待合併，Issue 28（Android APK 夾帶測試 fixtures）、Issue 30（開發機 release 畫面空白待查）已登錄待規劃，Issue 29（Windows 資料收進 `文件\elinkbook-data`）已實作並依審查修正、待合併，最終版已由使用者在另一台電腦驗證（回報「測試OK」），決策見 ADR 0043、ADR 0044
- Issue 32（Android 外掛遷移 built-in Kotlin 階段一）已合併（PR #443；`shared_preferences_android`、`url_launcher_android` 升級，KGP 外掛 9→7；Android／Windows debug 與 release 建置、全套測試通過；真機抽測未驗證；見 [issue-32-report.md](issue-32-report.md)）

## 範圍外

- ~~雲端匯入（Google Drive／OneDrive）~~：2026-11-14 改為納入，登錄為 Issue 31（待規劃）。
- MSIX 打包、程式碼簽章、自動更新（Inno Setup 安裝程式已另列為 Issue 27，見決策 32）。
- 桌面專用版面。
- macOS、Linux。
