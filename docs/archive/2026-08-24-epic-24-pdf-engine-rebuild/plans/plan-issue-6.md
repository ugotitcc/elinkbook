# Epic 24 Issue 6 — 內文搜尋 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 在已開啟的 PDF 文件內搜尋文字，找出所有符合位置並在頁面上高亮標示，支援「上一個／下一個」逐一跳轉瀏覽；搜尋 UI 掛載於 Issue 5 建立的目錄 Bottom Sheet「搜尋」分頁。

**Architecture:** 直接使用 `pdfrx` 的低階 `PdfDocument.pages[i].loadStructuredText()` ＋ `PdfPageText.allMatches()` API（**不**使用 `pdfrx` 提供的高階 `PdfTextSearcher`／`PdfViewerController.useDocument` 組合——本計畫撰寫階段已實測發現後者在 `flutter test` 的 fake-async 環境下會整個測試卡死不回應，且該組合本身還會引入額外的建構時機防呆與裁切模式座標不相容問題）。搜尋結果換算為本專案既有的 `PercentRect`（0-1 相對頁面座標）格式後，透過與劃線/備註（Issue 4）完全相同的 `pageOverlaysBuilder`／裁切相對轉換管線疊加渲染——這個選擇讓搜尋高亮在裁切模式下**天生正確**，不需要額外特殊處理。

**Tech Stack:** Flutter/Dart、`pdfrx`（`PdfPage.loadStructuredText()` → `PdfPageText`，`PdfPageText.allMatches(Pattern, {caseInsensitive})` → `Stream<PdfPageTextRange>`，`PdfPageTextRange.bounds` 為 `PdfRect`——PDF points 座標、左下角原點、`top >= bottom`）、既有 `flutter_test` 對真實 PDF fixture 驗證。

## Global Constraints

- **不使用 `PdfTextSearcher`／`PdfViewerController.useDocument`**：本計畫撰寫階段實測驗證過，透過 `PdfViewer.file(...)` + `PdfTextSearcher(controller)` 在 `testWidgets` 環境下呼叫 `startTextSearch()` 會導致測試永久卡死（即使包在 `tester.runAsync()` 內）；改用 `PdfDocument.openFile()` 已持有的 `_document` 直接呼叫 `page.loadStructuredText()`／`PdfPageText.allMatches()`（純 `test()`，非 `testWidgets()`，已實測驗證可正常運作且速度極快）不會有此問題，理由與既有 `_recomputeOverlay`／`_detectCropRect`（Issue 3）已經在同一個 State 內穩定運作的 `page.render()` 呼叫模式一致。
- **PDF points → `PercentRect` 座標轉換**：`PdfRect` 是左下角原點、Y 軸向上（`top >= bottom`）；`PercentRect`（本專案既有慣例，`percent_rect.dart`）是左上角原點、Y 軸向下（`top <= bottom`，比照 `Rect.fromLTRB` 語意）。轉換公式：`newTop = 1 - pdfRect.top / pageHeight`、`newBottom = 1 - pdfRect.bottom / pageHeight`、`newLeft = pdfRect.left / pageWidth`、`newRight = pdfRect.right / pageWidth`。
- **裁切模式相容性**：搜尋高亮透過 `_buildProcessedOverlay`（`pdf_reader_view.dart:599`）既有的 `pageOverlaysBuilder` 管線疊加，比照既有劃線/備註（`_annotations`）的作法呼叫 `originalToCropRelativePercent(rect:, cropRect:)`（`pdf_selection_geometry.dart`，Issue 4 既有函式，本計畫不新增）——裁切啟用時完全落在裁切範圍外的符合結果不渲染（回傳 `null`），落在範圍內的正確位移。**不使用** `pdfrx` 的 `pagePaintCallbacks`／`pageTextMatchPaintCallback`（那組 API 假設 `pageRect.size` 等於整頁縮放後尺寸，裁切模式下該假設不成立，會畫出錯位的高亮）。
- **`TocBottomSheet` 與 `ReaderScreen` 解耦的既有設計原則維持不變**（Issue 5 docstring）：`TocBottomSheet` 不知道搜尋分頁裡放的是什麼，只負責把呼叫端傳入的 `Widget?` 放進分頁籤殼層第三格。
- **搜尋範圍限定單一已開啟 PDF 文件內**，與全書庫全文檢索（FTS5，Backlog）無關、不整合。
- **測試策略**：一律用 `flutter test` 對真實 PDF fixture 驗證，優先重用既有 fixture（`sample_multi_page.pdf` 每頁皆有 `"Page N of 5 -- searchable keyword ELINKBOOK"` 文字，已實測確認 `loadStructuredText()`／`allMatches()` 可正確擷取比對；`sample.pdf` 已確認為空文字層，可直接用於「無結果」情境），不需要新增 fixture。
- **`flutter analyze` 乾淨、每個 Task 結束後相關測試全數通過**是每個 Task 的隱含驗收條件。

---

## 與計畫撰寫階段實測發現相關的技術澄清

1. **`PdfTextSearcher` 卡死問題已實測重現三次**（含一次在殺掉所有殘留 `dart`/`flutter_tester` 處理程序、確認無資源競爭後乾淨重跑，結果相同），卡在 `startTextSearch()` 呼叫之後，即使該呼叫已包在 `tester.runAsync()` 內。改用 `PdfDocument.openFile()` 直接呼叫 `page.loadStructuredText()`／`PdfPageText.allMatches()`（跳過 `PdfViewer`／`PdfViewerController` 整條路徑）後，改用單純 `test()`（非 `testWidgets()`）驗證，**瞬間完成、無任何延遲**，對 `sample_multi_page.pdf` 5 頁各自正確找到 1 筆符合（總計 5 筆），輸出：
   ```
   page 1 fullText="Page 1 of 5 -- searchable keyword ELINKBOOK"
   page 1 matches=1
   ...
   totalMatches=5
   ```
   這證實問題出在 `PdfTextSearcher`／`PdfViewerController` 這條路徑本身（很可能與其內部的 `useDocument` 重入呼叫或 `PdfViewer` 內部渲染管線的 Timer 排程在 fake-async 環境下的交互有關，未進一步深究根因，因為本計畫已改用不受影響的替代方案），不是本專案程式碼或 fixture 的問題——**不需要、也不應該在實作階段重新嘗試 `PdfTextSearcher` 路線**。
2. **裁切模式相容性問題透過重用既有管線自然解決**：閱讀 `_buildProcessedOverlay`（`pdf_reader_view.dart:599-647`）原始碼後發現，既有劃線/備註渲染已經在 `_cropEnabled` 時呼叫 `originalToCropRelativePercent()` 把「相對整頁的 `PercentRect`」轉換成「相對裁切區域的 `PercentRect`」，再搭配該迴圈當下的 `pageRectInViewer.size`（裁切模式下已經是縮小後的尺寸）畫出正確位置的疊加 widget。只要搜尋高亮的座標一開始就換算成同一種「相對整頁的 `PercentRect`」格式、走同一條管線，裁切模式相容性就是既有程式碼的既有保證，不需要另外處理或停用。

---

### Task 1: `PdfSearchMatch` 模型 ＋ `pdfRectToPercentRect` 座標轉換純函式

**Files:**
- Create: `app/lib/reader/pdf_search_match.dart`
- Create: `app/lib/reader/pdf_search_geometry.dart`
- Test: `app/test/reader/pdf_search_geometry_test.dart`

**Interfaces:**
- Produces: `class PdfSearchMatch { final int pageIndex; final String text; final PercentRect rect; }`；`PercentRect pdfRectToPercentRect({required PdfRect rect, required double pageWidth, required double pageHeight})`——Task 3 依賴兩者。

- [x] **Step 1: 建立 `PdfSearchMatch` 模型**

建立 `app/lib/reader/pdf_search_match.dart`：

```dart
import 'percent_rect.dart';

/// 單筆 PDF 內文搜尋符合結果（epic-24-pdf-engine-rebuild Issue 6）。
/// [pageIndex] 為 0-indexed（比照專案既有慣例），[rect] 是相對整頁（未經
/// 裁切轉換）的 `PercentRect`——與 [PdfAnnotationDecoration.rect]
/// （`pdf_annotation_decoration.dart`）採用同一種座標語意，`PdfReaderView`
/// 疊加渲染時會比照劃線/備註的既有作法，在裁切模式啟用時另外呼叫
/// `originalToCropRelativePercent()` 換算為裁切相對座標。
class PdfSearchMatch {
  final int pageIndex;
  final String text;
  final PercentRect rect;

  const PdfSearchMatch({
    required this.pageIndex,
    required this.text,
    required this.rect,
  });

  @override
  bool operator ==(Object other) =>
      other is PdfSearchMatch &&
      other.pageIndex == pageIndex &&
      other.text == text &&
      other.rect == rect;

  @override
  int get hashCode => Object.hash(pageIndex, text, rect);

  @override
  String toString() =>
      'PdfSearchMatch(pageIndex: $pageIndex, text: $text, rect: $rect)';
}
```

（審查修正，review-plan-issue-6.md Minor #1：補上 `==`／`hashCode`／`toString()`，與同為值物件的既有 `PercentRect`／`PdfPageInfo` 慣例一致，便於測試斷言與除錯輸出。）

- [x] **Step 2: 撰寫 `pdfRectToPercentRect` 的失敗測試**

建立 `app/test/reader/pdf_search_geometry_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_search_geometry.dart';

void main() {
  group('pdfRectToPercentRect', () {
    test('頁面正中央的矩形換算為 0.25-0.75 範圍（US Letter 612x792）', () {
      // PDF points：頁面 612x792，矩形涵蓋 [153,594]x[153,198]（水平置中
      // 1/4~3/4，垂直置中一小段）。
      const rect = PdfRect(153, 594, 459, 198);
      final result = pdfRectToPercentRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.left, closeTo(0.25, 0.001));
      expect(result.right, closeTo(0.75, 0.001));
      // PDF top=594（距離底部較遠，即視覺上較高）換算後 percent top 應較小。
      expect(result.top, closeTo(1 - 594 / 792, 0.001));
      expect(result.bottom, closeTo(1 - 198 / 792, 0.001));
      expect(result.top, lessThan(result.bottom));
    });

    test('頁面最頂端的矩形換算後 top 趨近 0', () {
      const rect = PdfRect(0, 792, 100, 770);
      final result = pdfRectToPercentRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.top, closeTo(0.0, 0.001));
    });

    test('頁面最底端的矩形換算後 bottom 趨近 1', () {
      const rect = PdfRect(0, 22, 100, 0);
      final result = pdfRectToPercentRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.bottom, closeTo(1.0, 0.001));
    });

    test('左邊界矩形換算後 left 為 0', () {
      const rect = PdfRect(0, 700, 50, 680);
      final result = pdfRectToPercentRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.left, 0.0);
    });

    // 審查修正（review-plan-issue-6.md Minor #2）：少數 PDF 字型的字元
    // bounding box 可能微幅超出頁面邊界（例如 top 略大於 pageHeight），
    // 換算結果須夾在 [0, 1] 範圍內，避免下游疊加渲染產生輕微溢出。
    test('PDF 矩形頂端座標超出頁面邊界時，換算結果夾在 0-1 範圍內', () {
      const rect = PdfRect(0, 800, 100, 770); // top=800 > pageHeight=792。
      final result = pdfRectToPercentRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.top, 0.0);
    });

    test('PDF 矩形左側座標為負值時，換算結果夾在 0-1 範圍內', () {
      const rect = PdfRect(-1.5, 700, 50, 680); // left=-1.5 略小於 0。
      final result = pdfRectToPercentRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.left, 0.0);
    });
  });

  // 審查修正（review-plan-issue-6.md Minor #1）：驗證 PdfSearchMatch 的值
  // 相等性，與同為值物件的既有 PercentRect／PdfPageInfo 慣例一致。
  group('PdfSearchMatch 值相等性', () {
    test('欄位皆相同的兩個實例視為相等', () {
      const rectA = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
      const rectB = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
      const a = PdfSearchMatch(pageIndex: 0, text: 'foo', rect: rectA);
      const b = PdfSearchMatch(pageIndex: 0, text: 'foo', rect: rectB);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('任一欄位不同則視為不相等', () {
      const rect = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
      const a = PdfSearchMatch(pageIndex: 0, text: 'foo', rect: rect);
      const b = PdfSearchMatch(pageIndex: 1, text: 'foo', rect: rect);
      expect(a == b, isFalse);
    });
  });
}
```

檔案開頭新增 import：
```dart
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/pdf_search_match.dart';
```

- [x] **Step 3: 執行測試確認失敗**

Run: `flutter test test/reader/pdf_search_geometry_test.dart`
Expected: FAIL，`pdf_search_geometry.dart` 尚未定義。

- [x] **Step 4: 實作 `pdfRectToPercentRect`**

建立 `app/lib/reader/pdf_search_geometry.dart`：

```dart
import 'package:pdfrx/pdfrx.dart';

import 'percent_rect.dart';

/// 把 `pdfrx` 原生的 [PdfRect]（PDF points 座標，左下角原點、Y 軸向上，
/// `top >= bottom`）換算為本專案既有的 [PercentRect]（0-1 相對頁面尺寸，
/// 左上角原點、Y 軸向下，`top <= bottom`，比照 `Rect.fromLTRB` 語意與
/// `PdfAnnotationDecoration.rect` 既有慣例）。
///
/// epic-24-pdf-engine-rebuild Issue 6：[PdfPageTextRange.bounds]
/// （`pdfrx_engine` 套件）回傳的搜尋符合位置矩形即為 [PdfRect]，需要這個
/// 轉換才能套用既有的 `PdfReaderView` 疊加渲染管線
/// （`_buildProcessedOverlay`／`originalToCropRelativePercent`）。
///
/// 換算結果一律夾在 0.0-1.0 範圍內（審查修正，review-plan-issue-6.md
/// Minor #2）：少數 PDF 字型解析出的字元 bounding box 可能微幅超出頁面
/// 邊界（例如 `top` 略大於 `pageHeight`、`left` 略小於 0），不夾範圍會讓
/// 換算結果變成負值或大於 1，下游疊加渲染（`_buildSearchHighlightWidget`）
/// 直接把 percent 乘上像素尺寸，會在頁面邊緣產生輕微視覺溢出。
PercentRect pdfRectToPercentRect({
  required PdfRect rect,
  required double pageWidth,
  required double pageHeight,
}) {
  return PercentRect(
    left: (rect.left / pageWidth).clamp(0.0, 1.0),
    right: (rect.right / pageWidth).clamp(0.0, 1.0),
    top: (1.0 - (rect.top / pageHeight)).clamp(0.0, 1.0),
    bottom: (1.0 - (rect.bottom / pageHeight)).clamp(0.0, 1.0),
  );
}
```

- [x] **Step 5: 執行測試確認通過**

Run: `flutter test test/reader/pdf_search_geometry_test.dart -v`
Expected: 8 項全數通過。

- [x] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/reader/pdf_search_match.dart app/lib/reader/pdf_search_geometry.dart app/test/reader/pdf_search_geometry_test.dart
git commit -m "feat(epic-24): 新增 PdfSearchMatch 模型與 PdfRect→PercentRect 座標轉換純函式"
```

---

### Task 2: `PdfSearchState` 不可變狀態類別

**Files:**
- Create: `app/lib/reader/pdf_search_state.dart`
- Test: `app/test/reader/pdf_search_state_test.dart`

**Interfaces:**
- Produces: `class PdfSearchState { final String query; final bool isSearching; final int matchCount; final int? currentIndex; const PdfSearchState({...}); const PdfSearchState.initial(); PdfSearchState copyWith({...}); }`——Task 5、Task 6 依賴此型別。

- [x] **Step 1: 撰寫失敗測試**

建立 `app/test/reader/pdf_search_state_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_search_state.dart';

void main() {
  test('initial 為空查詢、非搜尋中、0 筆符合、currentIndex 為 null', () {
    const state = PdfSearchState.initial();
    expect(state.query, '');
    expect(state.isSearching, isFalse);
    expect(state.matchCount, 0);
    expect(state.currentIndex, isNull);
  });

  test('copyWith 只覆寫指定欄位，其餘保留原值', () {
    const state = PdfSearchState(
      query: 'abc',
      isSearching: false,
      matchCount: 3,
      currentIndex: 1,
    );
    final updated = state.copyWith(currentIndex: 2);
    expect(updated.query, 'abc');
    expect(updated.isSearching, isFalse);
    expect(updated.matchCount, 3);
    expect(updated.currentIndex, 2);
  });

  test('copyWith 可將 currentIndex 明確設回 null（clearCurrentIndex）', () {
    const state = PdfSearchState(
      query: 'abc',
      isSearching: false,
      matchCount: 3,
      currentIndex: 1,
    );
    final updated = state.copyWith(clearCurrentIndex: true);
    expect(updated.currentIndex, isNull);
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/pdf_search_state_test.dart`
Expected: FAIL，`pdf_search_state.dart` 尚未定義。

- [x] **Step 3: 實作 `PdfSearchState`**

建立 `app/lib/reader/pdf_search_state.dart`：

```dart
/// PDF 內文搜尋的目前狀態（epic-24-pdf-engine-rebuild Issue 6），由
/// `ReaderScreen` 擁有並透過 `ValueNotifier<PdfSearchState>` 廣播給
/// `PdfSearchPanel`（`ValueListenableBuilder`），讓已開啟的目錄 Bottom
/// Sheet 能在背景搜尋完成當下即時更新——比照 `TocBottomSheet` 既有的
/// `totalCharacterCountListenable` 解決同一類「外部非同步狀態更新已開啟
/// 的 Bottom Sheet」問題的既有模式。
///
/// [currentIndex] 是 0-indexed，指向目前使用者正在檢視的符合結果在
/// `ReaderScreen` 所持有的符合結果清單中的位置；`null` 代表尚無符合結果
/// 或尚未開始搜尋。
class PdfSearchState {
  final String query;
  final bool isSearching;
  final int matchCount;
  final int? currentIndex;

  const PdfSearchState({
    required this.query,
    required this.isSearching,
    required this.matchCount,
    required this.currentIndex,
  });

  const PdfSearchState.initial()
      : query = '',
        isSearching = false,
        matchCount = 0,
        currentIndex = null;

  /// [clearCurrentIndex] 為 true 時，無論是否有傳入 [currentIndex] 參數，
  /// 結果一律是 `null`——一般的 `currentIndex: null` 語意在 `copyWith`
  /// 慣例下代表「不覆寫」，需要這個獨立旗標才能明確表達「覆寫為 null」。
  PdfSearchState copyWith({
    String? query,
    bool? isSearching,
    int? matchCount,
    int? currentIndex,
    bool clearCurrentIndex = false,
  }) {
    return PdfSearchState(
      query: query ?? this.query,
      isSearching: isSearching ?? this.isSearching,
      matchCount: matchCount ?? this.matchCount,
      currentIndex: clearCurrentIndex ? null : (currentIndex ?? this.currentIndex),
    );
  }
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/pdf_search_state_test.dart -v`
Expected: 3 項全數通過。

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/pdf_search_state.dart app/test/reader/pdf_search_state_test.dart
git commit -m "feat(epic-24): 新增 PdfSearchState 不可變狀態類別"
```

---

### Task 3: `PdfReaderView` 整合搜尋（執行搜尋、疊加高亮）

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Test: `app/test/reader/pdf_reader_view_search_test.dart`

**Interfaces:**
- Consumes: `PdfSearchMatch`（Task 1）、`pdfRectToPercentRect`（Task 1）。
- Produces: `static Future<List<PdfSearchMatch>> PdfReaderView.search(GlobalKey<State<PdfReaderView>> key, String query)`；`static void PdfReaderView.setSearchHighlights(GlobalKey<State<PdfReaderView>> key, List<PdfSearchMatch> matches, {required int? currentIndex})`——Task 6 依賴兩者的簽章。

- [x] **Step 1: 撰寫失敗測試**

建立 `app/test/reader/pdf_reader_view_search_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';

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

  testWidgets('搜尋 "Page" 正確找出每頁各一筆符合結果，座標落在合理範圍內', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'Page'));

    expect(matches, isNotNull);
    expect(matches!.length, 5);
    for (var i = 0; i < 5; i++) {
      expect(matches[i].pageIndex, i);
      expect(matches[i].text.toLowerCase(), contains('page'));
      expect(matches[i].rect.left, greaterThanOrEqualTo(0));
      expect(matches[i].rect.right, lessThanOrEqualTo(1));
      expect(matches[i].rect.top, lessThan(matches[i].rect.bottom));
    }
  });

  testWidgets('搜尋 "ELINKBOOK"（大小寫不敏感）仍能找到符合結果', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'elinkbook'));

    expect(matches, isNotNull);
    expect(matches!.length, 5);
  });

  testWidgets('查無符合結果時回傳空清單，不拋出例外', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'nonexistent_xyz'));

    expect(matches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('無文字層的 PDF（sample.pdf）搜尋回傳空清單，不拋出例外', (tester) async {
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

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'anything'));

    expect(matches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('setSearchHighlights 後畫面渲染出對應的高亮 widget，含目前符合結果的獨立 Key',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'Page'));
    expect(matches, isNotNull);

    PdfReaderView.setSearchHighlights(key, matches!, currentIndex: 0);
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_search_highlight_0_0')), findsOneWidget);
  });

  testWidgets('目前符合結果（isCurrent）額外疊加外框，其餘符合結果無外框（審查修正 Minor #3）',
      (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await waitRendered(tester, () => renderedCount);

    final matches = await tester.runAsync(() => PdfReaderView.search(key, 'Page'));
    expect(matches, isNotNull);

    PdfReaderView.setSearchHighlights(key, matches!, currentIndex: 0);
    await tester.pump();

    final currentContainer = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('pdf_reader_search_highlight_0_0')),
        matching: find.byType(Container),
      ),
    );
    final currentDecoration = currentContainer.decoration as BoxDecoration;
    expect(currentDecoration.border, isNotNull);

    // 頁碼 1（index 1）的符合結果不是目前選取項，不應有外框。
    PdfReaderView.jumpToPage(key, 1);
    await tester.pump(const Duration(milliseconds: 300));
    final otherContainer = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('pdf_reader_search_highlight_1_1')),
        matching: find.byType(Container),
      ),
    );
    final otherDecoration = otherContainer.decoration as BoxDecoration;
    expect(otherDecoration.border, isNull);
  });

  testWidgets('State 尚未掛載時，search／setSearchHighlights 皆靜默忽略', (tester) async {
    final orphanKey = GlobalKey<State<PdfReaderView>>();
    final matches = await PdfReaderView.search(orphanKey, 'x');
    expect(matches, isEmpty);
    expect(
      () => PdfReaderView.setSearchHighlights(orphanKey, const [], currentIndex: null),
      returnsNormally,
    );
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/pdf_reader_view_search_test.dart`
Expected: FAIL，`PdfReaderView.search`／`setSearchHighlights` 尚未定義。

- [x] **Step 3: 實作搜尋與高亮渲染**

修改 `app/lib/reader/pdf_reader_view.dart`，在檔案頂部 import 區塊新增：

```dart
import 'pdf_search_match.dart';
import 'pdf_search_geometry.dart';
```

在 `class PdfReaderView` 內、既有 `static void refreshAnnotations(...)`（Issue 4）之後新增：

```dart
  /// 在目前已開啟的文件內搜尋 [query]（大小寫不敏感），回傳所有符合位置
  /// （epic-24-pdf-engine-rebuild Issue 6）。文件尚未開啟完成或 [key]
  /// 尚未掛載時回傳空清單，比照既有靜態 helper 的靜默忽略慣例。
  static Future<List<PdfSearchMatch>> search(
    GlobalKey<State<PdfReaderView>> key,
    String query,
  ) async {
    final state = key.currentState;
    if (state is! _PdfReaderViewState) return const [];
    return state._search(query);
  }

  /// 一次性送出目前應高亮顯示的完整符合結果清單（非增量 diff，比照
  /// [refreshAnnotations] 整組送出慣例）。[currentIndex] 是 [matches]
  /// 清單中「目前使用者正在檢視」的索引，用不同顏色標示；`null` 代表尚無
  /// 目前選取的符合結果。
  static void setSearchHighlights(
    GlobalKey<State<PdfReaderView>> key,
    List<PdfSearchMatch> matches, {
    required int? currentIndex,
  }) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._setSearchHighlights(matches, currentIndex);
    }
  }
```

在 `class _PdfReaderViewState` 內、既有 `List<PdfAnnotationDecoration> _annotations = const [];`（`pdf_reader_view.dart:209`）附近新增欄位：

```dart
  List<PdfSearchMatch> _searchMatches = const [];
  int? _currentSearchMatchIndex;
  int _searchSessionId = 0;
```

在既有 `_setAnnotations` 方法附近新增：

```dart
  void _setSearchHighlights(List<PdfSearchMatch> matches, int? currentIndex) {
    setState(() {
      _searchMatches = matches;
      _currentSearchMatchIndex = currentIndex;
    });
  }

  /// 直接對 [_document] 逐頁呼叫 `loadStructuredText()`／`allMatches()`，
  /// 不透過 `PdfViewer`／`PdfViewerController`（見 Global Constraints「不
  /// 使用 PdfTextSearcher」）。[_searchSessionId] 是簡易的搜尋世代編號
  /// （比照 `PdfTextSearcher._searchSession` 既有設計精神），避免使用者
  /// 快速輸入導致前一次尚未完成的搜尋，在完成時覆蓋掉更新一次搜尋已經
  /// 寫入的結果——每次呼叫先遞增世代編號，逐頁掃描過程中若世代編號已被
  /// 後續呼叫超車就提早回傳空清單，呼叫端（`ReaderScreen`）以最後一次
  /// 真正跑完的呼叫結果為準。
  Future<List<PdfSearchMatch>> _search(String query) async {
    final sessionId = ++_searchSessionId;
    final document = _document;
    if (document == null) return const [];
    final matches = <PdfSearchMatch>[];
    for (final page in document.pages) {
      if (sessionId != _searchSessionId) return const [];
      final text = await page.loadStructuredText();
      if (sessionId != _searchSessionId) return const [];
      await for (final m in text.allMatches(query, caseInsensitive: true)) {
        matches.add(PdfSearchMatch(
          pageIndex: page.pageNumber - 1,
          text: m.text,
          rect: pdfRectToPercentRect(
            rect: m.bounds,
            pageWidth: page.width,
            pageHeight: page.height,
          ),
        ));
      }
    }
    return matches;
  }
```

在既有 `_buildDecorationWidget` 方法之後新增：

```dart
  /// 搜尋符合結果的高亮 widget，畫法比照 [_buildDecorationWidget]
  /// （同樣的 `PercentRect`→像素換算），[isCurrent] 為 true（目前使用者
  /// 正在檢視的符合結果）時額外疊加外框（審查修正，
  /// review-plan-issue-6.md Minor #3）：純粹用半透明橙色／黃色區分在
  /// E-Ink 灰階顯示或高對比主題下辨識度不足，外框在灰階轉換後仍能維持
  /// 明顯的邊界對比，不依賴色相差異。
  Widget _buildSearchHighlightWidget(
    int pageIndex,
    int matchIndex,
    PercentRect visibleRect,
    Size areaSize, {
    required bool isCurrent,
  }) {
    final rect = Rect.fromLTRB(
      visibleRect.left * areaSize.width,
      visibleRect.top * areaSize.height,
      visibleRect.right * areaSize.width,
      visibleRect.bottom * areaSize.height,
    );
    return Positioned.fromRect(
      // key 須同時包含 pageIndex 與 matchIndex（matchIndex 是在
      // _searchMatches 整份清單中的全域索引，非同頁內重新歸零的計數）——
      // 理由與 _buildDecorationWidget 的既有註解相同：同一頁可能有多筆
      // 符合結果，只用 pageIndex 當 key 會產生重複 key。
      key: Key('pdf_reader_search_highlight_${pageIndex}_$matchIndex'),
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: (isCurrent ? Colors.orange : Colors.yellow).withValues(alpha: 0.4),
          border: isCurrent
              ? Border.all(color: Colors.deepOrange, width: 1.5)
              : null,
        ),
      ),
    );
  }
```

修改既有 `_buildProcessedOverlay`（`pdf_reader_view.dart:599-647`），在「渲染既有標記（Issue 4）」區塊之後、`_buildSelectionGestureLayer` 呼叫之前，新增搜尋高亮渲染：

```dart
    // 渲染搜尋符合結果高亮（Issue 6）。
    for (var i = 0; i < _searchMatches.length; i++) {
      final match = _searchMatches[i];
      if (match.pageIndex != pageIndex) continue;
      final visibleRect = _cropEnabled
          ? originalToCropRelativePercent(rect: match.rect, cropRect: widget.pdfCropRect)
          : match.rect;
      if (visibleRect == null) continue; // 完全落在裁切範圍外。
      widgets.add(_buildSearchHighlightWidget(
        pageIndex,
        i,
        visibleRect,
        pageRectInViewer.size,
        isCurrent: i == _currentSearchMatchIndex,
      ));
    }
```

（插入位置：緊接在既有的
```dart
    final drag = _selectionDrag;
    if (drag != null && drag.pageIndex == pageIndex) {
      widgets.add(_buildDragIndicator(drag));
    }
```
這段之後、`widgets.add(_buildSelectionGestureLayer(pageIndex, pageRectInViewer));` 之前。）

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/pdf_reader_view_search_test.dart -v`
Expected: 7 項全數通過。

（本計畫撰寫階段已實測驗證過與 Step 1 等價的底層邏輯——`sample_multi_page.pdf` 5 頁搜尋 "Page" 找到 5 筆符合，`sample.pdf` 搜尋任何字串皆回傳空清單——真實輸出見上方「與計畫撰寫階段實測發現相關的技術澄清」第 1 點。）

- [x] **Step 5: 執行既有 PDF 測試確認零回歸**

Run: `flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_selection_test.dart test/reader/pdf_reader_view_dual_page_test.dart test/reader/pdf_reader_view_filters_test.dart test/reader/pdf_reader_view_toc_test.dart -v`
Expected: 全數通過，無新增失敗。

- [x] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_search_test.dart
git commit -m "feat(epic-24): PdfReaderView 整合內文搜尋——search()/setSearchHighlights()"
```

---

### Task 4: `TocBottomSheet` 新增搜尋分頁內容插槽

**Files:**
- Modify: `app/lib/screens/toc_bottom_sheet.dart`
- Test: `app/test/screens/toc_bottom_sheet_pdf_test.dart`（新增測試，不修改既有測試）

**Interfaces:**
- Produces: `TocBottomSheet` 新增建構參數 `final Widget? searchTabContent`——Task 6 依賴此參數名稱。

- [x] **Step 1: 確認既有測試現況（作為零回歸基準）**

Run: `flutter test test/screens/toc_bottom_sheet_test.dart test/screens/toc_bottom_sheet_pdf_test.dart -v`
Expected: 既有 6＋5 項全數通過（修改前的基準線）。

- [x] **Step 2: 修改 `TocBottomSheet` 新增 `searchTabContent` 參數**

修改 `app/lib/screens/toc_bottom_sheet.dart`，在 `class TocBottomSheet` 內既有 `final BookFormat? format;` 附近新增欄位：

```dart
  /// PDF「搜尋」分頁要顯示的內容（epic-24-pdf-engine-rebuild Issue 6）；
  /// `null` 時該分頁顯示既有的「此功能將於後續版本提供」佔位文字。本
  /// widget 刻意不知道傳入的是什麼（維持與 `ReaderScreen` 解耦的既有設計
  /// 原則，見類別 docstring），只負責把它放進分頁籤殼層的第三個分頁。
  final Widget? searchTabContent;
```

建構子新增對應參數（沿用既有全部具名參數＋加一個可選參數的模式）：

```dart
  const TocBottomSheet({
    super.key,
    this.format,
    required this.entries,
    required this.initiallyExpandedEntries,
    required this.currentEntry,
    required this.totalCharacterCountListenable,
    required this.resolved,
    required this.onEntrySelected,
    this.searchTabContent,
  });
```

修改 `build()` 內既有的 `TabBarView`：

```dart
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildTocList(totalCharacterCount),
                        const Center(child: Text('此功能將於後續版本提供')),
                        widget.searchTabContent ??
                            const Center(child: Text('此功能將於後續版本提供')),
                      ],
                    ),
                  ),
```

- [x] **Step 3: 撰寫新增情境的失敗測試**

在 `app/test/screens/toc_bottom_sheet_pdf_test.dart` 既有「PDF 格式下顯示三個分頁籤...」測試之後新增：

```dart
  testWidgets('傳入 searchTabContent 時，切換到搜尋分頁顯示該內容而非預設佔位文字',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          format: BookFormat.pdf,
          entries: const [],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (_) {},
          searchTabContent: const Text('SEARCH_PANEL_PLACEHOLDER'),
        ),
      ),
    ));

    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    expect(find.text('SEARCH_PANEL_PLACEHOLDER'), findsOneWidget);
    expect(find.text('此功能將於後續版本提供'), findsOneWidget, reason: '縮圖分頁仍是既有佔位文字，本工單不動它');
  });

  testWidgets('未傳入 searchTabContent 時，搜尋分頁維持既有佔位文字（零回歸）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          format: BookFormat.pdf,
          entries: const [],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    expect(find.text('此功能將於後續版本提供'), findsNWidgets(2), reason: '縮圖與搜尋分頁皆仍是既有佔位文字');
  });
```

檔案開頭確認已 import `package:flutter/material.dart`（既有，`Text` 屬於 Material/Widgets 套件，不需要額外 import）。

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/toc_bottom_sheet_pdf_test.dart -v`
Expected: 既有 5 項＋新增 2 項，共 7 項全數通過。

- [x] **Step 5: 執行 EPUB 既有測試確認零回歸**

Run: `flutter test test/screens/toc_bottom_sheet_test.dart -v`
Expected: 6 項全數通過（`TocBottomSheet` 未傳 `searchTabContent` 時走既有 `null` 預設值，不影響 EPUB 分支——EPUB 分支根本不會走到 `TabBarView`，這個新參數對它完全無感）。

- [x] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/toc_bottom_sheet.dart app/test/screens/toc_bottom_sheet_pdf_test.dart
git commit -m "feat(epic-24): TocBottomSheet 新增 searchTabContent 插槽（維持與 ReaderScreen 解耦）"
```

---

### Task 5: `PdfSearchPanel` widget（搜尋輸入框、防手震延遲、結果導覽）

**Files:**
- Create: `app/lib/screens/pdf_search_panel.dart`
- Test: `app/test/screens/pdf_search_panel_test.dart`

**Interfaces:**
- Consumes: `PdfSearchState`（Task 2）。
- Produces: `class PdfSearchPanel extends StatefulWidget { const PdfSearchPanel({required ValueListenable<PdfSearchState> searchStateListenable, required ValueChanged<String> onQueryChanged, required VoidCallback onNext, required VoidCallback onPrevious, String initialQuery = ''}); }`——Task 6 依賴此建構參數簽章。

- [x] **Step 1: 撰寫失敗測試**

建立 `app/test/screens/pdf_search_panel_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_search_state.dart';
import 'package:elinkbook/screens/pdf_search_panel.dart';

void main() {
  testWidgets('輸入文字後 500ms 內未再變動才觸發 onQueryChanged（防手震延遲）', (tester) async {
    final queries = <String>[];
    final notifier = ValueNotifier<PdfSearchState>(const PdfSearchState.initial());
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: queries.add,
          onNext: () {},
          onPrevious: () {},
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('pdf_search_field')), 'a');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('pdf_search_field')), 'ab');
    await tester.pump(const Duration(milliseconds: 100));
    expect(queries, isEmpty, reason: '連續輸入期間不應觸發，防止每個字元都各自查詢一次');

    await tester.pump(const Duration(milliseconds: 500));
    expect(queries, ['ab']);
  });

  testWidgets('清空輸入框時立即觸發 onQueryChanged("")，不等待防手震延遲', (tester) async {
    final queries = <String>[];
    final notifier = ValueNotifier<PdfSearchState>(const PdfSearchState.initial());
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: queries.add,
          onNext: () {},
          onPrevious: () {},
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('pdf_search_field')), 'a');
    await tester.pump(const Duration(milliseconds: 500));
    expect(queries, ['a']);

    await tester.enterText(find.byKey(const Key('pdf_search_field')), '');
    await tester.pump();
    expect(queries, ['a', '']);
  });

  testWidgets('query 為空時不顯示計數器/導覽按鈕/空結果訊息', (tester) async {
    final notifier = ValueNotifier<PdfSearchState>(const PdfSearchState.initial());
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: (_) {},
          onNext: () {},
          onPrevious: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('pdf_search_counter')), findsNothing);
    expect(find.byKey(const Key('pdf_search_empty')), findsNothing);
    expect(find.byKey(const Key('pdf_search_loading')), findsNothing);
  });

  testWidgets('isSearching 為 true 時顯示載入中指示', (tester) async {
    final notifier = ValueNotifier<PdfSearchState>(
      const PdfSearchState(query: 'abc', isSearching: true, matchCount: 0, currentIndex: null),
    );
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: (_) {},
          onNext: () {},
          onPrevious: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('pdf_search_loading')), findsOneWidget);
  });

  testWidgets('搜尋完成但 matchCount 為 0 時顯示「找不到符合的文字」', (tester) async {
    final notifier = ValueNotifier<PdfSearchState>(
      const PdfSearchState(query: 'xyz', isSearching: false, matchCount: 0, currentIndex: null),
    );
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: (_) {},
          onNext: () {},
          onPrevious: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('pdf_search_empty')), findsOneWidget);
    expect(find.text('找不到符合的文字'), findsOneWidget);
  });

  testWidgets('有符合結果時顯示「目前/共 N」計數器，點擊上一個/下一個觸發對應回呼',
      (tester) async {
    var nextCount = 0;
    var prevCount = 0;
    final notifier = ValueNotifier<PdfSearchState>(
      const PdfSearchState(query: 'abc', isSearching: false, matchCount: 5, currentIndex: 1),
    );
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: (_) {},
          onNext: () => nextCount++,
          onPrevious: () => prevCount++,
        ),
      ),
    ));

    expect(find.byKey(const Key('pdf_search_counter')), findsOneWidget);
    expect(find.text('2 / 5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pdf_search_next_button')));
    expect(nextCount, 1);
    await tester.tap(find.byKey(const Key('pdf_search_prev_button')));
    expect(prevCount, 1);
  });

  testWidgets('initialQuery 非空時，文字輸入框預先填入該查詢字串', (tester) async {
    final notifier = ValueNotifier<PdfSearchState>(const PdfSearchState.initial());
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfSearchPanel(
          searchStateListenable: notifier,
          onQueryChanged: (_) {},
          onNext: () {},
          onPrevious: () {},
          initialQuery: '既有查詢',
        ),
      ),
    ));

    expect(find.text('既有查詢'), findsOneWidget);
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/pdf_search_panel_test.dart`
Expected: FAIL，`pdf_search_panel.dart` 尚未定義。

- [x] **Step 3: 實作 `PdfSearchPanel`**

建立 `app/lib/screens/pdf_search_panel.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../reader/pdf_search_state.dart';

/// PDF 內文搜尋面板（epic-24-pdf-engine-rebuild Issue 6），掛載於
/// `TocBottomSheet` 的「搜尋」分頁（`TocBottomSheet.searchTabContent`）。
/// 與 `ReaderScreen`／`PdfReaderView` 完全解耦：只透過 [onQueryChanged]／
/// [onNext]／[onPrevious] 回呼與 [searchStateListenable] 溝通，本身不知道
/// 呼叫端如何實際執行搜尋。
///
/// 輸入框變動後套用 500ms 防手震延遲才觸發 [onQueryChanged]，避免使用者
/// 每輸入一個字元就觸發一次全文搜尋；清空輸入框時例外，立即觸發（讓畫面
/// 立刻清空搜尋結果與高亮，不需要额外等待）。
class PdfSearchPanel extends StatefulWidget {
  final ValueListenable<PdfSearchState> searchStateListenable;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  /// Bottom Sheet 重新開啟時，若使用者先前已有查詢字串，預先填入輸入框
  /// （不會自動觸發 [onQueryChanged]——呼叫端已經持有對應的搜尋結果，
  /// 不需要重新搜尋一次）。
  final String initialQuery;

  const PdfSearchPanel({
    super.key,
    required this.searchStateListenable,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrevious,
    this.initialQuery = '',
  });

  @override
  State<PdfSearchPanel> createState() => _PdfSearchPanelState();
}

class _PdfSearchPanelState extends State<PdfSearchPanel> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    _debounce?.cancel();
    if (value.isEmpty) {
      widget.onQueryChanged('');
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      widget.onQueryChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('pdf_search_field'),
            controller: _controller,
            decoration: const InputDecoration(
              hintText: '搜尋文字…',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _handleChanged,
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<PdfSearchState>(
            valueListenable: widget.searchStateListenable,
            builder: (context, state, _) {
              if (state.query.isEmpty) return const SizedBox.shrink();
              if (state.isSearching) {
                return const Padding(
                  key: Key('pdf_search_loading'),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (state.matchCount == 0) {
                return const Padding(
                  key: Key('pdf_search_empty'),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text('找不到符合的文字')),
                );
              }
              return Row(
                key: const Key('pdf_search_counter'),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${(state.currentIndex ?? 0) + 1} / ${state.matchCount}'),
                  Row(
                    children: [
                      IconButton(
                        key: const Key('pdf_search_prev_button'),
                        icon: const Icon(Icons.keyboard_arrow_up),
                        tooltip: '上一個',
                        onPressed: widget.onPrevious,
                      ),
                      IconButton(
                        key: const Key('pdf_search_next_button'),
                        icon: const Icon(Icons.keyboard_arrow_down),
                        tooltip: '下一個',
                        onPressed: widget.onNext,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/pdf_search_panel_test.dart -v`
Expected: 7 項全數通過。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/pdf_search_panel.dart app/test/screens/pdf_search_panel_test.dart
git commit -m "feat(epic-24): 新增 PdfSearchPanel widget——搜尋輸入框、防手震延遲、結果導覽"
```

---

### Task 6: `ReaderScreen` 接上搜尋執行與導覽邏輯

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: `PdfReaderView.search`／`PdfReaderView.setSearchHighlights`（Task 3）、`TocBottomSheet.searchTabContent`（Task 4）、`PdfSearchPanel`（Task 5）、`PdfSearchState`（Task 2）。

- [x] **Step 1: 在 `_ReaderScreenState` 新增搜尋狀態欄位**

修改 `app/lib/screens/reader_screen.dart`，在既有 `static final _pdfDummyCharacterCountNotifier = ValueNotifier<int?>(null);`（`reader_screen.dart:195`）附近新增：

```dart
  final _pdfSearchStateNotifier = ValueNotifier<PdfSearchState>(const PdfSearchState.initial());
  List<PdfSearchMatch> _pdfSearchMatches = const [];
  int _pdfSearchRequestId = 0;
```

`_pdfSearchRequestId` 的用途見下方 Step 2（審查修正，review-plan-issue-6.md Important #1：避免快速輸入時，先發起但較慢完成的搜尋請求覆寫掉後發起、較快完成的搜尋請求已經寫入的 UI 狀態）。

檔案開頭新增 import：

```dart
import '../reader/pdf_search_match.dart';
import '../reader/pdf_search_state.dart';
import 'pdf_search_panel.dart';
```

修改既有 `dispose()` 方法（`reader_screen.dart:419`），緊接在既有 `_totalCharacterCountNotifier.dispose();`（`reader_screen.dart:424`）之後新增一行：

```dart
  @override
  void dispose() {
    _syncCheckpointTimer?.cancel();
    _openBookTimeoutTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _volumeKeyChannel.setMethodCallHandler(null);
    _totalCharacterCountNotifier.dispose();
    _pdfSearchStateNotifier.dispose();
    // 離開閱讀畫面時觸發一次位置寫入（spec.md「本機閱讀位置記憶」寫入
    // 時機之一）。不 await——dispose() 是同步方法，且這是離開畫面前的
    // ...（其餘既有內容不變）
```

- [x] **Step 2: 新增 `_searchPdf`／`_goToPdfSearchMatch` 方法**

在既有 `_openPdfToc()` 方法（`reader_screen.dart:810-831`）之後新增：

```dart
  /// 執行 PDF 內文搜尋（epic-24-pdf-engine-rebuild Issue 6）：呼叫
  /// [PdfReaderView.search] 取得符合結果，寫回 [_pdfSearchMatches] 供
  /// [_goToPdfSearchMatch] 使用，並透過 [PdfReaderView.setSearchHighlights]
  /// 疊加高亮＋跳轉至第一筆符合結果所在頁面。[query] 為空字串時清空搜尋
  /// 狀態與畫面高亮，不觸發實際搜尋。
  ///
  /// [_pdfSearchRequestId] 是簡易的請求世代編號（審查修正，
  /// review-plan-issue-6.md Important #1）：`PdfReaderView._search()`
  /// 內部的 `_searchSessionId` 只保證「被超車的搜尋不會回傳過期的比對結果
  /// 給呼叫端」，但沒有阻止呼叫端（本方法）在拿到那個過期的空結果後，
  /// 誤把它當作「這次搜尋真的沒找到東西」寫回 UI 狀態——例如使用者連續
  /// 輸入 "a" 後又補打成 "ab"："a" 的搜尋被超車提早回傳空清單，若本方法
  /// 不做世代比對，"a" 的 `_searchPdf` 恢復執行時會用這個空清單覆寫掉
  /// "ab" 尚在背景搜尋中、稍後才會寫入的真正結果，讓使用者在畫面上看到
  /// 一閃而過的「找不到符合的文字」。每次呼叫先遞增世代編號，`await`
  /// 完成後比對世代編號是否仍是最新，不是最新就靜默放棄這次結果（不寫回
  /// 任何 UI 狀態），留給後面那個真正最新的呼叫收尾。
  ///
  /// 【測試涵蓋範圍說明】這個世代編號比對本身不額外寫專屬的競態重現
  /// 測試——`sample_multi_page.pdf` 這種小型 fixture 的搜尋在
  /// `flutter test` 環境下接近瞬間完成（見 Task 3 撰寫階段實測），要在
  /// widget test 的 pump 排程下可靠、非偶發地讓兩次真實搜尋呼叫確實重疊
  /// （而非其中一次已經跑完才開始下一次）需要额外的人工延遲注入點，
  /// 屬於為了測試而測試的額外複雜度；這個修正的正確性以程式碼比對／
  /// 既有同類先例（`PdfReaderView._searchSessionId`、`pdfrx` 自身
  /// `PdfTextSearcher._searchSession` 採用相同的世代編號比對手法）佐證，
  /// 比照 Task 3 `_searchSessionId` 本身也未另外寫競態重現測試的既有
  /// 判斷一致。
  Future<void> _searchPdf(String query) async {
    final requestId = ++_pdfSearchRequestId;
    if (query.isEmpty) {
      _pdfSearchMatches = const [];
      PdfReaderView.setSearchHighlights(_pdfReaderViewKey, const [], currentIndex: null);
      _pdfSearchStateNotifier.value = const PdfSearchState.initial();
      return;
    }
    _pdfSearchStateNotifier.value = PdfSearchState(
      query: query,
      isSearching: true,
      matchCount: 0,
      currentIndex: null,
    );
    final matches = await PdfReaderView.search(_pdfReaderViewKey, query);
    if (!mounted || requestId != _pdfSearchRequestId) return;
    _pdfSearchMatches = matches;
    final currentIndex = matches.isEmpty ? null : 0;
    PdfReaderView.setSearchHighlights(_pdfReaderViewKey, matches, currentIndex: currentIndex);
    if (currentIndex != null) {
      PdfReaderView.jumpToPage(_pdfReaderViewKey, matches[currentIndex].pageIndex);
    }
    _pdfSearchStateNotifier.value = PdfSearchState(
      query: query,
      isSearching: false,
      matchCount: matches.length,
      currentIndex: currentIndex,
    );
  }

  /// 導覽至下一個（[delta] = 1）或上一個（[delta] = -1）符合結果，循環
  /// 至清單另一端（比照常見 PDF 閱讀器/瀏覽器 Ctrl+F 的既有慣例）。
  /// [_pdfSearchMatches] 為空時無作用。
  void _goToPdfSearchMatch(int delta) {
    if (_pdfSearchMatches.isEmpty) return;
    final current = _pdfSearchStateNotifier.value.currentIndex ?? -1;
    final next = (current + delta) % _pdfSearchMatches.length;
    PdfReaderView.setSearchHighlights(_pdfReaderViewKey, _pdfSearchMatches, currentIndex: next);
    PdfReaderView.jumpToPage(_pdfReaderViewKey, _pdfSearchMatches[next].pageIndex);
    _pdfSearchStateNotifier.value = _pdfSearchStateNotifier.value.copyWith(currentIndex: next);
  }
```

- [x] **Step 3: 修改 `_openPdfToc()` 傳入 `searchTabContent`**

修改既有 `_openPdfToc()`（`reader_screen.dart:810-831`）：

```dart
  void _openPdfToc() {
    if (!_pdfTocLoaded) return;
    final currentPath =
        PdfTocNavigator.findCurrentPath(_pdfTocEntries, _pdfPageInfo?.pageIndex);
    _showThemedModalBottomSheet<void>(
      builder: (_) => TocBottomSheet(
        format: BookFormat.pdf,
        entries: _pdfTocEntries,
        initiallyExpandedEntries: currentPath.toSet(),
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        totalCharacterCountListenable: _pdfDummyCharacterCountNotifier,
        resolved: _resolved!,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          final pageIndex = (entry as PdfTocItem).pageIndex;
          if (pageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, pageIndex);
          }
        },
        searchTabContent: PdfSearchPanel(
          searchStateListenable: _pdfSearchStateNotifier,
          initialQuery: _pdfSearchStateNotifier.value.query,
          onQueryChanged: (query) => unawaited(_searchPdf(query)),
          onNext: () => _goToPdfSearchMatch(1),
          onPrevious: () => _goToPdfSearchMatch(-1),
        ),
      ),
    );
  }
```

`dart:async`（`unawaited` 來源）已於檔案開頭第 1 行 `import 'dart:async';` 既有，不需新增。

- [x] **Step 4: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 5: 撰寫搜尋端對端測試**

在 `app/test/screens/reader_screen_test.dart` 既有 Issue 5 新增的三則 PDF 目錄測試之後新增：

```dart
  testWidgets('PDF 搜尋："Page" 找到 5 筆符合，顯示計數器並跳轉至第一筆所在頁面',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_search',
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

    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('pdf_search_field')), 'Page');
    await tester.runAsync(() async {
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(find.byKey(const Key('pdf_search_counter')), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
  });

  testWidgets('PDF 搜尋：點擊下一個依序跳轉，最後一筆再按下一個循環回第一筆',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_search_nav',
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
    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('pdf_search_field')), 'Page');
    await tester.runAsync(() async {
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(find.text('1 / 5'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('pdf_search_next_button')));
      await tester.pump();
    }
    expect(find.text('5 / 5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pdf_search_next_button')));
    await tester.pump();
    expect(find.text('1 / 5'), findsOneWidget, reason: '最後一筆再按下一個應循環回第一筆');

    await tester.tap(find.byKey(const Key('pdf_search_prev_button')));
    await tester.pump();
    expect(find.text('5 / 5'), findsOneWidget, reason: '第一筆按上一個應循環到最後一筆');
  });

  testWidgets('PDF 搜尋：查無符合結果時顯示「找不到符合的文字」（無文字層 PDF 情境）',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_search_empty',
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
    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('pdf_search_field')), 'anything');
    await tester.runAsync(() async {
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(find.byKey(const Key('pdf_search_empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
```

檔案開頭確認已 import（若尚未 import 則新增）：
```dart
import 'package:elinkbook/screens/pdf_search_panel.dart';
```

- [x] **Step 6: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "PDF 搜尋" --reporter expanded`
Expected: 3 項全數通過。

- [x] **Step 7: 重複執行 3 次確認無間歇性失敗**

Run（重複 3 次）：`flutter test test/screens/reader_screen_test.dart --plain-name "PDF 搜尋"`
Expected: 3 次執行皆全數通過（比照 Issue 4/5 審查發現 Timer/動畫時序競態的教訓，新增的非同步互動測試務必重跑數次確認穩定）。

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-24): ReaderScreen 接上 PDF 搜尋執行與上一個/下一個導覽邏輯"
```

---

### Task 7: 端對端驗證

**Files:** 無新增/修改，純驗證。

- [x] **Step 1: 全量 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 2: Issue 6 相關測試檔案合併執行三次，確認無間歇性失敗**

Run（重複 3 次）：
```bash
flutter test test/reader/pdf_search_geometry_test.dart test/reader/pdf_search_state_test.dart \
  test/reader/pdf_reader_view_search_test.dart test/screens/toc_bottom_sheet_test.dart \
  test/screens/toc_bottom_sheet_pdf_test.dart test/screens/pdf_search_panel_test.dart \
  test/screens/reader_screen_test.dart
```
Expected: 3 次執行皆全數通過。

- [x] **Step 3: 全專案測試套件**

Run: `flutter test`
Expected: 全數通過，通過總數應為 Issue 5 合併時的基準（1094）之上，新增本工單測試數（Task1 +8、Task2 +3、Task3 +7、Task4 +2、Task5 +7、Task6 +3，共 +30）。

- [x] **Step 4: 對照 `issues.md` Issue 6 驗收條件逐項自我檢查**

- 輸入關鍵字後，正確找出文件內所有符合位置並以高亮標示——Task 3（`_search`／`_buildSearchHighlightWidget`）。
- 「下一個/上一個」導覽正確依序跳轉至各符合位置對應頁面——Task 6（`_goToPdfSearchMatch`）。
- 對無文字層的 PDF（掃描件）搜尋時，UI 顯示合理的「無結果」而非錯誤或無回應——Task 5（`pdf_search_empty` 狀態）／Task 6（`sample.pdf` 情境測試）。
- 搜尋分頁正確掛載於 Issue 5 的目錄 Bottom Sheet 殼層內，透過既有「目錄」FAB 開啟後可切換至此分頁——Task 4／Task 6。
- 單元測試：`flutter test` 對含可搜尋文字的 fixture 驗證搜尋結果數量、位置、導覽行為——Task 3／Task 6。
- `flutter analyze` 乾淨、`flutter test` 全數通過——Step 1／Step 3。

- [x] **Step 5: 更新本工單計畫檔案的完成狀態**

回頭把本檔案（`docs/epics/epic-24-pdf-engine-rebuild/plans/plan-issue-6.md`）所有已完成 Task 的 `- [x]` 改為 `- [x]`。

- [x] **Step 6: 提交追蹤性 commit（若 Step 5 有變更）**

```bash
git add docs/epics/epic-24-pdf-engine-rebuild/plans/plan-issue-6.md
git commit -m "docs(epic-24): plan-issue-6 全部 Task 標記完成"
```

（後續發 PR／合併／更新 `docs/epics.md`／`issues.md`／`CLAUDE.md` 進度，比照 Issue 1-5 已建立的既有流程，屬本計畫執行完成之後的下一步，不在本計畫範圍內。）
