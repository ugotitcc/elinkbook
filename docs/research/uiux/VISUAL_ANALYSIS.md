# Visual Analysis — Flutter 現況 vs Reference Screenshot

> Source of Truth 優先順序（依指示）：Reference Screenshot → HTML/CSS 實際 rendering → `DESIGN_TOKENS.md` → `COMPONENT_SPEC.md` → `SCREEN_SPEC.md` → 現有 Flutter Architecture → Material 預設值。
> 已確認：`docs/research/uiux/reference/*.png` 12 張截圖，實際內容與文字逐一核對後，**就是 `prototype/elinkbook_theme_prototype.html` 在 Light 主題下的瀏覽器渲染結果**（書名、假資料、UI 文案完全一致）——不是另一份獨立設計稿。這代表 Reference Screenshot 與 HTML/CSS 兩層 Source of Truth 實質上是同一個來源，兩者不會互相打架，可以放心互相佐證。
> 本文件覆蓋範圍：**書架（Library）、版面設定（LayoutSettings）為完整深度分析（已逐一讀取對應 Flutter 原始碼並附行號）；設定（Settings）、閱讀器（Reader）為部分深度分析（AppBar/頂部列已查證，其餘元件待下一輪）；來源（Source）尚未讀取現有 Flutter 原始碼，本輪未列入，僅標記 `[UNKNOWN]`**。

---

## 全域根因（影響全部 5 個畫面，優先處理）

`app/lib/theme/app_theme_data.dart` 的四個 `_build*Theme()` 只定義了 `ColorScheme`／`ElinkTokens`／`SwitchThemeData`，**完全沒有** `cardTheme`／`appBarTheme`／`elevatedButtonTheme`／`outlinedButtonTheme`／`inputDecorationTheme`／`listTileTheme` 等 Shape/Elevation 相關的全域主題覆寫。這代表：

- 所有 `Card`／`AppBar`／`Button` 目前呈現的圓角、陰影、邊框，全部是 **Material 3 預設值**（`Card` 預設圓角 12dp＋`elevation: 1` 陰影；`AppBar` 預設無邊框、捲動時有 surfaceTint 疊色）。
- 顏色（`DESIGN_TOKENS.md` 已確認）100% 正確對齊 `DESIGN.md`／原型；但 Reference Screenshot 的「無陰影、統一邊框、方正到中等圓角」視覺語彙，目前完全沒有在任何一個共用主題設定裡落地。

**這是本次分析找到影響面最大的單一問題**——與其逐一元件修，建議先在 `app_theme_data.dart` 的四個 `_build*Theme()` 補上共用的 `CardTheme`（無陰影、`BorderSide` 邊框、圓角）、`AppBarTheme`（無陰影、底部細分隔線）、按鈕/輸入框圓角，一次性解決 Library／Source／Settings 三個畫面的大部分「邊框缺失、陰影多餘、圓角不符」問題。下方逐畫面分析會分別標注哪些差異屬於「這個根因」、哪些是元件各自獨立的問題。

---

## Layout

- **AppBar 高度**：Reference／原型固定 56px；Flutter `AppBar` 預設高度 56dp（`kToolbarHeight`）——✅ 相符，唯一例外是 `ReaderChromeTopBar` 已手動寫 `_height = 56`（`reader_chrome_top_bar.dart:49`），也相符。
- **Safe area**：Reference 是瀏覽器截圖，沒有系統列/safe area 概念；Flutter `Scaffold` 預設會處理，這裡沒有比較基準，不列差異。
- **書架網格內距**：Reference/原型 `p-3`(12px) 外距＋`gap-x-3 gap-y-4`(12/16px)；需要對照 `library_screen.dart` 網格建構處的實際 `padding`/`crossAxisSpacing`/`mainAxisSpacing` 數值（本輪未逐行核對，標記 `[UNKNOWN]`，留待下一輪連同 `library_paging.dart`／`book_grid_tile_metrics.dart` 一併確認）。
- **設定畫面分區間距**：Reference 每個項目是獨立卡片＋卡片間有明顯間隔（約 8–10px）；Flutter `settings_scaffold.dart` 用連續 `ListView`＋`ListTile`＋`Divider(height: 1)`，項目之間**沒有間隔、沒有各自的卡片邊界**——見下方 Checklist，Critical。

## Typography

- AppBar 標題字級：Reference 20px `font-black`；Flutter 未見到 `settings_scaffold.dart`／`library_screen.dart` 對 `AppBar.title` 額外設定字級/字重，落回 M3 `AppBarTheme` 預設（`titleTextStyle` 預設約 22sp、`FontWeight.w400` 而非 black/bold）。⚠️ 字重明顯偏細。
- `ReaderOptionTile` 選中態文字已有 `fontWeight: FontWeight.bold`（`reader_option_tile.dart:72`）✅ 相符 Reference 的粗體白字。
- `EBStepper` 數值文字（`eb_stepper.dart:60`）未設定 `fontSize`/`fontWeight`，落回環境預設；Reference 該數字是大字級粗體黑字（例如「19」）。⚠️ `[CONFLICT]`。

## Color

已由 `DESIGN_TOKENS.md` 確認 100% 相符（`app_theme_data.dart` 色值逐一比對 `DESIGN.md`），此處只記錄本輪新發現的**元件層級**色彩問題（不是 `ColorScheme` 本身錯，是個別元件選錯角色）：

- **`ReaderOptionTile` 選中態**（`reader_option_tile.dart:48-53`）：非 E-Ink 時選中態用 `primaryContainer`(淺藍底) + `onPrimaryContainer`(藍字)——這是 M3 的「Tonal」配色慣例。Reference 的選中態（「點擊」「直排」「齊行」「自動」等）是**純 `primary` 實心藍底 + 白字**，兩者是完全不同的配色策略，不是同一個顏色深淺問題。**High severity**，影響「版面設定」呈現分頁全部 5 組三態按鈕。

## Components

逐元件記錄，格式：現況（Flutter 檔案:行號）→ 與 Reference 的差異。

### AppBar（書架／設定 共用）
`library_screen.dart:792` `_buildNormalAppBar()`／`settings_scaffold.dart:106`：純 `AppBar(title:, actions:)`，無自訂 `shape`／`elevation`／底部邊框。Reference：AppBar 下方有一條約 2px 的分隔線（藍色系 `outline`），且**沒有** M3 預設的 surfaceTint 提升色。

### ReaderChromeTopBar（閱讀器頂部列）
`reader_chrome_top_bar.dart:66-69`：`Material(color: backgroundColor)` 包 `SizedBox(height: 56)`，**沒有任何 border／divider**。Reference（`閱讀_一版.png`）在頂部列下方有一條明顯的深色分隔線。⚠️ `[CONFLICT]`，且此元件是 EPUB/PDF 共用元件，影響面等於整個閱讀器。

### BookCover／CoverPlaceholder（書籍封面）
`book_cover.dart:108-116`：`CoverPlaceholder` 只有 `isEink` 時才畫 `Border.all()`，非 E-Ink（Light/Dark/Sepia）時**完全沒有邊框、沒有圓角**；`BookCover`（真實圖片，第 42 行 `Image.file`）同樣沒有外框。Reference（`書架_1.png`）**不論主題，每張書封都有明顯的細邊框**。⚠️ `[CONFLICT]`，Critical——這是書架畫面視覺辨識度最高的元件。

### `_GroupGridTile`（分類拼貼格）
`library_screen.dart:1170-1240`：整個拼貼格外層（`InkWell > Column`）**沒有任何 `Container`/`decoration`**，即沒有外框。內部「分類」角標**沒有實作**——Reference 每個分類格左上角有一個藍底白字「分類」小標籤，目前 Flutter 版本完全沒有這個元素（純 2×2 封面拼貼+下方文字，沒有角標）。⚠️ `[CONFLICT]`，Critical：角標是原型/Reference 明確存在的視覺元素，目前 Flutter 完全遺漏，不是樣式微調層級的差異。

### PagingBar（換頁列）
`[UNKNOWN]`——本輪未讀取 `library_paging.dart`／換頁列 UI 建構程式碼，待下一輪確認實際按鈕尺寸/邊框/圓角。

### EBStepper（字級/行距/邊界等步進器）／Slider
`eb_stepper.dart` 全檔：純文字+`IconButton`(`Icons.remove`/`Icons.add`)，**沒有外框、沒有圓角容器**——Reference 每個步進器的 `-`/`+` 都是有黑色邊框的方形按鈕（見 `版面設定_文字_1.png`）。⚠️ `[CONFLICT]`。

**⚠️ 需要您決定，不是單純視覺樣式問題**：`reader_settings_sheet.dart:582-597`／`:742-764` 顯示 **`EBStepper` 目前只在 E-Ink 模式使用，非 E-Ink（Light/Dark/Sepia）一律用 `Slider`**，這是 `DESIGN.md` §18.3「E-Ink 模式下 Slider 替換為 Stepper」明文規則的**刻意落地**，且有審查記錄佐證（`review-plan-issue-1.md`／`review-plan-issue-3.md`）。但 Reference Screenshot（Light 主題）顯示的是 Stepper，不是 Slider——這是因為**原型本身從未做過 Slider 版本**（`DESIGN_TOKENS.md` 已記錄此為原型缺口 `[UNKNOWN]`，非刻意設計）。
若照本次任務「Reference Screenshot 優先於現有 Architecture」的字面規則，會要求非 E-Ink 模式也改用 Stepper、移除 Slider——但這牽動的已經不只是視覺樣式，而是**互動控制元件本身**（連續拖曳 vs. 離散點擊），且會推翻一個有審查記錄的既有設計決策。**在您明確裁示前，我不會動這一塊**，先列入 Critical 但標註「待決策」，不歸入待修清單。

### 設定畫面（Settings）整體結構
`settings_scaffold.dart:123-289`：連續 `ListView` + `ListTile` + `Divider(height:1)` 分隔各分區，項目之間無間距、無各自邊框。Reference（`設定_1.png`／`設定_2.png`）每個項目都是**獨立、有邊框、有圓角、彼此間有間距的卡片**，不是連續清單。⚠️ `[CONFLICT]`，Critical，整個畫面的視覺骨架都不同，不是單一元件的問題。

**已確認做對、不要「修正」回原型的地方**：`settings_scaffold.dart:314-330` E-Ink 鎖定佈景選擇器用的是**虛線圓形邊框**（`_LockedDotBorderPainter`），正確對應 `DESIGN.md` §17.2「邊框加粗為虛線，不使用降低對比度」——這一點原型本身反而做錯了（用 `opacity`，見 `DESIGN_TOKENS.md` 已記錄的衝突）。這裡 Flutter 已經比 Reference／原型更準確，維持現狀，不要照抄 Reference。

### Switch（E-Ink／頁首頁尾等開關）
`app_theme_data.dart:52-66` `_buildSwitchTheme()`：`thumbColor`/`trackColor` 皆用 `onSurface`（黑/深色系），非 M3 標準的 `primary` 藍色填色。Reference（`版面設定_邊界_1.png`「顯示頁首」開關）ON 態是**藍色**（`primary`）填滿樣式。目前 Flutter Switch 主題是 Epic-35 為電子紙可辨識度刻意選的 `onSurface`（見 `app_theme_data.dart:39-51` 註解），並非疏漏。⚠️ 這裡同樣是「需要判斷是否要為了視覺還原犧牲既有電子紙可辨識度決策」的衝突，先列 High、不預設修法，待您裁示是否要恢復 M3 標準的 `primary` 填色 Switch（僅限非 E-Ink 主題；E-Ink 主題本身這個決策的必要性不受影響，因為 E-Ink 下 `onSurface` 就是純黑，跟 `primary` 純黑相同）。

## Responsive
本輪 Reference 只有手機尺寸單一斷面，且原型本身沒有 `@media` 規則（`SCREEN_SPEC.md` 已記錄）。Flutter 現有畫面在平板/桌機下的行為（`AdaptiveShellScaffold`）不在本次比對範圍內，`[UNKNOWN]`。

---

## Visual Difference Checklist

| Category | Reference | Flutter | Difference | Severity |
|---|---|---|---|---|
| 書封／封面佔位符邊框 | 所有主題皆有細邊框 | 非 E-Ink 主題完全無邊框（`book_cover.dart:113`） | 缺少邊框 | **Critical** |
| 分類拼貼格「分類」角標 | 左上角藍底白字角標常駐顯示 | 完全未實作 | 缺少元素 | **Critical** |
| 分類拼貼格外框 | 有細邊框 | 無任何 `decoration`（`library_screen.dart:1170-1240`） | 缺少邊框 | **Critical** |
| 設定畫面整體結構 | 各項目獨立卡片＋間距 | 連續 ListTile＋細分隔線 | 版面骨架不同 | **Critical** |
| 步進器容器樣式 | `-`/`+` 為有邊框的方形按鈕 | 純 `IconButton`，無邊框無圓角 | 缺少邊框/圓角 | High |
| `ReaderOptionTile` 選中態配色 | 純 `primary` 實心＋白字 | `primaryContainer` 淺底＋`primary`字 | 配色策略不同 | High |
| AppBar 底部分隔線 | 常駐 ~2px 分隔線 | 無（M3 預設無邊框） | 缺少邊框 | High |
| `ReaderChromeTopBar` 底部分隔線 | 常駐分隔線 | 無（`reader_chrome_top_bar.dart:66`） | 缺少邊框 | High |
| AppBar 標題字重 | `font-black`（近似 900） | M3 預設（約 w400） | 字重明顯偏細 | Medium |
| `EBStepper` 數值文字字級/字重 | 大字級、粗體 | 無明確設定，環境預設 | 視覺不突出 | Medium |
| Card／Button 圓角 | 統一 ~6px（原型）／視覺近似小圓角 | M3 `Card` 預設 12dp | 圓角略大，非嚴重 | Low |
| Card 陰影 | 無陰影（全靠邊框） | M3 `Card` 預設 `elevation:1` 有陰影 | 多出不必要的陰影 | Medium（與全域根因連動，修一次全解） |
| `Switch` 開／關填色 | ON 態 `primary` 藍色填滿 | ON 態 `onSurface` 深色填滿（Epic-35 電子紙可辨識度決策） | 顏色策略不同，**牽動既有決策，待裁示** | High（待決策，非待修） |
| 非 E-Ink 主題用 `Slider`（字級/行距等） | 全部用 Stepper（`-`/`+`按鈕） | 非 E-Ink 用 `Slider`，E-Ink 才用 `EBStepper`（`DESIGN.md` §18.3 刻意決策） | 控制元件種類不同，**牽動既有決策，待裁示** | **Critical（待決策，非待修）** |

---

## 需要您裁示才能繼續的兩個決策點

1. **非 E-Ink 主題的字級/行距/邊界等控制項，要不要把 `Slider` 全部換成 `EBStepper`（-/+按鈕）？** 這會讓 Light/Dark/Sepia 三個主題失去連續拖曳調整的能力，且推翻 `DESIGN.md` §18.3＋既有審查記錄的設計決策，純粹是因為原型從未做過 Slider 版本才「看起來」該用 Stepper。
2. **非 E-Ink 主題的 `Switch` 開關填色，要不要從目前的 `onSurface`（深色，Epic-35 電子紙可辨識度決策）改回 M3 標準的 `primary`（藍色）填色以貼近 Reference？**

這兩點都會覆蓋過去已有審查記錄的架構決策，依「不要破壞既有 Architecture／不要修改 Business Logic」的原則，我不會自行決定，先停在這裡等您回覆。

## 建議的修改順序（其餘不需要裁示、可直接動工的項目）

若上述兩點您傾向「維持現狀，不改」，其餘 Critical/High 項目彼此獨立、不衝突架構決策，我建議依此順序修（每完成一批就跑 `flutter analyze`）：

1. `app_theme_data.dart` 補齊 `CardTheme`／`AppBarTheme`（無陰影、邊框、圓角）——一次解決全域根因，連動修好多數 Card/Button/AppBar 的圓角與陰影問題。
2. `book_cover.dart`：`CoverPlaceholder`／`BookCover` 補上非 E-Ink 主題的邊框。
3. `library_screen.dart` `_GroupGridTile`：補外框＋「分類」角標。
4. `eb_stepper.dart`：補邊框＋圓角＋數值文字樣式。
5. `reader_option_tile.dart`：選中態改為 `primary` 實心＋`onPrimary` 文字。
6. `reader_chrome_top_bar.dart`：補底部分隔線。
7. `settings_scaffold.dart`：改為卡片式版面（改動範圍較大，需要決定是否新增共用 `EBSettingsCard`／複用其他既有卡片元件，避免重複造元件——依指示 5「優先重用現有 Components、不要建立重複 Component」）。

在您確認兩個決策點＋這個順序後，我會依序修改、每一步跑 `flutter analyze`，並用 Chrome（`flutter run -d chrome`，目前環境沒有連接 Android 裝置/模擬器，僅 Windows/Chrome/Edge 三個 target）截圖比對，產出 `VISUAL_VALIDATION.md`。
