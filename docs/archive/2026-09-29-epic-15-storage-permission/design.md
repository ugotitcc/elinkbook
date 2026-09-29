# Design：儲存權限失效偵測與復原

## 問題陳述

書籍與字型匯入不複製檔案，直接以 SAF 取得的 `content://` URI 搭配 `takePersistableUriPermission()` 持久化授權引用原始檔案（見 ADR 0002、ADR 0021）。專案初期曾實際發生「部分裝置重新選取子資料夾體驗不佳」的狀況——使用者原本已授權的檔案/資料夾，在某個時間點後存取失敗，需要重新走一次 SAF 選取流程。

## 目前風險狀態

- 問題曾在專案初期實際發生過，但具體症狀（例如：每次重啟就要求重新選、還是特定操作後才觸發）與根本原因未查明。
- 開發至今所有測試機皆未再重現，期間程式碼並未針對此問題做過任何刻意修復——不確定是問題已隨其他改動間接消失，還是純粹沒有再撞到觸發條件（例如特定廠商 ROM 的背景權限自動回收機制，如小米/華為/OPPO 等 ROM 常見的「自動清理權限」功能）。
- 目前沒有具體使用者回報或可鎖定的裝置/ROM 清單。

**結論：問題目前的可重現性未知，風險等級無法精確評估，但曾經真實發生過，不宜視為「已解決」直接關閉追蹤。**

## 既有防禦現況（容易被忽略的既有程式碼事實）

- **單檔匯入已有退路**：`book_import_service_impl.dart` 的 `_importSingleFile` 在 `takePersistableUriPermission` 失敗時，會自動退而求其次把檔案內容複製一份到 App 私有儲存空間，改用本機複本的真實檔案路徑，不再依賴原始 `content://` URI 之後是否還能讀取。這正是「單檔匯入至今未再重現權限問題」的關鍵防禦機制，不是問題已自行消失。
- **資料夾匯入沒有這條防禦**：`importFolder` 為求效能，子檔案共用資料夾層級已取得的 Tree URI 授權（呼叫 `_importSingleFile` 時傳入 `takePermission: false`），刻意跳過上述複製退路。因此資料夾匯入的書籍完全沒有這層保底，是未來若權限被撤銷時風險最高的一群，候選補強方向應優先聚焦此路徑。

## 已排除的方向

### `MANAGE_EXTERNAL_STORAGE`（全域儲存權限，Android 11+ All Files Access）

一次授權即可長期存取所有外部儲存空間，不需逐檔/逐資料夾重新選取，理論上能徹底解決問題。但排除，原因：

- App 已規劃上架 Google Play。Play 政策將此權限保留給檔案總管／備份／防毒等特定類別 App，「電子書閱讀器」申請此權限通過審核的機率低，且有被下架風險。
- 產品仍須維持非 Google Play 商城（側載）安裝路徑正常運作，若真的走這條路，還需額外處理「Play 版本受限、側載版本不受限」的雙軌相容性，進一步墊高成本。

決策記錄於 [ADR 0029](../../adr/0029-storage-permission-saf-resilience-over-manage-external-storage.md)。

## 候選補強方向

不新增任何權限，改為強化既有 SAF 架構的容錯與使用者引導。以下方案已依 [Epic 與 Design 審查報告](./reviews/review-epic-and-design.md) 修正原案的技術可行性盲點。

### 1. 失效偵測：開書當下按需（JIT）串流探測，不查 persisted permission 表、不做背景輪詢

原案曾規劃檢查 `ContentResolver.getPersistedUriPermissions()` 是否仍列出對應 URI，經審查確認不可行並已推翻：

- 資料夾匯入書籍的 `Book.filePath` 存的是子檔案 Document URI，但 `getPersistedUriPermissions()` 只會列出當初 `takePersistableUriPermission` 核發的頂層 Tree URI——兩者字串必定不同，若照原案比對，所有資料夾匯入書籍會 100% 被誤判為權限失效。
- 即使 URI 對得上，這個 API 也只是查系統內部的授權登記表，無法反映檔案是否已被移動、改名、刪除或 SD 卡已拔出——授權登記仍存在，不代表檔案仍可實際開啟。

改採：**在使用者實際開啟書籍/字型檔案時**（不做定期於背景的輪詢喚醒），原生端直接嘗試 `contentResolver.openInputStream(uri)` / `openFileDescriptor(uri, "r")`，並精確區分捕捉到的例外類型：

- `SecurityException` → 判定為「權限已撤銷」，導向下方第 2 點的重新授權流程。
- `FileNotFoundException` → 判定為「檔案已被移動/刪除/來源已不存在」，同樣導向重新選取，但錯誤文案需與「權限撤銷」區分——換一個檔案通常無法解決，需先請使用者確認原始檔案是否仍存在。

明確排除「定期於背景檢查」：本產品首要目標為 E-Ink 裝置，長時間仰賴 Deep Sleep 待機，背景輪詢會喚醒 CPU 並發動跨行程 Binder IPC 查詢，對續航傷害顯著；且「使用者當下沒有要看的書」是否失效，對讀者體驗並無實質意義，一律收斂為「開書當下按需檢查」。

### 2. 主動提示復原 + 單書 Re-link 資料流

偵測到失效時，明確告知使用者「該檔案存取已失效，請重新選取」，直接導向對應的 SAF 選取流程，而非讓使用者自行從錯誤訊息猜測該怎麼做，也不要整批要求重新走一次完整匯入流程。

**Re-link 資料流（原案缺失，本次補齊）**：

- SAF 回傳的新 `content://` URI 字串不保證與原始字串一致（不同選取路徑可能導致 Document ID 編碼微調、第三方文件提供者核發不同 session token、或使用者將檔案搬移到新目錄）。若不處理這個落差，重新選檔會被系統當成一本全新的書匯入，原書 `Book.id` 關聯的閱讀進度、劃線、筆記、書籤會變成孤兒記錄。
- 修復流程：使用者重新選取原始檔案 → 對新 URI 呼叫 `takePersistableUriPermission` 持久化 → 呼叫 `LibraryRepository.updateBook(book.copyWith(filePath: newUri))` 原地更新既有記錄，`book.id` 不變，完整保全所有關聯的劃線/筆記/書籤/進度。`updateBook` 與 `Book.copyWith(filePath: ...)` 皆已是現有可用介面，這條修復路徑不需要新增架構。
- **範圍界定**：本輪 Discovery 僅涵蓋「單書按需引導修復（In-place Re-link）」。資料夾層級的批次重新對齊（重新選取整個資料夾後，自動比對幾十本書各自對應哪個新的子檔案）需要額外的檔名/內容特徵比對機制，複雜度高，且目前 `books` 表也沒有 `parentTreeUri` 之類的欄位可供對齊；明確排除於本輪候選方案範圍外，留待未來有實際批次失效案例時另行評估。

### 3. 原生例外透傳規範

`ReaderResourceChannel.kt` 目前對 `readContentUriAll`／`cacheBookForServing`／`readCustomFontBytes` 一律以 `catch (e: Exception) { null }` 統一吞掉例外回傳 `null`（部分方法有 `Log.w` 落地原始例外供 logcat 除錯，但未透傳給 Dart 端）。Dart 端因此拿不到「是權限失效還是檔案不存在」的區分，無法精準彈出對應的復原引導。

修補方向：原生端改用 `result.error(errorCode, message, null)` 依例外型別回傳明確錯誤碼（例如 `PERMISSION_REVOKED`／`FILE_NOT_FOUND`），Dart 端在開書/讀字型失敗處理中依錯誤碼分流，觸發第 2 點所述的 Re-link 引導；非上述兩類例外（例如 `IOException`）維持現行通用錯誤處理，不強求精確分類。

### 4. 字型降級與 UI 呈現邊界

- **自訂字型失效**：依 ADR 0021 與現行 WebView fallback 行為，字型讀取失敗會自動退回系統預設字型，不中斷開書、不彈錯誤對話框（靜默降級）。修復入口收斂於 `FontManagementScreen`（提供「重新連結字型檔案」），不在閱讀器內強迫使用者當場處理。
- **書架 vs 閱讀器**：`LibraryScreen` 載入書架列表時嚴禁批次探測所有書籍的權限有效性，避免書籍數量多時造成 I/O 卡頓與 E-Ink 殘影。所有失效偵測、提示與 Re-link 引導一律收斂在使用者實際點擊開書後的 `ReaderScreen` 錯誤視圖中，書架維持純靜態呈現、交互單純。

### 5. 相容性

以上四者皆與現有 ADR 0002／ADR 0021 架構相容，不改變「不複製檔案、直接引用原始檔案」的既有原則。

## 成因分析假說（尚未驗證，供未來重現時靶向排查）

專案初期「部分裝置重新選取子資料夾體驗不佳」的根本原因目前不明確。以下 4 項是 Android SAF 架構中已知的常見失效機制，列為待驗證假說，**不是已確認成因**：

1. **Tree URI 與 Child Document URI 授權不相容**：部分廠商 ROM（如華為 EMUI、早期 MIUI）在 App 重啟後，可能無法正確將 Tree 權限繼承給子文件，直接對子文件 URI 開啟串流會拋出 `SecurityException`，需以 `DocumentsContract.buildDocumentUriUsingTree` 包裝後才能合法存取。
2. **SAF 持久化授權配額上限**：Android 對每個 App 持有的 persistable URI 數量設有配額（Android 10 之前為 128，Android 11+ 為 512）。使用者選取大量目錄/書籍時，若超過配額，新的 `takePersistableUriPermission` 呼叫可能被系統拋出例外拒絕。
3. **外接 MicroSD 卡重掛載**：E-Ink 裝置使用者經常插拔 SD 卡；卸載重掛載時 Volume UUID 變動，可能導致原 Tree URI 永久失效。
4. **廠商 ROM 背景權限自動清理**：小米/華為/OPPO 等客製化 ROM 的「手機管家」類機制，具備閒置 App 權限自動撤銷的功能。

## 開放問題／後續評估觸發條件

- 若未來再次觀察到「重新選取子資料夾/檔案」的實際重現案例（不論是內部測試或使用者回報），應優先記錄：裝置型號、Android 版本、廠商 ROM、觸發前的操作序列（是否曾重啟 App／背景待機多久／是否手動清除過背景 App），並對照上方「成因分析假說」逐一排除，判斷是否命中特定假說。
- 若確認是特定廠商 ROM 的「背景權限自動回收」機制所致，候選補強方向的「按需失效偵測＋主動提示＋Re-link」仍然適用，且可能需要額外在該類 ROM 上引導使用者關閉自動清理／加入白名單（需視實際廠商而定，屬於後續 Architecting 階段的細節）。
- 若屆時判斷仍缺乏足夠案例佐證投入產出比，可以繼續維持 Discovery-only 狀態、不排入 Issue 拆分。
