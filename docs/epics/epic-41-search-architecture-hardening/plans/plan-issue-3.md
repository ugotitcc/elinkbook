# Epic 41 Issue 3：ReaderJumpTarget 收下「套用到 View」的行為（applyTo()）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 在 `ReaderJumpTarget` 新增 `applyTo()` 方法，收下「把跳轉目標套用到活著的閱讀器 View」這個行為，取代 `ReaderScreen._maybeShowSearchJumpHighlight()`／`_handleReaderSearchJumpTarget()` 兩處幾乎相同的格式分派 if-else。

**Architecture:** `applyTo()` 是同步方法、回傳 `bool`（本次是否真的疊加了暫態高亮），內部依 `format` 分派到 PDF／Foliate 分支，`shouldNavigate` 旗標決定要不要先跳頁。「啟動/清除 3 秒自動計時器」這段狀態機仍留在 `ReaderScreen`——`applyTo()` 只負責單次呼叫的判斷與側效應，呼叫端依回傳值決定是否啟動計時器。

**Tech Stack:** Flutter/Dart，`flutter_test`（純 Dart 單元測試驗證 `applyTo()` 本身；既有 `testWidgets` 全螢幕整合測試驗證 `ReaderScreen` 呼叫端零回歸）。

**Spec:** `docs/epics/epic-41-search-architecture-hardening/issues.md`（Issue 3 段落，已依 `reviews/review-epic-and-issues.md` I-1 修訂——`GlobalKey<State<PdfReaderView>>`/`GlobalKey<State<FoliateReaderView>>` 正確型別、同步方法、回傳 `bool`）。

## Global Constraints

- 所有新增/修改的程式碼註解與本計畫文件一律使用正體中文（zh-TW），不得使用簡體中文（使用者全域 CLAUDE.md 規則）。
- `applyTo()` 必須是**同步**方法（回傳 `bool`，不是 `Future<void>`）——`PdfReaderView`／`FoliateReaderView` 的四個靜態 helper（`jumpToPage`／`showTemporaryHighlight`／`jumpToLocator`／`showSearchHighlight`）皆為同步 `void` 方法，`applyTo()` 內部沒有任何 `await`，宣告成 `Future` 會強迫呼叫端不必要地非同步化。
- `applyTo()` **不含**「啟動/清除 3 秒自動計時器」（`_startSearchJumpHighlightAutoClearTimer`/`_clearSearchJumpHighlight`）——這是 `ReaderScreen` 自己的計時器生命週期狀態，維持留在 `ReaderScreen`，`applyTo()` 只回傳 `bool` 供呼叫端決定要不要啟動計時器。
- Key 型別使用專案既有公開型別 `GlobalKey<State<PdfReaderView>>`／`GlobalKey<State<FoliateReaderView>>`——**不存在** `PdfReaderViewState`／`FoliateReaderViewState` 這兩個公開型別（`_PdfReaderViewState`／`_FoliateReaderViewState` 皆為私有類別），`reader_screen.dart` 現有的 `_pdfReaderViewKey`／`_foliateEpubReaderViewKey` 兩個欄位本身就是 `GlobalKey<State<PdfReaderView>>`／`GlobalKey<State<FoliateReaderView>>`，直接照抄即可。
- 不改動 `PdfReaderView`／`FoliateReaderView` 這兩個檔案——四個既有靜態 helper 簽章與行為完全不動，`applyTo()` 純粹是呼叫端整合。
- 每個 Task 只跑「這次異動實際觸及」的測試檔；只在**最後一個 Task**（Task 2）跑一次完整 `flutter analyze`／`flutter test` 作最終確認（專案 `CLAUDE.md`「測試執行範圍」既有慣例）。
- Git commit 訊息結尾需附加下列兩行（本次 session 的固定 attribution，見系統提示）：
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
  ```
- **單元測試與整合測試的邊界權衡（`reviews/review-plan-issue-3.md` I-1）**：`app/test/reader/reader_jump_target_test.dart` 的 `applyTo()` 純單元測試使用未掛載的空白 `GlobalKey`，`PdfReaderView.jumpToPage`／`showTemporaryHighlight`（`FoliateReaderView` 同理）內部皆檢查 `key.currentState is _PdfReaderViewState`，key 未掛載時靜默忽略——這代表純單元測試只能驗證 `applyTo()` 自己的格式分派與回傳值邏輯，**無法**偵測「漏寫某個靜態 helper 呼叫」這類副作用缺失。真正驗證這些靜態 helper 副作用是否真的觸發，完全依賴 Task 2 Step 3 既有的 `test/screens/reader_screen_test.dart` 全螢幕整合測試（實際 pump 真實 `ReaderScreen`＋fixture，用 `find.byKey(...)` 斷言高亮真的出現/清除）——這是不可妥協的驗收關卡，Task 1 的單元測試不能取代它。

---

### Task 1: `ReaderJumpTarget` 新增 `applyTo()` 方法

**Files:**
- Modify: `app/lib/reader/reader_jump_target.dart`
- Modify: `app/test/reader/reader_jump_target_test.dart`（**此檔案已存在**，內含 `group('ReaderJumpTarget.fromContentLocator', ...)` 6 個既有測試——本 Task 只在其後追加新的 `group('applyTo：...', ...)`，既有 6 個測試維持原樣不動，**絕不可整檔覆蓋**）

**Interfaces:**
- Consumes：既有型別 `BookFormat`／`isFoliateFormat()`（`reader/book_format.dart`）、`PdfReaderView`（`reader/pdf_reader_view.dart`，靜態 helper `jumpToPage(GlobalKey<State<PdfReaderView>>, int)`／`showTemporaryHighlight(GlobalKey<State<PdfReaderView>>, int, PercentRect)`）、`FoliateReaderView`（`reader/foliate_reader_view.dart`，靜態 helper `jumpToLocator(GlobalKey<State<FoliateReaderView>>, String)`／`showSearchHighlight(GlobalKey<State<FoliateReaderView>>, String)`）。
- Produces（供 Task 2 呼叫）：
  ```dart
  bool applyTo({
    required BookFormat format,
    required GlobalKey<State<PdfReaderView>> pdfKey,
    required GlobalKey<State<FoliateReaderView>> foliateKey,
    required bool shouldNavigate,
  });
  ```

- [x] **Step 1: 寫失敗測試**

`app/test/reader/reader_jump_target_test.dart`**已存在**（`group('ReaderJumpTarget.fromContentLocator', ...)` 6 個既有測試，維持原樣不動）。先把開頭 import 區塊從：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
```

改為：

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/book_format.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
```

再於既有 `group('ReaderJumpTarget.fromContentLocator', () { ... });` 結尾之後、`void main() { ... }` 的最後一個 `}` 之前，追加以下內容（`fromContentLocator` 那個 group 本身完全不動）：

```dart

  // applyTo() 底層的 PdfReaderView/FoliateReaderView 靜態 helper 對「key
  // 尚未掛載任何 State」的情況皆為靜默忽略（見兩者各自文件註解），不拋
  // 例外——這裡刻意使用未掛載的空白 GlobalKey，讓測試只聚焦驗證 applyTo()
  // 自己的分派與回傳值邏輯，不需要真正渲染 PdfReaderView/FoliateReaderView
  // （那部分的副作用是否真的觸發，由 reader_screen_test.dart 既有的全螢幕
  // 整合測試把關，見本計畫 Global Constraints 的邊界權衡說明）。
  final pdfKey = GlobalKey<State<PdfReaderView>>();
  final foliateKey = GlobalKey<State<FoliateReaderView>>();

  group('applyTo：PDF 格式', () {
    test('pdfPageIndex 為 null 時，不論 shouldNavigate 為何皆回傳 false', () {
      const target = ReaderJumpTarget(
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      );

      expect(
        target.applyTo(
          format: BookFormat.pdf,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: false,
        ),
        isFalse,
      );
      expect(
        target.applyTo(
          format: BookFormat.pdf,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: true,
        ),
        isFalse,
      );
    });

    test('pdfPageIndex 存在、pdfRect 為 null 時回傳 false（只跳頁不顯示高亮）',
        () {
      const target = ReaderJumpTarget(pdfPageIndex: 3);

      expect(
        target.applyTo(
          format: BookFormat.pdf,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: false,
        ),
        isFalse,
      );
      expect(
        target.applyTo(
          format: BookFormat.pdf,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: true,
        ),
        isFalse,
      );
    });

    test('pdfPageIndex／pdfRect 皆存在時回傳 true', () {
      const target = ReaderJumpTarget(
        pdfPageIndex: 3,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      );

      expect(
        target.applyTo(
          format: BookFormat.pdf,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: false,
        ),
        isTrue,
      );
      expect(
        target.applyTo(
          format: BookFormat.pdf,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: true,
        ),
        isTrue,
      );
    });
  });

  group('applyTo：Foliate 格式', () {
    test('cfi 為 null 時，不論 shouldNavigate 為何皆回傳 false', () {
      const target = ReaderJumpTarget();

      expect(
        target.applyTo(
          format: BookFormat.epub,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: false,
        ),
        isFalse,
      );
      expect(
        target.applyTo(
          format: BookFormat.epub,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: true,
        ),
        isFalse,
      );
    });

    test('cfi 存在時，所有 Foliate 格式（epub/azw3/cbz/txt/md）皆回傳 true'
        '（防止實作誤寫成 format == BookFormat.epub 而非 isFoliateFormat(format)）',
        () {
      const target = ReaderJumpTarget(cfi: 'epubcfi(/6/4!/4/2)');

      for (final format in [
        BookFormat.epub,
        BookFormat.azw3,
        BookFormat.cbz,
        BookFormat.txt,
        BookFormat.md,
      ]) {
        expect(
          target.applyTo(
            format: format,
            pdfKey: pdfKey,
            foliateKey: foliateKey,
            shouldNavigate: false,
          ),
          isTrue,
          reason: '格式 $format 應被視為 Foliate 格式',
        );
      }
    });
  });

  group('applyTo：不支援的格式', () {
    test('BookFormat.unknown 不論 shouldNavigate 為何皆回傳 false', () {
      const target = ReaderJumpTarget(
        cfi: 'epubcfi(/6/4!/4/2)',
        pdfPageIndex: 3,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      );

      expect(
        target.applyTo(
          format: BookFormat.unknown,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: false,
        ),
        isFalse,
      );
      expect(
        target.applyTo(
          format: BookFormat.unknown,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: true,
        ),
        isFalse,
      );
    });
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/reader_jump_target_test.dart`
Expected: FAIL（編譯錯誤，`ReaderJumpTarget` 沒有 `applyTo` 方法；既有 6 個 `fromContentLocator` 測試因編譯失敗無法執行，屬預期現象）

- [x] **Step 3: 寫最小實作**

在 `app/lib/reader/reader_jump_target.dart`，把開頭 import 區塊：

```dart
import 'dart:convert';

import '../library/models/library_enums.dart';
import 'percent_rect.dart';
```

改為：

```dart
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../library/models/library_enums.dart';
import 'book_format.dart';
import 'foliate_reader_view.dart';
import 'pdf_reader_view.dart';
import 'percent_rect.dart';
```

在 `_parsePdfRect()` 方法之後、類別結尾 `}` 之前，新增：

```dart

  /// 把本跳轉目標套用到一個活著的閱讀器 View（epic-41-search-architecture-hardening
  /// Issue 3）：依 [format] 分派到 PDF／Foliate 分支，[shouldNavigate] 為
  /// `true` 時先呼叫 `jumpToPage`/`jumpToLocator` 導覽過去，再嘗試疊加
  /// 暫態高亮。**回傳值即「本次是否真的疊加了暫態高亮」**（PDF 端對應
  /// [pdfPageIndex] 與 [pdfRect] 皆存在；Foliate 端對應 [cfi] 存在），
  /// 呼叫端據此決定要不要啟動 3 秒自動清除計時器——本方法本身不管理
  /// 計時器生命週期，那是 [ReaderScreen] 自己的狀態。
  ///
  /// 對應欄位缺失時優雅跳出、不拋例外（沿用 [fromContentLocator] 文件
  /// 註解的既有語意）：PDF 只有 [pdfPageIndex]、[pdfRect] 為 `null` 時，
  /// [shouldNavigate] 為 `true` 仍會先跳頁，只是不顯示暫態高亮、回傳
  /// `false`——跳頁與顯示高亮是兩個獨立判斷，不能因為沒有精確座標就連
  /// 頁面都不跳（`review-plan-issue-8.md` C-1 既有教訓）。[format] 既非
  /// PDF 也非 Foliate（例如 [BookFormat.unknown]）時直接回傳 `false`，
  /// 不做任何事。
  bool applyTo({
    required BookFormat format,
    required GlobalKey<State<PdfReaderView>> pdfKey,
    required GlobalKey<State<FoliateReaderView>> foliateKey,
    required bool shouldNavigate,
  }) {
    if (format == BookFormat.pdf) {
      final pageIndex = pdfPageIndex;
      if (pageIndex == null) return false;
      if (shouldNavigate) {
        PdfReaderView.jumpToPage(pdfKey, pageIndex);
      }
      final rect = pdfRect;
      if (rect == null) return false;
      PdfReaderView.showTemporaryHighlight(pdfKey, pageIndex, rect);
      return true;
    }
    if (isFoliateFormat(format)) {
      final targetCfi = cfi;
      if (targetCfi == null) return false;
      if (shouldNavigate) {
        FoliateReaderView.jumpToLocator(foliateKey, targetCfi);
      }
      FoliateReaderView.showSearchHighlight(foliateKey, targetCfi);
      return true;
    }
    return false;
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/reader_jump_target_test.dart`
Expected: PASS（該檔總數 12 個測試案例全數通過——既有 6 個 `fromContentLocator` 測試＋新增 6 個 `applyTo` 測試）

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/reader/reader_jump_target.dart test/reader/reader_jump_target_test.dart`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/reader_jump_target.dart app/test/reader/reader_jump_target_test.dart
git commit -m "$(cat <<'EOF'
feat(reader): ReaderJumpTarget 新增 applyTo() 收下套用到 View 的行為（epic-41 Issue 3 Task 1）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

---

### Task 2: `ReaderScreen` 改用 `applyTo()`，並跑全套驗證收尾

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1577-1660`
- Test: `app/test/screens/reader_screen_test.dart`（既有測試，不新增案例）

**Interfaces:**
- Consumes：Task 1 產出的 `ReaderJumpTarget.applyTo()`。

- [x] **Step 1: 改寫 `_maybeShowSearchJumpHighlight()`**

在 `app/lib/screens/reader_screen.dart:1577-1596`，原本：

```dart
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
    _startSearchJumpHighlightAutoClearTimer();
  }
```

改為：

```dart
  void _maybeShowSearchJumpHighlight() {
    if (_searchJumpHighlightTriggered) return;
    final jumpTarget = widget.initialJumpTarget;
    if (jumpTarget == null) return;
    _searchJumpHighlightTriggered = true;
    final highlightShown = jumpTarget.applyTo(
      format: detectBookFormat(widget.filePath),
      pdfKey: _pdfReaderViewKey,
      foliateKey: _foliateEpubReaderViewKey,
      shouldNavigate: false,
    );
    if (highlightShown) {
      _startSearchJumpHighlightAutoClearTimer();
    }
  }
```

- [x] **Step 2: 改寫 `_handleReaderSearchJumpTarget()`**

在 `app/lib/screens/reader_screen.dart:1642-1660`，原本：

```dart
  void _handleReaderSearchJumpTarget(ReaderJumpTarget jumpTarget) {
    final format = detectBookFormat(widget.filePath);
    if (format == BookFormat.pdf) {
      final pageIndex = jumpTarget.pdfPageIndex;
      if (pageIndex == null) return;
      PdfReaderView.jumpToPage(_pdfReaderViewKey, pageIndex);
      final rect = jumpTarget.pdfRect;
      if (rect == null) return;
      PdfReaderView.showTemporaryHighlight(_pdfReaderViewKey, pageIndex, rect);
    } else if (isFoliateFormat(format)) {
      final cfi = jumpTarget.cfi;
      if (cfi == null) return;
      FoliateReaderView.jumpToLocator(_foliateEpubReaderViewKey, cfi);
      FoliateReaderView.showSearchHighlight(_foliateEpubReaderViewKey, cfi);
    } else {
      return;
    }
    _startSearchJumpHighlightAutoClearTimer();
  }
```

改為：

```dart
  void _handleReaderSearchJumpTarget(ReaderJumpTarget jumpTarget) {
    final highlightShown = jumpTarget.applyTo(
      format: detectBookFormat(widget.filePath),
      pdfKey: _pdfReaderViewKey,
      foliateKey: _foliateEpubReaderViewKey,
      shouldNavigate: true,
    );
    if (highlightShown) {
      _startSearchJumpHighlightAutoClearTimer();
    }
  }
```

（兩段既有的方法文件註解——`_maybeShowSearchJumpHighlight` 上方 1571-1576 行、`_handleReaderSearchJumpTarget` 上方 1629-1641 行——維持原樣不動，內容描述的仍是正確的行為語意，只是實作細節搬進 `applyTo()`。）

- [x] **Step 3: 執行既有回歸測試**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全數通過，含 `epic-10-search Issue 5：搜尋跳轉暫態高亮生命週期` 與 Issue 8 就地跳轉測試群組零回歸——這些測試實際 pump 真實 `ReaderScreen`＋PDF/EPUB fixture，透過 `find.byKey(const Key('pdf_reader_jump_highlight_0'))` 等既有 Key 驗證暫態高亮確實顯示/清除，是本次重構「行為完全不變」的關鍵證據）

- [x] **Step 4: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/reader_screen.dart`
Expected: `No issues found!`

- [x] **Step 5: 跑完整 `flutter analyze`／`flutter test` 作最終確認**

本 Issue 兩個 Task 皆完成，依專案慣例在最後一個 Task 跑一次全套驗證：

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數通過（`reader_jump_target_test.dart` 該檔總數為 12 個——既有 6 個 `fromContentLocator` 測試維持不動＋新增 6 個 `applyTo` 測試，全庫測試總數為 Issue 2 合併後的既有基準淨增 +6；失敗數維持 2 且必須是同樣兩個 `adaptive_shell_scaffold_test.dart` 既有案例，不可出現新的失敗）。

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen.dart
git commit -m "$(cat <<'EOF'
refactor(reader): ReaderScreen 兩處搜尋跳轉格式分派改用 ReaderJumpTarget.applyTo()（epic-41 Issue 3 Task 2）

_maybeShowSearchJumpHighlight()／_handleReaderSearchJumpTarget() 兩段
幾乎相同的 PDF/Foliate if-else 分派皆已收斂為呼叫同一個 applyTo()，
「啟動 3 秒自動清除計時器」的判斷改依 applyTo() 回傳值決定。
flutter analyze/flutter test 全數通過，零回歸。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

- [x] **Step 7: 更新工單狀態**

在 `docs/epics/epic-41-search-architecture-hardening/issues.md` 的 Issue 3 段落，依專案既有看板慣例，把 `**Status:** ready-for-agent` 改為：

```
**Status:** completed（`plans/plan-issue-3.md` 2 個 Task 全數完成，`ReaderJumpTarget` 新增 `applyTo()`，`ReaderScreen` 兩處格式分派皆已改用，`flutter analyze`/`flutter test` 全數通過零回歸）
```

同步在 `epic.md` 的開發記錄追加一句「Issue 3 已完成」。
