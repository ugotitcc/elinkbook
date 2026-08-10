# Epic 24 Issue 5 — 目錄（TOC）解析與 UI（`BookTocItem` 抽象介面）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一個格式無關的目錄項目抽象介面 `BookTocItem`，讓 EPUB 既有的 `TocBottomSheet` 改為消費該介面而非直接依賴 EPUB 專屬的 `TocEntry`；PDF 端透過 `pdfrx` 的 `loadOutline()` 解析大綱，轉換為同一介面的 `PdfTocItem` 實例，補齊「開啟 PDF 書籍能看到內建章節目錄、點擊跳轉、巢狀層級正確顯示、目前所在章節高亮」四項能力，與 EPUB 既有目錄行為對等。

**Architecture:** `BookTocItem`（`title`／`stableId`／`children` 三個成員）是唯一的共用抽象；「目前章節」判定演算法（`TocNavigator`／`PdfTocNavigator`）與「頁碼顯示」邏輯因為兩種格式的定位鍵型別完全不同（EPUB 用 0.0-1.0 的 progression double，PDF 用 0-indexed 整數頁碼）刻意不勉強收斂成單一泛型函式，各自獨立實作、`TocBottomSheet` 內部以 `is TocEntry`/`is PdfTocItem` 分流頁碼顯示邏輯。`TocEntry` 只需新增 `implements BookTocItem` 與一個 `stableId => locatorJson` getter，不改動任何既有欄位/建構子——這是本計畫刻意驗證過的核心設計決策（見下方「與 spec.md 的實作細節澄清」）。

**Tech Stack:** Flutter/Dart、`pdfrx`（`PdfDocument.loadOutline()` → `List<PdfOutlineNode>`，`PdfOutlineNode.dest?.pageNumber` 為 **1-indexed**）、既有 `flutter_test`（`flutter test` 對真實 PDF fixture 驗證，不需 `integration_test`）。

## Global Constraints

- **零回歸紅線**：EPUB 既有目錄行為（`TocBottomSheet` 的渲染、展開/收起、當前章節高亮、頁碼估算的即時更新）逐位元組不變；`app/test/screens/toc_bottom_sheet_test.dart` 現有 6 個 `testWidgets` 只允許新增/移動，**不允許刪除或弱化任何一則既有斷言**（唯一允許的例外是 Task 4 Step 3 描述的、因型別加寬而不得不做的一行區域變數型別修正，非行為變更）。
- **PDF 目錄目前沒有可見的觸發按鈕**：比照 Issue 4 書籤 toggle 的既有先例（`docs/epics/epic-24-pdf-engine-rebuild/issues.md` Issue 4：「本工單只需要完成 toggle 邏輯本身（可透過既有測試 seam 觸發驗證）；toggle 對應的 FAB 按鈕留給 Issue 8 統一接線」）——本工單只完成資料載入與 `TocBottomSheet` 顯示邏輯本身，透過新增的 `ReaderScreen.openPdfToc` static 測試 seam 觸發驗證；PDF 頂部工具列的 FAB 化與「目錄」按鈕實際接線屬於 Issue 8 範圍，不在本工單新增任何可見按鈕。既有測試「PDF 格式下，目錄入口按鈕不存在」（`app/test/screens/reader_screen_test.dart:1337`）驗證的是 `Key('reader_toc_button')`（EPUB 專屬 AppBar 按鈕），本工單不新增同名按鈕給 PDF，此測試不需要、也不應該被修改。
- **頁碼慣例**：本專案既有慣例一律 0-indexed（`PdfPageInfo.pageIndex`／`PdfReaderView.jumpToPage`）；`pdfrx` 的 `PdfOutlineNode.dest?.pageNumber` 是 1-indexed（已實際查證 `pdfrx_engine-0.4.5` 原始碼與 `PdfViewer` 內部 `dest.pageNumber - 1` 的一致用法，見 Task 3），轉換只發生在 `PdfReaderView._loadTableOfContents()` 內部。
- **測試策略**：一律用 `flutter test` 對真實 PDF fixture 驗證（`pdfrx` 純 Dart FFI，桌面 host 可直接載入真實 PDFium），不使用 `integration_test`。
- **`flutter analyze` 乾淨、每個 Task 結束後相關測試全數通過**是每個 Task 的隱含驗收條件，不重複在每個 Task 內贅述。

---

## 與 spec.md 的實作細節澄清（供審查對照）

以下三項是 `spec.md`「目錄（TOC）」一節留白、由本計畫在撰寫階段做出並已實測驗證的具體設計決策：

1. **`BookTocItem` 介面刻意精簡為 `title`／`stableId`／`children` 三個成員**，不包含「定位點」或「排序鍵」——`TocEntry.locatorJson`（字串 CFI）與 `PdfTocItem.pageIndex`（整數頁碼）型別完全不同，「目前章節高亮」演算法的比較鍵也不同（double progression vs. int pageIndex），勉強塞進同一個抽象欄位只會增加轉型成本，不會減少程式碼量。`TocNavigator`（EPUB，既有、本工單不改動）與新增的 `PdfTocNavigator`（PDF）各自獨立實作對稱演算法。
2. **`TocEntry implements BookTocItem` 的協變（covariant）合法性已用獨立腳本驗證**：`TocEntry` 的既有欄位 `final List<TocEntry> children` 可以直接滿足介面宣告的 `List<BookTocItem> get children`，因為 Dart 泛型是協變的（`List<TocEntry> <: List<BookTocItem>`，因為 `TocEntry <: BookTocItem`）。已用 `dart run` 實際編譯執行驗證此寫法合法且執行期行為正確（見下方 Task 1 Step 2 附上的驗證紀錄），不是理論推測。
3. **新增的 PDF fixture（`sample_pdf_toc.pdf`）已用真實 `pdfrx` 解析驗證過**：6 頁、3 個頂層大綱項目（其中 2 個各有 2 個子項），已實際跑過 `PdfDocument.loadOutline()` 確認巢狀結構、標題、`dest.pageNumber` 皆與生成腳本的設計意圖完全吻合（見 Task 3 Step 2 附上的實測輸出）。既有 `sample.pdf`（345 bytes）已驗證 `loadOutline()` 回傳空清單，可直接用於「無大綱」情境測試，不需要另外產生第二個 fixture。

---

### Task 1: `BookTocItem` 抽象介面 + `TocEntry` 實作（EPUB 零回歸）

**Files:**
- Create: `app/lib/reader/book_toc_item.dart`
- Modify: `app/lib/reader/toc_entry.dart`
- Test: `app/test/reader/toc_entry_test.dart`（新增，不刪除既有測試）

**Interfaces:**
- Produces: `abstract class BookTocItem { String get title; String get stableId; List<BookTocItem> get children; }`——後續所有 Task 皆依賴此介面。

- [x] **Step 1: 建立 `BookTocItem` 抽象介面**

建立 `app/lib/reader/book_toc_item.dart`：

```dart
/// 格式無關的目錄項目抽象介面（epic-24-pdf-engine-rebuild Issue 5，
/// spec.md「目錄（TOC）」）：EPUB（[TocEntry]，`toc_entry.dart`）與 PDF
/// （`PdfTocItem`，`pdf_toc_item.dart`）的目錄項目皆實作本介面，
/// `TocBottomSheet` 只依賴這個介面渲染，不再直接依賴任一格式專屬的目錄
/// 項目型別。
///
/// 刻意只包含 [title]／[children]／[stableId] 三個成員：目錄項目的
/// 「定位點」（EPUB 的 CFI locator 字串、PDF 的 0-indexed 頁碼整數）與
/// 「目前章節高亮」演算法所需的排序鍵（EPUB 的 progression double、PDF
/// 的頁碼 int）在兩種格式之間型別完全不同，無法無損收斂進同一個抽象
/// 欄位，改由各自的 Navigator（`TocNavigator`／`PdfTocNavigator`）與
/// 呼叫端（`reader_screen.dart`）各自處理，不勉強塞進本介面。
abstract class BookTocItem {
  String get title;

  /// 供 Widget `Key` 使用的穩定識別字串，同一次目錄樹中須全域唯一（不只
  /// 是同層兄弟節點唯一）。EPUB 沿用既有的 [TocEntry.locatorJson]；PDF
  /// 由 `PdfTocItem` 在解析大綱時以遞增計數器產生，因為 PDF 大綱可能有
  /// 多個節點指向同一頁碼，無法用頁碼本身保證唯一。
  String get stableId;

  List<BookTocItem> get children;
}
```

- [x] **Step 2: 驗證協變覆寫可編譯執行（一次性驗證，非長期測試）**

這一步驗證「`final List<TocEntry> children` 滿足 `List<BookTocItem> get children`」這個協變寫法在 Dart 是合法的。在專案外任意暫存目錄（例如系統暫存目錄）建立 `covariance_check.dart`：

```dart
abstract class BookTocItem {
  String get title;
  List<BookTocItem> get children;
}

class TocEntry implements BookTocItem {
  final String title;
  final String locatorJson;
  final double? progression;
  final List<TocEntry> children;

  const TocEntry({
    required this.title,
    required this.locatorJson,
    this.progression,
    this.children = const [],
  });
}

void takesList(List<BookTocItem> items) {
  for (final i in items) {
    print(i.title);
  }
}

void main() {
  final e = const TocEntry(title: 'a', locatorJson: 'l1');
  takesList([e]);
  BookTocItem? current = e;
  print(current.children);
}
```

Run: `dart run covariance_check.dart`
Expected: 印出 `a` 與 `[]`，無編譯錯誤——確認協變覆寫合法且執行期行為正確。驗證完成後刪除此暫存檔案（不提交進版控，`app/lib/reader/toc_entry.dart` 才是正式改動位置）。

（本計畫撰寫階段已實際執行過這個驗證，結果如上——這一步是給實作者的可重現確認手續，不是探索性質。）

- [x] **Step 3: 修改 `TocEntry` 實作 `BookTocItem`**

修改 `app/lib/reader/toc_entry.dart`，在檔案開頭新增 import，並在既有 `class TocEntry {` 前後做最小異動：

```dart
import 'book_toc_item.dart';

/// EPUB 目錄樹狀清單的單一節點（epic-5-toc-pagination Issue 4，spec.md
/// 「目錄模組」）：原生端一次性讀取 `Publication.tableOfContents` 後序列化
/// 傳來，保留完整巢狀階層（[children]，不攤平）。
///
/// 刻意不覆寫 `==`/`hashCode`（維持預設的物件識別語意）——[TocNavigator]
/// 回傳的「目前章節路徑」與 UI 的展開狀態集合，判斷依據都是「是否為同一個
/// 節點物件參照」，只要 `entries` 樹狀結構本身在同一次 build 週期內沒有
/// 被重新解析成新物件，物件識別語意就足夠正確，不需要值相等語意。
///
/// 實作 [BookTocItem]（epic-24-pdf-engine-rebuild Issue 5）：[children]
/// 欄位型別 `List<TocEntry>` 透過 Dart 協變泛型滿足介面宣告的
/// `List<BookTocItem>`，不需要額外轉換；[stableId] 直接回傳
/// [locatorJson]，確保既有的 `Key('toc_entry_${entry.locatorJson}')` 等
/// 既有 Widget Key 命名（`toc_bottom_sheet.dart`）逐位元組不變。
class TocEntry implements BookTocItem {
  @override
  final String title;

  /// 原生端 `Locator.toJSON().toString()`，透過
  /// `Publication.locatorFromLink(Link)` 建構、保留錨點精度（非僅解析到
  /// resource 起始位置）。點選項目時原樣傳回原生端 `jumpToLocator` 還原。
  final String locatorJson;

  /// 全書閱讀進度比例（0.0-1.0），供換算估算頁碼。原生端優先取用
  /// [locatorJson] 對應 Locator 自身的 `totalProgression`；查無則退回比對
  /// `Publication.positions()`，仍查無時為 `null`（此時 UI 顯示佔位符，不
  /// 視為錯誤）。
  final double? progression;

  @override
  final List<TocEntry> children;

  @override
  String get stableId => locatorJson;

  const TocEntry({
    required this.title,
    required this.locatorJson,
    this.progression,
    this.children = const [],
  });

  /// 遞迴解析原生端 `getTableOfContents` 回傳的巢狀 map 結構。缺失的
  /// `title`／`locatorJson` 以空字串防呆（不拋出例外），比照專案既有對
  /// MethodChannel 回傳資料的寬容解析慣例。
  factory TocEntry.fromWire(Map<Object?, Object?> map) {
    final rawChildren = map['children'] as List<Object?>? ?? const [];
    return TocEntry(
      title: map['title'] as String? ?? '',
      locatorJson: map['locatorJson'] as String? ?? '',
      progression: (map['progression'] as num?)?.toDouble(),
      children: rawChildren
          .map((e) => TocEntry.fromWire(e as Map<Object?, Object?>))
          .toList(),
    );
  }
}
```

- [x] **Step 4: 新增 `stableId` 的最小驗證測試**

在 `app/test/reader/toc_entry_test.dart` 既有 `void main() {` 的 `group('TocEntry.fromWire', ...)` 區塊之後（同一個 `main()` 內）新增：

```dart
  group('BookTocItem 介面（Issue 5）', () {
    test('stableId 回傳 locatorJson 本身', () {
      const entry = TocEntry(title: '第一章', locatorJson: 'l1', progression: 0.0);
      expect(entry.stableId, 'l1');
    });

    test('TocEntry 是 BookTocItem', () {
      const BookTocItem entry =
          TocEntry(title: '第一章', locatorJson: 'l1', progression: 0.0);
      expect(entry, isA<BookTocItem>());
    });
  });
```

檔案開頭新增 `import 'package:elinkbook/reader/book_toc_item.dart';`。

- [x] **Step 5: 執行測試確認通過**

Run: `flutter test test/reader/toc_entry_test.dart -v`
Expected: 既有 4 項＋新增 2 項，共 6 項全數通過。

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/book_toc_item.dart app/lib/reader/toc_entry.dart app/test/reader/toc_entry_test.dart
git commit -m "feat(epic-24): 新增 BookTocItem 抽象介面，TocEntry 實作該介面（EPUB 零回歸）"
```

---

### Task 2: `PdfTocItem` + `PdfTocNavigator`（純函式，無 I/O）

**Files:**
- Create: `app/lib/reader/pdf_toc_item.dart`
- Create: `app/lib/reader/pdf_toc_navigator.dart`
- Test: `app/test/reader/pdf_toc_navigator_test.dart`

**Interfaces:**
- Consumes: `BookTocItem`（Task 1）。
- Produces: `class PdfTocItem implements BookTocItem { final String title; final int? pageIndex; final String stableId; final List<PdfTocItem> children; const PdfTocItem({required title, required pageIndex, required stableId, children = const []}); }`；`class PdfTocNavigator { static List<PdfTocItem> findCurrentPath(List<PdfTocItem> entries, int? currentPageIndex); }`——Task 3、Task 5 皆依賴這兩個型別/方法簽章。

- [x] **Step 1: 建立 `PdfTocItem`**

建立 `app/lib/reader/pdf_toc_item.dart`：

```dart
import 'book_toc_item.dart';

/// PDF 目錄樹狀清單的單一節點（epic-24-pdf-engine-rebuild Issue 5，
/// spec.md「目錄（TOC）」）：由 `PdfReaderView._loadTableOfContents()`
/// 一次性把 `pdfrx` 的 `PdfOutlineNode` 樹轉換而來，保留完整巢狀階層。
///
/// 刻意不覆寫 `==`/`hashCode`（比照 `TocEntry` 既有慣例，維持預設的物件
/// 識別語意）——`PdfTocNavigator` 回傳的「目前章節路徑」與 UI 的展開狀態
/// 集合，判斷依據都是「是否為同一個節點物件參照」。
class PdfTocItem implements BookTocItem {
  @override
  final String title;

  /// 大綱項目的目標頁碼（0-indexed，比照專案既有慣例），`null` 代表該
  /// 大綱節點在原始 PDF 中沒有有效的目的地（`PdfOutlineNode.dest ==
  /// null`）——這是合法但少見的 PDF 寫法（例如純粹用來分組子項的標題列，
  /// 自身不指向任何頁面）。點擊 `pageIndex == null` 的節點時，呼叫端
  /// （`reader_screen.dart`）不執行跳轉，但節點仍正常顯示於目錄樹中。
  final int? pageIndex;

  @override
  final String stableId;

  @override
  final List<PdfTocItem> children;

  const PdfTocItem({
    required this.title,
    required this.pageIndex,
    required this.stableId,
    this.children = const [],
  });
}
```

- [x] **Step 2: 撰寫 `PdfTocNavigator` 的失敗測試**

建立 `app/test/reader/pdf_toc_navigator_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_toc_item.dart';
import 'package:elinkbook/reader/pdf_toc_navigator.dart';

void main() {
  final ch1 = const PdfTocItem(title: 'Ch1', pageIndex: 0, stableId: 'id1');
  final ch2s1 =
      const PdfTocItem(title: 'Ch2-S1', pageIndex: 3, stableId: 'id2s1');
  final ch2s2 =
      const PdfTocItem(title: 'Ch2-S2', pageIndex: 5, stableId: 'id2s2');
  final ch2 = PdfTocItem(
    title: 'Ch2',
    pageIndex: 2,
    stableId: 'id2',
    children: [ch2s1, ch2s2],
  );
  final ch3 = const PdfTocItem(title: 'Ch3', pageIndex: 8, stableId: 'id3');
  final noDest =
      const PdfTocItem(title: '無目的地章節', pageIndex: null, stableId: 'idNull');
  final entries = [ch1, ch2, ch3, noDest];

  group('findCurrentPath', () {
    test('currentPageIndex 為 null 時回傳空清單', () {
      expect(PdfTocNavigator.findCurrentPath(entries, null), isEmpty);
    });

    test('落在第一個頂層章節範圍內時，回傳只含該章節的路徑', () {
      expect(PdfTocNavigator.findCurrentPath(entries, 1), [ch1]);
    });

    test('落在有子章節的頂層章節、且已進入其第一個子項範圍時，回傳完整祖先路徑', () {
      expect(PdfTocNavigator.findCurrentPath(entries, 4), [ch2, ch2s1]);
    });

    test('落在最後一個頂層章節範圍內時，回傳只含該章節的路徑（不誤留前面章節的子項）', () {
      expect(PdfTocNavigator.findCurrentPath(entries, 9), [ch3]);
    });

    test('pageIndex 為 0（第一章開頭）時仍正確判定為該章節', () {
      expect(PdfTocNavigator.findCurrentPath(entries, 0), [ch1]);
    });

    test('全部節點 pageIndex 皆大於 currentPageIndex 時回傳空清單', () {
      expect(PdfTocNavigator.findCurrentPath(entries, -1), isEmpty);
    });

    test('pageIndex 為 null 的節點永遠不會被判定為目前章節', () {
      final onlyNullEntries = [noDest];
      expect(PdfTocNavigator.findCurrentPath(onlyNullEntries, 100), isEmpty);
    });

    test('父子節點指向同一頁碼時，回傳最深層（子節點）而非停在父節點（審查修正，'
        'review-plan-issue-5.md Minor #1：PDF 大綱常見「章節標題與該章第一節同頁」的寫法）', () {
      final child =
          const PdfTocItem(title: 'Chapter 1', pageIndex: 0, stableId: 'c1');
      final parent = PdfTocItem(
        title: 'Part One',
        pageIndex: 0,
        stableId: 'p1',
        children: [child],
      );
      expect(
        PdfTocNavigator.findCurrentPath([parent], 0),
        [parent, child],
      );
    });
  });
}
```

- [x] **Step 3: 執行測試確認失敗（`PdfTocNavigator` 尚未建立）**

Run: `flutter test test/reader/pdf_toc_navigator_test.dart`
Expected: FAIL，錯誤訊息類似 `Target of URI doesn't exist: 'package:elinkbook/reader/pdf_toc_navigator.dart'`。

- [x] **Step 4: 實作 `PdfTocNavigator`**

建立 `app/lib/reader/pdf_toc_navigator.dart`：

```dart
import 'pdf_toc_item.dart';

/// PDF 目錄樹狀清單的目前章節判定邏輯（epic-24-pdf-engine-rebuild Issue 5，
/// spec.md「PDF 目錄項目點擊後的行為...與 EPUB 既有目錄 Bottom Sheet 行為
/// 一致」）。演算法與 `TocNavigator.findCurrentPath`（`toc_navigator.dart`）
/// 完全對稱，差別只在比較鍵是頁碼（int，0-indexed）而非 EPUB 的
/// progression（double，0.0-1.0）——刻意不寫成共用泛型函式，兩邊呼叫端
/// 使用的型別（`PdfTocItem` vs `TocEntry`）與比較鍵型別（int vs double）
/// 都不同，泛型化不會減少程式碼量，只會增加閱讀成本。
class PdfTocNavigator {
  const PdfTocNavigator._();

  /// 找出讀者目前所在（或剛通過）的章節，回傳從樹根到該章節的完整祖先
  /// 路徑（含自身）。[currentPageIndex] 為 `null`（尚未收到任何
  /// `onPageChanged` 回報）或沒有任何節點的 `pageIndex <= currentPageIndex`
  /// 時，回傳空清單。`pageIndex == null` 的節點（大綱項目無有效目的地）
  /// 永遠不參與比較，比照 EPUB 版本對 `progression == null` 的既有語意。
  static List<PdfTocItem> findCurrentPath(
    List<PdfTocItem> entries,
    int? currentPageIndex,
  ) {
    if (currentPageIndex == null) return const [];
    List<PdfTocItem>? bestPath;
    void walk(List<PdfTocItem> nodes, List<PdfTocItem> path) {
      for (final node in nodes) {
        final newPath = [...path, node];
        final pageIndex = node.pageIndex;
        if (pageIndex != null && pageIndex <= currentPageIndex) {
          bestPath = newPath;
        }
        walk(node.children, newPath);
      }
    }

    walk(entries, const []);
    return bestPath ?? const [];
  }
}
```

- [x] **Step 5: 執行測試確認通過**

Run: `flutter test test/reader/pdf_toc_navigator_test.dart -v`
Expected: 8 項全數通過。

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_toc_item.dart app/lib/reader/pdf_toc_navigator.dart app/test/reader/pdf_toc_navigator_test.dart
git commit -m "feat(epic-24): 新增 PdfTocItem 與 PdfTocNavigator（PDF 目錄樹狀節點與目前章節判定）"
```

---

### Task 3: 巢狀大綱 PDF fixture + `PdfReaderView.loadTableOfContents`

**Files:**
- Create: `app/test/fixtures/sample_pdf_toc.pdf`
- Modify: `app/pubspec.yaml`（新增 asset 註冊，比照 `sample.pdf`／`sample_dual_page.pdf` 既有慣例）
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Test: `app/test/reader/pdf_reader_view_toc_test.dart`

**Interfaces:**
- Consumes: `PdfTocItem`（Task 2）。
- Produces: `static Future<List<PdfTocItem>> PdfReaderView.loadTableOfContents(GlobalKey<State<PdfReaderView>> key)`——Task 5 依賴此簽章。

- [x] **Step 1: 產生含巢狀大綱的 PDF fixture**

現行 `sample_multi_page.pdf`（Issue 1 產生）雖然已含一份「扁平」大綱（Chapter 1-5、無巢狀），不足以驗證「巢狀層級正確保留」這項驗收條件，需要一份真正含巢狀結構的 fixture。在 `app/test/fixtures/` 目錄下暫時建立 `_gen_sample_pdf_toc.py`：

```python
"""產生含巢狀大綱（Outline/Bookmark）樹的測試用 PDF，手動組裝 PDF 物件
（比照 epic-24 Issue 1 既有 sample_multi_page.pdf 產生腳本的技法），
不依賴任何第三方 PDF 函式庫。

樹狀結構（6 頁，0-indexed）：
  Part One (page 0)
    Chapter 1 (page 0)
    Chapter 2 (page 1)
  Part Two (page 2)
    Chapter 3 (page 2)
    Chapter 4 (page 3)
  Chapter 5 (page 4)          <- 頂層、無子項
  (page 5 無任何大綱項目指向，驗證「非每頁都在大綱中」的一般情況)
"""

def make_pdf():
    num_pages = 6
    objs = {}
    catalog_num = 1
    pages_num = 2
    outlines_num = 3
    font_num = 4
    page_nums = list(range(5, 5 + num_pages))
    content_nums = list(range(5 + num_pages, 5 + 2 * num_pages))

    outline_defs = [
        ("Part One", 0),
        ("Chapter 1", 0),
        ("Chapter 2", 1),
        ("Part Two", 2),
        ("Chapter 3", 2),
        ("Chapter 4", 3),
        ("Chapter 5", 4),
    ]
    outline_item_nums = list(range(5 + 2 * num_pages, 5 + 2 * num_pages + len(outline_defs)))

    tree_children = {0: [1, 2], 3: [4, 5]}
    tree_parent = {1: 0, 2: 0, 4: 3, 5: 3}
    top_level = [0, 3, 6]

    objs[catalog_num] = f"<< /Type /Catalog /Pages {pages_num} 0 R /Outlines {outlines_num} 0 R >>"
    objs[pages_num] = (
        f"<< /Type /Pages /Kids [{' '.join(f'{n} 0 R' for n in page_nums)}] /Count {num_pages} >>"
    )
    objs[outlines_num] = (
        f"<< /Type /Outlines /First {outline_item_nums[top_level[0]]} 0 R "
        f"/Last {outline_item_nums[top_level[-1]]} 0 R /Count {len(top_level)} >>"
    )

    for i in range(num_pages):
        pnum = page_nums[i]
        cnum = content_nums[i]
        objs[pnum] = (
            f"<< /Type /Page /Parent {pages_num} 0 R /MediaBox [0 0 612 792] "
            f"/Resources << /Font << /F1 {font_num} 0 R >> >> /Contents {cnum} 0 R >>"
        )

    objs[font_num] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"

    for i in range(num_pages):
        cnum = content_nums[i]
        text = f"(Page {i + 1} of {num_pages})"
        stream = f"BT /F1 24 Tf 72 700 Td {text} Tj ET".encode("latin-1")
        objs[cnum] = f"<< /Length {len(stream)} >>\nstream\n".encode("latin-1") + stream + b"\nendstream"

    for idx, (title, page_index) in enumerate(outline_defs):
        onum = outline_item_nums[idx]
        parent_idx = tree_parent.get(idx)
        parent_num = outline_item_nums[parent_idx] if parent_idx is not None else outlines_num
        siblings = tree_children[parent_idx] if parent_idx is not None else top_level
        pos = siblings.index(idx)
        parts = [f"/Title ({title})", f"/Parent {parent_num} 0 R"]
        if pos > 0:
            parts.append(f"/Prev {outline_item_nums[siblings[pos - 1]]} 0 R")
        if pos < len(siblings) - 1:
            parts.append(f"/Next {outline_item_nums[siblings[pos + 1]]} 0 R")
        children = tree_children.get(idx)
        if children:
            parts.append(f"/First {outline_item_nums[children[0]]} 0 R")
            parts.append(f"/Last {outline_item_nums[children[-1]]} 0 R")
            parts.append(f"/Count {len(children)}")
        parts.append(f"/Dest [{page_nums[page_index]} 0 R /Fit]")
        objs[onum] = "<< " + " ".join(parts) + " >>"

    buf = bytearray()
    buf += b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n"
    offsets = {}
    max_obj = max(objs.keys())
    for n in range(1, max_obj + 1):
        offsets[n] = len(buf)
        body = objs[n]
        if isinstance(body, bytes):
            buf += f"{n} 0 obj\n".encode("latin-1") + body + b"\nendobj\n"
        else:
            buf += f"{n} 0 obj\n{body}\nendobj\n".encode("latin-1")

    xref_offset = len(buf)
    buf += f"xref\n0 {max_obj + 1}\n".encode("latin-1")
    buf += b"0000000000 65535 f \n"
    for n in range(1, max_obj + 1):
        buf += f"{offsets[n]:010d} 00000 n \n".encode("latin-1")
    buf += f"trailer\n<< /Size {max_obj + 1} /Root {catalog_num} 0 R >>\nstartxref\n{xref_offset}\n%%EOF".encode("latin-1")
    return bytes(buf)


with open("sample_pdf_toc.pdf", "wb") as f:
    f.write(make_pdf())
```

Run（在 `app/test/fixtures/` 目錄下）：
```bash
python3 _gen_sample_pdf_toc.py && rm _gen_sample_pdf_toc.py
```
Expected: 產生 `sample_pdf_toc.pdf`（約 2.9KB），腳本本身執行後刪除、不進版本控制。

（本計畫撰寫階段已實際跑過這個腳本並用真實 `pdfrx` 驗證輸出——見下方 Step 2 附上的實測結果，不是未經測試的猜測。）

- [x] **Step 2: 登錄為 pubspec.yaml asset**

修改 `app/pubspec.yaml`，在既有 `- test/fixtures/sample_dual_page.pdf` 那一行之後新增一行：

```yaml
    - test/fixtures/sample_pdf_toc.pdf
```

- [x] **Step 3: 撰寫 `loadTableOfContents` 的失敗測試**

建立 `app/test/reader/pdf_reader_view_toc_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/pdf_toc_item.dart';

void main() {
  setUp(() => pdfrxInitialize());

  Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
    return tester.runAsync(() async {
      for (var i = 0; i < 30 && rendered() == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

  testWidgets('正確解析巢狀大綱，保留階層與頁碼（0-indexed）', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_pdf_toc.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final items = await tester.runAsync(
      () => PdfReaderView.loadTableOfContents(key),
    );

    expect(items, isNotNull);
    expect(items!.length, 3);
    expect(items[0].title, 'Part One');
    expect(items[0].pageIndex, 0);
    expect(items[0].children.length, 2);
    expect(items[0].children[0].title, 'Chapter 1');
    expect(items[0].children[0].pageIndex, 0);
    expect(items[0].children[1].title, 'Chapter 2');
    expect(items[0].children[1].pageIndex, 1);
    expect(items[1].title, 'Part Two');
    expect(items[1].children.length, 2);
    expect(items[1].children[0].pageIndex, 2);
    expect(items[1].children[1].pageIndex, 3);
    expect(items[2].title, 'Chapter 5');
    expect(items[2].pageIndex, 4);
    expect(items[2].children, isEmpty);

    final ids = <String>{};
    void collect(List<PdfTocItem> nodes) {
      for (final n in nodes) {
        expect(ids.add(n.stableId), isTrue, reason: 'stableId 須全域唯一');
        collect(n.children);
      }
    }

    collect(items);
  });

  testWidgets('無大綱的 PDF（sample.pdf）回傳空清單，不拋出例外', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final items = await tester.runAsync(
      () => PdfReaderView.loadTableOfContents(key),
    );

    expect(items, isEmpty);
  });

  testWidgets('State 尚未掛載（key 未對應任何 widget）時回傳空清單', (tester) async {
    final orphanKey = GlobalKey<State<PdfReaderView>>();
    final items = await PdfReaderView.loadTableOfContents(orphanKey);
    expect(items, isEmpty);
  });
}
```

- [x] **Step 4: 執行測試確認失敗**

Run: `flutter test test/reader/pdf_reader_view_toc_test.dart`
Expected: FAIL，`PdfReaderView.loadTableOfContents` 尚未定義。

- [x] **Step 5: 實作 `PdfReaderView.loadTableOfContents`**

修改 `app/lib/reader/pdf_reader_view.dart`，在檔案頂部 import 區塊新增：

```dart
import 'pdf_toc_item.dart';
```

在 `class PdfReaderView` 內、既有 `static void refreshAnnotations(...)` 靜態方法之後新增：

```dart
  /// 解析 PDF 內建大綱（Outline／Bookmark），一次性轉換為 [PdfTocItem]
  /// 樹狀結構（epic-24-pdf-engine-rebuild Issue 5）。文件尚未開啟完成
  /// （State 的 `_document` 為 null）或 [key] 尚未掛載時回傳空清單，比照
  /// [jumpToPage] 等既有靜態 helper 的靜默忽略慣例。
  static Future<List<PdfTocItem>> loadTableOfContents(
    GlobalKey<State<PdfReaderView>> key,
  ) async {
    final state = key.currentState;
    if (state is! _PdfReaderViewState) return const [];
    return state._loadTableOfContents();
  }
```

在 `class _PdfReaderViewState` 內、既有 `_setAnnotations` 方法附近新增：

```dart
  /// `PdfOutlineNode.dest?.pageNumber` 是 1-indexed（已查證
  /// `pdfrx_engine-0.4.5` 原始碼：`pdf_viewer.dart` 內部一律以
  /// `dest.pageNumber - 1` 索引 `document.pages[]`），換算為本專案既有的
  /// 0-indexed `pageIndex` 慣例。`stableId` 用遞增計數器（前序走訪順序）
  /// 產生，保證整棵樹唯一，不依賴頁碼或標題（大綱可能有多個節點指向
  /// 同一頁）——計數器刻意宣告為本方法內的區域變數（透過巢狀函式
  /// `convert` 閉包捕捉），不放在 State 欄位：若放在 State 欄位，
  /// `loadTableOfContents` 這個 public static API 被短時間內重入呼叫時
  /// （例如測試或未來呼叫端不慎重複觸發），後一次呼叫的重置會汙染前一次
  /// 呼叫尚在進行中的走訪計數，導致 `stableId` 不再保證唯一（審查修正，
  /// review-plan-issue-5.md Important #1）。改為區域變數後，每次呼叫都有
  /// 各自獨立的計數器，天生具備重入安全性。
  Future<List<PdfTocItem>> _loadTableOfContents() async {
    final document = _document;
    if (document == null) return const [];
    final outline = await document.loadOutline();
    var tocIdCounter = 0;

    List<PdfTocItem> convert(List<PdfOutlineNode> nodes) {
      return [
        for (final node in nodes)
          PdfTocItem(
            title: node.title,
            pageIndex: node.dest == null ? null : node.dest!.pageNumber - 1,
            stableId: 'pdf_toc_${tocIdCounter++}',
            children: convert(node.children),
          ),
      ];
    }

    return convert(outline);
  }
```

- [x] **Step 6: 執行測試確認通過**

Run: `flutter test test/reader/pdf_reader_view_toc_test.dart -v`
Expected: 3 項全數通過。

（本計畫撰寫階段已實際執行過與 Step 3 等價的驗證腳本，真實輸出：`Part One`/`dest.pageNumber=1`/2 children（`Chapter 1`→1、`Chapter 2`→2）；`Part Two`/`dest.pageNumber=3`/2 children；`Chapter 5`/`dest.pageNumber=5`/0 children——與 Step 3 測試斷言的 0-indexed 換算值（0/0/1/2/2/3/4）完全吻合。）

- [x] **Step 7: 執行既有 PDF 測試確認零回歸**

Run: `flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_selection_test.dart test/reader/pdf_reader_view_dual_page_test.dart test/reader/pdf_reader_view_filters_test.dart -v`
Expected: 全數通過，無新增失敗。

- [x] **Step 8: Commit**

```bash
git add app/test/fixtures/sample_pdf_toc.pdf app/pubspec.yaml app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_toc_test.dart
git commit -m "feat(epic-24): PdfReaderView.loadTableOfContents——解析 pdfrx 大綱為 PdfTocItem 樹"
```

---

### Task 4: `TocBottomSheet` 泛化以同時支援 EPUB／PDF

**Files:**
- Modify: `app/lib/screens/toc_bottom_sheet.dart`
- Modify: `app/test/screens/toc_bottom_sheet_test.dart`（僅一行必要修正，見 Step 3）
- Test: `app/test/screens/toc_bottom_sheet_pdf_test.dart`（新檔案，PDF 專屬情境）

**Interfaces:**
- Consumes: `BookTocItem`（Task 1）、`PdfTocItem`（Task 2）。
- Produces: `TocBottomSheet` 建構參數型別由 `List<TocEntry>`/`Set<TocEntry>`/`TocEntry?`/`ValueChanged<TocEntry>` 全部加寬為 `BookTocItem` 對應版本，其餘參數名稱/型別不變——Task 5 依賴這個加寬後的簽章。

- [x] **Step 1: 確認既有測試現況（作為零回歸基準）**

Run: `flutter test test/screens/toc_bottom_sheet_test.dart -v`
Expected: 既有 6 項全數通過（修改前的基準線）。

- [x] **Step 2: 修改 `TocBottomSheet` 型別與內部邏輯**

修改 `app/lib/screens/toc_bottom_sheet.dart`。在檔案開頭 import 區塊新增：

```dart
import '../reader/book_toc_item.dart';
import '../reader/pdf_toc_item.dart';
```

`TocEntry` 型別欄位改為 `BookTocItem`（`entries`／`initiallyExpandedEntries`／`currentEntry`／`onEntrySelected`），其餘欄位（`totalCharacterCountListenable`／`resolved`）保持不變：

```dart
class TocBottomSheet extends StatefulWidget {
  final List<BookTocItem> entries;

  /// 開啟當下的預設展開集合（通常是 `TocNavigator.findCurrentPath`／
  /// `PdfTocNavigator.findCurrentPath` 的回傳值），僅影響初始畫面；使用者
  /// 點擊展開/收起按鈕後由本 widget 自行管理後續狀態，不會回寫給呼叫端。
  final Set<BookTocItem> initiallyExpandedEntries;

  /// 目前所在章節（用於高亮），`null` 代表尚無法判斷。
  final BookTocItem? currentEntry;

  /// 全書字元數快取，`null` 時所有 EPUB 項目的頁碼顯示佔位符（`…`）；
  /// PDF 項目不使用此欄位（頁碼在解析大綱當下就已知，見
  /// `PdfReaderView._loadTableOfContents`），PDF 呼叫端可傳入任何值
  /// （建議 `ValueNotifier<int?>(null)`）。
  final ValueListenable<int?> totalCharacterCountListenable;

  /// 目前生效的版面參數，供換算「每螢幕可容納字元數」（僅 EPUB 項目使用，
  /// 見 [_buildEntryRow]）。
  final ResolvedPreferences resolved;

  final ValueChanged<BookTocItem> onEntrySelected;

  const TocBottomSheet({
    super.key,
    required this.entries,
    required this.initiallyExpandedEntries,
    required this.currentEntry,
    required this.totalCharacterCountListenable,
    required this.resolved,
    required this.onEntrySelected,
  });

  @override
  State<TocBottomSheet> createState() => _TocBottomSheetState();
}
```

`_FlatTocRow` 與 `_TocBottomSheetState` 內部型別同步加寬：

```dart
class _FlatTocRow {
  final BookTocItem entry;
  final int depth;

  const _FlatTocRow({required this.entry, required this.depth});
}

class _TocBottomSheetState extends State<TocBottomSheet> {
  late Set<BookTocItem> _expanded;
  late List<_FlatTocRow> _visibleRows;

  @override
  void initState() {
    super.initState();
    _expanded = Set.of(widget.initiallyExpandedEntries);
    _visibleRows = _flatten(widget.entries, depth: 0);
  }

  List<_FlatTocRow> _flatten(List<BookTocItem> nodes, {required int depth}) {
    final rows = <_FlatTocRow>[];
    for (final node in nodes) {
      rows.add(_FlatTocRow(entry: node, depth: depth));
      if (node.children.isNotEmpty && _expanded.contains(node)) {
        rows.addAll(_flatten(node.children, depth: depth + 1));
      }
    }
    return rows;
  }

  void _toggleExpanded(BookTocItem node) {
    setState(() {
      if (_expanded.contains(node)) {
        _expanded.remove(node);
      } else {
        _expanded.add(node);
      }
      _visibleRows = _flatten(widget.entries, depth: 0);
    });
  }
```

`build()` 方法新增「無目錄資料」空清單狀態（entries 為空時多顯示一列提示文字，不影響既有非空情境的 `itemCount`/索引對應）：

```dart
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<int?>(
        valueListenable: widget.totalCharacterCountListenable,
        builder: (context, totalCharacterCount, _) {
          final isEmpty = widget.entries.isEmpty;
          return ListView.builder(
            key: const Key('toc_bottom_sheet_list'),
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            // +1：索引 0 固定是標題列；entries 為空時額外 +1 顯示提示列；
            // 其餘索引對應 _visibleRows[index - 1]。
            itemCount: _visibleRows.length + 1 + (isEmpty ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('📖 目錄',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        key: const Key('toc_bottom_sheet_close_button'),
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                );
              }
              if (isEmpty && index == 1) {
                return const Padding(
                  key: Key('toc_bottom_sheet_empty_text'),
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('本書無目錄資料')),
                );
              }
              return _buildEntryRow(_visibleRows[index - 1], totalCharacterCount);
            },
          );
        },
      ),
    );
  }
```

`_buildEntryRow` 依節點實際型別分流頁碼顯示邏輯（EPUB 分支逐字保留既有邏輯，PDF 分支為新增）、Key 生成改用 `stableId`：

```dart
  Widget _buildEntryRow(_FlatTocRow row, int? totalCharacterCount) {
    final node = row.entry;
    final isCurrent = identical(node, widget.currentEntry);
    final String pageLabel;
    if (node is TocEntry) {
      // 審查修正：totalCharacterCount 已就緒不代表這個節點本身就有可用的
      // progression——原生端兩層 fallback（locatorFromLink() 自帶的
      // totalProgression、比對 positions() 的近似值）都可能查無資料，此時
      // node.progression 仍是 null。EpubPageEstimator.estimateCurrentPage
      // 對 progression == null 的既有語意是回傳第 1 頁（給「尚未收到任何
      // onLocatorChanged 回報」這個完全不同的情境使用），若不在這裡額外判斷
      // node.progression == null，會讓「查無位置」的章節被誤植成「第 1
      // 頁」，比顯示佔位符更誤導使用者。
      pageLabel = (totalCharacterCount == null || node.progression == null)
          ? '…'
          : EpubPageEstimator.estimateCurrentPage(
              progression: node.progression,
              totalPages: EpubPageEstimator.estimateTotalPages(
                totalCharacterCount: totalCharacterCount,
                charsPerScreen: EpubPageEstimator.estimateCharsPerScreen(
                  fontSize: widget.resolved.fontSize,
                  lineHeight: widget.resolved.lineHeight,
                  paragraphSpacing: widget.resolved.paragraphSpacing,
                  pageMargins: widget.resolved.pageMargins,
                ),
              ),
            ).toString();
    } else if (node is PdfTocItem) {
      // PDF 大綱項目的目標頁碼在解析當下就已知（見
      // PdfReaderView._loadTableOfContents），不像 EPUB 需要背景估算，
      // 不使用 totalCharacterCount／EpubPageEstimator。
      pageLabel = node.pageIndex == null ? '…' : (node.pageIndex! + 1).toString();
    } else {
      pageLabel = '…';
    }

    return Padding(
      padding: EdgeInsets.only(left: row.depth * 16),
      child: ListTile(
        key: Key('toc_entry_${node.stableId}'),
        title: Text(
          node.title,
          style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
        selected: isCurrent,
        onTap: () => widget.onEntrySelected(node),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pageLabel, key: Key('toc_entry_page_${node.stableId}')),
            if (node.children.isNotEmpty)
              IconButton(
                key: Key('toc_entry_expand_${node.stableId}'),
                icon: Icon(
                  _expanded.contains(node) ? Icons.expand_less : Icons.expand_more,
                ),
                onPressed: () => _toggleExpanded(node),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [x] **Step 3: 修正既有測試檔案中唯一因型別加寬而不相容的一行**

`app/test/screens/toc_bottom_sheet_test.dart` 第 105-125 行「點選項目標題觸發 onEntrySelected 並傳遞正確的 TocEntry」這則測試宣告 `TocEntry? selected;` 並在回呼中賦值——`onEntrySelected` 型別加寬為 `ValueChanged<BookTocItem>` 後，回呼參數的靜態型別是 `BookTocItem`，賦值給 `TocEntry?` 區域變數會編譯錯誤。這是型別加寬後**唯一**需要修正的一行（其餘 5 則測試傳入的 `List<TocEntry>`／`Set<TocEntry>`／`TocEntry` 皆可透過 Dart 協變泛型直接滿足加寬後的參數型別，不需要修改）：

修改該測試內：
```dart
    TocEntry? selected;
```
為：
```dart
    BookTocItem? selected;
```

檔案開頭新增 `import 'package:elinkbook/reader/book_toc_item.dart';`。

- [x] **Step 4: 執行既有測試確認零回歸**

Run: `flutter test test/screens/toc_bottom_sheet_test.dart -v`
Expected: 6 項全數通過，與 Step 1 基準線完全一致（僅型別修正，無行為變更）。

- [x] **Step 5: 撰寫 PDF 專屬情境的失敗測試**

建立 `app/test/screens/toc_bottom_sheet_pdf_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_toc_item.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';

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

void main() {
  final ch1 = const PdfTocItem(title: 'Part One', pageIndex: 0, stableId: 'p0');
  final ch1s1 =
      const PdfTocItem(title: 'Chapter 1', pageIndex: 0, stableId: 'p1');
  final ch1WithChild = PdfTocItem(
    title: 'Part One',
    pageIndex: 0,
    stableId: 'p0',
    children: [ch1s1],
  );
  final noDest =
      const PdfTocItem(title: '無目的地章節', pageIndex: null, stableId: 'pNull');

  testWidgets('PDF 節點頁碼顯示為 pageIndex+1（1-indexed），不使用 EpubPageEstimator',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: [ch1WithChild],
          initiallyExpandedEntries: {ch1WithChild},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(
      tester.widget<Text>(find.byKey(const Key('toc_entry_page_p0'))).data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('toc_entry_page_p1'))).data,
      '1',
    );
  });

  testWidgets('pageIndex 為 null 的 PDF 節點顯示佔位符', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: [noDest],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(
      tester.widget<Text>(find.byKey(const Key('toc_entry_page_pNull'))).data,
      '…',
    );
  });

  testWidgets('點選 PDF 項目觸發 onEntrySelected 並傳遞正確的 PdfTocItem',
      (tester) async {
    PdfTocItem? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: [ch1],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (entry) => selected = entry as PdfTocItem,
        ),
      ),
    ));

    await tester.tap(find.text('Part One'));
    await tester.pump();

    expect(selected, ch1);
  });

  testWidgets('entries 為空清單時顯示提示文字，不拋出例外', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: const [],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(find.byKey(const Key('toc_bottom_sheet_empty_text')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [x] **Step 6: 執行測試確認通過**

Run: `flutter test test/screens/toc_bottom_sheet_pdf_test.dart -v`
Expected: 4 項全數通過。

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/toc_bottom_sheet.dart app/test/screens/toc_bottom_sheet_test.dart app/test/screens/toc_bottom_sheet_pdf_test.dart
git commit -m "feat(epic-24): TocBottomSheet 泛化為消費 BookTocItem，同時支援 EPUB／PDF（EPUB 零回歸）"
```

---

### Task 5: `ReaderScreen` 接上 PDF 目錄背景載入與 `openPdfToc` 測試 seam

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: `PdfTocItem`／`PdfTocNavigator`（Task 2）、`PdfReaderView.loadTableOfContents`（Task 3）、加寬後的 `TocBottomSheet`（Task 4）。
- Produces: `static void ReaderScreen.openPdfToc(GlobalKey<State<ReaderScreen>> key)`——測試與（Issue 8 之後的）FAB 按鈕皆呼叫此 static helper。

- [x] **Step 1: 在 `_ReaderScreenState` 新增欄位與載入觸發**

修改 `app/lib/screens/reader_screen.dart`，在既有 `List<TocEntry> _tocEntries = const [];`／`bool _tocLoaded = false;` 欄位附近新增：

```dart
  List<PdfTocItem> _pdfTocEntries = const [];
  bool _pdfTocLoaded = false;
```

檔案開頭新增 import：

```dart
import '../reader/pdf_toc_item.dart';
import '../reader/pdf_toc_navigator.dart';
```

修改既有 `_handlePageRendered()` 方法（`app/lib/screens/reader_screen.dart:858`），在既有 PDF 劃線/備註載入判斷式之後新增對稱的 TOC 載入判斷式：

```dart
  void _handlePageRendered() {
    if (!mounted) return;
    _openBookTimeoutTimer?.cancel();
    setState(() => _state = _RenderState.rendered);
    // epic-6-annotations Issue 3：PDF 書籍開啟成功後載入既有劃線/備註並
    // 送給原生端渲染。與 EPUB 的觸發點（_handleLayoutResolved，見 Issue 2
    // Task 10 Step 7）刻意不同——PDF 沒有對應的版面解析回呼，本方法
    // （onPageRendered）是 PDF 開書成功的既有訊號，兩種格式共用同一個
    // _annotationsLoaded 旗標（單一書籍只會是其中一種格式，不會重複觸發）。
    if (detectBookFormat(widget.filePath) == BookFormat.pdf &&
        !_annotationsLoaded &&
        widget.highlightsRepository != null &&
        widget.notesRepository != null) {
      _annotationsLoaded = true;
      _reloadPdfAnnotationsAndSync();
    }
    // epic-24-pdf-engine-rebuild Issue 5：PDF 目錄背景載入，比照上方
    // _annotationsLoaded 的既有旗標模式（先設 true 再發起非同步呼叫，避免
    // 短時間內重複觸發）。與 EPUB 的 _tocLoaded 觸發點
    // （_handleFoliateLayoutResolved）刻意不同——PDF 同樣沒有版面解析
    // 回呼，onPageRendered 是 PDF 開書成功的唯一既有訊號。
    if (detectBookFormat(widget.filePath) == BookFormat.pdf && !_pdfTocLoaded) {
      _pdfTocLoaded = true;
      PdfReaderView.loadTableOfContents(_pdfReaderViewKey).then((items) {
        if (!mounted) return;
        setState(() => _pdfTocEntries = items);
      });
    }
  }
```

- [x] **Step 2: 新增 `_openPdfToc()` 與 static 測試 seam**

在既有 `_openToc()` 方法（`app/lib/screens/reader_screen.dart:760`）之後新增：

```dart
  /// PDF 版本的目錄開啟（epic-24-pdf-engine-rebuild Issue 5）：本工單只
  /// 完成資料載入與 Bottom Sheet 顯示邏輯本身，比照 Issue 4 書籤 toggle
  /// 的既有先例（「toggle 對應的 FAB 按鈕留給 Issue 8 統一接線」）——目前
  /// 沒有對應的可見按鈕，只能透過 [ReaderScreen.openPdfToc] 這個測試 seam
  /// 觸發，UI 尚無法直接互動；FAB 接線見 Issue 8。
  ///
  /// 背景載入尚未完成（[_pdfTocLoaded] 仍為 false）時直接忽略，比照 EPUB
  /// 「reader_toc_button」`onPressed: null` 的既有防呆語意（見
  /// _buildAppBarActions case BookFormat.epub 對 _tocLoaded 的既有判斷）。
  void _openPdfToc() {
    if (!_pdfTocLoaded) return;
    final currentPath =
        PdfTocNavigator.findCurrentPath(_pdfTocEntries, _pdfPageInfo?.pageIndex);
    _showThemedModalBottomSheet<void>(
      builder: (_) => TocBottomSheet(
        entries: _pdfTocEntries,
        initiallyExpandedEntries: currentPath.toSet(),
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        totalCharacterCountListenable: ValueNotifier<int?>(null),
        resolved: _resolved!,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          final pageIndex = (entry as PdfTocItem).pageIndex;
          if (pageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, pageIndex);
          }
        },
      ),
    );
  }
```

在 `class ReaderScreen` 內、既有 `static void togglePdfBookmark(...)`（`app/lib/screens/reader_screen.dart:168`）之後新增：

```dart
  /// 供測試（Issue 5 範圍：目錄載入/跳轉邏輯已完成，對應 FAB 按鈕留給
  /// Issue 8）安全呼叫 [_ReaderScreenState._openPdfToc] 的強型別 static
  /// helper，比照 [togglePdfBookmark] 既有模式。[key] 對應的 State 若尚未
  /// 掛載，靜默忽略。
  static void openPdfToc(GlobalKey<State<ReaderScreen>> key) {
    final state = key.currentState;
    if (state is _ReaderScreenState) {
      state._openPdfToc();
    }
  }
```

- [x] **Step 3: 修改既有 `_openToc()`（EPUB）的 `onEntrySelected` 回呼**

`_openToc()`（`app/lib/screens/reader_screen.dart:760`）的 `entries`／`initiallyExpandedEntries`／`currentEntry` 三個參數傳入值型別不變（仍是 `List<TocEntry>`／`Set<TocEntry>`／`TocEntry?`，透過 Dart 協變泛型直接滿足 `TocBottomSheet` 加寬後的參數型別，不需要修改），**只有** `onEntrySelected` 回呼內部需要一次向下轉型（因為回呼參數的靜態型別從 `TocEntry` 加寬為 `BookTocItem`）：

```dart
  void _openToc() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    _showThemedModalBottomSheet<void>(
      builder: (_) => TocBottomSheet(
        entries: _tocEntries,
        initiallyExpandedEntries: currentPath.toSet(),
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        totalCharacterCountListenable: _totalCharacterCountNotifier,
        resolved: _resolved!,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          _jumpToEpubLocator((entry as TocEntry).locatorJson);
        },
      ),
    );
  }
```

- [x] **Step 4: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 5: 撰寫 `openPdfToc` 測試 seam 的失敗測試**

在 `app/test/screens/reader_screen_test.dart` 既有 PDF 書籤 toggle 兩則測試（約 `:5498` 起）之後新增：

```dart
  testWidgets(
      'PDF 開書後背景載入目錄；載入完成前 openPdfToc 無作用，完成後可開啟 TocBottomSheet',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_pdf_toc.pdf',
          bookId: 'b_pdf_toc',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 目錄背景載入尚未完成（onPageRendered 尚未真正觸發），此時呼叫應
    // 無作用。
    ReaderScreen.openPdfToc(key);
    await tester.pump();
    expect(find.byType(TocBottomSheet), findsNothing);

    // 等待 pdfrx 真實載入 PDF（30 次輪詢，比照本檔案既有 PDF 測試慣例）。
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    // _pdfTocLoaded 由 loadTableOfContents() 這個 async 呼叫的 .then()
    // callback 設定，需要多一次 pump 讓其 microtask 完成、觸發 setState。
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsOneWidget);
    expect(find.text('Part One'), findsOneWidget);
    expect(find.text('Chapter 5'), findsOneWidget);
  });

  testWidgets('點選 PDF 目錄項目後正確跳轉頁面並關閉 Bottom Sheet', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_pdf_toc.pdf',
          bookId: 'b_pdf_toc_jump',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    // 開書完成後頁尾顯示第 1 頁（比照本檔案既有 PDF 頁尾測試慣例，見
    // reader_footer_progress_text 既有用法）。
    expect(
      tester
          .widget<Text>(find.byKey(const Key('reader_footer_progress_text')))
          .data,
      '1/6',
    );

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TocBottomSheet), findsOneWidget);

    await tester.tap(find.text('Chapter 5'));
    await tester.pump();

    expect(find.byType(TocBottomSheet), findsNothing, reason: '點選項目後應關閉 Bottom Sheet');

    // Chapter 5 的大綱目的地是 pageIndex=4（見 Task 3 fixture 生成腳本），
    // 頁尾應顯示第 5 頁（1-indexed）——這是跳轉是否真的發生、而非只是
    // Bottom Sheet 關閉的直接證據。真實 pdfrx 頁面切換需要跑完一輪背景
    // 處理，等待方式沿用本檔案既有的 30 次輪詢慣例（本計畫撰寫階段已用
    // 等價的 ZoneAction.nextPage 情境實測驗證過這個等待模式確實足夠，見
    // plan-issue-5.md 撰寫紀錄）。
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(
      tester
          .widget<Text>(find.byKey(const Key('reader_footer_progress_text')))
          .data,
      '5/6',
    );
  });

  testWidgets('無大綱的 PDF 開啟後，openPdfToc 顯示空清單提示而非崩潰', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_toc_empty',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsOneWidget);
    expect(find.byKey(const Key('toc_bottom_sheet_empty_text')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
```

檔案開頭確認已 import（若尚未 import 則新增）：
```dart
import 'package:elinkbook/reader/pdf_toc_item.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';
```

「跳轉是否真的發生」改用頁尾 `reader_footer_progress_text` 的實際顯示文字驗證，而非嘗試從測試端攔截 `PdfReaderView.jumpToPage` 的內部呼叫（`PdfReaderView` 沒有可供測試查詢「目前頁碼」的介面，`onPageChanged` 是原生端→Dart 的單向回報，不是查詢管道）——這是本計畫撰寫階段實際跑過的驗證手法（以等價的 `ZoneAction.nextPage` 情境驗證：真實頁面切換經過 30 次輪詢等待後，`reader_footer_progress_text` 確實從 `1/6` 更新為 `2/6`），不是未經測試的猜測。

- [x] **Step 6: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "PDF" --reporter expanded`
Expected: 新增 3 項＋既有 PDF 相關測試全數通過。

- [x] **Step 7: 執行既有「目錄入口按鈕不存在」測試確認零回歸**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "目錄入口按鈕不存在"`
Expected: 通過（本工單未新增 `Key('reader_toc_button')` 給 PDF，此測試不需修改）。

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-24): ReaderScreen 接上 PDF 目錄背景載入與 openPdfToc 測試 seam"
```

---

### Task 6: 端對端驗證

**Files:** 無新增/修改，純驗證。

- [x] **Step 1: 全量 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 2: Issue 5 相關測試檔案合併執行三次，確認無間歇性失敗**

Run（重複 3 次）：
```bash
flutter test test/reader/toc_entry_test.dart test/reader/toc_navigator_test.dart \
  test/reader/pdf_toc_navigator_test.dart test/reader/pdf_reader_view_toc_test.dart \
  test/screens/toc_bottom_sheet_test.dart test/screens/toc_bottom_sheet_pdf_test.dart \
  test/screens/reader_screen_test.dart
```
Expected: 3 次執行皆全數通過（比照 Issue 4 審查發現 Timer 競態的教訓，合併執行才能真正驗證跨檔案資源競態，不能只信任單檔案執行結果）。

- [x] **Step 3: 全專案測試套件**

Run: `flutter test`
Expected: 全數通過，通過總數應為 Issue 4 合併時的 135（`reader_screen_test.dart` 單檔）＋全專案基準之上，新增本工單新增的測試數（Task 1 起算：Task1 +2、Task2 +8、Task3 +3、Task4 +4、Task5 +3，共 +20，另加 `toc_entry_test.dart`／`toc_navigator_test.dart` 本身既有數量）。

- [x] **Step 4: 對照 `spec.md`／`issues.md` Issue 5 驗收條件逐項自我檢查**

逐項核對 `docs/epics/epic-24-pdf-engine-rebuild/issues.md` Issue 5 的 Acceptance criteria：
- `BookTocItem` 抽象介面完成，EPUB 既有目錄 Bottom Sheet 改為消費該介面，EPUB 既有目錄相關測試全數維持通過（零回歸）——Task 1／Task 4。
- PDF 端正確解析大綱（`loadOutline()`），轉換為 `BookTocItem` 樹狀結構，巢狀層級正確保留——Task 3。
- 點擊 PDF 目錄項目正確跳轉至對應頁面——Task 5。
- 目錄背景載入完成前，目錄相關互動正確停用（防呆）——Task 5（`_openPdfToc()` 的 `if (!_pdfTocLoaded) return;` 防呆）。
- 無大綱的 PDF（例如掃描件）目錄為空清單時，UI 有合理呈現（非例外崩潰）——Task 4（空清單提示文字）／Task 5。
- 單元測試：`flutter test` 對含大綱的 fixture 驗證解析結果與跳轉行為；對既有 EPUB 目錄測試確認零回歸——Task 3／Task 4／Task 5。
- `flutter analyze` 乾淨、`flutter test` 全數通過——Step 1／Step 3。

- [x] **Step 5: 更新本工單計畫檔案的完成狀態**

回頭把本檔案（`docs/epics/epic-24-pdf-engine-rebuild/plans/plan-issue-5.md`）所有已完成 Task 的 `- [ ]` 改為 `- [x]`（比照 CLAUDE.md「Task 的 Step 完成後即時反映進度」的既有慣例）。

- [x] **Step 6: 提交本次驗證的追蹤性 commit（若 Step 5 有變更）**

```bash
git add docs/epics/epic-24-pdf-engine-rebuild/plans/plan-issue-5.md
git commit -m "docs(epic-24): plan-issue-5 全部 Task 標記完成"
```

（後續發 PR／合併／更新 `docs/epics.md`／`issues.md`／`CLAUDE.md` 進度，比照 Issue 1-4 已建立的既有流程，屬本計畫執行完成之後的下一步，不在本計畫範圍內。）
