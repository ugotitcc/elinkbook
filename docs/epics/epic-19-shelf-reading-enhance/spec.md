# Epic 19 — 書架與閱讀體驗強化：規格 (Spec)

本文件依 `design.md` 已確認的決策，定義三項功能的核心介面/型別，自此成為本 Epic 的唯一事實來源。三項功能彼此獨立，分節撰寫；`issues.md` 拆解工單時可各自獨立排入。

## 功能 ① 全螢幕模式

### 模組 (Modules)

- **`app/lib/reader/book_reader_prefs.dart`（異動）**——新增 `final bool? fullscreen` 欄位（`null`＝未覆寫，`resolve()` 決成 `false`；比照既有 `showHeader`/`showFooter` 的 nullable-bool 慣例，無全域預設層）。`toMap()`／`fromMap()`／`copyWith()`／`==`／`hashCode` 皆需同步新增此欄位。
- **`app/lib/reader/resolved_preferences.dart`（異動）**——新增 `final bool fullscreen`（non-nullable，比照既有 `showHeader`/`showFooter` 欄位——已有明確安全預設值 `false`）。
- **`app/lib/reader/reader_prefs_manager_impl.dart`（異動）**——`resolve()` 內新增 `fullscreen: book.fullscreen ?? false,`（緊鄰既有 `showHeader: book.showHeader ?? true,`／`showFooter: book.showFooter ?? true,`，`reader_prefs_manager_impl.dart:179-180`）。
- **`app/lib/library/sqlite_library_repository.dart`（異動）**——schema `version` 由 14 提升為 15。**兩處都要改，缺一會導致全新安裝崩潰**（`/superpowers:requesting-code-review` 審查 Critical 1）：
  1. `_createBookReaderPrefsTable()`（`sqlite_library_repository.dart:190-222`）的 `CREATE TABLE` 陳述式本身直接加上 `fullscreen INTEGER`（比照該陳述式已包含 `show_header`/`column_mode`/`margin_top` 等既有慣例——這是「一次到位、含所有現行欄位」的建表陳述式，全新安裝走 `onCreate` → 這個函式，不會經過 `onUpgrade`；若只改 `onUpgrade`，全新安裝的表會永遠缺這個欄位，讀寫時直接拋出 `no such column: fullscreen`）。
  2. `onUpgrade` 內既有 `if (oldVersion < 2) {...} else { ... if (oldVersion < 14) { await _addMarginColumns(db); } }` 分支內追加 `if (oldVersion < 15) { await _addFullscreenColumn(db); }`（放在 else 分支內、緊接 `_addMarginColumns` 之後，供既有裝置——`oldVersion >= 2`——升級用）。
- **`app/lib/screens/reader_settings_sheet.dart`／`app/lib/screens/pdf_settings_sheet.dart`／`app/lib/screens/fxl_settings_sheet.dart`（異動，三者皆同步新增）**——各自新增 `late bool _fullscreen;`（`initState`／`didUpdateWidget`：`widget.prefs.fullscreen ?? false`），一個 `SwitchListTile`（`key: Key('<prefix>_settings_fullscreen')`，標籤「全螢幕模式」，比照既有 `show_header`/`show_footer`/`dual_page_cover_alone` 開關寫法），`_notifyChanged()` 帶入 `fullscreen: _fullscreen`。`fxl_settings_sheet.dart:9` 既有註解「為未來 FR-42（全螢幕顯示開關）預留擴充空間」即是此欄位的既定落點（本欄位範圍比 FR-42 更廣，見 `CONTEXT.md`「全螢幕模式」詞條，但沿用同一個預留位置）。
- **【審查修正——技術方案變更】原設計呼叫 `SystemChrome.setEnabledSystemUIMode()` 已確認在本專案的 Android 建置設定下無效**：直接查證 Flutter SDK（3.41.9）`system_chrome.dart:601-608` 官方文件——「若 targetSdk 為 API 36 以上，App 一律強制使用 `SystemUiMode.edgeToEdge`，呼叫其他模式一律被忽略、沒有退出方法」；本專案 `app/android/app/build.gradle.kts:16,41` 的 `compileSdk`/`targetSdk` 皆直接吃 `flutter.compileSdkVersion`/`flutter.targetSdkVersion`，目前安裝的 Flutter SDK 這兩個預設值皆為 36。故改採 Android 官方建議、繼任 `SystemUiMode` 的現代 API `WindowInsetsControllerCompat`——運作在原生 `Window`/`View` 層級，不經過 Flutter 引擎的 `SystemUiMode` 限制，透過新增的 `elinkbook/fullscreen` platform channel（比照既有 `elinkbook/volume_key`／`elinkbook/app_info` 頻道慣例）呼叫。
- **`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`（異動）**——`configureFlutterEngine()` 內新增 `MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "elinkbook/fullscreen")`，處理 `"setEnabled"`（`Boolean` 參數）：透過 `WindowCompat.getInsetsController(window, window.decorView)` 取得 controller，`true` 時設定 `systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE` 後呼叫 `hide(WindowInsetsCompat.Type.systemBars())`，`false` 時呼叫 `show(WindowInsetsCompat.Type.systemBars())`。
- **`app/android/app/build.gradle.kts`（異動）**——新增 `implementation("androidx.core:core-ktx:1.15.0")`（`WindowCompat`/`WindowInsetsControllerCompat`/`WindowInsetsCompat` 所在套件；本專案既有 `androidx.fragment:fragment-ktx:1.8.9` 雖已transitively 帶入相容版本的 `androidx.core`，但明確宣告版本比依賴未宣告的傳遞依賴更穩健，比照本檔案其餘依賴皆明確宣告版本號的既有慣例）。
- **`app/lib/screens/reader_screen.dart`（異動）**——新增 `static const _fullscreenChannel = MethodChannel('elinkbook/fullscreen');`（比照既有 `_volumeKeyChannel` 宣告方式，`reader_screen.dart:51`）；新增 `bool? _lastAppliedFullscreen;`（比照既有 `_lastAppliedOrientation`，`reader_screen.dart:239`），新增 `_applySystemUiMode()` 方法（比照既有 `_applyScreenOrientation()`，`reader_screen.dart:389-397`，改呼叫 `_fullscreenChannel.invokeMethod('setEnabled', resolved.fullscreen)`），在 `_resolved` 每次重新賦值後的既有呼叫點追加呼叫（即目前呼叫 `_applyScreenOrientation()` 的所有位置：`initState().then()`〔line 267〕、`_handlePrefsChanged()`〔line 441〕——**只有這兩處**，`_handleCropRectComputed`/`_handleCropRectSelected` 不呼叫，因為那兩條路徑不可能改變 `fullscreen` 欄位，比照 `_applyScreenOrientation()` 現有呼叫點範圍）；`dispose()`（`reader_screen.dart:301-314`）新增系統列還原呼叫，緊鄰既有 `SystemChrome.setPreferredOrientations(const [])`（line 313）。既有 `didChangeAppLifecycleState()`（`reader_screen.dart:322-326`，目前只處理 `AppLifecycleState.paused`）新增一個 `AppLifecycleState.resumed` 分支（見下方「介面」段落——App 從背景恢復時系統列可能被 OS 自動重新顯示，需要強制重套用，不能只靠等值防護，`/superpowers:requesting-code-review` 審查 Critical 2）。

### 資料模型 (Data Model)

```sql
-- _createBookReaderPrefsTable()：CREATE TABLE 陳述式本身新增這一欄
-- （與 show_header/column_mode/margin_top 等既有欄位並列，非另外 ALTER）
fullscreen INTEGER
```

```sql
-- onUpgrade，供 oldVersion >= 2 的既有裝置升級用
ALTER TABLE book_reader_prefs ADD COLUMN fullscreen INTEGER; -- nullable：NULL=未覆寫(視為 false)、0=false、1=true
```

### 介面 (Interfaces)

```kotlin
// MainActivity.kt configureFlutterEngine() 內新增
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "elinkbook/fullscreen")
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "setEnabled" -> {
                val enabled = call.arguments as Boolean
                val controller = WindowCompat.getInsetsController(window, window.decorView)
                if (enabled) {
                    controller.systemBarsBehavior =
                        WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    controller.hide(WindowInsetsCompat.Type.systemBars())
                } else {
                    controller.show(WindowInsetsCompat.Type.systemBars())
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
```

```dart
// reader_screen.dart —— 比照既有 _applyScreenOrientation() 的節流寫法，
// 避免偏好設定頻繁變動（例如快速切換開關）時重複呼叫 platform channel。
void _applySystemUiMode() {
  final resolved = _resolved;
  if (resolved == null) return;
  if (resolved.fullscreen == _lastAppliedFullscreen) return;
  _lastAppliedFullscreen = resolved.fullscreen;
  _fullscreenChannel.invokeMethod('setEnabled', resolved.fullscreen);
}
```

```dart
// reader_screen.dart 既有 didChangeAppLifecycleState()——新增 resumed 分支。
// App 從背景恢復時，Android 可能已自動重新顯示系統列，此時
// _lastAppliedFullscreen 仍等於 resolved.fullscreen（值本身沒變），
// _applySystemUiMode() 的等值節流防護會誤判「不需要重新套用」而略過
// platform channel 呼叫。故 resumed 時強制清空節流快取、無條件重新套用一次。
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    _writeCurrentPosition();
  } else if (state == AppLifecycleState.resumed) {
    _lastAppliedFullscreen = null;
    _applySystemUiMode();
  }
}
```

`dispose()` 新增（不論進入閱讀器時是否開啟過全螢幕模式，離開時一律強制還原，比照 `SystemChrome.setPreferredOrientations(const [])` 既有的無條件還原寫法，不判斷 `_lastAppliedFullscreen`）：

```dart
_fullscreenChannel.invokeMethod('setEnabled', false);
```

**與既有機制的邊界（見 `design.md`／`CONTEXT.md`「全螢幕模式」詞條）**：`_applySystemUiMode()` 只透過 `elinkbook/fullscreen` 頻道控制原生系統列，不讀取／不影響 `_chromeVisible`（沉浸模式）或 `resolved.showHeader`/`resolved.showFooter`——三套機制在程式碼層級完全獨立，互不呼叫對方。

### 測試決策 (Testing Decisions)

- `BookReaderPrefs.fullscreen` 的 `toMap`/`fromMap`/`copyWith`/`==`/`hashCode`：`flutter test` 單元測試，比照既有 `showHeader`/`showFooter` 欄位新增時的既有測試模式。
- 三個設定面板新增的 `SwitchListTile`：widget test，比照既有 `reader_settings_show_header`/`pdf_settings_show_footer` 的既有測試模式（tap 開關→驗證 `onChanged` 回報的 `BookReaderPrefs.fullscreen` 值）。
- `_applySystemUiMode()`／`dispose()` 的 `elinkbook/fullscreen` 頻道呼叫：用 `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('elinkbook/fullscreen'), ...)` 記錄 `MethodCall`（比照既有 `elinkbook/volume_key` 頻道的既有測試模式，`reader_screen_test.dart:2748-2760`），驗證等值節流防護生效／`fullscreen` 值改變時正確呼叫 `setEnabled` 且參數正確。「系統狀態列/導覽列是否真的從畫面消失」無法在 widget test 環境驗證原生 `WindowInsetsController` 的實際效果，需真機人工視覺確認（沿用本專案既有的兩層測試架構慣例，見 `CLAUDE.md`「兩層測試架構」）。
- `didChangeAppLifecycleState(AppLifecycleState.resumed)`：widget test 用 `tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed)` 觸發，驗證 `_lastAppliedFullscreen` 被重置後 `_applySystemUiMode()` 確實再次呼叫 `elinkbook/fullscreen` 頻道（即使 `resolved.fullscreen` 值前後相同也要再呼叫一次）；真機驗收項目新增「開啟全螢幕模式→切到背景→切回前台→系統列仍隱藏」。

---

## 功能 ② 刪除書籍

### 模組 (Modules)

- **`app/lib/screens/library_screen.dart`（異動）**——`_buildSelectionAppBar()`（`library_screen.dart:498-518`）新增第二個 `IconButton`（緊鄰既有「移動到分類」按鈕），呼叫新方法 `_deleteSelectedBooks()`；新增 `_confirmDeleteBooks(int count)` 對話框方法（比照既有 `_confirmAutoGroupByFolderName()` 的 `showDialog` 寫法）與 `_deleteSelectedBooks()` 方法（比照既有 `_moveSelectedBooksToGroup()` 的結構：立即退出選取模式、逐筆處理、完成後 `_loadBooks()`）。
- **不修改 `LibraryRepository` 介面**——`deleteBook(String id)` 已存在（`library_repository.dart:10`），本功能不需要新增任何 repository 方法；檔案清理屬於 UI 層呼叫端的職責（比照 `_moveSelectedBooksToGroup()` 直接呼叫 `widget.repository.updateBook()` 的既有分工，不把 UI 層邏輯下放進 repository）。

### 介面 (Interfaces)

【審查修正——已合併程式碼審查後的規格更新，`review-issue-2.md`／`plan-issue-2.md` 已記錄，此處回填同步】實際合併的程式碼與本節原始草稿相比有三處差異，皆已審查通過：

1. **`await File(...).delete()` → `File(...).deleteSync()`**：原始草稿用非同步 `delete()`，實作改為同步 `deleteSync()`。理由：widget test 的 `AutomatedTestWidgetsFlutterBinding` fake zone 無法讓真實 `dart:io` 非同步 I/O 的 `Future` 完成，若維持 `await delete()`，每個涉及刪除的測試都必須用 `tester.runAsync()` 包住確認刪除的 tap 動作、並搭配輪詢等待逾時；`deleteSync()` 是同步系統呼叫（底層即 `unlink`，屬中繼資料操作，不受檔案大小影響，效能風險低），可直接在 fake zone 內完成，測試因此不需要 `runAsync`/輪詢。此為程式碼審查（`plan-issue-2-code-review.md` Important 項目）後由作者確認保留的決策，非未經評估的規格漂移。
2. **新增 `if (!mounted) return;`**：`await _confirmDeleteBooks(...)` 這個 dialog await 之後、`_exitSelectionMode()`（會觸碰 state）之前，比照本檔案內 `_openManageGroupsDialog()` 等既有慣例補上此檢查（此項為 `plan-issue-2.md` 撰寫階段的計畫審查已要求，先前未回填進本檔案，此處一併同步）。
3. **檔案刪除包 `try-catch`**：單一檔案刪除失敗（例如被鎖定、權限異常）不應中斷整個批次刪除迴圈——`deleteBook()`（資料庫紀錄）已於迴圈內该筆書籍处理時完成，迴圈仍要繼續處理其餘已選取書籍並跑到最後的 `_loadBooks()`（同樣是計畫審查階段要求、此處回填）。

```dart
Future<bool?> _confirmDeleteBooks(int count) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('刪除書籍'),
      content: Text(
        '將刪除已選取的 $count 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('library_delete_confirm_button'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('刪除'),
        ),
      ],
    ),
  );
}

Future<void> _deleteSelectedBooks() async {
  final selectedIds = _selectedBookIds;
  final books = _books;
  if (selectedIds == null || selectedIds.isEmpty || books == null) return;
  final confirmed = await _confirmDeleteBooks(selectedIds.length);
  if (confirmed != true) return;
  // await 跳出 dialog 的操作之後、觸碰 state 之前先確認 widget 是否仍在
  // 畫面上（比照既有 _openManageGroupsDialog()）。
  if (!mounted) return;
  // 比照既有 _moveSelectedBooksToGroup()：先退出選取模式，避免刪除迴圈
  // 執行期間使用者重複點擊觸發本方法。
  _exitSelectionMode();
  for (final book in books) {
    if (!selectedIds.contains(book.id)) continue;
    await widget.repository.deleteBook(book.id);
    // existsSync() 防護對 content:// 來源的 filePath 安全（見 design.md
    // 調查結論——content:// 字串永遠不會判定為存在的本機路徑，故此處
    // 不需要分辨 filePath 是本機複本還是原始外部檔案參照）。單一檔案刪除
    // 失敗不應中斷整個批次迴圈，故用 try-catch 包住。
    try {
      // 使用 deleteSync()（同步系統呼叫）而非 await delete()：widget test
      // 的 fake zone 無法完成真實 I/O 的 Future，deleteSync() 不受此限制。
      if (File(book.filePath).existsSync()) {
        File(book.filePath).deleteSync();
      }
      final coverPath = book.coverPath;
      if (coverPath != null && File(coverPath).existsSync()) {
        File(coverPath).deleteSync();
      }
    } catch (_) {
      // 檔案刪除失敗時靜默略過，不中斷主流程；資料庫紀錄已刪除，殘留
      // 檔案不影響功能正確性。
    }
  }
  await _loadBooks();
}
```

`_buildSelectionAppBar()` 新增（緊接既有「移動到分類」`IconButton` 之後）：

```dart
IconButton(
  key: const Key('library_delete_books_button'),
  icon: const Icon(Icons.delete),
  tooltip: '刪除',
  onPressed: count == 0 ? null : _deleteSelectedBooks,
),
```

### 測試決策 (Testing Decisions)

- `_confirmDeleteBooks`/`_deleteSelectedBooks`：widget test，比照既有 `_moveSelectedBooksToGroup` 的既有測試模式——mock `LibraryRepository` 驗證 `deleteBook()` 對每個已選取 id 各被呼叫一次、取消對話框時不呼叫、確認對話框文案包含選取本數。
- 檔案清理邏輯：用 `Directory.systemTemp` 建立暫存檔驗證 `existsSync()` 防護（存在的檔案被刪除、不存在的路徑—含模擬 `content://` 字串—被安全跳過），不需要真機。暫存檔的建立/寫入（`Directory.systemTemp.createTemp()`／`writeAsBytes()`）仍需 `tester.runAsync()` 包住（fake zone 無法完成真實檔案系統 I/O）；但確認刪除的 tap 動作本身不需要——`_deleteSelectedBooks()` 改用 `deleteSync()`（見上方「介面」章節的審查修正說明）後，刪除在同一個同步延續內完成，不需額外的 `runAsync`/輪詢等待。

---

## 功能 ③ 分類 2×2 拼貼格

### 模組 (Modules)

- **`app/lib/screens/library_screen.dart`（異動，範圍最大）**：
  - `LibraryScreen` 新增建構參數 `final String? groupFilter;`（`null`＝頂層書架模式：顯示分類拼貼格區塊＋AppBar「管理分類」入口；非 `null`＝單一分類篩選模式：隱藏分類拼貼格區塊、AppBar 標題改顯示分類名稱、無「管理分類」入口，系統預設的 `Navigator` 返回鍵不受影響）。
  - 移除既有 `_buildGroupTabs()`（`library_screen.dart:520-562`，含「全部」與「管理分類」`ChoiceChip`/`ActionChip`）與 `build()` 內對它的呼叫（`library_screen.dart:354`）。
  - 移除既有可變的 `_groupFilter` 切換路徑：`_changeGroupFilter()`（`library_screen.dart:221-224`）不再被任何 UI 呼叫（分類 Chip 已移除），直接刪除；`_groupFilter` 改為在 `initState()` 一次性由 `widget.groupFilter` 初始化，固定於整個畫面生命週期（見「介面」段落）。
  - 新增 `_GroupTile`（private 資料類別）與 `_buildGroupTiles()`（分組/排序/截取前 4 筆）。
  - 新增 `_GroupGridTile`／`_GroupListTile`（private widget，2×2 拼貼／橫向 4 縮圖列表列）。
  - `_buildBookList()` 改為把分類格與書籍合併進同一個 `itemBuilder` 的 index 空間（分類格在前）。
  - 新增 `_openGroupFilteredView(String groupName)`：`Navigator.push` 一個新的 `LibraryScreen` 實例，`groupFilter: groupName`，其餘建構參數原樣透傳。
  - `_buildNormalAppBar()`：`title` 依 `widget.groupFilter` 決定（`書架` 或分類名稱）；「管理分類」從 Chip 列移到這裡的 `actions`，僅在 `widget.groupFilter == null` 時顯示。
  - `_openManageGroupsDialog()`（`library_screen.dart:313-332`）內「篩選中的分類已被刪除時重置為全部」這段既有安全網邏輯可以移除——`groupFilter` 已固定於畫面生命週期、且「管理分類」入口只出現在 `groupFilter == null` 的頂層畫面，不會再發生「使用者正在檢視的分類被自己刪除」這個情境（若使用者在分類篩選畫面裡透過其他路徑刪除當前分類，屬於分頁式導覽的既有已知邊界情況，非本功能新增風險）。

### 型別 (Types)

```dart
/// 單一分類在書架分類拼貼格上的顯示資料，純畫面呈現用途，不持久化、不
/// 跨檔案共用，故不建成 library/models 底下的公開模型。
class _GroupTile {
  final String name;
  final List<Book> previewBooks; // 最多 4 本，依目前排序結果順序截取前 4 筆
  final int totalCount;
  const _GroupTile({
    required this.name,
    required this.previewBooks,
    required this.totalCount,
  });
}
```

```dart
/// 依目前已載入的 [books]（已依 _sortBy 排序）與 [_groups]（name ASC，
/// 「未分類」強制排最後，見 design.md 決策）分組，只保留非空分類。
///
/// 【審查修正】`_groups` 是 `_loadGroups()` 讀取的記憶體快照，既有的
/// `_loadGroups()` 錯誤處理註解本身承認暫時性讀取失敗時會保留舊快照
/// （`library_screen.dart:91-97`）——故 `book.groupName` 理論上可能不在
/// 目前的 `_groups` 清單中、也不是 `BookGroup.uncategorized`（`_groups`
/// 落後於 `_books` 的情境）。若只依 `_groups` 組出 `orderedNames`，這些
/// 書籍會被整批漏掉、從書架上「消失」而非只是分類格顯示不完整，後果比
/// 拼貼格排序錯誤嚴重得多，故補一個兜底桶收留所有未被涵蓋的
/// `groupName`，確保 `byGroup` 裡的書一定會出現在某個拼貼格。
List<_GroupTile> _buildGroupTiles(List<Book> books) {
  final byGroup = <String, List<Book>>{};
  for (final book in books) {
    byGroup.putIfAbsent(book.groupName, () => []).add(book);
  }
  final orderedNames = [
    for (final group in _groups)
      if (group.name != BookGroup.uncategorized) group.name,
    BookGroup.uncategorized,
    for (final name in byGroup.keys)
      if (name != BookGroup.uncategorized &&
          !_groups.any((g) => g.name == name))
        name,
  ];
  return [
    for (final name in orderedNames)
      if (byGroup[name]?.isNotEmpty ?? false)
        _GroupTile(
          name: name,
          previewBooks: byGroup[name]!.take(4).toList(),
          totalCount: byGroup[name]!.length,
        ),
  ];
}
```

### 介面 (Interfaces)

```dart
// LibraryScreen 建構參數新增
class LibraryScreen extends StatefulWidget {
  // ...既有欄位不變...
  final String? groupFilter;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
    this.groupFilter,
  });
}
```

```dart
// _LibraryScreenState.initState()：_groupFilter 只在此處由 widget.groupFilter
// 初始化一次，畫面生命週期內不再變動（分類切換一律靠返回上一頁＋點擊另一
// 個拼貼格，見 design.md 決策 Q12/Q21）。
@override
void initState() {
  super.initState();
  _groupFilter = widget.groupFilter;
  _initialize();
}
```

```dart
void _openGroupFilteredView(String groupName) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => LibraryScreen(
        repository: widget.repository,
        importService: widget.importService,
        prefsManager: widget.prefsManager,
        bookmarksRepository: widget.bookmarksRepository,
        highlightsRepository: widget.highlightsRepository,
        notesRepository: widget.notesRepository,
        currentTheme: widget.currentTheme,
        isEinkMode: widget.isEinkMode,
        onThemeChanged: widget.onThemeChanged,
        onEinkModeChanged: widget.onEinkModeChanged,
        groupFilter: groupName,
      ),
    ),
  );
}
```

```dart
// _buildBookList()：分類格與書籍合併進同一個 index 空間，分類格在前
// （design.md 決策：分類格固定排最前面）。
Widget _buildBookList(List<Book> books) {
  final selectedIds = _selectedBookIds;
  final groupTiles =
      widget.groupFilter == null ? _buildGroupTiles(books) : const <_GroupTile>[];
  final itemCount = groupTiles.length + books.length;
  Widget itemBuilder(BuildContext context, int index, {required bool isGrid}) {
    if (index < groupTiles.length) {
      final tile = groupTiles[index];
      // 【審查修正】選取模式進行中時，分類格不可觸發導覽（onTap 傳
      // null），比照既有 _buildGroupTabs() 對 ChoiceChip/ActionChip 在
      // _inSelectionMode 時一律 onSelected/onPressed: null 的既有慣例
      // ——否則使用者長按多選書籍時誤觸分類格，會帶著選取狀態被推入
      // 另一個 LibraryScreen 實例，選取列顯示與計數會與使用者預期不符。
      final onTap =
          _inSelectionMode ? null : () => _openGroupFilteredView(tile.name);
      return isGrid
          ? _GroupGridTile(tile: tile, onTap: onTap)
          : _GroupListTile(tile: tile, onTap: onTap);
    }
    final book = books[index - groupTiles.length];
    return isGrid
        ? _BookGridTile(
            book: book,
            selectionMode: _inSelectionMode,
            selected: selectedIds?.contains(book.id) ?? false,
            onTap: () => _onBookTap(book),
            onLongPress: () => _onBookLongPress(book),
          )
        : _BookListTile(
            book: book,
            selectionMode: _inSelectionMode,
            selected: selectedIds?.contains(book.id) ?? false,
            onTap: () => _onBookTap(book),
            onLongPress: () => _onBookLongPress(book),
          );
  }
  if (_viewMode == LibraryViewMode.grid) {
    final orientation = MediaQuery.orientationOf(context);
    final crossAxisCount = orientation == Orientation.landscape ? 4 : 3;
    return GridView.builder(
      key: const Key('library_grid_view'),
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.62,
        crossAxisSpacing: 8,
        mainAxisSpacing: 12,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) => itemBuilder(context, index, isGrid: true),
    );
  }
  return ListView.builder(
    key: const Key('library_list_view'),
    itemCount: itemCount,
    itemBuilder: (context, index) => itemBuilder(context, index, isGrid: false),
  );
}
```

```dart
// _GroupGridTile：2×2 拼貼＋分類名稱/數量，重用既有 _BookCover。
// onTap 為 null 時（選取模式進行中）InkWell 自動停用點擊反饋，比照
// Flutter 既有「null 停用互動」慣例，與 _buildGroupTabs() 舊寫法一致。
class _GroupGridTile extends StatelessWidget {
  final _GroupTile tile;
  final VoidCallback? onTap;
  const _GroupGridTile({required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('group_tile_${tile.name}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              // 【審查修正】GridView 是 BoxScrollView 的子類，padding 為
              // null 時會自動吃進 MediaQuery.of(context).padding（垂直
              // 捲動吃 top/bottom safe area，見 Flutter SDK
              // scroll_view.dart 的 BoxScrollView.buildSlivers()）；這個
              // 巢狀在拼貼格內的小型 GridView 若不明講 padding: EdgeInsets.zero，
              // 會意外套上裝置狀態列/導覽列高度的內距，把 2×2 封面擠壓變形。
              padding: EdgeInsets.zero,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(
                4,
                (i) => i < tile.previewBooks.length
                    ? _BookCover(book: tile.previewBooks[i])
                    : ColoredBox(color: Colors.grey.shade200),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${tile.name} (${tile.totalCount})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
```

```dart
// _GroupListTile：橫向 4 張小縮圖＋名稱＋數量，列表檢視專用樣式
// （design.md 決策：不強行套用 2×2 方形拼貼於列表列）。
class _GroupListTile extends StatelessWidget {
  final _GroupTile tile;
  final VoidCallback? onTap; // null＝選取模式進行中，停用點擊（同 _GroupGridTile）
  const _GroupListTile({required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('group_tile_${tile.name}'),
      leading: SizedBox(
        width: 4 * 32,
        height: 48,
        child: Row(
          children: List.generate(
            4,
            (i) => SizedBox(
              width: 32,
              height: 48,
              child: i < tile.previewBooks.length
                  ? _BookCover(book: tile.previewBooks[i])
                  : ColoredBox(color: Colors.grey.shade200),
            ),
          ),
        ),
      ),
      title: Text(tile.name),
      subtitle: Text('${tile.totalCount} 本'),
      onTap: onTap,
    );
  }
}
```

```dart
// _buildNormalAppBar()：標題與「管理分類」入口依 groupFilter 調整。
AppBar _buildNormalAppBar(List<Book>? books) {
  return AppBar(
    title: Text(widget.groupFilter ?? '書架'),
    actions: [
      // ...既有主題圓點／E-Ink 切換／排序／檢視模式／匯入按鈕不變...
      if (widget.groupFilter == null)
        IconButton(
          key: const Key('library_manage_groups_button'),
          icon: const Icon(Icons.category),
          tooltip: '管理分類',
          onPressed: _openManageGroupsDialog,
        ),
      // ...既有設定按鈕不變...
    ],
  );
}
```

### 已知測試影響 (Known Test Impact)

- `app/test/screens/library_screen_test.dart` 既有針對 `library_group_tabs`／`library_group_tab_all`／`library_group_tab_${name}`／`library_group_manage_button`（原 Chip 列上的 key）的測試會全部失效，需要在實作階段同步移除／改寫為針對 `_GroupGridTile`/`_GroupListTile`/`library_manage_groups_button` 的新測試。
- `_buildBookList` 的既有 grid 欄數測試（epic-18 Issue 3 新增的 4 個測試，`library_screen_test.dart`）需要確認在「有分類拼貼格＋書籍混合排列」的新 `itemCount` 下依然通過——分類格與書籍共用同一個 `crossAxisCount`，欄數邏輯本身不受影響，但既有測試若用「第 N 個 item 一定是某本書」的索引假設斷言，需要調整索引偏移量（`groupTiles.length` 位移）。

### 測試決策 (Testing Decisions)

- `_buildGroupTiles()`：純函式單元測試（分組正確性、`name ASC` 排序、「未分類」強制排最後、只保留非空分類、`previewBooks` 正確截取前 4 筆且保留原排序、【審查修正】`book.groupName` 不在 `_groups` 快照中且非「未分類」時仍會被兜底桶收留、不會從結果中消失）。
- `_GroupGridTile`/`_GroupListTile`：widget test（不足 4 本時空格顯示正確、名稱＋數量文字正確、tap 觸發 `onTap`、【審查修正】`onTap` 為 `null` 時點擊無反應且不拋例外）。
- `_openGroupFilteredView`：widget test（tap 分類格後，`Navigator` 推入的新 `LibraryScreen.groupFilter` 等於分類名稱；新畫面 AppBar 標題顯示分類名稱、不顯示分類拼貼格區塊、不顯示「管理分類」按鈕）。
- `_buildBookList` 合併 index 空間：widget test（`itemCount` 等於分類格數＋書籍數；分類格永遠排在書籍之前）。
- 【審查修正】選取模式互動：widget test 驗證進入選取模式（長按任一本書）後，分類格的 `onTap` 為 `null`（點擊不觸發 `Navigator.push`，`_selectedBookIds` 與選取工具列狀態不受影響）。

---

## ADR

【審查修正——技術方案變更後新增】撰寫 `plan-issue-1.md` 前查證得知功能 ① 原始設計（純 Dart `SystemChrome.setEnabledSystemUIMode`）在本專案目前 `targetSdk`（36）下無效，改採原生 `WindowInsetsControllerCompat` 方案，屬於「難以回頭＋沒有前情提要會很意外＋真正的權衡取捨」皆成立的決策，已新增 **ADR 0015**（`docs/adr/0015-fullscreen-native-window-insets-controller.md`）。功能 ②③ 維持原判斷，不需要新增 ADR。
