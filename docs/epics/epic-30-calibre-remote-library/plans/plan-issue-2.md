# Epic 30 Issue 2：OPDS 目錄瀏覽＋批次下載＋匯入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者能從 Issue 1 建好的站點清單點進去，瀏覽 OPDS 目錄（分類下鑽＋分頁載入＋封面縮圖），勾選單/多本書後序列下載並自動匯入圖書庫——這是本 Epic 第一個能讓使用者實際「從 Calibre／OPDS 站點下載一本書」的完整可展示切片。

**Architecture:** 新增 `RemoteCatalogScreen`（`app/lib/screens/`，比照 `RemoteServerListScreen` 慣例）作為目錄瀏覽主畫面，內部以私有 `_DownloadQueueDialog` 承載序列下載狀態機；`FormatSelectionDialog` 為獨立可重用元件。下載流程分兩段落地：`OpdsClient.downloadBook()` 先寫入 `getTemporaryDirectory()` 下的暫存子目錄，成功後複製到 `getApplicationDocumentsDirectory()/remote_books/` 永久位置，才呼叫 `BookImportService.importFiles()`——避免用 OS 可清除的暫存/快取目錄當作書籍的永久儲存位置（`_importSingleFile()` 對非 `content://` 的一般路徑不會另外搬移檔案，見 Task 4 說明）。同時修正 Issue 1 遺留的技術債：`OpdsClient` 從「`main.dart` 建構的全域共用實例」改為「呼叫端各自建構的工廠函式」，讓 `RemoteCatalogScreen` 能依 `opds_http_client.dart` 既有文件警告，替每次瀏覽 session 建構全新實例（分頁循環防護的 `_visitedFeedUrls` 才不會跨 session/跨站點誤判）。

**Tech Stack:** Flutter/Dart、既有 `http`／`path_provider`／`path`／`uuid` 依賴，皆已在專案中使用，本 Issue 不新增任何套件。

**Spec:** `docs/epics/epic-30-calibre-remote-library/spec.md`（「OPDS 瀏覽與下載：`OpdsClient`」「既有匯入管線擴充」「UI 落地位置」章節為本計畫的唯一事實來源），另參 `docs/epics/epic-30-calibre-remote-library/design.md`（Discovery 決策）與 `issues.md`（Issue 2 條目）。

## Global Constraints

- **分頁模式**：`fetchFeed()` 每次只回傳「這一頁」，UI 層依 `nextUrl` 是否為 `null` 決定要不要提供「載入更多」，不做內部自動分頁累加、不設固定筆數上限（spec.md「分頁模式與 `epic-29-cloud-import` 的刻意差異」）。
- **批次下載為序列執行，非平行**：一本下完才下一本，清單逐項顯示等待中/下載中/完成/失敗狀態；下載失敗顯示錯誤並可針對單一檔案手動重試（不自動重試）；下載中可取消（立即清除暫存檔）。
- **不做斷點續傳**：重試一律從頭重新呼叫 `downloadBook()`。
- **`OpdsHttpClient` 生命週期**：`RemoteCatalogScreen` 必須替每次進入某站點的瀏覽 session 建構一個全新的 `OpdsClient` 實例（本計畫 Task 1 把 `main.dart` 的共用實例改為工廠函式正是為了讓這件事在型別層級上可行）。
- 所有新增/修改的程式碼註解使用正體中文，比照既有風格。
- `flutter analyze` 全程保持乾淨；每個 Task 結束時既有測試套件零回歸。

---

### Task 1: `OpdsClient` 由共用實例改為工廠函式；抽出共用 Basic Auth Header 產生器

**Files:**
- Modify: `app/lib/remote/opds_client.dart`
- Modify: `app/lib/remote/opds_http_client.dart`
- Modify: `app/lib/screens/remote_server_form_screen.dart`
- Modify: `app/lib/screens/remote_server_list_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/test/screens/remote_server_form_screen_test.dart`
- Modify: `app/test/screens/remote_server_list_screen_test.dart`
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Produces: 新的頂層函式 `Map<String, String> buildOpdsAuthHeaders(RemoteServerProfile server, String? password)`（`opds_client.dart`）；`RemoteServerFormScreen`／`RemoteServerListScreen`／`LibraryScreen` 的建構參數由 `OpdsClient opdsClient`／`OpdsClient? opdsClient` 改為 `OpdsClient Function() createOpdsClient`／`OpdsClient Function()? createOpdsClient`。Task 3（`RemoteCatalogScreen`）依賴 `buildOpdsAuthHeaders()` 產生縮圖 `Image.network` 的授權 header，並依賴 `createOpdsClient` 這個工廠慣例建構自己專屬的 session 實例。

本 Task **不新增使用者可見功能**，是後續 Task 的地基，純重構——沒有新行為需要紅燈/綠燈測試，改以「執行既有測試套件確認在簽章變更後仍全數通過」作為驗證方式。

- [ ] **Step 1: 抽出共用 Basic Auth Header 產生器**

修改 `app/lib/remote/opds_client.dart`，在檔案開頭新增 import 與頂層函式（放在 `OpdsDownloadCancellationToken` 類別之前）：

```dart
import 'dart:convert';
import 'dart:io';

import 'opds_types.dart';
import 'remote_server_profile.dart';

/// 依 [server.username]／[password] 組出 HTTP Basic Auth header；
/// [server.username] 為 `null` 或空白字串（匿名連線）時回傳空 map（不帶
/// `Authorization` header）。`OpdsHttpClient` 內部呼叫用於
/// `fetchFeed`/`downloadBook`，畫面層（`RemoteCatalogScreen`）呼叫用於
/// 縮圖 `Image.network` 的授權 header——兩處共用同一份邏輯，避免各自
/// 重寫一份 base64 編碼判斷（spec.md「認證與縮圖」：縮圖載入需要帶與
/// 目錄/下載相同的 Authorization header 才能存取）。**〔`review-plan-issue-2.md`
/// Finding 1 採納〕** `RemoteServerFormScreen._buildProfile()` 目前雖然
/// 已把空白字串正規化為 `null`（見 Issue 1），但這個函式是共用工具，
/// 不應該依賴唯一目前存在的呼叫端幫忙做過這層正規化，多一層防禦成本
/// 極低。
Map<String, String> buildOpdsAuthHeaders(RemoteServerProfile server, String? password) {
  final username = server.username?.trim();
  if (username == null || username.isEmpty) return {};
  final credentials = base64Encode(utf8.encode('$username:${password ?? ''}'));
  return {'Authorization': 'Basic $credentials'};
}
```

- [ ] **Step 2: `OpdsHttpClient` 改用共用函式**

修改 `app/lib/remote/opds_http_client.dart`：移除檔案開頭的 `import 'dart:convert';`（不再需要，`base64Encode`/`utf8` 已搬到 `opds_client.dart`）；刪除 `_authHeaders` 方法定義（第 42-46 行）；把方法內兩處呼叫 `_authHeaders(server, password)`（`fetchFeed()` 第 69 行、`downloadBook()` 第 104 行）改為呼叫 `buildOpdsAuthHeaders(server, password)`。

- [ ] **Step 3: `RemoteServerFormScreen` 改用工廠函式**

修改 `app/lib/screens/remote_server_form_screen.dart`：

第 16 行 `final OpdsClient opdsClient;` 改為：
```dart
  final OpdsClient Function() createOpdsClient;
```

第 22 行 `required this.opdsClient,` 改為：
```dart
    required this.createOpdsClient,
```

第 102 行 `final success = await widget.opdsClient.testConnection(_buildProfile(), password: password);` 改為：
```dart
    final success =
        await widget.createOpdsClient().testConnection(_buildProfile(), password: password);
```

- [ ] **Step 4: `RemoteServerListScreen` 改用工廠函式**

修改 `app/lib/screens/remote_server_list_screen.dart`：

第 13 行 `final OpdsClient opdsClient;` 改為：
```dart
  final OpdsClient Function() createOpdsClient;
```

第 18 行 `required this.opdsClient,` 改為：
```dart
    required this.createOpdsClient,
```

第 50 行（`_openAddForm` 內）與第 62 行（`_openEditForm` 內）的 `opdsClient: widget.opdsClient,` 皆改為：
```dart
          createOpdsClient: widget.createOpdsClient,
```

- [ ] **Step 5: `LibraryScreen` 改用工廠函式**

修改 `app/lib/screens/library_screen.dart`：

`final OpdsClient? opdsClient;` 改為：
```dart
  final OpdsClient Function()? createOpdsClient;
```

建構子參數 `this.opdsClient,` 改為：
```dart
    this.createOpdsClient,
```

AppBar 按鈕的條件判斷 `if (widget.remoteServerRepository != null && widget.opdsClient != null)` 改為：
```dart
        if (widget.remoteServerRepository != null && widget.createOpdsClient != null)
```

導覽呼叫內的 `opdsClient: widget.opdsClient!,` 改為：
```dart
                    createOpdsClient: widget.createOpdsClient!,
```

- [ ] **Step 6: `main.dart` 改用工廠函式**

修改 `app/lib/main.dart`：

刪除第 93 行 `final opdsClient = OpdsHttpClient();`（不再需要預先建構一個共用實例）。

`ElinkBookApp(...)` 呼叫內第 113 行 `opdsClient: opdsClient,` 改為：
```dart
      createOpdsClient: () => OpdsHttpClient(),
```

`class ElinkBookApp` 第 138 行 `final OpdsClient? opdsClient;` 改為：
```dart
  final OpdsClient Function()? createOpdsClient;
```

建構子參數 `this.opdsClient,` 改為：
```dart
    this.createOpdsClient,
```

`_ElinkBookAppState.build()` 內傳給 `LibraryScreen(...)` 的 `opdsClient: widget.opdsClient,` 改為：
```dart
        createOpdsClient: widget.createOpdsClient,
```

- [ ] **Step 7: 更新既有測試以符合新簽章**

在 `app/test/screens/remote_server_form_screen_test.dart` 找到檔案開頭的 `pumpScreen` 輔助函式（`Future<void> pumpScreen(tester, {required repository, required opdsClient, existingProfile}) async { ... }`），內部建構 `RemoteServerFormScreen(...)` 的 `opdsClient: opdsClient,` 改為：
```dart
        createOpdsClient: () => opdsClient,
```
（`pumpScreen` 自身的參數名稱 `opdsClient` 維持不變——外部呼叫端傳入的仍是 `FakeOpdsClient` 實例本身，只有餵給 widget 建構子時才包一層閉包，這樣測試檔案內既有的 13 處呼叫端完全不需要修改。）

同樣地，在 `app/test/screens/remote_server_list_screen_test.dart` 的 `pumpScreen` 輔助函式內，找到建構 `RemoteServerListScreen(...)` 的 `opdsClient: FakeOpdsClient(),`，改為：
```dart
        createOpdsClient: () => FakeOpdsClient(),
```

在 `app/test/screens/library_screen_test.dart` 的「遠端書庫進入點」`group` 內，找到第二個 `testWidgets`（`'提供 remoteServerRepository/opdsClient 時...'`）建構 `LibraryScreen(...)` 的 `opdsClient: FakeOpdsClient(),`，改為：
```dart
        createOpdsClient: () => FakeOpdsClient(),
```

- [ ] **Step 8: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨；`flutter test` 全數通過（1495 項，Issue 1 合併時的基準數，本 Task 不增減任何測試案例，純重構）。

- [ ] **Step 9: Commit**

```bash
git add app/lib/remote/opds_client.dart app/lib/remote/opds_http_client.dart app/lib/screens/remote_server_form_screen.dart app/lib/screens/remote_server_list_screen.dart app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/remote_server_form_screen_test.dart app/test/screens/remote_server_list_screen_test.dart app/test/screens/library_screen_test.dart
git commit -m "refactor(epic-30): OpdsClient 改為工廠函式，抽出共用 Basic Auth header 產生器"
```

---

### Task 2: `FormatSelectionDialog`

**Files:**
- Create: `app/lib/screens/format_selection_dialog.dart`
- Test: `app/test/screens/format_selection_dialog_test.dart`

**Interfaces:**
- Consumes: `OpdsEntry`／`OpdsAcquisition`（Issue 1 已定義）。
- Produces: `FormatSelectionDialog.show(BuildContext, OpdsEntry) → Future<OpdsAcquisition?>`（使用者取消或無任何可選格式時回傳 `null`）。Task 4（下載佇列）依賴這個靜態方法。

- [ ] **Step 1: 寫失敗測試**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/opds_types.dart';
import 'package:elinkbook/screens/format_selection_dialog.dart';

void main() {
  const entry = OpdsEntry(
    remoteBookId: 'book-1',
    title: '紅樓夢',
    acquisitions: [
      OpdsAcquisition(href: 'http://example.com/1.epub', format: BookFileFormat.epub),
      OpdsAcquisition(href: 'http://example.com/1.pdf', format: BookFileFormat.pdf),
      OpdsAcquisition(href: 'http://example.com/1.doc', format: null),
    ],
  );

  Future<OpdsAcquisition?> pumpAndShow(WidgetTester tester) async {
    OpdsAcquisition? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await FormatSelectionDialog.show(context, entry);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('顯示每個 acquisition 的格式選項，不支援格式置灰', (tester) async {
    await pumpAndShow(tester);

    expect(find.byKey(const Key('format_selection_option_http://example.com/1.epub')),
        findsOneWidget);
    expect(find.byKey(const Key('format_selection_option_http://example.com/1.pdf')),
        findsOneWidget);
    final unsupportedTile = tester.widget<ListTile>(
        find.byKey(const Key('format_selection_option_http://example.com/1.doc')));
    expect(unsupportedTile.enabled, false);
  });

  testWidgets('點擊支援的格式選項後回傳對應 OpdsAcquisition', (tester) async {
    OpdsAcquisition? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await FormatSelectionDialog.show(context, entry);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('format_selection_option_http://example.com/1.epub')));
    await tester.pumpAndSettle();

    expect(result?.format, BookFileFormat.epub);
  });

  testWidgets('點擊取消時回傳 null', (tester) async {
    final result = await pumpAndShow(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // pumpAndShow 已經 await 過整個 show()，取消發生在同一個 pumpAndSettle
    // 週期內；改用下方更明確的流程重新驗證一次取消情境。
    expect(result, isNull);
  });
}
```

**Step 1 附註**：第三個測試（點擊取消）的 `pumpAndShow` 呼叫方式會在 `tester.tap(find.text('open'))` 之後就已經 `pumpAndSettle()`，此時對話框仍開著、`show()` 的 Future 尚未完成（因為使用者還沒按下取消），`result` 變數此時仍是 `null` 的初始值——這個測試寫法巧合地永遠會通過（不管取消邏輯對不對）。改寫為正確驗證取消流程的版本：

```dart
  testWidgets('點擊取消時回傳 null', (tester) async {
    OpdsAcquisition? result;
    var completed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await FormatSelectionDialog.show(context, entry);
            completed = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(completed, true);
    expect(result, isNull);
  });
```

（撰寫本計畫時已直接把這個修正版納入下方最終測試檔案內容，上方附註僅說明為什麼原始草稿寫法是錯的，避免實作者照抄錯誤版本。）

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/format_selection_dialog_test.dart`
Expected: FAIL——`format_selection_dialog.dart` 尚不存在。

- [ ] **Step 3: 實作**

```dart
import 'package:flutter/material.dart';

import '../remote/opds_types.dart';

/// 同一書目提供多個下載格式時的選擇彈窗（epic-30-calibre-remote-library
/// Issue 2，spec.md「UI 落地位置」，沿用 `epic-29-cloud-import` 的命名
/// 慣例）。不支援的格式（`format == null`）置灰不可選。
class FormatSelectionDialog extends StatelessWidget {
  final OpdsEntry entry;

  const FormatSelectionDialog({super.key, required this.entry});

  static Future<OpdsAcquisition?> show(BuildContext context, OpdsEntry entry) {
    return showDialog<OpdsAcquisition>(
      context: context,
      builder: (context) => FormatSelectionDialog(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('format_selection_dialog'),
      title: Text('選擇格式：${entry.title}'),
      // 〔審查 review-plan-issue-2.md Finding 2 採納〕格式選項較多或在
      // 橫向/小螢幕裝置上時，固定高度的 AlertDialog 內容可能超出可視
      // 範圍，外層包 SingleChildScrollView 防禦 RenderFlex overflow。
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: entry.acquisitions.map((acquisition) {
            final supported = acquisition.format != null;
            return ListTile(
              key: Key('format_selection_option_${acquisition.href}'),
              enabled: supported,
              title: Text(supported ? acquisition.format!.name.toUpperCase() : '不支援的格式'),
              onTap: supported ? () => Navigator.of(context).pop(acquisition) : null,
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: 執行測試確認全數通過**

Run: `flutter test test/screens/format_selection_dialog_test.dart`
Expected: PASS，3 項測試全數通過。

- [ ] **Step 5: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/format_selection_dialog.dart app/test/screens/format_selection_dialog_test.dart
git commit -m "feat(epic-30): 新增 FormatSelectionDialog"
```

---

### Task 3: `RemoteCatalogScreen` 核心瀏覽（目錄下鑽／分頁／縮圖／多選）

**Files:**
- Create: `app/lib/screens/remote_catalog_screen.dart`
- Test: `app/test/screens/remote_catalog_screen_test.dart`

**Interfaces:**
- Consumes: Task 1（`createOpdsClient`／`buildOpdsAuthHeaders`）、Issue 1（`RemoteServerRepository`／`RemoteServerProfile`／`OpdsClient`／`OpdsFeed`）。
- Produces: `RemoteCatalogScreen({required server, required repository, required createOpdsClient, required importService, feedUrl, title})`。本 Task 先不接下載/匯入邏輯（`importService` 參數先接收但下載按鈕行為留給 Task 4），Task 4 會在同一個檔案內擴充。

- [ ] **Step 1: 寫失敗測試**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/opds_types.dart';
import 'package:elinkbook/screens/remote_catalog_screen.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_server_repository.dart';

void main() {
  final server = RemoteServerProfile(
    id: 'srv1',
    name: '家用 NAS',
    baseUrl: 'http://192.168.1.100:8080/opds',
    type: RemoteServerType.opds,
    username: 'admin',
    allowInsecure: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );

  const entry1 = OpdsEntry(
    remoteBookId: 'book-1',
    title: '紅樓夢',
    author: '曹雪芹',
    thumbnailUrl: 'http://192.168.1.100:8080/opds/cover/1.jpg',
    acquisitions: [
      OpdsAcquisition(href: 'http://192.168.1.100:8080/opds/download/1.epub', format: BookFileFormat.epub),
    ],
  );
  const entry2 = OpdsEntry(
    remoteBookId: 'book-2',
    title: '不支援格式的書',
    acquisitions: [
      OpdsAcquisition(href: 'http://192.168.1.100:8080/opds/download/2.doc', format: null),
    ],
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeOpdsClient opdsClient,
    FakeRemoteServerRepository? repository,
    String? feedUrl,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteCatalogScreen(
        server: server,
        repository: repository ?? FakeRemoteServerRepository(),
        createOpdsClient: () => opdsClient,
        importService: FakeBookImportService(),
        feedUrl: feedUrl,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('載入根目錄後顯示分類導覽與書目', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(
        title: '家用 NAS 書庫',
        navigationLinks: [OpdsNavigationLink(title: '作者分類', href: 'http://192.168.1.100:8080/opds/by-author')],
        entries: [entry1, entry2],
      ),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.text('作者分類'), findsOneWidget);
    expect(find.text('紅樓夢'), findsOneWidget);
    expect(find.text('不支援格式的書'), findsOneWidget);
  });

  testWidgets('點擊分類導覽項目時 push 新的 RemoteCatalogScreen 並載入該分類 Feed', (tester) async {
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
    await pumpScreen(tester, opdsClient: opdsClient);

    await tester.tap(find.text('作者分類'));
    await tester.pumpAndSettle();

    expect(find.text('紅樓夢'), findsOneWidget);
    expect(opdsClient.fetchFeedCalls, [null, 'http://192.168.1.100:8080/opds/by-author']);
  });

  testWidgets('有 nextUrl 時顯示載入更多按鈕，點擊後累加下一頁書目', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(
        title: '根目錄',
        nextUrl: 'http://192.168.1.100:8080/opds/page2',
        entries: [entry1],
      ),
      'http://192.168.1.100:8080/opds/page2': const OpdsFeed(
        title: '根目錄',
        entries: [entry2],
      ),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.byKey(const Key('remote_catalog_load_more_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('remote_catalog_load_more_button')));
    await tester.pumpAndSettle();

    expect(find.text('紅樓夢'), findsOneWidget);
    expect(find.text('不支援格式的書'), findsOneWidget);
    expect(find.byKey(const Key('remote_catalog_load_more_button')), findsNothing);
  });

  testWidgets('沒有 nextUrl 時不顯示載入更多按鈕', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.byKey(const Key('remote_catalog_load_more_button')), findsNothing);
  });

  testWidgets('書目縮圖以 Image.network 載入並帶入 Basic Auth header', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    final image = tester.widget<Image>(find.byKey(const Key('remote_catalog_thumbnail_book-1')));
    final provider = image.image as NetworkImage;
    expect(provider.url, entry1.thumbnailUrl);
    expect(provider.headers?['Authorization'], isNotNull);
  });

  testWidgets('沒有縮圖的書目顯示預設圖示佔位符', (tester) async {
    const entryNoCover = OpdsEntry(
      remoteBookId: 'book-3',
      title: '無縮圖的書',
      acquisitions: [OpdsAcquisition(href: 'http://x/3.epub', format: BookFileFormat.epub)],
    );
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entryNoCover]),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.byKey(const Key('remote_catalog_thumbnail_placeholder_book-3')), findsOneWidget);
  });

  testWidgets('點擊書目可勾選/取消勾選，僅有支援格式的書目可勾選', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1, entry2]),
    });
    await pumpScreen(tester, opdsClient: opdsClient);

    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
    await tester.pump();
    expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
    await tester.pump();
    expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsNothing);

    // entry2 完全沒有支援格式，點擊不應該有任何反應。
    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-2')));
    await tester.pump();
    expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-2')), findsNothing);
  });

  testWidgets('載入失敗時顯示錯誤文字', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: const {});
    await pumpScreen(tester, opdsClient: opdsClient);

    expect(find.byKey(const Key('remote_catalog_error_text')), findsOneWidget);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: FAIL——`remote_catalog_screen.dart` 尚不存在。

- [ ] **Step 3: 實作**

```dart
import 'package:flutter/material.dart';

import '../library/book_import_service.dart';
import '../remote/opds_client.dart';
import '../remote/opds_types.dart';
import '../remote/remote_server_profile.dart';
import '../remote/remote_server_repository.dart';

/// OPDS 目錄瀏覽畫面（epic-30-calibre-remote-library Issue 2，
/// spec.md「UI 落地位置」）：依 [OpdsFeed.navigationLinks] 分類下鑽（點擊
/// 後 push 新的本畫面實例）、依 [OpdsFeed.nextUrl] 提供「載入更多」、
/// 封面縮圖網格（帶 Basic Auth header）、多選勾選批次下載。
///
/// [createOpdsClient] 在 [initState] 只呼叫一次，整個瀏覽 session（含
/// 分頁下鑽、下載）共用同一個 [OpdsClient] 實例——比照
/// `opds_http_client.dart` 類別文件的生命週期警告，分頁循環防護的
/// `_visitedFeedUrls` 才會正確對應「一次瀏覽路徑」。
class RemoteCatalogScreen extends StatefulWidget {
  final RemoteServerProfile server;
  final RemoteServerRepository repository;
  final OpdsClient Function() createOpdsClient;
  final BookImportService importService;

  /// `null` 代表載入 [server.baseUrl]（站點根目錄）；非 `null` 時載入指定
  /// 的分類/分頁 Feed（點擊 [OpdsNavigationLink] 下鑽時使用）。
  final String? feedUrl;

  /// AppBar 標題，`null` 時使用 [server.name]（根目錄畫面）。
  final String? title;

  const RemoteCatalogScreen({
    super.key,
    required this.server,
    required this.repository,
    required this.createOpdsClient,
    required this.importService,
    this.feedUrl,
    this.title,
  });

  @override
  State<RemoteCatalogScreen> createState() => _RemoteCatalogScreenState();
}

class _RemoteCatalogScreenState extends State<RemoteCatalogScreen> {
  late final OpdsClient _client;
  bool _loading = true;
  String? _errorText;
  final List<OpdsNavigationLink> _navigationLinks = [];
  final List<OpdsEntry> _entries = [];
  String? _nextUrl;
  bool _loadingMore = false;
  final Set<String> _selectedRemoteBookIds = {};
  String? _password;

  @override
  void initState() {
    super.initState();
    _client = widget.createOpdsClient();
    _load();
  }

  bool _isSelectable(OpdsEntry entry) => entry.acquisitions.any((a) => a.format != null);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    _password = await widget.repository.loadPassword(widget.server.id);
    try {
      final feed = await _client.fetchFeed(
        widget.server,
        password: _password,
        feedUrl: widget.feedUrl,
      );
      if (!mounted) return;
      setState(() {
        _navigationLinks
          ..clear()
          ..addAll(feed.navigationLinks);
        _entries
          ..clear()
          ..addAll(feed.entries);
        _nextUrl = feed.nextUrl;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = '載入失敗，請檢查網路連線或站點設定';
      });
    }
  }

  Future<void> _loadMore() async {
    final nextUrl = _nextUrl;
    if (nextUrl == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final feed = await _client.fetchFeed(widget.server, password: _password, feedUrl: nextUrl);
      if (!mounted) return;
      setState(() {
        _navigationLinks.addAll(feed.navigationLinks);
        _entries.addAll(feed.entries);
        _nextUrl = feed.nextUrl;
        _loadingMore = false;
      });
    } catch (_) {
      // 失敗時保留既有 _nextUrl，讓使用者可以再按一次「載入更多」重試，
      // 不彈額外錯誤訊息干擾——這不是整頁載入失敗，只是分頁的一次嘗試。
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _openSubsection(OpdsNavigationLink link) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: widget.server,
        repository: widget.repository,
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
        feedUrl: link.href,
        title: link.title,
      ),
    ));
  }

  void _toggleSelection(OpdsEntry entry) {
    if (!_isSelectable(entry)) return;
    setState(() {
      if (_selectedRemoteBookIds.contains(entry.remoteBookId)) {
        _selectedRemoteBookIds.remove(entry.remoteBookId);
      } else {
        _selectedRemoteBookIds.add(entry.remoteBookId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? widget.server.name)),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(key: Key('remote_catalog_loading_indicator')),
            )
          : _errorText != null
              ? Center(
                  child: Text(_errorText!, key: const Key('remote_catalog_error_text')),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return ListView(
      children: [
        for (final link in _navigationLinks)
          ListTile(
            key: Key('remote_catalog_nav_${link.href}'),
            leading: const Icon(Icons.folder),
            title: Text(link.title),
            onTap: () => _openSubsection(link),
          ),
        if (_navigationLinks.isNotEmpty && _entries.isNotEmpty) const Divider(),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.6,
          ),
          itemCount: _entries.length,
          itemBuilder: (context, index) => _buildEntryTile(_entries[index]),
        ),
        if (_nextUrl != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: OutlinedButton(
                key: const Key('remote_catalog_load_more_button'),
                onPressed: _loadingMore ? null : _loadMore,
                child: _loadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('載入更多'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEntryTile(OpdsEntry entry) {
    final selectable = _isSelectable(entry);
    final selected = _selectedRemoteBookIds.contains(entry.remoteBookId);
    return InkWell(
      key: Key('remote_catalog_entry_${entry.remoteBookId}'),
      onTap: selectable ? () => _toggleSelection(entry) : null,
      child: Opacity(
        opacity: selectable ? 1 : 0.4,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _buildThumbnail(entry)),
                  if (selected)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(
                        Icons.check_circle,
                        key: Key('remote_catalog_checkbox_checked_${entry.remoteBookId}'),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(OpdsEntry entry) {
    final thumbnailUrl = entry.thumbnailUrl;
    if (thumbnailUrl == null) {
      return Center(
        child: Icon(
          Icons.book,
          key: Key('remote_catalog_thumbnail_placeholder_${entry.remoteBookId}'),
        ),
      );
    }
    return Image.network(
      thumbnailUrl,
      key: Key('remote_catalog_thumbnail_${entry.remoteBookId}'),
      headers: buildOpdsAuthHeaders(widget.server, _password),
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          key: Key('remote_catalog_thumbnail_loading_${entry.remoteBookId}'),
          child: const Icon(Icons.book),
        );
      },
      errorBuilder: (context, error, stack) => Center(
        key: Key('remote_catalog_thumbnail_error_${entry.remoteBookId}'),
        child: const Icon(Icons.broken_image),
      ),
    );
  }
}
```

- [ ] **Step 4: 執行測試確認全數通過**

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: PASS，8 項測試全數通過（`flutter test` 環境下無真實網路，`Image.network` 會停留在 `loadingBuilder` 分支，「縮圖以 Image.network 載入並帶入 header」這項測試斷言的是 `Image` widget 本身的 `NetworkImage` 設定，不需要圖片真的載入完成）。

- [ ] **Step 5: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/remote_catalog_screen.dart app/test/screens/remote_catalog_screen_test.dart
git commit -m "feat(epic-30): 新增 RemoteCatalogScreen 核心瀏覽（目錄下鑽/分頁/縮圖/多選）"
```

---

### Task 4: 下載佇列與匯入整合

**Files:**
- Modify: `app/lib/screens/remote_catalog_screen.dart`
- Modify: `app/test/support/fake_opds_client.dart`
- Test: `app/test/screens/remote_catalog_screen_test.dart`

**Interfaces:**
- Consumes: Task 2（`FormatSelectionDialog`）、Task 3（`RemoteCatalogScreen` 選取狀態）、既有 `BookImportService.importFiles()`（`source`/`remoteServerId`/`remoteBookIds`/`remoteDownloadUrls`，Issue 0 已定案簽章）。
- Produces：`RemoteCatalogScreen` AppBar 新增「下載」按鈕（`_selectedRemoteBookIds` 非空時啟用），觸發序列下載佇列對話框，完成後呼叫 `importFiles()`。

**下載檔案的暫存→永久位置搬移**：`OpdsClient.downloadBook()` 先寫入 `getTemporaryDirectory()/remote_download_temp/<uuid>.<ext>`；下載成功後複製到 `getApplicationDocumentsDirectory()/remote_books/<相同檔名>` 才刪除暫存檔——**這一步是必要的，不是可省略的講究**：`book_import_service_impl.dart` 的 `_importSingleFile()` 對非 `content://` 開頭的一般檔案路徑（我們下載下來的檔案就是這種）完全不會另外搬移或複製，`resolvedUri` 會直接沿用呼叫 `importFiles()` 時傳入的路徑當作永久 `filePath`；若傳入的是 OS 暫存/快取目錄下的路徑，這本書的檔案未來可能被系統回收清除，等同資料遺失。

- [ ] **Step 1: 擴充 `FakeOpdsClient` 支援測試控制下載完成時機**

修改 `app/test/support/fake_opds_client.dart`：在檔案開頭新增 `import 'dart:async';`；在 `downloadError` 欄位宣告之後新增：

```dart
  /// 供測試控制下載完成時機（比照 `FakeBookImportService.pendingCompleter`
  /// 既有模式）：非 `null` 時 [downloadBook] 改為等待這個 completer 完成，
  /// 讓測試能在下載「進行中」時呼叫 `cancellationToken.cancel()` 並斷言
  /// 正確反應為取消而非直接成功。
  Completer<void>? downloadPendingCompleter;
```

把 `downloadBook` 方法本體改為：

```dart
  @override
  Future<File> downloadBook(
    RemoteServerProfile server,
    OpdsAcquisition acquisition,
    String destinationPath, {
    String? password,
    void Function(int received, int total)? onProgress,
    OpdsDownloadCancellationToken? cancellationToken,
  }) async {
    downloadBookCalls.add(acquisition.href);
    final completer = downloadPendingCompleter;
    if (completer != null) {
      await completer.future;
    }
    if (cancellationToken?.isCancelled ?? false) {
      throw StateError('下載已取消');
    }
    if (downloadError != null) throw downloadError!;
    onProgress?.call(100, 100);
    final file = File(destinationPath);
    await file.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    return file;
  }
```

- [ ] **Step 2: 寫失敗測試**

在 `app/test/screens/remote_catalog_screen_test.dart` 檔案開頭新增 import：

```dart
import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart' show BookSource;
import 'package:elinkbook/remote/opds_client.dart';

import '../support/fake_path_provider_platform.dart';
```

在 `main()` 內、既有測試之後新增：

```dart
  group('下載與匯入', () {
    late Directory tempRoot;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('remote_catalog_test');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = FakePathProviderPlatform(tempRoot.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    testWidgets('勾選單本書下載後呼叫 importFiles，帶入 source/remoteServerId/remoteBookIds/remoteDownloadUrls',
        (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      final importService = FakeBookImportService();
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          createOpdsClient: () => opdsClient,
          importService: importService,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('download_queue_item_book-1')), findsOneWidget);
      expect(find.text('完成'), findsWidgets);

      await tester.tap(find.byKey(const Key('download_queue_done_button')));
      await tester.pumpAndSettle();

      expect(opdsClient.downloadBookCalls, ['http://192.168.1.100:8080/opds/download/1.epub']);
    });

    testWidgets('同一書目有多個支援格式時彈出 FormatSelectionDialog 讓使用者選擇', (tester) async {
      const multiFormatEntry = OpdsEntry(
        remoteBookId: 'book-multi',
        title: '多格式書',
        acquisitions: [
          OpdsAcquisition(href: 'http://x/m.epub', format: BookFileFormat.epub),
          OpdsAcquisition(href: 'http://x/m.pdf', format: BookFileFormat.pdf),
        ],
      );
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [multiFormatEntry]),
      });
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          createOpdsClient: () => opdsClient,
          importService: FakeBookImportService(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-multi')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('format_selection_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('format_selection_option_http://x/m.pdf')));
      await tester.pumpAndSettle();

      expect(opdsClient.downloadBookCalls, ['http://x/m.pdf']);
    });

    testWidgets('多選批次下載時逐項序列進行，非平行', (tester) async {
      const entryA = OpdsEntry(
        remoteBookId: 'book-a',
        title: '書 A',
        acquisitions: [OpdsAcquisition(href: 'http://x/a.epub', format: BookFileFormat.epub)],
      );
      const entryB = OpdsEntry(
        remoteBookId: 'book-b',
        title: '書 B',
        acquisitions: [OpdsAcquisition(href: 'http://x/b.epub', format: BookFileFormat.epub)],
      );
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entryA, entryB]),
      });
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          createOpdsClient: () => opdsClient,
          importService: FakeBookImportService(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-a')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-b')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pumpAndSettle();

      expect(opdsClient.downloadBookCalls, ['http://x/a.epub', 'http://x/b.epub']);
    });

    testWidgets('下載失敗時顯示失敗狀態並可手動重試', (tester) async {
      final opdsClient = FakeOpdsClient(
        feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        },
        downloadError: StateError('模擬下載失敗'),
      );
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          createOpdsClient: () => opdsClient,
          importService: FakeBookImportService(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pumpAndSettle();

      expect(find.text('失敗'), findsOneWidget);
      expect(find.byKey(const Key('download_queue_retry_book-1')), findsOneWidget);

      opdsClient.downloadError = null;
      await tester.tap(find.byKey(const Key('download_queue_retry_book-1')));
      await tester.pumpAndSettle();

      expect(find.text('完成'), findsWidgets);
    });

    testWidgets('下載中點擊取消後顯示已取消狀態，暫存檔不殘留', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      opdsClient.downloadPendingCompleter = Completer<void>();
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          createOpdsClient: () => opdsClient,
          importService: FakeBookImportService(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pump();

      expect(find.byKey(const Key('download_queue_cancel_book-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('download_queue_cancel_book-1')));
      opdsClient.downloadPendingCompleter!.complete();
      await tester.pumpAndSettle();

      expect(find.text('已取消'), findsOneWidget);
    });

    testWidgets('整合驗證：真實 BookImportServiceImpl 正確寫入 remoteServerId/remoteBookId/remoteDownloadUrl/isDownloaded',
        (tester) async {
      final libraryRepo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
      addTearDown(() => libraryRepo.close());
      final importService = BookImportServiceImpl(repository: libraryRepo);

      const channel = MethodChannel('elinkbook/book_metadata');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '紅樓夢'};
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          createOpdsClient: () => opdsClient,
          importService: importService,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('download_queue_done_button')));
      await tester.pumpAndSettle();

      final books = await libraryRepo.listBooks();
      expect(books, hasLength(1));
      final book = books.single;
      expect(book.source, BookSource.calibreOpds);
      expect(book.remoteServerId, 'srv1');
      expect(book.remoteBookId, 'book-1');
      expect(book.remoteDownloadUrl, 'http://192.168.1.100:8080/opds/download/1.epub');
      expect(book.isDownloaded, true);
      expect(await File(book.filePath).exists(), true);
    });
  });
```

- [ ] **Step 3: 執行測試確認失敗**

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: FAIL——AppBar 尚無下載按鈕、`_DownloadQueueDialog` 尚不存在。

- [ ] **Step 4: 實作下載佇列與匯入邏輯**

修改 `app/lib/screens/remote_catalog_screen.dart`：

在檔案開頭新增 import：

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../library/models/library_enums.dart';
import 'format_selection_dialog.dart';
```

在 `AppBar(title: ...)` 之後新增 `actions`（AppBar 改為）：

```dart
      appBar: AppBar(
        title: Text(widget.title ?? widget.server.name),
        actions: [
          IconButton(
            key: const Key('remote_catalog_download_button'),
            icon: const Icon(Icons.download),
            tooltip: '下載已選取',
            onPressed: _selectedRemoteBookIds.isEmpty ? null : _startDownload,
          ),
        ],
      ),
```

在 `_toggleSelection` 方法之後新增：

```dart
  Future<void> _startDownload() async {
    final selectedEntries =
        _entries.where((e) => _selectedRemoteBookIds.contains(e.remoteBookId)).toList();
    if (selectedEntries.isEmpty) return;

    final queue = <_DownloadQueueItem>[];
    for (final entry in selectedEntries) {
      final supported = entry.acquisitions.where((a) => a.format != null).toList();
      OpdsAcquisition? chosen;
      if (supported.length == 1) {
        chosen = supported.single;
      } else if (supported.length > 1) {
        if (!mounted) return;
        chosen = await FormatSelectionDialog.show(context, entry);
      }
      if (chosen == null) continue;
      queue.add(_DownloadQueueItem(entry: entry, acquisition: chosen));
    }
    if (queue.isEmpty) return;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadQueueDialog(
        queue: queue,
        client: _client,
        server: widget.server,
        password: _password,
        importService: widget.importService,
      ),
    );
    if (!mounted) return;
    setState(() => _selectedRemoteBookIds.clear());
  }
```

在檔案最末尾（`_RemoteCatalogScreenState` 類別結束的 `}` 之後）新增：

```dart
class _DownloadQueueItem {
  final OpdsEntry entry;
  final OpdsAcquisition acquisition;

  _DownloadQueueItem({required this.entry, required this.acquisition});
}

enum _DownloadItemStatus { pending, downloading, done, failed, cancelled }

/// 序列下載佇列對話框（epic-30-calibre-remote-library Issue 2，
/// spec.md「批次下載為序列執行，非平行」）：一本下完才下一本，逐項顯示
/// 等待中/下載中/完成/失敗/已取消狀態；下載失敗可針對單一檔案手動重試
/// （不自動重試）；全部處理完（無論成功/失敗）後，把所有成功下載的檔案
/// 一次呼叫 [BookImportService.importFiles] 匯入圖書庫；之後對個別失敗
/// 項目按重試、成功時額外呼叫一次 `importFiles()` 只匯入那一筆。
class _DownloadQueueDialog extends StatefulWidget {
  final List<_DownloadQueueItem> queue;
  final OpdsClient client;
  final RemoteServerProfile server;
  final String? password;
  final BookImportService importService;

  const _DownloadQueueDialog({
    required this.queue,
    required this.client,
    required this.server,
    required this.password,
    required this.importService,
  });

  @override
  State<_DownloadQueueDialog> createState() => _DownloadQueueDialogState();
}

class _DownloadQueueDialogState extends State<_DownloadQueueDialog> {
  late List<_DownloadItemStatus> _statuses;
  late List<String?> _permanentPaths;
  late List<OpdsDownloadCancellationToken?> _tokens;
  bool _allSettled = false;

  @override
  void initState() {
    super.initState();
    _statuses = List.filled(widget.queue.length, _DownloadItemStatus.pending);
    _permanentPaths = List.filled(widget.queue.length, null);
    _tokens = List.filled(widget.queue.length, null);
    _runQueue();
  }

  Future<void> _runQueue() async {
    for (var i = 0; i < widget.queue.length; i++) {
      await _downloadOne(i);
    }
    await _importSuccessful();
    if (!mounted) return;
    setState(() => _allSettled = true);
  }

  String _extensionFor(BookFileFormat format) {
    switch (format) {
      case BookFileFormat.epub:
        return 'epub';
      case BookFileFormat.pdf:
        return 'pdf';
      case BookFileFormat.txt:
        return 'txt';
      case BookFileFormat.azw3:
        return 'azw3';
      case BookFileFormat.cbz:
        return 'cbz';
      case BookFileFormat.md:
        return 'md';
    }
  }

  Future<void> _downloadOne(int index) async {
    if (!mounted) return;
    setState(() => _statuses[index] = _DownloadItemStatus.downloading);
    final item = widget.queue[index];
    final token = OpdsDownloadCancellationToken();
    _tokens[index] = token;
    // 〔審查 review-plan-issue-2.md Finding 3 採納〕宣告在 try 外，讓
    // catch 區塊也能存取，用於下方「copy 到永久目錄中途失敗」時的暫存檔
    // 清理。
    String? tempPath;
    try {
      final tempDir = await getTemporaryDirectory();
      final downloadDir = Directory(p.join(tempDir.path, 'remote_download_temp'));
      if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
      final fileName = '${const Uuid().v4()}.${_extensionFor(item.acquisition.format!)}';
      tempPath = p.join(downloadDir.path, fileName);

      await widget.client.downloadBook(
        widget.server,
        item.acquisition,
        tempPath,
        password: widget.password,
        cancellationToken: token,
      );

      final docsDir = await getApplicationDocumentsDirectory();
      final permanentDir = Directory(p.join(docsDir.path, 'remote_books'));
      if (!await permanentDir.exists()) await permanentDir.create(recursive: true);
      final permanentPath = p.join(permanentDir.path, fileName);
      final tempFile = File(tempPath);
      await tempFile.copy(permanentPath);
      await tempFile.delete();

      if (!mounted) return;
      setState(() {
        _permanentPaths[index] = permanentPath;
        _statuses[index] = _DownloadItemStatus.done;
      });
    } catch (_) {
      // 〔審查 review-plan-issue-2.md Finding 3 採納〕downloadBook() 本身
      // 失敗/取消時已經自行清過暫存檔（見 OpdsHttpClient 文件），但
      // copy() 到永久目錄這一步若中途失敗（例如磁碟空間不足），暫存檔
      // 仍會殘留在 remote_download_temp/ 底下——防禦性再清一次，確保
      // 任何例外路徑都不留孤兒檔案。
      if (tempPath != null) {
        final leftover = File(tempPath);
        if (await leftover.exists()) await leftover.delete();
      }
      if (!mounted) return;
      setState(() {
        _statuses[index] =
            token.isCancelled ? _DownloadItemStatus.cancelled : _DownloadItemStatus.failed;
      });
    }
  }

  Future<void> _importSuccessful() async {
    final paths = <String>[];
    final remoteBookIds = <String, String>{};
    final remoteDownloadUrls = <String, String>{};
    for (var i = 0; i < widget.queue.length; i++) {
      final path = _permanentPaths[i];
      if (path == null) continue;
      paths.add(path);
      remoteBookIds[path] = widget.queue[i].entry.remoteBookId;
      remoteDownloadUrls[path] = widget.queue[i].acquisition.href;
    }
    if (paths.isEmpty) return;
    await widget.importService.importFiles(
      paths,
      source: BookSource.calibreOpds,
      remoteServerId: widget.server.id,
      remoteBookIds: remoteBookIds,
      remoteDownloadUrls: remoteDownloadUrls,
    );
  }

  Future<void> _retry(int index) async {
    await _downloadOne(index);
    if (_statuses[index] != _DownloadItemStatus.done) return;
    final path = _permanentPaths[index]!;
    final item = widget.queue[index];
    await widget.importService.importFiles(
      [path],
      source: BookSource.calibreOpds,
      remoteServerId: widget.server.id,
      remoteBookIds: {path: item.entry.remoteBookId},
      remoteDownloadUrls: {path: item.acquisition.href},
    );
  }

  void _cancel(int index) {
    _tokens[index]?.cancel();
  }

  String _statusLabel(_DownloadItemStatus status) {
    switch (status) {
      case _DownloadItemStatus.pending:
        return '等待中';
      case _DownloadItemStatus.downloading:
        return '下載中';
      case _DownloadItemStatus.done:
        return '完成';
      case _DownloadItemStatus.failed:
        return '失敗';
      case _DownloadItemStatus.cancelled:
        return '已取消';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('download_queue_dialog'),
      title: const Text('下載進度'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.queue.length,
          itemBuilder: (context, index) {
            final item = widget.queue[index];
            final status = _statuses[index];
            final canRetry =
                status == _DownloadItemStatus.failed || status == _DownloadItemStatus.cancelled;
            return ListTile(
              key: Key('download_queue_item_${item.entry.remoteBookId}'),
              title: Text(item.entry.title),
              subtitle: Text(_statusLabel(status)),
              trailing: status == _DownloadItemStatus.downloading
                  ? IconButton(
                      key: Key('download_queue_cancel_${item.entry.remoteBookId}'),
                      icon: const Icon(Icons.close),
                      tooltip: '取消',
                      onPressed: () => _cancel(index),
                    )
                  : canRetry
                      ? IconButton(
                          key: Key('download_queue_retry_${item.entry.remoteBookId}'),
                          icon: const Icon(Icons.refresh),
                          tooltip: '重試',
                          onPressed: () => _retry(index),
                        )
                      : null,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          key: const Key('download_queue_done_button'),
          onPressed: _allSettled ? () => Navigator.of(context).pop() : null,
          child: const Text('完成'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: 執行測試確認全數通過**

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: PASS，全部測試（Task 3 的 8 項＋本 Task 新增的 6 項）通過。

- [ ] **Step 6: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: 乾淨、全數通過。

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/remote_catalog_screen.dart app/test/screens/remote_catalog_screen_test.dart app/test/support/fake_opds_client.dart
git commit -m "feat(epic-30): RemoteCatalogScreen 下載佇列與 importFiles 匯入整合"
```

---

### Task 5: `RemoteServerListScreen` 導向 `RemoteCatalogScreen`

**Files:**
- Modify: `app/lib/screens/remote_server_list_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/screens/remote_server_list_screen_test.dart`

**Interfaces:**
- Consumes: Task 3（`RemoteCatalogScreen`）。
- Produces：使用者從 `RemoteServerListScreen` 點擊站點列可進入該站點的目錄瀏覽——這是本 Issue 的最終接線，完成後「新增站點→瀏覽→勾選→下載→匯入」整條路徑可從 `LibraryScreen` 完整走通。

**行為變更說明**：Issue 1 當時 `RemoteServerListScreen` 的站點列 `onTap` 導向編輯表單（因為瀏覽畫面還不存在）。本 Task 起改為導向 `RemoteCatalogScreen`，編輯改為只能透過列表項目的編輯圖示按鈕觸發（該按鈕在 Issue 1 就已存在、本 Task 不變動）。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/screens/remote_server_list_screen_test.dart` 新增 import：

```dart
import 'package:elinkbook/screens/remote_catalog_screen.dart';

import '../support/fake_book_import_service.dart';
```

修改檔案內的 `pumpScreen` 輔助函式，新增 `importService` 參數：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeRemoteServerRepository repository,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteServerListScreen(
        repository: repository,
        createOpdsClient: () => FakeOpdsClient(),
        importService: FakeBookImportService(),
      ),
    ));
    await tester.pumpAndSettle();
  }
```

修改既有測試「點擊編輯按鈕導向 RemoteServerFormScreen（編輯模式）」——這個測試不受影響（編輯圖示按鈕的行為不變）。

新增測試（放在既有測試之後）：

```dart
  testWidgets('點擊站點列（非編輯/刪除按鈕）導向 RemoteCatalogScreen', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(initialServers: [profile('srv1')]),
    );

    await tester.tap(find.byKey(const Key('remote_server_item_srv1')));
    await tester.pumpAndSettle();

    expect(find.byType(RemoteCatalogScreen), findsOneWidget);
    expect(find.byType(RemoteServerFormScreen), findsNothing);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/remote_server_list_screen_test.dart`
Expected: FAIL——`RemoteServerListScreen` 尚無 `importService` 參數；站點列點擊仍導向編輯表單。

- [ ] **Step 3: 修改 `RemoteServerListScreen`**

修改 `app/lib/screens/remote_server_list_screen.dart`：

新增 import：

```dart
import '../library/book_import_service.dart';
import 'remote_catalog_screen.dart';
```

`class RemoteServerListScreen` 新增欄位與建構參數：

```dart
  final BookImportService importService;
```

```dart
    required this.importService,
```

在 `_openEditForm` 方法之後新增：

```dart
  void _openCatalog(RemoteServerProfile profile) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: profile,
        repository: widget.repository,
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
      ),
    ));
  }
```

把 `ListTile` 的 `onTap: () => _openEditForm(profile),` 改為：

```dart
                      onTap: () => _openCatalog(profile),
```

- [ ] **Step 4: 執行測試確認 `RemoteServerListScreen` 測試通過**

Run: `flutter test test/screens/remote_server_list_screen_test.dart`
Expected: PASS，全數通過（含新增的 1 項）。

- [ ] **Step 5: 接線 `LibraryScreen`／`main.dart`**

修改 `app/lib/screens/library_screen.dart`：找到 `RemoteServerListScreen(repository: widget.remoteServerRepository!, createOpdsClient: widget.createOpdsClient!,)` 這段建構呼叫（Issue 1 的遠端書庫進入點），新增一行：

```dart
                    importService: widget.importService,
```

（`widget.importService` 是 `LibraryScreen` 既有的必填欄位，`main.dart` 已經一路傳進來，這裡不需要新增任何新的資料流，只是多轉傳一層。）

`main.dart` 不需要任何修改——`ElinkBookApp`／`LibraryScreen` 的 `importService` 早已存在於既有建構鏈中。

- [ ] **Step 6: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨；`flutter test` 全數通過，零回歸。

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/remote_server_list_screen.dart app/lib/screens/library_screen.dart app/test/screens/remote_server_list_screen_test.dart
git commit -m "feat(epic-30): RemoteServerListScreen 站點列導向 RemoteCatalogScreen"
```

---

## Self-Review（撰寫計畫後的檢查）

**1. Spec 覆蓋度**：對照 `spec.md`「OPDS 瀏覽與下載」（Task 3 目錄下鑽/分頁/縮圖/認證、Task 4 序列下載/取消/重試涵蓋）、「既有匯入管線擴充」（Task 4 `importFiles()` 呼叫涵蓋）、「UI 落地位置」（`RemoteCatalogScreen`／`FormatSelectionDialog` 皆已建立，Task 5 完成入口串接）皆對應到任務；`issues.md` Issue 2 的四項條目（`RemoteCatalogScreen`、`FormatSelectionDialog`、序列下載、`importFiles()` 整合）全數覆蓋。

**2. Placeholder 掃描**：全文無 TBD／「之後補上」等空話，程式碼片段皆為完整可貼上內容。Task 5 的 Step 5 因是對既有大檔案的精確定位修改，採用「找到...這段...新增一行」的描述方式，符合既有計畫慣例。

**3. 型別一致性**：`RemoteCatalogScreen` 建構參數（`server`/`repository`/`createOpdsClient`/`importService`/`feedUrl`/`title`）在 Task 3（定義）、Task 3 的遞迴 `_openSubsection`、Task 5（`RemoteServerListScreen._openCatalog`）用字一致；`_DownloadQueueItem`/`_DownloadItemStatus` 僅在 Task 4 內部使用，未外洩到其他檔案；`buildOpdsAuthHeaders` 在 Task 1（定義＋`OpdsHttpClient` 消費）、Task 3（`RemoteCatalogScreen` 縮圖消費）簽章一致。

**4. 生命週期原則落實**：`RemoteCatalogScreen` 的 `_client` 在 `initState()` 呼叫一次 `widget.createOpdsClient()` 並存為 `late final`，整個 widget 生命週期（含遞迴下鑽 push 的新實例、下載佇列）共用同一個真正的 session 範圍實例，符合 Issue 1 遺留的生命週期警告；`main.dart` 的 `createOpdsClient: () => OpdsHttpClient()` 確保每次呼叫都拿到全新實例。

**5. 任務間依賴**：Task 1 是純重構、無新行為，安排在最前面讓後續 Task 從一開始就用正確的工廠模式建構程式碼，避免 Task 3/4 寫完後才回頭重構一次；Task 3 刻意先不處理下載按鈕（AppBar 只有標題，無 actions），Task 4 才新增「下載」按鈕與其邏輯，兩者之間沒有互相依賴的斷裂點（Task 3 的測試不會因為 Task 4 新增 AppBar action 而失敗，因為新增 action 不影響既有的 `find.text`/`find.byKey` 斷言）。

**6. `review-plan-issue-2.md` 審查修訂**（2026-08-18，APPROVED，0 Critical／0 Important／3 Minor，已全數採納並修訂本計畫）：Finding 1（`buildOpdsAuthHeaders` 補上空白字串防禦，不只判斷 `null`）、Finding 2（`FormatSelectionDialog` 內容包 `SingleChildScrollView` 防止小螢幕/多格式時 overflow）、Finding 3（`_downloadOne` 的 `copy()` 到永久目錄中途失敗時，`catch` 區塊補上暫存檔清理，避免磁碟空間不足等情境留下孤兒檔案）皆已修訂 Task 1／Task 2／Task 4 的程式碼。

---

**Plan complete and saved to `docs/epics/epic-30-calibre-remote-library/plans/plan-issue-2.md`.** Two execution options:

**1. Subagent-Driven (recommended)** - 逐 Task 派遣新的 subagent 執行，每個 Task 完成後進行審查，快速迭代

**2. Inline Execution** - 在本次對話中直接依 Task 順序批次執行，每個 Task 結束設檢查點

**Which approach?**
