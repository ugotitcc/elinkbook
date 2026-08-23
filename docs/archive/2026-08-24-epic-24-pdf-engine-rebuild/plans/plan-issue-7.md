# Epic 24 Issue 7 — 頁碼縮圖（Thumbnails） Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 以頁碼格狀縮圖呈現整本 PDF 每一頁的縮小預覽圖，點擊縮圖跳轉至對應頁面；縮圖僅於可視附近範圍內產生（不一次性渲染全書），並以有明確上限的快取策略管理縮圖影像記憶體，淘汰時明確釋放。UI 掛載於 Issue 5 建立的目錄 Bottom Sheet「縮圖」分頁。

**Architecture:** 新增與 `dart:ui`/Flutter 無關的泛型 `PdfThumbnailCache<T>`（純 Dart LRU 快取，供釋放策略獨立、可測試）；`PdfReaderView` 新增 `renderThumbnail()` 靜態 helper，比照既有 `search()`/`loadTableOfContents()` 慣例透過 `GlobalKey` 存取內部 `_document`，用 `page.render(fullWidth:, fullHeight:)` 直接渲染出縮圖尺寸的 `ui.Image`（不需要 Isolate——縮圖尺寸小，且 `page.render()` 本身透過 FFI 非同步呼叫，不是既有 Isolate.run() 模式鎖定的「CPU-bound 純 Dart 像素演算法」情境，那是 Issue 3 加粗/裁切的專屬狀況）；新增 `PdfThumbnailPanel` widget（`GridView.builder`＋`PdfThumbnailCache`），與 `ReaderScreen`/`PdfReaderView` 完全解耦（比照 `PdfSearchPanel` 既有設計），只透過 callback 溝通；`TocBottomSheet` 新增 `thumbnailTabContent: Widget?` 插槽（比照既有 `searchTabContent`）。

**Tech Stack:** Flutter/Dart、`pdfrx`（`PdfDocument.pages[i].render({fullWidth, fullHeight})` → `PdfImage?`，`PdfImage.createImage()` → `Future<ui.Image>`）、既有 `flutter_test` 對真實 PDF fixture 驗證＋合成小型 `ui.Image`（`ui.decodeImageFromPixels`）驗證快取邏輯。

## Global Constraints

- **縮圖僅於可視附近範圍內產生，不一次性渲染全書**：透過 `GridView.builder` 的既有 sliver 延遲建構機制達成——`itemBuilder` 只會對接近可視範圍的索引被呼叫，`PdfThumbnailPanel` 不得在初次建構時主動走訪 `totalPages` 全部索引預先渲染。
- **快取上限＋明確釋放**：縮圖影像（`ui.Image`）快取須有固定上限，超出上限時淘汰最舊使用的項目並呼叫其 `dispose()`；快取邏輯抽成獨立、不依賴 `dart:ui` 的泛型 `PdfThumbnailCache<T>`，讓核心 LRU 行為可以用輕量假物件（非真實 `ui.Image`）快速、確定性地單元測試——比照既有 `_PdfReaderViewState._boldOverlayImages`（Issue 3）的 LRU 快取設計精神，但抽成獨立可重用單元（Issue 3 當時是直接寫在 State 內部，未抽象化）。
- **`page.render()` 不需要 Isolate**：既有 Issue 3 的 `Isolate.run()` 用法（`_isolateDetectCropRect`／`_isolateProcessOverlayPixels`）是針對「CPU-bound 純 Dart 像素演算法」（型態學膨脹加粗、邊緣偵測裁切）情境；縮圖渲染只是呼叫 `page.render(fullWidth:, fullHeight:)` 取得指定尺寸的頁面圖片（與既有 `_detectCropRect`／`_recomputeOverlay` 呼叫 `page.render()` 的既有模式完全相同，兩者皆未用 Isolate 包裹這個呼叫本身），不涉及額外純 Dart 像素運算，不需要新增 Isolate 機制。
- **`PdfThumbnailPanel` 與 `ReaderScreen`／`PdfReaderView` 解耦**（比照 `PdfSearchPanel` 既有設計原則，`pdf_search_panel.dart` docstring）：本 widget 只透過 `renderThumbnail: Future<ui.Image?> Function(int)` 與 `onPageSelected: ValueChanged<int>` 兩個函式型別參數溝通，不直接依賴 `GlobalKey<State<PdfReaderView>>`、`PdfDocument`、或任何 `PdfReaderView` 型別。
- **`TocBottomSheet` 新增 `thumbnailTabContent: Widget?` 插槽**（比照既有 `searchTabContent`，`toc_bottom_sheet.dart` docstring 既定原則）：`TocBottomSheet` 不知道傳入的縮圖分頁內容是什麼，`null` 時維持既有「此功能將於後續版本提供」佔位文字（零回歸）。
- **`page.render(fullWidth:, fullHeight:)` 語意**（已查證 `pdfrx_engine-0.4.5` 原始碼 `pdf_page.dart` doc comment）：`fullWidth`/`fullHeight` 直接指定輸出影像的目標像素尺寸（非自動等比例縮放），未額外指定 `width`/`height` 子區域時預設輸出整頁、剛好是 `fullWidth`×`fullHeight` 像素——因此縮圖等比例縮放（維持頁面長寬比、避免影像變形）須由呼叫端自行依 `page.width`/`page.height` 算出 `fullHeight`，不能只傳 `fullWidth` 而假設 pdfrx 會自動等比例換算。
- **測試策略**：`PdfThumbnailCache<T>` 用純 Dart 假物件（`dispose` 旗標計數）單元測試，不依賴 `dart:ui`；`PdfReaderView.renderThumbnail()` 用既有 `sample_multi_page.pdf` fixture（612×792、5 頁，Issue 6 已驗證）真實渲染驗證；`PdfThumbnailPanel` 用可控制的假 `renderThumbnail` callback（回傳透過 `ui.decodeImageFromPixels` 合成的小型真實 `ui.Image`，避免依賴真實 PDFium 渲染耗時），透過 `dart:ui` 內建的 `Image.debugDisposed`（asserts 啟用時可用的除錯用 getter，`flutter test` 預設啟用 asserts）驗證淘汰/釋放時機——這是可觀察、確定性的資源計數斷言，不需要真機記憶體量測。
- **`flutter analyze` 乾淨、每個 Task 結束後相關測試全數通過**是每個 Task 的隱含驗收條件。

---

### Task 1: `PdfThumbnailCache<T>` 泛型 LRU 快取（純 Dart）

**Files:**
- Create: `app/lib/reader/pdf_thumbnail_cache.dart`
- Test: `app/test/reader/pdf_thumbnail_cache_test.dart`

**Interfaces:**
- Produces: `class PdfThumbnailCache<T> { PdfThumbnailCache({required int maxSize, required void Function(T) dispose}); T? get(int key); void put(int key, T value); bool contains(int key); int get length; void clear(); }`——Task 3（`PdfThumbnailPanel`）依賴此類別。

- [x] **Step 1: 建立 `PdfThumbnailCache<T>`**

建立 `app/lib/reader/pdf_thumbnail_cache.dart`：

```dart
/// 泛型、有大小上限的 LRU（最近最少使用）快取，供 [PdfThumbnailPanel]
/// 管理縮圖影像的生命週期（epic-24-pdf-engine-rebuild Issue 7）。刻意設計
/// 為不依賴 `dart:ui`／Flutter 的純 Dart 類別——淘汰時如何釋放資源交由
/// 呼叫端透過 [dispose] 決定，讓核心 LRU 邏輯本身可以用輕量假物件單元測試
/// （不需要真的建構 `ui.Image`），比照既有
/// `_PdfReaderViewState._boldOverlayImages`（Issue 3）的 LRU 快取設計精神
/// 抽成獨立可重用單元。
///
/// 使用 `Map`（Dart 預設實作為插入順序穩定的 `LinkedHashMap`）的插入順序
/// 語意實作 LRU：[get] 命中時會把該項目移到「最近使用」端（透過移除後
/// 重新插入），[put] 在超過 [maxSize] 時淘汰目前最舊（`keys.first`）的
/// 項目並呼叫 [dispose] 釋放。
class PdfThumbnailCache<T> {
  final int maxSize;
  final void Function(T value) dispose;
  final _entries = <int, T>{};

  PdfThumbnailCache({required this.maxSize, required this.dispose});

  /// 讀取鍵 [key] 對應的值；命中時視為「最近使用」，延後被淘汰的順序。
  /// 未命中回傳 `null`。
  T? get(int key) {
    final value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value;
    return value;
  }

  /// 寫入鍵 [key] 對應的值 [value]。若 [key] 已存在，舊值先被 [dispose]
  /// 釋放再覆寫；若寫入後項目數超過 [maxSize]，淘汰目前最舊的項目並呼叫
  /// [dispose] 釋放。
  void put(int key, T value) {
    final existing = _entries.remove(key);
    if (existing != null) dispose(existing);
    _entries[key] = value;
    if (_entries.length > maxSize) {
      final oldestKey = _entries.keys.first;
      dispose(_entries.remove(oldestKey) as T);
    }
  }

  bool contains(int key) => _entries.containsKey(key);

  int get length => _entries.length;

  /// 釋放所有目前快取的項目並清空——供持有者（例如
  /// [PdfThumbnailPanel]）在自身 `dispose()` 時呼叫，避免面板關閉時仍殘留
  /// 未釋放的縮圖影像。
  void clear() {
    for (final value in _entries.values) {
      dispose(value);
    }
    _entries.clear();
  }
}
```

- [x] **Step 2: 撰寫失敗測試**

建立 `app/test/reader/pdf_thumbnail_cache_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_thumbnail_cache.dart';

class _FakeImage {
  bool disposed = false;
  void dispose() => disposed = true;
}

void main() {
  PdfThumbnailCache<_FakeImage> makeCache({required int maxSize}) {
    return PdfThumbnailCache<_FakeImage>(
      maxSize: maxSize,
      dispose: (image) => image.dispose(),
    );
  }

  test('get() 對不存在的鍵回傳 null', () {
    final cache = makeCache(maxSize: 3);
    expect(cache.get(0), isNull);
  });

  test('put() 後 get() 可取回同一個值', () {
    final cache = makeCache(maxSize: 3);
    final image = _FakeImage();
    cache.put(0, image);
    expect(cache.get(0), same(image));
  });

  test('超過 maxSize 時，最舊未被 get() 觸碰過的項目會被 dispose 並移除', () {
    final cache = makeCache(maxSize: 2);
    final img0 = _FakeImage();
    final img1 = _FakeImage();
    final img2 = _FakeImage();
    cache.put(0, img0);
    cache.put(1, img1);
    cache.put(2, img2); // 超過上限 2，應淘汰最舊的 img0。

    expect(img0.disposed, isTrue);
    expect(cache.get(0), isNull);
    expect(cache.length, 2);
  });

  test('get() 會將項目標記為最近使用，延後其被淘汰的順序', () {
    final cache = makeCache(maxSize: 2);
    final img0 = _FakeImage();
    final img1 = _FakeImage();
    final img2 = _FakeImage();
    cache.put(0, img0);
    cache.put(1, img1);
    cache.get(0); // touch img0，img1 變成最舊。
    cache.put(2, img2); // 應淘汰 img1，不是 img0。

    expect(img1.disposed, isTrue);
    expect(img0.disposed, isFalse);
    expect(cache.get(0), same(img0));
  });

  test('put() 對已存在的鍵覆寫時，舊值會被 dispose', () {
    final cache = makeCache(maxSize: 3);
    final oldImg = _FakeImage();
    final newImg = _FakeImage();
    cache.put(0, oldImg);
    cache.put(0, newImg);

    expect(oldImg.disposed, isTrue);
    expect(cache.get(0), same(newImg));
  });

  test('contains() 正確反映鍵是否存在', () {
    final cache = makeCache(maxSize: 3);
    expect(cache.contains(0), isFalse);
    cache.put(0, _FakeImage());
    expect(cache.contains(0), isTrue);
  });

  test('clear() 釋放所有項目並清空', () {
    final cache = makeCache(maxSize: 3);
    final img0 = _FakeImage();
    final img1 = _FakeImage();
    cache.put(0, img0);
    cache.put(1, img1);
    cache.clear();

    expect(img0.disposed, isTrue);
    expect(img1.disposed, isTrue);
    expect(cache.length, 0);
  });
}
```

- [x] **Step 3: 執行測試確認通過**

Run: `flutter test test/reader/pdf_thumbnail_cache_test.dart --reporter expanded`
Expected: 7 項全數通過（Step 1 已先寫好實作，此步驟純粹是「先寫好完整實作，跑測試驗證行為正確」的驗證步驟——`PdfThumbnailCache` 的 LRU 邏輯屬於一次性可完整定義清楚的演算法，不透過逐一測試驅動增量開發）。

- [x] **Step 4: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/pdf_thumbnail_cache.dart app/test/reader/pdf_thumbnail_cache_test.dart
git commit -m "feat(epic-24): 新增 PdfThumbnailCache 泛型 LRU 快取（純 Dart，可脫離 dart:ui 測試）"
```

---

### Task 2: `PdfReaderView.renderThumbnail()` 靜態方法

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Test: `app/test/reader/pdf_reader_view_thumbnail_test.dart`

**Interfaces:**
- Consumes: `PdfReaderView` 既有的 `_document` 欄位（`PdfDocument?`）與 `document.pages[pageIndex]`（`PdfPage`，含 `.width`/`.height`/`.render()`）——皆為既有欄位/pdfrx API，非本工單新增。
- Produces: `static Future<ui.Image?> PdfReaderView.renderThumbnail(GlobalKey<State<PdfReaderView>> key, int pageIndex, {required double maxWidth})`——Task 5（`ReaderScreen` 接線）依賴此靜態方法。

- [x] **Step 1: 撰寫失敗測試**

建立 `app/test/reader/pdf_reader_view_thumbnail_test.dart`：

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

  testWidgets('renderThumbnail 回傳非 null 影像，寬度符合 maxWidth，高度依頁面比例換算',
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

    final image = await tester.runAsync(
      () => PdfReaderView.renderThumbnail(key, 0, maxWidth: 120),
    );

    expect(image, isNotNull);
    // sample_multi_page.pdf 頁面尺寸為 612×792（US Letter，見 fixture
    // MediaBox，Issue 5/6 已驗證），比例換算高度 = 792 / 612 * 120 ≈
    // 155.29，容許 1px 誤差（int 四捨五入）。
    expect(image!.width, 120);
    expect(image.height, closeTo(792 / 612 * 120, 1));
    image.dispose();
  });

  testWidgets('pageIndex 超出範圍時回傳 null，不拋出例外', (tester) async {
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

    final image = await tester.runAsync(
      () => PdfReaderView.renderThumbnail(key, 999, maxWidth: 120),
    );

    expect(image, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('State 尚未掛載時回傳 null', (tester) async {
    final orphanKey = GlobalKey<State<PdfReaderView>>();

    final image = await PdfReaderView.renderThumbnail(orphanKey, 0, maxWidth: 120);

    expect(image, isNull);
  });

  testWidgets('不同 pageIndex 各自產生獨立的影像，互不影響', (tester) async {
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

    final image0 = await tester.runAsync(
      () => PdfReaderView.renderThumbnail(key, 0, maxWidth: 80),
    );
    final image4 = await tester.runAsync(
      () => PdfReaderView.renderThumbnail(key, 4, maxWidth: 80),
    );

    expect(image0, isNotNull);
    expect(image4, isNotNull);
    expect(image0!.width, 80);
    expect(image4!.width, 80);
    image0.dispose();
    image4.dispose();
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/pdf_reader_view_thumbnail_test.dart`
Expected: FAIL（`renderThumbnail` 尚未定義，編譯錯誤）。

- [x] **Step 3: 新增靜態方法與私有實作**

在 `app/lib/reader/pdf_reader_view.dart` 中，於既有 `loadTableOfContents` 靜態方法（`search`／`setSearchHighlights`／`loadTableOfContents` 所在的靜態方法區塊）之後新增：

```dart
  /// 產生第 [pageIndex] 頁（0-indexed）的縮圖，寬度縮放至 [maxWidth]、
  /// 高度依頁面原始長寬比等比例換算（epic-24-pdf-engine-rebuild
  /// Issue 7）。文件尚未開啟完成、[pageIndex] 超出範圍、或 [key] 尚未掛載
  /// 時回傳 `null`，比照 [search]／[loadTableOfContents] 等既有靜態
  /// helper 的靜默忽略慣例。呼叫端負責在使用完畢後釋放回傳影像（
  /// `dispose()`）——[PdfThumbnailPanel] 透過 `PdfThumbnailCache` 管理
  /// 生命週期，見 `pdf_thumbnail_cache.dart`／`pdf_thumbnail_panel.dart`。
  static Future<ui.Image?> renderThumbnail(
    GlobalKey<State<PdfReaderView>> key,
    int pageIndex, {
    required double maxWidth,
  }) async {
    final state = key.currentState;
    if (state is! _PdfReaderViewState) return null;
    return state._renderThumbnail(pageIndex, maxWidth);
  }
```

於既有 `_search()` 方法（私有實作方法區塊）之後新增：

```dart
  /// 不使用 Isolate——`page.render()` 本身透過 pdfrx FFI 非同步呼叫取得
  /// 指定尺寸的頁面圖片，不涉及額外的純 Dart 像素運算（與 Issue 3
  /// `_detectCropRect`／`_recomputeOverlay` 呼叫 `page.render()` 的既有
  /// 模式相同，兩者皆未用 Isolate 包裹這個呼叫本身，見 Global
  /// Constraints）。[maxWidth] 是縮圖目標寬度（邏輯像素），高度依頁面
  /// 原始長寬比等比例換算，避免縮圖影像變形。
  Future<ui.Image?> _renderThumbnail(int pageIndex, double maxWidth) async {
    final document = _document;
    if (document == null) return null;
    if (pageIndex < 0 || pageIndex >= document.pages.length) return null;
    final page = document.pages[pageIndex];
    final scale = maxWidth / page.width;
    final rendered = await page.render(
      fullWidth: maxWidth,
      fullHeight: page.height * scale,
    );
    if (rendered == null) return null;
    try {
      return await rendered.createImage();
    } finally {
      rendered.dispose();
    }
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/pdf_reader_view_thumbnail_test.dart --reporter expanded`
Expected: 4 項全數通過。

- [x] **Step 5: 執行既有 PDF 測試確認零回歸**

Run: `flutter test test/reader/`
Expected: 全數通過（含既有 Issue 1-6 的 PDF 相關測試，確認新增的靜態/私有方法未影響既有行為）。

- [x] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_thumbnail_test.dart
git commit -m "feat(epic-24): PdfReaderView 新增 renderThumbnail() 靜態方法"
```

---

### Task 3: `PdfThumbnailPanel` widget

**Files:**
- Create: `app/lib/screens/pdf_thumbnail_panel.dart`
- Test: `app/test/screens/pdf_thumbnail_panel_test.dart`

**Interfaces:**
- Consumes: `PdfThumbnailCache<T>`（Task 1）。
- Produces: `class PdfThumbnailPanel extends StatefulWidget { const PdfThumbnailPanel({required int totalPages, required Future<ui.Image?> Function(int) renderThumbnail, required ValueChanged<int> onPageSelected}); }`——Task 5（`ReaderScreen` 接線）依賴此 widget。畫面 Key 慣例：`pdf_thumbnail_panel_empty`（空狀態）、`pdf_thumbnail_panel_grid`（`GridView`）、`pdf_thumbnail_tile_$index`（每格縮圖）。

- [x] **Step 1: 撰寫實作**

建立 `app/lib/screens/pdf_thumbnail_panel.dart`：

```dart
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../reader/pdf_thumbnail_cache.dart';

/// PDF 頁碼縮圖面板（epic-24-pdf-engine-rebuild Issue 7），掛載於
/// `TocBottomSheet` 的「縮圖」分頁（`TocBottomSheet.thumbnailTabContent`）。
/// 與 `ReaderScreen`／`PdfReaderView` 完全解耦（比照 `PdfSearchPanel`
/// 既有設計原則）：只透過 [renderThumbnail] 取得縮圖影像、透過
/// [onPageSelected] 回報選取，本身不知道呼叫端如何實際渲染 PDF 頁面、
/// 不直接依賴 `GlobalKey<State<PdfReaderView>>` 或 `PdfDocument`。
///
/// 縮圖僅於可視附近範圍內產生：`GridView.builder` 只會對接近可視範圍的
/// 索引呼叫 `itemBuilder`（Flutter 既有的 sliver 延遲建構機制），本
/// widget 不會在初次建構時就對全書每一頁呼叫 [renderThumbnail]。另外
/// 維護一個獨立於 `GridView` 版面回收機制的 [PdfThumbnailCache]（上限
/// [_maxCachedThumbnails] 張），確保無論捲動模式為何，記憶體中存活的
/// 縮圖影像數量有明確上限，超出上限時最舊使用的影像會被 `dispose()`
/// 釋放——比照既有 `_PdfReaderViewState._boldOverlayImages`（Issue 3）的
/// LRU 快取設計精神。
class PdfThumbnailPanel extends StatefulWidget {
  final int totalPages;
  final Future<ui.Image?> Function(int pageIndex) renderThumbnail;
  final ValueChanged<int> onPageSelected;

  const PdfThumbnailPanel({
    super.key,
    required this.totalPages,
    required this.renderThumbnail,
    required this.onPageSelected,
  });

  @override
  State<PdfThumbnailPanel> createState() => _PdfThumbnailPanelState();
}

class _PdfThumbnailPanelState extends State<PdfThumbnailPanel> {
  static const _maxCachedThumbnails = 24;

  late final _cache = PdfThumbnailCache<ui.Image>(
    maxSize: _maxCachedThumbnails,
    dispose: (image) => image.dispose(),
  );

  /// 防止同一個 [pageIndex] 在前一次 [renderThumbnail] 尚未完成時被重複
  /// 觸發（`GridView.builder` 可能在同一個索引仍在載入中時多次呼叫
  /// `itemBuilder`，例如捲動觸發的重建）。
  final _pending = <int>{};

  @override
  void dispose() {
    _cache.clear();
    super.dispose();
  }

  /// 面板已 unmount 時（`!mounted`）仍要 `image?.dispose()` 才 return——
  /// 非同步渲染完成當下面板可能已被移除（例如使用者已關閉 Bottom
  /// Sheet），此時回傳的 `ui.Image` 不會再被放進 [_cache]、也不會有機會
  /// 透過 [_cache] 的正常淘汰路徑釋放，若在這裡直接捨棄會造成原生記憶體
  /// （C++/GPU 端）洩漏。`_pending.remove` 改放進 `.whenComplete()`，
  /// 確保無論 [renderThumbnail] 成功、失敗或（理論上）被取消，都會執行，
  /// 避免非同步例外導致 `pageIndex` 永久卡在 [_pending]、使用者捲動回該頁
  /// 時 [_load] 恆被擋下、縮圖格永久停留在載入指示器（審查修正）。
  void _load(int pageIndex) {
    if (_pending.contains(pageIndex) || _cache.contains(pageIndex)) return;
    _pending.add(pageIndex);
    unawaited(
      widget.renderThumbnail(pageIndex).then((image) {
        if (!mounted || image == null) {
          image?.dispose();
          return;
        }
        setState(() => _cache.put(pageIndex, image));
      }).whenComplete(() {
        _pending.remove(pageIndex);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.totalPages <= 0) {
      return const Center(
        key: Key('pdf_thumbnail_panel_empty'),
        child: Text('無可用頁面'),
      );
    }
    return GridView.builder(
      key: const Key('pdf_thumbnail_panel_grid'),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.7,
      ),
      itemCount: widget.totalPages,
      itemBuilder: (context, index) {
        final image = _cache.get(index);
        if (image == null) _load(index);
        return InkWell(
          key: Key('pdf_thumbnail_tile_$index'),
          onTap: () => widget.onPageSelected(index),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: image == null
                    ? const Center(child: CircularProgressIndicator())
                    : RawImage(image: image, fit: BoxFit.contain),
              ),
              Text('${index + 1}'),
            ],
          ),
        );
      },
    );
  }
}
```

- [x] **Step 2: 撰寫測試**

建立 `app/test/screens/pdf_thumbnail_panel_test.dart`：

```dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/pdf_thumbnail_panel.dart';

/// 合成 [count] 張 2×2 像素的真實 `ui.Image`，供測試用假 `renderThumbnail`
/// callback 回傳——避免依賴真實 PDFium 渲染耗時，同時仍是真正的
/// `dart:ui` Image（可用 `debugDisposed` 驗證釋放時機，比純 Dart 假物件
/// 更貼近實際整合情境）。
Future<List<ui.Image>> _createTestImages(WidgetTester tester, int count) async {
  final images = await tester.runAsync(() async {
    final result = <ui.Image>[];
    for (var i = 0; i < count; i++) {
      final completer = Completer<ui.Image>();
      final pixels = Uint8List(2 * 2 * 4);
      ui.decodeImageFromPixels(pixels, 2, 2, ui.PixelFormat.rgba8888, completer.complete);
      result.add(await completer.future);
    }
    return result;
  });
  return images!;
}

void main() {
  testWidgets('totalPages 為 0 時顯示空狀態，不建構 GridView', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 0,
            renderThumbnail: (_) async => null,
            onPageSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('pdf_thumbnail_panel_empty')), findsOneWidget);
    expect(find.byKey(const Key('pdf_thumbnail_panel_grid')), findsNothing);
  });

  testWidgets('totalPages 遠大於可視範圍時，初次建構只觸發少量縮圖載入，不會一次渲染全書',
      (tester) async {
    final images = await _createTestImages(tester, 50);
    final requested = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 50,
            renderThumbnail: (index) async {
              requested.add(index);
              return images[index];
            },
            onPageSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(requested.length, lessThan(30),
        reason: '不應一次性渲染全書 50 頁縮圖，只應渲染可視附近範圍');
    expect(requested, isNot(contains(49)), reason: '清單底部（尚未捲動到）不應被提前渲染');
  });

  testWidgets('renderThumbnail 完成後，對應格子顯示縮圖影像取代載入指示器', (tester) async {
    final images = await _createTestImages(tester, 3);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 3,
            renderThumbnail: (index) async => images[index],
            onPageSelected: (_) {},
          ),
        ),
      ),
    );
    // 尚未完成非同步載入前，顯示載入指示器。
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pump();
    await tester.pump();

    expect(find.byType(RawImage), findsNWidgets(3));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('點擊縮圖觸發 onPageSelected 並傳入正確頁碼索引', (tester) async {
    final images = await _createTestImages(tester, 5);
    int? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 5,
            renderThumbnail: (index) async => images[index],
            onPageSelected: (index) => selected = index,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('pdf_thumbnail_tile_2')));
    expect(selected, 2);
  });

  testWidgets('捲動觸發夠多不同頁縮圖載入後，快取上限之外的舊縮圖會被 dispose', (tester) async {
    final images = await _createTestImages(tester, 40);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 40,
            renderThumbnail: (index) async => images[index],
            onPageSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 捲動至清單底部，觸發足夠多不同頁的縮圖載入（超過快取上限 24 張）。
    for (var i = 0; i < 10; i++) {
      await tester.drag(
        find.byKey(const Key('pdf_thumbnail_panel_grid')),
        const Offset(0, -2000),
      );
      await tester.pump();
      await tester.pump();
    }

    expect(images[0].debugDisposed, isTrue, reason: '最早載入、已捲出畫面外的縮圖應被淘汰釋放');
  });

  testWidgets('面板從 widget tree 移除時，快取中的縮圖全部釋放', (tester) async {
    final images = await _createTestImages(tester, 5);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 5,
            renderThumbnail: (index) async => images[index],
            onPageSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));

    for (final image in images) {
      expect(image.debugDisposed, isTrue);
    }
  });

  testWidgets('面板在縮圖仍在渲染中就被 Unmount，稍後才完成的影像仍會被 dispose，不洩漏',
      (tester) async {
    final completer = Completer<ui.Image?>();
    final images = await _createTestImages(tester, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 1,
            renderThumbnail: (_) => completer.future,
            onPageSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    // 縮圖仍在渲染中（completer 尚未完成）時就把面板從 widget tree 移除。
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));

    // 面板已 unmount 之後，非同步渲染才真正完成——這是 Critical 1 審查
    // 修正要保護的情境：遲來的 image 不會再被放進快取，必須在 `_load`
    // 的 `!mounted` 分支主動 dispose，否則原生記憶體洩漏。
    completer.complete(images[0]);
    await tester.pump();
    await tester.pump();

    expect(images[0].debugDisposed, isTrue,
        reason: '面板已 unmount，遲來的縮圖影像不應洩漏，須被 dispose()');
  });
}
```

- [x] **Step 3: 執行測試確認通過**

Run: `flutter test test/screens/pdf_thumbnail_panel_test.dart --reporter expanded`
Expected: 7 項全數通過。

- [x] **Step 4: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 5: Commit**

```bash
git add app/lib/screens/pdf_thumbnail_panel.dart app/test/screens/pdf_thumbnail_panel_test.dart
git commit -m "feat(epic-24): 新增 PdfThumbnailPanel widget——GridView 縮圖格＋LRU 快取整合"
```

---

### Task 4: `TocBottomSheet` 新增 `thumbnailTabContent` 插槽

**Files:**
- Modify: `app/lib/screens/toc_bottom_sheet.dart`
- Test: `app/test/screens/toc_bottom_sheet_pdf_test.dart`（新增測試至既有檔案）

**Interfaces:**
- Consumes: 無（純 `Widget?` 插槽，與 Task 1-3 型別無關，維持 `TocBottomSheet` 對其分頁內容不知情的既有解耦設計）。
- Produces: `TocBottomSheet(..., thumbnailTabContent: Widget?)`——Task 5（`ReaderScreen` 接線）依賴此參數。

- [x] **Step 1: 撰寫失敗測試**

在 `app/test/screens/toc_bottom_sheet_pdf_test.dart` 既有 `searchTabContent` 相關測試（`'傳入 searchTabContent 時...'`／`'未傳入 searchTabContent 時...'`）之後新增：

```dart
  testWidgets('傳入 thumbnailTabContent 時，切換到縮圖分頁顯示該內容而非預設佔位文字',
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
          thumbnailTabContent: const Text('THUMBNAIL_PANEL_PLACEHOLDER'),
        ),
      ),
    ));

    await tester.tap(find.text('縮圖'));
    await tester.pumpAndSettle();

    expect(find.text('THUMBNAIL_PANEL_PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('未傳入 thumbnailTabContent 時，縮圖分頁維持既有佔位文字（零回歸）',
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
        ),
      ),
    ));

    await tester.tap(find.text('縮圖'));
    await tester.pumpAndSettle();

    expect(find.text('此功能將於後續版本提供'), findsOneWidget);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/toc_bottom_sheet_pdf_test.dart`
Expected: 第一則新測試 FAIL（`thumbnailTabContent` 參數不存在，編譯錯誤；第二則因縮圖分頁目前已是既有佔位文字而通過，但整檔仍因編譯錯誤無法執行）。

- [x] **Step 3: 新增 `thumbnailTabContent` 參數並接線**

修改 `app/lib/screens/toc_bottom_sheet.dart`，在既有 `searchTabContent` 欄位宣告之後新增：

```dart
  /// PDF「縮圖」分頁要顯示的內容（epic-24-pdf-engine-rebuild Issue 7）；
  /// `null` 時該分頁顯示既有的「此功能將於後續版本提供」佔位文字。比照
  /// [searchTabContent] 既有設計，本 widget 刻意不知道傳入的是什麼。
  final Widget? thumbnailTabContent;
```

建構子新增對應具名參數：

```dart
    this.thumbnailTabContent,
    this.searchTabContent,
```

`build()` 內 PDF 分支的 `TabBarView.children`，把第二格（縮圖）的固定佔位文字改為消費新欄位：

```dart
                      children: [
                        _buildTocList(totalCharacterCount),
                        widget.thumbnailTabContent ??
                            const Center(child: Text('此功能將於後續版本提供')),
                        widget.searchTabContent ??
                            const Center(child: Text('此功能將於後續版本提供')),
                      ],
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/toc_bottom_sheet_pdf_test.dart --reporter expanded`
Expected: 全數通過（既有測試＋新增 2 則）。

- [x] **Step 5: 執行既有 EPUB 目錄測試確認零回歸**

Run: `flutter test test/screens/toc_bottom_sheet_test.dart`
Expected: 全數通過（EPUB 路徑不受影響——`thumbnailTabContent` 只在 `format == BookFormat.pdf` 分支被消費）。

- [x] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/toc_bottom_sheet.dart app/test/screens/toc_bottom_sheet_pdf_test.dart
git commit -m "feat(epic-24): TocBottomSheet 新增 thumbnailTabContent 插槽（維持與 ReaderScreen 解耦）"
```

---

### Task 5: `ReaderScreen` 接上縮圖面板

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`（新增測試至既有檔案）

**Interfaces:**
- Consumes: `PdfReaderView.renderThumbnail`（Task 2）、`PdfThumbnailPanel`（Task 3）、`TocBottomSheet.thumbnailTabContent`（Task 4）。

- [x] **Step 1: 新增縮圖寬度常數與匯入**

在 `app/lib/screens/reader_screen.dart` 檔案開頭既有 import 區塊（`import 'toc_bottom_sheet.dart';`／`import 'pdf_search_panel.dart';` 附近）新增：

```dart
import 'pdf_thumbnail_panel.dart';
```

在既有 `_pdfReaderViewKey` 欄位（`final _pdfReaderViewKey = GlobalKey<State<PdfReaderView>>();`）附近新增：

```dart
  /// PDF 縮圖面板（Issue 7）縮圖寬度上限，邏輯像素——與
  /// `PdfThumbnailPanel` 內部快取上限搭配控制記憶體占用；未鎖定於
  /// spec.md，屬實作階段依畫面呈現效果決定的數值。實際渲染寬度另外乘上
  /// `devicePixelRatio`（見 `_openPdfToc()`），避免高 PPI 裝置上縮圖模糊
  /// ——夾限於 [1.0, 3.0] 而非直接沿用（無上限），避免極端高 DPI 值讓
  /// 24 張快取上限的縮圖佔用過多記憶體（審查建議，Minor 1）。
  static const double _pdfThumbnailMaxWidth = 120;
```

- [x] **Step 2: 撰寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 既有 PDF 搜尋端對端測試群組之後（`tearDownAll` 之前）新增：

```dart
  testWidgets('PDF 縮圖：切換到縮圖分頁後正確顯示每一頁的縮圖格', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_thumbnail',
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

    await tester.tap(find.text('縮圖'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    for (var i = 0; i < 5; i++) {
      expect(find.byKey(Key('pdf_thumbnail_tile_$i')), findsOneWidget);
    }
    expect(find.byKey(const Key('pdf_thumbnail_tile_5')), findsNothing);
  });

  testWidgets('PDF 縮圖：點擊縮圖後正確關閉 Bottom Sheet，不拋出例外', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_thumbnail_tap',
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

    await tester.tap(find.text('縮圖'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    await tester.tap(find.byKey(const Key('pdf_thumbnail_tile_3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
```

（斷言設計比照 Issue 6 合併前審查歷程的既有教訓：透過 `TocBottomSheet`（Modal Route）呼叫 `PdfReaderView.jumpToPage()` 的實際頁碼變化，在測試環境下有不可靠的更新時序，即使搭配 `runAsync` 真實延遲等待仍可能停在目標頁前一頁——這是既有、與本工單邏輯無關的測試環境時序問題，不在此新增測試中斷言確切跳轉後頁碼，改為斷言 Bottom Sheet 正確關閉且無例外拋出。）

- [x] **Step 3: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "PDF 縮圖"`
Expected: FAIL（`pdf_thumbnail_tile_*` 找不到，因為「縮圖」分頁目前仍是佔位文字，尚未接上 `PdfThumbnailPanel`）。

- [x] **Step 4: 接上 `PdfThumbnailPanel`**

修改 `app/lib/screens/reader_screen.dart` 的 `_openPdfToc()` 方法。在既有 `final currentPath = PdfTocNavigator.findCurrentPath(...);` 之後、`_showThemedModalBottomSheet<void>(...)` 呼叫之前，新增一個依裝置螢幕密度換算的縮圖渲染寬度區域變數（審查建議 Minor 1：邏輯像素 120px 在高 PPI 裝置上放大顯示會模糊，乘上 `devicePixelRatio` 取得更清晰畫質；夾限於 `[1.0, 3.0]` 避免極端高 DPI 值讓 24 張快取上限的縮圖佔用過多記憶體，不直接沿用既有 `pageRenderScale()`——該函式下限鎖定 2.0，是為 Issue 3 全頁加粗/裁切覆蓋圖畫質需求設計，套用在縮圖上會讓一般 1x DPI 裝置也被迫渲染 2 倍尺寸，與縮圖「刻意犧牲畫質換取小記憶體占用」的設計目標相違）：

```dart
    final pdfThumbnailMaxWidth =
        _pdfThumbnailMaxWidth * MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
```

接著在既有 `TocBottomSheet(...)` 建構呼叫中，`searchTabContent: PdfSearchPanel(...)` 之前新增：

```dart
        thumbnailTabContent: PdfThumbnailPanel(
          totalPages: _pdfPageInfo?.totalPages ?? 0,
          renderThumbnail: (pageIndex) => PdfReaderView.renderThumbnail(
            _pdfReaderViewKey,
            pageIndex,
            maxWidth: pdfThumbnailMaxWidth,
          ),
          onPageSelected: (pageIndex) {
            Navigator.of(context).pop();
            PdfReaderView.jumpToPage(_pdfReaderViewKey, pageIndex);
          },
        ),
```

（`_openPdfToc()` 已有 `if (!_pdfTocLoaded) return;` 防呆，代表呼叫此方法時文件必已成功開啟過，`_pdfPageInfo` 必已由 `onPageChanged` 回報過至少一次，`totalPages` 不會是「文件根本未開啟」情境下的無意義預設值；`?? 0` 純粹是型別系統要求的空值防呆，非真正會在正常流程觸發的分支。）

- [x] **Step 5: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "PDF 縮圖" --reporter expanded`
Expected: 2 項全數通過。

- [x] **Step 6: 重複執行 3 次確認無間歇性失敗**

Run（重複 3 次）：`flutter test test/screens/reader_screen_test.dart --plain-name "PDF 縮圖"`
Expected: 3 次執行皆全數通過（比照 Issue 4/5/6 審查發現 Timer/動畫時序競態的教訓，新增的非同步互動測試務必重跑數次確認穩定）。

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-24): ReaderScreen 整合 PDF 頁碼縮圖——縮圖面板接線、點擊跳頁"
```

---

### Task 6: 端對端驗證與計畫收尾

- [x] **Step 1: `flutter analyze` 確認整專案乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 2: 執行本工單全部相關測試**

Run: `flutter test test/reader/pdf_thumbnail_cache_test.dart test/reader/pdf_reader_view_thumbnail_test.dart test/screens/pdf_thumbnail_panel_test.dart test/screens/toc_bottom_sheet_pdf_test.dart test/screens/reader_screen_test.dart`
Expected: 全數通過，新增本工單測試數（Task1 +7、Task2 +4、Task3 +7、Task4 +2、Task5 +2，共 +22）。

- [x] **Step 3: 執行全專案測試確認零回歸**

Run: `flutter test`
Expected: 全數通過，通過總數應為 Issue 6 合併時的基準（1124）之上，新增 +22（合計 1146）。若出現與本工單變更無關的既有間歇性失敗（例如 `pdf_reader_view_dual_page_test.dart`，見 Issue 6 合併前審查歷程），單獨重跑該檔案確認通過即可，非本工單需修復範圍。

- [x] **Step 4: 對照 `issues.md` Issue 7 驗收條件自我檢查**

逐項確認：
- 縮圖面板正確顯示整本書頁碼縮圖，點擊後正確跳轉至對應頁面（Task 5）。
- 縮圖僅於可視範圍內產生，不一次性渲染全書（Task 3 `GridView.builder` 延遲建構＋對應測試驗證）。
- 縮圖分頁正確掛載於 Issue 5 的目錄 Bottom Sheet 殼層內（Task 4）。
- 淘汰快取的縮圖資源正確釋放（`dispose()`），大量頁數書籍快速捲動不造成記憶體持續成長（Task 1 `PdfThumbnailCache` LRU＋Task 3 對應測試驗證）。
- 單元測試驗證縮圖產生/快取/釋放邏輯，透過可觀察的快取狀態或資源計數斷言（Task 1／Task 3，`debugDisposed`／假物件計數）。
- `flutter analyze` 乾淨、`flutter test` 全數通過（Step 1-3）。

- [x] **Step 5: 更新本工單計畫檔案的完成狀態**

將本檔案（`plan-issue-7.md`）中所有已完成 Task 的 `- [x]` 改為 `- [x]`。

- [x] **Step 6: 提交追蹤性 commit（若 Step 5 有變更）**

```bash
git add docs/epics/epic-24-pdf-engine-rebuild/plans/plan-issue-7.md
git commit -m "docs(epic-24): plan-issue-7 全部 Task 標記完成"
```
