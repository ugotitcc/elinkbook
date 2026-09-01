# Epic 35 — 設計系統 Token 落地：Discovery

## 緣起與範圍界定

`DESIGN.md`（依 `docs/research/uiux/elinkBook-uiux-audit.dc.html` 第 5～8 節與 `/grill-with-docs` 定案）已完整定義三主題（Light 晴空藍天／Dark 夜讀水墨／Sepia 宣紙古風）＋ E-Ink 修飾子的完整 M3 `ColorScheme` 與 `ElinkTokens` 語意色，但這份規範尚未落地到 Flutter 程式碼。本 Epic 的唯一目標：**讓 `DESIGN.md` §1 的色彩 Token 系統在程式碼裡變成真的**，做為 `epic-36-adaptive-shelf-navigation`（三目的地導覽／書架/設定重構）的地基，先行獨立完成、獨立驗收。

依循 `UI_DESIGN_RULES.md`：本 Epic 只碰 Theme／Design tokens，不碰任何「核心架構」清單（EPUB 解析、foliate-js、CFI、JS bridge、TTS/Read-along 同步、PocketBase 同步、OPDS/WebDAV/雲端來源實作、書籍儲存、閱讀進度持久化）。每個 Issue 的 `plan-issue-N.md` 動手改程式碼前，須先說明：(1) 改哪個 UI 元件 (2) 為什麼要改 (3) 哪些畫面依賴它 (4) 是否影響 business logic——不影響則明確寫「不影響」。

## 現有程式碼盤點（比預期範圍小很多）

查 `app/lib/theme/` 與 `app/lib/screens/settings_screen.dart` 發現：主題切換的 UI／持久化／E-Ink 鎖定行為**已經存在且可運作**，不是從零蓋：

- `AppThemePreferences`（`app_theme_preferences.dart`）：已用 `shared_preferences` 持久化 `AppTheme`（enum：light/dark/sepia）與 `isEinkMode`（bool）。
- `resolveThemeData({theme, isEinkMode})`（`app_theme_data.dart`）：已實作「`isEinkMode` 為 true 時無條件套用純黑白 `_buildEinkTheme()`，不論 `theme` 為何」——這正是 `DESIGN.md` 核心原則第 2 條「E-Ink 是修飾子，不是第四個主題」的既有實作，不用重寫。但 `_buildEinkTheme()` 除了色值角色，還額外設定了三個非色值屬性（`splashFactory: NoSplash.splashFactory`／`hoverColor: Colors.transparent`／`highlightColor: Colors.transparent`，`app_theme_data.dart:148-150`），對應 `DESIGN.md` §7.2／§18 的 E-Ink 防殘影要求——重構時**必須保留**這三行，只對齊色值角色的話會不小心遺失。
- `settings_screen.dart` 的「佈景」選擇圓點（`_buildThemeDot()`）：`isEinkMode` 為 true 時已經 `onTap: null` ＋ `opacity: 0.4`（`settings_screen.dart:237`）——跟這次 `DESIGN.md` §17.2 新寫的「E-Ink 開啟時主題選擇器鎖住」規格一半對得上：**鎖住**（`onTap: null`）已經做到了，但 `opacity(0.4)` 這個視覺手法**必須改**——`DESIGN.md` §17.2 明確禁止「降低對比度或灰階效果」，`Opacity(0.4)` 正是這條規則要禁止的做法，不是「建議改」而是**現行實作已經違反 `DESIGN.md` 自己剛寫的規則**，須改為 §17.2 指定的邊框加粗虛線手法。

## 真正缺的三件事

1. **色值不符** `_buildLightTheme()`/`_buildSepiaTheme()` 目前用 `ColorScheme.light()` 只填 `primary`/`surface`/`onSurface`/`outline` **四個角色**；`_buildDarkTheme()` 用 `ColorScheme.dark()` 填了**五個角色**（多一個 `surfaceContainerHighest`，`app_theme_data.dart:85-91`）。其餘角色（`onPrimary`／`primaryContainer`／`onPrimaryContainer`／`onSurfaceVariant`／`scaffoldBackground`／`error`）留給 M3 預設值，正是 `DESIGN.md` 開頭所述「羊皮紙主題下 Material 3 預設淡紫外洩」問題的程式碼本體——現行 Light 主色 `#8B5CF6`（紫）也不是 `DESIGN.md` 指定的 `#0284c7`（天空藍）。另外 `scaffoldBackgroundColor` 是各 `ThemeData` 建構式直接設定的獨立屬性（非 `ColorScheme` 角色，`app_theme_data.dart:54/96/120`），現行值（Light `#F8F8FA`／Dark `#121214`）也都跟 `DESIGN.md` §1.1 表格的 `scaffoldBackground` 欄位（`#f0f6fc`／`#141416`）不同，需要一併對齊；Light `onSurface` 現行 `#1A1A2E` 與 `DESIGN.md` 指定 `#0f172a` 亦有差異。**Dark 主題的 `outline`／`surfaceContainerHighest` 兩個角色需要特別處理，見下方「已知風險」，不能直接套 `DESIGN.md` 表格值。**
2. **`ElinkTokens` 不存在** `DESIGN.md` §1.2 已經寫好完整的 Dart 類別骨架（`highlightYellow`／`highlightGreen`／`highlightBlue`／`underlineColor`／`progressTrack`／`coverPlaceholder`／`badgeScrim`／`ttsActiveHighlight`／`isEink`／`reducedMotion`／`discretePaging`），需要建成真正的 `ThemeExtension<ElinkTokens>` 子類別，掛進 `resolveThemeData()` 回傳的 `ThemeData.extensions`。`app/lib/reader/highlight_style.dart` 目前寫死的 `highlighterYellowTint`／`highlighterPinkTint`／`highlighterBlueTint` 三色是這組 Token 的直接前身，需要遷移為由 `ElinkTokens` 驅動；**注意 `DESIGN.md` 用綠色（`highlightGreen`）取代了現行的粉紅色（`highlighterPinkTint`），這是語意變更，不是單純換色值**，實作時需確認這個變更是刻意的。
3. **至少 13 個檔案的寫死顏色** 原始盤點列出 8 個檔案（`book_cover.dart`／`foliate_reader_view.dart`／`pdf_reader_view.dart`／`layout_preset_book_picker_screen.dart`／`library_screen.dart`／`nav_zone_settings_screen.dart`／`reader_screen.dart`／`settings_screen.dart`），經審查交叉比對 grep 結果，**遺漏至少 5 個**：`notes_bottom_sheet.dart`（`Colors.red` 刪除按鈕前景色，L349／L531）、`library_group_management_dialog.dart`（`Colors.red` 刪除文字色，L174）、`highlight_style.dart`（見上第 2 點）、`pdf_crop_frame_overlay.dart`（`Colors.black`／`Colors.white`／自訂綠色等，L19-232）、`txt_cover_generator.dart`（6 色寫死色盤，L36-41，**候選排除**——這是離線產生 TXT 書封面用的裝飾色盤，跟畫面色彩無關，不需要主題感知；Architecting 階段須明確確認排除理由是否成立，而非預設排除）。本 Epic 範圍**包含**清乾淨前 12 個檔案（使用者已確認：不要留給以後零星補，避免遺漏用途要回頭改），`txt_cover_generator.dart` 待 Architecting 確認是否納入；**不**擴大搜尋到這份清單以外的全專案。

## 已知風險：`DESIGN.md` 色值與電子紙硬體實測值衝突（Architecting 階段須優先定論）

Dark 主題的兩個角色，現行值不是隨便選的，是**真機電子紙硬體肉眼實測**調校出來的，且 `test/theme/app_theme_data_test.dart` 已有專門的感知亮度差斷言把這兩個值鎖住：

- **`outline`**：現行 `#86868F`（`app_theme_data.dart:74`，附 10 行實測過程註解：`#2A2A30`→`#5C5C66`→`#86868F` 逐步調亮），`DESIGN.md` §1.1 指定 `#2c2c34`——比現行值暗得多。`app_theme_data_test.dart:59-78` 斷言 `outline` 與 `surface` 的感知亮度差需 `> 0.15`（現行值實測約 0.41）；換成 `#2c2c34` 對 `surface #1E1E22` 的亮度差僅約 0.06，**這個測試會直接失敗**，且 Switch 等元件的關閉狀態邊框會在電子紙上重新變得不可辨識（這正是當初調校這個值想解決的問題）。
- **`surfaceContainerHighest`**：現行 `#3C3C44`（`app_theme_data.dart:83`，附 8 行實測過程註解），`DESIGN.md` §1.1 指定 `#19191d`。`app_theme_data_test.dart:89-110` 斷言與 `surface` 的感知亮度差需 `> 0.10`（現行值實測約 0.119）；換成 `#19191d` 亮度差會大幅縮小，同樣有失敗風險，且 Switch 關閉狀態軌道會重新跟背景幾乎同色。

這不是「哪個對哪個錯」的問題，是**兩份文件在同一件事上給了不同答案**：`DESIGN.md` 給的是配色系統一致性的理想值，現行程式碼給的是真機電子紙裝置上驗證過「東西看得見」的實測值。直接二選一都有代價：照 `DESIGN.md` 值會讓已知修好的可辨識度問題復發；維持實測值則 Dark 主題的 `outline`／`surfaceContainerHighest` 會跟 `DESIGN.md` 色票表不一致。

**這個決策留給 Architecting 階段（`spec.md`）明確定論，不在本文件先下結論**——需要人類確認要選哪一條路：(a) 維持實測值，回頭在 `DESIGN.md` §1.1 表格這兩格加註「電子紙適配修正值，優先於配色系統一致性」；(b) 採用 `DESIGN.md` 值，同步想辦法讓 Switch 等元件用別的手法（例如強制邊框）維持電子紙可辨識度；(c) 其他方案。

## 其他待 Architecting 決定的小項

- `_buildEinkTheme()` 額外設定 `secondary: Colors.black`／`onSecondary: Colors.white`（`app_theme_data.dart:131-132`），`DESIGN.md` §1.1 表格沒有列這兩個角色——移除回退 M3 預設，還是補進 `DESIGN.md`，待決定。
- 四個 `_build*Theme()` 都直接設定了 `ThemeData.cardColor`／`ThemeData.dividerColor`（Material 2 遺留屬性，M3 下已被 `ColorScheme.surface`／`ColorScheme.outline`取代，例如 `app_theme_data.dart:55-56`）——若只對齊 `ColorScheme` 而不清掉這兩個直接設定，會殘留不一致。建議一併清理（只在 `app_theme_data.dart` 一個檔案，範圍不大），最終由 Architecting 定案是否納入本 Epic。

## 下一步

Architecting：撰寫 `spec.md`，**優先解決上方「已知風險」的色值衝突**，再把 `DESIGN.md` §1.2 的 `ElinkTokens` 骨架定為正式介面（欄位型別、`copyWith`/`lerp` 簽章），並定義 `resolveThemeData()` 銜接 `ElinkTokens` 的確切方式（四套 `ColorScheme` 各自搭配哪一組 `ElinkTokens` 實例、E-Ink 覆寫規則、`cardColor`/`dividerColor`/`secondary` 等遺留與額外角色的去留）。完成後進 Scrum Master 階段拆 `issues.md`，粗估切法：Issue 1（`ElinkTokens` 類別本體＋單元測試）、Issue 2（三主題＋E-Ink 四套 `ColorScheme` 對齊 `DESIGN.md` 色表，含 Dark 衝突角色的定案值、`scaffoldBackgroundColor`、`_buildEinkTheme()` 的 `splashFactory`/`hoverColor`/`highlightColor` 保留、同步更新 `app_theme_data_test.dart` 使其斷言新色值並保留亮度差門檻測試的精神）、Issue 3（`settings_screen.dart` 的 E-Ink 鎖定視覺從 `Opacity(0.4)` 改為邊框加粗虛線）、Issue 4～N（其餘 11 個檔案逐一或分組替換寫死顏色，含 `highlight_style.dart` 的粉紅→綠色語意變更確認、`txt_cover_generator.dart` 排除與否的定案，皆含既有測試回歸確認）。
