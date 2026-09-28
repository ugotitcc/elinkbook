# Epic 45 Issue 7：執行期例外訊息在地化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（recommended）or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把目前仍會把「原始例外文字」（`e.toString()`／`e.message`／JS 端原始錯誤字串）直接顯示給使用者的執行期錯誤路徑，改為固定的 `AppLocalizations` 在地化訊息；技術除錯細節改寫入既有 Console Log 機制。零使用者可見行為變動（除新增語言支援本身），技術例外詳情仍可由開發者/回報者透過既有管道查看。

**Architecture:** `issues.md` 原始列出的 14 個檔案是在 Issue 3-6（畫面字串抽取）完成**之前**盤點的。本計畫認領時重新逐檔案通讀＋追蹤呼叫鏈後確認：其中 10 個檔案的例外訊息在 Issue 3-6 過程中已順帶在地化完畢，或該例外訊息從未真正被顯示給使用者（呼叫端一律 `catch (_)` 泛用吞掉、或已有既存的泛用在地化訊息代打）——這些屬於**服務層拋出但呼叫端從不顯示**的既有行為缺口，不在本 Issue「翻譯可見文字」範圍內，不予處理（YAGNI，見下方「範圍已依實際盤點修正」逐檔說明）。實際需要修改的是 4 個檔案（外加 1 個既有 key 的既有反模式修正），拆為 4 個內容 Task＋1 個最終驗證 Task：

- `foliate_reader_view.dart`（Task 1）／`pdf_reader_view.dart`（Task 2）：EPUB／PDF 開書失敗時透過 `onError: ValueChanged<String>` 回呼把字串往上傳給 `reader_screen.dart`，目前分別在 3 處／1 處直接把 `e.toString()`／JS 端原始錯誤文字／`'$e'` 插值當作使用者可見文字，違反 `spec.md` §6。修法：呼叫端各自在自己的 `State`（皆持有 `context`）內把訊息在地化好才呼叫 `onError`，原始技術細節改寫入既有 `ReaderConsoleLog.add()`（`reader_screen.dart` 本身完全不需要修改，它只是把已在地化好的字串塞進 `_errorMessage`）。兩者皆重用既有 key `l10n.readerFailedToLoadBookMessage`（Issue 4 既有、語意完全吻合「書籍載入失敗」，不新增 ARB key，避免鍵值氾濫）。
- `library_repository.dart`／`sqlite_library_repository.dart`／`library_group_management_dialog.dart`（Task 3）：`LibraryRepositoryException` 目前只帶一個中文 `message` 欄位，`library_group_management_dialog.dart` 的 3 個 catch 分支直接顯示 `e.message`。修法：`LibraryRepositoryException` 新增 `LibraryRepositoryErrorReason` 列舉欄位（服務層拋出時標記語意分類，`message` 欄位保留但改為純診斷用途、不再顯示），呼叫端依 `reason` 對應 `AppLocalizations`（新增 1 個 ARB key `libraryGroupNameAlreadyExistsError`，其餘理論不可達的防禦分支重用既有 `l10n.errorOperationFailed`）。
- `reader_screen.dart`（Task 4）：Issue 4 遺留的既有反模式——3 個 ARB key（`readerSaveAsPresetFailedMessage`／`readerApplyPresetFailedMessage`／`readerDeletePresetFailedMessage`）目前帶 `{error}` placeholder，4 處呼叫點皆傳入 `'$e'`，把例外原始文字直接混進使用者可見的 SnackBar。4 處呼叫點本身**已經**各自在同一個 catch 分支用 `debugPrint('...: $e\n$stackTrace')` 記錄技術細節，只是同時**又**把 `$e` 塞進使用者可見文字——移除 3 個 key 的 `{error}` placeholder（改為固定訊息），呼叫點移除 `('$e')` 引數即可，不需要新增任何診斷機制（已經有了）。

**技術驗證（`_cacheBook()`／`_openDocument()` 皆由 `initState()` 觸發，是否受「`initState()` 存取 l10n 陷阱」鐵律限制？）**：Issue 3 審查確立的鐵律（`review-plan-issue-3.md` C-1）精確錯誤訊息是 `dependOnInheritedWidgetOfExactType<AppLocalizations>() was called before <State>.initState() completed`——**限制的是「`initState()` 方法本體執行期間、尚未 return 前」的同步呼叫**，不是「由 `initState()` 觸發的非同步流程」。`_cacheBook()`／`_openDocument()` 皆是 `initState()` 呼叫但不 `await` 的 `Future<void>` 方法（fire-and-forget），本次要修改的 `AppLocalizations.of(context)!` 呼叫點皆位於其 `await`（真正的檔案 I/O）**之後**的 `catch`/`else` 分支——此時 `initState()` 早已同步 return 完畢。本專案既有測試已提供實證：`test/reader/foliate_reader_view_test.dart` 的 `'cache failure calls onError'`／`'cacheBookForServing 拋出例外時...'` 兩個既有測試、`test/reader/pdf_reader_view_test.dart` 的 `'開啟不存在的檔案...'` 測試，皆已用裸 `MaterialApp` pump 過這個確切的非同步錯誤路徑且從未拋出 `FlutterError`（過去只是因為當時該路徑顯示的是硬編碼中文字面值，沒有呼叫 `AppLocalizations.of(context)`，所以沒有機會觸發這個問題；改為呼叫 l10n 後，這幾個既有測試就是最直接的迴歸驗證）。

**Tech Stack:** Flutter `flutter_localizations`／`intl`（ARB／`gen-l10n`）；既有 `ReaderConsoleLog`（`app/lib/reader/reader_console_log.dart`，純記憶體 `ValueNotifier<List<String>>` 緩衝區）。

**Spec:** `docs/epics/epic-45-interface-i18n/spec.md`（§6 執行期例外訊息在地化慣例）、`docs/epics/epic-45-interface-i18n/design.md`（「執行期例外訊息在地化」段落、ADR 0034）、`docs/epics/epic-45-interface-i18n/issues.md`（Issue 7 段落）。

## 範圍已依實際盤點修正（認領時逐檔通讀＋呼叫鏈追蹤）

`issues.md` Issue 7 列出的 14 個檔案，逐一核實後：

- **`sync_settings_screen.dart`**——已於 Issue 5 完全在地化（`catch` 分支已呼叫 `l10n.syncSettingsSyncFailedMessage`／`l10n.syncSettingsConnectionFailedMessage`），無 `e.toString()`/`e.message` 洩漏。**不處理。**
- **`wifi_transfer_screen.dart`**——已於 Issue 6 完全在地化。**不處理。**
- **`opds_http_client.dart`**——服務層，含 3 處硬編碼中文例外訊息，但唯一呼叫端（`remote_catalog_screen.dart`／`download_queue_controller.dart`／`library_screen.dart:618`）全部用 `catch (_)` 泛用吞掉或已有既存泛用在地化訊息代打，這些字串**從未被顯示給使用者**（也未寫入任何 Log）。訊息內容不可見，不屬本 Issue「翻譯可見文字」範圍。**不處理。**
- **`sync_engine.dart`**——通讀全檔：零字串字面值、零 `throw` 語句，只轉手 PocketBase `ClientException`（型別本身，不自訂中文訊息）。**不處理。**
- **`book_import_service_impl.dart`**——通讀全檔：零 `throw` 帶中文訊息，所有解析失敗皆優雅降級（檔名當標題、無封面）或 `return null`，呼叫端 `book_import_picker_helper.dart`（Issue 6 已在地化）只顯示成功/略過本數，不涉及個別失敗原因文字。**不處理。**
- **`sqlite_library_repository.dart`**——服務層，含 3 處硬編碼中文 `LibraryRepositoryException` 訊息，**確認會外洩**（見下方 Task 3）。**本 Issue 處理。**
- **`reader_screen.dart`**——4 處既有 ARB key（Issue 4 遺留）帶 `{error}` placeholder，直接顯示 `'$e'`，**確認違反 spec §6**（見下方 Task 4）。**本 Issue 處理。**
- **`search_repository.dart`**——通讀全檔：零字串字面值、零 `throw`。**不處理。**
- **`reader_jump_target.dart`**——通讀全檔：零字串字面值、零 `throw`，所有解析失敗皆優雅降級回傳 `null`。**不處理。**
- **`custom_fonts_repository.dart`**——通讀全檔：零自訂中文例外，只轉手 SQLite 原生 `DatabaseException`；唯一呼叫端 `font_management_screen.dart:53` 為 `catch (e) { debugPrint(...); }`，純 log 不顯示。**不處理。**
- **`txt_charset_detection.dart`**——通讀全檔：零 `throw`（設計上全數優雅降級，最終強制 UTF-8 寬鬆解碼，文件註解已明載此原則，絕不拋例外）。**不處理。**
- **`md_frontmatter.dart`**——通讀全檔：零 `throw`（格式不合法時優雅降級）。**不處理。**
- **`kf8_metadata.dart`**——服務層，含 4 處硬編碼中文例外（`FormatException`／`RangeError`／自訂 `DrmProtectedException`），但唯一呼叫端 `book_import_service_impl.dart:307-326` 對 `DrmProtectedException` 是 `return null`（訊息字串被丟棄，只用型別分支決定「中止匯入」，該書從匯入結果消失，無個別失敗原因提示）、其餘落入 `catch (_) {}` 泛用降級。訊息內容**從未被顯示**。**不處理。**
- **`foliate_reader_view.dart`**——`issues.md` 原始清單已列入，逐行核實找到 3 處確實外洩的使用者可見字串（見下方 Task 1）。**本 Issue 處理。**

**新增（不在原始 14 檔清單內，但透過呼叫鏈追蹤發現屬於同一例外處理鏈、邏輯上必須一併處理，否則會出現「一半在地化、一半仍是原始例外文字」的不完整狀態）：**

- **`pdf_reader_view.dart`**——`foliate_reader_view.dart` 的 PDF 對應檔案，`_openDocument()` 的 `catch (e)` 目前是 `widget.onError(e.toString())`——**任何**開檔例外（含 `_openContentUriDocument()` 拋出的 `StateError('無法讀取檔案：...')`、PDFium 原生例外）都原樣顯示給使用者，是本 Issue 掃描範圍內最直接的 spec §6 違規之一，唯一呼叫端與 `foliate_reader_view.dart` 相同（`reader_screen.dart._handleError`），一併收斂（見 Task 2）。
- **`library_group_management_dialog.dart`**——`sqlite_library_repository.dart` 拋出例外的唯一呼叫端（Issue 2 完成當下未涵蓋這 3 個 catch 分支），兩者是同一個修法的一體兩面，一併處理（見 Task 3）。

## Global Constraints

- 本 Issue **不新增**大部分 ARB key——`foliate_reader_view.dart`／`pdf_reader_view.dart` 兩個 Task 皆重用既有 `readerFailedToLoadBookMessage`（Issue 4 既有 key，語意「無法載入書籍」與「開書失敗」完全吻合），避免為同一種使用者體驗（開書失敗）新增多個近義字串。整個 Issue 只新增 1 個 ARB key：`libraryGroupNameAlreadyExistsError`（Task 3）。異動前四份 ARB 檔案皆為 539 個 key，完全同步。
- **技術例外詳情去向**：任何被移除的 `e.toString()`／`e.message`／JS 原始錯誤字串，一律改寫入該檔案既有的診斷管道——`app/lib/reader/` 下的兩個檔案（`foliate_reader_view.dart`／`pdf_reader_view.dart`）已 import `reader_console_log.dart`，改用 `ReaderConsoleLog.add('...')`；`app/lib/screens/library_group_management_dialog.dart` 沒有既有的 Console Log 機制（那是閱讀器專屬的診斷面板），改用 `debugPrint('...')`（`package:flutter/material.dart` 已透傳匯出 `debugPrint`，不需要額外 import，比照 Issue 5 `font_management_screen.dart` catch 分支既有慣例）；`reader_screen.dart`（Task 4）4 處呼叫點**已經**各自呼叫 `debugPrint('...: $e\n$stackTrace')`，不需新增。
- **`AppLocalizations.of(context)!` 一律 non-null assertion**（`review-issue-2.md` Important #1 確立的教訓），不得使用 nullable fallback。
- **`initState()` 存取 l10n 陷阱**：見上方「技術驗證」段落——本 Issue 兩個由 `initState()` 觸發的非同步方法（`_cacheBook()`／`_openDocument()`），其 l10n 呼叫點皆位於 `await` 之後的 `catch`/`else` 分支，此時 `initState()` 早已同步 return 完畢，不受此鐵律限制；每個 Task 的驗證步驟皆會實際執行既有涵蓋這條路徑的 widget test 作為實證，不能只憑理論判斷。
- 服務層（`sqlite_library_repository.dart`）**不可** import `package:flutter/material.dart`／`AppLocalizations`（`spec.md` §6 分層原則）——本 Issue 服務層的異動僅止於新增 `reason` 列舉欄位／傳遞既有的純 Dart enum 值，不涉及任何 UI 框架依賴。
- 測試執行範圍：單一 Task 完成後只跑該 Task 觸及的測試檔；完整 `flutter test`／`flutter analyze` 僅在 Task 5（最後一個 Task）執行一次。
- Commit 訊息前綴統一 `feat(epic-45):`，Task 5 除外用 `docs(epic-45):`。

---

### Task 1: `foliate_reader_view.dart`——開書快取失敗／JS 端錯誤訊息改為固定在地化文字

**Files:**
- Modify: `app/lib/reader/foliate_reader_view.dart`
- Test: `app/test/reader/foliate_reader_view_test.dart`

**Interfaces:**
- Consumes：既有 `AppLocalizations.readerFailedToLoadBookMessage`（getter，無 placeholder，`app/lib/l10n/app_localizations.dart` 既有，不新增）；既有 `ReaderConsoleLog.add(String message)`（`app/lib/reader/reader_console_log.dart`）。
- Produces：新頂層函式 `String resolveFoliateOpenBookErrorMessage(List<dynamic> args, AppLocalizations l10n)`（同檔案，比照既有 `handleFoliateConsoleMessage()` 抽出頂層純函式獨立測試的既定模式——`FakePlatformInAppWebViewWidget` 無法真正觸發 `addJavaScriptHandler` 回呼鏈，抽出後才能脫離該型別鏈直接以 `test()` 測試），供 `_onWebViewCreated()` 內的 JS bridge `onError` handler 呼叫。

- [ ] **Step 1: 新增 import**

在 `app/lib/reader/foliate_reader_view.dart` 現有 import 區塊（第 9 行 `import 'column_mode.dart';` 之前）新增：

```dart
import '../l10n/app_localizations.dart';
```

- [ ] **Step 2: 撰寫 `resolveFoliateOpenBookErrorMessage()` 的失敗測試**

在 `app/test/reader/foliate_reader_view_test.dart` 檔尾（`tearDownAll` 區塊之前）新增一個新 `group`：

```dart
  group('resolveFoliateOpenBookErrorMessage', () {
    setUp(() => ReaderConsoleLog.clear());

    test('main.js 回傳具體錯誤文字時，回傳固定在地化訊息、原始文字寫入 Console Log', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final message =
          resolveFoliateOpenBookErrorMessage(['SyntaxError: Unexpected token'], l10n);

      expect(message, l10n.readerFailedToLoadBookMessage);
      expect(
        ReaderConsoleLog.entries.value.last,
        contains('SyntaxError: Unexpected token'),
      );
    });

    test('main.js 未帶任何錯誤細節（args 為空）時，仍回傳固定在地化訊息、不拋例外', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final message = resolveFoliateOpenBookErrorMessage(const [], l10n);

      expect(message, l10n.readerFailedToLoadBookMessage);
    });

    test('args 為 [null] 時，回傳固定在地化訊息、Console Log 記錄 (no detail) 而非 "null"', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final message = resolveFoliateOpenBookErrorMessage([null], l10n);

      expect(message, l10n.readerFailedToLoadBookMessage);
      expect(ReaderConsoleLog.entries.value.last, contains('(no detail)'));
    });

    test('args 為 [\'   \']（純空白字串）時，回傳固定在地化訊息、Console Log 記錄 (no detail) 而非空白', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final message = resolveFoliateOpenBookErrorMessage(['   '], l10n);

      expect(message, l10n.readerFailedToLoadBookMessage);
      expect(ReaderConsoleLog.entries.value.last, contains('(no detail)'));
    });

    test('英文介面下回傳英文固定訊息', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final message = resolveFoliateOpenBookErrorMessage(['boom'], l10n);

      expect(message, 'Failed to load book');
    });
  });
```

在檔案頂端 import 區塊新增（`import 'package:elinkbook/reader/reader_console_log.dart';` 已存在，見既有第 11 行，不重複新增）：

```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

- [ ] **Step 3: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/foliate_reader_view_test.dart --plain-name "resolveFoliateOpenBookErrorMessage"`
Expected: 編譯錯誤或 `resolveFoliateOpenBookErrorMessage` 未定義（函式尚未實作）。

- [ ] **Step 4: 實作 `resolveFoliateOpenBookErrorMessage()`，並接上 JS bridge `onError` handler**

在 `app/lib/reader/foliate_reader_view.dart` 找到既有的：

```dart
    controller.addJavaScriptHandler(
      handlerName: FoliateBridgeHandlers.onError,
      callback: (args) {
        widget.onError(args.isNotEmpty ? args[0] as String : '未知錯誤');
      },
    );
```

改為：

```dart
    controller.addJavaScriptHandler(
      handlerName: FoliateBridgeHandlers.onError,
      callback: (args) {
        if (!mounted) return;
        widget.onError(
          resolveFoliateOpenBookErrorMessage(args, AppLocalizations.of(context)!),
        );
      },
    );
```

（`callback: (args)` 是 WebView 透過平台通道非同步觸發的事件回呼，與 `_cacheBook()`／`pdf_reader_view.dart._openDocument()` 的 `await` 之後分支同樣存在「回呼抵達時 widget 可能已 unmounted」的競態——例如使用者在開書卡頓時立即返回離開 `ReaderScreen`。比照同檔案 `_cacheBook()` 兩個分支與 `pdf_reader_view.dart._openDocument()` 既有的 `if (!mounted) return;` 防衛慣例補上，避免 `AppLocalizations.of(context)!` 在已 deactivate 的 `context` 上呼叫而拋出 `FlutterError`。）

在同檔案任一頂層函式旁邊（例如緊接在既有 `handleFoliateConsoleMessage()` 之後）新增：

```dart
/// [FoliateBridgeHandlers.onError] JS handler 的訊息解析邏輯，抽成頂層純函式
/// 獨立測試——原因同 [handleFoliateConsoleMessage]：
/// `FakePlatformInAppWebViewWidget`（`test/support/fake_inappwebview_platform.dart`）
/// 無法真正觸發完整的 `addJavaScriptHandler` 回呼型別鏈，抽出後才能脫離該型別鏈
/// 直接測試。main.js 的 `openBook()` 失敗時透過 `args[0]` 傳入原始技術性錯誤文字
/// （可能是英文 JS Error message，見 main.js `String((e && e.message) || e)`），
/// 依 `spec.md` §6「禁止在使用者可見文字中出現例外物件的原始文字內容」，這段原始
/// 文字只能寫入 [ReaderConsoleLog]，回傳給使用者的一律是固定在地化訊息。[args] 可能
/// 帶 `null` 或純空白字串（JS 端未附帶有意義的錯誤描述時），一併過濾為 `(no detail)`，
/// 避免 Console Log 診斷輸出淪為無意義的 `"null"`/空白。
String resolveFoliateOpenBookErrorMessage(
  List<dynamic> args,
  AppLocalizations l10n,
) {
  final raw = args.isNotEmpty ? args[0]?.toString().trim() : null;
  final detail = (raw != null && raw.isNotEmpty) ? raw : '(no detail)';
  ReaderConsoleLog.add('[FoliateReaderView] openBook 失敗: $detail');
  return l10n.readerFailedToLoadBookMessage;
}
```

- [ ] **Step 5: 執行測試確認通過**

Run: `cd app && flutter test test/reader/foliate_reader_view_test.dart --plain-name "resolveFoliateOpenBookErrorMessage"`
Expected: 3 個測試全數 PASS。

- [ ] **Step 6: 修改 `_cacheBook()` 的兩個失敗分支**

在 `app/lib/reader/foliate_reader_view.dart` 找到既有：

```dart
      if (cachedPath != null) {
        // cacheBookForServing 回傳的是檔案絕對路徑，InternalStoragePathHandler 要的是目錄
        setState(() {
          _bookCacheDir = File(cachedPath).parent.path;
        });
      } else {
        widget.onError('無法快取書籍檔案');
      }
    } catch (e) {
      if (!mounted) return;
      widget.onError('快取書籍失敗: $e');
    }
  }
```

改為：

```dart
      if (cachedPath != null) {
        // cacheBookForServing 回傳的是檔案絕對路徑，InternalStoragePathHandler 要的是目錄
        setState(() {
          _bookCacheDir = File(cachedPath).parent.path;
        });
      } else {
        ReaderConsoleLog.add('[FoliateReaderView] _cacheBook 失敗：cacheBookForServing 回傳 null');
        widget.onError(AppLocalizations.of(context)!.readerFailedToLoadBookMessage);
      }
    } catch (e) {
      if (!mounted) return;
      ReaderConsoleLog.add('[FoliateReaderView] _cacheBook 拋出例外: $e');
      widget.onError(AppLocalizations.of(context)!.readerFailedToLoadBookMessage);
    }
  }
```

- [ ] **Step 7: 遷移既有兩個 widget test 至 `pumpLocalizedWidget()`，更新斷言**

在 `app/test/reader/foliate_reader_view_test.dart` 頂端新增 import：

```dart
import '../support/pump_localized_widget.dart';
```

找到既有（約第 1930-1948 行）：

```dart
    testWidgets('cache failure calls onError', (tester) async {
      cacheBookForServing = (filePath, instanceId) async {
        return null;
      };

      String? receivedError;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: (msg) => receivedError = msg,
          ),
        ),
      ));

      await tester.pump();
      expect(receivedError, '無法快取書籍檔案');
    });
```

改為：

```dart
    testWidgets('cache failure calls onError（改為固定在地化訊息，不再是硬編碼中文字面值）',
        (tester) async {
      ReaderConsoleLog.clear();
      cacheBookForServing = (filePath, instanceId) async {
        return null;
      };

      String? receivedError;
      await pumpLocalizedWidget(
        tester,
        Scaffold(
          body: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: (msg) => receivedError = msg,
          ),
        ),
      );

      await tester.pump();
      expect(receivedError, '無法載入書籍');
      expect(
        ReaderConsoleLog.entries.value.last,
        contains('cacheBookForServing 回傳 null'),
      );
    });
```

找到既有（約第 1950-1972 行）：

```dart
    testWidgets(
        'cacheBookForServing 拋出例外時（epic-18-reader-device-qa Issue 33），'
        '呼叫 onError 帶入例外訊息，不會讓畫面永遠卡在載入指示器',
        (tester) async {
      cacheBookForServing = (filePath, instanceId) async {
        throw Exception('模擬檔案系統錯誤');
      };

      String? receivedError;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: (msg) => receivedError = msg,
          ),
        ),
      ));

      await tester.pump();
      expect(receivedError, contains('快取書籍失敗'));
      expect(receivedError, contains('模擬檔案系統錯誤'));
    });
```

改為：

```dart
    testWidgets(
        'cacheBookForServing 拋出例外時（epic-18-reader-device-qa Issue 33），'
        '呼叫 onError 帶入固定在地化訊息（不含例外原始文字），例外細節改寫入 Console Log，'
        '不會讓畫面永遠卡在載入指示器',
        (tester) async {
      ReaderConsoleLog.clear();
      cacheBookForServing = (filePath, instanceId) async {
        throw Exception('模擬檔案系統錯誤');
      };

      String? receivedError;
      await pumpLocalizedWidget(
        tester,
        Scaffold(
          body: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: (msg) => receivedError = msg,
          ),
        ),
      );

      await tester.pump();
      expect(receivedError, '無法載入書籍');
      expect(
        ReaderConsoleLog.entries.value.last,
        contains('模擬檔案系統錯誤'),
      );
    });

    testWidgets('英文介面下，cache 失敗顯示英文固定訊息', (tester) async {
      cacheBookForServing = (filePath, instanceId) async {
        return null;
      };

      String? receivedError;
      await pumpLocalizedWidget(
        tester,
        Scaffold(
          body: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: (msg) => receivedError = msg,
          ),
        ),
        locale: const Locale('en'),
      );

      await tester.pump();
      expect(receivedError, 'Failed to load book');
    });
```

- [ ] **Step 8: 執行本檔案測試確認通過**

Run: `cd app && flutter test test/reader/foliate_reader_view_test.dart`
Expected: 全數 PASS（既有測試數 + 本 Task 新增 6 個：`resolveFoliateOpenBookErrorMessage` 5 個〔具體錯誤文字／args 為空／args 為 `[null]`／args 為純空白字串／英文介面〕＋ `_cacheBook()` 英文介面 1 個）。

- [ ] **Step 9: `flutter analyze` 確認本檔案乾淨**

Run: `cd app && flutter analyze lib/reader/foliate_reader_view.dart test/reader/foliate_reader_view_test.dart`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add app/lib/reader/foliate_reader_view.dart app/test/reader/foliate_reader_view_test.dart
git commit -m "feat(epic-45): foliate_reader_view.dart 開書失敗訊息改為固定在地化文字"
```

---

### Task 2: `pdf_reader_view.dart`——開書失敗訊息改為固定在地化文字

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Test: `app/test/reader/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes：既有 `AppLocalizations.readerFailedToLoadBookMessage`（同 Task 1，重用同一個 key）；既有 `ReaderConsoleLog.add(String message)`。
- Produces：無新增公開介面（`_openDocument()` 為既有私有方法，簽章不變）。

- [ ] **Step 1: 新增 import**

在 `app/lib/reader/pdf_reader_view.dart` 現有 import 區塊找到：

```dart
import 'reader_console_log.dart';
import 'tap_zone_detector.dart';
import 'zone_action.dart';
import '../theme/elink_tokens.dart';
```

改為：

```dart
import 'reader_console_log.dart';
import 'tap_zone_detector.dart';
import 'zone_action.dart';
import '../l10n/app_localizations.dart';
import '../theme/elink_tokens.dart';
```

- [ ] **Step 2: 修改既有測試斷言（先改測試，確認會失敗）**

在 `app/test/reader/pdf_reader_view_test.dart` 頂端新增 import：

```dart
import 'package:elinkbook/reader/reader_console_log.dart';
import '../support/pump_localized_widget.dart';
```

找到既有（約第 40-62 行）：

```dart
  testWidgets('開啟不存在的檔案，觸發 onError、不觸發 onPageRendered',
      (tester) async {
    var renderedCount = 0;
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/does_not_exist.pdf',
          onPageRendered: () => renderedCount++,
          onError: (msg) => errorMessage = msg,
        ),
      ),
    );

    await pumpUntilPdfReady(
      tester,
      condition: () => renderedCount != 0 || errorMessage != null,
    );

    expect(errorMessage, isNotNull);
    expect(renderedCount, 0);
  });
```

改為：

```dart
  testWidgets(
      '開啟不存在的檔案，觸發 onError（固定在地化訊息，不含原始例外文字）、'
      '不觸發 onPageRendered，例外細節寫入 Console Log', (tester) async {
    ReaderConsoleLog.clear();
    var renderedCount = 0;
    String? errorMessage;

    await pumpLocalizedWidget(
      tester,
      PdfReaderView(
        filePath: 'test/fixtures/does_not_exist.pdf',
        onPageRendered: () => renderedCount++,
        onError: (msg) => errorMessage = msg,
      ),
    );

    await pumpUntilPdfReady(
      tester,
      condition: () => renderedCount != 0 || errorMessage != null,
    );

    expect(errorMessage, '無法載入書籍');
    expect(renderedCount, 0);
    expect(
      ReaderConsoleLog.entries.value.last,
      contains('_openDocument 失敗'),
    );
  });

  testWidgets('英文介面下，開檔失敗顯示英文固定訊息', (tester) async {
    var renderedCount = 0;
    String? errorMessage;

    await pumpLocalizedWidget(
      tester,
      PdfReaderView(
        filePath: 'test/fixtures/does_not_exist.pdf',
        onPageRendered: () => renderedCount++,
        onError: (msg) => errorMessage = msg,
      ),
      locale: const Locale('en'),
    );

    await pumpUntilPdfReady(
      tester,
      condition: () => renderedCount != 0 || errorMessage != null,
    );

    expect(errorMessage, 'Failed to load book');
  });
```

- [ ] **Step 3: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart --plain-name "開啟不存在的檔案"`
Expected: FAIL（`errorMessage` 仍是 `does_not_exist.pdf` 的原始例外字串，不等於 `'無法載入書籍'`）。

- [ ] **Step 4: 修改 `_openDocument()`**

在 `app/lib/reader/pdf_reader_view.dart` 找到既有：

```dart
  Future<void> _openDocument() async {
    try {
      final document = widget.filePath.contains('://')
          ? await _openContentUriDocument()
          : await PdfDocument.openFile(widget.filePath);
      if (!mounted) {
        await document.dispose();
        return;
      }
      setState(() => _document = document);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      widget.onError(e.toString());
    }
  }
```

改為：

```dart
  Future<void> _openDocument() async {
    try {
      final document = widget.filePath.contains('://')
          ? await _openContentUriDocument()
          : await PdfDocument.openFile(widget.filePath);
      if (!mounted) {
        await document.dispose();
        return;
      }
      setState(() => _document = document);
    } catch (e) {
      if (!mounted) return;
      ReaderConsoleLog.add('[PdfReaderView] _openDocument 失敗: $e');
      setState(() => _error = e);
      widget.onError(AppLocalizations.of(context)!.readerFailedToLoadBookMessage);
    }
  }
```

- [ ] **Step 5: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_test.dart`
Expected: 全數 PASS（既有測試數 + 本 Task 新增 1 個英文介面測試）。

- [ ] **Step 6: `flutter analyze` 確認本檔案乾淨**

Run: `cd app && flutter analyze lib/reader/pdf_reader_view.dart test/reader/pdf_reader_view_test.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_test.dart
git commit -m "feat(epic-45): pdf_reader_view.dart 開書失敗訊息改為固定在地化文字"
```

---

### Task 3: 分類重新命名/刪除例外訊息在地化（`library_repository.dart`／`sqlite_library_repository.dart`／`library_group_management_dialog.dart`）

**Files:**
- Modify: `app/lib/library/library_repository.dart`
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Modify: `app/lib/screens/library_group_management_dialog.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Modify: `app/test/support/fake_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`
- Test: `app/test/screens/library_group_management_dialog_test.dart`

**Interfaces:**
- Consumes：新增 ARB key `libraryGroupNameAlreadyExistsError(String name)`；既有 `l10n.errorOperationFailed`（Issue 2 既有通用 key，重用於理論不可達的防禦分支）。
- Produces：`LibraryRepositoryException` 新增 `LibraryRepositoryErrorReason reason` 欄位（預設值 `LibraryRepositoryErrorReason.unknown`）；新增列舉 `LibraryRepositoryErrorReason { reservedGroupRename, reservedGroupDelete, duplicateGroupName, unknown }`（`app/lib/library/library_repository.dart`，供 `sqlite_library_repository.dart` 拋出時標記、`library_group_management_dialog.dart` catch 時分派使用）。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 在既有 `"libraryGroupReservedNameError"` 的 `@` 描述區塊（第 88-96 行）之後、`"libraryMoveToGroupTitle"`（第 97 行）之前插入：

```json
  "libraryGroupNameAlreadyExistsError": "分類「{name}」已存在，請使用其他名稱",
  "@libraryGroupNameAlreadyExistsError": {
    "description": "重新命名分類時，新名稱與既有分類撞名時顯示的錯誤訊息，{name} 為使用者嘗試使用的新名稱",
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
```

`app_zh_CN.arb`（既有 `"libraryGroupReservedNameError"` 位於第 21 行，`"libraryMoveToGroupTitle"` 位於第 22 行）插入：

```json
  "libraryGroupNameAlreadyExistsError": "分类「{name}」已存在，请使用其他名称",
```

`app_en.arb`（既有 `"libraryGroupReservedNameError"` 位於第 21 行，`"libraryMoveToGroupTitle"` 位於第 22 行）插入：

```json
  "libraryGroupNameAlreadyExistsError": "\"{name}\" already exists. Please use a different name.",
```

`app_zh.arb`（結構與 `app_zh_CN.arb`/`app_en.arb` 相同，無 `@` 描述區塊，既有 `"libraryGroupReservedNameError"` 位於第 21 行）插入：

```json
  "libraryGroupNameAlreadyExistsError": "分類「{name}」已存在，請使用其他名稱",
```

- [ ] **Step 2: 執行 `flutter gen-l10n` 確認 ARB 語法正確**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤輸出，`lib/l10n/app_localizations*.dart` 新增 `String libraryGroupNameAlreadyExistsError(String name);`（位置參數）。

- [ ] **Step 3: `library_repository.dart` 新增例外分類列舉**

在 `app/lib/library/library_repository.dart` 找到既有：

```dart
/// `LibraryRepository` 操作違反資料規則時拋出（例如嘗試刪除/重新命名系統
/// 保留的「未分類」群組、或重新命名為已存在的群組名稱）。
class LibraryRepositoryException implements Exception {
  final String message;
  const LibraryRepositoryException(this.message);

  @override
  String toString() => 'LibraryRepositoryException: $message';
}
```

改為：

```dart
/// [LibraryRepositoryException] 的語意分類，供呼叫端（表現層）對應正確的
/// `AppLocalizations` 訊息（epic-45-interface-i18n Issue 7，`spec.md` §6：
/// 服務層例外訊息本身只作診斷用途，使用者可見文字一律由表現層依這個分類
/// 對應在地化字串，不可直接顯示 [LibraryRepositoryException.message]）。
enum LibraryRepositoryErrorReason {
  /// 嘗試重新命名系統保留群組「未分類」——UI 層已由 [isReservedGroupName]
  /// 攔截在呼叫本函式之前，此分支理論上不可達，僅作防禦。
  reservedGroupRename,

  /// 嘗試刪除系統保留群組「未分類」——同上，理論上不可達，僅作防禦。
  reservedGroupDelete,

  /// 重新命名的目標名稱與既有分類撞名——UI 層無事前檢查，可達路徑。
  duplicateGroupName,

  /// 未分類的其他情況（保留給未來擴充，目前無拋出點使用）。
  unknown,
}

/// `LibraryRepository` 操作違反資料規則時拋出（例如嘗試刪除/重新命名系統
/// 保留的「未分類」群組、或重新命名為已存在的群組名稱）。[message] 僅供
/// 診斷/日誌用途（例如 `debugPrint`），**不可**直接顯示給使用者——使用者
/// 可見文字由呼叫端依 [reason] 對應 `AppLocalizations`。
class LibraryRepositoryException implements Exception {
  final String message;
  final LibraryRepositoryErrorReason reason;
  const LibraryRepositoryException(
    this.message, {
    this.reason = LibraryRepositoryErrorReason.unknown,
  });

  @override
  String toString() => 'LibraryRepositoryException($reason): $message';
}
```

- [ ] **Step 4: `sqlite_library_repository.dart` 三個拋出點補上 `reason`**

在 `app/lib/library/sqlite_library_repository.dart` 找到既有：

```dart
  @override
  Future<void> renameGroup(String oldName, String newName) async {
    if (oldName == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可重新命名');
    }
    await _db.transaction((txn) async {
      final existing =
          await txn.query('groups', where: 'name = ?', whereArgs: [newName]);
      if (existing.isNotEmpty) {
        throw LibraryRepositoryException('分類「$newName」已存在');
      }
```

改為：

```dart
  @override
  Future<void> renameGroup(String oldName, String newName) async {
    if (oldName == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
        '系統保留群組「${BookGroup.uncategorized}」不可重新命名',
        reason: LibraryRepositoryErrorReason.reservedGroupRename,
      );
    }
    await _db.transaction((txn) async {
      final existing =
          await txn.query('groups', where: 'name = ?', whereArgs: [newName]);
      if (existing.isNotEmpty) {
        throw LibraryRepositoryException(
          '分類「$newName」已存在',
          reason: LibraryRepositoryErrorReason.duplicateGroupName,
        );
      }
```

找到既有：

```dart
  @override
  Future<void> deleteGroup(String name) async {
    if (name == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可刪除');
    }
```

改為：

```dart
  @override
  Future<void> deleteGroup(String name) async {
    if (name == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
        '系統保留群組「${BookGroup.uncategorized}」不可刪除',
        reason: LibraryRepositoryErrorReason.reservedGroupDelete,
      );
    }
```

- [ ] **Step 5: `test/support/fake_library_repository.dart` 同步補上 `reason`（維持與正式實作行為一致）**

在 `app/test/support/fake_library_repository.dart` 找到既有：

```dart
  @override
  Future<void> renameGroup(String oldName, String newName) async {
    renameGroupCalls.add((oldName, newName));
    if (oldName == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可重新命名');
    }
    if (_groups.contains(newName)) {
      throw LibraryRepositoryException('分類「$newName」已存在');
    }
```

改為：

```dart
  @override
  Future<void> renameGroup(String oldName, String newName) async {
    renameGroupCalls.add((oldName, newName));
    if (oldName == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
        '系統保留群組「${BookGroup.uncategorized}」不可重新命名',
        reason: LibraryRepositoryErrorReason.reservedGroupRename,
      );
    }
    if (_groups.contains(newName)) {
      throw LibraryRepositoryException(
        '分類「$newName」已存在',
        reason: LibraryRepositoryErrorReason.duplicateGroupName,
      );
    }
```

找到既有：

```dart
  @override
  Future<void> deleteGroup(String name) async {
    if (name == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可刪除');
    }
```

改為：

```dart
  @override
  Future<void> deleteGroup(String name) async {
    if (name == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
        '系統保留群組「${BookGroup.uncategorized}」不可刪除',
        reason: LibraryRepositoryErrorReason.reservedGroupDelete,
      );
    }
```

- [ ] **Step 6: 加強 `sqlite_library_repository_test.dart` 既有 3 個例外測試，一併驗證 `reason`**

在 `app/test/library/sqlite_library_repository_test.dart` 找到既有：

```dart
    test('deleteGroup 對「未分類」拋出例外', () async {
      expect(
        () => repository.deleteGroup('未分類'),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });
```

改為：

```dart
    test('deleteGroup 對「未分類」拋出例外，reason 為 reservedGroupDelete', () async {
      expect(
        () => repository.deleteGroup('未分類'),
        throwsA(
          isA<LibraryRepositoryException>().having(
            (e) => e.reason,
            'reason',
            LibraryRepositoryErrorReason.reservedGroupDelete,
          ),
        ),
      );
    });
```

找到既有：

```dart
    test('renameGroup 對「未分類」拋出例外', () async {
      expect(
        () => repository.renameGroup('未分類', '新名稱'),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });

    test('renameGroup 目標名稱已存在時拋出例外', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.upsertGroup('文言經典');

      expect(
        () => repository.renameGroup('古典奇幻', '文言經典'),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });
```

改為：

```dart
    test('renameGroup 對「未分類」拋出例外，reason 為 reservedGroupRename', () async {
      expect(
        () => repository.renameGroup('未分類', '新名稱'),
        throwsA(
          isA<LibraryRepositoryException>().having(
            (e) => e.reason,
            'reason',
            LibraryRepositoryErrorReason.reservedGroupRename,
          ),
        ),
      );
    });

    test('renameGroup 目標名稱已存在時拋出例外，reason 為 duplicateGroupName', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.upsertGroup('文言經典');

      expect(
        () => repository.renameGroup('古典奇幻', '文言經典'),
        throwsA(
          isA<LibraryRepositoryException>().having(
            (e) => e.reason,
            'reason',
            LibraryRepositoryErrorReason.duplicateGroupName,
          ),
        ),
      );
    });
```

- [ ] **Step 7: 執行測試確認失敗（`reason` 欄位尚不存在）**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart`
Expected: 編譯錯誤（`LibraryRepositoryErrorReason`／`reason` getter 尚未定義）。

- [ ] **Step 8: `library_group_management_dialog.dart` 三個 catch 分支改為依 `reason` 對應在地化字串**

在 `app/lib/screens/library_group_management_dialog.dart` 找到既有：

```dart
    try {
      await widget.repository.upsertGroup(name);
      if (!mounted) return;
      _addController.clear();
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
```

改為：

```dart
    try {
      await widget.repository.upsertGroup(name);
      if (!mounted) return;
      _addController.clear();
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      if (!mounted) return;
      debugPrint('新增分類「$name」失敗: ${e.message}');
      setState(() => _errorMessage = l10n.errorOperationFailed);
    } catch (_) {
```

找到既有：

```dart
    try {
      await widget.repository.renameGroup(oldName, newName);
      if (!mounted) return;
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
```

改為：

```dart
    try {
      await widget.repository.renameGroup(oldName, newName);
      if (!mounted) return;
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      if (!mounted) return;
      debugPrint('重新命名分類「$oldName」為「$newName」失敗: ${e.message}');
      setState(
        () => _errorMessage =
            e.reason == LibraryRepositoryErrorReason.duplicateGroupName
                ? l10n.libraryGroupNameAlreadyExistsError(newName)
                : l10n.errorOperationFailed,
      );
    } catch (_) {
```

找到既有：

```dart
    try {
      await widget.repository.deleteGroup(name);
      if (!mounted) return;
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
```

改為：

```dart
    try {
      await widget.repository.deleteGroup(name);
      if (!mounted) return;
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      if (!mounted) return;
      debugPrint('刪除分類「$name」失敗: ${e.message}');
      setState(() => _errorMessage = l10n.errorOperationFailed);
    } catch (_) {
```

- [ ] **Step 9: 更新既有測試斷言**

在 `app/test/screens/library_group_management_dialog_test.dart` 找到既有：

```dart
    final errorText = tester.widget<Text>(find.text('分類「B」已存在'));
    expect(errorText.style?.color, theme.colorScheme.error);
```

改為：

```dart
    final errorText = tester.widget<Text>(find.text('分類「B」已存在，請使用其他名稱'));
    expect(errorText.style?.color, theme.colorScheme.error);
```

- [ ] **Step 10: 新增英文介面驗證測試**

在 `app/test/screens/library_group_management_dialog_test.dart` 同一個 `testWidgets('重新命名為已存在的分類名稱時，錯誤訊息文字色為 colorScheme.error', ...)` 之後新增：

```dart
  testWidgets('英文介面下，重新命名撞名顯示英文固定訊息（不含伺服器原始診斷文字）',
      (tester) async {
    final repository = FakeLibraryRepository();
    await repository.upsertGroup('A');
    await repository.upsertGroup('B');
    final groups = await repository.listGroups();

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      locale: const Locale('en'),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_rename_button_A')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('library_group_rename_field')), 'B');
    await tester.tap(find.byKey(const Key('library_group_rename_confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('"B" already exists. Please use a different name.'),
      findsOneWidget,
    );
  });
```

- [ ] **Step 11: 執行測試確認全數通過**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart test/screens/library_group_management_dialog_test.dart`
Expected: 全數 PASS。

- [ ] **Step 12: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/library/library_repository.dart lib/library/sqlite_library_repository.dart lib/screens/library_group_management_dialog.dart test/support/fake_library_repository.dart test/library/sqlite_library_repository_test.dart test/screens/library_group_management_dialog_test.dart`
Expected: `No issues found!`

- [ ] **Step 13: Commit**

```bash
git add app/lib/library/library_repository.dart app/lib/library/sqlite_library_repository.dart \
  app/lib/screens/library_group_management_dialog.dart \
  app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb \
  app/lib/l10n/app_localizations.dart app/lib/l10n/app_localizations_en.dart app/lib/l10n/app_localizations_zh.dart \
  app/test/support/fake_library_repository.dart \
  app/test/library/sqlite_library_repository_test.dart app/test/screens/library_group_management_dialog_test.dart
git commit -m "feat(epic-45): 分類重新命名/刪除例外訊息改為依 reason 對應在地化文字"
```

---

### Task 4: `reader_screen.dart`——移除既有 3 個 ARB key 的 `{error}` placeholder 反模式

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：無新增依賴。
- Produces：既有 3 個 ARB key 簽章由 `String Function(String error)` 收窄為固定 `String` getter：`readerSaveAsPresetFailedMessage`／`readerApplyPresetFailedMessage`／`readerDeletePresetFailedMessage`（皆為既有 key，供 4 個既有呼叫點使用，簽章變更不影響任何其他呼叫端——已用 `grep -rn` 確認全專案僅 `reader_screen.dart` 這 4 處呼叫）。

- [ ] **Step 1: 移除 3 個 key 的 `{error}` placeholder（四語言）**

`app_zh_TW.arb` 找到既有：

```json
  "readerSaveAsPresetFailedMessage": "另存為新預設集失敗：{error}",
  "@readerSaveAsPresetFailedMessage": {
    "description": "另存為新預設集過程發生例外時顯示的 SnackBar 訊息，{error} 為例外物件的字串表示",
    "placeholders": {
      "error": {
        "type": "String"
      }
    }
  },
```

改為：

```json
  "readerSaveAsPresetFailedMessage": "另存為新預設集失敗",
  "@readerSaveAsPresetFailedMessage": {
    "description": "另存為新預設集過程發生例外時顯示的固定 SnackBar 訊息（不含例外原始文字，技術細節已由呼叫端 debugPrint() 記錄，見 epic-45-interface-i18n Issue 7）"
  },
```

找到既有：

```json
  "readerApplyPresetFailedMessage": "套用版面設定失敗：{error}",
  "@readerApplyPresetFailedMessage": {
    "description": "套用版面設定（來自預設集或來自其他書籍）過程發生例外時顯示的 SnackBar 訊息，{error} 為例外物件的字串表示，兩處呼叫端共用",
    "placeholders": {
      "error": {
        "type": "String"
      }
    }
  },
```

改為：

```json
  "readerApplyPresetFailedMessage": "套用版面設定失敗",
  "@readerApplyPresetFailedMessage": {
    "description": "套用版面設定（來自預設集或來自其他書籍）過程發生例外時顯示的固定 SnackBar 訊息（不含例外原始文字，技術細節已由呼叫端 debugPrint() 記錄，見 epic-45-interface-i18n Issue 7），兩處呼叫端共用"
  },
```

找到既有：

```json
  "readerDeletePresetFailedMessage": "刪除預設集失敗：{error}",
  "@readerDeletePresetFailedMessage": {
    "description": "刪除預設集過程發生例外時顯示的 SnackBar 訊息，{error} 為例外物件的字串表示",
    "placeholders": {
      "error": {
        "type": "String"
      }
    }
  },
```

改為：

```json
  "readerDeletePresetFailedMessage": "刪除預設集失敗",
  "@readerDeletePresetFailedMessage": {
    "description": "刪除預設集過程發生例外時顯示的固定 SnackBar 訊息（不含例外原始文字，技術細節已由呼叫端 debugPrint() 記錄，見 epic-45-interface-i18n Issue 7）"
  },
```

`app_zh_CN.arb`（同樣位於第 321/328/331 行，無 `@` 描述區塊）依序找到並改為：

```json
  "readerSaveAsPresetFailedMessage": "另存为新预设集失败",
  "readerApplyPresetFailedMessage": "套用版面设定失败",
  "readerDeletePresetFailedMessage": "删除预设集失败",
```

`app_en.arb`（第 321/328/331 行）依序找到並改為：

```json
  "readerSaveAsPresetFailedMessage": "Failed to save new preset",
  "readerApplyPresetFailedMessage": "Failed to apply layout settings",
  "readerDeletePresetFailedMessage": "Failed to delete preset",
```

`app_zh.arb`（第 321/328/331 行）依序找到並改為：

```json
  "readerSaveAsPresetFailedMessage": "另存為新預設集失敗",
  "readerApplyPresetFailedMessage": "套用版面設定失敗",
  "readerDeletePresetFailedMessage": "刪除預設集失敗",
```

- [ ] **Step 2: 執行 `flutter gen-l10n` 確認 ARB 語法正確**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤輸出，3 個 key 於 `app_localizations.dart` 由 `String Function(String)` 變為 `String` getter。

- [ ] **Step 3: 修改 4 處呼叫點**

在 `app/lib/screens/reader_screen.dart` 找到既有：

```dart
          content: Text(l10n.readerSaveAsPresetFailedMessage('$e')),
```

改為：

```dart
          content: Text(l10n.readerSaveAsPresetFailedMessage),
```

找到既有（共 2 處，`replace_all` 一次處理）：

```dart
          content: Text(AppLocalizations.of(context)!.readerApplyPresetFailedMessage('$e')),
```

改為：

```dart
          content: Text(AppLocalizations.of(context)!.readerApplyPresetFailedMessage),
```

找到既有：

```dart
          content: Text(AppLocalizations.of(context)!.readerDeletePresetFailedMessage('$e')),
```

改為：

```dart
          content: Text(AppLocalizations.of(context)!.readerDeletePresetFailedMessage),
```

（`debugPrint('...: $e\n$stackTrace')` 三處既有呼叫**不變**——技術細節記錄機制本來就已經存在，本 Task 只移除「同時又把 `$e` 塞進使用者可見文字」這個重複/違規部分。）

- [ ] **Step 4: 新增迴歸驗證測試——確認 SnackBar 文字不含模擬例外的原始文字**

在 `app/test/screens/reader_screen_test.dart` 找到既有斷言（約第 8763 行）：

```dart
      expect(
        find.byKey(const Key('reader_save_as_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
```

改為：

```dart
      expect(
        find.byKey(const Key('reader_save_as_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(find.text('另存為新預設集失敗'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
```

在同檔案找到既有斷言（約第 8860 行，該 `testWidgets` 內第一處）：

```dart
      expect(
        find.byKey(const Key('reader_apply_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
```

改為：

```dart
      expect(
        find.byKey(const Key('reader_apply_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(find.text('套用版面設定失敗'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
```

在同檔案找到既有斷言（約第 8998 行）：

```dart
      expect(
        find.byKey(const Key('reader_delete_preset_error_snackbar')),
        findsOneWidget,
      );
```

改為：

```dart
      expect(
        find.byKey(const Key('reader_delete_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(find.text('刪除預設集失敗'), findsOneWidget);
```

（第 9127 行第二處 `reader_apply_preset_error_snackbar` 斷言維持不變，避免與上一個測試重複斷言相同文字內容——`findsOneWidget` 已足夠確認 SnackBar 顯示，Key 斷言本身已是既有迴歸覆蓋，不強制每處都補文字斷言。）

- [ ] **Step 5: 新增英文 ARB 驗證測試**

上一步驟只補強了 `reader_screen_test.dart`（預設釘定 `zh_TW`）的繁中斷言；該檔案逾 11,000 行、全數為 `testWidgets`，額外 pump 一次英文版 `ReaderScreen` 只為驗證 3 個固定字串會顯著拉長測試耗時，不成比例。改在同檔案 `main()` 內、第一個既有 `group(...)`（第 182 行 `'epic-10-search Issue 5：initialJumpTarget 覆寫初始定位'`）之前，新增一個獨立的純 Dart `test()`（`lookupAppLocalizations()` 同步取得英文 `AppLocalizations` 實例，不需要 pump 任何 widget，比照 `spec.md` §7 已定案的純 Dart 單元測試取得 l10n 實例的既定作法）：

```dart
  test('reader_screen 版面預設集錯誤訊息英文 ARB 驗證（{error} placeholder 移除後的固定文字）',
      () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(l10n.readerSaveAsPresetFailedMessage, 'Failed to save new preset');
    expect(l10n.readerApplyPresetFailedMessage, 'Failed to apply layout settings');
    expect(l10n.readerDeletePresetFailedMessage, 'Failed to delete preset');
  });
```

- [ ] **Step 6: 執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "預設集"`
Expected: 全數 PASS（既有 3 個測試補強斷言內容，另新增 1 個純 Dart 單元測試）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/reader_screen.dart test/screens/reader_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/reader_screen.dart \
  app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb \
  app/lib/l10n/app_localizations.dart app/lib/l10n/app_localizations_en.dart app/lib/l10n/app_localizations_zh.dart \
  app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-45): reader_screen.dart 移除版面預設集錯誤訊息的 {error} placeholder 反模式"
```

---

### Task 5: 最終驗證與文件收尾

**Files:**
- Modify: `docs/epics/epic-45-interface-i18n/issues.md`（標記 Issue 7 為 completed，記錄範圍修正）
- Modify: `docs/epics/epic-45-interface-i18n/epic.md`（新增 Issue 7 完成記錄）
- Modify: `docs/epics.md`（更新 epic-45 備註）

**Interfaces:**
- Consumes：Task 1-4 全部完成的狀態。
- Produces：Issue 7 完整收尾，供人類決定發 PR／合併。

- [ ] **Step 1: 執行完整 `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 執行完整 `flutter test`**

Run: `cd app && flutter test`
Expected: 全數通過，較 Issue 6 收尾時記錄的 2744 passed 增加（本 Issue 新增測試數＝Task 1 Step 2(5，含 review-plan-issue-7.md I-2 補上的 `[null]`／純空白字串兩個邊界案例)＋Task 1 Step 7(1 新增英文測試)＋Task 2 Step 2(1 新增英文測試)＋Task 3 Step 10(1 新增英文測試)＋Task 4 Step 5(1 新增純 Dart 英文 ARB 驗證測試，見 I-3)＝9 個；Task 3 Step 6 僅為既有 3 個測試補強 `reason` 斷言，非新增測試案例)，無既有測試因本 Issue 回歸。

- [ ] **Step 3: 確認 `reader_console_log.dart`／`library_repository.dart` 公開介面型別零非預期異動**

Run: `git diff main -- app/lib/reader/reader_console_log.dart`
Expected: 空 diff（本 Issue 只**呼叫**既有 `ReaderConsoleLog.add()`，不修改該類別本身）。

- [ ] **Step 4: 更新 `issues.md`**

在 Issue 7 段落（`## Issue 7：執行期例外訊息在地化` 之後）新增：

```markdown
**Status:** completed

**實際執行範圍修正記錄（認領時逐檔通讀＋呼叫鏈追蹤）**：`design.md`/`issues.md` 原始列出的 14 個檔案是在 Issue 3-6 完成前盤點的，逐一核實後確認其中 10 個檔案（`sync_settings_screen.dart`／`wifi_transfer_screen.dart` 已於 Issue 5/6 完全在地化；`opds_http_client.dart`／`sync_engine.dart`／`book_import_service_impl.dart`／`search_repository.dart`／`reader_jump_target.dart`／`custom_fonts_repository.dart`／`txt_charset_detection.dart`／`md_frontmatter.dart`／`kf8_metadata.dart` 皆為服務層例外，唯一呼叫端一律 `catch (_)` 泛用吞掉或已有既存泛用在地化訊息代打，訊息內容從未真正顯示給使用者）不需要本 Issue 處理；實際處理 `sqlite_library_repository.dart`／`reader_screen.dart`（既有清單內）與新發現、透過呼叫鏈追蹤補記歸屬的 `pdf_reader_view.dart`（`foliate_reader_view.dart` 的 PDF 對應檔案，同一類「開書失敗顯示原始例外文字」缺陷）／`library_group_management_dialog.dart`（`sqlite_library_repository.dart` 拋出例外的唯一呼叫端，Issue 2 完成當下未涵蓋這 3 個 catch 分支）共 4 個檔案。`foliate_reader_view.dart`／`pdf_reader_view.dart` 皆重用既有 `readerFailedToLoadBookMessage` key（不新增），`library_group_management_dialog.dart` 新增 1 個 ARB key（`libraryGroupNameAlreadyExistsError`），`reader_screen.dart` 移除既有 3 個 key 的 `{error}` placeholder 反模式（Issue 4 遺留）。ARB 由 539 個 key 增至 540 個。
```

（若 `Status:` 欄位已存在則直接改值為 `completed`，不重複新增欄位。）

- [ ] **Step 5: 更新 `epic.md`**

在 `docs/epics/epic-45-interface-i18n/epic.md` 檔尾新增：

```markdown

**<今日日期> 完成 Issue 7 實作（`plans/plan-issue-7.md` 5 個 Task 全數落地）**：執行期例外訊息在地化——重新逐檔通讀＋追蹤呼叫鏈後確認，`issues.md` 原始列出的 14 個檔案中有 10 個已於 Issue 3-6 順帶在地化完畢或例外訊息從未真正顯示給使用者（服務層拋出、呼叫端一律泛用吞掉），不需處理；實際處理 4 個檔案：`foliate_reader_view.dart`（EPUB 開書快取失敗＋JS bridge 錯誤訊息，抽出頂層純函式 `resolveFoliateOpenBookErrorMessage()` 獨立測試）、`pdf_reader_view.dart`（PDF 開書失敗，原清單未列入、經呼叫鏈追蹤補記歸屬，`_openDocument()` catch 原本直接 `widget.onError(e.toString())` 是本 Issue 掃描範圍內最直接的 spec §6 違規）——兩者皆重用既有 `readerFailedToLoadBookMessage` key，不新增 ARB；`sqlite_library_repository.dart`／`library_group_management_dialog.dart`（分類重新命名/刪除例外，`LibraryRepositoryException` 新增 `LibraryRepositoryErrorReason` 列舉欄位取代直接顯示 `e.message`，新增 1 個 ARB key `libraryGroupNameAlreadyExistsError`）；`reader_screen.dart`（移除 Issue 4 遺留的 3 個 ARB key `{error}` placeholder 反模式，4 處呼叫點皆已有既存 `debugPrint()` 記錄技術細節，只是同時又把 `'$e'` 重複塞進使用者可見文字）。全部被移除的原始例外文字皆改寫入既有診斷管道（`ReaderConsoleLog.add()`／`debugPrint()`），技術除錯能力不受影響。ARB 新增 1 個 key（539→540）。驗證結果：`flutter analyze` 乾淨（`No issues found!`）、全套 `flutter test` 通過（本 Issue 觸及的測試檔全數綠燈）。下一步：認領 Issue 8（Markdown 匯出契約變更）或 Issue 9（收斂清理）。
```

- [ ] **Step 6: 更新 `docs/epics.md`**

找到 `epic-45-interface-i18n` 該列，把備註欄位：

```
| 46 | `epic-45-interface-i18n` 多語系介面（正體中文／簡體中文／英文，FR-49） | 🟡 開發中 (Active) | Issue 0／1／2／3／4／5／6 已完成，待認領 Issue 7 |
```

改為：

```
| 46 | `epic-45-interface-i18n` 多語系介面（正體中文／簡體中文／英文，FR-49） | 🟡 開發中 (Active) | Issue 0-7 已完成，待認領 Issue 8 |
```

- [ ] **Step 7: Commit**

```bash
git add docs/epics/epic-45-interface-i18n/issues.md docs/epics/epic-45-interface-i18n/epic.md docs/epics.md
git commit -m "docs(epic-45): 標記 Issue 7 為 completed，記錄實際執行範圍修正並更新 epic.md/epics.md"
```
