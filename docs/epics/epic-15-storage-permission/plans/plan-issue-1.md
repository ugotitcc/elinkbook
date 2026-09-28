# Epic 15 Issue 1：開書失敗時分辨「權限失效／找不到檔案」並顯示對應說明 — 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `content://` 書籍開書失敗時，閱讀器探測一次檔案可讀性。依結果顯示「存取權限已失效」或「找不到原始檔案」的說明；其他情況維持原本的通用錯誤文字。

**Architecture:**
- 原生 `ReaderResourceChannel` 新增 `probeUriAccess`：開啟輸入串流後立即關閉，依例外類型回傳四個代碼字串之一，走背景任務佇列通道。
- Dart 端在 `foliate_native_bridge.dart` 包成可覆寫的頂層函式變數 `probeStorageAccess`，含 3 秒逾時與例外防護。
- `ReaderScreen._handleError` 在書籍是 `content://` 時先探測、維持載入指示器，探測完才切到錯誤視圖。錯誤視圖依型別化欄位 `_probeResult` 分流顯示文字。

**Tech Stack:** Flutter／Dart 3、Kotlin（Android `ContentResolver`）、`flutter_test`、`flutter gen-l10n`（ARB）。

**Spec:** [`../spec.md`](../spec.md)（「存取探測」「閱讀器錯誤視圖」兩段）、[`../issues.md`](../issues.md) Issue 1

## Global Constraints

- 跨端契約逐字照 spec：
  - 通道 `elinkbook/reader_resources_cache`（背景任務佇列）、方法 `probeUriAccess`、引數 `{'uri': String}`。
  - 回傳 `String`，只能是 `readable`／`permissionRevoked`／`fileNotFound`／`unknownError` 之一。
- Dart 型別名稱固定為：`StorageAccessProbeResult { readable, permissionRevoked, fileNotFound, unknownError }`、`typedef ProbeStorageAccess`、頂層變數 `probeStorageAccess`。
- 探測逾時 3 秒；逾時、`PlatformException`、`MissingPluginException`、無法辨識的代碼，以及任何其他例外（例如原生回傳非字串導致的 `TypeError`），一律視為 `unknownError`。`probeStorageAccessViaChannel` 保證永不拋出例外。
- `ReaderScreen` 對探測函式本身也要防呆：即使注入的 `probeStorageAccess` 拋出例外，也要退回 `unknownError` 並切到錯誤視圖，絕不能停在載入中（第一次錯誤進來時逾時計時器已經取消，停住就永遠不會逾時）。
- 非 `content://` 的輸入不呼叫原生，直接回傳 `unknownError`。
- 原生端對後三類以 `Log.w`（警告等級，不可用 `Log.d`）記錄 URI 與例外類別；Dart 端每次探測結果都寫入 `ReaderConsoleLog`。
- **既有 `cacheBookForServing`／`readContentUriAll`／`readCustomFontBytes` 的行為與回傳契約完全不變。**
- `ReaderScreen` 只在「載入中、目前生效路徑（`_activeFilePath`）是 `content://`、錯誤來自 `onError`」時探測。開書逾時、不支援的格式、非 `content://` 的書，都不探測。
- 探測結果必須存成型別化欄位 `StorageAccessProbeResult? _probeResult`，不可只轉成錯誤字串（Issue 2 依它決定是否顯示按鈕）。
- 說明文字仍掛在既有的 `Key('reader_error_text')` 上；本 Issue **不加**重新選取按鈕。
- 在地化：新增 `readerStoragePermissionRevokedMessage`、`readerStorageFileNotFoundMessage` 兩個 key，四份 ARB 都要補：
  - `app_zh_TW.arb`：範本，含 `@key` 說明。
  - `app_zh.arb`：中文退路，內容同正體中文。
  - `app_zh_CN.arb`、`app_en.arb`。

  改完執行 `flutter gen-l10n`，生成的 `app_localizations*.dart` 已納入版控，要一起提交。
- 程式碼註解使用正體中文，並標註 `epic-15-storage-permission Issue 1`。
- 每個 Task 只跑觸及的測試檔；最後一個 Task 跑一次完整 `flutter test`。`flutter analyze` 必須是 `No issues found!`。
- 所有指令都在 `app/` 目錄下執行（除非另外註明）。

## Review Focus

1. **探測期間底層連續回報錯誤**：探測一次就好，而且在探測完成之前畫面維持載入指示器，不可閃出通用錯誤再改成分類說明（E-Ink 殘影）。由 Task 3 的「連續兩次 onError 只探測一次、期間仍是載入中」測試釘住。
2. **探測期間使用者離開閱讀器**：結果回來時 State 已 dispose，不可呼叫 `setState` 拋例外。由 Task 3 的「探測中離開不拋例外」測試釘住。
3. **探測期間開書其實成功了**（`onPageRendered` 晚到）：探測結果回來時狀態已不是載入中，不可把已經顯示的書蓋成錯誤畫面。由 Task 3 的「探測中 onPageRendered 先到」測試釘住。
4. **原生通道不存在或卡住**：widget test 與部分測試環境沒有原生實作（`MissingPluginException`），有缺陷的文件提供者可能讓呼叫一直不回來。兩種情況都必須退回通用錯誤，不能讓閱讀器永遠轉圈。由 Task 1 的 `MissingPluginException`、逾時兩個單元測試釘住。
5. **探測函式本身拋出例外**：第一次錯誤進來時已經取消了逾時計時器，如果探測函式拋例外、錯誤畫面沒切出來，閱讀器會永遠轉圈。`_probeAccessAndShowError` 用 try/catch 退回 `unknownError`。由 Task 3 的「探測函式拋出例外」測試釘住（審查 I-1）。
6. **探測中觸發開書逾時**：第一次錯誤進來時就取消了逾時計時器；`_handleOpenBookTimeout` 另外加上探測中直接略過的防護。由 Task 3 的「探測中推進 31 秒仍是載入中」測試釘住。

---

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/foliate_native_bridge.dart` | Modify | 新增 `StorageAccessProbeResult`、`ProbeStorageAccess`、`probeStorageAccess`、`probeStorageAccessViaChannel` |
| `app/test/reader/foliate_native_bridge_test.dart` | Modify | 探測包裝的單元測試 |
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt` | Modify | 新增 `probeUriAccess` 分支與 class doc 第 5 點 |
| `app/lib/screens/reader_screen.dart` | Modify | `_probeResult`／`_isProbingAccess`、`_handleError` 探測流程、`_handleOpenBookTimeout` 防護、錯誤視圖分流 |
| `app/test/screens/reader_screen_test.dart` | Modify | 探測流程與錯誤分流的 widget test |
| `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb` | Modify | 兩個新 key |
| `app/lib/l10n/app_localizations*.dart` | Regenerate | `flutter gen-l10n` 產物 |

---

### Task 0：建立工作分支（worktree）

- [ ] **Step 1：建立 worktree**

在儲存庫根目錄執行：

```bash
git worktree add .worktrees/epic-15-issue-1 -b epic-15/issue-1 main
```

之後所有 Task 都在 `.worktrees/epic-15-issue-1` 內進行。

---

### Task 1：Dart 端探測包裝 `probeStorageAccess`

**Files:**
- Modify: `app/lib/reader/foliate_native_bridge.dart`（import 區；在 `loadCustomFontBytes` 之前新增一段）
- Test: `app/test/reader/foliate_native_bridge_test.dart`

**Interfaces:**
- Consumes: 既有 `_readerResourcesCacheChannel`（`MethodChannel('elinkbook/reader_resources_cache')`）、`ReaderConsoleLog.add(String)`
- Produces（Task 3、Issue 2、Issue 3 使用）：

  ```dart
  enum StorageAccessProbeResult { readable, permissionRevoked, fileNotFound, unknownError }
  typedef ProbeStorageAccess = Future<StorageAccessProbeResult> Function(String uri);
  ProbeStorageAccess probeStorageAccess; // 預設 = probeStorageAccessViaChannel
  const Duration kStorageAccessProbeTimeout; // 3 秒
  @visibleForTesting
  Future<StorageAccessProbeResult> probeStorageAccessViaChannel(String uri, {Duration timeout});
  ```

- [ ] **Step 1：寫失敗的測試**

在 `foliate_native_bridge_test.dart` 的 `main()` 內，既有 `group('cacheFileExtension', ...)` 之前新增：

```dart
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
```

在檔案頂端 import 區補上：

```dart
import 'dart:async';

import 'package:elinkbook/reader/reader_console_log.dart';
```

（`package:flutter/services.dart` 已經 import，`PlatformException`、`MethodChannel`、`MethodCall` 都可以直接使用。）

- [ ] **Step 2：執行測試，確認失敗**

Run: `flutter test test/reader/foliate_native_bridge_test.dart`
Expected: 編譯錯誤，訊息為 `Undefined name 'StorageAccessProbeResult'`、`The function 'probeStorageAccessViaChannel' isn't defined`。

- [ ] **Step 3：最小實作**

`foliate_native_bridge.dart` import 區調整為：

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_font.dart';
import 'custom_font.dart';
import 'foliate_bridge_codec.dart';
import 'font_download_catalog.dart';
import 'reader_console_log.dart';
```

在 `/// 讀取自訂字型的位元組` 那段（`loadCustomFontBytes`）之前新增：

```dart
/// epic-15-storage-permission Issue 1：`content://` URI 存取探測結果。
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
/// 可覆寫的頂層函式變數（比照 [cacheBookForServing] 既有慣例），讓 widget
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

說明：`asNameMap()[null]` 回傳 null，所以原生回傳 null 也會落到 `unknownError`。

- [ ] **Step 4：執行測試，確認通過**

Run: `flutter test test/reader/foliate_native_bridge_test.dart`
Expected: All tests passed，包含新增的 12 個與既有測試。

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5：Commit**

```bash
git add lib/reader/foliate_native_bridge.dart test/reader/foliate_native_bridge_test.dart
git commit -m "feat(reader): 新增 content:// 存取探測 probeStorageAccess（epic-15 Issue 1）"
```

---

### Task 2：原生 `probeUriAccess`

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`（import 區、class doc、`onMethodCall` 的 `when`）

**Interfaces:**
- Consumes: 無
- Produces: `elinkbook/reader_resources_cache` 通道上的 `probeUriAccess`，引數 `{'uri': String}`，回傳四個代碼字串之一（Task 1 已定義 Dart 端對應）。

原生方法沒有 Dart 端自動化測試（`flutter test` 碰不到 `ContentResolver`），以編譯驗證加上 Task 4 的真機驗證取代。

- [ ] **Step 1：新增 import**

在 `import java.io.FileOutputStream` 之前新增：

```kotlin
import java.io.FileNotFoundException
```

- [ ] **Step 2：class doc 補第 5 點**

在 class doc 第 4 點（`readContentUriAll`）那段結尾、`取代原本 FoliateEpubReaderView.kt` 那段之前插入：

```kotlin
 * 5. `probeUriAccess`（epic-15-storage-permission Issue 1）：探測
 *    `content://` URI 是否仍可讀取——開啟輸入串流後立即關閉、不讀取
 *    內容，依例外類型回傳 `readable`／`permissionRevoked`／`fileNotFound`／
 *    `unknownError` 四個代碼字串之一（原生端不回傳使用者可見文字，由
 *    Dart 端在地化，比照 ADR 0034）。只在閱讀器開書失敗後呼叫一次；
 *    透過背景任務佇列通道呼叫，避免有缺陷的文件提供者卡住主執行緒。
 *
```

- [ ] **Step 3：新增 `when` 分支**

在 `onMethodCall` 的 `"readContentUriAll" -> { ... }` 分支之後、`else -> result.notImplemented()` 之前新增：

```kotlin
            // epic-15-storage-permission Issue 1：見 class doc 第 5 點。
            // 既有 cacheBookForServing／readContentUriAll／readCustomFontBytes
            // 仍維持「失敗回傳 null」契約，不受本方法影響。
            "probeUriAccess" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.success("unknownError")
                    return
                }
                val code = try {
                    // use 區塊確保串流與底層 FileDescriptor 在任何情況下都會釋放（審查 M-2）
                    context.contentResolver.openInputStream(Uri.parse(uriString))?.use {
                        "readable"
                    } ?: run {
                        Log.w("ReaderResourceChannel", "probeUriAccess: null stream for uri: $uriString")
                        "fileNotFound"
                    }
                } catch (e: SecurityException) {
                    // 警告等級：部分 ROM 會過濾 Debug 等級 logcat（epic-7 Issue 1 既有教訓）
                    Log.w("ReaderResourceChannel", "probeUriAccess: permission revoked for uri: $uriString", e)
                    "permissionRevoked"
                } catch (e: FileNotFoundException) {
                    Log.w("ReaderResourceChannel", "probeUriAccess: file not found for uri: $uriString", e)
                    "fileNotFound"
                } catch (e: Exception) {
                    Log.w("ReaderResourceChannel", "probeUriAccess: unknown error for uri: $uriString", e)
                    "unknownError"
                }
                result.success(code)
            }
```

- [ ] **Step 4：編譯驗證**

Run: `flutter build apk --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 5：Commit**

```bash
git add android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt
git commit -m "feat(android): ReaderResourceChannel 新增 probeUriAccess 存取探測（epic-15 Issue 1）"
```

---

### Task 3：`ReaderScreen` 探測流程與錯誤視圖分流（含在地化）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`：
  - import 區
  - State 欄位區（`late String _activeFilePath` 之後）
  - `_handleError`（約第 1937 行）
  - `_handleOpenBookTimeout`（約第 1951 行）
  - `_buildBody` 錯誤分支（約第 2862 行 `_errorMessage ?? l10n.readerFailedToLoadBookMessage`）
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`
- Regenerate: `app/lib/l10n/app_localizations*.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `probeStorageAccess`、`StorageAccessProbeResult`；Issue 0 的 `_activeFilePath`
- Produces（Issue 2 使用）：
  - `_ReaderScreenState._probeResult`（`StorageAccessProbeResult?`）：錯誤視圖依它分流；Issue 2 依它決定是否顯示按鈕。
  - `_ReaderScreenState._isProbingAccess`（`bool`）。
  - l10n getter `readerStoragePermissionRevokedMessage`、`readerStorageFileNotFoundMessage`。

- [ ] **Step 1：新增 ARB key 並產生程式碼**

四份 ARB 都在 `"readerFailedToLoadBookMessage"` 那個 key 之後插入（範本檔在它的 `"@readerFailedToLoadBookMessage": {...}` 區塊之後）。

`app_zh_TW.arb`：

```json
  "readerStoragePermissionRevokedMessage": "App 對這個檔案的存取權限已失效，請重新選取檔案。",
  "@readerStoragePermissionRevokedMessage": {
    "description": "epic-15 Issue 1：開書失敗且存取探測結果為權限已撤銷（SecurityException）時的錯誤說明"
  },
  "readerStorageFileNotFoundMessage": "找不到原始檔案，可能已被移動、改名或刪除。請先確認檔案仍在裝置中，再重新選取。",
  "@readerStorageFileNotFoundMessage": {
    "description": "epic-15 Issue 1：開書失敗且存取探測結果為檔案不存在（FileNotFoundException）時的錯誤說明"
  },
```

`app_zh.arb`（內容同正體中文，不含 `@key`）：

```json
  "readerStoragePermissionRevokedMessage": "App 對這個檔案的存取權限已失效，請重新選取檔案。",
  "readerStorageFileNotFoundMessage": "找不到原始檔案，可能已被移動、改名或刪除。請先確認檔案仍在裝置中，再重新選取。",
```

`app_zh_CN.arb`：

```json
  "readerStoragePermissionRevokedMessage": "App 对这个文件的访问权限已失效，请重新选择文件。",
  "readerStorageFileNotFoundMessage": "找不到原始文件，可能已被移动、重命名或删除。请先确认文件仍在设备中，再重新选择。",
```

`app_en.arb`：

```json
  "readerStoragePermissionRevokedMessage": "The app's access to this file has expired. Please select the file again.",
  "readerStorageFileNotFoundMessage": "The original file could not be found. It may have been moved, renamed, or deleted. Make sure the file is still on the device, then select it again.",
```

Run: `flutter gen-l10n`
Expected: 沒有錯誤輸出。`git status` 看得到 `lib/l10n/app_localizations.dart`、`app_localizations_zh.dart`、`app_localizations_en.dart` 被修改。

- [ ] **Step 2：寫失敗的測試**

在 `reader_screen_test.dart` 頂端 `main()` 之前新增測試輔助函式：

```dart
/// epic-15-storage-permission Issue 1：以 content:// EPUB 開啟 ReaderScreen，
/// 並覆寫 [probeStorageAccess]。回傳探測呼叫次數的讀取器。
Future<int Function()> _pumpContentUriReader(
  WidgetTester tester, {
  required FakeReaderPrefsManager prefsManager,
  required Future<StorageAccessProbeResult> Function(String uri) probe,
  String filePath = 'content://com.example.provider/book.epub',
}) async {
  var probeCalls = 0;
  final original = probeStorageAccess;
  probeStorageAccess = (uri) {
    probeCalls++;
    return probe(uri);
  };
  addTearDown(() => probeStorageAccess = original);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: ReaderScreen(
        filePath: filePath,
        bookId: 'b_probe',
        prefsManager: prefsManager,
        isFixedLayout: false,
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() => Future.delayed(Duration.zero));
  await tester.pump();
  return () => probeCalls;
}
```

在 `main()` 內、`tearDownAll(...)` 之前新增：

```dart
  group('開書失敗的存取探測（epic-15-storage-permission Issue 1）', () {
    testWidgets('permissionRevoked：顯示權限失效說明', (tester) async {
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked);

      tester.widget<FoliateReaderView>(find.byType(FoliateReaderView))
          .onError('boom');
      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('reader_error_text'))).data,
        'App 對這個檔案的存取權限已失效，請重新選取檔案。',
      );
    });

    testWidgets('fileNotFound：顯示找不到檔案說明', (tester) async {
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.fileNotFound);

      tester.widget<FoliateReaderView>(find.byType(FoliateReaderView))
          .onError('boom');
      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('reader_error_text'))).data,
        '找不到原始檔案，可能已被移動、改名或刪除。請先確認檔案仍在裝置中，再重新選取。',
      );
    });

    for (final result in [
      StorageAccessProbeResult.readable,
      StorageAccessProbeResult.unknownError,
    ]) {
      testWidgets('$result：維持原本的錯誤訊息', (tester) async {
        await _pumpContentUriReader(tester,
            prefsManager: prefsManager, probe: (_) async => result);

        tester.widget<FoliateReaderView>(find.byType(FoliateReaderView))
            .onError('原始錯誤訊息');
        await tester.pump();
        await tester.pump();

        expect(
          tester.widget<Text>(find.byKey(const Key('reader_error_text'))).data,
          '原始錯誤訊息',
        );
      });
    }

    testWidgets('非 content:// 的書不呼叫探測，直接顯示原本的錯誤訊息',
        (tester) async {
      final probeCalls = await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          filePath: 'test/fixtures/sample.epub',
          probe: (_) async => StorageAccessProbeResult.permissionRevoked);

      tester.widget<FoliateReaderView>(find.byType(FoliateReaderView))
          .onError('原始錯誤訊息');
      await tester.pump();

      expect(probeCalls(), 0);
      expect(
        tester.widget<Text>(find.byKey(const Key('reader_error_text'))).data,
        '原始錯誤訊息',
      );
    });

    testWidgets('開書逾時不呼叫探測', (tester) async {
      final probeCalls = await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked);

      await tester.pump(const Duration(seconds: 30));

      expect(probeCalls(), 0);
      expect(
        tester.widget<Text>(find.byKey(const Key('reader_error_text'))).data,
        '開書逾時，可能是系統 WebView 版本過舊或檔案異常',
      );
    });

    testWidgets('探測未完成時連續兩次 onError 只探測一次，期間維持載入指示器',
        (tester) async {
      final pending = Completer<StorageAccessProbeResult>();
      final probeCalls = await _pumpContentUriReader(tester,
          prefsManager: prefsManager, probe: (_) => pending.future);

      final view =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      view.onError('第一次');
      view.onError('第二次');
      await tester.pump();

      expect(probeCalls(), 1);
      expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      pending.complete(StorageAccessProbeResult.fileNotFound);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('reader_error_text')), findsOneWidget);
      expect(find.byKey(const Key('reader_loading_indicator')), findsNothing);
    });

    testWidgets('探測未完成時推進超過開書逾時，仍維持載入指示器、不顯示逾時訊息',
        (tester) async {
      final pending = Completer<StorageAccessProbeResult>();
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager, probe: (_) => pending.future);

      tester.widget<FoliateReaderView>(find.byType(FoliateReaderView))
          .onError('boom');
      await tester.pump(const Duration(seconds: 31));

      expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      pending.complete(StorageAccessProbeResult.permissionRevoked);
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('reader_error_text'))).data,
        'App 對這個檔案的存取權限已失效，請重新選取檔案。',
      );
    });

    testWidgets('探測未完成時 onPageRendered 先到，探測結果回來不覆蓋成錯誤畫面',
        (tester) async {
      final pending = Completer<StorageAccessProbeResult>();
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager, probe: (_) => pending.future);

      final view =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      view.onError('boom');
      await tester.pump();
      view.onPageRendered();
      await tester.pump();

      pending.complete(StorageAccessProbeResult.permissionRevoked);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('reader_error_text')), findsNothing);
      expect(find.byType(FoliateReaderView), findsOneWidget);
    });

    testWidgets('探測函式本身拋出例外：退回原本的錯誤訊息，不停在載入中（審查 I-1）',
        (tester) async {
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => throw StateError('probe 爆掉'));

      tester.widget<FoliateReaderView>(find.byType(FoliateReaderView))
          .onError('原始錯誤訊息');
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('reader_loading_indicator')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('reader_error_text'))).data,
        '原始錯誤訊息',
      );
    });

    testWidgets('探測未完成時離開閱讀器，結果回來後不拋例外', (tester) async {
      final pending = Completer<StorageAccessProbeResult>();
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager, probe: (_) => pending.future);

      tester.widget<FoliateReaderView>(find.byType(FoliateReaderView))
          .onError('boom');
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      pending.complete(StorageAccessProbeResult.permissionRevoked);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
```

**測試範圍取捨（審查 M-3）**：以上案例都以 `FoliateReaderView`（content:// EPUB）觸發錯誤。`PdfReaderView` 的 `onError` 走的是同一個 `_handleError` 進入點，而 `pdfrx` 在純 widget test 環境下有 FFI 初始化成本，所以 PDF 真實開書失敗的端到端驗證，交給 Task 4 的真機步驟。

若 `reader_screen_test.dart` 頂端尚未 import `dart:async`，補上 `import 'dart:async';`（`Completer` 需要）。`probeStorageAccess`、`StorageAccessProbeResult` 來自既有的 `import 'package:elinkbook/reader/foliate_native_bridge.dart';`，不必另外 import。

- [ ] **Step 3：執行測試，確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "開書失敗的存取探測"`
Expected: FAIL。
- `permissionRevoked`／`fileNotFound` 兩個案例：實際文字是 `boom`，不是分類說明。
- 「只探測一次」案例：`probeCalls()` 為 0，而且畫面已經是錯誤視圖。
- 「非 content://」「開書逾時」「readable／unknownError」幾個案例在實作前就可能通過，這是預期中的正向對照。

- [ ] **Step 4：實作**

`reader_screen.dart` import 區，在 `import '../reader/reader_console_log.dart';` 之前新增：

```dart
import '../reader/foliate_native_bridge.dart'
    show StorageAccessProbeResult, probeStorageAccess;
```

State 欄位區，在 `late String _activeFilePath = widget.filePath;` 之後新增：

```dart
  /// epic-15-storage-permission Issue 1：開書失敗後的存取探測結果。
  /// 錯誤視圖依它分流顯示說明文字；Issue 2 依它決定是否顯示「重新選取
  /// 檔案」按鈕。只有 `content://` 書籍的 onError 會探測，其餘情況維持
  /// null（顯示原本的錯誤訊息）。
  StorageAccessProbeResult? _probeResult;

  /// epic-15-storage-permission Issue 1：探測進行中。期間忽略後續
  /// onError 與開書逾時——底層視圖此時仍在樹上，可能連續回報多次錯誤。
  bool _isProbingAccess = false;
```

把整個 `_handleError` 方法本體（保留它上方既有的 doc comment）改成：

```dart
  void _handleError(String message) {
    if (!mounted) return;
    if (_state != _RenderState.loading) return;
    // epic-15-storage-permission Issue 1：探測進行中再收到的錯誤一律忽略。
    if (_isProbingAccess) return;
    _openBookTimeoutTimer?.cancel();
    if (_activeFilePath.startsWith('content://')) {
      // 維持載入指示器，探測完才切到錯誤視圖，避免 E-Ink 畫面先閃出通用
      // 錯誤再換成分類說明。
      _isProbingAccess = true;
      _probeAccessAndShowError(message);
      return;
    }
    setState(() {
      _state = _RenderState.error;
      _errorMessage = message;
    });
  }

  /// epic-15-storage-permission Issue 1：探測 [_activeFilePath] 的可讀性，
  /// 完成後切到錯誤視圖。結果回來時若 State 已 dispose，或開書其實已經
  /// 成功（狀態不再是載入中），就直接捨棄結果。
  Future<void> _probeAccessAndShowError(String message) async {
    StorageAccessProbeResult result;
    try {
      result = await probeStorageAccess(_activeFilePath);
    } catch (_) {
      // 逾時計時器在第一次錯誤時已取消；探測函式（含測試注入的替身）若
      // 拋出例外而沒有切到錯誤視圖，閱讀器會永遠停在載入中（審查 I-1）。
      result = StorageAccessProbeResult.unknownError;
    }
    if (!mounted) return;
    _isProbingAccess = false;
    if (_state != _RenderState.loading) return;
    setState(() {
      _state = _RenderState.error;
      _errorMessage = message;
      _probeResult = result;
    });
  }
```

`_handleOpenBookTimeout` 在 `if (_state != _RenderState.loading) return;` 之後新增一行：

```dart
    // epic-15-storage-permission Issue 1：探測進行中由探測結果決定錯誤畫面。
    if (_isProbingAccess) return;
```

`_buildBody` 錯誤分支中，把：

```dart
          Center(
            child: Text(
              _errorMessage ?? l10n.readerFailedToLoadBookMessage,
              key: const Key('reader_error_text'),
            ),
          ),
```

改成：

```dart
          Center(
            // epic-15-storage-permission Issue 1：新的分類說明是多行長文字
            // （英文約 140 字元），加上水平間距並置中，避免貼齊螢幕兩側
            // （審查 M-1）。
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                // 依存取探測結果分流。
                switch (_probeResult) {
                  StorageAccessProbeResult.permissionRevoked =>
                    l10n.readerStoragePermissionRevokedMessage,
                  StorageAccessProbeResult.fileNotFound =>
                    l10n.readerStorageFileNotFoundMessage,
                  _ => _errorMessage ?? l10n.readerFailedToLoadBookMessage,
                },
                key: const Key('reader_error_text'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
```

這個改動會套用到所有錯誤訊息（包含既有的通用錯誤與開書逾時），只影響排版，不影響文字內容。

- [ ] **Step 5：執行測試，確認通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "開書失敗的存取探測"`
Expected: 11 個測試全部通過。

Run: `flutter test test/screens/reader_screen_test.dart test/reader/foliate_native_bridge_test.dart`
Expected: All tests passed。既有的開書逾時、良性 ResizeObserver 警告等案例都不受影響。

Run: `flutter analyze`
Expected: `No issues found!`

Run: `node tool/check_l10n_hardcoded_strings.js`
Expected: 沒有新增違規。

- [ ] **Step 6：Commit**

```bash
git add lib/screens/reader_screen.dart test/screens/reader_screen_test.dart lib/l10n/
git commit -m "feat(reader): 開書失敗時探測 content:// 存取狀態並分流錯誤說明（epic-15 Issue 1）"
```

---

### Task 4：真機驗證（需要真人操作）

**Files:** 無程式改動；結果記錄在 `docs/epics/epic-15-storage-permission/epic.md`。

這個 Task 需要實體 Android 裝置，以及手動操作系統設定或檔案管理員。執行者若是 agent，完成 Step 1 後就停下來，把 Step 2～4 交給人類操作，並回報在哪裡等待。

- [ ] **Step 1：安裝 debug 版**

Run: `flutter devices`，確認裝置 ID 後執行 `flutter run -d <device-id>`。

- [ ] **Step 2：準備測試書籍（人類）**

- 在裝置上建一個資料夾，放入一本 EPUB 與一本 PDF。
- 用 App 的「匯入資料夾」匯入。資料夾匯入的書，`filePath` 會維持 `content://`。
- 確認兩本都能正常開啟。

- [ ] **Step 3：模擬權限失效（人類）**

擇一：
- 在系統設定清除 App 的檔案存取授權。
- 用 adb 撤銷授權：`adb shell cmd uri revoke-permission ...`，指令依 Android 版本不同。

開啟那本 EPUB，預期畫面顯示「App 對這個檔案的存取權限已失效…」。`adb logcat -s ReaderResourceChannel` 要有 `probeUriAccess: permission revoked` 的警告；閱讀器的 Console Log 要有 `→ permissionRevoked`。PDF 重複一次。

- [ ] **Step 4：模擬檔案不存在（人類）**

- 重新匯入後，用檔案管理員刪除或搬移原始檔案。
- 開書，預期畫面顯示「找不到原始檔案…」。logcat 要有 `file not found` 或 `null stream`。

- [ ] **Step 5：記錄結果**

在 `epic.md` 新增「Issue 1 真機驗證」段落，內容包含：裝置型號、Android 版本、撤銷授權的方式、每個情境的實際畫面文字與 logcat 摘要。任何一項不符預期，都要如實記錄並回報，不要逕自修改範圍外的程式碼。

---

### Task 5：完整測試與進度文件

- [ ] **Step 1：完整測試**

Run: `flutter test`
Expected: All tests passed。若有失敗，先單獨重跑該檔案，確認是不是本 Issue 造成的；和本 Issue 無關的失敗要如實記錄在 `epic.md`，不要為了讓它通過而修改範圍外的程式碼。

Run: `flutter analyze`
Expected: `No issues found!`

Run: `node tool/check_l10n_hardcoded_strings.js`
Expected: 通過。

- [ ] **Step 2：更新進度文件**

- `docs/epics/epic-15-storage-permission/issues.md`：Issue 1 的 `**Status:** ready-for-agent` 改為 `**Status:** completed`。
- `docs/epics/epic-15-storage-permission/epic.md`：在「目前狀態」之前新增 Issue 1 完成記錄，內容包含 commit 清單、完整 `flutter test` 結果與執行時的 commit、真機驗證摘要。把「目前狀態」改為「Issue 1 完成，待 PR 合併；下一步 Issue 2／Issue 3（可平行）」。
- `docs/epics.md`：epic-15 備註改為 `Issue 1 已完成`。

```bash
git add ../docs/epics/epic-15-storage-permission/issues.md ../docs/epics/epic-15-storage-permission/epic.md ../docs/epics.md
git commit -m "docs(epic-15): 記錄 Issue 1 完成"
```
