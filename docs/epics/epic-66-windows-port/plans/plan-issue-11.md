# Issue 11：Windows 測試穩定性與 loopback 連線可靠度 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `local_book_server_test.dart` 在這台 Windows 機器上穩定通過、為 Issue 6 建立乾淨的全套測試基準，並用有對照的實驗判斷「`127.0.0.1` 連線被重設」與這台機器上 Windows 版的「開書逾時」有沒有關係（目前只是假設，沒有證據）。

**Architecture:** 診斷顯示失敗來自這台機器的網路層，不是程式錯誤，所以不改伺服器邏輯。做三件事：（1）新增一支 Node 診斷腳本，可在任何機器量測 loopback 可靠度（分 `Connection: close` 與 keep-alive 兩種模式）；（2）給 `LocalBookServer.instance` 一個編譯期開關，能改綁 `127.0.0.2`（只接受 IPv4 loopback）做實驗，預設行為不變；（3）測試在 Windows 改綁 `127.0.0.2`。正式程式的預設位址與連線重試，等實驗結果出來後另行決定，不在本計畫內。

**Tech Stack:** Flutter 3.41.9、Dart `dart:io`、`shelf`、Node（純診斷腳本，不引入 npm 相依）。

**Spec:** `docs/epics/epic-66-windows-port/issues.md` 的「Issue 11 範圍／過關條件／單元測試要求」；`epic.md` 決策 27(d)。

## 診斷結果（2026-11-07，已實測，計畫的依據）

| 實驗 | 結果 |
|---|---|
| `flutter test` 單獨跑 `local_book_server_test.dart` 三次 | 每次失敗 2～3 個，項目會變；錯誤是 `Connection closed before full header was received` |
| 獨立 Dart 腳本，同一個 `LocalBookServer` 連續請求 100 次 | 失敗 20 次 |
| 純 `dart:io` `HttpServer`（不經 shelf）＋ `HttpClient` | 失敗 25 / 100 |
| 純 `dart:io` `HttpServer` ＋ 原始 `Socket` | 空回應 18 / 100 |
| Node 伺服器 ＋ Dart 原始 `Socket` | 空回應 5 / 100 |
| 純 Node（伺服器與客戶端都是 Node） | `ECONNRESET` 66 / 200 |
| 純 Node，只換位址：`127.0.0.1` / `127.0.0.2` / `::1` / 區網 `192.168.173.138` | 38 / 0 / 0 / 0 失敗（各 150 次） |
| 系統 proxy、`HTTP_PROXY` 環境變數 | 都沒有設定，已排除 |
| （審查補做）Node，`Connection: close`，請求間隔 0／50／250 ms | `127.0.0.1` 失敗 36／15／12 %；`127.0.0.2` 全為 0 |
| （審查補做）Node，同一條 keep-alive 連線重複使用 | `127.0.0.1` 與 `127.0.0.2` 都是 0 失敗 |
| （審查補做）Node，每次新連線但用 keep-alive | `127.0.0.1` 0 失敗 |
| （審查補做）Dart `HttpClient`，`persistentConnection=false` / `true` | `127.0.0.1` 26／100 與 0／100 失敗 |
| （審查補做）`netstat` TIME_WAIT | 322 筆；拉長間隔仍失敗，暫時連接埠耗盡已排除 |
| `pdf_reader_view_filters_test.dart` 單獨跑兩次 | 全過，沒有重現 |
| Issue 10 的全套 `flutter test`（5112 個） | 只有 2 個 `LocalBookServer` 失敗；Issue 9 報告列的其他 5 項（`pdf_reader_view_fit_mode`、`reader_screen_test` 2 項、`download_queue_controller`、`pdf_reader_view_filters`）當次沒有失敗 |

結論：
1. 只有 `127.0.0.1` 會被重設，與 Dart、shelf、本專案程式無關。
2. **只有請求帶 `Connection: close`（由伺服器端主動關閉）時才發生**；keep-alive 即使每次新連線也是 0 失敗。測試檔幾乎都設 `persistentConnection = false`，剛好踩中觸發條件。
3. WebView2（Chromium）用 keep-alive，所以這個問題**不一定**影響 Windows 版開書。這是假設，Task 6 才驗證。
4. 記憶中的「二次開書逾時」是 Android（BooksPad，WebView 91）的症狀，Android 不經 `LocalBookServer`，與本問題無直接關係。
5. Windows 上另有一筆實機觀察（2026-11-07，Issue 9 驗證時，尚未寫入文件）：`main` 與 Issue 9 分支各冷啟動一次、自動還原上次的書，都在約 35～55 秒後顯示「開書逾時」，所以這台機器的 Windows 版預設就會逾時，可作為 Task 6 的對照基準。

肇因（機器上有 Tailscale、多張 Hyper-V 虛擬網卡、Defender）尚未逐一比對，本計畫不做。

## Global Constraints

- Flutter 3.41.9，`flutter analyze` 乾淨；不得使用此版本沒有的 API。
- 不新增、不修改任何 ARB 字串。
- 預設行為不變：不帶 `LOCAL_BOOK_SERVER_BIND` 時，`LocalBookServer.instance` 綁 `127.0.0.1`；Android 與其他平台零改動。
- 不得 commit：`app/windows/flutter/generated_plugin_registrant.cc`、`generated_plugin_registrant.h`、`generated_plugins.cmake`、`pubspec.lock` 的任何變動；`git add` 一律明確列檔。
- 診斷腳本放 `app/tool/`，只用 Node 內建模組，並在 `app/tool/README.md` 登錄。
- Node：這台機器的 Git Bash 內 `node` 目前可直接用（v26.13）；PowerShell 需先 `$env:PATH = "$env:PNPM_HOME;$env:PATH"`。`app/tool/README.md` 寫的是「Git Bash 請改用 PowerShell、版本 v24.15」，Task 1 新增 README 一節時順手把這一點對齊現況。
- Windows 建置（Task 6）：PowerShell 設 `$env:CL='/utf-8'`；`$env:Path += ';C:\Users\huthief\bin'`（放尾端，不要放前面，該資料夾有個 `flutter` 檔會蓋掉指令）以找到 `nuget.exe`；新 worktree 第一次建置若曾在缺 `nuget.exe` 時失敗，要刪掉該 worktree 的 `app\build\windows` 再建，否則 CMake 會用錯安裝路徑（`C:/Program Files/elinkbook`）。
- 實驗腳本與暫存輸出放 scratchpad 目錄，不放進專案。

## Review Focus

1. `127.0.0.2` 在 macOS／Linux 預設不能綁定：測試改綁位址只在 Windows 啟用，其他平台維持 `127.0.0.1`。（Task 3）
2. `LOCAL_BOOK_SERVER_BIND` 給空字串、非 IP 字串、`0.0.0.0`、區網 IP、`::1`：App 不崩潰，一律退回 `127.0.0.1`，書檔服務不會暴露到區網。（Task 2）
3. 不帶開關的預設行為不變：位址仍是 `127.0.0.1`，Host 標頭檢查仍通過。（Task 2、3）
4. 「埠綁定失敗」測試：佔埠用的 `blocker` 與預期失敗的 `failing` 必須綁同一個位址，否則 `127.0.0.2` 綁得上、測試不會失敗。（Task 3）
5. 診斷腳本只量 `Connection: close` 會在別台機器顯示正常，卻不代表 keep-alive 的 WebView2 正常：腳本必須兩種模式都量並分開列出。（Task 1）
6. `127.0.0.2` 版在 WebView2 載入失敗，被誤判成「開書逾時」：實驗計數前先冒煙確認能渲染、伺服器收得到請求。（Task 6）
7. 實驗樣本太少、預設版本本來就不逾時、或順序效應（快取、Defender 掃描新 exe）：報告寫「不能確定」，不寫「已解決」。（Task 6）

---

### Task 1：診斷腳本 `check_loopback_reliability.js`

**Files:**
- Create: `app/tool/check_loopback_reliability.js`
- Modify: `app/tool/README.md`（新增一節，格式比照其他腳本）

**Interfaces:**
- Produces: 命令列 `node tool/check_loopback_reliability.js [--count N]`（`N` 預設 100）。對 `127.0.0.1`、`127.0.0.2`、`::1`、第一個非內部的 IPv4 位址各啟動一個 Node `http` 伺服器，用原始 TCP 連線循序發 `N` 次 `GET`，**每個位址跑兩種模式**：`close`（請求帶 `Connection: close`）與 `keepalive`（請求帶 `Connection: keep-alive`，收完回應後由客戶端關閉；每次仍是新連線）。每列輸出 `位址  模式  ok=… reset=… empty=…`，共 8 列。`127.0.0.1` 的 `close` 或 `keepalive` 任一有 `reset` 或 `empty` 時結束碼為 1，否則 0。腳本不需要 `flutter`。

- [ ] **Step 1: 實作腳本。** 以 scratchpad 內已驗證過的 `node_hosts.js` 為藍本：每個位址一個 `http.createServer`、`net.connect` 發 `Connection: close` 的 `GET`，收到資料後正常結束算 `ok`，收到 `error` 事件算 `reset`（輸出錯誤碼，例如 `ECONNRESET`），連線結束但沒收到任何位元組算 `empty`。位址無法綁定（例如沒有 IPv6）時該列印 `無法綁定:<code>`，不計入結束碼。程式註解用中文。
- [ ] **Step 2: 執行確認。** `node tool/check_loopback_reliability.js --count 50`，預期印出 8 列；在這台機器上 `127.0.0.1` 的 `close` 列 `reset` 或 `empty` 大於 0，`127.0.0.1` 的 `keepalive` 列與其餘位址各列為 0，結束碼為 1。
- [ ] **Step 3: 登錄 README。** 在 `tool/README.md` 加 `## check_loopback_reliability.js` 一節：用途（量測本機 loopback 連線可靠度）、指令、輸出怎麼看、「`127.0.0.1` 的 `close` 列有失敗、`keepalive` 列與其他位址正常，代表本機有軟體干擾 `127.0.0.1` 上由伺服器主動關閉的連線；使用 keep-alive 的客戶端（例如瀏覽器）不一定受影響，是否影響 Windows 版開書要另外驗證」。並把 README 開頭「Git Bash 請改用 PowerShell、Node v24.15」的敘述對齊現況（Git Bash 內 `node` 目前可用）。
- [ ] **Step 4: Commit。**

```bash
git add app/tool/check_loopback_reliability.js app/tool/README.md
git commit -m "feat(tool): 新增 loopback 連線可靠度診斷腳本（epic-66 Issue 11 Task 1）"
```

---

### Task 2：`LocalBookServer` 的綁定位址開關

**Files:**
- Modify: `app/lib/reader/local_book_server.dart`
- Test: `app/test/reader/local_book_server_test.dart`

**Interfaces:**
- Produces:
  - `static InternetAddress LocalBookServer.bindAddressFromDefine(String value)`：`value` 能解析成 **IPv4 且 `isLoopback`** 的位址就回傳該位址；空字串、解析失敗、非 loopback（例如 `0.0.0.0`、區網 IP）或 IPv6（`::1` 會讓 `http://::1:port` 無法被 `Uri.parse`）一律回傳 `InternetAddress.loopbackIPv4`，不拋例外。
  - `LocalBookServer.instance` 改為 `LocalBookServer(bindAddress: bindAddressFromDefine(const String.fromEnvironment('LOCAL_BOOK_SERVER_BIND')))`。不帶開關時結果與現況相同。

- [ ] **Step 1: 寫失敗測試。** 在 `local_book_server_test.dart` 的 `group('LocalBookServer')` 之外新增 `group('bindAddressFromDefine')`，六個測試：`'127.0.0.2'` → `address == '127.0.0.2'`；`''`、`'abc'`、`'0.0.0.0'`、`'192.168.1.5'`、`'::1'` 各自 → `InternetAddress.loopbackIPv4` 且不拋例外。
- [ ] **Step 2: 執行確認失敗。** `flutter test test/reader/local_book_server_test.dart --plain-name "bindAddressFromDefine"`，預期編譯失敗（方法不存在）。
- [ ] **Step 3: 實作。** 加 `static InternetAddress bindAddressFromDefine(String value)`（用 `InternetAddress.tryParse`，再檢查 `type == InternetAddressType.IPv4 && isLoopback`）；把 `static final instance = LocalBookServer();` 改為帶 `bindAddress` 的建構，值來自 `const String.fromEnvironment('LOCAL_BOOK_SERVER_BIND')`。加中文註解：這是實驗與診斷開關，預設不帶，見 Issue 11 報告。
- [ ] **Step 4: 執行確認通過。** 同 Step 2 指令，預期 6 個全過；`flutter analyze lib/reader/local_book_server.dart` 乾淨。
- [ ] **Step 5: Commit。**

```bash
git add app/lib/reader/local_book_server.dart app/test/reader/local_book_server_test.dart
git commit -m "feat(windows): LocalBookServer 綁定位址可用編譯開關指定（epic-66 Issue 11 Task 2）"
```

---

### Task 3：`local_book_server_test.dart` 在 Windows 改綁 `127.0.0.2`

**Files:**
- Modify: `app/test/reader/local_book_server_test.dart`

**Interfaces:**
- Consumes: Task 2 不需要；只用既有的 `LocalBookServer({InternetAddress? bindAddress})` 建構參數。
- Produces: 檔內私有輔助 `InternetAddress _testBindAddress()`：`Platform.isWindows` 回傳 `InternetAddress('127.0.0.2')`，否則回傳 `InternetAddress.loopbackIPv4`。

- [ ] **Step 1: 先量基準。** 連跑 `flutter test test/reader/local_book_server_test.dart` 5 次，記下每次失敗數（預期每次 2～3 個）。
- [ ] **Step 2: 改測試。** `setUp` 的 `server = LocalBookServer(bindAddress: _testBindAddress())`；其他在測試內自行 `LocalBookServer(...)` 的地方（並行 register、重啟那幾個）一併帶入。**「埠綁定失敗」測試：佔埠用的 `blocker`（現為 `ServerSocket.bind(InternetAddress.loopbackIPv4, 0)`）與預期失敗的 `failing` 都要用 `_testBindAddress()`**；實測 `blocker` 佔 `127.0.0.1:P` 時，綁 `127.0.0.2:P` 仍會成功，只改 `failing` 會讓這個測試不再失敗。把 `expect(handle.bookBaseUri.host, '127.0.0.1')` 改為 `_testBindAddress().address`；斷言 `server.address!.isLoopback` 不變。「錯誤 Host 標頭回傳 403」的偽造值是固定的 `spoofed.local:1234`，不受影響，不用改。既有「close 後連線被拒」測試的 `expect(() async {...}, throwsA(...))` 沒有 `await`（既有問題，本 Task 不改），報告不要把它當作已驗證的證據。
- [ ] **Step 3: 執行確認。** 連跑 5 次，預期每次 `All tests passed!`，共 11 + 6 個（含 Task 2 的六個）。若仍有失敗，先看錯誤是否仍為 `Connection closed before full header`；是的話表示 `127.0.0.2` 也會掉，停下來回報，不要加重試掩蓋。
- [ ] **Step 4: Commit。**

```bash
git add app/test/reader/local_book_server_test.dart
git commit -m "test(windows): LocalBookServer 測試在 Windows 改綁 127.0.0.2（epic-66 Issue 11 Task 3）"
```

---

### Task 4：`pdf_reader_view_filters_test.dart` 重現嘗試

**Files:**
- 預期不改檔案；結果寫入 Task 6 的報告。

- [ ] **Step 1: 整批重現。** 連跑 3 次 `flutter test test/reader`（整個目錄，讓多個測試檔平行執行；這比專案慣例的「只跑異動檔」範圍大，是為了重現平行執行時的互相干擾），每次記錄 `pdf_reader_view_filters_test.dart` 是否失敗。失敗時保存完整錯誤訊息。
- [ ] **Step 2: 判斷。** 3 次都沒失敗，連同 Task 5 全套結果，記為「無法重現（共 N 次含全套）」，不改檔案。有失敗就依 `superpowers:systematic-debugging` 查根因；若根因與 loopback 無關且需要改測試或程式，另寫一個 Task 補進本計畫並先在帳本記錄 ruling，再動手。

---

### Task 5：全套測試與乾淨基準

**Files:**
- 無異動；結果寫入 Task 6 的報告。

- [ ] **Step 1: 執行全套。** 在 `app/` 用 JSON reporter 跑 `flutter test`，輸出存 scratchpad，列出失敗測試名稱（比照 Issue 10 的做法）。
- [ ] **Step 2: 比對。** 預期 0 個 `LocalBookServer` 失敗。記錄總數與所有剩餘失敗；每個剩餘失敗再單獨跑一次，判斷是「單獨跑也失敗」（真問題）還是「只有全套失敗」（互相干擾），寫進報告。

---

### Task 6：開書逾時對照實驗、報告與文件（需人在電腦前、螢幕解鎖）

**Files:**
- Create: `docs/epics/epic-66-windows-port/issue-11-report.md`
- Modify: `docs/epics/epic-66-windows-port/issues.md`（Issue 11 狀態列）、本檔（勾選步驟）

**實驗的問題：** 在這台機器上，Windows 版預設（綁 `127.0.0.1`）會「開書逾時」；改綁 `127.0.0.2` 後逾時是否消失？對照基準：2026-11-07 兩次冷啟動都逾時（見診斷結論 5）。

- [ ] **Step 1: 建兩個 Windows 版本。** 依 Global Constraints 的建置說明，在同一個 worktree 建 debug 版：一次不帶開關（版本 A）、一次帶 `--dart-define=LOCAL_BOOK_SERVER_BIND=127.0.0.2`（版本 B）。建完第一個先把 `runner\Debug` 整個複製到 scratchpad，再建第二個，兩個輸出資料夾分開保存。
- [ ] **Step 2: 冒煙確認版本 B 能開書。** 只啟動版本 B 一次、開同一本書，並把標準輸出導到檔案（`Start-Process -RedirectStandardOutput`）。確認輸出裡有 `[OpenBook#…]` 的「已渲染」類階段紀錄，而不是 WebView 載入失敗；若載入失敗（混合內容或 Private Network Access 擋掉 `127.0.0.2`），停下來回報，不得往下計數，否則會把「載入失敗」誤判成「開書逾時」。
- [ ] **Step 3: 請使用者做交錯實驗。** 順序固定為 A、B、A、B、A、B、A、B、A、B（交錯，避免快取、`%APPDATA%` 的 WebView2 資料夾、Defender 掃描新 exe 造成順序效應）。每一次：完全關閉 App 後冷啟動、還原上次閱讀的同一本書，標準輸出導到各自的檔案；記錄「開書成功／顯示開書逾時」、`OpenBookTrace` 各階段耗時、最後階段名稱。每個版本再多做一輪「同一次啟動內連續開同一本書 3 次」。開始前與結束後各跑一次 `node tool/check_loopback_reliability.js --count 50`，確認當下 `127.0.0.1` 的 `close` 模式確實有重設。
- [ ] **Step 4: 寫 `issue-11-report.md`。** 內容：診斷表（本計畫的診斷結果）、Task 3～5 的結果、實驗每一次的原始紀錄（版本、成功或逾時、最後階段、耗時）、結論。結論只能是三種之一：（a）版本 A 逾時次數明顯多於版本 B（例如 A 至少 4／5、B 為 0／5），可以說 `127.0.0.2` 消除逾時，建議另開 Issue 決定正式程式要不要改預設位址或加重試；（b）A、B 逾時次數相近，開書逾時與 `127.0.0.1` 重設無關，更新記憶 `project_open-book-timeout-diagnosis` 與 `project_loopback-127-0-0-1-resets`；（c）樣本不足或結果混雜，寫「不能確定」與下一步（例如在伺服器端記錄 WebView2 實際送出的 `Connection` 標頭與連線數）。
- [ ] **Step 5: 同步文件並勾選。** `issues.md` Issue 11 狀態改為「✅ 實作完成，待 PR」；更新記憶 `project_loopback-127-0-0-1-resets` 的實驗結論；本檔已完成步驟 `- [ ]` 改 `- [x]`。
- [ ] **Step 6: Commit。**

```bash
git add docs/epics/epic-66-windows-port/issue-11-report.md docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/plans/plan-issue-11.md
git commit -m "docs(epic-66): Issue 11 驗證報告與進度同步"
```

---

## Self-Review

- **範圍涵蓋：** `issues.md` 範圍 1～7 對應 Task 1（診斷工具）、2（實驗開關）、3（測試穩定）、4（`pdf_reader_view_filters`）、5（乾淨基準）、6（開書逾時實驗與報告）；範圍 7「不處理」由 Task 6 結論的選項（a）另開 Issue 承接。
- **型別一致：** 新名稱只有 `LocalBookServer.bindAddressFromDefine`、`LOCAL_BOOK_SERVER_BIND`、`_testBindAddress`，定義與使用處名稱一致。
- **比例：** 計畫只列簽章、指令、預期輸出，沒有貼函式本體。
- **已知風險：**（a）Task 3 假設 `127.0.0.2` 在這台機器穩定，只有 Node 150 次的證據，所以 Step 3 要求連跑 5 次並明列「仍掉就停下來」；（b）Task 6 需要人在電腦前且螢幕解鎖，Issue 10 的實機確認也卡在同一點；（c）Task 6 實驗只有 5 + 5 次，樣本小，結論（c）「不能確定」是合法結果；（d）審查（2026-11-07）修訂：診斷補上 `Connection: close` 條件、開關限定 IPv4 loopback、`blocker` 改位址、實驗改交錯並加冒煙，詳見 `reviews/review-plan-issue-11.md`。
