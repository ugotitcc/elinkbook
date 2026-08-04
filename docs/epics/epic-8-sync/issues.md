# Epic 8 — 雲端同步：工單清單 (Issues)

依 `spec.md`（搭配 `design.md`、`/grill-with-docs` Discovery + Architecting + spec 審查修正，另見 [ADR 0019](../../adr/0019-pocketbase-sync-account-architecture.md)／[ADR 0020](../../adr/0020-cross-device-sync-strategy.md)）拆解出的 7 個垂直切片工單。依賴圖：Issue 1／2／7 可立即平行開始；Issue 3 依賴 1；Issue 4 依賴 1/2/3；Issue 5、6 依賴 4（5、6 互不依賴，可平行）。

---

## Issue 1：本機 Schema 遷移（v16 → v17）

**依賴／Blocked by：** None - can start immediately

**Status:** ready-for-agent

**What to build：**

SQLite schema 自 v16 升級至 v17（比照既有累加式 `if (oldVersion < 17)` 慣例）：

1. **遷移交易開始前先 `PRAGMA foreign_keys = OFF;`**，全部步驟完成、驗證新表資料無誤後**必須**恢復 `PRAGMA foreign_keys = ON;`（本專案 `sqlite_library_repository.dart:31` 既有開啟外鍵約束，且 `onConfigure` 早於 `onUpgrade` 執行，不暫停會導致既有裝置升級當下 `foreign key constraint failed` 崩潰，見 spec.md「Migration」）。
2. `books` 表新增 `content_fingerprint TEXT`／`position_updated_at INTEGER`／`position_synced_server_updated_at TEXT`。
3. `bookmarks`／`highlights`／`notes` 三表主鍵由 `INTEGER PRIMARY KEY AUTOINCREMENT` 改為 `TEXT PRIMARY KEY`（UUID）：建新表→逐筆搬移既有資料（產生新 UUID、重寫 `notes.highlight_id` 參照為對應劃線的新 UUID）→刪舊表→改名（SQLite 不支援 `ALTER COLUMN` 改型別，比照官方建議的 schema 變更手法）；新增 `updated_at INTEGER NOT NULL`（既有資料回填遷移當下時間戳記）／`deleted_at INTEGER`（可空，新資料一律 `NULL`）。`notes.highlight_id` 型別同步由 `INTEGER` 改為 `TEXT`。
4. 新增 `sync_metadata` 表：`lastPushCompletedAt`（初始 `NULL`）＋ 4 個 collection 各自的 `lastPulledServerUpdatedAt_<collection>`（初始皆 `NULL`）。
5. 對應 Dart 模型變更：`Bookmark`／`Highlight`／`Note` 的 `id` 型別由 `int?` 改為 `String`（不再 nullable，UUID 建立物件當下即指派）；`Note.highlightId` 由 `int?` 改為 `String?`（維持 nullable，語意不變）；三個模型的 `toMap()` 改為包含 `id` 欄位（不再省略交由 `AUTOINCREMENT` 指派）；對應 repository 的 `insert()` 回傳型別由 `Future<int>` 改為 `Future<void>`。**盤點所有依賴這三個型別的呼叫端**（UI 的 `Key('bookmark_$id')` 之類的字串內插、任何比較/傳遞這些 id 的邏輯），確保型別變更後全部正確改為 `String`，不遺漏。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - Migration 正確性：`bookmarks`/`highlights`/`notes` 既有整數 id 資料正確轉換為 UUID，`notes.highlight_id` 參照正確回填為對應劃線的新 UUID，`books`/`sync_metadata` 新增欄位有正確預設值（`NULL`）。
  - **驗證遷移過程中 `PRAGMA foreign_keys` 正確暫停又恢復**：先確認若忘記關閉 FK 檢查會重現 `foreign key constraint failed`（藉此證明測試真的涵蓋到這個情境），再驗證正式實作不會出現此例外，且遷移完成後 FK 約束確實已恢復生效（例如嘗試插入一筆參照不存在 `book_id` 的 `bookmarks` 紀錄，應被拒絕）。
  - `Bookmark`/`Highlight`/`Note` 的 `toMap()`/`fromMap()`/repository `insert()` 皆改用 `String` id 後行為正確（新增時呼叫端指派的 UUID 確實寫入、讀回一致）。

**驗收標準：**

- [x] `PRAGMA foreign_keys = OFF/ON` 正確包住整個表格重建流程，既有裝置升級不崩潰
- [x] `bookmarks`/`highlights`/`notes` 主鍵成功轉為 UUID，既有資料與 `notes.highlight_id` 參照正確轉換
- [x] `books`／`sync_metadata` 新增欄位正確建立
- [x] `Bookmark`/`Highlight`/`Note` 模型與對應 repository 型別變更完整（`int?`→`String`／`Future<int>`→`Future<void>`），全專案呼叫端無遺漏
- [x] 上述測試皆通過，`flutter analyze` 乾淨（兩輪實作結果審查發現並修正 4 項 Critical——`updated_at`/`deleted_at` 欄位缺失、`sync_metadata` schema 錯誤、`onCreate` 未建立該表、遷移測試缺失，見 `plans/plan-issue-1.md`「實作結果第二輪審查修正紀錄」）

---

## Issue 2：同步帳號模組 + Settings「同步」子頁面

**依賴／Blocked by：** None - can start immediately（與 Issue 1 完全獨立）

**Status:** ready-for-agent

**What to build：**

新增 `pubspec.yaml` 依賴：官方 `pocketbase` Dart package、`flutter_secure_storage`（若尚未加入）。

新增 `SyncAccountRepository`：`baseUrl` 讀寫 `SharedPreferences`（key `sync_base_url`，預設官方 URL）；`authToken`／`userId`／`email` 讀寫 `flutter_secure_storage`（僅這三項用加密儲存）；登入態判斷 `authToken == null`。

新增 `SyncClient`：`Future<bool> testConnection(String baseUrl, String email, String password)`——呼叫 PocketBase `authWithPassword`，成功即完成登入（token 存入 `flutter_secure_storage`），不做「測試/丟棄再登入」兩段式設計；`Future<void> logout()`——清除 `flutter_secure_storage` 內三項憑證，不影響任何本機資料。

新建 `SyncSettingsScreen`：base URL／email／password 輸入欄位、「連線／登入」按鈕（呼叫 `testConnection()`）、登出按鈕（已登入時顯示，呼叫 `logout()`）；未登入時不顯示任何同步狀態 UI（opt-in）。`SettingsScreen` 新增「同步」入口（比照既有「佈景」子頁面模式）。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - `SyncAccountRepository`：`baseUrl` 讀寫（含未設定時的預設值）、`authToken`/`userId`/`email` 讀寫（mock `flutter_secure_storage`）、登入態判斷正確。
  - `SyncClient.testConnection()`：mock PocketBase 回應，成功時正確寫入憑證並回傳 `true`；失敗（連線錯誤/帳密錯誤）時回傳 `false`、不寫入任何憑證。
  - `SyncClient.logout()`：清除全部三項憑證。
  - `SyncSettingsScreen`：未登入/已登入兩種狀態的 UI 呈現差異、輸入欄位、按鈕觸發對應方法。
  - `SettingsScreen`：新增「同步」入口，點擊導航正確。
- integration_test（真機，需要 Issue 7 產出的可連線測試用 PocketBase 實例）：真的對測試伺服器執行一次登入/登出，驗證憑證確實落地/清除。

**驗收標準：**

- [x] `SyncAccountRepository`／`SyncClient` 正確讀寫 base URL（SharedPreferences）與憑證（flutter_secure_storage）
- [x] `testConnection()` 成功即完成登入，失敗不寫入任何憑證
- [x] `logout()` 正確清除憑證，不影響本機資料
- [x] `SyncSettingsScreen` 正確呈現未登入/已登入狀態，`SettingsScreen` 新增入口可正確導航
- [x] 上述測試皆通過，`flutter analyze` 乾淨（含真機 `integration_test`，已於 Android 15 實機驗證通過，見 `plans/plan-issue-2.md`「實作結果審查修正紀錄」）

---

## Issue 3：書籍內容指紋計算 + 匯入流程串接

**依賴／Blocked by：** Issue 1（需要 `books.content_fingerprint` 欄位存在）

**Status:** ready-for-agent

**What to build：**

新增頂層函式 `Future<String> computeBookContentFingerprint(String filePath, BookFileFormat format)`：

- **EPUB**：優先讀取 OPF identifier——擴充 `BookMetadataChannel.kt` 既有的 `extractEpubMetadata()` 多回傳 `publication.metadata.identifier`（既有 Readium 物件既有欄位，不需新增相依）；為空/缺漏時退回對整份 `.epub` 檔案內容算 SHA-256。
- **PDF／TXT**：一律對整個檔案內容算 SHA-256。
- **必須串流計算＋獨立 Isolate 執行**：`File.openRead()` 搭配 `package:crypto` 的 `sha256.startChunkedConversion()` 逐塊計算，禁止 `File.readAsBytes()` 一次性讀入記憶體；整個計算過程外包至 `Isolate.run()`（或 `compute()`），不阻塞 UI isolate。

`book_import_service_impl.dart` 匯入流程新增一步，計算並寫入 `books.content_fingerprint`（與現有封面產生/中繼資料擷取並列，不需要額外背景執行緒——匯入本身允許稍長時間）。

既有書籍升級後 `content_fingerprint` 為 `NULL`：比照 `epic-17` `detectAndCacheEpubLayout()` 的一次性補判斷模式，首次觸發同步時才補算回填（精確時機留待實作時依 Issue 4 的介面決定）。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - 已知 OPF identifier 的 EPUB fixture 解析正確；缺漏 identifier 退回 SHA-256；PDF/TXT 一律 SHA-256；同一檔案兩次計算結果一致（確定性）。
  - 大檔案 fixture（測試環境不需真的用到 100MB，例如 >10MB 即可）驗證呼叫路徑確實走 `File.openRead()` 串流而非 `readAsBytes()` 一次性載入。
  - 匯入流程正確寫入 `books.content_fingerprint`。

**驗收標準：**

- [x] EPUB 優先使用 OPF identifier，缺漏時正確退回 SHA-256
- [x] PDF/TXT 一律使用全檔案 SHA-256，計算結果具確定性（同檔案兩次結果一致）
- [x] 指紋計算採串流讀取＋獨立 Isolate 執行，不一次性讀入整個檔案、不阻塞 UI
- [x] 匯入流程正確寫入 `content_fingerprint`
- [x] 上述測試皆通過，`flutter analyze` 乾淨

---

## Issue 4：同步引擎核心——劃線/備註/書籤同步（FR-20）+ 墓碑清理

**依賴／Blocked by：** Issue 1、Issue 2、Issue 3

**Status:** done

**What to build：**

新增 `SyncEngine`，核心方法 `Future<void> runCheckpoint()`（本 Issue 只實作劃線/備註/書籤與墓碑清理相關步驟，閱讀位置的衝突預檢留給 Issue 5 擴充同一方法）：

1. **推送**：查詢本機 `updated_at > sync_metadata.lastPushCompletedAt`（或 `deleted_at` 非空且尚未推送過）的所有 `bookmarks`/`highlights`/`notes` 異動，組成 PocketBase Batch API 請求。每筆 create/update payload 明確帶入 `user: <目前登入者 PocketBase user id>`。**分批送出**：每批最多 100 筆異動，超過則拆成多個依序送出的 Batch 請求。任一批失敗即整個 checkpoint 視為失敗（見「同步失敗」）。
2. **推送成功後**：更新 `sync_metadata.lastPushCompletedAt` 為現在（本機時鐘，純本機用途）。
3. **下載**：對 `sync_bookmarks`/`sync_highlights`/`sync_notes` 三個 collection 各自查詢一次「`updated` 系統欄位晚於 `sync_metadata.lastPulledServerUpdatedAt_<collection>`」；下載回來的紀錄直接覆寫本機對應紀錄（`client_id` 找得到就更新、找不到就新增；`deleted_at` 非空視同刪除狀態寫入）——本輪推送已完成，不需要再比較任何時間戳記。跨裝置參照：`sync_notes` 的 `highlight_client_id` 非空時直接寫入本機 `notes.highlight_id`（劃線本機 id 本身就是 UUID，不需轉換查表）；`book_fingerprint` 查不到對應本機 `books` 時該筆同步紀錄暫緩合併、留在待處理佇列。
4. 下載完成後，把每個 collection 這次查到的最大 `updated` 值更新回 `sync_metadata.lastPulledServerUpdatedAt_<collection>`（沒查到新紀錄則維持原值）。
5. **本機墓碑清理**：`bookmarks`/`highlights`/`notes` 三表中 `deleted_at IS NOT NULL AND deleted_at < (現在時間 - 30 天)` 的紀錄真正 `DELETE FROM`（非軟刪除）——只在成功完成本輪推送後才清理（確保墓碑已送達伺服器）。
6. **同步失敗（離線/逾時，發生於步驟 1-5 任一階段）**：本機異動已先落地成功不受影響；本次 checkpoint 整批放棄，不更新任何 `sync_metadata` 游標（含已推送成功那部分的 `lastPushCompletedAt`）——下次重試時重複推送同樣內容只是多一次無害的 Update()。

本 Issue 不含 Checkpoint 觸發來源（App 生命週期/書籍切換/閒置計時器）與併發鎖，`runCheckpoint()` 本 Issue 僅需可被手動/測試呼叫；觸發機制與併發防護見 Issue 6。

**單元測試要求：**

- **接縫**：推送批次組裝、下載合併套用、墓碑清理篩選皆設計為純函式（輸入本機/遠端清單，輸出待寫回本機的差異），不依賴 PocketBase SDK 或資料庫，比照本專案既有的「純函式優先」慣例。
- widget test（純 Dart，不需真機/不需真實 PocketBase 伺服器，mock PocketBase client）：
  - 推送批次組裝：dirty 判定（`updated_at > lastPushCompletedAt`）正確；異動筆數超過 100 筆時正確拆成多個批次；每筆 payload 確實帶有 `user` 欄位。
  - 下載合併套用：`client_id` 找得到就更新、找不到就新增；`deleted_at` 非空正確寫入刪除狀態；`highlight_client_id` 正確回填 `notes.highlight_id`；`book_fingerprint` 查無對應本機書籍時正確暫緩、不誤建空殼書籍紀錄。
  - 墓碑清理純函式：`deleted_at` 早於/晚於 30 天前的篩選正確；未刪除的紀錄不受影響；只在推送成功後才執行清理（推送失敗時不清理）。
  - 同步失敗：任一批推送失敗時，`sync_metadata` 游標（含已成功的部分）皆不更新。
- integration_test（真機，需要 Issue 7 產出的可連線測試用 PocketBase 實例）：端到端 checkpoint，真的透過 PocketBase Batch API 成功寫入/讀回劃線/備註/書籤資料。

**驗收標準：**

- [x] 推送正確分批（100 筆/批），payload 皆帶 `user` 欄位
- [x] 下載正確合併（新增/更新/刪除），`client_id`／`highlight_client_id`／`book_fingerprint` 跨裝置參照皆正確解析
- [x] 本機墓碑清理正確執行（僅推送成功後、僅 30 天以上的墓碑）
- [x] 同步失敗時本機異動不受影響、`sync_metadata` 游標不更新、下次重試會整批重來
- [x] 上述測試皆通過，`flutter analyze` 乾淨

---

## Issue 5：同步引擎——閱讀位置同步與衝突彈窗（FR-19）

**依賴／Blocked by：** Issue 4

**Status:** done

**What to build：**

擴充 Issue 4 的 `SyncEngine.runCheckpoint()`，於推送步驟之前新增「閱讀位置衝突預檢」：

- 僅當本機 `books.position_updated_at > sync_metadata.lastPushCompletedAt`（該書位置自上次推送後有本機新異動）時才執行。
- 查詢目前 PocketBase `sync_reading_positions` 該本書紀錄的 `updated`（伺服器蓋章時間）；若與本機快取的 `books.position_synced_server_updated_at` 不同（代表其他裝置在本機上次同步後又推送過），視為衝突：彈窗詢問使用者要保留本機還是雲端版本，使用者選擇前該書位置**不**納入本次推送批次（避免任一邊被靜默覆蓋）。
- 若相同（沒有其他裝置動過）或本機該書位置本來就沒有待推送異動：直接把本機值納入本次推送批次（與 Issue 4 的 `bookmarks`/`highlights`/`notes` 異動一起送出）。
- 推送成功後，若本次有推送閱讀位置，用 Batch API 回應中該筆紀錄的 `updated` 值回填 `books.position_synced_server_updated_at`（伺服器蓋章值，非本機時鐘）。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - 閱讀位置衝突判定純函式：本機 dirty 且伺服器 `updated` 與快取值不同 → 回傳「需要詢問使用者」；本機 dirty 但伺服器 `updated` 與快取值相同 → 回傳「直接套用本機」；本機不 dirty → 回傳「不需要動作」。
  - 衝突彈窗 UI：顯示本機與雲端兩個版本供使用者選擇，選擇前不寫入任何一邊；使用者選擇後正確套用所選版本並繼續推送流程。
  - `position_synced_server_updated_at` 正確於推送成功後回填為伺服器蓋章值。
- integration_test（真機，需要 Issue 7 產出的可連線測試用 PocketBase 實例）：模擬雙裝置情境（同一測試帳號、兩次獨立推送不同閱讀位置），驗證第二次同步時正確觸發衝突彈窗。

**驗收標準：**

- [x] 閱讀位置衝突偵測正確（僅雙方皆變動過才視為衝突）
- [x] 偵測到衝突時彈窗詢問使用者，使用者選擇前不靜默覆蓋任一邊（FR-19 硬性要求）
- [x] 無衝突時直接套用變動的一邊
- [x] `position_synced_server_updated_at` 正確維護
- [x] 上述測試皆通過，`flutter analyze` 乾淨（PR #108，2026-08-04；真機雙裝置驗證通過，過程中發現並修正 PocketBase `created`／`updated` autodate 欄位缺失〔影響已合併 Issue 4〕與兩個跨 Task 整合缺口〔衝突延後跳過永不重試、`Book.copyWith()` 清空同步欄位〕，見 `plans/plan-issue-5.md`「審查修正紀錄」；另開 Issue 8／Issue 9 追蹤不阻擋合併的既知缺口）

---

## Issue 6：Checkpoint 觸發機制 + 併發鎖

**依賴／Blocked by：** Issue 4（需要可呼叫的 `runCheckpoint()`；與 Issue 5 互不依賴，可平行）

**Status:** ready-for-agent

**What to build：**

三種 checkpoint 觸發來源接上 `SyncEngine.runCheckpoint()`：

1. App 生命週期監聽（`AppLifecycleState.paused`）。
2. 書籍切換（離開 `ReaderScreen`）。
3. 閱讀中每 5 分鐘閒置計時器。

`SyncEngine` 新增單一執行鎖（`bool _isSyncing` 或等效 async mutex）：三種觸發來源可能短時間內幾乎同時各自呼叫 `runCheckpoint()`，若鎖已被佔用，後續觸發直接放棄（不排隊等待——放棄的那次觸發所代表的本機異動，下一次任何 checkpoint 自然會涵蓋到）。

僅未登入（opt-in 未啟用同步）時，三種觸發來源皆不執行任何動作（不呼叫 `runCheckpoint()`）。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - 三種觸發來源個別正確呼叫 `runCheckpoint()`。
  - 併發鎖：模擬兩次幾乎同時呼叫 `runCheckpoint()`，驗證第二次呼叫在第一次仍執行中時直接放棄、不會兩次同時真的送出網路請求。
  - 未登入時三種觸發來源皆不呼叫 `runCheckpoint()`。

**驗收標準：**

- [ ] App 背景化／書籍切換／5 分鐘閒置計時器三種來源皆正確觸發 checkpoint
- [ ] 併發鎖正確防止同時執行多個 `runCheckpoint()`
- [ ] 未登入時不觸發任何同步動作
- [ ] 上述測試皆通過，`flutter analyze` 乾淨

---

## Issue 7：PocketBase 自架 SOP 文件

**依賴／Blocked by：** None - can start immediately

**Status:** ready-for-agent

**What to build：**

純文件交付物（不含 App 程式碼），對照 `spec.md`「PocketBase Collection Schema」撰寫：

1. 最低版本需求：PocketBase ≥ 0.23（Batch API 需要）。
2. Collection 建立步驟：4 個 collection（`sync_reading_positions`／`sync_bookmarks`／`sync_highlights`／`sync_notes`）逐一列出欄位/型別/API rule（`user = @request.auth.id`）設定步驟。
3. 基本部署建議：官方 Docker image 最簡啟動範例。
4. 備份建議：定期備份 PocketBase 的 SQLite 資料檔案。
5. 墓碑清理建議：`pb_hooks` JS cron 排程範例，定期清理 4 個 `sync_*` collection 中超過 30 天的 `deleted_at` 軟刪除紀錄。

依此文件實際建立一個可連線的測試用 PocketBase 實例，供 Issue 2／4／5 的 `integration_test` 使用。

**驗收標準（人工檢核，非自動化測試）：**

- [x] 依文件步驟可從零開始成功建立一個運作中的 PocketBase 實例
- [x] 4 個 collection 皆正確建立，欄位/型別/API rule 與 `spec.md` 一致
- [x] 依文件建立的測試用 PocketBase 實例可供 Issue 2／4／5 的 `integration_test` 實際連線使用
- [x] `pb_hooks` 墓碑清理範例語法正確、可實際載入運作（實作結果審查發現並修正 1 項 Critical——`deleted_at != null` 篩選條件對 PocketBase number 欄位無效，改為 `deleted_at > 0`，見 `plans/plan-issue-7.md`「實作結果審查修正紀錄」）

---

## Issue 8：`integration_test/sync_engine_test.dart` 既有 Issue 4 測試——sqflite `:memory:` 裝置隔離失敗（bug）

**依賴／Blocked by：** None（獨立 bug 修復，不阻擋 Issue 5/6）

**Status:** needs-triage

**背景（2026-08-04，Issue 5 Task 6 真機驗證時發現）：**

Issue 4 既有的 `integration_test/sync_engine_test.dart` 測試（「端到端 checkpoint：推送本機新增的書籤...」）在真機（Android 15, API 35）上執行時，於 `await deviceB.insertBook(bookA);` 這一行拋出 `SqfliteFfiException`：`UNIQUE constraint failed: books.id`。

**目前影響**：這個問題導致 `integration_test/sync_engine_test.dart`
**整個檔案**（`flutter test integration_test/sync_engine_test.dart -d
<device-id>`）無法完整跑完——Issue 4 的舊測試會先撞到這個 crash；Issue 5
Task 6 新增的測試必須用 `--plain-name "雙裝置閱讀位置衝突"`
單獨隔離執行才會通過。任何人之後想確認「整個 `integration_test` 套件是否
全綠」，在這個問題修好之前都需要記得這個限制。

`deviceA`／`deviceB` 分別是兩次獨立呼叫 `SqliteLibraryRepository.open(inMemoryDatabasePath)` 開出來的、理應互相獨立的記憶體內資料庫，`deviceB` 插入的是 `deviceA` 已經插入過的同一個 `bookA` 物件（同一個 `id`，測試刻意重用同一物件以取得相同 `content_fingerprint`，見該測試檔案內註解）。若兩個資料庫真的互相獨立，插入到一個全新的空資料庫不應該撞到 UNIQUE constraint。

**已排除的可能原因**（控制者已查證 `sqflite_common`/`sqflite_common_ffi` 原始碼，見 Issue 5 Task 6 對話紀錄）：
- 不是 `singleInstance` 快取——`sqflite_common-2.5.8/lib/src/database_mixin.dart:930-931` 明確對 `:memory:` 路徑強制 `singleInstance = false`，不受 `openDatabase()` 預設 `singleInstance: true` 影響。
- 不是 FFI 層級的路徑快取——`sqflite_common_ffi-2.4.0+3/lib/src/sqflite_ffi_impl_io.dart:25-26` 對 `:memory:` 路徑每次呼叫皆執行 `ffi.sqlite3.openInMemory()`，理論上每次都應該是全新、獨立的 sqlite3 連線。

**尚待查證**：既然套件原始碼看起來不應該共享連線，實際卻觀察到共享行為，可能是：
1. `sqflite_common_ffi` 底層共用的背景 isolate 在快速連續開啟多個 `:memory:` 連線時的某種 race condition 或內部狀態管理問題（`database_tracker.dart` 提到用 `file:sqflite_database_tracker?mode=memory&cache=shared` 追蹤已開啟的連線，值得深入研究這個追蹤機制本身是否有副作用）。
2. 或本專案 `sqflite_common_ffi` 鎖定版本（2.4.0+3）已知的既有 bug，可能後續版本已修正，需要查證 changelog。
3. 或是這個測試撰寫當下就已經有這個問題、只是先前真機驗證時剛好沒有真的跑到這條插入敘述（例如先前跑在不同 Android 版本/裝置上、或當時套件版本不同）。

**建議做法**：先寫一個最小重現案例（純粹兩次 `SqliteLibraryRepository.open(inMemoryDatabasePath)` + 各自插入不同表格但相同 id 的最簡單 widget test，在真機上跑），確認問題必現後再決定修法（例如改用具名的 in-memory URI 讓兩個「裝置」使用不同路徑字串，或升級 `sqflite_common_ffi` 版本）。

**驗收標準：**

- [ ] 已確認根本原因（透過最小重現案例）
- [ ] `integration_test/sync_engine_test.dart` 既有 Issue 4 測試在真機上可正確通過，不受這個問題影響
- [ ] 若採用「兩個裝置使用不同 in-memory 路徑」的修法，Issue 5 Task 6 新增的測試（同一份檔案）一併確認不受影響

---

## Issue 9：`sync_reading_positions` 缺少 unique index 強制「每 (user, book_fingerprint) 至多一筆」

**依賴／Blocked by：** None（獨立修正，建議在 Issue 6 開工前處理）

**Status:** done

**背景（2026-08-04，Issue 5 最終全分支審查發現）：**

plan-issue-5.md 的 Global Constraints 明確要求「`sync_reading_positions` 每個
使用者對每本書（`book_fingerprint`）至多一筆紀錄」，但這個約束目前完全只是
約定、沒有任何機制強制執行：

- `docker/pb_migrations/1785715200_create_sync_collections.js` 的
  `sync_reading_positions` collection 定義沒有宣告任何 unique index。
- `SyncEngine._syncReadingPositions()` 查詢既有紀錄時用
  `getList(filter: ..., perPage: 1)`，沒有帶 `sort`，理論上若真的有多筆
  符合的紀錄，回傳哪一筆是不確定的。

**可能觸發情境**：兩台裝置第一次同時推送同一本書（都查到 `remoteId` 為
`null`，因為推送前的查詢發生在真正 create 之前）會各自建一筆；本機同一本書
匯入兩次（產生兩列相同指紋、皆為 dirty）也會在同一次 checkpoint 內建出
兩筆。一旦出現重複列，`getList(perPage: 1)` 拿到不穩定的其中一筆、
`updated` 值忽大忽小，會導致反覆跳出假衝突彈窗，且無法自癒。

**建議做法**：

1. 新增一支冪等的升級 migration（比照 `1785801600_add_created_updated_autodate_fields.js`
   的模式），對 `sync_reading_positions` 加上
   `CREATE UNIQUE INDEX idx_sync_reading_positions_user_fp ON sync_reading_positions (user, book_fingerprint)`。
2. 套用前**必須先確認測試實例 `pbdev.jigong.org` 上沒有既存的重複紀錄**
   （否則加 unique index 會直接失敗）——先用 Admin API 查一次
   `sync_reading_positions` 全部紀錄，依 `(user, book_fingerprint)` 分組檢查。
3. `SyncEngine._syncReadingPositions()` 的 `getList()` 補上確定性的
   `sort`（例如 `sort: 'created'` 或 `'-updated'`），即使加了 unique index
   之後理論上不會再有重複，也讓查詢行為本身不依賴未定義的排序。

**驗收標準：**

- [x] 已確認 `pbdev.jigong.org` 上沒有既存重複紀錄，或已妥善清理
- [x] 新增的 unique index migration 正確套用（本機／測試實例皆驗證過）
- [x] `_syncReadingPositions()` 的查詢補上確定性排序
- [x] 新增測試驗證「同一 (user, book_fingerprint) 嘗試建立第二筆會被 PocketBase 拒絕」（PR #109，2026-08-04；本機用 PocketBase v0.39.10 binary 驗證 migration 正確套用/冪等/失敗情境三種行為，`pbdev.jigong.org` 已透過 Admin API 套用並驗證，見 `plans/plan-issue-9.md`）

---

## Issue 10：`LibraryScreen._openGroupFilteredView()`（分類篩選二次推入路徑）未貫穿同步相關欄位（`syncAccountRepository`／`syncClient`／`syncCheckpointTrigger`）

**依賴／Blocked by：** None（獨立缺口，不阻擋 Issue 6 合併）

**Status:** needs-triage

**背景（2026-08-04，Issue 6 程式碼審查發現，見 `plans/plan-issue-6.md` 文末「與 spec.md／issues.md 的落差說明彙整」第 5 點自陳、`review-report-code-issue-6.md` Important #2）：**

`LibraryScreen._openGroupFilteredView()`（`app/lib/screens/library_screen.dart:470-489`，依分類篩選後再次推入 `LibraryScreen` 的既有遞迴路徑）建構下一層 `LibraryScreen` 時，沒有貫穿 `syncAccountRepository`／`syncClient`（Issue 2 遺留的既有缺口）與 `syncCheckpointTrigger`（Issue 6 新增，本次審查發現）三個同步相關欄位。

**目前影響**：使用者從「書架 → 點分類拼貼格 → 開書」這條常見路徑閱讀時：
- `syncAccountRepository`／`syncClient` 缺席只影響該層畫面的同步狀態 UI 顯示（既有缺口，Issue 2 時期即存在）。
- `syncCheckpointTrigger` 缺席則代表該書籍的「離開畫面觸發」（Task 3）與「閱讀中 5 分鐘計時器觸發」（Task 4）兩種 checkpoint 來源會靜默失效，只剩「App 背景化」（Task 5，掛在 `ElinkBookApp` 層、不受 `LibraryScreen` 貫穿與否影響）仍作用。不會導致資料遺失（下次任何 checkpoint 仍會涵蓋到這段期間的異動），但會讓這條路徑上的同步延遲實質變長，偏離 spec.md「閱讀位置...目標延遲 <2 秒」的目標。

Issue 6 計畫刻意不在該 Issue 範圍內修正（比照既有 `syncAccountRepository`／`syncClient` 缺口的既定行為，避免用不相關的修正擴大變更範圍），本工單即為當時承諾的後續追蹤。

**建議做法**：一次處理全部三個欄位（`syncAccountRepository`／`syncClient`／`syncCheckpointTrigger`），在 `_openGroupFilteredView()` 建構下一層 `LibraryScreen` 時比照其餘既有欄位一併貫穿。

**驗收標準：**

- [ ] `_openGroupFilteredView()` 建構下一層 `LibraryScreen` 時正確貫穿 `syncAccountRepository`／`syncClient`／`syncCheckpointTrigger` 三個欄位
- [ ] 新增測試驗證「透過分類篩選路徑開書後，`ReaderScreen` 收到的 `syncCheckpointTrigger` 與外層一致」（比照既有 `library_screen_test.dart` 對第一層路徑的測試模式）
- [ ] `flutter analyze` 乾淨
