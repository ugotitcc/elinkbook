# Issue 3 實作計劃：原生 Android 模組 —— `PdfReaderView`（`PdfRenderer`）

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 建立包裝 Android 系統內建 `android.graphics.pdf.PdfRenderer` 的原生 `PlatformView`，透過 Flutter 的 `AndroidView` 機制嵌入畫面，實作 `spec.md` 定義的 `openBook`/`onPageRendered`/`onError` platform channel 契約，並用 `integration_test` 在真實 Android 裝置/模擬器上驗證。

**架構：** Flutter 端是一個包裝 `AndroidView` 的 `PdfReaderView` widget，透過每個 view 實例專屬的 `MethodChannel` 與原生端溝通：Flutter 呼叫 `openBook(path)` 通知原生端載入檔案；原生端非同步呼叫回 `onPageRendered()`（成功）或 `onError(message)`（失敗）。原生端是一個包裝 `PdfRenderer` 的 Kotlin `PlatformView`，用 `ImageView` 顯示渲染出的第 1 頁點陣圖。因為內容存在於原生 `PlatformView` 之中，一般 `flutter test` widget test 無法觀察到渲染結果（widget test 執行時沒有真實的 platform view），所以本工單的驗證方式改用 Flutter 的 `integration_test` 套件，在真實裝置/模擬器上執行——這是 `spec.md`「測試決策」章節已說明的預期做法，不是偏離 TDD，而是這一類原生渲染工作的既定驗證策略。

**技術棧：** Flutter（Dart）、Kotlin、Android `PdfRenderer`、`integration_test`、`path_provider`（僅用於測試，將夾帶測試用的 PDF 檔案從 Flutter assets 複製到裝置暫存目錄）。

## ⚠️ 執行前環境確認事項

撰寫本計劃時，目前開發環境**沒有任何 Android 模擬器或實體裝置連線**（`flutter devices` 只列出 Windows/Chrome/Edge；`adb` 指令不存在）。本計劃所有 `integration_test` 步驟都必須在真實 Android 裝置/模擬器上執行才能驗證——**執行本計劃前，請先確認已有可用的 Android 模擬器或裝置**（例如透過 Android Studio 建立 AVD，或連接實體裝置並開啟 USB 偵錯），否則 Task 1 與 Task 2 的驗證步驟都無法通過。

## 全域限制條件

- Flutter 專案位於 `app/`，套件名稱為 `elinkbook`，Android 應用程式 ID 為 `cc.ugotit.elinkbook`（Issue 1 已建立）。
- Platform channel 契約須與 `spec.md` 完全一致：`openBook(path: String) -> void`（Flutter → 原生）、`onPageRendered() -> void`（原生 → Flutter）、`onError(message: String) -> void`（原生 → Flutter）。
- 本工單只渲染 PDF 的**第 1 頁**（對應 `spec.md` 對 `ReaderScreen` 的定義：「渲染該書第 1 頁」），不實作多頁瀏覽、縮放、影像濾鏡等功能——那些屬於 `epic-4-pdf-enhance` 的範圍。
- 本工單**不得**引入 Readium/EPUB 相關程式碼（`epic-4` 原文為 Issue 4 範圍）、**不得**修改 `ReaderScreen` 的分派邏輯把佔位視圖換成 `PdfReaderView`（那是 Issue 5 的範圍）——本工單的 `PdfReaderView` 是獨立建構、獨立測試的元件。
- 所有畫面上的使用者可見文字（例如錯誤訊息）須為正體中文。
- `PdfReaderView` 的原生實作在目前階段以同步方式處理 PDF 載入/渲染（在 method channel 呼叫的執行緒上直接進行），未使用背景執行緒；這對測試用的小型 PDF 檔案而言足夠，若後續遇到大型 PDF 檔案造成 UI 卡頓，屬於未來 `epic-4-pdf-enhance` 需要重新檢視的效能議題，不在本工單範圍內。

---

### Task 1：建立 `integration_test` 測試基礎設施與範例 PDF 測試檔

**Files:**
- Modify: `app/pubspec.yaml`
- Create: `app/test/fixtures/sample.pdf`
- Create: `app/integration_test/smoke_test.dart`

**Interfaces:**
- Consumes: 無（獨立於 Issue 1/2 的程式碼介面，僅需要 `app/` 專案骨架與 `LibraryScreen` 已存在，用於 smoke test）
- Produces: `integration_test`、`path_provider` 套件依賴、已提交版本控制的 `app/test/fixtures/sample.pdf` 測試檔，供 Task 2 使用；已驗證可正常運作的 `integration_test` 執行環境，供 Task 2 與後續 Issue 4 使用。

- [ ] **Step 1：新增 `integration_test` SDK 依賴**

開啟 `app/pubspec.yaml`，在 `dev_dependencies:` 區塊中，於 `flutter_test:` 之後新增：

```yaml
  integration_test:
    sdk: flutter
```

- [ ] **Step 2：新增 `path_provider` 依賴（僅供測試使用）**

Run（於 `app/` 目錄下）：
```bash
flutter pub add path_provider --dev
```
Expected: 終端機顯示 `path_provider` 已加入 `dev_dependencies`，並顯示實際解析到的版本號。

- [ ] **Step 3：產生範例 PDF 測試檔**

Run（於 `app/` 目錄下，需要 Python 3；本機已確認可用）：
```bash
python3 -c "
objects = [
    b'<< /Type /Catalog /Pages 2 0 R >>',
    b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> >>',
]
pdf = b'%PDF-1.4\n'
offsets = [0]
for i, obj in enumerate(objects, start=1):
    offsets.append(len(pdf))
    pdf += ('%d 0 obj\n' % i).encode() + obj + b'\nendobj\n'
xref_offset = len(pdf)
pdf += ('xref\n0 %d\n' % (len(objects) + 1)).encode()
pdf += b'0000000000 65535 f \n'
for off in offsets[1:]:
    pdf += ('%010d 00000 n \n' % off).encode()
pdf += b'trailer\n'
pdf += ('<< /Size %d /Root 1 0 R >>\n' % (len(objects) + 1)).encode()
pdf += b'startxref\n'
pdf += ('%d\n' % xref_offset).encode()
pdf += b'%%EOF'
with open('test/fixtures/sample.pdf', 'wb') as f:
    f.write(pdf)
print('wrote', len(pdf), 'bytes')
"
```
Expected: 印出 `wrote <N> bytes`，且 `app/test/fixtures/sample.pdf` 檔案已建立（單頁、200x200pt 空白頁面的最小合法 PDF；位元組偏移量由腳本動態計算，保證 xref 表正確）。

- [ ] **Step 4：將測試檔宣告為 Flutter asset**

開啟 `app/pubspec.yaml`，在 `flutter:` 區塊中新增 `assets:`：

```yaml
  assets:
    - test/fixtures/sample.pdf
```

（此測試檔會被打包進 App 的 asset bundle，僅供 `integration_test` 用來把檔案複製到裝置暫存目錄使用；若未來要避免測試檔案進入正式發布版本，屬於後續可再優化的項目，不在本工單範圍內。）

- [ ] **Step 5：安裝相依套件**

Run（於 `app/` 目錄下）：
```bash
flutter pub get
```
Expected: 成功解析並安裝所有套件，無錯誤。

- [ ] **Step 6：撰寫 smoke test 驗證 `integration_test` 基礎設施本身可運作**

建立 `app/integration_test/smoke_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:elinkbook/screens/library_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LibraryScreen 可在真實裝置/模擬器上渲染（integration_test 基礎設施驗證）',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
  });
}
```

此測試刻意不涉及 PDF，只用來確認 `integration_test` 套件本身安裝正確、能在裝置上執行——把「測試基礎設施是否正常」與「PDF 渲染邏輯是否正確」分開驗證。

- [ ] **Step 7：於真實裝置/模擬器上執行 smoke test**

Run（於 `app/` 目錄下；`<device-id>` 請替換為 `flutter devices` 列出的實際 Android 裝置/模擬器 ID）：
```bash
flutter test integration_test/smoke_test.dart -d <device-id>
```
Expected: `All tests passed!`

- [ ] **Step 8：Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/test/fixtures/sample.pdf app/integration_test/smoke_test.dart
git commit -m "Add integration_test infrastructure and sample PDF fixture"
```

---

### Task 2：實作 `PdfReaderView`（原生 Kotlin + Flutter widget）並驗證兩項 `integration_test`

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderViewFactory.kt`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`
- Create: `app/lib/reader/pdf_reader_view.dart`
- Create: `app/integration_test/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes: `app/test/fixtures/sample.pdf`（Task 1 產出）、`path_provider`/`integration_test`（Task 1 已加入依賴）
- Produces: `PdfReaderView({required String filePath, required VoidCallback onPageRendered, required ValueChanged<String> onError})`（Flutter `StatefulWidget`），供 Issue 5（`ReaderScreen` 端到端整合，把佔位視圖換成本元件）使用。原生端註冊的 `PlatformView` 類型字串固定為 `"cc.ugotit.elinkbook/pdf_reader_view"`，method channel 名稱固定為 `"cc.ugotit.elinkbook/pdf_reader_view_$id"`（`$id` 為 Flutter 指派的 platform view 實例 id）——後續工單如需與原生端對接，須沿用這組命名。

- [ ] **Step 1：實作原生 `PdfReaderView`（Kotlin）**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`：

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
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
 * onPageRendered，失敗則呼叫 onError(message)。
 */
class PdfReaderView(
    context: Context,
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
            val file = File(path)
            pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
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

    override fun dispose() {}
}
```

- [ ] **Step 2：實作 `PlatformViewFactory`（Kotlin）**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderViewFactory.kt`：

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class PdfReaderViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        return PdfReaderView(context, id, messenger)
    }
}
```

- [ ] **Step 3：在 `MainActivity.kt` 註冊 `PlatformViewFactory`**

將 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt` 整份內容改為：

```kotlin
package cc.ugotit.elinkbook

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/pdf_reader_view",
                PdfReaderViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
    }
}
```

- [ ] **Step 4：實作 Flutter 端 `PdfReaderView` widget**

建立 `app/lib/reader/pdf_reader_view.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 包裝原生 Android PdfReaderView 的 Flutter widget，透過 AndroidView
/// （PlatformView）嵌入畫面。給定 PDF 檔案的裝置端絕對路徑，通知原生端
/// 渲染第 1 頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
class PdfReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;

  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
  });

  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();
}

class _PdfReaderViewState extends State<PdfReaderView> {
  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
    channel.setMethodCallHandler(_handleMethodCall);
    channel.invokeMethod('openBook', {'path': widget.filePath});
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPageRendered':
        widget.onPageRendered();
        break;
      case 'onError':
        widget.onError(call.arguments as String);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'cc.ugotit.elinkbook/pdf_reader_view',
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}
```

- [ ] **Step 5：撰寫兩項 `integration_test`**

建立 `app/integration_test/pdf_reader_view_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
/// PdfRenderer 需要真實的裝置檔案系統路徑，不能直接讀取 Flutter asset。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('開啟有效 PDF 檔案觸發 onPageRendered', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample.pdf');

    // 用 Completer 等待原生端的非同步 callback，callback 一觸發就立刻往下走，
    // 不需要固定等待一段時間。注意：pumpAndSettle 的參數是「每次 pump 之間
    // 的間隔」，不是「總等待時間」，不能拿來當作 timeout 使用。
    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: samplePath,
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

  testWidgets('開啟不存在的檔案路徑觸發 onError', (tester) async {
    final completer = Completer<void>();
    var rendered = false;
    String? errorMessage;

    final missingPath =
        '/data/local/tmp/does_not_exist_${DateTime.now().millisecondsSinceEpoch}.pdf';

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: missingPath,
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
}
```

- [ ] **Step 6：於真實裝置/模擬器上執行兩項 `integration_test`**

Run（於 `app/` 目錄下；`<device-id>` 請替換為 `flutter devices` 列出的實際 Android 裝置/模擬器 ID）：
```bash
flutter test integration_test/pdf_reader_view_test.dart -d <device-id>
```
Expected: `All tests passed!`（兩項測試皆通過：有效 PDF 觸發 `onPageRendered`；不存在的路徑觸發 `onError`）。

- [ ] **Step 7：重新執行 Task 1 的 smoke test 確認無回歸**

Run：
```bash
flutter test integration_test/smoke_test.dart -d <device-id>
```
Expected: `All tests passed!`

- [ ] **Step 8：靜態分析確認無警告**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 9：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderViewFactory.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt app/lib/reader/pdf_reader_view.dart app/integration_test/pdf_reader_view_test.dart
git commit -m "Add PdfReaderView native PlatformView with PdfRenderer integration"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍**：對應 `issues.md` Issue 3 的兩項 `integration_test` 要求（有效 PDF 觸發 `onPageRendered`、不存在/損毀檔案觸發 `onError`）與兩項驗收標準（範例 PDF 已提交版本控制、兩項 `integration_test` 皆通過）均已對應到 Task 1（測試基礎設施與 fixture）與 Task 2（實作與驗證）。`spec.md` 定義的 platform channel 契約（`openBook`/`onPageRendered`/`onError`）已逐字實作於原生與 Flutter 兩側。
- **佔位符掃描**：每個步驟皆含完整程式碼與明確指令/預期輸出；PDF 產生腳本以程式動態計算位元組偏移量，避免手算錯誤；`<device-id>` 是執行時才能得知的真實環境參數（非規格缺口），已於步驟中註明替換方式。
- **型別/命名一致性**：`PdfReaderView`、`filePath`、`onPageRendered`、`onError` 在 Flutter 與 Kotlin 兩側、以及與 `spec.md` 定義的介面保持一致；`PlatformView` 類型字串與 method channel 命名規則已在 Task 2 的 Interfaces 區塊中明確記錄，供 Issue 4（`EpubReaderView`，應沿用相同契約與類似命名慣例）與 Issue 5（`ReaderScreen` 整合）參考。
- **環境缺口揭露**：本計劃在開頭明確標註目前開發環境沒有 Android 模擬器/裝置可用，執行前需要先解決，避免執行者誤以為所有步驟都能立即照跑。

## 文件審查回應紀錄（`plan-issue-3-review.md`）

- **#1（原生資源釋放與例外捕獲）**：查證屬實，已採納「用 `finally` 確保資源釋放」。**未採用**審查建議的 `catch (t: Throwable)`——改為明確分開捕獲 `OutOfMemoryError` 與 `Exception`，只處理審查報告實際點出的風險（點陣圖解碼記憶體不足），避免連 `AssertionError`/`LinkageError` 這類代表程式或環境本身有問題的錯誤都被靜默吞掉。**未採用**審查建議新增的 `pageCount == 0` 檢查——`openPage(0)` 在該情境下本來就會拋例外並被既有 catch 區塊接住、回報 `onError`，沒有任何測試要求這個情境要有專屬訊息，屬於超出目前驗收範圍的擴增（YAGNI）。
- **#2（`pumpAndSettle` 參數誤用）**：查證屬實——`pumpAndSettle` 第一個參數是每次 pump 的間隔，不是總等待時間，原計劃寫法會讓測試不必要變慢。已採納，改用 `Completer` 等待原生端 callback，並設定 5 秒 timeout。
- **#3（`_stageAssetAsFile` 設計）**：審查報告本身即為確認既有設計正確，無需修改。
