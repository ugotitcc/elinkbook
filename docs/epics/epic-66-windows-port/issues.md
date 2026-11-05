# Epic 66 — Windows 版移植：工單清單 (Issues)

設計依據是 `epic.md`「Discovery 決策」。Issue 1 過關後，才展開後續 Issue。

| Issue | 標題 | 依賴 | 狀態 | PR |
|---|---|---|---|---|
| 1 | 技術驗證：啟用 `windows/`、啟動鏈平台防護、最小送書原型，確認 7 項過關條件，輸出驗證報告 | 無 | ✅ 已合併 | #381 |
| 2 | Windows Metadata 背景解析：EPUB 用 foliate-js、PDF 封面用 `pdfrx`，並與 Android Readium 逐本對比 | Issue 1 | ✅ 已合併 | #384 |
| 3 | 閱讀器開書與全文索引器的「整本回傳」記憶體：驗證是否洩漏，洩漏則修正（來源 Issue 2 審查發現） | Issue 2 | ✅ 已合併（量測確認閱讀器洩漏，修法移至 Issue 4） | #396 |
| 4 | Windows 書檔改由本機 loopback HTTP 伺服器（`shelf`）服務，消除「整本回傳」洩漏（來源 Issue 3 報告） | Issue 3 | ✅ 已合併 | #397 |

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

## 後續 Issue（待 Issue 1 結果決定）

- ~~生產級送書伺服器~~：Issue 1 實測攔截可行（決策 15），不做。大檔整本位元組尖峰（224 MB 書約 3.8 GB）若要改善，另開「分段服務」Issue；洩漏驗證見 Issue 3。
- 檔案匯入與資料夾匯入：取 `f.identifier ?? f.path`；資料夾用 `getDirectoryPath()` 加 `dart:io`，不寫原生 channel；`Book.filePath` 存本機路徑。
- 鍵盤快捷鍵與 F11（先確認 `window_manager` 與 `win32` 5.15.0 相容）。
- 平台專屬功能的隱藏。
- Windows 版 `integration_test` 冒煙測試。
- 免安裝 zip 打包。
