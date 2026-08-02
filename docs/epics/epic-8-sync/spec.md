# Epic 8 — 雲端同步：規格 (Spec)

這是實作 `epic-8-sync` 的唯一事實來源。決策的完整討論過程與理由請見 `design.md`（`/grill-with-docs` 2026-08-02，14 項決策）與 [ADR 0019](../../adr/0019-pocketbase-sync-account-architecture.md)（同步帳號架構）／[ADR 0020](../../adr/0020-cross-device-sync-strategy.md)（跨裝置同步策略，2026-08-03 Architecting 階段修訂 `sync_id`→`client_id` 措辭）。本文件延續 `design.md` 的所有範圍界定，不重複列出理由，僅在此定案核心介面/型別，供 Scrum Master 階段拆解工單使用。

## Problem Statement

見 `design.md`「問題陳述」。本文件額外釐清 Discovery 階段未發現的一個架構缺口：`bookmarks`/`highlights`/`notes` 三表目前用本機 `INTEGER AUTOINCREMENT` id，`notes.highlight_id` 也參照本機整數 id——這些 id 跨裝置完全不穩定，若不處理，同步到另一裝置的紀錄會失去「屬於哪本書／依附哪筆劃線」的正確關聯。本文件（Architecting 階段 `/grill-with-docs`，2026-08-03）已解決此缺口，見「本機 Schema 變更」。

## Solution

新增一個獨立的同步子系統，涵蓋：

1. **同步帳號**：PocketBase Auth（email+password），base URL 可設定，token 存 `flutter_secure_storage`。
2. **本機 schema 變更**：`bookmarks`/`highlights`/`notes` 主鍵改為 UUID（`client_id` 概念，本機 id 與同步 id 合一）；新增 `content_fingerprint`／`updated_at`／`deleted_at`／`position_updated_at` 等同步所需欄位。
3. **PocketBase collection schema**：4 個 collection（`sync_reading_positions`／`sync_bookmarks`／`sync_highlights`／`sync_notes`），皆以 `user` relation 隔離不同使用者的資料。
4. **同步引擎**：checkpoint 觸發（App 背景化／書籍切換／5 分鐘閒置計時器，單一執行鎖防併發）→ 閱讀位置衝突預檢（PocketBase 伺服器蓋章時間戳記比對，異動則彈窗詢問）→ 分批推送（PocketBase Batch API，每批上限 100 筆）→ 下載遠端異動（以伺服器蓋章時間戳記為游標）→ 直接套用（劃線/備註/書籤，`client_id` 聯集）→ 本機墓碑清理。LWW／下載游標一律採 PocketBase 伺服器蓋章時間戳記，不依賴任何裝置自己的時鐘（避免時鐘偏差問題）。
5. **書籍內容指紋**：匯入時計算，EPUB 優先 OPF identifier、缺漏或 PDF/TXT 用全檔案串流 SHA-256（獨立 Isolate 執行，避免 UI 卡頓/OOM）。
6. **Settings「同步」子頁面**＋**PocketBase 自架 SOP 文件**（含墓碑清理 cron 建議）。

## Implementation Decisions

### 帳號模組

- 新增 `SyncAccountRepository`（暫名，供 Scrum Master 拆解工單時精確定義方法簽章）負責：
  - `baseUrl`：讀寫 `SharedPreferences`（既有慣例，非敏感資訊），key `sync_base_url`，未設定時的預設值為官方 base URL（實際網址由實作階段依專案實際部署節點填入，本規格不假設具體網域）。
  - `authToken`／`userId`／`email`：讀寫 `flutter_secure_storage`（ADR 0019 決策 3），僅這三項使用加密儲存，其餘同步相關的非敏感設定（base URL）維持 `SharedPreferences`。
  - 登入態：`authToken == null` 即視為未登入（opt-in，design.md 決策 9）。
- 核心操作（`SyncClient`，暫名）：
  - `Future<bool> testConnection(String baseUrl, String email, String password)`——實際呼叫 PocketBase `authWithPassword`，成功即視為登入成功（token 直接存入 `flutter_secure_storage`），不做「先測試、丟棄結果、再要求使用者按一次登入」的兩段式設計——測試連線成功本身就是一次成功的登入，UI 呈現一顆按鈕即可覆蓋 design.md 決策 14 的「測試連線」需求，不需要額外的無副作用 ping 端點。
  - `Future<void> logout()`——清除 `flutter_secure_storage` 內的 token/userId/email（FR-30），不影響任何本機資料（單機功能不受影響，design.md 決策 9）。
- 依賴：官方 `pocketbase` Dart package（pub.dev，鏡射官方 JS SDK 的 Auth／CRUD／Batch API 封裝），精確版本號留待 `plan-issue-N.md` 查證最新版本後定案。

### 本機 Schema 變更（SQLite v16 → v17）

- **`bookmarks`／`highlights`／`notes` 三表主鍵格式變更**：`id INTEGER PRIMARY KEY AUTOINCREMENT` → `id TEXT PRIMARY KEY`（UUID，`package:uuid` 或等效套件產生，由 Dart 端建立物件當下就指派，不再等待 SQLite 插入後才取得 id）。
  - `notes.highlight_id INTEGER REFERENCES highlights(id)` → `highlight_id TEXT REFERENCES highlights(id)`。
  - 對應 Dart 模型 `Bookmark`／`Highlight`／`Note` 的 `id` 欄位型別由 `int?` 改為 `String`（**不再 nullable**——UUID 建立物件當下即可指派，不像 AUTOINCREMENT 需要等資料庫回寫，`id` 語意上不再有「尚未指派」的中間狀態）；`Note.highlightId` 型別由 `int?` 改為 `String?`（保持 nullable，語意不變——`null` 代表「純備註、未依附任何劃線」，非本次變更範圍）。
  - `toMap()`（`Bookmark`/`Highlight`/`Note` 三個模型類別）需要跟著改為**包含** `id` 欄位（目前刻意省略、交由 `AUTOINCREMENT` 指派，改用 UUID 後必須由呼叫端明確寫入）；對應 repository 的 `insert()` 方法回傳型別由 `Future<int>`（SQLite rowid）改為 `Future<void>`（呼叫端已經知道自己指派的 UUID，不需要再問資料庫要回傳值）。
  - **既有裝置升級遷移**：`onUpgrade` 針對 `oldVersion < 17` 的裝置，對 `bookmarks`/`highlights`/`notes` 三表逐筆讀出既有整數 id 資料、產生新 UUID、寫回新表（SQLite 不支援直接 `ALTER COLUMN` 改型別，需要「建新表→搬資料→刪舊表→改名」的標準遷移手法，比照 SQLite 官方建議的 schema 變更流程）；遷移過程中同步建立「舊整數 id → 新 UUID」的暫時對照表（僅遷移當下記憶體內使用，不落地），用來正確重寫 `notes.highlight_id` 的參照值。
- **`books` 表新增欄位**：`content_fingerprint TEXT`（design.md 決策 5；`books.id` 本身格式不變，見「跨裝置參照設計」）、`position_updated_at INTEGER`（**純本機用途**——偵測「使用者是否在本機讀過、需要推送」，只跟自己上一次的 `lastPushCompletedAt` 比較，不跨裝置比較，見「同步引擎」時鐘偏差防護說明）、`position_synced_server_updated_at TEXT`（可空，快取上次成功同步時 PocketBase 該筆閱讀位置紀錄的伺服器時間戳記字串，供偵測「其他裝置是否在此之後又推送過」用，2026-08-03 spec 審查修正新增）。
- **`bookmarks`／`highlights`／`notes` 三表各自新增**：`updated_at INTEGER NOT NULL`（每次本機新增/修改時寫入目前時間戳記，**純本機用途**，只跟本機的 `lastPushCompletedAt` 比較決定是否需要推送，不跨裝置比較，見「同步引擎」）、`deleted_at INTEGER`（可空，軟刪除墓碑，design.md 決策 8——刪除操作改為 `UPDATE ... SET deleted_at = ?`，不再是真正的 `DELETE FROM`；既有的「刪除」UI/Repository 方法對外行為不變，內部實作改為軟刪除）。
- **新增本機同步中繼資料表**（暫名 `sync_metadata`，精確 schema 留待 `plan-issue-N.md`，2026-08-03 spec 審查修正調整為多游標設計）：
  - `lastPushCompletedAt INTEGER`（可空，`NULL` 代表從未成功推送過）：**純本機時鐘**，只用來跟本機各表的 `updated_at` 比較判斷「這筆紀錄我自己是否已經推送過」，只跟自己過去的寫入比較，不受其他裝置時鐘準不準影響。
  - 4 個 collection 各自的 `lastPulledServerUpdatedAt_<collection> TEXT`（可空字串，PocketBase 系統欄位 `updated` 的原始時間戳記字串，作為下次下載查詢的游標，見「同步引擎」）：**必須是 PocketBase 伺服器蓋章的時間戳記**，不得用本機時鐘產生，這是解決裝置時鐘偏差問題（原審查報告 Critical #3）的核心機制——2026-08-03 spec 審查修正採用「PocketBase 伺服器蓋章時間戳記」方案（見文末「審查修正紀錄」選項 B），取代客端自行計算時間偏差的方案。

### 跨裝置參照設計

- **書籍身份**：同步負載一律攜帶 `books.content_fingerprint`（不攜帶本機 `books.id`）。接收端收到帶指紋的同步紀錄時，先用指紋查本機 `books` 表；找不到比對得上的書籍時（該裝置尚未匯入這本書），該筆同步紀錄**暫緩合併**、留在待處理佇列，等使用者之後匯入同一本書、指紋比對上後才落地（不主動建立一個「空殼」`books` 列去承接同步資料——`books` 表其餘必要欄位如 `filePath`/`format` 在同步協定中本來就沒有傳遞，不足以生出一筆完整可用的 `books` 紀錄）。
- **劃線身份（供備註參照）**：`sync_notes` collection 的 `highlight_client_id` 欄位存放該筆備註依附的劃線之 `client_id`（即該劃線本機 `highlights.id` 的 UUID 值）；接收端合併備註時，若 `highlight_client_id` 非空，直接把它當作本機 `notes.highlight_id` 寫入（因為劃線的本機 id 現在就是全域唯一的 UUID，同步/本機共用同一個值，不需要額外轉換查表）。
- **`books.id` 本身維持現行格式不變**（時間戳記＋URI hash），不因本 Epic 改成 UUID——書籍的跨裝置身份比對已由 `content_fingerprint` 承擔，兩者是正交的不同機制，變更 `books.id` 格式零效益、徒增遷移成本（YAGNI，2026-08-03 Architecting 階段確認）。

### 書籍內容指紋計算

- 新增頂層函式（暫名於 `book_content_fingerprint.dart`，精確路徑留待 `plan-issue-N.md`）：`Future<String> computeBookContentFingerprint(String filePath, BookFileFormat format)`。
- **EPUB**：優先讀取 OPF identifier——擴充 `BookMetadataChannel.kt` 既有的 `extractEpubMetadata()`（`publication.metadata` 已是 Readium 既有物件，只需多讀一個既有欄位 `publication.metadata.identifier`，不需要新增 Readium 相依）回傳給 Dart 端；OPF identifier 為空/缺漏時，退回對整份 `.epub` 檔案內容算 SHA-256（與 PDF/TXT 同一套退回邏輯）。
- **PDF／TXT**：一律對整個檔案內容算 **SHA-256**（`package:crypto`，2026-08-03 Architecting 階段定案：不做抽樣頭尾雜湊，正確性優先於一次性匯入成本的些微效能差異，避免抽樣造成的誤判碰撞）。
- **必須串流計算，且必須在獨立 Isolate 執行**（2026-08-03 spec 審查修正，見文末「審查修正紀錄」）：**不得**用 `File.readAsBytes()` 把整個檔案一次讀進記憶體再算雜湊——PRD 明訂支援 100MB+ 檔案，且本專案已有過同類型全檔案讀入記憶體導致 OOM 閃退的真實事故（`epic-20` Issue 8，大型 EPUB 串流服務修復）。改用 `File.openRead()` 取得位元組串流，搭配 `package:crypto` 的 `sha256.startChunkedConversion()`（或等效的分區段餵入 API）逐塊計算；整個計算過程外包至 `Isolate.run()`（或 `compute()`），避免長時間佔用 UI isolate 造成畫面卡頓。精確實作寫法（`ChunkedConversionSink` 串接方式等）留待 `plan-issue-N.md`。
- 計算時機：`book_import_service_impl.dart` 匯入流程新增一步，寫入 `books.content_fingerprint`，與現有的封面產生/中繼資料擷取並列（**不**在既有的匯入速度關鍵路徑之外另開背景執行緒——匯入本身已是允許稍長時間的操作，不同於「開書」的 2 秒 SLA；上述 Isolate 隔離是為了不卡 UI 畫面，不是為了平行化匯入流程本身）。

### PocketBase Collection Schema

四個 collection，皆設定 API rule `user = @request.auth.id`（讀寫皆限定本人資料），`user` 為 PocketBase 內建 Auth collection（`users`）的 relation 欄位：

**LWW 比較基準改用 PocketBase 內建的 `updated`／`created` 系統欄位，不再另外自訂一個客端傳入的 `updated_at`／`position_updated_at` 欄位**（2026-08-03 spec 審查修正，解決裝置時鐘偏差問題，見文末「審查修正紀錄」）。PocketBase 每個 collection 內建的 `updated`/`created` 是**伺服器**在處理寫入當下蓋章、客端無法覆寫的權威時間戳記，不受任何一台裝置時鐘準不準影響；下載端據此排序/篩選（見「同步引擎」），完全不需要客端自行比較彼此的 `updated_at` 或計算時間偏差校正。

**`sync_reading_positions`**（一筆＝某使用者、某本書的閱讀進度，FR-19）：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `user` | relation (users) | 擁有者 |
| `book_fingerprint` | text | 對應本機 `books.content_fingerprint` |
| `epub_locator` | text, 可空 | EPUB CFI |
| `pdf_page_index` | number, 可空 | PDF 頁碼 |
| `progress` | number | 進度百分比 |
| _(`updated`／`created`)_ | _(PocketBase 內建)_ | 衝突比對基準，見上方說明，不另建自訂欄位 |

**`sync_bookmarks`／`sync_highlights`／`sync_notes`**（共通欄位）：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `user` | relation (users) | 擁有者 |
| `client_id` | text | 對應本機 UUID 主鍵（同一 user 底下唯一） |
| `book_fingerprint` | text | 對應本機 `books.content_fingerprint`，純文字欄位，不做 PocketBase relation（見 design.md「不特別建書籍 collection」的理由：合併邏輯在 App 端純函式進行，不依賴 PocketBase join，也不用煩惱「新書要先建立關聯紀錄」的先後順序問題） |
| `deleted_at` | number, 可空 | 軟刪除墓碑（本機語意欄位，記錄「使用者刪除當下」，用於墓碑保留期限判斷，非 LWW 比較用途，見下方「墓碑清理」） |

（不再自訂 `updated_at` 欄位——LWW／下載游標一律用 PocketBase 內建的 `updated` 系統欄位，見上方說明。）

`sync_bookmarks` 額外欄位（對應本機 `bookmarks` 表）：`name` (text)、`epub_locator_json` (text, 可空)、`progression` (number, 可空)、`pdf_page_index` (number, 可空)。

`sync_highlights` 額外欄位（對應本機 `highlights` 表）：`style` (text)、`epub_locator_json` (text, 可空)、`progression` (number, 可空)、`pdf_page_index` (number, 可空)、`pdf_rect_json` (text, 可空)。

`sync_notes` 額外欄位（對應本機 `notes` 表）：`text` (text)、`epub_locator_json` (text, 可空)、`progression` (number, 可空)、`highlight_client_id` (text, 可空——見「跨裝置參照設計」)、`pdf_page_index` (number, 可空)、`pdf_rect_json` (text, 可空)。

PocketBase 內建的 `id` 欄位（每個 collection 皆自動具備）純粹是 PocketBase 內部管理用途，App 端完全不讀取/比對它，避免依賴特定 PocketBase 版本對自訂 `id` 格式的支援程度（2026-08-03 Architecting 階段定案）。

### 墓碑清理（Tombstone Purge）

2026-08-03 spec 審查修正新增（原規劃未定義清理策略，屬長期累積的儲存空間問題）。範圍分本機／伺服器兩側，皆採**固定 30 天保留期限**（與 5 分鐘閒置計時器同等級——初始建議值，非定案硬性需求，未來可依實際使用量調整）：

- **本機**：`SyncEngine.runCheckpoint()` 每次成功完成後（見「同步引擎」），額外執行一次清理查詢：`bookmarks`/`highlights`/`notes` 三表中 `deleted_at IS NOT NULL AND deleted_at < (現在時間 - 30 天)` 的紀錄，一律真正 `DELETE FROM`（非軟刪除）。**只清理已確認推送成功的墓碑**——由於 `runCheckpoint()` 是先推送成功、再進到這個清理步驟，能執行到這裡代表本機所有異動（含刪除）都已經送達伺服器，不會有「刪除了但還沒同步出去、卻先被本機清掉」的風險。
- **伺服器**：不由 App／同步引擎負責（同步引擎只管本機這一側），改在 PocketBase 自架 SOP 文件新增一節，建議自架者設定 PocketBase `pb_hooks`（PocketBase 原生支援的 JS cron hook 機制）排程定期清理 4 個 `sync_*` collection 中 `deleted_at` 早於 30 天前的紀錄——這是伺服器端設定/維運工作，與「PocketBase 伺服器部署本身」同一分類，比照 design.md 既有的範圍界定（本 Epic 只交付 App 端程式碼＋部署/維運 SOP 文件，不交付伺服器端自動化腳本本身），SOP 文件範圍相應擴充為 5 個部分（原 4 個＋本節）。

### 同步引擎

- **Checkpoint 觸發**（design.md 決策 7，三選一）：
  1. App 生命週期監聽（`AppLifecycleState.paused`）。
  2. 書籍切換（離開 `ReaderScreen`）。
  3. 閱讀中每 5 分鐘閒置計時器（design.md 標記為初始建議值，2026-08-03 Architecting 階段確認維持，未來可能依真機測試調整，非本次定案的硬性需求）。
- **併發防護**（2026-08-03 spec 審查修正新增）：`SyncEngine` 內建單一執行鎖（例如一個 `bool _isSyncing` 旗標或等效的 async mutex）。三種 checkpoint 觸發來源可能在極短時間內（例如使用者切書同時把 App 丟到背景）幾乎同時各自呼叫 `runCheckpoint()`；若鎖已被佔用，後續觸發**直接放棄**（比照下方「同步失敗」的靜默重試精神——不排隊等待，因為排隊等待的那次觸發所代表的「此刻的本機異動」，下一次任何 checkpoint 自然會涵蓋到，不需要額外排隊機制）。
- **批次同步流程**（暫名 `SyncEngine.runCheckpoint()`，2026-08-03 spec 審查修正：改為「先推送、後下載」且移除跨裝置時間比較，見「PocketBase Collection Schema」關於改用伺服器蓋章時間戳記的說明）：
  1. **閱讀位置衝突預檢**（僅當本機 `books.position_updated_at > sync_metadata.lastPushCompletedAt`，代表這本書的閱讀位置自上次推送後有本機新異動時才執行）：對該本書查詢目前 PocketBase `sync_reading_positions` 紀錄目前的 `updated`（伺服器蓋章時間）；若這個值與本機快取的 `books.position_synced_server_updated_at` 不同（代表**其他裝置**在本機上次同步之後又推送過新的位置），視為衝突（FR-19），彈窗詢問使用者要保留本機還是雲端版本，使用者選擇前**不**把這本書的閱讀位置納入本次上傳批次（避免任一邊被靜默覆蓋）；若相同（沒有其他裝置動過）或本機這本書的位置本來就沒有待推送的異動，直接把本機值納入本次上傳批次。
  2. **推送**：把本機 `updated_at > sync_metadata.lastPushCompletedAt`（或 `deleted_at` 非空且尚未推送過）的所有 `bookmarks`/`highlights`/`notes` 異動，加上步驟 1 判定可推送的閱讀位置，組成 PocketBase Batch API 請求。**每筆 create/update payload 必須明確帶入 `user: <目前登入者 PocketBase user id>`**（2026-08-03 spec 審查修正：PocketBase 的 API rule 驗證送入紀錄本身的欄位值，不會自動幫忙填入，客端遺漏會導致 validation error 而非「自動判斷」）。**分批送出**（2026-08-03 spec 審查修正：每批最多 100 筆異動一個 Batch 請求，超過則拆成多個依序送出的 Batch 請求；長時間離線後累積大量異動時，避免單一請求超出 PocketBase Batch payload/請求數上限或逾時，精確批次上限數字留待 `plan-issue-N.md` 依實測結果微調，比照「5 分鐘閒置計時器」同等級的初始建議值）。推送過程中任一批失敗即視為本次 checkpoint 失敗，走下方「同步失敗」處理。
  3. **推送成功後**：更新 `sync_metadata.lastPushCompletedAt` 為現在（純本機時鐘寫入，只跟自己過去的值比較，不受其他裝置影響）；若步驟 1 有推送閱讀位置，同步更新該本書的 `books.position_synced_server_updated_at`（用 Batch API 回應中該筆紀錄的 `updated` 值回填，這是伺服器蓋章值，不是本機時鐘）。
  4. **下載**：對 4 個 collection 各自查詢一次「`updated` 系統欄位晚於 `sync_metadata.lastPulledServerUpdatedAt_<collection>`」（純 GET，不批次——量體小不需優化，2026-08-03 Architecting 階段定案）。由於步驟 2 已經把本機所有異動（含刪除）成功送達伺服器，下載回來的紀錄**直接覆寫本機對應紀錄即可**（`client_id` 找得到就更新、找不到就新增；`deleted_at` 非空的視同刪除狀態寫入），不需要再比較任何時間戳記——本機這一輪已經沒有待推送的「dirty」狀態需要保護，不會發生「較舊的下載結果蓋掉本機較新編輯」的問題。閱讀位置的下載端結果已在步驟 1 處理過，此步驟不重複處理閱讀位置。
  5. 下載完成後，把每個 collection 這次實際查到的紀錄中最大的 `updated` 值，更新回 `sync_metadata.lastPulledServerUpdatedAt_<collection>`（若這次沒查到任何新紀錄則維持原值不變）。
  6. **本機墓碑清理**：見「墓碑清理」章節，於本步驟（下載完成、checkpoint 即將結束）執行。
  7. **同步失敗（離線/逾時，發生於步驟 1-5 任一階段）**：本機異動已經先落地成功（不受影響），本次 checkpoint 直接整批放棄（design.md 決策 10）——不局部套用已完成的步驟（例如已推送成功但下載失敗，仍視整個 checkpoint 為失敗，不更新任何 `sync_metadata` 游標，包含已經推送成功那部分的 `lastPushCompletedAt` 也不更新，確保下次重試時這批已推送成功的異動會被重新判斷一次「是否需要推送」——由於 PocketBase 端該筆紀錄已經是最新狀態，重複推送同樣內容只是多一次無害的 Update()，不會造成資料錯誤，換取失敗處理邏輯的單純性，不需要記錄「哪些子步驟成功了」這種細緻狀態）。下一次任何 checkpoint 觸發時整批重新嘗試。

### Settings「同步」子頁面

- 新建 `SyncSettingsScreen`（暫名），入口比照既有「佈景」子頁面模式加進 `SettingsScreen`（design.md 決策 2）。
- 欄位：base URL（文字輸入，預設值見「帳號模組」）、email、password、「連線／登入」按鈕（`testConnection()`，成功即完成登入）、登出按鈕（已登入時顯示，呼叫 `logout()`）。
- 未登入時不顯示任何同步狀態相關 UI（opt-in，design.md 決策 9），已登入時可顯示「上次同步時間」等輔助資訊（精確文案/版面留待 `plan-issue-N.md`）。

### PocketBase 自架 SOP 文件

範圍界定（design.md「PocketBase 自架 SOP 文件」，2026-08-03 Architecting 階段確認，2026-08-03 spec 審查修正擴充為 5 個部分，純文件、**不含**自動化腳本本身——第 5 項的 `pb_hooks` 範例程式碼屬於「文件內附的設定範例」，供自架者複製使用，非本 Epic App 程式碼交付物）：

1. 最低版本需求：PocketBase ≥ 0.23（Batch API 需要）。
2. Collection 建立步驟：對照本文件「PocketBase Collection Schema」逐一列出欄位/型別/API rule 設定步驟。
3. 基本部署建議：官方 Docker image 最簡啟動範例（快速上手，非完整雲端架構評估）。
4. 備份建議：定期備份 PocketBase 的 SQLite 資料檔案（cron 排程複製檔案層級，非異地備援/高可用性）。
5. **墓碑清理建議**（2026-08-03 spec 審查修正新增）：`pb_hooks` JS cron 排程範例，定期清理 4 個 `sync_*` collection 中超過 30 天的 `deleted_at` 軟刪除紀錄，見「墓碑清理」章節。

## Migration

- SQLite 版本自 16 升級至 17：
  0. **遷移交易開始前，先 `PRAGMA foreign_keys = OFF;`**（2026-08-03 spec 審查修正，Critical：本專案 `sqlite_library_repository.dart:31` 的 `onConfigure` 已經 `PRAGMA foreign_keys = ON`，且 `onConfigure` 早於 `onUpgrade` 執行，若不暫停 FK 檢查，下方步驟 2 的「建新表→搬資料→刪舊表→改名」會在中繼狀態觸發 `foreign key constraint failed` 導致既有使用者升級當下閃退/資料庫損毀）。步驟 1-3 全部完成、驗證新表資料無誤後，遷移交易結束前**必須**恢復 `PRAGMA foreign_keys = ON;`，不可讓 App 之後在關閉 FK 檢查的狀態下繼續運作。
  1. `books` 新增 `content_fingerprint TEXT`／`position_updated_at INTEGER`／`position_synced_server_updated_at TEXT`。
  2. `bookmarks`/`highlights`/`notes` 三表主鍵由 `INTEGER AUTOINCREMENT` 改為 `TEXT`（UUID）：建新表→逐筆搬移既有資料（產生新 UUID、回填 `notes.highlight_id` 參照）→刪舊表→改名，比照 SQLite 官方建議的 schema 變更手法；同時新增 `updated_at`/`deleted_at` 兩欄位（既有資料 `updated_at` 回填為遷移當下時間戳記，`deleted_at` 為 `NULL`）。
  3. 新增 `sync_metadata` 表：`lastPushCompletedAt`（初始 `NULL`，代表從未成功推送過）＋ 4 個 collection 各自的 `lastPulledServerUpdatedAt_<collection>`（初始皆 `NULL`，代表從未下載過，下載查詢時 `NULL` 視為「查全部」）。
- **既有資料的 `content_fingerprint`**：既有已匯入書籍在升級當下**不**自動補算指紋（可能是大檔案、升級當下批次計算會拖慢啟動速度）；改為採用既有專案慣例（比照 `epic-17` `detectAndCacheEpubLayout()` 的「一次性補判斷」模式）——首次對該書觸發同步（或首次開啟該書、精確時機留待 `plan-issue-N.md`）時才補算並回填，`content_fingerprint` 為 `NULL` 期間該書不參與跨裝置比對（該裝置尚無同步紀錄，不影響單機使用）。

## Testing Decisions

- **接縫**：同步引擎的核心邏輯設計為純函式，不依賴 PocketBase SDK 或資料庫，可離線單元測試，比照本專案既有的「純函式優先、易於測試」慣例（如 `resolveZoneActions()`／`resolveCustomFontUri()` 等既有先例）：
  - 推送批次組裝（哪些本機紀錄算 dirty、如何分批）。
  - 閱讀位置衝突判定（本機 `position_updated_at` 是否晚於 `lastPushCompletedAt`、伺服器 `updated` 是否不同於 `position_synced_server_updated_at`，回傳「需要詢問使用者」／「直接套用本機」／「不需要動作」三選一）。
  - 墓碑清理的篩選條件（`deleted_at` 早於 30 天前）。
- **`app/test/`**（純 widget/unit test，不需真機/不需真實 PocketBase 伺服器）：
  - 書籍內容指紋純函式：已知 OPF identifier 的 EPUB fixture 解析正確；缺漏 identifier 退回 SHA-256；PDF/TXT 一律 SHA-256；同一檔案兩次計算結果一致（確定性）；大檔案 fixture（例如 >10MB，測試環境不需真的用到 100MB）驗證確實透過串流讀取而非一次性載入全部位元組（例如檢查記憶體峰值，或至少確認呼叫路徑走 `File.openRead()` 而非 `readAsBytes()`）。
  - Schema migration（v16→v17）：**驗證遷移過程中 `PRAGMA foreign_keys` 正確暫停又恢復**（既有裝置升級時 `notes.highlight_id` 參照未失效的既有 FK 約束測試，若忘記關閉 FK 檢查應能重現 `foreign key constraint failed` 失敗，藉此確認回歸測試真的有涵蓋到這個情境）；`bookmarks`/`highlights`/`notes` 既有整數 id 資料正確轉換為 UUID，`notes.highlight_id` 參照正確回填為對應劃線的新 UUID，新增欄位有正確預設值。
  - 推送批次組裝純函式：dirty 判定（`updated_at > lastPushCompletedAt`）正確；異動筆數超過分批上限（如 101 筆）時正確拆成兩個批次。
  - 閱讀位置衝突判定純函式：本機 dirty 且伺服器 `updated` 與快取值不同 → 「需要詢問使用者」；本機 dirty 但伺服器 `updated` 與快取值相同 → 「直接套用本機」；本機不 dirty → 「不需要動作」。
  - `SyncEngine` 併發鎖：模擬兩次幾乎同時呼叫 `runCheckpoint()`，驗證第二次呼叫在第一次仍執行中時直接放棄、不會兩次同時真的送出網路請求。
  - 墓碑清理純函式：`deleted_at` 早於/晚於 30 天前的篩選正確；未設定 `deleted_at`（未刪除）的紀錄不受影響。
  - `SyncSettingsScreen`：未登入/已登入兩種狀態的 UI 呈現、登出按鈕清除憑證。
- **`app/integration_test/`**（真機，需要一個可連線的測試用 PocketBase 實例，精確測試環境建置方式留待 `plan-issue-N.md`）：端到端 checkpoint 觸發後，真的透過 PocketBase Batch API 成功寫入/讀回資料。

## Out of Scope

見 `design.md`「明確排除」，本文件不重複列出。

## Further Notes

- 本規格未列出所有欄位/方法的最終精確簽章（例如 `SyncEngine`/`SyncClient`/`SyncAccountRepository` 確切的 method 參數/回傳型別、`sync_metadata` 表的精確欄位設計），實作前請參閱 `design.md`「架構影響摘要」與本文件「Implementation Decisions」，實際簽章留待實作計畫階段（`plans/plan-issue-N.md`）決定（比照本專案一貫的 spec.md 慣例，見 `epic-14-system-settings/spec.md`「Further Notes」先例）。
- `bookmarks`/`highlights`/`notes` 主鍵改為 UUID 是本文件相對於 `design.md`／ADR 0020 原始措辭的一項修訂（原規劃是另外疊加一個獨立 `sync_id` 欄位）——2026-08-03 Architecting 階段 `/grill-with-docs` 過程中確認「本機 id 與同步 id 合一」更簡潔，已同步修訂 ADR 0020 決策 3 措辭，此處重申供實作者留意：**不要**依照 `design.md` 字面上「新增 `sync_id` 欄位」的舊措辭實作，以本文件「本機 Schema 變更」章節為準。

## 審查修正紀錄（`tmp/epic-8/spec-review.md`）

程式碼審查（`/superpowers:requesting-code-review`，2026-08-03）針對第一版 `spec.md` 提出 3 項 Critical、4 項 Important、2 項 Minor。逐項核對程式碼庫現況（`sqlite_library_repository.dart` 既有 `PRAGMA foreign_keys = ON`、`CLAUDE.md` 記載 `epic-20` Issue 8 真實發生過的大檔案 OOM 事故）後，結論如下：

- **Critical（確認屬實，已採納）**：SQLite v16→v17 遷移建新表流程未處理 FK 約束暫停，既有裝置升級會因 `PRAGMA foreign_keys = ON` 觸發 `foreign key constraint failed` 崩潰。已於「Migration」章節補上明確的 `PRAGMA foreign_keys = OFF/ON` 步驟。
- **Critical（確認屬實，已採納）**：書籍內容指紋計算對大檔案（100MB+，PRD 既有規格）一次性讀入記憶體有 OOM 與 UI 卡頓風險，且本專案已有過同類型真實事故（`epic-20` Issue 8）。已於「書籍內容指紋計算」章節改為要求串流讀取（`File.openRead()` + `sha256.startChunkedConversion()`）＋獨立 Isolate（`Isolate.run()`/`compute()`）執行。
- **Critical（確認屬實，但未採納審查報告的原始建議方案，改採更簡單的替代方案，人類已確認採用替代方案）**：Last-Write-Wins 依賴客端 `updated_at` 比較，確實有裝置時鐘偏差風險（目標裝置涵蓋 E-Ink 閱讀器，時間不準是真實情境）。審查報告建議客端自行計算與伺服器的時間偏差並校正寫入值；改採**用 PocketBase 內建的伺服器蓋章 `updated`/`created` 系統欄位取代自訂 `updated_at` 欄位作為跨裝置比較基準**，完全不需要客端計算時間偏差——本機端的 `updated_at` 欄位保留但改為純本機用途（只跟自己的 `lastPushCompletedAt` 比較判斷是否需要推送，同一裝置同一時鐘，不受偏差影響）。此修訂連帶重新設計「同步引擎」的推送/下載順序（先推送、後下載，見該章節），比原規劃的「雙邊比較 `updated_at`」更單純。
- **Important（確認屬實，已採納，人類確認納入本 Epic 範圍）**：PocketBase Batch API payload 缺乏分頁/大小限制，長時間離線後累積大量異動時有超出上限風險。已於「同步引擎」補上固定分批上限（100 筆/批）。
- **Important（確認屬實，原建議判定為超出本 Epic 範圍，人類確認納入本 Epic 範圍後已採納）**：軟刪除墓碑缺乏清理策略，長期累積影響查詢/同步效能。已新增「墓碑清理」章節，本機由 `SyncEngine` 於每次 checkpoint 後清理（30 天保留期限），伺服器端則納入 PocketBase 自架 SOP 文件（`pb_hooks` cron 範例），SOP 文件範圍相應由 4 項擴充為 5 項。
- **Important（確認屬實，已採納）**：三種 checkpoint 觸發來源可能短時間內幾乎同時觸發，`SyncEngine` 缺乏併發保護。已於「同步引擎」補上單一執行鎖，後續觸發於鎖定期間直接放棄（比照既有「同步失敗」的靜默重試精神，不做排隊機制）。
- **Important（確認屬實，已採納）**：PocketBase Batch API create payload 未明確要求帶入 `user` 欄位，可能導致 API rule validation 失敗。已於「同步引擎」推送步驟明確補上此要求。
- **Minor（確認屬實，已採納）**：DAO/Repository 層受主鍵型別變更影響的完整範圍（`delete(int id)`／`getById(int id)` 等），已於「本機 Schema 變更」章節提醒 `plan-issue-N.md` 階段需完整盤點。
- **Minor（確認屬實，已採納）**：時間戳記單位一致性——本機端 `*_at` 欄位皆沿用本專案既有慣例的毫秒（`DateTime.now().millisecondsSinceEpoch`，與既有 `createTime`/`lastReadTime` 等欄位同單位，非本次新增決策）；PocketBase 端已改用其內建 `updated`/`created` 系統欄位（ISO 8601 字串格式，非本專案自訂），不存在單位不一致的自訂數值欄位需要另外約定。
