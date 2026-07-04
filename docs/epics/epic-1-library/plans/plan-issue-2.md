# Issue 2 實作計劃：原生 `book_metadata` MethodChannel（EPUB/PDF 詮釋資料+封面提取）

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 新增原生 Android `MethodChannel`（`elinkbook/book_metadata`），實作 `extractMetadata(uri, format) -> { title, author, coverBytes }`：EPUB 用 Readium `Publication` API 讀取標題與封面圖，PDF 用 `PdfRenderer` 渲染第 1 頁當封面。此 channel 供圖書庫匯入流程（Issue 4）一次性呼叫，與既有 `openBook`/`onPageRendered`/`onError`（`PlatformView` 渲染契約）分開、獨立呼叫，用 `integration_test` 在真實裝置上驗證。

**架構：** 新增一個不綁定任何 `PlatformView` 實例的獨立 `MethodChannel`（`elinkbook/book_metadata`），在 `MainActivity.configureFlutterEngine()` 中註冊一次，供整個 App 生命週期共用。EPUB 提取重用 `EpubReaderView.kt` 已驗證可行的 Readium 開書流程（`AssetRetriever` → `DefaultPublicationParser` → `PublicationOpener`），額外讀取 `publication.metadata.title`/`publication.metadata.authors`，並呼叫 Readium 內建的 `publication.cover()` 取得封面點陣圖；PDF 提取重用 `PdfReaderView.kt` 已驗證可行的 `PdfRenderer` 渲染邏輯取得封面點陣圖。兩者的封面點陣圖皆編碼為 PNG bytes 回傳給 Flutter。

**技術棧：** Kotlin、Readium `readium-shared`/`readium-streamer` 3.3.0（已是專案既有依賴）、`android.graphics.pdf.PdfRenderer`、Flutter `MethodChannel`、`integration_test`。

## ⚠️ 執行前環境確認事項

本計劃的 Task 2 全數步驟須在真實 Android 模擬器/裝置上執行才能驗證——執行前請先確認 `flutter devices` 能列出至少一個 Android 裝置/模擬器（`adb devices` 顯示已連線），否則 Task 2 的驗證步驟無法通過。Task 1（重新產生 fixture）不需要裝置，可在任何環境執行。

## 全域限制條件

- Flutter 專案位於 `app/`，Android 應用程式 ID 為 `cc.ugotit.elinkbook`。
- Readium 版本固定為 `3.3.0`（`app/android/app/build.gradle.kts` 已釘選，不可變動）；本工單使用的 API（`AssetRetriever.retrieve(File, ...)`、`Metadata.title`、`Contributor.name`、`Publication.cover()`）皆已對照本機 Gradle 快取的 `readium-shared-3.3.0-api.jar` 位元組碼簽章確認存在，可直接使用。
- `extractMetadata` 的 channel 名稱固定為 `elinkbook/book_metadata`，方法名稱固定為 `extractMetadata`，參數鍵固定為 `uri`（String）與 `format`（String，值為 `"epub"` 或 `"pdf"`；本工單不處理 `"txt"`，圖書庫 Dart 端對 TXT 格式不會呼叫這個 channel，見 `spec.md`）。回傳值固定為 `{"title": String?, "author": String?, "coverBytes": ByteArray?}`。失敗一律透過 `MethodChannel.Result.error(code, message, details)` 回報（Dart 端會收到 `PlatformException`），**不得**讓例外未攔截導致 App 崩潰。
- 依 `spec.md`「原生 book_metadata MethodChannel 契約」，`extractMetadata` 的 `uri` 參數須同時接受**檔案系統路徑**與 `content://`/`file://` **URI 字串**（Issue 4 的 `BookImportService` 匯入真實書籍時傳入的就是真正的 `content://` URI，若這裡不支援會讓匯入流程的封面/詮釋資料提取失敗）。判斷規則與 Issue 3（`docs/adr/0002-content-uri-reader-contract.md`）一致：字串含 `"://"` 即視為 URI，否則視為檔案系統路徑——Issue 2、3 彼此獨立可平行進行，兩者各自實作一份判斷邏輯（各約 5 行），刻意不共用工具檔，避免造成兩個宣稱可平行進行的工單互相依賴。
- PDF 封面點陣圖須限制最大尺寸（寬高上限 600px，等比縮放），避免大尺寸 PDF（PRD 要求支援 100MB 以上檔案）造成記憶體壓力與封面檔案過度肥大。
- 本工單**不得**修改 `EpubReaderView.kt`/`PdfReaderView.kt` 既有的 `openBook`/`onPageRendered`/`onError` 契約或程式碼——只能新增獨立的 `BookMetadataChannel.kt`。
- 所有例外訊息（`result.error` 的 message 參數）須為正體中文。

---

### Task 1：擴充 `test/fixtures/sample.epub` 加入封面圖片

**Files:**
- Modify: `app/test/fixtures/sample.epub`（以 Python 腳本重新產生，覆蓋既有二進位檔案）

**Interfaces:**
- Consumes: 無
- Produces: 更新後的 `test/fixtures/sample.epub`（新增 `OEBPS/cover.png` 與對應 manifest 項目 `properties="cover-image"`），供本工單 Task 2 與既有 Issue 4/5 的 EPUB 渲染 `integration_test` 共用。既有的 `container.xml`/`nav.xhtml`/`chapter1.xhtml`/`dc:title` 結構完全不變，僅新增封面圖片，確保既有渲染測試不受影響。

- [ ] **Step 1：重新產生含封面圖片的 `sample.epub`**

Run（於 `app/` 目錄下，需要 Python 3；本機已確認可用）：

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

content_opf = '''<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"pub-id\">
  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">
    <dc:identifier id=\"pub-id\">urn:uuid:00000000-0000-0000-0000-000000000001</dc:identifier>
    <dc:title>elinkBook 範例 EPUB</dc:title>
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
<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\">
<head><title>目錄</title></head>
<body>
  <nav epub:type=\"toc\">
    <ol>
      <li><a href=\"chapter1.xhtml\">第一章</a></li>
    </ol>
  </nav>
</body>
</html>
'''

chapter1_xhtml = '''<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<html xmlns=\"http://www.w3.org/1999/xhtml\">
<head><title>第一章</title></head>
<body>
  <h1>第一章</h1>
  <p>這是 elinkBook 用於 integration_test 的範例 EPUB 內容。</p>
</body>
</html>
'''

cover_png = make_png(4, 4, (200, 50, 50))

with zipfile.ZipFile('test/fixtures/sample.epub', 'w') as z:
    z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip', zipfile.ZIP_STORED)
    z.writestr('META-INF/container.xml', container_xml, zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/content.opf', content_opf, zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/nav.xhtml', nav_xhtml, zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/chapter1.xhtml', chapter1_xhtml, zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/cover.png', cover_png, zipfile.ZIP_DEFLATED)

print('wrote sample.epub with cover image')
"
```

Expected: 印出 `wrote sample.epub with cover image`，`app/test/fixtures/sample.epub` 已被覆蓋（結構與 epic-0 Issue 4 產生的版本相同，僅新增 `OEBPS/cover.png` 與其 manifest 項目）。

- [ ] **Step 2：於真實裝置/模擬器上重新執行既有 EPUB 渲染 `integration_test`，確認無回歸**

Run（於 `app/` 目錄下；`<device-id>` 請替換為 `flutter devices` 列出的實際 Android 裝置/模擬器 ID）：
```bash
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```
Expected: `All tests passed!`（既有 3 項測試——有效檔案渲染、不存在路徑錯誤、損毀內容錯誤——皆不受新增封面圖片影響，維持通過）。

- [ ] **Step 3：Commit**

```bash
git add app/test/fixtures/sample.epub
git commit -m "Add cover image to sample.epub fixture for metadata extraction tests"
```

---

### Task 2：實作 `BookMetadataChannel`（原生 Kotlin）並驗證 3 項 `integration_test`

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`
- Create: `app/integration_test/book_metadata_channel_test.dart`

**Interfaces:**
- Consumes: `app/test/fixtures/sample.epub`（Task 1 已含封面圖片）、`app/test/fixtures/sample.pdf`（既有，無需修改）
- Produces: 原生端註冊的 `MethodChannel` 固定為 `"elinkbook/book_metadata"`，方法 `extractMetadata(uri: String, format: String) -> Map<String, Any?>`（鍵：`title`、`author`、`coverBytes`）。供 Issue 4（`BookImportService`）直接以 `const MethodChannel('elinkbook/book_metadata')` 呼叫，不需額外的 Dart 包裝類別（本工單範圍不含 Dart 端封裝，`issues.md` Issue 4 才需要）。

- [ ] **Step 1：實作原生 `BookMetadataChannel`（Kotlin）**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`：

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.readium.r2.shared.publication.services.cover
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.toAbsoluteUrl
import org.readium.r2.shared.util.toUrl
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser

/**
 * 一次性呼叫的原生 MethodChannel，供圖書庫匯入流程（Issue 4）提取詮釋資料
 * （標題/作者/封面），與 EpubReaderView/PdfReaderView 的 PlatformView 渲染
 * 契約分開（見 docs/epics/epic-1-library/spec.md）。`uri` 參數可能是真實
 * 檔案系統路徑，也可能是 content:// 或 file:// URI 字串（見 ADR 0002）；
 * 判斷規則與 EpubReaderView/PdfReaderView（Issue 3）一致但各自獨立實作。
 */
class BookMetadataChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "elinkbook/book_metadata")
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    init {
        channel.setMethodCallHandler(this)
    }

    /**
     * [path] 可能是真實檔案系統路徑，也可能是 content:// 或 file:// URI
     * 字串。含 "://" 者一律視為 URI，交給 Readium 的 Uri 解析；否則視為
     * 檔案系統路徑。
     */
    private fun resolveAbsoluteUrl(path: String): AbsoluteUrl {
        return if (path.contains("://")) {
            Uri.parse(path).toAbsoluteUrl()
        } else {
            File(path).toUrl()
        }
    }

    /**
     * [path] 含 "://" 者一律視為 URI，交給 ContentResolver 開啟；否則視為
     * 檔案系統路徑，沿用 ParcelFileDescriptor.open() 邏輯。
     */
    private fun openParcelFileDescriptor(path: String): ParcelFileDescriptor? {
        return if (path.contains("://")) {
            context.contentResolver.openFileDescriptor(Uri.parse(path), "r")
        } else {
            ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        }
    }

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

    private fun extractEpubMetadata(path: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                val httpClient = DefaultHttpClient()
                val assetRetriever = AssetRetriever(context.contentResolver, httpClient)
                val asset = assetRetriever.retrieve(resolveAbsoluteUrl(path)).getOrElse {
                    result.error("extraction_failed", "找不到檔案或檔案已損毀：$path", null)
                    return@launch
                }
                val publicationParser = DefaultPublicationParser(
                    context,
                    httpClient,
                    assetRetriever,
                    pdfFactory = null,
                )
                val publicationOpener = PublicationOpener(publicationParser)
                val publication =
                    publicationOpener.open(asset, allowUserInteraction = false).getOrElse {
                        result.error("extraction_failed", "無法解析 EPUB 檔案：${it.message}", null)
                        return@launch
                    }
                try {
                    val title = publication.metadata.title
                    val author = publication.metadata.authors.firstOrNull()?.name
                    val coverBytes = publication.cover()?.let { bitmapToPngBytes(it) }
                    result.success(
                        mapOf(
                            "title" to title,
                            "author" to author,
                            "coverBytes" to coverBytes,
                        ),
                    )
                } finally {
                    publication.close()
                }
            } catch (e: Exception) {
                result.error(
                    "extraction_failed",
                    "提取 EPUB 詮釋資料時發生未預期的錯誤：${e.message}",
                    null,
                )
            }
        }
    }

    private fun extractPdfMetadata(path: String, result: MethodChannel.Result) {
        var pfd: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        var page: PdfRenderer.Page? = null
        try {
            pfd = openParcelFileDescriptor(path)
            if (pfd == null) {
                result.error("extraction_failed", "找不到檔案或檔案已損毀：$path", null)
                return
            }
            renderer = PdfRenderer(pfd)
            page = renderer.openPage(0)
            // 封面只是書架縮圖，不需要頁面原始解析度；限制最大尺寸避免大型
            // PDF（PRD 要求支援 100MB 以上檔案）造成記憶體壓力與封面檔案
            // 過度肥大。PdfRenderer.Page.render() 在 transform 為 null 時，
            // 會自動把整頁內容縮放以符合目標點陣圖尺寸，不需額外的矩陣運算。
            val maxDimension = 600
            val scale = minOf(
                maxDimension.toFloat() / page.width,
                maxDimension.toFloat() / page.height,
                1f,
            )
            val bitmapWidth = (page.width * scale).toInt().coerceAtLeast(1)
            val bitmapHeight = (page.height * scale).toInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            result.success(
                mapOf(
                    "title" to null,
                    "author" to null,
                    "coverBytes" to bitmapToPngBytes(bitmap),
                ),
            )
        } catch (e: OutOfMemoryError) {
            result.error("extraction_failed", "記憶體不足，無法載入 PDF 檔案", null)
        } catch (e: Exception) {
            result.error(
                "extraction_failed",
                "提取 PDF 封面時發生未預期的錯誤：${e.message}",
                null,
            )
        } finally {
            try { page?.close() } catch (ignored: Exception) {}
            try { renderer?.close() } catch (ignored: Exception) {}
            try { pfd?.close() } catch (ignored: Exception) {}
        }
    }

    private fun bitmapToPngBytes(bitmap: Bitmap): ByteArray {
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }
}
```

- [ ] **Step 2：在 `MainActivity.kt` 註冊 `BookMetadataChannel`**

開啟 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`，在類別內新增一個欄位，並在 `configureFlutterEngine` 方法的既有兩個 `registerViewFactory(...)` 呼叫之後，新增一行初始化：

```kotlin
class MainActivity : FlutterFragmentActivity() {
    private lateinit var bookMetadataChannel: BookMetadataChannel

    override fun onCreate(savedInstanceState: Bundle?) {
        // ……（既有內容不變）
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/pdf_reader_view",
                PdfReaderViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/epub_reader_view",
                EpubReaderViewFactory(this, flutterEngine.dartExecutor.binaryMessenger),
            )
        bookMetadataChannel =
            BookMetadataChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
```

（只新增 `private lateinit var bookMetadataChannel: BookMetadataChannel` 欄位宣告與 `configureFlutterEngine` 方法內最後一行初始化；`onCreate` 方法與其餘既有內容維持不變。）

- [ ] **Step 3：撰寫 3 項 `integration_test`**

建立 `app/integration_test/book_metadata_channel_test.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

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

  testWidgets('EPUB 詮釋資料提取回傳非空的 title 與 coverBytes', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final result = await _channel.invokeMapMethod<String, Object?>(
      'extractMetadata',
      {'uri': samplePath, 'format': 'epub'},
    );

    expect(result, isNotNull);
    expect(result!['title'], isNotNull);
    expect((result['title'] as String).isNotEmpty, isTrue);
    expect(result['coverBytes'], isNotNull);
    expect((result['coverBytes'] as Uint8List).isNotEmpty, isTrue);
  });

  testWidgets('PDF 詮釋資料提取回傳非空的 coverBytes', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final result = await _channel.invokeMapMethod<String, Object?>(
      'extractMetadata',
      {'uri': samplePath, 'format': 'pdf'},
    );

    expect(result, isNotNull);
    expect(result!['coverBytes'], isNotNull);
    expect((result['coverBytes'] as Uint8List).isNotEmpty, isTrue);
  });

  testWidgets('不存在的檔案路徑呼叫 extractMetadata 拋出 PlatformException',
      (tester) async {
    final missingPath =
        '/data/local/tmp/does_not_exist_${DateTime.now().millisecondsSinceEpoch}.epub';

    expect(
      () => _channel.invokeMapMethod<String, Object?>(
        'extractMetadata',
        {'uri': missingPath, 'format': 'epub'},
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  // 以下兩項驗證 uri 參數走「URI 分支」（而非純檔案路徑）時同樣能提取成功。
  // 使用 file:// URI 驗證原生端的 URI 解析分支邏輯；真正 content:// URI
  // 的 SAF 權限情境（takePersistableUriPermission），由 Issue 4 匯入服務
  // 的手動驗收步驟做端到端驗證。
  testWidgets('以 file:// URI 表示路徑呼叫 extractMetadata（EPUB）同樣回傳非空結果',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_uri.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    final uriPath = Uri.file(samplePath).toString();

    final result = await _channel.invokeMapMethod<String, Object?>(
      'extractMetadata',
      {'uri': uriPath, 'format': 'epub'},
    );

    expect(result, isNotNull);
    expect(result!['title'], isNotNull);
    expect(result['coverBytes'], isNotNull);
  });

  testWidgets('以 file:// URI 表示路徑呼叫 extractMetadata（PDF）同樣回傳非空結果',
      (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample_uri.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    final uriPath = Uri.file(samplePath).toString();

    final result = await _channel.invokeMapMethod<String, Object?>(
      'extractMetadata',
      {'uri': uriPath, 'format': 'pdf'},
    );

    expect(result, isNotNull);
    expect(result!['coverBytes'], isNotNull);
  });
}
```

- [ ] **Step 4：於真實裝置/模擬器上執行 5 項 `integration_test`**

Run（於 `app/` 目錄下；`<device-id>` 請替換為 `flutter devices` 列出的實際 Android 裝置/模擬器 ID）：
```bash
flutter test integration_test/book_metadata_channel_test.dart -d <device-id>
```
Expected: `All tests passed!`（5 項測試皆通過：EPUB/PDF 檔案路徑各 1 項、錯誤路徑 1 項、EPUB/PDF file:// URI 各 1 項）。

- [ ] **Step 5：重新執行既有 `integration_test` 確認無回歸**

Run：
```bash
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
flutter test integration_test/pdf_reader_view_test.dart -d <device-id>
flutter test integration_test/reader_screen_test.dart -d <device-id>
flutter test integration_test/library_screen_test.dart -d <device-id>
flutter test integration_test/smoke_test.dart -d <device-id>
```
Expected: 全部 `All tests passed!`，確認新增的 `BookMetadataChannel` 與 `MainActivity.kt` 的修改未影響既有渲染流程。

- [ ] **Step 6：靜態分析與非 integration_test 全測試確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter test
```
Expected: `flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過（純 Dart/widget test，不受本工單原生程式碼異動影響）。

- [ ] **Step 7：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt app/integration_test/book_metadata_channel_test.dart
git commit -m "Add native book_metadata MethodChannel for EPUB/PDF metadata extraction"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍**：`spec.md`「原生 book_metadata MethodChannel 契約」章節定義的 `extractMetadata(uri, format) -> {title, author, coverBytes}` 已逐字實作，包含 `uri` 參數須同時支援檔案系統路徑與 `content://`/`file://` URI 字串（`resolveAbsoluteUrl`/`openParcelFileDescriptor`）；`issues.md` Issue 2 的三項 `integration_test` 要求（EPUB 非空 title/coverBytes、PDF 非空 coverBytes、不存在/損毀 URI 拋出可辨識錯誤）均已對應到 Task 2 的測試，另外新增 2 項 URI 分支測試（見「文件審查回應紀錄」）。
- **佔位符掃描**：每個步驟皆含完整程式碼與明確指令/預期輸出；Readium API 呼叫（`AssetRetriever.retrieve`、`Metadata.title`、`Contributor.name`、`Publication.cover()`、`toAbsoluteUrl`/`toUrl`）已對照本機 Gradle 快取的 `readium-shared-3.3.0-api.jar` 實際位元組碼簽章逐一確認存在，非憑記憶臆測。
- **型別/命名一致性**：channel 名稱 `elinkbook/book_metadata`、方法名稱 `extractMetadata`、回傳鍵 `title`/`author`/`coverBytes` 在 Task 2 的 Kotlin 實作與 Dart 測試之間完全一致，並與 `spec.md` 定義相符。
- **範圍邊界**：Task 1 修改共用測試 fixture（`sample.epub`）前後皆有回歸驗證步驟（Step 2）；本工單與 Issue 3 各自獨立實作一份路徑/URI 判斷邏輯（不共用工具檔），避免兩個宣稱可平行進行的工單互相依賴，但兩者現在對「是否支援 URI」的判斷規則一致，不再有 Issue 4 銜接時的功能落差。
- **PDF 封面尺寸**：新增最大 600px 縮放上限，避免大型 PDF 造成記憶體壓力與封面檔案過度肥大（縮圖用途不需要頁面原始解析度）。

## 文件審查回應紀錄（`review-plan-issue-2.md`）

- **Important #1（`BookMetadataChannel` 只接受檔案路徑，與 spec.md 的 URI 契約衝突）**：查證屬實——`spec.md` 明確要求 `Publication.open(Uri)`/`ContentResolver.openFileDescriptor(uri, "r")`，且 Issue 4 匯入真實書籍時傳入的正是 `content://` URI。已採納，比照 Issue 3 的判斷規則（含 `"://"` 即視為 URI）新增 `resolveAbsoluteUrl`/`openParcelFileDescriptor` 兩個獨立輔助方法，並新增 2 項 `file://` URI 測試案例驗證。
- **Important #2（PDF 封面點陣圖未限制尺寸）**：查證合理，已採納，新增最大 600px 等比縮放上限；確認 `PdfRenderer.Page.render()` 在 `transform=null` 時會自動把整頁內容縮放以符合目標點陣圖尺寸，不需額外的 Matrix 運算，比審查報告原始建議的寫法更簡潔（用 `minOf(a, b, 1f)` 一次限制「只縮小、不放大」，取代 `if (scale < 1f)` 條件判斷）。
