# Epic 35 — Issue 5：`nav_zone_settings_screen.dart`（電子紙可辨識度補強第二處＋其餘遷移） Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `NavZoneSettingsScreen`（`app/lib/screens/nav_zone_settings_screen.dart`）內 3 處直接讀取 `Theme.of(context).dividerColor` 畫熱區範本卡片邊框／自訂編輯器格線的地方，改為直接讀取 `Theme.of(context).colorScheme.onSurface`；並把檔案內僅剩的 2 處寫死 `Colors.grey.shade100`（`navZoneTemplateIconColor()` 的未知圖示回退值、`_buildTemplateCard()` 中間欄無圖示時的佔位色）遷移為 `colorScheme.surfaceContainerHighest`，讓檔案內無任何寫死顏色殘留。

**Architecture:** 兩類獨立的修法，各自一個 Task：Task 1 處理 3 處 `dividerColor`（Issue 2 移除四套主題顯式 `dividerColor` 覆寫後，它會退回解析到 `colorScheme.outline`；Dark 主題的 `outline` 新值跟 `surface` 亮度差縮小，電子紙上可能難以辨識這 3 處邊框／格線），修法是把讀取來源換成 `colorScheme.onSurface`。Task 2 處理 `navZoneTemplateIconColor()` 這個頂層純函式——它目前不吃 `BuildContext`／`ColorScheme`，遇到不認得的圖示時寫死回傳 `Colors.grey.shade100`；修法是幫函式加一個 `ColorScheme colorScheme` 參數，未知圖示分支改回傳 `colorScheme.surfaceContainerHighest`，呼叫端（`_buildTemplateCard()` 的 3 個呼叫點，含中間欄 `middleIcon == null` 的獨立分支）改傳入 `Theme.of(context).colorScheme`。兩個 Task 修改的程式碼區域完全不重疊（Task 1 動 L227-235／L313-321／L348-350；Task 2 動 L8-20 與 L236-262），先做哪個都不影響另一個的行號正確性。`NavZoneSettingsScreen` 的公開建構參數（`prefsManager`）全程不變。

**Tech Stack:** Flutter／Dart，`flutter_test`（widget test／plain `test()`，比照 `test/screens/nav_zone_settings_screen_test.dart` 既有慣例），`ThemeData`／`ColorScheme`／`BoxDecoration`／`Border` 皆為既有 Flutter SDK API，不新增任何 pub 套件依賴。

**Spec:** `docs/epics/epic-35-design-system-tokens/spec.md`（§「電子紙可辨識度補強機制」第二段〔`nav_zone_settings_screen.dart` 3 處 `dividerColor` 決議〕、§「寫死顏色遷移」、§「Testing Decisions」）；工單摘要見 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 5。

**範圍決定（已與人類確認，非本計劃自行認定）：** 本計劃第一版曾主張「`navZoneTemplateIconColor()` 的灰色回退值與中間欄無圖示佔位色屬於跟主題無關的裝飾配色，刻意不遷移」，但 `issues.md` Issue 5 的「驗收標準」與「Solution」都沒有任何但書條款地要求「無寫死顏色殘留」「其餘 `Colors.grey`／`black45`／`white70` 家族依用途遷移」；經 `/superpowers:requesting-code-review` 獨立審查（`reviews/review-plan-issue-5.md`）指出這個排除沒有 `spec.md`／`issues.md` 事先授權（不同於 Issue 4／6／7 的排除都寫在規格文件本身），提請人類決策者確認後，**改為一併遷移**。技術設計見 Task 2。（逐行核對 `nav_zone_settings_screen.dart` 全檔共 377 行，確認 `Colors.grey` 家族只出現原 L19／L248 這 2 處，`black45`／`white70` 兩個家族全檔不存在。）

## Global Constraints

- 依賴 Issue 2 已完成：`resolveThemeData()` 四套主題的 `ColorScheme` 已對齊 `DESIGN.md` §1.1，Dark 主題 `outline`（`#2c2c34`）與 `surface`（`#1d1d22`）亮度差已縮小，本工單直接引用這個既成事實作為 Task 1 的修改動機，不重新定義任何色值。
- Task 1 的 3 處修法完全一致：把 `Theme.of(context).dividerColor` 換成 `Theme.of(context).colorScheme.onSurface`，不透過 `dividerColor` 這個間接屬性、不新增元件層級 `DividerThemeData`／`ThemeExtension` 覆寫。
- Task 2 的 `navZoneTemplateIconColor()` 既有紅／藍／綠三個分支（`chevron_left`／`chevron_right`／`menu`）維持寫死 `Colors.red.shade100`／`Colors.blue.shade100`／`Colors.green.shade100` 不變——這三色是 `epic-18-reader-device-qa Issue 44` 訂下、跟主題無關的固定裝飾配色，`issues.md` Issue 5 沒有要求連這三色也遷移，只有第 4 個「其餘/未知」分支（灰色）與中間欄無圖示佔位色需要遷移。
- `NavZoneSettingsScreen` 的公開建構參數（`prefsManager`）不變；`GlobalReaderPrefs`／`NavZoneMode`／`ZoneAction` 等資料模型完全不變——本工單純粹是顏色來源調整，不影響任何 business logic。
- 本工單只碰 `app/lib/screens/nav_zone_settings_screen.dart` 與 `app/test/screens/nav_zone_settings_screen_test.dart`，不碰其他畫面檔案；不碰 OPDS／WebDAV／雲端來源實作／書籍儲存／閱讀進度持久化。
- 所有 Dart 原始碼註解使用正體中文。
- 每個 Task 完成後跑 `flutter test test/screens/nav_zone_settings_screen_test.dart`（於 `app/` 目錄下），不需要整套 `flutter test`；整份計劃最後一個 Task 完成時才跑一次完整 `flutter test`（見 `CLAUDE.md`「測試執行範圍」）。
- 每個 Task 的 Step 完成後，把本檔案對應的 `- [ ]` 改成 `- [x]`（`sdd-workflow` 規則，方便追蹤進度）。
- 提交前 `flutter analyze` 須維持「No issues found!」。

## 動手改程式碼前的四點說明（`UI_DESIGN_RULES.md` 要求）

1. **改哪個 UI 元件**：`app/lib/screens/nav_zone_settings_screen.dart` 的 `NavZoneSettingsScreen`——具體是 3 個私有 build 方法內的邊框／格線顏色來源（`_buildTemplateCard()`／`_buildOneHandTemplateCard()`／`_buildCustomEditor()`，Task 1），以及頂層純函式 `navZoneTemplateIconColor()` 與其在 `_buildTemplateCard()` 的呼叫端（Task 2）。不是新畫面，是既有畫面既有元件的顏色來源調整。
2. **為什麼要改**：(a) Issue 2 把四個 `_build*Theme()` 顯式設定的 `dividerColor` 移除後，`Theme.of(context).dividerColor` 會退回解析到 `colorScheme.outline`；Dark 主題的 `outline` 改採 `DESIGN.md` 色表值後跟 `surface` 亮度差大幅縮小，這 3 處邊框／格線在電子紙裝置的 Dark 主題下可能難以辨識，改讀 `colorScheme.onSurface` 是 `spec.md`「電子紙可辨識度補強機制」段落訂下的統一修法。(b) `navZoneTemplateIconColor()` 的灰色回退值與中間欄無圖示佔位色是檔案內僅剩的寫死顏色殘留，`issues.md` Issue 5 明文要求「無寫死顏色殘留」「依用途遷移」，沒有例外條款。
3. **哪些畫面依賴它**：只有 `NavZoneSettingsScreen` 這一個畫面（涉及的 build 方法皆為私有 helper；`navZoneTemplateIconColor()` 雖是頂層公開函式，但已 grep 確認全專案只有本檔案與其測試檔引用，未被其他畫面 import）。唯一的測試依賴是 `app/test/screens/nav_zone_settings_screen_test.dart`。
4. **是否影響 business logic**：不影響。純視覺邊框／格線／佔位色顏色來源調整，`_selectMode()`／`_toggleDebugOverlay()`／`_cycleCell()`／`_saveCustomActions()`／`isValidCustomZoneConfig()` 等既有邏輯、`GlobalReaderPrefs`／`NavZoneMode`／`ZoneAction` 資料模型與持久化流程完全不變。

---

### Task 1: 三處 `dividerColor` 改讀 `colorScheme.onSurface`

**Files:**
- Modify: `app/lib/screens/nav_zone_settings_screen.dart`（`_buildTemplateCard()` 原 L227-235；`_buildOneHandTemplateCard()` 原 L313-321；`_buildCustomEditor()` 原 L348-350）
- Test: `app/test/screens/nav_zone_settings_screen_test.dart`

**Interfaces:**
- Consumes: 無新介面——`Theme.of(context).colorScheme.onSurface` 為既有 Flutter `ColorScheme` API，`resolveThemeData()` 產出的四套主題皆已提供這個角色（Issue 2 已完成）。
- Produces: 無新介面——不新增／不變更任何函式簽章或公開建構參數。

- [x] **Step 1: 寫失敗的測試——更新既有斷言＋新增 2 則覆蓋範本卡片與自訂編輯器格線**

在 `app/test/screens/nav_zone_settings_screen_test.dart` 中，把既有測試（原第 132-159 行）：

```dart
  testWidgets('選中的模板卡片顯示 primary 色外框，未選中則為預設 dividerColor 外框', (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(navZoneMode: NavZoneMode.leftFlip),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NavZoneSettingsScreen));
    final primaryColor = Theme.of(context).colorScheme.primary;
    final dividerColor = Theme.of(context).dividerColor;

    final leftFlipCard = tester.widget<Container>(
      find.byKey(const Key('nav_zone_mode_leftFlip')),
    );
    final leftFlipBorder =
        (leftFlipCard.decoration as BoxDecoration).border as Border;
    expect(leftFlipBorder.top.color, primaryColor);

    final rightFlipCard = tester.widget<Container>(
      find.byKey(const Key('nav_zone_mode_rightFlip')),
    );
    final rightFlipBorder =
        (rightFlipCard.decoration as BoxDecoration).border as Border;
    expect(rightFlipBorder.top.color, dividerColor);
  });
```

改為：

```dart
  testWidgets(
      '選中的模板卡片顯示 primary 色外框，未選中則讀取 colorScheme.onSurface 外框'
      '（epic-35-design-system-tokens Issue 5：不再透過 dividerColor 間接讀取，'
      'Dark 主題下 dividerColor 會退回跟 outline 同值、電子紙可辨識度不足）',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(navZoneMode: NavZoneMode.leftFlip),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NavZoneSettingsScreen));
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;

    final leftFlipCard = tester.widget<Container>(
      find.byKey(const Key('nav_zone_mode_leftFlip')),
    );
    final leftFlipBorder =
        (leftFlipCard.decoration as BoxDecoration).border as Border;
    expect(leftFlipBorder.top.color, primaryColor);

    final rightFlipCard = tester.widget<Container>(
      find.byKey(const Key('nav_zone_mode_rightFlip')),
    );
    final rightFlipBorder =
        (rightFlipCard.decoration as BoxDecoration).border as Border;
    expect(rightFlipBorder.top.color, onSurfaceColor);
  });
```

在這則測試之後，緊接著新增 2 則測試（涵蓋 `_buildOneHandTemplateCard()` 與 `_buildCustomEditor()` 的邊框／格線來源；`oneHand` 測試比照下方 Minor 建議，顯式指定 `navZoneMode`，不依賴 `GlobalReaderPrefs.initial()` 的預設值）：

```dart
  testWidgets(
      '未選中的「單手」模板卡片外框讀取 colorScheme.onSurface'
      '（epic-35-design-system-tokens Issue 5，比照左右翻頁模板卡片同一補強）',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial()
          .copyWith(navZoneMode: NavZoneMode.rightFlip),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NavZoneSettingsScreen));
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;

    final oneHandCard = tester.widget<Container>(
      find.byKey(const Key('nav_zone_mode_oneHand')),
    );
    final oneHandBorder =
        (oneHandCard.decoration as BoxDecoration).border as Border;
    expect(oneHandBorder.top.color, onSurfaceColor);
  });

  testWidgets(
      '自訂模式 9 格編輯器格線外框讀取 colorScheme.onSurface'
      '（epic-35-design-system-tokens Issue 5）',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);

    final fakeManager = FakeReaderPrefsManager(
      globalPrefs:
          const GlobalReaderPrefs.initial().copyWith(navZoneMode: NavZoneMode.custom),
    );
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NavZoneSettingsScreen));
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;

    final cell0 = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('nav_zone_custom_cell_0')),
        matching: find.byType(Container),
      ),
    );
    final cellBorder = (cell0.decoration as BoxDecoration).border as Border;
    expect(cellBorder.top.color, onSurfaceColor);
  });
```

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/screens/nav_zone_settings_screen_test.dart`
Expected: 3 則測試 FAIL：
  - 更新後的「選中的模板卡片顯示 primary 色外框...」：`rightFlipBorder.top.color` 目前仍是 `Theme.of(context).dividerColor` 解析出的值，跟 `onSurfaceColor` 在預設 `MaterialApp`（未指定 `theme:`）下是不同顏色。
  - 新增的「單手」模板卡片測試：`oneHandBorder.top.color` 目前仍讀 `dividerColor`。
  - 新增的自訂編輯器格線測試：`cellBorder.top.color` 目前仍讀 `dividerColor`。

- [x] **Step 3: 實作——3 處 `dividerColor` 改為 `colorScheme.onSurface`**

在 `app/lib/screens/nav_zone_settings_screen.dart` 的 `_buildTemplateCard()`（原 L227-235）：

```dart
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
```

改為：

```dart
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
            width: selected ? 2 : 1,
          ),
        ),
```

在 `_buildOneHandTemplateCard()`（原 L313-321）：

```dart
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
```

改為：

```dart
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
            width: selected ? 2 : 1,
          ),
        ),
```

在 `_buildCustomEditor()`（原 L348-350）：

```dart
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
```

改為：

```dart
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
```

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/screens/nav_zone_settings_screen_test.dart`
Expected: PASS（本檔案全部測試皆過，含既有的模式切換／自訂編輯器循環切換／驗證擋下等測試，無回歸）。

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/nav_zone_settings_screen.dart app/test/screens/nav_zone_settings_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 5 Task 1 — nav_zone_settings_screen.dart 三處 dividerColor 改讀 colorScheme.onSurface

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ue4QKXFUDw4c8F8wzQJzGn
EOF
)"
```

---

### Task 2: `navZoneTemplateIconColor()` 灰色回退值＋中間欄佔位色改讀 `colorScheme.surfaceContainerHighest`

**Files:**
- Modify: `app/lib/screens/nav_zone_settings_screen.dart`（`navZoneTemplateIconColor()` 頂層函式，原 L8-20；`_buildTemplateCard()` 內 3 個呼叫點，原 L236-262）
- Test: `app/test/screens/nav_zone_settings_screen_test.dart`

**Interfaces:**
- Consumes: 既有 Flutter SDK `ColorScheme` 型別（不需要 `ElinkTokens`——這 2 處是「無圖示/未知圖示時的中性淺色背景塊」，語意上對應 `ColorScheme.surfaceContainerHighest` 這個既有角色，不是 `ElinkTokens` 定義的語意色）。
- Produces: `navZoneTemplateIconColor(IconData icon, ColorScheme colorScheme)` 新簽章（原本只吃 `IconData icon` 一個參數）——本工單範圍內沒有其他檔案呼叫這個函式（已 grep 全專案確認，只有本檔案與其測試檔引用），不影響其他呼叫端。

- [x] **Step 1: 寫失敗的測試——`navZoneTemplateIconColor()` 新簽章與未知圖示回退值**

在 `app/test/screens/nav_zone_settings_screen_test.dart` 中，把既有 `group`（原第 388-400 行）：

```dart
  group('navZoneTemplateIconColor（epic-18-reader-device-qa Issue 44）', () {
    test('chevron_left 恆為紅色', () {
      expect(navZoneTemplateIconColor(Icons.chevron_left), Colors.red.shade100);
    });

    test('chevron_right 恆為藍色', () {
      expect(navZoneTemplateIconColor(Icons.chevron_right), Colors.blue.shade100);
    });

    test('menu 恆為綠色', () {
      expect(navZoneTemplateIconColor(Icons.menu), Colors.green.shade100);
    });
  });
```

改為：

```dart
  group('navZoneTemplateIconColor（epic-18-reader-device-qa Issue 44）', () {
    final colorScheme = ColorScheme.light();

    test('chevron_left 恆為紅色', () {
      expect(navZoneTemplateIconColor(Icons.chevron_left, colorScheme),
          Colors.red.shade100);
    });

    test('chevron_right 恆為藍色', () {
      expect(navZoneTemplateIconColor(Icons.chevron_right, colorScheme),
          Colors.blue.shade100);
    });

    test('menu 恆為綠色', () {
      expect(navZoneTemplateIconColor(Icons.menu, colorScheme),
          Colors.green.shade100);
    });

    test(
        '未知圖示時退回 colorScheme.surfaceContainerHighest'
        '（epic-35-design-system-tokens Issue 5，取代原本寫死的 Colors.grey.shade100；'
        '刻意改用跟上面三則測試不同的 ColorScheme 實例，確保斷言的是「有沒有正確傳遞'
        '參數」而不是巧合撞到同一個值）',
        () {
      final darkColorScheme = ColorScheme.dark();
      expect(
        navZoneTemplateIconColor(Icons.info, darkColorScheme),
        darkColorScheme.surfaceContainerHighest,
      );
    });
  });
```

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/screens/nav_zone_settings_screen_test.dart`
Expected: **編譯失敗**（不是執行期斷言失敗）——`navZoneTemplateIconColor()` 目前只接受 1 個參數，新測試呼叫時傳了 2 個參數，`flutter test` 會回報 `Too many positional arguments` 之類的編譯期錯誤。這是本 Task 唯一一個「紅燈」是編譯錯誤而非斷言失敗的 Step，符合預期（TDD 對簽章變更本來就會先看到編譯失敗）。

- [x] **Step 3: 實作——函式簽章加 `ColorScheme` 參數，未知圖示與中間欄佔位色改讀 `surfaceContainerHighest`**

在 `app/lib/screens/nav_zone_settings_screen.dart`，把 `navZoneTemplateIconColor()`（原 L8-20）：

```dart
/// 「簡單」模板卡片（`leftFlip`／`rightFlip`／`oneHand`）色塊配色表
/// （epic-18-reader-device-qa Issue 44，真機使用回報：`leftFlip`／
/// `rightFlip` 原本用「欄位位置」決定色塊顏色，導致同一個 `chevron_left`
/// 圖示在兩張卡片上顏色不同〔一個紅一個藍〕。改用「圖示本身」決定顏色，
/// 讓三張卡片的配色語意一致：綠＝選單、紅＝上一頁、藍＝下一頁，比照
/// `_buildOneHandTemplateCard()` 既有的配色慣例。抽成頂層純函式方便獨立
/// 測試與未來重用。
Color navZoneTemplateIconColor(IconData icon) {
  if (icon == Icons.chevron_left) return Colors.red.shade100;
  if (icon == Icons.chevron_right) return Colors.blue.shade100;
  if (icon == Icons.menu) return Colors.green.shade100;
  return Colors.grey.shade100;
}
```

改為：

```dart
/// 「簡單」模板卡片（`leftFlip`／`rightFlip`／`oneHand`）色塊配色表
/// （epic-18-reader-device-qa Issue 44，真機使用回報：`leftFlip`／
/// `rightFlip` 原本用「欄位位置」決定色塊顏色，導致同一個 `chevron_left`
/// 圖示在兩張卡片上顏色不同〔一個紅一個藍〕。改用「圖示本身」決定顏色，
/// 讓三張卡片的配色語意一致：綠＝選單、紅＝上一頁、藍＝下一頁，比照
/// `_buildOneHandTemplateCard()` 既有的配色慣例。抽成頂層純函式方便獨立
/// 測試與未來重用。紅／藍／綠三色是跟主題無關的固定裝飾編碼，維持寫死不變；
/// 未知圖示的回退值改讀 [colorScheme] 的 `surfaceContainerHighest`，取代原本
/// 寫死的 `Colors.grey.shade100`（epic-35-design-system-tokens Issue 5）。
Color navZoneTemplateIconColor(IconData icon, ColorScheme colorScheme) {
  if (icon == Icons.chevron_left) return Colors.red.shade100;
  if (icon == Icons.chevron_right) return Colors.blue.shade100;
  if (icon == Icons.menu) return Colors.green.shade100;
  return colorScheme.surfaceContainerHighest;
}
```

把 `_buildTemplateCard()` 內的 3 個呼叫點（原 L236-262）：

```dart
        child: Row(
          children: [
            Expanded(
              child: Container(
                color: navZoneTemplateIconColor(leftIcon),
                alignment: Alignment.center,
                child: Icon(leftIcon, size: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: middleIcon == null
                    ? Colors.grey.shade100
                    : navZoneTemplateIconColor(middleIcon),
                alignment: Alignment.center,
                child: middleIcon == null ? null : Icon(middleIcon, size: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: navZoneTemplateIconColor(rightIcon),
                alignment: Alignment.center,
                child: Icon(rightIcon, size: 16),
              ),
            ),
          ],
        ),
```

改為：

```dart
        child: Row(
          children: [
            Expanded(
              child: Container(
                color: navZoneTemplateIconColor(
                    leftIcon, Theme.of(context).colorScheme),
                alignment: Alignment.center,
                child: Icon(leftIcon, size: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: middleIcon == null
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : navZoneTemplateIconColor(
                        middleIcon, Theme.of(context).colorScheme),
                alignment: Alignment.center,
                child: middleIcon == null ? null : Icon(middleIcon, size: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: navZoneTemplateIconColor(
                    rightIcon, Theme.of(context).colorScheme),
                alignment: Alignment.center,
                child: Icon(rightIcon, size: 16),
              ),
            ),
          ],
        ),
```

（`middleIcon == null` 這個分支目前無法被任何現有呼叫路徑觸發——`_buildTemplateCard()` 僅有的 2 個呼叫點都固定傳 `middleIcon: Icons.menu`，見檔案 L170-183——本工單仍把字面值換成 token 以徹底清除寫死顏色殘留，但因為外部無法實際觸發這個分支渲染，不強制新增對應的 widget test；`surfaceContainerHighest` 這個角色本身已由上面 Step 1 新增的 `navZoneTemplateIconColor()` 未知圖示單元測試驗證過。）

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/screens/nav_zone_settings_screen_test.dart`
Expected: PASS（本檔案全部測試皆過，含 `colorOfIcon` 那則比對 `leftFlip`／`rightFlip` 卡片 `chevron_left`／`chevron_right` 色塊顏色一致的既有測試——它讀的是渲染後的 `Container.color`，紅／藍分支值沒有變動，不受影響）。

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/nav_zone_settings_screen.dart app/test/screens/nav_zone_settings_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 5 Task 2 — navZoneTemplateIconColor() 灰色回退值改讀 colorScheme.surfaceContainerHighest

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ue4QKXFUDw4c8F8wzQJzGn
EOF
)"
```

---

## 全部 Task 完成後

- [x] 執行完整 `flutter test`（於 `app/` 目錄下，不帶檔案路徑），確認全專案無回歸。
- [x] 執行 `flutter analyze`，確認「No issues found!」。
- [x] 把 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 5 的 `Status` 從 `ready-for-agent` 更新為完成狀態（依當時 Epic 慣例用語），並在 `epics.md` 補一筆開發記錄。
- [x] 依 `sdd-workflow` 流程，發起 `/superpowers:requesting-code-review` 審查本次程式碼變更（`BASE_SHA`／`HEAD_SHA` 取本工單 2 個 commit 的起訖），審查報告存 `docs/epics/epic-35-design-system-tokens/reviews/review-issue-5.md`。
- [x] 提醒：`colorScheme.onSurface` 邊框補強手法比照 Issue 2 `SwitchThemeData`、Issue 3 鎖定虛線邊框的既有慣例，尚未經過真機驗證，需要下一輪真機驗證（比照 `epic-18`／`epic-25` 慣例）確認在電子紙上確實可辨識，不在本工單驗收範圍內完成。
