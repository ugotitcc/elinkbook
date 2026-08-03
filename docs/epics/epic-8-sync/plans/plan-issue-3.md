# Epic 8 Issue 3 — 書籍內容指紋計算 + 匯入流程串接 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking。

**Goal:** 新增 `computeBookContentFingerprint()`，在匯入流程中為每本書計算跨裝置身份指紋（EPUB 優先 OPF identifier、缺漏或 PDF/TXT 用全檔案 SHA-256），寫入 Issue 1 已新增的 `books.content_fingerprint` 欄位，供 Epic 8 後續 Issue（同步引擎的跨裝置書籍比對）使用。

**Architecture:** 指紋計算依 `filePath` 是否為 `content://` URI 分兩條路徑：本機檔案路徑在 Dart 端用 `File.openRead()` 串流＋`package:crypto` 計算，外包至 `Isolate.run()`；`content://` URI（ADR 0002：Dart 的 `dart:io File` 無法直接開啟）委由原生端新增的 `computeSha256`（`BookMetadataChannel.kt`）以 `ContentResolver` 串流計算，只有最終雜湊字串跨平台通道傳回。EPUB 的 OPF identifier 由既有 `extractMetadata` 呼叫一併回傳（不新增原生往返），由呼叫端（`book_import_service_impl.dart`）決定是否優先採用。

**Tech Stack:** Flutter/Dart、Kotlin（`BookMetadataChannel.kt`）、新增 `package:crypto`。純 widget/unit test（`flutter test`）供 Dart 端邏輯；Kotlin 變更的行為正確性由 `integration_test`（真機）驗證。

## Global Constraints

- **依賴 Issue 1 已完成的交付物**：`books.content_fingerprint TEXT` 欄位已存在（`sqlite_library_repository.dart` `onCreate` 內 `books` 表的 `CREATE TABLE` 已含此欄位，2026-08-03 完成並驗證），本 Issue 不需要再動 schema。
- **`filePath` 可能是本機檔案路徑，也可能是 `content://` URI**（ADR 0002）：`book_import_service_impl.dart` 的 `_importSingleFile()` 只有在「`takePersistableUriPermission` 失敗」或「URI 本身無可辨識副檔名」時才會把 `resolvedUri` 落地成本機複本，其餘情況（多數實際匯入情境）`resolvedUri` 維持原始 `content://` URI——這代表指紋計算**不能**假設一定拿得到真實檔案系統路徑，`Dart` 的 `dart:io` `File` 類別無法直接開啟 `content://` URI（沒有對應的真實檔案節點）。這是本計畫與 `issues.md`「What to build」字面描述（僅提到 `File.openRead()`）的落差，詳見下方「與 issues.md 的落差說明」。
- **串流計算，禁止一次性讀入整個檔案**：PRD 要求支援 100MB 以上檔案，本專案已有過同類全檔案讀入記憶體導致 OOM 閃退的真實事故（`epic-20` Issue 8，見 `spec.md`「書籍內容指紋計算」）。本機檔案路徑用 `File.openRead()` 串流；`content://` URI 委由原生端用固定緩衝區（8KB）串流計算，兩條路徑皆不得整段讀入記憶體。
- **本機檔案路徑的計算過程外包至 `Isolate.run()`**，避免大檔案雜湊運算阻塞 UI isolate；`content://` 路徑委由原生端 `Dispatchers.IO` 執行（比照 `BookMetadataChannel.kt` 既有 `extractPdfMetadata`／`listFolderContents` 的既定模式），Dart 端只是等待 `MethodChannel` 回應，不需要額外包 Isolate。
- **PDF／TXT 一律 SHA-256，不做抽樣頭尾雜湊**（spec.md 2026-08-03 Architecting 階段定案：正確性優先於一次性匯入成本的些微效能差異）。
- **計算失敗時降級為 `null`，不中斷整批匯入**：比照 `_importSingleFile()` 既有的 `extractMetadata` `on PlatformException` 降級慣例——`computeBookContentFingerprint()` 本身計算失敗時直接拋出例外（不吞錯誤），由呼叫端 `book_import_service_impl.dart` 決定降級。既有書籍升級後 `content_fingerprint` 為 `NULL` 是已知、預期的暫時狀態（該書尚未同步過），非本 Issue 負責回填（見 issues.md「既有書籍升級後...首次觸發同步時才補算回填」，回填時機由 Issue 4 決定）。

## 與 issues.md 的落差說明

`issues.md` Issue 3「What to build」原文只描述「`File.openRead()` 搭配 `package:crypto` 的 `sha256.startChunkedConversion()` 逐塊計算」，沒有提到 `content://` URI 的情況——但依 ADR 0002 與 `book_import_service_impl.dart` 現有程式碼（見上方 Global Constraints），這是實際匯入流程的常見情況，不是邊角案例。本計畫新增一個 `issues.md`／`spec.md` 皆未明確規劃的原生方法 `BookMetadataChannel.kt` 的 `computeSha256`，處理 `content://` 這條路徑；本機檔案路徑仍完全比照 `issues.md` 原文描述（`File.openRead()` + `package:crypto`，外包 `Isolate.run()`）。另外，`package:crypto` 的官方建議寫法是 `Hash.bind(stream).first`（見官方 `example/example.dart`），比手動 `startChunkedConversion()` + `AccumulatorSink` 更簡潔且效果相同（皆是逐塊處理、不緩衝整個串流），本計畫採用前者。

---

### Task 1：原生端——`extractEpubMetadata` 新增 `identifier`，新增 `computeSha256` 方法

**Files:**
- Modify：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`
- Create：`app/test/fixtures/sample_no_identifier.epub`（新 fixture，OPF `dc:identifier` 為空字串）

**Interfaces:**
- Consumes：無（本 Task 是整個 Issue 的地基，不依賴其他 Task）
- Produces：`extractMetadata`（既有方法）回應 map 新增 `"identifier": String?`（EPUB 專屬，PDF 呼叫時此鍵不存在，`cast` 結果自然為 `null`，比照既有 `isFixedLayout` 鍵的處理方式）；新增原生方法 `computeSha256`（參數 `{'uri': String}`，成功回傳 `String`——64 字元小寫十六進位 SHA-256 雜湊值；失敗以 `MethodChannel.Result.error("hash_failed", ...)` 回傳）。供 Task 2（`computeBookContentFingerprint`）與 Task 4（`integration_test`）使用。

- [ ] **Step 1：產生新 fixture `sample_no_identifier.epub`**

Run（於 `app/` 目錄下，需要 Python 3）：

```bash
python3 -c "
import struct
import zipfile
import zlib


def make_png(width, height, rgb):
    def chunk(tag, data):
        return (
            struct.pack('>I', len(data))
            + tag
            + data
            + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
        )

    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    raw = b''
    for _ in range(height):
        raw += b'\x00' + bytes(rgb) * width
    idat = zlib.compress(raw)
    return sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')


container_xml = '''<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">
  <rootfiles>
    <rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/>
  </rootfiles>
</container>
'''

# 與既有 sample.epub 生成腳本（epic-1-library Issue 2）同一套結構，唯一
# 差異是 dc:identifier 元素內容為空字串（見 epic-8-sync Issue 3
# spec.md「書籍內容指紋計算」「OPF identifier 為空/缺漏時」的『為空』
# 情境——unique-identifier 屬性仍指向這個元素本身，維持 EPUB3 規格要求
# 的參照有效性，只是內容本身是空的）。
content_opf = '''<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"pub-id\">
  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">
    <dc:identifier id=\"pub-id\"></dc:identifier>
    <dc:title>elinkBook 無指紋識別碼範例 EPUB</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property=\"dcterms:modified\">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>
    <item id=\"chapter1\" href=\"chapter1.xhtml\" media-type=\"application/xhtml+xml\"/>
    <item id=\"cover-img\" href=\"cover.png\" media-type=\"image/png\" properties=\"cover-image\"/>
  </manifest>
  <spine>
    <itemref idref=\"chapter1\"/>
  </spine>
</package>
'''

nav_xhtml = '''<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE html>
<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\">
<head><title>Nav</title></head>
<body>
  <nav epub:type=\"toc\"><ol><li><a href=\"chapter1.xhtml\">第一章</a></li></ol></nav>
</body>
</html>
'''

chapter1_xhtml = '''<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE html>
<html xmlns=\"http://www.w3.org/1999/xhtml\">
<head><title>第一章</title></head>
<body><p>測試內容。</p></body>
</html>
'''

cover_png = make_png(4, 4, (80, 120, 200))

with zipfile.ZipFile('test/fixtures/sample_no_identifier.epub', 'w') as z:
    z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip', zipfile.ZIP_STORED)
    z.writestr('META-INF/container.xml', container_xml, zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/content.opf', content_opf, zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/nav.xhtml', nav_xhtml, zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/chapter1.xhtml', chapter1_xhtml, zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/cover.png', cover_png, zipfile.ZIP_DEFLATED)

print('wrote sample_no_identifier.epub')
"
```

Expected：印出 `wrote sample_no_identifier.epub`，`app/test/fixtures/sample_no_identifier.epub` 已建立。

- [ ] **Step 2：`pubspec.yaml` 新增此 fixture 至 assets 清單**

`app/pubspec.yaml` 的 `assets:` 區塊、`- test/fixtures/sample.epub` 那一行之後新增：

```yaml
    - test/fixtures/sample_no_identifier.epub
```

- [ ] **Step 3：`extractEpubMetadata` 新增回傳 `identifier`**

`BookMetadataChannel.kt` 第 248-269 行（`extractEpubMetadata` 內 `try` 區塊）改為：

```kotlin
                try {
                    val title = publication.metadata.title
                    val author = publication.metadata.authors.firstOrNull()?.name
                    // epic-17-epub-render-migration Issue 2：免費多讀一個既有欄位——
                    // publication 本來就已經在這裡被建構，不需要新的解析路徑
                    // （見 docs/epics/epic-17-epub-render-migration/spec.md「模組」）。
                    val isFixedLayout = publication.metadata.layout == Layout.FIXED
                    // epic-8-sync Issue 3：同樣是免費多讀一個既有欄位，供
                    // computeBookContentFingerprint() 優先採用（見
                    // docs/epics/epic-8-sync/spec.md「書籍內容指紋計算」）。
                    // Readium Metadata.identifier 型別為 String?，缺漏時本來
                    // 就是 null，不需要額外處理。
                    val identifier = publication.metadata.identifier
                    // PNG 壓縮與封面退路的 I/O／解碼皆為耗時工作，移到背景執行緒避免
                    // 阻塞主執行緒；withContext 返回後會自動切回 scope 的 Main
                    // dispatcher。
                    val coverBytes = withContext(Dispatchers.IO) {
                        val bitmap = publication.cover() ?: findFallbackCoverBitmap(publication)
                        bitmap?.let { bitmapToPngBytes(it) }
                    }
                    result.success(
                        mapOf(
                            "title" to title,
                            "author" to author,
                            "coverBytes" to coverBytes,
                            "isFixedLayout" to isFixedLayout,
                            "identifier" to identifier,
                        ),
                    )
                } finally {
```

- [ ] **Step 4：新增 `computeSha256` 方法分派與實作**

`BookMetadataChannel.kt` 的 `onMethodCall` 內，`"detectEpubLayout" -> {...}` 區塊（第 95-102 行）之後新增：

```kotlin
            "computeSha256" -> {
                val path = call.argument<String>("uri")
                if (path == null) {
                    result.error("invalid_arguments", "缺少 uri 參數", null)
                    return
                }
                computeSha256(path, result)
            }
```

在 `extractPdfMetadata` 方法（第 327-387 行）之後新增：

```kotlin
    /**
     * 串流計算檔案內容的 SHA-256（epic-8-sync Issue 3，spec.md「書籍內容
     * 指紋計算」），供 [computeBookContentFingerprint]（Dart 端）處理
     * `content://` URI 使用——`dart:io` `File` 無法直接開啟 `content://`
     * URI，只能委由原生端透過 [openParcelFileDescriptor] 既有的
     * ContentResolver／檔案系統雙路徑開檔邏輯讀取。用固定 8KB 緩衝區
     * 逐塊餵入 MessageDigest，不論檔案多大都不會一次性讀入整個檔案
     * （PRD 要求支援 100MB 以上檔案）；只有最終的雜湊結果（64 字元十六
     * 進位字串）會透過 MethodChannel 回傳，不傳輸原始位元組。
     */
    private fun computeSha256(path: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                val hex = withContext(Dispatchers.IO) {
                    val pfd = openParcelFileDescriptor(path)
                        ?: throw java.io.IOException("找不到檔案或檔案已損毀：$path")
                    pfd.use {
                        ParcelFileDescriptor.AutoCloseInputStream(it).use { input ->
                            val digest = java.security.MessageDigest.getInstance("SHA-256")
                            val buffer = ByteArray(8192)
                            while (true) {
                                val read = input.read(buffer)
                                if (read == -1) break
                                digest.update(buffer, 0, read)
                            }
                            digest.digest().joinToString("") { b -> "%02x".format(b) }
                        }
                    }
                }
                result.success(hex)
            } catch (e: Exception) {
                result.error(
                    "hash_failed",
                    "計算檔案雜湊時發生未預期的錯誤：${e.message}",
                    null,
                )
            }
        }
    }
```

- [ ] **Step 5：確認 Kotlin 變更編譯成功**

Run：

```bash
cd app
flutter build apk --debug
```

Expected：建置成功（無編譯錯誤）。這一步只確認 Kotlin 語法/型別正確，`computeSha256`／`identifier` 的實際行為正確性由 Task 4 的 `integration_test`（真機）驗證——`flutter test` 無法執行原生 Kotlin 程式碼。

- [ ] **Step 6：Commit**

```bash
git add android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt test/fixtures/sample_no_identifier.epub pubspec.yaml
git commit -m "feat(epic-8-sync): Issue 3 Task 1 — BookMetadataChannel 新增 identifier 回傳與 computeSha256 方法"
```

---

### Task 2：`computeBookContentFingerprint()` 純函式

**Files:**
- Create：`app/lib/library/book_content_fingerprint.dart`
- Test：`app/test/library/book_content_fingerprint_test.dart`
- Modify：`app/pubspec.yaml`（新增 `crypto` 依賴）

**Interfaces:**
- Consumes：Task 1 的 `computeSha256` 原生方法（`content://` URI 情況）；`kBookMetadataChannel`（`app/lib/library/library_repository.dart` 既有常數）。
- Produces：`Future<String> computeBookContentFingerprint(String filePath, BookFileFormat format, {String? epubIdentifier})`——`filePath` 為本機路徑或 `content://` URI；`epubIdentifier` 由呼叫端（Task 3）從既有 `extractMetadata` 回應一併取得後傳入，非空時直接採用；計算失敗時拋出例外（不吞錯誤）。供 Task 3（`book_import_service_impl.dart`）使用。

- [ ] **Step 1：新增 `crypto` 依賴**

`app/pubspec.yaml` 第 49-56 行（`dependencies:` 區塊內，緊接 Issue 1 新增的 `uuid` 之後）改為：

```yaml
  uuid: ^4.6.0
  crypto: ^3.0.7
```

```bash
cd app
flutter pub get
```

Expected：`crypto` 成功加入 `pubspec.lock`。

- [ ] **Step 2：撰寫失敗測試**

Create `app/test/library/book_content_fingerprint_test.dart`：

```dart
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:elinkbook/library/book_content_fingerprint.dart';
import 'package:elinkbook/library/library_repository.dart';
import 'package:elinkbook/library/models/library_enums.dart';

void main() {
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kBookMetadataChannel, null);
  });

  group('EPUB：OPF identifier 優先', () {
    test('epubIdentifier 非空時，直接回傳該值，不計算 SHA-256', () async {
      final result = await computeBookContentFingerprint(
        'test/fixtures/sample.epub',
        BookFileFormat.epub,
        epubIdentifier: 'urn:uuid:00000000-0000-0000-0000-000000000001',
      );

      expect(result, 'urn:uuid:00000000-0000-0000-0000-000000000001');
    });

    test('epubIdentifier 為 null 時，退回計算整份檔案的 SHA-256', () async {
      final fileBytes = await File('test/fixtures/sample.epub').readAsBytes();
      final expected = sha256.convert(fileBytes).toString();

      final result = await computeBookContentFingerprint(
        'test/fixtures/sample.epub',
        BookFileFormat.epub,
      );

      expect(result, expected);
    });

    test('epubIdentifier 為空字串時，同樣退回計算 SHA-256（OPF identifier 元素存在但內容為空）',
        () async {
      final fileBytes = await File('test/fixtures/sample.epub').readAsBytes();
      final expected = sha256.convert(fileBytes).toString();

      final result = await computeBookContentFingerprint(
        'test/fixtures/sample.epub',
        BookFileFormat.epub,
        epubIdentifier: '',
      );

      expect(result, expected);
    });

    test('epubIdentifier 為純空白字串時，視同缺漏，退回計算 SHA-256（不規範 EPUB 防禦）',
        () async {
      final fileBytes = await File('test/fixtures/sample.epub').readAsBytes();
      final expected = sha256.convert(fileBytes).toString();

      final result = await computeBookContentFingerprint(
        'test/fixtures/sample.epub',
        BookFileFormat.epub,
        epubIdentifier: '   ',
      );

      expect(result, expected);
    });

    test('epubIdentifier 前後夾帶空白時，回傳修剪後的值', () async {
      final result = await computeBookContentFingerprint(
        'test/fixtures/sample.epub',
        BookFileFormat.epub,
        epubIdentifier: '  urn:uuid:00000000-0000-0000-0000-000000000001  ',
      );

      expect(result, 'urn:uuid:00000000-0000-0000-0000-000000000001');
    });
  });

  group('PDF／TXT：一律 SHA-256', () {
    test('PDF 檔案計算結果與獨立計算的參考雜湊值一致', () async {
      final fileBytes = await File('test/fixtures/sample.pdf').readAsBytes();
      final expected = sha256.convert(fileBytes).toString();

      final result = await computeBookContentFingerprint(
        'test/fixtures/sample.pdf',
        BookFileFormat.pdf,
      );

      expect(result, expected);
    });

    test('同一檔案計算兩次，結果一致（確定性）', () async {
      final result1 = await computeBookContentFingerprint(
        'test/fixtures/sample.pdf',
        BookFileFormat.pdf,
      );
      final result2 = await computeBookContentFingerprint(
        'test/fixtures/sample.pdf',
        BookFileFormat.pdf,
      );

      expect(result1, result2);
    });

    test('大檔案（>10MB）以串流方式計算，結果與獨立計算的參考雜湊值一致', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('fingerprint_large_file_test');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File(p.join(tempDir.path, 'large.pdf'));

      final sink = file.openWrite();
      final chunk = List<int>.generate(1024 * 1024, (i) => i % 256); // 1MB
      for (var i = 0; i < 15; i++) {
        sink.add(chunk);
      }
      await sink.close();

      final expected = sha256.convert(await file.readAsBytes()).toString();

      final result =
          await computeBookContentFingerprint(file.path, BookFileFormat.pdf);

      expect(result, expected);
    });
  });

  group('content:// URI：委由原生端 computeSha256', () {
    test('filePath 為 content:// URI 時，呼叫原生 computeSha256 並回傳其結果', () async {
      String? capturedMethod;
      Map? capturedArgs;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kBookMetadataChannel, (call) async {
        capturedMethod = call.method;
        capturedArgs = call.arguments as Map;
        return 'abc123deadbeef';
      });

      final result = await computeBookContentFingerprint(
        'content://example/book.pdf',
        BookFileFormat.pdf,
      );

      expect(result, 'abc123deadbeef');
      expect(capturedMethod, 'computeSha256');
      expect(capturedArgs?['uri'], 'content://example/book.pdf');
    });

    test('EPUB 且 epubIdentifier 非空時，即使 filePath 是 content:// 也不呼叫原生 computeSha256',
        () async {
      var computeSha256Called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kBookMetadataChannel, (call) async {
        if (call.method == 'computeSha256') computeSha256Called = true;
        return null;
      });

      final result = await computeBookContentFingerprint(
        'content://example/book.epub',
        BookFileFormat.epub,
        epubIdentifier: 'urn:isbn:9780000000000',
      );

      expect(result, 'urn:isbn:9780000000000');
      expect(computeSha256Called, isFalse);
    });

    test('原生 computeSha256 回傳 null 時，視為計算失敗並拋出例外', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kBookMetadataChannel, (call) async => null);

      await expectLater(
        () => computeBookContentFingerprint(
          'content://example/book.pdf',
          BookFileFormat.pdf,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
```

- [ ] **Step 3：執行測試，確認因函式不存在而失敗**

Run：

```bash
flutter test test/library/book_content_fingerprint_test.dart
```

Expected：FAIL，錯誤訊息指出找不到 `package:elinkbook/library/book_content_fingerprint.dart`（或找不到 `computeBookContentFingerprint`）。

- [ ] **Step 4：實作 `computeBookContentFingerprint`**

Create `app/lib/library/book_content_fingerprint.dart`：

```dart
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'library_repository.dart';
import 'models/library_enums.dart';

/// 計算書籍內容指紋（epic-8-sync Issue 3，spec.md「書籍內容指紋計算」／
/// 「跨裝置參照設計」）：供跨裝置比對「這是不是同一本書」使用，寫入
/// `books.content_fingerprint`。EPUB 優先採用 OPF identifier（由呼叫端
/// 透過既有 `extractMetadata` 呼叫一併取得並以 [epubIdentifier] 傳入，
/// 本函式不重複發出原生呼叫，取用前先 `trim()`——不規範的 EPUB 檔若在
/// `<dc:identifier>` 塞入純空白字串，不應被當成有效指紋值，見文末
/// 「審查修正紀錄」）；identifier 缺漏（`null`）、trim 後為空字串，
/// 以及 PDF／TXT 一律採用整個檔案內容的 SHA-256。
///
/// [filePath] 依 ADR 0002 可能是本機檔案系統路徑，也可能是 `content://`
/// URI——`dart:io` 的 `File` 無法直接開啟 `content://` URI（沒有對應的
/// 真實檔案系統節點），這種情況委由原生端的 `computeSha256`
/// （`BookMetadataChannel.kt`）以 `ContentResolver` 串流計算，計算過程
/// 與原始位元組皆不經過 Dart 端記憶體，只有最終的雜湊字串透過
/// `MethodChannel` 回傳。本機檔案路徑則在 Dart 端用 `File.openRead()`
/// 串流＋`package:crypto` 的 `Hash.bind()`（官方建議寫法，見
/// `package:crypto` `example/example.dart`），並外包至 `Isolate.run()`
/// 執行，避免大檔案（PRD 要求支援 100MB 以上）阻塞 UI isolate、也避免
/// 一次性讀入整個檔案（本專案已有過同類全檔案讀入記憶體導致 OOM 閃退的
/// 真實事故，見 `epic-20` Issue 8）。
///
/// 計算失敗（檔案不存在／原生端拋出例外／`computeSha256` 未回傳有效值）
/// 時直接拋出例外，由呼叫端（`book_import_service_impl.dart`）決定是否
/// 降級為 `null`，本函式本身不吞掉錯誤。
Future<String> computeBookContentFingerprint(
  String filePath,
  BookFileFormat format, {
  String? epubIdentifier,
}) async {
  final trimmedIdentifier = epubIdentifier?.trim();
  if (format == BookFileFormat.epub &&
      trimmedIdentifier != null &&
      trimmedIdentifier.isNotEmpty) {
    return trimmedIdentifier;
  }
  if (filePath.contains('://')) {
    final hash = await kBookMetadataChannel
        .invokeMethod<String>('computeSha256', {'uri': filePath});
    if (hash == null) {
      throw StateError('computeSha256 未回傳有效的雜湊值：$filePath');
    }
    return hash;
  }
  return Isolate.run(() => _sha256OfLocalFile(filePath));
}

Future<String> _sha256OfLocalFile(String filePath) async {
  final digest = await sha256.bind(File(filePath).openRead()).first;
  return digest.toString();
}
```

- [ ] **Step 5：執行測試，確認全數通過**

Run：

```bash
flutter test test/library/book_content_fingerprint_test.dart
```

Expected：PASS（11 個測試全數通過）。

- [ ] **Step 6：`flutter analyze` + Commit**

```bash
flutter analyze
git add pubspec.yaml pubspec.lock lib/library/book_content_fingerprint.dart test/library/book_content_fingerprint_test.dart
git commit -m "feat(epic-8-sync): Issue 3 Task 2 — computeBookContentFingerprint 純函式"
```

Expected：`flutter analyze` 顯示 "No issues found!"。

---

### Task 3：`Book` 模型新增欄位 + 匯入流程串接

**Files:**
- Modify：`app/lib/library/models/book.dart`
- Modify：`app/lib/library/book_import_service_impl.dart`
- Test：`app/test/library/models/book_test.dart`
- Test：`app/test/library/book_import_service_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `computeBookContentFingerprint(String filePath, BookFileFormat format, {String? epubIdentifier})`。
- Produces：`Book.contentFingerprint`（`String?`，`toMap()`/`fromMap()` 鍵為 `content_fingerprint`，對應 Issue 1 已建立的同名 SQLite 欄位）。`_importSingleFile()` 匯入時正確計算並寫入。

- [ ] **Step 1：撰寫失敗測試——`book_test.dart` 新增 `contentFingerprint` 案例**

`app/test/library/models/book_test.dart` 檔案結尾（最後一個 `test(...)` 之後、檔案結尾 `}` 之前）新增：

```dart

  test('contentFingerprint 欄位可正確往返（epic-8-sync Issue 3）', () {
    final book = Book(
      id: 'b13',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://com.example/book.epub',
      source: BookSource.local,
      contentFingerprint: 'urn:uuid:00000000-0000-0000-0000-000000000001',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.contentFingerprint,
        'urn:uuid:00000000-0000-0000-0000-000000000001');
  });

  test('contentFingerprint 未設定時，往返後仍為 null（代表尚未計算過指紋）', () {
    final book = Book(
      id: 'b14',
      title: '書名',
      format: BookFileFormat.pdf,
      filePath: '/storage/emulated/0/book.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.contentFingerprint, isNull);
  });
```

- [ ] **Step 2：執行測試，確認因欄位不存在而失敗**

Run：

```bash
flutter test test/library/models/book_test.dart
```

Expected：FAIL，編譯錯誤指出 `Book` 建構子沒有 `contentFingerprint` 具名參數。

- [ ] **Step 3：`Book` 模型新增 `contentFingerprint` 欄位**

`app/lib/library/models/book.dart` 第 50-72 行（`isFixedLayout` 欄位宣告之後、建構子）改為：

```dart
  final bool? isFixedLayout;

  /// 書籍內容指紋（epic-8-sync Issue 3，spec.md「書籍內容指紋計算」／
  /// 「跨裝置參照設計」）：EPUB 優先為 OPF identifier，缺漏或 PDF/TXT
  /// 為整份檔案內容的 SHA-256，供同步引擎跨裝置比對「這是不是同一本
  /// 書」使用（不攜帶本機 [id]，見 spec.md）。`null` 代表尚未計算過
  /// （既有書籍升級後的暫時狀態，或本次匯入計算失敗），該書在補算前
  /// 不參與跨裝置比對，不影響單機使用。
  final String? contentFingerprint;

  final String groupName;
  final DateTime createTime;
  final DateTime lastReadTime;

  const Book({
    required this.id,
    required this.title,
    this.author,
    required this.format,
    required this.filePath,
    required this.source,
    this.coverPath,
    this.progress = 0,
    this.epubLocator,
    this.pdfPageIndex,
    this.totalCharacterCount,
    this.isFixedLayout,
    this.contentFingerprint,
    this.groupName = BookGroup.uncategorized,
    required this.createTime,
    required this.lastReadTime,
  });
```

`toMap()`（第 74-95 行）的 `is_fixed_layout` 那一行之後新增一個鍵：

```dart
      'is_fixed_layout':
          isFixedLayout == null ? null : (isFixedLayout! ? 1 : 0),
      'content_fingerprint': contentFingerprint,
      'groupName': groupName,
```

`Book.fromMap()`（第 97-118 行）的 `isFixedLayout:` 那一行之後新增：

```dart
      isFixedLayout: map['is_fixed_layout'] == null
          ? null
          : (map['is_fixed_layout'] as int) == 1,
      contentFingerprint: map['content_fingerprint'] as String?,
      groupName: map['groupName'] as String,
```

`operator ==`（第 143-163 行）的 `isFixedLayout == other.isFixedLayout &&` 那一行之後新增：

```dart
          isFixedLayout == other.isFixedLayout &&
          contentFingerprint == other.contentFingerprint &&
          groupName == other.groupName &&
```

`hashCode`（第 164-182 行）的 `isFixedLayout,` 那一行之後新增：

```dart
        isFixedLayout,
        contentFingerprint,
        groupName,
```

（`copyWith()` 刻意不新增 `contentFingerprint` 參數——本 Issue 只需要匯入當下透過建構子一次指派，沒有「事後改寫既有 `Book` 物件的這個欄位」的呼叫端，YAGNI；既有欄位如 `author`/`coverPath`/`progression` 等同樣不在 `copyWith()` 內，是既有慣例而非本次遺漏。若 Issue 4 的補算回填流程需要，屆時再新增。）

- [ ] **Step 4：執行測試，確認通過**

Run：

```bash
flutter test test/library/models/book_test.dart
```

Expected：PASS（12 個測試全數通過）。

- [ ] **Step 5：撰寫失敗測試——`book_import_service_test.dart` 新增指紋案例**

`app/test/library/book_import_service_test.dart` 檔案結尾（最後一個 `test(...)` 之後、`});`／`}` 之前，比照既有測試的縮排層級）新增：

```dart

  group('content_fingerprint（epic-8-sync Issue 3）', () {
    test('EPUB 匯入時，extractMetadata 回傳的 identifier 優先寫入 content_fingerprint，不呼叫 computeSha256',
        () async {
      var computeSha256Called = false;
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {
            'title': '書名',
            'author': null,
            'coverBytes': null,
            'identifier': 'urn:uuid:00000000-0000-0000-0000-000000000099',
          };
        }
        if (call.method == 'computeSha256') {
          computeSha256Called = true;
          return 'should-not-be-used';
        }
        return null;
      });

      final result = await service.importFiles(['content://example/book.epub']);

      expect(result.importedBooks.single.contentFingerprint,
          'urn:uuid:00000000-0000-0000-0000-000000000099');
      expect(computeSha256Called, isFalse);
    });

    test('EPUB 匯入時，identifier 缺漏則呼叫 computeSha256，結果寫入 content_fingerprint',
        () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '書名', 'author': null, 'coverBytes': null};
        }
        if (call.method == 'computeSha256') {
          expect((call.arguments as Map)['uri'], 'content://example/book2.epub');
          return 'fallback-hash-abc';
        }
        return null;
      });

      final result =
          await service.importFiles(['content://example/book2.epub']);

      expect(
          result.importedBooks.single.contentFingerprint, 'fallback-hash-abc');
    });

    test('PDF 匯入時，呼叫 computeSha256 並寫入 content_fingerprint', () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': null, 'author': null, 'coverBytes': null};
        }
        if (call.method == 'computeSha256') return 'pdf-hash-xyz';
        return null;
      });

      final result = await service.importFiles(['content://example/report.pdf']);

      expect(result.importedBooks.single.contentFingerprint, 'pdf-hash-xyz');
    });

    test('TXT 匯入時，呼叫 computeSha256 並寫入 content_fingerprint', () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'computeSha256') return 'txt-hash-123';
        return null;
      });

      final result = await service.importFiles(['content://example/notes.txt']);

      expect(result.importedBooks.single.contentFingerprint, 'txt-hash-123');
    });

    test('computeSha256 失敗（回傳 null）時，content_fingerprint 降級為 null，不中斷匯入',
        () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': '書名', 'author': null, 'coverBytes': null};
        }
        return null; // computeSha256 未被特別處理，落到這裡回傳 null
      });

      final result = await service.importFiles(['content://example/book3.epub']);

      expect(result.importedBooks, hasLength(1));
      expect(result.importedBooks.single.contentFingerprint, isNull);
    });

    test('extractMetadata 拋出例外時，content_fingerprint 仍嘗試計算（兩者互相獨立）',
        () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          throw PlatformException(code: 'extraction_failed', message: '模擬失敗');
        }
        if (call.method == 'computeSha256') return 'still-computed-hash';
        return null;
      });

      final result = await service.importFiles(['content://example/book4.epub']);

      expect(result.importedBooks.single.title, 'book4');
      expect(result.importedBooks.single.contentFingerprint,
          'still-computed-hash');
    });
  });
```

- [ ] **Step 6：執行測試，確認因未串接而失敗**

Run：

```bash
flutter test test/library/book_import_service_test.dart
```

Expected：FAIL——新增的 6 個測試中，斷言 `contentFingerprint` 非 `null`／等於特定值的案例會失敗（目前 `_importSingleFile()` 尚未計算指紋，`Book` 建構時 `contentFingerprint` 恆為預設值 `null`）。

- [ ] **Step 7：`book_import_service_impl.dart` 串接指紋計算**

第 1-12 行 import 區塊新增：

```dart
import 'book_content_fingerprint.dart';
```

第 176-284 行（`_importSingleFile` 方法本體）改為：

```dart
  Future<Book?> _importSingleFile(
    String uri, {
    String? displayName,
    String? folderName,
    bool takePermission = true,
  }) async {
    final format =
        (displayName != null ? detectBookFileFormat(displayName) : null) ??
            detectBookFileFormat(uri);
    if (format == null) return null;

    final id = '${DateTime.now().microsecondsSinceEpoch}-${uri.hashCode}';

    var resolvedUri = uri;
    if (takePermission && uri.startsWith('content://')) {
      var permissionGranted = true;
      try {
        await kBookMetadataChannel.invokeMethod<void>(
          'takePersistableUriPermission',
          {'uri': uri},
        );
      } on PlatformException {
        permissionGranted = false;
      }
      if (!permissionGranted || detectBookFileFormat(uri) == null) {
        final localPath = await _copyToLocalStorage(uri, id, format);
        if (localPath == null) return null;
        resolvedUri = localPath;
      }
    }

    final fallbackTitle = titleFromFileName(displayName ?? uri);
    final now = DateTime.now();

    var title = fallbackTitle;
    String? author;
    String? coverPath;
    bool? isFixedLayout;
    String? epubIdentifier;

    if (format == BookFileFormat.txt) {
      final coverBytes = await generateTxtCover(fallbackTitle);
      coverPath = await _landCover(coverBytes, id);
    } else {
      try {
        final metadata = await kBookMetadataChannel.invokeMapMethod<String, Object?>(
          'extractMetadata',
          {'uri': resolvedUri, 'format': format.name},
        );
        final extractedTitle = metadata?['title'] as String?;
        if (extractedTitle != null && extractedTitle.isNotEmpty) {
          title = extractedTitle;
        }
        author = metadata?['author'] as String?;
        // PDF 的 extractMetadata 回傳 map 沒有這個鍵，cast 結果自然為 null，
        // 不需要另外依 format 分支判斷（見
        // docs/epics/epic-17-epub-render-migration/spec.md「模組」）。
        isFixedLayout = metadata?['isFixedLayout'] as bool?;
        // epic-8-sync Issue 3：同一次 extractMetadata 回應一併取得，PDF
        // 呼叫時這個鍵不存在，cast 結果自然為 null，不需要另外依 format
        // 分支判斷（比照 isFixedLayout 既有處理方式）。
        epubIdentifier = metadata?['identifier'] as String?;
        final coverBytes = metadata?['coverBytes'] as Uint8List?;
        if (coverBytes != null) {
          coverPath = await _landCover(coverBytes, id);
        }
      } on PlatformException {
        // 詮釋資料提取失敗：降級為「檔名為標題、無封面」，不中斷整批匯入。
        // 指紋計算與詮釋資料提取彼此獨立（見下方），此處失敗不影響指紋
        // 計算仍會嘗試執行。
      }
    }

    String? contentFingerprint;
    try {
      contentFingerprint = await computeBookContentFingerprint(
        resolvedUri,
        format,
        epubIdentifier: epubIdentifier,
      );
    } catch (_) {
      // 指紋計算失敗（原生端例外／檔案讀取失敗）：降級為 null，不中斷
      // 整批匯入——這本書在補算前不參與跨裝置比對，比照 epic-17
      // detectAndCacheEpubLayout() 的一次性補判斷模式（回填時機留待
      // Issue 4 決定，見 issues.md）。
    }

    final book = Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: resolvedUri,
      source: BookSource.local,
      coverPath: coverPath,
      isFixedLayout: isFixedLayout,
      contentFingerprint: contentFingerprint,
      groupName: folderName ?? BookGroup.uncategorized,
      createTime: now,
      lastReadTime: now,
    );

    return _repository.insertBook(book);
  }
```

（本次取代**保留**原第 176-232 行對 `format`／`resolvedUri` 判斷邏輯既有的全部中文註解說明——上方僅為節省篇幅省略未變動的註解區塊，實作時請維持原檔案這段既有註解，只新增/修改上述明確標示的部分：`epubIdentifier` 宣告與擷取、指紋計算區塊、`Book(...)` 新增 `contentFingerprint:` 參數。）

- [ ] **Step 8：執行測試，確認全數通過**

Run：

```bash
flutter test test/library/book_import_service_test.dart
```

Expected：PASS（全部既有＋新增測試通過）。

- [ ] **Step 9：`flutter analyze` + 執行完整測試套件 + Commit**

```bash
flutter analyze
flutter test
```

Expected：`flutter analyze` "No issues found!"，`flutter test` 全數 PASS（確認無 regression）。

```bash
git add lib/library/models/book.dart lib/library/book_import_service_impl.dart test/library/models/book_test.dart test/library/book_import_service_test.dart
git commit -m "feat(epic-8-sync): Issue 3 Task 3 — Book.contentFingerprint 欄位與匯入流程串接"
```

---

### Task 4：`integration_test`——原生端 `identifier`／`computeSha256` 真機驗證

**Files:**
- Modify：`app/integration_test/book_metadata_channel_test.dart`

**Interfaces:**
- Consumes：Task 1 的原生方法（`extractMetadata` 新增 `identifier` 欄位、新增 `computeSha256` 方法）。

- [ ] **Step 1：撰寫真機測試**

`app/integration_test/book_metadata_channel_test.dart` 檔案結尾（最後一個 `testWidgets(...)` 之後、檔案結尾 `}` 之前）新增：

```dart

  // epic-8-sync Issue 3：extractMetadata 新增回傳 identifier、新增
  // computeSha256 方法，皆無法透過 flutter test 驗證（需要真實原生端
  // 執行），比照本檔案既有慣例於此驗證。
  testWidgets('EPUB 有 OPF identifier 時，extractMetadata 正確回傳', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample_id.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final result = await _channel.invokeMapMethod<String, Object?>(
      'extractMetadata',
      {'uri': samplePath, 'format': 'epub'},
    );

    expect(result, isNotNull);
    expect(result!['identifier'], 'urn:uuid:00000000-0000-0000-0000-000000000001');
  });

  testWidgets('EPUB 的 OPF identifier 為空字串時，extractMetadata 回傳空字串（非 null、非拋例外）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_no_identifier.epub', 'sample_no_id.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final result = await _channel.invokeMapMethod<String, Object?>(
      'extractMetadata',
      {'uri': samplePath, 'format': 'epub'},
    );

    expect(result, isNotNull);
    expect(result!['identifier'], '');
  });

  testWidgets('PDF 呼叫 extractMetadata 時，回應 map 沒有 identifier 鍵', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample_id.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final result = await _channel.invokeMapMethod<String, Object?>(
      'extractMetadata',
      {'uri': samplePath, 'format': 'pdf'},
    );

    expect(result, isNotNull);
    expect(result!.containsKey('identifier'), isFalse);
  });

  testWidgets('computeSha256 對本機檔案路徑計算結果與獨立計算的參考雜湊值一致',
      (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample_hash.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final expected =
        sha256.convert(await File(samplePath).readAsBytes()).toString();

    final result = await _channel.invokeMethod<String>(
      'computeSha256',
      {'uri': samplePath},
    );

    expect(result, expected);
  });

  testWidgets('computeSha256 對真正的 content:// URI 計算結果與本機路徑計算結果一致',
      (tester) async {
    // createTestContentUri 僅供 integration_test 使用（見該原生方法註解），
    // 把裝置上真實檔案路徑轉為 content:// URI，模擬 SAF 回傳的路徑型態。
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample_hash_uri.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final contentUri = await _channel.invokeMethod<String>(
      'createTestContentUri',
      {'path': samplePath},
    );
    expect(contentUri, isNotNull);
    expect(contentUri!.startsWith('content://'), isTrue);

    final expectedFromPath = await _channel.invokeMethod<String>(
      'computeSha256',
      {'uri': samplePath},
    );
    final resultFromContentUri = await _channel.invokeMethod<String>(
      'computeSha256',
      {'uri': contentUri},
    );

    expect(resultFromContentUri, expectedFromPath);
  });

  testWidgets('computeSha256 對不存在的檔案路徑拋出 PlatformException', (tester) async {
    final missingPath =
        '/data/local/tmp/does_not_exist_hash_${DateTime.now().millisecondsSinceEpoch}.pdf';

    await expectLater(
      () => _channel.invokeMethod<String>('computeSha256', {'uri': missingPath}),
      throwsA(isA<PlatformException>()),
    );
  });
```

第 1-6 行 import 區塊新增：

```dart
import 'package:crypto/crypto.dart';
```

- [ ] **Step 2：於真實裝置/模擬器上執行，確認全數通過**

Run：

```bash
flutter devices
flutter test integration_test/book_metadata_channel_test.dart -d <device-id>
```

Expected：PASS（既有測試＋本次新增 6 則皆通過）——這代表 `identifier`（含空字串情況）與 `computeSha256`（本機路徑／`content://` URI 兩種來源結果一致、失敗情況正確拋例外）在真實 Android 原生環境下行為正確。

- [ ] **Step 3：Commit**

```bash
git add integration_test/book_metadata_channel_test.dart
git commit -m "test(epic-8-sync): Issue 3 Task 4 — BookMetadataChannel identifier／computeSha256 真機驗證"
```

---

## Self-Review Notes

- **spec.md／issues.md 覆蓋檢查**：EPUB OPF identifier 優先、缺漏退回 SHA-256 → Task 1（原生擷取）＋ Task 2（優先順序邏輯，Step 2 前三個 group）。PDF／TXT 一律 SHA-256 → Task 2 「PDF／TXT」group。串流計算＋不得一次性讀入 → Task 2 實作（`File.openRead()`／原生 8KB 緩衝區）。獨立 Isolate 執行 → Task 2 `Isolate.run()`（本機路徑；`content://` 路徑委由原生 `Dispatchers.IO`，理由見 Global Constraints）。確定性（同檔案兩次結果一致）→ Task 2 對應測試。大檔案（>10MB）驗證串流路徑 → Task 2 對應測試（測試時動態產生 15MB 暫存檔，不提交進版控）。匯入流程正確寫入 `content_fingerprint` → Task 3。既有書籍升級後為 `NULL`、回填時機留給 Issue 4 → 本 Issue 不做任何主動回填，`Book.contentFingerprint` 預設 `null`（Task 3 Step 3），符合此定案。
- **與既有專案慣例的差異說明**：`content://` URI 需要新增原生 `computeSha256` 方法，是本計畫查證 `issues.md` 原文遺漏後的必要修正（見文件開頭「與 issues.md 的落差說明」），非本計畫自創的範圍蔓延——`ADR 0002`／`book_import_service_impl.dart` 現有程式碼皆已明確顯示這是常見（非邊角）情況。
- **測試涵蓋範圍的誠實記錄**：Task 2「串流、不緩衝整個檔案」這個屬性本身無法透過 `flutter test` 直接斷言記憶體用量；改為兩層驗證：(a) 型別層面——`sha256.bind()` 要求 `Stream<List<int>>` 引數，與 `readAsBytes()` 回傳的 `Future<Uint8List>` 型別不相容，若誤用會直接編譯失敗；(b) 大檔案（15MB）end-to-end 正確性測試，確認真的能處理超過既有 fixture 規模的檔案而不逾時/崩潰。這不是「假裝測試了記憶體用量」，是誠實記錄測試邊界（比照本 Epic 前幾個 Issue 計畫的既有慣例，例如 `plan-issue-1.md` 對 `conflictAlgorithm.ignore` 防禦查詢的查證誠實記錄）。
- **Placeholder 掃描**：全文無 TBD/TODO；Task 3 Step 7 因既有函式本體較長，明確註記「取代保留原有未變動註解區塊、僅新增標示部分」並非模糊帶過（已列出全部需要新增/修改的確切程式碼），比照 `plan-issue-1.md` Task 5「編譯器導引窮舉」先例的說明風格。
- **型別一致性檢查**：`computeBookContentFingerprint(String, BookFileFormat, {String? epubIdentifier})`（Task 2 定義）→ Task 3 `_importSingleFile()` 呼叫時的引數型別與具名參數完全一致；`Book.contentFingerprint`（`String?`，Task 3）與 `computeBookContentFingerprint` 回傳型別 `Future<String>`／降級後的 `null` 皆相容；`BookMetadataChannel.kt` 的 `computeSha256` 回傳型別（`String`，Task 1）與 Dart 端 `invokeMethod<String>`（Task 2）一致。

## 審查修正紀錄（`tmp/epic-8/review-plan-issue-3.md`）

程式碼審查（`/superpowers:requesting-code-review`，2026-08-03）結論「Ready to Execute」，0 Critical/Important，附帶 2 項微幅改善建議：

- **建議 1「`epubIdentifier` 空白字串防禦」，確認屬實，已採納**：原判定邏輯 `epubIdentifier.isNotEmpty` 對純空白字串（例如 `"   "`）會判定為 `true`，把未正規化的空白字串當成有效指紋值——不規範的 EPUB 檔案在 `<dc:identifier>` 塞入空白內容是真實可能發生的情況（比照本計畫已處理的「空字串」情境同一類問題）。已於 Task 2 `computeBookContentFingerprint()` 加入 `epubIdentifier?.trim()`，判定與回傳皆改用修剪後的值；新增 2 則測試（純空白字串視同缺漏退回 SHA-256、前後夾帶空白時回傳修剪後的值），Task 2 測試總數由 9 則增為 11 則。
- **建議 2「Issue 4 `Book.copyWith` 前瞻提醒」，確認屬實，無需在本計畫採取行動**：審查明確指出這只是提醒，Issue 3 現有設計（`copyWith()` 不含 `contentFingerprint`，YAGNI）已足夠，屆時由 Issue 4 的回填流程計畫視需要自行補上。本計畫不預先新增未使用的 `copyWith` 參數。
