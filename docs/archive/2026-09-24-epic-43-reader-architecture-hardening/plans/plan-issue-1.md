# Epic 43 Issue 1 — AnnotationSession Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 收斂 `ReaderScreen` 的劃線/備註 CRUD（EPUB／PDF 兩條路徑各自逐行重寫、約 220 行同構程式碼）成一個不依賴 `BuildContext` 的深模組 `AnnotationSession`。

**Architecture:** 新增 `app/lib/reader/annotation_session.dart`，內含三個型別：`AnnotationSnapshot`（`highlights`/`notes` 快照值物件）、`AnnotationLocator`（統一 EPUB／PDF 定位方式的值物件，比照 `Highlight`/`Note` 既有「一組欄位皆可空」寫法）、`AnnotationSession`（建構子注入 `highlightsRepository`/`notesRepository`/`bookId`，4 個方法：`reload`/`createHighlight`/`createOrUpdateNote`/`deleteExisting`，皆回傳快照而非產生副作用）。`ReaderScreen` 新增 `late final AnnotationSession? _annotationSession`，EPUB／PDF 各自的 6 個私有方法改為呼叫 `_annotationSession` 的方法取得快照後自行 `setState`，`BuildContext`/`GlobalKey` 依賴（送原生端、跳窗拿備註文字、UI 收尾）維持留在呼叫端不動。

**Tech Stack:** Flutter/Dart 3.11，`flutter_test`，既有 `FakeHighlightsRepository`/`FakeNotesRepository`（`app/test/support/`）。

**Spec:** `docs/epics/epic-43-reader-architecture-hardening/issues.md` Issue 1（已依 `reviews/review-epic-and-issues.md` M-1 修訂補上 `AnnotationSnapshot` 值相等性）。

## Global Constraints

- 所有指令在 `app/` 目錄下執行。
- `AnnotationSession` 不得依賴 `BuildContext`、`GlobalKey`、`Theme.of(context)`——這是本 Issue 的核心邊界（`/grilling` Q3/Q5/Q6 已定案），測試須能在不 pump 任何 Widget 的情況下直接呼叫。
- `_handleHighlightStyleSelected`/`_handlePdfHighlightStyleSelected`、`_reloadAnnotationsAndRefreshDecorations`/`_reloadPdfAnnotationsAndSync` 等 EPUB／PDF 對應方法**本身不合併**——只有中間呼叫 repository 的邏輯改呼叫 `AnnotationSession`，兩個方法各自維持獨立（送原生端方式不同）。
- `_toggleBookmark`/`_togglePdfBookmark`（`bookmark_toggle.dart`）不在本 Issue 範圍內，不動。
- 實作前用 `grep -c "highlightsRepository:" test/screens/reader_screen_test.dart && grep -c "notesRepository:" test/screens/reader_screen_test.dart`（**M-1 審查修訂**：兩個 pattern 須分開下 `grep -c`，用 `\|` 合併成單一 pattern 只會輸出兩者加總的單一數字，無法個別核對）核對兩者出現次數仍相等（規劃當下皆為 34）；若不相等，先停下來回報，不可逕自假設「永遠成對」前提仍成立就繼續。
- 每個 Task 的 TDD 步驟只跑本次異動觸及的測試檔；完整 `flutter test` 只在最後一個 Task（Task 8）執行一次。

---

### Task 1: AnnotationSnapshot／AnnotationLocator 值物件

**Files:**
- Create: `app/lib/reader/annotation_session.dart`
- Test: `app/test/reader/annotation_session_test.dart`

**Interfaces:**
- Produces: `AnnotationSnapshot`（`{required List<Highlight> highlights, required List<Note> notes}`，具 `operator ==`/`hashCode`）、`AnnotationLocator.epub({required String locatorJson, double? progression})`、`AnnotationLocator.pdf({required int pageIndex, required PercentRect rect})`（欄位：`epubLocatorJson`/`progression`/`pdfPageIndex`/`pdfRect`，皆為 nullable）。

- [x] **Step 1: 建立測試檔並寫入失敗測試**

建立 `app/test/reader/annotation_session_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/annotation_session.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  group('AnnotationSnapshot', () {
    test('內容相同時視為相等', () {
      const highlight = Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: 'loc',
      );
      const note = Note(id: 'n1', bookId: 'b1', text: 'hi', epubLocatorJson: 'loc');
      const a = AnnotationSnapshot(highlights: [highlight], notes: [note]);
      const b = AnnotationSnapshot(highlights: [highlight], notes: [note]);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('highlights 清單內容不同時不相等', () {
      const h1 = Highlight(id: 'h1', bookId: 'b1', style: HighlightStyle.highlighterYellow);
      const h2 = Highlight(id: 'h2', bookId: 'b1', style: HighlightStyle.highlighterYellow);
      const a = AnnotationSnapshot(highlights: [h1], notes: []);
      const b = AnnotationSnapshot(highlights: [h2], notes: []);

      expect(a == b, isFalse);
    });
  });

  group('AnnotationLocator', () {
    test('.epub 只帶 EPUB 欄位，PDF 欄位皆為 null', () {
      const locator = AnnotationLocator.epub(locatorJson: 'loc', progression: 0.5);

      expect(locator.epubLocatorJson, 'loc');
      expect(locator.progression, 0.5);
      expect(locator.pdfPageIndex, isNull);
      expect(locator.pdfRect, isNull);
    });

    test('.pdf 只帶 PDF 欄位，EPUB 欄位皆為 null', () {
      const rect = PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.5);
      const locator = AnnotationLocator.pdf(pageIndex: 3, rect: rect);

      expect(locator.pdfPageIndex, 3);
      expect(locator.pdfRect, rect);
      expect(locator.epubLocatorJson, isNull);
      expect(locator.progression, isNull);
    });
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/annotation_session_test.dart`
Expected: FAIL（`annotation_session.dart` 尚不存在，import 錯誤）

- [x] **Step 3: 建立 `annotation_session.dart`，寫入 `AnnotationSnapshot`／`AnnotationLocator`**

```dart
import 'package:flutter/foundation.dart';

import 'highlight.dart';
import 'note.dart';
import 'percent_rect.dart';

/// 劃線/備註 CRUD 完成後的最新清單快照（Epic 43 Issue 1）。無狀態回傳值
/// ——AnnotationSession 本身不持有狀態，呼叫端 (ReaderScreen) 拿到快照後
/// 自行 setState。
@immutable
class AnnotationSnapshot {
  const AnnotationSnapshot({required this.highlights, required this.notes});

  final List<Highlight> highlights;
  final List<Note> notes;

  @override
  bool operator ==(Object other) =>
      other is AnnotationSnapshot &&
      listEquals(other.highlights, highlights) &&
      listEquals(other.notes, notes);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(highlights), Object.hashAll(notes));
}

/// 統一 EPUB／PDF 定位方式的值物件——比照 [Highlight]/[Note] 建構子本身
/// 既有的「一組欄位皆可空」寫法，不引入正式 adapter 介面（`/grilling` Q1）。
@immutable
class AnnotationLocator {
  const AnnotationLocator.epub({required String locatorJson, this.progression})
      : epubLocatorJson = locatorJson,
        pdfPageIndex = null,
        pdfRect = null;

  const AnnotationLocator.pdf({required int pageIndex, required PercentRect rect})
      : pdfPageIndex = pageIndex,
        pdfRect = rect,
        epubLocatorJson = null,
        progression = null;

  final String? epubLocatorJson;
  final double? progression;
  final int? pdfPageIndex;
  final PercentRect? pdfRect;
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/annotation_session_test.dart`
Expected: PASS（4 個測試全過）

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/annotation_session.dart app/test/reader/annotation_session_test.dart
git commit -m "feat(reader): 新增 AnnotationSnapshot/AnnotationLocator 值物件"
```

---

### Task 2: AnnotationSession.reload()

**Files:**
- Modify: `app/lib/reader/annotation_session.dart`
- Test: `app/test/reader/annotation_session_test.dart`

**Interfaces:**
- Consumes: `AnnotationSnapshot`（Task 1）、`HighlightsRepository`/`NotesRepository`（`app/lib/reader/highlights_repository.dart`/`notes_repository.dart`，既有 `listByBook(String bookId)` 方法）、測試用 `FakeHighlightsRepository`/`FakeNotesRepository`（`app/test/support/fake_highlights_repository.dart`/`fake_notes_repository.dart`，已 `implements` 對應 repository，直接複用不需新建）。
- Produces: `AnnotationSession({required HighlightsRepository highlightsRepository, required NotesRepository notesRepository, required String bookId})`，`Future<AnnotationSnapshot> reload()`。

- [x] **Step 1: 寫入失敗測試**

在 `annotation_session_test.dart` 加入（於既有 `import` 區塊補上兩行，於 `void main()` 內既有 group 後新增）：

```dart
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/reader/notes_repository.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';
```

```dart
  group('AnnotationSession.reload', () {
    test('回傳兩個 repository 目前的完整清單', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      await highlightsRepo.insert(const Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: 'loc',
        progression: 0.1,
      ));
      await notesRepo.insert(const Note(
        id: 'n1',
        bookId: 'b1',
        text: 'hi',
        epubLocatorJson: 'loc',
        progression: 0.1,
      ));
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );

      final snapshot = await session.reload();

      expect(snapshot.highlights, hasLength(1));
      expect(snapshot.highlights.single.id, 'h1');
      expect(snapshot.notes, hasLength(1));
      expect(snapshot.notes.single.id, 'n1');
    });

    // M-2（審查修訂）：不同 bookId 的資料須被過濾掉，避免未來實作遺漏
    // bookId 參數過濾而混入其他書籍的劃線/備註。
    test('只回傳指定 bookId 的資料，其他書籍的劃線/備註不混入', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      await highlightsRepo.insert(const Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: 'loc',
      ));
      await highlightsRepo.insert(const Highlight(
        id: 'h-other',
        bookId: 'b_other',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: 'loc',
      ));
      await notesRepo.insert(const Note(id: 'n1', bookId: 'b1', text: 'hi', epubLocatorJson: 'loc'));
      await notesRepo.insert(
        const Note(id: 'n-other', bookId: 'b_other', text: 'hi', epubLocatorJson: 'loc'),
      );
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );

      final snapshot = await session.reload();

      expect(snapshot.highlights, hasLength(1));
      expect(snapshot.highlights.single.id, 'h1');
      expect(snapshot.notes, hasLength(1));
      expect(snapshot.notes.single.id, 'n1');
    });
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/annotation_session_test.dart`
Expected: FAIL（`AnnotationSession` 類別不存在）

- [x] **Step 3: 在 `annotation_session.dart` 新增 `AnnotationSession` 類別與 `reload()`**

於檔案頂部補 import，於 `AnnotationLocator` 類別後新增：

```dart
import 'highlights_repository.dart';
import 'notes_repository.dart';
```

```dart
/// 建構子注入依賴；只做 repository CRUD＋查詢，不依賴 BuildContext／
/// GlobalKey（`/grilling` Q3/Q5/Q6：送原生端、跳窗拿文字、UI 收尾皆留在
/// ReaderScreen 呼叫端），純資料物件，回傳快照而非產生副作用（Q2）。
class AnnotationSession {
  AnnotationSession({
    required this.highlightsRepository,
    required this.notesRepository,
    required this.bookId,
  });

  final HighlightsRepository highlightsRepository;
  final NotesRepository notesRepository;
  final String bookId;

  Future<AnnotationSnapshot> reload() async {
    final highlights = await highlightsRepository.listByBook(bookId);
    final notes = await notesRepository.listByBook(bookId);
    return AnnotationSnapshot(highlights: highlights, notes: notes);
  }
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/annotation_session_test.dart`
Expected: PASS（6 個測試全過）

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/annotation_session.dart app/test/reader/annotation_session_test.dart
git commit -m "feat(reader): AnnotationSession 新增 reload()"
```

---

### Task 3: AnnotationSession.createHighlight()

**Files:**
- Modify: `app/lib/reader/annotation_session.dart`
- Test: `app/test/reader/annotation_session_test.dart`

**Interfaces:**
- Consumes: `AnnotationLocator`（Task 1）、`reload()`（Task 2）、`HighlightStyle`（`app/lib/reader/highlight_style.dart`）、`package:uuid/uuid.dart`（既有依賴，`reader_screen.dart` 已使用 `const Uuid().v4()`）。
- Produces: `Future<({AnnotationSnapshot snapshot, String highlightId})> createHighlight({required AnnotationLocator locator, required HighlightStyle style})`。

- [x] **Step 1: 寫入失敗測試**

```dart
  group('AnnotationSession.createHighlight', () {
    test('EPUB：寫入 epubLocatorJson/progression，PDF 欄位維持 null，回傳新 id', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );

      final result = await session.createHighlight(
        locator: const AnnotationLocator.epub(locatorJson: 'loc-a', progression: 0.2),
        style: HighlightStyle.highlighterYellow,
      );

      expect(result.snapshot.highlights, hasLength(1));
      final inserted = result.snapshot.highlights.single;
      expect(inserted.id, result.highlightId);
      expect(inserted.epubLocatorJson, 'loc-a');
      expect(inserted.progression, 0.2);
      expect(inserted.pdfPageIndex, isNull);
      expect(inserted.pdfRect, isNull);
    });

    test('PDF：寫入 pdfPageIndex/pdfRect，EPUB 欄位維持 null', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );
      const rect = PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2);

      final result = await session.createHighlight(
        locator: const AnnotationLocator.pdf(pageIndex: 4, rect: rect),
        style: HighlightStyle.underline,
      );

      final inserted = result.snapshot.highlights.single;
      expect(inserted.id, result.highlightId);
      expect(inserted.pdfPageIndex, 4);
      expect(inserted.pdfRect, rect);
      expect(inserted.epubLocatorJson, isNull);
      expect(inserted.progression, isNull);
    });
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/annotation_session_test.dart`
Expected: FAIL（`createHighlight` 方法不存在）

- [x] **Step 3: 實作 `createHighlight()`**

於檔案頂部補 import：

```dart
import 'package:uuid/uuid.dart';
```

於 `AnnotationSession` 類別內、`reload()` 後新增：

```dart
  /// 回傳新建 highlight 的 id（供呼叫端設定
  /// `_pendingHighlightIdForSelection`/`_pendingPdfHighlightIdForSelection`），
  /// 取代原本用 side-effect 直接寫欄位的作法。
  Future<({AnnotationSnapshot snapshot, String highlightId})> createHighlight({
    required AnnotationLocator locator,
    required HighlightStyle style,
  }) async {
    final id = const Uuid().v4();
    await highlightsRepository.insert(Highlight(
      id: id,
      bookId: bookId,
      style: style,
      epubLocatorJson: locator.epubLocatorJson,
      progression: locator.progression,
      pdfPageIndex: locator.pdfPageIndex,
      pdfRect: locator.pdfRect,
    ));
    final snapshot = await reload();
    return (snapshot: snapshot, highlightId: id);
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/annotation_session_test.dart`
Expected: PASS（8 個測試全過）

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/annotation_session.dart app/test/reader/annotation_session_test.dart
git commit -m "feat(reader): AnnotationSession 新增 createHighlight()"
```

---

### Task 4: AnnotationSession.createOrUpdateNote()

**Files:**
- Modify: `app/lib/reader/annotation_session.dart`
- Test: `app/test/reader/annotation_session_test.dart`

**Interfaces:**
- Consumes: `AnnotationLocator`（Task 1）、`reload()`（Task 2）、`Note`（`app/lib/reader/note.dart`，含既有 `copyWith`）。
- Produces: `Future<AnnotationSnapshot> createOrUpdateNote({required AnnotationLocator locator, required String text, Note? existing, String? pendingHighlightId})`。

- [x] **Step 1: 寫入失敗測試**

```dart
  group('AnnotationSession.createOrUpdateNote', () {
    test('existing 為 null 時 insert 新備註', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );

      final snapshot = await session.createOrUpdateNote(
        locator: const AnnotationLocator.epub(locatorJson: 'loc-a', progression: 0.3),
        text: '新備註',
      );

      expect(snapshot.notes, hasLength(1));
      expect(snapshot.notes.single.text, '新備註');
      expect(snapshot.notes.single.highlightId, isNull);
    });

    test('existing 非 null 時呼叫 updateText 而非 insert', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      const existing = Note(
        id: 'n1',
        bookId: 'b1',
        text: '舊文字',
        epubLocatorJson: 'loc-a',
        progression: 0.3,
      );
      await notesRepo.insert(existing);
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );

      final snapshot = await session.createOrUpdateNote(
        locator: const AnnotationLocator.epub(locatorJson: 'loc-a', progression: 0.3),
        text: '改過的文字',
        existing: existing,
      );

      expect(snapshot.notes, hasLength(1));
      expect(snapshot.notes.single.id, 'n1');
      expect(snapshot.notes.single.text, '改過的文字');
    });

    test('pendingHighlightId 非 null 時新備註依附該筆畫線', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );

      final snapshot = await session.createOrUpdateNote(
        locator: const AnnotationLocator.epub(locatorJson: 'loc-a'),
        text: '依附的備註',
        pendingHighlightId: 'h1',
      );

      expect(snapshot.notes.single.highlightId, 'h1');
    });

    // I-1（審查修訂）：前 3 則測試皆用 AnnotationLocator.epub，完全沒有
    // 覆蓋 PDF 新增路徑——若實作組裝 Note(...) 時漏傳 pdfPageIndex/pdfRect，
    // 前 3 則測試仍會全數通過，無法在單元測試層攔截。
    test('PDF：existing 為 null 時正確寫入 pdfPageIndex/pdfRect，EPUB 欄位維持 null', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );
      const rect = PercentRect(left: 0.1, top: 0.2, right: 0.8, bottom: 0.4);

      final snapshot = await session.createOrUpdateNote(
        locator: const AnnotationLocator.pdf(pageIndex: 2, rect: rect),
        text: 'PDF備註',
      );

      expect(snapshot.notes, hasLength(1));
      final inserted = snapshot.notes.single;
      expect(inserted.text, 'PDF備註');
      expect(inserted.pdfPageIndex, 2);
      expect(inserted.pdfRect, rect);
      expect(inserted.epubLocatorJson, isNull);
      expect(inserted.progression, isNull);
    });
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/annotation_session_test.dart`
Expected: FAIL（`createOrUpdateNote` 方法不存在）

- [x] **Step 3: 實作 `createOrUpdateNote()`**

於 `AnnotationSession` 類別內、`createHighlight()` 後新增：

```dart
  /// `existing != null` 時呼叫 `updateText`，否則 insert 新 Note。跳窗拿
  /// `text` 的步驟維持在 ReaderScreen，這裡只收「給定 text 之後」的 CRUD。
  Future<AnnotationSnapshot> createOrUpdateNote({
    required AnnotationLocator locator,
    required String text,
    Note? existing,
    String? pendingHighlightId,
  }) async {
    if (existing != null) {
      await notesRepository.updateText(existing.id, text);
    } else {
      await notesRepository.insert(Note(
        id: const Uuid().v4(),
        bookId: bookId,
        text: text,
        epubLocatorJson: locator.epubLocatorJson,
        progression: locator.progression,
        pdfPageIndex: locator.pdfPageIndex,
        pdfRect: locator.pdfRect,
        highlightId: pendingHighlightId,
      ));
    }
    return reload();
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/annotation_session_test.dart`
Expected: PASS（12 個測試全過）

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/annotation_session.dart app/test/reader/annotation_session_test.dart
git commit -m "feat(reader): AnnotationSession 新增 createOrUpdateNote()"
```

---

### Task 5: AnnotationSession.deleteExisting()

**Files:**
- Modify: `app/lib/reader/annotation_session.dart`
- Test: `app/test/reader/annotation_session_test.dart`

**Interfaces:**
- Consumes: `AnnotationListItem`（`app/lib/reader/annotation_list_item.dart`，既有 `{highlight, note}` 欄位）、`reload()`（Task 2）。
- Produces: `Future<AnnotationSnapshot> deleteExisting(AnnotationListItem item)`。

- [x] **Step 1: 寫入失敗測試**

於檔案頂部補 import：

```dart
import 'package:elinkbook/reader/annotation_list_item.dart';
```

```dart
  group('AnnotationSession.deleteExisting', () {
    test('只有 highlight 時只刪除 highlight', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      const highlight = Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: 'loc',
      );
      await highlightsRepo.insert(highlight);
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );

      final snapshot =
          await session.deleteExisting(const AnnotationListItem(highlight: highlight));

      expect(snapshot.highlights, isEmpty);
    });

    test('只有 note 時只刪除 note', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      const note = Note(id: 'n1', bookId: 'b1', text: '純備註', epubLocatorJson: 'loc');
      await notesRepo.insert(note);
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );

      final snapshot = await session.deleteExisting(const AnnotationListItem(note: note));

      expect(snapshot.notes, isEmpty);
    });

    test('highlight 與依附備註皆有時兩者一併刪除', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      const highlight = Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: 'loc',
      );
      const note = Note(
        id: 'n1',
        bookId: 'b1',
        text: '依附備註',
        epubLocatorJson: 'loc',
        highlightId: 'h1',
      );
      await highlightsRepo.insert(highlight);
      await notesRepo.insert(note);
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );

      final snapshot = await session.deleteExisting(
        const AnnotationListItem(highlight: highlight, note: note),
      );

      expect(snapshot.highlights, isEmpty);
      expect(snapshot.notes, isEmpty);
    });
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/annotation_session_test.dart`
Expected: FAIL（`deleteExisting` 方法不存在）

- [x] **Step 3: 實作 `deleteExisting()`**

於 `AnnotationSession` 類別內、`createOrUpdateNote()` 後新增：

```dart
  /// 對應現有 ReaderScreen._deleteAnnotationRecords，刪除後內部呼叫一次
  /// reload() 回傳最新快照——呼叫端不需要再自己額外呼叫 reload。
  Future<AnnotationSnapshot> deleteExisting(AnnotationListItem item) async {
    final note = item.note;
    final highlight = item.highlight;
    if (note != null) await notesRepository.delete(note.id);
    if (highlight != null) await highlightsRepository.delete(highlight.id);
    return reload();
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/annotation_session_test.dart`
Expected: PASS（15 個測試全過）

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/annotation_session.dart app/test/reader/annotation_session_test.dart
git commit -m "feat(reader): AnnotationSession 新增 deleteExisting()"
```

---

### Task 6: ReaderScreen 接上 AnnotationSession（EPUB 側）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:438`（新增欄位）、`:1905-1909`（`_handleDeleteExistingAnnotation`，`_deleteAnnotationRecords` 暫不刪除，Task 7 PDF 側仍在用）、`:1973-2067`（`_handleHighlightStyleSelected`/`_handleNotePressed`/`_reloadAnnotationsAndRefreshDecorations`/`_sendDecorationsToNative`）

**Interfaces:**
- Consumes: `AnnotationSession`/`AnnotationSnapshot`/`AnnotationLocator`（Task 1-5，`app/lib/reader/annotation_session.dart`）。

- [x] **Step 1: 核對「永遠成對」前提仍成立，並執行既有測試建立基準線**

Run: `grep -c "highlightsRepository:" test/screens/reader_screen_test.dart && grep -c "notesRepository:" test/screens/reader_screen_test.dart`
Expected: 分行輸出兩個數字，須相等（規劃當下皆為 34）。若不相等，停下來回報給人類，不可逕自假設前提仍成立後繼續。

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（記錄目前全數通過，作為本 Task 修改後的零回歸基準）

- [x] **Step 2: 新增 import 與 `_annotationSession` 欄位**

在 `reader_screen.dart` 頂部 import 區塊（`import '../reader/annotation_resolution.dart';` 附近）新增：

```dart
import '../reader/annotation_session.dart';
```

在 `_pendingPdfHighlightIdForSelection` 欄位宣告（第 438 行）後新增：

```dart
  // Epic 43 Issue 1：EPUB／PDF 共用的劃線/備註 CRUD 深模組，僅在兩個
  // repository 皆非 null 時建構，否則為 null（呼叫端統一 guard）。
  late final AnnotationSession? _annotationSession =
      (widget.highlightsRepository != null && widget.notesRepository != null)
          ? AnnotationSession(
              highlightsRepository: widget.highlightsRepository!,
              notesRepository: widget.notesRepository!,
              bookId: widget.bookId,
            )
          : null;
```

- [x] **Step 3: 改寫 `_handleHighlightStyleSelected`**

找到現有方法（約第 1973-1987 行）：

```dart
  Future<void> _handleHighlightStyleSelected(HighlightStyle style) async {
    final selection = _currentSelection;
    final repository = widget.highlightsRepository;
    if (selection == null || repository == null) return;
    final id = const Uuid().v4();
    await repository.insert(Highlight(
      id: id,
      bookId: widget.bookId,
      style: style,
      epubLocatorJson: selection.locatorJson,
      progression: selection.progression,
    ));
    _pendingHighlightIdForSelection = id;
    await _reloadAnnotationsAndRefreshDecorations();
  }
```

改為：

```dart
  Future<void> _handleHighlightStyleSelected(HighlightStyle style) async {
    final selection = _currentSelection;
    final session = _annotationSession;
    if (selection == null || session == null) return;
    final result = await session.createHighlight(
      locator: AnnotationLocator.epub(
        locatorJson: selection.locatorJson,
        progression: selection.progression,
      ),
      style: style,
    );
    if (!mounted) return;
    setState(() {
      _highlights = result.snapshot.highlights;
      _notes = result.snapshot.notes;
      _pendingHighlightIdForSelection = result.highlightId;
    });
    _sendDecorationsToNative();
  }
```

- [x] **Step 4: 改寫 `_handleNotePressed`**

找到現有方法（約第 1989-2022 行）：

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
      initialText: existing?.text ?? '',
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

改為：

```dart
  Future<void> _handleNotePressed() async {
    final selection = _currentSelection;
    final session = _annotationSession;
    if (selection == null || session == null) return;
    final existing = resolveEpubExistingAnnotation(
      existingAnnotationId: selection.existingAnnotationId,
      highlights: _highlights,
      notes: _notes,
    )?.note;
    final text = await showNoteTextDialog(
      context,
      initialText: existing?.text ?? '',
      title: existing != null ? '編輯備註' : '新增備註',
    );
    if (text == null) return;
    final snapshot = await session.createOrUpdateNote(
      locator: AnnotationLocator.epub(
        locatorJson: selection.locatorJson,
        progression: selection.progression,
      ),
      text: text,
      existing: existing,
      pendingHighlightId: _pendingHighlightIdForSelection,
    );
    if (!mounted) return;
    setState(() {
      _highlights = snapshot.highlights;
      _notes = snapshot.notes;
      _currentSelection = null;
      _pendingHighlightIdForSelection = null;
    });
    _sendDecorationsToNative();
  }
```

- [x] **Step 5: 改寫 `_reloadAnnotationsAndRefreshDecorations`**

找到現有方法（約第 2028-2040 行）：

```dart
  Future<void> _reloadAnnotationsAndRefreshDecorations() async {
    final highlightsRepository = widget.highlightsRepository;
    final notesRepository = widget.notesRepository;
    if (highlightsRepository == null || notesRepository == null) return;
    final highlights = await highlightsRepository.listByBook(widget.bookId);
    final notes = await notesRepository.listByBook(widget.bookId);
    if (!mounted) return;
    setState(() {
      _highlights = highlights;
      _notes = notes;
    });
    _sendDecorationsToNative();
  }
```

改為：

```dart
  Future<void> _reloadAnnotationsAndRefreshDecorations() async {
    final session = _annotationSession;
    if (session == null) return;
    final snapshot = await session.reload();
    if (!mounted) return;
    setState(() {
      _highlights = snapshot.highlights;
      _notes = snapshot.notes;
    });
    _sendDecorationsToNative();
  }
```

- [x] **Step 6: 改寫 `_handleDeleteExistingAnnotation`**

找到現有方法（約第 1905-1909 行）：

```dart
  Future<void> _handleDeleteExistingAnnotation(AnnotationListItem item) async {
    await _deleteAnnotationRecords(item);
    await _reloadAnnotationsAndRefreshDecorations();
    _handleCloseAnnotationToolbar();
  }
```

改為：

```dart
  Future<void> _handleDeleteExistingAnnotation(AnnotationListItem item) async {
    final session = _annotationSession;
    if (session == null) return;
    final snapshot = await session.deleteExisting(item);
    if (!mounted) return;
    setState(() {
      _highlights = snapshot.highlights;
      _notes = snapshot.notes;
    });
    _sendDecorationsToNative();
    _handleCloseAnnotationToolbar();
  }
```

**注意：** `_deleteAnnotationRecords()` 方法（約第 1898-1903 行）**先不要刪除**——`_handlePdfDeleteExistingAnnotation`（PDF 側）目前仍呼叫它，會在 Task 7 一併改掉後才刪除整個方法。本 Step 完成後 `_deleteAnnotationRecords` 會暫時變成只被 PDF 側呼叫，這是預期中的過渡狀態。

- [x] **Step 7: 執行測試確認零回歸**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（與 Step 1 記錄的基準線一致，無新增失敗）

- [x] **Step 8: flutter analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 9: Commit**

```bash
git add app/lib/screens/reader_screen.dart
git commit -m "refactor(reader): ReaderScreen EPUB 劃線/備註 CRUD 改用 AnnotationSession"
```

---

### Task 7: ReaderScreen 接上 AnnotationSession（PDF 側），移除 `_deleteAnnotationRecords`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1898-1903`（刪除 `_deleteAnnotationRecords`）、`:1911-1915`（`_handlePdfDeleteExistingAnnotation`）、`:2070-2137`（`_handlePdfHighlightStyleSelected`/`_handlePdfNotePressed`/`_reloadPdfAnnotationsAndSync`）

**Interfaces:**
- Consumes: 同 Task 6（`AnnotationSession`/`AnnotationSnapshot`/`AnnotationLocator`，`_annotationSession` 欄位已於 Task 6 建立）。

- [x] **Step 1: 執行既有測試建立基準線**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（延續 Task 6 完成後的狀態）

- [x] **Step 2: 改寫 `_handlePdfHighlightStyleSelected`**

找到現有方法（約第 2070-2084 行）：

```dart
  Future<void> _handlePdfHighlightStyleSelected(HighlightStyle style) async {
    final selection = _currentPdfSelection;
    final repository = widget.highlightsRepository;
    if (selection == null || repository == null) return;
    final highlightId = const Uuid().v4();
    await repository.insert(Highlight(
      id: highlightId,
      bookId: widget.bookId,
      style: style,
      pdfPageIndex: selection.pageIndex,
      pdfRect: selection.rect,
    ));
    _pendingPdfHighlightIdForSelection = highlightId;
    await _reloadPdfAnnotationsAndSync();
  }
```

改為：

```dart
  Future<void> _handlePdfHighlightStyleSelected(HighlightStyle style) async {
    final selection = _currentPdfSelection;
    final session = _annotationSession;
    if (selection == null || session == null) return;
    final result = await session.createHighlight(
      locator: AnnotationLocator.pdf(pageIndex: selection.pageIndex, rect: selection.rect),
      style: style,
    );
    if (!mounted) return;
    setState(() {
      _highlights = result.snapshot.highlights;
      _notes = result.snapshot.notes;
      _pendingPdfHighlightIdForSelection = result.highlightId;
    });
    _sendPdfAnnotationsToNative();
  }
```

- [x] **Step 3: 改寫 `_handlePdfNotePressed`**

找到現有方法（約第 2086-2119 行）：

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
      initialText: existing?.text ?? '',
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

改為：

```dart
  Future<void> _handlePdfNotePressed() async {
    final selection = _currentPdfSelection;
    final session = _annotationSession;
    if (selection == null || session == null) return;
    final existing = resolvePdfExistingAnnotation(
      selection: selection,
      highlights: _highlights,
      notes: _notes,
    )?.note;
    final text = await showNoteTextDialog(
      context,
      initialText: existing?.text ?? '',
      title: existing != null ? '編輯備註' : '新增備註',
    );
    if (text == null) return;
    final snapshot = await session.createOrUpdateNote(
      locator: AnnotationLocator.pdf(pageIndex: selection.pageIndex, rect: selection.rect),
      text: text,
      existing: existing,
      pendingHighlightId: _pendingPdfHighlightIdForSelection,
    );
    if (!mounted) return;
    setState(() {
      _highlights = snapshot.highlights;
      _notes = snapshot.notes;
      _currentPdfSelection = null;
      _pendingPdfHighlightIdForSelection = null;
    });
    _sendPdfAnnotationsToNative();
  }
```

- [x] **Step 4: 改寫 `_reloadPdfAnnotationsAndSync`**

找到現有方法（約第 2125-2137 行）：

```dart
  Future<void> _reloadPdfAnnotationsAndSync() async {
    final highlightsRepository = widget.highlightsRepository;
    final notesRepository = widget.notesRepository;
    if (highlightsRepository == null || notesRepository == null) return;
    final highlights = await highlightsRepository.listByBook(widget.bookId);
    final notes = await notesRepository.listByBook(widget.bookId);
    if (!mounted) return;
    setState(() {
      _highlights = highlights;
      _notes = notes;
    });
    _sendPdfAnnotationsToNative();
  }
```

改為：

```dart
  Future<void> _reloadPdfAnnotationsAndSync() async {
    final session = _annotationSession;
    if (session == null) return;
    final snapshot = await session.reload();
    if (!mounted) return;
    setState(() {
      _highlights = snapshot.highlights;
      _notes = snapshot.notes;
    });
    _sendPdfAnnotationsToNative();
  }
```

- [x] **Step 5: 改寫 `_handlePdfDeleteExistingAnnotation`，刪除 `_deleteAnnotationRecords`**

找到現有的 `_deleteAnnotationRecords`／`_handlePdfDeleteExistingAnnotation`（約第 1898-1915 行）：

```dart
  Future<void> _deleteAnnotationRecords(AnnotationListItem item) async {
    final note = item.note;
    final highlight = item.highlight;
    if (note != null) await widget.notesRepository!.delete(note.id);
    if (highlight != null) await widget.highlightsRepository!.delete(highlight.id);
  }

  Future<void> _handleDeleteExistingAnnotation(AnnotationListItem item) async {
    // ...（Task 6 已改寫，維持不動）
  }

  Future<void> _handlePdfDeleteExistingAnnotation(AnnotationListItem item) async {
    await _deleteAnnotationRecords(item);
    await _reloadPdfAnnotationsAndSync();
    _handlePdfSelectionCanceled();
  }
```

改為（整個 `_deleteAnnotationRecords` 方法刪除，`_handleDeleteExistingAnnotation` 維持 Task 6 已改寫的版本不動，只改 `_handlePdfDeleteExistingAnnotation`）：

```dart
  Future<void> _handlePdfDeleteExistingAnnotation(AnnotationListItem item) async {
    final session = _annotationSession;
    if (session == null) return;
    final snapshot = await session.deleteExisting(item);
    if (!mounted) return;
    setState(() {
      _highlights = snapshot.highlights;
      _notes = snapshot.notes;
    });
    _sendPdfAnnotationsToNative();
    _handlePdfSelectionCanceled();
  }
```

- [x] **Step 6: 執行測試確認零回歸**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（與 Step 1 記錄的基準線一致，無新增失敗）

- [x] **Step 7: flutter analyze**

Run: `flutter analyze`
Expected: `No issues found!`（確認 `_deleteAnnotationRecords` 刪除後沒有殘留呼叫點、沒有未使用的 import）

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/reader_screen.dart
git commit -m "refactor(reader): ReaderScreen PDF 劃線/備註 CRUD 改用 AnnotationSession，移除 _deleteAnnotationRecords"
```

---

### Task 8: 完整驗證

**Files:** 無新增/修改（純驗證）

- [x] **Step 1: 完整 flutter analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 2: 完整 flutter test**

Run: `flutter test`
Expected: 全數通過，零回歸（若有既有已知不穩定測試案例，比照 `epic-41` 慣例於 PR 描述註明，不視為本 Issue 造成的回歸）

- [x] **Step 3: 於 `plan-issue-1.md` 標記全部 Task 完成**

將本檔案所有 `- [x]` 改為 `- [x]`。

- [x] **Step 4: 發起獨立程式審查**

比照 `docs/agents/issue-tracker.md`／`sdd-workflow` 既有流程，使用 `/superpowers:requesting-code-review` 對本次異動（`git diff` 對比 Task 1 之前的 commit）發起審查，結果存至 `docs/epics/epic-43-reader-architecture-hardening/reviews/review-issue-1.md`（不進版控）。
