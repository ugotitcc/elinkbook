# Epic 30 — Calibre 遠端書架整合：工單清單 (Issues)

依 `spec.md`（Architecting 產出，已通過 `reviews/review-spec.md` 審查修訂）以 `/to-issues` 拆解為 6 個垂直切片（tracer bullet），每個切片皆貫穿 schema/service/UI/測試整條路徑，可獨立驗收。2026-08-17 與使用者確認：原 `review-spec.md` 附帶建議的 8 工單切法是按解析器/資料/網路/UI 分層的水平切分，不符合垂直切片原則，改為本清單的結構；使用者確認顆粒度與相依關係後定案發布。相依順序：Issue 0 無依賴 → Issue 1 依賴 0 → Issue 2 依賴 0＋1 → Issue 3／4 皆依賴 0＋2（互相獨立、可平行）→ Issue 5 依賴 2。

---

## Issue 0：擴充既有匯入/查詢管線與新增站點表（Prefactor）

**Status:** ✅ 已完成並合併回 `main`（PR [#157](https://git.jigong.org/huthief/elinkBook/pulls/157)，分支 `epic-30-issue-0`，7 個 commit：6 個 Task 各自一個 commit＋1 個審查修訂 commit）。`/superpowers:writing-plans` 產出 `plans/plan-issue-0.md`，`/superpowers:requesting-code-review` 派遣獨立 subagent 審查（`reviews/review-issue-0.md`，本機審查報告依專案慣例不進版控，結論 APPROVED WITH FINDINGS，0 Critical／1 Important／2 Minor）：Important（`plan-issue-0.md` Task 4/6 核取方塊未跟上實際完成狀態）與 2 項 Minor（`Book.fromMap()` 的 `isDownloaded` 多餘防禦性寫法、`ON DELETE SET NULL` 外鍵級聯測試未涵蓋 `ALTER TABLE` 升級路徑）皆已修訂並補測試。全專案 `flutter analyze` 乾淨、`flutter test` 1448 項全數通過、零回歸；審查過程另用獨立 `sqlite3` CLI（跳脫 Dart/sqflite）複驗計畫標記為技術風險的 `ALTER TABLE ADD COLUMN` 搭配 `REFERENCES ... ON DELETE SET NULL`，確認可行，走的是主要路徑而非計畫預先寫好的備援方案。

**依賴：** 無，可立即開始。

**背景：** 本身不含任何使用者可見的遠端書庫功能，是後續全部切片共用的資料層基礎設施（`spec.md`「資料模型與 Schema」「既有匯入管線擴充」已定案介面）。與尚未實作的 `epic-29-cloud-import` 有三個共用觸點（`importFiles()` 的 `source` 參數、`books` schema 版本號、`findByContentFingerprint()`），`spec.md`「與 `epic-29-cloud-import` 的順序無關性」已定案處理方式：**實作前先檢查這三處目前是否已存在**（可能因 `epic-29` 先落地而已經加過），已存在則直接沿用、只疊加本 Epic 需要的新參數/方法，不重複宣告。

**What to build：**
- 新表 `remote_servers`（id/name/base_url/type/username/allow_insecure/created_at/last_accessed_at）。
- `books` 表新增四欄：`remote_server_id TEXT`（嘗試以 `REFERENCES remote_servers(id) ON DELETE SET NULL` 內聯宣告；若實測 SQLite／sqflite 版本不支援 `ALTER TABLE ADD COLUMN` 搭配 `REFERENCES`，改為不宣告 FK 約束，`RemoteServerRepository.deleteServer()`——Issue 1——改在交易內手動 `UPDATE books SET remote_server_id = NULL WHERE remote_server_id = ?` 達成同等行為，兩者對外行為完全等價）、`remote_book_id TEXT`、`remote_download_url TEXT`、`is_downloaded INTEGER NOT NULL DEFAULT 1`；新增複合索引 `idx_books_remote_lookup ON books(remote_server_id, remote_book_id)`。schema 版本號取實作當下 `books` 表最新版本號 +1，不寫死特定數字。
- `pubspec.yaml`：`xml`／`http` 由 `dev_dependencies` 移至正式 `dependencies`。
- `BookImportService.importFiles()` 簽章擴充：若 `source: BookSource source = BookSource.local` 尚不存在則新增；一律新增本 Epic 專屬的 `remoteServerId`（`String?`）、`remoteBookIds`（`Map<String, String>?`，uri→remote_book_id）、`remoteDownloadUrls`（`Map<String, String>?`，uri→下載當下的絕對 URL）三個可選參數。既有呼叫端不需要任何修改。
- `LibraryRepository` 新增查詢方法：若 `findByContentFingerprint(String fingerprint) → Book?` 尚不存在則新增；一律新增 `findByRemoteBookId(String serverId, String remoteBookId) → Book?`。兩者皆在 `SqliteLibraryRepository` 與 `FakeLibraryRepository` 落地（比照既有介面/實作/Fake 三件套模式）。
- `Book` 模型新增四個欄位：`remoteServerId`、`remoteBookId`、`remoteDownloadUrl`（皆 `String?`）、`isDownloaded`（`bool`，預設 `true`）。
- `BookSource` enum 新增值 `calibreOpds`。

**單元測試要求：**
- Migration 測試：舊版資料庫升級後新欄位皆為 `NULL`（`is_downloaded` 為 `1`），既有資料不受影響；索引確實建立。
- `importFiles()`：傳入新參數時對應 `Book` 記錄正確落地；未傳入時（既有本機匯入情境）行為與現行完全一致，既有測試套件維持全綠、零回歸。
- `findByRemoteBookId()`／`findByContentFingerprint()`：命中/未命中兩種情境，`SqliteLibraryRepository` 與 `FakeLibraryRepository` 兩層皆須覆蓋。

**驗收標準：** `flutter analyze` 乾淨；`flutter test` 全數通過、零回歸；新查詢方法與擴充參數皆有對應測試覆蓋；`remote_server_id` 外鍵約束的可行性已實測確認並記錄採用的方案（內聯 FK 或應用層等效方案）。

**Blocked by：** 無。

---

## Issue 1：站點管理（新增/編輯/刪除/測試連線）與遠端書庫入口

**Status:** ✅ 已完成並合併回 `main`（PR [#158](https://git.jigong.org/huthief/elinkBook/pulls/158)，分支 `epic-30-calibre-remote-library`，10 個 commit：9 個 Task 各自一個 commit＋1 個審查修訂 commit）。`/superpowers:writing-plans` 產出 `plans/plan-issue-1.md`，動工前先經 `/superpowers:receiving-code-review` 計畫審查（`reviews/review-plan-issue-1.md`，APPROVED_WITH_SUGGESTIONS，2 Important／2 Minor，已全數修訂：OPDS 格式 MIME→副檔名退回判定、下載異常暫存檔清理、href trim、編輯模式密碼語意改在表單層解析而不動 Repository 契約）；實作完成後再經獨立 subagent 程式審查（`reviews/review-issue-1.md`，APPROVED WITH FINDINGS，3 Important／3 Minor，已全數修訂：密碼欄位 UI 文案與類別文件與 Finding 1 修正後語意矛盾、`_save()`/`_delete()` 缺乏例外處理、刪除確認對話框、`baseUrl` 格式驗證）。全專案 `flutter test` 1495 項與 `flutter analyze` 零回歸通過。

**依賴：** Issue 0（`remote_servers` 表）。

**背景：** `spec.md`「站點管理：`RemoteServerRepository`」「OPDS 瀏覽與下載：`OpdsClient`」已定案介面。本 Issue 一併完成整個 `OpdsClient` 契約（含 `OpdsFeedParser`），因為「測試連線」內部就是呼叫 `fetchFeed()`，與後續 Issue 2 的目錄瀏覽是同一份解析邏輯，拆成兩份會是人工製造的重複工作。同時提供進入這整個功能的唯一入口，否則本 Issue 與 Issue 2 建好的畫面都無法從既有 App 導覽到達。

**What to build：**
- `RemoteServerRepository`：`listServers`/`addServer`/`updateServer`/`deleteServer`/`loadPassword`。密碼獨立存 `flutter_secure_storage`（key 格式 `remote_server_password_<id>`），讀取失敗比照 `SyncAccountRepository` 既有先例安全退回 `null`。`deleteServer()` 交易內先檢查該站點是否有 `is_downloaded = 0` 的書籍，有則拒絕刪除並回傳清單（供 UI 顯示示警），確認沒有後才真正刪除。
- `OpdsClient` 抽象介面（`testConnection`/`fetchFeed`/`downloadBook`，含 `OpdsFeed`/`OpdsNavigationLink`/`OpdsEntry`/`OpdsAcquisition` 型別）與真實 `OpdsHttpClient` 實作：HTTP Basic Auth（`username` 為 `null` 則不帶 header）／`allowInsecure` 時單次連線放行憑證錯誤（不可全域關閉驗證）／`OpdsFeedParser` 對所有 `href`（Acquisition／縮圖／導覽／分頁）以 `Uri.resolve()` 轉絕對 URL／分頁循環防護（追蹤已造訪 URL）／格式過濾（MIME type 對應、退回副檔名判斷、皆無法判斷則 `format = null`）。
- `RemoteServerListScreen`（站點清單，含刪除防護的示警對話框）、`RemoteServerFormScreen`（新增/編輯表單，含「測試連線」按鈕）。
- `LibraryScreen` 新增一個獨立常駐入口，導向 `RemoteServerListScreen`（不塞進「匯入」選單，具體視覺位置由實作者依既有 IA 慣例決定）。

**單元測試要求：**
- `RemoteServerRepository`：CRUD 狀態轉換、密碼讀取失敗安全退回 `null`、`deleteServer()` 對「有僅雲端紀錄書籍」情境的拒絕邏輯，`SqliteLibraryRepository`／`FakeLibraryRepository` 兩層皆須覆蓋新增的資料存取。
- `OpdsFeedParser`：純 Dart 單元測試，餵入固定 OPDS XML 字串樣本（含相對路徑 `href` 的真實案例），斷言解析結果的 `href`/`thumbnailUrl`/`nextUrl`/`prevUrl` 皆為絕對 URL。
- `FakeOpdsClient`（`app/test/support/`）驅動 `RemoteServerListScreen`／`RemoteServerFormScreen` 的 widget test：新增/編輯/刪除、測試連線成功/失敗、刪除防護示警對話框。
- 真實 `OpdsHttpClient` 的實際 HTTP 呼叫、憑證處理不做自動化測試，留待真機/人工用真實 Calibre/OPDS 伺服器驗證。

**驗收標準：** 使用者可新增/編輯/刪除/測試連線一個真實 OPDS 站點（含匿名與帳密兩種情境、純 HTTP 與自簽憑證兩種情境）；刪除有僅雲端紀錄書籍的站點會被拒絕並顯示清單；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0。

---

## Issue 2：OPDS 目錄瀏覽＋批次下載＋匯入

**Status:** ✅ 已完成並合併回 `main`（PR [#159](https://git.jigong.org/huthief/elinkBook/pulls/159)，分支 `epic-30-issue-2`，7 個 commit：5 個 Task 各自一個 commit＋1 個審查修訂 commit）。`/superpowers:writing-plans` 產出 `plans/plan-issue-2.md`，動工前先經 `/superpowers:receiving-code-review` 計畫審查（`reviews/review-plan-issue-2.md`，0 Critical／0 Important／3 Minor，已全數修訂：`buildOpdsAuthHeaders` 空白字串防禦、`FormatSelectionDialog` 的 `SingleChildScrollView`、下載中途失敗清暫存檔）；實作完成後再經獨立 subagent 程式審查（`reviews/review-issue-2.md`，APPROVED WITH FINDINGS，1 Important／2 Minor，已全數修訂：Task 4 原訂的「真實持久化」整合測試因 `computeBookContentFingerprint()` 對非 `content://` 路徑呼叫 `Isolate.run()` 與 `testWidgets()` 假時間環境根本不相容（兩次重現皆卡死至 10 分鐘逾時），改移至 `book_import_service_test.dart` 的 plain `test()` 補回等效驗證；類別文件對 `OpdsClient` 生命週期的錯誤描述、死碼移除）。全專案 `flutter test` 1514 項與 `flutter analyze` 零回歸通過。

**依賴：** Issue 0（匯入管線）、Issue 1（`OpdsClient`／站點入口）。

**背景：** 第一個能讓使用者實際「從 Calibre／OPDS 站點下載一本書」的完整可展示切片，也是 Issue 3（重複偵測）與 Issue 4（快取生命週期）依附的主流程。

**What to build：**
- `RemoteCatalogScreen`：進入某個站點後的目錄瀏覽——依 `OpdsFeed.navigationLinks` 分類下鑽、依 `nextUrl` 提供「載入更多」、封面縮圖網格（帶 Basic Auth header，含載入佔位符）、多選勾選批次下載。
- `FormatSelectionDialog`：同一書目提供多個 `OpdsAcquisition` 時彈窗選擇格式；不支援格式（`format == null`）置灰不可選；整本書無任何支援格式時列表中標示不可下載。
- 批次下載為**序列執行**（非平行）：一本下完才下一本，清單逐項顯示等待中/下載中/完成/失敗狀態；下載失敗顯示錯誤並可針對單一檔案手動重試（不自動重試）；下載中可取消（立即清除暫存檔）；暫存於專屬子目錄、UUID 命名。
- 全部下載完成後透過 Issue 0 擴充後的 `importFiles()` 寫入圖書庫：`source: BookSource.calibreOpds`、`remoteServerId`、`remoteBookIds`、`remoteDownloadUrls`（記錄該次下載使用的絕對 URL，供 Issue 4 的重新下載重用）一併帶入。

**單元測試要求：**
- `FakeOpdsClient` 驅動 `RemoteCatalogScreen` 的 widget test：分類下鑽、「載入更多」分頁、格式過濾後的清單、縮圖佔位符、多選狀態、序列下載＋逐項狀態、下載失敗顯示錯誤＋手動重試、下載取消清暫存檔、多格式選擇彈窗（含置灰）。
- `importFiles()` 呼叫時 `source`/`remoteServerId`/`remoteBookIds`/`remoteDownloadUrls` 正確帶入的整合驗證（透過 `FakeLibraryRepository` 觀察寫入結果）。

**驗收標準：** 使用者可從已新增的站點瀏覽目錄、勾選單/多本書下載，成功匯入圖書庫且封面/格式偵測與本機匯入的書無差異；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0、Issue 1。

---

## Issue 3：雙層重複匯入偵測

**Status:** ✅ 已完成並合併回 `main`（PR [#160](https://git.jigong.org/huthief/elinkBook/pulls/160)，分支 `epic-30-issue-3`，3 個 commit：Task 1／Task 2 各自一個 commit＋1 個審查修訂 commit）。`/superpowers:writing-plans` 產出 `plans/plan-issue-3.md`；實作完成後經獨立 subagent 程式審查（`reviews/review-issue-3.md`，APPROVED WITH FINDINGS，0 Critical／1 Important／3 Minor，已全數修訂：Layer 1 的 `findByRemoteBookId()` 補上 try/catch，查詢失敗時視同未命中直接放行勾選；新增 `_pendingDuplicateChecks` 防止快速連點並行觸發兩次查詢；Layer 2「無重複」測試補上 `FakeFingerprintComputer.calls` 呼叫時機斷言；長行斷行）。審查特別確認未重新引入 Issue 2 review 已發現的 `Isolate.run()` × `testWidgets()` 卡死問題——新增的 `ComputeRemoteFingerprint` 可注入函式型別讓 widget/測試皆不直接觸碰真實 `computeBookContentFingerprint()`，`main.dart` 生產環境接上真實函式，經程式碼核對＋實際跑滿整套測試套件雙重驗證排除風險。全專案 `flutter test` 1521 項與 `flutter analyze` 零回歸通過。

**依賴：** Issue 0（`findByRemoteBookId`/`findByContentFingerprint`）、Issue 2（下載/匯入流程）。

**背景：** `spec.md`「重複匯入偵測」已定案雙層檢查設計，比照 `epic-29` 相同機制。與 Issue 4 彼此獨立，可平行進行。

**What to build：**
- 在 Issue 2 建好的目錄瀏覽/下載流程中掛入雙層重複偵測：
  1. **選檔前置檢查**——使用者勾選書籍當下，若該 `(remoteServerId, remoteBookId)` 已存在於某本書（`findByRemoteBookId()` 命中），立即彈出「這本書之前匯入過了，仍要建立新的一份嗎？」，不需下載即可判斷。
  2. **下載後指紋比對**——前置檢查未命中的檔案，下載到暫存位置後計算 `content_fingerprint`（沿用既有匯入管線的計算邏輯），與 `findByContentFingerprint()` 比對；命中則彈出同樣提示，使用者選擇不建立新副本時立即刪除暫存檔。
- 同一本書若先前用不同格式下載過，因 `remoteBookId` 為書本層級，仍會被前置檢查命中、視為重複並提示，不為「格式不同」開特例。
- 兩層皆為精確比對，不做書名/作者模糊比對。

**單元測試要求：**
`FakeOpdsClient` ＋ 預先塞入命中資料的 `FakeLibraryRepository`，驅動下列情境的 widget test：選檔前置命中、下載後指紋命中、使用者取消時暫存檔清除、使用者選擇仍要匯入時正常完成、不同格式仍判定重複。

**驗收標準：** 兩層檢查皆能正確攔截真實重複情境（同一 OPDS 條目重複勾選、與本機已匯入書籍指紋相同的檔案）；使用者可選擇仍要匯入、不被強制阻擋；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0、Issue 2。

---

## Issue 4：圖書庫整合與快取生命週期

**Status:** ✅ 已完成並合併回 `main`（PR [#161](https://git.jigong.org/huthief/elinkBook/pulls/161)，分支 `epic-30-issue-4`，4 個 commit：Task 1-3 各自一個 commit＋1 個修正後重新實作的 Task 3 commit）。`/superpowers:writing-plans` 產出 `plans/plan-issue-4.md`，動工前先經 `/superpowers:receiving-code-review` 計畫審查（`reviews/review-plan-issue-4.md`，APPROVED，1 項 Minor：`_handleRedownload()` 的 `tempPath` 應宣告於 `try` 外部供 `catch` 清理，已於計畫中修訂）。**實作完成後首輪獨立 subagent 程式審查發現分支基底問題**（`reviews/review-issue-4.md`）：`epic-30-issue-4` 分支建立於 Issue 2／Issue 3 合併進 `main` 之前的過期基底（`git merge-base` 核實分叉點早於 `RemoteCatalogScreen` 存在），導致 Task 3 首版缺少可依循的既有兩段式下載模式，出現 4 項 Critical（下載檔案落在 OS 可回收暫存目錄、行動數據警示缺席、`connectivity_plus` 未依計畫注入、無重入防護）。修法：`git rebase main`（尚未推送，純本機操作）修正基底，捨棄過期基底上的 Task 3 commit，依原計畫在正確基底上重新實作；過程中另外發現並修正 `_maybeOpenLastBookOnLaunch()` 繞過 `isDownloaded` 檢查、可能於開機時嘗試開啟不存在檔案的既有缺口。重新實作後第二輪獨立 subagent 複審結論 **READY TO MERGE**（0 Critical／0 Important／1 Minor 計畫勾選同步）。全專案 `flutter test` 1531 項與 `flutter analyze` 零回歸通過。

**依賴：** Issue 0（`isDownloaded`／`remoteDownloadUrl` 欄位）、Issue 2（下載/匯入流程與 `remoteDownloadUrl` 落地）。

**背景：** `spec.md`「下載與快取生命週期」已定案設計，是本 Epic 相對 `epic-29-cloud-import`（一次性匯入）的核心差異化能力。與 Issue 3 彼此獨立，可平行進行。

**What to build：**
- 書架上 `isDownloaded == false` 的書籍疊加雲朵角標（沿用既有封面元件擴充）。
- 圖書庫書籍操作選單新增「移除本機快取」選項（僅 `source == BookSource.calibreOpds` 的書籍顯示）：刪除 `filePath` 指向的實體檔案，`isDownloaded` 更新為 `false`；`filePath`／`coverPath`／劃線／書籤／閱讀進度等其餘欄位不變。
- 點擊「待下載」書籍時的重新下載流程：先跳出確認對話框（若偵測到目前為行動數據連線，額外強調流量提示，沿用/仿照 `epic-29` Issue 6 的行動數據下載警示邏輯），確認後直接以該書 `remoteDownloadUrl` 呼叫 `OpdsClient.downloadBook()` 重新下載（不重新 `fetchFeed()` 反查目錄）；成功後更新 `filePath`／`isDownloaded=true`，不建立新的 `Book` 記錄；若下載失敗（例如 URL 已失效），顯示錯誤訊息，不做自動重新瀏覽目錄的復原嘗試。

**單元測試要求：**
- widget test：「移除本機快取」動作後 `isDownloaded` 變 `false`、實體檔案被刪除、劃線/書籤/閱讀進度資料不受影響（透過既有劃線/書籤 repository 測試替身組合驗證）；僅 Calibre 來源書籍顯示此選項（本機/其他來源書籍不顯示）。
- `FakeOpdsClient` 驅動重新下載流程的 widget test：確認對話框顯示與取消、行動數據情境額外提示、下載成功更新欄位、下載失敗顯示錯誤。

**驗收標準：** 移除快取後書架正確呈現雲朵角標且劃線/書籤/進度資料完整保留；點擊待下載書籍會先確認才觸發重新下載，成功後可正常開啟閱讀；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 0、Issue 2。

---

## Issue 5：E-Ink 優化與真機驗收

**Status:** ✅ 已完成並合併回 `main`（PR #162，分支 `epic-30-issue-5`，5 個 commit，2026-08-19）

**依賴：** Issue 2（目錄瀏覽畫面）。

**背景：** `design.md`「E-Ink 與後續優化」已定案獨立成本 Epic 最後一個 Issue，不擋核心瀏覽/下載/入庫先在一般手機上驗證正確性。研究報告原提出三項優化（離散分頁導航、封面縮圖雙層快取、搜尋防抖動），其中「搜尋防抖動」在 v1 沒有適用對象——`spec.md`「Out of Scope」已排除 OPDS 全文/即時搜尋，沒有搜尋框可以防抖動，此項自然略過，非新決策。

**What to build：**
- `RemoteCatalogScreen` 的「載入更多」在偵測到 E-Ink 模式時，改為離散的「上一頁／下一頁」按鈕列整頁換頁，停用連續捲動載入的高幀率動畫，避免滾動殘影。
- 封面縮圖雙層快取：記憶體快取（LRU）＋本機磁碟快取，比照 `PdfThumbnailCache` 的既有純 Dart LRU 快取設計精神（非直接重用，縮圖來源為遠端 URL 而非 PDF 頁面渲染，需要獨立實作）。
- Android 真機（一般裝置，以及 E-Ink 裝置若有可用測試機）／模擬器端到端驗證整個 Epic 的完整流程（新增站點→瀏覽→下載→匯入→閱讀→移除快取→重新下載→刪除站點）。

**單元測試要求：**
- widget test：E-Ink 模式偵測下 `RemoteCatalogScreen` 改用按鈕列渲染、點擊翻頁行為正確。
- 縮圖快取單元測試：記憶體/磁碟快取命中與未命中邏輯。

**驗收標準：** E-Ink 模式下瀏覽目錄不觸發連續捲動殘影；縮圖快取有效減少重複請求；真機端到端驗證完整流程無阻塞性問題，驗證結果記錄於審查報告；`flutter analyze` 乾淨、`flutter test` 通過。

**Blocked by：** Issue 2。

**完成摘要：** `isEinkMode` 貫穿 `RemoteServerListScreen`→`RemoteCatalogScreen`，E-Ink 模式下「載入更多」改為離散「上一頁／下一頁」整頁替換（`_goToPage()`），新增 `ScrollController` 於換頁後歸零捲動位置；新增 `RemoteThumbnailCache` 雙層快取（記憶體 LRU＋磁碟 SHA-256 檔名），抽出共用 `createOpdsHttpClient()`；`RemoteCatalogScreen._buildThumbnail()` 改用 `FutureBuilder`（優先檢查 `hasData` 避免閃爍）。真機驗證（Calibre Content Server）9 項情境全數通過，過程中修正 2 個真實 bug（`OpdsFeedParser` Calibre 格式相容性、遠端下載後書架自動刷新），詳見 `reviews/review-issue-5.md`。程式碼審查（`reviews/review-issue-5-code.md`，0 Critical／2 Important／4 Minor）已全數修訂：導覽連結退回邏輯健壯性強化＋補測試、Task 4 修復補回歸測試、格式縮排修正；縮圖快取 TTL/去重等 3 項 Minor 為計畫已載明的刻意取捨，維持原樣。全專案 `flutter test` 1544 項、`flutter analyze` 零回歸通過。

---

## Issue 6：抽出「遠端書籍下載器」深模組（技術債／架構深化）

**Status:** ✅ 已完成並合併回 `main`（PR [#163](https://git.jigong.org/huthief/elinkBook/pulls/163)，分支 `epic-30/issue-6-remote-book-downloader`，3 個 commit：Task 1-3 各自一個 commit）。

**依賴：** Issue 2、Issue 4（皆已完成並合併回 `main`）。

**背景：** `/improve-codebase-architecture` 於 2026-08-19 針對 `library_screen.dart`／`remote_catalog_screen.dart` 熱點區域進行架構審查（`docs/research/architecture-review-library-remote-screens.md`），候選 1（Top recommendation）指出 `RemoteCatalogScreen._DownloadQueueDialogState._downloadOne()`（Issue 2 產物）與 `LibraryScreen._handleRedownload()`（Issue 4 產物）各自重複實作了同一段「把一筆 OPDS acquisition 下載並落地成永久檔案」的邏輯：建立 `remote_download_temp/` 暫存目錄、以 UUID＋`fileExtensionFor()` 產生檔名、呼叫 `OpdsClient.downloadBook()`、建立 `remote_books/` 永久目錄、複製、刪暫存檔，並各自補上同一種「複製到一半失敗要清殘留暫存檔」的防禦（`catch` 區塊寫法完全相同，連審查採納註解措辭都一樣）。

`/diagnose` 逐行核對兩處實作後確認：核心重複範圍約 20-25 行（temp dir 建立 → `downloadBook()` → permanent dir 建立 → copy → delete → 例外清理），但**不能整段抽成單一函式**——`_downloadOne()` 在「下載到暫存檔」與「複製到永久目錄」中間插入了 Issue 3 的第二層重複匯入偵測（計算指紋、比對、彈出確認對話框，使用者選擇不建立新副本時直接刪暫存檔並標記 `duplicateSkipped`、不會走到複製步驟），這個決策點是 `_handleRedownload()` 沒有的（它是替換既有書籍記錄的檔案，不需要重複偵測）。架構審查報告的 Before/After 圖把這一步簡化畫成單一 `materialize()` 呼叫，實際設計需拆成兩個獨立方法，見下方「What to build」。

**What to build：**
- 新增 `lib/remote/remote_book_downloader.dart`，內含兩個獨立方法（非單一 `materialize()`，理由見上）：
  - `Future<String> downloadToTempFile({required OpdsClient client, required RemoteServerProfile server, required OpdsAcquisition acquisition, required BookFileFormat format, String? password, void Function(int, int)? onProgress, OpdsDownloadCancellationToken? cancellationToken})`：建立 `remote_download_temp/` 目錄、產生 UUID 檔名、呼叫 `client.downloadBook()`，回傳暫存檔路徑；不需額外例外清理（`downloadBook()` 失敗/取消時已自行清過暫存檔，既有文件已記錄此行為）。
  - `Future<String> promoteToPermanent(String tempPath, BookFileFormat format)`：建立 `remote_books/` 目錄、複製暫存檔到永久路徑、刪暫存檔，回傳永久路徑；任何例外皆先清殘留暫存檔再重新拋出（兩個呼叫端既有的 `catch` 清理邏輯收進這裡，呼叫端不再需要各自宣告 `tempPath` 於 `try` 外）。
- `RemoteCatalogScreen._DownloadQueueDialogState._downloadOne()` 改為：呼叫 `downloadToTempFile()` → 指紋比對／確認對話框（邏輯不變）→ 使用者確認保留才呼叫 `promoteToPermanent()`；拒絕時維持現有「刪暫存檔＋標記 `duplicateSkipped`」邏輯不變。
- `LibraryScreen._handleRedownload()` 改為：依序呼叫 `downloadToTempFile()` → `promoteToPermanent()`（中間無決策點，背靠背呼叫）。
- 兩個呼叫端移除各自重複的 temp/permanent 目錄管理與例外清理程式碼，改為呼叫上述共用方法。

**單元測試要求：**
- `remote_book_downloader_test.dart`：`downloadToTempFile()` 正確建目錄／組檔名／呼叫 `client.downloadBook()`（Fake client 驗證呼叫參數）；`promoteToPermanent()` 正確複製＋刪暫存檔＋回傳永久路徑；`promoteToPermanent()` 在複製中途失敗時清殘留暫存檔並重新拋出例外（沿用既有 `_handleRedownload`/`_downloadOne` 測試已驗證過的情境，改為對新模組直接測試）。
- `remote_catalog_screen_test.dart`／`library_screen_test.dart` 既有涵蓋下載/重新下載成功與失敗路徑的測試須維持全數通過（改走新模組後行為不得改變，屬回歸驗證，不需新增案例）。

**驗收標準：** `flutter analyze` 乾淨；`flutter test` 全數通過、零回歸；`_downloadOne()`／`_handleRedownload()` 兩處不再各自宣告 temp/permanent 目錄管理與例外清理邏輯，改為呼叫 `RemoteBookDownloader` 的共用方法；審查報告記錄實際刪除的重複程式碼行數。

**Blocked by：** Issue 2、Issue 4（皆已完成，無實質阻塞）。

**完成摘要：** 新增 `lib/remote/remote_book_downloader.dart`，`downloadToTempFile()`／`promoteToPermanent()` 兩個獨立純 Dart 函式取代兩處重複實作；`promoteToPermanent()` 以 `copied` 旗標區分「`copy()` 本身失敗」與「`copy()` 成功但刪暫存檔失敗」兩種失敗窗口，只在前者才清理永久路徑殘檔，避免誤刪已下載成功的書籍檔案。`RemoteCatalogScreen._downloadOne()`／`LibraryScreen._handleRedownload()` 皆已改用新模組，控制流程（含 Issue 3 的重複匯入指紋比對決策點）完整保留。計畫審查（`reviews/review-plan-issue-6.md`，2 Important／2 Minor）已全數修訂：Task 3 原稿遺漏 `password:` 傳遞（會導致密碼保護站點重新下載回歸失敗 401）、補上參數透傳驗證測試、`promoteToPermanent()` 例外清理邏輯修正為兩窗口區分設計（審查原始建議的「無差別清理」技術上有誤）。程式碼審查（`reviews/review-issue-6.md`，0 Critical／0 Important／1 Minor）**APPROVED**，逐行核對確認計畫審查的修訂皆已落實到最終程式碼，與計畫無落差。全專案 `flutter test` 1549 項、`flutter analyze` 零回歸通過。
