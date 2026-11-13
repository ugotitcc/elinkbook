# Epic 9 Issue 4：接進 `ReaderScreen` 並落地寫入 — 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Issue 2 的 `ReadingStatsRepository` 與 Issue 3 的 `ReadingStatsTracker` 接進閱讀器：`main.dart` 建構 SQLite repository、經 `LibraryReaderFeatureRepositories` → `buildReaderScreen()` → `ReaderScreen` 一路傳下去；`ReaderScreen` 為每次開書建立會話級 tracker，把閱讀活動、`paused`／`resumed`、TTS 播放狀態、退出閱讀器轉送給它，讓每日閱讀時數真正落地到資料庫。

**Architecture:**
- **注入鏈路**：repository 放進既有的 `LibraryReaderFeatureRepositories` bundle（新增可為 null 的欄位），沿用該 bundle 已貫穿全部開書路徑（書架、全庫搜尋、單書搜尋、閱讀器→單書搜尋→閱讀器）的做法。`ReaderScreen` 新增兩個選用參數 `readingStatsRepository`、`readingStatsTracker`；兩者皆無時完全不計時，行為與現況相同。
- **`ReaderScreen` 只轉送事件、沒有任何計時邏輯**：活動來源為（a）Foliate `onLocatorChanged` 與 PDF `onPageChanged` 的「開書後第二次以後」回報、（b）熱區上一頁／下一頁（含音量鍵）、（c）Foliate／PDF 的選取（長按劃線）。單純點擊叫出工具列（`menu` 熱區）與開書當下的初始定位回報都不算。
- **生命週期**：`paused`／`resumed` 轉成 `onEnteredBackground()`／`onReturnedToForeground()`；`_onTtsStatusChanged` 把 TTS 狀態轉成 `onTtsPlayingChanged(bool)`；`dispose()` 呼叫 `unawaited(tracker.flushAndClose())`。`ReaderScreen` 擁有它的 tracker：即使是測試注入的，離開時也由它結算並關閉。

**Tech Stack:** Flutter／Dart 3、`package:clock`、`flutter_test`（`testWidgets`）、既有 `FakeReadingStatsRepository`（`app/test/support/`）與 `ReadingStatsTracker`（`app/lib/stats/`）。

**Spec:** [`../spec.md`](../spec.md)（「依賴注入鏈路」「閱讀活動事件」「背景與 TTS」「寫入策略」「範圍與相依」，以及「測試決策」對 `ReaderScreen` 的說明）、[`../issues.md`](../issues.md) Issue 4、[`../epic.md`](../epic.md)「Issue 2／Issue 3 完成記錄」的「給後續 Issue 的提醒」

## Global Constraints

- `ReaderScreen` 內**不得**有任何計時邏輯，只呼叫 tracker 的公開方法：`recordActivity()`、`onEnteredBackground()`、`onReturnedToForeground()`、`onTtsPlayingChanged(bool)`、`flushAndClose()`。
- 不改動 `ReadingStatsTracker`、`ReadingStatsRepository` 的公開簽章（Issue 2、3 已合併）。
- 新欄位皆為可為 null 的選用參數：`LibraryReaderFeatureRepositories.readingStatsRepository`、`ReaderScreen.readingStatsRepository`、`ReaderScreen.readingStatsTracker`、`ElinkBookApp.readingStatsRepository`；未提供時行為與現況完全相同（既有測試零回歸）。
- 有 tracker 用 tracker（優先）；否則有 repository 就以本書 `bookId`、書名（`widget.bookTitle`，未提供時退回 `bookId`；**存原始書名，不經簡繁轉換**）、repository 的 `addReadingSeconds` 與 `onCleared` 建立會話級 tracker；兩者皆無則不計時。
- 單純點擊叫出工具列（`ZoneAction.menu`）不算活動；開書後第一次位置回報（初始定位）不算活動（沿用 `_hasRelocatedSinceOpen` 的同一個判斷點）；Foliate 位置與上一次相同的重複回報（樣式重排、圖片或字型載入後重新對齊錨點造成）也不算；開書後立即退出不產生時數。
- 寫入失敗不影響閱讀：閱讀器不崩潰、不顯示錯誤（tracker 內部已吞下例外並記診斷日誌）。
- `flutter_test` 環境下 `TtsController` 永遠停在 idle（見 `reader_screen_test.dart` 既有「誠實測試邊界」），因此以 `ReaderScreen.reportTtsPlayingForTest` 靜態測試入口直接觸發「TTS 狀態 → tracker」的轉送；`status == playing` 的一行對應由 `_onTtsStatusChanged` 負責，widget test 觸及不到。
- 不新增任何使用者可見字串（無 i18n 變更）。
- 程式碼註解一律使用正體中文；提交前 `flutter analyze` 須乾淨。
- 只跑異動觸及的測試檔；**本 Issue 動到 `ReaderScreen`，最後一個 Task 跑一次完整 `flutter test`**。

## Review Focus

以下是 spec 隱含、但主要驗收條件沒有直接涵蓋，最可能讓使用者踩到的情況（最可能的在前）：

1. **Foliate 在開書後多次回報位置（版面穩定過程）**：初始定位之後若還有非使用者操作造成的位置回報，會被當成閱讀活動，「開書後不動就退出」仍會記到時數。→ Task 3 鎖住兩種已知情況：「第一次回報不算活動」與「同一位置的重複回報不算活動」（程式審查以 Foliate 原始碼推論：第一次 relocate 會觸發 `applyPreferences` 重排，其後與圖片、字型載入都會再派發 relocate）；**位置因重排而微幅改變的回報擋不住，只能靠真機確認**（見 Task 4 Step 6），這是本計畫唯一無法在無裝置環境驗證的風險。
2. **只點擊叫出／收起工具列，不翻頁**：不得產生時數。→ Task 3「點擊叫出工具列不算活動」。
3. **資料庫寫入失敗**：閱讀器不崩潰、不出現錯誤畫面，離開時也安全。→ Task 3「寫入失敗不影響閱讀」。
4. **背景聽書**：TTS 播放中切到背景不得立刻結算，TTS 停止才寫入。→ Task 2「TTS 播放中進背景」。
5. **`_openBookSearch` 手動重建 bundle 時遺失欄位**：該處逐欄重建 `LibraryReaderFeatureRepositories`，新欄位漏轉送不會有編譯錯誤（與 epic-15 的 `bookImportService` 同一類風險）。→ Task 1「單書搜尋 bundle」。（程式審查查證：目前「閱讀器→單書搜尋」的 `fromReader` 分支是 pop 回原閱讀器就地跳轉，不會再建構第二個 `ReaderScreen`，所以這是防禦性轉送，尚無現行流程會因遺失而出錯。）

已知限制（不修，計畫內明說）：
- **PDF 只回報「頁碼變動」**：`PdfReaderView` 沒有捲動回呼，單頁內部的捲動（例如很長的單頁）不會被記為活動；連續閱讀時翻頁本身會持續累積。
- **不會有同一本書同時兩個 `ReaderScreen` 的雙重計時**（程式審查查證更正）：`BookSearchScreen` 的 `fromReader == true` 分支是 `Navigator.pop(jumpTarget)`，由原閱讀器就地跳轉；`buildReaderScreen()` 只在 `fromReader == false`（自全庫搜尋進入）時被呼叫，該情境下路由堆疊底下沒有同一本書的閱讀器。
- **寫入失敗後 tracker 已閒置或已關閉時，失敗的那批不會重試**（Issue 3 審查 Minor 5，已知）；`dispose()` 不等待寫入完成（fire-and-forget，比照既有 `_writeCurrentPosition()`）。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/screens/library_screen_dependencies.dart` | 修改 | bundle 新增 `readingStatsRepository` |
| `app/lib/screens/reader_screen_route.dart` | 修改 | `buildReaderScreen()` 轉交 repository |
| `app/lib/screens/reader_screen.dart` | 修改 | 新參數、建立 tracker、轉送事件、生命週期與退出 |
| `app/lib/main.dart` | 修改 | 建構 `SqliteReadingStatsRepository`，經 `ElinkBookApp` 放進 bundle |
| `app/test/screens/reader_screen_stats_harness.dart` | 新增 | 三個 ReaderScreen 統計測試檔共用的環境註冊與 pump 工具（不是測試檔） |
| `app/test/screens/reader_screen_stats_test.dart` | 新增 | 注入鏈路：閱讀器→單書搜尋 bundle |
| `app/test/screens/reader_screen_stats_lifecycle_test.dart` | 新增 | `paused`／`resumed`／TTS／退出 |
| `app/test/screens/reader_screen_stats_activity_test.dart` | 新增 | 活動來源、僅 repository 建立 tracker、寫入失敗 |
| `app/test/screens/library_screen_dependencies_test.dart` | 修改 | bundle 新欄位 |
| `app/test/screens/reader_screen_route_test.dart` | 修改 | `buildReaderScreen()` 轉交 |
| `app/test/elinkbook_app_wiring_test.dart` | 修改 | `ElinkBookApp` 把 repository 放進 bundle |

（issues.md 只指定 `reader_screen_stats_test.dart`；這裡依主題拆成三個檔案並共用 harness，讓每個檔案聚焦。）

以下所有指令都在 `app/` 目錄下執行。

---

### Task 1：注入鏈路（無行為變化）

**Files:**
- Modify: `app/lib/screens/library_screen_dependencies.dart`
- Modify: `app/lib/screens/reader_screen_route.dart`
- Modify: `app/lib/screens/reader_screen.dart`（只加參數與 `_openBookSearch` 轉送，不建立 tracker）
- Modify: `app/lib/main.dart`
- Create: `app/test/screens/reader_screen_stats_harness.dart`
- Create: `app/test/screens/reader_screen_stats_test.dart`
- Modify: `app/test/screens/library_screen_dependencies_test.dart`
- Modify: `app/test/screens/reader_screen_route_test.dart`
- Modify: `app/test/elinkbook_app_wiring_test.dart`

**Interfaces:**
- Consumes: `ReadingStatsRepository`、`SqliteReadingStatsRepository({required Database database})`（Issue 2）、`ReadingStatsTracker`（Issue 3）、`FakeReadingStatsRepository`。
- Produces（Task 2、3 依賴，名稱與簽章固定）：
  - `LibraryReaderFeatureRepositories.readingStatsRepository`（`ReadingStatsRepository?`）
  - `ReaderScreen.readingStatsRepository`（`ReadingStatsRepository?`）、`ReaderScreen.readingStatsTracker`（`ReadingStatsTracker?`）
  - `ElinkBookApp.readingStatsRepository`（`ReadingStatsRepository?`）
  - 測試 harness：`registerReaderStatsTestEnvironment()`、`pumpStatsReader(tester, {filePath, readingStatsRepository, readingStatsTracker, searchRepository, libraryRepository, readerKey, markRendered})`、`disposeStatsReader(tester)`、`reportLocator(tester, n)`、`moveAppToBackground(tester)`、`moveAppToForeground(tester)`、`statsToday()`、常數 `kStatsTestBookId`、`kStatsTestBookTitle`

- [x] **Step 1: 撰寫失敗的測試**

建立 `app/test/screens/reader_screen_stats_harness.dart`：

```dart
import 'package:clock/clock.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/library/library_repository.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/search/search_repository.dart';
import 'package:elinkbook/stats/reading_stats_repository.dart';
import 'package:elinkbook/stats/reading_stats_tracker.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/fake_inappwebview_platform.dart';
import '../support/fake_reader_prefs_manager.dart';

/// 三個 ReaderScreen 統計測試檔共用的常數與工具（epic-9-stats Issue 4）。
const String kStatsTestBookId = 'stats-book';
const String kStatsTestBookTitle = '統計測試書';

/// 在測試檔的 `main()` 開頭呼叫：註冊 `reader_screen_test.dart` 既有的環境設定
/// （假 WebView 平台、略過檔案系統的書籍快取、全螢幕 channel、pdfrx 初始化）。
void registerReaderStatsTestEnvironment() {
  late Future<String?> Function(String, String) originalCacheBookForServing;

  setUpAll(() {
    InAppWebViewPlatform.instance = FakeInAppWebViewPlatform();
    originalCacheBookForServing = cacheBookForServing;
    cacheBookForServing =
        (filePath, instanceId) async => '/fake/cache/dir/current.epub';
  });

  tearDownAll(() {
    cacheBookForServing = originalCacheBookForServing;
  });

  setUp(() {
    pdfrxInitialize();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (call) async => null,
    );
  });

  // 生命週期狀態掛在全域 binding 上，不會隨測試重置：每個測試結束時還原為前景，
  // 避免上一個測試停在 paused，讓下一個測試的「進入背景」變成空操作。
  tearDown(() {
    _stepLifecycle(TestWidgetsFlutterBinding.instance, AppLifecycleState.resumed);
  });
}

/// 依 Flutter 允許的相鄰狀態逐步轉換（resumed ↔ inactive ↔ hidden ↔ paused），
/// 不能直接由 paused 跳到 resumed（`AppLifecycleListener` 會斷言失敗；
/// 有 PDF 測試留下的監聽時尤其明顯）。
void _stepLifecycle(WidgetsBinding binding, AppLifecycleState target) {
  const order = [
    AppLifecycleState.resumed,
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  var index = order.indexOf(binding.lifecycleState ?? AppLifecycleState.resumed);
  final targetIndex = order.indexOf(target);
  while (index != targetIndex) {
    index += targetIndex > index ? 1 : -1;
    binding.handleAppLifecycleStateChanged(order[index]);
  }
}

/// 模擬 App 進入背景（依序經過 inactive、hidden，最後 paused）。
void moveAppToBackground(WidgetTester tester) =>
    _stepLifecycle(tester.binding, AppLifecycleState.paused);

/// 模擬 App 回到前景（依序經過 hidden、inactive，最後 resumed）。
void moveAppToForeground(WidgetTester tester) =>
    _stepLifecycle(tester.binding, AppLifecycleState.resumed);

MaterialApp _app(Widget home) => MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: home,
    );

/// 開啟閱讀器。[markRendered] 為 true 時（預設）呼叫底層 View 的
/// `onPageRendered`，讓畫面離開載入中狀態（並取消 30 秒開書逾時計時器，
/// 否則之後 `pump` 超過 30 秒會被判定為開書逾時）。
Future<void> pumpStatsReader(
  WidgetTester tester, {
  String filePath = 'test/fixtures/sample.epub',
  String? bookTitle = kStatsTestBookTitle,
  ReadingStatsRepository? readingStatsRepository,
  ReadingStatsTracker? readingStatsTracker,
  SearchRepository? searchRepository,
  LibraryRepository? libraryRepository,
  GlobalKey<State<ReaderScreen>>? readerKey,
  bool markRendered = true,
}) async {
  await tester.pumpWidget(
    _app(
      ReaderScreen(
        key: readerKey,
        filePath: filePath,
        bookId: kStatsTestBookId,
        bookTitle: bookTitle,
        prefsManager: FakeReaderPrefsManager(),
        isFixedLayout: filePath.endsWith('.epub') ? false : null,
        readingStatsRepository: readingStatsRepository,
        readingStatsTracker: readingStatsTracker,
        searchRepository: searchRepository,
        libraryRepository: libraryRepository,
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() => Future.delayed(Duration.zero));
  await tester.pump();
  if (!markRendered) return;
  if (filePath.endsWith('.pdf')) {
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
  } else {
    tester
        .widget<FoliateReaderView>(find.byType(FoliateReaderView))
        .onPageRendered();
  }
  await tester.pump();
}

/// 換掉整棵樹讓 ReaderScreen dispose（觸發退出結算）。
Future<void> disposeStatsReader(WidgetTester tester) async {
  await tester.pumpWidget(_app(const SizedBox.shrink()));
  await tester.pump();
}

/// 模擬 Foliate 回報第 [n] 個位置（onLocatorChanged）。
void reportLocator(WidgetTester tester, int n) {
  tester
      .widget<FoliateReaderView>(find.byType(FoliateReaderView))
      .onLocatorChanged
      ?.call(
        EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/$n)","index":0,"fraction":0.1}',
          progression: 0.1,
          locationIndex: n,
          locationTotal: 100,
        ),
      );
}

/// 目前（fake 時鐘下）的本地日期字串，與 tracker 寫入的 `YYYY-MM-DD` 一致。
String statsToday() {
  // 與 ReadingStatsTracker 一致：一律轉成本地日期後再格式化。
  final now = clock.now().toLocal();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year.toString().padLeft(4, '0')}-$month-$day';
}
```

建立 `app/test/screens/reader_screen_stats_test.dart`：

```dart
import 'package:elinkbook/screens/book_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_library_repository.dart';
import '../support/fake_reading_stats_repository.dart';
import '../support/fake_search_repository.dart';
import 'reader_screen_stats_harness.dart';

void main() {
  registerReaderStatsTestEnvironment();

  testWidgets(
      '閱讀器→單書搜尋：推入的 BookSearchScreen 帶著同一個 readingStatsRepository'
      '（「閱讀器→單書搜尋→閱讀器」不遺失統計 repository）', (tester) async {
    final statsRepository = FakeReadingStatsRepository();

    // 比照 reader_screen_test.dart 既有的單書搜尋接線測試：不標記渲染完成。
    await pumpStatsReader(
      tester,
      readingStatsRepository: statsRepository,
      searchRepository: FakeSearchRepository(),
      libraryRepository: FakeLibraryRepository(),
      markRendered: false,
    );

    await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
    await tester.pumpAndSettle();

    final pushed =
        tester.widget<BookSearchScreen>(find.byType(BookSearchScreen));
    expect(pushed.readerFeatureRepositories.readingStatsRepository,
        same(statsRepository));

    await disposeStatsReader(tester);
  });

  testWidgets('閱讀器沒有 readingStatsRepository 時，單書搜尋 bundle 的欄位為 null',
      (tester) async {
    await pumpStatsReader(
      tester,
      searchRepository: FakeSearchRepository(),
      libraryRepository: FakeLibraryRepository(),
      markRendered: false,
    );

    await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
    await tester.pumpAndSettle();

    final pushed =
        tester.widget<BookSearchScreen>(find.byType(BookSearchScreen));
    expect(pushed.readerFeatureRepositories.readingStatsRepository, isNull);

    await disposeStatsReader(tester);
  });
}
```

修改 `app/test/screens/library_screen_dependencies_test.dart`：

尋找：

```dart
import '../support/fake_remote_thumbnail_cache.dart';
```

改為：

```dart
import '../support/fake_remote_thumbnail_cache.dart';
import '../support/fake_reading_stats_repository.dart';
```

尋找：

```dart
  test('LibraryReaderFeatureRepositories.bookImportService 預設為 null，'
```

改為：

```dart
  test('LibraryReaderFeatureRepositories.readingStatsRepository 預設為 null，'
      '傳入時原樣持有同一個實例（epic-9-stats Issue 4）', () {
    const empty = LibraryReaderFeatureRepositories();
    expect(empty.readingStatsRepository, isNull);

    final statsRepository = FakeReadingStatsRepository();
    final dependencies = LibraryReaderFeatureRepositories(
        readingStatsRepository: statsRepository);
    expect(dependencies.readingStatsRepository, same(statsRepository));
  });

  test('LibraryReaderFeatureRepositories.bookImportService 預設為 null，'
```

修改 `app/test/screens/reader_screen_route_test.dart`：

尋找：

```dart
import '../support/fake_reader_prefs_manager.dart';
```

改為：

```dart
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_reading_stats_repository.dart';
```

尋找：

```dart
    test('initialJumpTarget 有值時正確帶入 ReaderScreen', () {
```

改為：

```dart
    test('bundle 帶 readingStatsRepository 時，原樣轉交給 ReaderScreen'
        '（epic-9-stats Issue 4），readingStatsTracker 不由 bundle 提供', () {
      final statsRepository = FakeReadingStatsRepository();
      final screen = buildReaderScreen(
        book: _testBook(),
        prefsManager: FakeReaderPrefsManager(),
        features: LibraryReaderFeatureRepositories(
          readingStatsRepository: statsRepository,
        ),
        sync: const LibrarySyncDependencies(),
        libraryRepository: FakeLibraryRepository(),
        isEinkMode: false,
      );

      expect(screen.readingStatsRepository, same(statsRepository));
      expect(screen.readingStatsTracker, isNull);
    });

    test('bundle 未帶 readingStatsRepository 時，ReaderScreen 的兩個統計參數皆為 null',
        () {
      final screen = buildReaderScreen(
        book: _testBook(),
        prefsManager: FakeReaderPrefsManager(),
        features: const LibraryReaderFeatureRepositories(),
        sync: const LibrarySyncDependencies(),
        libraryRepository: FakeLibraryRepository(),
        isEinkMode: false,
      );

      expect(screen.readingStatsRepository, isNull);
      expect(screen.readingStatsTracker, isNull);
    });

    test('initialJumpTarget 有值時正確帶入 ReaderScreen', () {
```

修改 `app/test/elinkbook_app_wiring_test.dart`：

尋找：

```dart
import 'support/fake_reader_prefs_manager.dart';
```

改為：

```dart
import 'support/fake_reader_prefs_manager.dart';
import 'support/fake_reading_stats_repository.dart';
```

尋找：

```dart
    final ttsProvider = FakeTtsProvider();

    await tester.pumpWidget(
      ElinkBookApp(
```

改為：

```dart
    final ttsProvider = FakeTtsProvider();
    final readingStatsRepository = FakeReadingStatsRepository();

    await tester.pumpWidget(
      ElinkBookApp(
```

尋找：

```dart
        ttsProvider: ttsProvider,
        initialTheme: AppTheme.dark,
```

改為：

```dart
        ttsProvider: ttsProvider,
        readingStatsRepository: readingStatsRepository,
        initialTheme: AppTheme.dark,
```

尋找：

```dart
    expect(libraryScreen.readerFeatureRepositories.ttsProvider,
        same(ttsProvider));
```

改為：

```dart
    expect(libraryScreen.readerFeatureRepositories.ttsProvider,
        same(ttsProvider));
    expect(libraryScreen.readerFeatureRepositories.readingStatsRepository,
        same(readingStatsRepository));
```

- [x] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/library_screen_dependencies_test.dart test/screens/reader_screen_route_test.dart test/elinkbook_app_wiring_test.dart test/screens/reader_screen_stats_test.dart`
Expected: 編譯失敗，`The named parameter 'readingStatsRepository' isn't defined`（以及 `ReaderScreen` 沒有 `readingStatsTracker` 等）。

- [x] **Step 3: 實作注入鏈路**

修改 `app/lib/screens/library_screen_dependencies.dart`：

尋找：

```dart
import '../search/search_repository.dart';
```

改為：

```dart
import '../search/search_repository.dart';
import '../stats/reading_stats_repository.dart';
```

尋找：

```dart
  final BookImportService? bookImportService;

  const LibraryReaderFeatureRepositories({
```

改為：

```dart
  final BookImportService? bookImportService;

  /// epic-9-stats Issue 4：每日閱讀統計的存取層。`ReaderScreen` 據此為每次
  /// 開書建立會話級計時器；`null` 時閱讀器不計時（行為與未啟用統計相同）。
  /// 放進本 bundle 的理由同 [bookImportService]：本 bundle 已貫穿所有開啟
  /// 閱讀器的路徑。
  final ReadingStatsRepository? readingStatsRepository;

  const LibraryReaderFeatureRepositories({
```

尋找：

```dart
    this.bookImportService,
  });
}

/// 收斂帳號同步相關欄位
```

改為：

```dart
    this.bookImportService,
    this.readingStatsRepository,
  });
}

/// 收斂帳號同步相關欄位
```

修改 `app/lib/screens/reader_screen_route.dart`：

尋找：

```dart
    bookImportService: features.bookImportService,
    initialJumpTarget: initialJumpTarget,
```

改為：

```dart
    bookImportService: features.bookImportService,
    readingStatsRepository: features.readingStatsRepository,
    initialJumpTarget: initialJumpTarget,
```

修改 `app/lib/screens/reader_screen.dart`：

尋找：

```dart
import '../search/search_repository.dart';
import '../sync/sync_checkpoint_trigger.dart';
import '../theme/elink_tokens.dart';
```

改為：

```dart
import '../search/search_repository.dart';
import '../stats/reading_stats_repository.dart';
import '../stats/reading_stats_tracker.dart';
import '../sync/sync_checkpoint_trigger.dart';
import '../theme/elink_tokens.dart';
```

尋找：

```dart
  final SingleBookFilePicker? pickSingleBookFile;

  const ReaderScreen({
```

改為：

```dart
  final SingleBookFilePicker? pickSingleBookFile;

  /// epic-9-stats Issue 4：每日閱讀統計的存取層（由
  /// `LibraryReaderFeatureRepositories.readingStatsRepository` 經
  /// `buildReaderScreen` 轉交）。未提供 [readingStatsTracker] 時，以本書的
  /// id、書名與這個 repository 建立會話級計時器；兩者皆為 `null` 則完全不
  /// 計時，行為與現況相同。
  final ReadingStatsRepository? readingStatsRepository;

  /// epic-9-stats Issue 4：直接注入的計時器（測試用）。優先於
  /// [readingStatsRepository]。**由 [ReaderScreen] 擁有**：離開閱讀器時
  /// 由它呼叫 `flushAndClose()` 結算並關閉，呼叫端不需要（也不應）另外釋放。
  final ReadingStatsTracker? readingStatsTracker;

  const ReaderScreen({
```

尋找：

```dart
    this.bookImportService,
    this.pickSingleBookFile,
  });
```

改為：

```dart
    this.bookImportService,
    this.pickSingleBookFile,
    this.readingStatsRepository,
    this.readingStatsTracker,
  });
```

尋找：

```dart
            bookImportService: widget.bookImportService,
          ),
          syncDependencies: LibrarySyncDependencies(
```

改為：

```dart
            bookImportService: widget.bookImportService,
            // epic-9-stats Issue 4：同上，手動逐欄重建 bundle 的新欄位必須
            // 一併轉送，否則「閱讀器→單書搜尋→閱讀器」開啟的閱讀器不計時。
            readingStatsRepository: widget.readingStatsRepository,
          ),
          syncDependencies: LibrarySyncDependencies(
```

修改 `app/lib/main.dart`：

尋找：

```dart
import 'search/search_repository.dart';
import 'l10n/app_locale.dart';
```

改為：

```dart
import 'search/search_repository.dart';
import 'stats/reading_stats_repository.dart';
import 'stats/sqlite_reading_stats_repository.dart';
import 'l10n/app_locale.dart';
```

尋找：

```dart
  final searchRepository = SqliteSearchRepository(
    database: repository.database,
  );
```

改為：

```dart
  final searchRepository = SqliteSearchRepository(
    database: repository.database,
  );
  // epic-9-stats Issue 4：每日閱讀統計，同一個 Database 連線（不設外鍵，
  // 見 Issue 2）；經 LibraryReaderFeatureRepositories 貫穿所有開書路徑。
  final readingStatsRepository = SqliteReadingStatsRepository(
    database: repository.database,
  );
```

尋找：

```dart
      searchRepository: searchRepository,
    ),
  );
}
```

改為：

```dart
      searchRepository: searchRepository,
      readingStatsRepository: readingStatsRepository,
    ),
  );
}
```

尋找：

```dart
  final bool isFullTextSearchAvailable;
  final SearchRepository? searchRepository;
```

改為：

```dart
  final bool isFullTextSearchAvailable;
  final SearchRepository? searchRepository;

  /// epic-9-stats Issue 4：每日閱讀統計的存取層，放進
  /// `LibraryReaderFeatureRepositories` 轉交給閱讀器。
  final ReadingStatsRepository? readingStatsRepository;
```

尋找：

```dart
    this.searchRepository,
    this.checkNetworkAvailability,
```

改為：

```dart
    this.searchRepository,
    this.readingStatsRepository,
    this.checkNetworkAvailability,
```

尋找：

```dart
          searchRepository: widget.searchRepository,
```

改為：

```dart
          searchRepository: widget.searchRepository,
          readingStatsRepository: widget.readingStatsRepository,
```

- [x] **Step 4: 執行測試，確認通過**

Run: `flutter test test/screens/library_screen_dependencies_test.dart test/screens/reader_screen_route_test.dart test/elinkbook_app_wiring_test.dart test/screens/reader_screen_stats_test.dart`
Expected: 全部通過。

- [x] **Step 5: 靜態分析**

Run: `flutter analyze lib/screens lib/main.dart test/screens test/elinkbook_app_wiring_test.dart`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add lib/screens/library_screen_dependencies.dart lib/screens/reader_screen_route.dart lib/screens/reader_screen.dart lib/main.dart test/screens/reader_screen_stats_harness.dart test/screens/reader_screen_stats_test.dart test/screens/library_screen_dependencies_test.dart test/screens/reader_screen_route_test.dart test/elinkbook_app_wiring_test.dart
git commit -m "feat(stats): epic-9 Issue 4 閱讀統計 repository 注入鏈路（main → bundle → buildReaderScreen → ReaderScreen）"
```

---

### Task 2：`ReaderScreen` 建立 tracker，轉送生命週期、TTS 與退出

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_stats_lifecycle_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `ReaderScreen.readingStatsRepository`／`readingStatsTracker`、harness；`ReadingStatsTracker`（`recordActivity()`、`onEnteredBackground()`、`onReturnedToForeground()`、`onTtsPlayingChanged(bool)`、`flushAndClose()`）。
- Produces（Task 3 依賴）：`ReaderScreen` 內的 `_readingStatsTracker`（`ReadingStatsTracker?`）與 `_recordReadingActivity()`；靜態測試入口 `ReaderScreen.reportTtsPlayingForTest(GlobalKey<State<ReaderScreen>> key, bool isPlaying)`。

- [x] **Step 1: 撰寫失敗的測試**

建立 `app/test/screens/reader_screen_stats_lifecycle_test.dart`：

```dart
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/stats/reading_stats_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reader_screen_stats_harness.dart';

/// 記錄寫入的 tracker 包裝。時鐘用預設的 `package:clock`，在 testWidgets 的
/// fake async 下隨 `tester.pump(duration)` 推進。
class _StatsRecorder {
  final List<int> seconds = [];

  late final ReadingStatsTracker tracker = ReadingStatsTracker(
    bookId: kStatsTestBookId,
    bookTitle: kStatsTestBookTitle,
    onFlush: (date, bookId, bookTitle, s) async => seconds.add(s),
  );

  int get total => seconds.fold(0, (sum, s) => sum + s);
}

void main() {
  registerReaderStatsTestEnvironment();

  testWidgets('paused 轉為進入背景：結算尾段並立即寫入', (tester) async {
    final recorder = _StatsRecorder();
    await pumpStatsReader(tester, readingStatsTracker: recorder.tracker);

    recorder.tracker.recordActivity();
    await tester.pump(const Duration(seconds: 20));
    moveAppToBackground(tester);
    await tester.pump();

    expect(recorder.total, 20);

    await disposeStatsReader(tester);
  });

  testWidgets('resumed 轉為回到前景：背景期間的活動被忽略，回前景後才重新計時',
      (tester) async {
    final recorder = _StatsRecorder();
    await pumpStatsReader(tester, readingStatsTracker: recorder.tracker);

    recorder.tracker.recordActivity();
    await tester.pump(const Duration(seconds: 20));
    moveAppToBackground(tester);
    await tester.pump();
    expect(recorder.total, 20);

    await tester.pump(const Duration(seconds: 10));
    moveAppToForeground(tester);
    await tester.pump();
    recorder.tracker.recordActivity(); // 回前景後第一次活動：不回溯背景空檔
    await tester.pump(const Duration(seconds: 10));

    await disposeStatsReader(tester); // 尾段 10 秒
    expect(recorder.total, 30);
  });

  testWidgets('離開閱讀器：結算尾段並寫入，之後 tracker 已關閉不再計時', (tester) async {
    final recorder = _StatsRecorder();
    await pumpStatsReader(tester, readingStatsTracker: recorder.tracker);

    recorder.tracker.recordActivity();
    await tester.pump(const Duration(seconds: 20));

    await disposeStatsReader(tester);
    expect(recorder.total, 20);

    recorder.tracker.recordActivity();
    await tester.pump(const Duration(seconds: 600));
    expect(recorder.total, 20);
  });

  testWidgets('TTS 播放中進背景：不結算，TTS 停止才寫入', (tester) async {
    final recorder = _StatsRecorder();
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpStatsReader(
      tester,
      readingStatsTracker: recorder.tracker,
      readerKey: key,
    );

    recorder.tracker.recordActivity();
    ReaderScreen.reportTtsPlayingForTest(key, true);
    await tester.pump(const Duration(seconds: 10));
    moveAppToBackground(tester);
    await tester.pump();
    expect(recorder.total, 0, reason: '背景 TTS 播放中不應立即結算');

    await tester.pump(const Duration(seconds: 5));
    expect(recorder.total, 0);

    ReaderScreen.reportTtsPlayingForTest(key, false); // 睡眠定時器、耳機暫停等
    await tester.pump();
    expect(recorder.total, 15);

    await disposeStatsReader(tester);
  });

  testWidgets('兩個統計參數皆未提供：進出背景與離開閱讀器都正常，行為與現況相同',
      (tester) async {
    await pumpStatsReader(tester);

    moveAppToBackground(tester);
    await tester.pump();
    moveAppToForeground(tester);
    await tester.pump();

    await disposeStatsReader(tester);
    expect(tester.takeException(), isNull);
  });
}
```

- [x] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/reader_screen_stats_lifecycle_test.dart`
Expected: 編譯失敗，`The method 'reportTtsPlayingForTest' isn't defined for the type 'ReaderScreen'`。

- [x] **Step 3: 實作**

修改 `app/lib/screens/reader_screen.dart`，共六處（下列 (a)～(f)）。

(a) 靜態測試入口（放在既有 `openSleepTimerPickerForTest` 之後）：

尋找：

```dart
  static void openSleepTimerPickerForTest(GlobalKey<State<ReaderScreen>> key) {
    final state = key.currentState;
    if (state is _ReaderScreenState) {
      state._openSleepTimerPicker();
    }
  }
```

改為：

```dart
  static void openSleepTimerPickerForTest(GlobalKey<State<ReaderScreen>> key) {
    final state = key.currentState;
    if (state is _ReaderScreenState) {
      state._openSleepTimerPicker();
    }
  }

  /// 供測試直接回報「TTS 是否正在播放」給閱讀統計計時器
  /// （epic-9-stats Issue 4）：`flutter_test` 環境下 `TtsController` 永遠停在
  /// idle（見 [openSleepTimerPickerForTest] 的同類說明），無法經
  /// `_onTtsStatusChanged` 自然觸發，比照該入口新增。[key] 對應的 State
  /// 若尚未掛載，靜默忽略。
  static void reportTtsPlayingForTest(
    GlobalKey<State<ReaderScreen>> key,
    bool isPlaying,
  ) {
    final state = key.currentState;
    if (state is _ReaderScreenState) {
      state._forwardTtsPlaying(isPlaying);
    }
  }
```

(b) State 欄位：

尋找：

```dart
  late Zone _creationZone;
```

改為：

```dart
  late Zone _creationZone;

  /// 本次開書的閱讀統計計時器（epic-9-stats Issue 4）；兩個統計參數皆未提供
  /// 時為 `null`（完全不計時）。本 State 只負責轉送事件，不含任何計時邏輯。
  ReadingStatsTracker? _readingStatsTracker;
```

(c) `initState` 建立 tracker：

尋找：

```dart
    _creationZone = Zone.current;
    widget.readerActivityTracker?.markReaderOpened();
```

改為：

```dart
    _creationZone = Zone.current;
    widget.readerActivityTracker?.markReaderOpened();
    _readingStatsTracker = _createReadingStatsTracker();
```

(d) `dispose` 結算並寫入：

尋找：

```dart
  void dispose() {
    widget.readerActivityTracker?.markReaderClosed();
```

改為：

```dart
  void dispose() {
    widget.readerActivityTracker?.markReaderClosed();
    // 退出閱讀器：結算閱讀統計尾段並寫入（epic-9-stats Issue 4）。不 await
    // ——dispose() 是同步方法，比照下方 _writeCurrentPosition() 的既有慣例；
    // 寫入失敗由 tracker 內部吞下並記診斷日誌，不影響離開閱讀器。
    final statsTracker = _readingStatsTracker;
    if (statsTracker != null) unawaited(statsTracker.flushAndClose());
```

(e) 新增三個私有方法，並讓生命週期轉送（方法放在 `didChangeAppLifecycleState` 說明文件之前）：

尋找：

```dart
  /// App 進入背景時觸發一次位置寫入（spec.md「本機閱讀位置記憶」寫入
```

改為：

```dart
  /// 建立本次開書的閱讀統計計時器（epic-9-stats Issue 4）：有注入的
  /// [ReaderScreen.readingStatsTracker] 直接使用；否則有
  /// [ReaderScreen.readingStatsRepository] 就以本書 id、書名（原始書名，
  /// 不經簡繁轉換；未提供時退回 id）與 repository 的寫入方法、`onCleared`
  /// 建立；兩者皆無回傳 `null`（不計時）。
  ReadingStatsTracker? _createReadingStatsTracker() {
    final injected = widget.readingStatsTracker;
    if (injected != null) return injected;
    final repository = widget.readingStatsRepository;
    if (repository == null) return null;
    return ReadingStatsTracker(
      bookId: widget.bookId,
      bookTitle: widget.bookTitle ?? widget.bookId,
      onFlush: (date, bookId, bookTitle, seconds) =>
          repository.addReadingSeconds(
        date: date,
        bookId: bookId,
        bookTitle: bookTitle,
        seconds: seconds,
      ),
      onCleared: repository.onCleared,
    );
  }

  /// 回報一次閱讀活動（翻頁、捲動、長按劃線）。單純點擊叫出工具列不呼叫。
  void _recordReadingActivity() => _readingStatsTracker?.recordActivity();

  /// 回報 TTS 是否正在播放。tracker 對重複回報相同狀態是冪等的。
  void _forwardTtsPlaying(bool isPlaying) =>
      _readingStatsTracker?.onTtsPlayingChanged(isPlaying);

  /// App 進入背景時觸發一次位置寫入（spec.md「本機閱讀位置記憶」寫入
```

尋找：

```dart
    if (state == AppLifecycleState.paused) {
      _writeCurrentPosition();
    } else if (state == AppLifecycleState.resumed) {
```

改為：

```dart
    if (state == AppLifecycleState.paused) {
      _readingStatsTracker?.onEnteredBackground();
      _writeCurrentPosition();
    } else if (state == AppLifecycleState.resumed) {
      _readingStatsTracker?.onReturnedToForeground();
```

(f) TTS 狀態轉送：

尋找：

```dart
  void _onTtsStatusChanged() {
    final isActive = _isTtsActive;
```

改為：

```dart
  void _onTtsStatusChanged() {
    _forwardTtsPlaying(_ttsController?.status == TtsPlaybackStatus.playing);
    final isActive = _isTtsActive;
```

- [x] **Step 4: 執行測試，確認通過**

Run: `flutter test test/screens/reader_screen_stats_lifecycle_test.dart test/screens/reader_screen_stats_test.dart`
Expected: 全部通過。

- [x] **Step 5: 靜態分析**

Run: `flutter analyze lib/screens/reader_screen.dart test/screens`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add lib/screens/reader_screen.dart test/screens/reader_screen_stats_lifecycle_test.dart
git commit -m "feat(stats): epic-9 Issue 4 ReaderScreen 建立計時器並轉送 paused/resumed、TTS 狀態與退出結算"
```

---

### Task 3：閱讀活動來源

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_stats_activity_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `_recordReadingActivity()`、harness、`FakeReadingStatsRepository`（`addReadingSecondsError`、`getBookStatsForDate`、`getTotalReadingSeconds`）。
- Produces: 無（本 Task 只接線活動來源）。

- [x] **Step 1: 撰寫失敗的測試**

建立 `app/test/screens/reader_screen_stats_activity_test.dart`：

```dart
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/stats/reading_stats_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_reading_stats_repository.dart';
import 'reader_screen_stats_harness.dart';

void main() {
  registerReaderStatsTestEnvironment();

  testWidgets('僅注入 repository：開書後翻頁再進背景，repository 出現當日該書紀錄',
      (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(tester, readingStatsRepository: repository);

    reportLocator(tester, 1); // 開書後第一次回報（初始定位）：不算活動
    await tester.pump(const Duration(seconds: 10));
    reportLocator(tester, 2); // 翻頁：回溯採計開書後的 10 秒
    await tester.pump(const Duration(seconds: 20));
    moveAppToBackground(tester);
    await tester.pump();

    final stats = await repository.getBookStatsForDate(statsToday());
    expect(stats, hasLength(1));
    expect(stats.single.bookId, kStatsTestBookId);
    expect(stats.single.bookTitle, kStatsTestBookTitle);
    expect(stats.single.readingSeconds, 30);

    await disposeStatsReader(tester);
  });

  testWidgets('開書後立即退出，不產生時數', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(tester, readingStatsRepository: repository);

    await tester.pump(const Duration(seconds: 60));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 0);
  });

  testWidgets('開書後第一次位置回報（初始定位）不算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(tester, readingStatsRepository: repository);

    reportLocator(tester, 1);
    await tester.pump(const Duration(seconds: 60));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 0);
  });

  testWidgets('同一位置的重複回報（重排、圖片或字型載入造成）不算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(tester, readingStatsRepository: repository);

    reportLocator(tester, 1); // 初始定位
    await tester.pump(const Duration(milliseconds: 300));
    reportLocator(tester, 1); // 套用樣式重排後，Foliate 對同一位置再回報一次
    await tester.pump(const Duration(seconds: 90)); // 使用者沒有任何操作
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 0);
  });

  testWidgets('位置回報之間夾著同一位置的重複回報：位置真正改變的那一次仍算活動',
      (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(tester, readingStatsRepository: repository);

    reportLocator(tester, 1); // 初始定位
    await tester.pump(const Duration(milliseconds: 300));
    reportLocator(tester, 1); // 同一位置：不算
    await tester.pump(const Duration(seconds: 10));
    reportLocator(tester, 2); // 翻頁：算，回溯開書後約 10 秒
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    // 開書到翻頁共 10.3 秒（回溯採計），翻頁後 20 秒，合計 30.3 秒，取整數秒為 30。
    expect(await repository.getTotalReadingSeconds(), 30);
  });

  testWidgets('清除全部統計後，閱讀器仍在計時的 tracker 不會把清除前的秒數寫回',
      (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(tester, readingStatsRepository: repository);

    reportLocator(tester, 1);
    await tester.pump(const Duration(seconds: 10));
    reportLocator(tester, 2); // 確認 10 秒（尚未被 30 秒定時器寫入）
    await repository.clearAllStats(); // 使用者在統計畫面清除全部
    await tester.pump();
    await tester.pump(const Duration(seconds: 40)); // 第 30 秒的定時寫入不應寫回 10 秒
    await disposeStatsReader(tester); // 尾段：清除後的 40 秒

    expect(await repository.getTotalReadingSeconds(), 40);
  });

  testWidgets('未提供書名時，統計以 bookId 作為書名快照', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(
      tester,
      bookTitle: null,
      readingStatsRepository: repository,
    );

    reportLocator(tester, 1);
    await tester.pump(const Duration(seconds: 10));
    reportLocator(tester, 2);
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    final stats = await repository.getBookStatsForDate(statsToday());
    expect(stats, hasLength(1));
    expect(stats.single.bookTitle, kStatsTestBookId);
  });

  // 上一頁與下一頁各測一次：兩個方向各自有一行轉送，合在一起測會互相掩護。
  for (final action in [ZoneAction.nextPage, ZoneAction.previousPage]) {
    testWidgets('熱區 ${action.name} 算閱讀活動（回溯開書後 10 秒，再加翻頁後 20 秒）',
        (tester) async {
      final repository = FakeReadingStatsRepository();
      final key = GlobalKey<State<ReaderScreen>>();
      await pumpStatsReader(
        tester,
        readingStatsRepository: repository,
        readerKey: key,
      );

      await tester.pump(const Duration(seconds: 10));
      ReaderScreen.triggerZoneAction(key, action);
      await tester.pump(const Duration(seconds: 20));
      await disposeStatsReader(tester);

      expect(await repository.getTotalReadingSeconds(), 30);
    });
  }

  testWidgets('點擊叫出工具列（menu 熱區）不算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpStatsReader(
      tester,
      readingStatsRepository: repository,
      readerKey: key,
    );

    await tester.pump(const Duration(seconds: 30));
    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump(const Duration(seconds: 30));
    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump(const Duration(seconds: 30));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 0);
  });

  testWidgets('Foliate 長按選取（劃線）算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(tester, readingStatsRepository: repository);

    await tester.pump(const Duration(seconds: 10));
    tester
        .widget<FoliateReaderView>(find.byType(FoliateReaderView))
        .onSelectionChanged
        ?.call(
          const EpubSelectionInfo(
            locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
            progression: 0.1,
            rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
          ),
        );
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 30);
  });

  testWidgets('PDF：開書後第一次頁碼回報不算，之後的翻頁算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(
      tester,
      filePath: 'test/fixtures/sample_multi_page.pdf',
      readingStatsRepository: repository,
    );
    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));

    pdfView.onPageChanged
        ?.call(const PdfPageInfo(pageIndex: 0, totalPages: 5)); // 初始定位
    await tester.pump(const Duration(seconds: 10));
    pdfView.onPageChanged
        ?.call(const PdfPageInfo(pageIndex: 1, totalPages: 5)); // 翻頁：回溯 10 秒
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 30);
  });

  testWidgets('PDF 長按框選算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(
      tester,
      filePath: 'test/fixtures/sample_multi_page.pdf',
      readingStatsRepository: repository,
    );

    await tester.pump(const Duration(seconds: 10));
    tester
        .widget<PdfReaderView>(find.byType(PdfReaderView))
        .onSelectionRectComputed
        ?.call(
          const PdfSelectionInfo(
            pageIndex: 0,
            rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
            widgetRect:
                PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
          ),
        );
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 30);
  });

  testWidgets('PDF 零面積長按（未命中既有標註）是無效操作，不算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(
      tester,
      filePath: 'test/fixtures/sample_multi_page.pdf',
      readingStatsRepository: repository,
    );

    await tester.pump(const Duration(seconds: 10));
    tester
        .widget<PdfReaderView>(find.byType(PdfReaderView))
        .onSelectionRectComputed
        ?.call(
          const PdfSelectionInfo(
            pageIndex: 0,
            rect: PercentRect(left: 0.3, top: 0.2, right: 0.3, bottom: 0.2),
            widgetRect:
                PercentRect(left: 0.3, top: 0.2, right: 0.3, bottom: 0.2),
          ),
        );
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 0);
  });

  testWidgets('寫入失敗不影響閱讀：不崩潰、不顯示錯誤，離開時也安全', (tester) async {
    final repository = FakeReadingStatsRepository()
      ..addReadingSecondsError = StateError('database is locked');
    await pumpStatsReader(tester, readingStatsRepository: repository);

    reportLocator(tester, 1);
    await tester.pump(const Duration(seconds: 10));
    reportLocator(tester, 2);
    await tester.pump(const Duration(seconds: 40)); // 跨過 30 秒定時寫入（失敗）
    moveAppToBackground(tester);
    await tester.pump();
    moveAppToForeground(tester);
    await tester.pump();

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeStatsReader(tester);
    expect(tester.takeException(), isNull);
    expect(await repository.getTotalReadingSeconds(), 0);
  });

  testWidgets('同時注入 tracker 與 repository：以 tracker 為準，repository 不被寫入',
      (tester) async {
    final repository = FakeReadingStatsRepository();
    final flushed = <int>[];
    final tracker = ReadingStatsTracker(
      bookId: kStatsTestBookId,
      bookTitle: kStatsTestBookTitle,
      onFlush: (date, bookId, bookTitle, seconds) async => flushed.add(seconds),
    );
    await pumpStatsReader(
      tester,
      readingStatsRepository: repository,
      readingStatsTracker: tracker,
    );

    reportLocator(tester, 1);
    await tester.pump(const Duration(seconds: 10));
    reportLocator(tester, 2);
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    expect(flushed.fold<int>(0, (sum, s) => sum + s), 30);
    expect(await repository.getTotalReadingSeconds(), 0);
  });
}
```

- [x] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/reader_screen_stats_activity_test.dart`
Expected: 編譯通過；除「開書後立即退出」「第一次位置回報不算」「同一位置重複回報不算」「menu 不算」「PDF 零面積長按不算」「清除全部統計」「寫入失敗」這幾個「預期為 0」或鎖定既有行為的測試外，其餘（僅 repository 進背景、熱區翻頁、Foliate 選取、PDF 翻頁、PDF 框選、同時注入、位置改變仍算活動）失敗——因為活動尚未接線，`Expected: <30> Actual: <0>`。

- [x] **Step 3: 實作活動接線**

修改 `app/lib/screens/reader_screen.dart`，共六處（下列 (a)～(f)）。

(a) Foliate 位置回報（開書後第一次回報是初始定位、位置與上次相同的重複回報，皆不算）：

尋找：

```dart
            if (_epubPositionInfo != null) _hasRelocatedSinceOpen = true;
            setState(() => _epubPositionInfo = info);
```

改為：

```dart
            final previousPosition = _epubPositionInfo;
            if (previousPosition != null) {
              _hasRelocatedSinceOpen = true;
              // 不算閱讀活動的回報（epic-9-stats）：開書後第一次回報是初始定位
              // （上面 previousPosition 為 null 的情況）；位置與上一次相同的
              // 重複回報，是 Foliate 在開書後套用樣式重排、或圖片／字型載入後
              // 重新對齊錨點所派發的，不是使用者操作。位置真正改變（翻頁、
              // 捲動、跳轉）才算。
              if (previousPosition.locatorJson != info.locatorJson) {
                _recordReadingActivity();
              }
            }
            setState(() => _epubPositionInfo = info);
```

(b) PDF 頁碼回報（理由同上）：

尋找：

```dart
            if (_pdfPageInfo != null) _hasRelocatedSinceOpen = true;
            setState(() => _pdfPageInfo = info);
```

改為：

```dart
            if (_pdfPageInfo != null) {
              _hasRelocatedSinceOpen = true;
              _recordReadingActivity();
            }
            setState(() => _pdfPageInfo = info);
```

(c) 熱區上一頁（含音量鍵，載入中不算）：

尋找：

```dart
      case ZoneAction.previousPage:
        if (_state == _RenderState.loading) return;
```

改為：

```dart
      case ZoneAction.previousPage:
        if (_state == _RenderState.loading) return;
        _recordReadingActivity();
```

(d) 熱區下一頁：

尋找：

```dart
      case ZoneAction.nextPage:
        if (_state == _RenderState.loading) return;
```

改為：

```dart
      case ZoneAction.nextPage:
        if (_state == _RenderState.loading) return;
        _recordReadingActivity();
```

(e) Foliate 選取（長按劃線）：

尋找：

```dart
  void _handleSelectionChanged(EpubSelectionInfo info) {
    if (!mounted || _isFixedLayout) return;
```

改為：

```dart
  void _handleSelectionChanged(EpubSelectionInfo info) {
    if (!mounted) return;
    _recordReadingActivity(); // 長按選取（劃線）算閱讀活動
    if (_isFixedLayout) return;
```

(f) PDF 長按框選：

尋找：

```dart
      return;
    }
    setState(() {
      _currentPdfSelection = info;
```

改為：

```dart
      return;
    }
    // 放在退化選取守衛之後：沒命中既有標註的零面積長按（例如翻頁時手指多停留
    // 一下）是無效操作，不算閱讀活動；有效的拖曳框選或點選既有標註才算。
    _recordReadingActivity();
    setState(() {
      _currentPdfSelection = info;
```

- [x] **Step 4: 執行測試，確認通過**

Run: `flutter test test/screens/reader_screen_stats_activity_test.dart test/screens/reader_screen_stats_lifecycle_test.dart test/screens/reader_screen_stats_test.dart`
Expected: 全部通過。

- [x] **Step 5: 靜態分析**

Run: `flutter analyze lib/screens/reader_screen.dart test/screens`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add lib/screens/reader_screen.dart test/screens/reader_screen_stats_activity_test.dart
git commit -m "feat(stats): epic-9 Issue 4 ReaderScreen 轉送閱讀活動（位置回報、熱區翻頁、長按選取）"
```

---

### Task 4：最終驗證

**Files:**
- 無新增或修改（只驗證；失敗才回頭修對應 Task）。

- [x] **Step 1: 既有相關測試零回歸**

Run: `flutter test test/screens/reader_screen_test.dart test/screens/reader_screen_route_test.dart test/screens/library_screen_dependencies_test.dart test/screens/library_search_screen_test.dart test/screens/book_search_screen_test.dart test/screens/library_screen_test.dart test/elinkbook_app_wiring_test.dart`
Expected: 全部通過。

- [x] **Step 2: 確認 `ReaderScreen` 沒有計時邏輯**

Run: `grep -nE "Timer\(|Timer\.periodic|DateTime\.now\(\)|Stopwatch" lib/screens/reader_screen.dart | grep -in "stats\|統計"`
Expected: 無任何輸出（統計相關的行不含計時器或時間讀取）。

- [x] **Step 3: 靜態分析與字串檢查**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `node tool/check_l10n_hardcoded_strings.js`
Expected: 通過（本 Issue 沒有新增使用者可見字串）。

- [x] **Step 4: 完整測試**

Run: `flutter test`
Expected: 全部通過、0 失敗（既有 1 個略過為已知既有測試）。記下通過／略過數與分支 HEAD，供 PR 說明使用。

- [x] **Step 5: 突變驗證（證明測試抓得到錯）**

逐一在 `lib/screens/reader_screen.dart`（或指定檔案）套用下列修改，執行 `flutter test test/screens/reader_screen_stats_lifecycle_test.dart test/screens/reader_screen_stats_activity_test.dart test/screens/reader_screen_stats_test.dart test/screens/reader_screen_route_test.dart`，**必須出現失敗**；確認後 `git checkout -- <檔案>` 還原，再做下一個：

1. 拿掉 `didChangeAppLifecycleState` 內的 `_readingStatsTracker?.onEnteredBackground();`。
2. 拿掉 `didChangeAppLifecycleState` 內的 `_readingStatsTracker?.onReturnedToForeground();`。
3. 拿掉 `dispose()` 內的 `unawaited(statsTracker.flushAndClose())`（整個 `if` 那行）。
4. 拿掉 Foliate `onLocatorChanged` 內的 `_recordReadingActivity();`。
5. 把 Foliate `onLocatorChanged` 改成每次都記錄（`_recordReadingActivity();` 移到 `if (_epubPositionInfo != null)` 之外）。
6. 在 `case ZoneAction.menu:` 內加一行 `_recordReadingActivity();`。
7. 拿掉 `_openBookSearch` 內的 `readingStatsRepository: widget.readingStatsRepository,`。
8. 拿掉 `reader_screen_route.dart` 內的 `readingStatsRepository: features.readingStatsRepository,`。
9. `_createReadingStatsTracker()` 開頭那行 `if (injected != null) return injected;` 移到 repository 判斷之後（讓 repository 優先）。
10. 拿掉 PDF `onPageChanged` 內的 `_recordReadingActivity();`。
11. 拿掉 `case ZoneAction.nextPage:` 內新增的 `_recordReadingActivity();`。
12. 拿掉 `case ZoneAction.previousPage:` 內新增的 `_recordReadingActivity();`。
13. 拿掉 `_handleSelectionChanged` 內的 `_recordReadingActivity();`。
14. 拿掉 `_handlePdfSelectionRectComputed` 內的 `_recordReadingActivity();`。
15. 把 `_handlePdfSelectionRectComputed` 內的 `_recordReadingActivity();` 移到退化選取守衛（`if (isDegenerate && ... ) { return; }`）之前。
16. 拿掉 Foliate 位置回報內「位置與上次不同」的比較（改成一律記錄，`if (previousPosition.locatorJson != info.locatorJson) {` 換成 `if (true) {`）。
17. 拿掉 `_createReadingStatsTracker()` 內的 `onCleared: repository.onCleared,`。
18. 把 `bookTitle: widget.bookTitle ?? widget.bookId,` 改成 `bookTitle: widget.bookTitle ?? '',`。
19. 拿掉 `_onTtsStatusChanged` 內的 `_forwardTtsPlaying(...)` 那行——**預期不會被抓到**（widget test 觸及不到 `TtsController` 的狀態變化，見 Global Constraints），不要為了讓它被抓到而改測試；改由 Step 6 真機確認。

Expected: 1～18 各至少有一個測試失敗；19 存活是預期的。

- [x] **Step 6: 真機確認（選用，有裝置時才做，不阻擋本 Issue 完成）**（2026-09-29 完成，結果見 `epic.md`「Issue 4 真機確認記錄」）

`integration_test/reader_stats_test.dart`（issues.md 標為選用）**不在本計畫範圍**；有真機時改用人工確認，並把結果記進 `epic.md` 的完成記錄：
1. 開一本 EPUB，不動作，等 30 秒後退出。預期：統計資料庫沒有新增紀錄（確認 Review Focus 第 1 項——開書後沒有其他非使用者操作的位置回報被當成活動）。
2. 開書後翻頁數次、停留約 1 分鐘再退出。預期：當日該書累計約 1 分鐘上下。
3. 開始朗讀後切到背景，等 1 分鐘再暫停朗讀。預期：時數包含背景朗讀的 1 分鐘。

- [x] **Step 7: 回報**

在最終回報列出：三個新 ReaderScreen 測試檔與四個既有測試檔的通過數、完整 `flutter test` 結果（含 HEAD）、19 個突變的驗證結果，以及 Step 6 是否已做。
