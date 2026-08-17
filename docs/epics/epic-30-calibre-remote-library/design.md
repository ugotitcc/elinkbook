# Epic 30 — Calibre 遠端書架整合：Discovery

## 背景

2026-08-17 使用者提出「加入將 Calibre 作為遠端書架」需求，並提供研究報告 `docs/research/calibre_remote_library_integration_research.md` 作為架構參考，經 `/grill-with-docs`（`/grilling` ＋ `/domain-modeling`）5 輪問答完成 Discovery。

研究報告建議的 Epic 編號 `epic-17-remote-calibre` 已被既有 `epic-17-epub-render-migration` 占用，本 Epic 改編號為 `epic-30-calibre-remote-library`。

Discovery 前已核實下列事實，直接影響多個分岔的可行選項：

- `BookSource`（`app/lib/library/models/library_enums.dart:8`）目前為 `{local, googleDrive, oneDrive}`，`epic-29-cloud-import` 已定案延伸此 enum 供 Google Drive／OneDrive 使用（尚未實作）。
- `epic-29-cloud-import` 已完整走完 Discovery→Architecting→Scrum Master（`issues.md` 7 個工單），其帳號模型為「單一帳號＋OAuth＋`cloud_file_id` 單欄」——本次 Discovery 一開始即確認此模式不適合 Calibre（多站點自架伺服器）情境，兩者刻意分屬不同 Epic，不強行合併。
- `app/pubspec.yaml` 已有 `flutter_secure_storage: ^10.3.1`（正式 `dependencies`，帳密加密儲存可直接用）。**〔`review-design.md` Important #1 核實修正〕** 原文另稱 `xml: ^6.6.1`／`http: ^1.6.0`「本 Epic 不需要新增依賴」是錯的——經核對 `pubspec.yaml:90-116`，這兩項目前只宣告在 `dev_dependencies`（分別供測試驗證 XML 格式與 `MockClient` 模擬網路請求使用），OPDS Atom XML 解析／HTTP 通訊要進到正式 `lib/` 程式碼，需要在 Architecting 階段把兩者提升為正式 `dependencies`，並非零新增依賴成本。
- `CONTEXT.md`「雲端匯入來源帳號」詞條明確將範圍限定於「Google Drive／OneDrive 等**雲端硬碟**」——Calibre／OPDS 是自架遠端書庫伺服器，不屬於這個詞條範圍，需要獨立的新詞彙（見下方「`CONTEXT.md` 異動」）。

## `/grilling` 決策紀錄

### Epic 定位與協議範圍

- 獨立成新 Epic（`epic-30-calibre-remote-library`），不併入 `epic-29-cloud-import`。理由：Calibre/OPDS 是自架伺服器＋Basic Auth／匿名＋目錄下鑽瀏覽＋多站點，`epic-29` 是雲端硬碟＋OAuth＋單帳號＋資料夾樹瀏覽，帳號模型、通訊協議、UI 導覽邏輯幾乎沒有共用面。
- v1 僅實作標準 **OPDS 1.2/2.0** 協議（相容 Calibre Content Server／Calibre-Web／Kavita／任何標準 OPDS 站台）。研究報告建議的「Calibre 專屬 REST API（`/ajax/search`、`/ajax/categories`）加強」留待後續 Issue，不卡 v1。

### 伺服器與帳號模型

- **多站點 Profile**（可同時管理家用 NAS、公網 Calibre-Web、Project Gutenberg 等多個站點）——這是 Calibre/OPDS 用例與 `epic-29` 單帳號模式的核心差異，也是研究報告的核心結論。
- 認證方式為 **HTTP Basic Auth（帳密）或匿名**（帳密留空即代表匿名連線）；不採用 OAuth（OPDS/Calibre 生態沒有這個概念）。
- 支援**自簽憑證**（允許不安全連線開關）與**純 HTTP（非 TLS）**連線——家用 NAS 常見情境，若不支援會排除掉主要使用場景。
- 新增/編輯站點提供**「測試連線」按鈕**，儲存前驗證 URL／帳密／憑證是否正確——自架伺服器情境的常見出錯來源（URL 打錯、憑證問題、帳密錯誤）遠比雲端硬碟 OAuth 常見，先驗證能大幅降低使用者除錯難度。
- 站點 Profile 存於新增 SQLite 資料表 `remote_servers`（id/name/baseUrl/type/username/createdAt/lastAccessedAt），密碼獨立存 `flutter_secure_storage`（key 含 profile id，不落地明文於 SQLite）。理由：多筆列表資料適合關聯式表，且書籍列的 `remote_server_id` 需要反查站點顯示名稱（例如書架上顯示「來自：家用 NAS」），用資料表 JOIN 遠比反序列化一包 JSON 划算。

### 資料模型

- 延伸 `BookSource` enum 新增一個值（暫定 `calibreOpds`，最終命名留待 Architecting 定案），維持「`BookSource` = 這本書的來源類別」既有語意一致。
- `books` 表新增 `remote_server_id`／`remote_book_id` 兩欄位（不重用 `epic-29` 的 `cloud_file_id`，因其命名語意綁定 OAuth 雲端硬碟；且 Calibre 多站點需要額外的站點消歧義欄位，`cloud_file_id` 單欄不足以承載）。
- `remote_book_id` 代表 **OPDS 條目（書本身）層級**，不分格式——同一本書不論後來選哪個格式下載，都是同一個 `remote_book_id`。這個決定同時服務「選檔前置重複偵測」（見下方）與「多格式選擇」UI（格式差異交由選擇彈窗處理，不在 ID 層級區分）。

### 重複匯入偵測

- 比照 `epic-29` 的雙層檢查機制，維持專案內部一致性：
  1. **選檔前置檢查**：`(remote_server_id, remote_book_id)` 命中既有書籍即提示「這本書之前匯入過了，仍要建立新的一份嗎？」，不需下載就能判斷。
  2. **下載後指紋比對**：沿用「書籍內容指紋」（`books.content_fingerprint`）機制的**第三個用途**——前置檢查沒命中時，下載完成後計算指紋比對，命中則同樣提示。
- 同一本書若先前用不同格式下載過（例如先前 PDF、這次想要 EPUB），因 `remote_book_id` 為書本層級，仍會被前置檢查命中、視為重複並提示——不為「格式不同」開特例，維持規則單純，與 `epic-29` 既定 UX（精確比對命中即提示，使用者可選擇仍要建立新副本）一致。

### 下載與快取生命週期

- 下載完成後透過**對稱擴充的 `BookImportService.importFiles()`** 走既有入庫管線（新增可選參數，例如 `remoteServerId`／`remoteBookIds` map，具體簽章留待 Architecting），維持專案「不新增平行匯入路徑」的既定慣例（`epic-29`／`review-design.md` Critical #1 已確立的原則），既有呼叫端零回歸。
- **不做斷點續傳**，僅失敗後手動重試（從頭下載）——比照 `epic-29` 的簡化決定，維持專案複雜度基準一致。
- **支援「移除本機快取、保留雲端紀錄」**——這是本 Epic 相對 `epic-29`（一次性匯入、來源標記純歷史）的核心差異化能力，呼應「遠端書架」的產品定位（可重複造訪瀏覽，不是一次性匯入）。移除快取後：
  - Book 資料列**留在圖書庫**，以雲朵角標呈現「待下載」狀態，開啟時需先重新下載；劃線/書籤/閱讀進度**原樣保留**在本機 DB（重新下載後透過既有 `book_id`／`content_fingerprint` 機制接續使用，不遺失）。**〔`review-design.md` Important #2 核實〕** `Book.filePath`／`books.filePath` 目前是 `required String`／`NOT NULL`（`book.dart:14,92`），「待下載」狀態不能靠把 `filePath` 清空或填入無效路徑來實作，否則會破壞既有 non-null 契約，以及書架列表格式圖示判定、封面載入等依賴 `filePath` 的既有邏輯。具體技術手段（例如新增 `isDownloaded`／`downloadStatus` 旗標並讓 `filePath` 保留最後一次下載路徑、或改為可空型別）留待 Architecting／`spec.md` 定案，這裡更正的是產品層級的意圖敘述，不預先鎖定實作方式。
  - 點開「待下載」狀態的書時，**跳出確認對話框**才觸發重新下載（沿用/仿照 `epic-29` Issue 6 的行動數據下載警示邏輯），避免誤觸浪費流量。
- **站點刪除的邊界情況**：使用者刪除某個 `remote_servers` Profile 時，若圖書庫中存在該站點「僅雲端紀錄、無本機檔案」的書籍，**先示警／協助清理**再刪除，不允許直接刪除站點造成書籍列永久失效——直接刪除會讓使用者卡在「想重新下載卻永遠打不開」的困惑狀態，示警更符合專案「零意外」的既有產品原則。**〔`review-design.md` Important #4 核實，補上原文遺漏的另一半情境〕** 對於該站點「已下載完成、本機有檔案」的書籍，刪除站點**不影響**其繼續閱讀——書籍保留在圖書庫，`remote_server_id` 清為 `NULL`，退化為一般本機書籍（不再關聯已刪除站點，僅喪失「重新下載」與「站點名稱反查顯示」兩項能力，劃線/書籤/閱讀進度不受影響）。這與「僅雲端紀錄、無本機檔案」書籍的「先示警／協助清理」是不同情境——差別在於前者刪除站點後書籍仍可正常開啟閱讀（不需要雲端就能用），後者刪除站點後會直接喪失開啟能力（需要雲端才能取得檔案），因此只有後者需要示警防護。

### 瀏覽與匯入 UI

- v1 支援 **OPDS 目錄下鑽（依 Feed 提供的分類 navigation links 逐層點擊）＋分頁**（跟隨 `nextUrl`/`prevUrl`）——這是 OPDS 協議本身自帶的能力，非額外工程。**即時搜尋（OpenSearch）留待後續加強 Issue**，因為各 OPDS 伺服器搜尋語意不一致，風險較高，不擋 v1。
- 同一書目若 OPDS Feed 提供多個下載格式（Acquisition Links，例如 EPUB+PDF），**彈窗讓使用者選一個格式下載**（`FormatSelectionDialog`，沿用研究報告提案）；格式清單沿用 elinkBook 既有 6 種支援格式（EPUB/PDF/AZW3/CBZ/TXT/MD），不支援格式（如 MOBI）於選單中置灰，整本書若無任何支援格式則列表中標示不可下載。
- 「待下載」狀態的書**與一般書籍混合顯示**在同一書架網格/列表（用雲朵角標區分狀態），不獨立分頁——可直接相容現有 `groupName`／排序機制，維持使用者「一個地方看所有書」的既有心智模型。
- 遠端書庫瀏覽畫面需要**獨立的常駐入口**（不只塞進「匯入」選單的一個項目）。理由：這個功能的產品定位是「遠端書架」——可重複造訪瀏覽、管理多站點、重新下載，跟「匯入」選單既有的「選檔案、一次性動作」心智模型不同，需要一個比選單項目更持久的操作入口（例如書架頁面新增「遠端書庫」分頁或明顯按鈕，具體 UI 落地位置留待 Architecting）。

### E-Ink 與後續優化

- 研究報告 Section 6 提出的 E-Ink 專屬優化（離散分頁導航、封面縮圖雙層快取、搜尋防抖動）**不列入 v1**，維持研究報告本身建議的規劃，獨立成最後一個 Issue——核心瀏覽/下載/入庫先在一般手機上驗證正確性，E-Ink 細節優化再疊加，不擋 v1 上線。

## 依賴事實（供 Architecting 階段參考，非本 Discovery 待決）

- `BookImportService.importFiles()` 的具體參數簽章擴充方式，比照 `epic-29` 已定案的擴充模式（可選參數＋預設值，零回歸），留待 `spec.md` 定案。
- `remote_servers` 資料表的完整 schema（欄位型別、索引、與 `books.remote_server_id` 的外鍵/查詢方式）留待 `spec.md` 定案。
- OPDS Feed 解析的容錯策略（缺失 Title/Author/縮圖時的預設值、格式不規範時的防禦性解析）為技術細節，留待 `spec.md`。
- DRM 保護的 OPDS 條目（部分公開書庫可能提供需要 Adobe ACS4 等 DRM 的借閱連結）——PRD 既有「不支援解除 DRM」的產品邊界已涵蓋此情境，實作時比照「不支援格式」的處理方式過濾/置灰即可，非本次需要重新 grill 的新決策。

## `review-design.md` 審查後續（2026-08-17，待 Architecting／`spec.md` 落實，非本 Discovery 待決）

Important #1（`xml`/`http` 依賴分類）已如上更正「依賴事實」小節；Important #2（`filePath` 契約衝突）與 Important #4（站點刪除對已下載書籍的處置）已如上補上「下載與快取生命週期」小節的決策文字。以下項目經核實，性質上屬於實作/部署細節，依 SDD 分工留給 Architecting 階段的 `spec.md` 具體落實，此處僅列出避免遺漏：

- **自簽憑證信任（Important #3，核實後部分修正）**：審查提到「Android 9+ 預設禁止 Cleartext HTTP，需配置 `network_security_config.xml` 開放區網」——經核對 `AndroidManifest.xml:7`，本專案 `<application>` 已全域設定 `android:usesCleartextTraffic="true"`（既有設定，非本 Epic 新增），純 HTTP 連線目前已可用，**不需要**再額外針對區網網段設定 `network_security_config.xml`。但審查同時提出的**自簽憑證信任**問題仍然成立、需要處理：TLS 憑證驗證（例如 `badCertificateCallback` 之類機制）必須**僅**對使用者在該站點明確勾選「允許不安全連線」時放行，不可全域關閉憑證驗證以免波及其他正常連線的安全性，具體實作留待 `spec.md`。
- OPDS Feed 分頁循環防護（Minor #1）：`OpdsFeedParser` 需追蹤已造訪 URL，避免部分伺服器輸出指回自身/上一頁的 `next` 連結造成無限遞迴請求。
- 遠端封面縮圖 Basic Auth Header 傳遞（Minor #2）：站點啟用 Basic Auth 時，OPDS Entry 封面縮圖 URL 通常也需要帶 `Authorization` header 才能載入，UI 縮圖載入器需支援自訂 headers。
- `BookImportService` 擴充避免二次檔案 I/O（Minor #3）：從 OPDS 下載的檔案已在 App 私有下載目錄，擴充註冊邏輯時應避免對已就緒的本機檔案做不必要的重複複製。

## 範圍界定

- **本 Epic 涵蓋**：多站點 Calibre／OPDS 站點管理（新增/編輯/刪除/測試連線）、標準 OPDS 目錄瀏覽（下鑽＋分頁）、單檔下載與多格式選擇、既有匯入管線接線、雙層重複匯入偵測（比照 `epic-29` 機制）、本機快取移除與重新下載（保留雲端紀錄）、遠端書庫獨立常駐入口。
- **本 Epic 不涵蓋**（留待後續視需求評估，不在本波規劃）：Calibre 專屬 REST API 進階搜尋/分類；OPDS 全文/即時搜尋（OpenSearch）；斷點續傳；E-Ink 專屬優化（離散分頁導航、封面縮圖雙層快取，獨立成最後一個 Issue，仍在本 Epic 範圍內但排在最後）；研究報告 Backlog 章節的 Obsidian Fast Note Sync（明確排除，獨立於未來專屬 Epic）。

## `CONTEXT.md` 異動

- 新增「遠端書庫（Remote Library）」詞條：定義本 Epic 的產品概念，與「雲端匯入來源帳號」（雲端硬碟、OAuth、單帳號、一次性匯入）明確區分。
- 新增「遠端書庫站點（Remote Library Site）」詞條：對應 `remote_servers` 資料表的一筆站點 Profile。
- 更新「書籍來源（Book Source）」詞條：記錄 `BookSource` enum 即將新增第 4 個值（本 Epic Discovery 階段決議，暫定 `calibreOpds`，最終命名待 Architecting 定案）。
- 更新「書籍內容指紋（Book Content Fingerprint）」詞條：補上第三個用途（Calibre 遠端書架下載後重複偵測，與 `epic-29` 的雲端匯入重複偵測機制相同模式）。
