# Epic 4 Issue 1 — 資料層基礎建設：PDF 版面偏好設定儲存 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為 PDF 專業增強（FR-11）新增 6 個版面偏好欄位到既有 `BookReaderPrefs`／`book_reader_prefs` 表，純 Dart、不涉及原生程式碼、不需要真實裝置，作為 Issue 2-7 的共用資料基礎。

**Architecture:** 沿用 `epic-3-fonts-layout` 已建立的「全欄位 nullable、跨格式共用單一表」模式（`docs/epics/epic-4-pdf-enhance/design.md` 決策 #9）：新增 `PdfFitMode`／`PdfCropMode` 列舉與 `PdfCropRect` 資料類別，`BookReaderPrefs` 平行擴充 6 個對應欄位，`book_reader_prefs` 表透過 sqflite 既有的 `version`/`onUpgrade` 機制新增欄位（`version: 2 → 3`）。

**Tech Stack:** Flutter/Dart、`sqflite`（真機）／`sqflite_common_ffi`（測試）、`dart:convert`（`PdfCropRect` JSON 序列化，本專案首次使用，SDK 內建不需新增套件）。

## Global Constraints

- 所有新增的程式碼註解與文件皆須使用正體中文（zh-TW），不得使用簡體中文（見全域 CLAUDE.md）。
- `BookReaderPrefs` 的既有慣例：所有欄位皆為 nullable，`null` 代表未覆寫；`toMap`/`fromMap` 透過 `Map<String, Object?>` 往返，enum 欄位以 `.name`/`.byName` 對應字串，且**不做 `byName` 失敗回退**（與 `GlobalReaderDefaults`/`AppThemePreferences` 的 `shared_preferences` 容錯慣例不同——`BookReaderPrefs` 系列既有的 5 個 enum 欄位皆無 try/catch 回退，本次新增的 2 個 PDF enum 欄位須保持一致，見下方 Task 2 說明）。
- `book_reader_prefs` 表為 `books` 表 1:1 關聯，`ON DELETE CASCADE`；本次改動不得影響既有 EPUB 欄位或既有資料。
- `flutter analyze` 全程必須保持乾淨（"No issues found!"）。
- 不新增任何 pubspec 相依套件——`dart:convert` 是 Dart SDK 內建函式庫。
- 本 issue 完全不需要真實裝置即可驗收（純 Dart + `sqflite_common_ffi` 皆可在 `flutter test` 環境驗證），對應 `docs/epics/epic-4-pdf-enhance/issues.md` Issue 1 驗收標準。

---

## Task 1: PDF 基礎型別——`PdfFitMode`／`PdfCropMode`／`PdfCropRect`

**Files:**
- Create: `app/lib/reader/pdf_fit_mode.dart`
- Create: `app/lib/reader/pdf_crop_mode.dart`
- Create: `app/lib/reader/pdf_crop_rect.dart`
- Test: `app/test/reader/pdf_crop_rect_test.dart`

**Interfaces:**
- Consumes: 無（起始工單，無前置任務）
- Produces: `enum PdfFitMode { pageFit, fitWidth, actualSize }`；`enum PdfCropMode { none, autoDetect, manual }`；`class PdfCropRect { final double left, top, right, bottom; const PdfCropRect({required left, required top, required right, required bottom}); String toJson(); factory PdfCropRect.fromJson(String json); }`（含 `==`/`hashCode`/`toString`）——Task 2（`BookReaderPrefs`）直接依賴這三個型別的建構子與 `.name`/`.toJson`/`.fromJson`。

**說明（為何 `PdfFitMode`／`PdfCropMode` 沒有獨立測試檔）：** 比對既有 `app/lib/reader/page_turn_mode.dart`／`epub_text_align.dart`／`screen_orientation_setting.dart`——這三個同樣是「純值列舉、無額外邏輯」的既有欄位型別，本專案並未為它們建立獨立測試檔（`app/test/reader/` 底下沒有對應的 `*_test.dart`），而是透過 `BookReaderPrefs` 的 round-trip 測試間接涵蓋。本次新增的 `PdfFitMode`／`PdfCropMode` 比照同一慣例，其正確性由 Task 2 的 `BookReaderPrefs` round-trip 測試間接驗證。`PdfCropRect` 因為有 `toJson`/`fromJson` 實際邏輯（既有列舉型別皆無此類邏輯），需要獨立測試檔。

- [ ] **Step 1: 建立 `PdfFitMode` 列舉**

建立 `app/lib/reader/pdf_fit_mode.dart`：

```dart
/// PDF 頁面顯示縮放模式（FR-11）。[pageFit] 整頁完整顯示（預設）；
/// [fitWidth] 頁寬滿版、可視高度不足時可捲動；[actualSize] 真實比例
/// 1:1（1 PDF point = 1 Android 邏輯像素 dp，非物理像素，見
/// docs/epics/epic-4-pdf-enhance/design.md「已知風險」的 DPI 定義）。
enum PdfFitMode { pageFit, fitWidth, actualSize }
```

- [ ] **Step 2: 建立 `PdfCropMode` 列舉**

建立 `app/lib/reader/pdf_crop_mode.dart`：

```dart
/// PDF 頁面裁切模式（FR-11），三選一互斥。[none] 不裁切；[autoDetect]
/// 智慧自動裁切（取樣偵測邊界後全書統一套用同一比例，不逐頁重算）；
/// [manual] 手動選區裁切（全書套用使用者框選的矩形）。見
/// docs/epics/epic-4-pdf-enhance/design.md 決策 #3／#4／#5。
enum PdfCropMode { none, autoDetect, manual }
```

- [ ] **Step 3: 為 `PdfCropRect` 寫失敗測試**

建立 `app/test/reader/pdf_crop_rect_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';

void main() {
  test('建構後四個欄位正確保留', () {
    const rect = PdfCropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
    expect(rect.left, 0.1);
    expect(rect.top, 0.2);
    expect(rect.right, 0.9);
    expect(rect.bottom, 0.8);
  });

  test('四個欄位值完全相同的 PdfCropRect 視為相等', () {
    const a = PdfCropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
    const b = PdfCropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一欄位值不同時視為不相等', () {
    const a = PdfCropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
    const b = PdfCropRect(left: 0.15, top: 0.2, right: 0.9, bottom: 0.8);
    expect(a, isNot(b));
  });

  test('toJson／fromJson round-trip 保留所有欄位', () {
    const rect = PdfCropRect(left: 0.05, top: 0.1, right: 0.95, bottom: 0.9);

    final json = rect.toJson();
    final restored = PdfCropRect.fromJson(json);

    expect(restored, rect);
  });

  test('toJson 產出的字串包含四個座標鍵值', () {
    const rect = PdfCropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
    final json = rect.toJson();
    expect(json, contains('"left":0.1'));
    expect(json, contains('"top":0.2'));
    expect(json, contains('"right":0.9'));
    expect(json, contains('"bottom":0.8'));
  });
}
```

- [ ] **Step 4: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/pdf_crop_rect_test.dart`
Expected: FAIL（`Error: Error when reading 'lib/reader/pdf_crop_rect.dart': No such file or directory` 或等效的「找不到 `pdf_crop_rect.dart`」編譯錯誤）

- [ ] **Step 5: 實作 `PdfCropRect`**

建立 `app/lib/reader/pdf_crop_rect.dart`：

```dart
import 'dart:convert';

/// PDF 裁切矩形，四個座標皆為相對頁面尺寸的比例（0.0-1.0），與實際像素
/// /DPI/解析度無關，避免不同裝置渲染時跑位。見
/// docs/epics/epic-4-pdf-enhance/design.md「已知風險」。
class PdfCropRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const PdfCropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// 序列化為 JSON 字串，供 `book_reader_prefs.pdf_crop_rect`（TEXT 欄位）
  /// 儲存使用。
  String toJson() => jsonEncode({
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
      });

  /// 對應 [toJson] 的還原方法。
  factory PdfCropRect.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return PdfCropRect(
      left: (map['left'] as num).toDouble(),
      top: (map['top'] as num).toDouble(),
      right: (map['right'] as num).toDouble(),
      bottom: (map['bottom'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfCropRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'PdfCropRect(left: $left, top: $top, right: $right, bottom: $bottom)';
}
```

- [ ] **Step 6: 執行測試確認通過**

Run: `cd app && flutter test test/reader/pdf_crop_rect_test.dart`
Expected: PASS（5 個測試全過）

- [ ] **Step 7: Commit**

```bash
git add app/lib/reader/pdf_fit_mode.dart app/lib/reader/pdf_crop_mode.dart app/lib/reader/pdf_crop_rect.dart app/test/reader/pdf_crop_rect_test.dart
git commit -m "feat(epic-4): 新增 PdfFitMode/PdfCropMode/PdfCropRect 基礎型別"
```

---

## Task 2: `BookReaderPrefs` 擴充 6 個 PDF 欄位

**Files:**
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Modify: `app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Consumes: `PdfFitMode`（Task 1）、`PdfCropMode`（Task 1）、`PdfCropRect`（Task 1，含 `.toJson()`/`.fromJson()`）
- Produces: `BookReaderPrefs` 新增 6 個唯讀欄位：`final PdfFitMode? pdfFitMode; final double? pdfContrast; final double? pdfBrightness; final double? pdfBoldStrength; final PdfCropMode? pdfCropMode; final PdfCropRect? pdfCropRect;`，皆為建構子具名可選參數；`toMap(String bookId)` 回傳的 `Map` 新增對應 6 個 key（`pdf_fit_mode`／`pdf_contrast`／`pdf_brightness`／`pdf_bold_strength`／`pdf_crop_mode`／`pdf_crop_rect`）；`BookReaderPrefs.fromMap(Map<String, Object?>)` 對應解析——Task 3（資料庫 schema）與 Task 4（repository round-trip）依賴這組欄位名稱與 map key 完全一致。

- [ ] **Step 1: 為新欄位寫失敗測試**

編輯 `app/test/reader/book_reader_prefs_test.dart`（沿用既有測試檔案，不建立新檔）。

**先在既有 import 區塊中插入以下 3 行新 import**（既有 7 行 import 保留不動、不要刪除或重複貼上；下方完整程式碼區塊是插入後的最終結果，僅供比對參考）：

```dart
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
```

插入後，檔案開頭 import 區塊應為（**這是最終結果，不是要貼上取代的內容**——若已依上方指示插入 3 行，此區塊應已自動符合）：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';
```

**`void main() { ... }` 區塊同理**：下方是插入 4 個新測試（`PDF 欄位值完全相同的 BookReaderPrefs 視為相等`／`PDF 欄位任一不同時視為不相等`／`PDF 欄位的 toMap／fromMap round-trip 保留所有欄位`／`EPUB 讀取時 PDF 欄位恆為 null，反之 PDF 讀取時 EPUB 欄位恆為 null`，插入位置見下方各自在既有測試間的相對順序）**之後的完整檔案內容**，用於比對整份檔案最終應長成什麼樣子——既有 5 個測試（`BookReaderPrefs.empty 所有欄位皆為 null`／`兩個欄位值完全相同的 BookReaderPrefs 視為相等`／`任一欄位值不同時視為不相等`／`toMap／fromMap round-trip 保留所有欄位（含 book_id）`／`toMap／fromMap round-trip 正確處理全部欄位皆為 null`）內容不變，只是新增了 4 個測試穿插其中，不要重複貼上既有測試：

```dart
void main() {
  test('BookReaderPrefs.empty 所有欄位皆為 null', () {
    const prefs = BookReaderPrefs.empty;
    expect(prefs.fontFamily, isNull);
    expect(prefs.fontSize, isNull);
    expect(prefs.fontWeight, isNull);
    expect(prefs.lineHeight, isNull);
    expect(prefs.paragraphSpacing, isNull);
    expect(prefs.pageMargins, isNull);
    expect(prefs.textAlign, isNull);
    expect(prefs.publisherStyles, isNull);
    expect(prefs.writingModeOverride, isNull);
    expect(prefs.pageTurnModeOverride, isNull);
    expect(prefs.screenOrientationOverride, isNull);
    expect(prefs.pdfFitMode, isNull);
    expect(prefs.pdfContrast, isNull);
    expect(prefs.pdfBrightness, isNull);
    expect(prefs.pdfBoldStrength, isNull);
    expect(prefs.pdfCropMode, isNull);
    expect(prefs.pdfCropRect, isNull);
  });

  test('兩個欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(
      fontFamily: AppFont.sourceHanSans,
      fontSize: 18,
      writingModeOverride: WritingMode.vertical,
    );
    const b = BookReaderPrefs(
      fontFamily: AppFont.sourceHanSans,
      fontSize: 18,
      writingModeOverride: WritingMode.vertical,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一欄位值不同時視為不相等', () {
    const a = BookReaderPrefs(fontSize: 18);
    const b = BookReaderPrefs(fontSize: 20);
    expect(a, isNot(b));
  });

  test('PDF 欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(
      pdfFitMode: PdfFitMode.fitWidth,
      pdfContrast: 20,
      pdfBrightness: -10,
      pdfBoldStrength: 0.5,
      pdfCropMode: PdfCropMode.manual,
      pdfCropRect: PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
    );
    const b = BookReaderPrefs(
      pdfFitMode: PdfFitMode.fitWidth,
      pdfContrast: 20,
      pdfBrightness: -10,
      pdfBoldStrength: 0.5,
      pdfCropMode: PdfCropMode.manual,
      pdfCropRect: PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('PDF 欄位任一不同時視為不相等', () {
    const a = BookReaderPrefs(pdfContrast: 20);
    const b = BookReaderPrefs(pdfContrast: 30);
    expect(a, isNot(b));
  });

  test('toMap／fromMap round-trip 保留所有欄位（含 book_id）', () {
    const prefs = BookReaderPrefs(
      fontFamily: AppFont.taiwanPearl,
      fontSize: 18.5,
      fontWeight: 1.75,
      lineHeight: 1.6,
      paragraphSpacing: 12,
      pageMargins: 20,
      textAlign: EpubTextAlign.justify,
      publisherStyles: false,
      writingModeOverride: WritingMode.horizontal,
      pageTurnModeOverride: PageTurnMode.scroll,
      screenOrientationOverride: ScreenOrientationSetting.lock90,
    );

    final map = prefs.toMap('book-1');
    expect(map['book_id'], 'book-1');
    expect(map['font_family'], 'taiwanPearl');
    expect(map['publisher_styles'], 0);
    expect(map['writing_mode_override'], 'horizontal');

    final restored = BookReaderPrefs.fromMap(map);
    expect(restored, prefs);
  });

  test('toMap／fromMap round-trip 正確處理全部欄位皆為 null', () {
    const prefs = BookReaderPrefs.empty;
    final map = prefs.toMap('book-2');
    final restored = BookReaderPrefs.fromMap(map);
    expect(restored, prefs);
  });

  test('PDF 欄位的 toMap／fromMap round-trip 保留所有欄位', () {
    const prefs = BookReaderPrefs(
      pdfFitMode: PdfFitMode.actualSize,
      pdfContrast: 15.5,
      pdfBrightness: -5.5,
      pdfBoldStrength: 0.75,
      pdfCropMode: PdfCropMode.autoDetect,
      pdfCropRect: PdfCropRect(left: 0.02, top: 0.03, right: 0.98, bottom: 0.97),
    );

    final map = prefs.toMap('book-3');
    expect(map['pdf_fit_mode'], 'actualSize');
    expect(map['pdf_contrast'], 15.5);
    expect(map['pdf_brightness'], -5.5);
    expect(map['pdf_bold_strength'], 0.75);
    expect(map['pdf_crop_mode'], 'autoDetect');
    expect(map['pdf_crop_rect'], isA<String>());

    final restored = BookReaderPrefs.fromMap(map);
    expect(restored, prefs);
  });

  test('EPUB 讀取時 PDF 欄位恆為 null，反之 PDF 讀取時 EPUB 欄位恆為 null', () {
    const epubOnly = BookReaderPrefs(fontSize: 18, pdfContrast: null);
    final epubMap = epubOnly.toMap('book-4');
    expect(epubMap['pdf_fit_mode'], isNull);
    expect(epubMap['pdf_contrast'], isNull);
    expect(epubMap['pdf_crop_rect'], isNull);

    const pdfOnly = BookReaderPrefs(pdfContrast: 10, fontSize: null);
    final pdfMap = pdfOnly.toMap('book-5');
    expect(pdfMap['font_family'], isNull);
    expect(pdfMap['font_size'], isNull);
    expect(pdfMap['writing_mode_override'], isNull);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/book_reader_prefs_test.dart`
Expected: FAIL（編譯錯誤：`pdfFitMode`／`pdfContrast` 等具名參數在 `BookReaderPrefs` 建構子不存在；或 `pdf_crop_mode.dart`/`pdf_fit_mode.dart` 找不到——取決於 Task 1 是否已先完成，若依本計劃順序執行 Task 1 已完成，此處失敗訊息應為 `BookReaderPrefs` 建構子缺少對應具名參數）

- [ ] **Step 3: 擴充 `BookReaderPrefs` 實作**

完整重寫 `app/lib/reader/book_reader_prefs.dart`：

```dart
import 'app_font.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
import 'pdf_fit_mode.dart';
import 'screen_orientation_setting.dart';
import 'writing_mode.dart';

/// 單一書籍的版面偏好設定（FR-09／FR-10／FR-11），對應 `book_reader_prefs`
/// 表的一列（見 docs/epics/epic-4-pdf-enhance/spec.md「資料模型」）。所有
/// 欄位皆為 nullable：`null` 代表未覆寫，由呼叫端依各欄位語意決定回退值
/// （書本內建樣式、Readium 預設，或——僅限 [pageTurnModeOverride]／
/// [screenOrientationOverride]——全域預設值，見 `GlobalReaderDefaults`）。
/// `pdf` 前綴的 6 個欄位為 PDF 專屬，皆為單書持久化、無全域預設層（見
/// epic-4 design.md 決策 #2／#8）。
class BookReaderPrefs {
  final AppFont? fontFamily;
  final double? fontSize;
  final double? fontWeight; // Readium 倍率語意（1.0 = normal），非 CSS 300-900 原始值
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? pageMargins; // 單一數值，四邊同步變動，見 ADR 0005
  final EpubTextAlign? textAlign;
  final bool? publisherStyles; // 對應 Readium publisherStyles；true=使用書本內建 CSS
  final WritingMode? writingModeOverride; // null=採用書籍排版（自動偵測）
  final PageTurnMode? pageTurnModeOverride; // null=使用全域預設
  final ScreenOrientationSetting? screenOrientationOverride; // null=使用全域預設

  final PdfFitMode? pdfFitMode; // null=pageFit（預設）
  final double? pdfContrast; // -100..100，null=0（無調整）
  final double? pdfBrightness; // -100..100，null=0（無調整）
  final double? pdfBoldStrength; // 0..1，null=0（無加粗）
  final PdfCropMode? pdfCropMode; // null=none（不裁切）
  final PdfCropRect? pdfCropRect; // pdfCropMode != none 時才有意義

  const BookReaderPrefs({
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
    this.writingModeOverride,
    this.pageTurnModeOverride,
    this.screenOrientationOverride,
    this.pdfFitMode,
    this.pdfContrast,
    this.pdfBrightness,
    this.pdfBoldStrength,
    this.pdfCropMode,
    this.pdfCropRect,
  });

  /// 無任何覆寫，等同資料庫無對應列時的狀態。
  static const empty = BookReaderPrefs();

  Map<String, Object?> toMap(String bookId) {
    return {
      'book_id': bookId,
      'font_family': fontFamily?.name,
      'font_size': fontSize,
      'font_weight': fontWeight,
      'line_height': lineHeight,
      'paragraph_spacing': paragraphSpacing,
      'page_margins': pageMargins,
      'text_align': textAlign?.name,
      'publisher_styles':
          publisherStyles == null ? null : (publisherStyles! ? 1 : 0),
      'writing_mode_override': writingModeOverride?.name,
      'page_turn_mode_override': pageTurnModeOverride?.name,
      'screen_orientation_override': screenOrientationOverride?.name,
      'pdf_fit_mode': pdfFitMode?.name,
      'pdf_contrast': pdfContrast,
      'pdf_brightness': pdfBrightness,
      'pdf_bold_strength': pdfBoldStrength,
      'pdf_crop_mode': pdfCropMode?.name,
      'pdf_crop_rect': pdfCropRect?.toJson(),
    };
  }

  factory BookReaderPrefs.fromMap(Map<String, Object?> map) {
    return BookReaderPrefs(
      fontFamily: map['font_family'] == null
          ? null
          : AppFont.values.byName(map['font_family'] as String),
      // SQLite 對無小數部分的 REAL 欄位可能讀回 int（見
      // Book.fromMap 的 progress 欄位既有處理方式），故用 num? 轉換，
      // 不可直接 `as double?`（會拋出 type cast 例外）。
      fontSize: (map['font_size'] as num?)?.toDouble(),
      fontWeight: (map['font_weight'] as num?)?.toDouble(),
      lineHeight: (map['line_height'] as num?)?.toDouble(),
      paragraphSpacing: (map['paragraph_spacing'] as num?)?.toDouble(),
      pageMargins: (map['page_margins'] as num?)?.toDouble(),
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
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookReaderPrefs &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.lineHeight == lineHeight &&
      other.paragraphSpacing == paragraphSpacing &&
      other.pageMargins == pageMargins &&
      other.textAlign == textAlign &&
      other.publisherStyles == publisherStyles &&
      other.writingModeOverride == writingModeOverride &&
      other.pageTurnModeOverride == pageTurnModeOverride &&
      other.screenOrientationOverride == screenOrientationOverride &&
      other.pdfFitMode == pdfFitMode &&
      other.pdfContrast == pdfContrast &&
      other.pdfBrightness == pdfBrightness &&
      other.pdfBoldStrength == pdfBoldStrength &&
      other.pdfCropMode == pdfCropMode &&
      other.pdfCropRect == pdfCropRect;

  @override
  int get hashCode => Object.hash(
        fontFamily,
        fontSize,
        fontWeight,
        lineHeight,
        paragraphSpacing,
        pageMargins,
        textAlign,
        publisherStyles,
        writingModeOverride,
        pageTurnModeOverride,
        screenOrientationOverride,
        pdfFitMode,
        pdfContrast,
        pdfBrightness,
        pdfBoldStrength,
        pdfCropMode,
        pdfCropRect,
      );
}
```

**注意**：`Object.hash` 支援最多 20 個位置參數（Dart SDK `dart:core` 標準函式庫簽章），既有 11 個欄位加上新增 6 個共 17 個，未超過上限，可直接平鋪傳入、不需要巢狀 `Object.hash`。

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/book_reader_prefs_test.dart`
Expected: PASS（9 個測試全過）

- [ ] **Step 5: Commit**

```bash
git add app/lib/reader/book_reader_prefs.dart app/test/reader/book_reader_prefs_test.dart
git commit -m "feat(epic-4): BookReaderPrefs 新增 6 個 PDF 版面偏好欄位"
```

---

## Task 3: `book_reader_prefs` 資料庫 schema 升級（新舊裝置兩種路徑）

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: 無新增 Dart 型別依賴（純 SQL schema 變更），但欄位名稱須與 Task 2 的 `BookReaderPrefs.toMap`/`fromMap` 完全一致：`pdf_fit_mode`(TEXT)／`pdf_contrast`(REAL)／`pdf_brightness`(REAL)／`pdf_bold_strength`(REAL)／`pdf_crop_mode`(TEXT)／`pdf_crop_rect`(TEXT)
- Produces: `SqliteLibraryRepository.open()` 的 `version` 由 `2` 提升為 `3`；`book_reader_prefs` 表（不論全新安裝或既有 version 2 裝置升級）皆具備上述 6 個新欄位——Task 4（`BookReaderPrefsRepository`）依賴這個 schema 已就緒

**背景（現有機制）：** `app/lib/library/sqlite_library_repository.dart` 目前 `version: 2`，`onCreate` 建立全新資料庫時呼叫 `_createBookReaderPrefsTable(db)`；`onUpgrade` 目前只處理 `oldVersion < 2`（從完全沒有 `book_reader_prefs` 表的 version 1 升級）同樣呼叫 `_createBookReaderPrefsTable(db)`。本次新增欄位需要處理**第三種**情境：裝置已經是 version 2（`book_reader_prefs` 表已存在但沒有 PDF 欄位），需要用 `ALTER TABLE ADD COLUMN`，不能重新呼叫 `_createBookReaderPrefsTable`（表已存在會拋出「table already exists」例外）。

- [ ] **Step 1: 為 fresh-install 路徑寫失敗測試**

編輯 `app/test/library/sqlite_library_repository_test.dart`，在既有 `test('insertBook 後可用 listBooks 取回', ...)` 測試之前（或任何既有測試之間，維持既有測試不動）新增：

```dart
  test('全新安裝的 book_reader_prefs 表包含 PDF 欄位（version 3 起 onCreate 已含括）',
      () async {
    // 直接查詢 sqlite_master 的欄位清單，避免依賴 BookReaderPrefsRepository
    // （schema 是否正確就緒是本測試檔的職責，CRUD 邏輯正確性由
    // book_reader_prefs_repository_test.dart 負責）。
    final columns =
        await repository.database.rawQuery('PRAGMA table_info(book_reader_prefs)');
    final columnNames = columns.map((c) => c['name'] as String).toSet();

    expect(columnNames, containsAll([
      'pdf_fit_mode',
      'pdf_contrast',
      'pdf_brightness',
      'pdf_bold_strength',
      'pdf_crop_mode',
      'pdf_crop_rect',
    ]));
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL（`columnNames` 不包含 `pdf_fit_mode` 等 6 個新欄位名稱，`containsAll` 斷言失敗）

- [ ] **Step 3: 更新 `_createBookReaderPrefsTable`（fresh-install 路徑）與 `version`**

編輯 `app/lib/library/sqlite_library_repository.dart`，找到：

```dart
      version: 2,
```

改為：

```dart
      version: 3,
```

找到 `_createBookReaderPrefsTable` 方法：

```dart
  static Future<void> _createBookReaderPrefsTable(Database db) async {
    // 單書版面偏好設定（epic-3-fonts-layout FR-09/FR-10），與 books 表
    // 1:1 關聯；所有欄位皆為 nullable，null 代表未覆寫，見
    // docs/epics/epic-3-fonts-layout/spec.md「資料模型」。
    await db.execute('''
      CREATE TABLE book_reader_prefs (
        book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
        font_family TEXT,
        font_size REAL,
        font_weight REAL,
        line_height REAL,
        paragraph_spacing REAL,
        page_margins REAL,
        text_align TEXT,
        publisher_styles INTEGER,
        writing_mode_override TEXT,
        page_turn_mode_override TEXT,
        screen_orientation_override TEXT
      )
    ''');
  }
```

改為（新增 6 個 PDF 欄位到同一個 `CREATE TABLE`，讓全新安裝一步到位）：

```dart
  static Future<void> _createBookReaderPrefsTable(Database db) async {
    // 單書版面偏好設定（epic-3-fonts-layout FR-09/FR-10、epic-4-pdf-enhance
    // FR-11），與 books 表 1:1 關聯；所有欄位皆為 nullable，null 代表未
    // 覆寫，見 docs/epics/epic-4-pdf-enhance/spec.md「資料模型」。
    await db.execute('''
      CREATE TABLE book_reader_prefs (
        book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
        font_family TEXT,
        font_size REAL,
        font_weight REAL,
        line_height REAL,
        paragraph_spacing REAL,
        page_margins REAL,
        text_align TEXT,
        publisher_styles INTEGER,
        writing_mode_override TEXT,
        page_turn_mode_override TEXT,
        screen_orientation_override TEXT,
        pdf_fit_mode TEXT,
        pdf_contrast REAL,
        pdf_brightness REAL,
        pdf_bold_strength REAL,
        pdf_crop_mode TEXT,
        pdf_crop_rect TEXT
      )
    ''');
  }
```

- [ ] **Step 4: 執行測試確認 fresh-install 路徑通過**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart`
Expected: PASS（新增的欄位清單測試通過；既有測試皆使用 `inMemoryDatabasePath` 全新建立，走的正是這條 `onCreate` 路徑，因此不需要額外處理 `onUpgrade` 就能通過）

- [ ] **Step 5: 為既有 version 2 裝置的升級路徑寫失敗測試**

在同一個測試檔（`app/test/library/sqlite_library_repository_test.dart`）**頂部**新增所需 import：

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
```

在 `void main()` 內、既有測試群組**之後**新增：

```dart
  test('既有 version 2 裝置升級後，book_reader_prefs 新增 PDF 欄位且既有資料不受影響',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('elinkbook_migration_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 2」的舊資料庫：手動以 version 2 當時的
    // schema（不含 PDF 欄位）建立，不透過 SqliteLibraryRepository.open()
    // （該方法目前的 onCreate 已經是 version 3 的最終 schema，無法用來
    // 重現「舊裝置」情境）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
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
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'font_size': 18.0,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=2 →
    // newVersion=3），驗證既有 EPUB 資料不受影響、且新欄位可用。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row =
        (await upgraded.database.query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
            .single;
    expect(row['font_size'], 18.0); // 既有 EPUB 資料不受影響
    expect(row['pdf_fit_mode'], isNull); // 新欄位存在且預設 NULL

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'pdf_fit_mode': 'fitWidth'},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated =
        (await upgraded.database.query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
            .single;
    expect(updated['pdf_fit_mode'], 'fitWidth');
  });
```

- [ ] **Step 6: 執行測試確認失敗**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL（`onUpgrade` 目前對 `oldVersion == 2` 沒有任何處理，`book_reader_prefs` 表仍是舊 schema，`row['pdf_fit_mode']` 存取不存在的欄位會拋出例外或 `query` 直接因欄位不存在而失敗）

- [ ] **Step 7: 新增 `_addPdfReaderPrefsColumns` 並更新 `onUpgrade`**

編輯 `app/lib/library/sqlite_library_repository.dart`，找到：

```dart
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createBookReaderPrefsTable(db);
        }
      },
```

改為：

```dart
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 舊裝置從未有過 book_reader_prefs 表，_createBookReaderPrefsTable
          // 目前的 CREATE TABLE 已包含全部欄位（含 PDF），一步到位，不需要
          // 額外再跑 _addPdfReaderPrefsColumns（該表根本還不存在，ALTER TABLE
          // 會找不到表而失敗）。
          await _createBookReaderPrefsTable(db);
        } else if (oldVersion < 3) {
          // 裝置已經是 version 2：book_reader_prefs 表已存在但缺少 PDF
          // 欄位，只能用 ALTER TABLE 補上，不能重新 CREATE TABLE（會因
          // 表已存在而拋出例外）。
          await _addPdfReaderPrefsColumns(db);
        }
      },
```

在 `_createBookReaderPrefsTable` 方法**之後**新增：

```dart
  static Future<void> _addPdfReaderPrefsColumns(Database db) async {
    // PDF 專業增強（epic-4-pdf-enhance FR-11）新增的 6 個欄位，補追加到
    // 既有（version 2 起已存在）的 book_reader_prefs 表，見
    // docs/epics/epic-4-pdf-enhance/spec.md「資料模型」。SQLite 的
    // ALTER TABLE ADD COLUMN 一次只能新增一欄，需逐一執行。
    await db
        .execute('ALTER TABLE book_reader_prefs ADD COLUMN pdf_fit_mode TEXT');
    await db
        .execute('ALTER TABLE book_reader_prefs ADD COLUMN pdf_contrast REAL');
    await db.execute(
        'ALTER TABLE book_reader_prefs ADD COLUMN pdf_brightness REAL');
    await db.execute(
        'ALTER TABLE book_reader_prefs ADD COLUMN pdf_bold_strength REAL');
    await db
        .execute('ALTER TABLE book_reader_prefs ADD COLUMN pdf_crop_mode TEXT');
    await db
        .execute('ALTER TABLE book_reader_prefs ADD COLUMN pdf_crop_rect TEXT');
  }
```

- [ ] **Step 8: 執行測試確認全部通過**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart`
Expected: PASS（含既有測試與本次新增的兩個測試全數通過）

- [ ] **Step 9: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-4): book_reader_prefs 資料庫 schema 升級至 version 3，新增 PDF 欄位"
```

---

## Task 4: `BookReaderPrefsRepository` 端到端 round-trip 驗證

**Files:**
- Modify: `app/test/reader/book_reader_prefs_repository_test.dart`

**Interfaces:**
- Consumes: `BookReaderPrefs`（Task 2，含 PDF 欄位）、已升級的 `book_reader_prefs` schema（Task 3）、既有 `BookReaderPrefsRepository`（`app/lib/reader/book_reader_prefs_repository.dart`，**本任務不修改此檔案**——其 `load`/`save` 邏輯本來就是透過 `BookReaderPrefs.toMap`/`fromMap` 泛用運作，新欄位不需要额外程式碼即可支援，本任務純粹是驗證這個既有假設成立）
- Produces: 無新型別，本任務是驗證性質的收尾測試，證明 Task 1-3 三層（型別／模型／schema）組合後，`BookReaderPrefsRepository` 這個既有的高階 API 對 PDF 欄位也能正確運作

- [ ] **Step 1: 為 `BookReaderPrefsRepository` 的 PDF 欄位 round-trip 寫失敗測試**

編輯 `app/test/reader/book_reader_prefs_repository_test.dart`，在檔案開頭 import 區塊新增：

```dart
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
```

在既有 `test('save 寫入後，load 讀回相同的值', ...)` 測試之後新增：

```dart
  test('save 寫入 PDF 欄位後，load 讀回相同的值', () async {
    const prefs = BookReaderPrefs(
      pdfFitMode: PdfFitMode.actualSize,
      pdfContrast: 25,
      pdfBrightness: -15,
      pdfBoldStrength: 0.6,
      pdfCropMode: PdfCropMode.manual,
      pdfCropRect:
          PdfCropRect(left: 0.05, top: 0.1, right: 0.95, bottom: 0.9),
    );

    await repository.save('b1', prefs);

    expect(await repository.load('b1'), prefs);
  });

  test('同一本書同時儲存 EPUB 與 PDF 欄位，round-trip 皆保留（雖然實務上一本書只會用到其一）',
      () async {
    const prefs = BookReaderPrefs(
      fontSize: 18,
      writingModeOverride: WritingMode.vertical,
      pdfFitMode: PdfFitMode.fitWidth,
      pdfCropMode: PdfCropMode.autoDetect,
    );

    await repository.save('b1', prefs);

    final loaded = await repository.load('b1');
    expect(loaded.fontSize, 18);
    expect(loaded.writingModeOverride, WritingMode.vertical);
    expect(loaded.pdfFitMode, PdfFitMode.fitWidth);
    expect(loaded.pdfCropMode, PdfCropMode.autoDetect);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/book_reader_prefs_repository_test.dart`
Expected: FAIL（若 Task 1-3 尚未完成則為編譯錯誤；若依本計劃順序執行到此步，Task 1-3 皆已完成，此測試理論上應直接 PASS——**若確實直接 PASS 屬預期結果**，因為本任務的本質是「驗證既有程式碼不需修改」，見下一步）

- [ ] **Step 3: 確認測試通過，無需修改任何原始碼**

Run: `cd app && flutter test test/reader/book_reader_prefs_repository_test.dart`
Expected: PASS（全部測試通過，包含新增的 2 個測試；`BookReaderPrefsRepository` 本身完全不需要修改，因為它的 `load`/`save` 早已是透過 `BookReaderPrefs.toMap`/`fromMap` 泛用運作——這正是本任務要驗證的事）

- [ ] **Step 4: Commit**

```bash
git add app/test/reader/book_reader_prefs_repository_test.dart
git commit -m "test(epic-4): 驗證 BookReaderPrefsRepository 對 PDF 欄位的 round-trip"
```

---

## Task 5: 最終驗證與收尾

**Files:**
- 無新增/修改檔案（純驗證步驟）

**Interfaces:**
- Consumes: Task 1-4 的全部產出
- Produces: 無（收尾任務）

- [ ] **Step 1: 執行完整測試套件**

Run: `cd app && flutter test`
Expected: PASS（全部測試通過，含既有測試與本 issue 新增的測試，總數應較 Task 開始前增加約 16 個：`pdf_crop_rect_test.dart` 5 個、`book_reader_prefs_test.dart` 新增 4 個、`sqlite_library_repository_test.dart` 新增 2 個、`book_reader_prefs_repository_test.dart` 新增 2 個，實際數字以執行結果為準，不需要精確比對）

- [ ] **Step 2: 執行靜態分析**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 更新 `docs/epics/epic-4-pdf-enhance/issues.md` 的 Issue 1 狀態**

編輯 `docs/epics/epic-4-pdf-enhance/issues.md`，找到：

```markdown
## Issue 1：資料層基礎建設——PDF 版面偏好設定儲存

**Status:** ready-for-agent
```

改為：

```markdown
## Issue 1：資料層基礎建設——PDF 版面偏好設定儲存（已完成）

**Status:** ✅ 已完成。`PdfFitMode`／`PdfCropMode`／`PdfCropRect` 三個基礎型別、`BookReaderPrefs` 6 個新欄位、`book_reader_prefs` 資料庫 schema 升級至 version 3（含既有 version 2 裝置的 `ALTER TABLE` 升級路徑）、`BookReaderPrefsRepository` round-trip 驗證皆已完成。`flutter test`／`flutter analyze` 皆通過。完整計劃見 `plans/plan-issue-1.md`。
```

- [ ] **Step 4: Commit**

```bash
git add docs/epics/epic-4-pdf-enhance/issues.md
git commit -m "docs(epic-4): 標記 Issue 1 已完成"
```
