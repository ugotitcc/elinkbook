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
