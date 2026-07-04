# Issue 3 實作計劃：`EpubReaderView`/`PdfReaderView` content URI 契約擴充（ADR 0002）

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 依 `docs/adr/0002-content-uri-reader-contract.md`，把既有 `openBook(path)` 契約從「只接受真實檔案系統路徑」擴充為「同時接受檔案系統路徑或 URI 字串（`content://`/`file://`）」，讓 Issue 4（`BookImportService`）之後可以匯入本機檔案時不複製一份、直接引用 SAF 選檔取得的 `content://` URI。原本檔案路徑的呼叫方式必須完全保持相容。

**架構：** `EpubReaderView.kt`／`PdfReaderView.kt` 各自新增一個私有輔助方法，把傳入的路徑字串解析成 Readium 的 `AbsoluteUrl`（EPUB）或 `ParcelFileDescriptor`（PDF）：只要字串含 `"://"` 即視為 URI 交給對應機制解析，否則視為檔案系統路徑走原本邏輯。兩個檔案的解析邏輯彼此獨立實作（各自約 5 行），刻意不抽成共用檔案——`EpubReaderView`/`PdfReaderView` 分屬不同底層渲染引擎，且與 Issue 2（也需要類似的路徑判斷邏輯）宣告為可平行進行的獨立工單，抽共用檔案會在三者間造成不必要的實作順序耦合。

**技術棧：** Kotlin、Readium `readium-shared` 3.3.0（`AbsoluteUrl`/`Url` 相關 API）、Android `ContentResolver`、`integration_test`。

## ⚠️ 執行前環境確認事項

本計劃全數驗證步驟須在真實 Android 模擬器/裝置上執行——執行前請先確認 `flutter devices` 能列出至少一個 Android 裝置/模擬器。

## 全域限制條件

- `openBook(path: String) -> void` 的 method channel 契約名稱與既有回呼（`onPageRendered()`/`onError(message)`）**不變**；只調整 `path` 參數內部如何被解析使用。
- `ReaderScreen(filePath: String)`、`detectBookFormat()` 對外簽章不變（本工單不觸碰 Dart 端的 `ReaderScreen`/`book_format.dart`）。
- 判斷規則固定為：字串包含 `"://"` 即視為 URI（不論 `content://`、`file://` 或其他 scheme），否則視為檔案系統路徑——與 Issue 2 的 `BookMetadataChannel` 採用相同判斷規則，但**各自獨立實作**（不共用工具檔，見上方「架構」說明）。
- 原本「純檔案路徑」的呼叫方式（Issue 3 之前既有的用法）**必須**維持完全相容，用既有 `integration_test` 重新執行驗證無回歸。
- 本工單**不得**修改 `BookMetadataChannel.kt`（Issue 2 範圍）、**不得**處理 SAF `takePersistableUriPermission()`（那是匯入當下的關注點，屬於 Issue 4 `BookImportService` 的範圍，見 ADR 0002「決策」章節）。
- 所有錯誤訊息維持正體中文。

---

### Task 1：`EpubReaderView.kt` 擴充支援 URI 路徑

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
- Modify: `app/integration_test/epub_reader_view_test.dart`

**Interfaces:**
- Consumes: 無新依賴（`AbsoluteUrl`/`toAbsoluteUrl`/`toUrl` 皆來自既有的 `readium-shared` 依賴）
- Produces: `EpubReaderView`/`openBook` 現在同時接受檔案系統路徑或 URI 字串；`resolveAbsoluteUrl(path: String): AbsoluteUrl`（私有方法，不對外曝露，僅供本檔案內部使用）。

- [x] **Step 1：新增「開啟 URI 表示的有效 EPUB 檔案」與「URI 對應到不存在資源時觸發 onError」測試**

在 `app/integration_test/epub_reader_view_test.dart` 檔案開頭的 import 區塊新增：

```dart
import 'dart:io';
```

（若已存在則略過；此檔案已 import `dart:io`，只需確認存在即可。）

在既有的三項 `testWidgets` 之後（`}` 結束整個 `void main()` 之前），新增兩項測試：

```dart
  // 使用 file:// URI 驗證原生端的 URI 解析分支邏輯（resolveAbsoluteUrl 對
  // file:// 與 content:// 走的是完全相同的程式碼路徑）。真正 content://
  // URI 的 SAF 權限情境（takePersistableUriPermission）留待 Issue 4 匯入
  // 服務的手動驗收步驟做端到端驗證，本測試不涵蓋。
  testWidgets('開啟以 file:// URI 表示的有效 EPUB 檔案觸發 onPageRendered',
      (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample_uri.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    final uriPath = Uri.file(samplePath).toString();

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: uriPath,
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

  testWidgets('開啟指向不存在資源的 content:// URI 觸發 onError', (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    final missingUri =
        'content://cc.ugotit.elinkbook.does_not_exist/${DateTime.now().millisecondsSinceEpoch}.epub';

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: missingUri,
          onPageRendered: () {
            rendered = true;
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

    expect(errorMessage, isNotNull);
    expect(rendered, isFalse);
  });
```

- [x] **Step 2：於真實裝置/模擬器上執行測試確認新案例失敗（原生端尚未支援 URI）**

Run（於 `app/` 目錄下；`<device-id>` 請替換為 `flutter devices` 列出的實際 Android 裝置/模擬器 ID）：
```bash
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```
Expected: 既有 3 項測試通過，新增的「file:// URI」測試失敗（`errorMessage` 非 null，因為原生端目前把整個 URI 字串當成檔案系統路徑傳給 `File(path)`，找不到這個檔案）。

- [x] **Step 3：擴充 `EpubReaderView.kt` 支援 URI 路徑**

開啟 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`，在檔案開頭的 import 區塊，將：

```kotlin
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Url
```

改為（新增 `Uri`、`toAbsoluteUrl`、`toUrl`）：

```kotlin
import android.net.Uri
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.toAbsoluteUrl
import org.readium.r2.shared.util.toUrl
```

將 `openBook()` 方法中的這一行：

```kotlin
                val asset = assetRetriever.retrieve(File(path)).getOrElse {
```

改為：

```kotlin
                val asset = assetRetriever.retrieve(resolveAbsoluteUrl(path)).getOrElse {
```

在 `dispose()` 方法之前，新增私有輔助方法：

```kotlin
    /**
     * [path] 可能是真實檔案系統路徑，也可能是 content:// 或 file:// URI 字串
     * （見 docs/adr/0002-content-uri-reader-contract.md）。含 "://" 者一律
     * 視為 URI，交給 Readium 的 Uri 解析；否則視為檔案系統路徑。
     */
    private fun resolveAbsoluteUrl(path: String): AbsoluteUrl {
        return if (path.contains("://")) {
            Uri.parse(path).toAbsoluteUrl()
        } else {
            File(path).toUrl()
        }
    }
```

（`import java.io.File` 已存在於既有 import 區塊，不需重複新增。）

- [x] **Step 4：於真實裝置/模擬器上重新執行測試確認全部通過**

Run：
```bash
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```
Expected: `All tests passed!`（既有 3 項 + 新增 2 項，共 5 項測試皆通過）。

- [x] **Step 5：靜態分析與建置確認**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter build apk --debug
```
Expected: `flutter analyze` 顯示 `No issues found!`；`flutter build apk --debug` 成功建置，確認原生 Kotlin 程式碼可正確編譯。

- [x] **Step 6：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt app/integration_test/epub_reader_view_test.dart
git commit -m "Extend EpubReaderView to accept content/file URI paths (ADR 0002)"
```

---

### Task 2：`PdfReaderView.kt` 擴充支援 URI 路徑

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Modify: `app/integration_test/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes: 無新依賴
- Produces: `PdfReaderView`/`openBook` 現在同時接受檔案系統路徑或 URI 字串；`openParcelFileDescriptor(path: String): ParcelFileDescriptor?`（私有方法，不對外曝露）。

- [x] **Step 1：新增「開啟 URI 表示的有效 PDF 檔案」與「URI 對應到不存在資源時觸發 onError」測試**

在 `app/integration_test/pdf_reader_view_test.dart` 既有的兩項 `testWidgets` 之後，新增兩項測試：

```dart
  // 使用 file:// URI 驗證原生端的 URI 解析分支邏輯（openParcelFileDescriptor
  // 對 file:// 與 content:// 走的是完全相同的程式碼路徑）。真正 content://
  // URI 的 SAF 權限情境（takePersistableUriPermission）留待 Issue 4 匯入
  // 服務的手動驗收步驟做端到端驗證，本測試不涵蓋。
  testWidgets('開啟以 file:// URI 表示的有效 PDF 檔案觸發 onPageRendered',
      (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample_uri.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    final uriPath = Uri.file(samplePath).toString();

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: uriPath,
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

    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');
  });

  testWidgets('開啟指向不存在資源的 content:// URI 觸發 onError', (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    final missingUri =
        'content://cc.ugotit.elinkbook.does_not_exist/${DateTime.now().millisecondsSinceEpoch}.pdf';

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: missingUri,
          onPageRendered: () {
            rendered = true;
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(errorMessage, isNotNull);
    expect(rendered, isFalse);
  });
```

- [x] **Step 2：於真實裝置/模擬器上執行測試確認新案例失敗**

Run：
```bash
flutter test integration_test/pdf_reader_view_test.dart -d <device-id>
```
Expected: 既有 2 項測試通過，新增的「file:// URI」測試失敗（`errorMessage` 非 null，因為原生端目前把整個 URI 字串當成檔案系統路徑傳給 `File(path)`，找不到這個檔案）。

- [x] **Step 3：擴充 `PdfReaderView.kt` 支援 URI 路徑**

開啟 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`，將整份內容改為：

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.view.View
import android.widget.ImageView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File

/**
 * 包裝 android.graphics.pdf.PdfRenderer 的原生 PlatformView。
 * 透過 MethodChannel 接收 Flutter 的 openBook 呼叫，成功則呼叫
 * onPageRendered，失敗則呼叫 onError(message)。[path] 可能是真實檔案系統
 * 路徑，也可能是 content:// 或 file:// URI 字串（見
 * docs/adr/0002-content-uri-reader-contract.md）。
 */
class PdfReaderView(
    private val context: Context,
    id: Int,
    messenger: BinaryMessenger,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val imageView: ImageView = ImageView(context)
    private val channel: MethodChannel =
        MethodChannel(messenger, "cc.ugotit.elinkbook/pdf_reader_view_$id")

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = imageView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                val path = call.argument<String>("path")
                openBook(path)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun openBook(path: String?) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        var pfd: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        var page: PdfRenderer.Page? = null
        try {
            pfd = openParcelFileDescriptor(path)
            if (pfd == null) {
                channel.invokeMethod("onError", "找不到檔案或檔案已損毀：$path")
                return
            }
            renderer = PdfRenderer(pfd)
            page = renderer.openPage(0)
            val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            imageView.setImageBitmap(bitmap)
            channel.invokeMethod("onPageRendered", null)
        } catch (e: OutOfMemoryError) {
            channel.invokeMethod("onError", "記憶體不足，無法載入 PDF 檔案")
        } catch (e: Exception) {
            channel.invokeMethod("onError", e.message ?: "無法載入 PDF 檔案")
        } finally {
            // 確保任何情況下（含上方例外拋出時）原生資源都會被釋放，避免
            // 檔案描述符/渲染器洩漏。
            try { page?.close() } catch (ignored: Exception) {}
            try { renderer?.close() } catch (ignored: Exception) {}
            try { pfd?.close() } catch (ignored: Exception) {}
        }
    }

    /**
     * [path] 含 "://" 者一律視為 URI，交給 ContentResolver 開啟（Android
     * 對 file:// scheme 有內建直接處理，不需額外註冊 ContentProvider）；
     * 否則視為檔案系統路徑，沿用既有 ParcelFileDescriptor.open() 邏輯。
     */
    private fun openParcelFileDescriptor(path: String): ParcelFileDescriptor? {
        return if (path.contains("://")) {
            context.contentResolver.openFileDescriptor(Uri.parse(path), "r")
        } else {
            ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        }
    }

    override fun dispose() {}
}
```

- [x] **Step 4：於真實裝置/模擬器上重新執行測試確認全部通過**

Run：
```bash
flutter test integration_test/pdf_reader_view_test.dart -d <device-id>
```
Expected: `All tests passed!`（既有 2 項 + 新增 2 項，共 4 項測試皆通過）。

- [x] **Step 5：重新執行 Issue 1（epic-0）既有的 EPUB/其餘 `integration_test` 確認無回歸**

Run：
```bash
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
flutter test integration_test/reader_screen_test.dart -d <device-id>
flutter test integration_test/library_screen_test.dart -d <device-id>
flutter test integration_test/smoke_test.dart -d <device-id>
```
Expected: 全部 `All tests passed!`。

- [x] **Step 6：靜態分析與建置確認**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter build apk --debug
flutter test
```
Expected: `flutter analyze` 顯示 `No issues found!`；`flutter build apk --debug` 成功建置；`flutter test`（純 Dart/widget test）全數通過，無回歸。

- [x] **Step 7：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt app/integration_test/pdf_reader_view_test.dart
git commit -m "Extend PdfReaderView to accept content/file URI paths (ADR 0002)"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍**：ADR 0002「決策」章節定義的兩項擴充（EPUB 透過 `Uri` 開啟、PDF 透過 `ContentResolver.openFileDescriptor` 取得 fd）已分別對應到 Task 1、2；`issues.md` Issue 3 的三項 `integration_test` 要求（既有檔案路徑回歸、content/file URI 觸發 `onPageRendered`、無效 URI 觸發 `onError`）均已對應到兩個 Task 的測試案例（以 `file://` URI 驗證正向案例、以不存在的 `content://` URI 驗證錯誤案例——理由與 Readium/ContentResolver 對 `file://` scheme 的內建支援已在下方註記說明）。
- **佔位符掃描**：每個步驟皆含完整程式碼與明確指令/預期輸出，`PdfReaderView.kt` 以完整檔案內容呈現，避免局部修改指示產生歧義。
- **型別/命名一致性**：`resolveAbsoluteUrl`/`openParcelFileDescriptor` 命名與回傳型別在 Task 1、2 之間依各自檔案內部慣例保持一致；`openBook`/`onPageRendered`/`onError` 對外契約全程不變。
- **技術決策註記**：測試改用 `file://` URI（而非透過額外的 `FileProvider` 產生真正的 `content://` URI）驗證「URI 分支」邏輯，因為 Readium 的 `AbsoluteUrl`（`isFile()`）與 Android `ContentResolver.openFileDescriptor`（對 `file` scheme 有平台內建處理）皆原生支援 `file://` scheme，不需額外註冊 `ContentProvider`；`resolveAbsoluteUrl`/`openParcelFileDescriptor` 的分支判斷是「含 `"://"` 即走 URI 分支」，對 `file://` 與 `content://`走的是完全相同的程式碼路徑，因此用 `file://` 驗證已足以證明本工單新增的分支邏輯正確運作。真正的 `content://` URI（來自 SAF 選檔）之整合驗證，由 Issue 4 的手動驗收標準（「從裝置選取一個真實 EPUB/PDF 檔案，匯入後資料庫確實新增一筆對應記錄」）覆蓋。

## 文件審查回應紀錄（`review-plan-issue-3.md`）

- **Minor #1（測試案例使用 `file://` 而非 `content://` 的說明）**：已採納，於 Task 1、2 新增的 `file://` URI 測試案例前補上簡短註解，說明測試覆蓋範圍與 Issue 4 手動驗收的分工——與「自我審查紀錄」的技術決策註記一致，只是把說明移到測試程式碼旁邊，讓之後單獨閱讀測試檔案的人也能立即看到。
