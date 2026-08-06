# Epic 22 Issue 4 — 深色主題下設定面板 Toggle 開關對比不足 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 深色主題（`AppTheme.dark`）的 `colorScheme.outline` 色值從目前與 `background`/`surface` 亮度幾乎無法區分的 `#2A2A30`，調整為有明顯可辨識對比的新色值，讓 `SwitchListTile` 等使用 `outline` 角色的 Material 元件（例如版面設定面板的 Toggle 開關關閉狀態外框）在深色主題下清楚可辨識。

**Architecture:** `app/lib/theme/app_theme_data.dart` 的 `_buildDarkTheme()` 目前用同一個本地常數 `border` 同時餵給 `ColorScheme.dark(outline: border)` 與 `ThemeData(dividerColor: border)`——這是本檔案既有設計（單一色票同時代表 outline 語意與分隔線語意），本次調整直接改這一個常數值，兩個消費端（`Switch` 對比不足、`nav_zone_settings_screen.dart` 分隔線同樣過於不明顯）一併受惠，不需要拆成兩個獨立色票。只改這一個檔案，不涉及任何呼叫端程式碼（`ReaderSettingsSheet` 的 `SwitchListTile` 是標準 Flutter 元件，本身沒有寫死顏色，自動吃到新色值）。

**Tech Stack:** Flutter/Dart（`app/lib/theme/app_theme_data.dart`）。

## Global Constraints

- 只修改 `app/lib/theme/app_theme_data.dart` 的 `_buildDarkTheme()`——不修改 `_buildLightTheme()`／`_buildSepiaTheme()`／`_buildEinkTheme()`（這三者的 `outline`/`border` 皆是淺色背景，既有對比已足夠，非本 Issue 範圍）。
- 不修改 `ReaderSettingsSheet`／`nav_zone_settings_screen.dart` 等任何呼叫端——本次修法純粹是色票數值調整，Material `Switch`／`Divider` 等元件本身已正確吃 `Theme.of(context)`，無需額外接線。
- 新色值須有可驗證、非拍腦袋的最低對比保證——用簡化版感知亮度公式（`0.299R + 0.587G + 0.114B`，`R`/`G`/`B` 為 0.0–1.0 區間的 sRGB 分量）計算與 `surface`（`#1E1E22`）的亮度差，須明顯大於目前 `#2A2A30` 與 `surface` 幾乎為零的亮度差（≈0.048）。

---

## File Structure

- **Modify:** `app/lib/theme/app_theme_data.dart`（`_buildDarkTheme()` 的 `border` 常數值）
- **Test:** `app/test/theme/app_theme_data_test.dart`（既有檔案，`group('buildThemeData', ...)`）

---

### Task 1：調整深色主題 `outline`／`dividerColor` 色值並補上對比回歸測試

**Files:**
- Modify: `app/lib/theme/app_theme_data.dart`
- Test: `app/test/theme/app_theme_data_test.dart`

**Interfaces:**
- Consumes: 無新依賴。
- Produces: `buildThemeData(AppTheme.dark).colorScheme.outline` 與 `buildThemeData(AppTheme.dark).dividerColor` 回傳新色值 `Color(0xFF5C5C66)`（取代原本的 `Color(0xFF2A2A30)`）。

- [x] **Step 1: 在 `app_theme_data_test.dart` 新增對比回歸測試**

在既有 `group('buildThemeData', ...)` 區塊內、`test('sepia 主題使用淺色背景（羊皮紙色）', ...)` 之後，新增：

```dart

    test(
        'dark 主題的 outline 色與 surface 色有足夠感知亮度差，Switch 等元件'
        '關閉狀態外框在深色背景下清楚可辨識（epic-22-reader-theme-'
        'integration Issue 4：原色值 #2A2A30 與 surface #1E1E22 幾乎無法'
        '區分，對比嚴重不足）', () {
      final theme = buildThemeData(AppTheme.dark);
      final outline = theme.colorScheme.outline;
      final surface = theme.colorScheme.surface;

      double perceivedLuminance(Color c) =>
          0.299 * c.r + 0.587 * c.g + 0.114 * c.b;

      final luminanceDiff =
          (perceivedLuminance(outline) - perceivedLuminance(surface)).abs();

      // 舊色值（#2A2A30 對 #1E1E22）的亮度差約 0.048，明顯不足；新色值
      // 須顯著超過這個數字，門檻取 0.15（新色值實測約 0.246，留有餘裕）。
      expect(luminanceDiff, greaterThan(0.15));
    });

    test(
        'dark 主題的 dividerColor 與 outline 保持同一色值（本檔案既有設計：'
        '單一色票同時代表 outline 與分隔線語意）', () {
      final theme = buildThemeData(AppTheme.dark);
      expect(theme.dividerColor, theme.colorScheme.outline);
    });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/theme/app_theme_data_test.dart --plain-name "epic-22-reader-theme-integration Issue 4"`
Expected: 第一個測試 FAIL（目前 `outline` 仍是 `#2A2A30`，亮度差約 0.048，小於門檻 0.15）。第二個測試（`dividerColor` 與 `outline` 同值）預期本來就 PASS，是既有設計的回歸基準測試。

- [x] **Step 3: 調整 `_buildDarkTheme()` 的 `border` 常數**

在 `app/lib/theme/app_theme_data.dart` 找到：

```dart
ThemeData _buildDarkTheme() {
  const background = Color(0xFF121214);
  const surface = Color(0xFF1E1E22);
  const onSurface = Color(0xFFE8E8EC);
  const border = Color(0xFF2A2A30);
  const primary = Color(0xFFBB86FC);
```

改為：

```dart
ThemeData _buildDarkTheme() {
  const background = Color(0xFF121214);
  const surface = Color(0xFF1E1E22);
  const onSurface = Color(0xFFE8E8EC);
  // 【epic-22-reader-theme-integration Issue 4】原值 #2A2A30 與 surface
  // #1E1E22 亮度幾乎無法區分（感知亮度差僅約 0.048），導致 Switch 等
  // Material 元件關閉狀態外框（吃 colorScheme.outline）在深色主題下難以
  // 辨識。調整為亮度差約 0.246 的 #5C5C66，明顯可辨識但仍是低調的中灰
  // 色調、不搶過 onSurface 的視覺焦點，同時套用到 dividerColor（本檔案
  // 既有設計：單一色票同時代表 outline 與分隔線語意，見下方 dividerColor
  // 賦值處，一併受惠）。
  const border = Color(0xFF5C5C66);
  const primary = Color(0xFFBB86FC);
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/theme/app_theme_data_test.dart`
Expected: PASS，全部測試（含既有測試與本次新增測試）通過。

- [x] **Step 5: 執行完整 `app_theme_data_test.dart` 與相關既有測試確認零回歸**

Run: `flutter test test/theme/`
Expected: PASS，全數通過（含 `app_theme_preferences_test.dart`）。

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS，全數通過——本次改動的 `outline`/`dividerColor` 不影響任何既有斷言的 `onSurface`/`scaffoldBackgroundColor` 值（Issue 1/2/5 的測試皆比對這兩個欄位，與 `outline` 無關）。

- [x] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/theme/app_theme_data.dart app/test/theme/app_theme_data_test.dart
git commit -m "fix(epic-22): 深色主題 outline/dividerColor 色值對比不足，調整為可辨識色值"
```

---

### Task 2：全專案回歸測試 + 真機視覺確認

**Files:** 無新增/修改檔案，純驗證。

**Interfaces:** 無新增介面，驗證 Task 1 整合後的端到端行為。

- [x] **Step 1: 執行全專案 `flutter test`**

Run: `flutter test`
Expected: 全數通過，無任何回歸。

- [x] **Step 2: 執行全專案 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 3（建議）：真機/模擬器視覺確認**

本 Issue 是純色票數值調整，`flutter test` 已用感知亮度差驗證足夠對比，此步驟是建議而非強制，用於確認實際視覺觀感符合預期（而非只是數值上「差異夠大」）：

1. 深色主題下開啟「版面設定」面板，確認 Toggle 開關關閉狀態的外框清楚可見。
2. 確認 `nav_zone_settings_screen.dart` 的分隔線在深色主題下同樣變得可辨識（`dividerColor` 與 `outline` 同值，一併受惠）。
3. 確認新色值本身不會過於搶眼、破壞深色主題整體低調的視覺調性（純主觀視覺確認，若覺得不理想可微調 `#5C5C66` 這個數值，只要維持測試門檻 `luminanceDiff > 0.15` 即可）。

**結果：在一般 LCD/OLED 模擬器上確認達標，但人類在真正的電子紙（E-Ink）實體裝置上肉眼實測＋拍照後發現對比仍嚴重不足**（Switch 關閉狀態完全消失，FAB 圖示——Issue 3 已合併的既有問題——完全無法辨識形狀），見下方「電子紙硬體對比追加修正」。

- [x] **Step 4: Commit（若真機驗證過程中決定微調色值）**

若 Step 3 認為 `#5C5C66` 需要微調，重新走一次「改常數 → 重跑 Step 4-6 測試 → 確認仍通過既有門檻」，再另開一個 commit。若視覺確認滿意，本 Step 略過。

**結果：需要微調，見下方「電子紙硬體對比追加修正」一節，已另開 commit。**

---

## 電子紙硬體對比追加修正（同一分支延伸，未另立新 Issue）

**背景：** `/superpowers:requesting-code-review` 對本分支進行標準審查時，人類提供 4 張真機電子紙裝置照片（Switch 設定面板、FAB 按鈕，各自對照一般螢幕截圖版本），要求審查一併評估電子紙硬體對比是否足夠，並將 Issue 3 已合併的 FAB 顏色問題一併處理。完整審查報告：`tmp/epic-22/review-issue-4-implementation.md`。

**審查發現：**
- Issue 4 原本的 `outline` 調整（`#5C5C66`）本身程式碼合格、在一般顯示器上達標，但 Switch 關閉狀態在電子紙照片中完全消失——根因追查到 Flutter SDK 原始碼（`switch.dart`）：M3 `Switch` 關閉狀態同時吃 `outline`（外框線/圓鈕）與 `surfaceContainerHighest`（軌道底色），本專案的 `ColorScheme.dark(...)` 從未客製後者，隱性等於 `surface`，導致軌道底色與背景完全同色，只能靠一條 2dp 外框線撐可視度——這種「僅靠細線」的手法在電子紙灰階抖動渲染下結構性地不可靠。
- Issue 3（已合併）的 FAB 按鈕底色 `colorScheme.onSurface.withValues(alpha: 0.54)` 是半透明疊色，電子紙照片顯示圖示完全無法辨識——即時運算出的混合中間灰正好落在電子紙抖動演算法最弱的區間。

**人類決策：** 不另立新 Issue、不拆分 PR，直接在本分支（`fix/epic-22-issue4-outline-contrast`）擴大範圍一併修正；FAB 改用不透明實色的「近白底＋近黑圖示」方案（即拿掉 `.withValues(alpha: 0.54)`，底色改回不透明的 `colorScheme.onSurface` 原色，圖示 `colorScheme.surface` 不變）。

**追加修正內容：**

1. `app/lib/theme/app_theme_data.dart` `_buildDarkTheme()`：
   - `outline`（`border` 常數）從 `#5C5C66` 進一步調亮為 `#86868F`（對 `surface` 感知亮度差約 0.41，取代原本約 0.246）。
   - `ColorScheme.dark(...)` 新增 `surfaceContainerHighest: Color(0xFF3C3C44)`（原本未客製，隱性等於 `surface`；新值對 `surface` 感知亮度差約 0.119），讓 Switch 關閉狀態的軌道底色本身就是一塊與背景明顯不同的實心色塊。
2. `app/lib/screens/reader_screen.dart` `_themedFabBackgroundColor`：拿掉 `.withValues(alpha: 0.54)`，底色改為不透明的 `Theme.of(context).colorScheme.onSurface`（`_themedFabIconColor` 不變，仍是 `colorScheme.surface`）——此變動影響全部三個主題（light/dark/sepia），非僅深色主題，因為半透明疊色在電子紙上的結構性弱點與主題無關。
3. `app/test/theme/app_theme_data_test.dart`：新增 `surfaceContainerHighest` 對比回歸測試（門檻 `luminanceDiff > 0.10`），更新既有 `outline` 測試的說明註解反映新色值。
4. `app/test/screens/reader_screen_test.dart`：既有 3 個 Issue 3 FAB 測試斷言從 `.withValues(alpha: 0.54)` 改為不透明色值。

**驗證結果：** `flutter test test/theme/ test/screens/reader_screen_test.dart` 146 項全數通過；全專案 `flutter test` 1002/1002 全數通過；`flutter analyze` 乾淨。

**Commit（追加修正）：**

```bash
git add app/lib/theme/app_theme_data.dart app/lib/screens/reader_screen.dart app/test/theme/app_theme_data_test.dart app/test/screens/reader_screen_test.dart docs/epics/epic-22-reader-theme-integration/plans/plan-issue-4.md
git commit -m "fix(epic-22): 深色主題 Switch/FAB 電子紙硬體對比追加修正（Issue 3/4 一併處理）"
```
