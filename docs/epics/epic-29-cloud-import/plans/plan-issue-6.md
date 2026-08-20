# Epic 29 Issue 6：行動數據下載警示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Epic 29 Issue 3/4 已建好的雲端瀏覽/下載流程中，加入行動數據流量警示——使用者在行動數據連線下勾選超過 20MB 的雲端檔案並按下「下載已選取」時，下載前先跳出確認對話框，確認才繼續、取消則不下載。

**Architecture:** 檢查點設在 `CloudBrowserScreen._startDownload()`（`CloudDownloadQueueDialog` 開啟之前），因為 `CloudFileEntry.sizeBytes` 在 `listFolder()` 當下就已經知道，不需要真的下載檔案才能判斷大小。多選批次時**採整批判斷一次**（見下方「批次判斷方式決策」），不逐檔案分別跳出確認框。連線狀態偵測沿用 `epic-30-calibre-remote-library` Issue 4 已建置、`main.dart`／`library_screen.dart` 現行貫穿到位的 `Future<bool> Function()? isMobileDataConnection` callback（`connectivity_plus` 套件已在 `pubspec.yaml` 內，`Connectivity().checkConnectivity()` 判斷結果含 `ConnectivityResult.mobile`），只需要把這個既有 callback 再往下貫穿到 `CloudBrowserScreen`，**不需要新增任何依賴、不需要新增資料模型**。

**Tech Stack:** Flutter/Dart，`connectivity_plus`（既有依賴，無需新增）。

**Spec:** [`docs/epics/epic-29-cloud-import/spec.md`](../spec.md)「Further Notes」（行動數據下載警示閾值：單檔 > 20MB，建議值）；[`docs/epics/epic-29-cloud-import/issues.md`](../issues.md) Issue 6。

## 批次判斷方式決策

Issue 6 的「What to build」明確把「多選批次時對每個超過閾值的檔案如何生效（整批判斷一次 vs. 逐檔判斷）」留給實作者定案，兩種皆可接受。本計劃採用**整批判斷一次**：勾選的檔案清單中只要有任何一個 `sizeBytes` 超過門檻，且目前為行動數據連線，就在開始整個下載佇列**之前**跳出單一次確認對話框；使用者確認後，整批（含未超過門檻的檔案）照常依序下載，不逐檔案再次詢問。

**理由：**
1. `CloudDownloadQueueDialog` 是一個已經在執行中的 `StatefulWidget`（`initState()` 內直接呼叫 `_runQueue()` 依序下載），要在佇列執行到某個超過門檻的項目時「暫停佇列、跳出確認框、等使用者回應、再繼續佇列」需要對 `_runQueue()`/`_downloadOne()` 做較大幅度的狀態機改造（暫停/恢復語意），改動範圍會外溢到 Issue 5 剛審查合併、已驗證穩定的 `cloud_download_queue_dialog.dart`。整批判斷一次則完全不需要碰這個檔案——`sizeBytes` 在 `CloudBrowserScreen` 進入下載佇列**之前**就已經知道，檢查點放在 `_startDownload()` 內，`CloudDownloadQueueDialog` 完全不需要感知「行動數據」這個概念。
2. 使用者體驗上，「勾了 5 個檔案、下載到第 3 個時才跳出行動數據警示」比「一開始就告知這批裡有大檔案、要不要用行動數據下載」更容易讓使用者困惑（已經看到前兩個檔案下載完成，卻在中途被詢問「是否要用行動數據下載」，語意上不清楚問的是整批還是剩下的檔案）。整批判斷一次在使用者按下「下載已選取」的當下、佇列真正開始前就給出明確的一次性決定，心智模型更單純。
3. 比照本 Epic 既有的 `library_screen.dart._handleRedownload()`／`_confirmRedownload()`（epic-30-calibre-remote-library Issue 4 建置）既有模式——同樣是「下載前一次性詢問」，不是「下載中逐步詢問」。

## Global Constraints

- 所有回應、程式註解、文件、commit 訊息一律使用正體中文（zh-TW），禁止簡體中文。
- 審查一律先產出報告，不得直接修改被審查的計劃/程式碼（本專案 SDD 工作流程慣例）。
- `flutter analyze` 必須保持乾淨（"No issues found!"）；`flutter test` 全數通過、零回歸。
- 不新增任何 `pubspec.yaml` 依賴——`connectivity_plus` 已存在，`isMobileDataConnection` callback 型別已由 `main.dart`／`library_screen.dart` 定義完成，本 Issue 只需要延伸貫穿範圍。
- 每完成一個 Task 的 Step，把該 Step 前面的 `- [ ]` 改成 `- [x]`。

---

## 現況（實作前必讀）

- `app/lib/screens/cloud_browser_screen.dart`：`CloudBrowserScreen` 目前建構參數為 `client`／`libraryRepository`／`importService`／`source`／`computeFingerprint`／`folderId`／`title`，**沒有** `isMobileDataConnection` 欄位。`_startDownload()`（第 176-196 行）目前直接組 `folderName` 後開啟 `CloudDownloadQueueDialog`，沒有任何行動數據檢查。`_openSubfolder()`（第 134-146 行）遞迴建構下一層 `CloudBrowserScreen` 時，會把 `computeFingerprint` 等既有欄位轉發，未來新增的 `isMobileDataConnection` 同樣需要在這裡轉發，否則使用者往下鑽資料夾後，行動數據警示會在子資料夾內靜默失效。
- `app/lib/screens/library_screen.dart`：`LibraryScreen` 本身**已有** `final Future<bool> Function()? isMobileDataConnection;` 欄位（第 70 行，`epic-30-calibre-remote-library` Issue 4 建置，供 `_handleRedownload()`「待下載」書籍重新下載警示使用，第 651 行：`await (widget.isMobileDataConnection?.call() ?? Future.value(false))`）。`_openGoogleDriveBrowser()`（第 264-285 行）／`_openOneDriveBrowser()`（第 287-305 行）目前建構 `CloudBrowserScreen` 時**沒有**轉發這個既有欄位（因為 `CloudBrowserScreen` 目前根本沒有這個參數）。`_openGroupFilteredView()`（第 725-788 行，分類篩選畫面的自我遞迴導航點）建構下一層 `LibraryScreen` 時，同樣**沒有**轉發 `isMobileDataConnection`——這是一個先於本 Issue 就存在的缺口（該欄位自 epic-30 Issue 4 加入以來，這個遞迴點就從未轉發過它，因為當時沒有任何下游畫面需要它），Issue 6 讓 `CloudBrowserScreen` 開始依賴這個欄位後，若不順手補上，會讓「從分類篩選畫面進入的雲端匯入」失去流量警示（不影響「能不能匯入」，只影響「是否顯示流量提醒」，比 `computeFingerprint`／`googleDriveStorageClient` 那兩次漏轉發的後果輕微，但同一種錯誤模式已經在這個遞迴點重複出現兩次，見 `review-issue-3.md` Important #1、`review-issue-5.md` Important #1，本次一併主動補上，避免第三次重演）。
- `app/lib/cloud_import/cloud_storage_client.dart`：`CloudFileEntry` 已有 `final int? sizeBytes;` 欄位（第 59 行，Issue 3 就已定義），本 Issue **不需要修改**這個檔案，`FakeCloudStorageClient`／`GoogleDriveStorageClient`／`OneDriveStorageClient` 對 `sizeBytes` 的填值皆已到位。
- `app/lib/main.dart`：`_isMobileDataConnection()`（第 47-56 行）與 `isMobileDataConnection: _isMobileDataConnection` 已貫穿到 `LibraryScreen`（第 165 行），本 Issue **不需要修改**這個檔案。

---

## Task 1：`CloudBrowserScreen` 行動數據下載警示核心邏輯

**Files:**
- Modify: `app/lib/screens/cloud_browser_screen.dart`
- Test: `app/test/screens/cloud_browser_screen_test.dart`

**Interfaces:**
- Consumes：`CloudFileEntry.sizeBytes`（`app/lib/cloud_import/cloud_storage_client.dart:59`，既有欄位，`int?`）；`FakeCloudStorageClient`（`app/test/support/fake_cloud_storage_client.dart`，既有測試替身，無需修改）；`FakeBookImportService.lastImportCall`（`app/test/support/fake_book_import_service.dart:38`，既有欄位，`ImportCallRecord?`）。
- Produces：`CloudBrowserScreen` 新增的必要（實際上是可選，維持與其他選填欄位一致的 nullable 慣例）建構參數 `final Future<bool> Function()? isMobileDataConnection;`，供 Task 2 的 `library_screen.dart` 貫穿注入；新增的私有方法 `_confirmMobileDataDownload()` 與私有頂層常數 `_mobileDataWarningThresholdBytes`（僅本檔案內部使用，不對外暴露）。

- [ ] **Step 1：寫失敗測試——行動數據連線且勾選檔案超過門檻時，下載前跳出確認對話框，確認後正常下載**

在 `app/test/screens/cloud_browser_screen_test.dart` 第 34 行（`fileEntryWithThumbnail` 常數定義之後）新增兩個測試用 `CloudFileEntry` 常數：

```dart
  const largeFileEntry = CloudFileEntry(
    id: 'file-large',
    name: '大檔案.epub',
    isFolder: false,
    format: BookFileFormat.epub,
    sizeBytes: 25 * 1024 * 1024, // 25MB，超過 20MB 門檻
  );
  const smallFileEntry = CloudFileEntry(
    id: 'file-small',
    name: '小檔案.epub',
    isFolder: false,
    format: BookFileFormat.epub,
    sizeBytes: 1 * 1024 * 1024, // 1MB，未超過門檻
  );
```

把 `pumpScreen` 輔助函式（第 65-84 行）的參數清單擴充一個可選參數，並轉發給 `CloudBrowserScreen`：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeCloudStorageClient client,
    FakeLibraryRepository? libraryRepository,
    FakeBookImportService? importService,
    FakeFingerprintComputer? fingerprintComputer,
    Future<bool> Function()? isMobileDataConnection,
    String? folderId,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: CloudBrowserScreen(
        client: client,
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        importService: importService ?? FakeBookImportService(),
        source: BookSource.googleDrive,
        computeFingerprint: (fingerprintComputer ?? FakeFingerprintComputer()).call,
        isMobileDataConnection: isMobileDataConnection,
        folderId: folderId,
      ),
    ));
    await tester.pumpAndSettle();
  }
```

在檔案最後（`});` 收尾大括號之前，也就是現有「選檔前置重複偵測（Layer 1）」`group` 區塊之後）新增一個新的 `group`：

```dart
  group('行動數據下載警示（Epic 29 Issue 6）', () {
    testWidgets('行動數據連線且勾選檔案超過門檻時，下載前跳出確認對話框，確認後正常下載',
        (tester) async {
      final importService = FakeBookImportService();
      final client = FakeCloudStorageClient(
        folderContents: {
          null: const CloudFolderListing(entries: [largeFileEntry]),
        },
        downloadContents: {'file-large': [1, 2, 3]},
      );
      await pumpScreen(
        tester,
        client: client,
        importService: importService,
        isMobileDataConnection: () async => true,
      );

      await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-large')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('google_drive_browser_download_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloud_mobile_data_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloud_mobile_data_dialog_confirm')));
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloud_download_queue_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloud_download_queue_done_button')));
      await tester.pumpAndSettle();

      expect(importService.lastImportCall, isNotNull);
    });
  });
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/cloud_browser_screen_test.dart --plain-name "行動數據連線且勾選檔案超過門檻時"
```

預期：編譯失敗（`isMobileDataConnection` 不是 `CloudBrowserScreen` 的已知具名參數）或執行期找不到 `Key('cloud_mobile_data_dialog')`。

- [ ] **Step 3：實作 `CloudBrowserScreen` 行動數據警示邏輯**

修改 `app/lib/screens/cloud_browser_screen.dart`。在檔案頂部 import 區塊之後（第 11 行 `import 'cloud_download_queue_dialog.dart';` 之後）新增門檻常數：

```dart
/// 【Epic 29 Issue 6，spec.md「Further Notes」建議值】單檔案大小門檻——
/// 目前為行動數據連線且勾選的檔案中有任何一個超過此值時，下載前顯示流量
/// 警示（見本檔案 `_startDownload()`／`_confirmMobileDataDownload()`）。
const _mobileDataWarningThresholdBytes = 20 * 1024 * 1024;
```

在 `CloudBrowserScreen` class 的欄位清單（`computeFingerprint` 欄位之後、`folderId` 欄位之前，約第 43-47 行）新增：

```dart
  /// 【Epic 29 Issue 6】偵測目前是否為行動數據連線，與
  /// `library_screen.dart._handleRedownload()` 共用同一個 provider 無關的
  /// callback 型別（定義於 `main.dart._isMobileDataConnection`，底層為
  /// `connectivity_plus` 的 `Connectivity().checkConnectivity()`）。`null`
  /// 時視同「無法判斷連線類型」，不顯示警示（比照 `library_screen.dart`
  /// 既有 `?? Future.value(false)` 退回慣例）。
  final Future<bool> Function()? isMobileDataConnection;
```

在建構子的具名參數清單（`this.computeFingerprint` 之後——注意 `computeFingerprint` 是 `required`，`isMobileDataConnection` 不是，需放在 optional 參數群組內，約第 60 行 `this.folderId,` 之前）新增：

```dart
    this.isMobileDataConnection,
```

修改 `_openSubfolder()`（原第 134-146 行），在遞迴建構的 `CloudBrowserScreen(...)` 內新增轉發：

```dart
  void _openSubfolder(CloudFileEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => CloudBrowserScreen(
        client: widget.client,
        libraryRepository: widget.libraryRepository,
        importService: widget.importService,
        source: widget.source,
        computeFingerprint: widget.computeFingerprint,
        isMobileDataConnection: widget.isMobileDataConnection,
        folderId: entry.id,
        title: entry.name,
      ),
    ));
  }
```

修改 `_startDownload()`（原第 176-196 行），在組 `folderName` 之前插入行動數據檢查：

```dart
  Future<void> _startDownload() async {
    final selected = _entries.where((e) => _selectedIds.contains(e.id)).toList();
    if (selected.isEmpty) return;

    final hasLargeFile = selected.any(
      (e) => e.sizeBytes != null && e.sizeBytes! > _mobileDataWarningThresholdBytes,
    );
    if (hasLargeFile) {
      final isMobileData =
          await (widget.isMobileDataConnection?.call() ?? Future.value(false));
      if (!mounted) return;
      if (isMobileData) {
        final proceed = await _confirmMobileDataDownload();
        if (!mounted) return;
        if (proceed != true) return;
      }
    }

    final folderName =
        _selectedGroupName == BookGroup.uncategorized ? null : _selectedGroupName;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CloudDownloadQueueDialog(
        entries: selected,
        client: widget.client,
        importService: widget.importService,
        libraryRepository: widget.libraryRepository,
        computeFingerprint: widget.computeFingerprint,
        source: widget.source,
        folderName: folderName,
      ),
    );
    if (!mounted) return;
    setState(() => _selectedIds.clear());
  }

  /// 【Epic 29 Issue 6】整批判斷一次的行動數據流量警示彈窗（見本計劃「批次
  /// 判斷方式決策」）——只在 `_startDownload()` 偵測到「行動數據連線＋勾選
  /// 檔案內有超過門檻的項目」時才會被呼叫一次，不逐檔案詢問。UI 慣例比照
  /// `library_screen.dart._confirmRedownload()`。
  Future<bool?> _confirmMobileDataDownload() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('cloud_mobile_data_dialog'),
        title: const Text('行動數據下載提醒'),
        content: const Text(
          '目前使用行動數據連線，勾選的檔案中有超過 20MB 的項目，下載可能產生流量費用，'
          '確定要繼續嗎？',
        ),
        actions: [
          TextButton(
            key: const Key('cloud_mobile_data_dialog_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('cloud_mobile_data_dialog_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('繼續下載'),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 4：執行測試，確認通過**

```bash
cd app
flutter test test/screens/cloud_browser_screen_test.dart --plain-name "行動數據連線且勾選檔案超過門檻時"
```

預期：PASS。

- [ ] **Step 5：補齊其餘 3 個必要情境的測試**

在同一個 `group('行動數據下載警示（Epic 29 Issue 6）', () { ... })` 內，緊接 Step 1 新增的測試之後，補上以下三個測試：

```dart
    testWidgets('Wi-Fi 連線時即使檔案超過門檻也不跳出確認對話框，直接開始下載',
        (tester) async {
      final importService = FakeBookImportService();
      final client = FakeCloudStorageClient(
        folderContents: {
          null: const CloudFolderListing(entries: [largeFileEntry]),
        },
        downloadContents: {'file-large': [1, 2, 3]},
      );
      await pumpScreen(
        tester,
        client: client,
        importService: importService,
        isMobileDataConnection: () async => false,
      );

      await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-large')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('google_drive_browser_download_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloud_mobile_data_dialog')), findsNothing);
      expect(find.byKey(const Key('cloud_download_queue_dialog')), findsOneWidget);
    });

    testWidgets('行動數據連線但勾選檔案未超過門檻時不跳出確認對話框，直接開始下載',
        (tester) async {
      final importService = FakeBookImportService();
      final client = FakeCloudStorageClient(
        folderContents: {
          null: const CloudFolderListing(entries: [smallFileEntry]),
        },
        downloadContents: {'file-small': [1, 2, 3]},
      );
      await pumpScreen(
        tester,
        client: client,
        importService: importService,
        isMobileDataConnection: () async => true,
      );

      await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-small')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('google_drive_browser_download_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloud_mobile_data_dialog')), findsNothing);
      expect(find.byKey(const Key('cloud_download_queue_dialog')), findsOneWidget);
    });

    testWidgets('行動數據確認對話框選擇取消時不開始下載', (tester) async {
      final importService = FakeBookImportService();
      final client = FakeCloudStorageClient(
        folderContents: {
          null: const CloudFolderListing(entries: [largeFileEntry]),
        },
        downloadContents: {'file-large': [1, 2, 3]},
      );
      await pumpScreen(
        tester,
        client: client,
        importService: importService,
        isMobileDataConnection: () async => true,
      );

      await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-large')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('google_drive_browser_download_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cloud_mobile_data_dialog_cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloud_download_queue_dialog')), findsNothing);
      expect(importService.lastImportCall, isNull);
    });
  });
```

- [ ] **Step 6：執行整個測試檔案，確認全數通過、零回歸**

```bash
cd app
flutter test test/screens/cloud_browser_screen_test.dart
flutter analyze
```

預期：`flutter analyze` 顯示 "No issues found!"；`cloud_browser_screen_test.dart` 內全部測試（既有＋本次新增的 4 則）皆 PASS。

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/cloud_browser_screen.dart app/test/screens/cloud_browser_screen_test.dart
git commit -m "feat(epic-29): Issue 6 Task 1——CloudBrowserScreen 行動數據下載警示（整批判斷一次）"
```

---

## Task 2：貫穿 `LibraryScreen`（含自我遞迴導航點修復）

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 產出的 `CloudBrowserScreen.isMobileDataConnection`（`Future<bool> Function()?`）；`LibraryScreen` 既有欄位 `widget.isMobileDataConnection`（`app/lib/screens/library_screen.dart:70`，`epic-30-calibre-remote-library` Issue 4 已建置，本 Task 不新增、只擴大貫穿範圍）。
- Produces：無新公開介面——本 Task 純粹是既有欄位的貫穿範圍擴大。

- [ ] **Step 1：寫失敗測試——`_openGoogleDriveBrowser()`／`_openOneDriveBrowser()` 轉發 `isMobileDataConnection`**

在 `app/test/screens/library_screen_test.dart` 內尋找建構 `CloudBrowserScreen` 相關的既有測試（搜尋 `googleDriveStorageClient:` 附近、驗證「從 Google Drive 匯入」選單項目點擊後 push 的畫面的測試），若既有測試中沒有直接斷言 push 出的 `CloudBrowserScreen.isMobileDataConnection` 欄位，新增一則測試：

```dart
  testWidgets(
      '點擊「從 Google Drive 匯入」push 出的 CloudBrowserScreen，isMobileDataConnection '
      '與外層一致（Epic 29 Issue 6）', (tester) async {
    final googleDriveStorageClient = FakeCloudStorageClient();
    final computeFingerprint = FakeFingerprintComputer().call;
    Future<bool> isMobileDataConnection() async => false;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          googleDriveStorageClient: googleDriveStorageClient,
          computeFingerprint: computeFingerprint,
          isMobileDataConnection: isMobileDataConnection,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_import_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_google_drive_option')));
    await tester.pumpAndSettle();

    final browserScreen = tester.widget<CloudBrowserScreen>(find.byType(CloudBrowserScreen));
    expect(browserScreen.isMobileDataConnection, same(isMobileDataConnection),
        reason: '_openGoogleDriveBrowser() 未把 isMobileDataConnection 貫穿給 '
            'CloudBrowserScreen，行動數據下載警示會靜默失效');
  });
```

`library_import_button`（第 885 行）／`library_import_google_drive_option`（第 901 行）為 `library_screen.dart` 既有選單/選項的實際 `Key` 字串，已核對無誤，可直接套用。

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/library_screen_test.dart --plain-name "isMobileDataConnection 與外層一致"
```

預期：編譯失敗（`CloudBrowserScreen` 尚無 `isMobileDataConnection` 具名參數，此為 Task 1 產出，若 Task 1 已完成則改為執行期斷言失敗：`isMobileDataConnection` 為 `null`）。

- [ ] **Step 3：修改 `_openGoogleDriveBrowser()`／`_openOneDriveBrowser()`**

修改 `app/lib/screens/library_screen.dart` 第 264-305 行：

```dart
  void _openGoogleDriveBrowser(CloudStorageClient client) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (context) => CloudBrowserScreen(
            client: client,
            libraryRepository: widget.repository,
            importService: widget.importService,
            source: BookSource.googleDrive,
            computeFingerprint: widget.computeFingerprint!,
            isMobileDataConnection: widget.isMobileDataConnection,
          ),
        ))
        .then((_) {
      if (mounted) {
        _loadGroups();
        _loadBooks();
      }
    });
  }

  void _openOneDriveBrowser(CloudStorageClient client) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (context) => CloudBrowserScreen(
            client: client,
            libraryRepository: widget.repository,
            importService: widget.importService,
            source: BookSource.oneDrive,
            computeFingerprint: widget.computeFingerprint!,
            isMobileDataConnection: widget.isMobileDataConnection,
            title: 'OneDrive',
          ),
        ))
        .then((_) {
      if (mounted) {
        _loadGroups();
        _loadBooks();
      }
    });
  }
```

（只新增 `isMobileDataConnection: widget.isMobileDataConnection,` 這一行到兩個方法內，其餘程式碼不變。）

- [ ] **Step 4：執行測試，確認通過**

```bash
cd app
flutter test test/screens/library_screen_test.dart --plain-name "isMobileDataConnection 與外層一致"
```

預期：PASS。

- [ ] **Step 5：擴充 `_openGroupFilteredView()` 既有回歸測試，補上 `isMobileDataConnection` 斷言**

`app/test/screens/library_screen_test.dart` 內既有一則測試（`review-issue-3.md Important #1`、`review-issue-5.md Important #1` 採納，約第 2966-3008 行），驗證 `_openGroupFilteredView()` 正確轉發 `googleDriveStorageClient`／`computeFingerprint`。找到這則測試，把測試標題與內容一併擴充：

```dart
  testWidgets(
      'LibraryScreen 透過分類篩選路徑（_openGroupFilteredView）進入後，'
      'googleDriveStorageClient／computeFingerprint／isMobileDataConnection 皆與外層一致'
      '（review-issue-3.md Important #1、review-issue-5.md Important #1、'
      'Epic 29 Issue 6 一併補上 採納）',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      groupName: '奇幻',
      filePath: 'content://example/1.txt',
    );
    final googleDriveStorageClient = FakeCloudStorageClient();
    final computeFingerprint = FakeFingerprintComputer().call;
    Future<bool> isMobileDataConnection() async => false;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          googleDriveStorageClient: googleDriveStorageClient,
          computeFingerprint: computeFingerprint,
          isMobileDataConnection: isMobileDataConnection,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    final filteredScreen = tester.widget<LibraryScreen>(filteredScreenFinder);
    expect(filteredScreen.googleDriveStorageClient, same(googleDriveStorageClient),
        reason: '_openGroupFilteredView() 未把 googleDriveStorageClient 貫穿給下一層 '
            'LibraryScreen，會導致分類篩選畫面內「從 Google Drive 匯入」選單項目 '
            '永遠停用');
    expect(filteredScreen.computeFingerprint, same(computeFingerprint),
        reason: '_openGroupFilteredView() 未把 computeFingerprint 貫穿給下一層 '
            'LibraryScreen，會導致分類篩選畫面內「從 Google Drive／OneDrive 匯入」'
            '選單項目一起被誤停用（Issue 5 新增的門檻條件同時檢查 '
            'computeFingerprint != null）');
    expect(filteredScreen.isMobileDataConnection, same(isMobileDataConnection),
        reason: '_openGroupFilteredView() 未把 isMobileDataConnection 貫穿給下一層 '
            'LibraryScreen，會導致分類篩選畫面內雲端下載流量警示靜默失效（Issue 6）');
  });
```

（只在既有測試的標題與 `LibraryScreen(...)` 建構參數內新增 `isMobileDataConnection` 相關的一行，並在既有兩個 `expect` 之後新增第三個 `expect`，其餘程式碼不變。）

- [ ] **Step 6：修改 `_openGroupFilteredView()`**

修改 `app/lib/screens/library_screen.dart` 第 725-788 行，在 `computeFingerprint: widget.computeFingerprint,` 之後（`currentTheme: widget.currentTheme,` 之前）新增：

```dart
              // 【Epic 29 Issue 6】isMobileDataConnection 自 epic-30 Issue 4
              // 加入以來，這個自我遞迴導航點便一直未轉發（當時沒有下游畫面
              // 需要它）；Issue 6 讓 CloudBrowserScreen 開始依賴這個欄位後，
              // 若不轉發，分類篩選路徑內的雲端下載流量警示會靜默失效——比照
              // 上方 computeFingerprint／googleDriveStorageClient 兩次漏轉發
              // 的既有修正慣例，這次主動補上，避免同一種錯誤模式第三次重演
              // （見 review-issue-3.md Important #1、review-issue-5.md
              // Important #1）。
              isMobileDataConnection: widget.isMobileDataConnection,
              computeFingerprint: widget.computeFingerprint,
              currentTheme: widget.currentTheme,
```

（把新增的 `isMobileDataConnection: widget.isMobileDataConnection,` 放在既有 `computeFingerprint: widget.computeFingerprint,` 那一行的前面或後面皆可，上方範例放在前面；確保這行確實加入 `_openGroupFilteredView()` 內建構的 `LibraryScreen(...)` 參數清單即可。）

- [ ] **Step 7：執行測試，確認通過**

```bash
cd app
flutter test test/screens/library_screen_test.dart --plain-name "isMobileDataConnection"
```

預期：Step 1 與 Step 5 新增/擴充的測試皆 PASS。

- [ ] **Step 8：執行完整測試套件與靜態分析，確認零回歸**

```bash
cd app
flutter analyze
flutter test
```

預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS（相對 Issue 5 完成時的 1628 項，Task 1 新增 4 項、Task 2 新增 1 項，共增加 5 項，其餘既有測試不受影響）。

- [ ] **Step 9：Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-29): Issue 6 Task 2——貫穿 LibraryScreen 的 isMobileDataConnection（含自我遞迴導航點修復）"
```

---

## 自我審查（Self-Review）記錄

**規格覆蓋度：**
- spec.md「Further Notes」單檔 > 20MB 閾值 → Task 1 `_mobileDataWarningThresholdBytes = 20 * 1024 * 1024`。✅
- issues.md Issue 6「行動數據＋大檔案（跳出確認）」→ Task 1 Step 1。✅
- 「Wi-Fi（不跳出確認）」→ Task 1 Step 5 第一則測試。✅
- 「行動數據＋小檔案（不跳出確認）」→ Task 1 Step 5 第二則測試。✅
- 「使用者取消確認（不下載）」→ Task 1 Step 5 第三則測試。✅
- 「多選批次時...由實作者定案並說明理由」→ 本文件頂部「批次判斷方式決策」小節。✅
- 「Blocked by：Issue 3」→ 本計劃建立於 Issue 3/4/5 已合併的 `CloudBrowserScreen`／`CloudDownloadQueueDialog` 之上，未修改 Issue 3/4/5 既有邏輯（`cloud_download_queue_dialog.dart` 完全不改動）。✅

**佔位符掃描：** 全文無 "TBD"／"implement later"／"add appropriate error handling" 等禁止字樣，所有程式碼區塊皆為可直接套用的完整內容。

**型別一致性檢查：** `isMobileDataConnection` 型別 `Future<bool> Function()?` 在 Task 1（`CloudBrowserScreen` 新欄位）與 Task 2（`LibraryScreen` 既有欄位、`_openGoogleDriveBrowser`/`_openOneDriveBrowser`/`_openGroupFilteredView` 轉發）三處完全一致，與 `main.dart._isMobileDataConnection`／`library_screen.dart._handleRedownload()` 既有用法的型別相同，無新增型別別名。`_confirmMobileDataDownload()` 回傳 `Future<bool?>`，呼叫端 `_startDownload()` 用 `proceed != true` 判斷（`null`／`false` 皆視為取消），與 `library_screen.dart._confirmRedownload()`／`_handleRedownload()` 的既有 `confirmed != true` 判斷慣例一致。

**簡體字掃描：** 全文以正體中文撰寫，未使用任何簡體字。

---

## 執行方式選擇

計劃完成，已存至 `docs/epics/epic-29-cloud-import/plans/plan-issue-6.md`。兩種執行方式可選：

1. **Subagent-Driven（建議）**——每個 Task 派一個全新 subagent 實作，兩階段審查，快速迭代。
2. **Inline Execution**——在本次對話內依 Task 順序批次執行，每個檢查點暫停確認。

請問要採用哪一種方式？
