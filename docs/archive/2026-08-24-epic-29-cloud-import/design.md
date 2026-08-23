# Epic 29 — 雲端服務匯入書籍：Discovery

## 背景

2026-08-17 使用者提出「加入透過雲端服務匯入書籍。如：Google Drive、OneDrive、Dropbox」需求，經 `/grill-with-docs`（`/grilling` ＋ `/domain-modeling`）5 輪問答完成 Discovery。

這是 PRD FR-02（P0）的既有缺口：FR-02 原文「提供本機檔案選擇器介面，並支援 Google Drive 與 OneDrive 雲端存取；Google Drive 存取功能須確保在無 Google Play Services (GMS) 環境（如部分 E-Ink 裝置）下，登入、驗證與下載仍可正常運作」——本機檔案選擇器已在 `epic-1-library` 完成，雲端存取半直到本次才啟動 Discovery。此缺口最早於 2026-08-02 `epic-8-sync` Discovery 階段確認範圍時發現並記錄於 `CONTEXT.md`「雲端匯入來源帳號」詞條，當時明確標註「完全不同的帳號體系、不併入 `epic-8-sync`」。

Discovery 前已用背景 subagent 查核兩批事實，直接決定了多個分岔的可行選項：

- **現有匯入介面**：`BookImportService.importFiles(uris, {displayNames, folderName})` / `importFolder(folderUri, {autoGroupByFolderName})`——只接受呼叫端已選好的 URI 字串，picker/選檔邏輯不在 service 內。**〔2026-08-17 審查修正〕** 原先誤判「不需要改動這個介面本身」——經 `review-design.md` Critical #1 覆核程式碼證實這是錯的：`book_import_service_impl.dart:388` 的 `_importSingleFile` 內部**硬編碼** `source: BookSource.local`，且 `importFiles()`/`importFolder()` 簽章完全沒有傳遞 `BookSource`／雲端檔案 ID 的通道，與下方「資料模型」小節要求的「匯入完成後 `Book.source` 真正賦值為 `googleDrive`／`oneDrive`、並保留雲端檔案 ID」直接矛盾。**現有介面必須擴充**（新增參數或新增專屬方法）才能承載這兩項資料，正確的簽章設計留待 Architecting／`spec.md` 定案，這裡只更正「不需要改動」這個錯誤的事實陳述。
- **`BookSource` enum 已存在但從未賦值**（`library_enums.dart`：`local`／`googleDrive`／`oneDrive`，只有 `local` 曾被實際指派）——`Dropbox` 不在列，與 PRD FR-02 只承諾 Google Drive／OneDrive 一致。
- **ADR 0002 已預先定案**：雲端匯入的檔案一律先下載複製到 App 私有目錄，不會像本機 SAF 匯入那樣直接引用即時 URI——這點不需要在本次 Discovery 重新討論。
- **「書籍內容指紋」機制已存在**（`epic-8-sync` 為跨裝置同步比對而建，見 `CONTEXT.md`），匯入時對每本書都會計算並存入 `books.content_fingerprint`，原本從未被用於匯入時的重複偵測——本 Epic 是它的第一次「借用」。
- **AndroidManifest 目前乾淨**，沒有任何既有 OAuth redirect intent-filter／Account Manager 權限可沿用，OAuth 接線是全新工作。

## `/grilling` 決策紀錄

### 範圍與整合方式

- 只做 **Google Drive ＋ OneDrive**，不做 Dropbox——PRD FR-02 只承諾前兩者，Dropbox 是使用者這次臨時追加、未經需求文件驗證，排除於本 Epic 之外，非必要不擴大範圍。
- 兩者皆採**自建 OAuth ＋ 官方 API 整合**（Google Drive API／Microsoft Graph API），**不**借用 Android 系統的 Storage Access Framework（SAF）。理由：FR-02 明確要求 Google Drive 存取「須確保在無 Google Play Services (GMS) 環境下登入、驗證與下載仍可正常運作」——這句話事實上已經預先否決了「依賴使用者已安裝 Google 官方 App＋原生 Google 登入 SDK」這條路（該路徑重度依賴 GMS）。GMS 迴避是這個專案已出現過的既定慣例（`epic-8-sync` 的同步帳號當初就是為了避免 GMS 依賴才選 email+password 而非 OAuth，見 `CONTEXT.md`「elinkBook 同步帳號」）。OneDrive 沒有同等的無 GMS 硬性要求，但為了兩個 provider 架構一致、共用同一套「已連結帳戶」UI 模型，同樣採自建整合而非 SAF。
- 本波只做「瀏覽並勾選單一或多個檔案」匯入，**不含**整批資料夾匯入（遞迴列出雲端資料夾內容、大量檔案分頁/效能是不小的複雜度，留待後續視需求評估）。

### 帳號模型（沿用並補完既有「雲端匯入來源帳號」詞條）

- 每個 provider **限單一帳號**——同一 provider 只能連結一組，要換帳號需先解除連結再重新連結。不做多帳號切換（額外的帳號辨識/切換 UI，目前沒有明確訊號顯示使用者需要同時掛多組同 provider 帳號）。
- **記住登入狀態**（persist refresh token）——雲端匯入是偶爾重複使用的功能，每次都要重新走一次登入/授權流程對操作螢幕通常較慢的 E-Ink 裝置使用者體驗很差。
- Token 過期或被撤銷時，**先靜默嘗試用 refresh token 重新取得存取權**，失敗才跳出「請重新登入」提示——標準 OAuth 應用程式做法，多數情況下使用者完全無感。
- 帳號連結管理入口：**「設定」頁常駐**（可查看已連結哪些帳號、隨時解除授權），比照這個 App 現有「已連結雲端帳戶（同步用）」的既有 UI 慣例；**匯入流程中若尚未連結，也能直接觸發連結**，不強制使用者先跳去設定頁。
- 解除某個雲端帳號連結，**不影響**先前已下載匯入的書籍——書籍檔案本身已在本機，跟帳號連結與否無關；書籍上保留的來源標記（見下方）也不會被清空，純粹是「這本書當初從哪來」的歷史紀錄，即使之後沒有 token 了依然有效。

### 瀏覽與選檔 UI

- 匯入選單新增**兩個獨立項目**：「從 Google Drive 匯入」「從 OneDrive 匯入」——使用者通常清楚自己要從哪個服務匯入，比先跳出「選擇雲端服務」中介畫面更直接，也符合現有「選擇檔案」／「選擇資料夾」並列的既有選單模式。
- 雲端瀏覽器**只做逐層資料夾瀏覽**（跟系統檔案總管一樣點資料夾往下鑽），**不做搜尋**——Google Drive／Graph API 的搜尋語法各自不同，會增加不少開發量；多數使用者雲端硬碟裡的書通常集中在特定資料夾，逐層瀏覽已經夠用。
- 瀏覽清單**依格式過濾**，只顯示支援格式（EPUB/PDF/TXT/AZW3/CBZ/MD）——兩家 API 都支援伺服器端依 MIME type／副檔名篩選，直接把不支援的檔案（照片、Word 文件等）擋在畫面外。
- 瀏覽清單**顯示縮圖**（重用 Google Drive API／Microsoft Graph API 內建的 thumbnail 欄位）——尤其對 PDF/CBZ 這類封面重要的格式，能顯著改善「一堆檔名很像的檔案到底哪個是我要的」這種常見情境，且幾乎沒有額外開發成本。

### 下載與匯入行為

- 多選批次匯入時**循序下載**（一個下完才下一個，清單逐項顯示 等待中/下載中/完成/失敗 狀態），不做平行下載——平行下載對效能較弱的 E-Ink 裝置可能造成記憶體/網路壅塞，循序下載行為容易預期、實作也更簡單。
- 下載失敗時**立即顯示錯誤＋手動重試按鈕**，不做自動重試——自動重試在行動網路不穩定時容易讓使用者搞不清楚「App 是不是卡住了」；明確的失敗狀態＋手動重試，使用者感受更可控。
- 偵測到目前使用行動數據（非 Wi-Fi）且檔案較大時，**跳出「確定要用行動數據下載嗎」的確認**——PRD 其他地方已把 100MB+ PDF 當作明確的效能目標情境，大檔案是這個 App 的常態，行動數據誤下載大檔案的實際傷害（流量費/超額）比多一次確認的干擾更大。
- 匯入時**可選分類**，直接重用既有 `importFiles()` 的 `folderName` 參數（成本很低，不是像資料夾匯入那樣要處理遞迴列出的複雜度）——若不提供，常態性從雲端匯入的使用者書架會很快變得雜亂；未指定則沿用既有「未分類」預設行為。

### 重複匯入偵測

- 借用既有「書籍內容指紋」機制（`books.content_fingerprint`）：使用者選到一個指紋與圖書庫中既有書籍**完全相同**的雲端檔案時，提示「這本書之前匯入過了，仍要建立新的一份嗎？」。
- 刻意**不做**書名/作者模糊比對——已知覆蓋率落差：指紋對「EPUB 且 OPF 有 `<dc:identifier>`」跨來源比對可靠，但對「PDF／TXT／CBZ／沒有 identifier 的 EPUB」是整份檔案位元組雜湊，雲端副本與本機副本只要有任何位元組差異（時間戳記中繼資料、重新壓縮等）就會產生不同指紋，這類跨來源重複本波**抓不到**。接受此落差，符合本專案「不做超出需求的彈性設計」原則——模糊比對的誤判成本（書名作者剛好相同的不同書被誤判重複）不小，且使用者真正在意的情境（同一本書從雲端重複抓好幾次）多半是有 identifier 的 EPUB，剛好落在指紋可靠的那一半。之後若有真實回報再處理不遲。

### 資料模型

- 匯入完成後，`Book.source`（`BookSource` enum）真正賦值為 `googleDrive`／`oneDrive`（此前只是從未指派過的 UI stub），並額外保留一個雲端檔案 ID（供上述重複偵測與帳號解除連結後的歷史紀錄使用，欄位/資料表設計留待 Architecting 階段定案）。

## 依賴事實（供 Architecting 階段參考，非本 Discovery 待決）

- `BookImportService.importFiles()` 接受呼叫端已取得的 URI／本機路徑，雲端瀏覽器只需完成「登入 → 瀏覽 → 選檔 → 下載到本機」，下載完成後即可直接餵給既有 `importFiles()`。**〔2026-08-17 審查修正，同上〕** 但「不需要改動這個既有介面的簽章」是錯的（見上方「現有匯入介面」已更正的說明）——`importFiles()`/`importFolder()` 需擴充才能承載 `BookSource`／雲端檔案 ID，具體簽章留給 Architecting／`spec.md`。
- Google 官方 OAuth 政策不允許透過內嵌 WebView 完成登入（安全政策要求使用系統瀏覽器／Custom Tabs），OneDrive／Microsoft 的登入流程為求一致，同樣走系統瀏覽器導向的 OAuth 流程——這是外部平台政策的技術限制，不是本次需要 grill 的產品決策，留給 Architecting／`spec.md` 定案 redirect URI scheme 等技術細節。
- `AndroidManifest.xml` 目前沒有任何 OAuth redirect intent-filter，需要在 Architecting 階段新增。

## `review-design.md` 審查後續（2026-08-17，待 Architecting／`spec.md` 落實，非本 Discovery 待決）

Critical #1（介面契約矛盾）已如上更正說明文字。以下 Important／Minor 項目經核實技術主張成立（例如 `flutter_secure_storage` 確實已是既有依賴，見 `app/pubspec.yaml:62`），性質上屬於介面/技術規格設計，依 SDD 分工留給 Architecting 階段的 `spec.md` 具體落實，此處僅列出避免遺漏，不在 Discovery 階段展開：

- OAuth 安全架構：PKCE＋`state` 參數、refresh token 存入 `flutter_secure_storage`（不可存純文字）、Google Drive scope 選擇（`drive.readonly` 需 Google 應用程式驗證流程 vs. `drive.file` 只能存取本 App 建立/開啟過的檔案，兩者的取捨會影響「瀏覽任意雲端資料夾」這個已定案 UX 能否如實達成，**Architecting 階段須特別檢視此點是否需要回頭調整 UX 假設**）。
- 重複匯入偵測的時序：指紋需下載後才能計算，選檔當下無法立即比對；下載中/取消時的暫存檔清理機制。
- 雲端資料夾瀏覽的分頁（Google Drive `pageSize`／Microsoft Graph `@odata.nextLink`）。
- 資料庫 schema 遷移（新增雲端檔案 ID 欄位，`books` 表現行 version 21）。
- 行動數據流量警示的具體檔案大小閾值。
- 雲端縮圖的授權標頭／時效性 URL 處理與本地快取。
- 下載取消時的孤兒暫存檔清理。

## 範圍界定

- **本 Epic 涵蓋**：Google Drive／OneDrive 帳號連結（設定頁管理＋匯入流程觸發）、雲端檔案瀏覽（逐層/過濾/縮圖）、單/多檔選取下載、既有匯入管線接線、重複匯入偵測（指紋完全比對）、來源標記持久化。
- **本 Epic 不涵蓋**（留待後續視需求評估，不在本波規劃）：Dropbox；整批資料夾匯入；雲端檔案搜尋；多帳號（同 provider 多組）；PDF/TXT/CBZ 跨來源模糊比對重複偵測；「重新整理／同步最新版本」（利用已保留的雲端檔案 ID 重新抓取雲端最新版本覆蓋本機檔案）。

## `CONTEXT.md` 異動

- 更新「雲端匯入來源帳號」詞條：補上單一帳號／記住登入狀態／管理入口等本次定案細節，移除「目前沒有任何 Epic 追蹤」的過期敘述。
- 更新「書籍內容指紋」詞條：補上第二用途（雲端匯入重複偵測），並記錄已知的跨來源覆蓋率落差。
- 新增「書籍來源（Book Source）」詞條：說明 `BookSource` enum 從未賦值的 UI stub 狀態，到本 Epic 落地後才真正賦值的沿革。
