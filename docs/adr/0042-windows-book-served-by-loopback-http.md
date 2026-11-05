# ADR 0042：Windows 版書檔改由本機 Loopback HTTP 伺服器服務，取代 shouldInterceptRequest

## 狀態

已採納（2026-11-06）。對應 `epic-66-windows-port` Issue 4。

## 背景

在 Android 上，大型書籍本體透過原生 `androidx.webkit.WebViewAssetLoader`（`InternalStoragePathHandler`）串流服務，避免全檔讀入記憶體（見 [ADR 0018](0018-webviewassetloader-streaming-for-large-epub.md)）。

但在 Windows 上，`flutter_inappwebview_windows` 不支援 `WebViewAssetLoader`。`epic-66` Issue 1 移植時採用 `InAppWebView.shouldInterceptRequest` 攔截 `/book/` 請求並以 `WebResourceResponse(data: bytes)` 整本回傳。

Issue 3 建立 Windows 記憶體量測體系後發現嚴重洩漏：在同一 App 程序中，每次開啟 224 MB 大檔 EPUB，`elinkbook.exe` 的私有記憶體（Private Bytes）便永久上升約 452 MB（4 輪開關累計上升 +1808 MB），即使卸載 Widget、關閉 WebView、手動觸發 GC 皆無法回落，4 次開關即因記憶體耗盡而崩潰。

經 Issue 3 隔離實驗證實，根因為 WebView2 C++ 外掛層在處理 `shouldInterceptRequest` 回傳的位元組緩衝區時未能妥善釋放 COM 物件／`IStream`，洩漏量與經由該通道傳輸的資料量成正比。

## 決策

1. **引入輕量本機 Loopback HTTP 伺服器（`LocalBookServer`）**：
   以純 Dart 套件 `shelf` 與 `shelf_io` 實作本機 HTTP 伺服器，僅綁定 IPv4 本機迴路位址 `127.0.0.1`，作業系統動態配置隨機連接埠（`port: 0`），於首次開書註冊時惰性啟動並常駐於 App 生命週期中。
2. **只搬書檔，不搬 Foliate 靜態資源與字型**：
   `index.html` 仍維持載入於 `https://appassets.androidplatform.net/assets/foliate/index.html`，保留既有 origin 安全環境與 CSP 設定；Foliate 靜態腳本、樣式與字型檔體積小且未發生記憶體洩漏，維持既有自訂攔截或資產載入，不引入全站 HTTP 服務的攻擊面。
3. **Foliate `main.js` 動態基底網址（`bookBaseUrl`）**：
   修改 `assets/foliate/main.js` 的 `openBook()`，優先讀取 query 參數 `bookBaseUrl`（例如 `http://127.0.0.1:<port>/book/<token>/`）。若未提供該參數則回退至原有的 `https://appassets.androidplatform.net/book/`。Android 端與既有行為逐字相同、完全相容。
4. **安全隔離（隨機權杖、Host 標頭、CORS 與私有網路）**：
   - 每本書註冊時由 `Random.secure()` 產生具備至少 128 位元亂數熵的 URL-safe 權杖，路徑格式為 `/book/<token>/<fileName>`。
   - 伺服器嚴格比對 HTTP `Host` 標頭，必須完全等於 `127.0.0.1:<port>`，拒絕任何非 loopback 或偽造之 Host 請求（回傳 403 Forbidden）。
   - CORS 標頭（含預檢 `OPTIONS` 與 Private Network Access `Access-Control-Allow-Private-Network: true`）僅允許信任來源（`https://appassets.androidplatform.net`、`http://127.0.0.1:<port>`、`null`）。
   - 回應一律帶 `Cache-Control: no-store`，禁止瀏覽器磁碟與記憶體快取。
5. **HTTP Range 串流與主動中止**：
   - 實作 `parseByteRange` 解析單一 Range 請求（`bytes=start-end`、`bytes=start-`、`bytes=-suffix`），以 `206 Partial Content` 或 `200 OK` 透過 `File.openRead()` 串流回傳，絕不將整檔讀入記憶體。
   - 當書籍關閉（`BookServeHandle.dispose()`）時，除將權杖從註冊表移除外，立即以 `SocketException` 中止進行中的資料串流，確保釋放 Windows 檔案控制代碼（file handle），避免快取檔案鎖定無法刪除。
6. **索引器（`FoliateContentIndexer`）同步改接**：
   將內容索引器的 URL 組裝抽取為 `buildIndexerUri(Book book, {Uri? bookBaseUri})`，Windows 端建立 Headless 索引時同樣經由 `LocalBookServer.register` 服務，於 `finally` 區塊確保 `dispose()`。

## 替代方案與取捨

- **選項 B：在 `shouldInterceptRequest` 內實作 HTTP Range 攔截**：被否決。Issue 3 原型實驗顯示，即使將傳輸拆分為小分塊，每次跨 FFI/C++ 傳遞位元組緩衝區仍會成比例累積未釋放記憶體，無法根除洩漏。
- **選項 C：修改／修補 `flutter_inappwebview_windows` 外掛 C++ 底層**：被否決。外掛內部 COM 參照計數與 WebView2 事件機制交織，排查與維護 vendor patch 成本高昂且升級脆弱。
- **選項 D：使用 WebView2 原生虛擬網域映射（`SetVirtualHostNameToFolderMapping`）**：被否決。此 API 需直接操作原生 C++ WebView2 物件或修改外掛底層，無法以純 Dart 實作，且需處理虛擬網域跨來源與磁碟路徑安全性問題。

## 後果

- **記憶體洩漏徹底根除**：
  - Debug 整合測試（`reader_leak_test.dart -d windows`）：5 輪開關 224 MB 大檔 EPUB，4 次迭代私有記憶體增量為 `[6.99, 0.53, 2.92, -0.54] MB`，快取目錄殘留為 0，正式加入 `expect(verdict.leaked, isFalse)` 回歸斷言。
  - Release 實測（`probe_main.dart`）：4 次迭代增量為 `[4.17, -1.00, 5.01, 0.03] MB`，4 輪累積增量僅 +8.21 MB（對比原先 +1808 MB），`ratcheting=false`。
- **維護平台分流**：
  - Android：維持原生 `WebViewAssetLoader`。
  - Windows：使用 `LocalBookServer` loopback HTTP 串流服務。
- **新增依賴**：
  - `shelf: ^1.4.2`、`shelf_io: ^1.0.5` 正式納入 `app/pubspec.yaml`。
