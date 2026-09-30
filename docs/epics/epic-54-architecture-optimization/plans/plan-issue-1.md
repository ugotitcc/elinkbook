# Issue 1：可用字型（AvailableFonts）實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 把「偏好字型現在能不能用」這條規則收攏成一個純值物件 `AvailableFonts`，讓閱讀器渲染端與設定面板下拉選單共用同一個 `effectiveFamily()`，不再靠兩處註解維持一致。

**Architecture：** 新增 `app/lib/reader/available_fonts.dart`（純 Dart，不做 I/O）。`ReaderSettingsSheet` 改吃一個 `AvailableFonts`；`ReaderScreen` 把 4 個字型狀態欄位（`_customFonts`、`_installedFonts`、`_customFontsLoaded`、`_downloadedFontsLoaded`）換成單一 nullable `AvailableFonts? _availableFonts`（`null` 代表還在載入），並刪除私有的 `_renderedFontFamily`。`FoliateReaderView` 與 `buildFontFaceCss` 不動。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立的 `spec.md`，設計依據是 2026-09-30 `/grill-with-docs` 的決策，記錄於 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 1 設計決策」（Task 0 建立）與 `CONTEXT.md`「可用字型（Available Fonts）」詞條。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **不動的東西**：`FoliateReaderView` 對外建構參數、`buildFontFaceCss()`、`resolveCustomFontUri()`、`DownloadableFontStore`、`FontManagementScreen`、`supportedFonts`，以及 `ReaderScreen` 對外的公開建構參數（ADR 0007）。
- **不改寫偏好**：字型不可用時只影響渲染與顯示，絕不修改 `BookReaderPrefs.fontFamily`（ADR 0035）。
- **載入失敗語意不變**：已下載內建字型或自訂字型任一邊載入失敗，該邊視為空集合、仍能開書（既有測試 `reader_screen_test.dart` 的「installedFonts() 失敗時仍建構閱讀器」要求）。
- **Windows 環境**：`python` 在此環境不會實際執行（無輸出、檔案不變），不可用來編輯檔案；用 Edit 工具或 Node 腳本。多數原始檔是 CRLF 換行，Node 腳本要保留。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動實際觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：直接 TDD，不另寫其他 plan；程式審查先出報告（存於 `reviews/`，該目錄不進版控），審查者不直接改程式。

## Review Focus

以下是設計隱含、但既有測試沒涵蓋、最可能咬到使用者的情況（依可能性排序），每一條都有對應測試：

1. **一邊載入失敗、另一邊正常**：自訂字型清單讀取失敗時，已下載的內建字型仍要照原值生效（不能因為 `Future.wait` 的一邊例外就整個掛掉）。→ Task 3 新增 widget 測試。
2. **偏好為空字串 `''`**：不是 `null`，也不是任何字型，必須回傳 `null`，不能被當成有效家族名稱傳給 WebView。→ Task 1 純測試。
3. **自訂字型的家族名稱與內建字型相同**（例如使用者上傳的字型家族名也叫 `SourceHanSansTC`，而內建版沒下載）：自訂字型有自己的 `@font-face`，應視為可用。→ Task 1 純測試。
4. **字型載入中離開閱讀畫面**：載入完成後不可再 `setState`（`!mounted`），不可拋出例外。→ Task 3 新增 widget 測試。
5. **舊 WebView 載不動的字型**：`store.installedFonts()` 已過濾，`AvailableFonts` 不得再看到它；既有測試（Issue 7 兩個）必須維持綠燈，證明接線沒斷。→ Task 3 保留既有測試。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/available_fonts.dart` | 新增 | `AvailableFonts` 純值物件：`installedBuiltIn`、`customFonts`、`builtInFonts`、`effectiveFamily()`、`empty` |
| `app/test/reader/available_fonts_test.dart` | 新增 | `AvailableFonts` 純測試（規則的主要測試面） |
| `app/lib/screens/reader_settings_sheet.dart` | 修改 | 兩個參數 `customFonts`／`installedFonts` 換成一個 `availableFonts`；下拉選單「目前值」改用 `effectiveFamily()` |
| `app/test/screens/reader_settings_sheet_test.dart` | 修改 | `_pumpSheet` helper 與 1 處直接建構改用 `AvailableFonts`（其餘測試不變） |
| `app/lib/screens/reader_screen.dart` | 修改 | 4 個欄位→ `_availableFonts`；三個載入方法合併；刪除 `_renderedFontFamily`；gating 條件；兩處使用點 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 3 個規則類 widget test 刪除、2 個翻轉，新增 2 個接線測試 |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}` | 新增 | Epic 登錄與 Issue 清單（Task 0） |
| `docs/epics.md`、`.gitignore`、`CONTEXT.md` | 修改 | 看板新增第 55 列；reviews 規則；詞條（`CONTEXT.md` 已先行寫入，尚未 commit） |

---

### Task 0：登錄 Epic、建立分支

**Files：**
- Create: `docs/epics/epic-54-architecture-optimization/epic.md`
- Create: `docs/epics/epic-54-architecture-optimization/issues.md`
- Modify: `docs/epics.md`（第 54 列 `epic-53` 之後新增第 55 列）
- Modify: `.gitignore`（檔尾新增 reviews 規則）
- Commit（已存在的未提交異動）：`CONTEXT.md`（「可用字型」詞條）、本計畫檔

**Interfaces：**
- Consumes：無。
- Produces：後續 Task 都在分支 `epic-54/issue-1-available-fonts` 上提交。

- [x] **Step 1：建立分支**

```bash
cd /c/Users/fycdc/AI/elinkBook
git checkout main && git pull
git checkout -b epic-54/issue-1-available-fonts
```

Expected：`Switched to a new branch 'epic-54/issue-1-available-fonts'`。若 `git status` 顯示 `CONTEXT.md` 與本計畫檔為未提交，屬預期，會在 Step 5 一併提交。

- [x] **Step 2：建立 `epic.md`**

建立 `docs/epics/epic-54-architecture-optimization/epic.md`，內容：

```markdown
# `epic-54-architecture-optimization` 架構優化

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-54-architecture-optimization/`
**關聯 PRD 章節：** 無（純內部架構重構，不改變使用者可見功能，除 Issue 1 的一處刻意行為調整）
**關聯 ADR：** 0007、0035

## 背景

2026-09-30 `/improve-codebase-architecture` 檢視 epic-45／48／49／50／52／15 產出 7 個深化候選（報告 HTML 存於暫存目錄，不進版控）。候選 1 已由 `epic-53-sync-checkpoint-result` 完成並合併。使用者要求後續架構優化不要每一項各開一個 Epic，**集中在本 Epic，每個候選當作一張 Issue**（見 `issues.md`）。

## Issue 1 設計決策（`/grill-with-docs` 定案）

| 決策 | 結論 |
|---|---|
| module 範圍 | `AvailableFonts` 只做純推導，不做 I/O，不含 `@font-face` CSS |
| 不認得的名稱、沒有 store | 統一為 `effectiveFamily() == null`（行為調整：原本渲染端照原值傳，與下拉選單不一致） |
| `ReaderScreen` 狀態 | 4 個欄位換成單一 `AvailableFonts?`，`null` 代表載入中 |
| 命名 | 類別 `AvailableFonts`，檔案 `app/lib/reader/available_fonts.dart`，`CONTEXT.md` 詞條「可用字型」 |
| 既有 interface | `ReaderSettingsSheet` 改吃 `AvailableFonts`；`FoliateReaderView`／`buildFontFaceCss` 不改 |
| 測試 | 規則類搬到純測試；接線類留在 widget 層 |
| 載入失敗 | 任一邊失敗該邊視為空集合，仍組出 `AvailableFonts` |

## 開發記錄

**2026-09-30 登錄 Epic**，分支 `epic-54/issue-1-available-fonts`。實作計畫見 `plans/plan-issue-1.md`。
```

- [x] **Step 3：建立 `issues.md`**

建立 `docs/epics/epic-54-architecture-optimization/issues.md`，內容：

```markdown
# epic-54-architecture-optimization Issues

| # | 標題 | 強度 | 狀態 |
|---|---|---|---|
| 1 | 可用字型：收攏「偏好字型現在能不能用」規則（`AvailableFonts`） | Strong | 🟡 進行中（`plans/plan-issue-1.md`） |
| 2 | 同步與雲端匯入的「憑證失效」訊號形狀對齊（同步端已由 epic-53 對齊，僅需確認是否還有落差） | Worth exploring | ⚪ 待辦，尚未設計 |
| 3 | 字型重新連結搬出 Widget，與書籍重新連結（`relinkBook`）對齊；`takePersistableUriPermission` 授權策略集中 | Worth exploring | ⚪ 待辦，尚未設計 |
| 4 | 儲存權限探測移出 `foliate_native_bridge.dart`，改為獨立於閱讀器引擎的 module | Worth exploring | ⚪ 待辦，尚未設計 |
| 5 | 抽出 `ReaderScreen` 的「開書失敗、探測、重連、重開」狀態機 | Worth exploring | ⚪ 待辦，尚未設計 |
| 6 | 為四份 ARB 鍵一致性加自動守衛（鍵集合比對＋「刻意相同」白名單） | Worth exploring | ⚪ 待辦，尚未設計 |

Issue 2～6 只列標題，動手前須各自 `/grill-with-docs` 設計；候選來源與證據見 2026-09-30 架構檢視報告。
```

- [x] **Step 4：更新 `docs/epics.md` 與 `.gitignore`**

在 `docs/epics.md` 第 54 列（`epic-53-sync-checkpoint-result`）之後新增一列，內容：

```
| 55 | `epic-54-architecture-optimization` 架構優化（集中所有架構深化候選，每個候選一張 Issue） | 🟡 開發中 (Active) | Issue 1 進行中，路徑 `docs/epics/epic-54-architecture-optimization/` |
```

`.gitignore` 檔尾新增一行：

```
docs/epics/epic-54-architecture-optimization/reviews/
```

（兩個檔案是 CRLF；用 Edit 工具即可，不要用 python。）

- [x] **Step 5：Commit**

```bash
git add CONTEXT.md docs/epics.md .gitignore docs/epics/epic-54-architecture-optimization
git status --short
git commit -q -F - <<'EOF'
docs(epic-54): 登錄架構優化 Epic，新增「可用字型」詞條與 Issue 1 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
git log --oneline -1
```

Expected：`git status --short` 只列出上述檔案；`reviews/` 不會出現（已被忽略）。

---

### Task 1：`AvailableFonts` 純值物件（TDD）

**Files：**
- Create: `app/lib/reader/available_fonts.dart`
- Test: `app/test/reader/available_fonts_test.dart`

**Interfaces：**
- Consumes：`AppFont`（`app/lib/reader/app_font.dart`，含 `familyName` extension）、`CustomFont`（`app/lib/reader/custom_font.dart`，建構子 `CustomFont({int? id, required String displayName, required String familyName, required String fontUri})`）。
- Produces（Task 2、Task 3 依賴，名稱與型別不可更動）：

```dart
class AvailableFonts {
  const AvailableFonts({Set<AppFont> installedBuiltIn = const {}, List<CustomFont> customFonts = const []});
  static const AvailableFonts empty;
  final Set<AppFont> installedBuiltIn;
  final List<CustomFont> customFonts;
  List<AppFont> get builtInFonts;          // 依 AppFont.values 順序，只含 installedBuiltIn
  String? effectiveFamily(String? preferred);
}
```

- [x] **Step 1：寫失敗的測試**

建立 `app/test/reader/available_fonts_test.dart`：

```dart
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/available_fonts.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const kingHwa = CustomFont(
    displayName: '京華老宋體',
    familyName: 'KingHwa_OldSong',
    fontUri: 'content://example/kinghwa',
  );

  group('effectiveFamily：偏好字型現在能不能用（epic-54 Issue 1）', () {
    test('偏好為 null（使用書本字型）：回傳 null', () {
      const fonts = AvailableFonts(installedBuiltIn: {AppFont.sourceHanSerif});

      expect(fonts.effectiveFamily(null), isNull);
    });

    test('偏好為已下載的內建字型：照原值回傳', () {
      const fonts = AvailableFonts(installedBuiltIn: {AppFont.sourceHanSerif});

      expect(fonts.effectiveFamily('SourceHanSerifTC'), 'SourceHanSerifTC');
    });

    test('偏好為未下載的內建字型：回傳 null（偏好本身不會被改寫）', () {
      const fonts = AvailableFonts(installedBuiltIn: {AppFont.sourceHanSans});

      expect(fonts.effectiveFamily('SourceHanSerifTC'), isNull);
    });

    test('偏好為已恢復的內建字型（原俠正楷）：沒下載回傳 null，下載後照原值回傳', () {
      expect(const AvailableFonts().effectiveFamily('GuanKiapTsingKhai'), isNull);
      expect(
        const AvailableFonts(installedBuiltIn: {AppFont.guanKiapTsingKhai})
            .effectiveFamily('GuanKiapTsingKhai'),
        'GuanKiapTsingKhai',
      );
    });

    test('偏好為清單中的自訂字型：照原值回傳，即使沒有任何已下載的內建字型', () {
      const fonts = AvailableFonts(customFonts: [kingHwa]);

      expect(fonts.effectiveFamily('KingHwa_OldSong'), 'KingHwa_OldSong');
    });

    test('偏好為不認得的名稱：回傳 null（行為調整：與設定面板顯示一致）', () {
      const fonts = AvailableFonts(
        installedBuiltIn: {AppFont.sourceHanSerif},
        customFonts: [kingHwa],
      );

      expect(fonts.effectiveFamily('NoSuchFont'), isNull);
    });

    test('沒有任何來源（AvailableFonts.empty，例如測試與舊呼叫端）：內建字型偏好回傳 null', () {
      expect(AvailableFonts.empty.effectiveFamily('SourceHanSerifTC'), isNull);
    });

    test('偏好為空字串：回傳 null，不當成有效家族名稱（Review Focus 2）', () {
      const fonts = AvailableFonts(
        installedBuiltIn: {AppFont.sourceHanSerif},
        customFonts: [kingHwa],
      );

      expect(fonts.effectiveFamily(''), isNull);
    });

    test('自訂字型的家族名稱與未下載的內建字型相同：自訂字型有自己的 @font-face，視為可用（Review Focus 3）', () {
      const sameNameCustom = CustomFont(
        displayName: '我的思源黑體',
        familyName: 'SourceHanSansTC',
        fontUri: 'content://example/mine',
      );
      const fonts = AvailableFonts(customFonts: [sameNameCustom]);

      expect(fonts.effectiveFamily('SourceHanSansTC'), 'SourceHanSansTC');
    });
  });

  group('builtInFonts：下拉選單可列出的內建字型', () {
    test('依 AppFont.values 的順序，不受集合建構順序影響', () {
      const fonts = AvailableFonts(
        installedBuiltIn: {AppFont.taiwanPearl, AppFont.sourceHanSans},
      );

      expect(fonts.builtInFonts, [AppFont.sourceHanSans, AppFont.taiwanPearl]);
    });

    test('沒有任何已下載的內建字型：空清單', () {
      expect(AvailableFonts.empty.builtInFonts, isEmpty);
    });
  });
}
```

- [x] **Step 2：確認測試失敗**

Run（在 `app/` 目錄）：`flutter test test/reader/available_fonts_test.dart`
Expected：編譯失敗，訊息含 `Target of URI doesn't exist: 'package:elinkbook/reader/available_fonts.dart'`。

- [x] **Step 3：寫最小實作**

建立 `app/lib/reader/available_fonts.dart`：

```dart
import 'app_font.dart';
import 'custom_font.dart';

/// 可用字型（epic-54-architecture-optimization Issue 1，見 CONTEXT.md「可用字型」）：
/// 這台裝置、這次開書能實際渲染的字型集合——已下載且系統 WebView 載得動的內建
/// 字型，加上自訂字型。
///
/// 純值物件、不做 I/O：載入由呼叫端負責（[installedBuiltIn] 來自
/// `DownloadableFontStore.installedFonts()`，該方法已依 `supportedFonts` 過濾
/// WebView 載不動的字型；[customFonts] 來自 `CustomFontsRepository.listAll()`）。
///
/// 「偏好字型現在能不能用」這條規則只在 [effectiveFamily]：閱讀器渲染端與設定面板
/// 下拉選單的目前值共用同一個方法，兩邊不可能再分歧。
class AvailableFonts {
  /// 已下載且 WebView 載得動的內建字型。
  final Set<AppFont> installedBuiltIn;

  /// 使用者上傳的自訂字型（ADR 0021）。
  final List<CustomFont> customFonts;

  const AvailableFonts({
    this.installedBuiltIn = const {},
    this.customFonts = const [],
  });

  /// 什麼都沒有：兩個來源都沒提供（測試與舊呼叫端），或載入失敗的退路。
  static const AvailableFonts empty = AvailableFonts();

  /// 下拉選單可列出的內建字型，依 [AppFont.values] 的順序，不受集合迭代順序影響。
  List<AppFont> get builtInFonts => [
        for (final font in AppFont.values)
          if (installedBuiltIn.contains(font)) font,
      ];

  /// 偏好字型 [preferred]（`BookReaderPrefs.fontFamily`）實際該用的家族名稱。
  ///
  /// 偏好是「使用書本字型」（null），或指向不可用的字型（尚未下載、已刪除、
  /// WebView 載不動、名稱不認得、空字串）時回傳 null，讓書本字型生效；否則照
  /// 原值回傳。只影響渲染與顯示，**絕不改寫偏好**——字型之後變成可用（例如下載
  /// 完成）就自然恢復（ADR 0035）。
  String? effectiveFamily(String? preferred) {
    if (preferred == null) return null;
    if (installedBuiltIn.any((font) => font.familyName == preferred)) return preferred;
    if (customFonts.any((font) => font.familyName == preferred)) return preferred;
    return null;
  }
}
```

- [x] **Step 4：確認測試通過**

Run：`flutter test test/reader/available_fonts_test.dart`
Expected：`All tests passed!`（11 個測試）。

- [x] **Step 5：Commit**

```bash
git add app/lib/reader/available_fonts.dart app/test/reader/available_fonts_test.dart
git commit -q -F - <<'EOF'
feat(reader): epic-54 Issue 1 新增 AvailableFonts 純值物件

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2：`ReaderSettingsSheet` 改吃 `AvailableFonts`

**Files：**
- Modify: `app/lib/screens/reader_settings_sheet.dart`（欄位 `:34-37`、建構子 `:60-61`、`_buildFontFamilyDropdown` `:692-737`、import 區）
- Modify: `app/lib/screens/reader_screen.dart:1070-1071`（暫時性接線，Task 3 會再整理）
- Modify: `app/test/screens/reader_settings_sheet_test.dart`（`_pumpSheet` helper `:2508-2511`、直接建構 `:1249`（過長自訂字型名稱測試）與 `:2442-2443`）
- Modify: `app/test/screens/reader_screen_test.dart`（兩處 `sheet.installedFonts`）

**Interfaces：**
- Consumes：Task 1 的 `AvailableFonts`（`builtInFonts`、`customFonts`、`effectiveFamily()`）。
- Produces：`ReaderSettingsSheet({..., AvailableFonts availableFonts = AvailableFonts.empty, ...})`，欄位 `final AvailableFonts availableFonts;`。舊的 `customFonts`／`installedFonts` 兩個參數**移除**。

- [x] **Step 1：先改測試（讓它們因為參數不存在而編譯失敗）**

`app/test/screens/reader_settings_sheet_test.dart`：

(a) `_pumpSheet` helper（約 `:2508-2511`）：把
```dart
        customFonts: customFonts,
        // 既有測試的前提都是「內建字型已經可用」，沿用這個前提：沒指定時視為全部已下載。
        // 驗證「只列出已下載字型」的新測試會明確傳入集合。
        installedFonts: installedFonts ?? AppFont.values.toSet(),
```
改為
```dart
        // 既有測試的前提都是「內建字型已經可用」，沿用這個前提：沒指定時視為全部已下載。
        // 驗證「只列出已下載字型」的新測試會明確傳入集合。
        availableFonts: AvailableFonts(
          installedBuiltIn: installedFonts ?? AppFont.values.toSet(),
          customFonts: customFonts,
        ),
```
helper 自己的參數（`customFonts`、`installedFonts`）與所有呼叫它的測試**都不改**。

(b) 直接建構處（約 `:2442-2443`）：把
```dart
                customFonts: const [],
                installedFonts: AppFont.values.toSet(),
```
改為
```dart
                availableFonts: AvailableFonts(installedBuiltIn: AppFont.values.toSet()),
```

(b2) 直接建構處（約 `:1243-1256`，測試「自訂字型清單中存在過長顯示名稱時，字型下拉選單不應造成 RenderFlex overflow」）：這裡直接在 `ReaderSettingsSheet(...)` 傳了 `customFonts:`，必須一併改（審查 C-1，否則 Step 2／Step 5 會因 `The named parameter 'customFonts' isn't defined` 編譯失敗）。把
```dart
          customFonts: const [
            CustomFont(
              id: 1,
              displayName: '這是一個非常非常非常長的自訂字型顯示名稱範例測試用',
              familyName: 'CustomLongFontName',
              fontUri: 'content://example/font1',
            ),
          ],
```
改為
```dart
          availableFonts: const AvailableFonts(
            customFonts: [
              CustomFont(
                id: 1,
                displayName: '這是一個非常非常非常長的自訂字型顯示名稱範例測試用',
                familyName: 'CustomLongFontName',
                fontUri: 'content://example/font1',
              ),
            ],
          ),
```
（盤點結果：`reader_settings_sheet_test.dart` 內直接對建構子傳 `customFonts:`／`installedFonts:` 的只有 `:1249`、`:2442-2443`、`:2508-2511` 三處；`:1100-1208` 是 `_pumpSheet` helper 的具名參數，helper 簽章不改；其餘 `ReaderSettingsSheet(` 建構處都沒傳字型參數。）

(c) 檔案頂部 import 區新增：`import 'package:elinkbook/reader/available_fonts.dart';`

`app/test/screens/reader_screen_test.dart`：把兩處 `sheet.installedFonts` 改為 `sheet.availableFonts.installedBuiltIn`（約 `:6790` `expect(sheet.installedFonts, {AppFont.sourceHanSans});`、約 `:6948` `expect(sheet.installedFonts, isEmpty);`）。

- [x] **Step 2：確認失敗**

Run：`flutter test test/screens/reader_settings_sheet_test.dart`
Expected：編譯失敗，訊息含 `No named parameter with the name 'availableFonts'`。

- [x] **Step 3：修改 `ReaderSettingsSheet`**

`app/lib/screens/reader_settings_sheet.dart`：

(a) 欄位（約 `:34-37`）：把
```dart
  final List<CustomFont> customFonts;
  /// 已下載的內建字型（epic-49）。字型選單只列出這些內建字型，
  /// 選了一定有效果；一款都沒有時在選單下方提示去字型管理下載。
  final Set<AppFont> installedFonts;
```
改為
```dart
  /// 可用字型（epic-54 Issue 1，見 CONTEXT.md「可用字型」）。字型選單只列出已下載的
  /// 內建字型與自訂字型，選了一定有效果；一款內建字型都沒有時在選單下方提示去字型
  /// 管理下載。目前值與閱讀器渲染端共用 [AvailableFonts.effectiveFamily]。
  final AvailableFonts availableFonts;
```

(b) 建構子（約 `:60-61`）：把
```dart
    this.customFonts = const [],
    this.installedFonts = const {},
```
改為
```dart
    this.availableFonts = AvailableFonts.empty,
```

(c) `_buildFontFamilyDropdown`（約 `:692-737`）：

把
```dart
    // 依 AppFont.values 的順序列出，不受集合迭代順序影響
    final builtInFonts =
        AppFont.values.where(widget.installedFonts.contains).toList();
```
改為
```dart
    final fonts = widget.availableFonts;
    final builtInFonts = fonts.builtInFonts;
```

把 `value:` 那一段（含前面的三行註解）
```dart
                  // 偏好設定可能指向已停用（epic-48）或尚未下載／已刪除（epic-49）的
                  // 內建字型，該值不在選項中時 DropdownButton 會 assert 失敗，改顯示為
                  // 「使用書本字型」。只影響顯示，不改寫偏好設定，字型下載後舊設定
                  // 自然生效。
                  value: {
                    ...builtInFonts.map((f) => f.familyName),
                    ...widget.customFonts.map((f) => f.familyName),
                  }.contains(_fontFamily)
                      ? _fontFamily
                      : null,
```
改為
```dart
                  // 偏好可能指向尚未下載／已刪除／載不動的內建字型或不認得的名稱，
                  // 該值不在選項中時 DropdownButton 會 assert 失敗，改顯示為「使用
                  // 書本字型」。與閱讀器渲染端共用 effectiveFamily，兩邊一致；只影響
                  // 顯示，不改寫偏好設定，字型下載後舊設定自然生效。
                  value: fonts.effectiveFamily(_fontFamily),
```

把
```dart
                    ...widget.customFonts.map(
```
改為
```dart
                    ...fonts.customFonts.map(
```

(d) import：新增 `import '../reader/available_fonts.dart';`。若 `flutter analyze` 回報 `custom_font.dart` 未使用，就移除該 import；`app_font.dart` 同理（`font.displayName(l10n)` 需要 extension，通常仍會用到）。

- [x] **Step 4：暫時性接線 `ReaderScreen`**

`app/lib/screens/reader_screen.dart` 約 `:1070-1071`：把
```dart
            customFonts: _customFonts,
            installedFonts: _installedFonts,
```
改為
```dart
            availableFonts: AvailableFonts(
              installedBuiltIn: _installedFonts,
              customFonts: _customFonts,
            ),
```
並新增 `import '../reader/available_fonts.dart';`。（這是 Task 3 之前的過渡寫法，Task 3 會換成單一欄位。）

- [x] **Step 5：確認通過**

Run：
```bash
flutter analyze
flutter test test/reader/available_fonts_test.dart test/screens/reader_settings_sheet_test.dart
flutter test test/screens/reader_screen_test.dart --plain-name "epic-49"
```
Expected：`No issues found!`；兩批測試 `All tests passed!`（第三批先確認接線沒斷；名稱過濾若沒有命中，改跑 `--plain-name "已下載字型"`）。

- [x] **Step 6：Commit**

```bash
git add app/lib app/test
git commit -q -F - <<'EOF'
refactor(reader): epic-54 Issue 1 ReaderSettingsSheet 改吃 AvailableFonts

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3：`ReaderScreen` 改用單一 `AvailableFonts?`

**Files：**
- Modify: `app/lib/screens/reader_screen.dart`（欄位 `:458-479`、`initState` `:649-650`、載入方法 `:1437-1487`、gating `:3171-3177`、設定面板 `:1070-1073`、`_buildNativeView` `:3621` 起與 `:3647`、`:3668-3669`）
- Modify: `app/test/screens/reader_screen_test.dart`（字型規則區塊約 `:6690-6985`）

**Interfaces：**
- Consumes：Task 1 的 `AvailableFonts`、Task 2 的 `ReaderSettingsSheet(availableFonts:)`。
- Produces：`ReaderScreen` 對外行為不變（公開建構參數不動，ADR 0007）；`FoliateReaderView.fontFamily` 的值改由 `AvailableFonts.effectiveFamily()` 決定（行為調整：不認得的名稱與沒有 store 時為 `null`）。

- [ ] **Step 1：先改測試（RED）**

在 `app/test/screens/reader_screen_test.dart`，「未下載字型改用書本字型（epic-49 Issue 6）」`group` 內（`pumpReader`、`readerView` helper 所在處）：

(a) **翻轉**「不認得的字型名稱照原值傳遞（審查重點 4）」：把測試名稱與斷言改為

```dart
    testWidgets('不認得的字型名稱改傳 null，偏好不改寫（epic-54 Issue 1：與設定面板顯示一致）',
        (tester) async {
      // epic-49 Issue 8 恢復原俠正楷後，改用真的不存在的名稱，保留原本的意圖
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'NoSuchFont'));

      await pumpReader(tester, store: FakeDownloadableFontStore());

      expect(readerView(tester).fontFamily, isNull);
      expect(prefsManager.bookPrefsByBookId['b1']!.fontFamily, 'NoSuchFont');
    });
```

(a2) **翻轉**「沒有 store 時照原值傳遞，行為與 Issue 4 相同（審查重點 5）」（審查 I-3：這是刻意的行為調整，必須在 Widget 層留一個整合測試證明「沒有 store」端到端確實傳 `null`，不能只靠純測試）：

```dart
    testWidgets('沒有 store 時改傳 null，偏好不改寫（epic-54 Issue 1：與設定面板顯示一致）',
        (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'SourceHanSerifTC'));

      await pumpReader(tester); // downloadableFontStore 預設為 null

      expect(readerView(tester).fontFamily, isNull);
      expect(prefsManager.bookPrefsByBookId['b1']!.fontFamily, 'SourceHanSerifTC');
    });
```

(b) **刪除**下列 3 個測試（它們的規則已由 `available_fonts_test.dart` 的純測試涵蓋，且各自只是同一規則換個字型或情境的重複案例）：
- 「偏好為 null（使用書本字型）時，閱讀器收到 null（計畫審查 M-2）」
- 「epic-48 以前選的原俠正楷，沒下載時閱讀器收到 null，偏好不改寫（Issue 8）」
- 「epic-48 以前選的原俠正楷，下載後照原值傳遞（Issue 8）」

**保留不刪**（接線或代表性案例）：「偏好為未下載的內建字型時，閱讀器收到 null，偏好本身不改寫」、「偏好為已下載的內建字型時，照原值傳遞」、「installedFonts() 失敗時，內建字型偏好改傳 null」、「閱讀中改選已下載字型，閱讀器立即收到新字型」、「自訂字型照原值傳遞…」，兩個舊 WebView 測試（Review Focus 5），以及上面 (a)、(a2) 翻轉後的兩個。

（誠實記錄：設計討論時估計可刪 8～9 個；實際盤點後可安全刪除的是 3 個重複的規則案例，另 2 個翻轉（不認得的名稱、沒有 store，皆為 Q2 的行為調整），其餘都是接線或代表性案例，必須保留。）

(c) **新增**兩個接線測試（同一個 group 內，`readerView` 之後）：

```dart
    testWidgets('自訂字型讀取失敗時，已下載的內建字型仍照原值傳遞（epic-54 Review Focus 1）',
        (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'SourceHanSerifTC'));
      final store = FakeDownloadableFontStore()..installed.add(AppFont.sourceHanSerif);
      final customFonts = FakeCustomFontsRepository()..loadGate = Completer<void>();

      await pumpReader(tester, store: store, customFontsRepository: customFonts);
      customFonts.loadGate!.completeError(StateError('denied'));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(readerView(tester).fontFamily, 'SourceHanSerifTC');
    });

    testWidgets('字型載入中離開閱讀畫面，載入完成後不拋出例外（epic-54 Review Focus 4）',
        (tester) async {
      final store = FakeDownloadableFontStore()..installedFontsGate = Completer<void>();

      await pumpReader(tester, store: store);
      await tester.pumpWidget(const SizedBox());
      store.installedFontsGate!.complete();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
```

- [ ] **Step 2：確認 RED**

Run：`flutter test test/screens/reader_screen_test.dart --plain-name "不認得的字型名稱改傳 null"`
Expected：FAIL（`Expected: null  Actual: 'NoSuchFont'`）。兩個新增接線測試此時可能已通過（現行實作恰好滿足），這是預期的：它們是護欄，在重構後也必須維持綠燈。

- [ ] **Step 3：修改 `ReaderScreen` 欄位**

`app/lib/screens/reader_screen.dart`：

(a) 刪除 `List<CustomFont> _customFonts = [];` 與其上方 2 行註解（約 `:458-460`）。

(b) 刪除 `_customFontsLoaded` 的整段註解與欄位（約 `:464-472`，從 `// 自訂字型清單是否已完成載入判斷` 到 `late bool _customFontsLoaded = ...;`），以及 `_installedFonts`、`_downloadedFontsLoaded` 兩段註解與欄位（約 `:473-479`）。保留 `_layoutPresets` 那一段，但把其註解中的「比照既有 _customFonts 一次性載入快取模式；」改為「比照既有一次性載入快取模式；」（約 `:462`，這是 Step 6 grep 唯一會命中的殘留，審查 I-4）。

(c) 在原位置新增：

```dart
  // 可用字型（epic-54 Issue 1，見 CONTEXT.md「可用字型」）：已下載的內建字型加自訂
  // 字型，開書時各載入一次，閱讀期間不會改變（字型管理畫面不在閱讀器內，下載或
  // 刪除都要離開閱讀器）。兩邊都讀完（任一邊失敗視為空集合）才組出，在那之前為
  // null。FoliateReaderView 的初始網址（內含 @font-face）是 late final，提早建構
  // 就再也不會套用字型，所以 _buildBody 在 null 時延後建構閱讀器（取代原本的
  // _customFontsLoaded／_downloadedFontsLoaded 兩個旗標）。兩個來源都沒提供
  // （測試與舊呼叫端）時沒有東西要等，一開始就是 empty。
  late AvailableFonts? _availableFonts =
      widget.customFontsRepository == null && widget.downloadableFontStore == null
          ? AvailableFonts.empty
          : null;
```

- [ ] **Step 4：合併載入方法、刪除 `_renderedFontFamily`**

(a) `initState`（約 `:649-650`）：把
```dart
    _loadCustomFonts();
    _loadDownloadedFonts();
```
改為
```dart
    _loadAvailableFonts();
```

(b) 把 `_loadCustomFonts()`、`_loadDownloadedFonts()`、`_renderedFontFamily()` 三個方法（含 `_renderedFontFamily` 上方整段文件註解，約 `:1437-1487`）整段換成：

```dart
  /// 載入可用字型（epic-54 Issue 1）：已下載的內建字型與自訂字型各自讀取、各自
  /// 處理失敗（視為空集合，不阻擋開書），兩邊都完成才一次組出 [AvailableFonts]。
  Future<void> _loadAvailableFonts() async {
    if (_availableFonts != null) return;
    // Dart 3 record 的 .wait：強型別，不依賴陣列下標與強制轉型（審查 M-1）。
    // 兩個方法各自 catch，不會拋出例外，所以不會出現 ParallelWaitError。
    final (installedBuiltIn, customFonts) = await (
      _loadInstalledBuiltInFonts(),
      _loadCustomFonts(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _availableFonts = AvailableFonts(
        installedBuiltIn: installedBuiltIn,
        customFonts: customFonts,
      );
    });
  }

  Future<Set<AppFont>> _loadInstalledBuiltInFonts() async {
    final store = widget.downloadableFontStore;
    if (store == null) return const {};
    try {
      return await store.installedFonts();
    } catch (e) {
      debugPrint('Failed to load downloaded fonts: $e');
      return const {};
    }
  }

  Future<List<CustomFont>> _loadCustomFonts() async {
    final repository = widget.customFontsRepository;
    if (repository == null) return const [];
    try {
      return await repository.listAll();
    } catch (e) {
      debugPrint('Failed to load custom fonts: $e');
      return const [];
    }
  }
```

- [ ] **Step 5：改三個使用點**

(a) 設定面板（Task 2 的過渡寫法，約 `:1070-1073`）：把
```dart
            availableFonts: AvailableFonts(
              installedBuiltIn: _installedFonts,
              customFonts: _customFonts,
            ),
```
改為
```dart
            availableFonts: _availableFonts ?? AvailableFonts.empty,
```

(b) gating（約 `:3171-3177`）：把
```dart
                    (_dispatchedIsFixedLayout != null &&
                        _customFontsLoaded &&
                        _downloadedFontsLoaded)))
```
改為
```dart
                    (_dispatchedIsFixedLayout != null &&
                        _availableFonts != null)))
```

(c) `_buildNativeView`（約 `:3621`）：在方法開頭 `final resolved = _resolved!;` 之後新增一行
```dart
    final fonts = _availableFonts ?? AvailableFonts.empty;
```
把 `fontFamily: _renderedFontFamily(resolved.fontFamily),`（約 `:3647`）改為
```dart
          fontFamily: fonts.effectiveFamily(resolved.fontFamily),
```
把（約 `:3668-3669`）
```dart
          customFonts: _customFonts,
          installedFonts: _installedFonts,
```
改為
```dart
          customFonts: fonts.customFonts,
          installedFonts: fonts.installedBuiltIn,
```

- [ ] **Step 6：確認沒有遺留舊名稱**

Run：`grep -n "_customFonts\b\|_customFontsLoaded\|_downloadedFontsLoaded\|_installedFonts\|_renderedFontFamily" app/lib/screens/reader_screen.dart`
Expected：**沒有輸出**。若 `flutter analyze` 回報 `unused import`，移除該 import。

- [ ] **Step 7：確認 GREEN**

Run：
```bash
flutter analyze
flutter test test/reader/available_fonts_test.dart test/screens/reader_settings_sheet_test.dart
flutter test test/screens/reader_screen_test.dart
```
Expected：`No issues found!`；三批 `All tests passed!`。`reader_screen_test.dart` 整檔約 12,000 行，需要數分鐘，屬預期。

若 `reader_screen_test.dart` 有其他測試因為「首幀多等一個 microtask」而失敗（兩個來源都提供時，`_availableFonts` 需要等 `Future.wait`），先確認失敗的測試是否在 pump 前後少了 `await tester.runAsync(() => Future.delayed(Duration.zero))`；既有字型測試用的 `pumpReader` helper 已包含這個寫法，可比照。**不可**為了讓測試通過而放寬 gating 條件。

- [ ] **Step 8：Commit**

```bash
git add app/lib app/test
git commit -q -F - <<'EOF'
refactor(reader): epic-54 Issue 1 ReaderScreen 改用單一 AvailableFonts，渲染端與設定面板共用 effectiveFamily

- 4 個字型狀態欄位換成 AvailableFonts?（null＝載入中），刪除 _renderedFontFamily。
- 行為調整：偏好為不認得的名稱、或沒有 store 時，渲染端改傳 null，與設定面板顯示一致。
- reader_screen_test：規則類案例移到 available_fonts_test，翻轉 2 個、刪除 3 個重複案例，
  新增「一邊載入失敗」「載入中離開畫面」兩個接線測試。

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4：驗證、記錄與交付

**Files：**
- Modify: `docs/epics/epic-54-architecture-optimization/epic.md`（開發記錄）
- Modify: `docs/epics/epic-54-architecture-optimization/issues.md`（Issue 1 狀態）
- Modify: `docs/epics.md`（第 55 列備註）

**Interfaces：**
- Consumes：Task 0～3 的全部成果。
- Produces：一個可送審、可發 PR 的分支。

- [ ] **Step 1：靜態檢查**

Run（在 `app/`）：
```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```
Expected：`No issues found!`；兩行 `PASS`。

- [ ] **Step 2：跑異動觸及的測試檔（不跑全套）**

```bash
flutter test test/reader/available_fonts_test.dart test/reader/foliate_native_bridge_test.dart test/reader/foliate_reader_view_test.dart test/screens/reader_settings_sheet_test.dart test/screens/reader_screen_test.dart test/screens/font_management_screen_test.dart test/reader/downloadable_font_store_test.dart
```
Expected：`All tests passed!`。（`foliate_*`、`font_management_*`、`downloadable_font_store_*` 沒有被改動，跑它們是為了確認「不動的東西」真的沒被牽動。）

- [ ] **Step 3：更新記錄**

在 `epic.md` 的「開發記錄」新增一段，內容為：實作摘要（新增 `AvailableFonts`；`ReaderSettingsSheet` 參數 2→1；`ReaderScreen` 4 個欄位→1 個；刪除 `_renderedFontFamily`）、行為調整（不認得的名稱與沒有 store → `null`）、測試變動（純測試 11 個；`reader_screen_test` 翻轉 2、刪除 3、新增 2）、驗證結果（實際跑出的通過數與 analyze 結果，**不可預先填寫**）。`issues.md` 的 Issue 1 狀態改為「🟡 實作完成，待審查」；`docs/epics.md` 第 55 列備註改為「Issue 1 實作完成，待審查」。

- [ ] **Step 4：Commit 記錄**

```bash
git add docs
git commit -q -F - <<'EOF'
docs(epic-54): Issue 1 實作完成，更新 epic.md 進度

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 5：交付（需使用者指示，執行者不可自行進行）**

1. 程式審查：先產出報告 `docs/epics/epic-54-architecture-optimization/reviews/review-code.md`（不進版控），列出問題交使用者決定；審查者不直接修改程式。
2. 審查問題處理完畢後，跑一次完整 `flutter test`（無參數，約 5 分鐘）。
3. 全套通過後，經使用者同意才 push 並開 PR（Gitea：用 Gitea API，token 取自 remote URL，不可顯示在輸出）。

---

## 自我檢查

**設計決策覆蓋**

| 決策 | 對應 Task |
|---|---|
| Q1 純推導、不含 CSS／載入 | Task 1（純值物件）；`buildFontFaceCss` 不在任何 Task 的修改清單 |
| Q2 不認得的名稱、沒有 store → `null` | Task 1（純測試）、Task 3 Step 1(a)（翻轉）與 Step 5(c) |
| Q3 4 個欄位→單一 nullable | Task 3 Step 3～5 |
| Q4 新建 Epic 集中 | Task 0 |
| Q5 命名與 `CONTEXT.md` 詞條 | Task 1（檔名／類別）、Task 0 Step 5（詞條隨 commit） |
| Q6 `ReaderSettingsSheet` 改吃 `AvailableFonts`，Foliate 不動 | Task 2；Global Constraints「不動的東西」 |
| Q7 測試搬遷 | Task 1（純測試）、Task 3 Step 1（實際盤點後修正為刪 4／翻 1／增 2） |
| Q8 失敗語意 | Task 3 Step 4（各自 catch 回空集合）、Step 1(c)、Review Focus 1 |

**與討論當時的差異（已如實記錄）**
- Q7 討論時把「舊 WebView 上已下載的字型不列出」列為可搬到純測試。實際上該過濾發生在 `DownloadableFontStore.installedFonts()`（依 `supportedFonts`），`AvailableFonts` 收到的已是過濾後的集合，因此這兩個 widget 測試必須留著（Review Focus 5），不能搬。
- 可刪除的 widget test 估計由 8～9 個下修為 3 個（另翻轉 2 個），理由見 Task 3 Step 1(b)。

**型別一致性**：`AvailableFonts`、`installedBuiltIn`、`customFonts`、`builtInFonts`、`effectiveFamily`、`AvailableFonts.empty`、`ReaderSettingsSheet.availableFonts`、`ReaderScreen._availableFonts` 在全部 Task 中拼寫一致；`FoliateReaderView` 仍接收 `installedFonts`／`customFonts` 兩個參數（值分別取自 `fonts.installedBuiltIn`／`fonts.customFonts`）。

**已知風險**
- Task 3 的 `Future.wait` 讓「兩個來源都提供」時首幀多等一個 microtask；既有 `pumpReader` helper 已含 `runAsync` 等待，但整份 `reader_screen_test.dart` 仍需完整跑過確認（Task 3 Step 7）。
- 計畫中的行號取自 2026-09-30 的 `main`，實際動手時若行號偏移，以方法名稱與程式片段為準。

## 審查修訂紀錄

依 `reviews/review-plan-issue-1.md`（2026-09-30）逐項對照程式碼驗證後處理：

| 項目 | 結論 | 處理 |
|---|---|---|
| C-1 遺漏 `reader_settings_sheet_test.dart:1249` 直接建構點 | **成立**（已對照原始碼確認，該測試直接傳 `customFonts:`） | Task 2 補 Files 與 Step 1 (b2)，並盤點確認只有三處直接建構點 |
| I-1 `AvailableFonts` 加 `==`／`hashCode`／`toString` | **不採納** | 目前沒有任何呼叫端比較 `AvailableFonts`：`ReaderSettingsSheet` 沒有 `didUpdateWidget` 比對，測試也只斷言 `installedBuiltIn`（Task 2 Step 1）；為不存在的需求加程式碼違反 YAGNI。之後若真的出現比較需求再加（`CustomFont` 已有 `==`，屆時可直接用 `listEquals`） |
| I-2 `effectiveFamily` 不必經由 `builtInFonts` 產生 List | **部分採納** | 改為直接 `installedBuiltIn.any(...)`（`installedBuiltIn` ⊆ `AppFont.values`，結果等價，程式碼也更直接）；**不**加 `preferred.isEmpty` 判斷——沒有任何字型的 `familyName` 是空字串，Task 1 的 `''` 測試已涵蓋 |
| I-3 「沒有 store」測試應翻轉而非刪除 | **成立** | Task 3 Step 1 新增 (a2) 翻轉；刪除由 4 個降為 3 個，各處計數連動修正 |
| I-4 Step 6 grep 會命中 `reader_screen.dart:462` 註解 | **成立**（已確認該行為 `_layoutPresets` 註解的一部分） | Task 3 Step 3(b) 加入修改該註解的指示 |
| M-1 改用 record `.wait` | **成立**（`pubspec.yaml` SDK 為 `^3.11.5`） | Task 3 Step 4(b) 改寫 |
| M-2 補等價性測試 | **不採納** | 隨 I-1 不採納而不成立 |
