# Issue 11：閱讀器功能依賴組 `ReaderFeatureDependencies` 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 讓 `ReaderScreen` 與 `BookSearchScreen` 各自只收一個 `ReaderFeatureDependencies` 物件（non-null required），消除 `reader_screen.dart` 開單書搜尋時「手動逐欄重建 bundle」，並建立 `test/support/` 的預設全 fake 工廠。

**Architecture：** 新增不可變的 `ReaderFeatureDependencies`（18 個欄位，全部 non-null），`ReaderScreen` 建構子從 29 個參數降為 12 個（皆含 `super.key`；移除 17 個依賴＋`prefsManager`，留書本／UI 參數與兩個測試注入點）。尚未遷移的 `LibraryScreen`／`LibrarySearchScreen` 仍持有舊 bundle，由 `reader_screen_route.dart` 內單一轉換函式 `readerFeatureDependenciesFromLegacy` 暫時組裝（Issue 12/13 移除）。`ReaderScreen` 內部「依賴為 null 就停用功能」的分支因型別不再可為 null 而移除；測試改用預設全 fake 的工廠，只覆寫情境需要的欄位。

**Tech Stack：** Flutter／Dart、`flutter_test`、Node（只用於一次性、不進版控的 codemod 腳本）。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`。設計決策見 `docs/adr/0037-dependencies-grouped-by-consumer-passed-as-one-object.md`；工單審查見 `reviews/review-issues-11-14.md`（不進版控）；候選來源 2026-10-05 架構檢視候選 2；Issue 範圍見 `issues.md` Issue 11。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **ADR 0037 為準**：組內欄位一律 non-null required；不用 `InheritedWidget`、不引入 DI 套件；測試預設全 fake；`ReaderScreen` 建構子不保留新舊參數並存。
- **`ReaderScreen` 建構子最終只剩**：`filePath`、`bookId`、`dependencies`（required）；`bookTitle`、`bookAuthor`、`bookProgress`、`isFixedLayout`、`isEinkMode`、`initialJumpTarget`；測試注入點 `pickSingleBookFile`、`readingStatsTracker`（註解標明僅供測試）。
- **行為不變（正式環境）**：`main.dart` 現況就把所有依賴都傳非 null 值，所以移除 null 分支不改變任何正式行為；`LibraryScreen`、`LibrarySearchScreen`、`SettingsScaffold` 的簽名與行為本 Issue 不動。
- **範圍外**：不動 `SyncDependencies`／`SourceDependencies`／`AppearanceDependencies`／`AppDependencies`（Issue 12/13）；不動 `main.dart`；不動 `LibraryScreen` 等畫面的建構子；不改 `TtsProvider` 介面；不改 `fullTextSearchSettingsRepository`（只有設定頁用，不屬於閱讀器組）。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，用 `run_in_background`，**必須在 `app/` 目錄下執行**）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`（新增／修改畫面字串或測試後）。
- **Windows 環境**：用 Bash 工具（Git Bash）；`python` 不可用（只是 Windows Store 殼，會靜默失敗，不要用來編輯檔案）；多數原始檔是 CRLF，Edit 的定位字串不要含換行；一次性腳本用 Node，放 worktree 根目錄的 `.scratch/`（untracked，不進版控；提交時一律用明確路徑 `git add`，不用 `git add -A`）。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：計畫先審查再動手；程式審查先出報告（存於 `reviews/`，gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。

## 需使用者確認的前提（審查計畫時請回答）

本計畫在以下四點做了選擇，若不同意須在動手前改計畫：

1. **移除「依賴缺席」測試。** `ReaderScreen` 現有約 20 個測試斷言「未提供 X 時功能停用」（例如未提供 `bookmarksRepository` 時筆記按鈕停用、未提供 `ttsProvider` 時不顯示 TTS 按鈕、`searchRepository`／`libraryRepository` 為 null 時搜尋顯示不可用提示）。正式環境從不缺席（`main.dart` 全部傳非 null），non-null 之後這些狀態在型別上不可達，**計畫刪除這些測試**而非改寫成「不可用 adapter」，並在 `epic.md` 列出被刪測試名稱。
2. **TTS 不新增「不可用」adapter。** 審查 I-2 建議 `DisabledTtsProvider` 或旗標；但 `main.dart` 恆傳 `SystemTtsProvider`，沒有任何正式路徑使 TTS「缺席」，新增 adapter 只是為了刪掉的測試而存在（YAGNI）。`ttsAudio` 本來就有 `TtsAudioHandlerHolder.unavailable()` 可用。計畫：`ttsProvider` non-null，移除 `ttsProvider == null` 分支，CBZ 的「停用狀態按鈕」行為保留不動。**ADR 0037 §3 的「TTS 引擎」措辭須同步修訂**（Task 6）。
3. **舊 bundle 的 null 欄位在轉換時丟 `StateError`。** 舊 `LibraryReaderFeatureRepositories` 欄位仍是 nullable（Issue 12/13 才遷移），轉換成 non-null 的新組時，遇到 null 就丟 `StateError('<欄位名>')`。正式環境不受影響（`main.dart` 全傳值）；但「`LibraryScreen`／搜尋畫面系列測試中，點選書籍進入閱讀器」且使用空 bundle 的案例會失敗，須改用 `test/support/` 新增的 `completeLegacyReaderFeatures()` 補齊（Issue 12/13 隨舊 bundle 一併移除）。數量於 Task 4 才知道。
4. **轉換函式的呼叫點是三處，不是 ADR 寫的一處。** ADR 0037 §6 寫「只在 `buildReaderScreen` 暫時組裝」；實際上舊 bundle 持有者有三個呼叫點：`library_screen.dart:472`、`library_search_screen.dart:178`（開閱讀器）、`library_search_screen.dart:405`（開 `BookSearchScreen`）。計畫改為「只在 `reader_screen_route.dart` 提供的單一函式 `readerFeatureDependenciesFromLegacy`，由尚未遷移的外層畫面呼叫」，ADR 措辭同步修訂（Task 6）。

## Review Focus

最可能咬到使用者的情況（依可能性排序），每條都有對應測試：

1. **依賴組裝後某個欄位沒有到達使用端（本 Epic 要根除的缺陷類型）。** → Task 2／4：`buildReaderScreen` 欄位對帳測試改為斷言 `screen.dependencies` 內 18 個欄位逐一 `same(...)`，且 `syncCheckpointTrigger` 來自 `sync`、`libraryRepository`／`prefsManager` 來自參數。
2. **「閱讀器→單書搜尋→閱讀器」（`fromReader: false` 路徑）開出的閱讀器遺失依賴。** → Task 4：`BookSearchScreen` 收到的 `dependencies` 與它推入的 `ReaderScreen.dependencies` 必須是 `same`（同一實例，不是重建）；閱讀器開 `BookSearchScreen` 時傳的也是自己的 `dependencies`（`same`）。
3. **舊 bundle 缺欄位時，在轉換處就明確失敗，而不是在閱讀器深處 NPE。** → Task 2：`readerFeatureDependenciesFromLegacy` 對每個必要欄位為 null 的情形各一個測試，訊息含欄位名。
4. **預設全 fake 讓原本沒出現的功能出現，引發既有測試失敗（計時器未結束、重複 widget、pumpAndSettle 逾時）。** → Task 5：分類處理規則；結果記錄於 `epic.md`。
5. **無 FTS5 裝置（`isFullTextSearchAvailable: false`）從閱讀器進入單書搜尋仍顯示降級提示。** → Task 4：保留並改寫既有測試，斷言 `BookSearchScreen` 讀到的是組內的 `false`。
6. **CBZ 有 `ttsProvider` 仍顯示停用狀態的 TTS 按鈕（非隱藏）。** → 既有測試保留，不得被當成「缺席測試」誤刪。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/screens/reader_feature_dependencies.dart` | 新增 | `ReaderFeatureDependencies`（18 欄位，non-null，不可變） |
| `app/test/support/fake_layout_preset_repository.dart` | 新增 | `LayoutPresetRepository` 沒有現成 Fake，補一個（原本只能用真實 in-memory sqflite） |
| `app/test/support/fake_reader_feature_dependencies.dart` | 新增 | `fakeReaderFeatureDependencies({...覆寫})` 預設全 fake 工廠、`completeLegacyReaderFeatures()` |
| `app/test/support/fake_reader_feature_dependencies_test.dart` | 新增 | 工廠自身測試（Task 1 先通過才改 `ReaderScreen`） |
| `app/lib/screens/reader_screen_route.dart` | 修改 | 新增 `readerFeatureDependenciesFromLegacy`；`buildReaderScreen` 改收 `dependencies` |
| `app/lib/screens/reader_screen.dart` | 修改 | 建構子收 `dependencies`；移除 17 個欄位與 null 分支；開單書搜尋改傳 `dependencies` |
| `app/lib/screens/book_search_screen.dart` | 修改 | 收 `ReaderFeatureDependencies`（取代 `prefsManager`／`libraryRepository`／`readerFeatureRepositories`／`syncDependencies`） |
| `app/lib/screens/library_screen.dart`、`library_search_screen.dart` | 修改 | 三個呼叫點改呼叫 `readerFeatureDependenciesFromLegacy`（不動簽名） |
| 測試：`reader_screen_test.dart`（249 處）、`reader_screen_route_test.dart`、`reader_screen_stats_harness.dart`、`reader_screen_stats_test.dart`（讀 `readerFeatureRepositories` 並含缺席測試）、`reader_screen_stats_lifecycle_test.dart`、`reader_screen_stats_activity_test.dart`、`reader_screen_tts_degraded_notice_test.dart`、`reader_screen_tts_late_handler_test.dart`、`book_search_screen_test.dart`、`library_screen_test.dart`、`library_search_screen_test.dart` 與其他以 analyze 找到的檔案 | 修改 | 改用新建構子與工廠；刪除「缺席」測試 |
| `docs/adr/0037-…md`、`docs/epics/epic-54-…/{epic.md,issues.md}`、`docs/epics.md` | 修改 | ADR 措辭修訂、開發記錄、狀態 |

---

### Task 0：提交計畫、建立 worktree、記錄基準

**Files：**
- Commit：本計畫檔與 `issues.md` 狀態更新（在 `main` 上，純文件）
- 建立 worktree：`.worktrees/epic-54-issue-11-reader-deps`（`.worktrees/` 已 gitignore）

- [x] **Step 1：提交計畫（在 `main`）**

```bash
cd /c/Users/fycdc/AI/elinkBook
git add docs/epics/epic-54-architecture-optimization/plans/plan-issue-11.md docs/epics/epic-54-architecture-optimization/issues.md
git commit -m "docs(epic-54): Issue 11 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [x] **Step 2：建立 worktree 與分支**

```bash
git worktree add .worktrees/epic-54-issue-11-reader-deps -b epic-54/issue-11-reader-deps
cd .worktrees/epic-54-issue-11-reader-deps/app && flutter pub get
```

- [x] **Step 3：記錄異動範圍的基準（零回歸對照用）**

```bash
cd /c/Users/fycdc/AI/elinkBook/.worktrees/epic-54-issue-11-reader-deps/app
flutter test test/screens/reader_screen_test.dart test/screens/reader_screen_route_test.dart test/screens/book_search_screen_test.dart test/screens/library_screen_test.dart test/screens/library_search_screen_test.dart test/screens/reader_screen_tts_degraded_notice_test.dart test/screens/reader_screen_tts_late_handler_test.dart test/screens/reader_screen_stats_test.dart test/screens/reader_screen_stats_lifecycle_test.dart test/screens/reader_screen_stats_activity_test.dart 2>&1 | tail -3
```

把最後一行「`+N: All tests passed!`」的 N 記下，寫進 `epic.md` 的開發記錄作為基準（預期全過；若有既存失敗，先記錄不處理）。

---

### Task 1：`ReaderFeatureDependencies`、`FakeLayoutPresetRepository`、預設全 fake 工廠

先建工廠並通過自身測試，才動 `ReaderScreen`（審查 M-1）。這個 Task 結束時整個專案仍可編譯、既有測試不受影響（只新增檔案）。

**Files：**
- Create：`app/lib/screens/reader_feature_dependencies.dart`
- Create：`app/test/support/fake_layout_preset_repository.dart`
- Create：`app/test/support/fake_reader_feature_dependencies.dart`
- Test：`app/test/support/fake_reader_feature_dependencies_test.dart`

**Interfaces：**
- Produces：`class ReaderFeatureDependencies`（欄位見下）、`ReaderFeatureDependencies fakeReaderFeatureDependencies({...})`、`LibraryReaderFeatureRepositories completeLegacyReaderFeatures()`、`LibrarySyncDependencies completeLegacySyncDependencies()`。

- [x] **Step 1：確認 `LayoutPresetRepository` 的公開方法，才能寫 Fake**

```bash
cd /c/Users/fycdc/AI/elinkBook/.worktrees/epic-54-issue-11-reader-deps/app
grep -n "^  Future<\|^  Stream<\|^  [A-Za-z<>?]* get " lib/reader/layout_preset_repository.dart
```

把列出的每個公開方法在 Fake 中實作一遍（記憶體 `List<LayoutPreset>`，行為比照真實類別文件註解：依 `id ASC` 排序）。Fake 以 `implements LayoutPresetRepository` 宣告，**不呼叫** `super` 的建構子（`LayoutPresetRepository` 是 `const LayoutPresetRepository(this._db)`，`implements` 不需要）。

- [x] **Step 2：寫失敗測試（工廠自身）**

建立 `test/support/fake_reader_feature_dependencies_test.dart`：

```dart
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_bookmarks_repository.dart';
import 'fake_reader_feature_dependencies.dart';

void main() {
  group('fakeReaderFeatureDependencies', () {
    test('不傳任何覆寫時，18 個欄位全部有預設 fake（非 null）', () {
      final deps = fakeReaderFeatureDependencies();

      expect(deps.prefsManager, isNotNull);
      expect(deps.libraryRepository, isNotNull);
      expect(deps.bookImportService, isNotNull);
      expect(deps.bookmarksRepository, isNotNull);
      expect(deps.highlightsRepository, isNotNull);
      expect(deps.notesRepository, isNotNull);
      expect(deps.customFontsRepository, isNotNull);
      expect(deps.downloadableFontStore, isNotNull);
      expect(deps.layoutPresetRepository, isNotNull);
      expect(deps.bookReaderPrefsRepository, isNotNull);
      expect(deps.searchRepository, isNotNull);
      expect(deps.readingStatsRepository, isNotNull);
      expect(deps.readerActivityTracker, isNotNull);
      expect(deps.syncCheckpointTrigger, isNotNull);
      expect(deps.ttsProvider, isNotNull);
      expect(deps.ttsAudio, isNotNull);
      expect(deps.ttsAudioFocusSource, isNotNull);
      expect(deps.isFullTextSearchAvailable, isTrue);
    });

    test('覆寫的欄位原樣（同一實例）帶入，其餘維持預設', () {
      final bookmarks = FakeBookmarksRepository();

      final deps = fakeReaderFeatureDependencies(
        bookmarksRepository: bookmarks,
        isFullTextSearchAvailable: false,
      );

      expect(deps.bookmarksRepository, same(bookmarks));
      expect(deps.isFullTextSearchAvailable, isFalse);
    });

    test('兩次呼叫不共用狀態（各自獨立的 fake 實例）', () {
      final a = fakeReaderFeatureDependencies();
      final b = fakeReaderFeatureDependencies();

      expect(a.bookmarksRepository, isNot(same(b.bookmarksRepository)));
    });
  });

  group('completeLegacyReaderFeatures', () {
    test('覆寫的欄位原樣（同一實例）帶入，其餘維持預設非 null', () {
      final bookmarks = FakeBookmarksRepository();
      final trigger = SyncCheckpointTrigger(
        runCheckpoint: () async => SyncCheckpointResult.notLoggedIn,
      );

      final features = completeLegacyReaderFeatures(
        bookmarksRepository: bookmarks,
        isFullTextSearchAvailable: false,
      );
      final sync =
          completeLegacySyncDependencies(syncCheckpointTrigger: trigger);

      expect(features.bookmarksRepository, same(bookmarks));
      expect(features.isFullTextSearchAvailable, isFalse);
      expect(features.highlightsRepository, isNotNull);
      expect(sync.syncCheckpointTrigger, same(trigger));
    });

    test('舊 bundle 的 15 個閱讀器欄位全部非 null，且 sync 帶有 syncCheckpointTrigger', () {
      final features = completeLegacyReaderFeatures();
      final sync = completeLegacySyncDependencies();

      expect(features.bookmarksRepository, isNotNull);
      expect(features.highlightsRepository, isNotNull);
      expect(features.notesRepository, isNotNull);
      expect(features.customFontsRepository, isNotNull);
      expect(features.downloadableFontStore, isNotNull);
      expect(features.layoutPresetRepository, isNotNull);
      expect(features.bookReaderPrefsRepository, isNotNull);
      expect(features.ttsProvider, isNotNull);
      expect(features.ttsAudio, isNotNull);
      expect(features.ttsAudioFocusSource, isNotNull);
      expect(features.readerActivityTracker, isNotNull);
      expect(features.searchRepository, isNotNull);
      expect(features.bookImportService, isNotNull);
      expect(features.readingStatsRepository, isNotNull);
      expect(sync.syncCheckpointTrigger, isNotNull);
    });
  });
}
```

（`LibraryReaderFeatureRepositories`／`LibrarySyncDependencies` 在 `library_screen_dependencies.dart`；測試檔頂端已 import。）

- [x] **Step 3：跑測試確認失敗**

```bash
flutter test test/support/fake_reader_feature_dependencies_test.dart
```

預期：編譯失敗（`reader_feature_dependencies.dart`、`fake_reader_feature_dependencies.dart` 不存在）。

- [x] **Step 4：實作 `ReaderFeatureDependencies`**

建立 `app/lib/screens/reader_feature_dependencies.dart`：

```dart
import 'package:flutter/foundation.dart';

import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/bookmarks_repository.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/downloadable_font_store.dart';
import '../reader/highlights_repository.dart';
import '../reader/layout_preset_repository.dart';
import '../reader/notes_repository.dart';
import '../reader/reader_activity_tracker.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/tts_audio_focus_source.dart';
import '../reader/tts_audio_handler_startup.dart';
import '../reader/tts_provider.dart';
import '../search/search_repository.dart';
import '../stats/reading_stats_repository.dart';
import '../sync/sync_checkpoint_trigger.dart';

/// 閱讀器功能依賴組（ADR 0037）：`ReaderScreen` 與 `BookSearchScreen` 各自只
/// 接收這一個物件，取代逐欄傳遞。「閱讀器→單書搜尋→閱讀器」整組轉傳同一個
/// 實例，不再手動逐欄重建。
///
/// 全部 non-null、required：`main.dart` 啟動時全部都會建好，缺依賴是編譯錯誤，
/// 不是執行期靜默失效。`syncCheckpointTrigger` 同時也屬於同步依賴組，由
/// `AppDependencies` 建構一次、同一實例放進各組（Issue 13）。
///
/// 依書本才能建構的 `readingStatsTracker` 與純為 widget test 注入的
/// `pickSingleBookFile` **不在這裡**，留在 `ReaderScreen` 建構子上。
@immutable
class ReaderFeatureDependencies {
  final ReaderPrefsManager prefsManager;
  final LibraryRepository libraryRepository;
  final BookImportService bookImportService;
  final BookmarksRepository bookmarksRepository;
  final HighlightsRepository highlightsRepository;
  final NotesRepository notesRepository;
  final CustomFontsRepository customFontsRepository;
  final DownloadableFontStore downloadableFontStore;
  final LayoutPresetRepository layoutPresetRepository;
  final BookReaderPrefsRepository bookReaderPrefsRepository;
  final SearchRepository searchRepository;

  /// 本裝置系統 SQLite 是否有 FTS5 模組可用；`false` 時單書搜尋顯示降級提示。
  final bool isFullTextSearchAvailable;
  final ReadingStatsRepository readingStatsRepository;
  final ReaderActivityTracker readerActivityTracker;
  final SyncCheckpointTrigger syncCheckpointTrigger;
  final TtsProvider ttsProvider;

  /// 啟動階段 TTS 音訊服務 holder；服務不可用時為 `TtsAudioHandlerHolder.unavailable()`
  /// 或 `.degraded()`，不是 null。
  final TtsAudioHandlerHolder ttsAudio;
  final TtsAudioFocusSource ttsAudioFocusSource;

  const ReaderFeatureDependencies({
    required this.prefsManager,
    required this.libraryRepository,
    required this.bookImportService,
    required this.bookmarksRepository,
    required this.highlightsRepository,
    required this.notesRepository,
    required this.customFontsRepository,
    required this.downloadableFontStore,
    required this.layoutPresetRepository,
    required this.bookReaderPrefsRepository,
    required this.searchRepository,
    required this.isFullTextSearchAvailable,
    required this.readingStatsRepository,
    required this.readerActivityTracker,
    required this.syncCheckpointTrigger,
    required this.ttsProvider,
    required this.ttsAudio,
    required this.ttsAudioFocusSource,
  });
}
```

- [x] **Step 5：實作 `FakeLayoutPresetRepository`**

建立 `app/test/support/fake_layout_preset_repository.dart`，依 Step 1 列出的公開方法逐一實作（記憶體清單）。檔案頂端註解說明：「`LayoutPresetRepository` 原本沒有 Fake，只能用 in-memory sqflite；工廠需要無 I/O 的預設值，故補上」。簽名必須與真實類別一致（用 `@override` 讓分析器檢查）。

- [x] **Step 6：實作工廠**

建立 `app/test/support/fake_reader_feature_dependencies.dart`：

```dart
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/reader/custom_fonts_repository.dart';
import 'package:elinkbook/reader/downloadable_font_store.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:elinkbook/reader/notes_repository.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/reader/tts_audio_focus_source.dart';
import 'package:elinkbook/reader/tts_audio_handler_startup.dart';
import 'package:elinkbook/reader/tts_provider.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/reader_feature_dependencies.dart';
import 'package:elinkbook/search/search_repository.dart';
import 'package:elinkbook/stats/reading_stats_repository.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';

import 'fake_book_import_service.dart';
import 'fake_book_reader_prefs_repository.dart';
import 'fake_bookmarks_repository.dart';
import 'fake_custom_fonts_repository.dart';
import 'fake_downloadable_font_store.dart';
import 'fake_highlights_repository.dart';
import 'fake_layout_preset_repository.dart';
import 'fake_library_repository.dart';
import 'fake_notes_repository.dart';
import 'fake_reader_prefs_manager.dart';
import 'fake_reading_stats_repository.dart';
import 'fake_search_repository.dart';
import 'fake_tts_audio_focus_source.dart';
import 'fake_tts_provider.dart';

/// 預設全 fake 的閱讀器功能依賴組（ADR 0037）。只覆寫情境需要的欄位，其餘用
/// 各自獨立的 fake 實例；每次呼叫都建新實例，測試之間不共用狀態。
ReaderFeatureDependencies fakeReaderFeatureDependencies({
  ReaderPrefsManager? prefsManager,
  LibraryRepository? libraryRepository,
  BookImportService? bookImportService,
  BookmarksRepository? bookmarksRepository,
  HighlightsRepository? highlightsRepository,
  NotesRepository? notesRepository,
  CustomFontsRepository? customFontsRepository,
  DownloadableFontStore? downloadableFontStore,
  LayoutPresetRepository? layoutPresetRepository,
  BookReaderPrefsRepository? bookReaderPrefsRepository,
  SearchRepository? searchRepository,
  bool isFullTextSearchAvailable = true,
  ReadingStatsRepository? readingStatsRepository,
  ReaderActivityTracker? readerActivityTracker,
  SyncCheckpointTrigger? syncCheckpointTrigger,
  TtsProvider? ttsProvider,
  TtsAudioHandlerHolder? ttsAudio,
  TtsAudioFocusSource? ttsAudioFocusSource,
}) {
  return ReaderFeatureDependencies(
    prefsManager: prefsManager ?? FakeReaderPrefsManager(),
    libraryRepository: libraryRepository ?? FakeLibraryRepository(),
    bookImportService: bookImportService ?? FakeBookImportService(),
    bookmarksRepository: bookmarksRepository ?? FakeBookmarksRepository(),
    highlightsRepository: highlightsRepository ?? FakeHighlightsRepository(),
    notesRepository: notesRepository ?? FakeNotesRepository(),
    customFontsRepository: customFontsRepository ?? FakeCustomFontsRepository(),
    downloadableFontStore: downloadableFontStore ?? FakeDownloadableFontStore(),
    layoutPresetRepository:
        layoutPresetRepository ?? FakeLayoutPresetRepository(),
    bookReaderPrefsRepository:
        bookReaderPrefsRepository ?? FakeBookReaderPrefsRepository(),
    searchRepository: searchRepository ?? FakeSearchRepository(),
    isFullTextSearchAvailable: isFullTextSearchAvailable,
    readingStatsRepository:
        readingStatsRepository ?? FakeReadingStatsRepository(),
    readerActivityTracker: readerActivityTracker ?? ReaderActivityTracker(),
    syncCheckpointTrigger: syncCheckpointTrigger ?? _noopSyncCheckpointTrigger(),
    ttsProvider: ttsProvider ?? FakeTtsProvider(),
    ttsAudio: ttsAudio ?? TtsAudioHandlerHolder.unavailable(),
    ttsAudioFocusSource: ttsAudioFocusSource ?? FakeTtsAudioFocusSource(),
  );
}

SyncCheckpointTrigger _noopSyncCheckpointTrigger() => SyncCheckpointTrigger(
      runCheckpoint: () async => SyncCheckpointResult.notLoggedIn,
    );

/// 供尚未遷移的 `LibraryScreen`／`LibrarySearchScreen` 系列測試使用：舊 bundle
/// 欄位仍是 nullable，轉換成 non-null 的新組時遇到 null 會丟 `StateError`
/// （見 `readerFeatureDependenciesFromLegacy`）。需要「點選書籍進入閱讀器」的
/// 測試用這個補齊。**Issue 12／13 移除舊 bundle 時一併刪除。**
/// 與 [fakeReaderFeatureDependencies] 同形：14 個 repository／service 欄位與
/// `isFullTextSearchAvailable` 皆可選具名覆寫，測試只覆寫需要驗證貫穿的欄位。
LibraryReaderFeatureRepositories completeLegacyReaderFeatures({
  BookmarksRepository? bookmarksRepository,
  HighlightsRepository? highlightsRepository,
  NotesRepository? notesRepository,
  CustomFontsRepository? customFontsRepository,
  DownloadableFontStore? downloadableFontStore,
  LayoutPresetRepository? layoutPresetRepository,
  BookReaderPrefsRepository? bookReaderPrefsRepository,
  TtsProvider? ttsProvider,
  TtsAudioHandlerHolder? ttsAudio,
  TtsAudioFocusSource? ttsAudioFocusSource,
  ReaderActivityTracker? readerActivityTracker,
  bool isFullTextSearchAvailable = true,
  SearchRepository? searchRepository,
  BookImportService? bookImportService,
  ReadingStatsRepository? readingStatsRepository,
}) {
  return LibraryReaderFeatureRepositories(
    bookmarksRepository: bookmarksRepository ?? FakeBookmarksRepository(),
    highlightsRepository: highlightsRepository ?? FakeHighlightsRepository(),
    notesRepository: notesRepository ?? FakeNotesRepository(),
    customFontsRepository:
        customFontsRepository ?? FakeCustomFontsRepository(),
    downloadableFontStore:
        downloadableFontStore ?? FakeDownloadableFontStore(),
    layoutPresetRepository:
        layoutPresetRepository ?? FakeLayoutPresetRepository(),
    bookReaderPrefsRepository:
        bookReaderPrefsRepository ?? FakeBookReaderPrefsRepository(),
    ttsProvider: ttsProvider ?? FakeTtsProvider(),
    ttsAudio: ttsAudio ?? TtsAudioHandlerHolder.unavailable(),
    ttsAudioFocusSource: ttsAudioFocusSource ?? FakeTtsAudioFocusSource(),
    readerActivityTracker: readerActivityTracker ?? ReaderActivityTracker(),
    isFullTextSearchAvailable: isFullTextSearchAvailable,
    searchRepository: searchRepository ?? FakeSearchRepository(),
    bookImportService: bookImportService ?? FakeBookImportService(),
    readingStatsRepository:
        readingStatsRepository ?? FakeReadingStatsRepository(),
  );
}

/// 與 [completeLegacyReaderFeatures] 配對：帶有 `syncCheckpointTrigger` 的舊同步 bundle，
/// 可覆寫 `syncCheckpointTrigger`。
LibrarySyncDependencies completeLegacySyncDependencies({
  SyncCheckpointTrigger? syncCheckpointTrigger,
}) {
  return LibrarySyncDependencies(
    syncCheckpointTrigger:
        syncCheckpointTrigger ?? _noopSyncCheckpointTrigger(),
  );
}
```

若某個 Fake 的建構子需要參數（Step 1 之外未逐一驗證），以 `reader_screen_route_test.dart:74-92` 的建構方式為準（該處已無參數建構 `FakeReaderPrefsManager()`、`FakeLibraryRepository()`、`FakeBookmarksRepository()`、`FakeHighlightsRepository()`、`FakeNotesRepository()`、`FakeCustomFontsRepository()`、`FakeDownloadableFontStore()`、`FakeBookReaderPrefsRepository()`、`FakeTtsProvider()`、`FakeTtsAudioFocusSource()`、`FakeSearchRepository()`、`FakeBookImportService()`）。`FakeReadingStatsRepository()` 若需要必填參數，補上最小值並在註解說明。

- [x] **Step 7：跑測試確認通過，並分析**

```bash
flutter test test/support/fake_reader_feature_dependencies_test.dart
flutter analyze lib/screens/reader_feature_dependencies.dart test/support
```

預期：測試 5 個通過；analyze 無問題。

- [x] **Step 8：提交**

```bash
git add app/lib/screens/reader_feature_dependencies.dart app/test/support/fake_layout_preset_repository.dart app/test/support/fake_reader_feature_dependencies.dart app/test/support/fake_reader_feature_dependencies_test.dart
git commit -m "feat(epic-54): 新增 ReaderFeatureDependencies 與預設全 fake 測試工廠（Issue 11 Task 1）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：lib 端切換（`ReaderScreen`、`BookSearchScreen`、轉換函式、呼叫點）

**這個 Task 結束時 `test/` 無法編譯**（`ReaderScreen` 建構子已改）。這是 ADR 0037 §6 要求的「一刀切」；**不在 Task 2 結束時提交**，提交安排在 Task 5 結束時（避免留下 test 編譯失敗的 commit 造成 bisect 中斷）。驗證用 `flutter analyze lib`。

**Files：**
- Modify：`app/lib/screens/reader_screen_route.dart`
- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/lib/screens/book_search_screen.dart`
- Modify：`app/lib/screens/library_screen.dart:472`、`app/lib/screens/library_search_screen.dart:178,405`

**Interfaces：**
- Consumes：Task 1 的 `ReaderFeatureDependencies`。
- Produces：
  - `ReaderFeatureDependencies readerFeatureDependenciesFromLegacy({required ReaderPrefsManager prefsManager, required LibraryReaderFeatureRepositories features, required LibrarySyncDependencies sync, required LibraryRepository libraryRepository})`——任一必要欄位為 null 丟 `StateError('ReaderFeatureDependencies 缺少 <欄位名>')`。
  - `ReaderScreen buildReaderScreen({required Book book, required ReaderFeatureDependencies dependencies, required bool isEinkMode, ReaderJumpTarget? initialJumpTarget})`。
  - `ReaderScreen({super.key, required filePath, required bookId, required ReaderFeatureDependencies dependencies, bookTitle, bookAuthor, bookProgress = 0.0, isFixedLayout, isEinkMode = false, initialJumpTarget, pickSingleBookFile, readingStatsTracker})`，公開欄位 `final ReaderFeatureDependencies dependencies`。
  - `BookSearchScreen({super.key, required Book book, initialQuery = '', required ReaderFeatureDependencies dependencies, isEinkMode = false, fromReader = false})`。

- [x] **Step 1：`reader_screen_route.dart`——轉換函式與新 `buildReaderScreen`**

整檔改寫為（保留既有檔頭註解的歷史脈絡，但更新說明）：

```dart
// app/lib/screens/reader_screen_route.dart
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../reader/reader_jump_target.dart';
import '../reader/reader_prefs_manager.dart';
import 'library_screen_dependencies.dart';
import 'reader_feature_dependencies.dart';
import 'reader_screen.dart';

/// 【過渡用，Issue 12／13 移除】把尚未遷移的外層畫面（`LibraryScreen`、
/// `LibrarySearchScreen`）持有的舊 bundle 組裝成新的 [ReaderFeatureDependencies]
/// （ADR 0037 §6）。舊 bundle 欄位是 nullable，新組是 non-null：遇到 null 就丟
/// [StateError]，訊息含欄位名——正式環境 `main.dart` 全部傳值，不會觸發；
/// 測試需用 `completeLegacyReaderFeatures()` 補齊。
ReaderFeatureDependencies readerFeatureDependenciesFromLegacy({
  required ReaderPrefsManager prefsManager,
  required LibraryReaderFeatureRepositories features,
  required LibrarySyncDependencies sync,
  required LibraryRepository libraryRepository,
}) {
  T need<T>(T? value, String name) {
    if (value == null) {
      throw StateError('ReaderFeatureDependencies 缺少 $name');
    }
    return value;
  }

  return ReaderFeatureDependencies(
    prefsManager: prefsManager,
    libraryRepository: libraryRepository,
    bookImportService: need(features.bookImportService, 'bookImportService'),
    bookmarksRepository:
        need(features.bookmarksRepository, 'bookmarksRepository'),
    highlightsRepository:
        need(features.highlightsRepository, 'highlightsRepository'),
    notesRepository: need(features.notesRepository, 'notesRepository'),
    customFontsRepository:
        need(features.customFontsRepository, 'customFontsRepository'),
    downloadableFontStore:
        need(features.downloadableFontStore, 'downloadableFontStore'),
    layoutPresetRepository:
        need(features.layoutPresetRepository, 'layoutPresetRepository'),
    bookReaderPrefsRepository:
        need(features.bookReaderPrefsRepository, 'bookReaderPrefsRepository'),
    searchRepository: need(features.searchRepository, 'searchRepository'),
    isFullTextSearchAvailable: features.isFullTextSearchAvailable,
    readingStatsRepository:
        need(features.readingStatsRepository, 'readingStatsRepository'),
    readerActivityTracker:
        need(features.readerActivityTracker, 'readerActivityTracker'),
    syncCheckpointTrigger:
        need(sync.syncCheckpointTrigger, 'syncCheckpointTrigger'),
    ttsProvider: need(features.ttsProvider, 'ttsProvider'),
    ttsAudio: need(features.ttsAudio, 'ttsAudio'),
    ttsAudioFocusSource:
        need(features.ttsAudioFocusSource, 'ttsAudioFocusSource'),
  );
}

/// 三處開書路徑（書架、全庫搜尋、單書搜尋）共用的 `ReaderScreen` 組裝點
/// （epic-41 Issue 1）。書本欄位由 [book] 帶入，其餘依賴整組由 [dependencies]
/// 帶入。回傳具體型別 [ReaderScreen]，讓呼叫端與測試不轉型直接存取欄位。
ReaderScreen buildReaderScreen({
  required Book book,
  required ReaderFeatureDependencies dependencies,
  required bool isEinkMode,
  ReaderJumpTarget? initialJumpTarget,
}) {
  return ReaderScreen(
    filePath: book.filePath,
    bookId: book.id,
    dependencies: dependencies,
    bookTitle: book.title,
    bookAuthor: book.author,
    bookProgress: book.progress,
    isFixedLayout: book.isFixedLayout,
    isEinkMode: isEinkMode,
    initialJumpTarget: initialJumpTarget,
  );
}
```

- [x] **Step 2：`reader_screen.dart`——建構子與欄位**

1. 刪除 `reader_screen.dart:135-279` 之間 17 個依賴欄位宣告與其文件註解（`bookmarksRepository` … `readingStatsRepository`，以及 `prefsManager`、`libraryRepository`），僅保留：`filePath`、`bookId`、`bookTitle`、`bookAuthor`、`bookProgress`、`isFixedLayout`、`isEinkMode`、`initialJumpTarget`、`pickSingleBookFile`、`readingStatsTracker` 的宣告與註解；新增：

```dart
  /// 閱讀器功能依賴組（ADR 0037）。整組由呼叫端提供，內部不再逐欄接收；
  /// 開單書搜尋時整組轉傳給 [BookSearchScreen]。
  final ReaderFeatureDependencies dependencies;
```

2. `pickSingleBookFile`、`readingStatsTracker` 的註解各補一句：「僅供測試注入（ADR 0037 例外）」。
3. 建構子改為：

```dart
  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.dependencies,
    this.bookTitle,
    this.bookAuthor,
    this.bookProgress = 0.0,
    this.isFixedLayout,
    this.isEinkMode = false,
    this.initialJumpTarget,
    this.pickSingleBookFile,
    this.readingStatsTracker,
  });
```

4. 加入 `import 'reader_feature_dependencies.dart';`，刪除因此不再使用的 import（以 `flutter analyze` 的 unused_import 為準）。

- [x] **Step 3：`reader_screen.dart`——把 `widget.X` 改為 `widget.dependencies.X` 並移除 null 分支**

依下表逐一處理（行號為改動前的行號，僅供定位；改完一處就重新跑 `flutter analyze lib/screens/reader_screen.dart` 看剩餘錯誤，**不要憑行號盲改**）。通則：型別不再可為 null，所以 `x == null`／`x != null` 判斷、`?.`、`!`、`if (repository == null) return;` 全部移除；被移除分支內的行為（提示、提早 return）一併刪除。

| 位置（約） | 現況 | 改為 |
|---|---|---|
| 454 | `customFontsRepository == null && downloadableFontStore == null` 判斷字型是否「不需等待」 | 兩者必在，此條件恆為 false：整個判斷與其「不等待」捷徑刪除，永遠走載入已下載字型的路徑（讀取行 440-470 前後的註解確認語意再刪） |
| 525-528、1710、2041 | `highlightsRepository != null && notesRepository != null` | 條件恆真，移除條件，直接使用 `widget.dependencies.highlightsRepository`／`notesRepository` |
| 597、751、770 | `widget.ttsAudio` 可為 null | `widget.dependencies.ttsAudio`；`?.handler` 改 `.handler`（`handler` 本身仍可為 null，保留）；`?.consumeDegradedNotice()` 改 `.consumeDegradedNotice()` |
| 600 | `final importService = widget.bookImportService;`（null 則不提供重新連結） | 直接 `widget.dependencies.bookImportService`；`OpenBookFlow` 的重新連結不再因 null 而停用（讀 600-620 附近與 `OpenBookFlow` 建構處確認，保留 `OpenBookFlow` 內部對「選檔取消」等行為） |
| 619-621 | 傳 `statsRepository`／`syncCheckpointTrigger`／`readerActivityTracker` 給 `ReadingSession` | 改傳 `widget.dependencies.*`；`ReadingSession` 本身是否接受 nullable 參數**本 Issue 不動**（傳入非 null 值即可，其內部 null 分支保留，另開工單） |
| 714、1313 | `widget.libraryRepository` null 守衛 | 移除守衛 |
| 1039、1252、1382 | `layoutPresetRepository` null 守衛（含 9364 附近測試所述「為 null 時顯示提示」） | 移除守衛與該提示分支。**`readerSaveAsPresetUnavailableMessage`（`reader_screen.dart:1044` 唯一使用處）因此成為孤兒 ARB 鍵：保留鍵（不動 l10n），在 `epic.md` 記錄「鍵可後續清理」** |
| 1179、1227 | `bookReaderPrefsRepository` null 守衛 | 移除 |
| 1329、1421、1453、1616、2626、2630、3066、3070 | `bookmarksRepository == null` 時筆記／書籤按鈕停用 | 按鈕恆啟用；`onBookmarkTap`／`onAnnotationsTap` 不再因 null 回傳 null（若原本還有其他停用條件如 FXL 版面，保留那些條件） |
| 1360、1371、3479 | `downloadableFontStore`／`customFontsRepository` 守衛、`?.directory` | 移除守衛；`?.directory` 改 `.directory` |
| 1648-1655 | 建構 `NotesBottomSheet` 時 `(isFoliateFormat(format) && !_isFixedLayout) \|\| format == BookFormat.pdf ? widget.highlightsRepository : null`（`notesRepository` 同形）。**FXL 排除劃線／備註是結構性必然（epic-20 Issue 4、ADR 0017），三元條件不可刪** | 保留整個三元條件與 `: null` 分支不變，只把 true 分支的 `widget.highlightsRepository`／`widget.notesRepository` 改為 `widget.dependencies.highlightsRepository`／`widget.dependencies.notesRepository`（`NotesBottomSheet` 的對應參數維持 nullable，不動） |
| 1882-1893 | `searchRepository == null \|\| libraryRepository == null \|\| book == null` 顯示「搜尋不可用」 | 只保留 `book == null` 的判斷（`_buildSearchableBook()` 為 null 時的原行為，若原本三者共用同一則 SnackBar 就保留 SnackBar，僅條件縮減）。`readerSearchUnavailableMessage` 在 `book == null` 時仍使用，不是孤兒鍵 |
| 1901-1926 | 手動逐欄重建 `LibraryReaderFeatureRepositories`＋`LibrarySyncDependencies` | 整段刪除，改為 `BookSearchScreen(book: book, dependencies: widget.dependencies, isEinkMode: widget.isEinkMode, fromReader: true)`（`searchRepository` 由 `dependencies.searchRepository` 取得，`BookSearchScreen` 內部自取） |
| 2662、2665、2706、2836、3354、3405 | `ttsProvider == null` 隱藏 TTS 入口／不建構 `TtsController`；`ttsAudioFocusSource` null 守衛 | 移除 null 分支；TTS 按鈕恆顯示（CBZ 仍為停用狀態，**保留 `_cbzTtsPanelVisible` 等 CBZ 邏輯不動**）；`TtsController` 仍維持「首次存取才建構」 |
| 2931 | `widget.bookImportService != null && …` | 移除 null 判斷，保留其餘條件 |
| 3347 起註解 | 「`widget.ttsProvider` 為 `null` 時…」 | 同步改註解，不留與型別矛盾的描述 |

`ReaderScreen` 內 `widget.prefsManager`（若有）→ `widget.dependencies.prefsManager`；其餘 `isEinkMode`、`bookTitle` 等不動。

- [x] **Step 4：`book_search_screen.dart`**

欄位與建構子改為：

```dart
class BookSearchScreen extends StatefulWidget {
  final Book book;
  final String initialQuery;
  final ReaderFeatureDependencies dependencies;
  final bool isEinkMode;
  final bool fromReader;

  const BookSearchScreen({
    super.key,
    required this.book,
    this.initialQuery = '',
    required this.dependencies,
    this.isEinkMode = false,
    this.fromReader = false,
  });
```

內文替換：`widget.searchRepository` → `widget.dependencies.searchRepository`；`widget.prefsManager` → `widget.dependencies.prefsManager`；`widget.readerFeatureRepositories.isFullTextSearchAvailable`（三處：約 105、131、141）→ `widget.dependencies.isFullTextSearchAvailable`；`_handleSnippetTap` 內的 `buildReaderScreen(...)` 改為：

```dart
        builder: (_) => buildReaderScreen(
          book: widget.book,
          dependencies: widget.dependencies,
          isEinkMode: widget.isEinkMode,
          initialJumpTarget: jumpTarget,
        ),
```

移除不再使用的 import（`library_repository.dart`、`reader_prefs_manager.dart`、`search_repository.dart`、`library_screen_dependencies.dart`——以 analyzer 為準），加入 `reader_feature_dependencies.dart`。

- [x] **Step 5：三個呼叫點改呼叫轉換函式**

`library_screen.dart:472`：

```dart
            builder: (_) => buildReaderScreen(
              book: book,
              dependencies: readerFeatureDependenciesFromLegacy(
                prefsManager: widget.prefsManager,
                features: widget.readerFeatureRepositories,
                sync: widget.syncDependencies,
                libraryRepository: widget.repository,
              ),
              isEinkMode: widget.themeDependencies.isEinkMode,
            ),
```

`library_search_screen.dart:178`：同樣形式，`libraryRepository: widget.libraryRepository`，`isEinkMode: widget.isEinkMode`，保留 `initialJumpTarget: jumpTarget` 與其註解。

`library_search_screen.dart:405`（開 `BookSearchScreen`）：

```dart
        builder: (_) => BookSearchScreen(
          book: book,
          initialQuery: _controller.text.trim(),
          dependencies: readerFeatureDependenciesFromLegacy(
            prefsManager: widget.prefsManager,
            features: widget.readerFeatureRepositories,
            sync: widget.syncDependencies,
            libraryRepository: widget.libraryRepository,
          ),
          isEinkMode: widget.isEinkMode,
        ),
```

`library_search_screen.dart` 的 `searchRepository: widget.searchRepository` 實參不再傳給 `BookSearchScreen`（改由 `dependencies.searchRepository` 取得，來自 `features.searchRepository`）。**注意**：`LibrarySearchScreen` 自己的 `searchRepository` 建構參數與 `features.searchRepository` 在舊測試中可能是兩個不同實例，Task 4 會處理對應測試。

- [x] **Step 6：分析 lib**

```bash
flutter analyze lib
```

預期：No issues found!（`lib` 範圍；`test` 此時會有大量錯誤，屬預期）。若出現 `unnecessary_null_comparison`／`unnecessary_non_null_assertion`／`unused_*` 警告，代表還有 null 分支或 import 沒清，逐一處理直到乾淨。

---

### Task 3：測試遷移（A）——`ReaderScreen(` 建構呼叫點 codemod

`ReaderScreen(` 在 5 個測試檔共約 267 處，大多只傳 `filePath`／`bookId`／`prefsManager` 幾個參數。用一次性 Node 腳本機械改寫，**腳本放 worktree 根目錄 `.scratch/`，不進版控**。

**Files：**
- Create（`.scratch/`，不提交）：`.scratch/codemod_reader_screen.js`
- Modify：`test/screens/reader_screen_test.dart`、`reader_screen_route_test.dart`（不含 `buildReaderScreen` 區塊，Task 4 處理）、`reader_screen_stats_harness.dart`、`reader_screen_tts_degraded_notice_test.dart`、`reader_screen_tts_late_handler_test.dart`

- [x] **Step 1：寫 codemod 腳本**

存到 worktree 根目錄（`app/` 的上一層）的 `.scratch/codemod_reader_screen.js`（先建立 `.scratch/` 目錄）：

```js
// 一次性：把測試中 ReaderScreen( 的依賴具名參數收進 dependencies: fakeReaderFeatureDependencies(...)
const fs = require('fs');

const MOVED = new Set([
  'prefsManager', 'libraryRepository', 'bookImportService', 'bookmarksRepository',
  'highlightsRepository', 'notesRepository', 'customFontsRepository',
  'downloadableFontStore', 'layoutPresetRepository', 'bookReaderPrefsRepository',
  'searchRepository', 'isFullTextSearchAvailable', 'readingStatsRepository',
  'readerActivityTracker', 'syncCheckpointTrigger', 'ttsProvider', 'ttsAudio',
  'ttsAudioFocusSource',
]);

function skipString(src, i) {
  const q = src[i];
  if (src.startsWith(q.repeat(3), i)) {
    const end = src.indexOf(q.repeat(3), i + 3);
    return end + 2;
  }
  let j = i + 1;
  while (j < src.length && src[j] !== q) {
    if (src[j] === '\\') j++;
    j++;
  }
  return j;
}

// 回傳與 openIdx 的 '(' 配對的 ')' 位置
function matchParen(src, openIdx) {
  let depth = 0;
  for (let i = openIdx; i < src.length; i++) {
    const c = src[i];
    if (c === "'" || c === '"') { i = skipString(src, i); continue; }
    if (c === '/' && src[i + 1] === '/') { i = src.indexOf('\n', i); continue; }
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) { depth--; if (depth === 0) return i; }
  }
  throw new Error('括號不成對');
}

// 以最外層逗號切引數
function splitArgs(body) {
  const args = [];
  let depth = 0, start = 0;
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (c === "'" || c === '"') { i = skipString(body, i); continue; }
    if (c === '/' && body[i + 1] === '/') { i = body.indexOf('\n', i); continue; }
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) depth--;
    else if (c === ',' && depth === 0) { args.push(body.slice(start, i)); start = i + 1; }
  }
  if (body.slice(start).trim()) args.push(body.slice(start));
  return args;
}

const manual = [];
for (const file of process.argv.slice(2)) {
  let src = fs.readFileSync(file, 'utf8');
  const re = /(const\s+)?\bReaderScreen\(/g;
  let out = '', last = 0, m, changed = 0;
  while ((m = re.exec(src)) !== null) {
    const lineStart = src.lastIndexOf('\n', m.index) + 1;
    const linePrefix = src.slice(lineStart, m.index).trimStart();
    if (linePrefix.startsWith('//') || linePrefix.startsWith('///')) continue;
    if (/class\s+$/.test(src.slice(Math.max(0, m.index - 10), m.index))) continue;
    const open = m.index + m[0].length - 1;
    const close = matchParen(src, open);
    const body = src.slice(open + 1, close);
    const args = splitArgs(body);
    const keep = [], moved = [];
    let ok = true;
    for (const a of args) {
      const mm = /^\s*(\w+)\s*:/.exec(a);
      if (!mm) { ok = false; break; }
      (MOVED.has(mm[1]) ? moved : keep).push(a.trim());
    }
    const line = src.slice(0, m.index).split('\n').length;
    if (!ok) { manual.push(`${file}:${line}（引數含註解或無法解析）`); continue; }
    if (moved.length === 0 && keep.some((a) => a.startsWith('dependencies:'))) continue;
    const indent = /^\s*/.exec(src.slice(lineStart))[0];
    const dep = `dependencies: fakeReaderFeatureDependencies(${moved.join(', ')})`;
    const newArgs = [...keep, dep].join(', ');
    out += src.slice(last, m.index) + 'ReaderScreen(' + newArgs + ')';
    last = close + 1;
    changed++;
  }
  out += src.slice(last);
  if (changed && !/fake_reader_feature_dependencies\.dart/.test(out)) {
    const rel = file.includes('/test/screens/') || file.includes('\\test\\screens\\') ? '../support/' : 'support/';
    out = out.replace(/(\nimport [^\n]+;\n)(?!import)/, `$1import '${rel}fake_reader_feature_dependencies.dart';\n`);
  }
  fs.writeFileSync(file, out);
  console.log(`${file}: 改寫 ${changed} 處`);
}
if (manual.length) { console.log('需手動處理：'); manual.forEach((x) => console.log('  ' + x)); }
```

（腳本會把 `const ReaderScreen(` 的 `const` 一併去掉——因為 `fakeReaderFeatureDependencies(...)` 不是常數。匯入插入位置不理想時，改由 `dart format`／手動調整，不影響行為。）

- [x] **Step 2：只對 `ReaderScreen(` 建構點執行（排除 `buildReaderScreen`）**

```bash
cd /c/Users/fycdc/AI/elinkBook/.worktrees/epic-54-issue-11-reader-deps/app
node ../.scratch/codemod_reader_screen.js \
  test/screens/reader_screen_test.dart test/screens/reader_screen_stats_harness.dart \
  test/screens/reader_screen_tts_degraded_notice_test.dart test/screens/reader_screen_tts_late_handler_test.dart \
  test/screens/reader_screen_route_test.dart
```

預期：列出每檔改寫處數（合計應接近 267），以及「需手動處理」清單。若清單非空，逐一手改，改法同上（把移動的參數收進 `dependencies: fakeReaderFeatureDependencies(...)`）。

- [x] **Step 3：格式化並確認 diff 乾淨**

```bash
dart format test/screens/reader_screen_test.dart test/screens/reader_screen_stats_harness.dart test/screens/reader_screen_tts_degraded_notice_test.dart test/screens/reader_screen_tts_late_handler_test.dart test/screens/reader_screen_route_test.dart
git diff --stat
```

注意：`dart format` 只對這幾個檔案執行；如果它大幅改動非 `ReaderScreen(` 區域（代表原檔不是 dart format 風格），改為還原格式化（`git checkout` 後重跑 codemod 而不格式化），不要產生無關 diff。

- [x] **Step 4：分析這些檔案，統計剩餘編譯錯誤**

```bash
flutter analyze test/screens/reader_screen_test.dart test/screens/reader_screen_stats_harness.dart test/screens/reader_screen_tts_degraded_notice_test.dart test/screens/reader_screen_tts_late_handler_test.dart 2>&1 | tail -30
```

預期：剩下的錯誤應只有「讀取 `ReaderScreen` 欄位」類（例如 `.bookmarksRepository` 不存在），留給 Task 4。

---

### Task 4：測試遷移（B）——欄位讀取、`BookSearchScreen`、`buildReaderScreen`、`LibraryScreen` 系列

**Files：** Modify：`test/screens/reader_screen_route_test.dart`、`book_search_screen_test.dart`、`library_screen_test.dart`、`library_search_screen_test.dart`，以及 analyze 找到的其他檔案。

- [x] **Step 1：改寫 `buildReaderScreen` 欄位對帳測試（Review Focus 1）**

`reader_screen_route_test.dart` 的「欄位對帳」改為：用 `readerFeatureDependenciesFromLegacy` 組裝，斷言 `screen.dependencies` 的 18 個欄位逐一 `same(...)`，另外 `filePath`／`bookId`／`bookTitle`／`bookAuthor`／`bookProgress`／`isFixedLayout`／`isEinkMode`／`initialJumpTarget` 來自 `book`／參數。`syncCheckpointTrigger` 的來源是 `sync`，`libraryRepository`／`prefsManager` 來自參數。範例（取代原 `expect(screen.xxx, same(...))` 一整段）：

```dart
      final dependencies = readerFeatureDependenciesFromLegacy(
        prefsManager: prefsManager,
        features: features,
        sync: sync,
        libraryRepository: libraryRepository,
      );
      final screen = buildReaderScreen(
        book: book,
        dependencies: dependencies,
        isEinkMode: true,
      );

      expect(screen.dependencies, same(dependencies));
      expect(dependencies.prefsManager, same(prefsManager));
      expect(dependencies.libraryRepository, same(libraryRepository));
      expect(dependencies.bookmarksRepository, same(bookmarksRepository));
      // …其餘 15 個欄位同樣逐一 same(...)，包含 syncCheckpointTrigger 來自 sync
      expect(dependencies.isFullTextSearchAvailable, false);
      expect(screen.isEinkMode, true);
      expect(screen.initialJumpTarget, isNull);
```

其中該測試原本的 `layoutPresetRepository` 用真實 in-memory sqflite，可改用 `FakeLayoutPresetRepository()`（`dbRepository` 若因此不再被任何測試使用，連同 `setUp`／`tearDown` 與 sqflite 匯入刪除）。

- [x] **Step 2：新增轉換函式的 `StateError` 測試（Review Focus 3）**

在同檔新增 group `readerFeatureDependenciesFromLegacy`，對 15 個舊 bundle nullable 欄位（`features` 14 個＋`sync.syncCheckpointTrigger` 1 個；`prefsManager`／`libraryRepository`／`isFullTextSearchAvailable` 不是 nullable，不在內）各測一次「該欄位為 null 時丟 `StateError`，訊息含欄位名」。用迴圈減少重複，每個案例以 `completeLegacyReaderFeatures()` 為底，再以 `LibraryReaderFeatureRepositories(...)` 逐欄置 null 的方式建構（因為欄位是 `final`，需列出完整建構；以下為其中一個案例的完整形態，其餘比照改變單一欄位為 null）：

```dart
    test('bookmarksRepository 為 null 時丟 StateError，訊息含欄位名', () {
      final full = completeLegacyReaderFeatures();
      final features = LibraryReaderFeatureRepositories(
        bookmarksRepository: null,
        highlightsRepository: full.highlightsRepository,
        notesRepository: full.notesRepository,
        customFontsRepository: full.customFontsRepository,
        downloadableFontStore: full.downloadableFontStore,
        layoutPresetRepository: full.layoutPresetRepository,
        bookReaderPrefsRepository: full.bookReaderPrefsRepository,
        ttsProvider: full.ttsProvider,
        ttsAudio: full.ttsAudio,
        ttsAudioFocusSource: full.ttsAudioFocusSource,
        readerActivityTracker: full.readerActivityTracker,
        searchRepository: full.searchRepository,
        bookImportService: full.bookImportService,
        readingStatsRepository: full.readingStatsRepository,
      );

      expect(
        () => readerFeatureDependenciesFromLegacy(
          prefsManager: FakeReaderPrefsManager(),
          features: features,
          sync: completeLegacySyncDependencies(),
          libraryRepository: FakeLibraryRepository(),
        ),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('bookmarksRepository'))),
      );
    });
```

並另有一個 `sync.syncCheckpointTrigger` 為 `const LibrarySyncDependencies()` 的案例。

同檔原有 **6 個** bundle 轉傳測試（`reader_screen_route_test.dart:150-239`：`bookImportService`、`readingStatsRepository`、`ttsAudio` 各「帶／未帶」一對）**全部刪除**——「未帶」狀態已不可達，「帶」已由欄位對帳涵蓋；若只刪 2 個，其餘 4 個直接存取 `screen.readingStatsRepository`／`screen.ttsAudio` 會編譯失敗。另外第 241、257 行的 2 個 `initialJumpTarget` 測試仍有效，改為以 `dependencies: fakeReaderFeatureDependencies()` 呼叫新簽名的 `buildReaderScreen`。

- [x] **Step 3：`BookSearchScreen` 測試與 Review Focus 2、5**

`book_search_screen_test.dart` 的 3 處 `LibraryReaderFeatureRepositories` 建構（約 298、399、597 行）及 `BookSearchScreen(` 建構點，改為 `dependencies: fakeReaderFeatureDependencies(searchRepository: ..., isFullTextSearchAvailable: ..., ...)`。新增兩個測試：

- 「點選片段（`fromReader: false`）推入的 `ReaderScreen.dependencies` 與 `BookSearchScreen.dependencies` 是同一實例」：以 `tester.widget<ReaderScreen>(find.byType(ReaderScreen)).dependencies` 對 `same(deps)`。
- 「`isFullTextSearchAvailable: false` 時顯示降級提示」：沿用既有降級提示測試，把來源改為 `fakeReaderFeatureDependencies(isFullTextSearchAvailable: false)`。

`reader_screen_stats_test.dart` 同步處理：第 32 行改斷言 `pushed.dependencies.readingStatsRepository`（`same(...)` 原值）；第 38-55 行「閱讀器沒有 `readingStatsRepository` 時，單書搜尋 bundle 的欄位為 null」是缺席測試，**刪除**並記入 `epic.md`。`reader_screen_stats_harness.dart` 的 `pumpStatsReader` 以變數轉傳 nullable 參數（`readingStatsRepository`、`searchRepository`、`libraryRepository`），codemod 後變成 `fakeReaderFeatureDependencies(readingStatsRepository: readingStatsRepository, ...)`：傳 null 即採用預設 fake，語意與工廠一致，不需另改；`stats_lifecycle_test`／`stats_activity_test` 經由 harness，預期只需處理缺席測試與計時器副作用（Task 5 規則 B）。

閱讀器→單書搜尋方向（Review Focus 2 另一半）在 `reader_screen_test.dart` 既有「點搜尋按鈕開啟 `BookSearchScreen`」測試補斷言：

```dart
      final searchScreen = tester.widget<BookSearchScreen>(find.byType(BookSearchScreen));
      expect(searchScreen.dependencies, same(deps));
      expect(searchScreen.fromReader, isTrue);
```

（`deps` 為該測試傳給 `ReaderScreen` 的 `fakeReaderFeatureDependencies(...)` 實例；若該測試目前是用 codemod 內嵌建構，先把它抽成區域變數 `final deps = fakeReaderFeatureDependencies(...)` 再傳入。）

- [x] **Step 4：`LibraryScreen`／`LibrarySearchScreen` 測試**

先跑看有哪些失敗（預期是「點選書籍進入閱讀器」且使用空 bundle 的案例丟 `StateError`）：

```bash
flutter test test/screens/library_screen_test.dart test/screens/library_search_screen_test.dart 2>&1 | tail -40
```

對每個失敗案例：把該測試傳給 `LibraryScreen`／`LibrarySearchScreen` 的 `readerFeatureRepositories` 改為 `completeLegacyReaderFeatures()`、`syncDependencies` 改為 `completeLegacySyncDependencies()`（需要驗證特定欄位時，直接用具名參數覆寫，例如 `completeLegacyReaderFeatures(highlightsRepository: highlightsRepository, notesRepository: notesRepository)`，不要手寫整個 `LibraryReaderFeatureRepositories(...)`）。**只改失敗的案例，不改沒有失敗的**。同時，這兩個檔案中讀取 `tester.widget<ReaderScreen>(...).xxxRepository` 的斷言，改為 `.dependencies.xxxRepository`。記錄修改的案例數量，寫進 `epic.md`。

- [x] **Step 5：用 analyzer 收尾其餘檔案**

```bash
flutter analyze test 2>&1 | tail -50
```

逐檔處理剩餘錯誤（`bookmark_test.dart`、`pdf_reader_view*_test.dart`、`tts_audio_focus_coordinator_test.dart`、`locale_switch_test.dart`、`pdf_settings_sheet_test.dart` 若有提到 `ReaderScreen(` 的建構或欄位）。直到 `flutter analyze` 乾淨。

---

### Task 5：測試遷移（C）——行為失敗歸類、刪除「缺席」測試、提交

`fakeReaderFeatureDependencies()` 的預設值讓許多原本不存在的功能（書籤、劃線、TTS、統計、同步觸發）現在都在，既有測試可能因此失敗。**依下列規則逐一歸類，不要為了通過而放寬斷言。**

- [x] **Step 1：先跑 `reader_screen_test.dart`，取得失敗清單**

```bash
flutter test test/screens/reader_screen_test.dart 2>&1 | grep -E "^\s*\[E\]|\+[0-9]+ -[0-9]+|Some tests failed|All tests passed" | tail -60
```

- [x] **Step 2：對每個失敗案例歸類並處理**

| 類別 | 判斷 | 處理 |
|---|---|---|
| A. 缺席測試 | 測試名含「未提供…」「…為 null 時…」且斷言該功能停用／隱藏／提示 | **刪除**，並把測試名稱記入 `epic.md`（已知約 20 個，grep 起點：`未提供 bookmarksRepository`、`未提供 highlightsRepository／notesRepository`、`FXL：未提供 bookmarksRepository`、`未提供 syncCheckpointTrigger`、`layoutPresetRepository 為 null`、`未提供 ttsProvider`（含四個 TTS 變體）、`未提供 ttsAudioHandler／ttsAudioFocusSource`、`searchRepository 為 null`、`libraryRepository 為 null`、`isFixedLayout: null 且未提供 libraryRepository`）。**例外**：CBZ 的 TTS 停用狀態按鈕測試（Review Focus 6）、`isFixedLayout: null` 但有 `libraryRepository` 的偵測測試不是缺席測試，不刪 |
| B. 預設 fake 帶來新 UI／新計時器 | 該測試原本沒提供某依賴，現在多出的 widget／計時器干擾斷言（例如 `findsOneWidget` 變 `findsNWidgets`、`Timer still pending`） | 只在**該測試**的 `fakeReaderFeatureDependencies(...)` 覆寫對應欄位為「靜默」fake（例如 `ttsAudio: TtsAudioHandlerHolder.unavailable()` 已是預設；統計計時器問題則傳 `readingStatsTracker` 測試注入點或在測試結尾 `await tester.pump(...)` 結算）。**不得修改工廠預設值去遷就個別測試**；若同一原因在 ≥5 個測試出現，停下來回報，再決定是否調整工廠預設 |
| C. 真正的行為回歸 | 測試斷言的是仍然有效的行為，卻失敗 | 這是本重構的缺陷，回到 Task 2 修 lib，不改測試 |

- [x] **Step 3：跑所有異動範圍的測試**

```bash
flutter test test/screens/reader_screen_test.dart test/screens/reader_screen_route_test.dart test/screens/book_search_screen_test.dart test/screens/library_screen_test.dart test/screens/library_search_screen_test.dart test/screens/reader_screen_tts_degraded_notice_test.dart test/screens/reader_screen_tts_late_handler_test.dart test/screens/reader_screen_stats_test.dart test/screens/reader_screen_stats_lifecycle_test.dart test/screens/reader_screen_stats_activity_test.dart test/support/fake_reader_feature_dependencies_test.dart 2>&1 | tail -5
```

預期：全過。通過數 = Task 0 基準 N − 被刪缺席測試數 − 刪除的 6 個 bundle 測試（`reader_screen_route_test.dart`） − 刪除的統計缺席測試（`reader_screen_stats_test.dart`）＋ 新增測試數（工廠 5 個、StateError 15 個、身分比對等）；把這個算式與實際數字寫進 `epic.md`。

- [x] **Step 4：分析與 l10n 檢查**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

預期：`No issues found!`、兩行 PASS。

- [x] **Step 5：提交（lib＋測試一次切換）**

```bash
git add app/lib app/test
git status --short   # 確認 .scratch/ 沒有被加入
git commit -m "refactor(epic-54): ReaderScreen／BookSearchScreen 改收 ReaderFeatureDependencies（Issue 11）

ReaderScreen 建構子 29→12 個參數（含 super.key），消除開單書搜尋時手動逐欄重建 bundle；
舊 bundle 暫由 readerFeatureDependenciesFromLegacy 轉換；
測試改用預設全 fake 工廠，刪除依賴缺席的不可達測試。

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6：文件、完整測試、收尾

**Files：** Modify：`docs/adr/0037-…md`、`docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md`

- [ ] **Step 1：修訂 ADR 0037 兩處措辭**

- §3：把「真正可能缺席的能力（TTS 引擎、全文檢索、WiFi 傳書）以明確的「不可用」adapter 或旗標表示」改為：全文檢索以 `isFullTextSearchAvailable` 旗標表示；WiFi 傳書於 Issue 13 處理；**TTS 不新增不可用 adapter**——正式環境恆提供 `SystemTtsProvider`，音訊服務不可用以 `TtsAudioHandlerHolder.unavailable()`／`.degraded()` 表示。
- §6：把「只能在 `buildReaderScreen` 這一個呼叫點暫時組裝」改為「只能透過 `reader_screen_route.dart` 的單一轉換函式 `readerFeatureDependenciesFromLegacy` 暫時組裝，由尚未遷移的外層畫面呼叫，於最後一個外層畫面遷移完成時移除」。

- [ ] **Step 2：更新 `epic.md`、`issues.md`、`docs/epics.md`**

`epic.md` 新增「Issue 11 實作完成」段落：分支名、Task 0 基準 N、最終通過數與算式、被刪缺席測試名稱清單、Task 4 需 `completeLegacyReaderFeatures()` 補齊的測試數、`readerSaveAsPresetUnavailableMessage` 孤兒鍵的記錄、Review Focus 逐條對應的測試名稱。`issues.md` Issue 11 狀態改為「🟡 實作完成，待程式審查」；`docs/epics.md` 備註「最後處理的 Issue」同步為「Issue 11 實作完成，待程式審查」。

- [ ] **Step 3：完整測試（只在此處跑一次）**

```bash
cd /c/Users/fycdc/AI/elinkBook/.worktrees/epic-54-issue-11-reader-deps/app
flutter test
```

用 `run_in_background` 執行，約 6 分鐘。預期：0 失敗。

- [ ] **Step 4：提交文件**

```bash
git add docs
git commit -m "docs(epic-54): Issue 11 實作記錄與 ADR 0037 措辭修訂

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5：交給程式審查**

審查者先產出報告，存於 `docs/epics/epic-54-architecture-optimization/reviews/review-code-issue-11.md`（gitignore），不得直接改程式；審查完成後由人類決定發 PR 與合併。

---

## Self-Review

**Spec 對照（ADR 0037／Issue 11／審查）：** `ReaderFeatureDependencies` 含 18 欄位且 non-null（Task 1）；`syncCheckpointTrigger` 納入（Task 1、2）；`readingStatsTracker`／`pickSingleBookFile` 留作測試注入點（Task 2）；消除手動重建（Task 2 Step 3 表 1901-1926）；工廠先行並有自身測試（Task 1）；`buildReaderScreen` 過渡轉換（Task 2 Step 1）；TTS 不可用表示（以「前提 2」明確選擇）；`LibrarySearchScreen`／`LibraryScreen` 簽名不動。

**佔位符掃描：** Task 2 Step 3 為行號對照表（行為規則，非程式碼佔位）；Task 4 Step 2 的 15 個欄位案例只列出一個完整範例，其餘「比照改變單一欄位」是刻意用迴圈／同形寫法，執行者可用 `for` 迴圈搭配 `completeLegacyReaderFeatures()` 逐欄建構——若實作時發現手寫 15 份過於冗長，改以輔助函式 `legacyWithNull(String field)` 集中，不屬於佔位。

**型別一致：** `ReaderFeatureDependencies` 欄位名在 Task 1／2／4 一致（`bookmarksRepository`…`ttsAudioFocusSource`）；`readerFeatureDependenciesFromLegacy` 參數名在 Task 2 Step 1／5 與 Task 4 一致（`prefsManager`／`features`／`sync`／`libraryRepository`）；`buildReaderScreen` 在 Task 2 Step 1／4／5 與 Task 4 一致（`book`／`dependencies`／`isEinkMode`／`initialJumpTarget`）；`completeLegacyReaderFeatures`／`completeLegacySyncDependencies` 在 Task 1 定義、Task 4 使用。

**Review Focus：** 6 條皆有對應任務（1→Task 4 Step 1；2→Task 4 Step 3；3→Task 4 Step 2；4→Task 5 Step 2；5→Task 4 Step 3；6→Task 5 Step 2 例外條款）。

**已知風險：** 約 20 個缺席測試被刪（前提 1）；預設全 fake 可能讓 `reader_screen_test.dart`（12,588 行）出現成批副作用失敗（Task 5 規則 B 的「≥5 個同因就停下回報」是煞車）；`library_screen_test.dart` 受影響案例數量要到 Task 4 才知道（前提 3）；`reader_screen.dart` 內 null 分支移除量大，須靠 analyzer 的 `unnecessary_null_comparison` 逐一收斂。
