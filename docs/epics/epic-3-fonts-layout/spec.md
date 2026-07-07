# Epic 3 — 字型與版面設定：規格 (Spec)

這是實作 `epic-3-fonts-layout` 的唯一事實來源。問題/解法的完整敘述請見 `design.md`；`openBook` 契約擴充與偏好設定合併方式的完整理由請見 `docs/adr/0006-epub-reader-batch-preferences-contract.md`；邊距降規格的理由請見 `docs/adr/0005-epub-page-margins-single-value.md`。

## 模組 (Modules)

- **`BookReaderPrefs`**（Dart，新增，`app/lib/reader/book_reader_prefs.dart`）—— 單書版面偏好設定的不可變資料類別，對應 `book_reader_prefs` 表的一列。
- **`BookReaderPrefsRepository`**（Dart，新增，`app/lib/reader/book_reader_prefs_repository.dart`）—— `book_reader_prefs` 表的 CRUD，比照 `SqliteLibraryRepository` 慣例。
- **`GlobalReaderDefaults`**（Dart，新增，`app/lib/reader/global_reader_defaults.dart`）—— 翻頁模式／螢幕方向全域預設值，`shared_preferences`，比照 `LibraryPreferences` 慣例。
- **`AppThemePreferences`**（Dart，新增，`app/lib/theme/app_theme_preferences.dart`）—— 主題（三選一）與 E-Ink 高對比開關，`shared_preferences`，比照 `LibraryPreferences` 慣例。
- **`AppFont`／`EpubTextAlign`／`ScreenOrientationSetting`**（Dart，新增，`app/lib/reader/app_font.dart`／`epub_text_align.dart`／`screen_orientation_setting.dart`）—— 列舉型別。
- **`EpubReaderView`**（Dart，異動既有 `app/lib/reader/epub_reader_view.dart`）—— 新增 8 個版面偏好輸入參數；`_onPlatformViewCreated` 首次建構時把所有非 null 參數組成 `initialPreferences` 隨 `openBook` 送出；`didUpdateWidget` 改為偵測任何一個偏好欄位變動，統一透過單一 `setPreferences` 呼叫送出變動的欄位。
- **`EpubReaderView.kt`**（Android，異動既有）—— `openBook` 新增 `initialPreferences: Map<String, Any?>?` 參數，`attachNavigator()` 成功後套用；新增 `setPreferences` 處理，取代既有 `setWritingMode`／`setPageTurnMode`（兩者视为 `setPreferences` 的特例，方法本身移除）；`attachNavigator()` 建構 `EpubNavigatorFactory`/`createFragmentFactory` 時，額外組出 `EpubNavigatorFragment.Configuration`，為 5 款內建字型逐一呼叫 `addFontFamilyDeclaration(...)` 登記字型來源（見下方「自訂字型如何讓原生 WebView 實際載入」），此登記只需在 `attachNavigator()` 執行一次，與 `setPreferences`／`openBook` 的偏好設定合併邏輯無關。
- **`ReaderScreen`**（Dart，異動既有 `app/lib/screens/reader_screen.dart`）—— 移除現有 `reader_writing_mode_toggle`／`reader_page_turn_mode_toggle` 兩顆獨立按鈕；新增「⚙️ 版面」按鈕開啟 `ReaderSettingsSheet`；開書時載入 `BookReaderPrefs`＋`GlobalReaderDefaults` 並解析出最終生效值；管理 `_autoDetectedWritingMode`（唯讀）；`dispose()` 時呼叫 `SystemChrome.setPreferredOrientations([])` 還原螢幕方向。
- **`ReaderSettingsSheet`**（Dart，新增 widget，`app/lib/screens/reader_settings_sheet.dart`）—— Bottom Sheet UI，比照 `prototype/index.html` 第 1379-1520 行設計；每次互動即時呼叫 `BookReaderPrefsRepository.save()` 並更新 `EpubReaderView` 建構參數。
- **`ElinkBookApp`**（Dart，異動既有 `app/lib/main.dart`）—— 啟動時載入 `AppThemePreferences`，套用對應 `ThemeData` 到 `MaterialApp`。

`PdfReaderView`、`detectBookFormat()` 不受影響；`_isFixedLayout == true` 時「⚙️ 版面」按鈕與 `ReaderSettingsSheet` 皆不顯示。

## 資料模型 (Data Model)

### `book_reader_prefs`（SQLite，新表，與 `books` 表 1:1）

```sql
CREATE TABLE book_reader_prefs (
  book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
  font_family TEXT,           -- AppFont.name，NULL = 使用書本內建字型
  font_size REAL,             -- Readium fontSize 原始值，NULL = 使用預設
  font_weight REAL,           -- Readium fontWeight 倍率（1.0 = normal），NULL = 使用預設
  line_height REAL,
  paragraph_spacing REAL,
  page_margins REAL,          -- 單一數值，見 ADR 0005
  text_align TEXT,            -- EpubTextAlign.name
  publisher_styles INTEGER,   -- 0/1，對應 Readium publisherStyles（＝停用書本 CSS 的反向邏輯：true=使用書本 CSS）
  writing_mode_override TEXT, -- 'vertical' | 'horizontal'，NULL = 採用書籍排版
  page_turn_mode_override TEXT, -- PageTurnMode.name，NULL = 使用全域預設
  screen_orientation_override TEXT -- ScreenOrientationSetting.name，NULL = 使用全域預設
);
```

`ON DELETE CASCADE`：刪除書籍時一併清除對應偏好設定列，不需要額外的清理邏輯。

無對應書籍列＝所有欄位視為 `NULL`（全部使用預設值），與「有列但個別欄位為 `NULL`」語意一致，不特別區分。

### `BookReaderPrefs`（Dart model）

```dart
class BookReaderPrefs {
  final AppFont? fontFamily;
  final double? fontSize;
  final double? fontWeight; // Readium 倍率語意，UI 顯示時需換算（見下方「字重換算」）
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? pageMargins;
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;
  final WritingMode? writingModeOverride;
  final PageTurnMode? pageTurnModeOverride;
  final ScreenOrientationSetting? screenOrientationOverride;

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
  });

  static const empty = BookReaderPrefs(); // 無任何覆寫，等同資料庫無對應列
}
```

`WritingMode`／`PageTurnMode` 沿用既有型別（`app/lib/reader/writing_mode.dart`／`page_turn_mode.dart`），不重新定義。

### 新增列舉型別

```dart
// app/lib/reader/app_font.dart
enum AppFont {
  sourceHanSans,      // 思源黑體 SourceHanSansTC-VF.ttf
  sourceHanSerif,     // 思源宋體 SourceHanSerifTC-VF.ttf
  guanKiapTsingKhai,  // 原俠正楷 GuanKiapTsingKhai.ttf
  taiwanPearl,        // 台灣圓體 TaiwanPearl-Regular.ttf
  genRyuMinTW,        // 源流明體 GenRyuMinTW-Regular.ttf
}

// app/lib/reader/epub_text_align.dart
// 對應 Readium org.readium.r2.navigator.preferences.TextAlign（反編譯確認的 6 個值）
enum EpubTextAlign { center, justify, start, end, left, right }

// app/lib/reader/screen_orientation_setting.dart
enum ScreenOrientationSetting { auto, lock0, lock90, lock180, lock270 }
```

`AppFont` 到實際字型家族名稱的對應表（`app/lib/reader/app_font.dart` 新增 getter），對應原生端登記的 family 名稱字串（見下方「自訂字型如何讓原生 WebView 實際載入」，**不是**單純的 `pubspec.yaml` `fonts:` 區塊註冊——那個機制只影響 Flutter 自己的 Skia 渲染，與 Readium 內嵌 WebView 的字型載入無關，見下方修正說明）。字型檔案各 1 個 Regular/VF 靜態切面，無 Bold 獨立檔案，見「已知限制」。

### `GlobalReaderDefaults`（shared_preferences，比照 `LibraryPreferences`）

```dart
class GlobalReaderDefaults {
  Future<PageTurnMode> loadPageTurnMode(); // 預設 PageTurnMode.paginated
  Future<void> savePageTurnMode(PageTurnMode mode); // 目前無 UI 可呼叫，供 epic-14 未來使用
  Future<ScreenOrientationSetting> loadScreenOrientation(); // 預設 ScreenOrientationSetting.auto
  Future<void> saveScreenOrientation(ScreenOrientationSetting setting); // 同上
}
```

### `AppThemePreferences`（shared_preferences，比照 `LibraryPreferences`）

```dart
enum AppTheme { light, dark, sepia }

class AppThemePreferences {
  Future<AppTheme> loadTheme(); // 預設 AppTheme.light
  Future<void> saveTheme(AppTheme theme);
  Future<bool> loadEinkMode(); // 預設 false
  Future<void> saveEinkMode(bool enabled);
}
```

`ElinkBookApp` 依 `isEinkMode` 決定實際套用的 `ThemeData`：`isEinkMode == true` 時一律套用固定的高對比黑白 `ThemeData`（不管 `theme` 選了什麼）；`isEinkMode == false` 時依 `theme` 套用對應的 light/dark/sepia `ThemeData`。`theme` 值持續儲存與可修改，僅影響「`isEinkMode == false` 時」的實際呈現。

## 介面 (Interfaces)

### `EpubReaderView`（新增輸入參數）

```dart
class EpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final WritingMode? writingMode;       // 既有：呼叫端已解析好的最終生效值
  final PageTurnMode? pageTurnMode;     // 既有：呼叫端已解析好的最終生效值
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;

  // 新增：以下皆為「呼叫端已解析好的最終生效值」，null 表示不覆寫、使用 Readium 預設
  final AppFont? fontFamily;
  final double? fontSize;
  final double? fontWeight;             // 已換算為 Readium 倍率語意，widget 本身不做換算
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? pageMargins;
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;

  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.writingMode,
    this.pageTurnMode,
    this.onLayoutResolved,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
  });
}
```

- **`_onPlatformViewCreated`**：把當下所有非 null 的偏好參數（`writingMode`／`pageTurnMode`／新增 8 項）組成 `Map<String, Object?>`，隨 `openBook` 呼叫一併送出（key 名稱與下方原生端契約一致）。
- **`didUpdateWidget`**：比較全部 10 個偏好欄位，只要任一欄位與前次不同，就把**所有目前非 null 的欄位**（不只是變動的那個）組成一個 map，透過單一 `setPreferences` 呼叫送出——理由：原生端 `currentPreferences.plus()` 本身就是合併語意，送出完整目前狀態比只送變動欄位更不容易遺漏邊界情況（例如同一個 frame 內兩個欄位同時變動）。

### 原生 method channel 契約異動（ADR 0006）

沿用既有 per-instance channel `cc.ugotit.elinkbook/epub_reader_view_$id`（不新增獨立 channel）：

- **`openBook`**：簽章擴充為 `{'path': String, 'initialPreferences': Map<String, Any?>?}`。原生端 `openBook(path, initialPreferences)`；`attachNavigator()` 成功後，若 `initialPreferences` 非 null 且非空，組出對應 `EpubPreferences`、`plus()` 合併進 `currentPreferences`，呼叫一次 `submitPreferences()`。
- **`setPreferences`**：取代既有 `setWritingMode`／`setPageTurnMode`，參數為完整 `Map<String, Any?>`（key 與 `initialPreferences` 相同格式），原生端組出 `EpubPreferences`、`plus()` 合併進 `currentPreferences`、呼叫 `submitPreferences()`。可在書本開啟後任何時間點呼叫。
- **map key 對應**（Dart key → Readium `EpubPreferences` 欄位）：`writingMode`（`'vertical'|'horizontal'` → `verticalText: Boolean`）、`pageTurnMode`（`'scroll'|'paginated'` → `scroll: Boolean`）、`fontFamily`（`AppFont.name` → 對應的實際字型家族名稱字串（與原生端 `addFontFamilyDeclaration` 登記時使用的名稱完全一致）→ method channel 上仍是 `String`，原生端收到後包成 `FontFamily(name)` 再指派給 `EpubPreferences.fontFamily`）、`fontSize`（`fontSize: Double`）、`fontWeight`（`fontWeight: Double`，已是倍率語意）、`lineHeight`、`paragraphSpacing`、`pageMargins`、`textAlign`（`EpubTextAlign.name` → Readium `TextAlign` enum）、`publisherStyles`（`Boolean`）。
- `openBook`/`onPageRendered`/`onError`/`onLayoutResolved` 既有行為不變（`onLayoutResolved` 觸發時機不受本次擴充影響）。

### `ReaderScreen` 內部行為異動

- 開書流程：`initState`／收到 `onLayoutResolved` 後，非同步載入 `BookReaderPrefsRepository.load(bookId)`＋`GlobalReaderDefaults`，解析：
  - `_writingModeOverride ?? _autoDetectedWritingMode` → 送給 `EpubReaderView.writingMode`
  - `_pageTurnModeOverride ?? globalDefaults.pageTurnMode` → 送給 `EpubReaderView.pageTurnMode`
  - `_screenOrientationOverride ?? globalDefaults.screenOrientation` → 呼叫 `SystemChrome.setPreferredOrientations(...)`
  - 其餘欄位（`fontFamily`/`fontSize`/...）無雙層解析，`BookReaderPrefs` 的值就是最終生效值，直接送給 `EpubReaderView`
- AppBar：移除 `reader_writing_mode_toggle`／`reader_page_turn_mode_toggle`；新增 `Key('reader_layout_settings_button')`，`_isFixedLayout == true` 時不顯示，按下開啟 `ReaderSettingsSheet`（傳入目前 `BookReaderPrefs` 與 callback，選項變動時呼叫 `BookReaderPrefsRepository.save()` 並 `setState` 更新本地狀態）。
- `dispose()`：呼叫 `SystemChrome.setPreferredOrientations([])`，還原系統預設（允許自由旋轉），不論進入時鎖定了哪個角度。
- 對外公開建構參數 `ReaderScreen(filePath: String)` 不變。

## 測試決策 (Testing Decisions)

- **`BookReaderPrefs`／各列舉型別**：純 Dart unit test（建構、相等性、`AppFont`/`EpubTextAlign`/`ScreenOrientationSetting` 的 `byName` 失敗回退預設值）。
- **`BookReaderPrefsRepository`**：比照既有 SQLite repository 測試慣例，驗證無對應列時回傳 `BookReaderPrefs.empty`；`save()`/`load()` round-trip；書籍刪除後（`ON DELETE CASCADE`）確認偏好設定列一併消失。
- **`GlobalReaderDefaults`／`AppThemePreferences`**：比照 `LibraryPreferences` 既有測試慣例（`SharedPreferences.setMockInitialValues` 驅動）。
- **`EpubReaderView`**：widget test，透過假的 `MethodChannel` handler 驗證：`_onPlatformViewCreated` 呼叫 `openBook` 時，`initialPreferences` 包含所有非 null 建構參數且格式正確；任一偏好欄位變動時觸發 `setPreferences` 呼叫，內含所有目前非 null 欄位。
- **`ReaderScreen`**：widget test 驗證 `_isFixedLayout` 為 `true`/`false` 時「⚙️版面」按鈕是否顯示；點擊按鈕開啟 `ReaderSettingsSheet`；`BookReaderPrefs` 載入後正確解析出送給 `EpubReaderView` 的最終值（含雙層解析的兩個欄位）。
- **`integration_test/`（真實裝置）**：
  - 驗證帶有已持久化 `BookReaderPrefs` 的書籍開啟後，畫面依已持久化設定渲染（沿用「等待 loading indicator 消失且無 error」既有斷言模式）。
  - 驗證 `ReaderSettingsSheet` 內任一控制項調整後，`BookReaderPrefsRepository` 確實寫入新值（重新查詢資料庫確認，或關閉重開該書驗證設定被記住）。
  - 驗證螢幕方向鎖定生效與 `dispose()` 後正確還原（比照音量鍵離開閱讀器還原系統音量的既有驗證模式）。
  - **獨立驗證項（非自動化測試，人工視覺 QA）**：自動旋轉模式下實際旋轉裝置，確認 Readium／`R2WebView` 是否如反編譯推測般自動重新分頁，不需要額外手動觸發；若實測發現不會自動重新分頁，需回頭在 `ReaderScreen` 補監聽方向變化事件並手動觸發的邏輯，另立 issue 修正。
  - 需要涵蓋多種字型渲染效果比對的範例 EPUB fixture，是否可沿用既有 fixture 待第一個實作 issue 確認。

## 已驗證的技術基礎（Architecting 階段反編譯結果）

反編譯 `readium-navigator:3.3.0`（`javap -p`，見對話紀錄與 `design.md`）確認：

- **`EpubPreferences` 完整欄位清單**（已於 Issue 2 撰寫計劃階段對照官方原始碼 `readium/kotlin-toolkit` tag `3.3.0` 逐一核實，修正先前反編譯階段誤判的一處型別）：`fontFamily: FontFamily?`（**注意：非 `String?`**——`FontFamily` 是包一層 `String` 的 `value class`，建構時需 `FontFamily(name)`；先前反編譯階段誤判為 `String?`，已修正）、`fontSize: Double?`、`fontWeight: Double?`、`lineHeight: Double?`、`paragraphSpacing: Double?`、`pageMargins: Double?`（**單一數值，見 ADR 0005**）、`textAlign: TextAlign?`、`publisherStyles: Boolean?`（＝停用書本 CSS 的原生對應）等，皆有原生欄位可直接使用。
- **`TextAlign` 列舉值**：`org.readium.r2.navigator.preferences.TextAlign` 共 6 個值：`CENTER, JUSTIFY, START, END, LEFT, RIGHT`（另有一個內部 CSS 渲染層同名但只有 4 值的 enum，不使用）。
- **`fontWeight` 換算公式**：`EpubSettingsKt.class` 位元組碼確認為倍率語意，`實際 CSS font-weight = clamp(1, 1000, 400 × fontWeight)`。UI 滑桿沿用原型慣用的 300-900 CSS 數值呈現給使用者，送給原生端前需先除以 400 換算成倍率（例如 UI 顯示 700 → 送出 `fontWeight = 1.75`）。
- **自動旋轉重新分頁**：Readium 底層 `R2WebView`（Chromium WebView）的 `onSizeChanged` 只負責重新同步目前頁面位置，CSS 多欄重新排版由 WebView 引擎本身在 view 尺寸變化時自動處理；**理論上不需要 App 端手動觸發 `submitPreferences`**，但無法單靠位元組碼簽章 100% 確認方法內部邏輯，留待「測試決策」的獨立驗證項於實機確認。

### 自訂字型如何讓原生 WebView 實際載入（Issue 2 撰寫計劃階段補充驗證，已對照官方原始碼核實）

**修正說明：** 本節取代先前「`pubspec.yaml` 的 `fonts:` 區塊即可讓 `fontFamily` 生效」的錯誤假設。`fonts:` 區塊只註冊給 Flutter 自己的 Skia 文字渲染管線使用（`Text`/`TextStyle` 等 widget），與 Readium 內嵌、實際渲染 EPUB 內容的原生 Chromium WebView 完全無關——WebView 不會自動看到 Flutter 註冊的字型。以下先以反編譯 `readium-navigator:3.3.0` 定位機制存在，再逐一對照 `github.com/readium/kotlin-toolkit` tag `3.3.0` 官方原始碼核實精確簽章與語意（非僅憑反編譯猜測）：

- **`EpubPreferences.fontFamily` 型別更正**：官方原始碼核實為 `FontFamily?`（**不是**先前「已驗證的技術基礎」誤記的 `String?`），建構時需 `FontFamily(name)` 包裝。
- **`org.readium.r2.navigator.preferences.FontFamily`**：`@JvmInline value class FontFamily(val name: String)`，公開建構子（`FontFamily("SourceHanSansTC")` 直接可用），並提供內建泛型常數 `FontFamily.SERIF`／`SANS_SERIF`／`CURSIVE`／`FANTASY`／`MONOSPACE` 供 `alternates`（找不到主字型時的備援）使用。
- **`EpubNavigatorFactory.createFragmentFactory` 完整簽章**（官方原始碼核實，含全部參數名稱與預設值）：
  ```kotlin
  public fun createFragmentFactory(
      initialLocator: Locator?,
      readingOrder: List<Link>? = null,
      initialPreferences: EpubPreferences = EpubPreferences(),
      listener: EpubNavigatorFragment.Listener? = null,
      paginationListener: EpubNavigatorFragment.PaginationListener? = null,
      configuration: EpubNavigatorFragment.Configuration = EpubNavigatorFragment.Configuration(),
  ): FragmentFactory
  ```
  目前 `attachNavigator()` 只具名傳入 `initialLocator`／`listener`／`paginationListener`；新增字型登記時，額外具名傳入 `configuration = <本節下方組出的 Configuration>`。
- **`EpubNavigatorFragment.Configuration` 的 DSL 建構語法**（官方原始碼核實）：
  ```kotlin
  public companion object {
      public operator fun invoke(builder: Configuration.() -> Unit): Configuration =
          Configuration().apply(builder)
  }
  ```
  故 `EpubNavigatorFragment.Configuration { ... }` 直接可用（trailing lambda）。
- **`Configuration.addFontFamilyDeclaration` 完整簽章**（官方原始碼核實）：
  ```kotlin
  public fun addFontFamilyDeclaration(
      fontFamily: FontFamily,
      alternates: List<FontFamily> = emptyList(),
      builderAction: (MutableFontFamilyDeclaration).() -> Unit,
  )
  ```
- **`MutableFontFamilyDeclaration.addFontFace` 與 `MutableFontFaceDeclaration.addSource` 完整簽章**（官方原始碼核實）：
  ```kotlin
  public fun addFontFace(builderAction: MutableFontFaceDeclaration.() -> Unit)

  // 兩個 addSource 多載皆有 preload 預設值 false：
  public fun addSource(path: String, preload: Boolean = false) // path 是「解碼後路徑」，非完整 URL 字串，內部以 Url.fromDecodedPath(path) 轉換
  public fun addSource(href: Url, preload: Boolean = false)
  ```
  **注意：`addSource(path: String, ...)` 的 `path` 參數是相對路徑（`Url.fromDecodedPath`），不是 `https://...` 完整 URL 字串**——先前反編譯階段的假設（需自行組出完整 URL）是錯的。
- **`Configuration.servedAssets` 完整 KDoc**（官方原始碼核實，逐字翻譯）：「允許 EPUB 資源在 `https://readium/assets/` 底下存取的 asset 路徑樣式（pattern）清單。樣式可用簡易萬用字元，見 Android `PatternMatcher#PATTERN_SIMPLE_GLOB`；用 `.*` 可放行全部 app assets。」——**先前反編譯階段誤判網域為 `readium_assets`，正確網域是 `readium`、路徑前綴為 `/assets/`**；`addSource` 的相對路徑會被解析到這個網域/路徑底下（例如官方範例 `addSource("readium/fonts/OpenDyslexic-Regular.otf")` 是 Readium 內建無障礙字型，路徑慣例僅供參考，非本專案需沿用的固定前綴）。
- **本專案字型檔案的實際路徑組法**：`pubspec.yaml` 需改為 `assets:` 宣告（非 `fonts:`——`fonts:` 只影響 Flutter 自己的 Skia 渲染，兩者是獨立機制，若 Issue 3 的字型選單需要 Flutter 端預覽字型外觀可另外選用性加註 `fonts:`，不影響本節機制），5 個字型檔案各自列一個 `assets:` 項目（例如 `assets/fonts/SourceHanSansTC-VF.ttf`）；原生端透過 Flutter 官方公開 API（非反編譯，穩定公開介面）`FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/fonts/xxx.ttf")` 換算出實際打包後的 asset 路徑（例如慣例上會是 `flutter_assets/assets/fonts/xxx.ttf`，但呼叫端不可自行假設固定前綴字串，一律透過這個 API 換算），這個換算後的字串同時用於：(a) `addSource(lookupKey, preload = true)` 的 `path` 參數；(b) `servedAssets` 清單中的對應項目（可用完整字串或涵蓋整個字型目錄的簡易萬用字元樣式）。
- **完整登記程式碼骨架**（`attachNavigator()` 執行一次，字型集合固定、不隨後續 `setPreferences` 呼叫變動）：
  ```kotlin
  val loader = FlutterInjector.instance().flutterLoader()
  val fontAssets = mapOf(
      "SourceHanSansTC" to "assets/fonts/SourceHanSansTC-VF.ttf",
      "SourceHanSerifTC" to "assets/fonts/SourceHanSerifTC-VF.ttf",
      "GuanKiapTsingKhai" to "assets/fonts/GuanKiapTsingKhai.ttf",
      "TaiwanPearl" to "assets/fonts/TaiwanPearl-Regular.ttf",
      "GenRyuMinTW" to "assets/fonts/GenRyuMinTW-Regular.ttf",
  )
  val lookupKeys = fontAssets.mapValues { (_, path) -> loader.getLookupKeyForAsset(path) }
  val configuration = EpubNavigatorFragment.Configuration {
      servedAssets = lookupKeys.values.toList()
      for ((familyName, lookupKey) in lookupKeys) {
          addFontFamilyDeclaration(
              fontFamily = FontFamily(familyName),
              alternates = listOf(FontFamily.SANS_SERIF),
          ) {
              addFontFace {
                  addSource(lookupKey, preload = true)
              }
          }
      }
  }
  ```
  這 5 個 family 名稱字串（`SourceHanSansTC`／`SourceHanSerifTC`／`GuanKiapTsingKhai`／`TaiwanPearl`／`GenRyuMinTW`）須與 Dart 端 `AppFont` 對應的 family 名稱 getter 回傳值逐字一致（見 `app/lib/reader/app_font.dart` 的 `familyName` getter）。
- **殘餘風險（留待 Issue 6 實機驗證，非阻塞本 issue 撰寫）**：以上簽章與語意皆已對照官方原始碼核實（非僅反編譯猜測），但 `servedAssets` 的 `PatternMatcher` 比對字串與 `getLookupKeyForAsset` 實際回傳的路徑格式是否精確吻合、字型檔案是否真的能在 WebView 內正確渲染，只能在真實裝置上開書觀察最終確認——這與既有「自動旋轉重新分頁」殘餘風險屬同一類型（原始碼簽章正確不等於執行期行為 100% 如預期）。

## 範圍外 (Out of Scope)

- TXT 格式的版面設定串接——`epic-11-txt-engine` 尚未存在；`book_reader_prefs` 表本身格式無關，供未來直接複用。
- PDF——無 reflow/版面概念。
- FR-09 自訂字型上傳/管理/刪除——`epic-14-system-settings`（FR-35）；本 epic 僅從固定 5 款內建字型清單中選擇。
- FR-37/FR-38 全域預設值的正式設定畫面——`epic-14-system-settings`；本 epic 僅實作雙層解析邏輯與 `shared_preferences` 資料層，無 UI。
- 邊距獨立四邊控制——見 ADR 0005，降規格為單一數值。
- 九宮格導航熱區在直排模式下的左右鏡像映射邏輯——`epic-7-interaction`。
- 若實機驗證發現自動旋轉不會自動重新分頁，需額外開發監聽/手動觸發邏輯——留待驗證後視結果另立 issue，不阻塞本 epic 其餘部分。
