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
