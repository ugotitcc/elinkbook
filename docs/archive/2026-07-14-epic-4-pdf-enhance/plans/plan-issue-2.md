# Epic 4 Issue 2 — PDF 設定入口與 Fit 模式端到端 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 PDF 閱讀器擁有第一個版面設定入口——AppBar 齒輪按鈕開啟 `PdfSettingsSheet`，使用者可在「顯示」分頁切換 Page-fit／Fit Width／真實比例 1:1 三種 Fit 模式，設定即時反映且持久化。

**Architecture:** 沿用 `epic-3-fonts-layout` 已驗證的模式（`BookReaderPrefs` 宣告式最終生效值 → `XxxReaderView` 建構參數 → `initialPreferences`/`setXxxPreferences` method channel 契約 → 原生端合併套用）。`PdfSettingsSheet` 是全新獨立 widget（design.md 決策 #10：不與 EPUB 用的 `ReaderSettingsSheet` 共用），本 issue 只完成其「顯示」分頁，「濾鏡」「裁切」分頁留空白佔位供 Issue 3-6 填入。

**Tech Stack:** Flutter/Dart（`TabController`/`AndroidView`/`MethodChannel`）、Kotlin（`ImageView.scaleType`/`Matrix`）。

## Global Constraints

- 所有新增的程式碼註解與文件皆須使用正體中文（zh-TW），不得使用簡體中文。
- `flutter analyze` 全程必須保持乾淨（"No issues found!"）。
- PDF 的 Fit 模式為單書持久化，無全域預設層（design.md 決策 #8），`BookReaderPrefs.pdfFitMode` 為 `PdfFitMode?`，`null` 語意＝`PdfFitMode.pageFit`（已於 Issue 1 定義，見 `app/lib/reader/book_reader_prefs.dart`）。
- `PdfFitMode` 三值（已存在，`app/lib/reader/pdf_fit_mode.dart`）：`pageFit`／`fitWidth`／`actualSize`。
- **本 issue 刻意簡化範圍（已與人類確認）**：`fitWidth`／`actualSize` 若內容超出可視範圍，超出部分**不可捲動**（不新增 `ScrollView` 容器）；真正可捲動的 Fit Width 留待後續 issue 視需求評估。
- AppBar 齒輪按鈕沿用既有 Key `Key('reader_layout_settings_button')`（EPUB／PDF 共用同一顆按鈕、同一個 Key，只是 `onPressed` 依格式分派到不同方法）——這不是新決策，是延續現有程式碼唯一的一顆齒輪按鈕。
- **已知測試限制（沿用既有慣例，見 `app/test/screens/reader_screen_test.dart` 第 133-137 行既有註解）**：純 `flutter test` 環境下 `AndroidView` 不會觸發原生回呼，因此 EPUB 的齒輪按鈕永遠停留在「已渲染」前的停用狀態，「點擊後開啟正確的 Bottom Sheet」這件事只能在 `integration_test`（真實裝置）驗證，flutter widget test 只能驗證「按鈕存在＋初始停用狀態」。PDF 齒輪按鈕比照同一限制。

---

## Task 1: `PdfSettingsSheet`——三分頁骨架＋顯示分頁（Fit 模式）

**Files:**
- Create: `app/lib/screens/pdf_settings_sheet.dart`
- Test: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes: `BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`，已有 `pdfFitMode: PdfFitMode?` 欄位）、`PdfFitMode`（`app/lib/reader/pdf_fit_mode.dart`，已存在）
- Produces: `class PdfSettingsSheet extends StatefulWidget { final BookReaderPrefs prefs; final ValueChanged<BookReaderPrefs> onChanged; const PdfSettingsSheet({super.key, required this.prefs, required this.onChanged}); }`——Task 3（`ReaderScreen`）會直接建構這個 widget 並傳入 `prefs`/`onChanged`。

本任務不涉及 `ReaderScreen`/`PdfReaderView`，可獨立開發與測試（純 Dart widget，無平台通道）。

- [ ] **Step 1: 為顯示分頁的 Fit 模式選擇器寫失敗測試**

建立 `app/test/screens/pdf_settings_sheet_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/screens/pdf_settings_sheet.dart';

void main() {
  testWidgets('三個分頁標籤皆存在', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byKey(const Key('pdf_settings_tab_display')), findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_tab_filters')), findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_tab_crop')), findsOneWidget);
  });

  testWidgets('點擊 Fit Width 選項後，onChanged 帶入 pdfFitMode=fitWidth', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester.tap(find.byKey(const Key('pdf_settings_fit_mode_fit_width')));
    await tester.pump();

    expect(notified?.pdfFitMode, PdfFitMode.fitWidth);
  });

  testWidgets('點擊真實比例 1:1 選項後，onChanged 帶入 pdfFitMode=actualSize',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester.tap(find.byKey(const Key('pdf_settings_fit_mode_actual_size')));
    await tester.pump();

    expect(notified?.pdfFitMode, PdfFitMode.actualSize);
  });

  testWidgets('點擊 Page-fit 選項後，onChanged 帶入 pdfFitMode=pageFit', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfFitMode: PdfFitMode.fitWidth),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_fit_mode_page_fit')));
    await tester.pump();

    expect(notified?.pdfFitMode, PdfFitMode.pageFit);
  });

  testWidgets('prefs.pdfFitMode 為 null 時（未持久化過），不因為初始 build 就觸發 onChanged',
      (tester) async {
    var callCount = 0;
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) => callCount++);

    expect(callCount, 0);
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PdfSettingsSheet(
        prefs: prefs,
        onChanged: onChanged,
      ),
    ),
  ));
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: FAIL（找不到 `lib/screens/pdf_settings_sheet.dart`，編譯錯誤）

- [ ] **Step 3: 實作 `PdfSettingsSheet`**

建立 `app/lib/screens/pdf_settings_sheet.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/book_reader_prefs.dart';
import '../reader/pdf_fit_mode.dart';

/// PDF 專屬版面設定 Bottom Sheet（FR-11），三分頁結構：顯示／濾鏡／裁切，
/// 見 docs/epics/epic-4-pdf-enhance/design.md 決策 #10（不與 EPUB 用的
/// `ReaderSettingsSheet` 共用元件）。本 issue（Issue 2）僅實作「顯示」分頁
/// （Fit 模式三選一）；「濾鏡」「裁切」分頁為 Issue 3-6 預留的空白佔位。
///
/// 純展示、無 I/O：每次選擇立即透過 [onChanged] 回報目前完整的
/// [BookReaderPrefs]（本 issue 只包含 [BookReaderPrefs.pdfFitMode] 欄位，
/// 其餘 PDF 欄位由 Issue 3-6 各自擴充 [_notifyChanged]，比照
/// `ReaderSettingsSheet._notifyChanged` 的既有模式——只需重建目前已追蹤的
/// 本地狀態欄位，因為同一本書不會同時是 EPUB 又是 PDF，未追蹤的欄位維持
/// null 不影響實際使用情境）。持久化由呼叫端（`ReaderScreen`）負責。
class PdfSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;

  const PdfSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
  });

  @override
  State<PdfSettingsSheet> createState() => _PdfSettingsSheetState();
}

class _PdfSettingsSheetState extends State<PdfSettingsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late PdfFitMode _fitMode;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fitMode = widget.prefs.pdfFitMode ?? PdfFitMode.pageFit;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged(BookReaderPrefs(pdfFitMode: _fitMode));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        // TabBarView 無法在無邊界的父層自我量測高度（不同於 ReaderSettingsSheet
        // 用 ListView(shrinkWrap: true) 的做法），固定高度是本 widget 刻意的
        // 簡化選擇。
        height: 400,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('⚙️ PDF 版面設定',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(key: Key('pdf_settings_tab_display'), text: '顯示'),
                Tab(key: Key('pdf_settings_tab_filters'), text: '濾鏡'),
                Tab(key: Key('pdf_settings_tab_crop'), text: '裁切'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDisplayTab(context),
                  _buildPlaceholderTab('濾鏡功能即將推出'),
                  _buildPlaceholderTab('裁切功能即將推出'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplayTab(BuildContext context) {
    const options = [
      (PdfFitMode.pageFit, 'page_fit', Icons.fit_screen, 'Page-fit（整頁）'),
      (PdfFitMode.fitWidth, 'fit_width', Icons.swap_horiz, 'Fit Width（項寬）'),
      (PdfFitMode.actualSize, 'actual_size', Icons.crop_original, '真實比例 1:1'),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fit 模式'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: options.map((option) {
              final (mode, keySuffix, icon, tooltip) = option;
              final selected = _fitMode == mode;
              return IconButton(
                key: Key('pdf_settings_fit_mode_$keySuffix'),
                icon: Icon(icon),
                tooltip: tooltip,
                color: selected ? Theme.of(context).colorScheme.primary : null,
                onPressed: () => setState(() {
                  _fitMode = mode;
                  _notifyChanged();
                }),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderTab(String message) {
    return Center(child: Text(message));
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: PASS（5 個測試全過）

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-4): 新增 PdfSettingsSheet 骨架與顯示分頁（Fit 模式）"
```

---

## Task 2: `PdfReaderView`（Dart＋原生）——fitMode 契約與三種縮放邏輯

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Test: `app/test/reader/pdf_reader_view_test.dart`（新建）

**Interfaces:**
- Consumes: `PdfFitMode`（`app/lib/reader/pdf_fit_mode.dart`，已存在）
- Produces: `PdfReaderView` 新增建構參數 `final PdfFitMode? fitMode;`——Task 3（`ReaderScreen`）會傳入 `_resolvedPdfFitMode`（`PdfFitMode`，非 nullable，`ReaderScreen` 自行解析 `_prefs.pdfFitMode ?? PdfFitMode.pageFit`）。

本任務不涉及 `ReaderScreen`，`PdfReaderView` 本身可獨立開發測試。原生端 Kotlin 邏輯無法透過 `flutter test` 驗證，此限制沿用既有慣例（見 `docs/archive/2026-07-10-epic-3-fonts-layout/issues.md` Issue 2），留給 Task 4 的 `integration_test` 驗證。

- [ ] **Step 1: 為 Dart 端 `initialPreferences`／`setPdfPreferences` 契約寫失敗測試**

建立 `app/test/reader/pdf_reader_view_test.dart`（比照 `app/test/reader/epub_reader_view_test.dart` 的假 `MethodChannel` handler 模式，見該檔案第 10-45 行）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';

/// 驅動 [PdfReaderView] 底層 AndroidView 完成建立流程所需的最小 mock，比照
/// `epub_reader_view_test.dart` 的 `_pumpEpubReaderView` 模式。
Future<List<MethodCall>> _pumpPdfReaderView(
  WidgetTester tester,
  PdfReaderView widget,
) async {
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final instanceCalls = <MethodCall>[];

  binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
      (call) async {
    if (call.method == 'create') {
      final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
      binaryMessenger.setMockMethodCallHandler(
        MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
        (call) async {
          instanceCalls.add(call);
          return null;
        },
      );
      return 0; // textureId
    }
    return null;
  });

  await tester.pumpWidget(MaterialApp(home: widget));
  await tester.pumpAndSettle();
  return instanceCalls;
}

void main() {
  testWidgets('_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含 fitMode',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        fitMode: PdfFitMode.fitWidth,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['path'], '/tmp/sample.pdf');
    expect(openBookCall.arguments['initialPreferences'], {'fitMode': 'fitWidth'});
  });

  testWidgets('fitMode 為 null 時，initialPreferences 為空 map（而非 null）',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], <String, Object?>{});
  });

  testWidgets('fitMode 變動時，didUpdateWidget 呼叫 setPdfPreferences 並帶入新值',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        fitMode: PdfFitMode.pageFit,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        fitMode: PdfFitMode.actualSize, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {'fitMode': 'actualSize'});
  });

  testWidgets('fitMode 未變動時，didUpdateWidget 不觸發任何 setPdfPreferences 呼叫',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    final widget = const PdfReaderView(
      filePath: '/tmp/sample.pdf',
      onPageRendered: _noop,
      onError: _noopError,
      fitMode: PdfFitMode.pageFit,
    );
    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pumpAndSettle();

    expect(instanceCalls, isEmpty);
  });
}

void _noop() {}
void _noopError(String message) {}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: FAIL（`PdfReaderView` 建構子沒有 `fitMode` 具名參數，編譯錯誤）

- [ ] **Step 3: 擴充 Dart 端 `PdfReaderView`**

完整重寫 `app/lib/reader/pdf_reader_view.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pdf_fit_mode.dart';

/// 包裝原生 Android PdfReaderView 的 Flutter widget，透過 AndroidView
/// （PlatformView）嵌入畫面。給定 PDF 檔案的裝置端絕對路徑，通知原生端
/// 渲染第 1 頁；渲染成功或失敗會分別觸發 [onPageRendered] 或 [onError]。
///
/// 支援手勢翻頁：左右滑動可切換頁面，透過 [onNextPage]／[onPreviousPage]
/// 回調通知呼叫端；原生端頁面變更時會觸發 [onPageChanged]。
///
/// [fitMode] 是呼叫端已解析好的最終生效值（`null` 代表使用原生端預設
/// `pageFit`，見 docs/epics/epic-4-pdf-enhance/spec.md）。首次建構時，非
/// null 的偏好參數會組成 `initialPreferences` 隨 `openBook` 一併送出；之後
/// [fitMode] 變動（[didUpdateWidget] 偵測），會透過 `setPdfPreferences`
/// 送出，比照 EpubReaderView 的既有模式（見
/// docs/archive/2026-07-10-epic-3-fonts-layout/spec.md）。
class PdfReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final VoidCallback? onNextPage;
  final VoidCallback? onPreviousPage;
  final ValueChanged<int>? onPageChanged;
  final PdfFitMode? fitMode;

  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onNextPage,
    this.onPreviousPage,
    this.onPageChanged,
    this.fitMode,
  });

  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();
}

class _PdfReaderViewState extends State<PdfReaderView> {
  MethodChannel? _channel;

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    channel.invokeMethod('openBook', {
      'path': widget.filePath,
      'initialPreferences': _buildPreferencesMap(),
    });
  }

  @override
  void didUpdateWidget(covariant PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fitMode != oldWidget.fitMode) {
      _channel?.invokeMethod('setPdfPreferences', _buildPreferencesMap());
    }
  }

  /// 把目前所有非 null 的偏好參數組成一個 map，`null` 值的欄位完全不出現在
  /// map 中，比照 EpubReaderView 的既有模式。
  Map<String, Object?> _buildPreferencesMap() {
    final map = <String, Object?>{};
    if (widget.fitMode != null) map['fitMode'] = widget.fitMode!.name;
    return map;
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPageRendered':
        widget.onPageRendered();
        break;
      case 'onError':
        widget.onError(call.arguments as String);
        break;
      case 'onPageChanged':
        final pageIndex = call.arguments as int;
        widget.onPageChanged?.call(pageIndex);
        break;
    }
  }

  /// 導航至下一頁
  void nextPage() => _channel?.invokeMethod('nextPage');

  /// 導航至上一頁
  void previousPage() => _channel?.invokeMethod('previousPage');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < 0) {
          // 向左滑動 → 下一頁
          nextPage();
        } else if (details.primaryVelocity! > 0) {
          // 向右滑動 → 上一頁
          previousPage();
        }
      },
      child: AndroidView(
        viewType: 'cc.ugotit.elinkbook/pdf_reader_view',
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }
}
```

- [ ] **Step 4: 執行測試確認 Dart 端測試通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: PASS（4 個測試全過）

- [ ] **Step 5: 擴充原生端 `PdfReaderView.kt`**

覆寫前先執行 `git diff app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`（此時應無差異，確認目前工作目錄乾淨）——下方是完整重寫後的檔案內容，已保留既有 `openBook`／`renderCurrentPage`／`nextPage`／`previousPage`／`dispose` 的全部既有邏輯（含 `finally` 區塊的 `pfd?.close()`、`OutOfMemoryError` 的 fallback），僅新增 `fitMode` 欄位、`setPdfPreferences` handler、`applyFitMode()`。完整重寫後執行 `git diff` 比對，確認變動範圍只有新增的部分，既有邏輯逐行一致。

完整重寫 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`：

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
 *
 * 支援手勢翻頁：透過 nextPage／previousPage method channel 指令切換頁面，
 * 頁面變更時觸發 onPageChanged(pageIndex)。
 *
 * 支援 Fit 模式（FR-11，見 docs/epics/epic-4-pdf-enhance/spec.md）：透過
 * openBook 的 initialPreferences 或 setPdfPreferences 指令設定，只調整
 * imageView 的顯示層（scaleType／matrix），不重新解碼 PDF 頁面。
 */
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

    // Dart PdfFitMode.name 對應字串（'pageFit'／'fitWidth'／'actualSize'），
    // 預設 "pageFit"，與 BookReaderPrefs.pdfFitMode 為 null 時的語意一致。
    private var fitMode: String = "pageFit"

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = imageView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                @Suppress("UNCHECKED_CAST")
                openBook(
                    call.argument<String>("path"),
                    call.argument<Map<String, Any?>>("initialPreferences"),
                )
                result.success(null)
            }
            "setPdfPreferences" -> {
                @Suppress("UNCHECKED_CAST")
                setPdfPreferences(call.arguments as? Map<String, Any?>)
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

    /**
     * 合併 [preferences] 到目前生效狀態並套用（目前只有 fitMode 一個欄位，
     * 之後 Issue 3-6 會擴充濾鏡/裁切欄位）。書本尚未成功開啟
     * （renderer 仍為 null）時仍安全執行——applyFitMode() 內部若沒有已渲染
     * 的 bitmap 會靜默不做事。
     */
    private fun setPdfPreferences(preferences: Map<String, Any?>?) {
        if (preferences == null) return
        (preferences["fitMode"] as? String)?.let { fitMode = it }
        applyFitMode()
    }

    private fun openBook(path: String?, initialPreferences: Map<String, Any?>?) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = it }
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
            // 確保任何情況下（含上方例外拋出時）原生資源都會被釋放，避免
            // 檔案描述符/渲染器洩漏。
            try { pfd?.close() } catch (ignored: Exception) {}
        }
    }

    private fun renderCurrentPage() {
        val renderer = renderer ?: return
        val page = renderer.openPage(currentPageIndex)
        
        // 取得螢幕密度（density）來計算高解析度的 Bitmap，至少為 2.0 倍以保證清晰度，最高限制為 3.0 倍以避免 OutOfMemory
        val density = context.resources.displayMetrics.density
        val scale = density.coerceIn(2.0f, 3.0f)
        
        val width = (page.width * scale).toInt()
        val height = (page.height * scale).toInt()
        
        try {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val matrix = android.graphics.Matrix().apply {
                postScale(scale, scale)
            }
            page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            imageView.setImageBitmap(bitmap)
            applyFitMode()
        } catch (e: OutOfMemoryError) {
            // 如果發生 OutOfMemory，回退到原始尺寸渲染以確保不會崩潰
            try {
                val fallbackBitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                page.render(fallbackBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                imageView.setImageBitmap(fallbackBitmap)
                applyFitMode()
            } catch (ignored: Exception) {}
        }
        
        page.close()
    }

    /**
     * 依 [fitMode] 設定 imageView 的 scaleType／matrix，決定已渲染的 bitmap
     * 如何顯示在畫面上（見 docs/epics/epic-4-pdf-enhance/design.md 決策
     * #6/#7/#8）。只調整顯示層，不重新渲染 bitmap，因此可在
     * setPdfPreferences 收到新 fitMode 時單獨呼叫，不需要重新解碼 PDF 頁面。
     *
     * 已知限制（本 issue 刻意簡化範圍，已與人類確認）：fitWidth／actualSize
     * 若內容超出可視範圍，超出部分目前不可捲動（無 ScrollView 容器），留待
     * 後續 issue 視需求評估是否新增捲動能力。
     *
     * 殘餘風險（留待 Task 4 真機驗證確認）：fitWidth 分支依賴
     * imageView.width 在呼叫當下已完成量測；理論上 Flutter 的 hybrid
     * composition 會在建立 PlatformView 時就給定尺寸，但無法單靠原始碼
     * 100% 確認，若真機測試發現首次開書時 fitWidth 沒有立即生效，需回頭
     * 補上 ViewTreeObserver.OnGlobalLayoutListener 之類的重新量測機制。
     */
    private fun applyFitMode() {
        when (fitMode) {
            "fitWidth" -> {
                val viewWidth = imageView.width
                val bitmapWidth = imageView.drawable?.intrinsicWidth ?: 0
                if (viewWidth <= 0 || bitmapWidth <= 0) return
                val scale = viewWidth.toFloat() / bitmapWidth.toFloat()
                imageView.scaleType = ImageView.ScaleType.MATRIX
                imageView.imageMatrix = android.graphics.Matrix().apply { setScale(scale, scale) }
            }
            "actualSize" -> {
                val bitmapWidth = imageView.drawable?.intrinsicWidth ?: 0
                if (bitmapWidth <= 0) return
                val density = context.resources.displayMetrics.density
                // 與 renderCurrentPage() 算 bitmap 尺寸時使用的同一個 scale，
                // 換算回「1 PDF point = 1 dp」的真實顯示比例。【隱式耦合，
                // 修改時務必同步】這裡的 density.coerceIn(2.0f, 3.0f) 必須與
                // renderCurrentPage() 內算 width/height 用的 scale 算式保持
                // 完全一致，否則 actualSize 換算出的比例會失準；若未來調整
                // renderCurrentPage() 的 scale 策略，這裡要同步更新。
                val bitmapRenderScale = density.coerceIn(2.0f, 3.0f)
                val displayScale = density / bitmapRenderScale
                imageView.scaleType = ImageView.ScaleType.MATRIX
                imageView.imageMatrix = android.graphics.Matrix().apply { setScale(displayScale, displayScale) }
            }
            else -> { // "pageFit"（預設）
                imageView.scaleType = ImageView.ScaleType.FIT_CENTER
            }
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

    /**
     * [path] 含 "://" 者一律視為 URI，交給 ContentResolver 開啟（Android
     * 對 file:// scheme 有內建直接處理，不需額外註冊 ContentProvider）；
     * 否則視為檔案系統路徑，沿用既有 ParcelFileDescriptor.open() 邏輯。
     *
     * 已知限制：`contains("://")` 是啟發式判斷，若檔案系統路徑本身恰好含有
     * 這個子字串會被誤判為 URI 而解析失敗。此啟發式假設路徑皆為 Android
     * 慣例格式，在正常使用情境下風險可忽略，記錄於此供未來維護者知悉。
     */
    private fun openParcelFileDescriptor(path: String): ParcelFileDescriptor? {
        return if (path.contains("://")) {
            context.contentResolver.openFileDescriptor(Uri.parse(path), "r")
        } else {
            ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        }
    }

    override fun dispose() {
        renderer?.close()
        renderer = null
        channel.setMethodCallHandler(null)
    }
}
```

- [ ] **Step 6: 編譯驗證（原生端無法用 `flutter test` 驗證邏輯正確性，僅確認可編譯）**

Run: `cd app && flutter build apk --debug`
Expected: BUILD SUCCESSFUL（Kotlin 編譯通過；邏輯正確性留給 Task 4 的 `integration_test`）

- [ ] **Step 7: 重新執行 Dart 端全部測試確認無回歸**

Run: `cd app && flutter test`
Expected: PASS（全部通過，含 Task 1／Task 2 新增的測試）

- [ ] **Step 8: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt app/test/reader/pdf_reader_view_test.dart
git commit -m "feat(epic-4): PdfReaderView 新增 fitMode 契約與原生三種縮放邏輯"
```

---

## Task 3: `ReaderScreen` 整合——齒輪按鈕擴充至 PDF、開書流程載入 Fit 模式

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: `PdfSettingsSheet`（Task 1）、`PdfReaderView.fitMode`（Task 2）、`BookReaderPrefs.pdfFitMode`（Issue 1，已存在）
- Produces: `ReaderScreen` 新增 `PdfFitMode get _resolvedPdfFitMode => _prefs.pdfFitMode ?? PdfFitMode.pageFit;`、`_openPdfSettings()`——後續 issue（3-6）擴充 `PdfSettingsSheet` 時會沿用同一個 `_openPdfSettings()`／既有 `_handlePrefsChanged` 入口，不需要改動 `ReaderScreen` 的分派邏輯。

**設計澄清（與 `spec.md` 原文的一處刻意簡化）**：`spec.md` 原描述新增獨立的 `_handlePdfPrefsChanged(BookReaderPrefs)` 方法。查證現有 `_handlePrefsChanged(BookReaderPrefs prefs)`（`reader_screen.dart` 第 157-161 行）本身格式無關（`setState` 更新 `_prefs` ＋ `prefsRepository.save()` ＋ `_applyScreenOrientation()`），`_applyScreenOrientation()` 對只含 PDF 欄位的 `BookReaderPrefs` 呼叫是安全的空操作（`screenOrientationOverride` 恆為 null，等同未覆寫）。直接重用 `_handlePrefsChanged`，不新增重複邏輯的第二個方法（YAGNI）。

- [ ] **Step 1: 為 PDF 齒輪按鈕與 Fit 模式載入寫失敗測試**

編輯 `app/test/screens/reader_screen_test.dart`。

**先移除**既有的這個測試（PDF 現在應該顯示按鈕，這個測試的前提已不成立）——若檔案因先前異動導致行號偏移，以測試名稱字串 `'PDF 格式不顯示「⚙️版面」按鈕'` 搜尋定位，該測試目前在第 67-82 行：

```dart
  testWidgets('PDF 格式不顯示「⚙️版面」按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    expect(
      find.byKey(const Key('reader_layout_settings_button')),
      findsNothing,
    );
  });
```

**替換為**（緊接在「EPUB 格式顯示「⚙️版面」按鈕，初始為停用狀態」測試之後、原本 PDF 測試的位置）：

```dart
  testWidgets('PDF 格式顯示「⚙️版面」按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    final finder = find.byKey(const Key('reader_layout_settings_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onPageRendered（純 flutter test 環境下 AndroidView 不會'
          '觸發原生回呼），按鈕應為停用狀態，比照 EPUB 齒輪按鈕的既有測試限制'
          '（見本檔案第 46-65 行）',
    );
  });
```

**再新增**（於檔案最後、`}` 之前）以下兩個測試：

```dart
  testWidgets('開啟該書已有的持久化 pdfFitMode 後，PdfReaderView.fitMode 正確載入',
      (tester) async {
    await prefsRepository.save(
      'b1',
      const BookReaderPrefs(pdfFitMode: PdfFitMode.actualSize),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final viewFinder = find.byType(PdfReaderView);
    expect(viewFinder, findsOneWidget);
    final pdfView = tester.widget<PdfReaderView>(viewFinder);
    expect(pdfView.fitMode, PdfFitMode.actualSize);
  });

  testWidgets('尚未持久化 pdfFitMode 時，PdfReaderView.fitMode 採用預設值 pageFit',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.fitMode, PdfFitMode.pageFit);
  });
```

在檔案開頭 import 區塊插入以下 2 行新 import（既有 7 行 import 保留不動，這兩個檔案目前都還沒被 `reader_screen_test.dart` 引入）：

```dart
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: FAIL（「PDF 格式顯示「⚙️版面」按鈕」測試會失敗，因為目前 `_buildAppBarActions` 對 `format == BookFormat.pdf` 仍回傳 `null`；`pdfFitMode` 相關測試會因 `PdfReaderView` 建構時未傳入 `fitMode` 屬性、或 `_resolvedPdfFitMode` 尚不存在而失敗）

- [ ] **Step 3: 修改 `ReaderScreen`**

編輯 `app/lib/screens/reader_screen.dart`。

在檔案開頭 import 區塊新增（保留既有 import 不動）：

```dart
import '../reader/pdf_fit_mode.dart';
```

在 `_resolvedScreenOrientation` getter（第 82-84 行）之後新增：

```dart
  /// Fit 模式最終生效值：單書持久化，無全域預設層（design.md 決策 #8）。
  PdfFitMode get _resolvedPdfFitMode => _prefs.pdfFitMode ?? PdfFitMode.pageFit;
```

把 `_openLayoutSettings()`（第 163-176 行）之後新增一個新方法：

```dart
  void _openPdfSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder: (_) => PdfSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
      ),
    );
  }
```

在檔案開頭 import 區塊新增 `PdfSettingsSheet`（保留既有 `reader_settings_sheet.dart` import 不動）：

```dart
import 'pdf_settings_sheet.dart';
```

把 `_buildAppBarActions`（第 221-236 行）整段改為：

```dart
  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (_isFixedLayout) return null;
    switch (format) {
      case BookFormat.epub:
        return [
          IconButton(
            key: const Key('reader_layout_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '版面設定',
            // _autoDetectedWritingMode 非 null 代表 onLayoutResolved 已觸發，
            // 書本已成功開啟、navigatorFragment 已存在，此時開啟版面設定並
            // 呼叫 setPreferences 才有意義（見 EpubReaderView.kt 的靜默忽略
            // 邏輯說明）。
            onPressed:
                _autoDetectedWritingMode == null ? null : _openLayoutSettings,
          ),
        ];
      case BookFormat.pdf:
        return [
          IconButton(
            key: const Key('reader_layout_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '版面設定',
            // _state == rendered 代表 onPageRendered 已觸發，PDF 已成功
            // 開啟，此時開啟版面設定並呼叫 setPdfPreferences 才有意義，比照
            // EPUB 分支的既有判斷原則。
            onPressed: _state == _RenderState.rendered ? _openPdfSettings : null,
          ),
        ];
      case BookFormat.unknown:
        return null;
    }
  }
```

把 `_buildNativeView` 的 `BookFormat.pdf` 分支（第 305-310 行）改為：

```dart
      case BookFormat.pdf:
        return PdfReaderView(
          filePath: widget.filePath,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          fitMode: _resolvedPdfFitMode,
        );
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全部通過，含既有 EPUB 相關測試不迴歸）

- [ ] **Step 5: 執行全部測試與靜態分析確認無回歸**

Run: `cd app && flutter test && flutter analyze`
Expected: 全部測試通過；`flutter analyze` 顯示 `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-4): ReaderScreen 齒輪按鈕擴充至 PDF，串接 PdfSettingsSheet 與 Fit 模式"
```

---

## Task 4: 真機驗證（integration_test）

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1-3 的全部產出
- Produces: 無（驗證性質收尾任務）

- [ ] **Step 1: 新增真機驗證測試**

編輯 `app/integration_test/reader_screen_test.dart`。

**先修改既有的 `_book()` helper**，讓它可以指定 `format`（目前寫死 `BookFileFormat.epub`，本 issue 新增的 3 個測試會 `insertBook` 一本實際上是 PDF 的書，若不修改會讓測試資料的 `format` 欄位與實際檔案格式不符——雖然 `ReaderScreen` 的實際渲染路徑是靠 `detectBookFormat(filePath)` 依副檔名判斷、不讀這個 DB 欄位，`insertBook` 在這裡純粹是為了滿足 `book_reader_prefs` 的外鍵約束，資料不一致不會造成測試功能性錯誤，但仍是不必要的資料衛生問題，一併修正）：

```dart
Book _book(String id, {BookFileFormat format = BookFileFormat.epub}) => Book(
      id: id,
      title: '書名',
      format: format,
      filePath: 'content://example/$id',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
```

（預設值 `BookFileFormat.epub` 維持既有呼叫端 `_book(id)` 不必修改；`BookFileFormat` 已由既有 `import 'package:elinkbook/library/models/library_enums.dart';` 引入，不需新增 import）

在檔案開頭 import 區塊新增：

```dart
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/screens/pdf_settings_sheet.dart';
```

在檔案最後（`}` 之前，緊接在既有最後一個 `testWidgets` 之後）新增：

```dart
  testWidgets('PDF 點擊「⚙️版面」按鈕開啟 PdfSettingsSheet（非 ReaderSettingsSheet）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_settings_open.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_settings_open';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();

    expect(find.byType(PdfSettingsSheet), findsOneWidget);
    expect(find.byType(ReaderSettingsSheet), findsNothing);
  });

  testWidgets('PDF 切換三種 Fit 模式，畫面持續渲染成功、無 onError', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_fit_mode.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_fit_mode';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();

    for (final keySuffix in ['fit_width', 'actual_size', 'page_fit']) {
      await tester.tap(find.byKey(Key('pdf_settings_fit_mode_$keySuffix')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('reader_error_text')), findsNothing,
          reason: '切換至 $keySuffix 後畫面應持續渲染成功，不應觸發 onError');
    }
  });

  testWidgets('調整 PDF Fit 模式後關閉重開該書，設定被正確記住', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_fit_mode_persist.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_fit_mode_persist';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_fit_mode_actual_size')));
    await tester.pump();
    // 給非同步的 BookReaderPrefsRepository.save() 足夠時間完成寫入。
    await tester.pump(const Duration(milliseconds: 500));

    final saved = await prefsRepository.load(bookId);
    expect(saved.pdfFitMode, PdfFitMode.actualSize);

    // 關閉重開，確認 initialPreferences 機制真正生效（不只是 UI 顯示）。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.fitMode, PdfFitMode.actualSize);
  });
```

**注意**：本步驟的三個測試需要真實 Android 裝置/模擬器，不能用 `flutter test` 執行——見下一步。

- [ ] **Step 2: 於真實裝置/模擬器上執行驗證**

Run: `cd app && flutter devices`（確認至少一台可用裝置）
Run: `cd app && flutter test integration_test/reader_screen_test.dart -d <device-id>`
Expected: 全部測試通過（含既有 EPUB 相關測試不迴歸）；人工視覺確認：Fit Width／真實比例 1:1 模式下，若 PDF 內容超出畫面，超出部分不可捲動（決策 #Global Constraints 的刻意簡化行為），非崩潰或亂碼

- [ ] **Step 3: 更新 `docs/epics/epic-4-pdf-enhance/issues.md` 的 Issue 2 狀態**

編輯 `docs/epics/epic-4-pdf-enhance/issues.md`，找到：

```markdown
## Issue 2：PDF 設定入口與 Fit 模式端到端

**Status:** ready-for-agent
```

改為：

```markdown
## Issue 2：PDF 設定入口與 Fit 模式端到端（已完成）

**Status:** ✅ 已完成。`PdfSettingsSheet` 三分頁骨架與顯示分頁（Fit 模式三選一）、`PdfReaderView`（Dart＋原生）的 `fitMode` 契約與三種縮放邏輯、`ReaderScreen` 齒輪按鈕擴充至 PDF 皆已完成並經真機驗證。刻意簡化：Fit Width／真實比例 1:1 超出畫面的部分不可捲動，留待後續 issue 評估。完整計劃見 `plans/plan-issue-2.md`。
```

- [ ] **Step 4: Commit**

```bash
git add app/integration_test/reader_screen_test.dart docs/epics/epic-4-pdf-enhance/issues.md
git commit -m "test(epic-4): 新增 Issue 2 真機驗證測試並標記完成"
```
