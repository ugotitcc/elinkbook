# Epic 66 — Windows 版移植：工單清單 (Issues)

設計依據是 `epic.md`「Discovery 決策」。Issue 1 過關後，才展開後續 Issue。

| Issue | 標題 | 依賴 | 狀態 | PR |
|---|---|---|---|---|
| 1 | 技術驗證：啟用 `windows/`、啟動鏈平台防護、最小送書原型，確認 7 項過關條件，輸出驗證報告 | 無 | ✅ 已合併 | #381 |
| 2 | Windows Metadata 背景解析：EPUB 用 foliate-js、PDF 封面用 `pdfrx`，並與 Android Readium 逐本對比 | Issue 1 | ✅ 已合併 | #384 |
| 3 | 閱讀器開書與全文索引器的「整本回傳」記憶體：驗證是否洩漏，洩漏則修正（來源 Issue 2 審查發現） | Issue 2 | ✅ 已合併（量測確認閱讀器洩漏，修法移至 Issue 4） | #396 |
| 4 | Windows 書檔改由本機 loopback HTTP 伺服器（`shelf`）服務，消除「整本回傳」洩漏（來源 Issue 3 報告） | Issue 3 | ✅ 已合併 | #397 |
| 5 | Windows 檔案與資料夾匯入：選檔、選資料夾、拖曳三種方式，書檔維持原路徑，不支援格式略過並提示 | Issue 4 | ✅ 已合併（Windows 人工驗證 2026-11-06 使用者回報通過） | #398 |
| 6 | Flutter 升級至 ≥ 3.47.7（評估與遷移）：`onReorder` 棄用、built-in Kotlin／AGP 9、Windows 預設 Impeller、外掛相容；一併處理繁中 Windows 的 `/utf-8` 編譯問題 | Issue 11 | ✅ 已合併（共用 SDK 升到 3.47.9；`desktop_drop` 維持 0.8.4，登記 Issue 16；Android 已在 WAVE 真機安裝並實測啟動與重複開書，未跑 integration_test；過關條件 8 的全套測試有 1 個偶發失敗，以 ruling 判為偶發，見 [issue-6-report.md](issue-6-report.md)） | #404 |
| 7 | Windows 鍵盤快捷鍵與 F11 視窗全螢幕：翻頁類按鍵、Ctrl+F、F11，Esc 依序處理浮層與全螢幕 | Issue 5 | ✅ 已合併（Windows 人工驗證 2026-11-06 使用者回報通過，F11／Esc 在 WebView2 有焦點時可用） | #399 |
| 8 | 索引器在 Windows 讓整個 App 消失：根因是漏登錄 JS 會呼叫的處理器（Windows 外掛遇到未登錄處理器會結束程序）；已診斷並修正，報告見 [issue-8-report.md](issue-8-report.md) | Issue 4 | ✅ 已合併（大檔索引、背景排程端到端、Android 尚未實測） | #400 |
| 9 | WebView2 未安裝時顯示說明與下載連結（決策 4，原本漏掉） | Issue 7 | ✅ 已合併（Windows 實機以空 Runtime 資料夾模擬驗證通過；2026-11-09 使用者確認有 WebView2 時正常啟動；乾淨機器、重新檢查成功後進入 App 未實測（無乾淨機器，使用者決定記為未實測）） | #401 |
| 10 | 平台專屬功能隱藏：音量鍵翻頁、E-Ink 高對比與影像濾鏡、螢幕方向鎖定、「全螢幕模式」偏好項；並處理 Windows 呼叫 Android 原生全螢幕 channel 未處理例外 | Issue 7 | ✅ 已合併（Windows 實機確認 2026-11-09 使用者回報 a～e 全數通過，見 [issue-10-report.md](issue-10-report.md)） | #402 |
| 11 | Windows 測試穩定性：追查 `local_book_server_test.dart` 偶發失敗與 `pdf_reader_view_filters_test.dart`（`main` 上同樣失敗），為 Issue 6 建立乾淨基準；已查出根因是這台機器的 `127.0.0.1` 連線被重設，並新增開書逾時驗證 | 無 | ✅ 已合併（過關條件 5 以 ruling 延後：`pdf_reader_view_filters_test` 偶發失敗已重現但未修，登記為 Issue 15；開書逾時對照實驗結論為不能確定，見 [issue-11-report.md](issue-11-report.md)） | #403 |
| 12 | Android 也改用 foliate-js 讀 metadata、移除 Readium（`readium-shared`／`readium-streamer`、`BookMetadataChannel.kt`）：**第一步先補真實出版社書籍的 Readium 對比，通過才移除**；需 Android 實機 | Issue 6 | 🟢 階段一已完成並合併（PR #405；預設改 foliate-js、Readium 留作退路；見 [plan-issue-12.md](plans/plan-issue-12.md)、[issue-12-report.md](issue-12-report.md)；階段二見 Issue 18） | — |
| 13 | Windows `integration_test` 冒煙測試（每種格式：開書、翻頁、劃線） | Issue 6、8、9、10 | 🟢 已合併（PR #406、#407；套件清單 27 支檔案在本機 debug 版依序全數通過，其中 `library_screen_test` 3 項在 Windows 全部略過、`pdf_reader_view_test` 1 項略過；`reader_screen_test` 不在清單內，已登記 Issue 19；Android 只在一台 BooksPad 跑過 11 支，其中 3 支仍有失敗，已登記 Issue 21；見 [plan-issue-13.md](plans/plan-issue-13.md)、[issue-13-report.md](issue-13-report.md)） | — |
| 14 | 免安裝 zip 打包（含 VC++ 執行階段 DLL、README、SHA256；不簽章、不上傳） | Issue 13 | 🟢 已完成實作與自動化驗證（見 [plan-issue-14.md](plans/plan-issue-14.md)、[issue-14-report.md](issue-14-report.md)；乾淨機器未驗證，待使用者開書確認） | — |
| 15 | `pdf_reader_view_filters_test.dart` 加粗覆蓋圖偶發失敗查根因：整批跑 `test/reader` 約 1／3 機率失敗（等背景 Isolate 結果 120 輪仍無 `RawImage`），等待上限已放寬兩次仍偶發，疑 `PdfReaderView` 加粗佇列有競態（來源 Issue 11） | 無 | ⚪ 未開始（尚未規劃） | — |
| 16 | `desktop_drop` 0.9 與 `cross_file` 0.4 遷移：`desktop_drop` 0.9.x 要求 `cross_file ^0.4.0`（破壞性更新），與 `file_picker`、`share_plus`、`share_plus_platform_interface`（含最新版）要求的 `cross_file ^0.3.x` 衝突，需 vendor 修補三個套件並改寫拖曳匯入（來源 Issue 6） | Issue 6 | ⚪ 未開始（尚未規劃，不排程） | — |
| 17 | Android 建置工具升級：Flutter 3.47.9 警告對 Gradle 8.14.0（需 ≥ 9.1.0）與 AGP 8.11.1（需 ≥ 9.0.1）的支援「即將移除」，目前仍可建置；一併評估 built-in Kotlin 遷移（來源 Issue 6） | Issue 6 | ⚪ 未開始（尚未規劃，不排程） | — |
| 19 | `reader_screen_test` 在 Windows 整份中斷診斷：未修改的 `HEAD` 在這台機器上也會在第一支測試結束後整個結束（App 結束、exit 79、後續 18 支 `did not complete`），單獨跑第 1、2 支皆通過；原因未明（來源 Issue 13） | 無 | ⚪ 未開始（尚未規劃，不排程） | — |
| 20 | 桌面寬度（> 720px）雙欄排版下 EPUB 目錄「目前章節」判定落在前一章：Foliate 在雙欄補齊前一節內容並回報前一節，目錄因此沒收折；Issue 13 為了讓測試通過把視窗縮成 400x800，未判定是否為產品缺陷，且冒煙套件沒有任何一支在桌面寬度驗證（來源 Issue 13） | 無 | ⚪ 未開始（尚未規劃，不排程） | — |
| 21 | Android 上 `epub_toc_test`（1/2）、`epub_highlights_notes_test`（0/1）、`reader_screen_test`（14/19）仍有失敗：BooksPad（Android 12）螢幕常亮下實測，原因未查明；已排除 400x800 視窗覆寫與螢幕熄滅；PR 前版本在同機上這些測試連書都載入不了（來源 Issue 13） | 無 | ⚪ 未開始（尚未規劃，不排程） | — |

## Issue 1 範圍

過關條件要在 Windows 上實際開書，所以 Issue 1 必須包含下列前置工作（`epic.md` 決策 15～19）：

1. 啟用 `app/windows/`。
2. 啟動鏈平台防護：Windows 跳過 `AudioSession` 與 `AudioService.init()`，並決定 `TtsAudioHandlerHolder` 在 Windows 的狀態。
3. 最小 `shelf` 送書原型：只求能讓過關條件 1～4 跑起來，不做權杖與快取清理。
4. foliate-js 資源讓 Windows 取得得到，並讓書檔、資源、字型的 base URL 可由平台決定（Android 的值不變）。
5. `WebViewEnvironment` 的使用者資料夾指到 `%APPDATA%`。

## Issue 1 過關條件

全部通過才往下做。第 1 項失敗就停下來，重新評估整個計畫；其餘失敗各自討論。

1. EPUB 在 WebView2 能開，直排與橫排都正確。
2. 滑鼠拖曳能選字，並出現劃線工具列。
3. PDF 能開，頁數正確；並能用 `pdfrx` 算出第 0 頁封面 PNG。
4. `HeadlessInAppWebView` 能用 foliate-js 讀出書名、作者、`identifier`、封面。
5. 字典 MDX 的 WebView 能擋住所有外部網路（Android 靠 `shouldInterceptRequest`，Windows 要找對應做法）。
6. SQLite FTS5 搜尋可用。
7. `flutter_secure_storage` 能存取同步憑證。

同時產出：

- WebView2 是否有請求攔截或虛擬網域對應（決定送書方式，見 `epic.md` 決策 6）。
- foliate-js 與 Readium 的 metadata 逐本對比表（決定是否統一，見決策 7）。

## Issue 2 範圍

目前 Windows 匯入 EPUB／PDF 時沒有 `elinkbook/book_metadata` 原生端，書名退回檔名、沒有封面、沒有作者與 `identifier`（Issue 1 Task 8 的降級）。Issue 2 補上：

1. EPUB：用 `HeadlessInAppWebView` 載入 foliate-js，讀書名、第一位作者、`identifier`、是否固定版面、封面。
2. PDF：用 `pdfrx` 渲染第 0 頁為 PNG 封面（最長邊 600 px，與 Android 相同），書名與作者維持 `null`（與 Android 相同）。
3. 回傳格式與 Android 的 `extractMetadata` 相同（`title`／`author`／`coverBytes`／`isFixedLayout`／`identifier`），讓 `book_import_service_impl.dart` 的消費端不改。
4. 與 Android Readium 逐本對比（決策 7 的前提），特別是 `identifier`：`book_content_fingerprint.dart` 優先用它當指紋，兩端不一致會讓同步把同一本書當成兩本。

不在範圍：資料夾匯入、`Book.filePath` 規範、鍵盤快捷鍵、平台功能隱藏、大檔分段服務、EPUB 以外格式（TXT／MD／CBZ／AZW3 本來就是純 Dart，不受影響）。

## Issue 2 過關條件

1. Windows 匯入 EPUB fixture 後，`title`、第一位 `author`、`identifier`、`isFixedLayout`、封面都與 fixture 宣告值一致（含：多筆 `dc:identifier`、多位作者、多語系書名、EPUB2 式 `<meta name="cover">`、無封面、固定版面）。
2. Windows 匯入 PDF 後有 PNG 封面，最長邊不超過 600 px，`title`／`author` 為 `null`。
3. 解析失敗（損毀 EPUB、逾時）不中斷匯入：退回檔名為標題、無封面；不留下孤兒封面檔，且 headless WebView 會釋放（之後再解析仍成功）。
4. Android 行為不變：既有測試全綠，`main.dart` 在 Android 不注入 Windows 解析器。
5. 產出 Readium 與 foliate-js 的逐本對比表（同一批 fixture，Android 實機跑 Readium，Windows 跑 foliate-js），`identifier` 不一致的逐一列出；依結果修訂 `epic.md` 決策 7。
6. 讀 224 MB EPUB 的 metadata 時，記下 App 與 WebView2 的尖峰記憶體，與開書的 3.8 GB 比較。
7. 重新連結（`relinkBook`）與同步指紋回填在 Windows 取得的 `identifier` 與匯入時相同：同一本 EPUB 重新連結成功，同步回填的指紋等於 `identifier`。

## Issue 2 單元測試要求

- `readBookMetadata()`（JS，Puppeteer 測試台）：每份 fixture 的欄位期望值；書名為語系物件時取第一個值；作者為字串、物件、陣列三種形態都取第一位的名稱；缺 `identifier`、缺封面回 `null`；固定版面回 `true`。
- `renderPdfCover()`：回 PNG 簽章 `89 50 4E 47`；最長邊不超過 600；不存在的檔案回 `null`。
- `extractWindowsBookMetadata()`：依 `format` 分派（`epub`／`pdf`）；其他格式回 `null`；同時呼叫時依序執行（同一時間只有一個 headless WebView）；EPUB 解析逾時時釋放 WebView。
- `BookImportServiceImpl`（注入假解析器）：解析結果的 `title`／`author`／`isFixedLayout`／`identifier` 進入 `Book`；封面落地成 `<bookId>.png`；指紋採用 `identifier`；解析器丟 `PlatformException` 時降級；未注入解析器時走原有 channel 路徑（Android 不變）；`relinkBook` 透過解析器取得 `identifier` 比對指紋。
- `SyncEngine`（注入假解析器）：回填的指紋等於 `identifier`；解析器丟 `MissingPluginException` 時退回整檔 SHA-256、不中斷。
## Issue 3 範圍

Issue 2 的程式碼審查發現：用 `shouldInterceptRequest` 把大資料回傳給 WebView，會讓 App 程序（`elinkbook.exe`）的原生記憶體**永久**多出約兩份資料大小，量與傳輸位元組成正比（224 MB 的書每解析一次，私有記憶體多約 452 MB）。headless metadata 路徑已實證並以「只傳需要的區段」修正（`issue-2-report.md` 第 4 節）。

**同樣的機制還用在下列兩處，是否洩漏未驗證**（`issue-2-report.md` 第 5 節）：

1. **閱讀器開書：** `FoliateReaderView` 以攔截回應整本書位元組（`readWindowsBookBytes`）。Issue 1 的實測顯示離開閱讀器後 App 沒有多出兩份書的大小，所以**可能不受影響**，但原因沒有查明。
2. **全文索引器：** `FoliateContentIndexer` 同樣用 `HeadlessInAppWebView` 加攔截，一次處理一本，批次索引大書時若洩漏會累加。

要做的事：

1. 建立可重現的量測迴圈：同一個程序內重複開關同一本 224 MB 書（閱讀器）、重複索引同一本書（索引器），用程序內私有記憶體（Private Bytes）與工作集量測。可沿用 `integration_test/windows_metadata/leak_probe_test.dart` 的做法與 `tool/measure_large_epub_memory.ps1`。
2. 判定兩條路徑是否洩漏，並記錄數據。
3. 若洩漏：設計修法。Issue 2 的做法是「只傳需要的區段」；閱讀器需要整本內容，是否能區段化需要設計，不行就回頭檢視 `epic.md` 決策 15（`shelf` 備案）。**設計前先與使用者討論，不可逕自動手。**
4. 若不洩漏：查明 Issue 1 觀察到「離開閱讀器沒有多出兩份」的原因，寫進報告，確認該原因穩定而非巧合。

不在範圍：大檔開書的瞬間尖峰（Issue 1 實測 224 MB 書開書合計尖峰約 3.8 GB，持續約 3 秒後回落）。若洩漏已解決、尖峰仍要改善，另開「分段服務」Issue。

## Issue 3 過關條件

1. 有可重現、可自動執行的量測迴圈，涵蓋閱讀器與索引器兩條路徑，輸出每次開關／索引後的私有記憶體。
2. 兩條路徑各有「是否洩漏」的明確判定與數據（至少重複 4 次，每次後等待回落再量）。
3. 洩漏者修正後：重複 4 次，每次私有記憶體增量低於書檔大小的 5%（以 224 MB 的書為準），且結果與修正前功能一致。
4. 不洩漏者：有原因說明，並說明為何可信、不是量測巧合。
5. `epic.md` 決策 15 依結果補【Issue 3 結果】。

## Issue 3 單元測試要求

- Windows 整合測試（`-d windows`）：閱讀器與索引器各一支重複開關迴圈，輸出 `[leak] iter=<n> phase=<…> private_mb=<…>` 行；斷言增量門檻（過關條件 3）。
- 若修法新增純邏輯（例如區段切片、查詢解析），須有純 Dart 單元測試，比照 `test/library/windows_epub_range_test.dart`。
## Issue 4 範圍

Issue 3 已實證：閱讀器開書以 `shouldInterceptRequest` 整本回傳 224 MB 的書，App 程序私有記憶體每次開關**永久**多約 452 MB，debug 與 Release 版皆然，且與 Dart 端是否保留位元組陣列無關（`issue-3-report.md` §7.1）。依 `issue-3-report.md` §5 與使用者決定：WebView2 虛擬網域對應（選項 D）需 vendor 並修補外掛 C++，不採用；改走**選項 A：本機 `shelf` 伺服器**。

**做法（設計決定，細節見 `plans/plan-issue-4.md`）：**

1. **只搬書檔。** 只有 `/book/` 改由 App 內的 loopback HTTP 伺服器串流服務（綁 `127.0.0.1`、隨機埠、每本書一個隨機權杖、支援 HTTP Range）。foliate-js 頁面與資源、字型維持現行攔截（檔小）。
2. **頁面來源不變。** 頁面仍由攔截載入、origin 仍是 `https://appassets.androidplatform.net`；`main.js` 新增 `bookBaseUrl` 查詢參數，**未帶時維持原本寫死的網址**，所以 Android 與 metadata 解析器完全不受影響。伺服器對該 origin 回 CORS 標頭。
3. **Windows 專屬。** Android 維持 `WebViewAssetLoader`，不起伺服器。
4. **風險優先：** 先做拋棄式原型，用 Issue 3 的 `reader_leak_test` 量測洩漏是否真的消失，**通過才進入正式實作**；沒通過就停下重新評估。

要做的事：

1. 拋棄式原型 + 量測閘門（debug 與 Release）。
2. `Range` 標頭解析（純邏輯）、書檔 HTTP 處理器、`LocalBookServer`（生命週期、權杖註冊／釋放）。
3. `main.js` 的 `bookBaseUrl` 參數與 Dart 端 URL 組裝。
4. `FoliateReaderView` 在 Windows 改用伺服器；移除變成死碼的 `readWindowsBookBytes`／`windowsBookContentType` 與 `/book/` 攔截分支。
5. `FoliateContentIndexer` 同步改用（已決策納入；**端到端驗證受 Headless 卡住問題阻擋，見不在範圍**）。
6. ADR、`epic.md` 決策 6／15 補【Issue 3／4 結果】、重跑洩漏量測並寫 `issue-4-report.md`。

不在範圍：

- **索引器在 Windows `HeadlessInAppWebView` 無法跑完**（隱藏視窗疑似暫停 rAF，`issue-3-report.md` §4）：另開 Issue 追查，本 Issue 不解決。
- **開書時 WebView 端仍會把整本書讀進 WebView2 程序**（foliate-js 的 `makeBook(url)` 是 `fetch` 後轉 Blob）：改成 Range 版 loader 屬「分段服務」，另開 Issue；本 Issue 的目標是消除 `elinkbook.exe` 的洩漏，WebView2 子程序的尖峰只記錄。
- **自訂字型走攔截的洩漏**：字型是整檔回傳，單檔可達數 MB 到十數 MB，理論上有相同的比例洩漏。本 Issue 只量測並記錄，是否一併搬到伺服器視數據另議。
- 前兩輪的一次性額外記憶體增量（`issue-3-report.md` §3.2，成因未查明）。
- 直接服務原檔、省略快取複製：維持現行「先複製到快取子目錄再服務」，避免改變檔案生命週期。

## Issue 4 過關條件

1. **洩漏消失（debug）：** Windows `reader_leak_test` 暖身 1 次 + 正式 4 次，每次私有記憶體增量 < 書檔大小 × 5%（224.7 MB 的書約 11.23 MB）；`leaked == false`。
2. **洩漏消失（Release）：** 以 Issue 3 的 Release 迴圈（暫時進入點）重跑，同樣 4 次皆低於門檻。
3. **功能一致：** Windows 開 EPUB 後能翻頁、選字並出現劃線工具列、目錄可用、直排與橫排正確；CBZ（固定版面）能開。
4. **安全：** 伺服器只綁 loopback；未註冊或已釋放的權杖回 404；`Host` 標頭不是 `127.0.0.1:<port>` 回 403；CORS 只放行 `https://appassets.androidplatform.net`；不可能讀到註冊檔案以外的檔案。
5. **生命週期：** 離開閱讀器後權杖失效、快取子目錄已刪；同一本書連開兩次互不影響；開書中途離開不留殘餘註冊。
6. **Android 行為不變：** `main.js` 未帶 `bookBaseUrl` 時的網址與現狀逐字相同；Android 不起伺服器；既有測試全綠。
7. **記錄（不設硬門檻）：** 224 MB 書開書時 App 與 WebView2 的尖峰記憶體，與 Issue 1 的 3.8 GB 對照；字型攔截的洩漏量。
8. 新增 ADR；`epic.md` 決策 6／15 補【Issue 3／4 結果】。

## Issue 4 單元測試要求

- `parseByteRange()`（純 Dart）：`bytes=a-b`、`a-`、`-n`（尾端 n 位元組）；`b` 超過檔尾時截斷；`a` 超過檔尾 → 不可滿足（416）；`a > b`、非 `bytes` 單位、格式錯誤 → 無效；多段範圍 → 視為不支援（回整檔 200）；大小為 0 的檔案。
- 書檔處理器（直接呼叫 shelf `Handler`，不開 socket）：無 `Range` 回 200 + `Content-Length` + `Accept-Ranges: bytes`；單一範圍回 206 + 正確 `Content-Range` 與內容；416；`HEAD` 無本文；`OPTIONS` 預檢回允許 `Range`；未知權杖 404；`Host` 不符 403；`POST` 等回 405；CORS 標頭只對指定 origin；`Content-Type` 依副檔名（`.epub`／`.cbz`）。
- `LocalBookServer`（真實 loopback socket）：`address.isLoopback`；`register` 後以 `HttpClient` 取得的位元組（含 Range 區段）與原檔一致；`dispose` 後同網址 404；`close` 後連線被拒；同一程序多本書、多個權杖互不影響；權杖不可預測（長度與熵的下限）。
- URL 組裝：Windows 帶 `bookBaseUrl`、Android 與其他平台不帶（`_buildIndexUri` 既有測試不變）。
- JS：`bookBaseUrl` 未帶時 `openBook()` 使用的網址與現狀逐字相同（以現有 JS 測試台或純函式抽出後測試）。
- Windows 整合測試（`-d windows`）：沿用 `reader_leak_test.dart`，修法後把 `[leak-verdict]` 改為斷言 `leaked == false`。

## Issue 5 範圍

讓 Windows 使用者能用**選檔、選資料夾、拖曳**三種方式把書放進書架，三者進同一條匯入管線，行為與 Android 對齊。設計決策來自 2026-11-06 `/grill-with-docs`，詞彙見 `CONTEXT.md`「拖曳匯入」，決策見 `epic.md` 決策 5（修訂）與 25。細節見 `plans/plan-issue-5.md`。

**已確認的現況（查證過程見 plan）：**

- 選檔：`pickAndImportFiles` 在 Issue 1 Task 8 已取 `identifier ?? path`，Windows 已可選檔，本 Issue 只補驗證。
- 選資料夾：Windows 沒有可用路徑——`pickAndImportFolder` 走 Android 原生 `elinkbook/folder_picker`，`importFolder` 先呼叫 `persistReadAccess`（原生 channel，Windows 會拋 `MissingPluginException`，且該例外不會被轉成 `false`）再呼叫原生 `listFolderContents`。
- 拖曳：完全沒有，專案沒有任何拖放套件。
- 匯入入口在「來源」畫面（`sources_home_screen.dart`），書架畫面沒有匯入按鈕。三個畫面（書架、來源、設定）由 `AdaptiveShellScaffold` 的 `IndexedStack` 同時掛載。
- 不支援的格式：`_importSingleFile` 對無法辨識的格式回傳 `null`，目前**無聲略過、沒有計數**；Android 的資料夾匯入不過濾副檔名，也是如此。

**做法：**

1. **`ImportResult` 新增 `skippedUnsupportedCount`**（預設 0）。`importFiles`／`importFolder` 在去重之前先判斷格式，無法辨識就計數並略過。結果提示 `showImportResultSnackBar` 另起一行說明略過幾個，與「略過重複」分開。此行為跨平台（Android 資料夾匯入也會多出提示）。
2. **本機資料夾匯入走 `dart:io`。** `importFolder` 收到不以 `content://` 開頭的資料夾路徑時，不呼叫 `persistReadAccess` 與原生 `listFolderContents`，改用 `Directory.listSync` 只列第一層檔案（不進子資料夾、不跟隨連結），資料夾名稱取路徑最後一段。目錄不存在或不可讀回 `folderListingFailed`。`content://` 路徑逐字不變，Android 行為不受影響。
3. **選資料夾對話框改為可注入。** `pickAndImportFolder` 新增選用參數 `pickFolderPath`，預設在 Windows 用 `FilePicker.getDirectoryPath()`、其他平台維持原生 channel。
4. **拖曳匯入。** 新增純邏輯 `importDroppedPaths`（把拖入的路徑分成檔案與資料夾；檔案走 `importFiles`；每個資料夾走 `importFolder`；整批只問一次「依資料夾名稱自動分類」；取消確認框則整批取消；結果合併成一個 `ImportResult`）與 `ImportDropTarget` widget（包 `desktop_drop` 的 `DropTarget`，只在 Windows 啟用，拖曳經過顯示「放開以匯入」遮罩，匯入中再拖入忽略並提示，匯入後沿用既有的結果提示與「疑似更新版」流程）。
5. **只在書架與來源畫面有效。** `ImportDropTarget` 包住 `AdaptiveShellScaffold` 的 `IndexedStack`，設定分頁、以及任何疊在上方的路由（閱讀器、對話框）都停用。
6. **書檔不複製，維持原路徑**（`epic.md` 決策 5 修訂）。Windows「來源」畫面在匯入區塊旁常駐一行說明文字：書檔仍使用原本位置，搬動或刪除原檔後該書將無法開啟。
7. **新增依賴 `desktop_drop` 0.8.4**（固定版本，不用 `^`）。0.9.x 要求 Flutter ≥ 3.47.7，與專案固定的 3.41.9 不相容；0.8.4 不依賴 `win32`。

不在範圍：

- 雲端匯入（Google Drive／OneDrive）。
- 資料夾遞迴匯入子資料夾。
- 閱讀器與設定畫面的拖曳。
- 匯入進度條、可取消的匯入、匯入排隊。
- Flutter 升級（Issue 6）。`pubspec.lock` 與本機 Flutter 3.41.9 的既有落差（單純 `pub get` 會降級 `intl`、`meta`、`pdfrx_engine` 等 6 個套件）也留給 Issue 6，本 Issue 不處理。
- 拖曳匯入的端對端自動化測試：真實的 OS 拖放無法在 `flutter test` 或 `integration_test` 中模擬，改由人工驗證清單。

## Issue 5 過關條件

1. **選檔（Windows）：** 用選檔對話框選多個 `.epub`／`.pdf`／`.txt`／`.cbz`／`.azw3`／`.md`，全部出現在書架，`Book.filePath` 是標準本機路徑（不是 `file:///`），開書正常。
2. **選資料夾（Windows）：** 選一個含書與非書檔案的資料夾，先出現「依資料夾名稱自動分類」確認框；匯入後只含該資料夾第一層的書，子資料夾內的書不匯入；勾選自動分類時書歸入以資料夾名命名的分類。選不存在或無權限的資料夾，提示資料夾匯入失敗而不是崩潰或無聲無息。
3. **拖曳檔案：** 把多個書檔拖進「書架」與「來源」畫面都能匯入；拖進「設定」畫面、閱讀器、任何對話框之上都不響應。停在書架畫面直接拖入時，新書立即出現在書單，不需要切換分頁。
4. **拖曳資料夾：** 行為與選資料夾一致（含確認框）；同一次拖入多個資料夾只跳一次確認框，選擇套用到全部，每個資料夾各自成為一個分類；混合拖入檔案與資料夾時，單檔不歸入分類；取消確認框則整批都不匯入。
5. **不支援的格式：** 拖入或資料夾裡的 `.jpg`、`.zip` 等一律略過，不產生書、不報錯；匯入結束提示說明略過幾個，且與「略過重複」分開顯示。Android 的資料夾匯入同樣會顯示此提示。
6. **匯入中再拖入：** 忽略新的拖入並提示「匯入進行中，請稍後再拖入」，不重複匯入、不崩潰。
7. **視覺回饋：** 拖曳經過視窗時顯示「放開以匯入」遮罩；離開或放開後消失。
8. **疑似更新版與重複：** 拖入既有書的更新版或完全相同的檔案，行為與選檔匯入一致（跳更新確認或計入略過重複）。
9. **提醒文字：** Windows 的「來源」畫面常駐說明「書檔維持原位置，搬動或刪除原檔後該書將無法開啟」；Android 看不到這行。
10. **Android 行為不變：** `content://` 的選檔與選資料夾路徑逐字不變（除了新增的「略過不支援」提示）；`DropTarget` 在非 Windows 不掛載；既有測試全綠。
11. **人工驗證（Windows 實機，結果記入 `issue-5-report.md`）：** 條件 1 到 9 逐項實測，特別是真實的拖放（單檔、多檔、資料夾、混合、拖到設定畫面、匯入中再拖）。

## Issue 5 單元測試要求

- `ImportResult`：`skippedUnsupportedCount` 預設 0，既有建構呼叫不受影響。
- `BookImportServiceImpl.importFiles`：混入 `.jpg` 的清單，書只匯入可辨識格式、`skippedUnsupportedCount` 等於不可辨識的個數；不可辨識的檔案不計入 `skippedDuplicateCount`。
- `BookImportServiceImpl.importFolder`（本機路徑，用暫存目錄）：只匯入第一層；子資料夾內的書不匯入；`folderName` 為資料夾名稱；`autoGroupByFolderName` 為真時建立分類；非書檔計入 `skippedUnsupportedCount`；不存在的目錄回 `folderListingFailed`；全程不呼叫 `kBookMetadataChannel`（用會失敗的 mock 證明）。
- `importFolder`（`content://`）：既有測試不變。
- `pickAndImportFolder`：注入 `pickFolderPath` 回傳路徑時，路徑原樣傳給 `importFolder`；回傳 `null` 時整體回 `null` 且不問確認框。
- `showImportResultSnackBar`：只有略過不支援、與其他計數並存、全為 0 三種情況的訊息文字。
- `importDroppedPaths`：只有檔案（不問確認框）、只有資料夾、混合、多資料夾只問一次、取消確認框整批取消且不呼叫任何匯入、結果合併（書、兩種略過計數、更新候選相加；失敗只在「無檔案且所有資料夾皆失敗」時才設）。
- `ImportDropTarget`（widget test，`debugDefaultTargetPlatformOverride = windows`）：非 Windows 不掛載 `DropTarget`；`enabled: false` 時不響應；拖曳經過顯示遮罩、離開消失；匯入中再拖入不呼叫匯入並顯示提示；匯入完成顯示結果提示。
- `AdaptiveShellScaffold`：停留在書架與來源分頁時拖曳啟用，切到設定分頁時停用；停在書架分頁拖入新書後書單重新載入。
- `SourcesHomeScreen`：Windows 顯示提醒文字，其他平台不顯示。
- l10n：四個 arb（`app_zh_TW`、`app_zh`、`app_zh_CN`、`app_en`）都有新字串，`flutter gen-l10n` 成功；`check_l10n_hardcoded_strings.js` PASS。

## Issue 7 範圍

讓 Windows 使用者用實體鍵盤翻頁、搜尋，並用 F11 切換視窗全螢幕。設計決策來自 2026-11-06 `/grill-with-docs`，詞彙見 `CONTEXT.md`「鍵盤快捷鍵」「視窗全螢幕」，決策見 `epic.md` 決策 26，細節見 `plans/plan-issue-7.md`。**所有新增按鍵只在 Windows 生效，Android 與其他平台零改動。**

**已確認的現況（查證過程見 plan）：**

- 閱讀器已有一條統一的動作入口：`ReaderScreen._handleZoneAction(ZoneAction)`，熱區與音量鍵都走它；`ReaderSurface.jumpTo(ReaderJumpTarget)` 已能跳到進度比例（Foliate）或頁碼（PDF）；`_openBookSearch()` 是書內搜尋入口。鍵盤只需接到這些既有入口。
- PDF 只在「分頁模式」才掛 `onKey: _onPagedKey`（PageUp、PageDown、Space、Home、End），沒有方向鍵，捲動模式用 `pdfrx` 預設行為；EPUB 完全沒有鍵盤處理（`main.js` 沒有 `keydown`）。
- 搜尋是全螢幕路由 `BookSearchScreen`（輸入框 `autofocus: false`，已有 `_searchFocusNode`），不是疊在閱讀器上的面板。
- 專案沒有 `window_manager`；`window_manager` 0.5.2 可用（不依賴 `win32`，見 `epic.md` 決策 26）。
- **關鍵風險（已由實機驗證化解）：** WebView2 取得焦點時，方向鍵、Space、Home、End、Ctrl+F 只進網頁（已改由 `main.js` 轉送）。F11 與 Esc 在 Task 1 的合成輸入量測中兩邊都沒收到，但那是**推論而非結論**（合成輸入、只掛頂層 `window`、未量 section iframe）。2026-11-06 使用者以真實鍵盤在 Windows 實機驗證，書頁有焦點時 F11 與 Esc 皆可用，見 `plan-issue-7.md` Ruling 3。`flutter_inappwebview_windows` 仍沒有暴露 `AreBrowserAcceleratorKeysEnabled`，此事實不變。

**做法：**

1. **Task 1 實測（不產出正式程式）：** 在 Windows 上實測 WebView2 有焦點時，方向鍵、Space、Home、End、Ctrl+F、F11、Esc 各進哪一邊，結論記入 `issue-7-report.md`，決定 EPUB 走「A：Flutter 全域按鍵處理器就夠」或「B：`main.js` 轉送按鍵給 Dart」。
2. **純邏輯：** `readerKeyCommandFor(key, shift, control, alt, meta, verticalWriting)` 把按鍵對應成 `ReaderKeyCommand`（上一頁、下一頁、首頁、末頁、開啟搜尋）；直排時 ←／→ 鏡像；帶 Ctrl／Alt／Meta 的組合除了 Ctrl+F 一律不處理。
3. **視窗全螢幕：** `WindowFullscreenController` 介面加 `window_manager` 0.5.2 實作；只在 Windows 初始化；`WindowFullscreenShortcuts` 掛在 `MaterialApp.builder`：F11 用全域 `HardwareKeyboard` 處理器（任何畫面、不依賴焦點）；Esc 由單一決策點 `handleWindowEscape` 處理，優先序：焦點處可關閉的浮層（路由 `barrierDismissible` 或 `DismissAction` 子類）→ 註冊式內層消費者（閱讀器的文字選取與 PDF 裁切模式，且只在閱讀器是最上層時參與）→ 視窗全螢幕時退出。**不能**用 builder 層的 `Actions` 覆寫 `DismissIntent`（每個路由自帶的 `DismissIntent` 動作會遮蔽它，Flutter 原始碼已查證），也**不能**只看「最近的 `DismissIntent` 動作是否啟用」（`EditableText` 自帶永遠啟用的動作，輸入框有焦點時會被誤判成浮層）。控制器維護同步可讀的 `isFullscreenNow` 快取（`Action.isEnabled` 必須同步回答），連按 F11 以進行中旗標避免競態。
4. **閱讀器按鍵：** `ReaderScreen` 在 Windows 註冊全域 `HardwareKeyboard` 處理器（`dispose` 時移除）：路由不是最上層或文字輸入框有焦點時暫停；翻頁類走 `_handleZoneAction`，Home／End 走 `ReaderSurface.jumpTo`，Ctrl+F 走 `_openBookSearch`；書籍不在 `OpenBookRendered`（載入中、失敗等）或 PDF 手動裁切模式時一律忽略；Home／End 比照 `_handleZoneAction` 補清除搜尋高亮與記錄閱讀活動；Esc 在有文字選取時清除選取、在 PDF 裁切模式時只吞掉（不退出裁切、不退出全螢幕）。處理器先於焦點樹消費事件，因此不需要修改 `pdfrx` 的 `_onPagedKey`。
5. **EPUB 交付：** 依 Task 1 結論，A 則補驗證測試，B 則在 `main.js` 於 Windows 對每個 section 文件掛 `keydown` 並轉送（含 F11、Esc；`Ctrl+F` 的 `e.key` 在 CapsLock 開啟時是 `'F'`，需大小寫都接受），Android 不啟用；同一按鍵從 Flutter 與 WebView 兩邊送達時以 50 毫秒去重器只處理一次。
6. **`BookSearchScreen`：** Windows 上開啟即聚焦搜尋輸入框（Android 維持不自動聚焦，避免軟鍵盤彈出）；Ctrl+F 重新聚焦並全選既有文字，用全域 `HardwareKeyboard` 處理器實作（`CallbackShortcuts` 在焦點節點不在其子樹時收不到事件）。
7. **新增依賴 `window_manager` 0.5.2**（固定版本，不用 `^`）。

不在範圍：

- 目錄、書籤、字級、版面設定等其他快捷鍵；快捷鍵自訂與說明畫面。
- 滑鼠滾輪翻頁。
- 書架畫面的 Ctrl+F。
- 「全螢幕模式」偏好項在 Windows 設定中的隱藏，以及 Windows 上呼叫 Android 原生全螢幕 channel 未處理例外（`reader_screen.dart` 約 742 行）：留給「平台專屬功能隱藏」Issue，該 Issue 的隱藏清單要補進「全螢幕模式」。
- 視窗全螢幕狀態的持久化（每次啟動回到一般視窗）。
- Flutter 升級（Issue 6）；`window_manager` 升到 0.6.x 也留給 Issue 6。
- 真實按鍵與焦點行為的自動化測試：`flutter test` 的按鍵模擬只進 Flutter 框架，無法模擬 OS 層級送進 WebView2 的按鍵，改由人工驗證清單。

## Issue 7 過關條件

1. **實測結論：** `issue-7-report.md` 記錄 Task 1 的實測結果（WebView2 有焦點時各按鍵的歸屬）與採用的方案（A 或 B），並附實測方法。
2. **翻頁（EPUB 橫排）：** ←／↑／PageUp／Shift+Space 為上一頁，→／↓／PageDown／Space 為下一頁，Home／End 跳首頁與末頁；按住不放連續翻頁。
3. **翻頁（EPUB 直排）：** ←／→ 左右鏡像（← 為下一頁），其餘按鍵不變。
4. **翻頁（PDF）：** 同條件 2（PDF 沒有直排概念，不鏡像），分頁與捲動兩種模式行為一致。
5. **暫停條件：** 搜尋輸入框、備註輸入框有焦點，或對話框、面板疊在閱讀器上、或搜尋畫面開著時，按 ←／→／Space／Home／End 不翻頁。
6. **Ctrl+F：** 在閱讀器內開啟書內搜尋，搜尋畫面開啟後游標已在輸入框、可直接打字；在搜尋畫面內再按 Ctrl+F 重新聚焦並全選既有文字；書架畫面按 Ctrl+F 沒有反應；書籍載入中、失敗或 PDF 手動裁切模式時按 Ctrl+F 不會開啟搜尋。
7. **F11：** 在書架、來源、設定、閱讀器、PDF 閱讀、以及 EPUB 閱讀（焦點在 Flutter 區域時）都能切換視窗全螢幕；切換畫面或離開閱讀器不會重置全螢幕；重新啟動 App 回到一般視窗；連按 F11 不亂。**EPUB 書頁（WebView2）有焦點時 F11 是否可用，必須用真實鍵盤實測並記錄結果**；若實測無效，不得宣稱通過，須寫入已知限制並另開 Issue（需修改外掛或原生層，本 Issue 不處理）。**實測結果（2026-11-06，使用者以真實鍵盤在 Windows 實機回報）：可用。**未留下按鍵進入哪一邊的 log，僅為行為層面的結果。
8. **Esc：** 有對話框或面板時先關它、視窗全螢幕維持；閱讀器內有文字選取時先清除選取、PDF 手動裁切模式中只吞掉（不退出裁切、不退出全螢幕），視窗全螢幕維持；沒有任何內層狀態且在視窗全螢幕時退出全螢幕；沒有內層狀態也不在全螢幕時，閱讀器**不會**返回書架。疊在閱讀器上的頁面（例如搜尋畫面）不算浮層，Esc 直接退出視窗全螢幕；輸入框有焦點的頁面也一樣。EPUB 書頁（WebView2）有焦點時 Esc 是否到得了 Dart 同樣需要實機實測（見條件 7）；2026-11-06 使用者以真實鍵盤回報可用。已知邊界：不可關閉的對話框開著時 Esc 會退出全螢幕；TTS 面板不響應 Esc。
9. **載入與生命週期：** 書籍載入中按翻頁鍵被忽略、不崩潰；離開閱讀器後按鍵處理器已移除（再按方向鍵不會對已關閉的閱讀器動作）；重新開書後只有一份處理器。
10. **Android 與其他平台不變：** 所有新增處理器與 `main.js` 轉送都只在 Windows 啟用；既有測試全綠；`pubspec.lock` 只含 `window_manager` 及其傳遞相依（`screen_retriever` 系列）的異動。
11. **人工驗證（Windows 實機，結果記入 `issue-7-report.md`）：** 條件 2 到 8 逐項實測，必須包含真實鍵盤輸入、WebView2 有焦點、直排書、PDF、有對話框時的 Esc。驗證前不得宣稱通過。

## Issue 7 單元測試要求

- `readerKeyCommandFor`：每個按鍵的對應（含 Space 與 Shift+Space）；直排時 ←／→ 鏡像、橫排不鏡像；↑／↓／PageUp／PageDown 不受直排影響；Ctrl+F 回傳開啟搜尋；Ctrl+Shift+F、Alt+←、Ctrl+→、Meta 組合回傳 `null`；無關按鍵回傳 `null`。
- `WindowFullscreenController` 相關函式（假控制器，同步 `isFullscreenNow` 快取隨 `setFullscreen` 更新）：`toggleWindowFullscreen` 目前非全螢幕則設為全螢幕、反之亦然；上一次尚未完成時再呼叫會被忽略；例外不外洩；`exitWindowFullscreenIfActive` 在快取為 `false` 時回傳 `false` 且不呼叫 `setFullscreen`，與 toggle 共用進行中旗標。
- `WindowFullscreenShortcuts`（widget test，假控制器、Windows 平台 override）：F11 在任何畫面都切換、按住不放只切換一次、帶修飾鍵不切換；Esc 在視窗全螢幕且無浮層時退出；有 dismissible 對話框時第一次 Esc 只關對話框、全螢幕維持，第二次才退出（鎖定 `DismissIntent` 覆寫機制）；不可關閉的對話框時 Esc 退出全螢幕（已知邊界）；輸入框有焦點的頁面 Esc 仍退出全螢幕（鎖定 `EditableText` 的永遠啟用動作不被當成浮層）；內層 Esc 消費者回傳 true 時不退出、回傳 false 時退出、取消註冊後不再被詢問，且有可關閉浮層時根本不詢問消費者；`handleWindowEscape` 與按鍵處理器優先序一致；不在全螢幕時 Esc 不呼叫控制器；非 Windows 或控制器為 `null` 時不攔截任何按鍵。
- `ReaderScreen` 按鍵處理器：翻頁鍵走 `_handleZoneAction`（含直排鏡像）；Home／End 呼叫 `ReaderSurface.jumpTo`（Foliate 用進度 0.0／1.0，PDF 用頁碼 0／最後一頁，PDF 頁數未就緒時忽略）並清除搜尋高亮、記錄閱讀活動；Ctrl+F 呼叫書內搜尋；路由被疊上、文字輸入框有焦點時暫停；書籍載入中、失敗、PDF 裁切模式時忽略；Esc 有選取時清除、裁切模式時吞掉、否則不消費；`KeyRepeatEvent` 也觸發；`dispose` 後處理器已移除；非 Windows 不註冊。
- EPUB 交付：方案 A 補「全域處理器在 EPUB 開著時也收到按鍵」的測試；方案 B 補去重器（不同來源 50 毫秒內只處理一次、同來源連續不去重）、`main.js` 轉送（僅 Windows 啟用、帶修飾鍵正確、`'f'` 與 `'F'` 都對應 Ctrl+F）、`logicalKeyForWebKey` 與 `FoliateReaderView` 對應回呼的測試。
- `BookSearchScreen`：Windows 上開啟後輸入框已聚焦、Ctrl+F 重新聚焦並全選、帶 Shift 或有對話框疊上時不處理、關閉後處理器已移除；非 Windows 開啟後不自動聚焦、Ctrl+F 不處理。
- 依賴：`flutter pub get` 後 `pubspec.lock` 只含 `window_manager` 與 `screen_retriever` 系列新增。

## Issue 9 範圍

Windows 啟動時檢查 WebView2 Runtime，缺少或建立環境失敗時顯示說明畫面與微軟官方下載連結，裝好後免重啟 App 直接進入。

1. **啟動鏈防護：** `main()` 在 `runApp` 之前先呼叫 `checkAndInitWebView2()`；不是 ready 時 `runApp` 一個獨立的 `WebView2MissingApp`。
2. **純邏輯解耦：** `checkAndInitWebView2` 注入 `probe` 與 `createEnvironment`，保持純 Dart 邏輯。
3. **說明畫面：** 自帶 `MaterialApp` 與 `Scaffold`，包含標題、說明內文、微軟官方下載連結、可複製網址文字（`SelectableText`）與「重新檢查」按鈕。
4. **重新檢查：** 同一時間只跑一次檢查，檢查期間按鈕停用；成功就緒後呼叫 `onReady` 進入主畫面，且保持停用防重入。
5. **多語系支援：** 支援四語系（`zh_TW`、`zh`、`zh_CN`、`en`），`zh` 嚴格鏡像 `zh_TW` 滿足一致性守衛；支援 `localeOverride` 覆寫與系統語言解析。
6. **相依套件：** 將 `url_launcher` 提升為直接相依（鎖定 `^6.3.2`，僅修改 `pubspec.lock` 之 `dependency: "direct main"`）。
7. **平台隔離：** 僅在 Windows 生效（`isWindowsPlatform`），非 Windows 平台零改動。

## Issue 9 過關條件

1. Windows 啟動時偵測不到 WebView2、或環境建立失敗／逾時，顯示說明畫面而非壞掉的閱讀器；畫面含標題、說明、下載按鈕、網址、重新檢查。
2. 「下載」開啟預設瀏覽器到微軟官方頁；開啟失敗時網址仍可選取複製。
3. 「重新檢查」成功後直接進入 App，不必重開；進行中不可重入。
4. 說明畫面語系與 App 一致（覆寫優先，否則系統）。
5. 有 WebView2 時啟動行為與現況完全相同；Android 與其他平台零改動。
6. 人工／模擬驗證：以指定空資料夾與自動化 widget 測試完整覆蓋上述條件；如實記錄「未在真正沒裝 Runtime 的乾淨機器上測過」。

## Issue 9 單元測試要求

- `checkAndInitWebView2`（假函式注入）：
  - 探測回有效版本且建立成功 → ready，version 正確，`createEnvironment` 呼叫 1 次。
  - 探測回 null → missing，`createEnvironment` 從未呼叫。
  - 探測回空字串 "" 或純空白 "   " → missing。
  - 探測丟例外 → failed，detail 含例外訊息，不向外拋出。
  - 建立環境丟例外 → failed，detail 含例外訊息。
  - 建立環境逾時（15 秒／短逾時）→ failed，detail 註明逾時，且背景 Future 補上 `.catchError` 防禦。
- `WebView2CheckResult`：值物件等值性比較（`operator ==`、`hashCode` 與 `toString`）。
- `WebView2MissingApp`（widget test）：
  - missing 狀態顯示標題、下載、重新檢查、網址文字，不顯示錯誤摘要。
  - failed 狀態額外顯示 `Key('webview2_detail_text')`。
  - 點擊下載按鈕呼叫 `openUrl`，失敗或丟例外時不崩潰且網址文字留存。
  - 重新檢查回傳 ready 觸發 `onReady` 1 次，且按鈕保持停用防止重複觸發。
  - 重新檢查回傳 missing 顯示 `Key('webview2_still_missing_text')`。
  - 重新檢查進行中連按兩次只發起 1 次檢查。
  - 重新檢查丟例外顯示錯誤狀態且按鈕恢復可點擊。
  - 多語系切換（`en`、`zh_TW`）。
- 多語系一致性：`test/l10n/arb_consistency_test.dart` 通過（四檔鍵一致、`zh` 鏡像 `zh_TW`、`en` 無漏翻）。
- 硬編碼中文字串檢查：`node tool/check_l10n_hardcoded_strings.js` 全數 PASS。

## Issue 10 範圍

Windows 版隱藏只有手機有意義的控制項，並停止呼叫 Windows 上不存在的 Android 原生 channel。

1. **統一判斷：** 新增 `supportsMobileReaderControls`（`lib/platform/platform_support.dart`），Windows 為 `false`，其他平台為 `true`。
2. **閱讀預設值畫面：** Windows 隱藏「音量鍵翻頁」開關、「螢幕方向」區塊、「全螢幕模式」開關。
3. **版面設定面板：** Windows 隱藏「螢幕方向」列與「全螢幕模式」開關（流式 `ReaderSettingsSheet`、固定版面 `FxlSettingsSheet`、`PdfSettingsSheet` 各自的全螢幕開關）。
4. **PDF 設定面板：** Windows 隱藏整個「濾鏡」分頁（對比度、亮度、加粗），分頁數由 3 變 2。
5. **E-Ink：** Windows 隱藏設定畫面的「E-Ink 高對比模式」開關；`ElinkBookApp` 啟動時一律視為關閉，即使本機殘留已開啟的值。
6. **原生 channel：** Windows 的 `ReaderScreen` 不呼叫 `elinkbook/volume_key`（`setMethodCallHandler`、`notifyLeavingReader`）、`elinkbook/fullscreen`（`setEnabled`），也不呼叫 `SystemChrome.setPreferredOrientations`。
7. **不處理：** 已存進資料庫的單書 `fullscreen`、`screenOrientationOverride`、`pdfContrast` 等值不清除，也不遷移；Windows 新安裝沒有這些值。F11 視窗全螢幕（Issue 7）不變。「關於」頁的 `elinkbook/app_info`（建置時間、WebView 版本）在 Windows 顯示錯誤文字，以及 TXT 封面直接讀 E-Ink 殘留值，都是已知限制，本 Issue 不處理。
8. **不新增字串：** 只隱藏既有控制項，不動 ARB。

## Issue 10 過關條件

1. Windows 上，閱讀預設值畫面看不到音量鍵、螢幕方向、全螢幕三項；其餘項目（翻頁模式、文字轉換、開啟上次書籍、頁首、頁尾）仍可操作。
2. Windows 上，三種版面設定面板看不到全螢幕開關；流式面板看不到螢幕方向列；PDF 面板只剩「顯示」與「裁切」兩個分頁。
3. Windows 上，設定畫面看不到 E-Ink 開關；啟動後主題永遠不是 E-Ink。
4. Windows 上進出閱讀器，不呼叫任何 `elinkbook/volume_key`、`elinkbook/fullscreen` channel，主控台沒有 `MissingPluginException`。
5. Android 與其他平台所有控制項與行為完全不變（既有測試不改一行）。
6. Windows 實機人工確認以上畫面，記錄在 `issue-10-report.md`。

## Issue 10 單元測試要求

- `supportsMobileReaderControls`：Windows 為 `false`，Android、iOS 為 `true`（`test/platform/platform_support_test.dart`）。
- `ReadingDefaultsScreen`：Windows 三個 Key 不存在、其餘 Key 存在；Android 全部存在。
- `ReaderSettingsSheet`、`FxlSettingsSheet`、`PdfSettingsSheet`：Windows 全螢幕開關不存在；流式面板的螢幕方向列不存在；Android 都存在。
- `PdfSettingsSheet`：Windows 只有 2 個分頁，切到「裁切」分頁不拋例外；Android 3 個分頁。
- `SettingsScaffold`：Windows 無 `settings_eink_mode_switch`；Android 有。
- `ElinkBookApp`：Windows 傳入 `initialEinkMode: true` 仍套用一般主題；Android 套用 E-Ink 主題。
- `ReaderScreen`：Windows 開啟再關閉後，兩個 channel 的假處理器收到 0 次呼叫；Android 仍收到。

## Issue 11 範圍

2026-11-07 診斷發現：`local_book_server_test.dart` 的隨機失敗（`Connection closed before full header was received`）不是程式錯誤。這台開發機的 `127.0.0.1` TCP 連線約 20～30% 被重設；純 Node 對純 Node 也一樣，改連 `127.0.0.2`、`::1`、區網 IP 則 0 失敗。審查補做的對照顯示：只有請求帶 `Connection: close` 時才會被重設，keep-alive 是 0 失敗。肇因（Tailscale、Hyper-V 虛擬網卡、Defender 等）尚未查明。生產程式 `LocalBookServer` 預設綁 `127.0.0.1`，WebView2（Chromium）用 keep-alive，所以是否影響 Windows 版開書尚未證實；這台機器的 Windows 版預設本來就會「開書逾時」（2026-11-07 兩次實機觀察），是否相關要用對照實驗確認。記憶中的「二次開書逾時」是 Android 症狀，與本問題無直接關係。

1. **診斷工具：** `app/tool/check_loopback_reliability.js`，對 `127.0.0.1`、`127.0.0.2`、`::1`、區網 IP 各打 N 次本機 HTTP 請求（分 `Connection: close` 與 keep-alive 兩種模式），列出成功與被重設的次數。
2. **實驗開關：** `LocalBookServer.instance` 的綁定位址可用 `--dart-define=LOCAL_BOOK_SERVER_BIND=<IP>` 指定，預設仍是 `127.0.0.1`；只接受 IPv4 loopback，無效值、非 loopback（例如 `0.0.0.0`、區網 IP）與 IPv6 一律退回預設。
3. **測試穩定：** `local_book_server_test.dart` 在 Windows 改綁 `127.0.0.2`（其他平台維持 `127.0.0.1`），讓全套測試在這台機器穩定。
4. **`pdf_reader_view_filters_test.dart`：** 嘗試重現；重現不了就記為「無法重現」，不盲目修改。
5. **乾淨基準：** 修完後跑一次全套 `flutter test`，記錄剩餘失敗，作為 Issue 6 的比對基準。
6. **開書逾時對照實驗（需人在電腦前）：** 先冒煙確認 `127.0.0.2` 版能渲染；再以交錯順序（A、B、A、B…）各冷啟動 5 次、開同一本書，另各做一輪同一次啟動連開 3 次，記錄成功與逾時、各階段耗時，寫入 `issue-11-report.md`。
7. **不處理：** 正式程式的預設綁定位址要不要改、要不要加連線重試——等實驗結果出來，另開決定。

## Issue 11 過關條件

1. `node tool/check_loopback_reliability.js` 在這台機器上，`127.0.0.1` 的 `close` 列有被重設的次數，`127.0.0.1` 的 `keepalive` 列與其餘位址各列為 0。
2. 不帶 `LOCAL_BOOK_SERVER_BIND` 時，`LocalBookServer.instance` 綁 `127.0.0.1`，行為與現況完全相同。
3. Windows 上連跑 `local_book_server_test.dart` 5 次，全部通過。
4. 其他平台的 `local_book_server_test.dart` 仍綁 `127.0.0.1`。
5. `pdf_reader_view_filters_test.dart` 有明確結論：已修，或「無法重現」並記錄嘗試次數。
6. 全套 `flutter test` 結果與剩餘失敗項目寫入報告。
7. 開書逾時實驗的次數與結果如實記錄；沒有明顯的對照差異或樣本不足時寫「不能確定」，不寫「已解決」。

## Issue 11 單元測試要求

- `LocalBookServer.bindAddressFromDefine(String)`：`'127.0.0.2'` 回傳該位址；空字串回傳 `127.0.0.1`；非 IP 字串（`'abc'`）、非 loopback（`'0.0.0.0'`、`'192.168.1.5'`）與 IPv6（`'::1'`）都回傳 `127.0.0.1`，不拋例外。
- `local_book_server_test.dart` 既有 11 個測試改用「測試綁定位址」後全數通過；`bookBaseUri.host` 的斷言改比對實際位址。
- 診斷腳本不另寫單元測試，以實際執行輸出驗證。

## Issue 6 範圍

2026-11-07 盤點發現：這台機器的共用 SDK `C:\tools\flutter` 從 2026-10-23 起就是 Flutter 3.47.4，近期工作與全套測試（5118 個，0 失敗）都在 3.47.4 上通過；`CLAUDE.md` 寫的 3.41.9 已過時。所以本 Issue 的實質工作是：把共用 SDK 升到含安全公告修補的 3.47.9，把剩下的棄用與建置問題收乾淨，並讓政策文件對齊現況。使用者決定（2026-11-07）直接升級共用的 `C:\tools\flutter`。

1. **升級共用 SDK 到 3.47.9**（用 `flutter upgrade --force`，**從專案外的目錄執行**，否則第二階段會把 `pubspec.lock` 整個升級；執行前用 `git ls-remote` 確認 `stable` 就是 3.47.9，升級後確認鎖檔沒變；`C:\tools\flutter` 有 119 筆 untracked，不加 `--force` 會被拒；不要用 `git checkout` 到標籤，會讓 HEAD detached）。3.47.8 含安全公告 GHSA-frr6-h895-5pxp（Dart 執行環境的 BoringSSL 封鎖被入侵的 eMudhra 中繼 CA 憑證；Android、Windows、Linux 應用升級後重新建置）；3.47.6 修正 Windows 正式版 App 卡死。回退點是 `9584c6713b`（3.47.4），回退用 `git reset --hard`（留在 `stable` 分支），需要網路重新下載引擎；`C:\src\flutter-3.41.9` 保留不刪。
2. **回歸基準：** 只換 SDK、不改程式，先跑 `flutter pub get`、`flutter analyze`、全套 `flutter test`，與 3.47.4 基準（5118 個、0 失敗、2 個 info）比對。
3. **`onReorder` → `onReorderItem`：** 只有 `dictionary_settings_screen.dart` 一處；行為不變，既有 5 個拖曳測試（全是把 `c` 往前拖）不改斷言，另補 3 個「往後拖」測試（拖到最後一格、往後一格、原地放開）。
4. **Windows 建置不再需要手動設 `CL=/utf-8`：** 在 `windows/CMakeLists.txt` 為 MSVC 加 `/utf-8`；先重現失敗，再驗證修好；若在 3.47.9 已不需要，則記錄後略過。
5. **`desktop_drop` 維持 0.8.4，不在本 Issue 升級（2026-11-07 使用者決定）。** 0.9.x 要求 `cross_file ^0.4.0`（破壞性更新），與 `file_picker`、`share_plus`、`share_plus_platform_interface`（含它們的最新版）要求的 `cross_file ^0.3.x` 衝突，`pub get` 解析失敗；唯一的路是 vendor 修補三個套件。本 Issue 只在 `pubspec.yaml` 加原因註解，並在 `issues.md` 登記 **Issue 16（`cross_file` 0.4 遷移）**，不排程。不做 Issue 16 也不會壞任何東西：0.8.4 沒有缺我們需要的功能，官方支援 `cross_file` 0.4 後可用一般方式升級。
6. **建置驗證：** `flutter build apk --debug`（沒有 Android 裝置，只到建置成功；AGP 8.11.1、Kotlin 2.3.20、Gradle 8.14 的警告逐條記錄）與 `flutter build windows --debug`。
7. **Windows 實機確認（需人在電腦前）：** 3.47.9 的 Windows debug 版冷啟動 5 次、自動還原上次的書，記錄成功與耗時；另請使用者實機拖曳匯入（單檔、多檔、資料夾、不支援格式、匯入中再拖），確認 `desktop_drop` 0.8.4 在新 SDK 與引擎上沒有回歸。
8. **政策文件：** 更新 `CLAUDE.md` 的 Flutter 版本段落、`epic.md` 新增決策 28、撰寫 `issue-6-report.md`。
9. **不處理：** `pdfrx` 2.4.7→2.12.0、`file_picker` 11→13、`window_manager` 0.5.2→0.6.0（大跳版）；`sqflite`、`url_launcher`（只差 patch）；AGP 9／built-in Kotlin 遷移；Android 真機驗證；`desktop_drop` 0.9 升級（Issue 16）。

## Issue 6 過關條件

1. `flutter --version` 顯示 3.47.9，`flutter doctor` 的 Android、Windows、Visual Studio 仍為 ✓；回退指令寫在報告。
2. 只換 SDK 時，`pub get` 無鎖檔變動、`flutter analyze` 只有 2 個 info、全套 `flutter test` 5118 個 0 失敗；有差異就逐項記錄。
3. 全專案 `flutter analyze` 只剩 `use_null_aware_elements` 這 1 個 info（`onReorder` 棄用消失）。
4. 詞典拖曳排序的結果與現況完全相同（既有 5 個拖曳測試不改斷言，加新增 3 個「往後拖」測試，共 8 個通過）。
5. 沒有 `CL` 環境變數時 `flutter build windows --debug` 成功；設了 `CL=/utf-8` 時也成功。（或報告記載該問題已不存在。）
6. `desktop_drop` 維持 0.8.4，`pubspec.yaml` 有原因註解，`pubspec.lock` 完全不變，Issue 16 已登記；`import_drop_target_test.dart`、`adaptive_shell_scaffold_test.dart` 在 3.47.9 上全過；Windows 實機拖曳（單檔、多檔、資料夾、不支援格式、匯入中再拖）使用者回報通過。
7. `flutter build apk --debug` 成功，警告清單寫進報告；報告不得寫「Android 已驗證」，只能寫「建置成功」。
8. Windows 開書冒煙 5 次的結果如實記錄（用語限定為「冷啟動開書 5／5」，不外推）；全套 `flutter test` 5121 個（基準 5118 加 Task 3 的 3 個）0 失敗。
9. `CLAUDE.md` 的 Flutter 版本為 3.47.9，且不再有「`onReorderItem` 在 3.41.9 不存在」的警告。

## Issue 6 單元測試要求

- `dictionary_settings_screen_test.dart`：既有 5 個拖曳測試（全是把 `c` 往前拖）不改斷言並全過；新增 `往後拖曳（第一個拖到最後一格）後 reorder 傳入 [b, c, a]`、`往後拖曳一格後 reorder 傳入 [b, a, c]`、`原地放開（位移很小）不呼叫 reorder`，且三者在 `onReorder` 版本上必須先通過。
- `import_drop_target_test.dart`、`adaptive_shell_scaffold_test.dart`：不改程式與測試，在 3.47.9 上必須全過（`desktop_drop` 維持 0.8.4）。
- 建置與冒煙驗證（`CL`、Android、Windows 開書）以實際執行輸出驗證，不另寫單元測試。

## Issue 12 範圍（階段一）

**狀態：** 🟢 已完成並合併（2026-11-09，PR #405）

Android 讀 EPUB 的書名、作者、識別碼、是否固定版面、封面，改成預設用 foliate-js（與 Windows 同一支 `metadata-probe.js`），Readium 留作「foliate-js 失敗時的退路」。使用者決定（2026-11-08）：對比用 **App 書庫內的書**；**分兩階段**，本 Issue 是階段一，**不移除 Readium**，移除另立 Issue 18。

1. **Android 讀書檔區段（含 `content://`）：** `ReaderResourceChannel.kt` 新增 `contentUriLength`（`statSize` 小於 0 時補查 `OpenableColumns.SIZE`）、`readContentUriRange`（上限 4 MB，不整本讀入，每次呼叫以 `pfd.use` 關閉檔案描述元）；純函式 `clampByteRange` 有 JVM 單元測試；Dart 端 `book_range_reader.dart` 以 `startsWith('content://')` 分流，`file://` 轉本機路徑。
2. **Android 版探針：** `android_epub_metadata.dart` 的 `readEpubMetadataOnAndroid`，沿用索引器的 Android 背景 WebView 寫法（`loadAndroidAsset`、`esCompatPolyfillJs`、`globalErrorCaptureJs`），逾時 30 秒；註冊 `onError` handler 讓載入階段的 JS 錯誤立刻失敗；書檔區段讀取失敗一律回明確的 404（不拋例外、不回 `null`）；不改 `windows_epub_metadata.dart`。
3. **派送函式與旗標：** `extractAndroidBookMetadata`；`kAndroidMetadataFoliateFirst`（實作時先為 `false`，經使用者同意後於 Task 6 改為 `true`）；foliate-js 失敗時 `debugPrint` 原因並退回 Readium；PDF 等非 EPUB 一律走原生通道；foliate 路徑包在 `runSerialized` 內，同一時間只有一個背景探針 WebView；Readium 退路的通道引數為 `uri` 與 `format`；`main.dart` 在 Android 傳入此函式。
4. **書庫對比測試（唯讀）：** 純函式 `diffBookMetadata` 加 `integration_test/library_metadata_comparison_test.dart`：在手機上用 `openReadOnlyDatabase` 讀 `library.db` 的 EPUB，對每本直接呼叫 Readium 通道與 foliate-js 探針（不經派送函式），印出每本的差異與耗時，並斷言書庫至少有 1 本 EPUB（避免假綠）、測試前後 `library.db` 大小與修改時間不變。
5. **在 WAVE 上執行對比；BooksPad 由使用者視連線狀況執行。** 手機操作一律先備份資料庫、`adb install -r`、不解除安裝、測完還原正常版本。
6. **關卡：** 對比結果給使用者看，**使用者同意**才把旗標改為 `true`；否則維持 `false` 並記錄原因。
7. **報告與文件：** `issue-12-report.md`、`epic.md` 決策 29、登記 Issue 18（階段二）。
8. **不處理：** 移除 Readium 相依、`extractEpubMetadata`；`detectEpubLayout`（既有書籍回填，仍走 Readium）；Android release 版驗證；封面位元組是否逐位元相同（只比「有沒有」）。

## Issue 12 過關條件

1. 旗標為 `false` 時（切換前與日後退回時），Android 匯入、重新選取、回填的行為與現況完全相同（foliate-js 探針不啟動）。
2. WAVE 上的書庫對比：EPUB 逐本比對 `title`、`author`、`identifier`、`isFixedLayout`、封面有無；**`identifier` 有任何不一致就視為不通過**；沒有「只有 foliate-js 失敗」；結果與每本耗時寫入報告。兩邊都失敗的書（例如權限已收回）單獨列出，不算不一致。
3. 對比測試前後 `library.db` 的大小與修改時間相同；測試後 App 已還原為正常 debug 版並能啟動到書架。
4. 切換預設需**使用者明確同意**；若 BooksPad 未能連線，報告明講「只有 WAVE 的結果」，由使用者決定是否切換。
5. 切換後（若同意）：使用者在 WAVE 匯入 1～2 本 EPUB（含有封面與版面特殊的各一），書名、作者、封面正確；日誌顯示走的是 foliate-js 而非退回 Readium。
6. Readium 相依與 `extractEpubMetadata`、`detectEpubLayout` 仍在；Issue 18 已登記。
7. 報告不得外推：只有 WAVE（與可能的 BooksPad）上的結果，debug 版，非 release。

## Issue 12 單元測試要求

- `ByteRangeTest`（Kotlin JVM）：正常區段、`end` 超過長度被夾回、`start` 為負回傳 `null`、`start >= length` 回傳 `null`、`end <= start` 回傳 `null`、超過上限回傳 `null`、`start=0, end=5 MB, length=1 MB, maxBytes=4 MB` 回傳 `null`（先檢查原始區段大小）、`start=0, end=3 MB, length=1 MB` 回傳 `0 until 1 MB`。
- `book_range_reader_test.dart`：本機路徑讀區段與內容一致、`end` 夾回、`start` 越界回傳 `null`；`content://` 走通道帶對參數、通道回傳 `null` 時回傳 `null`、通道例外往外拋；`bookLength` 本機與 `content://` 各一；`file://` 網址轉本機路徑讀取、不走通道。
- `android_epub_metadata_test.dart`：`mapProbeResult` 有封面、沒封面、壞 base64、缺 `isFixedLayout`（預設 `false`）、缺 `title`／`author`／`identifier`；`androidProbeHtml` 含大小、兩個 handler 名稱與探針腳本路徑；`interceptBookRange` 讀取成功回傳資料，`readRange` 回 `null`、丟例外、缺 `start`／`end` 都回 404（且不往外拋）。
- `android_book_metadata_test.dart`：旗標關閉只走 Readium；旗標開啟 foliate 成功不呼叫 Readium；foliate 失敗退回 Readium 並有日誌；PDF 一律走原生；兩邊都失敗時把 Readium 的例外往外拋；兩次同時呼叫 foliate 路徑時依序執行；Readium 退路的通道引數鍵為 `uri` 與 `format`；（切換後）預設旗標為 `true`。
- `metadata_comparison_test.dart`：相同、`title`／`identifier`／`isFixedLayout` 不同各回傳對應欄位、前後空白與 `null`／空字串視為相同、封面有無不同回傳 `cover`、封面位元組不同但都有視為相同、空位元組陣列視為沒有封面。
- 手機上的書庫對比與切換後的匯入冒煙，以實際執行輸出驗證，不另寫單元測試。

## Issue 13 範圍

**狀態：** 🟢 已合併（PR #406、#407，2026-11-10；見 [issue-13-report.md](issue-13-report.md)；僅本機、debug 版、本機 WebView2；Android 僅一台 BooksPad 部分驗證，見報告第 8 節）

在 Windows 上用 `flutter test integration_test/… -d windows` 跑出一組可重複、依序執行的冒煙測試，涵蓋每種格式（EPUB 流式、EPUB 固定版面、PDF、TXT、MD、CBZ、AZW3）的「開書、翻頁、劃線」。不建 CI。2026-11-09 基準線：27 支現有整合測試單獨依序在 Windows 跑過，20 支通過、8 支失敗（詳見計畫）；因此多半是沿用與診斷，不是從零寫。

1. **跑測腳本與套件清單：** `app/tool/run_windows_smoke.ps1` 與 `app/integration_test/windows_smoke_suite.txt`；一次只准一份、逐支依序、跑前確認沒有殘留行程且記憶體足夠。
2. **診斷「無法載入書籍」：** FXL 翻頁、目錄頁尾、PDF 各一；分「測試假設 Android／Windows 產品問題／時序」三類，產品問題在改程式前先告知使用者。
3. **診斷畫面找不到 widget：** 目錄、劃線備註、`reader_screen_test`；不要求全數修好，未修好的列為已知缺口。
4. **Android 專屬測試的平台守門：** 只在 `Platform.isWindows` 時略過並寫明原因，不刪測試。
5. **補矩陣空格：** TXT、MD、AZW3 的翻頁與（預先寫入的）劃線顯示。
6. **完整依序執行、報告與文件。**
7. **不處理：** 建 CI；Windows release 版與乾淨機器；使用者在畫面上實際選字劃線（WebView 內手勢無法由 Flutter 驅動，只驗證預先寫入的標記能顯示）；未修好的 `reader_screen_test` 項目（另立 Issue）。

## Issue 13 過關條件

1. `windows_smoke_suite.txt` 內每一支測試，在乾淨環境下由 `run_windows_smoke.ps1` 依序執行一次全數通過，輸出附在報告。
2. 格式 × 動作矩陣每一格都有對應的 Windows 通過測試，或明寫「不適用／已知缺口」與原因（CBZ 劃線不適用）。
3. 8 個失敗檔案每一個都有診斷結論（A／B／C 類）與處理結果；沒修好的不在清單內，並登記後續 Issue。
4. 跑測腳本證明會拒絕並行與殘留行程（三個實際執行輸出）。
5. Android 專屬測試在 Windows 顯示略過且附原因；Android 上的行為沒有改變（程式審查確認）。
6. 報告不得外推：只有這台機器、debug 版、本機 WebView2；沒有乾淨機器、沒有 release。

## Issue 13 單元測試要求

- 跑測腳本與整合測試本身沒有單元測試框架；以實際執行輸出為證。
- `test/`（不需裝置）：檢查 `integration_test/` 內所有 `skipOnWindows(` 呼叫都帶有非空原因字串，且沒有裸的 `skip: Platform.isWindows`（`testWidgets` 的 `skip` 只收 `bool?`，原因字串改由 `skipOnWindows` helper 強制必填）。
- 新增的整合測試須先做一次變異驗證（暫時讓翻頁或劃線失效，確認測試變紅，再還原）。

## Issue 14 範圍

**狀態：** 🟢 已完成實作與自動化驗證（2026-11-10；見 [issue-14-report.md](issue-14-report.md)；僅代表本機開發環境與 Release 建置，乾淨機器與 Windows 10 1809 嚴格標記為未驗證；使用者手動開書待確認）

用一支腳本把 Windows release 版打成**免安裝 zip**：解壓到任何位置（含空格、中文、唯讀資料夾）雙擊 `elinkbook.exe` 就能用。決策 10：先自用；MSIX、程式碼簽章、自動更新不在本 Epic。

已查證的事實（2026-11-10，計畫階段）：
- `elinkbook.exe` 與外掛 DLL 動態依賴 `MSVCP140.dll`、`VCRUNTIME140.dll`、`VCRUNTIME140_1.dll`（`dumpbin /dependents`）。沒裝「Visual C++ 可轉散發套件」的乾淨 Windows 會直接跳「缺少 DLL」。使用者決定（2026-11-10）：**打包進 zip**（app-local 部署），來源是 Visual Studio Build Tools 的 `VC\Redist\MSVC\<版本>\x64\Microsoft.VC143.CRT`。
- 現有 Release 輸出（2026-11-05 舊版）含 `elinkbook.exe`、`flutter_windows.dll`、`pdfium.dll`、`sqlite3.dll`、`Webview2Loader.dll`、各外掛 DLL 與 `data\`（內含 `foliate\`、約 95 MB）；打包時一律重新建置。
- WebView2 使用者資料夾已指定到 `getApplicationSupportDirectory()`（`main.dart:500`，決策 23）；解壓到唯讀位置是否真的不寫入，由本 Issue 驗證。
- 乾淨機器驗證：使用者**沒有**另一台電腦或虛擬機（2026-11-10），所以只在本機驗證，乾淨機器、Windows 10 1809 一律「未驗證」，不外推。

1. **打包腳本：** `app/tool/package_windows_zip.ps1`——重新 `flutter build windows --release`、在暫存目錄組裝、複製三個 VC DLL（用 `vswhere` 找 Redist）、放入 README、壓成 zip、產生 SHA256。輸出到 `app/build/windows_zip/`（不進版控）。
2. **依賴靜態檢查：** 對暫存目錄每個 `.exe`／`.dll` 用 `dumpbin /dependents`，非系統 DLL 的依賴必須在目錄內，且三個 VC DLL 必須在目錄內；缺任何一個則失敗。
3. **內容規範：** 不含 `.pdb`／`.lib`／`.exp`／`.ilk`；必含 `data\foliate\`、`data\flutter_assets\`、README；zip 內路徑分隔符一律 `/`。
4. **README（正體中文）：** 需求（Windows 10 1809 以上、WebView2 Runtime）、可解壓到任何位置、資料存放位置、未簽章時 SmartScreen 的提示與解除封鎖方法、移除方式。
5. **本機驗證腳本：** `app/tool/verify_windows_zip.ps1`——解壓到「含空格與中文」且「唯讀」的資料夾、啟動、確認行程存活與主視窗出現、資料寫在使用者資料夾而非解壓資料夾。
6. **人工開書確認：** 在解壓出來的 release 版開一本 EPUB（使用者回報結果）。
7. **不處理：** MSIX、簽章、自動更新、上傳 GitHub Release、乾淨機器與 Windows 10 1809 驗證、安裝程式（Inno Setup 等）、zip 之外的格式。

## Issue 14 過關條件

1. 腳本可重複產生 `elinkbook-<版本>-windows-x64.zip` 與同名 `.sha256`；同一提交連續打兩次，zip 內**檔案清單**一致（不要求位元組相同）。
2. 依賴靜態檢查通過；**變異驗證**：從暫存目錄移除任一 VC DLL 時檢查必須失敗。
3. zip 內沒有除錯檔、有 `data\foliate\main.js`、有 README；路徑分隔符皆為 `/`。
4. 解壓到含空格與中文的路徑且資料夾唯讀：啟動後行程存活至少 20 秒、有主視窗；當次啟動確實有檔案寫入使用者資料夾（`LastWriteTime` 不早於啟動時間；此機器上該資料夾早已存在，單看「存在」沒有意義）；腳本啟動時明確指定工作目錄為程式資料夾；解壓資料夾在執行前後檔案清單相同（沒有新增檔）。
5. 使用者在解壓版 release 開一本 EPUB 成功並回報。
6. 報告不得外推：只有這台機器、release 版、本機 WebView2；乾淨機器（缺 VC 執行階段）、Windows 10 1809、SmartScreen 實際行為、他人電腦皆明寫「未驗證」。
7. 工作樹乾淨：`pubspec.lock`、`app/windows/flutter/generated_plugin_registrant.*`、`generated_plugins.cmake` 不得 commit；`git add` 明確列檔。

## Issue 14 單元測試要求

- 腳本類沒有單元測試框架；以實際執行輸出為證，記入報告。
- 依賴檢查須做一次變異驗證（移除一個 VC DLL，確認失敗，再還原）。
- 沒有 Dart 變動時 `flutter analyze` 須維持乾淨；發 PR 前跑一次完整 `flutter test`。

## 後續 Issue（待 Issue 1 結果決定）

- ~~生產級送書伺服器~~：Issue 1 實測攔截可行（決策 15），不做。大檔整本位元組尖峰（224 MB 書約 3.8 GB）若要改善，另開「分段服務」Issue；洩漏驗證見 Issue 3。
- ~~檔案匯入與資料夾匯入~~（已納入 Issue 5，上方有完整設計；原註記：取 `f.identifier ?? f.path`；資料夾用 `getDirectoryPath()` 加 `dart:io`，不寫原生 channel；`Book.filePath` 存本機路徑。）
- ~~鍵盤快捷鍵與 F11~~（已納入 Issue 7，上方有完整設計；`window_manager` 0.5.2 已確認不依賴 `win32`）。
- 平台專屬功能的隱藏（已登錄為 Issue 10）。
- Windows 版 `integration_test` 冒煙測試（已登錄為 Issue 13）。
- ~~免安裝 zip 打包~~（已納入 Issue 14，見 [issue-14-report.md](issue-14-report.md)）。
- **`desktop_drop` 0.9 與 `cross_file` 0.4 遷移（已登錄為 Issue 16，2026-11-07，不排程）。**
  - 阻礙：`cross_file` 0.4.0 是破壞性更新（移除 `XFile(String path)`、`XFile.path`、`XFile.mimeType`、`XFile.fromData`，`XFile.name` 變非同步）。`desktop_drop` 0.9.x、`file_picker`、`share_plus`、`share_plus_platform_interface` 目前都依賴 `cross_file ^0.3.x`；`file_picker` 最新 13.3.2、`share_plus` 最新 13.3.1 也還沒支援 0.4，所以升版解決不了，`pub get` 解析失敗（Issue 6 審查時以 `pub get --dry-run` 確認）。
  - 已知做法：vendor 修補三個套件，用 `dependency_overrides` 指向 `patches/`（先例：`patches/flutter_inappwebview_android`、`third_party/dict_reader`）。`file_picker` 11.0.3 的 `platform_file.dart` 之 `xFile` 取值（約 5 行，專案沒用到 `xFile`／`xFiles`）；`share_plus_platform_interface` 6.1.0 的 `method_channel_share.dart`（`.path`、`.mimeType`、`.name`、`XFile(path)`，約 15～20 行）；`share_plus` 11.1.0 只有 web 版檔案用到舊 API，只需改 pubspec 約束。專案內 `notes_bottom_sheet.dart:194` 的 `XFile(path, mimeType: 'text/markdown')` 改為 `XFile.fileSystem(path:)`（0.4 沒有 `mimeType`，Markdown 的 mimeType 要由修補後的套件依副檔名推斷或明確傳入）。
  - `import_drop_target.dart` 改寫成 0.9 的 API：`onDragDone(DropDoneDetails)` → 必要的非同步 `onDrop(DropDetails)`、`files` → `items`（`DropFileItem`／`DropDirectoryItem`／`DropStringItem`，`localPath` 可為 null）、`enable` → `enabled`、`onDragEntered/Exited` → `onEnter/onLeave`。**provider 與暫存檔只在 `onDrop` 期間有效，整段匯入必須在 `onDrop` 回傳的 Future 內完成。** 測試需先呼叫 `CrossFileIO.registerWith()`，`DropDirectoryItem` 需帶 `XDirectory.fileSystem(path:)`；`import_drop_target_test.dart` 約 6 個有對話框或擱置匯入的測試，不能直接 `await onDrop(...)`，要先取 Future、`pump`、再等。
  - 風險：Android 分享的 mimeType 行為會變、沒有 Android 裝置可驗證、長期維護修補；`cross_file` 0.4 會多拉進 `cross_file_android` 等外掛。
  - 出路與影響：官方 `file_picker`、`share_plus` 支援 `cross_file` 0.4 後，可用一般方式升級，不需要修補。**不做 Issue 16 也不會壞任何東西**：`desktop_drop` 0.8.4 沒有缺我們需要的功能（0.9 新增的是 iOS／Android 拖曳與虛擬檔案支援）。唯一的小風險是 0.9.1 修過一個只在部分 Flutter 引擎出現的 Windows 啟動崩潰，Issue 6 的 Windows 冷啟動冒煙會偵測 3.47.9 引擎是否受影響。
- **Android 建置工具升級（已登錄為 Issue 17，2026-11-08，不排程）。**
  - 現況：`flutter build apk --debug` 在 3.47.9 上成功，但印出兩條警告：Flutter 對專案 Gradle 版本 8.14.0 的支援「即將移除」，要求 ≥ 9.1.0；對 AGP 8.11.1 的支援「即將移除」，要求 ≥ 9.0.1。可用 `--android-skip-build-dependency-validation` 略過。專案目前：AGP 8.11.1、Kotlin 2.3.20、Gradle 8.14（`android/settings.gradle.kts`、`android/gradle/wrapper/gradle-wrapper.properties`），`gradle.properties` 有 `android.builtInKotlin=false`、`android.newDsl=false`。
  - 注意：Issue 6 審查時曾判斷這些版本「在支援範圍內」，那只是「目前還能建置」；Flutter 已明確預告會移除支援。
  - 風險：沒有 Android 裝置驗證；`patches/flutter_inappwebview_android` 本機修補、各外掛的 Kotlin 套用邏輯（built-in Kotlin）都可能受影響；這是 Android 第一次在 3.47.x 上建置，升到 AGP 9 後要重新驗證。
- **Android 移除 Readium 相依與清理（已登錄為 Issue 18，2026-11-09，階段二）。**
  - 背景：Issue 12 在 WAVE（7 本）與 BooksPad（103 本商業實體書）共 110 本真實 EPUB 逐欄對比，foliate-js 與 Readium 達到 100% 一致無任何差異，且耗時中位數無實質差異（1.70s vs 1.58s）。計畫原訂「先觀察一個版本再移除」；2026-11-09 使用者決議改為階段二直接拔除、不保留退路（決議後仍保留 Issue 12 階段一的退路直到階段二上線）。注意：WAVE 上 foliate-js 比 Readium 慢約 5 倍，拔除前應重新評估。
  - 範圍：
    1. 移除 `app/android/app/build.gradle.kts` 中的 `readium-shared` 與 `readium-streamer` 原生依賴。
    2. 移除 `BookMetadataChannel.kt` 或簡化為僅保留非 EPUB/必要之通道。
    3. 移除 `extractAndroidBookMetadata` 中的 Readium 退路邏輯，Android 與 Windows EPUB 詮釋資料抽取完全統一走 `readEpubMetadataOnAndroid` / foliate-js 探針。
    4. 移除 `extractEpubMetadata` 原生方法與相關宣告。
    5. 將既有書籍回填 `detectEpubLayout` 改由 foliate-js 探針抽取。
    6. 清理 `third_party_licenses`、更新專案文件與架構說明。
  - 狀態：已登錄，不排程。
- **`reader_screen_test` 在 Windows 整份中斷（已登錄為 Issue 19，2026-11-10，不排程）。**
  - 現象：未修改的 `HEAD` 在這台機器上，第一支測試結束後 App 結束（exit 79），其餘 18 支 `did not complete`；單獨跑第 1、2 支皆通過。Issue 13 初版報告所稱「9／19 通過」在這台機器上無法重現，原因未查明，因此此檔不在套件清單內。
  - 已排除：儲存閱讀位置時資料庫已關閉（診斷輸出沒有該例外）、測試端重複關庫。
- **桌面寬度 TOC 目前章節判定（已登錄為 Issue 20，2026-11-10，不排程）。** 見上方 Issue 表。
- **Android 上數支整合測試仍有失敗（已登錄為 Issue 21，2026-11-10，不排程）。**
  - 現象（BooksPad，螢幕常亮，debug 版，各跑一次）：`epub_toc_test` 第 2 支找不到 `TocBottomSheet`；`epub_highlights_notes_test` 找不到「已編輯的純備註」；`reader_screen_test` 5 項失敗（逐項未診斷）。
  - 已排除：400x800 視窗覆寫（拿掉後更差）、手機螢幕熄滅（螢幕常亮重跑）。
  - 注意：跑 Android 整合測試前，手機螢幕必須保持亮著（否則 WebView 不繪製、開書逾時）；`app/android/gradle.properties:5` 寫死舊電腦的 JDK 路徑，換電腦需裝同版本 JDK 17。
- 索引器跑不完（Issue 8，已合併 #400）、WebView2 缺少提示（Issue 9，已合併 #401）、測試穩定性（Issue 11，已合併 #403）、Android 統一 metadata（Issue 12，已完成）：2026-11-06 登錄。
- **預定執行順序：** ~~8~~ → ~~9~~ → ~~10~~ → ~~11~~ → ~~6~~ → ~~12~~ → ~~13~~ → ~~14~~（先補齊功能，再升級 Flutter，冒煙測試與打包放在最終版本上做）。全部 Issue 皆已完成或實作完畢。
- 不做：「分段服務」（大檔開書記憶體尖峰，224 MB 書約 3.8 GB），記為已知限制，遇到再議。
- Flutter 升級（Issue 6）：先用 `flutter pub outdated` 與 `pub get --dry-run` 盤點；升級後 `desktop_drop` 可改用最新版；一併處理 `pubspec.lock` 與 Flutter 版本的落差；Windows 預設 Impeller 下重驗 WebView2 閱讀器；`onReorder` 改 `onReorderItem`；built-in Kotlin／AGP 9 的 Android 建置；先查 3.47.8 的安全公告再選修補版本；升級前須與人類確認（`CLAUDE.md`）。
