# Issue 7：位置儲存規則搬出 `ReaderScreen` 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 把 `ReaderScreen._writeCurrentPosition()` 內「此刻要不要儲存閱讀位置、要存什麼」的規則，連同 `_hasRelocatedSinceOpen` 旗標，搬進一個不依賴 Widget 的新 module `ReadingPositionSaver`，讓規則可以用單元測試直接驗證；`ReaderScreen` 行為零變化。

**Architecture：** 新增 `app/lib/reader/reading_position_saver.dart`。它**擁有**「最新一筆 PDF／Foliate 位置回報」與「各格式開書後是否已重新定位」的狀態（PDF、Foliate 各一個旗標），並提供三個動作：收到 PDF 頁碼回報、收到 Foliate 定位回報、依格式儲存。`ReaderScreen` 仍保留自己的 `_pdfPageInfo`／`_epubPositionInfo`（它們同時驅動頁尾 UI），只在回呼中多轉發一次給 saver；`_writeCurrentPosition()` 刪除，兩個呼叫點（進入背景、dispose）直接呼叫 saver。saver 在偏好載入完成的同一個 `setState` 裡建立（與 `_initialPosition` 同時賦值）。

**旗標拆分的說明**：現有程式只有一個 `_hasRelocatedSinceOpen`，由 PDF 與 Foliate 兩個回呼共用。但一個畫面只會開一本書、只會收到其中一種格式的回報，所以拆成每種格式各一個旗標，**可觀察行為與現有完全相同**；拆開的好處是 saver 的 interface 不必隱含「兩種格式不會同時出現」這個前提。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立的 `spec.md`，設計依據是 2026-10-02 `/improve-codebase-architecture`＋`/grilling` 的決策，記錄於 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 7、8 設計決策」；詞彙見 `CONTEXT.md`「位置儲存規則」。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **純重構、零行為變化**（epic.md 決策 6）：以下三點逐字保留，不得「順便修好」——(1) 位置寫入不 await（`saveReadingPosition` 回傳的 `Future` 照舊直接丟掉，不加 `await`、不加 `unawaited`，與現有程式碼一致）；(2) `dispose` 與 `paused` 的呼叫順序不變（dispose 內「寫位置」仍排在「觸發 Checkpoint」之前，`paused` 仍不觸發 Checkpoint）；(3) 儲存規則的結果不變（見 Task 1 的規則表；唯一的結構差異是旗標由共用一個改為每種格式各一個，可觀察行為相同，理由見 Architecture）。
- **範圍外**：不動 `SyncEngine`（它直接寫 `books` 表是另一個問題，見 epic.md）；不動 `ReadingPositionRepository`、`ReaderPrefsManager` 的介面；不動閱讀活動判定（`_recordReadingActivity`、`_locatorPositionKey`，屬 Issue 8）；不新增 `ReaderScreen` 建構參數。
- **`ReaderScreen` 保留自己的 `_pdfPageInfo`／`_epubPositionInfo`**：它們還驅動頁尾顯示與閱讀活動判定，不得移除。
- **測試原則（replace, don't layer）**：規則類案例放在新的單元測試；`reader_screen_test.dart` 只保留「接線」案例（確認 dispose／paused 會觸發儲存、確認畫面把 `initialJumpTarget != null` 與兩種格式的位置回報轉發給 saver）。**盤點結果（2026-10-02 審查後）：`reader_screen_test.dart` 現有引用位置儲存的案例全部屬於接線或開書位置選擇，沒有可刪的純規則案例，所以本 Issue 不刪任何既有 widget 測試**；反而發現 Foliate 路徑沒有任何接線案例，Task 2 補一個。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，用 `run_in_background`）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：用 Bash 工具（Git Bash）；`python` 不可用來編輯檔案；多數原始檔是 CRLF，Edit 的定位字串不要含換行。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：直接 TDD＋本計畫；程式審查先出報告（存於 `reviews/`，gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。

## Review Focus

最可能咬到使用者的情況（依可能性排序），每條都有對應測試：

1. **從搜尋結果或書籤跳進去、看一眼就離開，卻把原本讀到一半的位置蓋掉。** 這是這段規則存在的原因。→ Task 1 測「有跳轉目標、只回報一次」不儲存（PDF 與 Foliate 各一）；Task 2 保留 widget 層的接線測試。
2. **跳轉後使用者翻了頁，位置卻不被儲存（旗標沒設到）。** 搬動旗標最容易漏設。→ Task 1 測「有跳轉目標、第二次回報後」會儲存（PDF 與 Foliate 各一）；旗標原本在兩個回呼各自設定，是遷移最容易漏的地方；Task 2 補 Foliate 路徑的接線測試，確認 `onLocatorChanged` 真的轉發給 saver（現有 widget 測試只涵蓋 PDF）。
3. **Foliate 的 `progression` 為 null（早期定位、固定版面）時，進度被倒退成 0%。** → Task 1 測「沿用開書時的進度」與「開書時也沒有進度就不儲存」。
4. **PDF `totalPages` 為 0 時除以零。** → Task 1 測進度為 0 而不是例外。
5. **書籍尚未回報任何位置（開書失敗、剛開就離開）時儲存。** 不得覆寫資料庫既有記錄，也不得因 saver 尚未建立而拋例外（偏好尚未載入完成就 dispose）。→ Task 1 測「沒有任何回報不儲存」；Task 2 所有呼叫點（回呼、dispose、paused）一律以 `?.` 呼叫，既有「尚未收到任何 onPageChanged 時 dispose 不儲存」案例涵蓋 dispose 端。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/reading_position_saver.dart` | 新增 | `ReadingPositionSaver`：持有最新位置回報與「已重新定位」旗標，依格式決定儲存內容 |
| `app/test/reader/reading_position_saver_test.dart` | 新增 | 以 `FakeReaderPrefsManager` 直接驗證五條規則 |
| `app/lib/screens/reader_screen.dart` | 修改 | 刪除 `_writeCurrentPosition`、`_hasRelocatedSinceOpen`；新增 `_positionSaver` 欄位與三處轉發／呼叫 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 既有案例全部保留（皆為接線）；新增 `paused` 與 Foliate 兩個接線案例 |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 開發記錄、狀態 |

---

### Task 0：提交計畫、建立 worktree

**Files：**
- Commit：本計畫檔與 `issues.md` 狀態更新（在 `main` 上，純文件）
- 建立 worktree：`.worktrees/epic-54-issue-7-position-saver`（`.worktrees/` 已 gitignore）

**Interfaces：**
- Consumes：無。
- Produces：分支 `epic-54/issue-7-position-saver`，後續 Task 都在這個 worktree 的 `app/` 下執行。

- [ ] **Step 1：在 `main` 提交計畫**

先把 `issues.md` 第 7 列狀態由「⚪ 未開始」改為「🟡 進行中（計畫已寫）」，然後：

```bash
cd /c/Users/fycdc/AI/elinkBook
git add docs/epics/epic-54-architecture-optimization/plans/plan-issue-7.md docs/epics/epic-54-architecture-optimization/issues.md
git commit -m "docs(epic-54): Issue 7 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2：建立 worktree 並安裝依賴**

```bash
git worktree add .worktrees/epic-54-issue-7-position-saver -b epic-54/issue-7-position-saver
cd .worktrees/epic-54-issue-7-position-saver/app && flutter pub get
```

預期：`Got dependencies!`。

- [ ] **Step 3：確認基準測試通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

預期：全數通過（記下通過數，Task 2 完成後應為這個數字 + 2）。

---

### Task 1：`ReadingPositionSaver` 與單元測試

**Files：**
- Create：`app/lib/reader/reading_position_saver.dart`
- Test：`app/test/reader/reading_position_saver_test.dart`

**Interfaces：**
- Consumes：`ReaderPrefsManager.saveReadingPosition(String bookId, ReadingPosition position)`（`lib/reader/reader_prefs_manager.dart:49`）、`ReadingPosition`、`EpubPositionInfo`、`PdfPageInfo`、`BookFormat`。
- Produces（Task 2 依賴）：

```dart
class ReadingPositionSaver {
  ReadingPositionSaver({
    required String bookId,
    required ReaderPrefsManager prefsManager,
    required bool hasJumpTarget,   // widget.initialJumpTarget != null
    double? initialProgress,       // 開書時既有位置的 progress（_initialPosition?.progress）
  });
  void onPdfPageChanged(PdfPageInfo info);
  void onEpubLocated(EpubPositionInfo info);
  void save(BookFormat format);
}
```

**儲存規則表**（對照現有 `_writeCurrentPosition`，順序即判斷順序）：

| # | 條件 | 結果 |
|---|---|---|
| 1 | 格式為 `unknown` | 不儲存 |
| 2 | PDF 或 Foliate，且 `hasJumpTarget` 但該格式尚未重新定位 | 不儲存 |
| 3 | PDF 且尚無頁碼回報 | 不儲存 |
| 4 | PDF | 存 `pdfPageIndex`，進度 = `totalPages > 0 ? (pageIndex+1)/totalPages : 0` |
| 5 | Foliate 格式（epub／azw3／cbz／txt／md）且尚無定位回報 | 不儲存 |
| 6 | Foliate 且 `progression != null` | 存 `epubLocatorJson`，進度 = `progression` |
| 7 | Foliate 且 `progression == null` 且 `initialProgress != null` | 存 `epubLocatorJson`，進度 = `initialProgress` |
| 8 | Foliate 且 `progression == null` 且 `initialProgress == null` | 不儲存 |

「已重新定位」＝該格式的第二次（含）以後回報（第一次回報是開書後套用跳轉目標的初始定位），PDF 與 Foliate 各有自己的旗標。現有程式是兩種格式共用一個旗標，但一個畫面只會收到一種格式的回報，所以可觀察行為相同（見 Architecture 的「旗標拆分的說明」）。表中 #1 與 #2 的先後在實作上不影響結果（`unknown` 格式不會有回報），故不再逐字保留原本「旗標檢查在格式分派之前」的寫法。

- [ ] **Step 1：寫失敗測試**

建立 `app/test/reader/reading_position_saver_test.dart`：

```dart
import 'package:elinkbook/reader/book_format.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/reading_position_saver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_reader_prefs_manager.dart';

void main() {
  late FakeReaderPrefsManager prefs;

  ReadingPositionSaver buildSaver({
    bool hasJumpTarget = false,
    double? initialProgress,
  }) =>
      ReadingPositionSaver(
        bookId: 'b1',
        prefsManager: prefs,
        hasJumpTarget: hasJumpTarget,
        initialProgress: initialProgress,
      );

  setUp(() => prefs = FakeReaderPrefsManager());

  group('尚未收到任何回報', () {
    test('PDF 不儲存', () {
      buildSaver().save(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('Foliate 格式不儲存（逐一涵蓋五種格式）', () {
      for (final format in [
        BookFormat.epub,
        BookFormat.azw3,
        BookFormat.cbz,
        BookFormat.txt,
        BookFormat.md,
      ]) {
        buildSaver().save(format);
      }
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('unknown 格式即使有回報也不儲存', () {
      final saver = buildSaver();
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 1, totalPages: 4));
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{}', progression: 0.5));
      saver.save(BookFormat.unknown);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });
  });

  group('PDF', () {
    test('儲存頁碼，進度為 (頁碼+1)/總頁數', () {
      final saver = buildSaver();
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 3, totalPages: 10));
      saver.save(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls, hasLength(1));
      expect(prefs.savedReadingPositionCalls.single.key, 'b1');
      expect(
        prefs.savedReadingPositionCalls.single.value,
        const ReadingPosition(pdfPageIndex: 3, progress: 0.4),
      );
    });

    test('總頁數為 0 時進度為 0，不拋例外', () {
      final saver = buildSaver();
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 0, totalPages: 0));
      saver.save(BookFormat.pdf);
      expect(
        prefs.savedReadingPositionCalls.single.value,
        const ReadingPosition(pdfPageIndex: 0, progress: 0),
      );
    });

    test('以最新一次回報為準', () {
      final saver = buildSaver();
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 1, totalPages: 10));
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 5, totalPages: 10));
      saver.save(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls.single.value.pdfPageIndex, 5);
    });
  });

  group('Foliate 格式', () {
    test('有 progression 時儲存定位點與該進度', () {
      final saver = buildSaver(initialProgress: 0.1);
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{"cfi":"a"}', progression: 0.7));
      saver.save(BookFormat.epub);
      expect(
        prefs.savedReadingPositionCalls.single.value,
        const ReadingPosition(epubLocatorJson: '{"cfi":"a"}', progress: 0.7),
      );
    });

    test('progression 為 null 時沿用開書時的進度，不倒退成 0', () {
      final saver = buildSaver(initialProgress: 0.8);
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{"cfi":"b"}'));
      saver.save(BookFormat.cbz);
      expect(
        prefs.savedReadingPositionCalls.single.value,
        const ReadingPosition(epubLocatorJson: '{"cfi":"b"}', progress: 0.8),
      );
    });

    test('progression 為 null 且開書時也沒有進度，不儲存', () {
      final saver = buildSaver();
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{"cfi":"c"}'));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });
  });

  group('有跳轉目標（例如從搜尋結果開書）', () {
    test('PDF：只有開書後第一次回報就離開，不儲存，保留既有位置', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 2, totalPages: 5));
      saver.save(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('PDF：使用者翻頁後（第二次回報）才儲存', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 2, totalPages: 5));
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 3, totalPages: 5));
      saver.save(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls.single.value.pdfPageIndex, 3);
    });

    test('Foliate：只有第一次回報就離開，不儲存', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{"cfi":"j"}', progression: 0.2));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('Foliate：第二次回報後才儲存', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{"cfi":"j"}', progression: 0.2));
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{"cfi":"k"}', progression: 0.3));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls.single.value.epubLocatorJson, '{"cfi":"k"}');
    });

    test('PDF 與 Foliate 的「已重新定位」各自獨立', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 1, totalPages: 5));
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 2, totalPages: 5));
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{}', progression: 0.1));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });
  });

  group('沒有跳轉目標（一般開書）', () {
    test('第一次回報就可以儲存', () {
      final saver = buildSaver();
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 0, totalPages: 5));
      saver.save(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls, hasLength(1));
    });
  });

  test('每次呼叫 save 都各自儲存一次', () {
    final saver = buildSaver();
    saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 1, totalPages: 5));
    saver.save(BookFormat.pdf);
    saver.save(BookFormat.pdf);
    expect(prefs.savedReadingPositionCalls, hasLength(2));
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

```bash
flutter test test/reader/reading_position_saver_test.dart
```

預期：編譯失敗，`reading_position_saver.dart` 不存在。

- [ ] **Step 3：寫最小實作**

建立 `app/lib/reader/reading_position_saver.dart`：

```dart
import 'book_format.dart';
import 'epub_position_info.dart';
import 'pdf_page_info.dart';
import 'reader_prefs_manager.dart';
import 'reading_position.dart';

/// 一次閱讀會話內「此刻要不要儲存閱讀位置、要存什麼」的規則（見
/// `CONTEXT.md`「位置儲存規則」，`epic-54-architecture-optimization`
/// Issue 7）。
///
/// 擁有最新一筆 PDF／Foliate 位置回報，以及各格式「開書後是否已重新定位」
/// 旗標。呼叫端在每次收到位置回報時轉發進來，在進入背景與離開畫面時呼叫
/// [save]。
///
/// [save] 不等待儲存完成；沒趕上的位置由下一次 Checkpoint 同步補送。
class ReadingPositionSaver {
  ReadingPositionSaver({
    required this.bookId,
    required this.prefsManager,
    required this.hasJumpTarget,
    this.initialProgress,
  });

  final String bookId;
  final ReaderPrefsManager prefsManager;

  /// 開書時是否帶有跳轉目標（例如從搜尋結果、書籤開啟）。
  final bool hasJumpTarget;

  /// 開書時資料庫既有位置的進度；Foliate 定位尚未解析出 progression 時沿用，
  /// 避免把已讀大半的書靜默倒退回 0%。
  final double? initialProgress;

  PdfPageInfo? _pdfInfo;
  EpubPositionInfo? _epubInfo;

  /// 只在 [hasJumpTarget] 為 true 時有意義：某格式第二次（含）以後的位置回報
  /// 才代表使用者離開了跳轉目標本身（第一次回報是套用跳轉目標後的初始定位）。
  /// 不論觸發來源是翻頁熱區、音量鍵、目錄／書籤跳轉或書內搜尋，都走同一組
  /// 回報，所以這個判斷涵蓋所有導覽方式。單向轉換（false → true）。
  bool _hasRelocatedPdf = false;
  bool _hasRelocatedEpub = false;

  void onPdfPageChanged(PdfPageInfo info) {
    if (_pdfInfo != null) _hasRelocatedPdf = true;
    _pdfInfo = info;
  }

  void onEpubLocated(EpubPositionInfo info) {
    if (_epubInfo != null) _hasRelocatedEpub = true;
    _epubInfo = info;
  }

  /// 依 [format] 決定要不要儲存、存什麼；規則見類別文件與 `CONTEXT.md`。
  void save(BookFormat format) {
    switch (format) {
      case BookFormat.pdf:
        // 跳轉後尚未重新定位：保留資料庫既有位置，避免使用者只是看一下搜尋
        // 結果就離開，卻把原本讀到一半的進度覆蓋成跳轉目標本身。
        if (hasJumpTarget && !_hasRelocatedPdf) return;
        final info = _pdfInfo;
        if (info == null) return;
        prefsManager.saveReadingPosition(
          bookId,
          ReadingPosition(
            pdfPageIndex: info.pageIndex,
            progress: info.totalPages > 0
                ? (info.pageIndex + 1) / info.totalPages
                : 0,
          ),
        );
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
      case BookFormat.txt:
      case BookFormat.md:
        if (hasJumpTarget && !_hasRelocatedEpub) return;
        final info = _epubInfo;
        if (info == null) return;
        final progress = info.progression ?? initialProgress;
        if (progress == null) return;
        prefsManager.saveReadingPosition(
          bookId,
          ReadingPosition(epubLocatorJson: info.locatorJson, progress: progress),
        );
      case BookFormat.unknown:
        return;
    }
  }
}
```

- [ ] **Step 4：執行測試確認通過**

```bash
flutter test test/reader/reading_position_saver_test.dart
flutter analyze lib/reader/reading_position_saver.dart test/reader/reading_position_saver_test.dart
```

預期：全數通過；analyze 無問題。

- [ ] **Step 5：提交**

```bash
git add lib/reader/reading_position_saver.dart test/reader/reading_position_saver_test.dart
git commit -m "feat(reader): 新增 ReadingPositionSaver，收攏位置儲存規則（epic-54 Issue 7）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：`ReaderScreen` 改用 saver，刪除舊規則（既有 widget 案例全部保留，另補兩個接線測試）

**Files：**
- Modify：`app/lib/screens/reader_screen.dart`（`_hasRelocatedSinceOpen` 欄位約 525–536 行；`initState` 偏好載入 `setState` 約 630–641 行；`_writeCurrentPosition` 約 845–906 行；`dispose` 約 761 行；paused 約 833 行；`onLocatorChanged` 約 3553–3562 行；`onPageChanged` 約 3640–3646 行。行號為 2026-10-02 `main` 的位置，動手前先重新 grep）
- Modify：`app/test/screens/reader_screen_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `ReadingPositionSaver`。
- Produces：無（後續 Issue 8 會把 saver 的建立與呼叫進一步收進會話 module）。

- [ ] **Step 1：確認既有 widget 測試分類（已盤點，執行前核對即可）**

```bash
grep -n "savedReadingPositionCalls|readingPositionByBookId" test/screens/reader_screen_test.dart
```

審查時（2026-10-02）逐一比對 12 處引用，結論是**全部保留、不刪任何案例**：

| 案例（`reader_screen_test.dart`，行號為 2026-10-02 位置） | 性質 | 處置 |
|---|---|---|
| 313「PDF：initialJumpTarget.pdfPageIndex 優先於資料庫既有 lastPosition」 | 開書起始位置選擇，與儲存無關 | 保留 |
| 343「Foliate：initialJumpTarget.cfi 優先於資料庫既有 lastPosition」 | 同上 | 保留 |
| 450「initialJumpTarget 為 null（一般開書）時，沿用資料庫既有 lastPosition，零回歸」 | 同上 | 保留 |
| 484「PDF：跳轉後使用者繼續翻頁，dispose() 的 checkpoint 存檔行為…一致」 | 接線：確認 `onPageChanged` 第二次回報有轉發給 saver | 保留 |
| 549「PDF：跳轉後使用者未曾產生任何後續重定位事件即離開…不覆寫」 | 接線：確認畫面把 `initialJumpTarget != null` 傳給 saver | 保留 |
| 2233「PDF 收到 onPageChanged 後離開畫面（dispose），正確寫入 ReadingPosition」 | 接線：dispose 觸發儲存 | 保留 |
| 2280「尚未收到任何 onPageChanged 時，dispose 不呼叫 saveReadingPosition」 | 接線：saver 無回報時安全 | 保留 |

沒有任何案例單獨驗證「progression 為 null 的回退」「PDF totalPages 為 0」，這些規則原本**完全沒有測試**，現在由 Task 1 的單元測試首次涵蓋。

**缺口**：`paused` 觸發儲存沒有專屬測試（`paused` 只出現在 stats harness）；Foliate 路徑（`onLocatorChanged` → saver）沒有任何接線測試。Step 2 補這兩個。

- [ ] **Step 2：補兩個接線測試，先在**未改動**的程式碼上確認通過（建立行為基準）**

**(a) `paused` 觸發儲存**：比照 2233 行的 PDF 案例（同樣的 `MaterialApp` 與 `ReaderScreen(filePath: 'test/fixtures/sample.pdf', bookId: 'b_paused_test', prefsManager: prefsManager)` 建構），取得 `PdfReaderView` 後呼叫 `pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 3, totalPages: 10))`，再：

```dart
tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
await tester.pump();
expect(prefsManager.savedReadingPositionCalls, hasLength(1));
expect(prefsManager.savedReadingPositionCalls.single.value.pdfPageIndex, 3);
```

**(b) Foliate 接線**：比照 343 行的案例建構（`filePath: 'test/fixtures/sample.epub'`、`bookId: 'b_epub_wiring'`、`initialJumpTarget: const ReaderJumpTarget(cfi: 'epubcfi(/jump)')`），取得 `FoliateReaderView` 後依序呼叫兩次回報（呼叫方式比照 2914 行的 `epubView.onLocatorChanged?.call(...)`）：

```dart
final epubView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
epubView.onLocatorChanged?.call(const EpubPositionInfo(locatorJson: '{"cfi":"a"}', progression: 0.2));
await tester.pump();
// 只有第一次回報：跳轉後尚未重新定位，離開不儲存
// （此處先以 paused 觸發一次，期望 savedReadingPositionCalls 為空）
tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
await tester.pump();
expect(prefsManager.savedReadingPositionCalls, isEmpty);
// 第二次回報後才儲存
epubView.onLocatorChanged?.call(const EpubPositionInfo(locatorJson: '{"cfi":"b"}', progression: 0.3));
await tester.pump();
tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
await tester.pump();
expect(prefsManager.savedReadingPositionCalls.single.value.epubLocatorJson, '{"cfi":"b"}');
```

兩個案例都先在未改動的程式碼上跑，確認通過（它們描述的是現有行為）：

```bash
flutter test test/screens/reader_screen_test.dart --plain-name "paused"
flutter test test/screens/reader_screen_test.dart --plain-name "Foliate 接線"
```

（測試名稱請依此兩個關鍵字命名：(a) 含「paused」、(b) 含「Foliate 接線」。）

- [ ] **Step 3：改 `ReaderScreen`**

1. 刪除 `_hasRelocatedSinceOpen` 欄位及其文件註解（規則說明已搬到 saver）。
2. 新增欄位 `ReadingPositionSaver? _positionSaver;`（放在 `_initialPosition` 旁），註解說明：與 `_initialPosition` 同時在偏好載入完成時建立；閱讀視圖只在 `_resolved` 非 null 後才建構，所以回呼內正常情況下已存在；回呼與 `dispose`／`paused` 一律以 `?.` 呼叫，與 `_loaded` 尚未載入時的其他早退路徑保持一致，不使用 `!`。
3. `initState` 的 `prefsManager.load(...).then` 內，`setState` 中 `_initialPosition = loaded.readingPosition;` 之後加：

```dart
_positionSaver = ReadingPositionSaver(
  bookId: widget.bookId,
  prefsManager: widget.prefsManager,
  hasJumpTarget: widget.initialJumpTarget != null,
  initialProgress: loaded.readingPosition?.progress,
);
```

4. `onLocatorChanged`：把 `_hasRelocatedSinceOpen = true;` 那一行換成在 `if (previousPosition != null)` **之外**（`setState` 之前）呼叫 `_positionSaver?.onEpubLocated(info);`。`previousPosition` 仍用於閱讀活動判定，不動。
5. `onPageChanged`（PDF）：同樣把 `_hasRelocatedSinceOpen = true;` 換成在 `if (_pdfPageInfo != null)` 之外呼叫 `_positionSaver?.onPdfPageChanged(info);`；`_recordReadingActivity()` 留在原條件內。
6. 刪除 `_writeCurrentPosition()` 整個方法；`dispose` 與 `paused` 兩處改為 `_positionSaver?.save(detectBookFormat(_activeFilePath));`。**位置與順序不變**（dispose 內仍在 `trigger()` 之前；`paused` 仍在 `stats.onEnteredBackground()` 之後）。
7. 順手確認 `ReadingPosition`、`BookFormat` 等 import 是否仍被使用；只移除「因本次改動變成未使用」的 import。附近過時註解（例如 dispose 內提到 `_writeCurrentPosition()` 的兩處、`initState` 內相關註解）改為提到 `ReadingPositionSaver.save`，不改其他文字。

- [ ] **Step 4：執行異動觸及的測試**

```bash
flutter test test/reader/reading_position_saver_test.dart test/screens/reader_screen_test.dart test/screens/reader_screen_stats_lifecycle_test.dart test/screens/reader_screen_stats_activity_test.dart test/screens/reader_screen_stats_test.dart test/app_lifecycle_sync_test.dart
flutter analyze
```

預期：全數通過（`reader_screen_test.dart` 通過數 = Task 0 基準 + 2）；analyze "No issues found!"。

- [ ] **Step 5：行為不變的手動核對**

- `git diff` 中 `dispose` 與 `paused` 兩個方法內的呼叫順序與 Task 0 前相同（只有被呼叫的對象從 `_writeCurrentPosition()` 變成 `_positionSaver?.save(...)`）。
- `rg "_hasRelocatedSinceOpen|_writeCurrentPosition" lib test` 不應再有任何命中（含註解）。

- [ ] **Step 6：提交**

```bash
git add lib/screens/reader_screen.dart test/screens/reader_screen_test.dart
git commit -m "refactor(reader): ReaderScreen 改用 ReadingPositionSaver（epic-54 Issue 7）

新增 paused 與 Foliate 兩個接線測試；未刪除任何既有 widget 案例。

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：文件、全套驗證、發 PR 前確認

**Files：**
- Modify：`docs/epics/epic-54-architecture-optimization/epic.md`（開發記錄）、`issues.md`（第 7 列狀態）、`docs/epics.md`（第 55 列備註）

- [ ] **Step 1：全套測試（最後一次，背景執行）**

```bash
flutter test
```

用 `run_in_background`，約 6 分鐘。預期 0 失敗；記下通過數與 1 略過。

- [ ] **Step 2：靜態檢查**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

預期："No issues found!" 與兩行 PASS。

- [ ] **Step 3：更新文件**

`epic.md` 開發記錄新增「Issue 7 實作完成」：新增檔案、被刪除的 widget 案例與取代它們的單元測試、驗證數字、行為變動「無」、待真機確認「無」（純重構，行為由既有 widget 測試守住）。`issues.md` 第 7 列改為「🟡 待程式審查」。`docs/epics.md` 第 55 列備註只更新最後處理的 Issue 編號，保持一句話。

- [ ] **Step 4：提交並停下**

```bash
# 此時工作目錄是 worktree 的 app/，../docs 即 worktree 根目錄的 docs
git add ../docs/epics/epic-54-architecture-optimization ../docs/epics.md
git commit -m "docs(epic-54): Issue 7 實作完成記錄

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

此時**停止**，等人類決定是否進行程式審查與發 PR（審查先出報告、不直接改程式）。

---

## Self-Review

- **Spec 涵蓋**：epic.md 決策 1（拆兩張）、6（零行為變化）、7（不新增建構參數）、8（replace don't layer）、9（寫 plan）皆對應到 Global Constraints 或 Task；決策 2–5 屬 Issue 8，本計畫刻意不碰。
- **型別一致**：`ReadingPositionSaver` 的建構參數與三個方法名稱在 Task 1 與 Task 2 完全一致（`onPdfPageChanged`／`onEpubLocated`／`save`）。
- **行為等價核對**：現有程式中「旗標由 `ReaderScreen` 的 `previousPosition != null` 判斷」，改為 saver 自己的 `_epubInfo != null`；兩者都在 `if (!mounted) return;` 之後、`setState` 賦值之前更新，每次回報同步，故等價。`progression == null` 分支原本兩個 `if/else`，合併為 `info.progression ?? initialProgress` 後語意相同（兩者皆 null 不儲存）。
- **風險**：`_positionSaver` 在回呼中假設已建立，依據是閱讀視圖只在 `_resolved` 非 null 後才建構（`_buildNativeView` 本身就依賴 `_resolved` 非 null 時 `_loaded` 恆非 null 的同一個不變式），而 `_resolved` 與 saver 在同一個 `setState` 賦值；回呼一律以 `?.` 呼叫，即使假設不成立也只會漏存、不會崩潰；Task 2 Step 2 的兩個接線測試與既有 PDF 接線案例會暴露「漏存」。
