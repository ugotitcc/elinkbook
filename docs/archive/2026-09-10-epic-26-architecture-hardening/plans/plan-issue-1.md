# Epic 26 Issue 1 — 收斂書籤 toggle 成一個共用 module 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修復「流式 EPUB 重新開啟已在目前位置有書籤的書、開書後尚未打開過筆記面板時，第一次點擊書籤按鈕會誤判無書籤而重複新增」這個現存 bug，做法是把 EPUB／PDF 兩份幾乎相同的書籤 toggle 演算法收斂成一個共用 module，兩邊皆改為直查 repository 判斷存在性（不依賴可能尚未載入的 `_fxlBookmarks` 記憶體快取），一次修復對兩邊同時生效。

**Architecture:** 新增純 Dart 函式 `toggleBookmark()`（`app/lib/reader/bookmark_toggle.dart`，不依賴 Flutter widget、`BookmarksRepository` 之外無其他外部依賴），簽章為 `matches: bool Function(Bookmark)` ／ `build: Bookmark Function()` 兩個注入參數，內部邏輯為「直查 `repository.listByBook(bookId)` → 用 `matches` 找出目前位置的既有書籤 → 有則 `delete`、無則 `insert(build())`」——與 PDF 端現行 `_togglePdfBookmark()` 已修過的邏輯完全等價，只是抽成可被 EPUB／PDF 兩處呼叫端共用的獨立函式。`reader_screen.dart` 的 `_toggleBookmark()`（EPUB）與 `_togglePdfBookmark()`（PDF）皆改為呼叫這個共用函式，各自只負責傳入格式專屬的比對邏輯（`epubLocatorJson` vs `pdfPageIndex`）與建構邏輯。`_bookmarkAtCurrentPosition`／`_pdfBookmarkAtCurrentPosition` 兩個既有 getter（供星星圖示 UI 顯示用）與 `_fxlBookmarks` 快取本身**維持不變**——candidate 1 的 bug 只在於「用這個可能過期的快取來判斷 toggle 當下的存在性」，快取繼續用於純顯示用途完全沒問題。

**Tech Stack:** Flutter/Dart（純函式 + 既有 `BookmarksRepository` 介面），無新增第三方套件。

## Global Constraints

- 新模組 `toggleBookmark()` 必須是純 Dart 函式（不 import `package:flutter/material.dart` 或任何 widget），確保可被 `app/test/reader/` 下的純邏輯測試直接呼叫，不需要 `flutter_test` 的 widget pump 儀式。
- `_bookmarkAtCurrentPosition`／`_pdfBookmarkAtCurrentPosition`／`_fxlBookmarks` 三者不得刪除或改變既有語意——它們仍是 UI 顯示（星星圖示狀態、Notes 面板書籤分頁）的唯一資料來源，本次修復範圍只限「toggle 當下的存在性判斷」這一件事。
- `_toggleBookmark()`／`_togglePdfBookmark()` 重構後，函式簽章（無參數、回傳 `Future<void>`）與既有呼叫端（FAB `onPressed`、`ReaderScreen.togglePdfBookmark` static seam）的呼叫方式不得改變。
- 每個 Task 完成後須讓 `docs/epics/epic-26-architecture-hardening/issues.md` Issue 1 保持可追蹤——Task 3 收尾時更新其 `Status` 行為已修復。
- 提交前必須 `flutter analyze` 乾淨（"No issues found!"），`flutter test` 全數通過，不得有回歸。

---

### Task 1：建立共用 `toggleBookmark()` module 與其單元測試

**Files:**
- Create: `app/lib/reader/bookmark_toggle.dart`
- Create: `app/test/reader/bookmark_toggle_test.dart`

**Interfaces:**
- Consumes：既有 `Bookmark`（`app/lib/reader/bookmark.dart`）、`BookmarksRepository`（`app/lib/reader/bookmarks_repository.dart`，`insert`/`listByBook`/`delete` 方法）。
- Produces：`Future<void> toggleBookmark({required BookmarksRepository repository, required String bookId, required bool Function(Bookmark bookmark) matches, required Bookmark Function() build})`——Task 2／Task 3 會直接呼叫這個函式簽章，名稱與參數順序須完全一致。

- [ ] **Step 1：寫失敗測試——目前位置無書籤時應新增**

建立 `app/test/reader/bookmark_toggle_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmark_toggle.dart';
import '../support/fake_bookmarks_repository.dart';

void main() {
  test('目前位置無書籤時，呼叫後新增一筆（build() 提供的內容）', () async {
    final repository = FakeBookmarksRepository();

    await toggleBookmark(
      repository: repository,
      bookId: 'b1',
      matches: (b) => b.epubLocatorJson == 'loc-a',
      build: () => Bookmark(
        id: 'new-id',
        bookId: 'b1',
        name: '書籤 A',
        epubLocatorJson: 'loc-a',
      ),
    );

    final saved = await repository.listByBook('b1');
    expect(saved, hasLength(1));
    expect(saved.single.id, 'new-id');
    expect(saved.single.epubLocatorJson, 'loc-a');
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/reader/bookmark_toggle_test.dart`
Expected: FAIL（`bookmark_toggle.dart` 不存在，`Target of URI doesn't exist`）。

- [ ] **Step 3：實作最小可行版本**

建立 `app/lib/reader/bookmark_toggle.dart`：

```dart
import 'bookmark.dart';
import 'bookmarks_repository.dart';

/// 收斂 EPUB／PDF 書籤 toggle 成一個共用 module（Epic 26 Issue 1）：兩者
/// 原本各自實作幾乎相同的「查 repository → 比對目前位置是否已有書籤 →
/// insert/delete」演算法，PDF 端已修過的「存在性判斷直查 repository、
/// 不依賴呼叫端記憶體快取」競態修復從未傳到 EPUB 端——EPUB 端原本用
/// 可能尚未載入的 `_fxlBookmarks` 快取判斷，開書後在使用者尚未打開過
/// 筆記面板前第一次點擊書籤按鈕會誤判無書籤而重複新增（見
/// `reviews/bugfix-repro.md`）。呼叫端各自傳入比對邏輯（[matches]：EPUB
/// 用 `epubLocatorJson`、PDF 用 `pdfPageIndex`）與建構邏輯（[build]），
/// 存在性判斷一律直查 [repository]，不依賴呼叫端任何快取是否已載入。
Future<void> toggleBookmark({
  required BookmarksRepository repository,
  required String bookId,
  required bool Function(Bookmark bookmark) matches,
  required Bookmark Function() build,
}) async {
  final all = await repository.listByBook(bookId);
  Bookmark? existing;
  for (final bookmark in all) {
    if (matches(bookmark)) {
      existing = bookmark;
      break;
    }
  }
  if (existing != null) {
    await repository.delete(existing.id);
  } else {
    await repository.insert(build());
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run: `cd app && flutter test test/reader/bookmark_toggle_test.dart`
Expected: PASS（1 項測試）。

- [ ] **Step 5：補上「目前位置已有書籤時應刪除」與「多筆書籤時 matches 挑出正確那一筆」兩項測試**

在 `app/test/reader/bookmark_toggle_test.dart` 的 `main()` 內、既有 `test(...)` 之後補上：

```dart
  test('目前位置已有書籤時，呼叫後刪除該筆（而非重複新增）', () async {
    final repository = FakeBookmarksRepository();
    await repository.insert(Bookmark(
      id: 'existing-id',
      bookId: 'b1',
      name: '既有書籤',
      epubLocatorJson: 'loc-a',
    ));

    await toggleBookmark(
      repository: repository,
      bookId: 'b1',
      matches: (b) => b.epubLocatorJson == 'loc-a',
      build: () => Bookmark(
        id: 'should-not-be-used',
        bookId: 'b1',
        name: '不應被插入',
        epubLocatorJson: 'loc-a',
      ),
    );

    final saved = await repository.listByBook('b1');
    expect(saved, isEmpty);
  });

  test('repository 有多筆書籤時，只刪除 matches 命中的那一筆', () async {
    final repository = FakeBookmarksRepository();
    await repository.insert(Bookmark(
      id: 'other-position',
      bookId: 'b1',
      name: '別的位置',
      epubLocatorJson: 'loc-b',
    ));
    await repository.insert(Bookmark(
      id: 'target-position',
      bookId: 'b1',
      name: '目標位置',
      epubLocatorJson: 'loc-a',
    ));

    await toggleBookmark(
      repository: repository,
      bookId: 'b1',
      matches: (b) => b.epubLocatorJson == 'loc-a',
      build: () => throw StateError('不應被呼叫'),
    );

    final saved = await repository.listByBook('b1');
    expect(saved, hasLength(1));
    expect(saved.single.id, 'other-position');
  });
```

- [ ] **Step 6：執行測試確認全數通過**

Run: `cd app && flutter test test/reader/bookmark_toggle_test.dart`
Expected: PASS（3 項測試）。

- [ ] **Step 7：Commit**

```bash
git add app/lib/reader/bookmark_toggle.dart app/test/reader/bookmark_toggle_test.dart
git commit -m "feat(epic-26): Issue 1——新增共用 toggleBookmark() module（純邏輯＋單元測試）"
```

---

### Task 2：EPUB `_toggleBookmark()` 改用共用 module，補上永久回歸測試

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:736-756`（`_toggleBookmark()`）、新增 import
- Modify: `app/test/screens/reader_screen_test.dart`（新增永久回歸測試，緊接在既有「流式 EPUB：點擊浮動書籤 toggle 按鈕可新增/移除目前頁書籤」測試之後，約 line 3736 附近）

**Interfaces:**
- Consumes：Task 1 的 `toggleBookmark({required BookmarksRepository repository, required String bookId, required bool Function(Bookmark) matches, required Bookmark Function() build})`。
- Produces：`_toggleBookmark()` 對外行為不變（`Future<void> Function()`，FAB `onPressed: _epubPositionInfo == null ? null : _toggleBookmark` 呼叫方式不變）。

- [ ] **Step 1：寫失敗測試——重現候選 1 的症狀（永久回歸測試）**

在 `app/test/screens/reader_screen_test.dart`，緊接在既有「流式 EPUB：點擊浮動書籤 toggle 按鈕可新增/移除目前頁書籤（複用泛用化後的 _toggleBookmark，Issue 7）」測試（約 line 3736）之後，新增：

```dart
  testWidgets(
    '流式 EPUB：重新開啟已在目前位置有書籤的書，開書後未打開過筆記面板時第一次點擊書籤按鈕應刪除既有書籤而非重複新增（Epic 26 Issue 1 回歸測試）',
    (tester) async {
      const locatorJson = '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}';
      final bookmarksRepository = FakeBookmarksRepository();
      // 模擬「先前已在此位置加過書籤」：重開書時 repository 已有一筆。
      await bookmarksRepository.insert(Bookmark(
        id: 'existing-bookmark',
        bookId: 'b_epic26_issue1',
        name: '既有書籤',
        epubLocatorJson: locatorJson,
        progression: 0.1,
      ));

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_epic26_issue1',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateEpubReaderView>(
        find.byType(FoliateEpubReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: locatorJson,
          progression: 0.1,
          pageIndex: 0,
          totalPages: 10,
        ),
      );
      await tester.pump();

      // 刻意不打開 NotesBottomSheet——重現「_fxlBookmarks 快取從未被
      // 預先載入」的狀態，開書後直接第一次點擊書籤按鈕。
      final finder = find.byKey(
        const Key('reader_foliate_bookmark_toggle_button'),
      );

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        (tester.widget<IconButton>(finder).icon as Icon).icon,
        Icons.star_border,
        reason: '既有書籤應已被刪除，圖示應變回未加書籤狀態',
      );

      final afterTap = await bookmarksRepository.listByBook(
        'b_epic26_issue1',
      );
      expect(
        afterTap,
        hasLength(0),
        reason: '目前位置已有書籤時第一次點擊應是刪除，不應變成重複新增',
      );
    },
  );
```

- [ ] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "Epic 26 Issue 1 回歸測試"`
Expected: FAIL（`afterTap` 長度為 2，而非預期的 0——與 `reviews/bugfix-repro.md` 記錄的重現結果一致）。

- [ ] **Step 3：新增 import**

修改 `app/lib/screens/reader_screen.dart`，在既有 `import '../reader/bookmark_position_context.dart';`（第 10 行）之後新增：

```dart
import '../reader/bookmark_toggle.dart' as bookmark_toggle;
```

（使用 `as bookmark_toggle` 前綴避免與本檔案內既有 `_toggleBookmark`／`_togglePdfBookmark` 方法名稱在閱讀時混淆，呼叫時寫成 `bookmark_toggle.toggleBookmark(...)`。）

- [ ] **Step 4：`_toggleBookmark()` 改用共用 module**

修改 `app/lib/screens/reader_screen.dart:736-756`，從：

```dart
  Future<void> _toggleBookmark() async {
    final repository = widget.bookmarksRepository;
    final positionInfo = _epubPositionInfo;
    if (repository == null || positionInfo == null) return;
    final existing = _bookmarkAtCurrentPosition;
    if (existing != null) {
      await repository.delete(existing.id);
    } else {
      await repository.insert(Bookmark(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        name: Bookmark.defaultName(BookmarkPositionContext(
          epubLocatorJson: positionInfo.locatorJson,
          progression: positionInfo.progression,
        )),
        epubLocatorJson: positionInfo.locatorJson,
        progression: positionInfo.progression,
      ));
    }
    await _loadFxlBookmarks();
  }
```

改為：

```dart
  Future<void> _toggleBookmark() async {
    final repository = widget.bookmarksRepository;
    final positionInfo = _epubPositionInfo;
    if (repository == null || positionInfo == null) return;
    await bookmark_toggle.toggleBookmark(
      repository: repository,
      bookId: widget.bookId,
      matches: (bookmark) =>
          bookmark.epubLocatorJson == positionInfo.locatorJson,
      build: () => Bookmark(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        name: Bookmark.defaultName(BookmarkPositionContext(
          epubLocatorJson: positionInfo.locatorJson,
          progression: positionInfo.progression,
        )),
        epubLocatorJson: positionInfo.locatorJson,
        progression: positionInfo.progression,
      ),
    );
    await _loadFxlBookmarks();
  }
```

- [ ] **Step 5：執行新測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "Epic 26 Issue 1 回歸測試"`
Expected: PASS。

- [ ] **Step 6：執行既有 EPUB 書籤測試確認無回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "書籤"`
Expected: 全數 PASS（含既有「流式 EPUB：點擊浮動書籤 toggle 按鈕可新增/移除目前頁書籤」等測試）。

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-26): Issue 1——EPUB _toggleBookmark() 改用共用 toggleBookmark() module，修復快取未載入誤判無書籤"
```

---

### Task 3：PDF `_togglePdfBookmark()` 改用共用 module，全量回歸驗證，收尾文件更新

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:762-787`（`_togglePdfBookmark()`）
- Modify: `docs/epics/epic-26-architecture-hardening/issues.md`（Issue 1 `Status` 行）
- Modify: `docs/epics.md`（epic-26 該列備註）

**Interfaces:**
- Consumes：Task 1 的 `bookmark_toggle.toggleBookmark(...)`（同 Task 2）。
- Produces：`_togglePdfBookmark()` 對外行為不變（`Future<void> Function()`，`ReaderScreen.togglePdfBookmark` static seam 呼叫方式不變）。

- [ ] **Step 1：`_togglePdfBookmark()` 改用共用 module**

修改 `app/lib/screens/reader_screen.dart:762-787`，從：

```dart
  Future<void> _togglePdfBookmark() async {
    final repository = widget.bookmarksRepository;
    final pageIndex = _pdfPageInfo?.pageIndex;
    if (repository == null || pageIndex == null) return;
    // 直接查詢 repository 而非依賴 _fxlBookmarks 快取，避免快取尚未載入時
    // 導致重複新增（見 issue-4 測試修正）。
    final all = await repository.listByBook(widget.bookId);
    Bookmark? existing;
    for (final b in all) {
      if (b.pdfPageIndex == pageIndex) {
        existing = b;
        break;
      }
    }
    if (existing != null) {
      await repository.delete(existing.id);
    } else {
      await repository.insert(Bookmark(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        name: Bookmark.defaultName(BookmarkPositionContext(pdfPageIndex: pageIndex)),
        pdfPageIndex: pageIndex,
      ));
    }
    await _loadFxlBookmarks();
  }
```

改為：

```dart
  Future<void> _togglePdfBookmark() async {
    final repository = widget.bookmarksRepository;
    final pageIndex = _pdfPageInfo?.pageIndex;
    if (repository == null || pageIndex == null) return;
    await bookmark_toggle.toggleBookmark(
      repository: repository,
      bookId: widget.bookId,
      matches: (bookmark) => bookmark.pdfPageIndex == pageIndex,
      build: () => Bookmark(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        name: Bookmark.defaultName(BookmarkPositionContext(pdfPageIndex: pageIndex)),
        pdfPageIndex: pageIndex,
      ),
    );
    await _loadFxlBookmarks();
  }
```

- [ ] **Step 2：執行既有 PDF 書籤測試確認無回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart --plain-name "PDF 書籤 toggle"`
Expected: 全數 PASS（「目前頁無書籤時呼叫後新增一筆，頁碼定位正確」／「目前頁已有書籤時呼叫後移除該筆」兩項既有測試）。

- [ ] **Step 3：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`（確認新 import、`Bookmark`/`BookmarkPositionContext` 是否仍在 `reader_screen.dart` 中被使用——`_toggleBookmark()`／`_togglePdfBookmark()` 的 `build:` 閉包仍會用到兩者，不會產生 unused-import 警告）。

- [ ] **Step 4：執行完整測試套件確認全域無回歸**

Run: `cd app && flutter test`
Expected: 全數通過（含新增的 `bookmark_toggle_test.dart` 3 項、`reader_screen_test.dart` 新增的 1 項回歸測試，以及既有全部測試）。

- [ ] **Step 5：更新 `issues.md` Issue 1 狀態**

修改 `docs/epics/epic-26-architecture-hardening/issues.md`，把 Issue 1 的 `Status` 行：

```markdown
**Status:** `ready-for-agent`——根因已由 `/diagnose` 確認（原始碼交叉核對＋widget test 重現），修法方向明確（比照 PDF 端已修過的版本），無需進一步 Discovery/Architecting，可直接進入 `/plan-issue`。
```

改為：

```markdown
**Status:** ✅ 已修復。新增純 Dart 共用 module `app/lib/reader/bookmark_toggle.dart`（`toggleBookmark()`，`matches`/`build` 參數化），EPUB `_toggleBookmark()`／PDF `_togglePdfBookmark()` 皆改為呼叫此 module、存在性判斷一律直查 `BookmarksRepository`，不再依賴可能尚未載入的 `_fxlBookmarks` 快取。`bookmark_toggle_test.dart`（3 項純邏輯單元測試）＋ `reader_screen_test.dart` 新增的永久回歸測試（重現「重開已加書籤的流式 EPUB、未開過筆記面板時第一次點擊誤新增重複書籤」symptom，修復後轉為不再誤觸發）皆通過；既有 EPUB／PDF 書籤 toggle 測試零回歸；`flutter analyze` 乾淨。
```

- [ ] **Step 6：更新 `docs/epics.md` epic-26 該列備註**

修改 `docs/epics.md` 的 `epic-26-architecture-hardening` 該列（搜尋 `epic-26-architecture-hardening`），在既有備註文字最後（`...待 Issue 1 驗證「抽 module 有效」後視優先順序評估是否納入。` 之後、表格儲存格結尾 ` |` 之前）補上一句：

```markdown
**Issue 1 已完成並修復（未走完整 PR 流程，直接於 `main` 上完成——變更範圍小、風險低，比照小型技術債修復慣例）**：新增共用 `toggleBookmark()` module，EPUB／PDF 書籤 toggle 存在性判斷皆改為直查 repository，一次修復兩邊；`bookmark_toggle_test.dart`＋`reader_screen_test.dart` 回歸測試皆通過，`flutter test`／`flutter analyze` 全數乾淨。
```

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/reader_screen.dart docs/epics/epic-26-architecture-hardening/issues.md docs/epics.md
git commit -m "fix(epic-26): Issue 1——PDF _togglePdfBookmark() 改用共用 toggleBookmark() module，結案"
```

---

## Self-Review

- **Spec 覆蓋度**：`issues.md` Issue 1 的「Solution」（抽出共用 module，EPUB／PDF 皆改用直查 repository 版本）由 Task 1（module 本體）＋ Task 2（EPUB 呼叫端）＋ Task 3（PDF 呼叫端）完整覆蓋；「單元測試要求」三項（永久回歸測試、既有測試不回歸、EPUB/PDF 共用同一 module 後其中一邊的競態測試對另一邊同樣有效）分別對應 Task 2 Step 1、Task 2 Step 6／Task 3 Step 2、Task 1（同一個 `toggleBookmark()` 函式，非各自兩份重複實作，語意上已滿足「刪除測試」精神——若把其中一份呼叫端實作刪掉、改呼叫共用 module，複雜度確實下降）。
- **No Placeholders 掃描**：三個 Task 的程式碼、測試程式碼、預期輸出皆為實際可執行內容，非佔位符；`Step 2` 的「Expected: FAIL」皆說明了失敗原因（對應目前程式碼實際會發生的行為），非空泛描述。
- **型別/介面一致性**：`toggleBookmark()` 的參數名稱（`repository`／`bookId`／`matches`／`build`）與回傳型別（`Future<void>`）在 Task 1 定義後，Task 2／Task 3 呼叫端逐字沿用，未出現改名不一致。`_toggleBookmark()`／`_togglePdfBookmark()` 對外簽章（無參數、`Future<void>` 回傳）維持不變，FAB `onPressed` 與 `ReaderScreen.togglePdfBookmark` static seam 兩處既有呼叫端不需要跟著修改。
- **既有測試不回歸的具體論證**：重構只改變「如何判斷目前位置是否已有書籤」這一段邏輯的呼叫方式（從各自內嵌改為呼叫共用函式），前後行為完全等價（PDF 端邏輯本來就是直查 repository，搬進共用函式只是換了呼叫方式；EPUB 端邏輯改為與 PDF 端等價的直查版本，這正是本次要修的 bug 本身）；`_bookmarkAtCurrentPosition`／`_pdfBookmarkAtCurrentPosition`／`_fxlBookmarks`／`_loadFxlBookmarks()` 皆未變動，UI 顯示邏輯不受影響。Task 2 Step 6、Task 3 Step 2 皆安排重跑既有書籤測試作為實測佐證，Task 3 Step 4 額外安排全域測試套件執行。
- **範圍誠實聲明**：本計畫刻意不處理架構檢視報告候選 2/3/6/4/5/7——`issues.md` 已明確記錄僅候選 1 拆案，其餘候選待本 Issue 驗證「抽 module 有效」後再評估。
