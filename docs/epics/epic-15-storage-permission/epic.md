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

## 目前狀態

Scrum Master 完成（`issues.md`）。下一步：認領 Issue 0，撰寫 `plans/plan-issue-0.md`。
