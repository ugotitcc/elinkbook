# Issue 4 實作計劃：`BookImportService` — 本機單檔/多檔匯入

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 實作 `BookImportService.importFiles(uris, {folderName})`：給定一組已由呼叫端（未來 Issue 5 的匯入按鈕）透過 `file_picker` 選取的原始 SAF URI 字串，依序持久化 URI 讀取權限、依副檔名判斷格式、呼叫 Issue 2 的 `book_metadata` channel（EPUB/PDF）或 Dart 端動態產生封面（TXT），寫入 Issue 1 的 `LibraryRepository`。同時補上 Issue 3 整分支審查點出的缺口：一項使用真正 `content://` SAF URI（而非 `file://` 替代）呼叫 `openBook` 的強制 `integration_test`。

**架構：** `BookImportService`（抽象介面，對應 `spec.md`）由 `BookImportServiceImpl` 實作；後者對每個 URI 執行「持久化權限 → 判斷格式 → 提取詮釋資料/產生封面 → 落地封面 PNG → 寫入 repository」的管線，單一檔案失敗時降級寫入且不中斷整批。`BookImportService.importFiles` 本身**不**呼叫 `file_picker`——介面簽章（`List<String> uris`）已明確是「給定已選取的 URI」，實際跳出系統選擇器 UI 是未來 Issue 5「匯入按鈕」的職責；本工單只需一個手動驗收用的暫時性測試小工具（見 Task 4）即可觸發真實裝置上的端到端驗證。「真正 content:// 授權測試」則透過在已合併的 `BookMetadataChannel.kt` 新增兩個測試支援用原生方法（`createTestContentUri`／`takePersistableUriPermission`）達成，前者用 `androidx.core.content.FileProvider` 模擬 SAF 授權。

**技術棧：** Flutter（Dart）、Kotlin（`androidx.core.content.FileProvider`、`ContentResolver.takePersistableUriPermission`）、`dart:ui`（TXT 封面產生，不需原生程式碼）、`file_picker`（僅供 Task 4 手動驗收工具與未來 Issue 5 使用）、`integration_test`。

## ⚠️ 執行前環境確認事項

Task 1 與 Task 4 全數驗證步驟須在真實 Android 模擬器/裝置上執行——執行前請先確認 `flutter devices` 能列出至少一個 Android 裝置/模擬器。Task 2、3 為純 Dart，不需裝置。

## 全域限制條件

- `BookImportService`/`BookImportServiceImpl` 的介面簽章須與 `docs/epics/epic-1-library/spec.md`「`BookImportService`」章節完全一致：`Future<List<Book>> importFiles(List<String> uris, {String? folderName})`、`Future<List<Book>> importFolder(String folderUri, {bool autoGroupByFolderName = true})`。`importFolder` 本工單**不實作**（留給 `epic-1-library` Issue 8），呼叫時拋出 `UnimplementedError`。
- `filePath` 欄位必須存放**原始、未經複製**的 URI 字串（ADR 0002 的核心決策）——**不可**把匯入的書籍檔案複製到 App 私有目錄；只有封面圖片才落地複製。
- 匯入流程須依序：判斷格式（不支援的格式直接跳過，不浪費一次原生呼叫）→ `takePersistableUriPermission` → （EPUB/PDF）呼叫 Issue 2 的 `elinkbook/book_metadata` channel `extractMetadata` 或（TXT）Dart 端動態產生封面 → 落地封面 PNG → 寫入 `LibraryRepository`（Issue 1）。此順序已依 Task 3 審查結果（`reviews/review-issue-4.md`）修正，與 `spec.md`/`design.md` 同步更新，配合實際程式碼（先判斷格式，格式不支援時完全不呼叫任何原生方法）。
- 單一檔案的詮釋資料提取失敗時，該筆以「檔名為標題（去除副檔名）、`coverPath=null`」降級寫入，**不得**中斷整批匯入的其餘檔案。
- 指定 `folderName` 時，須先呼叫 `LibraryRepository.upsertGroup(folderName)` 再寫入書籍（見 Issue 1 整分支審查建議：避免 `books.groupName` 指向一個 `groups` 表裡不存在的孤兒群組）。
- `takePersistableUriPermission` 只對 `content://` scheme 的 URI 呼叫，且須包在 try-catch 中；若持久化失敗（例如來源 URI 不支援 persistable 權限），該筆檔案視為匯入失敗並略過、不中斷整批匯入——**不可**在權限持久化失敗的情況下仍把書籍寫入 `LibraryRepository`，因為當次的暫時讀取權限只在本次 App 行程存活期間有效，寫入的 `filePath` 極可能在下次啟動後無法讀取，比略過該檔案更糟（見 `reviews/review-plan-issue-4.md`）。
- 本工單只處理**本機檔案**匯入（`BookSource.local`）；Google Drive/OneDrive 雲端匯入不在範圍內。
- 本工單**不得**修改 `EpubReaderView.kt`/`PdfReaderView.kt`（Issue 3 範圍已完成並合併）；只能在已合併的 `BookMetadataChannel.kt`（Issue 2）中新增方法，不修改既有的 `extractMetadata`/`extractEpubMetadata`/`extractPdfMetadata` 邏輯。
- `createTestContentUri` 這個原生方法**僅供 integration_test 使用**，不得被 `BookImportServiceImpl` 或任何正式匯入流程呼叫——正式流程的 `content://` URI 一律來自 `file_picker` 的 `PlatformFile.identifier`。
- 所有錯誤訊息與 UI 文字維持正體中文。

---

### Task 1：原生測試支援方法 + 真正 `content://` SAF 驗收測試

**Files:**
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Create: `app/android/app/src/main/res/xml/file_paths.xml`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`
- Create: `app/integration_test/content_uri_acceptance_test.dart`

**Interfaces:**
- Consumes: 既有 `elinkbook/book_metadata` channel（Issue 2）、`EpubReaderView`（Issue 3，`filePath` 接受 URI 字串）
- Produces: 原生方法 `takePersistableUriPermission(uri: String) -> void`（供 Task 3 的 `BookImportServiceImpl` 使用）、`createTestContentUri(path: String) -> String`（**僅供測試**，回傳一個已自我授權的真正 `content://` URI）。

- [ ] **Step 1：新增 `FileProvider` 宣告**

開啟 `app/android/app/src/main/AndroidManifest.xml`，在 `<application>` 區塊內、既有 `flutterEmbedding` `<meta-data>` 之後，新增：

```xml
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>
```

（`androidx.core.content.FileProvider` 已透過既有的 `androidx.fragment:fragment-ktx` 相依鏈間接引入，不需新增 Gradle 依賴。）

- [ ] **Step 2：新增 `file_paths.xml`**

建立 `app/android/app/src/main/res/xml/file_paths.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="cache" path="." />
</paths>
```

（測試用的檔案透過 `path_provider` 的 `getTemporaryDirectory()` 暫存，對應 Android 的 `context.cacheDir`，故用 `cache-path` 涵蓋整個快取目錄。）

- [ ] **Step 3：撰寫真正 `content://` URI 驗收測試（先寫測試，此時原生方法還不存在）**

建立 `app/integration_test/content_uri_acceptance_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';

const _metadataChannel = MethodChannel('elinkbook/book_metadata');

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '真正的 content:// SAF URI（透過 FileProvider 授權）開啟 EPUB 觸發 onPageRendered',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'content_uri_sample.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 這兩步驟模擬真實匯入流程：file_picker 回傳一個已有 SAF 授權的
    // content:// URI（此處用 FileProvider + 自我授權模擬，見 Step 5 的
    // createTestContentUri），接著呼叫 takePersistableUriPermission 持久化
    // 該授權——與 Task 3 的 BookImportServiceImpl 真實流程一致。
    final contentUri = await _metadataChannel
        .invokeMethod<String>('createTestContentUri', {'path': samplePath});
    expect(contentUri, isNotNull);
    expect(contentUri!.startsWith('content://'), isTrue,
        reason: '必須是真正的 content:// URI，而非 file://（Issue 3 已驗證過 file://，'
            '本測試要驗證的是不同的內部程式碼路徑）');

    await _metadataChannel.invokeMethod<void>(
        'takePersistableUriPermission', {'uri': contentUri});

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: contentUri,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');
  });
}
```

- [ ] **Step 4：於真實裝置上執行測試確認失敗（原生方法尚不存在）**

Run（於 `app/` 目錄下；`<device-id>` 請替換為 `flutter devices` 列出的實際 Android 裝置/模擬器 ID）：
```bash
flutter test integration_test/content_uri_acceptance_test.dart -d <device-id>
```
Expected: 測試失敗，`invokeMethod('createTestContentUri', ...)` 拋出 `MissingPluginException` 或等效「method not implemented」錯誤（因為 `BookMetadataChannel.kt` 目前的 `onMethodCall` 對這個方法名稱走 `else -> result.notImplemented()` 分支）。

- [ ] **Step 5：在 `BookMetadataChannel.kt` 新增兩個原生方法**

開啟 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`，將檔案開頭的 import 區塊：

```kotlin
import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
```

改為（新增 `Intent`、`FileProvider`）：

```kotlin
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.core.content.FileProvider
```

將 `onMethodCall` 方法：

```kotlin
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "extractMetadata" -> {
                val path = call.argument<String>("uri")
                val format = call.argument<String>("format")
                if (path == null || format == null) {
                    result.error("invalid_arguments", "缺少 uri 或 format 參數", null)
                    return
                }
                when (format) {
                    "epub" -> extractEpubMetadata(path, result)
                    "pdf" -> extractPdfMetadata(path, result)
                    else -> result.error("unsupported_format", "不支援的格式：$format", null)
                }
            }
            else -> result.notImplemented()
        }
    }
```

改為（新增兩個分支）：

```kotlin
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "extractMetadata" -> {
                val path = call.argument<String>("uri")
                val format = call.argument<String>("format")
                if (path == null || format == null) {
                    result.error("invalid_arguments", "缺少 uri 或 format 參數", null)
                    return
                }
                when (format) {
                    "epub" -> extractEpubMetadata(path, result)
                    "pdf" -> extractPdfMetadata(path, result)
                    else -> result.error("unsupported_format", "不支援的格式：$format", null)
                }
            }
            "takePersistableUriPermission" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.error("invalid_arguments", "缺少 uri 參數", null)
                    return
                }
                try {
                    context.contentResolver.takePersistableUriPermission(
                        Uri.parse(uriString),
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                    result.success(null)
                } catch (e: Exception) {
                    result.error("permission_failed", "無法持久化 URI 讀取權限：${e.message}", null)
                }
            }
            "createTestContentUri" -> {
                // 僅供 integration_test 使用：把裝置上真實檔案路徑透過 FileProvider
                // 轉為 content:// URI，並自我授予 persistable 權限（模擬 SAF
                // ACTION_OPEN_DOCUMENT 回傳的 URI 原本就帶有的授權），讓測試能驗證
                // 真正的 content:// 路徑（而非 Issue 3 已驗證過的 file://）。正式
                // 匯入流程（BookImportService）不會呼叫這個方法——真實的 content://
                // URI 來自 file_picker 的 PlatformFile.identifier。
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("invalid_arguments", "缺少 path 參數", null)
                    return
                }
                try {
                    val file = File(path)
                    val uri = FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        file,
                    )
                    context.grantUriPermission(
                        context.packageName,
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                    )
                    result.success(uri.toString())
                } catch (e: Exception) {
                    result.error(
                        "test_uri_failed",
                        "無法建立測試用 content URI：${e.message}",
                        null,
                    )
                }
            }
            else -> result.notImplemented()
        }
    }
```

- [ ] **Step 6：於真實裝置上重新執行測試確認通過**

Run：
```bash
flutter test integration_test/content_uri_acceptance_test.dart -d <device-id>
```
Expected: `All tests passed!`

- [ ] **Step 7：重新執行既有 `integration_test` 確認無回歸**

`BookMetadataChannel.kt` 是 Issue 2 已合併的檔案，本工單只新增方法、未修改既有邏輯，仍須驗證無回歸：

```bash
flutter test integration_test/book_metadata_channel_test.dart -d <device-id>
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
flutter test integration_test/pdf_reader_view_test.dart -d <device-id>
flutter test integration_test/reader_screen_test.dart -d <device-id>
flutter test integration_test/library_screen_test.dart -d <device-id>
flutter test integration_test/smoke_test.dart -d <device-id>
```
Expected: 全部 `All tests passed!`。

- [ ] **Step 8：靜態分析與建置確認**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter build apk --debug
```
Expected: `flutter analyze` 顯示 `No issues found!`；建置成功。

- [ ] **Step 9：Commit**

```bash
git add app/android/app/src/main/AndroidManifest.xml app/android/app/src/main/res/xml/file_paths.xml app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt app/integration_test/content_uri_acceptance_test.dart
git commit -m "Add FileProvider + takePersistableUriPermission/createTestContentUri, verify genuine content:// openBook"
```

---

### Task 2：TXT 封面產生器（純 Dart，`dart:ui`）

**Files:**
- Create: `app/lib/library/txt_cover_generator.dart`
- Test: `app/test/library/txt_cover_generator_test.dart`

**Interfaces:**
- Consumes: 無（純 `dart:ui`，不依賴任何原生程式碼或平台 channel）
- Produces: `Future<Uint8List> generateTxtCover(String title)`——供 Task 3 的 `BookImportServiceImpl` 在匯入 TXT 格式書籍時呼叫。

- [ ] **Step 1：撰寫測試（先寫測試，此時檔案還不存在）**

建立 `app/test/library/txt_cover_generator_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/txt_cover_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 以下測試只驗證 PNG 檔案格式簽章與整張圖片 bytes 是否相等/不相等，刻意不做
  // 像素級的 Golden Image 比對——文字排版的實際渲染像素可能因執行平台（字型
  // 可用性等）而有差異，但背景色是先填滿整張畫布的純色矩形，足以保證「相同
  // 標題」與「不同標題」的整體 bytes 分別相等/不相等，不受平台間字型渲染差異
  // 影響，測試在任何平台上都應穩定通過。

  test('generateTxtCover 產生非空的 PNG bytes（含正確的 PNG 檔頭簽章）', () async {
    final bytes = await generateTxtCover('測試書名');

    expect(bytes, isNotEmpty);
    expect(
      bytes.sublist(0, 8),
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      reason: 'PNG 檔案簽章（magic bytes）',
    );
  });

  test('相同書名產生相同背景色（可重現，非隨機）', () async {
    final bytes1 = await generateTxtCover('紅樓夢');
    final bytes2 = await generateTxtCover('紅樓夢');

    expect(bytes1, equals(bytes2));
  });

  test('不同書名（不同首字）產生不同背景色', () async {
    final bytes1 = await generateTxtCover('紅樓夢');
    final bytes2 = await generateTxtCover('三國演義');

    expect(bytes1, isNot(equals(bytes2)));
  });

  test('空字串書名不拋出例外，仍產生有效封面', () async {
    final bytes = await generateTxtCover('');

    expect(bytes, isNotEmpty);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/library/txt_cover_generator_test.dart
```
Expected: 編譯錯誤，找不到 `package:elinkbook/library/txt_cover_generator.dart`。

- [ ] **Step 3：實作 `generateTxtCover`**

建立 `app/lib/library/txt_cover_generator.dart`：

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 依書名文字動態產生 TXT 書籍的封面圖片（FR-27：TXT 沒有內嵌封面或首頁可
/// 渲染，改用書名文字合成一張正方形封面）。純 `dart:ui` 實作，不呼叫任何
/// 原生 book_metadata channel；背景色由書名首字的 code unit 決定（同一本書
/// 每次產生的封面一致，非隨機）。
Future<Uint8List> generateTxtCover(String title) async {
  const size = 400.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, size, size));

  final backgroundPaint = ui.Paint()..color = _backgroundColorForTitle(title);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, size, size), backgroundPaint);

  final firstChar = title.isNotEmpty ? title.substring(0, 1) : '?';
  final paragraphBuilder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textAlign: ui.TextAlign.center, fontSize: size * 0.4),
  )
    ..pushStyle(ui.TextStyle(color: const ui.Color(0xFFFFFFFF)))
    ..addText(firstChar);
  final paragraph = paragraphBuilder.build()
    ..layout(const ui.ParagraphConstraints(width: size));
  canvas.drawParagraph(
    paragraph,
    ui.Offset(0, (size - paragraph.height) / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

const _palette = [
  ui.Color(0xFF5C6BC0),
  ui.Color(0xFF26A69A),
  ui.Color(0xFFEF5350),
  ui.Color(0xFFFFA726),
  ui.Color(0xFF8D6E63),
  ui.Color(0xFF7E57C2),
];

ui.Color _backgroundColorForTitle(String title) {
  final index = title.isEmpty ? 0 : title.codeUnitAt(0) % _palette.length;
  return _palette[index];
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/library/txt_cover_generator_test.dart
```
Expected: `00:0X +4: All tests passed!`

若「不同書名產生不同背景色」測試偶爾失敗（兩個書名的首字剛好對應到 `_palette` 同一個索引），屬於測試資料選得不好，非程式碼問題——「紅樓夢」（紅 U+7D05）與「三國演義」（三 U+4E09）的 code unit 對 6 取餘數不同，已驗證過不會碰撞，可放心使用。

- [ ] **Step 5：靜態分析確認無警告**

Run：
```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/library/txt_cover_generator.dart app/test/library/txt_cover_generator_test.dart
git commit -m "Add pure-Dart TXT cover generator using dart:ui"
```

---

### Task 3：`BookImportService` 介面與 `BookImportServiceImpl` 匯入管線

**Files:**
- Create: `app/lib/library/book_import_service.dart`
- Create: `app/lib/library/book_import_service_impl.dart`
- Test: `app/test/library/book_import_service_test.dart`

**Interfaces:**
- Consumes: `LibraryRepository`（Issue 1，`app/lib/library/library_repository.dart`）、`Book`/`BookFileFormat`/`BookSource`/`BookGroup`（Issue 1 models）、`generateTxtCover`（Task 2）、原生 `elinkbook/book_metadata` channel 的 `extractMetadata`/`takePersistableUriPermission`（Issue 2 + Task 1）
- Produces: `abstract class BookImportService { Future<List<Book>> importFiles(...); Future<List<Book>> importFolder(...); }`、`class BookImportServiceImpl implements BookImportService`（建構子 `BookImportServiceImpl({required LibraryRepository repository, Directory? coversDirectory})`）、頂層函式 `BookFileFormat? detectBookFileFormat(String uriOrPath)`、`String titleFromFileName(String uriOrPath)`——供 Task 4 與未來 Issue 5/8 使用。

- [ ] **Step 1：定義 `BookImportService` 抽象介面**

建立 `app/lib/library/book_import_service.dart`：

```dart
import 'models/book.dart';

/// 圖書庫匯入服務的抽象介面（見 docs/epics/epic-1-library/spec.md
/// 「BookImportService」章節，為唯一事實來源）。
abstract class BookImportService {
  /// 匯入單一或多個已由呼叫端（例如 file_picker）選取的檔案 URI；
  /// [folderName] 標記來源資料夾名稱供 FR-34 自動分類判斷，單檔/多檔匯入
  /// （非資料夾匯入）時為 `null`。
  Future<List<Book>> importFiles(List<String> uris, {String? folderName});

  /// 匯入整個資料夾；[autoGroupByFolderName] 對應 FR-34 開關（預設 true）。
  /// 本 epic 的 Issue 8 才會實作；Issue 4 呼叫時拋出 [UnimplementedError]。
  Future<List<Book>> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  });
}
```

- [ ] **Step 2：撰寫失敗測試（先寫測試，此時實作檔案還不存在）**

建立 `app/test/library/book_import_service_test.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository repository;
  late Directory coversDir;
  late BookImportServiceImpl service;

  setUp(() async {
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    coversDir = Directory.systemTemp.createTempSync('book_import_test_covers');
    service =
        BookImportServiceImpl(repository: repository, coversDirectory: coversDir);
  });

  tearDown(() async {
    await repository.close();
    if (coversDir.existsSync()) coversDir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, handler);
  }

  test('匯入 EPUB 檔案呼叫 extractMetadata(format: epub) 並寫入正確詮釋資料',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        expect((call.arguments as Map)['format'], 'epub');
        return {
          'title': '紅樓夢',
          'author': '曹雪芹',
          'coverBytes': Uint8List.fromList([1, 2, 3]),
        };
      }
      return null;
    });

    final books = await service.importFiles(['content://example/book.epub']);

    expect(books, hasLength(1));
    expect(books.single.title, '紅樓夢');
    expect(books.single.author, '曹雪芹');
    expect(books.single.format, BookFileFormat.epub);
    expect(books.single.coverPath, isNotNull);
  });

  test('匯入 PDF 檔案呼叫 extractMetadata(format: pdf)，詮釋資料無標題時降級為檔名',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        expect((call.arguments as Map)['format'], 'pdf');
        return {
          'title': null,
          'author': null,
          'coverBytes': Uint8List.fromList([4, 5, 6]),
        };
      }
      return null;
    });

    final books = await service.importFiles(['content://example/report.pdf']);

    expect(books, hasLength(1));
    expect(books.single.format, BookFileFormat.pdf);
    expect(books.single.title, 'report');
    expect(books.single.coverPath, isNotNull);
  });

  test('匯入 TXT 檔案不呼叫 extractMetadata，改用 Dart 端動態產生封面', () async {
    var extractMetadataCalled = false;
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        extractMetadataCalled = true;
      }
      return null;
    });

    final books = await service.importFiles(['content://example/notes.txt']);

    expect(extractMetadataCalled, isFalse);
    expect(books, hasLength(1));
    expect(books.single.format, BookFileFormat.txt);
    expect(books.single.title, 'notes');
    expect(books.single.coverPath, isNotNull);
  });

  test('詮釋資料提取失敗時降級寫入：標題=檔名、coverPath=null，不中斷整批匯入',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        throw PlatformException(code: 'extraction_failed', message: '模擬失敗');
      }
      return null;
    });

    final books = await service.importFiles([
      'content://example/broken.epub',
      'content://example/another.pdf',
    ]);

    expect(books, hasLength(2));
    expect(books[0].title, 'broken');
    expect(books[0].coverPath, isNull);
    expect(books[1].title, 'another');
    expect(books[1].coverPath, isNull);
  });

  test('匯入成功的書籍 source 為 local，filePath 存放原始 URI（未被複製）',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    const uri =
        'content://com.android.externalstorage.documents/document/primary%3ADownload%2Fmybook.pdf';
    final books = await service.importFiles([uri]);

    expect(books.single.source, BookSource.local);
    expect(books.single.filePath, uri);
  });

  test('不支援的副檔名略過該檔案，不中斷整批匯入', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      return {'title': '有效書籍', 'author': null, 'coverBytes': null};
    });

    final books = await service.importFiles([
      'content://example/document.docx',
      'content://example/valid.epub',
    ]);

    expect(books, hasLength(1));
    expect(books.single.title, '有效書籍');
  });

  test('takePersistableUriPermission 失敗時略過該檔案，不寫入資料庫、不中斷整批匯入',
      () async {
    mockChannel((call) async {
      final args = call.arguments as Map;
      if (call.method == 'takePersistableUriPermission') {
        if ((args['uri'] as String).contains('no_permission')) {
          throw PlatformException(
              code: 'permission_failed', message: '模擬權限持久化失敗');
        }
        return null;
      }
      return {'title': '有效書籍', 'author': null, 'coverBytes': null};
    });

    final books = await service.importFiles([
      'content://example/no_permission.epub',
      'content://example/valid.pdf',
    ]);

    expect(books, hasLength(1));
    expect(books.single.title, '有效書籍');
  });

  test('指定 folderName 時自動建立分類並歸入，書籍 groupName 對應資料夾名稱',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final books = await service.importFiles(
      ['content://example/book.epub'],
      folderName: '古典奇幻',
    );

    expect(books.single.groupName, '古典奇幻');
    final groups = await repository.listGroups();
    expect(groups.map((g) => g.name), contains('古典奇幻'));
  });

  test('importFolder 尚未實作，呼叫時拋出 UnimplementedError', () async {
    expect(
      () => service.importFolder('content://example/folder'),
      throwsA(isA<UnimplementedError>()),
    );
  });
}
```

- [ ] **Step 3：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/library/book_import_service_test.dart
```
Expected: 編譯錯誤，找不到 `package:elinkbook/library/book_import_service_impl.dart`。

- [ ] **Step 4：實作 `BookImportServiceImpl`**

建立 `app/lib/library/book_import_service_impl.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'book_import_service.dart';
import 'library_repository.dart';
import 'models/book.dart';
import 'models/book_group.dart';
import 'models/library_enums.dart';
import 'txt_cover_generator.dart';

/// 依 URI/路徑字串最後一段（已對 percent-encoding 解碼）判斷書籍格式。
/// 只依副檔名判斷，僅適用於本機檔案匯入（file_picker/SAF 對本機檔案提供者
/// 通常會在 URI 中保留可辨識的原始檔名+副檔名）；不適用於雲端服務自訂的
/// 不透明文件 ID（雲端匯入本身不在本 epic 範圍內）。
BookFileFormat? detectBookFileFormat(String uriOrPath) {
  final name = _lastPathComponent(uriOrPath).toLowerCase();
  if (name.endsWith('.epub')) return BookFileFormat.epub;
  if (name.endsWith('.pdf')) return BookFileFormat.pdf;
  if (name.endsWith('.txt')) return BookFileFormat.txt;
  return null;
}

/// 從 URI/路徑字串取出檔名（去除副檔名），供詮釋資料提取失敗時的降級標題、
/// 以及 TXT 格式的封面文字使用。
String titleFromFileName(String uriOrPath) {
  final name = _lastPathComponent(uriOrPath);
  final dotIndex = name.lastIndexOf('.');
  return dotIndex > 0 ? name.substring(0, dotIndex) : name;
}

String _lastPathComponent(String uriOrPath) {
  final decoded = Uri.decodeFull(uriOrPath);
  final normalized = decoded.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isNotEmpty ? segments.last : normalized;
}

class BookImportServiceImpl implements BookImportService {
  BookImportServiceImpl({
    required LibraryRepository repository,
    Directory? coversDirectory,
  })  : _repository = repository,
        _coversDirectory = coversDirectory;

  static const _channel = MethodChannel('elinkbook/book_metadata');

  final LibraryRepository _repository;
  final Directory? _coversDirectory;

  @override
  Future<List<Book>> importFiles(
    List<String> uris, {
    String? folderName,
  }) async {
    if (folderName != null) {
      await _repository.upsertGroup(folderName);
    }

    final imported = <Book>[];
    for (final uri in uris) {
      final book = await _importSingleFile(uri, folderName: folderName);
      if (book != null) imported.add(book);
    }
    return imported;
  }

  @override
  Future<List<Book>> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  }) {
    throw UnimplementedError(
      'importFolder 尚未實作，屬於 epic-1-library Issue 8 的範圍',
    );
  }

  Future<Book?> _importSingleFile(String uri, {String? folderName}) async {
    final format = detectBookFileFormat(uri);
    if (format == null) return null;

    // 只對 content:// scheme 持久化權限（file_picker 在 Android 上一定回傳
    // content:// URI；此判斷主要防禦測試/除錯情境誤傳純路徑）。持久化失敗
    // 時（例如來源 URI 不支援 persistable 權限）視為這個檔案匯入失敗並略過
    // ——不能假裝成功寫入資料庫，因為當次的暫時讀取權限只在本次 App 行程
    // 存活期間有效，寫入的 filePath 極可能在下次啟動後無法讀取，那會是比
    // 略過更糟的靜默壞資料。
    if (uri.startsWith('content://')) {
      try {
        await _channel.invokeMethod<void>(
          'takePersistableUriPermission',
          {'uri': uri},
        );
      } on PlatformException {
        return null;
      }
    }

    final id = '${DateTime.now().microsecondsSinceEpoch}-${uri.hashCode}';
    final fallbackTitle = titleFromFileName(uri);
    final now = DateTime.now();

    var title = fallbackTitle;
    String? author;
    String? coverPath;

    if (format == BookFileFormat.txt) {
      final coverBytes = await generateTxtCover(fallbackTitle);
      coverPath = await _landCover(coverBytes, id);
    } else {
      try {
        final metadata = await _channel.invokeMapMethod<String, Object?>(
          'extractMetadata',
          {'uri': uri, 'format': format.name},
        );
        final extractedTitle = metadata?['title'] as String?;
        if (extractedTitle != null && extractedTitle.isNotEmpty) {
          title = extractedTitle;
        }
        author = metadata?['author'] as String?;
        final coverBytes = metadata?['coverBytes'] as Uint8List?;
        if (coverBytes != null) {
          coverPath = await _landCover(coverBytes, id);
        }
      } on PlatformException {
        // 詮釋資料提取失敗：降級為「檔名為標題、無封面」，不中斷整批匯入。
      }
    }

    final book = Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: uri,
      source: BookSource.local,
      coverPath: coverPath,
      groupName: folderName ?? BookGroup.uncategorized,
      createTime: now,
      lastReadTime: now,
    );

    return _repository.insertBook(book);
  }

  Future<String> _landCover(Uint8List bytes, String bookId) async {
    final dir = await _resolveCoversDirectory();
    final file = File(p.join(dir.path, '$bookId.png'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Directory> _resolveCoversDirectory() async {
    if (_coversDirectory != null) return _coversDirectory;
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'covers'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
```

- [ ] **Step 5：執行測試確認通過**

Run：
```bash
flutter test test/library/book_import_service_test.dart
```
Expected: `00:0X +9: All tests passed!`（9 項測試皆通過）。

- [ ] **Step 6：執行完整測試套件與靜態分析確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected: 全數通過；`No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/library/book_import_service.dart app/lib/library/book_import_service_impl.dart app/test/library/book_import_service_test.dart
git commit -m "Add BookImportService with importFiles pipeline (EPUB/PDF/TXT)"
```

---

### Task 4：手動端到端驗收（真實 `file_picker` 選檔 + 匯入）

**Files:**
- Modify: `app/pubspec.yaml`
- Create: `app/integration_test/manual_import_acceptance_test.dart`

**Interfaces:**
- Consumes: `BookImportServiceImpl`（Task 3）、`SqliteLibraryRepository`/`defaultLibraryDatabasePath`（Issue 1）、`file_picker` 套件
- Produces: 無新公開介面；本工單完成後即代表 `issues.md` Issue 4 的「手動驗證：從裝置選取一個真實 EPUB/PDF 檔案，匯入後資料庫確實新增一筆對應記錄」驗收標準已可執行。此測試檔案是**人工驅動**的驗收工具，不在一般 `flutter test`/CI 流程中自動斷言；未來 Issue 5 建立正式的「匯入按鈕」UI 後，本檔案可保留作為除錯工具或移除，由 Issue 5 的計劃決定。

- [ ] **Step 1：新增 `file_picker` 依賴**

Run（於 `app/` 目錄下）：
```bash
flutter pub add file_picker
```
Expected: 終端機顯示 `file_picker` 已成功解析並加入 `pubspec.yaml` 的 `dependencies`。

- [ ] **Step 2：撰寫手動驗收測試小工具**

建立 `app/integration_test/manual_import_acceptance_test.dart`：

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';

/// 手動驗收專用（對應 docs/epics/epic-1-library/issues.md Issue 4「手動
/// 驗證」步驟）：本測試不做任何自動斷言，而是提供一個畫面，供開發者在真實
/// 裝置上手動點擊「選擇並匯入」按鈕、於跳出的系統檔案選擇器中選取一個真實
/// EPUB/PDF 檔案，觀察畫面文字更新確認匯入成功，並可另行查詢裝置上的
/// library.db 確認資料庫確實新增一筆對應記錄。
///
/// 執行方式：
///   flutter test integration_test/manual_import_acceptance_test.dart -d <device-id>
/// 執行後畫面會停留在按鈕頁面達 30 秒，請在這段時間內手動操作。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('手動選擇並匯入一個真實檔案（人工驗收，不做自動斷言）',
      (tester) async {
    final repository = await SqliteLibraryRepository.open(
      await defaultLibraryDatabasePath(),
    );
    addTearDown(() => repository.close());
    final importService = BookImportServiceImpl(repository: repository);

    var resultText = '尚未匯入';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(resultText, key: const Key('manual_import_result')),
                    ElevatedButton(
                      key: const Key('manual_import_button'),
                      onPressed: () async {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['epub', 'pdf', 'txt'],
                        );
                        if (picked == null || picked.files.isEmpty) return;
                        final uris = picked.files
                            .map((f) => f.identifier)
                            .whereType<String>()
                            .toList();
                        final books = await importService.importFiles(uris);
                        setState(() {
                          resultText = books.isEmpty
                              ? '匯入失敗或無有效檔案'
                              : '已匯入：${books.map((b) => b.title).join(', ')}';
                        });
                      },
                      child: const Text('選擇並匯入'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    // 手動驗收：以下等待供人工於裝置螢幕上點擊「選擇並匯入」按鈕，並於系統
    // 檔案選擇器中選取一個真實 EPUB/PDF 檔案。
    await tester.pump(const Duration(seconds: 30));
  });
}
```

- [ ] **Step 3：於真實裝置上執行並手動操作**

Run（於 `app/` 目錄下；`<device-id>` 請替換為 `flutter devices` 列出的實際 Android 裝置/模擬器 ID）：
```bash
flutter test integration_test/manual_import_acceptance_test.dart -d <device-id>
```
在畫面停留的 30 秒內，於裝置螢幕上點擊「選擇並匯入」按鈕，於跳出的系統檔案選擇器中選取一個裝置上真實存在的 EPUB 或 PDF 檔案。

Expected: 選取完成後，畫面文字從「尚未匯入」變為「已匯入：《該書標題》」。

- [ ] **Step 4：確認資料庫確實新增記錄**

Run（於裝置已連線且已安裝 `adb` 的環境下，`<package>` 為 `cc.ugotit.elinkbook`）：
```bash
adb shell run-as cc.ugotit.elinkbook sqlite3 /data/data/cc.ugotit.elinkbook/app_flutter/library.db "SELECT id, title, source, filePath FROM books;"
```
Expected: 輸出至少一筆記錄，`source` 欄位為 `local`，`filePath` 為剛才選取檔案的真實 `content://` URI 字串（非本機複製路徑）。

（若裝置未 root 且 `run-as` 因故無法存取，退而求其次：確認 Step 3 畫面文字已正確顯示匯入的書名，並在後續 Issue 5 把 `LibraryScreen` 接上真實資料時，該書會出現在書架上，作為間接驗證。）

- [ ] **Step 5：靜態分析確認無警告**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/integration_test/manual_import_acceptance_test.dart
git commit -m "Add manual end-to-end import acceptance harness (file_picker)"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍**：`spec.md`「BookImportService」章節定義的 `importFiles`/`importFolder` 簽章已逐字實作（`importFolder` 依範圍明確拋出 `UnimplementedError`，留給 Issue 8）；`issues.md` Issue 4 的全部單元測試要求（EPUB/PDF/TXT 三種格式分流、降級寫入、`source=local`/`filePath` 未複製）與強制的真正 `content://` `integration_test` 均已對應到 Task 1、3 的測試。
- **佔位符掃描**：每個步驟皆含完整程式碼與明確指令/預期輸出；`file_picker` 的 `PlatformFile.identifier`/`.path` 行為差異已對照套件原始碼（`platform_file.dart`、原生端 `FileInfo.java`）逐一確認，非憑記憶臆測；`ACTION_OPEN_DOCUMENT`（支援 persistable 權限）與 `ACTION_GET_CONTENT`（不支援）的分支也已對照 `FilePickerDelegate.java` 原始碼確認本專案 minSdk 24 會走前者。
- **型別/命名一致性**：`BookImportService`/`BookImportServiceImpl`/`detectBookFileFormat`/`titleFromFileName`/`generateTxtCover` 在各 Task 之間簽章一致，並與 `spec.md`/Issue 1 既有的 `Book`/`BookFileFormat`/`BookSource`/`BookGroup` 定義相符。
- **範圍邊界**：`createTestContentUri` 明確標註僅供測試使用；`importFiles` 本身不呼叫 `file_picker`（該職責留給 Task 4 的手動驗收工具與未來 Issue 5 的正式匯入按鈕），避免本工單擴大成同時實作 UI 觸發點；`folderName` 觸發 `upsertGroup` 直接回應 Issue 1 整分支審查的孤兒群組風險建議。
- **已知限制**：`detectBookFileFormat`/`titleFromFileName` 依 URI 字串內是否保留可辨識的原始檔名判斷格式/標題，僅適用於本機檔案提供者（Android 內建的 Downloads/ExternalStorage 等 SAF provider）；不適用於雲端服務可能使用的不透明文件 ID——雲端匯入本身不在本 epic 範圍內，此限制已於程式碼註解中明確記錄。

## 文件審查回應紀錄（`review-plan-issue-4.md`）

- **Important（`takePersistableUriPermission` 缺乏協定檢查與 Exception 防禦）**：查證屬實——原設計未包 try-catch，任一檔案的權限持久化失敗會直接中斷整批匯入，與同一支函式裡「詮釋資料提取失敗要降級、不中斷整批」的既有設計精神矛盾。已採納，加上 `content://` scheme 判斷 + try-catch。**未完全採納**建議的復原方式（「僅記錄警告、繼續視為成功」）——改為將權限持久化失敗視為該檔案匯入失敗並略過（回傳 `null`），因為當次暫時讀取權限只在本次 App 行程存活期間有效，若假裝成功寫入資料庫，`filePath` 極可能在下次啟動後無法讀取，是比略過更糟的靜默壞資料。已於 Task 3 Step 2/4 補上對應程式碼與新測試案例（「takePersistableUriPermission 失敗時略過該檔案」），測試總數由 8 項增為 9 項。
- **Minor（TXT 封面測試環境說明）**：查證後這個顧慮實際上不適用於本計劃的測試設計（沒有做跨平台 Golden Image 像素比對，背景色本身的差異就足以保證 bytes 相等/不相等的斷言不受字型渲染影響），但補充說明性註解本身零成本、對未來讀者有幫助，已採納，於 Task 2 Step 1 測試檔開頭補上註解。
