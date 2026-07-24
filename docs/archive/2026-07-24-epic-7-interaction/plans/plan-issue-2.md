# Epic 7 Issue 2 — 資料層基礎建設：熱區設定資料模型與全域持久化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 Epic 7（互動控制）全部後續 issue 共用的熱區設定資料模型、純函式與 `SharedPreferences` 持久化機制——純 Dart、不涉及原生程式碼、不需要真實裝置。

**Architecture:** 新增 3 個獨立的純函式模組（`ZoneAction`+`isValidCustomZoneConfig`、`NavZoneMode`+`resolveZoneActions`、`hitTestZoneIndex`），再由 `GlobalReaderPrefs`（`SharedPreferences` 持久化的全域偏好）與 `ResolvedPreferences`（`ReaderScreen` 實際消費的解析後結果）兩層既有資料模型擴充串接。`GlobalReaderPrefs` 新增 3 個 non-nullable 欄位後，`ReaderPrefsManagerImpl` 是唯一同時持有讀寫兩端邏輯的類別，因此 `_loadGlobalPrefs()`/`saveGlobalPrefs()`（Task 4）與 `resolve()`（Task 5）分兩個 Task 修改，但都必須與觸發編譯錯誤的資料模型變更放在同一個 Task 內完成，讓每個 Task 結束時整個套件都能通過編譯。

**Tech Stack:** Dart（純函式、無 Flutter widget）、`shared_preferences`（既有依賴，`pageTurnMode`/`screenOrientation` 已用相同模式）、`flutter_test`。

## Global Constraints

- 格子索引慣例：全文一律 0-indexed、列優先：
  ```
  0 1 2
  3 4 5
  6 7 8
  ```
- 三個固定模板常數表（`resolveZoneActions()` 查表依據，逐格值）：

  | 模板 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
  |---|---|---|---|---|---|---|---|---|---|
  | `leftFlip` | nextPage | menu | previousPage | nextPage | menu | previousPage | nextPage | menu | previousPage |
  | `rightFlip` | previousPage | menu | nextPage | previousPage | menu | nextPage | previousPage | menu | nextPage |
  | `oneHand` | menu | none | menu | previousPage | none | previousPage | nextPage | none | nextPage |

  `custom` 無常數列，`resolveZoneActions()` 直接回傳呼叫端傳入的 `customActions` 原樣（同一個 List 參考，不重新排序/轉換/複製）。
- `hitTestZoneIndex()` 演算法（輸入 `dx`/`dy` 為點擊座標像素、相對容器左上角；`width`/`height` 為容器尺寸像素）：
  ```
  col = clamp(floor(dx / width * 3), 0, 2)
  row = clamp(floor(dy / height * 3), 0, 2)
  return row * 3 + col
  ```
  spec.md 演算法本身未定義 `width`/`height` <= 0 的行為；本計畫在 Task 3 額外加入前置防禦（直接回傳格子 4），避免除以 0 產生 `NaN`/`Infinity` 導致 `.floor()` 擲出 `UnsupportedError` 崩潰（審查修正，屬 spec.md 既有演算法之上的實作層防禦，不改變任何合法輸入下的行為）。
- `isValidCustomZoneConfig(List<ZoneAction> actions)` 驗證契約：`actions.length == 9 && actions.contains(ZoneAction.menu)`。
- `SharedPreferences` 鍵名（比照既有 `_pageTurnModeKey`/`_screenOrientationKey` 命名模式）：
  ```
  global_reader_nav_zone_mode           -> NavZoneMode.name（字串），缺席回退 rightFlip.name
  global_reader_nav_zone_custom_actions -> 9 個 ZoneAction.name 以半形逗號分隔的字串，缺席或解析失敗回退 rightFlip 模板的 9 格陣列
  global_reader_nav_zone_debug_overlay  -> bool，缺席回退 false
  ```
- **`navZoneCustomActions` 缺席/解析失敗時絕不可回退全 `none` 陣列**——會直接違反自訂模式「至少 1 格 `menu`」的驗證規則，一律回退 `rightFlip` 模板的 9 格陣列（spec.md「資料模型」審查修正）。
- 本 issue 全部程式碼皆為純 Dart（`app/lib/reader/` 下新增/修改的檔案）與既有 `ReaderPrefsManagerImpl`（`SharedPreferences`），**完全不需要真實裝置即可驗收**，不新增任何 `integration_test`。
- `flutter analyze` 全程須保持乾淨（"No issues found!"），每個 Task 結束時整個 `app/` 套件都必須能通過編譯與既有全部測試（不得留下編譯錯誤給下一個 Task）。
- 套件名稱為 `elinkbook`（測試檔 import 一律 `package:elinkbook/reader/...`）。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/lib/reader/zone_action.dart` | 新增 | `ZoneAction` 列舉（`previousPage`/`nextPage`/`menu`/`none`）+ `isValidCustomZoneConfig()` 純函式（只依賴 `List<ZoneAction>`，與 `ZoneAction` 型別同檔，不另開檔案） |
| `app/lib/reader/nav_zone_mode.dart` | 新增 | `NavZoneMode` 列舉（`leftFlip`/`rightFlip`/`oneHand`/`custom`）+ 3 個模板常數列表 + `resolveZoneActions()` 查表純函式 |
| `app/lib/reader/zone_hit_test.dart` | 新增 | `hitTestZoneIndex()` 座標轉格子索引純函式，PDF／EPUB FXL 兩條 Flutter 端手勢路徑（Issue 4、5）共用 |
| `app/lib/reader/global_reader_prefs.dart` | 修改 | 新增 `navZoneMode`/`navZoneCustomActions`/`showNavZoneDebugOverlay` 3 個 non-nullable 欄位，`copyWith`/`==`/`hashCode` 平行擴充 |
| `app/lib/reader/reader_prefs_manager_impl.dart` | 修改 | `_loadGlobalPrefs()`/`saveGlobalPrefs()` 新增 3 欄位讀寫；`resolve()` 呼叫 `resolveZoneActions()` 算出 `ResolvedPreferences.navZoneActions` |
| `app/lib/reader/resolved_preferences.dart` | 修改 | 新增 `navZoneActions: List<ZoneAction>`／`showNavZoneDebugOverlay: bool` 兩個 non-nullable 欄位 |
| `app/test/reader/zone_action_test.dart` | 新增 | `isValidCustomZoneConfig()` 邊界測試 |
| `app/test/reader/nav_zone_mode_test.dart` | 新增 | `resolveZoneActions()` 3 模板 + custom 測試 |
| `app/test/reader/zone_hit_test_test.dart` | 新增 | `hitTestZoneIndex()` 邊界值測試 |
| `app/test/reader/global_reader_prefs_test.dart` | 修改 | 擴充既有測試涵蓋新欄位 |
| `app/test/reader/reader_prefs_manager_test.dart` | 修改 | 修正因新增必填欄位而編譯失敗的既有呼叫點；新增讀寫往返（round-trip）／邊界情況測試 |
| `app/test/reader/resolved_preferences_test.dart` | 修改 | 修正因新增必填欄位而編譯失敗的既有呼叫點；擴充驗證 |
| `app/test/screens/toc_bottom_sheet_test.dart` | 修改 | 修正因 `ResolvedPreferences` 新增必填欄位而編譯失敗的既有 `const` 呼叫點（與本 issue 需求無關，純粹是介面異動的必要連帶修正） |

---

### Task 1：`ZoneAction` 列舉與 `isValidCustomZoneConfig()`

**Files:**
- Create: `app/lib/reader/zone_action.dart`
- Test: `app/test/reader/zone_action_test.dart`

**Interfaces:**
- Consumes：無（起始工單）
- Produces：`enum ZoneAction { previousPage, nextPage, menu, none }`；`bool isValidCustomZoneConfig(List<ZoneAction> actions)`——後續 Task 2（`resolveZoneActions()` 回傳型別）、Task 4/5（`GlobalReaderPrefs.navZoneCustomActions`/`ResolvedPreferences.navZoneActions` 型別）皆依賴 `ZoneAction`

- [ ] **Step 1：寫失敗測試**

建立 `app/test/reader/zone_action_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/zone_action.dart';

void main() {
  group('isValidCustomZoneConfig()', () {
    test('9 格皆非 menu 時回傳 false', () {
      final actions = List<ZoneAction>.filled(9, ZoneAction.none);
      expect(isValidCustomZoneConfig(actions), isFalse);
    });

    test('恰好 1 格為 menu 時回傳 true', () {
      final actions = List<ZoneAction>.filled(9, ZoneAction.none);
      actions[4] = ZoneAction.menu;
      expect(isValidCustomZoneConfig(actions), isTrue);
    });

    test('多格為 menu 時回傳 true', () {
      final actions = List<ZoneAction>.filled(9, ZoneAction.previousPage);
      actions[0] = ZoneAction.menu;
      actions[8] = ZoneAction.menu;
      expect(isValidCustomZoneConfig(actions), isTrue);
    });

    test('長度不為 9 時回傳 false（即使含 menu）', () {
      final actions = [ZoneAction.menu, ZoneAction.previousPage];
      expect(isValidCustomZoneConfig(actions), isFalse);
    });

    test('長度為 9 但全部為 previousPage/nextPage/none 混合時回傳 false', () {
      final actions = [
        ZoneAction.previousPage, ZoneAction.nextPage, ZoneAction.none,
        ZoneAction.previousPage, ZoneAction.nextPage, ZoneAction.none,
        ZoneAction.previousPage, ZoneAction.nextPage, ZoneAction.none,
      ];
      expect(isValidCustomZoneConfig(actions), isFalse);
    });
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/zone_action_test.dart
```

Expected：FAIL（`Error: Not found: 'package:elinkbook/reader/zone_action.dart'`，檔案尚不存在）。

- [ ] **Step 3：實作**

建立 `app/lib/reader/zone_action.dart`：

```dart
/// 熱區動作：使用者點擊 3×3 導航熱區某一格時觸發的行為
/// （design.md 決策 #8）。
enum ZoneAction { previousPage, nextPage, menu, none }

/// 驗證自訂熱區設定是否合法：長度需固定為 9，且至少 1 格為
/// [ZoneAction.menu]——避免使用者設定出沒有任何格子能退出沉浸模式的死鎖
/// 組合（design.md 決策 #7）。`NavZoneSettingsScreen`（Issue 3）儲存自訂
/// 設定前呼叫。
bool isValidCustomZoneConfig(List<ZoneAction> actions) =>
    actions.length == 9 && actions.contains(ZoneAction.menu);
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/zone_action_test.dart
```

Expected：PASS（5 個測試全過）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/zone_action.dart app/test/reader/zone_action_test.dart
git commit -m "feat(epic-7): add ZoneAction enum and isValidCustomZoneConfig"
```

---

### Task 2：`NavZoneMode` 列舉與 `resolveZoneActions()`

**Files:**
- Create: `app/lib/reader/nav_zone_mode.dart`
- Test: `app/test/reader/nav_zone_mode_test.dart`

**Interfaces:**
- Consumes：`ZoneAction`（Task 1，`app/lib/reader/zone_action.dart`）
- Produces：`enum NavZoneMode { leftFlip, rightFlip, oneHand, custom }`；`const List<ZoneAction> rightFlipZoneTemplate`（供 Task 4 的 `GlobalReaderPrefs.initial()` 常數初始化與 `ReaderPrefsManagerImpl` 回退值使用，`const` 保證可在 `const` 建構子初始化列表中引用）；`List<ZoneAction> resolveZoneActions(NavZoneMode mode, List<ZoneAction> customActions)`——供 Task 5（`ReaderPrefsManagerImpl.resolve()`）呼叫

- [ ] **Step 1：寫失敗測試**

建立 `app/test/reader/nav_zone_mode_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';

void main() {
  group('resolveZoneActions()', () {
    test('leftFlip 模板回傳與常數表逐格一致的 9 格陣列', () {
      expect(
        resolveZoneActions(NavZoneMode.leftFlip, const []),
        const [
          ZoneAction.nextPage, ZoneAction.menu, ZoneAction.previousPage,
          ZoneAction.nextPage, ZoneAction.menu, ZoneAction.previousPage,
          ZoneAction.nextPage, ZoneAction.menu, ZoneAction.previousPage,
        ],
      );
    });

    test('rightFlip 模板回傳與常數表逐格一致的 9 格陣列', () {
      expect(
        resolveZoneActions(NavZoneMode.rightFlip, const []),
        const [
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
        ],
      );
    });

    test('oneHand 模板回傳與常數表逐格一致的 9 格陣列', () {
      expect(
        resolveZoneActions(NavZoneMode.oneHand, const []),
        const [
          ZoneAction.menu, ZoneAction.none, ZoneAction.menu,
          ZoneAction.previousPage, ZoneAction.none, ZoneAction.previousPage,
          ZoneAction.nextPage, ZoneAction.none, ZoneAction.nextPage,
        ],
      );
    });

    test('custom 模式回傳傳入陣列原樣（同一個參考，不重新排序/轉換）', () {
      const customActions = [
        ZoneAction.none, ZoneAction.menu, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
      ];
      expect(
        resolveZoneActions(NavZoneMode.custom, customActions),
        same(customActions),
      );
    });
  });

  test('rightFlipZoneTemplate 常數本身與 rightFlip 模板一致', () {
    expect(
      rightFlipZoneTemplate,
      resolveZoneActions(NavZoneMode.rightFlip, const []),
    );
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/nav_zone_mode_test.dart
```

Expected：FAIL（`Error: Not found: 'package:elinkbook/reader/nav_zone_mode.dart'`）。

- [ ] **Step 3：實作**

建立 `app/lib/reader/nav_zone_mode.dart`：

```dart
import 'zone_action.dart';

/// 熱區映射模式：3 個固定模板（[leftFlip]/[rightFlip]/[oneHand]）與
/// [custom]（完全自由編輯 9 格）四選一互斥，不可個別微調固定模板
/// （design.md 決策 #2、#7）。
enum NavZoneMode { leftFlip, rightFlip, oneHand, custom }

/// `leftFlip`：左欄＝下一頁、中欄＝選單、右欄＝上一頁（design.md 決策 #4）。
const List<ZoneAction> leftFlipZoneTemplate = [
  ZoneAction.nextPage, ZoneAction.menu, ZoneAction.previousPage,
  ZoneAction.nextPage, ZoneAction.menu, ZoneAction.previousPage,
  ZoneAction.nextPage, ZoneAction.menu, ZoneAction.previousPage,
];

/// `rightFlip`：左欄＝上一頁、中欄＝選單、右欄＝下一頁（design.md 決策 #5）。
/// 也是 [NavZoneMode] 與 `GlobalReaderPrefs.navZoneCustomActions` 的預設/
/// 回退值來源（spec.md「資料模型」）。
const List<ZoneAction> rightFlipZoneTemplate = [
  ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
  ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
  ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
];

/// `oneHand`：左右欄對稱，上排＝選單、中排＝上一頁、下排＝下一頁，中間欄
/// 全部無動作（design.md 決策 #6）。
const List<ZoneAction> oneHandZoneTemplate = [
  ZoneAction.menu, ZoneAction.none, ZoneAction.menu,
  ZoneAction.previousPage, ZoneAction.none, ZoneAction.previousPage,
  ZoneAction.nextPage, ZoneAction.none, ZoneAction.nextPage,
];

/// 依 [mode] 查表回傳對應的 9 格熱區動作陣列；[mode] 為
/// [NavZoneMode.custom] 時直接回傳 [customActions] 原樣（不重新排序/
/// 轉換/複製）。
List<ZoneAction> resolveZoneActions(
  NavZoneMode mode,
  List<ZoneAction> customActions,
) {
  switch (mode) {
    case NavZoneMode.leftFlip:
      return leftFlipZoneTemplate;
    case NavZoneMode.rightFlip:
      return rightFlipZoneTemplate;
    case NavZoneMode.oneHand:
      return oneHandZoneTemplate;
    case NavZoneMode.custom:
      return customActions;
  }
}
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/nav_zone_mode_test.dart
```

Expected：PASS（5 個測試全過）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/nav_zone_mode.dart app/test/reader/nav_zone_mode_test.dart
git commit -m "feat(epic-7): add NavZoneMode enum and resolveZoneActions"
```

---

### Task 3：`hitTestZoneIndex()` 座標轉格子索引

**Files:**
- Create: `app/lib/reader/zone_hit_test.dart`
- Test: `app/test/reader/zone_hit_test_test.dart`

**Interfaces:**
- Consumes：無（純幾何運算，不依賴 `ZoneAction`/`NavZoneMode`）
- Produces：`int hitTestZoneIndex({required double dx, required double dy, required double width, required double height})`——供 Issue 4（PDF 熱區）、Issue 5（EPUB FXL 熱區，若採座標換算路徑）後續呼叫

- [ ] **Step 1：寫失敗測試**

建立 `app/test/reader/zone_hit_test_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/zone_hit_test.dart';

void main() {
  group('hitTestZoneIndex()', () {
    const width = 300.0;
    const height = 300.0;

    test('左上角 (0,0) 回傳格子 0', () {
      expect(hitTestZoneIndex(dx: 0, dy: 0, width: width, height: height), 0);
    });

    test('正中心回傳格子 4', () {
      expect(
        hitTestZoneIndex(dx: 150, dy: 150, width: width, height: height),
        4,
      );
    });

    test('右上角（寬度邊界內）回傳格子 2', () {
      expect(
        hitTestZoneIndex(dx: 299, dy: 0, width: width, height: height),
        2,
      );
    });

    test('左下角（高度邊界內）回傳格子 6', () {
      expect(
        hitTestZoneIndex(dx: 0, dy: 299, width: width, height: height),
        6,
      );
    });

    test('右下角（寬高邊界內）回傳格子 8', () {
      expect(
        hitTestZoneIndex(dx: 299, dy: 299, width: width, height: height),
        8,
      );
    });

    test('dx 恰好等於 width（浮點邊界）仍 clamp 在格子 2，不產生 index 9', () {
      expect(
        hitTestZoneIndex(dx: 300, dy: 0, width: width, height: height),
        2,
      );
    });

    test('dy 恰好等於 height（浮點邊界）仍 clamp 在格子 6，不產生超界', () {
      expect(
        hitTestZoneIndex(dx: 0, dy: 300, width: width, height: height),
        6,
      );
    });

    test('第一條格線正上方座標 (dx=100) 歸屬 col 1', () {
      expect(
        hitTestZoneIndex(dx: 100, dy: 150, width: width, height: height),
        4,
      );
    });

    test('第二條格線正上方座標 (dx=200) 歸屬 col 2', () {
      expect(
        hitTestZoneIndex(dx: 200, dy: 150, width: width, height: height),
        5,
      );
    });

    test(
        'width 或 height 為 0 或負數時，安全回傳格子 4，不拋出例外'
        '（審查修正：避免除以 0 產生 NaN/Infinity 導致 .floor() 拋出 UnsupportedError）',
        () {
      expect(hitTestZoneIndex(dx: 10, dy: 10, width: 0, height: 300), 4);
      expect(hitTestZoneIndex(dx: 10, dy: 10, width: 300, height: 0), 4);
      expect(hitTestZoneIndex(dx: 10, dy: 10, width: -1, height: 300), 4);
      expect(hitTestZoneIndex(dx: 10, dy: 10, width: 300, height: -1), 4);
    });
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/zone_hit_test_test.dart
```

Expected：FAIL（`Error: Not found: 'package:elinkbook/reader/zone_hit_test.dart'`）。

- [ ] **Step 3：實作**

建立 `app/lib/reader/zone_hit_test.dart`：

```dart
/// 依點擊座標換算 3×3 導航熱區的格子索引（0-8，列優先，見 spec.md
/// 「格子索引慣例」）。PDF／EPUB FXL 兩條 Flutter 端手勢路徑共用同一份
/// 實作；EPUB 流式熱區由原生 Kotlin `NavZoneHitTester.cellIndex()`
/// （Issue 6）平行實作相同演算法，兩端需人工保持同步。
///
/// [dx]/[dy] 為點擊座標（像素，相對容器左上角），[width]/[height] 為容器
/// 尺寸（像素）。回傳值以 `.clamp()` 保證落在 0-8，不因浮點誤差在邊界
/// 產生超界索引。[width]/[height] 為 0 或負數（例如版面尚未完成排版）時
/// 直接回傳格子 4（正中央），避免除以 0 產生 `NaN`/`Infinity` 導致
/// `.floor()` 擲出 `UnsupportedError` 而讓 App 崩潰（審查修正）。
int hitTestZoneIndex({
  required double dx,
  required double dy,
  required double width,
  required double height,
}) {
  if (width <= 0 || height <= 0) return 4;
  final col = ((dx / width) * 3).floor().clamp(0, 2).toInt();
  final row = ((dy / height) * 3).floor().clamp(0, 2).toInt();
  return row * 3 + col;
}
```

- [ ] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/zone_hit_test_test.dart
```

Expected：PASS（10 個測試全過）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/zone_hit_test.dart app/test/reader/zone_hit_test_test.dart
git commit -m "feat(epic-7): add hitTestZoneIndex coordinate-to-cell helper"
```

---

### Task 4：`GlobalReaderPrefs` 新欄位 + `ReaderPrefsManagerImpl` 讀寫

**Files:**
- Modify: `app/lib/reader/global_reader_prefs.dart`（全檔重寫，見 Step 3）
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart:1-90`（新增 import、3 個鍵名常數、`_loadGlobalPrefs()`/`saveGlobalPrefs()` 讀寫、新增 2 個 encode/decode helper）
- Modify: `app/test/reader/reader_prefs_manager_test.dart`（修正因新增必填欄位而編譯失敗的既有呼叫點；新增讀寫往返（round-trip）／邊界情況測試）
- Test: `app/test/reader/global_reader_prefs_test.dart`（全檔重寫，見 Step 1）

**Interfaces:**
- Consumes：`ZoneAction`（Task 1）、`NavZoneMode`/`rightFlipZoneTemplate`（Task 2）
- Produces：`GlobalReaderPrefs` 新增 `navZoneMode: NavZoneMode`／`navZoneCustomActions: List<ZoneAction>`／`showNavZoneDebugOverlay: bool` 三個 non-nullable 欄位（皆為 `copyWith` 具名參數）——供 Task 5（`ReaderPrefsManagerImpl.resolve()`）與後續 Issue 3（`NavZoneSettingsScreen`）讀寫

**⚠️ 編譯順序說明**：一旦 `GlobalReaderPrefs` 建構子新增必填參數，`reader_prefs_manager_impl.dart` 內建構 `GlobalReaderPrefs(...)` 的 `_loadGlobalPrefs()` 會立即編譯失敗，因此 Step 3（資料模型）與 Step 7（讀寫邏輯）必須在同一個 Task 內完成，不可分拆到不同 Task。

- [ ] **Step 1：寫失敗測試（`GlobalReaderPrefs`）**

全檔重寫 `app/test/reader/global_reader_prefs_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/zone_action.dart';

void main() {
  test(
      'GlobalReaderPrefs.initial() 回傳與現行硬編碼預設一致的值（paginated/auto/rightFlip）',
      () {
    const prefs = GlobalReaderPrefs.initial();
    expect(prefs.pageTurnMode, PageTurnMode.paginated);
    expect(prefs.screenOrientation, ScreenOrientationSetting.auto);
    expect(prefs.navZoneMode, NavZoneMode.rightFlip);
    expect(prefs.navZoneCustomActions, rightFlipZoneTemplate);
    expect(prefs.showNavZoneDebugOverlay, isFalse);
  });

  test('copyWith 只更新指定欄位，其餘欄位保留原值', () {
    const original = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
      navZoneMode: NavZoneMode.rightFlip,
      navZoneCustomActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: false,
    );
    final updated = original.copyWith(pageTurnMode: PageTurnMode.scroll);
    expect(updated.pageTurnMode, PageTurnMode.scroll);
    expect(updated.screenOrientation, ScreenOrientationSetting.auto);
    expect(updated.navZoneMode, NavZoneMode.rightFlip);
    expect(updated.navZoneCustomActions, rightFlipZoneTemplate);
    expect(updated.showNavZoneDebugOverlay, isFalse);
  });

  test('copyWith 可個別更新熱區三欄位', () {
    const original = GlobalReaderPrefs.initial();
    const customActions = [
      ZoneAction.menu, ZoneAction.none, ZoneAction.none,
      ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ];
    final updated = original.copyWith(
      navZoneMode: NavZoneMode.custom,
      navZoneCustomActions: customActions,
      showNavZoneDebugOverlay: true,
    );
    expect(updated.navZoneMode, NavZoneMode.custom);
    expect(updated.navZoneCustomActions, customActions);
    expect(updated.showNavZoneDebugOverlay, isTrue);
    expect(updated.pageTurnMode, original.pageTurnMode);
  });

  test('五個欄位值皆相同的 GlobalReaderPrefs 視為相等', () {
    const a = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.scroll,
      screenOrientation: ScreenOrientationSetting.lock90,
      navZoneMode: NavZoneMode.oneHand,
      navZoneCustomActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: true,
    );
    const b = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.scroll,
      screenOrientation: ScreenOrientationSetting.lock90,
      navZoneMode: NavZoneMode.oneHand,
      navZoneCustomActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: true,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('navZoneCustomActions 內容不同時視為不相等', () {
    const a = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
      navZoneMode: NavZoneMode.custom,
      navZoneCustomActions: [
        ZoneAction.menu, ZoneAction.none, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ],
      showNavZoneDebugOverlay: false,
    );
    const b = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
      navZoneMode: NavZoneMode.custom,
      navZoneCustomActions: [
        ZoneAction.none, ZoneAction.none, ZoneAction.menu,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ],
      showNavZoneDebugOverlay: false,
    );
    expect(a == b, isFalse);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/global_reader_prefs_test.dart
```

Expected：FAIL（`Error: The named parameter 'navZoneMode' isn't defined`，`GlobalReaderPrefs` 尚無新欄位）。

- [ ] **Step 3：實作（`GlobalReaderPrefs` 全檔重寫）**

```dart
import 'package:flutter/foundation.dart';

import 'nav_zone_mode.dart';
import 'page_turn_mode.dart';
import 'screen_orientation_setting.dart';
import 'zone_action.dart';

/// 跨書生效的全域預設閱讀偏好。
///
/// 五個欄位皆 non-nullable——與 [BookReaderPrefs] 的「全欄位 nullable、
/// null=未覆寫」語意刻意不同：全域層本身沒有更上層的預設可回退，任何時候
/// 都必須有一個明確生效值。
class GlobalReaderPrefs {
  final PageTurnMode pageTurnMode;
  final ScreenOrientationSetting screenOrientation;

  /// 熱區映射模式，預設 [NavZoneMode.rightFlip]（design.md「新增的
  /// GlobalReaderPrefs 欄位」）。
  final NavZoneMode navZoneMode;

  /// 長度固定 9。僅 [navZoneMode] 為 [NavZoneMode.custom] 時內容才生效
  /// （其餘模式由 [resolveZoneActions] 查表算出，忽略本欄位）；仍持續
  /// 保留是為了使用者切回自訂模式時能還原上次編輯結果。
  final List<ZoneAction> navZoneCustomActions;

  /// 是否顯示熱區輔助線，預設 `false`。
  final bool showNavZoneDebugOverlay;

  const GlobalReaderPrefs({
    required this.pageTurnMode,
    required this.screenOrientation,
    required this.navZoneMode,
    required this.navZoneCustomActions,
    required this.showNavZoneDebugOverlay,
  });

  /// 初始值，與現行 GlobalReaderDefaults 的既有硬編碼預設一致，
  /// 不改變任何現有使用者體驗。
  const GlobalReaderPrefs.initial()
      : pageTurnMode = PageTurnMode.paginated,
        screenOrientation = ScreenOrientationSetting.auto,
        navZoneMode = NavZoneMode.rightFlip,
        navZoneCustomActions = rightFlipZoneTemplate,
        showNavZoneDebugOverlay = false;

  GlobalReaderPrefs copyWith({
    PageTurnMode? pageTurnMode,
    ScreenOrientationSetting? screenOrientation,
    NavZoneMode? navZoneMode,
    List<ZoneAction>? navZoneCustomActions,
    bool? showNavZoneDebugOverlay,
  }) {
    return GlobalReaderPrefs(
      pageTurnMode: pageTurnMode ?? this.pageTurnMode,
      screenOrientation: screenOrientation ?? this.screenOrientation,
      navZoneMode: navZoneMode ?? this.navZoneMode,
      navZoneCustomActions: navZoneCustomActions ?? this.navZoneCustomActions,
      showNavZoneDebugOverlay:
          showNavZoneDebugOverlay ?? this.showNavZoneDebugOverlay,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlobalReaderPrefs &&
      other.pageTurnMode == pageTurnMode &&
      other.screenOrientation == screenOrientation &&
      other.navZoneMode == navZoneMode &&
      listEquals(other.navZoneCustomActions, navZoneCustomActions) &&
      other.showNavZoneDebugOverlay == showNavZoneDebugOverlay;

  @override
  int get hashCode => Object.hash(
        pageTurnMode,
        screenOrientation,
        navZoneMode,
        Object.hashAll(navZoneCustomActions),
        showNavZoneDebugOverlay,
      );
}
```

- [ ] **Step 4：執行測試確認 `GlobalReaderPrefs` 測試通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/global_reader_prefs_test.dart
```

Expected：PASS（5 個測試全過）。

- [ ] **Step 5：寫失敗測試（`ReaderPrefsManagerImpl` 讀寫）**

修改 `app/test/reader/reader_prefs_manager_test.dart`：

1. 修正既有兩處因新增必填欄位而編譯失敗的 `GlobalReaderPrefs(...)` 直接建構呼叫（原本只有 `pageTurnMode`/`screenOrientation` 兩個具名參數）。

   將第一處（`resolve()` 群組內「單書覆寫為 null 時，正確退回全域預設」測試）：

   ```dart
   globalPrefs: const GlobalReaderPrefs(
     pageTurnMode: PageTurnMode.scroll,
     screenOrientation: ScreenOrientationSetting.lock270,
   ),
   ```

   改為：

   ```dart
   globalPrefs: const GlobalReaderPrefs(
     pageTurnMode: PageTurnMode.scroll,
     screenOrientation: ScreenOrientationSetting.lock270,
     navZoneMode: NavZoneMode.rightFlip,
     navZoneCustomActions: rightFlipZoneTemplate,
     showNavZoneDebugOverlay: false,
   ),
   ```

   將第二處（`load()` 群組內「saveGlobalPrefs 寫入後，load 讀回相同的全域預設值」測試）整段改為：

   ```dart
   test('saveGlobalPrefs 寫入後，load 讀回相同的全域預設值（含熱區三欄位）',
       () async {
     const globalPrefs = GlobalReaderPrefs(
       pageTurnMode: PageTurnMode.scroll,
       screenOrientation: ScreenOrientationSetting.lock90,
       navZoneMode: NavZoneMode.custom,
       navZoneCustomActions: [
         ZoneAction.menu, ZoneAction.none, ZoneAction.none,
         ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
         ZoneAction.none, ZoneAction.none, ZoneAction.none,
       ],
       showNavZoneDebugOverlay: true,
     );
     await manager.saveGlobalPrefs(globalPrefs);
     final loaded = await manager.load('b1');
     expect(loaded.globalPrefs, globalPrefs);
   });
   ```

2. 在 `load()` 群組內新增 2 個邊界情況測試（緊接在上面那個測試之後）：

   ```dart
   test('navZoneCustomActions 已儲存值為空字串時，安全回退為 rightFlip 模板',
       () async {
     SharedPreferences.setMockInitialValues({
       'global_reader_nav_zone_custom_actions': '',
     });
     final loaded = await manager.load('b1');
     expect(loaded.globalPrefs.navZoneCustomActions, rightFlipZoneTemplate);
   });

   test('navZoneCustomActions 未儲存過（缺鍵）時，安全回退為 rightFlip 模板',
       () async {
     final loaded = await manager.load('b1');
     expect(loaded.globalPrefs.navZoneCustomActions, rightFlipZoneTemplate);
   });
   ```

3. 在檔案頂部新增缺少的 import：

   ```dart
   import 'package:elinkbook/reader/nav_zone_mode.dart';
   import 'package:elinkbook/reader/zone_action.dart';
   ```

- [ ] **Step 6：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/reader_prefs_manager_test.dart
```

Expected：FAIL（編譯錯誤：`reader_prefs_manager_impl.dart` 內 `_loadGlobalPrefs()` 建構 `GlobalReaderPrefs(pageTurnMode: ..., screenOrientation: ...)` 缺少 3 個新必填具名參數）。

- [ ] **Step 7：實作（`ReaderPrefsManagerImpl` 讀寫邏輯）**

修改 `app/lib/reader/reader_prefs_manager_impl.dart`。

檔案頂部 import 區塊（`global_reader_prefs.dart` 之後、`page_turn_mode.dart` 之前插入 `nav_zone_mode.dart`；`writing_mode.dart` 之後新增 `zone_action.dart`）：

```dart
import 'global_reader_prefs.dart';
import 'nav_zone_mode.dart';
import 'page_turn_mode.dart';
```

```dart
import 'writing_mode.dart';
import 'zone_action.dart';
```

鍵名常數區塊，原本：

```dart
  static const _pageTurnModeKey = 'global_reader_page_turn_mode';
  static const _screenOrientationKey = 'global_reader_screen_orientation';
```

改為：

```dart
  static const _pageTurnModeKey = 'global_reader_page_turn_mode';
  static const _screenOrientationKey = 'global_reader_screen_orientation';
  static const _navZoneModeKey = 'global_reader_nav_zone_mode';
  static const _navZoneCustomActionsKey =
      'global_reader_nav_zone_custom_actions';
  static const _navZoneDebugOverlayKey =
      'global_reader_nav_zone_debug_overlay';
```

`_loadGlobalPrefs()`，原本：

```dart
  Future<GlobalReaderPrefs> _loadGlobalPrefs() async {
    final sp = await SharedPreferences.getInstance();
    return GlobalReaderPrefs(
      pageTurnMode: _readEnum(sp, _pageTurnModeKey, PageTurnMode.values) ??
          PageTurnMode.paginated,
      screenOrientation: _readEnum(
            sp,
            _screenOrientationKey,
            ScreenOrientationSetting.values,
          ) ??
          ScreenOrientationSetting.auto,
    );
  }
```

改為：

```dart
  Future<GlobalReaderPrefs> _loadGlobalPrefs() async {
    final sp = await SharedPreferences.getInstance();
    return GlobalReaderPrefs(
      pageTurnMode: _readEnum(sp, _pageTurnModeKey, PageTurnMode.values) ??
          PageTurnMode.paginated,
      screenOrientation: _readEnum(
            sp,
            _screenOrientationKey,
            ScreenOrientationSetting.values,
          ) ??
          ScreenOrientationSetting.auto,
      navZoneMode: _readEnum(sp, _navZoneModeKey, NavZoneMode.values) ??
          NavZoneMode.rightFlip,
      navZoneCustomActions:
          _decodeZoneActions(sp.getString(_navZoneCustomActionsKey)),
      showNavZoneDebugOverlay: sp.getBool(_navZoneDebugOverlayKey) ?? false,
    );
  }
```

在 `_readEnum<T>()` 方法之後新增 2 個 helper 方法：

```dart
  /// `navZoneCustomActions` 缺席、長度不為 9、或含有無法辨識的 [ZoneAction]
  /// 名稱時，一律回退為 [rightFlipZoneTemplate]——不可回退全 `none`，會
  /// 違反自訂模式「至少 1 格 menu」的驗證規則（spec.md「資料模型」審查
  /// 修正）。只捕捉 `ArgumentError`——`EnumName.byName()` 找不到對應列舉
  /// 值時擲出的例外型別——不使用 `catch (_)` 寬泛捕捉一切，避免意外吞掉
  /// 非預期的系統層級錯誤（審查修正）。
  List<ZoneAction> _decodeZoneActions(String? raw) {
    if (raw == null) return rightFlipZoneTemplate;
    final parts = raw.split(',');
    if (parts.length != 9) return rightFlipZoneTemplate;
    try {
      return parts.map((name) => ZoneAction.values.byName(name)).toList();
    } on ArgumentError catch (_) {
      return rightFlipZoneTemplate;
    }
  }

  String _encodeZoneActions(List<ZoneAction> actions) =>
      actions.map((a) => a.name).join(',');
```

`saveGlobalPrefs()`，原本：

```dart
  @override
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_pageTurnModeKey, prefs.pageTurnMode.name);
    await sp.setString(_screenOrientationKey, prefs.screenOrientation.name);
  }
```

改為：

```dart
  @override
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_pageTurnModeKey, prefs.pageTurnMode.name);
    await sp.setString(_screenOrientationKey, prefs.screenOrientation.name);
    await sp.setString(_navZoneModeKey, prefs.navZoneMode.name);
    await sp.setString(
      _navZoneCustomActionsKey,
      _encodeZoneActions(prefs.navZoneCustomActions),
    );
    await sp.setBool(_navZoneDebugOverlayKey, prefs.showNavZoneDebugOverlay);
  }
```

- [ ] **Step 8：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/reader_prefs_manager_test.dart
flutter test test/reader/global_reader_prefs_test.dart
```

Expected：PASS（兩個檔案全部測試皆過。注意：此時 `resolve()` 群組測試與 `resolved_preferences_test.dart`／`toc_bottom_sheet_test.dart` 仍會編譯失敗——那是 Task 5 的範圍，`ResolvedPreferences` 尚未變更，`resolve()` 內部尚未呼叫 `resolveZoneActions()`，本 Task 不觸碰 `resolve()` 方法本體）。

- [ ] **Step 9：Commit**

```bash
git add app/lib/reader/global_reader_prefs.dart app/lib/reader/reader_prefs_manager_impl.dart app/test/reader/global_reader_prefs_test.dart app/test/reader/reader_prefs_manager_test.dart
git commit -m "feat(epic-7): add nav zone fields to GlobalReaderPrefs and persist them"
```

---

### Task 5：`ResolvedPreferences` 新欄位 + `resolve()` 串接

**Files:**
- Modify: `app/lib/reader/resolved_preferences.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`（`resolve()` 方法本體）
- Modify: `app/test/reader/resolved_preferences_test.dart`
- Modify: `app/test/reader/reader_prefs_manager_test.dart`（`resolve()` 群組新增/擴充測試）
- Modify: `app/test/screens/toc_bottom_sheet_test.dart`（修正因新增必填欄位而編譯失敗的既有 `const` 呼叫點，與本 issue 需求無關，純屬介面異動的必要連帶修正）

**Interfaces:**
- Consumes：`ZoneAction`（Task 1）、`resolveZoneActions()`（Task 2）、`GlobalReaderPrefs.navZoneMode`/`navZoneCustomActions`/`showNavZoneDebugOverlay`（Task 4）
- Produces：`ResolvedPreferences` 新增 `navZoneActions: List<ZoneAction>`／`showNavZoneDebugOverlay: bool` 兩個 non-nullable 欄位——供 Issue 4（`ReaderScreen`/`PdfReaderView`）、Issue 5（`EpubReaderView` FXL）、Issue 6（EPUB 流式）讀取

- [x] **Step 1：寫失敗測試（`ResolvedPreferences`）**

修改 `app/test/reader/resolved_preferences_test.dart` 全檔為：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/zone_action.dart';

void main() {
  test('建構後各欄位保留傳入值，EPUB 欄位可為 null（無既存預設值，維持既有 pass-through 語意）',
      () {
    const resolved = ResolvedPreferences(
      writingMode: null,
      fontFamily: null,
      fontSize: null,
      fontWeight: null,
      lineHeight: null,
      paragraphSpacing: null,
      pageMargins: null,
      textAlign: null,
      publisherStyles: null,
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
      pdfFitMode: PdfFitMode.pageFit,
      pdfContrast: 0,
      pdfBrightness: 0,
      pdfBoldStrength: 0,
      pdfCropMode: PdfCropMode.none,
      pdfCropRect: null,
      dualPageMode: DualPageMode.auto,
      dualPageCoverAlone: true,
      dualPageDirection: DualPageDirection.ltr,
      showHeader: true,
      showFooter: true,
      navZoneActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: false,
    );

    expect(resolved.fontSize, isNull);
    expect(resolved.textAlign, isNull);
    expect(resolved.pageTurnMode, PageTurnMode.paginated);
    expect(resolved.pdfFitMode, PdfFitMode.pageFit);
    expect(resolved.dualPageMode, DualPageMode.auto);
    expect(resolved.dualPageCoverAlone, isTrue);
    expect(resolved.dualPageDirection, DualPageDirection.ltr);
    expect(resolved.navZoneActions, rightFlipZoneTemplate);
    expect(resolved.showNavZoneDebugOverlay, isFalse);
  });
}
```

- [x] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/resolved_preferences_test.dart
```

Expected：FAIL（`Error: The named parameter 'navZoneActions' isn't defined`）。

- [x] **Step 3：實作（`ResolvedPreferences`）**

修改 `app/lib/reader/resolved_preferences.dart`。頂部 import 區塊新增：

```dart
import 'pdf_fit_mode.dart';
import 'screen_orientation_setting.dart';
import 'writing_mode.dart';
import 'zone_action.dart';
```

（原本 `import 'writing_mode.dart';` 是最後一行，改為在其後新增 `zone_action.dart`。）

類別 docstring 內「欄位是否 non-nullable 的判斷依據」段落，原本：

```dart
/// **欄位是否 non-nullable 的判斷依據**：只有現行架構已有明確、安全預設值
/// 的欄位才宣告 non-nullable（`pageTurnMode`／`screenOrientation`／
/// `pdfFitMode`／`pdfContrast`／`pdfBrightness`／`pdfBoldStrength`／
/// `pdfCropMode`）。EPUB 字型/排版 8 個欄位與 `writingMode`／`pdfCropRect`
/// 維持 nullable
```

改為：

```dart
/// **欄位是否 non-nullable 的判斷依據**：只有現行架構已有明確、安全預設值
/// 的欄位才宣告 non-nullable（`pageTurnMode`／`screenOrientation`／
/// `pdfFitMode`／`pdfContrast`／`pdfBrightness`／`pdfBoldStrength`／
/// `pdfCropMode`／`navZoneActions`／`showNavZoneDebugOverlay`）。EPUB
/// 字型/排版 8 個欄位與 `writingMode`／`pdfCropRect` 維持 nullable
```

欄位宣告區塊，原本最後兩行：

```dart
  final bool showHeader;
  final bool showFooter;

  const ResolvedPreferences({
```

改為：

```dart
  final bool showHeader;
  final bool showFooter;

  /// 長度固定 9，由 [ReaderPrefsManagerImpl.resolve] 呼叫
  /// `resolveZoneActions()` 算出（見 epic-7-interaction spec.md）。
  final List<ZoneAction> navZoneActions;
  final bool showNavZoneDebugOverlay;

  const ResolvedPreferences({
```

建構子具名參數區塊，原本結尾：

```dart
    required this.showHeader,
    required this.showFooter,
  });
```

改為：

```dart
    required this.showHeader,
    required this.showFooter,
    required this.navZoneActions,
    required this.showNavZoneDebugOverlay,
  });
```

- [x] **Step 4：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/resolved_preferences_test.dart
```

Expected：PASS（1 個測試通過）。

- [x] **Step 5：寫失敗測試（`resolve()` 串接 + 修正既有連帶編譯錯誤）**

1. 修改 `app/test/screens/toc_bottom_sheet_test.dart` 頂部新增 import：

   ```dart
   import 'package:elinkbook/reader/nav_zone_mode.dart';
   ```

   `_testResolved` 常數定義，原本：

   ```dart
   const _testResolved = ResolvedPreferences(
     pageTurnMode: PageTurnMode.paginated,
     screenOrientation: ScreenOrientationSetting.auto,
     pdfFitMode: PdfFitMode.pageFit,
     pdfContrast: 0,
     pdfBrightness: 0,
     pdfBoldStrength: 0,
     pdfCropMode: PdfCropMode.none,
     dualPageMode: DualPageMode.auto,
     dualPageCoverAlone: true,
     dualPageDirection: DualPageDirection.rtl,
     showHeader: true,
     showFooter: true,
   );
   ```

   改為：

   ```dart
   const _testResolved = ResolvedPreferences(
     pageTurnMode: PageTurnMode.paginated,
     screenOrientation: ScreenOrientationSetting.auto,
     pdfFitMode: PdfFitMode.pageFit,
     pdfContrast: 0,
     pdfBrightness: 0,
     pdfBoldStrength: 0,
     pdfCropMode: PdfCropMode.none,
     dualPageMode: DualPageMode.auto,
     dualPageCoverAlone: true,
     dualPageDirection: DualPageDirection.rtl,
     showHeader: true,
     showFooter: true,
     navZoneActions: rightFlipZoneTemplate,
     showNavZoneDebugOverlay: false,
   );
   ```

2. 修改 `app/test/reader/reader_prefs_manager_test.dart`：在 `resolve()` 群組（`group('resolve()（純同步，不需要資料庫/SharedPreferences）', () { ... })`）內，擴充既有「單書覆寫為 null 時，正確退回全域預設」測試，並新增 1 個 `custom` 模式測試。

   將既有測試整段改為：

   ```dart
   test('單書覆寫為 null 時，正確退回全域預設（非硬編碼初始值，證明真的有讀 globalPrefs）',
       () {
     final loaded = LoadedPrefs(
       bookPrefs: BookReaderPrefs.empty,
       globalPrefs: const GlobalReaderPrefs(
         pageTurnMode: PageTurnMode.scroll,
         screenOrientation: ScreenOrientationSetting.lock270,
         navZoneMode: NavZoneMode.oneHand,
         navZoneCustomActions: rightFlipZoneTemplate,
         showNavZoneDebugOverlay: true,
       ),
     );
     final resolved = manager.resolve(loaded);

     expect(resolved.pageTurnMode, PageTurnMode.scroll);
     expect(resolved.screenOrientation, ScreenOrientationSetting.lock270);
     expect(resolved.navZoneActions, oneHandZoneTemplate);
     expect(resolved.showNavZoneDebugOverlay, isTrue);
   });

   test('navZoneMode 為 custom 時，navZoneActions 直接採用 navZoneCustomActions',
       () {
     const customActions = [
       ZoneAction.none, ZoneAction.none, ZoneAction.menu,
       ZoneAction.none, ZoneAction.none, ZoneAction.none,
       ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
     ];
     final loaded = LoadedPrefs(
       bookPrefs: BookReaderPrefs.empty,
       globalPrefs: const GlobalReaderPrefs(
         pageTurnMode: PageTurnMode.paginated,
         screenOrientation: ScreenOrientationSetting.auto,
         navZoneMode: NavZoneMode.custom,
         navZoneCustomActions: customActions,
         showNavZoneDebugOverlay: false,
       ),
     );
     final resolved = manager.resolve(loaded);

     expect(resolved.navZoneActions, customActions);
   });
   ```

   同時修正該檔案內第一個測試（「全部欄位皆未覆寫時，回傳的 non-null 欄位皆為既存安全預設值」）與第二個測試（「單書覆寫存在時...」）——這兩個測試使用 `GlobalReaderPrefs.initial()` 建構 `LoadedPrefs`，不需要改動；但需在檔案末尾補上對 `resolved.navZoneActions`／`resolved.showNavZoneDebugOverlay` 的斷言，於「全部欄位皆未覆寫時」測試內新增：

   ```dart
     expect(resolved.navZoneActions, rightFlipZoneTemplate);
     expect(resolved.showNavZoneDebugOverlay, isFalse);
   ```

   （緊接在既有 `expect(resolved.showFooter, isTrue);` 之後。）

- [x] **Step 6：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/toc_bottom_sheet_test.dart
flutter test test/reader/reader_prefs_manager_test.dart
```

Expected：FAIL（`resolve()` 尚未計算 `navZoneActions`/`showNavZoneDebugOverlay`，`ResolvedPreferences(...)` 呼叫缺少 2 個新必填具名參數，編譯錯誤）。

- [x] **Step 7：實作（`resolve()` 串接）**

修改 `app/lib/reader/reader_prefs_manager_impl.dart` 的 `resolve()` 方法，原本結尾：

```dart
      dualPageMode: book.dualPageMode ?? DualPageMode.auto,
      dualPageCoverAlone: book.dualPageCoverAlone ?? true,
      dualPageDirection: book.dualPageDirection ?? DualPageDirection.rtl,
      showHeader: book.showHeader ?? true,
      showFooter: book.showFooter ?? true,
    );
  }
}
```

改為：

```dart
      dualPageMode: book.dualPageMode ?? DualPageMode.auto,
      dualPageCoverAlone: book.dualPageCoverAlone ?? true,
      dualPageDirection: book.dualPageDirection ?? DualPageDirection.rtl,
      showHeader: book.showHeader ?? true,
      showFooter: book.showFooter ?? true,
      navZoneActions:
          resolveZoneActions(global.navZoneMode, global.navZoneCustomActions),
      showNavZoneDebugOverlay: global.showNavZoneDebugOverlay,
    );
  }
}
```

- [x] **Step 8：執行測試確認通過**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/toc_bottom_sheet_test.dart
flutter test test/reader/reader_prefs_manager_test.dart
flutter test test/reader/resolved_preferences_test.dart
flutter test test/reader/global_reader_prefs_test.dart
```

Expected：全數 PASS。

- [x] **Step 9：Commit**

```bash
git add app/lib/reader/resolved_preferences.dart app/lib/reader/reader_prefs_manager_impl.dart app/test/reader/resolved_preferences_test.dart app/test/reader/reader_prefs_manager_test.dart app/test/screens/toc_bottom_sheet_test.dart
git commit -m "feat(epic-7): resolve navZoneActions and showNavZoneDebugOverlay in ResolvedPreferences"
```

---

### Task 6：全域驗證與收尾

**Files:** 無異動（本 Task 僅執行驗證指令，不修改任何檔案）

**Interfaces:**
- Consumes：Task 1-5 全部產出
- Produces：驗收證據（`flutter analyze`/`flutter test` 輸出），供人類判斷本 issue 是否可合併

- [ ] **Step 1：`flutter analyze` 全專案靜態分析**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 2：`flutter test` 執行全部 reader 相關測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/
```

Expected：全數 PASS，含本 issue 新增的 `zone_action_test.dart`／`nav_zone_mode_test.dart`／`zone_hit_test_test.dart`，以及擴充後的 `global_reader_prefs_test.dart`／`reader_prefs_manager_test.dart`／`resolved_preferences_test.dart`。

- [ ] **Step 3：`flutter test` 執行全專案測試（含 Task 5 連帶修正的 `toc_bottom_sheet_test.dart`）**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test
```

Expected：全數 PASS，無既有測試因本 issue 的介面異動而回歸失敗。

- [ ] **Step 4：確認 `git status` 乾淨（無未提交變更）**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：無輸出（Task 1-5 皆已個別 commit）。

（本 Task 不修改任何檔案，無需 commit。）

---

## Self-Review 摘要

- **Spec coverage**：`issues.md` Issue 2 描述的 6 個模組異動（`NavZoneMode`/`ZoneAction`、`resolveZoneActions`、`hitTestZoneIndex`、`isValidCustomZoneConfig`、`GlobalReaderPrefs`、`ReaderPrefsManagerImpl`、`ResolvedPreferences`）與全部單元測試要求，逐一對應 Task 1-5；驗收標準（測試通過、`flutter analyze` 乾淨、不需真實裝置）對應 Task 6。
- **Placeholder scan**：所有 Task 的程式碼區塊皆為完整可執行內容，無 TBD/待補。
- **Type consistency**：`ZoneAction`/`NavZoneMode`/`resolveZoneActions`/`hitTestZoneIndex`/`isValidCustomZoneConfig`/`rightFlipZoneTemplate` 等名稱與型別簽章在 Task 1-5 間保持一致，`GlobalReaderPrefs`/`ResolvedPreferences` 新欄位命名（`navZoneMode`/`navZoneCustomActions`/`showNavZoneDebugOverlay`/`navZoneActions`）與 spec.md 逐字一致。
