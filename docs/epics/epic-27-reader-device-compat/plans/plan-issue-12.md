# Epic 27 Issue 12 — 觸控硬體「彈跳」訊號導致連續失控自動翻頁 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在共用元件 `TapZoneDetector` 加入防彈跳（debounce）機制：同一格熱區在極短時間內收到第二次（或更多次）觸發時，只放行第一次、忽略其餘，用純軟體手段吸收本 Epic 已用 `adb shell getevent` 硬體訊號證實存在的觸控 IC 彈跳雜訊，根除「壓一下畫面自己連續亂跳頁、殘影發霧」的真機回報。

**Architecture:** `TapZoneDetector`（`app/lib/reader/tap_zone_detector.dart`）是 EPUB／PDF 共用的九宮格熱區單一格子偵測器，`FoliateReaderView`／`PdfReaderView` 各自用 `List.generate(9, ...)` 建立 9 個獨立的 `TapZoneDetector` 實例，每一格各自持有獨立的 `_TapZoneDetectorState`。真機硬體訊號證實：一次彈跳事件的所有重複按下座標幾乎不動（誤差僅個位數至數十像素），必然落在同一格熱區內——因此防彈跳邏輯只需要「每一格熱區記住自己最近一次成功判定為 tap 的時間」這個最小範圍即可完全吸收本 Epic 已觀測到的彈跳模式，不需要跨格子的全域協調機制。修法是在 `_TapZoneDetectorState` 新增一個 `_lastQualifyingTapUpTimeMs` 欄位，在既有「是否為一次快速點擊」判定成立之後、真正呼叫 `widget.onTap()` 之前，多比對一次「距離上次同樣判定成立的時間點是否已超過 `tapDebounceMs` 門檻」，未超過則忽略。

**Tech Stack:** Flutter/Dart，無新增依賴。

**Spec:** `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 12」、`docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md`「Issue 10」新問題 B 段落（硬體訊號座標交叉核對紀錄）、`docs/epics/epic-27-reader-device-compat/reviews/issue-10-11-12-analysis.md`（三項後續問題的關聯性矩陣與優先順序分析）。

## 設計決策（回應 `issues.md` Issue 12 留給實作者定案的範圍問題）

1. **防彈跳邏輯放在 `TapZoneDetector` 內部（`_TapZoneDetectorState`），不是 `_handleZoneAction`**：`TapZoneDetector` 是 PDF／EPUB 共用元件，且每一格熱區各自是獨立的 `State`，把邏輯放在這裡可以免費讓 PDF／EPUB 兩種格式同時受益，且「同一格熱區」這個防彈跳範圍本來就等於一個 `_TapZoneDetectorState` 實例的生命週期，不需要額外的跨元件協調狀態。`_handleZoneAction`（`reader_screen.dart`）是格式無關的動作分派後端，把防彈跳邏輯放在這裡反而需要額外記錄「上一次是哪一格熱區」，複雜度更高、且無法防止 PDF／EPUB 各自的呼叫端已經各自重複呼叫（`TapZoneDetector.onTap` 本身就已經被觸發多次）。
2. **`tapDebounceMs` 比照既有 `tapMaxDurationMs`／`tapSlop` 的既有慣例，作為呼叫端必要注入參數（`required`），不在 `TapZoneDetector` 內部設共用預設值**——與該檔案 class doc 既有的既定設計哲學一致（見 `tap_zone_detector.dart:35-41`）。
3. **初始值定為 350ms，而非 `issues.md`／分析報告原先建議的「150～200ms」**：真機用 `adb shell getevent` 側錄到的實際彈跳訊號，同一段彈跳內相鄰按下事件的**最大間隔是 326 毫秒**（`bugfix-repro.md`「Issue 10」新問題 B 段落：`86、152、261、326、87、207` 毫秒六段間隔，皆為連續事件間的間隔，非累計值）。防彈跳邏輯採「每次判定為快速點擊都重新起算冷卻窗」的設計（見下方 Task 1 實作），只要窗口門檻小於等於這個最大間隔，彈跳序列中間就會有一次意外被放行——`200ms < 326ms`，代表若照搬原始建議值，這次真機實際側錄到的彈跳序列**不會被完全吸收**。改採 350ms（大於已觀測到的最大間隔 326ms，留一點餘裕），並在下方 Task 1 用真機側錄到的實際間隔數值直接重播成回歸測試，而非只測抽象的「兩次點擊間隔小於門檻」情境。EPUB／PDF 兩個呼叫端目前都採用同一個值（比照 `tapSlop` 兩邊皆為 18.0 但仍分別明確注入的既有慣例）——**與 `tapMaxDurationMs` 相同，這是一個時間類數值，350ms 是根據本次已側錄到的具體證據推出的起始值，不是憑空選的，但仍可能需要真機使用一段時間後再校準**（例如是否誤傷「使用者刻意快速連續點擊翻好幾頁」這種正常操作模式），比照 `epic-25` Issue 1／`epic-26` Issue 3 先例，若真機使用後回報有需要調整，應另立工單處理，不在本計畫的驗收範圍內。

## Global Constraints

- 只修改 `app/lib/reader/tap_zone_detector.dart`、`app/test/reader/tap_zone_detector_test.dart`、`app/lib/reader/foliate_reader_view.dart`、`app/lib/reader/pdf_reader_view.dart` 四個檔案——後兩者的改動僅止於「新增 `tapDebounceMs: 350` 這一行參數」，不做其他修改。
- 不修改 `paginator.js`／`main.js`（本 Issue 根因是觸控硬體層級，與 vendored JS 或 `no-swipe` 無關，見 `bugfix-repro.md` 診斷結論）。
- 每個 Task 完成後跑 `flutter analyze`，維持乾淨。

---

### Task 1：`TapZoneDetector` 新增 `tapDebounceMs` 防彈跳機制

**Files:**
- Modify: `app/lib/reader/tap_zone_detector.dart`
- Modify: `app/lib/reader/foliate_reader_view.dart`（新增建構參數，約第 826-832 行）
- Modify: `app/lib/reader/pdf_reader_view.dart`（新增建構參數，約第 979-986 行）
- Test: `app/test/reader/tap_zone_detector_test.dart`

**Interfaces:**
- Consumes: 無新增——沿用既有 `nowMs`（計時來源注入）。
- Produces: `TapZoneDetector` 新增一個 **必要（`required`）** 建構參數 `final int tapDebounceMs`，兩個生產呼叫端（`FoliateReaderView`、`PdfReaderView`）都需要同步補上這個參數才能通過編譯，見下方 Step 3。

- [ ] **Step 1：寫失敗測試——三則新測試涵蓋「同格熱區彈跳只放行第一次」「真機實際側錄間隔的回歸重播」「超過門檻後仍正常觸發（非永久鎖死）」**

編輯 `app/test/reader/tap_zone_detector_test.dart`，先把 `wrap()` 輔助函式加上 `tapDebounceMs` 參數：

```dart
  Widget wrap({
    required VoidCallback onTap,
    required int Function() nowMs,
    int tapMaxDurationMs = 400,
    double tapSlop = 18.0,
    int tapDebounceMs = 350,
  }) {
    return MaterialApp(
      home: TapZoneDetector(
        onTap: onTap,
        nowMs: nowMs,
        tapMaxDurationMs: tapMaxDurationMs,
        tapSlop: tapSlop,
        tapDebounceMs: tapDebounceMs,
        child: const SizedBox(width: 100, height: 100),
      ),
    );
  }
```

於既有第 5 則測試（第 99-123 行，`onPointerMove` 熔斷那則）之後、`}` （`main()` 結尾）之前，新增以下 3 則測試：

```dart
  testWidgets(
      '短時間內同一格熱區收到第二次觸發（模擬觸控硬體彈跳）時，只有第一次觸發 onTap（epic-27-reader-device-compat Issue 12）',
      (tester) async {
    var tapCount = 0;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapCount++,
      nowMs: () => fakeNowMs,
      tapDebounceMs: 350,
    ));

    final firstGesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await firstGesture.up();
    await tester.pump();
    expect(tapCount, 1);

    // 第二次觸發發生在 100ms 後（< 350ms 防彈跳門檻），應被視為硬體彈跳
    // 雜訊忽略。
    fakeNowMs += 100;
    final secondGesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await secondGesture.up();
    await tester.pump();
    expect(tapCount, 1,
        reason: '第二次觸發在防彈跳門檻（350ms）內，應被忽略，tapCount 應維持 1');
  });

  testWidgets(
      '重現真機 adb getevent 側錄到的實際硬體彈跳間隔（7 次按下，共 1.119 秒），只觸發 1 次 onTap（epic-27-reader-device-compat Issue 12，間隔數值取自 bugfix-repro.md「Issue 10」新問題 B 段落）',
      (tester) async {
    var tapCount = 0;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapCount++,
      nowMs: () => fakeNowMs,
      tapDebounceMs: 350,
    ));

    final firstGesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 20;
    await firstGesture.up();
    await tester.pump();

    // 真機側錄到的 6 段相鄰「按下→按下」（DOWN to DOWN）事件間隔（毫秒），
    // 依序重播。迴圈內先扣掉本次模擬按壓耗時（20ms）再推進，確保兩次
    // startGesture() 之間量到的 DOWN-to-DOWN 間隔精確等於 gapMs 本身
    // （而非 gapMs + 20）；真機原始資料的實際持壓時間逐次不同（約
    // 20～40ms），此處用固定 20ms 近似，不影響本測試驗證的重點（防彈跳
    // 機制比對的是 UP-to-UP 間隔，用 DOWN-to-DOWN 間隔重播是更保守的
    // 模擬，只會讓相鄰兩次判定的實際間隔略大於等於真機數值，不會讓測試
    // 更容易通過）。
    const observedGapsMs = [86, 152, 261, 326, 87, 207];
    for (final gapMs in observedGapsMs) {
      fakeNowMs += gapMs - 20;
      final gesture = await tester.startGesture(const Offset(50, 50));
      fakeNowMs += 20;
      await gesture.up();
      await tester.pump();
    }

    expect(tapCount, 1,
        reason: '真機側錄到的硬體彈跳序列共 7 次獨立按下/放開，防彈跳機制'
            '應只放行第一次，其餘 6 次皆須被吸收，tapCount 應維持 1');
  });

  testWidgets(
      '間隔超過防彈跳門檻後再次點擊，仍正常觸發 onTap（確認是節流而非永久鎖死同一格熱區）',
      (tester) async {
    var tapCount = 0;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapCount++,
      nowMs: () => fakeNowMs,
      tapDebounceMs: 350,
    ));

    final firstGesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await firstGesture.up();
    await tester.pump();
    expect(tapCount, 1);

    // 間隔 400ms（> 350ms 門檻），應視為使用者刻意的下一次點擊，正常觸發。
    fakeNowMs += 400;
    final secondGesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await secondGesture.up();
    await tester.pump();
    expect(tapCount, 2,
        reason: '間隔已超過防彈跳門檻，不應被誤判為彈跳雜訊，須正常觸發第二次');
  });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/reader/tap_zone_detector_test.dart`
預期：新增的 3 則測試因為 `TapZoneDetector` 尚未接受 `tapDebounceMs` 參數而**編譯失敗**（`tapDebounceMs` 為未定義的具名參數）；也代表既有 5 則測試會一併無法執行（同一個檔案編譯失敗）。這是預期中的紅燈——先確認錯誤訊息是「找不到 `tapDebounceMs`」這個編譯錯誤，而不是其他無關錯誤。

- [ ] **Step 3：實作 `tapDebounceMs` 防彈跳機制，同步更新兩個生產呼叫端**

編輯 `app/lib/reader/tap_zone_detector.dart`，於 class doc 註解最後一段（第 43-46 行，說明 `onPointerMove` 熔斷那段）之後新增一段文件註解：

```dart
///
/// [tapDebounceMs] 防彈跳（Epic 27 Issue 12）：真機用 `adb shell getevent`
/// 直接側錄觸控 IC 原始硬體訊號，證實裝置存在觸控「彈跳」現象——單一次
/// 實體按壓被觸控 IC 誤報成多筆獨立的按下/放開事件，且座標幾乎不動（見
/// `docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md`
/// 「Issue 10」新問題 B 段落）。`TapZoneDetector` 忠實地將每一筆硬體回報
/// 的獨立按下/放開都判定為合法的快速點擊，逐一觸發 [onTap]，造成連續
/// 失控翻頁。[onPointerUp] 內每次「快速點擊」判定成立時，記錄下時間點
/// （[_lastQualifyingTapUpTimeMs]）；若距離上一次同樣判定成立的時間點
/// 尚未超過 [tapDebounceMs]，視為同一次實體按壓的彈跳雜訊，忽略、不呼叫
/// [onTap]（但仍更新時間點，讓冷卻窗隨每一次彈跳訊號延續，確保整段彈跳
/// 序列不論長短都只會放行第一筆）。與 [tapMaxDurationMs]／[tapSlop] 比照
/// 同樣的既定設計哲學，作為呼叫端必要注入參數，不在本 module 內設共用
/// 預設值。
```

於 `class TapZoneDetector` 新增欄位與建構參數：

```dart
class TapZoneDetector extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final int Function() nowMs;
  final int tapMaxDurationMs;
  final double tapSlop;
  final int tapDebounceMs;

  const TapZoneDetector({
    super.key,
    required this.onTap,
    required this.child,
    required this.nowMs,
    required this.tapMaxDurationMs,
    required this.tapSlop,
    required this.tapDebounceMs,
  });
```

於 `_TapZoneDetectorState` 新增欄位，並改寫 `onPointerUp`：

```dart
class _TapZoneDetectorState extends State<TapZoneDetector> {
  Offset? _downPosition;
  int? _downTimeMs;
  int? _lastQualifyingTapUpTimeMs;
```

```dart
      onPointerUp: (event) {
        final downPosition = _downPosition;
        final downTimeMs = _downTimeMs;
        if (downPosition == null || downTimeMs == null) return;
        final nowMsValue = widget.nowMs();
        final elapsed = nowMsValue - downTimeMs;
        final distance = (event.position - downPosition).distance;
        if (elapsed <= widget.tapMaxDurationMs &&
            distance <= widget.tapSlop) {
          final previousTapUpTimeMs = _lastQualifyingTapUpTimeMs;
          _lastQualifyingTapUpTimeMs = nowMsValue;
          if (previousTapUpTimeMs != null &&
              nowMsValue - previousTapUpTimeMs < widget.tapDebounceMs) {
            // 距離上一次「快速點擊」判定成立未滿防彈跳門檻，判定為觸控
            // 硬體彈跳雜訊，忽略（Epic 27 Issue 12）。
            return;
          }
          widget.onTap();
        }
      },
```

編輯 `app/lib/reader/foliate_reader_view.dart`（約第 826-832 行），於既有 `tapSlop: 18.0,` 之後新增一行：

```dart
                        nowMs: () => DateTime.now().millisecondsSinceEpoch,
                        tapMaxDurationMs: 700,
                        tapSlop: 18.0,
                        // epic-27-reader-device-compat Issue 12：真機
                        // adb getevent 側錄證實此裝置觸控 IC 存在彈跳
                        // 現象，最大觀測間隔 326ms，見
                        // tap_zone_detector.dart class doc。
                        tapDebounceMs: 350,
```

編輯 `app/lib/reader/pdf_reader_view.dart`（約第 979-986 行），於既有 `tapSlop: 18.0,` 之後新增一行：

```dart
                        nowMs: () => clock.now().millisecondsSinceEpoch,
                        tapMaxDurationMs: 400,
                        tapSlop: 18.0,
                        // epic-27-reader-device-compat Issue 12：理由同
                        // foliate_reader_view.dart 對應位置註解。
                        tapDebounceMs: 350,
```

- [ ] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/reader/tap_zone_detector_test.dart`
預期：全數 8 則測試 PASS（含 Step 1 新增的 3 則，以及既有 5 則零回歸）。

- [ ] **Step 5：執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS，零回歸。`TapZoneDetector` 被 `foliate_reader_view.dart`／`pdf_reader_view.dart` 共用，需特別留意兩邊既有的 nav-zone 相關測試（例如 `pdf_reader_view_nav_zone_test.dart`、`reader_screen_test.dart` 內熱區點擊相關測試）維持通過——這些既有測試的點擊時間間隔皆遠大於 350ms（多半是單次點擊或間隔數秒的操作），理論上不受新增的防彈跳窗口影響，仍建議全專案跑一次確認。

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/tap_zone_detector.dart app/lib/reader/foliate_reader_view.dart app/lib/reader/pdf_reader_view.dart app/test/reader/tap_zone_detector_test.dart
git commit -m "fix(epic-27): Issue 12——TapZoneDetector 新增 tapDebounceMs 防彈跳機制，吸收觸控硬體彈跳訊號"
```

---

## 完成後的驗證（對照 `issues.md` Issue 12 驗收標準）

- [ ] `flutter analyze`：全專案 "No issues found!"
- [ ] `flutter test`：全專案通過，零回歸
- [ ] （建議，非本計畫強制自動化）真機（比照本 Epic 既有先例，於曾經回報過本問題的裝置）驗證：反覆快速按壓同一熱區，確認不再出現連續失控翻頁與畫面殘影；同時確認正常的單次點擊翻頁、以及間隔明顯（>350ms）的刻意連續翻頁操作不受影響。
- [ ] 350ms 這個門檻值若真機使用後回報有需要調整（例如誤傷正常快速連續翻頁），比照 `epic-25` Issue 1／`epic-26` Issue 3 先例，另立後續工單處理，不阻塞本計畫驗收。
