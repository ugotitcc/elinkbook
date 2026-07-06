# Issue 2 實作計劃：`ReaderScreen` 橫直排切換按鈕 UI 串接

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 讓 `ReaderScreen` 在閱讀 EPUB 時，於 AppBar 顯示一顆橫直排切換按鈕：初始狀態依 Issue 1 建立的 `EpubReaderView.onLayoutResolved` 回報結果顯示（自動偵測），按下後即時呼叫 `EpubReaderView.writingMode` 切換（不重新開書），定樣式書籍不顯示按鈕。本 issue 完成後，Epic 2 的核心使用者可見功能即完整可展示。

**架構：** `ReaderScreen` 內部新增 `WritingMode? _writingMode`、`bool _isFixedLayout` 兩個 state 欄位；`_handleLayoutResolved` 接收 Issue 1 的 `onLayoutResolved` 回呼並更新這兩個欄位；AppBar 的 `actions` 依格式與 `_isFixedLayout` 決定是否顯示一顆 `IconButton`，圖示/tooltip 顯示切換後的目標狀態（沿用 `LibraryScreen` 既有的 `library_view_mode_toggle` 慣例）；按下按鈕翻轉 `_writingMode` 並 `setState`，驅動 `EpubReaderView` 以新值重建，觸發其既有的 `didUpdateWidget` 邏輯呼叫原生 `setWritingMode`。`ReaderScreen(filePath: String)` 對外建構參數不變。

**技術棧：** Dart/Flutter、`integration_test`（真機，沿用 Issue 1 已建立的三個 fixture）。

## ⚠️ 執行前環境確認事項

Task 2 的驗證步驟須在真實 Android 模擬器/裝置上執行——執行前請先確認 `flutter devices`（於 `app/` 目錄下）能列出至少一個 Android 裝置/模擬器。

## 全域限制條件

- `ReaderScreen(filePath: String)` 對外建構參數與行為**不變**；橫直排切換純屬內部狀態管理，不新增公開建構參數/callback。
- 只在格式為 `BookFormat.epub` 時顯示切換按鈕；PDF、未支援格式一律不顯示。
- `_isFixedLayout == true` 時不顯示切換按鈕。
- 本 issue 的切換**僅限當次 session 即時切換**，不寫入任何持久化儲存（FR-10 的「採用書籍排版／強制直排／強制橫排」三態覆寫與其持久化留給 `epic-3-fonts-layout`，見 `design.md`/`spec.md` 的範圍排除說明）。
- 沿用 Issue 1 已建立的 `EpubReaderView` 契約（`writingMode`/`onLayoutResolved` 參數、`WritingMode`/`EpubLayoutInfo` 型別），不修改 `EpubReaderView`/`EpubReaderView.kt`/`PdfReaderView.kt`。
- 所有新增的程式碼註解維持正體中文。
- `flutter analyze` 全程必須維持 `No issues found!`。

---

### Task 1：`ReaderScreen` 內部狀態管理與切換按鈕（含可離線驗證的部分）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Issue 1 的 `WritingMode`（`app/lib/reader/writing_mode.dart`）、`EpubLayoutInfo`、`EpubReaderView` 的 `writingMode`/`onLayoutResolved` 參數
- Produces: `ReaderScreen` 內部行為完整實作；`Key('reader_writing_mode_toggle')` 供測試觀察（`ReaderScreen(filePath: String)` 對外簽章不變）

**背景（測試策略決策）：** `ReaderScreen` 直接建構真正的 `EpubReaderView`（無法替換成假物件——見 `CLAUDE.md`「唯一閱讀器 seam」約定，`ReaderScreen` 對外只有 `filePath`，沒有依賴注入管道）。實測確認：純粹 `pumpWidget` 一個指向 `test/fixtures/sample.epub` 的 `ReaderScreen` 在 `flutter test`（無裝置）下不會卡住或報錯——`AndroidView` 在沒有真實原生引擎時單純不觸發 `onPlatformViewCreated`，widget 樹仍正常建構。因此「初始狀態」（`onLayoutResolved` 觸發前）可以用一般 `flutter test` 驗證；「`onLayoutResolved` 觸發後的狀態轉換」則必須交給 Task 2 的 `integration_test`。

- [x] **Step 1：寫下可離線驗證的失敗測試**

開啟 `app/test/screens/reader_screen_test.dart`，把整份內容改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_screen.dart';

// 依 spec.md「測試決策」：ReaderScreen 分派到 EpubReaderView/PdfReaderView
// 後，實際渲染內容存在於原生 PlatformView 之中，一般 flutter test（無真實
// 裝置/模擬器）無法觀察其渲染結果，因此 EPUB/PDF 兩個分支的「確實渲染出
// 內容」驗證改由 integration_test/reader_screen_test.dart（Task 2）在真實
// 裝置上執行；此處只保留 flutter test 就能可靠驗證的部分：「不支援格式」
// 分支，以及橫直排切換按鈕在 onLayoutResolved 觸發前的初始狀態（按鈕本身
// 的顯示/隱藏、停用狀態不依賴原生回呼，可離線驗證）。
void main() {
  testWidgets('不支援格式顯示明確錯誤訊息', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.txt'),
      ),
    );

    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.text('不支援的檔案格式'), findsOneWidget);
  });

  testWidgets('EPUB 格式顯示橫直排切換按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.epub'),
      ),
    );

    final finder = find.byKey(const Key('reader_writing_mode_toggle'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，_writingMode 仍為 null，按鈕應為停用狀態',
    );
  });

  testWidgets('PDF 格式不顯示橫直排切換按鈕', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.pdf'),
      ),
    );

    expect(find.byKey(const Key('reader_writing_mode_toggle')), findsNothing);
  });
}
```

- [x] **Step 2：執行測試確認新案例失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/screens/reader_screen_test.dart
```
Expected：第一項（不支援格式）通過；新增的兩項因 `Key('reader_writing_mode_toggle')` 尚不存在而失敗（`findsOneWidget`/`findsNothing` 斷言失敗或編譯錯誤，視 `IconButton` import 是否已存在而定）。

- [x] **Step 3：實作 `ReaderScreen`**

把 `app/lib/screens/reader_screen.dart` 整份內容改為：

```dart
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/epub_reader_view.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/writing_mode.dart';

/// 唯一的閱讀器顯示接縫（seam）：給定書籍檔案路徑，依偵測到的格式分派到
/// 對應的原生渲染視圖（EpubReaderView／PdfReaderView），畫面上會渲染出該
/// 書第 1 頁。公開建構參數僅有 [filePath]（見 spec.md 的 seam 定義）——載入
/// 中／錯誤狀態皆為內部實作細節，透過固定的 Key（`reader_loading_indicator`
/// ／`reader_error_text`）暴露給 integration_test 觀察，而非另外新增公開
/// callback 參數，避免違反 spec.md 定義的唯一對外契約。EPUB 格式下的橫直排
/// 切換按鈕（`reader_writing_mode_toggle`）同理：純屬內部狀態管理，僅限當次
/// 閱讀 session 即時切換，不持久化（見 docs/epics/epic-2-vertical-core/
/// design.md「範圍與排除項目」——持久化與三態覆寫 UI 屬 FR-10／epic-3）。
///
/// AppBar 沿用與 LibraryScreen/SettingsScreen 一致的寫法（純 `AppBar(title:
/// ...)`，不自訂 leading）：Flutter 會依 `Navigator.canPop()` 自動決定是否
/// 顯示返回鍵，且點擊時使用安全的 `Navigator.maybePop()`，不需要手動處理。
class ReaderScreen extends StatefulWidget {
  final String filePath;

  const ReaderScreen({super.key, required this.filePath});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

enum _RenderState { loading, rendered, error }

class _ReaderScreenState extends State<ReaderScreen> {
  _RenderState _state = _RenderState.loading;
  String? _errorMessage;
  WritingMode? _writingMode;
  bool _isFixedLayout = false;

  void _handlePageRendered() {
    if (!mounted) return;
    setState(() => _state = _RenderState.rendered);
  }

  void _handleError(String message) {
    if (!mounted) return;
    setState(() {
      _state = _RenderState.error;
      _errorMessage = message;
    });
  }

  /// 【已知、可接受的行為】把自動偵測結果寫回 [_writingMode] 後，會驅動
  /// EpubReaderView 以非 null 值重建；EpubReaderView 的 didUpdateWidget 偵測
  /// 到「null → 非 null」的變化時，會多送一次 setWritingMode 給原生端，等於
  /// 把 Readium 剛剛自動判斷好的值重新套用一次。這是多餘但無害的呼叫（目前
  /// 沒有其他偏好設定會被覆蓋，見 EpubReaderView.kt 的 setWritingMode 註解），
  /// 不特地加狀態去抑制它，避免為了避免一次無害的重複呼叫而增加複雜度。
  void _handleLayoutResolved(EpubLayoutInfo info) {
    if (!mounted) return;
    setState(() {
      _isFixedLayout = info.isFixedLayout;
      _writingMode = info.writingMode;
    });
  }

  void _toggleWritingMode() {
    setState(() {
      _writingMode = _writingMode == WritingMode.vertical
          ? WritingMode.horizontal
          : WritingMode.vertical;
    });
  }

  @override
  Widget build(BuildContext context) {
    final format = detectBookFormat(widget.filePath);
    return Scaffold(
      appBar: AppBar(
        title: const Text('閱讀器'),
        actions: _buildAppBarActions(format),
      ),
      body: _buildBody(format),
    );
  }

  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (format != BookFormat.epub || _isFixedLayout) return null;
    return [
      IconButton(
        key: const Key('reader_writing_mode_toggle'),
        icon: Icon(
          _writingMode == WritingMode.vertical
              ? Icons.text_rotation_none
              : Icons.text_rotate_vertical,
        ),
        tooltip: _writingMode == WritingMode.vertical ? '切換為橫排' : '切換為直排',
        onPressed: _writingMode == null ? null : _toggleWritingMode,
      ),
    ];
  }

  Widget _buildBody(BookFormat format) {
    if (format == BookFormat.unknown) {
      return const Center(child: Text('不支援的檔案格式'));
    }
    if (_state == _RenderState.error) {
      // 渲染失敗時直接以錯誤文字取代原生視圖（而非疊加在 Stack 上層），讓
      // 已失敗的 EpubReaderView/PdfReaderView 提早從 widget tree 移除、
      // 觸發其 dispose() 清理原生資源，不讓一個已知失敗的 PlatformView
      // 繼續留在畫面底層。
      return Center(
        child: Text(
          _errorMessage ?? '無法載入書籍',
          key: const Key('reader_error_text'),
        ),
      );
    }
    return Stack(
      children: [
        _buildNativeView(format),
        if (_state == _RenderState.loading)
          const Center(
            key: Key('reader_loading_indicator'),
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildNativeView(BookFormat format) {
    switch (format) {
      case BookFormat.epub:
        return EpubReaderView(
          filePath: widget.filePath,
          writingMode: _writingMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
        );
      case BookFormat.pdf:
        return PdfReaderView(
          filePath: widget.filePath,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
        );
      case BookFormat.unknown:
        return const SizedBox.shrink();
    }
  }
}
```

- [x] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/screens/reader_screen_test.dart
```
Expected：`All tests passed!`（3 項測試）。

- [x] **Step 5：全量 `flutter test` 與 `flutter analyze` 確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過（含既有 84 項 + 本次新增 2 項）；`flutter analyze` 顯示 `No issues found!`。

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "Add writing mode toggle button to ReaderScreen"
```

---

### Task 2：真機驗證——自動偵測初始狀態與即時切換

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 完成的 `ReaderScreen`；Issue 1 已建立的三個 fixture（`test/fixtures/sample.epub` 自動判斷為直排、`sample_horizontal.epub` 自動判斷為橫排、`sample_fixed_layout.epub` 為定樣式）
- Produces: 無新介面（純測試驗證）

本 task 不修改任何production 程式碼——`ReaderScreen` 的實作已由 Task 1 完成，本 task 只新增在真實裝置上驗證「`onLayoutResolved` 觸發後」行為的 `integration_test`。

- [x] **Step 1：於 `integration_test/reader_screen_test.dart` 新增測試輔助函式與 4 項測試**

開啟 `app/integration_test/reader_screen_test.dart`，把開頭的 import：

```dart
import 'package:elinkbook/screens/reader_screen.dart';
```

改為：

```dart
import 'package:elinkbook/screens/reader_screen.dart';
```

（import 本身不變；新增的是下面的 helper 與測試案例。）

在 `_loadingIndicatorGone` 函式定義之後、`void main() {` 之前，新增：

```dart
bool _writingModeToggleReady(WidgetTester tester) {
  final finder = find.byKey(const Key('reader_writing_mode_toggle'));
  if (finder.evaluate().isEmpty) return false;
  return tester.widget<IconButton>(finder).onPressed != null;
}
```

在既有的兩項 `testWidgets`（EPUB／PDF 渲染）之後、`main()` 收尾的 `}` 之前，新增 4 項測試：

```dart
  testWidgets('開啟直排 CJK 範例 EPUB，切換按鈕啟用且提示切換為橫排',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_toggle_vertical.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    await _pumpUntil(
      tester,
      () => _writingModeToggleReady(tester),
      timeout: const Duration(seconds: 10),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader_writing_mode_toggle')),
    );
    expect(button.tooltip, '切換為橫排');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('開啟英文範例 EPUB，切換按鈕啟用且提示切換為直排', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_horizontal.epub', 'sample_toggle_horizontal.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    await _pumpUntil(
      tester,
      () => _writingModeToggleReady(tester),
      timeout: const Duration(seconds: 10),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader_writing_mode_toggle')),
    );
    expect(button.tooltip, '切換為直排');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('開啟定樣式範例 EPUB，切換按鈕最終不顯示', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_toggle_fixed.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    await _pumpUntil(
      tester,
      () =>
          _loadingIndicatorGone() &&
          find.byKey(const Key('reader_writing_mode_toggle')).evaluate().isEmpty,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('點擊切換按鈕後，提示文字反轉且不觸發錯誤', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_toggle_tap.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    await _pumpUntil(
      tester,
      () => _writingModeToggleReady(tester),
      timeout: const Duration(seconds: 10),
    );

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('reader_writing_mode_toggle')))
          .tooltip,
      '切換為橫排',
    );

    await tester.tap(find.byKey(const Key('reader_writing_mode_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('reader_writing_mode_toggle')))
          .tooltip,
      '切換為直排',
    );
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
```

- [x] **Step 2：於真實裝置/模擬器上執行測試確認全部通過**

Run（於 `app/` 目錄下；`<device-id>` 請替換為 `flutter devices` 列出的實際 Android 裝置/模擬器 ID）：
```bash
flutter test integration_test/reader_screen_test.dart -d <device-id>
```
Expected：`All tests passed!`（既有 2 項 + 新增 4 項，共 6 項測試皆通過）。

- [x] **Step 3：重新執行 Issue 1 既有的 EPUB 相關 `integration_test` 確認無回歸**

Run：
```bash
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
flutter test integration_test/library_screen_test.dart -d <device-id>
```
Expected：全部 `All tests passed!`。

- [x] **Step 4：靜態分析、建置與純 Dart 測試確認**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter build apk --debug
flutter test
```
Expected：`flutter analyze` 顯示 `No issues found!`；`flutter build apk --debug` 成功建置；`flutter test` 全數通過，無回歸。

- [x] **Step 5：Commit**

```bash
git add app/integration_test/reader_screen_test.dart
git commit -m "Add device-verified tests for writing mode toggle auto-detection and live switching"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍**：`spec.md`「`ReaderScreen` 內部行為異動」章節定義的 `_writingMode`/`_isFixedLayout` 狀態管理、按鈕顯示/隱藏邏輯、`onLayoutResolved` 接線皆對應到 Task 1；`issues.md` Issue 2 的驗收標準（手動驗證按鈕即時切換、fixed-layout 隱藏按鈕）由 Task 1（離線可驗證部分）+ Task 2（真機驗證部分）共同覆蓋。
- **修正 `design.md`/`spec.md`/`issues.md` 對 UI 視覺參考的錯誤描述**：規劃階段查核 `prototype/index.html:1481-1482` 後發現，該按鈕對實際上屬於 FR-10（`epic-3-fonts-layout` 範圍）的三態持久化覆寫面板，並非本 issue 適用的簡易即時切換按鈕；已回頭修訂三份文件的對應描述，改為採用 `LibraryScreen` 既有的圖示切換慣例獨立設計本 issue 的按鈕。
- **修正 `issues.md` 對測試策略的錯誤假設**：原描述假設可「沿用假的 `EpubReaderView`/channel 驅動」做 widget test，但 `ReaderScreen` 沒有依賴注入管道、無法替換成假物件。經實測確認 `flutter test`（無裝置）可以安全 `pumpWidget` EPUB/PDF 分支而不卡住（只是原生回呼不會觸發），因此把測試拆為「初始狀態可離線驗證（Task 1）」與「`onLayoutResolved` 觸發後的狀態轉換須真機驗證（Task 2）」兩層，而非原先設想的單一層假物件驅動。
- **佔位符掃描**：所有步驟皆含完整程式碼、明確指令與預期輸出。
- **型別/命名一致性**：`WritingMode`/`EpubLayoutInfo`/`writingMode`/`onLayoutResolved` 命名與 Issue 1 建立的介面完全一致；`Key('reader_writing_mode_toggle')` 命名沿用既有的 `reader_loading_indicator`/`reader_error_text` 前綴慣例。
- **已知、記錄在案但不處理的行為**：`_handleLayoutResolved` 把自動偵測結果寫入 `_writingMode` 後，會經由 `EpubReaderView.didUpdateWidget` 多觸發一次無害的 `setWritingMode` 呼叫（重新套用 Readium 剛判斷好的同一個值）——這是 Issue 1 最終整體審查已記錄的已知現象，已在 `_handleLayoutResolved` 的程式碼註解中說明原因與為何不特地處理（目前沒有其他偏好設定會被覆蓋，加狀態抑制它得不償失）。
