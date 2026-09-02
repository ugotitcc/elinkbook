# Epic 35 — Issue 3：`settings_screen.dart` 全面遷移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `SettingsScreen`（`app/lib/screens/settings_screen.dart`）的「佈景」主題預覽圓點改讀 `resolveThemeData()` 的實際色值（取代自己另一份寫死近似值），並把 E-Ink 高對比模式開啟時的鎖定視覺從「降低透明度」改為 `DESIGN.md` §17.2 指定的虛線邊框＋提示文字＋無障礙標籤，同時清掉檔案內僅剩的一處寫死顏色（`Colors.grey`）。

**Architecture:** 全部改動集中在 `_SettingsScreenState._buildThemeDot()` 這一個私有 helper 與呼叫它的「佈景」`ListTile`，`SettingsScreen` 的公開建構參數（`onThemeChanged`／`onEinkModeChanged` 等）完全不變。分兩個 Task 處理：Task 1 先把圓點的背景／邊框色來源從呼叫端傳入的寫死 `Color` 改為呼叫 `resolveThemeData(theme: theme, isEinkMode: false)` 取得（連帶把未選取邊框的 `Colors.grey.withValues(alpha: 0.5)` 換成該主題自己的 `colorScheme.outline`）；Task 2 在此之上把 `Opacity(0.4)` 鎖定手法換成 `CustomPaint` 疊加繪製的 `3dp` 虛線圓框，並在「佈景」`ListTile` 加上鎖定提示文字、在圓點外層加上 `Semantics` 標籤。兩個 Task 都只碰同一個檔案與同一支測試檔，不影響其他畫面。

**Tech Stack:** Flutter／Dart，`flutter_test`（widget test，比照 `test/screens/settings_screen_test.dart` 既有慣例），`ThemeData`／`ColorScheme`／`BoxDecoration`／`CustomPainter`／`Semantics` 皆為既有 Flutter SDK API，不新增任何 pub 套件依賴。

**Spec:** `docs/epics/epic-35-design-system-tokens/spec.md`（§「`settings_screen.dart` E-Ink 鎖定視覺與主題預覽色」、§「Testing Decisions」）；鎖定視覺語彙定義在 `DESIGN.md` §17.2（佈景選擇與 E-Ink 鎖定行為）與 §7.2（觸控目標與狀態規範，E-Ink 離散狀態變更語彙）；工單摘要見 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 3。

**範圍決定（本計劃撰寫時與人類確認過）：** `issues.md` Issue 3 的「Solution」與「單元測試要求」只明講邊框虛線化，沒提到 `DESIGN.md` §17.2 全文另外要求的「提示文字」與「Semantics 標籤」兩件事，現行程式碼裡這兩者也完全沒有。經與人類確認，**本計劃依 `DESIGN.md` §17.2 全文補齊三件事**（邊框虛線化＋提示文字＋Semantics 標籤），不是只做邊框這一半——因為 Issue 3 的驗收標準明講「E-Ink 鎖定視覺符合 `DESIGN.md` §17.2」，是完整條款而非摘要。

## Global Constraints

- 依賴 Issue 2 已完成：`resolveThemeData({required AppTheme theme, required bool isEinkMode}) -> ThemeData` 四套主題色值與 `ElinkTokens` 已對齊 `DESIGN.md` §1.1，本工單直接引用其輸出，不重新定義任何色值。
- 三顆主題預覽圓點只涵蓋 `AppTheme.light`／`dark`／`sepia`（E-Ink 高對比模式是獨立的全域布林開關，不是第 4 種 `AppTheme` 選項，見 `app/lib/theme/app_theme.dart` 檔頭註解），本工單不新增第 4 顆圓點、不修改 `AppTheme` 列舉。
- 每顆圓點的背景色一律讀 `resolveThemeData(theme: theme, isEinkMode: false).scaffoldBackgroundColor`；邊框色（選取用 `colorScheme.primary`／未選取用 `colorScheme.outline`）一律讀**同一次呼叫**（該圓點自己的主題）回傳的 `ColorScheme`，不透過 `Theme.of(context)` 間接取值——確保圓點是每個主題「自身」的忠實預覽，不受 App 目前實際套用哪個主題影響。
- E-Ink 鎖定視覺改為 `DESIGN.md` §17.2 指定的 `3dp` 虛線邊框（比照 §7.2 離散狀態變更語彙），不得再用 `Opacity` 調降透明度；鎖定時 `onTap` 仍為 `null`（既有邏輯不變，不得讓使用者在鎖定狀態下切換主題）。
- E-Ink 鎖定時「佈景」列須顯示提示文字「這裡選的是關閉 E-Ink 後要恢復的主題」，且每顆圓點外層須保留 `Semantics` 標籤，讀出鎖定狀態與目前選擇的主題（`DESIGN.md` §17.2 全文要求）。
- 移除 `Colors.grey.withValues(alpha: 0.5)`——這是本檔案僅剩的一處寫死顏色殘留（`spec.md` 已盤點確認只剩這 1 處）。
- 本工單只碰 `app/lib/screens/settings_screen.dart` 與 `app/test/screens/settings_screen_test.dart`，不碰其他畫面檔案（`nav_zone_settings_screen.dart` 是 Issue 5 範圍）；不碰 OPDS／WebDAV／雲端來源實作／書籍儲存／閱讀進度持久化。
- 所有 Dart 原始碼註解使用正體中文。
- 每完成一個 Task 就跑一次 `flutter test test/screens/settings_screen_test.dart`（於 `app/` 目錄下），不需要整套 `flutter test`；整份計劃最後一個 Task 完成時才跑一次完整 `flutter test`（見 `CLAUDE.md`「測試執行範圍」）。
- 每個 Task 的 Step 完成後，把本檔案對應的 `- [ ]` 改成 `- [x]`（`sdd-workflow` 規則，方便追蹤進度）。
- 提交前 `flutter analyze` 須維持「No issues found!」。

## 動手改程式碼前的四點說明（`UI_DESIGN_RULES.md` 要求）

1. **改哪個 UI 元件**：`app/lib/screens/settings_screen.dart` 的 `SettingsScreen`——具體是 `_SettingsScreenState._buildThemeDot()` 這個私有 helper（畫「佈景」三顆主題預覽圓點），以及呼叫它的「佈景」`ListTile`。不是新畫面，是既有畫面的既有元件。
2. **為什麼要改**：(a) 三顆主題預覽圓點目前各自寫死一組獨立示意色（`Color(0xFFF5F5F5)`／`Color(0xFF121212)`／`Color(0xFFF4ECD8)`），跟 `resolveThemeData()` 經 Issue 2 對齊 `DESIGN.md` §1.1 後的實際色值是兩份不同資料，「預覽長什麼樣」跟「選了之後實際長什麼樣」會出現落差；(b) E-Ink 鎖定視覺目前用 `Opacity(0.4)`，不符合 `DESIGN.md` §17.2 規定的虛線邊框手法，且降低透明度的漸層效果在電子紙上比高對比虛線更容易產生殘影，違反 E-Ink 模式本身想解決的問題；(c) 未選取圓點的邊框目前寫死 `Colors.grey.withValues(alpha: 0.5)`，是這個檔案唯一殘留的寫死顏色；(d) 鎖定狀態下缺乏提示文字與完整 Semantics 標籤，螢幕報讀機使用者無法得知「這是鎖定狀態」與「底下選的是哪個主題」。
3. **哪些畫面依賴它**：只有 `SettingsScreen` 這一個畫面（`_buildThemeDot()` 是私有 helper，未被其他檔案呼叫）；唯一的測試依賴是 `app/test/screens/settings_screen_test.dart`。
4. **是否影響 business logic**：不影響。純視覺色票來源與鎖定狀態的視覺／無障礙呈現調整，`onThemeChanged`／`onEinkModeChanged` 既有回呼邏輯、`AppTheme` 列舉、資料流與持久化完全不變。

---

### Task 1: 主題預覽圓點改讀 `resolveThemeData()` 真實色值＋移除 `Colors.grey` 殘留

**Files:**
- Modify: `app/lib/screens/settings_screen.dart`（頂部 import 區塊；「佈景」`ListTile` 三個 `_buildThemeDot(...)` 呼叫點，原第 97-102 行；`_buildThemeDot()` 本體，原第 229-255 行）
- Test: `app/test/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes: `resolveThemeData({required AppTheme theme, required bool isEinkMode}) -> ThemeData`（`app/lib/theme/app_theme_data.dart`，Issue 2 已完成，四套主題色值已對齊 `DESIGN.md` §1.1）。
- Produces: `_buildThemeDot(BuildContext context, AppTheme theme, String key)` 新簽章（拿掉原本的 `Color color` 參數）——Task 2 沿用這個簽章，只改函式內部邏輯，不再變更參數列。

- [x] **Step 1: 寫失敗的測試——圓點色值來源改讀 `resolveThemeData()`**

在 `app/test/screens/settings_screen_test.dart` 第 13 行 `import 'package:elinkbook/theme/app_theme.dart';` 之後新增一行：

```dart
import 'package:elinkbook/theme/app_theme_data.dart';
```

在檔案最後一個 `testWidgets`（`'SettingsScreen 顯示 E-Ink 模式開關...'`，原第 285-303 行）之後、最外層 `main()` 的收尾 `}` 之前，新增：

```dart
  testWidgets(
      'SettingsScreen 主題預覽圓點改讀 resolveThemeData() 的實際色值（不再維持寫死近似值）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.dark,
      ),
    ));

    final lightPreview =
        resolveThemeData(theme: AppTheme.light, isEinkMode: false);
    final darkPreview =
        resolveThemeData(theme: AppTheme.dark, isEinkMode: false);
    final sepiaPreview =
        resolveThemeData(theme: AppTheme.sepia, isEinkMode: false);

    BoxDecoration decorationFor(String key) => tester
        .widget<Container>(find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(Container),
        ))
        .decoration as BoxDecoration;

    final light = decorationFor('settings_theme_dot_light');
    final dark = decorationFor('settings_theme_dot_dark');
    final sepia = decorationFor('settings_theme_dot_sepia');

    expect(light.color, lightPreview.scaffoldBackgroundColor);
    expect(dark.color, darkPreview.scaffoldBackgroundColor);
    expect(sepia.color, sepiaPreview.scaffoldBackgroundColor);

    // currentTheme 為 dark：dark 圓點是選取狀態，邊框讀取 dark 主題自己的
    // primary；light／sepia 未選取，邊框讀取各自主題自己的 outline
    // （取代原本寫死的 Colors.grey）。
    expect(
        (dark.border as Border).top.color, darkPreview.colorScheme.primary);
    expect(
        (light.border as Border).top.color, lightPreview.colorScheme.outline);
    expect(
        (sepia.border as Border).top.color, sepiaPreview.colorScheme.outline);
  });
```

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/screens/settings_screen_test.dart`
Expected: 新增的測試 FAIL（`light.color`／`dark.color`／`sepia.color` 目前是呼叫端寫死的 `Color(0xFFF5F5F5)`／`Color(0xFF121212)`／`Color(0xFFF4ECD8)`，跟 `resolveThemeData()` 的 `scaffoldBackgroundColor` 不同值）。

- [x] **Step 3: 實作——`_buildThemeDot()` 改讀 `resolveThemeData()`，移除 `Colors.grey` 殘留**

在 `app/lib/screens/settings_screen.dart` 頂部 `import '../theme/app_theme.dart';`（原第 10 行）之後新增：

```dart
import '../theme/app_theme_data.dart';
```

把「佈景」`ListTile` 內三個呼叫點（原第 97-102 行）：

```dart
                _buildThemeDot(context, AppTheme.light,
                    const Color(0xFFF5F5F5), 'settings_theme_dot_light'),
                _buildThemeDot(context, AppTheme.dark,
                    const Color(0xFF121212), 'settings_theme_dot_dark'),
                _buildThemeDot(context, AppTheme.sepia,
                    const Color(0xFFF4ECD8), 'settings_theme_dot_sepia'),
```

改為：

```dart
                _buildThemeDot(context, AppTheme.light,
                    'settings_theme_dot_light'),
                _buildThemeDot(context, AppTheme.dark,
                    'settings_theme_dot_dark'),
                _buildThemeDot(context, AppTheme.sepia,
                    'settings_theme_dot_sepia'),
```

把 `_buildThemeDot()` 本體（原第 229-255 行）：

```dart
  Widget _buildThemeDot(
      BuildContext context, AppTheme theme, Color color, String key) {
    final isSelected = widget.currentTheme == theme && !widget.isEinkMode;
    return GestureDetector(
      key: Key(key),
      onTap:
          widget.isEinkMode ? null : () => widget.onThemeChanged?.call(theme),
      child: Opacity(
        opacity: widget.isEinkMode ? 0.4 : 1.0,
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.withValues(alpha: 0.5),
              width: isSelected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
```

改為：

```dart
  Widget _buildThemeDot(BuildContext context, AppTheme theme, String key) {
    final previewTheme = resolveThemeData(theme: theme, isEinkMode: false);
    final isSelected = widget.currentTheme == theme && !widget.isEinkMode;
    return GestureDetector(
      key: Key(key),
      onTap:
          widget.isEinkMode ? null : () => widget.onThemeChanged?.call(theme),
      child: Opacity(
        opacity: widget.isEinkMode ? 0.4 : 1.0,
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: previewTheme.scaffoldBackgroundColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? previewTheme.colorScheme.primary
                  : previewTheme.colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
```

（`Opacity(0.4)` 鎖定手法在這個 Task 刻意原樣保留，Task 2 才會把它換成虛線邊框——這個 Task 只處理色值來源。）

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/screens/settings_screen_test.dart`
Expected: PASS（本檔案全部測試皆過，含既有的主題圓點點擊測試，無回歸）。

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/settings_screen.dart app/test/screens/settings_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 3 Task 1 — 主題預覽圓點改讀 resolveThemeData() 真實色值

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ue4QKXFUDw4c8F8wzQJzGn
EOF
)"
```

---

### Task 2: E-Ink 鎖定視覺改為 `DESIGN.md` §17.2 虛線邊框＋提示文字＋Semantics 標籤

**Files:**
- Modify: `app/lib/screens/settings_screen.dart`（「佈景」`ListTile`；`_buildThemeDot()`；檔案末尾新增 `_themeLabel()` helper 與 `_LockedDotBorderPainter` 類別）
- Test: `app/test/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 產出的 `_buildThemeDot(BuildContext context, AppTheme theme, String key)` 簽章（本 Task 不再變更參數列，只改函式內部實作）。
- Produces: 新增私有 `String _themeLabel(AppTheme theme)`（回傳 `'淺色'`／`'深色'`／`'羊皮紙'`）與 `class _LockedDotBorderPainter extends CustomPainter`（建構參數 `{required Color color, required double strokeWidth}`），僅供本檔案內部使用，不對外暴露。

- [x] **Step 1: 寫失敗的測試——鎖定視覺、提示文字、Semantics 標籤**

在 `app/test/screens/settings_screen_test.dart`、Task 1 新增的測試之後，追加：

在 `app/test/screens/settings_screen_test.dart` 頂部新增一行 import（`SemanticsAction` 需要這個 import）：

```dart
import 'package:flutter/semantics.dart';
```

```dart
  testWidgets(
      'SettingsScreen E-Ink 開啟時，主題預覽圓點呈現虛線邊框，不再降低透明度，'
      '且依目前選擇的主題呈現粗細差異（DESIGN.md §17.2／§7.2）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.light,
        isEinkMode: true,
      ),
    ));

    // 不再有 Opacity 包裹圓點（原本的降低透明度手法已移除）。
    expect(
      find.descendant(
        of: find.byKey(const Key('settings_theme_dot_light')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );

    // 鎖定狀態下 Container 不再設定 border（虛線改由疊加的 CustomPaint
    // 繪製）。
    final decoration = tester
        .widget<Container>(find.descendant(
          of: find.byKey(const Key('settings_theme_dot_light')),
          matching: find.byType(Container),
        ))
        .decoration as BoxDecoration;
    expect(decoration.border, isNull);

    CustomPaint customPaintFor(String key) => tester.widget<CustomPaint>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(CustomPaint),
          ),
        );

    // currentTheme 為 light：light 圓點是「目前選擇」，虛線用粗線
    // （3dp）；dark／sepia 未選擇，虛線用細線（1.5dp）——沿用 DESIGN.md
    // §7.2 既有定義的「Border Width 1.5dp -> 3dp」數值，讓鎖定狀態下仍能
    // 分辨原本選的是哪個主題。`_LockedDotBorderPainter` 是本檔案私有類
    // 別，測試檔無法用型別直接存取，改以 dynamic 讀取其公開欄位
    // strokeWidth。
    // ignore: avoid_dynamic_calls
    expect(
        (customPaintFor('settings_theme_dot_light').painter as dynamic)
            .strokeWidth,
        3.0);
    // ignore: avoid_dynamic_calls
    expect(
        (customPaintFor('settings_theme_dot_dark').painter as dynamic)
            .strokeWidth,
        1.5);

    // 提示文字「這裡選的是關閉 E-Ink 後要恢復的主題」顯示。
    expect(find.byKey(const Key('settings_theme_locked_hint')), findsOneWidget);
  });

  testWidgets(
      'SettingsScreen 主題預覽圓點在 E-Ink 開啟時，Semantics 標籤讀出鎖定狀態與目前選擇的主題',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.sepia,
        isEinkMode: true,
      ),
    ));

    final semantics = tester
        .getSemantics(find.byKey(const Key('settings_theme_dot_light')));
    expect(semantics.label, contains('已鎖定'));
    expect(semantics.label, contains('羊皮紙'));

    handle.dispose();
  });

  testWidgets(
      'SettingsScreen 主題預覽圓點在「未鎖定」狀態下仍保有可啟動的 Semantics tap 動作'
      '（回歸保護：Semantics 不得整包排除子樹語意，見 reviews/review-plan-issue-3.md Critical 1）',
      (tester) async {
    final handle = tester.ensureSemantics();
    AppTheme? receivedTheme;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.light,
        isEinkMode: false,
        onThemeChanged: (theme) => receivedTheme = theme,
      ),
    ));

    final semantics = tester
        .getSemantics(find.byKey(const Key('settings_theme_dot_sepia')));
    // SemanticsNode 本身沒有 hasAction()，要透過 getSemanticsData() 取得
    // SemanticsData 才有這個方法（已核對 Flutter SDK
    // src/semantics/semantics.dart 原始碼確認）。
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue);

    await tester.tap(find.byKey(const Key('settings_theme_dot_sepia')));
    await tester.pumpAndSettle();
    expect(receivedTheme, AppTheme.sepia);

    handle.dispose();
  });

  testWidgets('SettingsScreen E-Ink 關閉時，不顯示鎖定提示文字，圓點維持一般邊框', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.light,
        isEinkMode: false,
      ),
    ));

    expect(find.byKey(const Key('settings_theme_locked_hint')), findsNothing);

    final decoration = tester
        .widget<Container>(find.descendant(
          of: find.byKey(const Key('settings_theme_dot_light')),
          matching: find.byType(Container),
        ))
        .decoration as BoxDecoration;
    expect(decoration.border, isNotNull);
  });

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/screens/settings_screen_test.dart`
Expected: 新增的 4 則測試裡，**2 則 FAIL**：
  - 「呈現虛線邊框...粗細差異」測試：`expect(..., findsNothing)`（`Opacity` 仍在）會是第一個失敗並中止該 `test()` 的斷言，後續的 `border`／`CustomPaint`／`strokeWidth`／提示文字斷言在這次執行不會真的被跑到。
  - 「Semantics 標籤讀出鎖定狀態」測試：FAIL，因為目前 `_buildThemeDot()` 完全沒有 `Semantics` 包裹，`label` 讀不到「已鎖定」「羊皮紙」這些文字。

  另外 **2 則在 Task 1 完成後的程式碼上就已經通過**，不是本步驟要驗證失敗的對象，是鎖定既有行為的迴歸保護測試：
  - 「未鎖定狀態下仍保有可啟動的 Semantics tap 動作」測試：`GestureDetector(onTap: ...)` 在沒有額外 `Semantics` 包裹的情況下本來就會貢獻 `SemanticsAction.tap`，這則測試現在就會通過——它存在的目的是防止 Step 3 實作時不小心把這個動作弄丟（見上方 Critical 1 的教訓）。
  - 「E-Ink 關閉時，不顯示鎖定提示文字，圓點維持一般邊框」測試：`ListTile` 目前沒有 `subtitle`（key 天經地義找不到）、`_buildThemeDot()` 在 `isEinkMode: false` 時本來就無條件設定 `border`（非 `null`），兩個條件都已成立。

- [x] **Step 3: 實作——虛線邊框畫家、鎖定提示文字、Semantics 標籤**

在 `app/lib/screens/settings_screen.dart` 檔案最末尾（`class _SettingsScreenState` 的收尾 `}` 之後）新增：

```dart
/// E-Ink 鎖定狀態的圓形虛線邊框（`DESIGN.md` §17.2：邊框改為虛線，取代
/// 原本的降低透明度手法）。`strokeWidth` 由呼叫端依「是否為目前選擇的
/// 主題」傳入 `3`／`1.5`——沿用 §7.2 既有定義的「Border Width 1.5dp ->
/// 3dp」離散狀態變更數值，不是本工單另外自訂，用意是讓鎖定狀態下仍能
/// 分辨原本選的是哪個主題。虛線本身的 dash／gap 長度 `DESIGN.md` 未給
/// 精確數字，本工單自行決定為 3dp／3dp；若下一輪真機驗證發現電子紙上
/// 不夠清楚，這個數字是可直接調整的錨點。
class _LockedDotBorderPainter extends CustomPainter {
  const _LockedDotBorderPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  static const double _dashLength = 3;
  static const double _gapLength = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashLength;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LockedDotBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
```

把「佈景」`ListTile`（Task 1 完成後的樣子）：

```dart
          ListTile(
            title: const Text('佈景'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildThemeDot(context, AppTheme.light,
                    'settings_theme_dot_light'),
                _buildThemeDot(context, AppTheme.dark,
                    'settings_theme_dot_dark'),
                _buildThemeDot(context, AppTheme.sepia,
                    'settings_theme_dot_sepia'),
              ],
            ),
          ),
```

改為：

```dart
          ListTile(
            title: const Text('佈景'),
            subtitle: widget.isEinkMode
                ? const Text(
                    '這裡選的是關閉 E-Ink 後要恢復的主題',
                    key: Key('settings_theme_locked_hint'),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildThemeDot(context, AppTheme.light,
                    'settings_theme_dot_light'),
                _buildThemeDot(context, AppTheme.dark,
                    'settings_theme_dot_dark'),
                _buildThemeDot(context, AppTheme.sepia,
                    'settings_theme_dot_sepia'),
              ],
            ),
          ),
```

把 `_buildThemeDot()`（Task 1 完成後的樣子）：

```dart
  Widget _buildThemeDot(BuildContext context, AppTheme theme, String key) {
    final previewTheme = resolveThemeData(theme: theme, isEinkMode: false);
    final isSelected = widget.currentTheme == theme && !widget.isEinkMode;
    return GestureDetector(
      key: Key(key),
      onTap:
          widget.isEinkMode ? null : () => widget.onThemeChanged?.call(theme),
      child: Opacity(
        opacity: widget.isEinkMode ? 0.4 : 1.0,
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: previewTheme.scaffoldBackgroundColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? previewTheme.colorScheme.primary
                  : previewTheme.colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
```

改為：

```dart
  Widget _buildThemeDot(BuildContext context, AppTheme theme, String key) {
    final previewTheme = resolveThemeData(theme: theme, isEinkMode: false);
    final locked = widget.isEinkMode;
    // isCurrentTheme 跟既有的 isSelected 是兩個不同概念：isSelected 只在
    // 「未鎖定」時才有意義（鎖定時 onTap 已經是 null，不需要選取樣式）；
    // isCurrentTheme 不受鎖定與否影響，鎖定時的虛線粗細差異要靠它才能
    // 分辨「原本選的是哪個主題」。
    final isCurrentTheme = widget.currentTheme == theme;
    final isSelected = isCurrentTheme && !locked;
    return Semantics(
      label: locked
          ? '${_themeLabel(theme)}佈景，已鎖定，這裡選的是關閉 E-Ink 後要恢復的主題，'
              '目前選擇：${_themeLabel(widget.currentTheme)}'
          : '${_themeLabel(theme)}佈景',
      button: !locked,
      child: GestureDetector(
        key: Key(key),
        onTap: locked ? null : () => widget.onThemeChanged?.call(theme),
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: previewTheme.scaffoldBackgroundColor,
            shape: BoxShape.circle,
            border: locked
                ? null
                : Border.all(
                    color: isSelected
                        ? previewTheme.colorScheme.primary
                        : previewTheme.colorScheme.outline,
                    width: isSelected ? 2 : 1,
                  ),
          ),
          child: locked
              ? CustomPaint(
                  painter: _LockedDotBorderPainter(
                    color: Theme.of(context).colorScheme.onSurface,
                    strokeWidth: isCurrentTheme ? 3 : 1.5,
                  ),
                )
              : null,
        ),
      ),
    );
  }
```

（拿掉了原草稿裡的 `excludeSemantics: true`——`Semantics(label:, button:, child: GestureDetector(onTap:, ...))` 在不排除子樹語意的情況下，外層宣告的屬性會跟子樹〔`GestureDetector` 貢獻的 `SemanticsAction.tap`〕**合併**成同一個語意節點，同時保有 label／button 描述與可啟動的 tap 動作。原草稿的 `excludeSemantics: true` 會把子樹的 tap 動作整個丟掉、且未鎖定狀態沒有補上替代動作，導致螢幕報讀機使用者在「未鎖定」時反而按不動這三顆圓點——這牴觸 `DESIGN.md` §17.2「僅移除互動語意」只限定在鎖定狀態的原意。見 `reviews/review-plan-issue-3.md` Critical 1。）

在 `_buildThemeDot()` 之後新增：

```dart
  /// 主題預覽圓點的中文名稱，供 E-Ink 鎖定狀態下的 Semantics 標籤朗讀。
  String _themeLabel(AppTheme theme) => switch (theme) {
        AppTheme.light => '淺色',
        AppTheme.dark => '深色',
        AppTheme.sepia => '羊皮紙',
      };
```

（鎖定時 `Theme.of(context).colorScheme.onSurface` 讀的是 App 目前實際套用的主題——鎖定狀態下 App 一律套用 E-Ink 主題，`onSurface` 為純黑，這是刻意的：虛線邊框要呈現「目前 UI 實際處於什麼樣子」，跟圓點本身的 `previewTheme`〔該圓點所代表的主題〕是兩件不同的事，不能混用。）

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/screens/settings_screen_test.dart`
Expected: PASS（本檔案全部測試皆過，含既有的 E-Ink 模式下停用點擊測試，無回歸）。

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/settings_screen.dart app/test/screens/settings_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 3 Task 2 — E-Ink 鎖定視覺改為虛線邊框＋提示文字＋Semantics 標籤

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ue4QKXFUDw4c8F8wzQJzGn
EOF
)"
```

---

## 全部 Task 完成後

- [x] 執行完整 `flutter test`（於 `app/` 目錄下，不帶檔案路徑），確認全專案無回歸。
- [x] 執行 `flutter analyze`，確認「No issues found!」。
- [x] 把 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 3 的 `Status` 從 `ready-for-agent` 更新為完成狀態（依當時 Epic 慣例用語），並在 `epic.md` 補一筆開發記錄。
- [x] 依 `sdd-workflow` 流程，發起 `/superpowers:requesting-code-review` 審查本次程式碼變更（`BASE_SHA`／`HEAD_SHA` 取本工單 2 個 commit 的起訖），審查報告存 `docs/epics/epic-35-design-system-tokens/reviews/review-issue-3.md`。
- [x] 提醒：鎖定狀態下圓點虛線的粗細（選取 3dp／未選取 1.5dp）沿用 `DESIGN.md` §7.2 既有定義的數值，不是本工單自訂；但虛線本身的 dash／gap 長度（3dp／3dp）是本工單自行決定的具體詮釋，`DESIGN.md` 沒有給精確數字。比照 Issue 2 `SwitchThemeData` 補強的既有慣例，整體手法尚未經過真機驗證，需要下一輪真機驗證（比照 `epic-18`／`epic-25` 慣例）確認在電子紙上確實可辨識，不在本工單驗收範圍內完成。
