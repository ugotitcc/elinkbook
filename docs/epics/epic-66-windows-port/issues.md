# Epic 66 — Windows 版移植：工單清單 (Issues)

設計依據是 `epic.md`「Discovery 決策」。Issue 1 過關後，才展開後續 Issue。

| Issue | 標題 | 依賴 | 狀態 | PR |
|---|---|---|---|---|
| 1 | 技術驗證：啟用 `windows/`、啟動鏈平台防護、最小送書原型，確認 7 項過關條件，輸出驗證報告 | 無 | ✅ 已合併 | #381 |
| 2 | Windows Metadata 背景解析：EPUB 用 foliate-js、PDF 封面用 `pdfrx`，並與 Android Readium 逐本對比 | Issue 1 | 🟡 計畫中 | — |

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
3. 解析失敗（損毀 EPUB、逾時）不中斷匯入：退回檔名為標題、無封面；不留下孤兒封面檔與快取目錄。
4. Android 行為不變：既有測試全綠，`main.dart` 在 Android 不注入 Windows 解析器。
5. 產出 Readium 與 foliate-js 的逐本對比表（同一批 fixture，Android 實機跑 Readium，Windows 跑 foliate-js），`identifier` 不一致的逐一列出；依結果修訂 `epic.md` 決策 7。
6. 讀 224 MB EPUB 的 metadata 時，記下 App 與 WebView2 的尖峰記憶體，與開書的 3.8 GB 比較。

## Issue 2 單元測試要求

- `readBookMetadata()`（JS，Puppeteer 測試台）：每份 fixture 的欄位期望值；書名為語系物件時取第一個值；作者為字串、物件、陣列三種形態都取第一位的名稱；缺 `identifier`、缺封面回 `null`；固定版面回 `true`。
- `renderPdfCover()`：回 PNG 簽章 `89 50 4E 47`；最長邊不超過 600；不存在的檔案回 `null`。
- `extractWindowsBookMetadata()`：依 `format` 分派（`epub`／`pdf`）；其他格式回 `null`；EPUB 解析逾時時釋放 WebView 並刪除快取目錄。
- `BookImportServiceImpl`（注入假解析器）：解析結果的 `title`／`author`／`isFixedLayout`／`identifier` 進入 `Book`；封面落地成 `<bookId>.png`；指紋採用 `identifier`；解析器丟 `PlatformException` 時降級；未注入解析器時走原有 channel 路徑（Android 不變）。
## 後續 Issue（待 Issue 1 結果決定）

- ~~生產級送書伺服器~~：Issue 1 實測攔截可行（決策 15），不做。大檔整本位元組尖峰（224 MB 書約 3.8 GB）若要改善，另開「分段服務」Issue。
- 檔案匯入與資料夾匯入：取 `f.identifier ?? f.path`；資料夾用 `getDirectoryPath()` 加 `dart:io`，不寫原生 channel；`Book.filePath` 存本機路徑。
- 鍵盤快捷鍵與 F11（先確認 `window_manager` 與 `win32` 5.15.0 相容）。
- 平台專屬功能的隱藏。
- Windows 版 `integration_test` 冒煙測試。
- 免安裝 zip 打包。
