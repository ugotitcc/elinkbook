# Epic 31 Issue 3：TapZoneDetector 常數收斂＋PDF 門檻對齊 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `app/lib/reader/tap_zone_detector.dart` 新增 `kTapZoneSlop`／`kTapZoneDebounceMs` 兩個模組級共用常數，讓 EPUB／PDF 兩端呼叫端不再各自重複宣告完全相同的字面值；並把 PDF 端 `tapMaxDurationMs` 從未校準的 400ms 改為對齊 EPUB 端已校準的 700ms（刻意決定、明確不做真機驗證）。

**Architecture:** `tapSlop`／`tapDebounceMs` 兩端數值本來就完全相同（皆為 18.0／350），純粹是宣告位置重複，因此收斂成建構子具名參數的**預設值**（`this.tapSlop = kTapZoneSlop`），呼叫端不再傳這兩個引數即可套用共用值。`tapMaxDurationMs` **不**跟進設預設值——EPUB 的 700ms 是真機校準值、PDF 改成的 700ms 是本次刻意對齊但未經真機驗證的決定，兩者數值雖然變得相同，但脈絡不同，維持兩端各自明確傳字面值，把這個差異留在程式碼裡。這是一個小範圍、風格統一 + 一個數值變更的任務，不涉及手勢判斷邏輯本身的行為改寫。

**Tech Stack:** Flutter/Dart（`app/lib/reader/tap_zone_detector.dart` 及其兩個呼叫端 `foliate_reader_view.dart`／`pdf_reader_view.dart`）；`flutter_test` widget test。

**Spec:** `docs/epics/epic-31-touch-intent-unification/design.md`（「整體機制」> Dart 端：TapZoneDetector 常數收斂、「測試策略」> Dart 端）；工單描述見 `docs/epics/epic-31-touch-intent-unification/issues.md` Issue 3。

## Global Constraints

- `kTapZoneSlop = 18.0`／`kTapZoneDebounceMs = 350`：數值本身不可變動，只收斂宣告位置。
- `tapMaxDurationMs` 維持 EPUB／PDF 兩端**各自明確傳入字面值**，不設共用預設值——即使本次改動後兩者數值剛好都是 700，也不可合併成同一個常數/預設值，理由需保留在程式碼註解裡（校準狀態不同：EPUB 已真機校準，PDF 未經真機驗證）。
- PDF 端 `tapMaxDurationMs` 700ms **不做真機驗證**——這是使用者已知情並接受的風險，若之後真機回報「PDF 長按判斷變得比預期遲鈍」，需另立工單依真機資料重新校準（比照 Epic 25 Issue 1／Epic 26 Issue 3 先例），不在本工單範圍內處理。
- 只修改 `app/lib/reader/tap_zone_detector.dart`／`app/lib/reader/foliate_reader_view.dart`／`app/lib/reader/pdf_reader_view.dart` 三個檔案的既有 `TapZoneDetector` 建構呼叫與其宣告本身，以及對應的測試檔；不修改任何 vendored 檔案，不修改 `main.js`（本工單與 Epic 31 Issue 1/2 完全獨立，可平行進行，不依賴、不影響彼此）。
- `flutter analyze` 全程須維持「No issues found!」，`flutter test` 全數通過（提交前必須乾淨）。
- 建議在獨立 git worktree 中執行本計畫（比照 Issue 1/2 慣例，見 `superpowers:using-git-worktrees`），分支名稱 `epic-31-issue-3`。

---

### Task 1：`TapZoneDetector` 新增共用常數＋建構子預設值＋更新 class doc 註解

**Files:**
- Modify: `app/lib/reader/tap_zone_detector.dart`
- Modify: `app/test/reader/tap_zone_detector_test.dart`

**Interfaces:**
- Produces（供 Task 2 使用）：
  - 模組級常數 `const double kTapZoneSlop = 18.0`、`const int kTapZoneDebounceMs = 350`（`app/lib/reader/tap_zone_detector.dart` 頂端，`import` 之後、class 宣告之前）。
  - `TapZoneDetector` 建構子簽章變更：`tapSlop`／`tapDebounceMs` 從 `required` 具名參數改為有預設值的具名參數（`this.tapSlop = kTapZoneSlop`／`this.tapDebounceMs = kTapZoneDebounceMs`），呼叫端可以不傳這兩個引數；`tapMaxDurationMs` 維持 `required`，簽章不變。欄位型別（`final double tapSlop`／`final int tapDebounceMs`）不變。

- [x] **Step 1: 執行既有測試，確認基準線**

```bash
cd app && flutter test test/reader/tap_zone_detector_test.dart
```

Expected: 全數 PASS（重構前基準線，目前 8 個 `testWidgets` 案例）。

- [x] **Step 2: 新增模組級共用常數，建構子改為可選具名參數**

用 Read 工具開啟 `app/lib/reader/tap_zone_detector.dart`，找到：

```dart
import 'package:flutter/widgets.dart';

/// 九宮格導覽熱區的單一格子共用偵測器（Epic 26 Issue 2，收斂自
```

改為：

```dart
import 'package:flutter/widgets.dart';

/// EPUB／PDF 兩端共用的九宮格熱區點擊容許位移／防彈跳門檻（Epic 31
/// Issue 3：`TapZoneDetector` 常數收斂）。兩端原本各自宣告完全相同的
/// 數值（`tapSlop: 18.0`／`tapDebounceMs: 350`），純粹是宣告位置重複，
/// 收斂成這裡的模組級常數，供下方建構子當作預設值使用，呼叫端不再需要
/// 各自重複宣告，見下方 [TapZoneDetector.tapSlop]／
/// [TapZoneDetector.tapDebounceMs] 說明。
const double kTapZoneSlop = 18.0;
const int kTapZoneDebounceMs = 350;

/// 九宮格導覽熱區的單一格子共用偵測器（Epic 26 Issue 2，收斂自
```

再找到（class doc 內描述 `tapMaxDurationMs`／`tapSlop` 的段落）：

```dart
/// [tapMaxDurationMs]／[tapSlop] 同樣為呼叫端注入參數，刻意不在本
/// module 內設共用預設值/常數——EPUB 現行 700ms（`epic-25` Issue 1
/// 六輪真機診斷校準值）與 PDF 現行 400ms（原始未校準值）已被查證存在
/// 真實差異，兩者適用的正確門檻值可能本來就不同（見 Epic 26 Issue 3，
/// 需真機診斷才能定案 PDF 端數值，不可貿然套用 EPUB 數值），故此次收斂
/// 刻意只共用「偵測機制本身」（含 [onPointerCancel] 防禦性清理），不
/// 共用數值。
```

改為：

```dart
/// [tapMaxDurationMs] 為呼叫端注入參數，刻意不在本 module 內設共用預設
/// 值/常數——EPUB 現行 700ms（`epic-25` Issue 1 六輪真機診斷校準值）與
/// PDF 現行 400ms（原始未校準值）已被查證存在真實差異，兩者適用的正確
/// 門檻值可能本來就不同（見 Epic 26 Issue 3，需真機診斷才能定案 PDF 端
/// 數值，不可貿然套用 EPUB 數值），故刻意維持各自宣告字面值，不共用
/// 數值（epic-31-touch-intent-unification Issue 3 待辦：本工單稍後會把
/// PDF 端數值改為對齊 EPUB 的 700ms，屆時這段說明會再更新，見 Task 2）。
/// [tapSlop] 已收斂為模組級共用常數 [kTapZoneSlop]（見上方宣告），呼叫端
/// 不再需要各自宣告——EPUB／PDF 兩端這個欄位的數值本來就完全相同（皆為
/// 18.0），純粹是宣告位置重複，不像 [tapMaxDurationMs] 存在真實的校準
/// 狀態差異。
```

（這段暫時保留「PDF 現行 400ms」的敘述——本 Task 只改 `tapSlop`，PDF 呼叫端此刻仍是 400ms，Task 2 才會改成 700ms 並回頭再更新這段文字，避免文件在任何一個 Task 邊界上暫時失真。）

再找到：

```dart
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

改為：

```dart
  const TapZoneDetector({
    super.key,
    required this.onTap,
    required this.child,
    required this.nowMs,
    required this.tapMaxDurationMs,
    this.tapSlop = kTapZoneSlop,
    this.tapDebounceMs = kTapZoneDebounceMs,
  });
```

- [x] **Step 3: 新增測試驗證常數值與建構子預設值**

用 Read 工具開啟 `app/test/reader/tap_zone_detector_test.dart`，找到檔案結尾：

```dart
    expect(tapCount, 2);
  });
}
```

改為（在最後一個 `testWidgets` 之後、`main()` 結尾 `}` 之前插入 3 個新測試）：

```dart
    expect(tapCount, 2);
  });

  test('kTapZoneSlop 為 EPUB／PDF 共用的位移容許值 18.0', () {
    expect(kTapZoneSlop, 18.0);
  });

  test('kTapZoneDebounceMs 為 EPUB／PDF 共用的防彈跳門檻 350ms', () {
    expect(kTapZoneDebounceMs, 350);
  });

  testWidgets(
      '未明確傳入 tapSlop 時，建構子預設值等同 kTapZoneSlop——位移剛好超過 '
      'kTapZoneSlop 仍會被判定為超出容許範圍，不觸發 onTap',
      (tester) async {
    var tapped = false;
    var fakeNowMs = 1000;
    await tester.pumpWidget(
      MaterialApp(
        home: TapZoneDetector(
          onTap: () => tapped = true,
          nowMs: () => fakeNowMs,
          tapMaxDurationMs: 400,
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await gesture.moveTo(Offset(50, 50 + kTapZoneSlop + 1));
    await gesture.up();
    await tester.pump();

    expect(tapped, isFalse,
        reason: '若建構子預設值不是 kTapZoneSlop（例如意外退回舊的某個字面值），'
            '這個剛好超過 kTapZoneSlop 的位移可能不會被正確判定為超出範圍');
  });
}
```

**驗證要點**（不是新規則，只是確認這個測試真的測到了預設值）：這個新測試刻意**不傳** `tapSlop` 具名參數，完全依賴建構子的 `this.tapSlop = kTapZoneSlop` 預設值；若 Step 2 的預設值設定有誤（例如打錯常數名稱、或忘了拿掉 `required`），這個測試會因為編譯錯誤或行為不符直接失敗。

- [x] **Step 4: 執行測試，確認新測試通過且既有測試未受影響**

```bash
cd app && flutter test test/reader/tap_zone_detector_test.dart
```

Expected: 全數 PASS（原本 8 個既有案例 + 新增 3 個，共 11 個）。

- [x] **Step 5: `flutter analyze` 確認乾淨**

```bash
cd app && flutter analyze
```

Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/tap_zone_detector.dart app/test/reader/tap_zone_detector_test.dart
git commit -m "refactor(epic-31): TapZoneDetector 新增 kTapZoneSlop/kTapZoneDebounceMs 共用常數"
```

---

### Task 2：EPUB／PDF 呼叫端改用共用常數＋PDF 門檻對齊 700ms

**Files:**
- Modify: `app/lib/reader/foliate_reader_view.dart`
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/lib/reader/tap_zone_detector.dart`（回頭更新 Task 1 暫時保留的 class doc 段落）
- Modify: `app/test/reader/pdf_reader_view_nav_zone_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `kTapZoneSlop`／`kTapZoneDebounceMs`（已是 `TapZoneDetector` 建構子預設值，呼叫端只需要**不再傳** `tapSlop`／`tapDebounceMs` 這兩個具名引數即可套用）。
- Produces: 無新增（本 Task 是把 Task 1 建立的預設值機制實際接上兩個呼叫端）。

- [x] **Step 1: 執行既有測試，確認 Task 1 完成後的基準線**

```bash
cd app && flutter test test/reader/tap_zone_detector_test.dart test/reader/foliate_reader_view_test.dart test/reader/pdf_reader_view_nav_zone_test.dart
```

Expected: 全數 PASS。

- [x] **Step 2: EPUB 呼叫端移除字面值，改用建構子預設值**

用 Read 工具開啟 `app/lib/reader/foliate_reader_view.dart`，找到：

```dart
                      child: TapZoneDetector(
                        key: Key('nav_zone_$index'),
                        // Epic 26 Issue 1 校準值（epic-25 Issue 1 六輪
                        // 真機診斷得出，見 TapZoneDetector class doc）。
                        nowMs: () => DateTime.now().millisecondsSinceEpoch,
                        tapMaxDurationMs: 700,
                        tapSlop: 18.0,
                        // Epic 27 Issue 12 防彈跳門檻（吸收真機觸控硬體彈跳雜訊）
                        tapDebounceMs: 350,
                        onTap: () {
```

改為：

```dart
                      child: TapZoneDetector(
                        key: Key('nav_zone_$index'),
                        // Epic 26 Issue 1 校準值（epic-25 Issue 1 六輪
                        // 真機診斷得出，見 TapZoneDetector class doc）。
                        // tapSlop／tapDebounceMs 改用建構子預設值
                        // （kTapZoneSlop／kTapZoneDebounceMs，epic-31
                        // Issue 3 常數收斂），不再各自宣告字面值。
                        nowMs: () => DateTime.now().millisecondsSinceEpoch,
                        tapMaxDurationMs: 700,
                        onTap: () {
```

- [x] **Step 3: PDF 呼叫端移除字面值、門檻對齊 700ms**

用 Read 工具開啟 `app/lib/reader/pdf_reader_view.dart`，找到：

```dart
                      child: TapZoneDetector(
                        key: Key('pdf_reader_nav_zone_$index'),
                        // 原始未校準值——是否需要比照 epic-25 Issue 1
                        // 真機診斷調整，追蹤於 Epic 26 Issue 3，本次收斂
                        // 刻意不變更數值本身。
                        nowMs: () => clock.now().millisecondsSinceEpoch,
                        tapMaxDurationMs: 400,
                        tapSlop: 18.0,
                        // Epic 27 Issue 12 防彈跳門檻（吸收真機觸控硬體彈跳雜訊）
                        tapDebounceMs: 350,
                        onTap: () => widget.onZoneAction?.call(action),
```

改為：

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
                        onTap: () => widget.onZoneAction?.call(action),
```

- [x] **Step 4: 確認呼叫端已不再寫死這兩個引數（grep 驗證）**

```bash
grep -n "tapSlop:\|tapDebounceMs:" app/lib/reader/foliate_reader_view.dart app/lib/reader/pdf_reader_view.dart
```

Expected: 無任何輸出——兩個呼叫端都已改成完全依賴 `TapZoneDetector` 建構子的預設值（`kTapZoneSlop`／`kTapZoneDebounceMs`），這正是「呼叫端確實使用該常數、不寫死字面值」的直接證據：呼叫端連常數名稱都不需要重複打一次，值完全來自單一宣告來源（`tap_zone_detector.dart` 的建構子預設值）。

- [x] **Step 5: 回頭更新 `tap_zone_detector.dart` class doc，反映 PDF 端已對齊 700ms**

用 Read 工具開啟 `app/lib/reader/tap_zone_detector.dart`，找到 Task 1 Step 2 暫時保留的這段：

```dart
/// [tapMaxDurationMs] 為呼叫端注入參數，刻意不在本 module 內設共用預設
/// 值/常數——EPUB 現行 700ms（`epic-25` Issue 1 六輪真機診斷校準值）與
/// PDF 現行 400ms（原始未校準值）已被查證存在真實差異，兩者適用的正確
/// 門檻值可能本來就不同（見 Epic 26 Issue 3，需真機診斷才能定案 PDF 端
/// 數值，不可貿然套用 EPUB 數值），故刻意維持各自宣告字面值，不共用
/// 數值（epic-31-touch-intent-unification Issue 3 待辦：本工單稍後會把
/// PDF 端數值改為對齊 EPUB 的 700ms，屆時這段說明會再更新，見 Task 2）。
/// [tapSlop] 已收斂為模組級共用常數 [kTapZoneSlop]（見上方宣告），呼叫端
/// 不再需要各自宣告——EPUB／PDF 兩端這個欄位的數值本來就完全相同（皆為
/// 18.0），純粹是宣告位置重複，不像 [tapMaxDurationMs] 存在真實的校準
/// 狀態差異。
```

改為：

```dart
/// [tapMaxDurationMs] 為呼叫端注入參數，刻意不在本 module 內設共用預設
/// 值/常數——EPUB 的 700ms 是 `epic-25` Issue 1 六輪真機診斷校準值，PDF
/// 的 700ms 是 epic-31-touch-intent-unification Issue 3 刻意對齊、未經
/// 真機驗證的決定，兩者數值現在剛好相同，但校準狀態不同，各自明確傳值
/// 才能讓這個差異留在程式碼裡，不被「常數收斂」的動作悄悄合併掉（若之後
/// 真機回報 PDF 端門檻不合適，需另立工單依真機資料重新校準，比照
/// `epic-25` Issue 1／Epic 26 Issue 3 先例，不可逕自沿用 EPUB 數值）。
/// [tapSlop] 已收斂為模組級共用常數 [kTapZoneSlop]（見上方宣告），呼叫端
/// 不再需要各自宣告——EPUB／PDF 兩端這個欄位的數值本來就完全相同（皆為
/// 18.0），純粹是宣告位置重複，不像 [tapMaxDurationMs] 存在真實的校準
/// 狀態差異。
```

- [x] **Step 6: 修正 PDF 門檻改變後失真的既有測試**

用 Read 工具開啟 `app/test/reader/pdf_reader_view_nav_zone_test.dart`，找到（測試名稱「按壓超過快速點擊時長判定門檻不觸發 onZoneAction，避免與長按選取手勢衝突」內）：

```dart
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pdf_reader_nav_zone_4'))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();

    expect(triggered, isNull);
    await tester.pump(const Duration(milliseconds: 400));
  });
```

改為：

```dart
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pdf_reader_nav_zone_4'))),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.up();
    await tester.pump();

    expect(triggered, isNull);
    await tester.pump(const Duration(milliseconds: 400));
  });
```

**為什麼必須改**：這個測試驗證「按壓時間超過快速點擊門檻時不觸發 `onZoneAction`」。門檻改成 700ms 之前，600ms 已經超過舊門檻（400ms），測試成立；門檻改成 700ms 之後，600ms 反而落在**合格點擊範圍內**（600 ≤ 700），會被判定為一次快速點擊而觸發 `onZoneAction`，導致 `expect(triggered, isNull)` 失敗——把等待時間改成 800ms（> 700ms 新門檻）才能維持這個測試原本要驗證的意圖。

- [x] **Step 7: 執行完整測試，確認全數通過**

```bash
cd app && flutter test test/reader/tap_zone_detector_test.dart test/reader/foliate_reader_view_test.dart test/reader/pdf_reader_view_nav_zone_test.dart
```

Expected: 全數 PASS。

- [x] **Step 8: `flutter analyze` 確認乾淨**

```bash
cd app && flutter analyze
```

Expected: `No issues found!`

- [x] **Step 9: Commit**

```bash
git add app/lib/reader/foliate_reader_view.dart app/lib/reader/pdf_reader_view.dart app/lib/reader/tap_zone_detector.dart app/test/reader/pdf_reader_view_nav_zone_test.dart
git commit -m "refactor(epic-31): EPUB/PDF 改用 TapZoneDetector 共用常數，PDF 門檻對齊 700ms"
```

---

### Task 3：全域驗收＋更新工單狀態

**Files:**
- Modify: `docs/epics/epic-31-touch-intent-unification/issues.md`

**Interfaces:**
- Consumes: Task 1-2 完成後的 `tap_zone_detector.dart`／`foliate_reader_view.dart`／`pdf_reader_view.dart`。
- Produces: 無（本 Task 是驗收與收尾）。

- [x] **Step 1: 全專案 `flutter analyze`**

```bash
cd app && flutter analyze
```

Expected: `No issues found!`

- [x] **Step 2: 全專案 `flutter test`**

```bash
cd app && flutter test
```

Expected: 全數 PASS，比對 Epic 31 Issue 2 合併時記錄的基準（`reviews/review-issue-2.md`：1690/1690 PASS）——本工單只新增 3 個測試（Task 1 Step 3），總數應為 1693/1693 PASS 左右（實際數字以執行結果為準，重點是「全數 PASS、無 SKIP、無新增失敗」）。

- [x] **Step 3: 確認未修改範圍外的檔案**

```bash
git diff --stat main -- app/lib app/test
```

Expected: 只列出 `app/lib/reader/tap_zone_detector.dart`／`app/lib/reader/foliate_reader_view.dart`／`app/lib/reader/pdf_reader_view.dart`／`app/test/reader/tap_zone_detector_test.dart`／`app/test/reader/pdf_reader_view_nav_zone_test.dart` 這 5 個檔案，沒有其他 Dart 檔案被異動。

- [x] **Step 4: 更新工單狀態**

在 `docs/epics/epic-31-touch-intent-unification/issues.md` Issue 3 的 `**Status:**` 那一行，改為記錄已完成（PR 編號待實際發 PR 時補上），並在下方補一段簡短總結：`kTapZoneSlop`/`kTapZoneDebounceMs` 常數已收斂、EPUB／PDF 呼叫端已不再各自宣告字面值、PDF `tapMaxDurationMs` 已對齊 700ms（未經真機驗證，風險已記錄於程式碼註解），`flutter analyze`／`flutter test` 皆通過。

- [x] **Step 5: Commit**

```bash
git add docs/epics/epic-31-touch-intent-unification/issues.md
git commit -m "docs(epic-31): 更新 Issue 3 工單狀態為完成"
```
