# Epic 25 Issue 5 — PDF 長按拖曳建立標註彈跳容忍度實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 PDF 長按拖曳建立劃線/備註這個手勢，在觸控雜訊（彈跳）較嚴重的裝置上也能穩定啟動並完成選取——真機資料證實裝置 2 整段操作 48 次按壓、0 次成功啟動長按。

**Architecture:** 新增 `app/lib/reader/bounce_tolerant_long_press_detector.dart`（`BounceTolerantLongPressDetector`），比照 `TapZoneDetector`（`tap_zone_detector.dart`）的架構——用不參與手勢競技場的 `Listener` 取代 Flutter 內建 `GestureDetector`／`LongPressGestureRecognizer`，自己維護「目前按壓是否仍算存活」的狀態機。兩個真機校準過的既有常數（`kTapZoneDebounceMs`＝350ms、`kTapZoneSlop`＝18px）直接複用當彈跳合併判定的預設門檻，不重新發明。`app/lib/reader/pdf_reader_view.dart` 的 `_buildSelectionGestureLayer()` 改用這個新元件，選取狀態管理邏輯（`_selectionDrag`／`_selectionDragGenerationId`／`_finishSelectionDrag()`／`_cancelSelectionDrag()`）完全不變動。

**Tech Stack:** Flutter/Dart（`Listener`、`dart:async` 的 `Timer`、`package:clock`），無新增第三方套件。

**Spec:** `docs/epics/epic-25-annotation-interaction-qa/issues.md`（Issue 5，含 2026-08-31 `/grill-with-docs` 敲定的 Solution 段落）。

## Global Constraints

- 彈跳合併判定門檻**沿用既有真機校準常數**：時間門檻＝`kTapZoneDebounceMs`（350ms），位置門檻＝`kTapZoneSlop`（18px），皆從 `tap_zone_detector.dart` import，不重複宣告字面值。
- 長按判定時長維持 Flutter 預設的 `kLongPressTimeout`（500ms，`package:flutter/gestures.dart`），改為建構參數注入，不寫死字面值 500。**注意**：`kLongPressTimeout.inMilliseconds` 是執行期 getter、不是編譯期常數，不能直接當 `const` 建構子的可選參數預設值（`const_eval_property_access` 編譯錯誤，規劃階段已實測驗證）——正確做法是參數宣告為 `int? longPressDurationMs`（預設 `null`），State 內部用一個 `int get _effectiveDurationMs => widget.longPressDurationMs ?? kLongPressTimeout.inMilliseconds;` 取得有效值，所有內部邏輯改讀這個 getter，不直接讀 `widget.longPressDurationMs`（`reviews/review-plan-issue-5.md` 第二輪 Critical Finding 1 修訂意見）。
- **已知、經審查確認可接受的邊界情況（非本計畫範圍，暫不修復）**：已進入拖曳階段（`_isActive == true`）、手指剛放開、`mergeGapMs`（350ms）寬限期內若使用者在明顯不同的位置快速按下一次不相關的新觸碰，會被目前設計吞成「原本那次拖曳的延續」，導致選取矩形跳到新位置。發生機率低（需在 350ms 內、單指、且是使用者主動的新動作而非彈跳雜訊），審查明確判定非本計畫的 Blocker；若之後真機試用發現這個邊界情況會實際干擾正常選取，再另立工單處理，不在本計畫內預先加防禦（`reviews/review-plan-issue-5.md` 第二輪 Important Finding 2）。
- 手勢偵測器須正確拒絕多指觸控（避免與 `PdfViewer` 的縮放/平移手勢衝突、避免誤把第二指的觸碰當成新的長按起點）；`PointerCancelEvent`（系統手勢接管）須立即清除狀態，不套用彈跳合併的寬限期；累積時長跨過門檻但手指剛好不在螢幕上（彈跳空隙或已放開）時不可提前觸發，須等下一次真正按下時立即補上，避免快速點兩下被誤判成幽靈長按、也避免 150-500ms 的正常短按被誤判成長按（`reviews/review-plan-issue-5.md` Critical #1/#3、Important #1 修訂意見）。
- 已進入拖曳階段（`_isActive == true`）後收到的任何新 `down`，一律視為同一次手勢的延續並直接更新位置，不再套用位移門檻判斷、也不可在未呼叫 `onLongPressEnd`/`onLongPressCancel` 的情況下直接重置狀態，避免 `_selectionDrag` 卡在非 null、選取框殘留畫面（`reviews/review-plan-issue-5.md` Critical #2 修訂意見）。
- 選取起點（`onLongPressStart` 回呼收到的座標）固定為整串延續裡「最早那次 `down`」的位置，不隨雜訊延續而改變。
- `_selectionDragGenerationId` 的遞增時機（只在真正一次全新的長按啟動時遞增一次，位置在 `pdf_reader_view.dart:1147`）維持不變，本計畫不修改這段邏輯本身，只替換觸發它的手勢偵測機制。
- 座標一律使用 `PointerEvent.localPosition`（相對於 `_buildSelectionGestureLayer` 的 `Positioned.fill`），**不可用** `.position`（全域座標）——舊版 `GestureDetector` 的 `details.localPosition` 就是這個座標系，`_finishSelectionDrag()` 下游的 `percentRectFromDrag()` 依賴這個座標系假設，用錯會讓選取矩形整個算錯。
- 不調整 `TapZoneDetector`／`tapMaxDurationMs`／`tapSlop` 本身，範圍僅限 `_buildSelectionGestureLayer()` 這個獨立元件。
- 不另排真機插樁診斷這一輪——用已蒐集到的裝置 2 真實彈跳間隔資料（`tmp/epic-25/log-issue5/device-2.txt`）直接寫成自動化回歸測試，修復完成後由人類直接真機試用回報。
- 每個 Task 完成後只需執行該 Task 實際觸及的測試檔；全套 `flutter test` 留到本計畫最後一個 Task 執行一次。提交前 `flutter analyze` 須保持乾淨（"No issues found!"）。

---

### Task 1：新增 `BounceTolerantLongPressDetector` 元件與其專屬單元測試

**Files:**
- Create: `app/lib/reader/bounce_tolerant_long_press_detector.dart`
- Create: `app/test/reader/bounce_tolerant_long_press_detector_test.dart`

**Interfaces:**
- Consumes：`package:flutter/widgets.dart`（`Listener`／`Offset`／`PointerDownEvent` 等）、`package:flutter/gestures.dart`（`kLongPressTimeout`）、`dart:async`（`Timer`）、`package:clock`（`clock.now()`）、`tap_zone_detector.dart` 的 `kTapZoneSlop`／`kTapZoneDebounceMs` 常數。
- Produces：`class BounceTolerantLongPressDetector extends StatefulWidget`，建構參數 `{ Key? key, required Widget child, required void Function(Offset position) onLongPressStart, required void Function(Offset position) onLongPressMoveUpdate, required VoidCallback onLongPressEnd, required VoidCallback onLongPressCancel, int? longPressDurationMs, int mergeGapMs = kTapZoneDebounceMs, double mergeSlop = kTapZoneSlop }`——`longPressDurationMs` 為 `null` 時，內部一律以 `kLongPressTimeout.inMilliseconds`（500ms）作為有效值。Task 2 的 `pdf_reader_view.dart` 呼叫端會直接使用這個建構子簽章。

- [ ] **Step 1：寫失敗測試——真實裝置 2 彈跳資料重播後正確啟動長按並完整跑完一次生命週期**

建立 `app/test/reader/bounce_tolerant_long_press_detector_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/bounce_tolerant_long_press_detector.dart';

void main() {
  Widget wrap({
    required void Function(Offset) onLongPressStart,
    required void Function(Offset) onLongPressMoveUpdate,
    required VoidCallback onLongPressEnd,
    required VoidCallback onLongPressCancel,
    int? longPressDurationMs,
    int mergeGapMs = 350,
    double mergeSlop = 18.0,
  }) {
    return MaterialApp(
      home: BounceTolerantLongPressDetector(
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: onLongPressEnd,
        onLongPressCancel: onLongPressCancel,
        longPressDurationMs: longPressDurationMs,
        mergeGapMs: mergeGapMs,
        mergeSlop: mergeSlop,
        child: const SizedBox(width: 400, height: 400),
      ),
    );
  }

  testWidgets(
      '重現裝置 2 真實彈跳間隔序列（tmp/epic-25/log-issue5/device-2.txt），'
      '長按仍能正確啟動且完整跑完一次生命週期', (tester) async {
    var startCount = 0;
    Offset? startPos;
    var moveCount = 0;
    Offset? lastMovePos;
    var endCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (p) {
        startCount++;
        startPos = p;
      },
      onLongPressMoveUpdate: (p) {
        moveCount++;
        lastMovePos = p;
      },
      onLongPressEnd: () => endCount++,
      onLongPressCancel: () => cancelCount++,
    ));

    // 真實裝置 2 彈跳序列（device-2.txt 前 21 行，相對第一次 down 的毫秒偏移
    // 與座標，已用腳本逐行核對過，非憑空編造）：
    // down t=0   (297.8,401.4)   up t=49
    // down t=69  (297.8,401.4)   up t=134
    // down t=183 (296.4,403.4)   up t=190
    // down t=196 (296.4,403.4)   up t=251
    // down t=253 (296.8,403.4)   up t=255
    // down t=257 (300.3,406.8)   up t=302
    // down t=313 (301.3,407.3)   up t=322
    // down t=399 (309.6,415.2)   up t=409
    // down t=413 (309.6,415.2)   up t=538   ← duration 500ms 門檻在這段區間內跨過
    // down t=548 (311.0,416.6)   up t=559
    // down t=564 (311.0,417.1)   up t=580
    final downTimes = [0, 69, 183, 196, 253, 257, 313, 399, 413, 548, 564];
    final downPositions = [
      const Offset(297.8, 401.4),
      const Offset(297.8, 401.4),
      const Offset(296.4, 403.4),
      const Offset(296.4, 403.4),
      const Offset(296.8, 403.4),
      const Offset(300.3, 406.8),
      const Offset(301.3, 407.3),
      const Offset(309.6, 415.2),
      const Offset(309.6, 415.2),
      const Offset(311.0, 416.6),
      const Offset(311.0, 417.1),
    ];
    final upTimes = [49, 134, 190, 251, 255, 302, 322, 409, 538, 559, 580];

    var lastEventTime = 0;
    for (var i = 0; i < downTimes.length; i++) {
      await tester.pump(Duration(milliseconds: downTimes[i] - lastEventTime));
      final gesture = await tester.startGesture(downPositions[i]);
      lastEventTime = downTimes[i];
      await tester.pump(Duration(milliseconds: upTimes[i] - lastEventTime));
      await gesture.up();
      lastEventTime = upTimes[i];
    }

    // 最後一次放開後，等待超過 mergeGapMs（350ms）且沒有新的延續事件，
    // 判定為真正結束。
    await tester.pump(const Duration(milliseconds: 400));

    expect(startCount, 1, reason: '整串彈跳應被判定成同一次長按，只啟動一次');
    expect(startPos, const Offset(297.8, 401.4),
        reason: '選取起點須固定為最早那次 down 的位置，不隨雜訊飄移');
    expect(moveCount, greaterThan(0),
        reason: '長按啟動後的延續 down（t=548／t=564）應視為位置更新');
    expect(lastMovePos, const Offset(311.0, 417.1));
    expect(endCount, 1, reason: '最終真正放開後應觸發一次 onLongPressEnd');
    expect(cancelCount, 0, reason: '已成功啟動長按，不應該觸發 onLongPressCancel');
  });

  testWidgets('位移超過 mergeSlop 的新 down 視為全新一次按壓，前一次未結束的按壓須先收到取消回呼',
      (tester) async {
    var startCount = 0;
    Offset? startPos;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (p) {
        startCount++;
        startPos = p;
      },
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () => cancelCount++,
    ));

    final first = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await first.up();

    // 間隔 30ms（< 350ms mergeGapMs），但位置差了 200px（> 18px mergeSlop）。
    await tester.pump(const Duration(milliseconds: 30));
    await tester.startGesture(const Offset(200, 200));

    // 從第二次 down 起算滿 500ms，應以第二次 down 的位置啟動長按。
    await tester.pump(const Duration(milliseconds: 500));

    expect(cancelCount, 1,
        reason: '第一次按壓被判定為與新按壓不相關時，須先收到一次取消回呼，'
            '不能被靜默丟棄（避免下游 _selectionDrag 狀態卡住殘留，'
            'review-plan-issue-5.md Critical #2）');
    expect(startCount, 1);
    expect(startPos, const Offset(200, 200),
        reason: '位移過大應判定為全新按壓，起點是新按壓的位置，不是舊按壓的 (0,0)');
  });

  testWidgets('放開後超過 mergeGapMs 沒有延續事件，判定真正取消；之後的新按壓仍可獨立啟動',
      (tester) async {
    var startCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) => startCount++,
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () => cancelCount++,
    ));

    final first = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await first.up();

    // 超過 mergeGapMs（350ms），沒有任何延續事件。
    await tester.pump(const Duration(milliseconds: 400));
    expect(cancelCount, 1, reason: '未達長按時長就真正放開，應觸發一次取消');
    expect(startCount, 0);

    // 之後一次全新、獨立的長按仍應正常運作。
    await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(startCount, 1, reason: '新的獨立按壓不受先前已取消的按壓影響');
  });

  testWidgets('長按啟動前位移超過 mergeSlop，判定為滑動手勢，直接取消、不會啟動長按',
      (tester) async {
    var startCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) => startCount++,
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () => cancelCount++,
    ));

    final gesture = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(const Offset(30, 0)); // 位移 30px > 18px mergeSlop
    await tester.pump(const Duration(milliseconds: 500));

    expect(cancelCount, 1);
    expect(startCount, 0,
        reason: '長按判定成立前若移動過大，應視為滑動手勢，比照原生 '
            'LongPressGestureRecognizer 行為直接取消');
  });

  testWidgets('長按啟動後拖曳中途發生雜訊，位置更新被吸收、不重新觸發啟動/取消',
      (tester) async {
    var startCount = 0;
    final movePositions = <Offset>[];
    var endCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) => startCount++,
      onLongPressMoveUpdate: (p) => movePositions.add(p),
      onLongPressEnd: () => endCount++,
      onLongPressCancel: () => cancelCount++,
    ));

    final gesture = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(startCount, 1);

    await gesture.moveTo(const Offset(50, 50));
    await tester.pump();
    expect(movePositions.last, const Offset(50, 50));

    // 拖曳中途的雜訊：短暫放開又立刻在幾乎同一位置按下（間隔／位移皆在
    // 門檻內），不應該觸發 End/Cancel，矩形應延續更新到新位置。
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.startGesture(const Offset(52, 51));
    await tester.pump(const Duration(milliseconds: 400));

    expect(cancelCount, 0);
    expect(endCount, 0, reason: '拖曳中途的雜訊應被合併吸收，不應提前結束選取');
    expect(movePositions.last, const Offset(52, 51));
  });

  testWidgets('一般快速點擊（未達長按時長且無雜訊）僅觸發一次取消，不影響翻頁熱區',
      (tester) async {
    var startCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) => startCount++,
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () => cancelCount++,
    ));

    final gesture = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(startCount, 0);
    expect(cancelCount, 1);
  });

  testWidgets(
      '雙指觸控應被拒絕且立即取消，不觸發長按；雙指皆放開後新的單指長按仍可正常獨立啟動',
      (tester) async {
    var startCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) => startCount++,
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () => cancelCount++,
    ));

    final first = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    // 第二指觸碰（例如捏合縮放的第二指），距離遠超 mergeSlop。
    final second = await tester.startGesture(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 500));

    expect(startCount, 0, reason: '雙指同時存在時不能啟動長按，避免與縮放/平移手勢衝突');
    expect(cancelCount, 1, reason: '第一指原本 pending 中的按壓應在偵測到第二指時立即取消');

    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 400));

    // 雙指皆放開後，新的一次單指長按應能正常獨立啟動，不受先前拒絕狀態影響。
    await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(startCount, 1);
  });

  testWidgets(
      '快速點擊（含 150-500ms 短按與快速連續點兩下）不應在背景幽靈觸發長按',
      (tester) async {
    var startCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) => startCount++,
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () => cancelCount++,
    ));

    // 情境一：單次持續 300ms 的按壓（介於 mergeGapMs 與 longPressDurationMs
    // 之間，E-Ink 裝置常見），不應在 t=500 被誤判成長按。
    final gesture = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400)); // 超過 mergeGapMs

    expect(startCount, 0, reason: '300ms 的單次按壓不應被誤判成長按');
    expect(cancelCount, 1);

    // 情境二：快速點兩下（Down1@0-Up1@100、Down2@200-Up2@300，皆在
    // mergeGapMs 內合併成同一次按壓），t=500 那一刻手指其實不在螢幕上，
    // 不應該在背景幽靈觸發長按。
    final tap1 = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await tap1.up();
    await tester.pump(const Duration(milliseconds: 100));
    final tap2 = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await tap2.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(startCount, 0, reason: '500ms 那一刻手指不在螢幕上，不應幽靈觸發長按');

    // 再等超過 mergeGapMs，應正確判定為第二次取消。
    await tester.pump(const Duration(milliseconds: 200));
    expect(cancelCount, 2);
  });

  testWidgets('PointerCancelEvent（系統手勢接管）立即取消，不等待彈跳合併寬限期',
      (tester) async {
    var cancelCount = 0;
    var endCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) {},
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () => endCount++,
      onLongPressCancel: () => cancelCount++,
    ));

    final gesture = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.cancel();
    await tester.pump();

    expect(cancelCount, 1, reason: '系統取消應立即觸發，不必等 mergeGapMs 寬限期');
    expect(endCount, 0);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/reader/bounce_tolerant_long_press_detector_test.dart`
Expected: 全數 FAIL（編譯錯誤：`bounce_tolerant_long_press_detector.dart` 尚不存在）。

- [ ] **Step 3：實作 `BounceTolerantLongPressDetector`**

建立 `app/lib/reader/bounce_tolerant_long_press_detector.dart`：

```dart
import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/widgets.dart';
import 'tap_zone_detector.dart' show kTapZoneSlop, kTapZoneDebounceMs;

/// PDF 長按拖曳框選劃線/備註專用的手勢偵測器（Epic 25 Issue 5），取代
/// Flutter 內建 `GestureDetector`／`LongPressGestureRecognizer`——後者完全
/// 不知道「觸控彈跳」這件事：同一根手指持續按住不放，只要硬體回報成一連串
/// 極短暫的獨立 down/up 事件，內建元件的內部計時器每次遇到新的 down 就會
/// 歸零，導致長按永遠無法累積到啟動所需的時長（真機資料證實：裝置 2 整段
/// 操作 48 次按壓、0 次成功啟動，見
/// `docs/epics/epic-25-annotation-interaction-qa/issues.md` Issue 5）。
///
/// 比照 `TapZoneDetector`（見 `tap_zone_detector.dart`）同一套架構：用
/// [Listener]（不參與手勢競技場）直接觀察原始 pointer 事件，不註冊
/// `GestureRecognizer`，讓底層 `PdfViewer` 的原生觸控轉發不受影響。
///
/// **彈跳合併判定**（[mergeGapMs]／[mergeSlop]，預設沿用 `TapZoneDetector`
/// 既有真機校準值 [kTapZoneDebounceMs]／[kTapZoneSlop]）：新的 `down` 若與
/// 上一筆事件時間差 <= [mergeGapMs] 且與「最近一次已知位置」的位移
/// <= [mergeSlop]，視為同一次按壓的延續，不重置按壓起點/計時。這裡刻意用
/// **滑動比對**（跟最近一次已知位置比，不是跟最早的起點比）——真機資料顯示
/// 單一次彈跳爆發期間，位置會緩慢累積飄移，若跟固定起點比對，飄移超過
/// [mergeSlop] 後會被誤判成兩次獨立按壓，反而讓合併失效。
///
/// **長按判定前的位移取消**（[_handleMove] 尚未啟動長按時）則刻意改成跟
/// **固定起點**比對，比照原生 `LongPressGestureRecognizer` 行為——這段位移
/// 來自單一連續觸控的 move 事件（不是彈跳造成的離散 down 事件），沒有雜訊
/// 問題，用固定起點才能正確判定「這其實是一次滑動手勢，不是長按」。
///
/// **已進入拖曳階段後**（`_isActive == true`）收到的任何新 `down`，一律視為
/// 同一次手勢的延續、直接更新位置，不再套用位移門檻——拖曳階段本來就預期
/// 大幅移動，也避免在未通知 [onLongPressEnd]/[onLongPressCancel] 的情況下
/// 把使用中的按壓狀態靜默重置，導致下游 `_selectionDrag` 卡住殘留（規劃階段
/// 審查 Critical #2）。
///
/// **多指觸控防禦**：內部以 [_activePointers] 追蹤目前螢幕上有幾根手指。
/// 只要超過一指同時存在，立刻拒絕/取消目前追蹤中的按壓（不論是否已啟動長
/// 按），避免與 `PdfViewer` 的縮放/平移手勢衝突，也避免把第二指的觸碰誤判
/// 成新的長按起點；直到所有手指都放開才解除拒絕狀態（規劃階段審查
/// Critical #1）。
///
/// **幽靈觸發防禦**：長按判定時長的計時器觸發當下，若螢幕上剛好沒有任何
/// 手指（彈跳空隙、或使用者已經真正放開），**不會**立即啟動長按——真正放開
/// 太久會由 [_scheduleFinalizeCheck] 正確判定為取消；若只是短暫彈跳空隙、
/// 很快又按下，下一次 [_handleDown] 會在「累積時長其實已達標」時立即補上
/// 啟動，不會遺漏。這同時解決兩個問題：快速點兩下不會在背景幽靈觸發一次
/// 長按，介於 [mergeGapMs] 與 [longPressDurationMs] 之間的正常短按（例如
/// 300ms）也不會被誤判成長按（規劃階段審查 Critical #3）。
///
/// [onLongPressStart] 收到的座標固定為整串延續裡「最早那次 `down`」的
/// 位置，不會因雜訊本身的位置飄移而跳動。
class BounceTolerantLongPressDetector extends StatefulWidget {
  final Widget child;
  final void Function(Offset position) onLongPressStart;
  final void Function(Offset position) onLongPressMoveUpdate;
  final VoidCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;
  final int? longPressDurationMs;
  final int mergeGapMs;
  final double mergeSlop;

  const BounceTolerantLongPressDetector({
    super.key,
    required this.child,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
    this.longPressDurationMs,
    this.mergeGapMs = kTapZoneDebounceMs,
    this.mergeSlop = kTapZoneSlop,
  });

  @override
  State<BounceTolerantLongPressDetector> createState() =>
      _BounceTolerantLongPressDetectorState();
}

class _BounceTolerantLongPressDetectorState
    extends State<BounceTolerantLongPressDetector> {
  Offset? _anchorPosition;
  int? _anchorTimeMs;
  int? _lastActivityTimeMs;
  Offset? _lastKnownPosition;
  bool _isActive = false;
  Timer? _durationTimer;
  Timer? _finalizeTimer;

  // Critical #1（多指觸控防禦）：追蹤目前螢幕上有幾根手指，與「一次長按的
  // 邏輯狀態」（_anchorTimeMs 等）刻意分開管理，不因邏輯狀態被重置而跟著
  // 清空——必須忠實反映實體手指數量，才能正確判斷「是否所有手指都放開」。
  final Set<int> _activePointers = {};
  bool _isRejectedForMultiTouch = false;

  int _nowMs() => clock.now().millisecondsSinceEpoch;

  // Critical Finding 1（第二輪審查）：kLongPressTimeout.inMilliseconds 是
  // 執行期 getter、不是編譯期常數，不能直接當建構子可選參數的預設值（會是
  // const_eval_property_access 編譯錯誤，規劃階段已用 `dart analyze` 實測
  // 確認）。改成 widget.longPressDurationMs 宣告為 int?（預設 null），內部
  // 一律透過這個 getter 取得有效值。
  int get _effectiveDurationMs =>
      widget.longPressDurationMs ?? kLongPressTimeout.inMilliseconds;

  @override
  void dispose() {
    _durationTimer?.cancel();
    _finalizeTimer?.cancel();
    super.dispose();
  }

  void _resetState() {
    _anchorPosition = null;
    _anchorTimeMs = null;
    _lastActivityTimeMs = null;
    _lastKnownPosition = null;
    _isActive = false;
  }

  void _scheduleDurationTimer() {
    _durationTimer?.cancel();
    final observedAnchorTimeMs = _anchorTimeMs;
    _durationTimer =
        Timer(Duration(milliseconds: _effectiveDurationMs), () {
      if (!mounted) return;
      if (_anchorTimeMs != observedAnchorTimeMs) return;
      if (_isActive) return;
      if (_activePointers.isEmpty) {
        // Critical #3（幽靈觸發防禦）：手指目前剛好不在螢幕上（彈跳空隙或
        // 已經放開）。不要現在觸發——若使用者其實已放開太久，
        // _scheduleFinalizeCheck 會在稍後正確判定取消；若只是短暫彈跳
        // 空隙、馬上又按下，_handleDown 的存活時長檢查會立即補上啟動，
        // 不會漏掉。
        return;
      }
      _isActive = true;
      widget.onLongPressStart(_anchorPosition!);
      if (_lastKnownPosition != null &&
          _lastKnownPosition != _anchorPosition) {
        widget.onLongPressMoveUpdate(_lastKnownPosition!);
      }
    });
  }

  void _scheduleFinalizeCheck() {
    _finalizeTimer?.cancel();
    final observedAnchorTimeMs = _anchorTimeMs;
    final observedActivityTimeMs = _lastActivityTimeMs;
    _finalizeTimer = Timer(Duration(milliseconds: widget.mergeGapMs), () {
      if (!mounted) return;
      if (_anchorTimeMs != observedAnchorTimeMs) return;
      if (_lastActivityTimeMs != observedActivityTimeMs) return;
      _durationTimer?.cancel();
      final wasActive = _isActive;
      _resetState();
      if (wasActive) {
        widget.onLongPressEnd();
      } else {
        widget.onLongPressCancel();
      }
    });
  }

  void _rejectForMultiTouch() {
    _isRejectedForMultiTouch = true;
    _durationTimer?.cancel();
    _finalizeTimer?.cancel();
    final hadTracking = _anchorTimeMs != null;
    _resetState();
    if (hadTracking) widget.onLongPressCancel();
  }

  void _handleDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      // Critical #1：偵測到第二指，立刻拒絕，不論目前是否已啟動長按。
      _rejectForMultiTouch();
      return;
    }
    if (_isRejectedForMultiTouch) return; // 上一輪多指還沒完全放開，忽略。

    final now = _nowMs();

    if (_isActive) {
      // Critical #2：已在拖曳階段，任何後續 down（不論位移多大）都視為
      // 同一次手勢的延續，不套用位移門檻、也不會重置狀態。
      _finalizeTimer?.cancel();
      _finalizeTimer = null;
      _lastActivityTimeMs = now;
      _lastKnownPosition = event.localPosition;
      widget.onLongPressMoveUpdate(_lastKnownPosition!);
      return;
    }

    final isContinuation = _anchorTimeMs != null &&
        _lastActivityTimeMs != null &&
        _lastKnownPosition != null &&
        (now - _lastActivityTimeMs!) <= widget.mergeGapMs &&
        (_lastKnownPosition! - event.localPosition).distance <=
            widget.mergeSlop;
    if (isContinuation) {
      _finalizeTimer?.cancel();
      _finalizeTimer = null;
      _lastActivityTimeMs = now;
      _lastKnownPosition = event.localPosition;
      // Critical #3：彈跳空隙期間，若累積時長其實已經跨過門檻（因為
      // duration timer 觸發當下手指剛好不在螢幕上，被上方存活檢查擋
      // 下），這次重新按下就立即補上啟動，不必等下一個計時循環。
      if (now - _anchorTimeMs! >= _effectiveDurationMs) {
        _durationTimer?.cancel();
        _isActive = true;
        widget.onLongPressStart(_anchorPosition!);
        if (_lastKnownPosition != _anchorPosition) {
          widget.onLongPressMoveUpdate(_lastKnownPosition!);
        }
      }
    } else {
      _durationTimer?.cancel();
      _finalizeTimer?.cancel();
      if (_anchorTimeMs != null) {
        // Critical #2：前一次按壓尚未真正結束（pending 中）就被新的、不
        // 相關的按壓取代，須先通知這次 pending 嘗試已作廢，不能靜默丟棄。
        widget.onLongPressCancel();
      }
      _resetState();
      _anchorPosition = event.localPosition;
      _anchorTimeMs = now;
      _lastActivityTimeMs = now;
      _lastKnownPosition = event.localPosition;
      _scheduleDurationTimer();
    }
  }

  void _handleMove(PointerMoveEvent event) {
    if (_anchorTimeMs == null) return;
    if (!_isActive) {
      final distanceFromAnchor =
          (_anchorPosition! - event.localPosition).distance;
      if (distanceFromAnchor > widget.mergeSlop) {
        _durationTimer?.cancel();
        _finalizeTimer?.cancel();
        _resetState();
        widget.onLongPressCancel();
        return;
      }
    }
    _lastActivityTimeMs = _nowMs();
    _lastKnownPosition = event.localPosition;
    if (_isActive) {
      widget.onLongPressMoveUpdate(_lastKnownPosition!);
    }
  }

  void _handleUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) _isRejectedForMultiTouch = false;
    if (_anchorTimeMs == null) return;
    _lastActivityTimeMs = _nowMs();
    _scheduleFinalizeCheck();
  }

  void _handleCancel(PointerCancelEvent event) {
    // Important #1：系統手勢接管（例如邊緣滑動觸發系統返回）代表這根手指
    // 的整個手勢已被平台強制作廢，不可能有「彈跳延續」，不套用彈跳合併的
    // 寬限期，立即清除狀態。
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) _isRejectedForMultiTouch = false;
    if (_anchorTimeMs == null) return;
    _durationTimer?.cancel();
    _finalizeTimer?.cancel();
    _resetState();
    widget.onLongPressCancel();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: _handleCancel,
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4：執行測試確認全數通過**

Run: `cd app && flutter test test/reader/bounce_tolerant_long_press_detector_test.dart`
Expected: 8 項測試全數通過（含規劃階段審查後新增的多指觸控、幽靈觸發/短按誤判、系統取消三項）。

- [ ] **Step 5：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/bounce_tolerant_long_press_detector.dart app/test/reader/bounce_tolerant_long_press_detector_test.dart
git commit -m "feat(epic-25): Issue 5 新增 BounceTolerantLongPressDetector，具彈跳容忍度的長按偵測器"
```

---

### Task 2：`_buildSelectionGestureLayer()` 改用新元件，確認既有選取測試零回歸

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart:1136-1152`（`_buildSelectionGestureLayer()`）、檔案頂部 import 區
- Test: `app/test/reader/pdf_reader_view_selection_test.dart`（既有測試，不修改內容，僅執行驗證零回歸）

**Interfaces:**
- Consumes：Task 1 產出的 `BounceTolerantLongPressDetector` 建構子。
- Produces：無新增可供其他 Task 呼叫的函式，純替換底層手勢偵測機制，`_buildSelectionGestureLayer()` 對外行為（觸發 `_selectionDrag` 的建立/更新/結束時機與座標語意）不變。

- [ ] **Step 1：新增 import**

修改 `app/lib/reader/pdf_reader_view.dart`：在既有的 `import 'percent_rect.dart';` 與 `import 'tap_zone_detector.dart';` 之間，新增**這一行**：

```dart
import 'bounce_tolerant_long_press_detector.dart';
```

- [ ] **Step 2：`_buildSelectionGestureLayer()` 改用新元件**

修改 `app/lib/reader/pdf_reader_view.dart:1136-1174`，原本的（含 `epic-26-architecture-hardening` Issue 3 留下的暫時性真機診斷插樁 `[DEBUG-e26i3-selection]`，見該檔案該處註解）：

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

改為（**一併移除** `epic-26-architecture-hardening` Issue 3 的 `[DEBUG-e26i3-selection]` 暫時性診斷插樁——Issue 3 已於 2026-08-31 真機驗證結案，這段插樁本來就該在確認不再需要後清除，見該 Issue「2026-08-31 真機驗證結果」段落；`[DEBUG-e26i3]`（`TapZoneDetector` 內部）與 `[DEBUG-e26i3-zoneaction]`（`reader_screen.dart`）兩處插樁不受影響、本 Task 不觸碰）：

```dart
  Widget _buildSelectionGestureLayer(int pageIndex, Rect pageRectInViewer) {
    return Positioned.fill(
      child: BounceTolerantLongPressDetector(
        onLongPressStart: (position) {
          if (widget.cropEditModeActive) return;
          _selectionDragGenerationId++;
          setState(() {
            _selectionDrag = _PdfSelectionDragState(
              pageIndex: pageIndex,
              areaSize: pageRectInViewer.size,
              pageOffsetInViewer: pageRectInViewer.topLeft,
              start: position,
            );
          });
        },
        onLongPressMoveUpdate: (position) {
          final drag = _selectionDrag;
          if (drag == null || drag.pageIndex != pageIndex) return;
          setState(() => drag.current = position);
        },
        onLongPressEnd: () => _finishSelectionDrag(),
        onLongPressCancel: () => _cancelSelectionDrag(),
      ),
    );
  }
```

`_selectionDrag`／`_selectionDragGenerationId`／`_finishSelectionDrag()`／`_cancelSelectionDrag()`／`panEnabled: _selectionDrag == null`／`scaleEnabled: _selectionDrag == null` 皆完全不變動——本步驟只替換手勢偵測機制本身（含順帶清除 Issue 3 已完成的診斷插樁），選取狀態管理邏輯原封不動。

- [ ] **Step 3：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4：執行既有選取測試套件，確認零回歸**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 全數通過。既有測試（例如「長按拖曳後放開，觸發 `onSelectionRectComputed`」）用 `tester.pump(kLongPressTimeout + const Duration(milliseconds: 50))`（`kLongPressTimeout`＝500ms）等待長按判定成立，`BounceTolerantLongPressDetector` 未傳 `longPressDurationMs`（維持 `null`）時，`_effectiveDurationMs` 同樣解析為 500ms，時序語意一致，不需修改既有測試斷言。

Run: `cd app && flutter test test/reader/pdf_reader_view_nav_zone_test.dart`
Expected: 全數通過（確認熱區點擊行為不受選取層替換影響——兩者是平行的獨立 `Listener`，互不干擾）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart
git commit -m "refactor(epic-25): Issue 5 _buildSelectionGestureLayer 改用 BounceTolerantLongPressDetector"
```

---

### Task 3：新增真實裝置 2 彈跳資料端對端回歸測試（透過完整 `PdfReaderView` 重現症狀已修復）

**Files:**
- Modify: `app/test/reader/pdf_reader_view_selection_test.dart`（新增一項測試）

**Interfaces:**
- Consumes：Task 2 完成後的 `PdfReaderView`／`_buildSelectionGestureLayer()`。
- Produces：無新增函式，純新增一項端對端回歸測試。

- [ ] **Step 1：寫測試——重現裝置 2 真實彈跳序列，透過完整 `PdfReaderView` 驗證選取仍能完成**

在 `app/test/reader/pdf_reader_view_selection_test.dart` 的「長按拖曳後放開，觸發 `onSelectionRectComputed`」測試（第 47-84 行）之後，新增：

```dart
  testWidgets(
      '重現真機彈跳雜訊（tmp/epic-25/log-issue5/device-2.txt 前 21 行）'
      '仍能觸發 onSelectionRectComputed（Epic 25 Issue 5 回歸測試——'
      '修復前，同樣的彈跳序列會讓 GestureDetector 的內建長按計時器不斷'
      '被新的 down 打斷，onLongPressStart 永遠不會觸發，選取完全無法啟動）',
      (tester) async {
    var renderedCount = 0;
    PdfSelectionInfo? computed;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => computed = info,
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final pageFinder = find.byType(PdfReaderView);
    final topLeft = tester.getTopLeft(pageFinder);
    // 真實裝置 2 彈跳序列的相對位移量（毫米級微幅飄移，非憑空編造，
    // 換算自 device-2.txt 前 21 行的實際座標差值），疊加在頁面上一個
    // 固定基準點之上。
    Offset at(double dx, double dy) => topLeft + Offset(60 + dx, 80 + dy);

    final downTimes = [0, 69, 183, 196, 253, 257, 313, 399, 413];
    final downOffsets = [
      const Offset(0, 0),
      const Offset(0, 0),
      const Offset(-1.4, 2.0),
      const Offset(-1.4, 2.0),
      const Offset(-1.0, 2.0),
      const Offset(2.5, 5.4),
      const Offset(3.5, 5.9),
      const Offset(11.8, 13.8),
      const Offset(11.8, 13.8),
    ];
    final upTimes = [49, 134, 190, 251, 255, 302, 322, 409, 538];

    var lastEventTime = 0;
    for (var i = 0; i < downTimes.length; i++) {
      await tester.pump(Duration(milliseconds: downTimes[i] - lastEventTime));
      final gesture = await tester.startGesture(at(
        downOffsets[i].dx,
        downOffsets[i].dy,
      ));
      lastEventTime = downTimes[i];
      await tester.pump(Duration(milliseconds: upTimes[i] - lastEventTime));
      await gesture.up();
      lastEventTime = upTimes[i];
    }

    // 明顯的拖曳，確保不是退化選取。
    final finalGesture = await tester.startGesture(at(11.8, 13.8));
    await tester.pump(const Duration(milliseconds: 40));
    await finalGesture.moveTo(at(160, 160));
    await tester.pump();
    await finalGesture.up();
    await pumpUntilPdfReady(tester, condition: () => computed != null);

    expect(computed, isNotNull,
        reason: '修復前這段彈跳序列會讓長按永遠無法啟動，selection 回呼'
            '永遠不會觸發；修復後應正確判定為一次連續長按並完成選取');
  });
```

- [ ] **Step 2：執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 全數通過，含本次新增的回歸測試。

- [ ] **Step 3：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4：Commit**

```bash
git add app/test/reader/pdf_reader_view_selection_test.dart
git commit -m "test(epic-25): Issue 5 新增真機彈跳資料端對端回歸測試"
```

---

### Task 4：全套測試最終確認、更新 `issues.md`

**Files:**
- Modify: `docs/epics/epic-25-annotation-interaction-qa/issues.md`（Issue 5 區塊）

**Interfaces:**
- Consumes：Task 1-3 的實作與測試結果。
- Produces：無程式介面——文件更新。

- [ ] **Step 1：全套 `flutter test`／`flutter analyze` 最終確認**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數通過，零回歸。

- [ ] **Step 2：更新 `issues.md` Issue 5 狀態**

修改 `docs/epics/epic-25-annotation-interaction-qa/issues.md` 的「## Issue 5」區塊，將 `**Status:**` 那一行改為：

```markdown
**Status:** ✅ 已實作並通過自動化測試（比照 `plan-issue-5.md`）。新增 `BounceTolerantLongPressDetector`（`app/lib/reader/bounce_tolerant_long_press_detector.dart`）取代 `_buildSelectionGestureLayer()` 原本的 `GestureDetector`／`LongPressGestureRecognizer`，用真機校準過的既有常數（`kTapZoneDebounceMs`＝350ms、`kTapZoneSlop`＝18px）合併判定彈跳雜訊。用裝置 2 真實彈跳資料（`tmp/epic-25/log-issue5/device-2.txt`）重播的單元測試與端對端測試皆通過，證實修復前 0 次成功啟動的彈跳序列，修復後能正確判定為一次連續長按並完成選取。**待人類真機直接試用回報**（依 Issue 5 敲定的驗證方式，刻意不另排正式插樁診斷這一輪，見「Solution」段落）。
```

- [ ] **Step 3：Commit**

```bash
git add docs/epics/epic-25-annotation-interaction-qa/issues.md
git commit -m "docs(epic-25): Issue 5 更新為已實作狀態，待真機試用回報"
```

---

## Self-Review

- **Spec 覆蓋度**：Issue 5「Solution」段落逐項核對——彈跳合併判定（時間/位置雙門檻、沿用既有常數）→ Task 1；長按判定時長與注入方式 → Task 1；選取起點固定於最早 down → Task 1（測試 1）／Task 2（座標語意保留）；拖曳中途保護 → Task 1（測試 5）；`_selectionDragGenerationId` 語意不變 → Task 2（完全不改動這段程式碼）；驗證方式（真實資料自動化測試、不另排真機插樁）→ Task 1／Task 3。
- **Placeholder 掃描**：三個 Task 的元件程式碼、測試程式碼皆為完整可執行內容，測試中使用的真實彈跳資料（時間/座標）皆已用腳本從 `tmp/epic-25/log-issue5/device-2.txt` 精確核對過（見 Task 1 Step 1 程式碼內的行內對照表），非憑空編造數字。
- **型別/介面一致性**：`BounceTolerantLongPressDetector` 建構參數簽章在 Task 1（定義）、Task 2（`pdf_reader_view.dart` 呼叫端）、Task 1 測試（`wrap()` helper）三處完全一致；回呼型別從舊版 `LongPressStartDetails`/`LongPressMoveUpdateDetails` 改為直接傳 `Offset`，Task 2 的替換程式碼已同步把 `details.localPosition` 改為直接使用 `position` 參數。
- **座標系正確性（規劃階段特別核對的風險點）**：新元件內部一律使用 `PointerEvent.localPosition`（相對於 `_buildSelectionGestureLayer` 的 `Positioned.fill`），不是 `.position`（全域座標）——與舊版 `GestureDetector` 的 `details.localPosition` 語意一致，確保 `_finishSelectionDrag()` 下游的 `percentRectFromDrag()` 座標假設不被打破。
- **既有測試不回歸的具體論證**：Task 2 只替換手勢偵測機制本身，`_selectionDrag`／`_selectionDragGenerationId`／`_finishSelectionDrag()`／`_cancelSelectionDrag()`／`panEnabled`／`scaleEnabled` 邏輯完全不動；新元件 `longPressDurationMs` 未傳（維持 `null`）時，`_effectiveDurationMs` 解析為 `kLongPressTimeout.inMilliseconds`（等同 500ms），既有測試的等待時序不需調整。Task 2 Step 4 執行既有 `pdf_reader_view_selection_test.dart`／`pdf_reader_view_nav_zone_test.dart` 全數驗證零回歸。
- **範圍誠實聲明**：本計畫刻意不包含真機插樁診斷（Issue 5 已敲定改用真實資料驅動的自動化測試取代）；真機最終確認留給人類在實作完成後直接試用回報，若仍有殘留問題，屆時再依 Issue 3 的插樁診斷模式另開一輪。
- **依 `reviews/review-plan-issue-5.md` 第一輪審查意見修訂**：Critical #1（多指觸控防禦，新增 `_activePointers`／`_isRejectedForMultiTouch`）、Critical #2（已在拖曳階段時任何新 `down` 一律視為延續，避免未通知回呼就靜默重置狀態）、Critical #3（幽靈觸發/短按誤判防禦，`_scheduleDurationTimer` 觸發時檢查 `_activePointers.isEmpty`、`_handleDown` 延續分支補上「累積時長已達標則立即補上啟動」）、Important #1（`PointerCancelEvent` 拆成獨立 `_handleCancel`、立即清除不等待寬限期）、Important #2（新增 3 項測試：雙指觸控拒絕、幽靈觸發/短按誤判、系統取消立即生效）、Minor #1（`longPressDurationMs` 預設值改用 `kLongPressTimeout`）、Minor #2（Task 2 明確註記一併移除 Issue 3 的 `[DEBUG-e26i3-selection]` 插樁）皆已採納並反映於本計畫最終版本；三項 Critical 的修訂邏輯皆已用真實裝置 2 彈跳序列與新增測試案例逐行手動推演過，確認彼此不衝突（見 Task 1 Step 1 各測試案例的追蹤過程）。
- **依 `reviews/review-plan-issue-5.md` 第二輪審查意見修訂**：Critical Finding 1（`kLongPressTimeout.inMilliseconds` 不是編譯期常數，不能當 `const` 建構子可選參數預設值）——規劃階段已用 `dart analyze` 在真實專案環境實測驗證這個編譯錯誤確實存在，改為 `longPressDurationMs` 宣告成 `int?`（預設 `null`）、State 內部新增 `_effectiveDurationMs` getter 解析有效值，同一份 `dart analyze` 也驗證了這個修法本身能乾淨編譯過關；Important Finding 2（拖曳結束後 350ms 寬限期內的遠距新觸碰會被吞成延續）採納審查者自己「非 Blocker」的判定，記錄為已知、經審查確認可接受的邊界情況（見 Global Constraints），不在本計畫內加防禦；Minor Finding 3 為驗證性意見，無需修改。
