# Issue 9：PDF 書籍無法換頁 — 實作計劃

**Goal:** 實作 PDF 書籍的手勢翻頁功能，讓使用者可以左右滑動切換頁面

**根因分析：**
`PdfReaderView.kt` 目前只渲染第 0 頁（`renderer.openPage(0)`），沒有手勢偵測、頁面導航邏輯、或 method channel 處理。ImageView 是靜態的，完全沒有翻頁能力。

---

### Task 1: 擴充 Dart 端 PdfReaderView 支援翻頁

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`

**Description:**
新增頁面導航 API 和手勢偵測，讓使用者可以透過滑動或按鈕翻頁。

- [ ] **Step 1: 新增頁面導航回調參數**

```dart
class PdfReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final VoidCallback? onNextPage; // 新增：下一頁回調
  final VoidCallback? onPreviousPage; // 新增：上一頁回調
  
  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onNextPage,
    this.onPreviousPage,
  });
  // ...
}
```

- [ ] **Step 2: 新增手勢偵測（GestureDetector）**

```dart
@override
Widget build(BuildContext context) {
  return GestureDetector(
    onHorizontalDragEnd: (details) {
      if (details.primaryVelocity == null) return;
      if (details.primaryVelocity! < 0) {
        // 向左滑動 → 下一頁
        widget.onNextPage?.call();
      } else if (details.primaryVelocity! > 0) {
        // 向右滑動 → 上一頁
        widget.onPreviousPage?.call();
      }
    },
    child: AndroidView(
      viewType: 'cc.ugotit.elinkbook/pdf_reader_view',
      onPlatformViewCreated: _onPlatformViewCreated,
    ),
  );
}
```

- [ ] **Step 3: 新增 method channel 處理頁面導航**

```dart
void _onPlatformViewCreated(int id) {
  final channel = MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
  _channel = channel;
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
    case 'onPageChanged': // 新增：頁面變更回調
      // 可用於更新頁碼顯示
      break;
  }
}

// 新增：導航方法
void nextPage() => _channel?.invokeMethod('nextPage');
void previousPage() => _channel?.invokeMethod('previousPage');
```

---

### Task 2: 擴充 Kotlin 端 PdfReaderView 支援翻頁

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`

**Description:**
實作頁面導航邏輯，包括頁碼追蹤、手勢處理、和 method channel 回應。

- [ ] **Step 1: 新增頁碼追蹤狀態**

```kotlin
class PdfReaderView(
    private val context: Context,
    id: Int,
    messenger: BinaryMessenger,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val imageView: ImageView = ImageView(context)
    private val channel: MethodChannel =
        MethodChannel(messenger, "cc.ugotit.elinkbook/pdf_reader_view_$id")
    
    private var renderer: PdfRenderer? = null
    private var currentPageIndex: Int = 0
    private var totalPages: Int = 0
    
    // ...
}
```

- [ ] **Step 2: 修改 openBook() 儲存 renderer 並記錄總頁數**

```kotlin
private fun openBook(path: String?) {
    if (path == null) {
        channel.invokeMethod("onError", "缺少檔案路徑")
        return
    }
    var pfd: ParcelFileDescriptor? = null
    try {
        pfd = openParcelFileDescriptor(path)
        if (pfd == null) {
            channel.invokeMethod("onError", "找不到檔案或檔案已損毀：$path")
            return
        }
        renderer = PdfRenderer(pfd)
        totalPages = renderer!!.pageCount
        currentPageIndex = 0
        renderCurrentPage()
        channel.invokeMethod("onPageRendered", null)
    } catch (e: OutOfMemoryError) {
        channel.invokeMethod("onError", "記憶體不足，無法載入 PDF 檔案")
    } catch (e: Exception) {
        channel.invokeMethod("onError", e.message ?: "無法載入 PDF 檔案")
    } finally {
        pfd?.close()
    }
}
```

- [ ] **Step 3: 新增 renderCurrentPage() 方法**

```kotlin
private fun renderCurrentPage() {
    val renderer = renderer ?: return
    val page = renderer.openPage(currentPageIndex)
    val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
    imageView.setImageBitmap(bitmap)
    page.close()
}
```

- [ ] **Step 4: 新增 method channel 處理翻頁指令**

```kotlin
override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
        "openBook" -> {
            val path = call.argument<String>("path")
            openBook(path)
            result.success(null)
        }
        "nextPage" -> {
            nextPage()
            result.success(null)
        }
        "previousPage" -> {
            previousPage()
            result.success(null)
        }
        else -> result.notImplemented()
    }
}

private fun nextPage() {
    if (currentPageIndex < totalPages - 1) {
        currentPageIndex++
        renderCurrentPage()
        channel.invokeMethod("onPageChanged", currentPageIndex)
    }
}

private fun previousPage() {
    if (currentPageIndex > 0) {
        currentPageIndex--
        renderCurrentPage()
        channel.invokeMethod("onPageChanged", currentPageIndex)
    }
}
```

- [ ] **Step 5: 修改 dispose() 清理 renderer**

```kotlin
override fun dispose() {
    renderer?.close()
    renderer = null
    channel.setMethodCallHandler(null)
}
```

---

### Task 3: 更新 ReaderScreen 支援 PDF 翻頁

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`

**Description:**
在 `ReaderScreen` 中處理 PDF 翻頁事件，可選用：新增頁碼顯示或音量鍵翻頁支援。

- [ ] **Step 1: 在 `_buildNativeView()` 中傳入翻頁回調**

```dart
case BookFormat.pdf:
  return PdfReaderView(
    filePath: widget.filePath,
    onPageRendered: _handlePageRendered,
    onError: _handleError,
    onNextPage: _handleNextPage, // 新增
    onPreviousPage: _handlePreviousPage, // 新增
  );
```

- [ ] **Step 2: 新增翻頁處理方法**

```dart
void _handleNextPage() {
  // 可擴充：音量鍵翻頁、熱區翻頁等
}

void _handlePreviousPage() {
  // 可擴充：音量鍵翻頁、熱區翻頁等
}
```

---

### Task 4: 建立整合測試

**Files:**
- Create: `app/integration_test/pdf_page_turn_test.dart`

**Description:**
驗證 PDF 書籍可以正常翻頁。

- [ ] **Step 1: 測試 PDF 翻頁功能**

```dart
testWidgets('PDF 書籍可以左右滑動翻頁', (tester) async {
  final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample.pdf', 'sample_page_turn.pdf');
  
  await tester.pumpWidget(MaterialApp(
    home: ReaderScreen(
      filePath: samplePath,
      bookId: 'pdf_turn_test',
      prefsRepository: prefsRepository,
    ),
  ));
  
  // 等待載入
  await _pumpUntil(tester, _loadingIndicatorGone, timeout: Duration(seconds: 10));
  
  // 向左滑動（下一頁）
  await tester.drag(find.byType(PdfReaderView), Offset(-100, 0));
  await tester.pumpAndSettle();
  
  // 確認無錯誤
  expect(find.byKey(const Key('reader_error_text')), findsNothing);
});
```

---

### 驗收標準
- PDF 書籍可正常左右滑動翻頁
- 頁碼指示正確更新
- `flutter test` 通過、`flutter analyze` 乾淨
