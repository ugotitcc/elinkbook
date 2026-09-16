# Epic 43 Issue 4 — FoliateBridgeHandlers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 收斂 JS→Dart `callHandler()` 的 11 個相異 handler name 字串常值（目前在 `foliate_reader_view.dart`／`search/foliate_content_indexer.dart` 兩個檔案內以字面值手打兩次以上）成單一常數集合 `FoliateBridgeHandlers`，消除「任一處打錯字，型別系統攔不到、只會執行期靜默逾時」的風險。

**Architecture:** 新增 `app/lib/reader/foliate_bridge_handlers.dart`，內含一個 `abstract final class FoliateBridgeHandlers`，以 11 個 `static const String` 收斂所有 handler name。`foliate_reader_view.dart`／`search/foliate_content_indexer.dart` 內所有 `handlerName: '...'` 字面值改為 `handlerName: FoliateBridgeHandlers.xxx`——純替換，不改變任何呼叫邏輯、時序、fallback 值。`main.js` 端呼叫 `callHandler('...')` 的字串本身（vendor 釘定檔案）不受影響、不改動。

**Tech Stack:** Flutter/Dart 3.11，`flutter_test`。

**Spec:** `docs/epics/epic-43-reader-architecture-hardening/issues.md` Issue 4（`/grilling` Q1 已縮小範圍定案；I-1 審查修訂補上原稿遺漏的 3 個 handler；M-4 審查修訂要求常數值本身要有測試覆蓋）。

## Global Constraints

- 所有指令在 `app/` 目錄下執行（**含 `git add`／`git commit`**——I-1 審查修訂：各 Task 的 Commit 步驟路徑一律寫成相對 `app/` 的路徑，例如 `git add lib/reader/xxx.dart`，不要再加一層 `app/` 前綴，否則在 cwd 已是 `app/` 時會解析成不存在的 `app/app/lib/...` 而以 `fatal: pathspec` 失敗）。
- 只替換 **JS→Dart** 方向的 handler name 字面值（`JsBridgeGateway.register(handlerName: ...)`／`.request(handlerName: ...)`／`controller.addJavaScriptHandler(handlerName: ...)` 這三種呼叫點的字串字面值參數）。**不要**觸碰以下兩類，它們不在本 Issue 範圍：
  - `foliate_reader_view.dart:609`／`search/foliate_content_indexer.dart:102` 的 `registerHandler: (name, callback) => controller.addJavaScriptHandler(handlerName: name, callback: callback)`——這裡的 `name` 是 `JsBridgeGateway` 內部轉呼叫時的**參數變數**，不是字面值，維持原樣。
  - Dart→JS 方向（`main.js` 的 17 個 `window.*` 函式呼叫，例如 `state._evaluate('window.xxx(...)')`）——`/grilling` 已確認每個都只有單一呼叫點，deletion test 站不住腳，不在本 Issue 範圍，不要順手處理。
  - `main.js` 內部自己呼叫 `callHandler('...')` 的字串（vendor 釘定檔案原始碼字面值）——不改動釘定版本本身。
- **文件現況落差（規劃階段查證，2026-09-16）**：`issues.md` 原文提及「既有 `foliate_content_indexer_test.dart`...等既有測試必須零回歸即為驗證」，但實際查證 `app/test/` 下**不存在**任何 `foliate_content_indexer_test.dart` 或引用 `FoliateContentIndexer` 的測試檔（`grep -rl "FoliateContentIndexer" test/` 無結果）。本計畫 Task 3（`search/foliate_content_indexer.dart` 的替換）因此**沒有既有測試檔可跑來驗證零回歸**，改以 `flutter analyze` 乾淨＋人工核對替換後字串值與替換前完全一致（見 Task 3 Step 2）作為驗證手段；不在本 Issue 順手補一個新測試檔（不在 issues.md「單元測試要求」範圍內，屬於另一個既有落差，若需要另評估）。
- `test/reader/foliate_reader_view_test.dart` 本身**不直接斷言**任何 handler name 字串內容（該測試在 `FakeInAppWebViewPlatform` 環境下運作，依 `js_bridge_gateway.dart` 既有文件註解「現有的 fake_inappwebview_platform.dart 沒有能力模擬 JS handler 回呼」，測試驗證的是 widget 建構/行為，不是字串比對）——因此這份測試對本 Issue 而言只提供「編譯得過＋既有行為不壞」層級的保護，字串值本身正確性完全依賴 Task 1 新增的 `foliate_bridge_handlers_test.dart`，這正是 M-4 審查修訂存在的理由。
- 每個 Task 的 TDD 步驟只跑本次異動觸及的測試檔；完整 `flutter test` 只在最後一個 Task（Task 4）執行一次。

---

### Task 1: `FoliateBridgeHandlers` 常數集合

**Files:**
- Create: `app/lib/reader/foliate_bridge_handlers.dart`
- Test: `app/test/reader/foliate_bridge_handlers_test.dart`

**Interfaces:**
- Produces: `abstract final class FoliateBridgeHandlers`，11 個 `static const String` 欄位：`onTableOfContentsReady`／`onTtsSegmentsReady`／`onTtsSegmentIndexReady`／`onPageRendered`／`onError`／`onTtsHighlightOutOfSafeWindow`／`onSelectionCleared`／`onSectionCountReady`／`onSegmentsForSectionReady`／`onLocatorChanged`／`onSelectionChanged`。

- [x] **Step 1: 建立測試檔並寫入失敗測試**

建立 `app/test/reader/foliate_bridge_handlers_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/foliate_bridge_handlers.dart';

void main() {
  // M-4（審查修訂）：純靜態分析無法檢驗字串值本身有沒有筆誤（例如把
  // 'onPageRendered' 手滑打成 'onPageRenderd'），這是全專案唯一會實際
  // 比對這些字串內容的測試——main.js 端呼叫 callHandler('...') 的對應
  // 字串必須與這裡逐字相符，任一邊筆誤都只會在執行期靜默逾時（見
  // js_bridge_gateway.dart 既有註解），型別系統攔不到。
  test('每個常數值皆與預期字串完全相符', () {
    const expected = <String, String>{
      'onTableOfContentsReady': 'onTableOfContentsReady',
      'onTtsSegmentsReady': 'onTtsSegmentsReady',
      'onTtsSegmentIndexReady': 'onTtsSegmentIndexReady',
      'onPageRendered': 'onPageRendered',
      'onError': 'onError',
      'onTtsHighlightOutOfSafeWindow': 'onTtsHighlightOutOfSafeWindow',
      'onSelectionCleared': 'onSelectionCleared',
      'onSectionCountReady': 'onSectionCountReady',
      'onSegmentsForSectionReady': 'onSegmentsForSectionReady',
      'onLocatorChanged': 'onLocatorChanged',
      'onSelectionChanged': 'onSelectionChanged',
    };
    const actual = <String, String>{
      'onTableOfContentsReady': FoliateBridgeHandlers.onTableOfContentsReady,
      'onTtsSegmentsReady': FoliateBridgeHandlers.onTtsSegmentsReady,
      'onTtsSegmentIndexReady': FoliateBridgeHandlers.onTtsSegmentIndexReady,
      'onPageRendered': FoliateBridgeHandlers.onPageRendered,
      'onError': FoliateBridgeHandlers.onError,
      'onTtsHighlightOutOfSafeWindow':
          FoliateBridgeHandlers.onTtsHighlightOutOfSafeWindow,
      'onSelectionCleared': FoliateBridgeHandlers.onSelectionCleared,
      'onSectionCountReady': FoliateBridgeHandlers.onSectionCountReady,
      'onSegmentsForSectionReady':
          FoliateBridgeHandlers.onSegmentsForSectionReady,
      'onLocatorChanged': FoliateBridgeHandlers.onLocatorChanged,
      'onSelectionChanged': FoliateBridgeHandlers.onSelectionChanged,
    };

    expect(actual, expected);
  });

  test('11 個常數對應到 11 個相異字串，無重複值（防止複製貼上時誤用同一個字串）', () {
    const values = <String>{
      FoliateBridgeHandlers.onTableOfContentsReady,
      FoliateBridgeHandlers.onTtsSegmentsReady,
      FoliateBridgeHandlers.onTtsSegmentIndexReady,
      FoliateBridgeHandlers.onPageRendered,
      FoliateBridgeHandlers.onError,
      FoliateBridgeHandlers.onTtsHighlightOutOfSafeWindow,
      FoliateBridgeHandlers.onSelectionCleared,
      FoliateBridgeHandlers.onSectionCountReady,
      FoliateBridgeHandlers.onSegmentsForSectionReady,
      FoliateBridgeHandlers.onLocatorChanged,
      FoliateBridgeHandlers.onSelectionChanged,
    };

    expect(values, hasLength(11));
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/foliate_bridge_handlers_test.dart`
Expected: FAIL（`foliate_bridge_handlers.dart` 尚不存在，import 錯誤）

- [x] **Step 3: 建立 `foliate_bridge_handlers.dart`**

```dart
/// JS→Dart `callHandler()` 的 handler name 常數（Epic 43 Issue 4）。
/// main.js 端呼叫 callHandler() 時的字串字面值本身不受此常數約束
/// （vendor 檔案，不改動），僅收斂 Dart 端 register()/request()/
/// addJavaScriptHandler() 的重複字串常值。
abstract final class FoliateBridgeHandlers {
  static const onTableOfContentsReady = 'onTableOfContentsReady';
  static const onTtsSegmentsReady = 'onTtsSegmentsReady';
  static const onTtsSegmentIndexReady = 'onTtsSegmentIndexReady';
  static const onPageRendered = 'onPageRendered';
  static const onError = 'onError';
  static const onTtsHighlightOutOfSafeWindow =
      'onTtsHighlightOutOfSafeWindow';
  static const onSelectionCleared = 'onSelectionCleared';
  static const onSectionCountReady = 'onSectionCountReady';
  // I-1（審查修訂）：原稿遺漏的 3 個 handler。
  static const onSegmentsForSectionReady = 'onSegmentsForSectionReady';
  static const onLocatorChanged = 'onLocatorChanged';
  static const onSelectionChanged = 'onSelectionChanged';
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/foliate_bridge_handlers_test.dart`
Expected: PASS（2 個測試全過）

- [x] **Step 5: Commit**

```bash
git add lib/reader/foliate_bridge_handlers.dart test/reader/foliate_bridge_handlers_test.dart
git commit -m "feat(reader): 新增 FoliateBridgeHandlers handler name 常數集合"
```

---

### Task 2: `foliate_reader_view.dart` 接上 `FoliateBridgeHandlers`

**Files:**
- Modify: `app/lib/reader/foliate_reader_view.dart:17`（新增 import）、`:578`／`:586`／`:599`／`:614`／`:620`／`:626`／`:631`／`:645`／`:651`／`:660`／`:674`／`:697`（12 處 `handlerName: '...'` 字面值）

**Interfaces:**
- Consumes: `FoliateBridgeHandlers`（Task 1，`app/lib/reader/foliate_bridge_handlers.dart`）。

- [x] **Step 1: 執行既有測試建立基準線**

Run: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: PASS（記錄目前全數通過，作為本 Task 修改後的零回歸基準）

- [x] **Step 2: 新增 import**

在 `foliate_reader_view.dart` 頂部 import 區塊（`import 'foliate_bridge_codec.dart';` 後，第 17 行後）新增：

```dart
import 'foliate_bridge_handlers.dart';
```

- [x] **Step 3: 替換全部 12 處 `handlerName: '...'` 字面值**

逐一找到以下 12 處（皆為單行字面值替換，前後程式碼不變，只改 `handlerName:` 這一行本身）：

1. 約第 578 行（`_requestTableOfContents()` 內）：
   ```dart
   handlerName: 'onTableOfContentsReady',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onTableOfContentsReady,
   ```

2. 約第 586 行（`_requestTtsSegments()` 內）：
   ```dart
   handlerName: 'onTtsSegmentsReady',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onTtsSegmentsReady,
   ```

3. 約第 599 行（`_requestTtsSegmentIndex()` 內）：
   ```dart
   handlerName: 'onTtsSegmentIndexReady',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onTtsSegmentIndexReady,
   ```

4. 約第 614 行（`_onWebViewCreated()` 內 `_gateway.register<List<TocEntry>>(`）：
   ```dart
   handlerName: 'onTableOfContentsReady',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onTableOfContentsReady,
   ```

5. 約第 620 行（`_gateway.register<List<TtsSegmentCfi>>(`）：
   ```dart
   handlerName: 'onTtsSegmentsReady',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onTtsSegmentsReady,
   ```

6. 約第 626 行（`_gateway.register<int>(`）：
   ```dart
   handlerName: 'onTtsSegmentIndexReady',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onTtsSegmentIndexReady,
   ```

7. 約第 631 行（`controller.addJavaScriptHandler(` → `onPageRendered` 回呼）：
   ```dart
   handlerName: 'onPageRendered',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onPageRendered,
   ```

8. 約第 645 行（`onError` 回呼）：
   ```dart
   handlerName: 'onError',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onError,
   ```

9. 約第 651 行（`onLocatorChanged` 回呼）：
   ```dart
   handlerName: 'onLocatorChanged',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onLocatorChanged,
   ```

10. 約第 660 行（`onTtsHighlightOutOfSafeWindow` 回呼）：
    ```dart
    handlerName: 'onTtsHighlightOutOfSafeWindow',
    ```
    改為：
    ```dart
    handlerName: FoliateBridgeHandlers.onTtsHighlightOutOfSafeWindow,
    ```

11. 約第 674 行（`onSelectionChanged` 回呼）：
    ```dart
    handlerName: 'onSelectionChanged',
    ```
    改為：
    ```dart
    handlerName: FoliateBridgeHandlers.onSelectionChanged,
    ```

12. 約第 697 行（`onSelectionCleared` 回呼）：
    ```dart
    handlerName: 'onSelectionCleared',
    ```
    改為：
    ```dart
    handlerName: FoliateBridgeHandlers.onSelectionCleared,
    ```

**注意：** 第 609 行 `registerHandler: (name, callback) => controller.addJavaScriptHandler(handlerName: name, callback: callback),` **不要修改**——`name` 是 `JsBridgeGateway` 建構子注入的參數變數，不是字面值（見 Global Constraints）。

- [x] **Step 4: 執行測試確認零回歸**

Run: `flutter test test/reader/foliate_bridge_handlers_test.dart test/reader/foliate_reader_view_test.dart`（M-2 審查修訂：一併納入 Task 1 新增的常數測試，接入過程中持續受測，耗時可忽略）
Expected: PASS（`foliate_reader_view_test.dart` 與 Step 1 記錄的基準線一致，無新增失敗；`foliate_bridge_handlers_test.dart` 維持 Task 1 完成後的通過數）

- [x] **Step 5: flutter analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add lib/reader/foliate_reader_view.dart
git commit -m "refactor(reader): foliate_reader_view 改用 FoliateBridgeHandlers 常數"
```

---

### Task 3: `search/foliate_content_indexer.dart` 接上 `FoliateBridgeHandlers`

**Files:**
- Modify: `app/lib/search/foliate_content_indexer.dart:10`（新增 import）、`:105`／`:114`／`:132`／`:139`／`:164`（5 處 `handlerName: '...'` 字面值）

**Interfaces:**
- Consumes: `FoliateBridgeHandlers`（Task 1）。

- [x] **Step 1: 新增 import**

在 `foliate_content_indexer.dart` 頂部 import 區塊（`import '../reader/foliate_bridge_codec.dart';` 後，第 10 行後）新增：

```dart
import '../reader/foliate_bridge_handlers.dart';
```

- [x] **Step 2: 替換全部 5 處 `handlerName: '...'` 字面值**

1. 約第 105 行（`gateway.register<int>(` → `onSectionCountReady`）：
   ```dart
   handlerName: 'onSectionCountReady',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onSectionCountReady,
   ```

2. 約第 114 行（`c.addJavaScriptHandler(` → `onSegmentsForSectionReady`）：
   ```dart
   handlerName: 'onSegmentsForSectionReady',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onSegmentsForSectionReady,
   ```

3. 約第 132 行（`onPageRendered`）：
   ```dart
   handlerName: 'onPageRendered',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onPageRendered,
   ```

4. 約第 139 行（`onError`）：
   ```dart
   handlerName: 'onError',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onError,
   ```

5. 約第 164 行（`gateway.request<int>(` → `onSectionCountReady`）：
   ```dart
   handlerName: 'onSectionCountReady',
   ```
   改為：
   ```dart
   handlerName: FoliateBridgeHandlers.onSectionCountReady,
   ```

**注意：** 第 102 行 `registerHandler: (name, callback) => c.addJavaScriptHandler(handlerName: name, callback: callback),` **不要修改**（理由同 Task 2 注意事項）。

- [x] **Step 3: 驗證（本檔案無既有測試檔可跑，見 Global Constraints）**

Run: `flutter test test/reader/foliate_bridge_handlers_test.dart`（M-2 審查修訂：`foliate_content_indexer.dart` 本身沒有既有測試檔，但至少確保常數集合本身仍完整正確）
Expected: PASS（維持 Task 1 完成後的通過數）

Run: `flutter analyze`
Expected: `No issues found!`

人工核對：用 `grep -n "handlerName:" app/lib/search/foliate_content_indexer.dart` 確認除第 102 行（`name` 變數，不動）外，其餘 5 處皆已改為 `FoliateBridgeHandlers.xxx`，且對照 Task 1 常數值逐一與替換前的原始字面值完全相符（`onSectionCountReady`/`onSegmentsForSectionReady`/`onPageRendered`/`onError`）。

- [x] **Step 4: Commit**

```bash
git add lib/search/foliate_content_indexer.dart
git commit -m "refactor(reader): foliate_content_indexer 改用 FoliateBridgeHandlers 常數"
```

---

### Task 4: 完整驗證

**Files:** 無新增/修改（純驗證）

- [x] **Step 1: 完整 flutter analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 2: 完整 flutter test**

Run: `flutter test`
Expected: 全數通過，零回歸（若有既有已知不穩定測試案例，比照 `epic-41`/`epic-43` Issue 1/2 慣例於 PR 描述註明，不視為本 Issue 造成的回歸）

- [x] **Step 3: 於 `plan-issue-4.md` 標記全部 Task 完成**

將本檔案所有 `- [x]` 改為 `- [x]`。

- [x] **Step 4: 發起獨立程式審查**

比照 `docs/agents/issue-tracker.md`／`sdd-workflow` 既有流程，使用 `/superpowers:requesting-code-review` 對本次異動（`git diff` 對比 Task 1 之前的 commit）發起審查，結果存至 `docs/epics/epic-43-reader-architecture-hardening/reviews/review-issue-4.md`（不進版控）。
