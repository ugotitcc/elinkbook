# `epic-67-book-update-detection` 書籍更新版偵測與取代

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-67-book-update-detection/`
**關聯 PRD 章節：** 圖書庫管理（匯入）；詞彙見 `CONTEXT.md`「書籍更新版」「書籍內容指紋」；架構決策見 [ADR 0040](../../adr/0040-book-update-keeps-identity-fingerprint.md)

## 背景

出版社可能釋出同一本書的修訂檔。現況：

- 本機匯入（`book_import_service_impl.dart` 的 `_existingFilePaths()`）只比對來源 URI，更新檔會被當成全新的一本書，舊書的閱讀進度、書籤、劃線、備註留在舊書上。
- 雲端／遠端下載以 `cloud_file_id`、`remote_book_id` 或內容指紋偵測重複；EPUB 指紋取 OPF identifier，更新版 identifier 通常不變，會被判為「已存在」而跳過，更新檔進不來。
- `relinkBook` 只處理「同一份檔案換存取路徑」，內容必須相同，不處理內容變動。

## Discovery 定案（2026-11-03 `/grill-with-docs`，並依 `reviews/review-epic.md` 修訂）

1. **處置**：偵測到更新版時由使用者選「取代」（預設）／「並存」／「跳過」。
2. **格式一致為先決條件**：新檔格式必須與舊書相同（TXT／MD 互換也不算相同），格式不同者一律視為獨立新書，不進入更新版候選。自動判定與手動入口共用此規則。
3. **身份判定兩層**：EPUB 的 OPF identifier 相同＝高信心；其他格式或 identifier 不同時，書名＋作者完全相同＝疑似，必須使用者確認，不自動取代。
   - 比對前先正規化：去除首尾空白、忽略大小寫、全形半形視為相同。
   - 作者為空（null 或空字串）時**不進入第二層**；這類書只能靠 identifier 或手動入口更新。
   - 模糊比對僅用於更新版判定，不用於雲端／遠端的重複偵測（詞彙表已修訂）。
4. **重複 vs 更新版**：整檔 SHA-256 完全相同＝重複，跳過；身份相同但整檔雜湊不同＝更新版。EPUB 因此需多算一次整檔雜湊。
   - 資料庫不存整檔雜湊（EPUB 指紋是 identifier），故需現場讀舊檔計算；只在 identifier 命中時才算，頻率低，**不新增 `file_sha256` 欄位**。
   - 舊檔讀不到（SAF 權限遺失、原檔已刪）時降級：視為更新版，提示「舊檔已無法存取」，取代同時修復檔案連結。
5. **觸發**：匯入時自動比對，並提供書籍動作「用新檔案更新此書」（略過自動判定，仍須格式相同）。
6. **範圍與互動通道**：
   - 前台本機匯入：匯入完成後彈出彙整清單，每本一個選項，提供「全部取代」「全部跳過」。
   - 背景下載佇列（Google Drive／OneDrive、Calibre）：不彈對話框。下載完成後偵測到更新版，該項目標為「待確認更新」，留在下載面板，由使用者自行點開處理，不打斷閱讀。
   - 選檔階段（`CloudBrowserScreen`、`RemoteCatalogScreen`）檔案尚未下載，只能比對雲端／遠端識別碼、算不出指紋，故維持既有的「已在書庫，仍要下載？」提示不變；使用者選繼續後加入佇列，重複與更新版的真正判定一律在下載完成後執行（2026-11-03 `review-spec.md` C-1 後修訂）。
   - 待確認更新項目的新檔移入 App 私有專屬暫存目錄；清單不跨重啟持久化，重啟後暫存殘留於啟動時清掃。
   - **WiFi 傳輸不納入本 Epic**：維持現狀（指紋相同跳過，其餘當新書）。因為 App 可能在背景，沒有可確認的地方。列為後續工作。
7. **取代的行為**：
   - `Book.id` 與內容指紋維持舊值不重算（ADR 0040）。
   - 閱讀進度、書籤、劃線、備註、分類、單書版面偏好設定全部保留。
   - **註記失效不持久化、不在清單標示**（不加欄位，維持 ADR 0040 免動 PocketBase）：點擊書籤／劃線跳轉時，若 CFI 解析失敗或章節不存在，降級跳到該註記的 `progression`，並以 SnackBar 提示「位置已變更，已跳至概略進度」。開書時閱讀位置失效，同樣降級用進度百分比。PDF 對應頁碼超出範圍時比照處理。取代對話框提示註記可能偏移。
   - 資產清理清單（取代成功後）：舊實體檔（App 私有落地複本須刪除；`content://` 無撤銷單筆授權的 API，不處理）、舊合成檔（TXT／MD／CBZ）、舊封面（新檔沒有封面時刪除並清空封面欄位）、全書字元數重置、該書全文索引清除並重建、固定版面判定重新偵測。書名、作者、封面以新檔為準。
8. **批次暫存**：批次匯入若預先處理了新檔，使用者選「跳過」或離開時，暫存檔須立即清理，不留在儲存空間。
9. **多候選**：新檔對到多本舊書時，由使用者從候選清單挑一本或選「當成新書」；identifier 命中者排最前。
10. **失敗處理**：先處理新檔（複製、合成、解析中繼資料），全部成功才換掉舊檔並更新資料庫；任一步失敗保留舊書不動。舊檔不保留、不提供復原。
11. **`relinkBook` 相容**：被取代過的書，指紋與現存檔案不符，既有 `relinkBook` 會回 `contentMismatch`。處置：內容不符但格式相同時，改為詢問使用者「強制重新連結」。此規則對所有書通用，不另記錄哪本書被取代過。

## 已知代價

見 ADR 0040「後果與已知代價」：另一台裝置單純匯入同一份新檔，整檔雜湊格式會成為另一本書；資料庫指紋不再等於現存檔案雜湊。

## 待辦

- Architecting（`spec.md`）與 Issue 拆解（`issues.md`，6 個 Issue）已完成；Issue 5（Foliate 降級）已合併（PR #383，見 `plans/plan-issue-5.md`；該 PR 另衍生 PR #382，修正 `main` 在採用的 Flutter 3.41.9 編譯失敗的字典設定畫面）。下一步為 Issue 1（核心）與其餘 Issue 的 `plans/plan-issue-N.md` 與實作。
- 新增的使用者可見字串（書籍動作選單、更新確認對話框、批次清單、註記偏移 SnackBar、待確認更新狀態、強制重新連結確認）須同步登錄在四份 ARB 檔：`app_en.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_zh_TW.arb`。
- 後續工作：WiFi 傳輸的更新版處理。

## Issue 1 計畫與實作

- **計畫文件**：[plan-issue-1.md](plans/plan-issue-1.md)
- **實作分支**：`epic-67/issue-1-detect-and-replace`
- **核心架構與決策定案**：
  - **D1（重複 vs 更新版的舊檔雜湊）**：舊書 `id` 與 `contentFingerprint` 取代後嚴格保留（落實 ADR 0040，PocketBase 免更動 schema）。判定「重複／更新版」時，EPUB／PDF／AZW3 現場雜湊舊書 `filePath` 的整檔 SHA-256（舊檔讀不到 → 降級為更新版並記入 `unreadableCandidateBookIds`）；TXT／MD／CBZ 的 `filePath` 是合成／重建後的落地檔、沒有原始檔，改比對儲存的 `contentFingerprint`（原始檔 SHA-256）。已被取代過的 MD 因指紋過期，之後會被判為更新版（可由使用者跳過），列為已知限制。
  - **D2（整檔相同的重複直接略過）**：`importFiles`／`importFolder` 偵測到 `DetectedDuplicate` 時累加 `skippedDuplicateCount` 並略過，不產生候選也不寫入。代價：不同 URI、內容相同的 EPUB／PDF 不再能重複匯入。
  - **D3（取代採嚴格模式）**：`replaceBook` 解析新檔時，`PlatformException`、DRM、空 TXT／MD、無頁面 CBZ、KF8 解析例外一律回傳 `newFileParseFailed`（永不拋例外，舊書不動）；`MissingPluginException`（Windows 無原生端）維持降級，與匯入一致。偵測階段（`detectBookUpdate`、`_peekIdentity`）永不拋例外，失敗視為身份空白。
  - **D4（舊檔可讀性以集合表達）**：`BookUpdateCandidate.unreadableCandidateBookIds` 為「舊檔讀不到的候選書 id 集合」（空集合＝全部可讀），是 spec 單一旗標的超集。更新暫存目錄（`update_staging`）與 `discardUpdateCandidate` 另行提供。
  - **F6（字元數欄位處理）**：`totalCharacterCount` 欄位在現行程式碼中無讀寫操作，維持 no-op，不進行額外計算。
  - **F8（封面快取失效職責劃分）**：Service 層不依賴 Flutter 繪圖引擎快取；取代成功後，封面圖片快取失效（`PaintingBinding.instance.imageCache.evict(FileImage(File(coverPath)))`）必須由 UI 層（Issue 2 批次清單與 Issue 3 手動更新）主動處理。
  - **殘餘風險**：換名（檔案）與 `updateBook`（資料庫）無法放進同一交易。順序為「全部暫存成功 → 換名 → `updateBook` → 清舊資產」；換名成功但 `updateBook` 失敗時，磁碟已是新檔、資料庫仍是舊中繼資料，**程式沒有還原機制**，再執行一次取代即可修復（有測試證明）。任何失敗分支只會清掉暫存名稱檔。
  - **已知限制：取代沿用舊指紋（審查 I-5，人類決定維持）**：取代不重算整檔雜湊（計畫 M-4）。PDF／AZW3 的指紋是整檔 SHA-256，取代後仍是舊內容的雜湊；第二層（書名＋作者）命中且 identifier 不同的 EPUB，取代後指紋仍是舊 identifier。因此被取代過的書之後執行 `relinkBook` 會回 `contentMismatch`，由 Issue 3 的「強制重新連結」處理（見 ADR 0040、本 Epic 決策 11）。
  - **審查後修正**：換名前不再先刪目標檔（`File.rename` 本身原子覆蓋）；取代任何失敗分支改依 `bookId` 掃除所有 `.staging` 暫存檔（含寫到一半的半成品）；舊封面改在 `updateBook` 成功後才刪；同一本書的 `replaceBook` 以每書序列化避免暫存檔名碰撞；`importCandidateAsNewBook` 例外一律回傳 null 並清掉落地複本，書名退路在無 `displayName` 時改用 `sourceUri`；更新版暫存複製失敗時退回當成新書匯入，不讓檔案無聲消失。
  - **大批匯入體感效能量測（Review Focus 7）**：
    - 50 本全新 EPUB 匯入：約 125 ms（平均 2.5 ms/本）
    - 50 本重複 EPUB 偵測跳過：約 57 ms（平均 1.1 ms/本）
    - 50 本更新版 EPUB 暫存與偵測：約 164 ms（平均 3.3 ms/本）
    - 注意：以上數字來自 mock channel（中繼資料讀取為記憶體假回應），僅反映服務層本身的開銷，不代表真機原生呼叫與整檔雜湊的耗時；真機大批匯入體感須另行驗證。

## Issue 2 計畫與實作

- **計畫文件**：[plan-issue-2.md](plans/plan-issue-2.md)
- **實作分支**：`epic-67/issue-2-local-import-summary`
- **核心架構與決策定案**：
  - **D1（多候選呈現與並存對話）**：每筆候選書提供單選選項（取代特定書籍、並存、跳過），預設選取第一本取代；無須二層彈窗，結構扁平直覺。
  - **D2（全部取代與全部跳過）**：清單提供「全部取代」「全部跳過」捷徑按鈕，點擊僅批量修改選取狀態，仍須按下「套用」才正式執行，確保使用者保有檢視與確認偏移提示的機會。
  - **D3（不可中斷與不可重入）**：對話框 `barrierDismissible: false`，套用中以 `_applying` 旗標禁用所有按鈕與返回操作，防止重複執行與狀態競爭；以 `PopScope(canPop: false)` 攔截返回鍵並視為取消全跳過處理。
  - **D4（偏移提示常駐）**：只要目前選取包含任何「取代」，即顯示註記可能偏移提示，全選跳過或並存時自動隱藏。
  - **D5（舊檔無法存取提示）**：舊書若於 `unreadableCandidateBookIds` 中且被選為取代，明確提示「舊檔已無法存取，取代後會一併修復檔案連結」。
  - **D6（取代失敗不中斷整批）**：逐筆循序套用；單筆失敗（含拋例外）計入失敗數、補丟棄暫存檔後繼續下一筆；完成後只彈一則 SnackBar，成功與失敗訊息由 `bookUpdateResultWithFailedMessage` 以各語系自帶的分隔標點串接，全為跳過則不顯示。
  - **E-Ink 殘影抑制（計畫審查 M-3）**：傳入 `isEinkMode` 時，對話框設定 `animationStyle: AnimationStyle.noAnimation`，完全抑制過場動畫避免殘影。
  - **F6（並存落在未分類）**：`importCandidateAsNewBook` 依設計建立之新書 `groupName` 預設為未分類，此為已知限制。
  - **F7（雲端／Calibre／WiFi 暫存殘留風險）**：在 Issue 4（下載佇列接線）完成前，背景下載的更新候選暫存檔需待 Issue 4 之啟動清理機制掃除；前台本機匯入（檔案／資料夾）在 Issue 2 已完整落實卸載、取消與套用時的即時清理。
  - **快取失效**：取代成功後主動呼叫 `evictCoverImageCache` 淘汰舊書與新書封面快取（`PaintingBinding.instance.imageCache.evict`），使書架與畫面立即呈現新封面。
  - **卸載防護（Review Focus 1）**：若使用者於選檔等待期間切換畫面，`SourcesHomeScreen` 在 `context.mounted == false` 時無條件呼叫 `discardUpdateCandidates` 丟棄所有候選暫存檔，保證暫存目錄不洩漏殘留。
  - **程式審查修正**：補 `SourcesHomeScreen` 選檔／資料夾匯入途中卸載的 widget test；50 筆清單測試改為真的捲到最後一列並點選，窄螢幕與 E-Ink 各自獨立驗證；清單高度改為螢幕 60%（與計畫一致，`shrinkWrap` 會一次建出全部列，屬已接受的取捨）；候選書清單加非空 `assert`。
  - **真機手動驗證：已通過（2026-11-04，WAVE `TCE70P24B2202374`，debug 版，`main` 提交 `4a0c6c33`）**。測試書為自製 EPUB（同識別碼、內容與封面不同的 v1／v2 多組）。
    - 計畫 Task 4 Step 3 三項情境（1 取代後書名與封面即時更新且進度書籤保留、2 混合批次、3 取消後 `update_staging/` 無殘留）：通過。
    - 補充情境（原計畫未涵蓋）：一次更新 3 本（全部取代）、逐本不同處置（取代／並存／跳過）、全部跳過、5 種情況混合（含疑似更新）、一批 12 檔：全部通過。
    - 尚未涵蓋：失敗路徑（取代途中失敗）、大檔案耗時。

## Issue 4 計畫與實作

- **計畫文件**：[plan-issue-4.md](plans/plan-issue-4.md)
- **實作分支**：`epic-67/issue-4-download-queue-pending-update`
- **核心架構與決策定案**：
  - **D1（偵測先於指紋比對）**：下載完成後先呼叫 `job.detectUpdate(tempPath)`，再進入既有 `computeFingerprint` → `hasDuplicate` → `onDuplicateConfirm` 流程。EPUB 的指紋是 OPF 識別碼，若先比指紋，識別碼相同、內容不同的修訂檔會被「已存在」對話框吞掉、到不了更新版判定。偵測結果為新書／重複／不支援／偵測失敗／暫存複製失敗（`stagedPath == null`）一律回 `null`，走既有流程（重複仍走原對話框）。
  - **D2（新狀態「待確認更新」）**：`DownloadItemStatus.awaitingUpdateConfirmation`，項目攜帶 `updateCandidate`；進入後 `_downloadOne` 立即 return，佇列處理下一筆，不彈對話框、不阻塞；原下載暫存檔隨即刪除（候選已有服務暫存副本）。
  - **D3（結算語意）**：`resolveUpdate(id, choice)`：取代／並存成功 → `done`；失敗 → `failed`（可重試＝重新下載）；跳過 → 項目從面板移除。同一項目以 `_resolvingIds` 集合防止重入；非待確認狀態直接回 failed、不呼叫 job。結算抽出為 `settleBookUpdate`（`library/book_update_settle.dart`），與 Issue 2 的 `applyBookUpdateChoices` 共用；控制器維持來源無關，不 import `screens/` 或匯入服務。
  - **D4（面板對話框取消不丟棄）**：面板點「確認更新」開啟 `BookUpdateSummaryDialog` 時 `discardOnCancel: false`，取消／返回不刪暫存、項目保留可再處理；對話框新增 `applier`（由呼叫端提供套用函式）與可為 null 的 `importService`，`applier` 簽章為 `Future<BookUpdateApplyResult> Function(Map<BookUpdateCandidate, BookUpdateChoice>)`。取消與非預期關閉（`showDialog` 回 null）的保底順序：`!discardOnCancel` → 全 0；有 `applier` → `applier`（全 SkipChoice）；否則 `importService`（審查 I-1、I-2）。
  - **D5（「移除」待確認項目＝跳過）**：`dismiss(id)` 對待確認項目先結算為 `SkipChoice`（刪暫存）再移除，回傳型別改 `Future<void>`；結算中的項目不動作。面板待確認列顯示 `Icons.update`、「待確認更新」標籤與「確認更新」（Key `sources_download_queue_update_review_<id>`）、「移除」兩個按鈕；不畫進度條。`isEinkMode` 傳入對話框以關閉過場動畫。
  - **D6（沿用服務暫存目錄與啟動清掃）**：沿用 Issue 1 服務的 `<documents>/update_staging/`，不另建下載專屬目錄；共用常數 `kUpdateStagingFolderName`，App 啟動時（匯入服務建構之前）於 `main.dart` 呼叫 `sweepUpdateStaging()`，清掉 force-stop 或崩潰殘留；待確認清單不跨重啟持久化。
  - **D7（保底一律「當新書匯入」，不丟棄）**：Issue 1 合併後，雲端／Calibre 的 `import()` 原本丟掉 `importFiles` 回傳值、WiFi 遇更新版會判失敗，檔案靜默遺失。三處改為：殘留的更新候選逐筆 `importCandidateAsNewBook`（帶來源參數），並刪除原落地檔（`permanentPath`／`landedPath`，並存的新書使用服務重新複製的私有檔，原檔已無人引用）。雲端／Calibre 若一本都沒並存成功則丟出例外讓項目標為 failed（可重試，避免「完成」但書庫沒有這本書）；WiFi 回 failed 並刪落地檔。
  - **來源參數補寫**：雲端取代／並存帶 `BookSourceRefs(source, cloudFileId)` 與 `folderName`；Calibre 帶 `source: calibreOpds`、`remoteServerId`、`remoteBookId`、`remoteDownloadUrl`。Calibre 偵測／並存用的 displayName 為 `<title>.<副檔名>`。
  - **快取失效**：`DownloadQueueController` 注入 `onCoverChanged`（`main.dart` 傳入 `evictCoverImageCache`），取代成功時對舊書與新書封面路徑各通知一次；回呼拋例外不影響結算。
  - **程式審查修正**：保底並存全數失敗改為丟例外（項目 failed）；對話框取消保底補上 `applier` 分支；`_deleteIfExists` 吞例外；`onCoverChanged` 以 try/catch 包住；面板顯示結算結果改用事先取得的 `ScaffoldMessenger`，對話框期間該列被卸載仍可顯示提示；補齊面板與對話框缺漏的測試。
  - **真機／模擬器手動驗證：尚未執行**，由人類另行處理（計畫 Task 7 Step 3 的五項情境：Google Drive/OneDrive 更新版下載與 cloudFileId 補寫、Calibre 書庫更新版下載與 remote 識別碼補寫、force-stop 重啟後 update_staging 清掃、整檔相同重複提示迴歸、WiFi 上傳更新版成為新書）；完成後請把結果補記於此。

## Issue 3 計畫與實作

- **計畫文件**：[plan-issue-3.md](plans/plan-issue-3.md)
- **實作分支**：`epic-67/issue-3-manual-update-force-relink`（已合併，PR #391）
- **核心架構與決策定案**：
  - **D1（手動更新不比對身份）**：書架動作選單新增「用新檔案更新此書」（`BookAction.updateBook`），僅檢查檔案格式是否一致，不比對書名、作者或 identifier。
  - **D2（格式檢查優先）**：選檔後由 `detectImportFileFormat`（`displayName` 優先於 URI）判斷格式；若格式不符直接提示 SnackBar 並結束，不彈對話框，不呼叫 `replaceBook`。
  - **D3（強制重新連結通用規則）**：`relinkBook` 支援具名選填參數 `{bool force = false}`。原書有內容指紋且 `force: true` 時，跳過指紋計算與比對，直接完成重新連結；原書無指紋時仍會補寫新檔指紋。格式不符時即使 `force: true` 仍拒絕。
  - **D4（閱讀器對話框詢問）**：`ReaderScreen` 重新選檔時遇 `contentMismatch`，彈出強制重新連結對話框（`showForceRelinkDialog`）；使用者按「強制重新連結」時以 `force: true` 重新呼叫 `relinkBook` 並原地重新開書；按取消則關閉對話框，維持錯誤視圖且不顯示 SnackBar。
  - **D5（快取失效）**：取代成功後主動通知 `onCoverChanged`（`evictCoverImageCache`），去重後移除舊封面與新封面快取。
  - **D6（更新中防護與模態鎖定）**：確認對話框內等待 `replaceBook`，以 `PopScope(canPop: false)` 擋返回鍵，取消與更新按鈕皆停用並顯示處理中文字。
  - **D7（E-Ink 模式支援）**：對話框在 `isEinkMode: true` 時設定 `animationStyle: AnimationStyle.noAnimation` 抑制殘影。
  - **已知限制**：
    - 手動更新與強制重新連結後，既有的書籤、劃線、備註與閱讀進度位置不會因內容改版自動重新對齊，可能因內容不同而偏移。
    - TXT／MD／CBZ 因無指紋比對與 SAF 重新連結需求，不支援 `relinkBook`。
  - **真機／模擬器手動驗證：尚未執行**，由人類另行處理（計畫 Task 4 Step 3 的五項情境：1 書架「用新檔案更新此書」成功與封面即時更新、2 格式不符拒絕、3 閱讀器權限撤銷後重新選檔遇內容不符出現強制重新連結對話框、4 強制重新連結確認後原地開書、5 E-Ink 模式無過場動畫）；完成後請把結果補記於此。

## Issue 6 計畫與實作

- **計畫文件**：[plan-issue-6.md](plans/plan-issue-6.md)
- **實作分支**：`epic-67/issue-6-pdf-degrade`
- **核心架構與決策定案**：
  - **D1（列舉與提示文案沿用）**：回呼列舉沿用 `NavigationDegradedReason`（`readingPosition` 與 `annotation`），訊息文案與 SnackBar 樣式直接沿用既有 `readerNavigationDegradedMessage`，零新增 ARB 鍵值與字串。
  - **D2（不疊加提示）**：開書或跳頁期間若已觸發降級提示，SnackBar 遵循既有行為（非阻塞、短暫提示），不因連續回報而重複堆疊。
  - **D3（開書主動夾頁）**：`_openDocument` 開啟 PDF 完成後，主動檢查初始頁碼 `initialPageIndex` 是否超出合法範圍（`< 0` 夾為 0，`>= pageCount` 夾為 `pageCount - 1`）。若超界，設定 `_startPageIndex` 為合法最後一頁、標記 `_initialPageDegraded = true`，並在 `onViewerReady` 回呼時發出 `onNavigationDegraded(NavigationDegradedReason.readingPosition)` 一次。若中途 unmount（`mounted == false`），不拋出例外亦不通知。
  - **D4（跳頁夾頁取代靜默 return）**：`_jumpToPage(index)` 取代原本超界直接 `return false` 的行為，改為夾到 `pageCount - 1`（若 `< 0` 則夾為 0）、發出 `onNavigationDegraded(NavigationDegradedReason.annotation)`，回傳 `bool degraded` 表示是否發生降級。
  - **D5（超界跳頁不發出暫態高亮）**：`jumpToPageAtRect` 呼叫 `_jumpToPage`，若發生超界降級（`degraded == true`），跳過 `_revealHighlight`，避免在最後一頁錯誤的矩形區域疊加不相干的高亮。
  - **D6（閱讀位置持久化覆寫）**：降級落在最後一頁後，`onPageChanged` 依既有流程正常觸發，閱讀位置直接被最後一頁覆寫，原本超界的頁碼不保留。
  - **D7 / Ruling 1（pending 重定位頁碼超界同步更新）**：`_openDocument` 偵測超界並修正 `_startPageIndex` 時，若 `_pendingReanchorPageIndex != null && _pendingReanchorPageIndex > last`，同步更新 `_pendingReanchorPageIndex = last`，避免旋轉或版面切換時被舊的超界頁碼拉回。
  - **D8 / Ruling 2（高亮超界防禦保護）**：`_setJumpHighlight` 加入頁碼防禦 `pageIndex < 0 || pageIndex >= _controller.pageCount`，防止任何外部或內部非預期路徑以非法頁碼存取 `_pageHighlights` 導致例外。
  - **D9 / Ruling 3（開書負數頁碼防禦）**：`_openDocument` 針對負數頁碼（`start < 0`）統一防禦歸零。
  - **已知限制**：
    - 夾到最後一頁只是「不壞」的安全網，書籤與劃線仍指向舊頁碼（PDF 沒有概略進度可用，與 Foliate 不同）；劃線的頁內矩形座標在新版內容中也可能對不上，屬 spec 已接受的偏移。
    - 降級後閱讀位置會被最後一頁覆寫（D6），原本的超界頁碼不保留。
  - **真機／模擬器手動驗證：尚未執行**，由人類另行處理（計畫 Task 3 Step 3 的四項情境：1 書架 20 頁 PDF 讀到第 18 頁更新成 5 頁後開書開在第 5 頁並出提示不閃退、2 同書在書籤清單點第 18 頁書籤跳到最後一頁出提示、3 雙頁與逐頁翻頁模式落在最後一頁不空白、4 正常 PDF 開書與跳轉不出現提示迴歸）；完成後請把結果補記於此。
