# Issue 5 實作計劃：`ReaderScreen` 端到端整合（唯一 seam 完整驗證）

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 把 `ReaderScreen`（`app/lib/screens/reader_screen.dart`）從「依格式分派到佔位視圖」改為「依格式分派到 Issue 3/4 已建立並合併的真正原生視圖」（`PdfReaderView`／`EpubReaderView`），並用兩項 `integration_test`（EPUB fixture、PDF fixture）驗證這個唯一 seam 確實渲染出非空白內容。

**架構：** `ReaderScreen` 從 `StatelessWidget` 改為 `StatefulWidget`，內部維護一個三態狀態機（載入中／已渲染／錯誤）。`build()` 依 `detectBookFormat(filePath)`（Issue 2 已實作，不需修改）決定要疊加哪一個原生 view（`EpubReaderView` 或 `PdfReaderView`），並把這兩個 view 既有的 `onPageRendered`/`onError` callback 接到內部狀態機，用 `Stack` 疊加一個載入中的 `CircularProgressIndicator`（渲染成功後移除）與錯誤訊息（渲染失敗時顯示）。`ReaderScreen` 對外的公開建構參數維持 `spec.md` 定義的唯一契約——只有 `filePath`，不新增 `onPageRendered`/`onError` 這類公開參數；因此本計劃用兩個固定 `Key`（`reader_loading_indicator`、`reader_error_text`）把「載入中 → 已渲染」這個狀態轉換暴露給 `integration_test` 觀察，讓測試不需要、也不能直接掛 callback。

**技術棧：** Flutter（Dart）、既有的 `EpubReaderView`（`app/lib/reader/epub_reader_view.dart`，Issue 4 已合併）與 `PdfReaderView`（`app/lib/reader/pdf_reader_view.dart`，Issue 3 已合併）、`integration_test`、`path_provider`（皆已是專案既有相依套件，不需新增）。

## 全域限制條件

- Flutter 專案位於 `app/`，套件名稱為 `elinkbook`，Android 應用程式 ID 為 `cc.ugotit.elinkbook`。
- `ReaderScreen(filePath: String)` 是本 Epic 唯一對外契約（`spec.md`）：公開建構參數只有 `filePath`，本工單不得新增其他公開建構參數。
- Platform channel 契約（`openBook`/`onPageRendered`/`onError`）已由 `EpubReaderView`/`PdfReaderView` 實作完成——本工單**不得**修改這兩個原生模組或其 Kotlin 程式碼，只在 Flutter 端把 `ReaderScreen` 接上它們既有的 Dart widget 介面。
- 本工單只驗證「渲染該書第 1 頁（起始位置）」，不實作換頁 UI、劃線/備註、字型/邊距等偏好設定（`epic-2`/`epic-3`/`epic-6` 範圍）。
- 所有畫面上的使用者可見文字（例如錯誤訊息）須為正體中文。
- 依 `spec.md`「測試決策」：本 seam 的驗證方式須用 `integration_test` 在真實 Android 裝置/模擬器上執行，以 `onPageRendered` 是否觸發（而非 `onError`）作為通過條件；一般 `flutter test` widget test 無法觀察 `PlatformView` 內的真實渲染內容，不可用來斷言原生渲染是否成功。
- 本工單不得變更書架畫面（`library_screen.dart`）與「點擊書籍開啟」的導航流程——那是 Issue 6 的範圍。

## ⚠️ 執行前環境確認事項

撰寫本計劃時，已確認有 1 台 Android 裝置連線（`flutter devices` 列出 `9491G` / `3CEF42ECD491687` / Android 15 / API 35）。Task 2 的兩項 `integration_test` 都必須在真實 Android 裝置/模擬器上執行才能驗證——**執行本計劃前，請先用 `flutter devices` 確認裝置仍連線**，否則 Task 2 的驗證步驟無法通過。

---

### Task 1：`ReaderScreen` 改為分派到真正的原生視圖，並修正既有 widget test

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：`detectBookFormat(String path) -> BookFormat`（`app/lib/reader/book_format.dart`，Issue 2 已實作，不修改）；`EpubReaderView({required String filePath, required VoidCallback onPageRendered, required ValueChanged<String> onError})`（`app/lib/reader/epub_reader_view.dart`，Issue 4 已實作，不修改）；`PdfReaderView({required String filePath, required VoidCallback onPageRendered, required ValueChanged<String> onError})`（`app/lib/reader/pdf_reader_view.dart`，Issue 3 已實作，不修改）。
- Produces：`ReaderScreen({Key? key, required String filePath})`——公開建構參數不變；內部在 EPUB/PDF 格式下會疊加對應原生 view，並用 `Key('reader_loading_indicator')`（載入中顯示、渲染成功或失敗後消失）與 `Key('reader_error_text')`（僅渲染失敗時顯示）標記內部狀態，供 Task 2 的 `integration_test` 觀察。

- [ ] **Step 1：確認目前 widget test 基準線為綠燈**

Run（於 `app/` 目錄下）：

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected: `All tests passed!`（目前 3 項測試皆為佔位畫面文字斷言，尚未受本工單影響）。

- [ ] **Step 2：將 `ReaderScreen` 改為分派到真正的原生視圖**

把 `app/lib/screens/reader_screen.dart` 整份內容改為：

```dart
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/epub_reader_view.dart';
import '../reader/pdf_reader_view.dart';

/// 唯一的閱讀器顯示接縫（seam）：給定書籍檔案路徑，依偵測到的格式分派到
/// 對應的原生渲染視圖（EpubReaderView／PdfReaderView），畫面上會渲染出該
/// 書第 1 頁。公開建構參數僅有 [filePath]（見 spec.md 的 seam 定義）——載入
/// 中／錯誤狀態皆為內部實作細節，透過固定的 Key（`reader_loading_indicator`
/// ／`reader_error_text`）暴露給 integration_test 觀察，而非另外新增公開
/// callback 參數，避免違反 spec.md 定義的唯一對外契約。
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

  void _handlePageRendered() {
    setState(() => _state = _RenderState.rendered);
  }

  void _handleError(String message) {
    setState(() {
      _state = _RenderState.error;
      _errorMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final format = detectBookFormat(widget.filePath);
    return Scaffold(
      appBar: AppBar(
        title: const Text('閱讀器'),
      ),
      body: _buildBody(format),
    );
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
          onPageRendered: _handlePageRendered,
          onError: _handleError,
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

- [ ] **Step 3：確認舊的 widget test 現在會失敗（紅燈檢查點）**

Run（於 `app/` 目錄下）：

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected: 失敗，且失敗訊息中包含「EPUB 路徑顯示 EPUB 佔位畫面」與「PDF 路徑顯示 PDF 佔位畫面」兩項測試，錯誤為 `find.text('EPUB 佔位畫面（尚未接上 Readium 原生渲染）')`／`find.text('PDF 佔位畫面（尚未接上 PdfRenderer 原生渲染）')` 找不到符合的 widget（`findsOneWidget` 實際找到 0 個）。這證實 Step 2 的改動確實移除了舊有的佔位文字行為，舊測試需要更新才能反映新的分派目標。「不支援格式顯示明確錯誤訊息」這項測試預期仍會通過（`unknown` 分支行為未變）。

- [ ] **Step 4：更新 widget test 以反映新的分派行為**

把 `app/test/screens/reader_screen_test.dart` 整份內容改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_screen.dart';

// 依 spec.md「測試決策」：ReaderScreen 分派到 EpubReaderView/PdfReaderView
// 後，實際渲染內容存在於原生 PlatformView 之中，一般 flutter test（無真實
// 裝置/模擬器）無法觀察其渲染結果，因此 EPUB/PDF 兩個分支的「確實渲染出
// 內容」驗證改由 integration_test/reader_screen_test.dart（Task 2）在真實
// 裝置上執行；此處只保留 flutter test 就能可靠驗證的「不支援格式」分支。
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
}
```

- [ ] **Step 5：確認 widget test 恢復綠燈**

Run（於 `app/` 目錄下）：

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6：執行完整 `flutter test` 套件，確認無回歸**

Run（於 `app/` 目錄下）：

```bash
flutter test
```

Expected: `All tests passed!`（涵蓋 `book_format_test.dart`、`library_screen_test.dart`、`settings_screen_test.dart`、`navigation_test.dart`——這幾個檔案皆未被本工單修改，也不依賴 `ReaderScreen` 的內部實作，預期不受影響）。

- [ ] **Step 7：靜態分析確認無警告**

Run（於 `app/` 目錄下）：

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 8：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(task-1): ReaderScreen 分派至真正的 EpubReaderView/PdfReaderView"
```

---

### Task 2：撰寫並驗證兩項 `integration_test`（EPUB、PDF 端到端渲染）

**Files:**
- Create: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes：`ReaderScreen({required String filePath})`（Task 1 產出）；`app/test/fixtures/sample.epub`（Issue 4 已提交版本控制）；`app/test/fixtures/sample.pdf`（Issue 3 已提交版本控制）；`Key('reader_loading_indicator')`／`Key('reader_error_text')`（Task 1 產出，用於觀察渲染狀態）。
- Produces：兩項通過的 `integration_test`，是本工單（Issue 5）與 `spec.md`「測試決策」章節要求的驗證方式本身，供人類判斷 Issue 5 完成、以及供 Issue 6（書架串接開啟書籍）之後的回歸基準。

- [ ] **Step 1：撰寫兩項 `integration_test`**

建立 `app/integration_test/reader_screen_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/screens/reader_screen.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。原生
/// 渲染引擎（Readium／PdfRenderer）都需要真實的裝置檔案系統路徑，不能直接
/// 讀取 Flutter asset。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到 [condition] 成立或逾時。`ReaderScreen` 對外只有 filePath
/// 一個建構參數（見 spec.md 的 seam 定義），onPageRendered/onError 是內部
/// 實作細節，因此本檔案用 Key 觀察渲染狀態是否轉換，而非直接掛 callback。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時（$timeout）：條件未成立');
    }
    await tester.pump(step);
  }
}

bool _loadingIndicatorGone() =>
    find.byKey(const Key('reader_loading_indicator')).evaluate().isEmpty;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ReaderScreen 開啟範例 EPUB 檔案，渲染出非空白內容', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    // 10 秒逾時：Readium 需非同步解析 EPUB 套件結構並啟動 WebView 導覽器，
    // 與 Issue 4 的 EpubReaderView 整合測試採用相同的逾時時間。
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），'
            '但畫面顯示了錯誤');
  });

  testWidgets('ReaderScreen 開啟範例 PDF 檔案，渲染出非空白內容', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    // 5 秒逾時：PdfRenderer 為同步點陣圖渲染，與 Issue 3 的 PdfReaderView
    // 整合測試採用相同的逾時時間。
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 5),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），'
            '但畫面顯示了錯誤');
  });
}
```

- [ ] **Step 2：於真實裝置/模擬器上執行兩項 `integration_test`**

Run（於 `app/` 目錄下；`<device-id>` 請替換為 `flutter devices` 列出的實際 Android 裝置/模擬器 ID）：

```bash
flutter test integration_test/reader_screen_test.dart -d <device-id>
```

Expected: `All tests passed!`（兩項測試皆通過：EPUB fixture 觸發 `onPageRendered`——載入指示器消失且無錯誤文字；PDF fixture 同樣觸發 `onPageRendered`）。

- [ ] **Step 3：重新執行 Issue 3/4 既有的 `integration_test`，確認無回歸**

`ReaderScreen` 現在會建構 `EpubReaderView`/`PdfReaderView` 實例，雖然本工單未修改這兩個 widget 或其原生程式碼，仍應確認它們獨立執行時未受影響。

Run（於 `app/` 目錄下）：

```bash
flutter test integration_test/smoke_test.dart -d <device-id>
flutter test integration_test/pdf_reader_view_test.dart -d <device-id>
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```

Expected: 三個指令皆為 `All tests passed!`。

- [ ] **Step 4：靜態分析確認無警告**

Run（於 `app/` 目錄下）：

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 5：Commit**

```bash
git add app/integration_test/reader_screen_test.dart
git commit -m "test(task-2): 新增 ReaderScreen 端到端 integration_test（EPUB、PDF）"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍**：對應 `issues.md` Issue 5 的兩項 `integration_test` 要求（EPUB fixture 觸發 `onPageRendered`、PDF fixture 觸發 `onPageRendered`）與兩項驗收標準（同一個 `ReaderScreen` seam 用兩案例驗證、落實 `spec.md`「測試決策」章節描述的驗證方式）均已對應到 Task 2；Task 1 是達成這個目標所需的先決實作（把佔位分派換成真正的原生視圖），並同步處理因此變成過時的既有 widget test，避免留下會誤導後續開發者的失敗測試。
- **佔位符掃描**：每個步驟皆含完整程式碼與明確指令/預期輸出，無 TBD/待補內容；`<device-id>` 是執行時才能得知的真實環境參數，已於步驟中註明替換方式。
- **型別/命名一致性**：`ReaderScreen`、`filePath`、`EpubReaderView`、`PdfReaderView`、`onPageRendered`、`onError` 皆與 Issue 2/3/4 既有程式碼中的簽章逐字一致；`Key('reader_loading_indicator')`／`Key('reader_error_text')` 在 Task 1（生產者）與 Task 2（消費者）兩處字串完全相同。
- **對 spec.md「唯一對外契約」的遵守**：`ReaderScreen` 公開建構參數在本計劃前後皆只有 `filePath`，未新增 `onPageRendered`/`onError` 等參數；`Key` 是內部實作細節的觀察窗口，不是新增的公開 API 面。
- **對既有測試的處理方式揭露**：Task 1 刻意保留「先讓舊測試變紅、再修正」這個檢查點（Step 3），而非直接靜默覆寫測試檔案，目的是讓執行者能親眼確認新程式碼確實改變了可觀察行為，而非誤刪了原本仍然正確的斷言。EPUB/PDF 分支的「真的渲染出內容」驗證，依 `spec.md` 明文的測試決策，只能且只應該用 `integration_test`（Task 2）驗證，因此 Task 1 更新後的 widget test 只保留 `unknown` 分支——這不是測試覆蓋率倒退，而是把每種行為放到唯一能可靠驗證它的測試層級。
- **回歸風險揭露**：Task 2 Step 3 明確要求重跑 Issue 3（`pdf_reader_view_test.dart`）與 Issue 4（`epub_reader_view_test.dart`、`smoke_test.dart`）既有的 `integration_test`，確認 `ReaderScreen` 開始建構這兩個 widget 實例後，它們獨立運作的既有行為未受影響。

## 文件審查回應紀錄（`review-plan-issue-5.md`）

- **Important #1（錯誤狀態下未銷毀/隱藏原生視圖的資源風險）**：查證屬實。已採納：Task 1 Step 2 的 `_buildBody` 改為錯誤狀態時直接 early-return 錯誤文字（取代原本疊加在 `Stack` 上層的寫法），讓已失敗的 `EpubReaderView`/`PdfReaderView` 提早從 widget tree 移除、觸發其 `dispose()`，不再讓已知失敗的 `PlatformView` 繼續留在畫面底層。
- **Important #2（`didUpdateWidget` 未重設狀態）**：**未採用**。查證後發現兩點：其一，依 `design.md`/`spec.md` 與 Issue 6 的規劃，開書流程是「從書架點擊 → `Navigator.push` 到全新的 `ReaderScreen`」，每本書都是一個新的路由、新的 widget 實例，不存在「同一個 `ReaderScreenState` 收到不同 `filePath`」這個情境（審查意見本身也承認這點）。其二，就算真的發生這個情境，只在 `ReaderScreen` 這一層加 `didUpdateWidget` 也無法真正解決問題——`EpubReaderView`/`PdfReaderView`（Issue 3/4 已合併，本工單依全域限制不得修改）本身沒有偵測 `filePath` 變化並重新呼叫 `openBook` 的邏輯，`_onPlatformViewCreated` 只在原生 view 首次建立時觸發一次；就算 `ReaderScreen` 把自己的狀態重設回 `loading`，底層原生 view 也不會真的重新載入新檔案，畫面只會卡在載入動畫，比不處理更誤導。若未來真的需要「同一個閱讀畫面切換書籍」的功能，須連同 Issue 3/4 的原生 widget 一併重新設計，不屬於本工單範圍（YAGNI）。
- **Minor #1（`detectBookFormat` 同步/非同步擴充性提醒）**：**未採用**。技術描述本身正確，但這是純粹針對「未來若規格變更為魔數偵測」的假設性提醒；`book_format.dart` 也不在本計劃 Task 1 的檔案清單內（`detectBookFormat` 只被消費、未被修改），加註解需額外觸碰一個本工單不需要異動的檔案，屬於不對未發生情境預先設計的範圍。
