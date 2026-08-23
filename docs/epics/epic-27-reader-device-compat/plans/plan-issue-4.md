# Epic 27 Issue 4：版面設定「另存為新預設集」點擊後彈窗不會出現 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 以逐 Task 執行本計畫。步驟採用 checkbox（`- [ ]`）語法追蹤進度。

**Goal:** 使用者於 Mobiscribe WARE 真機回報，點擊「另存為新預設集」按鈕後畫面完全沒有任何變化（含盲點按鈕周邊區域也沒有反應）。根因尚無法 100% 確認（`widget.layoutPresetRepository == null`，或真機 Release build 下某處拋出未預期例外皆有可能，見 `reviews/bugfix-repro.md` Issue 4），故本 Issue 刻意不臆測修復，改為把兩條原本會「靜默失敗」的路徑都改成使用者可見的提示，同時保留除錯資訊，讓使用者若再次遇到問題時能看到明確訊息、可判斷根因方向。

**Architecture:** 純 Dart／Flutter 端改動，僅 `app/lib/screens/reader_screen.dart` 一個檔案的 `_handleSaveAsPreset()` 方法。不新增型別、不新增介面、不影響其他呼叫路徑。修法：`repository == null` 分支補上 `SnackBar` 提示；整個方法本體（含 `showDialog`／repository 讀寫）包上 `try`/`catch`，攔截到的例外一律 `debugPrint` 記錄並顯示 `SnackBar`。

**Tech Stack:** Flutter／Dart。測試層級為 `flutter test`（widget test），沿用 `app/test/screens/reader_screen_test.dart` 既有的「版面設定預設集（epic-28-reader-settings-enhancements Issue 3）」`group`、既有 `pumpReaderScreen()` helper 與 `LayoutPresetRepository`／`sqflite_common_ffi` 記憶體內資料庫測試手法，不需要新增測試框架或套件依賴。

**Spec:** `docs/epics/epic-27-reader-device-compat/issues.md` Issue 4；診斷過程與程式碼證據見 `docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md`「Issue 4」段落。本 Epic 依先例跳過正式 `spec.md`（見 issues.md 開頭說明：全數為既有邏輯的行為修正，不涉及新增介面/型別、無架構異動）。

## 規劃階段查證：呼叫路徑、既有慣例、零回歸邊界（務必先讀）

1. **`_handleSaveAsPreset()` 現況（`reader_screen.dart:774-806`）**：`final repository = widget.layoutPresetRepository; if (repository == null) return;` 是目前唯一會讓整個流程靜默 `return`、不留任何痕跡的守門條件；其後 `showLayoutPresetNameDialog()`／`repository.insert()`／`_selectPresetToOverwrite()`／`_confirmOverwrite()`／`repository.replace()`／`_loadLayoutPresets()` 皆無任何例外攔截，任一處在真機環境拋出未預期例外，依 Flutter 框架行為（Release build 下 Gesture handler 內未捕捉例外由 `FlutterError.onError` 攔截但不顯示任何畫面）會呈現與使用者回報完全相符的「點下去毫無反應」症狀。
2. **本檔案已有的 SnackBar 慣例可直接沿用，不需要新建 helper。** 已查證 `app/lib/screens/remote_server_list_screen.dart:151-159`：`if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(key: Key('...'), content: Text('...')));`——本 Issue 沿用同一種「`ScaffoldMessenger.of(context).showSnackBar(SnackBar(key: ..., content: Text(...)))`」寫法與「錯誤訊息 SnackBar 帶專屬 `Key`」的既有慣例，不引入新的錯誤提示元件。`debugPrint` 本檔案亦已在 `_loadFxlBookmarks()`／`_loadCustomFonts()`／`_loadLayoutPresets()`（`reader_screen.dart:997-1036`）的既有 `catch` 分支使用，屬既有慣例，`package:flutter/material.dart` 已涵蓋此符號，不需新增 import。
3. **`repository == null` 分支目前完全沒有任何 `await`，`ScaffoldMessenger.of(context)` 呼叫當下 `context`／`mounted` 必然有效**，不需要額外的 `mounted` 判斷式（按鈕點擊是同步 UI 事件，尚未經過任何非同步邊界）；`try`/`catch` 內的 `catch` 分支則在 `await` 之後才可能執行到，故沿用既有 `_loadLayoutPresets()` 等方法的既有慣例，在使用 `context` 前先判斷 `if (!mounted) return;`。
4. **既有 `pumpReaderScreen()` test helper（`reader_screen_test.dart:6677-6709`）目前無條件傳入 `layoutPresetRepository: layoutPresetRepository`**，本 Issue 需要新增兩則測試分別模擬「未傳入 `layoutPresetRepository`」與「傳入一個會拋出例外的假 repository」，故需要為這個 helper 新增兩個具預設值的具名參數（`includeLayoutPresetRepository`／`layoutPresetRepositoryOverride`），現有全部呼叫點（`pumpReaderScreen(tester)`，無額外參數）維持逐位元組相同的行為，零回歸。
5. **`LayoutPresetRepository`（`app/lib/reader/layout_preset_repository.dart:23`）是一般 class（非 `final class`／`sealed class`），可安全被測試繼承、覆寫單一方法製造「模擬 insert 失敗」的假 repository**，不需要引入 mock 套件；其建構子 `const LayoutPresetRepository(this._db)` 只是儲存 `Database` 供 `listAll()`/`insert()`/`replace()`/`delete()` 底層 SQL 呼叫使用，測試中傳入既有 `libraryRepository.database`（真實記憶體內 SQLite 連線）即可，`listAll()` 不覆寫、正常運作（回傳 `[]`，因為每個測試都是全新的記憶體內資料庫、預設沒有任何 `layout_preset` 資料列），只有 `insert()` 被覆寫成拋出例外——`_loadLayoutPresets()`（`initState` 時機呼叫，`reader_screen.dart:377`）因此不受影響，能正常完成、`_layoutPresets` 維持 `[]`，測試點擊「另存為新預設集」時會因 `_layoutPresets.length < 3` 進入 `insert()` 分支而觸發例外，符合本 Issue 要驗證的路徑。
6. **零回歸邊界：本 Issue 只改 `_handleSaveAsPreset()` 一個方法的例外處理層，不改動任何既有成功路徑的邏輯**（`showLayoutPresetNameDialog`／`insert`／`_selectPresetToOverwrite`／`_confirmOverwrite`／`replace`／`_loadLayoutPresets` 的呼叫順序與參數完全不動，只是外層多包一層 `try`/`catch`）。既有 6 則同 `group` 測試（「另存為新預設集：命名對話框輸入名稱後...」「存滿 3 組後再次另存...」「套用預設集到目前書籍」「套用預設集到其他書籍（多本）」「刪除預設集：正確從 LayoutPresetRepository 移除」「刪除預設集：確認對話框取消時不刪除」「複製其他書籍設定到本書...」）皆走成功路徑、不觸發新增的 `catch` 分支，斷言不需要任何修改。

## Global Constraints

- 程式碼註解使用中文，遵循既有檔案風格（`reader_screen.dart` 既有 `///`／`//` 註解慣例）。
- 本 Issue 刻意採取「提高可觀測性＋防禦性」而非直接臆測修復（issues.md 原文），不得在缺乏真機 log 佐證的情況下假設 `repository == null` 就是唯一根因並只修這一種情況——`try`/`catch` 覆蓋整個方法本體是必要範圍，不可只做 `repository == null` 分支的提示。
- 錯誤提示一律使用 `ScaffoldMessenger.of(context).showSnackBar(...)`，比照 `remote_server_list_screen.dart:151-159` 既有慣例，`SnackBar` 一律帶專屬 `Key`。
- 例外訊息須同時 `debugPrint`（供未來若再次回報時，開發者可從真機 log 直接判斷根因，不必再靠臆測）。
- 既有 `_handleSaveAsPreset()` 成功路徑的呼叫順序、參數、`_loadLayoutPresets()` 收尾呼叫皆不得變動。
- `flutter analyze` 必須乾淨（"No issues found!"）；`flutter test` 全數通過、零回歸。
- Commit message 慣例：`fix(epic-27): Issue 4——<描述>`（比照本 Epic 既有 commit 歷史，例如 `fix(epic-27): Issue 3——_buildBody() 於原生視圖上方新增 loading 專用遮罩層，蓋住首幀黑屏`）。

---

### Task 1：`_handleSaveAsPreset()` 靜默失敗防禦強化（TDD）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:771-806`
- Modify: `app/test/screens/reader_screen_test.dart`（新增私有假 repository class、擴充 `pumpReaderScreen()` helper、新增 2 則 widget test）

**Interfaces:**
- Produces：`_handleSaveAsPreset()` 對外行為（透過 UI 觀察）——`widget.layoutPresetRepository == null` 時顯示 `Key('reader_save_as_preset_repository_unavailable_snackbar')` 的 `SnackBar`；方法本體任何一步拋出例外時顯示 `Key('reader_save_as_preset_error_snackbar')` 的 `SnackBar`。方法簽章 `Future<void> _handleSaveAsPreset(BookReaderPrefs currentDraft)` 不變。

- [ ] **Step 1：寫失敗測試 1——`layoutPresetRepository` 為 `null` 時顯示提示**

修改 `app/test/screens/reader_screen_test.dart`，原本（`pumpReaderScreen` 定義，約 6677-6709 行）：

```dart
    Future<void> pumpReaderScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: false,
            libraryRepository: libraryRepository,
            layoutPresetRepository: layoutPresetRepository,
            bookReaderPrefsRepository: bookReaderPrefsRepository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      final foliateView =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
      );
      await tester.pump();
    }
```

改為：

```dart
    Future<void> pumpReaderScreen(
      WidgetTester tester, {
      // epic-27-reader-device-compat Issue 4：讓「另存為新預設集」的兩則
      // 新測試可以分別模擬 layoutPresetRepository 為 null、或注入一個會
      // 拋出例外的假 repository；其餘既有呼叫點沿用預設值，行為不變。
      bool includeLayoutPresetRepository = true,
      LayoutPresetRepository? layoutPresetRepositoryOverride,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final effectiveLayoutPresetRepository = layoutPresetRepositoryOverride ??
          (includeLayoutPresetRepository ? layoutPresetRepository : null);

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: false,
            libraryRepository: libraryRepository,
            layoutPresetRepository: effectiveLayoutPresetRepository,
            bookReaderPrefsRepository: bookReaderPrefsRepository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      final foliateView =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
      );
      await tester.pump();
    }
```

緊接著在「存滿 3 組後再次另存，跳出覆蓋選單，選擇並確認後正確覆蓋既有一組」測試（該測試以 `});` 結束，約第 6783 行）之後、「套用預設集到目前書籍」測試之前，新增：

```dart
    testWidgets(
        '另存為新預設集：layoutPresetRepository 為 null 時顯示提示，而非毫無反應',
        (tester) async {
      await pumpReaderScreen(tester, includeLayoutPresetRepository: false);

      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '設定喜好');
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_save_as_preset')));
      await tester
          .tap(find.byKey(const Key('reader_settings_save_as_preset')));
      await tester.pump();

      expect(
        find.byKey(
            const Key('reader_save_as_preset_repository_unavailable_snackbar')),
        findsOneWidget,
      );
      expect(find.text('暫時無法儲存預設集'), findsOneWidget);
      // 命名對話框不應該被誤開——確認「靜默失敗」已被提示取代，而不是
      // 多開出一個對話框（兩者都算「有反應」，但語意不同，須分開鑑別）。
      expect(
        find.byKey(const Key('layout_preset_name_dialog_field')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/screens/reader_screen_test.dart --plain-name "layoutPresetRepository 為 null 時顯示提示"`
預期：`expect(find.byKey(const Key('reader_save_as_preset_repository_unavailable_snackbar')), findsOneWidget)` 斷言失敗（`findsNothing`，因為 `_handleSaveAsPreset()` 目前只是靜默 `return`，沒有顯示任何 `SnackBar`）。

- [ ] **Step 3（階段一）：只實作 `repository == null` 分支的提示，暫不包 `try`/`catch`**

〔`reviews/review-plan-issue-4.md` Important #1 修正〕若本步驟一併把 `try`/`catch` 也寫進去，Step 5 新增的例外測試在 Step 6 就不會是紅燈（例外會直接被還沒該出現的 `catch` 接住），TDD 的紅燈驗證會失效。本步驟因此**只**改 `repository == null` 分支，方法其餘部分（含成功路徑）原樣保留，`try`/`catch` 留到階段二（Step 7）才加。

修改 `app/lib/screens/reader_screen.dart`，原本（`:771-806`）：

```dart
  /// 版面設定預設集「另存為新預設集」（epic-28-reader-settings-
  /// enhancements Issue 3）：命名輸入 → 未滿 3 組直接 insert，已滿 3 組
  /// 跳出覆蓋選單 → 覆蓋前二次確認 → replace，完成後重新載入清單。
  Future<void> _handleSaveAsPreset(BookReaderPrefs currentDraft) async {
    final repository = widget.layoutPresetRepository;
    if (repository == null) return;
    final name = await showLayoutPresetNameDialog(context);
    if (name == null || !mounted) return;
    final filteredPrefs = currentDraft.reflowableEpubFields();
    final now = DateTime.now();
    if (_layoutPresets.length < 3) {
      await repository.insert(LayoutPreset(
        id: null,
        name: name,
        createdAt: now,
        updatedAt: now,
        prefs: filteredPrefs,
      ));
    } else {
      final target = await _selectPresetToOverwrite();
      if (target == null || !mounted) return;
      final confirmed = await _confirmOverwrite(target.name);
      if (!confirmed) return;
      await repository.replace(
        target.id!,
        LayoutPreset(
          id: target.id,
          name: name,
          createdAt: target.createdAt,
          updatedAt: now,
          prefs: filteredPrefs,
        ),
      );
    }
    await _loadLayoutPresets();
  }
```

改為：

```dart
  /// 版面設定預設集「另存為新預設集」（epic-28-reader-settings-
  /// enhancements Issue 3）：命名輸入 → 未滿 3 組直接 insert，已滿 3 組
  /// 跳出覆蓋選單 → 覆蓋前二次確認 → replace，完成後重新載入清單。
  ///
  /// epic-27-reader-device-compat Issue 4（階段一）：真機回報點擊後畫面
  /// 完全無反應（`reviews/bugfix-repro.md` Issue 4），`repository == null`
  /// 是目前唯一已知會讓流程靜默 return 的路徑，本階段先補上使用者可見
  /// 提示；方法本體其餘部分是否需要例外攔截見階段二（`plans/plan-issue-4.md`
  /// Step 7）。
  Future<void> _handleSaveAsPreset(BookReaderPrefs currentDraft) async {
    final repository = widget.layoutPresetRepository;
    if (repository == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('reader_save_as_preset_repository_unavailable_snackbar'),
          content: Text('暫時無法儲存預設集'),
        ),
      );
      return;
    }
    final name = await showLayoutPresetNameDialog(context);
    if (name == null || !mounted) return;
    final filteredPrefs = currentDraft.reflowableEpubFields();
    final now = DateTime.now();
    if (_layoutPresets.length < 3) {
      await repository.insert(LayoutPreset(
        id: null,
        name: name,
        createdAt: now,
        updatedAt: now,
        prefs: filteredPrefs,
      ));
    } else {
      final target = await _selectPresetToOverwrite();
      if (target == null || !mounted) return;
      final confirmed = await _confirmOverwrite(target.name);
      if (!confirmed) return;
      await repository.replace(
        target.id!,
        LayoutPreset(
          id: target.id,
          name: name,
          createdAt: target.createdAt,
          updatedAt: now,
          prefs: filteredPrefs,
        ),
      );
    }
    await _loadLayoutPresets();
  }
```

- [ ] **Step 4：執行測試確認 Step 1 新增案例通過**

執行：`cd app && flutter test test/screens/reader_screen_test.dart --plain-name "layoutPresetRepository 為 null 時顯示提示"`
預期：`All tests passed!`

- [ ] **Step 5：寫失敗測試 2——方法本體拋出例外時顯示提示**

修改 `app/test/screens/reader_screen_test.dart`，在 `void main() {`（第 68 行）之前新增：

```dart
// epic-27-reader-device-compat Issue 4：模擬 LayoutPresetRepository.insert()
// 在真機環境拋出未預期例外的情境（見 reviews/bugfix-repro.md Issue 4
// 「未能透過程式碼靜態確認、但無法排除的可能」）。LayoutPresetRepository
// 是一般 class（非 final/sealed），可安全繼承並只覆寫 insert()；listAll()
// 不覆寫、沿用真實記憶體內 SQLite 連線正常運作，確保 ReaderScreen
// initState() 時機的 _loadLayoutPresets() 不受影響（見
// docs/epics/epic-27-reader-device-compat/plans/plan-issue-4.md
// 規劃階段查證第 5 點）。
class _ThrowingLayoutPresetRepository extends LayoutPresetRepository {
  _ThrowingLayoutPresetRepository(super.db);

  @override
  Future<void> insert(LayoutPreset preset) async {
    throw Exception('模擬 insert 失敗（測試用）');
  }
}

```

並在 Step 1 新增的「`layoutPresetRepository` 為 `null` 時顯示提示」測試之後，新增：

```dart
    testWidgets(
        '另存為新預設集：寫入過程拋出例外時顯示提示，不被靜默吞掉',
        (tester) async {
      final throwingRepository =
          _ThrowingLayoutPresetRepository(libraryRepository.database);
      await pumpReaderScreen(
        tester,
        layoutPresetRepositoryOverride: throwingRepository,
      );

      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '設定喜好');
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_save_as_preset')));
      await tester
          .tap(find.byKey(const Key('reader_settings_save_as_preset')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('layout_preset_name_dialog_field')), '測試預設集');
      await tester
          .tap(find.byKey(const Key('layout_preset_name_dialog_confirm')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reader_save_as_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
```

- [ ] **Step 6：執行測試確認失敗**

執行：`cd app && flutter test test/screens/reader_screen_test.dart --plain-name "寫入過程拋出例外時顯示提示"`
預期：測試失敗——`_ThrowingLayoutPresetRepository.insert()` 拋出的例外目前未被 `_handleSaveAsPreset()` 攔截，會在 `onSaveAsPreset` 的 `await _handleSaveAsPreset(draft)` 處成為未捕捉的非同步例外，於 `pumpAndSettle()`／`tester.takeException()` 處被測試框架偵測到並使測試失敗（實際錯誤訊息可能是測試逾時或例外堆疊輸出，非固定字串，但結果必為失敗，非 `findsOneWidget` 的斷言通過）。

- [ ] **Step 7（階段二）：方法本體其餘部分包上 `try`/`catch`**

修改 `app/lib/screens/reader_screen.dart`，原本（Step 3 階段一改完後的版本）：

```dart
  /// 版面設定預設集「另存為新預設集」（epic-28-reader-settings-
  /// enhancements Issue 3）：命名輸入 → 未滿 3 組直接 insert，已滿 3 組
  /// 跳出覆蓋選單 → 覆蓋前二次確認 → replace，完成後重新載入清單。
  ///
  /// epic-27-reader-device-compat Issue 4（階段一）：真機回報點擊後畫面
  /// 完全無反應（`reviews/bugfix-repro.md` Issue 4），`repository == null`
  /// 是目前唯一已知會讓流程靜默 return 的路徑，本階段先補上使用者可見
  /// 提示；方法本體其餘部分是否需要例外攔截見階段二（`plans/plan-issue-4.md`
  /// Step 7）。
  Future<void> _handleSaveAsPreset(BookReaderPrefs currentDraft) async {
    final repository = widget.layoutPresetRepository;
    if (repository == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('reader_save_as_preset_repository_unavailable_snackbar'),
          content: Text('暫時無法儲存預設集'),
        ),
      );
      return;
    }
    final name = await showLayoutPresetNameDialog(context);
    if (name == null || !mounted) return;
    final filteredPrefs = currentDraft.reflowableEpubFields();
    final now = DateTime.now();
    if (_layoutPresets.length < 3) {
      await repository.insert(LayoutPreset(
        id: null,
        name: name,
        createdAt: now,
        updatedAt: now,
        prefs: filteredPrefs,
      ));
    } else {
      final target = await _selectPresetToOverwrite();
      if (target == null || !mounted) return;
      final confirmed = await _confirmOverwrite(target.name);
      if (!confirmed) return;
      await repository.replace(
        target.id!,
        LayoutPreset(
          id: target.id,
          name: name,
          createdAt: target.createdAt,
          updatedAt: now,
          prefs: filteredPrefs,
        ),
      );
    }
    await _loadLayoutPresets();
  }
```

改為：

```dart
  /// 版面設定預設集「另存為新預設集」（epic-28-reader-settings-
  /// enhancements Issue 3）：命名輸入 → 未滿 3 組直接 insert，已滿 3 組
  /// 跳出覆蓋選單 → 覆蓋前二次確認 → replace，完成後重新載入清單。
  ///
  /// epic-27-reader-device-compat Issue 4：真機回報點擊後畫面完全無反應
  /// （`reviews/bugfix-repro.md` Issue 4），根因無法 100% 確認（可能是
  /// `repository == null`〔階段一〕，也可能是真機環境某處拋出未預期例外
  /// 〔階段二〕），故本次採「提高可觀測性＋防禦性」而非直接臆測修復——
  /// 把兩種原本會靜默失敗的路徑都改成使用者可見的 SnackBar 提示，並保留
  /// debugPrint 供日後若再次收到回報時排查根因。
  Future<void> _handleSaveAsPreset(BookReaderPrefs currentDraft) async {
    final repository = widget.layoutPresetRepository;
    if (repository == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('reader_save_as_preset_repository_unavailable_snackbar'),
          content: Text('暫時無法儲存預設集'),
        ),
      );
      return;
    }
    try {
      final name = await showLayoutPresetNameDialog(context);
      if (name == null || !mounted) return;
      final filteredPrefs = currentDraft.reflowableEpubFields();
      final now = DateTime.now();
      if (_layoutPresets.length < 3) {
        await repository.insert(LayoutPreset(
          id: null,
          name: name,
          createdAt: now,
          updatedAt: now,
          prefs: filteredPrefs,
        ));
      } else {
        final target = await _selectPresetToOverwrite();
        if (target == null || !mounted) return;
        final confirmed = await _confirmOverwrite(target.name);
        if (!confirmed) return;
        await repository.replace(
          target.id!,
          LayoutPreset(
            id: target.id,
            name: name,
            createdAt: target.createdAt,
            updatedAt: now,
            prefs: filteredPrefs,
          ),
        );
      }
      await _loadLayoutPresets();
    } catch (e, stackTrace) {
      debugPrint('另存為新預設集失敗：$e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_save_as_preset_error_snackbar'),
          content: Text('另存為新預設集失敗：$e'),
        ),
      );
    }
  }
```

- [ ] **Step 8：執行測試確認 Step 5 新增案例通過**

執行：`cd app && flutter test test/screens/reader_screen_test.dart --plain-name "寫入過程拋出例外時顯示提示"`
預期：`All tests passed!`

- [ ] **Step 9：執行整個測試檔案，確認零回歸**

執行：`cd app && flutter test test/screens/reader_screen_test.dart`
預期：全數通過，含「版面設定預設集（epic-28-reader-settings-enhancements Issue 3）」`group` 內既有 7 則測試（「另存為新預設集：命名對話框輸入名稱後...」「存滿 3 組後再次另存...」「套用預設集到目前書籍...」「套用預設集到其他書籍（多本）...」「刪除預設集：正確從 LayoutPresetRepository 移除」「刪除預設集：確認對話框取消時不刪除」「複製其他書籍設定到本書...」）與本 Task 新增 2 則測試皆通過，其餘檔案內既有測試不受影響。

- [ ] **Step 10：執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數通過，測試總數較目前 main 分支基準（epic-27 Issue 5-8 合併後，見 `issues.md` Issue 5 段落記載為 1647 項）多 2 項（Step 1、Step 5 新增的 2 則測試），無既有測試失敗或被跳過。

- [ ] **Step 11：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-27): Issue 4——_handleSaveAsPreset() 補上 repository 為 null 與例外攔截的使用者可見提示"
```

---

## 完成後的驗證（對照 `issues.md` Issue 4 驗收標準）

- [ ] `flutter analyze`：全專案 "No issues found!"
- [ ] `flutter test`：全專案通過，零回歸
- [ ] `layoutPresetRepository == null` 時，點擊「另存為新預設集」顯示 `Key('reader_save_as_preset_repository_unavailable_snackbar')` 的 `SnackBar`（文字「暫時無法儲存預設集」），不再毫無反應。
- [ ] `_handleSaveAsPreset()` 方法本體任一步拋出例外時，顯示 `Key('reader_save_as_preset_error_snackbar')` 的 `SnackBar`（含例外訊息），並透過 `debugPrint` 記錄完整例外與堆疊，不再被靜默吞掉。
- [ ] 既有「另存為新預設集」成功路徑（命名輸入、存滿 3 組覆蓋選單、套用、刪除、複製）行為與斷言完全不變。
- [ ]（建議，非本計畫強制自動化）若使用者於真機再次遇到本問題，應能看到明確的錯誤/提示訊息而非毫無反應——據此可判斷是 `repository == null`（需再往上追查建構時序，另立新工單）或其他例外原因（`debugPrint` 訊息可直接提供根因線索），屬於 `issues.md` Issue 4 驗收標準的真機驗證部分，非 `flutter test` 範圍。
