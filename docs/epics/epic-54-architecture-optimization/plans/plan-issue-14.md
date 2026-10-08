# Issue 14：開書路徑身分守衛測試（ADR 0037 最終驗收）實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:executing-plans` 逐 Task 執行本計畫（延續 Issue 12／13「使用者明確要求嚴禁 subagent」的做法，不要用 `subagent-driven-development`；若使用者改變主意，以使用者當下指示為準）。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 在 `app/test/elinkbook_app_wiring_test.dart` 補上「從 `AppDependencies` 容器出發，沿著每一條開書路徑走到底，路徑終點的畫面拿到的依賴組與容器內是同一個實例」的守衛測試，作為 ADR 0037 的最終驗收條件。

**Architecture：** 純測試工作，**不改 `lib/`**。用完整 `ElinkBookApp`（`fakeAppDependencies()` 組成的容器）當起點，真的用 `tester.tap` 走完 6 條開書路徑（書架→閱讀器、書架→全庫搜尋、全庫搜尋→閱讀器、全庫搜尋→單書搜尋→閱讀器、閱讀器→單書搜尋），在終點用 `same(...)` 比對。守衛是否真的有效，用「暫時改壞 `lib/` 再還原」的變異驗證（Task 4）證明，不靠肉眼。

**Tech Stack：** Flutter／Dart、`flutter_test`（`testWidgets`）。指令一律在 `app/` 目錄下執行，以 **Bash 工具（Git Bash）** 為準。

**Spec：** `docs/adr/0037-dependencies-grouped-by-consumer-passed-as-one-object.md`（§1、§2、「後果」最後一條）；`docs/epics/epic-54-architecture-optimization/issues.md` 第 14 列；`reviews/review-issues-11-14.md` I-4；前置做法見 `plans/plan-issue-13.md`。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **不改 `lib/`**：本 Issue 的 PR 對 `app/lib/` 的最終 diff 必須為空（`git diff main --stat -- app/lib` 無輸出）。變異驗證（Task 4）期間暫時修改的 `lib/` 檔案必須全數還原，且不得 commit。
- **不改既有測試**：`elinkbook_app_wiring_test.dart` 既有的 5 個測試一字不動（含 import 排序）；新測試以新增 `group` 附加在檔尾。不得為了通過而改弱任何斷言、加 `skip`、把 `same(...)` 改成 `isNotNull`。
- **身分比對**：容器層級一律用 `same(deps.readerFeatures)`（整組），不得只比對組內個別欄位——「整組換成欄位相同的新物件」正是要抓的缺陷（見 Review Focus 1）。
- **每個斷言只看終點畫面的 widget 欄位**（`tester.widget<ReaderScreen>(...).dependencies` 等），不讀 private State。
- **測試範圍**（`CLAUDE.md`）：單一 Task 只跑 `test/elinkbook_app_wiring_test.dart`；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，在 `app/` 下）。
- **提交前**：`flutter analyze` 必須 "No issues found!"；改了測試後跑 `node tool/check_l10n_hardcoded_strings.js`（本計畫的測試只用 `Key` 定位、不寫硬編碼中文字串參數，但仍須跑確認）。
- **Windows 環境**：多數原始檔是 CRLF，`Edit` 的定位字串不要含換行。提交一律明確路徑 `git add`。Commit 結尾須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：本計畫先審查再動手；程式審查先出報告（存 `reviews/`），審查者不直接改程式。實作在獨立 worktree 內進行（Task 0 建立），PR 合併後的進度同步（`issues.md` 第 14 列、`docs/epics.md`）才在 `main` 直接 commit＋push。

## 已查證的事實（撰寫計畫時對照 `lib/` 與 `test/` 所得，執行者開工前須再確認一次）

### 六條開書路徑（ADR 0037 §2「開書路徑整組轉傳同一個實例」）

| # | 起點 → 終點 | 轉傳點（`lib/screens/`） | 轉傳內容 |
|---|---|---|---|
| P1 | `LibraryScreen` → `ReaderScreen` | `library_screen.dart:440-449` `_openBook` → `buildReaderScreen(dependencies: widget.dependencies, isEinkMode: widget.appearance.isEinkMode)` | 整組 `readerFeatures`＋`isEinkMode` |
| P2 | `LibraryScreen` → `LibrarySearchScreen` | `library_screen.dart:829-838` `_openLibrarySearchScreen` | `dependencies: widget.dependencies`、`isEinkMode: widget.appearance.isEinkMode` |
| P3 | `LibrarySearchScreen` → `ReaderScreen`（書名／作者結果、內容片段兩種點擊） | `library_search_screen.dart:159-178` `_openBook` → `buildReaderScreen` | 同上，片段點擊另帶 `initialJumpTarget` |
| P4 | `LibrarySearchScreen` → `BookSearchScreen`（「查看全部」） | `library_search_screen.dart:385-398` `_openBookSearch` | `dependencies: widget.dependencies`、`isEinkMode: widget.isEinkMode` |
| P5 | `BookSearchScreen`（`fromReader == false`）→ `ReaderScreen` | `book_search_screen.dart:155-180` `_handleSnippetTap` → `buildReaderScreen` | 同上 |
| P6 | `ReaderScreen` → `BookSearchScreen`（`fromReader: true`） | `reader_screen.dart:1731-1754` `_openBookSearch` | `dependencies: widget.dependencies`、`isEinkMode: widget.isEinkMode` |

`buildReaderScreen`（`reader_screen_route.dart`，27 行）是 P1／P3／P5 共用的唯一組裝點，只做欄位搬移。`SourcesHomeScreen`／`CloudBrowserScreen`／`RemoteCatalogScreen` 等來源畫面**不開書**（它們只匯入／下載，回到書架才開），不在本守衛範圍；來源組的 `same(...)` 已由既有測試涵蓋。

### 既有測試已涵蓋與未涵蓋的

| 已涵蓋（不重做） | 位置 |
|---|---|
| 容器三組 → `AdaptiveShellScaffold`／`LibraryScreen`／`SourcesHomeScreen`／`SettingsScaffold` 的 `same(...)`、`syncCheckpointTrigger` 兩組同一實例 | `elinkbook_app_wiring_test.dart` 測試 1、2 |
| 主題／E-Ink／語言切換後三組仍是原實例、外觀快照三處一致 | 同檔測試 3、4、5 |
| **單一畫面層級**：`LibrarySearchScreen`→`ReaderScreen`、`BookSearchScreen`→`ReaderScreen`、`ReaderScreen`→`BookSearchScreen` 各自 `same(deps)`（手動 `pumpWidget` 該畫面，deps 由測試現造） | `library_search_screen_test.dart:522`、`book_search_screen_test.dart:296`、`reader_screen_test.dart:11093` |

**缺口（本 Issue 要補）**：以上單畫面測試的 `deps` 都是測試現造的，起點不是 `AppDependencies` 容器；沒有任何一個測試證明「容器 → 書架 → … → 終點」整條鏈是同一個實例，也沒有測試涵蓋 `LibraryScreen` → `LibrarySearchScreen`（P2）這一跳，以及每條路徑終點的 `syncCheckpointTrigger` 與 `isEinkMode`。

### 測試素材（皆已存在，不新增 support 檔）

| 項目 | 事實 | 出處 |
|---|---|---|
| 容器工廠 | `fakeAppDependencies({readerFeatures, sync, sources})`：只傳 `readerFeatures` 時，`sync` 沿用其 `syncCheckpointTrigger`（同一實例） | `test/support/fake_app_dependencies.dart` |
| 閱讀器依賴工廠 | `fakeReaderFeatureDependencies({libraryRepository, searchRepository, syncCheckpointTrigger, …})`，每次呼叫新建實例；`ReaderFeatureDependencies` **沒有** `copyWith` | `test/support/fake_reader_feature_dependencies.dart` |
| 假搜尋庫 | `FakeSearchRepository({titleAuthorResults, contentResults, bookSearchDetailResult})` | `test/support/fake_search_repository.dart` |
| 閱讀器測試環境 | `registerReaderStatsTestEnvironment()`（假 WebView 平台、略過書籍快取檔案系統、`elinkbook/fullscreen` channel、`pdfrxInitialize`）；內部呼叫 `setUpAll`／`setUp`／`tearDown`，**可放在 `group` 內只對該群組生效**。epub 路徑用 `test/fixtures/sample.epub` | `test/screens/reader_screen_stats_harness.dart:30-58` |
| 閱讀器載入後的等待 | 開 `ReaderScreen` 後需 `await tester.pump(); await tester.runAsync(() => Future.delayed(Duration.zero)); await tester.pump();`，之後 `reader_chrome_search_button` 才可點（不需 `markRendered`） | `reader_screen_test.dart:11103-11116`、`reader_screen_stats_test.dart` |
| 結束時收尾 | `ReaderScreen` 有 30 秒開書逾時計時器；測試結束前必須換掉整棵樹（`pumpWidget(SizedBox.shrink())`）讓它 dispose，否則 "A Timer is still pending" | `reader_screen_stats_harness.dart:141-144` |
| 書架開搜尋 | 點 `library_search_toggle_button` 展開 `library_search_field`，輸入關鍵字後點 `library_content_search_entry_button` 進 `LibrarySearchScreen`（帶入同一關鍵字，進入即自動搜尋） | `library_screen_test.dart:5442-5490、5807-5813` |
| 搜尋結果 Key | 書名結果 `library_search_title_author_result_<id>`；內容片段 `library_search_content_snippet_<id>_0`；查看全部 `library_search_drill_down_<id>`（需 `totalMatches > matches.length`）；單書搜尋片段 `book_search_snippet_0` | `library_search_screen_test.dart`、`book_search_screen_test.dart` |
| 書架書本 Key | `book_item_<id>` | `library_screen_test.dart:1549` |

## Review Focus

最可能咬到使用者（或讓守衛形同虛設）的情況，依可能性排序：

1. **某一跳把整組依賴換成「欄位相同的新物件」。**欄位級斷言（`deps.libraryRepository` 同一個）會全數通過，但整組已不是容器那一個；日後新增欄位又在該跳漏填時，才會變成執行期靜默失效。→ 每條路徑終點都用 `same(deps.readerFeatures)` 比整組；Task 4 的變異驗證用「欄位全帶、但整組是複本」的 `_cloneForMutation` 證明測試抓得到。
2. **`syncCheckpointTrigger` 在 `readerFeatures` 與 `sync` 不是同一實例。**使用者會看到「閱讀器離開時的 Checkpoint 與設定頁手動同步各自用不同 trigger」，防抖與併發保護失效。→ 每條通到 `ReaderScreen` 的路徑終點都比對 `reader.dependencies.syncCheckpointTrigger` 與 `deps.sync.syncCheckpointTrigger` 同一實例。
3. **`isEinkMode` 在某一跳沒帶到。**使用者會看到某一頁沒套 E-Ink 修飾子。→ 6 條路徑的終點都斷言 `isEinkMode`；Task 4 用「把該跳改成 `false`」的變異證明。
4. **外觀切換後開書拿到舊快照，或切換把依賴組變成新實例。**→ 測試 G：先非 E-Ink，用 `appearance.onEinkModeChanged(true)` 切換後再開書，終點 `isEinkMode == true` 且 `dependencies` 仍 `same(deps.readerFeatures)`。
5. **守衛本身假陽性：** 導覽堆疊殘留舊畫面使 `find.byType` 找到錯的那一個，或 `ReaderScreen` 的計時器沒收尾。→ 每條路徑先 `expect(find.byType(X), findsOneWidget)` 再取 widget；每個測試結尾換掉整棵樹。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/test/elinkbook_app_wiring_test.dart` | 修改（檔尾新增一個 `group` 與 4 個私有 helper） | 6 條開書路徑的身分守衛 |
| `docs/adr/0037-dependencies-grouped-by-consumer-passed-as-one-object.md` | 修改（「後果」最後一條補落地說明） | 記錄守衛落地位置與範圍界線（`main()` 不可單元測試） |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 進度與歷程同步 |

不新增 `test/support/` 檔案、不改 `lib/`。

---

### Task 0：建立基準、worktree 與取得設計決定

**Files:** 無程式修改。

- [ ] **Step 1: 確認前提（開工前再對照一次）**

在專案根目錄：
```bash
git status --short
git log --oneline -1
git worktree list
```

在 `app/` 目錄下確認六個轉傳點仍如「已查證的事實」所列（行號可能漂移，內容須相符）：
```bash
git grep -n -E "buildReaderScreen\(|LibrarySearchScreen\(|BookSearchScreen\(" -- lib/screens
git grep -n "dependencies: widget.dependencies" -- lib/screens/library_screen.dart lib/screens/library_search_screen.dart lib/screens/book_search_screen.dart lib/screens/reader_screen.dart
```

Expected：工作樹乾淨、`HEAD` 在 `main`、`git worktree list` 輸出中尚無 `epic-54-issue-14`（人工檢視）；第一組命中 `library_screen.dart`（`buildReaderScreen`、`LibrarySearchScreen(`）、`library_search_screen.dart`（`buildReaderScreen`、`BookSearchScreen(`）、`book_search_screen.dart`（`buildReaderScreen`）、`reader_screen.dart`（`BookSearchScreen(`）、`reader_screen_route.dart`（定義）；第二組恰好命中 4 個檔案各 1～2 處。任何一項不符，先停下回報。

- [x] **Step 2: 向使用者呈報兩個設計決定並等待回答（回答前不得改 `app/test/`、不得建 worktree 之外的任何檔案）**

```
Q1  守衛涵蓋 main() 的組裝嗎？ADR 0037 §1 要求「syncCheckpointTrigger 由 main() 建構一次、同一實例放進兩組」。
    但 main() 是 async、依賴 sqflite／secure storage／原生 channel，無法在 widget test 中執行。
    A) 【建議】不為 main() 寫永久測試。容器之後的每一跳由本 Issue 的測試守住；main() 本身只做一次性
       靜態確認（Task 4 Step 4：SyncCheckpointTrigger( 在 main.dart 只建構一次、兩組都引用同一個區域變數），
       結果記入 epic.md。代價：日後有人在 main() 裡把兩組改成各自建構，要靠程式審查才抓得到。
    B) 把 main() 內「組裝三組」抽成一個可測的純函式（例如 buildAppDependencies(...)），測試呼叫它。
       這會改 lib/，超出 Issue 14「守衛測試」的範圍，且需要把約 20 個已建好的物件當參數傳入，函式本身
       幾乎沒有邏輯；屬於投機，建議不做；若要做應另開 Issue。
Q2  測試放哪裡？
    A) 【建議】照 issues.md 第 14 列字面：擴充 elinkbook_app_wiring_test.dart，在檔尾新增 group
       （既有 5 個測試不動）。檔案會從約 400 行增到約 750 行，但主題一致（容器→畫面的身分比對）。
    B) 新檔 elinkbook_app_open_book_wiring_test.dart：檔案較小，但與 issues.md 字面不符，且兩個檔案
       會各自維護一份 ElinkBookApp 起手式。
```

使用者回答後，把原話填入「附錄 A」。

- [ ] **Step 3: 建立 worktree**

在專案根目錄執行（不使用 `cd`，工作目錄由執行工具的 Cwd 指定）：

```bash
git worktree add .worktrees/epic-54-issue-14 -b epic-54-issue-14 main
```

接著在 `.worktrees/epic-54-issue-14/app` 目錄下執行：

```bash
flutter pub get
```

Expected：`git worktree list` 出現 `epic-54-issue-14`；`flutter pub get` 成功。**之後所有 Task 的指令都以 `.worktrees/epic-54-issue-14/app` 為工作目錄執行。**

- [ ] **Step 4: 跑基準測試並記錄**

```bash
flutter test test/elinkbook_app_wiring_test.dart
flutter analyze
```

Expected：5 個測試全過（記入附錄 C 基準）；`No issues found!`。基準不綠先停下回報。

---

### Task 1：共用起手式 helper ＋ P1（書架→閱讀器）＋ P2（書架→全庫搜尋）＋ 外觀切換後開書

**Files:**
- Modify: `app/test/elinkbook_app_wiring_test.dart`（檔尾新增 import、helper 與 `group`）

**Interfaces:**
- Consumes：`fakeAppDependencies`、`fakeReaderFeatureDependencies`、`FakeLibraryRepository`、`FakeSearchRepository`、`registerReaderStatsTestEnvironment()`（皆已存在，見「測試素材」）。
- Produces（供 Task 2、3 使用，簽名須完全一致）：
  - `const _kWiringBookId = 'wiring-book';`
  - `Book _wiringBook()`
  - `Future<AppDependencies> _pumpWiringApp(WidgetTester tester, {FakeSearchRepository? searchRepository, bool isEinkMode = true})`
  - `Future<void> _openLibraryContentSearch(WidgetTester tester)`
  - `void _expectReaderWired(WidgetTester tester, AppDependencies deps, {required bool isEinkMode})`
  - `Future<void> _disposeWiringApp(WidgetTester tester)`

- [ ] **Step 1: 新增 import（接在既有 import 區塊最後一行之後，不動既有行）**

在檔頭既有 `import 'support/fake_sync_dependencies.dart';` 之後加入：

```dart
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/book_search_screen.dart';
import 'package:elinkbook/screens/library_search_screen.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/search/search_repository.dart';

import 'screens/reader_screen_stats_harness.dart';
import 'support/fake_search_repository.dart';
```

若 `flutter analyze` 回報其中某個 import 已存在或未使用，只調整本步新增的行，不動既有行。

- [ ] **Step 2: 寫 helper（檔尾，緊接在 `main()` 的結尾 `}` 之後，作為檔案層級私有函式）**

```dart
// ---------------------------------------------------------------------------
// Issue 14：開書路徑身分守衛的共同起手式。
// ---------------------------------------------------------------------------

const _kWiringBookId = 'wiring-book';

/// 書架上唯一的一本書。檔案用 `test/fixtures/sample.epub`，讓 `ReaderScreen`
/// 走假 WebView 平台（見 [registerReaderStatsTestEnvironment]）正常開啟。
Book _wiringBook() => Book(
  id: _kWiringBookId,
  title: '守衛測試書',
  format: BookFileFormat.epub,
  filePath: 'test/fixtures/sample.epub',
  source: BookSource.local,
  groupName: BookGroup.uncategorized,
  createTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  lastReadTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
);

/// 以完整 `ElinkBookApp` 為起點：容器由 `fakeAppDependencies` 組成，
/// `readerFeatures` 內的 `libraryRepository` 放一本 [_wiringBook]。
/// 只傳 `readerFeatures` 給 `fakeAppDependencies`，所以 `sync` 會沿用同一個
/// `syncCheckpointTrigger`（與 `main()` 的組裝方式一致）。
Future<AppDependencies> _pumpWiringApp(
  WidgetTester tester, {
  FakeSearchRepository? searchRepository,
  bool isEinkMode = true,
}) async {
  final deps = fakeAppDependencies(
    readerFeatures: fakeReaderFeatureDependencies(
      libraryRepository: FakeLibraryRepository(initialBooks: [_wiringBook()]),
      searchRepository: searchRepository,
    ),
  );
  await tester.pumpWidget(
    ElinkBookApp(dependencies: deps, initialEinkMode: isEinkMode),
  );
  await tester.pumpAndSettle();
  return deps;
}

/// 書架 → 全庫搜尋（P2）：展開書架搜尋框、輸入關鍵字、點「搜尋書本內容」入口。
Future<void> _openLibraryContentSearch(WidgetTester tester) async {
  if (find.byKey(const Key('library_search_field')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('library_search_toggle_button')));
    await tester.pumpAndSettle();
  }
  // 關鍵字「守衛」對應 [_wiringBook] 的書名「守衛測試書」；FakeSearchRepository
  // 不過濾、直接回傳建構時給的結果，所以結果必然包含該書。
  await tester.enterText(find.byKey(const Key('library_search_field')), '守衛');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('library_content_search_entry_button')));
  await tester.pumpAndSettle();
}

/// 通到 `ReaderScreen` 的每條路徑終點共用的斷言：整組同一實例、
/// `syncCheckpointTrigger` 與同步組是同一實例、E-Ink 狀態、書本身分。
void _expectReaderWired(
  WidgetTester tester,
  AppDependencies deps, {
  required bool isEinkMode,
}) {
  expect(find.byType(ReaderScreen), findsOneWidget);
  final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
  expect(reader.dependencies, same(deps.readerFeatures));
  expect(
    reader.dependencies.syncCheckpointTrigger,
    same(deps.sync.syncCheckpointTrigger),
  );
  expect(reader.isEinkMode, isEinkMode);
  expect(reader.bookId, _kWiringBookId);
}

/// 換掉整棵樹讓 `ReaderScreen` dispose（取消 30 秒開書逾時計時器）。
Future<void> _disposeWiringApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
```

- [ ] **Step 3: 寫失敗的測試（檔尾新增 `group`，放在 helper 之後）**

```dart
void _openBookWiringTests() {
  group('Issue 14：開書路徑身分守衛（容器 → 每條開書路徑）', () {
    registerReaderStatsTestEnvironment();

    testWidgets('P1 書架點書 → ReaderScreen：整組依賴、同步 trigger、E-Ink 皆原樣', (
      tester,
    ) async {
      final deps = await _pumpWiringApp(tester);

      await tester.tap(find.byKey(const Key('book_item_$_kWiringBookId')));
      await tester.pumpAndSettle();

      _expectReaderWired(tester, deps, isEinkMode: true);
      await _disposeWiringApp(tester);
    });

    testWidgets('P2 書架 → LibrarySearchScreen：整組依賴與 E-Ink 原樣', (tester) async {
      final deps = await _pumpWiringApp(tester);

      await _openLibraryContentSearch(tester);

      expect(find.byType(LibrarySearchScreen), findsOneWidget);
      final search = tester.widget<LibrarySearchScreen>(
        find.byType(LibrarySearchScreen),
      );
      expect(search.dependencies, same(deps.readerFeatures));
      expect(search.isEinkMode, isTrue);
      await _disposeWiringApp(tester);
    });

    testWidgets('切換 E-Ink 後再開書：ReaderScreen 看到新的 E-Ink 值，依賴組仍是容器原實例', (
      tester,
    ) async {
      final deps = await _pumpWiringApp(tester, isEinkMode: false);
      tester
          .widget<LibraryScreen>(find.byType(LibraryScreen))
          .appearance
          .onEinkModeChanged(true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_$_kWiringBookId')));
      await tester.pumpAndSettle();

      _expectReaderWired(tester, deps, isEinkMode: true);
      await _disposeWiringApp(tester);
    });
  });
}
```

並在既有 `main()` 內、最後一個既有 `testWidgets` 之後、`main()` 結尾 `}` 之前，加一行呼叫（這是對既有檔案唯一的「進入點」修改）：

```dart
  _openBookWiringTests();
```

> 說明：`group` 與 `registerReaderStatsTestEnvironment()` 的 `setUpAll`／`setUp`／`tearDown` 只在這個 group 內生效，不影響既有 5 個測試。把 group 包成函式是為了讓 `main()` 既有內容不動、只多一行呼叫。

- [ ] **Step 4: 跑測試，預期「新測試通過」**

這是守衛測試，被測的 `lib/` 本來就正確，所以「先紅」不成立；紅燈證明改由 Task 4 的變異驗證提供。此步預期直接全綠，若紅燈代表測試手法有誤（最常見的原因見下），不是 `lib/` 有缺陷：

```bash
flutter test test/elinkbook_app_wiring_test.dart
```

Expected：8 個測試全過（5 既有＋3 新增）。常見失敗與處理：
- `Timer is still pending`：該測試漏了 `_disposeWiringApp`。
- 找不到 `book_item_wiring-book`：`pumpAndSettle` 前書架尚未載入，先確認 `_pumpWiringApp` 的 `pumpAndSettle` 有執行；仍找不到則檢查書架預設分組是否把書收在別的分頁。
- `find.byType(ReaderScreen)` 找到 0 個：開書後需補 `await tester.runAsync(() => Future.delayed(Duration.zero)); await tester.pump();`（見「測試素材」）。補在 `_expectReaderWired` 之前，並在報告中記錄。
- 遇到的任何 flaky 現象一律記錄，不用 `skip` 掩蓋。

- [ ] **Step 5: 靜態檢查與 commit**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
git add test/elinkbook_app_wiring_test.dart
git commit -m "test(epic-54): Issue 14 開書路徑身分守衛——書架開書、書架開全庫搜尋、E-Ink 切換後開書

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：analyze 乾淨、守衛 PASS。

---

### Task 2：P3（全庫搜尋→閱讀器，兩種點擊）

**Files:**
- Modify: `app/test/elinkbook_app_wiring_test.dart`（在 `_openBookWiringTests()` 的 group 內新增 2 個測試）

**Interfaces:**
- Consumes：Task 1 的 `_pumpWiringApp`、`_openLibraryContentSearch`、`_expectReaderWired`、`_disposeWiringApp`、`_wiringBook()`、`_kWiringBookId`。
- Produces：無（Task 3 不依賴本 Task 新增的 symbol）。

- [ ] **Step 1: 新增兩個測試（接在 Task 1 的「切換 E-Ink 後再開書」測試之後、group 結尾之前）**

```dart
    testWidgets('P3a 書架 → 全庫搜尋 → 點書名結果 → ReaderScreen：整組依賴原樣', (tester) async {
      final deps = await _pumpWiringApp(
        tester,
        searchRepository: FakeSearchRepository(
          titleAuthorResults: [_wiringBook()],
        ),
      );
      await _openLibraryContentSearch(tester);

      await tester.tap(
        find.byKey(const Key('library_search_title_author_result_$_kWiringBookId')),
      );
      await tester.pumpAndSettle();

      _expectReaderWired(tester, deps, isEinkMode: true);
      await _disposeWiringApp(tester);
    });

    testWidgets('P3b 書架 → 全庫搜尋 → 點內容片段 → ReaderScreen：整組依賴原樣且帶跳轉目標', (
      tester,
    ) async {
      final deps = await _pumpWiringApp(
        tester,
        searchRepository: FakeSearchRepository(
          contentResults: [
            BookContentMatches(
              book: _wiringBook(),
              matches: const [
                ContentMatchSnippet(
                  snippet: '含有守衛關鍵字的句子',
                  locator: 'epubcfi(/6/2)',
                ),
              ],
            ),
          ],
        ),
      );
      await _openLibraryContentSearch(tester);

      await tester.tap(
        find.byKey(const Key('library_search_content_snippet_${_kWiringBookId}_0')),
      );
      await tester.pumpAndSettle();

      _expectReaderWired(tester, deps, isEinkMode: true);
      expect(
        tester.widget<ReaderScreen>(find.byType(ReaderScreen)).initialJumpTarget,
        isNotNull,
        reason: '內容片段點擊須帶跳轉目標，書名結果則不帶（P3a）',
      );
      await _disposeWiringApp(tester);
    });
```

- [ ] **Step 2: 跑測試**

```bash
flutter test test/elinkbook_app_wiring_test.dart
```

Expected：10 個測試全過。若 `initialJumpTarget` 不是 `ReaderScreen` 的公開欄位名稱，改用 `git grep -n "initialJumpTarget" -- lib/screens/reader_screen.dart` 查實際欄位名，不得刪除這條斷言。

- [ ] **Step 3: 靜態檢查與 commit**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
git add test/elinkbook_app_wiring_test.dart
git commit -m "test(epic-54): Issue 14 開書路徑身分守衛——全庫搜尋點書名／內容片段開書

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：P4＋P5（全庫搜尋→單書搜尋→閱讀器）與 P6（閱讀器→單書搜尋）

**Files:**
- Modify: `app/test/elinkbook_app_wiring_test.dart`（group 內新增 2 個測試）

**Interfaces:**
- Consumes：同 Task 2。
- Produces：無。

- [ ] **Step 1: 新增兩個測試（接在 Task 2 的測試之後、group 結尾之前）**

```dart
    testWidgets(
      'P4＋P5 書架 → 全庫搜尋 → 查看全部 → 單書搜尋 → 點片段 → ReaderScreen：整鏈同一實例',
      (tester) async {
        final book = _wiringBook();
        final deps = await _pumpWiringApp(
          tester,
          searchRepository: FakeSearchRepository(
            contentResults: [
              BookContentMatches(
                book: book,
                matches: [
                  for (var i = 0; i < 3; i++)
                    ContentMatchSnippet(
                      snippet: '片段$i',
                      locator: 'epubcfi(/6/$i)',
                    ),
                ],
                totalMatches: 10, // 大於顯示筆數，才會出現「查看全部」
              ),
            ],
            bookSearchDetailResult: BookSearchDetailResult(
              book: book,
              matches: const [
                ContentMatchSnippet(
                  snippet: '單書搜尋的片段',
                  locator: 'epubcfi(/6/2)',
                  chapterIndex: 1,
                ),
              ],
              totalMatches: 1,
              isTruncated: false, // 建構子必填（search_repository.dart:53）
            ),
          ),
        );
        await _openLibraryContentSearch(tester);

        // P4：全庫搜尋 → 單書搜尋
        await tester.tap(
          find.byKey(const Key('library_search_drill_down_$_kWiringBookId')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BookSearchScreen), findsOneWidget);
        final bookSearch = tester.widget<BookSearchScreen>(
          find.byType(BookSearchScreen),
        );
        expect(bookSearch.dependencies, same(deps.readerFeatures));
        expect(bookSearch.isEinkMode, isTrue);
        expect(bookSearch.fromReader, isFalse);

        // P5：單書搜尋（fromReader == false）→ 閱讀器
        await tester.tap(find.byKey(const Key('book_search_snippet_0')));
        await tester.pumpAndSettle();
        _expectReaderWired(tester, deps, isEinkMode: true);
        await _disposeWiringApp(tester);
      },
    );

    testWidgets('P6 書架 → ReaderScreen → 單書搜尋（fromReader）：整組依賴與 E-Ink 原樣', (
      tester,
    ) async {
      final deps = await _pumpWiringApp(tester);
      await tester.tap(find.byKey(const Key('book_item_$_kWiringBookId')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pumpAndSettle();

      expect(find.byType(BookSearchScreen), findsOneWidget);
      final bookSearch = tester.widget<BookSearchScreen>(
        find.byType(BookSearchScreen),
      );
      expect(bookSearch.fromReader, isTrue);
      expect(bookSearch.book.id, _kWiringBookId);
      expect(bookSearch.dependencies, same(deps.readerFeatures));
      expect(
        bookSearch.dependencies.syncCheckpointTrigger,
        same(deps.sync.syncCheckpointTrigger),
      );
      expect(bookSearch.isEinkMode, isTrue);
      await _disposeWiringApp(tester);
    });
```

- [ ] **Step 2: 跑測試**

```bash
flutter test test/elinkbook_app_wiring_test.dart
```

Expected：12 個測試全過。若 `ContentMatchSnippet` 不接受 `chapterIndex` 或 `BookSearchDetailResult` 建構子簽名不符，以 `book_search_screen_test.dart:51-73`（`_makeResult`）為準修正，不改 `lib/`。

- [ ] **Step 3: 靜態檢查與 commit**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
git add test/elinkbook_app_wiring_test.dart
git commit -m "test(epic-54): Issue 14 開書路徑身分守衛——全庫搜尋→單書搜尋→閱讀器、閱讀器→單書搜尋

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：變異驗證（證明守衛有效）與 `main()` 靜態確認

**Files:** 暫時修改 `app/lib/screens/` 下 4 個檔案，**全部還原、不 commit**。

守衛測試不能只看「全綠」，必須看到它在 `lib/` 被改壞時變紅。每個變異：改一處 → 跑 `flutter test test/elinkbook_app_wiring_test.dart` → 記錄哪些測試變紅 → `git checkout -- <file>` 還原。

- [ ] **Step 1: 建立暫時的複本函式（只用於變異，不 commit）**

變異期間只跑 `flutter test test/elinkbook_app_wiring_test.dart` 看紅燈即可，**不要跑 `flutter analyze`**（暫時函式與改壞的程式碼會引發無意義警告）；Step 3 全部還原後才跑完整分析。

在 `lib/screens/reader_feature_dependencies.dart` 檔尾暫時加入（19 個欄位全帶，名稱以該檔實際欄位為準；`lib/` 內 `ReaderFeatureDependencies` 沒有 `copyWith`，所以用這個函式模擬「欄位全帶、但整組是新物件」）：

```dart
ReaderFeatureDependencies cloneForMutation(ReaderFeatureDependencies d) =>
    ReaderFeatureDependencies(
      prefsManager: d.prefsManager,
      libraryRepository: d.libraryRepository,
      bookImportService: d.bookImportService,
      bookmarksRepository: d.bookmarksRepository,
      highlightsRepository: d.highlightsRepository,
      notesRepository: d.notesRepository,
      customFontsRepository: d.customFontsRepository,
      downloadableFontStore: d.downloadableFontStore,
      layoutPresetRepository: d.layoutPresetRepository,
      bookReaderPrefsRepository: d.bookReaderPrefsRepository,
      searchRepository: d.searchRepository,
      isFullTextSearchAvailable: d.isFullTextSearchAvailable,
      fullTextSearchSettingsRepository: d.fullTextSearchSettingsRepository,
      readingStatsRepository: d.readingStatsRepository,
      readerActivityTracker: d.readerActivityTracker,
      syncCheckpointTrigger: d.syncCheckpointTrigger,
      ttsProvider: d.ttsProvider,
      ttsAudio: d.ttsAudio,
      ttsAudioFocusSource: d.ttsAudioFocusSource,
    );
```

- [ ] **Step 2: 逐一套用變異並記錄**

每一列：套用「改法」→ 跑測試 → 填入「實際變紅的測試」→ 還原該檔（`reader_feature_dependencies.dart` 的複本函式保留到全部做完）。

| # | 檔案與改法 | 預期變紅 | 實際變紅（執行者填） |
|---|---|---|---|
| M1 | `reader_screen_route.dart`：`dependencies: dependencies` → `dependencies: cloneForMutation(dependencies)` | P1、P3a、P3b、P4＋P5、E-Ink 切換後開書 | |
| M2 | `library_screen.dart` `_openLibrarySearchScreen`：`dependencies: widget.dependencies` → `cloneForMutation(widget.dependencies)` | P2、P3a、P3b、P4＋P5 | |
| M3 | `library_search_screen.dart` `_openBookSearch`：`dependencies: widget.dependencies` → `cloneForMutation(widget.dependencies)` | P4＋P5 | |
| M4 | `reader_screen.dart` `_openBookSearch`：`dependencies: widget.dependencies` → `cloneForMutation(widget.dependencies)` | P6 | |
| M5 | `reader_screen_route.dart`：`isEinkMode: isEinkMode` → `isEinkMode: false` | P1、P3a、P3b、P4＋P5、E-Ink 切換後開書 | |
| M6 | `library_screen.dart` `_openLibrarySearchScreen`：`isEinkMode: widget.appearance.isEinkMode` → `false` | P2（及經它進入的 P3a、P3b、P4＋P5） | |
| M7 | `library_search_screen.dart` `_openBookSearch`：`isEinkMode: widget.isEinkMode` → `false` | P4＋P5 | |
| M8 | `reader_screen.dart` `_openBookSearch`：`isEinkMode: widget.isEinkMode` → `false` | P6 | |
| M9 | `main.dart`／`app_dependencies` 不改；改 `test/support/fake_app_dependencies.dart` 的 `fakeAppDependencies`：`sync` 改用不共用的新 trigger（`fakeSyncDependencies()` 不帶 `syncCheckpointTrigger`），且測試端 `_pumpWiringApp` 不改 | 所有通到 `ReaderScreen` 的測試（`syncCheckpointTrigger` 同一實例斷言）；**執行後務必還原 `test/` 檔** | |

驗收：「實際變紅」欄必須涵蓋「預期變紅」欄（可多不可少）。任何一列變異後測試仍全綠，代表該跳沒被守住——回到 Task 1～3 補斷言，不得調整預期欄來遷就。

- [ ] **Step 3: 全部還原並確認 `lib/` 無殘留**

```bash
git checkout -- lib test/support
git status --short
git diff main --stat -- lib
```

Expected：`git status --short` 無輸出（Task 1～3 的測試已 commit）；`git diff main --stat -- lib` 無輸出。再跑一次：

```bash
flutter test test/elinkbook_app_wiring_test.dart
```

Expected：12 個全過。

- [ ] **Step 4: `main()` 的一次性靜態確認（Q1 選 A 時）**

```bash
git grep -c "SyncCheckpointTrigger(" -- lib/main.dart
git grep -n "syncCheckpointTrigger: syncCheckpointTrigger" -- lib/main.dart
git grep -n "AppDependencies(" -- lib/main.dart
```

Expected：第一行輸出 `lib/main.dart:1`（`git grep -c` 會帶檔名前綴；`main()` 只建構一次）；第二行恰好 2 筆，分別落在 `ReaderFeatureDependencies(` 與 `SyncDependencies(` 的建構內；第三行 1 筆，三組皆以區域變數傳入。把輸出貼進附錄 C，供程式審查對照。

---

### Task 5：文件同步、完整驗證與程式審查

**Files:**
- Modify: `docs/adr/0037-dependencies-grouped-by-consumer-passed-as-one-object.md`
- Modify: `docs/epics/epic-54-architecture-optimization/epic.md`（新增「Issue 14 實作完成」段）
- 不在本 PR 改：`issues.md` 第 14 列與 `docs/epics.md`（合併後在 `main` 直接 commit＋push）

- [ ] **Step 1: ADR 0037「後果」最後一條補落地說明**

把

```
- 守衛測試縮小為身分比對：驗證 `main.dart` 組裝的同一個實例傳到每個開書路徑；欄位是否遺漏改由型別系統保證。
```

之後追加一行（保留原條目不動）：

```
  - 已於 Issue 14 落地為 `app/test/elinkbook_app_wiring_test.dart` 的「開書路徑身分守衛」group：以完整 `ElinkBookApp` 為起點，走完書架→閱讀器、書架→全庫搜尋、全庫搜尋→閱讀器（書名結果／內容片段）、全庫搜尋→單書搜尋→閱讀器、閱讀器→單書搜尋共 6 條路徑，終點以 `same(...)` 比對整組、`syncCheckpointTrigger` 與 `isEinkMode`。`main()` 本身（建構一次、同一 trigger 放進兩組）無法在 widget test 執行，改由程式審查與一次性靜態確認把關。
```

- [ ] **Step 2: `epic.md` 新增「Issue 14 實作完成」段**

仿「Issue 13 實作完成」（約 502 行）格式，內容：分支與 worktree、計畫連結、新增測試清單（12 個＝既有 5＋新增 7）、變異驗證 M1～M9 的實際結果表、`main()` 靜態確認輸出、`lib/` 零差異聲明、Q1／Q2 使用者決定。

- [ ] **Step 3: 完整驗證（在 `app/` 下，`run_in_background`）**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
node tool/check_integration_keys.js
flutter test
```

Expected：analyze 乾淨；兩個守衛 PASS；完整 `flutter test` 全過，唯一允許的失敗是 Issue 12 起已在乾淨 `main` 確認的既存項 `pdf_reader_view_filters_test` debouncer（Issue 13 計畫附錄 C 亦記載同一項；若出現須再於乾淨 `main` 對照一次並記錄，不得歸因為本 Issue）。測試數：基準 + 7（算式記入附錄 C）。

- [ ] **Step 4: 確認 `lib/` 零差異並 commit 文件**

```bash
git diff main --stat -- lib
git add ../docs/adr/0037-dependencies-grouped-by-consumer-passed-as-one-object.md ../docs/epics/epic-54-architecture-optimization/epic.md ../docs/epics/epic-54-architecture-optimization/plans/plan-issue-14.md
git commit -m "docs(epic-54): Issue 14 ADR 0037 落地說明與 epic 歷程

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：第一行無輸出。

- [ ] **Step 5: 請求程式審查**（嚴禁 subagent，改為自審：`reviews/review-code-issue-14.md`）

審查重點：(1) 六條路徑是否都有終點斷言（對照「六條開書路徑」表）；(2) 變異驗證表是否每列「實際」涵蓋「預期」；(3) `lib/` 零差異；(4) 既有 5 個測試未被改動（`git diff main -- app/test/elinkbook_app_wiring_test.dart` 只有新增行與 `main()` 內那一行呼叫）。審查者先產出報告（`reviews/`，gitignore），不得直接改程式；處理審查意見後才發 PR（Gitea：`tea pr create -l jigong -r huthief/elinkBook`，由使用者合併）。

---

## 附錄 A：使用者決定紀錄（Task 0 Step 2 取得後填入原話）

- Q1（`main()` 是否納入守衛）：使用者於 2026-10-08 先答「要」，經確認後選 A：不為 `main()` 寫永久測試，只做一次性靜態確認（Task 4 Step 4），結果記入 epic.md；不改 `lib/`。
- Q2（測試放哪個檔）：使用者於 2026-10-08 回答「加在 elinkbook_app_wiring_test.dart」＝A：檔尾新增 group，既有 5 個測試不動。

## 附錄 B：被刪除的測試清單

本 Issue 不刪除任何測試（純新增）。

## 附錄 C：測試數基準與實測紀錄（執行者依實測填入）

- Task 0 基準：`elinkbook_app_wiring_test.dart` 5 全過；`flutter analyze` No issues found。
- Task 1：8 全過（5＋3）。
- Task 2：10 全過（8＋2）。
- Task 3：12 全過（10＋2）。
- Task 4 Step 2 變異驗證結果：（填入 M1～M9 實際變紅表）
- Task 4 Step 4 `main()` 靜態確認輸出：
- Task 5：完整 `flutter test`：

## Self-Review 結果

- **Spec 涵蓋**：`issues.md` 第 14 列要求「擴充 `elinkbook_app_wiring_test.dart`」→ Task 1～3；「以身分比對驗證同一實例從容器傳到每個開書路徑」→ 6 條路徑（P1～P6）逐一有終點 `same(...)`；「含 `syncCheckpointTrigger` 在 `ReaderFeatureDependencies` 與 `SyncDependencies` 為同一實例」→ `_expectReaderWired` 與 P6 皆比對，既有測試 2 已在容器層比對；「ADR 0037 的最終驗收條件」→ Task 5 Step 1 回寫 ADR。
- **佔位掃描**：附錄 A／C 與 Task 4 Step 2 的「實際變紅」欄刻意留白由執行者依實測填入；其餘步驟皆含完整程式碼或指令。
- **型別一致**：`_kWiringBookId`、`_wiringBook()`、`_pumpWiringApp`、`_openLibraryContentSearch`、`_expectReaderWired`、`_disposeWiringApp` 在 Task 1 定義，Task 2、3 簽名與用法一致；`cloneForMutation` 只存在於 Task 4 暫時修改，不進 commit。
- **Review Focus**：5 項皆對應到具體測試或變異（1→M1～M4、2→每條通到閱讀器的路徑＋M9、3→M5～M8、4→「切換 E-Ink 後再開書」、5→每個測試的 `findsOneWidget` 與 `_disposeWiringApp`）。
- **風險**：(a) `ReaderScreen` 在完整 `ElinkBookApp` 下開啟需假 WebView 環境，若 `registerReaderStatsTestEnvironment()` 與 `ElinkBookApp` 的其他初始化衝突（例如重複註冊 channel handler），退路是把 P1／P3／P5／P6 的書本檔名改為 `.unknown` 以走「不支援格式」分支（`library_screen_test.dart:1552` 先例），但 P6 需要可辨識格式才能點搜尋鈕，屆時須與使用者討論；(b) 守衛是「綠燈型」測試，其價值全靠 Task 4 變異驗證證明，該 Task 不可省略。
