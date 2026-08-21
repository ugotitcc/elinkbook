# Epic 26 Issue 8：拆分 `LibraryScreen` God-Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 以逐 Task 執行本計畫。步驟採用 checkbox（`- [ ]`）語法追蹤進度。

**Goal:** 把 `_LibraryScreenState`（現行 1474 行單一 class body，同時裝載書籍清單狀態機、5 個批次操作、拼貼格 footer 非線性字級縮放數學、匯入對話框、導覽樞紐）依關注點拆出 3 個獨立、可脫離 widget 樹直接單元測試的 module（`LibraryBookListController`／`LibraryBatchActions`／`BookGridTileMetrics`），`LibraryScreen` 收斂為呈現＋委派，同時吸收候選 6（5 個批次操作方法骨架重複）為共用 `_runEach()` 骨架，全程維持零行為改變。

**Architecture:** 3 個新檔案各自對應一個關注點：`LibraryBookListController` 為 `ChangeNotifier`（書籍/分類清單載入、排序切換、非同步競態防護），`LibraryBatchActions` 為不可變純資料操作類別（5 個批次操作的差異化「單本書該做什麼」＋共用過濾迴圈骨架，不含 `BuildContext`／對話框／選取模式），`BookGridTileMetrics`（`book_grid_tile_metrics.dart`）為純函式（拼貼格 footer 高度數學，接受 `TextScaler` 而非 `BuildContext`，可用 `test()` 直接驗證不需 `testWidgets()`）。導覽樞紐（`_openBook`／`_openGroupFilteredView`／遠端書庫/設定入口）與選取模式狀態（`_selectedBookIds`／`_inSelectionMode`）維持留在 `_LibraryScreenState`——這是 `LibraryScreen` 收斂後仍保留的「呈現＋委派」角色本身，不是尚未拆完，理由詳見下方「規劃階段查證」。

**Tech Stack:** Flutter／Dart，無新增套件依賴（`LibraryBookListController` 使用 Flutter SDK 內建的 `ChangeNotifier`，`flutter/foundation.dart`）。

**Spec:** `docs/epics/epic-26-architecture-hardening/issues.md` Issue 8；`docs/research/architecture-review-library-remote-screens.md` 候選 2（強度 Strong）與候選 6（強度 Speculative，隨候選 2 一併收斂）。

## 規劃階段查證：module 邊界為何是這 3 個、其餘關注點為何刻意不拆（務必先讀）

Issue 8 原文明講「具體 module 邊界切法、是否需要額外拆出『匯入對話框』『導覽樞紐』為獨立 module，由規劃階段依實際切分後的檔案大小/職責清晰度定案」。逐行核對現行 `app/lib/screens/library_screen.dart`（1474 行，非 Issue 原文引用的舊數字 1504——落差來自 Issue 7 合併時同檔案的 bundle 化重構順手減少了部分行數，已重新核對過現況為準）後，本計畫的邊界決策與理由如下：

1. **匯入對話框（`_pickAndImportFiles`／`_pickAndImportFolder`／`_confirmAutoGroupByFolderName`／`_showImportResultSnackBar`）刻意不獨立成 module。** 這 4 個方法總計約 115 行，全部依賴 `BuildContext`（`showDialog`／`ScaffoldMessenger`）與 `setState`（`_isImporting` 旗標），抽出獨立 module 只會讓呼叫端需要額外傳遞 `BuildContext` 或改用 callback 間接觸發 UI 副作用，複雜度不會真的下降（比照候選 5「刪除測試」結論：純轉送/純 UI 膠水不是藏著複雜度的地方）。維持原樣。
2. **導覽樞紐（`_openBook`／`_openGroupFilteredView`／Google Drive／OneDrive／遠端書庫／設定入口）刻意不獨立成 module。** 這些方法的核心工作就是「用 `Navigator.of(context)` 建構下一個畫面」，`BuildContext` 依賴無法剝離；这正是 Issue 8 Solution 原文所說「`LibraryScreen` 收斂為呈現＋委派」中「委派」的具體體現——委派本身留在 `LibraryScreen`，不是還沒拆完的殘留。
3. **選取模式狀態機（`_selectedBookIds`／`_inSelectionMode`／`_enterSelectionMode`／`_exitSelectionMode`／`_toggleBookSelection`／`_onBookTap`／`_onBookLongPress`）刻意不獨立成 module。** 這組狀態直接驅動 `AppBar` 切換（`_buildSelectionAppBar()` vs `_buildNormalAppBar()`）與拼貼格/書籍格的勾選圖示渲染，是典型的「畫面呈現狀態」而非「業務資料狀態機」，且 Issue 8 Solution 原文列出的 3 個抽取目標（`LibraryBookListController`／`LibraryBatchActions`／`BookGridTileMetrics`）本就不包含它。`LibraryBatchActions` 會需要 `selectedIds`（由呼叫端傳入，不由它自己維護）。
4. **拼貼格/書籍格 4 個呈現 widget（`_GroupTile`／`_GroupGridTile`／`_GroupListTile`／`_BookGridTile`／`_BookListTile`）與 `_buildBookList()`／`_buildGroupTiles()`／`_buildNormalAppBar()`／`_buildSelectionAppBar()`／`build()` 刻意不搬移。** 這些是 `LibraryScreen` 收斂後應該保留的「呈現」本體，Issue 8 驗收標準也只要求「書籍清單狀態機／批次操作／版面數學不再與呈現邏輯混雜」，不要求把呈現邏輯本身搬到別的檔案；估算完成 Task 1-6 後 `_LibraryScreenState` class body 仍會保留約 700-800 行呈現/委派邏輯，不強行壓到特定行數門檻（Issue 8 驗收標準原文亦明講「不要求特定行數門檻」）。
5. **`LibraryPreferences`（檢視模式／排序偏好持久化）的注入方式維持現狀，`LibraryBookListController` 自行 `LibraryPreferences()` 建構、不透過建構子注入。** 現行 `_LibraryScreenState` 本身也是直接 `final _preferences = LibraryPreferences();`（無注入），`LibraryPreferences` 本身完全無狀態（每個方法各自呼叫 `SharedPreferences.getInstance()`，見 `library_preferences.dart` class doc），`LibraryScreen`（保留 `_viewMode`／`_toggleViewMode()`）與新控制器（`sortBy` 持久化）可以各自持有獨立實例而不互相干擾，維持 ADR 0007 精神、不引入 service locator，也不擴大這次重構的變更面。
6. **`_viewMode`／`_toggleViewMode()` 刻意留在 `_LibraryScreenState`，不併入 `LibraryBookListController`。** 候選 2 原文「書籍載入／排序／分類篩選狀態機」三個詞明確不含檢視模式（grid/list 切換是呈現偏好，與書籍內容/資料無關），且 `_viewMode` 只用於 `build()`/`_buildBookList()` 內部的 widget 選擇分支，不參與任何 repository 查詢條件。
7. **`_maybeOpenLastBookOnLaunch()` 刻意留在 `_LibraryScreenState`，不搬進 `LibraryBookListController`。** 這個方法雖然會呼叫 `widget.repository.listBooks(sortBy: LibrarySortBy.lastRead)`，但那是一次性、與控制器自身 `books`/`sortBy` 狀態完全無關的獨立查詢（查完直接呼叫 `_openBook()` 做導覽，不寫回控制器任何欄位），本質上是「啟動流程」而非「書籍清單狀態機」的一部分，且需要 `Navigator`，維持原樣不動、無需任何改寫。
8. **新增 `_LibraryScreenState.dispose()`（現行完全沒有 `dispose()` override）——這是本計畫唯一新增的、非搬移性質的程式碼。** `LibraryBookListController` 是 `ChangeNotifier`，依 Flutter 慣例必須在 `State.dispose()` 呼叫其 `dispose()`，否則會洩漏 listener／在極端情況下于背景任務完成時嘗試 `notifyListeners()` 觸發已無用武之地的 rebuild。這不是「新功能」，是引入 `ChangeNotifier` 這個實作手法後的必要配套，維持「使用者可觀察行為零改變」原則（`dispose()` 本身不影響任何 UI 行為，只影響物件生命週期正確性）。
9. **`initState()` 內「載入 `_viewMode`」與「載入 `_sortBy`」原本合併成同一次 `setState()`，拆分後會變成兩次獨立的重新渲染（`_LibraryScreenState` 一次 `setState()` 更新 `_viewMode`、`LibraryBookListController` 一次 `notifyListeners()` 更新 `sortBy`）。** 這是唯一一個「技術上多了一次 rebuild」的微幅偏差，經核對不會造成任何使用者可觀察的行為差異——`build()` 在 `_bookListController.books == null` 時一律顯示 `CircularProgressIndicator`（載入中畫面），兩次 rebuild 都發生在使用者看到的仍是同一個載入中畫面的期間，不影響最終呈現結果或計時行為。整體非同步呼叫順序（先讀 `viewMode`、再讀 `sortBy`、再平行載入分類與書籍、最後判斷是否自動開書）維持與原本完全一致的先後次序，只是把單一 `setState()` 拆成兩個獨立來源各自觸發一次，比照 Issue 6/7 慣例在此明確標記、不視為隱藏偏差。
10. **`LibraryBookListController.groupFilter` 從原本可變的 `String? _groupFilter` State 欄位改為建構子注入的 `final` 欄位。** 逐行核對現行程式碼，`_groupFilter` 只在 `initState()` 賦值一次（`_groupFilter = widget.groupFilter;`），此後全檔案沒有任何地方再次寫入，`_loadBooks()` 內比對 `_groupFilter != requestedGroupFilter` 的競態防護因此在實務上恆為 `false`（不曾真的觸發）——改為 `final` 只是把這個既有不變量用型別系統明確表達出來，不改變任何執行期行為，比對邏輯本身原樣保留（見 Task 3 `loadBooks()` 實作），不做「順手清理死程式碼」式的額外簡化。

**結論：** 3 個抽取模組（`LibraryBookListController`／`LibraryBatchActions`／`BookGridTileMetrics`）＋ 1 個必要新增（`dispose()`），其餘關注點（匯入對話框／導覽樞紐／選取模式／呈現 widget／`_viewMode`／`_maybeOpenLastBookOnLaunch`）依上述理由維持原樣，符合 Issue 8 驗收標準「不要求特定行數門檻，但應可觀察到書籍清單狀態機／批次操作／版面數學不再與呈現邏輯混雜在同一個 class body」。

## Global Constraints

- 程式碼註解／變數說明使用中文，遵循既有檔案風格；搬移既有程式碼時，原本解釋「為什麼」的歷史註解（真機回報、審查修正、既往事故）必須原樣隨程式碼一起搬到新檔案，不可在搬移過程中遺失（比照 Issue 7 審查 Minor #1 教訓）。
- 零行為改變：本計畫是純內部重構，不新增、不移除、不調整任何使用者可觀察行為，包含既有的「已知既有行為」（例如 `_moveSelectedBooksToGroup()` 缺少 `!mounted` 檢查這個既有缺口，本計畫原樣保留、不順手修正）。
- 維持 ADR 0007「平行建構子參數、不用 service locator」的組裝哲學：`LibraryBookListController`／`LibraryBatchActions` 皆透過建構子接收 `repository`，不是任何形式的全域單例或 service locator。
- `LibraryBatchActions` 為不可變（`const` 建構子）、無內部可變狀態；`LibraryBookListController` 為 `ChangeNotifier`，狀態變動一律透過 `notifyListeners()` 對外可觀察，不直接暴露可變欄位給外部任意寫入以外的方式修改（欄位本身仍是公開可讀寫的簡單欄位，比照 Flutter 常見輕量控制器慣例，不引入額外的 getter/setter 樣板）。
- Commit message 慣例：`refactor(epic-26): Issue 8 Task N——<描述>`。
- 每個 Task 完成後專案須維持可編譯；`library_screen.dart` 在 Task 3-6 之間會處於「部分關注點已抽出、部分仍是原內嵌邏輯」的過渡狀態，這是預期、允許的中繼狀態（比照 Issue 6/7 既有先例）。
- `flutter analyze` 涵蓋 `app/integration_test/`——本計畫不涉及 `ReaderScreen`／`PdfReaderView`，`integration_test/` 底下現行測試檔案預期不受影響，仍需確保能編譯通過。

---

### Task 1：建立 `BookGridTileMetrics`（拼貼格 footer 高度數學，最小風險，優先驗證抽取流程）

**Files:**
- Create: `app/lib/screens/book_grid_tile_metrics.dart`
- Test: `app/test/screens/book_grid_tile_metrics_test.dart`

**Interfaces:**
- Produces：
  - `const kGridTileFooterHeightAtScale1 = 34.0;`
  - `const kGridTileFooterTitleFontSize = 12.0;`
  - `const kGridTileFooterProgressFontSize = 10.0;`
  - `const kGridTileFooterLineHeightFactor = kGridTileFooterHeightAtScale1 / (kGridTileFooterTitleFontSize + kGridTileFooterProgressFontSize);`
  - `double gridTileFooterHeight(TextScaler scaler)`
  - Task 2 會 import 並在 `library_screen.dart` 的 `_GroupGridTile`／`_BookGridTile` 兩處呼叫點改用這個函式（改傳入 `MediaQuery.textScalerOf(context)` 而非 `context` 本身）。

- [ ] **Step 1：寫失敗測試，驗證線性與非線性 `TextScaler` 下的高度計算**

```dart
// app/test/screens/book_grid_tile_metrics_test.dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/book_grid_tile_metrics.dart';

void main() {
  test('系統字級 1.0 倍（TextScaler.noScaling）時，回傳基準值 34.0', () {
    expect(gridTileFooterHeight(TextScaler.noScaling), 34.0);
  });

  test('線性縮放（TextScaler.linear）時，回傳依比例放大的高度', () {
    final result = gridTileFooterHeight(const TextScaler.linear(1.5));
    expect(result, closeTo(34.0 * 1.5, 0.001));
  });

  test(
      '非線性縮放曲線時，對書名／進度兩個字級分別呼叫 scale() 後相加，'
      '不等於把基準值 34.0 整體丟進 scale()（/diagnose 第七輪真機回報重現方式）',
      () {
    const scaler = _NonLinearTextScaler(1.5);
    final result = gridTileFooterHeight(scaler);
    final expected = (scaler.scale(kGridTileFooterTitleFontSize) +
            scaler.scale(kGridTileFooterProgressFontSize)) *
        kGridTileFooterLineHeightFactor;
    expect(result, expected);
    expect(result, isNot(closeTo(scaler.scale(34.0), 0.001)));
  });
}

/// 刻意「非線性」的測試用 TextScaler，比照
/// `test/screens/library_screen_test.dart` 既有的 `_NonLinearTextScaler`
/// 同一種設計（凹函式：`scale(A) + scale(B)` 恆大於 `scale(A + B)`），
/// 獨立複製一份而非共用同一個類別——這是純函式的獨立單元測試，刻意不
/// 依賴 `library_screen_test.dart`（widget test）內的測試替身，兩者測試
/// 對象不同（純函式 vs widget 渲染）。
class _NonLinearTextScaler extends TextScaler {
  const _NonLinearTextScaler(this.textScaleFactor);

  @override
  final double textScaleFactor;

  @override
  double scale(double fontSize) {
    if (textScaleFactor == 1.0) return fontSize;
    return fontSize + (textScaleFactor - 1.0) * 6.0 * fontSize.sqrt();
  }

  @override
  bool operator ==(Object other) =>
      other is _NonLinearTextScaler && other.textScaleFactor == textScaleFactor;

  @override
  int get hashCode => textScaleFactor.hashCode;
}
```

`fontSize.sqrt()` 並非 `double` 內建方法，需改用 `dart:math` 的 `sqrt()`；請在檔案頂端補上 `import 'dart:math' show sqrt;`，並把 `fontSize.sqrt()` 改為 `sqrt(fontSize)`。

- [ ] **Step 2：執行測試確認失敗（型別尚未存在）**

執行：`cd app && flutter test test/screens/book_grid_tile_metrics_test.dart`
預期：`FAIL`，錯誤訊息為找不到 `package:elinkbook/screens/book_grid_tile_metrics.dart`。

- [ ] **Step 3：實作 `BookGridTileMetrics`（原樣搬移 `library_screen.dart:1151-1190` 的常數/函式與其歷史註解）**

```dart
// app/lib/screens/book_grid_tile_metrics.dart
import 'package:flutter/painting.dart' show TextScaler;

/// 分類拼貼格（`_GroupGridTile`）與書籍格（`_BookGridTile`）共用的文字說明區
/// 固定高度基準值（epic-18-reader-device-qa Issue 42，epic-26-architecture-
/// hardening Issue 8 從 `library_screen.dart` 抽出）：兩者原本文字說明區
/// 行數不同（前者 1 行、後者 2 行），導致封面 Expanded 吃到的剩餘高度不同，
/// 橫屏下兩者同列時封面底部邊界因此錯開（真機回報，已用 widget test 精確
/// 量測相差 14px）。固定高度取書籍格 2 行文字（書名＋進度）所需的自然高度
/// 為準，分類拼貼格的 1 行文字說明包進同樣高度的容器（會留一點點底部空白，
/// 換取跨 cell 對齊），是本修法必然的取捨。
///
/// 【程式碼審查修正】這是基準值（1.0 倍系統字級下的高度），實際使用時一律
/// 要經過 [gridTileFooterHeight] 換算成當下系統字級對應的高度，不可直接
/// 當作固定像素值使用——否則使用者放大系統字級時，書籍格的 2 行文字會被
/// 這個寫死的高度截斷，觸發 `RenderFlex` 溢位（審查發現：修法前文字說明區
/// 是自然高度、不會有這個風險，此為修法本身新引入、需要一併防護的技術債）。
const kGridTileFooterHeightAtScale1 = 34.0;
const kGridTileFooterTitleFontSize = 12.0;
const kGridTileFooterProgressFontSize = 10.0;

/// 【/diagnose 第七輪：Air Reader C 真機回報】上面 34.0 這個基準值原本是
/// 直接整體丟進 `textScaler.scale(34.0)`，但 `_BookGridTile` 實際渲染的
/// 兩行文字（書名 12px＋進度 10px）是各自獨立呼叫 `scale(12)`／
/// `scale(10)`——兩者只有在縮放曲線是「線性」（`scale(x) = x * 固定倍率`）
/// 時才恆等。真機使用者手動調大系統字級後，Android 會套用「非線性字級
/// 縮放」（避免超大字級把版面撐爆，對數值較大的輸入相對縮放得較保守），
/// `scale(34)` 因此比 `scale(12) + scale(10)` 縮放得少，容器高度不夠、
/// 觸發 RenderFlex 溢位。`flutter_test` 套件的 `TestPlatformDispatcher.
/// scaleFontSize` 寫死是線性乘法，先前的 widget test（`TextScaler.
/// linear(1.5)`）測不出這個落差。修法：改成對書名／進度兩個實際字級分別
/// 呼叫 `scale()` 後再相加，比對真正 Text 元件的縮放方式，
/// [kGridTileFooterLineHeightFactor] 則是由 34.0 這個既有校準值反推出來、
/// 與縮放曲線無關的固定行高比例常數，確保系統字級 1.0 倍時仍與原本行為
/// 完全一致。
const kGridTileFooterLineHeightFactor = kGridTileFooterHeightAtScale1 /
    (kGridTileFooterTitleFontSize + kGridTileFooterProgressFontSize);

/// 依 [scaler]（呼叫端傳入 `MediaQuery.textScalerOf(context)`）換算文字
/// 說明區的實際像素高度（epic-26-architecture-hardening Issue 8）。刻意
/// 接受 [TextScaler] 而非 `BuildContext`——讓這段縮放數學可以完全脫離
/// widget 樹，用純 `test()` 直接驗證（見 `book_grid_tile_metrics_test.dart`），
/// 不需要 `testWidgets()`。
double gridTileFooterHeight(TextScaler scaler) {
  return (scaler.scale(kGridTileFooterTitleFontSize) +
          scaler.scale(kGridTileFooterProgressFontSize)) *
      kGridTileFooterLineHeightFactor;
}
```

- [ ] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/screens/book_grid_tile_metrics_test.dart`
預期：`PASS`

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/book_grid_tile_metrics.dart app/test/screens/book_grid_tile_metrics_test.dart
git commit -m "refactor(epic-26): Issue 8 Task 1——新增 BookGridTileMetrics 拼貼格 footer 高度純函式"
```

---

### Task 2：`LibraryScreen` 改用 `gridTileFooterHeight(TextScaler)`，刪除原內嵌常數/函式

**Files:**
- Modify: `app/lib/screens/library_screen.dart`

**Interfaces:**
- Consumes：Task 1 的 `kGridTileFooterHeightAtScale1`／`kGridTileFooterTitleFontSize`／`kGridTileFooterProgressFontSize`／`kGridTileFooterLineHeightFactor`／`gridTileFooterHeight(TextScaler)`。

- [ ] **Step 1：刪除 `library_screen.dart:1151-1190` 整段常數與函式（連同其歷史註解，已完整搬到 Task 1 的新檔案，不留副本）**

刪除以下整段（原檔案 `_GroupTile` class 定義之後、`_GroupGridTile` class 定義之前）：

```dart
/// 分類拼貼格（_GroupGridTile）與書籍格（_BookGridTile）共用的文字說明區
/// 固定高度基準值（epic-18-reader-device-qa Issue 42）：...
/// （以下省略，完整內容見 Task 1 Step 3 已搬移至 book_grid_tile_metrics.dart 的版本）
const _kGridTileFooterHeightAtScale1 = 34.0;
const _kGridTileFooterTitleFontSize = 12.0;
const _kGridTileFooterProgressFontSize = 10.0;

/// 【/diagnose 第七輪：Air Reader C 真機回報】...
const _kGridTileFooterLineHeightFactor = _kGridTileFooterHeightAtScale1 /
    (_kGridTileFooterTitleFontSize + _kGridTileFooterProgressFontSize);

double _gridTileFooterHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return (scaler.scale(_kGridTileFooterTitleFontSize) +
          scaler.scale(_kGridTileFooterProgressFontSize)) *
      _kGridTileFooterLineHeightFactor;
}
```

- [ ] **Step 2：新增 import**

在檔案頂端 import 區塊新增（置於 `import 'library_screen_dependencies.dart';` 之後的合理位置）：

```dart
import 'book_grid_tile_metrics.dart';
```

- [ ] **Step 3：`_GroupGridTile.build()` 呼叫點改寫**

原本：

```dart
          const SizedBox(height: 4),
          SizedBox(
            height: _gridTileFooterHeight(context),
            child: Text(
              '${tile.name} (${tile.totalCount})',
```

改為：

```dart
          const SizedBox(height: 4),
          SizedBox(
            height: gridTileFooterHeight(MediaQuery.textScalerOf(context)),
            child: Text(
              '${tile.name} (${tile.totalCount})',
```

- [ ] **Step 4：`_BookGridTile.build()` 呼叫點改寫**

原本：

```dart
          const SizedBox(height: 4),
          SizedBox(
            height: _gridTileFooterHeight(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  book.title,
```

改為：

```dart
          const SizedBox(height: 4),
          SizedBox(
            height: gridTileFooterHeight(MediaQuery.textScalerOf(context)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  book.title,
```

- [ ] **Step 5：執行測試確認既有相關測試通過**

執行：`cd app && flutter test test/screens/library_screen_test.dart`
預期：`PASS`（全部既有案例，含系統字級放大/非線性縮放相關的兩項測試，因公式完全等價、只是換了函式簽章，渲染結果應與修改前逐像素一致）。

- [ ] **Step 6：執行 `flutter analyze` 確認無殘留未使用宣告**

執行：`cd app && flutter analyze app/lib/screens/library_screen.dart`
預期：`No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/library_screen.dart
git commit -m "refactor(epic-26): Issue 8 Task 2——LibraryScreen 改用 gridTileFooterHeight 純函式"
```

---

### Task 3：建立 `LibraryBookListController`（書籍清單狀態機，`ChangeNotifier`）

**Files:**
- Create: `app/lib/screens/library_book_list_controller.dart`
- Test: `app/test/screens/library_book_list_controller_test.dart`

**Interfaces:**
- Produces：
  - `class LibraryBookListController extends ChangeNotifier { LibraryBookListController({required LibraryRepository repository, String? groupFilter}); List<Book>? books; List<BookGroup> groups; LibrarySortBy sortBy; Future<void> initialLoad(); Future<void> loadGroups(); Future<void> loadBooks(); Future<void> changeSortBy(LibrarySortBy newSortBy); }`
  - Task 4 會 import 並在 `LibraryScreen` 中以 `late final LibraryBookListController _bookListController;` 持有一個實例，於 `initState()` 建立、`dispose()` 釋放。

- [ ] **Step 1：寫失敗測試，驗證載入、失敗降級、排序切換、dispose 後不再通知**

```dart
// app/test/screens/library_book_list_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/library_book_list_controller.dart';

import '../support/fake_library_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'initialLoad() 依序載入持久化排序偏好、分類清單與書籍清單，並依載入結果排序',
      () async {
    SharedPreferences.setMockInitialValues({'library_sort_by': 'title'});
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', title: 'B'),
      _book(id: '2', title: 'A'),
    ]);
    final controller = LibraryBookListController(repository: repository);
    addTearDown(controller.dispose);

    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    await controller.initialLoad();

    expect(controller.sortBy, LibrarySortBy.title);
    expect(controller.books?.map((b) => b.id).toList(), ['2', '1']);
    expect(controller.groups, isNotEmpty);
    expect(notifyCount, greaterThan(0));
  });

  test('loadGroups() 成功時更新 groups', () async {
    final repository = FakeLibraryRepository(
      initialBooks: [_book(id: '1', groupName: '奇幻')],
    );
    final controller = LibraryBookListController(repository: repository);
    addTearDown(controller.dispose);

    await controller.loadGroups();

    expect(controller.groups.map((g) => g.name), contains('奇幻'));
  });

  test('loadGroups() 失敗時保留先前已載入的群組清單，不拋出例外', () async {
    final repository = FakeLibraryRepository(
      initialBooks: [_book(id: '1', groupName: '奇幻')],
    );
    final controller = LibraryBookListController(repository: repository);
    addTearDown(controller.dispose);
    await controller.loadGroups();
    final before = controller.groups;

    final throwingController = LibraryBookListController(
      repository: _ThrowingListGroupsRepository(),
    )..groups = before;
    addTearDown(throwingController.dispose);

    await throwingController.loadGroups();

    expect(throwingController.groups, same(before));
  });

  test('loadBooks() 成功時依目前 sortBy／groupFilter 更新 books', () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', groupName: '奇幻'),
      _book(id: '2', groupName: '未分類'),
    ]);
    final controller = LibraryBookListController(
      repository: repository,
      groupFilter: '奇幻',
    );
    addTearDown(controller.dispose);

    await controller.loadBooks();

    expect(controller.books?.map((b) => b.id).toList(), ['1']);
  });

  test('loadBooks() 失敗時降級為空清單，不拋出例外', () async {
    final repository = FakeLibraryRepository(throwOnListBooks: true);
    final controller = LibraryBookListController(repository: repository);
    addTearDown(controller.dispose);

    await controller.loadBooks();

    expect(controller.books, isEmpty);
  });

  test('changeSortBy() 更新 sortBy、持久化選擇、並重新載入書籍清單', () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', title: 'B'),
      _book(id: '2', title: 'A'),
    ]);
    final controller = LibraryBookListController(repository: repository);
    addTearDown(controller.dispose);

    await controller.changeSortBy(LibrarySortBy.title);

    expect(controller.sortBy, LibrarySortBy.title);
    expect(controller.books?.map((b) => b.id).toList(), ['2', '1']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library_sort_by'), 'title');
  });

  test('dispose() 後呼叫 loadBooks()／loadGroups() 不再觸發 notifyListeners()、不拋出例外',
      () async {
    final repository = FakeLibraryRepository();
    final controller = LibraryBookListController(repository: repository);
    controller.dispose();

    await controller.loadBooks();
    await controller.loadGroups();
  });
}

Book _book({
  required String id,
  String title = '測試書',
  String groupName = BookGroup.uncategorized,
}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    author: null,
    format: BookFileFormat.epub,
    filePath: 'content://example/$id.epub',
    source: BookSource.local,
    coverPath: null,
    groupName: groupName,
    createTime: now,
    lastReadTime: now,
  );
}

/// 供「loadGroups() 失敗時保留先前清單」測試使用，只覆寫 listGroups() 一個
/// 方法使其拋出例外，其餘行為原樣繼承 FakeLibraryRepository（比照
/// `test/support/fake_remote_server_repository.dart` 系列既有「刻意可變
/// 錯誤模擬旗標」慣例，但此處只有單一測試需要、不下放到共用 fake 檔案，
/// 改用區域子類別)。
class _ThrowingListGroupsRepository extends FakeLibraryRepository {
  @override
  Future<List<BookGroup>> listGroups() async {
    throw Exception('模擬資料庫錯誤');
  }
}
```

- [ ] **Step 2：執行測試確認失敗（型別尚未存在）**

執行：`cd app && flutter test test/screens/library_book_list_controller_test.dart`
預期：`FAIL`，錯誤訊息為找不到 `package:elinkbook/screens/library_book_list_controller.dart`。

- [ ] **Step 3：實作 `LibraryBookListController`**

```dart
// app/lib/screens/library_book_list_controller.dart
import 'package:flutter/foundation.dart';

import '../library/library_preferences.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';

/// 收斂 `LibraryScreen` 的書籍清單狀態機（epic-26-architecture-hardening
/// Issue 8，候選 2）：書籍載入／分類清單載入／排序切換與其非同步競態防護
/// （避免較晚回應但較早發出的查詢結果覆蓋畫面），從 `_LibraryScreenState`
/// 抽出成獨立、可脫離 widget 樹直接單元測試的 [ChangeNotifier]。
///
/// `LibraryScreen` 在 `initState()` 建立本控制器並 `addListener()` 觸發
/// `setState()`，在 `dispose()` 時呼叫 [dispose]；本類別不需要
/// `if (!mounted) return;` 這類 guard——改用內部 [_disposed] 旗標達成相同
/// 效果（`notifyListeners()` 在 dispose 後呼叫會拋出例外，見
/// `ChangeNotifier` 官方文件）。
///
/// [groupFilter] 對應 `LibraryScreen.groupFilter`，於建構時決定、之後不再
/// 變動（比照原本 `_groupFilter` 欄位「只在 initState 賦值一次、此後從未
/// 再寫入」的既有行為，改為 `final` 更精確表達這個不變量，見
/// `plans/plan-issue-8.md`「規劃階段查證」第 10 點）。
class LibraryBookListController extends ChangeNotifier {
  LibraryBookListController({
    required this.repository,
    this.groupFilter,
  });

  final LibraryRepository repository;
  final String? groupFilter;
  final _preferences = LibraryPreferences();

  bool _disposed = false;

  List<Book>? books;
  List<BookGroup> groups = const [];
  LibrarySortBy sortBy = LibrarySortBy.lastRead;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 啟動時的初始載入：先讀取持久化的排序偏好，再平行載入分類清單與書籍
  /// 清單。對應原 `_LibraryScreenState._initialize()` 中「讀 `_sortBy`」與
  /// `Future.wait([_loadGroups(), _loadBooks()])` 兩段（`_viewMode` 讀取
  /// 不屬於書籍清單狀態機，留在 `_LibraryScreenState` 自行處理，見
  /// `plans/plan-issue-8.md`「規劃階段查證」第 6、9 點）。
  Future<void> initialLoad() async {
    sortBy = await _preferences.loadSortBy();
    if (_disposed) return;
    notifyListeners();
    await Future.wait([loadGroups(), loadBooks()]);
  }

  Future<void> loadGroups() async {
    try {
      final loaded = await repository.listGroups();
      if (_disposed) return;
      groups = loaded;
      notifyListeners();
    } catch (_) {
      // 暫時性錯誤時保留先前已載入的群組清單，避免因為單次讀取失敗就讓
      // 畫面的分類 tab 列與目前的篩選狀態不一致（見 Issue 7 審查）。若是
      // 第一次載入就失敗，groups 會維持初始的空清單（連「未分類」都不
      // 顯示）——這是「沒有最後已知正確狀態可保留」下的必然結果，安全但
      // 不完美，之後重新整理即可恢復。
    }
  }

  Future<void> loadBooks() async {
    // 擷取呼叫當下的排序條件；若呼叫端在這次非同步查詢完成前又切換了
    // 排序，較晚回應但較早發出的查詢結果會對應到舊條件，此時不應覆蓋
    // 畫面（避免顯示內容與目前選定的條件不一致）。`groupFilter` 為
    // `final`，理論上不會變動，仍保留比對以維持與原本邏輯逐行對應（見
    // `plans/plan-issue-8.md`「規劃階段查證」第 10 點）。
    final requestedSortBy = sortBy;
    final requestedGroupFilter = groupFilter;
    try {
      final loaded = await repository.listBooks(
        sortBy: requestedSortBy,
        groupFilter: requestedGroupFilter,
      );
      if (_disposed) return;
      if (sortBy != requestedSortBy || groupFilter != requestedGroupFilter) {
        return;
      }
      books = loaded;
      notifyListeners();
    } catch (_) {
      // 如果載入失敗，把它當作空列表，顯示既有的空狀態 UI
      if (_disposed) return;
      if (sortBy != requestedSortBy || groupFilter != requestedGroupFilter) {
        return;
      }
      books = [];
      notifyListeners();
    }
  }

  /// 切換排序方式：更新狀態並通知、持久化使用者選擇，再重新載入書籍清單
  /// （對應原 `_LibraryScreenState._changeSortBy()`）。
  Future<void> changeSortBy(LibrarySortBy newSortBy) async {
    sortBy = newSortBy;
    if (_disposed) return;
    notifyListeners();
    await _preferences.saveSortBy(newSortBy);
    await loadBooks();
  }
}
```

- [ ] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/screens/library_book_list_controller_test.dart`
預期：`PASS`

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/library_book_list_controller.dart app/test/screens/library_book_list_controller_test.dart
git commit -m "refactor(epic-26): Issue 8 Task 3——新增 LibraryBookListController"
```

---

### Task 4：`LibraryScreen` 改用 `LibraryBookListController`

**Files:**
- Modify: `app/lib/screens/library_screen.dart`

**Interfaces:**
- Consumes：Task 3 的 `LibraryBookListController`。

- [ ] **Step 1：欄位宣告——移除 `_books`／`_groups`／`_sortBy`／`_groupFilter`，新增 `_bookListController`**

修改 `app/lib/screens/library_screen.dart`（`_LibraryScreenState` 欄位區），原本：

```dart
  final _preferences = LibraryPreferences();

  List<Book>? _books;
  List<BookGroup> _groups = const [];
  LibraryViewMode _viewMode = LibraryViewMode.grid;
  LibrarySortBy _sortBy = LibrarySortBy.lastRead;
  String? _groupFilter;
  Set<String>? _selectedBookIds;
```

改為：

```dart
  final _preferences = LibraryPreferences();
  late final LibraryBookListController _bookListController;

  LibraryViewMode _viewMode = LibraryViewMode.grid;
  Set<String>? _selectedBookIds;
```

並在檔案頂端 import 區塊新增（置於 `import 'book_grid_tile_metrics.dart';` 之後）：

```dart
import 'library_book_list_controller.dart';
```

- [ ] **Step 2：`initState()`／新增 `dispose()`／新增 `_onBookListChanged()`**

原本：

```dart
  @override
  void initState() {
    super.initState();
    _groupFilter = widget.groupFilter;
    _initialize();
  }
```

改為：

```dart
  @override
  void initState() {
    super.initState();
    _bookListController = LibraryBookListController(
      repository: widget.repository,
      groupFilter: widget.groupFilter,
    )..addListener(_onBookListChanged);
    _initialize();
  }

  void _onBookListChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _bookListController.dispose();
    super.dispose();
  }
```

- [ ] **Step 3：`_initialize()` 改寫**

原本：

```dart
  Future<void> _initialize() async {
    final viewMode = await _preferences.loadViewMode();
    final sortBy = await _preferences.loadSortBy();
    if (!mounted) return;
    setState(() {
      _viewMode = viewMode;
      _sortBy = sortBy;
    });
    await Future.wait([_loadGroups(), _loadBooks()]);
    await _maybeOpenLastBookOnLaunch();
  }
```

改為：

```dart
  Future<void> _initialize() async {
    final viewMode = await _preferences.loadViewMode();
    if (!mounted) return;
    setState(() => _viewMode = viewMode);
    await _bookListController.initialLoad();
    await _maybeOpenLastBookOnLaunch();
  }
```

（`_maybeOpenLastBookOnLaunch()` 本身不需要任何修改，維持原樣——見 Global Constraints 與「規劃階段查證」第 7 點。）

- [ ] **Step 4：刪除 `_loadGroups()` 與 `_loadBooks()`（已移至 Task 3 控制器）**

刪除整個 `_loadGroups()` 方法（原 `library_screen.dart:140-152`）與整個 `_loadBooks()` 方法（原 `library_screen.dart:154-178`）。

- [ ] **Step 5：`_pickAndImportFiles()` 呼叫點改寫**

原本：

```dart
      final result =
          await widget.importService.importFiles(uris, displayNames: displayNames);
      await _loadBooks();
      _showImportResultSnackBar(result);
```

改為：

```dart
      final result =
          await widget.importService.importFiles(uris, displayNames: displayNames);
      await _bookListController.loadBooks();
      _showImportResultSnackBar(result);
```

- [ ] **Step 6：`_pickAndImportFolder()` 呼叫點改寫**

原本：

```dart
      final result = await widget.importService.importFolder(
        folderUri,
        autoGroupByFolderName: autoGroup,
      );
      await _loadGroups();
      await _loadBooks();
      _showImportResultSnackBar(result);
```

改為：

```dart
      final result = await widget.importService.importFolder(
        folderUri,
        autoGroupByFolderName: autoGroup,
      );
      await _bookListController.loadGroups();
      await _bookListController.loadBooks();
      _showImportResultSnackBar(result);
```

- [ ] **Step 7：`_openGoogleDriveBrowser()` 與 `_openOneDriveBrowser()` 的 `.then()` 回呼改寫**

`_openGoogleDriveBrowser()` 原本：

```dart
        .then((_) {
      // 【審查 review-plan-issue-3.md Minor #2 採納】比照
      // `_openGroupFilteredView` 既有慣例，一併重新載入分類——
      // `importFiles(folderName: ...)` 內部會 `upsertGroup()`，回到書架
      // 時分類清單與書籍清單應保持同步一致。
      if (mounted) {
        _loadGroups();
        _loadBooks();
      }
    });
  }

  void _openOneDriveBrowser(CloudStorageClient client) {
```

改為：

```dart
        .then((_) {
      // 【審查 review-plan-issue-3.md Minor #2 採納】比照
      // `_openGroupFilteredView` 既有慣例，一併重新載入分類——
      // `importFiles(folderName: ...)` 內部會 `upsertGroup()`，回到書架
      // 時分類清單與書籍清單應保持同步一致。
      if (mounted) {
        _bookListController.loadGroups();
        _bookListController.loadBooks();
      }
    });
  }

  void _openOneDriveBrowser(CloudStorageClient client) {
```

`_openOneDriveBrowser()` 內同一形狀的 `.then()` 區塊（無上述審查註解，其餘完全相同），原本：

```dart
        .then((_) {
      if (mounted) {
        _loadGroups();
        _loadBooks();
      }
    });
  }
```

改為：

```dart
        .then((_) {
      if (mounted) {
        _bookListController.loadGroups();
        _bookListController.loadBooks();
      }
    });
  }
```

- [ ] **Step 8：刪除 `_changeSortBy()`（已移至 Task 3 控制器 `changeSortBy()`）**

刪除整個方法（原 `library_screen.dart:336-340`）：

```dart
  Future<void> _changeSortBy(LibrarySortBy sortBy) async {
    setState(() => _sortBy = sortBy);
    await _preferences.saveSortBy(sortBy);
    await _loadBooks();
  }
```

- [ ] **Step 9：5 個批次操作方法內的 `_books`／`_groups`／`_loadBooks()` 讀取點改寫（本 Task 只換讀取來源，迴圈邏輯本身維持不動，留待 Task 6 抽出 `LibraryBatchActions`）**

`_moveSelectedBooksToGroup()` 原本：

```dart
  Future<void> _moveSelectedBooksToGroup() async {
    final selectedIds = _selectedBookIds;
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final destination = await showDialog<String>(
      context: context,
      builder: (context) => LibraryMoveToGroupDialog(groups: _groups),
    );
    if (destination == null) return;
    // 立即退出選取模式，而非等到逐筆寫入資料庫的迴圈結束後才退出：這個迴圈
    // 期間「移動到分類」按鈕仍會顯示在選取模式的 App Bar 上，若不提早退出，
    // 使用者理論上可以在寫入尚未完成時再次點擊，重複觸發本方法。
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      await widget.repository.updateBook(book.copyWith(groupName: destination));
    }
    await _loadBooks();
  }
```

改為：

```dart
  Future<void> _moveSelectedBooksToGroup() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final destination = await showDialog<String>(
      context: context,
      builder: (context) =>
          LibraryMoveToGroupDialog(groups: _bookListController.groups),
    );
    if (destination == null) return;
    // 立即退出選取模式，而非等到逐筆寫入資料庫的迴圈結束後才退出：這個迴圈
    // 期間「移動到分類」按鈕仍會顯示在選取模式的 App Bar 上，若不提早退出，
    // 使用者理論上可以在寫入尚未完成時再次點擊，重複觸發本方法。
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      await widget.repository.updateBook(book.copyWith(groupName: destination));
    }
    await _bookListController.loadBooks();
  }
```

`_forceFixedLayoutForSelectedBooks()`（開頭 doc comment 不動，只列受影響的方法本體）原本：

```dart
  Future<void> _forceFixedLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.format != BookFileFormat.epub) continue;
      await widget.repository.updateBook(book.copyWith(isFixedLayout: true));
    }
    await _loadBooks();
  }
```

改為：

```dart
  Future<void> _forceFixedLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.format != BookFileFormat.epub) continue;
      await widget.repository.updateBook(book.copyWith(isFixedLayout: true));
    }
    await _bookListController.loadBooks();
  }
```

`_restoreAutoLayoutForSelectedBooks()`（開頭 doc comment 不動）原本：

```dart
  Future<void> _restoreAutoLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.format != BookFileFormat.epub) continue;
      await widget.repository.detectAndCacheEpubLayout(book.id, book.filePath);
    }
    await _loadBooks();
  }
```

改為：

```dart
  Future<void> _restoreAutoLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.format != BookFileFormat.epub) continue;
      await widget.repository.detectAndCacheEpubLayout(book.id, book.filePath);
    }
    await _bookListController.loadBooks();
  }
```

`_deleteSelectedBooks()` 原本：

```dart
  Future<void> _deleteSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final confirmed = await _confirmDeleteBooks(selectedIds.length);
    if (confirmed != true) return;
    // 比照既有 _openManageGroupsDialog() 的既有慣例：await 跳出 dialog 的
    // 操作之後、觸碰 state 之前先確認 widget 是否仍在畫面上（見
    // library_screen.dart:322，同檔案內多數 await-dialog 後的路徑皆有此
    // 檢查，_moveSelectedBooksToGroup() 缺這道檢查屬既有缺口，不在本工單
    // 範圍內一併修正）。
    if (!mounted) return;
    // 比照既有 _moveSelectedBooksToGroup()：先退出選取模式，避免刪除迴圈
    // 執行期間使用者重複點擊觸發本方法。
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      await widget.repository.deleteBook(book.id);
      try {
        if (File(book.filePath).existsSync()) {
          File(book.filePath).deleteSync();
        }
        final coverPath = book.coverPath;
        if (coverPath != null && File(coverPath).existsSync()) {
          File(coverPath).deleteSync();
        }
      } catch (_) {
        // 檔案刪除失敗時靜默略過，不中斷主流程；資料庫紀錄已刪除，殘留
        // 檔案不影響功能正確性。
      }
    }
    await _loadBooks();
  }
```

改為：

```dart
  Future<void> _deleteSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final confirmed = await _confirmDeleteBooks(selectedIds.length);
    if (confirmed != true) return;
    // 比照既有 _openManageGroupsDialog() 的既有慣例：await 跳出 dialog 的
    // 操作之後、觸碰 state 之前先確認 widget 是否仍在畫面上（見
    // library_screen.dart:322，同檔案內多數 await-dialog 後的路徑皆有此
    // 檢查，_moveSelectedBooksToGroup() 缺這道檢查屬既有缺口，不在本工單
    // 範圍內一併修正）。
    if (!mounted) return;
    // 比照既有 _moveSelectedBooksToGroup()：先退出選取模式，避免刪除迴圈
    // 執行期間使用者重複點擊觸發本方法。
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      await widget.repository.deleteBook(book.id);
      try {
        if (File(book.filePath).existsSync()) {
          File(book.filePath).deleteSync();
        }
        final coverPath = book.coverPath;
        if (coverPath != null && File(coverPath).existsSync()) {
          File(coverPath).deleteSync();
        }
      } catch (_) {
        // 檔案刪除失敗時靜默略過，不中斷主流程；資料庫紀錄已刪除，殘留
        // 檔案不影響功能正確性。
      }
    }
    await _bookListController.loadBooks();
  }
```

（本 Step 只換 `books` 讀取來源與結尾重新載入呼叫，迴圈本體維持原樣不動——迴圈本體會在 Task 6 才抽出到 `LibraryBatchActions`，此處刻意保留、避免一次改太多不好審查。）

`_removeLocalCacheForSelectedBooks()` 原本：

```dart
  Future<void> _removeLocalCacheForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.source != BookSource.calibreOpds) continue;
      if (!book.isDownloaded) continue;
      // 比照 _deleteSelectedBooks() 既有慣例：用 try-catch 包住檔案系統
      // 操作，用 deleteSync() 避免 fake zone 限制。
      try {
        if (File(book.filePath).existsSync()) {
          File(book.filePath).deleteSync();
        }
      } catch (_) {
        // 檔案刪除失敗時靜默略過——資料庫標記更新才是核心操作。
      }
      await widget.repository
          .updateBook(book.copyWith(isDownloaded: false));
    }
    await _loadBooks();
  }
```

改為：

```dart
  Future<void> _removeLocalCacheForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.source != BookSource.calibreOpds) continue;
      if (!book.isDownloaded) continue;
      // 比照 _deleteSelectedBooks() 既有慣例：用 try-catch 包住檔案系統
      // 操作，用 deleteSync() 避免 fake zone 限制。
      try {
        if (File(book.filePath).existsSync()) {
          File(book.filePath).deleteSync();
        }
      } catch (_) {
        // 檔案刪除失敗時靜默略過——資料庫標記更新才是核心操作。
      }
      await widget.repository
          .updateBook(book.copyWith(isDownloaded: false));
    }
    await _bookListController.loadBooks();
  }
```

- [ ] **Step 10：`_openBook()` 的 `.then()` 回呼改寫**

原本：

```dart
        .then((_) {
      // 【審查修正】ReaderScreen 內離開/背景時會把最新閱讀進度與定位寫入
      // 資料庫（見 Task 6），但 _books 這份記憶體快照不會自動跟著更新。
      // 若不在此重新載入，_books 仍持有進入閱讀器前的舊 Book 物件；之後
      // 任何以 _books 為來源的整列 updateBook()（例如
      // _moveSelectedBooksToGroup()）會用舊值覆蓋掉剛剛寫入的最新進度，
      // 造成資料遺失（`/superpowers:requesting-code-review` Critical 2）。
      // 這裡不檢查 mounted——_loadBooks() 內部已有等效保護（見其既有實作）。
      _loadBooks();
    });
  }
```

改為：

```dart
        .then((_) {
      // 【審查修正】ReaderScreen 內離開/背景時會把最新閱讀進度與定位寫入
      // 資料庫，但 books 這份記憶體快照不會自動跟著更新。若不在此重新
      // 載入，books 仍持有進入閱讀器前的舊 Book 物件；之後任何以 books
      // 為來源的整列 updateBook()（例如 _moveSelectedBooksToGroup()）會
      // 用舊值覆蓋掉剛剛寫入的最新進度，造成資料遺失（
      // `/superpowers:requesting-code-review` Critical 2）。這裡不檢查
      // mounted——LibraryBookListController.loadBooks() 內部已有等效
      // 保護（見其既有實作）。
      _bookListController.loadBooks();
    });
  }
```

- [ ] **Step 11：`_openManageGroupsDialog()` 改寫**

原本：

```dart
  Future<void> _openManageGroupsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => LibraryGroupManagementDialog(
        repository: widget.repository,
        initialGroups: _groups,
      ),
    );
    await _loadGroups();
    if (!mounted) return;
    await _loadBooks();
  }
```

改為：

```dart
  Future<void> _openManageGroupsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => LibraryGroupManagementDialog(
        repository: widget.repository,
        initialGroups: _bookListController.groups,
      ),
    );
    await _bookListController.loadGroups();
    if (!mounted) return;
    await _bookListController.loadBooks();
  }
```

- [ ] **Step 12：`_openGroupFilteredView()` 的 `.then()` 回呼改寫**

原本結尾（`.then((_) { ... })` 區塊）：

```dart
        .then((_) {
      // 【審查修正】推入的畫面是獨立的 LibraryScreen State 實例，在裡面
      // 移動/刪除書籍只會更新該實例自己的 _books/_groups，不會 touch 這裡
      // （背景頂層畫面）的狀態；返回時若不重新載入，頂層拼貼格與書籍清單
      // 會停留在使用者離開當下的舊快照（比照既有 _openBook() 的 .then()
      // 修正所防範的同類問題）。
      //
      // 【審查修正】原本只呼叫 _loadBooks()，理由是「管理分類」入口在
      // groupFilter != null 的篩選畫面上不顯示，篩選畫面內無法變動分類
      // 名稱集合——但這個假設不成立：篩選畫面的 AppBar 仍保留「匯入書籍」
      // 按鈕（未比照「管理分類」用 groupFilter == null 隱藏），而「選擇
      // 資料夾＋依資料夾名稱自動建立分類」會呼叫
      // BookImportServiceImpl.importFolder() 內部的 repository.upsertGroup()，
      // 確實可以在篩選畫面內建立新分類。若不一併呼叫 _loadGroups()，頂層
      // 的 _groups 快照就不包含新分類，_buildGroupTiles() 的孤兒兜底桶會
      // 把新分類排到「未分類」之後，違反「未分類固定排最後」的不變量，
      // 故改為與 _loadBooks() 一起重新載入。
      if (!mounted) return;
      _loadGroups();
      _loadBooks();
    });
  }
```

改為：

```dart
        .then((_) {
      // 【審查修正】推入的畫面是獨立的 LibraryScreen State 實例（含獨立的
      // LibraryBookListController），在裡面移動/刪除書籍只會更新該實例
      // 自己的控制器狀態，不會 touch 這裡（背景頂層畫面）的狀態；返回時
      // 若不重新載入，頂層拼貼格與書籍清單會停留在使用者離開當下的舊快照
      // （比照既有 _openBook() 的 .then() 修正所防範的同類問題）。
      //
      // 【審查修正】原本只呼叫 loadBooks()，理由是「管理分類」入口在
      // groupFilter != null 的篩選畫面上不顯示，篩選畫面內無法變動分類
      // 名稱集合——但這個假設不成立：篩選畫面的 AppBar 仍保留「匯入書籍」
      // 按鈕（未比照「管理分類」用 groupFilter == null 隱藏），而「選擇
      // 資料夾＋依資料夾名稱自動建立分類」會呼叫
      // BookImportServiceImpl.importFolder() 內部的 repository.upsertGroup()，
      // 確實可以在篩選畫面內建立新分類。若不一併呼叫 loadGroups()，頂層的
      // groups 快照就不包含新分類，_buildGroupTiles() 的孤兒兜底桶會把
      // 新分類排到「未分類」之後，違反「未分類固定排最後」的不變量，故改
      // 為與 loadBooks() 一起重新載入。
      if (!mounted) return;
      _bookListController.loadGroups();
      _bookListController.loadBooks();
    });
  }
```

- [ ] **Step 13：`build()` 改用控制器的 `books`**

原本：

```dart
  @override
  Widget build(BuildContext context) {
    final books = _books;
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    final books = _bookListController.books;
```

- [ ] **Step 14：`_buildNormalAppBar()` 排序按鈕改用控制器**

原本：

```dart
        PopupMenuButton<LibrarySortBy>(
          key: const Key('library_sort_button'),
          icon: const Icon(Icons.sort),
          tooltip: '排序：${_sortLabel(_sortBy)}',
          enabled: books != null,
          onSelected: _changeSortBy,
```

改為：

```dart
        PopupMenuButton<LibrarySortBy>(
          key: const Key('library_sort_button'),
          icon: const Icon(Icons.sort),
          tooltip: '排序：${_sortLabel(_bookListController.sortBy)}',
          enabled: books != null,
          onSelected: _bookListController.changeSortBy,
```

- [ ] **Step 15：確認殘留 import／型別是否仍需要**

跑 `flutter analyze app/lib/screens/library_screen.dart`，確認 `LibraryPreferences`／`LibrarySortBy`（`_sortLabel()` 參數型別仍會用到，預期不會變成未使用）等既有 import 是否仍需要，依實際結果決定是否移除（原則同 Issue 7 Task 2 Step 5，不要憑空猜測）。

- [ ] **Step 16：執行測試確認通過**

執行：`cd app && flutter test test/screens/library_screen_test.dart`
預期：`PASS`（全部既有案例，本 Task 未變動任何測試檔案——所有斷言皆透過 widget 樹/按鍵行為進行黑箱測試，不直接存取 `_LibraryScreenState` 私有欄位，預期零回歸零修改）。

- [ ] **Step 17：Commit**

```bash
git add app/lib/screens/library_screen.dart
git commit -m "refactor(epic-26): Issue 8 Task 4——LibraryScreen 改用 LibraryBookListController"
```

---

### Task 5：建立 `LibraryBatchActions`（5 個批次操作 + 共用骨架，吸收候選 6）

**Files:**
- Create: `app/lib/screens/library_batch_actions.dart`
- Test: `app/test/screens/library_batch_actions_test.dart`

**Interfaces:**
- Produces：
  - `class LibraryBatchActions { const LibraryBatchActions({required LibraryRepository repository}); Future<void> moveToGroup(Set<String> selectedIds, List<Book> books, String destination); Future<void> forceFixedLayout(Set<String> selectedIds, List<Book> books); Future<void> restoreAutoLayout(Set<String> selectedIds, List<Book> books); Future<void> deleteBooks(Set<String> selectedIds, List<Book> books); Future<void> removeLocalCache(Set<String> selectedIds, List<Book> books); }`
  - Task 6 會 import 並在 `LibraryScreen` 中以 `late final LibraryBatchActions _batchActions;` 持有一個實例，於 `initState()` 建立。

- [ ] **Step 1：寫失敗測試，驗證 5 個批次操作的差異化過濾與 repository 呼叫**

```dart
// app/test/screens/library_batch_actions_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/library_batch_actions.dart';

import '../support/fake_library_repository.dart';

void main() {
  test('moveToGroup() 只更新選取集合中的書籍，未選取的維持原分類', () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', groupName: '未分類'),
      _book(id: '2', groupName: '未分類'),
    ]);
    final actions = LibraryBatchActions(repository: repository);
    final books = await repository.listBooks();

    await actions.moveToGroup({'1'}, books, '奇幻');

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').groupName, '奇幻');
    expect(updated.firstWhere((b) => b.id == '2').groupName, '未分類');
  });

  test('forceFixedLayout() 只處理選取集合中的 EPUB 書籍，非 EPUB 自動跳過',
      () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', format: BookFileFormat.epub),
      _book(id: '2', format: BookFileFormat.pdf),
    ]);
    final actions = LibraryBatchActions(repository: repository);
    final books = await repository.listBooks();

    await actions.forceFixedLayout({'1', '2'}, books);

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isFixedLayout, isTrue);
    expect(updated.firstWhere((b) => b.id == '2').isFixedLayout, isNull);
  });

  test('restoreAutoLayout() 只對選取集合中的 EPUB 書籍呼叫 detectAndCacheEpubLayout()',
      () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', format: BookFileFormat.epub),
      _book(id: '2', format: BookFileFormat.pdf),
    ]);
    final actions = LibraryBatchActions(repository: repository);
    final books = await repository.listBooks();

    await actions.restoreAutoLayout({'1', '2'}, books);

    expect(repository.detectAndCacheEpubLayoutCalls, ['1']);
  });

  test('deleteBooks() 刪除選取集合中每一本書的資料庫紀錄', () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1'),
      _book(id: '2'),
    ]);
    final actions = LibraryBatchActions(repository: repository);
    final books = await repository.listBooks();

    await actions.deleteBooks({'1'}, books);

    final remaining = await repository.listBooks();
    expect(remaining.map((b) => b.id), ['2']);
  });

  test(
      'removeLocalCache() 只處理選取集合中「Calibre 來源且已下載」的書籍，'
      '其餘來源與未下載的書籍不受影響', () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', source: BookSource.calibreOpds, isDownloaded: true),
      _book(id: '2', source: BookSource.local, isDownloaded: true),
      _book(id: '3', source: BookSource.calibreOpds, isDownloaded: false),
    ]);
    final actions = LibraryBatchActions(repository: repository);
    final books = await repository.listBooks();

    await actions.removeLocalCache({'1', '2', '3'}, books);

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isDownloaded, isFalse);
    expect(updated.firstWhere((b) => b.id == '2').isDownloaded, isTrue);
    expect(updated.firstWhere((b) => b.id == '3').isDownloaded, isFalse);
  });
}

Book _book({
  required String id,
  String groupName = BookGroup.uncategorized,
  BookFileFormat format = BookFileFormat.epub,
  BookSource source = BookSource.local,
  bool isDownloaded = true,
}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: '測試書 $id',
    author: null,
    format: format,
    filePath: 'content://example/$id.epub',
    source: source,
    coverPath: null,
    groupName: groupName,
    isDownloaded: isDownloaded,
    createTime: now,
    lastReadTime: now,
  );
}
```

`Book` 建構子沒有 `isDownloaded` 具名參數的話這個測試會編譯失敗——請先確認 `app/lib/library/models/book.dart` 的主建構子是否已開放 `isDownloaded` 具名參數（Book 主建構子第 122 行 `this.isDownloaded = true,` 已是既有具名參數，不需新增）。

- [ ] **Step 2：執行測試確認失敗（型別尚未存在）**

執行：`cd app && flutter test test/screens/library_batch_actions_test.dart`
預期：`FAIL`，錯誤訊息為找不到 `package:elinkbook/screens/library_batch_actions.dart`。

- [ ] **Step 3：實作 `LibraryBatchActions`（原樣搬移 5 個批次操作的迴圈本體與歷史註解，收斂共用骨架 `_runEach`）**

```dart
// app/lib/screens/library_batch_actions.dart
import 'dart:io';

import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/library_enums.dart';

/// 收斂 `LibraryScreen` 5 個批次操作（搬移分類／強制 FXL／恢復自動判斷／
/// 刪除／移除本機快取）共用的執行骨架（epic-26-architecture-hardening
/// Issue 8，候選 2＋候選 6）：原本 5 個方法各自重複「過濾選取集合中符合
/// 條件的書籍 → 逐筆呼叫 repository」這段骨架，本類別把骨架收斂為私有
/// [_runEach]，5 個公開方法只提供差異化的「單本書該做什麼」與（若需要）
/// 篩選條件。
///
/// **刻意不含**：`_selectedBookIds` 擷取、`_exitSelectionMode()`、任何
/// 需要 `BuildContext` 的確認對話框（搬移分類的目的地選擇、刪除前的確認
/// 對話框）、完成後的重新載入——這些是 UI 生命週期與導覽相關的職責，留在
/// `_LibraryScreenState`（見 `plans/plan-issue-8.md`「規劃階段查證」）。
class LibraryBatchActions {
  const LibraryBatchActions({required this.repository});

  final LibraryRepository repository;

  Future<void> _runEach(
    Set<String> selectedIds,
    List<Book> books,
    Future<void> Function(Book book) action, {
    bool Function(Book book)? shouldInclude,
  }) async {
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (shouldInclude != null && !shouldInclude(book)) continue;
      await action(book);
    }
  }

  /// 搬移到分類（對應原 `_moveSelectedBooksToGroup()` 迴圈本體）。
  Future<void> moveToGroup(
    Set<String> selectedIds,
    List<Book> books,
    String destination,
  ) {
    return _runEach(
      selectedIds,
      books,
      (book) => repository.updateBook(book.copyWith(groupName: destination)),
    );
  }

  /// 對選取集合中所有 EPUB 書籍手動覆寫「引擎分派判斷」結果為固定版面
  /// （FXL）——救濟部分漫畫 EPUB 因來源檔案 metadata 不完整/不規範，被
  /// 「引擎分派判斷」誤判為流式的情況（見 CONTEXT.md「人工版面覆蓋」）。
  /// 非 EPUB 書籍（PDF/TXT）自動跳過，不影響、不拋錯（對應原
  /// `_forceFixedLayoutForSelectedBooks()`）。
  Future<void> forceFixedLayout(Set<String> selectedIds, List<Book> books) {
    return _runEach(
      selectedIds,
      books,
      (book) => repository.updateBook(book.copyWith(isFixedLayout: true)),
      shouldInclude: (book) => book.format == BookFileFormat.epub,
    );
  }

  /// 對選取集合中所有 EPUB 書籍重新呼叫既有 detectAndCacheEpubLayout()，
  /// 回到系統原始的「引擎分派判斷」結果——用於復原誤按/誤判後想撤銷人工
  /// 覆蓋的情況（見 CONTEXT.md「人工版面覆蓋」）。非 EPUB 書籍自動跳過
  /// （對應原 `_restoreAutoLayoutForSelectedBooks()`）。
  Future<void> restoreAutoLayout(Set<String> selectedIds, List<Book> books) {
    return _runEach(
      selectedIds,
      books,
      (book) => repository.detectAndCacheEpubLayout(book.id, book.filePath),
      shouldInclude: (book) => book.format == BookFileFormat.epub,
    );
  }

  /// 刪除書籍：資料庫紀錄一律刪除；實體檔案／封面刪除失敗時靜默略過，不
  /// 中斷批次（對應原 `_deleteSelectedBooks()` 迴圈本體）。
  /// `existsSync()` 防護對 `content://` 來源的 `filePath` 安全（design.md
  /// 調查結論——`content://` 字串永遠不會判定為存在的本機路徑，故此處不
  /// 需要分辨 `filePath` 是本機複本還是原始外部檔案參照）；用
  /// `deleteSync()` 而非 `await delete()`——widget test 的 fake zone 無法
  /// 完成真實 I/O 的 Future，`deleteSync()` 是同步系統呼叫，可直接完成，
  /// 不受 zone 限制。
  Future<void> deleteBooks(Set<String> selectedIds, List<Book> books) {
    return _runEach(selectedIds, books, (book) async {
      await repository.deleteBook(book.id);
      try {
        if (File(book.filePath).existsSync()) {
          File(book.filePath).deleteSync();
        }
        final coverPath = book.coverPath;
        if (coverPath != null && File(coverPath).existsSync()) {
          File(coverPath).deleteSync();
        }
      } catch (_) {
        // 檔案刪除失敗時靜默略過，不中斷主流程；資料庫紀錄已刪除，殘留
        // 檔案不影響功能正確性。
      }
    });
  }

  /// 移除本機快取：對選取集合中所有 Calibre 來源且已下載的書籍，刪除實體
  /// 檔案並標記 `isDownloaded = false`。保留 epubLocator / progress /
  /// 書籤 / 劃線 / 備註等使用者資料（對應原
  /// `_removeLocalCacheForSelectedBooks()`）。
  Future<void> removeLocalCache(Set<String> selectedIds, List<Book> books) {
    return _runEach(
      selectedIds,
      books,
      (book) async {
        try {
          if (File(book.filePath).existsSync()) {
            File(book.filePath).deleteSync();
          }
        } catch (_) {
          // 檔案刪除失敗時靜默略過——資料庫標記更新才是核心操作。
        }
        await repository.updateBook(book.copyWith(isDownloaded: false));
      },
      shouldInclude: (book) =>
          book.source == BookSource.calibreOpds && book.isDownloaded,
    );
  }
}
```

- [ ] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/screens/library_batch_actions_test.dart`
預期：`PASS`

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/library_batch_actions.dart app/test/screens/library_batch_actions_test.dart
git commit -m "refactor(epic-26): Issue 8 Task 5——新增 LibraryBatchActions"
```

---

### Task 6：`LibraryScreen` 5 個批次操作方法改用 `LibraryBatchActions`

**Files:**
- Modify: `app/lib/screens/library_screen.dart`

**Interfaces:**
- Consumes：Task 5 的 `LibraryBatchActions`。

- [ ] **Step 1：新增 import 與 `_batchActions` 欄位**

在檔案頂端 import 區塊新增（置於 `import 'library_book_list_controller.dart';` 之後）：

```dart
import 'library_batch_actions.dart';
```

在 `_LibraryScreenState` 欄位區新增（緊接 `_bookListController` 之後）：

```dart
  late final LibraryBatchActions _batchActions;
```

在 `initState()` 新增建構（緊接 `_bookListController = ...` 之後、`_initialize();` 之前）：

```dart
    _batchActions = LibraryBatchActions(repository: widget.repository);
```

- [ ] **Step 2：`_moveSelectedBooksToGroup()` 改為委派 `LibraryBatchActions.moveToGroup()`**

原本（Task 4 之後的狀態）：

```dart
  Future<void> _moveSelectedBooksToGroup() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final destination = await showDialog<String>(
      context: context,
      builder: (context) =>
          LibraryMoveToGroupDialog(groups: _bookListController.groups),
    );
    if (destination == null) return;
    // 立即退出選取模式，而非等到逐筆寫入資料庫的迴圈結束後才退出：這個迴圈
    // 期間「移動到分類」按鈕仍會顯示在選取模式的 App Bar 上，若不提早退出，
    // 使用者理論上可以在寫入尚未完成時再次點擊，重複觸發本方法。
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      await widget.repository.updateBook(book.copyWith(groupName: destination));
    }
    await _bookListController.loadBooks();
  }
```

改為：

```dart
  Future<void> _moveSelectedBooksToGroup() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final destination = await showDialog<String>(
      context: context,
      builder: (context) =>
          LibraryMoveToGroupDialog(groups: _bookListController.groups),
    );
    if (destination == null) return;
    // 立即退出選取模式，而非等到逐筆寫入資料庫的迴圈結束後才退出：這個迴圈
    // 期間「移動到分類」按鈕仍會顯示在選取模式的 App Bar 上，若不提早退出，
    // 使用者理論上可以在寫入尚未完成時再次點擊，重複觸發本方法。
    _exitSelectionMode();
    await _batchActions.moveToGroup(selectedIds, books, destination);
    await _bookListController.loadBooks();
  }
```

- [ ] **Step 3：`_forceFixedLayoutForSelectedBooks()` 改為委派**

原本（Task 4 之後的狀態，doc comment 省略未變）：

```dart
  Future<void> _forceFixedLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.format != BookFileFormat.epub) continue;
      await widget.repository.updateBook(book.copyWith(isFixedLayout: true));
    }
    await _bookListController.loadBooks();
  }
```

改為：

```dart
  Future<void> _forceFixedLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    await _batchActions.forceFixedLayout(selectedIds, books);
    await _bookListController.loadBooks();
  }
```

上方原有的 doc comment（`/// 對選取集合中所有 EPUB 書籍手動覆寫...`）維持在方法上方不動——它同時解釋了「為何需要這個功能」與「為何在 `_exitSelectionMode()` 之前捕捉 `selectedIds` 是安全的」，後者仍是 `_LibraryScreenState` 這個呼叫端本身的不變量說明，即使差異化邏輯搬到 `LibraryBatchActions`，這段說明依然成立、不需要更動。

- [ ] **Step 4：`_restoreAutoLayoutForSelectedBooks()` 改為委派**

原本（Task 4 之後的狀態）：

```dart
  Future<void> _restoreAutoLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.format != BookFileFormat.epub) continue;
      await widget.repository.detectAndCacheEpubLayout(book.id, book.filePath);
    }
    await _bookListController.loadBooks();
  }
```

改為：

```dart
  Future<void> _restoreAutoLayoutForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    await _batchActions.restoreAutoLayout(selectedIds, books);
    await _bookListController.loadBooks();
  }
```

- [ ] **Step 5：`_deleteSelectedBooks()` 改為委派（`_confirmDeleteBooks()` 對話框維持不動）**

原本（Task 4 之後的狀態）：

```dart
  Future<void> _deleteSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final confirmed = await _confirmDeleteBooks(selectedIds.length);
    if (confirmed != true) return;
    // 比照既有 _openManageGroupsDialog() 的既有慣例：await 跳出 dialog 的
    // 操作之後、觸碰 state 之前先確認 widget 是否仍在畫面上（見
    // library_screen.dart:322，同檔案內多數 await-dialog 後的路徑皆有此
    // 檢查，_moveSelectedBooksToGroup() 缺這道檢查屬既有缺口，不在本工單
    // 範圍內一併修正）。
    if (!mounted) return;
    // 比照既有 _moveSelectedBooksToGroup()：先退出選取模式，避免刪除迴圈
    // 執行期間使用者重複點擊觸發本方法。
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      await widget.repository.deleteBook(book.id);
      // existsSync() 防護對 content:// 來源的 filePath 安全（design.md
      // 調查結論——content:// 字串永遠不會判定為存在的本機路徑，故此處
      // 不需要分辨 filePath 是本機複本還是原始外部檔案參照）。比照既有
      // _pickAndImportFiles()/_pickAndImportFolder() 的既有慣例，用
      // try-catch 包住檔案系統操作：單一檔案刪除失敗（例如被其他程序鎖
      // 定、權限異常）不應中斷整個批次刪除迴圈——deleteBook()（資料庫紀
      // 錄，使用者最關心的「書從書架消失」）已在上一行完成，迴圈仍要繼
      // 續處理其餘已選取的書籍並跑到最後的 _loadBooks()。
      try {
        // 使用 deleteSync() 而非 await delete()：widget test 的 fake zone
        // 無法完成真實 I/O 的 Future，deleteSync() 是同步系統呼叫，可直接完
        // 成，不受 zone 限制。
        if (File(book.filePath).existsSync()) {
          File(book.filePath).deleteSync();
        }
        final coverPath = book.coverPath;
        if (coverPath != null && File(coverPath).existsSync()) {
          File(coverPath).deleteSync();
        }
      } catch (_) {
        // 檔案刪除失敗時靜默略過，不中斷主流程；資料庫紀錄已刪除，殘留
        // 檔案不影響功能正確性。
      }
    }
    await _bookListController.loadBooks();
  }
```

改為：

```dart
  Future<void> _deleteSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    final confirmed = await _confirmDeleteBooks(selectedIds.length);
    if (confirmed != true) return;
    // 比照既有 _openManageGroupsDialog() 的既有慣例：await 跳出 dialog 的
    // 操作之後、觸碰 state 之前先確認 widget 是否仍在畫面上（同檔案內
    // 多數 await-dialog 後的路徑皆有此檢查，_moveSelectedBooksToGroup()
    // 缺這道檢查屬既有缺口，不在本工單範圍內一併修正）。
    if (!mounted) return;
    // 比照既有 _moveSelectedBooksToGroup()：先退出選取模式，避免刪除迴圈
    // 執行期間使用者重複點擊觸發本方法。
    _exitSelectionMode();
    await _batchActions.deleteBooks(selectedIds, books);
    await _bookListController.loadBooks();
  }
```

（`import 'dart:io';` 與 `File` 相關程式碼因搬到 `LibraryBatchActions` 而不再需要留在 `library_screen.dart`——留待 Step 7 統一以 `flutter analyze` 確認後處理。）

- [ ] **Step 6：`_removeLocalCacheForSelectedBooks()` 改為委派**

原本（Task 4 之後的狀態）：

```dart
  Future<void> _removeLocalCacheForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (book.source != BookSource.calibreOpds) continue;
      if (!book.isDownloaded) continue;
      // 比照 _deleteSelectedBooks() 既有慣例：用 try-catch 包住檔案系統
      // 操作，用 deleteSync() 避免 fake zone 限制。
      try {
        if (File(book.filePath).existsSync()) {
          File(book.filePath).deleteSync();
        }
      } catch (_) {
        // 檔案刪除失敗時靜默略過——資料庫標記更新才是核心操作。
      }
      await widget.repository
          .updateBook(book.copyWith(isDownloaded: false));
    }
    await _bookListController.loadBooks();
  }
```

改為：

```dart
  Future<void> _removeLocalCacheForSelectedBooks() async {
    final selectedIds = _selectedBookIds;
    final books = _bookListController.books;
    if (selectedIds == null || selectedIds.isEmpty || books == null) return;
    _exitSelectionMode();
    await _batchActions.removeLocalCache(selectedIds, books);
    await _bookListController.loadBooks();
  }
```

- [ ] **Step 7：確認 `dart:io`／`File` 是否仍需要，依 `flutter analyze` 實際結果決定是否移除 import**

跑 `flutter analyze app/lib/screens/library_screen.dart`。`import 'dart:io';` 原本只服務於已搬走的 3 個批次操作（`_deleteSelectedBooks`／`_removeLocalCacheForSelectedBooks`）內的 `File(...)` 呼叫，本 Task 完成後 `library_screen.dart` 預期不再使用 `File`；若 analyze 回報 `unused_import`，移除該行 import（不要憑空猜測，以 analyze 實際結果為準）。

- [ ] **Step 8：執行測試確認通過**

執行：`cd app && flutter test test/screens/library_screen_test.dart`
預期：`PASS`（全部既有案例，含刪除/移除本機快取/搬移分類/強制FXL/恢復自動判斷 5 組既有測試，零回歸零修改）。

- [ ] **Step 9：Commit**

```bash
git add app/lib/screens/library_screen.dart
git commit -m "refactor(epic-26): Issue 8 Task 6——LibraryScreen 5 個批次操作改用 LibraryBatchActions"
```

---

### Task 7：全專案最終驗證

**Files:**
- 無新增/修改檔案，純驗證。

- [ ] **Step 1：全域殘留掃描，確認舊的內嵌邏輯已無殘留**

執行：

```bash
cd app
grep -rn "_gridTileFooterHeight\|_kGridTileFooterHeightAtScale1\|_kGridTileFooterTitleFontSize\|_kGridTileFooterProgressFontSize\|_kGridTileFooterLineHeightFactor" lib/screens/library_screen.dart
grep -rn "\b_books\b\|\b_groups\b\|\b_sortBy\b\|\b_groupFilter\b" lib/screens/library_screen.dart
grep -rn "_loadGroups()\|_loadBooks()\|_changeSortBy(" lib/screens/library_screen.dart
```

預期：全數皆無輸出（`_bookListController.books`／`.groups`／`.sortBy` 這類存取不會誤命中——`\b_books\b` 等樣式要求前後皆為單字邊界，`_bookListController.books` 中的 `books` 前面是 `.` 而非單字邊界起點，`_bookListController` 本身也不含裸露的 `_books`／`_groups`／`_sortBy`／`_groupFilter` 子字串）。

**重要：本次殘留掃描同時檢查唯一組裝根 `main.dart` 是否受影響**——`LibraryScreen` 對外建構參數（`repository`／`importService`／`prefsManager`／5 個 bundle／`computeFingerprint`／`isMobileDataConnection`／`groupFilter`）在本次 Issue 8 全程未變動，`main.dart` 不需要任何修改，執行：

```bash
grep -n "LibraryScreen(" ../app/lib/main.dart
```

確認呼叫點existing 建構參數列與 Issue 7 合併後狀態一致（比照 `review-issue-7.md` Important #2 的教訓，任何「內部拆分」類型的計畫都必須明確驗證組裝根未被波及，即使本計畫理論上不觸碰 `main.dart`）。

- [ ] **Step 2：執行 `flutter analyze`**

執行：`cd app && flutter analyze`
預期：`No issues found!`（確認 Task 2、4、6 提到「依實際結果決定是否移除的 import」皆已正確處理，無 `unused_import` 或其他警告；`integration_test/` 不受影響）。

- [ ] **Step 3：執行全專案測試**

執行：`cd app && flutter test`
預期：全數通過，零回歸（相較 Issue 7 合併後的基準數字 1613，本 Issue Task 1/3/5 新增 3 個新檔案的獨立單元測試，其餘為既有 `library_screen_test.dart` 案例零修改地繼續通過，總數應為「1613 ＋ 新增測試數」）。

- [ ] **Step 4：逐項核對驗收標準**

- [ ] `LibraryScreen` 內部關注點依 module 邊界拆分完成：`LibraryBookListController`（書籍清單狀態機）／`LibraryBatchActions`（批次操作）／`BookGridTileMetrics`（拼貼格版面數學）皆已獨立成檔案，`_LibraryScreenState` 不再直接持有 `_books`／`_groups`／`_sortBy`／`_groupFilter`／`_gridTileFooterHeight` 等內嵌實作。
- [ ] 候選 6（批次操作骨架重複）隨本 Issue 一併收斂：`LibraryBatchActions._runEach()` 是唯一的過濾/迭代骨架，5 個公開方法各自只提供差異化邏輯，不需另立工單。
- [ ] 行為零改變：既有不對稱行為（`_moveSelectedBooksToGroup()` 缺少 `!mounted` 檢查等既有缺口）原樣保留；`main.dart` 組裝根與所有既有測試皆未變動。
- [ ] `flutter analyze` 乾淨、`flutter test` 全數通過。

- [ ] **Step 5：Commit（若 Step 1-4 有任何微調）**

```bash
git add -A
git commit -m "refactor(epic-26): Issue 8 Task 7——最終驗證：殘留掃描、flutter analyze 乾淨、全數測試通過"
```

（若 Step 1-4 皆一次到位無需任何修改，本 Task 可以不產生新 commit，直接在審查報告中記錄驗證結果。）
