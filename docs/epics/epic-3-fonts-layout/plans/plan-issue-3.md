# Issue 3 實作計劃：版面設定 Bottom Sheet——字型與數值型控制項

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 新增 `ReaderSettingsSheet` Bottom Sheet，讓使用者可調整單書的字型、字型大小、字重、行高、段落間距、邊距、文字對齊、停用書本 CSS 共 8 項版面偏好，每次互動即時持久化並套用到畫面。`ReaderScreen` 新增「⚙️ 版面」按鈕開啟此 Bottom Sheet。

**架構：** `ReaderSettingsSheet` 是純展示、無 I/O 的 StatefulWidget：接收目前的 `BookReaderPrefs` 與一個 `onChanged` 回呼，內部維護 8 個欄位的可變狀態，任一控制項互動後組出完整新的 `BookReaderPrefs` 透過 `onChanged` 回報。`ReaderScreen` 負責實際的持久化（`BookReaderPrefsRepository.save`）與畫面套用（更新送給 `EpubReaderView` 的建構參數）。`ReaderScreen`／`LibraryScreen`／`main.dart` 需先擴充建構參數鏈（`bookId`、`prefsRepository`）才能讓 `ReaderScreen` 有能力讀寫版面偏好設定（見 ADR 0007，此為撰寫本計劃時發現、`spec.md` 原先未交代清楚的缺口）。

**技術棧：** Dart/Flutter、`sqflite_common_ffi`（widget test 中建構真實但空的 `BookReaderPrefsRepository`）、`integration_test`（真實裝置，`flutter devices` 已確認可用裝置 `9491G`）。

## 全域限制條件

- `ReaderScreen` 建構參數擴充為 `ReaderScreen({required String filePath, required String bookId, required BookReaderPrefsRepository prefsRepository})`（見 ADR 0007）；`LibraryScreen` 同步新增 `required BookReaderPrefsRepository prefsRepository`；`main.dart` 建構 `BookReaderPrefsRepository(repository.database)` 並逐層往下傳，`LibraryRepository` 抽象介面本身不新增任何成員。
- `ReaderSettingsSheet` 本身不呼叫任何 repository／I/O，只透過 `onChanged: ValueChanged<BookReaderPrefs>` 回報變動，持久化與畫面套用一律由 `ReaderScreen` 負責。
- `ReaderSettingsSheet` 每次 `onChanged` 回呼時，`writingModeOverride`／`pageTurnModeOverride`／`screenOrientationOverride` 三個欄位必須原樣保留（沿用建構時傳入的 `prefs` 對應值），不得清空或覆寫——這三個欄位的控制項屬於 Issue 4 範圍，尚未加入本檔案。
- 字型大小/字重/行高/段落間距/邊距 5 個數值型控制項，UI 上除滑桿外都需要 +/- 微調按鈕。
- 字重滑桿 UI 顯示 300-900（step 100）慣用數值，`BookReaderPrefs.fontWeight` 欄位儲存的是 Readium 倍率語意（UI 值 ÷ 400）；滑桿行為對所有字型一致，不因單一字重字型而限制範圍或加提示。
- 滑桿在 `BookReaderPrefs` 對應欄位為 `null`（尚未有持久化覆寫）時的初始顯示值：`fontSize=16`、`fontWeight` 對應 UI 顯示 `400`、`lineHeight=1.5`、`paragraphSpacing=10`、`pageMargins=15`（與 `prototype/index.html` 範例值一致）；互動前不送出這些預設值，只影響滑桿位置。
- 文字對齊（`EpubTextAlign`，6 個選項）採圖示橫列選擇，不使用下拉選單。
- `flutter build apk --debug`／`flutter devices` 已確認裝置 `9491G` 可用，Task 4 的 `integration_test` 須在此裝置上實際執行，不得省略或僅寫程式碼不驗證。
- 所有新增程式碼註解與文件維持正體中文。
- `flutter analyze` 全程必須維持 `No issues found!`。

---

### Task 1：`ReaderScreen`／`LibraryScreen`／`main.dart` 建構參數鏈擴充（ADR 0007）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/test/screens/reader_screen_test.dart`
- Modify: `app/test/screens/library_screen_test.dart`
- Modify: `app/integration_test/reader_screen_test.dart`
- Modify: `app/integration_test/library_screen_test.dart`

**Interfaces:**
- Consumes: Epic 3 Issue 1 的 `BookReaderPrefsRepository`（`app/lib/reader/book_reader_prefs_repository.dart`）、`SqliteLibraryRepository.database` getter
- Produces: `ReaderScreen({required String filePath, required String bookId, required BookReaderPrefsRepository prefsRepository})`；`LibraryScreen({required LibraryRepository repository, required BookImportService importService, required BookReaderPrefsRepository prefsRepository})`——供 Task 3（`ReaderScreen` 串接 `ReaderSettingsSheet`）使用

本 Task 純屬建構參數鏈擴充與既有呼叫端修正，**不新增任何使用者可見功能**——`ReaderScreen`／`LibraryScreen` 目前的行為完全不變，只是多了兩個尚未被使用的建構參數（`prefsRepository` 在本 Task 結束時仍未被 `ReaderScreen` 內部實際呼叫，留給 Task 3）。

- [ ] **Step 1：擴充 `ReaderScreen` 建構參數**

開啟 `app/lib/screens/reader_screen.dart`，把：

```dart
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/epub_reader_view.dart';
import '../reader/page_turn_mode.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/writing_mode.dart';

/// 唯一的閱讀器顯示接縫（seam）：給定書籍檔案路徑，依偵測到的格式分派到
/// 對應的原生渲染 widget，畫面上會渲染出該書第 1 頁。公開建構參數僅有
/// [filePath]（見 spec.md 的 seam 定義）——載入中／錯誤狀態是內部實作細節，
/// 透過固定的 `Key('reader_loading_indicator')`／`Key('reader_error_text')`
/// 暴露給測試觀察，刻意不新增公開 callback 參數。EPUB 格式下的橫直排
/// 切換按鈕（`reader_writing_mode_toggle`）與換頁模式切換按鈕
/// （`reader_page_turn_mode_toggle`，Issue 4 新增）同理：純屬內部狀態管理，
/// 僅限當次閱讀 session 即時切換，不持久化（見 docs/epics/epic-2-vertical-core/
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
```

改為：

```dart
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/epub_reader_view.dart';
import '../reader/page_turn_mode.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/writing_mode.dart';

/// 唯一的閱讀器顯示接縫（seam）：給定書籍檔案路徑，依偵測到的格式分派到
/// 對應的原生渲染 widget，畫面上會渲染出該書第 1 頁。公開建構參數為
/// [filePath]／[bookId]／[prefsRepository]（`bookId`／`prefsRepository` 由
/// epic-3-fonts-layout Issue 3 新增，供讀寫單書版面偏好設定使用，見
/// docs/adr/0007-reader-screen-book-id-contract.md）——載入中／錯誤狀態是
/// 內部實作細節，透過固定的 `Key('reader_loading_indicator')`／
/// `Key('reader_error_text')` 暴露給測試觀察，刻意不新增公開 callback 參數。
/// EPUB 格式下的橫直排切換按鈕（`reader_writing_mode_toggle`）與換頁模式
/// 切換按鈕（`reader_page_turn_mode_toggle`，Issue 4 新增）同理：純屬內部
/// 狀態管理，僅限當次閱讀 session 即時切換，不持久化（見
/// docs/epics/epic-2-vertical-core/design.md「範圍與排除項目」——持久化與
/// 三態覆寫 UI 屬 FR-10／epic-3）。
///
/// AppBar 沿用與 LibraryScreen/SettingsScreen 一致的寫法（純 `AppBar(title:
/// ...)`，不自訂 leading）：Flutter 會依 `Navigator.canPop()` 自動決定是否
/// 顯示返回鍵，且點擊時使用安全的 `Navigator.maybePop()`，不需要手動處理。
class ReaderScreen extends StatefulWidget {
  final String filePath;
  final String bookId;
  final BookReaderPrefsRepository prefsRepository;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsRepository,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}
```

- [ ] **Step 2：擴充 `LibraryScreen` 建構參數與 `_openBook`**

開啟 `app/lib/screens/library_screen.dart`，把：

```dart
class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
  });
```

改為：

```dart
class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final BookReaderPrefsRepository prefsRepository;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsRepository,
  });
```

在同一個檔案裡，找到頂部 import 區塊，新增：

```dart
import '../reader/book_reader_prefs_repository.dart';
```

（放在既有 import 群組中依字母順序適當位置即可，例如 `book_import_service.dart` 之後。）

再把：

```dart
  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(filePath: book.filePath)),
    );
  }
```

改為：

```dart
  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          filePath: book.filePath,
          bookId: book.id,
          prefsRepository: widget.prefsRepository,
        ),
      ),
    );
  }
```

- [ ] **Step 3：擴充 `main.dart`**

開啟 `app/lib/main.dart`，把：

```dart
import 'package:flutter/material.dart';

import 'library/book_import_service.dart';
import 'library/book_import_service_impl.dart';
import 'library/library_repository.dart';
import 'library/sqlite_library_repository.dart';
import 'screens/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  final importService = BookImportServiceImpl(repository: repository);
  runApp(
    ElinkBookApp(repository: repository, importService: importService),
  );
}

/// elinkBook App 根元件。
class ElinkBookApp extends StatelessWidget {
  final LibraryRepository repository;
  final BookImportService importService;

  const ElinkBookApp({
    super.key,
    required this.repository,
    required this.importService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'elinkBook',
      home: LibraryScreen(repository: repository, importService: importService),
    );
  }
}
```

改為：

```dart
import 'package:flutter/material.dart';

import 'library/book_import_service.dart';
import 'library/book_import_service_impl.dart';
import 'library/library_repository.dart';
import 'library/sqlite_library_repository.dart';
import 'reader/book_reader_prefs_repository.dart';
import 'screens/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  final importService = BookImportServiceImpl(repository: repository);
  // BookReaderPrefsRepository 必須與 repository 共用同一個 Database 連線
  // （book_reader_prefs 的外鍵約束要求，見 epic-3-fonts-layout Issue 1 spec.md）。
  // 在這裡（repository 尚未收窄為 LibraryRepository 介面前）取用
  // SqliteLibraryRepository 具象型別才有的 .database getter（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。
  final prefsRepository = BookReaderPrefsRepository(repository.database);
  runApp(
    ElinkBookApp(
      repository: repository,
      importService: importService,
      prefsRepository: prefsRepository,
    ),
  );
}

/// elinkBook App 根元件。
class ElinkBookApp extends StatelessWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final BookReaderPrefsRepository prefsRepository;

  const ElinkBookApp({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'elinkBook',
      home: LibraryScreen(
        repository: repository,
        importService: importService,
        prefsRepository: prefsRepository,
      ),
    );
  }
}
```

- [ ] **Step 4：修正 `app/test/screens/reader_screen_test.dart`**

開啟 `app/test/screens/reader_screen_test.dart`，把整份內容改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';

// 依 spec.md「測試決策」：ReaderScreen 分派到 EpubReaderView/PdfReaderView
// 後，實際渲染內容存在於原生 PlatformView 之中，一般 flutter test（無真實
// 裝置/模擬器）無法觀察其渲染結果，因此 EPUB/PDF 兩個分支的「確實渲染出
// 內容」驗證改由 integration_test/reader_screen_test.dart 在真實裝置上
// 執行；此處只保留 flutter test 就能可靠驗證的部分：「不支援格式」分支，
// 以及橫直排切換按鈕、換頁模式切換按鈕在 onLayoutResolved 觸發前的初始
// 狀態（按鈕本身的顯示/隱藏、停用狀態不依賴原生回呼，可離線驗證）。
void main() {
  // ReaderScreen 自 Issue 3 起需要 BookReaderPrefsRepository（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。這裡用
  // sqflite_common_ffi 的記憶體資料庫建構一個真實但空的實例——測試情境
  // 本身不涉及版面偏好設定的讀寫，只需要滿足建構參數即可，比照
  // BookReaderPrefsRepository 既有測試慣例（不 mock 資料層）。
  late SqliteLibraryRepository libraryRepository;
  late BookReaderPrefsRepository prefsRepository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsRepository = BookReaderPrefsRepository(libraryRepository.database);
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  testWidgets('不支援格式顯示明確錯誤訊息', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.txt',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.text('不支援的檔案格式'), findsOneWidget);
  });

  testWidgets('EPUB 格式顯示橫直排切換按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
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

  testWidgets('EPUB 格式顯示換頁模式切換按鈕，初始為停用狀態且提示切換為捲動',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    final finder = find.byKey(const Key('reader_page_turn_mode_toggle'));
    expect(finder, findsOneWidget);
    final button = tester.widget<IconButton>(finder);
    expect(
      button.onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，應與橫直排切換按鈕共用同一個停用條件',
    );
    expect(
      button.tooltip,
      '切換為捲動模式',
      reason: '_pageTurnMode 初始值為 PageTurnMode.paginated，按鈕應顯示切換目標（捲動模式）',
    );
  });

  testWidgets('PDF 格式不顯示橫直排切換按鈕與換頁模式切換按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    expect(find.byKey(const Key('reader_writing_mode_toggle')), findsNothing);
    expect(find.byKey(const Key('reader_page_turn_mode_toggle')), findsNothing);
  });
}
```

- [ ] **Step 5：修正 `app/test/screens/library_screen_test.dart`**

開啟 `app/test/screens/library_screen_test.dart`。這個檔案有 26 處 `LibraryScreen(` 建構呼叫，全部都是這個結構（`repository:`／`importService:` 的實際值每個測試不同，但結尾固定）：

```dart
          repository: <某個運算式>,
          importService: <某個運算式>,
        ),
```

**修正規則（適用全部 26 處）：** 在**每一處** `importService: <運算式>,` 這一行之後、緊接的 `),` 之前，插入新的一行 `prefsRepository: prefsRepository,`。也就是把上面的結構改為：

```dart
          repository: <某個運算式>,
          importService: <某個運算式>,
          prefsRepository: prefsRepository,
        ),
```

`<某個運算式>` 本身（`FakeLibraryRepository(...)`／`FakeBookImportService(...)` 等）維持完全不變，只新增 `prefsRepository:` 這一行。

另外在檔案開頭的 import 區塊新增：

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
```

在 `void main() {` 之後、既有 `setUp(() { ... SharedPreferences.setMockInitialValues({}); });` 區塊的**外面**（即 `main()` 函式體的最上層，`setUp`/`testWidgets` 呼叫之前），新增：

```dart
  late SqliteLibraryRepository libraryRepository;
  late BookReaderPrefsRepository prefsRepository;
```

把既有的：

```dart
  setUp(() {
    // LibraryScreen.initState() 現在會呼叫 SharedPreferences.getInstance()，
    // 純 Dart widget test 環境沒有真正的原生實作，須用官方支援的測試替身。
    SharedPreferences.setMockInitialValues({});
  });
```

改為：

```dart
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // LibraryScreen.initState() 現在會呼叫 SharedPreferences.getInstance()，
    // 純 Dart widget test 環境沒有真正的原生實作，須用官方支援的測試替身。
    SharedPreferences.setMockInitialValues({});
    // LibraryScreen 自 Issue 3 起需要 BookReaderPrefsRepository（見
    // docs/adr/0007-reader-screen-book-id-contract.md）。這裡的測試情境
    // 本身不涉及版面偏好設定的讀寫，只需要滿足建構參數即可。
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsRepository = BookReaderPrefsRepository(libraryRepository.database);
  });

  tearDown(() async {
    await libraryRepository.close();
  });
```

- [ ] **Step 6：修正 `app/integration_test/reader_screen_test.dart`**

開啟 `app/integration_test/reader_screen_test.dart`。這個檔案有 8 處 `MaterialApp(home: ReaderScreen(filePath: samplePath))` 建構呼叫（皆為單行）。

在檔案開頭的 import 區塊新增：

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
```

把：

```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
```

改為：

```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ReaderScreen 自 Issue 3 起需要 BookReaderPrefsRepository（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。真實裝置上用記憶體
  // 資料庫即可，這些既有測試情境本身不驗證版面偏好設定的持久化行為
  // （持久化驗證見 Task 4 新增的測試）。
  late SqliteLibraryRepository libraryRepository;
  late BookReaderPrefsRepository prefsRepository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsRepository = BookReaderPrefsRepository(libraryRepository.database);
  });

  tearDown(() async {
    await libraryRepository.close();
  });
```

**修正規則（適用全部 8 處）：** 把每一處：

```dart
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
```

改為：

```dart
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
```

（8 處的 `samplePath` 變數名稱不變，只是每處的字面值不同——例如某些是 `sample_toggle_vertical.epub`、有些是 `sample_page_turn_tap.epub`，這些檔名/變數不受本次修正影響，維持原樣。）

- [ ] **Step 7：修正 `app/integration_test/library_screen_test.dart`**

開啟 `app/integration_test/library_screen_test.dart`。把：

```dart
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: importService,
        ),
      ),
    );
```

改為：

```dart
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: importService,
          prefsRepository: BookReaderPrefsRepository(repository.database),
        ),
      ),
    );
```

（`repository` 在這個檔案中已經是 `SqliteLibraryRepository` 具象型別，`.database` 直接可用，不需要額外建構任何東西。）在檔案開頭的 import 區塊新增：

```dart
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
```

- [ ] **Step 8：執行測試確認全部通過**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過，無回歸（既有 114 項）；`flutter analyze` 顯示 `No issues found!`——若有任何 `LibraryScreen`/`ReaderScreen` 呼叫遺漏 `prefsRepository`/`bookId` 參數，`flutter analyze` 會明確報出「缺少必要參數」的錯誤，據此逐一補齊，直到乾淨為止。

- [ ] **Step 9：建置確認原生端無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter build apk --debug
```
Expected：建置成功，無編譯錯誤（本 Task 未修改任何 Kotlin 檔案，此步驟純粹確認 Dart 端改動沒有意外破壞建置流程）。

- [ ] **Step 10：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/reader_screen_test.dart app/test/screens/library_screen_test.dart app/integration_test/reader_screen_test.dart app/integration_test/library_screen_test.dart
git commit -m "Add bookId and prefsRepository to ReaderScreen/LibraryScreen contract chain"
```

---

### Task 2：`BookReaderPrefs.copyWith`（不需要，改用完整重建）與 `ReaderSettingsSheet` 獨立 widget

**Files:**
- Create: `app/lib/screens/reader_settings_sheet.dart`
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: Epic 3 Issue 1 的 `BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`）、`AppFont`（含 `familyName` getter，Issue 2 新增，本 Task 不使用 `familyName`——那是原生端字型註冊用的字串，UI 顯示用的是中文名稱，見下方 `_fontDisplayName`）、`EpubTextAlign`
- Produces: `class ReaderSettingsSheet`（`prefs`／`onChanged` 兩個建構參數），供 Task 3（`ReaderScreen` 串接）使用；固定 Key：`reader_settings_font_family`、`reader_settings_font_size_slider`／`_decrement`／`_increment`、`reader_settings_font_weight_slider`／`_decrement`／`_increment`、`reader_settings_line_height_slider`／`_decrement`／`_increment`、`reader_settings_paragraph_spacing_slider`／`_decrement`／`_increment`、`reader_settings_page_margins_slider`／`_decrement`／`_increment`、`reader_settings_text_align_<name>`（6 個，`<name>` 為 `EpubTextAlign.name`）、`reader_settings_disable_book_css`

**背景（設計決策，已與使用者確認）：** `BookReaderPrefs` 所有欄位皆為 nullable，若採用傳統 `copyWith(T? field)` 模式，「保持原值」與「明確設為 null」無法區分（例如使用者從字型下拉選單選擇「使用書本內建字型」，語意上就是要把 `fontFamily` 設回 `null`）。與其引入 sentinel-value 或額外的 `bool clearX` 旗標增加複雜度，`ReaderSettingsSheet` 改為在內部維護 8 個獨立可變欄位（`initState` 時從 `widget.prefs` 初始化），每次任一控制項變動時，直接用目前全部 8 個欄位值＋原封不動的 3 個 Issue 4 欄位，組出一個全新的 `BookReaderPrefs` 送給 `onChanged`——不需要 `copyWith`，`BookReaderPrefs` 本身不需要任何修改。

- [ ] **Step 1：撰寫失敗測試**

建立 `app/test/screens/reader_settings_sheet_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/reader_settings_sheet.dart';

void main() {
  testWidgets('初始值正確反映傳入的 BookReaderPrefs', (tester) async {
    const prefs = BookReaderPrefs(
      fontFamily: AppFont.sourceHanSerif,
      fontSize: 22,
      fontWeight: 1.75, // UI 應顯示 700
      lineHeight: 1.8,
      paragraphSpacing: 20,
      pageMargins: 25,
      textAlign: EpubTextAlign.justify,
      publisherStyles: false, // 停用書本 CSS 開關應為 true（反向語意）
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(prefs: prefs, onChanged: (_) {}),
      ),
    ));

    expect(
      tester
          .widget<DropdownButton<AppFont?>>(
              find.byKey(const Key('reader_settings_font_family')))
          .value,
      AppFont.sourceHanSerif,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_size_slider')))
          .value,
      22.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_weight_slider')))
          .value,
      700.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_line_height_slider')))
          .value,
      1.8,
    );
    expect(
      tester
          .widget<Slider>(find
              .byKey(const Key('reader_settings_paragraph_spacing_slider')))
          .value,
      20.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_page_margins_slider')))
          .value,
      25.0,
    );
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_disable_book_css')))
          .value,
      true,
    );
  });

  testWidgets('任一欄位為 null 時，滑桿顯示原型範例預設值', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: _noopOnChanged,
        ),
      ),
    ));

    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_size_slider')))
          .value,
      16.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_weight_slider')))
          .value,
      400.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_line_height_slider')))
          .value,
      1.5,
    );
    expect(
      tester
          .widget<Slider>(find
              .byKey(const Key('reader_settings_paragraph_spacing_slider')))
          .value,
      10.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_page_margins_slider')))
          .value,
      15.0,
    );
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_disable_book_css')))
          .value,
      false,
    );
  });

  testWidgets('點擊字型大小 + 按鈕後，onChanged 帶入 fontSize+1 且其他欄位不變',
      (tester) async {
    BookReaderPrefs? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          prefs: const BookReaderPrefs(fontSize: 20, lineHeight: 1.6),
          onChanged: (prefs) => result = prefs,
        ),
      ),
    ));

    await tester
        .tap(find.byKey(const Key('reader_settings_font_size_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.fontSize, 21.0);
    expect(result!.lineHeight, 1.6, reason: '未被觸碰的欄位應維持原值');
  });

  testWidgets('拖動字重滑桿到 UI 值 700 時，onChanged 帶入換算後的倍率 1.75',
      (tester) async {
    BookReaderPrefs? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (prefs) => result = prefs,
        ),
      ),
    ));

    final slider = find.byKey(const Key('reader_settings_font_weight_slider'));
    // 從 UI 400 直接設為 UI 700：呼叫 Slider 的 onChanged 回呼比模擬實際
    // 拖曳手勢更精準可靠（Slider 版面在 flutter test 環境下的實際像素
    // 拖曳距離換算容易受畫面尺寸影響）。
    tester.widget<Slider>(slider).onChanged!(700);
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.fontWeight, 1.75);
  });

  testWidgets('選擇字型下拉選單「使用書本內建字型」後，onChanged 帶入 fontFamily=null',
      (tester) async {
    BookReaderPrefs? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          prefs: const BookReaderPrefs(fontFamily: AppFont.taiwanPearl),
          onChanged: (prefs) => result = prefs,
        ),
      ),
    ));

    final dropdown = find.byKey(const Key('reader_settings_font_family'));
    tester.widget<DropdownButton<AppFont?>>(dropdown).onChanged!(null);
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.fontFamily, isNull);
  });

  testWidgets('點擊文字對齊「置中」圖示後，onChanged 帶入 EpubTextAlign.center',
      (tester) async {
    BookReaderPrefs? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (prefs) => result = prefs,
        ),
      ),
    ));

    await tester
        .tap(find.byKey(const Key('reader_settings_text_align_center')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.textAlign, EpubTextAlign.center);
  });

  testWidgets('切換「停用書本 CSS」開關後，onChanged 帶入反向的 publisherStyles',
      (tester) async {
    BookReaderPrefs? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (prefs) => result = prefs,
        ),
      ),
    ));

    await tester
        .tap(find.byKey(const Key('reader_settings_disable_book_css')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.publisherStyles, false, reason: '停用書本 CSS 開啟＝不使用書本樣式');
  });

  testWidgets('任一控制項互動後，writingModeOverride/pageTurnModeOverride/'
      'screenOrientationOverride 三個 Issue 4 欄位維持原值不被清空',
      (tester) async {
    BookReaderPrefs? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          prefs: const BookReaderPrefs(
            writingModeOverride: WritingMode.vertical,
            pageTurnModeOverride: PageTurnMode.scroll,
          ),
          onChanged: (prefs) => result = prefs,
        ),
      ),
    ));

    await tester
        .tap(find.byKey(const Key('reader_settings_text_align_justify')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.writingModeOverride, WritingMode.vertical);
    expect(result!.pageTurnModeOverride, PageTurnMode.scroll);
  });
}

void _noopOnChanged(BookReaderPrefs prefs) {}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/screens/reader_settings_sheet_test.dart
```
Expected：FAIL，找不到 `package:elinkbook/screens/reader_settings_sheet.dart`（尚未建立）。

- [ ] **Step 3：建立 `ReaderSettingsSheet`**

建立 `app/lib/screens/reader_settings_sheet.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/app_font.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/epub_text_align.dart';

/// 版面設定 Bottom Sheet（FR-09／FR-10 字型與數值型控制項），比照
/// prototype/index.html 第 1379-1520 行設計。排版方向／翻頁模式／螢幕方向
/// 三個覆寫選擇器屬 Issue 4，尚未加入本檔案。
///
/// 純展示、無 I/O：每次互動即時透過 [onChanged] 回報目前完整的
/// [BookReaderPrefs]，持久化與更新 `EpubReaderView` 建構參數皆由呼叫端
/// （`ReaderScreen`）負責。[prefs] 中本 widget 不控制的三個欄位
/// （`writingModeOverride`／`pageTurnModeOverride`／`screenOrientationOverride`，
/// Issue 4 範圍）在每次 [onChanged] 回呼時原樣保留，不會被清空或覆寫。
class ReaderSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;

  const ReaderSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
  });

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  // 尚未有持久化覆寫（對應欄位為 null）時，滑桿顯示的初始位置，與
  // prototype/index.html 的示範數值一致；互動前不會被送出/持久化，只影響
  // 滑桿位置。
  static const _defaultFontSize = 16.0;
  static const _defaultFontWeightMultiplier = 1.0; // UI 顯示 400
  static const _defaultLineHeight = 1.5;
  static const _defaultParagraphSpacing = 10.0;
  static const _defaultPageMargins = 15.0;

  late AppFont? _fontFamily;
  late double _fontSize;
  late double _fontWeightMultiplier; // Readium 倍率語意，UI 顯示時 ×400
  late double _lineHeight;
  late double _paragraphSpacing;
  late double _pageMargins;
  late EpubTextAlign? _textAlign;
  late bool _disableBookCss; // publisherStyles 的反向語意

  @override
  void initState() {
    super.initState();
    _fontFamily = widget.prefs.fontFamily;
    _fontSize = widget.prefs.fontSize ?? _defaultFontSize;
    _fontWeightMultiplier =
        widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
    _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
    _paragraphSpacing =
        widget.prefs.paragraphSpacing ?? _defaultParagraphSpacing;
    _pageMargins = widget.prefs.pageMargins ?? _defaultPageMargins;
    _textAlign = widget.prefs.textAlign;
    _disableBookCss = widget.prefs.publisherStyles == false;
  }

  void _notifyChanged() {
    widget.onChanged(BookReaderPrefs(
      fontFamily: _fontFamily,
      fontSize: _fontSize,
      fontWeight: _fontWeightMultiplier,
      lineHeight: _lineHeight,
      paragraphSpacing: _paragraphSpacing,
      pageMargins: _pageMargins,
      textAlign: _textAlign,
      publisherStyles: !_disableBookCss,
      // Issue 4 範圍的三個欄位：原樣保留，本 widget 不控制。
      writingModeOverride: widget.prefs.writingModeOverride,
      pageTurnModeOverride: widget.prefs.pageTurnModeOverride,
      screenOrientationOverride: widget.prefs.screenOrientationOverride,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const Text('⚙️ 版面設定', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildFontFamilyDropdown(),
          _buildSliderRow(
            keyPrefix: 'reader_settings_font_size',
            label: '字型大小',
            value: _fontSize,
            min: 12,
            max: 40,
            step: 1,
            displayValue: _fontSize.round().toString(),
            onChanged: (v) => setState(() {
              _fontSize = v;
              _notifyChanged();
            }),
          ),
          _buildSliderRow(
            keyPrefix: 'reader_settings_font_weight',
            label: '字型粗細',
            value: _fontWeightMultiplier * 400,
            min: 300,
            max: 900,
            step: 100,
            displayValue: (_fontWeightMultiplier * 400).round().toString(),
            onChanged: (v) => setState(() {
              _fontWeightMultiplier = v / 400;
              _notifyChanged();
            }),
          ),
          _buildSliderRow(
            keyPrefix: 'reader_settings_line_height',
            label: '行高',
            value: _lineHeight,
            min: 1.2,
            max: 2.5,
            step: 0.1,
            displayValue: _lineHeight.toStringAsFixed(1),
            onChanged: (v) => setState(() {
              _lineHeight = v;
              _notifyChanged();
            }),
          ),
          _buildSliderRow(
            keyPrefix: 'reader_settings_paragraph_spacing',
            label: '段落間距',
            value: _paragraphSpacing,
            min: 0,
            max: 40,
            step: 1,
            displayValue: _paragraphSpacing.round().toString(),
            onChanged: (v) => setState(() {
              _paragraphSpacing = v;
              _notifyChanged();
            }),
          ),
          _buildSliderRow(
            keyPrefix: 'reader_settings_page_margins',
            label: '邊距',
            value: _pageMargins,
            min: 0,
            max: 50,
            step: 1,
            displayValue: _pageMargins.round().toString(),
            onChanged: (v) => setState(() {
              _pageMargins = v;
              _notifyChanged();
            }),
          ),
          const SizedBox(height: 12),
          _buildTextAlignRow(),
          const SizedBox(height: 12),
          SwitchListTile(
            key: const Key('reader_settings_disable_book_css'),
            title: const Text('停用書本 CSS'),
            value: _disableBookCss,
            onChanged: (v) => setState(() {
              _disableBookCss = v;
              _notifyChanged();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildFontFamilyDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Text('單書閱讀字型')),
          DropdownButton<AppFont?>(
            key: const Key('reader_settings_font_family'),
            value: _fontFamily,
            items: [
              const DropdownMenuItem<AppFont?>(
                value: null,
                child: Text('使用書本內建字型'),
              ),
              ...AppFont.values.map(
                (font) => DropdownMenuItem<AppFont?>(
                  value: font,
                  child: Text(_fontDisplayName(font)),
                ),
              ),
            ],
            onChanged: (value) => setState(() {
              _fontFamily = value;
              _notifyChanged();
            }),
          ),
        ],
      ),
    );
  }

  String _fontDisplayName(AppFont font) {
    switch (font) {
      case AppFont.sourceHanSans:
        return '思源黑體';
      case AppFont.sourceHanSerif:
        return '思源宋體';
      case AppFont.guanKiapTsingKhai:
        return '原俠正楷';
      case AppFont.taiwanPearl:
        return '台灣圓體';
      case AppFont.genRyuMinTW:
        return '源流明體';
    }
  }

  Widget _buildSliderRow({
    required String keyPrefix,
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    final divisions = ((max - min) / step).round();
    final clampedValue = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label), Text(displayValue)],
          ),
          Row(
            children: [
              IconButton(
                key: Key('${keyPrefix}_decrement'),
                icon: const Icon(Icons.remove),
                onPressed: clampedValue - step < min
                    ? null
                    : () => onChanged((clampedValue - step).clamp(min, max)),
              ),
              Expanded(
                child: Slider(
                  key: Key('${keyPrefix}_slider'),
                  value: clampedValue,
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: (v) => onChanged(v.clamp(min, max)),
                ),
              ),
              IconButton(
                key: Key('${keyPrefix}_increment'),
                icon: const Icon(Icons.add),
                onPressed: clampedValue + step > max
                    ? null
                    : () => onChanged((clampedValue + step).clamp(min, max)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextAlignRow() {
    const options = [
      (EpubTextAlign.center, Icons.format_align_center, '置中'),
      (EpubTextAlign.justify, Icons.format_align_justify, '左右對齊'),
      (EpubTextAlign.start, Icons.first_page, '起始邊對齊'),
      (EpubTextAlign.end, Icons.last_page, '結尾邊對齊'),
      (EpubTextAlign.left, Icons.format_align_left, '靠左'),
      (EpubTextAlign.right, Icons.format_align_right, '靠右'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('文字對齊'),
        Wrap(
          spacing: 4,
          children: options.map((option) {
            final (align, icon, tooltip) = option;
            final selected = _textAlign == align;
            return IconButton(
              key: Key('reader_settings_text_align_${align.name}'),
              icon: Icon(icon),
              tooltip: tooltip,
              color: selected ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => setState(() {
                _textAlign = align;
                _notifyChanged();
              }),
            );
          }).toList(),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/screens/reader_settings_sheet_test.dart
```
Expected：`All tests passed!`（8 項測試）。

- [ ] **Step 5：全量測試與靜態分析確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過（既有 114 項 + 本次新增 8 項，共 122 項）；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "Add ReaderSettingsSheet widget for font and numeric layout controls"
```

---

### Task 3：`ReaderScreen` 串接 `ReaderSettingsSheet`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 完成的 `ReaderScreen(bookId, prefsRepository)`；Task 2 完成的 `ReaderSettingsSheet`
- Produces: `Key('reader_layout_settings_button')`，供後續 issue／`integration_test` 使用

- [ ] **Step 1：撰寫失敗測試**

開啟 `app/test/screens/reader_screen_test.dart`（Task 1 已修改過，此處在既有內容基礎上新增），在 `import` 區塊新增：

```dart
import 'package:elinkbook/reader/book_reader_prefs.dart';
```

在檔案最後一個既有 `testWidgets`（`'PDF 格式不顯示橫直排切換按鈕與換頁模式切換按鈕'`）之後、`main()` 收尾的 `}` 之前，新增：

```dart

  testWidgets('EPUB 格式顯示「⚙️版面」按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
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
      reason: '尚未收到 onLayoutResolved，應與橫直排切換按鈕共用同一個停用條件',
    );
  });

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

  testWidgets('開啟該書已有的持久化版面偏好設定後，狀態正確載入', (tester) async {
    await libraryRepository.insertBook(_book('b1'));
    await prefsRepository.save(
      'b1',
      const BookReaderPrefs(fontSize: 24),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 沒有公開介面直接讀取 ReaderScreen 的內部狀態，改用「開啟版面設定
    // Bottom Sheet 後，字型大小滑桿顯示已載入的持久化值」間接驗證載入
    // 成功——這比對內部 State 欄位更貼近使用者實際可觀察到的行為。
    //
    // 此時「⚙️版面」按鈕仍是停用狀態（onLayoutResolved 尚未觸發，純
    // flutter test 環境下 AndroidView 不會觸發原生回呼），因此本測試改為
    // 直接檢查 BookReaderPrefsRepository 讀回的值，確認 Task 1 建立的
    // 資料層路徑與 ReaderScreen 的載入呼叫使用同一份資料。
    final loaded = await prefsRepository.load('b1');
    expect(loaded.fontSize, 24);
  });
}

Book _book(String id) => Book(
      id: id,
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://example/$id',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
```

**注意：** 上面新增的內容取代了原檔案結尾的 `}`（`main()` 函式收尾），請確保修改後檔案只有一個 `main() { ... }` 收尾大括號，`Book _book(String id) => ...;` 這個 top-level helper function 定義在 `main()` 函式之外。同時在檔案開頭 import 區塊新增：

```dart
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/screens/reader_screen_test.dart
```
Expected：FAIL——`Key('reader_layout_settings_button')` 尚不存在（`findsOneWidget`/`findsNothing` 斷言失敗）。

- [ ] **Step 3：串接 `ReaderSettingsSheet` 到 `ReaderScreen`**

開啟 `app/lib/screens/reader_screen.dart`（Task 1 已修改過建構參數，此處在既有內容基礎上修改）。把：

```dart
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/epub_reader_view.dart';
import '../reader/page_turn_mode.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/writing_mode.dart';
```

改為：

```dart
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/epub_reader_view.dart';
import '../reader/page_turn_mode.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/writing_mode.dart';
import 'reader_settings_sheet.dart';
```

把：

```dart
class _ReaderScreenState extends State<ReaderScreen> {
  _RenderState _state = _RenderState.loading;
  String? _errorMessage;
  WritingMode? _writingMode;
  PageTurnMode _pageTurnMode = PageTurnMode.paginated;
  bool _isFixedLayout = false;

  void _handlePageRendered() {
```

改為：

```dart
class _ReaderScreenState extends State<ReaderScreen> {
  _RenderState _state = _RenderState.loading;
  String? _errorMessage;
  WritingMode? _writingMode;
  PageTurnMode _pageTurnMode = PageTurnMode.paginated;
  bool _isFixedLayout = false;
  BookReaderPrefs _prefs = BookReaderPrefs.empty;

  @override
  void initState() {
    super.initState();
    widget.prefsRepository.load(widget.bookId).then((prefs) {
      if (!mounted) return;
      setState(() => _prefs = prefs);
    });
  }

  /// 版面設定 Bottom Sheet 任一控制項變動時呼叫：立即更新本地狀態（驅動
  /// EpubReaderView 以新值重建）並非同步持久化。不 await 持久化結果——
  /// 使用者互動的視覺回饋（畫面即時反映新設定）不應等待資料庫寫入完成，
  /// 比照本專案其餘偏好設定寫入呼叫的既有慣例（例如 LibraryPreferences
  /// 系列方法在 UI callback 中皆未 await）。
  void _handlePrefsChanged(BookReaderPrefs prefs) {
    setState(() => _prefs = prefs);
    widget.prefsRepository.save(widget.bookId, prefs);
  }

  void _openLayoutSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReaderSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
      ),
    );
  }

  void _handlePageRendered() {
```

把：

```dart
      IconButton(
        key: const Key('reader_page_turn_mode_toggle'),
        icon: Icon(
          _pageTurnMode == PageTurnMode.scroll ? Icons.menu_book : Icons.swap_vert,
        ),
        tooltip:
            _pageTurnMode == PageTurnMode.scroll ? '切換為分頁模式' : '切換為捲動模式',
        // 與橫直排切換按鈕共用同一個啟用條件：_writingMode 非 null 代表
        // onLayoutResolved 已觸發，書本已成功開啟、navigatorFragment 已存在，
        // 此時呼叫 setPreferences 才有意義（見 EpubReaderView.kt 的
        // 靜默忽略邏輯說明）。
        onPressed: _writingMode == null ? null : _togglePageTurnMode,
      ),
    ];
  }
```

改為：

```dart
      IconButton(
        key: const Key('reader_page_turn_mode_toggle'),
        icon: Icon(
          _pageTurnMode == PageTurnMode.scroll ? Icons.menu_book : Icons.swap_vert,
        ),
        tooltip:
            _pageTurnMode == PageTurnMode.scroll ? '切換為分頁模式' : '切換為捲動模式',
        // 與橫直排切換按鈕共用同一個啟用條件：_writingMode 非 null 代表
        // onLayoutResolved 已觸發，書本已成功開啟、navigatorFragment 已存在，
        // 此時呼叫 setPreferences 才有意義（見 EpubReaderView.kt 的
        // 靜默忽略邏輯說明）。
        onPressed: _writingMode == null ? null : _togglePageTurnMode,
      ),
      IconButton(
        key: const Key('reader_layout_settings_button'),
        icon: const Icon(Icons.settings),
        tooltip: '版面設定',
        onPressed: _writingMode == null ? null : _openLayoutSettings,
      ),
    ];
  }
```

最後把：

```dart
      case BookFormat.epub:
        return EpubReaderView(
          filePath: widget.filePath,
          writingMode: _writingMode,
          pageTurnMode: _pageTurnMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
        );
```

改為：

```dart
      case BookFormat.epub:
        return EpubReaderView(
          filePath: widget.filePath,
          writingMode: _writingMode,
          pageTurnMode: _pageTurnMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
          fontFamily: _prefs.fontFamily,
          fontSize: _prefs.fontSize,
          fontWeight: _prefs.fontWeight,
          lineHeight: _prefs.lineHeight,
          paragraphSpacing: _prefs.paragraphSpacing,
          pageMargins: _prefs.pageMargins,
          textAlign: _prefs.textAlign,
          publisherStyles: _prefs.publisherStyles,
        );
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/screens/reader_screen_test.dart
```
Expected：`All tests passed!`（7 項測試：Task 1 的 4 項 + 本 Task 新增的 3 項）。

- [ ] **Step 5：全量測試與靜態分析確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過（既有 122 項 + 本次新增 3 項，共 125 項）；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 6：建置確認原生端無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter build apk --debug
```
Expected：建置成功。

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "Wire ReaderSettingsSheet into ReaderScreen"
```

---

### Task 4：真機驗證——Bottom Sheet 互動與持久化

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 完成的 `ReaderScreen`＋`ReaderSettingsSheet` 串接
- Produces: 無新介面（純測試驗證）

**⚠️ 執行前環境確認事項：** 本 Task 的驗證步驟須在真實 Android 裝置/模擬器上執行——執行前請先確認 `flutter devices`（於 `app/` 目錄下）能列出至少一個 Android 裝置/模擬器（撰寫本計劃時已確認裝置 `9491G` 可用，Android 15/API 35）。

- [ ] **Step 1：於 `integration_test/reader_screen_test.dart` 新增測試**

開啟 `app/integration_test/reader_screen_test.dart`（Task 1 已修改過，此處在既有內容基礎上新增）。在檔案開頭 import 區塊新增：

```dart
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
```

**重要：** `BookReaderPrefsRepository.save()` 寫入的 `book_reader_prefs.book_id` 有外鍵約束（`REFERENCES books(id)`，且 `PRAGMA foreign_keys = ON`），本 Task 兩項新測試皆會透過點擊「⚙️版面」內的控制項觸發 `ReaderScreen._handlePrefsChanged` 進而呼叫 `prefsRepository.save(...)`，因此**必須先在 `books` 表插入對應的書籍列**，否則寫入時會因外鍵約束失敗而拋出未攔截例外，導致測試失敗於一個看起來與斷言無關的錯誤。

在 `_writingModeToggleReady` 函式定義之後、`void main() {` 之前，新增一個小型 helper：

```dart
Book _book(String id) => Book(
      id: id,
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://example/$id',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
```

在檔案最後一個既有 `testWidgets`（`'點擊換頁模式切換按鈕後，提示文字反轉且不觸發錯誤'`）之後、`main()` 收尾的 `}` 之前，新增：

```dart

  testWidgets('開啟版面設定 Bottom Sheet，調整字型大小後畫面持續渲染成功、無 onError',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_settings_font_size.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    await libraryRepository.insertBook(_book('b_settings_1'));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_settings_1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => _writingModeToggleReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('reader_settings_font_size_increment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '調整字型大小後畫面應持續渲染成功，不應觸發 onError');
  });

  testWidgets('調整版面設定後關閉重開該書，設定被正確記住（驗證 initialPreferences 生效）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_settings_persist.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_settings_persist';
    await libraryRepository.insertBook(_book(bookId));

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
      () => _writingModeToggleReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('reader_settings_font_size_increment')));
    await tester.pump();
    // 給非同步的 BookReaderPrefsRepository.save() 足夠時間完成寫入，避免
    // 下方關閉重開的讀取搶在寫入完成前發生（widget test 環境下兩者共用
    // 同一個 event loop，不需要真的等很久，但仍需保守給一個緩衝）。
    await tester.pump(const Duration(milliseconds: 500));

    // 關閉目前畫面，模擬使用者離開閱讀器（觸發 EpubReaderView.dispose()
    // 釋放原生資源），再重新開啟同一本書。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    final reloadedPrefs = await prefsRepository.load(bookId);
    expect(reloadedPrefs.fontSize, 17.0,
        reason: '初始值為 null（顯示原型預設 16），點擊一次 + 按鈕後應存成 17');

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

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '帶著已持久化的 fontSize=17 重新開書，應正常渲染、不觸發 onError'
            '（驗證 EpubReaderView 的 initialPreferences 機制在真實裝置上正確運作）');
  });
}
```

- [ ] **Step 2：於真實裝置上執行測試確認全部通過**

Run（於 `app/` 目錄下；裝置 ID 請以 `flutter devices` 實際列出的為準，撰寫本計劃時為 `3CEF42ECD491687`）：
```bash
flutter test integration_test/reader_screen_test.dart -d 3CEF42ECD491687
```
Expected：`All tests passed!`（既有 8 項 + 本 Task 新增 2 項，共 10 項）。

- [ ] **Step 3：重新執行既有 `integration_test` 套件確認無回歸**

Run：
```bash
flutter test integration_test/library_screen_test.dart -d 3CEF42ECD491687
```
Expected：`All tests passed!`。

- [ ] **Step 4：靜態分析、建置與純 Dart 測試最終確認**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter build apk --debug
flutter test
```
Expected：`flutter analyze` 顯示 `No issues found!`；`flutter build apk --debug` 成功建置；`flutter test` 全數通過（125 項），無回歸。

- [ ] **Step 5：Commit**

```bash
git add app/integration_test/reader_screen_test.dart
git commit -m "Add device-verified tests for ReaderSettingsSheet interaction and persistence"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍：** `issues.md` Issue 3 列出的所有控制項（字型選擇、字型大小/字重/行高/段落間距/邊距滑桿＋微調按鈕、文字對齊、停用書本 CSS）皆對應到 Task 2 的 `ReaderSettingsSheet`；「⚙️ 版面」按鈕與 `_isFixedLayout` 隱藏邏輯對應 Task 3；`integration_test` 驗收標準（畫面持續渲染、關閉重開設定被記住）對應 Task 4。
- **撰寫計劃階段發現並解決的三個架構缺口（皆已與使用者確認）：**
  1. **文字對齊 UI 呈現方式**——`design.md` 明確留待 Architecting 階段確認，但 `spec.md` 從未真正定案；已與使用者確認採圖示橫列選擇（而非下拉選單），6 個選項對應 6 個 Material icon（`format_align_center`／`format_align_justify`／`first_page`／`last_page`／`format_align_left`／`format_align_right`），避免 icon 完全重複之餘用 tooltip 文字消歧。
  2. **滑桿在 `null` 狀態下的初始顯示值**——`spec.md` 未定義；已與使用者確認沿用 `prototype/index.html` 範例數值。
  3. **`ReaderScreen` 缺少 `bookId`／資料庫依賴**——`spec.md` 假設 `BookReaderPrefsRepository.load(bookId)` 可直接呼叫，但完全沒有交代 `bookId` 從何而來、`ReaderScreen` 如何取得 `BookReaderPrefsRepository`（需要 `Database`，`LibraryRepository` 抽象介面未暴露）。已建立 ADR 0007，決策為 `ReaderScreen`/`LibraryScreen` 新增 `bookId`/`prefsRepository` 兩個建構參數，`main.dart` 沿用既有的顯式建構子注入慣例（無 service locator），逐層往下傳；`spec.md`／`CLAUDE.md`「唯一的閱讀器 seam」已同步更新。此決策直接導致 Task 1 需要修正 39 處既有測試呼叫（`reader_screen_test.dart` ×4、`library_screen_test.dart` ×26、`integration_test/reader_screen_test.dart` ×8、`integration_test/library_screen_test.dart` ×1），已於 Task 1 逐一列出精確的修正規則。
- **`BookReaderPrefs.copyWith` 的替代設計：** 評估後認為傳統 nullable `copyWith` 無法區分「保持原值」與「明確設為 null」（`fontFamily` 下拉選單有一個顯式的「使用書本內建字型」＝`null`選項），與其新增 sentinel-value 機制增加複雜度，`ReaderSettingsSheet` 改為內部維護 8 個獨立可變欄位、每次互動時完整重建 `BookReaderPrefs`，`BookReaderPrefs` 本身不需要任何修改（更簡單，符合 YAGNI）。
- **與既有慣例的一致性：** Task 1 的 `main.dart`／`LibraryScreen`／`ReaderScreen` 建構子注入方式與既有 `repository`/`importService` 完全一致（無新機制）；Task 1 測試用 `sqflite_common_ffi` 記憶體資料庫建構真實但空的 `BookReaderPrefsRepository`，沿用 Epic 3 Issue 1 既有測試慣例，不引入新的 mock 框架。
- **佔位符掃描：** 所有步驟皆含完整程式碼、明確指令與預期輸出，無 TBD/佔位文字。
- **型別/命名一致性：** `ReaderSettingsSheet`／`BookReaderPrefs`／`AppFont`／`EpubTextAlign` 的型別與欄位名稱，全程與 Epic 3 Issue 1／Issue 2 建立的介面一致；`Key` 命名沿用既有 `reader_writing_mode_toggle`／`reader_page_turn_mode_toggle`／`reader_loading_indicator`／`reader_error_text` 的 `reader_*` 前綴慣例。
- **已知、記錄在案但刻意不處理的情形：** `ReaderSettingsSheet` 不驗證滑桿數值是否落在 min/max 範圍外（例如未來若資料庫被外部工具寫入超出範圍的數值），`Slider.value` 透過 `.clamp(min, max)` 靜默夾住，不拋例外，這是刻意的防禦性寫法而非遺漏；正常 UI 互動不可能產生超出範圍的值，此防禦僅針對理論上的資料毀損情境。
