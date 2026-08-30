# Epic 27 Issue 5~8 實作計畫文件審查報告

**審查對象：**
- docs/epics/epic-27-reader-device-compat/plans/plan-issue-5.md
- docs/epics/epic-27-reader-device-compat/plans/plan-issue-6.md
- docs/epics/epic-27-reader-device-compat/plans/plan-issue-7.md
- docs/epics/epic-27-reader-device-compat/plans/plan-issue-8.md

**審查依據：** docs/epics/epic-27-reader-device-compat/issues.md Issue 5~8
**審查日期：** 2026-08-23

---

## 總覽

本次是事前計畫審查，四份計畫尚未實作。已逐一開啟並完整核對以下既有原始碼與測試檔案：`app/lib/screens/library_screen.dart`、`app/lib/screens/library_screen_dependencies.dart`、`app/lib/screens/settings_screen.dart`、`app/lib/screens/pdf_settings_sheet.dart`、`app/lib/screens/reader_settings_sheet.dart`、`app/lib/screens/fxl_settings_sheet.dart`、`app/lib/reader/pdf_crop_frame_overlay.dart`、`app/lib/theme/app_theme.dart`、`app/lib/theme/app_theme_data.dart`、`app/test/screens/library_screen_test.dart`、`app/test/screens/pdf_settings_sheet_test.dart`、`app/test/screens/reader_settings_sheet_test.dart`、`app/test/reader/pdf_crop_frame_overlay_test.dart`。

最重要的總體發現：**`buildEinkThemeData()` 並非計畫遺漏建立的測試 helper，而是既有正式函式**（`app/lib/theme/app_theme_data.dart:21`），三份計畫的測試片段引用它是合理且可行的——這點推翻了審查前的初步懷疑方向 #4。但另一方面，**Issue 5 與 Issue 8 的測試片段都各自獨立地無法通過編譯**，因為 `LibraryScreen` 建構子的 `repository`／`importService`／`prefsManager` 三個參數皆為 `required` 且無預設值，兩份計畫的測試片段都完全沒有提供——這比審查前懷疑方向 #1 描述的「兩份計畫互相矛盾」更嚴重：即使只單獨看其中一份計畫，測試本身就過不了編譯。

---

## Issue 5：E-Ink 高對比模式狀態感知與切換識別強化

### Strengths

- Task 1 Step 3 第 3 點所指的 `app/lib/screens/library_screen.dart:860` 行號準確——實際核對後，`builder: (context) => SettingsScreen(` 確實就在第 860 行，是導覽至 `SettingsScreen` 的正確插入點。
- `SettingsScreen` 確實已有 `final bool isEinkMode;` 欄位（`settings_screen.dart:27`，預設值 `false`），計畫正確判斷不需要重新新增這個欄位，只需新增 `onEinkModeChanged` 回呼——這點審查前的懷疑方向 #2 已被計畫正確處理，不是遺漏。
- `LibraryThemeDependencies`（`library_screen_dependencies.dart:108-119`）的 `isEinkMode`／`onEinkModeChanged` 兩個欄位皆有預設值（`false`／`null`），Task 2 測試片段以具名參數建構它本身沒有問題。

### Issues

#### Critical (Must Fix)

1. **`plan-issue-5.md:112-119`（Task 2 Step 1 測試片段）與 `app/lib/screens/library_screen.dart:65-78`（`LibraryScreen` 建構子）不相容，無法通過編譯。**
   `LibraryScreen` 建構子的 `repository`、`importService`、`prefsManager` 三個參數皆宣告為 `required this.xxx`，沒有預設值。計畫的測試片段：
   ```dart
   LibraryScreen(
     themeDependencies: LibraryThemeDependencies(
       isEinkMode: true,
       onEinkModeChanged: (val) => toggledValue = val,
     ),
   ),
   ```
   完全沒有提供這三個必要參數，會直接編譯失敗，不會進到「執行測試後失敗」這一步（Step 2「預期：FAIL」的前提就不成立）。既有 `app/test/screens/library_screen_test.dart:100-105` 已示範了正確寫法（`FakeLibraryRepository()`／`FakeBookImportService()`／檔案共用 `prefsManager`），計畫應改用相同 fixture 模式。

#### Important (Should Fix)

2. **`plan-issue-5.md:143-155`（Task 2 Step 3 實作片段）內的 `Brightness.dark` 分支是死碼，與既有主題解析架構不一致。**
   片段中：
   ```dart
   color: widget.themeDependencies.isEinkMode
       ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)
       : Colors.transparent,
   ```
   但核對 `app/lib/theme/app_theme_data.dart:25-31`（`resolveThemeData()`）與 `:127-152`（`_buildEinkTheme()`）可知：只要 `isEinkMode == true`，全域套用的 `ThemeData` 一律是 `_buildEinkTheme()`，而該函式寫死 `brightness: Brightness.light`（`app_theme_data.dart:141`）。也就是說，`widget.themeDependencies.isEinkMode == true` 的情況下，`Theme.of(context).brightness` 永遠不可能是 `Brightness.dark`——這個三元運算式的 `Colors.white` 分支永遠不會被走到。實際執行結果不算錯（一律變成純黑背景，符合 Issue 描述的「反白實心底色」），但這段程式碼會誤導後續維護者以為「E-Ink 模式下深色主題會有不同的按鈕底色」，而事實上 E-Ink 開啟時會完全覆蓋原本的主題選擇（`AppTheme` 的選擇僅在 E-Ink 關閉時才影響實際呈現，見 `app_theme.dart:1-6` 的類別註解）。建議在計畫中直接拿掉這個死碼分支，固定使用 `Colors.black`／`Colors.white`，並附註「E-Ink 開啟時全域主題一律為 `_buildEinkTheme()`，故不需要再判斷 brightness」。

#### Minor (Nice to Have)

3. Task 2 測試片段中 `expect(iconButton.tooltip, contains('開啟'))` 與實作片段的 `tooltip: 'E-Ink 模式：已開啟（點擊切換）'` 能對得上，斷言本身沒問題；但由於整個測試因 Critical #1 過不了編譯，這條斷言目前無法被實際驗證過，需要連同 Critical #1 一併修正後重新確認。

---

## Issue 6：閱讀器版面設定面板圖示選項高對比選中狀態重構

### Strengths

- **`buildEinkThemeData()` 確實存在**，是 `app/lib/theme/app_theme_data.dart:21` 的正式匯出函式，三份測試片段（Task 1/2/3）用 `import 'package:elinkbook/theme/app_theme_data.dart';` 引用它完全合理，不是計畫遺漏建立的 test helper（推翻審查前懷疑方向 #4 的「遺漏」假設）。
- 逐一核對 `PdfSettingsSheet`（`pdf_settings_sheet.dart`）、`ReaderSettingsSheet`（`reader_settings_sheet.dart`）、`FxlSettingsSheet`（`fxl_settings_sheet.dart`）三個檔案內所有以 `IconButton` + `color: selected ? primary : null` 呈現選中狀態的選項群組後，確認計畫 Architecture 段落列出的範圍是**窮盡的**，沒有遺漏：
  - `PdfSettingsSheet`：Fit 模式（`pdf_settings_fit_mode_*`，行 195-206）、雙頁模式（`pdf_settings_dual_page_mode_*`，行 216-227）、頁面方向（`pdf_settings_dual_page_direction_*`，行 265-276，對應原始碼中標題文字本身也叫「頁面方向」，行 258）、換頁動畫（`pdf_settings_page_turn_animation_*`，行 286-297）、裁切模式（`pdf_settings_crop_mode_*`，行 370-381）。
  - `ReaderSettingsSheet`：文字對齊（行 765-775）、排版方向（`reader_settings_writing_mode_*`，行 799-810）、翻頁模式（`reader_settings_page_turn_mode_*`，行 834-845）、螢幕方向（`reader_settings_screen_orientation_*`，行 881-894）、分欄（`reader_settings_column_mode_*`，行 548-587）——五組，與計畫描述一致。
  - `FxlSettingsSheet`：雙頁模式（`fxl_settings_dual_page_mode_*`，行 88-99）、翻頁方向（`fxl_settings_direction_*`，行 112-123）。
- `withValues(alpha:)` 已在既有程式碼中使用過（`settings_screen.dart:239`、`pdf_reader_view.dart`），確認目前 Flutter SDK 版本相容，不是本次計畫首次引入的風險項目。
- Task 3 測試片段建構 `ReaderSettingsSheet(...)` 時提供的具名參數（`bookId`、`prefs`、`onChanged`、`onSaveAsPreset`、`onApplyPreset`、`onApplyFromBook`、`onRequestBookPicker`、`onDeletePreset`）與實際建構子（`reader_settings_sheet.dart:39-51`）逐一核對後完全吻合，可正常編譯。

### Issues

#### Critical (Must Fix)

（無）

#### Important (Should Fix)

1. **E-Ink 主題偵測機制（`plan-issue-6.md:138-139`）用「顏色特徵比對」而非明確布林參數，與專案既有慣例不一致，且有長期脆弱風險。**
   ```dart
   final isEink = theme.colorScheme.primary == Colors.black &&
       theme.scaffoldBackgroundColor == Colors.white;
   ```
   核對 `app/lib` 後發現，`isEinkMode` 這個明確布林旗標已經在多個檔案間逐層明確傳遞（`library_screen.dart`、`library_screen_dependencies.dart`、`main.dart`、`remote_server_list_screen.dart`、`remote_catalog_screen.dart`、`settings_screen.dart`），是本專案處理 E-Ink 判斷的既定慣例，而非猜測主題顏色特徵。`ReaderOptionTile` 改用「顏色反推」的方式，一旦未來新增任何以黑底白字為視覺基調的一般主題（例如某種「純粹黑白復古」佈景），會被誤判為 E-Ink 模式。更根本的問題是：`PdfSettingsSheet`／`ReaderSettingsSheet`／`FxlSettingsSheet` 目前的建構子都**沒有** `isEinkMode` 參數，若要讓 `ReaderOptionTile` 改吃明確布林值，勢必要幫這三個 Sheet 都新增建構參數、並讓呼叫端（`ReaderScreen`）貫穿傳遞——這是比計畫目前規模更大的改動，計畫完全沒有評估或提及這個範圍擴張的可能性。建議至少在計畫中明確記錄「已知選擇顏色推斷而非顯式參數，原因是避免擴大三個 Sheet 的建構子改動範圍，此為刻意的技術折衷」，讓後續維護者不會誤以為是疏忽。
2. **測試斷言 `find.descendant(of: ..., matching: find.byType(Container)).first`（Task 1/2/3 三處测试片段皆有）對元件內部結構高度耦合，脆弱。**
   以目前提案的 `ReaderOptionTile` 實作（`Tooltip → Material(color: transparent) → InkWell(key: itemKey) → Container(decoration: ...)`）而言，`InkWell` 底下確實只有一個 `Container`，`.first` 目前能抓對；但只要日後任何一次重構在 `InkWell` 與最終 `Container` 之間多包一層（例如為了 ripple 裁切邊界新增 `ClipRRect`、或為了間距新增 `Padding` 之外再包一層 `Container`），這個測試就會靜默改抓錯的節點，產生「測試通過但功能沒真的做對」或「功能做對但測試莫名 fail」的假訊號。建議改為在真正帶 `BoxDecoration` 的容器上額外掛一個專屬 Key（例如衍生自 `itemKey` 的 `Key('${itemKeyValue}_decoration')`），測試直接用該 Key 定位，不依賴子樹中「第幾個 Container」。
3. **Task 2／Task 3 的測試片段沒有提及需要在既有測試檔案新增 `import`。**
   實際核對 `app/test/screens/pdf_settings_sheet_test.dart`（第 1-11 行）與 `app/test/screens/reader_settings_sheet_test.dart`（第 1-11 行）的現有 import 清單，兩者都**沒有**匯入 `package:elinkbook/theme/app_theme_data.dart`。計畫 Task 2/3 只寫「在 ... 中追加測試」並貼出 `testWidgets` 內文，沒有一併列出需要新增的 import 陳述式，容易被實作者遺漏而導致 `buildEinkThemeData` 找不到符號、編譯失敗。應在 Task 2/3 的 Files/Interfaces 段落明確加一行「新增 import」提醒。

#### Minor (Nice to Have)

4. `pdf_settings_crop_mode_manual`（手動選區按鈕）目前完全沒有「選中」語意（即使 `_cropMode == PdfCropMode.manual`，程式碼也不會反映選中狀態，見 `pdf_settings_sheet.dart:386-391`）。Task 2 Step 3 第 3 點只寫「手動選區裁切按鈕亦改為高對比外框按鈕」，沒有說清楚這顆按鈕改用 `ReaderOptionTile` 時要不要／能不能反映「目前裁切模式是否為 manual」的選中狀態——這個模糊地帶建議在實作前先釐清，避免實作者自由發揮出跟其餘選項不一致的視覺規則。

---

## Issue 7：PDF 手動裁切疊加層高對比視覺與 FAB 按鈕重構

### Strengths

- Global Constraints 列出的 6 個 Key（`pdf_crop_frame_confirm`、`pdf_crop_frame_cancel`、四個 `pdf_crop_frame_handle_*`）與 `app/lib/reader/pdf_crop_frame_overlay.dart` 現有程式碼（第 108-153 行）完全吻合，沒有列漏或列錯。
- 既有 `app/test/reader/pdf_crop_frame_overlay_test.dart` 的 6 則測試都是透過 `tester.tap`／`tester.drag` 直接對這些 Key 操作（例如第 30、47、69、91、115、144-147 行），並不斷言按鈕/控制點的視覺樣式（顏色、有無 `Material` 包裹）——只要計畫的重構把這些 Key 原樣保留在可被 `tap`/`drag` 命中的 widget（`InkWell`/`GestureDetector`）上，既有 6 則測試理論上不會被破壞，計畫「確認既有 6 則測試維持通過」的預期是合理的。
- 取消／確認按鈕改為 `Material` 包裹 `InkWell` 後，`tester.tap(find.byKey(...))` 仍可正常命中（`InkWell` 本身可被 hit-test），新增的 `find.ancestor(matching: find.byType(Material))` 斷言能有效鑑別「有沒有背景容器」，不是空泛斷言。

### Issues

#### Critical (Must Fix)

（無）

#### Important (Should Fix)

1. **Task 1 的實作片段只定義了 `CropOverlayPainter` 類別，卻沒有展示它實際如何被接進 `build()` 方法的 `Stack`／取代現有的 `Positioned.fromRect(...Container...border...)`。**
   現有實作（`pdf_crop_frame_overlay.dart:97-106`）用一個帶 `BoxDecoration.border` 的 `Container` 畫框，完全沒有任何 `CustomPaint`。計畫 Step 3 只給了「新增 `CropOverlayPainter` 類別」的程式碼，以及「更新 `_buildHandle`」「底部按鈕改為 FAB 樣式」兩段程式碼，唯獨遺漏了「把 `CropOverlayPainter` 實際包進 `CustomPaint` 並放進 `Stack`，取代舊有的邊框 `Container`」這一步的程式碼或明確指示。若實作者只照抄計畫給出的三段程式碼，`CropOverlayPainter` 類別會變成一段沒有任何地方使用的死碼，遮罩完全不會被畫出來——雖然 Step 4 的驗收測試 `expect(find.byType(CustomPaint), findsWidgets)` 最終會迫使實作者發現這個疏漏，但這代表計畫本身描述不完整，會讓「跟著計畫走」的執行過程卡關、需要臨場自行補完關鍵步驟。另外要留意：`CropOverlayPainter` 需要拿到「完整可用畫布尺寸」（`size`）與絕對座標的 `cropRect`（即 `frameRect`，而非目前 `_left/_top/_right/_bottom` 的 0-1 比例值）才能正確執行 `Path.combine`，這代表對應的 `CustomPaint` 必須用 `Positioned.fill` 或直接作為 `Stack` 的第一個子元件（鋪滿整個 `LayoutBuilder` 量到的 `size`），而不能沿用舊有 `Positioned.fromRect(rect: frameRect, ...)` 只鋪在裁切框範圍內的作法——這個座標系統轉換上的細節，計畫完全沒有著墨。
2. **`CropOverlayPainter.paint()` 每次 `shouldRepaint` 觸發都執行 `Path.combine(PathOperation.difference, ...)`，在使用者拖曳四角控制點時有掉幀風險，值得評估。**
   `_dragHandle()`（`pdf_crop_frame_overlay.dart:42-60`）在 `onPanUpdate` 的每一個手勢回呼都呼叫 `setState()`，也就是每個觸控影格都會讓 `cropRect` 改變、觸發 `shouldRepaint`（計畫程式碼：`cropRect != oldDelegate.cropRect`）為真，進而重新執行一次 `Path.combine` 布林運算。Path 布林運算相對於單純畫幾個矩形而言運算量明顯較高；本產品明確以 E-Ink／低效能裝置為目標受眾之一（CLAUDE.md 開發指引與 Issue 7 情境本身就是回報電子紙裝置上的可辨識度問題），在互動式拖曳的每一影格都做這個運算，有實際掉幀/手感卡頓的風險。建議計畫中至少評估一種替代方案並在 Task 1 明確採用，例如：改用四個不重疊的矩形（上/下/左/右色帶）直接疊加遮罩，避免 `Path.combine`；或至少在 `shouldRepaint` 中加入節流（例如量化到整數像素才視為「改變」，減少布林運算次數）。

#### Minor (Nice to Have)

3. Task 1 Step 3 第 2 點「更新 `_buildHandle` 為圓形帶邊框與陰影控制點」只有一句描述，沒有像另外兩處改動一樣附上具體程式碼片段。核對現有 `_buildHandle`（`pdf_crop_frame_overlay.dart:62-84`）可知，目前 `key: key` 是掛在最外層的 `GestureDetector` 上（不是視覺用的 `Container`），既有 6 則測試也是直接對這個 Key 呼叫 `tester.drag(...)`。只要實作者記得把 `key: key` 留在同一個可被拖曳手勢命中的 widget 上（不論它底下的視覺子樹怎麼改成圓形/陰影），既有測試就不會被破壞——但因為這段描述層級明顯比另外兩段程式碼略，建議比照補一段最小程式碼示意，降低「改到一半忘記把 Key 留在正確位置」的風險。

---

## Issue 8：書架排序選單加入當前模式選中指示

### Strengths

- Global Constraints 列出的 `library_sort_button`／`library_sort_option_${sortBy.name}` 與 `library_screen.dart:750`、`:758` 現有程式碼完全吻合。
- 測試片段中「預設排序為最近閱讀（lastRead）」的假設，核對 `app/lib/screens/library_book_list_controller.dart:38`（`LibrarySortBy sortBy = LibrarySortBy.lastRead;`）確認正確——雖然實際載入時 `initialLoad()` 還會透過 `LibraryPreferences.loadSortBy()` 讀取持久化值（`library_book_list_controller.dart:52`），但在測試環境下（`SharedPreferences.setMockInitialValues({})`，已由既有檔案 `setUp()` 覆蓋，見下方 Critical #1 說明）沒有先前存入的值時會回退到這個欄位預設值，斷言方向正確。
- 「有無 `Icons.check`」本身是強指示（未選中為完整 24dp 透明佔位，不是弱化的顏色差異），這點確實足以滿足使用者「無法辨識目前選用哪一種排序模式」的訴求，即便在 E-Ink 模式下顏色差異失效（見下方 Minor #2），單靠圖示存在與否加上粗體字重已經是無歧義的判斷依據。

### Issues

#### Critical (Must Fix)

1. **`plan-issue-8.md:41-43`（Task 1 Step 1 測試片段）的 `LibraryScreen()` 建構呼叫無法通過編譯，且與 Issue 5 Task 2 各自獨立犯下同一種錯誤。**
   ```dart
   await tester.pumpWidget(MaterialApp(
     home: LibraryScreen(),
   ));
   ```
   `LibraryScreen` 建構子（`library_screen.dart:65-78`）的 `repository`、`importService`、`prefsManager` 三個參數皆為 `required`，無預設值。這段測試完全沒有提供任何建構參數，會直接編譯失敗——這不只是「與 Issue 5 的測試片段互相矛盾」（Issue 5 至少還帶了 `themeDependencies` 具名參數，但兩者都同樣漏了三個必要參數），而是**這份測試就算 Issue 5 完全不存在、單獨拿出來也一樣過不了編譯**。應改用既有測試檔案（`app/test/screens/library_screen_test.dart:100-105`）已經建立的 fixture 模式：
   ```dart
   LibraryScreen(
     repository: FakeLibraryRepository(),
     importService: FakeBookImportService(),
     prefsManager: prefsManager,
   ),
   ```
   （`prefsManager` 沿用該測試檔案共用 `setUp()` 建立的執行個體，見 `library_screen_test.dart:87-90`）。

#### Important (Should Fix)

2. Issue 5 Task 2 與 Issue 8 Task 1 都會把新測試追加進同一份 `app/test/screens/library_screen_test.dart`，且兩者各自獨立犯下同一種「漏帶必要建構參數」錯誤（見上方 Issue 5 Critical #1、Issue 8 Critical #1）。由於兩份計畫聲稱「依賴：無」可平行進行，若由兩個不同的實作批次分別執行，其中一批修正了自己的測試片段後，另一批若沒有同步核對，容易重蹈覆轍或造成合併衝突。建議在兩份計畫的 Global Constraints 都補一句「新增至 `library_screen_test.dart` 的測試須遵循既有檔案的 fixture 建構模式（`FakeLibraryRepository`／`FakeBookImportService`／檔案共用 `prefsManager`）」，明確定錨到同一套既有慣例。

#### Minor (Nice to Have)

3. 計畫 Solution 段落的「使用主題色/高對比色」在 E-Ink 模式下其實是無效描述：`_buildEinkTheme()`（`app_theme_data.dart:127-138`）的 `colorScheme.primary` 與 `colorScheme.onSurface` 皆為 `Colors.black`，選中項目文字用 `primaryColor`、未選中項目文字用預設色（繼承自 `onSurface`），兩者在 E-Ink 模式下會是完全相同的黑色——顏色本身在這個模式下不構成任何辨識度貢獻，真正發揮作用的只有 `Icons.check` 的有無與 `FontWeight.bold`。這不影響驗收標準是否達成（見 Strengths 說明），但計畫文字若不註明這一點，容易讓後續維護者誤以為「顏色也在 E-Ink 下起了作用」，建議補一句說明其實際生效範圍僅限一般主題（Light/Dark/Sepia）。

---

## Recommendations

1. **Issue 5 與 Issue 8 應優先修正各自測試片段中 `LibraryScreen(...)` 缺少必要建構參數的問題**（Issue 5 Critical、Issue 8 Critical）——這是唯二會直接讓 `flutter test` 連編譯都過不了的錯誤，且彼此獨立、與哪份先實作無關，兩邊都要修。建議統一改用 `library_screen_test.dart` 現有的 `FakeLibraryRepository`／`FakeBookImportService`／共用 `prefsManager` 模式。
2. **Issue 6 應在動手前先決定 E-Ink 偵測機制的技術折衷是否可接受**：目前的「顏色特徵比對」能動、但與既有 `isEinkMode` 顯式布林傳遞慣例不一致；若團隊接受這個折衷（避免三個 Sheet 都新增建構參數的範圍擴張），建議至少在程式碼註解與計畫中明確記錄原因，而非讓後續維護者誤以為是疏漏。測試斷言的 `.first Container` 脆弱寫法也建議一併改為專屬 Key。
3. **Issue 7 的 Task 1 需要補完 `CropOverlayPainter` 實際接入 `Stack`／`CustomPaint` 的程式碼**，並且認真評估 `Path.combine` 在拖曳互動下的效能疑慮（目標裝置含 E-Ink 低效能硬體），這兩點都建議在計畫文件層級先補完，而不是留給實作者臨場摸索。
4. 四份計畫在「保留既有 Key」「窮盡既有選項群組」這兩個面向的準確度都相當高（尤其 Issue 6 對三個 Settings Sheet 的涵蓋範圍是完整的、Issue 7 對六個 Key 的列舉是精確的），顯示計畫作者確實有花時間核對過既有程式碼；主要問題集中在「測試程式碼片段本身能否通過編譯」與「新增元件的實作步驟是否完整可依樣畫葫蘆」兩類，性質上都是可在動手實作前的一次校對中修正的問題，不涉及需求理解錯誤或架構方向錯誤。

## Assessment

**Issue 5 — Ready for implementation?** With fixes
**Reasoning：** Task 2 的測試片段有一個會導致編譯失敗的 Critical 問題（缺少 `LibraryScreen` 必要建構參數），必須先修正才能開始 TDD 流程；另有一個死碼分支（Important）建議一併清理，但不阻塞實作方向本身——Solution 的兩個子項（AppBar 按鈕強化、SettingsScreen 新增開關）方向正確，且 `SettingsScreen` 既有 `isEinkMode` 欄位、`library_screen.dart:860` 行號等關鍵引用都準確無誤。

**Issue 6 — Ready for implementation?** With fixes
**Reasoning：** 沒有會直接卡住編譯的 Critical 問題，`buildEinkThemeData()` 確實存在、既有 Key 涵蓋範圍窮盡且準確，是四份計畫中與既有程式碼吻合度最高的一份。但 E-Ink 偵測機制的架構折衷（Important #1）建議實作前先與計畫作者/團隊確認是否接受，測試斷言的脆弱寫法（Important #2）與遺漏的 import 提醒（Important #3）也建議在計畫文件層級先補上，避免實作過程中零星卡關。

**Issue 7 — Ready for implementation?** With fixes
**Reasoning：** 沒有 Critical 問題，既有 6 個 Key 與既有測試的相容性判斷正確。但 Task 1 的「minimal implementation」程式碼片段本身不完整（遺漏 `CropOverlayPainter` 如何接入 `Stack`／`CustomPaint` 這個關鍵步驟），加上互動式拖曳下的效能疑慮未被評估或給出因應方案，這兩點都建議在計畫文件中補完後再交付實作，否則實作者需要臨場自行補完缺口，容易產生落差。

**Issue 8 — Ready for implementation?** With fixes
**Reasoning：** Solution 本身簡單直接、Key 命名與預設排序假設都核對無誤，唯一的問題是 Task 1 測試片段完全沒有提供 `LibraryScreen` 的必要建構參數，這是會直接讓 `flutter test` 編譯失敗的 Critical 問題，且與 Issue 5 各自獨立重複同一種錯誤模式，修正方式明確（比照既有測試檔案的 fixture 模式），修正後即可直接進入 TDD 流程。
