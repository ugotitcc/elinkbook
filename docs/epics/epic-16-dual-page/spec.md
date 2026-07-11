# Epic 16 — 橫向雙頁顯示：規格 (Spec)

這是實作 `epic-16-dual-page` 的唯一事實來源。決策的完整討論過程與理由請見 `design.md`。

## 模組 (Modules)

- **`BookReaderPrefs`**（Dart，異動既有 `app/lib/reader/book_reader_prefs.dart`）—— 新增 3 個雙頁專屬 nullable 欄位（見下方「資料模型」），沿用既有「全欄位 nullable、跨格式共用單一表」模式。
- **`DualPageMode`／`DualPageDirection`**（Dart，新增，`app/lib/reader/dual_page_mode.dart`／`dual_page_direction.dart`）—— 列舉型別。
- **`ReaderScreen`**（Dart，異動既有 `app/lib/screens/reader_screen.dart`）—— 
  - **方向偵測**：在 `build()` 中透過 `MediaQuery.of(context).orientation` 或 `OrientationBuilder` 偵測當前是否為橫向（`Orientation.landscape`），並將偵測結果傳入渲染 View 契約或控制 Sheet，用以決定 `auto` 模式下是否啟用雙頁。
  - **設定入口**：打破「固定版面不顯示齒輪按鈕」的現有慣例。當格式為 EPUB 且 `isFixedLayout == true` 時，依然在 `_buildAppBarActions` 顯示齒輪「版面設定」按鈕，點擊時開啟 `FxlSettingsSheet`。
- **`FxlSettingsSheet`**（Dart，新增 widget，`app/lib/screens/fxl_settings_sheet.dart`）—— 新增精簡版 Bottom Sheet，專為 EPUB 固定版面設計。提供「雙頁模式」三態切換選項，並為未來 FR-42（全螢幕顯示開關）留出擴充空間。
- **`PdfSettingsSheet`**（Dart，異動既有 `app/lib/screens/pdf_settings_sheet.dart`）—— 在「顯示」分頁中加入雙頁相關選項：雙頁模式（自動／永遠雙頁／永遠單頁）、封面獨立（開關）、頁面方向（左到右／右到左）。
- **`PdfReaderView`**（Dart，異動既有 `app/lib/reader/pdf_reader_view.dart`）—— 建構子新增 `dualPageMode`、`dualPageCoverAlone`、`dualPageDirection` 參數；`didUpdateWidget` 偵測變動時，統一透過 `setPdfPreferences` Method Channel 送出。
- **`PdfReaderView.kt`**（Android，異動既有）—— 
  - `openBook` 與 `setPdfPreferences` 接收新參數；`renderCurrentPage()` 升級為 **`renderCurrentSpread()`**：
    1. 判斷目前是否應啟用雙頁（若 `dualPageMode == always`，或 `dualPageMode == auto` 且裝置處於橫向，且目前**未處於手動裁切編輯模式下**）。
    2. 若啟用雙頁且 `dualPageCoverAlone == true`：當 `currentPageIndex == 0` 時，渲染單一封面頁（另一側留白）；當 `currentPageIndex > 0` 時，執行奇偶雙頁配對。
    3. 配對規則依 `dualPageDirection` 處理：
       - `ltr`（左到右）：左頁 = `currentPageIndex`，右頁 = `currentPageIndex + 1`
       - `rtl`（右到左）：右頁 = `currentPageIndex`，左頁 = `currentPageIndex + 1`
       - 若 `currentPageIndex + 1` 超出總頁數，另一側以白色背景填充。
    4. 各頁獨立套用自身的裁切矩形（`cropRect`）渲染出點陣圖後，橫向拼接成一張大點陣圖。
    5. 拼接後的大點陣圖統一套用加粗濾鏡（型態學膨脹），並將 `imageView` 設定 `colorFilter`（對比度、亮度）與 `fitMode`（Matrix 縮放）。
  - **翻頁步進變更**：當雙頁模式生效時，`nextPage()` 和 `previousPage()` 步進長度改為 2（若當前顯示第 0 頁封面且 `dualPageCoverAlone == true`，往後翻一頁直接跳到第 1 頁，步進為 1；其餘情境皆為 2）。
  - **頁碼回報**：雙頁生效時，原生 `onPageChanged` 回報當前 spread 中較小（左側）的頁面 index 給 Dart 端，Dart 端依模式推算另一頁。
- **`EpubReaderView`**（Dart，異動既有 `app/lib/reader/epub_reader_view.dart`）—— 建構子新增 `dualPageMode` 參數，`didUpdateWidget` 偵測變動時送出 `setPreferences`。
- **`EpubReaderView.kt`**（Android，異動既有）—— `setPreferences` 接收 `dualPageMode` 參數，若雙頁模式生效，則將 Readium 的 `spread` 偏好設定為 `true`，交由 Readium 內建機制處理雙頁配對與翻頁步進；`applyFxlFitScale()` 對並排後的 container 尺寸重新計算縮放適配比例。

## 資料模型 (Data Model)

### `book_reader_prefs`（SQLite，新增 3 欄位，既有表 ALTER）

```sql
ALTER TABLE book_reader_prefs ADD COLUMN dual_page_mode TEXT;            -- DualPageMode.name，NULL = auto（預設）
ALTER TABLE book_reader_prefs ADD COLUMN dual_page_cover_alone INTEGER;    -- 1=開啟, 0=關閉，NULL = 1（預設）
ALTER TABLE book_reader_prefs ADD COLUMN dual_page_direction TEXT;      -- DualPageDirection.name，NULL = ltr（預設）
```

### `BookReaderPrefs`（Dart model，新增欄位）

```dart
class BookReaderPrefs {
  // ... 既有欄位不變 ...

  final DualPageMode? dualPageMode;
  final bool? dualPageCoverAlone;
  final DualPageDirection? dualPageDirection;

  // copyWith / toMap / fromMap 依既有模式平行擴充。
  // SQLite 沒有布林值，對應關係：dualPageCoverAlone 為 true 轉為 1，false 轉為 0。
}
```

### 新增列舉型別

```dart
// app/lib/reader/dual_page_mode.dart
enum DualPageMode { auto, always, never }

// app/lib/reader/dual_page_direction.dart
enum DualPageDirection { ltr, rtl }
```

## 介面 (Interfaces)

### 原生 Method Channel 契約異動

#### PDF 頻道 (`cc.ugotit.elinkbook/pdf_reader_view_$id`)
- **`openBook`** / **`setPdfPreferences`**：Map 擴充參數：
  - `dualPageMode`：`String?`（`auto`／`always`／`never`）
  - `dualPageCoverAlone`：`bool?`
  - `dualPageDirection`：`String?`（`ltr`／`rtl`）

#### EPUB 頻道 (`cc.ugotit.elinkbook/epub_reader_view_$id`)
- **`openBook`** / **`setPreferences`**：Map 擴充參數：
  - `dualPageMode`：`String?`（`auto`／`always`／`never`）

---

## 測試決策 (Testing Decisions)

### 1. 單元測試 (Unit Tests)
- **列舉與資料模型**：驗證 `DualPageMode` 與 `DualPageDirection` 列舉定義；驗證 `BookReaderPrefs` 新欄位的 serialization/deserialization。
- **資料庫遷移**：驗證 `ALTER TABLE` 成功升級，升級後歷史書籍的新欄位預設皆為 `NULL`，不影響既有 EPUB 書籍之載入。

### 2. Widget 測試 (Widget Tests)
- **`PdfSettingsSheet`**：驗證「顯示」分頁新增的 3 個雙頁控制項：
  - 點擊「雙頁模式」選項會觸發 `onChanged` 傳回對應的 `BookReaderPrefs`。
  - 切換「封面獨立」與「閱讀方向」開關會觸發 `onChanged`。
- **`FxlSettingsSheet`**：驗證固定版面 EPUB 的設定 Sheet 能正常泵起（pump），且點擊「雙頁模式」選項會正確觸發 `onChanged`。
- **`ReaderScreen`**：
  - 驗證裝置轉為橫向時，會將當前螢幕方向狀態正確反映給 Native View。
  - 驗證 EPUB 固定版面（`isFixedLayout == true`）開書後，齒輪按鈕依然在 AppBar 顯示，且點擊能開啟 `FxlSettingsSheet`。

### 3. 整合測試 (Integration Tests，真實裝置)
- **PDF 橫向自動雙頁**：
  - 開啟 PDF，方向鎖定為 `auto`，模擬裝置旋轉至橫向，驗證畫面進入雙頁顯示，且每次點擊翻頁手勢，原生回傳的頁碼步進為 2。
  - 模擬裝置旋轉回直向，驗證畫面自動還原為單頁顯示，翻頁步進恢復為 1。
- **PDF 封面獨立與配對驗證**：
  - `dualPageCoverAlone` 為 `true` 時，第 0 頁（封面）應單頁顯示。往後翻一頁，畫面應顯示第 1 頁與第 2 頁的拼接，且回報 index 為 1。
  - `dualPageCoverAlone` 為 `false` 時，第 0 頁應與第 1 頁拼接並排顯示。
- **PDF 閱讀方向（LTR/RTL）驗證**：
  - `dualPageDirection` 為 `ltr` 時，左側顯示較小頁碼，右側顯示較大頁碼。
  - `dualPageDirection` 為 `rtl` 時，右側顯示較小頁碼，左側顯示較大頁碼。
- **EPUB FXL 雙頁切換**：
  - 橫向狀態下，傳入 `spread = true` 給 Readium，驗證畫面成功並排顯示兩頁，且無翻頁崩潰。
- **裁切與雙頁互動安全**：
  - 雙頁模式下點擊「手動選區」，驗證進入裁切模式時畫面會立刻暫時切回單頁渲染；完成裁切並確認後，畫面回到雙頁模式，且左右兩頁皆正確套用新裁切白邊。

---

## 已知限制

- **拼接 Bitmap 記憶體風險**：在低階 E-Ink 裝置上，雙頁拼接後的 Bitmap 記憶體佔用較高。若系統拋出 `OutOfMemoryError`，將自動回退到單頁渲染以確保閱讀器不崩潰。
- **裁切切換視覺閃爍**：進入手動裁切時會強制從雙頁切換為單頁預覽，這在視覺上會有一次瞬時閃爍，此為設計上的折衷（YAGNI），不進行額外的平滑動畫處理。
