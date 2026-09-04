# Epic 36 — 三目的地導覽／書架下鑽強化／設定四分區：工單清單 (Issues)

依 `spec.md`（Architecting 階段唯一事實來源，已經 `/superpowers:receiving-code-review` 依 `reviews/review-spec.md` 審查修訂）拆解為 5 個細粒度垂直切片工單，對應 `spec.md`「Implementation Decisions」的功能①~⑤分節（`spec.md` 原文已明訂此對應關係）。每個工單都附有單元測試要求；跟 `spec.md` 對應段落的引用一律用 `spec.md §功能N` 標示，實作者動手前應先讀那一段的完整說明，這裡只列摘要與驗收標準。

**依賴順序：** Issue 1 → Issue 2 → Issue 3 → Issue 4 為一條鏈（狀態逐層疊加：Issue 2 的 `_activeGroupFilter`、Issue 3 的 `_mostRecentBook` 皆是後續工單的前置條件）；Issue 5 只依賴 Issue 1，可與 Issue 2～4 平行進行。

**共同規則（每個工單皆適用，來自 `UI_DESIGN_RULES.md`）：** 動手改程式碼前，先在該工單的 `plans/plan-issue-<N>.md` 說明 (1) 改哪個 UI 元件 (2) 為什麼要改 (3) 哪些畫面依賴它 (4) 是否影響 business logic（不影響則明確寫「不影響」）。本 Epic 全程只碰 Navigation／Library UI／Settings UI／Bottom sheets／Dialogs／Layout，不碰 OPDS／WebDAV／雲端來源實作、書籍儲存、閱讀進度持久化等核心架構清單項目。

---

## Issue 1：三目的地導覽框架＋來源聚合頁

**Status:** ready-for-agent

**依賴：** 無（可立即開始）

**來源：** `spec.md` §功能①（對應原始 Issue 1，解決 C-1、M-3；含 `reviews/review-spec.md` I-5、M-1、M-2 修訂）

**背景／目標：** App 目前沒有任何跨畫面的常駐導覽——書架、來源匯入、設定分散在 `LibraryScreen` 自己的 AppBar 按鈕與 `Navigator.push` 堆疊裡。本工單建立 `AdaptiveShellScaffold` 作為 `main.dart` 新的 `home:`，以 `IndexedStack` 保留三個目的地畫面狀態，並補上「來源」目的地的承接畫面 `SourcesHomeScreen`（AppBar 拿掉「＋」匯入選單後的功能真空）。

**Solution：**
- 新增 `app/lib/screens/adaptive_shell_scaffold.dart`：`AdaptiveShellScaffold` `StatefulWidget`，持有 `_currentIndex`（0=書架／1=來源／2=設定），`body` 用 `IndexedStack` 管理三個子畫面（`initState()` 建構一次，之後只切換 `index`，零動畫轉場）；把 `main.dart` 現有直接餵給 `LibraryScreen` 的所有既有具名參數原樣轉送。**過渡期型別標注（`review-issues.md` M-1）**：`SettingsScreen`→`SettingsScaffold` 更名排在 Issue 5，本工單 `IndexedStack` 第三個子畫面暫時掛載既有 `SettingsScreen(...)`，待 Issue 5 執行時再改為 `SettingsScaffold(...)`，不需要在本工單預先更名。
- **死碼清理（`review-issues.md` M-3）**：`library_import_button`／`library_empty_import_button` 改動後，`_LibraryScreenState` 原有的 `_pickAndImportFiles()`、`_pickAndImportFolder()`、`_isImporting`、`_buildImportingOverlay()` 已無任何呼叫點（原呼叫點分別是被移除的 `library_import_button` 選單與被改為呼叫 `onNavigateToSource` 的 `library_empty_import_button`），須一併移除，邏輯已抽到 `book_import_picker_helper.dart` 供 `SourcesHomeScreen` 使用。
- 新增「書架背景刷新訊號」：`LibraryScreen` 新增 `refreshSignal: Listenable?` 建構參數，`AdaptiveShellScaffold` 切回書架分頁時觸發，解決 `IndexedStack` 常駐掛載下「來源」畫面匯入新書後書架不會自動刷新的問題。
- **系統返回鍵約定（`review-spec.md` M-1）**：`AdaptiveShellScaffold.build()` 最外層包 `PopScope(canPop: _currentIndex == 0, ...)`——非書架分頁時系統返回鍵優先切回書架（index 0）。
- 新增 `app/lib/screens/sources_home_screen.dart`：`SourcesHomeScreen` 只聚合既有入口（本機檔案／資料夾挑選按鈕＋已連結雲端/OPDS 服務清單），不新增底層匯入/雲端邏輯。
- **檔案挑選輔助函式分層（`review-spec.md` I-5）**：`pickAndImportFiles(BookImportService)`／`pickAndImportFolder(BookImportService, {required confirmAutoGroup})` 新建於 `app/lib/screens/support/book_import_picker_helper.dart`（展示層，非 `book_import_service.dart`），供 `LibraryScreen` 與 `SourcesHomeScreen` 共用。
- `library_screen.dart` AppBar 異動：移除 `library_eink_toggle`／`library_import_button`／`library_remote_library_button`；`library_sort_button`＋`library_view_mode_toggle` 合併為 `library_sort_view_button`（含「管理分類...」選單項目，先佔位，實際下鑽邏輯屬 Issue 2）；新增 `library_source_button`；`library_settings_button` 改呼叫 `onNavigateToSettings` callback。
- **空書架匯入按鈕對齊（`review-spec.md` M-2）**：`library_empty_import_button` 的 `onPressed` 改為呼叫 `widget.onNavigateToSource?.call()`，不再直接跳出檔案選擇器。

**單元測試要求：**
- `AdaptiveShellScaffold`：widget test 驗證三個目的地圖示切換後 `IndexedStack.index` 正確、且切換前後同一個 `LibraryScreen` state 不被重建；`refreshSignal` 觸發後驗證 mock `LibraryRepository` 方法被重新呼叫；系統返回鍵在非書架分頁時切回書架分頁（`_currentIndex == 0`）。
- `SourcesHomeScreen`：widget test 驗證本機兩顆按鈕呼叫對應 mock `BookImportService` 方法；雲端/OPDS 依賴缺席時對應項目為停用狀態且不可點擊；依賴齊全時點擊 `Navigator.push` 對應畫面。
- `library_screen_test.dart` 既有測試遷移：`library_import_button`（12 處）、`library_remote_library_button`（4 處）整段移除或改寫為 `SourcesHomeScreen` 測試；`library_eink_toggle`（2 處）測試移除；`library_sort_button`（5 處）、`library_view_mode_toggle`（10 處）改為透過 `library_sort_view_button` 選單操作；`library_settings_button`（2 處）斷言改為呼叫 `onNavigateToSettings` callback。
- `library_empty_import_button` 點擊後呼叫 `onNavigateToSource` callback（新增測試）。
- **`app/test/navigation_test.dart` 遷移（`review-issues.md` I-1）**：既有測試「點擊設定圖示導航至 SettingsScreen，返回後回到 LibraryScreen」（Line 35-61）直接具現化 `MaterialApp(home: LibraryScreen(...))`、斷言點擊設定圖示會 `Navigator.push` 出現 `find.text('設定')`——`library_settings_button` 改呼叫 `onNavigateToSettings` callback 後此斷言會落空。須改寫為驗證 `AdaptiveShellScaffold` 的三目的地切換與系統返回鍵行為（或改為對 `LibraryScreen` 傳入假 `onNavigateToSettings` callback 並驗證被呼叫），不得維持原本對 `Navigator.push`／`SettingsScreen` 出現的斷言。

**驗收標準：** `main.dart:342` 的 `home:` 改為 `AdaptiveShellScaffold(...)`；三目的地圖示互相切換為零動畫轉場且狀態不遺失；「來源」分頁能完成本機/雲端/OPDS 匯入且與現行行為相同；書架 AppBar 僅剩「排序/檢視、來源、設定」三圖示；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 2：書架原地下鑽重構＋管理分類入口搬遷

**依賴：** Issue 1（「管理分類」選單項目需掛進 Issue 1 建立的 `library_sort_view_button` 選單）

**Status:** ready-for-agent

**來源：** `spec.md` §功能②（對應原始 Issue 2，解決 C-2、I-1；含 `reviews/review-spec.md` C-1 修訂）

**背景／目標：** 現行 `_openGroupFilteredView()` 點擊分類拼貼格時是 `Navigator.push` 推入一個全新獨立的 `LibraryScreen` 實例模擬下鑽，感覺像「進入另一個 App」。本工單改為內部狀態切換＋「‹ 返回上層」引導列的原地下鑽。

**Solution：**
- `_LibraryScreenState` 新增 `String? _activeGroupFilter`（取代 `LibraryScreen.groupFilter` 建構參數，三目的地下 `LibraryScreen` 只會被建構一次、恆為頂層模式）。
- `_openGroupFilteredView(groupName)`／`_exitGroupFilteredView()` 改為 `setState` 切換 `_activeGroupFilter`＋重置 `_currentPage = 0`，移除原本 `Navigator.push` 整段。
- `_buildBookList()` 內所有 `widget.groupFilter` 改讀 `_activeGroupFilter`；`_activeGroupFilter != null` 時 AppBar `leading` 改為 `library_back_from_group_button`，`title` 顯示分類名稱。
- **系統返回鍵（`review-spec.md` C-1 修訂）**：修改（非另加）Issue 1 沿用下來的最外層 `PopScope`，合併判斷條件為 `canPop: !_inSelectionMode && _activeGroupFilter == null`，`onPopInvokedWithResult` 內優先解除多選模式、其次才 `_exitGroupFilteredView()`，避免下鑽返回鍵邏輯覆蓋既有多選攔截造成的狀態機衝突。
- 「管理分類」選單項目（`library_manage_groups_option`）併入 `library_sort_view_button` 選單，`_activeGroupFilter == null` 時才顯示。

**單元測試要求：**
- widget test 驗證點擊分類拼貼格後**不產生新的 `Navigator` 路由**（負向驗證，回歸測試核心）；AppBar 顯示「‹ 返回上層 [分類名稱]」；`_activeGroupFilter` 生效後書籍清單只剩該分類。
- 系統返回鍵合併邏輯測試：頂層書架多選模式下返回鍵先解除多選（不退出 App）；下鑽分類內多選模式下返回鍵同樣先解除多選（不誤切回頂層）；非多選模式下鑽狀態下返回鍵才觸發 `_exitGroupFilteredView()`。
- `library_manage_groups_button`（6 處既有測試）改為先開 `library_sort_view_button` 選單、再點擊 `library_manage_groups_option`。
- 選取模式進行中分類格 `onTap` 為 `null` 的既有測試於新的原地下鑽路徑下仍需成立。
- **`library_screen_test.dart` 既有測試遷移（`review-issues.md` I-2）**：
  1. `_filteredLibraryScreenFinder` 輔助函式（Line 4554，`find.byWidgetPredicate` 尋找 `widget.groupFilter == groupName` 的第二個 `LibraryScreen` 實例）及其 11 處呼叫點（Line 583, 786, 1082, 1374, 1417, 1481, 1560, 3387, 3458, 3524, 3590）：因 `LibraryScreen.groupFilter` 建構參數移除、原地下鑽後畫面樹上只會有一個 `LibraryScreen`，須移除這個輔助函式，11 處呼叫點改為直接在當前（唯一）畫面樹上查找目標書籍/元件，不再需要「descendant of 第二個 LibraryScreen」這層限定。
  2. Line 3713-3736「透過分類篩選路徑（`groupFilter` 非 null）進入的 `LibraryScreen` 不會自動開書」測試：因 `groupFilter` 具名參數移除會導致編譯失敗，須改寫為「在頂層書架點擊分類拼貼格下鑽後，確認不會觸發 `_maybeOpenLastBookOnLaunch`」，驗證意圖不變（只有頂層書架啟動當下才自動開書），僅觸發路徑從「建構時傳入 `groupFilter`」改為「執行期點擊下鑽」。

**驗收標準：** 點擊分類拼貼格為原地狀態切換，不推入新路由；系統返回鍵在多選/下鑽兩種情境下行為皆正確、不會誤關閉畫面或狀態混亂；「管理分類」功能不變、僅入口位置改變；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 3：繼續閱讀列與 PagingBar

**依賴：** Issue 2（分頁重置時機與繼續閱讀列顯示條件讀取 `_activeGroupFilter`）

**Status:** ready-for-agent

**來源：** `spec.md` §功能③（對應原始 Issue 3，解決 I-4、I-5；`review-spec.md` I-1 不採納，維持 spec.md 現狀）

**背景／目標：** 書架瀏覽目前用無限捲動的 `GridView.builder`，電子紙裝置上連續刷新大片畫面容易殘影。本工單改為固定每頁一整排（直向 3 項／橫向 4 項，比照 `DESIGN.md#L267`／`#L335` 明文規格）的 `PagingBar` 換頁，並新增常駐「繼續閱讀列」。

**Solution：**
- 新增 `app/lib/screens/widgets/paging_bar.dart`：純呈現、無狀態的 `PagingBar`（高度 52dp，觸控目標一般 48dp／E-Ink 56dp）。
- `library_screen.dart` 新增 `int _currentPage = 0`；`int get _pageSize => orientation == landscape ? 4 : 3`（**不採納 `review-spec.md` I-1 建議的 6 本/2列，維持與 `DESIGN.md` 一致的 1 整排**，理由詳見 `spec.md` Further Notes）；`GridView`/`ListView` 從 `.builder` 改為 `shrinkWrap: true` + `NeverScrollableScrollPhysics`，一頁只渲染當前頁子區間。
- 旋轉換算：`didChangeMetrics()` 偵測 `_pageSize` 改變時，用「目前頁第一項全局 index ÷ 新每頁容量」重新換算 `_currentPage`。
- 排序/搜尋/分類切換時（含 Issue 2 的 `_openGroupFilteredView`/`_exitGroupFilteredView`）皆重置 `_currentPage = 0`。
- 繼續閱讀列：新增 `Book? _mostRecentBook`，`_activeGroupFilter == null` 且存在 `lastReadTime > 0` 的書籍時於搜尋列下方渲染 `_ContinueReadingRow`；書庫全空或全部 `lastReadTime == 0` 或下鑽檢視分類時皆不渲染。

**單元測試要求：**
- `PagingBar` 純 widget test：`currentPage`/`pageCount` 顯示正確、邊界時 `onPrevious`/`onNext` 為 `null` 不崩潰。
- 分頁計算（`_pageSize`/`pageCount`/`safePage`/旋轉換算）抽成可單元測試的純函式，獨立驗證數學正確性；widget test 只需驗證畫面顯示符合純函式預期輸出。
- widget test 驗證 `MediaQuery` 為 portrait/landscape 時個別頁面渲染的項目數（3／4）正確。
- 繼續閱讀列三種情境：書庫全空（不渲染）、有書籍但全部 `lastReadTime` 為 epoch 0（不渲染）、至少一本 `lastReadTime > 0`（渲染且顯示該書資訊、點擊後導覽至該書）。

**驗收標準：** 書架瀏覽改為固定每頁一整排的換頁控制列（直向 3／橫向 4），無限捲動行為移除；旋轉螢幕時頁碼正確換算、不跳到看不懂的地方；繼續閱讀列依三種邊界條件正確顯示/隱藏；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 4：單書「⋮」動作選單 `BookActionSheet`

**依賴：** Issue 3（`onRemoveCache`/`onDelete` 完成後需重新計算 Issue 3 引入的 `_mostRecentBook`）

**Status:** ready-for-agent

**來源：** `spec.md` §功能④（對應原始 Issue 4，解決 I-2；含 `reviews/review-spec.md` I-2、I-3、I-4 修訂）

**背景／目標：** 單書想看詳細資料或臨時改一下這本書的排版方向，目前只能靠長按進多選模式再逐一操作，語意不吻合。本工單新增以「⋮」圖示觸發、和長按多選互斥的單書動作選單。

**Solution：**
- 新增 `app/lib/screens/widgets/eb_sheet_shell.dart`：`EBSheetShell`，`show()` 靜態方法呼叫 `showModalBottomSheet`。**E-Ink 瞬間顯示改用 `sheetAnimationStyle: isEinkMode ? AnimationStyle.noAnimation : null`**（`review-spec.md` I-2 修訂，取代原案自建 `AnimationController` 的 vsync 缺陷與洩漏風險，本專案 Flutter 3.41+ 已原生支援）。
- 新增 `app/lib/screens/book_action_sheet.dart`：`BookActionSheet`，五個選項（詳細資料／移動／版面覆寫／移除快取／刪除），`showRemoveCache: false` 時「移除快取」整項不渲染。
- `library_screen.dart`：`_BookGridTile`／`_BookListTile` 新增 `book_action_menu_${book.id}` 圖示；`_openBookActionSheet(Book book)` 串接五個 callback。**與多選勾選指示器互斥（`review-issues.md` M-2）**：`_BookGridTile` 的 `book_selection_indicator_${book.id}` 目前固定疊在右上角（`selectionMode == true` 時才渲染），新增的 `book_action_menu_${book.id}` 若疊在同一位置會與其重疊；`selectionMode == true` 時隱藏 `book_action_menu` 按鈕（呼應「⋮ 與長按多選互斥」的設計原則，多選進行中本來就不該同時觸發單書動作選單）。
  - `onShowDetails`：新增 `_BookDetailsDialog`。**檔案大小查詢須具防護**（`review-spec.md` I-4 修訂）：`!book.isDownloaded` 顯示「尚未下載」；本機路徑非同步查詢＋`try`/`catch`，`content://` URI 或讀取失敗顯示「未知大小」，不得拋出未捕捉例外。
  - `onMove`：重用 `LibraryBatchActions.moveToGroup`，完成後 `loadBooks()`。
  - `onRemoveCache`／`onDelete`：**完成後補呼叫 `await _bookListController.loadBooks()` 並重新計算 `_mostRecentBook`**（`review-spec.md` I-3 修訂，原案漏了這一步會導致畫面下載狀態標記不更新、或繼續閱讀列殘留無效書籍參照）。
  - `onLayoutOverride`：新增 `_LayoutOverrideDialog`——**必須先 `load()` 取得完整既有 `BookReaderPrefs`、`copyWith()` 只改兩個欄位、才 `save()`**，防止整列覆寫清空其他既有個人化設定（使用者故事 34，資料遺失等級的正確性要求）。

**單元測試要求：**
- `EBSheetShell` 獨立 widget test：拖曳把手存在、關閉按鈕能關閉、`isEinkMode: true` 時彈出動畫時長為 `Duration.zero`。
- `BookActionSheet` 獨立 widget test（不透過 `LibraryScreen` 間接測）：`showRemoveCache: false` 時「移除快取」選項 `findsNothing`；五個選項點擊後對應 callback 各被呼叫一次。
- `_BookDetailsDialog`：`isDownloaded: false` 顯示「尚未下載」；`content://` URI 或讀取拋例外時顯示「未知大小」、不崩潰。
- `onRemoveCache`／`onDelete` 完成後驗證 `loadBooks()` 被呼叫、`_mostRecentBook` 重新計算。
- `_LayoutOverrideDialog`：**核心回歸測試**——mock repository 準備一筆帶有非預設 `fontSize`/`marginTop` 的既有 `BookReaderPrefs`，儲存後斷言 `save()` 收到的物件這些既有欄位原樣保留、只有兩個 override 欄位改變。
- `library_screen.dart` 整合測試：點擊 `book_action_menu_${id}` 後 `BookActionSheet`／`EBSheetShell` 出現在畫面上。

**驗收標準：** 點擊「⋮」彈出單書動作選單，與長按多選互不干擾；五個選項功能正確且與既有批次操作共用底層邏輯；版面覆寫不清空既有其他個人化設定；檔案大小查詢不因 `content://` URI 或未下載書籍而崩潰；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 5：設定畫面四分區＋`GlobalReaderPrefs` 持久化契約

**依賴：** Issue 1（`SettingsScaffold` AppBar 新增的「書架」「來源」圖示需呼叫 `AdaptiveShellScaffold` 提供的 `onNavigateToLibrary`/`onNavigateToSource` callback）

**Status:** ready-for-agent

**來源：** `spec.md` §功能⑤（對應原始 Issue 5，解決 I-3、M-1）

**背景／目標：** 設定畫面是一長串攤平的 `ListTile`，沒有分區。本工單重構為四分區（外觀／閱讀／同步與帳號／關於），並補上「顯示頁首/頁尾」全域預設與「朗讀語音與語速」兩組新設定項的持久化契約。

**Solution：**
- `settings_screen.dart` 更名為 `app/lib/screens/settings_scaffold.dart`，`SettingsScreen` → `SettingsScaffold`；既有 `ListTile` 全部保留、只是包上新增的 `app/lib/screens/widgets/eb_section_header.dart`（`EBSectionHeader`）分組。
- `SettingsScaffold` AppBar 新增「書架」「來源」兩個圖示，分別呼叫 `onNavigateToLibrary`／`onNavigateToSource`。
- 四區塊重排：外觀（佈景／E-Ink／字型管理）、閱讀（閱讀預設值／導航熱區／**新增** `settings_tts_defaults_button`）、同步與帳號、關於（皆為既有項目原樣搬移）。
- `GlobalReaderPrefs` 新增 `showHeader`/`showFooter`（non-nullable，預設 `false`，比照 `fullscreen` 欄位風格）；`ReaderPrefsManagerImpl.resolve()` 的 `book.showHeader ?? false` 硬編碼改為 `book.showHeader ?? global.showHeader`（雙層解析，`reader_screen.dart` 本身不需改動）。
- `ReadingDefaultsScreen` 新增兩個 `SwitchListTile`（`reading_defaults_show_header_switch`／`reading_defaults_show_footer_switch`）。
- 新增 `app/lib/screens/tts_defaults_screen.dart`：`GlobalReaderPrefs` 新增 `ttsVoiceId`（nullable）／`defaultTtsSpeed`（預設 `1.0`），`isEinkMode` 時隱藏 `Slider`、只留 `+`/`-` 微調（步進 0.1x）。**TTS 播放端何時讀取套用為預設值不在本工單範圍**（留給下一個涉及 TTS 播放邏輯的 Epic）。

**單元測試要求：**
- `settings_screen_test.dart` 重新命名為 `settings_scaffold_test.dart`，既有斷言（各 `Key` 存在、點擊後正確導覽）**必須全數維持通過**；新增 `EBSectionHeader` 文字斷言（四個區塊標題皆存在且順序正確）。
- **`app/test/theme/theme_test.dart` 同步更新（`review-issues.md` I-3）**：該檔案 Line 11 `import 'package:elinkbook/screens/settings_screen.dart'`、Line 121 具現化 `home: SettingsScreen(...)`，須同步改為 `settings_scaffold.dart`／`SettingsScaffold`，否則本工單完成後全專案 `flutter test` 會編譯中斷。
- `GlobalReaderPrefs` 新欄位純 Dart 單元測試：`copyWith`/`==`/`hashCode`/SharedPreferences 讀寫 round-trip、缺席時的預設值。
- `resolve()` 雙層解析單元測試：單書覆寫存在時優先、不存在時吃全域預設、兩者皆缺席時吃 `GlobalReaderPrefs.initial()` 的 `false`。

**驗收標準：** 設定畫面分四區塊，既有功能與 Key 契約不變；「顯示頁首/頁尾」全域預設可調整且單書覆寫優先；「朗讀語音與語速」設定畫面可寫入 `GlobalReaderPrefs`（播放端串接留待後續 Epic）；既有使用者升級後新欄位有安全預設值不崩潰；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## 收尾提醒

- 整份 Epic 全數 Issue 完成後，於最後一個 Issue 收尾時執行一次完整 `flutter test`（不帶檔案路徑），比照 `CLAUDE.md`「測試執行範圍」規範確認無全域回歸。
- `docs/epics.md` 對應本 Epic 那一列的備註欄位，隨每個 Issue 完成同步更新為「Issue N 已完成」，完整歷程記錄於本 Epic 的 `epic.md`。
