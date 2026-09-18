# Epic 44 Issue 2：下載功能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 PC 端瀏覽器能在 WiFi 傳書首頁看到已下載書籍清單，並成功下載（含 `content://` 來源材質化與 TXT/MD 來源書籍誠實回傳 `.epub`），同時讓 Issue 1 建好的併發節流機制對下載請求的「整個傳輸期間」真正生效。

**Architecture:** `WifiTransferService` 補上兩個純邏輯方法（`listDownloadableBooks()`／`resolveDownloadSource()`），只依賴 `LibraryRepository`／`materializeContentUri` 兩個既有介面，可完全脫離真實 socket 用 `flutter test` 驗證。`WifiTransferHttpServer` 補上 `GET /api/books`／`GET /api/books/<id>/download` 兩條路由；下載路由需要把「取得併發許可」與「串流真正結束（EOF／例外／客戶端中途取消）才釋放許可＋刪除暫存檔」綁在一起，這件事無法用 Issue 1 既有的 `withTransferPermit()` 包裝寫法達成（詳見 Task 3 的說明），因此把 `withTransferPermit()` 內部邏輯拆成 `_acquirePermit()`／`_releasePermit()` 兩個方法（純內部重構，`withTransferPermit()` 對外行為與既有測試不變），下載路由改為手動配對呼叫。

**Tech Stack:** Flutter/Dart、`shelf`（HTTP 路由，沿用 Issue 1 已建立的手動路徑比對）、`dart:io`（`File`／`HttpServer`）、`dart:convert`（`jsonEncode` 組 `/api/books` JSON 回應）。不新增任何 `pubspec.yaml` 依賴——Issue 0／Issue 1 已引進的 `shelf` 已足夠。

**Spec:** `docs/epics/epic-44-wifi-book-transfer/spec.md`（「`wifi_transfer_service.dart`」「HTTP 路由表」「PC 端網頁」章節）與 `docs/epics/epic-44-wifi-book-transfer/issues.md`（Issue 2）。執行者應同時閱讀這兩份文件；Issue 0／Issue 1 的完成狀態（`findBookById`／`WifiTransferService`／`WifiTransferHttpServer` 骨架／`WifiTransferScreen`／三層裝配）已合併進 `main`（PR #257），本計畫直接建立在其上。

## Global Constraints

- 所有程式碼註解、commit message、文件皆使用正體中文（zh-TW），專業術語可保留英文（CLAUDE.md 全域規則）。
- 所有指令在 `app/` 目錄下執行（`flutter pub get`／`flutter analyze`／`flutter test`）。
- 每個 Task 只跑「這次異動實際觸及」的測試檔；只有本計畫最後一個 Task（Task 10）才跑一次完整 `flutter test`（CLAUDE.md「測試執行範圍」）。
- `resolveDownloadSource(bookId)` 的回傳型別 `DownloadSource?` 是 Issue 1 已定案、已合併的公開簽章，本計畫不變更它——「找不到書籍」與「`content://` 材質化失敗」兩種情境皆回傳 `null`，路由層**一律視為 404**（見 Task 2 說明；不新增例外型別或第二個回傳管道來分辨兩種原因，避免變更已合併的 Issue 1 介面）。
- **下載路由的併發許可持有到位元組真正傳輸完畢才釋放**，不是 `shelf.Response` 物件建構完成的當下（見 Task 3／Task 7 說明）——這是撰寫本計畫時發現、必須修正的正確性問題，不是照抄 Issue 1 程式碼註解裡的字面範例（`return withTransferPermit(() => _handleDownload(bookId));`）就能達成的效果。
- 下載檔名（`Content-Disposition`）一律同時附上 `filename`（ASCII 安全退路）與 `filename*=UTF-8''...`（完整 percent-encoding），兩者皆須確保任何輸入（含惡意書名夾帶 `\r\n` 等控制字元）都不會以原始位元組型式出現在標頭值中（見 Task 5）。
- 不新增 SQLite schema（spec.md「範圍界定」已定案）。
- 除本計畫列出的檔案外，不修改其他檔案；不「順手」重構、清理或改動未在本 Issue 範圍內的程式碼。`POST /api/upload` 路由目前的 `501` 佔位（Issue 3 範圍）維持原樣不動。
- **（`review-plan-issue-2.md` 審查意見，評估後不採納）** M-3（`listDownloadableBooks()` 改用 `Future.wait()` 並行查詢每本書的 `sizeBytes`）：issues.md 對本清單端點沒有設定效能門檻（不同於全文檢索明確的「1000 本書 500ms」要求），目前的循序 `await` 迴圈換來的是已驗證正確、無額外併發 I/O 風險的簡單實作；在沒有實測數據顯示這是真實瓶頸前，不引入未經測試的併發檔案存取模式（Simplicity First／YAGNI）。M-4（`integration_test/wifi_transfer_screen_test.dart` 每個 `testWidgets` 之間手動 unmount widget）：`flutter_test`／`integration_test` 的測試框架本身在每個 `testWidgets` 開始前就會重置並拆除前一個測試遺留的 widget 樹（`State.dispose()` 隨之執行），本檔案與本專案其餘 `integration_test/` 檔案（例如既有的 `content_uri_acceptance_test.dart`）皆未手動 unmount；其提及的埠號衝突風險本來就已由 `WifiTransferScreen._startServerIfNeeded()` 既有的「固定埠失敗即退回 `port: 0`」機制吸收，且本計畫的測試一律從 widget 讀取實際綁定的網址而非假設固定埠，不受影響。

---

### Task 1: `WifiTransferService.listDownloadableBooks()` 實作

**Files:**
- Modify: `app/lib/wifi_transfer/wifi_transfer_service.dart`
- Modify: `app/test/wifi_transfer/wifi_transfer_service_test.dart`

**Interfaces:**
- Consumes：`LibraryRepository.listBooks()`（既有）、`Book.isDownloaded`／`Book.filePath`（既有）。
- Produces：`WifiTransferService.listDownloadableBooks()` 由 `throw UnimplementedError()` 改為真正實作，回傳型別維持 `Future<List<DownloadableBook>>` 不變。新增私有 helper `Future<int?> _localSizeBytes(Book book)`（僅供本檔案內部使用，不對外匯出）。

- [x] **Step 1: 寫失敗測試——移除舊的「三方法皆拋出」測試，改為只鎖定 `handleUploadedFile` 仍未實作，並新增 `listDownloadableBooks` 測試群組**

Edit `app/test/wifi_transfer/wifi_transfer_service_test.dart`，整份取代為：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_service.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_fingerprint_computer.dart';

Book _bookWith({
  required String id,
  required String filePath,
  bool isDownloaded = true,
  BookFileFormat format = BookFileFormat.epub,
  String title = '書名',
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return Book(
    id: id,
    title: title,
    format: format,
    filePath: filePath,
    source: BookSource.local,
    isDownloaded: isDownloaded,
    createTime: now,
    lastReadTime: now,
  );
}

void main() {
  WifiTransferService buildService({
    List<Book> initialBooks = const [],
    Future<String?> Function(String uri)? materializeContentUri,
  }) {
    final fingerprintComputer = FakeFingerprintComputer();
    return WifiTransferService(
      libraryRepository: FakeLibraryRepository(initialBooks: initialBooks),
      importService: FakeBookImportService(),
      computeFingerprint: fingerprintComputer.call,
      materializeContentUri: materializeContentUri ?? (uri) async => null,
      deleteFile: (path) async {},
    );
  }

  test('handleUploadedFile 尚未實作，呼叫時明確拋出 UnimplementedError（Issue 3 填入前的契約）',
      () async {
    final service = buildService();

    await expectLater(
      service.handleUploadedFile(
        landedPath: '/tmp/a.epub',
        originalFileName: 'a.epub',
        format: BookFileFormat.epub,
      ),
      throwsA(isA<UnimplementedError>()),
    );
  });

  group('listDownloadableBooks', () {
    test('只列出 isDownloaded == true 的書，且欄位對應正確', () async {
      final downloaded =
          _bookWith(id: 'b1', filePath: 'test/fixtures/sample.pdf', title: '已下載');
      final notDownloaded = _bookWith(
          id: 'b2', filePath: 'test/fixtures/sample.epub', isDownloaded: false);
      final service = buildService(initialBooks: [downloaded, notDownloaded]);

      final result = await service.listDownloadableBooks();

      expect(result, hasLength(1));
      expect(result.single.id, 'b1');
      expect(result.single.title, '已下載');
      expect(result.single.format, BookFileFormat.epub);
    });

    test('本機路徑且檔案存在：sizeBytes 為真實檔案大小', () async {
      final book = _bookWith(id: 'b1', filePath: 'test/fixtures/sample.pdf');
      final service = buildService(initialBooks: [book]);

      final result = await service.listDownloadableBooks();

      final expectedSize = await File('test/fixtures/sample.pdf').length();
      expect(result.single.sizeBytes, expectedSize);
    });

    test(
        'content:// 來源：sizeBytes 恆為 null，且不觸發 materializeContentUri'
        '（清單階段嚴禁材質化）', () async {
      final calls = <String>[];
      final book = _bookWith(
          id: 'b1', filePath: 'content://com.example.provider/document/42');
      final service = buildService(
        initialBooks: [book],
        materializeContentUri: (uri) async {
          calls.add(uri);
          return '/tmp/should-not-be-called.pdf';
        },
      );

      final result = await service.listDownloadableBooks();

      expect(result.single.sizeBytes, isNull);
      expect(calls, isEmpty);
    });

    test('記錄存在但本機檔案已被外部刪除：sizeBytes 為 null，不拋出例外中斷整個查詢',
        () async {
      final missing =
          _bookWith(id: 'b1', filePath: 'test/fixtures/does_not_exist_book.pdf');
      final present = _bookWith(id: 'b2', filePath: 'test/fixtures/sample.pdf');
      final service = buildService(initialBooks: [missing, present]);

      final result = await service.listDownloadableBooks();

      expect(result, hasLength(2));
      expect(result.firstWhere((b) => b.id == 'b1').sizeBytes, isNull);
      expect(result.firstWhere((b) => b.id == 'b2').sizeBytes, isNotNull);
    });
  });
}
```

- [x] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/wifi_transfer/wifi_transfer_service_test.dart`
Expected: FAIL——`listDownloadableBooks` 群組的 4 個測試因 `UnimplementedError` 被拋出而失敗（`handleUploadedFile` 那個測試仍會通過）。

- [x] **Step 3: 實作 `listDownloadableBooks()`**

Edit `app/lib/wifi_transfer/wifi_transfer_service.dart`：

```dart
// 舊：
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/library_enums.dart';
```

```dart
// 新：
import 'dart:io';

import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/library_enums.dart';
```

```dart
// 舊：
  /// Issue 2 實作：呼叫 `libraryRepository.listBooks()` 並過濾
  /// `isDownloaded == true`，詳見 spec.md「`wifi_transfer_service.dart`」。
  Future<List<DownloadableBook>> listDownloadableBooks() async {
    throw UnimplementedError('Issue 2 實作：下載清單查詢');
  }
```

```dart
// 新：
  /// 對應「下載清單僅列出 isDownloaded == true」決策（spec.md
  /// 「`wifi_transfer_service.dart`」）。[DownloadableBook.sizeBytes] 只對
  /// 非 `content://` 的本機實體檔案計算，且須先 `await file.exists()`
  /// 防呆——書籍記錄可能因使用者在系統層級手動搬移/刪除本機檔案而失效，
  /// 直接呼叫 `.length()` 會拋 `FileSystemException` 中斷整個清單查詢；
  /// `content://` 或檔案不存在時 sizeBytes 恆為 null，清單建立階段嚴禁
  /// 呼叫 [materializeContentUri] 觸發材質化（會讓瀏覽清單時就把整個書架
  /// 複製一份到快取目錄）。
  Future<List<DownloadableBook>> listDownloadableBooks() async {
    final books = await libraryRepository.listBooks();
    final result = <DownloadableBook>[];
    for (final book in books) {
      if (!book.isDownloaded) continue;
      result.add(DownloadableBook(
        id: book.id,
        title: book.title,
        format: book.format,
        sizeBytes: await _localSizeBytes(book),
      ));
    }
    return result;
  }

  Future<int?> _localSizeBytes(Book book) async {
    if (book.filePath.contains('://')) return null;
    // 【`/receiving-code-review` 審查修正，review-plan-issue-2.md I-5】
    // await file.exists() 與 file.length() 之間仍有極短暫的 TOCTOU
    // 間隙（檔案在這中間被外部刪除/權限被收回），用 try-catch 兜底，
    // 讓單一一本書的檔案系統例外不會打垮整支 /api/books 清單查詢。
    try {
      final file = File(book.filePath);
      if (!await file.exists()) return null;
      return await file.length();
    } catch (_) {
      return null;
    }
  }
```

- [x] **Step 4: 執行測試，確認通過**

Run: `flutter test test/wifi_transfer/wifi_transfer_service_test.dart`
Expected: PASS，5 個測試全數通過。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_service.dart test/wifi_transfer/wifi_transfer_service_test.dart`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_service.dart app/test/wifi_transfer/wifi_transfer_service_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 實作 WifiTransferService.listDownloadableBooks()

epic-44-wifi-book-transfer Issue 2：呼叫 libraryRepository.listBooks()
過濾 isDownloaded == true；DownloadableBook.sizeBytes 對 content:// 或
本機檔案已不存在的情境皆回傳 null（不觸發材質化、不拋例外中斷整個查詢，
先 await file.exists() 防呆，外層再包 try-catch 兜底 exists()/length()
之間的 TOCTOU 間隙——review-plan-issue-2.md I-5）。新增私有
_localSizeBytes() helper。測試覆蓋 4 種情境（一般過濾、本機檔案存在、
content:// 來源、記錄存在但檔案已被外部刪除）。既有「三方法皆拋出」
測試拆分為只鎖定 handleUploadedFile（Issue 3 範圍）仍未實作。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `WifiTransferService.resolveDownloadSource()` 實作

**Files:**
- Modify: `app/lib/wifi_transfer/wifi_transfer_service.dart`
- Modify: `app/test/wifi_transfer/wifi_transfer_service_test.dart`

**Interfaces:**
- Consumes：`LibraryRepository.findBookById()`（Issue 0 已提供）、`WifiTransferService.materializeContentUri`（既有建構子欄位）、`fileExtensionFor()`（`app/lib/remote/opds_client.dart`，既有共用函式）。
- Produces：`WifiTransferService.resolveDownloadSource()` 由 `throw UnimplementedError()` 改為真正實作，回傳型別維持 `Future<DownloadSource?>` 不變（Issue 1 已定案的公開簽章）。新增私有 helper `String _downloadFileNameFor(Book book)`。

- [x] **Step 1: 寫失敗測試**

Edit `app/test/wifi_transfer/wifi_transfer_service_test.dart`，在 `listDownloadableBooks` 群組**之後**（`main()` 結尾 `}` 之前）新增：

```dart
  group('resolveDownloadSource', () {
    test('找不到書籍：回傳 null（呼叫端回 404）', () async {
      final service = buildService();

      expect(await service.resolveDownloadSource('missing'), isNull);
    });

    test('書籍存在但 isDownloaded == false：回傳 null', () async {
      final book = _bookWith(
          id: 'b1', filePath: 'test/fixtures/sample.pdf', isDownloaded: false);
      final service = buildService(initialBooks: [book]);

      expect(await service.resolveDownloadSource('b1'), isNull);
    });

    test(
        '圖書庫有多本書時，依 bookId 精確比對出正確的那一本（確實呼叫'
        ' findBookById，而非誤用 listBooks() 取第一筆）', () async {
      final first =
          _bookWith(id: 'b1', filePath: 'test/fixtures/sample.epub', title: '第一本');
      final second =
          _bookWith(id: 'b2', filePath: 'test/fixtures/sample.pdf', title: '第二本');
      final service = buildService(initialBooks: [first, second]);

      final source = await service.resolveDownloadSource('b2');

      expect(source!.resolvedPath, 'test/fixtures/sample.pdf');
      expect(source.downloadFileName, '第二本.pdf');
    });

    test('本機路徑來源：resolvedPath 為原始 filePath、isTemporaryFile 為 false、'
        '副檔名維持原格式', () async {
      final book = _bookWith(
        id: 'b1',
        filePath: 'test/fixtures/sample.pdf',
        format: BookFileFormat.pdf,
        title: '測試書',
      );
      final service = buildService(initialBooks: [book]);

      final source = await service.resolveDownloadSource('b1');

      expect(source, isNotNull);
      expect(source!.resolvedPath, 'test/fixtures/sample.pdf');
      expect(source.downloadFileName, '測試書.pdf');
      expect(source.isTemporaryFile, isFalse);
    });

    test(
        '本機路徑但檔案已被外部刪除：回傳 null（呼叫端回 404，而非因'
        ' file.length() 拋出 FileSystemException 回 500——審查修正 I-4）',
        () async {
      final book = _bookWith(
          id: 'b1', filePath: 'test/fixtures/does_not_exist_book.pdf');
      final service = buildService(initialBooks: [book]);

      expect(await service.resolveDownloadSource('b1'), isNull);
    });

    test('content:// 來源：呼叫 materializeContentUri 並回傳其結果、'
        'isTemporaryFile 為 true', () async {
      final book = _bookWith(
        id: 'b1',
        filePath: 'content://com.example.provider/document/42',
        title: '測試書',
      );
      final calls = <String>[];
      final service = buildService(
        initialBooks: [book],
        materializeContentUri: (uri) async {
          calls.add(uri);
          return '/tmp/materialized.epub';
        },
      );

      final source = await service.resolveDownloadSource('b1');

      expect(calls, ['content://com.example.provider/document/42']);
      expect(source!.resolvedPath, '/tmp/materialized.epub');
      expect(source.isTemporaryFile, isTrue);
    });

    test('content:// 材質化失敗（回傳 null）：整體回傳 null', () async {
      final book = _bookWith(
          id: 'b1', filePath: 'content://com.example.provider/document/42');
      final service = buildService(initialBooks: [book]);

      expect(await service.resolveDownloadSource('b1'), isNull);
    });

    test('TXT 來源書籍：downloadFileName 誠實改寫為 .epub', () async {
      final book = _bookWith(
        id: 'b1',
        filePath: 'test/fixtures/sample.pdf',
        format: BookFileFormat.txt,
        title: '我的筆記',
      );
      final service = buildService(initialBooks: [book]);

      final source = await service.resolveDownloadSource('b1');

      expect(source!.downloadFileName, '我的筆記.epub');
    });

    test('MD 來源書籍：downloadFileName 誠實改寫為 .epub', () async {
      final book = _bookWith(
        id: 'b1',
        filePath: 'test/fixtures/sample.pdf',
        format: BookFileFormat.md,
        title: '我的筆記',
      );
      final service = buildService(initialBooks: [book]);

      final source = await service.resolveDownloadSource('b1');

      expect(source!.downloadFileName, '我的筆記.epub');
    });
  });
```

- [x] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/wifi_transfer/wifi_transfer_service_test.dart`
Expected: FAIL——`resolveDownloadSource` 群組的 9 個測試因 `UnimplementedError` 被拋出而失敗。

- [x] **Step 3: 實作 `resolveDownloadSource()`**

Edit `app/lib/wifi_transfer/wifi_transfer_service.dart`：

```dart
// 舊：
import 'dart:io';

import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/library_enums.dart';
```

```dart
// 新：
import 'dart:io';

import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/library_enums.dart';
import '../remote/opds_client.dart' show fileExtensionFor;
```

```dart
// 舊：
  /// Issue 2 實作：`findBookById(bookId)` → `content://` 材質化 →
  /// TXT/MD 副檔名改寫，詳見 spec.md「`wifi_transfer_service.dart`」。
  Future<DownloadSource?> resolveDownloadSource(String bookId) async {
    throw UnimplementedError('Issue 2 實作：下載來源解析');
  }
```

```dart
// 新：
  /// 對應「content:// 下載」＋「TXT/MD 來源書籍誠實回傳 .epub」決策
  /// （spec.md「`wifi_transfer_service.dart`」）。找不到書籍、
  /// `!isDownloaded`、本機檔案已被外部刪除，或 `content://` 材質化失敗時
  /// 皆回傳 `null`——路由層（`WifiTransferHttpServer`）無法從單一
  /// nullable 回傳型別區分這些原因（`DownloadSource?` 是 Issue 1 已定案、
  /// 已合併的方法簽章，本 Issue 不變更它），一律視為 404，比照 spec.md
  /// 「HTTP 路由表」對本路由僅明確提及 404 的用詞——材質化失敗屬於極少
  /// 發生的邊界情境（SAF 授權過期或裝置儲存空間不足）。
  ///
  /// **（`/receiving-code-review` 審查修正，review-plan-issue-2.md I-4）**
  /// 本機路徑（非 `content://`）情境下，Task 1 的 `_localSizeBytes()`
  /// 已對「記錄存在但檔案已被外部刪除」做了防呆，這裡原本遺漏了同一種
  /// 防呆——若不檢查，`_handleDownload()`（Task 7）稍後呼叫
  /// `file.length()` 會拋出未預期的 `FileSystemException`，讓路由回傳
  /// HTTP 500 而非語意正確的 404。
  Future<DownloadSource?> resolveDownloadSource(String bookId) async {
    final book = await libraryRepository.findBookById(bookId);
    if (book == null || !book.isDownloaded) return null;
    final isContentUri = book.filePath.contains('://');
    final resolvedPath = isContentUri
        ? await materializeContentUri(book.filePath)
        : book.filePath;
    if (resolvedPath == null) return null;
    if (!isContentUri && !await File(resolvedPath).exists()) return null;
    return DownloadSource(
      resolvedPath: resolvedPath,
      downloadFileName: _downloadFileNameFor(book),
      isTemporaryFile: isContentUri,
    );
  }

  /// TXT／MD 來源書籍在匯入時已被合成為 EPUB3 結構（`Book.filePath` 指向
  /// 合成檔案，見 ADR 0023），下載時對使用者誠實回傳 `.epub`，而非 `Book`
  /// 記錄本身仍保留的 `txt`／`md` 格式標記。
  String _downloadFileNameFor(Book book) {
    final honestFormat =
        (book.format == BookFileFormat.txt || book.format == BookFileFormat.md)
            ? BookFileFormat.epub
            : book.format;
    return '${book.title}.${fileExtensionFor(honestFormat)}';
  }
```

- [x] **Step 4: 執行測試，確認通過**

Run: `flutter test test/wifi_transfer/wifi_transfer_service_test.dart`
Expected: PASS，14 個測試全數通過。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_service.dart test/wifi_transfer/wifi_transfer_service_test.dart`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_service.dart app/test/wifi_transfer/wifi_transfer_service_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 實作 WifiTransferService.resolveDownloadSource()

epic-44-wifi-book-transfer Issue 2：findBookById() 找不到或
!isDownloaded 回傳 null；content:// 來源呼叫 materializeContentUri()
材質化，失敗同樣回傳 null（路由層一律視為 404，DownloadSource? 這個
Issue 1 已定案的單一 nullable 回傳型別本來就無法分辨兩種原因，不新增
例外型別變更已合併介面）；TXT/MD 來源書籍的 downloadFileName 誠實改寫
為 .epub（複用既有 fileExtensionFor()）。新增私有 _downloadFileNameFor()
helper，測試覆蓋 9 種情境（含多本書時依 id 精確比對的安全網測試，以及
本機檔案已被外部刪除時回傳 null 的防呆——review-plan-issue-2.md I-4）。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `WifiTransferHttpServer` 併發許可內部重構——`_acquirePermit()`／`_releasePermit()`

**Files:**
- Modify: `app/lib/wifi_transfer/wifi_transfer_http_server.dart`
- Test: `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`（本 Task 不新增測試，只重跑既有測試驗證零回歸）

**Interfaces:**
- Consumes：無新依賴。
- Produces：新增兩個私有方法 `Future<void> _acquirePermit()`／`void _releasePermit()`，供 Task 7 的下載路由手動配對呼叫；`withTransferPermit<T>()` 對外簽章與可觀察行為完全不變（純內部重構）。新增私有欄位 `bool _disposed`，`dispose()` 設為 `true`；`_acquirePermit`／`_releasePermit` 在寫入 `_activeTransfersNotifier.value` 前皆檢查 `!_disposed`。

**為什麼需要這個重構**：Issue 1 的 `withTransferPermit<T>(Future<T> Function() action)` 在 `action()` 回傳的當下（`finally`）就釋放許可。這個包裝寫法對上傳（Issue 3）沒問題——上傳 handler 會在同一個 `action()` 呼叫內同步讀完整個請求 body 才回傳。但下載不同：`shelf` 的 handler 一旦回傳 `shelf.Response`（內含尚未被消費的 `Stream<List<int>>` 主體），實際位元組傳輸是在 handler **回傳之後**才由 `shelf_io` 非同步消費該 Stream。若把「建構 Response 物件」當成 `action`，`finally` 會在 Response 建好、位元組其實還沒送到客戶端前就釋放許可——併發節流對下載形同虛設，`activeTransfersNotifier`（供 `WifiTransferScreen` 的 `PopScope` 判斷「離開畫面時是否有傳輸進行中」）也無法正確反映真實狀態。正確做法是把「取得」與「釋放」拆成兩個獨立方法，讓下載路由能在串流真正結束（`onDone`/`onError`/客戶端中途取消）時才呼叫 `_releasePermit()`（見 Task 4／Task 7）。

**（`/receiving-code-review` 審查修正，`review-plan-issue-2.md` C-1）** `WifiTransferScreen.dispose()`（Issue 1 既有程式碼，`app/lib/screens/wifi_transfer_screen.dart:145-154`）呼叫 `wifiServer.stop(httpServer)`（非同步、未 `await`）後，同一個同步方法內緊接著呼叫 `wifiServer.dispose()`，讓 `_activeTransfersNotifier` 立刻進入 disposed 狀態。若使用者在下載進行中透過 `PopScope` 的確認對話框主動離開畫面，串流稍後才真正結束時觸發的 `_releasePermit()` 會對已 disposed 的 `ValueNotifier` 賦值，拋出 `FlutterError: A ValueNotifier<int> was used after being disposed.`——這是可被使用者操作真實觸發的路徑，不是理論邊界情況。修法：新增 `_disposed` 旗標，`dispose()` 設為 `true`；`_acquirePermit`／`_releasePermit` 寫入 `.value` 前檢查 `!_disposed`，`_activePermits`／`_waitQueue` 的計數與排隊邏輯本身不受影響（伺服器都已經 dispose，不會再有新的下載請求進來，只是不再嘗試通知一個沒有任何 UI 在監聽的已銷毀 notifier）。

- [x] **Step 1: 執行既有測試，確認目前是綠燈（重構前基準）**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: PASS，`WifiTransferHttpServer.withTransferPermit 併發節流` 群組的 3 個測試（連同其餘既有測試）全數通過。

- [x] **Step 2: 重構 `withTransferPermit()`**

Edit `app/lib/wifi_transfer/wifi_transfer_http_server.dart`：

```dart
// 舊：
  int _activePermits = 0;
  final List<Completer<void>> _waitQueue = [];
  bool _stopped = false;

  /// 併發節流：進入實際傳輸邏輯前先取得許可（超過 [maxConcurrentTransfers]
  /// 時在此等待，不回錯誤碼給客戶端，符合「零意外」原則），結束時（含
  /// 拋出例外）一律釋放並同步更新 [activeTransfersNotifier]。Issue 2／3
  /// 的下載/上傳路由須把各自的實際傳輸邏輯包在這個方法內呼叫，例如：
  /// `return withTransferPermit(() => _handleDownload(bookId));`
  Future<T> withTransferPermit<T>(Future<T> Function() action) async {
    if (_activePermits >= maxConcurrentTransfers) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
      if (_stopped) {
        throw StateError('WifiTransferHttpServer 已停止，取消排隊中的請求');
      }
    }
    _activePermits++;
    _activeTransfersNotifier.value = _activePermits;
    try {
      return await action();
    } finally {
      _activePermits--;
      _activeTransfersNotifier.value = _activePermits;
      if (_waitQueue.isNotEmpty && !_stopped) {
        _waitQueue.removeAt(0).complete();
      }
    }
  }
```

```dart
// 新：
  int _activePermits = 0;
  final List<Completer<void>> _waitQueue = [];
  bool _stopped = false;

  /// 併發節流：進入實際傳輸邏輯前先取得許可（超過 [maxConcurrentTransfers]
  /// 時在此等待，不回錯誤碼給客戶端，符合「零意外」原則），結束時（含
  /// 拋出例外）一律釋放並同步更新 [activeTransfersNotifier]。上傳路由
  /// （Issue 3）會在同一個 [action] 呼叫內同步讀完整個請求 body 才回傳，
  /// 可直接把處理邏輯包在這個方法內呼叫。
  ///
  /// **（Issue 2 撰寫下載路由時發現並修正的設計限制）** 下載路由不能沿用
  /// 這個包裝寫法：`shelf` 的 handler 一旦回傳 `shelf.Response`（內含尚未
  /// 被消費的 `Stream<List<int>>` 主體），實際位元組傳輸是在 handler 回傳
  /// 之後才由 `shelf_io` 非同步消費該 Stream；若把「建構 Response」當成
  /// 這裡的 [action]，`finally` 會在 Response 物件建好、位元組其實還沒送
  /// 到客戶端前就釋放許可，讓併發節流對下載形同虛設、
  /// [activeTransfersNotifier] 也無法正確反映「離開畫面時是否真的有傳輸
  /// 中」。下載路由改用下方 [_acquirePermit]／[_releasePermit] 手動配對，
  /// 於串流真正結束時才釋放，見 `_handleDownload`。
  Future<T> withTransferPermit<T>(Future<T> Function() action) async {
    await _acquirePermit();
    try {
      return await action();
    } finally {
      _releasePermit();
    }
  }

  /// 取得一個併發傳輸許可；超過 [maxConcurrentTransfers] 時在此等待，直到
  /// 有人呼叫 [_releasePermit]。伺服器已 [stop] 時，仍在排隊中的呼叫會
  /// 以 [StateError] 結束（見 [stop]）。
  Future<void> _acquirePermit() async {
    if (_activePermits >= maxConcurrentTransfers) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
      if (_stopped) {
        throw StateError('WifiTransferHttpServer 已停止，取消排隊中的請求');
      }
    }
    _activePermits++;
    // 【`/receiving-code-review` 審查修正，review-plan-issue-2.md C-1】
    // 伺服器已 dispose() 時，_activeTransfersNotifier 已被銷毀，不可再
    // 寫入 .value（會拋出 FlutterError）——此時已沒有任何 UI 在監聽，
    // 純粹略過通知，計數本身仍照常維護。
    if (!_disposed) {
      _activeTransfersNotifier.value = _activePermits;
    }
  }

  /// 釋放一個由 [_acquirePermit] 取得的許可，喚醒排隊中的下一個呼叫（若有）。
  void _releasePermit() {
    _activePermits--;
    if (!_disposed) {
      _activeTransfersNotifier.value = _activePermits;
    }
    if (_waitQueue.isNotEmpty && !_stopped) {
      _waitQueue.removeAt(0).complete();
    }
  }
```

再修改既有的 `dispose()` 方法（Issue 1 既有程式碼，`review-plan-issue-1.md` Minor #2 引入）：

```dart
// 舊：
  /// 釋放 [_activeTransfersNotifier] 持有的資源（`/receiving-code-review`
  /// 審查修正，review-issue-1.md Minor #2）。呼叫端（`WifiTransferScreen.
  /// dispose()`）應在呼叫 [stop] 之後一併呼叫本方法。
  void dispose() {
    _activeTransfersNotifier.dispose();
  }
```

```dart
// 新：
  bool _disposed = false;

  /// 釋放 [_activeTransfersNotifier] 持有的資源（`/receiving-code-review`
  /// 審查修正，review-issue-1.md Minor #2）。呼叫端（`WifiTransferScreen.
  /// dispose()`）應在呼叫 [stop] 之後一併呼叫本方法。
  ///
  /// **（`/receiving-code-review` 審查修正，review-plan-issue-2.md C-1）**
  /// 先標記 [_disposed]，讓仍在進行中的下載（`stop()` 是非同步的，呼叫端
  /// 不會 `await` 它就緊接著呼叫本方法）稍後觸發 [_releasePermit] 時不會
  /// 對已銷毀的 [_activeTransfersNotifier] 賦值。
  void dispose() {
    _disposed = true;
    _activeTransfersNotifier.dispose();
  }
```

- [x] **Step 3: 執行既有測試，確認重構後仍是綠燈（零回歸）**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: PASS，與 Step 1 相同的測試集合全數通過，行為不變。

- [x] **Step 4: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_http_server.dart`
Expected: `No issues found!`

- [x] **Step 5: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_http_server.dart
git commit -m "$(cat <<'EOF'
refactor(wifi-transfer): withTransferPermit 拆成 _acquirePermit/_releasePermit

epic-44-wifi-book-transfer Issue 2：純內部重構，withTransferPermit()
對外簽章與可觀察行為不變（既有 3 個併發節流測試零回歸）。拆分原因：
下載路由（下個 commit）需要在「shelf.Response 建構完成」與「位元組真正
傳輸完畢」之間持有許可，這個時間差無法用 withTransferPermit() 的
try/finally 包裝表達（handler 回傳 Response 的當下 finally 就會執行，
但此時位元組根本還沒開始送到客戶端）。

一併修正 review-plan-issue-2.md C-1：dispose() 新增 _disposed 旗標，
_acquirePermit/_releasePermit 寫入 activeTransfersNotifier.value 前
檢查 !_disposed——WifiTransferScreen.dispose() 呼叫 wifiServer.stop()
（非同步、未 await）後緊接著同步呼叫 wifiServer.dispose()，使用者若在
下載中途透過 PopScope 確認離開，稍後串流結束觸發的 _releasePermit()
會對已 disposed 的 ValueNotifier 賦值而崩潰，此為使用者可實際觸發的
路徑。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `wrapStreamWithCleanup()` 純函式——下載串流完成時清理

**Files:**
- Modify: `app/lib/wifi_transfer/wifi_transfer_http_server.dart`
- Modify: `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`

**Interfaces:**
- Consumes：無。
- Produces：頂層函式 `Stream<List<int>> wrapStreamWithCleanup(Stream<List<int>> source, Future<void> Function() onFinished)`，供 Task 7 的下載路由包裝 `file.openRead()` 使用。

**（`/receiving-code-review` 審查修正，`review-plan-issue-2.md` I-1／I-2）** 初版設計只轉發資料，沒有轉發下游的暫停/恢復訊號，也沒有在下游取消時等待內部訂閱真正取消完成。這兩個問題必須在本 Task 一併修正：
- **I-1（背壓／OOM 風險＋許可提前釋放）**：`StreamController` 若不實作 `onPause`/`onResume`，下游（`shelf_io` 把 Response body 寫進 socket 時，遇 TCP 壅塞會對其消費的 Stream 呼叫 `pause()`）發出的暫停訊號不會傳遞給內部對 `source`（`file.openRead()`）的訂閱——本機磁碟讀取速度遠快於慢速 WiFi 網路的發送速度，`source` 會不受控制地把整個檔案全部讀進 `controller` 的內部緩衝佇列（無界佇列，不會因為下游暫停而停止累積），大檔案在慢速網路下有 OOM 風險；同時 `source` 很快讀到 EOF 觸發 `onDone`，若 `finishOnce()`（進而釋放併發許可）在這個當下就執行，前面 Task 3 才修正的「許可持有到位元組真正傳輸完畢」設計承諾就被這裡的實作破功——必須改為等待 `controller.done`（等同 `controller.close()` 的回傳值，代表 done 事件已真正送達下游監聽者）完成後才呼叫 `finishOnce()`。
- **I-2（`onCancel` 未等待訂閱真正取消）**：`subscription?.cancel()` 是非同步操作（底層要等作業系統真正釋放檔案控制代碼），若不 `await` 就緊接著呼叫 `finishOnce()`（進而可能呼叫 `deleteFile()`），檔案控制代碼可能尚未被完全釋放就嘗試刪除，有觸發 `FileSystemException` 的風險。

- [x] **Step 1: 寫失敗測試**

Edit `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`，在檔案結尾（最後一個 `});` 之後、`}` 之前）新增一個新的頂層 `group`：

```dart

  group('wrapStreamWithCleanup', () {
    test('來源串流正常 EOF（onDone）：資料原樣轉發，onFinished 恰好被呼叫一次',
        () async {
      final source = StreamController<List<int>>();
      var finishedCount = 0;
      final wrapped = wrapStreamWithCleanup(source.stream, () async {
        finishedCount++;
      });

      final received = <int>[];
      final done = Completer<void>();
      wrapped.listen(
        received.addAll,
        onDone: () => done.complete(),
      );

      source
        ..add([1, 2, 3])
        ..add([4, 5]);
      await source.close();
      await done.future;
      // 【`/receiving-code-review` 審查修正 I-1】onFinished 改為等待
      // controller.done（真正送達下游）才呼叫，與下游自己的 onDone 回呼
      // 是兩個獨立的 Future 鏈，給一次事件迴圈機會讓前者的延續完成。
      await Future<void>.delayed(Duration.zero);

      expect(received, [1, 2, 3, 4, 5]);
      expect(finishedCount, 1);
    });

    test('來源串流拋出讀取例外（onError）：例外會轉發給下游，onFinished 恰好被呼叫一次',
        () async {
      final source = StreamController<List<int>>();
      var finishedCount = 0;
      final wrapped = wrapStreamWithCleanup(source.stream, () async {
        finishedCount++;
      });

      final errors = <Object>[];
      final done = Completer<void>();
      wrapped.listen(
        (_) {},
        onError: (Object error, StackTrace stackTrace) => errors.add(error),
        onDone: () => done.complete(),
      );

      source.addError(StateError('讀取失敗'));
      await done.future;
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(finishedCount, 1);
    });

    test('下游訂閱被 cancel()（模擬客戶端中途取消下載/斷線）：等待內部訂閱真正'
        '取消完成後，onFinished 才恰好被呼叫一次', () async {
      final source = StreamController<List<int>>();
      var finishedCount = 0;
      final wrapped = wrapStreamWithCleanup(source.stream, () async {
        finishedCount++;
      });

      final subscription = wrapped.listen((_) {});
      source.add([1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      // 【`/receiving-code-review` 審查修正 I-2】onCancel 內部須先
      // await 對 source 的訂閱真正取消完成，才呼叫 onFinished；本測試
      // 的 subscription.cancel() 回傳的 Future 須等到那個內部 await
      // 也完成才 resolve（不能提早釋放，實務上對應「檔案控制代碼真正
      // 關閉後才刪除暫存檔」）。
      await subscription.cancel();

      expect(finishedCount, 1);
      expect(source.hasListener, isFalse,
          reason: '下游取消後，內部應已完成對來源 StreamController 的取消訂閱');
    });

    test('onFinished 只會被呼叫一次，即使 onDone 之後下游又被取消', () async {
      final source = StreamController<List<int>>();
      var finishedCount = 0;
      final wrapped = wrapStreamWithCleanup(source.stream, () async {
        finishedCount++;
      });

      final done = Completer<void>();
      final subscription = wrapped.listen((_) {}, onDone: () => done.complete());
      await source.close();
      await done.future;
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(finishedCount, 1);
    });

    test(
        '下游暫停訂閱（onPause）時，內部對來源的訂閱也會暫停——不會在慢速'
        '消費時無視背壓持續灌入資料（審查修正 I-1 的背壓轉發驗證）',
        () async {
      final source = StreamController<List<int>>();
      final wrapped = wrapStreamWithCleanup(source.stream, () async {});

      final received = <int>[];
      final subscription = wrapped.listen(received.addAll);
      subscription.pause();
      await Future<void>.delayed(Duration.zero);

      // `source.isPaused` 反映的是「它自己內部訂閱」（也就是本函式對
      // source 建立的那個 subscription）目前是否被暫停——若 onPause 有
      // 正確轉發，這裡應為 true，證明下游的暫停訊號確實傳到了上游。
      expect(source.isPaused, isTrue,
          reason: '下游暫停應轉發至內部對 source 的訂閱（背壓正確傳遞）');
      source.add([1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty,
          reason: '下游暫停期間，資料不應被送達（背壓已正確轉發至來源）');

      subscription.resume();
      await Future<void>.delayed(Duration.zero);
      expect(received, [1, 2, 3]);

      await subscription.cancel();
    });
  });
```

在檔案頂部新增 import（若尚未存在）：

```dart
// 於既有 import 區塊新增：
import 'dart:async';
```

（`dart:async` 已因 `Completer` 使用被既有測試 import，若編譯器提示重複 import 則略過此步驟。）

- [x] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: FAIL，編譯錯誤（`wrapStreamWithCleanup` 尚未定義）。

- [x] **Step 3: 實作 `wrapStreamWithCleanup()`**

Edit `app/lib/wifi_transfer/wifi_transfer_http_server.dart`，在 `WifiTransferHttpServer` 類別定義**之後**（檔案結尾）新增：

```dart

/// 把 [source] 包裝成一個轉接 `Stream`，在來源串流真正結束時（正常
/// EOF、讀取例外，或下游訂閱被取消——三者對應下載請求的「正常完成」
/// 「讀取失敗」「客戶端中途取消/斷線」）非同步呼叫恰好一次 [onFinished]
/// （epic-44-wifi-book-transfer spec.md「HTTP 路由表」暫存檔清理時機）。
/// `shelf` 的 `Response` 沒有內建「串流真正傳輸完成」回呼，若在回傳
/// `Response.ok(...)` 之後立即清理暫存檔／釋放併發許可，會在客戶端仍在
/// 讀取串流中途執行，造成 0 位元組回應或許可提前釋放讓節流形同虛設。
Stream<List<int>> wrapStreamWithCleanup(
  Stream<List<int>> source,
  Future<void> Function() onFinished,
) {
  var finished = false;
  Future<void> finishOnce() {
    if (finished) return Future<void>.value();
    finished = true;
    return onFinished();
  }

  StreamSubscription<List<int>>? subscription;
  late final StreamController<List<int>> controller;
  controller = StreamController<List<int>>(
    onListen: () {
      subscription = source.listen(
        controller.add,
        onError: (Object error, StackTrace stackTrace) {
          controller.addError(error, stackTrace);
          controller.close();
          finishOnce();
        },
        onDone: () {
          // 【`/receiving-code-review` 審查修正 I-1】controller.close() 只
          // 代表「不會再新增事件」，controller.done 才是「done 事件已真正
          // 送達下游監聽者」——許可（Task 3 的 _releasePermit）／暫存檔
          // 清理必須等到這個時間點才執行，否則會在資料其實還在 controller
          // 內部緩衝佇列、尚未送達 shelf_io／客戶端時就提前釋放。
          controller.close();
          controller.done.then((_) => finishOnce());
        },
        cancelOnError: true,
      );
    },
    // 【`/receiving-code-review` 審查修正 I-1】把下游（`shelf_io` 寫入
    // socket 時）的暫停/恢復訊號轉發給內部對 [source] 的訂閱，避免
    // `file.openRead()` 在慢速網路下無視背壓、把整個檔案讀進無界的
    // controller 內部緩衝佇列（大檔案 OOM 風險）。
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      // 【`/receiving-code-review` 審查修正 I-2】先 await 內部訂閱真正
      // 取消完成（底層檔案控制代碼確實釋放）才呼叫 finishOnce()（可能
      // 觸發 deleteFile()），避免控制代碼尚未釋放就嘗試刪除檔案。
      await subscription?.cancel();
      await finishOnce();
    },
  );
  return controller.stream;
}
```

- [x] **Step 4: 執行測試，確認通過**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: PASS，`wrapStreamWithCleanup` 群組的 5 個測試（連同其餘既有測試）全數通過。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_http_server.dart test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_http_server.dart app/test/wifi_transfer/wifi_transfer_http_server_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 新增 wrapStreamWithCleanup() 純函式

epic-44-wifi-book-transfer Issue 2：把來源 Stream 包裝成在正常 EOF／
讀取例外／下游訂閱被取消三種情境下，皆非同步呼叫恰好一次 onFinished
的轉接 Stream，供下載路由（下個 commit）包裝 file.openRead() 使用。
用一個布林旗標確保 onFinished 不會被重複呼叫（例如 onDone 之後下游又
被取消）。

一併修正 review-plan-issue-2.md I-1/I-2：
- I-1：onPause/onResume 轉發下游暫停訊號給內部對 source 的訂閱，避免
  慢速網路下 file.openRead() 無視背壓把整個檔案讀進無界緩衝佇列
  （OOM 風險）；onDone 改為等待 controller.done（真正送達下游）才呼叫
  onFinished，不再是 controller.close() 的當下就視為完成，讓 Task 3
  「許可持有到位元組真正傳輸完畢」的設計承諾對下載真正成立。
- I-2：onCancel 先 await 內部訂閱真正取消完成，才呼叫 onFinished（可能
  觸發 deleteFile()），避免檔案控制代碼尚未釋放就嘗試刪除。

純 Dart 單元測試以真實 StreamController 驅動五種情境（含新增的暫停/
恢復背壓轉發驗證）。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `buildContentDispositionHeader()` 純函式——下載檔名標頭

**Files:**
- Modify: `app/lib/wifi_transfer/wifi_transfer_http_server.dart`
- Modify: `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`

**Interfaces:**
- Consumes：無。
- Produces：頂層函式 `String buildContentDispositionHeader(String downloadFileName)`，供 Task 7 的下載路由組 `content-disposition` 標頭值。

- [x] **Step 1: 寫失敗測試**

Edit `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`，在 `wrapStreamWithCleanup` 群組**之後**新增：

```dart

  group('buildContentDispositionHeader', () {
    test('純 ASCII 檔名：fallback 與 filename* 皆為原始檔名', () {
      final header = buildContentDispositionHeader('book.epub');
      expect(header,
          "attachment; filename=\"book.epub\"; filename*=UTF-8''book.epub");
    });

    test('中文檔名：fallback 以底線替代非 ASCII 字元，filename* 為 percent-encoded '
        '原始檔名（同時支援中文書名正確顯示）', () {
      final header = buildContentDispositionHeader('書名.epub');
      expect(
        header,
        "attachment; filename=\"__.epub\"; "
        "filename*=UTF-8''%E6%9B%B8%E5%90%8D.epub",
      );
    });

    test('檔名含雙引號與反斜線：fallback 以底線替代，避免破壞 quoted-string 語法',
        () {
      final header = buildContentDispositionHeader('a"b\\c.epub');
      expect(header, contains('filename="a_b_c.epub"'));
    });

    test(
        '檔名含 CRLF（模擬惡意書名中繼資料嘗試 HTTP header injection）：'
        'fallback 與 filename* 皆不含原始的 \\r／\\n 位元組', () {
      final malicious = 'evil\r\nSet-Cookie: x=1.epub';
      final header = buildContentDispositionHeader(malicious);

      expect(header.contains('\r'), isFalse);
      expect(header.contains('\n'), isFalse);
    });

    test(
        '檔名含單引號（`/receiving-code-review` 審查修正 M-1）：filename* '
        '中的單引號額外跳脫為 %27，不與 UTF-8\'\' 語法本身的分隔符混淆',
        () {
      final header = buildContentDispositionHeader("John's Book.epub");
      expect(header, contains("filename*=UTF-8''John%27s%20Book.epub"));
      expect(
        header.substring(header.indexOf("filename*=UTF-8''") + 18),
        isNot(contains("'")),
      );
    });

    test('空字串輸入：fallback 退回單一底線，不產生空的 quoted-string', () {
      final header = buildContentDispositionHeader('');
      expect(header, contains('filename="_"'));
    });
  });
```

- [x] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: FAIL，編譯錯誤（`buildContentDispositionHeader` 尚未定義）。

- [x] **Step 3: 實作 `buildContentDispositionHeader()`**

Edit `app/lib/wifi_transfer/wifi_transfer_http_server.dart`，在 `wrapStreamWithCleanup()` 函式**之後**（檔案結尾）新增：

```dart

/// 建構下載路由的 `Content-Disposition` 標頭值（RFC 5987/6266，spec.md
/// 「HTTP 路由表」）：`filename` 提供給不支援 `filename*` 的舊版客戶端
/// 當退路（僅保留可安全放進雙引號 quoted-string 的可列印 ASCII 字元，
/// 控制字元/非 ASCII 一律替換為 `_`），`filename*` 用 `Uri.encodeComponent`
/// 完整 percent-encode 原始檔名，同時支援中文書名在跨平台瀏覽器正確
/// 顯示。**安全性**：[downloadFileName] 源自使用者可匯入的書籍標題（不可
/// 信任輸入，例如惡意 EPUB 中繼資料可能夾帶 `\r\n` 意圖進行 HTTP header
/// injection）——兩個輸出分支皆對原始字串做完整轉換（ASCII 白名單過濾／
/// percent-encoding），任何控制字元皆不會以原始位元組型式出現在標頭值中。
String buildContentDispositionHeader(String downloadFileName) {
  final fallback = _asciiFallbackFilename(downloadFileName);
  // 【`/receiving-code-review` 審查修正，review-plan-issue-2.md M-1】
  // `Uri.encodeComponent`（比照 JavaScript `encodeURIComponent`）刻意
  // 不 percent-encode `- _ . ! ~ * ' ( )` 這組「unreserved」字元，但
  // RFC 5987 的 `attr-char` 文法明確排除單引號——單引號同時也是
  // `filename*=UTF-8''<value>` 語法本身的分隔符，若書名含 `'`（例如
  // `John's Book.epub`）没有另外處理會不符合規範，額外手動跳脫為
  // `%27`。
  final encoded =
      Uri.encodeComponent(downloadFileName).replaceAll("'", '%27');
  return 'attachment; filename="$fallback"; filename*=UTF-8\'\'$encoded';
}

String _asciiFallbackFilename(String filename) {
  final buffer = StringBuffer();
  for (final rune in filename.runes) {
    final isSafePrintableAscii =
        rune >= 0x20 && rune <= 0x7E && rune != 0x22 && rune != 0x5C;
    buffer.writeCharCode(isSafePrintableAscii ? rune : 0x5F); // '_'
  }
  final result = buffer.toString();
  return result.isEmpty ? '_' : result;
}
```

- [x] **Step 4: 執行測試，確認通過**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: PASS，`buildContentDispositionHeader` 群組的 6 個測試（連同其餘既有測試）全數通過。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_http_server.dart test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_http_server.dart app/test/wifi_transfer/wifi_transfer_http_server_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 新增 buildContentDispositionHeader() 純函式

epic-44-wifi-book-transfer Issue 2：RFC 5987/6266 Content-Disposition
標頭值——filename 為 ASCII 安全退路（控制字元/非 ASCII 替換為 _，避免
破壞 quoted-string 語法），filename* 為完整 percent-encoded 原始檔名
（支援中文書名）。兩個輸出分支皆對原始輸入做完整轉換，惡意書名夾帶
\r\n 等控制字元不會以原始位元組型式出現在標頭值中（HTTP header
injection 防護），測試含此情境的明確驗證。

一併修正 review-plan-issue-2.md M-1：filename* 額外把 Uri.encodeComponent
刻意不編碼的單引號手動跳脫為 %27（RFC 5987 attr-char 文法排除單引號，
且單引號同時是 UTF-8''<value> 語法本身的分隔符）。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `GET /api/books` 路由實作

**Files:**
- Modify: `app/lib/wifi_transfer/wifi_transfer_http_server.dart`
- Modify: `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`

**Interfaces:**
- Consumes：`WifiTransferService.listDownloadableBooks()`（Task 1）。
- Produces：`GET /api/books` 回傳 JSON 陣列 `[{id, title, format, sizeBytes}]`（`content-type: application/json; charset=utf-8`）。

- [x] **Step 1: 寫失敗測試**

Edit `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`：先在檔案頂部新增 import（`dart:convert` 已因既有 `_sendRealRequest` 的 `utf8.decoder` 使用而存在，不重複新增）：

```dart
// 於既有 import 區塊新增：
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
```

把既有的 `GET /api/books 回傳 501（留給 Issue 2 實作）` 測試整條**取代**為：

```dart
    test('GET /api/books 回傳 JSON 陣列，欄位對應正確且僅列出 isDownloaded 書籍',
        () async {
      final now = DateTime.fromMillisecondsSinceEpoch(0);
      final downloaded = Book(
        id: 'b1',
        title: '已下載的書',
        format: BookFileFormat.epub,
        filePath: 'content://com.example/document/1',
        source: BookSource.local,
        createTime: now,
        lastReadTime: now,
      );
      final notDownloaded = Book(
        id: 'b2',
        title: '未下載的書',
        format: BookFileFormat.pdf,
        filePath: 'content://com.example/document/2',
        source: BookSource.local,
        isDownloaded: false,
        createTime: now,
        lastReadTime: now,
      );
      final serverWithBooks = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(
            initialBooks: [downloaded, notDownloaded],
          ),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final serverWithBooksHttp =
          await serverWithBooks.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => serverWithBooks.stop(serverWithBooksHttp));

      final response = await _realGet(
          'http://127.0.0.1:${serverWithBooksHttp.port}/api/books');

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('application/json'));
      expect(response.headers['cache-control'], 'no-cache');
      final payload = jsonDecode(response.body) as List<dynamic>;
      expect(payload, hasLength(1));
      final entry = payload.single as Map<String, dynamic>;
      expect(entry['id'], 'b1');
      expect(entry['title'], '已下載的書');
      expect(entry['format'], 'epub');
      expect(entry['sizeBytes'], isNull);
    });
```

（此測試不使用 `setUp` 建立的共用 `wifiServer`/`httpServer`——需要自訂的 `FakeLibraryRepository(initialBooks: ...)`，故自行 `start`/`addTearDown(stop)`，比照本檔案 `withTransferPermit 併發節流` 群組既有的獨立實例慣例。）

- [x] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: FAIL——回應狀態碼為 501，不是 200。

- [x] **Step 3: 實作 `GET /api/books` 路由**

Edit `app/lib/wifi_transfer/wifi_transfer_http_server.dart`：

```dart
// 舊：
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'wifi_transfer_service.dart';
```

```dart
// 新：
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'wifi_transfer_service.dart';
```

```dart
// 舊：
    if (request.method == 'GET' && path == 'api/books') {
      // Issue 2 補上：service.listDownloadableBooks()。
      return shelf.Response(501, body: 'Not Implemented');
    }
```

```dart
// 新：
    if (request.method == 'GET' && path == 'api/books') {
      return _handleListBooks();
    }
```

在 `_handleRequest()` 方法**之後**（`WifiTransferHttpServer` 類別結尾之前）新增：

```dart

  Future<shelf.Response> _handleListBooks() async {
    final books = await service.listDownloadableBooks();
    final payload = [
      for (final book in books)
        {
          'id': book.id,
          'title': book.title,
          'format': book.format.name,
          'sizeBytes': book.sizeBytes,
        },
    ];
    return shelf.Response.ok(
      jsonEncode(payload),
      headers: {
        'content-type': 'application/json; charset=utf-8',
        // 【`/receiving-code-review` 審查修正，review-plan-issue-2.md
        // M-2】比照 Issue 1 的 GET / 路由既有理由：這份清單反映手機當下
        // 的圖書庫狀態（使用者可能在 PC 端頁面開著時於手機端刪書/匯入），
        // 不該被瀏覽器快取。
        'cache-control': 'no-cache',
      },
    );
  }
```

- [x] **Step 4: 執行測試，確認通過**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: PASS，全數測試通過。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_http_server.dart test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_http_server.dart app/test/wifi_transfer/wifi_transfer_http_server_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 實作 GET /api/books 路由

epic-44-wifi-book-transfer Issue 2：呼叫
WifiTransferService.listDownloadableBooks()，回傳 JSON 陣列
[{id, title, format, sizeBytes}]（content-type: application/json，
cache-control: no-cache——review-plan-issue-2.md M-2，比照 GET / 既有
理由：清單反映即時圖書庫狀態，不該被瀏覽器快取）。新增私有
_handleListBooks()。測試驗證欄位對應、isDownloaded 過濾與快取標頭。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `GET /api/books/<id>/download` 路由實作

**Files:**
- Modify: `app/lib/wifi_transfer/wifi_transfer_http_server.dart`
- Modify: `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`

**Interfaces:**
- Consumes：`WifiTransferService.resolveDownloadSource()`（Task 2）、`_acquirePermit()`／`_releasePermit()`（Task 3）、`wrapStreamWithCleanup()`（Task 4）、`buildContentDispositionHeader()`（Task 5）。
- Produces：`GET /api/books/<id>/download` 路由——找不到書籍回 404；成功則以 `Content-Disposition`＋正確 `Content-Length` 串流檔案；`isTemporaryFile == true` 時下載完成/中途取消後刪除暫存檔（`deleteFile` 失敗一律吞掉，不冒出未捕捉例外——`/receiving-code-review` 審查修正 I-5）；`resolveDownloadSource()` 成功後、真正建立串流前若拋出任何例外，仍會清理已材質化的 content:// 暫存檔（審查修正 I-3）；併發許可持有到串流真正結束才釋放（見 Task 3 說明）。

- [x] **Step 1: 寫失敗測試**

Edit `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`。下載路由回應是二進位內容（PDF/EPUB 位元組），既有的 `_realGet`／`_sendRealRequest` 一律用 `utf8.decoder` 把回應主體解碼成 `String`——對任意二進位內容（非合法 UTF-8 位元組序列，例如真實 PDF 檔案）幾乎必定拋出 `FormatException`，不能直接沿用。先在 `_realPost` 定義**之後**新增一組專供二進位回應使用的獨立 helper：

```dart
class _BytesResp {
  final int statusCode;
  final Map<String, String> headers;
  final List<int> bodyBytes;
  _BytesResp(this.statusCode, this.headers, this.bodyBytes);
}

Future<_BytesResp> _realGetBytes(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
    }
    final headers = <String, String>{};
    resp.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    return _BytesResp(resp.statusCode, headers, bytes);
  } finally {
    client.close(force: true);
  }
}
```

再把既有的 `GET /api/books/<id>/download 回傳 501（留給 Issue 2 實作）` 測試整條**取代**為（回應主體固定是純文字 `Not Found`，合法 UTF-8，可安全沿用 `_realGet`）：

```dart
    test('GET /api/books/<id>/download：找不到書籍回傳 404', () async {
      final response = await _realGet(
          'http://127.0.0.1:${httpServer.port}/api/books/no-such-book/download');
      expect(response.statusCode, 404);
    });
```

在同一個測試檔的 `withTransferPermit 併發節流` 群組**之後**（`}` 結尾之前）新增一個新的 `group`：

```dart

  group('GET /api/books/<id>/download', () {
    Book bookWith({
      required String id,
      required String filePath,
      String title = '書名',
      BookFileFormat format = BookFileFormat.epub,
    }) {
      final now = DateTime.fromMillisecondsSinceEpoch(0);
      return Book(
        id: id,
        title: title,
        format: format,
        filePath: filePath,
        source: BookSource.local,
        createTime: now,
        lastReadTime: now,
      );
    }

    test('本機路徑來源：回傳正確位元組、Content-Length 與 Content-Disposition',
        () async {
      final book = bookWith(
        id: 'b1',
        filePath: 'test/fixtures/sample.pdf',
        title: '測試書',
        format: BookFileFormat.pdf,
      );
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realGetBytes(
          'http://127.0.0.1:${server.port}/api/books/b1/download');

      final expectedBytes = await File('test/fixtures/sample.pdf').readAsBytes();
      expect(response.statusCode, 200);
      expect(response.bodyBytes, expectedBytes);
      expect(response.headers['content-length'], '${expectedBytes.length}');
      expect(response.headers['content-disposition'],
          contains(buildContentDispositionHeader('測試書.pdf')));
    });

    test('content:// 來源：呼叫 materializeContentUri，下載完成後呼叫 deleteFile '
        '恰好一次', () async {
      final tempFile = File(
          '${Directory.systemTemp.path}/wifi_transfer_download_test_${DateTime.now().microsecondsSinceEpoch}.epub');
      await tempFile.writeAsBytes([1, 2, 3, 4, 5]);
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });
      final book = bookWith(
        id: 'b1',
        filePath: 'content://com.example/document/1',
        title: 'content 書',
      );
      final deleteCalls = <String>[];
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => tempFile.path,
          deleteFile: (path) async {
            deleteCalls.add(path);
            if (await File(path).exists()) await File(path).delete();
          },
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realGetBytes(
          'http://127.0.0.1:${server.port}/api/books/b1/download');

      expect(response.statusCode, 200);
      expect(response.bodyBytes, [1, 2, 3, 4, 5]);
      expect(deleteCalls, [tempFile.path]);
    });

    test('resolveDownloadSource 回傳 null（材質化失敗）：回傳 404', () async {
      final book =
          bookWith(id: 'b1', filePath: 'content://com.example/document/1');
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realGet(
          'http://127.0.0.1:${server.port}/api/books/b1/download');

      expect(response.statusCode, 404);
    });

    test(
        'resolveDownloadSource 成功後、file.length() 才拋出例外：仍會清理'
        '已材質化的 content:// 暫存檔並釋放許可（審查修正 I-3）', () async {
      final book =
          bookWith(id: 'b1', filePath: 'content://com.example/document/1');
      final deleteCalls = <String>[];
      final nonexistentPath =
          '${Directory.systemTemp.path}/wifi_transfer_i3_test_${DateTime.now().microsecondsSinceEpoch}.epub';
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          // 回傳一個不存在的路徑，模擬材質化「回報成功」但緊接著
          // file.length() 讀取時才發現實際上失敗（例如檔案系統極短暫的
          // 競態）——重點是驗證 catch 區塊確實會嘗試清理這個路徑。
          materializeContentUri: (uri) async => nonexistentPath,
          deleteFile: (path) async {
            deleteCalls.add(path);
          },
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realGet(
          'http://127.0.0.1:${server.port}/api/books/b1/download');

      expect(response.statusCode, 500);
      expect(deleteCalls, [nonexistentPath]);
      expect(wifiServer.activeTransfersNotifier.value, 0);
    });

    test(
        'deleteFile 清理暫存檔時拋出例外：不會成為未捕捉的非同步例外，'
        '許可仍正確釋放（審查修正 I-5）', () async {
      final tempFile = File(
          '${Directory.systemTemp.path}/wifi_transfer_i5_test_${DateTime.now().microsecondsSinceEpoch}.epub');
      await tempFile.writeAsBytes([1, 2, 3]);
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });
      final book =
          bookWith(id: 'b1', filePath: 'content://com.example/document/1');
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => tempFile.path,
          deleteFile: (path) async => throw FileSystemException('模擬刪除失敗'),
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realGetBytes(
          'http://127.0.0.1:${server.port}/api/books/b1/download');

      expect(response.statusCode, 200);
      expect(response.bodyBytes, [1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      expect(wifiServer.activeTransfersNotifier.value, 0);
    });

    test(
        '下載期間 activeTransfersNotifier 維持在 1，直到用戶端讀完整個回應串流'
        '（許可涵蓋整個串流生命週期，非僅至 Response 建構完成——Task 3/7 的'
        '設計修正）', () async {
      final book = bookWith(id: 'b1', filePath: 'test/fixtures/sample.pdf');
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
        maxConcurrentTransfers: 1,
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/api/books/b1/download'));
      final response = await request.close();

      expect(wifiServer.activeTransfersNotifier.value, 1,
          reason: '許可應持續持有，直到位元組真正傳輸完畢，而非 Response 建構'
              '完成的當下就釋放');

      await response.drain<void>();
      await Future<void>.delayed(Duration.zero);

      expect(wifiServer.activeTransfersNotifier.value, 0);
    });
  });
```

（`Book`／`BookFileFormat`／`BookSource` 已於 Task 6 加入 import；`dart:io` 的 `HttpClient`／`File`／`Directory` 已由檔案既有 import 涵蓋。）

- [x] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: FAIL——下載相關測試回應狀態碼為 501，不是 200/404；`activeTransfersNotifier` 測試因路由仍是 501 佔位而不成立。

- [x] **Step 3: 實作 `GET /api/books/<id>/download` 路由**

Edit `app/lib/wifi_transfer/wifi_transfer_http_server.dart`：

```dart
// 舊：
    if (request.method == 'GET' &&
        RegExp(r'^api/books/[^/]+/download$').hasMatch(path)) {
      // Issue 2 補上：service.resolveDownloadSource()。
      return shelf.Response(501, body: 'Not Implemented');
    }
```

```dart
// 新：
    final downloadMatch =
        RegExp(r'^api/books/([^/]+)/download$').firstMatch(path);
    if (request.method == 'GET' && downloadMatch != null) {
      return _handleDownload(downloadMatch.group(1)!);
    }
```

在 `_handleListBooks()` 方法**之後**（`WifiTransferHttpServer` 類別結尾之前）新增：

```dart

  /// 處理 `GET /api/books/<id>/download`（epic-44-wifi-book-transfer
  /// spec.md「HTTP 路由表」）。併發許可改用 [_acquirePermit]／
  /// [_releasePermit] 手動配對（而非 [withTransferPermit]），理由見
  /// [withTransferPermit] 文件註解：許可須持有到位元組真正傳輸完畢（由
  /// [wrapStreamWithCleanup] 的完成/例外/取消三個回呼觸發釋放），不能在
  /// `Response` 物件建構完成的當下就釋放。
  Future<shelf.Response> _handleDownload(String bookId) async {
    await _acquirePermit();
    var permitReleased = false;
    void releasePermitOnce() {
      if (permitReleased) return;
      permitReleased = true;
      _releasePermit();
    }
    // 【`/receiving-code-review` 審查修正，review-plan-issue-2.md I-3】
    // 提升到 try 區塊外宣告，讓下方 catch 區塊能存取已材質化的
    // content:// 暫存檔路徑並清理——原設計把它宣告在 try 內，catch 區塊
    // 根本無法引用它（連編譯都過不了），materializeContentUri() 產生的
    // 暫存檔在 resolveDownloadSource() 成功之後、file.length() 之前若
    // 拋出任何例外，會永久殘留在快取目錄中。
    DownloadSource? source;
    try {
      source = await service.resolveDownloadSource(bookId);
      if (source == null) {
        releasePermitOnce();
        return shelf.Response.notFound('Not Found');
      }
      final file = File(source.resolvedPath);
      final length = await file.length();
      var cleanedUp = false;
      Future<void> finishOnce() async {
        if (cleanedUp) return;
        cleanedUp = true;
        releasePermitOnce();
        if (source!.isTemporaryFile) {
          // 【審查修正 I-5】刪除暫存檔是 best-effort 清理，失敗（例如
          // 已被其他流程刪除）不應成為未捕捉的非同步例外冒出、觸發全域
          // 錯誤處理器——比照本專案既有「靜默略過非關鍵清理失敗」慣例。
          try {
            await service.deleteFile(source.resolvedPath);
          } catch (_) {}
        }
      }
      final body = wrapStreamWithCleanup(file.openRead(), finishOnce);
      return shelf.Response.ok(
        body,
        headers: {
          'content-type': 'application/octet-stream',
          'content-length': '$length',
          'content-disposition':
              buildContentDispositionHeader(source.downloadFileName),
        },
      );
    } catch (_) {
      releasePermitOnce();
      // 【審查修正 I-3】resolveDownloadSource() 成功後、file.length() 之前
      // 若拋出例外，已材質化的 content:// 暫存檔仍須清理，否則永久洩漏。
      final resolvedSource = source;
      if (resolvedSource != null && resolvedSource.isTemporaryFile) {
        try {
          await service.deleteFile(resolvedSource.resolvedPath);
        } catch (_) {}
      }
      rethrow;
    }
  }
```

- [x] **Step 4: 執行測試，確認通過**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: PASS，全數測試通過（含 Task 1～6 累積的所有測試）。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_http_server.dart test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_http_server.dart app/test/wifi_transfer/wifi_transfer_http_server_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 實作 GET /api/books/<id>/download 路由

epic-44-wifi-book-transfer Issue 2：resolveDownloadSource() 找不到回
404；成功則用 wrapStreamWithCleanup() 包裝 file.openRead()，串流真正
結束（EOF/例外/客戶端中途取消）時才呼叫 deleteFile()（isTemporaryFile
時）並釋放併發許可——許可用 _acquirePermit()/_releasePermit() 手動配對，
涵蓋整個串流生命週期，不是 Response 建構完成的當下就釋放（見
_acquirePermit 重構 commit 的說明）。Content-Disposition／Content-Length
標頭正確設定。新增 _handleDownload()。測試涵蓋本機路徑/content://
來源、材質化失敗回 404、以及許可涵蓋完整串流生命週期的直接驗證。

一併修正 review-plan-issue-2.md I-3/I-5：
- I-3：DownloadSource? source 提升到 try 區塊外宣告（原設計宣告在
  try 內，catch 區塊根本無法引用，連編譯都過不了），resolveDownloadSource()
  成功後、file.length() 之前若拋出例外，catch 區塊仍會清理已材質化的
  content:// 暫存檔，不會永久洩漏。
- I-5：finishOnce() 與 catch 區塊呼叫 deleteFile() 皆包 try-catch 靜默
  吞掉失敗（best-effort 清理，比照既有「靜默略過非關鍵清理失敗」慣例），
  避免非同步例外冒出觸發全域錯誤處理器。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: `assets/wifi_transfer/index.html` 下載區塊 JS

**Files:**
- Modify: `app/assets/wifi_transfer/index.html`

**Interfaces:**
- Consumes：`GET /api/books`（Task 6）、`GET /api/books/<id>/download`（Task 7）。
- Produces：頁面載入時渲染可下載書籍勾選清單；使用者勾選後依序觸發下載。無自動化測試（純 HTML/JS，不在 `flutter test`／`flutter analyze` 範圍內；由 Task 9 的 `integration_test/` 透過實際 HTTP 呼叫間接驗證背後路由，頁面本身的視覺/互動建議另行人工於桌面瀏覽器開啟驗證）。

- [x] **Step 1: 修改 `index.html`**

Edit `app/assets/wifi_transfer/index.html`：

```html
<!-- 舊： -->
<style>
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    margin: 0;
    padding: 16px;
    background: #f5f5f5;
    color: #222;
  }
  h1 { font-size: 20px; }
  section {
    background: #fff;
    border-radius: 8px;
    padding: 16px;
    margin-bottom: 16px;
  }
  .placeholder { color: #888; }
</style>
</head>
<body>
  <h1>elinkBook WiFi 傳書</h1>
  <section id="download-section">
    <h2>下載書籍</h2>
    <p class="placeholder">開發中（Issue 2）</p>
  </section>
  <section id="upload-section">
    <h2>上傳書籍</h2>
    <p class="placeholder">開發中（Issue 3）</p>
  </section>
</body>
</html>
```

```html
<!-- 新： -->
<style>
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    margin: 0;
    padding: 16px;
    background: #f5f5f5;
    color: #222;
  }
  h1 { font-size: 20px; }
  section {
    background: #fff;
    border-radius: 8px;
    padding: 16px;
    margin-bottom: 16px;
  }
  .placeholder { color: #888; }
  .book-item { display: block; padding: 4px 0; }
  button { font-size: 14px; padding: 8px 16px; margin-top: 8px; }
</style>
</head>
<body>
  <h1>elinkBook WiFi 傳書</h1>
  <section id="download-section">
    <h2>下載書籍</h2>
    <div id="download-list" class="placeholder">載入中…</div>
    <button id="download-selected-button" type="button">下載已勾選書籍</button>
    <p id="download-status" class="placeholder"></p>
  </section>
  <section id="upload-section">
    <h2>上傳書籍</h2>
    <p class="placeholder">開發中（Issue 3）</p>
  </section>
  <script>
    function formatBytes(bytes) {
      if (bytes == null) return '';
      if (bytes < 1024) return ' (' + bytes + ' B)';
      if (bytes < 1024 * 1024) return ' (' + (bytes / 1024).toFixed(1) + ' KB)';
      return ' (' + (bytes / (1024 * 1024)).toFixed(1) + ' MB)';
    }

    async function loadDownloadableBooks() {
      const listEl = document.getElementById('download-list');
      try {
        const response = await fetch('/api/books');
        const books = await response.json();
        if (books.length === 0) {
          listEl.textContent = '目前沒有可下載的書籍';
          listEl.className = 'placeholder';
          return;
        }
        listEl.className = '';
        listEl.innerHTML = '';
        for (const book of books) {
          const label = document.createElement('label');
          label.className = 'book-item';
          const checkbox = document.createElement('input');
          checkbox.type = 'checkbox';
          checkbox.value = book.id;
          checkbox.className = 'download-book-checkbox';
          label.appendChild(checkbox);
          label.appendChild(
            document.createTextNode(' ' + book.title + formatBytes(book.sizeBytes))
          );
          listEl.appendChild(label);
        }
      } catch (err) {
        listEl.textContent = '無法載入書籍清單';
        listEl.className = 'placeholder';
      }
    }

    // 依序（for...of + await）逐一觸發下載：<a download> 程式化點擊觸發的
    // 瀏覽器原生下載沒有 JS 可觀察的「完成」事件，改用短暫延遲讓每個下載
    // 至少先各自開始，而非同一瞬間一次全部觸發；伺服器端的併發節流
    // （withTransferPermit/_acquirePermit）才是真正保證同時傳輸數量上限
    // 的機制，這裡的延遲只是讓 PC 端使用體感更像「依序」。
    //
    // 【`/receiving-code-review` 審查修正，review-plan-issue-2.md M-2】
    // 未勾選任何書籍時給予明確提示（而非靜默無反應）；按鈕在下載期間
    // disabled，避免使用者快速連點觸發多輪重入下載。
    async function downloadSelectedBooks() {
      const statusEl = document.getElementById('download-status');
      const button = document.getElementById('download-selected-button');
      const checkboxes =
        document.querySelectorAll('.download-book-checkbox:checked');
      if (checkboxes.length === 0) {
        statusEl.textContent = '請至少勾選一本書';
        return;
      }
      button.disabled = true;
      statusEl.textContent = '下載中…';
      try {
        for (const checkbox of checkboxes) {
          const link = document.createElement('a');
          link.href = '/api/books/' + encodeURIComponent(checkbox.value) + '/download';
          link.download = '';
          document.body.appendChild(link);
          link.click();
          document.body.removeChild(link);
          await new Promise((resolve) => setTimeout(resolve, 300));
        }
        statusEl.textContent = '已觸發全部下載';
      } finally {
        button.disabled = false;
      }
    }

    document
      .getElementById('download-selected-button')
      .addEventListener('click', downloadSelectedBooks);

    loadDownloadableBooks();
  </script>
</body>
</html>
```

- [x] **Step 2: 執行既有測試，確認未破壞 `GET /` 驗證**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: PASS——`GET / 回傳 index.html 內容與正確 Content-Type／Cache-Control` 測試仍通過（只斷言 `contains('elinkBook WiFi 傳書')`，`<h1>` 未變動）。

- [x] **Step 3: Commit**

```bash
git add app/assets/wifi_transfer/index.html
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): index.html 補上下載區塊 JS

epic-44-wifi-book-transfer Issue 2：頁面載入時 fetch('/api/books') 渲染
勾選清單（含檔案大小顯示）；使用者勾選後依序（for...of + await，搭配
300ms 間隔近似「依序」體感）建立 <a download> 並程式化點擊觸發下載，
下載進度交由瀏覽器原生下載列顯示。未勾選任何書籍時提示「請至少勾選
一本書」，下載期間按鈕 disabled 避免快速連點重入（review-plan-issue-2.md
M-2）。無自動化測試（純 HTML/JS，背後路由已由
wifi_transfer_http_server_test.dart 覆蓋，整體串接由 Issue 2
integration_test 驗證）。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: `integration_test/wifi_transfer_screen_test.dart`——真機下載驗證

**Files:**
- Modify: `app/integration_test/wifi_transfer_screen_test.dart`

**Interfaces:**
- Consumes：`WifiTransferScreen`（Issue 1）、`elinkbook/book_metadata` channel 的 `createTestContentUri`／`takePersistableUriPermission`（既有測試專用方法，見 `content_uri_acceptance_test.dart` 既有先例）。
- Produces：4 個新增 `testWidgets`，真機驗證本機路徑／`content://`／TXT 來源下載，以及中途取消下載後暫存檔仍會被清理。**必須在真實裝置上執行**（`-d <device-id>`），且裝置須已連上 WiFi 或已開啟手機熱點。

- [x] **Step 1: 修改測試檔**

Edit `app/integration_test/wifi_transfer_screen_test.dart`，整份取代為：

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/wifi_transfer_screen.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';

import '../test/support/fake_book_import_service.dart';
import '../test/support/fake_library_repository.dart';
import '../test/support/fake_fingerprint_computer.dart';

const _metadataChannel = MethodChannel('elinkbook/book_metadata');

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑（比照
/// `content_uri_acceptance_test.dart` 既有慣例）。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 在 [path] 檔案結尾附加 [megabytes] MB 的零位元組填充，讓「中途取消
/// 下載」測試有足夠大的檔案，提高真的能在串流傳輸「中途」（而非傳輸剛
/// 完成後）觸發取消的機率。
Future<void> _padFileWithZeros(String path, int megabytes) async {
  final padding = Uint8List(megabytes * 1024 * 1024);
  await File(path).writeAsBytes(padding, mode: FileMode.append);
}

Future<String> _createAndAuthorizeContentUri(String localPath) async {
  final contentUri = await _metadataChannel
      .invokeMethod<String>('createTestContentUri', {'path': localPath});
  if (contentUri == null) {
    fail('createTestContentUri 未回傳有效的 content:// URI');
  }
  await _metadataChannel
      .invokeMethod<void>('takePersistableUriPermission', {'uri': contentUri});
  return contentUri;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '真機：伺服器成功綁定 socket，GET / 可取得首頁 HTML（Issue 1 骨架驗證，'
      '裝置須已連上 WiFi 或已開啟手機熱點）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WifiTransferScreen(
          libraryRepository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          checkNetworkAvailability: checkNetworkAvailability,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證伺服器啟動；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }

    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final url = ipTextWidget.data!;

    final response = await http.get(Uri.parse(url));
    expect(response.statusCode, 200);
    expect(response.body, contains('elinkBook WiFi 傳書'));
  });

  testWidgets(
      '真機：下載本機路徑來源的書籍，位元組與檔名皆正確（含中文書名，Issue 2 驗收）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'wifi_download_local.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final book = Book(
      id: 'local-book-1',
      title: '真機測試書名',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: now,
      lastReadTime: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WifiTransferScreen(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          checkNetworkAvailability: checkNetworkAvailability,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證下載；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }

    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final listResponse = await http.get(Uri.parse('$baseUrl/api/books'));
    expect(listResponse.statusCode, 200);
    final books = jsonDecode(listResponse.body) as List<dynamic>;
    final entry =
        books.singleWhere((b) => b['id'] == 'local-book-1') as Map<String, dynamic>;
    expect(entry['title'], '真機測試書名');

    final downloadResponse =
        await http.get(Uri.parse('$baseUrl/api/books/local-book-1/download'));
    expect(downloadResponse.statusCode, 200);
    expect(downloadResponse.bodyBytes, await File(samplePath).readAsBytes());
    expect(downloadResponse.headers['content-disposition'],
        contains("filename*=UTF-8''"));
  });

  testWidgets(
      '真機：下載 content:// 來源的書籍，位元組正確且暫存檔下載完成後確實清理'
      '（Issue 2 驗收）', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'wifi_download_content.epub');
    final contentUri = await _createAndAuthorizeContentUri(samplePath);
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final book = Book(
      id: 'content-book-1',
      title: 'content 來源書',
      format: BookFileFormat.epub,
      filePath: contentUri,
      source: BookSource.local,
      createTime: now,
      lastReadTime: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WifiTransferScreen(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          checkNetworkAvailability: checkNetworkAvailability,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證下載；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }
    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final tempDir = await getTemporaryDirectory();
    final pdfTmpDir = Directory('${tempDir.path}/elinkbook_pdf_tmp');
    final before = await pdfTmpDir.exists()
        ? pdfTmpDir.listSync().map((f) => f.path).toSet()
        : <String>{};

    final downloadResponse =
        await http.get(Uri.parse('$baseUrl/api/books/content-book-1/download'));
    expect(downloadResponse.statusCode, 200);
    expect(downloadResponse.bodyBytes, await File(samplePath).readAsBytes());

    // 清理發生在回應串流完全送出「之後」，非同步執行；輪詢等待，最多 5 秒。
    var leftover = <String>{};
    for (var i = 0; i < 25; i++) {
      final after = await pdfTmpDir.exists()
          ? pdfTmpDir.listSync().map((f) => f.path).toSet()
          : <String>{};
      leftover = after.difference(before);
      if (leftover.isEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(leftover, isEmpty,
        reason: '下載完成後，content:// 材質化產生的暫存檔應已被刪除，殘留：$leftover');
  });

  testWidgets('真機：TXT 來源書籍下載時誠實回傳 .epub 副檔名（Issue 2 驗收）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'wifi_download_txt_source.txt');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final book = Book(
      id: 'txt-book-1',
      title: 'TXT 合成書',
      format: BookFileFormat.txt,
      filePath: samplePath,
      source: BookSource.local,
      createTime: now,
      lastReadTime: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WifiTransferScreen(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          checkNetworkAvailability: checkNetworkAvailability,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證下載；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }
    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final downloadResponse =
        await http.get(Uri.parse('$baseUrl/api/books/txt-book-1/download'));
    expect(downloadResponse.statusCode, 200);
    expect(downloadResponse.headers['content-disposition'], contains('.epub'));
    expect(downloadResponse.headers['content-disposition'], isNot(contains('.txt')));
  });

  testWidgets(
      '真機：下載 content:// 來源書籍時中途取消連線，暫存檔仍會被清理'
      '（Issue 2 驗收）', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'wifi_download_cancel.epub');
    // 補大檔案，提高真的能在串流傳輸「中途」（而非傳輸剛完成後）觸發
    // 取消的機率——見上方 _padFileWithZeros() 文件註解。
    await _padFileWithZeros(samplePath, 8);
    final contentUri = await _createAndAuthorizeContentUri(samplePath);
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final book = Book(
      id: 'cancel-book-1',
      title: '中途取消測試書',
      format: BookFileFormat.epub,
      filePath: contentUri,
      source: BookSource.local,
      createTime: now,
      lastReadTime: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WifiTransferScreen(
          libraryRepository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          checkNetworkAvailability: checkNetworkAvailability,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證下載；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }
    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final tempDir = await getTemporaryDirectory();
    final pdfTmpDir = Directory('${tempDir.path}/elinkbook_pdf_tmp');
    final before = await pdfTmpDir.exists()
        ? pdfTmpDir.listSync().map((f) => f.path).toSet()
        : <String>{};

    final client = HttpClient();
    final request = await client
        .getUrl(Uri.parse('$baseUrl/api/books/cancel-book-1/download'));
    final response = await request.close();
    // 只讀取第一個資料區塊就中途放棄，模擬使用者關閉瀏覽器分頁/中斷連線。
    await response.first;
    client.close(force: true);

    var leftover = <String>{};
    for (var i = 0; i < 25; i++) {
      final after = await pdfTmpDir.exists()
          ? pdfTmpDir.listSync().map((f) => f.path).toSet()
          : <String>{};
      leftover = after.difference(before);
      if (leftover.isEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(leftover, isEmpty,
        reason: '中途取消下載後，暫存檔仍應被清理，殘留：$leftover');
  });
}
```

- [x] **Step 2: `flutter analyze` 確認乾淨**

Run: `flutter analyze integration_test/wifi_transfer_screen_test.dart`
Expected: `No issues found!`

- [x] **Step 3: 真機執行（需人類操作：裝置已連上 WiFi 或開啟熱點）**

Run: `flutter test integration_test/wifi_transfer_screen_test.dart -d <device-id>`
Expected: 5 個測試全數通過。若裝置目前未連上 WiFi/熱點，測試會以明確的 `fail()` 訊息中止（而非誤判為程式錯誤），依訊息指示連線後重跑。

- [x] **Step 4: Commit**

```bash
git add app/integration_test/wifi_transfer_screen_test.dart
git commit -m "$(cat <<'EOF'
test(wifi-transfer): 新增 WifiTransferScreen 真機下載驗證

epic-44-wifi-book-transfer Issue 2：新增 4 個真機 integration_test——
本機路徑來源下載（含中文書名／Content-Disposition 驗證）、content://
來源下載＋下載完成後暫存檔確實清理（輪詢 elinkbook_pdf_tmp 目錄）、
TXT 來源書籍誠實回傳 .epub 副檔名、下載中途取消連線後暫存檔仍會被
清理（用 8MB 填充檔案提高真的在串流中途觸發取消的機率）。真實
content:// URI 透過既有 createTestContentUri／takePersistableUriPermission
測試專用方法建立（比照 content_uri_acceptance_test.dart 既有先例）。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: 最終驗證

**Files:** 無新增/修改檔案，純驗證步驟。

- [x] **Step 1: 完整 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 2: 完整 `flutter test`（CLAUDE.md 規定：整張計畫最後一個 Task 才跑一次）**

Run: `flutter test`
Expected: 全數通過（或與 PR #257 合併當下已知、與本次異動無關的既存缺陷數量一致，需在審查報告中列出並比對 base commit 確認非本次異動引入的回歸——比照 Issue 1 審查報告先例）。

- [x] **Step 3: 確認 Task 9 的真機測試已至少執行過一次**

若尚未在真實裝置上跑過 Task 9 的 `integration_test/wifi_transfer_screen_test.dart`，於此時執行：

Run: `flutter test integration_test/wifi_transfer_screen_test.dart -d <device-id>`
Expected: 5 個測試全數通過。

- [x] **Step 4: 更新 `docs/epics/epic-44-wifi-book-transfer/issues.md` 與 `docs/epics.md` 進度**（比照 Issue 1 完成後的既有慣例，由人類或執行者在確認上述驗證皆通過後手動進行，非本計畫自動化步驟的一部分）
