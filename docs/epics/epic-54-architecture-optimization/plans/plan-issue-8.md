# Issue 8：閱讀會話生命週期協調 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 把 `ReaderScreen` 裡「與一次閱讀的資料有關」的副作用（閱讀統計的建立與收尾、閱讀活動判定、5 分鐘 Checkpoint Timer、`markReaderOpened`／`markReaderClosed`、前後景切換、離開時的收尾順序，以及 Issue 7 的 `ReadingPositionSaver`）收進一個不依賴 Widget 的新 module `ReadingSession`，讓 `ReaderScreen` 只丟視圖事件進去；行為零變化。

**Architecture：** 新增 `app/lib/reader/reading_session.dart`。`ReaderScreen` 在 `initState` 建立一個 `ReadingSession`（不新增任何建構參數，用既有的 `readingStatsTracker`／`readingStatsRepository`／`syncCheckpointTrigger`／`readerActivityTracker`／`bookTitle` 組裝），之後只呼叫它的事件方法。session 內部持有 `ReadingPositionSaver`（偏好載入後才建立）、統計 tracker、Timer；「這次 relocate 算不算閱讀活動」的判斷（Foliate 比 cfi＋index、PDF 第二次起算）也搬進來。`ReaderScreen` 仍保留自己的 `_epubPositionInfo`／`_pdfPageInfo`（驅動頁尾 UI），session 自己另存「上一次位置」做活動判斷。

**Tech Stack：** Flutter／Dart、`flutter_test`、`fake_async`（已在 `dev_dependencies`）。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立的 `spec.md`，設計依據是 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 7、8 設計決策」（決策 2～9）；詞彙見 `CONTEXT.md`「閱讀會話」「閱讀活動」「Checkpoint 同步」；Issue 7 的先例見 `plans/plan-issue-7.md`。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **純重構、零行為變化**（epic.md 決策 6）：以下逐字保留，不得「順便修好」——(1) 位置寫入與統計 flush 都不 await（`save` 的 Future 直接丟掉、`flushAndClose` 用 `unawaited`）；(2) `paused` 只做「統計 `onEnteredBackground` → 儲存位置」，**不觸發 Checkpoint**；(3) 離開時 session 內部順序固定為 `markReaderClosed` → 統計 `flushAndClose` → 取消 Timer → 儲存位置 → 觸發 Checkpoint（儲存必須在觸發之前）。
- **一個已接受的順序差異（Review Focus 第 1 條驗證）**：現有 `dispose()` 把上述五步與畫面自己的收尾（`_openBookFlow`、搜尋高亮 timer、睡眠定時器、音量鍵 channel、TTS 與 audio focus）穿插在一起；改成一次 `session.close(...)` 後，儲存位置與觸發 Checkpoint 會**早於**畫面自己的收尾執行。已逐項確認畫面自己的收尾都不讀取 session 管理的任何狀態，所以可觀察行為相同；若實作時發現任何一項有相依，停下來回報，不要自行調整。
- **範圍外**：不動 `SyncEngine`、`ReadingStatsTracker`、`ReadingPositionSaver`、`SyncCheckpointTrigger`、`ReaderActivityTracker` 的內部；不動睡眠定時器、搜尋高亮 timer、音量鍵、螢幕方向、全螢幕、TTS（留在畫面，epic.md 決策 4）；不修 Issue 9（缺陷，見 `epic.md`）；不新增 `ReaderScreen` 建構參數（目前 27 個）。
- **`ReaderScreen` 保留自己的 `_pdfPageInfo`／`_epubPositionInfo`**：它們還驅動頁尾顯示，不得移除。
- **測試原則（replace, don't layer）**：生命週期與活動判定規則放在新的單元測試；`ReaderScreen` 層只保留接線案例。盤點結果見 Task 2 Step 1：共刪 2 個已被單元測試取代的純規則 widget 案例，其餘全部保留。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，用 `run_in_background`，**且必須在 `app/` 目錄下執行**，否則會得到 `Test directory "test" not found.`）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：用 Bash 工具（Git Bash）；`python` 不可用來編輯檔案；多數原始檔是 CRLF，Edit 的定位字串不要含換行。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：計畫先審查再動手；程式審查先出報告（存於 `reviews/`，gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。

## Review Focus

最可能咬到使用者的情況（依可能性排序），每條都有對應測試：

1. **離開閱讀畫面時，位置沒存到、或統計沒結算。** 順序一亂（先觸發 Checkpoint 再儲存位置、或漏掉統計 flush），最新位置不會被這次 Checkpoint 推送，閱讀時數遺失。→ Task 1 測離開時事件順序為 `closed → flush → save → trigger`；Task 2 保留既有「離開觸發一次 checkpoint」與統計「離開閱讀器」widget 案例。
2. **App 進背景時多觸發了 Checkpoint，或漏存位置。** 這是現況刻意的行為（進背景只存位置與結算統計）。→ Task 1 測 `paused` 的事件為 `background → save` 且沒有 `trigger`；`app_lifecycle_sync_test.dart` 守住 App 層級的 Checkpoint。
3. **重排造成的「同位置重複回報」被誤算成閱讀活動，灌水閱讀時數。** → Task 1 測「首次回報不算」「同 cfi＋index 但 fraction 抖動不算」「cfi 改變才算」「cfi 無法解析時退回整段字串比較」；PDF 測「首次不算、第二次起算」。
4. **離開畫面後 Timer 還在跑，或沒提供 trigger 卻建立了 Timer。** → Task 1 用 `fakeAsync` 測「每 5 分鐘一次」「離開後不再觸發」「未提供 trigger 不拋例外」。
5. **偏好尚未載入完成就離開（或收到回報）。** session 的位置儲存器尚未建立，不得拋例外，也不得儲存。→ Task 1 測 `onPrefsLoaded` 之前呼叫 `close`／`onAppPaused`／位置回報都安全；全部統計參數缺省時（tracker 為 null）各方法皆安全；正式環境只傳 `statsRepository`（`main.dart` 不傳 tracker），所以「僅提供 repository 時由 session 建立 tracker、寫入正確的秒數與書名」「未提供書名退回 bookId」「注入 tracker 優先」三個單元案例也守在這裡。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/reading_session.dart` | 新增 | `ReadingSession`：開關、前後景、位置回報、活動判定、Checkpoint Timer、離開收尾順序 |
| `app/test/reader/reading_session_test.dart` | 新增 | 以假 tracker／假偏好管理器／`fakeAsync` 直接驗證上述規則 |
| `app/lib/screens/reader_screen.dart` | 修改 | 刪除 `_readingStatsTracker`、`_createReadingStatsTracker`、`_syncCheckpointTimer`、`_positionSaver`、`_locatorPositionKey`、`_recordReadingActivity`、`_forwardTtsPlaying`；新增 `_session` 與呼叫點 |
| `app/test/screens/reader_screen_stats_activity_test.dart` | 修改 | 刪 2 個純規則案例（見 Task 2 Step 1） |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 開發記錄、狀態 |

---

### Task 0：提交計畫、建立 worktree

**Files：**
- Commit：本計畫檔與 `issues.md` 狀態更新（在 `main` 上，純文件）
- 建立 worktree：`.worktrees/epic-54-issue-8-reading-session`（`.worktrees/` 已 gitignore）

**Interfaces：**
- Consumes：無。
- Produces：分支 `epic-54/issue-8-reading-session`，後續 Task 都在這個 worktree 的 `app/` 下執行。

- [ ] **Step 1：在 `main` 提交計畫**

先把 `issues.md` 第 8 列狀態由「⚪ 未開始…」改為「🟡 進行中（計畫已寫）」，然後：

```bash
cd /c/Users/fycdc/AI/elinkBook
git add docs/epics/epic-54-architecture-optimization/plans/plan-issue-8.md docs/epics/epic-54-architecture-optimization/issues.md
git commit -m "docs(epic-54): Issue 8 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2：建立 worktree 並安裝依賴**

```bash
git worktree add .worktrees/epic-54-issue-8-reading-session -b epic-54/issue-8-reading-session
cd .worktrees/epic-54-issue-8-reading-session/app && flutter pub get
```

預期：`Got dependencies!`。

- [ ] **Step 3：確認基準測試通過並記下數字**

```bash
flutter test test/screens/reader_screen_test.dart test/screens/reader_screen_stats_lifecycle_test.dart test/screens/reader_screen_stats_activity_test.dart test/screens/reader_screen_stats_test.dart test/app_lifecycle_sync_test.dart test/reader/reading_position_saver_test.dart
```

預期：全數通過。記下通過數（Task 2 完成後應為這個數字減 2，因為刪了 2 個 widget 案例）。

---

### Task 1：`ReadingSession` 與單元測試

**Files：**
- Create：`app/lib/reader/reading_session.dart`
- Test：`app/test/reader/reading_session_test.dart`

**Interfaces：**
- Consumes：`ReadingPositionSaver`（`lib/reader/reading_position_saver.dart`，Issue 7：`onPdfPageChanged`／`onEpubLocated`／`save(BookFormat)`）、`ReadingStatsTracker`（`recordActivity`／`onEnteredBackground`／`onReturnedToForeground`／`onTtsPlayingChanged(bool)`／`Future<void> flushAndClose()`）、`ReadingStatsRepository`（`addReadingSeconds`、`onCleared`）、`SyncCheckpointTrigger.trigger()`、`ReaderActivityTracker.markReaderOpened/Closed`、`ReaderPrefsManager`、`BookFormat`、`EpubPositionInfo`、`PdfPageInfo`。
- Produces（Task 2 依賴）：

```dart
class ReadingSession {
  ReadingSession({
    required String bookId,
    required ReaderPrefsManager prefsManager,
    required bool hasJumpTarget,        // widget.initialJumpTarget != null
    String? bookTitle,                  // 未提供時統計以 bookId 當書名快照
    ReadingStatsTracker? statsTracker,  // 注入優先
    ReadingStatsRepository? statsRepository,
    SyncCheckpointTrigger? syncCheckpointTrigger,
    ReaderActivityTracker? readerActivityTracker,
    Duration checkpointInterval = const Duration(minutes: 5),
  });
  void start();                                       // markReaderOpened＋建立週期 Timer
  void onPrefsLoaded({required double initialProgress}); // 建立位置儲存器
  void onEpubLocated(EpubPositionInfo info);
  void onPdfPageChanged(PdfPageInfo info);
  void recordActivity();                              // 長按劃線、翻頁熱區等
  void onTtsPlayingChanged(bool isPlaying);
  void onAppPaused(BookFormat format);
  void onAppResumed();
  void close(BookFormat format);
}
```

**行為規則表**（對照現有 `ReaderScreen`，逐條成為測試）：

| # | 事件 | 結果 |
|---|---|---|
| 1 | `start()` | `readerActivityTracker?.markReaderOpened()`；有 `syncCheckpointTrigger` 才建立 `checkpointInterval` 週期 Timer，每次呼叫 `trigger()` |
| 2 | `onPrefsLoaded` | 建立位置儲存器（`initialProgress` 為開書時既有進度） |
| 3 | `onEpubLocated(info)` | 先轉發給位置儲存器（若已建立）；再判斷活動：**有上一次 Foliate 位置** 且 `cfi\|index` 與上次不同 → 統計 `recordActivity()`；首次回報不算；同 cfi＋index（fraction 抖動）不算；`locatorJson` 解析失敗時退回整段字串比較；最後記住本次位置 |
| 4 | `onPdfPageChanged(info)` | 先轉發給位置儲存器；**第二次起**統計 `recordActivity()`（首次不算）；記住已收過 |
| 5 | `recordActivity()` | 統計 `recordActivity()` |
| 6 | `onTtsPlayingChanged(p)` | 統計 `onTtsPlayingChanged(p)` |
| 7 | `onAppPaused(format)` | 統計 `onEnteredBackground()` → 位置儲存器 `save(format)`；**不觸發 Checkpoint** |
| 8 | `onAppResumed()` | 統計 `onReturnedToForeground()` |
| 9 | `close(format)` | 依序：`markReaderClosed` → 統計 `unawaited(flushAndClose())` → 取消 Timer → 位置儲存器 `save(format)` → `syncCheckpointTrigger?.trigger()` |

統計 tracker 的取得：有 `statsTracker` 直接用；否則有 `statsRepository` 就以 `bookId`、`bookTitle ?? bookId`、repository 的 `addReadingSeconds` 與 `onCleared` 建立；兩者皆無則為 null（所有統計呼叫都是無動作）。

- [ ] **Step 1：寫失敗測試**

建立 `app/test/reader/reading_session_test.dart`：

```dart
import 'package:fake_async/fake_async.dart';
import 'package:elinkbook/reader/book_format.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/reading_session.dart';
import 'package:elinkbook/stats/reading_stats_tracker.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_reading_stats_repository.dart';

/// 把所有互動記進同一份 log，才能驗證跨物件的先後順序。
class _FakeStatsTracker extends ReadingStatsTracker {
  _FakeStatsTracker(this.log)
      : super(
          bookId: 'b1',
          bookTitle: '書',
          onFlush: (date, bookId, bookTitle, seconds) async {},
        );
  final List<String> log;

  @override
  void recordActivity() => log.add('activity');
  @override
  void onEnteredBackground() => log.add('background');
  @override
  void onReturnedToForeground() => log.add('foreground');
  @override
  void onTtsPlayingChanged(bool isPlaying) => log.add('tts:$isPlaying');
  @override
  Future<void> flushAndClose() async => log.add('flush');
}

class _LoggingPrefs extends FakeReaderPrefsManager {
  _LoggingPrefs(this.log);
  final List<String> log;

  @override
  Future<void> saveReadingPosition(String bookId, ReadingPosition position) {
    log.add('save');
    return super.saveReadingPosition(bookId, position);
  }
}

/// 在 fakeAsync 內同步取得 Future 的結果（先 flushMicrotasks 再讀）。
T _resolve<T>(FakeAsync async, Future<T> future) {
  late T value;
  future.then((v) => value = v);
  async.flushMicrotasks();
  return value;
}

EpubPositionInfo _loc(String cfi, {int index = 0, double fraction = 0.1}) =>
    EpubPositionInfo(
      locatorJson: '{"cfi":"$cfi","index":$index,"fraction":$fraction}',
      progression: fraction,
    );

void main() {
  late List<String> log;
  late _LoggingPrefs prefs;

  setUp(() {
    log = [];
    prefs = _LoggingPrefs(log);
  });

  SyncCheckpointTrigger buildTrigger() => SyncCheckpointTrigger(
        runCheckpoint: () async {
          log.add('trigger');
          return SyncCheckpointResult.synced;
        },
      );

  ReadingSession build({
    bool hasJumpTarget = false,
    bool withStats = true,
    bool withTrigger = true,
    ReaderActivityTracker? activity,
  }) =>
      ReadingSession(
        bookId: 'b1',
        prefsManager: prefs,
        hasJumpTarget: hasJumpTarget,
        statsTracker: withStats ? _FakeStatsTracker(log) : null,
        syncCheckpointTrigger: withTrigger ? buildTrigger() : null,
        readerActivityTracker: activity,
      );

  group('離開（close）的收尾順序', () {
    test('markReaderClosed → 統計 flush → 儲存位置 → 觸發 Checkpoint', () {
      final activity = ReaderActivityTracker();
      activity.addListener(
          () => log.add(activity.isReaderOpen ? 'opened' : 'closed'));
      final session = build(activity: activity)..start();
      session.onPrefsLoaded(initialProgress: 0);
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 3, totalPages: 10));
      log.clear(); // 只看 close 之後的事件，並排除 start 的 'opened'

      session.close(BookFormat.pdf);

      expect(log, ['closed', 'flush', 'save', 'trigger']);
    });

    test('偏好尚未載入完成就離開：不儲存、不拋例外，仍結算統計並觸發 Checkpoint', () {
      final session = build()..start();
      log.clear();
      session.close(BookFormat.pdf);
      expect(log, ['flush', 'trigger']);
    });

    test('沒有統計與 trigger 也能安全離開', () {
      final session = build(withStats: false, withTrigger: false)..start();
      session.onPrefsLoaded(initialProgress: 0);
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 0, totalPages: 5));
      session.close(BookFormat.pdf);
      expect(log, ['save']);
    });

    test('readerActivityTracker：start 標記開啟、close 標記關閉', () {
      final activity = ReaderActivityTracker();
      final session = build(activity: activity);
      expect(activity.isReaderOpen, isFalse);
      session.start();
      expect(activity.isReaderOpen, isTrue);
      session.close(BookFormat.pdf);
      expect(activity.isReaderOpen, isFalse);
    });
  });

  group('前後景', () {
    test('paused：統計進背景 → 儲存位置，且不觸發 Checkpoint', () {
      final session = build()..start();
      session.onPrefsLoaded(initialProgress: 0);
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 1, totalPages: 5));
      log.clear();

      session.onAppPaused(BookFormat.pdf);

      expect(log, ['background', 'save']);
    });

    test('paused 時偏好尚未載入：只通知統計，不儲存、不拋例外', () {
      final session = build()..start();
      log.clear();
      session.onAppPaused(BookFormat.pdf);
      expect(log, ['background']);
    });

    test('resumed：通知統計回到前景', () {
      final session = build()..start();
      log.clear();
      session.onAppResumed();
      expect(log, ['foreground']);
    });
  });

  group('Checkpoint 週期 Timer', () {
    test('每 5 分鐘觸發一次，離開後不再觸發', () {
      fakeAsync((async) {
        final session = build()..start();
        async.elapse(const Duration(minutes: 5));
        expect(log.where((e) => e == 'trigger'), hasLength(1));
        async.elapse(const Duration(minutes: 5));
        expect(log.where((e) => e == 'trigger'), hasLength(2));

        session.close(BookFormat.pdf); // close 本身會再觸發一次
        final afterClose = log.where((e) => e == 'trigger').length;
        async.elapse(const Duration(minutes: 30));
        expect(log.where((e) => e == 'trigger').length, afterClose);
      });
    });

    test('未提供 trigger：不建立 Timer，經過任意時間也不拋例外', () {
      fakeAsync((async) {
        final session = build(withTrigger: false)..start();
        async.elapse(const Duration(minutes: 30));
        expect(log, isNot(contains('trigger')));
        session.close(BookFormat.pdf);
      });
    });
  });

  group('閱讀活動判定：Foliate', () {
    test('首次回報（初始定位）不算活動', () {
      final session = build()..start();
      log.clear();
      session.onEpubLocated(_loc('a'));
      expect(log, isNot(contains('activity')));
    });

    test('同 cfi 與 index 的重複回報不算活動', () {
      final session = build()..start();
      session.onEpubLocated(_loc('a'));
      log.clear();
      session.onEpubLocated(_loc('a'));
      expect(log, isNot(contains('activity')));
    });

    test('同 cfi 只有 fraction 抖動不算活動', () {
      final session = build()..start();
      session.onEpubLocated(_loc('a', fraction: 0.10));
      log.clear();
      session.onEpubLocated(_loc('a', fraction: 0.11));
      expect(log, isNot(contains('activity')));
    });

    test('cfi 改變才算活動；重複回報夾在中間不影響之後的判定', () {
      final session = build()..start();
      session.onEpubLocated(_loc('a'));
      session.onEpubLocated(_loc('a', fraction: 0.2));
      log.clear();
      session.onEpubLocated(_loc('b'));
      expect(log, ['activity']);
    });

    test('index 改變也算活動', () {
      final session = build()..start();
      session.onEpubLocated(_loc('a', index: 0));
      log.clear();
      session.onEpubLocated(_loc('a', index: 1));
      expect(log, ['activity']);
    });

    test('locatorJson 無法解析時退回整段字串比較', () {
      final session = build()..start();
      session.onEpubLocated(const EpubPositionInfo(locatorJson: 'not-json-1'));
      log.clear();
      session.onEpubLocated(const EpubPositionInfo(locatorJson: 'not-json-1'));
      expect(log, isNot(contains('activity')));
      session.onEpubLocated(const EpubPositionInfo(locatorJson: 'not-json-2'));
      expect(log, ['activity']);
    });
  });

  group('閱讀活動判定：PDF', () {
    test('首次頁碼回報不算，第二次起算', () {
      final session = build()..start();
      log.clear();
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 0, totalPages: 5));
      expect(log, isNot(contains('activity')));
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 1, totalPages: 5));
      expect(log, ['activity']);
    });
  });

  group('位置回報轉發給位置儲存器', () {
    test('Foliate 回報在 paused 時被儲存', () {
      final session = build()..start();
      session.onPrefsLoaded(initialProgress: 0);
      session.onEpubLocated(_loc('a', fraction: 0.4));
      session.onAppPaused(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls.single.value.epubLocatorJson,
          contains('"cfi":"a"'));
    });

    test('有跳轉目標：只有首次回報就離開，不儲存', () {
      final session = build(hasJumpTarget: true)..start();
      session.onPrefsLoaded(initialProgress: 0.5);
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 2, totalPages: 5));
      session.close(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('偏好載入前收到的位置回報不會讓位置儲存器之後誤存', () {
      final session = build()..start();
      session.onPdfPageChanged(const PdfPageInfo(pageIndex: 4, totalPages: 5));
      session.onPrefsLoaded(initialProgress: 0);
      session.close(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });
  });

  group('統計來源（正式環境只傳 statsRepository，由 session 建立 tracker）', () {
    // 計時語意比照 reader_screen_stats_activity_test：開書後 10 秒出現第一次
    // 活動（回溯採計 10 秒），再過 20 秒離開（尾段採計 20 秒），共 30 秒。
    test('僅提供 statsRepository：離開時把閱讀秒數與書名寫入 repository', () {
      fakeAsync((async) {
        final repository = FakeReadingStatsRepository();
        final session = ReadingSession(
          bookId: 'b1',
          bookTitle: '自訂書名',
          prefsManager: prefs,
          hasJumpTarget: false,
          statsRepository: repository,
        )..start();

        async.elapse(const Duration(seconds: 10));
        session.recordActivity();
        async.elapse(const Duration(seconds: 20));
        session.close(BookFormat.pdf);
        async.flushMicrotasks();

        expect(_resolve(async, repository.getTotalReadingSeconds()), 30);
        final date = _resolve(
          async,
          repository.getDailyTotals(startDate: '0000-01-01', endDate: '9999-12-31'),
        ).keys.single;
        final stats = _resolve(async, repository.getBookStatsForDate(date));
        expect(stats.single.bookId, 'b1');
        expect(stats.single.bookTitle, '自訂書名');
      });
    });

    test('未提供書名：統計以 bookId 作為書名快照', () {
      fakeAsync((async) {
        final repository = FakeReadingStatsRepository();
        final session = ReadingSession(
          bookId: 'b1',
          prefsManager: prefs,
          hasJumpTarget: false,
          statsRepository: repository,
        )..start();

        async.elapse(const Duration(seconds: 10));
        session.recordActivity();
        async.elapse(const Duration(seconds: 20));
        session.close(BookFormat.pdf);
        async.flushMicrotasks();

        final date = _resolve(
          async,
          repository.getDailyTotals(startDate: '0000-01-01', endDate: '9999-12-31'),
        ).keys.single;
        final stats = _resolve(async, repository.getBookStatsForDate(date));
        expect(stats.single.bookTitle, 'b1');
      });
    });

    test('同時提供 statsTracker 與 statsRepository：以注入的 tracker 為準，repository 不被寫入', () {
      fakeAsync((async) {
        final repository = FakeReadingStatsRepository();
        final session = ReadingSession(
          bookId: 'b1',
          prefsManager: prefs,
          hasJumpTarget: false,
          statsTracker: _FakeStatsTracker(log),
          statsRepository: repository,
        )..start();

        async.elapse(const Duration(seconds: 10));
        session.recordActivity();
        async.elapse(const Duration(seconds: 20));
        session.close(BookFormat.pdf);
        async.flushMicrotasks();

        expect(log, containsAll(['activity', 'flush']));
        expect(_resolve(async, repository.getTotalReadingSeconds()), 0);
      });
    });
  });

  group('其他事件的轉發', () {
    test('recordActivity 與 onTtsPlayingChanged 轉給統計', () {
      final session = build()..start();
      log.clear();
      session.recordActivity();
      session.onTtsPlayingChanged(true);
      session.onTtsPlayingChanged(false);
      expect(log, ['activity', 'tts:true', 'tts:false']);
    });

    test('沒有統計 tracker 時所有統計事件皆為無動作', () {
      final session = build(withStats: false)..start();
      session.recordActivity();
      session.onTtsPlayingChanged(true);
      session.onAppPaused(BookFormat.pdf);
      session.onAppResumed();
      session.onEpubLocated(_loc('a'));
      session.onEpubLocated(_loc('b'));
      expect(log, isEmpty);
    });
  });
}
```

> 最後一個「偏好載入前收到的位置回報」案例是在記錄現況：現有 `ReaderScreen` 的回呼只有在 `_positionSaver` 已建立後才轉發（`?.`），所以載入前的回報會被丟棄；`ReadingSession` 以「saver 尚未建立就不轉發」保持同樣行為。這與 Issue 7 審查 Minor 2 相同，維持現狀，不在本 Issue 改。

- [ ] **Step 2：執行測試確認失敗**

```bash
flutter test test/reader/reading_session_test.dart
```

預期：編譯失敗，`reading_session.dart` 不存在。

- [ ] **Step 3：寫最小實作**

建立 `app/lib/reader/reading_session.dart`：

```dart
import 'dart:async';
import 'dart:convert';

import '../stats/reading_stats_repository.dart';
import '../stats/reading_stats_tracker.dart';
import '../sync/sync_checkpoint_trigger.dart';
import 'book_format.dart';
import 'epub_position_info.dart';
import 'pdf_page_info.dart';
import 'reader_activity_tracker.dart';
import 'reader_prefs_manager.dart';
import 'reading_position_saver.dart';

/// 一次閱讀會話（見 `CONTEXT.md`「閱讀會話」，`epic-54-architecture-optimization`
/// Issue 8）：從閱讀畫面開啟到離開，一個畫面對應一本書。
///
/// 負責與「這次閱讀的資料」有關的事：閱讀統計的起訖、閱讀活動判定、進入
/// 背景與回到前景的處置、離開與定期觸發的 Checkpoint 同步、離開時儲存閱讀
/// 位置。與裝置畫面狀態有關的事（音量鍵、螢幕方向、全螢幕、朗讀播放）不屬於
/// 會話。呼叫端在 `initState` 建立並呼叫 [start]，之後只轉發事件。
///
/// 不等待任何儲存或統計寫入完成；沒趕上的位置由下一次 Checkpoint 補送。
class ReadingSession {
  ReadingSession({
    required this.bookId,
    required this.prefsManager,
    required this.hasJumpTarget,
    this.bookTitle,
    ReadingStatsTracker? statsTracker,
    ReadingStatsRepository? statsRepository,
    this.syncCheckpointTrigger,
    this.readerActivityTracker,
    this.checkpointInterval = const Duration(minutes: 5),
  }) : _stats = statsTracker ??
            _statsTrackerFor(bookId, bookTitle ?? bookId, statsRepository);

  final String bookId;
  final ReaderPrefsManager prefsManager;

  /// 開書時是否帶有跳轉目標（例如從搜尋結果、書籤開啟）。
  final bool hasJumpTarget;

  /// 統計用的書名快照（原始書名，不經簡繁轉換）；未提供時退回 [bookId]。
  final String? bookTitle;

  final SyncCheckpointTrigger? syncCheckpointTrigger;
  final ReaderActivityTracker? readerActivityTracker;
  final Duration checkpointInterval;

  /// 兩個統計來源皆未提供時為 null（完全不計時，所有統計呼叫為無動作）。
  final ReadingStatsTracker? _stats;

  /// 偏好載入完成後（取得開書時既有的進度）才建立，見 [onPrefsLoaded]。
  ReadingPositionSaver? _positionSaver;

  Timer? _checkpointTimer;

  /// 上一次 Foliate／PDF 位置回報，只用來判斷「這次算不算閱讀活動」。
  EpubPositionInfo? _lastEpubInfo;
  bool _hasPdfInfo = false;

  /// 標記閱讀畫面已開啟，並在有 [syncCheckpointTrigger] 時建立週期性 Checkpoint
  /// Timer。單純的週期性 Timer，不判斷使用者是否真的有互動；未提供 trigger
  /// 時完全不建立。
  void start() {
    readerActivityTracker?.markReaderOpened();
    final trigger = syncCheckpointTrigger;
    if (trigger != null) {
      _checkpointTimer =
          Timer.periodic(checkpointInterval, (_) => trigger.trigger());
    }
  }

  /// 偏好載入完成：以開書時既有位置的進度建立位置儲存器。
  void onPrefsLoaded({required double initialProgress}) {
    _positionSaver = ReadingPositionSaver(
      bookId: bookId,
      prefsManager: prefsManager,
      hasJumpTarget: hasJumpTarget,
      initialProgress: initialProgress,
    );
  }

  /// Foliate 格式的位置回報。位置真正改變（cfi 或 index 不同）才算閱讀活動：
  /// 開書後第一次回報是初始定位；位置相同的重複回報是 Foliate 開書後套用樣式
  /// 重排、或圖片／字型載入後重新對齊錨點所派發的，不是使用者操作。只比 cfi
  /// 與 index、忽略 fraction——真機日誌實證重排時同一 cfi 的 fraction 會來回
  /// 微幅抖動。
  void onEpubLocated(EpubPositionInfo info) {
    _positionSaver?.onEpubLocated(info);
    final previous = _lastEpubInfo;
    if (previous != null &&
        _locatorPositionKey(previous.locatorJson) !=
            _locatorPositionKey(info.locatorJson)) {
      _stats?.recordActivity();
    }
    _lastEpubInfo = info;
  }

  /// PDF 的頁碼回報。開書後第一次回報是初始定位，第二次起才算閱讀活動。
  void onPdfPageChanged(PdfPageInfo info) {
    _positionSaver?.onPdfPageChanged(info);
    if (_hasPdfInfo) _stats?.recordActivity();
    _hasPdfInfo = true;
  }

  /// 回報一次閱讀活動（長按劃線、翻頁熱區等）。單純點擊叫出工具列不呼叫。
  void recordActivity() => _stats?.recordActivity();

  /// 回報朗讀（TTS）是否正在播放。統計對重複回報相同狀態是冪等的。
  void onTtsPlayingChanged(bool isPlaying) =>
      _stats?.onTtsPlayingChanged(isPlaying);

  /// App 進入背景（`AppLifecycleState.paused`，不含 `inactive`）：先通知統計，
  /// 再儲存閱讀位置。**不觸發 Checkpoint。**
  void onAppPaused(BookFormat format) {
    _stats?.onEnteredBackground();
    _positionSaver?.save(format);
  }

  /// App 回到前景。
  void onAppResumed() => _stats?.onReturnedToForeground();

  /// 離開閱讀畫面。順序固定：標記關閉 → 統計 flush → 取消 Timer → 儲存位置 →
  /// 觸發 Checkpoint。儲存位置排在觸發 Checkpoint 之前，讓剛寫入的最新位置有
  /// 較高機率被這次 Checkpoint 判定為待推送；但兩者皆不 await，並不保證
  /// SQLite 寫入已落地，沒趕上的會延到下一次 Checkpoint 才推送，不會遺失。
  /// 未登入或已有 Checkpoint 執行中時 `trigger()` 內部會直接放棄，不拋例外。
  void close(BookFormat format) {
    readerActivityTracker?.markReaderClosed();
    final stats = _stats;
    if (stats != null) unawaited(stats.flushAndClose());
    _checkpointTimer?.cancel();
    _positionSaver?.save(format);
    syncCheckpointTrigger?.trigger();
  }

  /// 有注入的 tracker 直接使用（呼叫端已處理）；否則有 repository 就以本書 id、
  /// 書名與 repository 的寫入方法、`onCleared` 建立；兩者皆無回傳 null。
  static ReadingStatsTracker? _statsTrackerFor(
    String bookId,
    String bookTitle,
    ReadingStatsRepository? repository,
  ) {
    if (repository == null) return null;
    return ReadingStatsTracker(
      bookId: bookId,
      bookTitle: bookTitle,
      onFlush: (date, id, title, seconds) => repository.addReadingSeconds(
        date: date,
        bookId: id,
        bookTitle: title,
        seconds: seconds,
      ),
      onCleared: repository.onCleared,
    );
  }

  /// 取 locatorJson 中代表「位置」的部分（cfi＋index），忽略會因重排而抖動的
  /// fraction。解析失敗時退回整段字串。
  static String _locatorPositionKey(String locatorJson) {
    try {
      final map = jsonDecode(locatorJson);
      if (map is Map) return '${map['cfi']}|${map['index']}';
    } catch (_) {}
    return locatorJson;
  }
}
```

- [ ] **Step 4：執行測試確認通過**

```bash
flutter test test/reader/reading_session_test.dart
flutter analyze lib/reader/reading_session.dart test/reader/reading_session_test.dart
```

預期：全數通過；analyze 無問題。

- [ ] **Step 5：提交 Task 1 成果**

```bash
git add lib/reader/reading_session.dart test/reader/reading_session_test.dart
git commit -m "feat(reader): 新增 ReadingSession，收攏閱讀會話生命週期協調（epic-54 Issue 8）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6：變異驗證（守衛真的守得住）**

暫時改壞 `reading_session.dart` 三處，各跑一次 `flutter test test/reader/reading_session_test.dart`，確認對應案例失敗；每次驗證完用 `git checkout -- lib/reader/reading_session.dart` 還原（Step 5 已提交，所以還原到的是完整實作；**不要用 `git stash`**，worktree 共用 stash）：

1. 把 `close` 內 `_positionSaver?.save(format);` 與 `syncCheckpointTrigger?.trigger();` 兩行對調 → 「離開的收尾順序」案例必須失敗。
2. 把 `_locatorPositionKey` 回傳改成整段 `locatorJson` → 「fraction 抖動不算活動」必須失敗。
3. 在 `onAppPaused` 內加一行 `syncCheckpointTrigger?.trigger();` → 「paused … 不觸發 Checkpoint」必須失敗。

全部驗證完後 `git status --short` 必須乾淨。

---

### Task 2：`ReaderScreen` 改用 session，刪除舊的零散邏輯

**Files：**
- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/test/screens/reader_screen_stats_activity_test.dart`

行號為 2026-10-02 `main`（含 Issue 7）的位置，動手前先重新 grep：

| 位置 | 內容 | 處置 |
|---|---|---|
| 約 378 | `reportTtsPlayingForTest` 呼叫 `state._forwardTtsPlaying` | 改呼叫 `state._session.onTtsPlayingChanged(isPlaying)` |
| 約 529 | `ReadingPositionSaver? _positionSaver;` | 刪除 |
| 約 561–564 | `_syncCheckpointTimer` 欄位與註解 | 刪除 |
| 約 586–588 | `_readingStatsTracker` 欄位與註解 | 刪除，改為 `late final ReadingSession _session;` |
| 約 607–608 | `markReaderOpened`、`_createReadingStatsTracker()` | 刪除，改為建立 session 並 `start()` |
| 約 614–620 | 建立 `_syncCheckpointTimer` | 刪除 |
| 約 628–633 | `_positionSaver = ReadingPositionSaver(...)` | 改為 `_session.onPrefsLoaded(initialProgress: loaded.readingPosition.progress);` |
| 約 735–772 | `dispose` 內 markReaderClosed／統計 flush／取消 Timer／儲存位置／觸發 Checkpoint | 合併為 dispose 開頭一次 `_session.close(...)` |
| 約 786–832 | `_createReadingStatsTracker`、`_locatorPositionKey`、`_recordReadingActivity`、`_forwardTtsPlaying` | 全部刪除 |
| 約 829–836 | `didChangeAppLifecycleState` | 改呼叫 `_session.onAppPaused`／`onAppResumed` |
| 約 2056、2156、3638、3664 | `_recordReadingActivity()` | 改為 `_session.recordActivity()` |
| 約 2805 | `_forwardTtsPlaying(...)` | 改為 `_session.onTtsPlayingChanged(...)` |
| 約 3490–3506 | `onLocatorChanged` 內 saver 轉發與活動判定 | 改為單一呼叫 `_session.onEpubLocated(info);`（`previousPosition` 區塊整段刪除；`setState(() => _epubPositionInfo = info)` 保留） |
| 約 3577–3582 | `onPageChanged` 內 saver 轉發與活動判定 | 改為單一呼叫 `_session.onPdfPageChanged(info);`（`setState(() => _pdfPageInfo = info)` 保留） |

**Interfaces：**
- Consumes：Task 1 的 `ReadingSession`。
- Produces：無。

- [ ] **Step 1：盤點既有 widget 測試（已盤點，執行前核對）**

審查前（2026-10-02）逐一比對與生命週期、活動判定有關的 widget 案例，結論：**只有 2 個純規則案例被 Task 1 單元測試完全取代，可刪；其餘全部是接線案例，保留。**

| 案例（檔案：行號為 2026-10-02 位置） | 性質 | 處置 | 取代者／保留理由 |
|---|---|---|---|
| `reader_screen_stats_activity_test.dart:61` 「同一位置的重複回報（重排、圖片或字型載入造成）不算閱讀活動」 | 純規則（cfi＋index 比較） | **刪除** | Task 1「同 cfi 與 index 的重複回報不算活動」 |
| `reader_screen_stats_activity_test.dart:74` 「同一 cfi 只有進度小數抖動（重排造成，真機實證）不算閱讀活動」 | 純規則 | **刪除** | Task 1「同 cfi 只有 fraction 抖動不算活動」 |
| 同檔 :50 「開書後第一次位置回報（初始定位）不算閱讀活動」 | 接線（畫面首次回報確實進到 session） | 保留 | — |
| 同檔 :87 「位置回報之間夾著同一位置的重複回報：位置真正改變的那一次仍算活動」 | 接線（正向：Foliate 回報→活動） | 保留 | 唯一證明 `onLocatorChanged` 轉發給 session 的正向案例 |
| 同檔 :200 「PDF：開書後第一次頁碼回報不算，之後的翻頁算閱讀活動」 | 接線（PDF 回呼） | 保留 | — |
| 同檔 :19、:40、:104、:120、:141、:160、:179、:220、:246、:272、:294 | 統計建立、熱區活動、清除統計、寫入失敗、注入優先順序 | 保留 | 其中 :120（以 bookId 當書名）與 :294（tracker 優先於 repository）是 session 建構的接線 |
| `reader_screen_stats_lifecycle_test.dart` 全部 5 個（paused／resumed／離開／TTS 背景／無統計參數） | 接線（真實 tracker 經畫面驅動） | 保留 | — |
| `reader_screen_test.dart:6469`「離開 ReaderScreen（書籍切換）觸發一次 checkpoint」、`:6520`「未提供 syncCheckpointTrigger 時，離開不拋例外」、`:6562`「閱讀中每 5 分鐘計時器觸發 checkpoint，離開畫面後計時器停止」 | 接線（畫面建立 session、dispose 呼叫 close） | 保留 | — |
| `reader_screen_test.dart:11197`「readerActivityTracker 提供時，開啟/離開閱讀畫面會呼叫 markReaderOpened/markReaderClosed」 | 接線 | 保留 | — |
| `app_lifecycle_sync_test.dart` 全部 | App 層級 Checkpoint（不經 ReaderScreen） | 保留 | — |
| Issue 7 新增的 `paused` 與 Foliate 位置儲存接線案例、`reader_screen_test.dart` 內位置儲存案例 | 接線 | 保留 | — |

刪除前先確認 Task 1 對應的兩個單元案例存在且通過，並已完成 Task 1 Step 6 的變異驗證（證明單元測試真的守得住）。

- [ ] **Step 2：改 `ReaderScreen`**

1. **import**：新增 `import '../reader/reading_session.dart';`（依該檔既有 import 風格）。
2. **欄位**：刪除 `_positionSaver`、`_syncCheckpointTimer`、`_readingStatsTracker` 三個欄位與其文件註解，在原 `_readingStatsTracker` 位置新增：

```dart
  /// 本次開書的閱讀會話（epic-54 Issue 8）：閱讀統計、閱讀活動判定、Checkpoint
  /// Timer、前後景與離開時的收尾，以及閱讀位置儲存都在其中；本 State 只負責
  /// 轉送視圖事件。
  late final ReadingSession _session;
```

3. **`initState`**：刪除 `markReaderOpened()`、`_createReadingStatsTracker()` 與整段 `_syncCheckpointTimer` 建立，改為（放在原 `markReaderOpened` 的位置）：

```dart
    _session = ReadingSession(
      bookId: widget.bookId,
      prefsManager: widget.prefsManager,
      hasJumpTarget: widget.initialJumpTarget != null,
      bookTitle: widget.bookTitle,
      statsTracker: widget.readingStatsTracker,
      statsRepository: widget.readingStatsRepository,
      syncCheckpointTrigger: widget.syncCheckpointTrigger,
      readerActivityTracker: widget.readerActivityTracker,
    )..start();
```

   偏好載入的 `setState` 內，把建立 `ReadingPositionSaver` 的整段換成：

```dart
        _session.onPrefsLoaded(initialProgress: loaded.readingPosition.progress);
```

4. **`dispose`**：把原本分散的五個動作（`markReaderClosed`；統計 flush 與其註解；`_syncCheckpointTimer?.cancel()`；`_positionSaver?.save(...)` 與其註解；`syncCheckpointTrigger?.trigger()` 與其長註解）全部刪除，在 `dispose` 開頭（`_openBookFlow` 之前）加入：

```dart
    // 離開閱讀畫面：標記關閉、結算統計、取消 Checkpoint Timer、儲存位置、觸發
    // 一次 Checkpoint（順序與理由見 ReadingSession.close）。放在最前面，
    // 讓 _activeFilePath 在 _openBookFlow 被 dispose 之前取值。
    _session.close(detectBookFormat(_activeFilePath));
```

   其餘畫面自己的收尾（`_openBookFlow`、搜尋高亮 timer、睡眠定時器、`removeObserver`、音量鍵 channel、PDF 搜尋 notifier、TTS 與 audio focus、螢幕方向、全螢幕）一個字都不動。

5. **`didChangeAppLifecycleState`**：`paused` 分支改為 `_session.onAppPaused(detectBookFormat(_activeFilePath));`（取代 `_readingStatsTracker?.onEnteredBackground()` 與 `_positionSaver?.save(...)` 兩行）；`resumed` 分支第一行改為 `_session.onAppResumed();`，其後的全螢幕重套用與 TTS 高亮不動。
6. **刪除** `_createReadingStatsTracker`、`_locatorPositionKey`、`_recordReadingActivity`、`_forwardTtsPlaying` 四個方法與其文件註解。
7. **呼叫點**：`_recordReadingActivity()` 四處改為 `_session.recordActivity()`；`_forwardTtsPlaying(...)` 一處改為 `_session.onTtsPlayingChanged(...)`；`reportTtsPlayingForTest` 內改為 `state._session.onTtsPlayingChanged(isPlaying)`。
8. **`onLocatorChanged`**：把 `_positionSaver?.onEpubLocated(info);`、`final previousPosition = _epubPositionInfo;` 與整個 `if (previousPosition != null) {...}` 區塊，換成：

```dart
            // 位置儲存與閱讀活動判定都由閱讀會話處理（見 ReadingSession）。
            _session.onEpubLocated(info);
```

   `setState(() => _epubPositionInfo = info);` 與其後的 TTS 手動導覽處理原樣保留。
9. **`onPageChanged`**（PDF）：把 `_positionSaver?.onPdfPageChanged(info);` 與 `if (_pdfPageInfo != null) {...}` 換成 `_session.onPdfPageChanged(info);`，`setState(() => _pdfPageInfo = info);` 保留。
10. **清理自己造成的殘留**：跑 `flutter analyze`，只移除「因本次改動變成未使用」的 import（預期可能有 `dart:convert`、`ReadingStatsTracker`、`ReadingPositionSaver`，以 analyze 為準）；附近提到舊欄位名（例如「`_positionSaver`」「`_readingStatsTracker`」「`_syncCheckpointTimer`」）的註解改為提到 `ReadingSession`，不改其他文字。

- [ ] **Step 3：刪除 Step 1 判定可刪的 2 個 widget 案例**

只刪 `reader_screen_stats_activity_test.dart` 的「同一位置的重複回報…」與「同一 cfi 只有進度小數抖動…」兩個 `testWidgets`；刪除後確認檔案內不再有因此變成未使用的 import 或 helper（有才移除）。

- [ ] **Step 4：執行異動觸及的測試**

```bash
flutter test test/reader/reading_session_test.dart test/reader/reading_position_saver_test.dart test/screens/reader_screen_test.dart test/screens/reader_screen_stats_lifecycle_test.dart test/screens/reader_screen_stats_activity_test.dart test/screens/reader_screen_stats_test.dart test/app_lifecycle_sync_test.dart
flutter analyze
```

預期：全數通過（`reader_screen_stats_activity_test.dart` 少 2 個案例，其餘與 Task 0 基準一致，另加上 `reading_session_test.dart` 的新案例）；analyze "No issues found!"。

- [ ] **Step 5：行為不變的手動核對**

- `rg "_readingStatsTracker|_createReadingStatsTracker|_syncCheckpointTimer|_positionSaver|_locatorPositionKey|_recordReadingActivity|_forwardTtsPlaying" lib test` 不應再有任何命中（含註解）。
- `git diff` 中確認 `dispose` 裡畫面自己的收尾（`_openBookFlow`…螢幕方向、全螢幕）內容與相對順序與修改前完全相同，只有 session 相關五步被合併到開頭。
- 逐一確認這些畫面自己的收尾都不讀取 session 管理的狀態（`_openBookFlow.dispose`、搜尋高亮 timer、睡眠定時器、`removeObserver`、音量鍵 channel、`_pdfSearchStateNotifier`、`_ttsAudioFocusCoordinator`、`ttsAudioHandler.detachController`、`_ttsController.removeListener`／`dispose`）；`_ttsController.dispose()` 之前已先 `removeListener(_onTtsStatusChanged)`，所以不會在 session 關閉後又回報 TTS 狀態。若發現任何相依，停下來回報。

- [ ] **Step 6：提交**

```bash
git add lib/screens/reader_screen.dart test/screens/reader_screen_stats_activity_test.dart
git commit -m "refactor(reader): ReaderScreen 改用 ReadingSession（epic-54 Issue 8）

刪除的 widget 案例與取代它們的單元測試：
- 同一位置的重複回報不算閱讀活動 → 同 cfi 與 index 的重複回報不算活動
- 同一 cfi 只有進度小數抖動不算閱讀活動 → 同 cfi 只有 fraction 抖動不算活動

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：文件、全套驗證、發 PR 前確認

**Files：**
- Modify：`docs/epics/epic-54-architecture-optimization/epic.md`（開發記錄）、`issues.md`（第 8 列狀態）、`docs/epics.md`（第 55 列備註）

- [ ] **Step 1：全套測試（最後一次，背景執行，必須在 `app/` 目錄）**

```bash
cd <worktree>/app && flutter test
```

用 `run_in_background`，約 6 分鐘。預期 0 失敗；確認輸出最後是 `All tests passed!`（不是 `Test directory "test" not found.`），記下通過數與 1 略過。通過數預期 = Issue 7 合併基準 3369 + `reading_session_test.dart` 新案例數 − 2。

- [ ] **Step 2：靜態檢查**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

預期："No issues found!" 與兩行 PASS。

- [ ] **Step 3：更新文件**

`epic.md` 開發記錄新增「Issue 8 實作完成」：新增檔案、被刪除的 2 個 widget 案例與取代它們的單元測試、驗證數字、與計畫的差異（若有）、行為變動「無」、待真機確認「無」。**同時記錄一項需要使用者知道的事**：`dispose` 內畫面自己的收尾與 session 收尾的相對順序改變（見 Global Constraints），以及 Step 5 核對的結論。`issues.md` 第 8 列改為「🟡 待程式審查」。`docs/epics.md` 第 55 列備註只更新最後處理的 Issue 編號，保持一句話。

- [ ] **Step 4：提交並停下**

```bash
cd .. && git add docs/epics/epic-54-architecture-optimization docs/epics.md
git commit -m "docs(epic-54): Issue 8 實作完成記錄

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

（上面的 `cd ..` 回到 worktree 根目錄，路徑即為儲存庫相對路徑。）此時**停止**，等人類決定是否進行程式審查與發 PR（審查先出報告、不直接改程式）。

---

## Self-Review

- **Spec 涵蓋**：epic.md 決策 2（Timer 歸 session、trigger 注入）→ Task 1 規則 1／9；決策 3（一個 State 一個會話）→ `late final _session`；決策 4（搬走／留下清單）→ Task 2 行號表與 Global Constraints 範圍外；決策 5（活動判定歸 session）→ 規則 3／4；決策 6（純重構）→ Global Constraints；決策 7（不新增建構參數）→ session 用既有 widget 參數組裝；決策 8（replace don't layer）→ Task 2 Step 1 逐案例盤點；決策 9（寫 plan）→ 本檔。
- **型別一致**：`ReadingSession` 的建構參數與九個方法在 Task 1 Interfaces、Step 3 實作、Task 2 Step 2 呼叫點完全一致（`start`／`onPrefsLoaded({required double initialProgress})`／`onEpubLocated`／`onPdfPageChanged`／`recordActivity`／`onTtsPlayingChanged`／`onAppPaused(BookFormat)`／`onAppResumed`／`close(BookFormat)`）。
- **行為等價核對**：
  - 現有活動判定用畫面的 `_epubPositionInfo`／`_pdfPageInfo` 當「上一次」，session 改用自己的 `_lastEpubInfo`／`_hasPdfInfo`；兩者都在每次回報時同步更新，且畫面的兩個欄位全檔只有 `onLocatorChanged`／`onPageChanged` 兩處賦值（Issue 7 審查已確認），故等價。
  - `markReaderOpened` 與統計 tracker 建立的先後對調（session 建構子先建 tracker、`start()` 才 `markReaderOpened`）；兩者互不相依，無可觀察差異。Timer 也比原本略早建立（原本在 `_loadLayoutPresets()` 之後），5 分鐘週期，無可觀察差異。
  - 離開順序見 Global Constraints「已接受的順序差異」與 Task 2 Step 5 的逐項核對。
- **風險**：(1) 刪 widget 案例是這份計畫唯一會減少既有覆蓋的動作，已限定 2 個並以 Task 1 Step 6 的變異驗證先證明單元測試守得住；(2) `dispose` 提前執行 session 收尾，依賴「畫面自己的收尾不讀 session 狀態」這個事實，Step 5 要求逐項核對而不是只靠測試；(3) Issue 9（缺陷）刻意不在本 Issue 處理，但 session 現在同時持有位置儲存器與 `_locatorPositionKey`，之後修 Issue 9 的改動點會集中在 `reading_session.dart` 與 `reading_position_saver.dart`。
