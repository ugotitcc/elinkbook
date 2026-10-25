# Issue 2：自訂閱讀顏色實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:executing-plans`（行內執行）逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 版面設定面板新增「佈景」分頁。使用者可以替「目前正在用的佈景」（淺色／深色／羊皮紙）分別設定閱讀器的背景色與文字色，用 RGB 三條滑桿或 `#RRGGBB` 色碼輸入。全域、不分書；E-Ink 模式不套用；只影響 Foliate 流式閱讀器頁面。

**Architecture：** 新增純 Dart 的 `ReaderColors`（背景色、文字色，各自可為 `null`）與 `ReaderColorPreferences`（`SharedPreferences`，每個佈景兩個 key）。`ReaderFeatureDependencies` 新增一個有預設值的欄位帶入它。`ReaderScreen` 新增 `appTheme` 參數，啟動時讀出目前佈景的自訂色，疊在 `_themedTextColor`／`_themedBackgroundColor` 上；這兩個值本來就會送進 `FoliateReaderView` → `main.js`（`textColor`／`backgroundColor` 已支援），所以 **JS 與 `FoliateReaderView` 不用改**。`ReaderSettingsSheet` 新增第 5 個分頁「佈景」，自己持有本地顏色狀態，改動時回呼 `onReaderColorsChanged`，由 `ReaderScreen` 更新畫面並寫入偏好。

**Tech Stack：** Flutter／Dart、`shared_preferences`、`flutter_test`、`flutter gen-l10n`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-65-reader-indent-and-colors/epic.md`「Discovery 決策」（5、6、9、10）與「Issue 2 設計決策」（1～13，後者優先）。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **欄位語意**：`ReaderColors.background == null`＝沒設定，退回佈景原色（`Theme.scaffoldBackgroundColor`）；`text == null`＝退回 `colorScheme.onSurface`。兩個顏色獨立，可只設一個。
- **儲存**：key 為 `reader_color_<light|dark|sepia>_background` 與 `reader_color_<…>_text`，值為 `#RRGGBB` 大寫字串；還原時 `remove(key)`。讀到格式不合的字串當作沒設定，不崩潰。
- **E-Ink 不套用**：`isEinkMode == true` 時 `ReaderScreen` 不疊自訂色；「佈景」分頁仍顯示，但整頁停用並顯示說明。
- **只影響閱讀器頁面**：不得修改全域 `ThemeData`／`scaffoldBackgroundColor`；浮動按鈕（`_themedFabBackgroundColor`、`_themedFabForegroundColor`）維持跟佈景走。
- **套用範圍**：送進 `FoliateReaderView` 的 `textColor`／`backgroundColor`、頁首／頁尾文字（已用 `_themedTextColor`）、WebView 載入遮罩（`reader_render_placeholder_background`）。固定版面（`_isFixedLayout`）與 PDF 維持不套用：自訂色只在 `isFoliateFormat(format) && !_isFixedLayout` 時疊加（`_isFixedLayout` 對 PDF 預設是 `false`，不能只靠它判斷；審查 I-4）。PDF 的載入遮罩顏色必須維持 `scaffoldBackgroundColor`（既有 `reader_screen_test.dart` 約 8295 行斷言）。
- **無效色碼**：輸入框標紅、不套用、不寫入偏好；已套用的顏色維持上一個有效值。
- **對比警告**：以 WCAG 對比公式，有效背景色與有效文字色（沒設定的那邊用佈景原色）對比低於 3.0 時顯示警告文字，仍然套用。
- **新增建構參數一律有預設值**，避免大量既有測試改動：`ReaderScreen.appTheme` 預設 `AppTheme.light`；`ReaderSettingsSheet` 的 `appTheme`、`readerColors`、`onReaderColorsChanged` 皆有預設；`ReaderFeatureDependencies.readerColorPreferences` 預設 `ReaderColorPreferences()`（因此 `main.dart` 與 `fakeReaderFeatureDependencies` 都不必改）。
- **l10n**：新字串同時加進 4 個 `.arb`（`app_en`、`app_zh`、`app_zh_CN` 簡體、`app_zh_TW`），執行 `flutter gen-l10n`，生成檔進版控；佈景名稱重用既有 `settingsThemeLight`／`settingsThemeDark`／`settingsThemeSepia`；不得硬編碼中文。
- **不升級 SQLite、不動 `BookReaderPrefs`、不動版面預設集**。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，只跑一個）。
- **每個 Task／commit 結束都必須可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**。
- **提交前**：`flutter analyze` 必須 "No issues found!"；先 `node --version`。本機 Node 若仍未安裝，`node tool/check_l10n_hardcoded_strings.js` 與 `node tool/check_integration_keys.js` 無法執行，記錄為「未執行」並在 `epic.md` 寫清風險（本張新增使用者可見字串與 Key）。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔；不要對整個既有檔案跑 `dart format`；`git add` 一律明確列檔，**不得** `git add app`（會夾帶使用者擱置的 `app/android/gradle.properties`）。
- **Commit**：不加 `Co-Authored-By`；結尾加 `Claude-Session: https://claude.ai/code/session_019bmfxQJ1gaKoHGoWH7gJwD`。每個 Task 一個 commit。
- **不要提交** `app/android/gradle.properties`。
- **計畫與實作同分支同 PR**，不另開文件分支。

## Review Focus

1. **E-Ink 與 FXL 洩漏。** 自訂色不得在 E-Ink 或固定版面生效。→ `ReaderScreen` 測試各一個案例，且確認 `FoliateReaderView.textColor`／`backgroundColor` 的實際值。
2. **全域主題被污染。** 不得改 `Theme.of(context).scaffoldBackgroundColor`。→ 測試：自訂背景後，載入遮罩以外的畫面（例如 `ReaderScreen` 之外的 `Scaffold`）顏色不變；程式碼不動 `ThemeData`。
3. **`null` 與還原。** 還原只清一個顏色，另一個保留；清掉後必須真的 `remove` key，下次啟動不能殘留。→ 偏好測試與面板測試。
4. **佈景對應錯誤。** 淺色的自訂色不得出現在深色。→ 偏好測試（三個佈景互不影響）與 `ReaderScreen` 以不同 `appTheme` 開啟的測試。
5. **非同步載入閃爍。** 自訂色是非同步讀出，書頁可能先用佈景原色畫出再跳成自訂色。→ 計畫處理：`ReaderScreen` 在顏色載入完成前，沿用既有載入遮罩／開書流程等待（見 Task 2 Step 3 的取捨），並在 WAVE 實測確認無明顯閃爍。
6. **分頁數量變動。** 分頁從 4 個變 5 個，既有測試若假設 4 個或用索引取分頁會壞。→ Task 3 先全域搜尋 `reader_settings_tab_` 與 `length: 4`，逐一確認。
7. **滑桿與色碼輸入互相覆寫。** 輸入框打到一半（例如 `#12`）不能把滑桿重設，也不能被滑桿的更新蓋掉正在輸入的文字。→ 面板測試：打字過程中滑桿位置不變、輸入完整有效色碼後滑桿同步。
8. **對比警告基準。** 只設了其中一色時，另一色要用佈景原色計算。→ 純函式測試與面板測試。
9. **PDF 洩漏自訂色。** PDF 的 `_isFixedLayout` 預設為 `false`，只用它判斷會讓 PDF 載入遮罩吃到 Foliate 的自訂背景。→ `ReaderScreen` 測試：PDF 載入遮罩仍等於 `scaffoldBackgroundColor`（審查 I-4）。
10. **搜尋路徑的佈景傳遞。** 從全庫搜尋、單書搜尋開書時，`appTheme` 必須一路傳到 `ReaderScreen`，否則深色／羊皮紙使用者會吃到淺色的自訂色。→ 逐個呼叫端確認，並各補一個「傳入深色，開書後吃到深色自訂色」的測試（審查 I-1）。
11. **不可逆決策：頁籤不得抽成獨立 `StatefulWidget`。** 色碼控制器與錯誤狀態留在 `_ReaderSettingsSheetState`，並在 `dispose()` 釋放（審查 I-3）。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/theme/reader_colors.dart` | 新增 | `ReaderColors` 值物件、`parseHexColor`、`formatHexColor`、`contrastRatio` |
| `app/lib/theme/reader_color_preferences.dart` | 新增 | `ReaderColorPreferences`：`load(AppTheme)`／`save(AppTheme, ReaderColors)` |
| `app/lib/screens/reader_feature_dependencies.dart` | 修改 | 新欄位 `readerColorPreferences`（有預設值） |
| `app/lib/screens/reader_screen.dart` | 修改 | `appTheme` 參數、載入自訂色、疊色、遮罩、傳給面板、儲存 |
| `app/lib/screens/reader_screen_route.dart` | 修改 | `buildReaderScreen` 新增 `appTheme` 並轉傳 |
| `app/lib/screens/library_screen.dart` | 修改 | 開書（約 444 行）與推入 `LibrarySearchScreen`（約 833 行）時帶入 `widget.appearance.currentTheme` |
| `app/lib/screens/library_search_screen.dart` | 修改 | 新增 `appTheme` 參數（預設 `AppTheme.light`）；開書（約 167 行）與推入 `BookSearchScreen`（約 390 行）時轉傳 |
| `app/lib/screens/book_search_screen.dart` | 修改 | 新增 `appTheme` 參數（預設 `AppTheme.light`）；開書（約 172 行）時轉傳 |
| `app/lib/screens/reader_settings_sheet.dart` | 修改 | 第 5 個分頁「佈景」 |
| `app/lib/l10n/*.arb` 與生成檔 | 修改／重新產生 | 新字串 |
| `app/test/theme/reader_colors_test.dart` | 新增 | 色碼解析、格式化、對比 |
| `app/test/theme/reader_color_preferences_test.dart` | 新增 | 儲存、讀回、獨立、還原、壞資料 |
| `app/test/screens/reader_settings_sheet_test.dart`、`app/test/screens/reader_screen_*_test.dart` | 修改 | 見各 Task |
| `CONTEXT.md` | 不動 | 詞條「自訂閱讀顏色」已存在 |

---

## Task 1：顏色值物件與偏好儲存（純 Dart）

**Files:** 新增 `app/lib/theme/reader_colors.dart`、`app/lib/theme/reader_color_preferences.dart`、`app/test/theme/reader_colors_test.dart`、`app/test/theme/reader_color_preferences_test.dart`

**Interfaces — Produces：**

```dart
class ReaderColors {
  final Color? background;
  final Color? text;
  const ReaderColors({this.background, this.text});
  static const ReaderColors empty = ReaderColors();
  ReaderColors withBackground(Color? c);   // 傳 null 即清除
  ReaderColors withText(Color? c);
  // ==、hashCode
}
Color? parseHexColor(String input);        // 接受 "#RRGGBB"（大小寫）；其他一律回傳 null
String formatHexColor(Color c);            // "#RRGGBB" 大寫
double contrastRatio(Color a, Color b);    // WCAG：(L1+0.05)/(L2+0.05)，L1 較亮

class ReaderColorPreferences {
  const ReaderColorPreferences();
  Future<ReaderColors> load(AppTheme theme);
  Future<void> save(AppTheme theme, ReaderColors colors); // null 欄位 → remove key
}
```

- [x] **Step 1：寫失敗測試（色碼與對比）。** `reader_colors_test.dart`：`parseHexColor('#FFFFFF')` 得 `Color(0xFFFFFFFF)`；小寫 `#ff8800` 可解析；`'FFFFFF'`（缺 `#`）、`'#FFF'`、`'#GGGGGG'`、`''`、`'#FFFFFFF'` 皆回 `null`；`formatHexColor(Color(0xFF0A0B0C))` 為 `'#0A0B0C'`（補前導零）；`contrastRatio(白, 黑)` ≈ 21、`contrastRatio(白, 白)` = 1、參數順序對調結果相同；`ReaderColors.withBackground(null)` 清掉背景但保留文字。
- [x] **Step 2：** `flutter test test/theme/reader_colors_test.dart`。Expected：FAIL（檔案不存在）。
- [x] **Step 3：實作 `reader_colors.dart`。** 只含純函式與值物件，不 import `package:flutter/material.dart` 以外的東西（用 `dart:ui` 的 `Color` 即可）。
- [x] **Step 4：** 同一指令。Expected：PASS。
- [x] **Step 5：寫失敗測試（偏好）。** `reader_color_preferences_test.dart`（`SharedPreferences.setMockInitialValues({})`）：沒存過 → `load` 回 `ReaderColors.empty`；存背景後讀回相同；只存背景時文字為 `null`；淺色存的值不影響深色與羊皮紙；存 `ReaderColors.empty`（或把某欄位設 `null`）後該 key 確實不存在（`prefs.containsKey` 為 false）；預先塞 `reader_color_light_background: 'zzz'` 時 `load` 回 `null` 欄位、不崩潰。
- [x] **Step 6：** `flutter test test/theme/reader_color_preferences_test.dart`。Expected：FAIL。
- [x] **Step 7：實作 `reader_color_preferences.dart`。** key 用 `AppTheme.name` 組成；寫入用 `formatHexColor`、讀出用 `parseHexColor`。
- [x] **Step 8：** 兩個測試檔都跑。Expected：PASS。`flutter analyze` 乾淨。
- [x] **Step 9：Commit。** `git add` 四個檔案，訊息：`feat(reader): 自訂閱讀顏色的值物件與偏好儲存（epic-65 Issue 2 Task 1）`。

---

## Task 2：`ReaderScreen` 套用自訂色

**Files:** 修改 `reader_feature_dependencies.dart`、`reader_screen.dart`、`reader_screen_route.dart`、`library_screen.dart`、`book_search_screen.dart`、`library_search_screen.dart`（只有 `LibraryScreen` 持有 `appearance`，另外兩個搜尋畫面要新增 `appTheme` 參數，見審查 I-1）；測試新增 `app/test/screens/reader_screen_custom_colors_test.dart`（沿用既有 `reader_screen_*_test.dart` 的建構方式，先 `Grep` 找一個用 `FakeReaderSurface` 的現成測試當樣板）

**Interfaces — Consumes：** Task 1 的 `ReaderColors`、`ReaderColorPreferences`。**Produces：** `ReaderScreen.appTheme`（`AppTheme`，預設 `AppTheme.light`）；`buildReaderScreen(appTheme:)`；`ReaderFeatureDependencies.readerColorPreferences`。

- [x] **Step 1：確認樣板。** `Grep` `ReaderSettingsSheet(` 與 `FoliateReaderView(` 在 `test/screens/` 的用法，決定如何讀到送進 `FoliateReaderView` 的 `textColor`／`backgroundColor`（現有測試若已有讀取方式就沿用）。以 `reader_screen_surface_test.dart:28-38` 為樣板：`setUp` 要 mock `elinkbook/fullscreen` 與 `elinkbook/volume_key` 兩個 MethodChannel，否則會噴 `MissingPluginException`；顏色是非同步載入，`pumpWidget` 後要補 `await tester.pump(); await tester.runAsync(() => Future.delayed(Duration.zero)); await tester.pump();`（審查 M-1）。
- [x] **Step 2：寫失敗測試。** 預先 `setMockInitialValues` 塞淺色自訂色，開啟 `ReaderScreen(appTheme: AppTheme.light, isEinkMode: false)`：
  - `FoliateReaderView.backgroundColor` 與 `.textColor` 等於自訂色。
  - 只設背景時，文字色仍是 `colorScheme.onSurface`。
  - `appTheme: AppTheme.dark` 時不吃淺色的自訂色。
  - `isEinkMode: true` 時兩者都是 E-Ink 主題色（不是自訂色）。
  - `isFixedLayout: true` 時兩者為 `null`。
  - 頁首／頁尾文字顏色等於自訂文字色。
  - 載入遮罩 `reader_render_placeholder_background` 的 `ColoredBox.color` 等於自訂背景色（Foliate 流式、非 E-Ink）。
  - **PDF**（`.pdf` 路徑，預設 `_isFixedLayout == false`）：載入遮罩顏色仍等於 `scaffoldBackgroundColor`，不吃自訂色（審查 I-4）。
  - 全域 `Theme.of(context).scaffoldBackgroundColor` 不變。
  - `appTheme` 變更：同一個 `ReaderScreen` 以不同 `appTheme` 重建後，顏色改讀新佈景（審查 M-4）。
  - 搜尋路徑（審查 I-1）：`LibrarySearchScreen(appTheme: AppTheme.dark)` 與 `BookSearchScreen(appTheme: AppTheme.dark)` 開書後，傳給 `ReaderScreen` 的 `appTheme` 是 `dark`；`ReaderScreen` 推入 `BookSearchScreen` 時轉傳自己的 `appTheme`（各補一個案例，樣板見 `book_search_screen_test.dart`、`library_search_screen_test.dart`）。
- [x] **Step 3：** 執行該測試檔。Expected：FAIL。
- [x] **Step 4：實作。**
  1. `ReaderFeatureDependencies` 新增 `final ReaderColorPreferences readerColorPreferences;`，建構子 `this.readerColorPreferences = const ReaderColorPreferences()`。
  2. `ReaderScreen` 新增 `final AppTheme appTheme;`（預設 `AppTheme.light`）；`buildReaderScreen` 新增 `AppTheme appTheme = AppTheme.light` 並轉傳。呼叫端（審查 I-1，只有 `LibraryScreen` 持有 `appearance`）：
     - `LibraryScreen`：開書（約 444 行）與推入 `LibrarySearchScreen`（約 833 行）傳 `widget.appearance.currentTheme`。
     - `LibrarySearchScreen`、`BookSearchScreen`：各新增 `final AppTheme appTheme;`（預設 `AppTheme.light`，既有測試不受影響）；`LibrarySearchScreen` 開書（約 167 行）與推入 `BookSearchScreen`（約 390 行）傳 `widget.appTheme`；`BookSearchScreen` 開書（約 172 行）傳 `widget.appTheme`。
     - `ReaderScreen` 推入 `BookSearchScreen`（約 1437 行）傳 `widget.appTheme`。
  3. `_ReaderScreenState` 新增 `ReaderColors _readerColors = ReaderColors.empty;`，`initState` 以 `unawaited(_loadReaderColors())` 讀入，完成且 `mounted` 時 `setState`。**取捨（Review Focus 5）：** 不另外擋住開書流程；書頁先用佈景原色，讀完（一般在幾十毫秒內）再更新，由 `didUpdateWidget` 觸發 `setStyles`。WAVE 實測若有明顯閃爍，再改成在載入遮罩期間等待顏色讀完。
  4. `_themedTextColor`／`_themedBackgroundColor` 改為：固定版面回傳 `null`；E-Ink 模式回傳原本的 Theme 值；**非 Foliate 格式（PDF）也只回傳原本的 Theme值，不疊自訂色**（審查 I-4，判斷用 `isFoliateFormat(detectBookFormat(widget.filePath))`，與 `build()` 內既有的 `format` 同一來源）；其餘 `(_readerColors.text ?? Theme 值)`。
  5. 載入遮罩的 `color` 改為：Foliate 流式且非 E-Ink 時用 `_themedBackgroundColor`，否則維持 `Theme.of(context).scaffoldBackgroundColor`。
  6. 新增 `didUpdateWidget`（`ReaderScreen` 目前沒有）：`widget.appTheme != oldWidget.appTheme` 時 `unawaited(_loadReaderColors())`（審查 M-4）。
- [x] **Step 5：** 執行該測試檔。Expected：PASS。再跑 `flutter test test/screens/reader_screen_route_test.dart`（若檔案不存在，改跑 `Grep buildReaderScreen test/` 找到的測試檔）確認三個呼叫端與既有測試沒壞。
- [x] **Step 6：** `flutter analyze` 乾淨。
- [x] **Step 7：Commit。** 明確列檔，訊息：`feat(reader): 閱讀器套用各佈景自訂的背景色與文字色（epic-65 Issue 2 Task 2）`。

---

## Task 3：設定面板「佈景」分頁

**Files:** 修改 `reader_settings_sheet.dart`、`reader_screen.dart`（開面板處傳參數）、4 個 `.arb` 與生成檔；測試修改 `test/screens/reader_settings_sheet_test.dart`

**Interfaces — Consumes：** Task 1 的 `ReaderColors`、`parseHexColor`、`formatHexColor`、`contrastRatio`。**Produces：** `ReaderSettingsSheet` 新增 `appTheme`（預設 `AppTheme.light`）、`readerColors`（預設 `ReaderColors.empty`）、`onReaderColorsChanged`（`ValueChanged<ReaderColors>?`，預設 `null`）。

**新字串（key 與 zh-TW 文案，其他語言照譯）：**

| key | zh-TW |
|---|---|
| `readerSettingsTabTheme` | 佈景 |
| `readerColorsEditingTheme` | 正在調整：{themeName} |
| `readerColorsEinkDisabledHint` | E-Ink 高對比模式不套用自訂顏色 |
| `readerColorsBackgroundLabel` | 背景色 |
| `readerColorsTextLabel` | 文字色 |
| `readerColorsRed` / `readerColorsGreen` / `readerColorsBlue` | 紅 / 綠 / 藍 |
| `readerColorsHexLabel` | 色碼 |
| `readerColorsHexInvalid` | 色碼格式錯誤，請輸入 #RRGGBB |
| `readerColorsLowContrastWarning` | 文字色與背景色太接近，可能難以閱讀 |
| `readerColorsResetBackground` | 還原背景色 |
| `readerColorsResetText` | 還原文字色 |

`readerColorsEditingTheme` 帶參數，`app_zh_TW.arb` 的 `@readerColorsEditingTheme` 要比照 `@settingsThemeDotSemanticsLabel`（約 1680 行）寫 `description` 與 `placeholders: { "themeName": { "type": "String" } }`（審查 M-2）；其餘 3 個 `.arb` 比照各檔既有帶參數字串的寫法。

- [ ] **Step 1：全域搜尋分頁假設。** `Grep` `reader_settings_tab_`、`length: 4`、`readerSettingsTab` 在 `app/lib` 與 `app/test`，列出所有假設「4 個分頁」的地方（Review Focus 6），記入開發記錄。已知必改（審查 I-2）：
  - `reader_settings_sheet_test.dart:2418`「切換分頁沒有動畫」的陣列改為 `[('邊界', 1), ('呈現', 2), ('佈景', 3), ('預設集', 4), ('文字', 0)]`。
  - `reader_settings_sheet_test.dart:2472` 的分頁高度巡訪清單加入 `'佈景'`（新分頁高度也要受「面板高度不變」守衛）。
- [ ] **Step 2：寫失敗測試。** `reader_settings_sheet_test.dart` 新增（`Key` 命名：`reader_settings_tab_theme`、`reader_colors_background_hex`、`reader_colors_background_r/g/b`（滑桿 keyPrefix）、`reader_colors_text_*`、`reader_colors_background_reset`、`reader_colors_text_reset`、`reader_colors_low_contrast_warning`、`reader_colors_eink_hint`）：
  - 分頁順序為 文字｜邊界｜呈現｜佈景｜預設集，共 5 個。
  - 點「佈景」顯示「正在調整：羊皮紙」（傳 `appTheme: AppTheme.sepia`）。
  - 背景、文字兩個區塊都同時可見（不需展開）。
  - 沒設定時色碼框顯示佈景原色（以 `Theme` 值格式化）。
  - 拖動紅色滑桿 → 色碼框同步、`onReaderColorsChanged` 收到只改了背景的 `ReaderColors`。
  - 色碼框輸入 `#336699` → 三條滑桿同步為 51／102／153，回呼收到新色。
  - 輸入 `#12`（打到一半）→ 框標紅、無回呼、滑桿位置不變；再補成 `#123456` → 恢復並回呼。
  - 按「還原背景色」→ 回呼的 `background == null`、`text` 保持；按「還原文字色」同理。
  - 該顏色沒設定（`null`）時，對應的還原按鈕 `onPressed` 為 `null`（停用）；設定後啟用（審查 M-3）。
  - `didUpdateWidget`：外部傳入新的 `readerColors` 後，滑桿與色碼框同步更新（審查 I-3）。
  - 色碼控制器已釋放：面板移除後無例外（`dispose()` 有覆寫）。
  - 背景 `#FFFFFF`＋文字 `#EEEEEE` → 顯示低對比警告；改成 `#000000` → 警告消失。只設文字色時，背景用 `Theme.scaffoldBackgroundColor` 計算。
  - `isEinkMode: true` → 顯示 `reader_colors_eink_hint`，滑桿與輸入框不可操作（`enabled: false` / `IgnorePointer`），不呼叫回呼。
- [ ] **Step 3：** `flutter test test/screens/reader_settings_sheet_test.dart`。Expected：新案例 FAIL，既有案例照舊（若有因分頁數改變而壞的，依 Step 1 清單在同一步修正預期）。
- [ ] **Step 4：實作。**
  1. `.arb` 四檔新增字串，`flutter gen-l10n`。
  2. `DefaultTabController(length: 5)`；`TabBar` 在「呈現」後、「預設集」前加 `Tab(key: Key('reader_settings_tab_theme'), text: l10n.readerSettingsTabTheme)`；`IndexedStack` 依同順序加入 `_buildThemeColorsTab()`；更新「4 個 `_buildXxxTab()`」那段不可逆決策註解的數字與清單。
  3. State 新增 `late ReaderColors _readerColors`（`initState` 由 `widget.readerColors` 初始化）。
  4. `_buildThemeColorsTab()`：頂端「正在調整：{佈景名}」（佈景名用既有 `settingsThemeLight/Dark/Sepia`）；E-Ink 時加說明並以 `IgnorePointer`＋`Opacity` 整頁停用；背景、文字兩個區塊各用同一個輔助方法 `_buildColorEditor(...)`（色塊、R／G／B 三條 `_buildSliderRow`（min 0、max 255、step 1，顯示整數）、色碼 `TextField`＋錯誤文字、還原按鈕）。**它只是 `_ReaderSettingsSheetState` 的展示方法或純 `StatelessWidget`，不得是 `StatefulWidget`**（`reader_settings_sheet.dart:364` 的不可逆決策；審查 I-3）。還原按鈕在該顏色為 `null` 時 `onPressed: null`（審查 M-3）。
  5. 背景與文字的 `TextEditingController`（`_bgHexController`、`_textHexController`）與各自的錯誤狀態旗標定義在 `_ReaderSettingsSheetState` 根層級；`initState` 建立、**新增 `dispose()` 釋放兩個控制器**（目前此檔沒有 `dispose()`）。只有「使用者在框內輸入」時才解析並回推滑桿，「滑桿變動」時才改寫框內文字（避免互相覆寫，Review Focus 7）。既有 `didUpdateWidget`（約 163 行）補上：`widget.readerColors != oldWidget.readerColors` 時同步 `_readerColors` 與兩個控制器文字（審查 I-3）。
  6. 低對比警告用 `contrastRatio(有效背景, 有效文字) < 3.0` 判斷。
  7. 每次有效變動：更新 `_readerColors`、呼叫 `widget.onReaderColorsChanged?.call(_readerColors)`。
  8. `ReaderScreen` 開面板處傳入 `appTheme: widget.appTheme`、`readerColors: _readerColors`、`onReaderColorsChanged: _handleReaderColorsChanged`；後者 `setState(() => _readerColors = c)` 並 `unawaited(widget.dependencies.readerColorPreferences.save(widget.appTheme, c))`。
- [ ] **Step 5：** 執行 `reader_settings_sheet_test.dart`。Expected：全部 PASS。另外在 `reader_screen_custom_colors_test.dart` 補一個案例：開面板改背景色 → `FoliateReaderView.backgroundColor` 立刻更新，且偏好已寫入（重新 `load` 讀回相同）。跑該檔 PASS。
- [ ] **Step 6：** `flutter analyze` 乾淨。
- [ ] **Step 7：Commit。** 明確列檔（含 4 個 `.arb` 與生成的 `app_localizations*.dart`），訊息：`feat(reader): 設定面板新增「佈景」分頁（epic-65 Issue 2 Task 3）`。

---

## Task 4：驗證與收尾

- [ ] **Step 1：** `node --version`。可執行就跑 `node tool/check_l10n_hardcoded_strings.js` 與 `node tool/check_integration_keys.js`；不可執行就在 `epic.md` 開發記錄註明「未執行」與風險。
- [ ] **Step 2：** 背景執行一次完整 `flutter test`（`run_in_background`，只跑一個）；已知 `test/reader/pdf_reader_view_filters_test.dart` 的加粗案例偶發失敗，單跑通過即可記為既有不穩。
- [ ] **Step 3：** `flutter analyze` 乾淨。
- [ ] **Step 4：更新文件。** `epic.md` 補 Issue 2 開發記錄（實作、驗證結果、未執行項目）；`issues.md` Issue 2 狀態改「✅ 實作完成，待真機」；`docs/epics.md` 備註同步；本計畫勾選完成的步驟。
- [ ] **Step 5：Commit。** 訊息：`docs(epic-65): Issue 2 自訂閱讀顏色驗證與收尾（Issue 2 Task 4）`。
- [ ] **Step 6：WAVE 真機抽驗**（`flutter build apk --debug`，`adb -s TCE70P24B2202374 install -r build/app/outputs/flutter-apk/app-debug.apk`，由使用者操作）：
  1. 淺色佈景：背景改純白、文字改深灰，內文、頁首、頁尾、翻頁時的載入畫面都一致，沒有明顯閃一下原色。
  2. 深色與羊皮紙各自設不同顏色，切換佈景後各自保留。
  3. 重新開啟 App 與重新開書，顏色仍在。
  4. 設成白底白字：出現低對比警告但仍套用；按「還原」恢復。
  5. 書庫、設定頁背景不受影響。
  6. 開啟 E-Ink 高對比：閱讀器是黑白，「佈景」分頁停用並有說明。
  7. 固定版面（漫畫）書與 PDF：顏色不變，PDF 設定面板沒有「佈景」分頁。
  8. 直排與橫排書各確認一次顏色都生效。
- [ ] **Step 7：** 使用者回「OK」後 `git push`，用 `tea` 開 PR（流程同前幾張 Issue）。
