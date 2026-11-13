# Epic 66 Issue 29 驗證與實作報告：Windows 資料收進 `文件\elinkbook-data`

- **對應規格**：[`issues.md`](issues.md)（Issue 29）、[`epic.md`](epic.md) 決策 33、[ADR 0044](../../adr/0044-windows-data-under-documents-elinkbook.md)、[ADR 0043](../../adr/0043-windows-installer-inno-setup-unsigned-per-user.md)（決策 5）
- **執行計畫**：[`plans/plan-issue-29.md`](plans/plan-issue-29.md)
- **審查報告**：`reviews/review-code-issue-29.md`（不進版控）
- **日期**：2026-11-13
- **產出（最終版，含審查修正與改名）**：
  - `app/build/windows_installer/elinkbook-1.1.0-b3-windows-x64-setup.exe`（18,616,319 bytes），SHA256 `6129F56299F9D4ED17391A52A2AE634C0E190D233E4DA6DA0ED8E173B7D02CFF`
  - `app/build/windows_zip/elinkbook-1.1.0-b3-windows-x64.zip`（23,080,748 bytes），SHA256 `FFEB778FC808AFC42EE786BDD60970224B8C00C180FF6EFA04FE7A4F8B61590B`
- **結論**：程式與自動化驗證已完成並通過；最終版 setup 已由使用者在另一台電腦驗證，回報「測試OK」（無逐項紀錄，見第六節）。資料夾曾在審查後改名（`elinkbook` → `elinkbook-data`），改名前那一輪的人工驗證不能套用到最終版，所以最終版另外驗證過一次。

---

## 一、獨立審查與處理摘要

實作完成後經獨立審查（結論 With fixes，4 項 Important、6 項 Minor），處理如下：

| 審查項 | 處理 |
|---|---|
| **I-1** zip 的頂層資料夾也叫 `elinkbook`，資料目錄同名會合併成同一個資料夾 | **使用者決定改資料夾名稱，並確認為 `elinkbook-data`**。已改 `lib/platform/app_paths.dart`、`elinkbook.iss`、驗證腳本、README、ADR 0043／0044、`issues.md`／`epic.md`；ADR 0044 新增決策 5 與替代方案；測試釘住名稱。第三節有同名碰撞的實證。 |
| **I-2** 冒煙套件失敗被寫成「證實無關」 | 已更正，見第四節：上一輪 2 支失敗的原因**未查明**，最終一輪 28/28 通過。 |
| **I-3** 計畫要求的證據缺漏、時間線有疑點 | 已補：舊 `.iss` 的 2c／2d 失敗輸出（第三節）、Release 新建置確認（第五節）、現場編出舊版 setup 的過程。驗證改在**最終 commit 之後重做**，與 commit 對得上（第五節）。 |
| **I-4** 舊位置「完全不變」證據偏弱 | 已補：基準含 SHA256、各資料夾檔案清單雜湊與 `-wal`／`-shm`／`-journal` 的有無，啟動 App 前後各取一次比對（第五節）；並解釋 172,032 bytes 的巧合。 |
| M-1 掃描測試漏洞 | 已補強：抓函式參照、別名前綴、低階 `getApplicationDocumentsPath`、區塊註解不位移行號；新增掃描器自測 4 項；納入 `third_party/`；釘住 `foliate_native_bridge.dart` 的豁免（只能有一處，且在 Windows 提前返回之後）。 |
| M-2 `app_paths.dart` | 拿掉多餘的 `exists()` 檢查；新增測試：多處同時呼叫、被同名檔案佔用時丟 `FileSystemException`、名稱不得為 `elinkbook`。 |
| M-3 選「否」鑑別力下降 | 1e 改為兩個資料夾逐檔（路徑加大小）比對；誘餌新增 `elinkbook\elinkbook.exe`（zip 程式資料夾）、`elinkbook-data-backup\a.txt`、`elinkbook.db`。 |
| M-4 詢問框固定寫「兩個資料夾」 | 改為只列實際存在的資料夾。 |
| M-5 文件數字不一致 | 已修：改動前 `lib/` 內直接呼叫共 10 處（8 個檔案）；其中 7 個檔案共 9 處改呼叫 `appDocumentsDirectory()`，1 處（`foliate_native_bridge.dart`，Android 專用）保留；`README.txt` 的標題改回「設定與下載資料」。 |
| M-6 驗證腳本檔頭 | 已補 Issue 29 與刪除範圍說明。 |

---

## 二、實作摘要

1. 新增集中函式 `appDocumentsDirectory()`（`app/lib/platform/app_paths.dart`）：Windows 回傳 `<文件>\elinkbook-data` 並遞迴建立；其他平台原樣回傳 `getApplicationDocumentsDirectory()`，不建立任何東西。建立失敗時原樣丟出 `FileSystemException`，不做無聲退路。
2. 7 個檔案共 9 處改呼叫它：`sqlite_library_repository.dart`、`dictionary_database.dart`、`cloud_book_downloader.dart`、`book_import_service_impl.dart`（3 處）、`main.dart`（`sweepUpdateStaging`）、`remote_book_downloader.dart`、`wifi_transfer_http_server.dart`。`foliate_native_bridge.dart` 那處只在 Android 路徑執行（Windows 在它之前就 `return`），不動。
3. 防散落掃描測試：`lib/` 與 `third_party/` 內只有 `app_paths.dart` 與 Android 專用的 `foliate_native_bridge.dart` 可以直接取用文件資料夾。
4. `elinkbook.iss`：選「是」只刪 `{userdocs}\elinkbook-data` 與 `{userappdata}\cc.ugotit\elinkbook`，只在對應根目錄非空時才動作；詢問框只列實際存在者；預設按鈕「否」、靜默一律不刪、App 執行中拒絕解除安裝皆保留。
5. **不遷移舊資料**：升級後書架為空；舊位置的檔案不讀、不改、不刪（ADR 0044）。

---

## 三、單元測試與安裝程式驗證

**單元測試**（`app/test/platform/app_paths_test.dart` 7 項、`app/test/library/windows_data_location_test.dart` 2 項、`app/test/platform/documents_directory_usage_test.dart` 6 項）：
- 改名時依 TDD 先改測試期望：`flutter test test/platform/app_paths_test.dart test/library/windows_data_location_test.dart` 先得到 `+3 -3`（3 個 Windows 案例失敗，如預期），改常數後全部通過。
- 路徑測試用含空格與中文的暫存目錄（`app paths 測試 …`）；以 `addTearDown` 還原平台覆蓋、`PathProviderPlatform.instance` 並刪除暫存目錄。
- 全套 `flutter test`：`08:09 +5182 ~2: All tests passed!`（0 失敗、2 跳過）。`flutter analyze`：No issues found。`node tool/check_l10n_hardcoded_strings.js`：PASS。

**解除安裝驗證腳本 `verify_windows_uninstall_data.ps1` 的鑑別力**（用 `AppDataRootOverride`／`DocsRootOverride` 指到 `%TEMP%` 下的假資料夾，不碰真實資料；以 UI Automation 實際點擊詢問框）。同一份新腳本對三種 `.iss` 的結果：

| `.iss` 版本 | 結果 |
|---|---|
| Issue 29 之前（固定名稱清單，`28f5c5b6`） | **2c、2d 失敗**；2d 掉了 4 項誘餌（`covers\a.bin`、`imported_books\b.bin` 等）。對應計畫 Task 3 Step 2 的預期。 |
| 審查前（資料夾叫 `elinkbook`，`725b69ff`） | **2c、2d 失敗**；2d 掉了 `elinkbook\elinkbook.exe`——這正是 I-1 的實證：zip 的程式資料夾若與資料夾同名，解除安裝選「是」會把它一起刪掉。 |
| 目前版本（`elinkbook-data`） | 10 項全過（1a～1e、2a～2d、0）；1c 確認「否」鈕取得鍵盤焦點（預設按鈕為「否」）；1e 兩個資料夾 16 個檔案逐檔比對差異 0 項。 |
| 變異：目前版本多刪假文件根目錄的 `covers` | **2d 失敗**，點名 `covers\a.bin`；驗完用備份還原並以 `cmp` 確認相同。 |

---

## 四、全套測試與冒煙套件

- **最終一輪（改名後、最終 commit 之後）`tool/run_windows_smoke.ps1`：28 支，通過 28／失敗 0／逾時 0／中止 0**（`foliate_txt_test` +3、`foliate_cbz_test` +3 都通過）。
- **更正（審查 I-2）**：實作者的上一輪冒煙套件中，`foliate_txt_test`（「大型 TXT」那一項 `did not complete [E]`，之後 `Some tests failed`）與 `foliate_cbz_test` 失敗過；我讀到的當時失敗訊息是 flutter 工具自己的暫存目錄清理錯誤（`PathNotFoundException: Deletion failed, path = '…\Temp\flutter_tools.xxxx\flutter_test_listener.xxxx'`），但 TXT／CBZ 匯入正好會寫 `imported_books`，**不能因為單獨重跑通過就說「證實與本變更無關」**。該輪的 log 已被最終一輪覆蓋；**原因未查明**，也沒有做「還原到變更前仍失敗」的對照。最終一輪沒有重現。

---

## 五、建置、檔案落點與舊位置驗證

**完整建置確認（審查 I-3，並更正計畫的一個錯誤假設）**
- 計畫要求確認 `elinkbook.exe` 的 `LastWriteTime` 晚於程式 commit，這是錯的：Dart 程式編譯在 `data\app.so`，exe 只是 C++ 外殼，Dart 改動時 exe 不會重連結（本次 exe 為 13:43，沒變）。
- 改查 `data\app.so`：`build\windows\x64\runner\Release\data\app.so` 與暫存目錄內的複本都是 **19:29:22**，晚於最後一個程式 commit（`d451fb49`，19:19:53）；對它搜尋字串 `elinkbook-data` 命中 1 次。
- 較舊版本 setup 用**本次新建置的暫存目錄**現場編出（複製、`README.txt` 改成 `OLD-VERSION`、`elinkbook.exe` 尾端補 1 個 0x00 位元組，`package_windows_installer.ps1 -StageDir <複本> -Version 1.0.9+1`），**沒有沿用 Issue 27 的舊檔**。
- 本機自動驗證 `verify_windows_installer.ps1 -Setup <最終 setup> -OlderSetup <現場編出的舊版>`：**29 項全過、exit 0**。

**舊位置不被碰（審查 I-4）**
- 基準取兩次（2026-11-13 19:17 與 19:32），中間 App 被啟動多次（含 `verify_windows_installer.ps1` 的安裝、升級、啟動，以及獨立的 30 秒落點啟動）。每次記錄：`library.db`（172,032 bytes、修改時間 2026-11-06T12:53:44、SHA256 `39721B44…14FB`）、`-wal`／`-shm`／`-journal`（皆不存在）、`dictionary.db`（不存在）、`covers`（116 檔／7,016,029 bytes）與 `imported_books`（96 檔／1,947,056 bytes）的檔案清單雜湊（路徑加大小加修改時間）、其餘 4 個資料夾（不存在）。**前後逐項相同。**
- 落點：從暫存目錄啟動 `elinkbook.exe` 30 秒後，`C:\Users\fycdc\Documents\elinkbook-data\library.db` 已建立（172,032 bytes）；「文件」根目錄沒有新增任何 App 項目。這台機器畫面空白（Issue 30），所以只驗證落點，不驗證 GUI。
- **172,032 bytes 的巧合**：新舊兩個 `library.db` 大小相同，但 SHA256 不同（舊 `39721B44…`、新 `A49BF339…`），不是複製；兩者都是 42 頁（4,096 bytes 每頁），表結構佔大多數頁數；`lib/` 內沒有任何複製 `library.db` 的程式碼。

---

## 六、人工 GUI 驗證（另一台電腦，使用者操作）

- **改名前的版本（實作者階段）**：使用者以當時打包的 setup（SHA256 `F804E33BB07A515DE656F93878E969EA964F4F88D479FC8E5950CAB46D7E7B49`，資料夾叫 `elinkbook`）在另一台電腦驗證：安裝、匯入一本書、重啟書還在、檔案落在 `文件\elinkbook` 底下、解除安裝選「是」刪除兩個資料夾且不動其他檔案。使用者回報原文：「`1,2,3 都正確無誤`」。另一台電腦的環境沒有查證。
- **這個結果只適用於改名前的版本，不能套用到最終版。**
- **最終版（資料夾 `elinkbook-data`，SHA256 `6129F562…02CFF`）**：請使用者在另一台電腦再驗證一次（安裝、匯入一本書、關閉再開書還在、檔案落在 `文件\elinkbook-data`、解除安裝選「是」）。使用者回報：「測試OK」。**這只是一句回報，沒有逐項紀錄**，無法確認每一項都被涵蓋；另一台電腦的環境也沒有查證。

---

## 七、舊項目手動清除清單

本版**不遷移舊資料**（ADR 0044），升級後書架為空，需要的書請重新匯入。舊位置的檔案不會被讀取、修改或自動刪除，以下是這台開發機（`C:\Users\fycdc\Documents`）上實際存在的、可由使用者決定手動刪除的項目：

- Issue 29 之前的舊位置（「文件」根目錄）：
  - `library.db`（172,032 bytes，2026-11-06）
  - `covers\`（116 檔）
  - `imported_books\`（96 檔）
- **孤兒資料夾 `文件\elinkbook\`（33 個檔案：`library.db`、`covers\`、`imported_books\`，不含任何 exe）**：是審查前（資料夾還叫 `elinkbook` 時）的版本啟動時建立的，改名後已不再使用。**使用者確認後已刪除（2026-11-13）**；刪除前確認內容只有那三項。其餘上述舊項目（`library.db`、`covers\`、`imported_books\`）使用者沒有指示刪除，仍保留。注意：若日後把免安裝 zip 解壓到「文件」，解壓出來的程式資料夾也叫 `elinkbook`，與資料資料夾 `elinkbook-data` 是不同的資料夾。
- 其他機器若曾用過舊版，還可能有：`dictionary.db` 與各資料庫的 `-wal`／`-shm`／`-journal`、`cloud_import_books\`、`remote_books\`、`wifi_transfer_uploads\`、`update_staging\`。

**現行的資料位置**（請保留）：`文件\elinkbook-data\` 與 `%APPDATA%\cc.ugotit\elinkbook\`。

---

## 八、未驗證與未解決

1. **最終版 setup 的人工驗證只有一句回報**「測試OK」（無逐項紀錄），見第六節。
2. **真實路徑下選「是」的實際刪除**：自動驗證用假資料夾（`DocsRootOverride`／`AppDataRootOverride`），出貨版與測試版只差這兩個編譯參數，這個差異本身沒有被驗證。
3. **冒煙套件上一輪失敗的原因**：未查明（第四節）。
4. **開發機 GUI**：受 Issue 30 影響（本機 release 版畫面空白），只驗證檔案落點。
5. **乾淨機器、舊版 Windows**：缺 VC 執行階段與 WebView2 的環境、Windows 10 1809、真實 SmartScreen 行為，一律未驗證。
6. **特殊「文件」路徑**：OneDrive 重新導向、Windows 帳號名稱含中文的真實路徑，只以單元測試的假目錄（含空格與中文）覆蓋，未在實機驗證。
7. **VC 可轉散發授權對 Build Tools 是否適用**（Issue 27 遺留）：未查證，對外發佈前須判斷。
8. **已知限制**：掃描測試對 `foliate_native_bridge.dart` 是整檔豁免（以「只有一處、且在 Windows 提前返回之後」的測試補強）；行尾註解與字串內出現函式名稱會被誤報（方向安全）。
