# Epic 4 — PDF 專業增強：規格 (Spec)

這是實作 `epic-4-pdf-enhance` 的唯一事實來源。決策的完整討論過程與理由請見 `design.md`。

## 模組 (Modules)

- **`BookReaderPrefs`**（Dart，異動既有 `app/lib/reader/book_reader_prefs.dart`）—— 新增 6 個 PDF 專屬 nullable 欄位（見下方「資料模型」），沿用既有「全欄位 nullable、跨格式共用單一表」模式（決策 #9）。EPUB 讀取時新欄位恆為 `null`，PDF 讀取時既有 EPUB 欄位恆為 `null`。
- **`PdfFitMode`／`PdfCropMode`**（Dart，新增，`app/lib/reader/pdf_fit_mode.dart`／`pdf_crop_mode.dart`）—— 列舉型別。
- **`PdfCropRect`**（Dart，新增，`app/lib/reader/pdf_crop_rect.dart`）—— 相對座標（0.0–1.0）矩形的不可變資料類別，DPI/解析度無關。
- **`PdfReaderView`**（Dart，異動既有 `app/lib/reader/pdf_reader_view.dart`）—— 新增 6 個版面/濾鏡輸入參數；`_onPlatformViewCreated` 首次建構時把非 null 參數組成 `initialPreferences` 隨 `openBook` 送出；新增 `didUpdateWidget` 偵測欄位變動、統一透過 `setPdfPreferences` 送出；新增 `onCropRectComputed` callback（智慧自動裁切首次計算出矩形時觸發，供呼叫端持久化）。
- **`PdfReaderView.kt`**（Android，異動既有）—— `openBook` 新增 `initialPreferences: Map<String, Any?>?` 參數；新增 `setPdfPreferences` handler；`renderCurrentPage()` 渲染流程擴充為套用 fit 模式、濾鏡（對比度/亮度用 `ColorMatrixColorFilter`，加粗用型態學膨脹處理原始 Bitmap）、裁切（依 `PdfCropRect` 調整 `PdfRenderer.Page.render()` 的 `Matrix` 平移/縮放，只渲染指定區域並放大填滿）；智慧自動裁切模式下，若尚無快取矩形，首次渲染時取樣計算並透過 `onCropRectComputed` 回傳給 Dart 端持久化，之後全書沿用同一矩形（不逐頁重算，決策 #3）。
- **`ReaderScreen`**（Dart，異動既有 `app/lib/screens/reader_screen.dart`）—— `_buildAppBarActions` 條件從「僅 EPUB」擴充為「EPUB 或 PDF」（PDF 固定版面/雙頁等未來 epic 的排除條件不在本 epic 處理範圍內）；新增 `_openPdfSettings()`，依 `format` 分派開啟 `ReaderSettingsSheet` 或 `PdfSettingsSheet`；管理 PDF 版面偏好的載入/解析/寫回，比照既有 EPUB 偏好處理邏輯。
- **`PdfSettingsSheet`**（Dart，新增 widget，`app/lib/screens/pdf_settings_sheet.dart`）—— Bottom Sheet UI，三分頁（顯示／濾鏡／裁切），無既有原型可參考（見 `design.md`「問題陳述」），版面比照 `ReaderSettingsSheet` 既有分頁樣式延伸。裁切分頁選擇「手動選區」時，透過 `Navigator.push` 開啟 `PdfCropEditorScreen` 並等待回傳矩形。
- **`PdfCropEditorScreen`**（Dart，新增全螢幕畫面，`app/lib/screens/pdf_crop_editor_screen.dart`）—— 顯示當前頁面全圖，疊加可拖拉四角的裁切框；確認後以 `Navigator.pop(PdfCropRect)` 回傳結果，取消則 `pop(null)`。

## 資料模型 (Data Model)

### `book_reader_prefs`（SQLite，新增 6 欄位，既有表 ALTER）

```sql
ALTER TABLE book_reader_prefs ADD COLUMN pdf_fit_mode TEXT;         -- PdfFitMode.name，NULL = pageFit（預設）
ALTER TABLE book_reader_prefs ADD COLUMN pdf_contrast REAL;         -- -100..100，NULL = 0（無調整）
ALTER TABLE book_reader_prefs ADD COLUMN pdf_brightness REAL;       -- -100..100，NULL = 0（無調整）
ALTER TABLE book_reader_prefs ADD COLUMN pdf_bold_strength REAL;    -- 0..1，NULL = 0（無加粗）
ALTER TABLE book_reader_prefs ADD COLUMN pdf_crop_mode TEXT;        -- PdfCropMode.name，NULL = none（不裁切）
ALTER TABLE book_reader_prefs ADD COLUMN pdf_crop_rect TEXT;        -- JSON 編碼的 PdfCropRect，crop_mode != none 時才有意義
```

`pdf_crop_rect` 在 `pdf_crop_mode = autoDetect` 時，儲存的是**首次計算後快取的結果**（決策 #3），不是每次開書都重新偵測；在 `pdf_crop_mode = manual` 時，儲存的是使用者在 `PdfCropEditorScreen` 框選的結果。兩種模式切換時各自保留自己的矩形值互不覆蓋——需求上暫不支援（YAGNI，若未來需要可再擴充成分開的兩個欄位）。

### `BookReaderPrefs`（Dart model，新增欄位）

```dart
class BookReaderPrefs {
  // ...既有 EPUB 欄位不變...

  final PdfFitMode? pdfFitMode;
  final double? pdfContrast;      // -100..100
  final double? pdfBrightness;    // -100..100
  final double? pdfBoldStrength;  // 0..1
  final PdfCropMode? pdfCropMode;
  final PdfCropRect? pdfCropRect;

  // 建構子/toMap/fromMap/==/hashCode 依既有模式平行擴充
}
```

### 新增列舉/資料型別

```dart
// app/lib/reader/pdf_fit_mode.dart
enum PdfFitMode { pageFit, fitWidth, actualSize }

// app/lib/reader/pdf_crop_mode.dart
enum PdfCropMode { none, autoDetect, manual }

// app/lib/reader/pdf_crop_rect.dart
class PdfCropRect {
  final double left;   // 0.0-1.0，相對頁面寬度
  final double top;    // 0.0-1.0，相對頁面高度
  final double right;  // 0.0-1.0
  final double bottom; // 0.0-1.0

  const PdfCropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  String toJson();
  factory PdfCropRect.fromJson(String json);
}
```

## 介面 (Interfaces)

### `PdfReaderView`（新增輸入參數與 callback）

```dart
class PdfReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final VoidCallback? onNextPage;
  final VoidCallback? onPreviousPage;
  final ValueChanged<int>? onPageChanged;

  // 新增：呼叫端已解析好的最終生效值，null 表示使用預設
  final PdfFitMode? fitMode;
  final double? contrast;
  final double? brightness;
  final double? boldStrength;
  final PdfCropMode? cropMode;
  final PdfCropRect? cropRect; // manual 模式下由呼叫端提供；autoDetect 模式下若為 null，原生端會計算後透過 onCropRectComputed 回傳

  final ValueChanged<PdfCropRect>? onCropRectComputed;

  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onNextPage,
    this.onPreviousPage,
    this.onPageChanged,
    this.fitMode,
    this.contrast,
    this.brightness,
    this.boldStrength,
    this.cropMode,
    this.cropRect,
    this.onCropRectComputed,
  });
}
```

- **`_onPlatformViewCreated`**：把非 null 的偏好參數組成 `Map<String, Object?>`，隨 `openBook` 一併送出。
- **`didUpdateWidget`**：任一偏好欄位變動時，組出目前完整非 null 欄位集合，透過單一 `setPdfPreferences` 呼叫送出（合併語意，比照 EPUB `setPreferences` 慣例，見 `docs/archive/2026-07-10-epic-3-fonts-layout/spec.md` 的對應段落）。

### 原生 method channel 契約異動

沿用既有 per-instance channel `cc.ugotit.elinkbook/pdf_reader_view_$id`：

- **`openBook`**：簽章擴充為 `{'path': String, 'initialPreferences': Map<String, Any?>?}`。
- **`setPdfPreferences`**：參數為完整 `Map<String, Any?>`，原生端合併進目前生效設定，重新渲染當前頁。
- **`onCropRectComputed`**（原生 → Dart，新增）：`cropMode = autoDetect` 且尚無快取矩形時，首次渲染完成後觸發，參數為 `Map<String, double>`（`left`/`top`/`right`/`bottom`），呼叫端收到後寫入 `book_reader_prefs.pdf_crop_rect`。
- **map key 對應**：`fitMode`（`PdfFitMode.name` → 原生端 `ImageView.scaleType` 或等效的 Matrix 縮放邏輯）、`contrast`/`brightness`（`Double` → `ColorMatrixColorFilter` 參數）、`boldStrength`（`Double` → 型態學膨脹強度）、`cropMode`（`PdfCropMode.name`）、`cropRect`（`Map<String, Double>`，manual 模式時由 Dart 端提供）。
- `nextPage`／`previousPage`／`onPageChanged` 既有行為不變；渲染管線內部依序套用「裁切 → fit 模式縮放 → 濾鏡」，具體實作順序留待撰寫 `plan-issue-N.md` 時定案。

### `PdfSettingsSheet`（新增 widget）

```dart
class PdfSettingsSheet extends StatelessWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;

  const PdfSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
  });
}
```

三分頁（顯示／濾鏡／裁切），互動模式與既有 `ReaderSettingsSheet` 一致：每次調整即時呼叫 `onChanged`（濾鏡滑桿依決策 #11 於拖動時即時預覽、鬆手後才觸發持久化寫入；`ReaderScreen._handlePdfPrefsChanged` 沿用 EPUB 版本「setState 立即反映、不 await 持久化」的既有慣例）。

### `PdfCropEditorScreen`（新增全螢幕畫面）

```dart
class PdfCropEditorScreen extends StatefulWidget {
  final String filePath;
  final int pageIndex;       // 使用目前頁面作為裁切預覽底圖
  final PdfCropRect? initialRect; // 已有手動裁切結果時，作為起始框選位置

  const PdfCropEditorScreen({
    super.key,
    required this.filePath,
    required this.pageIndex,
    this.initialRect,
  });
}

// 呼叫方式：
// final PdfCropRect? result = await Navigator.push(context, MaterialPageRoute(
//   fullscreenDialog: true,
//   builder: (_) => PdfCropEditorScreen(...),
// ));
```

### `ReaderScreen` 內部行為異動

- `_buildAppBarActions(format)`：條件從 `format != BookFormat.epub` 改為 `format != BookFormat.epub && format != BookFormat.pdf`（`|| _isFixedLayout` 僅套用於 EPUB 分支，PDF 無固定版面概念，不受影響）。
- 齒輪按鈕 `onPressed`：依 `format` 分派 `_openLayoutSettings()`（EPUB，既有）或新增的 `_openPdfSettings()`（PDF）。
- 開書流程：`format == pdf` 時額外載入 `BookReaderPrefs` 中的 6 個 PDF 欄位，解析為 `PdfReaderView` 的最終生效值（皆為單書持久化，無雙層解析，決策 #2/#8）。
- `_handlePdfPrefsChanged(BookReaderPrefs prefs)`：比照既有 `_handlePrefsChanged` 模式，`setState` 更新本地狀態並呼叫 `widget.prefsRepository.save(...)`。
- `onCropRectComputed` 觸發時，同樣寫入 `BookReaderPrefs`（更新 `pdfCropRect` 欄位），避免下次開書重新計算。

## 測試決策 (Testing Decisions)

- **`PdfFitMode`／`PdfCropMode`／`PdfCropRect`**：純 Dart unit test（建構、相等性、`PdfCropRect` 的 JSON round-trip）。
- **`BookReaderPrefs`（PDF 欄位）**：既有 unit test 擴充，驗證新欄位的 `toMap`/`fromMap` round-trip，以及 EPUB/PDF 欄位互不干擾（EPUB 讀取時 PDF 欄位為 null，反之亦然）。
- **`BookReaderPrefsRepository`**：既有測試擴充涵蓋新欄位的 save/load round-trip；資料庫 migration 測試（既有列 ALTER 後新欄位預設為 `NULL`，不影響既有 EPUB 資料）。
- **`PdfReaderView`**：widget test，透過假的 `MethodChannel` handler 驗證：`_onPlatformViewCreated` 呼叫 `openBook` 時 `initialPreferences` 內容正確；欄位變動觸發 `setPdfPreferences`；收到原生端 `onCropRectComputed` 時正確觸發回呼。
- **`PdfSettingsSheet`**：widget test 驗證三分頁切換、各控制項變動時觸發 `onChanged`。
- **`PdfCropEditorScreen`**：widget test 驗證拖拉裁切框後 `Navigator.pop` 回傳正確的 `PdfCropRect`；取消時回傳 `null`。
- **`integration_test/`（真實裝置）**：
  - 驗證帶有已持久化 PDF 偏好設定的書籍開啟後，畫面依設定渲染（Fit 模式/濾鏡/裁切皆生效）。
  - 驗證智慧自動裁切首次開書時計算並持久化矩形，第二次開書不重新計算（比對兩次 `book_reader_prefs` 查詢結果一致）。
  - **獨立驗證項（非自動化測試，人工視覺 QA）**：加粗濾鏡在不同掃描品質的真實 PDF 樣本上的視覺效果是否符合預期（型態學膨脹強度是否合理）；100MB 以上 PDF 在無濾鏡/無裁切時的基礎開啟時間是否 < 2 秒（NFR-1，決策 #13 範圍）。

## 已知限制

- `pdf_crop_rect` 欄位在自動/手動兩種模式間切換時共用同一欄位，不保留「切換前」的另一種模式結果——使用者從智慧自動切到手動再切回自動，會需要重新觸發一次自動偵測計算。此為刻意簡化（YAGNI），如未來需要「記住兩種模式各自的結果」需另外拆欄位。
- 型態學膨脹的具體演算法與強度映射公式未在本次 Discovery 定案，留待撰寫對應 issue 的 `plan-issue-N.md` 時，由實作者依效能實測結果決定。

## 範圍外 (Out of Scope)

- `epic-16-dual-page`（FR-41）——已獨立分流，見 `docs/epics.md`。
- `epic-14-system-settings` 的全域預設層——本 epic 決議 PDF 濾鏡/裁切/Fit 模式皆不需要全域預設，僅單書持久化。
- EPUB／TXT 的濾鏡或裁切邏輯。
- 智慧自動裁切的邊界偵測演算法細節、型態學膨脹的具體實作方式——留待實作 issue 的規劃階段定案。
