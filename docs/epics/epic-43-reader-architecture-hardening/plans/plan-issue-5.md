# Epic 43 Issue 5 — Layout Preset Error Handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 補齊 `ReaderScreen` 版面設定預設集「套用／套用來源書籍／刪除」三個操作失敗時的錯誤處理一致性——目前三者失敗時皆靜默無提示（例外被吞掉），比照既有 `_handleSaveAsPreset` 的 try/catch + SnackBar 模式補齊。

**Architecture:** `_applyPrefsToTargets`（Epic 43 Issue 2 收斂出的共用核心）包一層 try/catch，涵蓋確認對話框之後的寫入與刷新；`_handleApplyFromBook` 需要**自己獨立的一層 try/catch**，包住呼叫 `_applyPrefsToTargets` **之前**的 `repository.load(sourceBookId)`（這段不在 `_applyPrefsToTargets` 的保護範圍內）；`_handleDeletePreset` 包一層 try/catch。三者皆在 catch 內先 `if (!mounted) return;` 才顯示 SnackBar，訊息格式比照既有 `另存為新預設集失敗：$e` 風格。純屬補防禦，不改變任何成功路徑的既有行為。

**Tech Stack:** Flutter/Dart 3.11，`flutter_test`，`sqflite_common_ffi`（測試沿用 `test/screens/reader_screen_test.dart` 既有「版面設定預設集」測試群組的 in-memory SQLite 基礎設施）。

**Spec:** `docs/epics/epic-43-reader-architecture-hardening/issues.md` Issue 5（`/grilling` 候選 2 Q5 定案；I-2 審查修訂：`_handleApplyFromBook` 需要自己獨立的 try/catch，不能只靠 `_applyPrefsToTargets` 內部處理）。

## Global Constraints

- 所有指令在 `app/` 目錄下執行（**含 `git add`／`git commit`**——各 Task 的 Commit 步驟路徑一律寫成相對 `app/` 的路徑，例如 `git add lib/screens/reader_screen.dart`，不要再加一層 `app/` 前綴）。
- 三個 try/catch 的範圍精確依 `issues.md` 定案，不可混淆：
  - `_applyPrefsToTargets`：一層 try/catch 涵蓋「判斷是否套用到目前書籍 → 視情況跳確認 → 寫入 → 刷新」整段（guard `if (repository == null || targetBookIds.isEmpty) return;` 在 try 區塊**外**，維持原樣不變——這個 guard 本身不是例外情境，不需要被 catch）。`_handleApplyPreset` 透過呼叫 `_applyPrefsToTargets` 即已自動涵蓋，不需要另外包一層。
  - `_handleApplyFromBook`：**自己獨立的一層 try/catch**，包住 `await repository.load(sourceBookId)` 與後續 `await _applyPrefsToTargets(sourcePrefs, targetBookIds)` 兩步（guard 同樣在 try 區塊外）。這一層與 `_applyPrefsToTargets` 內部的 try/catch 是**兩層獨立保護**——`_applyPrefsToTargets` 內部再拋出的例外會被它自己的 catch 接住、顯示一次 SnackBar 後正常 return，不會向上傳播讓 `_handleApplyFromBook` 的 catch 又跳一次（不會重複顯示兩次 SnackBar）。
  - `_handleDeletePreset`：一層 try/catch 包住 `layout_preset_actions.deleteLayoutPreset(...)` 呼叫與後續 `setState`（`repository == null` guard、confirm 對話框皆在 try 區塊外，維持原樣）。
- catch 區塊顯示 SnackBar **前**一律先 `if (!mounted) return;`（避免 `use_build_context_synchronously` analyzer 警告，比照既有 `_handleSaveAsPreset` 慣例），並保留 `debugPrint('...失敗：$e\n$stackTrace');` 診斷輸出。
- 三個新 SnackBar 訊息格式與既有 `另存為新預設集失敗：$e` 風格一致：套用/套用來源書籍共用 `Key('reader_apply_preset_error_snackbar')`、文字 `套用版面設定失敗：$e`；刪除用 `Key('reader_delete_preset_error_snackbar')`、文字 `刪除預設集失敗：$e`。
- **不新增** `repository == null` 情境的提示——維持現狀不變，本 Issue 只補「repository 存在但操作拋例外」這條路徑，`repository == null` 是另一個既有落差，不在本 Issue 範圍。
- 每個 Task 的 TDD 步驟只跑本次異動觸及的測試檔（`test/screens/reader_screen_test.dart`）；完整 `flutter test` 只在最後一個 Task（Task 4）執行一次。

---

### Task 1: `_applyPrefsToTargets` 補上 try/catch + SnackBar

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1103-1125`（`_applyPrefsToTargets`）
- Modify: `app/test/screens/reader_screen_test.dart:91-98`（新增 `_ThrowingBookReaderPrefsRepository` 測試替身，緊接在既有 `_ThrowingLayoutPresetRepository` 後）、`:7982-8014`（`pumpReaderScreen` helper 新增 `bookReaderPrefsRepositoryOverride` 參數）

**Interfaces:**
- Consumes: `layout_preset_actions.applyLayoutPresetPrefs`／`layoutPresetTargetsCurrentBookOnly`（Epic 43 Issue 2，已存在）。
- Produces: `_applyPrefsToTargets` 失敗時顯示 `Key('reader_apply_preset_error_snackbar')` 的 SnackBar；測試替身 `_ThrowingBookReaderPrefsRepository`（覆寫 `load`/`save`/`saveMultiple` 皆拋例外，供本 Task 與 Task 2 共用）；`pumpReaderScreen(..., bookReaderPrefsRepositoryOverride: ...)`。

- [x] **Step 1: 執行既有測試建立基準線**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（記錄目前全數通過，作為本 Task 修改後的零回歸基準）

- [x] **Step 2: 新增測試替身與 `pumpReaderScreen` 參數**

找到現有的 `_ThrowingLayoutPresetRepository`（約第 91-98 行）：

```dart
class _ThrowingLayoutPresetRepository extends LayoutPresetRepository {
  _ThrowingLayoutPresetRepository(super.db);

  @override
  Future<void> insert(LayoutPreset preset) async {
    throw Exception('模擬 insert 失敗（測試用）');
  }
}
```

其後新增：

```dart

// Epic 43 Issue 5：模擬 BookReaderPrefsRepository.load()/save()/
// saveMultiple() 拋出未預期例外的情境，比照上方 _ThrowingLayoutPreset-
// Repository 手法——單一「全部拋例外」的測試替身供「套用預設集」
// （Task 1，觸發 save/saveMultiple）與「套用來源書籍」（Task 2，觸發
// load）兩則測試共用。
class _ThrowingBookReaderPrefsRepository extends BookReaderPrefsRepository {
  _ThrowingBookReaderPrefsRepository(super.db);

  @override
  Future<BookReaderPrefs> load(String bookId) async {
    throw Exception('模擬 load 失敗（測試用）');
  }

  @override
  Future<void> save(String bookId, BookReaderPrefs prefs) async {
    throw Exception('模擬 save 失敗（測試用）');
  }

  @override
  Future<void> saveMultiple(
    List<String> bookIds,
    BookReaderPrefs prefs,
  ) async {
    throw Exception('模擬 saveMultiple 失敗（測試用）');
  }
}
```

找到現有的 `pumpReaderScreen` helper（約第 7982-8014 行）：

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

      final effectiveLayoutPresetRepository =
          layoutPresetRepositoryOverride ??
          (includeLayoutPresetRepository ? layoutPresetRepository : null);

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
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
      // Epic 43 Issue 5：讓「套用預設集」/「套用來源書籍」的失敗路徑測試
      // 可以注入一個會拋出例外的假 BookReaderPrefsRepository；其餘既有
      // 呼叫點沿用預設值，行為不變。
      BookReaderPrefsRepository? bookReaderPrefsRepositoryOverride,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final effectiveLayoutPresetRepository =
          layoutPresetRepositoryOverride ??
          (includeLayoutPresetRepository ? layoutPresetRepository : null);

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: false,
            libraryRepository: libraryRepository,
            layoutPresetRepository: effectiveLayoutPresetRepository,
            bookReaderPrefsRepository:
                bookReaderPrefsRepositoryOverride ?? bookReaderPrefsRepository,
          ),
        ),
      );
```

- [x] **Step 3: 寫入失敗測試**

在既有「套用預設集到目前書籍：立即寫入且畫面即時反映新值」測試（約第 8187 行）後新增：

```dart
    // M-2（審查修訂）：只用「套用到目前書籍」（save() 拋例外）驗證，不另外
    // 補一則「套用到其他書籍」（saveMultiple() 拋例外）——兩條路徑在
    // _applyPrefsToTargets 內部共用同一個 try/catch 區塊，save/saveMultiple
    // 各自的分支邏輯本身已由 Issue 2 的 layout_preset_actions_test.dart
    // 獨立驗證過，此處只需要證明「這一個 catch 區塊」有效即可，不需要
    // 為同一段 catch 邏輯重複測兩次。
    testWidgets('套用預設集到目前書籍：寫入過程拋出例外時顯示提示，不被靜默吞掉', (
      tester,
    ) async {
      await tester.runAsync(
        () => layoutPresetRepository.insert(
          LayoutPreset(
            id: null,
            name: '測試預設集',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            prefs: const BookReaderPrefs(fontSize: 24 / 16),
          ),
        ),
      );
      final throwingBookReaderPrefsRepository =
          _ThrowingBookReaderPrefsRepository(libraryRepository.database);
      await pumpReaderScreen(
        tester,
        bookReaderPrefsRepositoryOverride: throwingBookReaderPrefsRepository,
      );

      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_current')),
      );
      await tester.tap(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_current')),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reader_apply_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
```

- [x] **Step 4: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "預設集"`（M-4 審查修訂：只跑版面設定預設集群組即可看到新測試失敗，不需要跑全檔）
Expected: FAIL（`tester.takeException()` 回傳非 null 的未捕捉例外，而非單純找不到 SnackBar——`_applyPrefsToTargets` 目前完全沒有 try/catch 保護，`repository.save()` 拋出的例外會是未捕捉例外，與 Task 2/3 的情況本質相同；M-1 審查修訂：先前誤以為是「被靜默吞掉」的語意，實際在測試環境下三者皆是未捕捉例外，只是在真機/生產環境的 UI 互動下使用者看不到任何提示才是「看似被吞掉」）

- [x] **Step 5: 改寫 `_applyPrefsToTargets`**

找到現有方法（約第 1103-1125 行）：

```dart
  Future<void> _applyPrefsToTargets(
    BookReaderPrefs prefs,
    List<String> targetBookIds,
  ) async {
    final repository = widget.bookReaderPrefsRepository;
    if (repository == null || targetBookIds.isEmpty) return;
    if (!layout_preset_actions.layoutPresetTargetsCurrentBookOnly(
      targetBookIds,
      widget.bookId,
    )) {
      final confirmed = await _confirmApplyToOtherBooks(targetBookIds.length);
      if (!confirmed || !mounted) return;
    }
    await layout_preset_actions.applyLayoutPresetPrefs(
      repository,
      prefs: prefs,
      targetBookIds: targetBookIds,
    );
    if (!mounted) return;
    if (targetBookIds.contains(widget.bookId)) {
      _handlePrefsChanged(prefs);
    }
  }
```

改為：

```dart
  Future<void> _applyPrefsToTargets(
    BookReaderPrefs prefs,
    List<String> targetBookIds,
  ) async {
    final repository = widget.bookReaderPrefsRepository;
    if (repository == null || targetBookIds.isEmpty) return;
    try {
      if (!layout_preset_actions.layoutPresetTargetsCurrentBookOnly(
        targetBookIds,
        widget.bookId,
      )) {
        final confirmed =
            await _confirmApplyToOtherBooks(targetBookIds.length);
        if (!confirmed || !mounted) return;
      }
      await layout_preset_actions.applyLayoutPresetPrefs(
        repository,
        prefs: prefs,
        targetBookIds: targetBookIds,
      );
      if (!mounted) return;
      if (targetBookIds.contains(widget.bookId)) {
        _handlePrefsChanged(prefs);
      }
    } catch (e, stackTrace) {
      // Epic 43 Issue 5：比照 _handleSaveAsPreset 既有的 try/catch +
      // SnackBar 模式，補齊套用預設集失敗時的使用者可見提示。
      debugPrint('套用版面設定失敗：$e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_apply_preset_error_snackbar'),
          content: Text('套用版面設定失敗：$e'),
        ),
      );
    }
  }
```

- [x] **Step 6: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（與 Step 1 記錄的基準線一致，外加 Step 3 新測試通過）

- [x] **Step 7: flutter analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 8: Commit**

```bash
git add lib/screens/reader_screen.dart test/screens/reader_screen_test.dart
git commit -m "fix(reader): _applyPrefsToTargets 補上 try/catch 與失敗提示"
```

---

### Task 2: `_handleApplyFromBook` 補上獨立的 try/catch + SnackBar

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1137-1147`（`_handleApplyFromBook`）
- Modify: `app/test/screens/reader_screen_test.dart`（新增測試，約在既有「複製其他書籍設定到本書」測試後）

**Interfaces:**
- Consumes: `_ThrowingBookReaderPrefsRepository`（Task 1）、`pumpReaderScreen(..., bookReaderPrefsRepositoryOverride: ...)`（Task 1）。

- [x] **Step 1: 執行既有測試建立基準線**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（延續 Task 1 完成後的狀態）

- [x] **Step 2: 寫入失敗測試**

在既有「複製其他書籍設定到本書：正確以 reflowableEpubFields() 過濾後寫入並即時反映」測試（約第 8361 行）後新增：

```dart
    testWidgets('複製其他書籍設定到本書：讀取來源書籍設定拋出例外時顯示提示，不被靜默吞掉', (
      tester,
    ) async {
      final throwingBookReaderPrefsRepository =
          _ThrowingBookReaderPrefsRepository(libraryRepository.database);
      await pumpReaderScreen(
        tester,
        bookReaderPrefsRepositoryOverride: throwingBookReaderPrefsRepository,
      );

      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_copy_from_book_current')),
      );
      await tester.tap(
        find.byKey(const Key('reader_settings_copy_from_book_current')),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('layout_preset_book_picker_item_b_other')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('layout_preset_book_picker_confirm')),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reader_apply_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
```

**注意：** 這則測試觸發的是 `_handleApplyFromBook` 自己的 `repository.load(sourceBookId)` 拋例外——這一步發生在呼叫 `_applyPrefsToTargets` **之前**，因此驗證的是本 Task 新增的外層 try/catch，而不是 Task 1 已經覆蓋的內層 try/catch（若本 Task 尚未實作，`repository.load()` 拋出的例外會是完全未捕捉的例外，直接讓 `tester.takeException()` 非 null，而不是「SnackBar 沒顯示」——Step 3 會看到這個現象）。

- [x] **Step 3: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "預設集"`（M-4 審查修訂：理由同 Task 1 Step 4）
Expected: FAIL（`tester.takeException()` 回傳非 null 的未捕捉例外，而非單純找不到 SnackBar——因為 `repository.load()` 拋出的例外目前完全沒有 try/catch 保護）

- [x] **Step 4: 改寫 `_handleApplyFromBook`**

找到現有方法（約第 1137-1147 行）：

```dart
  Future<void> _handleApplyFromBook(
    String sourceBookId, {
    required List<String> targetBookIds,
  }) async {
    final repository = widget.bookReaderPrefsRepository;
    if (repository == null || targetBookIds.isEmpty) return;
    final sourcePrefs =
        (await repository.load(sourceBookId)).reflowableEpubFields();
    if (!mounted) return;
    await _applyPrefsToTargets(sourcePrefs, targetBookIds);
  }
```

改為：

```dart
  Future<void> _handleApplyFromBook(
    String sourceBookId, {
    required List<String> targetBookIds,
  }) async {
    final repository = widget.bookReaderPrefsRepository;
    if (repository == null || targetBookIds.isEmpty) return;
    try {
      final sourcePrefs =
          (await repository.load(sourceBookId)).reflowableEpubFields();
      if (!mounted) return;
      await _applyPrefsToTargets(sourcePrefs, targetBookIds);
    } catch (e, stackTrace) {
      // Epic 43 Issue 5（I-2 審查修訂）：repository.load() 發生在呼叫
      // _applyPrefsToTargets 之前，不在它內部的 try/catch 保護範圍內，
      // 需要自己獨立這一層——與 _applyPrefsToTargets 內部的 try/catch
      // 是兩層獨立保護，不會為同一次失敗重複顯示兩次 SnackBar（見上方
      // Global Constraints 說明）。
      debugPrint('套用版面設定失敗：$e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_apply_preset_error_snackbar'),
          content: Text('套用版面設定失敗：$e'),
        ),
      );
    }
  }
```

- [x] **Step 5: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（與 Step 1 記錄的基準線一致，外加 Step 2 新測試通過）

- [x] **Step 6: flutter analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add lib/screens/reader_screen.dart test/screens/reader_screen_test.dart
git commit -m "fix(reader): _handleApplyFromBook 補上獨立的 try/catch 與失敗提示"
```

---

### Task 3: `_handleDeletePreset` 補上 try/catch + SnackBar

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1149-1166`（`_handleDeletePreset`）
- Modify: `app/test/screens/reader_screen_test.dart:91-98`（`_ThrowingLayoutPresetRepository` 新增 `delete()` 覆寫）、新增測試（約在既有「刪除預設集：正確從 LayoutPresetRepository 移除」測試群組後）

**Interfaces:**
- Consumes: `_ThrowingLayoutPresetRepository`（既有，Task 3 為其新增 `delete()` 覆寫）。

- [x] **Step 1: 執行既有測試建立基準線**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（延續 Task 2 完成後的狀態）

- [x] **Step 2: `_ThrowingLayoutPresetRepository` 新增 `delete()` 覆寫，並寫入失敗測試**

找到現有的 `_ThrowingLayoutPresetRepository`（約第 91-98 行）：

```dart
class _ThrowingLayoutPresetRepository extends LayoutPresetRepository {
  _ThrowingLayoutPresetRepository(super.db);

  @override
  Future<void> insert(LayoutPreset preset) async {
    throw Exception('模擬 insert 失敗（測試用）');
  }
}
```

改為（新增 `delete()` 覆寫，`insert()` 維持不動）：

```dart
class _ThrowingLayoutPresetRepository extends LayoutPresetRepository {
  _ThrowingLayoutPresetRepository(super.db);

  @override
  Future<void> insert(LayoutPreset preset) async {
    throw Exception('模擬 insert 失敗（測試用）');
  }

  // Epic 43 Issue 5：供「刪除預設集失敗」測試使用。
  @override
  Future<void> delete(int id) async {
    throw Exception('模擬 delete 失敗（測試用）');
  }
}
```

在既有「刪除預設集：正確從 LayoutPresetRepository 移除」測試（約第 8293 行）後新增（**注意**：種子資料須用未覆寫的 `layoutPresetRepository`〔頂層 `late` 變數〕呼叫 `insert()`，不能用 `_ThrowingLayoutPresetRepository` 實例——它的 `insert()` 一律拋例外；兩者共用同一個 `libraryRepository.database` 連線，用哪個實例寫入的資料對另一個實例同樣可見）：

```dart
    testWidgets('刪除預設集：刪除過程拋出例外時顯示提示，不被靜默吞掉', (tester) async {
      await tester.runAsync(
        () => layoutPresetRepository.insert(
          LayoutPreset(
            id: null,
            name: '待刪除',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            prefs: BookReaderPrefs.empty,
          ),
        ),
      );
      final throwingRepository = _ThrowingLayoutPresetRepository(
        libraryRepository.database,
      );
      await pumpReaderScreen(
        tester,
        layoutPresetRepositoryOverride: throwingRepository,
      );

      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_delete')),
      );
      await tester.tap(
        find.byKey(const Key('reader_settings_preset_slot_0_delete')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('layout_preset_delete_confirm')));
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reader_delete_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      // M-3（審查修訂）：驗證刪除失敗時底層資料未被誤刪，狀態未受污染。
      final all = await tester.runAsync(() => layoutPresetRepository.listAll());
      expect(all, hasLength(1));
    });
```

- [x] **Step 3: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "預設集"`（M-4 審查修訂：理由同 Task 1 Step 4）
Expected: FAIL（`tester.takeException()` 回傳非 null 的未捕捉例外——`deleteLayoutPreset()` 拋出的例外目前完全沒有 try/catch 保護）

- [x] **Step 4: 改寫 `_handleDeletePreset`**

找到現有方法（約第 1149-1166 行）：

```dart
  Future<void> _handleDeletePreset(int id) async {
    final repository = widget.layoutPresetRepository;
    if (repository == null) return;
    String presetName = '';
    for (final preset in _layoutPresets) {
      if (preset.id == id) {
        presetName = preset.name;
        break;
      }
    }
    final confirmed = await _confirmDeletePreset(presetName);
    // I-2（審查修訂）：理由同上（`_handleSaveAsPreset` 覆蓋確認）。
    if (!confirmed || !mounted) return;
    final updated =
        await layout_preset_actions.deleteLayoutPreset(repository, id);
    if (!mounted) return;
    setState(() => _layoutPresets = updated);
  }
```

改為：

```dart
  Future<void> _handleDeletePreset(int id) async {
    final repository = widget.layoutPresetRepository;
    if (repository == null) return;
    String presetName = '';
    for (final preset in _layoutPresets) {
      if (preset.id == id) {
        presetName = preset.name;
        break;
      }
    }
    final confirmed = await _confirmDeletePreset(presetName);
    // I-2（審查修訂）：理由同上（`_handleSaveAsPreset` 覆蓋確認）。
    if (!confirmed || !mounted) return;
    try {
      final updated =
          await layout_preset_actions.deleteLayoutPreset(repository, id);
      if (!mounted) return;
      setState(() => _layoutPresets = updated);
    } catch (e, stackTrace) {
      // Epic 43 Issue 5：比照 _handleSaveAsPreset 既有的 try/catch +
      // SnackBar 模式，補齊刪除預設集失敗時的使用者可見提示。
      debugPrint('刪除預設集失敗：$e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_delete_preset_error_snackbar'),
          content: Text('刪除預設集失敗：$e'),
        ),
      );
    }
  }
```

- [x] **Step 5: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（與 Step 1 記錄的基準線一致，外加 Step 2 新測試通過）

- [x] **Step 6: flutter analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add lib/screens/reader_screen.dart test/screens/reader_screen_test.dart
git commit -m "fix(reader): _handleDeletePreset 補上 try/catch 與失敗提示"
```

---

### Task 4: 完整驗證

**Files:** 無新增/修改（純驗證）

- [x] **Step 1: 完整 flutter analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 2: 完整 flutter test**

Run: `flutter test`
Expected: 全數通過，零回歸（若有既有已知不穩定測試案例，比照 `epic-41`/`epic-43` Issue 1/2/4 慣例於 PR 描述註明，不視為本 Issue 造成的回歸）

- [x] **Step 3: 於 `plan-issue-5.md` 標記全部 Task 完成**

將本檔案所有 `- [x]` 改為 `- [x]`。

- [x] **Step 4: 發起獨立程式審查**

比照 `docs/agents/issue-tracker.md`／`sdd-workflow` 既有流程，使用 `/superpowers:requesting-code-review` 對本次異動（`git diff` 對比 Task 1 之前的 commit）發起審查，結果存至 `docs/epics/epic-43-reader-architecture-hardening/reviews/review-issue-5.md`（不進版控）。
