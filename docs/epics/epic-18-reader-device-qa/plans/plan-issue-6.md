# Issue 6 實作計畫：流式 EPUB「欄數」三態控制 +「欄位大小」閾值 (v2 複審修正版)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用「欄數（Column Mode）」三態選擇（自動/單欄/雙欄）+「欄位大小（Column Size）」閾值滑桿取代現有的 `singleColumn` 布林開關，並修復直排 EPUB 在多數裝置上因 paginator.js `+1` 邏輯導致單欄開關無效及大螢幕出現三欄的問題。

**Architecture:** 
透傳 `columnMode`（enum: auto, single, double）與 `columnSize`（double: 360~1440, 預設 720.0）從 `ReaderSettingsSheet` 到 `BookReaderPrefs` (SQLite v13) 與 `ResolvedPreferences`。原生層 `FoliateEpubReaderView` 將兩參數傳至 JavaScript `main.js`，透過 `view.renderer.setAttribute('max-inline-size', ...)` 動態控制 paginator.js 的分欄閾值，實現徹底繞過 paginator 直排 `+1` 限制的單欄/雙欄/自動分欄效果。

**Tech Stack:** Flutter, Dart, SQLite (sqflite), JavaScript (foliate-js paginator API), Android MethodChannel.

## Global Constraints

- 所有敘述與文件保持正體中文 (zh-TW)。
- 靜態檢查 `flutter analyze` 必須保持零警告零錯誤。
- 單元測試 `flutter test` 必須全數通過。
- 專案約束：不得改動 `foliate-js` 既有 vendored 原始碼檔案。
- SQLite Migration 陷阱：對 `book_reader_prefs` 追加欄位之 `if (oldVersion < 13)` 必須放在 `onUpgrade` 的 `else` 分支內（`oldVersion >= 2`），避免 `oldVersion == 1` 的裝置觸發 `duplicate column name` 例外崩潰。

---

### Task 1: 定義 `ColumnMode` Enum 與更新 `BookReaderPrefs`

**Files:**
- Create: `app/lib/reader/column_mode.dart`
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Test: `app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Consumes: N/A
- Produces: `ColumnMode` enum (`auto`, `single`, `double`), `BookReaderPrefs.columnMode`, `BookReaderPrefs.columnSize`

- [ ] **Step 1: 建立 `app/lib/reader/column_mode.dart` 檔案**

```dart
/// 流式 EPUB 專屬的分欄模式偏好（epic-18 Issue 6）。
enum ColumnMode {
  /// 自動（由 foliate-js paginator.js 依 [columnSize] 欄位大小閾值自由決定欄數）。
  auto,

  /// 強制單欄（不論螢幕幾何或排版方向，強制單頁排版）。
  single,

  /// 硬限雙欄（最多 2 欄）。
  double,
}
```

- [ ] **Step 2: 撰寫 `BookReaderPrefs` 測試**

修改 `app/test/reader/book_reader_prefs_test.dart`，移除 `singleColumn` 測試，改為測試 `columnMode` 與 `columnSize`：

```dart
    test('columnMode 與 columnSize 預設為 null（未覆寫）', () {
      const prefs = BookReaderPrefs.empty;
      expect(prefs.columnMode, isNull);
      expect(prefs.columnSize, isNull);
    });

    test('columnMode 與 columnSize 相同的 BookReaderPrefs 視為相等', () {
      const a = BookReaderPrefs(columnMode: ColumnMode.single, columnSize: 800);
      const b = BookReaderPrefs(columnMode: ColumnMode.single, columnSize: 800);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('toMap 與 fromMap 正確轉換 columnMode 與 columnSize', () {
      const prefs = BookReaderPrefs(columnMode: ColumnMode.double, columnSize: 600);
      final map = prefs.toMap('b1');
      expect(map['column_mode'], 'double');
      expect(map['column_size'], 600.0);

      final restored = BookReaderPrefs.fromMap(map);
      expect(restored.columnMode, ColumnMode.double);
      expect(restored.columnSize, 600.0);
    });

    test('copyWith 正確更新 columnMode 與 columnSize', () {
      const original = BookReaderPrefs(fontSize: 18);
      final updated = original.copyWith(columnMode: ColumnMode.single, columnSize: 900);
      expect(updated.fontSize, 18);
      expect(updated.columnMode, ColumnMode.single);
      expect(updated.columnSize, 900.0);
    });
```

- [ ] **Step 3: 執行測試並確認失敗**

Run: `flutter test test/reader/book_reader_prefs_test.dart`
Expected: FAIL (欄位未存在)

- [ ] **Step 4: 修改 `BookReaderPrefs` 移除 `singleColumn` 並加入 `columnMode` / `columnSize`**

在 `app/lib/reader/book_reader_prefs.dart` 中：
- 匯入 `column_mode.dart`
- 移除 `final bool? singleColumn;` (Line 46)
- 新增 `final ColumnMode? columnMode;` 與 `final double? columnSize;`
- 在建構子、`toMap` ('column_mode', 'column_size')、`fromMap` (解析 enum 與 double)、`==`、`hashCode`、`copyWith` 中更換對應欄位。

- [ ] **Step 5: 執行測試確認通過**

Run: `flutter test test/reader/book_reader_prefs_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/column_mode.dart app/lib/reader/book_reader_prefs.dart app/test/reader/book_reader_prefs_test.dart
git commit -m "feat(reader): 定義 ColumnMode 並於 BookReaderPrefs 新增 columnMode 與 columnSize 欄位"
```

---

### Task 2: SQLite Schema Migration v12 -> v13 (含舊值清零與防禦位置)

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: `BookReaderPrefs.columnMode`, `BookReaderPrefs.columnSize`
- Produces: SQLite `book_reader_prefs` table version 13 with `column_mode TEXT` and `column_size REAL`, with `single_column` migrated to NULL.

- [ ] **Step 1: 在 `sqlite_library_repository_test.dart` 撰寫 Migration 測試**

在 `app/test/library/sqlite_library_repository_test.dart` 中：
1. 更新全新安裝測試：`CREATE TABLE` 後包含 `column_mode` 與 `column_size`（無 `single_column`）。
2. 新增 v11 → v12 → v13 三段式升級測試：建立 v11 舊版 Schema，寫入 `single_column: 1` 的舊資料，開啟資料庫觸發 Migration 至 v13。驗證 `single_column` 變為 `NULL`，且 `column_mode`/`column_size` 可正常寫入與讀取。
3. 更新既有 v11→v12 測試的註解與說明（標明已自動升級至 v13）。

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL (schema version 仍為 12)

- [ ] **Step 3: 修改 `SqliteLibraryRepository` 提升 Version 至 13 並實作 Migration**

在 `app/lib/library/sqlite_library_repository.dart` 中：
- 將版本更新為 `version: 13` (Line 30)
- `_createBookReaderPrefsTable` 中移除 `single_column INTEGER`，新增 `column_mode TEXT, column_size REAL`
- 在 `onUpgrade` 的 **`else` 分支內（`oldVersion >= 2`）** 加上 `if (oldVersion < 13)`：
  ```dart
  } else {
    // book_reader_prefs 表已存在（oldVersion >= 2），依序 ALTER TABLE 追加新欄位
    if (oldVersion < 3) {
      await _addPdfReaderPrefsColumns(db);
    }
    if (oldVersion < 4) {
      await _addDualPageColumns(db);
    }
    if (oldVersion < 7) {
      await _addHeaderFooterColumns(db);
    }
    if (oldVersion < 12) {
      await _addSingleColumnColumn(db);
    }
    if (oldVersion < 13) {
      // epic-18-reader-device-qa Issue 6：欄數/欄位大小新增的 2 個欄位。
      // 必須放在 else 分支內（oldVersion >= 2）——理由同 _addSingleColumnColumn：
      // oldVersion < 2 時 _createBookReaderPrefsTable 已一步到位建表含 column_mode/column_size，
      // 若在 else 分支外無條件執行 ALTER TABLE，oldVersion == 1 的裝置會重複 ALTER TABLE 拋出崩潰。
      await _addColumnModeColumns(db);
    }
  }
  ```
- 實作 `_addColumnModeColumns`（含 issues.md 說明的 `single_column` 舊值遷移為 NULL）：
  ```dart
  static Future<void> _addColumnModeColumns(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute('ALTER TABLE book_reader_prefs ADD COLUMN column_mode TEXT');
      await db.execute('ALTER TABLE book_reader_prefs ADD COLUMN column_size REAL');
      // issues.md 明確要求：既有 single_column 欄位所有值遷移為 NULL（等同自動）
      await db.execute('UPDATE book_reader_prefs SET single_column = NULL');
    }
  }
  ```

- [ ] **Step 4: 執行測試驗證通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(db): 升級 SQLite DB 版本至 v13，新增 column_mode 與 column_size 欄位並遷移舊值"
```

---

### Task 3: 解析層 (`ResolvedPreferences` & `ReaderPrefsManager`) 與原生 PlatformView 介面 (`FoliateEpubReaderView`)

**Files:**
- Modify: `app/lib/reader/resolved_preferences.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`
- Test: `app/test/screens/reader_screen_test.dart`
- Test: `app/test/reader/resolved_preferences_test.dart`
- Test: `app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Consumes: `ColumnMode`, `BookReaderPrefs.columnMode`, `BookReaderPrefs.columnSize`
- Produces: `ResolvedPreferences.columnMode` (non-nullable, default `auto`), `ResolvedPreferences.columnSize` (non-nullable, default `720.0`), `FoliateEpubReaderView.columnMode`, `FoliateEpubReaderView.columnSize`

- [ ] **Step 1: 修改測試檔 (修正受 `singleColumn` 移除影響的所有單元測試)**

1. `app/test/reader/foliate_epub_reader_view_test.dart`：
   - 將 `singleColumn: true` 改為 `columnMode: ColumnMode.single, columnSize: 800.0` 測試 `initialPreferences`
   - `didUpdateWidget` 變更時測試帶入新值 `columnMode` 與 `columnSize`
2. `app/test/reader/resolved_preferences_test.dart`：
   - 將 `singleColumn: null` 建構與 `.singleColumn` 斷言改為 `columnMode: ColumnMode.auto, columnSize: 720.0`
3. `app/test/reader/reader_prefs_manager_test.dart`：
   - 將 `singleColumn: true/null` 測試改為 `columnMode: ColumnMode.single/auto` 及 `columnSize: 800.0/720.0`
4. `app/test/screens/reader_screen_test.dart`：
   - 更新 FoliateEpubReaderView 斷言：`expect(updatedView.columnMode, ColumnMode.single)`

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/foliate_epub_reader_view_test.dart test/reader/resolved_preferences_test.dart test/reader/reader_prefs_manager_test.dart`
Expected: FAIL (欄位未更新)

- [ ] **Step 3: 更新 `ResolvedPreferences` 與 `ReaderPrefsManagerImpl`**

1. 在 `app/lib/reader/resolved_preferences.dart`：
   - 替換 `final bool? singleColumn;` 為 `final ColumnMode columnMode;` 與 `final double columnSize;`
   - 建構子中指定：`this.columnMode = ColumnMode.auto, this.columnSize = 720.0`
2. 在 `app/lib/reader/reader_prefs_manager_impl.dart`：
   - `columnMode: book.columnMode ?? ColumnMode.auto`
   - `columnSize: book.columnSize ?? 720.0`

- [ ] **Step 4: 更新 `FoliateEpubReaderView` 與 `ReaderScreen`**

1. 在 `app/lib/reader/foliate_epub_reader_view.dart`：
   - 替換 `singleColumn` 為 `final ColumnMode? columnMode;` 與 `final double? columnSize;`
   - `_preferencesChanged` 檢查 `widget.columnMode != oldWidget.columnMode || widget.columnSize != oldWidget.columnSize`
   - `_buildPreferencesMap`:
     ```dart
     if (widget.columnMode != null) {
       map['columnMode'] = widget.columnMode!.name;
     }
     if (widget.columnSize != null) {
       map['columnSize'] = widget.columnSize;
     }
     ```
2. 在 `app/lib/screens/reader_screen.dart`：
   - 傳遞 `columnMode: resolved.columnMode` 與 `columnSize: resolved.columnSize` 給 `FoliateEpubReaderView`

- [ ] **Step 5: 執行測試驗證通過**

Run: `flutter test test/reader/foliate_epub_reader_view_test.dart test/reader/resolved_preferences_test.dart test/reader/reader_prefs_manager_test.dart test/screens/reader_screen_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/resolved_preferences.dart app/lib/reader/reader_prefs_manager_impl.dart app/lib/reader/foliate_epub_reader_view.dart app/lib/screens/reader_screen.dart app/test/reader/foliate_epub_reader_view_test.dart app/test/reader/resolved_preferences_test.dart app/test/reader/reader_prefs_manager_test.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(reader): 於 ResolvedPreferences 與 FoliateEpubReaderView 支援 columnMode 與 columnSize"
```

---

### Task 4: JavaScript 端渲染控制 (`main.js`) (修正算式 C1 與動態 Resize I3)

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: `prefs.columnMode` ('auto', 'single', 'double'), `prefs.columnSize` (number)
- Produces: Dynamic DOM attribute mutation on `view.renderer` (`max-inline-size`)

- [ ] **Step 1: 修改 `main.js` 中的 `applyPreferences` 與 `updateLayout` 計算**

在 `app/android/app/src/main/assets/foliate/main.js` 中：

```javascript
  // Issue 6：欄數（columnMode）與欄位大小（columnSize）控制。
  // 用 max-inline-size 控制分欄閾值，徹底解決 paginator.js 對直排書籍 max-column-count 的 +1 邏輯問題。
  if (prefs.columnMode === 'single') {
    // 強制單欄：設定極大 inline-size 確保 ceil(hostSize / maxInlineSize) 永遠為 1
    view.renderer.setAttribute('max-inline-size', '99999px')
  } else if (prefs.columnMode === 'double') {
    // 硬限雙欄：計算 hostSize 並將 max-inline-size 設為 Math.ceil(hostSize / 2)
    // 注意：必須使用 Math.ceil 而非 Math.floor，保證 targetSize * 2 >= hostSize，
    // 避免奇數/帶小數 hostSize 算出的 targetSize 偏小導致 ceil(hostSize / targetSize) 變成 3 欄！
    const hostRect = view.renderer.getBoundingClientRect()
    const hostSize = currentWritingMode === 'vertical' ? hostRect.height : hostRect.width
    const targetSize = Math.max(360, Math.ceil(hostSize / 2))
    view.renderer.setAttribute('max-inline-size', `${targetSize}px`)
  } else {
    // 自動模式：使用使用者設定的 columnSize（預設 720px）
    const size = prefs.columnSize || 720
    view.renderer.setAttribute('max-inline-size', `${size}px`)
  }
```

- [ ] **Step 2: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(foliate): 在 main.js 中依 columnMode 與 columnSize 正確動態設定 max-inline-size"
```

---

### Task 5: UI 控制元件 (`ReaderSettingsSheet`) 升級 (明確測試 M1)

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: `BookReaderPrefs.columnMode`, `BookReaderPrefs.columnSize`
- Produces: `ColumnMode` selection row + `columnSize` Slider (conditional) in `ReaderSettingsSheet`

- [ ] **Step 1: 更新 `reader_settings_sheet_test.dart` 測試檔**

將原本的 `SwitchListTile` 測試替換為三態「欄數」分段按鈕與「欄位大小」Slider 測試：
1. 驗證按鈕與 Slider 預設狀態。
2. 點選「單欄」按鈕（`Key('reader_settings_column_mode_single')`）後 `onChanged` 傳回 `columnMode == ColumnMode.single`。
3. 切換到「單欄」或「雙欄」後，確認 Slider 元件不顯示（`expect(find.byKey(const Key('reader_settings_column_size_slider')), findsNothing);`）。
4. 點選「自動」時 Slider 可見且可調，滑動傳回新 `columnSize`。

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: FAIL

- [ ] **Step 3: 實作 `ReaderSettingsSheet` 中的「欄數」三態按鈕與「欄位大小」滑桿**

在 `app/lib/screens/reader_settings_sheet.dart` 中：
- 宣告 `late ColumnMode _columnMode;` 與 `late double _columnSize;`
- `initState` / `didUpdateWidget` 初始化：
  ```dart
  _columnMode = widget.prefs.columnMode ?? ColumnMode.auto;
  _columnSize = widget.prefs.columnSize ?? 720.0;
  ```
- 在 `_notifyChanged` 帶入 `columnMode: _columnMode, columnSize: _columnSize`
- 新增 `_buildColumnModeRow()` 方法：
  ```dart
  Widget _buildColumnModeRow() {
    const options = [
      (ColumnMode.auto, 'auto', Icons.auto_awesome, '自動'),
      (ColumnMode.single, 'single', Icons.crop_portrait, '單欄'),
      (ColumnMode.double, 'double', Icons.book, '雙欄'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('欄數'),
        Wrap(
          spacing: 4,
          children: options.map((option) {
            final (mode, keySuffix, icon, tooltip) = option;
            final selected = _columnMode == mode;
            return IconButton(
              key: Key('reader_settings_column_mode_$keySuffix'),
              icon: Icon(icon),
              tooltip: tooltip,
              color: selected ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => setState(() {
                _columnMode = mode;
                _notifyChanged();
              }),
            );
          }).toList(),
        ),
        if (_columnMode == ColumnMode.auto) ...[
          const SizedBox(height: 8),
          Text('欄位大小 ${_columnSize.round()}px'),
          Slider(
            key: const Key('reader_settings_column_size_slider'),
            value: _columnSize,
            min: 360.0,
            max: 1440.0,
            divisions: 18, // (1440 - 360) / 60 = 18
            label: '${_columnSize.round()}px',
            onChanged: (v) => setState(() {
              _columnSize = v;
              _notifyChanged();
            }),
          ),
        ],
      ],
    );
  }
  ```
- 替換原本 `SwitchListTile` 為 `_buildColumnModeRow()`。

- [ ] **Step 4: 執行測試驗證通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(ui): 升級 ReaderSettingsSheet 提供欄數三態選擇與欄位大小滑桿"
```

---

### Task 6: 整合測試完整更新與全套驗證 (修正 C4)

**Files:**
- Modify: `app/integration_test/foliate_single_column_test.dart`

**Interfaces:**
- Consumes: All updated interfaces (`ColumnMode.single`, `ColumnMode.auto`)

- [ ] **Step 1: 更新 `foliate_single_column_test.dart` 中的兩個測試**

修改 `app/integration_test/foliate_single_column_test.dart`：
1. 第一個測試（連續翻頁遞增驗證）：將 `singleColumn: true` 改為 `columnMode: ColumnMode.single`，保留 pageIndex 遞增斷言。
2. 第二個測試（偏好持久化連動驗證）：
   - `BookReaderPrefs(singleColumn: true)` 改為 `BookReaderPrefs(columnMode: ColumnMode.single)`
   - 替換 `SwitchListTile` / `Key('reader_settings_single_column')` 斷言：改為尋找 `IconButton`（`Key('reader_settings_column_mode_single')`），斷言其 `color` 等於 `Theme.of(context).colorScheme.primary`（選中狀態）。

- [ ] **Step 2: 執行 `flutter analyze` 確保語法與型態檢查無誤**

Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 3: 執行全套單元測試**

Run: `flutter test`
Expected: All tests pass!

- [ ] **Step 4: Commit**

```bash
git add app/integration_test/foliate_single_column_test.dart
git commit -m "test(integration): 更新 foliate_single_column_test 以合乎 columnMode 介面與全新 UI"
```

---

## Plan Self-Review Checklist

1. **Spec coverage**:
   - 三態選項（自動/單欄/雙欄）? -> Task 1, Task 3, Task 4, Task 5
   - 欄位大小滑桿 (360-1440px, step 60, default 720)? -> Task 1, Task 3, Task 4, Task 5
   - 僅自動模式顯示滑桿? -> Task 5
   - SQLite Migration v12->v13 舊值清零與防禦位置? -> Task 2
   - main.js Math.ceil 修正 off-by-one? -> Task 4
   - 所有層級單元測試與整合測試更新 (含 resolved_preferences_test, reader_prefs_manager_test 等遺漏檔案)? -> Task 1~6

2. **Placeholder scan**: 無任何 TODO / TBD / implement later 佔位符。
3. **Type consistency**: 統一使用 `ColumnMode` enum (`auto`, `single`, `double`) 與 `columnSize` (`double`)。
