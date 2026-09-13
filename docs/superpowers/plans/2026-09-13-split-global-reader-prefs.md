# 拆分 GlobalReaderPrefs 的 13 個攤平欄位 Implementation Plan

> **狀態：已完成並合併**——PR [#239](https://git.jigong.org/huthief/elinkBook/pulls/239)（`refactor/split-global-reader-prefs` → `main`），已於 2026-09-13 合併（合併後 main 為 `4a2e6129`）。程式碼審查報告：`docs/superpowers/reviews/2026-09-13-code-review-split-global-reader-prefs.md`（Critical 0／Important 1／Minor 4，皆已於 commit `6455d24a` 修正）。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **【`docs/superpowers/reviews/2026-09-13-review-split-global-reader-prefs.md` 審查修訂】** 初版計畫兩個 Critical 問題已修正：(1) 遺漏 `app/lib/screens/library_screen.dart:267`（`globalPrefs.openLastBookOnLaunch`，Issue 29 自動開書功能，生產程式碼）——已補進 Task 4。(2) Task 2／Task 3 結尾在 `flutter analyze` 尚未乾淨時就執行 `git commit`，違反 `AGENTS.md`「`flutter analyze` 必須乾淨才能提交」與本計畫自身 Global Constraints——已改為 Task 2／Task 3 結尾只跑單元測試、不 commit，Task 2-4 視為一個不可分割的重構閉環，只在 Task 4 全專案 `flutter analyze`／`flutter test` 皆乾淨後執行一次整合 commit。三項 Important（`library_screen_test.dart`／`reader_screen_test.dart` 8 處遺漏、`reader_prefs_manager_test.dart` 前段 5 處 `.copyWith`、三個設定畫面測試的 `savedGlobalPrefsCalls` 斷言遺漏）與三項 Minor（`export` 子值物件、`ZoneAction` 來源描述筆誤、Task 4 反饋週期）皆已採納修訂。

**Goal:** 把 `app/lib/reader/global_reader_prefs.dart`（171 行，13 個攤平欄位）依語意拆成 3 個巢狀值物件（`NavZonePrefs`／`TtsDefaults`／`ReadingDefaults`），`GlobalReaderPrefs` 收斂為只剩 1 個真正無法歸類的攤平欄位（`consoleLogEnabled`）的聚合根。目標是解決現行「`copyWith` 參數表跟實作一樣長、新增任一語意分組的欄位都要碰同一個檔案」的 shallow module 症狀，同時讓 `CONTEXT.md`「閱讀預設值（Reading Defaults）」這個 UI 詞條與底層資料模型真正統一（見 Global Constraints）。

**Architecture:** 完全巢狀化（不做「內部重組、對外扁平 API 不變」的捷徑）——`GlobalReaderPrefs` 移除這 12 個欄位的扁平 getter 與 `copyWith` 具名參數，改為只保留 `consoleLogEnabled`（攤平）加 3 個巢狀物件欄位（`navZone`／`tts`／`reading`）。呼叫端一律改用巢狀路徑（`prefs.navZone.navZoneMode`、`prefs.copyWith(navZone: prefs.navZone.copyWith(navZoneMode: x))`）。持久化層（`ReaderPrefsManagerImpl` 的 SharedPreferences 讀寫）完全不受影響——每個欄位本來就各自存獨立 key，拆分只是組裝/拆解巢狀物件時多一層轉換，鍵名不變。`ResolvedPreferences`（`ReaderScreen` 實際消費的「已解析」扁平型別）也完全不變，只有 `ReaderPrefsManagerImpl.resolve()` 內部讀取 `GlobalReaderPrefs` 欄位的路徑從 `global.pageTurnMode` 改成 `global.reading.pageTurnMode` 等，對外回傳的 `ResolvedPreferences` 型別/欄位不動。

**Tech Stack:** Flutter/Dart、`shared_preferences`（既有，不新增依賴）。

## Global Constraints

- **這是一份直接 TDD 的技術債清理計畫，不是 SDD Epic/Issue**：本次拆分經過 `/grill-with-docs` 訪談定案，範圍小、無持久化風險、無跨團隊協調需求，比照使用者過往「小型範圍走直接 TDD、不開正式 Epic/Issue」的既有慣例。**不建立任何 Epic/Issue 追蹤文件、不修改 `docs/epics.md`**——本計畫檔案本身就是唯一的留存紀錄。
- **分組範圍是 3 組，不是原始架構回顧報告（`tmp/architecture-review-20260907-064145.html` Candidate 4）提出的 3 組＋「6 個雜項留在聚合根」，也不是訪談中途一度定案的 4 組（含獨立的 `ChromeVisibility`）**——這兩個版本都已被推翻，理由：
  - 原始報告只挑出 `NavZonePrefs`（3 欄位）／`TtsDefaults`（2 欄位）兩組有證據支撐的分組，把其餘 6 個欄位（`pageTurnMode`／`screenOrientation`／`volumeKeyEnabled`／`fullscreen`／`openLastBookOnLaunch`／`consoleLogEnabled`）與 `showHeader`／`showFooter` 一併丟進「聚合根雜項」，這個判斷証實不完整——查證 `app/lib/screens/reading_defaults_screen.dart` 全檔後發現，`showHeader`／`showFooter` 從來不是孤立欄位，而是跟另外 5 個「雜項」欄位（`pageTurnMode`／`screenOrientation`／`volumeKeyEnabled`／`fullscreen`／`openLastBookOnLaunch`）**在同一個畫面、同一個真實使用情境下被同時讀寫**，證據強度跟 `NavZonePrefs`／`TtsDefaults` 一樣扎實。
  - 訪談中途一度依「`reading_defaults_screen.dart` 疑似只有 5 個欄位」的不完整查證，定案成 4 組（額外拆出只有 `showHeader`／`showFooter` 兩欄位的獨立 `ChromeVisibility`）；後續重新讀取該檔案全文才發現它實際上是 7 個欄位一組，`ChromeVisibility` 這個獨立分組並不成立，予以推翻。
  - 最終依據 `reading_defaults_screen.dart` 實際內容定案：**`ReadingDefaults` 是 7 個欄位**（`pageTurnMode`／`screenOrientation`／`volumeKeyEnabled`／`fullscreen`／`openLastBookOnLaunch`／`showHeader`／`showFooter`），聚合根只剩 `consoleLogEnabled`（`app/lib/screens/settings_scaffold.dart` 唯一單獨讀寫，無其他分組成員可歸類）一個真正孤立的欄位。
- **完全巢狀化，不做「內部重組、對外扁平 API 不變」的捷徑**：曾評估過「只在類別內部用巢狀物件儲存、對外維持完全相同的扁平 `copyWith` 參數」這個零呼叫端改動的替代方案，但這樣完全沒解決「`copyWith` 參數表跟實作一樣長」這個報告點名的症狀，只是把攤平搬進私有欄位，等於沒做。故採用完全巢狀化，代價是需要同步修改 3 個消費端畫面（見 Task 4）。
- **持久化零風險，不需要任何資料遷移邏輯**：查證 `ReaderPrefsManagerImpl`（`app/lib/reader/reader_prefs_manager_impl.dart` 第 35-49 行）確認 13 個欄位各自存一個獨立 SharedPreferences key（例如 `global_reader_page_turn_mode`），並非整包 JSON 序列化。本次拆分**不改變任何 key 名稱**，`loadGlobalPrefs()`／`saveGlobalPrefs()` 只是改成組裝/拆解 3 個巢狀物件＋1 個攤平欄位，內部仍逐 key 讀寫同一批 SharedPreferences，既有使用者已儲存的偏好設定不受影響。
- **不修改任何已歸檔文件**：`docs/archive/2026-09-10-epic-36-adaptive-shelf-navigation/spec.md`「Further Notes」段落曾寫下「目前 13 個欄位規模尚不構成問題」的結論，本次判斷推翻這個結論，但**不回頭修改已歸檔文件**——歸檔文件是歷史記錄，新判斷只留在本計畫與其 commit 說明裡。
- **不寫 ADR**：這是區域性的資料型別重構（單一 `GlobalReaderPrefs` 類別的內部結構），不符合「難以逆轉／令人意外／真正的架構取捨」三條件——沒有其他系統/模組依賴這個內部結構的具體形狀，日後要合併回攤平也只是機械式的逆向操作，不夠格開 ADR。
- **已同步更新 `CONTEXT.md`「閱讀預設值（Reading Defaults）」詞條**（本計畫撰寫時已一併完成，非本計畫的 Task）：該詞條原本明文寫「純粹是 UI 呈現層的分組容器……不是新的資料模型」，且欄位數寫成過時的「四項」；已更正為 7 個欄位並說明現在 `GlobalReaderPrefs.reading`（`ReadingDefaults` 值物件）與 UI 畫面是同一件事。同時順手更正了「全域預設值」詞條裡一句過時陳述（「目前僅螢幕方向與翻頁模式已接上設定畫面 UI」，現況是四個畫面皆已完整實作）。**執行本計畫時不需要再碰 `CONTEXT.md`。**
- **明確排除範圍**：`BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`，單書覆寫層）**不**一併重構，即使欄位名稱有重複（`fullscreen`／`showHeader`／`showFooter`／`pageTurnMode`／`screenOrientation`）——這是完全獨立的型別，本計畫不觸碰。`ResolvedPreferences`（`app/lib/reader/resolved_preferences.dart`）維持完全不變。
- **禁止範圍**：不引入新的外部 `pubspec.yaml` 依賴；程式碼註解與使用者可見文字使用繁體中文。
- **提交邊界（審查意見 C-2，推翻計畫初版）**：`AGENTS.md` 三度強調「`flutter analyze` 必須乾淨才能提交」，是不可動搖的專案核心守則。Task 2、Task 3、Task 4 是同一個不可分割的重構閉環（改根模型 → 改持久化 → 改所有呼叫端與測試），**只有 Task 4 最終確認全專案 `flutter analyze` 為 `No issues found!` 且 `flutter test` 全數通過後，才執行一次涵蓋 Task 2-4 全部異動檔案的整合 commit**——Task 2、Task 3 結尾一律不 commit。計畫初版曾在 Task 2／Task 3 結尾各自提交一次、自稱「刻意讓 flutter analyze 暫時不乾淨」，經審查判定為對 `AGENTS.md` 的公然違反，已推翻。Task 1（4 個獨立值物件，可自我封閉驗證）不受影響，維持獨立 commit。
- **Task 4 的呼叫端清單不保證窮舉，以 `flutter analyze` 的編譯錯誤為最終權威**：規劃階段用 `grep "GlobalReaderPrefs("` 一開始只找到 `reader_prefs_manager_impl.dart`、`global_reader_prefs.dart` 自身、`global_reader_prefs_test.dart`、`reader_prefs_manager_test.dart` 四個檔案直接建構 `GlobalReaderPrefs(...)`；逐檔讀取確認 `nav_zone_settings_screen.dart`／`tts_defaults_screen.dart`／`reading_defaults_screen.dart` 三個畫面透過 `_prefs.copyWith(...)`／`_prefs.xxx` 存取欄位。但這輪查證漏掉了透過 `loadGlobalPrefs()` 回傳值間接持有 `GlobalReaderPrefs`（無顯式型別標注、grep 型別名稱抓不到）的生產程式碼 `library_screen.dart`，以及使用 `.initial().copyWith(...)`（不含 `GlobalReaderPrefs(` 子字串，grep 抓不到）的 `library_screen_test.dart`／`reader_screen_test.dart`／`reader_prefs_manager_test.dart` 前段——審查意見 C-1／I-1／I-2 逐一揪出後已補進 Task 3／Task 4。欄位名稱（`fullscreen`／`showHeader`／`showFooter`／`pageTurnMode`／`screenOrientation`）又與 `BookReaderPrefs`／`ResolvedPreferences` 重複，人工窮舉清單已經證明不可靠（詳見下方 Self-Review Notes）。Task 4 Step 7 因此明確要求「跑 `flutter analyze`，把每個編譯錯誤揪出來修正，重複直到 `No issues found!`」——Dart 靜態型別系統本身就是最可靠的「還有哪裡沒改完」偵測器，不依賴人工窮舉清單的完整性。

---

### Task 1：建立 `NavZonePrefs`／`TtsDefaults`／`ReadingDefaults` 三個值物件

**Files:**
- Create：`app/lib/reader/nav_zone_prefs.dart`
- Create：`app/lib/reader/tts_defaults.dart`
- Create：`app/lib/reader/reading_defaults.dart`
- Test：`app/test/reader/nav_zone_prefs_test.dart`
- Test：`app/test/reader/tts_defaults_test.dart`
- Test：`app/test/reader/reading_defaults_test.dart`

**Interfaces:**
- Consumes：`NavZoneMode`／`rightFlipZoneTemplate`（`app/lib/reader/nav_zone_mode.dart`）、`ZoneAction`（`app/lib/reader/zone_action.dart`——`nav_zone_mode.dart` 只 `import` 未 `export` 這個型別，需要另外直接匯入）、`PageTurnMode`（`app/lib/reader/page_turn_mode.dart`）、`ScreenOrientationSetting`（`app/lib/reader/screen_orientation_setting.dart`）——皆為既有型別，不修改
- Produces：`NavZonePrefs`／`TtsDefaults`／`ReadingDefaults` 三個獨立值物件（各自 `const` 建構子＋`.initial()`＋`copyWith`／`==`／`hashCode`），供 Task 2 的 `GlobalReaderPrefs` 聚合根消費

- [x] **Step 1：撰寫 `NavZonePrefs` 的失敗測試**

建立 `app/test/reader/nav_zone_prefs_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/nav_zone_prefs.dart';
import 'package:elinkbook/reader/zone_action.dart';

void main() {
  test('NavZonePrefs.initial() 回傳 rightFlip 模板、debug overlay 關閉', () {
    const prefs = NavZonePrefs.initial();
    expect(prefs.navZoneMode, NavZoneMode.rightFlip);
    expect(prefs.navZoneCustomActions, rightFlipZoneTemplate);
    expect(prefs.showNavZoneDebugOverlay, isFalse);
  });

  test('copyWith 只更新指定欄位，其餘欄位保留原值', () {
    const original = NavZonePrefs.initial();
    final updated = original.copyWith(navZoneMode: NavZoneMode.oneHand);
    expect(updated.navZoneMode, NavZoneMode.oneHand);
    expect(updated.navZoneCustomActions, rightFlipZoneTemplate);
    expect(updated.showNavZoneDebugOverlay, isFalse);
  });

  test('copyWith 可個別更新 navZoneCustomActions／showNavZoneDebugOverlay', () {
    const original = NavZonePrefs.initial();
    const customActions = [
      ZoneAction.menu, ZoneAction.none, ZoneAction.none,
      ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ];
    final updated = original.copyWith(
      navZoneMode: NavZoneMode.custom,
      navZoneCustomActions: customActions,
      showNavZoneDebugOverlay: true,
    );
    expect(updated.navZoneMode, NavZoneMode.custom);
    expect(updated.navZoneCustomActions, customActions);
    expect(updated.showNavZoneDebugOverlay, isTrue);
  });

  test('三個欄位值皆相同的 NavZonePrefs 視為相等', () {
    const a = NavZonePrefs(
      navZoneMode: NavZoneMode.oneHand,
      navZoneCustomActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: true,
    );
    const b = NavZonePrefs(
      navZoneMode: NavZoneMode.oneHand,
      navZoneCustomActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: true,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('navZoneCustomActions 內容不同時視為不相等', () {
    const a = NavZonePrefs(
      navZoneMode: NavZoneMode.custom,
      navZoneCustomActions: [
        ZoneAction.menu, ZoneAction.none, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ],
      showNavZoneDebugOverlay: false,
    );
    const b = NavZonePrefs(
      navZoneMode: NavZoneMode.custom,
      navZoneCustomActions: [
        ZoneAction.none, ZoneAction.none, ZoneAction.menu,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ],
      showNavZoneDebugOverlay: false,
    );
    expect(a == b, isFalse);
  });
}
```

- [x] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/reader/nav_zone_prefs_test.dart
```

Expected：FAIL——`nav_zone_prefs.dart` 不存在。

- [x] **Step 3：建立 `NavZonePrefs`**

```dart
import 'package:flutter/foundation.dart';

import 'nav_zone_mode.dart';
import 'zone_action.dart';

/// 導航熱區偏好（epic-7-interaction／FR-24），從 `GlobalReaderPrefs` 拆出
/// （2026-09-13，見 `docs/superpowers/plans/2026-09-13-split-global-reader-prefs.md`）。
/// 三個欄位皆 non-nullable，全域層本身沒有更上層的預設可回退。
class NavZonePrefs {
  /// 熱區映射模式，預設 [NavZoneMode.rightFlip]。
  final NavZoneMode navZoneMode;

  /// 長度固定 9。僅 [navZoneMode] 為 [NavZoneMode.custom] 時內容才生效
  /// （其餘模式由 `resolveZoneActions` 查表算出，忽略本欄位）；仍持續保留
  /// 是為了使用者切回自訂模式時能還原上次編輯結果。
  final List<ZoneAction> navZoneCustomActions;

  /// 是否顯示熱區輔助線，預設 `false`。
  final bool showNavZoneDebugOverlay;

  const NavZonePrefs({
    this.navZoneMode = NavZoneMode.rightFlip,
    this.navZoneCustomActions = rightFlipZoneTemplate,
    this.showNavZoneDebugOverlay = false,
  });

  /// 初始值，與現行硬編碼預設一致，不改變任何現有使用者體驗。
  const NavZonePrefs.initial() : this();

  NavZonePrefs copyWith({
    NavZoneMode? navZoneMode,
    List<ZoneAction>? navZoneCustomActions,
    bool? showNavZoneDebugOverlay,
  }) {
    return NavZonePrefs(
      navZoneMode: navZoneMode ?? this.navZoneMode,
      navZoneCustomActions: navZoneCustomActions ?? this.navZoneCustomActions,
      showNavZoneDebugOverlay:
          showNavZoneDebugOverlay ?? this.showNavZoneDebugOverlay,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NavZonePrefs &&
      other.navZoneMode == navZoneMode &&
      listEquals(other.navZoneCustomActions, navZoneCustomActions) &&
      other.showNavZoneDebugOverlay == showNavZoneDebugOverlay;

  @override
  int get hashCode => Object.hash(
        navZoneMode,
        Object.hashAll(navZoneCustomActions),
        showNavZoneDebugOverlay,
      );
}
```

（`rightFlipZoneTemplate` 定義於 `app/lib/reader/nav_zone_mode.dart` 第 18 行，本身已是 `const List<ZoneAction>`，可直接作為建構子預設參數值。）

- [x] **Step 4：執行測試，確認通過**

```bash
flutter test test/reader/nav_zone_prefs_test.dart
```

Expected：全數 PASS。

- [x] **Step 5：撰寫 `TtsDefaults` 的失敗測試**

建立 `app/test/reader/tts_defaults_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_defaults.dart';

void main() {
  test('TtsDefaults.initial() 的 ttsVoiceId 為 null（系統預設語音）、defaultTtsSpeed 為 1.0',
      () {
    const prefs = TtsDefaults.initial();
    expect(prefs.ttsVoiceId, isNull);
    expect(prefs.defaultTtsSpeed, 1.0);
  });

  test('copyWith 可個別更新 ttsVoiceId／defaultTtsSpeed，不影響另一欄位', () {
    const original = TtsDefaults.initial();
    final updated = original.copyWith(defaultTtsSpeed: 1.5);
    expect(updated.defaultTtsSpeed, 1.5);
    expect(updated.ttsVoiceId, isNull);

    final withVoice = original.copyWith(ttsVoiceId: 'voice-1');
    expect(withVoice.ttsVoiceId, 'voice-1');
    expect(withVoice.defaultTtsSpeed, 1.0);
  });

  test('兩個欄位值皆相同的 TtsDefaults 視為相等（含 ttsVoiceId 皆為 null）', () {
    const a = TtsDefaults.initial();
    const b = TtsDefaults.initial();
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('ttsVoiceId 或 defaultTtsSpeed 不同時視為不相等', () {
    const a = TtsDefaults.initial();
    final b = a.copyWith(ttsVoiceId: 'voice-1');
    expect(a == b, isFalse);
    final c = a.copyWith(defaultTtsSpeed: 1.25);
    expect(a == c, isFalse);
  });
}
```

- [x] **Step 6：執行測試，確認失敗**

```bash
flutter test test/reader/tts_defaults_test.dart
```

Expected：FAIL——`tts_defaults.dart` 不存在。

- [x] **Step 7：建立 `TtsDefaults`**

```dart
/// 朗讀（TTS）預設值（epic-36-adaptive-shelf-navigation Issue 5），從
/// `GlobalReaderPrefs` 拆出（2026-09-13，見
/// `docs/superpowers/plans/2026-09-13-split-global-reader-prefs.md`）。
class TtsDefaults {
  /// 預設語音 id。`null` 代表「使用系統預設語音」——語意上沒有一個放諸
  /// 四海皆準的安全非空預設值，是本類別唯一 nullable 的欄位。
  final String? ttsVoiceId;

  /// 預設語速，範圍 0.75x~2.0x（`DESIGN.md#L307` §13.2），預設 `1.0`。
  final double defaultTtsSpeed;

  const TtsDefaults({
    this.ttsVoiceId,
    this.defaultTtsSpeed = 1.0,
  });

  const TtsDefaults.initial() : this();

  TtsDefaults copyWith({
    String? ttsVoiceId,
    double? defaultTtsSpeed,
  }) {
    return TtsDefaults(
      ttsVoiceId: ttsVoiceId ?? this.ttsVoiceId,
      defaultTtsSpeed: defaultTtsSpeed ?? this.defaultTtsSpeed,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TtsDefaults &&
      other.ttsVoiceId == ttsVoiceId &&
      other.defaultTtsSpeed == defaultTtsSpeed;

  @override
  int get hashCode => Object.hash(ttsVoiceId, defaultTtsSpeed);
}
```

> [!NOTE]
> `copyWith` 對 `ttsVoiceId` 沿用既有 `??` 慣例——與 `GlobalReaderPrefs` 原本的
> `copyWith` 行為一致：目前沒有任何呼叫端需要「明確把 `ttsVoiceId` 從有值改回
> `null`」這個操作（`tts_defaults_screen.dart` 只會傳入實際選中的 voice id，
> 不會傳 `null`），維持原有限制，不在本次重構擴大 `copyWith` 的能力範圍。

- [x] **Step 8：執行測試，確認通過**

```bash
flutter test test/reader/tts_defaults_test.dart
```

Expected：全數 PASS。

- [x] **Step 9：撰寫 `ReadingDefaults` 的失敗測試**

建立 `app/test/reader/reading_defaults_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/reading_defaults.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';

void main() {
  test(
      'ReadingDefaults.initial() 回傳與現行硬編碼預設一致的值', () {
    const prefs = ReadingDefaults.initial();
    expect(prefs.pageTurnMode, PageTurnMode.paginated);
    expect(prefs.screenOrientation, ScreenOrientationSetting.auto);
    expect(prefs.volumeKeyEnabled, isTrue);
    expect(prefs.fullscreen, isFalse);
    expect(prefs.openLastBookOnLaunch, isTrue);
    expect(prefs.showHeader, isFalse);
    expect(prefs.showFooter, isFalse);
  });

  test('copyWith 只更新指定欄位，其餘欄位保留原值', () {
    const original = ReadingDefaults.initial();
    final updated = original.copyWith(pageTurnMode: PageTurnMode.scroll);
    expect(updated.pageTurnMode, PageTurnMode.scroll);
    expect(updated.screenOrientation, original.screenOrientation);
    expect(updated.volumeKeyEnabled, original.volumeKeyEnabled);
    expect(updated.fullscreen, original.fullscreen);
    expect(updated.openLastBookOnLaunch, original.openLastBookOnLaunch);
    expect(updated.showHeader, original.showHeader);
    expect(updated.showFooter, original.showFooter);
  });

  test('copyWith 可個別更新 volumeKeyEnabled／fullscreen／openLastBookOnLaunch', () {
    const original = ReadingDefaults.initial();
    final updated = original.copyWith(
      volumeKeyEnabled: false,
      fullscreen: true,
      openLastBookOnLaunch: false,
    );
    expect(updated.volumeKeyEnabled, isFalse);
    expect(updated.fullscreen, isTrue);
    expect(updated.openLastBookOnLaunch, isFalse);
    expect(updated.pageTurnMode, original.pageTurnMode);
  });

  test('copyWith 可個別更新 showHeader／showFooter', () {
    const original = ReadingDefaults.initial();
    final updated =
        original.copyWith(showHeader: true, showFooter: true);
    expect(updated.showHeader, isTrue);
    expect(updated.showFooter, isTrue);
    expect(updated.fullscreen, original.fullscreen);
  });

  test('七個欄位值皆相同的 ReadingDefaults 視為相等', () {
    const a = ReadingDefaults(
      pageTurnMode: PageTurnMode.scroll,
      screenOrientation: ScreenOrientationSetting.lock90,
      volumeKeyEnabled: false,
      fullscreen: true,
      openLastBookOnLaunch: false,
      showHeader: true,
      showFooter: true,
    );
    const b = ReadingDefaults(
      pageTurnMode: PageTurnMode.scroll,
      screenOrientation: ScreenOrientationSetting.lock90,
      volumeKeyEnabled: false,
      fullscreen: true,
      openLastBookOnLaunch: false,
      showHeader: true,
      showFooter: true,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一欄位不同時視為不相等', () {
    const a = ReadingDefaults.initial();
    expect(a == a.copyWith(pageTurnMode: PageTurnMode.scroll), isFalse);
    expect(
        a == a.copyWith(screenOrientation: ScreenOrientationSetting.lock90),
        isFalse);
    expect(a == a.copyWith(volumeKeyEnabled: false), isFalse);
    expect(a == a.copyWith(fullscreen: true), isFalse);
    expect(a == a.copyWith(openLastBookOnLaunch: false), isFalse);
    expect(a == a.copyWith(showHeader: true), isFalse);
    expect(a == a.copyWith(showFooter: true), isFalse);
  });
}
```

- [x] **Step 10：執行測試，確認失敗**

```bash
flutter test test/reader/reading_defaults_test.dart
```

Expected：FAIL——`reading_defaults.dart` 不存在。

- [x] **Step 11：建立 `ReadingDefaults`**

```dart
import 'page_turn_mode.dart';
import 'screen_orientation_setting.dart';

/// 「閱讀預設值」畫面（`ReadingDefaultsScreen`，FR-36/37/38/42）對應的 7 個
/// 欄位，從 `GlobalReaderPrefs` 拆出（2026-09-13，見
/// `docs/superpowers/plans/2026-09-13-split-global-reader-prefs.md`）。UI
/// 畫面與本類別現在是同一件事——見 `CONTEXT.md`「閱讀預設值」詞條
/// 2026-09-13 修訂。全部欄位皆 non-nullable，全域層本身沒有更上層的預設
/// 可回退。
class ReadingDefaults {
  final PageTurnMode pageTurnMode;
  final ScreenOrientationSetting screenOrientation;

  /// 音量鍵翻頁總開關（FR-36），預設 `true`（沿用既有行為）。無單書覆寫層。
  final bool volumeKeyEnabled;

  /// 全螢幕模式全域預設值（FR-42），預設 `false`。與單書層
  /// `BookReaderPrefs.fullscreen` 為雙層解析關係
  /// （`book.fullscreen ?? global.reading.fullscreen`）。
  final bool fullscreen;

  /// 啟動時開啟最後閱讀的那本書，預設 `true`。
  final bool openLastBookOnLaunch;

  /// 「顯示頁首／頁尾」全域預設值，預設 `false`。與單書層
  /// `BookReaderPrefs.showHeader`/`showFooter` 為雙層解析關係。
  final bool showHeader;
  final bool showFooter;

  const ReadingDefaults({
    this.pageTurnMode = PageTurnMode.paginated,
    this.screenOrientation = ScreenOrientationSetting.auto,
    this.volumeKeyEnabled = true,
    this.fullscreen = false,
    this.openLastBookOnLaunch = true,
    this.showHeader = false,
    this.showFooter = false,
  });

  const ReadingDefaults.initial() : this();

  ReadingDefaults copyWith({
    PageTurnMode? pageTurnMode,
    ScreenOrientationSetting? screenOrientation,
    bool? volumeKeyEnabled,
    bool? fullscreen,
    bool? openLastBookOnLaunch,
    bool? showHeader,
    bool? showFooter,
  }) {
    return ReadingDefaults(
      pageTurnMode: pageTurnMode ?? this.pageTurnMode,
      screenOrientation: screenOrientation ?? this.screenOrientation,
      volumeKeyEnabled: volumeKeyEnabled ?? this.volumeKeyEnabled,
      fullscreen: fullscreen ?? this.fullscreen,
      openLastBookOnLaunch: openLastBookOnLaunch ?? this.openLastBookOnLaunch,
      showHeader: showHeader ?? this.showHeader,
      showFooter: showFooter ?? this.showFooter,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReadingDefaults &&
      other.pageTurnMode == pageTurnMode &&
      other.screenOrientation == screenOrientation &&
      other.volumeKeyEnabled == volumeKeyEnabled &&
      other.fullscreen == fullscreen &&
      other.openLastBookOnLaunch == openLastBookOnLaunch &&
      other.showHeader == showHeader &&
      other.showFooter == showFooter;

  @override
  int get hashCode => Object.hash(
        pageTurnMode,
        screenOrientation,
        volumeKeyEnabled,
        fullscreen,
        openLastBookOnLaunch,
        showHeader,
        showFooter,
      );
}
```

- [x] **Step 12：執行測試，確認通過**

```bash
flutter test test/reader/reading_defaults_test.dart
```

Expected：全數 PASS。

- [x] **Step 13：`flutter analyze`**

```bash
flutter analyze
```

Expected："No issues found!"

- [x] **Step 14：Commit**

```bash
git add lib/reader/nav_zone_prefs.dart lib/reader/tts_defaults.dart lib/reader/reading_defaults.dart test/reader/nav_zone_prefs_test.dart test/reader/tts_defaults_test.dart test/reader/reading_defaults_test.dart
git commit -m "$(cat <<'EOF'
feat(reader): 新增 NavZonePrefs/TtsDefaults/ReadingDefaults 三個值物件

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_012isCaPSCSdqh3R2Wapj5Nd
EOF
)"
```

---

### Task 2：`GlobalReaderPrefs` 聚合根改用巢狀欄位

**Files:**
- Modify：`app/lib/reader/global_reader_prefs.dart`
- Modify：`app/test/reader/global_reader_prefs_test.dart`（整檔重寫）

**Interfaces:**
- Consumes：Task 1 的 `NavZonePrefs`／`TtsDefaults`／`ReadingDefaults`
- Produces：`GlobalReaderPrefs`（`consoleLogEnabled: bool` 攤平 + `navZone: NavZonePrefs` + `tts: TtsDefaults` + `reading: ReadingDefaults`，`copyWith`／`==`／`hashCode` 皆改為只處理這 4 個欄位）——供 Task 3 的 `ReaderPrefsManagerImpl` 消費

- [x] **Step 1：改寫 `global_reader_prefs_test.dart`（失敗測試）**

整檔取代 `app/test/reader/global_reader_prefs_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/nav_zone_prefs.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/reading_defaults.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/tts_defaults.dart';

void main() {
  test('GlobalReaderPrefs.initial() 的 4 個欄位皆為各自的 .initial()／預設值', () {
    const prefs = GlobalReaderPrefs.initial();
    expect(prefs.consoleLogEnabled, isFalse);
    expect(prefs.navZone, const NavZonePrefs.initial());
    expect(prefs.tts, const TtsDefaults.initial());
    expect(prefs.reading, const ReadingDefaults.initial());
  });

  test('copyWith 只更新指定欄位，其餘欄位保留原值', () {
    const original = GlobalReaderPrefs.initial();
    final updatedReading = original.copyWith(
      reading: original.reading.copyWith(pageTurnMode: PageTurnMode.scroll),
    );
    expect(updatedReading.reading.pageTurnMode, PageTurnMode.scroll);
    expect(updatedReading.navZone, original.navZone);
    expect(updatedReading.tts, original.tts);
    expect(updatedReading.consoleLogEnabled, original.consoleLogEnabled);
  });

  test('copyWith 可個別替換 navZone／tts／reading 整個子物件', () {
    const original = GlobalReaderPrefs.initial();
    const newNavZone = NavZonePrefs(navZoneMode: NavZoneMode.oneHand);
    const newTts = TtsDefaults(ttsVoiceId: 'voice-1');
    final updated = original.copyWith(navZone: newNavZone, tts: newTts);
    expect(updated.navZone, newNavZone);
    expect(updated.tts, newTts);
    expect(updated.reading, original.reading);
  });

  test('copyWith 可更新 consoleLogEnabled，不影響巢狀物件', () {
    const original = GlobalReaderPrefs.initial();
    final updated = original.copyWith(consoleLogEnabled: true);
    expect(updated.consoleLogEnabled, isTrue);
    expect(updated.navZone, original.navZone);
    expect(updated.tts, original.tts);
    expect(updated.reading, original.reading);
  });

  test('4 個欄位值皆相同的 GlobalReaderPrefs 視為相等', () {
    const a = GlobalReaderPrefs(
      consoleLogEnabled: true,
      navZone: NavZonePrefs(navZoneMode: NavZoneMode.oneHand),
      tts: TtsDefaults(ttsVoiceId: 'voice-1'),
      reading: ReadingDefaults(pageTurnMode: PageTurnMode.scroll),
    );
    const b = GlobalReaderPrefs(
      consoleLogEnabled: true,
      navZone: NavZonePrefs(navZoneMode: NavZoneMode.oneHand),
      tts: TtsDefaults(ttsVoiceId: 'voice-1'),
      reading: ReadingDefaults(pageTurnMode: PageTurnMode.scroll),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一巢狀子物件不同時視為不相等', () {
    const a = GlobalReaderPrefs.initial();
    expect(
        a ==
            a.copyWith(
                navZone: const NavZonePrefs(navZoneMode: NavZoneMode.oneHand)),
        isFalse);
    expect(a == a.copyWith(tts: const TtsDefaults(ttsVoiceId: 'voice-1')),
        isFalse);
    expect(
        a ==
            a.copyWith(
                reading: const ReadingDefaults(
                    pageTurnMode: PageTurnMode.scroll)),
        isFalse);
    expect(a == a.copyWith(consoleLogEnabled: true), isFalse);
  });
}
```

- [x] **Step 2：執行測試，確認失敗**

```bash
flutter test test/reader/global_reader_prefs_test.dart
```

Expected：FAIL（編譯錯誤）——`GlobalReaderPrefs` 尚無 `navZone`/`tts`/`reading` 具名參數。

- [x] **Step 3：改寫 `global_reader_prefs.dart`**

整檔取代 `app/lib/reader/global_reader_prefs.dart`：

```dart
import 'nav_zone_prefs.dart';
import 'reading_defaults.dart';
import 'tts_defaults.dart';

export 'nav_zone_prefs.dart';
export 'reading_defaults.dart';
export 'tts_defaults.dart';

/// 跨書生效的全域預設閱讀偏好聚合根（2026-09-13 由原本的 13 個攤平欄位拆分
/// 為 3 個巢狀值物件＋1 個攤平欄位，見
/// `docs/superpowers/plans/2026-09-13-split-global-reader-prefs.md`）。
///
/// [consoleLogEnabled] 是唯一維持攤平的欄位——`app/lib/screens/
/// settings_scaffold.dart` 是它唯一的讀寫端，語意上跟導覽熱區／TTS／閱讀
/// 預設值三組都無關，沒有可歸類的分組。
class GlobalReaderPrefs {
  /// Console Log 攔截總開關（epic-28-reader-settings-enhancements
  /// Issue 2），預設 `false`（不攔截一般等級訊息）。只影響 `[LOG]`/
  /// `[WARNING]`/`[DEBUG]`/`[TIP]` 等級——`[ERROR]` 等級（含未捕捉例外的
  /// 崩潰診斷用途）永遠強制記錄，不受本開關影響，見
  /// `handleFoliateConsoleMessage()`。
  final bool consoleLogEnabled;

  /// 導航熱區偏好（FR-24），見 [NavZonePrefs]。
  final NavZonePrefs navZone;

  /// 朗讀（TTS）預設值，見 [TtsDefaults]。
  final TtsDefaults tts;

  /// 「閱讀預設值」畫面對應的 7 個欄位，見 [ReadingDefaults]。
  final ReadingDefaults reading;

  const GlobalReaderPrefs({
    this.consoleLogEnabled = false,
    this.navZone = const NavZonePrefs.initial(),
    this.tts = const TtsDefaults.initial(),
    this.reading = const ReadingDefaults.initial(),
  });

  /// 初始值，與現行硬編碼預設一致，不改變任何現有使用者體驗。
  const GlobalReaderPrefs.initial() : this();

  GlobalReaderPrefs copyWith({
    bool? consoleLogEnabled,
    NavZonePrefs? navZone,
    TtsDefaults? tts,
    ReadingDefaults? reading,
  }) {
    return GlobalReaderPrefs(
      consoleLogEnabled: consoleLogEnabled ?? this.consoleLogEnabled,
      navZone: navZone ?? this.navZone,
      tts: tts ?? this.tts,
      reading: reading ?? this.reading,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlobalReaderPrefs &&
      other.consoleLogEnabled == consoleLogEnabled &&
      other.navZone == navZone &&
      other.tts == tts &&
      other.reading == reading;

  @override
  int get hashCode =>
      Object.hash(consoleLogEnabled, navZone, tts, reading);
}
```

> [!NOTE]
> 頂部同時 `import` 與 `export` 這 3 個值物件檔案（`import` 是本檔案自己
> 的欄位型別宣告需要；`export` 讓 Task 4 的三個消費端畫面只需要
> `import '../reader/global_reader_prefs.dart';` 一份 import 就能同時取得
> `GlobalReaderPrefs`／`NavZonePrefs`／`TtsDefaults`／`ReadingDefaults` 四個
> 型別，不需要額外分別匯入 3 個子檔案——審查意見 M-1）。

> [!IMPORTANT]
> 原檔案的欄位層級 doc comment（例如 [navZoneMode] 的用途說明、`fullscreen`
> 與單書層雙層解析關係的說明）已搬到 Task 1 建立的 `NavZonePrefs`／
> `ReadingDefaults` 各自檔案裡，不是被刪除——本步驟整檔取代
> `global_reader_prefs.dart` 時不需要保留這些欄位層級註解在本檔案，因為
> 欄位本身已經不在這裡。

- [x] **Step 4：執行測試，確認通過**

```bash
flutter test test/reader/global_reader_prefs_test.dart
```

Expected：全數 PASS。

- [x] **Step 5：`flutter analyze`（記錄現況，不代表本 Task 失敗）**

```bash
flutter analyze
```

Expected：**尚未乾淨**——`library_screen.dart`／`reader_prefs_manager_impl.dart`／三個消費端畫面此時仍在用舊的攤平 API，會出現大量編譯錯誤。這是預期中的暫時狀態，Task 3／Task 4 會逐一修正。**本步驟只是留存證據，不代表 Task 2 失敗**——不要因為這裡沒有 "No issues found!" 就回頭修改 Task 2 的程式碼。

> [!IMPORTANT]
> **不在此執行 `git commit`（審查意見 C-2，推翻原計畫初版）**：`AGENTS.md`
> 三度強調「`flutter analyze` 必須乾淨才能提交」，是不可動搖的專案核心
> 守則；本計畫自身 Global Constraints 也明文要求「`flutter analyze` 每個
> Task 結尾都必須乾淨」。Step 5 尚未乾淨，此時提交會產生違規的 intermediate
> commit（破壞 `git bisect` 二分除錯能力，也可能中斷有 pre-commit 靜態檢查
> 勾點的環境）。原計畫初版曾在此提交並自稱「刻意如此」，經審查判定為對
> `AGENTS.md` 的公然違反，已推翻——**Task 2、Task 3、Task 4 現在視為同一個
> 不可分割的重構閉環**：`global_reader_prefs.dart`／`global_reader_prefs_test.dart`
> 兩處改動先保留在工作目錄（未提交），繼續往下做 Task 3、Task 4，直到 Task 4
> 全專案 `flutter analyze`／`flutter test` 皆確認乾淨，才執行一次涵蓋 Task
> 2-4 全部異動檔案的整合 commit。

---

### Task 3：`ReaderPrefsManagerImpl` 改用巢狀讀寫

**Files:**
- Modify：`app/lib/reader/reader_prefs_manager_impl.dart`
- Modify：`app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `GlobalReaderPrefs`（`navZone`／`tts`／`reading`／`consoleLogEnabled`）
- Produces：`ReaderPrefsManagerImpl.loadGlobalPrefs()`／`saveGlobalPrefs()`／`resolve()` 內部改用巢狀讀寫——SharedPreferences key 名稱、`resolve()` 對外回傳的 `ResolvedPreferences` 型別/欄位皆不變

- [x] **Step 1：修改 `reader_prefs_manager_test.dart` 中所有直接建構 `GlobalReaderPrefs(...)` 的地方**

找出 `app/test/reader/reader_prefs_manager_test.dart` 中全部 `const GlobalReaderPrefs(...)`／`GlobalReaderPrefs(...)` 呼叫（規劃階段查證共 8 處，第 183、208、355、372、390、419、443、467、503、514 行——實際行號在前面 Task 2 提交後可能因無關改動略有偏移，以 `grep -n "GlobalReaderPrefs("` 實際結果為準），把攤平具名參數改成巢狀路徑。例如第 183 行附近：

```diff
       final loaded = LoadedPrefs(
         bookPrefs: BookReaderPrefs.empty,
-        globalPrefs: const GlobalReaderPrefs(
-          pageTurnMode: PageTurnMode.scroll,
-          screenOrientation: ScreenOrientationSetting.lock270,
-          navZoneMode: NavZoneMode.oneHand,
-          navZoneCustomActions: rightFlipZoneTemplate,
-          showNavZoneDebugOverlay: true,
-        ),
+        globalPrefs: const GlobalReaderPrefs(
+          reading: ReadingDefaults(
+            pageTurnMode: PageTurnMode.scroll,
+            screenOrientation: ScreenOrientationSetting.lock270,
+          ),
+          navZone: NavZonePrefs(
+            navZoneMode: NavZoneMode.oneHand,
+            navZoneCustomActions: rightFlipZoneTemplate,
+            showNavZoneDebugOverlay: true,
+          ),
+        ),
       );
```

第 355／372 行（`navZoneMode`／`navZoneCustomActions`／`showNavZoneDebugOverlay` 三欄位一起出現、其餘用預設值）比照同樣模式，改成 `navZone: NavZonePrefs(navZoneMode: ..., navZoneCustomActions: ..., showNavZoneDebugOverlay: ...)`，`reading` 欄位若原本用 `pageTurnMode`/`screenOrientation` 也一併搬進 `reading: ReadingDefaults(...)`。

第 390 行附近（`volumeKeyEnabled`／`fullscreen`）：

```diff
       const globalPrefs = GlobalReaderPrefs(
-        pageTurnMode: PageTurnMode.paginated,
-        screenOrientation: ScreenOrientationSetting.auto,
-        navZoneMode: NavZoneMode.rightFlip,
-        navZoneCustomActions: rightFlipZoneTemplate,
-        showNavZoneDebugOverlay: false,
-        volumeKeyEnabled: false,
-        fullscreen: true,
+        reading: ReadingDefaults(
+          volumeKeyEnabled: false,
+          fullscreen: true,
+        ),
       );
```

（`navZoneMode`／`navZoneCustomActions`／`showNavZoneDebugOverlay` 在這幾個測試裡本來就是傳入既有預設值，`copyWith`／建構子有預設值後可以整段省略不寫，不影響測試意圖——測試名稱與斷言只關心 `volumeKeyEnabled`／`fullscreen`。）

第 419／443 行（`openLastBookOnLaunch`／`consoleLogEnabled`）比照：

```diff
-        openLastBookOnLaunch: false,
+        reading: ReadingDefaults(openLastBookOnLaunch: false),
```

```diff
-        consoleLogEnabled: true,
+        consoleLogEnabled: true,  // 攤平欄位，維持頂層不變
```

（`consoleLogEnabled` 本來就會留在 `GlobalReaderPrefs` 頂層，不需要搬進任何巢狀物件，這一處反而不用改。）

第 467 行（`showHeader`／`showFooter`／`ttsVoiceId`／`defaultTtsSpeed` 四個欄位橫跨兩組）：

```diff
       const globalPrefs = GlobalReaderPrefs(
-        showHeader: true,
-        showFooter: true,
-        ttsVoiceId: 'voice-42',
-        defaultTtsSpeed: 1.5,
+        reading: ReadingDefaults(showHeader: true, showFooter: true),
+        tts: TtsDefaults(ttsVoiceId: 'voice-42', defaultTtsSpeed: 1.5),
       );
```

第 503／514 行（`ttsVoiceId` 單獨出現）比照：

```diff
-        ttsVoiceId: 'voice-1',
+        tts: TtsDefaults(ttsVoiceId: 'voice-1'),
```

同步修改所有斷言路徑，例如：

```diff
-      expect(loaded.globalPrefs.volumeKeyEnabled, isFalse);
-      expect(loaded.globalPrefs.fullscreen, isTrue);
+      expect(loaded.globalPrefs.reading.volumeKeyEnabled, isFalse);
+      expect(loaded.globalPrefs.reading.fullscreen, isTrue);
```

```diff
-      expect(loaded.globalPrefs.showHeader, isTrue);
-      expect(loaded.globalPrefs.showFooter, isTrue);
-      expect(loaded.globalPrefs.ttsVoiceId, 'voice-42');
-      expect(loaded.globalPrefs.defaultTtsSpeed, 1.5);
+      expect(loaded.globalPrefs.reading.showHeader, isTrue);
+      expect(loaded.globalPrefs.reading.showFooter, isTrue);
+      expect(loaded.globalPrefs.tts.ttsVoiceId, 'voice-42');
+      expect(loaded.globalPrefs.tts.defaultTtsSpeed, 1.5);
```

`(await manager.loadGlobalPrefs()).ttsVoiceId` 這類直接鏈式呼叫改成
`(await manager.loadGlobalPrefs()).tts.ttsVoiceId`。

**第 110-159 行：`const GlobalReaderPrefs.initial().copyWith(xxx: value)` 這個模式（`resolve()` 雙層解析測試群組）——審查意見 I-2**：這幾處用 `.initial().copyWith(...)`，不是 `GlobalReaderPrefs(...)` 完整建構子呼叫，字面上不含 `GlobalReaderPrefs(` 這個子字串（`GlobalReaderPrefs` 後面接的是 `.initial(`，不是 `(`），規劃階段第一輪查證只搜尋 `GlobalReaderPrefs(` 因而完全漏掉這 5 處。逐一修正：

```diff
     test('book.fullscreen 為 null 時退回 global.fullscreen（非硬編碼 false，證明雙層解析生效）',
         () {
       final loaded = LoadedPrefs(
         bookPrefs: BookReaderPrefs.empty,
-        globalPrefs:
-            const GlobalReaderPrefs.initial().copyWith(fullscreen: true),
+        globalPrefs: const GlobalReaderPrefs.initial()
+            .copyWith(reading: const ReadingDefaults(fullscreen: true)),
       );
```

```diff
     test('book.fullscreen 存在時優先於 global.fullscreen', () {
       final loaded = LoadedPrefs(
         bookPrefs: const BookReaderPrefs(fullscreen: false),
-        globalPrefs:
-            const GlobalReaderPrefs.initial().copyWith(fullscreen: true),
+        globalPrefs: const GlobalReaderPrefs.initial()
+            .copyWith(reading: const ReadingDefaults(fullscreen: true)),
       );
```

```diff
     test('global.showHeader／showFooter 為 true 時，book 未覆寫則 resolve() 回傳 true（非硬編碼 false，證明雙層解析生效）',
         () {
       final loaded = LoadedPrefs(
         bookPrefs: BookReaderPrefs.empty,
-        globalPrefs: const GlobalReaderPrefs.initial()
-            .copyWith(showHeader: true, showFooter: true),
+        globalPrefs: const GlobalReaderPrefs.initial().copyWith(
+          reading: const ReadingDefaults(showHeader: true, showFooter: true),
+        ),
       );
```

```diff
     test('book.showHeader／showFooter 存在時優先於 global 對應欄位', () {
       final loaded = LoadedPrefs(
         bookPrefs: const BookReaderPrefs(showHeader: false, showFooter: false),
-        globalPrefs: const GlobalReaderPrefs.initial()
-            .copyWith(showHeader: true, showFooter: true),
+        globalPrefs: const GlobalReaderPrefs.initial().copyWith(
+          reading: const ReadingDefaults(showHeader: true, showFooter: true),
+        ),
       );
```

```diff
       final loadedDisabled = LoadedPrefs(
         bookPrefs: BookReaderPrefs.empty,
-        globalPrefs: const GlobalReaderPrefs.initial()
-            .copyWith(volumeKeyEnabled: false),
+        globalPrefs: const GlobalReaderPrefs.initial().copyWith(
+          reading: const ReadingDefaults(volumeKeyEnabled: false),
+        ),
       );
```

> [!NOTE]
> 這個檔案第 340-560 行左右還有其餘測試（`navZoneCustomActions` 損毀資料
> 回退等），規劃階段沒有逐字列出每一處——實作者需要對照
> `grep -n "globalPrefs\.\|GlobalReaderPrefs(\|GlobalReaderPrefs\.initial()" test/reader/reader_prefs_manager_test.dart`
> 的完整輸出（**注意**：`GlobalReaderPrefs\.initial()` 這個模式務必一併搜尋，
> 不能只搜 `GlobalReaderPrefs(`，見上方 I-2 修正說明——這正是規劃階段第一輪
> 漏掉 5 處的原因），依照上述模式（頂層攤平欄位改巢狀路徑、巢狀建構參數改
> 用對應子物件包一層）逐一修正，不要遺漏任何一處斷言路徑。

- [x] **Step 2：執行測試，確認失敗**

```bash
flutter test test/reader/reader_prefs_manager_test.dart
```

Expected：FAIL（編譯錯誤）——`ReaderPrefsManagerImpl.loadGlobalPrefs()`/`saveGlobalPrefs()`/`resolve()` 尚未改用巢狀讀寫。

- [x] **Step 3：修改 `reader_prefs_manager_impl.dart` 的 `loadGlobalPrefs()`**

```diff
   @override
   Future<GlobalReaderPrefs> loadGlobalPrefs() async {
     final sp = await SharedPreferences.getInstance();
     return GlobalReaderPrefs(
-      pageTurnMode: _readEnum(sp, _pageTurnModeKey, PageTurnMode.values) ??
-          PageTurnMode.paginated,
-      screenOrientation: _readEnum(
-            sp,
-            _screenOrientationKey,
-            ScreenOrientationSetting.values,
-          ) ??
-          ScreenOrientationSetting.auto,
-      navZoneMode: _readEnum(sp, _navZoneModeKey, NavZoneMode.values) ??
-          NavZoneMode.rightFlip,
-      navZoneCustomActions:
-          _decodeZoneActions(sp.getString(_navZoneCustomActionsKey)),
-      showNavZoneDebugOverlay: sp.getBool(_navZoneDebugOverlayKey) ?? false,
-      volumeKeyEnabled: sp.getBool(_volumeKeyEnabledKey) ?? true,
-      fullscreen: sp.getBool(_fullscreenKey) ?? false,
-      openLastBookOnLaunch: sp.getBool(_openLastBookOnLaunchKey) ?? true,
       consoleLogEnabled: sp.getBool(_consoleLogEnabledKey) ?? false,
-      showHeader: sp.getBool(_showHeaderKey) ?? false,
-      showFooter: sp.getBool(_showFooterKey) ?? false,
-      ttsVoiceId: sp.getString(_ttsVoiceIdKey),
-      defaultTtsSpeed: sp.getDouble(_defaultTtsSpeedKey) ?? 1.0,
+      navZone: NavZonePrefs(
+        navZoneMode: _readEnum(sp, _navZoneModeKey, NavZoneMode.values) ??
+            NavZoneMode.rightFlip,
+        navZoneCustomActions:
+            _decodeZoneActions(sp.getString(_navZoneCustomActionsKey)),
+        showNavZoneDebugOverlay: sp.getBool(_navZoneDebugOverlayKey) ?? false,
+      ),
+      tts: TtsDefaults(
+        ttsVoiceId: sp.getString(_ttsVoiceIdKey),
+        defaultTtsSpeed: sp.getDouble(_defaultTtsSpeedKey) ?? 1.0,
+      ),
+      reading: ReadingDefaults(
+        pageTurnMode: _readEnum(sp, _pageTurnModeKey, PageTurnMode.values) ??
+            PageTurnMode.paginated,
+        screenOrientation: _readEnum(
+              sp,
+              _screenOrientationKey,
+              ScreenOrientationSetting.values,
+            ) ??
+            ScreenOrientationSetting.auto,
+        volumeKeyEnabled: sp.getBool(_volumeKeyEnabledKey) ?? true,
+        fullscreen: sp.getBool(_fullscreenKey) ?? false,
+        openLastBookOnLaunch: sp.getBool(_openLastBookOnLaunchKey) ?? true,
+        showHeader: sp.getBool(_showHeaderKey) ?? false,
+        showFooter: sp.getBool(_showFooterKey) ?? false,
+      ),
     );
   }
```

在檔案頂端 import 區塊新增：

```diff
+import 'nav_zone_prefs.dart';
+import 'reading_defaults.dart';
+import 'tts_defaults.dart';
```

（SharedPreferences key 常數第 35-49 行**完全不動**——這是本次重構「持久化零風險」的核心，鍵名一個字都不能改。）

- [x] **Step 4：修改 `saveGlobalPrefs()`**

```diff
   @override
   Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs) async {
     final sp = await SharedPreferences.getInstance();
-    await sp.setString(_pageTurnModeKey, prefs.pageTurnMode.name);
-    await sp.setString(_screenOrientationKey, prefs.screenOrientation.name);
-    await sp.setString(_navZoneModeKey, prefs.navZoneMode.name);
+    await sp.setString(_pageTurnModeKey, prefs.reading.pageTurnMode.name);
+    await sp.setString(
+      _screenOrientationKey,
+      prefs.reading.screenOrientation.name,
+    );
+    await sp.setString(_navZoneModeKey, prefs.navZone.navZoneMode.name);
     await sp.setString(
       _navZoneCustomActionsKey,
-      _encodeZoneActions(prefs.navZoneCustomActions),
+      _encodeZoneActions(prefs.navZone.navZoneCustomActions),
     );
-    await sp.setBool(_navZoneDebugOverlayKey, prefs.showNavZoneDebugOverlay);
-    await sp.setBool(_volumeKeyEnabledKey, prefs.volumeKeyEnabled);
-    await sp.setBool(_fullscreenKey, prefs.fullscreen);
-    await sp.setBool(_openLastBookOnLaunchKey, prefs.openLastBookOnLaunch);
+    await sp.setBool(
+      _navZoneDebugOverlayKey,
+      prefs.navZone.showNavZoneDebugOverlay,
+    );
+    await sp.setBool(_volumeKeyEnabledKey, prefs.reading.volumeKeyEnabled);
+    await sp.setBool(_fullscreenKey, prefs.reading.fullscreen);
+    await sp.setBool(
+      _openLastBookOnLaunchKey,
+      prefs.reading.openLastBookOnLaunch,
+    );
     await sp.setBool(_consoleLogEnabledKey, prefs.consoleLogEnabled);
-    await sp.setBool(_showHeaderKey, prefs.showHeader);
-    await sp.setBool(_showFooterKey, prefs.showFooter);
+    await sp.setBool(_showHeaderKey, prefs.reading.showHeader);
+    await sp.setBool(_showFooterKey, prefs.reading.showFooter);
     // ttsVoiceId 為 nullable——setString 不接受 null，缺席時須明確 remove()
     // 該鍵，否則舊值會殘留，導致「清空語音選擇」的意圖被忽略。
-    if (prefs.ttsVoiceId != null) {
-      await sp.setString(_ttsVoiceIdKey, prefs.ttsVoiceId!);
+    if (prefs.tts.ttsVoiceId != null) {
+      await sp.setString(_ttsVoiceIdKey, prefs.tts.ttsVoiceId!);
     } else {
       await sp.remove(_ttsVoiceIdKey);
     }
-    await sp.setDouble(_defaultTtsSpeedKey, prefs.defaultTtsSpeed);
+    await sp.setDouble(_defaultTtsSpeedKey, prefs.tts.defaultTtsSpeed);
   }
```

- [x] **Step 5：修改 `resolve()`**

```diff
   ResolvedPreferences resolve(
     LoadedPrefs loaded, {
     WritingMode? autoDetectedWritingMode,
   }) {
     final book = loaded.bookPrefs;
     final global = loaded.globalPrefs;
     return ResolvedPreferences(
       ...（EPUB 字型/排版/PDF/雙頁欄位皆只讀 book，完全不動）...
-      pageTurnMode: book.pageTurnModeOverride ?? global.pageTurnMode,
+      pageTurnMode: book.pageTurnModeOverride ?? global.reading.pageTurnMode,
       screenOrientation:
-          book.screenOrientationOverride ?? global.screenOrientation,
+          book.screenOrientationOverride ?? global.reading.screenOrientation,
       ...（pdfFitMode 等 PDF/雙頁欄位完全不動）...
-      showHeader: book.showHeader ?? global.showHeader,
-      showFooter: book.showFooter ?? global.showFooter,
-      navZoneActions:
-          resolveZoneActions(global.navZoneMode, global.navZoneCustomActions),
-      showNavZoneDebugOverlay: global.showNavZoneDebugOverlay,
-      fullscreen: book.fullscreen ?? global.fullscreen,
-      volumeKeyEnabled: global.volumeKeyEnabled,
+      showHeader: book.showHeader ?? global.reading.showHeader,
+      showFooter: book.showFooter ?? global.reading.showFooter,
+      navZoneActions: resolveZoneActions(
+        global.navZone.navZoneMode,
+        global.navZone.navZoneCustomActions,
+      ),
+      showNavZoneDebugOverlay: global.navZone.showNavZoneDebugOverlay,
+      fullscreen: book.fullscreen ?? global.reading.fullscreen,
+      volumeKeyEnabled: global.reading.volumeKeyEnabled,
       consoleLogEnabled: global.consoleLogEnabled,
     );
   }
```

（`ResolvedPreferences` 本身的型別／欄位完全不變，`resolve()` 的方法簽章與回傳型別也不變——這一步只是把讀取 `global.xxx` 的路徑換成 `global.reading.xxx`／`global.navZone.xxx`／`global.tts.xxx`，`consoleLogEnabled` 因為留在頂層攤平不動。）

- [x] **Step 6：執行測試，確認通過**

```bash
flutter test test/reader/reader_prefs_manager_test.dart
```

Expected：全數 PASS。

- [x] **Step 7：`flutter analyze`（記錄現況，不代表本 Task 失敗）**

```bash
flutter analyze
```

Expected：仍**未必**乾淨——`library_screen.dart`／三個消費端畫面（`nav_zone_settings_screen.dart`／`tts_defaults_screen.dart`／`reading_defaults_screen.dart`）此時仍在用舊的攤平 API，留給 Task 4 修正，比照 Task 2 Step 5 的說明。

> [!IMPORTANT]
> **不在此執行 `git commit`（審查意見 C-2）**：`AGENTS.md` 與本計畫 Global
> Constraints 皆明文要求「`flutter analyze` 必須乾淨才能提交」，Step 7 尚未
> 乾淨，此時提交會產生違反該守則的 intermediate commit（破壞 `git bisect`
> 與 pre-commit 靜態檢查）。Task 2、Task 3、Task 4 視為同一個不可分割的
> 重構閉環——`global_reader_prefs.dart`／`reader_prefs_manager_impl.dart`
> 兩處改動先保留在工作目錄（`git status` 會顯示為未提交變更），繼續往下做
> Task 4，直到 Task 4 全專案 `flutter analyze`／`flutter test` 皆確認乾淨，
> 才在 Task 4 結尾執行一次涵蓋 Task 2-4 全部異動檔案的整合 commit。

---

### Task 4：更新三個消費端畫面＋`library_screen.dart`＋全部核心測試套件＋全專案編譯錯誤掃描＋回歸驗證＋整合 commit

**Files:**
- Modify：`app/lib/screens/nav_zone_settings_screen.dart`
- Modify：`app/lib/screens/tts_defaults_screen.dart`
- Modify：`app/lib/screens/reading_defaults_screen.dart`
- Modify：`app/lib/screens/library_screen.dart`（審查意見 C-1——`_maybeOpenLastBookOnLaunch()` 第 267 行讀取 `globalPrefs.openLastBookOnLaunch`，Issue 29 自動開書功能，生產程式碼，規劃階段第一輪查證遺漏）
- Modify：`app/test/screens/nav_zone_settings_screen_test.dart`
- Modify：`app/test/screens/tts_defaults_screen_test.dart`
- Modify：`app/test/screens/reading_defaults_screen_test.dart`
- Modify：`app/test/screens/library_screen_test.dart`（審查意見 I-1——6 處 `openLastBookOnLaunch:` fixture，第 96、3017、3052、3076、3310、3370 行）
- Modify：`app/test/screens/reader_screen_test.dart`（審查意見 I-1——2 處，第 1286 行 `pageTurnMode`、第 3251 行 `volumeKeyEnabled`）
- 可能需要修改：任何被 `flutter analyze` 揪出來、規劃階段未列出的其餘檔案（見下方 Step 5）

**Interfaces:**
- Consumes：Task 2／Task 3 的 `GlobalReaderPrefs`（巢狀）
- Produces：全專案 `flutter analyze` 乾淨、全專案 `flutter test` 全數通過——本 Task 是整個計畫唯一「完成」的判定點，也是 Task 2-4 整合 commit 的執行點

- [x] **Step 1：修改 `nav_zone_settings_screen.dart`**

把 `_prefs.navZoneMode`／`_prefs.navZoneCustomActions`／`_prefs.showNavZoneDebugOverlay` 三處讀取改為 `_prefs.navZone.navZoneMode` 等；`_prefs.copyWith(navZoneMode: mode)` 改為 `_prefs.copyWith(navZone: _prefs.navZone.copyWith(navZoneMode: mode))`：

```diff
   Future<void> _load() async {
     final prefs = await widget.prefsManager.loadGlobalPrefs();
     if (!mounted) return;
     setState(() {
       _prefs = prefs;
-      _customActions = List.of(prefs.navZoneCustomActions);
+      _customActions = List.of(prefs.navZone.navZoneCustomActions);
       _loading = false;
     });
   }

   void _selectMode(NavZoneMode mode) {
-    final updated = _prefs.copyWith(navZoneMode: mode);
+    final updated =
+        _prefs.copyWith(navZone: _prefs.navZone.copyWith(navZoneMode: mode));
     widget.prefsManager.saveGlobalPrefs(updated);
     setState(() {
       _prefs = updated;
-      _customActions = List.of(updated.navZoneCustomActions);
+      _customActions = List.of(updated.navZone.navZoneCustomActions);
       _validationError = null;
     });
   }

   void _toggleDebugOverlay(bool value) {
-    final updated = _prefs.copyWith(showNavZoneDebugOverlay: value);
+    final updated = _prefs.copyWith(
+      navZone: _prefs.navZone.copyWith(showNavZoneDebugOverlay: value),
+    );
     widget.prefsManager.saveGlobalPrefs(updated);
     setState(() => _prefs = updated);
   }
```

```diff
     final updated =
-        _prefs.copyWith(navZoneCustomActions: List.of(_customActions));
+        _prefs.copyWith(
+          navZone: _prefs.navZone
+              .copyWith(navZoneCustomActions: List.of(_customActions)),
+        );
```

其餘讀取點（`_prefs.navZoneMode == NavZoneMode.custom` 等，共 6 處，第 151／155／159／168／192／222／286 行）比照改成 `_prefs.navZone.navZoneMode`；`_prefs.showNavZoneDebugOverlay`（第 198 行）改成 `_prefs.navZone.showNavZoneDebugOverlay`。文件註解裡的 `[GlobalReaderPrefs.navZoneMode]` 連結（第 208 行）改成 `[NavZonePrefs.navZoneMode]` 並新增對應 import。

在檔案頂端新增 import：

```diff
+import '../reader/nav_zone_prefs.dart';
```

- [x] **Step 2：修改 `tts_defaults_screen.dart`**

```diff
                   RadioGroup<String>(
-                    groupValue: _prefs.ttsVoiceId ?? TtsVoice.systemDefault.id,
+                    groupValue:
+                        _prefs.tts.ttsVoiceId ?? TtsVoice.systemDefault.id,
                     onChanged: (voiceId) {
                       if (voiceId == null) return;
-                      _update(_prefs.copyWith(ttsVoiceId: voiceId));
+                      _update(_prefs.copyWith(
+                          tts: _prefs.tts.copyWith(ttsVoiceId: voiceId)));
                     },
```

其餘 `_prefs.defaultTtsSpeed` 讀取（第 116／131／137／150 行一帶）改成 `_prefs.tts.defaultTtsSpeed`；`_prefs.copyWith(defaultTtsSpeed: ...)`（第 118／163 行一帶）改成 `_prefs.copyWith(tts: _prefs.tts.copyWith(defaultTtsSpeed: ...))`。

在檔案頂端新增 import：

```diff
+import '../reader/tts_defaults.dart';
```

- [x] **Step 3：修改 `reading_defaults_screen.dart`**

7 個 `SwitchListTile`/`RadioGroup` 的 `value:`／`groupValue:`／`onChanged:` 全部改為讀寫 `_prefs.reading.xxx`／`_prefs.copyWith(reading: _prefs.reading.copyWith(xxx: value))`：

```diff
                 SwitchListTile(
                   key: const Key('reading_defaults_volume_key_switch'),
                   title: const Text('音量鍵翻頁'),
-                  value: _prefs.volumeKeyEnabled,
-                  onChanged: (value) =>
-                      _update(_prefs.copyWith(volumeKeyEnabled: value)),
+                  value: _prefs.reading.volumeKeyEnabled,
+                  onChanged: (value) => _update(_prefs.copyWith(
+                      reading:
+                          _prefs.reading.copyWith(volumeKeyEnabled: value))),
                 ),
                 const Divider(height: 1),
                 _buildSectionHeader(context, '翻頁模式'),
                 RadioGroup<PageTurnMode>(
-                  groupValue: _prefs.pageTurnMode,
-                  onChanged: (mode) =>
-                      _update(_prefs.copyWith(pageTurnMode: mode)),
+                  groupValue: _prefs.reading.pageTurnMode,
+                  onChanged: (mode) => _update(_prefs.copyWith(
+                      reading: _prefs.reading.copyWith(pageTurnMode: mode))),
```

（其餘 `screenOrientation`／`fullscreen`／`openLastBookOnLaunch`／`showHeader`／`showFooter` 五處比照同一種模式：`value`/`groupValue` 改讀 `_prefs.reading.xxx`，`onChanged` 改成 `_update(_prefs.copyWith(reading: _prefs.reading.copyWith(xxx: value)))`。實作者對照現有檔案第 98-171 行逐一替換，模式完全一致，不再逐段列出。）

在檔案頂端新增 import：

```diff
+import '../reader/reading_defaults.dart';
```

- [x] **Step 4：更新三個畫面對應的測試檔＋逐一跑該畫面測試（審查意見 M-3：不集中到最後才拿到第一次回饋）**

`app/test/screens/nav_zone_settings_screen_test.dart`／`tts_defaults_screen_test.dart`／`reading_defaults_screen_test.dart` 中所有 `FakeReaderPrefsManager(globalPrefs: const GlobalReaderPrefs.initial().copyWith(xxx: value))` 這類建構，把 `xxx: value` 改成對應的巢狀 `copyWith`，例如 `reading_defaults_screen_test.dart` 第 13 行附近：

```diff
     final manager = FakeReaderPrefsManager(
-      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
-        pageTurnMode: PageTurnMode.scroll,
-        ...
-      ),
+      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
+        reading: const ReadingDefaults.initial().copyWith(
+          pageTurnMode: PageTurnMode.scroll,
+          ...
+        ),
+      ),
     );
```

第 139／197 行（`openLastBookOnLaunch`／`showHeader`+`showFooter`）比照包一層 `reading: const ReadingDefaults.initial().copyWith(...)`。三個測試檔都需要新增對應的值物件 import（`nav_zone_prefs.dart`／`tts_defaults.dart`／`reading_defaults.dart`）。

**除了上面這種建構 fixture 的地方，三個測試檔裡大量的 `fakeManager.savedGlobalPrefsCalls.last.<field>` 斷言也要同步改成巢狀路徑（審查意見 I-3——規劃階段第一輪只顧到建構部分，完全漏掉這些斷言，實測共 20 餘處）**，例如：

```diff
-    expect(fakeManager.savedGlobalPrefsCalls.last.volumeKeyEnabled, isFalse);
+    expect(
+      fakeManager.savedGlobalPrefsCalls.last.reading.volumeKeyEnabled,
+      isFalse,
+    );
```

```diff
-    expect(fakeManager.savedGlobalPrefsCalls.last.showHeader, isTrue);
+    expect(fakeManager.savedGlobalPrefsCalls.last.reading.showHeader, isTrue);
```

```diff
-      fakeManager.savedGlobalPrefsCalls.last.navZoneMode,
+      fakeManager.savedGlobalPrefsCalls.last.navZone.navZoneMode,
```

```diff
-      fakeManager.savedGlobalPrefsCalls.last.navZoneCustomActions[0],
+      fakeManager.savedGlobalPrefsCalls.last.navZone.navZoneCustomActions[0],
```

```diff
-      fakeManager.savedGlobalPrefsCalls.last.defaultTtsSpeed,
+      fakeManager.savedGlobalPrefsCalls.last.tts.defaultTtsSpeed,
```

規則很單純：`fakeManager.savedGlobalPrefsCalls.last` 的型別是 `GlobalReaderPrefs`，凡是接在它後面的欄位屬於 Task 2 移進 `navZone`／`tts`／`reading` 的那 12 個欄位之一，就要多插一層對應的巢狀存取；只有 `consoleLogEnabled`（本次三個畫面皆不涉及）維持原樣。

> [!NOTE]
> 這三個測試檔規劃階段沒有逐字讀取全檔——只確認了它們一律透過
> `GlobalReaderPrefs.initial().copyWith(xxx: value)` 這個模式建構測試資料
> （不直接呼叫 `GlobalReaderPrefs(...)` 完整建構子）。實作者需要對照
> `grep -n "\.copyWith(\|savedGlobalPrefsCalls" test/screens/nav_zone_settings_screen_test.dart
> test/screens/tts_defaults_screen_test.dart
> test/screens/reading_defaults_screen_test.dart` 的完整輸出逐一修正
> （**注意**：grep pattern 務必含 `savedGlobalPrefsCalls`，不能只搜
> `\.copyWith(`，否則會重蹈 I-3 的覆轍，漏掉斷言那一半），確保每一處都改
> 成巢狀路徑。

改完三個測試檔後，逐一跑該畫面對應的測試檔，確認各自綠燈，不要等到 Step 7／Step 8 全專案掃描才第一次得到回饋：

```bash
flutter test test/screens/nav_zone_settings_screen_test.dart
flutter test test/screens/tts_defaults_screen_test.dart
flutter test test/screens/reading_defaults_screen_test.dart
```

Expected：三個檔案各自全數 PASS。

- [x] **Step 5：修改 `library_screen.dart`（審查意見 C-1，規劃階段第一輪查證遺漏的生產程式碼）**

`_maybeOpenLastBookOnLaunch()`（`app/lib/screens/library_screen.dart:267` 附近，Issue 29「啟動時開啟最後閱讀的書籍」功能）直接讀取舊的攤平欄位：

```diff
   Future<void> _maybeOpenLastBookOnLaunch() async {
     if (_activeGroupFilter != null) return;
     final globalPrefs = await widget.prefsManager.loadGlobalPrefs();
-    if (!globalPrefs.openLastBookOnLaunch) return;
+    if (!globalPrefs.reading.openLastBookOnLaunch) return;
```

不需要新增 import——`Book`／`GlobalReaderPrefs` 型別本來就已經在這個檔案的作用範圍內，`reading` 只是多一層欄位存取。

- [x] **Step 6：修改 `library_screen_test.dart`／`reader_screen_test.dart` 兩個核心測試套件（審查意見 I-1，規劃階段第一輪查證遺漏）**

`app/test/screens/library_screen_test.dart` 6 處 `const GlobalReaderPrefs.initial().copyWith(openLastBookOnLaunch: true/false)`（第 96、3017、3052、3076、3310、3370 行），一律改為：

```diff
-      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
-        openLastBookOnLaunch: false,
-      ),
+      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
+        reading: const ReadingDefaults.initial().copyWith(
+          openLastBookOnLaunch: false,
+        ),
+      ),
```

（`true`／`false` 依原本各處的值保留，只是包一層 `reading: const ReadingDefaults.initial().copyWith(...)`。）需要在檔案頂端新增 `import 'package:elinkbook/reader/reading_defaults.dart';`。

`app/test/screens/reader_screen_test.dart` 2 處：

```diff
   testWidgets('全域預設值已改為 scroll 時，未覆寫的書籍採用該全域值', (tester) async {
-    prefsManager.globalPrefs = prefsManager.globalPrefs.copyWith(
-      pageTurnMode: PageTurnMode.scroll,
-    );
+    prefsManager.globalPrefs = prefsManager.globalPrefs.copyWith(
+      reading: prefsManager.globalPrefs.reading.copyWith(
+        pageTurnMode: PageTurnMode.scroll,
+      ),
+    );
```

```diff
     final disabledPrefsManager = FakeReaderPrefsManager(
-      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
-        volumeKeyEnabled: false,
-      ),
+      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
+        reading: const ReadingDefaults.initial().copyWith(
+          volumeKeyEnabled: false,
+        ),
+      ),
     );
```

這個檔案原本已經 `import 'package:elinkbook/reader/global_reader_prefs.dart';`（供其他測試使用），Task 2 加上的 `export` 語句（審查意見 M-1）讓 `ReadingDefaults` 自動可見，不需要另外新增 import。

跑這兩個測試檔確認綠燈：

```bash
flutter test test/screens/library_screen_test.dart test/screens/reader_screen_test.dart
```

Expected：全數 PASS（`library_screen_test.dart`／`reader_screen_test.dart` 皆是本專案規模數一數二大的測試檔，執行需要一些時間，屬正常現象）。

- [x] **Step 7：`flutter analyze` 全專案掃描，逐一修正直到乾淨**

```bash
flutter analyze
```

**這是本計畫最關鍵的收斂步驟**：Global Constraints 已說明規劃階段的呼叫端清單不保證窮舉——即使加上本次審查修訂新補的 `library_screen.dart`／`library_screen_test.dart`／`reader_screen_test.dart` 三個檔案，仍不保證清單完整。依實際輸出的每一個編譯錯誤（`The getter 'pageTurnMode' isn't defined for the type 'GlobalReaderPrefs'` 之類），回到對應檔案改成巢狀路徑，重複執行直到：

```
Analyzing app...
No issues found!
```

- [x] **Step 8：全專案 `flutter test` 回歸驗證**

```bash
flutter test
```

Expected：全數 PASS，無失敗。這是本計畫唯一一次要求跑全套（不分檔案）測試——比照專案既有慣例，整份計畫的最後一個 Task 完成時執行一次。

> [!NOTE]
> **實際執行紀錄（`docs/superpowers/reviews/2026-09-13-code-review-split-global-reader-prefs.md` Important 1）**：本步驟實際執行時，全專案 `flutter test` 出現 2 個失敗（`app/test/screens/adaptive_shell_scaffold_test.dart` 的「上層 themeDependencies 更新後，已切換過去的 SettingsScreen 收到最新 isEinkMode」與「在設定分頁點擊「書架」圖示切回書架分頁」兩案例），字面上未達成「全數 PASS」。程式碼審查已另外在 main 分支（未套用本次重構）重現同一份測試檔，得到完全相同的兩個失敗與錯誤堆疊，確認為 main 分支既有、與本次 `GlobalReaderPrefs` 拆分無關的既存問題（該測試檔本身也不在本計畫變更清單內），非本次重構引入的回歸，故仍照計畫於 Step 9 提交。

- [x] **Step 9：Commit（Task 2-4 整合為一次提交，審查意見 C-2）**

本計畫的**唯一**一個涵蓋 Task 2／Task 3／Task 4 全部異動的整合 commit——Task 2、Task 3 結尾刻意不提交（見兩處 Task 收尾的 `[!IMPORTANT]` 說明），只有在這裡、`flutter analyze` 與全專案 `flutter test` 都確認乾淨之後，才第一次提交：

```bash
git add \
  lib/reader/global_reader_prefs.dart \
  lib/reader/reader_prefs_manager_impl.dart \
  lib/screens/nav_zone_settings_screen.dart \
  lib/screens/tts_defaults_screen.dart \
  lib/screens/reading_defaults_screen.dart \
  lib/screens/library_screen.dart \
  test/reader/global_reader_prefs_test.dart \
  test/reader/reader_prefs_manager_test.dart \
  test/screens/nav_zone_settings_screen_test.dart \
  test/screens/tts_defaults_screen_test.dart \
  test/screens/reading_defaults_screen_test.dart \
  test/screens/library_screen_test.dart \
  test/screens/reader_screen_test.dart
git commit -m "$(cat <<'EOF'
refactor(reader): GlobalReaderPrefs 改用 3 個巢狀值物件，更新持久化與全部消費端

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_012isCaPSCSdqh3R2Wapj5Nd
EOF
)"
```

> [!NOTE]
> 若 Step 7 修正的檔案超出本計畫列出的清單（例如揪出某個規劃階段沒發現的
> 呼叫端），一併加進這次 `git add`，不需要另開一個 Task——這正是
> Global Constraints 提前說明過的「用編譯器取代人工窮舉清單」的預期結果。

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **分組範圍推翻了兩次**：架構回顧報告原案（3 組有證據＋6 個雜項留聚合根）→ 訪談中途一度定案 4 組（額外拆出只有 2 欄位的獨立 `ChromeVisibility`）→ 最終依 `reading_defaults_screen.dart` 全檔實際內容確認為 3 組（`ReadingDefaults` 吸收 `showHeader`/`showFooter`，變成 7 欄位）。每次推翻都是因為前一版查證不完整（只看 grep 統計數字或部分程式碼摘要，沒有讀完整個消費端檔案），教訓：欄位分組的證據必須來自實際讀取完整消費端檔案，不能只信任片段摘要或既有報告的結論。
- **`CONTEXT.md` 詞彙表衝突已於本計畫撰寫前解決**：「閱讀預設值（Reading Defaults）」詞條原本明文寫「不是新的資料模型」，與本計畫要新增的 `ReadingDefaults` 資料類別直接衝突；已改寫該詞條反映兩者現在統一為同一件事，並順手更正了同一份文件裡另一句過時陳述（「僅螢幕方向與翻頁模式已接上 UI」）。執行本計畫時不需要再碰 `CONTEXT.md`。
- **持久化格式查證**：`ReaderPrefsManagerImpl` 逐欄位存 SharedPreferences key（非整包 JSON）這件事在 grilling 階段已用讀取原始碼確認，本計畫 Task 3 的 diff 直接反映這個事實——SharedPreferences key 常數本身完全不動。
- **無佔位符掃描**：Task 1／Task 2／Task 3 的程式碼皆完整可執行；Task 4 Step 1/2/3 對於「同一種修改模式重複出現多次」的部分（例如 `reading_defaults_screen.dart` 其餘 5 個欄位）明確標註「比照同一種模式，實作者對照現有檔案逐一替換」而非憑空編造每一段可能對不上實際程式碼行號的 diff——這是誠實標註「依賴實作者對照既有檔案」，不是敷衍的 TODO（比照 `2026-07-12-refactor-reader-prefs-manager.md` Task 3 Step 1 的同一種做法）。
- **型別/介面一致性**：`NavZonePrefs`／`TtsDefaults`／`ReadingDefaults`／`GlobalReaderPrefs` 四個型別的欄位名稱、`copyWith`/`==`/`hashCode` 簽章在 Task 1、2、3、4 之間逐字一致；`ResolvedPreferences` 型別本身在整份計畫中確認不變。
- **審查回應（`reviews/2026-09-13-review-split-global-reader-prefs.md`）**：C-1（`library_screen.dart` 生產程式碼遺漏）、C-2（Task 2／3 結尾違規提交）、I-1（`library_screen_test.dart`／`reader_screen_test.dart` 8 處遺漏）、I-2（`reader_prefs_manager_test.dart` 前段 5 處 `.initial().copyWith(...)` 遺漏——因為這個模式不含 `GlobalReaderPrefs(` 子字串，規劃階段第一輪 grep 完全沒搜到）、I-3（三個設定畫面測試的 `savedGlobalPrefsCalls` 斷言遺漏）、M-1（`export` 子值物件）、M-2（`ZoneAction` 來源描述筆誤）、M-3（Task 4 拆成逐畫面測試回饋）全數已修訂並在對應段落標註。採納 M-1 時額外發現審查建議本身若照字面只加 `export` 不加 `import` 會讓 `global_reader_prefs.dart` 自己編譯失敗（`export` 不會把符號帶進當前檔案的作用域）——已在實作程式碼裡同時保留 `import` 與 `export`，這是本次修訂過程中另外抓到、審查報告沒點出的一個小陷阱。
