# Epic 15：儲存權限失效偵測與復原

## 背景

App 匯入書籍與字型檔案一律不複製檔案，直接以 SAF（Storage Access Framework）取得的 `content://` URI 搭配 `takePersistableUriPermission()` 持久化授權引用原始檔案（見 ADR 0002、ADR 0021）。專案初期曾實際發生「部分裝置重新選取子資料夾體驗不佳」的狀況，但當時未查明具體觸發裝置/ROM 或根本原因，也沒有針對性修復；後續開發至今，所有測試機皆未再重現這個問題，目前沒有可鎖定的具體場景或使用者回報。

由於問題不再重現、成因不明，這個 Epic 長期停留在 `docs/epics.md` 的 Backlog 備註，一句話帶過（「傳統儲存權限機制」）。2026-09-14 透過 `/grill-with-docs` 對此重新展開 Discovery，釐清方向。

## 目標

本次僅進行風險評估與方案調查（Discovery），**非**直接排入開發：

1. 釐清問題目前的風險狀態（是否仍可能發生、影響範圍多大）。
2. 排除技術上不可行或高風險的解法方向。
3. 提出若未來問題重現時的候選補強方向，降低下次重新評估的成本。

## Discovery 結論（2026-09-14 `/grill-with-docs`；2026-09-14 審查修正）

- **問題現況**：不再重現，無具體裝置/ROM 線索，原因不明（開發過程中未曾針對性修復，純粹是後續測試都沒再撞到）。
- **影響範圍**：SAF 檔案匯入與資料夾匯入兩條路徑皆可能受影響；經審查核對程式碼確認，單檔匯入已有 `_copyToLocalStorage` 落地複本退路防禦（`takePersistableUriPermission` 失敗時自動觸發），資料夾匯入的子檔案因共用 Tree URI 授權、刻意跳過此退路，是實際風險較高的路徑。
- **排除方向**：`MANAGE_EXTERNAL_STORAGE`（Android 11+ 全域儲存權限，All Files Access）——App 已規劃上架 Google Play，此權限對「電子書閱讀器」類別的審核風險高，且仍須維持非商城（側載）安裝路徑正常運作，兩個約束疊加使此方向不可行。詳見 [ADR 0029](../../adr/0029-storage-permission-saf-resilience-over-manage-external-storage.md)。
- **候選補強方向**：不新增權限，改為強化既有 SAF 路線的容錯——**開書當下（非定期背景輪詢）**以 `contentResolver.openInputStream()` 按需探測並精確區分 `SecurityException`（權限失效）／`FileNotFoundException`（檔案不存在），失效時導向重新選取，並將新 URI 原地更新回既有書籍記錄（Re-link，保全 `book.id` 與所有劃線/筆記/書籤/進度）。原案曾規劃以 `ContentResolver.getPersistedUriPermissions()` 查表偵測，經 [Epic 與 Design 審查](./reviews/review-epic-and-design.md) 確認此 API 對資料夾匯入書籍的 Document URI 必定誤判、且無法反映檔案真實可讀性，已修正為上述按需探測方案；「定期於背景檢查」亦已排除，因違反 E-Ink 裝置低功耗待機原則。詳見 [design.md](./design.md)。
- **後續**：Discovery 當下決定待有具體重現案例再評估是否排入開發；2026-09-28 使用者決定直接進入 Architecting（見下方）。

## Architecting 結論（2026-09-28 `/to-spec`）

`spec.md` 已產出（Status: `ready-for-agent`），自此為本 Epic 的唯一事實來源。與 design.md 的主要差異與新增決策：

- **失敗後探測取代例外全面透傳**：design §3 原規劃把原生讀取方法全面改成 `result.error`，但 `cacheBookForServing`／`readContentUriAll` 有 5 個呼叫端（兩個閱讀器、兩個全文索引器、WiFi 傳書）都靠「回傳 null」判斷失敗。改為新增單一原生「存取探測」方法，只在 `ReaderScreen` 開書失敗且 `filePath` 為 `content://` 時探測一次；既有讀取契約不變。
- **受影響範圍收斂**：TXT／MD／CBZ／雲端／Calibre／WiFi 傳書／單檔匯入落地複本的書，`filePath` 都是 App 私有路徑，不在範圍內；實際風險集中在 `filePath` 仍為 `content://` 的 EPUB／PDF／AZW3。
- **Re-link 放進 `BookImportService`**：共用既有格式判斷、持久化授權與落地複本退路；以書籍 id 為輸入，寫入前自行讀取最新記錄，避免整列覆寫把閱讀位置蓋回舊值。
- **內容指紋不一致一律拒絕連結**（保護劃線／書籤 CFI 與全文索引）；原書沒有指紋時略過比對並補寫。
- **字型納入本 Epic**：進入字型管理時探測自訂字型，失效者標示並可重新連結（字型家族名稱須相同）。
- 不新增 ADR（取捨可輕易反轉）。
- **規格審查修訂（同日）**：依 `reviews/review-spec.md`（3 Critical／7 Important／3 Minor）全數處理：EPUB 指紋比對明訂先取 OPF identifier、Re-link 改為先驗證後持久化授權、回傳型別改 sealed class、探測防重入與重新開書復位（當時另加「以路徑作為視圖 `ValueKey`」，後於工單審查 C-1 撤回）、匯入服務併入 `LibraryReaderFeatureRepositories` bundle、探測改走背景佇列通道＋3 秒逾時、字型探測狀態以 id 保存、列出 ARB key。修訂明細見 spec.md「Further Notes」。

## Scrum Master 結論（2026-09-28 `/to-tickets`）

`issues.md` 已產出，拆成 4 個垂直切片（皆為 `ready-for-agent`）。spec.md 原建議的 4 片偏向按層切（原生／服務／UI），改為每片可獨立展示：

- **Issue 0**（prefactor，不改行為）：`ReaderScreen` 改用「目前生效的檔案路徑」（閱讀視圖維持原 GlobalKey）；匯入服務併入 `LibraryReaderFeatureRepositories` bundle。
- **Issue 1**（Blocked by 0）：原生探測＋`ReaderScreen` 錯誤視圖分辨權限失效／找不到檔案（不含按鈕）＋真機驗證。放在 Issue 0 之後是為了避免同時改 `ReaderScreen` 衝突，非邏輯依賴。
- **Issue 2**（Blocked by 1）：`BookImportService.relinkBook`＋錯誤視圖重新選取按鈕＋成功後重新開書。使用者決定服務層與 UI 維持一片，不拆。
- **Issue 3**（Blocked by 1，可與 Issue 2 平行）：字型管理失效標示與重新連結。

- **工單審查修訂（同日）**：依 `reviews/review-issues.md`（1 Critical／4 Important／4 Minor）處理。
  - C-1 撤回「閱讀視圖改用 `ValueKey`」：會破壞既有 GlobalKey 控制鏈。審查建議改外包 `KeyedSubtree`，但這也無效，因為同一幀內 GlobalKey 換位置時 Flutter 會搬移既有 State。改為保留 GlobalKey，依賴「錯誤視圖把閱讀視圖移出樹」保證會建立新實例，並以測試釘住，spec.md 同步更正。
  - I-1：重複檢查排除原書自己。
  - I-2：取消選檔不顯示 SnackBar。
  - I-3：`FakeBookImportService`／`_ThrowingImportService` 同步實作 `relinkBook`。
  - I-4：ARB 為四份（含 `app_zh.arb`），改完執行 `flutter gen-l10n`。
  - Minor：探測結果以型別化欄位保存、明訂 widget Key 與選擇器 typedef、補 `library_screen_dependencies_test.dart`。

## Issue 0 完成記錄（2026-09-28）

分支 `epic-15/issue-0`，共 4 個 commit（依 `plans/plan-issue-0.md` 逐 Task 提交）：

1. `681363ff` — `refactor(library): LibraryReaderFeatureRepositories 新增 bookImportService 欄位`
2. `65ca731d` — `refactor(reader): ReaderScreen 新增 bookImportService 參數並由 buildReaderScreen 轉交`
3. `f4ea11a6` — `refactor(reader): 閱讀器開單書搜尋時轉送 bookImportService，main.dart 填入實例`
4. `24b81d90` — `refactor(reader): ReaderScreen State 改讀 _activeFilePath 取代 widget.filePath`

完整 `flutter test`（執行時 commit `24b81d90`）：2941 通過、1 跳過、1 失敗。唯一的失敗是 `test/wifi_transfer/wifi_transfer_http_server_test.dart` 的 `activeTransfersNotifier` 案例，與本 Issue 範圍無關——已在乾淨的 BASE（`a06e7c20`）重現同樣失敗，確認為既有問題，未為此修改範圍外程式碼。`flutter analyze` 乾淨（`No issues found!`），`node tool/check_l10n_hardcoded_strings.js` 通過（本 Issue 不新增字串）。

**2026-09-28 Issue 0 附帶修正：WiFi 傳書下載許可測試（缺陷，直接 TDD）**。Issue 0 完整 `flutter test` 唯一的失敗 `wifi_transfer_http_server_test.dart`「下載期間 activeTransfersNotifier 維持在 1…」（epic-51 以 PR #290 修過的同一個測試），經程式審查 M-4 確認在 `main`（`a06e7c20`）單獨執行同樣穩定失敗、與 Issue 0 無關；使用者決定在本 Issue 記錄並修正。

- **症狀**：失敗的是最後一個斷言——用戶端 `drain()` 讀完後只等一個 `Duration.zero` 就斷言許可數為 0，實際仍是 1。
- **根因**：伺服器在 `wrapStreamWithCleanup` 的 `controller.done` 之後才釋放許可；背壓下最後的 done 事件要等 socket 寫出、訂閱恢復後才送達，與用戶端讀完回應是兩個獨立 I/O 事件，先後不固定。暫時性探針實測 5 輪皆在讀完後第 2 個事件循環歸零（0～5 ms）——許可確實會釋放，伺服器行為正確，是測試的時序假設錯誤（與 epic-51 同一類）。
- **修正**：新增測試輔助函式 `_waitForActiveTransfers()`，以監聽 `activeTransfersNotifier` 等待歸零（5 秒逾時即 `fail`，逾時代表許可真的沒釋放），取代「等一個 tick」。正式程式碼不動。
- **驗證**：修正前穩定失敗（main 與本分支皆然）；修正後該檔連跑 3 次 `+42: All tests passed!`；`flutter analyze` 乾淨。
- 程式審查（`reviews/review-issue-0-wifi-test-fix.md`，0 Critical／0 Important／3 Minor）後：同檔另一處相同寫法（3 位元組下載後只等 `Duration.zero` 就斷言歸零，當時仍通過）一併改用 `_waitForActiveTransfers()`（M-3）；註解不再寫死「第 2 個事件循環」實測值（M-2）；等待後的 `expect(..., 0)` 刻意保留以表達斷言意圖（M-1）。該檔連跑 3 次 `+42: All tests passed!`。

## Issue 1 完成記錄（2026-09-28）

分支 `epic-15/issue-1`，共 3 個 commit（依 `plans/plan-issue-1.md` 逐 Task 提交）：

1. `eacad404` — `feat(reader): 新增 content:// 存取探測 probeStorageAccess（epic-15 Issue 1）`
2. `60e5831b` — `feat(android): ReaderResourceChannel 新增 probeUriAccess 存取探測（epic-15 Issue 1）`
3. `98c94d32` — `feat(reader): 開書失敗時探測 content:// 存取狀態並分流錯誤說明（epic-15 Issue 1）`

完整 `flutter test`（執行時 commit `98c94d32`）：2966 通過、1 跳過、0 失敗。`flutter analyze` 乾淨（`No issues found!`），`node tool/check_l10n_hardcoded_strings.js` 通過。

真機驗證（Task 4）當時未執行：實作環境無 Android 實體裝置（`flutter devices` 僅見 Edge web）。

**2026-09-28 真機驗證與修正（`/diagnose`）**。真機 `3CEF42ECD491687`：資料夾匯入的 PDF（`Download/TEST/黃仁勳傳_天下出版.pdf`）從資料夾刪除後開書，畫面顯示通用的「無法載入書籍」，而非「找不到檔案」說明。

- **症狀**：logcat 顯示 `probeUriAccess: unknown error`，例外為 `IllegalArgumentException: Failed to determine if ... is child of ...: java.io.FileNotFoundException: Missing file for ...`。
- **根因**：tree URI 的檔案被刪除時，ExternalStorageProvider 在自己的程序丟出 `IllegalArgumentException`；經 `DatabaseUtils.readExceptionFromParcel` 跨程序傳回時只剩例外種類與訊息，`cause` 為 `null`。原本只依例外類型分類，因此落入 `unknownError`。第一版修正「沿 cause 鏈尋找 `FileNotFoundException`」經真機證實無效（cause 已遺失），已捨棄。
- **修正**（`c64c8764`）：新增 `classifyProbeUriException()`；遇到 `IllegalArgumentException` 時呼叫 `probeTreeRootAccess()` 查詢匯入資料夾根文件——資料夾讀得到、書讀不到判定 `fileNotFound`；資料夾權限被收回判定 `permissionRevoked`；其他（非 tree URI、資料夾也讀不到）維持 `unknownError`。不依賴例外訊息文字。
- **驗證**：Kotlin 單元測試 `ProbeUriAccessClassifierTest` 6 個通過（依真機例外形狀建構，`cause` 為 `null`）；同一真機重測，logcat 顯示 `probeUriAccess: fileNotFound`，畫面顯示「找不到檔案」說明。完整 `flutter test`（commit `c64c8764`）：2966 通過、1 跳過；`flutter analyze` 乾淨。
- **仍未在真機驗證的情境**：撤銷資料夾授權（`permissionRevoked`）、資料夾匯入 EPUB、單檔匯入的檔案被刪除。

以 PR #293 合併進 `main`（`43e00ef0`）。

## Issue 2 完成記錄（2026-09-29）

分支 `epic-15/issue-2` 的 commit（依 `plans/plan-issue-2.md` 逐 Task 提交，之後依程式審查修正）：

1. `d32936f2` — `feat(library): BookImportService 新增 relinkBook 原地重新連結書籍（epic-15 Issue 2）`
2. `03a2f919` — `feat(reader): 錯誤畫面重新選取檔案並原地重新開書（epic-15 Issue 2）`
3. `fd708d8e` — `fix(reader): 依程式審查處理 Issue 2 Minor 意見（epic-15 Issue 2）`
4. `ad3483a6` — `docs(epic-15): 新增 Issue 2 實作計畫（含計畫審查與程式審查修訂）`

- **計畫審查**（`reviews/review-plan-issue-2.md`，0 Critical／0 Important／4 Minor）：
  - 採納 M-1：失敗 SnackBar 先收掉舊的再顯示。
  - 採納 M-4：選檔後先確認 `mounted`。
  - 不採納 M-2：`_isProbingAccess` 必定已是 false。
  - 不採納 M-3：`file.path` 是 file_picker 的快取暫存檔，不能當成書的檔案路徑。
  - 使用者決定保留 EPUB／PDF／AZW3 格式限制，以及「EPUB 版面偵測重新觸發」這段防禦。
- **程式審查**（`reviews/review-issue-2.md`，0 Critical／0 Important／4 Minor），使用者決定全部依建議處理：
  - M-1：Re-link 成功時收掉上一次的失敗提示。
  - M-2：移除 widget test 中永遠會通過的「記錄不變」斷言。
  - M-3：EPUB identifier 指紋不符時，退回 SHA-256 再比對一次。
  - M-4：記為已知限制。
  - 另外把 `_existingFilePaths` 被擠開的說明註解搬回原位。
- **已知限制**：
  - 資料庫存的是 EPUB identifier、重新連結時卻讀不到 identifier，仍會判定為內容不同（程式審查 M-3 的反方向，無從補救）。
  - `updateBook` 寫入失敗時，已持久化的授權與落地複本不會回收（程式審查 M-4）。原生端沒有釋放授權的方法；複本檔名固定，重試時會覆寫。
  - 同一個檔案以不同 URI 形式出現時，「已在書庫中」檢查抓不到，例如資料夾匯入的 tree URI 和單檔選取的 document URI。這沿用既有匯入的重複偵測方式。

完整 `flutter test`（執行時 commit `ad3483a6`，`--concurrency=1`）：3004 通過、1 跳過、0 失敗。`flutter analyze` 乾淨（`No issues found!`），`node tool/check_l10n_hardcoded_strings.js` 通過。

**Issue 2 真機驗證（2026-09-29，使用者執行）**：使用者回報「測試通過」，裝置型號與是否也測了 PDF 未記錄。

- **驗證方式的更正**：計畫原本要求「在系統設定或以 adb 撤銷授權」，這個前提是錯的。App 靠的是 SAF 持久化 URI 授權，它不在安裝時要求、不會出現在系統設定的權限頁面，沒有 root 的裝置也無法撤銷。因此 `permissionRevoked` 的真機情境無法主動重現，改用「搬移原始檔案」觸發 `fileNotFound`。兩者出現同一個「重新選取檔案」按鈕，也走同一條重新連結流程，只差錯誤說明文字；說明文字的分流由 widget test 驗證。計畫 Task 3 已同步更正。Issue 1 的驗證步驟有同樣的錯誤前提，所以 Issue 1 記錄中「撤銷資料夾授權」這個情境也無法用這個方式補驗。
- **執行的情境**（依計畫 Task 3，使用者回報全部符合預期）：
  1. 以資料夾匯入 EPUB，讀到中間，加一條劃線、一個書籤。
  2. 把原檔搬到另一個資料夾後開書：顯示「找不到原始檔案」說明與按鈕。
  3. 選另一本 EPUB：被拒絕，顯示「內容不同」提示。
  4. 選回原書的新位置：直接開書，閱讀位置、劃線、書籤都保留。
  5. 返回書架：分類、封面、書名不變。
  6. 重開 App 後再開同一本書：正常開啟。
- **仍未在真機驗證的情境**：`permissionRevoked`（理由見上）；PDF 的重新連結（使用者未說明是否有測）。

以 PR #294 合併進 `main`（`ed315bf6`）。

## 目前狀態

Issue 2 已合併（PR #294）；下一步 Issue 3（字型管理標示讀不到的自訂字型，並可重新連結）。
