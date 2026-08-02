# Epic 8 — 雲端同步：規格 (Spec)

這是實作 `epic-8-sync` 的唯一事實來源。決策的完整討論過程與理由請見 `design.md`（`/grill-with-docs` 2026-08-02，14 項決策）與 [ADR 0019](../../adr/0019-pocketbase-sync-account-architecture.md)（同步帳號架構）／[ADR 0020](../../adr/0020-cross-device-sync-strategy.md)（跨裝置同步策略，2026-08-03 Architecting 階段修訂 `sync_id`→`client_id` 措辭）。本文件延續 `design.md` 的所有範圍界定，不重複列出理由，僅在此定案核心介面/型別，供 Scrum Master 階段拆解工單使用。

## Problem Statement

見 `design.md`「問題陳述」。本文件額外釐清 Discovery 階段未發現的一個架構缺口：`bookmarks`/`highlights`/`notes` 三表目前用本機 `INTEGER AUTOINCREMENT` id，`notes.highlight_id` 也參照本機整數 id——這些 id 跨裝置完全不穩定，若不處理，同步到另一裝置的紀錄會失去「屬於哪本書／依附哪筆劃線」的正確關聯。本文件（Architecting 階段 `/grill-with-docs`，2026-08-03）已解決此缺口，見「本機 Schema 變更」。

## Solution

新增一個獨立的同步子系統，涵蓋：

1. **同步帳號**：PocketBase Auth（email+password），base URL 可設定，token 存 `flutter_secure_storage`。
2. **本機 schema 變更**：`bookmarks`/`highlights`/`notes` 主鍵改為 UUID（`client_id` 概念，本機 id 與同步 id 合一）；新增 `content_fingerprint`／`updated_at`／`deleted_at`／`position_updated_at` 等同步所需欄位。
3. **PocketBase collection schema**：4 個 collection（`sync_reading_positions`／`sync_bookmarks`／`sync_highlights`／`sync_notes`），皆以 `user` relation 隔離不同使用者的資料。
4. **同步引擎**：checkpoint 觸發（App 背景化／書籍切換／5 分鐘閒置計時器）→ 批次上傳（PocketBase Batch API）＋下載遠端異動 → 合併（id 聯集＋`updated_at`，閱讀位置例外走衝突彈窗）。
5. **書籍內容指紋**：匯入時計算，EPUB 優先 OPF identifier、缺漏或 PDF/TXT 用全檔案 SHA-256。
6. **Settings「同步」子頁面**＋**PocketBase 自架 SOP 文件**。

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
- **`books` 表新增欄位**：`content_fingerprint TEXT`（design.md 決策 5；`books.id` 本身格式不變，見「跨裝置參照設計」）、`position_updated_at INTEGER`（供 FR-19 衝突比對用）。
- **`bookmarks`／`highlights`／`notes` 三表各自新增**：`updated_at INTEGER NOT NULL`（每次本機新增/修改時寫入目前時間戳記）、`deleted_at INTEGER`（可空，軟刪除墓碑，design.md 決策 8——刪除操作改為 `UPDATE ... SET deleted_at = ?`，不再是真正的 `DELETE FROM`；既有的「刪除」UI/Repository 方法對外行為不變，內部實作改為軟刪除）。
- **新增本機同步中繼資料表**（暫名 `sync_metadata`，單列或 key-value 皆可，精確 schema 留待 `plan-issue-N.md`）：至少需要記錄「上次成功同步的時間戳記」，供下載遠端異動時的增量查詢（`updated_at > lastSyncedAt`）使用。

### 跨裝置參照設計

- **書籍身份**：同步負載一律攜帶 `books.content_fingerprint`（不攜帶本機 `books.id`）。接收端收到帶指紋的同步紀錄時，先用指紋查本機 `books` 表；找不到比對得上的書籍時（該裝置尚未匯入這本書），該筆同步紀錄**暫緩合併**、留在待處理佇列，等使用者之後匯入同一本書、指紋比對上後才落地（不主動建立一個「空殼」`books` 列去承接同步資料——`books` 表其餘必要欄位如 `filePath`/`format` 在同步協定中本來就沒有傳遞，不足以生出一筆完整可用的 `books` 紀錄）。
- **劃線身份（供備註參照）**：`sync_notes` collection 的 `highlight_client_id` 欄位存放該筆備註依附的劃線之 `client_id`（即該劃線本機 `highlights.id` 的 UUID 值）；接收端合併備註時，若 `highlight_client_id` 非空，直接把它當作本機 `notes.highlight_id` 寫入（因為劃線的本機 id 現在就是全域唯一的 UUID，同步/本機共用同一個值，不需要額外轉換查表）。
- **`books.id` 本身維持現行格式不變**（時間戳記＋URI hash），不因本 Epic 改成 UUID——書籍的跨裝置身份比對已由 `content_fingerprint` 承擔，兩者是正交的不同機制，變更 `books.id` 格式零效益、徒增遷移成本（YAGNI，2026-08-03 Architecting 階段確認）。

### 書籍內容指紋計算

- 新增頂層函式（暫名於 `book_content_fingerprint.dart`，精確路徑留待 `plan-issue-N.md`）：`Future<String> computeBookContentFingerprint(String filePath, BookFileFormat format)`。
- **EPUB**：優先讀取 OPF identifier——擴充 `BookMetadataChannel.kt` 既有的 `extractEpubMetadata()`（`publication.metadata` 已是 Readium 既有物件，只需多讀一個既有欄位 `publication.metadata.identifier`，不需要新增 Readium 相依）回傳給 Dart 端；OPF identifier 為空/缺漏時，退回對整份 `.epub` 檔案內容算 SHA-256（與 PDF/TXT 同一套退回邏輯）。
- **PDF／TXT**：一律對整個檔案內容算 **SHA-256**（`package:crypto`，2026-08-03 Architecting 階段定案：不做抽樣頭尾雜湊，正確性優先於一次性匯入成本的些微效能差異，避免抽樣造成的誤判碰撞）。
- 計算時機：`book_import_service_impl.dart` 匯入流程新增一步，寫入 `books.content_fingerprint`，與現有的封面產生/中繼資料擷取並列（**不**在既有的匯入速度關鍵路徑之外另開背景執行緒——匯入本身已是允許稍長時間的操作，不同於「開書」的 2 秒 SLA）。

### PocketBase Collection Schema

四個 collection，皆設定 API rule `user = @request.auth.id`（讀寫皆限定本人資料），`user` 為 PocketBase 內建 Auth collection（`users`）的 relation 欄位：

**`sync_reading_positions`**（一筆＝某使用者、某本書的閱讀進度，FR-19）：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `user` | relation (users) | 擁有者 |
| `book_fingerprint` | text | 對應本機 `books.content_fingerprint` |
| `epub_locator` | text, 可空 | EPUB CFI |
| `pdf_page_index` | number, 可空 | PDF 頁碼 |
| `progress` | number | 進度百分比 |
| `position_updated_at` | number | 對應本機 `books.position_updated_at`，衝突比對用 |

**`sync_bookmarks`／`sync_highlights`／`sync_notes`**（共通欄位）：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `user` | relation (users) | 擁有者 |
| `client_id` | text | 對應本機 UUID 主鍵（同一 user 底下唯一） |
| `book_fingerprint` | text | 對應本機 `books.content_fingerprint`，純文字欄位，不做 PocketBase relation（見 design.md「不特別建書籍 collection」的理由：合併邏輯在 App 端純函式進行，不依賴 PocketBase join，也不用煩惱「新書要先建立關聯紀錄」的先後順序問題） |
| `updated_at` | number | 對應本機同名欄位，last-write-wins 比較基準 |
| `deleted_at` | number, 可空 | 軟刪除墓碑 |

`sync_bookmarks` 額外欄位（對應本機 `bookmarks` 表）：`name` (text)、`epub_locator_json` (text, 可空)、`progression` (number, 可空)、`pdf_page_index` (number, 可空)。

`sync_highlights` 額外欄位（對應本機 `highlights` 表）：`style` (text)、`epub_locator_json` (text, 可空)、`progression` (number, 可空)、`pdf_page_index` (number, 可空)、`pdf_rect_json` (text, 可空)。

`sync_notes` 額外欄位（對應本機 `notes` 表）：`text` (text)、`epub_locator_json` (text, 可空)、`progression` (number, 可空)、`highlight_client_id` (text, 可空——見「跨裝置參照設計」)、`pdf_page_index` (number, 可空)、`pdf_rect_json` (text, 可空)。

PocketBase 內建的 `id` 欄位（每個 collection 皆自動具備）純粹是 PocketBase 內部管理用途，App 端完全不讀取/比對它，避免依賴特定 PocketBase 版本對自訂 `id` 格式的支援程度（2026-08-03 Architecting 階段定案）。

### 同步引擎

- **Checkpoint 觸發**（design.md 決策 7，三選一）：
  1. App 生命週期監聽（`AppLifecycleState.paused`）。
  2. 書籍切換（離開 `ReaderScreen`）。
  3. 閱讀中每 5 分鐘閒置計時器（design.md 標記為初始建議值，2026-08-03 Architecting 階段確認維持，未來可能依真機測試調整，非本次定案的硬性需求）。
- **批次同步流程**（暫名 `SyncEngine.runCheckpoint()`）：
  1. **上傳**：查詢本機 `updated_at > sync_metadata.lastSyncedAt`（或 `deleted_at` 非空）的所有 `bookmarks`/`highlights`/`notes` 異動，加上當前 `books.position_updated_at` 若比 `lastSyncedAt`新，組成一個 PocketBase Batch API 請求（design.md 決策 7、Architecting 階段定案），一次 HTTP 請求送出全部異動。
  2. **下載**：對 4 個 collection 各自查詢一次「`updated_at > lastSyncedAt`」（純 GET，不批次——量體小不需優化，2026-08-03 Architecting 階段定案）。
  3. **合併**：
     - 閱讀位置（FR-19）：本機與雲端 `position_updated_at` 不同且雙方皆晚於 `lastSyncedAt`（代表雙方都在上次同步後各自變動過）→ 彈窗詢問使用者要保留哪一邊（design.md 決策 8「維持既有明文規則」），使用者選擇前不寫入任何一邊，避免靜默覆蓋（FR-19 硬性要求）。只有一邊變動則直接套用該邊。
     - 劃線/備註/書籤（FR-20）：id（`client_id`）聯集，雙方都有同一 id 時比較 `updated_at`，新的蓋舊的（last-write-wins，design.md 決策 8）；`deleted_at` 非空的一律視為刪除狀態參與合併（軟刪除墓碑蓋過較舊的非刪除版本，反之則不會讓已刪除的紀錄意外復活）。
  4. 合併完成後更新 `sync_metadata.lastSyncedAt` 為本次 checkpoint 開始時的時間戳記。
  5. **同步失敗（離線/逾時）**：本機異動已經先落地成功（不受影響），本次 checkpoint 的上傳/下載步驟直接放棄、不重試、不彈錯誤視窗（design.md 決策 10），`lastSyncedAt` 不更新，下一次任何 checkpoint 觸發時整批重新嘗試。

### Settings「同步」子頁面

- 新建 `SyncSettingsScreen`（暫名），入口比照既有「佈景」子頁面模式加進 `SettingsScreen`（design.md 決策 2）。
- 欄位：base URL（文字輸入，預設值見「帳號模組」）、email、password、「連線／登入」按鈕（`testConnection()`，成功即完成登入）、登出按鈕（已登入時顯示，呼叫 `logout()`）。
- 未登入時不顯示任何同步狀態相關 UI（opt-in，design.md 決策 9），已登入時可顯示「上次同步時間」等輔助資訊（精確文案/版面留待 `plan-issue-N.md`）。

### PocketBase 自架 SOP 文件

範圍界定（design.md「PocketBase 自架 SOP 文件」，2026-08-03 Architecting 階段確認 4 個部分，純文件、不含自動化腳本/程式碼）：

1. 最低版本需求：PocketBase ≥ 0.23（Batch API 需要）。
2. Collection 建立步驟：對照本文件「PocketBase Collection Schema」逐一列出欄位/型別/API rule 設定步驟。
3. 基本部署建議：官方 Docker image 最簡啟動範例（快速上手，非完整雲端架構評估）。
4. 備份建議：定期備份 PocketBase 的 SQLite 資料檔案（cron 排程複製檔案層級，非異地備援/高可用性）。

## Migration

- SQLite 版本自 16 升級至 17：
  1. `books` 新增 `content_fingerprint TEXT`／`position_updated_at INTEGER`。
  2. `bookmarks`/`highlights`/`notes` 三表主鍵由 `INTEGER AUTOINCREMENT` 改為 `TEXT`（UUID）：建新表→逐筆搬移既有資料（產生新 UUID、回填 `notes.highlight_id` 參照）→刪舊表→改名，比照 SQLite 官方建議的 schema 變更手法；同時新增 `updated_at`/`deleted_at` 兩欄位（既有資料 `updated_at` 回填為遷移當下時間戳記，`deleted_at` 為 `NULL`）。
  3. 新增 `sync_metadata` 表（初始 `lastSyncedAt` 為 `NULL`，代表從未同步過）。
- **既有資料的 `content_fingerprint`**：既有已匯入書籍在升級當下**不**自動補算指紋（可能是大檔案、升級當下批次計算會拖慢啟動速度）；改為採用既有專案慣例（比照 `epic-17` `detectAndCacheEpubLayout()` 的「一次性補判斷」模式）——首次對該書觸發同步（或首次開啟該書、精確時機留待 `plan-issue-N.md`）時才補算並回填，`content_fingerprint` 為 `NULL` 期間該書不參與跨裝置比對（該裝置尚無同步紀錄，不影響單機使用）。

## Testing Decisions

- **接縫**：同步引擎的合併邏輯（id 聯集／`updated_at` 比較／軟刪除墓碑）設計為純函式（輸入本機清單＋遠端清單，輸出合併後清單＋待寫回本機的差異），不依賴 PocketBase SDK 或資料庫，可離線單元測試，比照本專案既有的「純函式優先、易於測試」慣例（如 `resolveZoneActions()`／`resolveCustomFontUri()` 等既有先例）。
- **`app/test/`**（純 widget/unit test，不需真機/不需真實 PocketBase 伺服器）：
  - 書籍內容指紋純函式：已知 OPF identifier 的 EPUB fixture 解析正確；缺漏 identifier 退回 SHA-256；PDF/TXT 一律 SHA-256；同一檔案兩次計算結果一致（確定性）。
  - Schema migration（v16→v17）：`bookmarks`/`highlights`/`notes` 既有整數 id 資料正確轉換為 UUID，`notes.highlight_id` 參照正確回填為對應劃線的新 UUID，新增欄位有正確預設值。
  - 合併純函式：id 聯集各種情境（僅本機有／僅遠端有／雙方皆有取新的／軟刪除墓碑蓋過較舊非刪除版本／已刪除的不會被較舊的遠端版本復活）。
  - 閱讀位置衝突判定純函式：雙方皆變動過→回傳「需要詢問使用者」；僅一邊變動→回傳「直接套用該邊」。
  - `SyncSettingsScreen`：未登入/已登入兩種狀態的 UI 呈現、登出按鈕清除憑證。
- **`app/integration_test/`**（真機，需要一個可連線的測試用 PocketBase 實例，精確測試環境建置方式留待 `plan-issue-N.md`）：端到端 checkpoint 觸發後，真的透過 PocketBase Batch API 成功寫入/讀回資料。

## Out of Scope

見 `design.md`「明確排除」，本文件不重複列出。

## Further Notes

- 本規格未列出所有欄位/方法的最終精確簽章（例如 `SyncEngine`/`SyncClient`/`SyncAccountRepository` 確切的 method 參數/回傳型別、`sync_metadata` 表的精確欄位設計），實作前請參閱 `design.md`「架構影響摘要」與本文件「Implementation Decisions」，實際簽章留待實作計畫階段（`plans/plan-issue-N.md`）決定（比照本專案一貫的 spec.md 慣例，見 `epic-14-system-settings/spec.md`「Further Notes」先例）。
- `bookmarks`/`highlights`/`notes` 主鍵改為 UUID 是本文件相對於 `design.md`／ADR 0020 原始措辭的一項修訂（原規劃是另外疊加一個獨立 `sync_id` 欄位）——2026-08-03 Architecting 階段 `/grill-with-docs` 過程中確認「本機 id 與同步 id 合一」更簡潔，已同步修訂 ADR 0020 決策 3 措辭，此處重申供實作者留意：**不要**依照 `design.md` 字面上「新增 `sync_id` 欄位」的舊措辭實作，以本文件「本機 Schema 變更」章節為準。
