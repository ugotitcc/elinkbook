# Epic 8 — 雲端同步：設計 (Design)

> 本文件由 `/grill-with-docs` 2026-08-02 逐項確認產生。**本次僅完成 Discovery 階段**；Architecting（`spec.md`）／Scrum Master（`issues.md`）／實作皆刻意延後，待 `epic-14-system-settings` 完成後才動工（見「開發排程修正」）。

## 問題陳述

FR-19/20/30 要求：閱讀進度（EPUB CFI／PDF 頁碼）在 App 關閉或切換書籍時自動同步至雲端，衝突時須詢問使用者、不得靜默覆蓋；劃線/備註/書籤與雲端帳號綁定，2 秒內完成同步；支援雲端帳號登出。後端已決策採用 **PocketBase**（`CLAUDE.md`）。目前專案完全是單機架構：`Book.id` 是本機時間戳記＋URI hash 產生（非跨裝置穩定）、`bookmarks`/`highlights`/`notes` 用本機自增整數 id、資料庫（v15）沒有任何 `updated_at`/dirty flag/soft-delete 欄位、零 connectivity/offline 既有模式、零帳號機制、`pubspec.yaml` 沒有任何 HTTP/PocketBase 相依套件——本 Epic 是從零開始的全新子系統。

## 開發排程修正

原排序決議（2026-07-14 `/grill-with-docs`，見 `docs/epics.md` 舊版 `epic-8-sync`／`epic-14-system-settings` 列）：單機閱讀優先波次 **5 → 7 → 14 → 6 → 8**。實際執行中 `epic-6-annotations`（2026-07-18 歸檔）先於 `epic-7-interaction`（2026-07-24 歸檔）完成，且 `epic-14-system-settings` 至今尚未啟動——已偏離原排序（既成事實，`epic-6` 提前完成不可逆）。2026-08-02 人類於本次 `/grill-with-docs` 過程中發現此偏離，決定**回頭修正剩餘順序**：`epic-8-sync` 的 Discovery（本文件）先完成，但 Architecting／Scrum Master／實作階段一律延後至 `epic-14-system-settings` 完成之後才開始，恢復原計畫「14 先於 8」的精神。

## 範圍界定

### 包含範圍

- **elinkBook 同步帳號**（PocketBase Auth，email+password）：註冊／登入／登出，帳號完全可選（opt-in，不登入也能完整使用 App 的所有既有單機功能）。
- **Settings「同步」子頁面**：帳號密碼欄位、可設定的 PocketBase base URL（預設帶一組官方 URL，可改）、「測試連線」按鈕（驗證 base URL + 帳密組合可連通）、登出按鈕（FR-30）——直接滿足 FR-39（同步設定入口），不需要另立小工單補到 `epic-14`。
- **閱讀位置同步**（FR-19）：EPUB（CFI）／PDF（頁碼），checkpoint 觸發（App 背景化／書籍切換／閱讀中每 5 分鐘閒置計時器三者之一），偵測到本機與雲端不一致時彈窗詢問使用者。
- **劃線/備註/書籤同步**（FR-20）：同一組 checkpoint 觸發，逐筆合併（id 聯集＋`updated_at`＋軟刪除墓碑），不彈窗。
- **跨裝置書籍身份比對**：新增書籍內容指紋欄位，同步時以指紋而非本機 `Book.id` 比對「是否為同一本書」。
- **離線容忍**：同步失敗（無網路）靜默重試，下一次 checkpoint 自然補上，不做佇列/退避機制。
- **PocketBase 自架 SOP 文件**：本 Epic 收尾產出，供人類日後自行架設/更新伺服器。

### 明確排除

- **FR-02（雲端匯入來源帳號：Google Drive／OneDrive／Dropbox）**——目前完全沒有任何 Epic 追蹤，是遺落的 P0 缺口，但與本 Epic 的 elinkBook 同步帳號是完全不同的帳號體系（見「決策 #1」），另開新 Epic 處理，不併入本 Epic。
- **PocketBase 伺服器部署本身**（Docker/雲端主機/PocketBase Cloud 方案選擇、實際上線）——純 DevOps 工作，本 Epic 只假設「base URL 已存在」，只產出自架 SOP 文件供人類自行操作。
- **TXT 字元偏移量同步**——比照 `epic-5-toc-pagination`／`epic-6-annotations` 既有慣例，暫緩至 `epic-11-txt-engine` 完成後才補。
- **FR-21（社群分享）**——P3，獨立需求，不屬於本 Epic。
- **書籍檔案本身的雲端儲存/串流**——PRD 明確排除電子書商店/租閱，本 Epic 只同步「進度／劃線／備註／書籤」這些後設資料，不同步書籍檔案本體。
- **OAuth 第三方登入**（Google/Apple 等）——只做 email+password，理由見決策 #3。
- **同步佇列/重試退避演算法**——採靜默重試＋下次 checkpoint 自然補上，不做額外的佇列/退避機制。

## 決策紀錄（Discovery 逐項確認）

| # | 決策點 | 採用結果 |
|---|---|---|
| 1 | 「雲端帳號」語彙衝突與範圍界定 | 明確區分**雲端匯入來源帳號**（FR-02，Google Drive/OneDrive，目前無 Epic 追蹤的缺口）與 **elinkBook 同步帳號**（FR-19/20/30，PocketBase，本 Epic）；本 Epic 只做後者。Settings 頁面結構上可預留「雲端帳號」大分類的位置，但本 Epic 只實作「elinkBook 同步」這一項 |
| 2 | 入口 UI 放置位置 | 放進既有的 **Settings「同步」子頁面**（`SettingsScreen` 已於 `epic-18` Issue 24 建立，比照「佈景」的模式新增一個 `ListTile` 入口），不做暫代按鈕，也不等 `epic-14` 才做——因為 `SettingsScreen` 已存在，直接加子頁面即可，同時滿足 FR-39 |
| 3 | PocketBase 伺服器現況 | 尚未架設，本 Epic 假設「base URL 已存在」，伺服器部署本身視為外部前置作業，不算進工單範圍；本 Epic 收尾產出一份自架 SOP 文件 |
| 4 | 登入方式 | 只做 **email + password**（PocketBase 內建），不做 OAuth——目標裝置涵蓋無 GMS 環境的 E-Ink 閱讀器，OAuth（尤其 Google Sign-In）在無 GMS 環境常需另接 Web-based fallback，徒增複雜度；email+password 開箱即用、零額外 SDK |
| 5 | 跨裝置書籍身份比對 | 新增**書籍內容指紋**欄位（EPUB 優先用 OPF identifier／ISBN，否則用檔案內容 hash；PDF/TXT 用檔案內容 hash），匯入時計算存入；同步時用指紋比對「是否為同一本書」，而非本機 `Book.id`（本機 id 是時間戳記＋URI hash，跨裝置不穩定，見「問題陳述」） |
| 6 | TXT 範圍 | 比照 `epic-5`/`epic-6` 既有慣例，本次同步 schema 只处理 EPUB/PDF，不預留 TXT 字元偏移量欄位；等 `epic-11-txt-engine` 啟動時再用新 migration 補 |
| 7 | 同步觸發時機（checkpoint） | **批次觸發**，非逐筆即時：(a) App 背景化（`AppLifecycleState.paused`）、(b) 書籍切換（離開閱讀器）、(c) 閱讀中每 5 分鐘的閒置計時器（堵住「長時間不背景化也不切書」的漏洞，避免另一裝置長期看不到最新異動）。三者任一觸發即對「期間累積的所有異動」做一次批次同步 |
| 8 | 劃線/備註/書籤合併策略 | **逐筆合併（merge by item），不彈窗**：每筆需要全域唯一 id（UUID）＋`updated_at`＋軟刪除的 `deleted_at`（墓碑，避免「A 已刪除、B 還沒同步到又同步回來復活」）。合併規則＝id 聯集，同一 id 兩邊都有時比較 `updated_at`、新的蓋舊的。閱讀位置（單一值，FR-19）維持既有規則：本機與雲端不一致時彈窗詢問，不自動合併 |
| 9 | 帳號必要性 | **完全可選（opt-in）**——不登入/不建立同步帳號也能完整使用 App 所有既有單機功能，跟目前產品「單機優先」的既有慣例一致，也跟 FR-30（登出後回到純本機模式）的隱含假設吻合 |
| 10 | 同步失敗（離線）處理 | **靜默重試**，不彈錯誤視窗：本機異動一律先落地成功，同步失敗只是「還沒同步過去」，靠 `updated_at`/墓碑機制本身就足以判斷待同步項目，下一次任何 checkpoint 觸發時自然重試，不做額外佇列/退避演算法 |
| 11 | 首次登入的本機/雲端資料合併 | **不特殊處理**，套用跟平常一樣的 checkpoint 同步規則（決策 7/8/閱讀位置既有規則）；「首次同步」只是「雲端那邊剛好大部分是空的」的一般情況，不需要額外的 bootstrap 邏輯 |
| 12 | Base URL 可設定性 | **使用者可自行輸入**，Settings「同步」子頁面提供伺服器網址欄位，預設帶一組官方 URL、可修改——呼應「本 Epic 要交付自架 SOP」的前提，也方便開發/測試時切換不同 PocketBase 實例 |
| 13 | 認證憑證儲存方式 | 新增 `flutter_secure_storage` 套件（Android Keystore／iOS Keychain 加密儲存），**只用來存 PocketBase auth token 這一項敏感憑證**；其餘既有 `SharedPreferences` 用途（版面偏好等非敏感設定）維持不動，不做全面遷移 |
| 14 | 帳號設定「測試連線」 | Settings「同步」子頁面的帳號/伺服器設定表單需要一顆「測試連線」按鈕，讓使用者在儲存設定前就能確認 base URL + 帳密組合是否正確可連通 |

## 新增的資料模型（草案，細節留待 Architecting 階段 `spec.md` 確認）

- `books` 表新增 `content_fingerprint TEXT`（決策 5）。
- `bookmarks`／`highlights`／`notes` 三表各自新增：`sync_id TEXT`（UUID，全域唯一）、`updated_at INTEGER`、`deleted_at INTEGER`（可空，軟刪除墓碑，決策 8）。
- 閱讀位置（目前直接內嵌於 `books` 表的 `epubLocator`/`pdfPageIndex`/`progress` 三欄，無獨立表）新增 `position_updated_at INTEGER`，供 FR-19 衝突比對使用。
- 新增本機「同步帳號設定」儲存：base URL（`SharedPreferences`，非敏感）＋ auth token（`flutter_secure_storage`，決策 13）。
- 預期為一次新的 schema migration（目前最新版本 15 → 16），累加式 `if (oldVersion < 16)`，比照既有慣例。

## 架構影響摘要

| 模組 | 異動類型 | 說明 |
|------|---------|------|
| `pubspec.yaml` | 新增依賴 | PocketBase SDK（或等效 HTTP client）、`flutter_secure_storage`；目前專案零網路/身份驗證相依套件 |
| `sqlite_library_repository.dart` | 擴充 | v15→v16 migration，新增決策 5/8 所列欄位 |
| `SettingsScreen` | 擴充 | 新增「同步」子頁面入口（比照「佈景」子頁面模式） |
| 新建同步子頁面（暫名 `SyncSettingsScreen`） | 新建 | base URL／帳密輸入、測試連線按鈕、登出按鈕 |
| 新建同步引擎模組 | 新建 | checkpoint 觸發邏輯（App 生命週期監聽＋書籍切換事件＋閒置計時器）、批次同步（閱讀位置 + 劃線/備註/書籤）、id 聯集合併邏輯、閱讀位置衝突彈窗 |
| 書籍匯入流程（`book_import_service_impl.dart`） | 擴充 | 匯入時計算並存入 `content_fingerprint`（決策 5） |
| `ReadingPosition`／`Bookmark`／`Highlight`／`Note` 及對應 repository | 擴充 | 新增 `updated_at`／`sync_id`／`deleted_at` 欄位與讀寫邏輯 |

## 已知風險 / 待 Architecting 階段確認的技術細節

- **PocketBase collection schema 設計**（`user_id` 關聯方式、每張本機表對應哪個 PocketBase collection、REST API 呼叫的批次化方式）留待 `spec.md`。
- **書籍內容指紋的實際計算方式**（EPUB OPF identifier 缺漏時的 hash 演算法選擇、PDF/TXT hash 是否需要抽樣而非全檔案雜湊以控制大檔案效能）留待 `spec.md`。
- **5 分鐘閒置計時器的實際數值**是本次 Discovery 的初始建議值，待真機測試/實際使用後可再調整，不視為定案的硬性需求。
- **PocketBase 自架 SOP 文件**的實際內容（伺服器規格建議、collection 建立步驟、備份策略）留待 Architecting／實作階段撰寫，目前只確認「要交付」這件事本身。

## 範圍外 (Out of Scope)

- **FR-02（雲端匯入來源帳號）**——另開新 Epic，見決策 1。
- **PocketBase 伺服器部署**——外部前置作業，只交付 SOP 文件。
- **TXT 定位同步**——留待 `epic-11-txt-engine`。
- **FR-21（社群分享）**——P3，獨立需求。
- **書籍檔案本體雲端儲存**——PRD 明確排除。
- **OAuth 第三方登入**——見決策 4。
- **同步佇列/重試退避演算法**——見決策 10。
