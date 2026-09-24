# Epic 43 Issue 2 — LayoutPreset Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 抽出 `ReaderScreen` 版面設定預設集「另存／套用／套用來源書籍／刪除」四個操作各自重複的「寫入 repository → 取得最新清單」邏輯，收斂成一組不依賴 `BuildContext` 的頂層純函式模組 `layout_preset_actions.dart`，並合併 `_handleApplyPreset`/`_handleApplyFromBook` 逐行相同的「判斷是否僅套用到目前書籍 → 視情況跳確認 → 單筆/批次寫入 → 套用到目前書籍時刷新」中段邏輯成共用私有方法 `_applyPrefsToTargets`。

**Architecture:** 新增 `app/lib/reader/layout_preset_actions.dart`，內含 5 個頂層函式（不做成類別——`LayoutPresetRepository`／`BookReaderPrefsRepository` 分屬不同操作子集、不保證成對提供，比照 `bookmark_toggle.dart` 既有風格，各函式各自宣告自己實際需要的 repository 為必要參數）：`layoutPresetTargetsCurrentBookOnly()`（純判斷）、`insertNewLayoutPreset()`／`overwriteLayoutPreset()`／`deleteLayoutPreset()`（皆回傳 `repository.listAll()` 最新結果）、`applyLayoutPresetPrefs()`（單筆/批次寫入）。`ReaderScreen` 新增私有方法 `_applyPrefsToTargets(prefs, targetBookIds)` 收斂 `_handleApplyPreset`/`_handleApplyFromBook` 原本重複的中段邏輯，兩者皆改為呼叫它的薄包裝；`_handleSaveAsPreset`/`_handleDeletePreset` 改呼叫對應的頂層函式取得最新清單後直接 `setState`，取代原本另外呼叫 `_loadLayoutPresets()`。`BuildContext`/`Navigator`/`ScaffoldMessenger` 相關邏輯（跳確認對話框、顯示 SnackBar、命名輸入對話框）維持留在 `ReaderScreen` 呼叫端不動。

**Tech Stack:** Flutter/Dart 3.11，`flutter_test`，`sqflite_common_ffi`（`LayoutPresetRepository`／`BookReaderPrefsRepository` 皆綁定真實 `Database`，非可替身的抽象介面，單元測試沿用既有 `test/reader/layout_preset_repository_test.dart`／`test/reader/book_reader_prefs_repository_test.dart` 的 in-memory SQLite 慣例，經 `SqliteLibraryRepository.open(inMemoryDatabasePath)` 取得含完整 schema 的 `Database`）。

**Spec:** `docs/epics/epic-43-reader-architecture-hardening/issues.md` Issue 2（`/grilling` Q1-Q4 已定案介面形狀）。

## Global Constraints

- 所有指令在 `app/` 目錄下執行。
- `layout_preset_actions.dart` 內任何函式皆**不做 `prefs` 欄位過濾**——過濾責任在呼叫端（`ReaderScreen` 呼叫 `BookReaderPrefs.reflowableEpubFields()` 後才把結果傳入），比照 `LayoutPresetRepository` 類別文件既有「本類別不負責欄位過濾」的既定分工，不在本 Issue 重新討論。
- `LayoutPresetRepository`／`BookReaderPrefsRepository` 為具體類別（非 `abstract`），綁定真實 `Database`；單元測試一律用 `sqfliteFfiInit()`＋`databaseFactory = databaseFactoryFfi`＋`SqliteLibraryRepository.open(inMemoryDatabasePath)` 取得含 `layout_preset`／`book_reader_prefs`／`books` 三張表 schema 的連線，不另外手刻假 repository（`LayoutPresetRepository`/`BookReaderPrefsRepository` 皆非抽象介面，無法用 `implements` 寫記憶體版本；`book_reader_prefs.book_id` 對 `books.id` 有外鍵約束，寫入前須先 `insertBook()`）。
- `_handleApplyPreset`/`_handleApplyFromBook`/`_handleSaveAsPreset`/`_handleDeletePreset`/`_confirmApplyToOtherBooks`/`_selectPresetToOverwrite`/`_confirmOverwrite`/`_confirmDeletePreset`/`_handleRequestBookPicker` 這幾個既有方法簽章（包含 `_openLayoutSettings()` 呼叫 `ReaderSettingsSheet` 時傳入的 6 個 callback 參數）**完全不變**——本 Issue 只改這些方法「內部如何寫入/刷新清單」，不改對外介面，`ReaderSettingsSheet`／`_openLayoutSettings()` 皆不需要修改。
- 每個 Task 的 TDD 步驟只跑本次異動觸及的測試檔；完整 `flutter test` 只在最後一個 Task（Task 8）執行一次。

---

### Task 1: `layoutPresetTargetsCurrentBookOnly()`

**Files:**
- Create: `app/lib/reader/layout_preset_actions.dart`
- Test: `app/test/reader/layout_preset_actions_test.dart`

**Interfaces:**
- Produces: `bool layoutPresetTargetsCurrentBookOnly(List<String> targetBookIds, String currentBookId)`

- [x] **Step 1: 建立測試檔並寫入失敗測試**

建立 `app/test/reader/layout_preset_actions_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/layout_preset_actions.dart';

void main() {
  group('layoutPresetTargetsCurrentBookOnly', () {
    test('targetBookIds 恰為 [currentBookId] 時回傳 true', () {
      expect(layoutPresetTargetsCurrentBookOnly(['b1'], 'b1'), isTrue);
    });

    test('targetBookIds 有多本書時回傳 false（即使包含 currentBookId）', () {
      expect(layoutPresetTargetsCurrentBookOnly(['b1', 'b2'], 'b1'), isFalse);
    });

    test('targetBookIds 恰有 1 本但不是 currentBookId 時回傳 false', () {
      expect(layoutPresetTargetsCurrentBookOnly(['b2'], 'b1'), isFalse);
    });

    test('targetBookIds 為空清單時回傳 false', () {
      expect(layoutPresetTargetsCurrentBookOnly([], 'b1'), isFalse);
    });
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/layout_preset_actions_test.dart`
Expected: FAIL（`layout_preset_actions.dart` 尚不存在，import 錯誤）

- [x] **Step 3: 建立 `layout_preset_actions.dart`，寫入 `layoutPresetTargetsCurrentBookOnly()`**

```dart
/// `ReaderScreen` 版面設定預設集「另存／套用／套用來源書籍／刪除」共用
/// 操作的純函式模組（Epic 43 Issue 2）。頂層函式，不做成類別——
/// `LayoutPresetRepository`／`BookReaderPrefsRepository` 分屬不同操作
/// 子集，已證實不永遠成對提供（`issues.md` Issue 2 Q3），比照
/// `bookmark_toggle.dart` 既有風格，各函式各自宣告自己實際需要的
/// repository 為必要參數。
library;

/// `_handleApplyPreset`/`_handleApplyFromBook` 原本各自重複的 inline
/// 判斷抽成純函式——「套用到目前書籍」的快速動作固定產生
/// `targetBookIds == [currentBookId]` 這個形狀，用來與「套用到其他
/// 書籍」picker 只勾選 1 本其他書籍時的 `targetBookIds.length == 1`
/// 區分開來（後者仍需要確認對話框，見 `ReaderScreen._applyPrefsToTargets`
/// 文件）。
bool layoutPresetTargetsCurrentBookOnly(
  List<String> targetBookIds,
  String currentBookId,
) =>
    targetBookIds.length == 1 && targetBookIds.single == currentBookId;
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/layout_preset_actions_test.dart`
Expected: PASS（4 個測試全過）

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/layout_preset_actions.dart app/test/reader/layout_preset_actions_test.dart
git commit -m "feat(reader): 新增 layoutPresetTargetsCurrentBookOnly()"
```

---

### Task 2: `insertNewLayoutPreset()`

**Files:**
- Modify: `app/lib/reader/layout_preset_actions.dart`
- Test: `app/test/reader/layout_preset_actions_test.dart`

**Interfaces:**
- Consumes: `LayoutPreset`（`app/lib/reader/layout_preset.dart`）、`LayoutPresetRepository`（`app/lib/reader/layout_preset_repository.dart`，既有 `insert(LayoutPreset)`/`listAll()` 方法）、`BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`）。
- Produces: `Future<List<LayoutPreset>> insertNewLayoutPreset(LayoutPresetRepository repository, {required String name, required BookReaderPrefs prefs})`。

- [x] **Step 1: 寫入失敗測試**

在 `layout_preset_actions_test.dart` 頂部 import 區塊新增：

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/layout_preset.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
```

在 `void main() {` 第一行、既有 `group('layoutPresetTargetsCurrentBookOnly', ...)` **之前**新增（M-1 審查修訂：`setUpAll` 為檔案全域初始化，依標準 Dart 測試組織慣例應置於所有 `group` 之前，而非夾在某個 `group` 之後）：

```dart
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
```

在既有 `group('layoutPresetTargetsCurrentBookOnly', ...)` 後新增：

```dart
  group('insertNewLayoutPreset', () {
    late SqliteLibraryRepository libraryRepository;
    late LayoutPresetRepository repository;

    setUp(() async {
      libraryRepository =
          await SqliteLibraryRepository.open(inMemoryDatabasePath);
      repository = LayoutPresetRepository(libraryRepository.database);
    });

    tearDown(() async {
      await libraryRepository.close();
    });

    test('insert 後回傳的清單包含新預設集，且已由資料庫指派 id', () async {
      final updated = await insertNewLayoutPreset(
        repository,
        name: '臥室夜讀直排',
        prefs: const BookReaderPrefs(fontSize: 18),
      );

      expect(updated, hasLength(1));
      expect(updated.single.id, isNotNull);
      expect(updated.single.name, '臥室夜讀直排');
      expect(updated.single.prefs.fontSize, 18);
    });

    test('回傳的清單反映目前完整內容，依插入順序排列', () async {
      await insertNewLayoutPreset(
        repository,
        name: '第一組',
        prefs: BookReaderPrefs.empty,
      );

      final updated = await insertNewLayoutPreset(
        repository,
        name: '第二組',
        prefs: BookReaderPrefs.empty,
      );

      expect(updated.map((p) => p.name).toList(), ['第一組', '第二組']);
    });
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/layout_preset_actions_test.dart`
Expected: FAIL（`insertNewLayoutPreset` 函式不存在）

- [x] **Step 3: 實作 `insertNewLayoutPreset()`**

於檔案頂部補 import：

```dart
import 'book_reader_prefs.dart';
import 'layout_preset.dart';
import 'layout_preset_repository.dart';
```

於 `layoutPresetTargetsCurrentBookOnly()` 後新增：

```dart
/// 新增一組預設集（未滿 3 組時的路徑）。[prefs] 須由呼叫端先以
/// `BookReaderPrefs.reflowableEpubFields()` 過濾（`LayoutPresetRepository`
/// 本身不做過濾，見該類別文件）。完成後回傳 [repository] 目前的完整
/// 清單，取代呼叫端另外呼叫 `_loadLayoutPresets()`。
Future<List<LayoutPreset>> insertNewLayoutPreset(
  LayoutPresetRepository repository, {
  required String name,
  required BookReaderPrefs prefs,
}) async {
  final now = DateTime.now();
  await repository.insert(LayoutPreset(
    id: null,
    name: name,
    createdAt: now,
    updatedAt: now,
    prefs: prefs,
  ));
  return repository.listAll();
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/layout_preset_actions_test.dart`
Expected: PASS（6 個測試全過）

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/layout_preset_actions.dart app/test/reader/layout_preset_actions_test.dart
git commit -m "feat(reader): layout_preset_actions 新增 insertNewLayoutPreset()"
```

---

### Task 3: `overwriteLayoutPreset()`

**Files:**
- Modify: `app/lib/reader/layout_preset_actions.dart`
- Test: `app/test/reader/layout_preset_actions_test.dart`

**Interfaces:**
- Consumes: `LayoutPreset`／`LayoutPresetRepository`（既有 `replace(int, LayoutPreset)` 方法）、`BookReaderPrefs`（Task 2 已 import）。
- Produces: `Future<List<LayoutPreset>> overwriteLayoutPreset(LayoutPresetRepository repository, {required LayoutPreset target, required String name, required BookReaderPrefs prefs})`。

- [x] **Step 1: 寫入失敗測試**

於 `layout_preset_actions_test.dart` 既有 `group('insertNewLayoutPreset', ...)` 後新增：

```dart
  group('overwriteLayoutPreset', () {
    late SqliteLibraryRepository libraryRepository;
    late LayoutPresetRepository repository;

    setUp(() async {
      libraryRepository =
          await SqliteLibraryRepository.open(inMemoryDatabasePath);
      repository = LayoutPresetRepository(libraryRepository.database);
    });

    tearDown(() async {
      await libraryRepository.close();
    });

    test('覆蓋後 id／createdAt 不變，name／prefs 更新為新值', () async {
      final createdAt = DateTime.fromMillisecondsSinceEpoch(1000);
      await repository.insert(LayoutPreset(
        id: null,
        name: '舊名稱',
        createdAt: createdAt,
        updatedAt: createdAt,
        prefs: const BookReaderPrefs(fontSize: 16),
      ));
      final target = (await repository.listAll()).single;

      final updated = await overwriteLayoutPreset(
        repository,
        target: target,
        name: '新名稱',
        prefs: const BookReaderPrefs(fontSize: 20),
      );

      expect(updated, hasLength(1));
      expect(updated.single.id, target.id);
      expect(updated.single.name, '新名稱');
      expect(updated.single.prefs.fontSize, 20);
      expect(updated.single.createdAt, target.createdAt);
    });

    test('target.id 為 null（未持久化的暫存物件）時觸發 assert', () async {
      final target = LayoutPreset(
        id: null,
        name: '暫存',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: BookReaderPrefs.empty,
      );

      expect(
        () => overwriteLayoutPreset(
          repository,
          target: target,
          name: '新名稱',
          prefs: BookReaderPrefs.empty,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/layout_preset_actions_test.dart`
Expected: FAIL（`overwriteLayoutPreset` 函式不存在）

- [x] **Step 3: 實作 `overwriteLayoutPreset()`**

於 `insertNewLayoutPreset()` 後新增：

```dart
/// 覆蓋既有一組（存滿 3 組時的路徑）。[target] 須為已持久化的預設集
/// （`target.id` 非 null）——未存檔的暫存物件呼叫本函式屬於呼叫端邏輯
/// 錯誤，assert 讓誤傳時有明確的除錯訊息，而非隱蔽的 `target.id!`
/// 執行期 null check 崩潰。[prefs] 過濾責任同 [insertNewLayoutPreset]。
Future<List<LayoutPreset>> overwriteLayoutPreset(
  LayoutPresetRepository repository, {
  required LayoutPreset target,
  required String name,
  required BookReaderPrefs prefs,
}) async {
  assert(target.id != null,
      'Target layout preset must have a valid id for overwrite');
  await repository.replace(
    target.id!,
    LayoutPreset(
      id: target.id,
      name: name,
      createdAt: target.createdAt,
      updatedAt: DateTime.now(),
      prefs: prefs,
    ),
  );
  return repository.listAll();
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/layout_preset_actions_test.dart`
Expected: PASS（8 個測試全過）

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/layout_preset_actions.dart app/test/reader/layout_preset_actions_test.dart
git commit -m "feat(reader): layout_preset_actions 新增 overwriteLayoutPreset()"
```

---

### Task 4: `deleteLayoutPreset()`

**Files:**
- Modify: `app/lib/reader/layout_preset_actions.dart`
- Test: `app/test/reader/layout_preset_actions_test.dart`

**Interfaces:**
- Consumes: `LayoutPreset`／`LayoutPresetRepository`（既有 `delete(int)` 方法）。
- Produces: `Future<List<LayoutPreset>> deleteLayoutPreset(LayoutPresetRepository repository, int id)`。

- [x] **Step 1: 寫入失敗測試**

於 `layout_preset_actions_test.dart` 既有 `group('overwriteLayoutPreset', ...)` 後新增：

```dart
  group('deleteLayoutPreset', () {
    late SqliteLibraryRepository libraryRepository;
    late LayoutPresetRepository repository;

    setUp(() async {
      libraryRepository =
          await SqliteLibraryRepository.open(inMemoryDatabasePath);
      repository = LayoutPresetRepository(libraryRepository.database);
    });

    tearDown(() async {
      await libraryRepository.close();
    });

    test('刪除後回傳的清單不含該筆，其餘保留', () async {
      await repository.insert(LayoutPreset(
        id: null,
        name: '保留組',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: BookReaderPrefs.empty,
      ));
      await repository.insert(LayoutPreset(
        id: null,
        name: '刪除組',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: BookReaderPrefs.empty,
      ));
      final toDelete =
          (await repository.listAll()).firstWhere((p) => p.name == '刪除組');

      final updated = await deleteLayoutPreset(repository, toDelete.id!);

      expect(updated, hasLength(1));
      expect(updated.single.name, '保留組');
    });
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/layout_preset_actions_test.dart`
Expected: FAIL（`deleteLayoutPreset` 函式不存在）

- [x] **Step 3: 實作 `deleteLayoutPreset()`**

於 `overwriteLayoutPreset()` 後新增：

```dart
/// 刪除一組預設集，完成後回傳 [repository] 目前的完整清單，取代呼叫端
/// 另外呼叫 `_loadLayoutPresets()`。
Future<List<LayoutPreset>> deleteLayoutPreset(
  LayoutPresetRepository repository,
  int id,
) async {
  await repository.delete(id);
  return repository.listAll();
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/layout_preset_actions_test.dart`
Expected: PASS（9 個測試全過）

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/layout_preset_actions.dart app/test/reader/layout_preset_actions_test.dart
git commit -m "feat(reader): layout_preset_actions 新增 deleteLayoutPreset()"
```

---

### Task 5: `applyLayoutPresetPrefs()`

**Files:**
- Modify: `app/lib/reader/layout_preset_actions.dart`
- Test: `app/test/reader/layout_preset_actions_test.dart`

**Interfaces:**
- Consumes: `BookReaderPrefs`、`BookReaderPrefsRepository`（`app/lib/reader/book_reader_prefs_repository.dart`，既有 `save(String, BookReaderPrefs)`/`saveMultiple(List<String>, BookReaderPrefs)`/`load(String)` 方法）、`Book`/`BookFileFormat`/`BookSource`（`app/lib/library/models/book.dart`、`app/lib/library/models/library_enums.dart`，測試用，滿足 `book_reader_prefs.book_id` 外鍵約束）。
- Produces: `Future<void> applyLayoutPresetPrefs(BookReaderPrefsRepository repository, {required BookReaderPrefs prefs, required List<String> targetBookIds})`。

- [x] **Step 1: 寫入失敗測試**

於 `layout_preset_actions_test.dart` 頂部 import 區塊新增：

```dart
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
```

於既有 `group('deleteLayoutPreset', ...)` 後新增：

```dart
  group('applyLayoutPresetPrefs', () {
    late SqliteLibraryRepository libraryRepository;
    late BookReaderPrefsRepository repository;

    setUp(() async {
      libraryRepository =
          await SqliteLibraryRepository.open(inMemoryDatabasePath);
      repository = BookReaderPrefsRepository(libraryRepository.database);
      for (final id in ['b1', 'b2', 'b3']) {
        await libraryRepository.insertBook(Book(
          id: id,
          title: '書名$id',
          format: BookFileFormat.epub,
          filePath: 'content://example/$id',
          source: BookSource.local,
          createTime: DateTime.fromMillisecondsSinceEpoch(1000),
          lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
        ));
      }
    });

    tearDown(() async {
      await libraryRepository.close();
    });

    test('targetBookIds 只有 1 本時呼叫 save（單筆寫入）', () async {
      await applyLayoutPresetPrefs(
        repository,
        prefs: const BookReaderPrefs(fontSize: 18),
        targetBookIds: ['b1'],
      );

      expect((await repository.load('b1')).fontSize, 18);
    });

    test('targetBookIds 有多本時呼叫 saveMultiple（批次寫入），皆正確寫入', () async {
      await applyLayoutPresetPrefs(
        repository,
        prefs: const BookReaderPrefs(fontSize: 22),
        targetBookIds: ['b1', 'b2', 'b3'],
      );

      expect((await repository.load('b1')).fontSize, 22);
      expect((await repository.load('b2')).fontSize, 22);
      expect((await repository.load('b3')).fontSize, 22);
    });

    // I-1（審查修訂）：targetBookIds 為空清單時，length==1 判定為
    // false 會落入 else 分支呼叫 saveMultiple([], prefs)，開啟一次
    // 完全無謂的 SQLite transaction——補上提早返回並驗證不寫入。
    test('targetBookIds 為空清單時不執行寫入且安全返回', () async {
      await applyLayoutPresetPrefs(
        repository,
        prefs: const BookReaderPrefs(fontSize: 20),
        targetBookIds: [],
      );

      expect((await repository.load('b1')).fontSize, isNull);
    });
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/layout_preset_actions_test.dart`
Expected: FAIL（`applyLayoutPresetPrefs` 函式不存在）

- [x] **Step 3: 實作 `applyLayoutPresetPrefs()`**

於檔案頂部補 import：

```dart
import 'book_reader_prefs_repository.dart';
```

於 `deleteLayoutPreset()` 後新增：

```dart
/// `_handleApplyPreset`/`_handleApplyFromBook` 共用的核心：只做寫入
/// （單筆 `save`／批次 `saveMultiple`），不含確認對話框、不含
/// `_handlePrefsChanged` 呼叫（皆需要 BuildContext／ReaderScreen 自身
/// 狀態，留在呼叫端，比照 Epic 43 Issue 1 一貫的邊界原則）。
///
/// I-1（審查修訂）：`targetBookIds` 為空清單時提早返回——本函式是
/// `layout_preset_actions.dart` 模組導出的公開頂層函式，即使目前唯一
/// 呼叫端 `ReaderScreen._applyPrefsToTargets` 已自行 guard
/// `targetBookIds.isEmpty`，本函式仍應有自我防禦能力，避免空清單落入
/// `else` 分支對 `saveMultiple([], prefs)` 開啟一次無謂的 SQLite
/// transaction。
Future<void> applyLayoutPresetPrefs(
  BookReaderPrefsRepository repository, {
  required BookReaderPrefs prefs,
  required List<String> targetBookIds,
}) async {
  if (targetBookIds.isEmpty) return;
  if (targetBookIds.length == 1) {
    await repository.save(targetBookIds.first, prefs);
  } else {
    await repository.saveMultiple(targetBookIds, prefs);
  }
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/layout_preset_actions_test.dart`
Expected: PASS（12 個測試全過）

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/layout_preset_actions.dart app/test/reader/layout_preset_actions_test.dart
git commit -m "feat(reader): layout_preset_actions 新增 applyLayoutPresetPrefs()"
```

---

### Task 6: `ReaderScreen` 接上 `layout_preset_actions`（另存／刪除）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:79`（新增 import）、`:971-1022`（`_handleSaveAsPreset`）、`:1153-1167`（`_handleDeletePreset`）

**Interfaces:**
- Consumes: `insertNewLayoutPreset`/`overwriteLayoutPreset`/`deleteLayoutPreset`（Task 2-4，`app/lib/reader/layout_preset_actions.dart`）。

- [x] **Step 1: 執行既有測試建立基準線**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（記錄目前全數通過，作為本 Task 修改後的零回歸基準）

- [x] **Step 2: 新增 import**

在 `reader_screen.dart` 頂部 import 區塊（`import '../reader/layout_preset_repository.dart';` 後，第 79 行後）新增：

```dart
import '../reader/layout_preset_actions.dart' as layout_preset_actions;
```

- [x] **Step 3: 改寫 `_handleSaveAsPreset`**

找到現有方法（約第 971-1022 行）：

```dart
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

改為：

```dart
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
      List<LayoutPreset> updated;
      if (_layoutPresets.length < 3) {
        updated = await layout_preset_actions.insertNewLayoutPreset(
          repository,
          name: name,
          prefs: filteredPrefs,
        );
      } else {
        final target = await _selectPresetToOverwrite();
        if (target == null || !mounted) return;
        final confirmed = await _confirmOverwrite(target.name);
        // I-2（審查修訂）：對話框彈出期間使用者可能退出閱讀器，pop 後
        // State 可能已 unmounted，比照 issues.md I-3／Task 7
        // _applyPrefsToTargets 既有慣例，`!confirmed` 與 `!mounted`
        // 合併檢查。
        if (!confirmed || !mounted) return;
        updated = await layout_preset_actions.overwriteLayoutPreset(
          repository,
          target: target,
          name: name,
          prefs: filteredPrefs,
        );
      }
      if (!mounted) return;
      setState(() => _layoutPresets = updated);
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

- [x] **Step 4: 改寫 `_handleDeletePreset`**

找到現有方法（約第 1153-1167 行）：

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
    if (!confirmed) return;
    await repository.delete(id);
    await _loadLayoutPresets();
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
    final updated =
        await layout_preset_actions.deleteLayoutPreset(repository, id);
    if (!mounted) return;
    setState(() => _layoutPresets = updated);
  }
```

**注意：** `_loadLayoutPresets()` 方法本身**不要刪除**——`initState()`（約第 547 行）仍呼叫它作為畫面初次進入時的載入路徑，這條路徑不在本 Issue 範圍內（見 Global Constraints）。

- [x] **Step 5: 執行測試確認零回歸**

Run: `flutter test test/reader/layout_preset_actions_test.dart test/screens/reader_screen_test.dart`（M-2 審查修訂：一併納入新抽出的純函式單元測試，確保接入過程中兩者持續受測）
Expected: PASS（`reader_screen_test.dart` 與 Step 1 記錄的基準線一致，無新增失敗；`layout_preset_actions_test.dart` 維持 Task 5 完成後的通過數）

- [x] **Step 6: flutter analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart
git commit -m "refactor(reader): ReaderScreen 另存/刪除預設集改用 layout_preset_actions"
```

---

### Task 7: `ReaderScreen` 接上 `layout_preset_actions`（套用／套用來源書籍），新增 `_applyPrefsToTargets`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1090-1151`（`_handleApplyPreset`/`_handleApplyFromBook`，新增 `_applyPrefsToTargets`）

**Interfaces:**
- Consumes: `layoutPresetTargetsCurrentBookOnly`（Task 1）、`applyLayoutPresetPrefs`（Task 5）、`layout_preset_actions` import（Task 6 Step 2 已新增）。

- [x] **Step 1: 執行既有測試建立基準線**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（延續 Task 6 完成後的狀態）

- [x] **Step 2: 改寫 `_handleApplyPreset`/`_handleApplyFromBook`，新增 `_applyPrefsToTargets`**

找到現有的兩個方法與其文件註解（約第 1090-1151 行）：

```dart
  /// 套用預設集（epic-28-reader-settings-enhancements Issue 3）：「套用到
  /// 目前書籍」（`targetBookIds` 恰為 `[widget.bookId]`，[ReaderSettingsSheet]
  /// 的「套用到本書」快速按鈕固定產生這個形狀）直接寫入不需確認；其餘
  /// 情況（「套用到其他書籍」流程，即使使用者只勾選 1 本其他書籍）皆先
  /// 跳出「即將覆蓋 N 本書」確認——**判斷依據刻意不是 `targetBookIds.length
  /// > 1`**：使用者透過「套用到其他書籍」picker 只勾選 1 本書時，
  /// `targetBookIds.length == 1`，但這仍是「其他書籍」語意（design.md
  /// 「套用目標二選一」的第二選項），不是「套用到目前書籍」的快速動作，
  /// 兩者不可用數量混為一談。目標含目前書籍時，寫入後呼叫既有
  /// [_handlePrefsChanged] 即時刷新畫面（比照 spec.md「套用到目前書籍後
  /// 的畫面刷新」，不新增另一條刷新路徑）。
  Future<void> _handleApplyPreset(
    LayoutPreset preset, {
    required List<String> targetBookIds,
  }) async {
    final repository = widget.bookReaderPrefsRepository;
    if (repository == null || targetBookIds.isEmpty) return;
    final isCurrentBookOnly =
        targetBookIds.length == 1 && targetBookIds.single == widget.bookId;
    if (!isCurrentBookOnly) {
      final confirmed = await _confirmApplyToOtherBooks(targetBookIds.length);
      if (!confirmed) return;
    }
    if (targetBookIds.length == 1) {
      await repository.save(targetBookIds.first, preset.prefs);
    } else {
      await repository.saveMultiple(targetBookIds, preset.prefs);
    }
    if (targetBookIds.contains(widget.bookId)) {
      _handlePrefsChanged(preset.prefs);
    }
  }

  /// 書籍設定複製（epic-28-reader-settings-enhancements Issue 3）：先讀取
  /// 來源書籍目前的版面偏好設定，以 [BookReaderPrefs.reflowableEpubFields]
  /// 過濾後寫入。確認對話框觸發條件與批次寫入門檻，語意皆與
  /// [_handleApplyPreset] 一致（見該方法文件「判斷依據刻意不是
  /// targetBookIds.length > 1」的說明）。
  Future<void> _handleApplyFromBook(
    String sourceBookId, {
    required List<String> targetBookIds,
  }) async {
    final repository = widget.bookReaderPrefsRepository;
    if (repository == null || targetBookIds.isEmpty) return;
    final sourcePrefs =
        (await repository.load(sourceBookId)).reflowableEpubFields();
    if (!mounted) return;
    final isCurrentBookOnly =
        targetBookIds.length == 1 && targetBookIds.single == widget.bookId;
    if (!isCurrentBookOnly) {
      final confirmed = await _confirmApplyToOtherBooks(targetBookIds.length);
      if (!confirmed) return;
    }
    if (targetBookIds.length == 1) {
      await repository.save(targetBookIds.first, sourcePrefs);
    } else {
      await repository.saveMultiple(targetBookIds, sourcePrefs);
    }
    if (targetBookIds.contains(widget.bookId)) {
      _handlePrefsChanged(sourcePrefs);
    }
  }
```

改為：

```dart
  /// 套用版面設定至一批書籍（epic-28-reader-settings-enhancements Issue 3，
  /// 經 Epic 43 Issue 2 收斂為 [_handleApplyPreset]/[_handleApplyFromBook]
  /// 共用核心）：「套用到目前書籍」（`targetBookIds` 恰為 `[widget.bookId]`，
  /// [ReaderSettingsSheet] 的「套用到本書」快速按鈕固定產生這個形狀）直接
  /// 寫入不需確認；其餘情況（「套用到其他書籍」流程，即使使用者只勾選 1
  /// 本其他書籍）皆先跳出「即將覆蓋 N 本書」確認——**判斷依據刻意不是
  /// `targetBookIds.length > 1`**：使用者透過「套用到其他書籍」picker 只
  /// 勾選 1 本書時，`targetBookIds.length == 1`，但這仍是「其他書籍」語意
  /// （design.md「套用目標二選一」的第二選項），不是「套用到目前書籍」的
  /// 快速動作，兩者不可用數量混為一談，見
  /// [layout_preset_actions.layoutPresetTargetsCurrentBookOnly]。目標含
  /// 目前書籍時，寫入後呼叫既有 [_handlePrefsChanged] 即時刷新畫面（比照
  /// spec.md「套用到目前書籍後的畫面刷新」，不新增另一條刷新路徑）。
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

  Future<void> _handleApplyPreset(
    LayoutPreset preset, {
    required List<String> targetBookIds,
  }) async {
    await _applyPrefsToTargets(preset.prefs, targetBookIds);
  }

  /// 書籍設定複製（epic-28-reader-settings-enhancements Issue 3）：先讀取
  /// 來源書籍目前的版面偏好設定，以 [BookReaderPrefs.reflowableEpubFields]
  /// 過濾後交給 [_applyPrefsToTargets] 處理後續判斷/確認/寫入/刷新。
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

- [x] **Step 3: 執行測試確認零回歸**

Run: `flutter test test/reader/layout_preset_actions_test.dart test/screens/reader_screen_test.dart`（M-2 審查修訂：理由同 Task 6 Step 5）
Expected: PASS（`reader_screen_test.dart` 與 Step 1 記錄的基準線一致，無新增失敗；`layout_preset_actions_test.dart` 維持 Task 5 完成後的通過數）

- [x] **Step 4: flutter analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 5: Commit**

```bash
git add app/lib/screens/reader_screen.dart
git commit -m "refactor(reader): ReaderScreen 套用預設集/套用來源書籍改用 _applyPrefsToTargets"
```

---

### Task 8: 完整驗證

**Files:** 無新增/修改（純驗證）

- [x] **Step 1: 完整 flutter analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 2: 完整 flutter test**

Run: `flutter test`
Expected: 全數通過，零回歸（若有既有已知不穩定測試案例，比照 `epic-41`/`epic-43` Issue 1 慣例於 PR 描述註明，不視為本 Issue 造成的回歸）

- [x] **Step 3: 於 `plan-issue-2.md` 標記全部 Task 完成**

將本檔案所有 `- [x]` 改為 `- [x]`。

- [x] **Step 4: 發起獨立程式審查**

比照 `docs/agents/issue-tracker.md`／`sdd-workflow` 既有流程，使用 `/superpowers:requesting-code-review` 對本次異動（`git diff` 對比 Task 1 之前的 commit）發起審查，結果存至 `docs/epics/epic-43-reader-architecture-hardening/reviews/review-issue-2.md`（不進版控）。
