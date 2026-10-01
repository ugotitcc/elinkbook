# Issue 5：開書流程（OpenBookFlow）實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 把 `ReaderScreen` 裡散落的「開書失敗、存取探測、逾時、重新連結、重新開書」規則收攏成一個可獨立測試的控制器 `OpenBookFlow`，讓狀態轉移與競態 guard 有純測試，不再只靠 287 個 widget 測試間接驗證。

**Architecture：** 新增 `app/lib/reader/open_book_flow.dart`：`ChangeNotifier` 子類，持有密封類別狀態（`Loading`／`Probing`／`Rendered`／`Failed`／`Relinking`）、30 秒逾時計時器與目前檔案路徑；探測、relink、計時器以建構參數注入。`ReaderScreen` 刪除 6 個狀態欄位與 `_RenderState` 列舉，改持有一個 `OpenBookFlow` 並以 listener 呼叫 `setState`；`l10n` 文字、SnackBar、選檔器與 EPUB 引擎分派重跑仍留在 `ReaderScreen`。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立的 `spec.md`，設計依據是 2026-10-01 `/grill-with-docs` 的決策，記錄於 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 5 設計決策」與 `CONTEXT.md`「開書流程（Open Book Flow）」詞條。

## 與設計決策的兩處細部差異（寫計畫時讀程式發現，執行者照本計畫做）

1. **`Failed` 不存 `message` 字串，改存失敗來源**：設計表寫 `Failed(message, probeResult)`，但逾時訊息是 `l10n` 字串，module 不能持有。改為 `Failed(source, viewMessage, probeResult)`，`source` 為 `OpenBookFailureSource.viewError | timeout`；`ReaderScreen` 依 `probeResult`、`source` 決定顯示哪段文字。
2. **`relink()` 接收「選檔 callback」而非已選好的檔案**：設計 Q9 決定選檔器留在 Widget，這點不變（選檔函式仍由 `ReaderScreen` 提供）。但現有行為是「從按下按鈕、開選檔器、到 relinkBook 回傳為止」按鈕都停用（既有測試「快速連點兩次只開一次選擇器」）。若 module 只收選好的檔案，選檔期間就沒有狀態可讓按鈕停用。所以 `relink(pick)` 由 module 先進入 `Relinking` 狀態再呼叫 `pick()`，選檔器本身仍是 Widget 提供的函式。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **不動的東西**：`ReaderScreen` 對外公開建構參數（ADR 0007；`bookImportService`／`pickSingleBookFile` 維持原樣）、`probeStorageAccess` 頂層可覆寫變數與 `probeStorageAccessViaChannel`（Issue 4 才會搬動）、`BookImportService.relinkBook`、`BookRelinkResult` 家族、`FontManagementScreen`（屬 Issue 3）、固定的 `Key('reader_loading_indicator')`／`Key('reader_error_text')`／`Key('reader_storage_relink_button')`／`Key('reader_storage_relink_progress')`。
- **唯一的行為調整**：`content://` 書籍開書逾時也做存取探測（探測結果為權限失效／找不到檔案時，顯示對應說明並提供「重新選取檔案」；探測結果為 `readable`／`unknownError` 時仍顯示原本的逾時訊息）。其餘行為（錯誤訊息文字、按鈕顯示條件、SnackBar 文字、重新開書復位、30 秒逾時值）一律不變。
- **既有測試已涵蓋、不必新增 widget 測試**：「relink 成功後重新開書再失敗，會重新探測並再顯示按鈕」已有 `reader_screen_test.dart` 的「重新開書後再次失敗：重新探測一次並再次顯示按鈕（Review Focus 2）」，Task 2 之後仍須維持綠燈；Task 1 另加純測試。
- **Windows 環境**：`python` 在此環境不會實際執行（無輸出、檔案不變），不可用來編輯檔案；用 Edit 工具或 Node 腳本。多數原始檔是 CRLF 換行，Node 腳本要保留。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動實際觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：直接 TDD，不另寫其他 plan；程式審查先出報告（存於 `reviews/`，該目錄不進版控），審查者不直接改程式。

## Review Focus

以下是設計隱含、既有測試未涵蓋或僅間接涵蓋、最可能咬到使用者的情況（依可能性排序），每一條都有對應測試：

1. **`content://` 書籍逾時且權限已撤銷**：使用者以前看到「開書逾時」且無路可走，現在應看到權限失效說明與重新選取按鈕；探測結果是 `readable`／`unknownError` 時則維持逾時訊息。→ Task 1 純測試 ＋ Task 3 widget 測試。
2. **探測進行中 `onRendered` 先到**（不論探測由視圖錯誤或逾時觸發）：畫面必須維持已渲染，探測結果回來不得蓋成錯誤畫面。→ Task 1 純測試。
3. **離開閱讀器後非同步結果才回來**（探測、選檔、relinkBook 三處）：不得拋例外、不得通知 listener（`notifyListeners` 在 `dispose` 後會拋錯）；選檔期間離開時不得呼叫 relinkBook。→ Task 1 純測試。
4. **重新連結處理中的重複觸發與雜訊事件**：處理中再次呼叫 `relink()` 必須被擋下（只開一次選擇器）；`Relinking` 期間收到的視圖錯誤一律忽略。→ Task 1 純測試。
5. **重新開書後的二次失敗與二次逾時**：relink 成功回到 `Loading` 後，視圖再回報錯誤要以新路徑重新探測；30 秒逾時要重新計時。→ Task 1 純測試；既有 widget 測試（`reader_screen_test.dart`「重新開書後再次卡住時…」「重新開書後再次失敗…」）須維持綠燈。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/open_book_flow.dart` | 新增 | `OpenBookFlow`（ChangeNotifier）、`OpenBookState` 密封家族、`OpenBookFailureSource`、`OpenBookRelinkOutcome` 密封家族、注入用 typedef |
| `app/test/reader/open_book_flow_test.dart` | 新增 | 狀態轉移與競態 guard 純測試（計時器以假 Timer 注入） |
| `app/lib/screens/reader_screen.dart` | 修改 | 刪 `_RenderState` 與 6 個欄位；`_activeFilePath` 改為 getter；建構／dispose／`_handleError`／`_handlePageRendered`／relink 流程／錯誤視圖／7 處 `_state` 判斷改接 `OpenBookFlow` |
| `app/test/screens/reader_screen_test.dart` | 修改 | 7 個與規則重疊的 widget 測試遷到純測試後刪除；1 個翻轉；新增 2 個接線測試 |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 開發記錄、狀態 |

---

### Task 0：建立分支並提交設計文件

**Files：**
- Commit（已存在的未提交異動）：`CONTEXT.md`（「開書流程」詞條）、`docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md`、本計畫檔

**Interfaces：**
- Consumes：無。
- Produces：後續 Task 都在分支 `epic-54/issue-5-open-book-flow` 上提交。

- [x] **Step 1：建立分支**（worktree 方式完成，見 ledger Ruling）

```bash
cd /c/Users/fycdc/AI/elinkBook
# 設計文件與計畫此時仍是 main 上的未提交異動，直接從目前位置建立分支
# （不要先 pull：dirty working tree 遇到遠端同檔異動會被 git 拒絕）。
git branch --show-current   # 應為 main
git checkout -b epic-54/issue-5-open-book-flow
git status --short
```

Expected：`Switched to a new branch 'epic-54/issue-5-open-book-flow'`；`git status` 顯示上列 5 個檔案為未提交（屬預期）。

- [x] **Step 2：提交設計文件與計畫**

```bash
git add CONTEXT.md docs/epics.md docs/epics/epic-54-architecture-optimization/epic.md docs/epics/epic-54-architecture-optimization/issues.md docs/epics/epic-54-architecture-optimization/plans/plan-issue-5.md
git commit -m "docs(epic-54): Issue 5 開書流程（OpenBookFlow）設計與實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 1：`OpenBookFlow` 模組與純測試

**Files：**
- Create: `app/lib/reader/open_book_flow.dart`
- Test: `app/test/reader/open_book_flow_test.dart`

**Interfaces：**
- Consumes：`StorageAccessProbeResult`（`app/lib/reader/foliate_native_bridge.dart:93`，只用型別；Issue 4 搬動後改一行 import）、`BookRelinkResult`／`BookRelinkSuccess`／`BookRelinkFailure`／`BookRelinkFailureReason`（`app/lib/library/book_import_service.dart:24-53`）。
- Produces（Task 2 依賴，名稱與型別必須一字不差）：

```dart
enum OpenBookFailureSource { viewError, timeout }

sealed class OpenBookState
final class OpenBookLoading extends OpenBookState        // const OpenBookLoading()
final class OpenBookProbing extends OpenBookState        // const OpenBookProbing()
final class OpenBookRendered extends OpenBookState       // const OpenBookRendered()
final class OpenBookFailed extends OpenBookState {       // 欄位：source, viewMessage?, probeResult?
  const OpenBookFailed({required this.source, this.viewMessage, this.probeResult});
}
final class OpenBookRelinking extends OpenBookState {    // 欄位：failed（進入前的 Failed）
  const OpenBookRelinking(this.failed);
}

sealed class OpenBookRelinkOutcome
final class OpenBookRelinkReopened extends OpenBookRelinkOutcome   // 欄位：newPath
final class OpenBookRelinkFailed extends OpenBookRelinkOutcome     // 欄位：reason（BookRelinkFailureReason）
final class OpenBookRelinkCancelled extends OpenBookRelinkOutcome

typedef OpenBookProbe = Future<StorageAccessProbeResult> Function(String uri);
typedef OpenBookRelink = Future<BookRelinkResult> Function(String uri, String? displayName);
typedef OpenBookPickedFile = ({String uri, String? displayName});
typedef OpenBookTimerFactory = Timer Function(Duration duration, void Function() callback);

class OpenBookFlow extends ChangeNotifier {
  OpenBookFlow({required String filePath, required OpenBookProbe probe,
      OpenBookRelink? relinkBook, Duration timeout = const Duration(seconds: 30),
      OpenBookTimerFactory timerFactory = Timer.new});
  String get filePath;
  OpenBookState get state;
  bool get isLoading;      // Loading 或 Probing（畫面仍顯示載入指示器）
  bool get isRendered;
  bool get isFailed;       // Failed 或 Relinking（畫面顯示錯誤視圖）
  OpenBookFailed? get failure;   // Failed 本身，或 Relinking 內的 failed；其餘 null
  void start();            // 啟動 30 秒逾時計時器（initState 呼叫一次）
  void onViewError(String message);
  void onRendered();
  Future<OpenBookRelinkOutcome> relink(Future<OpenBookPickedFile?> Function() pick);
  void dispose();
}
```

- [ ] **Step 1：寫失敗的純測試**

建立 `app/test/reader/open_book_flow_test.dart`：

```dart
import 'dart:async';

import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart'
    show StorageAccessProbeResult;
import 'package:elinkbook/reader/open_book_flow.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假計時器：由測試手動觸發，不依賴真實時間。
class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool cancelled = false;
  bool fired = false;

  /// 模擬時間到。已取消的計時器不會觸發（與真實 Timer 一致）。
  void fire() {
    if (cancelled) return;
    fired = true;
    _callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => fired ? 1 : 0;
}

const _contentUri = 'content://com.example.provider/book.epub';
const _newUri = 'content://com.example.provider/moved/book.epub';
const _picked = (uri: _newUri, displayName: 'book.epub');

Book _book(String filePath) => Book(
      id: 'b1',
      title: '測試書',
      format: BookFileFormat.epub,
      filePath: filePath,
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(0),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );

void main() {
  late List<_FakeTimer> timers;
  late List<String> probeCalls;

  setUp(() {
    timers = [];
    probeCalls = [];
  });

  /// 建立一個以假計時器與假探測組成的 [OpenBookFlow]。
  OpenBookFlow buildFlow({
    String filePath = _contentUri,
    OpenBookProbe? probe,
    OpenBookRelink? relinkBook,
  }) {
    final flow = OpenBookFlow(
      filePath: filePath,
      probe: (uri) {
        probeCalls.add(uri);
        return (probe ?? (_) async => StorageAccessProbeResult.unknownError)(uri);
      },
      relinkBook: relinkBook,
      timerFactory: (duration, callback) {
        final timer = _FakeTimer(duration, callback);
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(flow.dispose);
    return flow;
  }

  /// 讓微任務佇列跑完（探測／relink 的 await 結果回來）。
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('初始與成功', () {
    test('start 後為 Loading 並啟動 30 秒計時器', () {
      final flow = buildFlow()..start();

      expect(flow.state, isA<OpenBookLoading>());
      expect(flow.isLoading, isTrue);
      expect(flow.isRendered, isFalse);
      expect(flow.isFailed, isFalse);
      expect(flow.failure, isNull);
      expect(timers.single.duration, const Duration(seconds: 30));
    });

    test('onRendered：切到 Rendered 並取消計時器', () {
      final flow = buildFlow()..start();

      flow.onRendered();

      expect(flow.state, isA<OpenBookRendered>());
      expect(flow.isRendered, isTrue);
      expect(timers.single.cancelled, isTrue);
    });

    test('onRendered 重複呼叫只通知一次', () {
      final flow = buildFlow()..start();
      var notifications = 0;
      flow.addListener(() => notifications++);

      flow.onRendered();
      flow.onRendered();

      expect(notifications, 1);
    });

    test('已 dispose 或已 Rendered 後呼叫 start：不建立新計時器', () {
      final disposed = buildFlow()..start();
      disposed.dispose();
      disposed.start();
      expect(timers, hasLength(1));

      final rendered = buildFlow()..start();
      rendered.onRendered();
      rendered.start();
      expect(timers, hasLength(2));
    });

    test('Rendered 之後的視圖錯誤與逾時一律忽略', () async {
      final flow = buildFlow()..start();
      flow.onRendered();

      flow.onViewError('晚到的良性警告');
      timers.single.fire();
      await settle();

      expect(flow.state, isA<OpenBookRendered>());
      expect(probeCalls, isEmpty);
    });
  });

  group('視圖回報錯誤', () {
    test('content://：先進入 Probing（仍算載入中），探測完成後 Failed', () async {
      final pending = Completer<StorageAccessProbeResult>();
      final flow = buildFlow(probe: (_) => pending.future)..start();

      flow.onViewError('boom');

      expect(flow.state, isA<OpenBookProbing>());
      expect(flow.isLoading, isTrue);
      expect(flow.isFailed, isFalse);
      expect(timers.single.cancelled, isTrue);
      expect(probeCalls, [_contentUri]);

      pending.complete(StorageAccessProbeResult.permissionRevoked);
      await settle();

      final failed = flow.state as OpenBookFailed;
      expect(failed.source, OpenBookFailureSource.viewError);
      expect(failed.viewMessage, 'boom');
      expect(failed.probeResult, StorageAccessProbeResult.permissionRevoked);
      expect(flow.isFailed, isTrue);
      expect(flow.failure, same(failed));
    });

    test('非 content://：不探測，直接 Failed 且 probeResult 為 null', () {
      final flow = buildFlow(filePath: '/data/books/a.epub')..start();

      flow.onViewError('boom');

      final failed = flow.state as OpenBookFailed;
      expect(failed.viewMessage, 'boom');
      expect(failed.probeResult, isNull);
      expect(probeCalls, isEmpty);
    });

    test('Probing 期間再收到視圖錯誤：只探測一次', () async {
      final pending = Completer<StorageAccessProbeResult>();
      final flow = buildFlow(probe: (_) => pending.future)..start();

      flow.onViewError('第一次');
      flow.onViewError('第二次');

      expect(probeCalls, hasLength(1));
      pending.complete(StorageAccessProbeResult.fileNotFound);
      await settle();
      expect((flow.state as OpenBookFailed).viewMessage, '第一次');
    });

    test('探測函式拋出例外：視為 unknownError，不停在 Probing', () async {
      final flow = buildFlow(probe: (_) async => throw StateError('probe 爆掉'))
        ..start();

      flow.onViewError('boom');
      await settle();

      expect((flow.state as OpenBookFailed).probeResult,
          StorageAccessProbeResult.unknownError);
    });

    test('Probing 期間 onRendered 先到：維持 Rendered，探測結果不覆蓋（Review Focus 2）',
        () async {
      final pending = Completer<StorageAccessProbeResult>();
      final flow = buildFlow(probe: (_) => pending.future)..start();
      flow.onViewError('boom');

      flow.onRendered();
      pending.complete(StorageAccessProbeResult.permissionRevoked);
      await settle();

      expect(flow.state, isA<OpenBookRendered>());
    });
  });

  group('開書逾時', () {
    test('content:// 逾時且權限已撤銷：Failed(timeout) 帶探測結果（Review Focus 1）', () async {
      final flow = buildFlow(
          probe: (_) async => StorageAccessProbeResult.permissionRevoked)
        ..start();

      timers.single.fire();
      expect(flow.state, isA<OpenBookProbing>());
      await settle();

      final failed = flow.state as OpenBookFailed;
      expect(failed.source, OpenBookFailureSource.timeout);
      expect(failed.viewMessage, isNull);
      expect(failed.probeResult, StorageAccessProbeResult.permissionRevoked);
      expect(probeCalls, [_contentUri]);
    });

    test('content:// 逾時但探測為 readable：仍是 Failed(timeout)，由畫面顯示逾時訊息',
        () async {
      final flow = buildFlow(probe: (_) async => StorageAccessProbeResult.readable)
        ..start();

      timers.single.fire();
      await settle();

      final failed = flow.state as OpenBookFailed;
      expect(failed.source, OpenBookFailureSource.timeout);
      expect(failed.probeResult, StorageAccessProbeResult.readable);
    });

    test('非 content:// 逾時：不探測，直接 Failed(timeout)', () {
      final flow = buildFlow(filePath: '/data/books/a.epub')..start();

      timers.single.fire();

      final failed = flow.state as OpenBookFailed;
      expect(failed.source, OpenBookFailureSource.timeout);
      expect(failed.probeResult, isNull);
      expect(probeCalls, isEmpty);
    });

    test('逾時後探測未完成時 onRendered 先到：維持 Rendered（Review Focus 2）', () async {
      final pending = Completer<StorageAccessProbeResult>();
      final flow = buildFlow(probe: (_) => pending.future)..start();
      timers.single.fire();

      flow.onRendered();
      pending.complete(StorageAccessProbeResult.fileNotFound);
      await settle();

      expect(flow.state, isA<OpenBookRendered>());
    });

    test('逾時探測期間再收到視圖錯誤：忽略，只探測一次', () async {
      final pending = Completer<StorageAccessProbeResult>();
      final flow = buildFlow(probe: (_) => pending.future)..start();
      timers.single.fire();

      flow.onViewError('晚到的錯誤');
      pending.complete(StorageAccessProbeResult.fileNotFound);
      await settle();

      expect(probeCalls, hasLength(1));
      expect((flow.state as OpenBookFailed).source,
          OpenBookFailureSource.timeout);
    });
  });

  group('dispose 之後', () {
    test('探測結果回來：不拋例外、不通知（Review Focus 3）', () async {
      final pending = Completer<StorageAccessProbeResult>();
      final flow = buildFlow(probe: (_) => pending.future)..start();
      flow.onViewError('boom');
      var notifications = 0;
      flow.addListener(() => notifications++);

      flow.dispose();
      pending.complete(StorageAccessProbeResult.permissionRevoked);
      await settle();

      expect(notifications, 0);
    });

    test('dispose 取消計時器；之後的事件與重複 dispose 都不拋例外', () {
      final flow = buildFlow()..start();

      flow.dispose();

      expect(timers.single.cancelled, isTrue);
      flow.onViewError('晚到');
      flow.onRendered();
      flow.dispose();
    });
  });

  group('重新連結', () {
    /// 讓 flow 進入 Failed（權限已撤銷）。
    Future<OpenBookFlow> failedFlow({OpenBookRelink? relinkBook}) async {
      final flow = buildFlow(
        probe: (_) async => StorageAccessProbeResult.permissionRevoked,
        relinkBook: relinkBook,
      )..start();
      flow.onViewError('boom');
      await settle();
      expect(flow.state, isA<OpenBookFailed>());
      return flow;
    }

    test('不在 Failed 狀態：回傳 cancelled，且不呼叫選檔', () async {
      final flow = buildFlow(
          relinkBook: (_, __) async => BookRelinkSuccess(_book(_newUri)))
        ..start();
      var pickCalls = 0;

      final outcome = await flow.relink(() async {
        pickCalls++;
        return _picked;
      });

      expect(outcome, isA<OpenBookRelinkCancelled>());
      expect(pickCalls, 0);
    });

    test('沒有注入 relinkBook：回傳 cancelled', () async {
      final flow = await failedFlow();
      var pickCalls = 0;

      final outcome = await flow.relink(() async {
        pickCalls++;
        return _picked;
      });

      expect(outcome, isA<OpenBookRelinkCancelled>());
      expect(pickCalls, 0);
      expect(flow.state, isA<OpenBookFailed>());
    });

    test('成功：Relinking → Loading，路徑更新並重新啟動 30 秒計時器', () async {
      final calls = <(String, String?)>[];
      final flow = await failedFlow(relinkBook: (uri, displayName) async {
        calls.add((uri, displayName));
        return BookRelinkSuccess(_book('/data/imported/b1.epub'));
      });
      final states = <OpenBookState>[];
      flow.addListener(() => states.add(flow.state));

      final outcome = await flow.relink(() async => _picked);

      expect(calls, [(_newUri, 'book.epub')]);
      expect((outcome as OpenBookRelinkReopened).newPath,
          '/data/imported/b1.epub');
      expect(states.first, isA<OpenBookRelinking>());
      expect(flow.state, isA<OpenBookLoading>());
      expect(flow.filePath, '/data/imported/b1.epub');
      // 第 1 個是 start() 的計時器（已被視圖錯誤取消），第 2 個是重開後新建的。
      expect(timers, hasLength(2));
      expect(timers.last.cancelled, isFalse);
    });

    test('Relinking 期間 failure 仍指向進入前的 Failed', () async {
      final pending = Completer<BookRelinkResult>();
      final flow = await failedFlow(relinkBook: (_, __) => pending.future);
      final before = flow.failure;

      final future = flow.relink(() async => _picked);
      await settle();

      expect(flow.state, isA<OpenBookRelinking>());
      expect(flow.isFailed, isTrue);
      expect(flow.failure, same(before));

      pending.complete(const BookRelinkFailure(BookRelinkFailureReason.failed));
      await future;
    });

    test('選檔取消：回傳 cancelled、不呼叫 relinkBook、回到原 Failed', () async {
      var relinkCalls = 0;
      final flow = await failedFlow(relinkBook: (_, __) async {
        relinkCalls++;
        return BookRelinkSuccess(_book(_newUri));
      });
      final before = flow.state;

      final outcome = await flow.relink(() async => null);

      expect(outcome, isA<OpenBookRelinkCancelled>());
      expect(relinkCalls, 0);
      expect(flow.state, same(before));
    });

    for (final reason in BookRelinkFailureReason.values) {
      test('$reason：回傳 failed 並回到原 Failed，不重新開書', () async {
        final flow = await failedFlow(
            relinkBook: (_, __) async => BookRelinkFailure(reason));
        final before = flow.state;
        final timersBefore = timers.length;

        final outcome = await flow.relink(() async => _picked);

        expect((outcome as OpenBookRelinkFailed).reason, reason);
        expect(flow.state, same(before));
        expect(flow.filePath, _contentUri);
        expect(timers, hasLength(timersBefore));
      });
    }

    test('relinkBook 拋出例外：視為 failed', () async {
      final flow = await failedFlow(
          relinkBook: (_, __) async => throw StateError('爆掉'));

      final outcome = await flow.relink(() async => _picked);

      expect((outcome as OpenBookRelinkFailed).reason,
          BookRelinkFailureReason.failed);
      expect(flow.state, isA<OpenBookFailed>());
    });

    test('選檔函式拋出例外：視為 failed', () async {
      final flow = await failedFlow(
          relinkBook: (_, __) async => BookRelinkSuccess(_book(_newUri)));

      final outcome = await flow.relink(() async => throw StateError('爆掉'));

      expect((outcome as OpenBookRelinkFailed).reason,
          BookRelinkFailureReason.failed);
    });

    test('處理中再次呼叫 relink：回傳 cancelled，選檔只開一次（Review Focus 4）', () async {
      final pendingPick = Completer<OpenBookPickedFile?>();
      final flow = await failedFlow(
          relinkBook: (_, __) async => BookRelinkSuccess(_book(_newUri)));
      var pickCalls = 0;

      final first = flow.relink(() {
        pickCalls++;
        return pendingPick.future;
      });
      final second = flow.relink(() async {
        pickCalls++;
        return _picked;
      });

      expect(await second, isA<OpenBookRelinkCancelled>());
      expect(pickCalls, 1);
      pendingPick.complete(null);
      await first;
    });

    test('Relinking 期間的視圖錯誤與 onRendered 一律忽略（Review Focus 4）', () async {
      final pending = Completer<BookRelinkResult>();
      final flow = await failedFlow(relinkBook: (_, __) => pending.future);
      final future = flow.relink(() async => _picked);
      await settle();

      flow.onViewError('雜訊');
      flow.onRendered();

      expect(flow.state, isA<OpenBookRelinking>());
      expect(probeCalls, hasLength(1));
      pending.complete(const BookRelinkFailure(BookRelinkFailureReason.failed));
      await future;
    });

    test('選檔期間 dispose：不呼叫 relinkBook、不拋例外、不通知（Review Focus 3）', () async {
      final pendingPick = Completer<OpenBookPickedFile?>();
      var relinkCalls = 0;
      final flow = await failedFlow(relinkBook: (_, __) async {
        relinkCalls++;
        return BookRelinkSuccess(_book(_newUri));
      });
      final future = flow.relink(() => pendingPick.future);
      var notifications = 0;
      flow.addListener(() => notifications++);

      flow.dispose();
      pendingPick.complete(_picked);
      final outcome = await future;

      expect(outcome, isA<OpenBookRelinkCancelled>());
      expect(relinkCalls, 0);
      expect(notifications, 0);
    });

    test('relinkBook 處理中 dispose：結果回來不拋例外、不通知（Review Focus 3）', () async {
      final pending = Completer<BookRelinkResult>();
      final flow = await failedFlow(relinkBook: (_, __) => pending.future);
      final future = flow.relink(() async => _picked);
      await settle();
      var notifications = 0;
      flow.addListener(() => notifications++);

      flow.dispose();
      pending.complete(BookRelinkSuccess(_book(_newUri)));
      await future;

      expect(notifications, 0);
    });

    test('重新開書後再次視圖錯誤：以新路徑重新探測（Review Focus 5）', () async {
      final flow = await failedFlow(
          relinkBook: (_, __) async => BookRelinkSuccess(_book(_newUri)));
      await flow.relink(() async => _picked);

      flow.onViewError('又失敗');
      await settle();

      expect(probeCalls, [_contentUri, _newUri]);
      expect(flow.state, isA<OpenBookFailed>());
    });

    test('重新開書後再次卡住：新的 30 秒計時器到期會觸發逾時（Review Focus 5）', () async {
      final flow = await failedFlow(
          relinkBook: (_, __) async => BookRelinkSuccess(_book(_newUri)));
      await flow.relink(() async => _picked);

      timers.last.fire();
      await settle();

      expect((flow.state as OpenBookFailed).source,
          OpenBookFailureSource.timeout);
      expect(probeCalls, [_contentUri, _newUri]);
    });
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run：`cd app && flutter test test/reader/open_book_flow_test.dart`
Expected：編譯失敗，`Target of URI doesn't exist: 'package:elinkbook/reader/open_book_flow.dart'`。

- [ ] **Step 3：寫最小實作**

建立 `app/lib/reader/open_book_flow.dart`：

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../library/book_import_service.dart'
    show
        BookRelinkFailure,
        BookRelinkFailureReason,
        BookRelinkResult,
        BookRelinkSuccess;
import 'foliate_native_bridge.dart' show StorageAccessProbeResult;

/// 開書失敗的來源。畫面依它與探測結果決定顯示哪一段說明文字
/// （文字屬於 l10n，本模組不持有）。
enum OpenBookFailureSource {
  /// 閱讀視圖（Foliate／pdfrx）回報了錯誤。
  viewError,

  /// 30 秒內視圖沒有回報任何結果。
  timeout,
}

/// 開書流程的狀態（見 CONTEXT.md「開書流程」）。用密封類別而非列舉加多個
/// 旗標，讓「已渲染卻同時在探測」這類非法組合在型別上不可能出現。
sealed class OpenBookState {
  const OpenBookState();
}

/// 載入中，等待視圖回報結果。
final class OpenBookLoading extends OpenBookState {
  const OpenBookLoading();

  @override
  String toString() => 'OpenBookLoading';
}

/// 已偵測到失敗，正在探測 `content://` 的存取狀況。畫面仍顯示載入指示器，
/// 避免 E-Ink 先閃出通用錯誤再換成分類說明。
final class OpenBookProbing extends OpenBookState {
  const OpenBookProbing();

  @override
  String toString() => 'OpenBookProbing';
}

/// 已成功渲染。此後的錯誤不會再把畫面改成失敗。
final class OpenBookRendered extends OpenBookState {
  const OpenBookRendered();

  @override
  String toString() => 'OpenBookRendered';
}

/// 開書失敗。[probeResult] 只有 `content://` 書籍才有值。
final class OpenBookFailed extends OpenBookState {
  const OpenBookFailed({
    required this.source,
    this.viewMessage,
    this.probeResult,
  });

  final OpenBookFailureSource source;

  /// 視圖回報的錯誤訊息；[source] 為 timeout 時為 null。
  final String? viewMessage;
  final StorageAccessProbeResult? probeResult;

  // 只覆寫 toString：測試斷言失敗時才看得到內容，不會只印 Instance of。
  // 刻意不實作 ==／hashCode：測試以 same() 比對實例即可，沒有人需要值等價。
  @override
  String toString() => 'OpenBookFailed(source: $source, '
      'viewMessage: $viewMessage, probeResult: $probeResult)';
}

/// 重新連結處理中（含選檔期間）。保留進入前的 [failed]，畫面繼續顯示同一個
/// 錯誤視圖，只是按鈕停用並顯示進度。
final class OpenBookRelinking extends OpenBookState {
  const OpenBookRelinking(this.failed);

  final OpenBookFailed failed;

  @override
  String toString() => 'OpenBookRelinking($failed)';
}

/// [OpenBookFlow.relink] 的結果。
sealed class OpenBookRelinkOutcome {
  const OpenBookRelinkOutcome();
}

/// 重新連結成功，已回到 [OpenBookLoading] 並以 [newPath] 重新開書。
/// [newPath] 可能是落地複本的本機路徑，不一定是選取的 URI。
final class OpenBookRelinkReopened extends OpenBookRelinkOutcome {
  const OpenBookRelinkReopened(this.newPath);

  final String newPath;

  @override
  String toString() => 'OpenBookRelinkReopened($newPath)';
}

/// 重新連結失敗，狀態已回到進入前的 [OpenBookFailed]。
final class OpenBookRelinkFailed extends OpenBookRelinkOutcome {
  const OpenBookRelinkFailed(this.reason);

  final BookRelinkFailureReason reason;

  @override
  String toString() => 'OpenBookRelinkFailed($reason)';
}

/// 使用者取消選檔、目前不能重新連結（不在 Failed 狀態、處理中、沒有
/// relink 能力），或選檔期間已離開畫面。不需要提示使用者。
final class OpenBookRelinkCancelled extends OpenBookRelinkOutcome {
  const OpenBookRelinkCancelled();

  @override
  String toString() => 'OpenBookRelinkCancelled';
}

/// 探測 [uri] 的可讀性；保證不拋例外的契約由實作者負責，本模組仍會防禦。
typedef OpenBookProbe = Future<StorageAccessProbeResult> Function(String uri);

/// 以選好的檔案重新連結書籍記錄（`BookImportService.relinkBook` 的包裝）。
typedef OpenBookRelink = Future<BookRelinkResult> Function(
    String uri, String? displayName);

/// 使用者選取的檔案。與 `SingleBookFilePicker` 的回傳型別相同。
typedef OpenBookPickedFile = ({String uri, String? displayName});

/// 計時器工廠，預設是 [Timer.new]；測試注入假計時器以免等待真實時間。
typedef OpenBookTimerFactory = Timer Function(
    Duration duration, void Function() callback);

/// 開書流程控制器（epic-54-architecture-optimization Issue 5）。
///
/// 持有從載入、失敗探測、逾時，到重新連結後重新開書的整段狀態與規則；
/// `ReaderScreen` 只負責把視圖事件餵進來、依狀態畫畫面。`l10n` 文字、
/// SnackBar、選檔器與 EPUB 引擎分派仍屬 `ReaderScreen`。
class OpenBookFlow extends ChangeNotifier {
  OpenBookFlow({
    required String filePath,
    required this.probe,
    this.relinkBook,
    this.timeout = const Duration(seconds: 30),
    this.timerFactory = Timer.new,
  }) : _filePath = filePath;

  final OpenBookProbe probe;

  /// `null` 代表沒有重新連結能力（例如沒有匯入服務）。
  final OpenBookRelink? relinkBook;

  /// 開書逾時上限。30 秒是 epic-27-reader-device-compat Issue 2 依
  /// 慢速裝置真機回報調整的值（原為 12 秒）。
  final Duration timeout;
  final OpenBookTimerFactory timerFactory;

  String _filePath;

  /// 目前開啟的檔案路徑；重新連結成功後換成新路徑。
  String get filePath => _filePath;

  OpenBookState _state = const OpenBookLoading();
  OpenBookState get state => _state;

  /// 載入中或探測中：畫面仍顯示載入指示器，視圖手勢應忽略。
  bool get isLoading => _state is OpenBookLoading || _state is OpenBookProbing;

  bool get isRendered => _state is OpenBookRendered;

  /// 失敗或重新連結處理中：畫面顯示錯誤視圖。
  bool get isFailed => _state is OpenBookFailed || _state is OpenBookRelinking;

  /// 目前的失敗資訊；非失敗狀態為 null。
  OpenBookFailed? get failure => switch (_state) {
        OpenBookFailed failed => failed,
        OpenBookRelinking(:final failed) => failed,
        _ => null,
      };

  Timer? _timer;
  bool _disposed = false;

  /// 啟動開書逾時計時器。`ReaderScreen.initState` 呼叫一次。
  void start() => _restartTimer();

  /// 視圖回報錯誤。只在 [OpenBookLoading] 才處理：已渲染後的錯誤可能只是
  /// 良性警告（例如旋轉螢幕時的 ResizeObserver），不應覆蓋已顯示的內容；
  /// 探測中、失敗中再收到的錯誤也一律忽略。
  void onViewError(String message) {
    if (_disposed || _state is! OpenBookLoading) return;
    _timer?.cancel();
    _fail(OpenBookFailureSource.viewError, message);
  }

  /// 視圖回報已成功渲染。探測進行中先到時，探測結果之後會被捨棄。
  void onRendered() {
    if (_disposed) return;
    if (_state is! OpenBookLoading && _state is! OpenBookProbing) return;
    _timer?.cancel();
    _set(const OpenBookRendered());
  }

  /// 使用者要求重新連結。先進入 [OpenBookRelinking]（期間按鈕停用），再呼叫
  /// 由 Widget 提供的 [pick] 選檔；`null` 代表取消。保證不拋例外：選檔或
  /// relinkBook 的任何例外都視為 failed。
  Future<OpenBookRelinkOutcome> relink(
    Future<OpenBookPickedFile?> Function() pick,
  ) async {
    final current = _state;
    final relinkBook = this.relinkBook;
    if (_disposed || current is! OpenBookFailed || relinkBook == null) {
      return const OpenBookRelinkCancelled();
    }
    _set(OpenBookRelinking(current));

    OpenBookRelinkOutcome outcome;
    try {
      final picked = await pick();
      // 選檔期間使用者可能已離開閱讀器：不再發動 relinkBook，避免白做整檔
      // SHA-256 與持久化授權。
      if (_disposed || picked == null) {
        outcome = const OpenBookRelinkCancelled();
      } else {
        final result = await relinkBook(picked.uri, picked.displayName);
        outcome = switch (result) {
          BookRelinkSuccess(:final updatedBook) =>
            OpenBookRelinkReopened(updatedBook.filePath),
          BookRelinkFailure(:final reason) => OpenBookRelinkFailed(reason),
        };
      }
    } catch (_) {
      outcome = const OpenBookRelinkFailed(BookRelinkFailureReason.failed);
    }

    if (_disposed) return outcome;
    switch (outcome) {
      case OpenBookRelinkReopened(:final newPath):
        _filePath = newPath;
        _set(const OpenBookLoading());
        _restartTimer();
      case OpenBookRelinkFailed() || OpenBookRelinkCancelled():
        _set(current);
    }
    return outcome;
  }

  /// 只在仍是載入中時才建立計時器：已 dispose 或已渲染／失敗後不留下
  /// 無效的 30 秒背景計時器。
  void _restartTimer() {
    if (_disposed || _state is! OpenBookLoading) return;
    _timer?.cancel();
    _timer = timerFactory(timeout, _onTimeout);
  }

  void _onTimeout() {
    if (_disposed || _state is! OpenBookLoading) return;
    _fail(OpenBookFailureSource.timeout, null);
  }

  /// 失敗共同入口。`content://` 先探測再決定錯誤畫面，維持載入指示器；
  /// 其他路徑沒有存取權限問題，直接失敗。
  void _fail(OpenBookFailureSource source, String? viewMessage) {
    if (!_filePath.startsWith('content://')) {
      _set(OpenBookFailed(source: source, viewMessage: viewMessage));
      return;
    }
    _set(const OpenBookProbing());
    unawaited(_probeThenFail(source, viewMessage, _filePath));
  }

  /// 失敗來源與路徑以參數傳入（closure 捕獲），不另存實例欄位。
  Future<void> _probeThenFail(
    OpenBookFailureSource source,
    String? viewMessage,
    String targetPath,
  ) async {
    StorageAccessProbeResult result;
    try {
      result = await probe(targetPath);
    } catch (_) {
      // 計時器在進入探測前已取消或已觸發；探測函式若拋例外而不切到失敗，
      // 閱讀器會永遠停在載入中。
      result = StorageAccessProbeResult.unknownError;
    }
    // 結果回來時若已離開畫面，或開書其實已成功（狀態不再是 Probing），
    // 直接捨棄。
    if (_disposed || _state is! OpenBookProbing) return;
    _set(OpenBookFailed(
      source: source,
      viewMessage: viewMessage,
      probeResult: result,
    ));
  }

  void _set(OpenBookState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  /// 可重複呼叫：已 dispose 時為無害的空操作（`ChangeNotifier.dispose` 本身
  /// 重複呼叫會拋錯，而測試會同時明確 dispose 與 `addTearDown`）。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：`cd app && flutter test test/reader/open_book_flow_test.dart`
Expected：全部 PASS（`dispose()` 已設計為可重複呼叫，所以 `addTearDown(flow.dispose)` 與測試內明確 dispose 並存不會拋錯）。

- [ ] **Step 5：analyze 並提交**

```bash
cd app && flutter analyze
git add lib/reader/open_book_flow.dart test/reader/open_book_flow_test.dart
git commit -m "feat(reader): epic-54 Issue 5 新增 OpenBookFlow 開書流程控制器與純測試

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`No issues found!`。

---

### Task 2：`ReaderScreen` 改接 `OpenBookFlow`

**Files：**
- Modify: `app/lib/screens/reader_screen.dart`（列號為 Task 1 完成時的現況，每個 Step 先用 Grep 重新定位再改）
- Test: `app/test/screens/reader_screen_test.dart`（本 Task 不改測試，先確認既有測試在接線後仍綠，唯一預期會紅的是「開書逾時不呼叫探測」，留到 Task 3）

**Interfaces：**
- Consumes：Task 1 的 `OpenBookFlow` 全部公開成員、`OpenBookFailed`、`OpenBookRelinking`、`OpenBookRelinkOutcome` 家族、`OpenBookPickedFile`。
- Produces：`ReaderScreen` 對外行為不變（僅逾時探測一處調整）。

- [ ] **Step 1：新增 import**

在 `reader_screen.dart` 既有 `import '../reader/...'` 區塊（第 61 行 `show StorageAccessProbeResult, probeStorageAccess;` 附近）加：

```dart
import '../reader/open_book_flow.dart';
```

`StorageAccessProbeResult, probeStorageAccess` 的 import 保留（`probeStorageAccess` 由 initState 的探測 lambda 使用；`StorageAccessProbeResult` 由錯誤視圖的 `switch` 使用）。

- [ ] **Step 2：刪除舊狀態、改 `_activeFilePath`**

Grep 定位後修改：

1. 刪除 `enum _RenderState { loading, rendered, error }`（約 392 行）。
2. 刪除欄位：`_RenderState _state = _RenderState.loading;`、`String? _errorMessage;`、`StorageAccessProbeResult? _probeResult;`、`bool _isProbingAccess = false;`、`bool _isRelinking = false;`，以及各自上方的 doc comment（約 400–429 行）。
3. 刪除 `Timer? _openBookTimeoutTimer;` 及其上方整段 doc comment（約 595–609 行）；那段 30 秒的歷史沿革（epic-18 Issue 33、epic-27 Issue 2）已搬到 `OpenBookFlow.timeout` 的 doc comment。
4. 把
   ```dart
   late String _activeFilePath = widget.filePath;
   ```
   換成（保留其上方 doc comment 第一段，刪去「使用 `late` 惰性初始化…」與「刻意不在 `didUpdateWidget`…」兩段，改述如下）：
   ```dart
   /// 目前實際開啟的檔案路徑；「重新連結」成功後由 [_openBookFlow] 換成新路徑。
   /// 刻意不在 `didUpdateWidget` 跟隨建構參數 `filePath` 的變動：閱讀器一律由
   /// `MaterialPageRoute` 建立一次，沒有任何呼叫端會以不同 `filePath` 重建
   /// 同一個 `ReaderScreen`。
   String get _activeFilePath => _openBookFlow.filePath;

   /// 開書流程（見 CONTEXT.md「開書流程」）。在 `initState` 最前面建立，
   /// 因為 [_activeFilePath] 在其後的 `_resolveEpubEngineDispatch()` 就會讀取。
   late final OpenBookFlow _openBookFlow;
   ```

- [ ] **Step 3：`initState` 建立 flow、啟動計時**

在 `initState()` 的 `_creationZone = Zone.current;` 之後（`widget.readerActivityTracker?.markReaderOpened();` 之前）加：

```dart
    final importService = widget.bookImportService;
    _openBookFlow = OpenBookFlow(
      filePath: widget.filePath,
      // 讀取頂層可覆寫變數的當下值，widget test 才能以覆寫注入假探測。
      probe: (uri) => probeStorageAccess(uri),
      relinkBook: importService == null
          ? null
          : (uri, displayName) => importService.relinkBook(
                widget.bookId,
                uri,
                displayName: displayName,
              ),
    )..addListener(_onOpenBookFlowChanged);
```

並把
```dart
    _openBookTimeoutTimer = Timer(
      const Duration(seconds: 30),
      _handleOpenBookTimeout,
    );
```
換成
```dart
    _openBookFlow.start();
```

- [ ] **Step 4：`dispose` 與 listener**

`dispose()` 內把 `_openBookTimeoutTimer?.cancel();` 換成：

```dart
    _openBookFlow
      ..removeListener(_onOpenBookFlowChanged)
      ..dispose();
```

在 `dispose()` 之前（或緊鄰 `_handleError` 之前）新增：

```dart
  /// [_openBookFlow] 狀態變動時重繪。
  void _onOpenBookFlowChanged() {
    if (mounted) setState(() {});
  }
```

- [ ] **Step 5：改 `_handlePageRendered`**

把
```dart
    if (!mounted) return;
    _openBookTimeoutTimer?.cancel();
    setState(() => _state = _RenderState.rendered);
```
換成
```dart
    if (!mounted) return;
    _openBookFlow.onRendered();
```

- [ ] **Step 6：改寫失敗與重新連結處理函式**

把 `_handleError`、`_probeAccessAndShowError`、`_handleOpenBookTimeout`、`_handleRelinkPressed`、`_pickAndRelink`、`_reopenWithFilePath` 六個方法（約 2018–2169 行，含各自 doc comment）整段換成下列內容：

```dart
  /// 【/diagnose：真機回報旋轉螢幕後畫面被錯誤文字取代，無法繼續閱讀】
  /// 只在載入中才轉為錯誤畫面——書籍已成功渲染後才發生的 `onError` 不應覆蓋
  /// 掉已顯示的內容（例如旋轉螢幕時 Chromium 的 ResizeObserver 良性警告）。
  /// 這個 guard 與探測、逾時、重新連結的規則都收在 [OpenBookFlow]。
  void _handleError(String message) {
    if (!mounted) return;
    _openBookFlow.onViewError(message);
  }

  /// 「重新選取檔案」按鈕的處理函式。取消選檔時什麼都不做（不顯示
  /// SnackBar）；成功時原地重新開書；失敗時以 SnackBar 說明原因，錯誤視圖
  /// 維持原樣可再試一次。
  Future<void> _handleRelinkPressed() async {
    final outcome = await _openBookFlow.relink(_pickBookFileForRelink);
    if (!mounted) return;
    switch (outcome) {
      case OpenBookRelinkCancelled():
        return;
      case OpenBookRelinkReopened(:final newPath):
        // 先選錯、再選對時，收掉上一次的失敗提示，避免重新開書時畫面還掛著
        // 「內容不同」之類的錯誤訊息。
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // EPUB 版面偵測若在失敗前尚未完成（仍是 null），以新路徑重新觸發一次，
        // 否則 _buildBody 的 gating 條件會讓閱讀視圖永遠停在等待。偏好設定、
        // 閱讀位置、字型以 bookId 載入，重新連結不改 bookId，不需要重跑。
        if (_dispatchedIsFixedLayout == null &&
            detectBookFormat(newPath) == BookFormat.epub) {
          _resolveEpubEngineDispatch();
        }
      case OpenBookRelinkFailed(:final reason):
        final l10n = AppLocalizations.of(context)!;
        final message = switch (reason) {
          BookRelinkFailureReason.formatMismatch =>
            l10n.readerStorageRelinkFormatMismatch,
          BookRelinkFailureReason.contentMismatch =>
            l10n.readerStorageRelinkContentMismatch,
          BookRelinkFailureReason.alreadyInLibrary =>
            l10n.readerStorageRelinkAlreadyInLibrary,
          BookRelinkFailureReason.failed => l10n.readerStorageRelinkFailed,
        };
        // 先收掉上一則：連續選錯檔案時，新結果不必排在前一則（預設 4 秒）
        // 之後才出現，否則使用者會以為第二次嘗試沒有反應。
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// 開啟單檔選擇器（副檔名限定為原書格式），交給 [OpenBookFlow.relink]。
  /// 使用者取消時回傳 null。
  Future<OpenBookPickedFile?> _pickBookFileForRelink() {
    final picker = widget.pickSingleBookFile ?? pickSingleBookFileViaFilePicker;
    // 只有 EPUB／PDF／AZW3 會走到這裡，BookFormat 名稱即副檔名。
    return picker([detectBookFormat(_activeFilePath).name]);
  }
```

注意：`BookRelinkFailureReason` 由 `reader_screen.dart` 既有的 `book_import_service.dart` import 提供，不需新增；`BookRelinkResult`／`BookRelinkSuccess`／`BookRelinkFailure` 若因此不再被 `reader_screen.dart` 使用，且該 import 有 `show` 清單，依 `flutter analyze` 的 `unused_shown_name` 警告移除多餘名稱。

- [ ] **Step 7：改寫錯誤視圖**

Grep `if (_state == _RenderState.error) {` 定位（約 3069 行）。

1. 條件換成 `if (_openBookFlow.isFailed) {`，並在其內第一行加：
   ```dart
      final failure = _openBookFlow.failure!;
      final isRelinking = _openBookFlow.state is OpenBookRelinking;
   ```
2. 錯誤文字的 `switch` 換成：
   ```dart
                    switch (failure.probeResult) {
                      StorageAccessProbeResult.permissionRevoked =>
                        l10n.readerStoragePermissionRevokedMessage,
                      StorageAccessProbeResult.fileNotFound =>
                        l10n.readerStorageFileNotFoundMessage,
                      _ => switch (failure.source) {
                          OpenBookFailureSource.timeout =>
                            l10n.readerOpenBookTimeoutMessage,
                          OpenBookFailureSource.viewError =>
                            failure.viewMessage ??
                                l10n.readerFailedToLoadBookMessage,
                        },
                    },
   ```
3. 按鈕條件的 `_probeResult` 兩處換成 `failure.probeResult`；`_isRelinking` 兩處（按鈕的 `onPressed` 與 `child`）換成 `isRelinking`。

- [ ] **Step 8：其餘 `_state` 判斷**

Grep `_state == _RenderState|_state != _RenderState` 逐處替換（行號為現況）：

| 位置 | 原本 | 換成 |
|---|---|---|
| 約 3179、3346、3812、3838 | `_state == _RenderState.loading` | `_openBookFlow.isLoading` |
| 約 3242 | `_state != _RenderState.rendered` | `!_openBookFlow.isRendered` |
| 約 3246 | `_state == _RenderState.rendered ? ...` | `_openBookFlow.isRendered ? ...` |
| 約 3782 的 doc comment | `` `_state == _RenderState.loading` `` | `` `_openBookFlow.isLoading` `` |
| 約 3166 的行內註解 | `// _state == loading 時顯示——…` | `// _openBookFlow.isLoading 時顯示——…` |

- [ ] **Step 9：確認沒有殘留引用並 analyze**

```bash
cd app
grep -n "_RenderState\|_state == loading\|_openBookTimeoutTimer\|_isProbingAccess\|_isRelinking\|_probeResult\|_errorMessage\|_reopenWithFilePath\|_handleOpenBookTimeout\|_probeAccessAndShowError\|_pickAndRelink" lib/screens/reader_screen.dart
flutter analyze
```

Expected：grep 無輸出（若只剩 doc comment 內的歷史描述，改寫為新名稱）；`No issues found!`。

- [ ] **Step 10：跑相關 widget 測試**

Run：`flutter test test/screens/reader_screen_test.dart`

Expected：全部 PASS，**唯一例外**是「開書逾時不呼叫探測」會 FAIL（`probeCalls()` 變 1）——這是預期的行為調整，Task 3 處理。若有其他失敗，先確認是否為接線疏漏（常見原因：`_activeFilePath` 在 `initState` 之前被讀取、`isLoading` 漏換）。

- [ ] **Step 11：提交**

```bash
git add lib/screens/reader_screen.dart
git commit -m "refactor(reader): epic-54 Issue 5 ReaderScreen 改接 OpenBookFlow

開書失敗、探測、逾時、重新連結規則收進 OpenBookFlow；刪除 _RenderState
與 6 個狀態欄位。行為調整：content:// 書籍開書逾時也做存取探測。

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：整理 widget 測試（遷移、翻轉、新增）

**Files：**
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces：**
- Consumes：Task 2 之後的 `ReaderScreen` 行為；既有 helper `_pumpContentUriReader`、`_FakeSingleBookFilePicker`、`FakeBookImportService`、`_pumpUntil`。
- Produces：無。

遷移對照（刪除的 widget 測試 → 取代它的純測試）：

| 刪除的 widget 測試（`reader_screen_test.dart`） | Grep 定位關鍵字 | 取代它的純測試（`open_book_flow_test.dart`） |
|---|---|---|
| 探測未完成時連續兩次 onError 只探測一次，期間維持載入指示器 | `連續兩次 onError` | 「Probing 期間再收到視圖錯誤：只探測一次」；`isLoading` 於 Probing 為 true |
| 探測未完成時推進超過開書逾時，仍維持載入指示器、不顯示逾時訊息 | `推進超過開書逾時` | 「視圖回報錯誤」群組第一個測試（錯誤已取消計時器，`timers.single.cancelled`） |
| 探測未完成時 onPageRendered 先到，探測結果回來不覆蓋成錯誤畫面 | `onPageRendered 先到` | 「Probing 期間 onRendered 先到…」 |
| 探測函式本身拋出例外：退回原本的錯誤訊息，不停在載入中（審查 I-1） | `探測函式本身拋出例外` | 「探測函式拋出例外：視為 unknownError…」 |
| 探測未完成時離開閱讀器，結果回來後不拋例外 | `探測未完成時離開閱讀器` | 「dispose 之後：探測結果回來…」 |
| Re-link 處理中離開閱讀器，結果回來後不拋例外（Review Focus 3） | `Re-link 處理中離開閱讀器` | 「relinkBook 處理中 dispose…」 |
| 選檔期間離開閱讀器：選擇器回傳後不呼叫 relinkBook、不拋例外（計畫審查 M-4） | `選檔期間離開閱讀器` | 「選檔期間 dispose…」 |

注意：最後一個測試名稱在原始碼中是跨兩行的相鄰字串字面值（`'…不拋例外'` 換行 `'（計畫審查 M-4）'`），整句 Grep 會找不到；一律用上表「Grep 定位關鍵字」欄的短字串。

- [ ] **Step 1：翻轉「開書逾時不呼叫探測」**

Grep `開書逾時不呼叫探測` 定位，整個測試換成以下三個（第一個是翻轉後的原測試，後兩個是新增的接線測試）：

```dart
    testWidgets('開書逾時且權限已撤銷：顯示權限失效說明（探測一次）', (tester) async {
      final probeCalls = await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked);

      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      await tester.pump();

      expect(probeCalls(), 1);
      expect(
        tester.widget<Text>(find.byKey(const Key('reader_error_text'))).data,
        'App 對這個檔案的存取權限已失效，請重新選取檔案。',
      );
    });

    testWidgets('開書逾時且探測為 unknownError：維持逾時訊息', (tester) async {
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.unknownError);

      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('reader_error_text'))).data,
        '開書逾時，可能是系統 WebView 版本過舊或檔案異常',
      );
    });

    testWidgets('非 content:// 開書逾時：不探測，顯示逾時訊息', (tester) async {
      final probeCalls = await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          filePath: 'test/fixtures/sample.epub',
          probe: (_) async => StorageAccessProbeResult.permissionRevoked);

      await tester.pump(const Duration(seconds: 30));

      expect(probeCalls(), 0);
      expect(
        tester.widget<Text>(find.byKey(const Key('reader_error_text'))).data,
        '開書逾時，可能是系統 WebView 版本過舊或檔案異常',
      );
    });
```

- [ ] **Step 2：在「重新選取檔案」群組新增「逾時也提供重新選取」測試**

在 `group('重新選取檔案（epic-15-storage-permission Issue 2）'` 的「沒有匯入服務時只顯示分類說明，不顯示按鈕」測試之後加：

```dart
    testWidgets('開書逾時且權限已撤銷、有匯入服務：顯示重新選取按鈕（epic-54 Issue 5）',
        (tester) async {
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked,
          bookImportService: FakeBookImportService());

      await tester.pump(const Duration(seconds: 30));
      await _pumpUntil(
          tester, () => find.byKey(relinkButton).evaluate().isNotEmpty);

      expect(errorText(tester), 'App 對這個檔案的存取權限已失效，請重新選取檔案。');
      expect(find.byKey(relinkButton), findsOneWidget);
    });
```

- [ ] **Step 3：刪除 7 個已遷移的測試**

依上方對照表，用 Grep 以測試名稱定位，逐一刪除整個 `testWidgets(...)` 區塊（含緊鄰的空行）。刪除後 `Completer` 在該檔仍被其他測試使用（如「處理中按鈕停用」），不會變成未使用 import；`flutter analyze` 會確認。

- [ ] **Step 4：執行並提交**

```bash
cd app
flutter test test/screens/reader_screen_test.dart test/reader/open_book_flow_test.dart
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

Expected：全部 PASS；`No issues found!`；兩行 PASS。記下 `reader_screen_test` 新的測試總數（原 287，預期 287 − 7 + 3（翻轉 1 變 3，淨增 2）+ 1 = 283），寫進 Task 4 的開發記錄。

```bash
git add test/screens/reader_screen_test.dart
git commit -m "test(reader): epic-54 Issue 5 規則類 widget 測試遷到純測試，翻轉逾時探測

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：開發記錄、全套測試、準備發 PR

**Files：**
- Modify: `docs/epics/epic-54-architecture-optimization/epic.md`（開發記錄）
- Modify: `docs/epics/epic-54-architecture-optimization/issues.md`（Issue 5 狀態）
- Modify: `docs/epics.md`（第 65 列）

**Interfaces：**
- Consumes：Task 1–3 的實際測試數字。
- Produces：可發 PR 的分支。

- [ ] **Step 1：程式審查前先跑相關測試檔**

```bash
cd app
flutter test test/reader/open_book_flow_test.dart test/screens/reader_screen_test.dart test/reader/foliate_native_bridge_test.dart test/screens/font_management_screen_test.dart
```

Expected：全部 PASS（`foliate_native_bridge_test`、`font_management_screen_test` 確認 `probeStorageAccess` 未被動到）。

- [ ] **Step 2：請求程式審查**

使用 `superpowers:requesting-code-review`。審查報告存於 `docs/epics/epic-54-architecture-optimization/reviews/review-code-issue-5.md`（不進版控）；審查者只出報告，不直接改程式；依報告修訂前須先由使用者決定。

- [ ] **Step 3：全套測試（整張計畫的最後一個 Task，CLAUDE.md 規定此時跑一次）**

```bash
cd app
flutter test
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

Expected：全部 PASS（基準：Issue 1 合併時為 3221 個通過、1 個略過；本 Issue 預期淨增 34 個純測試（`for` 迴圈展開後）、widget 淨減 4 個，淨增約 +30，實際以執行結果為準）；`No issues found!`；兩行 PASS。

- [ ] **Step 4：寫開發記錄**

在 `epic.md`「開發記錄」末尾新增（數字以實際結果為準）：

```markdown
**2026-10-01 Issue 5 實作完成**：新增 `OpenBookFlow`（`app/lib/reader/open_book_flow.dart`，`ChangeNotifier`＋密封類別狀態 `Loading`／`Probing`／`Rendered`／`Failed`／`Relinking`）；`ReaderScreen` 刪除 `_RenderState` 與 6 個狀態欄位（`_state`、`_errorMessage`、`_probeResult`、`_isProbingAccess`、`_isRelinking`、`_openBookTimeoutTimer`），`_activeFilePath` 改為 flow 的 getter。細部調整（與設計表的差異）：`Failed` 存 `source`／`viewMessage`／`probeResult` 而非 `message`；`relink()` 接收選檔 callback 而非已選好的檔案，使選檔期間仍有狀態可停用按鈕。行為調整：`content://` 書籍開書逾時也做存取探測。測試：純測試 N 個（`open_book_flow_test.dart`）；`reader_screen_test` 遷出 7 個、翻轉 1 個（拆成 3 個）、新增 1 個。「relink 後再失敗會重新探測」既有 widget 測試已涵蓋，不另補。驗證：…
```

並把 `issues.md` Issue 5 狀態改為「🟡 進行中（`plans/plan-issue-5.md`）」、`epics.md` 第 65 列改為「Issue 1 已合併（PR #302）；Issue 5 實作完成待發 PR；Issue 2、3、4、6 待設計」。

- [ ] **Step 5：提交並準備發 PR**

```bash
cd /c/Users/fycdc/AI/elinkBook
git add docs/epics.md docs/epics/epic-54-architecture-optimization/epic.md docs/epics/epic-54-architecture-optimization/issues.md
git commit -m "docs(epic-54): Issue 5 實作完成，全套測試通過，準備發 PR

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

發 PR 與合併後的看板更新比照 Issue 1（PR 合併後再補一筆開發記錄並把 Issue 5 標為「🟢 已合併」）。依 CLAUDE.md，發 PR 前須經使用者確認。
