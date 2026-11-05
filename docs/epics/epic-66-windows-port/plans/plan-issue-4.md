# Epic 66 Issue 4：Windows 書檔改由本機 loopback HTTP 伺服器服務 實作計畫

> **給執行計畫的代理：** 必須使用 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans 逐 Task 執行。步驟用 `- [ ]` 追蹤。

**Goal：** 消除 Windows 閱讀器開書時 `shouldInterceptRequest` 整本回傳造成的 `elinkbook.exe` 私有記憶體永久上升（Issue 3 實證：每次開關約 +452 MB，debug／Release 皆是）。做法是讓書檔改由 App 內的 loopback HTTP 伺服器（`shelf`）以串流與 HTTP Range 服務，不再經過外掛的 `WebResourceResponse`。

**Architecture：** 新增純邏輯 `parseByteRange`、書檔 HTTP 處理器（shelf `Handler`）與 `LocalBookServer`（綁 `127.0.0.1`、隨機埠、每本書一個隨機權杖）。`main.js` 新增 `bookBaseUrl` 查詢參數，**未帶時維持原網址**；只有 Windows 帶入伺服器網址。頁面、foliate 資源、字型仍走既有攔截，頁面 origin 不變（`https://appassets.androidplatform.net`），伺服器對該 origin 回 CORS。Android 完全不變。

**Tech Stack：** Dart／`shelf`（已在 `pubspec.yaml`）、`dart:io` `HttpServer`／`HttpClient`、foliate-js `main.js`、Windows 整合測試（`-d windows`）。

**Spec：** 沒有獨立 spec。權威依據是 `issues.md` 的「Issue 4 範圍／過關條件／單元測試要求」、`issue-3-report.md`（尤其 §3、§5、§7.1）與 `epic.md` 決策 6、15、18。

## Global Constraints

- **語言：** 文件、註解、測試名稱一律正體中文；程式碼命名維持英文慣例。
- **Android 不變：** `main.js` 未帶 `bookBaseUrl` 時的書檔網址必須與現狀逐字相同（`https://appassets.androidplatform.net/book/<bookFileName>`）；Android 不起伺服器；不改 `InternalStoragePathHandler` 設定。
- **只搬書檔：** 不動 foliate 資源與字型的攔截路徑；不動 Issue 2 的 metadata 解析器（它有自己的 Range 攔截）。
- **伺服器安全底線：** 只綁 loopback；權杖用 `Random.secure()` 產生至少 128 位元；只服務已註冊的檔案，路徑由「權杖 → 註冊表」查得，不接受任何使用者提供的檔案路徑；`Host` 必須是 `127.0.0.1:<實際埠>`；CORS 只回指定 origin（不可用 `*`）；`Cache-Control: no-store`。
- **串流：** 一律 `File.openRead(start, end)` 串流，**不得把整檔讀成 `Uint8List`**（這正是洩漏的來源）。
- **Windows 環境：** 多數原始檔是 CRLF，Edit 的定位字串不要含換行；不要對整個既有檔案跑 `dart format`；`git add` 一律明確列檔；不要用 `python`（本機只有 Windows 商店空殼），腳本用 `node`。
- **Windows 整合測試：** 一次只跑一個檔。Bash：`cd app && export MSYS2_ENV_CONV_EXCL=CL CL=/utf-8 && flutter test integration_test/windows_leak/<檔名> -d windows`；PowerShell：`cd app; $env:MSYS2_ENV_CONV_EXCL='CL'; $env:CL='/utf-8'; flutter test integration_test/windows_leak/<檔名> -d windows`。跑完用 `git status` 確認 `pubspec.lock`、`windows/flutter/generated_plugin*` 沒被順帶改動（有就還原）。
- **測試範圍（`CLAUDE.md`）：** 單一 Task 只跑異動觸及的測試檔；完整 `flutter test` 只在最後一個 Task 跑一次，`run_in_background`。
- **提交前：** `flutter analyze` 必須 `No issues found!`；跑 `node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`。
- **Commit：** 每個 Task 一個 commit；推送前由使用者確認。

## 已決策（使用者已確認）

1. **索引器納入本 Issue（Task 7）。** 端到端驗證受 Headless 卡住問題阻擋，僅驗證到單元測試與 URL 組裝，並在報告明載「端到端待該問題解決」。
2. **權杖放 URL 路徑。** `bookBaseUrl` 本身含權杖，`main.js` 只做字串相接；不採 Cookie。
3. **自訂字型的攔截洩漏只量測、不搬**（Task 8 記錄數據，是否搬移另議）。

## Review Focus

1. **混合內容（HTTPS 頁面載入 `http://127.0.0.1`）**：Chromium 視 `127.0.0.1` 為可信來源而放行，但 WebView2 的實際行為與 `fetch` 的 CORS 預檢必須實測。→ Task 1 閘門。若被擋，整個方案要改成「連頁面也由伺服器服務」，範圍變大，必須停下與使用者討論。
2. **洩漏真的消失**：不能只看單元測試；以 Issue 3 的同一支 `reader_leak_test` 與 Release 迴圈量測。→ Task 1、Task 8。
3. **權杖與生命週期**：離開畫面、開書中途離開、同書連開兩次，權杖與快取目錄都要正確釋放。→ Task 3、5。
4. **Range 語意**：`foliate-js`／瀏覽器可能發 `Range: bytes=0-`、`bytes=N-`、尾端範圍；`HEAD`；預檢 `OPTIONS`。→ Task 2。
5. **死碼清理**：`readWindowsBookBytes`／`windowsBookContentType`／`/book/` 攔截分支在改接後是否真的無人使用；`integration_test/windows_spike/headless_metadata_test.dart` 仍引用，不可誤刪。→ Task 5。
6. **不要在這個 Issue 偷渡**：索引器 rAF 卡住、WebView 端 `fetch→Blob` 的分段載入、前兩輪的一次性額外增量，都不在範圍。

---

## 檔案結構

| 檔案 | 動作 | 職責 |
|---|---|---|
| `app/lib/reader/byte_range.dart` | 建立 | 純函式 `parseByteRange`：解析 `Range` 標頭 |
| `app/lib/reader/local_book_handler.dart` | 建立 | shelf `Handler`：權杖查表、Host／方法檢查、Range／CORS／串流 |
| `app/lib/reader/local_book_server.dart` | 建立 | `LocalBookServer`：啟動／關閉、`register`／`dispose`、產生網址 |
| `app/android/app/src/main/assets/foliate/main.js` | 修改 | `openBook()` 的書檔網址改讀 `bookBaseUrl` 參數（預設值不變） |
| `app/lib/reader/foliate_reader_view.dart` | 修改 | Windows：註冊書檔、`_buildIndexUri` 帶 `bookBaseUrl`、dispose 釋放；移除 `/book/` 攔截分支 |
| `app/lib/reader/foliate_native_bridge.dart` | 修改（Task 5） | 新增共用純函式 `foliateBookBaseUrlParams`（閱讀器與索引器共用） |
| `app/lib/search/foliate_content_indexer.dart` | 修改（Task 7） | 同上；`_buildIndexUri` 改為頂層 `buildIndexerUri` 以便單測 |
| `app/lib/reader/windows_reader_resources.dart` | 視情況修改 | 移除確定無人使用的書檔位元組讀取函式 |
| `app/test/reader/byte_range_test.dart` | 建立 | 範圍解析單元測試 |
| `app/test/reader/local_book_handler_test.dart` | 建立 | 處理器單元測試（不開 socket） |
| `app/test/reader/local_book_server_test.dart` | 建立 | 真實 loopback socket 測試 |
| `app/integration_test/windows_leak/reader_leak_test.dart` | 修改 | 修法後改為斷言 `leaked == false` |
| `docs/adr/0042-windows-book-served-by-loopback-http.md` | 建立 | 架構決策紀錄 |
| `docs/epics/epic-66-windows-port/{epic.md,issue-4-report.md}` | 修改／建立 | 決策補註與驗證報告 |

---

### Task 1：拋棄式原型與量測閘門（不進版控）

**目的：** 在寫任何正式程式之前，用最少的程式驗證兩件事：(a) HTTPS 頁面能從 `http://127.0.0.1:<port>` 取得書並正常開書（混合內容／CORS）；(b) 洩漏確實消失。**這個 Task 的程式碼全部拋棄，只留數據。**

**做法：**
- 暫時修改 `main.js` 的 `openBook()`，讀 `params.get('bookBaseUrl')`，有值就用它組書檔網址。
- 暫時在 `foliate_reader_view.dart` 的 Windows 分支起一個最簡 `dart:io` `HttpServer`（綁 loopback、埠 0、回 `Access-Control-Allow-Origin: https://appassets.androidplatform.net`、支援 `Range`、串流 `File.openRead`），把 `bookBaseUrl` 帶入 `_buildIndexUri`。權杖、Host 檢查、清理都不做。

- [x] **Step 1：** 實作上述暫時修改（先用 `git stash` 或獨立分支確保能乾淨還原）。
- [x] **Step 2：** 跑 `reader_leak_test.dart -d windows`（debug）。**閘門 A：** 能開書（`onPageRendered` 被呼叫）、4 次迭代每次增量 < 11.23 MB。
- [x] **Step 3：** 以暫時的 Release 進入點重跑（範本與建置指令見**附錄 A**；`flutter drive`／`flutter run integration_test/...` 在 Release 不可行）。**閘門 B：** 同樣低於門檻。
- [x] **Step 4：** 手動目視確認：開 EPUB 可翻頁、選字出現劃線工具列。
- [x] **Step 5：** 還原所有暫時修改（`git checkout -- <檔案>`、刪除暫時進入點），把數據摘要記在 `issue-4-report.md` 草稿（Task 8 補完）。
- **停點：** 閘門 A 或 B 不過 → **停下**，向使用者報告（可能是混合內容被擋、或洩漏另有他因），不進入 Task 2。

---

### Task 2：`parseByteRange`（純 Dart，TDD）

**Files：**
- Create：`app/lib/reader/byte_range.dart`
- Test：`app/test/reader/byte_range_test.dart`

**Interfaces：**
- Produces：`ByteRangeResult parseByteRange(String? header, int fileLength)`，其中結果為三態：`full`（無 Range 或不支援的形式 → 回整檔 200）、`partial(start, end)`（含頭尾，已截斷到檔尾）、`unsatisfiable`（416）。

- [x] **Step 1：寫失敗測試**，涵蓋：
  - `null`／空字串 → `full`。
  - `bytes=0-99`、`bytes=100-`（到檔尾）、`bytes=-500`（尾端 500 位元組；大於檔案則整檔）。
  - `end` 超過檔尾 → 截斷為 `fileLength-1`。
  - `start >= fileLength` → `unsatisfiable`；`bytes=-0` → `unsatisfiable`。
  - `start > end`、`bytes=abc`、非 `bytes` 單位（`items=0-1`）→ `full`（忽略無效標頭，符合 RFC 9110 對無法解析者的寬容處理）。
  - 多段範圍 `bytes=0-1,5-6` → `full`。
  - `fileLength == 0` 時任何範圍 → `unsatisfiable`，無 Range → `full`。
- [x] **Step 2：** `flutter test test/reader/byte_range_test.dart`，確認失敗。
- [x] **Step 3：** 實作。
- [x] **Step 4：** 重跑通過；`flutter analyze`。
- [x] **Step 5：** commit。

---

### Task 3：書檔 HTTP 處理器（shelf Handler，TDD，不開 socket）

**Files：**
- Create：`app/lib/reader/local_book_handler.dart`
- Test：`app/test/reader/local_book_handler_test.dart`

**Interfaces：**
- Consumes：`parseByteRange`（Task 2）。
- Produces：`Handler createLocalBookHandler({required Map<String, RegisteredBook> registry, required String Function() expectedHost, required String allowedOrigin})`。`RegisteredBook` 含 `filePath`、`fileName`、`contentType`。請求路徑固定為 `/book/<token>/<fileName>`。

**行為：**
- 方法：`GET`、`HEAD`、`OPTIONS`；其餘 405（附 `Allow`）。
- `Host` 標頭 ≠ `expectedHost()` → 403（防 DNS rebinding）。
- 權杖不在 registry、或 `<fileName>` 與註冊值不符 → 404（不洩漏是哪一種）。
- 檔案在處理當下不存在 → 404。
- `OPTIONS`：回 204，標頭為 `Access-Control-Allow-Origin: <allowedOrigin>`、`Access-Control-Allow-Methods: GET, HEAD, OPTIONS`、`Access-Control-Allow-Headers: Range`、`Access-Control-Allow-Private-Network: true`（預檢若帶 `Access-Control-Request-Private-Network`，Chromium 的 Private Network Access 檢查需要它；無害，一律回）、`Access-Control-Max-Age: 86400`、`Vary: Origin`。**標頭名稱必須有 `Access-Control-` 前綴**（`Allow`／`Allow-Methods` 不是 CORS 標頭，缺了預檢會被瀏覽器直接拒絕）。
- `GET`／`HEAD` 成功：`Accept-Ranges: bytes`、`Content-Type`、`Cache-Control: no-store`、`Access-Control-Allow-Origin: <allowedOrigin>`、`Access-Control-Expose-Headers: Content-Length, Content-Range, Accept-Ranges`、`Vary: Origin`；`full` → 200 + `Content-Length`；`partial` → 206 + `Content-Range: bytes s-e/len` + 對應 `Content-Length`；`unsatisfiable` → 416 + `Content-Range: bytes */len`。`HEAD` 不帶本文。
- 本文為 `File.openRead(start, end + 1)` 的串流，不得整檔讀入記憶體。
- **所有回應（含 403、404、405、416）都無條件附 `Access-Control-Allow-Origin: <allowedOrigin>` 與 `Vary: Origin`**；否則瀏覽器會把錯誤狀態碼包成不透明的 `TypeError: Failed to fetch`，無法診斷。
- **權杖釋放時主動中止進行中的串流（I-2）：** `RegisteredBook` 帶一個 `Future<void> disposed`（由 `dispose()` 完成）。本文串流不直接回傳 `File.openRead(...)`，而是以 `StreamController` 轉送並監聽 `disposed`：一旦完成就 `cancel()` 底層訂閱並關閉控制器，確保檔案 handle 同步釋放（Windows 上有開啟中的 handle 會讓 `Directory.deleteSync` 失敗）。

- [x] **Step 1：寫失敗測試**（以 `Handler(Request('GET', Uri.parse('http://127.0.0.1:1234/book/<token>/current.epub'), headers: {...}))` 直接呼叫，用暫存檔當書）：涵蓋上述每一條行為；另加：位元組內容與原檔指定區段逐位元組相同（含 `0-0`、檔尾單位元組、整檔）；`Content-Length` 與實際串流長度相符；本文是串流（以 `Response.read()` 逐塊讀取驗證，不依賴一次性 `List<int>`）。
- [x] **Step 2：** `flutter test test/reader/local_book_handler_test.dart`，確認失敗。
- [x] **Step 3：** 實作。
- [x] **Step 4：** 重跑通過；`flutter analyze`。
- [x] **Step 5：** commit。

---

### Task 4：`LocalBookServer`（真實 loopback socket，TDD）

**Files：**
- Create：`app/lib/reader/local_book_server.dart`
- Test：`app/test/reader/local_book_server_test.dart`

**Interfaces：**
- Consumes：`createLocalBookHandler`（Task 3）。
- Produces：
  - `class LocalBookServer { static final instance; Future<BookServeHandle> register(String filePath); Future<void> close(); }`
  - `class BookServeHandle { final Uri bookBaseUri; /* 例如 http://127.0.0.1:53211/book/<token>/ */ final String fileName; void dispose(); }`；`dispose()` 除了移出 registry，還要完成該書的 `disposed` Future，**主動中止所有進行中的串流並釋放檔案 handle**（見 Task 3）
  - 伺服器**惰性啟動**（第一次 `register` 才 `HttpServer.bind(InternetAddress.loopbackIPv4, 0)`），之後常駐到 `close()`（App 結束）。`dispose()` 把權杖從 registry 移除，**不**關伺服器。
  - 可注入的 `Random`（測試用）與可替換的綁定位址（僅測試用）。

- [x] **Step 1：寫失敗測試**：
  - 啟動後 `server.address.isLoopback == true`；埠 ≠ 0。
  - `register` 後以 `HttpClient` 取整檔與 `Range` 區段，位元組與原檔一致；`Range: bytes=-N` 亦然。
  - `dispose` 後同網址回 404；其他已註冊權杖不受影響。
  - **串流中途 `dispose`：** 以大檔開始讀取、收到第一塊後呼叫 `dispose()`，之後 `File.delete()`（Windows 上有開啟 handle 會失敗）必須成功；用戶端看到串流被中斷。
  - 測試用 `HttpClient` 一律設 `request.persistentConnection = false`，`tearDown` 呼叫 `client.close(force: true)`，避免殘餘 socket 讓暫存檔無法刪除（M-3）。
  - 同一檔案註冊兩次得到不同權杖。
  - 權杖長度與字元集下限（至少 128 位元的 URL-safe 編碼）；連續註冊 1000 次無重複。
  - 錯誤 `Host`（以 `HttpClient` 手動覆寫 `Host` 標頭）回 403。
  - `close()` 後連線被拒；再次 `register` 會重新啟動（便於測試隔離）。
  - 並行 `register` 只會綁定一次埠（不可起兩個伺服器）。
- [x] **Step 2：** `flutter test test/reader/local_book_server_test.dart`，確認失敗。
- [x] **Step 3：** 實作。
- [x] **Step 4：** 重跑通過；`flutter analyze`。
- [x] **Step 5：** commit。

---

### Task 5：`main.js` 與 `FoliateReaderView` 改接（Windows）

**Files：**
- Modify：`app/android/app/src/main/assets/foliate/main.js`（`openBook()`）
- Modify：`app/lib/reader/foliate_reader_view.dart`
- Modify（視 grep 結果）：`app/lib/reader/windows_reader_resources.dart`
- Test：`app/test/reader/foliate_reader_view_test.dart`（沿用既有，補 URL 組裝斷言）

**行為：**
1. `main.js`：`let bookBase = params.get('bookBaseUrl') || 'https://appassets.androidplatform.net/book/'`；`if (!bookBase.endsWith('/')) bookBase += '/'`（防禦性正規化，預設值本來就有結尾斜線，不影響 Android）；`makeBook(bookBase + (params.get('bookFileName') || 'current.epub'))`。**未帶參數時結果必須與現狀逐字相同。**
2. `foliate_reader_view.dart`：Windows 在 `cacheWindowsBook` 成功後 `LocalBookServer.instance.register(cachedPath)`，保存 `BookServeHandle`。**`_initialIndexUri` 由 `late final Uri x = _buildIndexUri()` 改為 `Uri?` 欄位，在 `_cacheBook()` 完成 `register` 後於 `setState` 內與 `_bookCacheDir` 一起明確賦值**（`_buildIndexUri(_serveHandle?.bookBaseUri)`），`build()` 守衛改為 `_bookCacheDir == null || _initialIndexUri == null` 時回 `SizedBox.shrink()`。（現行唯一存取點在 `build()` 守衛之後，不會誤讀；這是消除「欄位初值被提早求值而永久快取錯誤網址」這類脆弱性的加固。）`dispose` 順序：先 `handle.dispose()`（中止串流、釋放 handle），再刪快取目錄。**現行 `cacheDir.deleteSync(recursive: true)` 沒有 try／catch**——Windows 檔案鎖定時會丟 `FileSystemException`，使 `detachReaderView()` 等後續清理被跳過，所以要包 try／catch，失敗時以 `Future.delayed(100ms)` 非同步重試（最多 3 次）。開書中途離開（`!mounted`）也要釋放。
3. 移除 `_shouldInterceptRequest` 中 Windows 的 `/book/` 分支（`FoliateRequestKind.book` 在 Windows 回 `null`，維持 Android 行為）。
4. **死碼清理（surgical）：** `grep -rn "readWindowsBookBytes\|windowsBookContentType" app/lib app/test app/integration_test`。若僅剩單元測試與 `integration_test/windows_spike/headless_metadata_test.dart` 引用，**保留函式**，只移除閱讀器內的呼叫；若連它們都不再使用才刪除（含對應測試）。

- [ ] **Step 0（共用純函式，I-4）：** 在 `app/lib/reader/foliate_native_bridge.dart`（已有 `cacheFileExtension`）新增 `Map<String, String> foliateBookBaseUrlParams(Uri? bookBaseUri)`：`null` → 空 map；非 `null` → `{'bookBaseUrl': bookBaseUri.toString()}`。閱讀器（Task 5）與索引器（Task 7）的 URL 組裝都只呼叫 `params.addAll(foliateBookBaseUrlParams(...))`；兩者其餘參數本來就不同（閱讀器有 `prefs`／`fontFaceCss`／定位，索引器只有 `mode=index`），**不強行合併成單一 URL 建構函式**。
- [ ] **Step 1：寫失敗測試**：`foliateBookBaseUrlParams` 兩種輸入（放 `test/reader/foliate_native_bridge_test.dart`）；閱讀器 URL 組裝（把 `_buildIndexUri` 改成接受 `Uri? bookBaseUri` 的可測形式）有 `bookBaseUri` 時帶 `bookBaseUrl` 且值以 `/book/` 結尾、含權杖，無時不帶且其餘參數與現狀相同。
- [ ] **Step 2：** `flutter test test/reader/foliate_reader_view_test.dart`，確認失敗。
- [ ] **Step 3：** 實作 `main.js` 與 Dart 改接；`node tool/check_foliate_es_compat.js`（確認沒引入新 API）。
- [ ] **Step 4：** 測試通過；`flutter analyze`。
- [ ] **Step 5：** commit。

---

### Task 6：Windows 實機驗證與洩漏斷言

**Files：**
- Modify：`app/integration_test/windows_leak/reader_leak_test.dart`

- [ ] **Step 0：** `reader_leak_test.dart` 的快取殘留斷言改成最多輪詢 2 秒（每 100 ms 檢查一次）再判定，容許 Windows 檔案系統延遲釋放；仍未清空才失敗。
- [ ] **Step 1：** 跑 `reader_leak_test.dart -d windows`（debug）。**期望：** 4 次增量皆 < 11.23 MB、`leaked=false`、`book_cache` 本輪新增殘留為 0。
- [ ] **Step 2：** 把檔尾的 `[leak-verdict]` 區塊加上 `expect(verdict.leaked, isFalse, reason: …)`（移除「修法完成前刻意不斷言」註解），重跑通過。
- [ ] **Step 3：** 以附錄 A 的 Release 進入點重跑，記錄數據（量測完刪除 `probe_main.dart` 與 `probe_release_result.log`）。
- [ ] **Step 4：** 手動功能驗收（過關條件 3）：EPUB 直排／橫排、翻頁、選字與劃線工具列、目錄跳轉、CBZ 固定版面；同書連開兩次；開書中途離開。
- [ ] **Step 5：** 數據存 `docs/epics/epic-66-windows-port/assets/issue-4-*.log`；`flutter analyze`；commit。

---

### Task 7：索引器改接（已決策納入）

**Files：**
- Modify：`app/lib/search/foliate_content_indexer.dart`
- Test：既有索引器測試都在 `integration_test/`（需裝置）。把索引器的 `_buildIndexUri(book)` 改為頂層函式 `buildIndexerUri(Book book, {Uri? bookBaseUri})`（標註 `@visibleForTesting`），內部只多一行 `params.addAll(foliateBookBaseUrlParams(bookBaseUri))`，共用函式已在 Task 5 完成，此處只消費；單元測試放 `app/test/search/foliate_index_uri_test.dart`

- [ ] **Step 1：** 寫失敗測試：`buildIndexerUri` 有 `bookBaseUri` 時帶 `bookBaseUrl`，無時與現狀逐字相同（`bookFileName`、`mode=index`）。
- [ ] **Step 2：** 實作：Windows 在 `cacheBookForServing` 之後 `register`，`finally` 內 `dispose`；移除 `interceptIndexRequest` 的 Windows `/book/` 分支。
- [ ] **Step 3：** 測試通過；`flutter analyze`。**注意：** 端到端（`indexer_leak_test`）仍因 Headless 卡住無法驗證，報告需明載。
- [ ] **Step 4：** commit。

---

### Task 8：ADR、文件與報告

**Files：**
- Create：`docs/adr/0042-windows-book-served-by-loopback-http.md`
- Create：`docs/epics/epic-66-windows-port/issue-4-report.md`
- Modify：`epic.md`（決策 6、15 補【Issue 3／4 結果】）、`issues.md`（Issue 3、4 狀態）
- Modify（若架構事實改變）：根目錄 `CLAUDE.md` 的 `FoliateReaderView` 說明，以一句話補上「Windows 書檔由 loopback HTTP 服務」

- [ ] **Step 1：ADR**：背景（Issue 3 洩漏證據）、決策（只搬書檔、頁面 origin 不變、`bookBaseUrl`、權杖、Range）、被否決的選項（B Range 攔截仍與傳輸量成正比洩漏；C patch 外掛無根因；D 虛擬網域需 vendor 外掛 C++）、後果（維護一個 loopback 服務、平台分流）。
- [ ] **Step 2：報告**：Task 1 閘門數據、Task 6 debug／Release 數據、過關條件逐項勾選、尖峰記憶體與 3.8 GB 的對照、字型攔截洩漏量測（以 `reader_leak_test` 搭配自訂字型，或明載未量測的原因）、限制與後續 Issue（索引器 Headless、分段載入、前兩輪額外增量）。
- [ ] **Step 3：** 更新 `epic.md`、`issues.md`（及 `CLAUDE.md` 一句話）。
- [ ] **Step 4：** 完整 `flutter test`（`run_in_background`）與 `flutter analyze`、兩支 `node tool/check_*.js`。
- [ ] **Step 5：** commit；準備 PR。

---

## 後續（不在本計畫）

- 追查索引器在 Windows `HeadlessInAppWebView` 無法跑完的原因（疑似 rAF 暫停），並以 `indexer_leak_test` 完成端到端驗證。
- 「分段服務」：把 foliate-js 的整本 `fetch→Blob` 改成 Range 版 loader，降低 WebView2 子程序的尖峰記憶體。
- 自訂字型改走伺服器（視 Task 8 的量測數據）。
- 直接服務原檔、省略快取複製。
- 前兩輪的一次性額外記憶體增量成因（`issue-3-report.md` §3.2、§7.2）。

---

## 附錄 A：Release 迴圈進入點範本（`probe_main.dart`，不進版控）

`flutter drive` 在 Release／Profile 模式連不上 VM service，**無法用測試框架跑 Release**（Issue 3 已實測，`flutter run integration_test/...` 同理不可行）。改用暫時的 App 進入點，自己跑開關迴圈並印出 `[leak]` 行。檔案放 `app/probe_main.dart`（App 根目錄，讓相對匯入 `test/support/*` 成立），量測完刪除，**不得提交**。

```dart
// TEMP-PROBE：Release 版開關迴圈（不得提交）
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/windows/windows_webview_environment.dart';
import 'test/support/leak_meter.dart';
import 'test/support/leak_verdict.dart';

final _show = ValueNotifier<int>(0); // 0 = 不顯示閱讀器；n > 0 = 第 n 次開書（當作 widget key）
Completer<void>? _rendered;
late IOSink _out;

void _log(String s) {
  _out.writeln(s);
  print(s); // ignore: avoid_print
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _out = File('probe_release_result.log').openWrite();
  final appSupport = await getApplicationSupportDirectory();
  await initAppWebViewEnvironment(userDataFolder: appSupport.path);
  runApp(MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ValueListenableBuilder<int>(
      valueListenable: _show,
      builder: (context, n, child) => n == 0
          ? const SizedBox.shrink()
          : FoliateReaderView(
              key: ValueKey(n),
              filePath: kLargeEpubPath,
              onPageRendered: () {
                if (!(_rendered?.isCompleted ?? true)) _rendered!.complete();
              },
              onError: (e) {
                if (!(_rendered?.isCompleted ?? true)) {
                  _rendered!.completeError(StateError(e));
                }
              },
            ),
    ),
  ));
  await Future<void>.delayed(const Duration(seconds: 2));
  final list = <double>[];
  for (var i = 0; i <= kIterations; i++) {
    _log('[leak] path=reader-release iter=$i phase=before ${await sampleMemory()}');
    _rendered = Completer<void>();
    _show.value = i + 1;
    await _rendered!.future.timeout(const Duration(seconds: 120));
    _show.value = 0;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _log('[leak] path=reader-release iter=$i phase=after_run ${await sampleMemory()}');
    await Future<void>.delayed(const Duration(seconds: kSettleSeconds));
    final w = await sampleMemory();
    _log('[leak] path=reader-release iter=$i phase=after_wait $w');
    list.add(w.privateMb);
  }
  final v = evaluateLeak(privateMb: list, bookMb: bookSizeMb(), thresholdRatio: 0.05);
  _log('[leak-verdict] path=reader-release leaked=${v.leaked} ratcheting=${v.ratcheting} deltas=${v.deltas}');
  await _out.flush();
  await _out.close();
  exit(0);
}
```

建置與執行（PowerShell）：

```powershell
cd app
$env:MSYS2_ENV_CONV_EXCL = 'CL'; $env:CL = '/utf-8'
flutter build windows --release -t probe_main.dart      # 約 6～7 分鐘
.\build\windows\x64\runner\Release\elinkbook.exe        # 約 1 分鐘；結果寫入 probe_release_result.log
```

注意：迴圈結束的 `exit(0)` 在關閉階段可能出現 Segmentation fault，不影響已寫出的結果。第 0 輪（暖身）在 Release 版會包含首次開書的一次性額外增量（`issue-3-report.md` §7.1），判定看 iter1～4。
