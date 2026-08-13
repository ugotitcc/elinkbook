# Epic 26 Issue 2 — 收斂 nav-zone 熱區點擊偵測成一個共用 module 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 EPUB（`_NavZoneTapDetector`）與 PDF（`_PdfNavZoneTapDetector`）兩份逐字幾乎相同、刻意各自獨立實作的九宮格熱區點擊偵測邏輯收斂成一個共用 `TapZoneDetector` module，並補上 EPUB 端目前缺少、PDF 端已有的 `onPointerCancel` 防禦性清理，讓這類「一邊 review 抓到、另一邊沒同步到」的分歧未來不再發生。

**Architecture:** 新增 `app/lib/reader/tap_zone_detector.dart`，內含一個 `StatefulWidget`（`TapZoneDetector`），把兩份原始實作共同的「`Listener`（不參與手勢競技場）觀察 `onPointerDown`/`onPointerUp`/`onPointerCancel`、以耗時≤門檻且位移≤容許值判定是否為快速點擊」邏輯收斂為單一實作。三個會依情境不同的變數改為建構參數注入，**不**收斂成 module 內的共用常數：`nowMs`（計時來源，EPUB 傳 `DateTime.now()`、PDF 傳 `clock.now()`）、`tapMaxDurationMs`（EPUB 現行 700ms、PDF 現行 400ms，兩者數值本身是否都正確是 Epic 26 Issue 3 的範圍，本計畫不變更任何一邊的現行數值）、`tapSlop`（兩邊現行皆 18.0，同樣改為注入參數而非共用常數，避免未來只有其中一邊需要調整時又要重新拆分）。`foliate_epub_reader_view.dart`／`pdf_reader_view.dart` 的呼叫端各自改用 `TapZoneDetector` 並傳入各自現行數值，原本的 `_NavZoneTapDetector`／`_PdfNavZoneTapDetector` 私有類別整段刪除。

**Tech Stack:** Flutter/Dart（`Listener`、`package:clock`），無新增第三方套件。

## Global Constraints

- 本計畫刻意**不**變更任何一邊現行的 `tapMaxDurationMs`／`tapSlop` 數值（EPUB 700/18.0、PDF 400/18.0 維持不變）——`_tapMaxDurationMs` 的正確數值是否需要重新真機診斷校準是 Epic 26 Issue 3 的獨立範圍，見 `docs/epics/epic-26-architecture-hardening/issues.md` Issue 2「刻意排除的範圍」段落。
- `TapZoneDetector` 必須在建構參數層級同時支援兩種計時來源（`DateTime.now()`／`clock.now()`），透過 `nowMs: int Function()` 注入，不得在 module 內部寫死其中一種。
- 完成後 `pdf_reader_view_nav_zone_test.dart` 全部既有測試（含 600ms 排除測試、既有 `onPointerCancel` 測試）必須維持通過、斷言內容不變——這些測試鎖定的是 PDF 現行行為，本計畫的重構不得讓它們的語意跟著改變。
- 提交前必須 `flutter analyze` 乾淨（"No issues found!"），`flutter test` 全數通過，不得有回歸。

---

### Task 1：建立共用 `TapZoneDetector` module 與其專屬單元測試

**Files:**
- Create: `app/lib/reader/tap_zone_detector.dart`
- Create: `app/test/reader/tap_zone_detector_test.dart`

**Interfaces:**
- Consumes：`package:flutter/widgets.dart`（`Listener`／`Offset`／`VoidCallback`／`HitTestBehavior`），無其他外部依賴。
- Produces：`class TapZoneDetector extends StatefulWidget`，建構參數 `{ Key? key, required VoidCallback onTap, required Widget child, required int Function() nowMs, required int tapMaxDurationMs, required double tapSlop }`——Task 2／Task 3 的呼叫端會直接使用這個建構子簽章，欄位名稱與型別須完全一致。

- [ ] **Step 1：寫失敗測試——耗時與位移皆在門檻內應觸發 onTap**

建立 `app/test/reader/tap_zone_detector_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tap_zone_detector.dart';

void main() {
  Widget wrap({
    required VoidCallback onTap,
    required int Function() nowMs,
    int tapMaxDurationMs = 400,
    double tapSlop = 18.0,
  }) {
    return MaterialApp(
      home: TapZoneDetector(
        onTap: onTap,
        nowMs: nowMs,
        tapMaxDurationMs: tapMaxDurationMs,
        tapSlop: tapSlop,
        child: const SizedBox(width: 100, height: 100),
      ),
    );
  }

  testWidgets('按下與放開耗時在門檻內、位移在容許範圍內時觸發 onTap', (tester) async {
    var tapped = false;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapped = true,
      nowMs: () => fakeNowMs,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 100;
    await gesture.up();
    await tester.pump();

    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/reader/tap_zone_detector_test.dart`
Expected: FAIL（`tap_zone_detector.dart` 不存在，`Target of URI doesn't exist`）。

- [ ] **Step 3：實作最小可行版本**

建立 `app/lib/reader/tap_zone_detector.dart`：

```dart
import 'package:flutter/widgets.dart';

/// 九宮格導覽熱區的單一格子共用偵測器（Epic 26 Issue 2，收斂自
/// `foliate_epub_reader_view.dart` 原 `_NavZoneTapDetector` 與
/// `pdf_reader_view.dart` 原 `_PdfNavZoneTapDetector`——兩者原本刻意各自
/// 獨立實作、逐字幾乎相同，且已各自被獨立審查抓到過幾乎一樣的
/// bug〔PDF 端補過 `onPointerCancel` 防禦性清理、EPUB 端從未收到這個
/// 修復〕，見 `docs/research/architecture-review-test-suite-epub-pdf.md`
/// 候選 2 與 `docs/epics/epic-26-architecture-hardening/issues.md`
/// Issue 2）。
///
/// 取代原本的 `GestureDetector(onTap: ...)`（EPUB 端 /diagnose
/// 2026-07-27 真機診斷發現的根因修正）：`GestureDetector` 的
/// `TapGestureRecognizer` 沒有時長上限——即使按住 800ms 才放開，仍會被
/// 判定為一次有效的 tap。`InAppWebView`（Hybrid Composition 平台視圖）
/// 與這個 `GestureDetector` 在同一個 Stack 位置競爭手勢競技場時，只要有
/// 任何 Flutter 側的手勢辨識器參與競爭，平台視圖自己的原生觸控轉發就會
/// 等待競技場裁定結果——`TapGestureRecognizer` 一路持有到放開才裁定為
/// 「是」，導致 `InAppWebView` 從頭到尾都沒收到這次觸控序列，長按選字的
/// 原生選取 UI（控點）完全不會出現。改用 [Listener] 直接觀察原始
/// pointer 事件、自行判斷「是否為一次快速點擊」（位移在 [tapSlop] 內、
/// 耗時在 [tapMaxDurationMs] 內），完全不註冊 `GestureRecognizer`、不
/// 參與手勢競技場，讓底層原生觸控轉發（`InAppWebView` 或 `PdfViewer`）
/// 不再被攔截，選字/拖曳控點/長按框選/翻頁滑動皆可直接穿透。
///
/// [nowMs] 為計時來源注入參數：EPUB 呼叫端傳入
/// `() => DateTime.now().millisecondsSinceEpoch`，PDF 呼叫端傳入
/// `() => clock.now().millisecondsSinceEpoch`（`package:clock`，讓
/// `flutter_test` 的 FakeAsync 能攔截其 Zone 覆寫、隨 `tester.pump()`
/// 正確推進，正式裝置上仍取得真實系統時間；不像先前一度嘗試過的
/// `SchedulerBinding.currentSystemFrameTimeStamp` 只在畫面有新 frame
/// 排程時才更新，長按靜止區域可能整段時間都量不到經過的時間）。兩邊
/// 各自傳入各自現行的計時來源，不強制統一。
///
/// [tapMaxDurationMs]／[tapSlop] 同樣為呼叫端注入參數，刻意不在本
/// module 內設共用預設值/常數——EPUB 現行 700ms（`epic-25` Issue 1
/// 六輪真機診斷校準值）與 PDF 現行 400ms（原始未校準值）已被查證存在
/// 真實差異，兩者適用的正確門檻值可能本來就不同（見 Epic 26 Issue 3，
/// 需真機診斷才能定案 PDF 端數值，不可貿然套用 EPUB 數值），故此次收斂
/// 刻意只共用「偵測機制本身」（含 [onPointerCancel] 防禦性清理），不
/// 共用數值。
class TapZoneDetector extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final int Function() nowMs;
  final int tapMaxDurationMs;
  final double tapSlop;

  const TapZoneDetector({
    super.key,
    required this.onTap,
    required this.child,
    required this.nowMs,
    required this.tapMaxDurationMs,
    required this.tapSlop,
  });

  @override
  State<TapZoneDetector> createState() => _TapZoneDetectorState();
}

class _TapZoneDetectorState extends State<TapZoneDetector> {
  Offset? _downPosition;
  int? _downTimeMs;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _downPosition = event.position;
        _downTimeMs = widget.nowMs();
      },
      onPointerUp: (event) {
        final downPosition = _downPosition;
        final downTimeMs = _downTimeMs;
        if (downPosition == null || downTimeMs == null) return;
        final elapsed = widget.nowMs() - downTimeMs;
        final distance = (event.position - downPosition).distance;
        if (elapsed <= widget.tapMaxDurationMs &&
            distance <= widget.tapSlop) {
          widget.onTap();
        }
      },
      // 系統層級手勢中斷（例如滑出螢幕邊緣觸發 OS 系統手勢）會送出
      // PointerCancelEvent 而非 PointerUpEvent，須主動清除暫存狀態，
      // 避免殘留舊值（Epic 26 Issue 2：PDF 端原本已有這層保護、EPUB 端
      // 原本沒有，本次收斂後兩邊共用同一份，不會再各自漂移）。
      onPointerCancel: (_) {
        _downPosition = null;
        _downTimeMs = null;
      },
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run: `cd app && flutter test test/reader/tap_zone_detector_test.dart`
Expected: PASS（1 項測試）。

- [ ] **Step 5：補上耗時超過門檻、位移超過容許範圍、`onPointerCancel` 清除狀態三項測試**

在 `app/test/reader/tap_zone_detector_test.dart` 的 `main()` 內、既有 `testWidgets(...)` 之後補上：

```dart
  testWidgets('耗時超過門檻時不觸發 onTap', (tester) async {
    var tapped = false;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapped = true,
      nowMs: () => fakeNowMs,
      tapMaxDurationMs: 400,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 500;
    await gesture.up();
    await tester.pump();

    expect(tapped, isFalse);
  });

  testWidgets('位移超過容許範圍時不觸發 onTap（即使耗時在門檻內）', (tester) async {
    var tapped = false;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapped = true,
      nowMs: () => fakeNowMs,
      tapSlop: 18.0,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await gesture.moveTo(const Offset(50, 90)); // 位移 40px > 18px
    await gesture.up();
    await tester.pump();

    expect(tapped, isFalse);
  });

  testWidgets(
      'onPointerCancel 不會拋出例外，取消手勢本身不觸發 onTap，後續正常點擊仍正確判定',
      (tester) async {
    var tapped = false;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapped = true,
      nowMs: () => fakeNowMs,
    ));

    final cancelledGesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 100;
    await cancelledGesture.cancel();
    await tester.pump();

    expect(tapped, isFalse);

    final normalGesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 100;
    await normalGesture.up();
    await tester.pump();

    expect(tapped, isTrue);
  });
```

**誠實說明（避免誤讀本測試的效力）：** 這項測試**不是**「證明舊 EPUB 程式碼有 bug、新程式碼修好了」的 red→green 回歸測試——`_downPosition`/`_downTimeMs` 是單一（非依 pointer id 區分）欄位，下一次合法的 `onPointerDown`（本例中的 `normalGesture`）本來就會直接覆寫這兩個欄位，所以「取消後接一次全新的正常點擊」這個序列，即使拿掉 `onPointerCancel` handler 也會通過（自我修復，見 `issues.md` Issue 2「風險評估」段落）。這項測試的價值是**鎖定新共用 module 的行為**（onPointerCancel 不拋例外、取消手勢本身確實不觸發 onTap），供未來重構時偵測意外破壞，而非重現一個可觀察的歷史 bug——`issues.md` 已誠實記錄：單指循序操作情境本來就會自我修復，真正有風險的是同一熱區格子被兩個 pointer 幾乎同時觸碰（狀態不分 pointer id），但那個風險 EPUB／PDF 現況皆存在、不是 `onPointerCancel` 能解決的問題，不在本 Issue 範圍內。

- [ ] **Step 6：執行測試確認全數通過**

Run: `cd app && flutter test test/reader/tap_zone_detector_test.dart`
Expected: PASS（4 項測試）。

- [ ] **Step 7：Commit**

```bash
git add app/lib/reader/tap_zone_detector.dart app/test/reader/tap_zone_detector_test.dart
git commit -m "feat(epic-26): Issue 2——新增共用 TapZoneDetector module（純邏輯＋單元測試）"
```

---

### Task 2：EPUB 熱區呼叫端改用 `TapZoneDetector`，補上 `onPointerCancel` 特徵測試

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart:6-23`（新增 import）、`:784-816`（呼叫端）、`:842-918`（刪除舊 `_NavZoneTapDetector`／`_NavZoneTapDetectorState` 整段，含其上方 doc comment）
- Modify: `app/test/reader/foliate_epub_reader_view_test.dart`（新增 `onPointerCancel` 特徵測試，鎖定新行為而非重現歷史 bug，理由見 Step 6 下方「誠實說明」）

**Interfaces:**
- Consumes：Task 1 的 `TapZoneDetector({ key, required onTap, required child, required nowMs, required tapMaxDurationMs, required tapSlop })`。
- Produces：無新增可供其他 Task 呼叫的函式——呼叫端內部替換，`FoliateEpubReaderView` 對外公開介面不變。

- [ ] **Step 1：新增 import**

修改 `app/lib/reader/foliate_epub_reader_view.dart`，在既有 `import 'reader_console_log.dart';`（第 20 行）之後新增：

```dart
import 'tap_zone_detector.dart';
```

- [ ] **Step 2：呼叫端改用 `TapZoneDetector`**

修改 `app/lib/reader/foliate_epub_reader_view.dart:784-816`，從：

```dart
                      child: _NavZoneTapDetector(
                        key: Key('nav_zone_$index'),
                        onTap: () {
                          // Epic 25 Issue 1：真機診斷（見
                          // docs/epics/epic-25-annotation-interaction-qa/issues.md
                          // Issue 1）證實長按選字手勢即使成功讓 WebView
                          // 建立選取範圍，放開手指的那個動作仍可能同時滿足
                          // _NavZoneTapDetector 自己的「快速點擊」門檻而
                          // 觸發翻頁——_NavZoneTapDetector 刻意使用
                          // Listener、不加入手勢競技場（見上方 class
                          // doc），WebView 贏得選取不會讓這裡的 Tap 判定被
                          // 取消，兩者是完全獨立、各自判讀同一組觸控事件的
                          // 路徑。若目前有文字選取範圍存在，代表使用者這次
                          // 觸控是劃線/選字手勢的一部分，不應該連帶觸發
                          // 翻頁。
                          if (_hasActiveSelection) return;
                          widget.onZoneAction?.call(action);
                        },
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.white24))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _zoneActionLabel(action),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                )
                              : null,
                        ),
                      ),
```

改為：

```dart
                      child: TapZoneDetector(
                        key: Key('nav_zone_$index'),
                        // Epic 26 Issue 1 校準值（epic-25 Issue 1 六輪
                        // 真機診斷得出，見 TapZoneDetector class doc）。
                        nowMs: () => DateTime.now().millisecondsSinceEpoch,
                        tapMaxDurationMs: 700,
                        tapSlop: 18.0,
                        onTap: () {
                          // Epic 25 Issue 1：真機診斷（見
                          // docs/epics/epic-25-annotation-interaction-qa/issues.md
                          // Issue 1）證實長按選字手勢即使成功讓 WebView
                          // 建立選取範圍，放開手指的那個動作仍可能同時滿足
                          // TapZoneDetector 自己的「快速點擊」門檻而觸發
                          // 翻頁——TapZoneDetector 刻意使用 Listener、不
                          // 加入手勢競技場（見 class doc），WebView 贏得
                          // 選取不會讓這裡的 Tap 判定被取消，兩者是完全
                          // 獨立、各自判讀同一組觸控事件的路徑。若目前有
                          // 文字選取範圍存在，代表使用者這次觸控是劃線/
                          // 選字手勢的一部分，不應該連帶觸發翻頁。
                          if (_hasActiveSelection) return;
                          widget.onZoneAction?.call(action);
                        },
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.white24))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _zoneActionLabel(action),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                )
                              : null,
                        ),
                      ),
```

- [ ] **Step 3：刪除舊 `_NavZoneTapDetector`／`_NavZoneTapDetectorState`**

修改 `app/lib/reader/foliate_epub_reader_view.dart`，把第 842-918 行（`_NavZoneTapDetector` 的 doc comment、`class _NavZoneTapDetector extends StatefulWidget`、`class _NavZoneTapDetectorState extends State<_NavZoneTapDetector>` 整段，從 `/// 九宮格導覽熱區的單一格子，取代原本的 GestureDetector(onTap: ...)` 開始，到 `_NavZoneTapDetectorState` 的結尾 `}` 為止）整段刪除——歷史脈絡（`GestureDetector` 根因修正的故事）已在 Task 1 的 `TapZoneDetector` class doc 中保留，不會遺失。

- [ ] **Step 4：語法檢查**

Run: `cd app && flutter analyze lib/reader/foliate_epub_reader_view.dart`
Expected: `No issues found!`

- [ ] **Step 5：執行既有 EPUB nav-zone 測試確認無回歸**

Run: `cd app && flutter test test/reader/foliate_epub_reader_view_test.dart`
Expected: 全數 PASS（既有 64 項測試零回歸，含既有 nav-zone 熱區點擊測試）。

- [ ] **Step 6：新增 EPUB 版本的 `onPointerCancel` 特徵測試（characterization test，鎖定新行為，非 red→green 回歸測試——理由見下方「誠實說明」）**

在 `app/test/reader/foliate_epub_reader_view_test.dart` 找到既有涵蓋 nav-zone 熱區點擊的 `testWidgets` 區塊附近（搜尋 `nav_zone_` 或 `onZoneAction`），新增：

```dart
  testWidgets(
      'EPUB nav-zone 熱區：onPointerCancel 不會拋出例外，取消手勢本身不觸發 onZoneAction，後續正常點擊仍正確判定',
      (tester) async {
    ZoneAction? triggered;
    final actions = List<ZoneAction>.filled(9, ZoneAction.menu);

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          filePath: 'test/fixtures/sample.epub',
          onPageRendered: () {},
          onError: (_) {},
          navZoneActions: actions,
          onZoneAction: (action) => triggered = action,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final cancelledGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('nav_zone_4'))),
    );
    await cancelledGesture.cancel();
    await tester.pump();

    expect(triggered, isNull);

    await tester.tap(find.byKey(const Key('nav_zone_4')));
    await tester.pump();
    expect(triggered, ZoneAction.menu);
  });
```

**誠實說明（避免誤讀本測試的效力，比照 Task 1 Step 5 同一項說明）：** 這項測試**不會**在舊版 `_NavZoneTapDetector`（無 `onPointerCancel`）上失敗——`_downPosition`/`_downTimeMs` 是單一欄位，`tester.tap(...)` 觸發的全新 `onPointerDown` 本來就會覆寫掉取消手勢殘留的舊值，所以這個測試序列即使拿掉 `onPointerCancel` handler 也會通過（自我修復，見 `issues.md` Issue 2「風險評估」段落）。這項測試的價值是**鎖定 EPUB 端現在也有 `onPointerCancel` 保護這個新行為**，供未來重構時偵測意外破壞，不是重現一個先前存在、可被自動化測試觀察到的 bug——這正是本計畫刻意記錄的誠實範圍聲明：`onPointerCancel` 缺口本身是真實的程式碼分歧與防禦缺口（值得收斂），但單指循序操作情境下沒有可觀察的失敗症狀可供 red→green 測試鎖定，只有在「同一熱區格子被兩個 pointer 幾乎同時觸碰」這個 EPUB／PDF 現況皆有、本 Issue 不處理的情境下才有實際風險。

**注意（若既有測試檔案的 `pumpWidget`／初始化慣例與上方範例不同）：** 上方範例採用本檔案既有測試最基本的建構方式；若 `foliate_epub_reader_view_test.dart` 中既有 nav-zone 熱區測試（搜尋 `find.byKey(const Key('nav_zone_`）已有一套慣用的 pump/等待 render 完成的既有輔助流程，本 Step 應改為沿用該既有慣例（同一個 helper 函式或同樣的 `runAsync`/`pump` 序列），確保與同檔案其餘測試風格一致、能可靠等到 `_NavZoneTapDetector`（現為 `TapZoneDetector`）已掛載於 widget tree 上再開始送出手勢。

- [ ] **Step 7：執行測試確認通過**

Run: `cd app && flutter test test/reader/foliate_epub_reader_view_test.dart --plain-name "onPointerCancel"`
Expected: PASS。

- [ ] **Step 8：Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "fix(epic-26): Issue 2——EPUB nav-zone 改用共用 TapZoneDetector，收斂 onPointerCancel 防禦缺口"
```

---

### Task 3：PDF 熱區呼叫端改用 `TapZoneDetector`，全量回歸驗證，收尾文件更新

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart:5-25`（新增 import）、`:925-943`（呼叫端）、`:1208-1276`（刪除舊 `_PdfNavZoneTapDetector`／`_PdfNavZoneTapDetectorState` 整段，含其上方 doc comment）
- Modify: `docs/epics/epic-26-architecture-hardening/issues.md`（Issue 2 `Status` 行）
- Modify: `docs/epics.md`（epic-26 該列備註）

**Interfaces:**
- Consumes：Task 1 的 `TapZoneDetector({ key, required onTap, required child, required nowMs, required tapMaxDurationMs, required tapSlop })`（同 Task 2）。
- Produces：無新增可供其他 Task 呼叫的函式——呼叫端內部替換，`PdfReaderView` 對外公開介面不變。

- [ ] **Step 1：新增 import**

修改 `app/lib/reader/pdf_reader_view.dart`，在既有 `import 'percent_rect.dart';`（第 24 行）之後新增：

```dart
import 'tap_zone_detector.dart';
```

- [ ] **Step 2：呼叫端改用 `TapZoneDetector`**

修改 `app/lib/reader/pdf_reader_view.dart:925-943`，從：

```dart
                      child: _PdfNavZoneTapDetector(
                        key: Key('pdf_reader_nav_zone_$index'),
                        onTap: () => widget.onZoneAction?.call(action),
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.white24))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _pdfZoneActionLabel(action),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                )
                              : null,
                        ),
                      ),
```

改為：

```dart
                      child: TapZoneDetector(
                        key: Key('pdf_reader_nav_zone_$index'),
                        // 原始未校準值——是否需要比照 epic-25 Issue 1
                        // 真機診斷調整，追蹤於 Epic 26 Issue 3，本次收斂
                        // 刻意不變更數值本身。
                        nowMs: () => clock.now().millisecondsSinceEpoch,
                        tapMaxDurationMs: 400,
                        tapSlop: 18.0,
                        onTap: () => widget.onZoneAction?.call(action),
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.white24))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _pdfZoneActionLabel(action),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                )
                              : null,
                        ),
                      ),
```

- [ ] **Step 3：刪除舊 `_PdfNavZoneTapDetector`／`_PdfNavZoneTapDetectorState`**

修改 `app/lib/reader/pdf_reader_view.dart`，把第 1208-1276 行（`_PdfNavZoneTapDetector` 的 doc comment、`class _PdfNavZoneTapDetector extends StatefulWidget`、`class _PdfNavZoneTapDetectorState extends State<_PdfNavZoneTapDetector>` 整段，從 `/// 九宮格導覽熱區的單一格子（epic-24-pdf-engine-rebuild Issue 8）` 開始，到 `_PdfNavZoneTapDetectorState` 的結尾 `}` 為止）整段刪除。

- [ ] **Step 4：語法檢查**

Run: `cd app && flutter analyze lib/reader/pdf_reader_view.dart`
Expected: `No issues found!`（確認 `package:clock/clock.dart` 的 import 仍有被使用——呼叫端的 `clock.now()` 參考仍在，不會產生 unused-import 警告）。

- [ ] **Step 5：執行既有 PDF nav-zone 測試確認無回歸**

Run: `cd app && flutter test test/reader/pdf_reader_view_nav_zone_test.dart`
Expected: 全數 PASS（既有 6 項測試零回歸，含 600ms 排除測試「按壓超過快速點擊時長判定門檻不觸發 onZoneAction，避免與長按選取手勢衝突」與既有 `onPointerCancel` 測試——這兩項原本就是針對 `_PdfNavZoneTapDetector` 行為撰寫，收斂後應在不修改測試斷言的前提下依然通過，直接證明 `TapZoneDetector` 對 PDF 端行為零改變）。

- [ ] **Step 6：`flutter analyze` 確認全專案乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7：執行完整測試套件確認全域無回歸**

Run: `cd app && flutter test`
Expected: 全數通過（含 Task 1 新增的 `tap_zone_detector_test.dart` 4 項、Task 2 新增的 EPUB `onPointerCancel` 特徵測試 1 項，以及既有全部測試）。

- [ ] **Step 8：更新 `issues.md` Issue 2 狀態**

修改 `docs/epics/epic-26-architecture-hardening/issues.md`，把 Issue 2 的 `Status` 行：

```markdown
**Status:** `ready-for-agent`——安全的機械式收斂，範圍已明確排除有爭議的門檻值變更（見下方「刻意排除的範圍」），無需真機驗證即可實作與驗收。
```

改為：

```markdown
**Status:** ✅ 已修復。新增共用 `app/lib/reader/tap_zone_detector.dart`（`TapZoneDetector`，`nowMs`/`tapMaxDurationMs`/`tapSlop` 皆為呼叫端注入參數，內建 `onPointerCancel` 防禦性清理），EPUB `_NavZoneTapDetector`／PDF `_PdfNavZoneTapDetector` 兩份私有實作整段刪除、呼叫端皆改用此共用 module，各自維持現行數值不變（EPUB 700ms／PDF 400ms，皆 18.0 slop）。EPUB 端新增 `onPointerCancel` 特徵測試鎖定新行為（原本缺少此保護；誠實記錄：單指循序操作情境本來就會因狀態欄位被下一次合法按下覆寫而自我修復，此測試不是重現一個先前可觀察的 bug，價值在於防止未來重構時意外移除這層防禦），PDF 端既有 600ms 排除測試與 `onPointerCancel` 測試皆不需修改斷言即全數通過，證明收斂後兩邊行為零改變。`tap_zone_detector_test.dart`（4 項純邏輯單元測試）＋`flutter test` 全量通過、`flutter analyze` 乾淨。`_tapMaxDurationMs` 數值本身是否需要調整見 Issue 3（獨立範圍，不受本次收斂影響）。
```

- [ ] **Step 9：更新 `docs/epics.md` epic-26 該列備註**

修改 `docs/epics.md` 的 `epic-26-architecture-hardening` 該列（搜尋 `epic-26-architecture-hardening`），在既有備註文字最後（Issue 2／Issue 3 相關敘述之後、表格儲存格結尾 ` |` 之前）補上一句：

```markdown
**Issue 2 已完成並修復**：新增共用 `TapZoneDetector` module，EPUB／PDF 熱區點擊偵測收斂為同一份實作，EPUB 端補上原本缺少的 `onPointerCancel` 防禦，兩邊現行門檻數值皆維持不變；`tap_zone_detector_test.dart`＋既有 EPUB／PDF nav-zone 測試皆通過，`flutter test`／`flutter analyze` 全數乾淨。
```

- [ ] **Step 10：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart docs/epics/epic-26-architecture-hardening/issues.md docs/epics.md
git commit -m "fix(epic-26): Issue 2——PDF nav-zone 改用共用 TapZoneDetector，結案"
```

---

## Self-Review

- **Spec 覆蓋度**：`issues.md` Issue 2 的「Solution」（抽出共用 `TapZoneDetector` module，`nowMs` 注入計時來源）由 Task 1 完整覆蓋；「刻意排除的範圍」（`tapMaxDurationMs`/`tapSlop` 不收斂成共用常數、維持各自現行數值）由 Task 1 的建構參數設計＋Task 2/3 呼叫端傳入各自現行數值共同覆蓋；「單元測試要求」兩項（EPUB 版本 `onPointerCancel` 特徵測試、既有 EPUB／PDF nav-zone 測試零回歸）分別對應 Task 2 Step 6-7、Task 2 Step 5／Task 3 Step 5。
- **No Placeholders 掃描**：三個 Task 的程式碼、測試程式碼皆為實際可執行內容；Task 2 Step 6 的「注意」區塊明確說明了若既有測試檔案有既有 pump/等待慣例時該如何調整，不是空泛的「參考既有寫法」帶過，而是給出了具體要對齊的驗證目標（確保 widget tree 已掛載完成再送出手勢）。
- **型別/介面一致性**：`TapZoneDetector` 的建構參數名稱（`onTap`／`child`／`nowMs`／`tapMaxDurationMs`／`tapSlop`）與型別在 Task 1 定義後，Task 2／Task 3 呼叫端逐字沿用，無改名不一致。`FoliateEpubReaderView`／`PdfReaderView` 對外公開介面在整個計畫中皆未變動。
- **既有測試不回歸的具體論證**：`TapZoneDetector` 的核心判定邏輯（`elapsed <= tapMaxDurationMs && distance <= tapSlop` 才觸發 `onTap`）與原本兩份私有實作逐字等價，只是把常數改為建構參數、新增 EPUB 端原本沒有的 `onPointerCancel`（純新增能力，不影響原有「未取消手勢」路徑的行為）。PDF 端既有測試（600ms 排除、`onPointerCancel`）在數值不變的前提下不應受影響，Task 3 Step 5 安排原封不動重跑這兩項測試作為直接證據；Task 3 Step 7 額外安排全域測試套件執行。
- **範圍誠實聲明**：本計畫刻意不處理 Issue 3（PDF `tapMaxDurationMs` 是否需要重新真機診斷校準）——`issues.md` Issue 2「刻意排除的範圍」段落已明確記錄理由（沿用 EPUB 700ms 會讓 PDF 既有 600ms 排除測試反轉失敗，需真機資料佐證，非機械式修復），本計畫只收斂偵測機制本身、不變更任何一邊的門檻數值。
