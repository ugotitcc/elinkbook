# Epic 18 Issue 46 — EPUB 頁次（目前第 N 頁）精準度優化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提升 `EpubPageEstimator.estimateCharsPerScreen()` 的估算精準度——改用「CJK 全形字元近似正方形字格」的幾何模型，並修正兩個既有精準度缺口：(a) 完全未納入真實螢幕尺寸；(b) 讀取的 `pageMargins` 欄位對目前唯一的 foliate-js 流式渲染路徑是死欄位。

**Architecture:** 依 `issues.md` Issue 46 已定案的方向 1（精修估算，非改查 foliate-js 真實分欄狀態）：維持現行「全書進度比例 × 估計總頁數」模型不變，只重新設計 `estimateCharsPerScreen()` 內部公式——从「以 500 字為基準、用面積比例因子縮放」的不透明啟發式，改為「可視寬高（px）÷ 字格尺寸（px）」的幾何計算，直接吃真實螢幕尺寸與 `main.js` 實際使用的四邊邊距/行高欄位。`estimateTotalPages`／`estimateCurrentPage`／`estimateProgression` 三個函式簽章與行為不變。

**Tech Stack:** Dart（純函式模組，無 Flutter widget 依賴）、`flutter_test`（unit + widget test）。

## Global Constraints

- **範圍已由人類定案**：`issues.md` Issue 46 明確記錄兩個技術方向，本計畫採方向 1（精修估算係數），不做方向 2（向 foliate-js 查詢真實分欄數，需新 JS↔Dart 橋接）——不在本計畫範圍內，不得順便夾帶。
- **`pageMargins` 是死欄位，不得繼續讀取**：`book_reader_prefs.dart:25` 欄位註解明載「僅供 EpubReaderView／FXL 使用」，`EpubReaderView` 已於 `epic-20-fxl-foliate-migration` 完全移除（見 `CLAUDE.md`），目前唯一的 EPUB 渲染路徑（foliate-js）從未讀取這個欄位。改用 `marginTop`/`marginBottom`/`marginLeft`/`marginRight`（`ResolvedPreferences` 既有欄位，`main.js:269-272` 的 `applyPreferences()` 實際使用的就是這 4 個欄位，預設值 32/16/24/24px）。
- **`lineHeight` 是原始 CSS 倍率、非「相對 1.5 正規化」的比例**：`main.js` 的 `line-height: ${prefs.lineHeight}` 直接使用該值；`ReaderSettingsSheet._defaultLineHeight = 1.0`（`reader_settings_sheet.dart:45`）是目前的真實產品預設值——舊版估算式內部 `?? 1.5` 的預設假設已經過期（未隨 epic-18 Issue 25/26 的產品預設值變動同步更新），本次一併修正為 `?? 1.0`。
- **`screenWidth`／`screenHeight` 為必要參數，不提供預設值**：兩個既有呼叫端（`reader_screen.dart`／`toc_bottom_sheet.dart`）都在 `State` 方法內、都能存取 `MediaQuery.of(context).size`，沒有「呼叫端真的不知道螢幕尺寸」的合法情境；用必要參數強制呼叫端傳入真實值，避免未來新增呼叫端時因為偷懶傳入假設值而重蹈舊版「完全忽略螢幕尺寸」的覆轍。
- **`paragraphSpacing` 維持既有低權重整體壓縮處理，不做幾何化**：段落間距對可視面積的實際影響取決於書本本身的段落密度（未知、不可預先假設），沒有足夠資訊做真正的幾何換算；沿用舊版「套用低權重壓縮因子」的簡化精神，只是套用對象改成新的幾何計算結果。
- **`flutter analyze` 全程維持乾淨；每個 Task 結束後相關測試全數通過**是每個 Task 的隱含驗收條件。全專案 `flutter test` 基準為 **1152/1152 通過**（見 `epic-24-pdf-engine-rebuild` Issue 8 合併後狀態，本 Epic 與該 Epic 共用同一個 `app/` 專案、同一份測試母數）。

---

### Task 1: `EpubPageEstimator.estimateCharsPerScreen()` 改用幾何模型

**Files:**
- Modify: `app/lib/reader/epub_page_estimator.dart:1-56`
- Test: `app/test/reader/epub_page_estimator_test.dart:1-50`（僅 `estimateCharsPerScreen` group；`estimateTotalPages`／`estimateCurrentPage`／`estimateProgression` 三個 group 維持不動，不在本 Task 範圍）

**Interfaces:**
- Consumes: 無（純 Dart 函式，無跨 Task 依賴）
- Produces: `EpubPageEstimator.estimateCharsPerScreen({required double screenWidth, required double screenHeight, double? fontSize, double? lineHeight, double? paragraphSpacing, double? marginTop, double? marginBottom, double? marginLeft, double? marginRight})` → `int`——**簽章變動**：新增 4 個必要/選用參數、移除 `pageMargins` 參數（Task 2 的兩個呼叫端皆依賴此新簽章）。`EpubPageEstimator.baseFontSizePx`（`double`，值 16.0）為新增的公開常數，取代移除的 `referenceCharsPerScreen`。

- [ ] **Step 1: 寫下失敗的測試（改寫 `estimateCharsPerScreen` group）**

以下述內容完整取代 `app/test/reader/epub_page_estimator_test.dart` 第 4-50 行（`estimateCharsPerScreen` 這個 `group`），檔案其餘部分（`estimateTotalPages`／`estimateCurrentPage`／`estimateProgression` 三個 group）維持逐字不動：

```dart
  group('estimateCharsPerScreen', () {
    test(
        '參考情境（screenWidth=800/screenHeight=600，其餘皆用預設版面參數）'
        '換算出的每螢幕字元數（Issue 46：改用幾何模型，不再是舊版的 500 '
        '基準常數）', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
        ),
        1598,
      );
    });

    test('fontSize 加倍時，每行字數與每螢幕行數同時減少，可容納字元數大幅縮減', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          fontSize: 2.0,
        ),
        391,
      );
    });

    test('lineHeight 加倍以上時，每螢幕行數依線性比例縮減，每行字數不受影響', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          lineHeight: 3.0,
        ),
        517,
      );
    });

    test('lineHeight 為 0.0 時（epic-18-reader-device-qa Issue 25 行高滑桿範圍改為 '
        '0~3 後可選到的邊界值），不應除以零拋出 UnsupportedError，改回傳箝制後的合理值',
        () {
      expect(
        () => EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          lineHeight: 0.0,
        ),
        returnsNormally,
      );
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          lineHeight: 0.0,
        ),
        16215,
      );
    });

    test(
        'marginLeft／marginRight 加倍時，可用寬度縮減、每行字數隨之減少'
        '（Issue 46：改讀真實 marginLeft/marginRight，取代已對 foliate-js 路徑'
        '失效的 pageMargins 欄位）', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          marginLeft: 48,
          marginRight: 48,
        ),
        1496,
      );
    });

    test('marginTop／marginBottom 加倍時，可用高度縮減、每螢幕行數隨之減少'
        '（Issue 46 新增：舊版 pageMargins 是單一倍率、不區分上下左右，'
        '無法表達「只有上下邊距變動」這個情境）', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          marginTop: 64,
          marginBottom: 32,
        ),
        1457,
      );
    });

    test(
        '相同版面參數下，螢幕尺寸加倍時可容納字元數應大幅增加（Issue 46 核心'
        '回歸測試：證明舊版公式「完全忽略螢幕尺寸」的精準度缺口已修復——'
        '手機與平板讀同一本書，在相同版面設定下不應估出相同頁數）', () {
      final reference = EpubPageEstimator.estimateCharsPerScreen(
        screenWidth: 800,
        screenHeight: 600,
      );
      final doubledScreen = EpubPageEstimator.estimateCharsPerScreen(
        screenWidth: 1600,
        screenHeight: 1200,
      );
      expect(doubledScreen, greaterThan(reference * 3));
      expect(doubledScreen, 6984);
    });

    test('極端字體大小（超出可視寬度）時，結果被箝制在下限 50，不會估算出荒謬的總頁數', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          fontSize: 50.0,
        ),
        50,
      );
    });
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/epub_page_estimator_test.dart`
Expected: 上述 8 則新測試 FAIL（`estimateCharsPerScreen` 目前簽章沒有 `screenWidth`/`screenHeight`/`marginTop`/`marginBottom`/`marginLeft`/`marginRight` 具名參數，會是編譯期錯誤：`The named parameter 'screenWidth' isn't defined`）；`estimateTotalPages`／`estimateCurrentPage`／`estimateProgression` 三組共 11 則測試維持通過（本 Step 尚未觸碰對應程式碼）。

- [ ] **Step 3: 實作新版 `estimateCharsPerScreen()`**

用以下內容完整取代 `app/lib/reader/epub_page_estimator.dart` 第 1-56 行：

```dart
import 'dart:math' as math;

/// EPUB 模擬分頁估算邏輯（epic-5-toc-pagination Issue 3，spec.md「分頁估算
/// 模組」；精準度優化見 epic-18-reader-device-qa Issue 46）：純 Dart、無
/// I/O，供 `ReaderScreen`／`TocBottomSheet` 依目前生效的版面參數＋全書
/// 字元數快取換算「估計總頁數」／「目前頁碼」，以及頁尾跳頁互動的反向換算
/// （目標頁碼→全書進度比例）。
///
/// 明確聲明：本模組產生的頁碼為模擬估算值，不保證與 foliate-js 實際渲染
/// 逐頁精確對齊（見 spec.md「分頁估算模組」）——`estimateCharsPerScreen()`
/// 用「CJK 全形字元近似正方形字格」的幾何模型換算（字格邊長＝字級 px），
/// 並非逐字量測真實 DOM 版面。
class EpubPageEstimator {
  const EpubPageEstimator._();

  /// 對應「fontSize 倍率 1.0」的基準字級（16px，見 `ReaderSettingsSheet`
  /// 既有慣例：`_toMultiplier(_fontSize, 16.0)`）。
  static const double baseFontSizePx = 16.0;

  /// 依目前生效的版面參數＋實際可視區域尺寸估算「每螢幕可容納字元數」
  /// （Issue 46 精準度優化：改用 CJK 全形字元近似正方形字格的幾何模型，
  /// 並納入真實螢幕尺寸與四邊邊距——舊版公式完全不吃螢幕尺寸這個輸入，
  /// 同一本書在手機與平板上會估出完全相同的頁碼，是既有精準度落差的
  /// 主因之一）。
  ///
  /// [screenWidth]／[screenHeight] 為可視區域邏輯像素尺寸（呼叫端傳入
  /// `MediaQuery.of(context).size`，見 `ReaderScreen._buildEpubFooter()`／
  /// `TocBottomSheet._buildEntryRow()` 呼叫慣例），為必要參數——本函式的
  /// 估算意義完全建立在真實可視尺寸之上，不提供「未知尺寸」的預設語意。
  ///
  /// [marginTop]／[marginBottom]／[marginLeft]／[marginRight] 為原始像素值
  /// （非倍率，與 `main.js` 的 `applyPreferences()` 直接使用的單位一致，
  /// 預設值 32/16/24/24 與 `ReaderSettingsSheet._defaultMarginTop` 等常數
  /// 一致）——取代舊版讀取的 `pageMargins`（單一倍率、四邊同步變動，見
  /// `book_reader_prefs.dart` 欄位註解「僅供 EpubReaderView／FXL 使用」，
  /// `EpubReaderView` 已於 `epic-20-fxl-foliate-migration` 完全移除，
  /// `pageMargins` 對目前唯一的 foliate-js 流式渲染路徑是死欄位、從未真正
  /// 影響過實際版面）。
  ///
  /// [lineHeight] 直接作為 CSS `line-height` 倍率使用（與 `main.js` 的
  /// `line-height: ${prefs.lineHeight}` 用法一致，非舊版的「相對 1.5 正規化
  /// 倍率」），預設值 1.0 與 `ReaderSettingsSheet._defaultLineHeight` 一致
  /// （舊版預設 1.5 是尚未隨 epic-18 Issue 25/26 產品預設值變動同步更新的
  /// 過期假設）。
  static int estimateCharsPerScreen({
    required double screenWidth,
    required double screenHeight,
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? marginTop,
    double? marginBottom,
    double? marginLeft,
    double? marginRight,
  }) {
    final fontSizeFactor = fontSize ?? 1.0;
    final fontSizePx = fontSizeFactor * baseFontSizePx;
    // epic-18-reader-device-qa Issue 25 把行高滑桿範圍下限改為 0 後，
    // lineHeight 可能真的是 0.0——若不設下限，lineHeightPx 會是 0、
    // linesPerScreen 除以零得到 double.infinity，對 Infinity 呼叫 .floor()
    // 在 Dart 會直接拋出 UnsupportedError（審查發現，2026-08-05）。0.1
    // 只是避免除以零的下限，不代表這是「合理」的行高。
    final lineHeightFactor = math.max(0.1, lineHeight ?? 1.0);
    final paragraphSpacingFactor = paragraphSpacing ?? 1.0;

    final topPx = marginTop ?? 32.0;
    final bottomPx = marginBottom ?? 16.0;
    final leftPx = marginLeft ?? 24.0;
    final rightPx = marginRight ?? 24.0;

    // 可視內容區域至少保留一個字格的寬高，避免邊距設定超過螢幕尺寸時
    // availableWidth/Height 變成負值。
    final availableWidth =
        math.max(fontSizePx, screenWidth - leftPx - rightPx);
    final availableHeight =
        math.max(fontSizePx, screenHeight - topPx - bottomPx);

    final lineHeightPx = fontSizePx * lineHeightFactor;
    final charsPerLine = (availableWidth / fontSizePx).floor();
    final linesPerScreen = (availableHeight / lineHeightPx).floor();
    final baseChars = charsPerLine * linesPerScreen;

    // 段落間距對可視面積的實際影響取決於書本本身的段落密度（未知），沿用
    // 既有「低權重整體壓縮」精神，只是套用對象改成幾何算出的 baseChars，
    // 而非舊版的整體 areaFactor（見 Global Constraints）。
    final adjusted =
        (baseChars / (1 + (paragraphSpacingFactor - 1) * 0.1)).round();

    // 防呆下限/上限，避免極端版面設定（例如字體縮到最小、或邊距設定
    // 荒謬）估算出不合理的總頁數。上限自舊版的 2000（`referenceCharsPerScreen
    // * 4`）大幅提高至 20000——舊上限是針對「忽略螢幕尺寸」的舊公式校準，
    // 納入真實螢幕尺寸後，大尺寸平板/桌面在小字級下的合理值本就會遠超過
    // 2000（見本檔案對應測試「screenWidth/Height 加倍」案例）。
    return adjusted.clamp(50, 20000);
  }
```

檔案第 57 行起（`estimateTotalPages`／`estimateCurrentPage`／`estimateProgression` 三個函式）維持逐字不動，不需要複製到這裡——本 Step 只取代到 `estimateCharsPerScreen()` 函式結尾（原檔案第 56 行的 `}`）。

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/epub_page_estimator_test.dart`
Expected: 全數通過（`estimateCharsPerScreen` 8 則新測試＋其餘三組 11 則既有測試，共 19 則）。

- [ ] **Step 5: Commit**

```bash
cd app
git add lib/reader/epub_page_estimator.dart test/reader/epub_page_estimator_test.dart
git commit -m "fix(epic-18): Issue 46 EpubPageEstimator 改用幾何模型精修頁次估算"
```

---

### Task 2: 兩個呼叫端接上真實螢幕尺寸與四邊邊距

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:2044-2074`（`_buildEpubFooter()`）
- Modify: `app/lib/screens/toc_bottom_sheet.dart:210-244`（`_buildEntryRow()`）
- Test: `app/test/screens/reader_screen_test.dart:1218-1290`（既有 test，需更新 2 處寫死的頁碼斷言）
- Test: `app/test/screens/toc_bottom_sheet_test.dart:171-190`（既有 test，僅更新過期註解，斷言本身不受影響）

**Interfaces:**
- Consumes: `EpubPageEstimator.estimateCharsPerScreen({required double screenWidth, required double screenHeight, ...})`（Task 1 產出的新簽章）
- Produces: 無新介面（兩處皆為既有呼叫端的內部實作調整，不影響任何外部可見的 widget 建構參數或方法簽章）

- [ ] **Step 1: 更新 `reader_screen.dart` 的 `_buildEpubFooter()`**

用以下內容取代 `app/lib/screens/reader_screen.dart` 第 2049-2054 行（`EpubPageEstimator.estimateCharsPerScreen(...)` 呼叫本身）：

```dart
    final screenSize = MediaQuery.of(context).size;
    final charsPerScreen = EpubPageEstimator.estimateCharsPerScreen(
      screenWidth: screenSize.width,
      screenHeight: screenSize.height,
      fontSize: resolved.fontSize,
      lineHeight: resolved.lineHeight,
      paragraphSpacing: resolved.paragraphSpacing,
      marginTop: resolved.marginTop,
      marginBottom: resolved.marginBottom,
      marginLeft: resolved.marginLeft,
      marginRight: resolved.marginRight,
    );
```

- [ ] **Step 2: 更新 `toc_bottom_sheet.dart` 的 `_buildEntryRow()`**

用以下內容取代 `app/lib/screens/toc_bottom_sheet.dart` 第 223-236 行（`pageLabel = (totalCharacterCount == null || node.progression == null) ? '…' : ...` 這個三元運算式的完整內容）：

```dart
      pageLabel = (totalCharacterCount == null || node.progression == null)
          ? '…'
          : EpubPageEstimator.estimateCurrentPage(
              progression: node.progression,
              totalPages: EpubPageEstimator.estimateTotalPages(
                totalCharacterCount: totalCharacterCount,
                charsPerScreen: EpubPageEstimator.estimateCharsPerScreen(
                  screenWidth: MediaQuery.of(context).size.width,
                  screenHeight: MediaQuery.of(context).size.height,
                  fontSize: widget.resolved.fontSize,
                  lineHeight: widget.resolved.lineHeight,
                  paragraphSpacing: widget.resolved.paragraphSpacing,
                  marginTop: widget.resolved.marginTop,
                  marginBottom: widget.resolved.marginBottom,
                  marginLeft: widget.resolved.marginLeft,
                  marginRight: widget.resolved.marginRight,
                ),
              ),
            ).toString();
```

- [ ] **Step 3: 執行 `flutter analyze` 確認新程式碼無型別/語法錯誤**

Run: `cd app && flutter analyze`
Expected: 此時尚未更新測試檔的寫死斷言，`flutter analyze` 本身不檢查測試斷言的數值是否正確，應維持乾淨（No issues found!）。

- [ ] **Step 4: 更新 `reader_screen_test.dart` 兩處寫死的頁碼斷言**

用以下內容取代 `app/test/screens/reader_screen_test.dart` 第 1252-1253 行：

```dart
    // Issue 46：screenWidth=800/screenHeight=600（flutter_test 預設視窗
    // 尺寸）、其餘版面參數皆為預設值時，estimateCharsPerScreen() = 1598
    // （見 epub_page_estimator_test.dart 對應測試），totalPages =
    // ceil(5000/1598) = 4，progression 尚未收到任何回報（null）→ 第 1 頁。
    expect(find.text('1/4'), findsOneWidget);
```

用以下內容取代 `app/test/screens/reader_screen_test.dart` 第 1284-1289 行：

```dart
    // fontSize 倍率變成 2.0，且 16 次點擊過程中 ReaderSettingsSheet 的
    // _notifyChanged() 一併把行高／邊界的目前 UI 狀態（即使使用者未曾觸碰）
    // 送入 BookReaderPrefs——這些值恰好等於 estimateCharsPerScreen() 自身
    // 的預設 fallback（lineHeight 1.0／margin 32-16-24-24），數值不受影響。
    // fontSize=2.0、screenWidth=800/screenHeight=600 下
    // estimateCharsPerScreen() = 391（見 epub_page_estimator_test.dart
    // 對應測試），totalPages = ceil(5000/391) = 13。
    expect(find.text('1/13'), findsOneWidget);
```

- [ ] **Step 5: 更新 `toc_bottom_sheet_test.dart` 的過期註解**

用以下內容取代 `app/test/screens/toc_bottom_sheet_test.dart` 第 181-183 行（斷言本身 `'1'` 不需變動——`progression: 0.0` 恆回傳第 1 頁，與 `charsPerScreen`/`totalPages` 實際數值無關，僅註解描述的計算過程已過期）：

```dart
    // Issue 46：screenWidth=800/screenHeight=600（flutter_test 預設視窗
    // 尺寸）、_testResolved 未覆寫任何版面欄位時，
    // estimateCharsPerScreen() = 1598，totalPages = 5000/1598 = 4；
    // ch1.progression = 0.0 → estimateCurrentPage(0.0, 4) = 1（恆為第 1
    // 頁，與 totalPages 實際數值無關）。
```

- [ ] **Step 6: 執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart test/screens/toc_bottom_sheet_test.dart`
Expected: 全數通過，無回歸。

- [ ] **Step 7: Commit**

```bash
cd app
git add lib/screens/reader_screen.dart lib/screens/toc_bottom_sheet.dart test/screens/reader_screen_test.dart test/screens/toc_bottom_sheet_test.dart
git commit -m "fix(epic-18): Issue 46 兩處呼叫端接上真實螢幕尺寸與四邊邊距"
```

---

### Task 3: 端對端驗證與計畫收尾

**Files:**
- Modify: `docs/epics/epic-18-reader-device-qa/issues.md`（Issue 46 段落，Status 與內文）
- Modify: `docs/epics/epic-18-reader-device-qa/plans/plan-issue-46.md`（本檔案，Task 1-2 打勾狀態）

**Interfaces:**
- Consumes: Task 1、Task 2 的完整實作
- Produces: 無（收尾工單，不產出新介面）

- [ ] **Step 1: `flutter analyze` 確認全程乾淨**

Run: `cd app && flutter analyze`
Expected: No issues found!

- [ ] **Step 2: 執行全專案 `flutter test` 確認零回歸**

Run: `cd app && flutter test`
Expected: 全數通過。Global Constraints 記錄的基準為 1152（Task 1 新增 8 則、移除 6 則舊測試淨增 2 則；Task 2 未新增測試，只更新既有斷言），預期合計 1154；若與此數字不符，以實測結果為準並在下一步的 `issues.md` 更新中如實記錄實際數字，不得回頭竄改本行的「預期」敘述。

- [ ] **Step 3: 對照 `issues.md` Issue 46 內容自我檢查**

逐項確認：
- `EpubPageEstimator.estimateCharsPerScreen()` 已改用幾何模型，納入真實 `screenWidth`/`screenHeight`（Task 1）。
- 已改讀 `marginTop`/`marginBottom`/`marginLeft`/`marginRight`，`pageMargins` 死欄位不再被 `EpubPageEstimator` 讀取（Task 1）。
- `reader_screen.dart`／`toc_bottom_sheet.dart` 兩個呼叫端皆已傳入真實 `MediaQuery.of(context).size`（Task 2）。
- 未觸碰 `estimateTotalPages`／`estimateCurrentPage`／`estimateProgression` 三個函式的簽章與行為（Global Constraints，範圍界線）。
- 未實作方向 2（向 foliate-js 查詢真實分欄狀態）（Global Constraints，範圍界線）。

- [ ] **Step 4: 更新 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 46 段落**

`Status` 由 `needs-triage` 改為 `✅ 已完成`，並在原有「待決策方向」段落後方追加一段實作結果摘要（採用的方向、關鍵修正點、`flutter test` 通過數量），比照本檔案 Issue 37/42-44 等既有已完成 Issue 的敘述慣例。

- [ ] **Step 5: 更新本計畫檔案 Task 1、Task 2 的打勾狀態**

將 Task 1、Task 2 已完成的 Step 前面的 `- [ ]` 改為 `- [x]`，本 Task 3 各 Step 完成後同步勾選。

- [ ] **Step 6: 提交文件更新**

```bash
git add docs/epics/epic-18-reader-device-qa/issues.md docs/epics/epic-18-reader-device-qa/plans/plan-issue-46.md
git commit -m "docs(epic-18): Issue 46 標記完成，更新頁次估算精準度優化結果"
```
