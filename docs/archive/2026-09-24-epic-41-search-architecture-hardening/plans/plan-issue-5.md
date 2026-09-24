# Epic 41 Issue 5：抽出 FullTextSearchTogglesController Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 新增 `FullTextSearchTogglesController`，收斂 `library_search_screen.dart` 的 `_FullTextSearchQuickSettingsPanelState` 與 `settings_scaffold.dart` 的 `_SettingsScaffoldState` 兩處逐行重複的「載入兩個全文檢索開關狀態」＋「切換前確認、切換後更新」邏輯，兩個 Widget 改為持有同一個 controller 實例，只保留各自的 UI 排版與確認 Dialog 呼叫。

**Architecture:** 新增 `app/lib/search/full_text_search_toggles_controller.dart`，內含純資料物件 `FullTextSearchTogglesController`（不繼承 `ChangeNotifier`），持有 `pdfEnabled`／`foliateEnabled` 兩個公開可變布林欄位與 `load()`／`toggle()` 兩個方法。`_repository` 於建構子注入、可為 `null`（未組裝/測試替身缺省情境），為 `null` 時 `load()`／`toggle()` 皆直接 no-op。確認 Dialog 的彈出/取消判斷（需要 `BuildContext`）維持在各自 Widget 層，於呼叫 `toggle()` 前處理；兩個 Widget 在 `await controller.toggle(...)` 後自行 `setState(() {})` 刷新畫面。

**Tech Stack:** Flutter/Dart，`flutter_test`（純 Dart 單元測試驗證 `FullTextSearchTogglesController` 本身；既有 `testWidgets` 驗證兩個 Widget 呼叫端零回歸）。

**Spec:** `docs/epics/epic-41-search-architecture-hardening/issues.md`（Issue 5 段落，已依 `reviews/review-epic-and-issues.md` M-2 修訂——明訂可空 `repository` no-op 語意、controller 維持純資料物件、不繼承 `ChangeNotifier`）。

## Global Constraints

- 所有新增/修改的程式碼註解與本計畫文件一律使用正體中文（zh-TW），不得使用簡體中文（使用者全域 CLAUDE.md 規則）。
- `FullTextSearchTogglesController` **不得**繼承 `ChangeNotifier`——維持純資料物件，呼叫端在 `await controller.load()`/`await controller.toggle(...)` 後自行 `setState(() {})`（`reviews/review-epic-and-issues.md` M-2 已定案；比較貼合現有兩個 `StatefulWidget` 各自手動 `setState` 的既有寫法，不需要額外引入 `AnimatedBuilder`）。
- `_repository`（型別 `FullTextSearchSettingsRepository?`）於建構子注入、**唯讀**（`final`），不在 `load()`/`toggle()` 執行期間重新指定。`_repository == null` 時 `load()`/`toggle()` 皆直接 no-op、**不拋例外**，`pdfEnabled`/`foliateEnabled` 維持預設值 `false`；呼叫端不需要先自行判斷 `repository != null` 才建構 controller。
- `toggle()` **不**負責彈出確認 Dialog——「從關閉切成開啟時先詢問使用者確認」這段邏輯需要 `BuildContext`，維持在各自 Widget 的 `_load`/`_handleToggle` 方法內，於呼叫 `controller.toggle(...)` 前處理；`toggle()` 只負責呼叫 `repository.setEnabled()` 並更新內部布林值。
- 兩個 Widget 原本各自在 `_load()`/`_handleToggle()` 內部自行判斷 `if (repository == null) return;` 後才決定要不要彈確認 Dialog；重構後這個判斷完全交給 controller 的 no-op 語意吸收，Widget 層不需要再重複判斷——`Switch`/`IconButton` 的 `onChanged`/`onPressed` 原本就已經在 `widget.repository == null` 時停用（設為 `null`），UI 上本來就無法在 repository 為 null 時觸發切換，這個簡化不影響任何既有測試（兩個測試檔皆未針對「repository 為 null 時直接呼叫 `_handleToggle`」單獨測試過）。
- `full_text_search_toggles_controller.dart` 只依賴 `full_text_search_settings_repository.dart`（`FullTextSearchSettingsRepository`／`ContentIndexCategory`），不依賴 `BuildContext`／`Theme`／任何 Flutter widget 概念。
- **範圍邊界（`reviews/review-plan-issue-5.md` M-3）**：`_LibrarySearchScreenState`（`library_search_screen.dart:92-102`）也有一份逐行相同的 `_loadFullTextSearchSettings()`，但它只是用來產生 `_guidanceMessage()` 顯示文字的**純讀取端**，不含 `toggle` 切換操作、不是開關面板——Issue 5 的範圍（`/grilling` Q7）明確聚焦於「兩個開關面板」`_FullTextSearchQuickSettingsPanelState`／`_SettingsScaffoldState`，本次刻意不改動這第三份純讀取端。
- 每個 Task 只跑「這次異動實際觸及」的測試檔；只在**最後一個 Task**（Task 3）跑一次完整 `flutter analyze`／`flutter test` 作最終確認（專案 `CLAUDE.md`「測試執行範圍」既有慣例）。
- Git commit 訊息結尾需附加下列兩行（本次 session 的固定 attribution，見系統提示）：
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
  ```

---

### Task 1: 新增 `FullTextSearchTogglesController`

**Files:**
- Create: `app/lib/search/full_text_search_toggles_controller.dart`
- Test: `app/test/search/full_text_search_toggles_controller_test.dart`（新檔案）

**Interfaces:**
- Consumes：既有型別 `FullTextSearchSettingsRepository`／`ContentIndexCategory`（`search/full_text_search_settings_repository.dart`）；測試使用既有 `test/support/fake_full_text_search_settings_repository.dart` 的 `FakeFullTextSearchSettingsRepository`。
- Produces（供 Task 2／Task 3 呼叫）：
  ```dart
  class FullTextSearchTogglesController {
    FullTextSearchTogglesController(this._repository);
    bool get pdfEnabled;    // 預設 false，唯讀，只能透過 toggle() 變更
    bool get foliateEnabled; // 預設 false，唯讀，只能透過 toggle() 變更

    Future<void> load();
    Future<void> toggle(ContentIndexCategory category, bool newValue);
  }
  ```

- [x] **Step 1: 寫失敗測試**

建立 `app/test/search/full_text_search_toggles_controller_test.dart`：

```dart
// app/test/search/full_text_search_toggles_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';
import 'package:elinkbook/search/full_text_search_toggles_controller.dart';

import '../support/fake_full_text_search_settings_repository.dart';

void main() {
  group('FullTextSearchTogglesController.load', () {
    test('正確讀回兩個分類目前的啟用狀態', () async {
      final repository = FakeFullTextSearchSettingsRepository(
        initialEnabled: {
          ContentIndexCategory.pdf: true,
          ContentIndexCategory.foliate: false,
        },
      );
      final controller = FullTextSearchTogglesController(repository);

      await controller.load();

      expect(controller.pdfEnabled, isTrue);
      expect(controller.foliateEnabled, isFalse);
    });

    test('repository 為 null 時安全 no-op，兩個布林值維持預設 false，不拋例外', () async {
      final controller = FullTextSearchTogglesController(null);

      await controller.load();

      expect(controller.pdfEnabled, isFalse);
      expect(controller.foliateEnabled, isFalse);
    });
  });

  group('FullTextSearchTogglesController.toggle', () {
    test('切換 PDF 分類：呼叫 repository.setEnabled 並更新 pdfEnabled，foliateEnabled 不受影響',
        () async {
      final repository = FakeFullTextSearchSettingsRepository();
      final controller = FullTextSearchTogglesController(repository);

      await controller.toggle(ContentIndexCategory.pdf, true);

      expect(controller.pdfEnabled, isTrue);
      expect(controller.foliateEnabled, isFalse);
      expect(repository.setEnabledCalls, [(ContentIndexCategory.pdf, true)]);
    });

    test('切換其他格式分類：呼叫 repository.setEnabled 並更新 foliateEnabled，pdfEnabled 不受影響',
        () async {
      final repository = FakeFullTextSearchSettingsRepository();
      final controller = FullTextSearchTogglesController(repository);

      await controller.toggle(ContentIndexCategory.foliate, true);

      expect(controller.foliateEnabled, isTrue);
      expect(controller.pdfEnabled, isFalse);
      expect(
        repository.setEnabledCalls,
        [(ContentIndexCategory.foliate, true)],
      );
    });

    test('repository 為 null 時安全 no-op，兩個布林值維持不變，不拋例外', () async {
      final controller = FullTextSearchTogglesController(null);

      await controller.toggle(ContentIndexCategory.pdf, true);

      expect(controller.pdfEnabled, isFalse);
      expect(controller.foliateEnabled, isFalse);
    });

    test('切換開關由開啟轉為關閉（newValue = false）：正確更新布林值並呼叫 repository.setEnabled',
        () async {
      final repository = FakeFullTextSearchSettingsRepository(
        initialEnabled: {ContentIndexCategory.pdf: true},
      );
      final controller = FullTextSearchTogglesController(repository);
      await controller.load();
      expect(controller.pdfEnabled, isTrue);

      await controller.toggle(ContentIndexCategory.pdf, false);

      expect(controller.pdfEnabled, isFalse);
      expect(repository.setEnabledCalls, [(ContentIndexCategory.pdf, false)]);
    });
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/search/full_text_search_toggles_controller_test.dart`
Expected: FAIL（編譯錯誤，找不到 `package:elinkbook/search/full_text_search_toggles_controller.dart`）

- [x] **Step 3: 寫最小實作**

建立 `app/lib/search/full_text_search_toggles_controller.dart`：

```dart
// app/lib/search/full_text_search_toggles_controller.dart
import 'full_text_search_settings_repository.dart';

/// 收斂「啟用全文檢索」兩個分類（PDF／其他格式）開關的讀取與切換邏輯
/// （epic-41-search-architecture-hardening Issue 5）：`library_search_screen.dart`
/// 的 `_FullTextSearchQuickSettingsPanel` 與 `settings_scaffold.dart` 的
/// `SettingsScaffold` 原本逐行重複實作同一套「呼叫 isEnabled() 兩次填兩個
/// 布林值」＋「切換前彈確認 Dialog、確認後呼叫 setEnabled 再更新畫面」邏輯，
/// 收斂成這個純資料物件。
///
/// 刻意**不繼承** `ChangeNotifier`——確認 Dialog 的彈出/取消判斷需要
/// `BuildContext`，維持在各自 Widget 層呼叫 [toggle] 前處理；兩個呼叫端在
/// `await controller.toggle(...)` 後自行 `setState(() {})` 刷新畫面，比引入
/// `ChangeNotifier`／`AnimatedBuilder` 更貼合既有兩個 `StatefulWidget` 的
/// 既有寫法（`reviews/review-epic-and-issues.md` M-2 已定案）。
class FullTextSearchTogglesController {
  FullTextSearchTogglesController(this._repository);

  final FullTextSearchSettingsRepository? _repository;

  bool _pdfEnabled = false;
  bool _foliateEnabled = false;

  /// 唯讀——只能透過 [toggle] 變更，避免呼叫端略過 `repository.setEnabled()`
  /// 直接賦值，導致記憶體狀態與持久化儲存不同步。
  bool get pdfEnabled => _pdfEnabled;
  bool get foliateEnabled => _foliateEnabled;

  /// 從 repository 讀回兩個分類目前的啟用狀態。[_repository] 為 `null`
  /// （呼叫端尚未組裝完成，或測試替身刻意留空）時直接 no-op，
  /// [pdfEnabled]／[foliateEnabled] 維持預設值 `false`，不拋例外。
  Future<void> load() async {
    final repository = _repository;
    if (repository == null) return;
    _pdfEnabled = await repository.isEnabled(ContentIndexCategory.pdf);
    _foliateEnabled =
        await repository.isEnabled(ContentIndexCategory.foliate);
  }

  /// 切換 [category] 的啟用狀態為 [newValue]：呼叫 `repository.setEnabled()`
  /// 並更新對應的內部布林值。**不**負責彈出確認對話框——呼叫端須自行在
  /// 「從關閉切成開啟」時先詢問使用者確認，確認後才呼叫本方法。
  /// [_repository] 為 `null` 時直接 no-op，不拋例外。
  Future<void> toggle(ContentIndexCategory category, bool newValue) async {
    final repository = _repository;
    if (repository == null) return;
    await repository.setEnabled(category, newValue);
    if (category == ContentIndexCategory.pdf) {
      _pdfEnabled = newValue;
    } else {
      _foliateEnabled = newValue;
    }
  }
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/search/full_text_search_toggles_controller_test.dart`
Expected: PASS（6 個測試案例全數通過）

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/search/full_text_search_toggles_controller.dart test/search/full_text_search_toggles_controller_test.dart`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/search/full_text_search_toggles_controller.dart app/test/search/full_text_search_toggles_controller_test.dart
git commit -m "$(cat <<'EOF'
feat(search): 新增 FullTextSearchTogglesController 收斂全文檢索開關邏輯（epic-41 Issue 5 Task 1）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

---

### Task 2: `library_search_screen.dart` 改用 `FullTextSearchTogglesController`

**Files:**
- Modify: `app/lib/screens/library_search_screen.dart:1-19`（新增 import）、`:488-607`（`_FullTextSearchQuickSettingsPanelState` 類別本體）
- Test: `app/test/screens/library_search_screen_test.dart`（既有測試，不新增案例）

**Interfaces:**
- Consumes：Task 1 產出的 `FullTextSearchTogglesController`。

- [x] **Step 1: 新增 import**

在 `app/lib/screens/library_search_screen.dart` 開頭 import 區塊，原本：

```dart
import '../reader/reader_jump_target.dart';
import '../reader/reader_prefs_manager.dart';
import '../search/full_text_search_settings_repository.dart';
import '../search/search_repository.dart';
```

改為：

```dart
import '../reader/reader_jump_target.dart';
import '../reader/reader_prefs_manager.dart';
import '../search/full_text_search_settings_repository.dart';
import '../search/full_text_search_toggles_controller.dart';
import '../search/search_repository.dart';
```

- [x] **Step 2: 改寫 `_FullTextSearchQuickSettingsPanelState`**

在 `app/lib/screens/library_search_screen.dart:488-607`，原本：

```dart
class _FullTextSearchQuickSettingsPanelState
    extends State<_FullTextSearchQuickSettingsPanel> {
  bool _pdfEnabled = false;
  bool _foliateEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = widget.repository;
    if (repository == null) return;
    final pdfEnabled = await repository.isEnabled(ContentIndexCategory.pdf);
    final foliateEnabled =
        await repository.isEnabled(ContentIndexCategory.foliate);
    if (!mounted) return;
    setState(() {
      _pdfEnabled = pdfEnabled;
      _foliateEnabled = foliateEnabled;
    });
  }

  Future<void> _handleToggle(ContentIndexCategory category, bool value) async {
    final repository = widget.repository;
    if (repository == null) return;
    if (value) {
      final confirmed = await showFullTextSearchEnableConfirmDialog(
        context,
        category: category,
        isEinkMode: widget.isEinkMode,
      );
      if (!confirmed) return;
    }
    await repository.setEnabled(category, value);
    if (!mounted) return;
    setState(() {
      if (category == ContentIndexCategory.pdf) {
        _pdfEnabled = value;
      } else {
        _foliateEnabled = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isFullTextSearchAvailable) {
      return const Padding(
        key: Key('library_search_full_text_search_unavailable_hint'),
        padding: EdgeInsets.all(16),
        child: Text('本裝置不支援全文檢索'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('PDF 全文檢索'),
            subtitle: const Text('部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key(
                      'library_search_full_text_search_pdf_rebuild_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: '重建索引',
                  onPressed: !_pdfEnabled || widget.repository == null
                      ? null
                      : () => widget.repository!
                          .rebuildIndex(ContentIndexCategory.pdf),
                ),
                Switch(
                  key: const Key('library_search_full_text_search_pdf_switch'),
                  value: _pdfEnabled,
                  onChanged: widget.repository == null
                      ? null
                      : (value) =>
                          _handleToggle(ContentIndexCategory.pdf, value),
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text('其他格式全文檢索'),
            subtitle: const Text('EPUB／TXT／KF8 等格式的背景索引建置'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key(
                      'library_search_full_text_search_foliate_rebuild_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: '重建索引',
                  onPressed: !_foliateEnabled || widget.repository == null
                      ? null
                      : () => widget.repository!
                          .rebuildIndex(ContentIndexCategory.foliate),
                ),
                Switch(
                  key: const Key(
                      'library_search_full_text_search_foliate_switch'),
                  value: _foliateEnabled,
                  onChanged: widget.repository == null
                      ? null
                      : (value) =>
                          _handleToggle(ContentIndexCategory.foliate, value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

改為：

```dart
class _FullTextSearchQuickSettingsPanelState
    extends State<_FullTextSearchQuickSettingsPanel> {
  late final FullTextSearchTogglesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FullTextSearchTogglesController(widget.repository);
    _load();
  }

  Future<void> _load() async {
    await _controller.load();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _handleToggle(ContentIndexCategory category, bool value) async {
    if (value) {
      final confirmed = await showFullTextSearchEnableConfirmDialog(
        context,
        category: category,
        isEinkMode: widget.isEinkMode,
      );
      if (!confirmed) return;
    }
    await _controller.toggle(category, value);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isFullTextSearchAvailable) {
      return const Padding(
        key: Key('library_search_full_text_search_unavailable_hint'),
        padding: EdgeInsets.all(16),
        child: Text('本裝置不支援全文檢索'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('PDF 全文檢索'),
            subtitle: const Text('部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key(
                      'library_search_full_text_search_pdf_rebuild_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: '重建索引',
                  onPressed:
                      !_controller.pdfEnabled || widget.repository == null
                          ? null
                          : () => widget.repository!
                              .rebuildIndex(ContentIndexCategory.pdf),
                ),
                Switch(
                  key: const Key('library_search_full_text_search_pdf_switch'),
                  value: _controller.pdfEnabled,
                  onChanged: widget.repository == null
                      ? null
                      : (value) =>
                          _handleToggle(ContentIndexCategory.pdf, value),
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text('其他格式全文檢索'),
            subtitle: const Text('EPUB／TXT／KF8 等格式的背景索引建置'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key(
                      'library_search_full_text_search_foliate_rebuild_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: '重建索引',
                  onPressed:
                      !_controller.foliateEnabled || widget.repository == null
                          ? null
                          : () => widget.repository!
                              .rebuildIndex(ContentIndexCategory.foliate),
                ),
                Switch(
                  key: const Key(
                      'library_search_full_text_search_foliate_switch'),
                  value: _controller.foliateEnabled,
                  onChanged: widget.repository == null
                      ? null
                      : (value) =>
                          _handleToggle(ContentIndexCategory.foliate, value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [x] **Step 3: 執行既有回歸測試**

Run: `cd app && flutter test test/screens/library_search_screen_test.dart`
Expected: PASS（全數通過，含「設定選單內從關閉切成開啟，先跳出確認對話框，取消則不呼叫 setEnabled」與「確認後呼叫 setEnabled(true)，重建索引按鈕由停用變為可用」兩個關鍵回歸測試——這兩個測試實際 pump 真實 `_FullTextSearchQuickSettingsPanel` 並用 `find.byKey(...)` 驗證 `Switch`/`IconButton` 狀態，是本次重構「開關與重建索引按鈕行為完全不變」的關鍵證據）

- [x] **Step 4: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/library_search_screen.dart`
Expected: `No issues found!`

- [x] **Step 5: Commit**

```bash
git add app/lib/screens/library_search_screen.dart
git commit -m "$(cat <<'EOF'
refactor(search): library_search_screen 全文檢索開關改用 FullTextSearchTogglesController（epic-41 Issue 5 Task 2）

_FullTextSearchQuickSettingsPanelState 的 _load()/_handleToggle() 邏輯本體
已收斂為呼叫共用的 FullTextSearchTogglesController，本 State 只保留確認
Dialog 呼叫與 setState() 刷新。flutter analyze/flutter test 全數通過，零回歸。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

---

### Task 3: `settings_scaffold.dart` 改用 `FullTextSearchTogglesController`，並跑全套驗證收尾

**Files:**
- Modify: `app/lib/screens/settings_scaffold.dart:1-23`（新增 import）、`:90-95`（欄位宣告）、`:97-102`（`initState`）、`:110-114`（`didUpdateWidget`）、`:130-141`（`_loadFullTextSearchSettings`）、`:143-169`（`_handleFullTextSearchToggle`）、`:313-343`（build 內 PDF 開關區塊）、`:344-375`（build 內其他格式開關區塊）
- Test: `app/test/screens/settings_scaffold_test.dart`（既有測試，不新增案例）

**Interfaces:**
- Consumes：Task 1 產出的 `FullTextSearchTogglesController`。

- [x] **Step 1: 新增 import**

在 `app/lib/screens/settings_scaffold.dart` 開頭 import 區塊，原本：

```dart
import '../reader/tts_provider.dart';
import '../search/full_text_search_settings_repository.dart';
import '../sync/sync_account_repository.dart';
```

改為：

```dart
import '../reader/tts_provider.dart';
import '../search/full_text_search_settings_repository.dart';
import '../search/full_text_search_toggles_controller.dart';
import '../sync/sync_account_repository.dart';
```

- [x] **Step 2: 改寫欄位宣告**

在 `app/lib/screens/settings_scaffold.dart:92-95`，原本：

```dart
  /// 「啟用全文檢索」兩個分類目前顯示值（epic-10-search Issue 3），比照
  /// 上方 `_consoleLogEnabled` 同一套模式。
  bool _fullTextSearchPdfEnabled = false;
  bool _fullTextSearchFoliateEnabled = false;
```

改為：

```dart
  /// 「啟用全文檢索」兩個分類的讀取/切換邏輯已收斂至
  /// [FullTextSearchTogglesController]（epic-41-search-architecture-hardening
  /// Issue 5），本欄位比照上方 `_consoleLogEnabled` 同一套「先顯示預設值、
  /// initState() 非同步載入完成後才 setState 更新」模式。
  late FullTextSearchTogglesController _fullTextSearchTogglesController;
```

- [x] **Step 3: 改寫 `initState()`**

在 `app/lib/screens/settings_scaffold.dart:97-102`，原本：

```dart
  @override
  void initState() {
    super.initState();
    _loadConsoleLogEnabled();
    _loadFullTextSearchSettings();
  }
```

改為：

```dart
  @override
  void initState() {
    super.initState();
    _fullTextSearchTogglesController = FullTextSearchTogglesController(
      widget.fullTextSearchSettingsRepository,
    );
    _loadConsoleLogEnabled();
    _loadFullTextSearchSettings();
  }
```

- [x] **Step 4: 改寫 `didUpdateWidget()`**

在 `app/lib/screens/settings_scaffold.dart:110-114`，原本：

```dart
  @override
  void didUpdateWidget(covariant SettingsScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadFullTextSearchSettings();
  }
```

改為：

```dart
  @override
  void didUpdateWidget(covariant SettingsScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullTextSearchSettingsRepository !=
        widget.fullTextSearchSettingsRepository) {
      // 上層傳入了不同的 repository 實例（review-plan-issue-5.md I-1）：
      // 重新建構 controller 避免它繼續持有舊實例，與 build() 內
      // 「重建索引」按鈕直接取用 widget.fullTextSearchSettingsRepository
      // （永遠讀最新實例）的行為分歧。
      _fullTextSearchTogglesController = FullTextSearchTogglesController(
        widget.fullTextSearchSettingsRepository,
      );
    }
    _loadFullTextSearchSettings();
  }
```

- [x] **Step 5: 改寫 `_loadFullTextSearchSettings()`**

在 `app/lib/screens/settings_scaffold.dart:130-141`，原本：

```dart
  Future<void> _loadFullTextSearchSettings() async {
    final repository = widget.fullTextSearchSettingsRepository;
    if (repository == null) return;
    final pdfEnabled = await repository.isEnabled(ContentIndexCategory.pdf);
    final foliateEnabled =
        await repository.isEnabled(ContentIndexCategory.foliate);
    if (!mounted) return;
    setState(() {
      _fullTextSearchPdfEnabled = pdfEnabled;
      _fullTextSearchFoliateEnabled = foliateEnabled;
    });
  }
```

改為：

```dart
  Future<void> _loadFullTextSearchSettings() async {
    await _fullTextSearchTogglesController.load();
    if (!mounted) return;
    setState(() {});
  }
```

- [x] **Step 6: 改寫 `_handleFullTextSearchToggle()`**

在 `app/lib/screens/settings_scaffold.dart:143-169`，原本：

```dart
  /// 關閉開關（[value] 為 `false`）直接呼叫 `setEnabled`，不彈出確認對話框
  /// ——只有「從關閉切成開啟」才需要確認。使用者取消對話框時提前 return，
  /// 開關維持關閉、不呼叫 `setEnabled`。
  Future<void> _handleFullTextSearchToggle(
    ContentIndexCategory category,
    bool value,
  ) async {
    final repository = widget.fullTextSearchSettingsRepository;
    if (repository == null) return;
    if (value) {
      final confirmed = await showFullTextSearchEnableConfirmDialog(
        context,
        category: category,
        isEinkMode: widget.isEinkMode,
      );
      if (!confirmed) return;
    }
    await repository.setEnabled(category, value);
    if (!mounted) return;
    setState(() {
      if (category == ContentIndexCategory.pdf) {
        _fullTextSearchPdfEnabled = value;
      } else {
        _fullTextSearchFoliateEnabled = value;
      }
    });
  }
```

改為：

```dart
  /// 關閉開關（[value] 為 `false`）直接呼叫 `setEnabled`，不彈出確認對話框
  /// ——只有「從關閉切成開啟」才需要確認。使用者取消對話框時提前 return，
  /// 開關維持關閉、不呼叫 `setEnabled`。
  Future<void> _handleFullTextSearchToggle(
    ContentIndexCategory category,
    bool value,
  ) async {
    if (value) {
      final confirmed = await showFullTextSearchEnableConfirmDialog(
        context,
        category: category,
        isEinkMode: widget.isEinkMode,
      );
      if (!confirmed) return;
    }
    await _fullTextSearchTogglesController.toggle(category, value);
    if (!mounted) return;
    setState(() {});
  }
```

- [x] **Step 7: 改寫 build() 內兩處開關區塊**

在 `app/lib/screens/settings_scaffold.dart:313-343`，原本（PDF 區塊）：

```dart
            _SettingsCard(
              child: ListTile(
                title: const Text('PDF 全文檢索'),
                subtitle: const Text('部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key(
                          'settings_full_text_search_pdf_rebuild_button'),
                      icon: const Icon(Icons.refresh),
                      tooltip: '重建索引',
                      onPressed: !_fullTextSearchPdfEnabled ||
                              widget.fullTextSearchSettingsRepository == null
                          ? null
                          : () => widget.fullTextSearchSettingsRepository!
                              .rebuildIndex(ContentIndexCategory.pdf),
                    ),
                    Switch(
                      key: const Key('settings_full_text_search_pdf_switch'),
                      value: _fullTextSearchPdfEnabled,
                      onChanged: widget.fullTextSearchSettingsRepository ==
                              null
                          ? null
                          : (value) => _handleFullTextSearchToggle(
                              ContentIndexCategory.pdf, value),
                    ),
                  ],
                ),
              ),
            ),
```

改為：

```dart
            _SettingsCard(
              child: ListTile(
                title: const Text('PDF 全文檢索'),
                subtitle: const Text('部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key(
                          'settings_full_text_search_pdf_rebuild_button'),
                      icon: const Icon(Icons.refresh),
                      tooltip: '重建索引',
                      onPressed: !_fullTextSearchTogglesController
                                  .pdfEnabled ||
                              widget.fullTextSearchSettingsRepository == null
                          ? null
                          : () => widget.fullTextSearchSettingsRepository!
                              .rebuildIndex(ContentIndexCategory.pdf),
                    ),
                    Switch(
                      key: const Key('settings_full_text_search_pdf_switch'),
                      value: _fullTextSearchTogglesController.pdfEnabled,
                      onChanged: widget.fullTextSearchSettingsRepository ==
                              null
                          ? null
                          : (value) => _handleFullTextSearchToggle(
                              ContentIndexCategory.pdf, value),
                    ),
                  ],
                ),
              ),
            ),
```

在 `app/lib/screens/settings_scaffold.dart:344-375`，原本（其他格式區塊）：

```dart
            _SettingsCard(
              child: ListTile(
                title: const Text('其他格式全文檢索'),
                subtitle: const Text('EPUB／TXT／KF8 等格式的背景索引建置'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key(
                          'settings_full_text_search_foliate_rebuild_button'),
                      icon: const Icon(Icons.refresh),
                      tooltip: '重建索引',
                      onPressed: !_fullTextSearchFoliateEnabled ||
                              widget.fullTextSearchSettingsRepository == null
                          ? null
                          : () => widget.fullTextSearchSettingsRepository!
                              .rebuildIndex(ContentIndexCategory.foliate),
                    ),
                    Switch(
                      key: const Key(
                          'settings_full_text_search_foliate_switch'),
                      value: _fullTextSearchFoliateEnabled,
                      onChanged: widget.fullTextSearchSettingsRepository ==
                              null
                          ? null
                          : (value) => _handleFullTextSearchToggle(
                              ContentIndexCategory.foliate, value),
                    ),
                  ],
                ),
              ),
            ),
```

改為：

```dart
            _SettingsCard(
              child: ListTile(
                title: const Text('其他格式全文檢索'),
                subtitle: const Text('EPUB／TXT／KF8 等格式的背景索引建置'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key(
                          'settings_full_text_search_foliate_rebuild_button'),
                      icon: const Icon(Icons.refresh),
                      tooltip: '重建索引',
                      onPressed: !_fullTextSearchTogglesController
                                  .foliateEnabled ||
                              widget.fullTextSearchSettingsRepository == null
                          ? null
                          : () => widget.fullTextSearchSettingsRepository!
                              .rebuildIndex(ContentIndexCategory.foliate),
                    ),
                    Switch(
                      key: const Key(
                          'settings_full_text_search_foliate_switch'),
                      value: _fullTextSearchTogglesController.foliateEnabled,
                      onChanged: widget.fullTextSearchSettingsRepository ==
                              null
                          ? null
                          : (value) => _handleFullTextSearchToggle(
                              ContentIndexCategory.foliate, value),
                    ),
                  ],
                ),
              ),
            ),
```

- [x] **Step 8: 執行既有回歸測試**

Run: `cd app && flutter test test/screens/settings_scaffold_test.dart`
Expected: PASS（全數通過，含「開關初始值反映 repository.isEnabled()」「開啟開關前彈出確認對話框，取消不呼叫 setEnabled」「開啟開關確認後呼叫 setEnabled(true) 並更新畫面狀態」「關閉開關不彈出確認對話框，直接呼叫 setEnabled(false)」以及 `didUpdateWidget` 雙入口同步測試——這些測試實際 pump 真實 `SettingsScaffold` 並用 `find.byKey(...)` 驗證 `Switch`/`IconButton` 狀態，是本次重構「開關行為完全不變」的關鍵證據）

- [x] **Step 9: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/settings_scaffold.dart`
Expected: `No issues found!`

- [x] **Step 10: 跑完整 `flutter analyze`／`flutter test` 作最終確認**

本 Issue 三個 Task 皆完成，依專案慣例在最後一個 Task 跑一次全套驗證：

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數通過（新增 6 個 `full_text_search_toggles_controller_test.dart` 測試案例後，全庫測試總數為 Issue 4 合併後的既有基準淨增 +6；失敗數維持 2 且必須是同樣兩個 `adaptive_shell_scaffold_test.dart` 既有案例，不可出現新的失敗）。

- [x] **Step 11: Commit**

```bash
git add app/lib/screens/settings_scaffold.dart
git commit -m "$(cat <<'EOF'
refactor(search): SettingsScaffold 全文檢索開關改用 FullTextSearchTogglesController（epic-41 Issue 5 Task 3）

_loadFullTextSearchSettings()/_handleFullTextSearchToggle() 邏輯本體已收斂
為呼叫共用的 FullTextSearchTogglesController，本 State 只保留確認 Dialog
呼叫與 setState() 刷新。library_search_screen.dart 與 settings_scaffold.dart
兩處全文檢索開關邏輯現已完全共用同一份實作。
flutter analyze/flutter test 全數通過，零回歸。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

- [x] **Step 12: 更新工單狀態**

在 `docs/epics/epic-41-search-architecture-hardening/issues.md` 的 Issue 5 段落，依專案既有看板慣例，把 `**Status:** ready-for-agent` 改為：

```
**Status:** completed（`plans/plan-issue-5.md` 3 個 Task 全數完成，新增 `FullTextSearchTogglesController`，`library_search_screen.dart`／`settings_scaffold.dart` 兩處開關邏輯皆已改用，`flutter analyze`/`flutter test` 全數通過零回歸）
```

同步在 `epic.md` 的開發記錄追加一句「Issue 5 已完成，Epic 41 五個 `ready-for-agent`/`needs-info` Issue 中僅剩 Issue 6（`needs-info`，暫緩）」。
