# ADR 0037：依賴按使用者分組，以單一物件經建構子傳遞

## 狀態

已採納（2026-10-05）。取代 ADR 0007 中「依賴以建構子參數逐欄往下傳」的做法，以及 epic-26 Issue 7 的 bundle 切法。ADR 0007 的其餘決定（`bookId` 契約、不用 service locator）不變。

## 背景

依賴由 `main.dart` 建構後，經 `ElinkBookApp` → bundle → 各畫面逐欄展開再重組：`ElinkBookApp` 約 39 個欄位、`ReaderScreen` 28 個參數（其中 17 個是 repository／service，全部 nullable）、`SettingsScaffold` 22 個參數。`reader_screen.dart` 在「閱讀器→單書搜尋」流程中還要用 `widget.*` 手動逐欄重建 `LibraryReaderFeatureRepositories`。

這造成同一類缺陷反覆出現：新增欄位時，某一層漏轉送，編譯器抓不到（nullable 讓漏轉送變成執行期靜默失效）。epic-26 Issue 7 曾把 `LibraryScreen` 的參數收斂成 5 個 bundle，但 bundle 只是欄位集合，沒有改變「逐層展開重組」，之後仍漏轉發 `computeFingerprint`、`ttsDegradedNotice` 等欄位。

測試端也受 nullable 影響：測試只傳需要的參數，其餘靠省略，讓「缺依賴」在正式環境與測試環境行為不同。

## 決策

1. 依賴按「誰在用」分成四組，容器 `AppDependencies` 持有其中三組靜態依賴（`readerFeatures`／`sync`／`sources`），只在 `main.dart` 與根部使用；`AppearanceDependencies` 因含可變狀態（目前主題、E-Ink、語言覆寫），由 `ElinkBookApp` 的 State 每次 `build()` 組成快照往下傳，不進容器：
   - `ReaderFeatureDependencies`（閱讀器功能）：含 `libraryRepository`、`importService`、`prefsManager`、`fullTextSearchSettingsRepository`（「啟用全文檢索」設定；Issue 12 補列，供書架、全庫搜尋與設定頁使用），以及 `ReaderScreen` 的 `ReadingSession` 需要的 `syncCheckpointTrigger`（閱讀器只需要「請求一次 Checkpoint」，不需要帳號、`SyncClient` 或手動同步）。
   - `SyncDependencies`：同步帳號、`SyncClient`、`onManualSync`、`loadLastSyncedAt`，以及 `syncCheckpointTrigger`。只有 `SettingsScaffold` 與其上層（`AdaptiveShellScaffold`、`ElinkBookApp`）收這一組；`LibraryScreen`／`LibrarySearchScreen` 只收 `ReaderFeatureDependencies`。
   - `SourceDependencies`（雲端／遠端來源）：雲端帳號與 OAuth／storage client（Google Drive／OneDrive 各一）、`remoteServerRepository`、OPDS client 工廠（`createOpdsClient`）、`thumbnailCache`、`computeFingerprint`、行動網路判斷（`isMobileDataConnection`）、WiFi 傳書的網路偵測（`checkNetworkAvailability`，原 `WifiTransferDependencies` 欄位）與 `downloadQueueController`，共 12 欄位。書庫與匯入服務不重複收斂——取自閱讀器組（`readerFeatures.libraryRepository`／`bookImportService`）。
   - `AppearanceDependencies`：主題、E-Ink 模式，以及介面語言（`currentLocaleOverride`、`onLocaleChanged`）。
   同一個依賴可以出現在不只一組（例如 `syncCheckpointTrigger`），但必須由 `AppDependencies` 建構一次、把同一個實例放進各組，不得各組自行建構。
2. 畫面以建構子接收所需的那一組（單一物件），不再逐欄接收。開書路徑（`LibraryScreen`、搜尋畫面、`BookSearchScreen`）整組轉傳同一個實例。
3. 組內的 repository、service、tracker 與函式型依賴（例如 `onManualSync`、`computeFingerprint`）一律 non-null required。真正可能缺席的能力以明確的「不可用」adapter 或旗標表示，不用 null；目前這些能力的開關是靠 null 檢查（`ttsProvider == null`），改用哪一種表示由各 Issue 的 plan 定案。全文檢索以 `isFullTextSearchAvailable` 旗標表示；WiFi 傳書於 Issue 13 定案為不留開關、恆提供（正式環境本來就恆提供，沒有真實的「不可用」情境）；**TTS 不新增不可用 adapter**——正式環境恆提供 `SystemTtsProvider`，音訊服務不可用以 `TtsAudioHandlerHolder.unavailable()`／`.degraded()` 表示（Issue 11 前提 2，YAGNI）。
   例外：依書本才能建構的物件（`readingStatsTracker`）與純為 widget test 注入的 callback（`pickSingleBookFile`）不屬於應用層依賴，留在 `ReaderScreen` 建構子上作為測試注入點。
4. 測試使用 `test/support/` 的工廠建立預設全是 fake 的依賴組，只覆寫情境需要的欄位。正式與測試是兩個 adapter，seam 成立。
5. 不引入 DI 套件，也不使用 `InheritedWidget`；依賴仍顯式出現在建構子簽名上。
6. 遷移逐畫面一刀切，同一個畫面的建構子不保留新舊參數並存。遷移期間曾以 `reader_screen_route.dart` 的單一轉換函式 `readerFeatureDependenciesFromLegacy` 讓尚未遷移的外層畫面暫時組裝依賴組；該函式與舊 bundle（`LibraryReaderFeatureRepositories`、`LibrarySyncDependencies`）已於 Issue 12 全部移除，不再有新舊並存。epic-26 Issue 7 的其餘 4 個舊 bundle（`LibraryCloudAccountDependencies`、`LibraryRemoteLibraryDependencies`、`LibraryThemeDependencies`、`LibraryLocaleDependencies`）與 epic-44 的 `WifiTransferDependencies` 已於 Issue 13 全部移除。

## 後果

- 新增依賴只改「建立處」與「使用處」，中間的畫面不用動；漏轉送變成編譯錯誤。
- 畫面拿到的是整組而非單一依賴，單一畫面的 interface 比逐欄寬鬆；以按使用者分組控制寬度，不提供全部依賴的整包。
- 測試改動量大：`ReaderScreen(` 在 5 個檔案約 267 處、`LibraryScreen(` 約 135 處、`SettingsScaffold(` 約 53 處，靠共用工廠降低每處成本。
- 未選的做法：`InheritedWidget` 查找會讓缺依賴從編譯期錯誤變成執行期錯誤；保留 nullable 省略會延續目前的缺陷類型；新舊並存會延長漏轉送的風險期。
- 守衛測試縮小為身分比對：驗證 `main.dart` 組裝的同一個實例傳到每個開書路徑；欄位是否遺漏改由型別系統保證。
