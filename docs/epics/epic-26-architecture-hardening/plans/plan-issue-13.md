# 收斂重複三次的 JS 請求／回應樣板 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `app/lib/reader/foliate_reader_view.dart` 裡「發一個 JS 請求、等 JS 呼叫 handler 回來、完成 Completer」這個重複三次的樣板（TOC／TTS 朗讀段清單／TTS 朗讀段索引），收斂成一個獨立、不依賴 `InAppWebViewController` 具體型別、可被 Dart 單元測試直接驗證的深模組 `JsBridgeGateway`。

**Architecture：** 新增獨立檔案 `app/lib/reader/js_bridge_gateway.dart`，定義 `JsBridgeGateway` 類別——建構時收兩個注入函式（`evaluate`／`registerHandler`），不直接依賴 `InAppWebViewController`，讓它可以脫離真正的 WebView 環境被單元測試。`foliate_reader_view.dart` 的三個 `_requestXxx` 方法各自縮成呼叫 `_gateway.request<T>()` 的薄包裝；三個獨立的 `Completer` 欄位、三組 `addJavaScriptHandler` 註冊，改由 `JsBridgeGateway` 內部的 `Map` 統一管理。對外公開 API（`FoliateReaderView.loadTableOfContents`／`loadTtsSegments`／`lookupSegmentByCfi`）簽章與行為不變。

**Tech Stack：** Dart（`dart:async` `Completer`／`Future.timeout`）、`flutter_test`、`package:fake_async`（既有 dev dependency，測逾時行為）。

**Spec：** `docs/epics/epic-26-architecture-hardening/issues.md` Issue 13（把重複三次的 JS 請求／回應樣板收斂成 `JsBridgeGateway`）；設計細節出自 2026-08-30 `/diagnose` 查驗＋`/grilling` 會談，背景報告見 `docs/research/architecture-review-epic34-tts.md` 候選 2。

## Global Constraints

- 所有程式碼註解、commit message 一律使用正體中文（CLAUDE.md）。
- 測試執行範圍：每個 Task 只需要跑「這次異動實際觸及」的測試，不需要每次都跑全套 `flutter test`；完整 `flutter test`（無參數）只在本計畫最後一個 Task 完成時跑一次。
- 對外公開 API（`FoliateReaderView.loadTableOfContents`／`loadTtsSegments`／`lookupSegmentByCfi`，`foliate_reader_view.dart:516-549`）簽章與行為維持零改動，呼叫端（`reader_screen.dart`／`TtsController`）零改動。
- 除了 Issue 13 明確決議新增的 `parse()` 例外防護（見下方 Task 1 Step 3）之外，本計畫為純重構，不改變其他任何既有行為——特別是：TOC 請求維持不設逾時（`timeout: null`）；同型別重複請求互相覆蓋導致舊 `Completer` 永遠不會被 complete 的既有限制，原封不動搬移，不在本計畫修正（`/grilling` 決策，留給未來獨立 Issue）。
- `JsBridgeGateway` 不得依賴 `InAppWebViewController` 具體型別，只能透過建構子注入的 `evaluate`／`registerHandler` 兩個函式與外界溝通，確保可被純 Dart 單元測試涵蓋而不需要真正的 WebView 環境（`flutter_inappwebview` 目前沒有可用的假 controller 能模擬 JS handler 回呼，見 `app/test/support/fake_inappwebview_platform.dart`）。

---

### Task 1：新增 `JsBridgeGateway` 純類別與單元測試

**Files:**
- Create: `app/lib/reader/js_bridge_gateway.dart`
- Create: `app/test/reader/js_bridge_gateway_test.dart`

**Interfaces:**
- Produces：
  - `JsBridgeGateway({required void Function(String js) evaluate, required void Function(String handlerName, dynamic Function(List<dynamic> args) callback) registerHandler})`——建構子。
  - `void register<T>({required String handlerName, required T Function(List<dynamic> args) parse, required T fallback})`——設定期呼叫一次，註冊某個請求類型的 handler、解析方式與 fallback 值。
  - `Future<T> request<T>({required String jsCall, required String handlerName, Duration? timeout})`——每次請求呼叫一次，回傳 `Future<T>`。`timeout` 為 `null` 時不設逾時上限；設定時，逾時後退回 `register()` 當初登記的 fallback 值。
  - Task 2 會匯入並使用這三個成員。

- [ ] **Step 1: 寫測試腳本（先寫完整份，涵蓋四種情境）**

建立 `app/test/reader/js_bridge_gateway_test.dart`：

```dart
import 'dart:async';

import 'package:elinkbook/reader/js_bridge_gateway.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsBridgeGateway', () {
    test('request() 在對應 handler 回呼後正確完成，且真的呼叫了 evaluate', () async {
      final evaluatedCalls = <String>[];
      void Function(List<dynamic> args)? registeredCallback;
      final gateway = JsBridgeGateway(
        evaluate: (js) => evaluatedCalls.add(js),
        registerHandler: (name, callback) {
          expect(name, 'onFooReady');
          registeredCallback = callback;
        },
      );
      gateway.register<String>(
        handlerName: 'onFooReady',
        parse: (args) => args[0] as String,
        fallback: '',
      );

      final future = gateway.request<String>(
        jsCall: 'window.foo()',
        handlerName: 'onFooReady',
      );

      // evaluate 必須在 request() 呼叫的當下同步執行，不等 handler 回呼。
      expect(evaluatedCalls, ['window.foo()']);

      registeredCallback!(['bar']);

      expect(await future, 'bar');
    });

    test('設有逾時的請求，時限內未收到 handler 回呼時退回 register() 登記的 fallback；'
        '逾時後遲到的回呼不會拋出例外、也不會覆蓋已確定的結果', () {
      fakeAsync((async) {
        void Function(List<dynamic> args)? registeredCallback;
        final gateway = JsBridgeGateway(
          evaluate: (_) {},
          registerHandler: (name, callback) => registeredCallback = callback,
        );
        gateway.register<int>(
          handlerName: 'onBarReady',
          parse: (args) => args[0] as int,
          fallback: -1,
        );

        int? result;
        gateway
            .request<int>(
              jsCall: 'window.bar()',
              handlerName: 'onBarReady',
              timeout: const Duration(seconds: 5),
            )
            .then((value) => result = value);

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        expect(result, -1);

        // 逾時當下 _pending 裡的 Completer 已被移除；這裡模擬 JS 端遲到
        // 才送達的回呼，驗證不會拋出未處理例外，也不會把已經確定的
        // fallback 結果覆蓋掉（register() 內的
        // `if (completer == null) return null;` 防呆生效）。
        registeredCallback!([999]);
        async.flushMicrotasks();

        expect(result, -1);
      });
    });

    test('timeout 為 null 時不會被逾時機制打斷，只在 handler 真的回呼後才完成', () {
      fakeAsync((async) {
        void Function(List<dynamic> args)? registeredCallback;
        final gateway = JsBridgeGateway(
          evaluate: (_) {},
          registerHandler: (name, callback) => registeredCallback = callback,
        );
        gateway.register<List<String>>(
          handlerName: 'onBazReady',
          parse: (args) => (args[0] as List).cast<String>(),
          fallback: const [],
        );

        List<String>? result;
        gateway
            .request<List<String>>(
              jsCall: 'window.baz()',
              handlerName: 'onBazReady',
            )
            .then((value) => result = value);

        // 沒有設逾時：等再久也不該被打斷、也不該提前完成。
        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();
        expect(result, isNull);

        registeredCallback!([
          ['a', 'b']
        ]);
        async.flushMicrotasks();

        expect(result, ['a', 'b']);
      });
    });

    test('parse 拋出例外時立即退回 fallback，不需要等逾時', () {
      fakeAsync((async) {
        void Function(List<dynamic> args)? registeredCallback;
        final gateway = JsBridgeGateway(
          evaluate: (_) {},
          registerHandler: (name, callback) => registeredCallback = callback,
        );
        gateway.register<int>(
          handlerName: 'onBrokenReady',
          parse: (args) => throw const FormatException('模擬 JS 端回傳的 JSON 格式損壞'),
          fallback: -1,
        );

        int? result;
        gateway
            .request<int>(
              jsCall: 'window.broken()',
              handlerName: 'onBrokenReady',
              timeout: const Duration(seconds: 5),
            )
            .then((value) => result = value);

        registeredCallback!(['this triggers parse() to throw']);
        async.flushMicrotasks();

        // 還沒經過 5 秒逾時，就已經拿到 fallback——證明是 parse() 例外
        // 防護生效，不是靠逾時機制救回來的。
        expect(result, -1);
      });
    });
  });
}
```

- [ ] **Step 2: 執行測試腳本確認它會失敗**

執行（於 `app/` 目錄下）：`flutter test test/reader/js_bridge_gateway_test.dart`

預期結果：因為 `package:elinkbook/reader/js_bridge_gateway.dart` 還不存在，編譯失敗（`Error: Error when reading '...js_bridge_gateway.dart': No such file or directory` 或等效訊息），非全數通過。

- [ ] **Step 3: 建立 `js_bridge_gateway.dart` 實作**

建立 `app/lib/reader/js_bridge_gateway.dart`：

```dart
import 'dart:async';

/// 收斂「發一個 JS 請求、等 JS 呼叫 handler 回來、完成 Completer」這個
/// 重複樣板的深模組（epic-26-architecture-hardening Issue 13）。不直接
/// 依賴 InAppWebViewController，改收 [evaluate]／[registerHandler] 兩個
/// 注入函式，讓這個類別可以脫離真正的 WebView 環境被單元測試——現有的
/// `fake_inappwebview_platform.dart` 沒有能力模擬 JS handler 回呼，這是
/// 過去三個 `_requestXxx` 完全沒有 Dart 測試涵蓋的根本原因。
class JsBridgeGateway {
  JsBridgeGateway({
    required this.evaluate,
    required this.registerHandler,
  });

  /// 實際執行一段 JS 程式碼的注入函式。呼叫端通常是
  /// `(js) => controller?.evaluateJavascript(source: js)`——忽略回傳值，
  /// 回應資料一律由 JS 端主動呼叫對應 handler 取得，不透過
  /// evaluateJavascript 本身的回傳值。
  final void Function(String js) evaluate;

  /// 掛一個具名 JS→Dart handler 的注入函式。呼叫端通常是
  /// `(name, callback) => controller.addJavaScriptHandler(handlerName: name, callback: callback)`。
  final void Function(
    String handlerName,
    dynamic Function(List<dynamic> args) callback,
  ) registerHandler;

  final Map<String, Completer<dynamic>> _pending = {};
  final Map<String, dynamic> _fallbackByHandler = {};

  /// 設定期呼叫一次（每種請求類型各呼叫一次）：註冊 [handlerName] 對應
  /// 的 JS handler，記錄「怎麼把回傳的 args 解析成 [T]」（[parse]）與
  /// 「解析失敗或逾時時要退回的值」（[fallback]）。
  void register<T>({
    required String handlerName,
    required T Function(List<dynamic> args) parse,
    required T fallback,
  }) {
    _fallbackByHandler[handlerName] = fallback;
    registerHandler(handlerName, (args) {
      final completer = _pending.remove(handlerName);
      if (completer == null) return null;
      try {
        completer.complete(parse(args));
      } catch (_) {
        // 例如 JS 端回傳的 JSON 格式意外損壞——parse() 拋出的例外若不在
        // 這裡攔截，會被 flutter_inappwebview 的 method channel 邊界吞掉
        // （已查證：不會讓 App crash，但 completer 永遠不會被 complete，
        // 呼叫端的 await 會無限期卡住；若這個請求類型沒有設 timeout，
        // 沒有其他機制能救回來）。這是本次重構額外新增的防護，非單純
        // 從 foliate_reader_view.dart 搬移過來的既有行為。
        completer.complete(fallback);
      }
      return null;
    });
  }

  /// 每次請求呼叫一次：發出 [jsCall]，等 [handlerName] 對應的 handler
  /// 回呼完成。[timeout] 為 `null` 表示不設逾時上限（原樣等待，對應
  /// TOC 目前的既有行為）；設定逾時時，逾時後退回 [register] 當初登記
  /// 的 fallback 值。
  Future<T> request<T>({
    required String jsCall,
    required String handlerName,
    Duration? timeout,
  }) {
    assert(
      _fallbackByHandler.containsKey(handlerName),
      'Handler "$handlerName" 尚未透過 register() 註冊 fallback 值',
    );
    final completer = Completer<T>();
    _pending[handlerName] = completer;
    evaluate(jsCall);
    final future = completer.future;
    if (timeout == null) return future;
    return future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(handlerName);
        return _fallbackByHandler[handlerName] as T;
      },
    );
  }
}
```

- [ ] **Step 4: 執行測試腳本確認全數通過**

執行（於 `app/` 目錄下）：`flutter test test/reader/js_bridge_gateway_test.dart`

預期結果：4 個測試全數通過（`All tests passed!`）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/reader/js_bridge_gateway.dart app/test/reader/js_bridge_gateway_test.dart
git commit -m "feat(epic-26): Issue 13 Task 1——新增 JsBridgeGateway 純類別"
```

---

### Task 2：`foliate_reader_view.dart` 接線改用 `JsBridgeGateway`

**Files:**
- Modify: `app/lib/reader/foliate_reader_view.dart:9-26`（新增 import）
- Modify: `app/lib/reader/foliate_reader_view.dart:608-611`（移除三個 Completer 欄位，新增 `_gateway` 欄位宣告）
- Modify: `app/lib/reader/foliate_reader_view.dart:688-727`（三個 `_requestXxx` 方法縮成薄包裝）
- Modify: `app/lib/reader/foliate_reader_view.dart:729-786`（`_onWebViewCreated` 內建構 `_gateway` 並改用 `register<T>()`，移除舊的三組 `addJavaScriptHandler`）
- Test: `app/test/reader/foliate_reader_view_test.dart`（僅執行既有測試確認零回歸，本 Task 不需要新增/修改任何測試案例——這三個私有方法目前完全沒有被任何既有測試直接涵蓋，見下方 Step 5 說明）

**Interfaces:**
- Consumes：Task 1 產出的 `JsBridgeGateway`（建構子、`register<T>()`、`request<T>()`）。

- [ ] **Step 1: 新增 import**

`foliate_reader_view.dart` 第 17-18 行目前為：

```dart
import 'foliate_bridge_codec.dart';
import 'foliate_native_bridge.dart';
```

改為：

```dart
import 'foliate_bridge_codec.dart';
import 'foliate_native_bridge.dart';
import 'js_bridge_gateway.dart';
```

- [ ] **Step 2: 移除三個 Completer 欄位，新增 `_gateway` 欄位宣告**

`foliate_reader_view.dart` 第 607-611 行目前為：

```dart
class _FoliateReaderViewState extends State<FoliateReaderView> {
  InAppWebViewController? _controller;
  Completer<List<TocEntry>>? _pendingToc;
  Completer<List<TtsSegmentCfi>>? _pendingTtsSegments;
  Completer<int>? _pendingTtsSegmentIndex;
```

改為（三個 Completer 欄位的生命週期已收進 `JsBridgeGateway` 內部的
`Map`，`_gateway` 在 `_onWebViewCreated()` 取得 `controller` 之後才建構，
見下方 Step 4）：

```dart
class _FoliateReaderViewState extends State<FoliateReaderView> {
  InAppWebViewController? _controller;
  late final JsBridgeGateway _gateway;
```

- [ ] **Step 3: 三個 `_requestXxx` 方法縮成薄包裝**

`foliate_reader_view.dart` 第 688-727 行目前為：

```dart
  Future<List<TocEntry>> _requestTableOfContents() {
    if (_controller == null) return Future.value(const []);
    final completer = Completer<List<TocEntry>>();
    _pendingToc = completer;
    _evaluate('window.getTableOfContents()');
    return completer.future;
  }

  Future<List<TtsSegmentCfi>> _requestTtsSegments(int sectionIndex) {
    if (_controller == null) return Future.value(const []);
    final completer = Completer<List<TtsSegmentCfi>>();
    _pendingTtsSegments = completer;
    _evaluate('window.buildTtsSegments($sectionIndex)');
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _pendingTtsSegments = null;
        return const [];
      },
    );
  }

  Future<int> _requestTtsSegmentIndex(
    String visibleCfi,
    List<String> segmentCfis,
  ) {
    if (_controller == null) return Future.value(0);
    final completer = Completer<int>();
    _pendingTtsSegmentIndex = completer;
    _evaluate(
      'window.lookupTtsSegmentIndex(${jsonEncode(visibleCfi)}, ${jsonEncode(segmentCfis)})',
    );
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _pendingTtsSegmentIndex = null;
        return 0;
      },
    );
  }
```

改為（`_controller == null` 的既有防呆保留在呼叫端——這是唯一知道
「WebView 是否已就緒」的地方，`JsBridgeGateway` 刻意不依賴
`InAppWebViewController`，不應該由它判斷這件事；行為與搬移前逐字一致）：

```dart
  Future<List<TocEntry>> _requestTableOfContents() {
    if (_controller == null) return Future.value(const []);
    return _gateway.request<List<TocEntry>>(
      jsCall: 'window.getTableOfContents()',
      handlerName: 'onTableOfContentsReady',
    );
  }

  Future<List<TtsSegmentCfi>> _requestTtsSegments(int sectionIndex) {
    if (_controller == null) return Future.value(const []);
    return _gateway.request<List<TtsSegmentCfi>>(
      jsCall: 'window.buildTtsSegments($sectionIndex)',
      handlerName: 'onTtsSegmentsReady',
      timeout: const Duration(seconds: 5),
    );
  }

  Future<int> _requestTtsSegmentIndex(
    String visibleCfi,
    List<String> segmentCfis,
  ) {
    if (_controller == null) return Future.value(0);
    return _gateway.request<int>(
      jsCall:
          'window.lookupTtsSegmentIndex(${jsonEncode(visibleCfi)}, ${jsonEncode(segmentCfis)})',
      handlerName: 'onTtsSegmentIndexReady',
      timeout: const Duration(seconds: 5),
    );
  }
```

- [ ] **Step 4: `_onWebViewCreated` 內建構 `_gateway` 並改用 `register<T>()`**

`foliate_reader_view.dart` 第 729-786 行目前為：

```dart
  Future<void> _onWebViewCreated(InAppWebViewController controller) async {
    _controller = controller;
    controller.addJavaScriptHandler(
      handlerName: 'onPageRendered',
      callback: (args) {
        widget.onPageRendered();
        final writingModeStr =
            args.isNotEmpty ? args[0] as String : 'horizontal';
        widget.onLayoutResolved?.call(EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: writingModeStr == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        ));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onError',
      callback: (args) {
        widget.onError(args.isNotEmpty ? args[0] as String : '未知錯誤');
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onLocatorChanged',
      // epic-26-architecture-hardening Issue 10：解析邏輯抽成
      // foliate_bridge_codec.dart 的 parseLocatorChanged() 純函式（比照
      // extractCfi()/parseTableOfContents() 既有慣例），可脫離 WebView
      // 直接單元測試，不再是這個 widget 內無法獨立驗證的匿名 closure。
      callback: (args) =>
          widget.onLocatorChanged?.call(parseLocatorChanged(args)),
    );
    controller.addJavaScriptHandler(
      handlerName: 'onTableOfContentsReady',
      callback: (args) {
        final completer = _pendingToc;
        _pendingToc = null;
        final json = args.isNotEmpty ? args[0] as String : '[]';
        completer?.complete(parseTableOfContents(json));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onTtsSegmentsReady',
      callback: (args) {
        final completer = _pendingTtsSegments;
        _pendingTtsSegments = null;
        final json = args.length > 1 ? args[1] as String : '[]';
        completer?.complete(parseTtsSegments(json));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onTtsSegmentIndexReady',
      callback: (args) {
        final completer = _pendingTtsSegmentIndex;
        _pendingTtsSegmentIndex = null;
        final index = args.isNotEmpty ? (args[0] as num).toInt() : 0;
        completer?.complete(index);
      },
    );
```

（後面接著 `onTtsHighlightOutOfSafeWindow` 等其餘 handler 註冊，與本次
改動無關，維持不動。）

改為（`onTableOfContentsReady`／`onTtsSegmentsReady`／
`onTtsSegmentIndexReady` 三組改用 `_gateway.register<T>()`；其餘
`onPageRendered`／`onError`／`onLocatorChanged` 三組維持原樣不動）：

```dart
  Future<void> _onWebViewCreated(InAppWebViewController controller) async {
    _controller = controller;
    _gateway = JsBridgeGateway(
      evaluate: _evaluate,
      registerHandler: (name, callback) => controller.addJavaScriptHandler(
        handlerName: name,
        callback: callback,
      ),
    );
    _gateway.register<List<TocEntry>>(
      handlerName: 'onTableOfContentsReady',
      parse: (args) =>
          parseTableOfContents(args.isNotEmpty ? args[0] as String : '[]'),
      fallback: const [],
    );
    _gateway.register<List<TtsSegmentCfi>>(
      handlerName: 'onTtsSegmentsReady',
      parse: (args) =>
          parseTtsSegments(args.length > 1 ? args[1] as String : '[]'),
      fallback: const [],
    );
    _gateway.register<int>(
      handlerName: 'onTtsSegmentIndexReady',
      parse: (args) => args.isNotEmpty ? (args[0] as num).toInt() : 0,
      fallback: 0,
    );
    controller.addJavaScriptHandler(
      handlerName: 'onPageRendered',
      callback: (args) {
        widget.onPageRendered();
        final writingModeStr =
            args.isNotEmpty ? args[0] as String : 'horizontal';
        widget.onLayoutResolved?.call(EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: writingModeStr == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        ));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onError',
      callback: (args) {
        widget.onError(args.isNotEmpty ? args[0] as String : '未知錯誤');
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onLocatorChanged',
      // epic-26-architecture-hardening Issue 10：解析邏輯抽成
      // foliate_bridge_codec.dart 的 parseLocatorChanged() 純函式（比照
      // extractCfi()/parseTableOfContents() 既有慣例），可脫離 WebView
      // 直接單元測試，不再是這個 widget 內無法獨立驗證的匿名 closure。
      callback: (args) =>
          widget.onLocatorChanged?.call(parseLocatorChanged(args)),
    );
```

- [ ] **Step 5: 執行受影響測試確認全數通過**

執行（於 `app/` 目錄下）：`flutter test test/reader/foliate_reader_view_test.dart`

預期結果：全數通過，無新增失敗案例。這三個私有方法（`_requestTableOfContents`／`_requestTtsSegments`／`_requestTtsSegmentIndex`）與其對應 handler 名稱目前沒有被這份測試檔任何案例直接引用（已用 `grep` 確認），所以這一步的目的是確認本次改動沒有讓其他既有案例（例如 `onPageRendered`／`onError`／`onLocatorChanged` 這三組維持原樣的 handler 相關測試）意外壞掉，而不是驗證新接線本身——新接線的行為已由 Task 1 的 `js_bridge_gateway_test.dart` 直接涵蓋。

- [ ] **Step 6: 再次執行 Task 1 的測試腳本確認未受影響**

執行（於 `app/` 目錄下）：`flutter test test/reader/js_bridge_gateway_test.dart`

預期結果：4 個測試全數通過。

- [ ] **Step 7: 執行 `flutter analyze` 確認乾淨**

執行（於 `app/` 目錄下）：`flutter analyze`

預期結果：`No issues found!`

- [ ] **Step 8: 執行完整 `flutter test`（本計畫最後一個 Task，依 Global Constraints 慣例整套跑一次）**

執行（於 `app/` 目錄下）：`flutter test`

預期結果：全數通過，零回歸。

- [ ] **Step 9: Commit**

```bash
git add app/lib/reader/foliate_reader_view.dart
git commit -m "refactor(epic-26): Issue 13 Task 2——foliate_reader_view.dart 接線改用 JsBridgeGateway"
```

---

## Self-Review（撰寫計畫時的自我檢查記錄）

1. **Spec 涵蓋度**：Issue 13 的 6 條 Solution 要點（新檔案／不依賴 `InAppWebViewController`／兩個對外方法／`parse` 例外防護／三個 `_requestXxx` 縮成薄包裝／對外 API 零改動／TOC 維持不逾時）對應 Task 1 Step 1-3 與 Task 2 Step 1-4；「已知限制」（同型別重複請求互相覆蓋、TOC 無逾時）在 Global Constraints 與 Task 2 Step 3 說明中明確保留、不修正；單元測試要求（4 種情境的 `js_bridge_gateway_test.dart`、既有測試零回歸、`flutter analyze`／`flutter test`）對應 Task 1 Step 1、4 與 Task 2 Step 5-8。無遺漏。
2. **Placeholder 掃描**：全文無 TBD／「補上驗證邏輯」等佔位字樣，所有程式碼步驟皆附完整內容。
3. **型別/簽章一致性**：`JsBridgeGateway` 建構子參數（`evaluate`／`registerHandler`）與 `register<T>()`／`request<T>()` 的參數名稱、型別在 Task 1（定義、測試）與 Task 2（呼叫端）三處逐字一致；`register<T>()` 內部 handler 名稱與 Task 2 呼叫端傳入的 `handlerName`（`onTableOfContentsReady`／`onTtsSegmentsReady`／`onTtsSegmentIndexReady`）一一對應。
4. **既有行為零改變查證**：`foliate_reader_view.dart` 現行三個 `_requestXxx` 方法的座標／控制流程（`_controller == null` 防呆、`evaluateJavascript` 呼叫字串、逾時秒數與 fallback 值）已逐字比對搬進 `JsBridgeGateway` 呼叫參數，唯一新增的行為是 `parse()` 例外防護（Issue 13 明確決議新增，非搬移遺漏）。
