# Epic 26 Issue 6：收斂 `ComputeRemoteFingerprint` 在多個畫面之間的穿透 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ComputeRemoteFingerprint`／`RemoteThumbnailCache`／`OpdsClient Function()` 這三個永遠一起出現在 `RemoteServerListScreen`／`RemoteCatalogScreen` 建構子的參數，收斂為單一 `RemoteCatalogDependencies` bundle 物件，消除自我遞迴（`RemoteCatalogScreen._openSubsection()`）與跨畫面轉送時「忘記轉送某個欄位」的風險。

**Architecture:** 新增一個不可變資料類別 `RemoteCatalogDependencies`（純資料持有者，無邏輯），只在 `RemoteServerListScreen`／`RemoteCatalogScreen` 兩個「OPDS 遠端書庫瀏覽」相關畫面之間流通；`LibraryScreen`、`main.dart`、`CloudBrowserScreen`、`CloudDownloadQueueDialog` 完全不受影響（原因見下方「規劃階段查證：範圍為何比 Issue 原文更窄」）。

**Tech Stack:** Flutter／Dart，無新增套件依賴。

**Spec:** `docs/epics/epic-26-architecture-hardening/issues.md` Issue 6；`docs/research/architecture-review-library-remote-screens.md` 候選 3。

## 規劃階段查證：範圍為何比 Issue 原文更窄（務必先讀，避免誤解本計畫範圍）

Issue 6 原文建議「封裝為一個小型不可變資料類別，內含 `computeFingerprint`／`createOpdsClient`／`thumbnailCache`」，字面上聽起來像是要在**所有** 7 個穿透檔案（`main.dart`／`library_screen.dart`／`cloud_browser_screen.dart`／`remote_server_list_screen.dart`／`remote_catalog_screen.dart`／`cloud_download_queue_dialog.dart`／`book_content_fingerprint.dart`）套用同一個 bundle。規劃階段逐檔案交叉核對後，發現這三個欄位**並非在每個檔案都以相同組合一起出現**，若不分青紅皂白全部塞進同一個 bundle，會改變現行行為：

1. **`LibraryScreen._openGroupFilteredView()`（`library_screen.dart:727-777`）自我遞迴建構 `LibraryScreen` 時，只轉送 `computeFingerprint`，刻意（或至少現況如此）不轉送 `remoteServerRepository`／`thumbnailCache`／`createOpdsClient`**——分類篩選子畫面內「從 Google Drive／OneDrive 匯入」可用（只需要 `computeFingerprint`），但「遠端書庫」按鈕（`library_remote_library_button`，需要另外 3 個欄位皆非 null，見 `library_screen.dart:940-943`）不會出現。若把 `computeFingerprint` 綁進一個要求「三者皆非 null」的 bundle，這個子畫面會連 Google Drive／OneDrive 匯入都失效——**是真實的行為倒退**，不是本 Issue 該做的事。
2. **`LibraryScreen._handleRedownload()`（`library_screen.dart:638-690`）只用 `remoteServerRepository`＋`createOpdsClient`，完全不碰 `thumbnailCache`／`computeFingerprint`**——`createOpdsClient` 在這裡是獨立配對，不是恆定三人組。
3. **`CloudBrowserScreen`／`CloudDownloadQueueDialog` 只需要 `computeFingerprint` 一個欄位**，用於 Google Drive／OneDrive 雲端匯入的重複偵測，與 `thumbnailCache`／`createOpdsClient`（皆為 OPDS/Calibre 專屬）完全無關。

**唯一驗證為「每次出現皆三者同時、皆為必要（`required`，非 nullable）、無例外」的邊界，是 `RemoteServerListScreen` 與 `RemoteCatalogScreen`（含其自我遞迴 `_openSubsection()`）這兩個類別本身**——本計畫只在這個範圍內收斂，`LibraryScreen`／`main.dart`／`CloudBrowserScreen`／`CloudDownloadQueueDialog` 的欄位與轉送邏輯完全不動，零行為改變。範圍縮小但仍然直接命中 Issue 6 描述的核心風險最集中處：`RemoteCatalogScreen._openSubsection()` 是**同一個類別建構自己**的自我遞迴（與造成 `925703f` 那次事故的 `LibraryScreen` 自我遞迴屬於同一種高風險模式），也是本次查證中「三個獨立參數」重複次數最多的單一檔案（13 處測試建構＋2 處正式程式碼建構）。

## Global Constraints

- 程式碼註解／變數說明使用中文，遵循既有檔案風格。
- `flutter analyze` 涵蓋 `app/integration_test/`——即使不執行也需確保能編譯通過；本 Issue 不涉及 `integration_test/` 底下任何檔案（`RemoteCatalogScreen`／`RemoteServerListScreen` 目前沒有對應的 integration test），Task 4 仍需執行 `flutter analyze` 確認。
- 維持 ADR 0007「平行建構子參數、不用 service locator」的組裝哲學——`RemoteCatalogDependencies` 是一個透過建構子參數傳遞的**資料**物件，不是任何形式的 service locator／全域單例。
- 零行為改變：本計畫是純重構，不新增、不移除、不調整任何使用者可觀察行為；`RemoteServerFormScreen`（`_openAddForm`/`_openEditForm`）目前只用 `createOpdsClient` 一個欄位，維持獨立傳遞方式不變（不因為 `RemoteServerListScreen` 改用 bundle 就連帶改變 `RemoteServerFormScreen` 的既有介面）。
- Commit message 慣例：`refactor(epic-26): Issue 6 Task N——<描述>` / `test(epic-26): Issue 6 Task N——<描述>`。

---

### Task 1：建立 `RemoteCatalogDependencies` bundle 型別

**Files:**
- Create: `app/lib/remote/remote_catalog_dependencies.dart`
- Test: `app/test/remote/remote_catalog_dependencies_test.dart`

**Interfaces:**
- Produces：`class RemoteCatalogDependencies { final ComputeRemoteFingerprint computeFingerprint; final RemoteThumbnailCache thumbnailCache; final OpdsClient Function() createOpdsClient; const RemoteCatalogDependencies({required this.computeFingerprint, required this.thumbnailCache, required this.createOpdsClient}); }`——Task 2／3 皆會 import 並使用這個型別與其三個欄位存取器（`.computeFingerprint`／`.thumbnailCache`／`.createOpdsClient`）。

- [ ] **Step 1：寫失敗測試，驗證 bundle 正確持有三個欄位**

```dart
// app/test/remote/remote_catalog_dependencies_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/remote/remote_catalog_dependencies.dart';
import 'package:elinkbook/remote/opds_client.dart';

import '../support/fake_fingerprint_computer.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_thumbnail_cache.dart';

void main() {
  test('RemoteCatalogDependencies 原樣持有三個注入的依賴', () {
    final fingerprintComputer = FakeFingerprintComputer();
    final thumbnailCache = FakeRemoteThumbnailCache();
    OpdsClient createClient() => FakeOpdsClient();

    final dependencies = RemoteCatalogDependencies(
      computeFingerprint: fingerprintComputer.call,
      thumbnailCache: thumbnailCache,
      createOpdsClient: createClient,
    );

    expect(dependencies.computeFingerprint, same(fingerprintComputer.call));
    expect(dependencies.thumbnailCache, same(thumbnailCache));
    expect(dependencies.createOpdsClient, same(createClient));
  });
}
```

- [ ] **Step 2：執行測試確認失敗（型別尚未存在）**

執行：`cd app && flutter test test/remote/remote_catalog_dependencies_test.dart`
預期：`FAIL`，錯誤訊息為找不到 `package:elinkbook/remote/remote_catalog_dependencies.dart`（或找不到 `RemoteCatalogDependencies` 型別）。

- [ ] **Step 3：實作 `RemoteCatalogDependencies`**

```dart
// app/lib/remote/remote_catalog_dependencies.dart
import '../library/book_content_fingerprint.dart';
import 'opds_client.dart';
import 'remote_thumbnail_cache.dart';

/// 收斂 `RemoteServerListScreen`／`RemoteCatalogScreen`（含其自我遞迴
/// `_openSubsection()`）之間永遠同時出現、缺一不可的三個依賴，取代原本
/// 各自宣告/轉送 3 個獨立具名參數的做法（epic-26-architecture-hardening
/// Issue 6，docs/research/architecture-review-library-remote-screens.md
/// 候選 3）。**範圍刻意侷限這兩個畫面**——`LibraryScreen`／`main.dart`／
/// `CloudBrowserScreen`／`CloudDownloadQueueDialog` 對這三個依賴有各自
/// 獨立、不完全重疊的使用組合，不適合套用同一個 bundle（詳見
/// `plans/plan-issue-6.md`「規劃階段查證」段落），故不動這些檔案。
class RemoteCatalogDependencies {
  final ComputeRemoteFingerprint computeFingerprint;
  final RemoteThumbnailCache thumbnailCache;
  final OpdsClient Function() createOpdsClient;

  const RemoteCatalogDependencies({
    required this.computeFingerprint,
    required this.thumbnailCache,
    required this.createOpdsClient,
  });
}
```

- [ ] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/remote/remote_catalog_dependencies_test.dart`
預期：`PASS`

- [ ] **Step 5：Commit**

```bash
git add app/lib/remote/remote_catalog_dependencies.dart app/test/remote/remote_catalog_dependencies_test.dart
git commit -m "refactor(epic-26): Issue 6 Task 1——新增 RemoteCatalogDependencies bundle 型別"
```

---

### Task 2：`RemoteCatalogScreen` 改用 `dependencies`（含自我遞迴 `_openSubsection()` 與內部 `_DownloadQueueDialog` 呼叫端），同步更新 `RemoteServerListScreen._openCatalog()` 呼叫端

**Files:**
- Modify: `app/lib/screens/remote_catalog_screen.dart`
- Modify: `app/lib/screens/remote_server_list_screen.dart:85-98`（`_openCatalog()`）
- Test: `app/test/screens/remote_catalog_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `RemoteCatalogDependencies`（`app/lib/remote/remote_catalog_dependencies.dart`）。
- Produces：`RemoteCatalogScreen` 建構子新增 `required RemoteCatalogDependencies dependencies` 參數，取代原本的 `computeFingerprint`／`thumbnailCache`／`createOpdsClient` 三個獨立參數（Task 3 的 `RemoteServerListScreen._openCatalog()` 呼叫端需要同步更新，已在本 Task 一併處理）。

- [ ] **Step 1：修改 `RemoteCatalogScreen` 欄位與建構子**

修改 `app/lib/screens/remote_catalog_screen.dart:32-66`，原本：

```dart
class RemoteCatalogScreen extends StatefulWidget {
  final RemoteServerProfile server;
  final RemoteServerRepository repository;
  final LibraryRepository libraryRepository;
  final ComputeRemoteFingerprint computeFingerprint;
  final RemoteThumbnailCache thumbnailCache;
  final OpdsClient Function() createOpdsClient;
  final BookImportService importService;

  /// `null` 代表載入 [server.baseUrl]（站點根目錄）；非 `null` 時載入指定
  /// 的分類/分頁 Feed（點擊 [OpdsNavigationLink] 下鑽時使用）。
  final String? feedUrl;

  /// AppBar 標題，`null` 時使用 [server.name]（根目錄畫面）。
  final String? title;

  /// E-Ink 模式（epic-30-calibre-remote-library Issue 5，design.md
  /// 「E-Ink 與後續優化」）：`true` 時把連續捲動「載入更多」換成離散
  /// 「上一頁／下一頁」整頁換頁，避免高幀率捲動動畫造成的殘影。比照
  /// 既有 `LibraryScreen.isEinkMode` 的預設值與非空語意。
  final bool isEinkMode;

  const RemoteCatalogScreen({
    super.key,
    required this.server,
    required this.repository,
    required this.libraryRepository,
    required this.computeFingerprint,
    required this.thumbnailCache,
    required this.createOpdsClient,
    required this.importService,
    this.feedUrl,
    this.title,
    this.isEinkMode = false,
  });
```

改為：

```dart
class RemoteCatalogScreen extends StatefulWidget {
  final RemoteServerProfile server;
  final RemoteServerRepository repository;
  final LibraryRepository libraryRepository;

  /// 收斂原本 `computeFingerprint`／`thumbnailCache`／`createOpdsClient`
  /// 三個獨立參數（epic-26-architecture-hardening Issue 6）。
  final RemoteCatalogDependencies dependencies;

  final BookImportService importService;

  /// `null` 代表載入 [server.baseUrl]（站點根目錄）；非 `null` 時載入指定
  /// 的分類/分頁 Feed（點擊 [OpdsNavigationLink] 下鑽時使用）。
  final String? feedUrl;

  /// AppBar 標題，`null` 時使用 [server.name]（根目錄畫面）。
  final String? title;

  /// E-Ink 模式（epic-30-calibre-remote-library Issue 5，design.md
  /// 「E-Ink 與後續優化」）：`true` 時把連續捲動「載入更多」換成離散
  /// 「上一頁／下一頁」整頁換頁，避免高幀率捲動動畫造成的殘影。比照
  /// 既有 `LibraryScreen.isEinkMode` 的預設值與非空語意。
  final bool isEinkMode;

  const RemoteCatalogScreen({
    super.key,
    required this.server,
    required this.repository,
    required this.libraryRepository,
    required this.dependencies,
    required this.importService,
    this.feedUrl,
    this.title,
    this.isEinkMode = false,
  });
```

並在檔案頂端 import 區塊新增：

```dart
import '../remote/remote_catalog_dependencies.dart';
```

- [ ] **Step 2：新增 import 後，`ComputeRemoteFingerprint`／`RemoteThumbnailCache`／`OpdsClient` 三個型別是否仍需要各自 import 需重新確認**

`book_content_fingerprint.dart`／`remote_thumbnail_cache.dart` 的 import 若本檔案其餘地方不再直接引用這兩個型別名稱（只透過 `dependencies.xxx` 存取值、不再宣告該型別的變數），可以移除；`opds_client.dart` 的 import 仍需保留（`OpdsClient _client` 欄位、`OpdsClient?` 相關型別標註仍存在，見 `remote_catalog_screen.dart:73` `late final OpdsClient _client;`）。實作時先完成 Step 3-6 的內文改動，最後對整份檔案跑一次 `flutter analyze app/lib/screens/remote_catalog_screen.dart` 確認有無 `unused_import`，依實際結果決定是否移除 `book_content_fingerprint.dart`／`remote_thumbnail_cache.dart` 這兩個 import（不要憑空猜測，以 analyze 實際結果為準）。

- [ ] **Step 3：修改 `initState()`（`_client = widget.createOpdsClient();`）**

修改 `app/lib/screens/remote_catalog_screen.dart:98` 附近，原本：

```dart
    _client = widget.createOpdsClient();
```

改為：

```dart
    _client = widget.dependencies.createOpdsClient();
```

- [ ] **Step 4：修改 `_openSubsection()` 自我遞迴建構**

修改 `app/lib/screens/remote_catalog_screen.dart:200-215`，原本：

```dart
  void _openSubsection(OpdsNavigationLink link) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: widget.server,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        computeFingerprint: widget.computeFingerprint,
        thumbnailCache: widget.thumbnailCache,
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
        feedUrl: link.href,
        title: link.title,
        isEinkMode: widget.isEinkMode,
      ),
    ));
  }
```

改為：

```dart
  void _openSubsection(OpdsNavigationLink link) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: widget.server,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        dependencies: widget.dependencies,
        importService: widget.importService,
        feedUrl: link.href,
        title: link.title,
        isEinkMode: widget.isEinkMode,
      ),
    ));
  }
```

- [ ] **Step 5：修改 `_startDownload()` 建構 `_DownloadQueueDialog`（該對話框自己只需要 `computeFingerprint` 一個欄位，維持獨立傳遞，不整包塞入 bundle）**

修改 `app/lib/screens/remote_catalog_screen.dart:275-283` 附近，原本：

```dart
      builder: (context) => _DownloadQueueDialog(
        queue: queue,
        client: _client,
        server: widget.server,
        password: _password,
        importService: widget.importService,
        libraryRepository: widget.libraryRepository,
        computeFingerprint: widget.computeFingerprint,
      ),
```

改為：

```dart
      builder: (context) => _DownloadQueueDialog(
        queue: queue,
        client: _client,
        server: widget.server,
        password: _password,
        importService: widget.importService,
        libraryRepository: widget.libraryRepository,
        computeFingerprint: widget.dependencies.computeFingerprint,
      ),
```

- [ ] **Step 6：修改縮圖抓取（`widget.thumbnailCache.fetch(...)`）**

修改 `app/lib/screens/remote_catalog_screen.dart:434` 附近，原本：

```dart
      future: widget.thumbnailCache.fetch(
```

改為：

```dart
      future: widget.dependencies.thumbnailCache.fetch(
```

- [ ] **Step 7：更新 `remote_server_list_screen.dart._openCatalog()` 呼叫端**

修改 `app/lib/screens/remote_server_list_screen.dart:85-98`，原本：

```dart
  void _openCatalog(RemoteServerProfile profile) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: profile,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        computeFingerprint: widget.computeFingerprint,
        thumbnailCache: widget.thumbnailCache,
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
        isEinkMode: widget.isEinkMode,
      ),
    ));
  }
```

改為：

```dart
  void _openCatalog(RemoteServerProfile profile) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: profile,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        dependencies: RemoteCatalogDependencies(
          computeFingerprint: widget.computeFingerprint,
          thumbnailCache: widget.thumbnailCache,
          createOpdsClient: widget.createOpdsClient,
        ),
        importService: widget.importService,
        isEinkMode: widget.isEinkMode,
      ),
    ));
  }
```

（`RemoteServerListScreen` 自身此時仍保留原本 3 個獨立欄位——Task 3 才會把它自己的建構子也改成接收 `dependencies`，本 Step 只是讓它「內部組裝」一次 bundle 傳給 `RemoteCatalogScreen`，屬過渡狀態，Task 完成後專案仍可編譯。）

並在 `app/lib/screens/remote_server_list_screen.dart` 頂端 import 區塊新增：

```dart
import '../remote/remote_catalog_dependencies.dart';
```

- [ ] **Step 8：更新 `remote_catalog_screen_test.dart` 的共用 `pumpScreen` helper**

修改 `app/test/screens/remote_catalog_screen_test.dart:80-101` 附近的 `pumpScreen()`，原本：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeOpdsClient opdsClient,
    FakeRemoteServerRepository? repository,
    FakeLibraryRepository? libraryRepository,
    FakeFingerprintComputer? fingerprintComputer,
    FakeRemoteThumbnailCache? thumbnailCache,
    String? feedUrl,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteCatalogScreen(
        server: server,
        repository: repository ?? FakeRemoteServerRepository(),
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        computeFingerprint: (fingerprintComputer ?? FakeFingerprintComputer()).call,
        thumbnailCache: thumbnailCache ?? FakeRemoteThumbnailCache(),
        createOpdsClient: () => opdsClient,
        importService: FakeBookImportService(),
        feedUrl: feedUrl,
      ),
```

改為：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeOpdsClient opdsClient,
    FakeRemoteServerRepository? repository,
    FakeLibraryRepository? libraryRepository,
    FakeFingerprintComputer? fingerprintComputer,
    FakeRemoteThumbnailCache? thumbnailCache,
    String? feedUrl,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteCatalogScreen(
        server: server,
        repository: repository ?? FakeRemoteServerRepository(),
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        dependencies: RemoteCatalogDependencies(
          computeFingerprint: (fingerprintComputer ?? FakeFingerprintComputer()).call,
          thumbnailCache: thumbnailCache ?? FakeRemoteThumbnailCache(),
          createOpdsClient: () => opdsClient,
        ),
        importService: FakeBookImportService(),
        feedUrl: feedUrl,
      ),
```

並在檔案頂端新增 import：

```dart
import 'package:elinkbook/remote/remote_catalog_dependencies.dart';
```

- [ ] **Step 9：更新其餘 12 處獨立建構 `RemoteCatalogScreen` 的測試案例**

執行 `grep -n "computeFingerprint:" app/test/screens/remote_catalog_screen_test.dart` 確認：Step 8 完成後，這個指令應只剩下 bundle 內部（`RemoteCatalogDependencies(computeFingerprint: ...)`）與 Step 5 對應的 `_DownloadQueueDialog` 相關案例（若有獨立測到 `_DownloadQueueDialog`）會命中。Step 8 之外，本檔案還有 12 處**不經過 `pumpScreen()`、直接建構 `RemoteCatalogScreen` 或以 `Navigator.push` 方式驅動 `_openSubsection()` 情境**的獨立測試案例（分布於 302／338／374／415／463／509／546／586／626／677／728／771 行附近），每一處都是同一種寫法：

```dart
          computeFingerprint: FakeFingerprintComputer().call,
          thumbnailCache: FakeRemoteThumbnailCache(),
          createOpdsClient: () => opdsClient,
```

（或部分案例是 `computeFingerprint: (path, format) async => 'unused-fingerprint',` / `computeFingerprint: fingerprintComputer.call,` 這兩種變形，取值不同但結構相同）逐一改為：

```dart
          dependencies: RemoteCatalogDependencies(
            computeFingerprint: FakeFingerprintComputer().call,
            thumbnailCache: FakeRemoteThumbnailCache(),
            createOpdsClient: () => opdsClient,
          ),
```

（依原本三行各自的實際值代入 bundle 內對應欄位，保留每個案例原本各自使用的 fake／inline function 值不變，只改變包裝方式；縮排依照該處原本的巢狀層級調整，部分案例巢狀較深、縮排會是 10 或 12 個空格，比照原本三行的縮排量）。

- [ ] **Step 10：新增自我遞迴回歸測試，鎖定「新轉送路徑只需要一個 bundle 參數就不會漏轉送」**

現有測試（`app/test/screens/remote_catalog_screen_test.dart:120-138`「點擊分類導覽項目時 push 新的 RemoteCatalogScreen 並載入該分類 Feed」）只間接證明 `createOpdsClient` 有被正確轉送（透過 `opdsClient.fetchFeedCalls` 觀察），沒有直接斷言 `dependencies` 本身有沒有被完整、原樣轉送給下鑽後的新畫面實例——這正是 Issue 6 要求鎖定的回歸情境（比照 `925703f` 那類「自我遞迴時漏轉送」的 bug class，現在改用 bundle 後，若有人不小心在 `_openSubsection()` 內少寫 `dependencies: widget.dependencies,`，會直接編譯失敗而非靜默漏轉送；本測試額外鎖定「就算編譯過了，轉送的必須是同一個 bundle 實例，不是重新組裝的另一個」）。在該測試之後新增：

```dart
  testWidgets('點擊分類導覽項目下鑽後，新畫面沿用同一個 RemoteCatalogDependencies 實例（epic-26 Issue 6 回歸鎖定）',
      (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(
        title: '根目錄',
        navigationLinks: [OpdsNavigationLink(title: '作者分類', href: 'http://192.168.1.100:8080/opds/by-author')],
      ),
      'http://192.168.1.100:8080/opds/by-author': const OpdsFeed(
        title: '作者分類',
        entries: [entry1],
      ),
    });
    final dependencies = RemoteCatalogDependencies(
      computeFingerprint: FakeFingerprintComputer().call,
      thumbnailCache: FakeRemoteThumbnailCache(),
      createOpdsClient: () => opdsClient,
    );
    await tester.pumpWidget(MaterialApp(
      home: RemoteCatalogScreen(
        server: server,
        repository: FakeRemoteServerRepository(),
        libraryRepository: FakeLibraryRepository(),
        dependencies: dependencies,
        importService: FakeBookImportService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('作者分類'));
    await tester.pumpAndSettle();

    final pushedScreen = tester.widget<RemoteCatalogScreen>(find.byType(RemoteCatalogScreen).last);
    expect(pushedScreen.dependencies, same(dependencies),
        reason: '下鑽後的新畫面應沿用同一個 bundle 實例，不是重新組裝的另一份');
  });
```

- [ ] **Step 11：執行 `remote_catalog_screen_test.dart` 全部測試確認通過**

執行：`cd app && flutter test test/screens/remote_catalog_screen_test.dart`
預期：`PASS`（全部案例，含 Step 10 新增的自我遞迴回歸測試）。

- [ ] **Step 12：執行 `remote_server_list_screen_test.dart` 確認 Step 7 的過渡狀態未破壞既有測試**

執行：`cd app && flutter test test/screens/remote_server_list_screen_test.dart`
預期：`PASS`（`RemoteServerListScreen` 本身建構子在本 Task 尚未變動，此檔案不需修改；本步驟純粹確認 Step 7 對 `_openCatalog()` 內部實作的修改沒有連帶破壞既有測試）。

- [ ] **Step 13：Commit**

```bash
git add app/lib/screens/remote_catalog_screen.dart app/lib/screens/remote_server_list_screen.dart app/test/screens/remote_catalog_screen_test.dart
git commit -m "refactor(epic-26): Issue 6 Task 2——RemoteCatalogScreen 改用 RemoteCatalogDependencies bundle"
```

---

### Task 3：`RemoteServerListScreen` 改用 `dependencies`，更新 `library_screen.dart` 呼叫端

**Files:**
- Modify: `app/lib/screens/remote_server_list_screen.dart`
- Modify: `app/lib/screens/library_screen.dart:940-960`
- Test: `app/test/screens/remote_server_list_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `RemoteCatalogDependencies`；Task 2 已完成的 `RemoteCatalogScreen(dependencies: ...)` 建構子。
- Produces：`RemoteServerListScreen` 建構子新增 `required RemoteCatalogDependencies dependencies`，取代原本的 `computeFingerprint`／`thumbnailCache`／`createOpdsClient` 三個獨立參數。`LibraryScreen` 自身的欄位與建構子**不變**（見計畫開頭「規劃階段查證」，`LibraryScreen` 仍保留三個獨立欄位，只在建構 `RemoteServerListScreen` 這唯一一處呼叫端組裝 bundle）。

- [ ] **Step 1：修改 `RemoteServerListScreen` 欄位與建構子**

修改 `app/lib/screens/remote_server_list_screen.dart:16-38`，原本：

```dart
class RemoteServerListScreen extends StatefulWidget {
  final RemoteServerRepository repository;
  final LibraryRepository libraryRepository;
  final ComputeRemoteFingerprint computeFingerprint;
  final RemoteThumbnailCache thumbnailCache;
  final OpdsClient Function() createOpdsClient;
  final BookImportService importService;
  final bool isEinkMode;

  const RemoteServerListScreen({
    super.key,
    required this.repository,
    required this.libraryRepository,
    required this.computeFingerprint,
    required this.thumbnailCache,
    required this.createOpdsClient,
    required this.importService,
    this.isEinkMode = false,
  });

  @override
  State<RemoteServerListScreen> createState() => _RemoteServerListScreenState();
}
```

改為：

```dart
class RemoteServerListScreen extends StatefulWidget {
  final RemoteServerRepository repository;
  final LibraryRepository libraryRepository;

  /// 收斂原本 `computeFingerprint`／`thumbnailCache`／`createOpdsClient`
  /// 三個獨立參數（epic-26-architecture-hardening Issue 6）。
  final RemoteCatalogDependencies dependencies;

  final BookImportService importService;
  final bool isEinkMode;

  const RemoteServerListScreen({
    super.key,
    required this.repository,
    required this.libraryRepository,
    required this.dependencies,
    required this.importService,
    this.isEinkMode = false,
  });

  @override
  State<RemoteServerListScreen> createState() => _RemoteServerListScreenState();
}
```

- [ ] **Step 2：修改 `_openAddForm()`／`_openEditForm()`（只用 `createOpdsClient`，從 bundle 取值）**

修改 `app/lib/screens/remote_server_list_screen.dart:60-83`，原本：

```dart
  Future<void> _openAddForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => RemoteServerFormScreen(
          repository: widget.repository,
          createOpdsClient: widget.createOpdsClient,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openEditForm(RemoteServerProfile profile) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => RemoteServerFormScreen(
          repository: widget.repository,
          createOpdsClient: widget.createOpdsClient,
          existingProfile: profile,
        ),
      ),
    );
    if (saved == true) _load();
  }
```

改為：

```dart
  Future<void> _openAddForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => RemoteServerFormScreen(
          repository: widget.repository,
          createOpdsClient: widget.dependencies.createOpdsClient,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openEditForm(RemoteServerProfile profile) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => RemoteServerFormScreen(
          repository: widget.repository,
          createOpdsClient: widget.dependencies.createOpdsClient,
          existingProfile: profile,
        ),
      ),
    );
    if (saved == true) _load();
  }
```

- [ ] **Step 3：修改 `_openCatalog()`，改為直接轉送整包 `dependencies`（取代 Task 2 Step 7 的過渡寫法）**

修改 `app/lib/screens/remote_server_list_screen.dart` 內 `_openCatalog()`（Task 2 Step 7 已改為此過渡狀態）：

```dart
  void _openCatalog(RemoteServerProfile profile) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: profile,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        dependencies: RemoteCatalogDependencies(
          computeFingerprint: widget.computeFingerprint,
          thumbnailCache: widget.thumbnailCache,
          createOpdsClient: widget.createOpdsClient,
        ),
        importService: widget.importService,
        isEinkMode: widget.isEinkMode,
      ),
    ));
  }
```

改為（不再需要就地組裝，直接轉送 `widget.dependencies`）：

```dart
  void _openCatalog(RemoteServerProfile profile) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: profile,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        dependencies: widget.dependencies,
        importService: widget.importService,
        isEinkMode: widget.isEinkMode,
      ),
    ));
  }
```

- [ ] **Step 4：確認 `ComputeRemoteFingerprint`／`RemoteThumbnailCache`／`OpdsClient` 三個型別的 import 是否仍需要**

`app/lib/screens/remote_server_list_screen.dart` 頂端原有 `import '../library/book_content_fingerprint.dart';`／`import '../remote/opds_client.dart';`／`import '../remote/remote_thumbnail_cache.dart';`：`opds_client.dart` 因 `RemoteServerFormScreen` 的 `createOpdsClient` 參數型別標註（`OpdsClient Function()`）與 `widget.dependencies.createOpdsClient` 的回傳型別仍會用到 `OpdsClient`，需保留；`book_content_fingerprint.dart`／`remote_thumbnail_cache.dart` 若本檔案其餘地方不再直接以型別名稱出現（只透過 `dependencies.xxx` 存取值），可能變成未使用 import——比照 Task 2 Step 2 的做法，先完成 Step 1-3 修改後跑 `flutter analyze app/lib/screens/remote_server_list_screen.dart` 確認，依實際結果決定是否移除。

- [ ] **Step 5：更新 `library_screen.dart` 呼叫端**

修改 `app/lib/screens/library_screen.dart:940-961`，原本：

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
                        computeFingerprint: widget.computeFingerprint!,
                        thumbnailCache: widget.thumbnailCache!,
                        createOpdsClient: widget.createOpdsClient!,
                        importService: widget.importService,
                        isEinkMode: widget.isEinkMode,
                      ),
                    ),
                  )
                  .then((_) {
```

改為：

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
                  .then((_) {
```

（`LibraryScreen` 自身的 `remoteServerRepository`／`createOpdsClient`／`computeFingerprint`／`thumbnailCache` 四個欄位與上方的 `if` 空值判斷式**維持完全不變**——本計畫刻意不動 `LibraryScreen` 自己的介面，只在這個唯一的建構 `RemoteServerListScreen` 呼叫點多做一次 bundle 組裝，這正是「規劃階段查證」段落解釋過的範圍邊界。）

並在 `app/lib/screens/library_screen.dart` 頂端 import 區塊新增：

```dart
import '../remote/remote_catalog_dependencies.dart';
```

- [ ] **Step 6：更新 `remote_server_list_screen_test.dart` 的 `pumpScreen` helper**

修改 `app/test/screens/remote_server_list_screen_test.dart:42-56`，原本：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeRemoteServerRepository repository,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteServerListScreen(
        repository: repository,
        libraryRepository: FakeLibraryRepository(),
        computeFingerprint: FakeFingerprintComputer().call,
        thumbnailCache: FakeRemoteThumbnailCache(),
        createOpdsClient: () => FakeOpdsClient(),
        importService: FakeBookImportService(),
      ),
    ));
    await tester.pumpAndSettle();
  }
```

改為：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeRemoteServerRepository repository,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteServerListScreen(
        repository: repository,
        libraryRepository: FakeLibraryRepository(),
        dependencies: RemoteCatalogDependencies(
          computeFingerprint: FakeFingerprintComputer().call,
          thumbnailCache: FakeRemoteThumbnailCache(),
          createOpdsClient: () => FakeOpdsClient(),
        ),
        importService: FakeBookImportService(),
      ),
    ));
    await tester.pumpAndSettle();
  }
```

並在檔案頂端新增 import：

```dart
import 'package:elinkbook/remote/remote_catalog_dependencies.dart';
```

- [ ] **Step 7：執行 `remote_server_list_screen_test.dart` 確認通過**

執行：`cd app && flutter test test/screens/remote_server_list_screen_test.dart`
預期：`PASS`（本檔案只有這一個共用 helper 建構點，所有測試案例皆透過它，Step 6 完成後應全數通過）。

- [ ] **Step 8：執行 `library_screen_test.dart` 中涉及遠端書庫按鈕的測試，確認 Step 5 未破壞既有行為**

執行：`cd app && flutter test test/screens/library_screen_test.dart --plain-name "遠端書庫"`
預期：`PASS`（`library_screen_test.dart:3338-3390` 附近「提供 remoteServerRepository/opdsClient 時，AppBar 顯示遠端書庫按鈕，點擊後導向 RemoteServerListScreen」等案例；這些測試只用 `find.byType(RemoteServerListScreen)` 檢查畫面是否成功推入，不直接檢查 `RemoteServerListScreen` 內部欄位值，`LibraryScreen` 自身建構子未變動，預期零回歸、不需修改測試程式碼本身）。

- [ ] **Step 9：Commit**

```bash
git add app/lib/screens/remote_server_list_screen.dart app/lib/screens/library_screen.dart app/test/screens/remote_server_list_screen_test.dart
git commit -m "refactor(epic-26): Issue 6 Task 3——RemoteServerListScreen 改用 RemoteCatalogDependencies bundle"
```

---

### Task 4：全專案最終驗證

**Files:**
- 無新增/修改檔案，純驗證。

- [ ] **Step 1：全域殘留掃描，確認舊的三參數呼叫模式已無殘留**

執行：
```bash
cd app
grep -rn "thumbnailCache: widget\.thumbnailCache\b" lib/
grep -rn "createOpdsClient: widget\.createOpdsClient\b" lib/screens/remote_catalog_screen.dart lib/screens/remote_server_list_screen.dart
```
預期：兩者皆無輸出（`lib/screens/library_screen.dart`／`lib/main.dart`／`lib/screens/cloud_browser_screen.dart`／`lib/screens/cloud_download_queue_dialog.dart` 仍會出現 `widget.computeFingerprint`／`widget.thumbnailCache`／`widget.createOpdsClient` 的其他既有引用——這些檔案刻意不在本 Issue 範圍內，見計畫開頭「規劃階段查證」，出現屬於預期行為，不是殘留）。

- [ ] **Step 2：執行 `flutter analyze`**

執行：`cd app && flutter analyze`
預期：`No issues found!`（確認 Task 2/3 Step 中提到「依實際結果決定是否移除的 import」皆已正確處理，無 `unused_import` 或其他警告）。

- [ ] **Step 3：執行全專案測試**

執行：`cd app && flutter test`
預期：全數通過，零回歸（相較 Issue 5 合併後的基準數字，本 Issue 新增 2 項測試——Task 1 的 bundle 持有值測試、Task 2 Step 10 的自我遞迴回歸測試——其餘為既有測試的等價重寫，總數應為「基準 + 2」）。

- [ ] **Step 4：逐項核對驗收標準**

- [ ] `RemoteCatalogDependencies` 已建立，`RemoteServerListScreen`／`RemoteCatalogScreen`（含自我遞迴 `_openSubsection()`）皆已改用單一 `dependencies` 參數取代原本 3 個獨立具名參數。
- [ ] `LibraryScreen`／`main.dart`／`CloudBrowserScreen`／`CloudDownloadQueueDialog` 的欄位與行為完全未變動（純粹是這兩個畫面內部呼叫 `RemoteServerListScreen`／`RemoteCatalogScreen` 建構子時，多做一次 bundle 組裝）。
- [ ] `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。
- [ ] `RemoteServerFormScreen` 的既有介面（`createOpdsClient` 獨立參數）未受影響。
