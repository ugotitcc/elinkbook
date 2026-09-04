# Epic 36 — 三目的地導覽／書架下鑽強化／設定四分區：Architecting Spec

自本文件起，這是 `epic-36-adaptive-shelf-navigation` 的唯一事實來源，取代 `design.md` 中尚未定案的細節；`design.md` 保留作為決策背景與 `DESIGN.md` 矛盾修正的歷史紀錄。本文件依 `reviews/review-design.md` 審查結論收斂後的 5-Issue 切法分節撰寫，`issues.md` 拆解工單時可依此逐節對應。

## Problem Statement

App 目前沒有任何跨畫面的常駐導覽——書架、來源匯入、設定三件事分散在 `LibraryScreen` 自己的 AppBar 按鈕與 `Navigator.push` 堆疊裡，使用者點擊分類拼貼格時甚至會被推入一個帶著完整重複 AppBar 的新畫面（`_openGroupFilteredView()`），感覺像是「進入了另一個 App」而非「書架往下鑽了一層」。書架瀏覽用無限捲動的 `GridView.builder`，電子紙裝置上連續刷新大片畫面容易殘影。設定畫面是一長串攤平的 `ListTile`，沒有分區，找不到常用項目要一路往下滑。單書想看詳細資料或臨時改一下這本書的排版方向，只能靠長按進多選模式再逐一操作，多選模式的批次語意跟「我只想看這一本書的資訊」的單書意圖並不吻合。

## Solution

導入以 `IndexedStack` 保留三個目的地畫面狀態的 `AdaptiveShellScaffold`：書架／來源／設定三個目的地互相以圖示切換，不使用底部導覽列（手機寬度），每個目的地畫面的 AppBar 固定顯示「另外兩個目的地」的圖示＋自己專屬的動作圖示。書架分類下鑽從「推入新畫面」改為「內部狀態切換＋返回引導列」；書架瀏覽從無限捲動改為固定每頁一整排（直向 3 項／橫向 4 項）的 `PagingBar` 換頁；新增常駐「繼續閱讀列」；新增以「⋮」圖示觸發、和長按多選互斥的單書動作選單 `BookActionSheet`；設定畫面重構為 `SettingsScaffold`，四個區塊（外觀／閱讀／同步與帳號／關於）取代攤平清單。「來源」目的地新增輕量聚合頁 `SourcesHomeScreen`，把現有的本機檔案／資料夾／雲端／OPDS 匯入入口收攏到單一畫面，填補 AppBar 拿掉「＋」後的匯入功能真空——不新建任何底層匯入邏輯，純粹是既有入口的重新排列。

## User Stories

### 三目的地導覽（Issue 1）

1. 作為讀者，我希望在書架畫面就能一鍵切到「來源」畫面，不用先想「匯入書籍藏在哪個選單裡」。
2. 作為讀者，我希望在任何一個目的地畫面都能直接切到另外兩個目的地，不需要先返回書架再繞路。
3. 作為讀者，我希望切換目的地時畫面是瞬間跳轉，不是滑動或淡入淡出動畫（尤其在 E-Ink 裝置上避免殘影）。
4. 作為讀者，我希望從「來源」或「設定」切回書架時，書架維持我離開前的頁碼、搜尋關鍵字與分類下鑽狀態，不要每次都重新回到第一頁。
5. 作為讀者，我希望在「來源」畫面能看到「本機檔案」「本機資料夾」兩個按鈕，點了就跟以前一樣直接跳出系統選擇器。
6. 作為讀者，我希望在「來源」畫面能看到我已連結的 Google Drive／OneDrive／OPDS 書庫入口，點了跳轉到既有的雲端瀏覽／遠端書庫畫面，行為與現在完全相同。
7. 作為未連結任何雲端帳號的讀者，我希望「來源」畫面上的雲端/OPDS 項目清楚顯示為停用狀態，而不是點了沒反應或閃退。
8. 作為讀者，我希望書架 AppBar 上不再有 E-Ink 快速切換按鈕之後，仍然可以在「設定」畫面裡開關 E-Ink 模式，只是少了一步捷徑。
9. 作為讀者，我希望書架 AppBar 的「排序」與「檢視模式（格狀/列表）」合併成一個選單後，仍能個別選擇排序條件與切換檢視模式，操作結果跟合併前一樣。
10. 作為讀者，我希望在雲端瀏覽畫面完成一次匯入後切回書架，書架能看到新匯入的書，不需要手動下拉刷新。

### 書架原地下鑽重構（Issue 2）

11. 作為讀者，我希望點擊分類拼貼格進入該分類時，畫面是「原地往下鑽」的感覺，不是跳到另一個看起來幾乎一樣的新畫面。
12. 作為讀者，我希望下鑽進某個分類後，頂部出現清楚的「‹ 返回上層 [分類名稱]」引導列，點擊能回到完整書架。
13. 作為讀者，我希望下鑽檢視分類時，系統返回鍵（Android 手勢/實體鍵）的行為跟點擊「‹ 返回上層」一致，不會意外跳出 App。
14. 作為讀者，我希望在下鑽檢視某分類時看到的書籍清單只有該分類底下的書，跟現在的行為一樣。
15. 作為讀者，我希望「管理分類」的入口現在雖然從 AppBar 圖示變成藏在「排序/檢視」選單裡，但功能（新增/改名/刪除分類）完全不變。
16. 作為讀者，我希望在下鑽檢視分類的畫面裡沒有「管理分類」這個選項（因為那本來就只在頂層書架才有意義）。
17. 作為讀者，我希望長按書籍進入多選模式時，分類拼貼格暫時不可點擊，不會誤觸下鑽。

### 繼續閱讀列與 PagingBar（Issue 3）

18. 作為讀者，我希望書架搜尋列下方常駐顯示我最後閱讀的那本書與進度，點一下直接回到上次讀的地方。
19. 作為剛安裝 App、書架還是空的讀者，我希望不會看到一個奇怪的空白「繼續閱讀」區塊。
20. 作為剛匯入書籍但還沒打開過任何一本的讀者，我希望同樣不會看到「繼續閱讀」區塊佔用畫面空間。
21. 作為讀者，我希望書架瀏覽時，畫面底部有清楚的「‹ 上一頁／頁碼／下一頁 ›」控制列，不再是無限往下滑。
22. 作為讀者，我希望换頁時分類拼貼格與書籍是混在同一份分頁清單裡的，跟現在的排列邏輯一致（拼貼格排最前面）。
23. 作為讀者，我希望切換直向/橫向時，書架每頁顯示的本數會跟著調整（直向 3、橫向 4），而且不會因為換算錯誤讓我「跳頁跳到看不懂的地方」。
24. 作為使用小尺寸螢幕或橫向模式的讀者，我希望這個換頁控制列不會把畫面撐爆（`RenderFlex overflowed`）。
25. 作為 E-Ink 裝置使用者，我希望換頁控制列的按鈕觸控目標比一般模式更大（56dp），方便手指點擊。
26. 作為讀者，我希望切換排序條件或搜尋關鍵字後，換頁自動回到第一頁，不會停留在一個可能已經不存在的頁碼。

### 單書動作選單（Issue 4）

27. 作為讀者，我希望點擊書本卡片上的「⋮」圖示，能彈出一個只針對這一本書的操作選單，不需要進多選模式。
28. 作為讀者，我希望這個選單裡有「詳細資料」，點了能看到書名、作者、格式、檔案大小、閱讀進度百分比、最後閱讀時間。
29. 作為讀者，我希望選單裡的「移動」跟現有的批次「移動到分類」用同一套分類選擇畫面，選了哪個分類這本書就歸到哪個分類。
30. 作為讀者，我希望選單裡的「刪除」會先跳出確認對話框，確認後這本書連同書籤/劃線/備註一起被刪除，行為跟批次刪除一致。
31. 作為使用遠端書庫（Calibre/OPDS）書籍的讀者，我希望選單裡看得到「移除快取」選項，點了本機檔案被清掉但書籍紀錄與閱讀進度保留。
32. 作為使用本機匯入書籍的讀者，我希望選單裡看不到（或呈現停用）「移除快取」選項，因為這本書本來就沒有遠端來源可以重新下載。
33. 作為讀者，我希望選單裡的「版面覆寫」能讓我針對這一本書單獨設定排版方向與翻頁模式，不影響其他書籍或全域預設值。
34. 作為讀者，我希望修改某一本書的版面覆寫設定後，這本書原本已經設定好的其他偏好（字級、邊距等）不會被清空或還原成預設值。
35. 作為讀者，我希望長按書本卡片仍然是進多選模式，「⋮」跟長按是兩個互不干擾的獨立手勢。

### 設定四分區與新設定項（Issue 5）

36. 作為讀者，我希望設定畫面分成「外觀」「閱讀」「同步與帳號」「關於」四個清楚的區塊，不再是一整條長清單。
37. 作為讀者，我希望「外觀」區塊裡看得到佈景選擇、E-Ink 開關、字型管理，跟以前功能相同。
38. 作為讀者，我希望「閱讀」區塊裡看得到閱讀預設值、翻頁與熱區設定的入口，跟以前功能相同（只是重新分組）。
39. 作為讀者，我希望能在「閱讀」區塊裡找到「顯示頁首／頁尾」的全域預設開關，設定後新書預設套用這個顯示狀態。
40. 作為讀者，我希望在閱讀器裡用單書設定覆寫「顯示頁首／頁尾」後，這本書優先套用單書設定，而不是被全域預設值蓋掉。
41. 作為使用朗讀（TTS）功能的讀者，我希望能在「閱讀」區塊裡找到語音與語速的預設值設定，下次開始朗讀時直接套用。
42. 作為 E-Ink 裝置使用者，我希望朗讀語速設定用階梯式加減按鈕操作，不是需要精細拖曳的滑桿。
43. 作為讀者，我希望「同步與帳號」區塊裡看得到同步狀態、已連結雲端帳戶的入口，跟以前功能相同。
44. 作為讀者，我希望「關於」區塊裡看得到版本資訊、授權、閱讀器 Console Log 診斷功能，跟以前功能相同（只是移到新的區塊裡）。
45. 作為維護者，我希望這次新增的 `GlobalReaderPrefs` 欄位（顯示頁首/頁尾全域預設、TTS 語音與語速）都有預設值，既有使用者升級後不會因為欄位缺席而崩潰。

## Implementation Decisions

### 功能 ①：三目的地導覽框架＋來源聚合頁（對應 Issue 1，解決 C-1、M-3）

#### 模組

- **`app/lib/screens/adaptive_shell_scaffold.dart`（新）**——`AdaptiveShellScaffold` `StatefulWidget`，是 `main.dart` 新的 `home:`。持有 `_currentIndex`（0=書架／1=來源／2=設定）與一個 `_libraryRefreshSignal`（見下方「書架背景刷新訊號」）。`body` 用 `IndexedStack(index: _currentIndex, children: [LibraryScreen(...), SourcesHomeScreen(...), SettingsScaffold(...)])`——三個子畫面在 `initState()` 建構一次，往後只切換 `IndexedStack.index`，不重新具現化，滿足 `DESIGN.md` §18.1「零動畫轉場」與本 Epic M-3（狀態保留）要求。**本 Epic 只完整實作手機寬度（<600dp）路徑**——`AdaptiveShellScaffold` 目前不做寬度斷點判斷，`build()` 恆定走 IndexedStack＋三圖示 AppBar 這一條路徑；平板/桌機的 `NavigationRail` 留待未來桌面/平板 Epic（見下方「Out of Scope」）。
  - 建構參數：把 `main.dart` 現有直接餵給 `LibraryScreen` 的所有既有具名參數（`repository`／`importService`／`prefsManager`／`readerFeatureRepositories`／`syncDependencies`／`cloudAccountDependencies`／`remoteLibraryDependencies`／`computeFingerprint`／`isMobileDataConnection`／`themeDependencies`）原樣接收並轉送給內部建構的 `LibraryScreen`／`SourcesHomeScreen`／`SettingsScaffold`，`main.dart:342` 的 `home: LibraryScreen(...)` 改為 `home: AdaptiveShellScaffold(...)`，既有具名參數搬過去、內容不變。
  - 三個目的地切換方法：`_navigateTo(int index)`——`setState(() => _currentIndex = index)`；切到 index 0（書架）時額外呼叫 `_libraryRefreshSignal.notifyListeners()`（見下方）。
  - **系統返回鍵導覽約定**（對應審查報告 M-1）：`build()` 最外層包一層 `PopScope(canPop: _currentIndex == 0, onPopInvokedWithResult: (didPop, result) { if (!didPop) _navigateTo(0); })`——在「來源」或「設定」分頁按系統返回鍵時優先切回書架分頁（index 0），符合 Android 移動端導覽慣例，不會直接關閉/退出 App；已在書架分頁（`_currentIndex == 0`）時交由 `LibraryScreen` 自己的 `PopScope`（見功能②）處理多選/下鑽狀態。
- **書架背景刷新訊號**：`LibraryScreen` 新增建構參數 `final Listenable? refreshSignal;`。`_LibraryScreenState.initState()` 對它 `addListener(_onExternalRefreshRequested)`（`_onExternalRefreshRequested` 呼叫既有 `_bookListController.loadBooks()`／`loadGroups()`），`dispose()` 對應 `removeListener`。`AdaptiveShellScaffold` 用一個 `final _libraryRefreshSignal = ChangeNotifier();` 傳給 `LibraryScreen(refreshSignal: _libraryRefreshSignal)`，並在 `_navigateTo(0)` 時觸發——因為 `IndexedStack` 讓 `LibraryScreen` 全程保持掛載，使用者從「來源」畫面匯入新書後切回書架，若不主動觸發不會自動重新整理（`IndexedStack` 切換可見子項不會重跑 `build()`，也不存在既有「`Navigator.push` 返回時 `.then()` 回呼」這個機制了）。`refreshSignal` 為 `null` 時（例如既有測試直接建構 `LibraryScreen` 不傳這個新參數）維持現行行為，向下相容。
- **`app/lib/screens/sources_home_screen.dart`（新）**——`SourcesHomeScreen` `StatefulWidget`，只聚合既有入口，不新增任何匯入/雲端/OPDS 底層邏輯：
  ```dart
  class SourcesHomeScreen extends StatelessWidget {
    final LibraryRepository repository;
    final BookImportService importService;
    final LibraryCloudAccountDependencies cloudAccountDependencies;
    final LibraryRemoteLibraryDependencies remoteLibraryDependencies;
    final ComputeRemoteFingerprint? computeFingerprint;
    final Future<bool> Function()? isMobileDataConnection;
    final bool isEinkMode;
    final VoidCallback? onNavigateToLibrary;
    final VoidCallback? onNavigateToSettings;
    // 本機檔案／資料夾挑選＋匯入：直接複用 LibraryScreen 現有的
    // _pickAndImportFiles()/_pickAndImportFolder() 邏輯——這兩個方法目前是
    // _LibraryScreenState 私有方法，搬遷為 library_screen.dart 內的頂層
    // 私有函式不可行（跨檔案），改為抽出等價的獨立函式
    // pickAndImportFiles(BookImportService)/pickAndImportFolder(
    // BookImportService, {required Future<bool?> Function() confirmAutoGroup})，
    // 新建於 app/lib/screens/support/book_import_picker_helper.dart（展示/
    // 畫面支援層，非 book_import_service.dart——後者是純 Dart 領域服務抽象
    // 介面，不依賴 Flutter UI／FilePicker／MethodChannel，這兩個函式內部會用
    // 到 FilePicker 與 UI 對話框回呼，放進去會破壞既有分層架構與純 Dart 測試
    // 性，對應審查報告 I-5）。LibraryScreen 與 SourcesHomeScreen 兩處呼叫端
    // 共用，避免邏輯重複維護兩份。
  }
  ```
  - AppBar：`Icons.library_books`／`Icons.grid_view`（書架）＋ `Icons.settings`（設定）兩個圖示，分別呼叫 `onNavigateToLibrary`／`onNavigateToSettings`。
  - Body：「本機」區塊（`ListTile`／按鈕：`sources_pick_files_button`、`sources_pick_folder_button`）＋「已連結服務」區塊，逐一列出 Google Drive／OneDrive（`cloudAccountDependencies.googleDriveStorageClient`／`oneDriveStorageClient` 非 null 且 `computeFingerprint` 非 null 時可點擊，導覽至既有 `CloudBrowserScreen`；否則顯示為 `enabled: false` 的 `ListTile`，`subtitle` 顯示「尚未連結，請至設定畫面連結帳戶」）與 OPDS 遠端書庫（`remoteLibraryDependencies.remoteServerRepository`／`createOpdsClient`／`thumbnailCache` 與 `computeFingerprint` 皆非 null 時可點擊，導覽至既有 `RemoteServerListScreen`），比照 `prototype/elinkbook_theme_prototype.html#L690-L740` 卡片版面精神，不需逐像素還原。
  - 從 `CloudBrowserScreen`／`RemoteServerListScreen` 返回時（這兩個畫面本身仍用 `Navigator.push`，不是三目的地之一），比照 `library_screen.dart:218`／`:904` 既有 `.then()` 慣例——但因為 `LibraryScreen` 已改用 `refreshSignal` 機制（見上），這裡的 `.then()` 不需要重新載入 `LibraryScreen` 的資料，`LibraryScreen` 會在使用者切回書架目的地時自然透過 `refreshSignal` 拿到最新資料。
- **`library_screen.dart` AppBar 異動**（`_buildNormalAppBar()`）：
  - 移除 `library_eink_toggle`（`library_screen.dart:764-780`）——比照 `DESIGN.md#L260-263`，書架 AppBar 固定只有「排序/檢視、來源、設定」三個圖示，E-Ink 快速切換收斂回「設定」目的地既有開關（`settings_eink_mode_switch`）。`LibraryThemeDependencies.onEinkModeChanged`／`isEinkMode` 兩個既有欄位不受影響，繼續原樣轉送給 `SettingsScaffold`。
  - `library_sort_button`（`PopupMenuButton<LibrarySortBy>`）與 `library_view_mode_toggle`（`IconButton`）合併為單一 `library_sort_view_button`（`PopupMenuButton<void>`，`icon: Icons.sort`）：選單項目為既有 `LibrarySortBy.values` 各一項（沿用 `library_sort_option_${sortBy.name}` key 與勾選樣式）＋一條 `Divider`＋一項「切換為格狀／切換為列表」（`library_sort_view_toggle_option`，呼叫既有 `_toggleViewMode`）＋一項「管理分類...」（`library_manage_groups_option`，`groupFilter == null` 時才出現，呼叫既有 `_openManageGroupsDialog`，解決 I-1）。
  - `library_import_button`（`PopupMenuButton` 匯入選單，`library_screen.dart:832-871`）整段移除——匯入能力完全交給 `SourcesHomeScreen`。
  - 新增 `library_source_button`（`IconButton`，`icon: Icons.cloud_download`，呼叫 `widget.onNavigateToSource`）。
  - **空書架的「匯入書籍」按鈕行為對齊**（對應審查報告 M-2）：既有 `library_empty_import_button`（`library_screen.dart:996`，書架全空時顯示的 `ElevatedButton`）`onPressed` 改為呼叫 `widget.onNavigateToSource?.call()`，不再直接跳出檔案選擇器——引導使用者前往「來源」分頁，使全 App 的書籍匯入起點收斂為單一入口。
  - `library_remote_library_button`（`library_screen.dart:883-909`）**移除**——「遠端書庫」入口現在只透過 `SourcesHomeScreen` 的「已連結服務」區塊進入，書架本身不再直接持有這條路徑；`RemoteServerListScreen` 本身不變。
  - `library_settings_button`（`library_screen.dart:910-935`）的 `onPressed` 從 `Navigator.push(...)` 改為呼叫 `widget.onNavigateToSettings`（新建構參數，`AdaptiveShellScaffold` 傳入 `() => _navigateTo(2)`）。
  - `LibraryScreen` 新增建構參數：`final VoidCallback? onNavigateToSource; final VoidCallback? onNavigateToSettings;`（皆為 nullable，維持既有「未接上時不崩潰、按鈕維持存在但 `onPressed: null`」慣例）。

### 功能 ②：書架原地下鑽重構＋管理分類入口搬遷（對應 Issue 2，解決 C-2、I-1）

#### 模組

- **`library_screen.dart`（異動）**：
  - `_LibraryScreenState` 新增可變狀態 `String? _activeGroupFilter`，`initState()` 由 `widget.groupFilter` 初始化一次（頂層書架呼叫時 `widget.groupFilter` 恆為 `null`——見下一點）。
  - **`LibraryScreen.groupFilter` 建構參數移除**：三目的地下 `LibraryScreen` 只會被 `AdaptiveShellScaffold` 建構一次、恆為頂層模式，不再有「篩選畫面是另一個獨立 `LibraryScreen` 實例」這回事（`_maybeOpenLastBookOnLaunch()` 現有的 `if (widget.groupFilter != null) return;` 判斷相應移除，改判斷 `_activeGroupFilter != null`，語意不變：只在頂層書架、剛啟動當下觸發一次）。
  - **`_openGroupFilteredView(String groupName)` 改為原地狀態切換**：
    ```dart
    void _openGroupFilteredView(String groupName) {
      setState(() {
        _activeGroupFilter = groupName;
        _currentPage = 0; // 換分類等同換了一份新的 itemCount，回到第一頁
      });
    }

    void _exitGroupFilteredView() {
      setState(() {
        _activeGroupFilter = null;
        _currentPage = 0;
      });
    }
    ```
    移除原本推入新 `LibraryScreen` 實例的 `Navigator.of(context).push(MaterialPageRoute(...))` 整段（`library_screen.dart:615-657`，含審查歷史留下的 `syncDependencies`/`cloudAccountDependencies`/`computeFingerprint`/`isMobileDataConnection`/`themeDependencies` 轉送——這些轉送存在的唯一理由就是「篩選畫面是獨立實例」，實例消失後轉送需求一併消失，這批審查注解可以整段刪除，不是遺留技術債）。
  - **`_buildBookList()` 內所有 `widget.groupFilter` 改讀 `_activeGroupFilter`**（分類拼貼格是否顯示、`visibleBooks` 過濾邏輯、AppBar 標題與「管理分類」選單項目的顯示條件，皆為既有邏輯原樣保留，只是資料來源從建構參數換成內部狀態）。
  - **返回引導列**：`_activeGroupFilter != null` 時，`_buildNormalAppBar()` 的 `leading` 改為 `IconButton(key: Key('library_back_from_group_button'), icon: Icon(Icons.arrow_back), onPressed: _exitGroupFilteredView)`（取代預設的無 `leading`），`title` 顯示 `_activeGroupFilter`（沿用既有 `Text(widget.groupFilter ?? '書架')` 邏輯，改讀 `_activeGroupFilter`）。**系統返回鍵（`PopBack`）行為**：**修改（而非另外新增）`library_screen.dart:684-690` 現有的最外層 `PopScope`**，合併「多選模式」與「分類下鑽」兩種攔截條件：
  ```dart
  return PopScope(
    canPop: !_inSelectionMode && _activeGroupFilter == null,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;
      if (_inSelectionMode) {
        _exitSelectionMode();
      } else if (_activeGroupFilter != null) {
        _exitGroupFilteredView();
      }
    },
    child: Scaffold(...),
  );
  ```
  沿用既有正確的 Flutter SDK 方法名 `onPopInvokedWithResult`（不是 `onPopInvokedWithDidPop`，該名稱在現行 Flutter 3.41 SDK 中不存在）。若在頂層書架進入多選模式，`_activeGroupFilter == null` 使 `canPop` 原本會計算為 `true`——合併後優先判斷 `_inSelectionMode` 可避免系統返回鍵直接關閉畫面；若在下鑽分類內進入多選，同樣先解除多選模式，不會在多選未解除時就切回頂層書架，狀態不會混亂（滿足使用者故事 13，修正審查報告 C-1）。
  - `_openManageGroupsDialog()` 內既有「篩選中的分類已被刪除時重置為全部」安全網邏輯（若存在）**保留**——不同於 epic-19 時期「管理分類入口在篩選畫面完全不顯示」的假設，本次「管理分類」搬進「排序/檢視」選單後在下鑽檢視分類時仍隱藏（`_activeGroupFilter == null` 才顯示，見功能①的選單項目定義），這一點與 epic-19 現況相同、不受影響。

### 功能 ③：繼續閱讀列與 PagingBar（對應 Issue 3，解決 I-4、I-5）

#### 模組

- **`app/lib/screens/widgets/paging_bar.dart`（新）**——純呈現、無狀態的換頁控制列，不知道分頁邏輯本身：
  ```dart
  class PagingBar extends StatelessWidget {
    final int currentPage; // 0-based
    final int pageCount;
    final VoidCallback? onPrevious;
    final VoidCallback? onNext;
    final bool isEinkMode;
    const PagingBar({
      super.key,
      required this.currentPage,
      required this.pageCount,
      required this.onPrevious,
      required this.onNext,
      this.isEinkMode = false,
    });
  }
  ```
  高度 52dp；`IconButton` 觸控目標一般模式 48dp、`isEinkMode: true` 時 56dp（`DESIGN.md#L344` §15.1）；中央文字 `'${currentPage + 1} / $pageCount'`；`currentPage == 0` 時 `onPrevious` 由呼叫端傳 `null`（`pageCount <= 1` 或已在最後一頁時 `onNext` 同理），`PagingBar` 本身不做邊界判斷。
- **`library_screen.dart`（異動）**：
  - 新增 `int _currentPage = 0;`。
  - **【訂正審查報告 I-5 建議算式】** 每頁固定顯示一整排：`int get _pageSize => MediaQuery.orientationOf(context) == Orientation.landscape ? 4 : 3;`（比照 `DESIGN.md#L267`／`#L335` 明文「直排 1 行 3 欄、橫排 1 行 4 欄」，不是 6 本）。分類拼貼格與書籍混排共用同一份分頁計數（`groupTiles.length + visibleBooks.length` 這份既有 `itemCount` 不變，只是不再一次性全部塞進 `GridView.builder`/`ListView.builder`，而是切出當前頁的子區間）。
  - `_buildBookList()` 改造：
    ```dart
    final itemCount = groupTiles.length + visibleBooks.length;
    final pageSize = _pageSize;
    final pageCount = itemCount == 0 ? 1 : (itemCount / pageSize).ceil();
    final safePage = _currentPage.clamp(0, pageCount - 1);
    final pageStart = safePage * pageSize;
    final pageEnd = (pageStart + pageSize).clamp(0, itemCount);
    // itemBuilder 邏輯不變，只是外層迴圈/GridView.itemCount 改用
    // (pageEnd - pageStart)，index 一律加上 pageStart 位移後再查
    // groupTiles/visibleBooks。
    ```
    `GridView`/`ListView` 从 `.builder`（無限捲動）改為 `shrinkWrap: true, physics: const NeverScrollableScrollPhysics()`（一頁只有 3-4 項，不需要捲動；短螢幕高度風險因此大幅降低，見審查報告 I-5 訂正說明）。`PagingBar` 置於 `Column` 最下方，`onPrevious`/`onNext` 呼叫 `setState(() => _currentPage = safePage - 1 / + 1)`。
  - **旋轉換算**：`didChangeMetrics()`（`WidgetsBindingObserver`，`LibraryScreen` 新增 `with WidgetsBindingObserver` 並在 `initState`/`dispose` 註冊/解除註冊）偵測到 `_pageSize` 實際改變時（記錄 `_lastPageSize`，每次 `build()` 比對），套用「目前頁第一項的全局 index ÷ 新每頁容量」：`_currentPage = ((_currentPage * _lastPageSize) / newPageSize).floor(); _lastPageSize = newPageSize;`。
  - **排序/搜尋/分類切換時回到第一頁**：`_bookListController.changeSortBy()`／進出 `_activeGroupFilter`／（若本 Epic 範圍內有搜尋關鍵字變更，沿用同一慣例）皆在對應呼叫點追加 `_currentPage = 0`（`_openGroupFilteredView`/`_exitGroupFilteredView` 已在功能②列出；`changeSortBy` 呼叫後的 `setState` 追加）。
- **繼續閱讀列**：
  - `_LibraryScreenState` 新增 `Book? _mostRecentBook;`，`_initialize()`／`_onBookListChanged()` 完成後計算：`_bookListController.books` 中 `lastReadTime.millisecondsSinceEpoch > 0` 者依 `lastReadTime` 取最新一筆；若無符合條件的書籍，`_mostRecentBook = null`。
  - `_activeGroupFilter == null` 且 `_mostRecentBook != null` 時，於搜尋列下方渲染 `_ContinueReadingRow`（`library_screen.dart` 內新增 private widget，`key: Key('library_continue_reading_row')`，顯示封面縮圖＋書名＋進度百分比，`onTap: () => _onBookTap(_mostRecentBook!)`，重用既有 `_onBookTap` 開書邏輯）；否則整段不渲染（不是 `Opacity`/`Visibility` 隱藏，直接不插入 widget 樹，對應審查報告 I-4「`SizedBox.shrink()`」的等價效果，本 Epic 採用「不渲染」而非「渲染但收縮為零尺寸」——效果相同、程式碼更直接）。
  - `_activeGroupFilter != null`（下鑽檢視某分類）時，繼續閱讀列**不渲染**——它是頂層書架的常駐列，語意上不屬於「已下鑽到單一分類」的畫面（`DESIGN.md` 未明講下鑽時是否保留，但既有「此列常駐不受下方分類/書籍格狀區域換頁影響」的描述是針對頂層書架，下鑽畫面標題列本身已改為顯示分類名稱＋返回列，兩者疊加會讓頂部過於擁擠，故此 Epic 決議下鑽時隱藏，如后續真機/易用性回饋認為需要在下鑽畫面也顯示，另開工單）。

### 功能 ④：單書「⋮」動作選單 `BookActionSheet`（對應 Issue 4，解決 I-2）

#### 模組

- **`app/lib/screens/widgets/eb_sheet_shell.dart`（新，`DESIGN.md` §10 要求的基礎元件，本 Epic 首次建立、只給 `BookActionSheet` 用，不回頭改造既有 `NotesBottomSheet`／閱讀器內既有 Sheet——那些屬於閱讀器 Chrome 重構範圍，本 Epic 明確不動，見「Out of Scope」）**：
  ```dart
  class EBSheetShell extends StatelessWidget {
    final String title;
    final Widget child; // 內容自行決定是否要 ListView（超出高度上限時）
    final bool isEinkMode;
    const EBSheetShell({
      super.key,
      required this.title,
      required this.child,
      this.isEinkMode = false,
    });

    static Future<T?> show<T>(
      BuildContext context, {
      required String title,
      required WidgetBuilder builder,
      bool isEinkMode = false,
    }) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        // isEinkMode==true 時用 sheetAnimationStyle: AnimationStyle.noAnimation
        // 達成「瞬間具現化顯示」（DESIGN.md §10.2），非 E-Ink 維持預設滑入動畫；
        // 本專案運行於 Flutter 3.41+，showModalBottomSheet 已原生支援此參數，
        // 不需自行建構/管理 AnimationController（靜態方法無 TickerProvider
        // 可用，且呼叫端須負責 dispose，自建有記憶體洩漏風險，對應審查報告 I-2）。
        sheetAnimationStyle:
            isEinkMode ? AnimationStyle.noAnimation : null,
        builder: (context) => EBSheetShell(
          title: title,
          isEinkMode: isEinkMode,
          child: Builder(builder: builder),
        ),
      );
    }
  }
  ```
  物理規格依 `DESIGN.md#L232-239` §10.1/10.2：頂部置中 `32×4dp` 拖曳把手；`SafeArea(bottom: true)` 包裹；`ConstrainedBox` 限制最大高度為 `MediaQuery.sizeOf(context).height` 的 `50%~85%`（超出時 `child` 自行以 `ListView` 呈現，`EBSheetShell` 不強制）；右上角恆常顯示 `Icons.close` 的 `IconButton`（`key: Key('eb_sheet_shell_close_button')`）。
- **`app/lib/screens/book_action_sheet.dart`（新）**：
  ```dart
  class BookActionSheet extends StatelessWidget {
    final Book book;
    final bool showRemoveCache; // book.source == BookSource.calibreOpds && book.isDownloaded
    final VoidCallback onShowDetails;
    final VoidCallback onMove;
    final VoidCallback onLayoutOverride;
    final VoidCallback? onRemoveCache; // null 時該選項停用
    final VoidCallback onDelete;
    const BookActionSheet({
      super.key,
      required this.book,
      required this.showRemoveCache,
      required this.onShowDetails,
      required this.onMove,
      required this.onLayoutOverride,
      required this.onRemoveCache,
      required this.onDelete,
    });
  }
  ```
  五個選項對應 `Key`：`book_action_details`／`book_action_move`／`book_action_layout_override`／`book_action_remove_cache`（`showRemoveCache == false` 時整項不渲染，不是停用——本機匯入書籍不該讓使用者以為「這本書其實可以移除快取只是現在按不了」）／`book_action_delete`。每個選項 `onTap` 先 `Navigator.of(context).pop()` 關閉 Sheet 再呼叫對應 callback（比照現有 Dialog／Sheet 選項的既有慣例，避免 callback 內再彈出的新 Dialog 跟尚未關閉的 Sheet 疊在一起）。
- **`library_screen.dart`（異動）**：
  - `_BookGridTile`／`_BookListTile` 新增 `final VoidCallback onMenuTap;` 建構參數，各自在既有版面右上角/尾端疊加一個 `key: Key('book_action_menu_${book.id}')` 的 `IconButton(icon: Icons.more_vert, onPressed: onMenuTap)`——與既有 `onTap`（開書）/`onLongPress`（多選）三者並存、互不干擾（點擊「⋮」不觸發 `onTap` 開書，`InkWell`/`GestureDetector` 疊層需確認 hit-test 不衝突，實作時以 `Stack` 疊加、`IconButton` 天生會攔截自己範圍內的點擊，不需要額外手勢仲裁邏輯）。
  - 新增 `Future<void> _openBookActionSheet(Book book) async { ... }`：呼叫 `EBSheetShell.show(context, title: book.title, isEinkMode: widget.themeDependencies.isEinkMode, builder: (context) => BookActionSheet(...))`，五個 callback 對應：
    - `onShowDetails`：`showDialog(builder: (_) => _BookDetailsDialog(book: book))`（新 private widget，`AlertDialog` 顯示書名/作者/格式/檔案大小/`progress`/`lastReadTime`，`lastReadTime.millisecondsSinceEpoch == 0` 時顯示「尚未閱讀」而非誤導性的 1970 年日期）。**檔案大小查詢須具防護**（對應審查報告 I-4——`Book` 目前沒有 `fileSize` 欄位，需即時查詢）：若 `!book.isDownloaded`，直接顯示「尚未下載」，不查詢檔案；否則以非同步方式（例如 `_LayoutOverrideDialog` 同層級的 `FutureBuilder`／`initState` 內 `await` 後 `setState`，不得同步阻塞 UI 執行緒）包在 `try`/`catch` 內讀取檔案大小，`book.filePath` 為 `content://` URI（`File(...).lengthSync()`／`.length()` 會拋出 `FileSystemException`）或讀取失敗時，一律顯示「未知大小」，不得讓例外未捕捉往外拋。
    - `onMove`：`showDialog<String?>(builder: (_) => LibraryMoveToGroupDialog(groups: _bookListController.groups))`，非 null 時呼叫 `_batchActions.moveToGroup({book.id}, _bookListController.books, destination)` 後 `_bookListController.loadBooks()`（單書版本直接重用 `LibraryBatchActions.moveToGroup`，傳入單一元素的 `Set`，不需要 `_selectedBookIds`／多選模式介入，對應 design.md「重用既有批次操作的同一組底層邏輯」）。
    - `onRemoveCache`（`showRemoveCache` 為 `false` 時此 callback 不會被觸發，`BookActionSheet` 該選項未渲染）：沿用既有確認對話框語意，`showDialog<bool>` 確認後呼叫 `_batchActions.removeLocalCache({book.id}, _bookListController.books)`，完成後**比照 `onMove` 補呼叫 `await _bookListController.loadBooks()` 並重新計算 `_mostRecentBook`**（對應審查報告 I-3——不刷新的話畫面上的下載狀態標記不會更新，使用者會誤以為操作失敗）。
    - `onDelete`：重用既有 `_confirmDeleteBooks(1)`（`library_screen.dart:399`，該方法已接受 `count` 參數，單書呼叫只需傳 `1`），確認後呼叫 `_batchActions.deleteBooks({book.id}, _bookListController.books)`，完成後**同樣補呼叫 `await _bookListController.loadBooks()` 並重新計算 `_mostRecentBook`**（若被刪除的書恰為 `_mostRecentBook`，避免繼續閱讀列殘留無效書籍參照，對應審查報告 I-3）。
    - `onLayoutOverride`：`showDialog(builder: (_) => _LayoutOverrideDialog(bookId: book.id, repository: widget.readerFeatureRepositories.bookReaderPrefsRepository))`（新 private widget，見下方「版面覆寫對話框」）。`widget.readerFeatureRepositories.bookReaderPrefsRepository == null` 時「版面覆寫」選項整項不顯示（比照 `showRemoveCache` 的不渲染慣例，而非停用）。

#### 版面覆寫對話框（`_LayoutOverrideDialog`）

**關鍵正確性要求**：`BookReaderPrefsRepository.save(bookId, prefs)` 是整列覆寫（`INSERT OR REPLACE`），**不是**只更新有變動的欄位。`_LayoutOverrideDialog` 必須先 `await repository.load(bookId)` 取得該書完整既有 `BookReaderPrefs`（含既有的字級/邊距/PDF 裁切等其他覆寫），再用 `.copyWith(writingModeOverride: ..., pageTurnModeOverride: ...)` 只改這兩個欄位、其餘欄位原樣帶回，最後才 `save()`——直接 `BookReaderPrefs(writingModeOverride: x, pageTurnModeOverride: y)`（其餘欄位吃建構子預設值）會把這本書所有其他既有的個人化設定整列清空，這是資料遺失等級的錯誤，解決使用者故事 34。

```dart
class _LayoutOverrideDialog extends StatefulWidget {
  final String bookId;
  final BookReaderPrefsRepository repository;
  const _LayoutOverrideDialog({required this.bookId, required this.repository});
}
// initState 內 repository.load(bookId) 取得 _existingPrefs；
// 畫面呈現 WritingMode?／PageTurnMode? 兩組單選（含「使用預設」選項，
// 對應 null，即 writingModeOverride/pageTurnModeOverride 清為 null）；
// 儲存時 _existingPrefs.copyWith(writingModeOverride: ..., pageTurnModeOverride: ...) 後 save()。
```

### 功能 ⑤：設定畫面四分區＋`GlobalReaderPrefs` 持久化契約（對應 Issue 5，解決 I-3、M-1）

#### 模組

- **`settings_screen.dart` → 更名為 `app/lib/screens/settings_scaffold.dart`，類別 `SettingsScreen` → `SettingsScaffold`**（比照 `DESIGN.md#L378` 「設定畫面 (`SettingsScaffold`) 分為四個區塊」的正式命名；呼叫端 `library_screen.dart`／`adaptive_shell_scaffold.dart`／既有 `settings_screen_test.dart` 同步更名為 `settings_scaffold_test.dart` 並更新 import／類別名稱，行為與既有測試斷言不變，純粹是重新命名＋分區重排，不是重寫）。
- **`app/lib/screens/widgets/eb_section_header.dart`（新，`DESIGN.md` §17 要求的基礎元件）**：
  ```dart
  class EBSectionHeader extends StatelessWidget {
    final String title;
    const EBSectionHeader({super.key, required this.title});
    @override
    Widget build(BuildContext context) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold)),
        );
  }
  ```
  （最小可用版本，不含互動；比照 `ReadingDefaultsScreen._buildSectionHeader()` 現有樣式定調，抽成共用元件供 `SettingsScaffold` 使用。）
- **`SettingsScaffold` AppBar**：新增「書架」（`Icons.grid_view`，呼叫 `onNavigateToLibrary`）與「來源」（`Icons.cloud_download`，呼叫 `onNavigateToSource`）兩個圖示（`DESIGN.md#L262-263`），既有 `title: Text('設定')` 不變。
- **`SettingsScaffold.build()` 四區塊重排**（既有 `ListTile` 全部保留、只是包上 `EBSectionHeader` 分組，功能與既有 key 不變，除下方兩項新增）：
  - **外觀**：`EBSectionHeader('外觀')` ＋ 既有「佈景」`ListTile` ＋ `settings_eink_mode_switch` ＋ `settings_font_management_button`。
  - **閱讀**：`EBSectionHeader('閱讀')` ＋ `settings_reading_defaults_button`（既有，導覽至 `ReadingDefaultsScreen`——本 Epic 在該畫面內新增頁首/頁尾開關，見下方）＋ `settings_nav_zone_button`（既有，導覽至 `NavZoneSettingsScreen`，標籤沿用既有「導航熱區」文字，`DESIGN.md` 稱呼「翻頁與熱區」是概念性描述、不強制改動既有畫面標題文字）＋ **新增** `settings_tts_defaults_button`（導覽至新 `TtsDefaultsScreen`，見下方）。
  - **同步與帳號**：`EBSectionHeader('同步與帳號')` ＋ `settings_sync_button` ＋ `settings_cloud_account_button`（皆既有，原樣搬移）。
  - **關於**：`EBSectionHeader('關於')` ＋ `settings_about_button` ＋ `settings_reader_console_log_button` ＋ `settings_console_log_switch`（皆既有，原樣搬移，維持目前一般可見狀態——**不落地** `DESIGN.md` §17.1「藏在連點版號之後」這項行為變更，本次僅做分區重排，維持診斷項目直接可見；若日後要落地連點手勢，另開工單）。
- **`ReadingDefaultsScreen`（異動）新增「顯示頁首／頁尾」全域預設開關**：
  - `GlobalReaderPrefs` 新增兩個 non-nullable 欄位 `final bool showHeader; final bool showFooter;`（比照既有 `fullscreen` 欄位風格，皆有明確安全預設值，不是 nullable——全域層本身沒有更上層可回退，`GlobalReaderPrefs.initial()` 兩者皆設為 `false`，與目前 `reader_screen.dart` 多處硬編碼的 `?? false` 回退值一致，升級後行為不變）。`copyWith`/`==`/`hashCode` 同步新增。
  - `ReaderPrefsManagerImpl`：新增 `_showHeaderKey = 'global_reader_show_header'`／`_showFooterKey = 'global_reader_show_footer'` 兩個 SharedPreferences 鍵，`loadGlobalPrefs()`／`saveGlobalPrefs()` 對稱新增讀寫（比照既有 `fullscreen` 鍵的既有寫法）。
  - `reader_prefs_manager_impl.dart:185-186` 的 `resolve()`：
    ```dart
    showHeader: book.showHeader ?? global.showHeader,
    showFooter: book.showFooter ?? global.showFooter,
    ```
    取代既有 `book.showHeader ?? false`／`book.showFooter ?? false` 硬編碼——這是本次唯一需要異動 `reader_prefs_manager_impl.dart` 的地方，`reader_screen.dart` 本身完全不需要改動（它一律讀 `_resolved?.showHeader`／`showFooter`，不知道回退值來自哪裡），不構成「閱讀器 Chrome 重構」。
  - `ReadingDefaultsScreen` 新增兩個 `SwitchListTile`（`key: reading_defaults_show_header_switch`／`reading_defaults_show_footer_switch`），比照既有 `reading_defaults_volume_key_switch` 的 `_update(_prefs.copyWith(...))` 寫法。
- **`app/lib/screens/tts_defaults_screen.dart`（新）**——比照 `NavZoneSettingsScreen`／`ReadingDefaultsScreen` 既有「全域偏好、即時生效、無儲存按鈕」慣例：
  - `GlobalReaderPrefs` 新增 `final String? ttsVoiceId; final double defaultTtsSpeed;`（`ttsVoiceId` 為 nullable——`null` 代表「使用系統預設語音」，語意上沒有一個放諸四海皆準的安全非空預設值；`defaultTtsSpeed` non-nullable，預設 `1.0`，比照 `DESIGN.md#L307` §13.2 語速範圍 0.75x~2.0x）。`copyWith`/`==`/`hashCode` 同步新增。
  - `ReaderPrefsManagerImpl` 新增對應 SharedPreferences 鍵（`_ttsVoiceIdKey`／`_defaultTtsSpeedKey`），`defaultTtsSpeed` 用 `sp.getDouble(...) ?? 1.0`。
  - `TtsDefaultsScreen` 呼叫 `LibraryReaderFeatureRepositories.ttsProvider?.getAvailableVoices()`（既有 `SystemTtsProvider.getAvailableVoices()` API，`ttsProvider == null` 時整個「語音選擇」區塊顯示不可用提示，不崩潰）列出可選語音（`RadioListTile`）；語速控制為 `Slider`＋既有慣例的 `+`/`-` `IconButton` 微調（比照 `reader_settings_sheet.dart:698,715` 既有寫法，**不建立**新的共用 `EBStepper` 元件——`DESIGN.md` §18.3 提及的 `EBStepper` 是尚未落地的抽象元件名稱，目前全專案數值型控制項的既有慣例就是「Slider + 內聯 +/- IconButton」，本 Epic 沿用既有慣例，不在此無關的一步新增一個共用元件，避免無謂抽象化）；`isEinkMode` 為 `true` 時（沿用 `LibraryThemeDependencies.isEinkMode` 一路轉送下來）隱藏 `Slider`、只留 `+`/`-` 兩顆按鈕，步進 `0.1x`（`DESIGN.md#L307`）。呼叫 `widget.prefsManager.saveGlobalPrefs(prefs.copyWith(ttsVoiceId: ..., defaultTtsSpeed: ...))` 即時生效。
  - **TTS 播放端串接為本 Epic 交付範圍之外的最小串接**：`SystemTtsProvider` 呼叫端（既有 TTS 播放邏輯所在，屬於 §13 閱讀器 TTS 元件、本 Epic 明確不動）**維持現狀**——本 Epic 只交付「設定畫面能寫入這兩個全域欄位」，播放端何時讀取套用為預設值留給下一個涉及 TTS 播放邏輯的 Epic（見「Out of Scope」），避免為了串接一個小小的預設值讀取而觸碰明確排除的 §13 範圍。

## Testing Decisions

- **一般原則**：新／異動 widget 一律沿用既有「`pumpWidget(MaterialApp(home: X(...)))` + `Key` 斷言」既有慣例（`library_screen_test.dart`／`settings_screen_test.dart` 現有寫法），不引入新的測試工具或 golden test 基礎設施。
- **`AdaptiveShellScaffold`**：widget test 驗證三個目的地圖示切換後 `IndexedStack.index` 正確、且切換前後同一個 `LibraryScreen` state 不被重建（用一個可觀察的內部計數或 `find.byType` 配合 `Key` 確認 widget identity 不變，比照 Flutter 官方 `IndexedStack` 測試手法）；`refreshSignal` 觸發後驗證傳入的 mock `LibraryRepository.listBooks`/`listGroups` 被重新呼叫。
- **`SourcesHomeScreen`**：widget test 驗證本機兩顆按鈕呼叫對應的 mock `BookImportService` 方法；雲端/OPDS 依賴缺席時對應項目為停用狀態且不可點擊；依賴齊全時點擊會 `Navigator.push` 對應畫面（斷言 pushed route 的 widget 型別，比照 `library_screen_test.dart` 既有對雲端匯入選單項目的測試模式）。
- **書架原地下鑽（功能②）**：widget test 驗證點擊分類拼貼格後**不產生新的 `Navigator` 路由**（`Navigator.of(context).canPop()`／pushed route 數量不變，這是本次修正 C-2 最核心的回歸測試——舊行為必須明確斷言「不會再發生」，不能只驗證新行為存在）、AppBar 顯示「‹ 返回上層 [分類名稱]」、`_activeGroupFilter` 生效後書籍清單只剩該分類；點擊返回列／觸發系統返回鍵（`tester.pageBack()` 或直接呼叫 `PopScope` 對應的返回邏輯）能回到頂層書架；選取模式進行中分類格 `onTap` 為 `null` 的既有測試需確認在新的原地下鑽路徑下仍然成立。「管理分類」搬入「排序/檢視」選單後，既有 `library_manage_groups_button` 相關測試改為先開啟 `library_sort_view_button` 選單、再點擊 `library_manage_groups_option`。
- **`PagingBar`／分頁邏輯**：`PagingBar` 本身為純 widget test（`currentPage`/`pageCount` 顯示正確、邊界時 `onPrevious`/`onNext` 為 `null` 不崩潰）。`library_screen.dart` 分頁計算（`_pageSize`/`pageCount`/`safePage`/旋轉換算公式）獨立抽成可單元測試的純函式（例如 `int recalculatePage({required int oldPage, required int oldPageSize, required int newPageSize})`），比照 epic-19「`_buildGroupTiles()` 純函式單元測試」的既有拆分手法，不要求透過 widget test 間接驗證數學正確性；widget test 只需驗證「旋轉後畫面顯示的頁碼與書籍符合純函式已驗證的預期輸出」。直向 3 項/橫向 4 項每頁筆數：widget test 驗證 `MediaQuery` 為 portrait/landscape 時個別頁面渲染的項目數正確（既有 `library_screen_test.dart` 已有直向 3 欄/橫向 4 欄的既有測試可參考擴充，不是全新模式）。
- **繼續閱讀列**：widget test 覆蓋三種情境——書庫全空（不渲染）、有書籍但全部 `lastReadTime` 為 epoch 0（不渲染）、至少一本 `lastReadTime > 0`（渲染且顯示該書資訊、點擊後導覽至該書），比照 I-4 的三種邊界條件逐一驗證，不只測「有資料時正確顯示」這一種情境。
- **`BookActionSheet`／`EBSheetShell`**：`EBSheetShell` 獨立 widget test（拖曳把手存在、右上角關閉按鈕能關閉、`isEinkMode: true` 時彈出動畫時長為 `Duration.zero`——比照 `epic-35` 新增 `themeAnimationDuration` 斷言的既有測試手法）。`BookActionSheet` 獨立 widget test，不透過 `LibraryScreen` 間接測——`showRemoveCache: false` 時「移除快取」選項不存在於 widget 樹（`findsNothing`，不是 `findsOneWidget` + 斷言 `enabled: false`）；五個選項點擊後對應 callback 各被呼叫一次。`library_screen.dart` 只需一則整合測試：點擊某本書的 `book_action_menu_${id}` 後，`BookActionSheet`／`EBSheetShell` 出現在畫面上（斷言型別即可，選項本身的行為已由上述獨立測試覆蓋，避免重複測試同一件事兩次）。
- **`_LayoutOverrideDialog`**：widget test 驗證**先 `load()` 既有 `BookReaderPrefs` 再 `copyWith()` 才 `save()`**——用 mock `BookReaderPrefsRepository` 準備一筆帶有非預設 `fontSize`/`marginTop` 等既有欄位的 `BookReaderPrefs`，儲存後斷言 `save()` 收到的物件這些既有欄位原樣保留、只有 `writingModeOverride`/`pageTurnModeOverride` 改變（這是解決使用者故事 34、防止資料遺失的核心回歸測試，必須明確存在，不能只測「儲存後值變成新選的值」這種會漏掉「其他欄位被清空」的弱斷言）。
- **`GlobalReaderPrefs` 新欄位（`showHeader`/`showFooter`/`ttsVoiceId`/`defaultTtsSpeed`）**：純 Dart 單元測試，`copyWith`/`==`/`hashCode`/`ReaderPrefsManagerImpl` 的 SharedPreferences 讀寫 round-trip、缺席時的預設值，比照 epic-19 `fullscreen` 欄位新增時的既有測試模式（`reader_prefs_manager_impl_test.dart` 或既有等價檔案）。`resolve()` 新的 `book.showHeader ?? global.showHeader` 雙層解析：單元測試驗證單書覆寫存在時優先、不存在時吃全域預設、兩者皆缺席時吃 `GlobalReaderPrefs.initial()` 的 `false`。
- **`SettingsScaffold` 重新命名與分區**：既有 `settings_screen_test.dart` 重新命名為 `settings_scaffold_test.dart`，既有斷言（各 `Key` 存在、點擊後正確導覽）**必須全數維持通過**，不因為重新命名/分區而改變任何一個既有 `Key` 的行為契約——這是驗證「本次是重排不是重寫」的核心回歸測試。新增 `EBSectionHeader` 文字斷言（四個區塊標題皆存在且順序正確：外觀／閱讀／同步與帳號／關於）。
- **已知測試影響**（呼應審查報告 M-2，具體盤點結果）：
  - `library_import_button`（12 處）、`library_remote_library_button`（4 處）：測試整段移除或改寫為 `SourcesHomeScreen` 測試。
  - `library_eink_toggle`（2 處）：測試移除（功能移除，不是搬遷）。
  - `library_sort_button`（5 處）、`library_view_mode_toggle`（10 處）：改為透過新的 `library_sort_view_button` 選單操作，斷言邏輯不變（選對排序條件/切換檢視模式的結果相同），只是觸發路徑改變。
  - `library_manage_groups_button`（6 處）：改為先開 `library_sort_view_button` 選單、再點 `library_manage_groups_option`。
  - `library_settings_button`（2 處）：斷言從「`Navigator.push` 出現 `SettingsScreen`」改為「呼叫傳入的 `onNavigateToSettings` callback」（widget test 用假 callback 記錄呼叫次數，不再斷言 pushed route）。

## Out of Scope

- 平板（>=600dp）／桌機（>=1024dp）的 `NavigationRail` 與雙欄 Master-Detail 版面：`AdaptiveShellScaffold` 本 Epic 只完整交付手機寬度（<600dp）路徑，寬度斷點判斷與 `NavigationRail` 視覺本身留給未來桌面/平板 Epic（`CLAUDE.md` 已定調「初期幾波不含桌面版目標」）。
- `DESIGN.md` §16 `SourceBrowser` 完整新架構（`LocalFileProvider`/`GoogleDriveProvider`/`OneDriveProvider`/`OpdsServerProvider` 統一抽象、麵包屑導覽、`DownloadQueueRow`、`SyncStatusChip`）：`SourcesHomeScreen` 只是既有入口的聚合頁，不建立這套新抽象，留在 `DESIGN.md` §19 階段四 Backlog。
- 閱讀器 Chrome／TTS UI 重構（`DESIGN.md` §12／§13：淘汰右側按鈕塔、`TTSMiniPlayer`、TTS Expanded Sheet）：本 Epic 完全不動，`TtsDefaultsScreen` 只交付設定畫面寫入 `GlobalReaderPrefs` 兩個新欄位，播放端何時讀取套用為預設值留給下一個涉及 TTS 播放邏輯的 Epic。
- 「關於」區塊「診斷功能藏在連點版號之後」的手勢行為（`DESIGN.md` §17.1 字面要求）：本 Epic 只做四分區重排，診斷項目（Console Log 按鈕/開關）維持一般可見，不落地連點手勢。
- `EBButton`／`EBIconButton`／`EBStepper`／`EBRadius` 等 `DESIGN.md` 第一層基礎元件命名：本 Epic 只建立本次實際用到的 `EBSheetShell`／`EBSectionHeader` 兩個最小可用版本，其餘基礎元件名稱不預先建立空殼，避免未經驗證的抽象化。
- 既有 `NotesBottomSheet`／閱讀器內既有 Bottom Sheet 改用新建的 `EBSheetShell`：這些屬於閱讀器 Chrome 重構範圍，本 Epic 不動，`EBSheetShell` 本次只有 `BookActionSheet` 一個使用者。
- OPDS／WebDAV／雲端來源實作、書籍儲存、閱讀進度持久化等 `UI_DESIGN_RULES.md` 明文禁止本輪碰的核心架構——本 Epic 完全不涉及，`SourcesHomeScreen` 純粹導覽至既有畫面。
- 書架搜尋列的 `SearchView` 即時過濾（`DESIGN.md` §15.2）：`design.md`／本 spec 皆未將其列入本次落地範圍（現有程式碼是否已有搜尋列需在 Issue 規劃時另行查證，若既有搜尋機制與本次 `PagingBar`/`_currentPage` 有交互作用——例如搜尋結果變動時是否也要重置頁碼——屬於 Issue 3 規劃階段的查證項目，非本 spec 遺漏）。

## Further Notes

- **對 `design.md` 的訂正**：本 spec 撰寫過程中發現 `design.md` 依審查報告 I-5 建議寫入的「直向每頁 6 本（2 列×3 欄）」與 `DESIGN.md#L267`／`#L335` 明文的「1 行 3 欄／1 行 4 欄」不符，已回頭訂正 `design.md` 該段文字（本 spec 的功能③已採用訂正後的正確版本：直向 3 項、橫向 4 項）。這處錯誤源於接受審查報告建議算式時沒有回頭核對 `DESIGN.md` 原文，往後審查報告的具體數字建議都需要對照原始規格文件二次確認，不能直接照抄。
- **`reviews/review-spec.md` I-1 不採納**：`review-spec.md` I-1 重複提出了與上一點相同的「直向每頁 6 本（2×3）」建議（換了個編號，內容實質相同），本 spec 維持直向 3／橫向 4（各一整排）不變——`DESIGN.md#L267`／`#L335` 明文即為此意，已核對過兩輪。留白過大的 UX 疑慮若日後真機驗證後認為需要調整，屬於 `DESIGN.md` 層級的設計決策異動，需另開工單回頭修訂 `DESIGN.md`，不由 `spec.md` 單方面推翻。
- **命名一致性**：`SettingsScreen` 更名為 `SettingsScaffold`、新增 `EBSheetShell`/`EBSectionHeader` 兩個以 `DESIGN.md` 命名為準的基礎元件，是本 Epic 第一次把 `DESIGN.md` 使用的正式元件命名系統性地反映到程式碼裡；後續 Epic 若要新增更多 `EB*` 基礎元件，可參考本次 `app/lib/screens/widgets/` 的擺放位置慣例。
- **Issue 順序上的暫時性不一致**：Issue 1（三目的地導覽框架）先於 Issue 2（書架原地下鑽重構）合併時，`LibraryScreen` 內部仍會短暫維持 `_openGroupFilteredView()` 的 `Navigator.push` 舊行為，只是這個推入的畫面現在活在 `AdaptiveShellScaffold` 的 `IndexedStack` 其中一個分頁裡——架構上不優雅但功能不會壞掉，兩個 Issue 個別的 PR 審查與測試皆可獨立通過，不需要合併成單一 Issue。
- **`GlobalReaderPrefs` 欄位持續增長**：本 Epic 新增 4 個欄位（`showHeader`／`showFooter`／`ttsVoiceId`／`defaultTtsSpeed`），皆走 SharedPreferences（不涉及 SQLite schema 版本異動，與 `BookReaderPrefs` 那類需要 `ALTER TABLE` 的欄位不同）；若未來欄位持續增加，可能需要考慮拆分 `GlobalReaderPrefs` 或改用更結構化的儲存格式，但目前 13 個欄位規模尚不構成本 Epic 需要處理的問題。
