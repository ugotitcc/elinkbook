# Epic 29 Issue 3：Google Drive 瀏覽＋匯入（單/多檔＋分類選擇）實作計劃

> **給執行者：** 本計劃必須搭配 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行。每個 Step 用 checkbox（`- [ ]`）追蹤，完成後改為 `- [x]`。

**Goal：** 讓使用者能在「匯入」選單選擇「從 Google Drive 匯入」，逐層瀏覽已連結帳號的雲端硬碟資料夾、勾選單/多個支援格式的檔案、選擇分類，一次完成「瀏覽→勾選→下載→匯入圖書庫」，是第一個讓使用者實際「從雲端匯入一本書」的完整可展示切片。

**Architecture：** 新增 `CloudStorageClient` 抽象介面（`app/lib/cloud_import/cloud_storage_client.dart`），是整個瀏覽＋下載 UX 唯一依賴的邊界，比照 `epic-30-calibre-remote-library` 的 `OpdsClient`／`RemoteCatalogScreen` 既有設計原則（畫面只認識介面，不知道底層是哪個 provider）——`GoogleDriveStorageClient` 是第一個實作，Issue 4 的 `OneDriveStorageClient` 沿用同一套 `GoogleDriveBrowserScreen`／`CloudDownloadQueueDialog` 不需要重新設計 UI。下載＋落地邏輯（`downloadCloudFileToTempFile`／`promoteCloudFileToPermanent`）刻意獨立於 `epic-30` 的 `remote/remote_book_downloader.dart` 之外、寫入獨立的 `cloud_import_books/` 目錄——`CONTEXT.md`「雲端匯入來源帳號」與「遠端書庫」是兩個不同概念，不共用落地目錄，即使兩段程式碼結構相似也不合併（避免動到 `epic-30` 已審查合併的既有程式碼，比照 Issue 2 對 `GoogleDriveOAuthClient`／`OneDriveOAuthClient` 不合併的既定原則）。刻意不含重複匯入偵測（Issue 5 的範圍）與行動數據警示（Issue 6 的範圍），本 Issue 只交付「瀏覽→勾選→下載→匯入」主流程本身。

**Tech Stack：** Flutter／Dart、Google Drive API v3（`https://www.googleapis.com/drive/v3/files`，REST，`http` 套件直接呼叫，非官方 SDK）、`GoogleDriveOAuthClient.ensureValidAccessToken()`（Issue 1 既有，取得 Bearer token）。

**Spec：** `docs/epics/epic-29-cloud-import/spec.md`（Architecting 階段產出，本 Issue 對應「雲端瀏覽與下載：`CloudStorageClient`」「既有匯入管線擴充」「UI 落地位置」三節，已通過 `reviews/review-spec.md` 審查修訂）。`spec.md` 內 `CloudStorageClient`／`CloudFileEntry` 為決策草圖、非最終原始碼（spec.md 原文自述），本計劃在下方 Global Constraints 記錄相對於草圖的具體修訂與理由。

## Global Constraints

- `CloudStorageClient.listFolder()` 相對 spec.md 決策草圖的修訂：草圖回傳 `Future<List<CloudFileEntry>>`，本計劃改回傳 `Future<CloudFolderListing>`（`{ entries, truncated }` 小型包裝類別）——草圖沒有交代「超過 1000 筆時如何提示」這個 spec.md 已明確要求的行為要如何傳遞給呼叫端，加一個 `truncated` 布林欄位是最小必要修訂。
- 格式過濾機制：伺服器端 Google Drive API `q` 查詢先做粗篩（資料夾恆納入；EPUB/PDF/TXT 用標準 MIME type 精確比對；AZW3/CBZ/MD 沒有標準 MIME type，用 `name contains` 子字串粗篩縮小結果集），`detectCloudFileFormat()`（純 Dart 函式，可獨立單元測試）再做一次精確判斷過濾掉粗篩的誤判（例如 `name contains '.md'` 會誤命中 `notes.mdx`），只有精確判斷通過的檔案才會出現在 `CloudFolderListing.entries` 內——不支援格式的檔案完全不會回傳給呼叫端，不是回傳後在 UI 置灰。
- `detectCloudFileFormat()` 刻意放在 `cloud_storage_client.dart`（介面所在檔案，非 `google_drive_storage_client.dart`）——EPUB/PDF/TXT 的標準 MIME type 是跨 provider 通用的（非 Google 專屬），供 Issue 4 的 `OneDriveStorageClient` 共用，避免重寫一份。
- `downloadCloudFileToTempFile()`／`promoteCloudFileToPermanent()`（`app/lib/cloud_import/cloud_book_downloader.dart`）刻意**不**重用／修改 `app/lib/remote/remote_book_downloader.dart`（`epic-30` 已審查合併的既有程式碼）——兩者結構相似是巧合（同樣的「暫存→落地」模式），語意上服務不同概念，各自獨立維護；但可以重用 `remote/opds_client.dart` 內與 provider 無關的純函式 `fileExtensionFor(BookFileFormat)`（純粹依格式回傳副檔名字串，無 OPDS 特定邏輯，重寫一份是不必要的重複）。
- `GoogleDriveStorageClient` 真實 API 呼叫（HTTP 請求/回應解析、分頁、縮圖授權）**不做自動化測試**，留待真機/人工用真實帳號驗證（比照 `issues.md` Issue 3 既定測試範圍，以及本專案對 `OpdsHttpClient` 的既有先例）——但 `listFolder()` 的分頁/1000 筆上限/格式過濾邏輯可用 `MockClient` 測試（不涉及真實網路/OAuth 瀏覽器流程），比照 Issue 1/2 對 `ensureValidAccessToken()` 的既定測試範圍延伸。
- 刻意不含重複匯入偵測（Issue 5 範圍）與行動數據下載警示（Issue 6 範圍）——`CloudDownloadQueueDialog` 只負責序列下載＋落地＋匯入，未來 Issue 5/6 會在既有的 `_downloadOne()`／畫面選檔流程插入新的檢查點，本計劃不預先設計那些擴充點（YAGNI，避免猜錯介面形狀）。
- 完成後 `flutter analyze` 必須乾淨（"No issues found!"），`flutter test` 必須全數通過、零回歸。
- 所有程式碼註解、doc comment、commit message、本計劃文件本身，一律使用正體中文（zh-TW），不得出現簡體中文。

---

## Task 1：`CloudStorageClient` 抽象介面＋型別＋`FakeCloudStorageClient`

**Files：**
- Create: `app/lib/cloud_import/cloud_storage_client.dart`
- Create: `app/test/support/fake_cloud_storage_client.dart`
- Test: `app/test/cloud_import/cloud_storage_client_test.dart`

**Interfaces：**
- Produces：
  - `abstract class CloudStorageClient { Future<CloudFolderListing> listFolder({String? folderId}); Future<File> downloadFile(CloudFileEntry entry, String destinationPath, {onProgress, cancellationToken}); Future<Uint8List> fetchThumbnail(String thumbnailUrl); }`
  - `class CloudFolderListing { final List<CloudFileEntry> entries; final bool truncated; }`
  - `class CloudFileEntry { final String id; final String name; final bool isFolder; final BookFileFormat? format; final String? thumbnailUrl; final int? sizeBytes; }`
  - `class CloudDownloadCancellationToken { bool get isCancelled; void cancel(); }`
  - `class CloudAuthRequiredException implements Exception {}`
  - `BookFileFormat? detectCloudFileFormat(String name, String? mimeType)`
  - `class FakeCloudStorageClient implements CloudStorageClient`（供 Task 2/3/4 測試使用）

- [ ] **Step 1：寫入失敗的 `detectCloudFileFormat()` 測試**

建立 `app/test/cloud_import/cloud_storage_client_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';

void main() {
  test('依標準 MIME type 判斷 EPUB/PDF/TXT', () {
    expect(detectCloudFileFormat('book', 'application/epub+zip'), BookFileFormat.epub);
    expect(detectCloudFileFormat('book', 'application/pdf'), BookFileFormat.pdf);
    expect(detectCloudFileFormat('book', 'text/plain'), BookFileFormat.txt);
  });

  test('無標準 MIME type 時退回副檔名判斷 AZW3/CBZ/MD', () {
    expect(detectCloudFileFormat('book.azw3', 'application/octet-stream'), BookFileFormat.azw3);
    expect(detectCloudFileFormat('book.cbz', 'application/octet-stream'), BookFileFormat.cbz);
    expect(detectCloudFileFormat('notes.md', 'application/octet-stream'), BookFileFormat.md);
  });

  test('MIME type 為 null 時同樣退回副檔名判斷', () {
    expect(detectCloudFileFormat('book.epub', null), BookFileFormat.epub);
  });

  test('副檔名子字串誤判（例如 .mdx）不會被判定為支援格式', () {
    expect(detectCloudFileFormat('notes.mdx', 'application/octet-stream'), isNull);
  });

  test('完全不支援的格式回傳 null', () {
    expect(detectCloudFileFormat('photo.jpg', 'image/jpeg'), isNull);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/cloud_import/cloud_storage_client_test.dart`
預期：編譯失敗（`cloud_storage_client.dart` 尚未存在）。

- [ ] **Step 3：建立 `CloudStorageClient` 介面與型別**

建立 `app/lib/cloud_import/cloud_storage_client.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';

import '../library/models/library_enums.dart';

/// 雲端匯入來源（Google Drive／OneDrive）瀏覽＋下載共用介面（spec.md
/// 「雲端瀏覽與下載：CloudStorageClient」），是整個雲端匯入瀏覽/下載 UX
/// 唯一依賴的邊界（seam 已與使用者確認）。`GoogleDriveBrowserScreen` 只
/// 認識這個介面，不知道底層是哪個 provider——Issue 4（OneDrive）新增
/// `OneDriveStorageClient` 實作後即可直接沿用同一套瀏覽畫面，不需要重新
/// 設計 UI（比照 `remote/opds_client.dart` 的 `OpdsClient`／
/// `RemoteCatalogScreen` 既有設計原則）。
abstract class CloudStorageClient {
  /// [folderId] 為 `null` 時列出雲端硬碟根目錄的內容。回傳清單只含資料夾
  /// 與 elinkBook 支援格式（EPUB/PDF/TXT/AZW3/CBZ/MD）的檔案——不支援格式
  /// 的檔案已被過濾掉，完全不會出現在清單內（spec.md「格式過濾」）。
  Future<CloudFolderListing> listFolder({String? folderId});

  /// 下載 [entry] 到 [destinationPath]。[onProgress] 於每個資料區塊到達時
  /// 回呼 `(received, total)`，`total` 為 0 代表伺服器未提供
  /// Content-Length。[cancellationToken] 於下載中途被 `cancel()` 時中斷
  /// 連線；下載失敗或被取消時，實作必須自行刪除 [destinationPath] 已寫入
  /// 的部分檔案，不留孤兒/半成品檔案（呼叫端不需要自己再判斷該路徑是否
  /// 還存在，比照 `remote/opds_client.dart` 的 `OpdsClient.downloadBook`
  /// 既定契約）。
  Future<File> downloadFile(
    CloudFileEntry entry,
    String destinationPath, {
    void Function(int received, int total)? onProgress,
    CloudDownloadCancellationToken? cancellationToken,
  });

  /// 取得 [thumbnailUrl] 指向的縮圖圖片位元組（部分 provider 的縮圖網址
  /// 需要與瀏覽/下載相同的授權標頭才能存取，不能直接交給
  /// `Image.network()`，故收斂為介面方法由各實作自行處理授權）。
  Future<Uint8List> fetchThumbnail(String thumbnailUrl);
}

/// 單一資料夾一次列出的結果。[truncated] 為 `true` 代表該資料夾檔案數量
/// 超過 1000 筆上限，[entries] 只包含前 1000 筆，UI 應顯示「這個資料夾
/// 檔案較多，僅顯示前 1000 筆」提示（spec.md「雲端瀏覽與下載」審查
/// Important #4 採納）。
class CloudFolderListing {
  final List<CloudFileEntry> entries;
  final bool truncated;

  const CloudFolderListing({this.entries = const [], this.truncated = false});
}

/// 一筆雲端硬碟項目（資料夾或檔案）。[format] 為 `null` 代表不支援的格式
/// （`listFolder()` 已預先過濾掉，理論上只會在 [isFolder] 為 `false` 的
/// 項目上被檢查）。
class CloudFileEntry {
  final String id;
  final String name;
  final bool isFolder;
  final BookFileFormat? format;
  final String? thumbnailUrl;
  final int? sizeBytes;

  const CloudFileEntry({
    required this.id,
    required this.name,
    required this.isFolder,
    this.format,
    this.thumbnailUrl,
    this.sizeBytes,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudFileEntry &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          isFolder == other.isFolder &&
          format == other.format &&
          thumbnailUrl == other.thumbnailUrl &&
          sizeBytes == other.sizeBytes;

  @override
  int get hashCode =>
      Object.hash(id, name, isFolder, format, thumbnailUrl, sizeBytes);
}

/// 下載中途取消的輕量信號（比照 `remote/opds_client.dart` 的
/// `OpdsDownloadCancellationToken`：本專案僅有 `http` 套件、無 `dio`，故
/// 不採用 `dio` 的 `CancelToken` 型別，自訂一個語意等價的輕量取消信號）。
class CloudDownloadCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// [CloudStorageClient] 的 access token 已過期且靜默續期失敗（例如
/// `GoogleDriveOAuthClient.ensureValidAccessToken()` 回傳 `null`）時拋出，
/// 呼叫端（`GoogleDriveBrowserScreen`）應提示使用者重新連結帳號，與其餘
/// 泛用網路/解析失敗（顯示通用「載入失敗」訊息）區分開來。
class CloudAuthRequiredException implements Exception {}

/// 依副檔名／MIME type 判斷雲端硬碟項目對應的 [BookFileFormat]，回傳
/// `null` 代表不支援的格式。EPUB/PDF/TXT 三種格式有廣泛認可的標準 MIME
/// type（跨 provider 通用，非 Google 專屬），AZW3/CBZ/MD 沒有普遍認可的
/// 標準 MIME type，一律退回副檔名判斷（spec.md「格式過濾」）。供
/// `GoogleDriveStorageClient` 與未來 Issue 4 的 `OneDriveStorageClient`
/// 共用，避免各自重寫一份判斷邏輯。
BookFileFormat? detectCloudFileFormat(String name, String? mimeType) {
  switch (mimeType) {
    case 'application/epub+zip':
      return BookFileFormat.epub;
    case 'application/pdf':
      return BookFileFormat.pdf;
    case 'text/plain':
      return BookFileFormat.txt;
  }
  final lower = name.toLowerCase();
  if (lower.endsWith('.epub')) return BookFileFormat.epub;
  if (lower.endsWith('.pdf')) return BookFileFormat.pdf;
  if (lower.endsWith('.txt')) return BookFileFormat.txt;
  if (lower.endsWith('.azw3')) return BookFileFormat.azw3;
  if (lower.endsWith('.cbz')) return BookFileFormat.cbz;
  if (lower.endsWith('.md')) return BookFileFormat.md;
  return null;
}
```

- [ ] **Step 4：執行測試確認通過**

執行：`flutter test test/cloud_import/cloud_storage_client_test.dart`
預期：全數 PASS。

- [ ] **Step 5：建立 `FakeCloudStorageClient`**

建立 `app/test/support/fake_cloud_storage_client.dart`：

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:elinkbook/cloud_import/cloud_storage_client.dart';

/// 供 widget test 使用的記憶體內 [CloudStorageClient] 假實作（比照
/// `FakeOpdsClient` 既有命名慣例）。
class FakeCloudStorageClient implements CloudStorageClient {
  /// 依 folderId（`null` 代表根目錄）預先塞入要回傳的清單。
  final Map<String?, CloudFolderListing> folderContents;

  /// 依 [CloudFileEntry.id] 預先塞入下載成功要寫入的位元組內容；未設定
  /// 的 id 呼叫 [downloadFile] 會拋出例外（模擬下載失敗）。
  final Map<String, List<int>> downloadContents;

  /// 若設定，[downloadFile] 改為等待這個 completer 完成才繼續（或拋出
  /// 例外），供測試模擬「下載中」與「使用者中途取消」情境（比照
  /// `FakeOpdsClient` 既有的 `downloadDelayCompleter` 模式）。
  Completer<void>? pendingDownloadCompleter;

  /// 記錄每次 [downloadFile] 呼叫的 entry id，供測試驗證序列下載順序。
  final List<String> downloadCalls = [];

  Uint8List? thumbnailBytes;

  FakeCloudStorageClient({
    this.folderContents = const {},
    this.downloadContents = const {},
  });

  @override
  Future<CloudFolderListing> listFolder({String? folderId}) async {
    return folderContents[folderId] ?? const CloudFolderListing();
  }

  @override
  Future<File> downloadFile(
    CloudFileEntry entry,
    String destinationPath, {
    void Function(int received, int total)? onProgress,
    CloudDownloadCancellationToken? cancellationToken,
  }) async {
    downloadCalls.add(entry.id);
    final completer = pendingDownloadCompleter;
    if (completer != null) {
      await completer.future;
    }
    if (cancellationToken?.isCancelled ?? false) {
      throw Exception('下載已取消');
    }
    final bytes = downloadContents[entry.id];
    if (bytes == null) {
      throw Exception('模擬下載失敗：${entry.id}');
    }
    final file = File(destinationPath);
    await file.writeAsBytes(bytes);
    onProgress?.call(bytes.length, bytes.length);
    return file;
  }

  @override
  Future<Uint8List> fetchThumbnail(String thumbnailUrl) async {
    return thumbnailBytes ?? Uint8List(0);
  }
}
```

- [ ] **Step 6：執行完整測試套件確認零回歸**

執行：`flutter test`
預期：全數 PASS（`FakeCloudStorageClient` 目前尚無呼叫端，僅需確認編譯成功）。

- [ ] **Step 7：Commit**

```bash
git add app/lib/cloud_import/cloud_storage_client.dart app/test/support/fake_cloud_storage_client.dart app/test/cloud_import/cloud_storage_client_test.dart
git commit -m "feat(epic-29): Issue 3——CloudStorageClient 抽象介面/detectCloudFileFormat/Fake 測試替身"
```

---

## Task 2：`GoogleDriveStorageClient` 實作

**Files：**
- Create: `app/lib/cloud_import/google_drive_storage_client.dart`
- Test: `app/test/cloud_import/google_drive_storage_client_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `CloudStorageClient`／`CloudFolderListing`／`CloudFileEntry`／`CloudAuthRequiredException`／`detectCloudFileFormat()`，Issue 1 的 `GoogleDriveOAuthClient.ensureValidAccessToken()`。
- Produces：`class GoogleDriveStorageClient implements CloudStorageClient`，供 Task 4（UI）與 Task 5（貫穿注入）使用。

- [ ] **Step 1：寫入失敗的 `listFolder()` 測試**

建立 `app/test/cloud_import/google_drive_storage_client_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/google_drive_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';

import '../support/fake_cloud_account_repository.dart';

void main() {
  late FakeCloudAccountRepository accountRepository;
  late GoogleDriveOAuthClient oauthClient;

  setUp(() async {
    accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'valid-token',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    oauthClient = GoogleDriveOAuthClient(accountRepository: accountRepository);
  });

  test('未連結時 listFolder 拋出 CloudAuthRequiredException', () async {
    final unlinkedAccountRepository = FakeCloudAccountRepository();
    final unlinkedOauthClient =
        GoogleDriveOAuthClient(accountRepository: unlinkedAccountRepository);
    final client = GoogleDriveStorageClient(oauthClient: unlinkedOauthClient);

    expect(() => client.listFolder(), throwsA(isA<CloudAuthRequiredException>()));
  });

  test('listFolder 正確解析回傳的資料夾與檔案，過濾掉不支援格式', () async {
    final mockClient = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer valid-token');
      expect(request.url.queryParameters['q'], contains("'root' in parents"));
      return http.Response(
        jsonEncode({
          'files': [
            {'id': 'f1', 'name': '小說', 'mimeType': 'application/vnd.google-apps.folder'},
            {'id': 'f2', 'name': 'book.epub', 'mimeType': 'application/epub+zip', 'size': '1024'},
            {'id': 'f3', 'name': 'photo.jpg', 'mimeType': 'image/jpeg'},
          ],
        }),
        200,
      );
    });
    final client =
        GoogleDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(listing.truncated, false);
    expect(listing.entries, hasLength(2));
    expect(listing.entries[0].isFolder, true);
    expect(listing.entries[1].format, BookFileFormat.epub);
    expect(listing.entries[1].sizeBytes, 1024);
  });

  test('listFolder 指定 folderId 時查詢對應資料夾內容', () async {
    final mockClient = MockClient((request) async {
      expect(request.url.queryParameters['q'], contains("'folder-123' in parents"));
      return http.Response(jsonEncode({'files': <dynamic>[]}), 200);
    });
    final client =
        GoogleDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    await client.listFolder(folderId: 'folder-123');
  });

  test('listFolder 跨分頁累加直到 nextPageToken 為 null', () async {
    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      if (callCount == 1) {
        expect(request.url.queryParameters.containsKey('pageToken'), false);
        return http.Response(
          jsonEncode({
            'nextPageToken': 'page2',
            'files': [
              {'id': 'f1', 'name': 'a.epub', 'mimeType': 'application/epub+zip'},
            ],
          }),
          200,
        );
      }
      expect(request.url.queryParameters['pageToken'], 'page2');
      return http.Response(
        jsonEncode({
          'files': [
            {'id': 'f2', 'name': 'b.pdf', 'mimeType': 'application/pdf'},
          ],
        }),
        200,
      );
    });
    final client =
        GoogleDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(callCount, 2);
    expect(listing.entries, hasLength(2));
  });

  test('累積達 1000 筆時標記 truncated 並停止讀取後續分頁', () async {
    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      final files = List.generate(
        1000,
        (i) => {'id': 'f$i', 'name': 'book$i.epub', 'mimeType': 'application/epub+zip'},
      );
      return http.Response(
        jsonEncode({'nextPageToken': 'page2', 'files': files}),
        200,
      );
    });
    final client =
        GoogleDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(listing.truncated, true);
    expect(listing.entries, hasLength(1000));
    expect(callCount, 1);
  });

  test('HTTP 非 200 回應時拋出例外', () async {
    final mockClient = MockClient((request) async => http.Response('', 403));
    final client =
        GoogleDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    expect(client.listFolder(), throwsException);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/cloud_import/google_drive_storage_client_test.dart`
預期：編譯失敗（`GoogleDriveStorageClient` 尚未定義）。

- [ ] **Step 3：實作 `GoogleDriveStorageClient`**

建立 `app/lib/cloud_import/google_drive_storage_client.dart`：

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cloud_storage_client.dart';
import 'google_drive_oauth_client.dart';

/// [CloudStorageClient] 的 Google Drive API v3 實作（spec.md「雲端瀏覽與
/// 下載」）：直接呼叫 REST API（`https://www.googleapis.com/drive/v3/`），
/// 不使用官方 SDK（本專案其餘雲端整合皆是直接呼叫 REST API，比照
/// `OpdsHttpClient`／`GoogleDriveOAuthClient` 既有慣例）。每次呼叫皆先
/// 經 [GoogleDriveOAuthClient.ensureValidAccessToken] 取得（必要時靜默
/// 續期後的）access token，`null` 時拋出 [CloudAuthRequiredException]。
class GoogleDriveStorageClient implements CloudStorageClient {
  GoogleDriveStorageClient({
    required GoogleDriveOAuthClient oauthClient,
    http.Client? httpClient,
  })  : _oauthClient = oauthClient,
        _httpClient = httpClient ?? http.Client();

  final GoogleDriveOAuthClient _oauthClient;
  final http.Client _httpClient;

  static const _filesEndpoint = 'https://www.googleapis.com/drive/v3/files';
  static const _maxEntries = 1000;

  @override
  Future<CloudFolderListing> listFolder({String? folderId}) async {
    final token = await _oauthClient.ensureValidAccessToken();
    if (token == null) throw CloudAuthRequiredException();

    final parent = folderId ?? 'root';
    // 伺服器端粗篩：資料夾恆納入（供逐層導覽）；EPUB/PDF/TXT 有廣泛認可
    // 的標準 MIME type，直接比對；AZW3/CBZ/MD 沒有標準 MIME type，用
    // name contains 先做粗略篩選縮小結果集（Drive API 的 `contains` 是
    // 子字串比對、非嚴格副檔名比對，可能有極少數誤判，例如
    // `notes.mdx`），精確判斷交給 detectCloudFileFormat() 做最終過濾
    // （spec.md「格式過濾」：伺服器端 MIME type 過濾 EPUB/PDF/TXT ＋
    // 用戶端副檔名過濾 AZW3/CBZ/MD）。
    final query = "'$parent' in parents and trashed = false and ("
        "mimeType = 'application/vnd.google-apps.folder' or "
        "mimeType = 'application/epub+zip' or "
        "mimeType = 'application/pdf' or "
        "mimeType = 'text/plain' or "
        "name contains '.azw3' or "
        "name contains '.cbz' or "
        "name contains '.md')";

    final entries = <CloudFileEntry>[];
    String? pageToken;
    var truncated = false;
    do {
      final uri = Uri.parse(_filesEndpoint).replace(queryParameters: {
        'q': query,
        'fields': 'nextPageToken,files(id,name,mimeType,thumbnailLink,size)',
        'pageSize': '1000',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final response =
          await _httpClient.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode != 200) {
        throw Exception('Google Drive 目錄讀取失敗（HTTP ${response.statusCode}）');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final files = json['files'] as List<dynamic>? ?? const [];
      for (final raw in files) {
        final file = raw as Map<String, dynamic>;
        final mimeType = file['mimeType'] as String?;
        final name = file['name'] as String? ?? '';
        final isFolder = mimeType == 'application/vnd.google-apps.folder';
        final format = isFolder ? null : detectCloudFileFormat(name, mimeType);
        // 非資料夾且格式判斷不通過：伺服器端粗篩的誤判，精確過濾掉、不
        // 回傳給呼叫端（見上方 query 註解）。
        if (!isFolder && format == null) continue;
        entries.add(CloudFileEntry(
          id: file['id'] as String,
          name: name,
          isFolder: isFolder,
          format: format,
          thumbnailUrl: file['thumbnailLink'] as String?,
          sizeBytes:
              file['size'] != null ? int.tryParse(file['size'] as String) : null,
        ));
        if (entries.length >= _maxEntries) {
          truncated = true;
          break;
        }
      }
      pageToken = truncated ? null : json['nextPageToken'] as String?;
    } while (pageToken != null);

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
      final uri = Uri.parse('$_filesEndpoint/${entry.id}')
          .replace(queryParameters: {'alt': 'media'});
      final request = http.Request('GET', uri)
        ..headers['Authorization'] = 'Bearer $token';
      final response = await _httpClient.send(request);
      if (response.statusCode != 200) {
        throw Exception('Google Drive 下載失敗（HTTP ${response.statusCode}）');
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
      // 刪除仍被開啟的檔案），不留孤兒/半成品檔案。
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

執行：`flutter test test/cloud_import/google_drive_storage_client_test.dart`
預期：全數 PASS。

- [ ] **Step 5：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS。

- [ ] **Step 6：Commit**

```bash
git add app/lib/cloud_import/google_drive_storage_client.dart app/test/cloud_import/google_drive_storage_client_test.dart
git commit -m "feat(epic-29): Issue 3——GoogleDriveStorageClient（Drive API v3 瀏覽/下載/縮圖）"
```

---

## Task 3：下載＋落地（`cloud_book_downloader.dart`）與 `CloudDownloadQueueDialog`

**Files：**
- Create: `app/lib/cloud_import/cloud_book_downloader.dart`
- Create: `app/lib/screens/cloud_download_queue_dialog.dart`
- Test: `app/test/screens/cloud_download_queue_dialog_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `CloudStorageClient`／`CloudFileEntry`／`CloudDownloadCancellationToken`／`FakeCloudStorageClient`，Issue 0 的 `BookImportService.importFiles(cloudFileIds: ...)`。
- Produces：
  - `Future<String> downloadCloudFileToTempFile({required CloudStorageClient client, required CloudFileEntry entry, onProgress, cancellationToken})`
  - `Future<String> promoteCloudFileToPermanent(String tempPath)`
  - `class CloudDownloadQueueDialog extends StatefulWidget { required List<CloudFileEntry> entries; required CloudStorageClient client; required BookImportService importService; required BookSource source; String? folderName; }`，供 Task 4 與未來 Issue 4（OneDrive，傳入 `source: BookSource.oneDrive`）使用。

- [ ] **Step 1：建立下載＋落地函式**

建立 `app/lib/cloud_import/cloud_book_downloader.dart`：

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../remote/opds_client.dart' show fileExtensionFor;
import 'cloud_storage_client.dart';

/// 把一筆雲端硬碟項目下載到 App 暫存目錄（epic-29-cloud-import Issue 3，
/// spec.md「暫存於專屬子目錄，UUID 命名，非平行下載」）。**不含例外
/// 清理**：[CloudStorageClient.downloadFile] 已依介面契約在下載失敗／
/// 使用者取消時自行刪除目的檔案，這裡重複清理是死碼，故意不做（比照
/// `remote/remote_book_downloader.dart` 的 `downloadToTempFile()` 既定
/// 設計）。
Future<String> downloadCloudFileToTempFile({
  required CloudStorageClient client,
  required CloudFileEntry entry,
  void Function(int received, int total)? onProgress,
  CloudDownloadCancellationToken? cancellationToken,
}) async {
  final tempDir = await getTemporaryDirectory();
  final downloadDir =
      Directory(p.join(tempDir.path, 'cloud_import_download_temp'));
  if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
  final fileName = '${const Uuid().v4()}.${fileExtensionFor(entry.format!)}';
  final tempPath = p.join(downloadDir.path, fileName);

  await client.downloadFile(
    entry,
    tempPath,
    onProgress: onProgress,
    cancellationToken: cancellationToken,
  );

  return tempPath;
}

/// 把 [tempPath] 指向的暫存檔複製到 App 永久文件目錄的
/// `cloud_import_books/` 子目錄（與 `epic-30-calibre-remote-library` 的
/// `remote_books/` 目錄語意上完全獨立——`CONTEXT.md`「雲端匯入來源帳號」
/// 與「遠端書庫」是兩個不同概念，不共用落地目錄），成功後刪除暫存檔，
/// 回傳永久檔案的絕對路徑。任何例外皆確保不留孤兒/半成品檔案，比照
/// `remote/remote_book_downloader.dart` 的 `promoteToPermanent()` 既定
/// 設計（區分「複製本身失敗」與「複製成功、只有刪暫存檔失敗」兩種失敗
/// 窗口，避免誤刪已下載成功的檔案）。
Future<String> promoteCloudFileToPermanent(String tempPath) async {
  final fileName = p.basename(tempPath);
  final docsDir = await getApplicationDocumentsDirectory();
  final permanentDir = Directory(p.join(docsDir.path, 'cloud_import_books'));
  if (!await permanentDir.exists()) await permanentDir.create(recursive: true);
  final permanentPath = p.join(permanentDir.path, fileName);
  final tempFile = File(tempPath);
  var copied = false;
  try {
    await tempFile.copy(permanentPath);
    copied = true;
    await tempFile.delete();
    return permanentPath;
  } catch (_) {
    if (!copied) {
      final leftoverPerm = File(permanentPath);
      if (await leftoverPerm.exists()) await leftoverPerm.delete();
    }
    final leftoverTemp = File(tempPath);
    if (await leftoverTemp.exists()) await leftoverTemp.delete();
    rethrow;
  }
}
```

- [ ] **Step 2：寫入失敗的 `CloudDownloadQueueDialog` widget test**

建立 `app/test/screens/cloud_download_queue_dialog_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/cloud_download_queue_dialog.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_path_provider_platform.dart';

void main() {
  late Directory tempRoot;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('cloud_download_queue_test');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempRoot.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  const entry1 = CloudFileEntry(
    id: 'file-1',
    name: '紅樓夢.epub',
    isFolder: false,
    format: BookFileFormat.epub,
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    required FakeCloudStorageClient client,
    required FakeBookImportService importService,
    List<CloudFileEntry> entries = const [entry1],
    String? folderName,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (context) => CloudDownloadQueueDialog(
                entries: entries,
                client: client,
                importService: importService,
                source: BookSource.googleDrive,
                folderName: folderName,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  Future<void> settleDownload(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('下載成功後顯示完成狀態，importFiles 正確帶入 source/cloudFileIds/folderName',
      (tester) async {
    final client = FakeCloudStorageClient(downloadContents: {
      'file-1': [1, 2, 3],
    });
    final importService = FakeBookImportService();
    await pumpDialog(tester, client: client, importService: importService, folderName: '小說');

    await settleDownload(tester);

    expect(find.byKey(const Key('cloud_download_queue_item_file-1')), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(importService.lastImportCall?.source, BookSource.googleDrive);
    expect(importService.lastImportCall?.cloudFileIds, {importService.lastImportCall!.uris.single: 'file-1'});
  });

  testWidgets('下載失敗顯示失敗狀態，可手動重試', (tester) async {
    final client = FakeCloudStorageClient(downloadContents: const {});
    final importService = FakeBookImportService();
    await pumpDialog(tester, client: client, importService: importService);

    await settleDownload(tester);

    expect(find.text('失敗'), findsOneWidget);
    expect(find.byKey(const Key('cloud_download_queue_retry_file-1')), findsOneWidget);

    // 補上這次會成功的下載內容再重試。
    client.downloadContents['file-1'] = [1, 2, 3];
    await tester.tap(find.byKey(const Key('cloud_download_queue_retry_file-1')));
    await settleDownload(tester);

    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets('下載中點擊取消後顯示已取消狀態，暫存檔不殘留', (tester) async {
    final client = FakeCloudStorageClient(downloadContents: {
      'file-1': [1, 2, 3],
    });
    client.pendingDownloadCompleter = Completer<void>();
    final importService = FakeBookImportService();
    await pumpDialog(tester, client: client, importService: importService);
    await tester.pump();

    await tester.tap(find.byKey(const Key('cloud_download_queue_cancel_file-1')));
    client.pendingDownloadCompleter!.complete();
    await settleDownload(tester);

    expect(find.text('已取消'), findsOneWidget);
    final tempDownloadDir =
        Directory('${tempRoot.path}/cloud_import_download_temp');
    expect(
      tempDownloadDir.existsSync() ? tempDownloadDir.listSync() : const [],
      isEmpty,
    );
  });
}
```

- [ ] **Step 3：執行測試確認失敗**

執行：`flutter test test/screens/cloud_download_queue_dialog_test.dart`
預期：編譯失敗（`CloudDownloadQueueDialog` 尚未定義）。

- [ ] **Step 4：實作 `CloudDownloadQueueDialog`**

建立 `app/lib/screens/cloud_download_queue_dialog.dart`：

```dart
import 'package:flutter/material.dart';

import '../cloud_import/cloud_book_downloader.dart';
import '../cloud_import/cloud_storage_client.dart';
import '../library/book_import_service.dart';
import '../library/models/library_enums.dart';

enum CloudDownloadItemStatus { pending, downloading, done, failed, cancelled }

/// 序列下載佇列對話框（epic-29-cloud-import Issue 3，spec.md「確認匯入後，
/// 多選檔案循序下載...並顯示逐項狀態」）：一本下完才下一本，逐項顯示等待
/// 中/下載中/完成/失敗/已取消狀態；下載失敗可針對單一檔案手動重試（不
/// 自動重試）；全部處理完後，把所有成功下載的檔案一次呼叫
/// [BookImportService.importFiles] 匯入圖書庫。結構比照
/// `remote_catalog_screen.dart` 的私有 `_DownloadQueueDialog`，但刻意
/// 公開（非私有）供 Issue 4（OneDrive）沿用同一個對話框、只需傳入不同的
/// [source]；刻意不含重複匯入偵測（Issue 5 的範圍）。
class CloudDownloadQueueDialog extends StatefulWidget {
  final List<CloudFileEntry> entries;
  final CloudStorageClient client;
  final BookImportService importService;
  final BookSource source;
  final String? folderName;

  const CloudDownloadQueueDialog({
    super.key,
    required this.entries,
    required this.client,
    required this.importService,
    required this.source,
    this.folderName,
  });

  @override
  State<CloudDownloadQueueDialog> createState() => _CloudDownloadQueueDialogState();
}

class _CloudDownloadQueueDialogState extends State<CloudDownloadQueueDialog> {
  late List<CloudDownloadItemStatus> _statuses;
  late List<String?> _permanentPaths;
  late List<CloudDownloadCancellationToken?> _tokens;
  bool _allSettled = false;

  @override
  void initState() {
    super.initState();
    _statuses = List.filled(widget.entries.length, CloudDownloadItemStatus.pending);
    _permanentPaths = List.filled(widget.entries.length, null);
    _tokens = List.filled(widget.entries.length, null);
    _runQueue();
  }

  Future<void> _runQueue() async {
    for (var i = 0; i < widget.entries.length; i++) {
      await _downloadOne(i);
    }
    await _importSuccessful();
    if (!mounted) return;
    setState(() => _allSettled = true);
  }

  Future<void> _downloadOne(int index) async {
    if (!mounted) return;
    setState(() => _statuses[index] = CloudDownloadItemStatus.downloading);
    final entry = widget.entries[index];
    final token = CloudDownloadCancellationToken();
    _tokens[index] = token;
    try {
      final tempPath = await downloadCloudFileToTempFile(
        client: widget.client,
        entry: entry,
        cancellationToken: token,
      );
      final permanentPath = await promoteCloudFileToPermanent(tempPath);
      if (!mounted) return;
      setState(() {
        _permanentPaths[index] = permanentPath;
        _statuses[index] = CloudDownloadItemStatus.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statuses[index] = token.isCancelled
            ? CloudDownloadItemStatus.cancelled
            : CloudDownloadItemStatus.failed;
      });
    }
  }

  Future<void> _importSuccessful() async {
    final paths = <String>[];
    final cloudFileIds = <String, String>{};
    for (var i = 0; i < widget.entries.length; i++) {
      final path = _permanentPaths[i];
      if (path == null) continue;
      paths.add(path);
      cloudFileIds[path] = widget.entries[i].id;
    }
    if (paths.isEmpty) return;
    await widget.importService.importFiles(
      paths,
      folderName: widget.folderName,
      source: widget.source,
      cloudFileIds: cloudFileIds,
    );
  }

  Future<void> _retry(int index) async {
    // 【審查 review-plan-issue-3.md Minor #1 採納】整批下載已完成時
    // _allSettled 為 true（「完成」按鈕已啟用）；若此時對單一失敗項目
    // 按重試，重試期間必須暫時關閉「完成」按鈕，避免使用者在這段窗口
    // 誤觸關閉對話框、看不到這次重試的最終結果。
    setState(() => _allSettled = false);
    await _downloadOne(index);
    if (mounted) setState(() => _allSettled = true);
    if (_statuses[index] != CloudDownloadItemStatus.done) return;
    final path = _permanentPaths[index]!;
    final entry = widget.entries[index];
    await widget.importService.importFiles(
      [path],
      folderName: widget.folderName,
      source: widget.source,
      cloudFileIds: {path: entry.id},
    );
  }

  void _cancel(int index) {
    _tokens[index]?.cancel();
  }

  String _statusLabel(CloudDownloadItemStatus status) {
    switch (status) {
      case CloudDownloadItemStatus.pending:
        return '等待中';
      case CloudDownloadItemStatus.downloading:
        return '下載中';
      case CloudDownloadItemStatus.done:
        return '完成';
      case CloudDownloadItemStatus.failed:
        return '失敗';
      case CloudDownloadItemStatus.cancelled:
        return '已取消';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('cloud_download_queue_dialog'),
      title: const Text('下載進度'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.entries.length,
          itemBuilder: (context, index) {
            final entry = widget.entries[index];
            final status = _statuses[index];
            final canRetry = status == CloudDownloadItemStatus.failed ||
                status == CloudDownloadItemStatus.cancelled;
            return ListTile(
              key: Key('cloud_download_queue_item_${entry.id}'),
              title: Text(entry.name),
              subtitle: Text(_statusLabel(status)),
              trailing: status == CloudDownloadItemStatus.downloading
                  ? IconButton(
                      key: Key('cloud_download_queue_cancel_${entry.id}'),
                      icon: const Icon(Icons.close),
                      tooltip: '取消',
                      onPressed: () => _cancel(index),
                    )
                  : canRetry
                      ? IconButton(
                          key: Key('cloud_download_queue_retry_${entry.id}'),
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
          key: const Key('cloud_download_queue_done_button'),
          onPressed: _allSettled ? () => Navigator.of(context).pop() : null,
          child: const Text('完成'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5：執行測試確認通過**

執行：`flutter test test/screens/cloud_download_queue_dialog_test.dart`
預期：全數 PASS。

- [ ] **Step 6：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS。

- [ ] **Step 7：Commit**

```bash
git add app/lib/cloud_import/cloud_book_downloader.dart app/lib/screens/cloud_download_queue_dialog.dart app/test/screens/cloud_download_queue_dialog_test.dart
git commit -m "feat(epic-29): Issue 3——雲端下載/落地函式與 CloudDownloadQueueDialog"
```

---

## Task 4：`GoogleDriveBrowserScreen` 瀏覽畫面

**Files：**
- Create: `app/lib/screens/google_drive_browser_screen.dart`
- Test: `app/test/screens/google_drive_browser_screen_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `CloudStorageClient`／`CloudFileEntry`／`CloudFolderListing`／`CloudAuthRequiredException`／`FakeCloudStorageClient`，Task 3 的 `CloudDownloadQueueDialog`，既有 `LibraryRepository.listGroups()`／`BookGroup`。
- Produces：`class GoogleDriveBrowserScreen extends StatefulWidget { required CloudStorageClient client; required LibraryRepository libraryRepository; required BookImportService importService; String? folderId; String? title; }`，供 Task 5 從「匯入」選單導航進入。

- [ ] **Step 1：寫入失敗的 widget test**

建立 `app/test/screens/google_drive_browser_screen_test.dart`：

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/google_drive_browser_screen.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_path_provider_platform.dart';

void main() {
  const folderEntry = CloudFileEntry(id: 'folder-1', name: '小說', isFolder: true);
  const fileEntryNoThumbnail = CloudFileEntry(
    id: 'file-1',
    name: '紅樓夢.epub',
    isFolder: false,
    format: BookFileFormat.epub,
  );
  const fileEntryWithThumbnail = CloudFileEntry(
    id: 'file-2',
    name: '西遊記.pdf',
    isFolder: false,
    format: BookFileFormat.pdf,
    thumbnailUrl: 'https://drive.google.com/thumbnail/2',
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeCloudStorageClient client,
    FakeLibraryRepository? libraryRepository,
    FakeBookImportService? importService,
    String? folderId,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: GoogleDriveBrowserScreen(
        client: client,
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        importService: importService ?? FakeBookImportService(),
        folderId: folderId,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('載入根目錄後顯示資料夾與格式過濾後的檔案', (tester) async {
    final client = FakeCloudStorageClient(folderContents: {
      null: const CloudFolderListing(entries: [folderEntry, fileEntryNoThumbnail]),
    });
    await pumpScreen(tester, client: client);

    expect(find.text('小說'), findsOneWidget);
    expect(find.text('紅樓夢.epub'), findsOneWidget);
  });

  testWidgets('點擊資料夾項目 push 新畫面並帶入正確 folderId', (tester) async {
    final client = FakeCloudStorageClient(folderContents: {
      null: const CloudFolderListing(entries: [folderEntry]),
      'folder-1': const CloudFolderListing(entries: [fileEntryNoThumbnail]),
    });
    await pumpScreen(tester, client: client);

    await tester.tap(find.byKey(const Key('google_drive_browser_entry_folder-1')));
    await tester.pumpAndSettle();

    expect(find.text('紅樓夢.epub'), findsOneWidget);
  });

  testWidgets('無縮圖網址的檔案顯示縮圖佔位符', (tester) async {
    final client = FakeCloudStorageClient(folderContents: {
      null: const CloudFolderListing(entries: [fileEntryNoThumbnail]),
    });
    await pumpScreen(tester, client: client);

    expect(
      find.byKey(const Key('google_drive_browser_thumbnail_placeholder_file-1')),
      findsOneWidget,
    );
  });

  testWidgets('有縮圖網址的檔案透過 client.fetchThumbnail 顯示縮圖', (tester) async {
    final client = FakeCloudStorageClient(folderContents: {
      null: const CloudFolderListing(entries: [fileEntryWithThumbnail]),
    })..thumbnailBytes = Uint8List.fromList([1, 2, 3]);
    await pumpScreen(tester, client: client);

    expect(
      find.byKey(const Key('google_drive_browser_thumbnail_file-2')),
      findsOneWidget,
    );
  });

  testWidgets('點擊檔案項目切換勾選狀態', (tester) async {
    final client = FakeCloudStorageClient(folderContents: {
      null: const CloudFolderListing(entries: [fileEntryNoThumbnail]),
    });
    await pumpScreen(tester, client: client);

    expect(
      find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
    await tester.pump();

    expect(
      find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
    await tester.pump();

    expect(
      find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
      findsNothing,
    );
  });

  testWidgets('資料夾檔案數超過 1000 筆時顯示提示文字', (tester) async {
    final client = FakeCloudStorageClient(folderContents: {
      null: const CloudFolderListing(entries: [fileEntryNoThumbnail], truncated: true),
    });
    await pumpScreen(tester, client: client);

    expect(
      find.byKey(const Key('google_drive_browser_truncated_text')),
      findsOneWidget,
    );
  });

  testWidgets('access token 過期時顯示需要重新連結的訊息', (tester) async {
    final client = _ThrowingCloudStorageClient();
    await pumpScreen(tester, client: client);

    expect(find.byKey(const Key('google_drive_browser_reauth_text')), findsOneWidget);
  });

  group('選擇分類後下載＋匯入', () {
    late Directory tempRoot;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('google_drive_browser_test');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = FakePathProviderPlatform(tempRoot.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    testWidgets('選擇分類、勾選檔案、下載完成後 importFiles 帶入正確的 folderName', (tester) async {
      final libraryRepository = FakeLibraryRepository();
      await libraryRepository.upsertGroup('小說');
      final importService = FakeBookImportService();
      final client = FakeCloudStorageClient(
        folderContents: {
          null: const CloudFolderListing(entries: [fileEntryNoThumbnail]),
        },
        downloadContents: {
          'file-1': [1, 2, 3],
        },
      );
      await pumpScreen(
        tester,
        client: client,
        libraryRepository: libraryRepository,
        importService: importService,
      );

      await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
      await tester.pump();
      await tester
          .tap(find.byKey(const Key('google_drive_browser_group_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('小說').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('google_drive_browser_download_button')));
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cloud_download_queue_done_button')));
      await tester.pumpAndSettle();

      expect(importService.lastImportCall?.source, BookSource.googleDrive);
    });
  });
}

class _ThrowingCloudStorageClient extends FakeCloudStorageClient {
  @override
  Future<CloudFolderListing> listFolder({String? folderId}) async {
    throw CloudAuthRequiredException();
  }
}
```

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/screens/google_drive_browser_screen_test.dart`
預期：編譯失敗（`GoogleDriveBrowserScreen` 尚未定義）。

- [ ] **Step 3：實作 `GoogleDriveBrowserScreen`**

建立 `app/lib/screens/google_drive_browser_screen.dart`：

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../cloud_import/cloud_storage_client.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';
import 'cloud_download_queue_dialog.dart';

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
  bool _loading = true;
  bool _needsReauth = false;
  String? _errorText;
  List<CloudFileEntry> _entries = const [];
  bool _truncated = false;
  final Set<String> _selectedIds = {};
  List<BookGroup> _groups = const [];
  String _selectedGroupName = BookGroup.uncategorized;
  final Map<String, Uint8List> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
      _needsReauth = false;
    });
    try {
      final listing = await widget.client.listFolder(folderId: widget.folderId);
      final groups = await widget.libraryRepository.listGroups();
      if (!mounted) return;
      setState(() {
        _entries = listing.entries;
        _truncated = listing.truncated;
        _groups = groups;
        _loading = false;
      });
    } on CloudAuthRequiredException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _needsReauth = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = '載入失敗，請檢查網路連線';
      });
    }
  }

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

  void _toggleSelection(CloudFileEntry entry) {
    setState(() {
      if (_selectedIds.contains(entry.id)) {
        _selectedIds.remove(entry.id);
      } else {
        _selectedIds.add(entry.id);
      }
    });
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Google Drive'),
        actions: [
          IconButton(
            key: const Key('google_drive_browser_download_button'),
            icon: const Icon(Icons.download),
            tooltip: '下載已選取',
            onPressed: _selectedIds.isEmpty ? null : _startDownload,
          ),
        ],
      ),
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
              : _errorText != null
                  ? Center(
                      child: Text(
                        _errorText!,
                        key: const Key('google_drive_browser_error_text'),
                      ),
                    )
                  : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('匯入分類：'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                key: const Key('google_drive_browser_group_dropdown'),
                value: _selectedGroupName,
                items: [
                  const DropdownMenuItem(
                    value: BookGroup.uncategorized,
                    child: Text(BookGroup.uncategorized),
                  ),
                  for (final group
                      in _groups.where((g) => g.name != BookGroup.uncategorized))
                    DropdownMenuItem(value: group.name, child: Text(group.name)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedGroupName = value);
                },
              ),
            ],
          ),
        ),
        if (_truncated)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '這個資料夾檔案較多，僅顯示前 1000 筆',
              key: Key('google_drive_browser_truncated_text'),
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.6,
            ),
            itemCount: _entries.length,
            itemBuilder: (context, index) => _buildEntryTile(_entries[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildEntryTile(CloudFileEntry entry) {
    final selected = _selectedIds.contains(entry.id);
    return InkWell(
      key: Key('google_drive_browser_entry_${entry.id}'),
      onTap:
          entry.isFolder ? () => _openSubfolder(entry) : () => _toggleSelection(entry),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: entry.isFolder
                      ? const Icon(Icons.folder, size: 48)
                      : _buildThumbnail(entry),
                ),
                if (selected)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Icon(
                      Icons.check_circle,
                      key: Key('google_drive_browser_checkbox_checked_${entry.id}'),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            entry.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(CloudFileEntry entry) {
    final thumbnailUrl = entry.thumbnailUrl;
    if (thumbnailUrl == null) {
      return Center(
        child: Icon(
          Icons.book,
          key: Key('google_drive_browser_thumbnail_placeholder_${entry.id}'),
        ),
      );
    }
    final cached = _thumbnailCache[thumbnailUrl];
    if (cached != null) {
      return Image.memory(
        cached,
        key: Key('google_drive_browser_thumbnail_${entry.id}'),
        fit: BoxFit.cover,
      );
    }
    return FutureBuilder<Uint8List>(
      future: widget.client.fetchThumbnail(thumbnailUrl).then((bytes) {
        _thumbnailCache[thumbnailUrl] = bytes;
        return bytes;
      }),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            key: Key('google_drive_browser_thumbnail_${entry.id}'),
            fit: BoxFit.cover,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            key: Key('google_drive_browser_thumbnail_loading_${entry.id}'),
            child: const Icon(Icons.book),
          );
        }
        return Center(
          key: Key('google_drive_browser_thumbnail_error_${entry.id}'),
          child: const Icon(Icons.broken_image),
        );
      },
    );
  }
}
```

- [ ] **Step 4：執行測試確認通過**

執行：`flutter test test/screens/google_drive_browser_screen_test.dart`
預期：全數 PASS。

- [ ] **Step 5：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS。

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/google_drive_browser_screen.dart app/test/screens/google_drive_browser_screen_test.dart
git commit -m "feat(epic-29): Issue 3——GoogleDriveBrowserScreen 瀏覽畫面"
```

---

## Task 5：貫穿注入（「匯入」選單新增項目＋`LibraryScreen`→`ElinkBookApp`→`main.dart`）

**Files：**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces：**
- Consumes：Task 2 的 `GoogleDriveStorageClient`，Task 4 的 `GoogleDriveBrowserScreen`。
- Produces：`LibraryScreen`／`ElinkBookApp` 新增可選具名參數 `googleDriveStorageClient`，`main.dart` 正式組裝真實實例；「匯入」選單新增「從 Google Drive 匯入」項目。

- [ ] **Step 1：寫入失敗的「匯入」選單測試**

在 `app/test/screens/library_screen_test.dart` 找到既有的匯入選單相關測試群組（搜尋 `library_import_button` 找到對應 `group`），在其中新增：

```dart

    testWidgets('googleDriveStorageClient 為 null 時「從 Google Drive 匯入」選項停用', (tester) async {
      await pumpLibraryScreen(tester);

      await tester.tap(find.byKey(const Key('library_import_button')));
      await tester.pumpAndSettle();

      final option = tester.widget<PopupMenuItem<void>>(
        find.byKey(const Key('library_import_google_drive_option')),
      );
      expect(option.enabled, false);
    });

    testWidgets('提供 googleDriveStorageClient 時點擊「從 Google Drive 匯入」導航至 GoogleDriveBrowserScreen',
        (tester) async {
      final client = FakeCloudStorageClient();
      await pumpLibraryScreen(tester, googleDriveStorageClient: client);

      await tester.tap(find.byKey(const Key('library_import_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_import_google_drive_option')));
      await tester.pumpAndSettle();

      expect(find.text('Google Drive'), findsOneWidget);
    });
```

**注意**：`pumpLibraryScreen` 是本測試檔既有的共用建構 helper（若既有測試呼叫方式不同，依實際簽章調整上述兩處呼叫，新增 `googleDriveStorageClient` 具名參數）；在檔案開頭 import 區塊新增：

```dart
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';

import '../support/fake_cloud_storage_client.dart';
```

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/screens/library_screen_test.dart --plain-name "Google Drive"`
預期：編譯失敗（`LibraryScreen` 沒有 `googleDriveStorageClient` 具名參數，`library_import_google_drive_option` 不存在）。

- [ ] **Step 3：`LibraryScreen` 新增參數與匯入選單項目**

在 `app/lib/screens/library_screen.dart` 找到 import 區塊：

```dart
import '../cloud_import/cloud_account_repository.dart';
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

找到：

```dart
import 'library_move_to_group_dialog.dart';
import 'reader_screen.dart';
```

改為：

```dart
import 'google_drive_browser_screen.dart';
import 'library_move_to_group_dialog.dart';
import 'reader_screen.dart';
```

找到欄位宣告：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final RemoteServerRepository? remoteServerRepository;
```

改為：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final CloudStorageClient? googleDriveStorageClient;
  final RemoteServerRepository? remoteServerRepository;
```

找到建構子內：

```dart
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.remoteServerRepository,
```

改為：

```dart
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.googleDriveStorageClient,
    this.remoteServerRepository,
```

找到分類篩選畫面的自我遞迴導航點（`_openGroupFilteredView` 內）：

```dart
              cloudAccountRepository: widget.cloudAccountRepository,
              googleDriveOAuthClient: widget.googleDriveOAuthClient,
              oneDriveOAuthClient: widget.oneDriveOAuthClient,
```

改為：

```dart
              cloudAccountRepository: widget.cloudAccountRepository,
              googleDriveOAuthClient: widget.googleDriveOAuthClient,
              oneDriveOAuthClient: widget.oneDriveOAuthClient,
              googleDriveStorageClient: widget.googleDriveStorageClient,
```

找到「匯入」`PopupMenuButton` 的 `itemBuilder`：

```dart
          itemBuilder: (context) => [
            PopupMenuItem<void>(
              key: const Key('library_import_files_option'),
              onTap: _pickAndImportFiles,
              child: const Text('選擇檔案（可多選）'),
            ),
            PopupMenuItem<void>(
              key: const Key('library_import_folder_option'),
              onTap: _pickAndImportFolder,
              child: const Text('選擇資料夾'),
            ),
          ],
        ),
```

改為：

```dart
          itemBuilder: (context) => [
            PopupMenuItem<void>(
              key: const Key('library_import_files_option'),
              onTap: _pickAndImportFiles,
              child: const Text('選擇檔案（可多選）'),
            ),
            PopupMenuItem<void>(
              key: const Key('library_import_folder_option'),
              onTap: _pickAndImportFolder,
              child: const Text('選擇資料夾'),
            ),
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

在 `_pickAndImportFolder()` 方法結尾（`}` 之後）新增新方法：

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
        .then((_) {
      // 【審查 review-plan-issue-3.md Minor #2 採納】比照
      // `_openGroupFilteredView` 既有慣例，一併重新載入分類——
      // `importFiles(folderName: ...)` 內部會 `upsertGroup()`，回到書架
      // 時分類清單與書籍清單應保持同步一致。
      if (mounted) {
        _loadGroups();
        _loadBooks();
      }
    });
  }
```

- [ ] **Step 4：執行測試確認通過**

執行：`flutter test test/screens/library_screen_test.dart`
預期：全數 PASS。

- [ ] **Step 5：`main.dart` 組裝真實實例並貫穿 `ElinkBookApp`**

在 `app/lib/main.dart` 找到：

```dart
import 'cloud_import/cloud_account_repository.dart';
import 'cloud_import/google_drive_oauth_client.dart';
import 'cloud_import/onedrive_oauth_client.dart';
import 'cloud_import/secure_storage_cloud_account_repository.dart';
import 'library/book_content_fingerprint.dart';
```

改為：

```dart
import 'cloud_import/cloud_account_repository.dart';
import 'cloud_import/cloud_storage_client.dart';
import 'cloud_import/google_drive_oauth_client.dart';
import 'cloud_import/google_drive_storage_client.dart';
import 'cloud_import/onedrive_oauth_client.dart';
import 'cloud_import/secure_storage_cloud_account_repository.dart';
import 'library/book_content_fingerprint.dart';
```

找到：

```dart
  // epic-29-cloud-import Issue 1/2：雲端匯入帳號模組
  final cloudAccountRepository = SecureStorageCloudAccountRepository();
  final googleDriveOAuthClient = GoogleDriveOAuthClient(
    accountRepository: cloudAccountRepository,
  );
  final oneDriveOAuthClient = OneDriveOAuthClient(
    accountRepository: cloudAccountRepository,
  );
```

改為：

```dart
  // epic-29-cloud-import Issue 1/2：雲端匯入帳號模組
  final cloudAccountRepository = SecureStorageCloudAccountRepository();
  final googleDriveOAuthClient = GoogleDriveOAuthClient(
    accountRepository: cloudAccountRepository,
  );
  final oneDriveOAuthClient = OneDriveOAuthClient(
    accountRepository: cloudAccountRepository,
  );
  // epic-29-cloud-import Issue 3：Google Drive 瀏覽＋下載。無內部可變的
  // session 狀態（不像 OpdsHttpClient 的 _visitedFeedUrls），單一共用
  // 實例即可，不需要比照 createOpdsClient 那樣的工廠函式。
  final CloudStorageClient googleDriveStorageClient =
      GoogleDriveStorageClient(oauthClient: googleDriveOAuthClient);
```

找到 `runApp(ElinkBookApp(...))` 內：

```dart
      cloudAccountRepository: cloudAccountRepository,
      googleDriveOAuthClient: googleDriveOAuthClient,
      oneDriveOAuthClient: oneDriveOAuthClient,
```

改為：

```dart
      cloudAccountRepository: cloudAccountRepository,
      googleDriveOAuthClient: googleDriveOAuthClient,
      oneDriveOAuthClient: oneDriveOAuthClient,
      googleDriveStorageClient: googleDriveStorageClient,
```

找到 `ElinkBookApp` 的欄位宣告：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
```

改為：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final CloudStorageClient? googleDriveStorageClient;
```

找到 `ElinkBookApp` 建構子內：

```dart
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
```

改為：

```dart
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.googleDriveStorageClient,
```

找到 `build()` 內 `LibraryScreen(...)` 建構呼叫點：

```dart
        cloudAccountRepository: widget.cloudAccountRepository,
        googleDriveOAuthClient: widget.googleDriveOAuthClient,
        oneDriveOAuthClient: widget.oneDriveOAuthClient,
```

改為：

```dart
        cloudAccountRepository: widget.cloudAccountRepository,
        googleDriveOAuthClient: widget.googleDriveOAuthClient,
        oneDriveOAuthClient: widget.oneDriveOAuthClient,
        googleDriveStorageClient: widget.googleDriveStorageClient,
```

- [ ] **Step 6：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS。

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-29): Issue 3——貫穿注入 GoogleDriveStorageClient 至匯入選單"
```

---

## Self-Review（撰寫計劃時的自我檢查記錄）

**1. Spec 涵蓋範圍檢查：**
- `spec.md`「雲端瀏覽與下載：`CloudStorageClient`」的 `listFolder`/`downloadFile`、`CloudFileEntry` 型別 → Task 1 涵蓋（`truncated` 欄位為相對決策草圖的必要修訂，已於 Global Constraints 說明理由）。
- `spec.md`「格式過濾」的伺服器端 MIME type 過濾 EPUB/PDF/TXT ＋用戶端副檔名過濾 AZW3/CBZ、分頁機制、1000 筆上限提示 → Task 2 涵蓋。
- `spec.md`「縮圖」需要授權標頭＋載入佔位符與快取 → Task 4（`fetchThumbnail()` 授權由 `GoogleDriveStorageClient` 內部處理，畫面層記憶體 `_thumbnailCache` 提供快取）涵蓋。
- `spec.md`「下載到暫存路徑...使用者取消或整個匯入流程時，暫存檔案需要被清除」→ Task 2（`downloadFile()` 契約）／Task 3（`downloadCloudFileToTempFile`／`promoteCloudFileToPermanent` 兩種失敗窗口區分處理）涵蓋。
- `issues.md` Issue 3「What to build」三項（`CloudStorageClient`＋`GoogleDriveStorageClient`、「匯入」選單新增項目＋瀏覽畫面、序列下載＋逐項狀態＋`importFiles()` 落地）→ Task 1/2（第一項）、Task 4/5（第二項）、Task 3（第三項）逐一對應涵蓋。
- `issues.md` Issue 3「單元測試要求」九項（資料夾導覽、格式過濾清單、縮圖佔位符、單選/多選、循序下載＋逐項狀態、失敗重試、取消清暫存檔、1000 筆提示、分類選擇正確傳入）與「`importFiles()` 呼叫時 source/cloudFileIds 正確帶入的整合驗證」→ Task 3 Step 2（前 3 項）與 Task 4 Step 1（其餘 6 項＋整合驗證）逐一對應涵蓋。

**2. 佔位符掃描：** 全文檢查過，所有 Step 皆含完整可執行的程式碼區塊。Task 5 Step 1 提及「若既有測試呼叫方式不同，依實際簽章調整」——這不是佔位符，是對既有測試檔案 `pumpLibraryScreen` helper 簽章的合理不確定性揭露（本計劃撰寫時未逐字核對該檔案內部 helper 的確切參數順序），執行者需要在該步驟開始前先讀取 `library_screen_test.dart` 既有內容確認 helper 簽章，這是正常的實作前置動作，不影響計劃的可執行性。

**3. 型別一致性檢查：** `CloudFileEntry`／`CloudFolderListing`／`CloudDownloadCancellationToken`／`CloudAuthRequiredException`（Task 1 定義）在 Task 2（`GoogleDriveStorageClient`）、Task 3（`cloud_book_downloader.dart`／`CloudDownloadQueueDialog`）、Task 4（`GoogleDriveBrowserScreen`）的呼叫全數對應一致；`downloadCloudFileToTempFile`／`promoteCloudFileToPermanent`（Task 3 定義）與 `CloudDownloadQueueDialog._downloadOne()` 的呼叫簽章一致；`BookSource.googleDrive`／`cloudFileIds` 在 Task 3（`CloudDownloadQueueDialog._importSuccessful()`）呼叫 `BookImportService.importFiles()` 的參數與 Issue 0 既有簽章一致；`LibraryScreen`／`ElinkBookApp` 的 `googleDriveStorageClient` 具名參數命名與型別（可選、nullable，`CloudStorageClient?`）在 Task 5 兩處貫穿注入完全一致。
