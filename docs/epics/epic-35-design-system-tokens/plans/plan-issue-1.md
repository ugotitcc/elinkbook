# Epic 35 — Issue 1：`ElinkTokens` 類別本體＋`MaterialApp` 零時長主題轉場 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 建立 `ElinkTokens extends ThemeExtension<ElinkTokens>` 資料類別（`DESIGN.md` §1.2 骨架的正式定案版），並讓 `main.dart` 的 `MaterialApp` 明確設定 `themeAnimationDuration: Duration.zero`。這是 `epic-35-design-system-tokens` 後續所有 Issue 的地基。

**Architecture:** 本工單只建立獨立、自包含的資料類別本體，**不**修改 `resolveThemeData()` 或任何 `_build*Theme()`——`ElinkTokens` 此時還沒被任何主題實際使用，掛進 `ThemeData.extensions` 是 Issue 2 的範圍。`MaterialApp` 的零動畫轉場設定則是獨立、跟 `ElinkTokens` 本身無關的小改動，一併收在本工單完成。

**Tech Stack:** Flutter／Dart，`flutter_test`（widget test），既有 `ThemeExtension` API（`copyWith`／`lerp`）。

**Spec:** `docs/epics/epic-35-design-system-tokens/spec.md`（§「核心型別：ElinkTokens」、§「【審查新增】MaterialApp 零時長主題轉場」）；工單摘要見 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 1。

## Global Constraints

- 依循 `UI_DESIGN_RULES.md`：本 Epic 全程只碰 Theme／Design tokens，不碰 EPUB 解析／foliate-js／CFI／JS bridge／TTS/Read-along 同步／PocketBase 同步／OPDS／WebDAV／雲端來源實作／書籍儲存／閱讀進度持久化等核心架構清單。
- `resolveThemeData({required AppTheme theme, required bool isEinkMode}) -> ThemeData` 既有公開簽章不可變（本工單完全不碰這個函式）。
- 本工單**不**修改 `app/lib/theme/app_theme_data.dart` 任何一行——`ElinkTokens` 掛進四套 `ColorScheme` 是 Issue 2 的範圍，Task 1/2 建立的類別此時是「存在但還沒被使用」的狀態。
- 所有 Dart 原始碼註解使用正體中文。
- 每完成一個 Task 就跑一次該 Task 涉及的測試檔（不需要整套 `flutter test`），整份計劃最後一個 Task 完成時才跑一次完整 `flutter test`（見 `CLAUDE.md`「測試執行範圍」）。
- 每個 Task 的 Step 完成後，把本檔案對應的 `- [x]` 改成 `- [x]`（`sdd-workflow` 規則，方便追蹤進度）。
- 提交前 `flutter analyze` 須維持「No issues found!」。

## 動手改程式碼前的四點說明（`UI_DESIGN_RULES.md` 要求）

1. **改哪個 UI 元件**：(a) 新增 `app/lib/theme/elink_tokens.dart`——一個純資料類別（`ThemeExtension<ElinkTokens>` 子類別），不是 widget。(b) 修改 `app/lib/main.dart` 的 `ElinkBookApp` 內部 `build()` 方法裡建構 `MaterialApp` 的那一段，加一個建構參數。
2. **為什麼要改**：(a) `DESIGN.md` §1.2 定義的語意色（螢光筆黃/綠/藍、底線色、進度條、封面佔位色、徽章罩、TTS 高亮）跟 E-Ink 修飾子旗標目前完全沒有程式碼承載，各畫面只能各自寫死顏色，換一次主題無法保證全部畫面同步更新。(b) `MaterialApp` 目前沒設 `themeAnimationDuration`，Flutter 預設 200ms 交叉淡出動畫違反 `DESIGN.md` §18「零動畫轉場」規定，且在電子紙裝置上比瞬間切換更容易產生殘影。
3. **哪些畫面依賴它**：本工單完成後，`ElinkTokens` 類別本身還沒有任何畫面依賴它（要等 Issue 2 把它掛進 `resolveThemeData()` 才會生效）；`themeAnimationDuration` 影響的是全域——任何主題切換／E-Ink 開關動作經過的畫面（設定畫面、書架 E-Ink 切換鈕）都會受惠於零時長轉場。
4. **是否影響 business logic**：不影響。`ElinkTokens` 是純資料容器，沒有任何業務邏輯；`themeAnimationDuration` 只影響視覺轉場動畫時長，不影響任何資料流或狀態邏輯。

---

### Task 1: `ElinkTokens` 資料類別本體（欄位＋建構子＋`copyWith()`）

**Files:**
- Create: `app/lib/theme/elink_tokens.dart`
- Test: `app/test/theme/elink_tokens_test.dart`

**Interfaces:**
- Consumes: 無（獨立新類別，只依賴 Flutter SDK 的 `ThemeExtension<T>`／`Color`）。
- Produces: `ElinkTokens` 類別，欄位 `highlightYellow`／`highlightGreen`／`highlightBlue`／`underlineColor`／`progressTrack`／`coverPlaceholder`／`badgeScrim`／`ttsActiveHighlight`（皆 `Color`）、`isEink`／`reducedMotion`／`discretePaging`（皆 `bool`），`const` 建構子（全部具名必填參數）、`ElinkTokens copyWith({...})`（每個欄位對應同名選填具名參數）。Task 2 會在同一個類別上補 `lerp()`。

- [x] **Step 1: 寫失敗的測試——`copyWith()` 的三種情境**

建立 `app/test/theme/elink_tokens_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

const _base = ElinkTokens(
  highlightYellow: Color(0xFF111111),
  highlightGreen: Color(0xFF222222),
  highlightBlue: Color(0xFF333333),
  underlineColor: Color(0xFF444444),
  progressTrack: Color(0xFF555555),
  coverPlaceholder: Color(0xFF666666),
  badgeScrim: Color(0xFF777777),
  ttsActiveHighlight: Color(0xFF888888),
  isEink: false,
  reducedMotion: false,
  discretePaging: false,
);

void _expectAllFieldsEqual(ElinkTokens a, ElinkTokens b) {
  expect(a.highlightYellow, b.highlightYellow);
  expect(a.highlightGreen, b.highlightGreen);
  expect(a.highlightBlue, b.highlightBlue);
  expect(a.underlineColor, b.underlineColor);
  expect(a.progressTrack, b.progressTrack);
  expect(a.coverPlaceholder, b.coverPlaceholder);
  expect(a.badgeScrim, b.badgeScrim);
  expect(a.ttsActiveHighlight, b.ttsActiveHighlight);
  expect(a.isEink, b.isEink);
  expect(a.reducedMotion, b.reducedMotion);
  expect(a.discretePaging, b.discretePaging);
}

void main() {
  group('ElinkTokens.copyWith', () {
    test('不傳任何參數時，回傳的新實例所有欄位與原值相同', () {
      final copy = _base.copyWith();
      _expectAllFieldsEqual(copy, _base);
    });

    test('只覆寫單一 Color 欄位時，只有該欄位改變，其餘欄位維持原值', () {
      final copy = _base.copyWith(highlightYellow: const Color(0xFFAAAAAA));
      expect(copy.highlightYellow, const Color(0xFFAAAAAA));
      expect(copy.highlightGreen, _base.highlightGreen);
      expect(copy.highlightBlue, _base.highlightBlue);
      expect(copy.underlineColor, _base.underlineColor);
      expect(copy.progressTrack, _base.progressTrack);
      expect(copy.coverPlaceholder, _base.coverPlaceholder);
      expect(copy.badgeScrim, _base.badgeScrim);
      expect(copy.ttsActiveHighlight, _base.ttsActiveHighlight);
      expect(copy.isEink, _base.isEink);
      expect(copy.reducedMotion, _base.reducedMotion);
      expect(copy.discretePaging, _base.discretePaging);
    });

    test('只覆寫單一 bool 欄位時，只有該欄位改變，其餘欄位維持原值', () {
      final copy = _base.copyWith(isEink: true);
      expect(copy.isEink, true);
      expect(copy.reducedMotion, _base.reducedMotion);
      expect(copy.discretePaging, _base.discretePaging);
      expect(copy.highlightYellow, _base.highlightYellow);
    });

    test('同時覆寫多個欄位時，指定的欄位全部同時生效，其餘欄位不受影響', () {
      final copy = _base.copyWith(
        highlightBlue: const Color(0xFFBBBBBB),
        reducedMotion: true,
        badgeScrim: const Color(0xFFCCCCCC),
      );
      expect(copy.highlightBlue, const Color(0xFFBBBBBB));
      expect(copy.reducedMotion, true);
      expect(copy.badgeScrim, const Color(0xFFCCCCCC));
      // 沒指定的欄位維持原值
      expect(copy.highlightYellow, _base.highlightYellow);
      expect(copy.isEink, _base.isEink);
      expect(copy.discretePaging, _base.discretePaging);
    });
  });
}
```

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/theme/elink_tokens_test.dart`
Expected: FAIL（`package:elinkbook/theme/elink_tokens.dart` 不存在，編譯錯誤）

- [x] **Step 3: 實作 `ElinkTokens` 類別（欄位＋建構子＋`copyWith()`）**

建立 `app/lib/theme/elink_tokens.dart`：

```dart
import 'package:flutter/material.dart';

/// 依 `DESIGN.md` §1.2 定案的語意色 Token，透過
/// `Theme.of(context).extension<ElinkTokens>()` 存取，取代畫面各自寫死顏色。
/// 各欄位在四套主題（晴空藍天／夜讀水墨／宣紙古風／E-Ink）下的實際色值，由
/// `app_theme_data.dart` 的 `resolveThemeData()` 組裝並掛進
/// `ThemeData.extensions`（見 `epic-35-design-system-tokens` Issue 2）；本檔案
/// 只定義型別本身，此時尚未被任何主題實際使用。
class ElinkTokens extends ThemeExtension<ElinkTokens> {
  final Color highlightYellow;
  // 取代舊有 highlighterPinkTint，語意色由粉紅改綠（DESIGN.md §1.2 既有決策，
  // 見 epic-35 spec.md「既有語意色遷移到 ElinkTokens」）。
  final Color highlightGreen;
  final Color highlightBlue;
  final Color underlineColor;
  final Color progressTrack;
  final Color coverPlaceholder;
  final Color badgeScrim;
  final Color ttsActiveHighlight;

  /// 是否為 E-Ink 高對比模式。
  final bool isEink;

  /// 是否簡化動態效果（E-Ink 下為 true）。
  final bool reducedMotion;

  /// 是否採離散換頁（E-Ink 下為 true）。
  final bool discretePaging;

  const ElinkTokens({
    required this.highlightYellow,
    required this.highlightGreen,
    required this.highlightBlue,
    required this.underlineColor,
    required this.progressTrack,
    required this.coverPlaceholder,
    required this.badgeScrim,
    required this.ttsActiveHighlight,
    required this.isEink,
    required this.reducedMotion,
    required this.discretePaging,
  });

  @override
  ElinkTokens copyWith({
    Color? highlightYellow,
    Color? highlightGreen,
    Color? highlightBlue,
    Color? underlineColor,
    Color? progressTrack,
    Color? coverPlaceholder,
    Color? badgeScrim,
    Color? ttsActiveHighlight,
    bool? isEink,
    bool? reducedMotion,
    bool? discretePaging,
  }) {
    return ElinkTokens(
      highlightYellow: highlightYellow ?? this.highlightYellow,
      highlightGreen: highlightGreen ?? this.highlightGreen,
      highlightBlue: highlightBlue ?? this.highlightBlue,
      underlineColor: underlineColor ?? this.underlineColor,
      progressTrack: progressTrack ?? this.progressTrack,
      coverPlaceholder: coverPlaceholder ?? this.coverPlaceholder,
      badgeScrim: badgeScrim ?? this.badgeScrim,
      ttsActiveHighlight: ttsActiveHighlight ?? this.ttsActiveHighlight,
      isEink: isEink ?? this.isEink,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      discretePaging: discretePaging ?? this.discretePaging,
    );
  }

  @override
  ElinkTokens lerp(ThemeExtension<ElinkTokens>? other, double t) {
    // Task 2 會實作真正的插值邏輯，這裡先給最小合法實作讓 Task 1 可以編譯
    // 通過（ThemeExtension 要求 lerp 必須被 override）。
    return this;
  }
}
```

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/theme/elink_tokens_test.dart`
Expected: PASS（4 個測試全過）

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/theme/elink_tokens.dart app/test/theme/elink_tokens_test.dart
git commit -m "feat(epic-35): Issue 1 Task 1 — 新增 ElinkTokens 類別本體與 copyWith()"
```

---

### Task 2: `ElinkTokens.lerp()`

**Files:**
- Modify: `app/lib/theme/elink_tokens.dart`
- Test: `app/test/theme/elink_tokens_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `ElinkTokens` 類別（欄位、建構子）。
- Produces: `ElinkTokens lerp(ThemeExtension<ElinkTokens>? other, double t)` 的真正插值實作（Color 欄位用 `Color.lerp` 插值、bool 欄位在 `t < 0.5` 取 `this`／`t >= 0.5` 取 `other`、`other` 非 `ElinkTokens` 型別時回傳 `this`）。這是 `ThemeExtension` 介面要求的最後一個抽象方法，完成後 `ElinkTokens` 才是可以合法掛進 `ThemeData.extensions` 的完整型別（Issue 2 會用到）。

- [x] **Step 1: 寫失敗的測試——`lerp()` 的四種情境**

在 `app/test/theme/elink_tokens_test.dart` 的 `void main() { ... }` 內、`group('ElinkTokens.copyWith', ...)` 之後，新增：

```dart
  group('ElinkTokens.lerp', () {
    final other = _base.copyWith(
      highlightYellow: const Color(0xFFFFFFFF),
      isEink: true,
      reducedMotion: true,
      discretePaging: true,
    );

    test('Color 欄位在 t=0.5 時走 Color.lerp 插值，不是直接回傳其中一邊', () {
      // _base.highlightYellow = 0xFF111111（近黑），other = 0xFFFFFFFF（純白）
      // t=0.5 插值結果應介於兩者之間，既不等於黑也不等於白。
      final result = _base.lerp(other, 0.5);
      expect(result.highlightYellow, isNot(_base.highlightYellow));
      expect(result.highlightYellow, isNot(other.highlightYellow));
      expect(
        result.highlightYellow,
        Color.lerp(_base.highlightYellow, other.highlightYellow, 0.5),
      );
    });

    test('bool 欄位在 t < 0.5 時回傳 this（自己）的值', () {
      final result = _base.lerp(other, 0.3);
      expect(result.isEink, _base.isEink); // false
      expect(result.reducedMotion, _base.reducedMotion); // false
      expect(result.discretePaging, _base.discretePaging); // false
    });

    test('bool 欄位在 t >= 0.5 時回傳 other 的值', () {
      final result = _base.lerp(other, 0.5);
      expect(result.isEink, other.isEink); // true
      expect(result.reducedMotion, other.reducedMotion); // true
      expect(result.discretePaging, other.discretePaging); // true
    });

    test('other 不是 ElinkTokens 型別（含 null）時，回傳 this 本身', () {
      expect(_base.lerp(null, 0.5), same(_base));
    });
  });
```

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/theme/elink_tokens_test.dart`
Expected: FAIL——但不是全部新測試都失敗，Task 1 留的 `lerp()` 最小實作永遠回傳 `this`，逐一比對：
- 「Color 欄位插值」：失敗（`this` 不是插值結果）。
- 「bool 欄位在 t < 0.5 時回傳 this」：**在這個最小實作下剛好通過**（因為它本來就只會回傳 `this`，不是真的測到了 `t < 0.5` 分支邏輯，只是巧合綠燈）。
- 「bool 欄位在 t >= 0.5 時回傳 other」：失敗（`this` 不是 `other`）。
- 「other 非 ElinkTokens 時回傳 this」：**同樣在這個最小實作下巧合通過**。

整體跑起來 `flutter test` 仍會回報 FAIL（4 個測試裡有 2 個真的失敗），這樣就足以確認「尚未實作完成」；後面兩個巧合通過的測試在 Step 3 補上真正邏輯後依然是有效的迴歸測試，不需要額外處理。

- [x] **Step 3: 實作真正的 `lerp()` 邏輯**

修改 `app/lib/theme/elink_tokens.dart`，把 Task 1 寫的最小 `lerp()` 換成：

```dart
  @override
  ElinkTokens lerp(ThemeExtension<ElinkTokens>? other, double t) {
    if (other is! ElinkTokens) return this;
    return ElinkTokens(
      highlightYellow: Color.lerp(highlightYellow, other.highlightYellow, t)!,
      highlightGreen: Color.lerp(highlightGreen, other.highlightGreen, t)!,
      highlightBlue: Color.lerp(highlightBlue, other.highlightBlue, t)!,
      underlineColor: Color.lerp(underlineColor, other.underlineColor, t)!,
      progressTrack: Color.lerp(progressTrack, other.progressTrack, t)!,
      coverPlaceholder:
          Color.lerp(coverPlaceholder, other.coverPlaceholder, t)!,
      badgeScrim: Color.lerp(badgeScrim, other.badgeScrim, t)!,
      ttsActiveHighlight:
          Color.lerp(ttsActiveHighlight, other.ttsActiveHighlight, t)!,
      // bool 欄位沒有漸變意義，t < 0.5 取自己、t >= 0.5 取對方（離散跳變）。
      isEink: t < 0.5 ? isEink : other.isEink,
      reducedMotion: t < 0.5 ? reducedMotion : other.reducedMotion,
      discretePaging: t < 0.5 ? discretePaging : other.discretePaging,
    );
  }
```

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/theme/elink_tokens_test.dart`
Expected: PASS（8 個測試全過，Task 1 的 4 個＋Task 2 的 4 個）

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/theme/elink_tokens.dart app/test/theme/elink_tokens_test.dart
git commit -m "feat(epic-35): Issue 1 Task 2 — 實作 ElinkTokens.lerp() 插值邏輯"
```

---

### Task 3: `MaterialApp` 零時長主題轉場

**Files:**
- Modify: `app/lib/main.dart:334-337`（`ElinkBookApp` 的 `build()` 方法內建構 `MaterialApp` 處）
- Test: `app/test/theme/theme_test.dart`

**Interfaces:**
- Consumes: 無（獨立於 Task 1／2，跟 `ElinkTokens` 本身無直接程式碼依賴，只是同一份 spec 決議下順手一起做的小改動）。
- Produces: `MaterialApp` 建構時明確帶 `themeAnimationDuration: Duration.zero`，後續 Issue 2 讓 `ElinkTokens.lerp()` 真正被呼叫時（主題／E-Ink 切換），不會有跑到一半的過場動畫。

- [x] **Step 1: 寫失敗的測試——`MaterialApp.themeAnimationDuration` 為 `Duration.zero`**

在 `app/test/theme/theme_test.dart` 的 `void main() { ... }` 內、第一個 `testWidgets` 之前，新增：

```dart
  testWidgets(
      'MaterialApp 設定 themeAnimationDuration 為 Duration.zero'
      '（DESIGN.md §18 零動畫轉場：切換主題／E-Ink 不應有交叉淡出動畫，'
      '避免電子紙殘影）', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeAnimationDuration, Duration.zero);
  });
```

（`prefsManager`／`FakeLibraryRepository`／`FakeBookImportService` 皆為此檔案既有的 `setUp()`／import，不需要新增 import。）

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/theme/theme_test.dart`
Expected: FAIL（`materialApp.themeAnimationDuration` 為 Flutter 預設值 200ms，不等於 `Duration.zero`）

- [x] **Step 3: 修改 `main.dart`，加上 `themeAnimationDuration: Duration.zero`**

修改 `app/lib/main.dart` 第 334-337 行附近的 `MaterialApp(...)` 建構：

```dart
    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      title: 'elinkBook',
      theme: themeData,
      themeAnimationDuration: Duration.zero,
```

（只在既有的 `theme: themeData,` 後面加這一行，其餘建構參數不動。）

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/theme/theme_test.dart`
Expected: PASS（含本檔案原有的 4 個測試＋新增的 1 個，共 5 個全過）

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/main.dart app/test/theme/theme_test.dart
git commit -m "feat(epic-35): Issue 1 Task 3 — MaterialApp 加上零時長主題轉場"
```

---

## 全部 Task 完成後

- [x] 執行完整 `flutter test`（於 `app/` 目錄下，不帶檔案路徑），確認全專案無回歸。
- [x] 執行 `flutter analyze`，確認「No issues found!」。
- [x] 把 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 1 的 `Status` 從 `ready-for-agent` 更新為完成狀態（依當時 Epic 慣例用語），並在 `epic.md` 補一筆開發記錄。
- [x] 依 `sdd-workflow` 流程，發起 `/superpowers:requesting-code-review` 審查本次程式碼變更（`BASE_SHA`／`HEAD_SHA` 取本工單 3 個 commit 的起訖），審查報告存 `docs/epics/epic-35-design-system-tokens/reviews/review-issue-1.md`。
