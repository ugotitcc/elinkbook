# Epic 14 Issue 2 — 字型管理畫面 + 單書字型選擇器整合 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> 本計畫經 `/superpowers:requesting-code-review` 審查（`tmp/epic-14/review-plan-issue-2.md`）與 `/superpowers:receiving-code-review` 核對修訂：修正 1 項 Critical（自訂字型與內建字型 family name 重名會導致 `DropdownButton` 崩潰）、2 項 Important（`_customFonts` 載入缺錯誤處理、缺重名阻擋測試），詳見文末「審查修正紀錄」。

**Goal:** 新建字型管理畫面（批次上傳 `.ttf`/`.otf`、清單顯示內建+自訂、重新命名、刪除含使用中提示與級聯重置），並把既有單書字型選擇器（`reader_settings_sheet.dart`）從「只列內建 5 款」擴充為「合併內建 5 款＋自訂字型清單」。純 Dart + SQLite + `file_picker`，不涉及原生程式碼渲染，不需要真實裝置（真正把自訂字型實際渲染到 WebView 是 Issue 3 的範圍）。

**Architecture:** 沿用本專案既有的「Repository 直接包一層 `Database`＋對應純 Dart model」模式（`Bookmark`/`BookmarksRepository` 為對照組）；`CustomFontsRepository` 與既有 `SqliteLibraryRepository` 共用同一個 `Database` 連線（`custom_fonts`/`book_reader_prefs` 的級聯更新需要同一個連線內的 transaction）。畫面/資料存取層透過既有「可選具名建構參數＋預設值」慣例，逐層貫穿 `main.dart` → `ElinkBookApp` → `LibraryScreen` → `SettingsScreen`／`ReaderScreen`，零回歸（既有大量測試呼叫端不需要逐一補上新參數）。

**Tech Stack:** Flutter/Dart、`sqflite`、`file_picker: ^11.0.2`（`FilePicker.pickFiles`，非 `.platform.pickFiles`——這個版本已簡化為直接靜態方法，見 `file_picker-11.0.2/lib/src/file_picker.dart:57`）。

## Global Constraints

- **前置依賴（Issue 1 已完成並合併）**：`custom_fonts` 表已存在（`id`／`display_name`／`family_name UNIQUE`／`font_uri`）；`book_reader_prefs.font_family` 已是 `String?`；`app/lib/reader/font_name_parser.dart` 已提供頂層函式 `String? parseFontFamilyName(Uint8List bytes)`（找不到可用 family name 時回傳 `null`，本 Issue 負責退回檔名）。
- **重複阻擋一律以 family name 為準**：`custom_fonts.family_name` 已有 `UNIQUE` 約束，`CustomFontsRepository` 插入前先查詢是否已存在，存在則不寫入、計入「已存在」計數（比照 `epic-21` `ImportResult` 合併訊息模式，見 `library_screen.dart:182-199` 的 `_showImportResultSnackBar` 既有寫法）。
- **刪除級聯**：`custom_fonts` 刪除與 `book_reader_prefs.font_family` 重置為 `NULL` 必須在同一個 SQLite `transaction` 內完成（避免中途失敗留下不一致狀態）。
- **不落地字型檔複本**（[ADR 0021](../../adr/0021-custom-font-content-uri-no-copy.md)）：`font_uri` 存 `content://` URI 本身，只做 `takePersistableUriPermission()`（沿用 `elinkbook/book_metadata` channel，`book_import_service_impl.dart:106-109` 既有呼叫方式）；本 Issue 只需要一次性讀取位元組給解析器用（`file_picker` 的 `withData: true`），不涉及後續實際渲染時的原生讀取（Issue 3 範圍）。
- **內建字型清單不可變動**：`reader_settings_sheet.dart` 的既有 5 款內建字型（`AppFont.values`）與其中文顯示名稱（`_fontDisplayName`）維持不動，只在既有清單後面接上自訂字型清單。
- **本 Issue 不做原生渲染**：字型選妥後即使是自訂字型，實際排版顯示效果本 Issue 不驗證（該路徑要到 Issue 3 才會被打通），只驗證「選擇/持久化」這段資料流正確。
- **既有慣例**：新增的可選具名參數一律有預設值／nullable，未提供時退回本 Issue 之前的行為（零回歸）；批次刪除/危險操作一律先跳 `AlertDialog` 確認（比照 `library_screen.dart:344-365` 的 `_confirmDeleteBooks` 既有寫法）。

---

### Task 1：`CustomFont` model + `CustomFontsRepository`

**Files:**
- Create：`app/lib/reader/custom_font.dart`
- Create：`app/lib/reader/custom_fonts_repository.dart`
- Create：`app/test/support/fake_custom_fonts_repository.dart`
- Test：`app/test/reader/custom_fonts_repository_test.dart`

**Interfaces:**
- Consumes：無（Issue 1 的 `custom_fonts` 表 schema 已存在）
- Produces：`CustomFont`（`id`／`displayName`／`familyName`／`fontUri`）；`CustomFontsRepository`（`listAll()`／`familyNameExists(String)`／`insert(CustomFont)`／`rename(int, String)`／`countBooksUsing(String)`／`deleteAndResetUsage(int, String)`），供 Task 2（`FontManagementScreen`）與 Task 4（`reader_settings_sheet.dart`）使用

- [x] **Step 1：撰寫失敗測試——`CustomFont` model round-trip**

新建 `app/test/reader/custom_fonts_repository_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/custom_fonts_repository.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('CustomFont.toMap／fromMap round-trip 保留所有欄位', () {
    const font = CustomFont(
      id: 1,
      displayName: '我的字型',
      familyName: 'MyFamily',
      fontUri: 'content://example/font1',
    );
    final map = font.toMap();
    expect(map['display_name'], '我的字型');
    expect(map['family_name'], 'MyFamily');
    expect(map['font_uri'], 'content://example/font1');
    expect(map.containsKey('id'), isFalse); // 新增用 toMap 刻意不含 id，交由 AUTOINCREMENT 指派

    final restoredMap = {'id': 1, ...map};
    final restored = CustomFont.fromMap(restoredMap);
    expect(restored, font);
  });

  group('CustomFontsRepository', () {
    late SqliteLibraryRepository libraryRepository;
    late CustomFontsRepository repository;

    setUp(() async {
      libraryRepository =
          await SqliteLibraryRepository.open(inMemoryDatabasePath);
      repository = CustomFontsRepository(libraryRepository.database);
    });

    tearDown(() async {
      await libraryRepository.close();
    });

    test('insert 後 listAll 依 displayName 排序回傳', () async {
      await repository.insert(const CustomFont(
        displayName: 'Zeta 字型',
        familyName: 'ZetaFamily',
        fontUri: 'content://example/zeta',
      ));
      await repository.insert(const CustomFont(
        displayName: 'Alpha 字型',
        familyName: 'AlphaFamily',
        fontUri: 'content://example/alpha',
      ));

      final all = await repository.listAll();
      expect(all.map((f) => f.displayName).toList(),
          ['Alpha 字型', 'Zeta 字型']);
      expect(all.every((f) => f.id != null), isTrue);
    });

    test('familyNameExists 正確反映是否已存在', () async {
      expect(await repository.familyNameExists('SomeFamily'), isFalse);
      await repository.insert(const CustomFont(
        displayName: 'X',
        familyName: 'SomeFamily',
        fontUri: 'content://example/x',
      ));
      expect(await repository.familyNameExists('SomeFamily'), isTrue);
    });

    test('相同 family_name 重複 insert 拋出例外（UNIQUE 約束）', () async {
      await repository.insert(const CustomFont(
        displayName: 'A',
        familyName: 'DupFamily',
        fontUri: 'content://example/a',
      ));
      expect(
        () => repository.insert(const CustomFont(
          displayName: 'B',
          familyName: 'DupFamily',
          fontUri: 'content://example/b',
        )),
        throwsA(anything),
      );
    });

    test('rename 只更新 displayName，familyName／fontUri 不變', () async {
      final id = await repository.insert(const CustomFont(
        displayName: '舊名稱',
        familyName: 'RenameFamily',
        fontUri: 'content://example/r',
      ));

      await repository.rename(id, '新名稱');

      final all = await repository.listAll();
      final renamed = all.single;
      expect(renamed.displayName, '新名稱');
      expect(renamed.familyName, 'RenameFamily');
      expect(renamed.fontUri, 'content://example/r');
    });

    test('countBooksUsing 正確統計 book_reader_prefs 使用中筆數', () async {
      await libraryRepository.insertBook(_book('b1'));
      await libraryRepository.insertBook(_book('b2'));
      await libraryRepository.insertBook(_book('b3'));
      final db = libraryRepository.database;
      await db.insert('book_reader_prefs',
          {'book_id': 'b1', 'font_family': 'UsedFamily'});
      await db.insert('book_reader_prefs',
          {'book_id': 'b2', 'font_family': 'UsedFamily'});
      await db.insert(
          'book_reader_prefs', {'book_id': 'b3', 'font_family': 'Other'});

      expect(await repository.countBooksUsing('UsedFamily'), 2);
      expect(await repository.countBooksUsing('Other'), 1);
      expect(await repository.countBooksUsing('Unused'), 0);
    });

    test('deleteAndResetUsage 於同一交易內刪除字型並把使用中書籍重置為 NULL',
        () async {
      await libraryRepository.insertBook(_book('b1'));
      await libraryRepository.insertBook(_book('b2'));
      final db = libraryRepository.database;
      await db.insert('book_reader_prefs',
          {'book_id': 'b1', 'font_family': 'ToDeleteFamily'});
      await db.insert('book_reader_prefs',
          {'book_id': 'b2', 'font_family': 'KeepFamily'});
      final id = await repository.insert(const CustomFont(
        displayName: '待刪除字型',
        familyName: 'ToDeleteFamily',
        fontUri: 'content://example/del',
      ));

      await repository.deleteAndResetUsage(id, 'ToDeleteFamily');

      expect(await repository.listAll(), isEmpty);
      final row1 = (await db.query('book_reader_prefs',
              where: 'book_id = ?', whereArgs: ['b1']))
          .single;
      expect(row1['font_family'], isNull);
      final row2 = (await db.query('book_reader_prefs',
              where: 'book_id = ?', whereArgs: ['b2']))
          .single;
      expect(row2['font_family'], 'KeepFamily'); // 不相關的書籍不受影響
    });
  });
}
```

在檔案最上方（`import` 區塊之後、`void main()` 之前）新增測試用的書籍建構輔助函式（比照 `sqlite_library_repository_test.dart:12-34` 既有的 `_book()` 寫法）：

```dart
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

Book _book(String id) {
  return Book(
    id: id,
    title: '書名 $id',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    progress: 0,
    groupName: '未分類',
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}
```

（把這兩行 import 與 `_book()` 函式放在檔案最上方，`void main()` 之前，與其他 `import` 語句放在一起。）

- [x] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/reader/custom_fonts_repository_test.dart
```

Expected：FAIL——`package:elinkbook/reader/custom_font.dart`／`custom_fonts_repository.dart` 找不到。

- [x] **Step 3：建立 `custom_font.dart`**

```dart
/// 使用者上傳的自訂字型（epic-14-system-settings FR-35），對應
/// `custom_fonts` 表的一列（見 docs/epics/epic-14-system-settings/spec.md
/// 「字型管理模組」）。字型檔案本身不落地複本（ADR 0021），[fontUri] 存
/// `content://` URI。
class CustomFont {
  /// SQLite 自動指派的 rowid，新增前（尚未寫入資料庫）為 null。
  final int? id;
  final String displayName;
  final String familyName;
  final String fontUri;

  const CustomFont({
    this.id,
    required this.displayName,
    required this.familyName,
    required this.fontUri,
  });

  /// 供 [CustomFontsRepository.insert] 使用；刻意不含 `id`——新增一律交由
  /// SQLite `AUTOINCREMENT` 指派。
  Map<String, Object?> toMap() {
    return {
      'display_name': displayName,
      'family_name': familyName,
      'font_uri': fontUri,
    };
  }

  factory CustomFont.fromMap(Map<String, Object?> map) {
    return CustomFont(
      id: map['id'] as int?,
      displayName: map['display_name'] as String,
      familyName: map['family_name'] as String,
      fontUri: map['font_uri'] as String,
    );
  }

  CustomFont copyWith({String? displayName}) {
    return CustomFont(
      id: id,
      displayName: displayName ?? this.displayName,
      familyName: familyName,
      fontUri: fontUri,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CustomFont &&
      other.id == id &&
      other.displayName == displayName &&
      other.familyName == familyName &&
      other.fontUri == fontUri;

  @override
  int get hashCode => Object.hash(id, displayName, familyName, fontUri);

  @override
  String toString() =>
      'CustomFont(id: $id, displayName: $displayName, familyName: $familyName, fontUri: $fontUri)';
}
```

- [x] **Step 4：建立 `custom_fonts_repository.dart`**

```dart
import 'package:sqflite/sqflite.dart';

import 'custom_font.dart';

/// `custom_fonts` 表的存取層（epic-14-system-settings Issue 2，spec.md
/// 「字型管理模組」）。與 [SqliteLibraryRepository] 共用同一個 [Database]
/// 連線，比照既有 `BookmarksRepository`／`HighlightsRepository` 模式。
class CustomFontsRepository {
  final Database _db;

  const CustomFontsRepository(this._db);

  Future<List<CustomFont>> listAll() async {
    final rows = await _db.query('custom_fonts', orderBy: 'display_name ASC');
    return rows.map(CustomFont.fromMap).toList();
  }

  Future<bool> familyNameExists(String familyName) async {
    final rows = await _db.query(
      'custom_fonts',
      where: 'family_name = ?',
      whereArgs: [familyName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 回傳 SQLite 自動指派的 rowid。呼叫端須先以 [familyNameExists] 確認
  /// 不重複——本方法本身不做重複檢查，交由 `family_name UNIQUE` 約束
  /// 兜底（重複時拋出 [DatabaseException]）。
  Future<int> insert(CustomFont font) {
    return _db.insert('custom_fonts', font.toMap());
  }

  Future<void> rename(int id, String newDisplayName) {
    return _db.update(
      'custom_fonts',
      {'display_name': newDisplayName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 統計 `book_reader_prefs` 中目前使用中 [familyName] 的書籍數量，供刪除
  /// 前的確認對話框文案使用。
  Future<int> countBooksUsing(String familyName) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM book_reader_prefs WHERE font_family = ?',
      [familyName],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// 刪除字型並把所有使用中書籍的 `font_family` 重置為 `NULL`（FR-09 規則：
  /// 刪除使用中字型時自動退回預設字型），於同一交易內完成避免中途失敗留下
  /// 不一致狀態。
  Future<void> deleteAndResetUsage(int id, String familyName) async {
    await _db.transaction((txn) async {
      await txn.delete('custom_fonts', where: 'id = ?', whereArgs: [id]);
      await txn.update(
        'book_reader_prefs',
        {'font_family': null},
        where: 'font_family = ?',
        whereArgs: [familyName],
      );
    });
  }
}
```

- [x] **Step 5：執行測試，確認通過**

```bash
flutter test test/reader/custom_fonts_repository_test.dart
```

Expected：全數 PASS。

- [x] **Step 6：建立測試用 Fake（供 Task 2 widget test 使用）**

新建 `app/test/support/fake_custom_fonts_repository.dart`（比照 `app/test/support/fake_bookmarks_repository.dart` 既有模式）：

```dart
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/custom_fonts_repository.dart';

/// 測試用 Fake，比照 [FakeBookmarksRepository] 模式。不共用真實
/// `book_reader_prefs` 表資料，[countBooksUsing] 改由 [usageCounts] 手動
/// 設定回傳值（widget test 不需要真的建一個資料庫連線）。
class FakeCustomFontsRepository implements CustomFontsRepository {
  final List<CustomFont> _storage = [];
  int _nextId = 1;

  /// 測試預先設定「這個 family name 目前有幾本書使用中」，供
  /// [countBooksUsing] 回傳；未設定的 family name 預設回傳 0。
  final Map<String, int> usageCounts = {};

  @override
  Future<List<CustomFont>> listAll() async {
    final list = List<CustomFont>.from(_storage);
    list.sort((a, b) => a.displayName.compareTo(b.displayName));
    return list;
  }

  @override
  Future<bool> familyNameExists(String familyName) async {
    return _storage.any((f) => f.familyName == familyName);
  }

  @override
  Future<int> insert(CustomFont font) async {
    final id = _nextId++;
    _storage.add(CustomFont(
      id: id,
      displayName: font.displayName,
      familyName: font.familyName,
      fontUri: font.fontUri,
    ));
    return id;
  }

  @override
  Future<void> rename(int id, String newDisplayName) async {
    final index = _storage.indexWhere((f) => f.id == id);
    if (index == -1) return;
    _storage[index] = _storage[index].copyWith(displayName: newDisplayName);
  }

  @override
  Future<int> countBooksUsing(String familyName) async {
    return usageCounts[familyName] ?? 0;
  }

  @override
  Future<void> deleteAndResetUsage(int id, String familyName) async {
    _storage.removeWhere((f) => f.id == id);
  }
}
```

- [x] **Step 7：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/reader/custom_font.dart lib/reader/custom_fonts_repository.dart test/reader/custom_fonts_repository_test.dart test/support/fake_custom_fonts_repository.dart
git commit -m "feat(epic-14): CustomFont model + CustomFontsRepository"
```

Expected：`flutter analyze` "No issues found!"。

---

### Task 2：`FontManagementScreen`（批次上傳／清單／重新命名／刪除）

**Files:**
- Create：`app/lib/screens/font_management_screen.dart`
- Test：`app/test/screens/font_management_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `CustomFont`／`CustomFontsRepository`（含 Fake）；`app/lib/reader/font_name_parser.dart` 的 `parseFontFamilyName(Uint8List)`；`app/lib/reader/app_font.dart` 的 `AppFont.values`／`AppFontFamilyName.familyName`
- Produces：`FontManagementScreen` widget（`required CustomFontsRepository repository`），供 Task 3 的 `SettingsScreen` 導航使用

- [ ] **Step 1：撰寫失敗測試——清單顯示內建+自訂字型**

新建 `app/test/screens/font_management_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/screens/font_management_screen.dart';
import '../support/fake_custom_fonts_repository.dart';

void main() {
  late FakeCustomFontsRepository repository;

  setUp(() {
    repository = FakeCustomFontsRepository();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FontManagementScreen(repository: repository),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('顯示標題與 5 款內建字型（無操作按鈕）', (tester) async {
    await pumpScreen(tester);

    expect(find.text('字型管理'), findsOneWidget);
    expect(find.text('思源黑體'), findsOneWidget);
    expect(find.text('思源宋體'), findsOneWidget);
    expect(find.text('原俠正楷'), findsOneWidget);
    expect(find.text('台灣圓體'), findsOneWidget);
    expect(find.text('源流明體'), findsOneWidget);
    expect(find.byKey(const Key('font_management_upload_button')),
        findsOneWidget);
  });

  testWidgets('顯示已存在的自訂字型，含重新命名與刪除按鈕', (tester) async {
    await repository.insert(const CustomFont(
      displayName: '我的自訂字型',
      familyName: 'MyCustomFamily',
      fontUri: 'content://example/font1',
    ));

    await pumpScreen(tester);

    expect(find.text('我的自訂字型'), findsOneWidget);
    expect(
        find.byKey(const Key('font_management_rename_button_1')),
        findsOneWidget);
    expect(
        find.byKey(const Key('font_management_delete_button_1')),
        findsOneWidget);
  });
}
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/font_management_screen_test.dart
```

Expected：FAIL——`package:elinkbook/screens/font_management_screen.dart` 找不到。

- [ ] **Step 3：建立 `FontManagementScreen`（清單顯示部分）**

新建 `app/lib/screens/font_management_screen.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/app_font.dart';
import '../reader/custom_font.dart';
import '../reader/custom_fonts_repository.dart';

/// 字型管理畫面（epic-14-system-settings FR-35，spec.md「字型管理模組」）：
/// 顯示內建 5 款字型（唯讀）＋使用者上傳的自訂字型（可重新命名／刪除），
/// 支援批次上傳 `.ttf`/`.otf`。
class FontManagementScreen extends StatefulWidget {
  final CustomFontsRepository repository;

  const FontManagementScreen({super.key, required this.repository});

  @override
  State<FontManagementScreen> createState() => _FontManagementScreenState();
}

class _FontManagementScreenState extends State<FontManagementScreen> {
  List<CustomFont> _customFonts = [];
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    final fonts = await widget.repository.listAll();
    if (!mounted) return;
    setState(() => _customFonts = fonts);
  }

  String _builtInDisplayName(AppFont font) {
    switch (font) {
      case AppFont.sourceHanSans:
        return '思源黑體';
      case AppFont.sourceHanSerif:
        return '思源宋體';
      case AppFont.guanKiapTsingKhai:
        return '原俠正楷';
      case AppFont.taiwanPearl:
        return '台灣圓體';
      case AppFont.genRyuMinTW:
        return '源流明體';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('字型管理'),
        actions: [
          IconButton(
            key: const Key('font_management_upload_button'),
            icon: _isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            tooltip: '上傳字型',
            onPressed: _isUploading ? null : _pickAndUploadFonts,
          ),
        ],
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('內建字型', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final font in AppFont.values)
            ListTile(title: Text(_builtInDisplayName(font))),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('自訂字型', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (_customFonts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('尚未上傳任何自訂字型'),
            ),
          for (final font in _customFonts)
            ListTile(
              title: Text(font.displayName),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('font_management_rename_button_${font.id}'),
                    icon: const Icon(Icons.edit),
                    tooltip: '重新命名',
                    onPressed: () => _renameFont(font),
                  ),
                  IconButton(
                    key: Key('font_management_delete_button_${font.id}'),
                    icon: const Icon(Icons.delete),
                    tooltip: '刪除',
                    onPressed: () => _deleteFont(font),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadFonts() async {}

  Future<void> _renameFont(CustomFont font) async {}

  Future<void> _deleteFont(CustomFont font) async {}
}
```

（`_pickAndUploadFonts`／`_renameFont`／`_deleteFont` 先留空殼讓 Step 4 的測試能編譯通過，實作在後續 Step 補上。）

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/screens/font_management_screen_test.dart
```

Expected：全數 PASS。

- [ ] **Step 5：撰寫失敗測試——重新命名**

在 `font_management_screen_test.dart` 的 `main()` 內新增：

```dart
  testWidgets('點擊重新命名按鈕，輸入新名稱後清單更新', (tester) async {
    await repository.insert(const CustomFont(
      displayName: '舊名稱',
      familyName: 'RenameFamily',
      fontUri: 'content://example/r',
    ));
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('font_management_rename_button_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('font_management_rename_field')),
        findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('font_management_rename_field')), '新名稱');
    await tester
        .tap(find.byKey(const Key('font_management_rename_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('新名稱'), findsOneWidget);
    expect(find.text('舊名稱'), findsNothing);
  });
```

- [ ] **Step 6：執行測試，確認失敗**

```bash
flutter test test/screens/font_management_screen_test.dart
```

Expected：FAIL——`font_management_rename_field`／`font_management_rename_confirm` 找不到（`_renameFont` 目前是空殼）。

- [ ] **Step 7：實作 `_renameFont`**

```dart
  Future<void> _renameFont(CustomFont font) async {
    final controller = TextEditingController(text: font.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新命名'),
        content: TextField(
          key: const Key('font_management_rename_field'),
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('font_management_rename_confirm'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('確定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || font.id == null) return;
    await widget.repository.rename(font.id!, newName);
    await _loadFonts();
  }
```

- [ ] **Step 8：執行測試，確認通過**

```bash
flutter test test/screens/font_management_screen_test.dart
```

Expected：全數 PASS。

- [ ] **Step 9：撰寫失敗測試——刪除（一般情況與使用中情況兩種文案）**

繼續在 `main()` 內新增：

```dart
  testWidgets('刪除未使用中的字型：確認對話框文案不含使用中提示，確認後清單移除',
      (tester) async {
    await repository.insert(const CustomFont(
      displayName: '未使用字型',
      familyName: 'UnusedFamily',
      fontUri: 'content://example/u',
    ));
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('font_management_delete_button_1')));
    await tester.pumpAndSettle();

    expect(find.text('確定要刪除「未使用字型」嗎？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('font_management_delete_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('未使用字型'), findsNothing);
  });

  testWidgets('刪除使用中的字型：確認對話框文案含使用中書籍數量提示', (tester) async {
    await repository.insert(const CustomFont(
      displayName: '使用中字型',
      familyName: 'UsedFamily',
      fontUri: 'content://example/used',
    ));
    repository.usageCounts['UsedFamily'] = 3;
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('font_management_delete_button_1')));
    await tester.pumpAndSettle();

    expect(find.text('確定要刪除「使用中字型」嗎？'), findsOneWidget);
    expect(find.text('目前有 3 本書使用此字型，刪除後將自動改用預設字型'),
        findsOneWidget);
  });

  testWidgets('刪除對話框點擊取消，字型不受影響', (tester) async {
    await repository.insert(const CustomFont(
      displayName: '保留字型',
      familyName: 'KeepFamily',
      fontUri: 'content://example/k',
    ));
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('font_management_delete_button_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('font_management_delete_cancel')));
    await tester.pumpAndSettle();

    expect(find.text('保留字型'), findsOneWidget);
  });
```

- [ ] **Step 10：執行測試，確認失敗**

```bash
flutter test test/screens/font_management_screen_test.dart
```

Expected：FAIL——`_deleteFont` 目前是空殼，對話框未出現。

- [ ] **Step 11：實作 `_deleteFont`**

```dart
  Future<void> _deleteFont(CustomFont font) async {
    final usageCount = await widget.repository.countBooksUsing(font.familyName);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('確定要刪除「${font.displayName}」嗎？'),
        content: usageCount > 0
            ? Text('目前有 $usageCount 本書使用此字型，刪除後將自動改用預設字型')
            : null,
        actions: [
          TextButton(
            key: const Key('font_management_delete_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('font_management_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true || font.id == null) return;
    await widget.repository.deleteAndResetUsage(font.id!, font.familyName);
    await _loadFonts();
  }
```

- [ ] **Step 12：執行測試，確認通過**

```bash
flutter test test/screens/font_management_screen_test.dart
```

Expected：全數 PASS。

- [ ] **Step 13：撰寫失敗測試——批次上傳合併訊息（重複阻擋）**

繼續在 `main()` 內新增（本測試直接呼叫 `_FontManagementScreenState` 的上傳邏輯核心純函式，見下方 Step 14 抽出的 `resolveUploadOutcome`，不透過 `file_picker` 實際彈出系統選擇器——widget test 環境無法驅動系統檔案選擇器）：

```dart
  test('resolveUploadOutcome：同一批次內重複 family name 只寫入第一筆，其餘計入已存在',
      () {
    final outcome = resolveUploadOutcome(
      parsedFamilyNames: ['FamilyA', 'FamilyB', 'FamilyA'],
      alreadyExistingFamilyNames: {'FamilyB'},
    );

    expect(outcome.toInsertIndexes, [0]); // 只有索引 0（第一次出現的 FamilyA）要寫入
    expect(outcome.addedCount, 1);
    expect(outcome.skippedCount, 2); // FamilyB（資料庫已存在）+ 第二個 FamilyA（批次內重複）
  });

  test('resolveUploadOutcome：合併訊息文案（有新增有跳過／全部新增／全部跳過）', () {
    expect(
      buildUploadResultMessage(addedCount: 3, skippedCount: 2),
      '已新增 3 款字型，2 款已存在已跳過',
    );
    expect(buildUploadResultMessage(addedCount: 3, skippedCount: 0), '已新增 3 款字型');
    expect(
      buildUploadResultMessage(addedCount: 0, skippedCount: 2),
      '2 款字型已存在，已跳過',
    );
  });

  test(
      'resolveUploadOutcome：與內建字型 family name 相同時視為已存在並跳過'
      '（審查發現：custom_fonts 表不含內建字型，見 tmp/epic-14/review-plan-issue-2.md Critical）',
      () {
    final outcome = resolveUploadOutcome(
      parsedFamilyNames: ['SourceHanSansTC', 'MyOwnFamily'],
      // 呼叫端（_pickAndUploadFonts）會把 AppFont.values 的 family name
      // 併入這個集合，此處直接模擬併入後的結果，不重複走訪 AppFont.values。
      alreadyExistingFamilyNames: {'SourceHanSansTC'},
    );

    expect(outcome.toInsertIndexes, [1]); // 只有 MyOwnFamily 要寫入
    expect(outcome.addedCount, 1);
    expect(outcome.skippedCount, 1); // SourceHanSansTC 被判定為已存在（內建字型）而跳過
  });
```

- [ ] **Step 14：執行測試，確認失敗**

```bash
flutter test test/screens/font_management_screen_test.dart
```

Expected：FAIL——`resolveUploadOutcome`／`buildUploadResultMessage` 未定義。

- [ ] **Step 15：抽出上傳結果純函式並實作 `_pickAndUploadFonts`**

在 `font_management_screen.dart` 檔案最上方（class 定義之前）新增匯入與兩個頂層純函式：

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../reader/font_name_parser.dart';
```

在檔案最下方（class 定義之後）新增：

```dart
/// 批次上傳結果：哪些索引（對應呼叫端傳入的 [parsedFamilyNames] 順序）
/// 真的要寫入資料庫，以及新增/跳過各自的計數。同一批次內重複的 family
/// name（例如使用者一次選了兩個內容相同的字型檔）只保留第一次出現的索引，
/// 其餘視同重複一併跳過——不能只靠 [alreadyExistingFamilyNames]（那只反映
/// 資料庫既有資料，抓不到「這一批次自己內部重複」的情況）。
class UploadOutcome {
  final List<int> toInsertIndexes;
  final int addedCount;
  final int skippedCount;
  const UploadOutcome({
    required this.toInsertIndexes,
    required this.addedCount,
    required this.skippedCount,
  });
}

UploadOutcome resolveUploadOutcome({
  required List<String> parsedFamilyNames,
  required Set<String> alreadyExistingFamilyNames,
}) {
  final seenInBatch = <String>{};
  final toInsertIndexes = <int>[];
  var skipped = 0;
  for (var i = 0; i < parsedFamilyNames.length; i++) {
    final familyName = parsedFamilyNames[i];
    final isDuplicate = alreadyExistingFamilyNames.contains(familyName) ||
        !seenInBatch.add(familyName);
    if (isDuplicate) {
      skipped++;
    } else {
      toInsertIndexes.add(i);
    }
  }
  return UploadOutcome(
    toInsertIndexes: toInsertIndexes,
    addedCount: toInsertIndexes.length,
    skippedCount: skipped,
  );
}

String buildUploadResultMessage({
  required int addedCount,
  required int skippedCount,
}) {
  if (addedCount > 0 && skippedCount > 0) {
    return '已新增 $addedCount 款字型，$skippedCount 款已存在已跳過';
  }
  if (addedCount > 0) {
    return '已新增 $addedCount 款字型';
  }
  return '$skippedCount 款字型已存在，已跳過';
}

/// 字型檔名去除副檔名，供 [parseFontFamilyName] 回傳 `null`（解析失敗）時
/// 的顯示名稱與 family name 退回依據。
String _stripExtension(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
}

const _metadataChannel = MethodChannel('elinkbook/book_metadata');
```

把 `_pickAndUploadFonts` 空殼實作補齊：

```dart
  Future<void> _pickAndUploadFonts() async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    // identifier 是 Android SAF content:// URI（見 ADR 0021），本專案手機
    // 優先且目前只有 Android 實作，非 Android 平台/桌面測試環境下可能為
    // null，一併過濾避免後續 fontUri 寫入 null。
    final validFiles = picked.files
        .where((f) => f.bytes != null && f.identifier != null)
        .toList();
    if (validFiles.isEmpty) return;

    setState(() => _isUploading = true);
    try {
      final parsedFamilyNames = <String>[];
      for (final file in validFiles) {
        final parsed = parseFontFamilyName(file.bytes!);
        parsedFamilyNames.add(parsed ?? _stripExtension(file.name));
      }

      // 內建 5 款字型的 family name 不存在於 custom_fonts 表（該表只存自訂
      // 字型），必須額外併入重複判定集合——否則上傳一款與內建字型 family
      // name 相同的自訂字型會成功寫入，導致 reader_settings_sheet.dart
      // 的 DropdownButton 出現兩個相同 value 的 DropdownMenuItem，觸發
      // Flutter「exactly one item with value」assertion 崩潰（審查發現，
      // 見 tmp/epic-14/review-plan-issue-2.md Critical）。
      final existing = AppFont.values.map((f) => f.familyName).toSet();
      for (final familyName in parsedFamilyNames.toSet()) {
        if (await widget.repository.familyNameExists(familyName)) {
          existing.add(familyName);
        }
      }

      final outcome = resolveUploadOutcome(
        parsedFamilyNames: parsedFamilyNames,
        alreadyExistingFamilyNames: existing,
      );

      for (final index in outcome.toInsertIndexes) {
        final file = validFiles[index];
        final uri = file.identifier!;
        try {
          await _metadataChannel
              .invokeMethod<void>('takePersistableUriPermission', {'uri': uri});
        } on PlatformException {
          // 部分文件提供者不保證核發可持久化授權（比照書籍匯入既有慣例，
          // book_import_service_impl.dart:201-207）；字型檔案本身刻意不做
          // 落地複本退路（ADR 0021），僅盡力而為，不因此中止整批上傳。
        }
        await widget.repository.insert(CustomFont(
          displayName: _stripExtension(file.name),
          familyName: parsedFamilyNames[index],
          fontUri: uri,
        ));
      }

      await _loadFonts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(buildUploadResultMessage(
          addedCount: outcome.addedCount,
          skippedCount: outcome.skippedCount,
        )),
      ));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
```

- [ ] **Step 16：執行測試，確認通過**

```bash
flutter test test/screens/font_management_screen_test.dart
```

Expected：全數 PASS（含 Step 13 新增的兩個純函式測試——它們不透過 `pumpScreen`，直接測試頂層函式，不受 widget 樹或 `file_picker` 影響）。

- [ ] **Step 17：全專案回歸測試 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：全數 PASS，`flutter analyze` "No issues found!"。

- [ ] **Step 18：Commit**

```bash
git add lib/screens/font_management_screen.dart test/screens/font_management_screen_test.dart
git commit -m "feat(epic-14): FontManagementScreen——批次上傳/清單/重新命名/刪除"
```

---

### Task 3：`SettingsScreen`「字型管理」入口 + 全鏈路貫穿

**Files:**
- Modify：`app/lib/screens/settings_screen.dart`
- Modify：`app/lib/screens/library_screen.dart`
- Modify：`app/lib/main.dart`
- Test：`app/test/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `CustomFontsRepository`；Task 2 的 `FontManagementScreen`
- Produces：`SettingsScreen`／`LibraryScreen`／`ElinkBookApp` 新增可選具名參數 `customFontsRepository`，貫穿至 `main.dart` 實際建構一份 `CustomFontsRepository(repository.database)` 注入（比照既有 `bookmarksRepository` 貫穿模式）

- [x] **Step 1：撰寫失敗測試——`SettingsScreen` 新增「字型管理」入口**

`app/test/screens/settings_screen_test.dart` 新增 import：

```dart
import 'package:elinkbook/reader/custom_fonts_repository.dart';
import '../support/fake_custom_fonts_repository.dart';
```

在既有第一個 `testWidgets('SettingsScreen 顯示設定標題與...')` 測試內，`expect(find.byKey(const Key('settings_nav_zone_button')), findsOneWidget);` 之後新增：

```dart
    expect(
        find.byKey(const Key('settings_font_management_button')),
        findsOneWidget);
```

在檔案最後新增一個新測試（比照既有「點擊「導航熱區」導航至 NavZoneSettingsScreen」測試的既有寫法）：

```dart
  testWidgets('點擊「字型管理」導航至 FontManagementScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        customFontsRepository: FakeCustomFontsRepository(),
      ),
    ));

    await tester.tap(find.byKey(const Key('settings_font_management_button')));
    await tester.pumpAndSettle();

    expect(find.text('字型管理'), findsOneWidget);
  });
```

- [x] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/settings_screen_test.dart
```

Expected：FAIL——`SettingsScreen` 建構子沒有 `customFontsRepository` 具名參數；`settings_font_management_button` 找不到。

- [x] **Step 3：修改 `settings_screen.dart`**

`import` 區塊（第 1-6 行）新增：

```dart
import '../reader/custom_fonts_repository.dart';
import 'font_management_screen.dart';
```

class 欄位（第 12-15 行 `final ReaderPrefsManager prefsManager;` 等）之後新增：

```dart
  final CustomFontsRepository? customFontsRepository;
```

建構子（第 17-23 行）新增：

```dart
    this.customFontsRepository,
```

`body: ListView(children: [...])`（第 31-70 行），在「佈景」`ListTile`（第 33-46 行）之後、「導航熱區」`ListTile`（第 47-59 行）之前新增：

```dart
          ListTile(
            key: const Key('settings_font_management_button'),
            title: const Text('字型管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: customFontsRepository == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => FontManagementScreen(
                          repository: customFontsRepository!,
                        ),
                      ),
                    );
                  },
          ),
```

（`customFontsRepository` 為 `null` 時 `onTap` 也是 `null`——`ListTile` 的既有語意是 `onTap: null` 時整顆項目仍會顯示但點擊無反應，比照 Flutter 內建行為，不需要額外隱藏整個項目；本專案既有慣例是保留可選參數缺席時「入口仍在、但不可互動」而非「入口整個消失」，讓使用者知道這個功能存在。）

- [x] **Step 4：執行測試，確認通過**

```bash
flutter test test/screens/settings_screen_test.dart
```

Expected：全數 PASS。

- [x] **Step 5：撰寫失敗測試——`LibraryScreen` 貫穿 `customFontsRepository` 到 `SettingsScreen`**

`app/test/screens/library_screen_test.dart` 目前完全沒有任何測試涵蓋「點擊設定圖示導航至 `SettingsScreen`」這條路徑（`library_screen.dart:617-621` 的設定 `IconButton` 也還沒有 `key:`），新增：

```dart
  testWidgets('LibraryScreen 貫穿 customFontsRepository 至 SettingsScreen',
      (tester) async {
    final customFontsRepository = FakeCustomFontsRepository();
    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        repository: FakeLibraryRepository(initialBooks: const []),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        customFontsRepository: customFontsRepository,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();

    final settingsScreen =
        tester.widget<SettingsScreen>(find.byType(SettingsScreen));
    expect(settingsScreen.customFontsRepository, customFontsRepository);
  });
```

（`FakeLibraryRepository`／`FakeBookImportService` 已由檔案頂部既有 import 提供〔`../support/fake_library_repository.dart`／`../support/fake_book_import_service.dart`〕；`prefsManager` 為檔案內既有 `late ReaderPrefsManager prefsManager;` 欄位，於 `setUp()` 賦值為 `FakeReaderPrefsManager()`〔第 37、61 行〕，直接沿用不重新定義。）

- [x] **Step 6：執行測試，確認失敗**

```bash
flutter test test/screens/library_screen_test.dart
```

Expected：FAIL——`LibraryScreen` 建構子沒有 `customFontsRepository` 參數。

- [x] **Step 7：修改 `library_screen.dart`**

`import` 區塊（第 1-21 行）新增：

```dart
import '../reader/custom_fonts_repository.dart';
```

class 欄位（第 28-39 行）新增：

```dart
  final CustomFontsRepository? customFontsRepository;
```

建構子（第 41-54 行）新增：

```dart
    this.customFontsRepository,
```

`SettingsScreen(...)` 建構呼叫（第 623-628 行）新增：

```dart
                  customFontsRepository: widget.customFontsRepository,
```

`_openGroupFilteredView`（第 456-470 行左右，`LibraryScreen(...)` 遞迴建構自身供分類篩選視圖使用）也新增同一行 `customFontsRepository: widget.customFontsRepository,`（否則從分類篩選視圖進入的「設定」會遺失這個參數——比照該處既有的 `bookmarksRepository: widget.bookmarksRepository,` 等既有寫法逐一對照補上）。

「設定」`IconButton`（第 617-621 行）目前沒有 `key:`，補上：

```dart
        IconButton(
          key: const Key('library_settings_button'),
          icon: const Icon(Icons.settings),
```

- [x] **Step 8：執行測試，確認通過**

```bash
flutter test test/screens/library_screen_test.dart
```

Expected：全數 PASS。

- [x] **Step 9：修改 `main.dart` 實際注入**

`import` 區塊（第 1-18 行）新增：

```dart
import 'reader/custom_fonts_repository.dart';
```

`main()`（第 41 行 `final bookmarksRepository = BookmarksRepository(repository.database);` 之後）新增：

```dart
  final customFontsRepository = CustomFontsRepository(repository.database);
```

`ElinkBookApp(...)` 建構呼叫（第 44-56 行）新增：

```dart
      customFontsRepository: customFontsRepository,
```

`ElinkBookApp` class 欄位（第 61-70 行）新增：

```dart
  final CustomFontsRepository? customFontsRepository;
```

`ElinkBookApp` 建構子（第 72-83 行）新增：

```dart
    this.customFontsRepository,
```

`_ElinkBookAppState.build()` 內的 `LibraryScreen(...)` 建構呼叫（第 119-129 行左右）新增：

```dart
        customFontsRepository: widget.customFontsRepository,
```

- [x] **Step 10：全專案回歸測試 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：全數 PASS，`flutter analyze` "No issues found!"（`main.dart` 本身沒有自動化測試覆蓋，此步驟只能靠 `flutter analyze` 靜態檢查其型別正確；`flutter build apk --debug` 若時間允許可額外驗證整個 App 實際可編譯執行，非必要但建議）。

- [x] **Step 11：Commit**

```bash
git add lib/screens/settings_screen.dart lib/screens/library_screen.dart lib/main.dart test/screens/settings_screen_test.dart test/screens/library_screen_test.dart
git commit -m "feat(epic-14): SettingsScreen「字型管理」入口 + customFontsRepository 全鏈路貫穿"
```

---

### Task 4：`reader_settings_sheet.dart` 字型選擇器合併自訂字型 + `ReaderScreen` 貫穿

**Files:**
- Modify：`app/lib/screens/reader_settings_sheet.dart`
- Modify：`app/lib/screens/reader_screen.dart`
- Test：`app/test/screens/reader_settings_sheet_test.dart`
- Test：`app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `CustomFont`／`CustomFontsRepository`
- Produces：`ReaderSettingsSheet` 新增可選具名參數 `customFonts: List<CustomFont>`（預設 `const []`）；`ReaderScreen` 新增可選具名參數 `customFontsRepository`，開書時載入一次並快取

- [ ] **Step 1：撰寫失敗測試——字型選單合併顯示自訂字型**

`app/test/screens/reader_settings_sheet_test.dart` 新增 import：

```dart
import 'package:elinkbook/reader/custom_font.dart';
```

新增測試（比照既有字型下拉選單相關測試的既有寫法）：

```dart
  testWidgets('字型選單合併顯示內建 5 款與傳入的自訂字型清單', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(),
      (_) {},
      customFonts: const [
        CustomFont(
          id: 1,
          displayName: '我的自訂字型',
          familyName: 'MyCustomFamily',
          fontUri: 'content://example/font1',
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('reader_settings_font_family')));
    await tester.pumpAndSettle();

    expect(find.text('思源黑體'), findsWidgets);
    expect(find.text('我的自訂字型'), findsWidgets);
  });

  testWidgets('選擇自訂字型後，onChanged 帶入其 familyName', (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(),
      (prefs) => result = prefs,
      customFonts: const [
        CustomFont(
          id: 1,
          displayName: '我的自訂字型',
          familyName: 'MyCustomFamily',
          fontUri: 'content://example/font1',
        ),
      ],
    );

    final dropdown = find.byKey(const Key('reader_settings_font_family'));
    tester.widget<DropdownButton<String?>>(dropdown).onChanged!('MyCustomFamily');
    await tester.pump();

    expect(result?.fontFamily, 'MyCustomFamily');
  });
```

找到既有的 `_pumpSheet` 測試輔助函式定義（檔案內搜尋 `Future<void> _pumpSheet`），新增一個可選具名參數 `customFonts`：

```dart
Future<void> _pumpSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  List<CustomFont> customFonts = const [],
}) async {
```

並在該函式內部建構 `ReaderSettingsSheet(...)` 的地方新增 `customFonts: customFonts,`（依檔案實際既有寫法的確切位置調整，找到 `ReaderSettingsSheet(` 那一行往下對照既有的 `prefs:`／`onChanged:` 具名參數，新增同一層級的 `customFonts:`）。

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/reader_settings_sheet_test.dart
```

Expected：FAIL——`_pumpSheet` 沒有 `customFonts` 具名參數／`ReaderSettingsSheet` 建構子沒有 `customFonts`。

- [ ] **Step 3：修改 `reader_settings_sheet.dart`**

`import` 區塊新增：

```dart
import '../reader/custom_font.dart';
```

class 欄位（第 22-24 行）新增：

```dart
  final List<CustomFont> customFonts;
```

建構子（第 26-30 行）新增：

```dart
    this.customFonts = const [],
```

`_buildFontFamilyDropdown()`（第 416-445 行），`...AppFont.values.map(...)` 之後新增：

```dart
              ...widget.customFonts.map(
                (font) => DropdownMenuItem<String?>(
                  value: font.familyName,
                  child: Text(font.displayName),
                ),
              ),
```

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/screens/reader_settings_sheet_test.dart
```

Expected：全數 PASS。

- [ ] **Step 5：撰寫失敗測試——`ReaderScreen` 貫穿自訂字型清單至 `ReaderSettingsSheet`**

`app/test/screens/reader_screen_test.dart` 新增 import：

```dart
import 'package:elinkbook/reader/custom_font.dart';
import '../support/fake_custom_fonts_repository.dart';
```

新增測試（比照檔案內既有第 1690-1719 行「頁首開關不影響既有版面設定入口」測試的既有寫法——EPUB 的「⚙️版面設定」按鈕〔`Key('reader_layout_settings_button')`〕要等 `_autoDetectedWritingMode` 非 null 才可點擊，widget test 環境下 `FoliateEpubReaderView` 不會真正觸發原生 `onLayoutResolved` 回呼，需手動呼叫該 widget 的 `onLayoutResolved` 模擬）：

```dart
  testWidgets('提供 customFontsRepository 時，開啟版面設定顯示自訂字型選項',
      (tester) async {
    final customFontsRepository = FakeCustomFontsRepository();
    await customFontsRepository.insert(const CustomFont(
      displayName: '測試自訂字型',
      familyName: 'TestCustomFamily',
      fontUri: 'content://example/test',
    ));

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.epub',
        bookId: 'b1',
        prefsManager: prefsManager,
        customFontsRepository: customFontsRepository,
      ),
    ));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();

    expect(find.text('測試自訂字型'), findsWidgets);
  });
```

（`prefsManager` 變數沿用檔案內既有於 `setUp`/頂層建立的既有 fixture，不重新定義；`FoliateEpubReaderView`／`EpubLayoutInfo`／`WritingMode` 皆為檔案內既有 import，本測試不需要新增這些型別的 import。）

- [ ] **Step 6：執行測試，確認失敗**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：FAIL——`ReaderScreen` 建構子沒有 `customFontsRepository` 參數。

- [ ] **Step 7：修改 `reader_screen.dart`**

class 欄位（第 82-110 行 `final BookmarksRepository? bookmarksRepository;` 等區塊）新增：

```dart
  /// 自訂字型清單的資料存取層（epic-14-system-settings Issue 2）。刻意為
  /// 可選參數——比照 [bookmarksRepository] 既有慣例，未提供時字型選單僅
  /// 顯示內建 5 款，行為等同本 Issue 之前，零回歸。
  final CustomFontsRepository? customFontsRepository;
```

建構子（第 112-125 行）新增：

```dart
    this.customFontsRepository,
```

`import` 區塊新增：

```dart
import '../reader/custom_font.dart';
import '../reader/custom_fonts_repository.dart';
```

`_ReaderScreenState` 新增欄位（比照既有 `List<Bookmark> _fxlBookmarks = [];` 等既有欄位的宣告位置）：

```dart
  // 自訂字型清單快取（epic-14-system-settings Issue 2），開書時載入一次，
  // 比照既有 _fxlBookmarks／_highlights 等一次性載入快取模式。
  List<CustomFont> _customFonts = [];
```

新增一個對稱於既有 `_loadFxlBookmarks()`（`reader_screen.dart:601-611`）的載入方法——`customFontsRepository` 與 `bookmarksRepository` 同樣是可選、非關鍵路徑的補充資料，讀取失敗時應安全退回空清單（僅顯示內建字型），不應讓未捕捉的例外往外冒出（審查發現，見 `tmp/epic-14/review-plan-issue-2.md` Important 1；**不比照** `initState()` 既有的 `widget.prefsManager.load(...).then(...)`〔第 266-281 行〕——後者讀取的是閱讀器渲染必要的核心資料，失敗時例外往外冒出是可接受的行為，兩者情境不同，不適合套用同一種錯誤處理姿態）。在 `_loadFxlBookmarks()` 方法定義之後新增：

```dart
  Future<void> _loadCustomFonts() async {
    final repository = widget.customFontsRepository;
    if (repository == null) return;
    try {
      final fonts = await repository.listAll();
      if (!mounted) return;
      setState(() => _customFonts = fonts);
    } catch (e) {
      debugPrint('Failed to load custom fonts: $e');
    }
  }
```

在 `initState()`（第 260-282 行）的 `_resolveEpubEngineDispatch();` 之後新增呼叫：

```dart
    _loadCustomFonts();
```

`_openLayoutSettings()`（第 562-575 行）的 `ReaderSettingsSheet(...)` 建構呼叫新增：

```dart
        customFonts: _customFonts,
```

- [ ] **Step 8：執行測試，確認通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：全數 PASS。

- [ ] **Step 9：全專案回歸測試 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：全數 PASS，`flutter analyze` "No issues found!"。

- [ ] **Step 10：Commit**

```bash
git add lib/screens/reader_settings_sheet.dart lib/screens/reader_screen.dart test/screens/reader_settings_sheet_test.dart test/screens/reader_screen_test.dart
git commit -m "feat(epic-14): 單書字型選擇器合併自訂字型清單，ReaderScreen 貫穿 customFontsRepository"
```

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：`spec.md`「字型管理模組」的批次上傳、重複阻擋（family name 比對）、重新命名、刪除（一般/使用中兩種文案＋級聯重置）、清單顯示內建+自訂皆有對應任務；`issues.md` Issue 2 驗收標準與「新發現缺口」（`reader_settings_sheet.dart` 選擇器整合）皆有對應 Task（Task 4）。字型實際渲染（Foliate-JS 服務機制）明確排除於本計畫外，留給 Issue 3，已在 Goal 段落與各 Task 說明中反覆註明避免混淆。
- **型別/介面一致性**：`CustomFont`／`CustomFontsRepository` 的方法命名（`listAll`／`familyNameExists`／`insert`／`rename`／`countBooksUsing`／`deleteAndResetUsage`）在 Task 1 定義後，Task 2/3/4 呼叫端逐一核對皆使用相同名稱與參數型別；`ReaderSettingsSheet.customFonts`／`ReaderScreen.customFontsRepository` 的具名參數命名與既有 `bookmarksRepository`／`highlightsRepository` 慣例一致（Repository 給資料存取層、已載入的 plain List 給純展示層元件，對照 `_fxlBookmarks` 快取模式）。
- **無佔位符掃描**：所有步驟皆附完整程式碼與確切檔案位置/行號。Task 3 Step 5（`library_screen_test.dart` 目前無此路徑測試、`library_screen.dart:617-621` 設定按鈕無 `key:`）與 Task 4 Step 5（`ReaderScreen` 的「⚙️版面設定」按鈕實際 Key 為 `reader_layout_settings_button`，非隨意假設；EPUB widget test 需手動呼叫 `FoliateEpubReaderView.onLayoutResolved` 模擬原生回呼，比照 `reader_screen_test.dart:1690-1719` 既有先例）皆已直接讀取對應檔案當下內容核實後寫入確切內容，撰寫計畫過程中未發現需要保留假設性佔位符的地方。
- **額外發現並主動排查的問題**：`LibraryScreen._openGroupFilteredView()` 遞迴建構自身時容易漏掉新參數（過去 `bookmarksRepository` 等既有參數都需要在此處與主要建構呼叫兩處同步維護），Task 3 Step 7 已明確列出這個容易遺漏的第二處建構呼叫，避免只改主要入口、分類篩選視圖裡的「設定」入口卻遺失 `customFontsRepository`。

## 審查修正紀錄（`tmp/epic-14/review-plan-issue-2.md`）

- **Critical（確認屬實，已修正）**：`custom_fonts` 表不含內建 5 款字型記錄，`familyNameExists` 只查該表，若自訂字型與內建字型 family name 相同會成功寫入，導致 `reader_settings_sheet.dart` 的 `DropdownButton` 出現兩個相同 `value` 的 `DropdownMenuItem`，觸發 Flutter「exactly one item with value」assertion 崩潰。已於 Task 2 Step 15 的 `_pickAndUploadFonts` 把 `AppFont.values` 的 family name 併入重複判定集合，並於 Step 13 補上對應純函式測試。**未採納**審查建議 3（`reader_settings_sheet.dart` 二次防禦過濾）——上傳端已結構性阻擋此情境進入 `custom_fonts` 表，UI 層再加一層過濾是對已被上游擋死的情境做重複防禦，比照 `epic-14` Issue 1 審查對「移除不會觸發的防禦檢查」（Minor 3）的相同處理原則，予以簡化不採納。
- **Important（確認屬實，已修正，且比建議更貼合既有慣例）**：`reader_screen.dart` 載入 `_customFonts` 原計畫用裸 `.then()`、無錯誤處理。查證發現同一檔案已有更貼切的既有先例——`_loadFxlBookmarks()`（`reader_screen.dart:601-611`，同樣是「可選 repository、非關鍵路徑、失敗應安全退回」的情境）用的是 `try/catch` + `debugPrint`，非審查建議的泛用 `.catchError((_) {})`。已改為新增對稱的 `_loadCustomFonts()` 方法直接沿用該既有模式，並說明為何不比照 `initState()` 另一個 `.then()`（`prefsManager.load()`，讀取核心必要資料，情境不同）。
- **Important（確認屬實，已修正）**：Task 2 Step 13 補上「與內建字型 family name 相同時視為已存在並跳過」的 `resolveUploadOutcome` 純函式測試。
- **Minor（確認屬實，已採納）**：Task 2 Step 15 的 `f.identifier != null` 過濾補充註解，標明其為 Android SAF `content://` URI 特性（ADR 0021）。
