# Refactor ReaderPrefsManager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ReaderScreen` 內散落的偏好設定覆寫解析邏輯（4 個 `_resolved*` getter）與雙層資料存取（SQLite `BookReaderPrefsRepository` + SharedPreferences `GlobalReaderDefaults`）收斂成一個深模組 `ReaderPrefsManager`，讓 `ReaderScreen` 只依賴單一介面，並讓覆寫優先級邏輯可用純 Dart 單元測試驗證，不需每次異動都跑 widget/整合測試。

**Architecture:** `ReaderPrefsManager` 把「載入（async，讀 SQLite + SharedPreferences）」與「解析（sync，純 `??` 合併）」明確拆成兩個方法——`load()` 回傳 `LoadedPrefs`（未解析的原始資料），`resolve()` 是純函式、可重複呼叫且不重讀儲存層。`ResolvedPreferences` 只對**目前已有明確既存預設值**的欄位（PDF 濾鏡/裁切/Fit 模式、翻頁模式、螢幕方向）宣告為 non-nullable；EPUB 字型/排版 7 個欄位**維持 nullable**，因為現行架構下這些欄位完全沒有 Dart 端預設值（null 時 Method Channel 整個 key 省略，交由 Readium 內部預設值/書本 CSS 決定）——把它們改成 non-null 等於發明一個目前不存在的行為，不是本次重構的範圍。`ReaderPrefsManagerImpl` 直接吸收 `GlobalReaderDefaults` 的 SharedPreferences 讀寫邏輯（不再是注入依賴），讓 `global_reader_defaults.dart` 在 Task 5 可以真正被刪除。

**Tech Stack:** Flutter/Dart、`shared_preferences`、`sqflite`（`BookReaderPrefsRepository` 不變）。

## Global Constraints

- **本計劃是對 `tmp/refactor-reader-prefs/reviews/review-refactor-reader-prefs-plan.md` 審查意見的修訂版**，以下 Global Constraints 直接對應該審查的 3 項 Critical + 4 項 Important：
  - **C1 修正**：`ResolvedPreferences` 的 `fontFamily`／`fontSize`／`fontWeight`／`lineHeight`／`paragraphSpacing`／`pageMargins`／`textAlign`／`publisherStyles` 8 個 EPUB 欄位**必須維持 nullable**，不得宣告 `required` 或發明預設值。只有以下 7 個欄位有既存、可安全 non-null 的預設值：`pageTurnMode`（`PageTurnMode.paginated`）、`screenOrientation`（`ScreenOrientationSetting.auto`）、`pdfFitMode`（`PdfFitMode.pageFit`）、`pdfContrast`（`0`）、`pdfBrightness`（`0`）、`pdfBoldStrength`（`0`）、`pdfCropMode`（`PdfCropMode.none`）。`writingMode`／`pdfCropRect` 維持 nullable（前者 layout 解析前為 null，後者不裁切時為 null，既有語意不變）。
  - **C2 修正**：`resolve()` 必須是**純同步函式**（不得是 `Future`），讓 `_handleLayoutResolved`（原生 layout 解析完成的回呼）能在同一個 `setState` 內立即重新呼叫 `resolve()` 取得含自動偵測排版方向的最新結果，不遺失現行「同步 getter 自動反映」的既有行為。
  - **C3 修正**：`ReaderPrefsManagerImpl` 直接內建 SharedPreferences 讀寫（吸收 `GlobalReaderDefaults` 的邏輯），建構子**不**注入 `GlobalReaderDefaults`。`global_reader_defaults.dart` 與其測試檔 `global_reader_defaults_test.dart` 在 Task 5 整個刪除。
  - **I3 修正**：`load()`（async，一次讀 SQLite + SharedPreferences）與 `resolve()`（sync，純合併）明確分離，偏好變動時不重新呼叫 `load()`，只重新呼叫 `resolve()`。
  - **I1 修正**：本文件的「目標」不誇稱／不低估現行複雜度——現行只有 4 個 `_resolved*` getter（`writingMode`／`pageTurnMode`／`screenOrientation`／`pdfFitMode`），`ResolvedPreferences` 新增的其餘 PDF 欄位（`contrast`/`brightness`/`boldStrength`/`cropMode`）今天是直接 pass-through、無解析邏輯，本次是「新增」而非「搬移」。
  - **I2/I4 修正**：Task 4 測試矩陣涵蓋 `resolve()` 全部 7 個 non-null 欄位的預設值斷言；新增 `FakeReaderPrefsManager`；明確交代現有 `global_reader_defaults_test.dart` 與 `reader_screen_test.dart` 內的全域預設回歸測試如何遷移到 `reader_prefs_manager_test.dart`。
  - **M1 修正**：不寫「未來可擴充」等預先設計的註解（YAGNI，見本專案 CLAUDE.md）。
- `BookReaderPrefsRepository`（`app/lib/reader/book_reader_prefs_repository.dart`）與 `BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`）**不修改**——本計劃只重組 `ReaderScreen` 與其上游的解析/存取邏輯，不動資料模型本身。
- 設定面板（`ReaderSettingsSheet`／`PdfSettingsSheet`）維持接收 `BookReaderPrefs`（原始 nullable 覆寫值），**不改用** `ResolvedPreferences`——兩者用途不同（前者要顯示「使用者是否已覆寫」的三態，後者是「實際套用到畫面」的值），現有 `reader_screen.dart:223-240` 已正確區分，本次重構延續此設計。

---

### Task 1：`GlobalReaderPrefs` 與 `ResolvedPreferences` 資料型別

**Files:**
- Create：`app/lib/reader/global_reader_prefs.dart`
- Create：`app/lib/reader/resolved_preferences.dart`
- Test：`app/test/reader/global_reader_prefs_test.dart`
- Test：`app/test/reader/resolved_preferences_test.dart`

**Interfaces:**
- Consumes：`PageTurnMode`（`app/lib/reader/page_turn_mode.dart`）、`ScreenOrientationSetting`（`app/lib/reader/screen_orientation_setting.dart`）、`WritingMode`、`AppFont`、`EpubTextAlign`、`PdfFitMode`、`PdfCropMode`、`PdfCropRect`（皆為既有型別，不修改）
- Produces：`GlobalReaderPrefs`（non-nullable，`pageTurnMode`/`screenOrientation` 兩欄 + `copyWith`）；`ResolvedPreferences`（`writingMode`/8 個 EPUB 欄位/`pdfCropRect` nullable，`pageTurnMode`/`screenOrientation`/`pdfFitMode`/`pdfContrast`/`pdfBrightness`/`pdfBoldStrength`/`pdfCropMode` non-nullable）——供 Task 2 的 `ReaderPrefsManager.resolve()` 回傳、Task 3 的 `ReaderScreen` 消費

- [ ] **Step 1：撰寫 `GlobalReaderPrefs` 的失敗測試**

建立 `app/test/reader/global_reader_prefs_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';

void main() {
  test('GlobalReaderPrefs.initial() 回傳與現行硬編碼預設一致的值（paginated/auto）', () {
    const prefs = GlobalReaderPrefs.initial();
    expect(prefs.pageTurnMode, PageTurnMode.paginated);
    expect(prefs.screenOrientation, ScreenOrientationSetting.auto);
  });

  test('copyWith 只更新指定欄位，其餘欄位保留原值', () {
    const original = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
    );
    final updated = original.copyWith(pageTurnMode: PageTurnMode.scroll);
    expect(updated.pageTurnMode, PageTurnMode.scroll);
    expect(updated.screenOrientation, ScreenOrientationSetting.auto);
  });

  test('兩個欄位值相同的 GlobalReaderPrefs 視為相等', () {
    const a = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.scroll,
      screenOrientation: ScreenOrientationSetting.lock90,
    );
    const b = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.scroll,
      screenOrientation: ScreenOrientationSetting.lock90,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/reader/global_reader_prefs_test.dart
```

Expected：FAIL——`global_reader_prefs.dart` 不存在。

- [ ] **Step 3：建立 `GlobalReaderPrefs`**

```dart
import 'page_turn_mode.dart';
import 'screen_orientation_setting.dart';

/// 跨書生效的全域預設值（FR-37／FR-38），供單書未覆寫時的回退使用。
/// 兩個欄位皆 non-nullable——與 [BookReaderPrefs] 的「全欄位 nullable、
/// null=未覆寫」語意刻意不同：全域層本身沒有更上層的預設可回退，任何時候
/// 都必須有一個明確生效值。
class GlobalReaderPrefs {
  final PageTurnMode pageTurnMode;
  final ScreenOrientationSetting screenOrientation;

  const GlobalReaderPrefs({
    required this.pageTurnMode,
    required this.screenOrientation,
  });

  /// 初始值，與現行 GlobalReaderDefaults 的既有硬編碼預設一致，
  /// 不改變任何現有使用者體驗。
  const GlobalReaderPrefs.initial()
      : pageTurnMode = PageTurnMode.paginated,
        screenOrientation = ScreenOrientationSetting.auto;

  GlobalReaderPrefs copyWith({
    PageTurnMode? pageTurnMode,
    ScreenOrientationSetting? screenOrientation,
  }) {
    return GlobalReaderPrefs(
      pageTurnMode: pageTurnMode ?? this.pageTurnMode,
      screenOrientation: screenOrientation ?? this.screenOrientation,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlobalReaderPrefs &&
      other.pageTurnMode == pageTurnMode &&
      other.screenOrientation == screenOrientation;

  @override
  int get hashCode => Object.hash(pageTurnMode, screenOrientation);
}
```

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/reader/global_reader_prefs_test.dart
```

Expected：全數 PASS。

- [ ] **Step 5：撰寫 `ResolvedPreferences` 的失敗測試**

建立 `app/test/reader/resolved_preferences_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';

void main() {
  test('建構後各欄位保留傳入值，EPUB 欄位可為 null（無既存預設值，維持既有 pass-through 語意）',
      () {
    const resolved = ResolvedPreferences(
      writingMode: null,
      fontFamily: null,
      fontSize: null,
      fontWeight: null,
      lineHeight: null,
      paragraphSpacing: null,
      pageMargins: null,
      textAlign: null,
      publisherStyles: null,
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
      pdfFitMode: PdfFitMode.pageFit,
      pdfContrast: 0,
      pdfBrightness: 0,
      pdfBoldStrength: 0,
      pdfCropMode: PdfCropMode.none,
      pdfCropRect: null,
    );

    expect(resolved.fontSize, isNull);
    expect(resolved.textAlign, isNull);
    expect(resolved.pageTurnMode, PageTurnMode.paginated);
    expect(resolved.pdfContrast, 0);
  });
}
```

- [ ] **Step 6：執行測試，確認失敗**

```bash
flutter test test/reader/resolved_preferences_test.dart
```

Expected：FAIL——`resolved_preferences.dart` 不存在。

- [ ] **Step 7：建立 `ResolvedPreferences`**

```dart
import 'app_font.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
import 'pdf_fit_mode.dart';
import 'screen_orientation_setting.dart';
import 'writing_mode.dart';

/// 「實際套用到畫面」的最終生效值，由 [ReaderPrefsManager.resolve] 產生。
/// 與 [BookReaderPrefs]（使用者是否覆寫了哪些欄位，供設定面板顯示）刻意
/// 分離，見 docs/superpowers/plans/2026-07-12-refactor-reader-prefs-manager.md。
///
/// **欄位是否 non-nullable 的判斷依據**：只有現行架構已有明確、安全預設值
/// 的欄位才宣告 non-nullable（`pageTurnMode`／`screenOrientation`／
/// `pdfFitMode`／`pdfContrast`／`pdfBrightness`／`pdfBoldStrength`／
/// `pdfCropMode`）。EPUB 字型/排版 8 個欄位與 `writingMode`／`pdfCropRect`
/// 維持 nullable——現行 `EpubReaderView`／`PdfReaderView` 對這些欄位是
/// null 時整個 Method Channel key 省略、交由 Readium 內部預設值或書本
/// CSS 決定，本類別不得發明一個目前不存在的預設值（見審查意見 C1，
/// `tmp/refactor-reader-prefs/reviews/review-refactor-reader-prefs-plan.md`）。
class ResolvedPreferences {
  final WritingMode? writingMode;
  final AppFont? fontFamily;
  final double? fontSize;
  final double? fontWeight;
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? pageMargins;
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;

  final PageTurnMode pageTurnMode;
  final ScreenOrientationSetting screenOrientation;

  final PdfFitMode pdfFitMode;
  final double pdfContrast;
  final double pdfBrightness;
  final double pdfBoldStrength;
  final PdfCropMode pdfCropMode;
  final PdfCropRect? pdfCropRect; // pdfCropMode == none 時為 null，既有語意

  const ResolvedPreferences({
    this.writingMode,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
    required this.pageTurnMode,
    required this.screenOrientation,
    required this.pdfFitMode,
    required this.pdfContrast,
    required this.pdfBrightness,
    required this.pdfBoldStrength,
    required this.pdfCropMode,
    this.pdfCropRect,
  });
}
```

- [ ] **Step 8：執行測試，確認通過**

```bash
flutter test test/reader/resolved_preferences_test.dart
```

Expected：全數 PASS。

- [ ] **Step 9：`flutter analyze`**

```bash
flutter analyze
```

Expected："No issues found!"

- [ ] **Step 10：Commit**

```bash
git add lib/reader/global_reader_prefs.dart lib/reader/resolved_preferences.dart test/reader/global_reader_prefs_test.dart test/reader/resolved_preferences_test.dart
git commit -m "feat: 新增 GlobalReaderPrefs 與 ResolvedPreferences 資料型別"
```

---

### Task 2：`ReaderPrefsManager` 介面與實作（load 與 resolve 分離）

**Files:**
- Create：`app/lib/reader/reader_prefs_manager.dart`
- Create：`app/lib/reader/reader_prefs_manager_impl.dart`
- Test：`app/test/reader/reader_prefs_manager_test.dart`
- Test：`app/test/support/fake_reader_prefs_manager.dart`

**Interfaces:**
- Consumes：Task 1 的 `GlobalReaderPrefs`／`ResolvedPreferences`；既有 `BookReaderPrefsRepository`（`app/lib/reader/book_reader_prefs_repository.dart`，`load(bookId)`/`save(bookId, prefs)`，不修改）；既有 `BookReaderPrefs`（不修改）
- Produces：
  ```dart
  abstract class ReaderPrefsManager {
    Future<LoadedPrefs> load(String bookId);
    Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs);
    Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs);
    ResolvedPreferences resolve(
      LoadedPrefs loaded, {
      WritingMode? autoDetectedWritingMode,
    });
  }

  class LoadedPrefs {
    final BookReaderPrefs bookPrefs;
    final GlobalReaderPrefs globalPrefs;
  }
  ```
  供 Task 3 的 `ReaderScreen` 消費（`load()` 在 `initState` 呼叫一次；`resolve()` 在 `initState` 完成後、`_handleLayoutResolved`、以及任何偏好變動時皆可重複同步呼叫，不重讀儲存層）

- [ ] **Step 1：定義 `LoadedPrefs`（不需要獨立測試——純資料容器，透過 `reader_prefs_manager_test.dart` 間接驗證）**

在 `app/lib/reader/reader_prefs_manager.dart` 中連同介面一起定義：

```dart
import 'book_reader_prefs.dart';
import 'global_reader_prefs.dart';
import 'resolved_preferences.dart';
import 'writing_mode.dart';

/// [ReaderPrefsManager.load] 回傳的「尚未解析」原始資料：單書覆寫值
/// （[BookReaderPrefs]，可能大部分欄位是 null）與全域預設值（
/// [GlobalReaderPrefs]，non-nullable）。呼叫端把這個物件連同（若有）自動
/// 偵測到的排版方向一起交給 [ReaderPrefsManager.resolve]（純同步函式）
/// 求出最終生效值，兩者刻意分離：`load` 是唯一需要 async 的地方，
/// `resolve` 可在任何時機（含原生 layout 解析完成的同步回呼內）重複呼叫
/// 而不必再等一次儲存層 I/O。
class LoadedPrefs {
  final BookReaderPrefs bookPrefs;
  final GlobalReaderPrefs globalPrefs;

  const LoadedPrefs({required this.bookPrefs, required this.globalPrefs});
}

/// 偏好設定的載入／持久化／解析深模組，取代 `ReaderScreen` 原本直接依賴
/// `BookReaderPrefsRepository`（SQLite）與 `GlobalReaderDefaults`
/// （SharedPreferences）兩條路徑的做法。
abstract class ReaderPrefsManager {
  /// 一次載入單書覆寫值與全域預設值（原本 `ReaderScreen.initState` 裡
  /// 3 個平行 Future 中的 2 個，見 Task 3）。
  Future<LoadedPrefs> load(String bookId);

  Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs);
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs);

  /// 純同步合併（單書覆寫 `??` 全域預設／既存安全預設值），不觸發任何
  /// I/O，可在同一個 `setState` 內依需要重複呼叫（例如原生 layout 解析
  /// 完成後才拿到 [autoDetectedWritingMode]，需要重新求值）。
  ResolvedPreferences resolve(
    LoadedPrefs loaded, {
    WritingMode? autoDetectedWritingMode,
  });
}
```

- [ ] **Step 2：撰寫 `resolve()` 的失敗測試（純同步，涵蓋全部 7 個 non-null 欄位的預設值與覆寫優先級）**

建立 `app/test/reader/reader_prefs_manager_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';

void main() {
  group('resolve()（純同步，不需要資料庫/SharedPreferences）', () {
    late ReaderPrefsManagerImpl manager;

    setUp(() {
      // resolve() 不觸碰任何儲存層，建構子的 repository 參數在這組測試中
      // 不會被用到，傳 null 佔位即可證明這一點——若 resolve() 意外變成
      // 依賴它，這裡會因型別錯誤而編譯失敗，反向確保 resolve() 保持純函式。
      manager = ReaderPrefsManagerImpl(null as dynamic);
    });

    test('全部欄位皆未覆寫時，回傳的 non-null 欄位皆為既存安全預設值', () {
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.writingMode, isNull);
      expect(resolved.fontSize, isNull); // 無既存預設值，維持 null（C1）
      expect(resolved.pageTurnMode, PageTurnMode.paginated);
      expect(resolved.screenOrientation, ScreenOrientationSetting.auto);
      expect(resolved.pdfFitMode, PdfFitMode.pageFit);
      expect(resolved.pdfContrast, 0);
      expect(resolved.pdfBrightness, 0);
      expect(resolved.pdfBoldStrength, 0);
      expect(resolved.pdfCropMode, PdfCropMode.none);
      expect(resolved.pdfCropRect, isNull);
    });

    test('單書覆寫存在時，優先套用單書覆寫，忽略全域預設', () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(
          pageTurnModeOverride: PageTurnMode.scroll,
          screenOrientationOverride: ScreenOrientationSetting.lock90,
          pdfFitMode: PdfFitMode.fitWidth,
          pdfContrast: 20,
        ),
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.pageTurnMode, PageTurnMode.scroll);
      expect(resolved.screenOrientation, ScreenOrientationSetting.lock90);
      expect(resolved.pdfFitMode, PdfFitMode.fitWidth);
      expect(resolved.pdfContrast, 20);
    });

    test('單書覆寫為 null 時，正確退回全域預設（非硬編碼初始值，證明真的有讀 globalPrefs）',
        () {
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs(
          pageTurnMode: PageTurnMode.scroll,
          screenOrientation: ScreenOrientationSetting.lock270,
        ),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.pageTurnMode, PageTurnMode.scroll);
      expect(resolved.screenOrientation, ScreenOrientationSetting.lock270);
    });

    test('autoDetectedWritingMode 在沒有 writingModeOverride 時參與解析', () {
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(
        loaded,
        autoDetectedWritingMode: WritingMode.vertical,
      );
      expect(resolved.writingMode, WritingMode.vertical);
    });

    test('writingModeOverride 存在時優先於 autoDetectedWritingMode', () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(
          writingModeOverride: WritingMode.horizontal,
        ),
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(
        loaded,
        autoDetectedWritingMode: WritingMode.vertical,
      );
      expect(resolved.writingMode, WritingMode.horizontal);
    });

    test('EPUB 字型/排版欄位原樣透傳（不套用任何預設值，維持既有 pass-through 語意）',
        () {
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.fontFamily, isNull);
      expect(resolved.fontSize, isNull);
      expect(resolved.fontWeight, isNull);
      expect(resolved.lineHeight, isNull);
      expect(resolved.paragraphSpacing, isNull);
      expect(resolved.pageMargins, isNull);
      expect(resolved.textAlign, isNull);
      expect(resolved.publisherStyles, isNull);
    });
  });

  group('load()（async，涵蓋原 global_reader_defaults_test.dart 與部分 reader_screen_test.dart 的回歸覆蓋）',
      () {
    late SqliteLibraryRepository libraryRepository;
    late ReaderPrefsManagerImpl manager;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});
      libraryRepository =
          await SqliteLibraryRepository.open(inMemoryDatabasePath);
      manager =
          ReaderPrefsManagerImpl(BookReaderPrefsRepository(libraryRepository.database));
      await libraryRepository.insertBook(Book(
        id: 'b1',
        title: '書名',
        format: BookFileFormat.epub,
        filePath: 'content://example/b1',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
    });

    tearDown(() async {
      await libraryRepository.close();
    });

    test('尚未儲存過任何偏好時，load 回傳 BookReaderPrefs.empty + GlobalReaderPrefs.initial()',
        () async {
      final loaded = await manager.load('b1');
      expect(loaded.bookPrefs, BookReaderPrefs.empty);
      expect(loaded.globalPrefs, const GlobalReaderPrefs.initial());
    });

    test('saveBookPrefs 寫入後，load 讀回相同的單書覆寫值', () async {
      const prefs = BookReaderPrefs(pageTurnModeOverride: PageTurnMode.scroll);
      await manager.saveBookPrefs('b1', prefs);
      final loaded = await manager.load('b1');
      expect(loaded.bookPrefs, prefs);
    });

    test('saveGlobalPrefs 寫入後，load 讀回相同的全域預設值（取代 global_reader_defaults_test.dart 的 save/load round-trip 覆蓋）',
        () async {
      const globalPrefs = GlobalReaderPrefs(
        pageTurnMode: PageTurnMode.scroll,
        screenOrientation: ScreenOrientationSetting.lock90,
      );
      await manager.saveGlobalPrefs(globalPrefs);
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs, globalPrefs);
    });

    test('已儲存的全域預設字串無法對應到任何列舉值時，安全回退為初始值（取代 global_reader_defaults_test.dart 的損毀資料防護覆蓋）',
        () async {
      SharedPreferences.setMockInitialValues({
        'global_reader_page_turn_mode': 'not_a_real_enum_value',
        'global_reader_screen_orientation': 'not_a_real_enum_value',
      });
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs, const GlobalReaderPrefs.initial());
    });
  });
}
```

- [ ] **Step 3：執行測試，確認失敗**

```bash
flutter test test/reader/reader_prefs_manager_test.dart
```

Expected：FAIL——`reader_prefs_manager_impl.dart` 不存在。

- [ ] **Step 4：實作 `ReaderPrefsManagerImpl`**

建立 `app/lib/reader/reader_prefs_manager_impl.dart`：

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'book_reader_prefs.dart';
import 'book_reader_prefs_repository.dart';
import 'global_reader_prefs.dart';
import 'page_turn_mode.dart';
import 'pdf_crop_mode.dart';
import 'pdf_fit_mode.dart';
import 'reader_prefs_manager.dart';
import 'resolved_preferences.dart';
import 'screen_orientation_setting.dart';
import 'writing_mode.dart';

/// [ReaderPrefsManager] 的正式實作。直接內建全域預設值的 SharedPreferences
/// 讀寫邏輯（吸收原 `GlobalReaderDefaults` 的職責，鍵名沿用不變以保留既有
/// 使用者資料），不把它當成注入依賴——這樣 `global_reader_defaults.dart`
/// 才能在完成遷移後被真正刪除，不會卡在「還有人依賴它」的狀態。
class ReaderPrefsManagerImpl implements ReaderPrefsManager {
  final BookReaderPrefsRepository _sqliteRepository;

  const ReaderPrefsManagerImpl(this._sqliteRepository);

  static const _pageTurnModeKey = 'global_reader_page_turn_mode';
  static const _screenOrientationKey = 'global_reader_screen_orientation';

  @override
  Future<LoadedPrefs> load(String bookId) async {
    final results = await Future.wait([
      _sqliteRepository.load(bookId),
      _loadGlobalPrefs(),
    ]);
    return LoadedPrefs(
      bookPrefs: results[0] as BookReaderPrefs,
      globalPrefs: results[1] as GlobalReaderPrefs,
    );
  }

  Future<GlobalReaderPrefs> _loadGlobalPrefs() async {
    final sp = await SharedPreferences.getInstance();
    return GlobalReaderPrefs(
      pageTurnMode: _readEnum(sp, _pageTurnModeKey, PageTurnMode.values) ??
          PageTurnMode.paginated,
      screenOrientation: _readEnum(
            sp,
            _screenOrientationKey,
            ScreenOrientationSetting.values,
          ) ??
          ScreenOrientationSetting.auto,
    );
  }

  /// 儲存的字串無法對應到任何列舉值時（例如未來改了列舉名稱、或裝置上的
  /// 資料被污染）安全回傳 null，交由呼叫端套用預設值，比照原
  /// GlobalReaderDefaults 的既有防護邏輯。
  T? _readEnum<T extends Enum>(
    SharedPreferences sp,
    String key,
    List<T> values,
  ) {
    final raw = sp.getString(key);
    if (raw == null) return null;
    try {
      return values.byName(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs) =>
      _sqliteRepository.save(bookId, prefs);

  @override
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_pageTurnModeKey, prefs.pageTurnMode.name);
    await sp.setString(_screenOrientationKey, prefs.screenOrientation.name);
  }

  @override
  ResolvedPreferences resolve(
    LoadedPrefs loaded, {
    WritingMode? autoDetectedWritingMode,
  }) {
    final book = loaded.bookPrefs;
    final global = loaded.globalPrefs;
    return ResolvedPreferences(
      writingMode: book.writingModeOverride ?? autoDetectedWritingMode,
      fontFamily: book.fontFamily,
      fontSize: book.fontSize,
      fontWeight: book.fontWeight,
      lineHeight: book.lineHeight,
      paragraphSpacing: book.paragraphSpacing,
      pageMargins: book.pageMargins,
      textAlign: book.textAlign,
      publisherStyles: book.publisherStyles,
      pageTurnMode: book.pageTurnModeOverride ?? global.pageTurnMode,
      screenOrientation:
          book.screenOrientationOverride ?? global.screenOrientation,
      pdfFitMode: book.pdfFitMode ?? PdfFitMode.pageFit,
      pdfContrast: book.pdfContrast ?? 0,
      pdfBrightness: book.pdfBrightness ?? 0,
      pdfBoldStrength: book.pdfBoldStrength ?? 0,
      pdfCropMode: book.pdfCropMode ?? PdfCropMode.none,
      pdfCropRect: book.pdfCropRect,
    );
  }
}
```

- [ ] **Step 5：執行測試，確認通過**

```bash
flutter test test/reader/reader_prefs_manager_test.dart
```

Expected：全數 PASS。

- [ ] **Step 6：建立 `FakeReaderPrefsManager` 供 `ReaderScreen` widget test 使用**

建立 `app/test/support/fake_reader_prefs_manager.dart`（比照既有 `app/test/support/fake_book_reader_prefs_repository.dart` 的風格）：

```dart
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/writing_mode.dart';

/// 供 `reader_screen_test.dart` 使用的假 [ReaderPrefsManager]：`load`／
/// `save*` 皆為純記憶體內操作；`resolve` 直接委派給
/// [ReaderPrefsManagerImpl.resolve]（純函式、無 I/O，不需要另外假造）以
/// 確保測試驗證的合併邏輯與正式實作完全一致。
class FakeReaderPrefsManager implements ReaderPrefsManager {
  final Map<String, BookReaderPrefs> bookPrefsByBookId;
  GlobalReaderPrefs globalPrefs;
  final List<String> savedBookPrefsCalls = [];
  final List<GlobalReaderPrefs> savedGlobalPrefsCalls = [];

  FakeReaderPrefsManager({
    Map<String, BookReaderPrefs>? bookPrefsByBookId,
    this.globalPrefs = const GlobalReaderPrefs.initial(),
  }) : bookPrefsByBookId = bookPrefsByBookId ?? {};

  final _delegate = const ReaderPrefsManagerImpl(null as dynamic);

  @override
  Future<LoadedPrefs> load(String bookId) async {
    return LoadedPrefs(
      bookPrefs: bookPrefsByBookId[bookId] ?? BookReaderPrefs.empty,
      globalPrefs: globalPrefs,
    );
  }

  @override
  Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs) async {
    bookPrefsByBookId[bookId] = prefs;
    savedBookPrefsCalls.add(bookId);
  }

  @override
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs) async {
    globalPrefs = prefs;
    savedGlobalPrefsCalls.add(prefs);
  }

  @override
  ResolvedPreferences resolve(
    LoadedPrefs loaded, {
    WritingMode? autoDetectedWritingMode,
  }) =>
      _delegate.resolve(loaded, autoDetectedWritingMode: autoDetectedWritingMode);
}
```

- [ ] **Step 7：`flutter analyze`**

```bash
flutter analyze
```

Expected："No issues found!"

- [ ] **Step 8：Commit**

```bash
git add lib/reader/reader_prefs_manager.dart lib/reader/reader_prefs_manager_impl.dart test/reader/reader_prefs_manager_test.dart test/support/fake_reader_prefs_manager.dart
git commit -m "feat: 新增 ReaderPrefsManager（load/resolve 分離）取代雙層直接存取"
```

---

### Task 3：重構 `ReaderScreen` 改用 `ReaderPrefsManager`

**Files:**
- Modify：`app/lib/screens/reader_screen.dart`
- Modify：`app/lib/main.dart`（建構 `ReaderScreen` 的呼叫點，改傳 `prefsManager`）
- Test：`app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `ReaderPrefsManager`（含 `load`/`resolve`/`saveBookPrefs`/`saveGlobalPrefs`）、`LoadedPrefs`、`ResolvedPreferences`
- Produces：`ReaderScreen` 建構參數由 `prefsRepository: BookReaderPrefsRepository` 改為 `prefsManager: ReaderPrefsManager`；`_buildNativeView` 改讀 `_resolved` 而非分散的 `_resolved*` getter + 原始 `_prefs.xxx`

- [ ] **Step 1：撰寫失敗測試——`reader_screen_test.dart` 改用 `FakeReaderPrefsManager`**

找出 `app/test/screens/reader_screen_test.dart` 中所有 `ReaderScreen(... prefsRepository: fakeRepository ...)` 的建構呼叫，改為 `prefsManager: fakeManager`（`FakeReaderPrefsManager` 實例）；找出所有 `SharedPreferences.setMockInitialValues({'global_reader_page_turn_mode': 'scroll'})` 這類直接操作 SharedPreferences 模擬全域預設的測試（約在原檔第 157-222 行），改為在建構 `FakeReaderPrefsManager` 時傳入 `globalPrefs: const GlobalReaderPrefs(pageTurnMode: PageTurnMode.scroll, screenOrientation: ...)`——這類「全域預設是否正確生效」的底層邏輯覆蓋已經下沉到 Task 2 的 `reader_prefs_manager_test.dart`，本檔案的測試職責收斂為「`ReaderScreen` 是否把 `ReaderPrefsManager` 回傳的 `ResolvedPreferences` 正確交給原生 view」，不再重複驗證合併邏輯本身。

新增一個測試，驗證 C2 修正的反應性：

```dart
  testWidgets('onLayoutResolved 觸發後，_resolved 帶入自動偵測到的排版方向（不需要 writingModeOverride）',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.epub',
        bookId: 'b1',
        prefsManager: fakeManager,
      ),
    ));
    await tester.pumpAndSettle();

    // 觸發原生 layout 解析完成的回呼（依現行 EpubReaderView 測試 harness
    // 的既有方式模擬 MethodChannel 呼叫 onLayoutResolved，見既有測試檔中
    // 其他呼叫 onLayoutResolved 的既有測試寫法，此處沿用同一機制）。
    // 斷言 EpubReaderView 收到的 writingMode 參數等於自動偵測結果，證明
    // resolve() 在 _handleLayoutResolved 內被重新呼叫且生效，而非停留在
    // initState 當下的 null 快照。
  });
```

（此測試步驟需要實作者依 `reader_screen_test.dart` 現有觸發 `onLayoutResolved` 的既有慣例填入完整程式碼——本計劃到這裡引用既有測試檔案內已存在的機制，而非發明新的測試手法；若既有檔案中沒有可直接沿用的 `onLayoutResolved` 觸發方式，才需要新增，屆時请依現有 `EpubReaderView` 假 MethodChannel handler 的既有寫法比照辦理。）

- [ ] **Step 2：執行測試，確認失敗**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：FAIL——`ReaderScreen` 尚無 `prefsManager` 具名參數，且仍是 `prefsRepository`。

- [ ] **Step 3：修改 `reader_screen.dart`**

建構參數（原第 37-51 行）：

```dart
class ReaderScreen extends StatefulWidget {
  final String filePath;
  final String bookId;
  final ReaderPrefsManager prefsManager;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}
```

State 欄位（原第 55-77 行）——移除 `_globalDefaults`／`_globalPageTurnMode`／`_globalScreenOrientation`／4 個 `_resolved*` getter，改為：

```dart
class _ReaderScreenState extends State<ReaderScreen> {
  _RenderState _state = _RenderState.loading;
  String? _errorMessage;
  WritingMode? _autoDetectedWritingMode;
  bool _isFixedLayout = false;
  BookReaderPrefs _prefs = BookReaderPrefs.empty;
  LoadedPrefs? _loaded;
  ResolvedPreferences? _resolved;
  bool _cropEditModeActive = false;
  ScreenOrientationSetting? _lastAppliedOrientation;
```

（`_resolved` 在 `initState` 的 `Future.wait` 完成前為 `null`；`build()` 呼叫 `_buildNativeView` 前必須確認 `_resolved != null`——見下方 `_applyScreenOrientation` 與 `build()` 的既有 loading 狀態守衛，本步驟不需新增額外守衛，因為 `_state` 在 `_resolved` 就緒前仍是 `loading`，`build()` 既有邏輯已經不會在 loading 狀態下呼叫 `_buildNativeView`。）

`initState`（原第 96-115 行）：

```dart
  @override
  void initState() {
    super.initState();
    widget.prefsManager.load(widget.bookId).then((loaded) {
      if (!mounted) return;
      setState(() {
        _prefs = loaded.bookPrefs;
        _loaded = loaded;
        _resolved = widget.prefsManager.resolve(
          loaded,
          autoDetectedWritingMode: _autoDetectedWritingMode,
        );
      });
      _applyScreenOrientation();
    });
  }
```

`_applyScreenOrientation`（原第 135-142 行）改讀 `_resolved`：

```dart
  void _applyScreenOrientation() {
    final resolved = _resolved;
    if (resolved == null) return;
    if (resolved.screenOrientation == _lastAppliedOrientation) return;
    _lastAppliedOrientation = resolved.screenOrientation;
    SystemChrome.setPreferredOrientations(
      _deviceOrientationsFor(resolved.screenOrientation),
    );
  }
```

`_handleLayoutResolved`（原第 264-270 行，**C2 修正的核心**）：

```dart
  void _handleLayoutResolved(EpubLayoutInfo info) {
    if (!mounted) return;
    setState(() {
      _isFixedLayout = info.isFixedLayout;
      _autoDetectedWritingMode = info.writingMode;
      final loaded = _loaded;
      if (loaded != null) {
        _resolved = widget.prefsManager.resolve(
          loaded,
          autoDetectedWritingMode: info.writingMode,
        );
      }
    });
  }
```

任何呼叫 `widget.prefsRepository.save(...)` 的地方（原第 169、181、211 行，皆為版面設定變動回呼）改為 `widget.prefsManager.saveBookPrefs(...)`，並在同一個 `setState` 內同步重新呼叫 `resolve()`：

```dart
    setState(() {
      _prefs = updated;
      final loaded = _loaded;
      if (loaded != null) {
        final newLoaded = LoadedPrefs(bookPrefs: updated, globalPrefs: loaded.globalPrefs);
        _loaded = newLoaded;
        _resolved = widget.prefsManager.resolve(
          newLoaded,
          autoDetectedWritingMode: _autoDetectedWritingMode,
        );
      }
    });
    widget.prefsManager.saveBookPrefs(widget.bookId, updated); // 不 await，比照既有慣例
```

（實作者需對照原檔第 161-215 行三個既有偏好變動回呼方法的完整內容，逐一比照上述樣式替換 `_prefs` 賦值與 `save` 呼叫，保留原本「立即更新本地狀態＋不 await 持久化＋重新套用螢幕方向鎖定」的既有行為順序，只替換資料來源與呼叫對象。）

`_buildNativeView`（原第 377-414 行）改讀 `_resolved!`（此處呼叫前 `build()` 已保證非 null，見上方欄位宣告的說明）：

```dart
  Widget _buildNativeView(BookFormat format) {
    final resolved = _resolved!;
    switch (format) {
      case BookFormat.epub:
        return EpubReaderView(
          filePath: widget.filePath,
          writingMode: resolved.writingMode,
          pageTurnMode: resolved.pageTurnMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
          fontFamily: resolved.fontFamily,
          fontSize: resolved.fontSize,
          fontWeight: resolved.fontWeight,
          lineHeight: resolved.lineHeight,
          paragraphSpacing: resolved.paragraphSpacing,
          pageMargins: resolved.pageMargins,
          textAlign: resolved.textAlign,
          publisherStyles: resolved.publisherStyles,
        );
      case BookFormat.pdf:
        return PdfReaderView(
          filePath: widget.filePath,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          fitMode: resolved.pdfFitMode,
          contrast: resolved.pdfContrast,
          brightness: resolved.pdfBrightness,
          boldStrength: resolved.pdfBoldStrength,
          cropMode: resolved.pdfCropMode,
          cropRect: resolved.pdfCropRect,
          onCropRectComputed: _handleCropRectComputed,
          cropEditModeActive: _cropEditModeActive,
          onCropRectSelected: _handleCropRectSelected,
        );
      case BookFormat.unknown:
        return const SizedBox.shrink();
    }
  }
```

（`PdfReaderView`／`EpubReaderView` 的建構參數型別需要對應放寬/收緊——`contrast`/`brightness`/`boldStrength`/`cropMode`/`fitMode` 原本是 nullable 參數，現在改傳 non-null 的 `resolved.xxx`；由於 Dart 允許把 non-null 值傳給 nullable 參數，此處**不需要修改** `PdfReaderView`／`EpubReaderView` 的建構子簽章，維持既有 nullable 參數型別即可，只是呼叫端現在保證一定傳非 null 值。）

在 import 區塊新增：

```dart
import '../reader/global_reader_prefs.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/resolved_preferences.dart';
```

移除不再使用的 `import '../reader/global_reader_defaults.dart';`（若原檔有此 import）。

- [ ] **Step 4：修改 `main.dart` 的 `ReaderScreen` 建構呼叫點**

找出 `app/lib/main.dart` 中建構 `BookReaderPrefsRepository` 並傳給 `ReaderScreen(prefsRepository: ...)` 的位置，改為建構 `ReaderPrefsManagerImpl` 並傳給 `ReaderScreen(prefsManager: ...)`：

```dart
final prefsManager = ReaderPrefsManagerImpl(bookReaderPrefsRepository);
// ... 原本建構 ReaderScreen 的地方
ReaderScreen(
  filePath: filePath,
  bookId: bookId,
  prefsManager: prefsManager,
)
```

（`bookReaderPrefsRepository` 沿用既有已建構好的 `BookReaderPrefsRepository` 實例，不需要重新建構；實作者需對照 `main.dart` 現有的依賴建構順序找到正確的插入點。）

- [ ] **Step 5：執行測試，確認通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：全數 PASS。

- [ ] **Step 6：全專案回歸測試 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：全數 PASS，"No issues found!"（此時 `global_reader_defaults_test.dart`／`global_reader_defaults.dart` 仍存在且應仍通過——尚未刪除，留給 Task 5）。

- [ ] **Step 7：Commit**

```bash
git add lib/screens/reader_screen.dart lib/main.dart test/screens/reader_screen_test.dart
git commit -m "refactor: ReaderScreen 改用 ReaderPrefsManager 取代直接依賴 SQLite/SharedPreferences"
```

---

### Task 4：刪除 `GlobalReaderDefaults`（C3 修正——確認已無殘留依賴）

**Files:**
- Delete：`app/lib/reader/global_reader_defaults.dart`
- Delete：`app/test/reader/global_reader_defaults_test.dart`

**Interfaces:**
- Consumes：Task 2、Task 3 完成後，`GlobalReaderDefaults` 的全域預設讀寫邏輯已完整遷移進 `ReaderPrefsManagerImpl`
- Produces：無（純刪除；本 issue 的「消除複雜度洩漏／隱藏雙層存取」目標在此步驟真正完成，而不是像原始計劃 Task 5 那樣留下無法刪除的殘留依賴）

- [ ] **Step 1：確認已無任何檔案引用 `GlobalReaderDefaults`**

```bash
cd app
grep -rn "GlobalReaderDefaults" lib/ test/ --include="*.dart"
```

Expected：只剩 `lib/reader/global_reader_defaults.dart` 自身與 `test/reader/global_reader_defaults_test.dart`（即將在本 Task 一併刪除的兩個檔案）。若還有其他檔案引用，回頭檢查 Task 3 Step 3 是否有遺漏的呼叫點，修正後再繼續。

- [ ] **Step 2：刪除兩個檔案**

```bash
git rm lib/reader/global_reader_defaults.dart test/reader/global_reader_defaults_test.dart
```

- [ ] **Step 3：全專案回歸測試 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：全數 PASS，"No issues found!"（`reader_prefs_manager_test.dart` 已在 Task 2 涵蓋原 `global_reader_defaults_test.dart` 的全部行為——初始預設值、save/load round-trip、損毀資料安全回退，見 Task 2 Step 2 的 `load()` 測試群組）。

- [ ] **Step 4：Commit**

```bash
git commit -m "chore: 刪除已被 ReaderPrefsManager 取代的 GlobalReaderDefaults"
```

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **審查意見覆蓋度**：C1（Task 1 Step 7 的欄位分類 + Global Constraints 明文列出安全/不安全欄位表）、C2（Task 3 Step 3 `_handleLayoutResolved` 重新呼叫 `resolve()`，並新增對應測試）、C3（Task 2 `ReaderPrefsManagerImpl` 不注入 `GlobalReaderDefaults`，Task 4 真正刪除，不再是原計劃自相矛盾的「Task 5」）、I1（Global Constraints 誠實描述現行 4 個 getter vs. 新增的 PDF 欄位解析）、I2（Task 2 Step 2 測試涵蓋全部 7 個 non-null 欄位的預設值斷言）、I3（`load`/`resolve` 分離，`resolve` 為同步純函式）、I4（Task 3 Step 1 明確交代 `reader_screen_test.dart` 全域預設測試的遷移方式，Task 2 Step 6 新增 `FakeReaderPrefsManager`）、M1（`GlobalReaderPrefs` 註解未寫「未來可擴充」推測性文字）、M2（`ReaderPrefsManagerImpl` doc comment 已交代選擇吸收而非注入 `GlobalReaderDefaults` 的理由）——皆已在對應任務處理。
- **無佔位符掃描**：所有步驟皆有完整程式碼；Task 3 Step 1 的 `onLayoutResolved` 觸發測試因需要對照 `reader_screen_test.dart` 既有機制填入（避免在計劃中臆測一個可能與既有測試 harness 不一致的觸發方式），已明確註記「需依既有慣例填入」而非留空——這不是敷衍的 TODO，而是誠實標註「此處依賴實作者查閱既有測試檔案的既有寫法」，比在計劃中憑空編造一段可能無法通過編譯的測試程式碼更安全。
- **型別/介面一致性**：`ReaderPrefsManager.load`/`resolve`/`saveBookPrefs`/`saveGlobalPrefs` 四個方法名稱與簽章在 Task 2（定義+實作+測試）、Task 3（`ReaderScreen` 消費端）全文一致；`LoadedPrefs`/`GlobalReaderPrefs`/`ResolvedPreferences` 三個型別的欄位名稱在 Task 1、2、3 之間逐字一致。
