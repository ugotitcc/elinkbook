# Epic 26 Issue 4：收斂「等待 PDF 就緒」成一個共用測試 adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把散落在 9 個測試檔案、共 104 個編輯點的「等待 pdfrx 完成非同步開書」輪詢邏輯，收斂成一個共用測試 adapter `pumpUntilPdfReady()`，行為完全不變（純重構，零功能回歸）。

**Architecture:** 新增 `app/test/support/pump_until_pdf_ready.dart`，簽章涵蓋現行 3 種變形（無條件跑滿 N 輪／帶提前跳出條件／不同的 pump 間隔）。9 個測試檔案的呼叫點與 local helper 定義全部改用這個共用函式，不改變任何測試的斷言或行為。

**Tech Stack:** Flutter test（`flutter_test`）、`tester.runAsync`（bridge 到真實 async I/O，pdfrx 開書為真實非同步流程）。

**Spec:** `docs/epics/epic-26-architecture-hardening/issues.md`（「Issue 4」，含逐檔案精確統計與根因分析）。

## Global Constraints

- 純測試重構，**不得**修改任何生產程式碼（`app/lib/` 底下不動）。
- 每個檔案遷移後，該檔案的測試案例數量、斷言內容、通過/失敗結果須與遷移前完全一致（零回歸）——這是本計畫唯一的正確性判準。
- 條件式呼叫端的介面轉換方向：舊制「`int Function() rendered`，`rendered() == 0` 時繼續等待」→ 新制「`bool Function()? condition`，`condition()` 為 `true` 時停止等待」，即 `condition: () => rendered() != 0`（或直接用具名變數 `() => renderedCount != 0`）。方向寫反會讓測試變成「完全不等待」或「每次都跑滿 `maxIterations`」，兩者都可能導致該測試變 flaky 或變慢但不一定會立即failed，**必須靠「零回歸」規則跑一遍該檔案全部測試來驗證**，不能只看單一測試。
- 遇到用本計畫指定的 old_string 做 `replace_all` 卻找不到完全匹配（多半是空白字元與本計畫轉錄時不完全一致）時，改用 Grep 在該檔案內定位每一處精確位置，逐一以該處實際文字為 old_string 個別編輯，不得略過。
- 每完成一個 Task 就跑一次該檔案（或該組檔案）的 `flutter test`，全數通過才進下一個 Task。全部 Task 完成後跑一次 `flutter analyze` 確認乾淨。

---

### Task 1：建立共用 adapter `pumpUntilPdfReady()`

**Files:**
- Create: `app/test/support/pump_until_pdf_ready.dart`
- Create: `app/test/support/pump_until_pdf_ready_test.dart`

**Interfaces:**
- Produces: `Future<void> pumpUntilPdfReady(WidgetTester tester, {bool Function()? condition, int maxIterations = 30, Duration delayBetweenPumps = const Duration(milliseconds: 10)})`——Task 2-5 的所有呼叫端皆消費此函式。

- [ ] **Step 1: 寫失敗測試——基本行為**

建立 `app/test/support/pump_until_pdf_ready_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'pump_until_pdf_ready.dart';

void main() {
  testWidgets('condition 省略時（null），確實跑滿 maxIterations 輪（以真實耗時下限驗證，'
      '而非只驗證「不拋例外」——避免 null 分支被誤判為提前終止卻測不出來）',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    final stopwatch = Stopwatch()..start();
    await pumpUntilPdfReady(
      tester,
      maxIterations: 3,
      delayBetweenPumps: const Duration(milliseconds: 20),
    );
    stopwatch.stop();

    // delayBetweenPumps 是跳出 fake zone（runAsync）後的真實
    // Future.delayed，3 輪至少累積 3*20=60ms 真實耗時；用「至少」而非
    // 精確比對，避免測試環境時序 jitter 造成 flaky。若 condition==null
    // 分支被誤寫成提前跳出（例如迴圈只跑 1 輪就停），耗時會遠低於
    // 60ms，這則測試就會抓到。
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(60),
        reason: 'condition 為 null 時應無條件跑滿 3 輪，每輪至少 20ms 真實延遲，'
            '總耗時應 >= 60ms；耗時遠低於此代表迴圈未跑滿或 null 分支邏輯有誤');
  });

  testWidgets('condition 提前滿足時，提前跳出、不跑滿 maxIterations', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    var callCount = 0;

    await pumpUntilPdfReady(
      tester,
      condition: () {
        callCount++;
        return callCount >= 2; // 第 2 次呼叫就回傳 true，應提前跳出
      },
      maxIterations: 100,
      delayBetweenPumps: Duration.zero,
    );

    expect(callCount, 2, reason: 'condition 在第 2 次呼叫回傳 true，迴圈應立即停止，'
        '不應繼續呼叫到第 3 次（若繼續呼叫代表提前跳出邏輯有誤）');
  });

  testWidgets('maxIterations 上限確實生效（condition 永遠不滿足時）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    var callCount = 0;

    await pumpUntilPdfReady(
      tester,
      condition: () {
        callCount++;
        return false; // 永遠不滿足
      },
      maxIterations: 3,
      delayBetweenPumps: Duration.zero,
    );

    expect(callCount, 3, reason: 'condition 永遠回傳 false 時，迴圈應恰好跑滿 '
        'maxIterations=3 輪後停止，不多不少');
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/support/pump_until_pdf_ready_test.dart`
預期：編譯錯誤（`pumpUntilPdfReady` 函式不存在，找不到同目錄的 `pump_until_pdf_ready.dart`）。

- [ ] **Step 3: 實作 `pumpUntilPdfReady()`**

建立 `app/test/support/pump_until_pdf_ready.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 等待 pdfrx（或其他真實非同步渲染流程）在 widget test 環境下完成初次
/// 渲染的共用測試 adapter（epic-26-architecture-hardening Issue 4，收斂
/// 原本散落在 9 個測試檔案、104 個編輯點的重複輪詢迴圈）。
///
/// [condition] 為 `null`（省略）時無條件跑滿 [maxIterations] 輪；提供時，
/// 每輪 pump 之後檢查一次，回傳 `true` 即提前停止等待。[maxIterations] 與
/// [delayBetweenPumps] 皆可覆寫，涵蓋既有程式碼中出現過的 10／30／40 輪與
/// 10ms／50ms 間隔等變形。
///
/// 兩種時間職責不同、不可混淆：`tester.pump(Duration(milliseconds: 100))`
/// 是固定的 fake-clock 虛擬推進量（framework 動畫/計時器邏輯用），寫死不
/// 開放調整；[delayBetweenPumps] 則是 `runAsync` 跳出 fake zone 之後、
/// 真實 `Future.delayed`，用來讓底層真正的非同步 I/O／Isolate 運算（例如
/// pdfrx 解碼、影像濾鏡背景運算）有機會推進，兩者分屬不同時鐘、不可互相
/// 替代。
Future<void> pumpUntilPdfReady(
  WidgetTester tester, {
  bool Function()? condition,
  int maxIterations = 30,
  Duration delayBetweenPumps = const Duration(milliseconds: 10),
}) {
  return tester.runAsync(() async {
    for (var i = 0;
        i < maxIterations && (condition == null || !condition());
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(delayBetweenPumps);
    }
  });
}
```

- [ ] **Step 4: 執行測試確認全數通過**

執行：`cd app && flutter test test/support/pump_until_pdf_ready_test.dart`
預期：全數 PASS。

- [ ] **Step 5: Commit**

```bash
git add app/test/support/pump_until_pdf_ready.dart app/test/support/pump_until_pdf_ready_test.dart
git commit -m "test(epic-26): Issue 4 Task 1——新增共用 pumpUntilPdfReady() adapter"
```

---

### Task 2：遷移 `pdf_reader_view_test.dart`（5 處，2 種條件）

**Files:**
- Modify: `app/test/reader/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes: `pumpUntilPdfReady()`（Task 1 產出）。

**背景**：本檔案 5 處皆無 local helper、直接內嵌 `await tester.runAsync(() async { for (...) {...} });`，2 種條件：

- 形狀 A（3 處，第 29/55/122 行）：`renderedCount == 0 && errorMessage == null`
- 形狀 B（2 處，第 83/169 行）：`renderedCount == 0`

- [ ] **Step 1: 新增 import**

編輯 `app/test/reader/pdf_reader_view_test.dart`，於檔案最上方既有 import 區塊最後一行之後新增：

```dart
import '../support/pump_until_pdf_ready.dart';
```

- [ ] **Step 2: 用 `replace_all` 取代形狀 A（3 處）**

用 Edit 工具，`replace_all: true`，把下列文字（3 處逐字相同）：

```dart
    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0 && errorMessage == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
```

取代為：

```dart
    await pumpUntilPdfReady(
      tester,
      condition: () => renderedCount != 0 || errorMessage != null,
    );
```

若 `replace_all` 因空白字元轉錄落差找不到完全匹配，改用 Grep 在檔案內搜尋 `renderedCount == 0 && errorMessage == null` 定位 3 處確切行號，逐一個別編輯（比照 Global Constraints 的規定）。

- [ ] **Step 3: 用 `replace_all` 取代形狀 B（2 處）**

把下列文字（2 處逐字相同）：

```dart
    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
```

取代為：

```dart
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
```

（同樣：若找不到完全匹配，改用 Grep 逐一定位個別編輯。）

- [ ] **Step 4: 執行測試確認全數通過、零回歸**

執行：`cd app && flutter test test/reader/pdf_reader_view_test.dart`
預期：全數 PASS（案例數與遷移前相同）。

- [ ] **Step 5: Commit**

```bash
git add app/test/reader/pdf_reader_view_test.dart
git commit -m "test(epic-26): Issue 4 Task 2——pdf_reader_view_test.dart 改用 pumpUntilPdfReady"
```

---

### Task 3：遷移 `reader_screen_test.dart`（20 處，3 種形狀）

**Files:**
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: `pumpUntilPdfReady()`（Task 1 產出）。

**背景**：本檔案 20 處皆無 local helper、直接內嵌，3 種形狀：

- 形狀 A（1 處，第 2716 行）：帶條件 `renderedCount == 0`，`maxIterations=30`。
- 形狀 B（16 處，第 2776/5510/5558/5629/5844/5915/5965/6016/6069/6104/6147/6180/6232/6314/6363/6406 行）：無條件，`maxIterations=30`。**縮排不完全一致**——多數（14 處）為 `for` 前 6 個空白（`await tester.runAsync` 前 4 個空白），僅第 5510／5558 行這 2 處為巢狀較深的區塊、`for` 前 8 個空白（`await tester.runAsync` 前 6 個空白）。
- 形狀 C（3 處，第 6202/6252/6334 行）：無條件，`maxIterations=10`，縮排與形狀 B 的 6 空白變體相同。

- [ ] **Step 1: 新增 import**

編輯 `app/test/screens/reader_screen_test.dart`，於既有 import 區塊最後新增：

```dart
import '../support/pump_until_pdf_ready.dart';
```

- [ ] **Step 2: 個別編輯形狀 A（第 2716 行附近，唯一一處，不需 replace_all）**

把：

```dart
    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
```

取代為：

```dart
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
```

- [ ] **Step 3: 用 `replace_all` 取代形狀 B 的 6 空白縮排變體（14 處）**

把：

```dart
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
```

取代為：

```dart
      await pumpUntilPdfReady(tester);
```

（`for` 前 6 空白、`await tester.runAsync` 前 4 空白這個縮排層級對應的完整區塊，含左側縮排請依實際檔案內容為準；若 `replace_all` 找不到完全匹配，改用 Grep 搜尋 `for (var i = 0; i < 30; i++) {` 逐一核對每處縮排後個別編輯。）

- [ ] **Step 4: 個別處理形狀 B 的 8 空白縮排變體（第 5510、5558 行，2 處）**

這 2 處巢狀較深，`replace_all` 不會匹配 Step 3 的縮排版本。用 Grep 定位這 2 處確切位置，各自把該處的：

```dart
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
```

（含外層 `await tester.runAsync(() async { ... });` 包裹）取代為：

```dart
        await pumpUntilPdfReady(tester);
```

- [ ] **Step 5: 用 `replace_all` 取代形狀 C（3 處，`maxIterations=10`）**

把：

```dart
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
```

取代為：

```dart
    await pumpUntilPdfReady(tester, maxIterations: 10);
```

- [ ] **Step 6: 執行測試確認全數通過、零回歸**

執行：`cd app && flutter test test/screens/reader_screen_test.dart`
預期：全數 PASS（案例數與遷移前相同，這是本檔案最大宗的遷移，務必完整跑一次全檔案）。

- [ ] **Step 7: Commit**

```bash
git add app/test/screens/reader_screen_test.dart
git commit -m "test(epic-26): Issue 4 Task 3——reader_screen_test.dart 改用 pumpUntilPdfReady"
```

---

### Task 4：遷移 6 個「單一 local `waitRendered`」檔案

**Files:**
- Modify: `app/test/reader/pdf_reader_view_dual_page_test.dart`（1 定義＋16 呼叫）
- Modify: `app/test/reader/pdf_reader_view_selection_test.dart`（1 定義＋14 呼叫）
- Modify: `app/test/reader/pdf_reader_view_search_test.dart`（1 定義＋6 呼叫）
- Modify: `app/test/reader/pdf_reader_view_nav_zone_test.dart`（1 定義＋6 呼叫）
- Modify: `app/test/reader/pdf_reader_view_thumbnail_test.dart`（1 定義＋3 呼叫）
- Modify: `app/test/reader/pdf_reader_view_toc_test.dart`（1 定義＋2 呼叫）

**Interfaces:**
- Consumes: `pumpUntilPdfReady()`（Task 1 產出）。

**背景（已用 `grep` 逐檔案核對確認）**：這 6 個檔案的 local `waitRendered` 定義**逐位元組相同**：

```dart
  Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
    return tester.runAsync(() async {
      for (var i = 0; i < 30 && rendered() == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }
```

呼叫端也逐字相同：`await waitRendered(tester, () => renderedCount);`（已核對 6 個檔案全部呼叫點文字一致，無變體）。以下同一組步驟對 6 個檔案逐一套用：

- [ ] **Step 1: （對 6 個檔案逐一執行）新增 import**

於每個檔案最上方既有 import 區塊最後新增：

```dart
import '../support/pump_until_pdf_ready.dart';
```

- [ ] **Step 2: （對 6 個檔案逐一執行）刪除 local `waitRendered` 定義**

用 Edit 工具，把上方「背景」列出的 `Future<void> waitRendered(...) { ... }` 整段函式定義（含前後空行視檔案排版調整）從檔案中刪除。

- [ ] **Step 3: （對 6 個檔案逐一執行）用 `replace_all` 取代全部呼叫點**

把：

```dart
    await waitRendered(tester, () => renderedCount);
```

取代為：

```dart
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
```

（注意部分呼叫點縮排可能是 4 或 6 個空白，視巢狀深度而定——若單一 `replace_all` 因縮排不同找不到全部匹配，針對每種縮排各自跑一次 `replace_all`，或改用 Grep 逐一定位。）

- [ ] **Step 4: 用 Grep 驗證 `waitRendered` 已 100% 清除**

執行：`grep -rn "waitRendered" app/test/reader/pdf_reader_view_dual_page_test.dart app/test/reader/pdf_reader_view_selection_test.dart app/test/reader/pdf_reader_view_search_test.dart app/test/reader/pdf_reader_view_nav_zone_test.dart app/test/reader/pdf_reader_view_thumbnail_test.dart app/test/reader/pdf_reader_view_toc_test.dart`
預期：無任何結果——若有殘留（定義未刪乾淨，或某處呼叫點縮排不同未被 `replace_all` 命中），先處理乾淨再進下一步，避免帶著遺漏進入測試階段才發現。

- [ ] **Step 5: 執行測試確認全數通過、零回歸（每個檔案跑一次）**

依序執行：

```bash
cd app
flutter test test/reader/pdf_reader_view_dual_page_test.dart
flutter test test/reader/pdf_reader_view_selection_test.dart
flutter test test/reader/pdf_reader_view_search_test.dart
flutter test test/reader/pdf_reader_view_nav_zone_test.dart
flutter test test/reader/pdf_reader_view_thumbnail_test.dart
flutter test test/reader/pdf_reader_view_toc_test.dart
```

預期：全數 PASS（各檔案案例數與遷移前相同）。

- [ ] **Step 6: Commit**

```bash
git add app/test/reader/pdf_reader_view_dual_page_test.dart app/test/reader/pdf_reader_view_selection_test.dart app/test/reader/pdf_reader_view_search_test.dart app/test/reader/pdf_reader_view_nav_zone_test.dart app/test/reader/pdf_reader_view_thumbnail_test.dart app/test/reader/pdf_reader_view_toc_test.dart
git commit -m "test(epic-26): Issue 4 Task 4——6 個檔案移除重複 local waitRendered，改用 pumpUntilPdfReady"
```

---

### Task 5：遷移 `pdf_reader_view_filters_test.dart`（26 處：6 定義＋16 呼叫＋4 獨立變體）

**Files:**
- Modify: `app/test/reader/pdf_reader_view_filters_test.dart`

**Interfaces:**
- Consumes: `pumpUntilPdfReady()`（Task 1 產出）。

**背景**：本檔案內 6 個 `group` 各自重新定義一次與 Task 4 完全相同的 `waitRendered`（第 19/117/221/317/384/456 行），呼叫端 16 處皆為 `await waitRendered(tester, () => renderedCount);`；另有 4 處不經 `waitRendered`、獨立內嵌的迴圈，條件互異且 `delayBetweenPumps` 為 50ms（其餘 8 個檔案皆為 10ms）：

- 第 165 行：`find.byType(RawImage).evaluate().isEmpty`，`maxIterations=30`
- 第 199 行：`find.byType(RawImage).evaluate().length < 2`，`maxIterations=40`
- 第 250 行：`computedRect == null`，`maxIterations=30`
- 第 367 行：`find.byType(RawImage).evaluate().isEmpty`（與第 165 行同形狀），`maxIterations=30`

- [ ] **Step 1: 新增 import**

於檔案最上方既有 import 區塊最後新增：

```dart
import '../support/pump_until_pdf_ready.dart';
```

- [ ] **Step 2: 刪除 6 份重複的 local `waitRendered` 定義**

用 Edit 工具，把 Task 4「背景」列出的同一份 `Future<void> waitRendered(...) { ... }` 函式定義，在本檔案內 6 個出現處（第 19/117/221/317/384/456 行附近，各自在不同 `group` 內）逐一刪除（無法用單一 `replace_all` 一次刪光，因為函式定義文字雖然相同、但刪除操作需要確保不誤刪呼叫點，建議逐一用 Grep 定位每個 `Future<void> waitRendered` 出現行號後個別刪除該整段函式）。

- [ ] **Step 3: 用 `replace_all` 取代 16 處呼叫點**

把：

```dart
      await waitRendered(tester, () => renderedCount);
```

取代為：

```dart
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
```

（16 處呼叫點皆為相同縮排，已核對過。）

- [ ] **Step 4: 個別處理第 165 行的獨立變體**

用 Grep 定位「`find.byType(RawImage).evaluate().isEmpty`」在檔案中的第一個出現處，把該處的：

```dart
      await tester.runAsync(() async {
        for (var i = 0; i < 30 && find.byType(RawImage).evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
```

取代為：

```dart
      await pumpUntilPdfReady(
        tester,
        condition: () => find.byType(RawImage).evaluate().isNotEmpty,
        delayBetweenPumps: const Duration(milliseconds: 50),
      );
```

- [ ] **Step 5: 個別處理第 199 行的獨立變體（`maxIterations=40`）**

把：

```dart
      await tester.runAsync(() async {
        for (var i = 0; i < 40 && find.byType(RawImage).evaluate().length < 2; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
```

取代為：

```dart
      await pumpUntilPdfReady(
        tester,
        condition: () => find.byType(RawImage).evaluate().length >= 2,
        maxIterations: 40,
        delayBetweenPumps: const Duration(milliseconds: 50),
      );
```

- [ ] **Step 6: 個別處理第 250 行的獨立變體（`computedRect`）**

把：

```dart
      await tester.runAsync(() async {
        for (var i = 0; i < 30 && computedRect == null; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
```

取代為：

```dart
      await pumpUntilPdfReady(
        tester,
        condition: () => computedRect != null,
        delayBetweenPumps: const Duration(milliseconds: 50),
      );
```

- [ ] **Step 7: 個別處理第 367 行的獨立變體（與 Step 4 同形狀，第二個出現處）**

用 Grep 定位「`find.byType(RawImage).evaluate().isEmpty`」在檔案中剩餘的出現處（Step 4 已處理第一處），比照 Step 4 的替換內容處理這一處。

- [ ] **Step 8: 用 Grep 驗證 `waitRendered` 已 100% 清除**

執行：`grep -n "waitRendered" app/test/reader/pdf_reader_view_filters_test.dart`
預期：無任何結果——若有殘留，先處理乾淨再進下一步。

- [ ] **Step 9: 執行測試確認全數通過、零回歸**

執行：`cd app && flutter test test/reader/pdf_reader_view_filters_test.dart`
預期：全數 PASS（案例數與遷移前相同，這是本檔案唯一一個混合多種變形的檔案，務必仔細核對）。

- [ ] **Step 10: Commit**

```bash
git add app/test/reader/pdf_reader_view_filters_test.dart
git commit -m "test(epic-26): Issue 4 Task 5——pdf_reader_view_filters_test.dart 改用 pumpUntilPdfReady"
```

---

## 完成後的驗證（對照 `issues.md` Issue 4 驗收標準）

- [ ] `flutter analyze`：全專案 "No issues found!"
- [ ] `flutter test`：全專案通過，零回歸（案例總數與 Task 1 開始前的基準一致）
- [ ] `git diff --stat app/lib/`：應無任何輸出——本 Issue 純測試重構，任何 `app/lib/` 底下的異動都代表誤觸生產程式碼，須立即檢視。
- [ ] `grep -rn "waitRendered" app/test/`：應無任何結果（12 份重複定義與所有呼叫點皆已移除）
- [ ] `grep -rn "for (var i = 0; i < .* && rendered" app/test/`／類似模式：應無殘留的舊式內嵌輪詢迴圈
