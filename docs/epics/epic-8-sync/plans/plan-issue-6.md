# Epic 8 — 雲端同步 Issue 6：Checkpoint 觸發機制 + 併發鎖 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 Issue 4/5 已經完成、目前只能被手動/測試呼叫的 `SyncEngine.runCheckpoint()`，接上三種真實觸發來源（App 背景化／書籍切換／閱讀中 5 分鐘計時器），並補上 `SyncEngine` 內建的單一執行鎖，避免三種來源短時間內重疊觸發時同時真的送出網路請求。

**Architecture：** `SyncEngine.runCheckpoint()` 本身新增 `_isSyncing` 旗標＋`try/finally`包住既有邏輯（併發鎖必須內建於 `SyncEngine`，見 spec.md「同步引擎」／issues.md Issue 6，不可放在外部包裝類別）。新增一個很薄的 `SyncCheckpointTrigger` 類別，唯一職責是「呼叫 `runCheckpoint()` 前先確認已登入（opt-in），未登入時完全不呼叫」——這一層登入閘門刻意留在 `SyncEngine` 之外，因為 `runCheckpoint()` 內部雖然也有登入判斷會早退，但 issues.md 明確要求「未登入時三種觸發來源皆不執行任何動作（**不呼叫** `runCheckpoint()`）」，需要呼叫端自己先判斷，才能讓測試觀察到「根本沒呼叫」而非「呼叫了但內部早退」。三個觸發點（`ElinkBookApp` 生命週期觀察者、`ReaderScreen.dispose()`、`ReaderScreen` 內的週期性 `Timer`）皆只認識 `SyncCheckpointTrigger`，不直接依賴 `SyncEngine`／`SyncAccountRepository`，讓 widget test 可以用簡單的假 callback 驗證，不需要牽動真實資料庫／PocketBase。

**Tech Stack：** Flutter（`dart:async` `Timer`／`WidgetsBindingObserver`），既有 `SyncEngine`／`SyncAccountRepository`（epic-8-sync Issue 2／4／5，皆已合併至 main），`flutter_test`（`tester.pump(Duration)` 驅動 fake clock 觸發 `Timer.periodic`；`tester.binding.handleAppLifecycleStateChanged()` 模擬 App 生命週期事件，本專案 `reader_screen_test.dart` 已有先例）。

## Global Constraints

- 所有新增/修改的程式碼註解、文件、commit message 一律使用正體中文（專案 `CLAUDE.md` 規定）。
- 每個 Task 完成後 `flutter analyze`（於 `app/` 目錄下執行）必須維持乾淨（"No issues found!"）。
- **併發鎖必須內建於 `SyncEngine.runCheckpoint()` 內部**（spec.md「同步引擎」：「`SyncEngine` 內建單一執行鎖」；issues.md Issue 6：「`SyncEngine` 新增單一執行鎖」）——不可把鎖狀態放在外部的 `SyncCheckpointTrigger` 或呼叫端，`SyncEngine` 才是唯一持有 `_isSyncing` 狀態的物件。
- **鎖定期間的後續觸發直接放棄，不排隊等待**（spec.md：「不排隊等待，因為排隊等待的那次觸發所代表的『此刻的本機異動』，下一次任何 checkpoint 自然會涵蓋到」）。
- **未登入時三種觸發來源皆不得呼叫 `runCheckpoint()`**（issues.md 逐字要求，見上方 Architecture 說明——這是呼叫端「先判斷登入態、不登入就完全不呼叫」的責任，不是單純依賴 `runCheckpoint()` 內部早退）。
- `SyncEngine` 既有的公開介面（`runCheckpoint()` 無參數、回傳 `Future<void>`；建構子既有具名參數）不得變動語意——Issue 4/5 的既有呼叫端（`app/test/sync/sync_engine_test.dart` 全部既有測試）必須維持全數通過，不得修改既有測試的預期行為。
- 5 分鐘閒置計時器採**單純的週期性 `Timer.periodic`**（開啟 `ReaderScreen` 期間每 5 分鐘觸發一次，不判斷使用者是否真的有互動）——issues.md 的「What to build」與單元測試要求皆只提到「閱讀中每 5 分鐘閒置計時器」觸發 checkpoint，沒有要求「偵測實際互動才重置倒數」的複雜度（那是 Backlog 中「閱讀統計」Epic 的熱點圖計時規則，PRD 該處明訂「排除閒置或背景狀態的時間」，是完全不同的機制與目的，不要混淆套用到這裡，YAGNI）。
- 三個觸發點呼叫 `SyncCheckpointTrigger.trigger()` 一律不 `await`（fire-and-forget）——比照 `reader_screen.dart` 既有 `_writeCurrentPosition()`／`_handlePrefsChanged` 不等待寫入完成的既有慣例，這些觸發點都位於同步方法（`dispose()`／`Timer` callback／`didChangeAppLifecycleState`）中，不需要、也不應該阻塞呼叫端。

---

### Task 1：`SyncEngine` 內建併發鎖

**Files：**
- Modify: `app/lib/sync/sync_engine.dart:17-66`（類別文件註解、`_onReadingPositionConflict` 欄位註解）、`app/lib/sync/sync_engine.dart:67-188`（`runCheckpoint()` 方法本身）
- Test: `app/test/sync/sync_engine_test.dart`

**Interfaces：**
- Consumes：無（`SyncEngine` 既有建構子與內部方法皆不變）。
- Produces：`SyncEngine.runCheckpoint()` 維持原有簽章（`Future<void> Function()`，無參數）——這是 Task 2-6 唯一需要知道的介面，行為新增「執行中時後續呼叫直接放棄」。

現況：`app/lib/sync/sync_engine.dart` 第 67 行起，`runCheckpoint()` 直接是完整的 checkpoint 邏輯本體（推送/下載/合併/墓碑清理），沒有任何併發防護。

- [ ] **Step 1：在 `sync_engine_test.dart` 寫一個會失敗的併發鎖測試**

在 `app/test/sync/sync_engine_test.dart` 第 101 行（`test('未登入時 runCheckpoint 直接早退...')` 結束的 `});` 之後、第 103 行 `test('有指紋的書籍新增一筆書籤...')` 之前）插入：

```dart
  test('併發鎖：兩次幾乎同時呼叫 runCheckpoint()，第二次在第一次仍執行中時直接放棄，不會兩次都真的送出網路請求',
      () async {
    var requestCount = 0;
    final mockClient = MockClient((request) async {
      requestCount++;
      return http.Response(
        jsonEncode({'items': [], 'page': 1, 'perPage': 1000, 'totalItems': 0}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = SyncEngine(
      db: libraryRepository.database,
      accountRepository: accountRepository,
      metadataRepository: metadataRepository,
      clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    // 不 await 第一次呼叫就立刻發起第二次呼叫，模擬兩個觸發來源幾乎同時
    // 觸發 checkpoint 的情境（例如使用者切書同時把 App 丟到背景）。
    final first = engine.runCheckpoint();
    final second = engine.runCheckpoint();
    await Future.wait([first, second]);
    final requestCountAfterConcurrentCalls = requestCount;

    // 鎖應已釋放：接著單獨呼叫一次，取得「一次完整 checkpoint」實際會發出
    // 的請求數作為基準，用來跟上面併發呼叫的結果比較——若鎖沒生效，併發
    // 呼叫會是基準的兩倍（兩次完整 checkpoint 都真的執行了）。
    requestCount = 0;
    await engine.runCheckpoint();
    final requestCountSingleRun = requestCount;

    expect(requestCountAfterConcurrentCalls, requestCountSingleRun,
        reason: '併發呼叫應只有一次真正執行 checkpoint 邏輯，網路請求數應與單次呼叫相同，'
            '而非兩倍');
  });

```

**Step 2：執行測試，確認目前會失敗**

Run: `cd app && flutter test test/sync/sync_engine_test.dart --plain-name "併發鎖"`

Expected: FAIL——`requestCountAfterConcurrentCalls` 會是 `requestCountSingleRun` 的兩倍（兩次呼叫都真的各自完整跑了一次 checkpoint，各自對 4 個標註 collection＋1 個閱讀位置 collection 送出下載 GET 請求）。

- [ ] **Step 3：實作併發鎖**

修改 `app/lib/sync/sync_engine.dart`：

先把第 17-31 行的類別文件註解：

```dart
/// 雲端同步引擎核心（epic-8-sync Issue 4，spec.md「同步引擎」）：本 Issue
/// 只實作劃線/備註/書籤的推送/下載/合併與本機墓碑清理；閱讀位置的衝突
/// 預檢由 Issue 5 擴充同一個 [runCheckpoint]；三種觸發來源與併發鎖由
/// Issue 6 負責，本 Issue 的 [runCheckpoint] 僅需可被手動/測試呼叫。
///
/// **給 Issue 6 實作者的例外處理提醒**（審查意見 Minor #1，2026-08-04
/// `/superpowers:requesting-code-review`，見文末「審查修正紀錄」）：
/// [runCheckpoint] 只捕捉網路層的 `ClientException`（PocketBase SDK
/// 統一封裝的 HTTP 錯誤），**不**捕捉本機 SQLite 操作可能拋出的
/// `DatabaseException`（例如磁碟空間不足）——這是刻意的，本 Issue 不吞
/// 掉未預期的本機例外。Issue 6 規劃的 `_isSyncing` 執行鎖，呼叫
/// [runCheckpoint] 時**必須**用 `try { await runCheckpoint(); } finally
/// { _isSyncing = false; }` 包住，否則任何一次未預期的本機例外都會讓鎖
/// 永久卡住（需要重開 App 才能恢復），而不能假設 [runCheckpoint] 永遠
/// 不會拋出例外。
class SyncEngine {
```

改為：

```dart
/// 雲端同步引擎核心（epic-8-sync Issue 4，spec.md「同步引擎」）：本 Issue
/// 只實作劃線/備註/書籤的推送/下載/合併與本機墓碑清理；閱讀位置的衝突
/// 預檢由 Issue 5 擴充同一個 [runCheckpoint]；三種觸發來源由 Issue 6
/// 負責接上（見 `sync_checkpoint_trigger.dart`），本 Issue 的
/// [runCheckpoint] 僅需可被手動/測試呼叫。
///
/// **例外處理與併發鎖**（審查意見 Minor #1，2026-08-04
/// `/superpowers:requesting-code-review`；併發鎖由 epic-8-sync Issue 6
/// 實作，見 [_isSyncing]）：[runCheckpoint] 只捕捉網路層的
/// `ClientException`（PocketBase SDK 統一封裝的 HTTP 錯誤），**不**捕捉
/// 本機 SQLite 操作可能拋出的 `DatabaseException`（例如磁碟空間不足）
/// ——這是刻意的，本 Issue 不吞掉未預期的本機例外。[runCheckpoint] 內部
/// 一律用 `try { await _runCheckpointBody(); } finally { _isSyncing =
/// false; }` 包住實際執行內容，確保任何一次未預期的本機例外都不會讓鎖
/// 永久卡住（不需要呼叫端自行處理，也不能假設 [runCheckpoint] 永遠不會
/// 拋出例外）。
class SyncEngine {
```

再把第 38-53 行 `_onReadingPositionConflict` 欄位的文件註解：

```dart
  /// 見建構子 [onReadingPositionConflict] 參數說明。
  ///
  /// **給 Issue 6 實作者的提醒**（審查意見 Minor #1，2026-08-04
  /// `/superpowers:requesting-code-review`）：這個回呼被呼叫時
  /// [runCheckpoint] 會 `await` 它，直到使用者做出選擇（或關閉對話框）
  /// 才會繼續——若使用者放著對話框不理，`runCheckpoint()` 會無限期停滯。
  /// Issue 6 規劃的 `_isSyncing` 執行鎖若用 `try { await runCheckpoint();
  /// } finally { _isSyncing = false; }` 包住（見既有 `DatabaseException`
  /// 提醒），鎖本身不會因此洩漏，但使用者放著對話框不理期間，後續的
  /// checkpoint 觸發都會因為鎖已被佔用而直接放棄——這是可接受的行為
  /// （比照「同步失敗」的靜默重試精神，等使用者處理完對話框、下一次
  /// 觸發自然會繼續），只需確認 Task 4 的
  /// `showReadingPositionConflictDialog()` 在使用者點擊對話框外部區域時
  /// 會正確回傳 `null`（已在 Task 4 測試驗證過），不會讓 `runCheckpoint()`
  /// 真的卡死。
  final ReadingPositionConflictResolver? _onReadingPositionConflict;
```

改為：

```dart
  /// 見建構子 [onReadingPositionConflict] 參數說明。
  ///
  /// **與併發鎖的互動**（審查意見 Minor #1，2026-08-04
  /// `/superpowers:requesting-code-review`；epic-8-sync Issue 6 實作
  /// [_isSyncing]）：這個回呼被呼叫時 [runCheckpoint] 會 `await` 它，
  /// 直到使用者做出選擇（或關閉對話框）才會繼續——若使用者放著對話框
  /// 不理，`runCheckpoint()` 會無限期停滯。[runCheckpoint] 內部的
  /// `try { ... } finally { _isSyncing = false; }` 保證鎖本身不會因此
  /// 洩漏，但使用者放著對話框不理期間，後續的 checkpoint 觸發都會因為
  /// 鎖已被佔用而直接放棄——這是可接受的行為（比照「同步失敗」的靜默
  /// 重試精神，等使用者處理完對話框、下一次觸發自然會繼續），
  /// `showReadingPositionConflictDialog()` 在使用者點擊對話框外部區域時
  /// 會正確回傳 `null`（見 `reading_position_conflict_dialog.dart` 既有
  /// 測試），不會讓 `runCheckpoint()` 真的卡死。
  final ReadingPositionConflictResolver? _onReadingPositionConflict;
```

最後把第 67 行 `Future<void> runCheckpoint() async {` 這一行本身改名為 `Future<void> _runCheckpointBody() async {`，**方法本體（原第 68-188 行，一路到 `await _purgeTombstones();` 之後的收尾 `}`）完全不變**，只改這一行方法簽章；再緊接在這個（改名後的）方法**之前**插入新的公開 `runCheckpoint()` 與 `_isSyncing` 欄位：

```dart
  /// epic-8-sync Issue 6（spec.md「同步引擎」併發防護）：SyncEngine 內建
  /// 單一執行鎖，避免三種 checkpoint 觸發來源（App 背景化／書籍切換／5
  /// 分鐘閒置計時器，見 `sync_checkpoint_trigger.dart`）短時間內幾乎同時
  /// 呼叫 [runCheckpoint] 時真的同時送出兩份網路請求。鎖定期間的後續
  /// 呼叫直接放棄（不排隊），比照「同步失敗」的靜默重試精神——放棄的那次
  /// 呼叫所代表的本機異動，下一次任何 checkpoint 自然會涵蓋到。
  bool _isSyncing = false;

  Future<void> runCheckpoint() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await _runCheckpointBody();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _runCheckpointBody() async {
    // ↑ 原本的 `runCheckpoint()` 方法本體從這裡開始，內容完全不變。
```

（上面最後一行只是標註插入位置，不是要實際寫進檔案的文字——實際編輯時，第 67 行原文 `Future<void> runCheckpoint() async {` 直接替換成 `Future<void> _runCheckpointBody() async {`，其餘原本方法內容原封不動接在後面。）

- [ ] **Step 4：執行測試，確認通過**

Run: `cd app && flutter test test/sync/sync_engine_test.dart --plain-name "併發鎖"`

Expected: PASS。

- [ ] **Step 5：執行整份 `sync_engine_test.dart`，確認無回歸**

Run: `cd app && flutter test test/sync/sync_engine_test.dart`

Expected: 全數 PASS（既有 Issue 4/5 測試皆只呼叫一次 `runCheckpoint()`，新的鎖對它們的行為無影響）。

- [ ] **Step 6：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`

Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/sync/sync_engine.dart app/test/sync/sync_engine_test.dart
git commit -m "feat(epic-8-sync): Issue 6 Task 1 — SyncEngine 內建併發鎖"
```

---

### Task 2：`SyncCheckpointTrigger`——登入閘門包裝

**Files：**
- Create: `app/lib/sync/sync_checkpoint_trigger.dart`
- Test: `app/test/sync/sync_checkpoint_trigger_test.dart`

**Interfaces：**
- Consumes：無（純函式注入，不依賴 `SyncEngine`／`SyncAccountRepository` 具體型別，見下方類別設計）。
- Produces：`SyncCheckpointTrigger`——建構子具名參數 `isLoggedIn`（`Future<bool> Function()`）／`runCheckpoint`（`Future<void> Function()`）；方法 `Future<void> trigger()`。Task 3-6 皆只透過這個類別呼叫同步引擎，不直接持有 `SyncEngine`。

- [ ] **Step 1：寫失敗測試**

建立 `app/test/sync/sync_checkpoint_trigger_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';

void main() {
  test('已登入時，trigger() 呼叫 runCheckpoint()', () async {
    var runCheckpointCallCount = 0;
    final trigger = SyncCheckpointTrigger(
      isLoggedIn: () async => true,
      runCheckpoint: () async {
        runCheckpointCallCount++;
      },
    );

    await trigger.trigger();

    expect(runCheckpointCallCount, 1);
  });

  test('未登入時，trigger() 不呼叫 runCheckpoint()', () async {
    var runCheckpointCallCount = 0;
    final trigger = SyncCheckpointTrigger(
      isLoggedIn: () async => false,
      runCheckpoint: () async {
        runCheckpointCallCount++;
      },
    );

    await trigger.trigger();

    expect(runCheckpointCallCount, 0);
  });

  test('trigger() 每次呼叫都重新檢查登入狀態', () async {
    var loggedIn = false;
    var runCheckpointCallCount = 0;
    final trigger = SyncCheckpointTrigger(
      isLoggedIn: () async => loggedIn,
      runCheckpoint: () async {
        runCheckpointCallCount++;
      },
    );

    await trigger.trigger();
    expect(runCheckpointCallCount, 0, reason: '第一次呼叫時尚未登入');

    loggedIn = true;
    await trigger.trigger();
    expect(runCheckpointCallCount, 1, reason: '第二次呼叫時已登入，應正常觸發');
  });
}
```

- [ ] **Step 2：執行測試，確認失敗**

Run: `cd app && flutter test test/sync/sync_checkpoint_trigger_test.dart`

Expected: FAIL（`package:elinkbook/sync/sync_checkpoint_trigger.dart` 尚不存在，編譯錯誤）。

- [ ] **Step 3：實作 `SyncCheckpointTrigger`**

建立 `app/lib/sync/sync_checkpoint_trigger.dart`：

```dart
/// Checkpoint 觸發器（epic-8-sync Issue 6，spec.md「同步引擎」／
/// issues.md Issue 6）：包裝一次 `SyncEngine.runCheckpoint()` 呼叫，
/// 加上「未登入（opt-in 尚未啟用同步）時完全不呼叫」的登入閘門。
///
/// 併發鎖**不**由本類別負責——`SyncEngine.runCheckpoint()` 本身已內建
/// 單一執行鎖（見 `sync_engine.dart` 的 `_isSyncing`，spec.md「同步
/// 引擎」明定併發鎖須內建於 `SyncEngine`），本類別只單純轉呼叫。
///
/// 刻意用函式注入（[isLoggedIn]／[runCheckpoint]）而非直接持有
/// `SyncAccountRepository`／`SyncEngine` 具體型別：三個實際觸發點
/// （App 生命週期觀察者、`ReaderScreen.dispose()`、`ReaderScreen` 內的
/// 週期性 `Timer`）都只需要「呼叫一次 checkpoint」這個動作，注入函式
/// 讓 widget test 可以用簡單的假 callback 驗證觸發時機，不需要牽動真實
/// 資料庫／PocketBase 用戶端。
class SyncCheckpointTrigger {
  final Future<bool> Function() _isLoggedIn;
  final Future<void> Function() _runCheckpoint;

  SyncCheckpointTrigger({
    required Future<bool> Function() isLoggedIn,
    required Future<void> Function() runCheckpoint,
  })  : _isLoggedIn = isLoggedIn,
        _runCheckpoint = runCheckpoint;

  Future<void> trigger() async {
    if (!await _isLoggedIn()) return;
    await _runCheckpoint();
  }
}
```

- [ ] **Step 4：執行測試，確認通過**

Run: `cd app && flutter test test/sync/sync_checkpoint_trigger_test.dart`

Expected: PASS（3 個測試）。

- [ ] **Step 5：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`

Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/sync/sync_checkpoint_trigger.dart app/test/sync/sync_checkpoint_trigger_test.dart
git commit -m "feat(epic-8-sync): Issue 6 Task 2 — SyncCheckpointTrigger 登入閘門"
```

---

### Task 3：`ReaderScreen`——書籍切換觸發 checkpoint

**Files：**
- Modify: `app/lib/screens/reader_screen.dart`（新增欄位／建構子參數／`dispose()` 呼叫）
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces：**
- Consumes：`SyncCheckpointTrigger.trigger()`（Task 2 產出，回傳 `Future<void>`）。
- Produces：`ReaderScreen` 新增可選具名建構參數 `syncCheckpointTrigger`（型別 `SyncCheckpointTrigger?`），比照既有 `customFontsRepository` 等可選參數慣例——未提供時完全零回歸。Task 4／6 沿用同一個欄位。

- [ ] **Step 1：在 `reader_screen_test.dart` 寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 檔案頂部 import 區塊（第 45 行 `import 'package:elinkbook/reader/highlight_style.dart';` 之後）新增：

```dart
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
```

在第 4535 行（「離開 ReaderScreen 時，elinkbook/fullscreen 頻道收到 setEnabled(false) 無條件還原」測試結束的 `});`）之後插入：

```dart

  testWidgets('離開 ReaderScreen（書籍切換）觸發一次 checkpoint', (tester) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => true,
      runCheckpoint: () async {
        triggerCallCount++;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open_reader'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    filePath: 'test/fixtures/sample.pdf',
                    bookId: 'b1',
                    prefsManager: prefsManager,
                    syncCheckpointTrigger: syncCheckpointTrigger,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(triggerCallCount, 0, reason: '開書當下不應觸發 checkpoint');

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(triggerCallCount, 1);
  });

  testWidgets('未提供 syncCheckpointTrigger 時，離開 ReaderScreen 不拋出例外（零回歸）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open_reader'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    filePath: 'test/fixtures/sample.pdf',
                    bookId: 'b1',
                    prefsManager: prefsManager,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 2：執行測試，確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "書籍切換"`

Expected: FAIL——`ReaderScreen` 建構子沒有 `syncCheckpointTrigger` 具名參數，編譯錯誤。

- [ ] **Step 3：實作**

在 `app/lib/screens/reader_screen.dart` 頂部 import 區塊（第 37 行 `import '../reader/zone_action.dart';` 之後、`import 'annotation_toolbar.dart';` 之前）新增：

```dart
import '../sync/sync_checkpoint_trigger.dart';
```

在 `ReaderScreen` 類別（第 118 行 `final CustomFontsRepository? customFontsRepository;` 之後）新增欄位：

```dart

  /// Checkpoint 觸發器（epic-8-sync Issue 6）。刻意為可選參數——比照
  /// [bookmarksRepository] 既有慣例，未提供時離開閱讀畫面／背景化／閒置
  /// 計時器皆不觸發任何同步動作，行為等同本 Issue 之前，零回歸。
  final SyncCheckpointTrigger? syncCheckpointTrigger;
```

在建構子（第 120-134 行）的 `this.customFontsRepository,` 之後新增：

```dart
    this.syncCheckpointTrigger,
```

在 `dispose()` 方法（第 346-364 行）的 `_writeCurrentPosition();` 呼叫（第 355 行）之後新增：

```dart
    // epic-8-sync Issue 6（spec.md「同步引擎」checkpoint 觸發來源之
    // 「書籍切換」）：離開閱讀畫面視為一次書籍切換，觸發一次 checkpoint。
    // 刻意排在 _writeCurrentPosition() 之後——ReadingPositionRepository.
    // saveReadingPosition() 會同步寫入 books.position_updated_at（見該
    // 檔案），確保這裡觸發的 checkpoint 能把剛寫入的最新閱讀位置一併
    // 判定為待推送。不 await，理由同上一行 _writeCurrentPosition()，
    // dispose() 是同步方法；未登入或已有 checkpoint 執行中時
    // SyncCheckpointTrigger.trigger() 內部會直接放棄，不會拋出例外。
    widget.syncCheckpointTrigger?.trigger();
```

- [ ] **Step 4：執行測試，確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "書籍切換"`

Expected: PASS（2 個測試）。

- [ ] **Step 5：執行整份 `reader_screen_test.dart`，確認無回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`

Expected: 全數 PASS。

- [ ] **Step 6：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`

Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-8-sync): Issue 6 Task 3 — 離開 ReaderScreen（書籍切換）觸發 checkpoint"
```

---

### Task 4：`ReaderScreen`——5 分鐘閒置計時器觸發 checkpoint

**Files：**
- Modify: `app/lib/screens/reader_screen.dart`（新增 `Timer` 欄位、`initState()`/`dispose()` 啟動與取消）
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces：**
- Consumes：`widget.syncCheckpointTrigger`（Task 3 已新增的欄位）。
- Produces：無新增公開介面，純內部行為擴充。

- [ ] **Step 1：寫失敗測試**

在 `app/test/screens/reader_screen_test.dart`（緊接 Task 3 新增的兩個測試之後）插入：

```dart

  testWidgets('閱讀中每 5 分鐘計時器觸發 checkpoint，離開畫面後計時器停止', (tester) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => true,
      runCheckpoint: () async {
        triggerCallCount++;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open_reader'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    filePath: 'test/fixtures/sample.pdf',
                    bookId: 'b1',
                    prefsManager: prefsManager,
                    syncCheckpointTrigger: syncCheckpointTrigger,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(triggerCallCount, 0);

    await tester.pump(const Duration(minutes: 5));
    expect(triggerCallCount, 1, reason: '第一次 5 分鐘計時應觸發一次 checkpoint');

    await tester.pump(const Duration(minutes: 5));
    expect(triggerCallCount, 2, reason: '計時器應持續每 5 分鐘觸發一次');

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();
    // 離開畫面當下 Task 3 的「書籍切換」觸發也會呼叫一次 trigger()，
    // 這裡只關心「離開之後計時器是否已停止」，故以離開當下的次數為基準，
    // 不假設離開當下的確切次數。
    final countAfterLeaving = triggerCallCount;

    await tester.pump(const Duration(minutes: 5));
    expect(triggerCallCount, countAfterLeaving,
        reason: '離開畫面後計時器應已被 cancel，不應再繼續觸發');
  });
```

- [ ] **Step 2：執行測試，確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "5 分鐘計時器"`

Expected: FAIL——目前沒有任何計時器邏輯，`triggerCallCount` 在 `tester.pump(const Duration(minutes: 5))` 後仍是 0。

- [ ] **Step 3：實作**

在 `app/lib/screens/reader_screen.dart` 頂部新增 `dart:async` import（目前檔案完全沒有任何 `dart:` 開頭的 import，加在第 1 行 `import 'package:flutter/material.dart';` 之前）：

```dart
import 'dart:async';

```

在 `_ReaderScreenState` 類別內、`_dispatchedIsFixedLayout` 欄位（第 278 行）之後新增：

```dart

  // epic-8-sync Issue 6：閱讀中每 5 分鐘觸發一次 checkpoint 的週期性
  // 計時器。單純的週期性 Timer（不判斷使用者是否真的有互動），見
  // plan-issue-6.md Global Constraints 的 YAGNI 說明。未提供
  // syncCheckpointTrigger 時完全不建立（見 initState），零額外開銷。
  Timer? _syncCheckpointTimer;
```

在 `initState()`（第 280-303 行）的 `_loadCustomFonts();` 呼叫之後新增：

```dart
    final syncCheckpointTrigger = widget.syncCheckpointTrigger;
    if (syncCheckpointTrigger != null) {
      _syncCheckpointTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => syncCheckpointTrigger.trigger(),
      );
    }
```

在 `dispose()`（第 346-364 行）的最開頭、`WidgetsBinding.instance.removeObserver(this);` 這一行**之前**新增：

```dart
    _syncCheckpointTimer?.cancel();
```

- [ ] **Step 4：執行測試，確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "5 分鐘計時器"`

Expected: PASS。

- [ ] **Step 5：執行整份 `reader_screen_test.dart`，確認無回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`

Expected: 全數 PASS（既有測試皆未提供 `syncCheckpointTrigger`，`_syncCheckpointTimer` 維持 `null`，不受影響；本專案既有測試也不會意外因為背景計時器殘留而在 `tearDown` 後跳出 pending-timer 警告，因為每個測試各自的 `tester.pumpWidget` 產生獨立 widget tree，測試結束時 `flutter_test` 會自動 dispose）。

- [ ] **Step 6：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`

Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-8-sync): Issue 6 Task 4 — 閱讀中 5 分鐘計時器觸發 checkpoint"
```

---

### Task 5：`ElinkBookApp`——App 背景化觸發 checkpoint

**Files：**
- Modify: `app/lib/main.dart`（`ElinkBookApp` 新增欄位／`_ElinkBookAppState` 新增生命週期觀察者）
- Test: `app/test/app_lifecycle_sync_test.dart`（新檔案，比照既有 `app/test/navigation_test.dart` 直接放在 `app/test/` 下的慣例——這個測試針對 `ElinkBookApp`／`main.dart` 本身，不屬於任何既有子資料夾主題）

**Interfaces：**
- Consumes：`SyncCheckpointTrigger.trigger()`（Task 2）。
- Produces：`ElinkBookApp` 新增可選具名建構參數 `syncCheckpointTrigger`（型別 `SyncCheckpointTrigger?`）。Task 6 沿用同一個欄位並實際組裝真正的物件傳入。

- [ ] **Step 1：寫失敗測試**

建立 `app/test/app_lifecycle_sync_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/main.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';

import 'support/fake_book_import_service.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_reader_prefs_manager.dart';

void main() {
  testWidgets('App 進入背景（AppLifecycleState.paused）時觸發一次 checkpoint',
      (tester) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => true,
      runCheckpoint: () async {
        triggerCallCount++;
      },
    );

    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
        syncCheckpointTrigger: syncCheckpointTrigger,
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(triggerCallCount, 1);
  });

  testWidgets('App 恢復前景（AppLifecycleState.resumed）不觸發 checkpoint', (tester) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => true,
      runCheckpoint: () async {
        triggerCallCount++;
      },
    );

    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
        syncCheckpointTrigger: syncCheckpointTrigger,
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(triggerCallCount, 0);
  });

  testWidgets('未提供 syncCheckpointTrigger 時，App 進入背景不拋出例外（零回歸）',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2：執行測試，確認失敗**

Run: `cd app && flutter test test/app_lifecycle_sync_test.dart`

Expected: FAIL——`ElinkBookApp` 建構子沒有 `syncCheckpointTrigger` 具名參數，編譯錯誤。

- [ ] **Step 3：實作**

修改 `app/lib/main.dart`：

在 import 區塊（第 17 行 `import 'sync/sync_account_repository.dart';` 之後）新增：

```dart
import 'sync/sync_checkpoint_trigger.dart';
```

在 `ElinkBookApp` 類別（第 79 行 `final SyncClient? syncClient;` 之後）新增欄位：

```dart
  final SyncCheckpointTrigger? syncCheckpointTrigger;
```

在其建構子（第 84-98 行）的 `this.syncClient,` 之後新增：

```dart
    this.syncCheckpointTrigger,
```

把 `_ElinkBookAppState` 類別宣告（第 104 行 `class _ElinkBookAppState extends State<ElinkBookApp> {`）改為加上 `WidgetsBindingObserver` mixin：

```dart
class _ElinkBookAppState extends State<ElinkBookApp> with WidgetsBindingObserver {
```

在 `initState()`（第 108-113 行）新增 observer 註冊：

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _theme = widget.initialTheme;
    _isEinkMode = widget.initialEinkMode;
  }
```

（即在既有的 `super.initState();` 之後、`_theme = widget.initialTheme;` 之前插入 `WidgetsBinding.instance.addObserver(this);` 這一行，其餘既有內容不變。）

在 `initState()` 之後新增 `dispose()`／`didChangeAppLifecycleState()`（`_ElinkBookAppState` 目前沒有 `dispose()` 覆寫）：

```dart

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// epic-8-sync Issue 6（spec.md「同步引擎」checkpoint 觸發來源之
  /// 「App 生命週期監聽」）：只在 [AppLifecycleState.paused]（真正進入
  /// 背景）觸發，不含 [AppLifecycleState.inactive]（系統對話框短暫遮蓋等
  /// 過渡狀態）——比照 `reader_screen.dart` 既有
  /// `didChangeAppLifecycleState` 對 `_writeCurrentPosition()` 的同一條
  /// 判斷準則。不 await，理由同 `reader_screen.dart` 既有慣例。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      widget.syncCheckpointTrigger?.trigger();
    }
  }
```

- [ ] **Step 4：執行測試，確認通過**

Run: `cd app && flutter test test/app_lifecycle_sync_test.dart`

Expected: PASS（3 個測試）。

- [ ] **Step 5：執行既有 `theme_test.dart`，確認無回歸**

Run: `cd app && flutter test test/theme/theme_test.dart`

Expected: 全數 PASS（該檔案直接建構 `ElinkBookApp` 且未提供 `syncCheckpointTrigger`，新增的 `WidgetsBindingObserver` 對其行為無影響）。

- [ ] **Step 6：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`

Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/main.dart app/test/app_lifecycle_sync_test.dart
git commit -m "feat(epic-8-sync): Issue 6 Task 5 — App 背景化（AppLifecycleState.paused）觸發 checkpoint"
```

---

### Task 6：`main()` 正式組裝 `SyncEngine`／`SyncCheckpointTrigger`，並貫穿 `LibraryScreen` → `ReaderScreen`

**背景（與 issues.md 的落差說明）：** Issue 4／5 只在測試中建構過 `SyncEngine`，`main.dart` 從未真正組裝過一個會實際運作的 `SyncEngine` 實例——`SyncEngine` 建構需要的 `SyncMetadataRepository`、`SyncEngine` 本身、閱讀位置衝突對話框（`reading_position_conflict_dialog.dart`，Issue 5 產出但同樣從未接上任何呼叫端）都還停留在「類別已存在、從未被 App 實際使用」的狀態。Task 1-5 完成的是「觸發機制＋併發鎖」這個 issues.md 明確列出的骨架，但這個骨架必須接上一個真正的 `SyncEngine` 才有意義——本 Task 補上這個必要但 issues.md 沒有逐字列出的組裝步驟，屬於「三種 checkpoint 觸發來源接上 `SyncEngine.runCheckpoint()`」這句 What-to-build 裡「接上」兩個字實際要求的工作範圍，不是額外加碼的新功能。

**Files：**
- Modify: `app/lib/main.dart`（`main()` 函式本體組裝＋ `ElinkBookApp` 新增 `navigatorKey` 欄位）
- Modify: `app/lib/screens/library_screen.dart`（新增 `syncCheckpointTrigger` 欄位並貫穿至 `ReaderScreen`）
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces：**
- Consumes：`SyncEngine`（Issue 4/5，`app/lib/sync/sync_engine.dart`）、`SyncMetadataRepository`（Issue 4，`app/lib/sync/sync_metadata_repository.dart`）、`showReadingPositionConflictDialog`（Issue 5，`app/lib/screens/reading_position_conflict_dialog.dart`）、`SyncCheckpointTrigger`（Task 2）。
- Produces：`LibraryScreen` 新增可選具名建構參數 `syncCheckpointTrigger`（型別 `SyncCheckpointTrigger?`），貫穿至其內部 `_openBook()` 建構的 `ReaderScreen`。

- [ ] **Step 1：在 `library_screen_test.dart` 寫失敗測試**

在 `app/test/screens/library_screen_test.dart` 頂部 import 區塊新增：

```dart
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
```

在既有「LibraryScreen 點開一本書後，ReaderScreen 收到的 customFontsRepository 正確貫穿」測試（第 2529-2564 行）之後插入：

```dart

  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 syncCheckpointTrigger 正確貫穿',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => false,
      runCheckpoint: () async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          syncCheckpointTrigger: syncCheckpointTrigger,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.syncCheckpointTrigger, same(syncCheckpointTrigger),
        reason: 'LibraryScreen._openBook() 未把 syncCheckpointTrigger 貫穿給 '
            'ReaderScreen，離開閱讀畫面時就不會觸發書籍切換 checkpoint');
  });
```

- [ ] **Step 2：執行測試，確認失敗**

Run: `cd app && flutter test test/screens/library_screen_test.dart --plain-name "syncCheckpointTrigger 正確貫穿"`

Expected: FAIL——`LibraryScreen` 建構子沒有 `syncCheckpointTrigger` 具名參數，編譯錯誤。

- [ ] **Step 3：修改 `LibraryScreen`**

修改 `app/lib/screens/library_screen.dart`：

在 import 區塊（第 19 行 `import '../sync/sync_client.dart';` 之後）新增：

```dart
import '../sync/sync_checkpoint_trigger.dart';
```

在 `LibraryScreen` 類別（第 40 行 `final SyncClient? syncClient;` 之後）新增欄位：

```dart
  final SyncCheckpointTrigger? syncCheckpointTrigger;
```

在其建構子（第 47-63 行）的 `this.syncClient,` 之後新增：

```dart
    this.syncCheckpointTrigger,
```

在 `_openBook()`（第 421-451 行）建構 `ReaderScreen` 的具名參數列（第 425-438 行）的 `customFontsRepository: widget.customFontsRepository,` 之後新增：

```dart
              syncCheckpointTrigger: widget.syncCheckpointTrigger,
```

- [ ] **Step 4：執行測試，確認通過**

Run: `cd app && flutter test test/screens/library_screen_test.dart --plain-name "syncCheckpointTrigger 正確貫穿"`

Expected: PASS。

- [ ] **Step 5：組裝 `main()`**

修改 `app/lib/main.dart`：

在 import 區塊新增（`import 'sync/sync_checkpoint_trigger.dart';` 已於 Task 5 加入，這裡在其後接續新增）：

```dart
import 'sync/sync_engine.dart';
import 'sync/sync_metadata_repository.dart';
import 'screens/reading_position_conflict_dialog.dart';
```

在 `ElinkBookApp` 類別（Task 5 新增的 `final SyncCheckpointTrigger? syncCheckpointTrigger;` 欄位之後）新增：

```dart
  final GlobalKey<NavigatorState>? navigatorKey;
```

在其建構子（Task 5 新增的 `this.syncCheckpointTrigger,` 之後）新增：

```dart
    this.navigatorKey,
```

在 `_ElinkBookAppState.build()` 方法中，找到現有的：

```dart
    return MaterialApp(
      title: 'elinkBook',
      theme: themeData,
```

改為：

```dart
    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      title: 'elinkBook',
      theme: themeData,
```

在 `LibraryScreen(` 建構參數列（`main.dart` 內 `home: LibraryScreen(...)`，`customFontsRepository: widget.customFontsRepository,` 之後）新增：

```dart
        syncCheckpointTrigger: widget.syncCheckpointTrigger,
```

在 `main()` 函式本體中，找到現有的：

```dart
  final syncAccountRepository = SyncAccountRepository();
  final syncClient = SyncClient(accountRepository: syncAccountRepository);
  runApp(
```

改為：

```dart
  final syncAccountRepository = SyncAccountRepository();
  final syncClient = SyncClient(accountRepository: syncAccountRepository);
  // epic-8-sync Issue 6：Issue 4/5 只在測試中建構過 SyncEngine，這裡是
  // App 正式啟動流程第一次真正組裝一個會運作的實例（見
  // plan-issue-6.md Task 6「與 issues.md 的落差說明」）。navigatorKey
  // 用來在 SyncEngine 的閱讀位置衝突回呼中取得 BuildContext 顯示對話框
  // ——SyncEngine 本身刻意不依賴 Flutter widget 樹（見 sync_engine.dart
  // 既有設計，保持可離線單元測試），衝突對話框的顯示改由這裡的回呼
  // 橋接。
  final navigatorKey = GlobalKey<NavigatorState>();
  final syncMetadataRepository = SyncMetadataRepository(repository.database);
  final syncEngine = SyncEngine(
    db: repository.database,
    accountRepository: syncAccountRepository,
    metadataRepository: syncMetadataRepository,
    onReadingPositionConflict: (conflict) async {
      final context = navigatorKey.currentContext;
      // App 啟動極早期（尚未渲染出第一個畫面）理論上呼叫不到這裡——
      // checkpoint 觸發來源（Task 3-5）都發生在畫面已經渲染之後；仍防禦
      // 性處理 context 為 null 的情況，回傳 null 等同使用者關閉對話框
      // 未決定，SyncEngine 會照既有邏輯留待下次 checkpoint 重試，不會
      // 拋出例外或靜默覆蓋任一邊（FR-19）。
      if (context == null) return null;
      return showReadingPositionConflictDialog(context, conflict);
    },
  );
  final syncCheckpointTrigger = SyncCheckpointTrigger(
    isLoggedIn: syncAccountRepository.isLoggedIn,
    runCheckpoint: syncEngine.runCheckpoint,
  );
  runApp(
```

再找到既有的 `ElinkBookApp(` 建構呼叫（`syncClient: syncClient,` 這一行之後），新增：

```dart
      syncCheckpointTrigger: syncCheckpointTrigger,
      navigatorKey: navigatorKey,
```

- [ ] **Step 6：執行整份 `library_screen_test.dart`／`app_lifecycle_sync_test.dart`／`theme_test.dart`，確認無回歸**

Run: `cd app && flutter test test/screens/library_screen_test.dart test/app_lifecycle_sync_test.dart test/theme/theme_test.dart`

Expected: 全數 PASS。

- [ ] **Step 7：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`

Expected: `No issues found!`

- [ ] **Step 8：`flutter build apk --debug` 確認整個 App 可正常編譯**

本 Task 修改 `main()` 啟動流程本身，`main()` 沒有任何自動化測試直接覆蓋它（本專案既有慣例——`app/test/` 下沒有任何測試呼叫真正的 `main()` 函式，只有 `theme_test.dart` 直接建構 `ElinkBookApp` 繞過 `main()`），因此額外用一次 debug build 確認整條組裝鏈（`SyncMetadataRepository`／`SyncEngine`／`GlobalKey`／`showReadingPositionConflictDialog` 的具名參數與 import 都正確）能實際編譯成功，作為 Step 6-7 純靜態分析之外的最後一道防線。

Run: `cd app && flutter build apk --debug`

Expected: `Built build\app\outputs\flutter-apk\app-debug.apk`（建置成功，無編譯錯誤）。

- [ ] **Step 9：Commit**

```bash
git add app/lib/main.dart app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-8-sync): Issue 6 Task 6 — main() 正式組裝 SyncEngine 並貫穿 LibraryScreen/ReaderScreen"
```

---

## 與 spec.md／issues.md 的落差說明彙整

1. **Task 6 的 `main()` 正式組裝屬於必要但未逐字列出的工作**（詳見 Task 6 開頭「背景」說明）——issues.md「What to build」寫的是「三種 checkpoint 觸發來源接上 `SyncEngine.runCheckpoint()`」，若沒有 Task 6，Task 3-5 做出來的觸發機制會是「接到一個從未在正式 App 中被建構過的方法」，無法真正運作。
2. **併發鎖的實作位置**：spec.md／issues.md 皆明確要求「`SyncEngine` 內建單一執行鎖」，本計畫嚴格遵守，鎖定狀態（`_isSyncing`）只存在於 `SyncEngine` 內部（Task 1），`SyncCheckpointTrigger`（Task 2）不重複實作鎖、只負責登入閘門。
3. **5 分鐘計時器不做「偵測實際互動才重置」**：見 Global Constraints 說明，issues.md 原文只要求「閱讀中每 5 分鐘閒置計時器」觸發 checkpoint，未要求任何互動偵測邏輯，採最簡單的週期性 `Timer` 實作（YAGNI）。
4. **「未登入時三種觸發來源皆不呼叫 `runCheckpoint()`」只在 Task 2 集中測試一次，不在 Task 3/5 各自重複測試「未登入」情境**：三個觸發點（`ReaderScreen.dispose()`／`Timer`／`didChangeAppLifecycleState`）都是直接呼叫同一個 `SyncCheckpointTrigger.trigger()`，登入判斷邏輯完全相同、完全共用，Task 2 已經用假 callback 完整覆蓋「已登入才呼叫／未登入不呼叫／每次呼叫重新檢查登入狀態」三種情境；Task 3/5 只需驗證「有提供 trigger 時确實呼叫了 `.trigger()`」與「未提供 trigger 時不拋例外」，不需要在三個 UI 呼叫點重複測試同一段已被完整覆蓋的登入判斷邏輯，比照 spec.md「測試決策」推崇的「純函式接縫、避免重複測試同一段邏輯」既有原則。
5. **`LibraryScreen._openGroupFilteredView()`（既有的「依分類篩選」二次推入 `LibraryScreen` 的路徑）不貫穿 `syncCheckpointTrigger`**：檢視現有程式碼（`library_screen.dart` 第 466-485 行）會發現這個既有的遞迴推入路徑本來就沒有貫穿 `syncAccountRepository`／`syncClient` 這兩個既有的同步相關欄位（Issue 2 遺留的既有落差，非本 Issue 造成）；本計畫比照這個既有的既定行為，同樣不在這裡新增貫穿，避免用不相關的修正擴大本 Issue 的變更範圍（見 `CLAUDE.md`「Surgical Changes」）。若之後要修正，應該一次處理全部三個同步相關欄位，另開獨立的 bug 修復工單處理。
