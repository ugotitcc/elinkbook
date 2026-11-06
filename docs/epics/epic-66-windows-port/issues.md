# Epic 66 — Windows 版移植：工單清單 (Issues)

設計依據是 `epic.md`「Discovery 決策」。Issue 1 過關後，才展開後續 Issue。

| Issue | 標題 | 依賴 | 狀態 | PR |
|---|---|---|---|---|
| 1 | 技術驗證：啟用 `windows/`、啟動鏈平台防護、最小送書原型，確認 7 項過關條件，輸出驗證報告 | 無 | ✅ 已合併 | #381 |
| 2 | Windows Metadata 背景解析：EPUB 用 foliate-js、PDF 封面用 `pdfrx`，並與 Android Readium 逐本對比 | Issue 1 | ✅ 已合併 | #384 |
| 3 | 閱讀器開書與全文索引器的「整本回傳」記憶體：驗證是否洩漏，洩漏則修正（來源 Issue 2 審查發現） | Issue 2 | ✅ 已合併（量測確認閱讀器洩漏，修法移至 Issue 4） | #396 |
| 4 | Windows 書檔改由本機 loopback HTTP 伺服器（`shelf`）服務，消除「整本回傳」洩漏（來源 Issue 3 報告） | Issue 3 | ✅ 已合併 | #397 |
| 5 | Windows 檔案與資料夾匯入：選檔、選資料夾、拖曳三種方式，書檔維持原路徑，不支援格式略過並提示 | Issue 4 | ✅ 已合併（Windows 人工驗證待補） | #398 |
| 6 | Flutter 升級至 ≥ 3.47.7（評估與遷移）：`onReorder` 棄用、built-in Kotlin／AGP 9、Windows 預設 Impeller、外掛相容 | Issue 5 | ⚪ 未開始（尚未規劃） | — |
| 7 | Windows 鍵盤快捷鍵與 F11 視窗全螢幕：翻頁類按鍵、Ctrl+F、F11，Esc 依序處理浮層與全螢幕 | Issue 5 | 🟡 實作完成，待 Windows 人工驗證 | — |

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
- **未確認的關鍵風險：** WebView2 取得焦點時，按鍵會進 Flutter 還是被網頁吞掉（連 F11 都可能收不到）。由第一個 Task 實測。

**做法：**

1. **Task 1 實測（不產出正式程式）：** 在 Windows 上實測 WebView2 有焦點時，方向鍵、Space、Home、End、Ctrl+F、F11、Esc 各進哪一邊，結論記入 `issue-7-report.md`，決定 EPUB 走「A：Flutter 全域按鍵處理器就夠」或「B：`main.js` 轉送按鍵給 Dart」。
2. **純邏輯：** `readerKeyCommandFor(key, shift, control, alt, meta, verticalWriting)` 把按鍵對應成 `ReaderKeyCommand`（上一頁、下一頁、首頁、末頁、開啟搜尋）；直排時 ←／→ 鏡像；帶 Ctrl／Alt／Meta 的組合除了 Ctrl+F 一律不處理。
3. **視窗全螢幕：** `WindowFullscreenController` 介面加 `window_manager` 0.5.2 實作；只在 Windows 初始化；`WindowFullscreenShortcuts` 掛在 `MaterialApp.builder`：F11 用全域 `HardwareKeyboard` 處理器（任何畫面、不依賴焦點）；Esc 不手動攔截，改在 builder 層以 `Actions` 覆寫 `DismissIntent`，由 Flutter 從焦點往上找第一個啟用中的動作，對話框先、「退出視窗全螢幕」後（手動攔截會搶在 `WidgetsApp` 把 Esc 轉成 `DismissIntent` 之前，讓對話框關不掉）。控制器維護同步可讀的 `isFullscreenNow` 快取（`Action.isEnabled` 必須同步回答），連按 F11 以進行中旗標避免競態。
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
7. **F11：** 在書架、來源、設定、閱讀器、EPUB 與 PDF 閱讀中都能切換視窗全螢幕（包含 WebView2 有焦點時）；切換畫面或離開閱讀器不會重置全螢幕；重新啟動 App 回到一般視窗；連按 F11 不亂。
8. **Esc：** 有對話框或面板時先關它、視窗全螢幕維持；閱讀器內有文字選取時先清除選取、PDF 手動裁切模式中只吞掉（不退出裁切、不退出全螢幕），視窗全螢幕維持；沒有任何內層狀態且在視窗全螢幕時退出全螢幕；沒有內層狀態也不在全螢幕時，閱讀器**不會**返回書架。已知邊界：不可關閉的對話框開著時 Esc 會退出全螢幕；TTS 面板不響應 Esc。
9. **載入與生命週期：** 書籍載入中按翻頁鍵被忽略、不崩潰；離開閱讀器後按鍵處理器已移除（再按方向鍵不會對已關閉的閱讀器動作）；重新開書後只有一份處理器。
10. **Android 與其他平台不變：** 所有新增處理器與 `main.js` 轉送都只在 Windows 啟用；既有測試全綠；`pubspec.lock` 只含 `window_manager` 及其傳遞相依（`screen_retriever` 系列）的異動。
11. **人工驗證（Windows 實機，結果記入 `issue-7-report.md`）：** 條件 2 到 8 逐項實測，必須包含真實鍵盤輸入、WebView2 有焦點、直排書、PDF、有對話框時的 Esc。驗證前不得宣稱通過。

## Issue 7 單元測試要求

- `readerKeyCommandFor`：每個按鍵的對應（含 Space 與 Shift+Space）；直排時 ←／→ 鏡像、橫排不鏡像；↑／↓／PageUp／PageDown 不受直排影響；Ctrl+F 回傳開啟搜尋；Ctrl+Shift+F、Alt+←、Ctrl+→、Meta 組合回傳 `null`；無關按鍵回傳 `null`。
- `WindowFullscreenController` 相關函式（假控制器，同步 `isFullscreenNow` 快取隨 `setFullscreen` 更新）：`toggleWindowFullscreen` 目前非全螢幕則設為全螢幕、反之亦然；上一次尚未完成時再呼叫會被忽略；例外不外洩；`exitWindowFullscreenIfActive` 在快取為 `false` 時回傳 `false` 且不呼叫 `setFullscreen`，與 toggle 共用進行中旗標。
- `WindowFullscreenShortcuts`（widget test，假控制器、Windows 平台 override）：F11 在任何畫面都切換、按住不放只切換一次、帶修飾鍵不切換；Esc 在視窗全螢幕且無浮層時退出；有 dismissible 對話框時第一次 Esc 只關對話框、全螢幕維持，第二次才退出（鎖定 `DismissIntent` 覆寫機制）；不可關閉的對話框時 Esc 退出全螢幕（已知邊界）；不在全螢幕時 Esc 不呼叫控制器；非 Windows 或控制器為 `null` 時不攔截任何按鍵。
- `ReaderScreen` 按鍵處理器：翻頁鍵走 `_handleZoneAction`（含直排鏡像）；Home／End 呼叫 `ReaderSurface.jumpTo`（Foliate 用進度 0.0／1.0，PDF 用頁碼 0／最後一頁，PDF 頁數未就緒時忽略）並清除搜尋高亮、記錄閱讀活動；Ctrl+F 呼叫書內搜尋；路由被疊上、文字輸入框有焦點時暫停；書籍載入中、失敗、PDF 裁切模式時忽略；Esc 有選取時清除、裁切模式時吞掉、否則不消費；`KeyRepeatEvent` 也觸發；`dispose` 後處理器已移除；非 Windows 不註冊。
- EPUB 交付：方案 A 補「全域處理器在 EPUB 開著時也收到按鍵」的測試；方案 B 補去重器（不同來源 50 毫秒內只處理一次、同來源連續不去重）、`main.js` 轉送（僅 Windows 啟用、帶修飾鍵正確、`'f'` 與 `'F'` 都對應 Ctrl+F）、`logicalKeyForWebKey` 與 `FoliateReaderView` 對應回呼的測試。
- `BookSearchScreen`：Windows 上開啟後輸入框已聚焦、Ctrl+F 重新聚焦並全選、帶 Shift 或有對話框疊上時不處理、關閉後處理器已移除；非 Windows 開啟後不自動聚焦、Ctrl+F 不處理。
- 依賴：`flutter pub get` 後 `pubspec.lock` 只含 `window_manager` 與 `screen_retriever` 系列新增。

## 後續 Issue（待 Issue 1 結果決定）

- ~~生產級送書伺服器~~：Issue 1 實測攔截可行（決策 15），不做。大檔整本位元組尖峰（224 MB 書約 3.8 GB）若要改善，另開「分段服務」Issue；洩漏驗證見 Issue 3。
- ~~檔案匯入與資料夾匯入~~（已納入 Issue 5，上方有完整設計；原註記：取 `f.identifier ?? f.path`；資料夾用 `getDirectoryPath()` 加 `dart:io`，不寫原生 channel；`Book.filePath` 存本機路徑。）
- ~~鍵盤快捷鍵與 F11~~（已納入 Issue 7，上方有完整設計；`window_manager` 0.5.2 已確認不依賴 `win32`）。
- 平台專屬功能的隱藏。
- Windows 版 `integration_test` 冒煙測試。
- 免安裝 zip 打包。
- Flutter 升級（Issue 6）：先用 `flutter pub outdated` 與 `pub get --dry-run` 盤點；升級後 `desktop_drop` 可改用最新版；一併處理 `pubspec.lock` 與 Flutter 版本的落差；Windows 預設 Impeller 下重驗 WebView2 閱讀器；`onReorder` 改 `onReorderItem`；built-in Kotlin／AGP 9 的 Android 建置；先查 3.47.8 的安全公告再選修補版本；升級前須與人類確認（`CLAUDE.md`）。
