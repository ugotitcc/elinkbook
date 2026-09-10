# Epic 35 — Issue 2：四套 `ColorScheme` 對齊 `DESIGN.md` §1.1＋YAGNI 清理＋電子紙可辨識度補強（Switch）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 把 `_buildLightTheme()`／`_buildDarkTheme()`／`_buildSepiaTheme()`／`_buildEinkTheme()`（`app/lib/theme/app_theme_data.dart`）四個函式的 `ColorScheme` 逐角色對齊 `DESIGN.md` §1.1 色表，各自掛上對應的 `ElinkTokens`（`DESIGN.md` §1.2），移除 `secondary`／`cardColor`／`dividerColor` 等 YAGNI 殘留，並新增 `SwitchThemeData` 把 Dark 主題色值衝突（`outline`／`surfaceContainerHighest`）造成的可辨識度風險，轉嫁到 `colorScheme.onSurface` 邊框補強機制上。

**Architecture:** `resolveThemeData({theme, isEinkMode}) -> ThemeData` 這個公開函式簽章完全不變，只改四個私有 `_build*Theme()` 函式內部：(1) `ColorScheme` 補齊全部角色值＋`scaffoldBackgroundColor`，不留任何角色給 M3 baseline；(2) `extensions: [ElinkTokens(...)]` 掛上該主題自己的語意色版本；(3) 移除 `cardColor`／`dividerColor` 顯式覆寫，讓 `Card`／`Divider` 走 M3 預設；(4) 新增共用的 `_buildSwitchTheme(ColorScheme)` 輔助函式，四個 `_build*Theme()` 都呼叫它掛上 `switchTheme:`。5 個 Task 依序處理：Light、Dark（含移除舊感知亮度測試）、Sepia、E-Ink（含移除 `secondary`／`onSecondary`）、最後統一補上 `SwitchThemeData`。

**Tech Stack:** Flutter／Dart，`flutter_test`（純 Dart unit test，測試縫沿用既有的 `resolveThemeData()`／`buildThemeData()` 公開函式，比照 `test/theme/app_theme_data_test.dart` 既有慣例，不直接測 `_build*Theme()` 私有函式），`ThemeExtension`／`ColorScheme`／`SwitchThemeData`／`WidgetStateProperty` 皆為既有 Flutter SDK API。

**Spec:** `docs/epics/epic-35-design-system-tokens/spec.md`（§「`resolveThemeData()` 銜接方式」、§「四套 `ColorScheme` 對齊 `DESIGN.md` §1.1」、§「電子紙可辨識度補強機制」Switch 部分、§「移除項目」、§「Testing Decisions」）；色表原始定義在 `DESIGN.md` §1.1／§1.2；工單摘要見 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 2。

## Global Constraints

- `resolveThemeData({required AppTheme theme, required bool isEinkMode}) -> ThemeData` 既有公開簽章不可變，且「`isEinkMode` 為 true 時無條件套用 E-Ink 主題」邏輯不變。
- 三主題＋E-Ink 全部角色（`primary`／`onPrimary`／`primaryContainer`／`onPrimaryContainer`／`surface`／`onSurface`／`onSurfaceVariant`／`outline`／`surfaceContainerHighest`／`error`）與 `scaffoldBackgroundColor`，逐一填成 `DESIGN.md` §1.1 表格值，不留任何角色給 M3 baseline。
- Dark 主題 `outline`（`#2c2c34`）與 `surfaceContainerHighest`（`#19191d`）**採用 `DESIGN.md` 值**，不維持現行真機實測值（`#86868F`／`#3C3C44`）；既有感知亮度差門檻斷言（`> 0.15`／`> 0.10`）須移除，不是回歸。
- 移除 `secondary`／`onSecondary`（`_buildEinkTheme()`）；移除四個函式顯式的 `cardColor`／`dividerColor` 設定，讓 `Card`／`Divider` 走 M3 預設。
- 新增 `SwitchThemeData`：`thumbColor`／`trackColor`／`trackOutlineColor` 三個插槽皆改參照 `colorScheme.onSurface`（依 OFF/ON 狀態調整透明度維持三者可區分），不是 `outline` 或 `surfaceContainerHighest`。
- `_buildEinkTheme()` 既有的 `splashFactory`／`hoverColor`／`highlightColor` 三行原樣保留。
- 既有「`dividerColor` 與 `outline` 同值」測試（`app_theme_data_test.dart` 第 81-86 行附近）**維持不動**，不需要跟著改動。
- 本工單只碰 `app/lib/theme/app_theme_data.dart` 與 `app/test/theme/app_theme_data_test.dart`，不碰任何畫面檔案（那是 Issue 3～8 的範圍）；不碰 OPDS／WebDAV／雲端來源實作／書籍儲存／閱讀進度持久化。
- 所有 Dart 原始碼註解使用正體中文。
- 每完成一個 Task 就跑一次該 Task 涉及的測試檔（`flutter test test/theme/app_theme_data_test.dart`），不需要整套 `flutter test`；整份計劃最後一個 Task 完成時才跑一次完整 `flutter test`（見 `CLAUDE.md`「測試執行範圍」）。
- 每個 Task 的 Step 完成後，把本檔案對應的 `- [x]` 改成 `- [x]`（`sdd-workflow` 規則，方便追蹤進度）。
- 提交前 `flutter analyze` 須維持「No issues found!」。

## 動手改程式碼前的四點說明（`UI_DESIGN_RULES.md` 要求）

1. **改哪個 UI 元件**：`app/lib/theme/app_theme_data.dart` 的四個私有函式 `_buildLightTheme()`／`_buildDarkTheme()`／`_buildSepiaTheme()`／`_buildEinkTheme()`——這些是 `ThemeData` 工廠函式，不是 widget，本工單不新增或修改任何 widget 檔案。
2. **為什麼要改**：(a) 現行 `primary` 色其實是紫色（`#8B5CF6`），不是 `DESIGN.md` 指定的天空藍（`#0284c7`）；(b) Light／Sepia／E-Ink 三個函式完全沒設定 `surfaceContainerHighest`，隱性等於 M3 baseline，會透出設計文件未預期的淡紫色；(c) Dark 主題 `outline`／`surfaceContainerHighest` 目前是真機電子紙實測調校值，跟 `DESIGN.md` 色表不一致，這次改採配色系統一致性優先，可辨識度風險改由 `SwitchThemeData` 的 `onSurface` 邊框補強機制承接；(d) `ElinkTokens`（Issue 1 已建好類別本體）尚未被任何主題實際使用，本工單是它第一次真正掛上 `ThemeData.extensions`。
3. **哪些畫面依賴它**：`resolveThemeData()` 是全 App 唯一的主題組裝入口，任何呼叫 `Theme.of(context)` 的畫面都會立即受到 `ColorScheme` 色值改變影響（書架、閱讀器、設定等所有既有 Material 元件如 `AppBar`／`Card`／`Switch` 都會跟著換色）；`Theme.of(context).extension<ElinkTokens>()` 這個新讀取方式，本工單完成後尚未有任何畫面主動改用（那是 Issue 3～8 的範圍），本工單只確保它能被正確組裝、讀取得到。
4. **是否影響 business logic**：不影響。純視覺色票調整與資料容器組裝，不涉及任何資料流、狀態邏輯或持久化。

---

### Task 1: Light 主題（`_buildLightTheme()`）——`ColorScheme` 全角色對齊＋`ElinkTokens` 掛載＋移除 `cardColor`／`dividerColor`

**Files:**
- Modify: `app/lib/theme/app_theme_data.dart`（頂部 import、`_buildLightTheme()`，約第 37-59 行）
- Test: `app/test/theme/app_theme_data_test.dart`

**Interfaces:**
- Consumes: Issue 1 已建好的 `ElinkTokens` 類別（`app/lib/theme/elink_tokens.dart`，`const` 建構子、全部欄位具名必填）。
- Produces: `_buildLightTheme()` 回傳的 `ThemeData` 之 `colorScheme` 補齊 `primary`／`onPrimary`／`primaryContainer`／`onPrimaryContainer`／`surface`／`onSurface`／`onSurfaceVariant`／`outline`／`surfaceContainerHighest`／`error`，`scaffoldBackgroundColor` 對齊 `DESIGN.md`；`extensions` 掛上 `isEink: false` 的 `ElinkTokens`。後續 Task 2～5 沿用同一種函式結構。

- [x] **Step 1: 寫失敗的測試——Light 主題 `ColorScheme` 各角色值＋`ElinkTokens` 組裝＋`Card`／`Divider` M3 預設**

在 `app/test/theme/app_theme_data_test.dart` 頂部加入 `ElinkTokens` import：

```dart
import 'package:elinkbook/theme/elink_tokens.dart';
```

在 `group('buildThemeData', () { ... })` 區塊內、既有 `test('light 主題使用淺色背景', ...)` 之後，新增：

```dart
    test('light 主題 ColorScheme 全角色對齊 DESIGN.md §1.1（不留 M3 baseline）',
        () {
      final theme = buildThemeData(AppTheme.light);
      final scheme = theme.colorScheme;

      expect(scheme.primary, const Color(0xFF0284C7));
      expect(scheme.onPrimary, const Color(0xFFFFFFFF));
      expect(scheme.primaryContainer, const Color(0xFFE0F2FE));
      expect(scheme.onPrimaryContainer, const Color(0xFF0284C7));
      expect(scheme.surface, const Color(0xFFFFFFFF));
      expect(scheme.onSurface, const Color(0xFF0F172A));
      expect(scheme.onSurfaceVariant, const Color(0xFF334155));
      expect(scheme.outline, const Color(0xFFCBDFE9));
      expect(scheme.surfaceContainerHighest, const Color(0xFFE6F1FA));
      expect(scheme.error, const Color(0xFFEF4444));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF0F6FC));
    });

    test(
        '移除 cardColor／dividerColor 顯式設定後，ThemeData 這兩個 M2 遺留'
        '欄位本身的 M3 預設解析值仍符合預期（cardColor 退回'
        ' colorScheme.surface，dividerColor 退回 colorScheme.outline，皆與'
        '移除前手動設定的值相同）——**注意**：這兩個欄位只是 ThemeData 上的'
        '獨立屬性，不代表 Card()／Divider() widget 實際渲染會讀取它們（M3'
        '下兩個 widget 各自直接吃 colorScheme 的其他角色，見下一則'
        ' testWidgets），這裡只保護「還有其他呼叫端直接讀'
        ' Theme.of(context).dividerColor」這種用法（例如'
        ' nav_zone_settings_screen.dart，屬 Issue 5 範圍）不會被本工單影響。',
        () {
      final theme = buildThemeData(AppTheme.light);
      expect(theme.cardColor, theme.colorScheme.surface);
      expect(theme.dividerColor, theme.colorScheme.outline);
    });

    testWidgets(
        '移除 cardColor／dividerColor 顯式設定後，Card()／Divider() widget'
        '實際渲染出的顏色符合 M3 預設角色（Card 走'
        ' colorScheme.surfaceContainerLow，Divider 走'
        ' colorScheme.outlineVariant——這兩個角色從頭到尾都不吃'
        ' cardColor／dividerColor，跟本工單是否移除這兩個欄位無關；這則'
        '測試單純鎖定／記錄這個容易被誤解的 M3 實際渲染事實，不是本 Task'
        ' diff 要驗證失敗轉通過的對象，見 Step 2 說明。'
        ' surfaceContainerLow／outlineVariant 本身不在 DESIGN.md §1.1 本次'
        '要對齊的角色清單內，若之後要讓 Card／Divider 視覺對齊設計系統色'
        '票，需另開工單評估，不在本 Issue 2 範圍）', (tester) async {
      final theme = buildThemeData(AppTheme.light);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Column(
              children: [
                Card(child: SizedBox(width: 10, height: 10)),
                Divider(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cardMaterial = tester.widget<Material>(
        find.descendant(
          of: find.byType(Card),
          matching: find.byType(Material),
        ),
      );
      expect(cardMaterial.color, theme.colorScheme.surfaceContainerLow);

      final dividerContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(Divider),
          matching: find.byType(Container),
        ),
      );
      final dividerDecoration = dividerContainer.decoration! as BoxDecoration;
      expect(
        dividerDecoration.border!.bottom.color,
        theme.colorScheme.outlineVariant,
      );
    });
```

在檔案最底部（`group('buildThemeData', ...)` 之後）新增一個新 group：

```dart

  group('resolveThemeData 組裝的 ElinkTokens', () {
    test('light 主題（isEinkMode: false）組裝出正確的 ElinkTokens 值', () {
      final theme = resolveThemeData(theme: AppTheme.light, isEinkMode: false);
      final tokens = theme.extension<ElinkTokens>();

      expect(tokens, isNotNull);
      expect(tokens!.highlightYellow, const Color(0xFFFEF08A));
      expect(tokens.highlightGreen, const Color(0xFFBBF7D0));
      expect(tokens.highlightBlue, const Color(0xFFBFDBFE));
      expect(tokens.underlineColor, const Color(0xFF0284C7));
      expect(tokens.progressTrack, const Color(0xFFCBDFE9));
      expect(tokens.coverPlaceholder, const Color(0xFFE6F1FA));
      expect(tokens.badgeScrim, const Color(0xFF94A3B8));
      expect(tokens.ttsActiveHighlight, const Color(0xFFE0F2FE));
      expect(tokens.isEink, false);
      expect(tokens.reducedMotion, false);
      expect(tokens.discretePaging, false);
    });
  });
```

（`group('resolveThemeData 組裝的 ElinkTokens', ...)` 這個新 group 在 Task 2／3／4 會繼續往裡面加測試，本 Task 先建立它、放第一個 `test`。）

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/theme/app_theme_data_test.dart`
Expected: FAIL——「Light 主題 ColorScheme 全角色對齊」該則測試的第一個斷言 `expect(scheme.primary, ...)` 就會失敗（現行值 `#8B5CF6` 不等於預期 `#0284C7`），`expect()` 遇到失敗會立即中止該 `test()`，後續 `primaryContainer`／`onSurfaceVariant`／`surfaceContainerHighest` 等斷言不會被實際執行到（這些角色現行確實也未設定、真的執行到同樣會不相符，但不是本次紅燈實際觸發的斷言）；「ElinkTokens 值」該則因 `theme.extension<ElinkTokens>()` 回傳 `null`（尚未掛上）而在 `expect(tokens, isNotNull)` 失敗。「cardColor／dividerColor M3 預設解析值」與「Card()／Divider() widget 實際渲染顏色」這兩則測試在 Step 3 修改前後皆會通過——現行程式碼的 `cardColor`／`dividerColor` 本來就手動設成跟 `colorScheme.surface`／`outline` 相同的值，而 `Card`／`Divider` widget 的 M3 實際渲染色（`surfaceContainerLow`／`outlineVariant`）從頭到尾都不吃 `cardColor`／`dividerColor` 這兩個欄位，跟本 Task 是否移除它們無關；這兩則不是本步驟要驗證失敗的對象，屬於鎖定既有行為的迴歸保護測試，不影響本步驟整體 FAIL 判定（前兩則測試仍會讓 `flutter test` 回報 FAIL）。

- [x] **Step 3: 修改 `app_theme_data.dart`——加 import、改寫 `_buildLightTheme()`**

在檔案頂部加入 import（`import 'app_theme.dart';` 之後）：

```dart
import 'elink_tokens.dart';
```

把 `_buildLightTheme()`（原第 37-59 行）整段換成：

```dart
ThemeData _buildLightTheme() {
  const primary = Color(0xFF0284C7);
  const onPrimary = Color(0xFFFFFFFF);
  const primaryContainer = Color(0xFFE0F2FE);
  const onPrimaryContainer = Color(0xFF0284C7);
  const surface = Color(0xFFFFFFFF);
  const onSurface = Color(0xFF0F172A);
  const onSurfaceVariant = Color(0xFF334155);
  const outline = Color(0xFFCBDFE9);
  const scaffoldBackground = Color(0xFFF0F6FC);
  const surfaceContainerHighest = Color(0xFFE6F1FA);
  const error = Color(0xFFEF4444);

  final colorScheme = ColorScheme.light(
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    useMaterial3: true,
    extensions: const [
      ElinkTokens(
        highlightYellow: Color(0xFFFEF08A),
        highlightGreen: Color(0xFFBBF7D0),
        highlightBlue: Color(0xFFBFDBFE),
        underlineColor: Color(0xFF0284C7),
        progressTrack: Color(0xFFCBDFE9),
        coverPlaceholder: Color(0xFFE6F1FA),
        badgeScrim: Color(0xFF94A3B8),
        ttsActiveHighlight: Color(0xFFE0F2FE),
        isEink: false,
        reducedMotion: false,
        discretePaging: false,
      ),
    ],
  );
}
```

（`switchTheme:` 留給 Task 5 統一補上，本 Task 先不加。）

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/theme/app_theme_data_test.dart`
Expected: PASS（含既有測試＋本 Task 新增的 3 個測試全過）

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/theme/app_theme_data.dart app/test/theme/app_theme_data_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 2 Task 1 — Light 主題 ColorScheme 對齊 DESIGN.md 並掛上 ElinkTokens

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01RWEY3jycaFLoUQtzMmwK6E
EOF
)"
```

---

### Task 2: Dark 主題（`_buildDarkTheme()`）——`ColorScheme` 全角色對齊（新 `outline`／`surfaceContainerHighest` 值）＋`ElinkTokens` 掛載＋移除舊感知亮度測試

**Files:**
- Modify: `app/lib/theme/app_theme_data.dart`（`_buildDarkTheme()`，約第 61-101 行）
- Test: `app/test/theme/app_theme_data_test.dart`

**Interfaces:**
- Consumes: Task 1 建立的 `ElinkTokens` import 與 `group('resolveThemeData 組裝的 ElinkTokens', ...)` group。
- Produces: `_buildDarkTheme()` 的 `ColorScheme`／`ElinkTokens` 對齊 `DESIGN.md`，`outline`／`surfaceContainerHighest` 改為 `#2c2c34`／`#19191d`（不再是真機實測調校值）。

- [x] **Step 1: 移除舊有感知亮度差測試＋寫失敗的新測試**

在 `app/test/theme/app_theme_data_test.dart` 的 `group('buildThemeData', () { ... })` 區塊內，**刪除**以下兩則既有測試整段（原第 58-79 行「dark 主題的 outline 色與 surface 色有足夠感知亮度差…」、原第 88-111 行「dark 主題的 surfaceContainerHighest 色與 surface 色有足夠感知亮度差…」）——這兩則斷言的門檻（`> 0.15`／`> 0.10`）建立在真機實測調校值上，Dark 主題改採 `DESIGN.md` 值後兩個角色跟 `surface` 的亮度差會大幅縮小，門檻必然失敗，這是預期中的行為改變，可辨識度風險改由 Task 5 的 `SwitchThemeData` 承接。

**保留不動**：`test('dark 主題的 dividerColor 與 outline 保持同一色值…')`（原第 81-86 行）——這則測試在移除顯式 `dividerColor` 覆寫後（本 Task Step 3）仍會通過，因為 M3 預設也會讓兩者同值，不需要跟著改動。

在同一個 `group('buildThemeData', ...)` 內新增：

```dart
    test('dark 主題 ColorScheme 全角色對齊 DESIGN.md §1.1（不留 M3 baseline，'
        'outline／surfaceContainerHighest 採用 DESIGN.md 值，不維持真機實測'
        '調校值——可辨識度風險改由 SwitchThemeData 承接，見 Issue 2 Task 5）',
        () {
      final theme = buildThemeData(AppTheme.dark);
      final scheme = theme.colorScheme;

      expect(scheme.primary, const Color(0xFF38BDF8));
      expect(scheme.onPrimary, const Color(0xFF141416));
      expect(scheme.primaryContainer, const Color(0xFF182836));
      expect(scheme.onPrimaryContainer, const Color(0xFF38BDF8));
      expect(scheme.surface, const Color(0xFF1D1D22));
      expect(scheme.onSurface, const Color(0xFFF2EFE6));
      expect(scheme.onSurfaceVariant, const Color(0xFFB5B2A8));
      expect(scheme.outline, const Color(0xFF2C2C34));
      expect(scheme.surfaceContainerHighest, const Color(0xFF19191D));
      expect(scheme.error, const Color(0xFFF87171));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF141416));
    });
```

在 `group('resolveThemeData 組裝的 ElinkTokens', () { ... })` 內、Task 1 那則測試之後新增：

```dart

    test('dark 主題（isEinkMode: false）組裝出正確的 ElinkTokens 值', () {
      final theme = resolveThemeData(theme: AppTheme.dark, isEinkMode: false);
      final tokens = theme.extension<ElinkTokens>();

      expect(tokens, isNotNull);
      expect(tokens!.highlightYellow, const Color(0xFF854D0E));
      expect(tokens.highlightGreen, const Color(0xFF166534));
      expect(tokens.highlightBlue, const Color(0xFF1E40AF));
      expect(tokens.underlineColor, const Color(0xFF38BDF8));
      expect(tokens.progressTrack, const Color(0xFF2C2C34));
      expect(tokens.coverPlaceholder, const Color(0xFF1D1D22));
      expect(tokens.badgeScrim, const Color(0xFF7A7872));
      expect(tokens.ttsActiveHighlight, const Color(0xFF182836));
      expect(tokens.isEink, false);
      expect(tokens.reducedMotion, false);
      expect(tokens.discretePaging, false);
    });
```

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/theme/app_theme_data_test.dart`
Expected: FAIL——「dark 主題 ColorScheme 全角色對齊」該則測試的第一個斷言 `expect(scheme.primary, ...)` 就會失敗（現行值 `#BB86FC` 不等於預期 `#38BDF8`），`expect()` 立即中止該 `test()`，後續 `outline`／`surfaceContainerHighest` 等斷言不會被實際執行到（這些角色現行值 `#86868F`／`#3C3C44` 同樣不等於 `DESIGN.md` 新值，真的執行到同樣會不相符，但不是本次紅燈實際觸發的斷言）；「dark ElinkTokens 值」該則因 `tokens` 為 `null` 而失敗。

- [x] **Step 3: 改寫 `_buildDarkTheme()`**

把 `_buildDarkTheme()`（原第 61-101 行）整段換成：

```dart
ThemeData _buildDarkTheme() {
  const primary = Color(0xFF38BDF8);
  const onPrimary = Color(0xFF141416);
  const primaryContainer = Color(0xFF182836);
  const onPrimaryContainer = Color(0xFF38BDF8);
  const surface = Color(0xFF1D1D22);
  const onSurface = Color(0xFFF2EFE6);
  const onSurfaceVariant = Color(0xFFB5B2A8);
  // 【epic-35-design-system-tokens Issue 2】改採 DESIGN.md §1.1 色表值，
  // 不再維持先前真機電子紙實測調亮值（outline #86868F／
  // surfaceContainerHighest #3C3C44，見 spec.md「Dark 主題色值衝突決議」）
  // ——選擇配色系統一致性優先。這兩個角色跟 surface 的感知亮度差因此大幅
  // 縮小，Switch 等元件不再靠這兩個角色的顏色對比撐可辨識度，改由
  // _buildSwitchTheme() 的 onSurface 邊框補強機制承接（見下方 switchTheme
  // 賦值處，Issue 2 Task 5 加上）。
  const outline = Color(0xFF2C2C34);
  const scaffoldBackground = Color(0xFF141416);
  const surfaceContainerHighest = Color(0xFF19191D);
  const error = Color(0xFFF87171);

  final colorScheme = ColorScheme.dark(
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    useMaterial3: true,
    extensions: const [
      ElinkTokens(
        highlightYellow: Color(0xFF854D0E),
        highlightGreen: Color(0xFF166534),
        highlightBlue: Color(0xFF1E40AF),
        underlineColor: Color(0xFF38BDF8),
        progressTrack: Color(0xFF2C2C34),
        coverPlaceholder: Color(0xFF1D1D22),
        badgeScrim: Color(0xFF7A7872),
        ttsActiveHighlight: Color(0xFF182836),
        isEink: false,
        reducedMotion: false,
        discretePaging: false,
      ),
    ],
  );
}
```

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/theme/app_theme_data_test.dart`
Expected: PASS（含既有測試＋新增測試全過；已移除的兩則舊感知亮度測試不應再出現於測試輸出中）

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/theme/app_theme_data.dart app/test/theme/app_theme_data_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 2 Task 2 — Dark 主題 ColorScheme 對齊 DESIGN.md，移除舊感知亮度測試

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01RWEY3jycaFLoUQtzMmwK6E
EOF
)"
```

---

### Task 3: Sepia 主題（`_buildSepiaTheme()`）——`ColorScheme` 全角色對齊＋`ElinkTokens` 掛載

**Files:**
- Modify: `app/lib/theme/app_theme_data.dart`（`_buildSepiaTheme()`，約第 103-125 行）
- Test: `app/test/theme/app_theme_data_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `ElinkTokens` import 與測試 group。
- Produces: `_buildSepiaTheme()` 的 `ColorScheme`／`ElinkTokens` 對齊 `DESIGN.md`（`primary` 由現行橙棕色 `#B45309` 改為硃砂印泥紅 `#b8362d`）。

- [x] **Step 1: 寫失敗的測試**

在 `group('buildThemeData', ...)` 內新增：

```dart
    test('sepia 主題 ColorScheme 全角色對齊 DESIGN.md §1.1（不留 M3 baseline）',
        () {
      final theme = buildThemeData(AppTheme.sepia);
      final scheme = theme.colorScheme;

      expect(scheme.primary, const Color(0xFFB8362D));
      expect(scheme.onPrimary, const Color(0xFFFFFFFF));
      expect(scheme.primaryContainer, const Color(0xFFFAECEA));
      expect(scheme.onPrimaryContainer, const Color(0xFFB8362D));
      expect(scheme.surface, const Color(0xFFFAF3E3));
      expect(scheme.onSurface, const Color(0xFF1F2022));
      expect(scheme.onSurfaceVariant, const Color(0xFF535457));
      expect(scheme.outline, const Color(0xFFE6DFCB));
      expect(scheme.surfaceContainerHighest, const Color(0xFFF0EBD9));
      expect(scheme.error, const Color(0xFFDC2626));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFCFAF2));
    });
```

在 `group('resolveThemeData 組裝的 ElinkTokens', ...)` 內新增：

```dart

    test('sepia 主題（isEinkMode: false）組裝出正確的 ElinkTokens 值', () {
      final theme = resolveThemeData(theme: AppTheme.sepia, isEinkMode: false);
      final tokens = theme.extension<ElinkTokens>();

      expect(tokens, isNotNull);
      expect(tokens!.highlightYellow, const Color(0xFFFEF3C7));
      expect(tokens.highlightGreen, const Color(0xFFEDF5F0));
      expect(tokens.highlightBlue, const Color(0xFFEDF2F7));
      expect(tokens.underlineColor, const Color(0xFFB8362D));
      expect(tokens.progressTrack, const Color(0xFFE6DFCB));
      expect(tokens.coverPlaceholder, const Color(0xFFF0EBD9));
      expect(tokens.badgeScrim, const Color(0xFF848588));
      expect(tokens.ttsActiveHighlight, const Color(0xFFFAECEA));
      expect(tokens.isEink, false);
      expect(tokens.reducedMotion, false);
      expect(tokens.discretePaging, false);
    });
```

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/theme/app_theme_data_test.dart`
Expected: FAIL——「sepia 主題 ColorScheme 全角色對齊」該則測試的第一個斷言 `expect(scheme.primary, ...)` 就會失敗（現行值 `#B45309` 不等於預期 `#B8362D`），`expect()` 立即中止該 `test()`，後續 `primaryContainer`／`onSurfaceVariant`／`surfaceContainerHighest` 等斷言不會被實際執行到（這些角色現行完全未設定，真的執行到同樣會不相符，但不是本次紅燈實際觸發的斷言）；「sepia ElinkTokens 值」該則因 `tokens` 為 `null` 而失敗。

- [x] **Step 3: 改寫 `_buildSepiaTheme()`**

把 `_buildSepiaTheme()`（原第 103-125 行）整段換成：

```dart
ThemeData _buildSepiaTheme() {
  const primary = Color(0xFFB8362D);
  const onPrimary = Color(0xFFFFFFFF);
  const primaryContainer = Color(0xFFFAECEA);
  const onPrimaryContainer = Color(0xFFB8362D);
  const surface = Color(0xFFFAF3E3);
  const onSurface = Color(0xFF1F2022);
  const onSurfaceVariant = Color(0xFF535457);
  const outline = Color(0xFFE6DFCB);
  const scaffoldBackground = Color(0xFFFCFAF2);
  const surfaceContainerHighest = Color(0xFFF0EBD9);
  const error = Color(0xFFDC2626);

  final colorScheme = ColorScheme.light(
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    useMaterial3: true,
    extensions: const [
      ElinkTokens(
        highlightYellow: Color(0xFFFEF3C7),
        highlightGreen: Color(0xFFEDF5F0),
        highlightBlue: Color(0xFFEDF2F7),
        underlineColor: Color(0xFFB8362D),
        progressTrack: Color(0xFFE6DFCB),
        coverPlaceholder: Color(0xFFF0EBD9),
        badgeScrim: Color(0xFF848588),
        ttsActiveHighlight: Color(0xFFFAECEA),
        isEink: false,
        reducedMotion: false,
        discretePaging: false,
      ),
    ],
  );
}
```

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/theme/app_theme_data_test.dart`
Expected: PASS

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/theme/app_theme_data.dart app/test/theme/app_theme_data_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 2 Task 3 — Sepia 主題 ColorScheme 對齊 DESIGN.md 並掛上 ElinkTokens

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01RWEY3jycaFLoUQtzMmwK6E
EOF
)"
```

---

### Task 4: E-Ink 主題（`_buildEinkTheme()`）——`ColorScheme` 全角色對齊（移除 `secondary`／`onSecondary`）＋`ElinkTokens` 掛載

**Files:**
- Modify: `app/lib/theme/app_theme_data.dart`（`_buildEinkTheme()`，約第 127-152 行）
- Test: `app/test/theme/app_theme_data_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `ElinkTokens` import 與測試 group。
- Produces: `_buildEinkTheme()` 的 `ColorScheme` 補齊 `primaryContainer`／`onPrimaryContainer`／`onSurfaceVariant`／`surfaceContainerHighest`，移除 `secondary`／`onSecondary`；`extensions` 掛上 `isEink: true`／`reducedMotion: true`／`discretePaging: true` 的 `ElinkTokens`。完成後四種 `theme × isEinkMode` 組合的 `ElinkTokens` 組裝測試全數到位。

- [x] **Step 1: 寫失敗的測試**

在 `group('buildThemeData', ...)` 內新增：

```dart
    test('eink 主題 ColorScheme 全角色對齊 DESIGN.md §1.1（純黑白，不留'
        ' secondary／onSecondary）', () {
      final theme = buildEinkThemeData();
      final scheme = theme.colorScheme;

      expect(scheme.primary, const Color(0xFF000000));
      expect(scheme.onPrimary, const Color(0xFFFFFFFF));
      expect(scheme.primaryContainer, const Color(0xFFFFFFFF));
      expect(scheme.onPrimaryContainer, const Color(0xFF000000));
      expect(scheme.surface, const Color(0xFFFFFFFF));
      expect(scheme.onSurface, const Color(0xFF000000));
      expect(scheme.onSurfaceVariant, const Color(0xFF000000));
      expect(scheme.outline, const Color(0xFF000000));
      expect(scheme.surfaceContainerHighest, const Color(0xFFFFFFFF));
      expect(scheme.error, const Color(0xFF000000));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    });
```

在 `group('resolveThemeData 組裝的 ElinkTokens', ...)` 內新增：

```dart

    test('E-Ink 模式（isEinkMode: true，不論 theme 為何）組裝出正確的'
        ' ElinkTokens 值', () {
      final theme = resolveThemeData(theme: AppTheme.dark, isEinkMode: true);
      final tokens = theme.extension<ElinkTokens>();

      expect(tokens, isNotNull);
      expect(tokens!.highlightYellow, const Color(0xFF000000));
      expect(tokens.highlightGreen, const Color(0xFF000000));
      expect(tokens.highlightBlue, const Color(0xFF000000));
      expect(tokens.underlineColor, const Color(0xFF000000));
      expect(tokens.progressTrack, const Color(0xFF000000));
      expect(tokens.coverPlaceholder, const Color(0xFFFFFFFF));
      expect(tokens.badgeScrim, const Color(0xFF000000));
      expect(tokens.ttsActiveHighlight, const Color(0xFF000000));
      expect(tokens.isEink, true);
      expect(tokens.reducedMotion, true);
      expect(tokens.discretePaging, true);
    });
```

（刻意傳 `theme: AppTheme.dark` 而非 `AppTheme.light`，用來確認「`isEinkMode: true` 時不論 `theme` 為何都拿到同一組 E-Ink `ElinkTokens`」這件事，跟本檔案既有的 `resolveThemeData` group 測試精神一致。）

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/theme/app_theme_data_test.dart`
Expected: FAIL——「eink 主題 ColorScheme 全角色對齊」該則測試的前兩個斷言 `primary`／`onPrimary` 現行值恰好就是 `Colors.black`／`Colors.white`，跟預期值相同，會先通過；第三個斷言 `expect(scheme.primaryContainer, ...)` 才是真正觸發失敗的斷言——現行 `_buildEinkTheme()` 沒有設定 `primaryContainer`，`ColorScheme.light()` 對這個角色的預設 fallback 是 `primary` 本身（即 `Colors.black`），不等於預期的 `#FFFFFF`，`expect()` 在這裡中止，後續 `onPrimaryContainer`／`onSurfaceVariant`／`surfaceContainerHighest` 等斷言不會被實際執行到；「E-Ink ElinkTokens 值」該則因 `tokens` 為 `null` 而失敗。

- [x] **Step 3: 改寫 `_buildEinkTheme()`**

把 `_buildEinkTheme()`（原第 127-152 行）整段換成：

```dart
ThemeData _buildEinkTheme() {
  const primary = Color(0xFF000000);
  const primaryContainer = Color(0xFFFFFFFF);
  const onPrimaryContainer = Color(0xFF000000);
  const surface = Color(0xFFFFFFFF);
  const onSurface = Color(0xFF000000);
  const onSurfaceVariant = Color(0xFF000000);
  const outline = Color(0xFF000000);
  const surfaceContainerHighest = Color(0xFFFFFFFF);
  const error = Color(0xFF000000);

  final colorScheme = ColorScheme.light(
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
    onError: Colors.white,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.white,
    useMaterial3: true,
    // 停用點擊水波紋效果與高亮，以避免電子紙裝置上產生嚴重殘影與刷新閃爍
    splashFactory: NoSplash.splashFactory,
    hoverColor: Colors.transparent,
    highlightColor: Colors.transparent,
    extensions: const [
      ElinkTokens(
        // highlightYellow／highlightGreen／highlightBlue／ttsActiveHighlight：
        // DESIGN.md §1.2 標註「無背景（改用下劃線／外框／點虛線）」、未給
        // 明確 hex 值——E-Ink 純黑白色盤下取黑色（描邊/底線用色），實際
        // 「不畫底色改畫線條」的渲染邏輯屬其他 Issue 範圍，這裡只決定色票值。
        highlightYellow: Color(0xFF000000),
        highlightGreen: Color(0xFF000000),
        highlightBlue: Color(0xFF000000),
        underlineColor: Color(0xFF000000),
        progressTrack: Color(0xFF000000),
        coverPlaceholder: Color(0xFFFFFFFF),
        badgeScrim: Color(0xFF000000),
        ttsActiveHighlight: Color(0xFF000000),
        isEink: true,
        reducedMotion: true,
        discretePaging: true,
      ),
    ],
  );
}
```

（`secondary`／`onSecondary`／`cardColor`／`dividerColor` 皆已從原本的 `ColorScheme.light(...)`／`ThemeData(...)` 呼叫中拿掉，不再顯式設定。）

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/theme/app_theme_data_test.dart`
Expected: PASS（本檔案全部測試皆過，含既有的「E-Ink 高對比 ThemeData 使用純白背景與純黑文字」等測試）

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/theme/app_theme_data.dart app/test/theme/app_theme_data_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 2 Task 4 — E-Ink 主題 ColorScheme 對齊 DESIGN.md，移除 secondary/onSecondary

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01RWEY3jycaFLoUQtzMmwK6E
EOF
)"
```

---

### Task 5: `SwitchThemeData` 電子紙可辨識度補強（四套主題統一掛上）

**Files:**
- Modify: `app/lib/theme/app_theme_data.dart`（新增 `_buildSwitchTheme()` 輔助函式；四個 `_build*Theme()` 各自的 `ThemeData(...)` 加一行 `switchTheme:`）
- Test: `app/test/theme/app_theme_data_test.dart`

**Interfaces:**
- Consumes: Task 1～4 完成後四個 `_build*Theme()` 函式內已存在的區域變數 `colorScheme`。
- Produces: `SwitchThemeData _buildSwitchTheme(ColorScheme colorScheme)`——`thumbColor`／`trackColor`／`trackOutlineColor` 三個插槽皆為 `WidgetStateProperty`，解析結果的 RGB 皆來自 `colorScheme.onSurface`（僅 alpha 依 OFF/ON 狀態不同）。本 Task 完成後 Issue 2 全部驗收標準到位。

- [x] **Step 1: 寫失敗的測試——四套主題 `switchTheme` 三插槽於 OFF 狀態皆解析自 `colorScheme.onSurface`**

在 `app/test/theme/app_theme_data_test.dart` 的 `import` 區塊與 `void main() {` 之間（檔案層級，`main()` 函式外）新增一個共用 helper：

```dart
/// 比較兩個顏色的 RGB 分量是否相同，忽略 alpha（用於驗證某個顏色是否
/// 「來源於」另一個顏色，即使中間套用了不同透明度）。
bool _sameRgb(Color a, Color b) => a.r == b.r && a.g == b.g && a.b == b.b;
```

在 `group('buildThemeData', ...)` 內新增：

```dart
    test('四套主題的 switchTheme 三插槽於 OFF 狀態皆解析自 colorScheme.onSurface'
        '（電子紙可辨識度補強，取代不再可靠的 outline／surfaceContainerHighest'
        ' 對比手法，見 spec.md「電子紙可辨識度補強機制」）', () {
      for (final theme in AppTheme.values) {
        final themeData = buildThemeData(theme);
        final onSurface = themeData.colorScheme.onSurface;
        final switchTheme = themeData.switchTheme;

        final thumb = switchTheme.thumbColor?.resolve(<WidgetState>{});
        final track = switchTheme.trackColor?.resolve(<WidgetState>{});
        final trackOutline =
            switchTheme.trackOutlineColor?.resolve(<WidgetState>{});

        expect(thumb, isNotNull, reason: '$theme thumbColor 未設定');
        expect(track, isNotNull, reason: '$theme trackColor 未設定');
        expect(trackOutline, isNotNull, reason: '$theme trackOutlineColor 未設定');
        expect(_sameRgb(thumb!, onSurface), true,
            reason: '$theme thumbColor 應來源於 onSurface');
        expect(_sameRgb(track!, onSurface), true,
            reason: '$theme trackColor 應來源於 onSurface');
        expect(_sameRgb(trackOutline!, onSurface), true,
            reason: '$theme trackOutlineColor 應來源於 onSurface');
      }
    });

    test('E-Ink 主題的 switchTheme 三插槽於 OFF 狀態皆解析自 colorScheme.onSurface',
        () {
      final themeData = buildEinkThemeData();
      final onSurface = themeData.colorScheme.onSurface;
      final switchTheme = themeData.switchTheme;

      final thumb = switchTheme.thumbColor?.resolve(<WidgetState>{});
      final track = switchTheme.trackColor?.resolve(<WidgetState>{});
      final trackOutline =
          switchTheme.trackOutlineColor?.resolve(<WidgetState>{});

      expect(thumb, isNotNull);
      expect(track, isNotNull);
      expect(trackOutline, isNotNull);
      expect(_sameRgb(thumb!, onSurface), true);
      expect(_sameRgb(track!, onSurface), true);
      expect(_sameRgb(trackOutline!, onSurface), true);
    });
```

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/theme/app_theme_data_test.dart`
Expected: FAIL——現行四個 `_build*Theme()` 都沒有設定 `switchTheme`，`ThemeData.switchTheme` 因此是 Flutter 預設值 `const SwitchThemeData()`，`thumbColor`／`trackColor`／`trackOutlineColor` 三個插槽皆為 `null`（`outline`／`surfaceContainerHighest` 的解析只發生在實際建構 `Switch` widget 當下，不影響 `ThemeData.switchTheme` 這個屬性本身的值）。每一組 `expect(thumb, isNotNull, ...)` 這類斷言會在第一步就失敗，`_sameRgb` 比對不會被執行到。

- [x] **Step 3: 新增 `_buildSwitchTheme()`，四個 `_build*Theme()` 各自掛上**

在 `app_theme_data.dart` 的 `_buildLightTheme()` 函式定義**之前**新增：

```dart
/// 電子紙可辨識度補強（epic-35-design-system-tokens Issue 2）：M3 Switch
/// OFF 狀態預設會吃 outline（thumbColor）／surfaceContainerHighest
/// （trackColor）兩個角色，這兩個角色在 Dark 主題改採 DESIGN.md 色值後彼此
/// 跟 surface 的亮度差大幅縮小，電子紙上不可靠（見 spec.md「Dark 主題色值
/// 衝突決議」）。改為三個插槽全部參照 colorScheme.onSurface——onSurface 對
/// surface 的對比由文字可讀性需求保證足夠，比原本設計給裝飾用的
/// outline／surfaceContainerHighest 更適合扛「使用者必須看得見」的責任。
/// thumb／trackOutline 用滿不透明，track 依 OFF/ON 狀態調整透明度，三者
/// 之間仍可互相區分。【注意】0.5／0.15 這兩個透明度數值是本工單自行決定
/// 的具體詮釋，spec.md 只給了「依狀態調整透明度以維持三者可區分」的定性
/// 描述，沒有指定精確數字——下一輪真機驗證（比照 epic-18／epic-25 慣例）
/// 若發現電子紙上不夠清楚，這兩個數字是可以直接調整的錨點，不需要重新
/// 討論整體設計。
SwitchThemeData _buildSwitchTheme(ColorScheme colorScheme) {
  return SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith(
      (states) => colorScheme.onSurface,
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (states) => colorScheme.onSurface.withValues(
        alpha: states.contains(WidgetState.selected) ? 0.5 : 0.15,
      ),
    ),
    trackOutlineColor: WidgetStateProperty.resolveWith(
      (states) => colorScheme.onSurface,
    ),
  );
}

```

在四個 `_build*Theme()` 函式各自的 `ThemeData(...)` 建構裡，於 `useMaterial3: true,` 這一行之後加上 `switchTheme:` 這一行：

`_buildLightTheme()` 內：

```dart
    useMaterial3: true,
    switchTheme: _buildSwitchTheme(colorScheme),
    extensions: const [
      ElinkTokens(
        highlightYellow: Color(0xFFFEF08A),
```

`_buildDarkTheme()` 內：

```dart
    useMaterial3: true,
    switchTheme: _buildSwitchTheme(colorScheme),
    extensions: const [
      ElinkTokens(
        highlightYellow: Color(0xFF854D0E),
```

`_buildSepiaTheme()` 內：

```dart
    useMaterial3: true,
    switchTheme: _buildSwitchTheme(colorScheme),
    extensions: const [
      ElinkTokens(
        highlightYellow: Color(0xFFFEF3C7),
```

`_buildEinkTheme()` 內（插在 `useMaterial3: true,` 與既有的 `splashFactory` 那三行之間）：

```dart
    useMaterial3: true,
    switchTheme: _buildSwitchTheme(colorScheme),
    // 停用點擊水波紋效果與高亮，以避免電子紙裝置上產生嚴重殘影與刷新閃爍
    splashFactory: NoSplash.splashFactory,
```

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/theme/app_theme_data_test.dart`
Expected: PASS（本檔案全部測試皆過）

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/theme/app_theme_data.dart app/test/theme/app_theme_data_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 2 Task 5 — 新增 SwitchThemeData 電子紙可辨識度補強

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01RWEY3jycaFLoUQtzMmwK6E
EOF
)"
```

---

## 全部 Task 完成後

- [x] 執行完整 `flutter test`（於 `app/` 目錄下，不帶檔案路徑），確認全專案無回歸。
- [x] 執行 `flutter analyze`，確認「No issues found!」。
- [x] 把 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 2 的 `Status` 從 `ready-for-agent` 更新為完成狀態（依當時 Epic 慣例用語），並在 `epic.md` 補一筆開發記錄。
- [x] 依 `sdd-workflow` 流程，發起 `/superpowers:requesting-code-review` 審查本次程式碼變更（`BASE_SHA`／`HEAD_SHA` 取本工單 5 個 commit 的起訖），審查報告存 `docs/epics/epic-35-design-system-tokens/reviews/review-issue-2.md`。
- [x] 提醒：本 Issue 驗收標準明確排除「`SwitchThemeData` 補強手法的真機驗證」——需要下一輪真機驗證確認在電子紙上確實可辨識（比照 `epic-18`／`epic-25` 慣例），不在本工單範圍內完成。
