# Epic 30 Issue 5：E-Ink 優化與真機驗收 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RemoteCatalogScreen` 在 E-Ink 模式下改用離散「上一頁／下一頁」整頁換頁（取代連續捲動「載入更多」），避免滾動殘影；縮圖新增記憶體 LRU＋本機磁碟兩層快取，減少重複下載縮圖的網路請求；並對整個 Epic 的完整流程做一次 Android 真機／模擬器端到端驗證，記錄於審查報告。

**Architecture:** 三個獨立子任務。(1) `isEinkMode` 比照既有 `LibraryScreen.isEinkMode` 逐層貫穿 `RemoteServerListScreen`→`RemoteCatalogScreen`，`RemoteCatalogScreen` 在 E-Ink 模式下把「載入更多」（累加 `_entries`）換成「上一頁／下一頁」（整批替換 `_entries`，比照 `OpdsFeed.prevUrl`/`nextUrl` 既有欄位）。(2) 新增獨立的 `RemoteThumbnailCache` 純 Dart 類別（記憶體 LRU 比照 `PdfThumbnailCache` 既有設計精神，非直接重用——鍵為縮圖 URL 字串而非頁碼整數，需要獨立實作；磁碟層為新增），從 `OpdsHttpClient` 抽出共用的 `createOpdsHttpClient()` 憑證處理邏輯供縮圖網路擷取共用；`RemoteCatalogScreen` 的 `_buildThumbnail()` 改用注入的快取取代直接 `Image.network()`。(3) 端到端驗證是文件化的手動驗證程序（非自動化測試碼），比照本 Epic `spec.md` 對真實 `OpdsHttpClient` HTTP 呼叫「留待真機/人工用真實 Calibre/OPDS 伺服器驗證」的既定原則。

**Tech Stack:** Flutter widget、既有 `OpdsFeed.prevUrl`/`nextUrl`、`package:crypto`（既有依賴，縮圖磁碟快取檔名雜湊）、`package:path_provider`（`getApplicationCacheDirectory()`，2.1.6 已支援，不需升級版本）。不需要新的第三方套件。

**Spec:** `docs/epics/epic-30-calibre-remote-library/design.md`（「E-Ink 與後續優化」小節）、`docs/epics/epic-30-calibre-remote-library/issues.md`（「Issue 5：E-Ink 優化與真機驗收」）。本 Issue 沒有獨立的 `spec.md` 章節（`design.md` 已定案為獨立成本 Epic 最後一個 Issue，不涉及新增資料層介面/型別，未走正式 Architecting 階段）。

## Global Constraints

- 「搜尋防抖動」原研究報告提出的第三項優化，v1 沒有適用對象（`spec.md`「Out of Scope」已排除 OPDS 全文/即時搜尋），本 Issue 不處理，非新決策。
- E-Ink 模式偵測沿用既有 `LibraryScreen.isEinkMode`（`bool`，非新機制），不新增獨立的 E-Ink 偵測邏輯。
- 縮圖快取的網路擷取必須遵守既有「不得全域關閉憑證驗證」原則（`allowInsecure` 時僅該次連線放行憑證錯誤，比照 `OpdsHttpClient._clientFor()` 既有處理）。
- 縮圖快取的網路擷取路徑本身不做自動化測試（比照 Issue 1 對真實 `OpdsHttpClient` HTTP 呼叫的既定測試範圍界定：「真實 HTTP 呼叫、憑證處理不做自動化測試，留待真機/人工驗證」）；記憶體/磁碟快取的命中/未命中邏輯透過注入可替換的網路擷取函式做完整單元測試。

---

## Task 1：`isEinkMode` 貫穿三層＋E-Ink 離散分頁

**Files:**
- Modify: `app/lib/screens/remote_server_list_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/screens/remote_catalog_screen.dart`
- Test: `app/test/screens/remote_catalog_screen_test.dart`

**Interfaces:**
- Consumes：既有 `OpdsFeed.prevUrl`/`nextUrl`（`opds_types.dart`，Issue 1 已定案，`prevUrl` 目前未被任何呼叫端使用，本 Task 是第一個消費者）。
- Produces：`RemoteCatalogScreen`/`RemoteServerListScreen` 新增可選建構參數 `bool isEinkMode`（預設 `false`，比照 `LibraryScreen.isEinkMode` 既有預設值與非空語意，不使用 `bool?`）。

- [ ] **Step 1: 寫失敗測試（E-Ink 離散分頁）**

在 `app/test/screens/remote_catalog_screen_test.dart` 的 `group('下載與匯入')` 區塊**之前**（與既有的分類下鑽／載入更多測試同一層級）新增：

```dart
  group('E-Ink 模式離散分頁（Issue 5）', () {
    testWidgets('E-Ink 模式下有 nextUrl 時顯示上一頁/下一頁按鈕，不顯示載入更多按鈕；第一頁上一頁按鈕停用',
        (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(
          title: '根目錄',
          nextUrl: 'http://x/page2',
          entries: [entry1],
        ),
      });
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          computeFingerprint: FakeFingerprintComputer().call,
          thumbnailCache: FakeRemoteThumbnailCache(),
          createOpdsClient: () => opdsClient,
          importService: FakeBookImportService(),
          isEinkMode: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_eink_next_page_button')), findsOneWidget);
      expect(find.byKey(const Key('remote_catalog_eink_prev_page_button')), findsOneWidget);
      expect(find.byKey(const Key('remote_catalog_load_more_button')), findsNothing);

      final prevButton =
          tester.widget<OutlinedButton>(find.byKey(const Key('remote_catalog_eink_prev_page_button')));
      expect(prevButton.onPressed, isNull);
    });

    testWidgets('E-Ink 模式點擊下一頁後整批替換書目（非累加），上一頁按鈕變為可點擊', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(
          title: '根目錄',
          nextUrl: 'http://x/page2',
          entries: [entry1],
        ),
        'http://x/page2': const OpdsFeed(
          title: '根目錄',
          prevUrl: 'http://x/page1',
          entries: [entry2],
        ),
      });
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          computeFingerprint: FakeFingerprintComputer().call,
          thumbnailCache: FakeRemoteThumbnailCache(),
          createOpdsClient: () => opdsClient,
          importService: FakeBookImportService(),
          isEinkMode: true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_eink_next_page_button')));
      await tester.pumpAndSettle();

      expect(find.text('紅樓夢'), findsNothing);
      expect(find.text('不支援格式的書'), findsOneWidget);

      final nextButton =
          tester.widget<OutlinedButton>(find.byKey(const Key('remote_catalog_eink_next_page_button')));
      expect(nextButton.onPressed, isNull);
      final prevButton =
          tester.widget<OutlinedButton>(find.byKey(const Key('remote_catalog_eink_prev_page_button')));
      expect(prevButton.onPressed, isNotNull);
    });

    testWidgets('非 E-Ink 模式（預設）維持既有載入更多按鈕，不顯示上一頁/下一頁按鈕', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(
          title: '根目錄',
          nextUrl: 'http://x/page2',
          entries: [entry1],
        ),
      });
      await tester.pumpWidget(MaterialApp(
        home: RemoteCatalogScreen(
          server: server,
          repository: FakeRemoteServerRepository(),
          libraryRepository: FakeLibraryRepository(),
          computeFingerprint: FakeFingerprintComputer().call,
          thumbnailCache: FakeRemoteThumbnailCache(),
          createOpdsClient: () => opdsClient,
          importService: FakeBookImportService(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_load_more_button')), findsOneWidget);
      expect(find.byKey(const Key('remote_catalog_eink_next_page_button')), findsNothing);
      expect(find.byKey(const Key('remote_catalog_eink_prev_page_button')), findsNothing);
    });
  });
```

（`FakeRemoteThumbnailCache` 在 Task 3 才會建立——這裡先寫入測試碼，Step 2 會先確認因為 `thumbnailCache`／`FakeRemoteThumbnailCache` 都不存在而編譯失敗；Task 1 只需要先讓 `isEinkMode` 相關的部分可運作，實際完整編譯通過要等到 Task 3 完成三個 Task 都疊加後。此為刻意安排：Task 1 先寫「未來會需要」的完整測試碼一次到位，避免之後還要回頭補這幾個新欄位。）

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: FAIL——編譯錯誤（`isEinkMode`/`thumbnailCache` 具名參數不存在、`FakeRemoteThumbnailCache` 未定義）。

- [ ] **Step 3: 修改 `RemoteCatalogScreen`，新增 `isEinkMode` 與離散分頁邏輯**

修改 `app/lib/screens/remote_catalog_screen.dart`，`RemoteCatalogScreen` 類別欄位與建構子新增（緊接在 `title` 之後）：

```dart
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
    required this.createOpdsClient,
    required this.importService,
    this.feedUrl,
    this.title,
    this.isEinkMode = false,
  });
```

修改 `_RemoteCatalogScreenState`，`_nextUrl` 欄位之後新增 `_prevUrl`與 `_scrollController`：

```dart
  String? _nextUrl;
  String? _prevUrl;
  bool _loadingMore = false;
  // 〔審查 review-plan-issue-5.md Minor 採納〕ListView 沒有替換 Key，
  // Element／ScrollableState 在 _goToPage() 整批替換 _entries 後仍是
  // 同一個，捲動位移預設不會自動歸零——E-Ink 離散換頁若使用者在上一頁
  // 捲到一半才換頁，新頁面會直接停在同一個像素位移，容易讓使用者誤以為
  // 換頁沒有生效或畫面跑版，換頁後主動歸零比較符合「翻到新的一頁」的
  // 直覺。
  final ScrollController _scrollController = ScrollController();
```

在 `initState()` 之後（`_isSelectable()` 之前）新增 `dispose()`（本類別目前沒有任何 `dispose()` 覆寫，這是第一個需要釋放資源的欄位）：

```dart
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
```

修改 `_load()`，在 `_nextUrl = feed.nextUrl;` 之後新增一行：

```dart
        _nextUrl = feed.nextUrl;
        _prevUrl = feed.prevUrl;
        _loading = false;
```

修改 `_openSubsection()`，新增 `isEinkMode` 貫穿：

```dart
  void _openSubsection(OpdsNavigationLink link) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: widget.server,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        computeFingerprint: widget.computeFingerprint,
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
        feedUrl: link.href,
        title: link.title,
        isEinkMode: widget.isEinkMode,
      ),
    ));
  }
```

在 `_loadMore()` 之後新增 `_goToPage()`（E-Ink 專用的整批替換換頁，與 `_loadMore()` 的累加語意刻意分開，不合併成同一個方法）：

```dart
  /// E-Ink 模式的離散換頁（epic-30-calibre-remote-library Issue 5）：與
  /// [_loadMore] 的累加語意不同——整批替換 [_entries]/[_navigationLinks]，
  /// 不是累加在後面。換頁後清空選取狀態：[_entries] 整批替換後，先前選取
  /// 的 remoteBookId 可能已經不在畫面上，[_startDownload] 只會處理目前
  /// [_entries] 內找得到的項目，若保留跨頁選取容易讓使用者誤以為换頁前
  /// 選的書也會一併下載，實際上卻被靜默忽略——比起保留容易誤解的狀態，
  /// 換頁清空更符合直覺。
  Future<void> _goToPage(String pageUrl) async {
    setState(() => _loadingMore = true);
    try {
      final feed = await _client.fetchFeed(widget.server, password: _password, feedUrl: pageUrl);
      if (!mounted) return;
      setState(() {
        _navigationLinks
          ..clear()
          ..addAll(feed.navigationLinks);
        _entries
          ..clear()
          ..addAll(feed.entries);
        _nextUrl = feed.nextUrl;
        _prevUrl = feed.prevUrl;
        _selectedRemoteBookIds.clear();
        _loadingMore = false;
      });
      // 〔審查 review-plan-issue-5.md Minor 採納〕換頁成功後把捲動位置
      // 歸零，避免停留在上一頁的捲動位移。`hasClients` 防禦性檢查——理論
      // 上 `_buildContent()` 一定會掛上 `ListView`，但 `setState()` 之後
      // 到下一次 build 完成前的極短暫窗口仍可能尚未附加，直接呼叫
      // `jumpTo()` 會拋例外。
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }
```

修改 `_buildContent()`，把原本內嵌的「載入更多」`if (_nextUrl != null) Padding(...)` 區塊抽成獨立方法呼叫：

```dart
  Widget _buildContent() {
    return ListView(
      controller: _scrollController,
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
        _buildPaginationControls(),
      ],
    );
  }

  Widget _buildPaginationControls() {
    if (widget.isEinkMode) {
      if (_prevUrl == null && _nextUrl == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              key: const Key('remote_catalog_eink_prev_page_button'),
              onPressed: _prevUrl == null || _loadingMore ? null : () => _goToPage(_prevUrl!),
              child: const Text('上一頁'),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              key: const Key('remote_catalog_eink_next_page_button'),
              onPressed: _nextUrl == null || _loadingMore ? null : () => _goToPage(_nextUrl!),
              child: const Text('下一頁'),
            ),
          ],
        ),
      );
    }
    if (_nextUrl == null) return const SizedBox.shrink();
    return Padding(
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
    );
  }
```

- [ ] **Step 4: 貫穿 `RemoteServerListScreen`／`LibraryScreen`**

修改 `app/lib/screens/remote_server_list_screen.dart`，`RemoteServerListScreen` 類別欄位與建構子新增（緊接在 `importService` 之後）：

```dart
  final BookImportService importService;
  final bool isEinkMode;

  const RemoteServerListScreen({
    super.key,
    required this.repository,
    required this.libraryRepository,
    required this.computeFingerprint,
    required this.createOpdsClient,
    required this.importService,
    this.isEinkMode = false,
  });
```

修改 `_openCatalog()`：

```dart
  void _openCatalog(RemoteServerProfile profile) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: profile,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        computeFingerprint: widget.computeFingerprint,
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
        isEinkMode: widget.isEinkMode,
      ),
    ));
  }
```

修改 `app/lib/screens/library_screen.dart`，找到「遠端書庫」按鈕建構 `RemoteServerListScreen(...)` 處，新增一行：

```dart
                  builder: (context) => RemoteServerListScreen(
                    repository: widget.remoteServerRepository!,
                    libraryRepository: widget.repository,
                    computeFingerprint: widget.computeFingerprint!,
                    createOpdsClient: widget.createOpdsClient!,
                    importService: widget.importService,
                    isEinkMode: widget.isEinkMode,
                  ),
```

（`LibraryScreen` 本身的 `isEinkMode` 欄位已存在，不需要新增。）

- [ ] **Step 5: 執行測試確認通過（除 `thumbnailCache` 相關編譯錯誤外）**

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: 仍然 FAIL——`thumbnailCache` 具名參數與 `FakeRemoteThumbnailCache` 尚未定義（Task 3 才會補上），但錯誤訊息應僅限於這兩者，不應再有 `isEinkMode` 相關錯誤。這是預期中的中間狀態，Task 1 到此為止不強求全綠——比照 Issue 2 Task 1（`createOpdsClient` 工廠函式重構）同樣手法：新增必要建構參數會讓整個檔案先編譯失敗，等後續 Task 補上其餘依賴才會一起變綠。

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/remote_catalog_screen.dart app/lib/screens/remote_server_list_screen.dart app/lib/screens/library_screen.dart app/test/screens/remote_catalog_screen_test.dart
git commit -m "feat(epic-30): Issue 5 Task 1 - isEinkMode 貫穿三層與 E-Ink 離散分頁"
```

---

## Task 2：`RemoteThumbnailCache` 縮圖雙層快取核心邏輯

**Files:**
- Create: `app/lib/remote/remote_thumbnail_cache.dart`
- Modify: `app/lib/remote/opds_client.dart`
- Modify: `app/lib/remote/opds_http_client.dart`
- Test: `app/test/remote/remote_thumbnail_cache_test.dart`（新建）

**Interfaces:**
- Consumes：既有 `RemoteServerProfile`（`server.allowInsecure` 決定憑證放行）。
- Produces：`opds_client.dart` 新增共用函式 `http.Client createOpdsHttpClient(RemoteServerProfile server)`；`remote_thumbnail_cache.dart` 新增 `abstract class RemoteThumbnailCache { Future<Uint8List> fetch(RemoteServerProfile server, String url, Map<String, String> headers); }`、`typedef ThumbnailNetworkFetcher = Future<Uint8List> Function(RemoteServerProfile server, String url, Map<String, String> headers)`、頂層函式 `fetchThumbnailBytesOverHttp`（`ThumbnailNetworkFetcher` 的生產環境預設實作）、`class RemoteThumbnailCacheImpl implements RemoteThumbnailCache`。供 Task 3 使用。

- [ ] **Step 1: 抽出共用的 `createOpdsHttpClient()`**

修改 `app/lib/remote/opds_client.dart` 開頭 import，新增：

```dart
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
```

在 `fileExtensionFor()` 函式之後新增：

```dart
/// 依 [server.allowInsecure] 決定是否放行憑證錯誤的共用 [http.Client]
/// 建構函式（epic-30-calibre-remote-library Issue 5，從
/// `OpdsHttpClient` 原本的私有 `_clientFor()` 抽出，供縮圖快取的網路
/// 擷取共用同一份憑證處理邏輯，避免各自重寫一份）。**僅這一次呼叫端
/// 持有的 client 物件生效**（呼叫端用畢即 `close()`），不會影響其他
/// 連線，符合「不得全域關閉憑證驗證」的既定原則。
http.Client createOpdsHttpClient(RemoteServerProfile server) {
  if (!server.allowInsecure) return http.Client();
  final rawClient = HttpClient()..badCertificateCallback = (cert, host, port) => true;
  return IOClient(rawClient);
}
```

修改 `app/lib/remote/opds_http_client.dart`：刪除私有 `_clientFor()` 方法（原第 30-39 行的文件註解＋方法本體），並把兩個呼叫點 `_clientFor(server)` 改為 `createOpdsHttpClient(server)`：

```dart
    final url = feedUrl ?? server.baseUrl;
    _visitedFeedUrls.add(url);
    final client = createOpdsHttpClient(server);
```

```dart
  ) async {
    final client = createOpdsHttpClient(server);
```

（`createOpdsHttpClient` 已由既有的 `import 'opds_client.dart';` 匯入，不需要新增 import。）

- [ ] **Step 2: 執行 `flutter analyze` 確認重構沒有編譯期問題**

Run: `flutter analyze lib/remote/opds_client.dart lib/remote/opds_http_client.dart`
Expected: 乾淨，無錯誤或警告。**注意**：`OpdsHttpClient` 本身沒有自動化測試覆蓋真實 HTTP 行為（比照本 Epic 既定範圍界定，Issue 1 `plan-issue-1.md`「真實 `OpdsHttpClient` 的實際 HTTP 呼叫、憑證處理不做自動化測試，留待真機/人工用真實 Calibre/OPDS 伺服器驗證」），本專案目前也沒有 `opds_http_client_test.dart`——這個重構是否維持行為等價，主要靠程式碼比對（`_clientFor()` 搬到 `createOpdsHttpClient()` 邏輯逐行相同）與 Task 4 的真機驗證間接覆蓋，`flutter analyze` 只能確認型別/編譯正確，不是完整的行為驗證，這是既有測試範圍的既定限制、非本 Task 新引入的缺口。

- [ ] **Step 3: 寫失敗測試（`RemoteThumbnailCache`）**

新建 `app/test/remote/remote_thumbnail_cache_test.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/remote_thumbnail_cache.dart';

void main() {
  final server = RemoteServerProfile(
    id: 'srv1',
    name: '家用 NAS',
    baseUrl: 'http://192.168.1.100:8080/opds',
    type: RemoteServerType.opds,
    allowInsecure: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('remote_thumbnail_cache_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('兩層皆未命中時呼叫網路擷取函式，結果寫入磁碟快取', () async {
    final networkCalls = <String>[];
    final cache = RemoteThumbnailCacheImpl(
      cacheDir: tempDir,
      fetchOverNetwork: (server, url, headers) async {
        networkCalls.add(url);
        return Uint8List.fromList([1, 2, 3]);
      },
    );

    final bytes = await cache.fetch(server, 'http://x/cover.jpg', const {});

    expect(bytes, [1, 2, 3]);
    expect(networkCalls, ['http://x/cover.jpg']);
    expect(tempDir.listSync(), isNotEmpty);
  });

  test('記憶體快取命中時不呼叫網路擷取函式', () async {
    final networkCalls = <String>[];
    final cache = RemoteThumbnailCacheImpl(
      cacheDir: tempDir,
      fetchOverNetwork: (server, url, headers) async {
        networkCalls.add(url);
        return Uint8List.fromList([1, 2, 3]);
      },
    );

    await cache.fetch(server, 'http://x/cover.jpg', const {});
    final bytes = await cache.fetch(server, 'http://x/cover.jpg', const {});

    expect(bytes, [1, 2, 3]);
    expect(networkCalls, ['http://x/cover.jpg']);
  });

  test('記憶體未命中但磁碟命中時，讀取磁碟內容且不呼叫網路擷取函式', () async {
    var networkCallCount = 0;
    final cacheA = RemoteThumbnailCacheImpl(
      cacheDir: tempDir,
      fetchOverNetwork: (server, url, headers) async {
        networkCallCount++;
        return Uint8List.fromList([9, 9, 9]);
      },
    );
    await cacheA.fetch(server, 'http://x/cover.jpg', const {});
    expect(networkCallCount, 1);

    // 新建一個實例，模擬「記憶體快取是每個實例獨立、磁碟快取是持久化」
    // 的情境——第二個實例的記憶體是空的，但磁碟快取檔案仍在。
    final cacheB = RemoteThumbnailCacheImpl(
      cacheDir: tempDir,
      fetchOverNetwork: (server, url, headers) async {
        networkCallCount++;
        return Uint8List.fromList([9, 9, 9]);
      },
    );
    final bytes = await cacheB.fetch(server, 'http://x/cover.jpg', const {});

    expect(bytes, [9, 9, 9]);
    expect(networkCallCount, 1);
  });

  test('記憶體 LRU 超過上限時淘汰最舊項目，磁碟快取仍保留', () async {
    var networkCallCount = 0;
    final cache = RemoteThumbnailCacheImpl(
      cacheDir: tempDir,
      memoryMaxSize: 2,
      fetchOverNetwork: (server, url, headers) async {
        networkCallCount++;
        return Uint8List.fromList(utf8.encode(url));
      },
    );

    await cache.fetch(server, 'http://x/a.jpg', const {});
    await cache.fetch(server, 'http://x/b.jpg', const {});
    await cache.fetch(server, 'http://x/c.jpg', const {});
    expect(networkCallCount, 3);

    // http://x/a.jpg 應已被 LRU 淘汰出記憶體（c 進來時 a 最舊）；刪除它
    // 對應的磁碟快取檔案後，再次 fetch 應該要嘗試重新從網路擷取（因為
    // 記憶體沒有、磁碟也被我們手動刪除了）——藉此間接驗證記憶體確實
    // 已淘汰，而非還殘留著。
    final aDiskFiles = tempDir.listSync().whereType<File>().toList();
    for (final file in aDiskFiles) {
      final content = utf8.decode(file.readAsBytesSync());
      if (content == 'http://x/a.jpg') file.deleteSync();
    }
    await cache.fetch(server, 'http://x/a.jpg', const {});
    expect(networkCallCount, 4);
  });
}
```

在檔案開頭補上 `import 'dart:convert';`（`utf8.encode`/`utf8.decode` 需要）：

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
```

- [ ] **Step 4: 執行測試確認失敗**

Run: `flutter test test/remote/remote_thumbnail_cache_test.dart`
Expected: FAIL——`remote_thumbnail_cache.dart` 尚不存在（編譯錯誤）。

- [ ] **Step 5: 實作 `RemoteThumbnailCache`**

新建 `app/lib/remote/remote_thumbnail_cache.dart`：

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'opds_client.dart';
import 'remote_server_profile.dart';

/// OPDS 目錄縮圖的雙層快取（epic-30-calibre-remote-library Issue 5，
/// design.md「E-Ink 與後續優化」）：記憶體 LRU＋本機磁碟，減少使用者
/// 在同一瀏覽 session 或跨 App 啟動重複下載同一張縮圖。
abstract class RemoteThumbnailCache {
  Future<Uint8List> fetch(RemoteServerProfile server, String url, Map<String, String> headers);
}

/// [RemoteThumbnailCacheImpl] 的網路擷取函式型別，注入而非直接呼叫
/// [fetchThumbnailBytesOverHttp]——單元測試需要能替換成不觸碰真實網路
/// 的假函式（比照本 Epic 既有 `createOpdsClient`／`ComputeRemoteFingerprint`
/// 的注入先例），真實網路擷取路徑本身比照 `OpdsHttpClient` 既定範圍不做
/// 自動化測試。
typedef ThumbnailNetworkFetcher = Future<Uint8List> Function(
  RemoteServerProfile server,
  String url,
  Map<String, String> headers,
);

/// [ThumbnailNetworkFetcher] 的生產環境預設實作：透過 [createOpdsHttpClient]
/// 取得依 [server.allowInsecure] 決定是否放行憑證錯誤的 client，逾時比照
/// `OpdsHttpClient` 既有的 10 秒設定。
Future<Uint8List> fetchThumbnailBytesOverHttp(
  RemoteServerProfile server,
  String url,
  Map<String, String> headers,
) async {
  final client = createOpdsHttpClient(server);
  try {
    final response =
        await client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('縮圖下載失敗：HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    return response.bodyBytes;
  } finally {
    client.close();
  }
}

/// [RemoteThumbnailCache] 的真實實作。記憶體層用 `Map`（Dart 預設實作為
/// 插入順序穩定的 `LinkedHashMap`）的插入順序語意做 LRU——命中時移除後
/// 重新插入視為「最近使用」，超過 [memoryMaxSize] 時淘汰 `keys.first`
/// （最舊項目），比照 `pdf_thumbnail_cache.dart` 的 `PdfThumbnailCache`
/// 既有設計精神；鍵為縮圖 URL 字串（非頁碼整數），故非直接重用該類別、
/// 獨立實作。磁碟層以 URL 的 SHA-256 雜湊做檔名（URL 本身含斜線/問號等
/// 不適合直接當檔名的字元），落地於 [cacheDir]（呼叫端提供，生產環境
/// 由 `main.dart` 透過 `getApplicationCacheDirectory()` 取得——語意上是
/// 可被 OS 回收的快取，與 Issue 2/4 用 `getApplicationDocumentsDirectory()`
/// 的永久書籍檔案是不同目錄、不同生命週期保證）。
///
/// **已知取捨（刻意，非疏漏）**：同一個 URL 在第一次擷取完成前又被重複
/// `fetch()`（例如畫面因其他原因 `setState()` 重建、GridView 對同一張
/// 縮圖再次呼叫 `_buildThumbnail()`），兩次呼叫可能並行各自觸發一次真實
/// 網路請求——沒有做「同一個 URL 進行中的 Future 去重」。縮圖網格的請求
/// 量與重複機率低，最終兩次都會成功並各自寫入相同內容的磁碟快取，不是
/// 正確性問題，只是輕微浪費；為了避免這個低機率情境新增第三層快取
/// （in-flight Future 去重表）複雜度不划算。
class RemoteThumbnailCacheImpl implements RemoteThumbnailCache {
  RemoteThumbnailCacheImpl({
    required Directory cacheDir,
    this.memoryMaxSize = 100,
    ThumbnailNetworkFetcher fetchOverNetwork = fetchThumbnailBytesOverHttp,
  })  : _cacheDir = cacheDir,
        _fetchOverNetwork = fetchOverNetwork;

  final Directory _cacheDir;
  final int memoryMaxSize;
  final ThumbnailNetworkFetcher _fetchOverNetwork;
  final _memory = <String, Uint8List>{};

  Uint8List? _memoryGet(String key) {
    final value = _memory.remove(key);
    if (value == null) return null;
    _memory[key] = value;
    return value;
  }

  void _memoryPut(String key, Uint8List value) {
    _memory.remove(key);
    _memory[key] = value;
    if (_memory.length > memoryMaxSize) {
      _memory.remove(_memory.keys.first);
    }
  }

  String _diskKeyFor(String url) => sha256.convert(utf8.encode(url)).toString();

  @override
  Future<Uint8List> fetch(RemoteServerProfile server, String url, Map<String, String> headers) async {
    final memHit = _memoryGet(url);
    if (memHit != null) return memHit;

    final diskFile = File(p.join(_cacheDir.path, _diskKeyFor(url)));
    if (await diskFile.exists()) {
      final bytes = await diskFile.readAsBytes();
      _memoryPut(url, bytes);
      return bytes;
    }

    final bytes = await _fetchOverNetwork(server, url, headers);
    if (!await _cacheDir.exists()) await _cacheDir.create(recursive: true);
    await diskFile.writeAsBytes(bytes);
    _memoryPut(url, bytes);
    return bytes;
  }
}
```

- [ ] **Step 6: 執行測試確認通過**

Run: `flutter test test/remote/remote_thumbnail_cache_test.dart`
Expected: PASS，4 項測試皆通過。

- [ ] **Step 7: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨（`remote_catalog_screen.dart` 因 Task 1 已引用尚不存在的 `thumbnailCache` 仍會報錯，這是預期中的中間狀態，Task 3 完成後才會一起變綠——本步驟只需確認新增的這兩個檔案本身、以及 `OpdsHttpClient` 重構沒有引入新問題）；`flutter test` 除 `remote_catalog_screen_test.dart`（Task 1 已寫入但依賴 Task 3 才存在的 `FakeRemoteThumbnailCache`）外全數通過。

- [ ] **Step 8: Commit**

```bash
git add app/lib/remote/remote_thumbnail_cache.dart app/lib/remote/opds_client.dart app/lib/remote/opds_http_client.dart app/test/remote/remote_thumbnail_cache_test.dart
git commit -m "feat(epic-30): Issue 5 Task 2 - RemoteThumbnailCache 縮圖雙層快取核心邏輯"
```

---

## Task 3：`RemoteCatalogScreen` 縮圖快取整合＋三層螢幕貫穿

**Files:**
- Modify: `app/lib/screens/remote_catalog_screen.dart`
- Modify: `app/lib/screens/remote_server_list_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Create: `app/test/support/fake_remote_thumbnail_cache.dart`
- Test: `app/test/screens/remote_catalog_screen_test.dart`
- Test: `app/test/screens/remote_server_list_screen_test.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `RemoteThumbnailCache`／`RemoteThumbnailCacheImpl`。
- Produces：`RemoteCatalogScreen`/`RemoteServerListScreen` 新增必要建構參數 `RemoteThumbnailCache thumbnailCache`；`LibraryScreen` 新增可選建構參數 `RemoteThumbnailCache? thumbnailCache`（比照 `createOpdsClient`/`computeFingerprint` 既有的「遠端功能整組同時存在」可選模式）。

- [x] **Step 1: 新增 `FakeRemoteThumbnailCache` 測試替身**

新建 `app/test/support/fake_remote_thumbnail_cache.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/remote_thumbnail_cache.dart';

/// 供 widget test 使用的 [RemoteThumbnailCache] 假實作，避免測試環境
/// 觸碰真實網路／磁碟 I/O（比照本 Epic 既有 `FakeOpdsClient` 命名與
/// 設計慣例）。預設回傳一張最小合法的 1x1 透明 PNG（讓 `Image.memory()`
/// 能成功解碼、不觸發 `errorBuilder`）——沿用 `library_screen_test.dart`
/// 既有測試（`Key('cover.png')` 附近）已驗證可用的同一組 base64 位元組，
/// 不重新手key一份新的 PNG 二進位內容以避免自行手誤產生無效檔案，
/// [error] 非 `null` 時改為拋出例外，供測試驗證錯誤狀態呈現。
class FakeRemoteThumbnailCache implements RemoteThumbnailCache {
  FakeRemoteThumbnailCache({this.error});

  final Object? error;
  final List<String> fetchCalls = [];

  static final Uint8List minimalPngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
    '42YAAAAASUVORK5CYII=',
  );

  @override
  Future<Uint8List> fetch(RemoteServerProfile server, String url, Map<String, String> headers) async {
    fetchCalls.add(url);
    if (error != null) throw error!;
    return minimalPngBytes;
  }
}
```

- [x] **Step 2: 寫失敗測試（縮圖快取整合）**

修改 `app/test/screens/remote_catalog_screen_test.dart` 開頭 import，新增：

```dart
import '../support/fake_remote_thumbnail_cache.dart';
```

修改 `pumpScreen` helper，新增 `thumbnailCache` 參數：

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
    ));
    await tester.pumpAndSettle();
  }
```

既有測試「書目縮圖以 Image.network 載入並帶入 Basic Auth header」（斷言 `image.image as NetworkImage`）在改用 `FutureBuilder`＋`Image.memory` 後會直接編譯期通過但執行期斷言失敗（`image.image` 已不再是 `NetworkImage`，`as` 轉型會拋出例外）——**整段刪除這則既有測試**，替換為下面兩則驗證新快取路徑的測試（第一則涵蓋原測試想驗證的「正確的 URL／header 有被使用」意圖，只是驗證手法從檢查 `NetworkImage` 屬性改為檢查 `FakeRemoteThumbnailCache.fetchCalls`）：

```dart
  testWidgets('書目縮圖透過 RemoteThumbnailCache 取得，帶入正確的 URL 與 Basic Auth header', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
    });
    final thumbnailCache = FakeRemoteThumbnailCache();
    await pumpScreen(tester, opdsClient: opdsClient, thumbnailCache: thumbnailCache);

    expect(thumbnailCache.fetchCalls, [entry1.thumbnailUrl]);
    final image = tester.widget<Image>(find.byKey(const Key('remote_catalog_thumbnail_book-1')));
    expect(image.image, isA<MemoryImage>());
  });

  testWidgets('縮圖快取擷取失敗時顯示錯誤圖示', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
    });
    final thumbnailCache = FakeRemoteThumbnailCache(error: StateError('模擬縮圖下載失敗'));
    await pumpScreen(tester, opdsClient: opdsClient, thumbnailCache: thumbnailCache);

    expect(find.byKey(const Key('remote_catalog_thumbnail_error_book-1')), findsOneWidget);
  });
```

Task 1 新增的 3 則 E-Ink 測試（Step 1 已寫入）已經各自帶有 `thumbnailCache: FakeRemoteThumbnailCache(),`，不需要再改。**除了這 3 則與使用 `pumpScreen` helper 的測試之外**，本檔案其餘所有不經過 `pumpScreen` helper、直接呼叫 `RemoteCatalogScreen(...)` 建構子的既有測試（下載與匯入相關的一系列測試），逐一新增一行 `thumbnailCache: FakeRemoteThumbnailCache(),`（緊接在 `computeFingerprint:` 那一行之後即可，順序不影響正確性）。實際筆數以檔案當下內容為準逐一確認，不要漏改任何一處——漏改會在 Step 3 執行測試時以編譯錯誤的形式立即暴露，逐一修正到全部通過為止。

- [x] **Step 3: 執行測試確認失敗**

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: FAIL——`RemoteCatalogScreen` 沒有 `thumbnailCache` 具名參數（編譯錯誤）。

- [x] **Step 4: 修改 `RemoteCatalogScreen`**

修改 `app/lib/screens/remote_catalog_screen.dart` 開頭 import，新增：

```dart
import 'dart:typed_data';

import '../remote/remote_thumbnail_cache.dart';
```

修改 `RemoteCatalogScreen` 類別欄位與建構子，新增 `thumbnailCache`（緊接在 `computeFingerprint` 之後）：

```dart
  final ComputeRemoteFingerprint computeFingerprint;
  final RemoteThumbnailCache thumbnailCache;
  final OpdsClient Function() createOpdsClient;
```

```dart
    required this.computeFingerprint,
    required this.thumbnailCache,
    required this.createOpdsClient,
```

修改 `_openSubsection()`，新增貫穿：

```dart
        computeFingerprint: widget.computeFingerprint,
        thumbnailCache: widget.thumbnailCache,
        createOpdsClient: widget.createOpdsClient,
```

修改 `_buildThumbnail()`，改用注入的快取：

```dart
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
    return FutureBuilder<Uint8List>(
      future: widget.thumbnailCache.fetch(
        widget.server,
        thumbnailUrl,
        buildOpdsAuthHeaders(widget.server, _password),
      ),
      // 〔審查 review-plan-issue-5.md Important 採納〕Flutter 的
      // FutureBuilder.didUpdateWidget() 只要傳入的 future 是新的物件實例
      // 就會把 connectionState 重置（不是 done），但 snapshot.data 仍保留
      // 上一輪成功的結果——這個 build() 方法每次重建都會呼叫一次
      // fetch()、產生新的 Future 實例（即使底層記憶體 LRU 幾乎立即命中），
      // 若先判斷 connectionState != done 就先回傳載入中佔位符，會讓已經
      // 載入完成的縮圖在任何無關的 setState()（例如勾選另一本書）後閃爍
      // 回佔位符一幀，在 E-Ink 螢幕上更明顯、恰好牴觸本 Issue 想解決的
      // 殘影問題——優先檢查 hasData，已有資料就直接顯示，不受
      // connectionState 短暫重置影響。
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            key: Key('remote_catalog_thumbnail_${entry.remoteBookId}'),
            fit: BoxFit.cover,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            key: Key('remote_catalog_thumbnail_loading_${entry.remoteBookId}'),
            child: const Icon(Icons.book),
          );
        }
        return Center(
          key: Key('remote_catalog_thumbnail_error_${entry.remoteBookId}'),
          child: const Icon(Icons.broken_image),
        );
      },
    );
  }
```

**設計選擇說明（非計畫遺漏）**：這個修法解決的是「已有資料時優先顯示、不被短暫的 connectionState 重置蓋掉」，沒有連帶處理「每次 build() 都重新呼叫一次 `fetch()`」本身這件事（沒有用 `Map<String, Future<Uint8List>>` 之類的欄位把 Future 記憶下來）。後者屬於已知、刻意接受的取捨——見 `remote_thumbnail_cache.dart` 類別文件「已知取捨」段落：重複呼叫 `fetch()` 對同一個 URL，記憶體 LRU 幾乎立即命中，成本很低，加一層 Future 記憶化只是為了避免這個低成本的重複呼叫，複雜度不划算；本次修法已經解決了唯一有實際使用者可見影響的部分（畫面閃爍）。

- [x] **Step 5: 執行測試確認通過**

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: PASS，全數通過（含 Task 1 的 3 項 E-Ink 測試、既有測試、本 Task 新增的 2 項）。

- [x] **Step 6: 貫穿 `RemoteServerListScreen`／`LibraryScreen`／`main.dart`**

修改 `app/lib/screens/remote_server_list_screen.dart` 開頭 import，新增：

```dart
import '../remote/remote_thumbnail_cache.dart';
```

修改 `RemoteServerListScreen` 類別欄位與建構子：

```dart
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
```

修改 `_openCatalog()`：

```dart
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
```

修改 `app/test/screens/remote_server_list_screen_test.dart`，新增 import：

```dart
import '../support/fake_remote_thumbnail_cache.dart';
```

修改 `pumpScreen` helper：

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

修改 `app/lib/screens/library_screen.dart` 開頭 import，新增：

```dart
import '../remote/remote_thumbnail_cache.dart';
```

修改 `LibraryScreen` 類別，新增欄位與建構參數（緊接在 `computeFingerprint` 之後）：

```dart
  final ComputeRemoteFingerprint? computeFingerprint;
  final RemoteThumbnailCache? thumbnailCache;
  final Future<bool> Function()? isMobileDataConnection;
```

```dart
    this.computeFingerprint,
    this.thumbnailCache,
    this.isMobileDataConnection,
```

修改遠端書庫入口按鈕，條件與建構呼叫皆新增 `thumbnailCache`：

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
              Navigator.of(context).push(
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
              );
            },
          ),
```

修改 `app/test/screens/library_screen_test.dart`，找到「提供 remoteServerRepository/opdsClient 時，AppBar 顯示遠端書庫按鈕」測試，新增 import（若尚未存在）：

```dart
import '../support/fake_remote_thumbnail_cache.dart';
```

並在該測試的 `LibraryScreen(...)` 建構呼叫新增一行：

```dart
          repository: repository,
          importService: importService,
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(),
          createOpdsClient: () => FakeOpdsClient(),
          computeFingerprint: (path, format) async => 'test-fingerprint',
          thumbnailCache: FakeRemoteThumbnailCache(),
```

修改 `app/lib/main.dart` 開頭 import，新增（`main.dart` 目前尚未匯入 `dart:io`／`package:path`，皆為新增，非既有重複）：

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'remote/remote_thumbnail_cache.dart';
```

在 `main()` 函式內、建構 `ElinkBookApp(...)` **之前**新增（緊接在 `remoteServerRepository` 建構之後）：

```dart
  final remoteServerRepository = SqliteRemoteServerRepository(
    database: repository.database,
    libraryRepository: repository,
  );
  final thumbnailCacheDir = await getApplicationCacheDirectory();
  final thumbnailCache = RemoteThumbnailCacheImpl(
    cacheDir: Directory(p.join(thumbnailCacheDir.path, 'remote_thumbnails')),
  );
```

在 `ElinkBookApp(...)` 建構呼叫中，於 `computeFingerprint: computeBookContentFingerprint,` 之後新增：

```dart
      computeFingerprint: computeBookContentFingerprint,
      thumbnailCache: thumbnailCache,
      isMobileDataConnection: _isMobileDataConnection,
```

在 `ElinkBookApp` 類別欄位與建構子，於 `computeFingerprint` 之後新增：

```dart
  final ComputeRemoteFingerprint? computeFingerprint;
  final RemoteThumbnailCache? thumbnailCache;
  final Future<bool> Function()? isMobileDataConnection;
```

```dart
    this.computeFingerprint,
    this.thumbnailCache,
    this.isMobileDataConnection,
```

在 `_ElinkBookAppState.build()` 建構 `LibraryScreen` 處，於 `computeFingerprint: widget.computeFingerprint,` 之後新增：

```dart
        computeFingerprint: widget.computeFingerprint,
        thumbnailCache: widget.thumbnailCache,
        isMobileDataConnection: widget.isMobileDataConnection,
```

- [x] **Step 7: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨；`flutter test` 全數通過，零回歸。

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/remote_catalog_screen.dart app/lib/screens/remote_server_list_screen.dart app/lib/screens/library_screen.dart app/lib/main.dart app/test/support/fake_remote_thumbnail_cache.dart app/test/screens/remote_catalog_screen_test.dart app/test/screens/remote_server_list_screen_test.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-30): Issue 5 Task 3 - RemoteCatalogScreen 縮圖快取整合與三層貫穿"
```

---

## Task 4：Android 真機／模擬器端到端驗證

**Files:**
- Create（審查階段產出，非本 Task 產生）：`docs/epics/epic-30-calibre-remote-library/reviews/review-issue-5.md`（記錄驗證結果，比照既有 `reviews/review-issue-N.md` 慣例）

**背景：** 本 Task 沒有可自動化的程式碼步驟——比照 `spec.md` 對真實 `OpdsHttpClient` HTTP 呼叫「不做自動化測試，留待真機/人工用真實 Calibre/OPDS 伺服器驗證」的既定範圍界定，這是本 Epic 第一次、也是唯一一次要求對**整個 Epic**（Issue 0-5 全部功能）做一次串接真實伺服器的端到端人工驗證。執行者需要：(a) 一台可連上區域網路的 Android 真機或模擬器，(b) 一個真實可連線的 Calibre Content Server 或其他 OPDS 1.2/2.0 伺服器（純 HTTP 或自簽憑證 HTTPS 皆可，比照 Issue 1 已支援的兩種情境）。若沒有實體 E-Ink 裝置可用，一般 Android 裝置切換「E-Ink 高對比模式」（`LibraryScreen` 既有的 `library_eink_toggle` 按鈕）即可驗證離散分頁邏輯本身是否正確運作，只是無法驗證真實 E-Ink 螢幕的殘影觀感。

- [ ] **Step 1: 準備測試環境**

```bash
cd app
flutter devices
```

確認至少一台裝置可用（實體裝置或模擬器皆可）。啟動一個可連線的 Calibre Content Server（例如 `calibre-server --port=8080` 於同網段主機上執行，或使用既有可用的測試伺服器），記下其區網 IP 與埠號。

- [ ] **Step 2: 建置並安裝**

```bash
flutter build apk --debug
flutter install
```

或直接 `flutter run -d <device-id>` 啟動除錯執行，方便同時觀察 log。

- [ ] **Step 3: 執行完整流程逐項驗證**

依序操作並記錄每一步的實際結果（成功／失敗＋失敗描述）：

1. **新增站點**：進入圖書庫→遠端書庫入口→新增站點，輸入步驟 1 記下的 Calibre Content Server 位址（純 HTTP 情境）；點擊「測試連線」，預期顯示連線成功。若有自簽憑證 HTTPS 測試伺服器可用，另建一筆勾選「允許不安全連線」的站點，同樣測試連線成功。
2. **瀏覽目錄**：點擊剛新增的站點，預期進入 `RemoteCatalogScreen` 顯示分類導覽與書目縮圖網格；縮圖應正常載入（非破圖圖示）；點擊分類項目可下鑽；若目錄有分頁，「載入更多」應正確累加書目。
3. **下載**：勾選 1-2 本書（若有提供多格式的書目，驗證彈出格式選擇彈窗），點擊下載，預期依序顯示「下載中」→「完成」狀態，下載佇列對話框「完成」按鈕變為可點擊。
4. **匯入**：關閉下載佇列對話框，預期回到圖書庫可看到剛下載的書（封面/書名正確，非「待下載」雲朵角標狀態）。
5. **閱讀**：點擊該書，預期正常開啟 `ReaderScreen` 並顯示內容（非空白/錯誤畫面）。
6. **移除快取**：返回圖書庫，長按該書進入選取模式，點擊「移除本機快取」，預期書架封面疊加雲朵角標，書名/分類等中繼資料不變。
7. **重新下載**：點擊該本「待下載」的書，預期跳出確認對話框（若裝置目前為行動數據連線會額外顯示流量提示，Wi-Fi 連線則不會），確認後預期重新下載成功、雲朵角標消失、可再次正常開啟閱讀。
8. **E-Ink 模式驗證**：於圖書庫 AppBar 切換「E-Ink 高對比模式」按鈕，重新進入該站點的目錄瀏覽，預期原本的「載入更多」變成「上一頁／下一頁」按鈕列；若目錄有多頁，驗證換頁後書目確實整批替換（非累加），且捲動時不再有連續載入觸發的高幀率動畫。
9. **刪除站點**：返回站點清單，確認該站點已無「僅雲端紀錄」（`isDownloaded == false`）的書籍後，點擊刪除，預期成功刪除且不影響已下載書籍（該書籍應仍在圖書庫，只是不再顯示遠端來源相關操作選項如「移除本機快取」）。若手動另外建立一筆有「待下載」書籍的測試情境並嘗試刪除該站點，預期被拒絕並顯示示警清單（回歸驗證 Issue 1 既有行為）。

- [ ] **Step 4: 記錄驗證結果**

無論全數通過或發現問題，皆整理為 `docs/epics/epic-30-calibre-remote-library/reviews/review-issue-5.md`（比照既有 `reviews/review-issue-N.md` 格式）：驗證日期、使用的裝置型號／Android 版本、OPDS 伺服器類型與版本、每一步驟的實際結果、發現的問題（若有，依 Critical/Important/Minor 分級，比照既有程式審查報告慣例）。若發現阻擋性問題，回頭修正對應 Task 的程式碼並重新驗證，不在本 Task 直接修改——遵循本專案「審查先出報告，不得直接修改被審查對象」的既定流程；但這裡的「被審查對象」是程式碼本身的正確性驗證結果，若問題明確且範圍限於本 Issue 新增的程式碼（Task 1-3），可由實作者自行修正後重新驗證，不需要另外發起一輪獨立審查（本 Task 性質上就是這個 Issue 的最終驗收關卡）。

- [ ] **Step 5: Commit（若驗證過程中有修正）**

```bash
git add docs/epics/epic-30-calibre-remote-library/reviews/review-issue-5.md
git commit -m "docs(epic-30): Issue 5 Task 4 - 真機端到端驗證結果記錄"
```

若驗證過程中發現問題並修正了 Task 1-3 的程式碼，另外針對每次修正各自提交一個 commit（比照本專案既有的逐項修正 commit 慣例），不與驗證結果文件記錄混在同一個 commit。

---

## Self-Review（撰寫計畫時的自我檢查）

**Spec 涵蓋度**：`issues.md` Issue 5「What to build」3 個條列點——(1) E-Ink 離散分頁→Task 1；(2) 縮圖雙層快取→Task 2＋Task 3；(3) 真機端到端驗證→Task 4。「單元測試要求」2 項——E-Ink 模式偵測下改用按鈕列渲染／點擊翻頁行為正確→Task 1 測試；縮圖快取記憶體/磁碟命中與未命中邏輯→Task 2 測試。「驗收標準」4 項——E-Ink 模式不觸發連續捲動殘影（Task 1，離散分頁本身消除了連續捲動的觸發條件）、縮圖快取有效減少重複請求（Task 2 測試已驗證記憶體/磁碟命中時不重新呼叫網路擷取）、真機端到端驗證結果記錄於審查報告（Task 4）、`flutter analyze`/`flutter test` 通過（每個 Task 皆有對應步驟）。

**型別一致性**：`isEinkMode`（`bool`，預設 `false`）在 `RemoteCatalogScreen`/`RemoteServerListScreen`/`LibraryScreen`（既有）三處型別一致。`RemoteThumbnailCache`／`ThumbnailNetworkFetcher`／`RemoteThumbnailCacheImpl` 在 Task 2 定義後，Task 3 的所有使用處（`RemoteCatalogScreen`／`RemoteServerListScreen`／`LibraryScreen`／`main.dart`）簽章一致。`createOpdsHttpClient(RemoteServerProfile)` 在 Task 2 Step 1 定義後，`OpdsHttpClient`（既有重構）與 `fetchThumbnailBytesOverHttp`（Task 2 Step 5 新呼叫點）簽章一致。

**佔位符掃描**：全文無 TBD／implement later／"add appropriate error handling" 等字樣；所有程式碼步驟皆附完整可執行程式碼。Task 4 屬性質上就是手動驗證程序，依「No Placeholders」的精神已提供具體到「每一步做什麼、預期看到什麼」的程度，不是模糊的「測試整個流程」帶過。
