# `epic-54-architecture-optimization` 架構優化

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-54-architecture-optimization/`
**關聯 PRD 章節：** 無（純內部架構重構，不改變使用者可見功能，除 Issue 1 的一處刻意行為調整）
**關聯 ADR：** 0007、0035

## 背景

2026-09-30 `/improve-codebase-architecture` 檢視 epic-45／48／49／50／52／15 產出 7 個深化候選（報告 HTML 存於暫存目錄，不進版控）。候選 1 已由 `epic-53-sync-checkpoint-result` 完成並合併。使用者要求後續架構優化不要每一項各開一個 Epic，**集中在本 Epic，每個候選當作一張 Issue**（見 `issues.md`）。

## Issue 1 設計決策（`/grill-with-docs` 定案）

| 決策 | 結論 |
|---|---|
| module 範圍 | `AvailableFonts` 只做純推導，不做 I/O，不含 `@font-face` CSS |
| 不認得的名稱、沒有 store | 統一為 `effectiveFamily() == null`（行為調整：原本渲染端照原值傳，與下拉選單不一致） |
| `ReaderScreen` 狀態 | 4 個欄位換成單一 `AvailableFonts?`，`null` 代表載入中 |
| 命名 | 類別 `AvailableFonts`，檔案 `app/lib/reader/available_fonts.dart`，`CONTEXT.md` 詞條「可用字型」 |
| 既有 interface | `ReaderSettingsSheet` 改吃 `AvailableFonts`；`FoliateReaderView`／`buildFontFaceCss` 不改 |
| 測試 | 規則類搬到純測試；接線類留在 widget 層 |
| 載入失敗 | 任一邊失敗該邊視為空集合，仍組出 `AvailableFonts` |

## Issue 5 設計決策（`/grill-with-docs` 定案）

| 決策 | 結論 |
|---|---|
| 命名 | 類別 `OpenBookFlow`，檔案 `app/lib/reader/open_book_flow.dart`，`CONTEXT.md` 詞條「開書流程」 |
| 範圍 | 控制器：持有狀態並編排探測與 relink；`l10n`、SnackBar、選檔器、引擎分派（`_resolveEpubEngineDispatch` 重跑）留在 `ReaderScreen` |
| 狀態 | 密封類別 `Loading`／`Probing`／`Rendered`／`Failed(message, probeResult)`／`Relinking`；`Relinking` 期間的視圖錯誤與逾時一律忽略 |
| 通知方式 | 繼承 `ChangeNotifier`，Widget 加 listener 並 `setState`；`dispose()` 取消計時器、捨棄之後才回來的探測結果 |
| 逾時 | module 持有 30 秒計時器，計時來源注入；成功、失敗取消，重開重啟 |
| 注入的依賴 | 探測函式、relink 函式、計時來源；不直接 import `foliate_native_bridge`，與 Issue 4 互不依賴 |
| `relink(picked)` 回傳 | `reopened(newPath)`／`failed(reason)`／`cancelled`；例外一律轉 `failed` |
| 行為調整（唯一一處） | `content://` 書籍開書逾時也做存取探測，與「視圖回報錯誤」路徑一致 |
| 範圍排除 | `font_management_screen` 的探測與重新連結屬 Issue 3；`_pickAndRelink` 在 `importService == null` 回傳 `null` 的到不了路徑不處理 |
| 測試 | 狀態轉移與競態 guard 搬到純測試 `open_book_flow_test.dart`（計時用替身）；`reader_screen_test` 只留接線類，重疊舊測試遷移後刪除並於記錄列出對應；補「relink 後再失敗會重新探測」 |

## Issue 3 設計決策（`/grill-with-docs` 定案）

| 決策 | 結論 |
|---|---|
| 範圍 | 字型重新連結搬出 Widget、與書籍 `relinkBook` 對齊、授權呼叫集中；批次上傳只把授權那段與家族名稱解析換成共用呼叫，其餘不動 |
| 字型重新連結 module | `CustomFontRelinker`（`app/lib/reader/custom_font_relinker.dart`），`relink(font, picked) → FontRelinkResult`，密封類別 `FontRelinkSuccess`／`FontRelinkFamilyMismatch`／`FontRelinkFailed`；內部做家族名稱解析、比對、授權（盡力而為）、`updateUri`。選檔器、SnackBar、`_relinkingIds` 按鈕停用、探測標示更新與重新載入留在 `FontManagementScreen` |
| 授權集中 | `app/lib/storage/storage_permission.dart`：`Future<bool> persistReadAccess(String uri)`，`PlatformException` 轉成 `false`，內部用既有 `kBookMetadataChannel`。只集中「呼叫與例外轉換」，四處失敗處置仍由各呼叫端決定（書籍複製、資料夾中止、字型忽略×2） |
| 家族名稱規則 | 抽出 `resolveFontFamilyName(bytes, fileName)` 放進 `font_name_parser.dart`，上傳與重新連結共用；`_stripExtension` 因 `displayName` 仍需要而保留 |
| 行為調整 ①（字型） | `FontRelinkFailed` 也顯示 SnackBar，重用 `readerStorageRelinkFailed`，不改鍵名、不動 ARB |
| 行為調整 ②（資料夾匯入） | `ImportResult` 新增 `failure`（`folderAccessDenied`／`folderListingFailed`），涵蓋授權失敗、列舉失敗、列舉為 null 三條路徑；`showImportResultSnackBar` 在 `failure` 不為 null 時只顯示一則共用訊息（新增 1 個 ARB 鍵，同步四份 ARB） |
| 其他假設 | `FontRelinkFamilyMismatch` 時不呼叫授權、不改記錄（維持現狀） |
| 不納入 | 資料夾裡合法地沒有可匯入的書（不是失敗）；`pickAndImportFolder`／`pickAndImportFiles` 的「選擇器例外一律靜默」；批次上傳時資料庫寫入失敗的回饋 |
| 詞條與 ADR | `CONTEXT.md` 新增「持久化授權」；不寫 ADR（差異已由 ADR 0021、0029 說明） |
| 與 Issue 4 | 新目錄 `app/lib/storage/`，Issue 4 之後把探測搬進同一目錄（`storage_access_probe.dart`），兩者互不依賴 |
| 測試 | 純測試：`CustomFontRelinker`（家族不符時不呼叫授權也不改記錄、授權失敗仍繼續、`updateUri` 拋例外回傳 failed、呼叫順序）、`resolveFontFamilyName`、`persistReadAccess`、`importFolder` 三條失敗路徑；`font_management_screen_test` 只留接線類，規則類遷出後刪除並於記錄列出對應；新增「字型重新連結失敗顯示 SnackBar」「資料夾匯入失敗顯示 SnackBar」 |

## Issue 4 設計決策（`/grill-with-docs` 定案）

| 決策 | 結論 |
|---|---|
| 範圍 | 只搬 Dart 端：`StorageAccessProbeResult`、`ProbeStorageAccess`、`kStorageAccessProbeTimeout`、頂層變數 `probeStorageAccess`、`probeStorageAccessViaChannel` 整組搬到 `app/lib/storage/storage_access_probe.dart`，**名稱全部不變**；原生 `probeUriAccess`（`ReaderResourceChannel.kt`）與 channel 名稱 `elinkbook/reader_resources_cache` 不動 |
| 相容與測試 | 乾淨搬家，橋接檔不留 re-export；8 個檔案的 import 一次改完（`reader_screen`、`font_management_screen`、`open_book_flow` 與 4 個測試檔）；`foliate_native_bridge_test` 的探測群組整組搬到 `test/storage/storage_access_probe_test.dart`；畫面測試與 `open_book_flow_test` 只改 import |
| channel 宣告 | 新檔自己宣告私有 `MethodChannel('elinkbook/reader_resources_cache')`（`MethodChannel` 只是依名稱指向同一條原生通道的代理，橋接檔內 `_volumeKeyChannel` 同樣做法）；橋接檔的 `cacheBookForServing`／`readContentUriAll` 維持用它自己那一份；測試以 channel 名稱註冊 mock，寫法不變 |
| M-4（Issue 3 審查遺留） | 不處理：`storage_permission.dart` 繼續 import `library_repository.dart` 取得 `kBookMetadataChannel`；那只是 channel 名稱常數，搬它要動 14 個無關檔案（lib 8＋test 6） |
| 診斷日誌 | 探測函式內繼續寫 `ReaderConsoleLog`，新檔 import `reader/reader_console_log.dart`（無依賴的純工具類別，不屬於 Foliate 引擎） |
| 解讀規則差異 | 不統一、不抽取：書籍只在 `permissionRevoked`／`fileNotFound` 顯示重新選取；字型在 `!= readable`（含 `unknownError`）就顯示標示與重新連結。兩者情境不同（書籍的 `unknownError` 可能是檔案損毀，重新連結救不了；字型沒有其他處置途徑）。之後若要統一另外處理 |
| 詞條與 ADR | `CONTEXT.md` 新增「存取探測」；不寫 ADR（只是搬家，沒有新取捨） |
| 行為變動 | 無，純搬家 |

## Issue 2 設計決策（`/grill-with-docs` 定案）

| 決策 | 結論 |
|---|---|
| 範圍 | 確認同步端與雲端匯入端的落差後實際修正：①離線被當成登入失效 ②API 401 被當成一般錯誤 ③下載佇列吞掉登入失效。同步端（epic-53 已對齊）不動 |
| 形狀 | 兩邊各自保留：同步端用回傳值（`SyncCheckpointResult.sessionExpired`），雲端端用例外（`CloudAuthRequiredException`，因 `listFolder`／`downloadFile` 本來就回傳資料）；`CloudStorageClient` 介面不改 |
| 詞條 | 不統一。「登入過期」維持專指同步帳號；新增「雲端授權失效」，兩詞條互相註明差異（同步端會清 token 留 email，雲端端不改任何儲存狀態） |
| 分類規則 | 新增 `cloud_import/cloud_auth_classifier.dart`，兩個 OAuth client 與兩個 storage client 共用，**不**合併兩個 OAuth client。換發 token 端點回 400／401 → 授權失效；網路例外、5xx、429 → 暫時性。Drive／Graph API 回 401 → 授權失效，其他非 200 → 一般例外 |
| `ensureValidAccessToken` | 簽章不變（`Future<String?>`）。`null` 專指需重新連結（未連結或被撤銷）；暫時性情況改為拋出一般例外，呼叫端本來就歸為網路錯誤 |
| 下載佇列 | `QueuedDownloadJob` 新增 `bool isAuthFailure(Object error)`（預設 `false`），`CloudDownloadJob` 覆寫為 `error is CloudAuthRequiredException`；`DownloadQueueItem` 新增 `needsReauth`，狀態仍為 `failed`。控制器維持來源無關，OPDS 不受影響；重試成功時重設旗標 |
| 使用者介面 | 面板對 `needsReauth` 項目顯示「需重新連結帳號」取代「失敗」（新增 1 個 ARB 鍵，四份同步），保留重試鈕。瀏覽畫面維持文字、不加按鈕；兩處都不加「前往重新連結」按鈕（需牽動 `CloudAccountSettingsScreen` 的依賴建構，另立後續 Issue） |
| 行為調整 | ①離線瀏覽雲端不再顯示「請重新連結」，改顯示網路錯誤 ②API 401 顯示重新連結而非網路錯誤 ③下載佇列失敗項目標示需重新連結 |
| 測試 | 純測試：分類規則；兩個 OAuth client 各補斷網拋一般例外；兩個 storage client 各補 API 401；`download_queue_controller_test` 補 `needsReauth` 設定與重設；`cloud_download_job` 的 `isAuthFailure`。widget：面板新文字、瀏覽畫面離線顯示網路錯誤而非 reauth（翻轉現有行為）。被取代的舊測試刪除並於記錄列出對應 |
| ADR | 不寫（沒有難以回頭的取捨） |

## Issue 6 設計決策（`/grill-with-docs` 定案）

| 決策 | 結論 |
|---|---|
| 動機 | 現況沒有漂移（四份各 641 鍵，鍵集合與 placeholder 全數一致），這張是預防：`l10n.yaml` 沒設 `untranslated-messages-file`，非 template 的 ARB 漏鍵不會編譯失敗，使用者會靜默看到 zh_TW 的字；既有 `check_l10n_hardcoded_strings.js` 只管 Widget 內硬編碼中文，不看 ARB 本身 |
| 形式 | Dart 測試 `app/test/l10n/arb_consistency_test.dart`，用 `dart:io` 讀四份 JSON，隨 `flutter test` 執行（repo 沒有 CI，Node 腳本只能靠提交前手動跑，風險與現在「記得四份同步」相同） |
| 檢查項目 | A. `zh`、`en`、`zh_CN` 對 `zh_TW` 不得缺鍵、不得多鍵；B. 每鍵 placeholder 名稱集合一致；C. `en` 與 zh_TW 字串相同、或 `en` 值含中文字元，視為漏翻，除非列入白名單。略過 `@@locale` 與所有 `@key` |
| 不檢查 | `zh_CN` 與 zh_TW 相同（現況 78 個多為兩岸寫法一致的詞，白名單會變 78 行噪音，且擋不住「漏翻成簡體」，需繁簡字典才判得出，超出範圍）；模板每鍵須有 `@` 描述（現況 641/641，gen-l10n 不因缺 `@` 出錯，YAGNI） |
| `app_zh.arb` 定位 | 強制 `zh` 每個鍵與 `zh_TW` 逐字相同。它存在只因 Flutter 3.41 gen-l10n 在有國別代碼的 locale 時必須有 base locale，沒有獨立翻譯理由；若將來要讓它分歧，改測試是明確決定而非意外 |
| placeholder 抽取 | 四份字串各自用 `{s*(w+)s*(?:,|})` 抽名稱集合互相比對（對稱、不依賴 `@` 中繼資料）。已驗證此規則在 641 鍵上與 template 的 `@key.placeholders` 宣告零差異。已知限制：將來若加 `select` 語法，分支內單字 `{He}` 會被誤判，屆時測試報錯再調整，不提前處理 |
| 白名單 | 測試檔內 `const Map<String, String>`（鍵 → 理由），目前 3 筆：`settingsLanguageZhTW`／`settingsLanguageZhCN`／`settingsLanguageEn`（語言自稱，不翻譯）。白名單項目若不再命中（字串已不同、鍵已刪）測試同樣失敗，逼人清掉過期項目 |
| 守衛自身驗證 | 偵測邏輯寫成純函式放 `app/test/l10n/arb_consistency_helpers.dart`，用小型合成資料各寫一個測試證明每條規則會失敗（缺鍵、多鍵、placeholder 少一個、en 漏翻、en 含中文、zh 偏離、白名單過期，約 8 個）；真實檔案測試呼叫同一組函式 |
| 失敗訊息 | 一次列出所有違規鍵（如 `[en] 缺鍵：a, b`），不是遇到第一個就停 |
| 文件 | `app/tool/README.md`「找到問題時怎麼修」第 1 步加一行指向新測試；`CLAUDE.md` 不動（不是新指令）；`CONTEXT.md` 不新增詞條；不寫 ADR |
| 行為變動 | 無（僅新增測試，不改任何 App 程式碼與 ARB） |

## Issue 7、8 設計決策（`/improve-codebase-architecture` 第二次檢視後 `/grilling` 定案，2026-10-02）

來源：第二次架構檢視的候選 1（閱讀會話生命週期）與候選 2（位置寫入規則）；報告存暫存目錄，不進版控。檢視另有三個候選未排入：LibraryScreen 依賴 bundle、重新連結概念跨檔案、睡眠定時器放在畫面層，皆為 Worth exploring，需要時再開 Issue。

**事實修正（探索子代理回報，已核對）**
- 位置只在「進入背景」與「dispose」兩處寫入；`onLocatorChanged` 只判斷是否算閱讀活動，不寫位置也不觸發 Checkpoint。
- `SyncEngine` 不使用 `ReadingPositionRepository`，直接對 `books` 表讀寫相同欄位，`position_updated_at` 的維護邏輯因此有兩份。**不在本批 Issue 範圍**，需要時另立。
- `dispose` 實際順序：統計 flush → … → 寫位置 → 觸發 Checkpoint；僅「寫位置須在觸發 Checkpoint 之前」有註解說明的依賴，且兩者皆不 await。
- `reader_screen.dart:400` 註解：刻意不在 `didUpdateWidget` 跟隨 `filePath`，所以一個 State 恆為一本書。

**定案**
1. 拆成兩張 Issue。Issue 7（位置 module）先做，Issue 8（會話 module）後做並呼叫它。
2. 會話 module 擁有 5 分鐘 Checkpoint Timer；sync 觸發器為注入依賴，測試以 fake 取代（沿用現有 `SyncCheckpointTrigger`）。
3. 會話邊界 = 一個 `ReaderScreen` State 的生命週期。
4. 會話搬走：統計 tracker 建立與收尾、Timer、`markReaderOpened`／`markReaderClosed`、前後景切換時的位置寫入與統計通知、dispose 收尾順序。留在畫面：音量鍵 channel、螢幕方向與 system UI、TTS 與 audio focus dispose、搜尋高亮 timer、睡眠定時器。
5. 「這次 relocate 算不算閱讀活動」（Foliate 比對 cfi＋index 的 key、PDF 一律算）歸會話 module，不歸 `ReadingStatsTracker`。
6. **純重構、零行為變化**：連同「`paused` 不觸發 Checkpoint」「先 flush 統計再寫位置」「位置寫入不 await」都逐字保留，寫進 module 文件。要改順序另開缺陷 Issue。
7. 不新增 `ReaderScreen` 建構參數（目前 27 個）；由內部以既有的注入點組裝。
8. 測試：replace, don't layer。只遷移「生命週期與位置規則」案例（`reader_screen_test.dart` 約 600、2260–2300、6386–6560 行附近與 `reader_screen_stats_*`），純 UI 案例留在 widget 測試。每個 Task 只跑異動到的測試檔，全套只在最後一個 Task 與發 PR 前各一次。
9. 流程：兩張 Issue 都寫 `plan-issue-N.md`。

CONTEXT.md 已新增「閱讀會話」「位置儲存規則」兩詞條。無需新 ADR（可逆、不違反既有 ADR）。

## 開發記錄

**2026-09-30 登錄 Epic**，分支 `epic-54/issue-1-available-fonts`。實作計畫見 `plans/plan-issue-1.md`。

**2026-09-30 Issue 1 實作完成**：新增 `AvailableFonts` 純值物件（`app/lib/reader/available_fonts.dart`）；`ReaderSettingsSheet` 參數 2→1（`customFonts`／`installedFonts`→`availableFonts`）；`ReaderScreen` 4 個欄位→單一 `AvailableFonts?`（`null`＝載入中），刪除 `_renderedFontFamily`，載入改為 record `.wait` 並行、各自 catch（任一邊失敗視為空集合）。行為調整：偏好為不認得的名稱或沒有 store 時，渲染端改傳 `null`，與設定面板顯示一致（偏好本身不改寫）。測試：純測試 11 個（`available_fonts_test.dart`）；`reader_screen_test` 翻轉 2、刪除 3、新增 2（「一邊載入失敗」「載入中離開畫面」）。驗證：`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS；7 個相關測試檔 622/622 通過（`available_fonts_test` 11、`foliate_native_bridge_test` 28、`foliate_reader_view_test` 117、`reader_settings_sheet_test` 95、`font_management_screen_test` 49、`downloadable_font_store_test` 35、`reader_screen_test` 287；尚未跑完整 `flutter test`）。

**2026-09-30 程式審查與修訂**

- 審查報告：`reviews/review-code-issue-1.md`（不進版控），0 Critical／0 Important／4 Minor，結論 With fixes。
- M-1：`ReaderScreen` 兩個建構參數（`customFontsRepository`、`downloadableFontStore`）的 doc comment 改為符合新行為（沒有 store 時內建字型偏好退回書本字型）。
- M-2：`reader_screen_test.dart` 字型區塊刪除 2 處多餘空行；`reader_settings_sheet_test.dart` 過長自訂字型名稱測試的 `CustomFont(...)` 縮排修正。
- M-3：上方驗證數字補上 7 個檔名與各自數量；reviewer 只得 587 是因為被指定的清單少了第 7 個檔 `downloadable_font_store_test.dart`（35 個），622 可重現。
- M-4：不需動作。
- 「未評判」5 項：均維持不處理；「`FontManagementScreen` 自己持有 `_installedFonts`」是否列為後續待辦由使用者決定。
- 驗證：`flutter analyze` No issues found；上述 7 個檔修訂後重跑 622/622 通過。
- 全套 `flutter test`：3221 個通過（1 個略過）；`flutter analyze` 乾淨；`check_l10n_hardcoded_strings.js` PASS。準備發 PR。

**2026-09-30 PR 合併**

- PR #302（`epic-54/issue-1-available-fonts` → `main`）已合併。Issue 1 完成。Issue 2～6 尚未設計，動手前各自須先 `/grill-with-docs`；本 Epic 維持開發中，待所有 Issue 完成或決定收尾後再歸檔。

**2026-10-01 Issue 5 實作完成**：新增 `OpenBookFlow`（`app/lib/reader/open_book_flow.dart`，`ChangeNotifier`＋密封類別狀態 `Loading`／`Probing`／`Rendered`／`Failed`／`Relinking`）；`ReaderScreen` 刪除 `_RenderState` 與 6 個狀態欄位（`_state`、`_errorMessage`、`_probeResult`、`_isProbingAccess`、`_isRelinking`、`_openBookTimeoutTimer`），`_activeFilePath` 改為 flow 的 getter。細部調整（與設計表的差異）：`Failed` 存 `source`／`viewMessage`／`probeResult` 而非 `message`；`relink()` 接收選檔 callback 而非已選好的檔案，使選檔期間仍有狀態可停用按鈕。行為調整：`content://` 書籍開書逾時也做存取探測。測試：純測試 34 個（`open_book_flow_test.dart`）；`reader_screen_test` 283 個（遷出 7 個、翻轉 1 個為 3 個、新增 1 個、另更新「重新開書後再次卡住時」期望為新行為）。「relink 後再失敗會重新探測」既有 widget 測試已涵蓋，不另補。驗證：相關 4 檔 394/394 通過；全套 `flutter test` 3251 通過、1 略過（審查修訂補 4 個測試後重跑：3255 通過、1 略過）；`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS。程式審查結果見下方「程式審查與修訂」。待發 PR。

**2026-10-01 程式審查與修訂**（獨立審查員，範圍 `cc189f94..8b957b69`；審查報告在 `reviews/` 不進版控，以下為摘要。0 Critical／0 Important／5 Minor，結論 Ready to merge。審查員實跑：`flutter analyze` 乾淨、`open_book_flow_test`＋`reader_screen_test` 317 通過、`check_l10n_hardcoded_strings.js` PASS；對照 `main` 逐項比對 `ReaderScreen` 行為，未發現未說明的行為改動；計畫指定遷移的 7 個 widget 測試皆已刪除並有純測試對應）

- M-1（行為差異，不改程式，記錄於此與 PR 描述）：`onRendered` 重複呼叫不再 `setState`（只有第一次重繪）；失敗後晚到的 `onRendered` 不再把錯誤畫面翻回已渲染。前者是無害的效能收斂，後者因失敗時閱讀視圖已被移出樹，實務上不會發生，且符合「失敗後不復活」語意。
- M-2：`_FakeTimer` 新增 `forceFire()`（無視取消狀態直接呼叫 callback），補 4 個測試直接驗證 `_onTimeout` 的狀態 guard（Rendered 後、Failed 後、dispose 後）與「重複 `start()` 先取消舊計時器」。變異驗證：暫時拿掉 `_onTimeout` 的 guard，3 個新測試如預期失敗，已還原。原兩個空轉測試保留（仍驗證視圖錯誤部分）。
- M-3：`app_zh_TW.arb` 的 `readerFailedToLoadBookMessage` 描述改為指向 `OpenBookFailed.viewMessage`；以 `flutter gen-l10n` 重新產生，`app_localizations.dart` 只有該行描述變動。
- M-4：`OpenBookFlow` 類別註解補上指向 epic-27 `bugfix-repro.md` 與 epic-18 Issue 33 的追溯路徑。
- M-5：`isFailed` 改為 `failure != null` 推導，消除兩個 getter 各自維護的不變式風險。

**2026-10-01 PR 合併**

- PR #303（`epic-54/issue-5-open-book-flow` → `main`）已合併，合併 commit `707645e5`。Issue 5 完成。審查修訂後全套 `flutter test` 3255 通過、1 略過。
- 待真機確認（PR 描述已列）：`onPageRendered` 在 Foliate WebView／pdfrx 的實際觸發頻率，以及慢速裝置上逾時多一次探測的延遲。
- 後續：Issue 2、3、4、6 尚未設計，動手前各自須先 `/grill-with-docs`。Issue 3 做時評估字型重新連結是否與 `OpenBookFlow` 共用「探測後分類」；Issue 4 把探測移出 `foliate_native_bridge.dart` 時，`open_book_flow.dart` 內對 `StorageAccessProbeResult` 的 import 需改一行。

**2026-10-01 Issue 3 實作完成**：新增 `persistReadAccess`（`app/lib/storage/storage_permission.dart`，集中 4 處 `takePersistableUriPermission` 呼叫，失敗處置仍由各呼叫端決定）、`CustomFontRelinker`（`app/lib/reader/custom_font_relinker.dart`，密封類別 `FontRelinkResult` 與 `BookRelinkResult` 並列）、`resolveFontFamilyName`／`stripFontFileExtension`（`font_name_parser.dart`，上傳與重新連結共用同一條家族名稱規則）；`ImportResult` 新增 `failure`。與設計表的差異：`_stripExtension` 改為公開的 `stripFontFileExtension` 並移入 `font_name_parser.dart`，避免兩份實作。行為調整：① 字型重新連結失敗顯示 SnackBar（重用 `readerStorageRelinkFailed`）；② 資料夾匯入三條失敗路徑回報 `failure` 並顯示新訊息 `libraryImportFolderFailedMessage`（4 份 ARB）。測試：新增純測試 21 個（`storage_permission_test` 3、`font_name_parser_test` 4、`custom_font_relinker_test` 8、`book_import_service_test` 5、`book_import_picker_helper_test` 1）；`font_management_screen_test` 刪 1 個規則類（授權失敗仍更新 URI，改由 relinker 純測試涵蓋）、`updateUri` 失敗測試補 SnackBar 斷言。驗證：觸及檔 219/219 通過；全套 `flutter test` 3275 通過、1 略過（Issue 5 基準 3255＋20＝21 新增−1 刪除）；`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS。程式審查結果見下方「程式審查與修訂」。待發 PR。

**2026-10-01 程式審查與修訂**（獨立審查員，範圍 `560cdcf5..10ec1ca6`；審查報告在 `reviews/` 不進版控，以下為摘要。0 Critical／0 Important／4 Minor，結論 Ready to merge。審查員實跑：`flutter analyze` 乾淨、受影響 6 個測試檔 174 通過、`check_l10n_hardcoded_strings.js` PASS、`flutter gen-l10n` 後工作樹乾淨；對照 `main` 逐項比對 `_relinkFont`、批次上傳、`_persistPermissionOrLandCopy`、`relinkBook` 皆無行為差異；Dart `lib/` 只剩 `storage_permission.dart` 一處實際呼叫 `takePersistableUriPermission`）

- M-1（已修）：`book_import_service.dart` 的 `ImportResult` 說明註解被新增的 `ImportFailure` 區塊接在後面，兩段 `///` 合併成同一份註解掛到 enum 上；`ImportFailure` 移到說明之前，註解回到 `ImportResult` 上。
- M-2（已修）：`CustomFontRelinker.relink` 的「保證不拋出例外」註解與 `try` 範圍不一致（`resolveFontFamilyName` 在 `try` 外）；整段移進 `try`，並在註解說明。
- M-3（不處理）：訊息「請確認已授權存取」對「已有授權但列舉失敗」稍偏。設計決策本來就選擇兩種失敗共用一則。
- M-4（不處理）：`storage/storage_permission.dart` 為取得 channel 常數而 import `library_repository.dart`，依賴方向不理想。把常數搬家會動到許多檔案，不屬於本 Issue，可在 Issue 4 一併評估。
- 實作者自審另列兩項 defer，亦未處理：測試輔助 `mockPersistPermission` 的 `throws` 參數已無人傳 true；`_relinker` 以 `late final` 綁定初建的 repository，實務上到不了。
- 驗證：修訂後 `flutter analyze` No issues found；`custom_font_relinker_test`、`book_import_service_test`、`font_management_screen_test`、`book_import_picker_helper_test` 共 159 通過。修訂後重跑全套 `flutter test`：3275 通過、1 略過、0 失敗（兩項修訂只動註解順序與 `try` 範圍，未新增或刪除測試）。待發 PR。

**2026-10-01 PR 合併（Issue 3）**

- PR #304（`epic-54/issue-3-font-relink-permission` → `main`）已合併，合併 commit `ab8aa403`。Issue 3 完成。全套 `flutter test` 3275 通過、1 略過。
- 待真機確認（PR 描述已列）：媒體庫等不核發持久化授權的文件提供者，在字型上傳、字型重新連結、資料夾匯入三處的實際行為。
- 後續：Issue 2、4、6 尚未設計，動手前各自須先 `/grill-with-docs`。Issue 4 把探測搬出 `foliate_native_bridge.dart` 時，依設計放進 `app/lib/storage/`（與 `storage_permission.dart` 同目錄），並順手評估審查 M-4：`storage_permission.dart` 為取得 channel 常數而 import `library_repository.dart` 的依賴方向。

**2026-10-01 Issue 4 實作完成**：新增 `app/lib/storage/storage_access_probe.dart`，把 `StorageAccessProbeResult`、`ProbeStorageAccess`、`kStorageAccessProbeTimeout`、`probeStorageAccess`、`probeStorageAccessViaChannel` 從 `foliate_native_bridge.dart` 搬出（名稱不變、不留 re-export）；新檔自己宣告私有 `MethodChannel('elinkbook/reader_resources_cache')`，原生端與 channel 名稱不動。`reader_screen`／`font_management_screen`／`open_book_flow` 與 4 個測試檔改 import；探測測試群組（13 個）自 `foliate_native_bridge_test` 搬到 `test/storage/storage_access_probe_test.dart`，另新增 1 個釘住逾時 3 秒的測試。純搬家，無行為變動；`ReaderScreen` 對 `foliate_native_bridge.dart` 的引用歸零（它對橋接檔唯一的 import 就是探測）；M-4（`kBookMetadataChannel` 位置）依設計不處理；書籍與字型對探測結果的解讀差異依設計不統一。驗證：全套 `flutter test` 3276 通過、1 略過（Issue 3 合併後基準 3275＋1 個新增測試）；`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS。程式審查結果見下方「程式審查」。待發 PR。

**2026-10-02 程式審查**（獨立審查員，範圍 `934fcd9c..3f3962bb`；審查報告在 `reviews/` 不進版控，以下為摘要。0 Critical／0 Important／2 Minor，結論 Ready to merge。審查員實跑：`flutter analyze` 乾淨、觸及的測試檔群 401 通過（`storage_access_probe_test` 14 通過）、`check_l10n_hardcoded_strings.js` PASS；5 個符號與 `main` 的橋接檔逐字相同（僅 channel 宣告與註解不同），channel `elinkbook/reader_resources_cache` 與方法 `probeUriAccess` 和 `ReaderResourceChannel.kt` 一致；三個 lib 檔與四個測試檔都指向新檔的同一個頂層變數，注入覆寫有效；`lib/`、`test/` 無舊定義、re-export 或孤兒 import，`ReaderScreen` 對橋接檔的依賴歸零，無循環依賴；橋接測試搬走恰好 13 個案例，無其他覆蓋損失）

- M-1（不處理）：`reader_screen.dart` 的新 import 夾在 `reader/` 的 import 群組中間，純風格；計畫本來就指定原位替換。
- M-2（不處理）：channel 在橋接檔與新檔各宣告一次，是計畫接受的取捨（`MethodChannel` 只是依名稱指向同一條原生通道的代理），新檔註解已說明。
- 全套 `flutter test` 審查員未重跑；發 PR 前由實作者重跑：第一次 3275 通過、1 略過、**1 失敗**（`test/downloads/download_queue_controller_test.dart`「偵測到重複且 onDuplicateConfirm 回傳 false 時，標記為略過且不呼叫 import」，預期 `duplicateSkipped`、實際 `checkingDuplicate`）；本分支未動 `lib/downloads`／`test/downloads`，該檔單獨連跑 5 次全過，不改任何程式直接重跑全套則 **3276 通過、1 略過、0 失敗**。判斷為既有的不穩定測試（只用固定輪數的 `pumpEventQueue()` 等非同步鏈，整套並行負載高時可能來不及），與本 Issue 無關，不在本 Issue 處理；若之後重複出現，應另立工單把等待改為條件式。

**2026-10-02 PR 合併（Issue 4）**

- PR #305（`epic-54/issue-4-storage-access-probe` → `main`）已合併，合併 commit `e8cbd95b`。Issue 4 完成。全套 `flutter test` 3276 通過、1 略過。
- 待真機確認：無（純搬家，無行為變動）。
- 附帶：`test/downloads/download_queue_controller_test.dart` 在整套並行時偶發失敗（只用固定輪數的 `pumpEventQueue()` 等非同步鏈），與本 Epic 無關，未處理；若重複出現，應另立工單把等待改為條件式。
- 後續：Issue 6 尚未設計，動手前須先 `/grill-with-docs`；本 Epic 其餘 Issue 完成後再決定是否歸檔。

**2026-10-02 Issue 2 實作完成**：雲端匯入端正確區分「雲端授權失效」與暫時性錯誤。新增 `app/lib/cloud_import/cloud_auth_classifier.dart`（`isRefreshTokenRejected`：換發 token 端點回 400／401 視為授權被撤銷；`throwCloudApiStatusError`：資料 API 回 401 拋 `CloudAuthRequiredException`，其餘非 200 拋一般例外），兩個 OAuth client 與兩個 storage client 共用（兩個 OAuth client 本身刻意不合併）。`ensureValidAccessToken` 簽章不變，`null` 專指需重新連結（未連結或換發被拒）；斷網與 429／5xx 改為往上拋，由呼叫端歸為一般網路錯誤；刻意不主動 `unlink`。`QueuedDownloadJob` 新增抽象方法 `isAuthFailure`（`CloudDownloadJob` 回傳 `error is CloudAuthRequiredException`，`RemoteDownloadJob` 回傳 `false`），`DownloadQueueItem` 新增 `needsReauth`（預設 false，重試先重設；已取消的工作不設旗標）；面板對 `needsReauth` 項目顯示「需重新連結帳號」（新 ARB 鍵 `downloadQueueStatusNeedsReauth`，四份同步＋`flutter gen-l10n`），保留重試鈕，不加「前往重新連結」按鈕。與設計表的兩處差異（見 `plans/plan-issue-2.md` 開頭）：① `isAuthFailure` 改為抽象方法（`implements` 不繼承本體，預設值無從生效）；② 瀏覽畫面 widget 測試不翻轉（`CloudBrowserScreen` 未動），改在 storage client 測試驗證斷網不拋 `CloudAuthRequiredException`。測試：新增 35 個（分類規則 5、兩 OAuth client 各 5、兩 storage client 各 6、控制器 4、`cloud_download_job_test` 1、面板 3）；刪除 2 個（Google／OneDrive storage client 的 `HTTP 非 200 回應時拋出例外` 各 1 個，被 group 內的 403 案例取代）。驗證：`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS；全套 `flutter test` 3309 通過、1 略過、0 失敗。待發 PR。
- 待真機確認：真實 Google／OneDrive 帳號被撤銷授權後，瀏覽顯示「請重新連結」、下載佇列顯示「需重新連結帳號」，以及飛航模式下瀏覽顯示網路錯誤而非重新連結。

**2026-10-02 Issue 2 程式審查與修訂**（獨立審查員，範圍 `50d3d79b..71141c07`；審查報告在 `reviews/review-code-issue-2.md`，不進版控，以下為摘要。0 Critical／0 Important／4 Minor，結論 Ready to merge。審查員實跑：`flutter analyze` 乾淨、`check_l10n_hardcoded_strings.js` PASS、`test/cloud_import` 整個目錄與佇列控制器、面板、瀏覽畫面測試通過；grep 確認所有 `ensureValidAccessToken` 呼叫點與 `QueuedDownloadJob` 實作者都已處理；ARB 四份與生成檔以讀檔比對一致）

- M-1（不處理）：兩個 storage client 新增 import 的排序，純風格。
- M-2（已修）：補控制器測試「授權失效後重試又遇一般失敗：仍是 failed，但 `needsReauth` 重設為 false」。控制器測試由 4 個增為 5 個，Issue 2 新增測試合計 36 個。
- M-3（不處理）：storage client 非 401 的下載與縮圖路徑沒有直接測試；三個方法共用 `throwCloudApiStatusError`，規則已由分類測試與 `listFolder` 的 403／500 測試涵蓋。
- M-4（不處理）：token 端點的 400 一律視為授權撤銷，這是設計表定案的假設（`invalid_request` 等其他 400 也會被當成需重新連結，實務上罕見）。
- 審查員「未判斷」5 項（真機上服務端實際回應碼、面板無前往設定的導引等）均維持不處理，導引按鈕已在設計決策中排除。
- 驗證：修訂後 `flutter analyze` No issues found；`download_queue_controller_test` 14 個全數通過。上方「實作完成」記載的全套 3309 通過是補測試前的數字，補 1 個測試後重跑全套：3310 通過、1 略過、0 失敗。

**2026-10-02 PR 合併（Issue 2）**

- PR #306（`epic-54/issue-2-cloud-reauth` → `main`）已合併，合併 commit `f6f76873`。Issue 2 完成。全套 `flutter test` 3310 通過、1 略過。
- 待真機確認：真實 Google／OneDrive 帳號被撤銷授權後，瀏覽顯示「請重新連結」、下載佇列顯示「需重新連結帳號」；飛航模式下瀏覽顯示網路錯誤而非重新連結。
- 後續：Issue 6 尚未設計，動手前須先 `/grill-with-docs`；本 Epic 其餘 Issue 完成後再決定是否歸檔。另有兩項已排除、可另立工單的項目：在佇列面板或瀏覽畫面加「前往重新連結」按鈕（需牽動 `CloudAccountSettingsScreen` 的依賴建構）、合併 Google 與 OneDrive 兩個重複的 OAuth client。

**2026-10-02 Issue 6 實作完成**：新增 ARB 一致性守衛，只加測試、不改 App 程式碼與 ARB。

- 新增三個測試檔：`app/test/l10n/arb_consistency_helpers.dart`（偵測純函式：`messagesOf`、`loadArbMessages`、`placeholderNames`、`keySetViolations`、`placeholderViolations`、`zhMirrorViolations`、`enUntranslatedViolations`）、`arb_consistency_helpers_test.dart`（合成資料測試 21 個）、`arb_consistency_test.dart`（讀真實四份 ARB 的守衛測試 4 個，持有 `_enAllowlist` 3 筆語言自稱）。
- 變異驗證（改壞真實檔→確認守衛失敗→還原，四種皆如預期）：刪 `en` 的 `cancel` 報 `[en] 缺鍵：cancel`；`en.cancel` 設成與 zh_TW 相同報疑似漏翻；拿掉 `zh_CN` 的 `settingsLanguageFollowSystemSubtitle` 的 placeholder 報 placeholder 不一致；`zh.cancel` 加字尾報 `[zh] 與 zh_TW 文字不同的鍵：cancel`。全部還原後守衛 4/4 通過。
- 驗證：`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS；全套 `flutter test` 3335 通過、1 略過、0 失敗（Issue 2 合併基準 3310＋helpers 21＋守衛 4）。
- 行為變動：無。待真機確認：無。
- 文件：`app/tool/README.md`「找到問題時怎麼修」第 1 步加註守衛測試，並新增第 4 步說明 `_enAllowlist` 用法。待程式審查與發 PR。

**2026-10-02 Issue 6 程式審查與修訂**（獨立審查員，範圍 `42ce8cd3..b31b5c47`；審查報告在 `reviews/review-code-issue-6.md`，不進版控，以下為摘要。0 Critical／0 Important／5 Minor，結論 Ready to merge。審查員實跑：`flutter analyze` 乾淨、`check_l10n_hardcoded_strings.js` PASS、兩個測試檔 25 個全過、`app/lib` 零異動、相對路徑 `lib/l10n/...` 在 `flutter test` 下成立；七個公開函式簽章、違規訊息字串、白名單三筆與計畫逐字一致；Review Focus 五條皆有有效測試。審查員未對 ARB 副本實際執行變異，改以推理並附對照表）

- M-1（已修）：補合成測試「zh 缺鍵：不在此重複回報（交給 `keySetViolations`）」。變異驗證：暫時拿掉 `zhMirrorViolations` 的 `zh.containsKey(k)`，新測試如預期失敗，已還原。helpers 測試由 21 個增為 22 個，Issue 6 新增測試合計 26 個。
- M-2（不處理）：中文字元判定只含 `一-鿿`，不含全形標點與假名；這是計畫固定的規則，非實作偏離。
- M-3（不處理）：`placeholderViolations` 只比名稱集合，不比數量或型別；名稱集合即設計決策。
- M-4（不處理）：測試檔有超長行、未跑 `dart format`，純風格。
- M-5（已修）：`app/tool/README.md` 新增的「第 4 點」不屬於「找到問題時怎麼修」的步驟，改為獨立小節「ARB 一致性守衛」，並去掉第 3、4 點間多餘的空行。
- 審查員「未判斷」5 條均維持不處理。
- 驗證：修訂後 `flutter analyze` No issues found；`test/l10n/arb_consistency_helpers_test.dart` 與 `arb_consistency_test.dart` 共 26 個全數通過。上方「實作完成」記載的全套 3335 通過是補測試前的數字，補 1 個測試後重跑全套：3336 通過、1 略過、0 失敗。待發 PR。

**2026-10-02 PR 合併（Issue 6）**

- PR #307（`epic-54/issue-6-arb-guard` → `main`）已合併，合併 commit `f7d5230b`。Issue 6 完成。全套 `flutter test` 3336 通過、1 略過。合併前曾與 `origin/main` 在 `docs/epics.md` 衝突（Epic 54 那列的 Issue 6 進度，對上 Epic 55 新增的第 56 列），兩邊皆保留，無程式碼衝突。
- 待真機確認：無（僅新增測試）。
- 已知限制（寫在 `app/tool/README.md` 與 `arb_consistency_helpers.dart`）：ICU `select`／`plural` 的單字分支（如 `=0{None}`）會被誤判成 placeholder，避開寫法是寫成含空格的片語；`zh_CN` 與 zh_TW 相同的字串不檢查。
- **Epic 54 的 6 個 Issue 全數完成並合併**（#302、#306、#304、#305、#303、#307）。是否歸檔由使用者決定；歸檔時依 sdd-workflow 慣例，`.gitignore` 的 reviews 規則改指向 archive 路徑，不刪除。

**2026-10-02 Issue 7 實作完成**（分支 `epic-54/issue-7-position-saver`，worktree 內 Native 直接開發，未使用 subagent。計畫見 `plans/plan-issue-7.md`）

- 新增 `app/lib/reader/reading_position_saver.dart`（`ReadingPositionSaver`：持有最新一筆 PDF／Foliate 位置回報與各格式「開書後是否已重新定位」旗標，依格式決定要不要儲存、存什麼）；`ReaderScreen` 刪除 `_writeCurrentPosition` 與 `_hasRelocatedSinceOpen`，改為在回呼中轉發位置回報、在 dispose／paused 呼叫 saver（呼叫順序不變）。
- 被刪除的 widget 案例：無（盤點 `reader_screen_test.dart` 12 處引用，皆為接線或開書位置選擇，全數保留）；新增 16 個單元測試（`test/reader/reading_position_saver_test.dart`，規則表逐條涵蓋，含總頁數為 0、progression 為 null 回退、跳轉後首次回報不儲存等過去完全沒有測試的規則）與 2 個接線測試（paused 觸發儲存、Foliate `onLocatorChanged` 轉發，皆先在舊程式碼上確認通過）。
- 與計畫的差異（2 項，均記於執行 ledger）：(1) `initialProgress` 取值由 `loaded.readingPosition?.progress` 改為 `.progress`（`LoadedPrefs.readingPosition` 為非空型別，`?.` 觸發 analyze 警告；行為等價）；(2) 另更新計畫未列的 5 處過時註解（`main.dart`、`app_lifecycle_sync_test.dart` 各 1 處，`reader_screen_test.dart` 3 處），純文字，不斷言與程式零變動。
- 驗證：全套 `flutter test` 3369 通過、1 略過、0 失敗；`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS。
- 行為變動：無（純重構）。待真機確認：無。待程式審查與發 PR。

**2026-10-02 Issue 7 程式審查與修訂**（獨立審查員，範圍 `e005a4de..4ba13a59`；審查報告在 `reviews/review-code-issue-7.md`，不進版控，以下為摘要。0 Critical／0 Important／3 Minor，結論 Ready to merge。審查員實跑：三個異動測試檔 305 案例通過、`flutter analyze` 乾淨、`_hasRelocatedSinceOpen`／`_writeCurrentPosition` 零命中；未獨立重現全套測試）

- M-1（已修）：`onLocatorChanged` 內「賦值前非 null」註解已不貼切，改為說明第一次／第二次回報的區分由 `ReadingPositionSaver` 處理。
- M-2（不處理）：saver 未建立時回報被 `?.` 靜默丟棄，無測試鎖定。目前不變式成立（`_resolved` 與 saver 同一個 `setState`），既有接線案例會在漏存時失敗；留待 Issue 8 收進會話 module 時一併考慮。
- M-3（**記錄為待處理缺陷，見下**）：重複回報同位置仍使「已重新定位」旗標成立。

**待處理缺陷（Issue 9，由 Issue 7 審查 M-3 發現，尚未修正）**

- 現象（依程式碼與既有註解推論，**尚未在真機重現**）：帶跳轉目標（搜尋結果、書籤）開書時，`ReadingPositionSaver` 以「該格式第二次回報」判定使用者已離開跳轉目標。但 Foliate 在開書後套用樣式重排、或圖片／字型載入後重新對齊錨點時，會派發「位置相同」的重複回報（`reader_screen.dart` 閱讀活動判定的註解已實證：同一 cfi 的 fraction 會來回微幅抖動）。這會讓旗標提早成立，使用者什麼都沒做就離開時，跳轉落點被存成新進度，覆蓋原本讀到一半的位置——正是這條規則要防止的情況。
- 這是修改前就存在的行為（Issue 7 只搬動、未改變）；PDF 路徑不受影響（頁碼回報不會無故重複）。
- 修正方向：旗標只在「位置真的改變」時成立，可沿用閱讀活動判定已有的「只比 cfi 與 index、忽略 fraction」的位置鍵比較。該比較目前在 `ReaderScreen`（`_locatorPositionKey`），預計 Issue 8 搬進會話 module，建議 Issue 8 之後再處理，避免兩個 Issue 同時動同一段邏輯。
- 動手前須先決定：要不要先用真機日誌確認重複回報確實發生在帶跳轉目標的開書流程；測試以 `ReadingPositionSaver` 單元測試（同位置重複回報不算重新定位）直接守住。

**2026-10-02 PR 合併（Issue 7）**

- PR #310（`epic-54/issue-7-position-saver` → `main`）已合併，合併 commit `e07cb604`。Issue 7 完成。全套 `flutter test` 3369 通過、1 略過、0 失敗（發 PR 前在最終 commit `32691768` 上重跑）。
- 待真機確認：無（純重構）。
- 後續：Issue 8（閱讀會話）尚未寫 `plan-issue-8.md`，動手前先寫計畫並審查；Issue 9（缺陷）建議在 Issue 8 之後處理，且動手前先決定是否以真機日誌確認重複回報確實發生。本 Epic 其餘 Issue 完成後再決定是否歸檔。

**2026-10-02 Issue 8 實作完成**（分支 `epic-54/issue-8-reading-session`，worktree 內 Native 直接開發，未使用 subagent。計畫見 `plans/plan-issue-8.md`）

- 新增 `app/lib/reader/reading_session.dart`（`ReadingSession`：開關、前後景、位置回報、活動判定、Checkpoint Timer、離開收尾順序 `markReaderClosed` → 統計 `flushAndClose` → 取消 Timer → 儲存位置 → 觸發 Checkpoint；`paused` 只做統計 `onEnteredBackground` → 儲存位置，不觸發 Checkpoint；位置寫入與統計 flush 皆不 await）；`ReaderScreen` 刪除 `_readingStatsTracker`、`_createReadingStatsTracker`、`_syncCheckpointTimer`、`_positionSaver`、`_locatorPositionKey`、`_recordReadingActivity`、`_forwardTtsPlaying`，改為 `late final ReadingSession _session` 並只轉發事件（`_epubPositionInfo`／`_pdfPageInfo` 保留，仍驅動頁尾 UI）。
- 被刪除的 widget 案例（2 個，皆有單元測試取代並先經變異驗證守得住）：「同一位置的重複回報不算閱讀活動」→「同 cfi 與 index 的重複回報不算活動」；「同一 cfi 只有進度小數抖動不算閱讀活動」→「同 cfi 只有 fraction 抖動不算活動」。其餘 widget 案例（首次回報、夾雜重複回報的正向、PDF、統計建立／清除／寫入失敗／注入優先、paused／resumed／離開／TTS、checkpoint 週期與離開觸發、readerActivityTracker、位置儲存接線）全數保留。
- 與計畫的差異：無（行號表逐項相符；`ReadingStatsTracker` import 因 widget 參數型別仍需而保留，只刪了 `dart:convert`）。
- 驗證：全套 `flutter test` 3391 通過、1 略過、0 失敗（Issue 7 合併基準 3369＋`reading_session_test.dart` 新案例 24−2 個刪除）；`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS。
- 行為變動：無（純重構）。
- **需要知道的事**：`dispose` 內畫面自己的收尾與 session 收尾的相對順序改變——原本五步（markReaderClosed／統計 flush／取消 Timer／儲存位置／觸發 Checkpoint）與畫面自己的收尾穿插，現在一次 `_session.close(...)` 在 `dispose` 開頭執行，儲存位置與觸發 Checkpoint 早於畫面自己的收尾。已逐項核對畫面自己的收尾（`_openBookFlow`、`_searchJumpHighlightTimer`、睡眠定時器、`removeObserver`、音量鍵 channel、`_pdfSearchStateNotifier`、`_ttsAudioFocusCoordinator`、`ttsAudioHandler.detachController`、`_ttsController.removeListener`／`dispose`）都不讀取 session 管理的任何狀態，且 `_ttsController.dispose()` 之前已先 `removeListener(_onTtsStatusChanged)`，不會在 session 關閉後又回報 TTS 狀態；可觀察行為相同。若之後發現任何相依，視為缺陷另立工單。
- 待真機確認：無（純重構）。待程式審查與發 PR。

**2026-10-03 Issue 8 程式審查與修訂**（獨立審查員，範圍 `5628fa0a..25226502`；審查報告在 `reviews/review-code-issue-8.md`，不進版控，以下為摘要。0 Critical／0 Important／3 Minor，結論 Ready to merge。審查員實跑：七個異動測試檔 351 案例通過、`flutter analyze` 乾淨、舊欄位名零殘留；未獨立重現全套測試、未做變異驗證。對照修改前版本逐項核對：session 內部五步順序一致、`dispose` 內畫面自己的收尾內容與相對順序未動且不讀 session 狀態、`paused` 不觸發 Checkpoint、活動判定與 `_locatorPositionKey` 逐字搬移，結論為無可觀察行為差異）

- M-1（不處理）：`late final _session` 若在 `initState` 賦值前失敗，`dispose` 會多拋 `LateInitializationError`。與既有 `_openBookFlow` 同風險且幾乎不可達，依「不為不可能情境加防護」不動。
- M-2（不處理）：兩行超過 80 欄，純格式；跑格式化可能連帶改到不相關的行，不值得。
- M-3（已修）：「注入 tracker 優先」案例的斷言由 `containsAll` 改為精確比對 `log == ['activity', 'flush']`，鑑別力更強。
- 審查員補充：Issue 9 因這次重構更容易修——位置回報都經過 `ReadingSession.onEpubLocated`，session 已有 `_lastEpubInfo` 與 `_locatorPositionKey`，改動點集中在 `reading_session.dart` 與 `reading_position_saver.dart`。

**2026-10-03 PR 合併（Issue 8）**

- PR #311（`epic-54/issue-8-reading-session` → `main`）已合併，合併 commit `fd98ef3e`。Issue 8 完成。全套 `flutter test` 3391 通過、1 略過、0 失敗（發 PR 前在最終 commit `78abd39a` 上跑）。
- 待真機確認：無（純重構）。
- 後續：Issue 1～8 全數完成；Issue 9（缺陷，Foliate 同位置重複回報使跳轉保護提早失效，尚未在真機重現）仍待處理，審查員指出這次重構讓它更容易修，改動點集中在 `reading_session.dart` 與 `reading_position_saver.dart`。是否先處理 Issue 9 再歸檔 Epic 54，由使用者決定。

**2026-10-03 Issue 9 實作完成**（分支 `epic-54/issue-9-relocate-dedup`，worktree 內 Native 直接開發，未使用 subagent。計畫見 `plans/plan-issue-9.md`，計畫審查 I-1／M-1／M-2／M-3 皆已採納）

- 修法：`ReadingSession` 私有的位置鍵提升為 `EpubPositionInfo.positionKey`（cfi＋index，忽略 fraction，解析失敗退回整段字串），session 的閱讀活動判定與 `ReadingPositionSaver` 的「已重新定位」旗標共用同一條規則。saver 只有在 `hasJumpTarget` 且旗標尚未成立時才比對，位置鍵與上一筆不同才設旗標；`_epubInfo` 恆常更新。PDF 路徑與 `ReaderScreen` 未動。
- 新增測試 16 個：`epub_position_info_test.dart` 7、saver 7（同位置重複回報、完全相同字串、index 改變、夾雜真移動、A→B→A、無法解析、一般開書）、session 層端到端 2。變異驗證：把比較改回舊行為（永遠 true），恰好 3 個案例失敗，還原後通過。
- 驗證：全套 `flutter test` 3407 通過、1 略過、0 失敗（Issue 8 基準 3391＋16）；`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS。
- 行為變動：旗標成立條件變嚴格，僅影響「帶跳轉目標的 Foliate 開書」；活動判定行為零變化（既有 session 案例未修改而通過）。`CONTEXT.md`「位置儲存規則」已補上「真正移動」定義。
- 待真機確認（可選）：從搜尋結果開書後不操作直接離開，確認原進度未被跳轉落點覆蓋。待程式審查與發 PR。

**2026-10-03 Issue 9 程式審查**（範圍 `814f1e5e..93a2798f`；審查報告在 `reviews/review-code-issue-9.md`，不進版控，以下為摘要。0 Critical／0 Important／2 Minor，結論 Ready to merge。審查員實跑：異動測試檔與相關畫面測試 356 案例通過、`flutter analyze` 乾淨、`_locatorPositionKey` 零殘留；未重跑全套、未獨立做變異驗證）

- M-1（不處理，待真機確認）：修正只擋「cfi 與 index 皆相同」的重複回報；若重排後回報的 cfi 字串與開書落點不同，旗標仍會提早成立。證據只涵蓋 fraction 抖動，為計畫已揭露的前提。合併後須實測：從搜尋結果開書、不操作直接離開，確認原進度未被覆蓋；若仍復現，依日誌另立工單放寬比較。
- M-2（不處理）：`CONTEXT.md` 「真正移動」括號偏長，純行文。

**2026-10-03 PR 合併（Issue 9）**

- PR #312（`epic-54/issue-9-relocate-dedup` → `main`）已合併，合併 commit `11461dd3`。Issue 9 完成。全套 `flutter test` 3407 通過、1 略過、0 失敗（發 PR 前在最終實作 commit 上跑）。
- 待真機確認：從搜尋結果開書後不操作直接離開，確認原進度未被跳轉落點覆蓋；若仍復現，依日誌另立工單放寬位置鍵比較（見程式審查 M-1）。
- **Epic 54 的 9 個 Issue 全數完成並合併。** 是否歸檔由使用者決定；歸檔時依 sdd-workflow 慣例，`.gitignore` 的 reviews 規則改指向 archive 路徑，不刪除。

**2026-10-03 新增 Issue 10**

- 來源：`epic-57-layout-override-save-drops-fields` 程式審查 M-1。書架版面覆寫 `_save()` 整列重建 `BookReaderPrefs`，欄位皆為 nullable，漏帶欄位編譯器不會報錯；epic-56、epic-57 已各自出現一次漏帶。登錄為本 Epic 的 Issue 10，依既定做法不另開 Epic。
- 內容與設計決策待動手前 `/grill-with-docs` 定案；Epic 暫不歸檔。

**2026-10-05 新增 Issue 11～14（依賴傳遞收斂）**

- 來源：2026-10-05 架構檢視候選 2（`/improve-codebase-architecture`）。同一類「bundle 逐欄轉送漏欄位」缺陷已出現三次（epic-26 Issue 7 審查、`computeFingerprint`、`ttsDegradedNotice`）；`ReaderScreen` 28 個參數中 17 個為 nullable 依賴，`reader_screen.dart` 在開單書搜尋時手動重建 bundle。
- 設計經 grilling 定案，詳見 ADR 0037：依賴按使用者分四組、單一物件經建構子傳遞、non-null required、測試預設全 fake、逐畫面一刀切、不用 `InheritedWidget`。Issue 11 先做，完成後確認設計成立再做 12～14。
- 工單審查（`reviews/review-issues-11-14.md`，2 Critical／4 Important／3 Minor）已逐項對照程式碼後採納並修訂 ADR 0037 與 Issues：`syncCheckpointTrigger` 同時放入閱讀器組與同步組（同一實例）、介面語言併入 `AppearanceDependencies`、`WifiTransferDependencies` 併入 `SourceDependencies`、`readingStatsTracker`／`pickSingleBookFile` 留作測試注入點、`buildReaderScreen` 暫時組裝僅限該處且於 Issue 12/13 移除、Issue 14 調為 Strong。原先整理分組時漏列這三項（`LibraryLocaleDependencies` 是第 6 個既有 bundle，非 5 個）。
- 已知風險：測試改動量大（`ReaderScreen(` 約 267 處、`LibraryScreen(` 約 135 處、`SettingsScaffold(` 約 53 處）；Issue 11 開工前須核對 `ReaderScreen` 的 17 個依賴中是否有 `readingStatsTracker` 這類由畫面自行建構者。

**2026-10-06 Issue 11 實作完成**（分支 `epic-54/issue-11-reader-deps`，worktree 內 Native 直接開發，未使用 subagent。計畫見 `plans/plan-issue-11.md`）

- 內容：新增 `ReaderFeatureDependencies`（18 欄位，non-null required）；`ReaderScreen` 建構子 29→12 個參數（含 `super.key`）；`BookSearchScreen` 改收整組；開單書搜尋整組轉傳（同一實例）；舊 bundle 暫由 `readerFeatureDependenciesFromLegacy` 轉換（缺欄位丟 `StateError` 含欄位名，Issue 12/13 移除）；測試改用預設全 fake 工廠。
- 驗證：Task 0 基準 512 全過；範圍測試 509 通過（算式：512 − 缺席 18（reader 17＋stats 1）− bundle 轉傳 6 ＋ 新增 21（工廠 5＋StateError 14＋sync 1＋完整轉換 1））；`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS。
- 被刪缺席測試（18，依前提 1，型別上不可達）：未提供 syncCheckpointTrigger／layoutPresetRepository 為 null／沒有傳入 store／searchRepository 為 null／libraryRepository 為 null／沒有匯入服務／未提供 bookmarksRepository（EPUB＋FXL）／未提供 highlights／notes（EPUB＋PDF）／未提供 ttsProvider（播放鍵、上下句/語速、Mini Player、safeWindow 回呼、小喇叭）／未提供 ttsAudioHandler／ttsAudioFocusSource／isFixedLayout:null 且未提供 libraryRepository／stats「閱讀器沒有 readingStatsRepository」；另刪 route 6 個 bundle 轉傳測試（「帶／未帶」已不可達）。
- `completeLegacyReaderFeatures()` 補齊：library 15 例＋search 8 例＝23 個「點選書籍進入閱讀器」測試。
- 孤兒鍵：`readerSaveAsPresetUnavailableMessage`（ARB 鍵保留未刪，待後續清理）。
- Review Focus 對應：1→route 對帳 same 身分 18 欄位；2→雙向 same（`searchScreen.dependencies`／`ReaderScreen.dependencies`，offstage 路由查找用 `skipOffstage: false`）；3→StateError 15 例；4→B 類 4 例補主題＋volume_key 全域 mock（無同因 ≥5 例）；5→降級提示測試保留改寫；6→CBZ 停用按鈕測試保留。
- 計畫外追加：`integration_test/` 21 檔 60 處同值機械遷移（提交門檻 bare analyze 乾淨所需；真機部分無法本地驗證，發 PR 時須跑裝置）。
- ADR 0037 措辭已同步修訂（§3 TTS 不新增 adapter、§6 轉換函式三呼叫點）。待程式審查與發 PR。
- 全量 `flutter test`（最終 commit 前）：3672 通過、1 略過、1 失敗——失敗為 `pdf_reader_view_filters_test` bold overlay debouncer 案例，在乾淨 main 上同樣失敗，既存缺陷與本 Issue 無關，不在本 Issue 修。

**2026-10-06 Issue 11 程式審查（獨立審查子代理）與修訂**（報告 `reviews/review-code-issue-11-independent.md`，不進版控；0 Critical／1 Important／5 Minor，Assessment：With fixes；子代理全量 `flutter test` 3672 通過／1 略過／1 失敗，同一個既有失敗案例，它未在乾淨 `main` 上重跑確認）

- I-1（已修）：舊程式 `isFixedLayout == null` 且未傳 `libraryRepository` 時，EPUB 視為 FXL；此 fallback 已刪，預設 `FakeLibraryRepository` 偵測為 `false`。只有兩個 integration 測試真的載入 FXL 素材（`fxl_bookmarks_test`、`reader_screen_test` 的「定樣式範例 EPUB」），已明確傳 `isFixedLayout: true`（與正式環境一致：匯入的 FXL 書本帶 `isFixedLayout: true`）。其餘 integration 測試由「FXL 語意」變為「流式偵測」，更貼近正式環境，維持現狀。
- M-1（已修）：`readerFeatureDependenciesFromLegacy` 新增可選 `searchRepository`，`LibrarySearchScreen` 開單書搜尋時沿用自己的參數（與遷移前行為一致），新增 2 個測試；Issue 12 須合併兩個來源並移除此參數（已記入 `issues.md` Issue 12）。
- M-2（已修）：`reader_screen.dart` 6 處過時註解更新。
- M-3（已修）：約 295 處 codemod 產生的超長單行展開為每引數一行。未整檔 `dart format`：base 版本這些檔案本來就不是 `dart format` 乾淨的，整檔格式化會混入無關改動。
- M-4（已修）：`legacyWithNull` 14 個 `switch` case 收斂為單一 helper；vacuous 的 `isNotNull` 測試改為逐欄 `same(...)` 對帳。
- M-5（記錄，未刪）：`readerSaveAsPresetUnavailableMessage` ARB 鍵已無使用端，排入 Issue 13 清理（`issues.md` 已註記）；`_ttsControllerOrNull` 命名維持不動（`null` 是「尚未按下朗讀」的合法狀態，審查亦判斷非必改）。
- 驗證（修訂後）：範圍測試 511 通過（509＋M-1 新增 2），0 失敗；`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS。integration 測試的真機結果見下兩則。
- 既存失敗確認（2026-10-06）：在乾淨 `main`（`bdff826c`，工作區乾淨）單獨跑 `pdf_reader_view_filters_test`，15 通過、1 失敗，失敗案例為「bold overlay 同時有多頁需要加粗運算時，各頁互不取消」（`Expected: >= 2, Actual: 1`），與分支全量測試的同一失敗一致。**確認為既存失敗，與 Issue 11 無關，不在本 Issue 修。**
- 真機 integration 結果（2026-10-06，OPD2102 `bfa4e772`，分支 `318584c8`）：`fxl_bookmarks_test` 0／1、`epub_toc_test` 0／1、`reading_position_test` 0／2、`foliate_cbz_test` 0／3、`reader_screen_test` 0／19——**全部失敗，0 通過**，皆為 `reader_screen.dart:2679` 的 `AppLocalizations.of(context)!` null check（測試的 `MaterialApp` 未設定 `localizationsDelegates`；`reading_position_test` 另有 1 個 `Bad state: No element` 為連帶結果）。base 版本 `_buildBody` 同一行與同樣缺 delegates 的測試寫法都存在，**確認為既存失敗**：在乾淨 `main`（`bdff826c`，無 Issue 11 改動）、同一台 OPD2102 上跑 `fxl_bookmarks_test`，同樣 0 通過／1 失敗，例外為 `_ReaderScreenState._buildBody` 的 `Null check operator used on a null value`（`reader_screen.dart:2878:46`，即 `AppLocalizations.of(context)!`；分支上同一行為 2679:46）。只對 `fxl_bookmarks_test` 做了 base 對照，其餘 4 個檔案的失敗原因與它一致（同一行 null check）但未逐一在 base 上跑；`integration_test/` 約 30 個檔案缺 `localizationsDelegates`，推測 integration 測試自加入介面多語系後即未維護。這批測試目前無法驗證 Issue 11：它們在第一步就失敗，沒有走到依賴組相關程式。

另外記錄：以 debug 版安裝時，手機上原有 elinkBook（versionCode 2001）因 `INSTALL_FAILED_VERSION_DOWNGRADE` 被 Flutter 自動解除安裝，該裝置上的 App 資料已清除。

**2026-10-06 新增 Issue 15（缺陷，測試基礎設施：integration 測試缺多語系設定）**

- 來源：Issue 11 的真機 integration 驗證。5 個檔案 26 個測試全部失敗，原因皆為 `AppLocalizations.of(context)!` 取到 null；base 上同樣失敗，為既存問題。
- 事實（2026-10-06 查證）：`integration_test/` 共 40 個檔案，33 個含 `MaterialApp(`、共 104 處，**33 個全部缺 `localizationsDelegates`**，沒有任何一個檔案有。`tool/check_l10n_hardcoded_strings.js` 只掃 `app/test/`（epic-45 Issue 0 建立 `pumpLocalizedWidget` 並加檢查時未涵蓋 `integration_test/`），所以這批測試自介面多語系導入後無聲壞掉，沒有任何機制發現。
- 工單內容與驗收見 `issues.md` Issue 15：統一改用帶多語系的包裝、把檢查腳本擴大到 `integration_test/` 當回歸守衛、真機驗證並分類補完後暴露的其他失敗。
- 時序：須等 PR #327（Issue 11）合併後再做——33 個檔案中有 21 個與 Issue 11 的 integration 遷移重疊，避免合併衝突。
- 流程建議：依「小型缺陷修正」慣例走直接 TDD（登錄於本 Epic，不寫 plan，保留程式審查）；但本案範圍較大（33 檔／104 處，且需真機驗證），若希望先寫 plan 請另行指定。
- 附帶發現：手機連線在測試過程中多次中斷（USB 接觸問題），真機驗證前先確認 `adb devices -l` 穩定。

**2026-10-06 PR 合併（Issue 11）**

- PR #327（`epic-54/issue-11-reader-deps` → `main`）已合併，合併 commit `fdced956`。Issue 11 完成。
- 合併後的後續：Issue 15（integration 測試補 `localizationsDelegates`）的時序前提（等 Issue 11 合併）已滿足，可處理；Issue 12 須合併 `LibrarySearchScreen` 的 `searchRepository` 來源並移除 `readerFeatureDependenciesFromLegacy` 的 `searchRepository` 覆寫參數（程式審查 M-1）；`readerSaveAsPresetUnavailableMessage` 孤兒 ARB 鍵排入 Issue 13 清理（M-5）。
- Issue 11 的 integration 遷移（21 檔、約 60 處）合併時只有靜態檢查，尚無執行期驗證，須待 Issue 15 補完後在真機驗證。
- 分支 worktree `.worktrees/epic-54-issue-11-reader-deps`（含 untracked 的 `.scratch/`）尚未清除。

**2026-10-06 Issue 15 實作完成（Task 0～3、Task 5；Task 4 真機驗證由使用者在另一台設備執行）**（分支 `epic-54/issue-15-integration-l10n`，worktree 內 Native 直接開發，未使用 subagent。計畫見 `plans/plan-issue-15.md`）

- 內容：檢查腳本新增 `--integration-dir`（Task 1；預設行為不變），33 檔 104 處 `tester.pumpWidget(MaterialApp(home: X))` 機械改寫為 `pumpLocalizedWidget(tester, X)`（Task 2；手動清單為空；`theme:` 僅在等於預設值時省略），無旗標預設納入 `integration_test/` 並更新 `tool/README.md`（Task 3）。
- 驗證：`flutter analyze` No issues found；檢查腳本三行 PASS（lib 250 檔、test 283 檔、integration 40 檔）；檢查腳本單元測試通過；`flutter test` 全量 3674 通過、1 略過、1 失敗——唯一失敗為既存 `pdf_reader_view_filters_test`（bold overlay 多頁案例，已在乾淨 `main` 確認，與本 Issue 無關；本 Issue 只動 `integration_test/` 與 `tool/`）。
**2026-10-06 Issue 15 真機驗證結果（Task 4，部分完成）**

- 裝置：`BooksPad`（Android 12，序號 `B78CW2508006423`，System WebView 91.0.4472.114）。原定的 `OPD2102`（`bfa4e772`）因 OPPO「透過 USB 安裝」驗證與 `flutter test` 自動安裝不相容而放棄。
- **範圍：32 個檔案只跑了 5 個**（計畫的 5 個關鍵檔案）。其餘 27 個**未執行**。原因：`BooksPad` 的 `adb` 傳輸只有約 100 KB/s，228 MB 的測試 APK 無法由 Flutter 自動安裝，每個檔案都要由使用者用 MTP 手動安裝。
- 執行方式（與計畫的 `flutter test` 不同，需知悉）：每個檔案先 `flutter build apk --debug --target=integration_test/<檔>.dart`，使用者手動安裝，再以 `flutter drive --use-application-binary` 搭配一個會吞掉 `install` 指令的 `adb` 替身執行。測試檔本身未改。替身與 `test_driver/` 都在 `.scratch/`／untracked，不進版控。
- **Step 5 結果：5 個檔案的 `Null check operator` 皆為 0 次。** 先前卡在 `AppLocalizations.of(context)!` 的缺陷已修好，畫面以正體中文顯示。

| 檔案 | 結果 | 例外摘要 | 分類 |
|---|---|---|---|
| `fxl_bookmarks_test` | `exit=1`（1 個失敗） | `等待逾時：載入指示器未消失`（`_pumpUntilLoaded`，第 32 行） | 待分類（同 `epub_toc_test` 症狀，未逐檔對照 base） |
| `epub_toc_test` | `exit=1`（1 個失敗） | `等待逾時：載入指示器未消失` | **B**：base `bdff826c` 補多語系後同機同樣失敗 |
| `reading_position_test` | `exit=1`（2 個失敗） | PDF 案例找不到文字 `進度 67% ｜ 第 4/6 頁`（第 88 行）；EPUB 案例為測試結束後的 `inTest is not true` 斷言 | 待分類（PDF 疑為 D 或跳頁未成功；EPUB 為連帶錯誤） |
| `foliate_cbz_test` | `exit=1`（1 個失敗） | `等待逾時：載入指示器未消失` | 待分類（同上症狀） |
| `reader_screen_test` | `exit=1`（1 個失敗） | `等待逾時（10 秒）：條件未成立`（渲染非空白內容） | 待分類 |

- **B 類依據（`epub_toc_test`）：** 在 base 的 worktree 對該檔案手動補上 `pumpLocalizedWidget`，同裝置執行，結果與本分支完全相同（`等待逾時：載入指示器未消失`，`exit=1`）。故不是 Issue 11 的回歸。建議另立工單。
- **輔助證據（非計畫要求的測試結果）：** 用同分支的一般 debug APK，`BooksPad`（WebView 91）與 `ViWoods Reader Air`（WebView 153.0.8010.36）都能正常開書閱讀。可排除「裝置 WebView 太舊」；問題只出在 integration 測試的執行情境，原因未查明。
- **未完成：** 其餘 27 個檔案未執行；4 個症狀相同的檔案未逐檔對照 base；`reading_position_test` PDF 案例與 `reader_screen_test` 的根因未查。D 類（斷言文字與 locale 不符）尚無確認案例，`reading_position_test` PDF 案例有嫌疑，待使用者決定。
- C 類（Issue 11 回歸）：目前 0 個確認。未修改任何 `lib/` 或測試檔。

**2026-10-06 Issue 15 已合併（PR #328）。** 真機驗證只完成 5/32 檔，其餘與根因調查移至 Issue 16。

**2026-10-06 Issue 16 實作完成與真機驗證結果**（分支 `epic-54/issue-16-integration-device`，worktree 內 Native 直接開發。計畫見 `plans/plan-issue-16.md`，附錄 A 為診斷結論）

- 裝置：`TCL 14`（序號 `3CEF42ECD491687`，Android 15，WebView 154）。前段在 `BooksPad` 嘗試，因下方「adb 服務」問題無法有效進行。
- **根因（載入指示器一直轉圈）：** `ReaderFeatureDependencies` 預設的 `FakeDownloadableFontStore.directory` 是不存在的 `/fake/downloaded-fonts`。`ReaderScreen` 把它傳給 `FoliateReaderView.downloadedFontsDirectory`，Android 原生的 `WebViewAssetLoader.InternalStoragePathHandler` 在建立 WebView 時拒絕，丟 `PlatformException`，`InAppWebView` 從未掛載，30 秒後 `OpenBookFlow` 逾時。`BooksPad` 實驗：H1（等待太短）不成立（指示器 28 秒消失，但出現 `reader_error_text`）、H2（JS 錯誤）不成立、H3（WebView 未掛載）成立。base `bdff826c` 的字型 store 可為 null，沒有這個 handler。
- **修法（只改 `app/test/support/`，未動 `lib/`）：** `FakeDownloadableFontStore` 新增 `directory` 參數與 `forPlatform()`。Android 上改用 `cache/` 底下真實存在的暫存目錄；其他平台維持原值。**踩到的錯：** 第一版用 `Directory.systemTemp`，在 Android 上是 `code_cache/`，`WebViewAssetLoader` 同樣禁用，TCL 14 驗證才發現，第二版改用其上一層的 `cache/`。commit `e6718ed4`、`2dd07925`。
- **Issue 11 回歸（C 類，已修）：** `library_screen_test` 漏傳 `readerFeatureRepositories`／`syncDependencies`，真機丟 `StateError: ReaderFeatureDependencies 缺少 bookImportService`。補上後，失敗與 base 對照完全相同（找不到 `book_item_…`，既存，B 類）。commit `c8276045`。
- **工具列 key 過期（D 類，部分已修）：** Epic 38 把按鈕搬到 `ReaderChromeBottomBar`，key 改名，單元測試已遷移，integration 測試漏了。已換：`reader_toc_button`→`reader_chrome_toc_button`、`reader_notes_button`→`reader_chrome_annotations_button`、`reader_layout_settings_button`→`reader_chrome_layout_button`、`reader_fixed_layout_bookmark_toggle_button`→`reader_chrome_bookmark_button`（8 檔 24 行，只換 key）。`foliate_highlights_notes_test` 因此通過。commit `4ae3d990`。
- **adb 服務問題（環境，非程式）：** 舊的 adb 服務（`Services` 工作階段，pid 11908）讓每個 adb 指令多等 12～23 秒、推送只有約 0.1 MB/s，`BooksPad` 與 `TCL 14` 都一樣。`adb kill-server` 重啟後降到 0.1 秒、23.5 MB/s。`BooksPad` 後續的 ANR（`Application does not have a focused window`）是否同因未驗證。
- **全量結果（`TCL 14`，32 檔，`flutter test integration_test/<檔> -d <序號>`）：** 通過 14，失敗 18。`manual_import_acceptance_test` 為人工驗收，未執行。

| 類別 | 檔案 | 說明 |
|---|---|---|
| E 通過 | `content_uri_acceptance_test`、`custom_font_rendering_test`、`epub_dual_page_test`、`foliate_cbz_test`、`foliate_kf8_test`、`foliate_margin_test`、`foliate_md_test`、`foliate_stream_nav_zone_test`、`foliate_txt_test`、`orientation_repagination_test`、`pdf_reader_view_test`、`smoke_test`、`wifi_transfer_screen_test`、`foliate_highlights_notes_test` | 14 檔 |
| D 過期介面／斷言 | `reader_footer_test`、`reading_position_test`、`volume_key_test`（找 `進度 67% ｜ 第 4/6 頁`、`第 1/` 等，頁尾現在只顯示 `4/6`）、`pdf_nav_zone_test`（找 `AppBar`）、`reader_header_footer_toggle_test`（找 `reader_appbar_chapter_title`，舊 AppBar 已刪）、`epub_highlights_notes_test`／`notes_bookmark_test`（`notes_sheet_*` key 不見）、`pdf_highlights_notes_test`（筆記按鈕逾時，尚未對照新 key）、`fxl_bookmarks_test`（`reader_fixed_layout_notes_button` 不見）、`markdown_export_test`（`TextButton` 變 `IconButton`） | 換 key 後往後多走幾步才暴露，已依分類表記錄，**未修** |
| 待判斷（過期或真行為改變） | `epub_toc_test`（點目錄後預期「第一節」消失，實際仍在）、`epub_pagination_test`（浮動進度文字未出現）、`foliate_single_column_test`（`Bad state: No element`）、`reader_screen_test`（6 通過、13 失敗，多為 10 秒條件逾時）、`epub_fxl_tap_zone_test`、`foliate_toc_footer_test`（預期 493 頁實際 490，疑與裝置字型有關）、`foliate_epub_reader_view_test`（預期錯誤文字「無法快取書籍檔案」實際「無法載入書籍」） | 需逐檔對照介面與行為，**未修** |
| B 既存 | `library_screen_test` | base 同機同樣失敗（找不到 `book_item_…`） |

- `database_closed` 例外多為測試失敗後 teardown 的連帶錯誤，不計為獨立失敗。
- **建議另立 Issue 17：** 把上表 D 類與待判斷類的 integration 測試遷移到 Epic 38 之後的介面（約 17 檔）。需要逐檔對照新介面與行為，部分須判斷「過期」還是「行為真的改變」，工作量大，不適合併入本 Issue。
- 診斷方法備忘：真機 integration 測試先用 `adb shell echo hi` 量延遲；超過 1 秒先 `adb kill-server` 再重試。

**2026-10-06 Issue 16 程式審查回應**（審查報告 `reviews/review-issue-16.md`：Critical 0、Important 2、Minor 2，結論 Ready to merge with fixes，皆已查證屬實並處理）

- I-1：`plans/plan-issue-16.md` 的 28 個 Step 全部勾選；Task 3 勾選並註明「因 H4 取消」；附錄 A 補「執行偏差」，如實記錄與原計畫不同之處（Task 1 的真解法是重啟 adb 服務、Task 4 改在 `TCL 14` 用 `flutter test`、base 對照只做 `library_screen_test`）。
- I-2：Issue 17 補上「換 key 後仍失敗的 7 個檔案為首要對象，須一次遷移完整」。
- M-1：`FakeDownloadableFontStore.forPlatform` 改用固定目錄名 `cache/fake-fonts-integration`，多次呼叫共用同一目錄，不再累積暫存子目錄；新增單元測試先紅後綠。
- M-2：補上 `systemTemp.parent` 與 `cache/` 的目錄結構假設註解。
- 驗證：相關單元測試 41 個通過、`flutter analyze` 乾淨；`TCL 14` 上 `foliate_highlights_notes_test` 仍通過（+2）。

**2026-10-06 Issue 16 已合併（PR #330）。** 真機 integration 通過數 0 → 14／32；其餘 18 檔的介面遷移移至 Issue 17。

**2026-10-07 Issue 17 實作完成與真機驗證結果**（分支 `epic-54/issue-17-integration-migrate`，worktree 內 Native 直接開發，無 subagent。計畫見 `plans/plan-issue-17.md`）

- 裝置：`TCL 14`（序號 `3CEF42ECD491687`，Android 15，WebView 154.0.8037.49）。以下結果僅宣稱此裝置通過。
- **全量結果（31 檔，`manual_import_acceptance_test` 為人工驗收未執行）：26 通過、5 失敗。** Issue 16 的 14 個通過檔案無回歸；本 Issue 的 18 個檔案中 13 個完全通過、5 個仍有失敗（見停止回報）：其中 3 個為部分通過（`reader_header_footer_toggle_test` 1/2、`reader_screen_test` 13/19、`foliate_epub_reader_view_test` 9/10），2 個為 0 通過（`epub_toc_test`、`epub_fxl_tap_zone_test`）。
- 完整 `flutter test`：3685 通過、1 跳過、0 失敗。`flutter analyze` 乾淨；`check_l10n_hardcoded_strings.js`、守衛與其單元測試皆 PASS。

| 檔案 | 結果 | 舊斷言 → 新斷言（強度） |
|---|---|---|
| `reader_footer_test`、`reading_position_test`、`volume_key_test` | 通過 | 頁尾文字改讀 `reader_chrome_page_info_text` 完全相等（提高）；音量鍵以前綴比對＋`reader_chrome_back_button` 存在判斷（等強） |
| `pdf_nav_zone_test` | 通過 | `AppBar`→`reader_chrome_back_button`（等強）；另有計畫漏列的舊頁碼斷言一併遷移 |
| `reader_header_footer_toggle_test` | 1/2 通過 | 章節名改讀收合後的 `reader_foliate_header_text`（等強，須先 `triggerZoneAction(menu)`）；靜態標題測試 2 個整組刪除（使用者決定，2026-10-07 確認：這兩個測試驗證舊 `AppBar` 的靜態標題「閱讀器」，Epic 38 之後需求已改變、用不到）；`showHeader=true` 的 static 不出現斷言刪除（計畫原定） |
| `epub_highlights_notes_test`、`pdf_highlights_notes_test`、`notes_bookmark_test`、`markdown_export_test`、`fxl_bookmarks_test` | 通過 | `TextButton`→`IconButton`、`reader_pdf_notes_button`／`reader_fixed_layout_*`→現行工具列 key（等強）；書籤分頁先切換；刪除鍵改查真實筆記 id（字串 id，非數字 1） |
| `foliate_single_column_test`、`epub_pagination_test` | 通過 | 欄數選項改讀 `Container` 背景色精確比對（等強，未選取為 `surface`）；開 Sheet 步驟刪除改走工具列頁尾（流程簡化，依據 `4ad5e4d8`）；浮動進度鍵在 `Container` 上，改讀後代 `Text` |
| `reader_screen_test` | 13/19 通過 | 設定按鈕→`reader_chrome_layout_button`；直排／滾動列搬到「呈現」分頁，先切分頁再以分頁內 `Scrollable` 捲動（等強） |
| `foliate_toc_footer_test` | 通過 | 頁數嚴格相等改為「與開書時相差不超過 5%」（程式審查 M-1 後；流式頁數為近似估計，翻頁收斂屬設計，TCL 14 實測 493→490 約 0.6%，三次一致）。原先曾放寬為「大於 0」，因斷言過弱、決定紀錄也查無依據而改回；容許值設 0 做突變驗證會失敗並印出實際漂移 |
| `foliate_epub_reader_view_test` | 9/10 通過 | 錯誤字串改「無法載入書籍」（`8db899cf` 起統一在地化訊息，等強） |
| `library_screen_test` | 通過 | 進入閱讀器改以 `reader_chrome_back_button` 判斷（等強）；書架啟動自動開書時先返回書架（epic-18 Issue 29） |

- **依判定規則停止回報（未改 `lib/`、未改斷言）：** `epub_toc_test`（開書即見第二章展開，兩節可見；目前路徑展開是設計，但此案例新舊行為皆不符預期，無法判定設計或缺陷）、`epub_fxl_tap_zone_test`（熱區分派成功但原生未翻頁，疑點按時長門檻，屬真機校準值，建議另立校準工單）、`foliate_epub_reader_view_test` 的 `isFixedLayout` 誤報（FXL 範例回報 false，疑產品缺陷）、`reader_header_footer_toggle_test` 的 `showFooter=false` 頁尾仍顯示（工具列頁尾不受該偏好控制）、`reader_screen_test` 的 FXL 版面按鈕（新工具列恆顯示）、智慧重開 `pdfCropRect`（pdfrx 內部 `maxScale >= minScale` 斷言崩潰，疑引擎問題）、手動裁切確認與 `manual→manual`（座標點確認鈕後設定面板未出現，裝置座標相關）。
- **過期 key 守衛（Task 1）：** 新增 `app/tool/check_integration_keys.js`（找出測試引用但 `lib/` 不存在的 `Key`，結束碼 0／1／2）與其單元測試，文件見 `app/tool/README.md`，已納入 `CLAUDE.md` 常用指令。對現況從 7 個 key、22 處收斂到 PASS。比對規則：範本只從 `Key(…)` 取（避開 `$_temp0` 類萬用字串癱瘓，計畫審查 C-1）、動態 key 與測試自建 key 不誤報。
- **執行偏差：** A/B 組 5 檔的基準即改後驗證（並行施工，改前數以計畫書為準）；`reader_screen_test` 全檔跑有 `database_closed` 級聯噪音，改以 `--plain-name` 隔離驗證（字型大小、手動裁切手勢隔離後通過，證實為噪音）。

**2026-10-07 Issue 17 程式審查回應**（審查報告 `reviews/review-issue-17.md`：Critical 0、Important 2、Minor 6，結論 With fixes；皆已對照分支內容查證屬實並處理）

- I-1：`issues.md` 新增 Issue 18，列出 5 個仍失敗檔案各自的原因與性質（疑產品缺陷、疑引擎問題、真機校準、需判定設計或缺陷）；`docs/epics.md` 備註改為「已完成（5 檔仍失敗，見 Issue 18）」。
- I-2：改寫全量結果統計句為「13 個全過、5 個仍有失敗（3 個部分通過、2 個 0 通過）」，三處數字一致；第 418 行的簡體字已改為繁體「與」。
- M-1：`foliate_toc_footer_test` 把「換頁後總頁數嚴格相等」放寬成「大於 0」過弱，且「使用者決定」的聲明在對話查無紀錄，依使用者指示改回更強的斷言：與開書時相差不超過 5%（實測 493→490 約 0.6%）。**突變驗證：** 容許值暫改為 0 時真機失敗並印出「開書 493、換頁後 490、漂移 0.6%」，證明斷言會咬人；還原後 `TCL 14` 通過（+3）。
- M-2：PDF 頁尾不受 `showFooter` 影響的現行語意沒有測試覆蓋，登記在 Issue 18 第 (3) 項。
- M-3：同 I-2，已修正。
- M-4：`reader_header_footer_toggle_test.dart` 的註解改為「showHeader 已明確持久化為 true；全域預設其實是 false」。
- M-5：`library_screen_test.dart` 第一個測試新增區塊少縮排 2 格，已補齊；現在整檔相對計畫基準只刪 1 行（`find.text('閱讀器')`），沒有縮排噪音。
- M-6：`app/tool/README.md`「已知限制」補兩點：`lib/` 內任何無 `$` 字串都算存在（刻意取捨）、測試端逐行比對（`Key(` 與字串分兩行會漏掉）。
- **使用者決定的確認（2026-10-07）：** 審查指出「使用者決定」類聲明無法查證。M-1 的聲明經確認不成立（已改回更強的斷言）；`reader_header_footer_toggle_test` 刪除 2 個靜態標題測試，使用者確認是自己的決定，原因是舊 `AppBar` 靜態標題的需求在 Epic 38 之後已改變、用不到。
- 驗證：`flutter analyze` 乾淨；守衛單元測試與守衛本身 PASS；`check_l10n_hardcoded_strings.js` 三項 PASS；`TCL 14` 上 `foliate_toc_footer_test` +3、`library_screen_test` +3、`reader_header_footer_toggle_test` 1/2（與先前一致）。未重跑完整 `flutter test`，上一次全套通過為 3685 通過、0 失敗（Issue 17 計畫最後一個 Task）。

**2026-10-07 Issue 17 已合併（PR #331）。** 真機 integration（`TCL 14`）通過數 14／32 → 26／31；其餘 5 檔的判定與校準移至 Issue 18。過期 key 守衛 `app/tool/check_integration_keys.js` 已納入 `CLAUDE.md` 常用指令。

**2026-10-07 Issue 18 實作完成與真機驗證結果**（分支 `epic-54/issue-18-integration-triage`，worktree 內 Native 直接開發，無 subagent；使用者明確要求後續嚴禁 subagent。計畫見 `plans/plan-issue-18.md`）

- 裝置：`TCL 14`（序號 `3CEF42ECD491687`，Android 15，WebView 154.0.8037.49）。以下結果僅宣稱此裝置通過。
- **5 檔全部通過**：`epub_toc_test`（0→1 通過）、`foliate_epub_reader_view_test`（9/10→10/10）、`reader_header_footer_toggle_test`（1/2→4/4，含 2 新增案例）、`reader_screen_test`（改寫前整檔 13/19→改寫後整檔 19/19）、`epub_fxl_tap_zone_test`（0→1 通過）。程式審查 I-2 後於 2026-10-07 清除 App 資料、在 `TCL 14` 單獨重跑 `reader_screen_test` 整檔，**19/19 全過**（先前記錄的字型大小、手勢暫停兩個「整檔級聯噪音」案例，在本次整檔順序下亦通過）；同日亦重跑本次審查回應異動到的 `reader_header_footer_toggle_test`（4/4）、`epub_toc_test`（1/1）、`epub_fxl_tap_zone_test`（1/1），皆通過。
- **判定與使用者決定**（2026-10-07 對話原話：`1. 丙, 2 乙, 3 OK 並補PDF 補同類案例, 5 甲`；Task 4：`4-a,c 皆為「是」, 4-b 甲`）：
  - (1) `epub_toc_test`（丙）：測試過期＋行為改變。真機證實開書 CFI 正確（第一章）但全書 fraction 回報 0.554（＝2×1763／6362，foliate 位元組估計含當前頁的 double-count），疊加頂層章節 progression 結構性 null，使第二章預設展開。測試改為狀態無關的收合→展開雙向驗證；強健性問題登記為 **Issue 19**。
  - (2) `foliate…isFixedLayout`（乙）：產品缺陷（迴歸）。`8e760653` 明文契約「呼叫端已確定流式書」→ epic-20 起前提失效、`15f2a6eb` 的寫死未跟著修；`widget.isFixedLayout==null`＋實 FXL 經非同步偵測空窗被蓋成 false。修 `lib/`（`main.js` 轉發 `view.isFixedLayout`，Dart 新增 `parseFoliateLayoutResolved` 純函式），測試維持原斷言。`widget.isFixedLayout` 三種情形的行為（程式審查 I-1，已有 widget 測試覆蓋，見 `test/screens/reader_screen_test.dart` 的「onLayoutResolved 回報 isFixedLayout=…」6 案例）：`true`＝強制 FXL 保護，原生回報 false 也不覆寫；`null`＝以原生回報值為準（修正目標）；`false`＝以原生回報值為準，此前永遠被蓋成 false，現在書實為 FXL 時 `_isFixedLayout` 會變 true，而 `_dispatchedIsFixedLayout` 仍為 false——兩者是不同概念（見 `reader_screen.dart` 約 434-437 註解），此分歧為預期行為。
  - (3) `header_footer`（OK＋PDF）：測試過期（失敗的是 EPUB，`issues.md` 原寫 PDF 已更正）。改寫為三條現行語意斷言＋`showFooter=true` 對照組＋PDF 同類案例（M-2）。
  - (4) `reader_screen_test`：(4-a) 測試過期（Epic 38 統一工具列），改斷言 FxlSettingsSheet；(4-b) 產品缺陷（甲）：智慧裁切後 `zoom=8.0`／pdfrx 原生 `min=8.0407`／`max=8.0`，delegate 透傳點火斷言，修箝位；(4-c) 測試過期（驅動已清退的原生 UI），改走手勢層畫框＋按 Key 確認，`manual→manual` 第二次矩形須不同（更強）。
  - (5) `tap_zone`（甲）：測試素材問題（單頁書）。新增 2 頁 FXL fixture，700ms 門檻不動。
- **斷言強度變化**：無放寬。toc（覆蓋面不同：原斷言保護「開書預設收合」，新測試改為收合→展開雙向切換、不再保護初始狀態，Issue 19 修復時須改回，測試內有 TODO(Issue 19)（已於 Issue 19 還原））、header（三條＋對照組＋PDF 新增）、tap_zone（維持真的換頁）、reader_screen（Fxl 驗存在且正確；manual→manual 由相等改為不相等，更強）。
- **突變驗證**：header 案例 2 在 `showFooter` 條件強制 true 時失敗並印出角落文字存在，對照組通過（整檔同跑的對照組失敗證實為連帶污染）；toc 改寫前後皆紅→綠（基準紅、改寫後綠）。
- **全量結果**：integration 38 檔（除人工驗收）34 通過；未通過 4 項皆非本 Issue 回歸——`book_metadata_channel_test`（乾淨樹同樣失敗，既存）、`sync_account/engine_test`（裝置對 `pbdev.jigong.org` 100% 丟包，環境）、`foliate_toc_footer_test`（整檔順序下 66% 漂移，隔離通過，flaky）。完整 `flutter test`：3692 通過、1 跳過、1 失敗（`pdf_reader_view_filters` 加粗 debouncer，乾淨樹同樣失敗，既存）。`flutter analyze` 乾淨；三支守衛全過。
- **執行偏差**：見計畫附錄 A。

**2026-10-07 Issue 18 程式審查回應**（審查報告 `reviews/review-code-issue-18.md`：Critical 0、Important 3、Minor 6，結論 With fixes，經使用者同意全部處理，細節見計畫附錄 C）

- I-1：補 6 個 `_handleFoliateLayoutResolved` widget 測試並做保護條件突變驗證；I-2：`TCL 14` 清資料後重跑 `reader_screen_test` 整檔 19/19，並重跑 `reader_header_footer_toggle_test`（4/4）、`epub_toc_test`（1/1）、`epub_fxl_tap_zone_test`（1/1）；I-3：`issues.md` 表格空行。
- M-1～M-5 已處理（M-2 審查建議的 `metrics.maxScale < zoom` 案例因建構子固定 `maxScale` 而無法建構，改註明不變式）；M-6（使用者對話原話）已由使用者確認無誤（2026-10-07）：`epic.md` Issue 18 結果段引用的「`1. 丙, 2 乙, 3 OK 並補PDF 補同類案例, 5 甲`」與「`4-a,c 皆為「是」, 4-b 甲`」屬實。

**2026-10-07 Issue 18 已合併（PR #333）。** 真機 integration（`TCL 14`）5 個遺留檔案全數通過；`onLayoutResolved` 回報真實 `isFixedLayout`、`PdfFitSizeDelegate` 箝位 `minScale<=maxScale` 兩項產品缺陷已修。開書當下目錄「目前章節」判定不可靠移至 Issue 19（待處理）。

**2026-10-07 Issue 19 實作完成與真機驗證結果**（分支 `epic-54/issue-19-toc-current-chapter`，worktree 內 Native 直接開發，無 subagent；使用者明確要求本案嚴禁 subagent。計畫見 `plans/plan-issue-19.md`）

- 根因：`TocNavigator.findCurrentPath` 只用全書 progression 比對：(a) 無頁內錨點的頂層章節 `TocEntry.progression` 結構性為 `null`，永遠不會被選中；(b) 開書初始全書 fraction 偏高（foliate 位元組估計含當前頁 double-count，TCL 14 實測 0.554＝2×1763／6362），使後面章節的子節被誤判為已通過。
- 演算法取捨與使用者決定（2026-10-07 對話原話：`B`；採計畫方案）：先比 spine index、同 spine 內才比 progression；同一 spine 內多錨點時，開書 progression 偏高可能多選到同章較後子節（不再跨章誤判），同章內精確須改 `main.js`（另案）。`findCurrentPath` 新增可選參數 `currentSpineIndex`，任一方缺 index 即退回舊規則；`ReaderScreen` 新增 `_currentEpubTocPath()` helper，四處呼叫共用；PDF 分支未動；`main.js`／vendor 未動。
- 真機（`TCL 14`，序號 `3CEF42ECD491687`，Android 15。以下結果僅宣稱此裝置通過）：`epub_toc_test` 未收緊版通過（+1）；收緊版通過（+1，含新增「跳轉第三章後再開目錄」斷言：第二章維持收合、第三章 `ListTile.selected`）；突變（註解 `currentSpineIndex` 傳入）失敗於「開書在第一章，第二章應預設收合」（+0 -1），還原後通過（+1）。單元 `toc_navigator_test` 15/15（含新 9 案）；突變（`nodeIndex > currentSpineIndex` 改 `return true`）4 案失敗，還原後全過。
- 斷言強度變化：收緊。`epub_toc_test` 移除 `TODO(Issue 19)` 與容錯分支，改回斷言開書第二章預設收合，並新增跳轉後判定斷言。
- 全量與回歸（2026-10-08，`TCL 14` 序號 `3CEF42ECD491687`；僅宣稱此裝置通過）：完整 `flutter test` 3709 通過、1 跳過、1 失敗（`pdf_reader_view_filters_test` 加粗 debouncer，Issue 18 已記錄為乾淨樹同樣失敗的既存問題，與本 Issue 無關）；integration 回歸 `notes_bookmark_test` +2、`reader_header_footer_toggle_test` +4 皆通過；`flutter analyze` 乾淨；`check_integration_keys.js`／`check_l10n_hardcoded_strings.js` 全 PASS。

**2026-10-08 Issue 19 程式審查回應**（審查報告 `reviews/review-code-issue-19.md`：Critical 0、Important 2、Minor 3）

- I-1：使用者原話更正為 `B`（epic.md 與計畫附錄 A 兩處，先前誤記為 `B 本計畫方案`）。
- I-2：補上上列完整 `flutter test` 與兩個 integration 檔的實測結果。
- M-1：`_currentEpubTocPath()` 註解折行並補空行。M-2：新增單元測試釘住「`currentProgression` 為 null 但 spine 已知」的現行語意（`toc_navigator_test` 現 16 案）。M-3：真機突變當時未保留日誌，無法補檔，維持文字記載（不追溯杜撰）。

**2026-10-08 Issue 19 已合併（PR #334）。** EPUB 目錄「目前章節」改以 spine index 優先判定（`TocNavigator.findCurrentPath` 新增 `currentSpineIndex`），開書當下不再誤展開後面章節；`epub_toc_test` 已改回斷言開書預設收合。同一 spine 內多錨點的精確度須改 `main.js`，已登記為 Issue 20，經審查修訂後由使用者決定推動方案 B（見下）。

**2026-10-08 Issue 20 決定推動（方案 B）。** 登記後經 `reviews/review-issue-20.md` 查證：原修復方向（回報章節內 fraction）不可行，改為轉發 foliate `relocate` 的 `tocItem` 可達 DOM 級精確。使用者在「方案 B（轉發 tocItem）」與「方案 C（維持 Issue 19 取捨、關閉工單）」之間，先回答 `C`，隨即更正為（2026-10-08 對話原話）：`打錯了，要選擇B才對，請修正`。最終決定為方案 B；曾短暫以 wontfix 關閉（commit `6cb1b767`），已還原為待處理。

**2026-10-08 Issue 12 實作完成**（分支 `worktree-epic-54-issue-12`〔Native `EnterWorktree` 建立，另有早先建立的 `.worktrees/epic-54-issue-12`／`epic-54/issue-12-sync-deps` 空分支未使用，發 PR 前擇一〕，Native 直接開發，未使用 subagent。計畫見 `plans/plan-issue-12.md`）

- 設計決定：使用者於 2026-10-08 對 Q1～Q3 回答「全 A」（原話記於計畫附錄 A）。`fullTextSearchSettingsRepository` 併入 `ReaderFeatureDependencies`（19 欄位）；`LibraryScreen`／`AdaptiveShellScaffold` 移除自己的 repository／importService／prefsManager，單一來源；`ElinkBookApp` 本 Issue 就改收 `readerFeatures`／`sync`。
- 內容：新增 `SyncDependencies`（5 欄位，non-null）；`LibrarySearchScreen` 改收 `dependencies`（`searchRepository` 單一來源）；`SettingsScaffold` 改收 `readerFeatures`＋`sync`（建構子少 11 欄位，移除字型／統計／全文檢索／同步入口的 null 判斷與 `!`）；`LibraryScreen` 改收 `dependencies`；`AdaptiveShellScaffold`、`ElinkBookApp` 改收兩組；`main()` 建構一次兩組，`syncCheckpointTrigger` 同一實例放進兩組。刪除 `readerFeatureDependenciesFromLegacy`、`LibraryReaderFeatureRepositories`、`LibrarySyncDependencies`、`completeLegacy*`。
- 驗證：範圍測試（14 檔）255 通過；完整 `flutter test` 3689 通過／1 略過／1 失敗，失敗為既存的 `pdf_reader_view_filters_test` bold overlay debouncer 案例（Issue 11 已在乾淨 `main` 確認，與本 Issue 無關）；`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js`／`check_integration_keys.js` PASS；殘留 grep（舊型別、`completeLegacy`）無輸出。
- 被刪測試與新恆真行為：見計畫附錄 B（共 25 案，皆為「依賴缺席型別上不可達」；降級提示測試全保留）。測試數算式見附錄 C。
- Review Focus 對應：1→`elinkbook_app_wiring_test` 斷言 `readerFeatures.syncCheckpointTrigger` same `sync.syncCheckpointTrigger`；2→主題切換後 `LibraryScreen.dependencies`／`SettingsScaffold` 組仍 same；3→`LibrarySearchScreen`→`ReaderScreen` 與書架→搜尋的 `dependencies` same；4→附錄 B；5→`settings_scaffold_test` 同步入口 same 測試。
- 真機 integration（2026-10-08，TCL 14〔`3CEF42ECD491687`，Android 15〕，分支 `f52fbc52`）：`smoke_test` 1／1 通過；`library_screen_test` 3／3 通過（流式 EPUB、FXL EPUB 皆由 `FoliateReaderView` 成功渲染）。結果只代表此裝置。計畫原預期 `library_screen_test` 在 base 上仍失敗（Issue 17 記錄），本次通過，未在 base 上重跑比對，不宣稱是本 Issue 修好。
- 計畫外：codemod 搭配 `dart format` 使被遷移的測試檔格式變動較大（無行為差異）；清除一次 worktree gitdir 內的 0 位元組 stale `index.lock`（無 git 程序運行）。
- ADR 0037 已同步：§1 補列 `fullTextSearchSettingsRepository` 與 `SyncDependencies` 的使用範圍；§6 轉換函式改為過去式。

**2026-10-08 Issue 13 實作完成**（分支 `epic-54-issue-13`〔`.worktrees/epic-54-issue-13`，基於 `main@b2b07178`〕，Native 直接開發，未使用 subagent。計畫見 `plans/plan-issue-13.md`）

- 設計決定：Task 0 Q1～Q3 使用者回答「依據建議」（即 Q1=A、Q2=A、Q3=A，原話見計畫附錄 A）。`AppDependencies` 只持有 `readerFeatures`／`sync`／`sources` 三組靜態依賴；`AppearanceDependencies` 為每次 `build()` 現組的快照；WiFi 傳書不留開關、tile 恆顯示；外觀組不加 `==`／`hashCode`。ADR 0037 §1／§3／§6 已按此同步。
- 內容：新增 `SourceDependencies`（12 欄位，non-null）／`AppearanceDependencies`（3 值＋3 callback）／`AppDependencies`（3 組容器）與三個 `fake_*_dependencies` 工廠；`SourcesHomeScreen`／`LibraryScreen`／`SettingsScaffold`／`AdaptiveShellScaffold`／`ElinkBookApp` 分兩段外殼樹原子切換（先來源組 Task 2，後外觀組 Task 3），最後 `AppDependencies` 收尾（Task 4）；`main()` 建構一次三組＋`syncCheckpointTrigger` 同一實例放進兩組。刪除 epic-26 Issue 7 的 4 個舊 bundle（`LibraryCloudAccountDependencies`、`LibraryRemoteLibraryDependencies`、`LibraryThemeDependencies`、`LibraryLocaleDependencies`）與 epic-44 的 `WifiTransferDependencies`，`library_screen_dependencies.dart` 整檔刪除。
- 驗證：同基準檔清單 318 全過（算式見計畫附錄 C）；完整 `flutter test` 3698 通過／1 略過／1 失敗，失敗為既存的 `pdf_reader_view_filters_test` bold overlay debouncer 案例（Issue 12 已在乾淨 `main` 確認，與本 Issue 無關，改動範圍未碰 `reader/`）；`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js`／`check_integration_keys.js` PASS；殘留 grep（5 個舊型別名，含註解）無輸出。
- 被刪測試與新恆真行為：見計畫附錄 B（Task 2 刪 6 案＋新增 5 案；Task 3 整檔刪 2 案＋新增 3 案快照測試；Task 4 新增 4 案、無刪除）。測試數算式見附錄 C。
- Review Focus 對應：1→來源頁開遠端／WiFi／GDrive／OneDrive 的 `same(...)` 欄位對帳 4 案；2→切換主題後三畫面同一新快照、其餘三組 same；3→E-Ink 三處一致＋遠端書庫貫穿、切語言後 State 保留；4→附錄 B；5→缺 `remoteDownloadUrl` 書本仍提示且不呼叫 `createOpdsClient`。
- 真機 integration（TCL 14〔`3CEF42ECD491687`〕）：`library_screen_test` 3／3、`smoke_test` 1／1、`wifi_transfer_screen_test` 8／8 通過。結果只代表此裝置。真機手動確認（來源頁四入口與下載佇列、主題／E-Ink／語言三頁同步、設定頁雲端帳號與同步入口、書架重新下載與開書、三支 integration）已由使用者於 2026-10-08 完成，回報全數通過（使用者口頭回報，未附日誌；裝置以使用者實測為準）。
- 與 `issues.md` 第 13 列的兩處落差：(1)「6 個舊 bundle」實際只剩 4 個（Issue 12 已刪 `LibraryReaderFeatureRepositories`、`LibrarySyncDependencies`）；(2)「`buildReaderScreen` 的暫時組裝」Issue 12 已整段刪除，無暫時組裝可移除。合併後回寫 `issues.md`／`docs/epics.md` 時一併更正。
- 格式雜訊（程式審查 M-1）：`lib/` 內三處與本 Issue 無關的 `dart format` 重排（`settings_scaffold.dart` 三個 Key 折行、`main.dart` 建構子初始化清單、`library_screen.dart` SnackBar 折行）已還原為基線寫法（對 `main` 比對無差異）；測試檔（`library_screen_test`、`sources_home_screen_test`、`settings_scaffold_test` 等）因 codemod 搭配 `dart format` 含大量無行為差異的重排，未逐檔還原，沿用 Issue 12 先例於此註明。
- 驗證數字的來源（程式審查 M-3）：獨立審查重跑 Task 3 範圍 14 組測試 418 通過、analyze 與守衛腳本 PASS；完整 `flutter test` 3698 與 TCL 14 真機結果為實作者記錄，審查者未重現；真機手動確認已由使用者回報全數通過（2026-10-08）。
- 孤兒 ARB 鍵清理：刪除 `readerSaveAsPresetUnavailableMessage`（Issue 11 M-5）與本次新孤兒 `sourcesHomeCloudNotLinkedSubtitle`、`sourcesHomeRemoteLibraryNotConfiguredSubtitle`（Dart 使用端皆已消失，僅剩 ARB）；`flutter gen-l10n` 同步 3 個產生檔；`test/l10n` 71 全過。

**2026-10-08 Issue 14 實作完成**（分支 `epic-54-issue-14`〔`.worktrees/epic-54-issue-14`，基於 `main@6f3d6656`〕，Native 直接開發，未使用 subagent。計畫見 `plans/plan-issue-14.md`）

- 設計決定：Task 0 Q1＝A（不為 `main()` 寫永久測試，只做一次性靜態確認，結果見下）、Q2＝A（擴充 `elinkbook_app_wiring_test.dart`，檔尾新增 group；原話見計畫附錄 A）。`lib/` 零差異（純測試工作）。
- 內容：`app/test/elinkbook_app_wiring_test.dart` 新增「開書路徑身分守衛」group（7 案）：P1 書架點書→閱讀器、P2 書架→全庫搜尋、E-Ink 切換後再開書、P3a 全庫搜尋點書名結果→閱讀器、P3b 點內容片段→閱讀器（含 `initialJumpTarget` 非空斷言）、P4＋P5 全庫搜尋→查看全部→單書搜尋→點片段→閱讀器、P6 閱讀器→單書搜尋（fromReader）。共用起手式 `_pumpWiringApp`／`_openLibraryContentSearch`／`_expectReaderWired`／`_disposeWiringApp`。既有測試實測為 6 案（計畫撰寫時記為 5），全檔共 13 案。`_pumpWiringApp` 明確關閉 Issue 29 啟動自動開書（`openLastBookOnLaunch: false`，比照 `library_screen_test.dart` 共用 fixture），否則啟動即自動推入閱讀器、書架按鍵不可點。
- 變異驗證 M1～M9（暫時改壞 `lib/` 再還原，不 commit）：M1（路由整組複本）→ P1、E-Ink 切換、P3a、P3b、P4＋P5、P6 變紅；M2（書架→全庫搜尋整組複本）→ P2、P3a、P3b、P4＋P5；M3（全庫搜尋→單書搜尋整組複本）→ P4＋P5；M4（閱讀器→單書搜尋整組複本）→ P6；M5（路由 E-Ink 鎖 false）→ P1、E-Ink 切換、P3a、P3b、P4＋P5、P6；M6（書架→全庫搜尋 E-Ink 鎖 false）→ P2、P3a、P3b、P4＋P5；M7（全庫搜尋→單書搜尋 E-Ink 鎖 false）→ P4＋P5；M8（閱讀器→單書搜尋 E-Ink 鎖 false）→ P6；M9（`sync` 改用不共用的新 trigger）→ 既有測試 2（三組原樣）＋ P1、E-Ink 切換、P3a、P3b、P4＋P5、P6，P2 維持通過。每列「實際」皆涵蓋「預期」（M1／M5 另含 P6、M9 另含既有測試 2，皆為預期的超集，詳見計畫變異表）。還原後 `git diff main --stat -- lib` 無輸出，單檔 13 全過。
- `main()` 靜態確認輸出：`git grep -c "SyncCheckpointTrigger(" -- lib/main.dart` → `lib/main.dart:1`；`syncCheckpointTrigger: syncCheckpointTrigger` 2 筆（`:333` 在 `ReaderFeatureDependencies(` 建構內、`:341` 在 `SyncDependencies(` 建構內）；`AppDependencies(` 1 筆（`:360`，三組皆區域變數傳入）。
- ADR 0037「後果」最後一條已追加 Issue 14 落地說明行。
- 程式審查補驗（`reviews/review-code-issue-14.md`，0 Critical／0 Important／3 Minor）：獨立重現 M1～M9 全部變異，變紅測試皆涵蓋預期（與上列一致）；完整 `flutter test` 3705 通過／1 略過／1 失敗，失敗為既存的 `pdf_reader_view_filters_test` debouncer 案例（單跑重現，`lib/` 零差異故非本 Issue 造成）。

**2026-10-08 Issue 21 實作（缺陷，測試過期；分支 `epic-54-issue-21`，直接 TDD，不寫 plan）**

- 症狀：`flutter test` 長期有 1 個失敗——`pdf_reader_view_filters_test` 的「同時有多頁需要加粗運算時，各頁互不取消」，`Expected: >= 2 / Actual: 1`。Issue 12 起被記為「既存失敗」，Issue 14 完整測試時再度出現。
- 診斷：單跑穩定重現（4/4 紅）。二分：`1e20dda6^`（epic-59 之前）綠、`1e20dda6`（`PdfOverlayJobQueue`，`maxConcurrent = 1`）起紅，該提交只新增 `pdf_overlay_job_queue_test.dart`，未同步調整本案例。等待輪數掃描：40／42／44 全紅、46 偶爾綠、48～120 全綠。結論：覆蓋圖計算序列化後第 2 頁較晚完成，測試的「40 輪內完成」時間假設過期；測試要防的「後登記的頁面取消先前頁面」在佇列下仍成立（同頁去重、頁與頁互不取消），非產品缺陷。
- 修正：只改 `test/reader/pdf_reader_view_filters_test.dart` 該案例——`maxIterations` 40→120（約 2.5 倍餘裕）、測試名稱與 `reason` 改寫為佇列語意（不再談 debouncer）。`lib/` 零差異。
- 驗證：目標案例連跑 3 次全綠、整檔 16 案全過、`flutter analyze` 乾淨、l10n 守衛 PASS。

**2026-10-08 Issue 10 實作完成**（分支 `epic-54-issue-10`〔`.worktrees/epic-54-issue-10`〕，Native 直接開發，未使用 subagent。計畫見 `plans/plan-issue-10.md`，設計決定 Task 0 Q1＝A〔不做 Sentinel，只做守衛〕、Q2＝A〔納入 PDF 面板修復〕；原話見計畫附錄 A）

- 內容：新增 `app/test/support/full_book_reader_prefs.dart`（33 欄位全填的 `fullBookReaderPrefsSeed`，值皆取非面板預設＋可被滑桿換算無損來回；`expectPrefsPreserved` 以 `toMap()` 逐欄位比對並在訊息列出欄位名，`except` 先驗為 `toMap()` 鍵）。守衛範圍 S1～S4 共 12 案：種子自檢 3（全非 null／round-trip／`copyWith()` 等價）、書架版面覆寫 1、FxlSettingsSheet 3、PdfSettingsSheet 3、ReaderSettingsSheet 2（以 `reflowableEpubFields()` 為基準，12 欄位依設計為 null）。Task 5 守衛初寫時把 `show_footer` 誤放在「呈現」分頁（實際在「邊界」分頁），已按檔內既有測試慣例修正，註解記於測試內。
- PDF 面板缺陷與修法（S3）：守衛先紅，證實 20 個欄位被清成 null（與計畫預測一致，詳見計畫附錄 C）。`_notifyChanged()` 改為 `widget.prefs.copyWith(...)`（面板送出的 12 欄位全是非 null，不需清空語意；`pdfCropRect` 不傳即保留），類別文件註解同步更新。`lib/` diff 僅此一檔。
- 變異驗證 M1～M6（暫改後全數 `git checkout` 還原，不 commit）：M1（刪書架 `fullscreen` 帶回）→ `fullscreen：預期 1，實際 null`；M2（刪書架 `columnSize`）→ `column_size`；M3（刪 FXL `columnSize`）→ 3 守衛全紅；M4（PDF 還原舊 13 欄位寫法）→ 3 守衛全紅 20 欄位；M5（刪 `_currentDraft` 的 `textConversionOverride`）→ `text_conversion_override`；M6（刪種子 `textConversionOverride`）→ 種子自檢紅。還原後全綠，`git status` 乾淨。
- 完整 `flutter test`：程式審查前第一次 3716 通過／1 略過／2 失敗；審查後在最終實作 commit 上重跑為 **3717 通過／1 略過／1 失敗**，唯一失敗為 `download_queue_controller_test`「偵測到重複且 onDuplicateConfirm 回傳 false…」（`checkingDuplicate` 未進到 `duplicateSkipped`）。該檔單跑連續 3 次 14/14 全過，且本 Issue 未碰下載相關程式；此即上文（約第 188 行）已記錄的「整套並行時偶發失敗：固定輪數 `pumpEventQueue()`」，**未**確認乾淨 `main` 是否同樣重現。第一次的另一失敗（`pdf_reader_view_filters_test` 覆蓋層案例，同 Issue 21 家族的計時抖動）重跑未再出現。`flutter analyze` 乾淨，l10n 守衛三行 PASS。

**2026-10-08 PR 合併（Issue 10）**

- PR #339（`epic-54-issue-10` → `main`）已合併，合併 commit `fe765e77`。程式審查 0 Critical／1 Important（文件措辭，已修）／3 Minor。全套 `flutter test` 3717 通過／1 略過／1 失敗（`download_queue_controller_test` 整套並行偶發，單跑通過，見上）。
- Epic 54 剩 Issue 20（EPUB 目錄同一 spine 多錨點，方案 B）待撰寫 Plan；Epic 暫不歸檔。

**2026-10-09 Issue 20 實作完成與真機驗證結果**（分支 `epic-54/issue-20-toc-tocitem-forward`，計畫 `plans/plan-issue-20.md`，方案 B 的使用者原話見該計畫附錄 A）

- **機制**：`main.js buildTocEntry` 輸出 `tocId: item.id ?? null`；`onLocatorChanged` 第 2 參數 `position`（FXL／流式兩分支）帶 `tocItemId: e.detail.tocItem?.id ?? null`。Dart 端 `TocEntry.tocId`／`EpubPositionInfo.tocItemId`／`parseLocatorChanged` 接收；`TocNavigator.findCurrentPath` 新增 `currentTocItemId`，樹中命中即回傳祖先路徑，查無退回 Issue 19 的 spine index 規則。`_currentEpubTocPath()` 一處傳入。第 1 參數 `locatorJson` 與釘定 vendor 檔皆未改動（`git diff` 對 `chapterIndex, fraction` 零命中）。
- **單元測試**：`toc_navigator_test` 25 案（新增 9 案，含 id 為 0、前章節點、查無 id、缺 tocId 舊資料）；codec／entry／position info 共 85 案。突變：把 id 0 排除 → 1 案失敗；整段停用 id 分支 → 5 案失敗。
- **真機（TCL 14，Android 15）**：新增單 spine 三錨點 fixture `sample_single_spine_multi_anchor.epub` 與 `epub_toc_test` 第二個 `testWidgets`，`epub_toc_test` +2 通過；`notes_bookmark_test`（+2）、`reader_header_footer_toggle_test`（+4）無回歸。**未對該裝置執行 `pm clear`**（破壞性、未經使用者確認，且測試不依賴乾淨狀態）。
- **整合測試咬力（如實記錄）**：暫時移除 `currentTocItemId` 傳入後在 TCL 14 重跑，新 `testWidgets` **仍通過**——此 fixture 與裝置上舊規則剛好答對，故整合測試只證明端到端接線（JS 的 id 確實傳到 Dart 且路徑正確、無例外），**不證明精確度改善**；精確度改善由 `toc_navigator_test` 的「progression 偏高仍選第一節」等案證明。
- **完整 `flutter test`**：3735 通過／1 略過／0 失敗（Issue 21 後首度維持全綠）。
