# Epic 19 — 書架與閱讀體驗強化：工單清單 (Issues)

依 `design.md`（2026-07-28 `/grill-with-docs` Discovery，三項新功能需求）與 `spec.md`（Architecting 階段定義的核心介面/型別，已依 `/superpowers:requesting-code-review` 審查修訂）拆解出的 3 個工單。三項功能彼此獨立、無依賴關係，可任意順序或平行開始。

---

## Issue 1：全螢幕模式

**Status:** ✅ 已完成

**依賴：** 無

**描述：**

新增一個獨立於既有「沉浸模式」（`_chromeVisible`，九宮格中央熱區觸發）的全新每本書持久化開關「全螢幕模式」，只控制 Android 系統狀態列與導覽列的顯示/隱藏，不影響 App 自己的 AppBar/Footer/頁首/頁尾/懸浮按鈕（後者永遠只受既有的沉浸模式與 `showHeader`/`showFooter` 控制）。完整型別/介面定義見 `spec.md`「功能 ① 全螢幕模式」。

**重要：機制為原生 `WindowInsetsControllerCompat`，非 Flutter `SystemChrome`**——經查證，純 Dart `SystemChrome.setEnabledSystemUIMode()` 在本專案目前 `targetSdk`（36）下確認無效（Flutter SDK 官方文件：API 36+ 一律強制 `edgeToEdge`、無退出方法），已改採原生方案並新增 **ADR 0015**（`docs/adr/0015-fullscreen-native-window-insets-controller.md`）。

- **`app/lib/reader/book_reader_prefs.dart`**：新增 `final bool? fullscreen` 欄位（`null`＝未覆寫，`resolve()` 決成 `false`，比照既有 `showHeader`/`showFooter` 的 nullable-bool 慣例），`toMap()`／`fromMap()`／`copyWith()`／`==`／`hashCode` 同步新增。
- **`app/lib/reader/resolved_preferences.dart`**：新增 `final bool fullscreen`（non-nullable）。
- **`app/lib/reader/reader_prefs_manager_impl.dart`**：`resolve()` 內新增 `fullscreen: book.fullscreen ?? false,`（緊鄰既有 `showHeader`/`showFooter` 兩行，`reader_prefs_manager_impl.dart:179-180`）。
- **`app/lib/library/sqlite_library_repository.dart`**：schema `version` 由 14 提升為 15。**兩處都要改**：① `_createBookReaderPrefsTable()`（`sqlite_library_repository.dart:190-222`）的 `CREATE TABLE` 陳述式本身直接加上 `fullscreen INTEGER`（比照該陳述式已包含 `show_header`/`column_mode`/`margin_top` 等既有欄位的一次到位慣例——全新安裝走 `onCreate` 不會經過 `onUpgrade`，只改 `onUpgrade` 會讓全新安裝的表永遠缺這個欄位，讀寫時拋出 `no such column: fullscreen`）；② `onUpgrade` 既有 `if (oldVersion < 2) {...} else { ... if (oldVersion < 14) { await _addMarginColumns(db); } }` 分支內追加 `if (oldVersion < 15) { await _addFullscreenColumn(db); }`（供既有裝置升級用）。
- **`app/lib/screens/reader_settings_sheet.dart`／`app/lib/screens/pdf_settings_sheet.dart`／`app/lib/screens/fxl_settings_sheet.dart`**：三者皆同步新增 `late bool _fullscreen;`（`initState`／`didUpdateWidget`：`widget.prefs.fullscreen ?? false`）與一個 `SwitchListTile`（標籤「全螢幕模式」，比照既有開關寫法），`_notifyChanged()` 帶入 `fullscreen: _fullscreen`。`fxl_settings_sheet.dart:9` 既有註解已預留此欄位的落點。
- **`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`**：`configureFlutterEngine()` 新增 `elinkbook/fullscreen` MethodChannel（比照既有 `elinkbook/volume_key`／`elinkbook/app_info` 頻道慣例），處理 `"setEnabled"`（`Boolean` 參數），透過 `WindowCompat.getInsetsController(window, window.decorView)` 呼叫 `hide`/`show(WindowInsetsCompat.Type.systemBars())`，`systemBarsBehavior = BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE`。
- **`app/android/app/build.gradle.kts`**：明確新增 `implementation("androidx.core:core-ktx:1.15.0")`。
- **`app/lib/screens/reader_screen.dart`**：新增 `static const _fullscreenChannel = MethodChannel('elinkbook/fullscreen');`（比照既有 `_volumeKeyChannel`），新增 `bool? _lastAppliedFullscreen;`（比照 `_lastAppliedOrientation`），新增 `_applySystemUiMode()`（比照 `_applyScreenOrientation()`，`reader_screen.dart:389-397`，呼叫 `_fullscreenChannel.invokeMethod('setEnabled', resolved.fullscreen)`），只在 `_applyScreenOrientation()` 現有的兩個呼叫點追加呼叫（`initState().then()` line 267、`_handlePrefsChanged()` line 441）；`dispose()`（`reader_screen.dart:301-314`）新增 `_fullscreenChannel.invokeMethod('setEnabled', false)` 無條件還原，緊鄰既有 `SystemChrome.setPreferredOrientations(const [])`。既有 `didChangeAppLifecycleState()`（`reader_screen.dart:322-326`，目前只處理 `paused`）新增 `AppLifecycleState.resumed` 分支：`_lastAppliedFullscreen = null; _applySystemUiMode();`（App 從背景恢復時系統列可能被 OS 自動重新顯示，等值節流防護會誤判不需重套用，需強制清空快取後重呼叫）。

**單元測試要求：**
- `BookReaderPrefs.fullscreen` 的 `toMap`/`fromMap`/`copyWith`/`==`/`hashCode`：`flutter test`，比照既有 `showHeader`/`showFooter` 欄位新增時的既有測試模式。
- 三個設定面板新增的 `SwitchListTile`：widget test（tap 開關→驗證 `onChanged` 回報的 `BookReaderPrefs.fullscreen` 值）。
- `_applySystemUiMode()`：widget test 用 mock `elinkbook/fullscreen` method channel（比照既有 `elinkbook/volume_key` 頻道測試模式）記錄 `setEnabled` 被呼叫的次數與參數（等值節流防護生效／`fullscreen` 值改變時正確呼叫）。
- `didChangeAppLifecycleState(AppLifecycleState.resumed)`：widget test 用 `tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed)` 觸發，驗證 `_lastAppliedFullscreen` 被重置後 `_applySystemUiMode()` 確實再次呼叫 `elinkbook/fullscreen` 頻道，即使 `resolved.fullscreen` 值前後相同也要再呼叫一次。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- 真機：三種格式（EPUB 流式/FXL/PDF）各自開啟全螢幕模式，確認系統狀態列/導覽列消失、App 自己的頁首/頁尾/按鈕不受影響；關閉開關後系統列恢復；離開閱讀畫面（返回書架）後系統列恢復正常，不外溢到其他畫面；開啟全螢幕模式後將 App 切到背景再切回前台，確認系統列仍隱藏（未被 OS 重新顯示後卡住）。

---

## Issue 2：刪除書籍

**Status:** ✅ 已完成

**依賴：** 無

**描述：**

`LibraryRepository.deleteBook(String id)`（`library_repository.dart:10`，實作於 `sqlite_library_repository.dart:459`）早已存在，但全專案沒有任何 UI 呼叫它——目前使用者完全無法從畫面上刪除書籍。「刪除分類」（`deleteGroup`）已有完整 UI（`library_group_management_dialog.dart`），本工單不涉及。完整介面定義見 `spec.md`「功能 ② 刪除書籍」。

- **`app/lib/screens/library_screen.dart`**：`_buildSelectionAppBar()`（`library_screen.dart:498-518`）新增第二個 `IconButton`（`Key('library_delete_books_button')`，icon `Icons.delete`，緊鄰既有「移動到分類」按鈕），呼叫新方法 `_deleteSelectedBooks()`。新增 `_confirmDeleteBooks(int count)` 對話框（比照既有 `_confirmAutoGroupByFolderName()` 的 `showDialog` 寫法，文案需明確提示「將一併刪除已勾選書籍的書籤、劃線與備註，此操作無法復原」）。新增 `_deleteSelectedBooks()`（比照既有 `_moveSelectedBooksToGroup()` 結構：確認對話框→立即 `_exitSelectionMode()`→逐筆呼叫 `widget.repository.deleteBook(book.id)`→對 `book.filePath`／`book.coverPath` 各自用 `File(path).existsSync()` 判斷後才刪除→完成後 `_loadBooks()`）。
- **不修改 `LibraryRepository` 介面**——`deleteBook()` 已存在，檔案清理屬於 UI 層職責，不下放進 repository。
- **重要事實**：`filePath` 不一定是本機複本——只有持久化 URI 權限授權失敗、或原始 URI 無可辨識副檔名時才會落地成本機複本（`book_import_service_impl.dart:190-194`），其餘情況維持原始 `content://` URI。`coverPath` 則永遠是本機複本。`existsSync()` 防護對兩種來源都安全：本機複本會被正確刪除，`content://` 參照（`dart:io File` 永遠判定為不存在）會被安全跳過，不觸碰使用者原始檔案，實作時不需要分辨來源。

**單元測試要求：**
- `_confirmDeleteBooks`/`_deleteSelectedBooks`：widget test，比照既有 `_moveSelectedBooksToGroup` 測試模式——mock `LibraryRepository` 驗證 `deleteBook()` 對每個已選取 id 各被呼叫一次、取消對話框時不呼叫、確認對話框文案包含選取本數。
- 檔案清理邏輯：用 `Directory.systemTemp` 建立暫存檔驗證 `existsSync()` 防護（存在的檔案被刪除、不存在的路徑—含模擬 `content://` 字串—被安全跳過）。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- 真機：長按進入選取模式勾選 1 本或多本書，點擊刪除→確認對話框正確顯示選取本數→確認後書籍從書架消失、對應的書籤/劃線/備註（若有）一併清除、裝置上對應檔案（若為本機複本）被刪除；取消對話框不刪除任何內容。

---

## Issue 3：分類 2×2 拼貼格取代分類 Chip 列

**Status:** ✅ 已完成

**依賴：** 無

**描述：**

現有水平分類 Chip 列（`_buildGroupTabs()`，`library_screen.dart:520-562`，含「全部」篩選與「管理分類」入口）整個移除，改為每個分類顯示成一格：2×2 拼貼該分類前 4 本書封面＋分類名稱/書籍總數，固定排在書籍清單最前面。點擊拼貼格進入該分類的專屬篩選畫面（重用 `LibraryScreen` 本身，新增 `groupFilter` 建構參數）。本工單範圍涵蓋移除舊 UI、新增拼貼格顯示、導覽、管理分類入口搬遷——四者因果耦合（拿掉舊 Chip 列必須同時提供篩選/管理分類的替代入口，否則是既有能力的回歸），不可分批上線。完整型別/介面定義（含程式碼草案）見 `spec.md`「功能 ③ 分類 2×2 拼貼格」，此處僅摘要要點：

- `LibraryScreen` 新增建構參數 `final String? groupFilter;`（`null`＝頂層書架模式；非 `null`＝單一分類篩選模式，隱藏拼貼格區塊、AppBar 標題顯示分類名稱、無「管理分類」入口）。`_groupFilter` 改為在 `initState()` 由 `widget.groupFilter` 一次性初始化，畫面生命週期內不再變動；既有 `_changeGroupFilter()` 直接刪除（分類 Chip 移除後不再被任何 UI 呼叫）。
- 新增 `_GroupTile`（`name`／`previewBooks`／`totalCount`）與 `_buildGroupTiles()`：依目前已排序的 `_books` 依 `groupName` 分組、依 `_groups`（`name ASC`）排序、「未分類」強制排最後，且對 `book.groupName` 不在 `_groups` 快照中的孤兒書籍有兜底桶收留（避免書籍從書架消失，見 `spec.md` 審查修正）。
- 新增 `_GroupGridTile`（格狀檢視，2×2 拼貼，`GridView.count` 須明確 `padding: EdgeInsets.zero`，否則會被自動吃入 `MediaQuery.padding` 擠壓變形）／`_GroupListTile`（列表檢視，橫向 4 縮圖列樣式）；兩者 `onTap` 型別為 `VoidCallback?`，`_inSelectionMode == true` 時傳 `null`（比照既有 `_buildGroupTabs()` 對 Chip/ActionChip 在選取模式時停用互動的既有慣例，避免選取模式下誤觸拼貼格導致狀態錯亂）。
- `_buildBookList()` 把拼貼格與書籍合併進同一個 `itemBuilder` index 空間（拼貼格在前，書籍在後，`crossAxisCount` 邏輯不受影響）。
- 新增 `_openGroupFilteredView(String groupName)`：`Navigator.push` 新的 `LibraryScreen` 實例，`groupFilter: groupName`，其餘建構參數原樣透傳。
- `_buildNormalAppBar()`：`title` 依 `widget.groupFilter` 決定；「管理分類」入口搬到這裡的 `actions`（`Key('library_manage_groups_button')`），僅 `groupFilter == null` 時顯示。
- `_openManageGroupsDialog()`（`library_screen.dart:313-332`）內「篩選中的分類已被刪除時重置為全部」的既有安全網邏輯可移除（`groupFilter` 已固定於畫面生命週期，管理分類入口只出現在頂層畫面）。

**單元測試要求：**
- `_buildGroupTiles()`：純函式單元測試（分組正確性、`name ASC` 排序、「未分類」強制排最後、只保留非空分類、`previewBooks` 正確截取前 4 筆且保留原排序、孤兒 `groupName` 兜底收留不消失）。
- `_GroupGridTile`/`_GroupListTile`：widget test（不足 4 本時空格顯示正確、名稱＋數量文字正確、tap 觸發 `onTap`、`onTap` 為 `null` 時點擊無反應且不拋例外）。
- `_openGroupFilteredView`：widget test（tap 拼貼格後，`Navigator` 推入的新 `LibraryScreen.groupFilter` 等於分類名稱；新畫面 AppBar 標題顯示分類名稱、不顯示拼貼格區塊、不顯示「管理分類」按鈕）。
- `_buildBookList` 合併 index 空間：widget test（`itemCount` 等於拼貼格數＋書籍數；拼貼格永遠排在書籍之前）。
- 選取模式互動：widget test 驗證進入選取模式（長按任一本書）後，拼貼格的 `onTap` 為 `null`（點擊不觸發 `Navigator.push`，`_selectedBookIds` 與選取工具列狀態不受影響）。
- **審查修正——既有測試會壞掉，需同步處理**：`app/test/screens/library_screen_test.dart` 既有針對 `library_group_tabs`／`library_group_tab_all`／`library_group_tab_${name}`／`library_group_manage_button` 的測試全部失效，需移除／改寫為針對新 key 的測試；既有 grid 欄數測試（epic-18 Issue 3）若用「第 N 個 item 一定是某本書」的索引假設斷言，需調整索引偏移量（`groupTiles.length`）。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- 真機：格狀/列表兩種檢視模式下，分類拼貼格皆正確顯示（2×2 封面/橫向 4 縮圖＋名稱＋數量，不足 4 本時空格為中性佔位、不拉伸/不重複封面）；點擊拼貼格進入該分類篩選畫面，畫面內排序/檢視模式切換/長按多選/刪除功能皆正常，返回鍵可退回書架；書架頂層「管理分類」入口功能與原本一致；長按書籍進入選取模式時拼貼格點擊無反應。

---
