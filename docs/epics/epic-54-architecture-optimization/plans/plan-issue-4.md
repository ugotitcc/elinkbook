# Issue 4：存取探測獨立於閱讀器引擎 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 把「存取探測」（`StorageAccessProbeResult`、`probeStorageAccess` 等 5 個符號）從 Foliate WebView 橋接檔 `foliate_native_bridge.dart` 搬到獨立的 `app/lib/storage/storage_access_probe.dart`，讓字型管理畫面與 `OpenBookFlow` 不必為了一個列舉而依賴整個 WebView 橋接；`ReaderScreen`（格式無關的唯一閱讀器入口）對 `foliate_native_bridge.dart` 的引用也隨之歸零（它對橋接檔唯一的 import 就是探測，已逐一確認沒有使用其他橋接符號）。

**Architecture：** 純 Dart 搬家，**名稱、行為、原生端、channel 名稱全部不變**。新檔自己宣告一個私有的 `MethodChannel('elinkbook/reader_resources_cache')`（`MethodChannel` 只是依名稱指向同一條原生通道的代理）；橋接檔不留 re-export，8 個引用檔的 import 一次改完；探測的測試群組整組搬到 `test/storage/`。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立的 `spec.md`，設計依據是 2026-10-01 `/grill-with-docs` 的決策，記錄於 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 4 設計決策」與 `CONTEXT.md`「存取探測」詞條。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **純搬家，無行為變動**：5 個符號的名稱（`StorageAccessProbeResult`、`ProbeStorageAccess`、`kStorageAccessProbeTimeout`、`probeStorageAccess`、`probeStorageAccessViaChannel`）、簽名、逾時值（3 秒）、四種結果、`ReaderConsoleLog` 診斷日誌格式 `[probeStorageAccess] <uri> → <結果>` 一律不變。
- **不動的東西**：原生 `ReaderResourceChannel.kt`（`probeUriAccess` 方法與其 KDoc）、channel 名稱 `elinkbook/reader_resources_cache`、方法名稱 `probeUriAccess`、橋接檔內 `cacheBookForServing`／`readContentUriAll` 使用的那一份 channel 宣告、`ReaderScreen` 對外建構參數（ADR 0007）、`kBookMetadataChannel` 的位置（審查 M-4 已決定不處理）、書籍與字型對探測結果的解讀規則（書籍只在 `permissionRevoked`／`fileNotFound` 顯示重新選取；字型在 `!= readable` 就顯示標示，兩者刻意不同，不統一）。
- **不留 re-export**：`foliate_native_bridge.dart` 搬走後不得再出現任何探測符號，也不得 `export` 新檔。
- **指令語法**：本計畫的指令是 bash 語法，用 Bash 工具（Git Bash）執行，路徑 `/c/Users/...` 與 `/tmp` 皆可用。Node 腳本內若讀寫檔案，用相對路徑（從 `app/` 起算）或 `C:/...` 形式。
- **Windows 環境**：`python` 在此環境不會實際執行（無輸出、檔案不變），不可用來編輯檔案；用 Edit 工具或 Node 腳本。多數原始檔是 CRLF 換行，Node 腳本以不含換行的字串當定位標記，不要依賴換行字元。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動實際觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（耗時約 6 分鐘，用 `run_in_background`）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：直接 TDD；程式審查先出報告（存於 `reviews/`，該目錄 gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。

## Review Focus

這是純搬家，最可能咬到使用者的是「搬完看似沒問題、實際探測失效」的情況（依可能性排序），每一條都有對應驗證：

1. **注入機制必須仍然有效，且兩個畫面吃到的是同一個頂層變數。** `ReaderScreen` 以 `(uri) => probeStorageAccess(uri)` 呼叫、`FontManagementScreen` 直接呼叫；widget 測試覆寫 `probeStorageAccess` 後兩者都必須吃到假結果。若 import 搬錯（例如測試覆寫的是新檔、畫面卻還在讀舊檔的變數），測試會靜默地走真實 channel 並回傳 `unknownError`。→ Task 2 搬遷後，`font_management_screen_test`（28 處引用）與 `reader_screen_test`（31 處引用）既有探測測試必須維持綠燈；它們是這條的驗證。
2. **channel 名稱與方法名打錯就永遠回 `unknownError`。** 新檔重新宣告了 channel 字串。→ Task 1 搬過去的測試直接對 channel 名稱 `elinkbook/reader_resources_cache` 註冊 mock，並斷言收到的方法名為 `probeUriAccess`。
3. **預設值接線：`probeStorageAccess` 預設必須指向 `probeStorageAccessViaChannel`。** → Task 1 搬過去的「`probeStorageAccess` 預設指向 `probeStorageAccessViaChannel`」測試。
4. **橋接檔不得殘留舊符號、也不得留下孤兒 import。** 殘留會造成「兩份定義、各測各的」。→ Task 2 的 grep 與 `flutter analyze`。
5. **`ReaderConsoleLog` 診斷日誌仍要寫入**（真機回報時對照成因用）。→ Task 1 搬過去的「結果寫入 ReaderConsoleLog」測試；另確認 `reader_console_log.dart` 不 import `storage/`（避免循環依賴）。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/storage/storage_access_probe.dart` | 新增 | 5 個探測符號＋私有 channel 宣告 |
| `app/test/storage/storage_access_probe_test.dart` | 新增 | 從橋接測試搬來的探測測試群組（13 個）＋釘住逾時常數的 1 個新測試，共 14 個 |
| `app/lib/reader/foliate_native_bridge.dart` | 修改 | 刪除探測區塊與因此變成孤兒的 import |
| `app/test/reader/foliate_native_bridge_test.dart` | 修改 | 刪除探測測試群組與孤兒 import |
| `app/lib/screens/reader_screen.dart`、`app/lib/screens/font_management_screen.dart`、`app/lib/reader/open_book_flow.dart` | 修改 | import 改指向新檔 |
| `app/test/screens/font_management_screen_test.dart`、`app/test/screens/reader_screen_test.dart`、`app/test/reader/open_book_flow_test.dart` | 修改 | import 改指向新檔（`reader_screen_test` 是整個 import 橋接檔，需另補一行） |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 開發記錄、狀態 |

---

### Task 0：提交計畫、建立 worktree

**Files：**
- Commit：本計畫檔與 `issues.md` 狀態更新（在 `main` 上，純文件）
- 建立 worktree：`.worktrees/epic-54-issue-4-storage-access-probe`（`.worktrees/` 已 gitignore）

**Interfaces：**
- Consumes：無。
- Produces：後續 Task 都在 worktree 的分支 `epic-54/issue-4-storage-access-probe` 上進行與提交。

- [x] **Step 1：在 `main` 提交計畫，並把 Issue 4 標為進行中**

先把 `docs/epics/epic-54-architecture-optimization/issues.md` 的 Issue 4 狀態從「🟡 已設計，待寫計畫」改為「🟡 進行中（`plans/plan-issue-4.md`）」（與 Issue 1 的做法一致：進入計畫執行就標進行中），再提交：

```bash
cd /c/Users/fycdc/AI/elinkBook
git status --short
git add docs/epics/epic-54-architecture-optimization/plans/plan-issue-4.md docs/epics/epic-54-architecture-optimization/issues.md
git commit -m "docs(epic-54): Issue 4 實作計畫，標為進行中

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`git status --short` 在 add 之前只有這兩個檔案。

- [ ] **Step 2：推送 `main`（對外動作，須先取得使用者確認，已暫緩）**

**執行前先向使用者確認，不得自動推送。** 確認後：

```bash
git push origin main
```

若 push 被拒絕（遠端有他人新 commit），**不要強制推送**：先 `git pull --no-rebase --no-edit`（merge 而非 rebase，避免改寫 worktree 分支的基底），再重新 `git push origin main`。

- [x] **Step 3：建立 worktree 與分支**

```bash
cd /c/Users/fycdc/AI/elinkBook
git worktree add .worktrees/epic-54-issue-4-storage-access-probe -b epic-54/issue-4-storage-access-probe main
cd .worktrees/epic-54-issue-4-storage-access-probe/app
flutter pub get
```

Expected：`Preparing worktree (new branch 'epic-54/issue-4-storage-access-probe')`。之後所有指令都在這個 worktree 的 `app/` 下執行。

---

### Task 1：新增 `storage_access_probe.dart` 與搬遷後的測試

這一步只「新增」，橋接檔與所有現有引用都還沒動，所以整個專案仍可編譯；新舊兩份定義暫時並存（沒有任何檔案同時 import 兩者）。

**Files：**
- Create: `app/lib/storage/storage_access_probe.dart`
- Create: `app/test/storage/storage_access_probe_test.dart`

**Interfaces：**
- Consumes：`ReaderConsoleLog.add(String)`（`app/lib/reader/reader_console_log.dart`，靜態方法；`ReaderConsoleLog.clear()` 與 `ReaderConsoleLog.entries.value` 供測試）。
- Produces（Task 2 依賴，名稱與型別必須與現有橋接檔一字不差）：

```dart
enum StorageAccessProbeResult { readable, permissionRevoked, fileNotFound, unknownError }
typedef ProbeStorageAccess = Future<StorageAccessProbeResult> Function(String uri);
const Duration kStorageAccessProbeTimeout = Duration(seconds: 3);
ProbeStorageAccess probeStorageAccess = probeStorageAccessViaChannel;
@visibleForTesting
Future<StorageAccessProbeResult> probeStorageAccessViaChannel(String uri, {Duration timeout = kStorageAccessProbeTimeout});
```

- [x] **Step 1：寫失敗的測試（把現有探測測試群組搬過來）**

建立 `app/test/storage/storage_access_probe_test.dart`，內容是 `app/test/reader/foliate_native_bridge_test.dart` 第 202–301 行的 `group('probeStorageAccessViaChannel（…）'` 原樣搬過來，只換 import 與檔頭：

```dart
import 'dart:async';

import 'package:elinkbook/reader/reader_console_log.dart';
import 'package:elinkbook/storage/storage_access_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('probeStorageAccessViaChannel（epic-15-storage-permission Issue 1）', () {
    const channel = MethodChannel('elinkbook/reader_resources_cache');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    for (final entry in {
      'readable': StorageAccessProbeResult.readable,
      'permissionRevoked': StorageAccessProbeResult.permissionRevoked,
      'fileNotFound': StorageAccessProbeResult.fileNotFound,
      'unknownError': StorageAccessProbeResult.unknownError,
    }.entries) {
      test('原生回傳 "${entry.key}" 對應到 ${entry.value}', () async {
        MethodCall? captured;
        messenger.setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return entry.key;
        });

        final result = await probeStorageAccessViaChannel(
            'content://com.example.provider/book.epub');

        expect(result, entry.value);
        expect(captured!.method, 'probeUriAccess');
        expect(captured!.arguments,
            {'uri': 'content://com.example.provider/book.epub'});
      });
    }

    test('無法辨識的代碼回傳 unknownError', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => 'somethingNew');
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('原生回傳 null 時回傳 unknownError', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('原生回傳非字串（型別不符）回傳 unknownError，不拋出 TypeError', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => 42);
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('PlatformException 回傳 unknownError', () async {
      messenger.setMockMethodCallHandler(
          channel, (call) async => throw PlatformException(code: 'boom'));
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('通道沒有原生實作（MissingPluginException）回傳 unknownError',
        () async {
      // 不註冊任何 handler：對應 widget test／無原生實作的環境。
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('原生逾時未回應時回傳 unknownError', () async {
      final never = Completer<String>();
      messenger.setMockMethodCallHandler(channel, (call) => never.future);
      expect(
        await probeStorageAccessViaChannel('content://x/a.epub',
            timeout: const Duration(milliseconds: 50)),
        StorageAccessProbeResult.unknownError,
      );
    });

    test('非 content:// 輸入不呼叫通道，直接回傳 unknownError', () async {
      var called = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        called = true;
        return 'readable';
      });
      expect(await probeStorageAccessViaChannel('/data/user/0/app/book.epub'),
          StorageAccessProbeResult.unknownError);
      expect(called, isFalse);
    });

    test('結果寫入 ReaderConsoleLog', () async {
      ReaderConsoleLog.clear();
      messenger.setMockMethodCallHandler(
          channel, (call) async => 'permissionRevoked');
      await probeStorageAccessViaChannel('content://x/a.epub');
      expect(
        ReaderConsoleLog.entries.value.last,
        contains('content://x/a.epub → permissionRevoked'),
      );
    });

    test('probeStorageAccess 預設指向 probeStorageAccessViaChannel', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => 'readable');
      expect(await probeStorageAccess('content://x/a.epub'),
          StorageAccessProbeResult.readable);
    });
  });

  // 新增（計畫審查 M-1）：CONTEXT.md「存取探測」把逾時 3 秒寫成領域事實，
  // 這個常數原本只作為預設參數存在、沒有任何直接斷言。
  test('kStorageAccessProbeTimeout 為 3 秒', () {
    expect(kStorageAccessProbeTimeout, const Duration(seconds: 3));
  });
}
```

- [x] **Step 2：執行測試確認失敗**

Run：`flutter test test/storage/storage_access_probe_test.dart`
Expected：編譯失敗，`Target of URI doesn't exist: 'package:elinkbook/storage/storage_access_probe.dart'`。

- [x] **Step 3：寫實作（逐字搬自橋接檔，只改 channel 宣告與註解中的引用）**

建立 `app/lib/storage/storage_access_probe.dart`：

```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;

import '../reader/reader_console_log.dart';

/// 背景任務佇列的 method channel，原生端 `ReaderResourceChannel.kt` 的
/// `probeUriAccess` 掛在這條通道上。`MethodChannel` 物件只是依名稱字串指向
/// 同一條平台通道的輕量代理，這裡與 `foliate_native_bridge.dart` 內的同名
/// 宣告是兩個各自獨立、但指向同一條原生通道的物件實例，皆可正常運作。
const _readerResourcesCacheChannel =
    MethodChannel('elinkbook/reader_resources_cache');

/// `content://` URI 存取探測結果（epic-15-storage-permission Issue 1；
/// epic-54 Issue 4 起獨立於閱讀器引擎，見 CONTEXT.md「存取探測」）。
/// 對應原生 `ReaderResourceChannel.probeUriAccess` 回傳的四個代碼字串。
enum StorageAccessProbeResult {
  /// 可以開啟輸入串流。
  readable,

  /// 原生端捕捉到 `SecurityException`：App 對此 URI 的存取權限已失效。
  permissionRevoked,

  /// 原生端捕捉到 `FileNotFoundException`，或內容提供者回傳 null 串流：
  /// 原始檔案可能已被移動、改名或刪除。
  fileNotFound,

  /// 其他例外、逾時、通道不存在，或無法辨識的代碼。
  unknownError,
}

typedef ProbeStorageAccess = Future<StorageAccessProbeResult> Function(
    String uri);

/// 探測原生呼叫的逾時上限。有缺陷的第三方／雲端文件提供者可能讓
/// `openInputStream` 卡住，逾時一律視為 [StorageAccessProbeResult.unknownError]，
/// 閱讀器退回通用錯誤文字，不會永遠停在載入中。
const Duration kStorageAccessProbeTimeout = Duration(seconds: 3);

/// 探測 [uri] 是否仍可讀取（epic-15-storage-permission Issue 1）。
///
/// 可覆寫的頂層函式變數（比照 `cacheBookForServing` 既有慣例），讓 widget
/// test 注入假結果，不需要原生實作。只在開書失敗後呼叫一次，不做背景輪詢。
ProbeStorageAccess probeStorageAccess = probeStorageAccessViaChannel;

/// [probeStorageAccess] 的預設實作：呼叫背景任務佇列通道的
/// `probeUriAccess`。非 `content://` 輸入不呼叫原生。每次結果都寫入
/// [ReaderConsoleLog]，供真機回報時對照 design.md 的成因假說。
@visibleForTesting
Future<StorageAccessProbeResult> probeStorageAccessViaChannel(
  String uri, {
  Duration timeout = kStorageAccessProbeTimeout,
}) async {
  if (!uri.startsWith('content://')) {
    return StorageAccessProbeResult.unknownError;
  }
  StorageAccessProbeResult result;
  try {
    final code = await _readerResourcesCacheChannel
        .invokeMethod<String>('probeUriAccess', {'uri': uri})
        .timeout(timeout);
    result = StorageAccessProbeResult.values.asNameMap()[code] ??
        StorageAccessProbeResult.unknownError;
  } catch (_) {
    // 預期會遇到 TimeoutException（原生卡住）、PlatformException、
    // MissingPluginException（無原生實作的環境），以及原生回傳非字串時
    // invokeMethod<String> 內部轉型拋出的 TypeError（屬於 Error 而非
    // Exception）。一律退回 unknownError：本函式保證永不拋出例外，閱讀器
    // 最壞情況只是顯示通用錯誤文字（審查 I-2）。
    result = StorageAccessProbeResult.unknownError;
  }
  ReaderConsoleLog.add('[probeStorageAccess] $uri → ${result.name}');
  return result;
}
```

- [x] **Step 4：執行測試確認通過，並確認沒有循環依賴**

```bash
flutter test test/storage/storage_access_probe_test.dart
grep -n "^import" lib/reader/reader_console_log.dart
```

Expected：14 個測試 PASS（4 個結果對應＋9 個其餘＋1 個逾時常數）；`reader_console_log.dart` 只 import `package:flutter/foundation.dart`，沒有 `storage/`（Review Focus 5 的循環依賴檢查）。

- [x] **Step 5：analyze 並提交**

```bash
flutter analyze
git add lib/storage/storage_access_probe.dart test/storage/storage_access_probe_test.dart
git commit -m "feat(storage): epic-54 Issue 4 新增 storage_access_probe.dart 與搬遷後的探測測試

橋接檔與既有引用尚未切換，新舊定義暫時並存，下一個 commit 切換並刪除舊定義。

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`No issues found!`。

---

### Task 2：切換所有引用、刪除橋接檔裡的舊定義

**Files：**
- Modify: `app/lib/reader/foliate_native_bridge.dart`、`app/test/reader/foliate_native_bridge_test.dart`
- Modify: `app/lib/screens/reader_screen.dart`、`app/lib/screens/font_management_screen.dart`、`app/lib/reader/open_book_flow.dart`
- Modify: `app/test/screens/font_management_screen_test.dart`、`app/test/screens/reader_screen_test.dart`、`app/test/reader/open_book_flow_test.dart`

**Interfaces：**
- Consumes：Task 1 的 5 個符號（新位置 `package:elinkbook/storage/storage_access_probe.dart`）。
- Produces：橋接檔不再含任何探測符號。

- [x] **Step 1：切換 3 個 lib 檔的 import**

1. `app/lib/screens/reader_screen.dart`，把
```dart
import '../reader/foliate_native_bridge.dart'
    show StorageAccessProbeResult, probeStorageAccess;
```
換成
```dart
import '../storage/storage_access_probe.dart'
    show StorageAccessProbeResult, probeStorageAccess;
```

2. `app/lib/screens/font_management_screen.dart`，同樣把
```dart
import '../reader/foliate_native_bridge.dart'
    show StorageAccessProbeResult, probeStorageAccess;
```
換成
```dart
import '../storage/storage_access_probe.dart'
    show StorageAccessProbeResult, probeStorageAccess;
```

3. `app/lib/reader/open_book_flow.dart`，把 `import 'foliate_native_bridge.dart' show StorageAccessProbeResult;` 換成
```dart
import '../storage/storage_access_probe.dart' show StorageAccessProbeResult;
```

- [x] **Step 2：切換 3 個測試檔的 import**

1. `app/test/screens/font_management_screen_test.dart`，把
```dart
import 'package:elinkbook/reader/foliate_native_bridge.dart'
    show ProbeStorageAccess, StorageAccessProbeResult, probeStorageAccess;
```
換成
```dart
import 'package:elinkbook/storage/storage_access_probe.dart'
    show ProbeStorageAccess, StorageAccessProbeResult, probeStorageAccess;
```

2. `app/test/reader/open_book_flow_test.dart`，把
```dart
import 'package:elinkbook/reader/foliate_native_bridge.dart'
    show StorageAccessProbeResult;
```
換成
```dart
import 'package:elinkbook/storage/storage_access_probe.dart'
    show StorageAccessProbeResult;
```

3. `app/test/screens/reader_screen_test.dart`：這個檔案是**整個** import 橋接檔（沒有 `show`，因為還用到 `cacheBookForServing` 等），所以**保留**那行 `import 'package:elinkbook/reader/foliate_native_bridge.dart';`，並在它的下一行新增：
```dart
import 'package:elinkbook/storage/storage_access_probe.dart';
```

- [x] **Step 3：刪除橋接檔的探測區塊**

用 Node 腳本（不依賴換行字元）刪除 `foliate_native_bridge.dart` 中從探測列舉的 doc comment 起、到下一個函式 `loadCustomFontBytes` 的 doc comment 之前的整段：

```bash
node -e '
const fs=require("fs");
const p="lib/reader/foliate_native_bridge.dart";
let s=fs.readFileSync(p,"utf8");
const start=s.indexOf("/// epic-15-storage-permission Issue 1：`content://` URI 存取探測結果。");
const end=s.indexOf("/// 讀取自訂字型的位元組（`content://` URI，ADR 0021 決策");
if(start<0||end<0||end<=start) throw new Error("標記找不到："+start+","+end);
s=s.slice(0,start)+s.slice(end);
fs.writeFileSync(p,s);
console.log("removed",end-start,"chars");
'
```

Expected：印出 `removed N chars`（約 2,000–2,500）。

- [x] **Step 4：刪除橋接測試的探測群組**

```bash
node -e '
const fs=require("fs");
const p="test/reader/foliate_native_bridge_test.dart";
let s=fs.readFileSync(p,"utf8");
const start=s.indexOf("  group(\u0027probeStorageAccessViaChannel（epic-15-storage-permission Issue 1）\u0027");
const end=s.indexOf("  group(\u0027cacheFileExtension\u0027");
if(start<0||end<0||end<=start) throw new Error("標記找不到："+start+","+end);
s=s.slice(0,start)+s.slice(end);
fs.writeFileSync(p,s);
console.log("removed",end-start,"chars");
'
```

Expected：印出 `removed N chars`（約 3,500–4,000）。

- [x] **Step 5：清理孤兒 import 並確認沒有殘留**

```bash
flutter analyze
grep -rn "probeStorageAccess\|StorageAccessProbeResult\|ProbeStorageAccess\|kStorageAccessProbeTimeout" lib test --include="*.dart" | grep -v "lib/storage/storage_access_probe.dart\|test/storage/storage_access_probe_test.dart" | grep "foliate_native_bridge"
```

Expected：
- `flutter analyze` 若回報 `unused_import`：橋接檔可能是 `package:flutter/foundation.dart show visibleForTesting`、`reader_console_log.dart`、`dart:async`；橋接測試可能是 `dart:async`、`reader_console_log.dart`。**逐一確認該 import 在檔內確實再無使用後才移除**（`dart:async`／`visibleForTesting` 可能仍被橋接檔其他部分使用，以 analyze 的結果為準，不要憑印象刪）。最後必須 `No issues found!`。
- grep 無輸出（沒有任何地方還透過橋接檔引用探測符號）。

另外檢查註解裡是否還有指向舊位置的文字說明：

```bash
grep -rn "foliate_native_bridge" lib --include="*.dart" | grep -i "probe\|探測"
```

若有，把註解改指向 `storage/storage_access_probe.dart`（只改註解文字）。

- [x] **Step 6：執行觸及的測試檔**

```bash
flutter test test/storage test/reader/foliate_native_bridge_test.dart test/reader/open_book_flow_test.dart test/screens/font_management_screen_test.dart test/screens/reader_screen_test.dart
```

Expected：全部 PASS。其中兩個畫面測試的探測相關案例（`font_management_screen_test` 的「儲存權限失效標示與重新連結」群組、`reader_screen_test` 的「開書失敗的存取探測」與「重新選取檔案」群組）必須維持綠燈，這是 Review Focus 1 的驗證；若這些測試出現「走了真實 channel、結果變 unknownError」的失敗，代表某處 import 搬錯了，回頭檢查 Step 1、2。

- [x] **Step 7：提交**

```bash
node tool/check_l10n_hardcoded_strings.js
git add -A lib test
git commit -m "refactor(storage): epic-54 Issue 4 存取探測獨立於閱讀器引擎，橋接檔不再含探測符號

reader_screen／font_management_screen／open_book_flow 與 4 個測試檔改 import
新位置；刪除橋接檔與橋接測試中的舊定義。純搬家，無行為變動。

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`check_l10n_hardcoded_strings.js` 兩行 PASS。

---

### Task 3：開發記錄、全套測試、程式審查、準備發 PR

**Files：**
- Modify: `docs/epics/epic-54-architecture-optimization/epic.md`（開發記錄）
- Modify: `docs/epics/epic-54-architecture-optimization/issues.md`（Issue 4 狀態）
- Modify: `docs/epics.md`（第 65 行，即表格編號 55 的那一列）

**Interfaces：**
- Consumes：Task 1–2 的實際測試數字。
- Produces：可發 PR 的分支。

- [x] **Step 1：請求程式審查**

使用 `superpowers:requesting-code-review`，審查範圍為本分支相對 Task 0 提交計畫之後的 commit 範圍。審查重點請明確寫給審查員：(a) 純搬家無行為差異（對照 `main` 的橋接檔，新檔逐字相同，只有 channel 宣告與註解不同）；(b) 5 個符號在 `lib/`、`test/` 沒有殘留舊定義；(c) 新檔 channel 名稱 `elinkbook/reader_resources_cache` 與方法名 `probeUriAccess` 與原生 `ReaderResourceChannel.kt` 一致；(d) 沒有循環依賴（`storage/` → `reader/reader_console_log.dart`，後者不 import `storage/`）；(e) 孤兒 import 是否清乾淨。審查報告存於 `docs/epics/epic-54-architecture-optimization/reviews/review-code-issue-4.md`（gitignore，不進版控）；審查者只出報告、不直接改程式；依報告修訂前須先由使用者決定。審查摘要要寫進 `epic.md`。

- [x] **Step 2：全套測試（整張計畫最後一個 Task，CLAUDE.md 規定此時跑一次）**

```bash
flutter test
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

全套約 6 分鐘，請用 `run_in_background`。Expected：`All tests passed!`；`No issues found!`；兩行 PASS。基準：Issue 3 合併後為 3275 通過、1 略過；本 Issue 是純搬家，13 個測試只是換檔案，另新增 1 個逾時常數測試，所以預期 **3276 通過、1 略過**（只多 1 個）。

- [x] **Step 3：寫開發記錄**

在 `epic.md`「開發記錄」末尾新增（數字以實際結果為準）：

```markdown
**YYYY-MM-DD Issue 4 實作完成**：新增 `app/lib/storage/storage_access_probe.dart`，把 `StorageAccessProbeResult`、`ProbeStorageAccess`、`kStorageAccessProbeTimeout`、`probeStorageAccess`、`probeStorageAccessViaChannel` 從 `foliate_native_bridge.dart` 搬出（名稱不變、不留 re-export）；新檔自己宣告私有 `MethodChannel('elinkbook/reader_resources_cache')`，原生端與 channel 名稱不動。`reader_screen`／`font_management_screen`／`open_book_flow` 與 4 個測試檔改 import；探測測試群組（13 個）自 `foliate_native_bridge_test` 搬到 `test/storage/storage_access_probe_test.dart`，另新增 1 個釘住逾時 3 秒的測試。純搬家，無行為變動；`ReaderScreen` 對 `foliate_native_bridge.dart` 的引用歸零（它對橋接檔唯一的 import 就是探測）；M-4（`kBookMetadataChannel` 位置）依設計不處理；書籍與字型對探測結果的解讀差異依設計不統一。驗證：全套 `flutter test` N 通過、1 略過（Issue 3 合併後基準 3275＋1 個新增測試）；`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS。程式審查摘要：…
```

並把 `docs/epics.md` 第 65 行（表格編號 55）改為「…Issue 4 實作完成待發 PR…」。`issues.md` 的 Issue 4 狀態已在 Task 0 標為「🟡 進行中」，這裡維持不變，待 PR 合併後再改為「🟢 已合併（PR #N）」。

- [ ] **Step 4：提交並準備發 PR**

```bash
cd /c/Users/fycdc/AI/elinkBook/.worktrees/epic-54-issue-4-storage-access-probe
git add docs/epics.md docs/epics/epic-54-architecture-optimization/epic.md docs/epics/epic-54-architecture-optimization/issues.md
git commit -m "docs(epic-54): Issue 4 實作完成，全套測試通過，準備發 PR

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

發 PR 前須經使用者確認（對外動作）；PR 描述結尾加 `🤖 Generated with [Claude Code](https://claude.com/claude-code)`。PR 合併後比照 Issue 1、3、5：在 `epic.md` 補合併記錄、`issues.md` 標為「🟢 已合併（PR #N）」、更新 `docs/epics.md`，並移除 worktree 與分支（本機＋遠端）。
