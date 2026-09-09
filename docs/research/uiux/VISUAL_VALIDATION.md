# Visual Validation

> **環境限制（誠實聲明，不誇大驗證程度）**：本機沒有連接 Android 裝置/模擬器（`flutter devices` 僅列出 Windows／Chrome／Edge）。嘗試 `flutter run -d chrome` 後確認此專案**未設定 Web 平台支援**（`flutter create .` 提示訊息），啟動後 `path_provider`／`sqflite` 等原生外掛在 Web 上直接丟 `MissingPluginException`，無法跑出真正可用的畫面可供截圖——已終止該次嘗試，不強行在不支援的平台上湊出截圖。
> 因此本輪驗證**不是**依 Reference 截圖做像素級疊圖比對，而是：(1) 逐一元件對照 Reference 截圖與程式碼實際渲染邏輯做人工核對，(2) 針對每個修正新增或更新對應的 `flutter test` 斷言（顏色/樣式直接斷言，非僅存在性檢查），(3) `flutter analyze` 全綠、完整 `flutter test`（2146 個測試）全數通過。PASS/PARTIAL/FAIL 判定依據見各項「驗證依據」。若要做到真正的截圖疊圖比對，需要接上 Android 裝置或幫這個 Android-only 專案另外補上 Web 平台支援（`path_provider`/`sqflite` 的 Web 實作），兩者都超出本輪範圍，需要您決定是否要投入。

---

## Screen

Library（書架）

## Reference

`docs/research/uiux/reference/書架_1.png`

## Flutter Screenshot

無（見上方環境限制聲明）

## Result

### Layout
PARTIAL — AppBar／搜尋列／PagingBar 版面結構未變動，維持既有正確版面；書封/分類格邊框、分類角標已補上（見 Components）。網格 padding／gap 是否與 Reference 的 12/16px 完全一致本輪未逐行核對。

### Typography
PARTIAL — AppBar 標題字重已改為 `FontWeight.w900`（`_buildAppBarTheme`），對齊 Reference 的 `font-black`；書名/其餘字級本輪未逐一核對。

### Color
PASS — `DESIGN_TOKENS.md` 先前已驗證 100% 對齊 `DESIGN.md`；本輪新增修正的 `_GroupGridTile` 角標（`primary`/`onPrimary`）、書封邊框（`outline`）皆使用既有 `ColorScheme` 角色，無寫死色值。

### Spacing
PARTIAL — 未逐行核對網格 gap／卡片內距與 Reference 是否完全一致。

### Components
PASS（有測試佐證）——
- 書封／封面佔位符邊框：`book_cover.dart` 非 E-Ink 主題已補 `outline` 邊框。驗證依據：`flutter test test/library/widgets/book_cover_test.dart` 全數通過。
- 分類拼貼格外框＋「分類」角標：`library_screen.dart` `_GroupGridTile` 已補上。驗證依據：`flutter test test/screens/library_screen_test.dart`（156 項全過，含既有的分類拼貼格系列測試，證明新增的外層 `DecoratedBox`／角標未破壞既有版面斷言）；**本輪未新增角標本身的存在性斷言**，建議下一輪補一則 `find.text('分類')` 測試。
- AppBar 底部分隔線／無陰影：`app_theme_data.dart` `_buildAppBarTheme()` 全域生效。無專屬測試斷言，PARTIAL。

### Responsive
`[UNKNOWN]` — 未涵蓋，Reference 本身也只有單一手機尺寸可比對（見 `SCREEN_SPEC.md`）。

## Remaining Differences
- 網格內距/間距未逐值核對。
- 「分類」角標存在性尚無自動化測試覆蓋。
- PagingBar／搜尋列本輪未再檢視（先前分析標記為 `[UNKNOWN]`，仍未處理）。

---

## Screen

LayoutSettings（版面設定：文字／邊界／呈現／預設集）

## Reference

`docs/research/uiux/reference/版面設定_文字_1.png`、`_文字_2.png`、`_邊界_1.png`、`_邊界_2.png`、`_呈現_1.png`、`_呈現_2.png`、`_預設集.png`

## Flutter Screenshot

無（見上方環境限制聲明）

## Result

### Layout
PASS — 分頁籤結構（文字/邊界/呈現/預設集）與 Reference 一致，未變動。

### Typography
PARTIAL — `EBStepper` 數值文字已改為 `18px / FontWeight.w900`，貼近 Reference 大字級粗體；`-`/`+` 圖示字級未特別調整。

### Color
PASS（有測試佐證）——`ReaderOptionTile` 選中態由 `primaryContainer` 改為 `primary`＋`onPrimary`，對齊 Reference「主色實心填滿＋白字」。驗證依據：`flutter test test/screens/fxl_settings_sheet_test.dart test/screens/pdf_settings_sheet_test.dart test/screens/reader_settings_sheet_test.dart`（141 項全過，含本輪更新的 3 則精確色值斷言：`fxl_settings_sheet_test.dart` 2 處、`pdf_settings_sheet_test.dart` 1 處）。

### Spacing
`[UNKNOWN]` — 未逐值核對。

### Components
PASS（有測試佐證，`EBStepper`）／**決策保留不動**（`Slider`）——
- `EBStepper`（字級/行距/段落間距/字重/字距/上下左右邊界）：已補上邊框＋8dp 圓角容器（`_StepperButton`），對齊 Reference。驗證依據：`flutter test test/screens/widgets/eb_stepper_test.dart` 全數通過（原有測試未斷言邊框存在性，僅驗證數值邏輯不受影響；視覺本身依人工核對程式碼確認）。
- 非 E-Ink 主題的 `Slider`：**依您明確指示維持現況，不改**（`reader_settings_sheet.dart` 非 E-Ink 仍用 `Slider`，E-Ink 用 `EBStepper`，`DESIGN.md` §18.3 既有決策）。此項與 Reference 的差異**刻意保留**，不計入待修清單。
- `Switch`（顯示頁首/頁尾等）：ON 態已改為 `primary`／`onPrimary`。驗證依據：`flutter test test/theme/app_theme_data_test.dart`（新增／更新 4 則測試，含 E-Ink 主題「黑底白點」對比度驗證）。

### Responsive
`[UNKNOWN]`。

## Remaining Differences
- `EBStepper` 邊框/圓角本輪無專屬測試斷言其視覺屬性（僅有既有數值邏輯測試持續通過，證明未破壞行為）。
- 步進器數值文字以外的其餘文字字級（如「使用全域預設」次要說明）未核對。

---

## Screen

Settings（設定）

## Reference

`docs/research/uiux/reference/設定_1.png`、`設定_2.png`

## Flutter Screenshot

無（見上方環境限制聲明）

## Result

### Layout
PASS（有測試佐證）——`settings_scaffold.dart` 每個項目改由 `_SettingsCard`（內部即 `Card`，套用全域 `CardTheme`：無陰影＋`outline` 邊框＋8dp 圓角）包裹，取代原本連續 `ListTile`＋`Divider` 清單；分區間距改由 `EBSectionHeader` 既有頂部留白承擔，畫面上不再出現 `Divider`。驗證依據：`flutter test test/screens/settings_scaffold_test.dart`（24 項全過，含本輪重寫的結構測試——`find.byType(Divider)` 為 `findsNothing`，8 個已知項目 Key 皆能找到 `Card` 祖先）。

### Typography
PASS — 未變動，沿用既有 `EBSectionHeader`／`ListTile` 文字樣式，本輪未發現額外差異。

### Color
PASS — `Card` 顏色來自全域 `CardTheme`（`colorScheme.surface`＋`outline` 邊框），無寫死色值。

### Spacing
PARTIAL — 卡片間距（`margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4)`）依既有 `EBSpace`／原型間距慣例決定，未逐像素比對 Reference 實際間距值。

### Components
PASS（有測試佐證）——見上方 Layout。`clipBehavior: Clip.antiAlias` 確保 `ListTile`/`SwitchListTile` 的按壓水波紋不溢出卡片圓角邊界（人工核對程式碼確認，無專屬測試斷言此點）。

### Responsive
`[UNKNOWN]`。

## Remaining Differences
- 卡片間距未逐像素核對。
- 佈景圓點選擇器（`_buildThemeDot`）本輪未變動，是否需要視覺調整未重新核對。

---

## Screen

LayoutSettings 補件：欄位列邊框（三個版面設定 Bottom Sheet）

## Result

上一輪只修了 `ReaderOptionTile`（三態選項按鈕選中色）與 `EBStepper`（`-`/`+` 按鈕本身的邊框），**遺漏了整列的邊框卡片**（Reference 每個「字級」「行距」「欄位大小」等欄位是一整個有邊框的卡片，不是只有 `-`/`+` 按鈕有框）——這是您這次回報「版面設定並沒有更新到」的根本原因，本輪已補上：

### Components
PASS（有測試佐證）——`reader_settings_sheet.dart`／`fxl_settings_sheet.dart`／`pdf_settings_sheet.dart` 的 `_buildSliderRow`／`_buildFontFamilyDropdown`／各 `SwitchListTile`／`_buildColumnModeRow` 內的「欄位大小」子區塊，皆已改用新共用元件 `EBFieldCard` 包裹。核對 Reference 後確認**只有「欄位大小」這類數值列有邊框卡片，「換頁模式／欄數／書寫方向／文字對齊／螢幕方向鎖定」這幾組三態選項按鈕群組本身沒有外層卡片**（各按鈕自己已有邊框），故未對它們加卡片，避免過度還原。`_buildPresetSlot`（預設集卡片）補上 `outline` 邊框。驗證依據：`flutter test test/screens/reader_settings_sheet_test.dart test/screens/fxl_settings_sheet_test.dart test/screens/pdf_settings_sheet_test.dart test/screens/settings_scaffold_test.dart`（334 項全過）。

副作用修正：`pdf_settings_sheet.dart` 濾鏡分頁固定 400px 高度的 Bottom Sheet 在加了卡片後 3 個數值列會溢位（RenderFlex overflowed by 40 pixels），已比照顯示分頁既有的 `SingleChildScrollView` 做法補上捲動；對應測試補了 `ensureVisible()` 呼叫。

---

## Screen

Source（來源）

## Reference

`docs/research/uiux/reference/來源.png`

## Flutter Screenshot

無（見上方環境限制聲明）

## Result

### Components
PASS（有測試佐證）——`sources_home_screen.dart` 的「選擇檔案」「選擇資料夾」「Google Drive」「OneDrive」「遠端書庫（OPDS）」五個 `ListTile` 皆已用 `EBFieldCard` 包裹；分區標題改用既有 `EBSectionHeader`（原本是裸 `Padding`+粗體 `Text`，與設定畫面的分區標題樣式不一致，現已統一）。驗證依據：`flutter test test/screens/sources_home_screen_test.dart`（7 項全過）。

### Remaining Differences
- Reference「選擇檔案」／「選擇資料夾」是並排的兩個方形按鈕（icon 在上、文字在下），本輪維持原本 `ListTile`（icon 在左、文字在右）的橫列格式，只加邊框卡片，未重排版面——版面重排風險/工作量較高，且非「缺邊框」這個核心問題，本輪判斷為超出範圍，如需要請另外指示。

---

## Screen

Source（來源）常駐下載佇列（架構變更，非純視覺）

## Reference

`docs/research/uiux/reference/來源.png`

## Result

依您明確指示（「建立共享狀態，改成常駐行列」），完成架構變更：

### 新增
- `CloudDownloadQueueController`（`app/lib/cloud_import/cloud_download_queue_controller.dart`）：純 Dart `ChangeNotifier`，比照 `main.dart` 既有 `SyncEngine.onReadingPositionConflict` 的橋接原則——不依賴 Flutter widget 樹，重複匯入確認對話框透過 `navigatorKey.currentContext` 橋接，使用者下載途中離開畫面也能正常彈出。下載迴圈（含 Layer 2 指紋比對、`onProgress` 進度回報、取消、重試）從原本 `CloudDownloadQueueDialog` 的 widget State 搬過來。
- `CloudDownloadQueuePanel`（`app/lib/screens/widgets/cloud_download_queue_panel.dart`）：常駐於「來源」畫面底部，訂閱控制器即時重繪，沒有項目時整個區塊（含分區標題）不渲染；每個項目用確定式 `LinearProgressIndicator`（`DESIGN.md` §16.2 要求，不用連續旋轉指示器）。

### 修改
- `CloudBrowserScreen`：確認下載後改為 `controller.enqueue(...)`＋顯示提示 Snackbar，不再 `showDialog()` 跳出模態視窗，使用者可立即繼續瀏覽或離開畫面。
- `main.dart`／`AdaptiveShellScaffold`／`SourcesHomeScreen`：貫穿新增的 `downloadQueueController`；`downloadQueueController == null` 時 Google Drive／OneDrive 入口一併停用（比照既有「相依不齊全就停用」慣例）。

### 移除
- `CloudDownloadQueueDialog`（`cloud_download_queue_dialog.dart`）與其測試——功能已被 `CloudDownloadQueueController` 取代，不留舊檔案。`showCloudDuplicateConfirmDialog` 移到獨立檔案 `cloud_duplicate_confirm_dialog.dart`（Layer 1／Layer 2 共用）。

### Remaining Differences（本輪已解決，見下一節「OPDS／Calibre 併入」）
- ~~OPDS／Calibre 遠端書庫（`remote_catalog_screen.dart`）的下載佇列仍是獨立的模態對話框，未併入這個常駐佇列~~ → 已於下一節併入同一份共用佇列。
- 佇列項目目前不會自動消失，`done`／`duplicateSkipped` 狀態的項目提供了個別的「×」按鈕手動移除（`dismiss()`），沒有做「清除全部」或自動淡出，Reference 截圖沒有示範這塊，避免自行發明。

### Components
PASS（有測試佐證，注意：本節列出的 `CloudDownloadQueueController`／`CloudDownloadQueuePanel`／其測試檔已於下一節「OPDS／Calibre 併入」重構為泛化的 `DownloadQueueController`／`DownloadQueuePanel`，檔案已不存在，下方列表保留作為當時的驗證紀錄）：
- `flutter test test/cloud_import/cloud_download_queue_controller_test.dart`（9 項全過：完成/失敗重試/取消/重複比對三種情境/序列處理/dismiss/notifyListeners）
- `flutter test test/screens/cloud_browser_screen_test.dart`（24 項全過，改為驗證 Snackbar 而非模態對話框）
- `flutter test test/screens/sources_home_screen_test.dart`（10 項全過，含 3 則新增：`downloadQueueController` 為 null 時停用雲端入口、佇列空/有項目時區塊顯示與否、項目即時反映狀態變化）

---

## Screen

Source（來源）常駐下載佇列 — OPDS／Calibre 併入（架構泛化，非純視覺）

## Reference

`docs/research/uiux/reference/來源.png`

## Result

延續上一節，將 Cloud（Google Drive／OneDrive）專屬的 `CloudDownloadQueueController` 泛化為與 Provider 無關的共用佇列，讓 OPDS／Calibre 遠端書庫（`remote_catalog_screen.dart`）也改用同一份常駐佇列，不再各自維護一份模態對話框：

### 新增
- `DownloadQueueController`（`app/lib/downloads/download_queue_controller.dart`）：取代原本 Cloud 專屬的 `CloudDownloadQueueController`，內部改依賴新的抽象介面 `QueuedDownloadJob`（`id`／`name`／`download()`／`cancel()`／`isCancelled`／`computeFingerprint()`／`hasDuplicate()`／`promote()`／`import()`），控制器本身完全不認得 Cloud 或 OPDS 的具體型別，只負責排程（序列、非平行）／進度／重複確認橋接（`onDuplicateConfirm`，比照既有 `navigatorKey` 橋接原則）／失敗重試／取消。
- `CloudDownloadJob`（`app/lib/cloud_import/cloud_download_job.dart`）與 `RemoteDownloadJob`（`app/lib/remote/remote_download_job.dart`）：`QueuedDownloadJob` 的兩個具體實作，分別包裝原本 `CloudDownloadQueueController`／`RemoteCatalogScreen` 私有 `_DownloadQueueDialog` 各自的下載/指紋/去重/搬移/匯入邏輯。
- `DownloadQueuePanel`（`app/lib/screens/widgets/download_queue_panel.dart`，取代 `CloudDownloadQueuePanel`）：型別泛化，UI／Key 命名不變。

### 修改
- `RemoteServerListScreen`／`RemoteCatalogScreen`：新增必要參數 `downloadQueueController`，`_startDownload()` 改為組出 `RemoteDownloadJob` 清單後呼叫 `controller.enqueueJobs(...)`＋顯示提示 Snackbar（`remote_catalog_queued_snackbar`），不再 `showDialog()` 跳出模態視窗。
- `sources_home_screen.dart`：`_openRemoteLibrary()` 把同一個 `downloadQueueController` 往下傳給 `RemoteServerListScreen`，三種來源（Google Drive／OneDrive／OPDS）共用同一份佇列面板。
- 下載完成即匯入的時機統一為「逐項完成立即匯入」（比照 Cloud 原本行為）——OPDS 舊版是整批下載完才一次呼叫 `importFiles()`，泛化後佇列沒有固定的「這批結束」邊界，因此統一為逐項匯入，此為刻意的行為調整，非疏漏。

### 移除
- `CloudDownloadQueueController`（`app/lib/cloud_import/cloud_download_queue_controller.dart`）與其測試、`CloudDownloadQueuePanel`（`app/lib/screens/widgets/cloud_download_queue_panel.dart`）——功能已被泛化版取代。
- `RemoteCatalogScreen` 私有的 `_DownloadQueueDialog`／`_DownloadQueueDialogState`（含 `download_queue_dialog`／`download_queue_item_*`／`download_queue_done_button` 等 Key）——Layer 1（選檔前置，`remote_catalog_duplicate_dialog*`）維持原樣不動；Layer 2（下載後指紋比對）改由共用 `DownloadQueueController.onDuplicateConfirm` 觸發，實際彈窗改為與 Cloud 共用的 `showCloudDuplicateConfirmDialog`（Key 變為 `cloud_duplicate_dialog*`）。

### Components
PASS（有測試佐證）——驗證依據：
- `flutter test test/downloads/download_queue_controller_test.dart`（新增，9 項全過：完成/序列非平行/重複 id 略過/重複比對兩種選擇/失敗/取消/重試/dismiss，以最小假 `QueuedDownloadJob` 實作獨立驗證控制器本身的狀態機，不依賴任何具體 Provider）
- `flutter test test/screens/remote_catalog_screen_test.dart`（61 項全過，下載/取消/重試/Layer 2 重複比對系列測試改為直接操作注入的 `DownloadQueueController` 實例＋驗證 `controller.items` 狀態，不再依賴已刪除的模態對話框 Key）
- `flutter test test/screens/remote_server_list_screen_test.dart`（8 項全過）
- `flutter test test/screens/cloud_browser_screen_test.dart`（24 項全過，型別改名後重跑確認無回歸）
- `flutter test test/screens/sources_home_screen_test.dart`（16 項全過，含 `CloudDownloadJob` 型別改名後的常駐佇列即時反映測試）

### Remaining Differences
- 佇列項目仍不會自動消失（承襲上一節決策，`dismiss()` 手動移除，無「清除全部」）。

---

## Screen

Reader 底部工具列（`ReaderChromeBottomBar`）＋ TTS 常駐面板（`TtsPanel`）

## Reference

`docs/research/uiux/reference/閱讀_一版.png`、`閱讀_朗讀.png`

## Flutter Screenshot

無（見上方環境限制聲明）

## Result

### Components
PASS（有測試佐證）——

- `reader_chrome_bottom_bar.dart`：頁碼列／跳頁列／選單列三列之間補上分隔線（頁碼列上方 2px、跳頁列上方 1px、選單列上方 2px，對應 Reference 的粗細差異），選單列 4 顆按鈕之間補上垂直分隔線。驗證依據：`flutter test test/screens/reader_chrome_bottom_bar_test.dart`。
- `tts_panel.dart`：展開列 5 顆按鈕與底層動作列 3 顆按鈕，全部補上邊框圓角容器；播放/暫停鍵與停止鍵改為 `primary` 實心填滿＋`onPrimary` 前景色，對齊 Reference「主動作實心填滿、其餘按鈕僅描邊」的視覺語彙。驗證依據：`flutter test test/screens/tts_panel_test.dart`（含觸控目標高度回歸測試，過程中發現並修正一個約束衝突 bug——見下方）。

**過程中修正的一個潛在 bug（非視覺，是本輪修改差點引入的 layout 問題）**：一開始把邊框容器多包了一層 `Padding(all: 2)`，導致外層 `SizedBox(height: minSize)` 的緊約束被 Padding deflate 後小於 `IconButton`/`TextButton` 內建的 `minimumSize`（56／52dp 觸控目標，`DESIGN.md` §7.2），約束衝突下觸控目標被迫縮水 4px（56→52、52→48），被既有的觸控目標回歸測試抓到，已移除該層 Padding 修正（`DecoratedBox`／`ClipRRect` 本身不影響約束，安全）。

### Remaining Differences
- 展開列按鈕彼此間距（`spaceEvenly`）與 Reference 實際間距未逐像素核對。

---

## Screen

筆記（`NotesBottomSheet`：書籤／劃線與備註兩分頁）

## Reference

`[UNKNOWN]` — 無使用者提供的 Reference 截圖，`prototype/elinkbook_theme_prototype.html` 也只有閱讀器底部「書籤」／「劃線備註」兩顆入口按鈕（點擊僅彈出 Toast 提示，未示範實際面板畫面），故本輪改以 `DESIGN.md` §10／§14.2 的明文規格（`NotesSheet` 由 `EBSheetShell` 包裹、雙分頁圖示＋文字標籤不用 Emoji）與本次會話已建立的共用元件（`EBSheetShell`／`EBFieldCard`）作為依據，優先序見下方 Components 說明。

## Flutter Screenshot

無（見文件開頭環境限制聲明）

## Result

### Layout
PASS（有測試佐證）——`notes_bottom_sheet.dart` 改由 `EBSheetShell` 包裹（拖曳把手／標題／關閉按鈕／高度上限 85% 螢幕高度），取代原本自建的 `SafeArea`＋固定 `SizedBox(height:)`（0.6 螢幕高度、clamp 320–600）＋手刻標題列；「導出為 Markdown」透過新增的 `EBSheetShell.actions` 參數插入標題列（既有唯一呼叫端 `BookActionSheet` 不傳此參數，預設空陣列，零影響）。驗證依據：`flutter test test/screens/notes_bottom_sheet_test.dart test/screens/widgets/eb_sheet_shell_test.dart`（56 項全過）。

### Typography
PASS——標題「筆記」與分頁籤「書籤」／「劃線與備註」移除 Emoji（`📚`／`🔖`／`✏️`），改為圖示＋純文字，對齊 `DESIGN.md` §14.2「分頁標籤一律搭配文字標籤，不使用 Emoji（舊版曾用 🔖／✏️ 作為分頁圖示，已淘汰）」的明文規定；備註項目標題文字同樣移除 `📌` Emoji（該筆記列已有左側依劃線色彩/備註著色的圓點圖示區分類型，不需要重複的 Emoji）。

### Color
PASS — 無新增寫死色值；`EBFieldCard`／`EBSheetShell` 皆沿用既有 `ColorScheme`/`CardTheme`。

### Components
PASS（有測試佐證）——
- 分頁籤圖示依 `DESIGN.md` §14.2 明文指定：`Icons.bookmark_outline`（書籤）／`Icons.edit_note`（劃線與備註）。
- 書籤清單列、劃線/備註合併清單列，皆改用本次會話已在 Settings／Source／LayoutSettings 等畫面套用的 `EBFieldCard` 包裹 `ListTile`（邊框卡片，取代裸 `ListTile`），維持全 App 一致的清單列視覺語彙。
- `EBSheetShell` 新增可選 `actions` 參數（標題列右側、關閉按鈕左側），供「導出為 Markdown」使用；`.show()` 靜態方法／既有呼叫端行為不變。

驗證依據：`flutter test test/screens/notes_bottom_sheet_test.dart test/screens/widgets/eb_sheet_shell_test.dart test/screens/library_screen_test.dart test/screens/reader_screen_test.dart`（576 項全過，含既有的 Markdown 導出／批次刪除確認對話框等回歸測試，證明本輪視覺調整未影響任何業務邏輯）。

### Remaining Differences（刻意不做，超出本次範圍）
- `AnnotationToolbar`（畫線時浮現的選字工具列，`annotation_toolbar.dart`）未列入本輪——它是選取文字後浮現的情境操作工具列，不是「畫面」本身；且它目前用固定 `Material(elevation: 4)`（無 E-Ink 感知），與 `DESIGN.md` §5「E-Ink 模式下所有元件強制為 none」原則有落差，但這屬於元件層級的 Token 補完，且牽涉到 §14.1 提到的浮動定位幾何計算（現況問題／重構設計是同一段落，混在一起可能連動既有定位邏輯），建議另開一輪或另立工單處理，避免與這次「畫面」重新設計混在一起、擴大變更風險。
- 使用者未提供 Reference 截圖，本輪視覺判斷完全依賴 `DESIGN.md` 文字規格與既有共用元件推導，若截圖後續補上，建議重新核對一次。

---

## Screen

LayoutSettings（版面設定）文字修正＋標題粗體＋「預設集」分頁重新設計

## Reference

`docs/research/uiux/reference/版面設定_文字_1.png`、`版面設定_邊界_1.png`、`版面設定_呈現_1.png`、`版面設定_預設集.png`

## Result

### Typography
PASS（有測試佐證）——三個版面設定 Bottom Sheet（`reader_settings_sheet.dart`／`fxl_settings_sheet.dart`／`pdf_settings_sheet.dart`）內每一個「設定標題」（數值列標題、SwitchListTile 標題、選項晶片群組上方的區段標題）皆補上 `FontWeight.bold`，對齊 Reference 全部標題皆為粗體的排版語彙；選項晶片本身的短標籤（例如「整頁」「雙頁」）維持原樣不加粗，只有「標題」層級文字變動。

### 名詞修正
PASS——依 `版面設定_文字_1.png` 逐一核對並修正 `reader_settings_sheet.dart` 的四處字面值：「單書閱讀字型」→「字型」、「字型大小」→「字級」、「字型粗細」→「字重」、「行高」→「行距」。`fxl_settings_sheet.dart`／`pdf_settings_sheet.dart` 沒有對應欄位，未變動；`markdown_export.dart` 的匯出文件標題（`## 🔖 書籤清單`／`## ✏️ 劃線與個人備註`）與本次 UI 名詞修正無關，未觸碰。

### Components
PASS（有測試佐證）——「預設集」分頁依 `版面設定_預設集.png` 重新設計：
- 「將目前設定存為新預設集」移到清單最上方，改為 `FilledButton.icon` 滿版實心按鈕（原本 `ElevatedButton` 是 M3 預設的淺色按鈕，與 Reference 的實心主色按鈕不符，兩者一併修正，非本輪新引入的差異）。
- 新增「已儲存的預設集」區段標題；移除原本置頂、與分頁籤標題重複的「版面設定預設集」文字。
- 3 個使用者自建 slot 卡片新增摘要副標題「字級X・行距Y・橫排/直排」（由 `preset.prefs` 即時算出，欄位為 `null` 時顯示「預設」，不捏造假數字）；套用中列的底色/前景色由 `colorScheme.inverseSurface`/`onInverseSurface` 改為 `colorScheme.primary`/`onPrimary`，對齊全 App 已統一的「選中態＝主色實心填滿」語彙（`ReaderOptionTile`／`Switch` 皆同）；「套用到本書」由純圖示按鈕改為文字「套用」的 `OutlinedButton`；「套用到其他書籍」／「刪除」改用有邊框的方形圖示按鈕（比照 `EBStepper._StepperButton` 既有樣式）。
- **新增「系統預設」固定列**（不佔用 3 個 slot 名額、不可刪除）：一鍵把字級/字重/行距/段落間距/字距 5 個目前有覆寫的欄位全部清空、改回本書原始樣式，等同依序按下每個欄位既有的「恢復本書原樣式」按鈕。副標題刻意使用中性說明文字，不顯示 Reference 示範資料裡的具體數字（`字級16・行距1.6`）——這 5 個欄位在未覆寫狀態下沒有對應的全域數值設定可顯示（`GlobalReaderPrefs` 只涵蓋翻頁模式／螢幕方向／熱區等欄位，不含字級/行距等排版數值），顯示假數字會誤導使用者；這是與您確認過的修正後理解（Reference 的「系統預設」列被判定為範例資料裡一個普通已存預設集的名稱，但您希望仍保留一鍵重置這個真實功能）。

驗證依據：`flutter test test/screens/reader_settings_sheet_test.dart test/screens/fxl_settings_sheet_test.dart test/screens/pdf_settings_sheet_test.dart`（219 項全過，含 3 則新增測試涵蓋「系統預設」列的顯示/套用/不影響邊界欄位）。

### Remaining Differences（刻意不做，超出本次範圍）
- 「從其他書籍複製」區塊（複製到本書／複製到其他書籍）Reference 截圖沒有示範，判斷是畫面被截斷未拍到而非要移除——保留在「已儲存的預設集」清單下方，未依 Reference 「看起來沒有」而移除既有功能。
- `AnnotationToolbar` E-Ink 感知（另開一輪處理，您已明確指示）。

---

## flutter analyze Result

```
No issues found! (ran in 11.3s)
```

## flutter test Result

```
+2155: All tests passed!
```
（本輪〔版面設定文字修正/標題粗體/預設集重新設計〕新增 3 則測試（`reader_settings_sheet_test.dart`「系統預設」固定列），總數從上一輪〔筆記面板 Design System 對齊〕的 2152 增至 2155。）
（含本輪新增/更新的 8 則測試：`app_theme_data_test.dart` Switch ON/OFF 色值 4 則、`fxl_settings_sheet_test.dart`／`pdf_settings_sheet_test.dart` 選中態色值更新 3 則、`library_screen_test.dart` 既有分類拼貼格系列間接驗證 `_GroupGridTile` 改動未回歸）
