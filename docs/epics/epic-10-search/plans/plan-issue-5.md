# Epic 10 Issue 5：搜尋跳轉 Seam（`ReaderScreen.initialJumpTarget`＋暫態高亮）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者從全庫搜尋（Issue 4 的 `LibrarySearchScreen`）點擊一則內容匹配片段後，真正開書並精確跳轉到該片段所在位置（Foliate：CFI；PDF：頁碼＋頁內座標），抵達後顯示 3 秒暫態高亮提示，且完全不影響使用者原本既有的閱讀進度記錄機制。

**Architecture：** `ReaderScreen` 新增可選建構參數 `initialJumpTarget`（`ReaderJumpTarget` 值物件，新檔案 `app/lib/reader/reader_jump_target.dart`），只影響「開書當下傳給底層 View 的初始定位參數」這一個決策點（`initialLocatorJson`/`initialPageIndex` 改為「`initialJumpTarget` 存在則優先用它，否則沿用既有 `_initialPosition`」），不新增任何暫停/追蹤旗標。抵達目標位置後（`onPageRendered` 觸發時）由 `ReaderScreen` 端一個 Dart `Timer` 主導 3 秒暫態高亮生命週期：PDF 複用既有 `pageOverlaysBuilder` 疊加機制新增一個獨立的暫態高亮矩形；Foliate 在 `main.js` 新增 `window.showSearchHighlight()`/`window.clearSearchHighlight()`，使用與既有 TTS 朗讀高亮完全獨立的 `currentSearchHighlightValue` annotation key 空間。使用者提前翻頁或點擊畫面時，既有的 `_handleZoneAction()` 統一入口一併呼叫清除。`LibrarySearchScreen`（Issue 4）點擊內容匹配片段時，透過新的 `ReaderJumpTarget.fromContentLocator()` 靜態方法把 `ContentMatchSnippet.locator` 字串解析成 `ReaderJumpTarget`，帶入開書呼叫。

**Tech Stack：** Flutter/Dart、`flutter_inappwebview`（Foliate JS 橋接，既有）、`pdfrx`（PDF `pageOverlaysBuilder`，既有）。

**Spec：** [`docs/epics/epic-10-search/spec.md`](../spec.md) §6（`ReaderScreen` Seam 擴充，本計畫的唯一技術事實來源）、§1（`book_content_index.locator` 的 PDF/Foliate 兩種格式，供解析邏輯對照）；工單來源 [`docs/epics/epic-10-search/issues.md`](../issues.md) Issue 5；既有程式碼依據：`app/lib/screens/reader_screen.dart`（`_initialPosition`／`_writeCurrentPosition()`／`_handlePageRendered()`／`_handleZoneAction()` 既有機制）、`app/lib/reader/pdf_reader_view.dart`（`_buildProcessedOverlay`／`setSearchHighlights` 既有暫態疊加模式）、`app/lib/reader/foliate_reader_view.dart`＋`app/android/app/src/main/assets/foliate/main.js`（`showTtsHighlight`/`clearTtsHighlight` 既有獨立 key 空間模式，ADR 0026）、`app/lib/screens/library_search_screen.dart`（Issue 4，`_openBook()` 既有開書呼叫點）。

## Global Constraints

- **依賴已滿足**：Issue 4（`LibrarySearchScreen`／`SearchRepository`／`ContentMatchSnippet.locator`）已完成並合併（PR #234）。
- **`initialJumpTarget` 的作用範圍精確限定，不新增任何「暫停進度儲存」旗標（spec.md §6 逐字規定）**：現行 `_writeCurrentPosition()` 只在 App 背景化／`dispose()` 這種 checkpoint 時機才讀取當下最新的 `_epubPositionInfo`/`_pdfPageInfo` 寫入資料庫，不是每次 `onLocatorChanged` 都寫入；`initialJumpTarget` 要做的事情跟現行「用資料庫存的 `lastPosition` 決定 `initialLocatorJson`/`initialPageIndex`」完全同構，只是多一個優先權更高的來源可選。除了「開書當下決定初始定位參數」這一個決策點，**不特殊處理後續的 `onLocatorChanged`／checkpoint 寫入**——使用者從跳轉位置開始往後翻頁閱讀，`_epubPositionInfo`/`_pdfPageInfo` 自然更新為使用者實際所在位置，下次 checkpoint 觸發時就會正確存下使用者真正閱讀到的地方。
- **已知且刻意接受的邊界情況（`review-plan-issue-5.md` I-2）：使用者跳轉後未曾翻頁即離開，`dispose()` 會把跳轉位置存成新進度，覆蓋掉跳轉前的舊進度**——這不是本計畫的疏漏，而是上一條規則的直接推論，且 spec.md §6 已在文件層級明確權衡並記錄過**同一類**考量後拒絕過："`不需要額外的「使用者是否已產生主動互動」判斷（審查意見 I-2 提議追蹤『第一次重定位事件』，經查證現行 checkpoint-only 寫入機制後，這層追蹤是不必要的複雜度，予以簡化）`"（原文逐字引用，見 spec.md §6）。本計畫不在 Task 層級重新引入這層追蹤去覆蓋 spec.md 已經定案的簡化決策；改為在 Task 4 補一個測試明確鎖定並記錄「使用者跳轉後立即離開時，checkpoint 會把跳轉位置存成新進度」這個目前的實際行為（測試名稱與註解會清楚標註這是刻意接受的行為，不是回歸），讓這個權衡不再是「無測試覆蓋的隱性行為」。**若日後要修改這個行為（例如真的要加一層互動追蹤），需要回頭修訂 spec.md §6 本身，不是單獨修這張計畫**——這屬於產品層級的取捨，需要人類決定是否值得為此增加複雜度。
- **暫態高亮的生命週期由 Dart 端 `Timer` 主導，不用 JS `setTimeout`（spec.md §6 逐字規定）**：比照專案既有「計時器一律由 Dart 端主導」慣例。這裡刻意**不**引入 `package:clock`——`Timer` 本身是 Zone-aware 的，`flutter_test` 的 `TestWidgetsFlutterBinding` 已經把整個測試包在 fake-async zone 內，`tester.pump(Duration(...))` 天然能推進一般 `Timer(duration, callback)`（比照本檔案既有 `_openBookTimeoutTimer`/`_syncCheckpointTimer` 皆為裸 `Timer`、無需 `package:clock` 即可測試的既有先例）；`package:clock` 只在需要「量測兩個真實時間點之間經過了多久」（例如 `TapZoneDetector` 判斷兩次點擊間隔）時才需要，本工單的需求是「排定一個未來回呼」，兩者本質不同，不要混淆套用。
- **Foliate 暫態高亮改用 `view.js`（釘定 vendored 檔案）既有的 `foliate-search:` 前綴＋原生 `Overlayer.outline` 樣式，放棄自訂顏色/直排橫排/E-Ink 客製化（`review-plan-issue-5.md` I-1，推翻原計畫「main.js 自行定義綠色高亮＋直排橫排＋E-Ink 樣式」設計）**：原計畫誤判 `main.js` 第 910 行註解「一般標記（非 `foliate-search:`/`foliate-note:` 前綴）……」是在說「`foliate-search:` 是保留但尚未使用的前綴名稱」，規劃階段查證 `view.js` 原始碼後推翻這個判斷——`SEARCH_PREFIX = 'foliate-search:'`是這份釘定 vendored 函式庫**自己既有、寫死的常數**，`#drawAnnotations()`/`addAnnotation()` 對它的處理是無條件呼叫 `overlayer.add(value, range, Overlayer.outline)`（**不帶任何 `options`、也不發送 `draw-annotation` 事件**），與 `foliate-note:`（TTS）／裸 CFI（劃線/備註）這兩種會透過 `draw-annotation` 事件把繪製決定權交還給 `main.js` 呼叫端的既有機制完全不同；`Overlayer.outline()` 未收到 `options` 時的預設值固定是 `color='red', strokeWidth=3`，無法從 `main.js` 客製化。三個可能的替代方案逐一評估：(1) 修改 `view.js` 讓 `SEARCH_PREFIX` 也發送 `draw-annotation` 事件——違反 ADR 0011「不修改任何 vendored 檔案」；(2) 重用 `foliate-note:`（TTS 既有 key 空間）——若搜尋跳轉目標剛好是目前正在朗讀的句子，兩者會共用完全相同的 annotation value 字串，`clearSearchHighlight()`／`clearTtsHighlight()` 任一方呼叫都會刪掉對方的高亮，正是 spec.md §6 明文要求要避免的「互相汙染」；(3) 使用裸 CFI（劃線/備註既有 key 空間）——若搜尋跳轉目標剛好是使用者已手動劃線的句子，會暫時覆蓋掉該劃線的視覺呈現，且 `clearSearchHighlight()` 會把使用者的真實劃線從畫面上一併移除，直到下次 `setDecorations()` 全量重送才會恢復，是比 (2) 更嚴重的資料層級風險。三者相比，直接沿用 `foliate-search:` 既有的固定紅色外框樣式是風險最低的選擇——它的 key 空間本來就與劃線/備註/TTS 三者完全獨立（這正是 `view.js` 把它與 `NOTE_PREFIX` 分開處理的原因），語意上也精確符合「暫態、非持久化的搜尋位置指示」。**代價（已知且接受的平台限制）**：Foliate 端的暫態高亮固定為紅色外框（無填色），無法依 E-Ink 模式切換高對比樣式、無法依直排/橫排調整外觀，與 PDF 端可自訂的綠色填色＋外框樣式不一致——這是 ADR 0011 與現有 vendored 函式庫行為交互下的必然結果，非實作疏漏，issues.md 若要追求兩端視覺一致，需要另立工單評估修改 `view.js` 的利弊（超出本工單範圍）。
- **PDF 暫態高亮複用既有 `pageOverlaysBuilder` 疊加機制（`pdf_reader_view.dart`），比照劃線/既有 PDF 內文搜尋（Chrome Bar「搜尋」按鈕，`PdfSearchPanel`／`setSearchHighlights`）既有疊加繪製模式**，但**不共用**內部狀態（`_searchMatches`/`_currentSearchMatchIndex` 是 PDF 內文搜尋專屬的「可能多筆、由使用者手動關閉搜尋面板才消失」清單；本工單的暫態高亮是「全域最多一筆、3 秒後自動消失」的完全獨立概念，兩者資料來源、生命週期、觸發呼叫端皆不同，只有視覺樣式相似）。
- **清除時機統一收斂在既有 `_handleZoneAction()` 入口最上方**（spec.md §6：「使用者提前翻頁或點擊畫面時，既有的翻頁/點擊處理路徑一併呼叫清除，取兩者較早發生者」）：`_handleZoneAction()` 是本專案 3×3 熱區點擊（`previousPage`/`nextPage`/`menu`/`none`）與音量鍵翻頁（`_handleVolumeKeyCall` 內部轉呼叫 `_handleZoneAction`）的唯一既有統一入口，涵蓋了「翻頁」與「點擊畫面」兩種情境，不需要另外攔截 `onLocatorChanged`（該回呼在「書籍剛開啟、顯示跳轉目標位置」當下本身就會觸發一次，若在那裡清除會在使用者看到高亮之前就把它清掉，見下方 Task 4 說明）。
- **`SearchRepository.searchContent()` 命中的書籍已排除 CBZ（Issue 2/3 既有結論：CBZ 恆為 `unsupported`，不會出現在索引資料中）**，本計畫的 Foliate 分支雖然技術上涵蓋 `isFoliateFormat()` 的全部格式（含 CBZ），但實務上 CBZ 不會透過本 Seam 被跳轉，不需要為此另寫防呆（YAGNI）。
- **誠實測試邊界（比照既有 TTS 朗讀高亮測試慣例，`reader_screen_test.dart`「同步高亮跟隨」測試群組既有註解）**：`flutter_test` 環境下 `FoliateReaderView` 的 `_controller` 恆為 `null`，`showSearchHighlight()`/`clearSearchHighlight()` 實際送出的 JS 呼叫參數無法在 `ReaderScreen`／`FoliateReaderView` 這層直接攔截斷言。本計畫的測試策略：(1) `main.js` 端的 key 空間隔離／函式存在性用**靜態原始碼掃描**驗證（比照既有「main.js 朗讀高亮 regression guard」）；(2) `ReaderScreen` 端只驗證「wiring 不崩潰」；(3) PDF 端因為 `pageOverlaysBuilder` 是純 Dart／真實可渲染的機制，可以完整驗證（顯示、3 秒自動清除、提前清除皆有真實 widget 可斷言），**PDF 測試因此是本工單「Dart 端 Timer 生命週期邏輯」（`_maybeShowSearchJumpHighlight`/`_clearSearchJumpHighlight`/`_searchJumpHighlightTimer`，格式無關的共用程式碼）唯一但足夠的完整驗證**——Foliate 分支呼叫的是不同的靜態方法，但共用同一段 Timer 生命週期程式碼，PDF 測試已完整覆蓋這段共用邏輯正確性；(4) 真實 JS 高亮渲染正確性（含跳轉是否精確、3 秒視覺效果；Foliate 端因改用 `view.js` 既有的 `foliate-search:` 固定紅色外框樣式，**不**隨直排/橫排或 E-Ink 模式調整，見上方「Foliate 暫態高亮改用 view.js 既有前綴」說明）須真機或 `integration_test/` 手動驗證，見 Task 5 收尾步驟。
- **`ReaderJumpTarget.fromContentLocator()` 解析失敗時分層優雅退化（審查修正 M-2，推翻原計畫「缺欄位一律回傳 null」設計）**：`page` 欄位缺失/型別錯誤時回傳 `null`（沒有頁碼就沒有任何可跳轉目標），呼叫端（`LibrarySearchScreen`）當作「一般開書、無跳轉目標」處理，不拋例外、不崩潰；`rect` 欄位缺失/型別錯誤時**不**整筆放棄，改為回傳只有 `pdfPageIndex`（無 `pdfRect`）的 `ReaderJumpTarget`——仍能正確跳轉到目標頁面，只是沒有精確座標可畫暫態高亮，比完全放棄跳轉、退回舊 `lastPosition` 更貼近使用者意圖。這是「無法窮舉但理論上不該發生」的防禦（`book_content_index.locator` 是系統自己寫入的資料，不是使用者輸入），比照 `SqliteSearchRepository.searchContent()` 對 `DatabaseException` 的既有防禦分級（見 `reviews/review-issue-4.md` M-4 的先例）。
- **所有新增程式碼註解使用正體中文（zh-TW）**，比照全專案既有慣例。

---

## 檔案結構總覽

- **Create：** `app/lib/reader/reader_jump_target.dart` — `ReaderJumpTarget` 值物件＋`fromContentLocator()` 靜態解析方法。
- **Create：** `app/test/reader/reader_jump_target_test.dart`
- **Modify：** `app/lib/reader/pdf_reader_view.dart` — 新增 `showTemporaryHighlight`/`clearTemporaryHighlight` 靜態方法、內部狀態、疊加繪製。
- **Create：** `app/test/reader/pdf_reader_view_jump_highlight_test.dart`
- **Modify：** `app/android/app/src/main/assets/foliate/main.js` — 新增 `window.showSearchHighlight`/`window.clearSearchHighlight`。
- **Modify：** `app/lib/reader/foliate_reader_view.dart` — 新增對應的 Dart 端靜態方法。
- **Modify：** `app/test/reader/foliate_reader_view_test.dart` — 新增 main.js regression guard 測試群組。
- **Modify：** `app/lib/screens/reader_screen.dart` — 新增 `initialJumpTarget` 建構參數＋位置覆寫邏輯＋暫態高亮 Timer 生命週期。
- **Modify：** `app/test/screens/reader_screen_test.dart` — 新增對應測試。
- **Modify：** `app/lib/screens/library_search_screen.dart` — 內容匹配片段點擊時帶入 `ReaderJumpTarget`。
- **Modify：** `app/test/screens/library_search_screen_test.dart` — 新增對應測試。

---

### Task 1：`ReaderJumpTarget` 值物件＋`ReaderScreen` 初始定位覆寫

**Files：**
- Create: `app/lib/reader/reader_jump_target.dart`
- Test: `app/test/reader/reader_jump_target_test.dart`
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces：**
- Consumes：既有 `app/lib/reader/percent_rect.dart` 的 `PercentRect`、`app/lib/library/models/library_enums.dart` 的 `BookFileFormat`。
- Produces：
  ```dart
  class ReaderJumpTarget {
    final String? cfi;
    final int? pdfPageIndex;
    final PercentRect? pdfRect;
    const ReaderJumpTarget({this.cfi, this.pdfPageIndex, this.pdfRect});

    static ReaderJumpTarget? fromContentLocator({
      required BookFileFormat format,
      required String locator,
    });
  }
  ```
  `ReaderScreen` 新增可選具名建構參數 `initialJumpTarget`（型別 `ReaderJumpTarget?`）。供 Task 4（暫態高亮觸發）與 Task 5（`LibrarySearchScreen` 呼叫端）使用。

- [ ] **Step 1：寫一組會失敗的測試（`ReaderJumpTarget.fromContentLocator`）**

建立 `app/test/reader/reader_jump_target_test.dart`：

```dart
// app/test/reader/reader_jump_target_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';

void main() {
  group('ReaderJumpTarget.fromContentLocator', () {
    test('Foliate 格式：locator 本身即為 CFI 字串，原樣帶入 cfi 欄位', () {
      final target = ReaderJumpTarget.fromContentLocator(
        format: BookFileFormat.epub,
        locator: 'epubcfi(/6/2!/4/2)',
      );

      expect(target, isNotNull);
      expect(target!.cfi, 'epubcfi(/6/2!/4/2)');
      expect(target.pdfPageIndex, isNull);
      expect(target.pdfRect, isNull);
    });

    test('KF8(AZW3)/TXT/MD 皆比照 EPUB，locator 原樣帶入 cfi 欄位', () {
      for (final format in [
        BookFileFormat.azw3,
        BookFileFormat.txt,
        BookFileFormat.md,
      ]) {
        final target = ReaderJumpTarget.fromContentLocator(
          format: format,
          locator: 'epubcfi(/6/4)',
        );
        expect(target?.cfi, 'epubcfi(/6/4)', reason: '格式 $format 應原樣帶入');
      }
    });

    test('PDF 格式：解析 {"page":int,"rect":{...}} JSON 字串', () {
      final target = ReaderJumpTarget.fromContentLocator(
        format: BookFileFormat.pdf,
        locator:
            '{"page":3,"rect":{"left":0.1,"top":0.2,"right":0.5,"bottom":0.3}}',
      );

      expect(target, isNotNull);
      expect(target!.pdfPageIndex, 3);
      expect(
        target.pdfRect,
        const PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
      );
      expect(target.cfi, isNull);
    });

    test('PDF 格式但 locator 不是合法 JSON 時回傳 null，呼叫端應退回一般開書路徑', () {
      final target = ReaderJumpTarget.fromContentLocator(
        format: BookFileFormat.pdf,
        locator: '不是 JSON',
      );

      expect(target, isNull);
    });

    test(
        'PDF 格式但 locator 缺少（或壞掉的）rect 欄位時，優雅降級為只有頁碼、沒有暫態高亮座標'
        '（審查修正 M-2，推翻原計畫「整筆回傳 null」設計）', () {
      final missingRect = ReaderJumpTarget.fromContentLocator(
        format: BookFileFormat.pdf,
        locator: '{"page":3}',
      );
      expect(missingRect, isNotNull);
      expect(missingRect!.pdfPageIndex, 3);
      expect(missingRect.pdfRect, isNull);

      final malformedRect = ReaderJumpTarget.fromContentLocator(
        format: BookFileFormat.pdf,
        locator: '{"page":3,"rect":"不是物件"}',
      );
      expect(malformedRect, isNotNull);
      expect(malformedRect!.pdfPageIndex, 3);
      expect(malformedRect.pdfRect, isNull);
    });

    test('PDF 格式但 locator 缺少 page 欄位時回傳 null（沒有頁碼就沒有任何可跳轉的目標）', () {
      final target = ReaderJumpTarget.fromContentLocator(
        format: BookFileFormat.pdf,
        locator: '{"rect":{"left":0.1,"top":0.2,"right":0.5,"bottom":0.3}}',
      );

      expect(target, isNull);
    });
  });
}
```

- [ ] **Step 2：執行測試，確認因 `reader_jump_target.dart` 不存在而失敗**

Run: `flutter test test/reader/reader_jump_target_test.dart`
Expected: FAIL（`Target of URI doesn't exist: 'package:elinkbook/reader/reader_jump_target.dart'`）

- [ ] **Step 3：實作 `reader_jump_target.dart`**

```dart
// app/lib/reader/reader_jump_target.dart
import 'dart:convert';

import '../library/models/library_enums.dart';
import 'percent_rect.dart';

/// 全庫搜尋跳轉目標（epic-10-search Issue 5，spec.md §6）：`ReaderScreen`
/// 開書當下用來決定「建構子傳給底層 View 的初始定位參數」，優先權高於
/// 資料庫既有的 `lastPosition`；作用範圍精確限定於開書當下這一次性用途，
/// 不影響後續任何翻頁/checkpoint 寫入行為（見 `reader_screen.dart`
/// `initialJumpTarget` 欄位文件註解）。
class ReaderJumpTarget {
  /// Foliate 格式（EPUB/KF8/CBZ/TXT/MD）的目標 CFI。
  final String? cfi;

  /// PDF 目標頁碼（0-indexed）。
  final int? pdfPageIndex;

  /// PDF 頁內精確座標，暫態高亮疊加繪製用；[pdfPageIndex] 存在但本欄位
  /// 為 `null` 時，仍會正常跳轉頁面，只是不顯示暫態高亮。
  final PercentRect? pdfRect;

  const ReaderJumpTarget({this.cfi, this.pdfPageIndex, this.pdfRect});

  /// 從 `SearchRepository.searchContent()` 回傳的
  /// `ContentMatchSnippet.locator` 建構跳轉目標（spec.md §1／§6）：
  /// Foliate 格式 locator 本身即為 CFI 字串；PDF 格式 locator 為
  /// `{"page":int,"rect":{"left":...,"top":...,"right":...,"bottom":...}}`
  /// 的 JSON 字串（見 `pdf_content_indexer.dart` 寫入格式，Issue 1）。
  /// `page` 欄位缺失/型別錯誤時回傳 `null`——沒有頁碼就沒有任何可跳轉的
  /// 目標，呼叫端應退回一般開書路徑而非崩潰；`rect` 欄位缺失/型別錯誤時
  /// **優雅降級**為只有 `pdfPageIndex`、`pdfRect` 為 `null`（審查修正
  /// M-2，推翻原計畫「rect 有問題就整筆回傳 null」設計）——仍能正確跳轉
  /// 到目標頁面，只是沒有精確座標可畫暫態高亮，比整個放棄跳轉、退回舊
  /// `lastPosition` 更貼近使用者「點了搜尋結果」的意圖。這兩種欄位皆是
  /// 系統自己寫入的衍生資料，理論上不會異常，但不假設一定合法（比照
  /// `SqliteSearchRepository.searchContent()` 對 `DatabaseException` 的
  /// 既有防禦分級）。
  static ReaderJumpTarget? fromContentLocator({
    required BookFileFormat format,
    required String locator,
  }) {
    if (format != BookFileFormat.pdf) {
      return ReaderJumpTarget(cfi: locator);
    }
    try {
      final map = jsonDecode(locator) as Map<String, dynamic>;
      final pageIndex = map['page'] as int;
      return ReaderJumpTarget(
        pdfPageIndex: pageIndex,
        pdfRect: _parsePdfRect(map['rect']),
      );
    } catch (_) {
      return null;
    }
  }

  /// [rawRect] 是否為合法的 `{"left":...,"top":...,"right":...,"bottom":...}`
  /// 結構，任何一步失敗（型別不符、缺欄位）皆回傳 `null`，不拋例外——
  /// 呼叫端（[fromContentLocator]）遇到 `null` 會保留已解析出的
  /// `pdfPageIndex`，只是不顯示暫態高亮（審查修正 M-2）。
  static PercentRect? _parsePdfRect(dynamic rawRect) {
    if (rawRect is! Map<String, dynamic>) return null;
    try {
      return PercentRect(
        left: (rawRect['left'] as num).toDouble(),
        top: (rawRect['top'] as num).toDouble(),
        right: (rawRect['right'] as num).toDouble(),
        bottom: (rawRect['bottom'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 4：執行測試，確認全數通過**

Run: `flutter test test/reader/reader_jump_target_test.dart`
Expected: PASS（全部 6 個測試）

- [ ] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/reader_jump_target.dart app/test/reader/reader_jump_target_test.dart
git commit -m "$(cat <<'EOF'
feat(search): 新增 ReaderJumpTarget 值物件（Issue 5）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B86LmxdxNXsUcepHoYjhmX
EOF
)"
```

- [ ] **Step 7：寫一組會失敗的測試（`ReaderScreen.initialJumpTarget` 覆寫初始定位）**

在 `app/test/screens/reader_screen_test.dart`，於 import 區塊新增：

```dart
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/reader/reading_position.dart';
```

在檔案內任一 `void main() { ... }` 的既有 `group`/`testWidgets` 之間（建議緊接在檔案開頭 `prefsManager` 等共用 fixture 宣告之後、第一個既有 `testWidgets` 之前）新增：

```dart
  group('epic-10-search Issue 5：initialJumpTarget 覆寫初始定位', () {
    testWidgets('PDF：initialJumpTarget.pdfPageIndex 優先於資料庫既有 lastPosition',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        readingPositionByBookId: {
          'b_jump_pdf_pos': const ReadingPosition(pdfPageIndex: 4),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_jump_pdf_pos',
            prefsManager: prefsManager,
            initialJumpTarget: const ReaderJumpTarget(pdfPageIndex: 2),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      expect(pdfView.initialPageIndex, 2);
    });

    testWidgets('Foliate：initialJumpTarget.cfi 優先於資料庫既有 lastPosition',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        readingPositionByBookId: {
          'b_jump_epub_pos': const ReadingPosition(
            epubLocatorJson: 'epubcfi(/stored)',
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_jump_epub_pos',
            prefsManager: prefsManager,
            initialJumpTarget: const ReaderJumpTarget(cfi: 'epubcfi(/jump)'),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      expect(foliateView.initialLocatorJson, 'epubcfi(/jump)');
    });

    testWidgets(
        'initialJumpTarget 為 null（一般開書）時，沿用資料庫既有 lastPosition，零回歸',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        readingPositionByBookId: {
          'b_no_jump_pos': const ReadingPosition(
            epubLocatorJson: 'epubcfi(/stored)',
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_no_jump_pos',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      expect(foliateView.initialLocatorJson, 'epubcfi(/stored)');
    });

    testWidgets(
        'PDF：跳轉後使用者繼續翻頁，dispose() 的 checkpoint 存檔行為與未帶入 initialJumpTarget 時完全一致'
        '（issues.md Issue 5 單元測試要求，審查修正 I-3）', (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        readingPositionByBookId: {
          'b_jump_then_navigate': const ReadingPosition(pdfPageIndex: 4),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_jump_then_navigate',
            prefsManager: prefsManager,
            initialJumpTarget: const ReaderJumpTarget(pdfPageIndex: 2),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 模擬使用者從跳轉目標（頁碼 2）繼續往後翻到頁碼 3（比照既有 PDF
      // 測試直接呼叫 onPageChanged 的既有慣例，不需要真的等待 pdfrx
      // 完整載入）。
      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 3, totalPages: 5));
      await tester.pump();

      // 移除畫面觸發 dispose()，比照既有「PDF 收到 onPageChanged 後離開
      // 畫面（dispose），正確寫入 ReadingPosition」測試的既有慣例（見
      // reader_screen_test.dart「Epic 5 Issue 2：閱讀位置記憶」區塊）。
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      expect(
        prefsManager.savedReadingPositionCalls.last.key,
        'b_jump_then_navigate',
      );
      expect(
        prefsManager.savedReadingPositionCalls.last.value.pdfPageIndex,
        3,
        reason: 'dispose() 應寫入使用者實際翻到的頁碼（3），而非跳轉目標'
            '（2）或跳轉前資料庫既有的舊進度（4）——checkpoint 寫入行為與'
            '一般開書完全同構，不因為曾經是搜尋跳轉而有任何殘留特殊狀態。',
      );
    });

    testWidgets(
        'PDF：跳轉後使用者未曾翻頁即離開，dispose() 會把跳轉位置存為新進度'
        '（審查意見 I-2：這是 spec.md §6 已明確權衡並接受的簡化，本測試'
        '的目的是把這個已知行為鎖進測試，避免無測試覆蓋的隱性行為，'
        '不代表本計畫判定它是理想行為——見本計畫 Global Constraints）',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        readingPositionByBookId: {
          'b_jump_immediate_exit': const ReadingPosition(pdfPageIndex: 49),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_jump_immediate_exit',
            prefsManager: prefsManager,
            initialJumpTarget: const ReaderJumpTarget(pdfPageIndex: 2),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 模擬原生端回報「目前顯示跳轉目標頁碼」，這是開書當下的正常事件
      // （不代表使用者主動翻頁）——onPageChanged 是原生端每次頁面確實
      // 顯示變更時都會回報，不區分「開書自動定位」與「使用者手動翻頁」
      // 兩種來源，這正是本測試要記錄的既有限制本身。
      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 2, totalPages: 5));
      await tester.pump();

      // 使用者未曾翻頁即離開閱讀畫面。
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      expect(
        prefsManager.savedReadingPositionCalls.last.value.pdfPageIndex,
        2,
        reason: 'checkpoint 只反映「畫面目前顯示的位置」，不區分該位置是'
            '使用者主動翻頁到的，還是搜尋跳轉開書當下就顯示的——這代表'
            '使用者跳轉前的舊進度（49）會被覆蓋成跳轉目標（2）。spec.md '
            '§6 已明確記錄「不需要額外的『使用者是否已產生主動互動』'
            '判斷……予以簡化」，本計畫依此設計，不在這裡另外實作追蹤'
            '邏輯；若要改變這個行為需要回頭修訂 spec.md §6 本身。',
      );
    });
  });
```

- [ ] **Step 8：執行測試，確認因 `initialJumpTarget` 尚不存在而失敗**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: FAIL（`no parameter named 'initialJumpTarget'`）

- [ ] **Step 9：`ReaderScreen` 新增 `initialJumpTarget` 建構參數**

在 `app/lib/screens/reader_screen.dart`，於 import 區塊新增（緊接在既有 `import '../reader/reader_console_log.dart';` 之後）：

```dart
import '../reader/reader_jump_target.dart';
```

找到（`ReaderScreen` 欄位宣告與建構子）：

```dart
  final ReaderActivityTracker? readerActivityTracker;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.bookTitle = '未知書籍',
    this.bookAuthor,
    this.bookProgress = 0.0,
    this.isFixedLayout,
    this.libraryRepository,
    this.customFontsRepository,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
    this.syncCheckpointTrigger,
    this.ttsProvider,
    this.ttsAudioHandler,
    this.ttsAudioFocusSource,
    this.isEinkMode = false,
    this.readerActivityTracker,
  });
```

取代為：

```dart
  final ReaderActivityTracker? readerActivityTracker;

  /// 全庫搜尋跳轉目標（epic-10-search Issue 5，spec.md §6）：非 `null`
  /// 時，開書當下傳給底層 View 的初始定位參數改用本欄位（優先權高於
  /// 資料庫既有 `lastPosition`），除此之外不影響任何後續行為——後續翻頁
  /// /checkpoint 寫入與一般開書完全同構，不新增任何「暫停進度儲存」旗標
  /// （見 `_maybeShowSearchJumpHighlight()` 文件註解的完整理由）。刻意為
  /// 可選參數——比照 `readerActivityTracker` 既有慣例，未提供時零回歸。
  final ReaderJumpTarget? initialJumpTarget;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.bookTitle = '未知書籍',
    this.bookAuthor,
    this.bookProgress = 0.0,
    this.isFixedLayout,
    this.libraryRepository,
    this.customFontsRepository,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
    this.syncCheckpointTrigger,
    this.ttsProvider,
    this.ttsAudioHandler,
    this.ttsAudioFocusSource,
    this.isEinkMode = false,
    this.readerActivityTracker,
    this.initialJumpTarget,
  });
```

找到（`_buildNativeView()` 的 `FoliateReaderView` 建構，`initialLocatorJson` 那一行——**審查修正 M-1**：原計畫誤寫成 `_buildBody()`，實際上 `_buildBody()`／`_buildNativeView()` 是兩個不同方法，`FoliateReaderView`/`PdfReaderView` 的實例化在後者）：

```dart
          initialLocatorJson: _initialPosition?.epubLocatorJson,
```

取代為：

```dart
          // epic-10-search Issue 5：initialJumpTarget 存在時優先權高於
          // 資料庫既有 lastPosition（spec.md §6），僅此一處決策點，其餘
          // 行為與一般開書完全同構。
          initialLocatorJson:
              widget.initialJumpTarget?.cfi ?? _initialPosition?.epubLocatorJson,
```

找到（`_buildNativeView()` 的 `PdfReaderView` 建構，`initialPageIndex` 那一行）：

```dart
          initialPageIndex: _initialPosition?.pdfPageIndex,
```

取代為：

```dart
          // epic-10-search Issue 5：理由同上方 FoliateReaderView 分支。
          initialPageIndex: widget.initialJumpTarget?.pdfPageIndex ??
              _initialPosition?.pdfPageIndex,
```

- [ ] **Step 10：執行測試，確認全數通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全套既有測試＋本 Task 新增 5 個測試皆通過，無回歸）

- [ ] **Step 11：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 12：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(search): ReaderScreen 新增 initialJumpTarget 覆寫初始定位（Issue 5）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B86LmxdxNXsUcepHoYjhmX
EOF
)"
```

---

### Task 2：PDF 暫態高亮（`pdf_reader_view.dart`）

**Files：**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Test: `app/test/reader/pdf_reader_view_jump_highlight_test.dart`

**Interfaces：**
- Consumes：既有 `PercentRect`、`_buildProcessedOverlay()`／`originalToCropRelativePercent()` 既有裁切換算、`ElinkTokens.highlightGreen`。
- Produces：
  ```dart
  static void showTemporaryHighlight(
    GlobalKey<State<PdfReaderView>> key,
    int pageIndex,
    PercentRect rect,
  );
  static void clearTemporaryHighlight(GlobalKey<State<PdfReaderView>> key);
  ```
  供 Task 4 的 `ReaderScreen` 呼叫；渲染出的 widget 帶 `Key('pdf_reader_jump_highlight_$pageIndex')`。

- [ ] **Step 1：寫一組會失敗的測試**

建立 `app/test/reader/pdf_reader_view_jump_highlight_test.dart`：

```dart
// app/test/reader/pdf_reader_view_jump_highlight_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import '../support/pump_until_pdf_ready.dart';

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('showTemporaryHighlight 後畫面渲染出對應頁碼的暫態高亮 widget', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.showTemporaryHighlight(
      key,
      0,
      const PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('pdf_reader_jump_highlight_0')),
      findsOneWidget,
    );
  });

  testWidgets('clearTemporaryHighlight 後高亮 widget 從畫面消失', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.showTemporaryHighlight(
      key,
      0,
      const PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('pdf_reader_jump_highlight_0')),
      findsOneWidget,
    );

    PdfReaderView.clearTemporaryHighlight(key);
    await tester.pump();
    expect(find.byKey(const Key('pdf_reader_jump_highlight_0')), findsNothing);
  });

  testWidgets('高亮只在對應的 pageIndex 顯示，其他頁不受影響', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.showTemporaryHighlight(
      key,
      1,
      const PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
    );
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_jump_highlight_0')), findsNothing);
  });

  testWidgets(
      'State 尚未掛載時，showTemporaryHighlight／clearTemporaryHighlight 皆靜默忽略',
      (tester) async {
    final orphanKey = GlobalKey<State<PdfReaderView>>();
    expect(
      () => PdfReaderView.showTemporaryHighlight(
        orphanKey,
        0,
        const PercentRect(left: 0, top: 0, right: 1, bottom: 1),
      ),
      returnsNormally,
    );
    expect(
      () => PdfReaderView.clearTemporaryHighlight(orphanKey),
      returnsNormally,
    );
  });
}
```

- [ ] **Step 2：執行測試，確認因靜態方法不存在而失敗**

Run: `flutter test test/reader/pdf_reader_view_jump_highlight_test.dart`
Expected: FAIL（`showTemporaryHighlight isn't defined`）

- [ ] **Step 3：`pdf_reader_view.dart` 新增暫態高亮狀態與靜態方法**

找到（`setSearchHighlights` 靜態方法區塊，緊接在其後）：

```dart
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

取代為：

```dart
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

  /// 顯示搜尋跳轉的暫態高亮（epic-10-search Issue 5，spec.md §6）：
  /// [pageIndex] 為 0-indexed 目標頁碼，[rect] 為頁內精確座標。全程只會有
  /// 一個暫態高亮存在（與 [setSearchHighlights] 可能同時存在多筆符合
  /// 結果的既有 PDF 內文搜尋是完全獨立的概念，見本計畫 Global
  /// Constraints）。生命週期由呼叫端（[ReaderScreen]）的 Dart 端 Timer
  /// 主導，本方法本身不會自動清除，需搭配 [clearTemporaryHighlight]
  /// 呼叫。[key] 對應的 State 若尚未掛載，靜默忽略。
  static void showTemporaryHighlight(
    GlobalKey<State<PdfReaderView>> key,
    int pageIndex,
    PercentRect rect,
  ) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._setJumpHighlight(pageIndex, rect);
    }
  }

  /// 清除目前顯示中的搜尋跳轉暫態高亮（若有）。[key] 對應的 State 若尚未
  /// 掛載，靜默忽略。
  static void clearTemporaryHighlight(GlobalKey<State<PdfReaderView>> key) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._setJumpHighlight(null, null);
    }
  }
```

找到（`_setSearchHighlights` 私有方法本體，緊接在其後新增內部狀態與方法）：

```dart
  void _setSearchHighlights(List<PdfSearchMatch> matches, int? currentIndex) {
    setState(() {
      _searchMatches = matches;
      _currentSearchMatchIndex = currentIndex;
    });
  }
```

取代為：

```dart
  void _setSearchHighlights(List<PdfSearchMatch> matches, int? currentIndex) {
    setState(() {
      _searchMatches = matches;
      _currentSearchMatchIndex = currentIndex;
    });
  }

  // epic-10-search Issue 5：搜尋跳轉的暫態高亮，全程只會有一個存在。
  int? _jumpHighlightPageIndex;
  PercentRect? _jumpHighlightRect;

  // 【審查修正 M-3】加上 mounted 防護——雖然既有 _setSearchHighlights()
  // 沒有這道防護（呼叫鏈全程同步、key.currentState 非 null 已隱含當下
  // 仍是 mounted，理論上不需要），但 _setAnnotations() 已有這個慣例，
  // 補上不影響行為、多一層保險。
  void _setJumpHighlight(int? pageIndex, PercentRect? rect) {
    if (!mounted) return;
    setState(() {
      _jumpHighlightPageIndex = pageIndex;
      _jumpHighlightRect = rect;
    });
  }
```

- [ ] **Step 4：`_buildProcessedOverlay()` 新增暫態高亮的疊加渲染**

找到：

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

    widgets.add(_buildSelectionGestureLayer(pageIndex, pageRectInViewer));
```

取代為：

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

    // 渲染搜尋跳轉暫態高亮（epic-10-search Issue 5）。
    if (_jumpHighlightPageIndex == pageIndex && _jumpHighlightRect != null) {
      final visibleRect = _cropEnabled
          ? originalToCropRelativePercent(
              rect: _jumpHighlightRect!, cropRect: widget.pdfCropRect)
          : _jumpHighlightRect;
      if (visibleRect != null) {
        widgets.add(_buildJumpHighlightWidget(
          pageIndex,
          visibleRect,
          pageRectInViewer.size,
        ));
      }
    }

    widgets.add(_buildSelectionGestureLayer(pageIndex, pageRectInViewer));
```

- [ ] **Step 5：新增 `_buildJumpHighlightWidget()`**

找到 `_buildSearchHighlightWidget()` 方法本體結尾的 `}`（該方法定義區塊結束處），在其後新增：

```dart
  /// 搜尋跳轉暫態高亮的視覺樣式（epic-10-search Issue 5）：比照
  /// [_buildSearchHighlightWidget] 的 `isCurrent` 樣式（半透明色塊＋外框）
  /// ——兩者概念相同，都是「標示出目前應注意的文字位置」，差別只在生命
  /// 週期（本高亮 3 秒後自動消失，PDF 內文搜尋符合結果由使用者手動關閉
  /// 搜尋面板才消失）；刻意不共用程式碼，因為兩者的資料來源
  /// （[_jumpHighlightRect] vs [_searchMatches]）完全獨立，由不同呼叫端
  /// （[ReaderScreen] vs `PdfSearchPanel`）驅動。
  Widget _buildJumpHighlightWidget(
    int pageIndex,
    PercentRect visibleRect,
    Size areaSize,
  ) {
    final rect = Rect.fromLTRB(
      visibleRect.left * areaSize.width,
      visibleRect.top * areaSize.height,
      visibleRect.right * areaSize.width,
      visibleRect.bottom * areaSize.height,
    );
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fromRect(
      key: Key('pdf_reader_jump_highlight_$pageIndex'),
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.highlightGreen.withValues(alpha: 0.4),
          border: Border.all(color: colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }
```

- [ ] **Step 6：執行測試，確認全數通過**

Run: `flutter test test/reader/pdf_reader_view_jump_highlight_test.dart`
Expected: PASS（全部 4 個測試）

- [ ] **Step 7：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_jump_highlight_test.dart
git commit -m "$(cat <<'EOF'
feat(search): PdfReaderView 新增搜尋跳轉暫態高亮（Issue 5）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B86LmxdxNXsUcepHoYjhmX
EOF
)"
```

---

### Task 3：Foliate 暫態高亮（`main.js`＋`foliate_reader_view.dart`）

**Files：**
- Modify: `app/android/app/src/main/assets/foliate/main.js`
- Modify: `app/lib/reader/foliate_reader_view.dart`
- Test: `app/test/reader/foliate_reader_view_test.dart`

**Interfaces：**
- Consumes：既有 `view.addAnnotation()`/`view.deleteAnnotation()`；`view.js`（釘定 vendored 檔案）既有的 `SEARCH_PREFIX = 'foliate-search:'` 常數與其固定的 `Overlayer.outline` 渲染路徑（見本計畫 Global Constraints「Foliate 暫態高亮改用 view.js 既有的 foliate-search: 前綴」的完整查證與理由——**這是本 Task 與原計畫第一版差異最大的地方**，不再自訂顏色/直排橫排/E-Ink 樣式）。
- Produces：
  ```dart
  static void showSearchHighlight(
    GlobalKey<State<FoliateReaderView>> key,
    String cfi,
  );
  static void clearSearchHighlight(GlobalKey<State<FoliateReaderView>> key);
  ```
  供 Task 4 的 `ReaderScreen` 呼叫；**不再有** `vertical`/`einkMode` 參數（`view.js` 對 `foliate-search:` 前綴的處理不會發送 `draw-annotation` 事件，這兩個參數傳了也不會被使用，故不定義）。

**本 Task 的 TDD 紅燈只涵蓋 Step 1-2（main.js regression guard，可在實作前先失敗）**——比照本計畫 Global Constraints「誠實測試邊界」說明，`FoliateReaderView` 的 JS 呼叫在 `flutter_test` 環境下無法被攔截斷言，既有 `showTtsHighlight`/`clearTtsHighlight` 兩個靜態方法本身也沒有對應的 Dart 級測試，故 Step 4 的 Dart 端靜態方法新增沒有對應的獨立紅燈步驟（改由 Step 5 與 Task 4 的 `ReaderScreen` widget test 一併涵蓋「wiring 不崩潰」）。

- [ ] **Step 1：寫一組會失敗的測試（main.js regression guard）**

在 `app/test/reader/foliate_reader_view_test.dart`，於既有 `group('main.js 朗讀高亮 regression guard（epic-34-tts-readalong Issue 3，ADR 0026）', () { ... });` 區塊結束的 `});` 之後（緊接在其後，`group('main.js 朗讀段反向查找 regression guard...')` 之前）新增：

```dart
  group('main.js 搜尋跳轉高亮 regression guard（epic-10-search Issue 5，spec.md §6）',
      () {
    late String mainJsSource;
    late String viewJsSource;

    setUpAll(() {
      mainJsSource = File('android/app/src/main/assets/foliate/main.js')
          .readAsStringSync();
      viewJsSource = File('android/app/src/main/assets/foliate/view.js')
          .readAsStringSync();
    });

    test(
        'main.js 的 foliate-search: 前綴字面值與 view.js 既有 SEARCH_PREFIX 常數一致'
        '（規劃階段查證：此前綴是 view.js 這份釘定 vendored 檔案自己既有的保留字，'
        '不是本工單自訂的名稱，見本計畫 Global Constraints）', () {
      expect(
        viewJsSource.contains("const SEARCH_PREFIX = 'foliate-search:'"),
        isTrue,
        reason: '若這行斷言失敗，代表 view.js 這份釘定版本升級後 '
            'SEARCH_PREFIX 的字面值改變了，main.js 下面兩個函式寫死的 '
            "'foliate-search:' 前綴必須同步更新，否則兩者不再是同一個 "
            'key 空間，搜尋跳轉高亮會完全不顯示（view.js 會把它導向一般'
            '劃線/備註的 key 空間，可能覆蓋使用者真實資料，見 Global '
            'Constraints 對這個風險的完整說明）。',
      );
      expect(mainJsSource.contains("'foliate-search:' + cfi"), isTrue,
          reason: 'main.js 內找不到 window.showSearchHighlight——搜尋跳轉'
              '高亮橋接函式缺失。');
    });

    test('window.showSearchHighlight／window.clearSearchHighlight 皆存在，且各自呼叫 view.addAnnotation／view.deleteAnnotation',
        () {
      final showFnIndex =
          mainJsSource.indexOf('window.showSearchHighlight = function');
      final clearFnIndex =
          mainJsSource.indexOf('window.clearSearchHighlight = function');
      expect(showFnIndex, greaterThanOrEqualTo(0),
          reason: 'main.js 內找不到 window.showSearchHighlight。');
      expect(clearFnIndex, greaterThanOrEqualTo(0),
          reason: 'main.js 內找不到 window.clearSearchHighlight——搜尋跳轉'
              '高亮清除橋接函式缺失。');
      final addCallIndex =
          mainJsSource.indexOf('view.addAnnotation(', showFnIndex);
      expect(addCallIndex, greaterThanOrEqualTo(0),
          reason: 'window.showSearchHighlight 內找不到 view.addAnnotation '
              '呼叫。');
      final deleteCallIndex =
          mainJsSource.indexOf('view.deleteAnnotation(', clearFnIndex);
      expect(deleteCallIndex, greaterThanOrEqualTo(0),
          reason: 'window.clearSearchHighlight 內找不到 view.deleteAnnotation '
              '呼叫。');
    });

    test(
        'showSearchHighlight／clearSearchHighlight 使用獨立的 currentSearchHighlightValue 變數，不觸及 currentTtsAnnotationValue（單向隔離）',
        () {
      final showFnStart =
          mainJsSource.indexOf('window.showSearchHighlight = function');
      final showFnEnd = mainJsSource.indexOf('\n}', showFnStart);
      final showFnBody = mainJsSource.substring(showFnStart, showFnEnd);
      expect(showFnBody.contains('currentSearchHighlightValue'), isTrue);
      expect(showFnBody.contains('currentTtsAnnotationValue'), isFalse,
          reason: 'showSearchHighlight 不應觸及 currentTtsAnnotationValue，'
              '否則搜尋跳轉高亮與朗讀高亮的生命週期會互相汙染（spec.md '
              '§6）。');

      final clearFnStart =
          mainJsSource.indexOf('window.clearSearchHighlight = function');
      final clearFnEnd = mainJsSource.indexOf('\n}', clearFnStart);
      final clearFnBody = mainJsSource.substring(clearFnStart, clearFnEnd);
      expect(clearFnBody.contains('currentTtsAnnotationValue'), isFalse);
    });

    test(
        'showTtsHighlight／clearTtsHighlight 不觸及 currentSearchHighlightValue（反向隔離，確保雙向皆獨立）',
        () {
      final showTtsStart =
          mainJsSource.indexOf('window.showTtsHighlight = function');
      final showTtsEnd = mainJsSource.indexOf('\n}', showTtsStart);
      expect(
        mainJsSource
            .substring(showTtsStart, showTtsEnd)
            .contains('currentSearchHighlightValue'),
        isFalse,
      );

      final clearTtsStart =
          mainJsSource.indexOf('window.clearTtsHighlight = function');
      final clearTtsEnd = mainJsSource.indexOf('\n}', clearTtsStart);
      expect(
        mainJsSource
            .substring(clearTtsStart, clearTtsEnd)
            .contains('currentSearchHighlightValue'),
        isFalse,
      );
    });
  });
```

- [ ] **Step 2：執行測試，確認因 `main.js`／Dart 端靜態方法尚未新增而失敗**

Run: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: FAIL（`window.showSearchHighlight = function` 等字串在目前 `main.js` 內找不到）

- [ ] **Step 3：`main.js` 新增 `window.showSearchHighlight`/`window.clearSearchHighlight`**

找到：

```js
window.clearTtsHighlight = function () {
  if (!currentTtsAnnotationValue) return
  view.deleteAnnotation({ value: currentTtsAnnotationValue })
  currentTtsAnnotationValue = null
}
```

取代為：

```js
window.clearTtsHighlight = function () {
  if (!currentTtsAnnotationValue) return
  view.deleteAnnotation({ value: currentTtsAnnotationValue })
  currentTtsAnnotationValue = null
}

/**
 * 搜尋跳轉暫態高亮（epic-10-search Issue 5，spec.md §6）。
 *
 * 【規劃階段查證，推翻原計畫「自訂顏色/直排橫排/E-Ink 樣式」設計】
 * foliate-search: 不是本工單自訂、尚未使用的保留前綴，而是 view.js
 * （釘定 vendored 檔案）自己既有的 SEARCH_PREFIX 常數：
 * addAnnotation() 對這個前綴的處理是無條件呼叫
 * overlayer.add(value, range, Overlayer.outline)，**不帶任何 options、
 * 也不發送 draw-annotation 事件**，與 foliate-note:（TTS 朗讀高亮，會
 * 發送 draw-annotation 事件把繪製決定權交還給下方監聽器）完全不同，
 * 因此無法從這裡客製化顏色/直排橫排/E-Ink 樣式——Overlayer.outline()
 * 在沒有收到 options 時的預設值固定是紅色、3px 外框（overlayer.js
 * Overlayer.outline() 原始碼），這是 view.js 內建、無法客製化的樣式。
 *
 * 改用 foliate-note:（TTS 既有 key 空間）或裸 cfi（劃線/備註既有 key
 * 空間）雖然可以透過 draw-annotation 事件客製化樣式，但會與 TTS 播放
 * 狀態或使用者真實劃線/備註資料共用同一個 key，彼此的 show/clear 呼叫
 * 會互相覆蓋（spec.md §6 明文要求要避免這種汙染）；修改 view.js 本身
 * 讓 SEARCH_PREFIX 也發送 draw-annotation 事件則違反 ADR 0011「不修改
 * 任何 vendored 檔案」。三者相比，直接沿用 foliate-search: 既有的固定
 * 紅色外框樣式是風險最低的選擇——**已知且接受的代價**：Foliate 端暫態
 * 高亮固定為紅色外框、不隨 E-Ink 模式或直排/橫排調整，與 PDF 端可自訂
 * 的綠色填色樣式不一致，見本計畫 Global Constraints 完整說明。
 */
let currentSearchHighlightValue = null

window.showSearchHighlight = function (cfi) {
  if (currentSearchHighlightValue) {
    view.deleteAnnotation({ value: currentSearchHighlightValue })
  }
  currentSearchHighlightValue = 'foliate-search:' + cfi
  view.addAnnotation({ value: currentSearchHighlightValue })
}

window.clearSearchHighlight = function () {
  if (!currentSearchHighlightValue) return
  view.deleteAnnotation({ value: currentSearchHighlightValue })
  currentSearchHighlightValue = null
}
```

- [ ] **Step 4：`foliate_reader_view.dart` 新增對應的 Dart 端靜態方法**

找到：

```dart
  /// 清除目前的朗讀高亮（epic-34-tts-readalong Issue 3）。朗讀段切換時不
  /// 需要呼叫端先呼叫這個方法再呼叫 [showTtsHighlight]——main.js
  /// window.showTtsHighlight() 內部已處理「顯示新的之前先清除舊的」，本
  /// 方法只在播放結束（不再有下一段可顯示）時由 [ReaderScreen] 呼叫。
  static void clearTtsHighlight(GlobalKey<State<FoliateReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.clearTtsHighlight()');
    }
  }
```

取代為：

```dart
  /// 清除目前的朗讀高亮（epic-34-tts-readalong Issue 3）。朗讀段切換時不
  /// 需要呼叫端先呼叫這個方法再呼叫 [showTtsHighlight]——main.js
  /// window.showTtsHighlight() 內部已處理「顯示新的之前先清除舊的」，本
  /// 方法只在播放結束（不再有下一段可顯示）時由 [ReaderScreen] 呼叫。
  static void clearTtsHighlight(GlobalKey<State<FoliateReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.clearTtsHighlight()');
    }
  }

  /// 顯示搜尋跳轉的暫態高亮（epic-10-search Issue 5，spec.md §6）：呼叫
  /// main.js window.showSearchHighlight()，底層走 view.js 既有的
  /// `foliate-search:` 前綴（固定紅色外框樣式，無法客製化顏色/直排橫排/
  /// E-Ink 樣式，見 main.js 該函式上方的完整查證註解與本計畫 Global
  /// Constraints），與 [showTtsHighlight] 使用的 `foliate-note:` 完全
  /// 獨立的 key 空間——兩者的生命週期與觸發時機互不相干，混用會互相
  /// 汙染。
  static void showSearchHighlight(
    GlobalKey<State<FoliateReaderView>> key,
    String cfi,
  ) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.showSearchHighlight(${jsonEncode(cfi)})');
    }
  }

  /// 清除目前的搜尋跳轉暫態高亮，由 [ReaderScreen] 的 Dart 端 Timer
  /// （3 秒）或使用者提前翻頁/點擊畫面時呼叫。
  static void clearSearchHighlight(GlobalKey<State<FoliateReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.clearSearchHighlight()');
    }
  }
```

- [ ] **Step 5：執行測試，確認全數通過**

Run: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: PASS（既有測試＋本 Task 新增 4 個測試皆通過）

- [ ] **Step 6：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js app/lib/reader/foliate_reader_view.dart app/test/reader/foliate_reader_view_test.dart
git commit -m "$(cat <<'EOF'
feat(search): Foliate 新增搜尋跳轉暫態高亮 window.showSearchHighlight（Issue 5）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B86LmxdxNXsUcepHoYjhmX
EOF
)"
```

---

### Task 4：`ReaderScreen` 暫態高亮生命週期（Dart 端 Timer 主導）

**Files：**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `widget.initialJumpTarget`；Task 2 的 `PdfReaderView.showTemporaryHighlight`/`clearTemporaryHighlight`；Task 3 的 `FoliateReaderView.showSearchHighlight`/`clearSearchHighlight`。
- Produces：`_ReaderScreenState` 私有方法 `_maybeShowSearchJumpHighlight()`（供 `_handlePageRendered()` 呼叫）／`_clearSearchJumpHighlight()`（供 `_handleZoneAction()`／`dispose()` 呼叫），無新公開 API。

- [ ] **Step 1：寫一組會失敗的測試**

在 `app/test/screens/reader_screen_test.dart`，於 Task 1 新增的 `group('epic-10-search Issue 5：initialJumpTarget 覆寫初始定位', ...)` 區塊之後（緊接在其 `});` 後）新增：

```dart
  group('epic-10-search Issue 5：搜尋跳轉暫態高亮生命週期', () {
    testWidgets('PDF：抵達 initialJumpTarget 後顯示暫態高亮，3 秒後自動清除',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_jump_highlight_auto_clear',
            prefsManager: FakeReaderPrefsManager(),
            initialJumpTarget: const ReaderJumpTarget(
              pdfPageIndex: 0,
              pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      // 【審查修正 C-1】不能用不帶 condition 的 pumpUntilPdfReady(tester)
      // ——該 helper 沒有 condition 時會無條件跑滿 30 輪、每輪
      // pump(100ms)，在 fake-async 環境下等同一次性推進 3,000ms 的假時鐘，
      // 剛好等於本測試要驗證的 3 秒暫態高亮計時器時長，會讓計時器在下面
      // 第一個 expect() 執行「之前」就已經到期並清除高亮，導致
      // findsOneWidget 斷言必定失敗（誤判成通過的反而是巧合）。改為傳入
      // condition，讓 pumpUntilPdfReady 一偵測到高亮 widget 出現就立刻
      // 返回，把「等待 3 秒計時器到期」這件事完全交給下面明確的
      // tester.pump(const Duration(seconds: 3))。
      await pumpUntilPdfReady(
        tester,
        condition: () =>
            find.byKey(const Key('pdf_reader_jump_highlight_0')).evaluate().isNotEmpty,
      );

      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_0')),
        findsOneWidget,
        reason: '開書抵達跳轉目標後應立即顯示暫態高亮',
      );

      await tester.pump(const Duration(seconds: 3));
      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_0')),
        findsNothing,
        reason: '3 秒後應自動清除',
      );
    });

    testWidgets('PDF：使用者提前點擊畫面（_handleZoneAction）時立即清除，不等待 3 秒',
        (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_jump_highlight_early_clear',
            prefsManager: FakeReaderPrefsManager(),
            initialJumpTarget: const ReaderJumpTarget(
              pdfPageIndex: 0,
              pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      // 【審查修正 C-1】理由同上一個測試——必須帶 condition，否則
      // pumpUntilPdfReady(tester) 累積推進的 3,000ms 假時鐘會讓 3 秒計時
      // 器在下面斷言之前就先到期，讓這個測試即使 _handleZoneAction 的
      // 提前清除邏輯根本沒有執行也會「意外看似通過」。
      await pumpUntilPdfReady(
        tester,
        condition: () =>
            find.byKey(const Key('pdf_reader_jump_highlight_0')).evaluate().isNotEmpty,
      );

      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_0')),
        findsOneWidget,
      );

      // 用 ZoneAction.menu（單純點擊畫面，不換頁）驗證清除邏輯本身，
      // 避免與「換頁導致頁面本身不再可見」的效果混淆（見本計畫 Global
      // Constraints 對測試設計的說明）。
      ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
      await tester.pump();

      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_0')),
        findsNothing,
        reason: '使用者點擊畫面應立即清除，不需要等待 3 秒計時器到期',
      );
    });

    testWidgets(
        'PDF：initialJumpTarget 只有 pdfPageIndex、沒有 pdfRect 時，正常跳轉頁面但不顯示暫態高亮',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_jump_no_rect',
            prefsManager: FakeReaderPrefsManager(),
            initialJumpTarget: const ReaderJumpTarget(pdfPageIndex: 0),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      expect(pdfView.initialPageIndex, 0);
      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_0')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Foliate：initialJumpTarget 帶 cfi 時，開書流程與暫態高亮 wiring 皆不崩潰（誠實測試邊界，見本計畫 Global Constraints）',
        (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_jump_epub_highlight',
            prefsManager: FakeReaderPrefsManager(),
            initialJumpTarget:
                const ReaderJumpTarget(cfi: 'epubcfi(/6/2!/4/2)'),
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
      await tester.pump();

      // 3 秒自動清除路徑。
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);

      // 提前點擊清除路徑（此時計時器已到期，_clearSearchJumpHighlight
      // 內部的早退保護應能安全處理重複呼叫）。
      ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('initialJumpTarget 為 null 時，_handlePageRendered 不觸發任何暫態高亮',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_no_jump_no_highlight',
            prefsManager: FakeReaderPrefsManager(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>)
                  .value
                  .startsWith('pdf_reader_jump_highlight_'),
        ),
        findsNothing,
      );
    });
  });
```

- [ ] **Step 2：執行測試，確認因暫態高亮觸發邏輯不存在而失敗**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: FAIL（新增的暫態高亮測試找不到 `pdf_reader_jump_highlight_0`）

- [ ] **Step 3：`ReaderScreen` 新增 Timer 欄位**

找到：

```dart
  Timer? _openBookTimeoutTimer;

  @override
  void initState() {
```

取代為：

```dart
  Timer? _openBookTimeoutTimer;

  /// 搜尋跳轉暫態高亮 3 秒生命週期計時器（epic-10-search Issue 5，
  /// spec.md §6）。非 `null` 代表目前有顯示中的暫態高亮，
  /// [_handleZoneAction] 於任何翻頁/點擊動作發生時會提前呼叫
  /// [_clearSearchJumpHighlight]，取 3 秒與提前清除兩者較早發生者。刻意
  /// 使用裸 `Timer`（不引入 `package:clock`）——理由見本計畫 Global
  /// Constraints。
  Timer? _searchJumpHighlightTimer;

  /// 避免 [_handlePageRendered] 在極端情況下被呼叫超過一次時重複觸發
  /// 暫態高亮、重新啟動 3 秒計時——`initialJumpTarget` 只在開書當下這一
  /// 次性場景生效（spec.md §6）。
  bool _searchJumpHighlightTriggered = false;

  @override
  void initState() {
```

- [ ] **Step 4：`dispose()` 新增計時器清理**

找到：

```dart
  void dispose() {
    widget.readerActivityTracker?.markReaderClosed();
    _syncCheckpointTimer?.cancel();
    _openBookTimeoutTimer?.cancel();
    _ttsSleepTimer?.cancel();
```

取代為：

```dart
  void dispose() {
    widget.readerActivityTracker?.markReaderClosed();
    _syncCheckpointTimer?.cancel();
    _openBookTimeoutTimer?.cancel();
    _searchJumpHighlightTimer?.cancel();
    _ttsSleepTimer?.cancel();
```

- [ ] **Step 5：`_handlePageRendered()` 觸發暫態高亮**

找到（`_handlePageRendered()` 方法本體結尾）：

```dart
    if (detectBookFormat(widget.filePath) == BookFormat.pdf && !_pdfTocLoaded) {
      _pdfTocLoaded = true;
      PdfReaderView.loadTableOfContents(_pdfReaderViewKey).then((items) {
        if (!mounted) return;
        setState(() => _pdfTocEntries = items);
      });
      // epic-24-pdf-engine-rebuild Issue 8（審查意見 Important 1）：PDF
      // 開書成功時一併載入書籤快取，讓 Step 9 新增的書籤 FAB 星號圖示在
      // 使用者尚未手動 toggle／開過筆記面板前就能正確反映既有書籤狀態。
      // 借用既有 _pdfTocLoaded 旗標的去重保護（本區塊本來就只會在單一
      // PDF 開書流程中執行一次），不另外新增專屬旗標。
      // _loadFxlBookmarks() 內部已對 widget.bookmarksRepository == null
      // 做早退防呆，此處不需額外判斷。
      _loadFxlBookmarks();
    }
  }
```

取代為：

```dart
    if (detectBookFormat(widget.filePath) == BookFormat.pdf && !_pdfTocLoaded) {
      _pdfTocLoaded = true;
      PdfReaderView.loadTableOfContents(_pdfReaderViewKey).then((items) {
        if (!mounted) return;
        setState(() => _pdfTocEntries = items);
      });
      // epic-24-pdf-engine-rebuild Issue 8（審查意見 Important 1）：PDF
      // 開書成功時一併載入書籤快取，讓 Step 9 新增的書籤 FAB 星號圖示在
      // 使用者尚未手動 toggle／開過筆記面板前就能正確反映既有書籤狀態。
      // 借用既有 _pdfTocLoaded 旗標的去重保護（本區塊本來就只會在單一
      // PDF 開書流程中執行一次），不另外新增專屬旗標。
      // _loadFxlBookmarks() 內部已對 widget.bookmarksRepository == null
      // 做早退防呆，此處不需額外判斷。
      _loadFxlBookmarks();
    }
    // epic-10-search Issue 5：書籍成功渲染（含 PDF／Foliate，兩者皆走
    // onPageRendered）即代表已抵達 initialJumpTarget 指定的目標位置
    // （initialLocatorJson/initialPageIndex 已在建構時套用，見 Task 1），
    // 此時觸發暫態高亮。
    _maybeShowSearchJumpHighlight();
  }

  /// 抵達 `initialJumpTarget` 目標位置後觸發暫態高亮（epic-10-search
  /// Issue 5，spec.md §6）：[widget.initialJumpTarget] 為 `null`（一般
  /// 開書，非搜尋跳轉而來）時完全不動作，零回歸。PDF 需要
  /// `pdfPageIndex`／`pdfRect` 皆存在才顯示（缺 `pdfRect` 時仍已透過
  /// `initialPageIndex` 正常跳轉頁面，只是沒有精確座標可畫暫態高亮框，見
  /// `ReaderJumpTarget` 文件註解）；Foliate 需要 `cfi` 存在。
  void _maybeShowSearchJumpHighlight() {
    if (_searchJumpHighlightTriggered) return;
    final jumpTarget = widget.initialJumpTarget;
    if (jumpTarget == null) return;
    _searchJumpHighlightTriggered = true;
    final format = detectBookFormat(widget.filePath);
    if (format == BookFormat.pdf) {
      final pageIndex = jumpTarget.pdfPageIndex;
      final rect = jumpTarget.pdfRect;
      if (pageIndex == null || rect == null) return;
      PdfReaderView.showTemporaryHighlight(_pdfReaderViewKey, pageIndex, rect);
    } else if (isFoliateFormat(format)) {
      final cfi = jumpTarget.cfi;
      if (cfi == null) return;
      FoliateReaderView.showSearchHighlight(_foliateEpubReaderViewKey, cfi);
    } else {
      return;
    }
    _searchJumpHighlightTimer?.cancel();
    _searchJumpHighlightTimer = Timer(
      const Duration(seconds: 3),
      _clearSearchJumpHighlight,
    );
  }

  /// 清除搜尋跳轉暫態高亮：3 秒計時到期，或 [_handleZoneAction] 偵測到
  /// 使用者提前翻頁/點擊畫面時呼叫，取兩者較早發生者（spec.md §6）。
  /// [_searchJumpHighlightTimer] 為 `null`（尚未顯示過或已清除過）時安全
  /// 提前 return，可重複呼叫（[_handleZoneAction] 對每一次動作都無條件
  /// 呼叫本方法，不會判斷目前是否真的有顯示中的高亮）。
  void _clearSearchJumpHighlight() {
    if (_searchJumpHighlightTimer == null) return;
    _searchJumpHighlightTimer?.cancel();
    _searchJumpHighlightTimer = null;
    final format = detectBookFormat(widget.filePath);
    if (format == BookFormat.pdf) {
      PdfReaderView.clearTemporaryHighlight(_pdfReaderViewKey);
    } else if (isFoliateFormat(format)) {
      FoliateReaderView.clearSearchHighlight(_foliateEpubReaderViewKey);
    }
  }
```

- [ ] **Step 6：`_handleZoneAction()` 統一入口新增提前清除呼叫**

找到：

```dart
  void _handleZoneAction(ZoneAction action) {
    final format = detectBookFormat(widget.filePath);
    switch (action) {
```

取代為：

```dart
  void _handleZoneAction(ZoneAction action) {
    // epic-10-search Issue 5：使用者翻頁或點擊畫面（本方法涵蓋 3×3 熱區
    // 全部四種動作＋音量鍵翻頁，見 spec.md §6「既有的翻頁/點擊處理路徑
    // 一併呼叫清除」）一律提前清除搜尋跳轉暫態高亮，取 3 秒計時與提前
    // 清除兩者較早發生者。無條件呼叫——_clearSearchJumpHighlight()
    // 內部已對「目前根本沒有顯示中的高亮」做早退保護，重複呼叫安全。
    _clearSearchJumpHighlight();
    final format = detectBookFormat(widget.filePath);
    switch (action) {
```

- [ ] **Step 7：執行測試，確認全數通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全套既有測試＋本 Task 新增 5 個測試皆通過，無回歸）

- [ ] **Step 8：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(search): ReaderScreen 新增搜尋跳轉暫態高亮生命週期（Issue 5）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B86LmxdxNXsUcepHoYjhmX
EOF
)"
```

---

### Task 5：`LibrarySearchScreen` 帶入跳轉目標＋收尾驗證

**Files：**
- Modify: `app/lib/screens/library_search_screen.dart`
- Test: `app/test/screens/library_search_screen_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `ReaderJumpTarget.fromContentLocator()`；Task 4 完成後的 `ReaderScreen.initialJumpTarget`。
- Produces：無新公開 API，`_openBook()` 新增可選具名參數 `jumpTarget`。

- [ ] **Step 1：寫一組會失敗的測試**

在 `app/test/screens/library_search_screen_test.dart`，於 import 區塊新增：

```dart
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
```

找到（`_testBook` 輔助函式）：

```dart
Book _testBook({required String id, String title = '測試書', String? author}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
    filePath: 'content://example/$id.epub',
    source: BookSource.local,
    groupName: BookGroup.uncategorized,
    createTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}
```

取代為：

```dart
Book _testBook({
  required String id,
  String title = '測試書',
  String? author,
  BookFileFormat format = BookFileFormat.epub,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: format,
    filePath: 'content://example/$id.epub',
    source: BookSource.local,
    groupName: BookGroup.uncategorized,
    createTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}
```

在檔案內任一位置（建議緊接在既有「點擊內容匹配片段會開啟 ReaderScreen」測試之後）新增：

```dart
  testWidgets(
      '點擊內容匹配片段開書時，帶入依 locator 解析出的 ReaderJumpTarget（epic-10-search Issue 5）',
      (tester) async {
    final book = _testBook(id: 'b1', title: '書一');
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: FakeSearchRepository(
          contentResults: [
            BookContentMatches(
              book: book,
              matches: const [
                ContentMatchSnippet(
                  snippet: '含有關鍵字的句子',
                  locator: 'epubcfi(/6/2)',
                ),
              ],
            ),
          ],
        ),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.pdf: true,
            ContentIndexCategory.foliate: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_content_snippet_b1_0')),
    );
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.initialJumpTarget?.cfi, 'epubcfi(/6/2)');
  });

  testWidgets(
      '內容匹配為 PDF 書籍時，帶入依 JSON locator 解析出的頁碼與座標（epic-10-search Issue 5）',
      (tester) async {
    final book = _testBook(id: 'b1', title: 'PDF 書', format: BookFileFormat.pdf);
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '關鍵字',
        searchRepository: FakeSearchRepository(
          contentResults: [
            BookContentMatches(
              book: book,
              matches: const [
                ContentMatchSnippet(
                  snippet: '含有關鍵字的句子',
                  locator:
                      '{"page":2,"rect":{"left":0.1,"top":0.2,"right":0.5,"bottom":0.3}}',
                ),
              ],
            ),
          ],
        ),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.pdf: true,
            ContentIndexCategory.foliate: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_content_snippet_b1_0')),
    );
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.initialJumpTarget?.pdfPageIndex, 2);
    expect(
      readerScreen.initialJumpTarget?.pdfRect,
      const PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
    );
  });

  testWidgets('點擊書名/作者匹配結果開書時，不帶 initialJumpTarget（一般開書路徑，零回歸）',
      (tester) async {
    final book = _testBook(id: 'b1', title: '書一');
    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '書一',
        searchRepository: FakeSearchRepository(titleAuthorResults: [book]),
        prefsManager: FakeReaderPrefsManager(),
        libraryRepository: FakeLibraryRepository(),
      )),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_search_title_author_result_b1')),
    );
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.initialJumpTarget, isNull);
  });
```

- [ ] **Step 2：執行測試，確認因 `_openBook` 尚未支援 `jumpTarget` 而失敗**

Run: `flutter test test/screens/library_search_screen_test.dart`
Expected: FAIL（`initialJumpTarget` 恆為 `null`，前兩個新測試斷言失敗）

- [ ] **Step 3：`library_search_screen.dart` 新增 `jumpTarget` 參數並帶入內容匹配片段**

在 import 區塊新增：

```dart
import '../reader/reader_jump_target.dart';
```

找到：

```dart
  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          filePath: book.filePath,
          bookId: book.id,
          prefsManager: widget.prefsManager,
          bookmarksRepository:
              widget.readerFeatureRepositories.bookmarksRepository,
          highlightsRepository:
              widget.readerFeatureRepositories.highlightsRepository,
          notesRepository: widget.readerFeatureRepositories.notesRepository,
          bookTitle: book.title,
          bookAuthor: book.author,
          bookProgress: book.progress,
          isFixedLayout: book.isFixedLayout,
          libraryRepository: widget.libraryRepository,
          customFontsRepository:
              widget.readerFeatureRepositories.customFontsRepository,
          layoutPresetRepository:
              widget.readerFeatureRepositories.layoutPresetRepository,
          bookReaderPrefsRepository:
              widget.readerFeatureRepositories.bookReaderPrefsRepository,
          syncCheckpointTrigger: widget.syncDependencies.syncCheckpointTrigger,
          ttsProvider: widget.readerFeatureRepositories.ttsProvider,
          ttsAudioHandler: widget.readerFeatureRepositories.ttsAudioHandler,
          ttsAudioFocusSource:
              widget.readerFeatureRepositories.ttsAudioFocusSource,
          isEinkMode: widget.isEinkMode,
          readerActivityTracker:
              widget.readerFeatureRepositories.readerActivityTracker,
        ),
      ),
    );
  }
```

取代為：

```dart
  void _openBook(Book book, {ReaderJumpTarget? jumpTarget}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          filePath: book.filePath,
          bookId: book.id,
          prefsManager: widget.prefsManager,
          bookmarksRepository:
              widget.readerFeatureRepositories.bookmarksRepository,
          highlightsRepository:
              widget.readerFeatureRepositories.highlightsRepository,
          notesRepository: widget.readerFeatureRepositories.notesRepository,
          bookTitle: book.title,
          bookAuthor: book.author,
          bookProgress: book.progress,
          isFixedLayout: book.isFixedLayout,
          libraryRepository: widget.libraryRepository,
          customFontsRepository:
              widget.readerFeatureRepositories.customFontsRepository,
          layoutPresetRepository:
              widget.readerFeatureRepositories.layoutPresetRepository,
          bookReaderPrefsRepository:
              widget.readerFeatureRepositories.bookReaderPrefsRepository,
          syncCheckpointTrigger: widget.syncDependencies.syncCheckpointTrigger,
          ttsProvider: widget.readerFeatureRepositories.ttsProvider,
          ttsAudioHandler: widget.readerFeatureRepositories.ttsAudioHandler,
          ttsAudioFocusSource:
              widget.readerFeatureRepositories.ttsAudioFocusSource,
          isEinkMode: widget.isEinkMode,
          readerActivityTracker:
              widget.readerFeatureRepositories.readerActivityTracker,
          // epic-10-search Issue 5：只有內容匹配片段的點擊會帶入
          // jumpTarget（見下方 _buildContentGroupCard 呼叫端），書名/作者
          // 匹配結果維持一般開書路徑（jumpTarget 預設 null）。
          initialJumpTarget: jumpTarget,
        ),
      ),
    );
  }
```

找到（內容匹配片段的 `ListTile`）：

```dart
          for (var i = 0; i < group.matches.length; i++)
            ListTile(
              key: Key(
                'library_search_content_snippet_${group.book.id}_$i',
              ),
              dense: true,
              title: Text(group.matches[i].snippet),
              onTap: () => _openBook(group.book),
            ),
```

取代為：

```dart
          for (var i = 0; i < group.matches.length; i++)
            ListTile(
              key: Key(
                'library_search_content_snippet_${group.book.id}_$i',
              ),
              dense: true,
              title: Text(group.matches[i].snippet),
              onTap: () => _openBook(
                group.book,
                jumpTarget: ReaderJumpTarget.fromContentLocator(
                  format: group.book.format,
                  locator: group.matches[i].locator,
                ),
              ),
            ),
```

- [ ] **Step 4：執行測試，確認全數通過**

Run: `flutter test test/screens/library_search_screen_test.dart`
Expected: PASS（既有測試＋本 Task 新增 3 個測試皆通過）

- [ ] **Step 5：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6：跑本次全部異動觸及的測試檔，確認整體沒有回歸**

Run: `flutter test test/reader/reader_jump_target_test.dart test/reader/pdf_reader_view_jump_highlight_test.dart test/reader/foliate_reader_view_test.dart test/screens/reader_screen_test.dart test/screens/library_search_screen_test.dart`
Expected: PASS（本計畫新增與修改的所有測試檔皆通過）

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/library_search_screen.dart app/test/screens/library_search_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(search): LibrarySearchScreen 點擊內容匹配片段時帶入 ReaderJumpTarget（Issue 5）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B86LmxdxNXsUcepHoYjhmX
EOF
)"
```

- [ ] **Step 8：跑本工單所屬 Epic 收尾前的全套測試**

本工單是 Epic 10（全文檢索）依 `issues.md` 依賴圖規劃的最後一個 Issue（Issue 6 為獨立、已完成的相容性缺陷修復），依專案慣例「整張計畫的最後一個 Task 完成時」跑一次完整 `flutter test`：

Run: `flutter test`
Expected: `All tests passed!`（比照 `plan-issue-0.md`／`plan-issue-3.md` 既有收尾慣例；若有與本計畫無關的既有失敗，先確認是否為既有已知問題，非本計畫引入的回歸）

- [ ] **Step 9：（人類／執行者手動）真機或模擬器驗證**

`flutter run` 啟動 App：
1. 進入全庫搜尋畫面（需已啟用全文檢索並完成背景索引，見 Issue 3/4），搜尋一個已知存在於某本 EPUB 書內容中的詞彙。
2. 點擊「內容匹配」區的一則片段，確認真的開書並精確跳轉到該片段所在位置（而非書籍開頭或上次閱讀位置）。
3. 確認畫面上出現約 3 秒的暫態高亮提示，3 秒後自動消失；提前點擊畫面或翻頁應立即讓高亮消失。
4. 確認直排/橫排書籍的暫態高亮皆正確跟隨排版方向顯示（比照既有朗讀高亮的直排/橫排正確性，真機或模擬器皆可）。
5. 對一本已索引的 PDF 重複步驟 1-3，確認頁碼與頁內精確位置皆正確，暫態高亮矩形框住正確的文字範圍。
6. 從跳轉位置開始繼續翻頁閱讀一段時間後離開閱讀畫面，重新開啟同一本書，確認閱讀進度是使用者實際翻到的最新位置（而非搜尋跳轉的原始位置、也不是搜尋跳轉之前的舊進度）——驗證 spec.md §6「不影響原本閱讀進度記錄機制」。

（本 Task 為整個 Epic 10 最後一個 Issue 的最後一個 Task，Step 8 的全套 `flutter test` 已滿足專案「Issue 準備發 PR／合併進 main 前的最終確認」慣例，不需要再另外重跑。）

---

## 自我審查（Self-Review，計畫撰寫者執行，非另一輪審查）

**Spec 覆蓋度：** spec.md §6 逐項對應——(1) `ReaderJumpTarget`（`cfi`／`pdfPageIndex`／`pdfRect`）＋`ReaderScreen.initialJumpTarget` 建構參數，型別與欄位名稱與 spec.md §6 程式碼範例逐字一致 → Task 1；(2) 「作用範圍精確限定為決定初始定位參數，不新增暫停進度儲存旗標」→ Task 1 Step 9（`initialLocatorJson`/`initialPageIndex` 的 `??` 覆寫，不觸碰 `_writeCurrentPosition()`/`onLocatorChanged` 既有邏輯）；(3) Foliate `window.showSearchHighlight`/`window.clearSearchHighlight`＋獨立 `currentSearchHighlightValue` → Task 3；(4) PDF 複用 `pageOverlaysBuilder` 畫暫態高亮矩形 → Task 2；(5) 生命週期由 Dart 端 `Timer` 主導（3 秒／提前翻頁或點擊清除，取兩者較早）→ Task 4；(6) `LibrarySearchScreen` 點擊內容匹配片段時帶 `ReaderJumpTarget` 開啟 `ReaderScreen` → Task 5。issues.md Issue 5 單元測試要求三項：「`initialJumpTarget` 定位來源正確、後續翻頁/checkpoint 行為與一般開書一致」→ Task 1 測試（含零回歸測試）；「暫態高亮 3 秒自動消失／提前翻頁點擊清除」→ Task 4 測試（PDF 端完整驗證，見 Global Constraints 對誠實測試邊界的說明）；「Foliate 端 showSearchHighlight/clearSearchHighlight 不影響 TTS 播放狀態」→ Task 3 main.js regression guard 雙向隔離測試。驗收標準「`integration_test/` 或手動驗證：從全庫搜尋點擊一則內容匹配，真的跳到該精確位置並看到 3 秒暫態高亮，且原本的閱讀進度不受影響」→ Task 5 Step 9 人工驗證項目 1-6。

**Placeholder 掃描：** 無「TBD」「稍後補上」「類似 Task N」等字樣，所有程式碼片段皆為完整可直接套用的內容（含 `reader_screen.dart`／`pdf_reader_view.dart`／`main.js` 的逐段 find/replace 皆為實際既有文字，已於規劃階段逐一讀取原始檔案確認）。

**型別一致性：** `ReaderJumpTarget`（`cfi`／`pdfPageIndex`／`pdfRect`／`fromContentLocator()`）在 Task 1 定義，Task 4 的 `_maybeShowSearchJumpHighlight()` 與 Task 5 的 `LibrarySearchScreen._openBook()` 呼叫端欄位存取方式一致；`PdfReaderView.showTemporaryHighlight`/`clearTemporaryHighlight` 在 Task 2 定義（含 `pdf_reader_jump_highlight_$pageIndex` Key 命名），Task 4 呼叫端參數順序/型別一致；`FoliateReaderView.showSearchHighlight`/`clearSearchHighlight` 在 Task 3 定義（審查修正 I-1 後簽章簡化為只有 `cfi`，不再有 `vertical`/`einkMode`），Task 4 呼叫端已同步移除這兩個具名參數；`ReaderScreen.initialJumpTarget` 在 Task 1 定義，Task 4／Task 5 皆原樣引用，命名一致。

**審查回應總結（`reviews/review-plan-issue-5.md`）：** 1 Critical／3 Important／4 Minor 共 8 項發現逐一查證後：C-1（Task 4 高亮生命週期測試的 `pumpUntilPdfReady(tester)` 不帶 `condition` 時會在 fake-async 環境累積推進 3,000ms，恰好等於 3 秒暫態高亮計時器時長，導致斷言在計時器到期前後順序錯亂）、I-1（規劃階段查證 `view.js` 原始碼後推翻原設計——`foliate-search:` 是 vendored 函式庫自己既有、寫死走 `Overlayer.outline` 固定紅色外框的常數，不是可自訂顏色的保留前綴，main.js／`FoliateReaderView` 的簽章與實作、Global Constraints 皆已改寫）、I-3（issues.md 明定的「後續翻頁 checkpoint 行為一致」測試原計畫遺漏，已補上）、M-1（`_buildBody()`／`_buildNativeView()` 方法名稱指稱錯誤）、M-2（PDF locator 缺 `rect` 時的優雅降級，推翻原「整筆回傳 null」設計）、M-3（`_setJumpHighlight` 補 `mounted` 防護）皆查證屬實並已修訂。I-2（`dispose()` 在使用者跳轉後未翻頁即離開時會覆寫舊進度）技術上屬實，但這是 spec.md §6 已明文記錄並拒絕過的同一類「主動互動追蹤」提案（"不需要額外的『使用者是否已產生主動互動』判斷……予以簡化"，原文逐字引用）——本計畫不在計畫層級片面推翻已定案的 spec 決策，改為在 Task 1 新增一個測試把這個行為明確鎖定並記錄為已知、刻意接受的簡化，同時在 Global Constraints 說明「若要改變此行為需回頭修訂 spec.md §6」，留給人類決定是否值得重新開這個決策。M-4（commit 訊息含舊版 attribution）經逐一核對本計畫全部 6 處 commit 區塊後確認不成立——皆已是 `Claude Sonnet 5 <noreply@anthropic.com>`，判斷為審查者誤判，維持原樣不修改。
