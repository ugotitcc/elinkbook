# Epic 36 Issue 1：三目的地導覽框架＋來源聚合頁 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `AdaptiveShellScaffold`（`IndexedStack` 管理書架／來源／設定三個目的地）與 `SourcesHomeScreen`（聚合既有本機/雲端/OPDS 匯入入口），並把 `LibraryScreen` 的 AppBar 從「匯入＋E-Ink 切換＋排序＋檢視切換＋管理分類＋遠端書庫＋設定」七個獨立入口收斂為「排序/檢視、來源、設定」三個圖示。

**Architecture：** 不改變任何底層匯入/雲端/OPDS 邏輯，純粹是導覽外殼與既有入口的重新排列。`LibraryScreen`/`SourcesHomeScreen`/`SettingsScreen` 三個目的地由 `AdaptiveShellScaffold` 的 `build()` 每次直接建構、交給 `IndexedStack` 管理顯示——狀態保留靠 `IndexedStack` 讓所有子項全程掛載＋Flutter reconciliation 依 `runtimeType`/清單位置重用既有 `Element`/`State`（見 Task 5，`review-plan-issue-1.md` C-1），**不是**靠把子畫面快取成欄位；只切換 `_currentIndex` 即可達成零動畫轉場、頁碼/搜尋/下鑽狀態不遺失，同時保留對上層 `themeDependencies` 等參數變更的正常響應。檔案挑選邏輯（`pickAndImportFiles`/`pickAndImportFolder`）從 `_LibraryScreenState` 私有方法抽成 `app/lib/screens/support/book_import_picker_helper.dart` 的頂層函式，供 `SourcesHomeScreen` 呼叫；`LibraryScreen` 這一側對應的私有方法與死碼一併移除。

**Tech Stack：** Flutter 3.41.9、既有 `flutter_test` widget test 慣例（`pumpWidget(MaterialApp(home: X(...)))` + `Key` 斷言），無新增依賴套件。

**Spec：** `docs/epics/epic-36-adaptive-shelf-navigation/spec.md` §功能①、`docs/epics/epic-36-adaptive-shelf-navigation/issues.md` Issue 1

## Global Constraints

- 本 Epic 全程只碰 Navigation／Library UI／Settings UI／Bottom sheets／Dialogs／Layout，不碰 OPDS／WebDAV／雲端來源實作、書籍儲存、閱讀進度持久化等核心架構清單項目（`UI_DESIGN_RULES.md`）。
- `AdaptiveShellScaffold` 的 `build()` **每次都直接建構** `LibraryScreen`／`SourcesHomeScreen`／`SettingsScreen` 三個子 widget 交給 `IndexedStack`——**不得**把它們快取成 `initState()` 具現化一次的欄位（那樣會讓 `widget.themeDependencies` 等參數的後續變更永遠傳不到子畫面，`review-plan-issue-1.md` C-1 已修正）；也**不得**替這三個子 widget 加上會變動的 `Key`（例如 `UniqueKey()`）——狀態保留（頁碼/搜尋/下鑽狀態不遺失）完全由 `IndexedStack` 保持所有子項掛載＋Flutter 依 `runtimeType`/清單位置重用 `Element`/`State` 這個既有機制達成，不需要額外手段。
- `LibraryScreen` 新增的 `refreshSignal`/`onNavigateToSource`/`onNavigateToSettings` 三個建構參數皆為 **nullable**，未接上時維持現行行為，不得改成 required（既有直接建構 `LibraryScreen` 的測試/呼叫端不因此損壞）。
- `SettingsScreen`→`SettingsScaffold` 更名排在 Issue 5——本 Issue 的 `AdaptiveShellScaffold` 第三個子畫面暫時掛載既有 `SettingsScreen(...)`，不在本 Issue 預先更名或新增 AppBar 圖示。
- 每個 Task 完成後只跑該 Task 實際觸及的測試檔（`flutter test <path>`），全套 `flutter test`（不帶路徑）留到 Task 6 收尾時執行一次（比照 `CLAUDE.md`「測試執行範圍」）。
- `flutter analyze` 必須在每個 Task 結束時保持乾淨（`No issues found!`）。

## 計劃範圍澄清（撰寫本計劃時發現並解決的 issues.md 內部落差）

1. **`library_manage_groups_button` 併入本 Issue 範圍**：`issues.md` Issue 1 的「單元測試要求」清單沒有列出 `library_manage_groups_button`（6 處既有測試）的遷移，但 Issue 1 自己的**驗收標準**明文要求「書架 AppBar 僅剩『排序/檢視、來源、設定』三圖示」——若不把「管理分類」併入合併選單，AppBar 會剩 4 個頂層入口而非 3 個，直接違反本 Issue 自己的驗收標準。本計劃依驗收標準為準，把 `library_manage_groups_button` 併入 Task 4 的 `library_sort_view_button` 選單（沿用現有 `widget.groupFilter == null` 條件，不變更為 `_activeGroupFilter`——那是 Issue 2 的範圍），並在 Task 4 一併遷移這 6 處測試。Issue 2 的計劃撰寫者屆時只需確認這 6 處測試已經是新路徑、無需重新遷移。
2. **`_openGoogleDriveBrowser`/`_openOneDriveBrowser`/`_confirmAutoGroupByFolderName`/`_showImportResultSnackBar`/`_folderPickerChannel` 一併清理**：`issues.md` M-3 只點名 `_pickAndImportFiles`/`_pickAndImportFolder`/`_isImporting`/`_buildImportingOverlay` 四項死碼，但移除 `library_import_button` 後，上述五項也會失去唯一呼叫點、一併成為死碼（見 Task 4 的死碼清單），本計劃一併清理，避免 `flutter analyze` 出現 unused code 警告。

---

## Task 1：`book_import_picker_helper.dart`（檔案挑選純函式）

**Files:**
- Create: `app/lib/screens/support/book_import_picker_helper.dart`
- Test: `app/test/screens/support/book_import_picker_helper_test.dart`

**Interfaces:**
- Produces:
  - `Future<ImportResult?> pickAndImportFiles(BookImportService importService)`
  - `Future<ImportResult?> pickAndImportFolder(BookImportService importService, {required Future<bool?> Function() confirmAutoGroup})`
  - `Future<bool?> confirmAutoGroupByFolderName(BuildContext context)`
  - `void showImportResultSnackBar(BuildContext context, ImportResult result)`

- [x] **Step 1: 寫失敗測試——`pickAndImportFiles` 使用者取消選擇時回傳 null**

建立 `app/test/screens/support/book_import_picker_helper_test.dart`：

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/support/book_import_picker_helper.dart';

import '../../support/fake_book_import_service.dart';

void main() {
  const filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
  );
  const folderPickerChannel = MethodChannel('elinkbook/folder_picker');

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, null);
  });

  test('pickAndImportFiles：使用者取消選擇時回傳 null，不呼叫 importFiles', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, (call) async => null);
    final importService = FakeBookImportService();

    final result = await pickAndImportFiles(importService);

    expect(result, isNull);
    expect(importService.importFilesCalls, isEmpty);
  });
}
```

（若 `FakeBookImportService` 尚未有 `importFilesCalls` 這種呼叫記錄欄位，改為斷言 `importService.lastImportedUris`/等既有欄位維持初始值——動手前先讀 `app/test/support/fake_book_import_service.dart` 確認實際欄位名稱，勿臆測。）

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/support/book_import_picker_helper_test.dart`
Expected: FAIL（`book_import_picker_helper.dart` 不存在，import 錯誤）

- [x] **Step 3: 實作 `pickAndImportFiles`／`pickAndImportFolder`／`confirmAutoGroupByFolderName`／`showImportResultSnackBar`**

建立 `app/lib/screens/support/book_import_picker_helper.dart`（邏輯逐字取自 `library_screen.dart` 現行 `_pickAndImportFiles()`/`_pickAndImportFolder()`/`_confirmAutoGroupByFolderName()`/`_showImportResultSnackBar()`，拆成不依賴 `State` 的頂層函式；`mounted` 檢查移除——呼叫端自己的 `confirmAutoGroup` 閉包與 `BuildContext` 使用需自行注意 `context.mounted`）：

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../library/book_import_service.dart';

const _folderPickerChannel = MethodChannel('elinkbook/folder_picker');

/// 挑選一或多個檔案並匯入圖書庫；使用者取消選擇、或選取結果不含可用 URI
/// 時回傳 `null`（呼叫端不需要顯示任何提示）。呼叫端負責後續 UI 回饋
/// （loading 狀態、SnackBar、重新整理書單），本函式不觸碰任何 widget
/// 狀態——原本 `_LibraryScreenState._pickAndImportFiles()` 的邏輯搬遷至此
/// （見 epic-36-adaptive-shelf-navigation spec.md §功能①、審查報告
/// review-spec.md I-5：挑選輔助函式須放在展示層，不可放進純 Dart 的
/// `book_import_service.dart`）。
Future<ImportResult?> pickAndImportFiles(BookImportService importService) async {
  try {
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf', 'txt', 'cbz', 'azw3', 'md'],
    );
    if (picked == null || picked.files.isEmpty) return null;
    // uris／displayNames 必須用同一次過濾（f.identifier != null）建立，保持
    // 逐一對應——分開各自 map 再各自過濾會在有檔案 identifier 為 null 時
    // 位移量不同，導致 displayNames[i] 對應到錯誤的 uris[i]。
    final pickedWithUri =
        picked.files.where((f) => f.identifier != null).toList();
    final uris = pickedWithUri.map((f) => f.identifier!).toList();
    if (uris.isEmpty) return null;
    final displayNames = pickedWithUri.map((f) => f.name).toList();
    return await importService.importFiles(uris, displayNames: displayNames);
  } catch (_) {
    // 原 `_LibraryScreenState._pickAndImportFiles()` 既有的靜默吞例外行為
    // （`FilePicker` 在 Android 遭遇權限拒絕/取消/特定 SAF Provider 錯誤時
    // 會拋出 `PlatformException`），搬遷後維持不變（審查報告 I-2 採納）。
    return null;
  }
}

/// 挑選一個資料夾並匯入圖書庫；使用者取消選擇資料夾、或取消「是否依資料夾
/// 名稱自動建立分類」確認對話框時回傳 `null`。[confirmAutoGroup] 由呼叫端
/// 提供（負責彈出確認對話框並自行檢查 `context.mounted`——原本
/// `_LibraryScreenState` 在資料夾選擇器等待期間的 `if (!mounted) return;`
/// 保護，現在由呼叫端的閉包自行負責）。
Future<ImportResult?> pickAndImportFolder(
  BookImportService importService, {
  required Future<bool?> Function() confirmAutoGroup,
}) async {
  try {
    final folderUri =
        await _folderPickerChannel.invokeMethod<String>('pickFolder');
    if (folderUri == null) return null;
    final autoGroup = await confirmAutoGroup();
    if (autoGroup == null) return null;
    return await importService.importFolder(
      folderUri,
      autoGroupByFolderName: autoGroup,
    );
  } catch (_) {
    // 同上，維持原 `_pickAndImportFolder()` 既有的靜默吞例外行為
    // （審查報告 I-2 採納）。
    return null;
  }
}

/// 「是否依資料夾名稱自動建立分類」確認對話框（原
/// `_LibraryScreenState._confirmAutoGroupByFolderName()`，逐字搬遷）。
Future<bool?> confirmAutoGroupByFolderName(BuildContext context) {
  var autoGroup = true;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('匯入資料夾'),
        content: CheckboxListTile(
          key: const Key('library_import_folder_auto_group_checkbox'),
          value: autoGroup,
          onChanged: (value) => setDialogState(() => autoGroup = value ?? true),
          title: const Text('依資料夾名稱自動建立分類'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('library_import_folder_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(autoGroup),
            child: const Text('匯入'),
          ),
        ],
      ),
    ),
  );
}

/// 匯入完成後顯示單一合併提示：成功匯入本數與（若有）因來源 URI 與既有
/// 書籍重複而被跳過的本數。兩者皆為 0 時不顯示任何提示（原
/// `_LibraryScreenState._showImportResultSnackBar()`，逐字搬遷）。
void showImportResultSnackBar(BuildContext context, ImportResult result) {
  final importedCount = result.importedBooks.length;
  final skippedCount = result.skippedDuplicateCount;
  if (importedCount <= 0 && skippedCount <= 0) return;
  final message = importedCount > 0
      ? (skippedCount > 0
          ? '已匯入 $importedCount 本，$skippedCount 本已存在，已跳過'
          : '已匯入 $importedCount 本書')
      : '$skippedCount 本已存在，已跳過';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/support/book_import_picker_helper_test.dart`
Expected: PASS

- [x] **Step 5: 補齊 `pickAndImportFolder` 的成功路徑測試**

在同一個測試檔新增：

```dart
  test('pickAndImportFolder：確認自動分類後呼叫 importFolder(autoGroupByFolderName: true)', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, (call) async {
          if (call.method == 'pickFolder') return 'content://example/folder';
          return null;
        });
    final importService = FakeBookImportService();

    final result = await pickAndImportFolder(
      importService,
      confirmAutoGroup: () async => true,
    );

    expect(result, isNotNull);
    // 動手前先讀 FakeBookImportService 實際記錄欄位名稱（例如
    // lastImportFolderUri／lastAutoGroupByFolderName），依實際欄位改寫下列
    // 斷言，不得臆測欄位名稱。
  });

  test('pickAndImportFolder：取消自動分類確認對話框時回傳 null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, (call) async {
          if (call.method == 'pickFolder') return 'content://example/folder';
          return null;
        });
    final importService = FakeBookImportService();

    final result = await pickAndImportFolder(
      importService,
      confirmAutoGroup: () async => null,
    );

    expect(result, isNull);
  });

  test('pickAndImportFiles：平台例外（PlatformException）不外拋，優雅回傳 null（審查報告 I-2 回歸測試）', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, (call) async {
          throw PlatformException(code: 'read_external_storage_denied');
        });
    final importService = FakeBookImportService();

    final result = await pickAndImportFiles(importService);

    expect(result, isNull);
  });

  test('pickAndImportFolder：MethodChannel 拋例外不外拋，優雅回傳 null（審查報告 I-2 回歸測試）', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, (call) async {
          throw PlatformException(code: 'pick_folder_failed');
        });
    final importService = FakeBookImportService();

    final result = await pickAndImportFolder(
      importService,
      confirmAutoGroup: () async => true,
    );

    expect(result, isNull);
  });
```

- [x] **Step 6: 執行測試確認通過**

Run: `flutter test test/screens/support/book_import_picker_helper_test.dart`
Expected: PASS（全部案例）

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/support/book_import_picker_helper.dart app/test/screens/support/book_import_picker_helper_test.dart
git commit -m "feat(epic-36): 抽出 pickAndImportFiles/pickAndImportFolder 為獨立函式"
```

---

## Task 2：`SourcesHomeScreen`（來源聚合頁）

**Files:**
- Create: `app/lib/screens/sources_home_screen.dart`
- Test: `app/test/screens/sources_home_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `pickAndImportFiles`／`pickAndImportFolder`／`confirmAutoGroupByFolderName`／`showImportResultSnackBar`；既有 `LibraryCloudAccountDependencies`／`LibraryRemoteLibraryDependencies`（`app/lib/screens/library_screen_dependencies.dart`）、`ComputeRemoteFingerprint`（`app/lib/library/book_content_fingerprint.dart`）、`CloudBrowserScreen`（`app/lib/screens/cloud_browser_screen.dart`）、`RemoteServerListScreen`（`app/lib/screens/remote_server_list_screen.dart`）、`RemoteCatalogDependencies`（`app/lib/remote/remote_catalog_dependencies.dart`）。
- Produces: `SourcesHomeScreen` widget，建構參數 `repository`／`importService`／`cloudAccountDependencies`／`remoteLibraryDependencies`／`computeFingerprint`／`isMobileDataConnection`／`isEinkMode`／`onNavigateToLibrary`／`onNavigateToSettings`；Key 契約：`sources_pick_files_button`／`sources_pick_folder_button`／`sources_google_drive_tile`／`sources_onedrive_tile`／`sources_remote_library_tile`／`sources_library_button`／`sources_settings_button`。

- [x] **Step 1: 寫失敗測試——本機兩顆按鈕呼叫對應匯入函式**

建立 `app/test/screens/sources_home_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/sources_home_screen.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_remote_server_repository.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_thumbnail_cache.dart';

void main() {
  const filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, null);
  });

  testWidgets('點擊「選擇檔案」觸發 FilePicker 並匯入', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, (call) async {
          if (call.method == 'custom') {
            return [
              {
                'name': 'book.epub',
                'path': '/tmp/book.epub',
                'size': 100,
                'bytes': null,
                'identifier': 'content://example/book.epub',
              },
            ];
          }
          return null;
        });
    final importService = FakeBookImportService();

    await tester.pumpWidget(
      MaterialApp(
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: importService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sources_pick_files_button')));
    await tester.pumpAndSettle();

    // 動手前先讀 FakeBookImportService 實際欄位名稱，改寫為正確斷言
    // （驗證 importFiles 確實被呼叫、URI 為 'content://example/book.epub'）。
  });

  testWidgets('雲端/OPDS 依賴缺席時對應項目為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final googleDriveTile = tester.widget<ListTile>(
      find.byKey(const Key('sources_google_drive_tile')),
    );
    expect(googleDriveTile.enabled, isFalse);
    final oneDriveTile = tester.widget<ListTile>(
      find.byKey(const Key('sources_onedrive_tile')),
    );
    expect(oneDriveTile.enabled, isFalse);
    final remoteTile = tester.widget<ListTile>(
      find.byKey(const Key('sources_remote_library_tile')),
    );
    expect(remoteTile.enabled, isFalse);
  });

  testWidgets('依賴齊全時點擊 Google Drive 項目導覽至 CloudBrowserScreen', (tester) async {
    final fingerprintComputer = FakeFingerprintComputer();
    await tester.pumpWidget(
      MaterialApp(
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          cloudAccountDependencies: LibraryCloudAccountDependencies(
            googleDriveStorageClient: FakeCloudStorageClient(),
          ),
          computeFingerprint: fingerprintComputer.call,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sources_google_drive_tile')));
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsWidgets);
    // 動手前先讀 cloud_browser_screen.dart 確認可辨識 widget/Key，補齊
    // 「確實導覽到 CloudBrowserScreen」的精確斷言（例如
    // find.byType(CloudBrowserScreen)）。
  });

  testWidgets('依賴齊全時點擊遠端書庫項目導覽至 RemoteServerListScreen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
            remoteServerRepository: FakeRemoteServerRepository(),
            createOpdsClient: () => FakeOpdsClient(),
            thumbnailCache: FakeRemoteThumbnailCache(),
          ),
          computeFingerprint: FakeFingerprintComputer().call,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sources_remote_library_tile')));
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsWidgets);
    // 動手前先讀 remote_server_list_screen.dart 確認可辨識 widget/Key，補齊
    // 「確實導覽到 RemoteServerListScreen」的精確斷言。
  });

  testWidgets('AppBar 書架/設定圖示呼叫對應 callback', (tester) async {
    var libraryTapped = 0;
    var settingsTapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          onNavigateToLibrary: () => libraryTapped++,
          onNavigateToSettings: () => settingsTapped++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sources_library_button')));
    await tester.tap(find.byKey(const Key('sources_settings_button')));

    expect(libraryTapped, 1);
    expect(settingsTapped, 1);
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/sources_home_screen_test.dart`
Expected: FAIL（`sources_home_screen.dart` 不存在）

- [x] **Step 3: 實作 `SourcesHomeScreen`**

建立 `app/lib/screens/sources_home_screen.dart`：

```dart
import 'package:flutter/material.dart';

import '../cloud_import/cloud_storage_client.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/library_enums.dart';
import '../remote/remote_catalog_dependencies.dart';
import 'cloud_browser_screen.dart';
import 'library_screen_dependencies.dart';
import 'remote_server_list_screen.dart';
import 'support/book_import_picker_helper.dart';

/// 「來源」目的地聚合頁（epic-36-adaptive-shelf-navigation spec.md
/// §功能①）：只聚合既有本機/雲端/OPDS 入口，不新增任何底層匯入/雲端
/// 邏輯——AppBar 拿掉「＋」匯入選單後的功能真空由本畫面承接。
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

  const SourcesHomeScreen({
    super.key,
    required this.repository,
    required this.importService,
    this.cloudAccountDependencies = const LibraryCloudAccountDependencies(),
    this.remoteLibraryDependencies = const LibraryRemoteLibraryDependencies(),
    this.computeFingerprint,
    this.isMobileDataConnection,
    this.isEinkMode = false,
    this.onNavigateToLibrary,
    this.onNavigateToSettings,
  });

  Future<void> _handlePickFiles(BuildContext context) async {
    final result = await pickAndImportFiles(importService);
    if (result == null) return;
    if (!context.mounted) return;
    showImportResultSnackBar(context, result);
  }

  Future<void> _handlePickFolder(BuildContext context) async {
    final result = await pickAndImportFolder(
      importService,
      // 資料夾選擇器等待期間使用者可能已離開此畫面（審查報告 M-1）：
      // `context.mounted` 需在等待結束、真正要彈出確認對話框前才檢查，
      // 而非在呼叫 pickAndImportFolder() 之前檢查一次就假設之後都有效。
      confirmAutoGroup: () =>
          context.mounted ? confirmAutoGroupByFolderName(context) : Future.value(null),
    );
    if (result == null) return;
    if (!context.mounted) return;
    showImportResultSnackBar(context, result);
  }

  void _openGoogleDriveBrowser(BuildContext context, CloudStorageClient client) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CloudBrowserScreen(
          client: client,
          libraryRepository: repository,
          importService: importService,
          source: BookSource.googleDrive,
          computeFingerprint: computeFingerprint!,
          isMobileDataConnection: isMobileDataConnection,
        ),
      ),
    );
  }

  void _openOneDriveBrowser(BuildContext context, CloudStorageClient client) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CloudBrowserScreen(
          client: client,
          libraryRepository: repository,
          importService: importService,
          source: BookSource.oneDrive,
          computeFingerprint: computeFingerprint!,
          isMobileDataConnection: isMobileDataConnection,
          title: 'OneDrive',
        ),
      ),
    );
  }

  void _openRemoteLibrary(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RemoteServerListScreen(
          repository: remoteLibraryDependencies.remoteServerRepository!,
          libraryRepository: repository,
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: computeFingerprint!,
            thumbnailCache: remoteLibraryDependencies.thumbnailCache!,
            createOpdsClient: remoteLibraryDependencies.createOpdsClient!,
          ),
          importService: importService,
          isEinkMode: isEinkMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final googleDriveClient = cloudAccountDependencies.googleDriveStorageClient;
    final oneDriveClient = cloudAccountDependencies.oneDriveStorageClient;
    final googleDriveEnabled =
        googleDriveClient != null && computeFingerprint != null;
    final oneDriveEnabled = oneDriveClient != null && computeFingerprint != null;
    final remoteEnabled = remoteLibraryDependencies.remoteServerRepository != null &&
        remoteLibraryDependencies.createOpdsClient != null &&
        remoteLibraryDependencies.thumbnailCache != null &&
        computeFingerprint != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('來源'),
        actions: [
          IconButton(
            key: const Key('sources_library_button'),
            icon: const Icon(Icons.grid_view),
            tooltip: '書架',
            onPressed: onNavigateToLibrary,
          ),
          IconButton(
            key: const Key('sources_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: onNavigateToSettings,
          ),
        ],
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('本機', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            key: const Key('sources_pick_files_button'),
            leading: const Icon(Icons.description),
            title: const Text('選擇檔案（可多選）'),
            onTap: () => _handlePickFiles(context),
          ),
          ListTile(
            key: const Key('sources_pick_folder_button'),
            leading: const Icon(Icons.folder),
            title: const Text('選擇資料夾'),
            onTap: () => _handlePickFolder(context),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('已連結服務', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            key: const Key('sources_google_drive_tile'),
            leading: const Icon(Icons.cloud),
            title: const Text('Google Drive'),
            subtitle:
                googleDriveEnabled ? null : const Text('尚未連結，請至設定畫面連結帳戶'),
            enabled: googleDriveEnabled,
            onTap: googleDriveEnabled
                ? () => _openGoogleDriveBrowser(context, googleDriveClient!)
                : null,
          ),
          ListTile(
            key: const Key('sources_onedrive_tile'),
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('OneDrive'),
            subtitle: oneDriveEnabled ? null : const Text('尚未連結，請至設定畫面連結帳戶'),
            enabled: oneDriveEnabled,
            onTap: oneDriveEnabled
                ? () => _openOneDriveBrowser(context, oneDriveClient!)
                : null,
          ),
          ListTile(
            key: const Key('sources_remote_library_tile'),
            leading: const Icon(Icons.dns),
            title: const Text('遠端書庫（OPDS）'),
            subtitle: remoteEnabled ? null : const Text('尚未設定遠端書庫伺服器'),
            enabled: remoteEnabled,
            onTap: remoteEnabled ? () => _openRemoteLibrary(context) : null,
          ),
        ],
      ),
    );
  }
}
```

- [x] **Step 4: 執行測試，逐一修正斷言直到全數通過**

Run: `flutter test test/screens/sources_home_screen_test.dart`

先讀 `app/test/support/fake_book_import_service.dart`（確認匯入呼叫記錄欄位名稱）、`app/lib/screens/cloud_browser_screen.dart`／`app/lib/screens/remote_server_list_screen.dart`（確認畫面 widget 型別），把 Step 1 測試中的佔位斷言替換為實際可通過的精確斷言，不得保留模糊斷言（`findsWidgets` 只作為過渡，最終須改為 `find.byType(CloudBrowserScreen)`/`find.byType(RemoteServerListScreen)` 等精確斷言）。

Expected: PASS（全部案例）

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/sources_home_screen.dart app/test/screens/sources_home_screen_test.dart
git commit -m "feat(epic-36): 新增 SourcesHomeScreen 來源聚合頁"
```

---

## Task 3：`LibraryScreen` 新增 `refreshSignal`/`onNavigateToSource`/`onNavigateToSettings`

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/test/navigation_test.dart`
- Modify: `app/test/screens/library_screen_test.dart:3137-3199`（兩則 `library_settings_button` 測試）

**Interfaces:**
- Produces: `LibraryScreen` 新增建構參數 `final Listenable? refreshSignal; final VoidCallback? onNavigateToSource; final VoidCallback? onNavigateToSettings;`（皆 nullable，預設 null）。

- [x] **Step 1: 寫失敗測試——`onNavigateToSettings` callback 取代 `Navigator.push`**

改寫 `app/test/navigation_test.dart` 全檔為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import 'support/fake_book_import_service.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_reader_prefs_manager.dart';

void main() {
  late SqliteLibraryRepository libraryRepository;
  late ReaderPrefsManager prefsManager;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsManager = FakeReaderPrefsManager();
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  testWidgets(
    '點擊設定圖示呼叫 onNavigateToSettings callback（epic-36 三目的地導覽取代 '
    'Navigator.push，見 reviews/review-issues.md I-1）',
    (tester) async {
      var settingsRequested = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: LibraryScreen(
            repository: FakeLibraryRepository(),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
            onNavigateToSettings: () => settingsRequested++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('書架'), findsOneWidget);

      await tester.tap(find.byKey(const Key('library_settings_button')));
      await tester.pumpAndSettle();

      expect(settingsRequested, 1);
      // 三目的地導覽下設定畫面由 AdaptiveShellScaffold 的 IndexedStack
      // 承接，不再是 Navigator.push 推入的新路由——這裡只驗證 LibraryScreen
      // 端呼叫了 callback，跨分頁 IndexedStack 切換與參數轉送行為由
      // adaptive_shell_scaffold_test.dart（Task 5）驗證。
      expect(find.text('書架'), findsOneWidget);
    },
  );
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/navigation_test.dart`
Expected: FAIL（`LibraryScreen` 尚無 `onNavigateToSettings` 具名參數，編譯錯誤）

- [x] **Step 3: `LibraryScreen` 新增三個建構參數並修改設定按鈕**

編輯 `app/lib/screens/library_screen.dart`：

在 `class LibraryScreen` 欄位宣告區（`final String? groupFilter;` 之後）新增：

```dart
  final String? groupFilter;
  final Listenable? refreshSignal;
  final VoidCallback? onNavigateToSource;
  final VoidCallback? onNavigateToSettings;
```

建構子新增對應具名參數（皆選填、無預設值即為 `null`）：

```dart
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.readerFeatureRepositories = const LibraryReaderFeatureRepositories(),
    this.syncDependencies = const LibrarySyncDependencies(),
    this.cloudAccountDependencies = const LibraryCloudAccountDependencies(),
    this.remoteLibraryDependencies = const LibraryRemoteLibraryDependencies(),
    this.computeFingerprint,
    this.isMobileDataConnection,
    this.themeDependencies = const LibraryThemeDependencies(),
    this.groupFilter,
    this.refreshSignal,
    this.onNavigateToSource,
    this.onNavigateToSettings,
  });
```

`_LibraryScreenState.initState()`／`dispose()` 掛上/解除 `refreshSignal` 監聽：

```dart
  @override
  void initState() {
    super.initState();
    _bookListController = LibraryBookListController(
      repository: widget.repository,
      groupFilter: widget.groupFilter,
    )..addListener(_onBookListChanged);
    _batchActions = LibraryBatchActions(repository: widget.repository);
    widget.refreshSignal?.addListener(_onExternalRefreshRequested);
    _initialize();
  }

  /// 「來源」畫面匯入新書後切回書架時觸發（見 AdaptiveShellScaffold，
  /// Task 5）——IndexedStack 讓 LibraryScreen 全程保持掛載，切換可見子項不
  /// 會重跑 build()，需要這個外部訊號主動重新整理。
  void _onExternalRefreshRequested() {
    _bookListController.loadBooks();
    _bookListController.loadGroups();
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_onExternalRefreshRequested);
    _bookListController.dispose();
    super.dispose();
  }
```

`_buildNormalAppBar()` 內的 `library_settings_button`（移除 `Navigator.push` 整段，改呼叫 callback）：

```dart
        IconButton(
          key: const Key('library_settings_button'),
          icon: const Icon(Icons.settings),
          tooltip: '設定',
          onPressed: widget.onNavigateToSettings,
        ),
```

檔案頂部移除 `import 'settings_screen.dart';`（不再直接參照 `SettingsScreen`）。

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/navigation_test.dart`
Expected: PASS

- [x] **Step 5: 刪除已無法成立的 2 則既有測試（改由 Task 5 的 `adaptive_shell_scaffold_test.dart` 承接）**

編輯 `app/test/screens/library_screen_test.dart`：刪除以下兩則 `testWidgets`（原第 3137-3163 行、3169-3199 行，皆斷言「點擊 `library_settings_button` 後 `find.byType(SettingsScreen)` 收到轉送參數」——這個轉送責任已隨 `Navigator.push` 移除轉移給 `AdaptiveShellScaffold`，等價覆蓋在 Task 5 補上）：

- `'LibraryScreen 貫穿 customFontsRepository 至 SettingsScreen'`
- `'LibraryScreen 貫穿 onEinkModeChanged 至 SettingsScreen'`

刪除後確認檔案仍可編譯（`SettingsScreen` 型別若因此在該測試檔完全無其他引用，一併移除 `import 'package:elinkbook/screens/settings_screen.dart';`——動手前先確認檔案內是否還有其他地方引用 `SettingsScreen`，若有則保留 import）。

- [x] **Step 6: 執行 `library_screen_test.dart` 確認無新增失敗（可能仍有 Task 4 才會處理的既有失敗，先確認本步驟改動沒有引入新的失敗）**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 除了 Task 4 範圍內尚未處理的既有測試（`library_import_button` 等）外，其餘測試 PASS；本 Step 只確認沒有新增與本 Step 改動直接相關的失敗。

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/navigation_test.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-36): LibraryScreen 新增 refreshSignal/onNavigateToSource/onNavigateToSettings"
```

---

## Task 4：`LibraryScreen` AppBar 收斂＋死碼清理

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/test/screens/library_screen_test.dart`（大量既有測試遷移，見下方逐項清單）

**Interfaces:**
- Produces: AppBar 三圖示 `library_sort_view_button`／`library_source_button`／`library_settings_button`；`library_sort_view_button` 選單項目 `library_sort_option_${sortBy.name}`／`library_sort_view_toggle_option`／`library_manage_groups_option`。
- 移除的 Key：`library_eink_toggle`、`library_import_button`、`library_import_files_option`、`library_import_folder_option`、`library_import_google_drive_option`、`library_import_onedrive_option`、`library_manage_groups_button`、`library_remote_library_button`、`library_sort_button`、`library_view_mode_toggle`、`library_importing_overlay`。

### Step A：先讀懂要刪除/遷移的既有測試分佈

- [x] **Step 1**：Run（唯讀，不改檔案）：

```bash
grep -n "library_import_button\|library_import_files_option\|library_import_folder_option\|library_import_google_drive_option\|library_import_onedrive_option\|library_eink_toggle\|library_remote_library_button\|library_sort_button\|library_view_mode_toggle\|library_manage_groups_button\|library_importing_overlay" app/test/screens/library_screen_test.dart
```

記下所有行號，逐一讀取每個命中行號前後 30 行（`testWidgets(...)` 區塊的起訖），分類為以下三種：

- **(a) 整個測試的唯一主題就是被移除的功能**（例如「匯入中狀態遮罩」「E-Ink 快速切換」「遠端書庫入口」「透過匯入選單匯入」）→ 整個 `testWidgets` 區塊刪除。
- **(b) 測試主題不是被移除的功能，但其中一個步驟／斷言用到被移除或搬遷的 Key**（例如某個批次操作測試中途用 `library_view_mode_toggle` 切到列表檢視以方便斷言）→ 只修正該行，其餘不動。
- **(c) Key 本身還在、只是換了名字或觸發路徑**（`library_sort_button`→`library_sort_view_button`；`library_view_mode_toggle`／`library_manage_groups_button` 觸發路徑改為先開 `library_sort_view_button` 選單）→ 依下方 Step B 的轉換規則機械式修改。

### Step B：production code 異動

- [x] **Step 2**：編輯 `app/lib/screens/library_screen.dart`，`_buildNormalAppBar()` 內容整段改為：

```dart
  AppBar _buildNormalAppBar(List<Book>? books) {
    return AppBar(
      title: Text(widget.groupFilter ?? '書架'),
      actions: [
        PopupMenuButton<void>(
          key: const Key('library_sort_view_button'),
          icon: const Icon(Icons.sort),
          tooltip: '排序與檢視',
          enabled: books != null,
          itemBuilder: (context) {
            final currentSort = _bookListController.sortBy;
            final primaryColor = Theme.of(context).colorScheme.primary;
            return [
              for (final sortBy in LibrarySortBy.values)
                PopupMenuItem<void>(
                  key: Key('library_sort_option_${sortBy.name}'),
                  onTap: () => _bookListController.changeSortBy(sortBy),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: currentSort == sortBy
                            ? Icon(Icons.check, size: 20, color: primaryColor)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _sortLabel(sortBy),
                        style: TextStyle(
                          fontWeight: currentSort == sortBy
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: currentSort == sortBy ? primaryColor : null,
                        ),
                      ),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<void>(
                key: const Key('library_sort_view_toggle_option'),
                onTap: _toggleViewMode,
                child: Text(
                  _viewMode == LibraryViewMode.grid ? '切換為列表' : '切換為書架',
                ),
              ),
              if (widget.groupFilter == null)
                PopupMenuItem<void>(
                  key: const Key('library_manage_groups_option'),
                  onTap: _openManageGroupsDialog,
                  child: const Text('管理分類...'),
                ),
            ];
          },
        ),
        IconButton(
          key: const Key('library_source_button'),
          icon: const Icon(Icons.cloud_download),
          tooltip: '來源',
          onPressed: widget.onNavigateToSource,
        ),
        IconButton(
          key: const Key('library_settings_button'),
          icon: const Icon(Icons.settings),
          tooltip: '設定',
          onPressed: widget.onNavigateToSettings,
        ),
      ],
    );
  }
```

（這段取代原本從 `Container`〔`library_eink_toggle`〕開始，到 `library_settings_button` 結束的整段 `actions:` 內容——`library_manage_groups_button`／`library_remote_library_button`／`library_import_button` 三個區塊整段刪除，不保留任何殘餘 `if` 判斷式。）

- [x] **Step 3**：`_buildEmptyState()` 的匯入按鈕改為導向來源分頁：

```dart
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('尚未匯入書籍'),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('library_empty_import_button'),
            onPressed: widget.onNavigateToSource,
            child: const Text('匯入書籍'),
          ),
        ],
      ),
    );
  }
```

- [x] **Step 4**：`build()` 內移除 `_isImporting` 遮罩疊層：

```dart
  @override
  Widget build(BuildContext context) {
    final books = _bookListController.books;
    return PopScope(
      canPop: !_inSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _inSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: _inSelectionMode
            ? _buildSelectionAppBar()
            : _buildNormalAppBar(books),
        body: books == null
            ? const Center(child: CircularProgressIndicator())
            : (books.isEmpty ? _buildEmptyState() : _buildBookList(books)),
      ),
    );
  }
```

（原本外層 `Stack`＋`Column`＋`if (_isImporting) _buildImportingOverlay()` 整段收斂，因為 `_isImporting` 欄位本身即將移除。）

- [x] **Step 5**：刪除以下死碼（連同其 dartdoc 註解整段移除）：`_isImporting` 欄位、`_pickAndImportFiles()`、`_pickAndImportFolder()`、`_openGoogleDriveBrowser()`、`_openOneDriveBrowser()`、`_showImportResultSnackBar()`、`_confirmAutoGroupByFolderName()`、`_buildImportingOverlay()`，以及檔案頂部的 `const _folderPickerChannel = MethodChannel('elinkbook/folder_picker');`。

- [x] **Step 6**：Run `flutter analyze`，依報告清掉檔案頂部殘留的未使用 import（預期至少包含 `package:file_picker/file_picker.dart`、`package:flutter/services.dart`、`../cloud_import/cloud_storage_client.dart`、`cloud_browser_screen.dart`、`remote_server_list_screen.dart`、`../remote/remote_catalog_dependencies.dart`——實際以 `flutter analyze` 報告為準，不要憑記憶刪多或刪少）。

Expected: `No issues found!`

### Step C：測試遷移（機械式規則，逐一套用在 Step 1 記下的每個行號）

- [x] **Step 7**：套用以下規則機械式修改 `app/test/screens/library_screen_test.dart`：

**規則 1（`library_sort_button` → `library_sort_view_button`，純改名，5 處，含既有 `findsOneWidget` 存在性斷言與 `tester.tap` 呼叫）：**
```diff
-await tester.tap(find.byKey(const Key('library_sort_button')));
+await tester.tap(find.byKey(const Key('library_sort_view_button')));
```
```diff
-expect(find.byKey(const Key('library_sort_button')), findsOneWidget);
+expect(find.byKey(const Key('library_sort_view_button')), findsOneWidget);
```

**規則 2（`library_view_mode_toggle` 單擊 → 先開選單再點切換項，10 處）：**
```diff
-await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
+await tester.tap(find.byKey(const Key('library_sort_view_button')));
+await tester.pumpAndSettle();
+await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
```
（原本緊接在後的 `await tester.pumpAndSettle();` 維持不動。）

**規則 3（`library_manage_groups_button` 單擊 → 先開選單再點管理分類項，6 處）：**
```diff
-await tester.tap(find.byKey(const Key('library_manage_groups_button')));
+await tester.tap(find.byKey(const Key('library_sort_view_button')));
+await tester.pumpAndSettle();
+await tester.tap(find.byKey(const Key('library_manage_groups_option')));
```
第 1438 行附近若是 `find.descendant(..., matching: find.byKey(const Key('library_manage_groups_button')))` 這種「檢查某個祖先範圍內管理分類按鈕存不存在」的存在性斷言（而非 `tester.tap`），改為先開 `library_sort_view_button` 選單，再對 `library_manage_groups_option` 做同義的 `findsOneWidget`/`findsNothing` 斷言——讀該處完整上下文後再動手，勿套用「規則 3」的 tap 版本。

**規則 4（`library_eink_toggle`，2 處，整個測試主題就是 E-Ink 快速切換功能，功能本身移除）：**
刪除該 `testWidgets` 整個區塊（第 4374、4407 行附近，涵蓋第 4433 行同一個測試內對 `library_sort_button` 的引用一併隨區塊刪除，不需要對它套用規則 1）。

**規則 5（`library_remote_library_button`，4 處，整個測試主題就是遠端書庫入口，功能搬遷至 `SourcesHomeScreen`，已由 Task 2 的 `sources_home_screen_test.dart` 承接等價覆蓋）：**
刪除涵蓋第 3942、3971、3976、4013 行的 `testWidgets` 整個區塊。

**規則 6（`library_import_button`／`library_import_files_option`／`library_import_folder_option`／`library_import_google_drive_option`／`library_import_onedrive_option`／`library_importing_overlay`，共 12＋處，功能整段搬遷至 `SourcesHomeScreen`，已由 Task 2 承接等價覆蓋）：**
逐一讀取每個命中行號的 `testWidgets` 區塊：
- 若整個測試的目的就是「透過匯入選單匯入」「匯入中遮罩顯示」「匯入按鈕停用狀態」，整段刪除。
- 若只是某個測試裡順手用匯入選單準備測試資料（例如先匯入一本書才能繼續斷言其他行為），改為改用 `FakeLibraryRepository(initialBooks: [...])` 建構子直接塞入測試資料，不透過 UI 操作匯入（比照本檔案其餘多數測試已採用的既有模式）。
- 第 105-125 行「圖書庫為空時顯示『尚未匯入書籍』提示與匯入按鈕」測試**保留**，只刪除第 124 行 `expect(find.byKey(const Key('library_import_button')), findsOneWidget);` 這一行斷言（該測試其餘部分——空狀態文字與 `library_empty_import_button` 存在性——依然成立）。

- [x] **Step 8**：新增 `issues.md` 明訂但先前遺漏的兩則 callback 測試（審查報告 I-1、M-3）

在 `app/test/screens/library_screen_test.dart` 新增：

```dart
  testWidgets('空書架點擊「匯入書籍」呼叫 onNavigateToSource callback（issues.md Issue 1 明訂，審查報告 I-1）', (tester) async {
    var sourceTapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          onNavigateToSource: () => sourceTapped++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_empty_import_button')));
    await tester.pumpAndSettle();

    expect(sourceTapped, 1);
  });

  testWidgets('點擊 AppBar「來源」圖示呼叫 onNavigateToSource callback（審查報告 M-3）', (tester) async {
    var sourceTapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: const []),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          onNavigateToSource: () => sourceTapped++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();

    expect(sourceTapped, 1);
  });
```

- [x] **Step 9**：執行測試，逐一修正殘餘失敗

Run: `flutter test test/screens/library_screen_test.dart`

反覆執行、依失敗訊息修正（每個失敗對應 Step 7 規則清單中的一項），直到全數 PASS 或該檔案剩餘失敗與本 Task 改動無關（若有，記錄下來，不在本 Task 修正超出範圍的既有問題）。

Expected: PASS（本 Task 改動涉及的全部案例）

- [x] **Step 10**：`flutter analyze` 確認乾淨

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 11**：Commit

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-36): LibraryScreen AppBar 收斂為排序/檢視、來源、設定三圖示"
```

---

## Task 5：`AdaptiveShellScaffold`（三目的地導覽外殼）＋ `main.dart` 接線

**Files:**
- Create: `app/lib/screens/adaptive_shell_scaffold.dart`
- Test: `app/test/screens/adaptive_shell_scaffold_test.dart`
- Modify: `app/lib/main.dart`

**Interfaces:**
- Consumes: Task 2 的 `SourcesHomeScreen`；Task 3/4 的 `LibraryScreen`（`refreshSignal`/`onNavigateToSource`/`onNavigateToSettings`）；既有 `SettingsScreen`（暫不更名，見 Global Constraints）。
- Produces: `AdaptiveShellScaffold` widget，建構參數與 `ElinkBookApp` 現有直接餵給 `LibraryScreen` 的參數集合完全相同（`repository`／`importService`／`prefsManager`／`readerFeatureRepositories`／`syncDependencies`／`cloudAccountDependencies`／`remoteLibraryDependencies`／`computeFingerprint`／`isMobileDataConnection`／`themeDependencies`）。

- [ ] **Step 1: 寫失敗測試——三個目的地圖示切換後 `IndexedStack.index` 正確、狀態不遺失**

建立 `app/test/screens/adaptive_shell_scaffold_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/adaptive_shell_scaffold.dart';
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/settings_screen.dart';
import 'package:elinkbook/screens/sources_home_screen.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_custom_fonts_repository.dart';

void main() {
  late SqliteLibraryRepository libraryRepository;
  late ReaderPrefsManager prefsManager;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsManager = FakeReaderPrefsManager();
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  Widget buildApp({Listenable? refreshSignalOverrideNotUsed}) {
    return MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: AdaptiveShellScaffold(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
      ),
    );
  }

  testWidgets('三個目的地圖示切換後 IndexedStack.index 正確且畫面對應正確', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);

    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
    expect(find.text('來源'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sources_settings_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);
    expect(find.text('設定'), findsOneWidget);
  });

  testWidgets('切換目的地不重建 LibraryScreen 的 State（狀態保留）', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final stateBefore = tester.state(find.byType(LibraryScreen));

    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sources_library_button')));
    await tester.pumpAndSettle();

    final stateAfter = tester.state(find.byType(LibraryScreen));
    expect(identical(stateBefore, stateAfter), isTrue);
  });

  testWidgets('切回書架分頁時觸發 refreshSignal，書架重新載入資料', (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: AdaptiveShellScaffold(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 新增一本書到 repository 記憶體資料，模擬「來源」畫面完成匯入
    // （`FakeLibraryRepository.insertBook(Book)`，見
    // `app/test/support/fake_library_repository.dart:50`；審查報告
    // M-2——`Book` 建構子的 `format`/`source` 為必填欄位）。
    await repository.insertBook(
      Book(
        id: 'new_book',
        title: '後補書',
        format: BookFileFormat.epub,
        filePath: 'content://example/new_book.epub',
        source: BookSource.local,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      ),
    );

    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sources_library_button')));
    await tester.pumpAndSettle();

    expect(find.text('後補書'), findsOneWidget);
  });

  testWidgets('非書架分頁時系統返回鍵優先切回書架', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
  });

  testWidgets('SettingsScreen 收到 customFontsRepository/onEinkModeChanged 轉送（取代原 library_screen_test.dart 的 2 則測試）', (tester) async {
    final customFontsRepository = FakeCustomFontsRepository();
    bool? toggledValue;
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: AdaptiveShellScaffold(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            customFontsRepository: customFontsRepository,
          ),
          themeDependencies: LibraryThemeDependencies(
            onEinkModeChanged: (val) => toggledValue = val,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();

    final settingsScreen =
        tester.widget<SettingsScreen>(find.byType(SettingsScreen));
    expect(settingsScreen.customFontsRepository, customFontsRepository);
    expect(settingsScreen.onEinkModeChanged, isNotNull);

    await tester.tap(find.byKey(const Key('settings_eink_mode_switch')));
    await tester.pumpAndSettle();

    expect(toggledValue, isTrue);
  });

  testWidgets('上層 themeDependencies 更新後，已切換過去的 SettingsScreen 收到最新 isEinkMode（審查報告 C-1 回歸測試：子畫面不得在 initState 快取）', (tester) async {
    Widget buildWithEink(bool isEinkMode) {
      return MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: isEinkMode),
        home: AdaptiveShellScaffold(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          themeDependencies: LibraryThemeDependencies(isEinkMode: isEinkMode),
        ),
      );
    }

    await tester.pumpWidget(buildWithEink(false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();

    var settingsScreen =
        tester.widget<SettingsScreen>(find.byType(SettingsScreen));
    expect(settingsScreen.isEinkMode, isFalse);

    // 重新 pumpWidget 同一個 AdaptiveShellScaffold（同一個 widget tree
    // 位置），但 themeDependencies.isEinkMode 已改變——模擬使用者在別處
    // 切換 E-Ink 模式後，main.dart 的 setState() 觸發整棵 widget tree
    // 帶著新的 themeDependencies 重新 build()。
    await tester.pumpWidget(buildWithEink(true));
    await tester.pumpAndSettle();

    settingsScreen = tester.widget<SettingsScreen>(find.byType(SettingsScreen));
    expect(
      settingsScreen.isEinkMode,
      isTrue,
      reason: '若 AdaptiveShellScaffold 把子畫面快取在 initState()，這裡會維持 false，'
          '因為快取的 SettingsScreen 建構當下的 isEinkMode 已經是舊值',
    );
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/adaptive_shell_scaffold_test.dart`
Expected: FAIL（`adaptive_shell_scaffold.dart` 不存在）

- [ ] **Step 3: 實作 `AdaptiveShellScaffold`**

建立 `app/lib/screens/adaptive_shell_scaffold.dart`：

```dart
import 'package:flutter/material.dart';

import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../reader/reader_prefs_manager.dart';
import 'library_screen.dart';
import 'library_screen_dependencies.dart';
import 'settings_screen.dart';
import 'sources_home_screen.dart';

/// 三目的地導覽外殼（epic-36-adaptive-shelf-navigation spec.md §功能①）：
/// 書架／來源／設定互相以圖示切換，`IndexedStack` 保留三個目的地畫面狀態，
/// 手機寬度不使用底部導覽列。三個子畫面的狀態保留完全由 `IndexedStack`
/// 本身負責（所有子項全程掛載、只是視覺上切換顯示），**不需要、也不應該**
/// 把子畫面 widget 快取成欄位——只要 `build()` 每次都建構「相同
/// `runtimeType`、相同清單位置」的 widget，Flutter reconciliation
/// （`Element.update`／`State.didUpdateWidget`）就會重用既有 `Element`／
/// `State`，`LibraryScreen` 的頁碼/搜尋/下鑽狀態不會遺失；反之若快取成
/// `late final` 欄位，上層 `themeDependencies` 等參數之後的變更（例如
/// 使用者在「設定」切換主題／E-Ink 模式回呼到 `main.dart` 觸發
/// `setState()`）永遠不會被子畫面收到（審查報告 review-plan-issue-1.md
/// C-1，本計劃已依此修正為 `build()` 內直接建構）。
///
/// **過渡期型別標注**：`SettingsScreen`→`SettingsScaffold` 更名排在 Issue
/// 5，本類別第三個子畫面暫時掛載既有 `SettingsScreen`（見
/// `reviews/review-issues.md` M-1）。
class AdaptiveShellScaffold extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final ReaderPrefsManager prefsManager;
  final LibraryReaderFeatureRepositories readerFeatureRepositories;
  final LibrarySyncDependencies syncDependencies;
  final LibraryCloudAccountDependencies cloudAccountDependencies;
  final LibraryRemoteLibraryDependencies remoteLibraryDependencies;
  final ComputeRemoteFingerprint? computeFingerprint;
  final Future<bool> Function()? isMobileDataConnection;
  final LibraryThemeDependencies themeDependencies;

  const AdaptiveShellScaffold({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.readerFeatureRepositories = const LibraryReaderFeatureRepositories(),
    this.syncDependencies = const LibrarySyncDependencies(),
    this.cloudAccountDependencies = const LibraryCloudAccountDependencies(),
    this.remoteLibraryDependencies = const LibraryRemoteLibraryDependencies(),
    this.computeFingerprint,
    this.isMobileDataConnection,
    this.themeDependencies = const LibraryThemeDependencies(),
  });

  @override
  State<AdaptiveShellScaffold> createState() => _AdaptiveShellScaffoldState();
}

class _AdaptiveShellScaffoldState extends State<AdaptiveShellScaffold> {
  int _currentIndex = 0;
  final _libraryRefreshSignal = ChangeNotifier();

  @override
  void dispose() {
    _libraryRefreshSignal.dispose();
    super.dispose();
  }

  void _navigateTo(int index) {
    setState(() => _currentIndex = index);
    if (index == 0) _libraryRefreshSignal.notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    // 【審查修正 review-plan-issue-1.md C-1】三個子畫面在此直接建構、不
    // 快取成欄位——IndexedStack 讓所有子項全程掛載，Flutter 依
    // runtimeType/清單位置比對重用既有 Element/State，狀態不會遺失；
    // 反之若快取在 initState()，widget.themeDependencies 等參數之後的
    // 變更就永遠傳不到已快取的子畫面（例如使用者在「設定」切主題/E-Ink
    // 後，SettingsScreen/SourcesHomeScreen 拿到的仍是最初舊值）。
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _navigateTo(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            LibraryScreen(
              repository: widget.repository,
              importService: widget.importService,
              prefsManager: widget.prefsManager,
              readerFeatureRepositories: widget.readerFeatureRepositories,
              syncDependencies: widget.syncDependencies,
              cloudAccountDependencies: widget.cloudAccountDependencies,
              remoteLibraryDependencies: widget.remoteLibraryDependencies,
              computeFingerprint: widget.computeFingerprint,
              isMobileDataConnection: widget.isMobileDataConnection,
              themeDependencies: widget.themeDependencies,
              refreshSignal: _libraryRefreshSignal,
              onNavigateToSource: () => _navigateTo(1),
              onNavigateToSettings: () => _navigateTo(2),
            ),
            SourcesHomeScreen(
              repository: widget.repository,
              importService: widget.importService,
              cloudAccountDependencies: widget.cloudAccountDependencies,
              remoteLibraryDependencies: widget.remoteLibraryDependencies,
              computeFingerprint: widget.computeFingerprint,
              isMobileDataConnection: widget.isMobileDataConnection,
              isEinkMode: widget.themeDependencies.isEinkMode,
              onNavigateToLibrary: () => _navigateTo(0),
              onNavigateToSettings: () => _navigateTo(2),
            ),
            SettingsScreen(
              prefsManager: widget.prefsManager,
              currentTheme: widget.themeDependencies.currentTheme,
              isEinkMode: widget.themeDependencies.isEinkMode,
              onThemeChanged: widget.themeDependencies.onThemeChanged,
              onEinkModeChanged: widget.themeDependencies.onEinkModeChanged,
              customFontsRepository:
                  widget.readerFeatureRepositories.customFontsRepository,
              syncAccountRepository: widget.syncDependencies.syncAccountRepository,
              syncClient: widget.syncDependencies.syncClient,
              cloudAccountRepository:
                  widget.cloudAccountDependencies.cloudAccountRepository,
              googleDriveOAuthClient:
                  widget.cloudAccountDependencies.googleDriveOAuthClient,
              oneDriveOAuthClient:
                  widget.cloudAccountDependencies.oneDriveOAuthClient,
            ),
          ],
        ),
      ),
    );
  }
}
```

**注意：不得為上面三個子 widget 加上 `Key`（例如 `UniqueKey()`／依 `_currentIndex` 產生的動態 `Key`）**——那才是真正會打斷狀態保留的寫法（Flutter 遇到不同 `Key` 會判定為不同 widget，捨棄舊 `Element`／`State` 重新建構）。保持目前寫法（無 `key:` 參數，僅靠 `runtimeType` 與清單位置識別）即可。

- [ ] **Step 4: `main.dart` 改用 `AdaptiveShellScaffold`**

編輯 `app/lib/main.dart`，`_ElinkBookAppState.build()` 的 `home:` 整段（原 `LibraryScreen(...)`）改為：

```dart
      home: AdaptiveShellScaffold(
        repository: widget.repository,
        importService: widget.importService,
        prefsManager: widget.prefsManager,
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          bookmarksRepository: widget.bookmarksRepository,
          highlightsRepository: widget.highlightsRepository,
          notesRepository: widget.notesRepository,
          customFontsRepository: widget.customFontsRepository,
          layoutPresetRepository: widget.layoutPresetRepository,
          bookReaderPrefsRepository: widget.bookReaderPrefsRepository,
          ttsProvider: widget.ttsProvider,
          ttsAudioHandler: widget.ttsAudioHandler,
          ttsAudioFocusSource: widget.ttsAudioFocusSource,
        ),
        syncDependencies: LibrarySyncDependencies(
          syncAccountRepository: widget.syncAccountRepository,
          syncClient: widget.syncClient,
          syncCheckpointTrigger: widget.syncCheckpointTrigger,
        ),
        cloudAccountDependencies: LibraryCloudAccountDependencies(
          cloudAccountRepository: widget.cloudAccountRepository,
          googleDriveOAuthClient: widget.googleDriveOAuthClient,
          oneDriveOAuthClient: widget.oneDriveOAuthClient,
          googleDriveStorageClient: widget.googleDriveStorageClient,
          oneDriveStorageClient: widget.oneDriveStorageClient,
        ),
        remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
          remoteServerRepository: widget.remoteServerRepository,
          createOpdsClient: widget.createOpdsClient,
          thumbnailCache: widget.thumbnailCache,
        ),
        computeFingerprint: widget.computeFingerprint,
        isMobileDataConnection: widget.isMobileDataConnection,
        themeDependencies: LibraryThemeDependencies(
          currentTheme: _theme,
          isEinkMode: _isEinkMode,
          onThemeChanged: _handleThemeChanged,
          onEinkModeChanged: _handleEinkModeChanged,
        ),
      ),
```

並在檔案頂部 import 區新增 `import 'screens/adaptive_shell_scaffold.dart';`（`import 'screens/library_screen.dart';` 是否仍需要保留，視 `ElinkBookApp` 其餘程式碼是否還直接引用 `LibraryScreen` 型別而定——目前只有 `home:` 這處引用，若移除後 `flutter analyze` 報告未使用，一併移除）。

- [ ] **Step 5: 執行測試確認通過**

Run: `flutter test test/screens/adaptive_shell_scaffold_test.dart`

依失敗訊息修正 Step 1 中標記「動手前先讀」的佔位斷言（`FakeLibraryRepository` 塞資料 API 等），直到全數通過。

Expected: PASS

- [ ] **Step 6: 執行完整 `library_screen_test.dart` 與 `navigation_test.dart` 確認無回歸**

Run: `flutter test test/screens/library_screen_test.dart test/navigation_test.dart`
Expected: PASS

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/adaptive_shell_scaffold.dart app/test/screens/adaptive_shell_scaffold_test.dart app/lib/main.dart
git commit -m "feat(epic-36): 新增 AdaptiveShellScaffold 並接上 main.dart"
```

---

## Task 6：全套驗證與收尾

**Files:** 無新增/修改，純驗證。

- [ ] **Step 1: 執行全套 `flutter test`（不帶檔案路徑）**

Run: `flutter test`
Expected: 全數通過（比照 `CLAUDE.md`「測試執行範圍」，這是整份計劃收尾的唯一一次全套執行）。若有失敗，比對是否為本計劃改動觸及的檔案；非本計劃觸及範圍的既有不穩定測試（若有）記錄下來，不在本 Issue 修復範圍內。

- [ ] **Step 2: 執行 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 逐條核對 `issues.md` Issue 1 驗收標準**

- [ ] `main.dart:342`（原行號）的 `home:` 已改為 `AdaptiveShellScaffold(...)`
- [ ] 三目的地圖示互相切換為零動畫轉場且狀態不遺失（`IndexedStack`，`MaterialApp.themeAnimationDuration` 已是既有的 `Duration.zero`，不需要在 `AdaptiveShellScaffold` 本身另外設定）
- [ ] 「來源」分頁能完成本機/雲端/OPDS 匯入且與現行行為相同
- [ ] 書架 AppBar 僅剩「排序/檢視、來源、設定」三圖示
- [ ] `app/test/navigation_test.dart` 已改為驗證 callback／新導覽行為（`review-issues.md` I-1）
- [ ] `_pickAndImportFiles`/`_pickAndImportFolder`/`_isImporting`/`_buildImportingOverlay` 等死碼已清理（`review-issues.md` M-3，含計劃範圍澄清第 2 點擴充的五項）

- [ ] **Step 4: 更新 `docs/epics.md` 備註欄位**

將 Epic 36 該列備註改為「Issue 1 已完成，待認領 Issue 2/5」。

- [ ] **Step 5: 依 `superpowers:requesting-code-review` 發起本 Issue 的程式碼審查**

審查者先產出報告至 `docs/epics/epic-36-adaptive-shelf-navigation/reviews/review-issue-1.md`，不得直接修改程式碼（比照專案 SDD 工作流程第 6 步）。

---

## Self-Review 紀錄（撰寫本計劃時的覆核結果）

- **Spec 覆蓋**：`spec.md` §功能①／`issues.md` Issue 1 的 Solution 逐條對照——`AdaptiveShellScaffold`（Task 5）、`SourcesHomeScreen`（Task 2）、`book_import_picker_helper.dart`（Task 1）、AppBar 收斂＋死碼清理（Task 3/4）、系統返回鍵約定 M-1（Task 5 Step 3）、空書架按鈕對齊 M-2（Task 4 Step 3）皆有對應 Task，無遺漏。
- **`review-issues.md` 六項發現**：I-1（Task 3）、I-2（Issue 2 範圍，不動）、I-3（Issue 5 範圍，不動）、M-1（Task 5 明文標注）、M-2（Issue 4 範圍，不動）、M-3（Task 4 死碼清單，並擴充至實際發現的完整死碼集合）——本 Issue 範圍內的三項皆已納入。
- **型別一致性**：`LibraryScreen` 新增的 `refreshSignal`/`onNavigateToSource`/`onNavigateToSettings` 在 Task 3 定義、Task 5 `AdaptiveShellScaffold` 建構 `LibraryScreen` 時原樣使用，命名一致；`SourcesHomeScreen` 的 `onNavigateToLibrary`/`onNavigateToSettings` 在 Task 2 定義、Task 5 建構時原樣使用。
- **範圍落差已於「計劃範圍澄清」段落明文記錄並解決**：`library_manage_groups_button` 併入本 Issue（依驗收標準推導）、擴充版死碼清單（依實際程式碼依賴關係查證）。

## 複審修訂紀錄（`reviews/review-plan-issue-1.md`，2026-09-05）

- **C-1（Critical，已修正）**：`AdaptiveShellScaffold` 原案在 `initState()` 把三個子畫面快取為 `late final List<Widget> _screens`，誤以為「快取一次」才能保留 `LibraryScreen` 狀態。經核實，`IndexedStack` 的狀態保留機制是「所有子項全程掛載＋Flutter 依 `runtimeType`/清單位置重用 `Element`/`State`」，與是否快取無關；快取反而會讓 `widget.themeDependencies` 之後的更新（例如使用者切換主題/E-Ink 模式）永遠傳不到已快取的 `SettingsScreen`/`SourcesHomeScreen`。已改為 `build()` 內直接建構 `IndexedStack.children`（Task 5 Step 3），並補上對應回歸測試（Task 5 Step 1 新增「上層 themeDependencies 更新後...」測試）。Global Constraints、Architecture 摘要、類別 dartdoc 一併同步修正用詞，避免「建構一次」這個錯誤前提在計劃其他段落擴散。
- **I-1（Important，已修正）**：Task 4 補上 `issues.md` 明訂但先前遺漏的「空書架點擊『匯入書籍』呼叫 `onNavigateToSource`」測試。
- **I-2（Important，已修正）**：Task 1 的 `pickAndImportFiles`/`pickAndImportFolder` 補回原程式碼既有的 `try`/`catch` 靜默吞例外行為，並新增兩則例外情境的回歸測試。
- **M-1（Minor，已修正）**：Task 2 的 `_handlePickFolder` 補上 `context.mounted` 檢查後才彈出自動分類確認對話框。
- **M-2（Minor，部分採納並訂正）**：採納「改用 `FakeLibraryRepository.insertBook()` 而非模糊佔位符」的建議，但審查報告附的範例程式碼本身遺漏 `Book` 建構子必填的 `format`/`source` 欄位、無法編譯——已核實 `app/lib/library/models/book.dart` 建構子簽章後訂正為可編譯版本。
- **M-3（Minor，已修正）**：Task 4 一併補上「點擊 `library_source_button` 呼叫 `onNavigateToSource`」的獨立單元測試。
