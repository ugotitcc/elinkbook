# Epic 26 Issue 7：收斂 `LibraryScreen` 建構子的參數膨脹（27→單位數 bundle）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 以逐 Task 執行本計畫。步驟採用 checkbox（`- [ ]`）語法追蹤進度。

**Goal:** 把 `LibraryScreen` 建構子目前 27 個具名參數中、25 個「同質但各自宣告」的可選參數，依實際轉送足跡（forwarding footprint）收斂為 5 個小型不可變 bundle 物件，取代目前逐一具名參數的宣告/轉送方式，同時維持零行為改變。

**Architecture:** 新增 5 個不可變資料類別（純資料持有者，無邏輯，皆為 nullable 欄位以維持現行「功能未啟用時為 null」語意）於單一新檔案 `app/lib/screens/library_screen_dependencies.dart`；`LibraryScreen` 建構子改為接收這 5 個 bundle（各自可選，皆有 `const` 空預設值），`repository`／`importService`／`prefsManager`（必要）與 `computeFingerprint`／`isMobileDataConnection`／`groupFilter`（可選但無法乾淨併入任何 bundle，見下方查證）維持獨立參數不變。

**Tech Stack:** Flutter／Dart，無新增套件依賴。

**Spec:** `docs/epics/epic-26-architecture-hardening/issues.md` Issue 7；`docs/research/architecture-review-library-remote-screens.md` 候選 5。

## 規劃階段查證：為何是 5 個 bundle、而非 Issue 7 原文例示的 2-3 個（務必先讀）

Issue 7 原文僅為「例示」分組（原文明講「具體分組方式…由規劃階段定案」），逐欄位交叉核對 `library_screen.dart` 目前所有轉送/使用足跡（`_openBook()` → `ReaderScreen`；`_openGroupFilteredView()` 自我遞迴 → `LibraryScreen`；`_buildAppBarActions()` → `RemoteServerListScreen`／`SettingsScreen`；`_openGoogleDriveBrowser()`/`_openOneDriveBrowser()` → `CloudBrowserScreen`；`_handleRedownload()`）後，原文例示的分組與現況有 3 處實質落差，若照抄字面分組會製造新的行為風險，故本計畫依實測足跡調整：

1. **原文建議「既有 repository 群組」含 `syncAccountRepository`，但 `syncAccountRepository` 從未轉送給 `ReaderScreen`**（只轉送給 `SettingsScreen` 與自我遞迴），與同群組其餘 6 個欄位（`bookmarksRepository`／`highlightsRepository`／`notesRepository`／`customFontsRepository`／`layoutPresetRepository`／`bookReaderPrefsRepository`，皆轉送給 `ReaderScreen`）足跡不同——`syncAccountRepository` 改與 `syncClient`／`syncCheckpointTrigger` 同組（**Bundle 2：`LibrarySyncDependencies`**），這三者才是真正同質（皆為「帳號同步」網域、自我遞迴皆整組轉送）。
2. **原文建議「雲端/遠端群組」把 `remoteServerRepository` 與 `cloudAccountRepository`／`googleDriveOAuthClient`／`oneDriveOAuthClient`／`googleDriveStorageClient`／`oneDriveStorageClient` 合為一組，並建議「可與 Issue 6 的 bundle 整合」**：查證發現 `_openGroupFilteredView()` 自我遞迴目前**整組轉送**後 5 者（`cloudAccountRepository`/`googleDriveOAuthClient`/`oneDriveOAuthClient`/`googleDriveStorageClient`/`oneDriveStorageClient`，`library_screen.dart:747-755`），但**完全不轉送** `remoteServerRepository`／`createOpdsClient`／`thumbnailCache`（OPDS 遠端書庫按鈕在分類篩選子畫面內本來就不會出現，這是現行既有行為，非疏漏）。若把 `remoteServerRepository` 併入同一個「整組轉送」的 bundle，會讓自我遞迴的「整包轉送」寫法（`cloudAccountDependencies: widget.cloudAccountDependencies`）意外把 `remoteServerRepository` 也帶進子畫面——即使因為 `createOpdsClient`／`thumbnailCache` 仍分開、門檻判斷不會因此顯示按鈕，這種「欄位洩漏但恰好無害」的設計本身就是未來重構時的地雷，故 `remoteServerRepository`／`createOpdsClient`／`thumbnailCache` 獨立成 **Bundle 4：`LibraryRemoteLibraryDependencies`**，`cloudAccountRepository`／`googleDriveOAuthClient`／`oneDriveOAuthClient`／`googleDriveStorageClient`／`oneDriveStorageClient` 獨立成 **Bundle 3：`LibraryCloudAccountDependencies`**，兩者網域也天生不同（前者是 OPDS/Calibre 遠端書庫站點，後者是 Google Drive／OneDrive 個人雲端帳號）。
3. **`computeFingerprint`（`ComputeRemoteFingerprint`）刻意不併入任何 bundle**：其轉送足跡橫跨 `CloudBrowserScreen`（雲端匯入重複偵測）、自我遞迴（整組轉送）、popup menu 門檻判斷（與 `googleDriveStorageClient`／`oneDriveStorageClient` 各自搭配）、`RemoteServerListScreen` 門檻判斷（與 `remoteServerRepository`／`createOpdsClient`／`thumbnailCache` 搭配），與 Bundle 3、Bundle 4 兩者都有交集但都不是「完全相同足跡」——這正是 Issue 6 規劃階段已確立的同一種風險模式（`RemoteCatalogDependencies` 刻意不吸收 `computeFingerprint` 以外的用途），本計畫延續同一原則，`computeFingerprint` 維持獨立參數。同理 `isMobileDataConnection`（足跡橫跨 `CloudBrowserScreen`／自我遞迴／`_handleRedownload`，三者分屬不同網域）也維持獨立參數。
4. `groupFilter` 依 Issue 7 原文明文指示維持獨立參數（不打包）。

**結論：** 5 個 bundle（`LibraryReaderFeatureRepositories`／`LibrarySyncDependencies`／`LibraryCloudAccountDependencies`／`LibraryRemoteLibraryDependencies`／`LibraryThemeDependencies`）＋ 6 個獨立核心參數（`repository`／`importService`／`prefsManager`／`computeFingerprint`／`isMobileDataConnection`／`groupFilter`）＝ 11 個建構子參數，符合驗收標準「27 個收斂為個位數的 bundle＋少數核心參數」（5 個 bundle 本身即為個位數）。

**已知既有行為（非本計畫引入、亦非本計畫修正範圍，原樣保留）：** `SettingsScreen` 呼叫端（`library_screen.dart:979-991`）目前只轉送 `onThemeChanged` 不轉送 `onEinkModeChanged`——這個不對稱是現行既有程式碼行為，本計畫零行為改變原則下原樣保留，不在本 Issue 修正。

## Global Constraints

- 程式碼註解／變數說明使用中文，遵循既有檔案風格。
- `flutter analyze` 涵蓋 `app/integration_test/`——`integration_test/library_screen_test.dart` 目前只使用 `repository`／`importService`／`prefsManager` 三個必要參數建構 `LibraryScreen`，不受本次任何 bundle 異動影響，仍需確保能編譯通過。
- 維持 ADR 0007「平行建構子參數、不用 service locator」的組裝哲學——5 個 bundle 皆為透過建構子參數傳遞的**資料**物件，不是任何形式的 service locator／全域單例。
- 零行為改變：本計畫是純重構，不新增、不移除、不調整任何使用者可觀察行為，包含上述「已知既有行為」段落列出的既有不對稱轉送模式。
- 每個 bundle 皆為 `@immutable`、皆有 `const` 建構子與全欄位皆有預設值（nullable 欄位預設 `null`，`LibraryThemeDependencies.currentTheme`/`isEinkMode` 沿用原欄位現行預設值 `AppTheme.light`/`false`），讓 `LibraryScreen` 呼叫端在不需要對應功能時可以完全省略該 bundle 參數（比照現行「不傳等於該功能未啟用」的既有語意）。
- Commit message 慣例：`refactor(epic-26): Issue 7 Task N——<描述>`。
- 每個 Task 完成後專案須維持可編譯（`LibraryScreen` 建構子在 Task 2-6 之間會處於「部分欄位已收斂為 bundle、部分仍是獨立參數」的過渡狀態，這是預期、允許的中繼狀態，比照 Issue 6 Task 2 Step 7 的既有先例）。

---

### Task 1：建立 5 個 bundle 型別

**Files:**
- Create: `app/lib/screens/library_screen_dependencies.dart`
- Test: `app/test/screens/library_screen_dependencies_test.dart`

**Interfaces:**
- Produces：
  - `class LibraryReaderFeatureRepositories { final BookmarksRepository? bookmarksRepository; final HighlightsRepository? highlightsRepository; final NotesRepository? notesRepository; final CustomFontsRepository? customFontsRepository; final LayoutPresetRepository? layoutPresetRepository; final BookReaderPrefsRepository? bookReaderPrefsRepository; const LibraryReaderFeatureRepositories({this.bookmarksRepository, this.highlightsRepository, this.notesRepository, this.customFontsRepository, this.layoutPresetRepository, this.bookReaderPrefsRepository}); }`
  - `class LibrarySyncDependencies { final SyncAccountRepository? syncAccountRepository; final SyncClient? syncClient; final SyncCheckpointTrigger? syncCheckpointTrigger; const LibrarySyncDependencies({this.syncAccountRepository, this.syncClient, this.syncCheckpointTrigger}); }`
  - `class LibraryCloudAccountDependencies { final CloudAccountRepository? cloudAccountRepository; final GoogleDriveOAuthClient? googleDriveOAuthClient; final OneDriveOAuthClient? oneDriveOAuthClient; final CloudStorageClient? googleDriveStorageClient; final CloudStorageClient? oneDriveStorageClient; const LibraryCloudAccountDependencies({this.cloudAccountRepository, this.googleDriveOAuthClient, this.oneDriveOAuthClient, this.googleDriveStorageClient, this.oneDriveStorageClient}); }`
  - `class LibraryRemoteLibraryDependencies { final RemoteServerRepository? remoteServerRepository; final OpdsClient Function()? createOpdsClient; final RemoteThumbnailCache? thumbnailCache; const LibraryRemoteLibraryDependencies({this.remoteServerRepository, this.createOpdsClient, this.thumbnailCache}); }`
  - `class LibraryThemeDependencies { final AppTheme currentTheme; final bool isEinkMode; final ValueChanged<AppTheme>? onThemeChanged; final ValueChanged<bool>? onEinkModeChanged; const LibraryThemeDependencies({this.currentTheme = AppTheme.light, this.isEinkMode = false, this.onThemeChanged, this.onEinkModeChanged}); }`
  - Task 2-6 皆會 import 並使用對應的型別與其欄位存取器。

- [ ] **Step 1：寫失敗測試，驗證 5 個 bundle 皆正確持有各自的欄位、未提供時預設皆為 null（或現行預設值）**

```dart
// app/test/screens/library_screen_dependencies_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/theme/app_theme.dart';

import '../support/fake_bookmarks_repository.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';
import '../support/fake_custom_fonts_repository.dart';
import '../support/fake_book_reader_prefs_repository.dart';
import '../support/fake_cloud_account_repository.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_remote_server_repository.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_thumbnail_cache.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('LibraryReaderFeatureRepositories 原樣持有六個注入的依賴，未提供時預設皆為 null', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    final bookmarksRepository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    final customFontsRepository = FakeCustomFontsRepository();
    final layoutPresetRepository = LayoutPresetRepository(db);
    final bookReaderPrefsRepository = FakeBookReaderPrefsRepository();

    const empty = LibraryReaderFeatureRepositories();
    expect(empty.bookmarksRepository, isNull);
    expect(empty.highlightsRepository, isNull);
    expect(empty.notesRepository, isNull);
    expect(empty.customFontsRepository, isNull);
    expect(empty.layoutPresetRepository, isNull);
    expect(empty.bookReaderPrefsRepository, isNull);

    final dependencies = LibraryReaderFeatureRepositories(
      bookmarksRepository: bookmarksRepository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
      customFontsRepository: customFontsRepository,
      layoutPresetRepository: layoutPresetRepository,
      bookReaderPrefsRepository: bookReaderPrefsRepository,
    );
    expect(dependencies.bookmarksRepository, same(bookmarksRepository));
    expect(dependencies.highlightsRepository, same(highlightsRepository));
    expect(dependencies.notesRepository, same(notesRepository));
    expect(dependencies.customFontsRepository, same(customFontsRepository));
    expect(dependencies.layoutPresetRepository, same(layoutPresetRepository));
    expect(dependencies.bookReaderPrefsRepository, same(bookReaderPrefsRepository));
  });

  test('LibrarySyncDependencies 原樣持有三個注入的依賴，未提供時預設皆為 null', () {
    final syncAccountRepository = SyncAccountRepository();
    final syncClient = SyncClient(accountRepository: syncAccountRepository);
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => false,
      runCheckpoint: () async {},
    );

    const empty = LibrarySyncDependencies();
    expect(empty.syncAccountRepository, isNull);
    expect(empty.syncClient, isNull);
    expect(empty.syncCheckpointTrigger, isNull);

    final dependencies = LibrarySyncDependencies(
      syncAccountRepository: syncAccountRepository,
      syncClient: syncClient,
      syncCheckpointTrigger: syncCheckpointTrigger,
    );
    expect(dependencies.syncAccountRepository, same(syncAccountRepository));
    expect(dependencies.syncClient, same(syncClient));
    expect(dependencies.syncCheckpointTrigger, same(syncCheckpointTrigger));
  });

  test('LibraryCloudAccountDependencies 原樣持有五個注入的依賴，未提供時預設皆為 null', () {
    final cloudAccountRepository = FakeCloudAccountRepository();
    final googleDriveOAuthClient =
        GoogleDriveOAuthClient(accountRepository: cloudAccountRepository);
    final oneDriveOAuthClient =
        OneDriveOAuthClient(accountRepository: cloudAccountRepository);
    final googleDriveStorageClient = FakeCloudStorageClient();
    final oneDriveStorageClient = FakeCloudStorageClient();

    const empty = LibraryCloudAccountDependencies();
    expect(empty.cloudAccountRepository, isNull);
    expect(empty.googleDriveOAuthClient, isNull);
    expect(empty.oneDriveOAuthClient, isNull);
    expect(empty.googleDriveStorageClient, isNull);
    expect(empty.oneDriveStorageClient, isNull);

    final dependencies = LibraryCloudAccountDependencies(
      cloudAccountRepository: cloudAccountRepository,
      googleDriveOAuthClient: googleDriveOAuthClient,
      oneDriveOAuthClient: oneDriveOAuthClient,
      googleDriveStorageClient: googleDriveStorageClient,
      oneDriveStorageClient: oneDriveStorageClient,
    );
    expect(dependencies.cloudAccountRepository, same(cloudAccountRepository));
    expect(dependencies.googleDriveOAuthClient, same(googleDriveOAuthClient));
    expect(dependencies.oneDriveOAuthClient, same(oneDriveOAuthClient));
    expect(dependencies.googleDriveStorageClient, same(googleDriveStorageClient));
    expect(dependencies.oneDriveStorageClient, same(oneDriveStorageClient));
  });

  test('LibraryRemoteLibraryDependencies 原樣持有三個注入的依賴，未提供時預設皆為 null', () {
    final remoteServerRepository = FakeRemoteServerRepository();
    OpdsClient createClient() => FakeOpdsClient();
    final thumbnailCache = FakeRemoteThumbnailCache();

    const empty = LibraryRemoteLibraryDependencies();
    expect(empty.remoteServerRepository, isNull);
    expect(empty.createOpdsClient, isNull);
    expect(empty.thumbnailCache, isNull);

    final dependencies = LibraryRemoteLibraryDependencies(
      remoteServerRepository: remoteServerRepository,
      createOpdsClient: createClient,
      thumbnailCache: thumbnailCache,
    );
    expect(dependencies.remoteServerRepository, same(remoteServerRepository));
    expect(dependencies.createOpdsClient, same(createClient));
    expect(dependencies.thumbnailCache, same(thumbnailCache));
  });

  test('LibraryThemeDependencies 原樣持有四個注入的值，未提供時 currentTheme/isEinkMode 沿用現行預設值、callback 預設為 null', () {
    const empty = LibraryThemeDependencies();
    expect(empty.currentTheme, AppTheme.light);
    expect(empty.isEinkMode, isFalse);
    expect(empty.onThemeChanged, isNull);
    expect(empty.onEinkModeChanged, isNull);

    void onThemeChanged(AppTheme theme) {}
    void onEinkModeChanged(bool enabled) {}
    final dependencies = LibraryThemeDependencies(
      currentTheme: AppTheme.dark,
      isEinkMode: true,
      onThemeChanged: onThemeChanged,
      onEinkModeChanged: onEinkModeChanged,
    );
    expect(dependencies.currentTheme, AppTheme.dark);
    expect(dependencies.isEinkMode, isTrue);
    expect(dependencies.onThemeChanged, same(onThemeChanged));
    expect(dependencies.onEinkModeChanged, same(onEinkModeChanged));
  });
}
```

- [ ] **Step 2：執行測試確認失敗（型別尚未存在）**

執行：`cd app && flutter test test/screens/library_screen_dependencies_test.dart`
預期：`FAIL`，錯誤訊息為找不到 `package:elinkbook/screens/library_screen_dependencies.dart`（或找不到對應型別）。

- [ ] **Step 3：實作 5 個 bundle 型別**

```dart
// app/lib/screens/library_screen_dependencies.dart
import 'package:flutter/foundation.dart';

import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/cloud_storage_client.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/bookmarks_repository.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/highlights_repository.dart';
import '../reader/layout_preset_repository.dart';
import '../reader/notes_repository.dart';
import '../remote/opds_client.dart';
import '../remote/remote_server_repository.dart';
import '../remote/remote_thumbnail_cache.dart';
import '../sync/sync_account_repository.dart';
import '../sync/sync_checkpoint_trigger.dart';
import '../sync/sync_client.dart';
import '../theme/app_theme.dart';

/// 收斂 `LibraryScreen` 建構子中「轉送給 `ReaderScreen` 的個人化閱讀功能」
/// 相關欄位（epic-26-architecture-hardening Issue 7），取代原本 6 個獨立
/// 具名參數各自宣告/轉送的做法。皆為 nullable——維持 `LibraryScreen` 現行
/// 「功能未啟用時為 null」的既有語意，純粹收斂宣告/轉送方式，非改變可用性
/// 判斷邏輯。**範圍刻意不含 `syncAccountRepository`**——後者從未轉送給
/// `ReaderScreen`，與本 bundle 其餘欄位足跡不同（詳見
/// `plans/plan-issue-7.md`「規劃階段查證」），改併入 [LibrarySyncDependencies]。
@immutable
class LibraryReaderFeatureRepositories {
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final CustomFontsRepository? customFontsRepository;
  final LayoutPresetRepository? layoutPresetRepository;
  final BookReaderPrefsRepository? bookReaderPrefsRepository;

  const LibraryReaderFeatureRepositories({
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.customFontsRepository,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
  });
}

/// 收斂帳號同步相關欄位（epic-26-architecture-hardening Issue 7）。
@immutable
class LibrarySyncDependencies {
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final SyncCheckpointTrigger? syncCheckpointTrigger;

  const LibrarySyncDependencies({
    this.syncAccountRepository,
    this.syncClient,
    this.syncCheckpointTrigger,
  });
}

/// 收斂 Google Drive／OneDrive 雲端帳號與匯入相關欄位
/// （epic-26-architecture-hardening Issue 7）。**刻意不含
/// `remoteServerRepository`**——OPDS/Calibre 遠端書庫是獨立網域，且
/// `_openGroupFilteredView()` 自我遞迴目前整組轉送本 bundle 五個欄位、卻
/// 完全不轉送 `remoteServerRepository`，併入會造成欄位洩漏風險（詳見
/// `plans/plan-issue-7.md`「規劃階段查證」），改併入
/// [LibraryRemoteLibraryDependencies]。
@immutable
class LibraryCloudAccountDependencies {
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final CloudStorageClient? googleDriveStorageClient;
  final CloudStorageClient? oneDriveStorageClient;

  const LibraryCloudAccountDependencies({
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.googleDriveStorageClient,
    this.oneDriveStorageClient,
  });
}

/// 收斂 OPDS/Calibre 遠端書庫相關欄位（epic-26-architecture-hardening
/// Issue 7）。**刻意不含 `computeFingerprint`**——`computeFingerprint`
/// 同時被 Google Drive／OneDrive 雲端匯入重複偵測共用，且
/// `_openGroupFilteredView()` 自我遞迴目前轉送 `computeFingerprint` 卻不
/// 轉送本 bundle 任何欄位，兩者足跡不同（詳見 `plans/plan-issue-7.md`
/// 「規劃階段查證」），`computeFingerprint` 維持 `LibraryScreen` 獨立參數。
@immutable
class LibraryRemoteLibraryDependencies {
  final RemoteServerRepository? remoteServerRepository;
  final OpdsClient Function()? createOpdsClient;
  final RemoteThumbnailCache? thumbnailCache;

  const LibraryRemoteLibraryDependencies({
    this.remoteServerRepository,
    this.createOpdsClient,
    this.thumbnailCache,
  });
}

/// 收斂主題／顯示控制相關欄位（epic-26-architecture-hardening Issue 7）。
/// `currentTheme`/`isEinkMode` 沿用 `LibraryScreen` 原欄位現行預設值
/// （`AppTheme.light`/`false`），維持不傳入時的既有行為。
@immutable
class LibraryThemeDependencies {
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final ValueChanged<bool>? onEinkModeChanged;

  const LibraryThemeDependencies({
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
  });
}
```

- [ ] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/screens/library_screen_dependencies_test.dart`
預期：`PASS`

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/library_screen_dependencies.dart app/test/screens/library_screen_dependencies_test.dart
git commit -m "refactor(epic-26): Issue 7 Task 1——新增 LibraryScreen 5 個 dependencies bundle 型別"
```

---

### Task 2：`LibraryScreen` 改用 `readerFeatureRepositories`（`bookmarksRepository`／`highlightsRepository`／`notesRepository`／`customFontsRepository`／`layoutPresetRepository`／`bookReaderPrefsRepository`）

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `LibraryReaderFeatureRepositories`。
- Produces：`LibraryScreen` 建構子新增 `LibraryReaderFeatureRepositories readerFeatureRepositories`（可選，預設 `const LibraryReaderFeatureRepositories()`），取代原本 6 個獨立具名參數。

- [ ] **Step 1：修改 `LibraryScreen` 欄位宣告與建構子**

修改 `app/lib/screens/library_screen.dart:49-107`，欄位宣告原本（節錄相關 6 行）：

```dart
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final CustomFontsRepository? customFontsRepository;
  final LayoutPresetRepository? layoutPresetRepository;
  final BookReaderPrefsRepository? bookReaderPrefsRepository;
```

改為：

```dart
  /// 收斂原本 `bookmarksRepository`／`highlightsRepository`／
  /// `notesRepository`／`customFontsRepository`／`layoutPresetRepository`／
  /// `bookReaderPrefsRepository` 六個獨立參數（epic-26-architecture-hardening
  /// Issue 7）。
  final LibraryReaderFeatureRepositories readerFeatureRepositories;
```

建構子參數列原本（節錄相關 6 行）：

```dart
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.customFontsRepository,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
```

改為：

```dart
    this.readerFeatureRepositories = const LibraryReaderFeatureRepositories(),
```

並在檔案頂端 import 區塊新增（比照既有 import 排序，置於 `import '../library/library_repository.dart';` 之後、`import 'cloud_browser_screen.dart';` 之前的合理位置）：

```dart
import 'library_screen_dependencies.dart';
```

- [ ] **Step 2：修改 `_openBook()` 建構 `ReaderScreen`**

修改 `app/lib/screens/library_screen.dart:573-589`，原本：

```dart
            builder: (_) => ReaderScreen(
              filePath: book.filePath,
              bookId: book.id,
              prefsManager: widget.prefsManager,
              bookmarksRepository: widget.bookmarksRepository,
              highlightsRepository: widget.highlightsRepository,
              notesRepository: widget.notesRepository,
              bookTitle: book.title,
              bookAuthor: book.author,
              bookProgress: book.progress,
              isFixedLayout: book.isFixedLayout,
              libraryRepository: widget.repository,
              customFontsRepository: widget.customFontsRepository,
              layoutPresetRepository: widget.layoutPresetRepository,
              bookReaderPrefsRepository: widget.bookReaderPrefsRepository,
              syncCheckpointTrigger: widget.syncCheckpointTrigger,
            ),
```

改為（僅本 bundle 涵蓋的 5 個欄位改走 `widget.readerFeatureRepositories.xxx`；`syncCheckpointTrigger` 屬 Task 3 範圍，本步驟維持原樣不動）：

```dart
            builder: (_) => ReaderScreen(
              filePath: book.filePath,
              bookId: book.id,
              prefsManager: widget.prefsManager,
              bookmarksRepository: widget.readerFeatureRepositories.bookmarksRepository,
              highlightsRepository: widget.readerFeatureRepositories.highlightsRepository,
              notesRepository: widget.readerFeatureRepositories.notesRepository,
              bookTitle: book.title,
              bookAuthor: book.author,
              bookProgress: book.progress,
              isFixedLayout: book.isFixedLayout,
              libraryRepository: widget.repository,
              customFontsRepository: widget.readerFeatureRepositories.customFontsRepository,
              layoutPresetRepository: widget.readerFeatureRepositories.layoutPresetRepository,
              bookReaderPrefsRepository: widget.readerFeatureRepositories.bookReaderPrefsRepository,
              syncCheckpointTrigger: widget.syncCheckpointTrigger,
            ),
```

- [ ] **Step 3：修改 `_openGroupFilteredView()` 自我遞迴，只轉送 `bookmarksRepository`／`highlightsRepository`／`notesRepository`／`customFontsRepository`（比照現行行為，不轉送 `layoutPresetRepository`／`bookReaderPrefsRepository`）**

修改 `app/lib/screens/library_screen.dart:736-739`，原本：

```dart
              bookmarksRepository: widget.bookmarksRepository,
              highlightsRepository: widget.highlightsRepository,
              notesRepository: widget.notesRepository,
              customFontsRepository: widget.customFontsRepository,
```

改為（維持現行「不轉送 `layoutPresetRepository`／`bookReaderPrefsRepository`」的既有行為——這兩個欄位在新 bundle 建構時省略、沿用 `const` 預設值 `null`，等同現行效果）：

```dart
              readerFeatureRepositories: LibraryReaderFeatureRepositories(
                bookmarksRepository: widget.readerFeatureRepositories.bookmarksRepository,
                highlightsRepository: widget.readerFeatureRepositories.highlightsRepository,
                notesRepository: widget.readerFeatureRepositories.notesRepository,
                customFontsRepository: widget.readerFeatureRepositories.customFontsRepository,
              ),
```

- [ ] **Step 4：修改 `_buildAppBarActions()` 建構 `SettingsScreen`（只用 `customFontsRepository`）**

修改 `app/lib/screens/library_screen.dart:984`，原本：

```dart
                  customFontsRepository: widget.customFontsRepository,
```

改為：

```dart
                  customFontsRepository: widget.readerFeatureRepositories.customFontsRepository,
```

- [ ] **Step 5：確認 6 個型別的 import 是否仍需要**

`app/lib/screens/library_screen.dart` 頂端原有 `BookmarksRepository`／`HighlightsRepository`／`NotesRepository`／`CustomFontsRepository`／`LayoutPresetRepository`／`BookReaderPrefsRepository` 對應 import：本檔案內若這 6 個型別名稱不再以獨立宣告形式出現（只透過 `widget.readerFeatureRepositories.xxx` 存取值），可能變成未使用 import——待 Step 1-4 完成後跑 `flutter analyze app/lib/screens/library_screen.dart` 確認，依實際結果決定是否移除（不要憑空猜測，以 analyze 實際結果為準；由於 Task 3-6 仍會陸續移除其餘型別的獨立宣告，若本步驟 analyze 尚未報告某個 import 未使用，留待該型別對應的 Task 處理，不要提前猜測移除）。

- [ ] **Step 6：更新 `main.dart` 呼叫端**

修改 `app/lib/main.dart:287-314`，原本（節錄相關 6 行）：

```dart
        bookmarksRepository: widget.bookmarksRepository,
        highlightsRepository: widget.highlightsRepository,
        notesRepository: widget.notesRepository,
        customFontsRepository: widget.customFontsRepository,
        layoutPresetRepository: widget.layoutPresetRepository,
        bookReaderPrefsRepository: widget.bookReaderPrefsRepository,
```

改為：

```dart
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          bookmarksRepository: widget.bookmarksRepository,
          highlightsRepository: widget.highlightsRepository,
          notesRepository: widget.notesRepository,
          customFontsRepository: widget.customFontsRepository,
          layoutPresetRepository: widget.layoutPresetRepository,
          bookReaderPrefsRepository: widget.bookReaderPrefsRepository,
        ),
```

（`main.dart` 自身 State 類別的 `widget.bookmarksRepository` 等欄位維持不變——這些是組裝根本身的既有欄位，本步驟只改變傳給 `LibraryScreen` 時的包裝方式。）

並在 `app/lib/main.dart` 頂端 import 區塊新增（置於 `import 'screens/library_screen.dart';` 之後）：

```dart
import 'screens/library_screen_dependencies.dart';
```

- [ ] **Step 7：更新 `library_screen_test.dart` 的 6 處測試建構**

在 `app/test/screens/library_screen_test.dart` 頂端新增 import（置於 `import 'package:elinkbook/screens/library_screen.dart';` 之後）：

```dart
import 'package:elinkbook/screens/library_screen_dependencies.dart';
```

修改以下 6 處（皆為 `LibraryScreen(` 建構參數列，依檔案內原始出現順序）：

**(a) 約 2166-2172 行**（`highlightsRepository`／`notesRepository`），原本：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            highlightsRepository: highlightsRepository,
            notesRepository: notesRepository,
          ),
        ),
```

**(b) 約 2249-2256 行**（`bookmarksRepository`／`highlightsRepository`／`notesRepository`），原本：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            bookmarksRepository: bookmarksRepository,
            highlightsRepository: highlightsRepository,
            notesRepository: notesRepository,
          ),
        ),
```

**(c) 約 2370-2377 行**（另一個獨立 `testWidgets`，與 (b) 完全相同的欄位組合與縮排），原本：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            bookmarksRepository: bookmarksRepository,
            highlightsRepository: highlightsRepository,
            notesRepository: notesRepository,
          ),
        ),
```

**(d) 約 2811-2816 行**（`customFontsRepository` 單獨出現，於「貫穿至 `SettingsScreen`」測試），原本：

```dart
      home: LibraryScreen(
        repository: FakeLibraryRepository(initialBooks: const []),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        customFontsRepository: customFontsRepository,
      ),
```

改為：

```dart
      home: LibraryScreen(
        repository: FakeLibraryRepository(initialBooks: const []),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          customFontsRepository: customFontsRepository,
        ),
      ),
```

**(e) 約 2844-2849 行**（`customFontsRepository` 單獨出現，於「貫穿至 `ReaderScreen`」測試），原本：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          customFontsRepository: customFontsRepository,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            customFontsRepository: customFontsRepository,
          ),
        ),
```

**(f) 約 2882-2889 行**（`layoutPresetRepository`／`bookReaderPrefsRepository`），原本：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          layoutPresetRepository: layoutPresetRepository,
          bookReaderPrefsRepository: bookReaderPrefsRepository,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            layoutPresetRepository: layoutPresetRepository,
            bookReaderPrefsRepository: bookReaderPrefsRepository,
          ),
        ),
```

**(g) 約 3439-3446 行**（`bookmarksRepository` 單獨出現，於「移除本機快取」測試），原本：

```dart
      home: LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(
          globalPrefs: const GlobalReaderPrefs.initial()
              .copyWith(openLastBookOnLaunch: false),
        ),
        bookmarksRepository: bookmarksRepository,
      ),
```

改為：

```dart
      home: LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(
          globalPrefs: const GlobalReaderPrefs.initial()
              .copyWith(openLastBookOnLaunch: false),
        ),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          bookmarksRepository: bookmarksRepository,
        ),
      ),
```

（共 7 處，其餘未提及本 bundle 任何欄位的 `LibraryScreen(` 建構——約 80 餘處——不需修改，`readerFeatureRepositories` 省略時自動採用 `const LibraryReaderFeatureRepositories()` 空預設值，等同現行未提供這些參數時的行為。）

- [ ] **Step 8：執行測試確認通過**

執行：`cd app && flutter test test/screens/library_screen_test.dart`
預期：`PASS`（全部既有案例）。

- [ ] **Step 9：Commit**

```bash
git add app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/library_screen_test.dart
git commit -m "refactor(epic-26): Issue 7 Task 2——LibraryScreen 改用 readerFeatureRepositories bundle"
```

---

### Task 3：`LibraryScreen` 改用 `syncDependencies`（`syncAccountRepository`／`syncClient`／`syncCheckpointTrigger`）

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `LibrarySyncDependencies`。
- Produces：`LibraryScreen` 建構子新增 `LibrarySyncDependencies syncDependencies`（可選，預設 `const LibrarySyncDependencies()`），取代原本 3 個獨立具名參數。

- [ ] **Step 1：修改 `LibraryScreen` 欄位宣告與建構子**

修改 `app/lib/screens/library_screen.dart`，欄位宣告原本：

```dart
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final SyncCheckpointTrigger? syncCheckpointTrigger;
```

改為：

```dart
  /// 收斂原本 `syncAccountRepository`／`syncClient`／`syncCheckpointTrigger`
  /// 三個獨立參數（epic-26-architecture-hardening Issue 7）。
  final LibrarySyncDependencies syncDependencies;
```

建構子參數列原本：

```dart
    this.syncAccountRepository,
    this.syncClient,
    this.syncCheckpointTrigger,
```

改為：

```dart
    this.syncDependencies = const LibrarySyncDependencies(),
```

- [ ] **Step 2：修改 `_openBook()` 建構 `ReaderScreen`（只用 `syncCheckpointTrigger`）**

修改 `app/lib/screens/library_screen.dart`（`_openBook()` 內，Task 2 Step 2 已改過的區塊）最後一行，原本：

```dart
              syncCheckpointTrigger: widget.syncCheckpointTrigger,
```

改為：

```dart
              syncCheckpointTrigger: widget.syncDependencies.syncCheckpointTrigger,
```

- [ ] **Step 3：修改 `_openGroupFilteredView()` 自我遞迴，整包轉送（現行三者皆整組轉送，可安全整包轉送同一個 bundle 實例）**

修改 `app/lib/screens/library_screen.dart:744-746`，原本：

```dart
              syncAccountRepository: widget.syncAccountRepository,
              syncClient: widget.syncClient,
              syncCheckpointTrigger: widget.syncCheckpointTrigger,
```

改為：

```dart
              syncDependencies: widget.syncDependencies,
```

- [ ] **Step 4：修改 `_buildAppBarActions()` 建構 `SettingsScreen`（只用 `syncAccountRepository`／`syncClient`，不用 `syncCheckpointTrigger`——比照現行行為）**

修改 `app/lib/screens/library_screen.dart:985-986`，原本：

```dart
                  syncAccountRepository: widget.syncAccountRepository,
                  syncClient: widget.syncClient,
```

改為：

```dart
                  syncAccountRepository: widget.syncDependencies.syncAccountRepository,
                  syncClient: widget.syncDependencies.syncClient,
```

- [ ] **Step 5：確認 `SyncAccountRepository`／`SyncClient`／`SyncCheckpointTrigger` 三個型別的 import 是否仍需要**

跑 `flutter analyze app/lib/screens/library_screen.dart` 確認，依實際結果決定是否移除對應 import（原則同 Task 2 Step 5）。

- [ ] **Step 6：更新 `main.dart` 呼叫端**

修改 `app/lib/main.dart`，原本（節錄相關 3 行）：

```dart
        syncAccountRepository: widget.syncAccountRepository,
        syncClient: widget.syncClient,
        syncCheckpointTrigger: widget.syncCheckpointTrigger,
```

改為：

```dart
        syncDependencies: LibrarySyncDependencies(
          syncAccountRepository: widget.syncAccountRepository,
          syncClient: widget.syncClient,
          syncCheckpointTrigger: widget.syncCheckpointTrigger,
        ),
```

- [ ] **Step 7：更新 `library_screen_test.dart` 的 2 處測試建構與 3 處直接欄位斷言**

**(a) 約 2919-2926 行**（`syncCheckpointTrigger` 單獨出現），原本：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          syncCheckpointTrigger: syncCheckpointTrigger,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          syncDependencies: LibrarySyncDependencies(
            syncCheckpointTrigger: syncCheckpointTrigger,
          ),
        ),
```

**(b) 約 2958-2967 行**（三者皆出現，於「自我遞迴 syncAccountRepository/syncClient/syncCheckpointTrigger 貫穿」測試），原本：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          syncAccountRepository: syncAccountRepository,
          syncClient: syncClient,
          syncCheckpointTrigger: syncCheckpointTrigger,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          syncDependencies: LibrarySyncDependencies(
            syncAccountRepository: syncAccountRepository,
            syncClient: syncClient,
            syncCheckpointTrigger: syncCheckpointTrigger,
          ),
        ),
```

**(c) 約 2977-2984 行**（同一測試內，斷言 `_openGroupFilteredView()` 轉送給子畫面的欄位），原本：

```dart
    expect(filteredScreen.syncAccountRepository, same(syncAccountRepository),
        reason: '_openGroupFilteredView() 未把 syncAccountRepository 貫穿給下一層 '
            'LibraryScreen');
    expect(filteredScreen.syncClient, same(syncClient),
        reason: '_openGroupFilteredView() 未把 syncClient 貫穿給下一層 LibraryScreen');
    expect(filteredScreen.syncCheckpointTrigger, same(syncCheckpointTrigger),
        reason: '_openGroupFilteredView() 未把 syncCheckpointTrigger 貫穿給下一層 '
            'LibraryScreen');
```

改為：

```dart
    expect(filteredScreen.syncDependencies.syncAccountRepository, same(syncAccountRepository),
        reason: '_openGroupFilteredView() 未把 syncDependencies 貫穿給下一層 '
            'LibraryScreen');
    expect(filteredScreen.syncDependencies.syncClient, same(syncClient),
        reason: '_openGroupFilteredView() 未把 syncDependencies 貫穿給下一層 LibraryScreen');
    expect(filteredScreen.syncDependencies.syncCheckpointTrigger, same(syncCheckpointTrigger),
        reason: '_openGroupFilteredView() 未把 syncDependencies 貫穿給下一層 '
            'LibraryScreen');
```

（同一測試稍後的 `readerScreen.syncCheckpointTrigger`——約 2993 行——是斷言 `ReaderScreen` 自身欄位，不受本次影響，維持不變。）

- [ ] **Step 8：執行測試確認通過**

執行：`cd app && flutter test test/screens/library_screen_test.dart`
預期：`PASS`。

- [ ] **Step 9：Commit**

```bash
git add app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/library_screen_test.dart
git commit -m "refactor(epic-26): Issue 7 Task 3——LibraryScreen 改用 syncDependencies bundle"
```

---

### Task 4：`LibraryScreen` 改用 `cloudAccountDependencies`（`cloudAccountRepository`／`googleDriveOAuthClient`／`oneDriveOAuthClient`／`googleDriveStorageClient`／`oneDriveStorageClient`）

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `LibraryCloudAccountDependencies`。
- Produces：`LibraryScreen` 建構子新增 `LibraryCloudAccountDependencies cloudAccountDependencies`（可選，預設 `const LibraryCloudAccountDependencies()`），取代原本 5 個獨立具名參數。

- [ ] **Step 1：修改 `LibraryScreen` 欄位宣告與建構子**

欄位宣告原本：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final CloudStorageClient? googleDriveStorageClient;
  final CloudStorageClient? oneDriveStorageClient;
```

改為：

```dart
  /// 收斂原本 `cloudAccountRepository`／`googleDriveOAuthClient`／
  /// `oneDriveOAuthClient`／`googleDriveStorageClient`／
  /// `oneDriveStorageClient` 五個獨立參數（epic-26-architecture-hardening
  /// Issue 7）。
  final LibraryCloudAccountDependencies cloudAccountDependencies;
```

建構子參數列原本：

```dart
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.googleDriveStorageClient,
    this.oneDriveStorageClient,
```

改為：

```dart
    this.cloudAccountDependencies = const LibraryCloudAccountDependencies(),
```

- [ ] **Step 2：修改 `_openGoogleDriveBrowser()`/`_openOneDriveBrowser()` 呼叫端與 popup menu 門檻判斷**

修改 `app/lib/screens/library_screen.dart:912-931`，原本：

```dart
            PopupMenuItem<void>(
              key: const Key('library_import_google_drive_option'),
              enabled: widget.googleDriveStorageClient != null &&
                  widget.computeFingerprint != null,
              onTap: (widget.googleDriveStorageClient == null ||
                      widget.computeFingerprint == null)
                  ? null
                  : () => _openGoogleDriveBrowser(widget.googleDriveStorageClient!),
              child: const Text('從 Google Drive 匯入'),
            ),
            PopupMenuItem<void>(
              key: const Key('library_import_onedrive_option'),
              enabled: widget.oneDriveStorageClient != null &&
                  widget.computeFingerprint != null,
              onTap: (widget.oneDriveStorageClient == null ||
                      widget.computeFingerprint == null)
                  ? null
                  : () => _openOneDriveBrowser(widget.oneDriveStorageClient!),
              child: const Text('從 OneDrive 匯入'),
            ),
```

改為：

```dart
            PopupMenuItem<void>(
              key: const Key('library_import_google_drive_option'),
              enabled: widget.cloudAccountDependencies.googleDriveStorageClient != null &&
                  widget.computeFingerprint != null,
              onTap: (widget.cloudAccountDependencies.googleDriveStorageClient == null ||
                      widget.computeFingerprint == null)
                  ? null
                  : () => _openGoogleDriveBrowser(
                      widget.cloudAccountDependencies.googleDriveStorageClient!),
              child: const Text('從 Google Drive 匯入'),
            ),
            PopupMenuItem<void>(
              key: const Key('library_import_onedrive_option'),
              enabled: widget.cloudAccountDependencies.oneDriveStorageClient != null &&
                  widget.computeFingerprint != null,
              onTap: (widget.cloudAccountDependencies.oneDriveStorageClient == null ||
                      widget.computeFingerprint == null)
                  ? null
                  : () => _openOneDriveBrowser(
                      widget.cloudAccountDependencies.oneDriveStorageClient!),
              child: const Text('從 OneDrive 匯入'),
            ),
```

（`_openGoogleDriveBrowser(CloudStorageClient client)`/`_openOneDriveBrowser(CloudStorageClient client)` 兩個方法本身簽章與內部實作不變，只有呼叫端傳入值的來源改變。）

- [ ] **Step 3：修改 `_openGroupFilteredView()` 自我遞迴，整包轉送**

修改 `app/lib/screens/library_screen.dart:747-749,754-755`，原本（注意這 5 行在自我遞迴建構子參數列中並非相鄰——`googleDriveStorageClient`／`oneDriveStorageClient` 中間夾著 Task 2 已處理過的 `computeFingerprint` 相關註解與欄位，這裡只處理本 bundle 的 5 個欄位本身，其餘欄位維持原位置不動）：

```dart
              cloudAccountRepository: widget.cloudAccountRepository,
              googleDriveOAuthClient: widget.googleDriveOAuthClient,
              oneDriveOAuthClient: widget.oneDriveOAuthClient,
```

以及稍後（原欄位順序中間夾了 `googleDriveStorageClient`/`oneDriveStorageClient` 的既有審查修正註解，一併保留）：

```dart
              googleDriveStorageClient: widget.googleDriveStorageClient,
              oneDriveStorageClient: widget.oneDriveStorageClient,
```

改為（5 個欄位合併為一行整包轉送，原位置擇一即可，另一處對應原始碼行整段移除）：

```dart
              cloudAccountDependencies: widget.cloudAccountDependencies,
```

（原本兩段之間夾著的 `computeFingerprint`／`isMobileDataConnection`／`currentTheme` 等其他欄位維持原樣不動，只移除這 5 行、在其中一處位置插入上面這一行取代。）

- [ ] **Step 4：修改 `_buildAppBarActions()` 建構 `SettingsScreen`（只用 3 個帳號欄位，不用 2 個 storage client）**

修改 `app/lib/screens/library_screen.dart:987-989`，原本：

```dart
                  cloudAccountRepository: widget.cloudAccountRepository,
                  googleDriveOAuthClient: widget.googleDriveOAuthClient,
                  oneDriveOAuthClient: widget.oneDriveOAuthClient,
```

改為：

```dart
                  cloudAccountRepository: widget.cloudAccountDependencies.cloudAccountRepository,
                  googleDriveOAuthClient: widget.cloudAccountDependencies.googleDriveOAuthClient,
                  oneDriveOAuthClient: widget.cloudAccountDependencies.oneDriveOAuthClient,
```

- [ ] **Step 5：確認 5 個型別的 import 是否仍需要**

跑 `flutter analyze app/lib/screens/library_screen.dart` 確認，依實際結果決定是否移除對應 import。

- [ ] **Step 6：更新 `main.dart` 呼叫端**

原本（節錄相關 5 行）：

```dart
        cloudAccountRepository: widget.cloudAccountRepository,
        googleDriveOAuthClient: widget.googleDriveOAuthClient,
        oneDriveOAuthClient: widget.oneDriveOAuthClient,
        googleDriveStorageClient: widget.googleDriveStorageClient,
        oneDriveStorageClient: widget.oneDriveStorageClient,
```

改為：

```dart
        cloudAccountDependencies: LibraryCloudAccountDependencies(
          cloudAccountRepository: widget.cloudAccountRepository,
          googleDriveOAuthClient: widget.googleDriveOAuthClient,
          oneDriveOAuthClient: widget.oneDriveOAuthClient,
          googleDriveStorageClient: widget.googleDriveStorageClient,
          oneDriveStorageClient: widget.oneDriveStorageClient,
        ),
```

- [ ] **Step 7：更新 `library_screen_test.dart` 的 4 處測試建構與 1 處直接欄位斷言**

**(a) 約 2053-2062 行**，原本：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          googleDriveStorageClient: client,
          computeFingerprint: FakeFingerprintComputer().call,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          cloudAccountDependencies: LibraryCloudAccountDependencies(
            googleDriveStorageClient: client,
          ),
          computeFingerprint: FakeFingerprintComputer().call,
        ),
```

**(b) 約 2081-2091 行**，原本：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          googleDriveStorageClient: googleDriveStorageClient,
          computeFingerprint: computeFingerprint,
          isMobileDataConnection: isMobileDataConnection,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          cloudAccountDependencies: LibraryCloudAccountDependencies(
            googleDriveStorageClient: googleDriveStorageClient,
          ),
          computeFingerprint: computeFingerprint,
          isMobileDataConnection: isMobileDataConnection,
        ),
```

**(c) 約 2129-2138 行**，原本：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          oneDriveStorageClient: client,
          computeFingerprint: FakeFingerprintComputer().call,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          cloudAccountDependencies: LibraryCloudAccountDependencies(
            oneDriveStorageClient: client,
          ),
          computeFingerprint: FakeFingerprintComputer().call,
        ),
```

**(d) 約 3016-3027 行**（於「自我遞迴 googleDriveStorageClient／computeFingerprint／isMobileDataConnection 貫穿」測試），原本：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          googleDriveStorageClient: googleDriveStorageClient,
          computeFingerprint: computeFingerprint,
          isMobileDataConnection: isMobileDataConnection,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          cloudAccountDependencies: LibraryCloudAccountDependencies(
            googleDriveStorageClient: googleDriveStorageClient,
          ),
          computeFingerprint: computeFingerprint,
          isMobileDataConnection: isMobileDataConnection,
        ),
```

**(e) 約 3035-3038 行**（同一測試內，斷言自我遞迴子畫面的欄位），原本：

```dart
    expect(filteredScreen.googleDriveStorageClient, same(googleDriveStorageClient),
        reason: '_openGroupFilteredView() 未把 googleDriveStorageClient 貫穿給下一層 '
            'LibraryScreen，會導致分類篩選畫面內「從 Google Drive 匯入」選單項目 '
            '永遠停用');
```

改為：

```dart
    expect(filteredScreen.cloudAccountDependencies.googleDriveStorageClient,
        same(googleDriveStorageClient),
        reason: '_openGroupFilteredView() 未把 cloudAccountDependencies 貫穿給下一層 '
            'LibraryScreen，會導致分類篩選畫面內「從 Google Drive 匯入」選單項目 '
            '永遠停用');
```

（同一測試稍後的 `filteredScreen.computeFingerprint`／`filteredScreen.isMobileDataConnection` 斷言——約 3039、3044 行——不受本次影響，維持不變。）

- [ ] **Step 8：執行測試確認通過**

執行：`cd app && flutter test test/screens/library_screen_test.dart`
預期：`PASS`。

- [ ] **Step 9：Commit**

```bash
git add app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/library_screen_test.dart
git commit -m "refactor(epic-26): Issue 7 Task 4——LibraryScreen 改用 cloudAccountDependencies bundle"
```

---

### Task 5：`LibraryScreen` 改用 `remoteLibraryDependencies`（`remoteServerRepository`／`createOpdsClient`／`thumbnailCache`）

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `LibraryRemoteLibraryDependencies`；Issue 6 的 `RemoteCatalogDependencies`（`app/lib/remote/remote_catalog_dependencies.dart`，本 Task 只改變其欄位值的來源，不改變 `RemoteCatalogDependencies` 本身）。
- Produces：`LibraryScreen` 建構子新增 `LibraryRemoteLibraryDependencies remoteLibraryDependencies`（可選，預設 `const LibraryRemoteLibraryDependencies()`），取代原本 3 個獨立具名參數。

- [ ] **Step 1：修改 `LibraryScreen` 欄位宣告與建構子**

欄位宣告原本：

```dart
  final RemoteServerRepository? remoteServerRepository;
  final OpdsClient Function()? createOpdsClient;
  final RemoteThumbnailCache? thumbnailCache;
```

改為：

```dart
  /// 收斂原本 `remoteServerRepository`／`createOpdsClient`／`thumbnailCache`
  /// 三個獨立參數（epic-26-architecture-hardening Issue 7）。**刻意不含
  /// `computeFingerprint`——`_openGroupFilteredView()` 自我遞迴目前轉送
  /// `computeFingerprint` 卻不轉送這三者，見 `plans/plan-issue-7.md`
  /// 「規劃階段查證」。
  final LibraryRemoteLibraryDependencies remoteLibraryDependencies;
```

建構子參數列原本：

```dart
    this.remoteServerRepository,
    this.createOpdsClient,
    this.thumbnailCache,
```

改為：

```dart
    this.remoteLibraryDependencies = const LibraryRemoteLibraryDependencies(),
```

（`_openGroupFilteredView()` 自我遞迴目前完全不轉送這 3 個欄位——本 Task 不需修改該方法：省略 `remoteLibraryDependencies` 參數即自動採用 `const LibraryRemoteLibraryDependencies()` 空預設值，等同現行「不轉送」的既有行為，零程式碼異動即可維持零行為改變。）

- [ ] **Step 2：修改 `_handleRedownload()`**

修改 `app/lib/screens/library_screen.dart:640-641`，原本：

```dart
    final remoteServerRepository = widget.remoteServerRepository;
    final createOpdsClient = widget.createOpdsClient;
```

改為：

```dart
    final remoteServerRepository = widget.remoteLibraryDependencies.remoteServerRepository;
    final createOpdsClient = widget.remoteLibraryDependencies.createOpdsClient;
```

- [ ] **Step 3：修改 `_buildAppBarActions()` 的「遠端書庫」按鈕門檻判斷與 `RemoteServerListScreen` 建構**

修改 `app/lib/screens/library_screen.dart:941-963`，原本：

```dart
        if (widget.remoteServerRepository != null &&
            widget.createOpdsClient != null &&
            widget.computeFingerprint != null &&
            widget.thumbnailCache != null)
          IconButton(
            key: const Key('library_remote_library_button'),
            icon: const Icon(Icons.cloud_outlined),
            tooltip: '遠端書庫',
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (context) => RemoteServerListScreen(
                        repository: widget.remoteServerRepository!,
                        libraryRepository: widget.repository,
                        dependencies: RemoteCatalogDependencies(
                          computeFingerprint: widget.computeFingerprint!,
                          thumbnailCache: widget.thumbnailCache!,
                          createOpdsClient: widget.createOpdsClient!,
                        ),
                        importService: widget.importService,
                        isEinkMode: widget.isEinkMode,
                      ),
                    ),
                  )
```

改為（`widget.isEinkMode` 屬 Task 6 範圍，本步驟維持原樣不動）：

```dart
        if (widget.remoteLibraryDependencies.remoteServerRepository != null &&
            widget.remoteLibraryDependencies.createOpdsClient != null &&
            widget.computeFingerprint != null &&
            widget.remoteLibraryDependencies.thumbnailCache != null)
          IconButton(
            key: const Key('library_remote_library_button'),
            icon: const Icon(Icons.cloud_outlined),
            tooltip: '遠端書庫',
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (context) => RemoteServerListScreen(
                        repository: widget.remoteLibraryDependencies.remoteServerRepository!,
                        libraryRepository: widget.repository,
                        dependencies: RemoteCatalogDependencies(
                          computeFingerprint: widget.computeFingerprint!,
                          thumbnailCache: widget.remoteLibraryDependencies.thumbnailCache!,
                          createOpdsClient: widget.remoteLibraryDependencies.createOpdsClient!,
                        ),
                        importService: widget.importService,
                        isEinkMode: widget.isEinkMode,
                      ),
                    ),
                  )
```

- [ ] **Step 4：確認 `RemoteServerRepository`／`OpdsClient`（`Function()` 型別標註部分）／`RemoteThumbnailCache` 三個型別的 import 是否仍需要**

`opds_client.dart` 因 `RemoteCatalogDependencies(createOpdsClient: ...)` 建構時仍需要 `OpdsClient` 型別標註，通常仍需保留；`remote_server_repository.dart`／`remote_thumbnail_cache.dart` 待 Step 1-3 完成後跑 `flutter analyze app/lib/screens/library_screen.dart` 確認，依實際結果決定是否移除。

- [ ] **Step 5：更新 `main.dart` 呼叫端**

原本（節錄相關 3 行）：

```dart
        remoteServerRepository: widget.remoteServerRepository,
        createOpdsClient: widget.createOpdsClient,
        thumbnailCache: widget.thumbnailCache,
```

改為：

```dart
        remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
          remoteServerRepository: widget.remoteServerRepository,
          createOpdsClient: widget.createOpdsClient,
          thumbnailCache: widget.thumbnailCache,
        ),
```

- [ ] **Step 6：更新 `library_screen_test.dart` 的 6 處測試建構**

**(a) 約 3343-3351 行**（「提供 remoteServerRepository/opdsClient 時，AppBar 顯示遠端書庫按鈕」測試），原本：

```dart
        home: LibraryScreen(
          repository: repository,
          importService: importService,
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(),
          createOpdsClient: () => FakeOpdsClient(),
          computeFingerprint: (path, format) async => 'test-fingerprint',
          thumbnailCache: FakeRemoteThumbnailCache(),
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: repository,
          importService: importService,
          prefsManager: FakeReaderPrefsManager(),
          remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
            remoteServerRepository: FakeRemoteServerRepository(),
            createOpdsClient: () => FakeOpdsClient(),
            thumbnailCache: FakeRemoteThumbnailCache(),
          ),
          computeFingerprint: (path, format) async => 'test-fingerprint',
        ),
```

**(b) 約 3373-3381 行**（「從遠端書庫返回書架時，重新載入書籍清單」測試），與 (a) 完全相同的欄位組合，套用同一轉換規則。

**(c) 約 3550-3557 行**（「點擊待下載書籍先跳出確認對話框」測試），原本：

```dart
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
          createOpdsClient: () => opdsClient,
          isMobileDataConnection: () async => false,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
            remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
            createOpdsClient: () => opdsClient,
          ),
          isMobileDataConnection: () async => false,
        ),
```

**(d) 約 3573-3582 行**（「偵測到行動數據連線時，確認對話框額外顯示流量提示文字」測試），原本：

```dart
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
          createOpdsClient: () => FakeOpdsClient(),
          isMobileDataConnection: () async => true,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
            remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
            createOpdsClient: () => FakeOpdsClient(),
          ),
          isMobileDataConnection: () async => true,
        ),
```

**(e) 約 3595-3602 行**（「確認後成功重新下載」測試），原本：

```dart
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
          createOpdsClient: () => opdsClient,
          isMobileDataConnection: () async => false,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
            remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
            createOpdsClient: () => opdsClient,
          ),
          isMobileDataConnection: () async => false,
        ),
```

**(f) 約 3630-3637 行**（「下載失敗時顯示錯誤訊息」測試），原本：

```dart
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
          createOpdsClient: () => opdsClient,
          isMobileDataConnection: () async => false,
        ),
```

改為：

```dart
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
            remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
            createOpdsClient: () => opdsClient,
          ),
          isMobileDataConnection: () async => false,
        ),
```

- [ ] **Step 7：執行測試確認通過**

執行：`cd app && flutter test test/screens/library_screen_test.dart`
預期：`PASS`。

- [ ] **Step 8：Commit**

```bash
git add app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/library_screen_test.dart
git commit -m "refactor(epic-26): Issue 7 Task 5——LibraryScreen 改用 remoteLibraryDependencies bundle"
```

---

### Task 6：`LibraryScreen` 改用 `themeDependencies`（`currentTheme`／`isEinkMode`／`onThemeChanged`／`onEinkModeChanged`）

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`

**Interfaces:**
- Consumes：Task 1 的 `LibraryThemeDependencies`。
- Produces：`LibraryScreen` 建構子新增 `LibraryThemeDependencies themeDependencies`（可選，預設 `const LibraryThemeDependencies()`，`currentTheme`/`isEinkMode` 沿用原欄位現行預設值），取代原本 4 個獨立具名參數。無需修改 `library_screen_test.dart`——該檔案目前沒有任何測試案例傳入 `currentTheme`／`isEinkMode`／`onThemeChanged`／`onEinkModeChanged`（已用 `grep` 核對確認零筆），既有測試不受影響。

- [ ] **Step 1：修改 `LibraryScreen` 欄位宣告與建構子**

欄位宣告原本：

```dart
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final ValueChanged<bool>? onEinkModeChanged;
```

改為：

```dart
  /// 收斂原本 `currentTheme`／`isEinkMode`／`onThemeChanged`／
  /// `onEinkModeChanged` 四個獨立參數（epic-26-architecture-hardening
  /// Issue 7）。
  final LibraryThemeDependencies themeDependencies;
```

建構子參數列原本：

```dart
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
```

改為：

```dart
    this.themeDependencies = const LibraryThemeDependencies(),
```

- [ ] **Step 2：修改 `_buildNormalAppBar()` 的 E-Ink 切換按鈕**

修改 `app/lib/screens/library_screen.dart:859-868`，原本：

```dart
        IconButton(
          key: const Key('library_eink_toggle'),
          icon: Icon(
            widget.isEinkMode ? Icons.contrast : Icons.contrast_outlined,
            color:
                widget.isEinkMode ? Theme.of(context).colorScheme.primary : null,
          ),
          tooltip: 'E-Ink 高對比模式',
          onPressed: () => widget.onEinkModeChanged?.call(!widget.isEinkMode),
        ),
```

改為：

```dart
        IconButton(
          key: const Key('library_eink_toggle'),
          icon: Icon(
            widget.themeDependencies.isEinkMode ? Icons.contrast : Icons.contrast_outlined,
            color: widget.themeDependencies.isEinkMode
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          tooltip: 'E-Ink 高對比模式',
          onPressed: () => widget.themeDependencies.onEinkModeChanged
              ?.call(!widget.themeDependencies.isEinkMode),
        ),
```

- [ ] **Step 3：修改 `_openGroupFilteredView()` 自我遞迴，整包轉送（現行四者皆整組轉送）**

修改 `app/lib/screens/library_screen.dart:771-774`，原本：

```dart
              currentTheme: widget.currentTheme,
              isEinkMode: widget.isEinkMode,
              onThemeChanged: widget.onThemeChanged,
              onEinkModeChanged: widget.onEinkModeChanged,
```

改為：

```dart
              themeDependencies: widget.themeDependencies,
```

- [ ] **Step 4：修改 `_buildAppBarActions()` 的「遠端書庫」按鈕（只用 `isEinkMode`，Task 5 已處理過的 `RemoteServerListScreen` 建構區塊）**

修改 `app/lib/screens/library_screen.dart`（Task 5 Step 3 已改過的區塊）內：

```dart
                        isEinkMode: widget.isEinkMode,
```

改為：

```dart
                        isEinkMode: widget.themeDependencies.isEinkMode,
```

- [ ] **Step 5：修改 `_buildAppBarActions()` 建構 `SettingsScreen`（只用 `currentTheme`／`isEinkMode`／`onThemeChanged`，不用 `onEinkModeChanged`——比照現行既有行為，不做修正）**

修改 `app/lib/screens/library_screen.dart:981-983`，原本：

```dart
                  currentTheme: widget.currentTheme,
                  isEinkMode: widget.isEinkMode,
                  onThemeChanged: widget.onThemeChanged,
```

改為：

```dart
                  currentTheme: widget.themeDependencies.currentTheme,
                  isEinkMode: widget.themeDependencies.isEinkMode,
                  onThemeChanged: widget.themeDependencies.onThemeChanged,
```

- [ ] **Step 6：確認 `AppTheme`／`ValueChanged` 是否仍需要 import**

`AppTheme` 型別在 `LibraryScreen` 其餘地方（例如 `_buildAppBarActions()` 內的 `AppTheme` 具名參照，如果有）可能仍需要，`ValueChanged` 通常只在欄位型別標註使用——待本 Step 完成後跑 `flutter analyze app/lib/screens/library_screen.dart` 確認，依實際結果決定是否移除對應 import。

- [ ] **Step 7：更新 `main.dart` 呼叫端**

原本（節錄相關 4 行）：

```dart
        currentTheme: _theme,
        isEinkMode: _isEinkMode,
        onThemeChanged: _handleThemeChanged,
        onEinkModeChanged: _handleEinkModeChanged,
```

改為：

```dart
        themeDependencies: LibraryThemeDependencies(
          currentTheme: _theme,
          isEinkMode: _isEinkMode,
          onThemeChanged: _handleThemeChanged,
          onEinkModeChanged: _handleEinkModeChanged,
        ),
```

- [ ] **Step 8：執行測試確認通過**

執行：`cd app && flutter test test/screens/library_screen_test.dart`
預期：`PASS`（本 Task 未修改任何測試建構，純粹驗證 Step 1-7 對正式程式碼的修改沒有連帶破壞既有測試）。

- [ ] **Step 9：Commit**

```bash
git add app/lib/screens/library_screen.dart app/lib/main.dart
git commit -m "refactor(epic-26): Issue 7 Task 6——LibraryScreen 改用 themeDependencies bundle"
```

---

### Task 7：全專案最終驗證

**Files:**
- 無新增/修改檔案，純驗證。

- [ ] **Step 1：全域殘留掃描，確認舊的獨立參數存取模式已無殘留**

執行：
```bash
cd app
grep -rn "widget\.bookmarksRepository\b\|widget\.highlightsRepository\b\|widget\.notesRepository\b\|widget\.layoutPresetRepository\b\|widget\.bookReaderPrefsRepository\b" lib/screens/library_screen.dart
grep -rn "widget\.syncAccountRepository\b\|widget\.syncClient\b\|widget\.syncCheckpointTrigger\b" lib/screens/library_screen.dart
grep -rn "widget\.cloudAccountRepository\b\|widget\.googleDriveOAuthClient\b\|widget\.oneDriveOAuthClient\b\|widget\.googleDriveStorageClient\b\|widget\.oneDriveStorageClient\b" lib/screens/library_screen.dart
grep -rn "widget\.remoteServerRepository\b\|widget\.createOpdsClient\b\|widget\.thumbnailCache\b" lib/screens/library_screen.dart
grep -rn "widget\.currentTheme\b\|widget\.isEinkMode\b\|widget\.onThemeChanged\b\|widget\.onEinkModeChanged\b" lib/screens/library_screen.dart
```
預期：全數皆無輸出（`widget.customFontsRepository` 這類子字串在 `widget.readerFeatureRepositories.customFontsRepository` 中不會誤命中——`widget\.customFontsRepository\b` 要求緊接在 `widget.` 之後，中間插入 `readerFeatureRepositories.` 後已不再符合此樣式，無需另外排除）。

**【審查修正 review-issue-7.md Important #2】** 本 Step 原始設計的掃描範圍只涵蓋 `lib/screens/library_screen.dart`（確認「舊參數存取模式是否還在」），沒有反向掃描 `lib/main.dart`（確認「新 bundle 呼叫點是否仍逐一轉發所有原始欄位」）——這正是 Task 5 把 `computeFingerprint` 漏轉發到 `main.dart` 組裝根的 Critical 問題（見 review-issue-7.md Critical #1）能一路通過本 Task 卻未被攔截的根因。日後同類「多處呼叫點需要同步改寫」的計畫，最終驗證除了掃描「新介面殘留舊寫法」外，也應對每一個涉及的**呼叫端組裝檔案**（尤其是 `main.dart` 這種組裝根）加一條「新舊欄位數量/清單比對」的驗證步驟，不要只信任計畫文件裡摘錄的 before/after 片段，改用 `git show`／實際檔案內容重新核對。

- [ ] **Step 2：執行 `flutter analyze`**

執行：`cd app && flutter analyze`
預期：`No issues found!`（確認 Task 2-6 Step 中提到「依實際結果決定是否移除的 import」皆已正確處理，無 `unused_import` 或其他警告；`integration_test/library_screen_test.dart` 只用必要參數建構，預期不受影響）。

- [ ] **Step 3：執行全專案測試**

執行：`cd app && flutter test`
預期：全數通過，零回歸（相較 Issue 6 合併後的基準數字 1607，本 Issue Task 1 新增 5 項 bundle 單元測試，其餘為既有 `library_screen_test.dart` 案例的等價重寫，總數應為「1607 + 5」）。

- [ ] **Step 4：逐項核對驗收標準**

- [ ] `LibraryScreen` 建構子的具名參數數量明顯減少（27 個收斂為 5 個 bundle＋6 個核心參數，共 11 個）。
- [ ] 所有既有呼叫點（`main.dart`／`library_screen_test.dart`）皆已更新為新介面。
- [ ] 行為零改變，含「規劃階段查證」與各 Task 內明確記載的既有不對稱轉送模式（`_openGroupFilteredView()` 不轉送 `layoutPresetRepository`／`bookReaderPrefsRepository`／`remoteServerRepository`／`createOpdsClient`／`thumbnailCache`；`SettingsScreen` 不接收 `onEinkModeChanged`）皆原樣保留。
- [ ] `flutter analyze` 乾淨、`flutter test` 全數通過。
