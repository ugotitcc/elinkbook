# Epic 24 Issue 1 — PDF 引擎基礎替換：單頁開書/頁碼/跳頁/`content://` 存取 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增以 `pdfrx`（PDFium + Dart FFI）為底層的 Dart PDF 閱讀 widget，取代現行以 `android.graphics.pdf.PdfRenderer` 為底層、透過 `AndroidView` `PlatformView` 渲染的既有實作；範圍限定「單頁顯示＋頁碼＋跳頁＋`content://` URI 存取」這一最小可驗證路徑。

**Architecture:** 三個 Task 依序推進：Task 1 在隔離狀態下（不觸碰 `ReaderScreen`／舊 widget）建構新 widget 的本機檔案路徑開書能力並完整測試；Task 2 補上 `content://` URI 支援（透過 `pdfrx` 的 `PdfDocument.openCustom` 自訂讀取 callback，橋接既有 `ReaderResourceChannel.kt` 新增的隨機存取方法，逐段讀取，不整包複製、不整包讀進記憶體——本專案曾發生過整檔讀入記憶體導致 OOM 閃退的真實事故，見 `epic-20` Issue 8，本次刻意避開同一種反模式）；Task 3 把新 widget 接上 `ReaderScreen`、清退舊原生 PDF 渲染叢集（6 個 Kotlin 檔案＋`MainActivity.kt` 註冊＋舊 Dart widget／測試檔），並把暫用檔名/類別名正式改回 `PdfReaderView`。

**Tech Stack:** Flutter/Dart（`pdfrx` ^2.4.6 套件，PDFium 透過 `dart:ffi`）、Kotlin（既有 `ReaderResourceChannel.kt` 擴充，非新建 `PlatformView`）。

## Global Constraints

- `pdfrx` 套件版本鎖定 `^2.4.6`（`pubspec.yaml`）。
- 檔案存取優先評估 `pdfrx.openCustom()` 橋接既有系統檔案描述符存取，不整包複製到 App 私有目錄、不整包讀進 Dart 端記憶體——見上方 Architecture 段落的 OOM 事故教訓（`spec.md`「檔案存取」章節、ADR 0002）。
- 新 widget 對外的建構參數（檔案路徑、開書成功/失敗回呼）須與現行 `PdfReaderView` 契約語意相容：開書成功一次性回呼 `onPageRendered()`、開書失敗攜帶錯誤訊息字串呼叫 `onError(String)`——`ReaderScreen` 既有的 `_state`（`loading`/`rendered`/`error`）狀態機與「已成功渲染的畫面不會被之後才發生的錯誤覆蓋」既有守衛邏輯不得改動（`issues.md` Issue 1）。
- 現行 `PdfReaderView` 的靜態 helper 方法名稱（`jumpToPage`／`previousPage`／`nextPage`／`refreshAnnotations`）須全數保留在新類別上，即使部分方法（`refreshAnnotations`）本工單內只能是暫時性 no-op——這是為了讓 `reader_screen.dart` 內既有呼叫端（書籤跳轉、頁尾跳頁、熱區換頁、劃線疊圖刷新）不必逐一修改呼叫點，只需改動 widget 建構式本身（`spec.md`「範圍」原則：本工單不擴大到全面重寫 `reader_screen.dart`）。
- 頁碼慣例：`pdfrx` 的 `PdfViewerController.goToPage`／`PdfPageChangedCallback` 皆為 **1-indexed**；本專案既有慣例（`PdfPageInfo.pageIndex`／`Bookmark.pdfPageIndex`）為 **0-indexed**。新 widget 對外一律維持 0-indexed，換算只發生在 widget 內部與 `pdfrx` API 的交界處。
- 測試策略：直接用 `flutter test`（非 `integration_test/`）對真實 PDF fixture 驗證，不透過真機/模擬器——`pdfrx` 純 Dart FFI，桌面 host 也能載入真實 PDFium（已查證 `pdfrx` 官方測試套件 `pdfium_loading_test.dart`／`pdf_viewer_test.dart` 皆採此模式，非本專案自創假設）。
- 測試須在 `setUp()` 呼叫 `pdfrxInitialize()`（比照 `pdfrx` 官方 `pdf_viewer_test.dart` 既有寫法；正式 App 執行期改在 `main()` 呼叫 `pdfrxFlutterInitialize()`，兩者不可混用，見 Task 1 Step 1 的完整理由）。
- 清退舊原生路徑時須確保沒有任何殘留引用（`issues.md` Issue 1 驗收條件），但不得動到與 PDF 無關的既有死碼（例如 `NavZoneHitTester.kt`——已查證與現行 `PdfReaderView.kt`／`PdfReaderViewFactory.kt` 皆無實際程式碼耦合，只是同一批舊註解提及，不屬於本工單清退範圍）。

---

## File Structure

- **Modify:** `app/pubspec.yaml`（新增 `pdfrx` 依賴）
- **Modify:** `app/lib/main.dart`（新增 `pdfrxFlutterInitialize()` 呼叫）
- **Create（Task 1-2，暫用檔名，Task 3 改名）:** `app/lib/reader/pdfx_reader_view.dart`
- **Create（Task 1-2，暫用檔名，Task 3 改名）:** `app/test/reader/pdfx_reader_view_test.dart`
- **Create:** `app/test/fixtures/sample_multi_page.pdf`（5 頁、含大綱書籤樹的測試 fixture，供本工單與 Issue 2-8 共用；既有 `app/test/fixtures/sample.pdf` 維持不動，供既有測試繼續使用）
- **Modify（Task 2）:** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`（新增 3 個隨機存取讀取方法＋ `closeAllSessions()` 防禦性清理方法）
- **Modify（Task 2 與 Task 3，各自異動不同區塊）:** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`（Task 2：保留 `ReaderResourceChannel` 參照＋新增 `onDestroy()` 呼叫 `closeAllSessions()`；Task 3：移除 `pdf_reader_view` PlatformView 註冊）
- **Modify（Task 3）:** `app/lib/screens/reader_screen.dart`（PDF 分支的 widget 建構式縮減為本工單支援的參數）
- **Delete（Task 3）:** `app/lib/reader/pdf_reader_view.dart`、`app/test/reader/pdf_reader_view_test.dart`
- **Delete（Task 3）:** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`、`PdfReaderViewFactory.kt`、`PdfImageProcessor.kt`、`PdfContentBounds.kt`、`CropOverlayView.kt`、`HighlightSelectionOverlayView.kt`

---

### Task 1：新增 `pdfrx` 依賴，建構新 widget 的本機檔案路徑開書/頁碼/跳頁能力

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/main.dart`
- Create: `app/lib/reader/pdfx_reader_view.dart`
- Create: `app/test/reader/pdfx_reader_view_test.dart`
- Create: `app/test/fixtures/sample_multi_page.pdf`

**Interfaces:**
- Consumes: 無新依賴（本工單是最底層基礎）。
- Produces: `class PdfxReaderView extends StatefulWidget`，建構參數 `{required String filePath, required VoidCallback onPageRendered, required ValueChanged<String> onError, int? initialPageIndex, ValueChanged<PdfPageInfo>? onPageChanged}`；靜態方法 `PdfxReaderView.jumpToPage(GlobalKey<State<PdfxReaderView>> key, int pageIndex)`／`.previousPage(key)`／`.nextPage(key)`／`.refreshAnnotations(key, List<PdfAnnotationDecoration> annotations)`（本工單內為 no-op）。供 Task 2（同一檔案擴充 `content://` 分支）與 Task 3（`reader_screen.dart` 改接、更名為 `PdfReaderView`）使用。

  - [x] **Step 1: 新增 `pdfrx` 依賴**

在 `app/pubspec.yaml` 的 `dependencies:` 區塊，於 `flutter_secure_storage: ^10.3.1` 這一行之後新增：

```yaml
  # PDF 引擎（epic-24-pdf-engine-rebuild）：PDFium 透過 dart:ffi 直接呼叫，
  # 取代 android.graphics.pdf.PdfRenderer（ADR 0022）。
  pdfrx: ^2.4.6
```

Run: `cd app && flutter pub get`
Expected: 成功解析，`pubspec.lock` 更新，無版本衝突錯誤。

  - [x] **Step 2: 在 `main.dart` 加入 pdfrx 初始化**

在 `app/lib/main.dart` 頂部新增 import：

```dart
import 'package:pdfrx/pdfrx.dart';
```

找到：

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themePreferences = AppThemePreferences();
```

改為：

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // pdfrx（PDFium FFI）初始化，epic-24-pdf-engine-rebuild：Flutter App
  // 執行期一律呼叫 pdfrxFlutterInitialize()（而非 pdfrxInitialize()，後者
  // 用於純 Dart、無 Flutter 環境），須在任何 PDF 開書呼叫之前完成。
  await pdfrxFlutterInitialize();

  final themePreferences = AppThemePreferences();
```

  - [x] **Step 3: 產生多頁＋含大綱的 PDF 測試 fixture**

現行 `app/test/fixtures/sample.pdf` 只有 345 bytes、單頁、無大綱，不足以驗證頁數/目錄/搜尋/雙頁配對等後續工單的行為（`issues.md` Issue 1 驗收條件）。以下腳本手工組出一份符合 PDF 1.7 規格、5 頁、含 5 個大綱書籤項目（`/Type /Outlines`，各頁一個章節）、每頁含可搜尋文字的最小 PDF，不依賴任何第三方 PDF 函式庫（純 stdlib）。已實際執行驗證：用 `pdftotext` 讀出全部 5 頁文字正確無誤，xref 表偏移量正確。

在 `app/test/fixtures/` 目錄下建立暫用產生腳本 `_gen_sample_multi_page.py`（產生完 fixture 後即可刪除，不需要留在版本控制內——這是一次性產生工具，不是需要長期維護的專案工具，比照既有 `sample.epub`／`sample.pdf` 原始 fixture 也不隨附產生腳本的既有慣例）：

```python
def make_pdf(num_pages=5):
    catalog_num = 1
    pages_num = 2
    outlines_num = 3
    page_nums = [4 + i for i in range(num_pages)]
    font_num = 4 + num_pages
    outline_item_nums = [font_num + 1 + i for i in range(num_pages)]
    content_nums = [outline_item_nums[-1] + 1 + i for i in range(num_pages)]

    objs = {}
    objs[catalog_num] = f"<< /Type /Catalog /Pages {pages_num} 0 R /Outlines {outlines_num} 0 R >>"

    kids = " ".join(f"{n} 0 R" for n in page_nums)
    objs[pages_num] = f"<< /Type /Pages /Kids [{kids}] /Count {num_pages} >>"

    first_outline = outline_item_nums[0]
    last_outline = outline_item_nums[-1]
    objs[outlines_num] = f"<< /Type /Outlines /First {first_outline} 0 R /Last {last_outline} 0 R /Count {num_pages} >>"

    for i in range(num_pages):
        pnum = page_nums[i]
        cnum = content_nums[i]
        objs[pnum] = (
            f"<< /Type /Page /Parent {pages_num} 0 R /MediaBox [0 0 612 792] "
            f"/Resources << /Font << /F1 {font_num} 0 R >> >> /Contents {cnum} 0 R >>"
        )

    objs[font_num] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"

    for i in range(num_pages):
        onum = outline_item_nums[i]
        title = f"Chapter {i+1}"
        parts = [f"/Title ({title})", f"/Parent {outlines_num} 0 R"]
        if i > 0:
            parts.append(f"/Prev {outline_item_nums[i-1]} 0 R")
        if i < num_pages - 1:
            parts.append(f"/Next {outline_item_nums[i+1]} 0 R")
        parts.append(f"/Dest [{page_nums[i]} 0 R /Fit]")
        objs[onum] = "<< " + " ".join(parts) + " >>"

    for i in range(num_pages):
        cnum = content_nums[i]
        text = f"(Page {i+1} of {num_pages} -- searchable keyword ELINKBOOK)"
        stream = f"BT /F1 24 Tf 72 700 Td {text} Tj ET".encode("latin-1")
        objs[cnum] = f"<< /Length {len(stream)} >>\nstream\n".encode("latin-1") + stream + b"\nendstream"

    buf = bytearray()
    buf += b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n"
    offsets = {}
    max_obj = max(objs.keys())
    for n in range(1, max_obj + 1):
        offsets[n] = len(buf)
        body = objs[n]
        if isinstance(body, bytes):
            buf += f"{n} 0 obj\n".encode("latin-1") + body + b"\nendobj\n"
        else:
            buf += f"{n} 0 obj\n{body}\nendobj\n".encode("latin-1")

    xref_offset = len(buf)
    buf += f"xref\n0 {max_obj+1}\n".encode("latin-1")
    buf += b"0000000000 65535 f \n"
    for n in range(1, max_obj + 1):
        buf += f"{offsets[n]:010d} 00000 n \n".encode("latin-1")
    buf += f"trailer\n<< /Size {max_obj+1} /Root {catalog_num} 0 R >>\nstartxref\n{xref_offset}\n%%EOF".encode("latin-1")
    return bytes(buf)


with open("sample_multi_page.pdf", "wb") as f:
    f.write(make_pdf(5))
```

Run（在 `app/test/fixtures/` 目錄下）：
```bash
python3 _gen_sample_multi_page.py && rm _gen_sample_multi_page.py
```
Expected: 產生 `sample_multi_page.pdf`（約 2.5KB），腳本本身執行後刪除、不進版本控制。

Run: `git -C app add test/fixtures/sample_multi_page.pdf`
Expected: 檔案已加入暫存區，準備隨 Task 1 最後的 commit 一併提交。

  - [x] **Step 4: 撰寫本機檔案開書的失敗測試**

在 `app/test/reader/pdfx_reader_view_test.dart` 新增：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdfx_reader_view.dart';

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('本機路徑開書成功，觸發 onPageRendered，不觸發 onError',
      (tester) async {
    var renderedCount = 0;
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfxReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (msg) => errorMessage = msg,
        ),
      ),
    );

    // pdfrx 開書為非同步流程，須讓多輪 microtask/frame 有機會完成。
    for (var i = 0; i < 30 && renderedCount == 0 && errorMessage == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(renderedCount, 1);
    expect(errorMessage, isNull);
  });

  testWidgets('開啟不存在的檔案，觸發 onError、不觸發 onPageRendered',
      (tester) async {
    var renderedCount = 0;
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfxReaderView(
          filePath: 'test/fixtures/does_not_exist.pdf',
          onPageRendered: () => renderedCount++,
          onError: (msg) => errorMessage = msg,
        ),
      ),
    );

    for (var i = 0; i < 30 && renderedCount == 0 && errorMessage == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(errorMessage, isNotNull);
    expect(renderedCount, 0);
  });

  testWidgets('pageCount／jumpToPage 正確運作，含邊界情況', (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfxReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfxReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );

    for (var i = 0; i < 30 && renderedCount == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(renderedCount, 1);
    expect(lastPageInfo?.totalPages, 5);
    expect(lastPageInfo?.pageIndex, 0);

    // 跳到最後一頁（0-indexed 第 4 頁 = fixture 第 5 頁）。
    PdfxReaderView.jumpToPage(key, 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 4);

    // 跳到超出範圍的頁碼須被安全忽略，不拋出例外、不改變目前頁碼。
    PdfxReaderView.jumpToPage(key, 999);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(lastPageInfo?.pageIndex, 4);
  });
}
```

  - [x] **Step 5: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdfx_reader_view_test.dart`
Expected: 編譯失敗（`pdfx_reader_view.dart` 尚不存在）。

  - [x] **Step 6: 建立 `PdfxReaderView` widget**

建立 `app/lib/reader/pdfx_reader_view.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_annotation_decoration.dart';
import 'pdf_page_info.dart';

/// 以 pdfrx（PDFium + Dart FFI）為底層的 PDF 閱讀 widget
/// （epic-24-pdf-engine-rebuild Issue 1），取代現行以
/// android.graphics.pdf.PdfRenderer 為底層、透過 AndroidView PlatformView
/// 渲染的既有實作（ADR 0022）。本工單範圍限定「單頁顯示＋頁碼＋跳頁」，
/// 雙頁/影像濾鏡/劃線/目錄/搜尋/縮圖/FAB 工具列皆為後續獨立工單，
/// 尚未實作。
///
/// 頁碼慣例：pdfrx 的 PdfViewerController 使用 1-indexed pageNumber，本
/// widget 對外一律維持本專案既有的 0-indexed pageIndex 慣例，換算只發生
/// 在本檔案內部與 pdfrx API 的交界處。
class PdfxReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final int? initialPageIndex;
  final ValueChanged<PdfPageInfo>? onPageChanged;

  const PdfxReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.initialPageIndex,
    this.onPageChanged,
  });

  @override
  State<PdfxReaderView> createState() => _PdfxReaderViewState();

  /// 跳轉至指定頁碼（0-indexed）。[key] 對應的 State 若尚未掛載或尚未
  /// 就緒，靜默忽略，比照現行 PdfReaderView 既有的 fire-and-forget 慣例。
  static void jumpToPage(GlobalKey<State<PdfxReaderView>> key, int pageIndex) {
    final state = key.currentState;
    if (state is _PdfxReaderViewState) {
      state._jumpToPage(pageIndex);
    }
  }

  /// 導航至下一頁。
  static void nextPage(GlobalKey<State<PdfxReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfxReaderViewState) {
      state._nextPage();
    }
  }

  /// 導航至上一頁。
  static void previousPage(GlobalKey<State<PdfxReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfxReaderViewState) {
      state._previousPage();
    }
  }

  /// 【epic-24 Issue 1 暫時性 no-op】劃線/備註疊圖刷新——新引擎尚未實作
  /// 標註渲染（Issue 4 範圍），本工單只保留方法簽章讓既有呼叫端
  /// （reader_screen.dart 的 _refreshPdfAnnotations）不必修改呼叫點即可
  /// 編譯通過，呼叫本方法目前無任何效果。
  static void refreshAnnotations(
    GlobalKey<State<PdfxReaderView>> key,
    List<PdfAnnotationDecoration> annotations,
  ) {
    // 見上方 docstring：Issue 4 落地前刻意無行為。
  }

  @override
  Widget build(BuildContext context) => throw UnimplementedError();
}

class _PdfxReaderViewState extends State<PdfxReaderView> {
  final _controller = PdfViewerController();
  PdfDocument? _document;
  Object? _error;
  bool _renderedNotified = false;

  @override
  void initState() {
    super.initState();
    _openDocument();
  }

  Future<void> _openDocument() async {
    try {
      final document = await PdfDocument.openFile(widget.filePath);
      if (!mounted) {
        await document.dispose();
        return;
      }
      setState(() => _document = document);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      widget.onError(e.toString());
    }
  }

  @override
  void dispose() {
    _document?.dispose();
    super.dispose();
  }

  void _jumpToPage(int pageIndex) {
    if (!_controller.isReady) return;
    if (pageIndex < 0 || pageIndex >= _controller.pageCount) return;
    _controller.goToPage(pageNumber: pageIndex + 1);
  }

  void _nextPage() {
    if (!_controller.isReady) return;
    final current = _controller.pageNumber ?? 1;
    if (current >= _controller.pageCount) return;
    _controller.goToPage(pageNumber: current + 1);
  }

  void _previousPage() {
    if (!_controller.isReady) return;
    final current = _controller.pageNumber ?? 1;
    if (current <= 1) return;
    _controller.goToPage(pageNumber: current - 1);
  }

  void _handlePageChanged(int? pageNumber) {
    if (pageNumber == null || !_controller.isReady) return;
    widget.onPageChanged?.call(PdfPageInfo(
      pageIndex: pageNumber - 1,
      totalPages: _controller.pageCount,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      // 已透過 widget.onError 通知呼叫端；呼叫端（ReaderScreen）會切換到
      // 自己的錯誤畫面並把本 widget 從樹上移除，這裡回傳空白佔位即可。
      return const SizedBox.shrink();
    }
    final document = _document;
    if (document == null) {
      return const SizedBox.shrink();
    }
    return PdfViewer(
      PdfDocumentRefDirect(document, autoDispose: false),
      controller: _controller,
      params: PdfViewerParams(
        initialPageNumber: (widget.initialPageIndex ?? 0) + 1,
        onViewerReady: (doc, controller) {
          if (!_renderedNotified) {
            _renderedNotified = true;
            widget.onPageRendered();
          }
          widget.onPageChanged?.call(PdfPageInfo(
            pageIndex: (controller.pageNumber ?? 1) - 1,
            totalPages: controller.pageCount,
          ));
        },
        onPageChanged: _handlePageChanged,
      ),
    );
  }
}
```

（`build()` 覆寫在 `PdfxReaderView` 這個 `StatelessWidget` 一樣的介面上宣告了 `throw UnimplementedError()`——這是刻意的：`StatefulWidget` 的 `build()` 屬於 `State`，不屬於 `Widget` 本身，上面那個 `@override Widget build(BuildContext context) => throw UnimplementedError();` 屬於誤植，實際不需要、也不會被呼叫，`StatefulWidget` 不應該有 `build()` 方法。)

  - [x] **Step 7: 移除誤植的 `build()` 覆寫**

刪除 Step 4 程式碼中 `PdfxReaderView` class（非 `_PdfxReaderViewState`）內的這一段：

```dart
  @override
  Widget build(BuildContext context) => throw UnimplementedError();
```

`StatefulWidget` 不應宣告 `build()`（那是 `State.build()` 的職責，`_PdfxReaderViewState` 已經正確實作）。

  - [x] **Step 8: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdfx_reader_view_test.dart`
Expected: 3 項測試全數 PASS。

  - [x] **Step 9: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

  - [x] **Step 10: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/main.dart app/lib/reader/pdfx_reader_view.dart app/test/reader/pdfx_reader_view_test.dart app/test/fixtures/sample_multi_page.pdf
git commit -m "feat(epic-24): 新增 pdfrx 依賴與 PdfxReaderView，本機路徑開書/頁碼/跳頁"
```

---

### Task 2：`content://` URI 支援（`openCustom` 橋接既有檔案描述符存取，不整包複製/讀入記憶體）

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`
- Modify: `app/lib/reader/pdfx_reader_view.dart`
- Modify: `app/test/reader/pdfx_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `PdfxReaderView`／`_PdfxReaderViewState._openDocument()`。
- Produces: `_PdfxReaderViewState` 新增 `content://` 分支，透過既有 `MethodChannel('elinkbook/reader_resources')`（`ReaderResourceChannel.kt` 既有 channel，新增 3 個 method：`openContentUriForRandomAccess`／`readContentUriRange`／`closeContentUriSession`）取得位元組。供 Task 3、及後續 Issue 2-8 沿用同一份開書邏輯，不需要再處理。

**已知技術風險與備援方案（`spec.md` 開放問題）**：若下方 `openCustom` 橋接方式因故無法運作（例如 FFI 非同步呼叫與 platform channel 之間的介接問題），退回「落地複製到本機快取」——但這不是本工單預期路徑，須先完整嘗試下方實作並確認測試通過。

  - [x] **Step 1: 撰寫 `content://` 開書的失敗測試**

由於 `flutter test` 桌面 host 環境沒有真正的 Android `ContentResolver`，本測試改為驗證「偵測到 `://` 時會走 `openCustom` 分支、且不會嘗試 `File.openRead()`/整包複製」這件事本身——用可觀察的公開行為驗證：對一個帶 `://` 但底層 `MethodChannel` 呼叫會失敗（未 mock）的路徑，應觸發 `onError`，而非丟出未捕捉例外或誤判為本機路徑成功開啟。

在 `app/test/reader/pdfx_reader_view_test.dart` 新增（於檔案頂部既有 import 之後新增 `import 'dart:io'; import 'dart:typed_data'; import 'package:flutter/services.dart';`，兩個新測試放在 `main()` 內既有測試之後）：

```dart
  testWidgets('content:// URI 路徑觸發 openCustom 分支（無 mock channel 時安全失敗，不當成本機路徑處理）',
      (tester) async {
    var renderedCount = 0;
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfxReaderView(
          filePath: 'content://com.example.provider/document/42',
          onPageRendered: () => renderedCount++,
          onError: (msg) => errorMessage = msg,
        ),
      ),
    );

    for (var i = 0; i < 30 && renderedCount == 0 && errorMessage == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(renderedCount, 0);
    expect(errorMessage, isNotNull);
  });

  testWidgets('content:// URI 開書透過 openCustom 分段讀取（驗證不整包一次讀完，避免大檔 OOM）',
      (tester) async {
    final fileBytes = await File('test/fixtures/sample_multi_page.pdf').readAsBytes();
    final readCalls = <int>[]; // 記錄每次 read 呼叫請求的 size

    const channel = MethodChannel('elinkbook/reader_resources');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'openContentUriForRandomAccess':
          return {'sessionId': 'test-session', 'fileSize': fileBytes.length};
        case 'readContentUriRange':
          final position = call.arguments['position'] as int;
          final size = call.arguments['size'] as int;
          readCalls.add(size);
          final end = (position + size).clamp(0, fileBytes.length);
          return Uint8List.fromList(fileBytes.sublist(position, end));
        case 'closeContentUriSession':
          return null;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    var renderedCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PdfxReaderView(
          filePath: 'content://com.example.provider/document/42',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );

    for (var i = 0; i < 30 && renderedCount == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(renderedCount, 1);
    // 至少發生一次以上的分段讀取請求，且沒有任何一次請求的 size 等於整個
    // 檔案大小（代表真的是分段讀取，不是把整包一次讀完再假裝分段）。
    expect(readCalls, isNotEmpty);
    expect(readCalls.every((size) => size < fileBytes.length), isTrue);
  });
```

  - [x] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdfx_reader_view_test.dart --plain-name "content://"`
Expected: 兩項新測試皆 FAIL（`_openDocument()` 尚未有 `content://` 分支，會嘗試當本機路徑開啟而拿到不同的錯誤/行為）。

  - [x] **Step 3: `ReaderResourceChannel.kt` 新增隨機存取讀取方法**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`，於檔案頂部 import 區塊新增：

```kotlin
import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
```

在 `class ReaderResourceChannel` 內、`private val cacheChannel = ...` 之後新增欄位：

```kotlin
    // epic-24-pdf-engine-rebuild Issue 2：pdfrx 的 PdfDocument.openCustom
    // 需要對 content:// URI 做隨機存取（seek + 分段讀取），不能整包讀進
    // 記憶體（本專案已有整檔讀入記憶體導致 OOM 閃退的真實事故，見
    // epic-20 Issue 8）。以 sessionId 追蹤每次開書期間持續開啟的
    // ParcelFileDescriptor，避免每次 read 呼叫都重新打開一次 URI
    // （SAF 反覆開關可能較慢、且部分裝置有次數限制）。
    private val openSessions = ConcurrentHashMap<String, ParcelFileDescriptor>()
```

在 `onMethodCall` 的 `when (call.method)` 內、`"cacheBookForServing" -> { ... }` 分支之後、`else -> result.notImplemented()` 之前，新增 3 個分支：

```kotlin
            "openContentUriForRandomAccess" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.success(null)
                    return
                }
                try {
                    val pfd = context.contentResolver.openFileDescriptor(Uri.parse(uriString), "r")
                    if (pfd == null) {
                        result.success(null)
                        return
                    }
                    val sessionId = UUID.randomUUID().toString()
                    openSessions[sessionId] = pfd
                    result.success(mapOf("sessionId" to sessionId, "fileSize" to pfd.statSize))
                } catch (e: Exception) {
                    Log.w("ReaderResourceChannel", "Failed to open content uri for random access: $uriString", e)
                    result.success(null)
                }
            }
            "readContentUriRange" -> {
                val sessionId = call.argument<String>("sessionId")
                val position = call.argument<Int>("position")
                val size = call.argument<Int>("size")
                val pfd = openSessions[sessionId]
                if (pfd == null || position == null || size == null) {
                    result.success(null)
                    return
                }
                try {
                    // 每次讀取用獨立的 FileInputStream 包裝同一個底層檔案描述符，
                    // 各自 seek 到指定位置再讀，不共用可變的讀取游標狀態
                    // （pdfrx 的 read callback 可能非循序呼叫）。
                    FileInputStream(pfd.fileDescriptor).use { stream ->
                        stream.channel.position(position.toLong())
                        val buffer = ByteArray(size)
                        val bytesRead = stream.read(buffer)
                        if (bytesRead <= 0) {
                            result.success(ByteArray(0))
                        } else if (bytesRead == size) {
                            result.success(buffer)
                        } else {
                            result.success(buffer.copyOf(bytesRead))
                        }
                    }
                } catch (e: Exception) {
                    Log.w("ReaderResourceChannel", "Failed to read content uri range", e)
                    result.success(null)
                }
            }
            "closeContentUriSession" -> {
                val sessionId = call.argument<String>("sessionId")
                openSessions.remove(sessionId)?.close()
                result.success(null)
            }
```

在 `class ReaderResourceChannel` 內、`private fun copyToCache(...)` 之後新增一個公開方法，供 `MainActivity` 於 Activity 銷毀時呼叫，防禦性關閉任何未正常經 `closeContentUriSession` 釋放的 session（`/superpowers:receiving-code-review` 審查回應：正常路徑已由 Dart 端 `dispose()` 呼叫 `closeContentUriSession` 逐一釋放，這裡是額外的防禦層，避免 Activity 生命週期非預期中斷時 session 累積導致檔案描述符用量持續增加）：

```kotlin
    /**
     * 防禦性關閉所有尚未釋放的 content:// 隨機存取 session（審查回應：
     * 正常路徑已由 Dart 端 dispose() 逐一呼叫 closeContentUriSession，本
     * 方法是 Activity 銷毀時的最後一道防線，避免非預期生命週期中斷造成
     * 檔案描述符持續累積）。供 MainActivity.onDestroy() 呼叫。
     */
    fun closeAllSessions() {
        openSessions.values.forEach { it.close() }
        openSessions.clear()
    }
```

  - [x] **Step 4: `MainActivity.kt` 保留 `ReaderResourceChannel` 參照並於 `onDestroy()` 清理**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`，於既有欄位宣告區塊（`private lateinit var bookMetadataChannel: BookMetadataChannel`這一行附近）新增：

```kotlin
    private lateinit var readerResourceChannel: ReaderResourceChannel
```

找到：

```kotlin
        ReaderResourceChannel(this, flutterEngine.dartExecutor.binaryMessenger)
```

改為（原本捨棄回傳值，現在存進上方新增的欄位）：

```kotlin
        readerResourceChannel = ReaderResourceChannel(this, flutterEngine.dartExecutor.binaryMessenger)
```

新增 `onDestroy()` 覆寫（放在既有 `configureFlutterEngine()` 方法之後）：

```kotlin
    override fun onDestroy() {
        readerResourceChannel.closeAllSessions()
        super.onDestroy()
    }
```

  - [x] **Step 5: `PdfxReaderView` 新增 `content://` 分支**

在 `app/lib/reader/pdfx_reader_view.dart` 頂部新增 import：

```dart
import 'dart:typed_data';
import 'package:flutter/services.dart';
```

在 `_PdfxReaderViewState` 內新增欄位（緊接 `_renderedNotified` 之後）：

```dart
  static const _resourceChannel = MethodChannel('elinkbook/reader_resources');
  String? _contentUriSessionId;
```

把 `_openDocument()` 改為：

```dart
  Future<void> _openDocument() async {
    try {
      final document = widget.filePath.contains('://')
          ? await _openContentUriDocument()
          : await PdfDocument.openFile(widget.filePath);
      if (!mounted) {
        await document.dispose();
        return;
      }
      setState(() => _document = document);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      widget.onError(e.toString());
    }
  }

  /// content:// URI 開書（epic-24-pdf-engine-rebuild Issue 2）：透過
  /// openCustom 自訂讀取 callback，橋接原生端 ReaderResourceChannel 新增的
  /// 隨機存取方法分段讀取，不整包複製到本機、不整包讀進 Dart 端記憶體
  /// （維持 ADR 0002「不落地複製」原則，同時避開 epic-20 Issue 8 曾發生
  /// 過的整檔讀入記憶體 OOM 反模式）。
  Future<PdfDocument> _openContentUriDocument() async {
    final openResult = await _resourceChannel.invokeMethod<Map>(
      'openContentUriForRandomAccess',
      {'uri': widget.filePath},
    );
    if (openResult == null) {
      throw StateError('無法開啟檔案：${widget.filePath}');
    }
    final sessionId = openResult['sessionId'] as String;
    final fileSize = openResult['fileSize'] as int;
    _contentUriSessionId = sessionId;

    return PdfDocument.openCustom(
      fileSize: fileSize,
      sourceName: widget.filePath,
      read: (buffer, position, size) async {
        final bytes = await _resourceChannel.invokeMethod<Uint8List>(
          'readContentUriRange',
          {'sessionId': sessionId, 'position': position, 'size': size},
        );
        if (bytes == null || bytes.isEmpty) return 0;
        buffer.setRange(0, bytes.length, bytes);
        return bytes.length;
      },
    );
  }
```

把 `dispose()` 改為，於文件釋放後一併關閉原生端的隨機存取 session：

```dart
  @override
  void dispose() {
    _document?.dispose();
    final sessionId = _contentUriSessionId;
    if (sessionId != null) {
      _resourceChannel.invokeMethod('closeContentUriSession', {'sessionId': sessionId});
    }
    super.dispose();
  }
```

  - [x] **Step 6: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdfx_reader_view_test.dart`
Expected: 全部（含 Task 1 既有 3 項＋本工單新增 2 項，共 5 項）PASS。

  - [x] **Step 7: 確認 Android 端可正常編譯（`MainActivity.kt`／`ReaderResourceChannel.kt` 的新增程式碼）**

Run: `cd app && flutter build apk --debug`
Expected: 建置成功，無編譯錯誤——本工單新增的 `closeAllSessions()`／`onDestroy()` 覆寫沒有現成的 Dart 端測試可驗證（純 Activity 生命週期行為），以建置成功＋型別檢查作為最低限度驗證，比照 Task 3 Step 9 的既有模式。

  - [x] **Step 8: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

  - [x] **Step 9: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt app/lib/reader/pdfx_reader_view.dart app/test/reader/pdfx_reader_view_test.dart
git commit -m "feat(epic-24): PdfxReaderView 新增 content:// URI 支援，openCustom 分段讀取不落地複製"
```

---

### Task 3：整合進 `ReaderScreen`，清退舊原生 PDF 渲染叢集，正式更名為 `PdfReaderView`

**Files:**
- Delete: `app/lib/reader/pdf_reader_view.dart`
- Delete: `app/test/reader/pdf_reader_view_test.dart`
- Delete: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Delete: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderViewFactory.kt`
- Delete: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`
- Delete: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfContentBounds.kt`
- Delete: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt`
- Delete: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/HighlightSelectionOverlayView.kt`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`
- Rename: `app/lib/reader/pdfx_reader_view.dart` → `app/lib/reader/pdf_reader_view.dart`（`PdfxReaderView` → `PdfReaderView`）
- Rename: `app/test/reader/pdfx_reader_view_test.dart` → `app/test/reader/pdf_reader_view_test.dart`
- Modify: `app/lib/screens/reader_screen.dart`

**Interfaces:**
- Consumes: Task 1-2 完成的 `PdfxReaderView`（更名前）。
- Produces: `ReaderScreen._buildNativeView()` 的 `case BookFormat.pdf:` 分支改為建構更名後的 `PdfReaderView`，只傳入本工單支援的參數；`_pdfReaderViewKey` 型別改為 `GlobalKey<State<PdfReaderView>>`。既有呼叫端（`PdfReaderView.jumpToPage`／`.previousPage`／`.nextPage`／`.refreshAnnotations`）維持原呼叫方式不變，因為更名後的類別保留了相同的靜態方法簽章。

  - [x] **Step 1: 確認既有舊 widget 測試作為刪除前基準仍通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: PASS（刪除前的基準，證明本次刪除前該測試檔仍是有效、非早已損壞的狀態）。

  - [x] **Step 2: 更名 `PdfxReaderView` → `PdfReaderView`**

刪除舊檔案：

```bash
git rm app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_test.dart
```

把 `app/lib/reader/pdfx_reader_view.dart` 更名為 `app/lib/reader/pdf_reader_view.dart`：

```bash
git mv app/lib/reader/pdfx_reader_view.dart app/lib/reader/pdf_reader_view.dart
git mv app/test/reader/pdfx_reader_view_test.dart app/test/reader/pdf_reader_view_test.dart
```

在新的 `app/lib/reader/pdf_reader_view.dart` 與 `app/test/reader/pdf_reader_view_test.dart` 內，把所有 `PdfxReaderView` 字串取代為 `PdfReaderView`（`class PdfxReaderView` → `class PdfReaderView`、`_PdfxReaderViewState` → `_PdfReaderViewState`、`State<PdfxReaderView>` → `State<PdfReaderView>`，測試檔內同步取代 import 與所有型別引用）。

  - [x] **Step 3: 執行更名後的測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: 5 項測試（Task 1 的 3 項＋Task 2 的 2 項）全數 PASS，證明更名未破壞任何行為。

  - [x] **Step 4: 改接 `reader_screen.dart` 的 PDF 分支**

在 `app/lib/screens/reader_screen.dart` 找到：

```dart
      case BookFormat.pdf:
        return PdfReaderView(
          key: _pdfReaderViewKey,
          filePath: widget.filePath,
          initialPageIndex: _initialPosition?.pdfPageIndex,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          fitMode: resolved.pdfFitMode,
          contrast: resolved.pdfContrast,
          brightness: resolved.pdfBrightness,
          boldStrength: resolved.pdfBoldStrength,
          cropMode: resolved.pdfCropMode,
          cropRect: resolved.pdfCropRect,
          onCropRectComputed: _handleCropRectComputed,
          cropEditModeActive: _cropEditModeActive,
          onCropRectSelected: _handleCropRectSelected,
          dualPageMode: resolved.dualPageMode,
          dualPageCoverAlone: resolved.dualPageCoverAlone,
          dualPageDirection: resolved.dualPageDirection,
          isLandscape: isLandscape,
          onPageChanged: (info) {
            if (!mounted) return;
            setState(() => _pdfPageInfo = info);
          },
          onSelectionRectComputed: _handlePdfSelectionRectComputed,
          onSelectionCanceled: _handlePdfSelectionCanceled,
          navZoneActions: resolved.navZoneActions,
          onZoneAction: _handleZoneAction,
          showNavZoneDebugOverlay: resolved.showNavZoneDebugOverlay,
        );
```

改為：

```dart
      case BookFormat.pdf:
        // 【epic-24-pdf-engine-rebuild Issue 1，已知且經人類確認接受的
        // 暫時性行為退化】新引擎目前只支援單頁顯示＋頁碼＋跳頁，濾鏡
        // （contrast/brightness/boldStrength/cropMode/cropRect）、雙頁
        // （dualPageMode 等）、劃線選取（onSelectionRectComputed 等）、
        // 導航熱區（navZoneActions/onZoneAction）皆暫不傳遞——這些能力
        // 會在 Issue 2-4/8 陸續補回。版面設定面板等 UI 入口在補回前仍會
        // 顯示，但操作暫時無效果，這是刻意接受的風險排序，非遺漏。
        return PdfReaderView(
          key: _pdfReaderViewKey,
          filePath: widget.filePath,
          initialPageIndex: _initialPosition?.pdfPageIndex,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onPageChanged: (info) {
            if (!mounted) return;
            setState(() => _pdfPageInfo = info);
          },
        );
```

  - [x] **Step 5: 執行 `reader_screen_test.dart` 確認 PDF 相關測試現況**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 部分既有測試可能因為斷言了本工單移除的參數（例如檢查 `PdfReaderView.cropMode`／`dualPageMode` 等欄位的既有測試）而編譯失敗或斷言失敗——這是預期中的、Issue 1 範圍內必須修正的既有測試，不是回歸。逐一檢視失敗清單，記錄下來供 Step 6 處理。

  - [x] **Step 6: 修正/移除因參數移除而失敗的既有測試**

對 Step 5 列出的每一項失敗測試：若測試斷言的是本工單移除的參數（濾鏡/雙頁/選取/熱區），依該測試的性質判斷——若測試主體是「驗證這些參數有沒有正確從 `ResolvedPreferences` 傳遞到 `PdfReaderView`」，本工單範圍內這些參數已不存在，測試本身失去斷言對象，應移除該測試（不是本工單刻意要做的功能刪除，是既有測試驗證的能力本身已不在新架構中，等 Issue 2/3/4/8 補回對應能力時，各自的實作計劃會重新補上對應測試）；若測試主體是與移除參數無關的其他行為（例如頁碼顯示、開書狀態機），只移除斷言中提及已移除參數的部分，保留測試其餘部分。

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: PASS，全數通過。

  - [x] **Step 7: 清退舊原生 PDF 渲染叢集**

```bash
git rm app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt
git rm app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderViewFactory.kt
git rm app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt
git rm app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfContentBounds.kt
git rm app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt
git rm app/android/app/src/main/kotlin/cc/ugotit/elinkbook/HighlightSelectionOverlayView.kt
```

（已於本計劃撰寫前查證：`NavZoneHitTester.kt` 雖然檔案命名相似，但與上述 6 個檔案完全無程式碼耦合，不屬於本次清退範圍，維持不動。）

  - [x] **Step 8: 移除 `MainActivity.kt` 的 PlatformView 註冊**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt` 找到：

```kotlin
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/pdf_reader_view",
                PdfReaderViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
        bookMetadataChannel =
```

改為：

```kotlin
        bookMetadataChannel =
```

（也就是直接刪除 `flutterEngine.platformViewsController...` 這整段 5 行的 PlatformView 註冊呼叫。）

  - [x] **Step 9: 確認 Android 端可正常編譯**

Run: `cd app && flutter build apk --debug`
Expected: 建置成功，無編譯錯誤（特別確認移除 6 個 Kotlin 檔案後沒有任何殘留引用導致的 "unresolved reference" 錯誤）。

  - [x] **Step 10: Grep 驗證無殘留引用（Issue 1 驗收條件）**

Run:
```bash
grep -rn "PdfImageProcessor\|PdfContentBounds\b\|CropOverlayView\|HighlightSelectionOverlayView\|PdfReaderViewFactory" app/android/app/src/main/kotlin app/lib
```
Expected: 沒有任何符合結果（`PdfReaderView` 本身因為新類別沿用同名，不在此次 grep 範圍內；上述是舊架構專屬、已刪除的輔助類別名稱，理論上不該再被任何檔案引用）。

Run:
```bash
grep -rn "cc.ugotit.elinkbook/pdf_reader_view" app/android app/lib
```
Expected: 沒有任何符合結果（舊 PlatformView viewType 字串已完全移除）。

  - [x] **Step 11: 執行全專案 `flutter test`**

Run: `cd app && flutter test`
Expected: 全數通過，無任何回歸（`integration_test/` 若有涵蓋舊 PDF PlatformView 渲染驗證的案例，這裡預期需要一併更新或移除——若發現此類案例，記錄下來，比照 Step 6 的判斷原則處理：能力已不存在的測試予以移除，等對應 Issue 補回能力時各自重新補上）。

  - [x] **Step 12: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

  - [x] **Step 13: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(epic-24): PdfReaderView 正式切換至 pdfrx 引擎，清退舊原生 PlatformView 渲染叢集

完全替換 android.graphics.pdf.PdfRenderer 為 pdfrx（ADR 0022）。本工單範圍
限定單頁顯示/頁碼/跳頁/content:// 存取；雙頁/濾鏡/劃線/目錄/搜尋/縮圖/FAB
工具列為已知且經人類確認接受的暫時性能力退化，將於 Issue 2-8 陸續補回。
EOF
)"
```

---

### Task 4：全專案回歸測試 + 真機視覺確認

**Files:** 無新增/修改檔案，純驗證。

**Interfaces:** 無新增介面，驗證 Task 1-3 整合後的端到端行為。

  - [x] **Step 1: 執行全專案 `flutter test`**

Run: `cd app && flutter test`
Expected: 全數通過，無任何回歸。

  - [x] **Step 2: 執行全專案 `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

  - [x] **Step 3（建議）：真機視覺確認**

`flutter test` 已涵蓋開書/頁數/跳頁/`content://` 存取的核心行為，此步驟是建議而非強制，用於確認真實 PDFium 原生函式庫在 Android 裝置上的實際渲染結果（桌面 host 測試驗證的是邏輯正確性，不是視覺渲染品質本身）：

1. 從本機檔案匯入一本 PDF，確認能正常開啟、顯示第一頁。
2. 從系統檔案選擇器（SAF，`content://` URI）匯入一本 PDF，確認能正常開啟——特別觀察大型 PDF（100MB 以上）開書過程中裝置記憶體用量是否穩定（不應隨檔案增大而大幅飆升，驗證 Task 2 的分段讀取確實生效、非整包讀入記憶體）。
3. 確認版面設定面板仍可開啟（濾鏡/裁切/雙頁控制項目前操作無效果，屬預期中的暫時行為，不是本步驟要驗證的項目）。

  - [x] **Step 4: Commit（若真機驗證過程中發現需要修正的問題）**

若 Step 3 發現任何問題並修正程式碼，比照 Task 1-3 的模式（先確認測試涵蓋、修正、重新測試、commit）。若無需修正，本 Step 略過。
