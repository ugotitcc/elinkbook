# Epic 27 Issue 11 — 長按已畫線區域改由畫線工具列統一處理 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 長按已畫線文字時，不再依賴瀏覽器原生 `click` 事件觸發刪除確認視窗（這條路徑已被真機 log 證實會被原生選字搶走，永遠不會發生）。改成：長按（不論有沒有畫線）一律跳出同一個 `AnnotationToolbar`；若長按處剛好命中既有畫線／備註，工具列上多出「刪除」按鈕（可刪除、也可編輯既有備註），並新增「複製」按鈕把選取文字複製到剪貼簿。工具列改為雙列版面。範圍涵蓋 EPUB（含 KF8/TXT/MD）與 PDF。

**Architecture:** EPUB 端在 `main.js` 的 `reportSelection()` 內，用 `view.js` 既有公開方法 `overlayer.hitTest()` 查詢選取範圍是否命中既有畫線/備註裝飾，連同選取文字一起送給 Dart 端；PDF 端框選本身就是純 Flutter 手勢（不經 WebView），直接用矩形重疊比對 `Highlight`/`Note` 既有的 `pdfRect`。兩條路徑最終都收斂成同一個 `AnnotationListItem?`（命中就非 null），供 `AnnotationToolbar` 決定要不要顯示「刪除」按鈕、以及「備註」按鈕要新增還是編輯。完全移除舊的 `_showAnnotationActionDialog`／`onAnnotationActivated`／JS `show-annotation` 監聽器。

**Tech Stack:** Flutter/Dart（`app/lib`）＋ JS 整合層（`app/android/app/src/main/assets/foliate/main.js`，不修改 vendored 檔案，ADR 0011）；PDF 文字萃取用既有 `pdfrx` 的 `page.loadStructuredText()`。

**Spec:** `docs/superpowers/specs/2026-08-24-epic27-issue11-annotation-toolbar-merge-design.md`（已依審查報告 `docs/epics/epic-27-reader-device-compat/reviews/review-issue-11-annotation-toolbar-merge-design.md` 修訂）；工單原文 `docs/epics/epic-27-reader-device-compat/issues.md` Issue 11。

## 立案依據說明（回應 `issues.md` 現行文字與本計畫的落差）

`issues.md` 目前 Issue 11 的 `Status` 欄寫的是 `needs-info`，且明文「修法需要設計決策...不建議在未經人類/設計討論前直接動手改」。這個設計決策已經在 2026-08-24 透過 `superpowers:brainstorming` 與人類逐項討論定案（範圍涵蓋 EPUB+PDF、完全汰除舊機制、備註按鈕改為編輯既有備註三項關鍵決策），並寫成上述設計文件、經過一輪審查修正。本計畫據此直接進入實作；`issues.md` 將於本計畫完成後同步更新 Status 與根因/解法段落（見文末「完成後的驗證」）。

## 與設計文件的落差說明（撰寫計畫時發現的簡化，皆為降低風險/複雜度，不改變功能範圍）

撰寫本計畫時，比對實際程式碼發現設計文件有 3 處可以簡化，記錄如下（皆已與設計文件的目標一致，只是實作細節更精簡）：

1. **`PdfSelectionInfo` 不新增 `existingAnnotationId` 欄位。** 設計文件原本讓 EPUB／PDF 對稱都加這個欄位，但 PDF 的框選本來就在 `reader_screen.dart`（持有 `_highlights`/`_notes`）算完就直接用，不需要像 EPUB 那樣跨 WebView bridge 傳遞一個編碼字串再解碼回來。`PdfSelectionInfo` 只新增 `text` 欄位。
2. **不寫 `_rectsOverlap` 自訂函式。** `pdfrx_engine` 的 `PdfRect` 類別本來就有公開方法 `overlaps(PdfRect other)`（`pdfrx_engine-0.4.5/lib/src/pdf_rect.dart:81-86`），直接呼叫即可。
3. **`_resolveExistingAnnotation`／PDF 命中判斷改寫成獨立檔案的頂層純函式**（`app/lib/reader/annotation_resolution.dart`），不是 `_ReaderScreenState` 的私有方法。純函式不依賴 State，可以直接用 `test()` 單元測試（不需要 `testWidgets`/pump 整個 `ReaderScreen`），也更符合「檔案結構：每個檔案一個清楚職責」的原則。因此設計文件裡的 `encodeAnnotationId` 也不需要新增——PDF 路徑不會產生也不需要解碼字串。

`text` 欄位（`EpubSelectionInfo`/`PdfSelectionInfo`）採預設值 `''`（而非設計文件寫的 `required`），理由：專案內既有 9 處測試呼叫點（`reader_screen_test.dart`）直接建構這兩個類別但不關心 `text`，給預設值可以避免不必要的測試churn（Surgical Changes 原則），不影響任何實際行為——正式呼叫端（JS 橋接／PDF 文字萃取）一律會明確傳入真正的文字。

## Global Constraints

- 不修改任何 vendored 檔案內容（`paginator.js`／`view.js`／`epub.js`／`overlayer.js`／`fixed-layout.js`），只呼叫其既有公開方法（ADR 0011）。
- 每個 Task 完成後執行 `cd app && flutter analyze`，必須維持「No issues found!」。
- 每個 Task 完成後執行對應範圍的 `flutter test`（至少涵蓋該 Task 修改到的測試檔），最後一個 Task 完成後需執行全專案 `flutter test`，零回歸。
- PDF 座標系換算務必使用 `pdfRectToPercentRect`/`percentRectToPdfRect` 這組互逆函式（`pdf_search_geometry.dart`），不可自行用 `rect.top * pageHeight` 這種未做 Y 軸翻轉的算法直接建構 `PdfRect`（會觸發其建構子的 `assert(top >= bottom)`，見審查報告 Important #1）。
- 所有 Dart 檔案內的中文註解與商業邏輯說明沿用正體中文，比照全專案既有慣例。

---

### Task 1：PDF 座標反向轉換 `percentRectToPdfRect`

**Files:**
- Modify: `app/lib/reader/pdf_search_geometry.dart`
- Test: `app/test/reader/pdf_search_geometry_test.dart`

**Interfaces:**
- Consumes: 無新增——沿用既有 `PercentRect`（`app/lib/reader/percent_rect.dart`）與 `pdfrx` 套件的 `PdfRect`。
- Produces: `PdfRect percentRectToPdfRect({required PercentRect rect, required double pageWidth, required double pageHeight})`，供 Task 4 的 PDF 文字萃取使用。

- [ ] **Step 1：寫失敗的測試——驗證 `percentRectToPdfRect` 與既有 `pdfRectToPercentRect` 互為反函式**

在 `app/test/reader/pdf_search_geometry_test.dart` 的 `pdfRectToPercentRect` 這個 `group` 結尾 `});`（第 54 行）之後、`PdfSearchMatch 值相等性` 這個 `group` 開始之前，新增：

```dart
  group('percentRectToPdfRect', () {
    test('與 pdfRectToPercentRect 互為反函式（US Letter 612x792）', () {
      const original = PdfRect(153, 594, 459, 198);
      final percent = pdfRectToPercentRect(rect: original, pageWidth: 612, pageHeight: 792);
      final restored = percentRectToPdfRect(rect: percent, pageWidth: 612, pageHeight: 792);
      expect(restored.left, closeTo(original.left, 0.001));
      expect(restored.right, closeTo(original.right, 0.001));
      expect(restored.top, closeTo(original.top, 0.001));
      expect(restored.bottom, closeTo(original.bottom, 0.001));
    });

    test('換算結果一律滿足 PdfRect 的 top >= bottom（不觸發 assert）', () {
      const rect = PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.4);
      final result = percentRectToPdfRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.top, greaterThanOrEqualTo(result.bottom),
          reason: 'PercentRect.top（螢幕座標，數值較小）換算回 PdfRect 後，'
              '必須對應到較大的 top 值（PDF 座標左下角原點、Y 軸向上），'
              '否則 PdfRect 建構子的 assert(top >= bottom) 會直接拋出例外。');
    });

    test('頁面正中央的百分比矩形換算回 PDF points 座標正確', () {
      const rect = PercentRect(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75);
      final result = percentRectToPdfRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.left, closeTo(153, 0.001));
      expect(result.right, closeTo(459, 0.001));
      expect(result.top, closeTo(594, 0.001));
      expect(result.bottom, closeTo(198, 0.001));
    });
  });

```

**Files 匯入注意：** 本檔案已 `import 'package:pdfrx/pdfrx.dart';` 與 `import 'package:elinkbook/reader/percent_rect.dart';`（見既有第 2、5 行），不需新增 import。

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_search_geometry_test.dart`
Expected: 新增的 3 則測試 FAIL（`percentRectToPdfRect` 尚未定義），既有 8 則測試維持通過。

- [ ] **Step 3：實作 `percentRectToPdfRect`**

在 `app/lib/reader/pdf_search_geometry.dart` 檔案結尾（第 31 行 `pdfRectToPercentRect` 函式結束的 `}` 之後）新增：

```dart

/// [pdfRectToPercentRect] 的反向轉換，供 Issue 11「PDF 框選矩形換算回
/// PDF points 座標以查詢 charRects」使用。公式為代數逆推：
/// percentRect.top = 1.0 - pdfRect.top/pageHeight，故
/// pdfRect.top = (1.0 - percentRect.top) * pageHeight，bottom 同理。
PdfRect percentRectToPdfRect({
  required PercentRect rect,
  required double pageWidth,
  required double pageHeight,
}) {
  return PdfRect(
    rect.left * pageWidth,
    (1.0 - rect.top) * pageHeight,
    rect.right * pageWidth,
    (1.0 - rect.bottom) * pageHeight,
  );
}
```

- [ ] **Step 4：執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_search_geometry_test.dart`
Expected: 全部 11 則測試（既有 8 + 新增 3）PASS。

- [ ] **Step 5：`flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/pdf_search_geometry.dart app/test/reader/pdf_search_geometry_test.dart
git commit -m "feat(epic-27): Issue 11 Task 1——新增 percentRectToPdfRect PDF 座標反向轉換"
```

---

### Task 2：`EpubSelectionInfo`／`PdfSelectionInfo` 新增 `text` 欄位

**Files:**
- Modify: `app/lib/reader/epub_selection_info.dart`
- Modify: `app/lib/reader/pdf_selection_info.dart`
- Test: `app/test/reader/epub_selection_info_test.dart`
- Test: `app/test/reader/pdf_selection_info_test.dart`

**Interfaces:**
- Consumes: 無新增。
- Produces: `EpubSelectionInfo.text`（`String`，預設 `''`）、`PdfSelectionInfo.text`（`String`，預設 `''`），供 Task 3（EPUB）／Task 4（PDF）填入真正的選取文字，供 Task 7 的「複製」按鈕使用。

- [ ] **Step 1：寫失敗的測試——`text` 欄位參與相等性比較**

在 `app/test/reader/epub_selection_info_test.dart` 新增一則測試（附加在既有測試之後）：

```dart
  test('text 欄位不同時，兩個 EpubSelectionInfo 不視為相等', () {
    const a = EpubSelectionInfo(
      locatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.2,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
      text: 'hello',
    );
    const b = EpubSelectionInfo(
      locatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.2,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
      text: 'world',
    );
    expect(a == b, isFalse);
  });

  test('不傳 text 時預設為空字串，existingAnnotationId 預設為 null', () {
    const a = EpubSelectionInfo(
      locatorJson: '{"href":"/c1.xhtml"}',
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    );
    expect(a.text, '');
    expect(a.existingAnnotationId, isNull);
  });
```

在 `app/test/reader/pdf_selection_info_test.dart` 新增（附加在既有測試之後）：

```dart
  test('text 欄位不同時，兩個 PdfSelectionInfo 不視為相等', () {
    const a = PdfSelectionInfo(
      pageIndex: 3,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
      widgetRect: PercentRect(left: 0.15, top: 0.25, right: 0.35, bottom: 0.45),
      text: 'hello',
    );
    const b = PdfSelectionInfo(
      pageIndex: 3,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
      widgetRect: PercentRect(left: 0.15, top: 0.25, right: 0.35, bottom: 0.45),
      text: 'world',
    );
    expect(a == b, isFalse);
  });

  test('不傳 text 時預設為空字串', () {
    const a = PdfSelectionInfo(
      pageIndex: 0,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
      widgetRect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    );
    expect(a.text, '');
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/reader/epub_selection_info_test.dart test/reader/pdf_selection_info_test.dart`
Expected: 新增的 4 則測試 FAIL（`text` 具名參數不存在，編譯錯誤）。

- [ ] **Step 3：`EpubSelectionInfo` 新增欄位**

把 `app/lib/reader/epub_selection_info.dart` 整份改為：

```dart
import 'percent_rect.dart';

/// [EpubReaderView] 使用者原生選字手勢建立/變動選取範圍時回報的資訊
/// （epic-6-annotations Issue 2）。[rect] 為選取矩形相對於 AndroidView
/// 容器寬高的百分比值（見 [PercentRect]），供 Dart 端在
/// `ReaderScreen._buildBody` 既有的 Stack 座標系內定位浮動工具列。
///
/// [text]（epic-27-reader-device-compat Issue 11）為這次選取的文字內容
/// （JS 端 `selection.toString()`），供 `AnnotationToolbar` 的「複製」
/// 按鈕使用；預設空字串。[existingAnnotationId]（同 Issue 11）為 JS 端用
/// `overlayer.hitTest()` 查出這次選取是否命中既有畫線/備註裝飾的結果
/// （`decodeAnnotationId` 相容格式，例如 `"highlight:5"`），沒命中為
/// `null`，供 `resolveEpubExistingAnnotation`
/// （`annotation_resolution.dart`）反查是哪一筆記錄。
class EpubSelectionInfo {
  final String locatorJson;
  final double? progression;
  final PercentRect rect;
  final String text;
  final String? existingAnnotationId;

  const EpubSelectionInfo({
    required this.locatorJson,
    this.progression,
    required this.rect,
    this.text = '',
    this.existingAnnotationId,
  });

  @override
  bool operator ==(Object other) =>
      other is EpubSelectionInfo &&
      other.locatorJson == locatorJson &&
      other.progression == progression &&
      other.rect == rect &&
      other.text == text &&
      other.existingAnnotationId == existingAnnotationId;

  @override
  int get hashCode =>
      Object.hash(locatorJson, progression, rect, text, existingAnnotationId);

  @override
  String toString() =>
      'EpubSelectionInfo(locatorJson: $locatorJson, progression: $progression, '
      'rect: $rect, text: $text, existingAnnotationId: $existingAnnotationId)';
}
```

- [ ] **Step 4：`PdfSelectionInfo` 新增欄位**

把 `app/lib/reader/pdf_selection_info.dart` 整份改為：

```dart
import 'percent_rect.dart';

/// [PdfReaderView] 使用者長按拖曳框選劃線範圍完成時回報的資訊
/// （epic-6-annotations Issue 3）。[rect] 為框選矩形相對「目前顯示中
/// bitmap 內容範圍」的百分比值（見 plan-issue-3.md Global Constraints
/// 「PDF 座標協定」），供持久化（[Highlight]/[Note]）與 Bitmap 重繪使用，
/// 內容範圍不含 letterbox 留白。[widgetRect] 為同一筆框選改以相對「整個
/// widget/View 尺寸」（含 letterbox 留白）換算出的百分比值，僅供 UI
/// 定位使用（例如浮動 `AnnotationToolbar`）——PAGE_FIT 模式下頁面經常因
/// 長寬比與螢幕不同而產生 letterbox，若拿 [rect] 直接乘上整個 widget
/// 尺寸來定位 UI，會偏移 letterbox 留白的量（見 review 修正 Finding 1）。
/// [pageIndex] 為框選發生的頁碼（0-indexed）。
///
/// [text]（epic-27-reader-device-compat Issue 11）為框選矩形內萃取出的
/// 文字（見 `_PdfReaderViewState._extractTextInRect`），供
/// `AnnotationToolbar` 的「複製」按鈕使用；預設空字串。PDF 沒有對應
/// EPUB 的 `existingAnnotationId` 欄位——PDF 的既有標記命中判斷直接在
/// `ReaderScreen`（已持有 `_highlights`/`_notes`）用
/// `resolvePdfExistingAnnotation` 純函式計算，不需要像 EPUB 那樣跨
/// WebView bridge 傳遞一個中間編碼字串。
class PdfSelectionInfo {
  final int pageIndex;
  final PercentRect rect;
  final PercentRect widgetRect;
  final String text;

  const PdfSelectionInfo({
    required this.pageIndex,
    required this.rect,
    required this.widgetRect,
    this.text = '',
  });

  @override
  bool operator ==(Object other) =>
      other is PdfSelectionInfo &&
      other.pageIndex == pageIndex &&
      other.rect == rect &&
      other.widgetRect == widgetRect &&
      other.text == text;

  @override
  int get hashCode => Object.hash(pageIndex, rect, widgetRect, text);

  @override
  String toString() =>
      'PdfSelectionInfo(pageIndex: $pageIndex, rect: $rect, widgetRect: $widgetRect, text: $text)';
}
```

- [ ] **Step 5：執行測試確認通過**

Run: `cd app && flutter test test/reader/epub_selection_info_test.dart test/reader/pdf_selection_info_test.dart`
Expected: 全部測試 PASS（既有 2 則 + 新增 4 則）。

- [ ] **Step 6：全專案編譯檢查（確認預設值讓既有 9 處呼叫點不受影響）**

Run: `cd app && flutter analyze`
Expected: `No issues found!`（若這裡出現 `text`/`existingAnnotationId` 相關錯誤，代表某處呼叫點使用了不支援具名參數的方式建構，需檢查是否誤用 positional 建構）。

- [ ] **Step 7：Commit**

```bash
git add app/lib/reader/epub_selection_info.dart app/lib/reader/pdf_selection_info.dart app/test/reader/epub_selection_info_test.dart app/test/reader/pdf_selection_info_test.dart
git commit -m "feat(epic-27): Issue 11 Task 2——EpubSelectionInfo/PdfSelectionInfo 新增 text 欄位"
```

---

### Task 3：EPUB 端 JS 橋接——選取範圍 hit-test 既有標記＋回傳選取文字

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`（約第 674-707 行 `reportSelection` 閉包）
- Modify: `app/lib/reader/foliate_reader_view.dart`（約第 666-684 行 `onSelectionChanged` handler）
- Test: `app/test/reader/foliate_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `EpubSelectionInfo.text`/`existingAnnotationId`。
- Produces: `main.js` 的 `callHandler('onSelectionChanged', ...)` 送出 8 個位置參數（原 6 個 + `text` + `existingAnnotationId`）；`foliate_reader_view.dart` 的 `widget.onSelectionChanged` 回呼收到完整填入 `text`/`existingAnnotationId` 的 `EpubSelectionInfo`。

- [ ] **Step 1：寫失敗的靜態內容回歸測試**

在 `app/test/reader/foliate_reader_view_test.dart`，找到既有的「main.js 選取收尾保護期（Selection Release Guard）regression guard（Epic 27 Issue 10）」這個 `group`（Issue 10 新增，見 plan-issue-10.md），在它結尾的 `});` 之後新增：

```dart
  group('main.js 選取範圍 hit-test 既有標記＋回傳文字 regression guard'
      '（Epic 27 Issue 11）', () {
    late String mainJsSource;

    setUpAll(() {
      mainJsSource = File('android/app/src/main/assets/foliate/main.js')
          .readAsStringSync();
    });

    test('reportSelection 內含 overlayer.hitTest 呼叫，位置晚於取得 rect、早於 callHandler',
        () {
      const rectCall = 'const rect = range.getClientRects()[0]';
      const hitTestCall = '.hitTest({ x: (rect.left + rect.right) / 2, y: (rect.top + rect.bottom) / 2 })';
      const callHandlerCall = "window.flutter_inappwebview.callHandler(\n          'onSelectionChanged',";

      final rectIndex = mainJsSource.indexOf(rectCall);
      final hitTestIndex = mainJsSource.indexOf(hitTestCall);
      final callHandlerIndex = mainJsSource.indexOf(callHandlerCall);

      expect(rectIndex, greaterThanOrEqualTo(0),
          reason: 'main.js 內找不到 "$rectCall"——若上游改了寫法，下面的順序'
              '斷言也需要一併更新。');
      expect(hitTestIndex, greaterThanOrEqualTo(0),
          reason: 'main.js 內找不到 overlayer.hitTest 呼叫——選取範圍變動'
              '時應查詢是否命中既有畫線/備註裝飾（見'
              'docs/superpowers/specs/2026-08-24-epic27-issue11-'
              'annotation-toolbar-merge-design.md），若被刪掉，長按已畫線'
              '文字時工具列不會出現刪除按鈕。');
      expect(callHandlerIndex, greaterThanOrEqualTo(0),
          reason: 'main.js 內找不到既有的 onSelectionChanged callHandler '
              '呼叫——若上游改了寫法，下面的順序斷言也需要一併更新。');
      expect(rectIndex, lessThan(hitTestIndex),
          reason: 'hitTest 必須在取得 rect 之後才能執行（需要 rect 座標）。');
      expect(hitTestIndex, lessThan(callHandlerIndex),
          reason: 'hitTest 的結果必須在 callHandler 呼叫之前算好，才能當作'
              '參數送出。');
    });

    test('decorationIdByCfi.get 用於反查 hit 結果對應的既有標記 id', () {
      expect(mainJsSource.contains('decorationIdByCfi.get(hitCfi)'), isTrue,
          reason: 'main.js 內找不到 "decorationIdByCfi.get(hitCfi)"——hitTest '
              '查到的是 cfi 字串，須反查回 Dart 端可解讀的 "highlight:x"/'
              '"note:y" 格式，否則 existingAnnotationId 永遠等於 hitTest '
              '回傳的原始 cfi，reader_screen.dart 的 decodeAnnotationId '
              '會解析失敗。');
    });

    test('callHandler(onSelectionChanged, ...) 最後兩個參數依序為選取文字與 existingAnnotationId',
        () {
      const callHandlerCall = "window.flutter_inappwebview.callHandler(\n          'onSelectionChanged',";
      final callHandlerIndex = mainJsSource.indexOf(callHandlerCall);
      expect(callHandlerIndex, greaterThanOrEqualTo(0));

      const textArg = 'selection.toString(),';
      const idArg = 'existingAnnotationId,';
      final textArgIndex = mainJsSource.indexOf(textArg, callHandlerIndex);
      final idArgIndex = mainJsSource.indexOf(idArg, callHandlerIndex);

      expect(textArgIndex, greaterThanOrEqualTo(0),
          reason: 'callHandler(onSelectionChanged, ...) 呼叫內找不到 '
              '"$textArg"——選取文字須一併送給 Dart 端，供「複製」按鈕使用。');
      expect(idArgIndex, greaterThanOrEqualTo(0),
          reason: 'callHandler(onSelectionChanged, ...) 呼叫內找不到 '
              '"$idArg"——hit-test 結果須一併送給 Dart 端。');
      expect(textArgIndex, lessThan(idArgIndex),
          reason: '選取文字必須排在 existingAnnotationId 之前（對應 Dart 端 '
              'args[6]/args[7] 的固定順序，foliate_reader_view.dart 的 '
              'onSelectionChanged handler 依此順序解析）。');
    });
  });
```

**Files 匯入注意：** 本檔案已 `import 'dart:io';`（見 Issue 10 既有 group 用到 `File(...)`），不需新增 import。

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/reader/foliate_reader_view_test.dart`
Expected: 新增的 3 則測試 FAIL（`main.js` 尚未有 `overlayer.hitTest`/`decorationIdByCfi.get(hitCfi)`/新增的 2 個參數），既有測試維持通過。

- [ ] **Step 3：修改 `main.js` 的 `reportSelection`**

在 `app/android/app/src/main/assets/foliate/main.js`，找到 `reportSelection` 閉包內（約第 691-707 行）：

```js
        const range = selection.getRangeAt(0)
        const rect = range.getClientRects()[0]
        if (!rect) return
        const cfi = view.getCFI(index, range)
        const progress = await view.getCFIProgress(cfi)
        const iframeRect = doc.defaultView.frameElement.getBoundingClientRect()
        const viewportRect = view.getBoundingClientRect()
        window.flutter_inappwebview.callHandler(
          'onSelectionChanged',
          JSON.stringify({ cfi, index, fraction: progress?.fraction ?? 0 }),
          progress?.fraction ?? 0,
          (iframeRect.left + rect.left - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.top - viewportRect.top) / viewportRect.height,
          (iframeRect.left + rect.right - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.bottom - viewportRect.top) / viewportRect.height,
        )
```

改為：

```js
        const range = selection.getRangeAt(0)
        const rect = range.getClientRects()[0]
        if (!rect) return
        const cfi = view.getCFI(index, range)
        const progress = await view.getCFIProgress(cfi)
        const iframeRect = doc.defaultView.frameElement.getBoundingClientRect()
        const viewportRect = view.getBoundingClientRect()
        // epic-27-reader-device-compat Issue 11：長按已畫線文字時，原生
        // 選字機制會搶先啟動，click 事件永遠不會發生，靠 click 觸發的舊版
        // 刪除確認機制形同虛設（見 bugfix-repro.md「Issue 10」新問題 A）。
        // 改成每次選取範圍變動時，直接查詢這次選取是否命中既有的畫線/
        // 備註裝飾，讓 Dart 端能在同一個 AnnotationToolbar 上顯示「刪除」
        // 按鈕。overlayer.hitTest() 是 view.js 既有公開方法，只用選取範圍
        // 第一個 client rect 的中點做判斷（已知簡化，見上述設計文件），
        // 不修改任何 vendored 檔案（ADR 0011）。
        const overlayerEntry = view.renderer.getContents().find(c => c.index === index)
        const hit = overlayerEntry?.overlayer
          ? overlayerEntry.overlayer.hitTest({ x: (rect.left + rect.right) / 2, y: (rect.top + rect.bottom) / 2 })
          : []
        const hitCfi = hit[0]
        const existingAnnotationId = hitCfi ? (decorationIdByCfi.get(hitCfi) ?? null) : null
        window.flutter_inappwebview.callHandler(
          'onSelectionChanged',
          JSON.stringify({ cfi, index, fraction: progress?.fraction ?? 0 }),
          progress?.fraction ?? 0,
          (iframeRect.left + rect.left - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.top - viewportRect.top) / viewportRect.height,
          (iframeRect.left + rect.right - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.bottom - viewportRect.top) / viewportRect.height,
          selection.toString(),
          existingAnnotationId,
        )
```

- [ ] **Step 4：修改 `foliate_reader_view.dart` 的 `onSelectionChanged` handler**

在 `app/lib/reader/foliate_reader_view.dart`，找到（約第 666-684 行）：

```dart
      handlerName: 'onSelectionChanged',
      callback: (args) {
        // 審查修正：同 onLocatorChanged，改用防禦性轉型取代直接強制轉型。
        num? argAt(int index) =>
            args.length > index ? args[index] as num? : null;
        _hasActiveSelection = true;
        widget.onSelectionChanged?.call(EpubSelectionInfo(
          locatorJson: args.isNotEmpty ? args[0] as String : '',
          progression: argAt(1)?.toDouble() ?? 0.0,
          rect: PercentRect(
            left: argAt(2)?.toDouble() ?? 0.0,
            top: argAt(3)?.toDouble() ?? 0.0,
            right: argAt(4)?.toDouble() ?? 0.0,
            bottom: argAt(5)?.toDouble() ?? 0.0,
          ),
        ));
      },
```

改為：

```dart
      handlerName: 'onSelectionChanged',
      callback: (args) {
        // 審查修正：同 onLocatorChanged，改用防禦性轉型取代直接強制轉型。
        num? argAt(int index) =>
            args.length > index ? args[index] as num? : null;
        _hasActiveSelection = true;
        widget.onSelectionChanged?.call(EpubSelectionInfo(
          locatorJson: args.isNotEmpty ? args[0] as String : '',
          progression: argAt(1)?.toDouble() ?? 0.0,
          rect: PercentRect(
            left: argAt(2)?.toDouble() ?? 0.0,
            top: argAt(3)?.toDouble() ?? 0.0,
            right: argAt(4)?.toDouble() ?? 0.0,
            bottom: argAt(5)?.toDouble() ?? 0.0,
          ),
          // epic-27-reader-device-compat Issue 11：main.js 新增送出的選取
          // 文字與 hit-test 結果，見上方 JS 端 reportSelection() 註解。
          text: args.length > 6 ? (args[6] as String? ?? '') : '',
          existingAnnotationId: args.length > 7 ? args[7] as String? : null,
        ));
      },
```

**說明（本步驟不需另外新增 widget test）：** 這段 JS→Dart 參數解析邏輯與既有 6 個參數的解析邏輯屬於同一種「WebView JS 橋接的薄轉接層」，本專案既有慣例（`foliate_reader_view_test.dart` 全檔案沒有任何測試直接呼叫 `addJavaScriptHandler` 註冊的內部 callback，一律靠 Step 1 的靜態內容檢查驗證 JS 端送出正確的資料形狀，實際的下游行為由 Task 7 在 `reader_screen_test.dart` 透過 `foliateView.onSelectionChanged?.call(EpubSelectionInfo(...))` 這個既有的 bypass 測試手法驗證）比照辦理，不新增測試基礎設施。

- [ ] **Step 5：執行測試確認通過**

Run: `cd app && flutter test test/reader/foliate_reader_view_test.dart`
Expected: 全部測試 PASS。

- [ ] **Step 6：`flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js app/lib/reader/foliate_reader_view.dart app/test/reader/foliate_reader_view_test.dart
git commit -m "feat(epic-27): Issue 11 Task 3——EPUB 選取範圍 hit-test 既有標記並回傳選取文字"
```

---

### Task 4：PDF 端框選文字萃取＋非同步競速防護

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Test: `app/test/reader/pdf_reader_view_selection_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `percentRectToPdfRect`；Task 2 的 `PdfSelectionInfo.text`。
- Produces: `_finishSelectionDrag()` 改為 `Future<void>`，完成後才呼叫 `widget.onSelectionRectComputed`（帶有真正萃取出的 `text`）；過期的萃取結果會被世代編號防護擋下，不會覆蓋新一次框選的狀態。

- [ ] **Step 1：寫失敗的測試——框選涵蓋整頁時，`onSelectionRectComputed` 回報的 `text` 內含頁面文字**

在 `app/test/reader/pdf_reader_view_selection_test.dart`，於檔案結尾（最後一個 `testWidgets` 之後、`}` 之前）新增：

```dart
  testWidgets('框選涵蓋整頁時，onSelectionRectComputed 回報的 text 內含頁面文字',
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

    final box = tester.getRect(find.byType(PdfReaderView));
    final startPos = Offset(box.left + 5, box.top + 5);
    final endPos = Offset(box.right - 5, box.bottom - 5);

    final gesture = await tester.startGesture(startPos);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(endPos);
    await tester.pump();
    // page.loadStructuredText() 是真實 FFI 呼叫，需要 tester.runAsync 才能
    // 真正推進（比照既有搜尋測試 pdf_reader_view_search_test.dart 的既定
    // 手法：await tester.runAsync(() => PdfReaderView.search(key, 'Page'))）。
    await tester.runAsync(() async {
      await gesture.up();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();

    expect(computed, isNotNull);
    expect(computed!.text.toLowerCase(), contains('page'),
        reason: '框選涵蓋整頁時應萃取出頁面上的文字內容（例如 "Page 1"，'
            '見 pdf_reader_view_search_test.dart 已驗證此 fixture 每頁'
            '皆含 "Page" 字樣）。');
  });

  testWidgets('框選完成後文字萃取尚未完成前又開始下一次框選，只有最後一次結果生效（競速防護）',
      (tester) async {
    var renderedCount = 0;
    final results = <PdfSelectionInfo>[];
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onSelectionRectComputed: (info) => results.add(info),
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final box = tester.getRect(find.byType(PdfReaderView));

    // 第一次框選：放開手指、觸發文字萃取，但刻意不用 tester.runAsync 讓它
    // 有機會真正推進（沒有 runAsync 包住，真實 FFI 呼叫不會實際完成），
    // 模擬「文字萃取還卡在半路」的狀態。
    final firstGesture = await tester.startGesture(
      Offset(box.left + 5, box.top + 5),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await firstGesture.moveTo(Offset(box.left + 100, box.top + 100));
    await tester.pump();
    await firstGesture.up();
    await tester.pump();

    // 第二次框選：在第一次的文字萃取還沒完成前就開始，正常完整跑完。
    final secondGesture = await tester.startGesture(
      Offset(box.left + 5, box.top + 5),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await secondGesture.moveTo(Offset(box.right - 5, box.bottom - 5));
    await tester.pump();
    await tester.runAsync(() async {
      await secondGesture.up();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();

    // 讓第一次可能還卡著的文字萃取有機會跑完——若世代編號防護失效，
    // 這裡才會補上一筆過期結果。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(results.length, 1,
        reason: '第一次框選的過期文字萃取結果應被世代編號防護擋下，不應'
            '呼叫 onSelectionRectComputed；只有第二次（最新一次）框選的'
            '結果應該送達，否則使用者新一次框選的狀態會被過期結果覆蓋'
            '（見審查報告 Important #2）。');
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 新增的 2 則測試 FAIL（`PdfSelectionInfo` 目前永遠 `text: ''`；`_finishSelectionDrag` 仍是同步、沒有世代編號防護，第二則測試可能因 `results.length` 不等於 1 而失敗，或因當前同步實作根本不會有過期結果問題而通不過「有意義」檢查——兩則皆預期先 FAIL）。

- [ ] **Step 3：新增 `_selectionDragGenerationId` 欄位**

在 `app/lib/reader/pdf_reader_view.dart`，找到（約第 306 行）：

```dart
  _PdfSelectionDragState? _selectionDrag;
```

改為：

```dart
  _PdfSelectionDragState? _selectionDrag;
  // epic-27-reader-device-compat Issue 11：_finishSelectionDrag() 改為
  // 非同步（需要 await page.loadStructuredText() 萃取選取文字）後，任何
  // 會開始新框選手勢的地方都遞增這個世代編號；_finishSelectionDrag()
  // 在 await 之前先記下當下的編號，await 完成後比對編號是否仍相同，不同
  // 就代表使用者已經開始了下一次框選，這次的萃取結果是過期資料，直接
  // 丟棄不送出（比照既有 _searchSessionId 世代編號慣例，見 _search()）。
  int _selectionDragGenerationId = 0;
```

- [ ] **Step 4：`onLongPressStart` 遞增世代編號**

找到（約第 1124-1134 行）：

```dart
        onLongPressStart: (details) {
          if (widget.cropEditModeActive) return;
          setState(() {
            _selectionDrag = _PdfSelectionDragState(
              pageIndex: pageIndex,
              areaSize: pageRectInViewer.size,
              pageOffsetInViewer: pageRectInViewer.topLeft,
              start: details.localPosition,
            );
          });
        },
```

改為：

```dart
        onLongPressStart: (details) {
          if (widget.cropEditModeActive) return;
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
```

- [ ] **Step 5：新增 `_extractTextInRect`，`_finishSelectionDrag` 改為非同步**

找到（約第 1146-1175 行）：

```dart
  void _finishSelectionDrag() {
    final drag = _selectionDrag;
    if (drag == null) return;
    setState(() => _selectionDrag = null);
    final pageRelativeRect = percentRectFromDrag(
      start: drag.start,
      end: drag.current,
      areaSize: drag.areaSize,
    );
    if (pageRelativeRect == null) return; // 退化選取，等同取消。
    final originalRect = cropRelativeToOriginalPercent(
      rect: pageRelativeRect,
      cropRect: _cropEnabled ? widget.pdfCropRect : null,
    );
    final viewerSize = context.size;
    final widgetRect = viewerSize == null || viewerSize.isEmpty
        ? pageRelativeRect
        : percentRectFromDrag(
            start: drag.pageOffsetInViewer +
                Offset(drag.start.dx, drag.start.dy),
            end: drag.pageOffsetInViewer + Offset(drag.current.dx, drag.current.dy),
            areaSize: viewerSize,
            minFraction: 0,
          )!;
    widget.onSelectionRectComputed?.call(PdfSelectionInfo(
      pageIndex: drag.pageIndex,
      rect: originalRect,
      widgetRect: widgetRect,
    ));
  }
```

改為：

```dart
  /// 框選矩形內文字萃取（epic-27-reader-device-compat Issue 11）：把框選
  /// 的 [rect]（PercentRect，同一套換算慣例見 percent_rect.dart）換算回
  /// PDF points 座標，找出落在這個矩形內的字元，組成文字供「複製」按鈕
  /// 使用。座標系換算必須用 percentRectToPdfRect（見審查報告 Important
  /// #1）——PercentRect 是左上角原點、Y 軸向下，PdfRect 是左下角原點、
  /// Y 軸向上，方向相反，不能直接相乘頁面尺寸後原樣塞進 PdfRect。
  Future<String> _extractTextInRect(int pageIndex, PercentRect rect) async {
    final document = _document;
    if (document == null) return '';
    if (pageIndex < 0 || pageIndex >= document.pages.length) return '';
    final page = document.pages[pageIndex];
    final pageText = await page.loadStructuredText();
    final targetRect = percentRectToPdfRect(
      rect: rect,
      pageWidth: page.width,
      pageHeight: page.height,
    );
    final buffer = StringBuffer();
    for (var i = 0; i < pageText.charRects.length; i++) {
      if (pageText.charRects[i].overlaps(targetRect)) {
        buffer.write(pageText.fullText[i]);
      }
    }
    return buffer.toString();
  }

  Future<void> _finishSelectionDrag() async {
    final drag = _selectionDrag;
    if (drag == null) return;
    setState(() => _selectionDrag = null);
    final pageRelativeRect = percentRectFromDrag(
      start: drag.start,
      end: drag.current,
      areaSize: drag.areaSize,
    );
    if (pageRelativeRect == null) return; // 退化選取，等同取消。
    final originalRect = cropRelativeToOriginalPercent(
      rect: pageRelativeRect,
      cropRect: _cropEnabled ? widget.pdfCropRect : null,
    );
    final viewerSize = context.size;
    final widgetRect = viewerSize == null || viewerSize.isEmpty
        ? pageRelativeRect
        : percentRectFromDrag(
            start: drag.pageOffsetInViewer +
                Offset(drag.start.dx, drag.start.dy),
            end: drag.pageOffsetInViewer + Offset(drag.current.dx, drag.current.dy),
            areaSize: viewerSize,
            minFraction: 0,
          )!;
    // epic-27-reader-device-compat Issue 11（審查報告 Important #2）：
    // page.loadStructuredText() 是真實 FFI 呼叫，可能耗時；這段 await
    // 期間使用者可能離開畫面或開始下一次框選，過期結果不能覆蓋新狀態。
    final generationId = _selectionDragGenerationId;
    final text = await _extractTextInRect(drag.pageIndex, originalRect);
    if (!mounted || generationId != _selectionDragGenerationId) return;
    widget.onSelectionRectComputed?.call(PdfSelectionInfo(
      pageIndex: drag.pageIndex,
      rect: originalRect,
      widgetRect: widgetRect,
      text: text,
    ));
  }
```

**說明：** `onLongPressEnd: (details) => _finishSelectionDrag(),`（約第 1140 行）不需要修改——`_finishSelectionDrag` 改回傳 `Future<void>` 後，這個箭頭函式回傳值被隱式捨棄（fire-and-forget），這是合法的 `VoidCallback` 用法，本專案 `analysis_options.yaml` 未啟用 `unawaited_futures` 這類會標記此用法的 lint 規則。

- [ ] **Step 6：執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 全部測試 PASS（含既有 10 則 + 新增 2 則）。

- [ ] **Step 7：`flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_selection_test.dart
git commit -m "feat(epic-27): Issue 11 Task 4——PDF 框選文字萃取，補上非同步競速防護"
```

---

### Task 5：既有標記命中判斷（`annotation_resolution.dart`）＋ `PercentRect.overlaps`

**Files:**
- Create: `app/lib/reader/annotation_resolution.dart`
- Create: `app/test/reader/annotation_resolution_test.dart`
- Modify: `app/lib/reader/percent_rect.dart`
- Modify: `app/test/reader/percent_rect_test.dart`

**Interfaces:**
- Consumes: `AnnotationListItem`（`annotation_list_item.dart`）、`decodeAnnotationId`/`AnnotationKind`（`epub_decoration.dart`）、`Highlight`/`Note`（既有模型）、`PdfSelectionInfo`（Task 2）。
- Produces:
  - `AnnotationListItem? resolveEpubExistingAnnotation({required String? existingAnnotationId, required List<Highlight> highlights, required List<Note> notes})`
  - `AnnotationListItem? resolvePdfExistingAnnotation({required PdfSelectionInfo selection, required List<Highlight> highlights, required List<Note> notes})`
  - `PercentRect.overlaps(PercentRect other) → bool`
  這三者供 Task 7 在 `reader_screen.dart` 呼叫。

- [ ] **Step 1：寫失敗的測試——`PercentRect.overlaps`**

在 `app/test/reader/percent_rect_test.dart` 結尾（既有 3 則測試之後）新增：

```dart
  group('overlaps', () {
    test('兩個矩形有重疊區域時回傳 true', () {
      const a = PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.5);
      const b = PercentRect(left: 0.3, top: 0.3, right: 0.7, bottom: 0.7);
      expect(a.overlaps(b), isTrue);
      expect(b.overlaps(a), isTrue);
    });

    test('兩個矩形完全不重疊時回傳 false', () {
      const a = PercentRect(left: 0.1, top: 0.1, right: 0.2, bottom: 0.2);
      const b = PercentRect(left: 0.8, top: 0.8, right: 0.9, bottom: 0.9);
      expect(a.overlaps(b), isFalse);
    });

    test('兩個矩形僅邊緣相接（不重疊面積）時回傳 false', () {
      const a = PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.5);
      const b = PercentRect(left: 0.5, top: 0.1, right: 0.9, bottom: 0.5);
      expect(a.overlaps(b), isFalse);
    });
  });
```

在 `app/test/reader/annotation_resolution_test.dart`（新檔案）寫入：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/annotation_resolution.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  group('resolveEpubExistingAnnotation', () {
    test('existingAnnotationId 為 null 時回傳 null', () {
      final result = resolveEpubExistingAnnotation(
        existingAnnotationId: null,
        highlights: const [],
        notes: const [],
      );
      expect(result, isNull);
    });

    test('命中畫線 id 時回傳含該畫線與其依附備註的 AnnotationListItem', () {
      const highlight = Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: '{"cfi":"epubcfi(/6/4)"}',
      );
      const note = Note(
        id: 'n1',
        bookId: 'b1',
        text: 'note text',
        epubLocatorJson: '{"cfi":"epubcfi(/6/4)"}',
        highlightId: 'h1',
      );
      final result = resolveEpubExistingAnnotation(
        existingAnnotationId: 'highlight:h1',
        highlights: const [highlight],
        notes: const [note],
      );
      expect(result?.highlight?.id, 'h1');
      expect(result?.note?.id, 'n1');
    });

    test('命中純備註 id 時回傳只含備註的 AnnotationListItem', () {
      const note = Note(
        id: 'n2',
        bookId: 'b1',
        text: 'standalone note',
        epubLocatorJson: '{"cfi":"epubcfi(/6/8)"}',
      );
      final result = resolveEpubExistingAnnotation(
        existingAnnotationId: 'note:n2',
        highlights: const [],
        notes: const [note],
      );
      expect(result?.highlight, isNull);
      expect(result?.note?.id, 'n2');
    });

    test('id 格式合法但查無對應記錄時回傳 null', () {
      final result = resolveEpubExistingAnnotation(
        existingAnnotationId: 'highlight:not-exist',
        highlights: const [],
        notes: const [],
      );
      expect(result, isNull);
    });
  });

  group('resolvePdfExistingAnnotation', () {
    test('框選矩形與既有畫線重疊時回傳含該畫線的 AnnotationListItem', () {
      const highlight = Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        pdfPageIndex: 0,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.3),
      );
      const selection = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
        widgetRect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
      );
      final result = resolvePdfExistingAnnotation(
        selection: selection,
        highlights: const [highlight],
        notes: const [],
      );
      expect(result?.highlight?.id, 'h1');
    });

    test('框選矩形與既有畫線不重疊時回傳 null', () {
      const highlight = Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        pdfPageIndex: 0,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.2, bottom: 0.2),
      );
      const selection = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.7, top: 0.7, right: 0.9, bottom: 0.9),
        widgetRect: PercentRect(left: 0.7, top: 0.7, right: 0.9, bottom: 0.9),
      );
      final result = resolvePdfExistingAnnotation(
        selection: selection,
        highlights: const [highlight],
        notes: const [],
      );
      expect(result, isNull);
    });

    test('不同頁的畫線即使矩形數值重疊也不命中（頁碼優先比對）', () {
      const highlight = Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        pdfPageIndex: 1,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.3),
      );
      const selection = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
        widgetRect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
      );
      final result = resolvePdfExistingAnnotation(
        selection: selection,
        highlights: const [highlight],
        notes: const [],
      );
      expect(result, isNull);
    });

    test('框選矩形與純備註（無畫線）重疊時回傳只含備註的 AnnotationListItem', () {
      const note = Note(
        id: 'n1',
        bookId: 'b1',
        text: 'pdf standalone note',
        pdfPageIndex: 0,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.3),
      );
      const selection = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
        widgetRect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
      );
      final result = resolvePdfExistingAnnotation(
        selection: selection,
        highlights: const [],
        notes: const [note],
      );
      expect(result?.note?.id, 'n1');
      expect(result?.highlight, isNull);
    });

    test('已依附於畫線的備註（highlightId 非 null）不會被當成獨立命中', () {
      const note = Note(
        id: 'n1',
        bookId: 'b1',
        text: 'attached note',
        pdfPageIndex: 0,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.3),
        highlightId: 'h-not-in-list',
      );
      const selection = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
        widgetRect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
      );
      final result = resolvePdfExistingAnnotation(
        selection: selection,
        highlights: const [],
        notes: const [note],
      );
      expect(result, isNull,
          reason: '比照 _sendPdfAnnotationsToNative 既有慣例，highlightId '
              '非 null 的備註是依附於某筆畫線顯示，不應被當成獨立的純'
              '備註命中。');
    });
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/reader/percent_rect_test.dart test/reader/annotation_resolution_test.dart`
Expected: `percent_rect_test.dart` 新增 3 則 FAIL（`overlaps` 未定義）；`annotation_resolution_test.dart` 因為 `annotation_resolution.dart` 檔案不存在而整份編譯失敗。

- [ ] **Step 3：`PercentRect` 新增 `overlaps`**

在 `app/lib/reader/percent_rect.dart`，於 `toString()` 方法（第 54-55 行）之前新增：

```dart
  /// 判斷此矩形與 [other] 是否有重疊區域（epic-27-reader-device-compat
  /// Issue 11，供 PDF 框選矩形比對既有畫線/備註使用）。僅邊緣相接（無
  /// 重疊面積）視為不重疊，比照 `pdfrx_engine` 的 `PdfRect.overlaps` 同一
  /// 慣例（不等式皆為嚴格 `<`/`>`）。
  bool overlaps(PercentRect other) {
    return left < other.right &&
        right > other.left &&
        top < other.bottom &&
        bottom > other.top;
  }

```

- [ ] **Step 4：新增 `annotation_resolution.dart`**

```dart
import 'annotation_list_item.dart';
import 'epub_decoration.dart';
import 'highlight.dart';
import 'note.dart';
import 'pdf_selection_info.dart';

/// 依 EPUB 選取範圍回報的 [existingAnnotationId]（JS 端 hit-test 結果，
/// 見 main.js `reportSelection()`），反查是哪一筆既有畫線/備註記錄
/// （epic-27-reader-device-compat Issue 11）。純函式，不依賴
/// `_ReaderScreenState` 內部狀態，方便獨立單元測試；[highlights]/[notes]
/// 由呼叫端傳入目前的完整清單。查無對應記錄（理論上不會發生，id 皆由
/// `EpubDecoration` 具名建構子產生）時回傳 `null`。
AnnotationListItem? resolveEpubExistingAnnotation({
  required String? existingAnnotationId,
  required List<Highlight> highlights,
  required List<Note> notes,
}) {
  if (existingAnnotationId == null) return null;
  final decoded = decodeAnnotationId(existingAnnotationId);
  if (decoded == null) return null;
  switch (decoded.kind) {
    case AnnotationKind.highlight:
      for (final highlight in highlights) {
        if (highlight.id == decoded.id) {
          Note? note;
          for (final n in notes) {
            if (n.highlightId == highlight.id) {
              note = n;
              break;
            }
          }
          return AnnotationListItem(highlight: highlight, note: note);
        }
      }
      return null;
    case AnnotationKind.note:
      for (final note in notes) {
        if (note.id == decoded.id) return AnnotationListItem(note: note);
      }
      return null;
  }
}

/// 依 PDF 框選矩形，掃描同一頁既有畫線/備註是否與框選矩形重疊
/// （epic-27-reader-device-compat Issue 11）。PDF 框選不像 EPUB 走
/// WebView，沒有 JS 端可以預先算好命中結果，直接在這裡用純 Dart 矩形
/// 重疊比對；先掃畫線（連同它依附的備註一併回傳），沒有才掃純備註（比照
/// `ReaderScreen._sendPdfAnnotationsToNative` 既有的
/// `note.highlightId == null` 判斷慣例，避免已依附畫線的備註被誤判為
/// 獨立命中）。
AnnotationListItem? resolvePdfExistingAnnotation({
  required PdfSelectionInfo selection,
  required List<Highlight> highlights,
  required List<Note> notes,
}) {
  for (final highlight in highlights) {
    if (highlight.pdfPageIndex == selection.pageIndex &&
        highlight.pdfRect != null &&
        highlight.pdfRect!.overlaps(selection.rect)) {
      Note? note;
      for (final n in notes) {
        if (n.highlightId == highlight.id) {
          note = n;
          break;
        }
      }
      return AnnotationListItem(highlight: highlight, note: note);
    }
  }
  for (final note in notes) {
    if (note.highlightId == null &&
        note.pdfPageIndex == selection.pageIndex &&
        note.pdfRect != null &&
        note.pdfRect!.overlaps(selection.rect)) {
      return AnnotationListItem(note: note);
    }
  }
  return null;
}
```

- [ ] **Step 5：執行測試確認通過**

Run: `cd app && flutter test test/reader/percent_rect_test.dart test/reader/annotation_resolution_test.dart`
Expected: 全部測試 PASS。

- [ ] **Step 6：`flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/reader/annotation_resolution.dart app/test/reader/annotation_resolution_test.dart app/lib/reader/percent_rect.dart app/test/reader/percent_rect_test.dart
git commit -m "feat(epic-27): Issue 11 Task 5——新增既有標記命中判斷純函式與 PercentRect.overlaps"
```

---

### Task 6：`AnnotationToolbar` 雙列改版——新增複製／刪除按鈕

**Files:**
- Modify: `app/lib/screens/annotation_toolbar.dart`
- Modify: `app/test/screens/annotation_toolbar_test.dart`

**Interfaces:**
- Consumes: 無新增（純 UI widget）。
- Produces: `AnnotationToolbar` 新增建構參數 `onCopyPressed`（`VoidCallback`，必填）、`onDeletePressed`（`VoidCallback?`，選填，`null` 代表不顯示刪除按鈕）、`deleteButtonLabel`（`String?`）、`hasExistingNote`（`bool`，預設 `false`）；新增 `Key('annotation_toolbar_copy')`／`Key('annotation_toolbar_delete')`。供 Task 7 呼叫。

- [ ] **Step 1：寫失敗的測試——新按鈕的顯示與互動**

在 `app/test/screens/annotation_toolbar_test.dart`，把既有 7 個 `testWidgets` 呼叫全部補上 `onCopyPressed: () {},`（放在 `onClosePressed` 之後），例如第一個測試改為：

```dart
  testWidgets('顯示螢光筆三色、底線、備註、關閉共 6 個按鈕', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (_) {},
          onNotePressed: () {},
          onClosePressed: () {},
          onCopyPressed: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('annotation_toolbar_highlighter_yellow')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_highlighter_pink')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_highlighter_blue')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_underline')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_note')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_close')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_copy')), findsOneWidget,
        reason: '雙列版面第二列應永遠顯示複製按鈕（epic-27 Issue 11）');
  });
```

其餘 6 個既有測試（第 26、42、58、74、90、106 行起）比照方式，在各自的 `AnnotationToolbar(...)` 建構內補上 `onCopyPressed: () {},`（值不影響該測試斷言，維持該測試原本聚焦的行為即可）。

然後在檔案結尾（第 121 行 `}` 之前）新增：

```dart

  testWidgets('點擊複製按鈕觸發 onCopyPressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (_) {},
          onNotePressed: () {},
          onClosePressed: () {},
          onCopyPressed: () => pressed = true,
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_copy')));
    expect(pressed, isTrue);
  });

  testWidgets('onDeletePressed 為 null 時不顯示刪除按鈕', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (_) {},
          onNotePressed: () {},
          onClosePressed: () {},
          onCopyPressed: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('annotation_toolbar_delete')), findsNothing);
  });

  testWidgets('onDeletePressed 非 null 時顯示刪除按鈕，tooltip 對應 deleteButtonLabel',
      (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (_) {},
          onNotePressed: () {},
          onClosePressed: () {},
          onCopyPressed: () {},
          onDeletePressed: () => pressed = true,
          deleteButtonLabel: '刪除畫線',
        ),
      ),
    ));

    final finder = find.byKey(const Key('annotation_toolbar_delete'));
    expect(finder, findsOneWidget);
    final button = tester.widget<IconButton>(finder);
    expect(button.tooltip, '刪除畫線');

    await tester.tap(finder);
    expect(pressed, isTrue);
  });

  testWidgets('hasExistingNote 為 true 時，備註按鈕 tooltip 顯示「編輯備註」；'
      'false 時顯示「新增備註」', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (_) {},
          onNotePressed: () {},
          onClosePressed: () {},
          onCopyPressed: () {},
          hasExistingNote: true,
        ),
      ),
    ));
    var button = tester.widget<IconButton>(find.byKey(const Key('annotation_toolbar_note')));
    expect(button.tooltip, '編輯備註');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (_) {},
          onNotePressed: () {},
          onClosePressed: () {},
          onCopyPressed: () {},
        ),
      ),
    ));
    button = tester.widget<IconButton>(find.byKey(const Key('annotation_toolbar_note')));
    expect(button.tooltip, '新增備註');
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/screens/annotation_toolbar_test.dart`
Expected: 全部測試 FAIL（`onCopyPressed` 具名參數不存在，整份檔案編譯錯誤）。

- [ ] **Step 3：改版 `AnnotationToolbar`**

把 `app/lib/screens/annotation_toolbar.dart` 整份改為：

```dart
import 'package:flutter/material.dart';

import '../reader/highlight_style.dart';

/// 選字/框選後浮現的浮動工具列（design.md「使用者流程」步驟 1-2；
/// EPUB（本 Issue）與 PDF（issues.md Issue 3）共用同一組 Widget）。
///
/// epic-27-reader-device-compat Issue 11 改版為雙列：第一列維持螢光筆
/// 三色＋底線＋關閉；第二列永遠顯示複製，並依這次選取是否命中既有畫線/
/// 備註（呼叫端已用 `resolveEpubExistingAnnotation`/
/// `resolvePdfExistingAnnotation` 算好）決定要不要一併顯示刪除按鈕、以及
/// 備註按鈕要顯示「新增」還是「編輯」。這個改版取代了舊有的
/// `_showAnnotationActionDialog`（原本靠原生 `click` 事件觸發，已被真機
/// log 證實會被瀏覽器原生選字搶走，永遠不會觸發，見
/// docs/superpowers/specs/2026-08-24-epic27-issue11-annotation-toolbar-
/// merge-design.md）。
///
/// 點擊螢光筆/底線立即觸發 [onStyleSelected]（呼叫端負責建立劃線，並保持
/// 選取狀態存在讓使用者能接著點備註）；點擊備註觸發 [onNotePressed]
/// （呼叫端依 [hasExistingNote] 決定要開新增還是編輯對話框，本 Widget
/// 只負責顯示對應文字，不含 Dialog 邏輯）；點擊關閉觸發 [onClosePressed]；
/// 點擊複製觸發 [onCopyPressed]（呼叫端負責把選取文字寫入剪貼簿）；
/// [onDeletePressed] 為 `null` 時不顯示刪除按鈕（代表這次選取沒有命中
/// 既有標記），非 `null` 時顯示，`tooltip` 使用 [deleteButtonLabel]。
class AnnotationToolbar extends StatelessWidget {
  final ValueChanged<HighlightStyle> onStyleSelected;
  final VoidCallback onNotePressed;
  final VoidCallback onClosePressed;
  final VoidCallback onCopyPressed;
  final VoidCallback? onDeletePressed;
  final String? deleteButtonLabel;
  final bool hasExistingNote;

  const AnnotationToolbar({
    super.key,
    required this.onStyleSelected,
    required this.onNotePressed,
    required this.onClosePressed,
    required this.onCopyPressed,
    this.onDeletePressed,
    this.deleteButtonLabel,
    this.hasExistingNote = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _colorButton(
                  key: const Key('annotation_toolbar_highlighter_yellow'),
                  color: highlighterYellowTint,
                  onTap: () => onStyleSelected(HighlightStyle.highlighterYellow),
                ),
                _colorButton(
                  key: const Key('annotation_toolbar_highlighter_pink'),
                  color: highlighterPinkTint,
                  onTap: () => onStyleSelected(HighlightStyle.highlighterPink),
                ),
                _colorButton(
                  key: const Key('annotation_toolbar_highlighter_blue'),
                  color: highlighterBlueTint,
                  onTap: () => onStyleSelected(HighlightStyle.highlighterBlue),
                ),
                IconButton(
                  key: const Key('annotation_toolbar_underline'),
                  icon: const Icon(Icons.format_underline),
                  tooltip: '底線',
                  onPressed: () => onStyleSelected(HighlightStyle.underline),
                ),
                IconButton(
                  key: const Key('annotation_toolbar_close'),
                  icon: const Icon(Icons.close),
                  tooltip: '關閉',
                  onPressed: onClosePressed,
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('annotation_toolbar_copy'),
                  icon: const Icon(Icons.copy),
                  tooltip: '複製',
                  onPressed: onCopyPressed,
                ),
                IconButton(
                  key: const Key('annotation_toolbar_note'),
                  icon: const Icon(Icons.edit_note),
                  tooltip: hasExistingNote ? '編輯備註' : '新增備註',
                  onPressed: onNotePressed,
                ),
                if (onDeletePressed != null)
                  IconButton(
                    key: const Key('annotation_toolbar_delete'),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: deleteButtonLabel,
                    onPressed: onDeletePressed,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorButton({
    required Key key,
    required Color color,
    required VoidCallback onTap,
  }) {
    return IconButton(
      key: key,
      icon: Icon(Icons.circle, color: color),
      onPressed: onTap,
    );
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run: `cd app && flutter test test/screens/annotation_toolbar_test.dart`
Expected: 全部測試 PASS（既有 7 則 + 新增 4 則）。

- [ ] **Step 5：`flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`（`reader_screen.dart` 目前呼叫 `AnnotationToolbar(...)` 的兩處尚未補上 `onCopyPressed` 這個新的必填參數，這裡會出現編譯錯誤，屬預期中——留給 Task 7 修正，本步驟只需確認 `annotation_toolbar.dart` 與其測試檔本身沒有問題，可用 `flutter analyze lib/screens/annotation_toolbar.dart test/screens/annotation_toolbar_test.dart` 縮小範圍確認，全專案分析要到 Task 7 結束才會乾淨）。

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/annotation_toolbar.dart app/test/screens/annotation_toolbar_test.dart
git commit -m "feat(epic-27): Issue 11 Task 6——AnnotationToolbar 改版雙列版面，新增複製/刪除按鈕"
```

---

### Task 7：`reader_screen.dart` 接線——刪除／編輯／複製功能上線

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 5 的 `resolveEpubExistingAnnotation`/`resolvePdfExistingAnnotation`；Task 6 的 `AnnotationToolbar` 新參數。
- Produces: `_handleDeleteExistingAnnotation`（EPUB）/`_handlePdfDeleteExistingAnnotation`（PDF）/`_handleCopySelection`/`_annotationDeleteButtonLabel` 新增方法；`_handleNotePressed`/`_handlePdfNotePressed` 改為依既有備註分流。

- [ ] **Step 1：寫失敗的測試——命中既有畫線時顯示刪除按鈕並可刪除（EPUB）**

在 `app/test/screens/reader_screen_test.dart`，找到「流式 EPUB：FoliateReaderView 回報 onAnnotationActivated 時，開啟對話框」這個測試（約第 3555-3609 行）**正上方**插入新測試（這個既有測試會在 Task 8 被移除，本步驟先在它之前新增，避免插入位置在 Task 8 刪除範圍內造成混淆）：

```dart
  testWidgets(
    '流式 EPUB：長按選取範圍命中既有畫線時，工具列顯示刪除按鈕，點擊後刪除該畫線',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      const highlightId = 'h_merge1';
      await highlightsRepo.insert(
        const Highlight(
          id: highlightId,
          bookId: 'b_foliate_merge1',
          style: HighlightStyle.highlighterYellow,
          epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_merge1',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      foliateView.onSelectionChanged?.call(
        const EpubSelectionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
          text: '選取的文字',
          existingAnnotationId: 'highlight:$highlightId',
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('annotation_toolbar_delete')), findsOneWidget,
          reason: '選取範圍命中既有畫線時，工具列應顯示刪除按鈕');

      await tester.tap(find.byKey(const Key('annotation_toolbar_delete')));
      await tester.pump();
      await tester.pump();

      expect(await highlightsRepo.listByBook('b_foliate_merge1'), isEmpty,
          reason: '點擊刪除按鈕後，該畫線應從 repository 移除');
      expect(find.byType(AnnotationToolbar), findsNothing,
          reason: '刪除後工具列應一併關閉');
    },
  );

  testWidgets(
    '流式 EPUB：長按選取範圍未命中既有標記時，工具列不顯示刪除按鈕',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_merge2',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      foliateView.onSelectionChanged?.call(
        const EpubSelectionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
          text: '沒有畫線的文字',
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsOneWidget);
      expect(find.byKey(const Key('annotation_toolbar_delete')), findsNothing);
    },
  );

  testWidgets(
    '流式 EPUB：長按選取範圍命中既有備註時，點擊備註按鈕開啟編輯對話框且文字已預填',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      const noteId = 'n_merge1';
      await notesRepo.insert(
        const Note(
          id: noteId,
          bookId: 'b_foliate_merge3',
          text: '既有備註內容',
          epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_merge3',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      foliateView.onSelectionChanged?.call(
        const EpubSelectionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
          text: '既有備註內容',
          existingAnnotationId: 'note:$noteId',
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('annotation_toolbar_note')));
      await tester.pump();

      expect(find.text('編輯備註'), findsOneWidget);
      expect(find.text('既有備註內容'), findsOneWidget,
          reason: '編輯備註對話框應預填既有備註文字');
    },
  );

  testWidgets(
    '流式 EPUB：點擊複製按鈕，選取文字寫入剪貼簿',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final clipboardCalls = <String>[];
      // 比照既有 reader_console_log_screen_test.dart 的驗證過寫法（不是
      // tester.binding.defaultBinaryMessenger，是
      // TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger）。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardCalls.add(call.arguments['text'] as String);
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_merge4',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      foliateView.onSelectionChanged?.call(
        const EpubSelectionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
          text: '要複製的文字',
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('annotation_toolbar_copy')));
      await tester.pump();

      expect(clipboardCalls, ['要複製的文字']);
    },
  );
```

在檔案結尾（最後一個 `testWidgets` 之後、`}` 之前）新增 PDF 對應版本：

```dart

  testWidgets(
    'PDF：框選矩形命中既有畫線時，工具列顯示刪除按鈕，點擊後刪除該畫線',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      const highlightId = 'ph_merge1';
      await highlightsRepo.insert(
        const Highlight(
          id: highlightId,
          bookId: 'b_pdf_merge1',
          style: HighlightStyle.highlighterYellow,
          pdfPageIndex: 0,
          pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.3),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_pdf_merge1',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onSelectionRectComputed?.call(
        const PdfSelectionInfo(
          pageIndex: 0,
          rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
          widgetRect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
          text: '框選文字',
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('annotation_toolbar_delete')), findsOneWidget);

      await tester.tap(find.byKey(const Key('annotation_toolbar_delete')));
      await tester.pump();
      await tester.pump();

      expect(await highlightsRepo.listByBook('b_pdf_merge1'), isEmpty);
      expect(find.byType(AnnotationToolbar), findsNothing);
    },
  );

  testWidgets(
    'PDF：框選矩形未命中既有標記時，工具列不顯示刪除按鈕',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_pdf_merge2',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onSelectionRectComputed?.call(
        const PdfSelectionInfo(
          pageIndex: 0,
          rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
          widgetRect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
          text: '框選文字',
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsOneWidget);
      expect(find.byKey(const Key('annotation_toolbar_delete')), findsNothing);
    },
  );
```

**Files 匯入注意：** `reader_screen_test.dart` 需確認已 `import 'package:flutter/services.dart';`（供 `SystemChannels`），若尚未匯入請於檔案頂端補上。

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 新增的 6 則測試 FAIL（`AnnotationToolbar` 呼叫端尚未傳入 `onCopyPressed` 導致整份測試檔編譯錯誤，或執行期找不到 `annotation_toolbar_delete`/`annotation_toolbar_copy` 對應行為）。

- [ ] **Step 3：新增 import**

在 `app/lib/screens/reader_screen.dart` 頂端 import 區塊（約第 7 行之後）新增：

```dart
import '../reader/annotation_resolution.dart';
```

- [ ] **Step 4：`build()` 內算出 `existingItem`/`pdfExistingItem`**

找到（約第 2040-2044 行）：

```dart
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final selection = _currentSelection;
        final pdfSelection = _currentPdfSelection;
```

改為：

```dart
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final selection = _currentSelection;
        final pdfSelection = _currentPdfSelection;
        // epic-27-reader-device-compat Issue 11：每次 build 都重新計算，
        // 不快取在 State 欄位——_highlights/_notes 可能在選取進行中被其他
        // 途徑更動，重新計算才能保證資料是最新的。
        final existingItem = selection == null
            ? null
            : resolveEpubExistingAnnotation(
                existingAnnotationId: selection.existingAnnotationId,
                highlights: _highlights,
                notes: _notes,
              );
        final pdfExistingItem = pdfSelection == null
            ? null
            : resolvePdfExistingAnnotation(
                selection: pdfSelection,
                highlights: _highlights,
                notes: _notes,
              );
```

- [ ] **Step 5：新增刪除／複製 handler，`_annotationDeleteButtonLabel` helper**

在 `app/lib/screens/reader_screen.dart`，找到 `_handleCloseAnnotationToolbar`（約第 1511-1514 行）結尾的 `}` 之後，新增：

```dart

  /// 刪除既有畫線/備註的共用邏輯（epic-27-reader-device-compat Issue 11，
  /// 直接搬用舊 `_showAnnotationActionDialog` 的 delete 分支：note/
  /// highlight 各自存在才各自刪除，單筆刪除＝整筆一起刪，spec.md 決策
  /// #13）。EPUB／PDF 各自的 reload／關閉工具列方式不同，由呼叫端各自的
  /// wrapper 負責。
  Future<void> _deleteAnnotationRecords(AnnotationListItem item) async {
    final note = item.note;
    final highlight = item.highlight;
    if (note != null) await widget.notesRepository!.delete(note.id);
    if (highlight != null) await widget.highlightsRepository!.delete(highlight.id);
  }

  Future<void> _handleDeleteExistingAnnotation(AnnotationListItem item) async {
    await _deleteAnnotationRecords(item);
    await _reloadAnnotationsAndRefreshDecorations();
    _handleCloseAnnotationToolbar();
  }

  Future<void> _handlePdfDeleteExistingAnnotation(AnnotationListItem item) async {
    await _deleteAnnotationRecords(item);
    await _reloadPdfAnnotationsAndSync();
    _handlePdfSelectionCanceled();
  }

  Future<void> _handleCopySelection(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// 刪除按鈕的 tooltip 文字，依 [item] 實際含有的內容組合而定
  /// （epic-27-reader-device-compat Issue 11）。
  String _annotationDeleteButtonLabel(AnnotationListItem item) {
    final hasHighlight = item.highlight != null;
    final hasNote = item.note != null;
    if (hasHighlight && hasNote) return '刪除畫線與備註';
    if (hasHighlight) return '刪除畫線';
    return '刪除備註';
  }
```

- [ ] **Step 6：`_handleNotePressed`／`_handlePdfNotePressed` 改為依既有備註分流**

找到（約第 1549-1569 行）：

```dart
  Future<void> _handleNotePressed() async {
    final selection = _currentSelection;
    final repository = widget.notesRepository;
    if (selection == null || repository == null) return;
    final text = await showNoteTextDialog(context, title: '新增備註');
    if (text == null) return;
    await repository.insert(Note(
      id: const Uuid().v4(),
      bookId: widget.bookId,
      text: text,
      epubLocatorJson: selection.locatorJson,
      progression: selection.progression,
      highlightId: _pendingHighlightIdForSelection,
    ));
    await _reloadAnnotationsAndRefreshDecorations();
    if (!mounted) return;
    setState(() {
      _currentSelection = null;
      _pendingHighlightIdForSelection = null;
    });
  }
```

改為：

```dart
  Future<void> _handleNotePressed() async {
    final selection = _currentSelection;
    final repository = widget.notesRepository;
    if (selection == null || repository == null) return;
    final existing = resolveEpubExistingAnnotation(
      existingAnnotationId: selection.existingAnnotationId,
      highlights: _highlights,
      notes: _notes,
    )?.note;
    final text = await showNoteTextDialog(
      context,
      initialText: existing?.text,
      title: existing != null ? '編輯備註' : '新增備註',
    );
    if (text == null) return;
    if (existing != null) {
      await repository.updateText(existing.id, text);
    } else {
      await repository.insert(Note(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        text: text,
        epubLocatorJson: selection.locatorJson,
        progression: selection.progression,
        highlightId: _pendingHighlightIdForSelection,
      ));
    }
    await _reloadAnnotationsAndRefreshDecorations();
    if (!mounted) return;
    setState(() {
      _currentSelection = null;
      _pendingHighlightIdForSelection = null;
    });
  }
```

找到 `_handlePdfNotePressed`（約第 1718-1739 行）：

```dart
  Future<void> _handlePdfNotePressed() async {
    final selection = _currentPdfSelection;
    final repository = widget.notesRepository;
    if (selection == null || repository == null) return;
    final text = await showNoteTextDialog(context, title: '新增備註');
    if (text == null) return;
    final noteId = const Uuid().v4();
    await repository.insert(Note(
      id: noteId,
      bookId: widget.bookId,
      text: text,
      pdfPageIndex: selection.pageIndex,
      pdfRect: selection.rect,
      highlightId: _pendingPdfHighlightIdForSelection,
    ));
    await _reloadPdfAnnotationsAndSync();
    if (!mounted) return;
    setState(() {
      _currentPdfSelection = null;
      _pendingPdfHighlightIdForSelection = null;
    });
  }
```

改為：

```dart
  Future<void> _handlePdfNotePressed() async {
    final selection = _currentPdfSelection;
    final repository = widget.notesRepository;
    if (selection == null || repository == null) return;
    final existing = resolvePdfExistingAnnotation(
      selection: selection,
      highlights: _highlights,
      notes: _notes,
    )?.note;
    final text = await showNoteTextDialog(
      context,
      initialText: existing?.text,
      title: existing != null ? '編輯備註' : '新增備註',
    );
    if (text == null) return;
    if (existing != null) {
      await repository.updateText(existing.id, text);
    } else {
      await repository.insert(Note(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        text: text,
        pdfPageIndex: selection.pageIndex,
        pdfRect: selection.rect,
        highlightId: _pendingPdfHighlightIdForSelection,
      ));
    }
    await _reloadPdfAnnotationsAndSync();
    if (!mounted) return;
    setState(() {
      _currentPdfSelection = null;
      _pendingPdfHighlightIdForSelection = null;
    });
  }
```

- [ ] **Step 7：更新工具列常數與呼叫端**

找到（約第 1996-2008 行）：

```dart
  // 浮動工具列估計高度／與選取範圍的間距（初始選擇，真機測試後可能需
  // 微調，見 Global Constraints「選取矩形座標協定」）。
  static const _annotationToolbarHeight = 56.0;
  static const _annotationToolbarGap = 8.0;
  // AnnotationToolbar 實際渲染寬度（6 顆 IconButton，Material 3 預設每顆
  // 48dp 寬 + Row 外層 Padding 左右各 8dp = 6*48+16 = 304；widget test
  // 量測值，見 plan-issue-2.md Global Constraints，與既有
  // _annotationToolbarHeight 同一量測手法得出）。選取範圍靠近螢幕右緣時，
  // left 的 clamp 上界須扣除這個寬度，否則工具列本體會整個超出螢幕右側
  // （issues.md Issue 2）。【issues.md Issue 3】新增第 6 顆關閉按鈕後，
  // 實際渲染寬度從 256（5 顆）變為 304（6 顆），此常數需同步更新，否則
  // Issue 2 的 clamp 修法會重新出現裁切（見 plan-issue-3.md Task 1）。
  static const _annotationToolbarWidth = 304.0;
```

改為：

```dart
  // 浮動工具列估計高度／與選取範圍的間距（初始選擇，真機測試後可能需
  // 微調，見 Global Constraints「選取矩形座標協定」）。
  //
  // 【epic-27-reader-device-compat Issue 11】改為雙列版面後的估計值：
  // 第一列 5 顆 IconButton（3 色+底線+關閉）＝5*48=240，第二列最多 3 顆
  // （複製/備註/刪除）＝3*48=144，寬度取兩列較大者 240，加上外層 Padding
  // 左右各 8dp＝256；高度為兩列各 48dp 加上外層 Padding 上下各 4dp＝104。
  // 這是估計值，不是嚴謹量測結果——若 widget test（例如既有的「工具列
  // 右緣不應超出畫面寬度」測試）顯示與實際渲染尺寸有落差，以測試回報的
  // 真實數值為準調整這兩個常數，不可保留錯誤估計值。
  static const _annotationToolbarHeight = 104.0;
  static const _annotationToolbarGap = 8.0;
  static const _annotationToolbarWidth = 256.0;
```

找到（約第 2359-2382 行）：

```dart
            if (selection != null)
              Positioned(
                left: (selection.rect.left * size.width)
                    .clamp(0.0, size.width - _annotationToolbarWidth),
                top: _annotationToolbarTop(selection, size),
                child: AnnotationToolbar(
                  onStyleSelected: _handleHighlightStyleSelected,
                  onNotePressed: _handleNotePressed,
                  onClosePressed: _handleCloseAnnotationToolbar,
                ),
              ),
            if (pdfSelection != null)
              Positioned(
                // 同上（見 _pdfAnnotationToolbarTop 註解）：改用相對整個
                // widget 尺寸的 widgetRect，避免 letterbox 留白造成偏移。
                left: (pdfSelection.widgetRect.left * size.width)
                    .clamp(0.0, size.width - _annotationToolbarWidth),
                top: _pdfAnnotationToolbarTop(pdfSelection, size),
                child: AnnotationToolbar(
                  onStyleSelected: _handlePdfHighlightStyleSelected,
                  onNotePressed: _handlePdfNotePressed,
                  onClosePressed: _handlePdfSelectionCanceled,
                ),
              ),
```

改為：

```dart
            if (selection != null)
              Positioned(
                left: (selection.rect.left * size.width)
                    .clamp(0.0, size.width - _annotationToolbarWidth),
                top: _annotationToolbarTop(selection, size),
                child: AnnotationToolbar(
                  onStyleSelected: _handleHighlightStyleSelected,
                  onNotePressed: _handleNotePressed,
                  onClosePressed: _handleCloseAnnotationToolbar,
                  onCopyPressed: () => _handleCopySelection(selection.text),
                  onDeletePressed: existingItem == null
                      ? null
                      : () => _handleDeleteExistingAnnotation(existingItem),
                  deleteButtonLabel: existingItem == null
                      ? null
                      : _annotationDeleteButtonLabel(existingItem),
                  hasExistingNote: existingItem?.note != null,
                ),
              ),
            if (pdfSelection != null)
              Positioned(
                // 同上（見 _pdfAnnotationToolbarTop 註解）：改用相對整個
                // widget 尺寸的 widgetRect，避免 letterbox 留白造成偏移。
                left: (pdfSelection.widgetRect.left * size.width)
                    .clamp(0.0, size.width - _annotationToolbarWidth),
                top: _pdfAnnotationToolbarTop(pdfSelection, size),
                child: AnnotationToolbar(
                  onStyleSelected: _handlePdfHighlightStyleSelected,
                  onNotePressed: _handlePdfNotePressed,
                  onClosePressed: _handlePdfSelectionCanceled,
                  onCopyPressed: () => _handleCopySelection(pdfSelection.text),
                  onDeletePressed: pdfExistingItem == null
                      ? null
                      : () => _handlePdfDeleteExistingAnnotation(pdfExistingItem),
                  deleteButtonLabel: pdfExistingItem == null
                      ? null
                      : _annotationDeleteButtonLabel(pdfExistingItem),
                  hasExistingNote: pdfExistingItem?.note != null,
                ),
              ),
```

- [ ] **Step 8：執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全部測試 PASS（含既有測試、Task 7 新增 6 則）。若「工具列右緣不應超出畫面寬度」（約第 3490-3497 行）或其他既有定位測試因新常數而失敗，依失敗訊息回報的實際數值調整 Step 7 的 `_annotationToolbarHeight`/`_annotationToolbarWidth`，不可略過失敗。

- [ ] **Step 9：`flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-27): Issue 11 Task 7——reader_screen.dart 接線刪除/編輯/複製功能"
```

---

### Task 8：移除舊機制（`_showAnnotationActionDialog`／`onAnnotationActivated`）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/lib/reader/foliate_reader_view.dart`
- Modify: `app/android/app/src/main/assets/foliate/main.js`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: 無。
- Produces: 無——本 Task 只刪除程式碼，不新增任何介面。

- [ ] **Step 1：移除既有的 `onAnnotationActivated` 測試**

在 `app/test/screens/reader_screen_test.dart`，刪除「流式 EPUB：FoliateReaderView 回報 onAnnotationActivated 時，開啟對話框」這整個 `testWidgets` 區塊（Task 7 Step 1 已確認它緊接在新增的 4 則 EPUB 測試之後，內容見本計畫前段引用的原始碼，約在移除前的行號 3555-3609 一帶，實際行號因 Task 7 新增測試而順延，以文字內容「流式 EPUB：FoliateReaderView 回報 onAnnotationActivated 時，開啟對話框」定位）。

- [ ] **Step 2：執行測試確認移除後其餘測試仍通過（但 `_handleAnnotationActivated` 尚未刪除，此步驟只是先拿掉會失效的舊測試）**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全部測試 PASS（少了 1 則，其餘不受影響）。

- [ ] **Step 3：刪除 `reader_screen.dart` 內的舊機制程式碼**

刪除 `_handleAnnotationActivated`（原約第 1637-1664 行，含其上方的文件註解）：

```dart
  /// 原生端 onAnnotationActivated 回呼（使用者點擊既有標記）：依
  /// [decodeAnnotationId] 反查是哪一筆記錄，開啟編輯/刪除 Dialog
  /// （design.md 使用者流程步驟 3）。id 格式不明或查無對應記錄時靜默
  /// 忽略——理論上不會發生（送給原生端的 id 皆由
  /// [EpubDecoration.forHighlight]/[EpubDecoration.forNote] 產生），但
  /// 點擊當下記錄可能已被其他途徑刪除（極短競速窗口），静默忽略比拋出
  /// 例外更穩妥。
  void _handleAnnotationActivated(String decorationId) {
    final decoded = decodeAnnotationId(decorationId);
    if (decoded == null) return;
    AnnotationListItem item;
    switch (decoded.kind) {
      case AnnotationKind.highlight:
        final highlight = _findHighlightById(decoded.id);
        if (highlight == null) return;
        item = AnnotationListItem(
          highlight: highlight,
          note: _findNoteByHighlightId(decoded.id),
        );
        break;
      case AnnotationKind.note:
        final note = _findNoteById(decoded.id);
        if (note == null) return;
        item = AnnotationListItem(note: note);
        break;
    }
    _showAnnotationActionDialog(item);
  }
```

刪除緊接在它之後的 `_showAnnotationActionDialog`（原約第 1666-1700 行）：

```dart
  Future<void> _showAnnotationActionDialog(AnnotationListItem item) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('劃線/備註'),
        children: [
          if (item.note != null)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop('edit'),
              child: const Text('✍️ 編輯備註文字'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop('delete'),
            child: const Text('🗑️ 刪除此劃線與備註'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final note = item.note;
    final highlight = item.highlight;
    if (action == 'edit' && note != null) {
      final newText = await showNoteTextDialog(context, initialText: note.text, title: '編輯備註');
      if (newText != null) {
        await widget.notesRepository!.updateText(note.id, newText);
        await _reloadAnnotationsAndRefreshDecorations();
      }
    } else if (action == 'delete') {
      // 單筆刪除＝整筆一起刪（spec.md 決策 #13），比照
      // NotesBottomSheet._deleteAnnotationItem 的既有原則。
      if (note != null) await widget.notesRepository!.delete(note.id);
      if (highlight != null) await widget.highlightsRepository!.delete(highlight.id);
      await _reloadAnnotationsAndRefreshDecorations();
    }
  }
```

刪除已經孤立、只被上述兩個方法使用的 3 個 finder（原約第 1616-1635 行，緊接在 `_sendDecorationsToNative` 之後）：

```dart
  Highlight? _findHighlightById(String id) {
    for (final highlight in _highlights) {
      if (highlight.id == id) return highlight;
    }
    return null;
  }

  Note? _findNoteByHighlightId(String highlightId) {
    for (final note in _notes) {
      if (note.highlightId == highlightId) return note;
    }
    return null;
  }

  Note? _findNoteById(String id) {
    for (final note in _notes) {
      if (note.id == id) return note;
    }
    return null;
  }
```

找到 `FoliateReaderView` 建構呼叫（原約第 2646 行）：

```dart
          onAnnotationActivated: _handleAnnotationActivated,
```

整行刪除。

- [ ] **Step 4：刪除 `foliate_reader_view.dart` 內的 `onAnnotationActivated`**

刪除建構參數宣告（約第 421 行）：

```dart
  final ValueChanged<String>? onAnnotationActivated;
```

刪除建構子內對應項（約第 466 行）：

```dart
    this.onAnnotationActivated,
```

刪除 handler 註冊（約第 692-697 行）：

```dart
    controller.addJavaScriptHandler(
      handlerName: 'onAnnotationActivated',
      callback: (args) {
        widget.onAnnotationActivated?.call(args[0] as String);
      },
    );
```

- [ ] **Step 5：`flutter analyze` 確認無殘留引用**

Run: `cd app && flutter analyze`
Expected: `No issues found!`（若出現 `decodeAnnotationId`/`AnnotationKind`/`AnnotationListItem` 未使用的 import 警告，檢查是否還有其他地方使用——`AnnotationListItem` 應仍被 `annotation_resolution.dart` 使用；`decodeAnnotationId`/`AnnotationKind` 應仍被 `annotation_resolution.dart` 使用，`reader_screen.dart` 本身若不再直接引用這兩者，需移除對應的 `import '../reader/epub_decoration.dart';`——先確認 `reader_screen.dart` 是否還有其他地方用到 `epub_decoration.dart` 匯出的符號再決定是否移除整行 import）。

- [ ] **Step 6：刪除 `main.js` 的 `show-annotation` 監聽器**

找到（約第 636-639 行）：

```js
    view.addEventListener('show-annotation', (e) => {
      const id = decorationIdByCfi.get(e.detail.value)
      if (id) window.flutter_inappwebview.callHandler('onAnnotationActivated', id)
    })
```

整段連同上方緊接的說明註解（約第 630-635 行，「點擊既有標記（epic-17 Issue 8）...」這段，因為它只是解釋這個監聽器的存在理由，監聽器本身移除後這段註解也失去意義）一併刪除。

- [ ] **Step 7：新增靜態內容回歸測試——確認舊機制已移除**

在 `app/test/reader/foliate_reader_view_test.dart` Task 3 新增的「main.js 選取範圍 hit-test 既有標記＋回傳文字 regression guard（Epic 27 Issue 11）」group 結尾，新增一則測試：

```dart

    test('main.js 不再監聽 show-annotation 事件（舊機制已由 Issue 11 汰除）', () {
      expect(mainJsSource.contains("addEventListener('show-annotation'"), isFalse,
          reason: 'show-annotation 監聽器應已隨 Issue 11 移除——長按已畫線'
              '文字的刪除功能現在改由選取範圍 hit-test（見同一 group 前面'
              '幾則測試）統一處理，不再依賴這個永遠不會被原生選字放行的 '
              'click 事件路徑。');
    });
```

- [ ] **Step 8：執行完整測試套件**

Run: `cd app && flutter test`
Expected: 全專案測試 PASS，零回歸。

- [ ] **Step 9：`flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/lib/reader/foliate_reader_view.dart app/android/app/src/main/assets/foliate/main.js app/test/screens/reader_screen_test.dart app/test/reader/foliate_reader_view_test.dart
git commit -m "refactor(epic-27): Issue 11 Task 8——移除舊版點擊觸發刪除確認機制"
```

---

## 完成後的驗證（對照 `issues.md` Issue 11，本計畫執行後應同步更新該工單）

- [ ] `cd app && flutter analyze` 全專案乾淨（`No issues found!`）。
- [ ] `cd app && flutter test` 全專案零回歸通過。
- [ ] 長按 EPUB 已畫線文字：工具列出現「刪除」按鈕，點擊後畫線（含依附備註）從資料庫刪除、工具列關閉。
- [ ] 長按 EPUB 已有備註（無畫線）文字：點擊「備註」按鈕開啟編輯對話框，文字已預填。
- [ ] 長按 EPUB 空白文字：工具列不顯示刪除按鈕，「備註」按鈕開新增對話框。
- [ ] PDF 框選命中既有畫線／備註／空白區域三種情境，行為與 EPUB 對稱。
- [ ] 點擊「複製」按鈕，選取/框選文字寫入剪貼簿。
- [ ] 本計畫完成後，同步更新 `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 11」的 `Status`（`needs-info` → 完成後之對應狀態），並在 Solution 段落註記實際採用的機制（選取範圍 hit-test 既有標記，取代原本依賴 click 事件的方案），不覆蓋掉原文的診斷歷程記錄。
- [ ] 建議合併後請使用者在真機（WAVE／AiPaper Reader C 任一台）做一次手感驗證：長按已畫線文字能否穩定跳出刪除按鈕；PDF 框選命中既有畫線的手感是否符合預期。
