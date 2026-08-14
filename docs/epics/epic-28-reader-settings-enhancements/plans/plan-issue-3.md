# Epic 28 Issue 3 — 版面設定預設集（存 3 組具名預設集）＋書籍設定複製 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者在流式 EPUB 版面設定（`ReaderSettingsSheet`）另存最多 3 組具名版面設定預設集並跨書套用，並可不經預設集直接複製其他書籍目前的版面設定；套用目標可為目前書籍（即時生效，無需確認）或批次套用到其他流式 EPUB 書籍（需二次確認）。PDF/FXL 書籍不出現在選書清單、不受影響。

**Architecture:** 新表 `layout_preset`（`prefs_json` 為過濾後 `BookReaderPrefs` 的 JSON 序列化，非逐欄位對應）由新的 `LayoutPresetRepository` 存取；`ReaderSettingsSheet` 純展示，新增 5 個 callback（`onSaveAsPreset`/`onApplyPreset`/`onApplyFromBook`/`onRequestBookPicker`/`onDeletePreset`）交由 `ReaderScreen` 完成實際 I/O、命名輸入、覆蓋選擇/確認對話框；書籍選擇器是新的獨立畫面 `LayoutPresetBookPickerScreen`，資料來源為新的 `LibraryRepository.listReflowableEpubBooks()` 資料庫層級過濾查詢。`BookReaderPrefs.fromMap()` 的 enum 反序列化改用容錯輔助函式 `enumByNameOrNull()`，同時服務既有 SQLite 路徑與本 Issue 新增的 JSON 路徑。

**Tech Stack:** Flutter/Dart、`sqflite`（`Database.transaction()`）、`dart:convert`（`jsonEncode`/`jsonDecode`）。

**Spec:** `docs/epics/epic-28-reader-settings-enhancements/design.md`（「Issue 3：版面設定預設集 ＋ 書籍設定複製」「欄位範圍」）、`docs/epics/epic-28-reader-settings-enhancements/spec.md`（含 2026-08-14 審查修訂：enum 容錯反序列化、批次寫入、資料庫層書籍過濾、命名驗證、`updated_at`／排序、欄位污染防護、Bottom Sheet 同步）、`docs/epics/epic-28-reader-settings-enhancements/issues.md`「Issue 3」。

## Global Constraints

- 範圍僅**流式 EPUB**（`ReaderSettingsSheet`）。PDF/FXL 不適用，`listReflowableEpubBooks()` 明確排除。
- 最多 3 組具名預設集；名稱 trim 後 1~20 字元（超過截斷，見 `validateLayoutPresetName()`），允許重複名稱、不做唯一性檢查。
- 預設集排序固定 `id ASC`（插入順序），**不隨 `updatedAt` 重新排序**。`replace`（覆蓋）時 `id`／`created_at` 不變，`updated_at` 更新。
- `prefs_json` 儲存前必須經過 `BookReaderPrefs.reflowableEpubFields()` 過濾（20 個流式 EPUB 欄位保留，其餘 PDF/雙頁/`pageMargins` 共 10 個欄位一律強制 `null`），不依賴「應該恆為 null」的假設。
- `BookReaderPrefs.fromMap()` 的 9 個 enum 欄位改用 `enumByNameOrNull()`（找不到對應名稱回傳 `null`，不拋 `ArgumentError`）——此函式同時服務既有 SQLite 讀取路徑與本 Issue 新增的 JSON 路徑，是本計畫的**第一個** Task（後續 Task 皆依賴它）。
- 批次寫入（套用到多本其他書籍）一律用 `BookReaderPrefsRepository.saveMultiple()`（單一 `Database.transaction()`），單一書籍（套用到目前書籍）繼續用既有 `save()`。
- 「套用到目前書籍」不需確認；「套用到其他書籍」（`targetBookIds.length > 1`）須先跳出「即將覆蓋 N 本書」確認對話框。
- SQLite `book_reader_prefs`/`books` 表結構本身**不變**——本 Issue 只新增一張完全獨立的 `layout_preset` 表，`version` 由 19 提升為 20（**實作前務必重新用 `grep -n "version:" app/lib/library/sqlite_library_repository.dart` 確認 `main` 當下實際數值，不可憑空假設**——`epic-24-pdf-engine-rebuild` Issue 11 若已先合併，此數值可能已經是 20，本 Issue 屆時需改用 21；本計畫寫作當下確認為 19）。
- **`design.md`「管理介面（新增/命名/刪除）」明確要求「刪除」能力，但 `spec.md`「UI 元件責任劃分」列出的 4 個 callback 遺漏了對應的刪除 callback——本計畫視為 `spec.md` 的一個小疏漏，補上第 5 個 callback `onDeletePreset(int id)`，以 `design.md`（產品需求源頭）為準。**
- 每完成一個 Task 就跑一次 `flutter analyze`，維持乾淨。

---

### Task 1：`enumByNameOrNull()` 容錯輔助函式 ＋ `BookReaderPrefs.fromMap()` 重構

**Files:**
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Test: `app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Produces: `T? enumByNameOrNull<T extends Enum>(List<T> values, String? name)`（頂層函式，`book_reader_prefs.dart` 內，找不到對應名稱或 `name` 為 `null` 時回傳 `null`）。

- [ ] **Step 1: 寫失敗測試——`enumByNameOrNull()` 行為與 `fromMap()` 容錯**

編輯 `app/test/reader/book_reader_prefs_test.dart`，於檔案結尾（`main()` 函式關閉大括號之前）新增：

```dart
  group('enumByNameOrNull', () {
    test('找不到對應名稱時回傳 null，不拋出例外', () {
      expect(enumByNameOrNull(EpubTextAlign.values, 'not_a_real_value'), isNull);
    });

    test('name 為 null 時回傳 null', () {
      expect(enumByNameOrNull(EpubTextAlign.values, null), isNull);
    });

    test('找得到時正確回傳對應列舉值', () {
      expect(enumByNameOrNull(EpubTextAlign.values, 'center'), EpubTextAlign.center);
    });
  });

  test('fromMap 對未知的列舉名稱字串安全降級為 null，不拋出例外（epic-28 Issue 3 反序列化容錯，服務 SQLite 與 JSON 兩條路徑）',
      () {
    final map = BookReaderPrefs.empty.toMap('book-1')
      ..['text_align'] = 'not_a_real_enum_value'
      ..['writing_mode_override'] = 'not_a_real_enum_value'
      ..['page_turn_mode_override'] = 'not_a_real_enum_value'
      ..['screen_orientation_override'] = 'not_a_real_enum_value'
      ..['pdf_fit_mode'] = 'not_a_real_enum_value'
      ..['pdf_crop_mode'] = 'not_a_real_enum_value'
      ..['dual_page_mode'] = 'not_a_real_enum_value'
      ..['dual_page_direction'] = 'not_a_real_enum_value'
      ..['column_mode'] = 'not_a_real_enum_value';

    final restored = BookReaderPrefs.fromMap(map);

    expect(restored.textAlign, isNull);
    expect(restored.writingModeOverride, isNull);
    expect(restored.pageTurnModeOverride, isNull);
    expect(restored.screenOrientationOverride, isNull);
    expect(restored.pdfFitMode, isNull);
    expect(restored.pdfCropMode, isNull);
    expect(restored.dualPageMode, isNull);
    expect(restored.dualPageDirection, isNull);
    expect(restored.columnMode, isNull);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/reader/book_reader_prefs_test.dart`
預期：編譯錯誤（`enumByNameOrNull` 不存在）。

- [ ] **Step 3: 新增 `enumByNameOrNull()` 並重構 `fromMap()` 的 9 個 enum 欄位**

編輯 `app/lib/reader/book_reader_prefs.dart`：

於 import 區塊之後、`class BookReaderPrefs` 之前（第 11 行與第 12 行之間）新增：

```dart

/// 依名稱從 [values] 尋找對應列舉值，找不到時回傳 `null`（而非拋出
/// `ArgumentError`，`EnumType.values.byName()` 的既有行為）——用於服務
/// 可能讀到「目前 App 版本不認識的列舉名稱」的反序列化路徑（既有
/// `book_reader_prefs` SQLite 讀取路徑與 epic-28-reader-settings-
/// enhancements Issue 3 新增的 `layout_preset.prefs_json` JSON 讀取路徑
/// 皆共用同一份 [BookReaderPrefs.fromMap] 程式碼），`null` 在
/// [BookReaderPrefs] 語意上正是「未覆寫/採用預設」，是最安全的降級行為。
T? enumByNameOrNull<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
```

於 `fromMap()`（既有的 9 處 `EnumType.values.byName(map['key'] as String)` 三元運算式）整段替換：

原本（第 156-201 行區間，逐一列出）：

```dart
      textAlign: map['text_align'] == null
          ? null
          : EpubTextAlign.values.byName(map['text_align'] as String),
      publisherStyles: map['publisher_styles'] == null
          ? null
          : (map['publisher_styles'] as int) == 1,
      writingModeOverride: map['writing_mode_override'] == null
          ? null
          : WritingMode.values.byName(map['writing_mode_override'] as String),
      pageTurnModeOverride: map['page_turn_mode_override'] == null
          ? null
          : PageTurnMode.values
              .byName(map['page_turn_mode_override'] as String),
      screenOrientationOverride: map['screen_orientation_override'] == null
          ? null
          : ScreenOrientationSetting.values
              .byName(map['screen_orientation_override'] as String),
      pdfFitMode: map['pdf_fit_mode'] == null
          ? null
          : PdfFitMode.values.byName(map['pdf_fit_mode'] as String),
      pdfContrast: (map['pdf_contrast'] as num?)?.toDouble(),
      pdfBrightness: (map['pdf_brightness'] as num?)?.toDouble(),
      pdfBoldStrength: (map['pdf_bold_strength'] as num?)?.toDouble(),
      pdfCropMode: map['pdf_crop_mode'] == null
          ? null
          : PdfCropMode.values.byName(map['pdf_crop_mode'] as String),
      pdfCropRect: map['pdf_crop_rect'] == null
          ? null
          : PdfCropRect.fromJson(map['pdf_crop_rect'] as String),
      dualPageMode: map['dual_page_mode'] == null
          ? null
          : DualPageMode.values.byName(map['dual_page_mode'] as String),
      dualPageCoverAlone: map['dual_page_cover_alone'] == null
          ? null
          : (map['dual_page_cover_alone'] as int) == 1,
      dualPageDirection: map['dual_page_direction'] == null
          ? null
          : DualPageDirection.values
              .byName(map['dual_page_direction'] as String),
      showHeader:
          map['show_header'] == null ? null : (map['show_header'] as int) == 1,
      showFooter:
          map['show_footer'] == null ? null : (map['show_footer'] as int) == 1,
      columnMode: map['column_mode'] == null
          ? null
          : ColumnMode.values.byName(map['column_mode'] as String),
      columnSize: (map['column_size'] as num?)?.toDouble(),
      fullscreen:
          map['fullscreen'] == null ? null : (map['fullscreen'] as int) == 1,
```

改為：

```dart
      textAlign:
          enumByNameOrNull(EpubTextAlign.values, map['text_align'] as String?),
      publisherStyles: map['publisher_styles'] == null
          ? null
          : (map['publisher_styles'] as int) == 1,
      writingModeOverride: enumByNameOrNull(
          WritingMode.values, map['writing_mode_override'] as String?),
      pageTurnModeOverride: enumByNameOrNull(
          PageTurnMode.values, map['page_turn_mode_override'] as String?),
      screenOrientationOverride: enumByNameOrNull(
          ScreenOrientationSetting.values,
          map['screen_orientation_override'] as String?),
      pdfFitMode:
          enumByNameOrNull(PdfFitMode.values, map['pdf_fit_mode'] as String?),
      pdfContrast: (map['pdf_contrast'] as num?)?.toDouble(),
      pdfBrightness: (map['pdf_brightness'] as num?)?.toDouble(),
      pdfBoldStrength: (map['pdf_bold_strength'] as num?)?.toDouble(),
      pdfCropMode:
          enumByNameOrNull(PdfCropMode.values, map['pdf_crop_mode'] as String?),
      pdfCropRect: map['pdf_crop_rect'] == null
          ? null
          : PdfCropRect.fromJson(map['pdf_crop_rect'] as String),
      dualPageMode: enumByNameOrNull(
          DualPageMode.values, map['dual_page_mode'] as String?),
      dualPageCoverAlone: map['dual_page_cover_alone'] == null
          ? null
          : (map['dual_page_cover_alone'] as int) == 1,
      dualPageDirection: enumByNameOrNull(
          DualPageDirection.values, map['dual_page_direction'] as String?),
      showHeader:
          map['show_header'] == null ? null : (map['show_header'] as int) == 1,
      showFooter:
          map['show_footer'] == null ? null : (map['show_footer'] as int) == 1,
      columnMode:
          enumByNameOrNull(ColumnMode.values, map['column_mode'] as String?),
      columnSize: (map['column_size'] as num?)?.toDouble(),
      fullscreen:
          map['fullscreen'] == null ? null : (map['fullscreen'] as int) == 1,
```

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/reader/book_reader_prefs_test.dart`
預期：全數 PASS（含既有全部 `fromMap`/`toMap` round-trip 測試——合法列舉名稱的行為與重構前逐位元組相同）。

- [ ] **Step 5: 執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test test/reader/`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/book_reader_prefs.dart app/test/reader/book_reader_prefs_test.dart
git commit -m "feat(epic-28): Issue 3 Task 1——enumByNameOrNull 容錯輔助函式，BookReaderPrefs.fromMap() 重構"
```

---

### Task 2：`BookReaderPrefs.reflowableEpubFields()` 欄位污染防護

**Files:**
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Test: `app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Produces: `BookReaderPrefs.reflowableEpubFields()`（實例方法，回傳只保留 20 個流式 EPUB 欄位、其餘 10 個 PDF/雙頁/`pageMargins` 欄位強制為 `null` 的新物件）。

- [ ] **Step 1: 寫失敗測試——過濾行為**

編輯 `app/test/reader/book_reader_prefs_test.dart`，於檔案結尾新增：

```dart
  test('reflowableEpubFields() 過濾掉 PDF／雙頁／pageMargins 共 10 個欄位，其餘 20 個流式 EPUB 欄位保留（epic-28 Issue 3 欄位污染防護）',
      () {
    const prefs = BookReaderPrefs(
      fontFamily: 'SourceHanSansTC',
      fontSize: 18,
      fontWeight: 1.5,
      lineHeight: 1.6,
      paragraphSpacing: 12,
      letterSpacing: 0.1,
      marginTop: 40,
      marginBottom: 20,
      marginLeft: 24,
      marginRight: 24,
      textAlign: EpubTextAlign.justify,
      publisherStyles: false,
      writingModeOverride: WritingMode.vertical,
      pageTurnModeOverride: PageTurnMode.scroll,
      screenOrientationOverride: ScreenOrientationSetting.lock90,
      showHeader: true,
      showFooter: false,
      fullscreen: true,
      columnMode: ColumnMode.double,
      columnSize: 800,
      pageMargins: 20,
      pdfFitMode: PdfFitMode.fitWidth,
      pdfContrast: 20,
      pdfBrightness: -10,
      pdfBoldStrength: 0.5,
      pdfCropMode: PdfCropMode.manual,
      pdfCropRect: PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
      dualPageMode: DualPageMode.always,
      dualPageCoverAlone: false,
      dualPageDirection: DualPageDirection.ltr,
    );

    final filtered = prefs.reflowableEpubFields();

    // 20 個保留欄位。
    expect(filtered.fontFamily, 'SourceHanSansTC');
    expect(filtered.fontSize, 18);
    expect(filtered.fontWeight, 1.5);
    expect(filtered.lineHeight, 1.6);
    expect(filtered.paragraphSpacing, 12);
    expect(filtered.letterSpacing, 0.1);
    expect(filtered.marginTop, 40);
    expect(filtered.marginBottom, 20);
    expect(filtered.marginLeft, 24);
    expect(filtered.marginRight, 24);
    expect(filtered.textAlign, EpubTextAlign.justify);
    expect(filtered.publisherStyles, isFalse);
    expect(filtered.writingModeOverride, WritingMode.vertical);
    expect(filtered.pageTurnModeOverride, PageTurnMode.scroll);
    expect(filtered.screenOrientationOverride, ScreenOrientationSetting.lock90);
    expect(filtered.showHeader, isTrue);
    expect(filtered.showFooter, isFalse);
    expect(filtered.fullscreen, isTrue);
    expect(filtered.columnMode, ColumnMode.double);
    expect(filtered.columnSize, 800);

    // 10 個強制清空欄位。
    expect(filtered.pageMargins, isNull);
    expect(filtered.pdfFitMode, isNull);
    expect(filtered.pdfContrast, isNull);
    expect(filtered.pdfBrightness, isNull);
    expect(filtered.pdfBoldStrength, isNull);
    expect(filtered.pdfCropMode, isNull);
    expect(filtered.pdfCropRect, isNull);
    expect(filtered.dualPageMode, isNull);
    expect(filtered.dualPageCoverAlone, isNull);
    expect(filtered.dualPageDirection, isNull);
  });

  test('reflowableEpubFields() 對全部欄位皆為 null 的輸入，回傳值仍全部為 null（不引入非預期的預設值）',
      () {
    final filtered = BookReaderPrefs.empty.reflowableEpubFields();
    expect(filtered, BookReaderPrefs.empty);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/reader/book_reader_prefs_test.dart`
預期：編譯錯誤（`reflowableEpubFields` 不存在）。

- [ ] **Step 3: 新增 `reflowableEpubFields()`**

編輯 `app/lib/reader/book_reader_prefs.dart`，於 `copyWith()` 方法（Step 3 結束位置，`}` 之後、`class BookReaderPrefs` 結尾 `}` 之前）新增：

```dart

  /// 只保留 [ReaderSettingsSheet]（流式 EPUB 版面設定）實際呈現的 20 個
  /// 欄位，其餘 10 個欄位（`pageMargins`、6 個 `pdf*`、3 個 `dualPage*`）
  /// 一律強制設為 `null`，**不論來源物件實際內容為何**——epic-28-reader-
  /// settings-enhancements Issue 3「欄位污染防護」，見 spec.md「資料
  /// 模型」。「另存為預設集」與「書籍設定複製」寫入 `LayoutPreset.prefs`
  /// 前皆須經過這道過濾，不依賴「這些欄位在流式 EPUB 情境下結構性恆為
  /// null」的假設（來源書籍若曾經歷人工版面覆蓋/FXL↔流式切換，可能殘留
  /// 非 null 的污染欄位）。刻意不使用 `copyWith()`——`copyWith()` 是
  /// `newValue ?? this.value` 語意，無法明確把欄位清成 `null`（見
  /// `copyWith()` 文件註解），需要整列建構。
  BookReaderPrefs reflowableEpubFields() {
    return BookReaderPrefs(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      lineHeight: lineHeight,
      paragraphSpacing: paragraphSpacing,
      letterSpacing: letterSpacing,
      marginTop: marginTop,
      marginBottom: marginBottom,
      marginLeft: marginLeft,
      marginRight: marginRight,
      textAlign: textAlign,
      publisherStyles: publisherStyles,
      writingModeOverride: writingModeOverride,
      pageTurnModeOverride: pageTurnModeOverride,
      screenOrientationOverride: screenOrientationOverride,
      showHeader: showHeader,
      showFooter: showFooter,
      fullscreen: fullscreen,
      columnMode: columnMode,
      columnSize: columnSize,
    );
  }
```

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/reader/book_reader_prefs_test.dart`
預期：全數 PASS。

- [ ] **Step 5: 執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test test/reader/`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/book_reader_prefs.dart app/test/reader/book_reader_prefs_test.dart
git commit -m "feat(epic-28): Issue 3 Task 2——BookReaderPrefs.reflowableEpubFields() 欄位污染防護"
```

---

### Task 3：`LayoutPreset` 模型 ＋ `validateLayoutPresetName()` 命名驗證

**Files:**
- Create: `app/lib/reader/layout_preset.dart`
- Test: `app/test/reader/layout_preset_test.dart`

**Interfaces:**
- Produces: `LayoutPreset`（`id`/`name`/`createdAt`/`updatedAt`/`prefs: BookReaderPrefs`）；`String? validateLayoutPresetName(String raw)`（trim 後為空回傳 `null`，超過 20 字元截斷，否則回傳已 trim 的字串）。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/reader/layout_preset_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/layout_preset.dart';

void main() {
  test('LayoutPreset 建構後各欄位正確保存', () {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(1000);
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(2000);
    const prefs = BookReaderPrefs(fontSize: 18);
    final preset = LayoutPreset(
      id: 1,
      name: '臥室夜讀直排',
      createdAt: createdAt,
      updatedAt: updatedAt,
      prefs: prefs,
    );

    expect(preset.id, 1);
    expect(preset.name, '臥室夜讀直排');
    expect(preset.createdAt, createdAt);
    expect(preset.updatedAt, updatedAt);
    expect(preset.prefs, prefs);
  });

  test('LayoutPreset 的 id 可為 null（尚未存入資料庫的暫存物件）', () {
    final preset = LayoutPreset(
      id: null,
      name: '暫存',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    );
    expect(preset.id, isNull);
  });

  group('validateLayoutPresetName', () {
    test('空字串回傳 null（拒絕）', () {
      expect(validateLayoutPresetName(''), isNull);
    });

    test('純空白字串回傳 null（拒絕）', () {
      expect(validateLayoutPresetName('   '), isNull);
    });

    test('一般名稱回傳已 trim 的字串', () {
      expect(validateLayoutPresetName('  臥室夜讀  '), '臥室夜讀');
    });

    test('超過 20 字元時截斷為 20 字元', () {
      final tooLong = 'a' * 25;
      final result = validateLayoutPresetName(tooLong);
      expect(result, hasLength(20));
      expect(result, 'a' * 20);
    });

    test('恰好 20 字元時原樣保留，不截斷', () {
      final exact = 'a' * 20;
      expect(validateLayoutPresetName(exact), exact);
    });
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/reader/layout_preset_test.dart`
預期：編譯錯誤（`app/lib/reader/layout_preset.dart` 不存在）。

- [ ] **Step 3: 建立 `LayoutPreset` 與 `validateLayoutPresetName()`**

建立 `app/lib/reader/layout_preset.dart`：

```dart
import 'book_reader_prefs.dart';

/// 版面設定預設集（epic-28-reader-settings-enhancements Issue 3），見
/// spec.md「資料模型」。[id] 為 `null` 代表尚未存入資料庫（新建立時的
/// 暫存物件）；一旦指定後在 `LayoutPresetRepository.replace()`（覆蓋）
/// 流程中維持不變（同一個 slot 身份）。[prefs] 快照內容須先經
/// `BookReaderPrefs.reflowableEpubFields()` 過濾才寫入，見該方法文件。
class LayoutPreset {
  final int? id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final BookReaderPrefs prefs;

  const LayoutPreset({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.prefs,
  });
}

/// 預設集命名驗證（spec.md「命名驗證」）：trim 後為空字串（含純空白輸入）
/// 回傳 `null`（拒絕儲存）；超過 20 字元直接截斷（design.md 允許的兩種
/// 處理方式之一——本專案選擇截斷而非拒絕輸入）；允許重複名稱，呼叫端
/// 不需要做唯一性檢查。
String? validateLayoutPresetName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length > 20 ? trimmed.substring(0, 20) : trimmed;
}
```

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/reader/layout_preset_test.dart`
預期：全數 PASS。

- [ ] **Step 5: 執行完整分析，確認乾淨**

執行：`cd app && flutter analyze`
預期："No issues found!"

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/layout_preset.dart app/test/reader/layout_preset_test.dart
git commit -m "feat(epic-28): Issue 3 Task 3——LayoutPreset 模型與 validateLayoutPresetName() 命名驗證"
```

---

### Task 4：SQLite Migration——`layout_preset` 表，`version` 19→20

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Produces: `layout_preset` 表（`id INTEGER PK AUTOINCREMENT`／`name TEXT NOT NULL`／`created_at INTEGER NOT NULL`／`updated_at INTEGER NOT NULL`／`prefs_json TEXT NOT NULL`）。

**執行前必做**：`grep -n "version:" app/lib/library/sqlite_library_repository.dart` 確認目前 `main` 的實際版本號現值（本計畫寫作當下為 19，若已變動，下列所有「19」「20」需對應調整為「現值」「現值+1」）。

- [ ] **Step 1: 寫失敗測試——全新安裝與既有版本升級**

編輯 `app/test/library/sqlite_library_repository_test.dart`：

於 `test('全新安裝的 book_reader_prefs 表包含 letter_spacing 欄位（version 19 起 onCreate 已含括）', ...)`（約第 1794-1805 行）之後新增：

```dart
  test('全新安裝的 layout_preset 表可用（version 20 起 onCreate 已含括）', () async {
    await repository.database.insert('layout_preset', {
      'name': '測試預設集',
      'created_at': 1000,
      'updated_at': 1000,
      'prefs_json': '{}',
    });
    final rows = await repository.database.query('layout_preset');
    expect(rows, hasLength(1));
    expect(rows.single['name'], '測試預設集');
  });
```

於 `test('既有 version 18 裝置升級到 version 19，book_reader_prefs 新增 letter_spacing 欄位，既有 margin_top 值不受影響', ...)`（約第 2044-2167 行）之後新增：

```dart
  test('既有 version 19 裝置升級到 version 20，新增 layout_preset 表，可正常寫入讀取',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v19_to_v20_layout_preset_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 這個遷移只新增一張與 book_reader_prefs 完全無關的獨立表，故「舊
    // 版本」schema 只需要 groups/books 兩張表即可重現（比照
    // _migrateFontFamilyValues 既有註解「本測試檔內多個既有測試為了只
    // 聚焦驗證單一遷移，刻意省略建立 book_reader_prefs 表」的既有簡化
    // 慣例）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 19,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              is_fixed_layout INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL,
              content_fingerprint TEXT,
              position_updated_at INTEGER,
              position_synced_server_updated_at TEXT
            )
          ''');
        },
      ),
    );
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=19 →
    // newVersion=20）。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    await upgraded.database.insert('layout_preset', {
      'name': '測試預設集',
      'created_at': 1000,
      'updated_at': 1000,
      'prefs_json': '{}',
    });
    final rows = await upgraded.database.query('layout_preset');
    expect(rows, hasLength(1));
    expect(rows.single['name'], '測試預設集');
  });
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/library/sqlite_library_repository_test.dart`
預期：兩則新測試皆失敗（`no such table: layout_preset`）。

- [ ] **Step 3: 新增 `_createLayoutPresetTable()`，`version` 提升為 20，`onCreate`/`onUpgrade` 接線**

編輯 `app/lib/library/sqlite_library_repository.dart`：

第 42 行 `version: 19,` 改為：

```dart
      version: 20,
```

`onCreate`（第 98-105 行）的 `await _createSyncPendingRecordsTable(db);` 之後新增：

```dart
        await _createLayoutPresetTable(db);
```

`onUpgrade` 的 `if (oldVersion < 18) { ... }` 區塊（第 281-290 行）之後、`},`（第 291 行，`onUpgrade` 結尾）之前新增：

```dart
        if (oldVersion < 20) {
          // epic-28-reader-settings-enhancements Issue 3：版面設定預設集
          // 新增的全新獨立資料表（非既有表新增欄位）。與 bookmarks
          // （oldVersion < 8）／custom_fonts（oldVersion < 16）比照同一
          // 原則——任何 oldVersion < 20 的裝置都必然還沒有這張表，直接
          // 無條件建立即可，不需要放在 book_reader_prefs 表是否已存在的
          // if/else 分支內。
          await _createLayoutPresetTable(db);
        }
```

於 `_addLetterSpacingColumn()`（第 573-583 行）之後新增：

```dart

  static Future<void> _createLayoutPresetTable(Database db) async {
    // 版面設定預設集（epic-28-reader-settings-enhancements Issue 3），見
    // spec.md「儲存格式」——prefs_json 為過濾後 BookReaderPrefs 的 JSON
    // 序列化結果，非逐欄位對應，理由見 LayoutPresetRepository 類別文件。
    await db.execute('''
      CREATE TABLE layout_preset (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        prefs_json TEXT NOT NULL
      )
    ''');
  }
```

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/library/sqlite_library_repository_test.dart`
預期：全數 PASS。

- [ ] **Step 5: 執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test test/library/`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 6: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-28): Issue 3 Task 4——SQLite migration：新增 layout_preset 表，version 20"
```

---

### Task 5：`LayoutPresetRepository`

**Files:**
- Create: `app/lib/reader/layout_preset_repository.dart`
- Test: `app/test/reader/layout_preset_repository_test.dart`

**Interfaces:**
- Consumes: `layout_preset` 表（Task 4 產出）、`LayoutPreset`／`BookReaderPrefs.toMap()`/`fromMap()`（Task 1/3 產出，已具備 enum 容錯）。
- Produces: `LayoutPresetRepository`（`listAll()`/`insert()`/`replace()`/`delete()`）。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/reader/layout_preset_repository_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/layout_preset.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

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

  test('尚未儲存過任何預設集時，listAll 回傳空清單', () async {
    expect(await repository.listAll(), isEmpty);
  });

  test('insert 後 listAll 可讀回，id 由資料庫自動指派', () async {
    await repository.insert(LayoutPreset(
      id: null,
      name: '臥室夜讀直排',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: const BookReaderPrefs(
        fontSize: 18,
        writingModeOverride: WritingMode.vertical,
      ),
    ));

    final all = await repository.listAll();
    expect(all, hasLength(1));
    expect(all.single.id, isNotNull);
    expect(all.single.name, '臥室夜讀直排');
    expect(all.single.prefs.fontSize, 18);
    expect(all.single.prefs.writingModeOverride, WritingMode.vertical);
  });

  test('insert 三組後，listAll 依 id ASC（插入順序）排序', () async {
    for (final name in ['第一組', '第二組', '第三組']) {
      await repository.insert(LayoutPreset(
        id: null,
        name: name,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: BookReaderPrefs.empty,
      ));
    }

    final all = await repository.listAll();
    expect(all.map((p) => p.name).toList(), ['第一組', '第二組', '第三組']);
  });

  test('replace 後，id／createdAt 不變，updatedAt 更新，name／prefs 覆蓋為新值', () async {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(1000);
    await repository.insert(LayoutPreset(
      id: null,
      name: '舊名稱',
      createdAt: createdAt,
      updatedAt: createdAt,
      prefs: const BookReaderPrefs(fontSize: 16),
    ));
    final original = (await repository.listAll()).single;

    await repository.replace(
      original.id!,
      LayoutPreset(
        id: original.id,
        name: '新名稱',
        createdAt: createdAt,
        updatedAt: createdAt, // 呼叫端傳入的 updatedAt 應被忽略，repository 一律用當下時間。
        prefs: const BookReaderPrefs(fontSize: 20),
      ),
    );

    final updated = (await repository.listAll()).single;
    expect(updated.id, original.id);
    expect(updated.name, '新名稱');
    expect(updated.prefs.fontSize, 20);
    expect(updated.createdAt, original.createdAt);
    expect(updated.updatedAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(original.updatedAt.millisecondsSinceEpoch));
  });

  test('delete 後該筆從 listAll 消失，其餘不受影響', () async {
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

    await repository.delete(toDelete.id!);

    final remaining = await repository.listAll();
    expect(remaining, hasLength(1));
    expect(remaining.single.name, '保留組');
  });

  test('prefs_json 的 JSON 序列化往返正確保留欄位值（含 enum／double／bool）', () async {
    const prefs = BookReaderPrefs(
      fontFamily: 'TaiwanPearl',
      fontSize: 18.5,
      letterSpacing: 0.1,
      writingModeOverride: WritingMode.vertical,
      publisherStyles: false,
    );
    await repository.insert(LayoutPreset(
      id: null,
      name: '完整欄位測試',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: prefs,
    ));

    final restored = (await repository.listAll()).single.prefs;
    expect(restored, prefs);
  });

  test('即使 prefs 含未過濾的 PDF/雙頁欄位，JSON 往返仍不遺失資料（過濾責任在寫入端 reflowableEpubFields()，repository 本身不做過濾）',
      () async {
    const prefs = BookReaderPrefs(
      pdfFitMode: PdfFitMode.fitWidth,
      pdfContrast: 15,
      dualPageMode: DualPageMode.always,
    );
    await repository.insert(LayoutPreset(
      id: null,
      name: 'PDF 測試',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: prefs,
    ));

    final restored = (await repository.listAll()).single.prefs;
    expect(restored.pdfFitMode, PdfFitMode.fitWidth);
    expect(restored.pdfContrast, 15);
    expect(restored.dualPageMode, DualPageMode.always);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/reader/layout_preset_repository_test.dart`
預期：編譯錯誤（`app/lib/reader/layout_preset_repository.dart` 不存在）。

- [ ] **Step 3: 建立 `LayoutPresetRepository`**

建立 `app/lib/reader/layout_preset_repository.dart`：

```dart
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'book_reader_prefs.dart';
import 'layout_preset.dart';

/// `layout_preset` 表的存取層（epic-28-reader-settings-enhancements
/// Issue 3），比照 `BookReaderPrefsRepository` 既有模式，與其共用同一個
/// `Database` 連線（`main.dart` 建構時注入）。
///
/// **`prefs_json` 儲存格式（非逐欄位對應）**：`BookReaderPrefs` 未來每
/// 新增一個欄位，逐欄位設計都需要同步維護「book_reader_prefs」與
/// 「layout_preset」兩張表的 migration，容易遺漏其中一邊；JSON blob
/// 設計下本表結構完全不受 `BookReaderPrefs` 欄位增減影響，只需要
/// `toMap()`/`fromMap()` 序列化邏輯保持正確即可（見 spec.md「儲存
/// 格式」）。代價是無法對個別欄位下 SQL `WHERE` 查詢，但本表的存取模式
/// （列出全部 3 組、依 id 存取單一組）完全不需要這種查詢能力。
///
/// 本類別**不**負責欄位過濾（`reflowableEpubFields()`）——過濾責任在
/// 寫入端（`ReaderScreen`），`insert()`/`replace()` 原樣序列化傳入的
/// `preset.prefs`，見 `BookReaderPrefs.reflowableEpubFields()` 文件。
class LayoutPresetRepository {
  const LayoutPresetRepository(this._db);
  final Database _db;

  /// 依 `id ASC`（插入順序）排序，見 [LayoutPreset] 類別文件「一旦指定
  /// 後...」——不隨 `updatedAt` 重新排序，避免使用者覆蓋某一組後畫面上
  /// 卡片位置無預警互換造成困惑。
  Future<List<LayoutPreset>> listAll() async {
    final rows = await _db.query('layout_preset', orderBy: 'id ASC');
    return rows.map(_fromRow).toList();
  }

  /// [preset.id]／`createdAt`／`updatedAt` 皆被忽略——`id` 由資料庫自動
  /// 指派（`AUTOINCREMENT`），`created_at`/`updated_at` 皆設為呼叫當下的
  /// 時間。
  Future<void> insert(LayoutPreset preset) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert('layout_preset', {
      'name': preset.name,
      'created_at': now,
      'updated_at': now,
      'prefs_json': _encodePrefs(preset.prefs),
    });
  }

  /// 覆蓋既有一組（存滿 3 組時）：[id]／既有 `created_at` 不變，
  /// `updated_at` 更新為呼叫當下的時間。[preset] 自帶的 `id`／
  /// `createdAt`／`updatedAt` 皆被忽略，一律以參數 [id] 與資料庫既有
  /// `created_at`、呼叫當下時間為準，避免呼叫端誤傳不一致的值。[id]
  /// 對應的列不存在時靜默不做任何事。
  Future<void> replace(int id, LayoutPreset preset) async {
    final existing =
        await _db.query('layout_preset', where: 'id = ?', whereArgs: [id]);
    if (existing.isEmpty) return;
    final createdAt = existing.single['created_at'] as int;
    await _db.update(
      'layout_preset',
      {
        'name': preset.name,
        'created_at': createdAt,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'prefs_json': _encodePrefs(preset.prefs),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) async {
    await _db.delete('layout_preset', where: 'id = ?', whereArgs: [id]);
  }

  String _encodePrefs(BookReaderPrefs prefs) {
    final map = prefs.toMap('')..remove('book_id');
    return jsonEncode(map);
  }

  LayoutPreset _fromRow(Map<String, Object?> row) {
    final prefsMap =
        (jsonDecode(row['prefs_json'] as String) as Map).cast<String, Object?>();
    return LayoutPreset(
      id: row['id'] as int,
      name: row['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      prefs: BookReaderPrefs.fromMap(prefsMap),
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/reader/layout_preset_repository_test.dart`
預期：全數 PASS。

- [ ] **Step 5: 執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test test/reader/`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/layout_preset_repository.dart app/test/reader/layout_preset_repository_test.dart
git commit -m "feat(epic-28): Issue 3 Task 5——LayoutPresetRepository"
```

---

### Task 6：`BookReaderPrefsRepository.saveMultiple()` 批次寫入

**Files:**
- Modify: `app/lib/reader/book_reader_prefs_repository.dart`
- Test: `app/test/reader/book_reader_prefs_repository_test.dart`

**Interfaces:**
- Produces: `BookReaderPrefsRepository.saveMultiple(List<String> bookIds, BookReaderPrefs prefs)`（單一 `Database.transaction()` 包裹）。

- [ ] **Step 1: 寫失敗測試**

編輯 `app/test/reader/book_reader_prefs_repository_test.dart`，於檔案結尾（`main()` 最後一個 `test(...)` 之後）新增：

```dart
  test('saveMultiple 批次寫入多本書的版面設定，皆可正確讀回', () async {
    for (final id in ['b2', 'b3']) {
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

    const prefs = BookReaderPrefs(fontSize: 22, lineHeight: 1.5);
    await repository.saveMultiple(['b1', 'b2', 'b3'], prefs);

    expect(await repository.load('b1'), prefs);
    expect(await repository.load('b2'), prefs);
    expect(await repository.load('b3'), prefs);
  });

  test('saveMultiple 覆寫既有偏好設定（同一批 bookId 再次呼叫）', () async {
    await repository.save('b1', const BookReaderPrefs(fontSize: 14));

    await repository.saveMultiple(['b1'], const BookReaderPrefs(fontSize: 30));

    expect((await repository.load('b1')).fontSize, 30);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/reader/book_reader_prefs_repository_test.dart`
預期：編譯錯誤（`saveMultiple` 不存在於 `BookReaderPrefsRepository`）。

- [ ] **Step 3: 新增 `saveMultiple()`**

編輯 `app/lib/reader/book_reader_prefs_repository.dart`，於 `save()` 方法（第 31-37 行）之後新增：

```dart

  /// 批次寫入多本書的版面設定，以單一 `Database.transaction()` 包裹
  /// （epic-28-reader-settings-enhancements Issue 3「批次寫入效能」），
  /// 避免套用預設集/書籍複製到多本其他書籍時，多次獨立 SQLite 交易造成
  /// UI 卡頓。單一書籍（套用到目前書籍）請直接呼叫既有 [save]。
  Future<void> saveMultiple(List<String> bookIds, BookReaderPrefs prefs) async {
    await _db.transaction((txn) async {
      for (final bookId in bookIds) {
        await txn.insert('book_reader_prefs', prefs.toMap(bookId),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
```

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/reader/book_reader_prefs_repository_test.dart`
預期：全數 PASS。

- [ ] **Step 5: 執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test test/reader/`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/book_reader_prefs_repository.dart app/test/reader/book_reader_prefs_repository_test.dart
git commit -m "feat(epic-28): Issue 3 Task 6——BookReaderPrefsRepository.saveMultiple() 批次寫入"
```

---

### Task 7：`LibraryRepository.listReflowableEpubBooks()` 書籍選擇器過濾

**Files:**
- Modify: `app/lib/library/library_repository.dart`
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Modify: `app/test/support/fake_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Produces: `LibraryRepository.listReflowableEpubBooks({String? excludeBookId})`（抽象方法，`SqliteLibraryRepository`／`FakeLibraryRepository` 皆須實作）。

**Global Constraint 提醒**：`LibraryRepository` 是抽象介面，新增抽象方法後，**任何** `implements LibraryRepository` 的類別都會編譯失敗直到補上實作——目前已知只有 `SqliteLibraryRepository`（正式實作）與 `test/support/fake_library_repository.dart` 的 `FakeLibraryRepository`（測試假實作）兩個，本 Task 兩者皆須同步更新，否則全專案幾乎所有使用 `FakeLibraryRepository` 的既有 widget test 都會編譯失敗。

- [ ] **Step 1: 寫失敗測試——`SqliteLibraryRepository` 實作**

編輯 `app/test/library/sqlite_library_repository_test.dart`，於檔案結尾新增：

```dart
  group('listReflowableEpubBooks', () {
    test('只回傳流式（非 FXL）EPUB，依 title ASC 排序，排除 PDF／FXL EPUB／TXT',
        () async {
      await repository.insertBook(Book(
        id: 'flow1',
        title: 'B 流式書',
        format: BookFileFormat.epub,
        filePath: 'content://example/flow1.epub',
        source: BookSource.local,
        isFixedLayout: false,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      await repository.insertBook(Book(
        id: 'flow2',
        title: 'A 流式書',
        format: BookFileFormat.epub,
        filePath: 'content://example/flow2.epub',
        source: BookSource.local,
        isFixedLayout: null, // 尚未判斷過，視為流式（非 FXL）。
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      await repository.insertBook(Book(
        id: 'fxl1',
        title: 'FXL 書',
        format: BookFileFormat.epub,
        filePath: 'content://example/fxl1.epub',
        source: BookSource.local,
        isFixedLayout: true,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      await repository.insertBook(Book(
        id: 'pdf1',
        title: 'PDF 書',
        format: BookFileFormat.pdf,
        filePath: 'content://example/pdf1.pdf',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      await repository.insertBook(Book(
        id: 'txt1',
        title: 'TXT 書',
        format: BookFileFormat.txt,
        filePath: 'content://example/txt1.txt',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      final result = await repository.listReflowableEpubBooks();

      expect(result.map((b) => b.id).toList(), ['flow2', 'flow1']);
    });

    test('excludeBookId 排除來源書本身', () async {
      await repository.insertBook(Book(
        id: 'flow1',
        title: '書A',
        format: BookFileFormat.epub,
        filePath: 'content://example/flow1.epub',
        source: BookSource.local,
        isFixedLayout: false,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      await repository.insertBook(Book(
        id: 'flow2',
        title: '書B',
        format: BookFileFormat.epub,
        filePath: 'content://example/flow2.epub',
        source: BookSource.local,
        isFixedLayout: false,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      final result =
          await repository.listReflowableEpubBooks(excludeBookId: 'flow1');

      expect(result.map((b) => b.id).toList(), ['flow2']);
    });
  });
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/library/sqlite_library_repository_test.dart`
預期：編譯錯誤（`listReflowableEpubBooks` 不存在於 `LibraryRepository`/`SqliteLibraryRepository`）。

- [ ] **Step 3: `LibraryRepository` 新增抽象方法，`SqliteLibraryRepository` 實作**

編輯 `app/lib/library/library_repository.dart`，於 `listBooks({...});`（第 17-20 行）之後新增：

```dart

  /// 只列出流式（非 FXL）EPUB 書籍（epic-28-reader-settings-enhancements
  /// Issue 3「書籍選擇器過濾與效能」），供版面設定預設集／書籍設定複製
  /// 的書籍選擇器使用——PDF/FXL/TXT 欄位語意不共通，排除避免誤選。
  /// [excludeBookId] 用於「複製其他書籍」流程排除來源書本身。依
  /// `title ASC` 排序。
  Future<List<Book>> listReflowableEpubBooks({String? excludeBookId});
```

編輯 `app/lib/library/sqlite_library_repository.dart`，於 `listBooks()` 方法（第 840-851 行）之後新增：

```dart

  @override
  Future<List<Book>> listReflowableEpubBooks({String? excludeBookId}) async {
    final where = StringBuffer(
        "filePath LIKE '%.epub' AND (is_fixed_layout IS NULL OR is_fixed_layout != 1)");
    final whereArgs = <Object?>[];
    if (excludeBookId != null) {
      where.write(' AND id != ?');
      whereArgs.add(excludeBookId);
    }
    final rows = await _db.query(
      'books',
      where: where.toString(),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'title ASC',
    );
    return rows.map(Book.fromMap).toList();
  }
```

- [ ] **Step 4: `FakeLibraryRepository` 補上實作**

編輯 `app/test/support/fake_library_repository.dart`，於 `listBooks()` 方法（第 59-72 行）之後新增：

```dart

  @override
  Future<List<Book>> listReflowableEpubBooks({String? excludeBookId}) async {
    final filtered = _books.where((b) {
      if (excludeBookId != null && b.id == excludeBookId) return false;
      if (!b.filePath.toLowerCase().endsWith('.epub')) return false;
      return b.isFixedLayout != true;
    }).toList();
    filtered.sort((a, b) => a.title.compareTo(b.title));
    return filtered;
  }
```

- [ ] **Step 5: 執行測試確認通過**

執行：`cd app && flutter analyze && flutter test test/library/`
預期：`flutter analyze` "No issues found!"（確認 `FakeLibraryRepository` 補上實作後，全專案不再有「未實作抽象方法」的編譯錯誤）；`flutter test test/library/sqlite_library_repository_test.dart` 全數 PASS。

- [ ] **Step 6: 執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS（尤其確認所有既有使用 `FakeLibraryRepository` 的 widget test——`library_screen_test.dart`／`reader_screen_test.dart` 等——皆能正常編譯執行）。

- [ ] **Step 7: Commit**

```bash
git add app/lib/library/library_repository.dart app/lib/library/sqlite_library_repository.dart app/test/support/fake_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-28): Issue 3 Task 7——LibraryRepository.listReflowableEpubBooks() 書籍選擇器過濾"
```

---

### Task 8：`ReaderSettingsSheet` UI——預設集管理區塊 ＋ 5 個新 callback

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: `LayoutPreset`（Task 3 產出）。
- Produces: `ReaderSettingsSheet` 新增 `bookId`（`String`，required）、`layoutPresets`（`List<LayoutPreset>`，預設 `const []`）建構參數；新增 5 個 required callback：`onSaveAsPreset(BookReaderPrefs currentDraft)`、`onApplyPreset(LayoutPreset preset, {required List<String> targetBookIds})`、`onApplyFromBook(String sourceBookId, {required List<String> targetBookIds})`、`onRequestBookPicker({required bool multiSelect}) → Future<List<String>?>`、`onDeletePreset(int id)`。

- [ ] **Step 1: 寫失敗測試——預設集區塊顯示與 5 個 callback 觸發**

編輯 `app/test/screens/reader_settings_sheet_test.dart`：

於 import 區塊新增：

```dart
import 'package:elinkbook/reader/layout_preset.dart';
```

於檔案結尾的 `_pumpSheet(...)` 定義（第 759-783 行）改為：

```dart
Future<void> _pumpSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  List<CustomFont> customFonts = const [],
  String bookId = 'b1',
  List<LayoutPreset> layoutPresets = const [],
  void Function(BookReaderPrefs)? onSaveAsPreset,
  void Function(LayoutPreset, {required List<String> targetBookIds})? onApplyPreset,
  void Function(String, {required List<String> targetBookIds})? onApplyFromBook,
  Future<List<String>?> Function({required bool multiSelect})? onRequestBookPicker,
  void Function(int)? onDeletePreset,
}) async {
  // 設定較大的 Viewport，以防 ListView 元件超出預設的 800x600 範圍導致 tap 失敗
  // （Issue 14 邊距拆為 4 個獨立滑桿後內容變高，1200 已不足，調高至 1600）
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ReaderSettingsSheet(
        prefs: prefs,
        onChanged: onChanged,
        customFonts: customFonts,
        bookId: bookId,
        layoutPresets: layoutPresets,
        onSaveAsPreset: onSaveAsPreset ?? _noopSaveAsPreset,
        onApplyPreset: onApplyPreset ?? _noopApplyPreset,
        onApplyFromBook: onApplyFromBook ?? _noopApplyFromBook,
        onRequestBookPicker: onRequestBookPicker ?? _noopRequestBookPicker,
        onDeletePreset: onDeletePreset ?? _noopDeletePreset,
      ),
    ),
  ));
}

void _noopSaveAsPreset(BookReaderPrefs _) {}
void _noopApplyPreset(LayoutPreset _, {required List<String> targetBookIds}) {}
void _noopApplyFromBook(String _, {required List<String> targetBookIds}) {}
Future<List<String>?> _noopRequestBookPicker({required bool multiSelect}) async =>
    null;
void _noopDeletePreset(int _) {}
```

於 `_TestSettingsSheetWrapperState.build()`（第 814-820 行）與 `_pumpModalSheet(...)` 內的 `ReaderSettingsSheet(...)`（第 836-839 行）兩處，各自補上同樣的必要參數（皆用 no-op 預設值即可）：

```dart
    return ReaderSettingsSheet(
      prefs: _prefs,
      onChanged: (_) {},
      bookId: 'b1',
      onSaveAsPreset: _noopSaveAsPreset,
      onApplyPreset: _noopApplyPreset,
      onApplyFromBook: _noopApplyFromBook,
      onRequestBookPicker: _noopRequestBookPicker,
      onDeletePreset: _noopDeletePreset,
    );
```

```dart
            builder: (_) => ReaderSettingsSheet(
              prefs: prefs,
              onChanged: onChanged,
              bookId: 'b1',
              onSaveAsPreset: _noopSaveAsPreset,
              onApplyPreset: _noopApplyPreset,
              onApplyFromBook: _noopApplyFromBook,
              onRequestBookPicker: _noopRequestBookPicker,
              onDeletePreset: _noopDeletePreset,
            ),
```

於檔案結尾（`_noopOnChanged` 定義之後）新增以下測試：

```dart
  testWidgets('空 slot 顯示「（空）」，已存的 slot 顯示名稱與更新日期', (tester) async {
    final preset = LayoutPreset(
      id: 1,
      name: '臥室夜讀直排',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 8, 14),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        layoutPresets: [preset]);

    expect(find.byKey(const Key('reader_settings_preset_slot_0_label')),
        findsOneWidget);
    expect(
        find.textContaining('臥室夜讀直排'), findsOneWidget);
    expect(find.byKey(const Key('reader_settings_preset_slot_1_empty')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_preset_slot_2_empty')),
        findsOneWidget);
  });

  testWidgets('點擊「另存為新預設集」呼叫 onSaveAsPreset 並帶入目前完整草稿', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(fontSize: 18 / 16, lineHeight: 1.6),
      _noopOnChanged,
      onSaveAsPreset: (draft) => notified = draft,
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_save_as_preset')));
    await tester.tap(find.byKey(const Key('reader_settings_save_as_preset')));
    await tester.pump();

    expect(notified, isNotNull);
    expect(notified!.lineHeight, 1.6);
  });

  testWidgets('點擊 slot 的「套用到本書」呼叫 onApplyPreset 且 targetBookIds=[bookId]',
      (tester) async {
    LayoutPreset? appliedPreset;
    List<String>? appliedTargets;
    final preset = LayoutPreset(
      id: 1,
      name: '預設集A',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      bookId: 'current_book',
      layoutPresets: [preset],
      onApplyPreset: (p, {required targetBookIds}) {
        appliedPreset = p;
        appliedTargets = targetBookIds;
      },
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_current')));
    await tester
        .tap(find.byKey(const Key('reader_settings_preset_slot_0_apply_current')));
    await tester.pump();

    expect(appliedPreset, preset);
    expect(appliedTargets, ['current_book']);
  });

  testWidgets(
      '點擊 slot 的「套用到其他書籍」，onRequestBookPicker 回傳清單後呼叫 onApplyPreset 帶入該清單',
      (tester) async {
    List<String>? appliedTargets;
    final preset = LayoutPreset(
      id: 1,
      name: '預設集A',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      layoutPresets: [preset],
      onRequestBookPicker: ({required multiSelect}) async => ['b2', 'b3'],
      onApplyPreset: (p, {required targetBookIds}) => appliedTargets = targetBookIds,
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_others')));
    await tester
        .tap(find.byKey(const Key('reader_settings_preset_slot_0_apply_others')));
    await tester.pumpAndSettle();

    expect(appliedTargets, ['b2', 'b3']);
  });

  testWidgets('onRequestBookPicker 回傳 null（使用者取消）時，不呼叫 onApplyPreset',
      (tester) async {
    var applyCalled = false;
    final preset = LayoutPreset(
      id: 1,
      name: '預設集A',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      layoutPresets: [preset],
      onRequestBookPicker: ({required multiSelect}) async => null,
      onApplyPreset: (p, {required targetBookIds}) => applyCalled = true,
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_others')));
    await tester
        .tap(find.byKey(const Key('reader_settings_preset_slot_0_apply_others')));
    await tester.pumpAndSettle();

    expect(applyCalled, isFalse);
  });

  testWidgets('點擊 slot 的「刪除」呼叫 onDeletePreset 帶入該 preset 的 id', (tester) async {
    int? deletedId;
    final preset = LayoutPreset(
      id: 42,
      name: '預設集A',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      layoutPresets: [preset],
      onDeletePreset: (id) => deletedId = id,
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_delete')));
    await tester.tap(find.byKey(const Key('reader_settings_preset_slot_0_delete')));
    await tester.pump();

    expect(deletedId, 42);
  });

  testWidgets(
      '點擊「複製到本書」，onRequestBookPicker(multiSelect:false) 回傳後呼叫 onApplyFromBook(sourceId, targetBookIds:[bookId])',
      (tester) async {
    String? appliedSource;
    List<String>? appliedTargets;
    bool? capturedMultiSelect;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      bookId: 'current_book',
      onRequestBookPicker: ({required multiSelect}) async {
        capturedMultiSelect = multiSelect;
        return ['source_book'];
      },
      onApplyFromBook: (source, {required targetBookIds}) {
        appliedSource = source;
        appliedTargets = targetBookIds;
      },
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_copy_from_book_current')));
    await tester
        .tap(find.byKey(const Key('reader_settings_copy_from_book_current')));
    await tester.pumpAndSettle();

    expect(capturedMultiSelect, isFalse);
    expect(appliedSource, 'source_book');
    expect(appliedTargets, ['current_book']);
  });

  testWidgets('點擊「複製到其他書籍」，依序呼叫兩次 onRequestBookPicker 後呼叫 onApplyFromBook',
      (tester) async {
    final requestedMultiSelectFlags = <bool>[];
    String? appliedSource;
    List<String>? appliedTargets;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      onRequestBookPicker: ({required multiSelect}) async {
        requestedMultiSelectFlags.add(multiSelect);
        return multiSelect ? ['b2', 'b3'] : ['source_book'];
      },
      onApplyFromBook: (source, {required targetBookIds}) {
        appliedSource = source;
        appliedTargets = targetBookIds;
      },
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_copy_from_book_others')));
    await tester
        .tap(find.byKey(const Key('reader_settings_copy_from_book_others')));
    await tester.pumpAndSettle();

    expect(requestedMultiSelectFlags, [false, true]);
    expect(appliedSource, 'source_book');
    expect(appliedTargets, ['b2', 'b3']);
  });

  testWidgets(
      'Sheet 開啟中，layoutPresets 外部更新後畫面立即反映新清單（Bottom Sheet 開啟中同步）',
      (tester) async {
    final onWrapperCreatedCalls = <void Function(BookReaderPrefs)>[];
    // 沿用既有 _TestSettingsSheetWrapper 只涵蓋 prefs 更新，這裡改用直接
    // 重新 pump 不同 layoutPresets 驗證同一顆 State 樹是否正確反映——
    // ReaderSettingsSheet 對 layoutPresets 是直接在 build() 內消費
    // widget.layoutPresets（無內部草稿複本），故不需要額外 didUpdateWidget
    // 邏輯，重新 pumpWidget 同一個 widget tree 即可驗證。
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    expect(find.byKey(const Key('reader_settings_preset_slot_0_empty')),
        findsOneWidget);

    final preset = LayoutPreset(
      id: 1,
      name: '新存的預設集',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        layoutPresets: [preset]);

    expect(find.byKey(const Key('reader_settings_preset_slot_0_label')),
        findsOneWidget);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart`
預期：編譯錯誤（`bookId`/`layoutPresets`/5 個新 callback 皆不存在於 `ReaderSettingsSheet`）。

- [ ] **Step 3: `ReaderSettingsSheet` 新增建構參數與預設集管理 UI**

編輯 `app/lib/screens/reader_settings_sheet.dart`：

於 import 區塊新增：

```dart
import '../reader/layout_preset.dart';
```

於 `class ReaderSettingsSheet` 欄位宣告（第 24-26 行）改為：

```dart
class ReaderSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;
  final List<CustomFont> customFonts;
  final String bookId;
  final List<LayoutPreset> layoutPresets;
  final void Function(BookReaderPrefs currentDraft) onSaveAsPreset;
  final void Function(LayoutPreset preset, {required List<String> targetBookIds})
      onApplyPreset;
  final void Function(String sourceBookId, {required List<String> targetBookIds})
      onApplyFromBook;
  final Future<List<String>?> Function({required bool multiSelect})
      onRequestBookPicker;
  final void Function(int id) onDeletePreset;

  const ReaderSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
    this.customFonts = const [],
    required this.bookId,
    this.layoutPresets = const [],
    required this.onSaveAsPreset,
    required this.onApplyPreset,
    required this.onApplyFromBook,
    required this.onRequestBookPicker,
    required this.onDeletePreset,
  });
```

於 `_notifyChanged()`（第 140-163 行）重構，抽出 `_currentDraft` getter：

```dart
  BookReaderPrefs get _currentDraft => BookReaderPrefs(
        fontFamily: _fontFamily,
        fontSize: _toMultiplier(_fontSize, 16.0),
        fontWeight: _fontWeightMultiplier,
        lineHeight: _lineHeight,
        paragraphSpacing: _toMultiplier(_paragraphSpacing, 10.0),
        letterSpacing: _letterSpacing,
        marginTop: _marginTop,
        marginBottom: _marginBottom,
        marginLeft: _marginLeft,
        marginRight: _marginRight,
        textAlign: _textAlign,
        publisherStyles: _publisherStyles,
        writingModeOverride: _writingModeOverride,
        pageTurnModeOverride: _pageTurnModeOverride,
        screenOrientationOverride: _screenOrientationOverride,
        showHeader: _showHeader,
        showFooter: _showFooter,
        fullscreen: _fullscreen,
        columnMode: _columnMode,
        columnSize: _columnSize,
      );

  void _notifyChanged() {
    widget.onChanged(_currentDraft);
  }
```

於 `build()` 的 `ListView` `children:` 清單（第 193-360 行）結尾、`_buildPageTurnModeOverrideRow()`（第 359 行）之後新增：

```dart
                const SizedBox(height: 12),
                _buildLayoutPresetSection(),
```

於檔案結尾（`_buildScreenOrientationOverrideRow()` 方法之後、`class` 結尾 `}` 之前）新增：

```dart

  /// 版面設定預設集管理區塊（epic-28-reader-settings-enhancements
  /// Issue 3）：3 個 slot 卡片（存在則顯示名稱＋更新日期＋套用/刪除
  /// 按鈕，空則顯示「（空）」）、「另存為新預設集」按鈕、「從其他書籍
  /// 複製」兩顆按鈕。本 widget 只負責觸發對應 callback，實際 I/O、
  /// 「存量是否已滿 3 組」判斷、命名輸入、覆蓋選擇/確認對話框皆由呼叫端
  /// （`ReaderScreen`）完成，見 spec.md「UI 元件責任劃分」。
  Widget _buildLayoutPresetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('版面設定預設集', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...List.generate(3, _buildPresetSlot),
        const SizedBox(height: 8),
        ElevatedButton(
          key: const Key('reader_settings_save_as_preset'),
          onPressed: () => widget.onSaveAsPreset(_currentDraft),
          child: const Text('另存為新預設集'),
        ),
        const SizedBox(height: 16),
        const Text('從其他書籍複製', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('reader_settings_copy_from_book_current'),
                onPressed: _handleCopyFromBookToCurrent,
                child: const Text('複製到本書'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const Key('reader_settings_copy_from_book_others'),
                onPressed: _handleCopyFromBookToOthers,
                child: const Text('複製到其他書籍'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetSlot(int index) {
    if (index >= widget.layoutPresets.length) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('（空）', key: Key('reader_settings_preset_slot_${index}_empty')),
      );
    }
    final preset = widget.layoutPresets[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${preset.name}（${preset.updatedAt.year}/${preset.updatedAt.month}/${preset.updatedAt.day}）',
              key: Key('reader_settings_preset_slot_${index}_label'),
            ),
          ),
          IconButton(
            key: Key('reader_settings_preset_slot_${index}_apply_current'),
            icon: const Icon(Icons.check),
            tooltip: '套用到本書',
            onPressed: () =>
                widget.onApplyPreset(preset, targetBookIds: [widget.bookId]),
          ),
          IconButton(
            key: Key('reader_settings_preset_slot_${index}_apply_others'),
            icon: const Icon(Icons.library_books),
            tooltip: '套用到其他書籍',
            onPressed: () => _handleApplyPresetToOthers(preset),
          ),
          IconButton(
            key: Key('reader_settings_preset_slot_${index}_delete'),
            icon: const Icon(Icons.delete),
            tooltip: '刪除',
            onPressed: () => widget.onDeletePreset(preset.id!),
          ),
        ],
      ),
    );
  }

  Future<void> _handleApplyPresetToOthers(LayoutPreset preset) async {
    final targets = await widget.onRequestBookPicker(multiSelect: true);
    if (targets == null || targets.isEmpty) return;
    widget.onApplyPreset(preset, targetBookIds: targets);
  }

  Future<void> _handleCopyFromBookToCurrent() async {
    final sources = await widget.onRequestBookPicker(multiSelect: false);
    if (sources == null || sources.isEmpty) return;
    widget.onApplyFromBook(sources.first, targetBookIds: [widget.bookId]);
  }

  Future<void> _handleCopyFromBookToOthers() async {
    final sources = await widget.onRequestBookPicker(multiSelect: false);
    if (sources == null || sources.isEmpty) return;
    final targets = await widget.onRequestBookPicker(multiSelect: true);
    if (targets == null || targets.isEmpty) return;
    widget.onApplyFromBook(sources.first, targetBookIds: targets);
  }
```

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart`
預期：全數 PASS（含 Step 1 新增測試與全部既有測試——既有測試皆透過更新後的 `_pumpSheet`/`_pumpModalSheet`/`_TestSettingsSheetWrapper` 建構，5 個新 callback 皆有 no-op 預設值，零回歸）。

- [ ] **Step 5: 執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test test/screens/reader_settings_sheet_test.dart`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-28): Issue 3 Task 8——ReaderSettingsSheet 新增版面設定預設集管理區塊"
```

---

### Task 9：`LayoutPresetBookPickerScreen` 書籍選擇器畫面

**Files:**
- Create: `app/lib/screens/layout_preset_book_picker_screen.dart`
- Test: `app/test/screens/layout_preset_book_picker_screen_test.dart`

**Interfaces:**
- Consumes: `Book`（既有型別）。
- Produces: `LayoutPresetBookPickerScreen`（`books: List<Book>`／`multiSelect: bool`，`Navigator.pop()` 單選時回傳 `[book.id]`、複選時回傳已勾選 id 清單、使用者返回時回傳 `null`）。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/screens/layout_preset_book_picker_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/layout_preset_book_picker_screen.dart';

void main() {
  testWidgets('單選模式：點擊項目立即回傳該書 id 的單一清單', (tester) async {
    List<String>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<List<String>?>(
              MaterialPageRoute(
                builder: (_) => LayoutPresetBookPickerScreen(
                  books: [_book('b1', '書一'), _book('b2', '書二')],
                  multiSelect: false,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_item_b2')));
    await tester.pumpAndSettle();

    expect(result, ['b2']);
  });

  testWidgets('複選模式：勾選兩本書後點擊確定，回傳兩個 id 的清單', (tester) async {
    List<String>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<List<String>?>(
              MaterialPageRoute(
                builder: (_) => LayoutPresetBookPickerScreen(
                  books: [_book('b1', '書一'), _book('b2', '書二'), _book('b3', '書三')],
                  multiSelect: true,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_item_b1')));
    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_item_b3')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_confirm')));
    await tester.pumpAndSettle();

    expect(result, unorderedEquals(['b1', 'b3']));
  });

  testWidgets('複選模式：未勾選任何項目時，確定按鈕停用', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LayoutPresetBookPickerScreen(
        books: [_book('b1', '書一')],
        multiSelect: true,
      ),
    ));

    final button = tester.widget<TextButton>(
        find.byKey(const Key('layout_preset_book_picker_confirm')));
    expect(button.onPressed, isNull);
  });

  testWidgets('書籍清單為空時顯示提示文字', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LayoutPresetBookPickerScreen(books: [], multiSelect: false),
    ));

    expect(find.text('沒有可選擇的流式 EPUB 書籍'), findsOneWidget);
  });
}

Book _book(String id, String title) => Book(
      id: id,
      title: title,
      format: BookFileFormat.epub,
      filePath: 'content://example/$id.epub',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/screens/layout_preset_book_picker_screen_test.dart`
預期：編譯錯誤（`app/lib/screens/layout_preset_book_picker_screen.dart` 不存在）。

- [ ] **Step 3: 建立 `LayoutPresetBookPickerScreen`**

建立 `app/lib/screens/layout_preset_book_picker_screen.dart`：

```dart
import 'package:flutter/material.dart';

import '../library/models/book.dart';

/// 版面設定預設集／書籍設定複製的書籍選擇器（epic-28-reader-settings-
/// enhancements Issue 3「UI 元件責任劃分」`onRequestBookPicker`），純
/// 展示 widget，不做任何 Repository I/O——[books] 由呼叫端
/// （`ReaderScreen`，已透過 `LibraryRepository.listReflowableEpubBooks()`
/// 過濾為僅流式 EPUB）傳入。[multiSelect] 為 `false` 時單選、點擊項目
/// 立即以 `[book.id]` 關閉畫面；為 `true` 時可複選，AppBar「確定」按鈕
/// （至少選取 1 本才啟用）關閉畫面並回傳已選取 id 清單。使用者直接返回
/// （無選取）時回傳 `null`。
class LayoutPresetBookPickerScreen extends StatefulWidget {
  final List<Book> books;
  final bool multiSelect;

  const LayoutPresetBookPickerScreen({
    super.key,
    required this.books,
    required this.multiSelect,
  });

  @override
  State<LayoutPresetBookPickerScreen> createState() =>
      _LayoutPresetBookPickerScreenState();
}

class _LayoutPresetBookPickerScreenState
    extends State<LayoutPresetBookPickerScreen> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.multiSelect ? '選擇書籍（可複選）' : '選擇書籍'),
        actions: widget.multiSelect
            ? [
                TextButton(
                  key: const Key('layout_preset_book_picker_confirm'),
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selected.toList()),
                  child: const Text('確定'),
                ),
              ]
            : null,
      ),
      body: widget.books.isEmpty
          ? const Center(child: Text('沒有可選擇的流式 EPUB 書籍'))
          : ListView.builder(
              itemCount: widget.books.length,
              itemBuilder: (context, index) {
                final book = widget.books[index];
                if (widget.multiSelect) {
                  return CheckboxListTile(
                    key: Key('layout_preset_book_picker_item_${book.id}'),
                    title: Text(book.title),
                    subtitle: book.author == null ? null : Text(book.author!),
                    value: _selected.contains(book.id),
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _selected.add(book.id);
                      } else {
                        _selected.remove(book.id);
                      }
                    }),
                  );
                }
                return ListTile(
                  key: Key('layout_preset_book_picker_item_${book.id}'),
                  title: Text(book.title),
                  subtitle: book.author == null ? null : Text(book.author!),
                  onTap: () => Navigator.of(context).pop([book.id]),
                );
              },
            ),
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/screens/layout_preset_book_picker_screen_test.dart`
預期：全數 PASS。

- [ ] **Step 5: 執行完整分析，確認乾淨**

執行：`cd app && flutter analyze`
預期："No issues found!"

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/layout_preset_book_picker_screen.dart app/test/screens/layout_preset_book_picker_screen_test.dart
git commit -m "feat(epic-28): Issue 3 Task 9——LayoutPresetBookPickerScreen 書籍選擇器"
```

---

### Task 10：`reader_screen.dart`——5 個 callback 實作、命名/覆蓋/確認對話框

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: `LayoutPresetRepository`（Task 5）、`BookReaderPrefsRepository.saveMultiple()`（Task 6）、`LibraryRepository.listReflowableEpubBooks()`（Task 7）、`ReaderSettingsSheet` 5 個新 callback（Task 8）、`LayoutPresetBookPickerScreen`（Task 9）。
- Produces: `ReaderScreen` 新增可選建構參數 `layoutPresetRepository`（`LayoutPresetRepository?`）、`bookReaderPrefsRepository`（`BookReaderPrefsRepository?`）——比照 `customFontsRepository` 既有慣例，未提供時預設集功能完全停用（按鈕點擊無效果），既有呼叫端零回歸。

**新增檔案（本 Task 內建立）：**
- Create: `app/lib/screens/layout_preset_name_dialog.dart`（命名輸入 Dialog，比照既有 `note_edit_dialog.dart` 的 controller 生命週期慣例）

- [ ] **Step 1: 建立 `showLayoutPresetNameDialog()`**

建立 `app/lib/screens/layout_preset_name_dialog.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/layout_preset.dart';

/// 版面設定預設集命名輸入 Dialog（epic-28-reader-settings-enhancements
/// Issue 3），比照 `note_edit_dialog.dart` 的既有 controller 生命週期
/// 慣例（`TextEditingController` 綁定在 Dialog 自己的 State，避免退場
/// 動畫尚未跑完就被呼叫端提早 `dispose()`）。回傳通過
/// [validateLayoutPresetName] 驗證、已 trim 的名稱；取消或驗證失敗
/// （trim 後為空字串）回傳 `null`。長度上限 20 字元由 `TextField.maxLength`
/// 原生截斷（spec.md「命名驗證」允許的兩種處理方式之一，`validateLayoutPresetName`
/// 本身也會截斷，雙重保險）。
Future<String?> showLayoutPresetNameDialog(
  BuildContext context, {
  String initialText = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) =>
        _LayoutPresetNameDialog(initialText: initialText),
  );
}

class _LayoutPresetNameDialog extends StatefulWidget {
  final String initialText;
  const _LayoutPresetNameDialog({required this.initialText});

  @override
  State<_LayoutPresetNameDialog> createState() =>
      _LayoutPresetNameDialogState();
}

class _LayoutPresetNameDialogState extends State<_LayoutPresetNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('為預設集命名'),
      content: TextField(
        key: const Key('layout_preset_name_dialog_field'),
        controller: _controller,
        autofocus: true,
        maxLength: 20,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('layout_preset_name_dialog_confirm'),
          onPressed: () {
            final name = validateLayoutPresetName(_controller.text);
            Navigator.of(context).pop(name);
          },
          child: const Text('儲存'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: 寫失敗測試——`ReaderScreen` 5 個 callback 的實際行為**

編輯 `app/test/screens/reader_screen_test.dart`：

於 import 區塊新增：

```dart
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/layout_preset.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
```

於檔案結尾新增（使用真實 in-memory SQLite，比照 `book_reader_prefs_repository_test.dart` 既有模式，因 `LayoutPresetRepository`／`BookReaderPrefsRepository` 皆為與 SQLite 直接耦合的具體類別、非抽象介面，比照既有慣例不另外新建 Fake）：

```dart
  group('版面設定預設集（epic-28-reader-settings-enhancements Issue 3）', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late SqliteLibraryRepository libraryRepository;
    late LayoutPresetRepository layoutPresetRepository;
    late BookReaderPrefsRepository bookReaderPrefsRepository;

    setUp(() async {
      libraryRepository = await SqliteLibraryRepository.open(
        inMemoryDatabasePath,
        singleInstance: false,
      );
      layoutPresetRepository =
          LayoutPresetRepository(libraryRepository.database);
      bookReaderPrefsRepository =
          BookReaderPrefsRepository(libraryRepository.database);
      await libraryRepository.insertBook(Book(
        id: 'b1',
        title: '目前書籍',
        format: BookFileFormat.epub,
        filePath: 'test/fixtures/sample.epub',
        source: BookSource.local,
        isFixedLayout: false,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      await libraryRepository.insertBook(Book(
        id: 'b_other',
        title: '其他流式書',
        format: BookFileFormat.epub,
        filePath: 'content://example/other.epub',
        source: BookSource.local,
        isFixedLayout: false,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
    });

    tearDown(() async {
      await libraryRepository.close();
    });

    // 比照既有「流式 EPUB 開書後，ReaderSettingsSheet 變動的偏好正確傳遞到
    // FoliateEpubReaderView」測試（約 line 351）的既有手法：settings 按鈕
    // 的 onPressed 要到 `onLayoutResolved` 觸發、_autoDetectedWritingMode
    // 非 null 後才可用（純 flutter test 環境沒有真實 WebView，須手動呼叫
    // FoliateEpubReaderView widget 上的 onPageRendered()/onLayoutResolved()
    // 模擬原生端回報）。按鈕 key 用 `reader_foliate_settings_button`（現行
    // FAB 化路徑，非舊版 `reader_layout_settings_button`）。
    Future<void> pumpReaderScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
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
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView =
          tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
      );
      await tester.pump();
    }

    testWidgets('另存為新預設集：命名對話框輸入名稱後，正確寫入 LayoutPresetRepository',
        (tester) async {
      await pumpReaderScreen(tester);

      // 開啟版面設定 Sheet、捲動到「另存為新預設集」按鈕並點擊。
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_save_as_preset')));
      await tester
          .tap(find.byKey(const Key('reader_settings_save_as_preset')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('layout_preset_name_dialog_field')), '測試預設集');
      await tester
          .tap(find.byKey(const Key('layout_preset_name_dialog_confirm')));
      await tester.pumpAndSettle();

      final all = await layoutPresetRepository.listAll();
      expect(all, hasLength(1));
      expect(all.single.name, '測試預設集');
    });

    testWidgets('存滿 3 組後再次另存，跳出覆蓋選單，選擇並確認後正確覆蓋既有一組',
        (tester) async {
      for (final name in ['A', 'B', 'C']) {
        await layoutPresetRepository.insert(LayoutPreset(
          id: null,
          name: name,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          prefs: const BookReaderPrefs(fontSize: 16),
        ));
      }

      await pumpReaderScreen(tester);
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_save_as_preset')));
      await tester
          .tap(find.byKey(const Key('reader_settings_save_as_preset')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('layout_preset_name_dialog_field')), 'D');
      await tester
          .tap(find.byKey(const Key('layout_preset_name_dialog_confirm')));
      await tester.pumpAndSettle();

      // 覆蓋選單：選第一組（名稱 'A'，這是這個乾淨的記憶體內資料庫本測試
      // 第一筆 insert，AUTOINCREMENT id 必為 1）。
      await tester
          .tap(find.byKey(const Key('layout_preset_overwrite_option_1')));
      await tester.pumpAndSettle();
      // 確認覆蓋對話框。
      await tester
          .tap(find.byKey(const Key('layout_preset_overwrite_confirm')));
      await tester.pumpAndSettle();

      final all = await layoutPresetRepository.listAll();
      expect(all, hasLength(3));
      expect(all.map((p) => p.name).toList(), ['D', 'B', 'C']);
    });

    testWidgets('套用預設集到目前書籍：立即寫入且畫面即時反映新值（透過 _handlePrefsChanged）',
        (tester) async {
      await layoutPresetRepository.insert(LayoutPreset(
        id: null,
        name: '測試預設集',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: const BookReaderPrefs(fontSize: 24 / 16),
      ));

      await pumpReaderScreen(tester);
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find
          .byKey(const Key('reader_settings_preset_slot_0_apply_current')));
      await tester.tap(
          find.byKey(const Key('reader_settings_preset_slot_0_apply_current')));
      await tester.pumpAndSettle();

      final saved = await bookReaderPrefsRepository.load('b1');
      expect(saved.fontSize, 24 / 16);

      // Bottom Sheet 開啟中同步（spec.md「套用當下 Sheet 仍開啟」情境，
      // 對應審查意見 Minor 2.7）：套用當下 Sheet 仍在畫面上，_prefs 更新
      // 觸發 ReaderScreen 重建，_openLayoutSettings() 的 builder 以新的
      // _prefs 重新建構 ReaderSettingsSheet，其既有 didUpdateWidget 邏輯
      // （本 Task 未改動，沿用既有機制）同步內部草稿——驗證目前畫面上這顆
      // ReaderSettingsSheet 的 prefs 已是套用後的新值，而非套用前的舊值。
      final sheetAfterApply =
          tester.widget<ReaderSettingsSheet>(find.byType(ReaderSettingsSheet));
      expect(sheetAfterApply.prefs.fontSize, 24 / 16);
    });

    testWidgets('套用預設集到其他書籍（多本）：跳出「即將覆蓋 N 本書」確認對話框，確認後批次寫入',
        (tester) async {
      await layoutPresetRepository.insert(LayoutPreset(
        id: null,
        name: '測試預設集',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: const BookReaderPrefs(fontSize: 24 / 16),
      ));

      await pumpReaderScreen(tester);
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_preset_slot_0_apply_others')));
      await tester.tap(
          find.byKey(const Key('reader_settings_preset_slot_0_apply_others')));
      await tester.pumpAndSettle();

      // 書籍選擇器：勾選「其他流式書」後點確定。
      await tester
          .tap(find.byKey(const Key('layout_preset_book_picker_item_b_other')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('layout_preset_book_picker_confirm')));
      await tester.pumpAndSettle();

      // 「即將覆蓋 N 本書」確認對話框。
      await tester.tap(find.byKey(const Key('layout_preset_apply_confirm')));
      await tester.pumpAndSettle();

      final saved = await bookReaderPrefsRepository.load('b_other');
      expect(saved.fontSize, 24 / 16);
      // 目前書籍（b1）不在目標內，不受影響。
      final currentBookPrefs = await bookReaderPrefsRepository.load('b1');
      expect(currentBookPrefs.fontSize, isNull);
    });

    testWidgets('刪除預設集：正確從 LayoutPresetRepository 移除', (tester) async {
      await layoutPresetRepository.insert(LayoutPreset(
        id: null,
        name: '待刪除',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: BookReaderPrefs.empty,
      ));

      await pumpReaderScreen(tester);
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_preset_slot_0_delete')));
      await tester
          .tap(find.byKey(const Key('reader_settings_preset_slot_0_delete')));
      await tester.pumpAndSettle();

      expect(await layoutPresetRepository.listAll(), isEmpty);
    });

    testWidgets('複製其他書籍設定到本書：正確以 reflowableEpubFields() 過濾後寫入並即時反映',
        (tester) async {
      await bookReaderPrefsRepository.save(
        'b_other',
        const BookReaderPrefs(
          fontSize: 20 / 16,
          pdfContrast: 30, // 應被過濾，不應出現在複製結果中。
        ),
      );

      await pumpReaderScreen(tester);
      await tester
          .tap(find.byKey(const Key('reader_foliate_settings_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_copy_from_book_current')));
      await tester
          .tap(find.byKey(const Key('reader_settings_copy_from_book_current')));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('layout_preset_book_picker_item_b_other')));
      await tester.pumpAndSettle();

      final saved = await bookReaderPrefsRepository.load('b1');
      expect(saved.fontSize, 20 / 16);
      expect(saved.pdfContrast, isNull);
    });
  });
```

- [ ] **Step 3: 執行測試確認失敗**

執行：`cd app && flutter test test/screens/reader_screen_test.dart`
預期：編譯錯誤（`layoutPresetRepository`/`bookReaderPrefsRepository` 不存在於 `ReaderScreen` 建構參數）。

- [ ] **Step 4: `ReaderScreen` 新增建構參數與 5 個 callback 實作**

編輯 `app/lib/screens/reader_screen.dart`：

於 import 區塊新增：

```dart
import '../reader/book_reader_prefs_repository.dart';
import '../reader/layout_preset.dart';
import '../reader/layout_preset_repository.dart';
import 'layout_preset_book_picker_screen.dart';
import 'layout_preset_name_dialog.dart';
```

於 `class ReaderScreen` 的 `customFontsRepository` 欄位（第 130 行）之後新增：

```dart

  /// 版面設定預設集的資料存取層（epic-28-reader-settings-enhancements
  /// Issue 3）。刻意為可選參數——比照 [customFontsRepository] 既有慣例，
  /// 未提供時預設集相關按鈕點擊無效果（callback 內提早 return），行為
  /// 等同本 Issue 之前，零回歸。
  final LayoutPresetRepository? layoutPresetRepository;

  /// 供「書籍設定複製」（讀取來源書籍目前的版面偏好設定）與「套用預設集/
  /// 複製設定到目前書籍以外的其他書籍」（批次寫入）使用，與 [prefsManager]
  /// 底層共用同一個 `BookReaderPrefsRepository` 實例（見 main.dart 建構
  /// 處）。刻意為可選參數，理由同 [layoutPresetRepository]。
  final BookReaderPrefsRepository? bookReaderPrefsRepository;
```

於建構子（第 137-152 行）新增：

```dart
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
```

於 `_ReaderScreenState` 新增欄位（`_customFonts` 欄位，第 230 行，之後）：

```dart
  // 版面設定預設集清單快取（epic-28-reader-settings-enhancements
  // Issue 3），開書時載入一次，比照既有 _customFonts 一次性載入快取模式；
  // 另存/覆蓋/刪除完成後重新載入。
  List<LayoutPreset> _layoutPresets = [];
```

於 `initState()`（第 352-357 行）的 `_loadCustomFonts();` 之後新增：

```dart
    _loadLayoutPresets();
```

於 `_loadCustomFonts()` 方法（第 693-707 行）之後新增：

```dart

  Future<void> _loadLayoutPresets() async {
    final repository = widget.layoutPresetRepository;
    if (repository == null) return;
    final presets = await repository.listAll();
    if (!mounted) return;
    setState(() => _layoutPresets = presets);
  }
```

於 `_openLayoutSettings()`（第 647-659 行）的 `ReaderSettingsSheet(...)` 建構式改為：

```dart
      builder: (_) => ReaderSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
        customFonts: _customFonts,
        bookId: widget.bookId,
        layoutPresets: _layoutPresets,
        onSaveAsPreset: _handleSaveAsPreset,
        onApplyPreset: _handleApplyPreset,
        onApplyFromBook: _handleApplyFromBook,
        onRequestBookPicker: _handleRequestBookPicker,
        onDeletePreset: _handleDeletePreset,
      ),
```

於 `_openFxlSettings()`（第 672-679 行）之後新增全部 5 個 callback 實作與 3 個對話框 helper：

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

  Future<LayoutPreset?> _selectPresetToOverwrite() {
    return showDialog<LayoutPreset>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('選擇要覆蓋的預設集'),
        children: _layoutPresets
            .map((preset) => SimpleDialogOption(
                  key: Key('layout_preset_overwrite_option_${preset.id}'),
                  onPressed: () => Navigator.of(dialogContext).pop(preset),
                  child: Text(
                      '${preset.name}（最後更新：${preset.updatedAt.year}/${preset.updatedAt.month}/${preset.updatedAt.day}）'),
                ))
            .toList(),
      ),
    );
  }

  Future<bool> _confirmOverwrite(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認覆蓋'),
        content: Text('即將覆蓋預設集「$name」，此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('layout_preset_overwrite_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認覆蓋'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<bool> _confirmApplyToOtherBooks(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認套用'),
        content: Text('即將覆蓋 $count 本書的版面設定，此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('layout_preset_apply_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認套用'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

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

  Future<void> _handleDeletePreset(int id) async {
    final repository = widget.layoutPresetRepository;
    if (repository == null) return;
    await repository.delete(id);
    await _loadLayoutPresets();
  }

  /// 書籍選擇器（epic-28-reader-settings-enhancements Issue 3
  /// `onRequestBookPicker`）：以 [LibraryRepository.listReflowableEpubBooks]
  /// 過濾為僅流式 EPUB（排除目前書籍本身），推入
  /// [LayoutPresetBookPickerScreen] 供使用者選取。
  Future<List<String>?> _handleRequestBookPicker({
    required bool multiSelect,
  }) async {
    final repository = widget.libraryRepository;
    if (repository == null) return null;
    final books =
        await repository.listReflowableEpubBooks(excludeBookId: widget.bookId);
    if (!mounted) return null;
    return Navigator.of(context).push<List<String>?>(
      MaterialPageRoute(
        builder: (_) => LayoutPresetBookPickerScreen(
          books: books,
          multiSelect: multiSelect,
        ),
      ),
    );
  }
```

- [ ] **Step 5: 執行測試確認通過**

執行：`cd app && flutter test test/screens/reader_screen_test.dart`
預期：全數 PASS（含 Step 2 新增測試與全部既有測試）。

- [ ] **Step 6: 執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/lib/screens/layout_preset_name_dialog.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-28): Issue 3 Task 10——ReaderScreen 實作 5 個版面設定預設集 callback"
```

---

### Task 11：App 層級貫穿——`main.dart`／`LibraryScreen`

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: `LayoutPresetRepository`（Task 5）、`ReaderScreen.layoutPresetRepository`／`.bookReaderPrefsRepository`（Task 10）。

- [ ] **Step 1: 寫失敗測試——貫穿回歸測試**

編輯 `app/test/screens/library_screen_test.dart`：

於 import 區塊新增：

```dart
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
```

於既有 `testWidgets('LibraryScreen 點開一本書後，ReaderScreen 收到的 customFontsRepository 正確貫穿...', ...)` 測試（約第 2696-2730 行）之後新增：

```dart
  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 layoutPresetRepository／bookReaderPrefsRepository 正確貫穿',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final sqliteRepository = await SqliteLibraryRepository.open(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    addTearDown(() => sqliteRepository.close());
    final layoutPresetRepository =
        LayoutPresetRepository(sqliteRepository.database);
    final bookReaderPrefsRepository =
        BookReaderPrefsRepository(sqliteRepository.database);

    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          layoutPresetRepository: layoutPresetRepository,
          bookReaderPrefsRepository: bookReaderPrefsRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.layoutPresetRepository, same(layoutPresetRepository),
        reason: 'LibraryScreen._openBook() 未把 layoutPresetRepository 貫穿給 '
            'ReaderScreen，版面設定預設集功能將完全無法使用。');
    expect(readerScreen.bookReaderPrefsRepository, same(bookReaderPrefsRepository),
        reason: 'LibraryScreen._openBook() 未把 bookReaderPrefsRepository 貫穿給 '
            'ReaderScreen，書籍設定複製與批次套用功能將完全無法使用。');
  });
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/screens/library_screen_test.dart`
預期：編譯錯誤（`layoutPresetRepository`/`bookReaderPrefsRepository` 不存在於 `LibraryScreen`/`ReaderScreen` 建構參數——`ReaderScreen` 部分已由 Task 10 完成，此處新增的是 `LibraryScreen` 部分）。

- [ ] **Step 3: `LibraryScreen`／`ElinkBookApp`／`main.dart` 貫穿新參數**

編輯 `app/lib/screens/library_screen.dart`：

於 import 區塊新增：

```dart
import '../reader/book_reader_prefs_repository.dart';
import '../reader/layout_preset_repository.dart';
```

於 `class LibraryScreen` 的 `customFontsRepository` 欄位（第 39 行）之後新增：

```dart
  final LayoutPresetRepository? layoutPresetRepository;
  final BookReaderPrefsRepository? bookReaderPrefsRepository;
```

於建構子（第 49-66 行）的 `this.customFontsRepository,` 之後新增：

```dart
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
```

於 `_openBook()`（第 445-463 行）的 `ReaderScreen(...)` 建構式，`customFontsRepository: widget.customFontsRepository,`（第 461 行）之後新增：

```dart
              layoutPresetRepository: widget.layoutPresetRepository,
              bookReaderPrefsRepository: widget.bookReaderPrefsRepository,
```

編輯 `app/lib/main.dart`：

於 import 區塊新增：

```dart
import 'reader/layout_preset_repository.dart';
```

於第 47-52 行 `prefsRepository`／`prefsManager` 建構之後新增：

```dart
  final layoutPresetRepository = LayoutPresetRepository(repository.database);
```

於 `runApp(ElinkBookApp(...))`（第 87-104 行）的 `customFontsRepository: customFontsRepository,`（第 95 行）之後新增：

```dart
      layoutPresetRepository: layoutPresetRepository,
      bookReaderPrefsRepository: prefsRepository,
```

於 `class ElinkBookApp` 的 `customFontsRepository` 欄位（第 116 行）之後新增：

```dart
  final LayoutPresetRepository? layoutPresetRepository;
  final BookReaderPrefsRepository? bookReaderPrefsRepository;
```

於其建構子（第 125-141 行）的 `this.customFontsRepository,` 之後新增：

```dart
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
```

於 `build()` 的 `LibraryScreen(...)` 建構式（第 198-213 行），`customFontsRepository: widget.customFontsRepository,`（第 205 行）之後新增：

```dart
        layoutPresetRepository: widget.layoutPresetRepository,
        bookReaderPrefsRepository: widget.bookReaderPrefsRepository,
```

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/screens/library_screen_test.dart`
預期：全數 PASS。

- [ ] **Step 5: 執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 6: `flutter build apk --debug` 確認可編譯**

執行：`cd app && flutter build apk --debug`
預期：編譯成功——本 Task 是全部 11 個 Task 中唯一觸及 `main.dart` App 進入點的一個，額外用真實 build 驗證比純 `flutter analyze`/`flutter test` 更貼近實際執行環境的組裝正確性。

- [ ] **Step 7: Commit**

```bash
git add app/lib/main.dart app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-28): Issue 3 Task 11——App 層級貫穿 layoutPresetRepository／bookReaderPrefsRepository"
```

---

## 完成後的驗證（對照 `issues.md` Issue 3 驗收標準）

- [ ] `flutter analyze`：全專案 "No issues found!"
- [ ] `flutter test`：全專案通過，零回歸
- [ ] `flutter build apk --debug`：編譯成功
- [ ] （建議，非本計畫強制自動化）於真機或模擬器：開啟一本流式 EPUB，調整版面設定後「另存為新預設集」，確認存滿 3 組後跳出覆蓋選單；套用預設集到目前書籍即時生效；套用到其他書籍時彈出確認對話框且目前畫面不受影響；「從其他書籍複製」流程正確讀取來源書籍設定；PDF/FXL 書籍確認不出現在書籍選擇器清單中。
