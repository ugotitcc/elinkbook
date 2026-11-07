# Issue 11：Windows 測試穩定性與 loopback 連線可靠度 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `local_book_server_test.dart` 在這台 Windows 機器上穩定通過、為 Issue 6 建立乾淨的全套測試基準，並驗證「`127.0.0.1` 連線被重設」是不是「開書逾時」的原因。

**Architecture:** 診斷顯示失敗來自這台機器的網路層，不是程式錯誤，所以不改伺服器邏輯。做三件事：（1）新增一支 Node 診斷腳本，可在任何機器量測 loopback 可靠度；（2）給 `LocalBookServer.instance` 一個編譯期開關，能改綁 `127.0.0.2` 做實驗，預設行為不變；（3）測試在 Windows 改綁 `127.0.0.2`。正式程式的預設位址與連線重試，等實驗結果出來後另行決定，不在本計畫內。

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
| `pdf_reader_view_filters_test.dart` 單獨跑兩次 | 全過，沒有重現 |
| Issue 10 的全套 `flutter test`（5112 個） | 只有 2 個 `LocalBookServer` 失敗；Issue 9 報告列的其他 5 項（`pdf_reader_view_fit_mode`、`reader_screen_test` 2 項、`download_queue_controller`、`pdf_reader_view_filters`）當次沒有失敗 |

結論：只有 `127.0.0.1` 會被重設，與 Dart、shelf、本專案程式無關。肇因（機器上有 Tailscale、多張 Hyper-V 虛擬網卡、Defender）尚未逐一比對，本計畫不做。

## Global Constraints

- Flutter 3.41.9，`flutter analyze` 乾淨；不得使用此版本沒有的 API。
- 不新增、不修改任何 ARB 字串。
- 預設行為不變：不帶 `LOCAL_BOOK_SERVER_BIND` 時，`LocalBookServer.instance` 綁 `127.0.0.1`；Android 與其他平台零改動。
- 不得 commit：`app/windows/flutter/generated_plugin_registrant.cc`、`generated_plugin_registrant.h`、`generated_plugins.cmake`、`pubspec.lock` 的任何變動；`git add` 一律明確列檔。
- 診斷腳本放 `app/tool/`，只用 Node 內建模組，並在 `app/tool/README.md` 登錄。
- Node 在這台機器的 Git Bash 可直接用；PowerShell 需先 `$env:PATH = "$env:PNPM_HOME;$env:PATH"`。
- Windows 建置（Task 6）：PowerShell 設 `$env:CL='/utf-8'`；`$env:Path += ';C:\Users\huthief\bin'`（放尾端，不要放前面，該資料夾有個 `flutter` 檔會蓋掉指令）以找到 `nuget.exe`；新 worktree 第一次建置若曾在缺 `nuget.exe` 時失敗，要刪掉該 worktree 的 `app\build\windows` 再建，否則 CMake 會用錯安裝路徑（`C:/Program Files/elinkbook`）。
- 實驗腳本與暫存輸出放 scratchpad 目錄，不放進專案。

## Review Focus

1. `127.0.0.2` 在 macOS／Linux 預設不能綁定：測試改綁位址只在 Windows 啟用，其他平台維持 `127.0.0.1`。（Task 3）
2. `LOCAL_BOOK_SERVER_BIND` 給空字串或非 IP 字串：App 不崩潰，退回 `127.0.0.1`。（Task 2）
3. 不帶開關的預設行為不變：位址仍是 `127.0.0.1`，Host 標頭檢查仍通過。（Task 2、3）
4. 測試改位址後，「錯誤 Host 標頭回傳 403」仍有意義：偽造的 Host 必須與實際綁定位址不同。（Task 3）
5. 實驗樣本太少或逾時本來就是間歇性：報告寫「不能確定」，不寫「已解決」。（Task 6）

---

### Task 1：診斷腳本 `check_loopback_reliability.js`

**Files:**
- Create: `app/tool/check_loopback_reliability.js`
- Modify: `app/tool/README.md`（新增一節，格式比照其他腳本）

**Interfaces:**
- Produces: 命令列 `node tool/check_loopback_reliability.js [--count N]`（`N` 預設 100）。對 `127.0.0.1`、`127.0.0.2`、`::1`、第一個非內部的 IPv4 位址各啟動一個 Node `http` 伺服器，用原始 TCP 連線循序發 `N` 次 `GET`，每列輸出 `位址  ok=… reset=… empty=…`。`127.0.0.1` 有任何 `reset` 或 `empty` 時結束碼為 1，否則 0。腳本不需要 `flutter`。

- [ ] **Step 1: 實作腳本。** 以 scratchpad 內已驗證過的 `node_hosts.js` 為藍本：每個位址一個 `http.createServer`、`net.connect` 發 `Connection: close` 的 `GET`，收到資料後正常結束算 `ok`，收到 `error` 事件算 `reset`（輸出錯誤碼，例如 `ECONNRESET`），連線結束但沒收到任何位元組算 `empty`。位址無法綁定（例如沒有 IPv6）時該列印 `無法綁定:<code>`，不計入結束碼。程式註解用中文。
- [ ] **Step 2: 執行確認。** `node tool/check_loopback_reliability.js --count 50`，預期印出 4 列；在這台機器上 `127.0.0.1` 列的 `reset` 或 `empty` 大於 0、其餘三列為 0，結束碼為 1。
- [ ] **Step 3: 登錄 README。** 在 `tool/README.md` 加 `## check_loopback_reliability.js` 一節：用途（量測本機 loopback 連線可靠度）、指令、輸出怎麼看、「`127.0.0.1` 有失敗但其他位址正常，代表本機有軟體干擾 `127.0.0.1`，可能影響 Windows 版開書」。
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
  - `static InternetAddress LocalBookServer.bindAddressFromDefine(String value)`：`value` 能解析成 IP 位址就回傳該位址；空字串或解析失敗回傳 `InternetAddress.loopbackIPv4`，不拋例外。
  - `LocalBookServer.instance` 改為 `LocalBookServer(bindAddress: bindAddressFromDefine(const String.fromEnvironment('LOCAL_BOOK_SERVER_BIND')))`。不帶開關時結果與現況相同。

- [ ] **Step 1: 寫失敗測試。** 在 `local_book_server_test.dart` 的 `group('LocalBookServer')` 之外新增 `group('bindAddressFromDefine')`，三個測試：`'127.0.0.2'` → `address == '127.0.0.2'`；`''` → `InternetAddress.loopbackIPv4`；`'abc'` → `InternetAddress.loopbackIPv4` 且不拋例外。
- [ ] **Step 2: 執行確認失敗。** `flutter test test/reader/local_book_server_test.dart --plain-name "bindAddressFromDefine"`，預期編譯失敗（方法不存在）。
- [ ] **Step 3: 實作。** 加 `static InternetAddress bindAddressFromDefine(String value)`（用 `InternetAddress.tryParse`）；把 `static final instance = LocalBookServer();` 改為帶 `bindAddress` 的建構，值來自 `const String.fromEnvironment('LOCAL_BOOK_SERVER_BIND')`。加中文註解：這是實驗與診斷開關，預設不帶，見 Issue 11 報告。
- [ ] **Step 4: 執行確認通過。** 同 Step 2 指令，預期 3 個全過；`flutter analyze lib/reader/local_book_server.dart` 乾淨。
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
- [ ] **Step 2: 改測試。** `setUp` 的 `server = LocalBookServer(bindAddress: _testBindAddress())`；其他在測試內自行 `LocalBookServer(...)` 的地方（例如埠綁定失敗、並行 register、重啟那幾個）一併帶入。把 `expect(handle.bookBaseUri.host, '127.0.0.1')` 改為 `_testBindAddress().address`；「錯誤 Host 標頭回傳 403」若寫死 `127.0.0.1:…` 的偽造 Host，改成與實際綁定位址不同的值（例如實際是 `127.0.0.2` 就偽造 `127.0.0.1:<port>` 以外也要確認不同）；斷言 `server.address!.isLoopback` 不變。
- [ ] **Step 3: 執行確認。** 連跑 5 次，預期每次 `All tests passed!`，共 11 + 3 個（含 Task 2 的三個）。若仍有失敗，先看錯誤是否仍為 `Connection closed before full header`；是的話表示 `127.0.0.2` 也會掉，停下來回報，不要加重試掩蓋。
- [ ] **Step 4: Commit。**

```bash
git add app/test/reader/local_book_server_test.dart
git commit -m "test(windows): LocalBookServer 測試在 Windows 改綁 127.0.0.2（epic-66 Issue 11 Task 3）"
```

---

### Task 4：`pdf_reader_view_filters_test.dart` 重現嘗試

**Files:**
- 預期不改檔案；結果寫入 Task 6 的報告。

- [ ] **Step 1: 整批重現。** 連跑 3 次 `flutter test test/reader`（整個目錄，讓多個測試檔平行執行），每次記錄 `pdf_reader_view_filters_test.dart` 是否失敗。失敗時保存完整錯誤訊息。
- [ ] **Step 2: 判斷。** 3 次都沒失敗，連同 Task 5 全套結果，記為「無法重現（共 N 次含全套）」，不改檔案。有失敗就依 `superpowers:systematic-debugging` 查根因；若根因與 loopback 無關且需要改測試或程式，另寫一個 Task 補進本計畫並先在帳本記錄 ruling，再動手。

---

### Task 5：全套測試與乾淨基準

**Files:**
- 無異動；結果寫入 Task 6 的報告。

- [ ] **Step 1: 執行全套。** 在 `app/` 用 JSON reporter 跑 `flutter test`，輸出存 scratchpad，列出失敗測試名稱（比照 Issue 10 的做法）。
- [ ] **Step 2: 比對。** 預期 0 個 `LocalBookServer` 失敗。記錄總數與所有剩餘失敗；每個剩餘失敗再單獨跑一次，判斷是「單獨跑也失敗」（真問題）還是「只有全套失敗」（互相干擾），寫進報告。

---

### Task 6：開書逾時實驗、報告與文件（需人在電腦前、螢幕解鎖）

**Files:**
- Create: `docs/epics/epic-66-windows-port/issue-11-report.md`
- Modify: `docs/epics/epic-66-windows-port/issues.md`（Issue 11 狀態列）、本檔（勾選步驟）

- [ ] **Step 1: 建兩個 Windows 版本。** 依 Global Constraints 的建置說明，在同一個 worktree 建 debug 版：一次不帶開關、一次帶 `--dart-define=LOCAL_BOOK_SERVER_BIND=127.0.0.2`，兩個輸出資料夾分開保存（建完第一個先複製 `runner\Debug` 到 scratchpad，再建第二個）。
- [ ] **Step 2: 請使用者做實驗。** 兩個版本各冷啟動 5 次（每次完全關閉 App 再開），每次都是還原上次閱讀的同一本書；記錄「開書成功」或「顯示開書逾時」。同時在開 App 前後各跑一次 `node tool/check_loopback_reliability.js --count 50`，確認當下 `127.0.0.1` 確實有重設。
- [ ] **Step 3: 寫 `issue-11-report.md`。** 內容：診斷表（本計畫的診斷結果）、Task 3～5 的結果、實驗的 5 + 5 次原始紀錄、結論。結論只能是三種之一：（a）`127.0.0.2` 消除逾時，建議另開 Issue 決定正式程式要不要改預設位址或加重試；（b）兩者逾時次數相近，開書逾時與 loopback 無關，更新記憶 `project_open-book-timeout-diagnosis`；（c）樣本不足或結果混雜，寫「不能確定」與下一步。
- [ ] **Step 4: 同步文件並勾選。** `issues.md` Issue 11 狀態改為「✅ 實作完成，待 PR」；更新記憶 `project_loopback-127-0-0-1-resets` 的實驗結論；本檔已完成步驟 `- [ ]` 改 `- [x]`。
- [ ] **Step 5: Commit。**

```bash
git add docs/epics/epic-66-windows-port/issue-11-report.md docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/plans/plan-issue-11.md
git commit -m "docs(epic-66): Issue 11 驗證報告與進度同步"
```

---

## Self-Review

- **範圍涵蓋：** `issues.md` 範圍 1～7 對應 Task 1（診斷工具）、2（實驗開關）、3（測試穩定）、4（`pdf_reader_view_filters`）、5（乾淨基準）、6（開書逾時實驗與報告）；範圍 7「不處理」由 Task 6 結論的選項（a）另開 Issue 承接。
- **型別一致：** 新名稱只有 `LocalBookServer.bindAddressFromDefine`、`LOCAL_BOOK_SERVER_BIND`、`_testBindAddress`，定義與使用處名稱一致。
- **比例：** 計畫只列簽章、指令、預期輸出，沒有貼函式本體。
- **已知風險：**（a）Task 3 假設 `127.0.0.2` 在這台機器穩定，只有 Node 150 次的證據，所以 Step 3 要求連跑 5 次並明列「仍掉就停下來」；（b）Task 6 需要人在電腦前且螢幕解鎖，Issue 10 的實機確認也卡在同一點；（c）Task 6 實驗只有 5 + 5 次，樣本小，結論（c）「不能確定」是合法結果。
