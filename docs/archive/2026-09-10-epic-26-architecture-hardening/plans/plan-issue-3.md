# Epic 26 Issue 3 — PDF 熱區快速點擊時長門檻真機診斷插樁實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為「PDF 熱區快速點擊時長門檻（現行 700ms，`epic-31-touch-intent-unification` Issue 3 刻意對齊、未經真機驗證）是否合適」新增暫時性真機診斷插樁，並產出真機資料蒐集操作手冊。本計畫**不**決定最終數值該是多少——那要等真機資料回來後另立修復計畫。

**Architecture:** 在共用 `TapZoneDetector`（`app/lib/reader/tap_zone_detector.dart`）新增一個可選的 `onDebugEvent` 除錯回呼，預設 `null`（不影響任何既有行為，EPUB 呼叫端不接、PDF 既有測試不受影響）；只在 PDF 的建構呼叫端（`pdf_reader_view.dart`）接上，轉送到既有的 `ReaderConsoleLog`（`app/lib/reader/reader_console_log.dart`，App 內建的真機診斷 log 檢視/複製工具，`epic-18` Issue 33、`epic-25` Issue 4 已有先例）。另在 PDF 長按拖曳框選手勢層（`_buildSelectionGestureLayer`）與 `reader_screen.dart` 的 `_handleZoneAction()` PDF 分支各自補上對應標籤的插樁，三者交叉比對即可還原真機上「長按拖曳建立標註」與「熱區判定觸發換頁」之間的實際時序關係。三種訊息標籤：`[DEBUG-e26i3]`（`TapZoneDetector` 內部判定）、`[DEBUG-e26i3-selection]`（長按框選手勢起訖）、`[DEBUG-e26i3-zoneaction]`（實際觸發換頁的那一刻）。

**Tech Stack:** Flutter/Dart（既有 `Listener`／`GestureDetector`／`package:clock`／`ReaderConsoleLog`），無新增第三方套件。

**Spec:** `docs/epics/epic-26-architecture-hardening/issues.md`（Issue 3，含 2026-08-31 `/grill-with-docs` 校準後的最新範圍界定）。

## Global Constraints

- 範圍僅限驗證/校準 PDF 的 `tapMaxDurationMs`（現行 700ms）。**不**調整 `tapSlop`（18px，`kTapZoneSlop`）、**不**觸碰 EPUB 呼叫端（`foliate_reader_view.dart`）任何現行數值或行為。
- 本計畫新增的所有插樁皆為**暫時性**，禁止當作永久功能保留。全部三個標籤（`[DEBUG-e26i3]`／`[DEBUG-e26i3-selection]`／`[DEBUG-e26i3-zoneaction]`）與新增的 `onDebugEvent` 參數，需在拿到真機資料、另立修復計畫（或確認 700ms 合適、直接結案）後的 Cleanup 階段整段移除，本計畫不含 Cleanup。
- 不預先指定真機裝置型號——依實作/測試當下手邊可用的裝置為準（2026-08-31 grilling 已定案，見 Issue 3 文字）。
- `onDebugEvent` 為 `null` 時（EPUB 現況、PDF 舊測試現況），`TapZoneDetector`／PDF 既有行為與既有測試斷言必須逐一維持不變，不得有任何回歸。
- 每個 Task 完成後只需執行該 Task 實際觸及的測試檔；全套 `flutter test` 留到本計畫最後一個 Task（Task 4）執行一次（比照 CLAUDE.md「測試執行範圍」慣例）。提交前 `flutter analyze` 須保持乾淨（"No issues found!"）。

---

### Task 1：`TapZoneDetector` 新增可選除錯插樁 hook（`onDebugEvent`，預設不影響既有行為）

**Files:**
- Modify: `app/lib/reader/tap_zone_detector.dart`
- Test: `app/test/reader/tap_zone_detector_test.dart`

**Interfaces:**
- Consumes：既有 `TapZoneDetector` 建構參數（`onTap`／`child`／`nowMs`／`tapMaxDurationMs`／`tapSlop`／`tapDebounceMs`），皆不變更。
- Produces：新增可選建構參數 `final void Function(String message)? onDebugEvent`（預設 `null`）。Task 2 的 PDF 呼叫端會用這個確切欄位名稱與型別接上 `ReaderConsoleLog.add`。

- [ ] **Step 1：寫失敗測試——合格點擊時 `onDebugEvent` 回報 `qualified=true fired=true`**

修改 `app/test/reader/tap_zone_detector_test.dart`，`wrap()` helper 新增可選參數：

```dart
  Widget wrap({
    required VoidCallback onTap,
    required int Function() nowMs,
    int tapMaxDurationMs = 400,
    double tapSlop = 18.0,
    int tapDebounceMs = 350,
    void Function(String message)? onDebugEvent,
  }) {
    return MaterialApp(
      home: TapZoneDetector(
        onTap: onTap,
        nowMs: nowMs,
        tapMaxDurationMs: tapMaxDurationMs,
        tapSlop: tapSlop,
        tapDebounceMs: tapDebounceMs,
        onDebugEvent: onDebugEvent,
        child: const SizedBox(width: 100, height: 100),
      ),
    );
  }
```

在檔案最後一個 `testWidgets`（`'未明確傳入 tapSlop 時...'`，第 227-253 行）與結尾的 `}` 之間，新增三個測試：

```dart
  testWidgets(
      'onDebugEvent（Epic 26 Issue 3 暫時性真機診斷插樁）在合格點擊時回報 up qualified=true fired=true',
      (tester) async {
    final messages = <String>[];
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () {},
      nowMs: () => fakeNowMs,
      onDebugEvent: messages.add,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 100;
    await gesture.up();
    await tester.pump();

    expect(
      messages,
      contains(
          '[DEBUG-e26i3] up qualified=true fired=true elapsed=100 distance=0.0 t=1100'),
    );
  });

  testWidgets(
      'onDebugEvent（Epic 26 Issue 3 暫時性真機診斷插樁）在超過時長門檻時回報 qualified=false reason=duration',
      (tester) async {
    final messages = <String>[];
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () {},
      nowMs: () => fakeNowMs,
      tapMaxDurationMs: 400,
      onDebugEvent: messages.add,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 500;
    await gesture.up();
    await tester.pump();

    expect(
      messages,
      contains(
          '[DEBUG-e26i3] up qualified=false reason=duration elapsed=500 distance=0.0 t=1500'),
    );
  });

  testWidgets(
      'onDebugEvent（Epic 26 Issue 3 暫時性真機診斷插樁）位移已作廢按壓後放開，依序回報 invalidated reason=slop 與 up reason=no-active-press',
      (tester) async {
    final messages = <String>[];
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () {},
      nowMs: () => fakeNowMs,
      tapSlop: 18.0,
      onDebugEvent: messages.add,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await gesture.moveTo(const Offset(50, 90)); // 位移 40px > 18px，作廢本次按壓
    fakeNowMs += 50;
    await gesture.up();
    await tester.pump();

    expect(
      messages,
      containsAllInOrder([
        '[DEBUG-e26i3] invalidated reason=slop distance=40.0 t=1050',
        '[DEBUG-e26i3] up reason=no-active-press t=1100',
      ]),
    );
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/reader/tap_zone_detector_test.dart`
Expected: 新增的兩個測試 FAIL（編譯錯誤：`TapZoneDetector` 建構子沒有 `onDebugEvent` 具名參數）。

- [ ] **Step 3：`TapZoneDetector` 實作 `onDebugEvent`**

修改 `app/lib/reader/tap_zone_detector.dart`，在既有 class doc 註解（`[tapDebounceMs] 防彈跳...` 段落之後、`class TapZoneDetector extends StatefulWidget {` 之前）新增一段：

```dart
///
/// [onDebugEvent]（Epic 26 Issue 3 暫時性真機診斷插樁）：非 null 時，於每次
/// `onPointerDown`/`onPointerMove`（位移超出容許範圍作廢）/`onPointerUp`
/// （合格/不合格判定結果）/`onPointerCancel` 回報一則描述訊息，供 PDF 呼叫端
/// 接上 `ReaderConsoleLog` 進行真機資料蒐集，驗證現行 700ms 是否合適。EPUB
/// 呼叫端不接此參數（維持 null），行為完全不受影響。診斷結束後需整段移除
/// （`grep -rn "onDebugEvent"` 確認清除乾淨）。
```

`TapZoneDetector` class 欄位與建構子改為：

```dart
class TapZoneDetector extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final int Function() nowMs;
  final int tapMaxDurationMs;
  final double tapSlop;
  final int tapDebounceMs;
  final void Function(String message)? onDebugEvent;

  const TapZoneDetector({
    super.key,
    required this.onTap,
    required this.child,
    required this.nowMs,
    required this.tapMaxDurationMs,
    this.tapSlop = kTapZoneSlop,
    this.tapDebounceMs = kTapZoneDebounceMs,
    this.onDebugEvent,
  });

  @override
  State<TapZoneDetector> createState() => _TapZoneDetectorState();
}
```

`_TapZoneDetectorState.build()` 整段改為：

```dart
class _TapZoneDetectorState extends State<TapZoneDetector> {
  Offset? _downPosition;
  int? _downTimeMs;
  int? _lastQualifyingTapUpTimeMs;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _downPosition = event.position;
        _downTimeMs = widget.nowMs();
        widget.onDebugEvent?.call(
            '[DEBUG-e26i3] down t=${_downTimeMs} pos=${event.position}');
      },
      onPointerMove: (event) {
        final downPosition = _downPosition;
        if (downPosition == null) return;
        final distance = (event.position - downPosition).distance;
        if (distance > widget.tapSlop) {
          // 位移已超過容許範圍，永久作廢本次按壓——即使之後手指移回附近
          // 才放開，onPointerUp 也不會再誤判為一次快速點擊（Epic 27
          // Issue 9）。
          _downPosition = null;
          _downTimeMs = null;
          widget.onDebugEvent?.call(
              '[DEBUG-e26i3] invalidated reason=slop distance=${distance.toStringAsFixed(1)} t=${widget.nowMs()}');
        }
      },
      onPointerUp: (event) {
        final downPosition = _downPosition;
        final downTimeMs = _downTimeMs;
        final now = widget.nowMs();
        if (downPosition == null || downTimeMs == null) {
          widget.onDebugEvent
              ?.call('[DEBUG-e26i3] up reason=no-active-press t=$now');
          return;
        }
        final elapsed = now - downTimeMs;
        final distance = (event.position - downPosition).distance;
        if (elapsed <= widget.tapMaxDurationMs &&
            distance <= widget.tapSlop) {
          final previousTapUpTimeMs = _lastQualifyingTapUpTimeMs;
          _lastQualifyingTapUpTimeMs = now;
          final debounced = previousTapUpTimeMs != null &&
              now - previousTapUpTimeMs < widget.tapDebounceMs;
          widget.onDebugEvent?.call(
              '[DEBUG-e26i3] up qualified=true fired=${!debounced} elapsed=$elapsed distance=${distance.toStringAsFixed(1)} t=$now');
          if (!debounced) {
            widget.onTap();
          }
        } else {
          widget.onDebugEvent?.call(
              '[DEBUG-e26i3] up qualified=false reason=${elapsed > widget.tapMaxDurationMs ? "duration" : "distance"} elapsed=$elapsed distance=${distance.toStringAsFixed(1)} t=$now');
        }
      },
      // 系統層級手勢中斷（例如滑出螢幕邊緣觸發 OS 系統手勢）會送出
      // PointerCancelEvent 而非 PointerUpEvent，須主動清除暫存狀態，
      // 避免殘留舊值（Epic 26 Issue 2：PDF 端原本已有這層保護、EPUB 端
      // 原本沒有，本次收斂後兩邊共用同一份，不會再各自漂移）。
      onPointerCancel: (_) {
        _downPosition = null;
        _downTimeMs = null;
        widget.onDebugEvent
            ?.call('[DEBUG-e26i3] cancel t=${widget.nowMs()}');
      },
      child: widget.child,
    );
  }
}
```

`debounced` 這個新變數與原本的 `if (previousTapUpTimeMs == null || now - previousTapUpTimeMs >= widget.tapDebounceMs) widget.onTap();` 邏輯完全等價（`!debounced` 即為原本的條件式），純粹是為了同時能在 `widget.onTap()` 呼叫前先組出 debug 訊息，不改變既有防彈跳判定結果。

- [ ] **Step 4：執行測試確認通過，並確認既有測試零回歸**

Run: `cd app && flutter test test/reader/tap_zone_detector_test.dart`
Expected: 全數通過（含新增的 3 項與既有全部項目，`onDebugEvent` 預設 `null` 時既有測試不需要任何修改）。

- [ ] **Step 5：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/tap_zone_detector.dart app/test/reader/tap_zone_detector_test.dart
git commit -m "debug(epic-26): Issue 3 TapZoneDetector 新增可選 onDebugEvent 真機診斷插樁"
```

---

### Task 2：PDF 熱區與長按框選手勢層接上 `[DEBUG-e26i3]`／`[DEBUG-e26i3-selection]` 插樁（僅 PDF，EPUB 不受影響）

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart:26`（新增 import）、`:986-998`（`TapZoneDetector` 建構呼叫）、`:1129-1154`（`_buildSelectionGestureLayer()`）
- Test: `app/test/reader/pdf_reader_view_nav_zone_test.dart`

**Interfaces:**
- Consumes：Task 1 產出的 `TapZoneDetector.onDebugEvent`；既有 `ReaderConsoleLog.add(String message)`（`app/lib/reader/reader_console_log.dart:20`）、`ReaderConsoleLog.clear()`（`:28`）、`ReaderConsoleLog.entries`（`:17`，`ValueNotifier<List<String>>`）。
- Produces：無新增可供其他 Task 呼叫的函式，純插樁。

- [ ] **Step 1：新增 import**

修改 `app/lib/reader/pdf_reader_view.dart`：在既有的 `import 'tap_zone_detector.dart';`（第 26 行）與 `import 'zone_action.dart';`（第 27 行）之間，新增**這一行**（`tap_zone_detector.dart`／`zone_action.dart` 兩行皆為既有 import，不要重複插入）：

```dart
import 'reader_console_log.dart';
```

- [ ] **Step 2：`TapZoneDetector` 建構呼叫接上 `onDebugEvent`**

修改 `app/lib/reader/pdf_reader_view.dart:986-998`：

```dart
                      child: TapZoneDetector(
                        key: Key('pdf_reader_nav_zone_$index'),
                        // epic-31-touch-intent-unification Issue 3：對齊
                        // EPUB 端 700ms——刻意決定、未經真機驗證（見
                        // TapZoneDetector class doc），若之後真機回報
                        // PDF 長按判斷變遲鈍，需另立工單依真機資料重新
                        // 校準，不可逕自沿用這裡的數值。
                        // tapSlop／tapDebounceMs 改用建構子預設值
                        // （kTapZoneSlop／kTapZoneDebounceMs，同一 Issue
                        // 常數收斂），不再各自宣告字面值。
                        nowMs: () => clock.now().millisecondsSinceEpoch,
                        tapMaxDurationMs: 700,
                        // Epic 26 Issue 3 暫時性真機診斷插樁：僅 PDF 端接上
                        // onDebugEvent，EPUB 端（foliate_reader_view.dart）
                        // 不接、不受影響。診斷結束後需整段移除（grep
                        // "DEBUG-e26i3" 確認清除乾淨）。
                        onDebugEvent: (message) =>
                            ReaderConsoleLog.add('$message zone=$index'),
                        onTap: () => widget.onZoneAction?.call(action),
                        child: Container(
```

- [ ] **Step 3：`_buildSelectionGestureLayer()` 新增長按框選手勢插樁**

修改 `app/lib/reader/pdf_reader_view.dart:1129-1154`：

```dart
  Widget _buildSelectionGestureLayer(int pageIndex, Rect pageRectInViewer) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (details) {
          if (widget.cropEditModeActive) return;
          // Epic 26 Issue 3 暫時性真機診斷插樁：量測長按拖曳框選手勢與
          // 九宮格熱區判定之間的真機時序，與 [DEBUG-e26i3] 系列交叉比對。
          // 診斷結束後需整段移除。
          ReaderConsoleLog.add(
              '[DEBUG-e26i3-selection] longPressStart page=$pageIndex t=${clock.now().millisecondsSinceEpoch}');
          _selectionDragGenerationId++;
          setState(() {
            _selectionDrag = _PdfSelectionDragState(
              pageIndex: pageIndex,
              areaSize: pageRectInViewer.size,
              pageOffsetInViewer: pageRectInViewer.topLeft,
              start: details.localPosition,
            );
          });
        },
        onLongPressMoveUpdate: (details) {
          final drag = _selectionDrag;
          if (drag == null || drag.pageIndex != pageIndex) return;
          setState(() => drag.current = details.localPosition);
        },
        onLongPressEnd: (details) {
          ReaderConsoleLog.add(
              '[DEBUG-e26i3-selection] longPressEnd page=$pageIndex t=${clock.now().millisecondsSinceEpoch}');
          _finishSelectionDrag();
        },
        onLongPressCancel: () {
          ReaderConsoleLog.add(
              '[DEBUG-e26i3-selection] longPressCancel page=$pageIndex t=${clock.now().millisecondsSinceEpoch}');
          _cancelSelectionDrag();
        },
      ),
    );
  }
```

- [ ] **Step 4：寫失敗測試——透過完整 `PdfReaderView` 點擊熱區，確認 `ReaderConsoleLog` 收到帶 zone 索引的插樁訊息**

修改 `app/test/reader/pdf_reader_view_nav_zone_test.dart`：檔案已經 import 過 `package:elinkbook/reader/pdf_reader_view.dart` 與 `package:elinkbook/reader/zone_action.dart`（第 4-5 行），在這兩行之間新增**這一行**：

```dart
import 'package:elinkbook/reader/reader_console_log.dart';
```

在檔案最後一個 `testWidgets`（`onPointerCancel` 測試）與結尾 `}` 之間新增：

```dart
  testWidgets(
      '合格快速點擊時，ReaderConsoleLog 收到帶 zone 索引的 [DEBUG-e26i3] 插樁訊息（Epic 26 Issue 3 暫時性真機診斷插樁）',
      (tester) async {
    ReaderConsoleLog.clear();
    var renderedCount = 0;
    final actions = List<ZoneAction>.filled(9, ZoneAction.menu);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          navZoneActions: actions,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_4')));
    await tester.pump();

    expect(
      ReaderConsoleLog.entries.value.any((line) =>
          line.startsWith('[DEBUG-e26i3] up qualified=true fired=true') &&
          line.endsWith('zone=4')),
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 400));
  });
```

- [ ] **Step 5：執行測試確認先失敗再通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_nav_zone_test.dart`
Expected：Step 4 寫完、Step 2/3 實作前執行應 FAIL（`ReaderConsoleLog` 收不到任何 `[DEBUG-e26i3]` 訊息）；完成 Step 2/3 後重跑，全數（含既有全部項目、含 600ms→800ms 排除測試）通過。

- [ ] **Step 6：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_nav_zone_test.dart
git commit -m "debug(epic-26): Issue 3 PDF 熱區與長按框選手勢層接上真機診斷插樁"
```

---

### Task 3：`reader_screen.dart` 的 `_handleZoneAction()` PDF 分支新增 `[DEBUG-e26i3-zoneaction]` 插樁

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:46`（新增 import）、`:3007-3039`（`_handleZoneAction()` 的 `ZoneAction.previousPage`／`ZoneAction.nextPage` 分支）
- Test: 無新增測試檔——本 Task 只在既有 `switch` 分支內新增一行純副作用呼叫，不改變任何回傳值或控制流程，以「執行既有測試套件零回歸」作為驗證（比照 `epic-25` Issue 4 Task 2 同類插樁的驗證方式）。

**Interfaces:**
- Consumes：既有 `ReaderConsoleLog.add(String message)`；`package:clock` 的 `clock.now()`（與 Task 2 的 `pdf_reader_view.dart` 插樁統一時間源，避免 `flutter_test` 的 `FakeAsync` 環境下兩邊時間軸不一致）；既有 `_handleZoneAction(ZoneAction action)`（PDF／EPUB 兩種格式共用同一個方法，本插樁只加在 PDF 分支）。
- Produces：無新增可供其他 Task 呼叫的函式。

- [ ] **Step 1：新增 import**

修改 `app/lib/screens/reader_screen.dart`：

1. 在既有的 `import 'package:flutter/services.dart';` 與 `import 'package:uuid/uuid.dart';` 之間，新增**這一行**（依專案既有的 `package:` import 字母序慣例，`clock` 排在 `flutter`／`uuid` 之前）：

```dart
import 'package:clock/clock.dart';
```

2. 在既有的 `import '../reader/reading_position.dart';`（第 46 行）與 `import '../reader/reader_prefs_manager.dart';`（第 47 行）之間，新增**這一行**（這兩行皆為既有 import，不要重複插入）：

```dart
import '../reader/reader_console_log.dart';
```

- [ ] **Step 2：`_handleZoneAction()` 的 PDF 分支新增插樁**

修改 `app/lib/screens/reader_screen.dart:3007-3039`：

```dart
      case ZoneAction.previousPage:
        if (_state == _RenderState.loading) return;
        if (format == BookFormat.pdf) {
          // Epic 26 Issue 3 暫時性真機診斷插樁：量測熱區判定觸發換頁的
          // 時間點，與 TapZoneDetector／長按框選插樁交叉比對，確認是否
          // 為誤觸換頁。診斷結束後需整段移除。
          ReaderConsoleLog.add(
              '[DEBUG-e26i3-zoneaction] previousPage t=${clock.now().millisecondsSinceEpoch}');
          PdfReaderView.previousPage(_pdfReaderViewKey);
          // Epic 24 Issue 10：PDF 框選狀態是純 Dart 端矩形選取，沒有
          // EPUB 那種 WebView 切頁自動清空 window.getSelection() 的
          // 瀏覽器原生語意可依賴，換頁時需主動清除既有選取與工具列，
          // 避免選取範圍/AnnotationToolbar 殘留在已經翻過的頁面上。
          if (_currentPdfSelection != null) _handlePdfSelectionCanceled();
          // 審查修正：換頁當下若長按拖曳框選仍進行中（尚未放開手指），
          // 上面的 guard 不會觸發（_currentPdfSelection 此時仍是
          // null），但 PdfReaderView 內部進行中的拖曳狀態不受換頁影響，
          // 放開手指後仍會用換頁前的舊頁面座標重新彈出 Toolbar，一併
          // 中止它，見 PdfReaderView.cancelActiveSelectionDrag 文件。
          PdfReaderView.cancelActiveSelectionDrag(_pdfReaderViewKey);
        } else if (isFoliateFormat(format)) {
          // Epic 11 Issue 2：KF8 (AZW3) 與 EPUB 共用 FoliateReaderView。
          FoliateReaderView.previousPage(_foliateEpubReaderViewKey);
        }
        break;
      case ZoneAction.nextPage:
        if (_state == _RenderState.loading) return;
        if (format == BookFormat.pdf) {
          // Epic 26 Issue 3 暫時性真機診斷插樁：見上方 previousPage
          // 分支註解，同理。
          ReaderConsoleLog.add(
              '[DEBUG-e26i3-zoneaction] nextPage t=${clock.now().millisecondsSinceEpoch}');
          PdfReaderView.nextPage(_pdfReaderViewKey);
          // Epic 24 Issue 10：理由同上方 previousPage 分支。
          if (_currentPdfSelection != null) _handlePdfSelectionCanceled();
          // 審查修正：理由同上方 previousPage 分支。
          PdfReaderView.cancelActiveSelectionDrag(_pdfReaderViewKey);
        } else if (isFoliateFormat(format)) {
          // Epic 11 Issue 2：KF8 (AZW3) 與 EPUB 共用 FoliateReaderView。
          FoliateReaderView.nextPage(_foliateEpubReaderViewKey);
        }
        break;
```

- [ ] **Step 3：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4：執行既有測試套件，確認無回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數通過——插樁只新增 `ReaderConsoleLog.add()` 呼叫（純副作用、無回傳值影響控制流程），不改變任何既有分派邏輯。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/reader_screen.dart
git commit -m "debug(epic-26): Issue 3 reader_screen PDF 換頁分支新增真機診斷插樁"
```

---

### Task 4：全套測試最終確認、撰寫真機資料蒐集操作手冊，更新 `issues.md`

**Files:**
- Modify: `docs/epics/epic-26-architecture-hardening/issues.md`（Issue 3 區塊，「下一步」與「單元測試要求」段落之間新增「真機資料蒐集步驟」小節）

**Interfaces:**
- Consumes：Task 1-3 產出的 `[DEBUG-e26i3]`／`[DEBUG-e26i3-selection]`／`[DEBUG-e26i3-zoneaction]` 插樁（已隨 debug build 部署到裝置）。
- Produces：無程式介面——本 Task 的產出是給人類操作的文字步驟，供人類在真機上實際執行後，將擷取到的 log 回報回來，供下一輪校準/結案使用。

- [ ] **Step 1：全套 `flutter test`／`flutter analyze` 最終確認**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數通過，零回歸（比照 CLAUDE.md「測試執行範圍」慣例，整張計畫最後一個 Task 執行一次全套測試）。

- [ ] **Step 2：在 `issues.md` Issue 3 區塊新增操作手冊**

修改 `docs/epics/epic-26-architecture-hardening/issues.md` 的「## Issue 3」區塊內，「**下一步**」段落之後、「**單元測試要求**」段落之前，新增：

```markdown
**真機資料蒐集步驟（`plan-issue-3.md` Task 1-3 完成後可執行）：**

1. 用含 `[DEBUG-e26i3]`／`[DEBUG-e26i3-selection]`／`[DEBUG-e26i3-zoneaction]` 插樁的 debug build（`flutter build apk --debug`）安裝到手邊可用的真機（不預先指定機型，見上方「2026-08-31 更新」）。
2. 開啟一本多頁 PDF，開啟「設定」→「閱讀器 Console Log」畫面（可隨時切回複製）。
3. **方向一（長按拖曳建立標註是否誤觸換頁）**：在頁面上長按拖曳框選一段文字建立劃線/備註，重複至少 5-10 次（動作很快，單次不一定會踩到競速窗口），留意畫面是否誤跳頁。
4. **方向二（一般快速點擊翻頁手感是否變遲鈍）**：用 3×3 熱區正常快速點擊翻頁至少 10 次，主觀評估翻頁反應是否感覺到延遲（比照 `epic-25` Issue 1 校準 EPUB 時的做法，翻頁手感是主觀判斷，不是自動化斷言）。
5. 每組操作後，回到「閱讀器 Console Log」點擊「複製全部」，貼到文字檔或直接回報，同步註記「該次操作是否有觀察到誤跳頁」與「翻頁手感是否感覺遲鈍」。
6. 回報 log 時，交叉比對 `[DEBUG-e26i3-selection] longPressStart/longPressEnd/longPressCancel` 與 `[DEBUG-e26i3] up qualified=true fired=true`／`[DEBUG-e26i3-zoneaction] previousPage/nextPage`——若一次長按框選手勢的時間區間內出現 `fired=true` 與 `zoneaction`，代表該次操作被誤判成一次快速點擊、觸發了換頁，即為方向一要抓的 bug；若快速點擊時 `elapsed` 明顯偏大（接近甚至超過 700ms）卻仍 `fired=true`，可用來評估方向二的手感問題。

**下一輪（拿到真機資料後）**：依比對結果決定 700ms 是否合適——沒問題直接結案（記錄真機資料佐證，更新上方 Status／驗收標準）；有問題則依真機資料重新校準出新數值，另立修復計畫。本插樁需在修復計畫的 Cleanup 階段整段移除（`grep -rn "DEBUG-e26i3"` 確認清除乾淨，含 `onDebugEvent` 參數本身）。
```

- [ ] **Step 3：Commit**

```bash
git add docs/epics/epic-26-architecture-hardening/issues.md
git commit -m "docs(epic-26): Issue 3 補上真機資料蒐集操作手冊"
```

---

## Self-Review

- **Spec 覆蓋度**：Issue 3（2026-08-31 校準版）「下一步」1-4 點，本計畫 Task 1-3 覆蓋第 1 點（插樁）與第 2 點（雙方向：Task 2 的長按框選插樁對應「是否誤觸換頁」、Task 4 手冊 Step 4 對應「翻頁手感」）；第 3 點（依真機資料決定數值）與第 4 點（重新檢視既有斷言）刻意留給下一輪，不在本計畫內用臆測方式提前完成（見下方「範圍誠實聲明」）。
- **Placeholder 掃描**：三個 Task 的插樁程式碼、測試程式碼、Task 4 的操作手冊文字，皆為規劃階段已對照實際原始碼位置（行號皆已核對）寫出的具體內容，無 TBD/待補。
- **型別/介面一致性**：`onDebugEvent` 的簽章 `void Function(String message)?` 在 Task 1（定義）、Task 2（PDF 呼叫端使用）全程一致；`ReaderConsoleLog.add`／`clear`／`entries` 的用法與既有 `foliate_reader_view_test.dart` 既有慣例（`setUp(() { ReaderConsoleLog.clear(); })`）一致。
- **既有測試不回歸的具體論證**：Task 1 新增欄位有預設值 `null`，未接上的呼叫端（EPUB）行為零改變；Task 2/3 新增的插樁呼叫皆為新增的一行純副作用呼叫（`ReaderConsoleLog.add(...)`），不改變任何既有回傳值或控制流程分支。三個 Task 各自安排執行既有測試套件作為實測佐證，不僅依賴此推論；Task 4 額外執行一次全套 `flutter test` 做最終確認。
- **範圍誠實聲明**：本計畫刻意不包含「鎖定最終 `tapMaxDurationMs` 數值」與「移除暫時性插樁」——這兩步依賴 Task 4 蒐集回來的真機資料，屬於下一輪計畫（校準/結案 + Cleanup）的範圍，不在本計畫內提前完成。
