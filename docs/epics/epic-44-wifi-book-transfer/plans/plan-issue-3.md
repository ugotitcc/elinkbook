# Epic 44 Issue 3：上傳功能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 PC 端瀏覽器能在 WiFi 傳書首頁拖放/選擇檔案上傳，手機端依副檔名白名單判斷是否接受、算內容指紋去重、呼叫既有匯入管線寫入圖書庫，並讓格式不支援的檔案不會卡住同一請求內其他檔案的解析。

**Architecture:** `WifiTransferService` 補上最後一個業務方法 `handleUploadedFile()`（純邏輯：指紋比對 → 去重／匯入 → 依結果清理落地檔案），只依賴既有的 `LibraryRepository.findByContentFingerprint()`／`BookImportService.importFiles()`／`ComputeRemoteFingerprint`／`deleteFile` 四個介面，可完全脫離真實 socket 用 `flutter test` 驗證。`WifiTransferHttpServer` 新增一個純函式 `bookFileFormatForFileName()`（依副檔名反查 `fileExtensionFor()` 的既有對應表，不重新維護第二份白名單）與 `POST /api/upload` 路由——路由用 `shelf_multipart` 逐一解析 multipart part，白名單外的格式必須先耗盡該 part 的位元組串流才能繼續解析下一個 part（否則整個上傳請求會卡死），白名單內的格式落地到 App 持久化文件目錄後呼叫 `handleUploadedFile()`。與 Issue 2（下載）不同，上傳整個請求（解析＋落地＋匯入）在 handler 回傳 `Response` 之前就同步完成，因此直接沿用 Issue 1／2 既有的 `withTransferPermit()` 包裝寫法即可，不需要下載路由那種 `_acquirePermit()`/`_releasePermit()` 手動配對。

**Tech Stack:** Flutter/Dart、`shelf_multipart`（Issue 0 已引進的既有依賴，本計畫首次實際使用）、`package:path`（`p.basename()`/`p.extension()`，既有依賴）、`path_provider`（`getApplicationDocumentsDirectory()`，既有依賴）、`dart:io`（`File`/`Directory`）。不新增任何 `pubspec.yaml` 依賴。

**Spec:** `docs/epics/epic-44-wifi-book-transfer/spec.md`（「`wifi_transfer_service.dart`」「HTTP 路由表」「PC 端網頁」章節）與 `docs/epics/epic-44-wifi-book-transfer/issues.md`（Issue 3）。執行者應同時閱讀這兩份文件；Issue 0／1／2 的完成狀態（`findByContentFingerprint`／`WifiTransferService`／`WifiTransferHttpServer`／`WifiTransferScreen`／下載路由）已合併進 `main`（PR #257、#258），本計畫直接建立在其上。

## Global Constraints

- 所有程式碼註解、commit message、文件皆使用正體中文（zh-TW），專業術語可保留英文（CLAUDE.md 全域規則）。
- 所有指令在 `app/` 目錄下執行（`flutter pub get`／`flutter analyze`／`flutter test`）。
- 每個 Task 只跑「這次異動實際觸及」的測試檔；只有本計畫最後一個 Task（Task 6）才跑一次完整 `flutter test`（CLAUDE.md「測試執行範圍」）。
- `handleUploadedFile()` 的公開簽章是 Issue 1 已定案、已合併的介面（`landedPath`／`originalFileName`／`format` 三個具名參數，回傳 `Future<UploadResult>`），本計畫不變更它。
- 上傳落地檔名一律用 `p.basename(originalFileName)` 消毒路徑穿越＋額外過濾作業系統禁用字元（`\ / : * ? " < > |`，`review-plan-issue-3.md` I-3）＋附加唯一前綴（spec.md「HTTP 路由表」M-1），原始檔名只透過 `importFiles()` 的 `displayNames` 參數保留供顯示，不參與實體路徑組裝。
- 格式不在白名單時，必須先 `await part.drain()` 耗盡該 part 的位元組串流才能繼續解析下一個 part（spec.md「HTTP 路由表」M-2）——`shelf_multipart` 底層是單一 TCP 串流依序切出多個 part，跳過未消費的 part 會讓解析器卡死。
- 不新增 `pubspec.yaml` 依賴（`shelf_multipart`／`path`／`path_provider` 皆是既有依賴）。
- 除本計畫列出的檔案外，不修改其他檔案；不「順手」重構、清理或改動未在本 Issue 範圍內的程式碼。
- **已知限制（撰寫本計畫時查證發現，評估後維持 spec.md 原定設計，不擴大範圍修正）**：`handleUploadedFile()` 依 spec.md 定案呼叫 `computeFingerprint(landedPath, format)` 時不傳入 `epubIdentifier`，這與 `BookImportServiceImpl._importSingleFile()` 對 EPUB 額外呼叫原生 `extractMetadata` 取得 `dc:identifier` 並以此為指紋的做法不同——對帶有 `dc:identifier` 的真實 EPUB 檔案（多數合法 EPUB3 檔案皆有），第一次上傳後圖書庫存的 `contentFingerprint` 是這個 identifier，第二次上傳同一檔案時 `handleUploadedFile()` 算出的是檔案內容 SHA-256，兩者對不上，去重會偵測不到。這個落差與既有 `RemoteDownloadJob.hasDuplicate()`（OPDS 遠端下載去重）完全相同，是全專案既有、已審查通過的既定模式，非本 Issue 新增，本計畫不修正它——Task 1／Task 5 的「重複上傳」測試改用 PDF（原生端 `extractMetadata` 對 PDF 不回傳 identifier，兩處指紋計算天然一致）驗證去重邏輯本身正確，不受這個限制影響。
- **（`review-plan-issue-3.md` 審查意見，評估後部分不採納）** M-3（`integration_test/wifi_transfer_screen_test.dart` 每個 `testWidgets` 之間手動 unmount widget）：與 `plan-issue-2.md` Global Constraints 已明確評估並駁回的舊 M-4 是同一個疑慮——`flutter_test`／`integration_test` 測試框架本身在每個 `testWidgets` 開始前就會重置並拆除前一個測試遺留的 widget 樹（`State.dispose()` 隨之執行），本檔案與本專案其餘 `integration_test/` 檔案皆未手動 unmount；其提及的埠號衝突風險本來就已由 `WifiTransferScreen._startServerIfNeeded()` 既有的「固定埠失敗即退回 `port: 0`」機制吸收，不受影響，不重複採納。I-4 建議在 `_landAndProcess()` 呼叫外再包一層 `try-catch`：I-1／I-2 修正後，`_landUpload()` 與 `handleUploadedFile()` 本身皆已保證不再拋出例外，這層外層 `try-catch` 會是永遠進不去的死碼，不採納這一小段（Simplicity First／不為不可能發生的情境加錯誤處理）；I-4 提及的「底層 multipart 串流本身在 part 之間中斷」與「`drain()` 本身失敗」兩個情境是真實會發生、且不受 I-1／I-2 涵蓋的獨立錯誤來源，予以採納（見 Task 3 Step 3）。

---

### Task 1：`WifiTransferService.handleUploadedFile()` 實作

**Files:**
- Modify: `app/test/support/fake_book_import_service.dart`
- Modify: `app/test/wifi_transfer/wifi_transfer_service_test.dart`
- Modify: `app/lib/wifi_transfer/wifi_transfer_service.dart`

**Interfaces:**
- Consumes：`LibraryRepository.findByContentFingerprint(String)`（既有）、`BookImportService.importFiles(List<String>, {List<String?>? displayNames, ...})`（既有）、`ComputeRemoteFingerprint`（既有 typedef）、`WifiTransferService.deleteFile`（既有建構子欄位）。
- Produces：`WifiTransferService.handleUploadedFile()` 由 `throw UnimplementedError()` 改為真正實作，回傳型別維持 `Future<UploadResult>` 不變。

- [ ] **Step 1: 擴充 `FakeBookImportService`，記錄 `importFiles()` 的 `displayNames` 參數**

當前 `ImportCallRecord`／`FakeBookImportService.importFiles()` 沒有記錄呼叫端傳入的 `displayNames`，本 Task 的測試需要驗證 `handleUploadedFile()` 確實把 `originalFileName` 透過 `displayNames` 傳給 `importFiles()`（spec.md 明確要求：「原始檔名只透過 `importFiles()` 的 `displayNames` 參數保留供顯示，不參與實體路徑組裝」）。

Edit `app/test/support/fake_book_import_service.dart`：

```dart
// 舊：
class ImportCallRecord {
  final List<String> uris;
  final BookSource source;
  final String? remoteServerId;
  final Map<String, String>? remoteBookIds;
  final Map<String, String>? remoteDownloadUrls;
  final Map<String, String>? cloudFileIds;

  const ImportCallRecord({
    required this.uris,
    required this.source,
    this.remoteServerId,
    this.remoteBookIds,
    this.remoteDownloadUrls,
    this.cloudFileIds,
  });
}
```

```dart
// 新：
class ImportCallRecord {
  final List<String> uris;
  final List<String?>? displayNames;
  final BookSource source;
  final String? remoteServerId;
  final Map<String, String>? remoteBookIds;
  final Map<String, String>? remoteDownloadUrls;
  final Map<String, String>? cloudFileIds;

  const ImportCallRecord({
    required this.uris,
    this.displayNames,
    required this.source,
    this.remoteServerId,
    this.remoteBookIds,
    this.remoteDownloadUrls,
    this.cloudFileIds,
  });
}
```

```dart
// 舊：
    lastImportCall = ImportCallRecord(
      uris: uris,
      source: source,
      remoteServerId: remoteServerId,
      remoteBookIds: remoteBookIds,
      remoteDownloadUrls: remoteDownloadUrls,
      cloudFileIds: cloudFileIds,
    );
```

```dart
// 新：
    lastImportCall = ImportCallRecord(
      uris: uris,
      displayNames: displayNames,
      source: source,
      remoteServerId: remoteServerId,
      remoteBookIds: remoteBookIds,
      remoteDownloadUrls: remoteDownloadUrls,
      cloudFileIds: cloudFileIds,
    );
```

（純新增可為 `null` 的欄位，既有呼叫端／既有測試斷言皆不受影響。）

- [ ] **Step 2: 寫失敗測試**

Edit `app/test/wifi_transfer/wifi_transfer_service_test.dart`。先在檔案頂部新增 import（於既有 import 區塊）：

```dart
// 舊：
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_service.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_fingerprint_computer.dart';
```

```dart
// 新：
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_service.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_fingerprint_computer.dart';
```

把既有的 `_bookWith()` helper 擴充一個可選的 `contentFingerprint` 參數（供「重複偵測」測試建立一本已存在、指紋已知的書）：

```dart
// 舊：
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
```

```dart
// 新：
Book _bookWith({
  required String id,
  required String filePath,
  bool isDownloaded = true,
  BookFileFormat format = BookFileFormat.epub,
  String title = '書名',
  String? contentFingerprint,
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return Book(
    id: id,
    title: title,
    format: format,
    filePath: filePath,
    source: BookSource.local,
    isDownloaded: isDownloaded,
    contentFingerprint: contentFingerprint,
    createTime: now,
    lastReadTime: now,
  );
}
```

把既有的「`handleUploadedFile` 尚未實作」測試整條**取代**，並在其後新增 `group('handleUploadedFile', ...)`：

```dart
// 舊：
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
```

```dart
// 新：
  group('handleUploadedFile', () {
    test('沒有重複、匯入成功：回傳 imported，落地檔案不會被刪除，displayNames '
        '正確帶入原始檔名', () async {
      final fingerprintComputer = FakeFingerprintComputer();
      final importService = FakeBookImportService()
        ..pendingCompleter = (Completer<ImportResult>()
          ..complete(ImportResult(
            importedBooks: [_bookWith(id: 'new-1', filePath: '/tmp/landed.epub')],
          )));
      final deleteCalls = <String>[];
      final service = WifiTransferService(
        libraryRepository: FakeLibraryRepository(),
        importService: importService,
        computeFingerprint: fingerprintComputer.call,
        materializeContentUri: (uri) async => null,
        deleteFile: (path) async => deleteCalls.add(path),
      );

      final result = await service.handleUploadedFile(
        landedPath: '/tmp/landed.epub',
        originalFileName: '我的書.epub',
        format: BookFileFormat.epub,
      );

      expect(result.outcome, UploadOutcome.imported);
      expect(result.originalFileName, '我的書.epub');
      expect(deleteCalls, isEmpty);
      expect(importService.lastImportCall!.uris, ['/tmp/landed.epub']);
      expect(importService.lastImportCall!.displayNames, ['我的書.epub']);
    });

    test('內容指紋命中圖書庫既有書籍：回傳 duplicateSkipped，刪除落地檔案，'
        '且不呼叫 importFiles', () async {
      final fingerprintComputer = FakeFingerprintComputer()
        ..nextFingerprint = 'shared-fingerprint';
      final existing = _bookWith(
        id: 'existing-1',
        filePath: '/tmp/existing.epub',
        contentFingerprint: 'shared-fingerprint',
      );
      final importService = FakeBookImportService();
      final deleteCalls = <String>[];
      final service = WifiTransferService(
        libraryRepository: FakeLibraryRepository(initialBooks: [existing]),
        importService: importService,
        computeFingerprint: fingerprintComputer.call,
        materializeContentUri: (uri) async => null,
        deleteFile: (path) async => deleteCalls.add(path),
      );

      final result = await service.handleUploadedFile(
        landedPath: '/tmp/landed.epub',
        originalFileName: '重複的書.epub',
        format: BookFileFormat.epub,
      );

      expect(result.outcome, UploadOutcome.duplicateSkipped);
      expect(deleteCalls, ['/tmp/landed.epub']);
      expect(importService.lastImportCall, isNull);
    });

    test('importFiles 回傳空清單（模擬損毀/空內容檔案）：回傳 failed，刪除落地檔案',
        () async {
      final fingerprintComputer = FakeFingerprintComputer();
      final deleteCalls = <String>[];
      final service = WifiTransferService(
        libraryRepository: FakeLibraryRepository(),
        importService: FakeBookImportService(), // 預設回傳空清單
        computeFingerprint: fingerprintComputer.call,
        materializeContentUri: (uri) async => null,
        deleteFile: (path) async => deleteCalls.add(path),
      );

      final result = await service.handleUploadedFile(
        landedPath: '/tmp/landed.pdf',
        originalFileName: '損毀的書.pdf',
        format: BookFileFormat.pdf,
      );

      expect(result.outcome, UploadOutcome.failed);
      expect(deleteCalls, ['/tmp/landed.pdf']);
    });

    test('importFiles 拋出例外：回傳 failed，刪除落地檔案，例外不會冒出中斷上傳請求',
        () async {
      final fingerprintComputer = FakeFingerprintComputer();
      final importService = FakeBookImportService()
        ..pendingCompleter = (Completer<ImportResult>()
          ..completeError(StateError('模擬匯入失敗')));
      final deleteCalls = <String>[];
      final service = WifiTransferService(
        libraryRepository: FakeLibraryRepository(),
        importService: importService,
        computeFingerprint: fingerprintComputer.call,
        materializeContentUri: (uri) async => null,
        deleteFile: (path) async => deleteCalls.add(path),
      );

      final result = await service.handleUploadedFile(
        landedPath: '/tmp/landed.epub',
        originalFileName: '例外的書.epub',
        format: BookFileFormat.epub,
      );

      expect(result.outcome, UploadOutcome.failed);
      expect(deleteCalls, ['/tmp/landed.epub']);
    });

    test('computeFingerprint 本身拋出例外：回傳 failed，刪除落地檔案', () async {
      final deleteCalls = <String>[];
      final service = WifiTransferService(
        libraryRepository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        computeFingerprint: (path, format) async =>
            throw StateError('模擬指紋計算失敗'),
        materializeContentUri: (uri) async => null,
        deleteFile: (path) async => deleteCalls.add(path),
      );

      final result = await service.handleUploadedFile(
        landedPath: '/tmp/landed.epub',
        originalFileName: '無法計算指紋的書.epub',
        format: BookFileFormat.epub,
      );

      expect(result.outcome, UploadOutcome.failed);
      expect(deleteCalls, ['/tmp/landed.epub']);
    });

    test(
        'importFiles 拋出例外，且清理落地檔案時 deleteFile 本身也拋出例外：'
        '仍回傳 failed，例外不會冒出（`review-plan-issue-3.md` I-1 回歸測試）',
        () async {
      final fingerprintComputer = FakeFingerprintComputer();
      final importService = FakeBookImportService()
        ..pendingCompleter = (Completer<ImportResult>()
          ..completeError(StateError('模擬匯入失敗')));
      final service = WifiTransferService(
        libraryRepository: FakeLibraryRepository(),
        importService: importService,
        computeFingerprint: fingerprintComputer.call,
        materializeContentUri: (uri) async => null,
        deleteFile: (path) async => throw FileSystemException('模擬清理失敗'),
      );

      final result = await service.handleUploadedFile(
        landedPath: '/tmp/landed.epub',
        originalFileName: '清理也失敗的書.epub',
        format: BookFileFormat.epub,
      );

      expect(result.outcome, UploadOutcome.failed);
    });
  });
```

- [ ] **Step 3: 執行測試，確認失敗**

Run: `flutter test test/wifi_transfer/wifi_transfer_service_test.dart`
Expected: FAIL——`handleUploadedFile` 群組的 6 個測試因 `UnimplementedError` 被拋出而失敗。

- [ ] **Step 4: 實作 `handleUploadedFile()`**

Edit `app/lib/wifi_transfer/wifi_transfer_service.dart`：

```dart
// 舊：
  /// Issue 3 實作：對落地檔案算內容指紋 → 查重複 → 匯入或略過，詳見
  /// spec.md「`wifi_transfer_service.dart`」。
  Future<UploadResult> handleUploadedFile({
    required String landedPath,
    required String originalFileName,
    required BookFileFormat format,
  }) async {
    throw UnimplementedError('Issue 3 實作：上傳落地/去重/匯入邏輯');
  }
```

```dart
// 新：
  /// 對應「上傳位元組落地路徑」＋「重複匯入偵測」決策（spec.md
  /// 「`wifi_transfer_service.dart`」）：呼叫端（`WifiTransferHttpServer`）
  /// 已把上傳位元組寫入持久化目錄的 [landedPath]（副檔名已通過白名單檢查，
  /// 不通過的呼叫端直接回傳 `unsupportedFormat`、不呼叫本方法；[landedPath]
  /// 的檔名本身已由呼叫端消毒＋附加唯一前綴，[originalFileName] 只用於
  /// 顯示，不參與實體路徑組裝）。內部依序：算指紋 → 查
  /// `findByContentFingerprint` → 命中則刪除 [landedPath] 並回傳
  /// `duplicateSkipped`；沒命中才呼叫
  /// `importService.importFiles([landedPath], displayNames: [originalFileName])`。
  /// 呼叫後檢查 `result.importedBooks.isEmpty`——是則刪除 [landedPath]、
  /// 回傳 `failed`；任何未預期例外（`catch`，含指紋計算本身失敗）同樣刪除
  /// [landedPath] 並回傳 `failed`，不讓例外冒出中斷整個上傳請求。
  ///
  /// **已知限制**：本方法呼叫 `computeFingerprint(landedPath, format)` 時
  /// 不傳入 `epubIdentifier`（`ComputeRemoteFingerprint` typedef 本身也
  /// 沒有這個參數位置），對帶有 `dc:identifier` 的 EPUB 檔案，這裡算出的
  /// 指紋（內容 SHA-256）與 `BookImportServiceImpl._importSingleFile()`
  /// 正式匯入時實際存入 `Book.contentFingerprint` 的值（`dc:identifier`）
  /// 不同，重複上傳同一份這樣的 EPUB 可能偵測不到重複——與既有
  /// `RemoteDownloadJob.hasDuplicate()`（OPDS 遠端下載去重）相同的既定
  /// 限制，非本方法特有，詳見本 Issue plan 的 Global Constraints。
  Future<UploadResult> handleUploadedFile({
    required String landedPath,
    required String originalFileName,
    required BookFileFormat format,
  }) async {
    // 【`/receiving-code-review` 審查修正，review-plan-issue-3.md I-1】
    // deleteFile 是使用者注入的清理動作（生產環境為 File.delete()），本身
    // 可能拋出例外（檔案已被其他流程刪除/權限問題）。下方每個清理呼叫都
    // 已經身處某個決定「回傳什麼結果」的分支，若 deleteFile 在這裡失敗
    // 又沒有內層防護，例外會直接冒出、逃出整個方法，違反「不可讓例外冒出
    // 中斷整個上傳請求」的契約——比照 Issue 2 對 deleteFile 呼叫的既有
    // 靜默吞錯慣例。
    Future<void> safeDelete(String path) async {
      try {
        await deleteFile(path);
      } catch (_) {}
    }

    try {
      final fingerprint = await computeFingerprint(landedPath, format);
      final duplicate =
          await libraryRepository.findByContentFingerprint(fingerprint);
      if (duplicate != null) {
        await safeDelete(landedPath);
        return UploadResult(
          originalFileName: originalFileName,
          outcome: UploadOutcome.duplicateSkipped,
        );
      }
      final result = await importService.importFiles(
        [landedPath],
        displayNames: [originalFileName],
      );
      if (result.importedBooks.isEmpty) {
        await safeDelete(landedPath);
        return UploadResult(
          originalFileName: originalFileName,
          outcome: UploadOutcome.failed,
        );
      }
      return UploadResult(
        originalFileName: originalFileName,
        outcome: UploadOutcome.imported,
      );
    } catch (_) {
      await safeDelete(landedPath);
      return UploadResult(
        originalFileName: originalFileName,
        outcome: UploadOutcome.failed,
      );
    }
  }
```

- [ ] **Step 5: 執行測試，確認通過**

Run: `flutter test test/wifi_transfer/wifi_transfer_service_test.dart`
Expected: PASS，全數測試通過（含 Issue 2 遺留的 `listDownloadableBooks`／`resolveDownloadSource` 群組，共 20 個測試）。

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_service.dart test/wifi_transfer/wifi_transfer_service_test.dart test/support/fake_book_import_service.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_service.dart app/test/wifi_transfer/wifi_transfer_service_test.dart app/test/support/fake_book_import_service.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 實作 WifiTransferService.handleUploadedFile()

epic-44-wifi-book-transfer Issue 3：算內容指紋 → 命中既有書籍則刪除落地
檔案並回傳 duplicateSkipped；沒命中呼叫 importFiles([landedPath],
displayNames: [originalFileName])；importedBooks 為空（損毀/空內容）或
任何未預期例外（含指紋計算本身失敗）皆刪除落地檔案並回傳 failed，不讓
例外冒出中斷上傳請求。清理呼叫一律經 safeDelete() 包裝，deleteFile()
本身拋出例外時同樣靜默吞掉（review-plan-issue-3.md I-1：deleteFile 是
使用者注入的清理動作，本身可能失敗，若無內層防護會讓例外冒出逃出整個
方法）。FakeBookImportService 新增 displayNames 記錄，供測試驗證原始
檔名確實透過 displayNames 傳遞、不參與實體路徑組裝。測試覆蓋 6 種情境
（成功匯入、重複略過、匯入回傳空清單、匯入拋例外、指紋計算拋例外、
匯入與清理雙雙失敗的 I-1 回歸測試）。

已知限制（不在本次修正範圍，詳見 plan-issue-3.md Global Constraints）：
對帶 dc:identifier 的 EPUB，去重指紋與正式匯入指紋不同，可能偵測不到
重複，與既有 RemoteDownloadJob.hasDuplicate() 相同限制。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2：`bookFileFormatForFileName()` 純函式——上傳白名單判斷

**Files:**
- Modify: `app/lib/wifi_transfer/wifi_transfer_http_server.dart`
- Modify: `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`

**Interfaces:**
- Consumes：`fileExtensionFor(BookFileFormat)`（既有，`app/lib/remote/opds_client.dart`）。
- Produces：頂層函式 `BookFileFormat? bookFileFormatForFileName(String fileName)`，供 Task 3 的上傳路由判斷白名單使用。

- [ ] **Step 1: 寫失敗測試**

Edit `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`，在檔案結尾（`buildContentDispositionHeader` 群組的 `});` 之後、`}` 之前）新增：

```dart

  group('bookFileFormatForFileName', () {
    test('支援的副檔名對應到正確的 BookFileFormat，且不分大小寫', () {
      expect(bookFileFormatForFileName('book.epub'), BookFileFormat.epub);
      expect(bookFileFormatForFileName('book.EPUB'), BookFileFormat.epub);
      expect(bookFileFormatForFileName('book.pdf'), BookFileFormat.pdf);
      expect(bookFileFormatForFileName('book.txt'), BookFileFormat.txt);
      expect(bookFileFormatForFileName('book.azw3'), BookFileFormat.azw3);
      expect(bookFileFormatForFileName('book.cbz'), BookFileFormat.cbz);
      expect(bookFileFormatForFileName('book.md'), BookFileFormat.md);
    });

    test('不在白名單內的副檔名回傳 null', () {
      expect(bookFileFormatForFileName('book.docx'), isNull);
      expect(bookFileFormatForFileName('book.zip'), isNull);
    });

    test('無副檔名或空字串回傳 null', () {
      expect(bookFileFormatForFileName('book'), isNull);
      expect(bookFileFormatForFileName(''), isNull);
    });
  });
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: FAIL，編譯錯誤（`bookFileFormatForFileName` 尚未定義）。

- [ ] **Step 3: 實作 `bookFileFormatForFileName()`**

Edit `app/lib/wifi_transfer/wifi_transfer_http_server.dart`：

```dart
// 舊：
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
// 新：
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../library/models/library_enums.dart';
import '../remote/opds_client.dart' show fileExtensionFor;
import 'wifi_transfer_service.dart';
```

在檔案結尾（`buildContentDispositionHeader()`／`_asciiFallbackFilename()` 之後）新增：

```dart

/// 依檔名副檔名反查對應的 [BookFileFormat]（epic-44-wifi-book-transfer
/// spec.md「HTTP 路由表」上傳白名單判斷）：反查既有 [fileExtensionFor] 的
/// 對應表，不重新維護第二份白名單常數。副檔名比對不分大小寫；無副檔名或
/// 不在白名單內一律回傳 `null`（呼叫端視為 [UploadOutcome.unsupportedFormat]）。
BookFileFormat? bookFileFormatForFileName(String fileName) {
  final extension = p.extension(fileName);
  if (extension.isEmpty) return null;
  final normalized = extension.substring(1).toLowerCase();
  for (final format in BookFileFormat.values) {
    if (fileExtensionFor(format) == normalized) return format;
  }
  return null;
}
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: PASS，`bookFileFormatForFileName` 群組的 3 個測試（連同其餘既有測試）全數通過。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_http_server.dart test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_http_server.dart app/test/wifi_transfer/wifi_transfer_http_server_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 新增 bookFileFormatForFileName() 純函式

epic-44-wifi-book-transfer Issue 3：依檔名副檔名反查對應的
BookFileFormat，反查既有 fileExtensionFor() 對應表而非重新維護第二份
白名單常數，比對不分大小寫。供下一個 commit 的 POST /api/upload 路由
判斷格式白名單使用。純 Dart 單元測試涵蓋支援/不支援/無副檔名三種情境。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3：`POST /api/upload` 路由實作

**Files:**
- Modify: `app/lib/wifi_transfer/wifi_transfer_http_server.dart`
- Modify: `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`

**Interfaces:**
- Consumes：`WifiTransferService.handleUploadedFile()`（Task 1）、`bookFileFormatForFileName()`（Task 2）、`withTransferPermit()`（Issue 1 既有）。
- Produces：`POST /api/upload` 路由——`shelf_multipart` 逐一解析 part；格式不在白名單先 `drain()` 該 part 再記錄 `unsupportedFormat`；在白名單則落地到持久化目錄後呼叫 `handleUploadedFile()`；回應 JSON 陣列 `[{originalFileName, outcome}]`。整個處理過程包在既有 `withTransferPermit()` 內，不需要 Issue 2 那種手動配對許可的寫法（回傳 `Response` 前所有檔案早已落地/匯入完畢）。

- [ ] **Step 1: 寫失敗測試**

Edit `app/test/wifi_transfer/wifi_transfer_http_server_test.dart`。先在檔案頂部新增 import：

```dart
// 舊：
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_http_server.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_service.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_fingerprint_computer.dart';
```

```dart
// 新：
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_http_server.dart';
import 'package:elinkbook/wifi_transfer/wifi_transfer_service.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_path_provider_platform.dart';
```

**（`/receiving-code-review` 審查修正，`review-plan-issue-3.md` C-1）** `_landUpload()`（Task 3 Step 3）呼叫 `path_provider` 的 `getApplicationDocumentsDirectory()`，這是透過 Method Channel 呼叫原生平台的外掛方法；純 Dart `flutter test` 環境（無真機/無模擬器）沒有任何原生實作可回應，直接呼叫會拋出 `MissingPluginException`。本專案既有慣例（`test/library/book_import_service_test.dart` 等 12 個測試檔案）是在需要用到 `path_provider` 的測試範圍內，把 `PathProviderPlatform.instance` 換成 `FakePathProviderPlatform`（`test/support/fake_path_provider_platform.dart`，Issue 3 前就已存在，回傳呼叫端指定的真實可寫入目錄），本 Task 沿用同一個慣例。

在 `_realGetBytes()` 定義之後新增一個真實 multipart 上傳的 helper（沿用既有 `_Resp` 型別）：

```dart

Future<_Resp> _realMultipartUpload(
  String url,
  List<({String filename, List<int> bytes})> files,
) async {
  final request = http.MultipartRequest('POST', Uri.parse(url));
  for (final file in files) {
    request.files.add(
      http.MultipartFile.fromBytes('files', file.bytes, filename: file.filename),
    );
  }
  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);
  final headers = <String, String>{};
  response.headers.forEach((key, value) => headers[key] = value);
  return _Resp(response.statusCode, headers, response.body);
}
```

把既有的 `POST /api/upload 回傳 501（留給 Issue 3 實作）` 測試整條**取代**（放在原本同一個位置，`WifiTransferHttpServer 路由` 群組內）：

```dart
// 舊：
    test('POST /api/upload 回傳 501（留給 Issue 3 實作）', () async {
      final response =
          await _realPost('http://127.0.0.1:${httpServer.port}/api/upload');
      expect(response.statusCode, 501);
    });
```

```dart
// 新：
    test('POST /api/upload：非 multipart 請求回傳 400', () async {
      final response =
          await _realPost('http://127.0.0.1:${httpServer.port}/api/upload');
      expect(response.statusCode, 400);
    });
```

在同一個測試檔的 `bookFileFormatForFileName` 群組**之後**（`}` 結尾之前）新增一個新的 `group`：

```dart

  group('POST /api/upload', () {
    // 【`/receiving-code-review` 審查修正，review-plan-issue-3.md C-1】
    // 本群組所有測試皆透過真實 HTTP 請求觸發 _landUpload()，其內部呼叫
    // path_provider 的 getApplicationDocumentsDirectory()——純 Dart
    // `flutter test` 環境沒有原生實作可回應，需替換 PathProviderPlatform
    // 為 FakePathProviderPlatform（比照 book_import_service_test.dart 等
    // 既有慣例），否則 100% 拋出 MissingPluginException。
    late Directory tempDocsDir;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      originalPathProvider = PathProviderPlatform.instance;
      tempDocsDir = Directory.systemTemp.createTempSync('wifi_upload_test_');
      PathProviderPlatform.instance = FakePathProviderPlatform(tempDocsDir.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      if (tempDocsDir.existsSync()) {
        try {
          tempDocsDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('上傳一個支援格式的檔案：回傳 200、outcome 為 imported，落地檔案內容正確、'
        'displayNames 正確帶入原始檔名', () async {
      final importedBook = Book(
        id: 'x',
        title: 'x',
        format: BookFileFormat.epub,
        filePath: 'x',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(0),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final importService = FakeBookImportService()
        ..pendingCompleter = (Completer<ImportResult>()
          ..complete(ImportResult(importedBooks: [importedBook])));
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(),
          importService: importService,
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [(filename: '我的書.epub', bytes: [1, 2, 3, 4, 5])],
      );

      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      expect(results, hasLength(1));
      expect(results.single['originalFileName'], '我的書.epub');
      expect(results.single['outcome'], 'imported');
      final landedPath = importService.lastImportCall!.uris.single;
      addTearDown(() async {
        final f = File(landedPath);
        if (await f.exists()) await f.delete();
      });
      expect(await File(landedPath).readAsBytes(), [1, 2, 3, 4, 5]);
      expect(landedPath.endsWith('我的書.epub'), isTrue);
      expect(importService.lastImportCall!.displayNames, ['我的書.epub']);
    });

    test('上傳不支援格式的檔案：回傳 200、outcome 為 unsupportedFormat，未呼叫 '
        'importFiles', () async {
      final importService = FakeBookImportService();
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(),
          importService: importService,
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [(filename: '文件.docx', bytes: [1, 2, 3])],
      );

      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      expect(results.single['originalFileName'], '文件.docx');
      expect(results.single['outcome'], 'unsupportedFormat');
      expect(importService.lastImportCall, isNull);
    });

    test(
        '同一請求內第一個檔案格式不支援、第二個支援：不支援的那個不會卡住'
        '後續 part 的解析（M-2 驗證），第二個檔案正常匯入', () async {
      final importedBook = Book(
        id: 'x',
        title: 'x',
        format: BookFileFormat.pdf,
        filePath: 'x',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(0),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final importService = FakeBookImportService()
        ..pendingCompleter = (Completer<ImportResult>()
          ..complete(ImportResult(importedBooks: [importedBook])));
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(),
          importService: importService,
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [
          (filename: '不支援.docx', bytes: List.filled(1024, 7)),
          (filename: '支援.pdf', bytes: [9, 9, 9]),
        ],
      );

      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      expect(results, hasLength(2));
      expect(results[0]['outcome'], 'unsupportedFormat');
      expect(results[1]['outcome'], 'imported');
      addTearDown(() async {
        final landedPath = importService.lastImportCall!.uris.single;
        final f = File(landedPath);
        if (await f.exists()) await f.delete();
      });
    });

    test('內容指紋命中既有書籍：回傳 duplicateSkipped，落地暫存檔已被刪除',
        () async {
      final fingerprintComputer = FakeFingerprintComputer()
        ..nextFingerprint = 'dup-fp';
      final existing = Book(
        id: 'existing',
        title: 'existing',
        format: BookFileFormat.epub,
        filePath: '/tmp/existing.epub',
        source: BookSource.local,
        contentFingerprint: 'dup-fp',
        createTime: DateTime.fromMillisecondsSinceEpoch(0),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final deleteCalls = <String>[];
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(initialBooks: [existing]),
          importService: FakeBookImportService(),
          computeFingerprint: fingerprintComputer.call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async => deleteCalls.add(path),
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [(filename: '重複的書.epub', bytes: [1, 2, 3])],
      );

      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      expect(results.single['outcome'], 'duplicateSkipped');
      expect(deleteCalls, hasLength(1));
      expect(deleteCalls.single.endsWith('重複的書.epub'), isTrue);
    });

    test('沒有任何檔案的合法 multipart 請求：回傳 200 與空陣列', () async {
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [],
      );

      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), isEmpty);
    });

    test(
        '檔名含作業系統禁用字元（例如冒號）：仍能成功落地並匯入，不因'
        '非法檔名字元拋出 FileSystemException（`review-plan-issue-3.md` '
        'I-3 回歸測試）', () async {
      final importedBook = Book(
        id: 'x',
        title: 'x',
        format: BookFileFormat.epub,
        filePath: 'x',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(0),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final importService = FakeBookImportService()
        ..pendingCompleter = (Completer<ImportResult>()
          ..complete(ImportResult(importedBooks: [importedBook])));
      final wifiServer = WifiTransferHttpServer(
        service: WifiTransferService(
          libraryRepository: FakeLibraryRepository(),
          importService: importService,
          computeFingerprint: FakeFingerprintComputer().call,
          materializeContentUri: (uri) async => null,
          deleteFile: (path) async {},
        ),
      );
      final server = await wifiServer.start(ipAddress: '127.0.0.1', port: 0);
      addTearDown(() => wifiServer.stop(server));

      final response = await _realMultipartUpload(
        'http://127.0.0.1:${server.port}/api/upload',
        [(filename: '深入理解電腦系統：工程師觀點.epub', bytes: [1, 2, 3])],
      );

      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      expect(results.single['outcome'], 'imported');
      addTearDown(() async {
        final landedPath = importService.lastImportCall!.uris.single;
        final f = File(landedPath);
        if (await f.exists()) await f.delete();
      });
    });
  });
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: FAIL——上傳相關測試回應狀態碼為 501，不是 200/400。

- [ ] **Step 3: 實作 `POST /api/upload` 路由**

Edit `app/lib/wifi_transfer/wifi_transfer_http_server.dart`：

```dart
// 舊：
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../library/models/library_enums.dart';
import '../remote/opds_client.dart' show fileExtensionFor;
import 'wifi_transfer_service.dart';
```

```dart
// 新：
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_multipart/shelf_multipart.dart';

import '../library/models/library_enums.dart';
import '../remote/opds_client.dart' show fileExtensionFor;
import 'wifi_transfer_service.dart';
```

```dart
// 舊：
    if (request.method == 'POST' && path == 'api/upload') {
      // Issue 3 補上：shelf_multipart 解析＋service.handleUploadedFile()。
      return shelf.Response(501, body: 'Not Implemented');
    }
```

```dart
// 新：
    if (request.method == 'POST' && path == 'api/upload') {
      return withTransferPermit(() => _handleUpload(request));
    }
```

在 `_handleDownload()` 方法**之後**（`WifiTransferHttpServer` 類別結尾之前）新增：

```dart

  /// 處理 `POST /api/upload`（epic-44-wifi-book-transfer spec.md「HTTP
  /// 路由表」）。與 [_handleDownload] 不同，這裡整個請求（解析／落地／
  /// 呼叫 [WifiTransferService.handleUploadedFile]）都在回傳 `Response`
  /// 之前同步完成，因此直接沿用 [withTransferPermit] 即可（見該方法文件
  /// 註解），不需要 [_acquirePermit]／[_releasePermit] 手動配對。
  Future<shelf.Response> _handleUpload(shelf.Request request) async {
    final form = request.formData();
    if (form == null) {
      return shelf.Response(
        400,
        body: jsonEncode({'error': '不是合法的 multipart/form-data 請求'}),
        // 【`/receiving-code-review` 審查修正，review-plan-issue-3.md M-2】
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-cache',
        },
      );
    }
    final results = <Map<String, String>>[];
    // 【`/receiving-code-review` 審查修正，review-plan-issue-3.md I-4】
    // 這裡攔截的是 shelf_multipart 解析器本身在 part 與 part 之間中斷（例如
    // 客戶端在兩個檔案之間斷線，錯誤發生在 await for 還沒產生下一個 data
    // 物件之前）——[_landUpload]／[WifiTransferService.handleUploadedFile]
    // 各自已完整吞下自己範圍內的例外（見兩者文件註解），不會讓例外冒到
    // 這裡；這層 try-catch 涵蓋的是它們之外、屬於解析器本身的例外，不是
    // 兩者的重複防護。
    try {
      await for (final data in form.formData) {
        final filename = data.filename;
        final format =
            filename == null ? null : bookFileFormatForFileName(filename);
        if (filename == null || format == null) {
          // 【spec.md「HTTP 路由表」M-2】格式不在白名單時，必須先耗盡這個
          // part 的位元組串流，shelf_multipart 底層（單一 TCP 串流依序切
          // 出多個 part）才能定位下一個 part 的邊界繼續解析，否則整個上傳
          // 請求會卡死。
          try {
            await data.part.drain<void>();
          } catch (_) {
            // 【review-plan-issue-3.md I-4】耗盡動作本身失敗（例如客戶端
            // 在此時斷線）：忽略，讓迴圈能繼續處理下一個 part（若解析器
            // 仍能定位邊界的話），不因單一 part 的清理失敗中斷整批上傳。
          }
          results.add({
            'originalFileName': filename ?? '(未知檔名)',
            'outcome': UploadOutcome.unsupportedFormat.name,
          });
          continue;
        }
        final outcome = await _landAndProcess(data.part, filename, format);
        results.add({'originalFileName': filename, 'outcome': outcome.name});
      }
    } catch (_) {
      if (results.isEmpty) {
        return shelf.Response(
          400,
          body: jsonEncode({'error': '上傳串流解析中斷或格式錯誤'}),
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'cache-control': 'no-cache',
          },
        );
      }
    }
    return shelf.Response.ok(
      jsonEncode(results),
      headers: {
        'content-type': 'application/json; charset=utf-8',
        // 【review-plan-issue-3.md M-2】比照 GET /api/books 既有理由。
        'cache-control': 'no-cache',
      },
    );
  }

  Future<UploadOutcome> _landAndProcess(
    Stream<List<int>> partStream,
    String originalFileName,
    BookFileFormat format,
  ) async {
    final landedPath = await _landUpload(partStream, originalFileName);
    if (landedPath == null) return UploadOutcome.failed;
    final result = await service.handleUploadedFile(
      landedPath: landedPath,
      originalFileName: originalFileName,
      format: format,
    );
    return result.outcome;
  }

  /// 把上傳位元組串流落地到 App 持久化文件目錄的 `wifi_transfer_uploads/`
  /// 子目錄（spec.md「HTTP 路由表」M-1）：檔名一律先用 [p.basename] 消毒
  /// （避免 `originalFileName` 夾帶 `../` 造成路徑穿越）＋過濾作業系統
  /// 禁用字元（`review-plan-issue-3.md` I-3：`p.basename()` 不會過濾
  /// Windows／部分 Android 外部儲存的禁用字元，書名帶副標題冒號極為常見）
  /// 再附加微秒時間戳前綴（避免同名檔案互相覆蓋）。串流落地失敗（例如
  /// 磁碟空間不足、連線中斷）時關閉並清除可能已部分寫入的殘檔並回傳
  /// `null`，呼叫端視為 [UploadOutcome.failed]，不中斷同一請求內其他檔案
  /// 的解析。
  Future<String?> _landUpload(
    Stream<List<int>> partStream,
    String originalFileName,
  ) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final uploadsDir = Directory(p.join(docsDir.path, 'wifi_transfer_uploads'));
    if (!await uploadsDir.exists()) await uploadsDir.create(recursive: true);
    // 【`/receiving-code-review` 審查修正，review-plan-issue-3.md I-3】
    final sanitized =
        p.basename(originalFileName).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final safeName = '${DateTime.now().microsecondsSinceEpoch}_$sanitized';
    final landedPath = p.join(uploadsDir.path, safeName);
    // 【`/receiving-code-review` 審查修正，review-plan-issue-3.md I-2】
    // sink 宣告於 try 外，讓 catch 區塊能在刪除殘檔前先關閉它——若不關閉
    // 就嘗試刪除，仍持有寫入控制代碼的檔案在部分作業系統/檔案系統上會
    // 刪除失敗，讓已寫入一半的殘檔永久殘留。
    IOSink? sink;
    try {
      sink = File(landedPath).openWrite();
      await sink.addStream(partStream);
      await sink.flush();
      await sink.close();
      sink = null;
      return landedPath;
    } catch (_) {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      final partial = File(landedPath);
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
      return null;
    }
  }
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: PASS，全數測試通過（含 Task 1～2 累積的所有測試）。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/wifi_transfer/wifi_transfer_http_server.dart test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/wifi_transfer/wifi_transfer_http_server.dart app/test/wifi_transfer/wifi_transfer_http_server_test.dart
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): 實作 POST /api/upload 路由

epic-44-wifi-book-transfer Issue 3：request.formData() 逐一解析
multipart part；格式不在白名單（bookFileFormatForFileName() 反查）先
await part.drain() 耗盡串流才記錄 unsupportedFormat（M-2：避免卡死後續
part 的解析）；在白名單則以消毒過的檔名（p.basename() 防路徑穿越＋過濾
作業系統禁用字元）附加微秒時間戳前綴落地到 wifi_transfer_uploads/ 目錄，
呼叫 service.handleUploadedFile()。整個處理過程沿用既有
withTransferPermit() 包裝（不需要下載路由那種手動配對許可的寫法，見
_handleUpload 文件註解）。新增 _handleUpload()/_landAndProcess()/
_landUpload()。測試涵蓋成功匯入、不支援格式、同請求內混合支援/不支援
格式（M-2 直接驗證）、重複匯入、空 multipart 請求、非 multipart 請求回
400，以及檔名含禁用字元仍能成功落地（I-3 回歸測試）。單元測試改用
FakePathProviderPlatform 替身 path_provider（C-1：純 Dart flutter test
環境無原生實作可回應 getApplicationDocumentsDirectory()）。

一併修正 review-plan-issue-3.md：
- I-2：_landUpload() 的 IOSink 宣告於 try 外，例外路徑先關閉 sink 才
  嘗試刪除殘檔，避免控制代碼未釋放導致刪除失敗、殘檔永久殘留。
- I-3：落地檔名額外過濾 \ / : * ? " < > | 等作業系統禁用字元（書名含
  副標題冒號極為常見，未過濾會讓 File.openWrite() 拋出例外）。
- I-4（部分採納，理由見 plan-issue-3.md Global Constraints）：
  _handleUpload() 的 await for 迴圈整體包 try-catch，攔截 shelf_multipart
  解析器本身在 part 之間中斷的例外；drain() 本身失敗也個別吞掉，讓迴圈
  能繼續處理後續 part。未採納在 _landAndProcess() 呼叫外再包一層
  try-catch——I-2 修正後該呼叫路徑已不會拋出例外，屬不可能發生的情境。
- M-2：非 multipart 請求的 400 回應補上 content-type；成功回應補上
  cache-control: no-cache（比照既有 GET /api/books 慣例）。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4：`assets/wifi_transfer/index.html` 上傳區塊 JS

**Files:**
- Modify: `app/assets/wifi_transfer/index.html`

**Interfaces:**
- Consumes：`POST /api/upload`（Task 3）。
- Produces：頁面提供拖放區＋檔案選擇器，選定/拖放檔案後以 `XMLHttpRequest` 上傳並顯示進度，完成後依伺服器回應的 JSON 陣列逐檔顯示結果。無自動化測試（純 HTML/JS，不在 `flutter test`／`flutter analyze` 範圍內；背後路由已由 Task 3 覆蓋，整體串接由 Task 5 的 `integration_test/` 間接驗證）。

- [ ] **Step 1: 修改 `index.html`**

Edit `app/assets/wifi_transfer/index.html`：

```html
<!-- 舊： -->
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
```

```html
<!-- 新： -->
  .placeholder { color: #888; }
  .book-item { display: block; padding: 4px 0; }
  button { font-size: 14px; padding: 8px 16px; margin-top: 8px; }
  #upload-dropzone {
    border: 2px dashed #aaa;
    border-radius: 8px;
    padding: 24px;
    text-align: center;
    color: #666;
  }
  #upload-dropzone.dragover { border-color: #333; background: #f0f0f0; }
  #upload-dropzone label { text-decoration: underline; cursor: pointer; }
  #upload-progress { display: none; width: 100%; margin-top: 8px; }
  #upload-result-list { list-style: none; padding: 0; margin: 8px 0 0; }
  #upload-result-list li { padding: 4px 0; }
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
    <div id="upload-dropzone">
      拖放檔案到此處，或
      <label for="upload-file-input">選擇檔案</label>
    </div>
    <input id="upload-file-input" type="file" multiple style="display: none;">
    <progress id="upload-progress" value="0" max="100"></progress>
    <ul id="upload-result-list"></ul>
  </section>
```

在既有 `<script>` 區塊結尾（`loadDownloadableBooks();` 之後、`</script>` 之前）新增：

```html
<!-- 舊： -->
    document
      .getElementById('download-selected-button')
      .addEventListener('click', downloadSelectedBooks);

    loadDownloadableBooks();
  </script>
```

```html
<!-- 新： -->
    document
      .getElementById('download-selected-button')
      .addEventListener('click', downloadSelectedBooks);

    loadDownloadableBooks();

    // 對應 UploadOutcome 四個值（wifi_transfer_service.dart）的顯示文案。
    const UPLOAD_OUTCOME_LABELS = {
      imported: '已匯入',
      duplicateSkipped: '已存在，已略過',
      unsupportedFormat: '格式不支援',
      failed: '匯入失敗',
    };

    // 【spec.md「PC 端網頁」第二輪審查修正】fetch() 原生不支援上傳進度
    // 事件，一律改用 XMLHttpRequest（xhr.upload.onprogress 顯示進度）。
    function uploadFiles(fileList) {
      if (fileList.length === 0) return;
      const formData = new FormData();
      for (const file of fileList) {
        formData.append('files', file, file.name);
      }
      const progressEl = document.getElementById('upload-progress');
      const resultListEl = document.getElementById('upload-result-list');
      progressEl.style.display = '';
      progressEl.value = 0;
      resultListEl.innerHTML = '';

      const xhr = new XMLHttpRequest();
      xhr.open('POST', '/api/upload');
      xhr.upload.onprogress = (event) => {
        if (event.lengthComputable) {
          progressEl.value = (event.loaded / event.total) * 100;
        }
      };
      // 【`/receiving-code-review` 審查修正，review-plan-issue-3.md M-1】
      // 非 2xx 回應（例如 400）的 body 是 `{"error": "..."}` 物件而非陣列，
      // 若不先檢查 xhr.status／Array.isArray() 就直接 for...of 疊代，會
      // 拋出 `TypeError: results is not iterable`；上傳成功時額外呼叫
      // loadDownloadableBooks() 刷新下方下載清單，避免使用者誤以為書籍
      // 未被手機收錄。
      xhr.onload = () => {
        progressEl.style.display = 'none';
        if (xhr.status >= 200 && xhr.status < 300) {
          try {
            const results = JSON.parse(xhr.responseText);
            if (Array.isArray(results)) {
              let hasImported = false;
              for (const result of results) {
                const li = document.createElement('li');
                const label = UPLOAD_OUTCOME_LABELS[result.outcome] || result.outcome;
                li.textContent = result.originalFileName + '：' + label;
                resultListEl.appendChild(li);
                if (result.outcome === 'imported') hasImported = true;
              }
              if (hasImported) loadDownloadableBooks();
              return;
            }
          } catch (err) {
            // 落到下方統一的失敗訊息分支。
          }
        }
        const li = document.createElement('li');
        li.textContent = '上傳失敗：' +
          (xhr.status ? `伺服器回應錯誤 (${xhr.status})` : '無法解析伺服器回應');
        resultListEl.appendChild(li);
      };
      xhr.onerror = () => {
        progressEl.style.display = 'none';
        const li = document.createElement('li');
        li.textContent = '上傳失敗：網路錯誤';
        resultListEl.appendChild(li);
      };
      xhr.send(formData);
    }

    const uploadFileInput = document.getElementById('upload-file-input');
    uploadFileInput.addEventListener('change', () => {
      uploadFiles(uploadFileInput.files);
      uploadFileInput.value = '';
    });

    const uploadDropzone = document.getElementById('upload-dropzone');
    uploadDropzone.addEventListener('dragover', (event) => {
      event.preventDefault();
      uploadDropzone.classList.add('dragover');
    });
    uploadDropzone.addEventListener('dragleave', () => {
      uploadDropzone.classList.remove('dragover');
    });
    uploadDropzone.addEventListener('drop', (event) => {
      event.preventDefault();
      uploadDropzone.classList.remove('dragover');
      uploadFiles(event.dataTransfer.files);
    });
  </script>
```

- [ ] **Step 2: 執行既有測試，確認未破壞 `GET /` 驗證**

Run: `flutter test test/wifi_transfer/wifi_transfer_http_server_test.dart`
Expected: PASS——`GET / 回傳 index.html 內容與正確 Content-Type／Cache-Control` 測試仍通過（只斷言 `contains('elinkBook WiFi 傳書')`，`<h1>` 未變動）。

- [ ] **Step 3: Commit**

```bash
git add app/assets/wifi_transfer/index.html
git commit -m "$(cat <<'EOF'
feat(wifi-transfer): index.html 補上上傳區塊 JS

epic-44-wifi-book-transfer Issue 3：拖放區＋<input type="file" multiple>
選檔，選定/拖放後一律用 XMLHttpRequest（非 fetch()，因 fetch() 原生
不支援上傳進度事件）上傳並以 <progress> 顯示進度；完成後依伺服器回應
的 JSON 陣列逐檔顯示「已匯入／已存在已略過／格式不支援／匯入失敗」
（對應 UploadOutcome 四個值）。無自動化測試（純 HTML/JS，背後路由已由
wifi_transfer_http_server_test.dart 覆蓋，整體串接由 Issue 3
integration_test 驗證）。

一併修正 review-plan-issue-3.md M-1：xhr.onload 先檢查 xhr.status 與
Array.isArray()，避免非 2xx 回應（body 是 {"error": "..."} 物件而非
陣列）觸發 TypeError: results is not iterable；上傳成功（outcome 含
imported）後自動呼叫既有 loadDownloadableBooks() 刷新下方下載清單。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5：`integration_test/wifi_transfer_screen_test.dart`——真機上傳驗證

**Files:**
- Modify: `app/integration_test/wifi_transfer_screen_test.dart`

**Interfaces:**
- Consumes：`WifiTransferScreen`（Issue 1）、真實 `SqliteLibraryRepository`／`BookImportServiceImpl`／`computeBookContentFingerprint`（既有，比照 `foliate_cbz_test.dart` 等既有 integration_test 使用真實圖書庫管線的先例，而非 Issue 2 下載測試使用的 Fake）。
- Produces：3 個新增 `testWidgets`，真機驗證上傳一個支援格式檔案成功出現在圖書庫、上傳不支援格式檔案被拒絕且不影響同一請求內其他檔案、重複上傳同一檔案兩次第二次靜默略過。**必須在真實裝置上執行**（`-d <device-id>`），且裝置須已連上 WiFi 或已開啟手機熱點。

**重複上傳測試改用 PDF，不用 EPUB**：見本計畫 Global Constraints 的「已知限制」說明——真實 EPUB 檔案若帶 `dc:identifier`，`handleUploadedFile()` 的去重指紋（內容 SHA-256）與 `BookImportServiceImpl` 正式匯入時存入的指紋（`dc:identifier`）不同，可能偵測不到重複；`test/fixtures/sample.epub` 實際上就帶有 `dc:identifier`（`urn:uuid:00000000-0000-0000-0000-000000000001`），若拿它測「重複上傳」會不穩定。PDF 格式的 `extractMetadata` 原生端不回傳 identifier，兩處指紋計算天然一致，用 `test/fixtures/sample.pdf` 才能穩定驗證去重邏輯本身正確。

- [ ] **Step 1: 修改測試檔**

Edit `app/integration_test/wifi_transfer_screen_test.dart`。先在檔案頂部新增 import：

```dart
// 舊：
import 'dart:convert';
import 'dart:io';

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
```

```dart
// 新：
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_content_fingerprint.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/screens/wifi_transfer_screen.dart';
import 'package:elinkbook/wifi_transfer/network_availability.dart';

import '../test/support/fake_book_import_service.dart';
import '../test/support/fake_library_repository.dart';
import '../test/support/fake_fingerprint_computer.dart';
```

在檔案結尾（最後一個 `testWidgets(...)` 的 `});` 之後、`}` 之前）新增 3 個 `testWidgets`：

```dart

  testWidgets(
      '真機：上傳一個支援格式檔案，成功出現在圖書庫（Issue 3 驗收）',
      (tester) async {
    sqfliteFfiInit();
    final repository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repository.close());
    final importService = BookImportServiceImpl(repository: repository);

    await tester.pumpWidget(
      MaterialApp(
        home: WifiTransferScreen(
          libraryRepository: repository,
          importService: importService,
          computeFingerprint: computeBookContentFingerprint,
          checkNetworkAvailability: checkNetworkAvailability,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證上傳；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }
    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final bytes =
        (await rootBundle.load('test/fixtures/sample.pdf')).buffer.asUint8List();
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'))
          ..files.add(http.MultipartFile.fromBytes('files', bytes,
              filename: '真機上傳測試書.pdf'));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    expect(response.statusCode, 200);
    final results = jsonDecode(response.body) as List<dynamic>;
    expect(results.single['outcome'], 'imported');

    final books = await repository.listBooks();
    expect(books, hasLength(1));
    expect(books.single.format, BookFileFormat.pdf);
  });

  testWidgets(
      '真機：上傳不支援格式檔案被拒絕，且不影響同一請求內其他檔案的解析'
      '（Issue 3 M-2 驗收）', (tester) async {
    sqfliteFfiInit();
    final repository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repository.close());
    final importService = BookImportServiceImpl(repository: repository);

    await tester.pumpWidget(
      MaterialApp(
        home: WifiTransferScreen(
          libraryRepository: repository,
          importService: importService,
          computeFingerprint: computeBookContentFingerprint,
          checkNetworkAvailability: checkNetworkAvailability,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證上傳；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }
    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final pdfBytes =
        (await rootBundle.load('test/fixtures/sample.pdf')).buffer.asUint8List();
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'))
          ..files.add(http.MultipartFile.fromBytes(
              'files', Uint8List.fromList([1, 2, 3]),
              filename: '不支援的檔案.docx'))
          ..files.add(http.MultipartFile.fromBytes('files', pdfBytes,
              filename: '正常上傳.pdf'));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    expect(response.statusCode, 200);
    final results = jsonDecode(response.body) as List<dynamic>;
    expect(results, hasLength(2));
    expect(results[0]['outcome'], 'unsupportedFormat');
    expect(results[1]['outcome'], 'imported');
    final books = await repository.listBooks();
    expect(books, hasLength(1));
  });

  testWidgets(
      '真機：重複上傳同一檔案兩次，第二次靜默略過、書架上只有一筆記錄'
      '（Issue 3 驗收；改用 PDF，理由見 plan-issue-3.md「已知限制」）',
      (tester) async {
    sqfliteFfiInit();
    final repository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repository.close());
    final importService = BookImportServiceImpl(repository: repository);

    await tester.pumpWidget(
      MaterialApp(
        home: WifiTransferScreen(
          libraryRepository: repository,
          importService: importService,
          computeFingerprint: computeBookContentFingerprint,
          checkNetworkAvailability: checkNetworkAvailability,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (tester.any(find.text('請連線至 WiFi 或開啟手機熱點'))) {
      fail('真機測試裝置目前沒有連上 WiFi／開啟熱點，無法驗證上傳；'
          '請先連線至 WiFi 或開啟手機熱點後重跑本測試。');
    }
    final ipTextWidget =
        tester.widget<Text>(find.byKey(const Key('wifi_transfer_ip_text')));
    final baseUrl = ipTextWidget.data!;

    final bytes =
        (await rootBundle.load('test/fixtures/sample.pdf')).buffer.asUint8List();

    Future<String> uploadOnce() async {
      final request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'))
            ..files.add(http.MultipartFile.fromBytes('files', bytes,
                filename: '重複測試.pdf'));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      expect(response.statusCode, 200);
      final results = jsonDecode(response.body) as List<dynamic>;
      return results.single['outcome'] as String;
    }

    final firstOutcome = await uploadOnce();
    final secondOutcome = await uploadOnce();

    expect(firstOutcome, 'imported');
    expect(secondOutcome, 'duplicateSkipped');
    final books = await repository.listBooks();
    expect(books, hasLength(1));
  });
```

- [ ] **Step 2: `flutter analyze` 確認乾淨**

Run: `flutter analyze integration_test/wifi_transfer_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 3: 真機執行（需人類操作：裝置已連上 WiFi 或開啟熱點）**

Run: `flutter test integration_test/wifi_transfer_screen_test.dart -d <device-id>`
Expected: 8 個測試全數通過（Issue 2 遺留的 5 個下載測試＋本 Task 新增的 3 個上傳測試）。若裝置目前未連上 WiFi/熱點，測試會以明確的 `fail()` 訊息中止（而非誤判為程式錯誤），依訊息指示連線後重跑。

- [ ] **Step 4: Commit**

```bash
git add app/integration_test/wifi_transfer_screen_test.dart
git commit -m "$(cat <<'EOF'
test(wifi-transfer): 新增 WifiTransferScreen 真機上傳驗證

epic-44-wifi-book-transfer Issue 3：新增 3 個真機 integration_test——
上傳一個支援格式檔案成功出現在圖書庫、同一請求內混合不支援/支援格式時
不支援的那個不會卡住後續解析（M-2 真機驗收）、重複上傳同一檔案兩次第
二次靜默略過。改用真實 SqliteLibraryRepository／BookImportServiceImpl／
computeBookContentFingerprint（比照 foliate_cbz_test.dart 等既有先例），
而非 Fake，讓「成功出現在圖書庫」「書架上只有一筆記錄」有真實資料庫可
驗證。重複上傳測試刻意改用 PDF 而非 EPUB，理由見 plan-issue-3.md
Global Constraints 的已知限制說明（EPUB 帶 dc:identifier 時兩處指紋
計算依據不同，可能偵測不到重複，非本次修正範圍）。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6：最終驗證

**Files:** 無新增/修改檔案，純驗證步驟。

- [ ] **Step 1: 完整 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 完整 `flutter test`（CLAUDE.md 規定：整張計畫最後一個 Task 才跑一次）**

Run: `flutter test`
Expected: 全數通過（或與 PR #258 合併當下已知、與本次異動無關的既存缺陷數量一致——`adaptive_shell_scaffold_test.dart` 的 `_batchActions` `LateInitializationError`，見 `reviews/review-issue-2.md`「驗證記錄」——需在審查報告中列出並比對 base commit 確認非本次異動引入的回歸）。

- [ ] **Step 3: 確認 Task 5 的真機測試已至少執行過一次**

若尚未在真實裝置上跑過 Task 5 的 `integration_test/wifi_transfer_screen_test.dart`，於此時執行：

Run: `flutter test integration_test/wifi_transfer_screen_test.dart -d <device-id>`
Expected: 8 個測試全數通過。

- [ ] **Step 4: 更新 `docs/epics/epic-44-wifi-book-transfer/issues.md` 與 `docs/epics.md` 進度**（比照 Issue 1／2 完成後的既有慣例，由人類或執行者在確認上述驗證皆通過後手動進行，非本計畫自動化步驟的一部分）
