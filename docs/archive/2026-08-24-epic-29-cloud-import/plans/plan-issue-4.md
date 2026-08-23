# Epic 29 Issue 4：OneDrive 瀏覽＋匯入（單/多檔）實作計劃

> **給執行者：** 本計劃必須搭配 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行。每個 Step 用 checkbox（`- [ ]`）追蹤，完成後改為 `- [x]`。

**Goal：** 讓使用者能在「匯入」選單選擇「從 OneDrive 匯入」，沿用 Issue 3 已建好的瀏覽/下載畫面（`CloudBrowserScreen`／`CloudDownloadQueueDialog`），只需新增 `OneDriveStorageClient` 實作 `CloudStorageClient` 介面即可，不需要重新設計 UI。

**Architecture：** `OneDriveStorageClient` 結構完全比照 Issue 3 已審查通過的 `GoogleDriveStorageClient`（同一套 `listFolder`/`downloadFile`/`fetchThumbnail`/`CloudAuthRequiredException` 契約），差異僅在於 Microsoft Graph API 的端點格式與回應欄位——Graph API 的分頁機制是完整絕對 URL 的 `@odata.nextLink`（不像 Google Drive 是不透明的 `pageToken` 字串），下一頁直接 `GET` 該 URL 即可，不需要另外組查詢參數。格式過濾**刻意不使用** Graph OData `$filter`（例如 `endswith(name,'.epub')`）做伺服器端精確篩選——雖然 Graph OData 語法理論上支援，但本計劃作者無法在撰寫當下存取真實 Graph API 驗證這類複合 filter 表達式（`folder` facet 是否存在＋多個 `endswith` 用 `or` 串接）實際可用，為避免在未經驗證的 API 語法上下注，改採**與 Google Drive 完全相同的保守策略**：`listFolder()` 取回資料夾內全部項目（不做任何伺服器端格式篩選），100% 交給既有的 `detectCloudFileFormat()`（Issue 3 已建置，`CloudStorageClient` 介面所在檔案內的共用純函式）做用戶端精確過濾——這個函式當初就是為了跨 provider 共用而設計，本 Issue 直接復用、不新增任何格式判斷邏輯。Issue 3 的瀏覽畫面原本命名為 `GoogleDriveBrowserScreen`，用它來瀏覽 OneDrive 會是誤導性的類別名稱（比照 Issue 2 把 `_buildGoogleDriveTile()` 泛化為 `_buildProviderTile()` 的既有先例），Task 2 先把這個類別（含檔案名稱）重新命名為通用的 `CloudBrowserScreen`——**但刻意不重新命名其內部的 `Key('google_drive_browser_...')` 系列 widget key 字串**：這些是測試用的內部選擇器、非公開 API，Issue 3 既有測試套件已大量依賴這些字面字串，重新命名純粹是命名一致性的美觀考量、不影響任何功能正確性，全面重新命名會在已審查合併的既有測試檔案上產生大量與本 Issue 無關的 diff，違反「僅手術式修改」原則，故保留不動。

**Tech Stack：** Flutter／Dart、Microsoft Graph API v1.0（`https://graph.microsoft.com/v1.0/me/drive/`，REST，`http` 套件直接呼叫，非官方 SDK，比照 `GoogleDriveStorageClient` 既有慣例）、`OneDriveOAuthClient.ensureValidAccessToken()`（Issue 2 既有，取得 Bearer token）。

**Spec：** `docs/epics/epic-29-cloud-import/spec.md`（本 Issue 對應「雲端瀏覽與下載：`CloudStorageClient`」節 OneDrive 部分）與 `docs/epics/epic-29-cloud-import/issues.md` Issue 4（`OneDriveStorageClient` 實作 `CloudStorageClient` 介面；「匯入」選單新增「從 OneDrive 匯入」項目，接上 Issue 3 已建好的共用瀏覽/下載畫面）。

## Global Constraints

- `OneDriveStorageClient` 的 `listFolder`/`downloadFile`/`fetchThumbnail` 三個方法簽章與回傳型別必須與 Issue 3 的 `CloudStorageClient` 介面（`app/lib/cloud_import/cloud_storage_client.dart`，本 Issue **不修改**這個檔案）逐字一致，`ensureValidAccessToken()` 回傳 `null` 時三個方法皆須拋出既有的 `CloudAuthRequiredException`（不新增 OneDrive 專屬的例外型別）。
- 格式過濾**不**在 Graph API `$filter` 查詢參數內做任何篩選（理由見上方 Architecture），`listFolder()` 一律取回資料夾內全部項目後，100% 交給既有 `detectCloudFileFormat()` 做用戶端過濾；非資料夾且格式判斷不通過的項目一律排除，不回傳給呼叫端（比照 Google Drive 既有行為）。
- Graph API 分頁：`@odata.nextLink`（回應 JSON 內的完整絕對 URL 字串）為 `null` 時終止迴圈；累積達 1000 筆時提前停止並標記 `truncated = true`（`_maxEntries` 常數與 Google Drive 版本相同）。
- `GoogleDriveBrowserScreen` 重新命名為 `CloudBrowserScreen`（檔案：`google_drive_browser_screen.dart` → `cloud_browser_screen.dart`；測試檔同步重新命名）——**只重新命名類別/檔案本身，不重新命名內部 `Key('google_drive_browser_...')` 系列 widget key 字串**（理由見上方 Architecture，避免對 Issue 3 既有測試套件造成大量無關 diff）。
- `OneDriveStorageClient` 真實 API 呼叫（HTTP 請求/回應解析、分頁、縮圖授權）**不做自動化測試**，留待真機/人工用真實帳號驗證（比照 `issues.md` Issue 3/4 既定測試範圍）——但 `listFolder()` 的分頁/1000 筆上限/格式過濾邏輯可用 `MockClient` 測試，比照 Issue 3 對 `GoogleDriveStorageClient.listFolder()` 的既定測試範圍延伸。
- 完成後 `flutter analyze` 必須乾淨（"No issues found!"），`flutter test` 必須全數通過、零回歸（Google Drive 既有流程不受影響）。
- 所有程式碼註解、doc comment、commit message、本計劃文件本身，一律使用正體中文（zh-TW），不得出現簡體中文。

---

## Task 1：`OneDriveStorageClient` 實作

**Files：**
- Create: `app/lib/cloud_import/onedrive_storage_client.dart`
- Test: `app/test/cloud_import/onedrive_storage_client_test.dart`

**Interfaces：**
- Consumes：Issue 3 的 `CloudStorageClient`／`CloudFolderListing`／`CloudFileEntry`／`CloudAuthRequiredException`／`detectCloudFileFormat()`，Issue 2 的 `OneDriveOAuthClient.ensureValidAccessToken()`。
- Produces：`class OneDriveStorageClient implements CloudStorageClient`，供 Task 3（貫穿注入）使用。

- [ ] **Step 1：寫入失敗的 `listFolder()` 測試**

建立 `app/test/cloud_import/onedrive_storage_client_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';

import '../support/fake_cloud_account_repository.dart';

void main() {
  late FakeCloudAccountRepository accountRepository;
  late OneDriveOAuthClient oauthClient;

  setUp(() async {
    accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.oneDrive,
      CloudAccountTokens(
        accessToken: 'valid-token',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    oauthClient = OneDriveOAuthClient(accountRepository: accountRepository);
  });

  test('未連結時 listFolder 拋出 CloudAuthRequiredException', () async {
    final unlinkedAccountRepository = FakeCloudAccountRepository();
    final unlinkedOauthClient =
        OneDriveOAuthClient(accountRepository: unlinkedAccountRepository);
    final client = OneDriveStorageClient(oauthClient: unlinkedOauthClient);

    expect(() => client.listFolder(), throwsA(isA<CloudAuthRequiredException>()));
  });

  test('folderId 為 null 時查詢 me/drive/root/children，正確解析資料夾與檔案，過濾掉不支援格式',
      () async {
    final mockClient = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer valid-token');
      expect(request.url.toString(), contains('me/drive/root/children'));
      return http.Response(
        jsonEncode({
          'value': [
            {'id': 'f1', 'name': '小說', 'folder': {'childCount': 2}},
            {
              'id': 'f2',
              'name': 'book.epub',
              'size': 1024,
              'file': {'mimeType': 'application/epub+zip'},
            },
            {
              'id': 'f3',
              'name': 'photo.jpg',
              'size': 2048,
              'file': {'mimeType': 'image/jpeg'},
            },
          ],
        }),
        200,
      );
    });
    final client =
        OneDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(listing.truncated, false);
    expect(listing.entries, hasLength(2));
    expect(listing.entries[0].isFolder, true);
    expect(listing.entries[1].format, BookFileFormat.epub);
    expect(listing.entries[1].sizeBytes, 1024);
  });

  test('指定 folderId 時查詢 me/drive/items/{id}/children', () async {
    final mockClient = MockClient((request) async {
      expect(request.url.toString(), contains('me/drive/items/folder-123/children'));
      return http.Response(jsonEncode({'value': <dynamic>[]}), 200);
    });
    final client =
        OneDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    await client.listFolder(folderId: 'folder-123');
  });

  test('有縮圖時正確帶出 medium 縮圖網址', () async {
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'value': [
            {
              'id': 'f1',
              'name': 'book.pdf',
              'size': 100,
              'file': {'mimeType': 'application/pdf'},
              'thumbnails': [
                {
                  'medium': {'url': 'https://graph.microsoft.com/thumb/f1'},
                },
              ],
            },
          ],
        }),
        200,
      );
    });
    final client =
        OneDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(listing.entries.single.thumbnailUrl, 'https://graph.microsoft.com/thumb/f1');
  });

  test('跨分頁累加，@odata.nextLink 為完整 URL 直接 GET，直到欄位不存在為止', () async {
    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      if (callCount == 1) {
        expect(request.url.toString(), contains('me/drive/root/children'));
        return http.Response(
          jsonEncode({
            '@odata.nextLink': 'https://graph.microsoft.com/v1.0/me/drive/root/children?\$skiptoken=page2',
            'value': [
              {
                'id': 'f1',
                'name': 'a.epub',
                'size': 1,
                'file': {'mimeType': 'application/epub+zip'},
              },
            ],
          }),
          200,
        );
      }
      expect(request.url.toString(), contains('skiptoken=page2'));
      return http.Response(
        jsonEncode({
          'value': [
            {
              'id': 'f2',
              'name': 'b.pdf',
              'size': 1,
              'file': {'mimeType': 'application/pdf'},
            },
          ],
        }),
        200,
      );
    });
    final client =
        OneDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(callCount, 2);
    expect(listing.entries, hasLength(2));
  });

  test('累積達 1000 筆時標記 truncated 並停止讀取後續分頁', () async {
    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      final items = List.generate(
        1000,
        (i) => {
          'id': 'f$i',
          'name': 'book$i.epub',
          'size': 1,
          'file': {'mimeType': 'application/epub+zip'},
        },
      );
      return http.Response(
        jsonEncode({
          '@odata.nextLink': 'https://graph.microsoft.com/v1.0/me/drive/root/children?\$skiptoken=page2',
          'value': items,
        }),
        200,
      );
    });
    final client =
        OneDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(listing.truncated, true);
    expect(listing.entries, hasLength(1000));
    expect(callCount, 1);
  });

  test('HTTP 非 200 回應時拋出例外', () async {
    final mockClient = MockClient((request) async => http.Response('', 403));
    final client =
        OneDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    expect(client.listFolder(), throwsException);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/cloud_import/onedrive_storage_client_test.dart`
預期：編譯失敗（`OneDriveStorageClient` 尚未定義）。

- [ ] **Step 3：實作 `OneDriveStorageClient`**

建立 `app/lib/cloud_import/onedrive_storage_client.dart`：

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cloud_storage_client.dart';
import 'onedrive_oauth_client.dart';

/// [CloudStorageClient] 的 Microsoft Graph API v1.0 實作（`issues.md`
/// Issue 4，結構比照 Issue 3 已審查通過的 `GoogleDriveStorageClient`）：
/// 直接呼叫 REST API（`https://graph.microsoft.com/v1.0/me/drive/`），
/// 不使用官方 SDK。每次呼叫皆先經 [OneDriveOAuthClient.ensureValidAccessToken]
/// 取得（必要時靜默續期後的）access token，`null` 時拋出
/// [CloudAuthRequiredException]。
///
/// **格式過濾刻意不使用 Graph OData `$filter`**（例如
/// `endswith(name,'.epub')`）在伺服器端精確篩選——雖然 Graph OData 語法
/// 理論上支援，但無法在實作當下存取真實 Graph API 驗證複合 filter
/// 表達式實際可用，為避免在未經驗證的 API 語法上下注，改採與
/// `GoogleDriveStorageClient` 相同的保守策略：取回資料夾內全部項目，
/// 100% 交給用戶端的 `detectCloudFileFormat()` 過濾。
class OneDriveStorageClient implements CloudStorageClient {
  OneDriveStorageClient({
    required OneDriveOAuthClient oauthClient,
    http.Client? httpClient,
  })  : _oauthClient = oauthClient,
        _httpClient = httpClient ?? http.Client();

  final OneDriveOAuthClient _oauthClient;
  final http.Client _httpClient;

  static const _rootChildrenEndpoint =
      'https://graph.microsoft.com/v1.0/me/drive/root/children';
  static const _itemsEndpoint = 'https://graph.microsoft.com/v1.0/me/drive/items';
  static const _maxEntries = 1000;

  @override
  Future<CloudFolderListing> listFolder({String? folderId}) async {
    final token = await _oauthClient.ensureValidAccessToken();
    if (token == null) throw CloudAuthRequiredException();

    final initialUri = Uri.parse(
      folderId == null ? _rootChildrenEndpoint : '$_itemsEndpoint/$folderId/children',
    ).replace(queryParameters: {
      '\$select': 'id,name,size,file,folder',
      '\$expand': 'thumbnails(\$select=medium)',
      '\$top': '999',
    });

    final entries = <CloudFileEntry>[];
    Uri? nextUri = initialUri;
    var truncated = false;
    do {
      final response =
          await _httpClient.get(nextUri!, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode != 200) {
        throw Exception('OneDrive 目錄讀取失敗（HTTP ${response.statusCode}）');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final items = json['value'] as List<dynamic>? ?? const [];
      for (final raw in items) {
        final item = raw as Map<String, dynamic>;
        final name = item['name'] as String? ?? '';
        final isFolder = item['folder'] != null;
        final mimeType = (item['file'] as Map<String, dynamic>?)?['mimeType'] as String?;
        final format = isFolder ? null : detectCloudFileFormat(name, mimeType);
        // 非資料夾且格式判斷不通過：不回傳給呼叫端（比照 Google Drive
        // 既有行為，見上方類別文件說明）。
        if (!isFolder && format == null) continue;
        final thumbnails = item['thumbnails'] as List<dynamic>?;
        String? thumbnailUrl;
        if (thumbnails != null && thumbnails.isNotEmpty) {
          final first = thumbnails.first as Map<String, dynamic>;
          thumbnailUrl = (first['medium'] as Map<String, dynamic>?)?['url'] as String?;
        }
        entries.add(CloudFileEntry(
          id: item['id'] as String,
          name: name,
          isFolder: isFolder,
          format: format,
          thumbnailUrl: thumbnailUrl,
          sizeBytes: item['size'] as int?,
        ));
        if (entries.length >= _maxEntries) {
          truncated = true;
          break;
        }
      }
      // Graph API 的分頁機制是完整絕對 URL 的 @odata.nextLink（不像
      // Google Drive 是不透明的 pageToken），下一頁直接 GET 這個 URL 即可。
      final nextLink = json['@odata.nextLink'] as String?;
      nextUri = truncated ? null : (nextLink != null ? Uri.parse(nextLink) : null);
    } while (nextUri != null);

    return CloudFolderListing(entries: entries, truncated: truncated);
  }

  @override
  Future<File> downloadFile(
    CloudFileEntry entry,
    String destinationPath, {
    void Function(int received, int total)? onProgress,
    CloudDownloadCancellationToken? cancellationToken,
  }) async {
    final token = await _oauthClient.ensureValidAccessToken();
    if (token == null) throw CloudAuthRequiredException();

    final file = File(destinationPath);
    IOSink? sink;
    try {
      final uri = Uri.parse('$_itemsEndpoint/${entry.id}/content');
      final request = http.Request('GET', uri)
        ..headers['Authorization'] = 'Bearer $token';
      final response = await _httpClient.send(request);
      if (response.statusCode != 200) {
        throw Exception('OneDrive 下載失敗（HTTP ${response.statusCode}）');
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      sink = file.openWrite();
      await for (final chunk in response.stream) {
        if (cancellationToken?.isCancelled ?? false) {
          throw Exception('下載已取消');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.close();
      return file;
    } catch (e) {
      // 無論失敗原因為何，皆確保檔案控制代碼先關閉再刪除（Windows 上無法
      // 刪除仍被開啟的檔案），比照 GoogleDriveStorageClient 既有做法。
      await sink?.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  @override
  Future<Uint8List> fetchThumbnail(String thumbnailUrl) async {
    final token = await _oauthClient.ensureValidAccessToken();
    if (token == null) throw CloudAuthRequiredException();
    final response = await _httpClient.get(
      Uri.parse(thumbnailUrl),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception('縮圖載入失敗（HTTP ${response.statusCode}）');
    }
    return response.bodyBytes;
  }
}
```

- [ ] **Step 4：執行測試確認通過**

執行：`flutter test test/cloud_import/onedrive_storage_client_test.dart`
預期：全數 PASS。

- [ ] **Step 5：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS。

- [ ] **Step 6：Commit**

```bash
git add app/lib/cloud_import/onedrive_storage_client.dart app/test/cloud_import/onedrive_storage_client_test.dart
git commit -m "feat(epic-29): Issue 4——OneDriveStorageClient（Microsoft Graph API 瀏覽/下載/縮圖）"
```

---

## Task 2：`GoogleDriveBrowserScreen` 重新命名為通用的 `CloudBrowserScreen`

**Files：**
- Rename: `app/lib/screens/google_drive_browser_screen.dart` → `app/lib/screens/cloud_browser_screen.dart`
- Rename: `app/test/screens/google_drive_browser_screen_test.dart` → `app/test/screens/cloud_browser_screen_test.dart`
- Modify: `app/lib/screens/library_screen.dart`

**Interfaces：**
- Consumes：Issue 3 的 `CloudStorageClient`／`CloudDownloadQueueDialog`。
- Produces：`class CloudBrowserScreen extends StatefulWidget`（原 `GoogleDriveBrowserScreen`，公開建構參數與內部 widget key 字串**完全不變**，只有類別/檔案名稱改變），供 Task 3 的「從 OneDrive 匯入」選單項目與既有「從 Google Drive 匯入」選單項目共用。

- [ ] **Step 1：重新命名檔案**

```bash
git mv app/lib/screens/google_drive_browser_screen.dart app/lib/screens/cloud_browser_screen.dart
git mv app/test/screens/google_drive_browser_screen_test.dart app/test/screens/cloud_browser_screen_test.dart
```

- [ ] **Step 2：更新 `cloud_browser_screen.dart` 內的類別名稱與文件註解**

在 `app/lib/screens/cloud_browser_screen.dart` 找到：

```dart
/// Google Drive 雲端匯入瀏覽畫面（epic-29-cloud-import Issue 3，spec.md
/// 「UI 落地位置」）：逐層資料夾導覽（不做搜尋）、封面縮圖（含載入佔位符
/// 與記憶體快取）、單選/多選勾選檔案、可選分類，確認匯入後交給
/// [CloudDownloadQueueDialog] 序列下載＋匯入。畫面本身只依賴
/// [CloudStorageClient] 介面，Issue 4（OneDrive）注入
/// `OneDriveStorageClient` 即可直接沿用，不需要重新設計 UI（比照
/// `RemoteCatalogScreen` 對 `OpdsClient` 的既有設計原則）。刻意不含重複
/// 匯入偵測（Issue 5 的範圍）。
class GoogleDriveBrowserScreen extends StatefulWidget {
  final CloudStorageClient client;
  final LibraryRepository libraryRepository;
  final BookImportService importService;

  /// `null` 代表瀏覽雲端硬碟根目錄；非 `null` 時瀏覽指定資料夾（點擊
  /// [CloudFileEntry.isFolder] 為 `true` 的項目下鑽時使用）。
  final String? folderId;

  /// AppBar 標題，`null` 時使用預設「Google Drive」。
  final String? title;

  const GoogleDriveBrowserScreen({
    super.key,
    required this.client,
    required this.libraryRepository,
    required this.importService,
    this.folderId,
    this.title,
  });

  @override
  State<GoogleDriveBrowserScreen> createState() =>
      _GoogleDriveBrowserScreenState();
}

class _GoogleDriveBrowserScreenState extends State<GoogleDriveBrowserScreen> {
```

改為：

```dart
/// 雲端匯入瀏覽畫面（epic-29-cloud-import Issue 3 建置、Issue 4 泛化為
/// Google Drive／OneDrive 共用，原名 `GoogleDriveBrowserScreen`——沿用
/// Issue 2 把 `_buildGoogleDriveTile()` 泛化為 `_buildProviderTile()` 的
/// 既有先例，用一個寫死 provider 名稱的類別瀏覽另一個 provider 是誤導性
/// 命名，故重新命名）：逐層資料夾導覽（不做搜尋）、封面縮圖（含載入佔位符
/// 與記憶體快取）、單選/多選勾選檔案、可選分類，確認匯入後交給
/// [CloudDownloadQueueDialog] 序列下載＋匯入。畫面本身只依賴
/// [CloudStorageClient] 介面，注入 `GoogleDriveStorageClient` 或
/// `OneDriveStorageClient` 皆可直接沿用，不需要重新設計 UI（比照
/// `RemoteCatalogScreen` 對 `OpdsClient` 的既有設計原則）。刻意不含重複
/// 匯入偵測（Issue 5 的範圍）。**內部 `Key('google_drive_browser_...')`
/// 系列 widget key 字串刻意維持原樣未重新命名**——單純內部測試選擇器、
/// 非公開 API，重新命名對正確性無益處，只會在 Issue 3 既有測試套件產生
/// 大量無關 diff。
class CloudBrowserScreen extends StatefulWidget {
  final CloudStorageClient client;
  final LibraryRepository libraryRepository;
  final BookImportService importService;

  /// 【審查修正 review-plan-issue-4.md Critical #1】原本 Issue 3 版本
  /// 在 `_startDownload()` 內把 `BookSource.googleDrive` 寫死，泛化成
  /// `CloudBrowserScreen` 後若不新增這個欄位，OneDrive 匯入的書籍會被
  /// 誤記為 `BookSource.googleDrive`，破壞資料正確性且讓 Issue 5 未來的
  /// `findByCloudFileId(BookSource.oneDrive, ...)` 重複偵測永遠查無結果。
  /// 呼叫端必須明確傳入對應的 provider。
  final BookSource source;

  /// `null` 代表瀏覽雲端硬碟根目錄；非 `null` 時瀏覽指定資料夾（點擊
  /// [CloudFileEntry.isFolder] 為 `true` 的項目下鑽時使用）。
  final String? folderId;

  /// AppBar 標題，`null` 時使用預設「Google Drive」（呼叫端瀏覽 OneDrive
  /// 時應明確傳入 `title: 'OneDrive'` 覆蓋這個預設值）。
  final String? title;

  const CloudBrowserScreen({
    super.key,
    required this.client,
    required this.libraryRepository,
    required this.importService,
    required this.source,
    this.folderId,
    this.title,
  });

  @override
  State<CloudBrowserScreen> createState() => _CloudBrowserScreenState();
}

class _CloudBrowserScreenState extends State<CloudBrowserScreen> {
```

找到 `_startDownload()` 內建構 `CloudDownloadQueueDialog` 的地方：

```dart
  Future<void> _startDownload() async {
    final selected = _entries.where((e) => _selectedIds.contains(e.id)).toList();
    if (selected.isEmpty) return;
    final folderName =
        _selectedGroupName == BookGroup.uncategorized ? null : _selectedGroupName;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CloudDownloadQueueDialog(
        entries: selected,
        client: widget.client,
        importService: widget.importService,
        source: BookSource.googleDrive,
        folderName: folderName,
      ),
    );
    if (!mounted) return;
    setState(() => _selectedIds.clear());
  }
```

改為（`source: BookSource.googleDrive` 改為 `source: widget.source`）：

```dart
  Future<void> _startDownload() async {
    final selected = _entries.where((e) => _selectedIds.contains(e.id)).toList();
    if (selected.isEmpty) return;
    final folderName =
        _selectedGroupName == BookGroup.uncategorized ? null : _selectedGroupName;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CloudDownloadQueueDialog(
        entries: selected,
        client: widget.client,
        importService: widget.importService,
        source: widget.source,
        folderName: folderName,
      ),
    );
    if (!mounted) return;
    setState(() => _selectedIds.clear());
  }
```

找到 `build()` 內載入中/需要重新登入的區塊：

```dart
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('google_drive_browser_loading_indicator'),
              ),
            )
          : _needsReauth
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '登入已過期，請至「設定」重新連結 Google Drive 帳號',
                      key: Key('google_drive_browser_reauth_text'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
```

改為（【審查修正 review-plan-issue-4.md Important #2】文案改為依 `widget.title` 動態組成，`Center`／`Padding`／`Text` 因此不能再是編譯期常數，移除對應的 `const`）：

```dart
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('google_drive_browser_loading_indicator'),
              ),
            )
          : _needsReauth
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '登入已過期，請至「設定」重新連結 ${widget.title ?? '雲端'} 帳號',
                      key: const Key('google_drive_browser_reauth_text'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
```

找到 `_openSubfolder()` 內遞迴建構的地方：

```dart
  void _openSubfolder(CloudFileEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => GoogleDriveBrowserScreen(
        client: widget.client,
        libraryRepository: widget.libraryRepository,
        importService: widget.importService,
        folderId: entry.id,
        title: entry.name,
      ),
    ));
  }
```

改為（一併轉發 `source: widget.source`，否則下鑽進資料夾後 `source` 會遺失，等同重現 Critical #1 同一個問題）：

```dart
  void _openSubfolder(CloudFileEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => CloudBrowserScreen(
        client: widget.client,
        libraryRepository: widget.libraryRepository,
        importService: widget.importService,
        source: widget.source,
        folderId: entry.id,
        title: entry.name,
      ),
    ));
  }
```

- [ ] **Step 3：更新測試檔案內的類別名稱**

在 `app/test/screens/cloud_browser_screen_test.dart` 找到：

```dart
import 'package:elinkbook/screens/google_drive_browser_screen.dart';
```

改為：

```dart
import 'package:elinkbook/screens/cloud_browser_screen.dart';
```

找到 `pumpScreen` helper 內的建構呼叫：

```dart
      home: GoogleDriveBrowserScreen(
        client: client,
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        importService: importService ?? FakeBookImportService(),
        folderId: folderId,
      ),
```

改為（【計劃自我審查補充】`CloudBrowserScreen.source` 是新增的必填欄位，
若只重新命名類別而不補上這個參數，本檔案會編譯失敗；既有測試皆針對
Google Drive 情境撰寫，故固定傳入 `BookSource.googleDrive`）：

```dart
      home: CloudBrowserScreen(
        client: client,
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        importService: importService ?? FakeBookImportService(),
        source: BookSource.googleDrive,
        folderId: folderId,
      ),
```

- [ ] **Step 4：更新 `library_screen.dart` 內的參照**

在 `app/lib/screens/library_screen.dart` 找到：

```dart
import 'google_drive_browser_screen.dart';
```

改為：

```dart
import 'cloud_browser_screen.dart';
```

找到 `_openGoogleDriveBrowser()`：

```dart
  void _openGoogleDriveBrowser(CloudStorageClient client) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (context) => GoogleDriveBrowserScreen(
            client: client,
            libraryRepository: widget.repository,
            importService: widget.importService,
          ),
        ))
```

改為（【審查修正 review-plan-issue-4.md Critical #1】`CloudBrowserScreen.source`
新增為必填欄位後，這個既有呼叫點若不補上 `source`，`flutter analyze`
會直接編譯失敗；補上 `source: BookSource.googleDrive` 讓 Google Drive
匯入的書籍繼續正確標記來源）：

```dart
  void _openGoogleDriveBrowser(CloudStorageClient client) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (context) => CloudBrowserScreen(
            client: client,
            libraryRepository: widget.repository,
            importService: widget.importService,
            source: BookSource.googleDrive,
          ),
        ))
```

- [ ] **Step 5：執行測試確認通過**

執行：`flutter test test/screens/cloud_browser_screen_test.dart test/screens/library_screen_test.dart`
預期：全數 PASS（純重新命名，零行為變化，`Key` 字串未變動故既有測試斷言不需要修改）。

- [ ] **Step 6：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS。

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/cloud_browser_screen.dart app/lib/screens/google_drive_browser_screen.dart app/test/screens/cloud_browser_screen_test.dart app/test/screens/google_drive_browser_screen_test.dart app/lib/screens/library_screen.dart
git commit -m "refactor(epic-29): Issue 4——GoogleDriveBrowserScreen 重新命名為通用 CloudBrowserScreen"
```

---

## Task 3：貫穿注入（「匯入」選單新增「從 OneDrive 匯入」＋`LibraryScreen`→`ElinkBookApp`→`main.dart`）

**Files：**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `OneDriveStorageClient`，Task 2 的 `CloudBrowserScreen`。
- Produces：`LibraryScreen`／`ElinkBookApp` 新增可選具名參數 `oneDriveStorageClient`，`main.dart` 正式組裝真實實例；「匯入」選單新增「從 OneDrive 匯入」項目。

- [ ] **Step 1：寫入失敗的「從 OneDrive 匯入」選單測試**

在 `app/test/screens/library_screen_test.dart` 找到既有「從 Google Drive 匯入」相關測試（搜尋 `library_import_google_drive_option`），在其後新增對等的兩則測試：

```dart

    testWidgets('oneDriveStorageClient 為 null 時「從 OneDrive 匯入」選項停用', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            repository: FakeLibraryRepository(),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('library_import_button')));
      await tester.pumpAndSettle();

      final option = tester.widget<PopupMenuItem<void>>(
        find.byKey(const Key('library_import_onedrive_option')),
      );
      expect(option.enabled, false);
    });

    testWidgets('提供 oneDriveStorageClient 時點擊「從 OneDrive 匯入」導航至 CloudBrowserScreen',
        (tester) async {
      final client = FakeCloudStorageClient();
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            repository: FakeLibraryRepository(),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
            oneDriveStorageClient: client,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('library_import_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_import_onedrive_option')));
      await tester.pumpAndSettle();

      expect(find.text('OneDrive'), findsOneWidget);
    });
```

**【審查修正 review-plan-issue-4.md Important #3】** 原版計劃誤植了一個
本測試檔不存在的共用 helper `pumpLibraryScreen`，會直接導致
`Undefined name 'pumpLibraryScreen'` 編譯錯誤；上方已改為本檔案實際使用的
`tester.pumpWidget(MaterialApp(home: LibraryScreen(...)))` 標準寫法（比照同檔案內
既有測試的建構方式），`prefsManager`／`FakeLibraryRepository`／
`FakeBookImportService` 均為本測試檔既有變數/類別，直接沿用即可。

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/screens/library_screen_test.dart --plain-name "OneDrive"`
預期：編譯失敗（`LibraryScreen` 沒有 `oneDriveStorageClient` 具名參數，`library_import_onedrive_option` 不存在）。

- [ ] **Step 3：`LibraryScreen` 新增參數與匯入選單項目**

在 `app/lib/screens/library_screen.dart` 找到 import 區塊：

```dart
import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/cloud_storage_client.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../library/book_content_fingerprint.dart';
```

改為：

```dart
import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/cloud_storage_client.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../library/book_content_fingerprint.dart';
```

（此區塊本身不需要新增 import——`OneDriveStorageClient` 型別只在 `main.dart` 組裝時用到，`LibraryScreen` 只需要 `CloudStorageClient` 抽象型別，已存在。）

找到欄位宣告：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final CloudStorageClient? googleDriveStorageClient;
  final RemoteServerRepository? remoteServerRepository;
```

改為：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final CloudStorageClient? googleDriveStorageClient;
  final CloudStorageClient? oneDriveStorageClient;
  final RemoteServerRepository? remoteServerRepository;
```

找到建構子內：

```dart
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.googleDriveStorageClient,
    this.remoteServerRepository,
```

改為：

```dart
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.googleDriveStorageClient,
    this.oneDriveStorageClient,
    this.remoteServerRepository,
```

找到分類篩選畫面的自我遞迴導航點（`_openGroupFilteredView` 內）：

```dart
              cloudAccountRepository: widget.cloudAccountRepository,
              googleDriveOAuthClient: widget.googleDriveOAuthClient,
              oneDriveOAuthClient: widget.oneDriveOAuthClient,
              googleDriveStorageClient: widget.googleDriveStorageClient,
```

改為：

```dart
              cloudAccountRepository: widget.cloudAccountRepository,
              googleDriveOAuthClient: widget.googleDriveOAuthClient,
              oneDriveOAuthClient: widget.oneDriveOAuthClient,
              googleDriveStorageClient: widget.googleDriveStorageClient,
              oneDriveStorageClient: widget.oneDriveStorageClient,
```

找到「匯入」`PopupMenuButton` 的 `itemBuilder`（Google Drive 項目之後）：

```dart
            PopupMenuItem<void>(
              key: const Key('library_import_google_drive_option'),
              enabled: widget.googleDriveStorageClient != null,
              onTap: widget.googleDriveStorageClient == null
                  ? null
                  : () => _openGoogleDriveBrowser(widget.googleDriveStorageClient!),
              child: const Text('從 Google Drive 匯入'),
            ),
          ],
        ),
```

改為：

```dart
            PopupMenuItem<void>(
              key: const Key('library_import_google_drive_option'),
              enabled: widget.googleDriveStorageClient != null,
              onTap: widget.googleDriveStorageClient == null
                  ? null
                  : () => _openGoogleDriveBrowser(widget.googleDriveStorageClient!),
              child: const Text('從 Google Drive 匯入'),
            ),
            PopupMenuItem<void>(
              key: const Key('library_import_onedrive_option'),
              enabled: widget.oneDriveStorageClient != null,
              onTap: widget.oneDriveStorageClient == null
                  ? null
                  : () => _openOneDriveBrowser(widget.oneDriveStorageClient!),
              child: const Text('從 OneDrive 匯入'),
            ),
          ],
        ),
```

在 `_openGoogleDriveBrowser()` 方法結尾（`}` 之後）新增新方法：

```dart

  void _openOneDriveBrowser(CloudStorageClient client) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (context) => CloudBrowserScreen(
            client: client,
            libraryRepository: widget.repository,
            importService: widget.importService,
            source: BookSource.oneDrive,
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

【審查修正 review-plan-issue-4.md Critical #1】`CloudBrowserScreen.source`
新增為必填欄位後，這裡是唯一真正建立 OneDrive 專屬畫面實例的地方，須明確傳入
`source: BookSource.oneDrive`，否則 OneDrive 匯入的書籍會被誤記錄為
`BookSource.googleDrive`（見上方 Task 2 Step 2 的欄位定義與 Critical #1 說明）。

- [ ] **Step 4：執行測試確認通過**

執行：`flutter test test/screens/library_screen_test.dart`
預期：全數 PASS。

- [ ] **Step 5：`main.dart` 組裝真實實例並貫穿 `ElinkBookApp`**

在 `app/lib/main.dart` 找到：

```dart
import 'cloud_import/cloud_account_repository.dart';
import 'cloud_import/cloud_storage_client.dart';
import 'cloud_import/google_drive_oauth_client.dart';
import 'cloud_import/google_drive_storage_client.dart';
import 'cloud_import/onedrive_oauth_client.dart';
import 'cloud_import/secure_storage_cloud_account_repository.dart';
```

改為：

```dart
import 'cloud_import/cloud_account_repository.dart';
import 'cloud_import/cloud_storage_client.dart';
import 'cloud_import/google_drive_oauth_client.dart';
import 'cloud_import/google_drive_storage_client.dart';
import 'cloud_import/onedrive_oauth_client.dart';
import 'cloud_import/onedrive_storage_client.dart';
import 'cloud_import/secure_storage_cloud_account_repository.dart';
```

找到：

```dart
  // epic-29-cloud-import Issue 3：Google Drive 瀏覽＋下載。無內部可變的
  // session 狀態（不像 OpdsHttpClient 的 _visitedFeedUrls），單一共用
  // 實例即可，不需要比照 createOpdsClient 那樣的工廠函式。
  final CloudStorageClient googleDriveStorageClient =
      GoogleDriveStorageClient(oauthClient: googleDriveOAuthClient);
```

改為：

```dart
  // epic-29-cloud-import Issue 3/4：Google Drive／OneDrive 瀏覽＋下載。
  // 皆無內部可變的 session 狀態（不像 OpdsHttpClient 的
  // _visitedFeedUrls），單一共用實例即可，不需要比照 createOpdsClient
  // 那樣的工廠函式。
  final CloudStorageClient googleDriveStorageClient =
      GoogleDriveStorageClient(oauthClient: googleDriveOAuthClient);
  final CloudStorageClient oneDriveStorageClient =
      OneDriveStorageClient(oauthClient: oneDriveOAuthClient);
```

找到 `runApp(ElinkBookApp(...))` 內：

```dart
      oneDriveOAuthClient: oneDriveOAuthClient,
      googleDriveStorageClient: googleDriveStorageClient,
```

改為：

```dart
      oneDriveOAuthClient: oneDriveOAuthClient,
      googleDriveStorageClient: googleDriveStorageClient,
      oneDriveStorageClient: oneDriveStorageClient,
```

找到 `ElinkBookApp` 的欄位宣告：

```dart
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final CloudStorageClient? googleDriveStorageClient;
```

改為：

```dart
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final CloudStorageClient? googleDriveStorageClient;
  final CloudStorageClient? oneDriveStorageClient;
```

找到 `ElinkBookApp` 建構子內：

```dart
    this.oneDriveOAuthClient,
    this.googleDriveStorageClient,
```

改為：

```dart
    this.oneDriveOAuthClient,
    this.googleDriveStorageClient,
    this.oneDriveStorageClient,
```

找到 `build()` 內 `LibraryScreen(...)` 建構呼叫點：

```dart
        oneDriveOAuthClient: widget.oneDriveOAuthClient,
        googleDriveStorageClient: widget.googleDriveStorageClient,
```

改為：

```dart
        oneDriveOAuthClient: widget.oneDriveOAuthClient,
        googleDriveStorageClient: widget.googleDriveStorageClient,
        oneDriveStorageClient: widget.oneDriveStorageClient,
```

- [ ] **Step 6：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS。

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-29): Issue 4——貫穿注入 OneDriveStorageClient 至匯入選單"
```

---

## Self-Review（撰寫計劃時的自我檢查記錄）

**1. Spec 涵蓋範圍檢查：**
- `issues.md` Issue 4「What to build」兩項（`OneDriveStorageClient` 實作 `CloudStorageClient` 介面；「匯入」選單新增項目接上 Issue 3 共用瀏覽/下載畫面）→ Task 1（第一項）、Task 2/3（第二項——Task 2 先泛化畫面類別名稱，Task 3 才是實際新增選單項目與貫穿注入）逐一對應涵蓋。
- `issues.md` Issue 4「單元測試要求」兩項（既有 `FakeCloudStorageClient` 驅動的瀏覽畫面 widget test 天然涵蓋 OneDrive；`OneDriveStorageClient` 真實 API 邏輯不做自動化測試）→ Task 2（畫面泛化後既有 widget test 零回歸，天然涵蓋兩個 provider）、Task 1 Global Constraints（`listFolder()` 分頁/截斷/過濾邏輯仍用 `MockClient` 測試，超出 issue 字面最低要求但比照 Issue 3 既定延伸範圍）逐一對應涵蓋。
- `issues.md` Issue 4「驗收標準」的「Google Drive 既有流程不受影響（零回歸）」→ Task 2 Step 5-6、Task 3 Step 4/6 皆執行完整 `flutter test` 確認零回歸涵蓋。

**2. 佔位符掃描：** 全文檢查過，所有 Step 皆含完整可執行的程式碼區塊。Task 3 Step 1 提及「依實際簽章新增...呼叫」——這是對既有測試檔案 `pumpLibraryScreen` helper 簽章的合理不確定性揭露（比照 Issue 3 計劃自我審查時的既有慣例，不是佔位符）。

**3. 型別一致性檢查：** `OneDriveStorageClient` 的三個方法簽章與 Task 1 定義的 `CloudStorageClient` 介面（Issue 3 既有）完全一致；`CloudBrowserScreen`（Task 2 重新命名後）在 Task 3 的兩個建構呼叫點（`_openGoogleDriveBrowser()`／新增的 `_openOneDriveBrowser()`）皆使用相同的建構參數形狀；`LibraryScreen`／`ElinkBookApp` 的 `oneDriveStorageClient` 具名參數命名與型別（可選、nullable，`CloudStorageClient?`）在 Task 3 兩處貫穿注入與既有 `googleDriveStorageClient` 完全對稱一致。
