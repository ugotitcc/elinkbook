# Issue 6 實作計劃：書架畫面串接「開啟書籍」流程

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 把 `LibraryScreen`（`app/lib/screens/library_screen.dart`，目前只有一行佔位文字）改為顯示固定的範例書籍清單（一本 EPUB、一本 PDF），點擊項目後導航至 Issue 5 完成的 `ReaderScreen` 並顯示該書內容，讓「從書架點開一本書、看到內容渲染出來」成為從 App 正常入口即可觸及的真實使用者流程。此工單完成後，`epic-0-skeleton` 的目標（Flutter + Android + EPUB(Readium) + PDF 端到端）即達成。

**架構：** 新增 `app/lib/screens/sample_books.dart`：定義一個極簡的 `SampleBook` 資料型別、一份固定的兩筆範例清單（EPUB、PDF），以及一個 `stageSampleBookFile()` 輔助函式——把範例書籍的 Flutter asset（`test/fixtures/sample.epub`／`sample.pdf`，Issue 3/4 已提交版本控制並在 `pubspec.yaml` 宣告為 asset）複製為裝置暫存目錄中的真實檔案，因為 `ReaderScreen` 底層的原生渲染引擎（Readium／`PdfRenderer`）需要真實的裝置檔案系統路徑，無法直接讀取 asset。`LibraryScreen` 改為 `ListView` 渲染這份清單，點擊項目時呼叫 `stageSampleBookFile()`，取得真實路徑後用 `Navigator.push` 導航至 `ReaderScreen(filePath: ...)`。這是本 Epic 唯一新增的產品程式碼；`ReaderScreen`、`EpubReaderView`、`PdfReaderView` 與所有原生程式碼維持不動。

**技術棧：** Flutter（Dart）、既有的 `ReaderScreen`（`app/lib/screens/reader_screen.dart`，Issue 5 已合併）、`path_provider`（已是專案既有相依套件）、`integration_test`。

## 全域限制條件

- Flutter 專案位於 `app/`，套件名稱為 `elinkbook`，Android 應用程式 ID 為 `cc.ugotit.elinkbook`。
- `ReaderScreen(filePath: String)` 是本 Epic 唯一對外契約（`spec.md`），本工單**不得**修改 `ReaderScreen`、`EpubReaderView`、`PdfReaderView` 或任何原生 Kotlin 程式碼——只把 `LibraryScreen` 接上 `ReaderScreen` 既有的公開介面。
- 本工單只使用固定、硬編碼的範例書籍清單；不得引入任何資料結構、持久化層或真實圖書庫匯入邏輯（真正的圖書庫管理屬於 `epic-1-library`，見 `spec.md`「範圍外」章節）。
- 不得修改 `SettingsScreen` 或既有的設定頁導航行為（`navigation_test.dart` 涵蓋的行為必須維持不變）。
- 所有畫面上的使用者可見文字（書名、按鈕、錯誤訊息等）須為正體中文。
- 依 `spec.md`「測試決策」：`stageSampleBookFile()` 依賴 `path_provider` 的平台 channel，`ReaderScreen` 的真實渲染依賴原生 `PlatformView`——兩者皆無法在一般 `flutter test`（無真實裝置/模擬器）中可靠驗證，因此「點擊 → 導航 → 渲染」的驗證只能且只應該用 `integration_test` 在真實 Android 裝置/模擬器上執行。
- `Key('reader_loading_indicator')`／`Key('reader_error_text')`（Issue 5 已在 `reader_screen.dart` 建立）是觀察 `ReaderScreen` 渲染狀態的既有機制，本工單的 `integration_test` 應沿用，不得另建新的觀察管道。

## ⚠️ 執行前環境確認事項

撰寫本計劃時，已確認有 1 台 Android 裝置連線（`flutter devices` 列出 `9491G` / `3CEF42ECD491687` / Android 15 / API 35）。Task 2 的兩項 `integration_test` 都必須在真實 Android 裝置/模擬器上執行才能驗證——**執行本計劃前，請先用 `flutter devices` 確認裝置仍連線**，否則 Task 2 的驗證步驟無法通過。

---

### Task 1：`LibraryScreen` 顯示範例書籍清單並串接開書流程

**Files:**
- Create: `app/lib/screens/sample_books.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：`BookFormat`（`app/lib/reader/book_format.dart`，Issue 2 已實作，不修改）；`ReaderScreen({required String filePath})`（`app/lib/screens/reader_screen.dart`，Issue 5 已實作，不修改）；已提交版本控制的 `app/test/fixtures/sample.epub`／`sample.pdf`（Issue 3/4，已在 `pubspec.yaml` 宣告為 asset）。
- Produces：`SampleBook`（`title`、`assetPath`、`fileName`、`format` 四個欄位皆為 `final`）；`const sampleBooks`（`List<SampleBook>`，固定兩筆：EPUB、PDF）；`Future<String> stageSampleBookFile(SampleBook book)`——回傳真實裝置檔案路徑，供 `LibraryScreen`（本任務）與 Task 2 的 `integration_test` 間接使用（透過點擊 UI 觸發，測試不直接呼叫此函式）。`LibraryScreen` 中每個範例書籍項目皆有 `Key('sample_book_${book.fileName}')`（例如 `Key('sample_book_sample.epub')`），供 Task 2 的 `integration_test` 定位點擊目標。

- [ ] **Step 1：撰寫失敗的 widget test**

把 `app/test/screens/library_screen_test.dart` 整份內容改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/library_screen.dart';

// 依 spec.md「測試決策」：點擊範例書籍後的檔案複製（path_provider）與
// ReaderScreen 的原生渲染都仰賴真實平台 channel，一般 flutter test（無真實
// 裝置/模擬器）無法可靠驗證，因此「點擊 → 導航 → 渲染」的驗證交給
// integration_test/library_screen_test.dart；此處只驗證書架清單本身有
// 正確渲染出兩個範例書籍項目。
void main() {
  testWidgets('LibraryScreen 顯示書架標題與兩個範例書籍項目', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    expect(find.text('書架'), findsOneWidget);
    expect(find.text('範例 EPUB 書籍'), findsOneWidget);
    expect(find.text('範例 PDF 文件'), findsOneWidget);
  });
}
```

- [ ] **Step 2：執行測試，確認失敗**

Run（於 `app/` 目錄下）：

```bash
flutter test test/screens/library_screen_test.dart
```

Expected: 失敗。錯誤訊息顯示 `find.text('範例 EPUB 書籍')`／`find.text('範例 PDF 文件')` 找不到符合的 widget（`findsOneWidget` 實際找到 0 個）——目前 `LibraryScreen` 仍是舊的「書架（佔位畫面）」單行文字，尚未渲染範例書籍清單。

- [ ] **Step 3：建立範例書籍資料與檔案暫存輔助函式**

建立 `app/lib/screens/sample_books.dart`：

```dart
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../reader/book_format.dart';

/// 書架佔位畫面用的固定範例書籍項目。真正的圖書庫管理（匯入、詮釋資料、
/// 封面產生）屬於 epic-1-library；這裡只是讓「點開一本書」在 epic-0-skeleton
/// 的骨架驗證範圍內，能從 App 正常入口（書架）觸發，而非測試專用的硬編碼
/// 呼叫。
class SampleBook {
  final String title;
  final String assetPath;
  final String fileName;
  final BookFormat format;

  const SampleBook({
    required this.title,
    required this.assetPath,
    required this.fileName,
    required this.format,
  });
}

const sampleBooks = <SampleBook>[
  SampleBook(
    title: '範例 EPUB 書籍',
    assetPath: 'test/fixtures/sample.epub',
    fileName: 'sample.epub',
    format: BookFormat.epub,
  ),
  SampleBook(
    title: '範例 PDF 文件',
    assetPath: 'test/fixtures/sample.pdf',
    fileName: 'sample.pdf',
    format: BookFormat.pdf,
  ),
];

/// 把範例書籍的 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對
/// 路徑。原生渲染引擎（Readium／PdfRenderer）都需要真實的裝置檔案系統路徑，
/// 不能直接讀取 Flutter asset，因此書架點擊範例書籍時，必須先做這一步才能
/// 呼叫 ReaderScreen(filePath: ...)。
Future<String> stageSampleBookFile(SampleBook book) async {
  final bytes = await rootBundle.load(book.assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/${book.fileName}');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}
```

- [ ] **Step 4：把 `LibraryScreen` 改為渲染範例書籍清單並串接導航**

把 `app/lib/screens/library_screen.dart` 整份內容改為：

```dart
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import 'reader_screen.dart';
import 'sample_books.dart';
import 'settings_screen.dart';

/// 書架佔位畫面：真正的圖書庫管理邏輯屬於 epic-1-library；本畫面目前顯示
/// 固定的範例書籍清單（一本 EPUB、一本 PDF，見 sample_books.dart），點擊項目
/// 會把對應範例檔案複製為裝置真實檔案後導航至 ReaderScreen，讓「從書架點開
/// 一本書、看到內容渲染出來」成為從 App 正常入口即可觸及的真實使用者流程。
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('書架'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          for (final book in sampleBooks)
            ListTile(
              key: Key('sample_book_${book.fileName}'),
              leading: Icon(
                book.format == BookFormat.epub
                    ? Icons.menu_book
                    : Icons.picture_as_pdf,
              ),
              title: Text(book.title),
              onTap: () => _openSampleBook(context, book),
            ),
        ],
      ),
    );
  }

  Future<void> _openSampleBook(BuildContext context, SampleBook book) async {
    final filePath = await stageSampleBookFile(book);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ReaderScreen(filePath: filePath)),
    );
  }
}
```

（`_openSampleBook` 在 `await stageSampleBookFile(book)` 這個非同步空隙之後，使用 `context` 前先檢查 `context.mounted`——與 Issue 5 審查中採納的 `mounted` 防護是同一個道理：使用者有可能在檔案複製完成前就離開書架畫面，此時再對已卸載的 `BuildContext` 呼叫 `Navigator.of(context)` 是不安全的。）

- [ ] **Step 5：執行測試，確認通過**

Run（於 `app/` 目錄下）：

```bash
flutter test test/screens/library_screen_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6：執行完整 `flutter test` 套件，確認無回歸**

Run（於 `app/` 目錄下）：

```bash
flutter test
```

Expected: `All tests passed!`（涵蓋 `navigation_test.dart`——確認 AppBar 的設定圖示與導航行為未受影響；`book_format_test.dart`、`reader_screen_test.dart`、`settings_screen_test.dart` 皆未被本工單修改，預期不受影響）。

- [ ] **Step 7：靜態分析確認無警告**

Run（於 `app/` 目錄下）：

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 8：Commit**

```bash
git add app/lib/screens/sample_books.dart app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(task-1): LibraryScreen 顯示範例書籍清單並串接開書流程"
```

---

### Task 2：撰寫並驗證兩項 `integration_test`（從書架點擊範例書籍，端到端渲染）

**Files:**
- Create: `app/integration_test/library_screen_test.dart`

**Interfaces:**
- Consumes：`LibraryScreen()`（Task 1 產出，無建構參數）；`Key('sample_book_sample.epub')`／`Key('sample_book_sample.pdf')`（Task 1 產出，用於定位點擊目標）；`Key('reader_loading_indicator')`／`Key('reader_error_text')`（Issue 5 已在 `reader_screen.dart` 建立，用於觀察渲染狀態）。
- Produces：兩項通過的 `integration_test`，是本工單（Issue 6）與 `issues.md` 驗收標準要求的驗證方式本身；完成後代表 `epic-0-skeleton` 的端到端目標達成。

- [ ] **Step 1：撰寫兩項 `integration_test`**

建立 `app/integration_test/library_screen_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/screens/library_screen.dart';

/// 持續 pump，直到 [condition] 成立或逾時。與 Issue 5 的
/// integration_test/reader_screen_test.dart 採用相同的手法：ReaderScreen
/// 對外只有 filePath 一個建構參數，onPageRendered/onError 是內部實作細節，
/// 因此用 Key 觀察渲染狀態是否轉換，而非直接掛 callback。
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

/// 刪除 LibraryScreen 點擊範例書籍時，由 stageSampleBookFile() 複製到裝置
/// 暫存目錄中的檔案，避免測試殘留累積。
Future<void> _deleteStagedFile(String fileName) async {
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  if (await file.exists()) await file.delete();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('從書架點擊範例 EPUB 項目，導航至 ReaderScreen 且內容成功渲染',
      (tester) async {
    addTearDown(() => _deleteStagedFile('sample.epub'));

    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    await tester.tap(find.byKey(const Key('sample_book_sample.epub')));
    await tester.pumpAndSettle();

    expect(find.text('閱讀器'), findsOneWidget);

    // 先確認載入指示器真的存在，才能保證下面「等它消失」是有意義的等待，
    // 而不是 Key 被改名/移除後，condition 從一開始就成立、測試沒等待就
    // silently 通過（與 Issue 5 審查採納的修正手法一致）。
    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    // 10 秒逾時：Readium 需非同步解析 EPUB 套件結構並啟動 WebView 導覽器，
    // 與 Issue 4/5 的整合測試採用相同的逾時時間。
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），'
            '但畫面顯示了錯誤');
  });

  testWidgets('從書架點擊範例 PDF 項目，導航至 ReaderScreen 且內容成功渲染',
      (tester) async {
    addTearDown(() => _deleteStagedFile('sample.pdf'));

    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    await tester.tap(find.byKey(const Key('sample_book_sample.pdf')));
    await tester.pumpAndSettle();

    expect(find.text('閱讀器'), findsOneWidget);

    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    // 5 秒逾時：PdfRenderer 為同步點陣圖渲染，與 Issue 3/5 的整合測試採用
    // 相同的逾時時間。
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
flutter test integration_test/library_screen_test.dart -d <device-id>
```

Expected: `All tests passed!`（兩項測試皆通過：點擊範例 EPUB 項目後導航至 `ReaderScreen` 並觸發 `onPageRendered`；點擊範例 PDF 項目同樣導航並觸發 `onPageRendered`）。

- [ ] **Step 3：重新執行既有的 `integration_test`，確認無回歸**

Run（於 `app/` 目錄下）：

```bash
flutter test integration_test/smoke_test.dart -d <device-id>
flutter test integration_test/pdf_reader_view_test.dart -d <device-id>
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
flutter test integration_test/reader_screen_test.dart -d <device-id>
```

Expected: 四個指令皆為 `All tests passed!`。

- [ ] **Step 4：靜態分析確認無警告**

Run（於 `app/` 目錄下）：

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 5：Commit**

```bash
git add app/integration_test/library_screen_test.dart
git commit -m "test(task-2): 新增 LibraryScreen 開書流程端到端 integration_test（EPUB、PDF）"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍**：對應 `issues.md` Issue 6 的兩項 `integration_test` 要求（點擊範例 EPUB 項目導航並渲染、點擊範例 PDF 項目導航並渲染）與兩項驗收標準（兩項 `integration_test` 皆通過；完成後 `epic-0-skeleton` 端到端目標達成）均已對應到 Task 2；Task 1 是達成這個目標所需的先決實作（把書架佔位畫面換成真正的範例清單並串接開書流程）。
- **佔位符掃描**：每個步驟皆含完整程式碼與明確指令/預期輸出，無 TBD/待補內容；`<device-id>` 是執行時才能得知的真實環境參數，已於步驟中註明替換方式。
- **型別/命名一致性**：`SampleBook`、`sampleBooks`、`stageSampleBookFile`、`LibraryScreen`、`ReaderScreen`、`filePath` 皆在 Task 1（生產者）與 Task 2（消費者）兩處一致；`Key('sample_book_${book.fileName}')` 與 `Key('reader_loading_indicator')`/`Key('reader_error_text')` 在兩個 Task 間字串完全相同。
- **對既有鎖定範圍的遵守**：`ReaderScreen`、`EpubReaderView`、`PdfReaderView` 與所有原生程式碼皆未被本計劃的任何步驟修改；`SettingsScreen` 與既有設定頁導航行為（`navigation_test.dart`）亦未被修改，Task 1 Step 6 明確要求重新執行完整測試套件以驗證這點。
- **與 Issue 5 既有模式的一致性**：Task 2 的 `_pumpUntil`／`_loadingIndicatorGone` 輔助函式、載入指示器前置斷言、EPUB 10 秒／PDF 5 秒逾時、`context.mounted` 防護，皆直接沿用 Issue 5 審查後確立的手法，避免重蹈已修正過的錯誤（假陽性通過、非同步 callback 缺乏生命週期檢查）。
- **範圍外事項揭露**：Issue 6 完成後 `issues.md` 註明「可準備歸檔」，但依 `CLAUDE.md` 的 SDD 工作流程，歸檔（搬移至 `docs/archive/` 並更新 `docs/epics.md`）是人類指定的步驟，不屬於本實作計劃的任務範圍，本計劃不含歸檔動作。
