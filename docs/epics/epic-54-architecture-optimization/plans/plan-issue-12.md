# Issue 12：`SyncDependencies`——`LibraryScreen`／`LibrarySearchScreen`／`SettingsScaffold`／`AdaptiveShellScaffold` 改收依賴組 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:executing-plans` 逐 Task 執行本計畫（**使用者明確要求嚴禁 subagent**，不要用 `subagent-driven-development`）。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 把書架（`LibraryScreen`）、全庫搜尋（`LibrarySearchScreen`）、設定（`SettingsScaffold`）與外殼（`AdaptiveShellScaffold`）的依賴改為「收單一依賴組物件」（`ReaderFeatureDependencies`＋新增的 `SyncDependencies`），讓 `LibrarySearchScreen` 的 `searchRepository` 只剩一個來源，並移除 Issue 11 留下的過渡層（`readerFeatureDependenciesFromLegacy`、`grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories`、`LibrarySyncDependencies`）。

**Architecture：** 依 ADR 0037 §2／§3／§6：畫面以建構子接收所需的組、組內依賴 non-null required、逐畫面一刀切、不留新舊並存。實作順序**由葉到根**（`LibrarySearchScreen` → `SettingsScaffold` → `LibraryScreen`／`AdaptiveShellScaffold`／`ElinkBookApp`／`main.dart`），每個 Task 結束時 `flutter analyze` 乾淨、範圍測試全過、可獨立 commit；尚未遷移的外層畫面暫時用既有的 `readerFeatureDependenciesFromLegacy`（以及 Task 3 暫時新增、Task 4 刪除的 `grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories`）組裝新組。Issue 13 才處理 `SourceDependencies`／`AppearanceDependencies`／`AppDependencies`，本 Issue **不碰**雲端／遠端／主題／語言這四個既有 bundle。

**Tech Stack：** Flutter／Dart、`flutter_test`、`integration_test`、Node（既有守衛腳本與一次性 codemod）。指令一律在 `app/` 目錄下執行（除非另有標明），以 **Bash 工具（Git Bash）** 為準。

**Spec：** `docs/adr/0037-dependencies-grouped-by-consumer-passed-as-one-object.md`；`docs/epics/epic-54-architecture-optimization/issues.md` 第 12 列；`reviews/review-issues-11-14.md`；Issue 11 的做法見 `plans/plan-issue-11.md` 與 `epic.md`「Issue 11 實作完成」「Issue 11 程式審查」兩段（尤其 M-1：`searchRepository` 雙來源）。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **一刀切**：同一個畫面的建構子不得新舊參數並存（ADR 0037 §6）。過渡用的轉換函式只能由「尚未遷移的外層畫面」呼叫，且必須在本 Issue 內全部刪除（Issue 13 前不得殘留 `readerFeatureDependenciesFromLegacy`）。
- **non-null required**：兩個依賴組內的 repository／service／函式型依賴一律 non-null（ADR 0037 §3）；不得為了讓測試省事而把欄位改回 nullable。
- **不碰 Issue 13 的範圍**：`LibraryCloudAccountDependencies`、`LibraryRemoteLibraryDependencies`、`LibraryThemeDependencies`、`LibraryLocaleDependencies`、`computeFingerprint`、`isMobileDataConnection`、`downloadQueueController`、`wifiTransferDependencies`、`thumbnailCache` 等維持現狀。
- **不放寬測試**：刪除測試只允許一種理由——「該測試驗證的是『可選依賴缺席』，而依賴現在是 non-null required，型別上不可達」（Issue 11 先例）。每一個被刪的測試必須列入附錄 B（名稱＋理由）；仍可達的行為（例如 `isFullTextSearchAvailable: false` 的降級提示、空書架、錯誤狀態）一律保留。**不得**為了通過而改弱斷言、加 `skip`、把 `same(...)` 改成 `isNotNull`。
- **同一實例**：`syncCheckpointTrigger` 同時屬於閱讀器組與同步組，`main.dart` 必須建構一次、把同一實例放進兩組（ADR 0037 §1）。
- **不改 `lib/` 以外的行為**：本 Issue 是結構重構，不得順手改畫面文案、版面、Key、ARB。唯一的行為差異是「原本因依賴為 null 而停用的入口，在 non-null 下恆啟用」，這些差異必須逐項列入附錄 B。
- **測試範圍**（`CLAUDE.md`）：單一 Task 只跑異動觸及的測試；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，在 `app/` 下）。
- **提交前**：`flutter analyze` 必須 "No issues found!"；改了畫面字串或測試後跑 `node tool/check_l10n_hardcoded_strings.js`；改了 `integration_test/` 後跑 `node tool/check_integration_keys.js`。
- **Windows 環境**：多數原始檔是 CRLF，`Edit` 的定位字串不要含換行。提交一律明確路徑 `git add`。Commit 結尾須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：本計畫先審查再動手；程式審查先出報告（存 `reviews/`），審查者不直接改程式。實作在 worktree `.worktrees/epic-54-issue-12`（分支 `epic-54/issue-12-sync-deps`）內進行，PR 合併後的進度同步才在 `main` 直接 commit＋push。

## 已查證的事實（撰寫計畫時對照 `lib/` 所得，執行者開工前須再確認一次）

| 項目 | 事實 | 出處 |
|---|---|---|
| 現況：兩個舊 bundle | `grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories`（16 欄位，全 nullable）與 `LibrarySyncDependencies`（5 欄位，全 nullable）定義在 `library_screen_dependencies.dart`；同檔另有 4 個 bundle（Cloud／Remote／Theme／Locale）**本 Issue 保留** | `lib/screens/library_screen_dependencies.dart` |
| 使用者範圍 | 舊兩個 bundle 只被 `AdaptiveShellScaffold`、`LibraryScreen`、`LibrarySearchScreen`、`main.dart` 使用（`SettingsScaffold` 收的是展開後的個別欄位） | `grep -rn "readerFeatureRepositories\|syncDependencies" lib` |
| **`LibraryScreen` 其實不需要同步組** | `LibraryScreen` 的 `syncDependencies` 只用在兩處：組裝 `ReaderScreen` 依賴（取 `syncCheckpointTrigger`）、轉傳給 `LibrarySearchScreen`。新閱讀器組已含 `syncCheckpointTrigger`，所以 `LibraryScreen`／`LibrarySearchScreen` **只收 `ReaderFeatureDependencies`**；真正需要 `SyncDependencies` 的是 `SettingsScaffold`（同步設定入口）與其上層 `AdaptiveShellScaffold`、`ElinkBookApp`（`paused` 時觸發 checkpoint）。`issues.md` 第 12 列標題把四個畫面並列為「改收依賴組」，指的是「依賴組」整體，不是四個都收同步組 | `library_screen.dart:474-477,881-882`、`library_search_screen.dart:180-183,410-413`、`main.dart:507` |
| **重複來源** | `ReaderFeatureDependencies` 已含 `prefsManager`、`libraryRepository`、`bookImportService`；`LibraryScreen`／`AdaptiveShellScaffold` 目前另外各收 `repository`／`importService`／`prefsManager`，`LibrarySearchScreen` 另收 `libraryRepository`／`prefsManager`／`searchRepository`。遷移後必須各只剩一個來源（比照 Issue 11 M-1） | `library_screen.dart:60-62`、`library_search_screen.dart:27-33`、`adaptive_shell_scaffold.dart:34-36`、`reader_feature_dependencies.dart` |
| **組尚缺一個欄位** | `fullTextSearchSettingsRepository`（「啟用全文檢索」設定）不在 `ReaderFeatureDependencies` 的 18 欄位內，但 `LibraryScreen`（`LibraryBatchActions`、重新下載後 `handleBookAvailable`）、`LibrarySearchScreen`、`SettingsScaffold`（開關與重建索引）都要用，且 `main.dart` 恆提供。ADR 0037 §1 沒有列出它的歸屬 → **Task 0 取得使用者決定**；本計畫建議併入 `ReaderFeatureDependencies`（與同組已有的 `isFullTextSearchAvailable`、`searchRepository` 同屬搜尋功能） | `library_screen.dart:171-176,616`、`settings_scaffold.dart:126,378-420` |
| 欄位 null 判斷（遷移後變成恆真，須處理） | (1) `LibraryScreen._openBookActionSheet`：`showLayoutOverride: bookReaderPrefsRepository != null`（`library_screen.dart:684`）；(2) `_openLibrarySearchScreen` 的 `searchRepository == null` 提前返回、`_buildContentSearchEntryButton` 的 `onPressed: hasSearchRepository ? … : null`（`library_screen.dart:871-900`）；(3) `fullTextSearchSettingsRepository?.handleBookAvailable`（`:616`）；(4) `SettingsScaffold` 的字型管理入口（`customFontsRepository == null`，`:272`）、閱讀統計入口（`readingStatsRepository != null`，`:337`）、全文檢索兩個開關（`fullTextSearchSettingsRepository == null`，`:378-420`）、同步入口四欄位 null 判斷（`:437-440`）與 `!` 解參考（`:446-449`） | 同左 |
| `main.dart` 全部恆提供 | `main()` 建好所有 repository／同步物件後才 `runApp`；`ElinkBookApp` 的欄位型別是 nullable 純為舊測試省略參數而設 | `main.dart:241-341`、`:388-447` |
| `ElinkBookApp` 目前持有 | 逐欄位 39 個（含 `repository`／`importService`／`prefsManager` 與 reader／sync 欄位），在 `build()` 內重新組裝兩個舊 bundle。`didChangeAppLifecycleState` 以 `widget.syncCheckpointTrigger?.trigger()` 在 `paused` 觸發同步 | `main.dart:386-520,543-575` |
| 呼叫端數量（測試） | `LibraryScreen(` 133（`library_screen_test.dart`）＋integration 4；`LibrarySearchScreen(` 29；`SettingsScaffold(` 45＋其他 7；`AdaptiveShellScaffold(` 12；`ElinkBookApp(` 16；`completeLegacyReaderFeatures` 33；`syncDependencies:` 26；`readerFeatureRepositories:` 51 | `grep -rc` |
| Issue 11 留下的過渡物 | `readerFeatureDependenciesFromLegacy`（`reader_screen_route.dart`，含 `searchRepository` 覆寫參數）、`completeLegacyReaderFeatures`／`completeLegacySyncDependencies`（`test/support/fake_reader_feature_dependencies.dart`）、`reader_screen_route_test.dart` 內針對轉換函式的測試 | 同左 |
| 同步組欄位來源 | `SyncSettingsScreen` 需要 `accountRepository`／`syncClient`／`onManualSync`／`loadLastSyncedAt` 四項，皆 non-null required；測試用真實 `SyncAccountRepository()`＋`SyncClient(accountRepository:)`（建構子不做 I/O） | `sync_settings_screen.dart:15-30`、`settings_scaffold_test.dart:197-198` |

## Review Focus

最可能咬到使用者的情況，依可能性排序：

1. **同步組與閱讀器組的 `syncCheckpointTrigger` 不是同一實例。**使用者在閱讀器裡離開書本會觸發 checkpoint、App 進背景（`paused`）也要觸發；若兩處各建一份，兩邊的去重／節流狀態分家，同步時機會悄悄錯亂。→ Task 3 在 `main.dart` 只建構一次並同時放進兩組；`elinkbook_app_wiring_test` 新增 `same(...)` 斷言（App 層的 `sync.syncCheckpointTrigger` 與 `readerFeatures.syncCheckpointTrigger` 為同一實例）。
2. **主題／語言切換使 `ElinkBookApp` 重建時，依賴組被重新建構成新實例。**舊做法在 `build()` 內 new bundle，`LibraryScreen.didUpdateWidget` 因此每次都重建 `LibraryBatchActions`；新做法組必須由 `main()` 建一次、`ElinkBookApp` 持有並原樣往下傳。→ Task 3 wiring 測試：切換主題後 `LibraryScreen.dependencies` 仍 `same` 於原組。
3. **兩個來源分歧（`searchRepository`、`libraryRepository`、`prefsManager`、`importService`）。**遷移後使用者從書架進搜尋再進閱讀器，看到的必須是同一份。→ Task 2／3 以 `same(...)` 驗證 `LibrarySearchScreen.dependencies`、`ReaderScreen.dependencies` 與外層傳入的組是同一實例。
4. **原本因 null 而停用的入口，現在恆啟用。**對使用者而言正式環境本來就恆啟用，不是回歸；但若不逐項列出，後人無法分辨「刪掉的測試」是合理還是掩蓋。→ 附錄 B 逐項記錄（搜尋入口按鈕、版面覆寫列、全文檢索開關、同步入口、字型管理入口、閱讀統計入口）。
5. **設定頁同步入口點下去，`SyncSettingsScreen` 拿到的不是組內同一批物件。**→ Task 3 新測試（SettingsScaffold）：點 `settings_sync_button` 後 `SyncSettingsScreen` 的 `accountRepository`／`syncClient`／`onManualSync`／`loadLastSyncedAt` 與傳入的 `SyncDependencies` 同一實例。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/screens/sync_dependencies.dart` | 新增 | `SyncDependencies`（5 欄位，non-null required） |
| `app/lib/screens/reader_feature_dependencies.dart` | 修改 | 新增 `fullTextSearchSettingsRepository`（19 欄位；以 Task 0 決定為準） |
| `app/lib/screens/library_search_screen.dart` | 修改 | 改收 `ReaderFeatureDependencies`（取代 5 個舊參數） |
| `app/lib/screens/settings_scaffold.dart` | 修改 | 改收 `readerFeatures`＋`sync`（取代 11 個欄位），移除 null 判斷與 `!` |
| `app/lib/screens/library_screen.dart` | 修改 | 改收 `dependencies`（取代 `repository`／`importService`／`prefsManager`／兩個舊 bundle） |
| `app/lib/screens/adaptive_shell_scaffold.dart` | 修改 | 改收 `readerFeatures`＋`sync`，往下傳整組 |
| `app/lib/main.dart` | 修改 | `main()` 建構兩個組；`ElinkBookApp` 改收 `readerFeatures`／`sync`（取代 reader／sync 相關欄位） |
| `app/lib/screens/reader_screen_route.dart` | 修改 | 刪除 `readerFeatureDependenciesFromLegacy`（`buildReaderScreen` 保留） |
| `app/lib/screens/library_screen_dependencies.dart` | 修改 | 刪除 `grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories`、`LibrarySyncDependencies`（其餘 4 個 bundle 保留） |
| `app/test/support/fake_sync_dependencies.dart`（＋`_test.dart`） | 新增 | 預設全 fake 的同步組工廠 |
| `app/test/support/fake_reader_feature_dependencies.dart`（＋`_test.dart`） | 修改 | 新增 `fullTextSearchSettingsRepository` 參數；刪除 `completeLegacy*` |
| `app/test/screens/{library_screen,library_search_screen,settings_scaffold,settings_scaffold_reading_stats,adaptive_shell_scaffold,library_screen_dependencies,reader_screen_route}_test.dart` | 修改 | 依新建構子遷移 |
| `app/test/{elinkbook_app_wiring,app_lifecycle_sync,navigation}_test.dart`、`app/test/l10n/{locale_switch,elinkbook_app_locale}_test.dart`、`app/test/theme/theme_test.dart` | 修改 | 同上 |
| `app/integration_test/{library_screen,smoke}_test.dart` | 修改 | 同上（只能本機靜態驗證，真機見 Task 4） |
| `docs/adr/0037-…md`、`docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 措辭同步與進度 |

---

### Task 0：建立基準、worktree 與取得設計決定

**Files:** 無程式修改。

- [x] **Step 1: 確認前提（開工前再對照一次）**

```bash
cd /c/Users/fycdc/AI/elinkBook
git status --short
git log --oneline -1
cd app
grep -rn "readerFeatureRepositories\|syncDependencies" lib --include=*.dart | grep -v "library_screen_dependencies.dart" | wc -l
grep -n "fullTextSearchSettingsRepository" lib/screens/reader_feature_dependencies.dart | wc -l
grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories" lib --include=*.dart | cut -d: -f1 | sort | uniq -c
```

Expected：工作樹乾淨；第二行輸出 `0`（組尚無該欄位）；`readerFeatureDependenciesFromLegacy` 出現在 `reader_screen_route.dart`、`library_screen.dart`、`library_search_screen.dart`。任何一項不符，先停下回報。

- [x] **Step 2: 向使用者呈報三個設計決定並等待回答（回答前不得改 `lib/`、不得改測試）**

```
Q1  fullTextSearchSettingsRepository 要放哪一組？ADR 0037 沒列歸屬。
    A) 併入 ReaderFeatureDependencies（19 欄位）【建議】：LibraryScreen／LibrarySearchScreen／
       SettingsScaffold 都收這一組，且同組已有 isFullTextSearchAvailable、searchRepository；
       代價是 ReaderScreen／BookSearchScreen 拿到用不到的欄位（ADR 已接受「組比單欄寬鬆」）。
    B) 另開一個「設定相關」組：多一個類別與工廠，目前只有這一個欄位，屬於過度設計（YAGNI）。
Q2  LibraryScreen／AdaptiveShellScaffold 移除自己的 repository／importService／prefsManager
    參數，一律取自 ReaderFeatureDependencies（單一來源）？
    A) 是【建議】：與 Issue 11 M-1 處理 searchRepository 的做法一致，否則同一個物件有兩個來源。
    B) 否，保留並新增「必須與組內同一實例」的約定：違反 ADR 一刀切、也擋不住分歧。
Q3  ElinkBookApp（中間層）要不要在本 Issue 就改收兩個組？
    A) 是【建議】：main() 建一次組、App 原樣往下傳，才能讓「主題／語言切換重建 App 時組不會變成新實例」；
       代價是 ElinkBookApp 的 16 個測試呼叫要改（用工廠，成本低）。Issue 13 再把它收進 AppDependencies。
    B) 否，ElinkBookApp 先維持逐欄位，在 State.initState 內組裝一次：App 欄位仍是 nullable，
       無法 non-null 組裝，等於把 Issue 13 的工作拆成兩半。
```

把使用者原話逐字記入本計畫「附錄 A」（Step 4 才補），不得改寫。

- [x] **Step 3: 建立 worktree 與分支**

```bash
cd /c/Users/fycdc/AI/elinkBook
git worktree add .worktrees/epic-54-issue-12 -b epic-54/issue-12-sync-deps main
cd .worktrees/epic-54-issue-12/app
flutter pub get
```

- [x] **Step 4: 記錄基準並補附錄 A**

```bash
flutter test test/screens/library_screen_test.dart test/screens/library_search_screen_test.dart \
  test/screens/settings_scaffold_test.dart test/screens/settings_scaffold_reading_stats_test.dart \
  test/screens/adaptive_shell_scaffold_test.dart test/screens/library_screen_dependencies_test.dart \
  test/screens/reader_screen_route_test.dart test/elinkbook_app_wiring_test.dart \
  test/app_lifecycle_sync_test.dart test/navigation_test.dart test/l10n/locale_switch_test.dart \
  test/l10n/elinkbook_app_locale_test.dart test/theme/theme_test.dart \
  test/support/fake_reader_feature_dependencies_test.dart 2>&1 | tail -3
flutter analyze 2>&1 | tail -2
```

把「通過數」記入附錄 C（後續各 Task 的測試數算式以它為基準，比照 Issue 11 的算式寫法）。`flutter analyze` 須為 "No issues found!"。

---

### Task 1：`SyncDependencies`、組新增欄位與測試工廠

**Files:**
- Create: `app/lib/screens/sync_dependencies.dart`
- Create: `app/test/support/fake_sync_dependencies.dart`、`app/test/support/fake_sync_dependencies_test.dart`
- Modify: `app/lib/screens/reader_feature_dependencies.dart`
- Modify: `app/test/support/fake_reader_feature_dependencies.dart`、`app/test/support/fake_reader_feature_dependencies_test.dart`
- Modify: `app/lib/screens/reader_screen_route.dart`（轉換函式補新欄位，過渡用）
- Modify: `app/test/screens/reader_screen_route_test.dart`（對帳測試改 19 欄位）

**Interfaces:**
- Produces（後續所有 Task 使用，名稱與型別不得更動）：

```dart
class SyncDependencies {
  final SyncAccountRepository syncAccountRepository;
  final SyncClient syncClient;
  final SyncCheckpointTrigger syncCheckpointTrigger;
  final Future<SyncCheckpointResult> Function() onManualSync;
  final Future<int?> Function() loadLastSyncedAt;
  const SyncDependencies({required …五個欄位});
}
// ReaderFeatureDependencies 新增（Q1 選 A 時）：
//   final FullTextSearchSettingsRepository fullTextSearchSettingsRepository;
SyncDependencies fakeSyncDependencies({
  SyncAccountRepository? syncAccountRepository,
  SyncClient? syncClient,
  SyncCheckpointTrigger? syncCheckpointTrigger,
  Future<SyncCheckpointResult> Function()? onManualSync,
  Future<int?> Function()? loadLastSyncedAt,
});
// fakeReaderFeatureDependencies 新增具名參數 FullTextSearchSettingsRepository? fullTextSearchSettingsRepository
```

> 以下以 Q1＝A（併入）撰寫；若使用者選 B，本 Task 的第二組新增欄位改放新類別，其餘不變。

- [x] **Step 1: 寫失敗測試**

`test/support/fake_sync_dependencies_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';

import 'fake_sync_dependencies.dart';

void main() {
  test('fakeSyncDependencies 預設全部有值（non-null），且每次呼叫是新實例', () async {
    final a = fakeSyncDependencies();
    final b = fakeSyncDependencies();
    expect(identical(a.syncCheckpointTrigger, b.syncCheckpointTrigger), isFalse);
    expect(identical(a.syncAccountRepository, b.syncAccountRepository), isFalse);
    expect(await a.onManualSync(), SyncCheckpointResult.notLoggedIn);
    expect(await a.loadLastSyncedAt(), isNull);
  });

  test('fakeSyncDependencies 具名覆寫原樣帶入（同一實例）', () {
    final trigger = fakeSyncDependencies().syncCheckpointTrigger;
    final deps = fakeSyncDependencies(syncCheckpointTrigger: trigger);
    expect(deps.syncCheckpointTrigger, same(trigger));
  });
}
```

在 `fake_reader_feature_dependencies_test.dart` 新增一案：`fakeReaderFeatureDependencies(fullTextSearchSettingsRepository: x)` 的結果欄位 `same(x)`，且預設不為 null。

- [x] **Step 2: 跑測試確認失敗**

Run：`flutter test test/support/fake_sync_dependencies_test.dart test/support/fake_reader_feature_dependencies_test.dart`
Expected：編譯失敗（`fake_sync_dependencies.dart` 不存在、`fullTextSearchSettingsRepository` 命名參數不存在）。

- [x] **Step 3: 實作**

`lib/screens/sync_dependencies.dart`：

```dart
import 'package:flutter/foundation.dart';

import '../sync/sync_account_repository.dart';
import '../sync/sync_checkpoint_result.dart';
import '../sync/sync_checkpoint_trigger.dart';
import '../sync/sync_client.dart';

/// 同步依賴組（ADR 0037）：`SettingsScaffold`（同步設定入口）與其上層
/// `AdaptiveShellScaffold`／`ElinkBookApp`（進背景時觸發 checkpoint）接收這一個
/// 物件，取代逐欄傳遞。
///
/// 全部 non-null、required：`main.dart` 啟動時全部都會建好。
/// `syncCheckpointTrigger` 同時也屬於閱讀器依賴組，**由 `main()` 建構一次、同一
/// 實例放進兩組**，不得各組自行建構（ADR 0037 §1）。
@immutable
class SyncDependencies {
  final SyncAccountRepository syncAccountRepository;
  final SyncClient syncClient;
  final SyncCheckpointTrigger syncCheckpointTrigger;

  /// 「立即同步」按鈕：刻意收窄成單一 callback 而非整個 `SyncEngine`，讓
  /// `SyncSettingsScreen` 的 widget test 可注入輕量假 closure，不需要真實 sqflite。
  final Future<SyncCheckpointResult> Function() onManualSync;
  final Future<int?> Function() loadLastSyncedAt;

  const SyncDependencies({
    required this.syncAccountRepository,
    required this.syncClient,
    required this.syncCheckpointTrigger,
    required this.onManualSync,
    required this.loadLastSyncedAt,
  });
}
```

`test/support/fake_sync_dependencies.dart`：

```dart
import 'package:elinkbook/screens/sync_dependencies.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:elinkbook/sync/sync_client.dart';

/// 預設全 fake 的同步依賴組（ADR 0037）。只覆寫情境需要的欄位；每次呼叫都建新實例。
/// `SyncAccountRepository()`／`SyncClient(...)` 建構時不做 I/O，可直接用於 widget test。
SyncDependencies fakeSyncDependencies({
  SyncAccountRepository? syncAccountRepository,
  SyncClient? syncClient,
  SyncCheckpointTrigger? syncCheckpointTrigger,
  Future<SyncCheckpointResult> Function()? onManualSync,
  Future<int?> Function()? loadLastSyncedAt,
}) {
  final account = syncAccountRepository ?? SyncAccountRepository();
  return SyncDependencies(
    syncAccountRepository: account,
    syncClient: syncClient ?? SyncClient(accountRepository: account),
    syncCheckpointTrigger: syncCheckpointTrigger ??
        SyncCheckpointTrigger(
          runCheckpoint: () async => SyncCheckpointResult.notLoggedIn,
        ),
    onManualSync: onManualSync ?? () async => SyncCheckpointResult.notLoggedIn,
    loadLastSyncedAt: loadLastSyncedAt ?? () async => null,
  );
}
```

`reader_feature_dependencies.dart`：新增 `import '../search/full_text_search_settings_repository.dart';`、欄位 `final FullTextSearchSettingsRepository fullTextSearchSettingsRepository;`（放在 `isFullTextSearchAvailable` 之後，文件註解寫「『啟用全文檢索』設定；書架重新下載後補索引、全庫搜尋與設定頁開關使用，閱讀器本身不用」）與 `required this.fullTextSearchSettingsRepository`。`fake_reader_feature_dependencies.dart` 新增對應具名參數，預設 `FakeFullTextSearchSettingsRepository()`（`test/support/fake_full_text_search_settings_repository.dart` 已存在）。

`reader_screen_route.dart` 的 `readerFeatureDependenciesFromLegacy` 新增一行
`fullTextSearchSettingsRepository: need(features.fullTextSearchSettingsRepository, 'fullTextSearchSettingsRepository'),`；`reader_screen_route_test.dart` 的「缺欄位丟 StateError」測試補這個欄位名的案例（沿用該檔既有的逐欄位寫法）。

**同步補齊舊相容工廠與對帳測試（計畫審查 I-2；否則 Task 1 自己的測試與所有走轉換函式的既有測試會立刻紅燈）：**

1. `test/support/fake_reader_feature_dependencies.dart` 的 `completeLegacyReaderFeatures()` 新增具名參數 `FullTextSearchSettingsRepository? fullTextSearchSettingsRepository`，傳入 `grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories` 時預設 `FakeFullTextSearchSettingsRepository()`（轉換函式現在對這個欄位 `need(...)`，沒補的話 `library_screen_test` 15 案、`library_search_screen_test` 8 案「點選書籍進入閱讀器」都會丟 `StateError`）。
2. `test/screens/reader_screen_route_test.dart` 的對帳測試「欄位對帳：dependencies 18 個欄位逐一同一實例，書本欄位來自 book」：手動建構的 `grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories` 補上 `fullTextSearchSettingsRepository`，測試名稱改為「19 個欄位」，新增 `expect(dependencies.fullTextSearchSettingsRepository, same(fullTextSearchSettingsRepository))`；「舊 bundle 完整時轉換成功」一案同樣沿用補齊後的 `completeLegacyReaderFeatures()`。
3. `test/support/fake_reader_feature_dependencies_test.dart` 補驗證：`completeLegacyReaderFeatures().fullTextSearchSettingsRepository` 不為 null，且覆寫時 `same(...)`。

- [x] **Step 4: 跑測試確認通過**

Run：`flutter test test/support test/screens/reader_screen_route_test.dart`
Expected：全過。再跑 `flutter analyze`：因為 `ReaderFeatureDependencies` 新增必填欄位，所有直接 `ReaderFeatureDependencies(` 建構處都會報錯——這是預期的編譯器提示，逐一補上（預期只有 `fake_reader_feature_dependencies.dart` 與 `readerFeatureDependenciesFromLegacy` 兩處；若出現其他處，先確認是否為 Issue 11 之後新增的呼叫端）。

- [x] **Step 5: Commit**

```bash
flutter analyze
git add lib/screens/sync_dependencies.dart lib/screens/reader_feature_dependencies.dart lib/screens/reader_screen_route.dart \
  test/support/fake_sync_dependencies.dart test/support/fake_sync_dependencies_test.dart \
  test/support/fake_reader_feature_dependencies.dart test/support/fake_reader_feature_dependencies_test.dart \
  test/screens/reader_screen_route_test.dart
git commit -m "feat(epic-54): Issue 12 新增 SyncDependencies 與閱讀器組的全文檢索設定欄位" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：`LibrarySearchScreen` 改收 `ReaderFeatureDependencies`

**Files:**
- Modify: `app/lib/screens/library_search_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`（只改「開 `LibrarySearchScreen`」那一處，過渡用）
- Modify: `app/lib/screens/reader_screen_route.dart`（移除 `searchRepository` 覆寫參數）
- Test: `app/test/screens/library_search_screen_test.dart`、`app/test/screens/reader_screen_route_test.dart`、`app/test/screens/library_screen_test.dart`（只動開搜尋那幾案）

**Interfaces:**
- Consumes：Task 1 的 `ReaderFeatureDependencies`（含 `fullTextSearchSettingsRepository`）、`fakeReaderFeatureDependencies`。
- Produces：`LibrarySearchScreen({super.key, String initialQuery = '', required ReaderFeatureDependencies dependencies, bool isEinkMode = false})`；欄位 `final ReaderFeatureDependencies dependencies`（公開，供測試以 `same(...)` 對帳）。`readerFeatureDependenciesFromLegacy` 失去 `searchRepository` 參數。

遷移對照（`library_search_screen.dart`）：

| 舊 | 新 |
|---|---|
| `widget.searchRepository` | `widget.dependencies.searchRepository` |
| `widget.prefsManager` | `widget.dependencies.prefsManager` |
| `widget.libraryRepository` | `widget.dependencies.libraryRepository` |
| `widget.readerFeatureRepositories.fullTextSearchSettingsRepository` | `widget.dependencies.fullTextSearchSettingsRepository`（non-null，移除 `?.`／null 判斷） |
| `widget.readerFeatureRepositories.isFullTextSearchAvailable` | `widget.dependencies.isFullTextSearchAvailable` |
| 兩處 `readerFeatureDependenciesFromLegacy(…)` | 直接 `dependencies: widget.dependencies`（整組轉傳同一實例） |

- [x] **Step 1: 改測試（先紅）**

`library_search_screen_test.dart` 的 29 個 `LibrarySearchScreen(` 改為新建構子。規則（codemod 或手改皆可，完成後以 `flutter analyze` 驗證零遺漏）：

```dart
// 舊
LibrarySearchScreen(
  searchRepository: repo,
  prefsManager: prefs,
  libraryRepository: library,
  readerFeatureRepositories: completeLegacyReaderFeatures(ttsProvider: tts),
  syncDependencies: completeLegacySyncDependencies(syncCheckpointTrigger: t),
)
// 新
LibrarySearchScreen(
  dependencies: fakeReaderFeatureDependencies(
    searchRepository: repo,
    prefsManager: prefs,
    libraryRepository: library,
    ttsProvider: tts,
    syncCheckpointTrigger: t,
  ),
)
```

`completeLegacyReaderFeatures(...)` 的具名引數與 `fakeReaderFeatureDependencies(...)` 同名，直接搬；`completeLegacySyncDependencies(syncCheckpointTrigger: t)` 只搬 `syncCheckpointTrigger`。新增一案（Review Focus 3）：

```dart
testWidgets('點選書籍進入閱讀器時，ReaderScreen 拿到的是 LibrarySearchScreen 的同一個依賴組', (tester) async {
  final deps = fakeReaderFeatureDependencies(/* 沿用該檔既有的搜尋結果種子 */);
  // …沿用既有「點選書籍進入閱讀器」案的 pump／tap 步驟…
  final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
  expect(readerScreen.dependencies, same(deps));
});
```

`reader_screen_route_test.dart`：刪除針對 `searchRepository` 覆寫參數的 2 個測試（Issue 11 M-1 新增者），列入附錄 B。

`library_screen_test.dart`：開全庫搜尋的測試改以 `find.byType(LibrarySearchScreen)` 取 widget，斷言 `.dependencies.searchRepository` 為 `readerFeatureRepositories.searchRepository` 同一實例（此時 `LibraryScreen` 仍是舊建構子，由 Step 3 的過渡組裝產生）。

- [x] **Step 2: 跑測試確認失敗**

Run：`flutter test test/screens/library_search_screen_test.dart`
Expected：編譯失敗（`dependencies` 命名參數不存在）。

- [x] **Step 3: 實作**

1. `LibrarySearchScreen` 建構子與欄位依上表改寫；移除 `searchRepository`／`prefsManager`／`libraryRepository`／`readerFeatureRepositories`／`syncDependencies` 五個參數，以及不再使用的 import（`library_screen_dependencies.dart` 等，以 analyze 為準）。
2. `readerFeatureDependenciesFromLegacy` 刪除 `SearchRepository? searchRepository` 參數與 `searchRepository ?? need(...)` 寫法，改回 `need(features.searchRepository, 'searchRepository')`，並更新文件註解（移除「Issue 12 合併後移除」那段）。
3. `LibraryScreen._openLibrarySearchScreen` 暫時組裝：

```dart
builder: (_) => LibrarySearchScreen(
  initialQuery: _searchQuery,
  dependencies: readerFeatureDependenciesFromLegacy(
    prefsManager: widget.prefsManager,
    features: widget.readerFeatureRepositories,
    sync: widget.syncDependencies,
    libraryRepository: widget.repository,
  ),
  isEinkMode: widget.themeDependencies.isEinkMode,
),
```

保留既有 `searchRepository == null` 提前返回（`LibraryScreen` 本 Task 尚未遷移）。

- [x] **Step 4: 跑測試確認通過**

Run：`flutter test test/screens/library_search_screen_test.dart test/screens/reader_screen_route_test.dart test/screens/library_screen_test.dart`
Expected：全過（通過數＝附錄 C 基準三檔之和 − 被刪案例數 ＋ 新增案例數，算式寫入附錄 C）。

- [x] **Step 5: Commit**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
git add lib/screens/library_search_screen.dart lib/screens/library_screen.dart lib/screens/reader_screen_route.dart \
  test/screens/library_search_screen_test.dart test/screens/reader_screen_route_test.dart test/screens/library_screen_test.dart
git commit -m "refactor(epic-54): Issue 12 LibrarySearchScreen 改收 ReaderFeatureDependencies，合併 searchRepository 單一來源" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：外殼骨幹（`SettingsScaffold`／`LibraryScreen`／`AdaptiveShellScaffold`／`ElinkBookApp`／`main.dart`）一刀切並刪除過渡層

**Files:**
- Modify: `app/lib/screens/settings_scaffold.dart`、`library_screen.dart`、`adaptive_shell_scaffold.dart`、`app/lib/main.dart`
- Modify（刪除）: `app/lib/screens/reader_screen_route.dart`（`readerFeatureDependenciesFromLegacy`）、`app/lib/screens/library_screen_dependencies.dart`（`grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories`、`LibrarySyncDependencies`）
- Modify（刪除）: `app/test/support/fake_reader_feature_dependencies.dart` 內 `completeLegacyReaderFeatures`／`completeLegacySyncDependencies`
- Modify（註解清理，見 Step 2 第 4 點）: `app/lib/screens/sync_settings_screen.dart`、`app/lib/search/full_text_search_settings_repository.dart`、`app/lib/screens/book_action_sheet.dart`
- Test: `app/test/screens/{settings_scaffold,settings_scaffold_reading_stats,library_screen,adaptive_shell_scaffold,library_screen_dependencies,reader_screen_route}_test.dart`、`app/test/{elinkbook_app_wiring,app_lifecycle_sync,navigation}_test.dart`、`app/test/l10n/{locale_switch,elinkbook_app_locale}_test.dart`、`app/test/theme/theme_test.dart`、`app/integration_test/{library_screen,smoke}_test.dart`

> **為什麼這五個畫面必須在同一個 Task 完成（計畫審查 I-1）：** `SettingsScaffold` 不是動態 push 的路由，而是長駐在 `AdaptiveShellScaffold` 的 `IndexedStack` 子項，首幀就會被建構；`AdaptiveShellScaffold` 又由 `ElinkBookApp` 以逐欄位（預設 null）組出舊 bundle。若先單獨把 `SettingsScaffold` 改成 non-null 組，過渡轉換函式在首幀就會對空 bundle 丟 `StateError`，所有經 `ElinkBookApp`／`AdaptiveShellScaffold` 的測試（`theme_test`、`navigation_test`、`adaptive_shell_scaffold_test` 等）必然全紅，而 `ElinkBookApp` 的測試無法補舊 bundle。因此**不設** `grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories` 這種只活一個 Task 的過渡函式，整棵外殼樹原子切換（ADR 0037 §6 一刀切）。**Step 1～3 的中途不 commit**，Task 結束時才一次 commit；工作順序為 `SettingsScaffold` → `LibraryScreen` → `AdaptiveShellScaffold` → `ElinkBookApp`／`main()`，以 `flutter analyze` 的錯誤清單當作遺漏檢查。

**Interfaces:**
- Consumes：Task 1 的兩個組與工廠、Task 2 的 `LibrarySearchScreen(dependencies:)`。
- Produces：
  - `SettingsScaffold` 建構子——保留 `super.key`、`currentTheme`、`isEinkMode`、`onThemeChanged`、`onEinkModeChanged`、`currentLocaleOverride`、`onLocaleChanged`、`cloudAccountRepository`、`googleDriveOAuthClient`、`oneDriveOAuthClient`、`onNavigateToLibrary`、`onNavigateToSource`（Issue 13 範圍，不動）；新增 `required ReaderFeatureDependencies readerFeatures`、`required SyncDependencies sync`；**移除** `prefsManager`、`customFontsRepository`、`downloadableFontStore`、`syncAccountRepository`、`syncClient`、`onManualSync`、`loadLastSyncedAt`、`ttsProvider`、`fullTextSearchSettingsRepository`、`isFullTextSearchAvailable`、`readingStatsRepository`（共 11 個）。
  - `LibraryScreen({super.key, required ReaderFeatureDependencies dependencies, LibraryCloudAccountDependencies cloudAccountDependencies, LibraryRemoteLibraryDependencies remoteLibraryDependencies, ComputeRemoteFingerprint? computeFingerprint, Future<bool> Function()? isMobileDataConnection, LibraryThemeDependencies themeDependencies, Listenable? refreshSignal, VoidCallback? onNavigateToSource, VoidCallback? onNavigateToSettings})`——**移除** `repository`／`importService`／`prefsManager`／`readerFeatureRepositories`／`syncDependencies`；公開欄位 `final ReaderFeatureDependencies dependencies`。
  - `AdaptiveShellScaffold({super.key, required ReaderFeatureDependencies readerFeatures, required SyncDependencies sync, …Issue 13 範圍欄位原樣保留})`——**移除** `repository`／`importService`／`prefsManager`／`readerFeatureRepositories`／`syncDependencies`；公開欄位 `readerFeatures`、`sync`。
  - `ElinkBookApp({super.key, required ReaderFeatureDependencies readerFeatures, required SyncDependencies sync, …雲端／遠端／主題／語言／網路等欄位原樣保留})`——**移除**逐欄位的 `repository`／`importService`／`prefsManager`／`bookmarksRepository`／`highlightsRepository`／`notesRepository`／`customFontsRepository`／`downloadableFontStore`／`layoutPresetRepository`／`bookReaderPrefsRepository`／`ttsProvider`／`ttsAudio`／`ttsAudioFocusSource`／`readerActivityTracker`／`syncAccountRepository`／`syncClient`／`syncCheckpointTrigger`／`onManualSync`／`loadLastSyncedAt`／`fullTextSearchSettingsRepository`／`isFullTextSearchAvailable`／`searchRepository`／`readingStatsRepository`（共 23 個）。

遷移對照與 null 判斷處理（`settings_scaffold.dart`）：

| 位置 | 舊 | 新 |
|---|---|---|
| 字型管理入口 | `customFontsRepository == null ? null : …` 與 `!` | 恆可點；`repository: widget.readerFeatures.customFontsRepository`、`downloadableFontStore: widget.readerFeatures.downloadableFontStore` |
| 閱讀統計入口 | `if (readingStatsRepository != null)` | 移除條件，恆顯示；`repository: widget.readerFeatures.readingStatsRepository` |
| 全文檢索開關 | `isFullTextSearchAvailable`（保留判斷）、`fullTextSearchSettingsRepository == null` 判斷與 `!` | 保留 `!isFullTextSearchAvailable` 降級提示；移除 null 判斷與 `!` |
| 同步入口 | 四欄位 null 判斷＋`!` | 恆可點；`SyncSettingsScreen(accountRepository: widget.sync.syncAccountRepository, syncClient: widget.sync.syncClient, onManualSync: widget.sync.onManualSync, loadLastSyncedAt: widget.sync.loadLastSyncedAt)` |
| `initState`／`didUpdateWidget` | `FullTextSearchTogglesController(widget.fullTextSearchSettingsRepository)`、比較舊新 repository | 改取 `widget.readerFeatures.fullTextSearchSettingsRepository`；`didUpdateWidget` 比較 `oldWidget.readerFeatures.fullTextSearchSettingsRepository`（保留此守衛，行為不變）。`FullTextSearchTogglesController` 建構子參數維持 nullable（內部元件，不在本 Issue 範圍） |
| 其他 `widget.prefsManager` | | `widget.readerFeatures.prefsManager` |


遷移對照（`library_screen.dart`）：

| 舊 | 新 |
|---|---|
| `widget.repository` | `widget.dependencies.libraryRepository` |
| `widget.importService` | `widget.dependencies.bookImportService` |
| `widget.prefsManager` | `widget.dependencies.prefsManager` |
| `widget.readerFeatureRepositories.fullTextSearchSettingsRepository`（含 `?.`） | `widget.dependencies.fullTextSearchSettingsRepository`（移除 `?.`） |
| `readerFeatureDependenciesFromLegacy(…)`（`_openBook`） | `dependencies: widget.dependencies`（整組轉傳同一實例） |
| `_openLibrarySearchScreen` 暫時組裝與 `searchRepository == null` 提前返回 | `LibrarySearchScreen(initialQuery: _searchQuery, dependencies: widget.dependencies, isEinkMode: …)`；移除提前返回 |
| `_buildContentSearchEntryButton` 的 `hasSearchRepository ? … : null` | `onPressed: _openLibrarySearchScreen`；移除 `hasSearchRepository` |
| `showLayoutOverride: bookReaderPrefsRepository != null` | `showLayoutOverride: true`；移除區域變數 `bookReaderPrefsRepository`（`BookActionSheet` 的 `showLayoutOverride` 參數與其測試保留，那是元件自己的可達行為） |
| `didUpdateWidget` 的 `readerFeatureRepositories != old… \|\| repository != old…` | `widget.dependencies != oldWidget.dependencies`（組是同一實例時不重建 `_batchActions`） |

- [x] **Step 1: 改測試（先紅）**

0. **`SettingsScaffold` 測試（`settings_scaffold_test.dart` 45 處等，含 `locale_switch_test.dart`、`theme_test.dart`、`library_search_screen_test.dart` 內各 1～3 處）：**

```dart
// 舊
SettingsScaffold(
  prefsManager: prefs,
  customFontsRepository: fonts,
  syncAccountRepository: acc, syncClient: client, onManualSync: sync, loadLastSyncedAt: last,
  fullTextSearchSettingsRepository: fts, isFullTextSearchAvailable: false,
  ttsProvider: tts, readingStatsRepository: stats,
  currentTheme: …, onThemeChanged: …,   // Issue 13 範圍，原樣保留
)
// 新
SettingsScaffold(
  readerFeatures: fakeReaderFeatureDependencies(
    prefsManager: prefs, customFontsRepository: fonts,
    fullTextSearchSettingsRepository: fts, isFullTextSearchAvailable: false,
    ttsProvider: tts, readingStatsRepository: stats,
  ),
  sync: fakeSyncDependencies(
    syncAccountRepository: acc, syncClient: client, onManualSync: sync, loadLastSyncedAt: last,
  ),
  currentTheme: …, onThemeChanged: …,
)
```

   新增測試（Review Focus 5）：

```dart
testWidgets('同步入口恆可點，且 SyncSettingsScreen 拿到的是組內同一批物件', (tester) async {
  final sync = fakeSyncDependencies();
  await pumpLocalizedWidget(tester, SettingsScaffold(
    readerFeatures: fakeReaderFeatureDependencies(),
    sync: sync,
  ));
  await tester.tap(find.byKey(const Key('settings_sync_button')));
  await tester.pumpAndSettle();
  final screen = tester.widget<SyncSettingsScreen>(find.byType(SyncSettingsScreen));
  expect(screen.accountRepository, same(sync.syncAccountRepository));
  expect(screen.syncClient, same(sync.syncClient));
  expect(screen.onManualSync, same(sync.onManualSync));
  expect(screen.loadLastSyncedAt, same(sync.loadLastSyncedAt));
});
```

   被刪的「依賴缺席」測試：先以 `grep -n "未提供\|沒有\|為 null\|null 時\|disabled\|停用" test/screens/settings_scaffold*_test.dart` 列出候選，逐一對照是否「僅驗證缺席」。預期涵蓋 字型管理入口停用、閱讀統計入口隱藏、全文檢索開關在 repository 為 null 時停用、同步入口在任一欄位為 null 時停用；逐一記入附錄 B（名稱＋刪除理由＋對應的新恆真行為）。**`isFullTextSearchAvailable: false` 的降級提示測試必須保留。**

1. `library_screen_test.dart`（133 處）、`adaptive_shell_scaffold_test.dart`（12）、integration 的 `library_screen_test.dart`／`smoke_test.dart`、`navigation_test.dart`、`locale_switch_test.dart`、`settings_scaffold_reading_stats_test.dart`：依下列規則遷移。**寫一支一次性 Node codemod**（放在 worktree 內已 gitignore 的 `.scratch/`〔`.gitignore` 第 80 行〕，不進版控，完成後刪除；比照 Issue 11 的做法）處理機械部分，規則如下，處理後以 `git diff --stat` 與 `flutter analyze` 驗收，無法機械處理的手改：

```dart
// LibraryScreen 舊
LibraryScreen(
  repository: R, importService: I, prefsManager: P,
  readerFeatureRepositories: completeLegacyReaderFeatures(a: …),   // 或 const grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories(b: …)
  syncDependencies: completeLegacySyncDependencies(syncCheckpointTrigger: T),
  themeDependencies: …, cloudAccountDependencies: …,               // 其餘 Issue 13 範圍原樣保留
)
// 新
LibraryScreen(
  dependencies: fakeReaderFeatureDependencies(
    libraryRepository: R, bookImportService: I, prefsManager: P,
    a: …, b: …, syncCheckpointTrigger: T,
  ),
  themeDependencies: …, cloudAccountDependencies: …,
)
// AdaptiveShellScaffold：同上，另加 sync: fakeSyncDependencies(syncAccountRepository: …, syncCheckpointTrigger: T, …)
```

   - `const grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories(x: v)` 裡的欄位若為 `null`／省略，一律改用工廠預設 fake（Issue 11 先例：預設全 fake，只覆寫情境需要者）。
   - `SourcesHomeScreen` 等其他畫面的呼叫不動。

2. `library_screen_test.dart` 被刪案例（計畫審查 M-1）：`bookReaderPrefsRepository 未提供時，「版面覆寫」選項不顯示`（約 4791 行）；另以 `grep -n "searchRepository|未提供|沒有" test/screens/library_screen_test.dart` 找出「搜尋入口在 searchRepository 為 null 時停用」類案例。一律記入附錄 B。
3. `library_screen_dependencies_test.dart`：刪除針對 `grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories`／`LibrarySyncDependencies` 的測試（型別即將刪除），保留 Cloud／Remote／Theme／Locale 四個 bundle 的測試。列入附錄 B。
4. `reader_screen_route_test.dart`：刪除針對轉換函式的測試（含 Task 1 新增者），保留 `buildReaderScreen` 的測試。列入附錄 B。
5. **新增 wiring 測試**（`elinkbook_app_wiring_test.dart`，Review Focus 1、2）：

```dart
testWidgets('ElinkBookApp 把同一個閱讀器組與同步組原樣傳到書架、搜尋與設定', (tester) async {
  final trigger = fakeSyncDependencies().syncCheckpointTrigger;
  final readerFeatures = fakeReaderFeatureDependencies(syncCheckpointTrigger: trigger);
  final sync = fakeSyncDependencies(syncCheckpointTrigger: trigger);
  await tester.pumpWidget(ElinkBookApp(readerFeatures: readerFeatures, sync: sync));
  await tester.pumpAndSettle();
  expect(tester.widget<AdaptiveShellScaffold>(find.byType(AdaptiveShellScaffold)).readerFeatures, same(readerFeatures));
  expect(tester.widget<AdaptiveShellScaffold>(find.byType(AdaptiveShellScaffold)).sync, same(sync));
  expect(tester.widget<LibraryScreen>(find.byType(LibraryScreen)).dependencies, same(readerFeatures));
  expect(tester.widget<SettingsScaffold>(find.byType(SettingsScaffold, skipOffstage: false)).readerFeatures, same(readerFeatures));
  expect(readerFeatures.syncCheckpointTrigger, same(sync.syncCheckpointTrigger));
});

testWidgets('主題切換使 ElinkBookApp 重建後，依賴組仍是同一實例（不是 build 內新建）', (tester) async {
  // 以 theme_test 既有的切換主題手法觸發 setState，再重新取 LibraryScreen.dependencies，
  // 斷言仍 same(readerFeatures)。
});
```

   `app_lifecycle_sync_test.dart` 既有案例（`paused` 觸發 checkpoint）改以 `sync.syncCheckpointTrigger` 驗證，並保留原斷言強度。

- [x] **Step 2: 實作畫面層（SettingsScaffold、LibraryScreen、AdaptiveShellScaffold）**

1. `SettingsScaffold` 依「遷移對照與 null 判斷處理」表改寫（移除 11 個舊欄位與不再使用的 import）。
2. `LibraryScreen`、`AdaptiveShellScaffold` 依 Interfaces 與 `library_screen.dart` 對照表改寫；`AdaptiveShellScaffold` 把 `widget.readerFeatures.libraryRepository`／`.bookImportService` 傳給 `SourcesHomeScreen`（它的建構子是 Issue 13 範圍，不動）；`SettingsScaffold` 直接收 `readerFeatures: widget.readerFeatures, sync: widget.sync`；`LibraryScreen` 收 `dependencies: widget.readerFeatures`。
3. 刪除 `readerFeatureDependenciesFromLegacy`（`reader_screen_route.dart` 只剩 `buildReaderScreen`）、`grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories`、`LibrarySyncDependencies`（`library_screen_dependencies.dart` 剩四個 bundle，並清掉不再使用的 import）。
4. **清理註解中的舊型別名稱（計畫審查 M-2；否則 Step 4 的殘留 grep 會被註解誤報）：** 以 `grep -rn "grep -rn "readerFeatureDependenciesFromLegacy|LibraryReaderFeatureRepositories\|LibrarySyncDependencies" lib` 列出，預期位置為 `main.dart`（約 175、393、419 行）、`library_screen.dart`（約 199 行）、`settings_scaffold.dart`（約 62 行）、`sync_settings_screen.dart`（約 18 行）、`search/full_text_search_settings_repository.dart`（約 53 行）、`screens/book_action_sheet.dart`（約 31 行提到 `readerFeatureRepositories.bookReaderPrefsRepository`）。這些註解改為指向新的 `SyncDependencies`／`ReaderFeatureDependencies`，**只改型別名稱與必要的措辭，不重寫其他說明**。
5. 刪除 `completeLegacyReaderFeatures`／`completeLegacySyncDependencies`（`fake_reader_feature_dependencies.dart`）與其測試（`fake_reader_feature_dependencies_test.dart` 的相關案例，含 Task 1 補的）。

- [x] **Step 3: 實作根部（`ElinkBookApp`／`main()`）**

1. `ElinkBookApp` 依 Interfaces 改為持有 `readerFeatures`／`sync`；`build()` 直接 `AdaptiveShellScaffold(readerFeatures: widget.readerFeatures, sync: widget.sync, …)`，不再組裝舊 bundle；`WifiTransferDependencies(libraryRepository: widget.readerFeatures.libraryRepository, importService: widget.readerFeatures.bookImportService, …)`；`didChangeAppLifecycleState` 改為 `widget.sync.syncCheckpointTrigger.trigger()`（non-null，移除 `?.`）。
2. `main()` 在 `runApp` 前建構兩個組，**`syncCheckpointTrigger` 只用已有的那個區域變數**：

```dart
final readerFeatures = ReaderFeatureDependencies(
  prefsManager: prefsManager,
  libraryRepository: repository,
  bookImportService: importService,
  /* …bookmarks／highlights／notes／customFonts／downloadableFontStore／layoutPreset／prefsRepository→bookReaderPrefsRepository／
     searchRepository／isFullTextSearchAvailable: repository.isFullTextSearchAvailable／fullTextSearchSettingsRepository／
     readingStatsRepository／readerActivityTracker／ttsProvider／ttsAudio／ttsAudioFocusSource…值沿用原 ElinkBookApp(...) 實參… */
  syncCheckpointTrigger: syncCheckpointTrigger,
);
final sync = SyncDependencies(
  syncAccountRepository: syncAccountRepository,
  syncClient: syncClient,
  syncCheckpointTrigger: syncCheckpointTrigger,        // 與上方同一實例
  onManualSync: syncEngine.runCheckpoint,
  loadLastSyncedAt: syncMetadataRepository.loadLastPushCompletedAt,
);
runApp(ElinkBookApp(readerFeatures: readerFeatures, sync: sync, /* 其餘欄位原樣 */));
```

   `main.dart` 內原本傳給 `ElinkBookApp` 的值（含上面省略者）一律照抄，不得改動取值方式。

- [x] **Step 4: 跑測試確認通過**

```bash
flutter analyze
flutter test test/screens/settings_scaffold_test.dart test/screens/library_screen_test.dart test/screens/adaptive_shell_scaffold_test.dart \
  test/screens/library_screen_dependencies_test.dart test/screens/reader_screen_route_test.dart \
  test/screens/settings_scaffold_reading_stats_test.dart test/elinkbook_app_wiring_test.dart \
  test/app_lifecycle_sync_test.dart test/navigation_test.dart test/l10n test/theme \
  test/support/fake_reader_feature_dependencies_test.dart
```

Expected：analyze 乾淨；全過。通過數算式寫入附錄 C：`基準 − 被刪（附錄 B）＋ 新增`。刪除殘留檢查：

```bash
grep -rn "readerFeatureDependenciesFromLegacy\|LibraryReaderFeatureRepositories\|LibrarySyncDependencies\|completeLegacy" lib test integration_test
```

Expected：**無輸出**（含註解；註解已於 Step 2 第 4 點清理）。

- [x] **Step 5: 守衛腳本與提交**

```bash
node tool/check_l10n_hardcoded_strings.js
node tool/check_integration_keys.js
git add lib test integration_test
git commit -m "refactor(epic-54): Issue 12 外殼骨幹（設定、書架、外殼、App）改收依賴組並移除過渡層" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：完整驗證、ADR 與文件同步

**Files:**
- Modify: `docs/adr/0037-dependencies-grouped-by-consumer-passed-as-one-object.md`、`docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、本計畫檔（勾選、附錄 A／B／C）

- [x] **Step 1: 完整 `flutter test`（只此一次，背景執行）**

在 `app/` 下以 `run_in_background` 執行 `flutter test`。Expected：除 Issue 18／19 已記錄的既存失敗（`pdf_reader_view_filters_test` 加粗 debouncer，乾淨 `main` 同樣失敗）外全過；出現其他失敗逐一判定是否本 Issue 回歸。

- [x] **Step 2: integration 靜態確認與真機（需使用者在場）**

`integration_test/library_screen_test.dart`、`smoke_test.dart` 本 Task 只做機械遷移。向使用者確認後在 `TCL 14`（序號 `3CEF42ECD491687`）執行：

```bash
export MSYS_NO_PATHCONV=1
cd /c/Users/fycdc/AI/elinkBook/.worktrees/epic-54-issue-12/app
flutter test integration_test/library_screen_test.dart -d 3CEF42ECD491687
flutter test integration_test/smoke_test.dart -d 3CEF42ECD491687
```

結果只宣稱此裝置；`library_screen_test` 在 base 上本來就失敗（Issue 17 記錄「找不到 `book_item_…`」，既存），以「與 base 同樣失敗」或「通過」如實記錄，不得宣稱修好。無法在場則在 `epic.md` 明寫「真機未驗」。

- [x] **Step 3: 同步 ADR 0037 措辭**

- §1 `ReaderFeatureDependencies` 補列 `fullTextSearchSettingsRepository`（Q1 決定）；`SyncDependencies` 註明只被 `SettingsScaffold` 與其上層使用，`LibraryScreen`／`LibrarySearchScreen` 只收閱讀器組。
- §6 的「過渡轉換函式」段改為過去式（計畫審查 M-3：改寫時對照 ADR 原文，§1 關於「`syncCheckpointTrigger` 同時放入閱讀器組與同步組、由 `AppDependencies` 建構一次」的敘述必須逐字保持，不得因本次補列欄位而位移語意）：`readerFeatureDependenciesFromLegacy` 已於 Issue 12 移除，不再有新舊並存。

- [x] **Step 4: 回寫文件（隨功能分支一起 commit）**

- `epic.md`：新增「Issue 12 實作完成」段（內容、驗證數字、附錄 B 摘要、真機結果或「未驗」、使用者決定的原話出處）。
- 本計畫：勾選全部 Step，附錄 A（使用者原話）、附錄 B（被刪測試清單）、附錄 C（測試數算式）填完。
- **不要**在功能分支上改 `issues.md` 第 12 列與 `docs/epics.md`：這兩處在 PR 合併後於 `main` 直接 commit＋push（`⚪ 待規劃` → `🟢 已合併（PR #N）`，備註只寫「Issue 12 已合併」）。

- [ ] **Step 5: 請求程式審查**

```bash
git log --oneline main..HEAD
flutter analyze
```

審查者先產出報告（`reviews/review-code-issue-12.md`，gitignore），不得直接改程式；處理審查意見後才發 PR（Gitea：`tea pr create -l jigong -r huthief/elinkBook`，由使用者合併）。

---

## 附錄 A：使用者決定紀錄（Task 0 Step 2 取得後填入原話）

- Task 0 Step 2（Q1～Q3 設計決定）：使用者於 2026-10-08 對話回答原話：`全 A`。對應：Q1＝A（`fullTextSearchSettingsRepository` 併入 `ReaderFeatureDependencies`，19 欄位）；Q2＝A（`LibraryScreen`／`AdaptiveShellScaffold` 移除自己的 `repository`／`importService`／`prefsManager`，單一來源）；Q3＝A（`ElinkBookApp` 本 Issue 就改收 `readerFeatures`／`sync`）。

## 附錄 B：被刪除的測試清單（依「依賴 non-null，缺席型別上不可達」原則）

依「依賴 non-null，缺席型別上不可達」原則刪除，無其他理由：

| 測試檔 | 被刪測試 | 理由／對應的新恆真行為 |
|---|---|---|
| `reader_screen_route_test.dart`（Task 2） | 「傳入 searchRepository 時優先於 bundle 內的欄位」「傳入 searchRepository 時，bundle 的 searchRepository 為 null 也不丟 StateError」共 2 案 | `searchRepository` 覆寫參數隨雙來源合併一併移除（單一來源） |
| `reader_screen_route_test.dart`（Task 3） | `readerFeatureDependenciesFromLegacy` 整個 group 共 17 案：15 個欄位為 null 丟 StateError、sync trigger 為 null、舊 bundle 完整轉換 | 轉換函式與舊 bundle 已刪除，型別不存在 |
| `library_screen_dependencies_test.dart` | `LibraryReaderFeatureRepositories` 持有六個依賴／readingStatsRepository／bookImportService 共 3 案、`LibrarySyncDependencies` 1 案 | 兩個舊 bundle 已刪除；Cloud／Remote／Theme／Locale 四個 bundle 的測試保留 |
| `fake_reader_feature_dependencies_test.dart` | `completeLegacyReaderFeatures` group 2 案 | 相容工廠已刪除 |
| `settings_scaffold_reading_stats_test.dart` | 「readingStatsRepository 為 null 時不顯示閱讀統計項目」「AdaptiveShellScaffold 的 bundle 沒有 repository 時設定頁不顯示項目」共 2 案 | `readingStatsRepository` 為 non-null required，設定頁閱讀統計入口恆顯示 |
| `library_screen_test.dart` | 「bookReaderPrefsRepository 未提供時，版面覆寫選項不顯示」「searchRepository 為 null 時，搜尋書本內容入口停用」共 2 案 | 版面覆寫列、全庫搜尋入口恆啟用（`BookActionSheet.showLayoutOverride` 參數與其元件測試保留） |

原本因欄位為 null 而停用的入口，在 non-null 下恆啟用（正式環境本來就恆提供）：全庫搜尋入口按鈕、書架長按版面覆寫列、設定頁字型管理／閱讀統計／全文檢索兩個開關／同步入口。`isFullTextSearchAvailable: false` 的降級提示測試全部保留。

另有一案「點擊搜尋結果開書時，ReaderScreen 收到的 searchRepository…」（library_search_screen_test）改寫而非刪除：雙來源合併後改為比對 `LibrarySearchScreen.dependencies.searchRepository` 同一實例。

## 附錄 C：測試數基準與算式

- Task 0 基準（14 個測試檔）：278 通過；`flutter analyze` No issues found。
- Task 1：`flutter test test/support test/screens/reader_screen_route_test.dart` → 71 通過。
- Task 2：library_search + reader_screen_route + library_screen 三檔 → 180 通過。
- Task 3（範圍：14 個基準檔）：255 通過。算式：基準 278 ＋ 新增 5（fake_reader 全文檢索覆寫 1、library_search 同一依賴組 1、wiring 2、settings 同步入口 1）− 被刪 28（route 轉換函式 group 18〔含 Task 2 刪的 2 案與 Task 1 補的 1 案後淨值〕、library_screen_dependencies 4、fake_reader 相容工廠 2、reading_stats 2、library_screen 2）＝ 255，與實測一致（審查 M-4 已對帳）。
- Task 4 完整 `flutter test`：見 `epic.md`「Issue 12 實作完成」。

## Self-Review 結果

- **Spec 涵蓋**：issues.md 第 12 列——「四個畫面改收依賴組」→ Task 2／3（並澄清 `LibraryScreen`／`LibrarySearchScreen` 只收閱讀器組的事實，見「已查證的事實」）；「`LibrarySearchScreen` 的 `searchRepository` 與 bundle 內欄位合併為一個來源」→ Task 2；「移除 `readerFeatureDependenciesFromLegacy` 的 `searchRepository` 覆寫參數」→ Task 2 Step 3，並於 Task 3 整個函式刪除；「依賴 Issue 11」→ 已合併（PR #327）。ADR 0037 §6「最後一個外層畫面遷移完成時移除組裝」→ Task 3。
- **佔位掃描**：附錄 A／B／C 刻意留白，由執行者依實測填入（附錄 B 已寫明預期類別與唯一允許的刪除理由）；`main()` 的 `ReaderFeatureDependencies(...)` 欄位列表以「照抄原 `ElinkBookApp(...)` 實參」交代，原因是 19 個欄位的取值逐字存在於現行 `main.dart`，重抄一份只會製造不一致。
- **型別一致**：`SyncDependencies` 五欄位、`fakeSyncDependencies`、`readerFeatures`／`sync`／`dependencies` 三個公開欄位名在 Task 1～4 一致；`LibrarySearchScreen.dependencies`、`LibraryScreen.dependencies`、`AdaptiveShellScaffold.readerFeatures`／`.sync`、`ElinkBookApp.readerFeatures`／`.sync`、`SettingsScaffold.readerFeatures`／`.sync` 的命名依畫面角色區分，已在各 Task 的 Interfaces 逐一列出。
- **Review Focus**：5 項皆對應到具體測試（wiring `same`、主題切換後組不變、搜尋→閱讀器 `same`、同步入口 `same`、附錄 B 逐項記錄）。
- **風險**：Task 3 是原子切換（外殼骨幹五個畫面，不可再拆，見計畫審查 I-1）（ADR §6 要求），範圍大但不可再拆；其內部 Step 順序（先測試後實作、最後才 commit）已寫明。測試呼叫端合計約 300 處，採 codemod＋`flutter analyze` 驗收，與 Issue 11 做法一致。
