# Epic 27 Issue 11：長按已畫線區域改由畫線工具列統一處理（設計文件）

**狀態：** 待人類審閱
**對應工單：** `docs/epics/epic-27-reader-device-compat/issues.md` Issue 11
**診斷依據：** `docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md`「Issue 10」第三、四輪測試段落（新問題 A）

## 背景

長按已經畫線的文字，預期應該跳出「編輯備註／刪除此劃線」的確認視窗，實際上完全不會跳出，取而代之的是選字用的 `AnnotationToolbar`（本來是用來建立「新」劃線的工具列）。

真機 log 已經證實根因：長按已畫線文字時，瀏覽器原生選字機制會搶先啟動，導致 `click` 事件從未真正發生，舊的刪除確認機制（`_showAnnotationActionDialog`，靠 `click` 事件觸發）完全沒有機會執行。這是 WebView 原生行為與畫線點擊偵測機制之間的架構衝突，不是單純的邏輯錯誤，純粹調整時間門檻無法解決。

## 目標

不跟原生選字搶事件，改成：使用者長按（不論長按處有沒有畫線）都跳出同一個 `AnnotationToolbar`；如果長按處剛好命中既有畫線／備註，工具列上多顯示「刪除」按鈕（可以刪除、也可以編輯既有備註）。同時追加兩個使用者提出的新功能：

1. 工具列新增「複製」按鈕，複製目前選取文字到剪貼簿。
2. 工具列改為兩列版面，把「刪除」「複製」「備註」集中放第二列，縮減版面寬度。

範圍涵蓋 EPUB（含 KF8/TXT/MD，皆走 `FoliateReaderView`）與 PDF 兩種格式。

## 非目標

- 不重新設計工具列的定位演算法（沿用既有 `_annotationToolbarTop`／`_pdfAnnotationToolbarTop`，只調整高度常數配合雙列版面）。
- 不處理「原生長按選字」本身的觸發時機（瀏覽器/系統層級行為，不可控，也不是本次要修的對象）。
- 不新增「編輯已存在畫線的顏色」功能（範圍外，使用者未提出）。
- 不修改任何 vendored 檔案（`paginator.js`／`view.js`／`epub.js`／`overlayer.js`／`fixed-layout.js`）內容，只呼叫其既有公開方法，符合 ADR 0011。

## 整體機制

### EPUB（FoliateReaderView，WebView）

`view.js` 的 `#createOverlayer` 已經建立了一個 `Overlayer` 實例，並提供公開方法 `overlayer.hitTest({x, y})`——傳入某個座標，回傳 `[decorationCfiKey, range, rect]`（沒命中則回傳空陣列）。這個座標系跟 `range.getClientRects()` 用的是同一套（iframe 文件座標），`main.js` 的 `reportSelection()` 本來就已經算出選取範圍的 `rect`（`range.getClientRects()[0]`）。

在 `reportSelection()` 內，選取範圍每次變動時，額外做一次：

```js
const overlayer = view.renderer.getContents().find(x => x.index === index)?.overlayer
const hit = overlayer
  ? overlayer.hitTest({ x: (rect.left + rect.right) / 2, y: (rect.top + rect.bottom) / 2 })
  : []
const hitCfi = hit[0]
const existingAnnotationId = hitCfi ? (decorationIdByCfi.get(hitCfi) ?? null) : null
```

`decorationIdByCfi` 是 `main.js` 既有的模組級變數（`window.setDecorations()` 建立），本來就用在 `show-annotation` 事件的反查邏輯裡，`reportSelection()` 這個 closure 本來就在同一個模組作用域內，可以直接存取，不需要額外傳遞。

搜尋結果的高亮（`SEARCH_PREFIX` 開頭的 cfi）不需要額外排除——它們不是透過 `setDecorations()` 建立的，`decorationIdByCfi` 裡查不到對應 key，`existingAnnotationId` 自然是 `null`。

**已知限制（審查報告 Minor #1）：** `overlayer.hitTest()` 是反向遍歷內部 `#map`、只回傳第一個命中結果，不是回傳所有命中結果的清單。如果畫面上同時存在搜尋高亮（開著搜尋面板時）且它剛好疊在使用者畫線正上方、又比畫線晚加入 `#map`，`hitTest` 會先命中搜尋高亮、遮住底下真正的畫線，導致 `existingAnnotationId` 判斷成 `null`（沒命中），即使那個位置其實有畫線。要完整解決需要修改 vendored 的 `overlayer.js`（讓 `hitTest` 支援跳過搜尋結果、繼續往下找），違反 ADR 0011（不改 vendored 檔案內容），且觸發條件窄（必須同時符合「搜尋面板開著」+「搜尋高亮與畫線像素重疊」）。本次不處理，留作已知限制；使用者長按會拿到「一般選字工具列」（沒有刪除按鈕），行為上跟目前一致，不算功能倒退。

**已知簡化，先寫明白：** 只用選取範圍第一個 client rect 的中點做 hit test，不逐行檢查整個選取範圍。多行選取、或選取起點剛好在畫線外緣的邊界情況，可能測不準。這個簡化對應「長按已畫線文字」這個主要場景（選取起點就在畫線範圍內）已經足夠，之後如果真機回報邊界誤判，再加強不遲（YAGNI）。

`text`（選取文字）用 `selection.toString()`，同一次 `callHandler` 呼叫內一起送出。

### PDF（PdfReaderView，純 Flutter 手勢）

PDF 的框選本來就是 Flutter 手勢做的，不經過 WebView，也就不會有「原生選字搶事件」這個問題——這次要做的是全新功能，不是修 bug。

判斷「框選矩形是否命中既有畫線/備註」：`Highlight`/`Note` 模型本身就存了 `pdfPageIndex` + `pdfRect`（`PercentRect`，頁面百分比座標）。框選結束時，拿這次框選的 `PercentRect` 跟同一頁所有既存 `Highlight`/`Note` 的 `pdfRect` 做矩形重疊測試即可，純 Dart 運算，不需要碰 PDF 引擎本身。

`text`（選取文字）用 PDF 搜尋功能已經在用的 `page.loadStructuredText()`（回傳 `PdfPageText`，含 `charRects: List<PdfRect>`，逐字元的頁面座標）。把框選的 `PercentRect` 換算回頁面像素座標，找出 `charRects` 落在這個矩形內的字元索引範圍，用 `fullText.substring(...)` 取出文字。

## 資料模型／介面異動

### `EpubSelectionInfo`（`app/lib/reader/epub_selection_info.dart`）

新增兩個欄位：

```dart
class EpubSelectionInfo {
  final String locatorJson;
  final double? progression;
  final PercentRect rect;
  final String text;                    // 新增：選取文字，供複製使用
  final String? existingAnnotationId;   // 新增：命中既有標記的 id（decodeAnnotationId 相容格式），未命中為 null

  const EpubSelectionInfo({
    required this.locatorJson,
    this.progression,
    required this.rect,
    required this.text,
    this.existingAnnotationId,
  });
  // ==、hashCode、toString 一併補上新欄位
}
```

### `PdfSelectionInfo`（`app/lib/reader/pdf_selection_info.dart`）

新增兩個欄位，語意與上面相同：

```dart
class PdfSelectionInfo {
  final int pageIndex;
  final PercentRect rect;
  final PercentRect widgetRect;
  final String text;                    // 新增
  final String? existingAnnotationId;   // 新增：格式同 EpubSelectionInfo（decodeAnnotationId 相容）

  const PdfSelectionInfo({
    required this.pageIndex,
    required this.rect,
    required this.widgetRect,
    required this.text,
    this.existingAnnotationId,
  });
  // ==、hashCode、toString 一併補上新欄位
}
```

`existingAnnotationId` 的編碼格式沿用既有 `epub_decoration.dart` 的 `encodeAnnotationId`/`decodeAnnotationId`（`"highlight:5"`/`"note:12"`），PDF 端由 `reader_screen.dart` 在算出命中的 `Highlight`/`Note` 之後自行組裝這個字串，跟 EPUB 端共用同一套解碼邏輯與後續的 `AnnotationListItem` 查找程式碼（`_findHighlightById`／`_findNoteByHighlightId`／`_findNoteById`，皆已存在，不需新增）。

### `main.js` JS 橋接（`app/android/app/src/main/assets/foliate/main.js`）

`reportSelection()` 的 `callHandler('onSelectionChanged', ...)` 呼叫，在既有 6 個位置參數（`locatorJson`／`fraction`／`rect` 四個座標分量）之後，新增 2 個位置參數：`text`、`existingAnnotationId`（沒命中傳 `null`，JS→Dart 橋接會變成 Dart 的 `null`）。既有 6 個參數的順序/型別不動，向後相容。

### `foliate_reader_view.dart` 的 `onSelectionChanged` handler（約 667-684 行）

對應新增 2 個參數的解析：

```dart
controller.addJavaScriptHandler(
  handlerName: 'onSelectionChanged',
  callback: (args) {
    num? argAt(int index) => args.length > index ? args[index] as num? : null;
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
      text: args.length > 6 ? (args[6] as String? ?? '') : '',
      existingAnnotationId: args.length > 7 ? args[7] as String? : null,
    ));
  },
);
```

### `pdf_reader_view.dart` 框選結束流程

**座標系換算（審查修正 Important #1）：** `pdfrx` 的 `PdfRect` 建構子是 `PdfRect(left, top, right, bottom)`，並帶 `assert(top >= bottom)`（PDF points 座標，左下角原點、Y 軸向上，見 `pdf_search_geometry.dart` 既有文件註解）；本專案的 `PercentRect` 是左上角原點、Y 軸向下（`top <= bottom`）。兩者 Y 軸方向相反，不能直接把 `PercentRect` 的 `top`/`bottom` 乘上 `pageHeight` 後原樣塞進 `PdfRect`——那樣會讓 `top < bottom`，直接觸發上述 assert（debug 模式會拋例外，不是安靜地算錯）。

需要在 `pdf_search_geometry.dart` 新增 `pdfRectToPercentRect` 的反向轉換 helper（與既有函式放在同一檔案，維持「PDF 座標轉換集中一處」的既有慣例）：

```dart
/// [pdfRectToPercentRect] 的反向轉換，供 Issue 11「框選矩形換算回 PDF
/// points 座標以查詢 charRects」使用。公式為 pdfRectToPercentRect 的代數
/// 逆推：percentRect.top = 1.0 - pdfRect.top/pageHeight，故
/// pdfRect.top = (1.0 - percentRect.top) * pageHeight，bottom 同理。
PdfRect percentRectToPdfRect({
  required PercentRect rect,
  required double pageWidth,
  required double pageHeight,
}) {
  return PdfRect(
    rect.left * pageWidth,
    (1.0 - rect.top) * pageHeight,    // PdfRect.top（較大值）
    rect.right * pageWidth,
    (1.0 - rect.bottom) * pageHeight, // PdfRect.bottom（較小值）
  );
}
```

框選手勢結束時（`_finishSelectionDrag()`，`pdf_reader_view.dart:1146`，目前整個方法是**同步**的），原本呼叫 `widget.onSelectionRectComputed`（送出 `PdfSelectionInfo`）之前，新增一段文字萃取：

```dart
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
    if (_rectsOverlap(pageText.charRects[i], targetRect)) {
      buffer.write(pageText.fullText[i]);
    }
  }
  return buffer.toString();
}
```

（`_rectsOverlap` 為新增的簡單矩形重疊判斷函式，比較兩個 `PdfRect`。）

**非同步競速防護（審查修正 Important #2）：** `_finishSelectionDrag()` 目前是同步方法，一進來就同步呼叫 `setState(() => _selectionDrag = null)`。改成需要 `await page.loadStructuredText()`（大檔案/慢裝置可能耗時）之後，中間這段空隙使用者可能離開畫面、或放開後立刻開始下一次框選——若不防護，過期的萃取結果回來時會呼叫 `widget.onSelectionRectComputed`，用舊資料覆蓋掉使用者新一次框選已經產生的狀態。

比照本檔案既有的 `_searchSessionId`（`_search()` 方法，見上方）世代編號慣例，新增一個 `_selectionDragGenerationId`（`int`，初始 0）欄位：`_finishSelectionDrag()` 一開始同步遞增並記錄局部變數 `final generationId = ++_selectionDragGenerationId;`；`await _extractTextInRect(...)` 回來後，先檢查 `if (!mounted || generationId != _selectionDragGenerationId) return;`，通過才呼叫 `widget.onSelectionRectComputed`。任何會開始新框選手勢的地方（拖曳起點建立 `_selectionDrag = _PdfSelectionDragState(...)` 處，`pdf_reader_view.dart:1127`）也要遞增這個計數器，讓「使用者放開後立刻開始下一次框選」這個情境也能讓上一次的過期結果被正確擋下。

`existingAnnotationId` 的命中判斷不需要動到 `pdf_reader_view.dart`——`Highlight`/`Note` 清單本來就只存在 `reader_screen.dart`，重疊比對直接在 `reader_screen.dart` 收到 `PdfSelectionInfo` 之後算即可（見下方）。

### `reader_screen.dart` 新增／修改的方法

新增一個共用 helper（EPUB／PDF 共用），依 `existingAnnotationId`（或 PDF 算出的重疊結果）反查 `AnnotationListItem`：

```dart
AnnotationListItem? _resolveExistingAnnotation(String? existingAnnotationId) {
  final decoded = existingAnnotationId == null ? null : decodeAnnotationId(existingAnnotationId);
  if (decoded == null) return null;
  switch (decoded.kind) {
    case AnnotationKind.highlight:
      final highlight = _findHighlightById(decoded.id);
      if (highlight == null) return null;
      return AnnotationListItem(highlight: highlight, note: _findNoteByHighlightId(decoded.id));
    case AnnotationKind.note:
      final note = _findNoteById(decoded.id);
      if (note == null) return null;
      return AnnotationListItem(note: note);
  }
}
```

PDF 端在 `_handlePdfSelectionRectComputed` 內，收到新的 `PdfSelectionInfo` 後，先用矩形重疊掃描 `_highlights`/`_notes`（同 `pdfPageIndex`）算出命中的 `Highlight`/`Note`，組出 `encodeAnnotationId(...)` 字串，等效於 EPUB 端已經算好的 `existingAnnotationId`，後續共用同一個 `_resolveExistingAnnotation`。

「刪除」按鈕的處理邏輯（直接搬用舊 `_showAnnotationActionDialog` 的 `delete` 分支，改成同步呼叫，不再包一層 `showDialog`）：

```dart
Future<void> _handleDeleteExistingAnnotation(AnnotationListItem item) async {
  final note = item.note;
  final highlight = item.highlight;
  if (note != null) await widget.notesRepository!.delete(note.id);
  if (highlight != null) await widget.highlightsRepository!.delete(highlight.id);
  await _reloadAnnotationsAndRefreshDecorations(); // PDF 端呼叫 _reloadPdfAnnotationsAndSync()
  _handleCloseAnnotationToolbar(); // 或 PDF 對應的 _handlePdfSelectionCanceled()
}
```

「備註」按鈕的處理邏輯改成依 `existingAnnotation` 是否有 `note` 分流：

```dart
Future<void> _handleNotePressed() async {
  final selection = _currentSelection;
  final repository = widget.notesRepository;
  if (selection == null || repository == null) return;
  final existing = _resolveExistingAnnotation(selection.existingAnnotationId)?.note;
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

PDF 端的 `_handlePdfNotePressed` 比照同樣的分流邏輯修改。

「複製」按鈕的處理邏輯（EPUB／PDF 共用同一個工具函式）：

```dart
Future<void> _handleCopySelection(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}
```

## AnnotationToolbar 改版（`app/lib/screens/annotation_toolbar.dart`）

Widget 建構參數新增：

```dart
class AnnotationToolbar extends StatelessWidget {
  final ValueChanged<HighlightStyle> onStyleSelected;
  final VoidCallback onNotePressed;
  final VoidCallback onClosePressed;
  final VoidCallback onCopyPressed;      // 新增：永遠可用
  final VoidCallback? onDeletePressed;   // 新增：null 代表這次選取沒有命中既有標記，不顯示刪除按鈕
  final String? deleteButtonLabel;       // 新增：「刪除畫線」／「刪除備註」／「刪除畫線與備註」，onDeletePressed 非 null 時必填
  final bool hasExistingNote;            // 新增：控制「備註」按鈕的 tooltip/icon 顯示「新增」或「編輯」

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
```

版面改為兩列（`Column` 包兩個 `Row`）：

- 第一列：3 顆螢光筆色 + 底線 + 關閉（跟現在一樣，`Key` 不變，維持既有 widget test 相容）。
- 第二列：`複製`（`Key('annotation_toolbar_copy')`，`Icons.copy`，永遠顯示）、`備註`（沿用既有 `Key('annotation_toolbar_note')`，圖示/tooltip 依 `hasExistingNote` 切換「新增備註」/「編輯備註」）、`刪除`（`Key('annotation_toolbar_delete')`，僅 `onDeletePressed != null` 時顯示，`tooltip` 用 `deleteButtonLabel`）。

呼叫端（`reader_screen.dart` 約 2364、2377 行）：

```dart
AnnotationToolbar(
  onStyleSelected: _handleHighlightStyleSelected,
  onNotePressed: _handleNotePressed,
  onClosePressed: _handleCloseAnnotationToolbar,
  onCopyPressed: () => _handleCopySelection(selection.text),
  onDeletePressed: existingItem == null
      ? null
      : () => _handleDeleteExistingAnnotation(existingItem),
  deleteButtonLabel: existingItem == null ? null : _deleteButtonLabel(existingItem),
  hasExistingNote: existingItem?.note != null,
),
```

（`existingItem` 為 build 方法內先算好的 `_resolveExistingAnnotation(selection.existingAnnotationId)`；`_deleteButtonLabel` 為新增的小 helper，依 `highlight`/`note` 是否同時存在回傳對應文字。）

`_annotationToolbarHeight`（`reader_screen.dart:1998`）常數需要調整為雙列高度（原本 56.0 為單列估計值，雙列需要重新量測，實作時以實際 widget render 尺寸為準，不可憑空套用兩倍；概估含 padding 後兩列合計約落在 96-112dp 區間，僅供實作時抓量測範圍參考，實際數值仍須以 widget test 量出的 render 尺寸為準）。

## 舊機制移除清單

- `reader_screen.dart`：`_showAnnotationActionDialog`（1666-1700 行）、`_handleAnnotationActivated`（1637-1664 行）整個方法一併刪除；`FoliateReaderView` 建構時傳入的 `onAnnotationActivated: _handleAnnotationActivated`（2646 行）一併移除。
- `foliate_reader_view.dart`：`onAnnotationActivated` 建構參數、對應的 `addJavaScriptHandler('onAnnotationActivated', ...)` 一併移除。
- `main.js`：`view.addEventListener('show-annotation', ...)`（636-639 行）監聽器移除。`view.js` 的 `#createOverlayer` 本身（含它內部的 `click`/`mousemove` 監聽器與 `show-annotation` 事件 emit）是 vendored 檔案，不動；只是 `main.js` 這邊不再監聽 `show-annotation` 事件，效果等同停用這條路徑的下游行為。

`epub_decoration.dart` 的 `decodeAnnotationId`/`encodeAnnotationId` **不刪除**——新機制仍然需要它們解析/組裝 `existingAnnotationId`。

## 測試計畫

- `annotation_toolbar_test.dart`（新建或擴充既有測試檔）：
  - `onDeletePressed == null` 時不顯示刪除按鈕；非 null 時顯示，文字對應 `deleteButtonLabel`。
  - `hasExistingNote: true`／`false` 時，備註按鈕 tooltip 分別顯示「編輯備註」／「新增備註」。
  - 點擊「複製」呼叫 `onCopyPressed`。
  - 兩列版面：第一列/第二列各自包含哪些 `Key`（回歸既有第一列 5 顆按鈕的既有測試）。
- `reader_screen_test.dart`：
  - EPUB／PDF 長按命中既有畫線：斷言工具列出現刪除按鈕，點擊後畫線／備註從 repository 刪除、`_reloadAnnotationsAndRefreshDecorations`／`_reloadPdfAnnotationsAndSync` 被呼叫。
  - EPUB／PDF 長按命中既有備註（無畫線）：斷言「備註」按鈕開啟編輯對話框且文字已預填既有內容。
  - EPUB／PDF 長按空白處（無命中）：斷言不顯示刪除按鈕，「備註」按鈕開啟新增對話框（沿用既有測試語意，只是改走新的分流函式）。
  - 點擊「複製」：斷言 `Clipboard.setData` 被呼叫且內容等於 `selection.text`（用 `TestWidgetsFlutterBinding` 攔截 `SystemChannels.platform` 的 `Clipboard.setData` method call）。
  - 移除 `_showAnnotationActionDialog`／`_handleAnnotationActivated` 相關的既有測試（若有）並確認沒有殘留引用。
- `foliate_reader_view_test.dart`：靜態回歸測試，斷言 `main.js` 的 `reportSelection` 內含 `overlayer.hitTest`／`decorationIdByCfi.get` 呼叫，且 `callHandler('onSelectionChanged', ...)` 參數數量增加為 8 個；`show-annotation` 監聽器已移除。
- `pdf_reader_view_test.dart`：文字萃取函式用已知 `charRects` 座標的假資料驗證抓到的文字正確；命中/未命中既有畫線的矩形重疊測試用已知座標驗證。
- `pdf_search_geometry_test.dart`（既有測試檔，擴充）：新增 `percentRectToPdfRect` 與既有 `pdfRectToPercentRect` 互為反函式的斷言（`percentRectToPdfRect(pdfRectToPercentRect(r))` 近似等於 `r`，浮點數用近似比較），並斷言換算結果一律滿足 `PdfRect` 的 `top >= bottom`（不觸發 assert）。
- `pdf_reader_view_test.dart`：新增競速回歸測試——框選完成、文字萃取尚未 `await` 完成前就觸發下一次框選（或模擬 widget unmount），斷言只有最後一次框選的結果會呼叫 `onSelectionRectComputed`，過期結果被正確擋下。
- 全部既有 `flutter test`／`flutter analyze` 需維持零回歸。

## 風險與限制

- EPUB 端的 hit test 只測選取範圍第一個 client rect 的中點（見上方「已知簡化」），多行選取的邊界情況未涵蓋，不在本次範圍內處理。
- EPUB 端搜尋高亮若剛好疊在畫線正上方且較晚加入，會讓 `hitTest` 命中搜尋高亮而非底下的畫線，導致該次長按判斷為「沒有既有標記」（見上方「已知限制」段落）；修正需要改動 vendored 檔案，違反 ADR 0011，本次不處理。
- 本次改動不涉及真機專屬的時間門檻調校（不像 Issue 9/10/12），理論上可以純靠 widget test 驗證完整，但畫線/備註互動屬於使用者體感高敏感區塊，仍建議合併後請使用者在真機（WAVE／AiPaper Reader C 任一台）做一次手感驗證，確認長按已畫線文字能穩定跳出刪除按鈕。
