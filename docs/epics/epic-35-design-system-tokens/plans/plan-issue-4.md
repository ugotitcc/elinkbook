# Epic 35 — Issue 4：`highlight_style.dart` 遷移＋呼叫端更新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `HighlightStyle` 列舉的編譯期色票（`fixedTint`）改為執行期透過 `ElinkTokens` 解析的 `highlightStyleColor()` 函式，並同步更新四處呼叫端（`reader_screen.dart` 兩處、`notes_bottom_sheet.dart` 一處、`annotation_toolbar.dart` 一處）與 `notes_bottom_sheet.dart` 僅剩的 `Colors.red` 寫死顏色殘留（2 處）。

**Architecture:** `HighlightStyle` 列舉拿掉 `fixedTint` 欄位與三個頂層色票常數，改為新增純函式 `Color highlightStyleColor(HighlightStyle style, {required ElinkTokens tokens})`，回傳型別從舊函式 `highlightStyleTint()` 的 `int`（ARGB32）改為 `Color`——需要 `int` 的原生 Decoration API 呼叫端自行加一次 `.toARGB32()`。這是一個跨四個檔案的破壞性重新命名（`highlightStyleTint`／三個頂層色票常數整個消失），Dart 是單一編譯單元語言，`reader_screen.dart` 又透過 `import 'annotation_toolbar.dart';`／`import 'notes_bottom_sheet.dart';` 間接依賴它們——四個檔案的呼叫端**必須在同一個 Task 內原子性地一起改完**，否則任何中繼狀態下 `flutter analyze`／`flutter test`（含只測單一檔案）都會因為編譯錯誤而整批失敗，不是真正「這個 Task 沒做完」的訊號。

這次重構同時讓 `reader_screen_test.dart`（181 處建構 `ReaderScreen` 的地方）與 `annotation_toolbar_test.dart`（12 處建構 `AnnotationToolbar`）裡，凡是沒有帶入含 `ElinkTokens` 主題的 `MaterialApp`，都會在改用 `Theme.of(context).extension<ElinkTokens>()!` 後於執行期對 `null` 做 `!` 而崩潰——這個風險面遠比「插入過劃線的測試」這個子集合大（任何會顯示 `AnnotationToolbar` 的測試都會踩到，不只是插入過劃線的測試）。經與人類確認，**本計劃不採用人工逐一篩選「哪些測試會踩到」的精簡策略**（已證實這種篩選方式會漏，見下方「範圍決定」段落），改為用一支經過驗證的小型 Python 腳本，對兩個測試檔案裡「每一處」建構 `ReaderScreen`／`AnnotationToolbar` 的 `MaterialApp` 都補上 `theme:`，用機械式的完整覆蓋取代容易出錯的人工稽核。因此本計劃只有 2 個 Task：Task 1 是這個不可分割的核心遷移（含全面補齊兩個測試檔的主題缺口）；Task 2 是完全獨立、非破壞性的 `Colors.red` 遷移。

**Tech Stack:** Flutter／Dart，`flutter_test`（unit test 測 `highlightStyleColor()` 純函式、既有 widget test 套件驗證呼叫端無回歸），Python 3（僅用於 Task 1 Step 8 的一次性機械式文字轉換，不是專案執行期依賴，跑完即可刪除），不新增任何 pub 套件依賴。

**Spec:** `docs/epics/epic-35-design-system-tokens/spec.md`（§「既有語意色遷移到 `ElinkTokens`」、§「寫死顏色遷移」`notes_bottom_sheet.dart` 部分、§「Testing Decisions」）；工單摘要見 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 4。

**範圍決定（本計劃撰寫時與人類確認過，共兩輪）：**

1. `reader_screen.dart` 盤點後發現剩餘的 3 處寫死顏色（`_themedTtsDisabledIconColor` 的 `Colors.grey`、`_themedTextColor ?? Colors.black` 的黑色候補值 2 處）都只在固定版面（CBZ／FXL）情境下才會被用到，且畫在跟已明文排除的 `_themedFabBackgroundColor`（`Colors.black54`）同一顆固定黑底按鈕上——若改成跟隨主題的顏色，深色主題下可能與固定黑底對比不足，重踩 `epic-22`／`epic-34` 已修過的電子紙可辨識度問題。經與人類確認，**這 3 處一併歸入 `issues.md` 已明文排除的「固定版面例外」範圍，不在本 Issue 遷移**，維持寫死不動。此決定經 `/superpowers:requesting-code-review` 複審（`reviews/review-plan-issue-4.md`）確認技術推理站得住腳，成立。
2. 同一次複審也抓到兩個 Critical：(a) `spec.md`／`issues.md` 列舉的呼叫端清單本身就漏掉 `annotation_toolbar.dart`——它直接引用即將被刪除的三個頂層色票常數，不補上 Task 1 一執行就會編譯失敗；(b) 原本計劃書用「人工逐一核對 `reader_screen_test.dart` 裡插入過劃線的測試，篩出只有 5 處要補 `theme:`」的稽核方法論本身有系統性漏洞——它只涵蓋「`pumpWidget` 前已 `.insert()` 好的劃線」，漏掉「測試執行中途透過 UI 互動動態建立的劃線」與「只是顯示 `AnnotationToolbar`（不需要真的有劃線）」兩類情形，複審實際抽查就找到至少 3 個反例。經與人類確認，**兩項都全數採納修正**：`annotation_toolbar.dart` 併入 Task 1 一起遷移；`reader_screen_test.dart`（181 處）與新增的 `annotation_toolbar_test.dart`（12 處）改採機械式全面覆蓋，不再嘗試人工精確篩選。

## Global Constraints

- `HighlightStyle` 列舉成員名稱（`highlighterYellow`／`highlighterPink`／`highlighterBlue`／`underline`）**維持不變**，即使 `highlighterPink` 視覺上對應綠色——改名會讓 `Enum.values.byName()` 持久化的既有使用者資料反序列化失敗。
- `highlightStyleTint()` 整個移除（不是改名保留舊函式），改為 `Color highlightStyleColor(HighlightStyle style, {required ElinkTokens tokens})`——拿掉 `primaryColor` 參數，回傳型別是 `Color`（非 `int`）。
- 對應關係：`highlighterYellow` → `tokens.highlightYellow`／`highlighterPink` → `tokens.highlightGreen`（語意變更，`DESIGN.md` §1.2 既有決策，非本 Issue 新增）／`highlighterBlue` → `tokens.highlightBlue`／`underline` → `tokens.underlineColor`。
- `HighlightStyle.fixedTint` 欄位與 `highlighterYellowTint`／`highlighterPinkTint`／`highlighterBlueTint` 三個頂層常數一併移除。`noteOnlyTint` **不動**（不在本 Issue 範圍，`ElinkTokens` 未定義對應欄位）。
- **四處**呼叫端（`reader_screen.dart` 兩處、`notes_bottom_sheet.dart` 一處、`annotation_toolbar.dart` 一處）改為傳 `tokens`（從 `Theme.of(context).extension<ElinkTokens>()!` 取得，`!` 是安全的——正式 App 的 `main.dart` 一律用 `resolveThemeData()` 建構 `MaterialApp.theme`，`ElinkTokens` 保證存在；只有測試環境若沒帶對應主題才會炸，見下一條）。
- `reader_screen.dart`／`notes_bottom_sheet.dart` 需要原生 `int` ARGB32 值的呼叫點，改為 `highlightStyleColor(...).toARGB32()`（色彩決策收斂在 Dart 端，`int` 轉換交給呼叫端）；`annotation_toolbar.dart` 直接用 `Color`，不需要 `.toARGB32()`。
- **既有測試環境缺口（本計劃盤點時新發現，`spec.md`/`issues.md` 皆未記載，不修就會讓既有測試在本 Issue 之後大量崩潰）**：`app/test/screens/reader_screen_test.dart` 有 181 處、`app/test/screens/annotation_toolbar_test.dart` 有 12 處建構 `ReaderScreen`／`AnnotationToolbar` 的 `MaterialApp`，目前都用不帶 `theme:` 參數（或用不含 `ElinkTokens` 的舊寫法）的裸 `MaterialApp(home: ...)`——這種情況下 `Theme.of(context)` 解析到沒有掛 `ElinkTokens` 的主題。改用 `Theme.of(context).extension<ElinkTokens>()!` 後，沒補的地方會在執行期對 `null` 做 `!` 而直接拋例外崩潰。本 Task 1 用 Step 8 的腳本一次性全面補齊，**不依賴人工逐一判斷「這處會不會踩到」**（已證實這種判斷方式會漏，見上方「範圍決定」）。`app/test/screens/reader_screen_test.dart` 裡另有 13 處已經用 `theme: buildThemeData(AppTheme.light/dark)` 帶入含 `ElinkTokens` 的主題（`buildThemeData()` 內部同樣掛了 `extensions: [ElinkTokens(...)]`），這 13 處本來就安全，Step 8 的腳本比對樣式時會自動略過，不會重複插入。
- `notes_bottom_sheet.dart` 的 `Colors.red`（L349／L531，兩個「刪除」按鈕的 `TextButton.styleFrom(foregroundColor: ...)`）改為 `Theme.of(context).colorScheme.error`。
- `reader_screen.dart` 剩餘的 3 處寫死顏色（`_themedTtsDisabledIconColor` 的 `Colors.grey`、`_themedTextColor ?? Colors.black` 候補值 2 處）**維持不動**（見上方「範圍決定」第 1 點）。
- 本工單只碰 `app/lib/reader/highlight_style.dart`、`app/lib/screens/reader_screen.dart`、`app/lib/screens/notes_bottom_sheet.dart`、`app/lib/screens/annotation_toolbar.dart` 四個原始碼檔案，與 `app/test/reader/highlight_style_test.dart`、`app/test/screens/reader_screen_test.dart`、`app/test/screens/notes_bottom_sheet_test.dart`、`app/test/screens/annotation_toolbar_test.dart` 四個測試檔案；不碰 OPDS／WebDAV／雲端來源實作／書籍儲存／閱讀進度持久化。
- 所有 Dart 原始碼註解使用正體中文；Task 1 Step 8 用到的 Python 腳本本身是一次性工具、不進版控，註解可用英文（不對外呈現）。
- Task 1 逐檔跑對應測試（`flutter test test/reader/highlight_style_test.dart`、`flutter test test/screens/reader_screen_test.dart`、`flutter test test/screens/notes_bottom_sheet_test.dart`、`flutter test test/screens/annotation_toolbar_test.dart`）；Task 2 只跑 `flutter test test/screens/notes_bottom_sheet_test.dart`。整份計劃最後一個 Task 完成時才跑一次完整 `flutter test`（見 `CLAUDE.md`「測試執行範圍」）。
- 每個 Task 的 Step 完成後，把本檔案對應的 `- [ ]` 改成 `- [x]`（`sdd-workflow` 規則，方便追蹤進度）。
- 提交前 `flutter analyze` 須維持「No issues found!」。

## 動手改程式碼前的四點說明（`UI_DESIGN_RULES.md` 要求）

1. **改哪個 UI 元件**：不是單一 UI 元件，是一個橫跨四個檔案的資料模型＋呼叫端重構——`app/lib/reader/highlight_style.dart`（劃線樣式的純資料模型，非 widget）、`app/lib/screens/reader_screen.dart`（`_sendDecorationsToNative()`／`_sendPdfAnnotationsToNative()` 兩個私有方法，把劃線色值送給原生端疊圖渲染）、`app/lib/screens/notes_bottom_sheet.dart`（`_buildAnnotationRow()` 劃線清單項目的圓點顏色、`_confirmDeleteAllBookmarks()`／`_confirmDeleteAll()` 兩個刪除確認對話框的按鈕顏色）、`app/lib/screens/annotation_toolbar.dart`（選字/框選後浮現的工具列，三顆螢光筆色塊）。
2. **為什麼要改**：`HighlightStyle` 列舉目前用編譯期常數色票（`fixedTint`），但 `ElinkTokens`（Issue 1/2 已建好、掛上 `resolveThemeData()`）的色值只有執行期透過 `Theme.of(context)` 才能取得，兩者架構衝突，不是把常數名稱換掉這麼簡單，需要重構函式簽章；`Colors.red` 是 `notes_bottom_sheet.dart` 僅剩的寫死顏色殘留。
3. **哪些畫面依賴它**：閱讀器主畫面（`ReaderScreen`，EPUB／FXL／PDF 皆會呼叫）在有劃線資料時，會呼叫 `_sendDecorationsToNative()`／`_sendPdfAnnotationsToNative()` 把劃線顏色送給原生端疊圖渲染，選字/框選後也會顯示 `AnnotationToolbar`；「筆記」Bottom Sheet（`NotesBottomSheet`）的「劃線與備註」分頁會顯示每筆劃線的顏色圓點與樣式標籤。
4. **是否影響 business logic**：不影響。純視覺色票來源重構，`Highlight`／`HighlightStyle` 的持久化格式、CRUD 邏輯、劃線與備註的資料流完全不變。

---

### Task 1: `HighlightStyle` 遷移本體＋四處呼叫端同步更新＋既有測試環境全面補齊

**Files:**
- Modify: `app/lib/reader/highlight_style.dart`（全檔重寫，移除 `fixedTint`／三個頂層常數／`highlightStyleTint()`，新增 `highlightStyleColor()`）
- Modify: `app/lib/screens/reader_screen.dart`（頂部 import；`_sendDecorationsToNative()` 原第 1724-1745 行；`_sendPdfAnnotationsToNative()` 原第 1817-1838 行）
- Modify: `app/lib/screens/notes_bottom_sheet.dart`（頂部 import；`_buildAnnotationRow()` 原第 436-444 行）
- Modify: `app/lib/screens/annotation_toolbar.dart`（頂部 import；`build()` 原第 46-73 行）
- Test: `app/test/reader/highlight_style_test.dart`（全檔重寫）
- Test: `app/test/screens/reader_screen_test.dart`（181 處 `MaterialApp` 中的 168 處機械式補 `theme:`，另 13 處已安全略過）
- Test: `app/test/screens/annotation_toolbar_test.dart`（12 處 `MaterialApp` 機械式補 `theme:`）
- Test: `app/test/screens/notes_bottom_sheet_test.dart`（`_pumpSheet`／`_pumpModalSheet` 兩個共用 helper 補 `theme:`，原第 34-52／596-617 行附近）

**Interfaces:**
- Consumes: `ElinkTokens`（`app/lib/theme/elink_tokens.dart`，Issue 1 已建好，`highlightYellow`／`highlightGreen`／`highlightBlue`／`underlineColor` 四個欄位）；`resolveThemeData({required AppTheme theme, required bool isEinkMode}) -> ThemeData`（`app/lib/theme/app_theme_data.dart`，Issue 2 已完成）。
- Produces: `Color highlightStyleColor(HighlightStyle style, {required ElinkTokens tokens})`——本 Task 內四處呼叫端與 Task 2 皆沿用這個簽章，不再變更。

- [x] **Step 1: 寫失敗的測試——`highlightStyleColor()` 全新單元測試（取代舊測試）**

把 `app/test/reader/highlight_style_test.dart` 整個檔案內容取代為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

void main() {
  const tokens = ElinkTokens(
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
  );

  test('highlightStyleColor()：四個樣式各自對應正確的 ElinkTokens 欄位', () {
    expect(
      highlightStyleColor(HighlightStyle.highlighterYellow, tokens: tokens),
      tokens.highlightYellow,
    );
    expect(
      highlightStyleColor(HighlightStyle.highlighterPink, tokens: tokens),
      tokens.highlightGreen,
      reason: 'highlighterPink 語意變更為綠色，DESIGN.md §1.2 既有決策',
    );
    expect(
      highlightStyleColor(HighlightStyle.highlighterBlue, tokens: tokens),
      tokens.highlightBlue,
    );
    expect(
      highlightStyleColor(HighlightStyle.underline, tokens: tokens),
      tokens.underlineColor,
    );
  });

  test('HighlightStyle 列舉成員名稱維持不變（Enum.values.byName() 持久化相容性）', () {
    expect(
      HighlightStyle.values.map((e) => e.name).toList(),
      ['highlighterYellow', 'highlighterPink', 'highlighterBlue', 'underline'],
    );
  });
}
```

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/reader/highlight_style_test.dart`
Expected: FAIL（編譯錯誤：`highlightStyleColor` 未定義——`highlight_style.dart` 此時仍是舊版，只有 `highlightStyleTint()`）。

- [x] **Step 3: 實作——`highlight_style.dart` 全檔重寫**

把 `app/lib/reader/highlight_style.dart` 整個檔案內容取代為：

```dart
import 'package:flutter/material.dart';

import '../theme/elink_tokens.dart';

/// 純備註（無劃線）的固定畫面指示色（design.md 決策 #2「淡灰底」，見
/// Global Constraints「純備註視覺簡化」）。不在 epic-35-design-system-tokens
/// 遷移範圍——`ElinkTokens` 未定義對應欄位，維持既有寫死值。
const noteOnlyTint = Color(0x73D1D5DB);

/// 劃線樣式（epic-6-annotations Issue 2，spec.md「劃線與備註模組」）：
/// 螢光筆三色（背景底色填滿）與底線（波浪底線，跟隨主題色）為 4 個互斥值，
/// 非「樣式＋顏色」兩個獨立維度——避免「底線＋顏色」這種 design.md 決策
/// #5 明確排除的無效狀態組合。持久化時使用 `.name`（比照既有
/// `PdfCropMode`/`WritingMode` 等列舉的既有慣例，見 book_reader_prefs.dart
/// 的 `Enum.values.byName()` 既有寫法）。
///
/// 【epic-35-design-system-tokens Issue 4】列舉不再攜帶編譯期色票常數——
/// 色值改由 [highlightStyleColor] 於執行期透過 `ElinkTokens` 解析，因為
/// `ElinkTokens` 只有 `Theme.of(context)` 才能取得，不可能收斂為列舉的
/// 編譯期欄位。**列舉成員名稱維持不變**（含 `highlighterPink` 即使視覺上
/// 對應綠色）——改名會讓 `Enum.values.byName()` 持久化的既有使用者資料
/// （劃線樣式）反序列化失敗；「這個樣式渲染出來是什麼顏色」跟「這個樣式的
/// 識別字串是什麼」是兩件事，不需要同步改。純 UI 顯示標籤（例如「螢光筆
/// （黃）」）不放在這個檔案——見 `notes_bottom_sheet.dart` 的
/// `_highlightStyleLabel()`。
enum HighlightStyle {
  highlighterYellow,
  highlighterPink,
  highlighterBlue,
  underline,
}

/// 依樣式解析出對應的 [ElinkTokens] 顏色（`highlighterPink` 對應
/// `tokens.highlightGreen`，語意變更，`DESIGN.md` §1.2 既有決策）。純函式，
/// 呼叫端自行從 `Theme.of(context).extension<ElinkTokens>()!` 取得
/// [tokens]。原生 Decoration API 需要的 `int` ARGB32 值由呼叫端自行呼叫
/// `.toARGB32()`（見 Global Constraints「色彩決策收斂在 Dart 端」）。
Color highlightStyleColor(
  HighlightStyle style, {
  required ElinkTokens tokens,
}) {
  switch (style) {
    case HighlightStyle.highlighterYellow:
      return tokens.highlightYellow;
    case HighlightStyle.highlighterPink:
      return tokens.highlightGreen;
    case HighlightStyle.highlighterBlue:
      return tokens.highlightBlue;
    case HighlightStyle.underline:
      return tokens.underlineColor;
  }
}
```

- [x] **Step 4: 執行測試，確認通過（僅此檔案，其餘檔案此時仍在編譯錯誤狀態，不影響本步驟）**

Run（於 `app/` 目錄下）: `flutter test test/reader/highlight_style_test.dart`
Expected: PASS（這個測試檔只 import `highlight_style.dart` 與 `elink_tokens.dart`，不依賴 `reader_screen.dart`／`notes_bottom_sheet.dart`／`annotation_toolbar.dart`，`flutter test` 只編譯該測試檔的遞移依賴，其餘檔案此刻仍呼叫已刪除的 `highlightStyleTint()`／頂層常數也不影響這個獨立測試通過）。

- [x] **Step 5: 更新 `reader_screen.dart` 呼叫端**

在 `app/lib/screens/reader_screen.dart` 頂部 `import '../sync/sync_checkpoint_trigger.dart';`（原第 56 行）之後新增：

```dart
import '../theme/elink_tokens.dart';
```

把 `_sendDecorationsToNative()`（原第 1724-1745 行）：

```dart
  void _sendDecorationsToNative() {
    if (!mounted) return;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final decorations = <EpubDecoration>[
      for (final highlight in _highlights)
        if (highlight.epubLocatorJson != null)
          EpubDecoration.forHighlight(
            highlightId: highlight.id,
            locatorJson: highlight.epubLocatorJson!,
            tint: highlightStyleTint(highlight.style, primaryColor: primaryColor),
            isUnderline: highlight.style == HighlightStyle.underline,
          ),
      for (final note in _notes)
        if (note.highlightId == null && note.epubLocatorJson != null)
          EpubDecoration.forNote(
            noteId: note.id,
            locatorJson: note.epubLocatorJson!,
            tint: noteOnlyTint.toARGB32(),
          ),
    ];
    FoliateReaderView.setDecorations(_foliateEpubReaderViewKey, decorations);
  }
```

改為：

```dart
  void _sendDecorationsToNative() {
    if (!mounted) return;
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final decorations = <EpubDecoration>[
      for (final highlight in _highlights)
        if (highlight.epubLocatorJson != null)
          EpubDecoration.forHighlight(
            highlightId: highlight.id,
            locatorJson: highlight.epubLocatorJson!,
            tint: highlightStyleColor(highlight.style, tokens: tokens).toARGB32(),
            isUnderline: highlight.style == HighlightStyle.underline,
          ),
      for (final note in _notes)
        if (note.highlightId == null && note.epubLocatorJson != null)
          EpubDecoration.forNote(
            noteId: note.id,
            locatorJson: note.epubLocatorJson!,
            tint: noteOnlyTint.toARGB32(),
          ),
    ];
    FoliateReaderView.setDecorations(_foliateEpubReaderViewKey, decorations);
  }
```

把 `_sendPdfAnnotationsToNative()`（原第 1817-1838 行）：

```dart
  void _sendPdfAnnotationsToNative() {
    if (!mounted) return;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final annotations = <PdfAnnotationDecoration>[
      for (final highlight in _highlights)
        if (highlight.pdfPageIndex != null && highlight.pdfRect != null)
          PdfAnnotationDecoration.forHighlight(
            pageIndex: highlight.pdfPageIndex!,
            rect: highlight.pdfRect!,
            tint: highlightStyleTint(highlight.style, primaryColor: primaryColor),
            isUnderline: highlight.style == HighlightStyle.underline,
          ),
      for (final note in _notes)
        if (note.highlightId == null && note.pdfPageIndex != null && note.pdfRect != null)
          PdfAnnotationDecoration.forNote(
            pageIndex: note.pdfPageIndex!,
            rect: note.pdfRect!,
            tint: noteOnlyTint.toARGB32(),
          ),
    ];
    PdfReaderView.refreshAnnotations(_pdfReaderViewKey, annotations);
  }
```

改為：

```dart
  void _sendPdfAnnotationsToNative() {
    if (!mounted) return;
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final annotations = <PdfAnnotationDecoration>[
      for (final highlight in _highlights)
        if (highlight.pdfPageIndex != null && highlight.pdfRect != null)
          PdfAnnotationDecoration.forHighlight(
            pageIndex: highlight.pdfPageIndex!,
            rect: highlight.pdfRect!,
            tint: highlightStyleColor(highlight.style, tokens: tokens).toARGB32(),
            isUnderline: highlight.style == HighlightStyle.underline,
          ),
      for (final note in _notes)
        if (note.highlightId == null && note.pdfPageIndex != null && note.pdfRect != null)
          PdfAnnotationDecoration.forNote(
            pageIndex: note.pdfPageIndex!,
            rect: note.pdfRect!,
            tint: noteOnlyTint.toARGB32(),
          ),
    ];
    PdfReaderView.refreshAnnotations(_pdfReaderViewKey, annotations);
  }
```

- [x] **Step 6: 更新 `notes_bottom_sheet.dart` 呼叫端**

在 `app/lib/screens/notes_bottom_sheet.dart` 頂部 `import '../reader/markdown_export.dart';`（原第 17 行）之後新增：

```dart
import '../theme/elink_tokens.dart';
```

把 `_buildAnnotationRow()` 內的圖示顏色（原第 436-444 行）：

```dart
  Widget _buildAnnotationRow(AnnotationListItem item) {
    final highlight = item.highlight;
    final note = item.note;
    return ListTile(
      key: Key('notes_sheet_annotation_${item.key}'),
      leading: Icon(
        Icons.circle,
        color: highlight != null
            ? Color(highlightStyleTint(highlight.style,
                primaryColor: Theme.of(context).colorScheme.primary))
            : noteOnlyTint,
      ),
```

改為：

```dart
  Widget _buildAnnotationRow(AnnotationListItem item) {
    final highlight = item.highlight;
    final note = item.note;
    return ListTile(
      key: Key('notes_sheet_annotation_${item.key}'),
      leading: Icon(
        Icons.circle,
        color: highlight != null
            ? highlightStyleColor(highlight.style,
                tokens: Theme.of(context).extension<ElinkTokens>()!)
            : noteOnlyTint,
      ),
```

（`highlightStyleColor()` 已回傳 `Color`，不再需要外層 `Color(...)` 包裝原生 `int` 值。）

- [x] **Step 7: 更新 `annotation_toolbar.dart` 呼叫端（審查新增，原計劃遺漏）**

在 `app/lib/screens/annotation_toolbar.dart` 頂部 `import '../reader/highlight_style.dart';`（原第 3 行）之後新增：

```dart
import '../theme/elink_tokens.dart';
```

把 `build()` 方法內第一列的三顆螢光筆色塊（原第 46-73 行）：

```dart
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _colorButton(
                  key: const Key('annotation_toolbar_highlighter_yellow'),
                  color: highlighterYellowTint,
                  onTap: () => onStyleSelected(HighlightStyle.highlighterYellow),
                ),
                _colorButton(
                  key: const Key('annotation_toolbar_highlighter_pink'),
                  color: highlighterPinkTint,
                  onTap: () => onStyleSelected(HighlightStyle.highlighterPink),
                ),
                _colorButton(
                  key: const Key('annotation_toolbar_highlighter_blue'),
                  color: highlighterBlueTint,
                  onTap: () => onStyleSelected(HighlightStyle.highlighterBlue),
                ),
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _colorButton(
                  key: const Key('annotation_toolbar_highlighter_yellow'),
                  color: highlightStyleColor(HighlightStyle.highlighterYellow,
                      tokens: tokens),
                  onTap: () => onStyleSelected(HighlightStyle.highlighterYellow),
                ),
                _colorButton(
                  key: const Key('annotation_toolbar_highlighter_pink'),
                  color: highlightStyleColor(HighlightStyle.highlighterPink,
                      tokens: tokens),
                  onTap: () => onStyleSelected(HighlightStyle.highlighterPink),
                ),
                _colorButton(
                  key: const Key('annotation_toolbar_highlighter_blue'),
                  color: highlightStyleColor(HighlightStyle.highlighterBlue,
                      tokens: tokens),
                  onTap: () => onStyleSelected(HighlightStyle.highlighterBlue),
                ),
```

（`AnnotationToolbar` 是 `StatelessWidget`，`build(BuildContext context)` 本來就有 `context` 可用，不需要額外傳遞參數。）

- [x] **Step 8: 用腳本一次性補齊 `reader_screen_test.dart`／`annotation_toolbar_test.dart` 缺少 `ElinkTokens` 主題的 `MaterialApp`（審查新增，取代原本人工篩選 5 處的做法）**

原本計劃只精確列出 5 處需要修的 `MaterialApp`，但複審發現這個人工篩選方式有系統性漏洞（詳見上方「範圍決定」第 2 點）。改採以下已驗證過的腳本，對兩個測試檔案裡「每一處」建構 `ReaderScreen`／`AnnotationToolbar` 的 `MaterialApp` 做機械式全面補齊，不再依賴人工判斷。

在 `app/` 目錄下建立一個一次性工具檔 `insert_theme.py`（跑完即可刪除，不會被 commit）：

```python
import re
import sys

path = sys.argv[1]
home_body = sys.argv[2]  # e.g. "ReaderScreen(" or "Scaffold("

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

theme_arg = "theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),"

# Case A: MaterialApp( followed by a newline + indent + home: <home_body>
pattern_multiline = re.compile(
    r"(MaterialApp\(\r?\n)(?P<indent>[ \t]*)(home: " + re.escape(home_body) + r")"
)
# Case B: MaterialApp(home: <home_body> written on a single line
pattern_sameline = re.compile(
    r"MaterialApp\((home: " + re.escape(home_body) + r")"
)

count_multiline = 0
count_sameline = 0


def repl_multiline(m):
    global count_multiline
    count_multiline += 1
    indent = m.group("indent")
    return m.group(1) + indent + theme_arg + "\n" + indent + m.group(3)


def repl_sameline(m):
    global count_sameline
    count_sameline += 1
    return "MaterialApp(" + theme_arg + " " + m.group(1)


new_content = pattern_multiline.sub(repl_multiline, content)
new_content = pattern_sameline.sub(repl_sameline, new_content)

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)

print(
    f"{path}: multiline={count_multiline}, sameline={count_sameline}, "
    f"total={count_multiline + count_sameline}"
)
```

在 `app/test/screens/annotation_toolbar_test.dart` 頂部 `import 'package:flutter_test/flutter_test.dart';`（原第 2 行）之後新增（**這一步必須先做**——這個檔案跟 `reader_screen_test.dart` 不一樣，目前完全沒有 import 這兩個檔案，若漏了這步，下面的腳本插入 `theme: resolveThemeData(...)` 後這個測試檔會直接編譯失敗）：

```dart
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
```

`reader_screen_test.dart` 頂部第 32-33 行已經有這兩個 import（`resolveThemeData`／`AppTheme` 兩個測試檔在這步之後才「皆已在頂部 import」），不需要再新增。

執行（於 `app/` 目錄下）：

```bash
python3 insert_theme.py test/screens/reader_screen_test.dart "ReaderScreen("
python3 insert_theme.py test/screens/annotation_toolbar_test.dart "Scaffold("
```

Expected 輸出：

```
test/screens/reader_screen_test.dart: multiline=166, sameline=2, total=168
test/screens/annotation_toolbar_test.dart: multiline=12, sameline=0, total=12
```

（`reader_screen_test.dart` 總共有 181 處 `home: ReaderScreen(`，其中 13 處已經用 `theme: buildThemeData(AppTheme.light/dark)` 帶入含 `ElinkTokens` 的主題——這 13 處後面接的是 `theme: buildThemeData(...)` 而非直接 `home:`，不符合腳本比對的樣式，會被正確跳過，不會重複插入；168 + 13 = 181，數字對得上。除此之外，本檔案還有 6 處是先包一層 `MediaQuery`／`Builder` 才建到 `ReaderScreen`（例如 `home: Builder(builder: (context) => ... Navigator.push(..., builder: (_) => ReaderScreen(...)))`），這 6 處不符合腳本比對的樣式、也**不會**被腳本補上 `theme:`——已逐一讀過這 6 處程式碼確認：皆未傳入 `highlightsRepository`／`notesRepository`（劃線同步不會觸發），也沒有任何選字/框選模擬（不會顯示 `AnnotationToolbar`），維持現狀不會崩潰，刻意不擴大腳本比對範圍去處理它們——用更寬鬆的樣式（例如直接比對任何 `MaterialApp(` 後面接 `home: Builder(`）容易誤傷前面那 13 處已經有 `theme: buildThemeData(...)` 的測試，得不償失。`annotation_toolbar_test.dart` 全部 12 處皆為 `MaterialApp(\n  home: Scaffold(` 這個固定樣式，全部命中。若實際輸出數字跟這裡不同，先不要繼續，回頭檢查是否有新增/刪除過測試導致基準數字改變。）

跑完後執行 `dart format`（於 `app/` 目錄下）讓插入的程式碼符合專案既有格式：

```bash
dart format test/screens/reader_screen_test.dart test/screens/annotation_toolbar_test.dart
```

最後刪除這個一次性工具檔（不進版控；此時工作目錄仍是 `app/`，檔案就在當前目錄下，不要加 `app/` 前綴，否則會找錯路徑變成 `app/app/insert_theme.py`）：

```bash
rm insert_theme.py
```

- [x] **Step 9: 修正 `notes_bottom_sheet_test.dart` 兩個共用 pump helper**

在 `app/test/screens/notes_bottom_sheet_test.dart` 頂部 `import 'package:elinkbook/screens/notes_bottom_sheet.dart';` 之後新增：

```dart
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
```

把 `_pumpSheet()`（原第 20-52 行）內的 `pumpWidget` 呼叫：

```dart
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: NotesBottomSheet(
```

改為：

```dart
  await tester.pumpWidget(MaterialApp(
    theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
    home: Scaffold(
      body: NotesBottomSheet(
```

把 `_pumpModalSheet()`（原第 590-621 行）內的 `pumpWidget` 呼叫：

```dart
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
```

改為：

```dart
  await tester.pumpWidget(MaterialApp(
    theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
    home: Scaffold(
      body: Builder(
```

- [x] **Step 10: 執行四支測試檔，確認全數通過**

Run（於 `app/` 目錄下）:
```bash
flutter test test/reader/highlight_style_test.dart
flutter test test/screens/reader_screen_test.dart
flutter test test/screens/notes_bottom_sheet_test.dart
flutter test test/screens/annotation_toolbar_test.dart
```
Expected: 四個指令皆 PASS，全數綠燈（`reader_screen_test.dart`／`annotation_toolbar_test.dart` 皆為既有測試檔，此步驟同時驗證 Step 8 的機械式補齊沒有引入任何回歸；若有紅燈，先確認是否是 Step 8 腳本漏補或補錯某處，而不是回頭改動 `highlight_style.dart`／呼叫端邏輯）。

- [x] **Step 11: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`（此時四個原始碼檔案與四支測試檔的 API 用法已彼此一致，不再有任何地方引用已刪除的 `highlightStyleTint()`／`HighlightStyle.fixedTint`／三個頂層色票常數）。

- [x] **Step 12: Commit**

```bash
git add app/lib/reader/highlight_style.dart app/lib/screens/reader_screen.dart app/lib/screens/notes_bottom_sheet.dart app/lib/screens/annotation_toolbar.dart app/test/reader/highlight_style_test.dart app/test/screens/reader_screen_test.dart app/test/screens/notes_bottom_sheet_test.dart app/test/screens/annotation_toolbar_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 4 Task 1 — HighlightStyle 遷移＋四處呼叫端同步更新

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ue4QKXFUDw4c8F8wzQJzGn
EOF
)"
```

（`app/insert_theme.py` 已於 Step 8 刪除，不在這次 commit 的檔案清單內；若不小心忘記刪，`git status` 會看到這個未追蹤檔案，回頭刪掉即可，不要 `git add` 進去。）

---

### Task 2: `notes_bottom_sheet.dart`——`Colors.red` 遷移至 `colorScheme.error`

**Files:**
- Modify: `app/lib/screens/notes_bottom_sheet.dart`（`_confirmDeleteAllBookmarks()` 原第 349 行；`_confirmDeleteAll()` 原第 531 行，兩處皆為 Task 1 完成後的行號，Task 1 只新增 import 與改動 `_buildAnnotationRow()`，不影響這兩處的行號）
- Test: `app/test/screens/notes_bottom_sheet_test.dart`

**Interfaces:**
- Consumes: 無新增依賴（`Theme.of(context).colorScheme.error` 為既有 `ColorScheme` 標準角色，四套主題皆已在 Issue 2 設定好，見 `app_theme_data.dart`）。
- Produces: 無新增介面，本 Task 只改顏色來源，不改任何函式簽章。

- [x] **Step 1: 寫失敗的測試——刪除按鈕前景色改讀 `colorScheme.error`**

在 `app/test/screens/notes_bottom_sheet_test.dart` 檔案最後一個 `testWidgets`（`'點擊右上角 X 取消按鈕後...'`）之後、`main()` 收尾 `}` 之前，新增：

```dart
  testWidgets('批次刪除書籤確認對話框的「刪除」按鈕前景色為 colorScheme.error', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository
        .insert(const Bookmark(id: 'bm13', bookId: 'b1', name: 'A', progression: 0.1));
    await _pumpSheet(tester, repository: repository);

    await tester
        .tap(find.byKey(const Key('notes_sheet_delete_all_bookmarks')));
    await tester.pumpAndSettle();

    final button = tester.widget<TextButton>(
      find.byKey(const Key('notes_sheet_delete_all_bookmarks_confirm')),
    );
    final context = tester.element(
      find.byKey(const Key('notes_sheet_delete_all_bookmarks_confirm')),
    );
    expect(
      button.style?.foregroundColor?.resolve({}),
      Theme.of(context).colorScheme.error,
    );
  });

  testWidgets('批次刪除劃線確認對話框的「刪除」按鈕前景色為 colorScheme.error', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(
      const Highlight(id: 'h8', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1),
    );
    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notes_sheet_delete_all_highlights')));
    await tester.pumpAndSettle();

    final button = tester.widget<TextButton>(
      find.byKey(const Key('notes_sheet_delete_all_highlights_confirm')),
    );
    final context = tester.element(
      find.byKey(const Key('notes_sheet_delete_all_highlights_confirm')),
    );
    expect(
      button.style?.foregroundColor?.resolve({}),
      Theme.of(context).colorScheme.error,
    );
  });
```

（`button.style?.foregroundColor?.resolve({})` 已核對 Flutter SDK 原始碼：`TextButton.styleFrom()` 內部呼叫 `ButtonStyleButton.defaultColor(foregroundColor, disabledForegroundColor)`，組成 `WidgetStateProperty<Color?>.fromMap({WidgetState.disabled: disabled, WidgetState.any: enabled})`；`resolve(const <WidgetState>{})`〔空集合，代表「未停用」〕會落入 `WidgetState.any` 分支、回傳 `enabled`〔即 `styleFrom()` 傳入的 `foregroundColor`〕——這是 Flutter 框架內部本身採用的標準手法，不是巧合湊出來的寫法。）

- [x] **Step 2: 執行測試，確認失敗**

Run（於 `app/` 目錄下）: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: 兩則新測試皆 FAIL（目前 `foregroundColor` 解析出的是 `Colors.red`，不等於 `resolveThemeData(theme: AppTheme.light, isEinkMode: false).colorScheme.error`，兩者不同值——Light 主題 `error` 為 `Color(0xFFEF4444)`，並非 Material `Colors.red` 的 `Color(0xFFF44336)`）。

- [x] **Step 3: 實作——兩處 `Colors.red` 改為 `colorScheme.error`**

把 `_confirmDeleteAllBookmarks()` 內（原第 349 行，`builder: (dialogContext) => AlertDialog(...)` 區塊內）：

```dart
            style: TextButton.styleFrom(foregroundColor: Colors.red),
```

改為：

```dart
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
```

把 `_confirmDeleteAll()` 內（原第 531 行，供 `_confirmDeleteAllHighlights()`／`_confirmDeleteAllNotes()` 共用，同樣是 `builder: (dialogContext) => AlertDialog(...)` 區塊內）：

```dart
            style: TextButton.styleFrom(foregroundColor: Colors.red),
```

改為：

```dart
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
```

（兩處都用 `_NotesBottomSheetState` 本身的 `context`（`State.context` getter），不是 `builder` 回呼帶入的 `dialogContext`——`showDialog` 走 root `Navigator`，`Theme` 掛在外層 `MaterialApp`，兩個 `BuildContext` 在這裡會解析到同一個 `ThemeData`，用哪一個功能上皆可運作，本計劃統一採用外層 `context`，避免改動 `builder` 簽章。）

- [x] **Step 4: 執行測試，確認通過**

Run（於 `app/` 目錄下）: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: PASS（本檔案全部測試皆過，含 Task 1 新增的既有測試，無回歸）。

- [x] **Step 5: 執行 `flutter analyze`，確認乾淨**

Run（於 `app/` 目錄下）: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/notes_bottom_sheet.dart app/test/screens/notes_bottom_sheet_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 4 Task 2 — notes_bottom_sheet.dart Colors.red 遷移至 colorScheme.error

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ue4QKXFUDw4c8F8wzQJzGn
EOF
)"
```

---

## 全部 Task 完成後

- [x] 執行完整 `flutter test`（於 `app/` 目錄下，不帶檔案路徑），確認全專案無回歸。
- [x] 執行 `flutter analyze`，確認「No issues found!」。
- [x] 把 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 4 的 `Status` 從 `ready-for-agent` 更新為完成狀態（依當時 Epic 慣例用語），並在 `epic.md` 補一筆開發記錄。
- [x] 依 `sdd-workflow` 流程，發起 `/superpowers:requesting-code-review` 審查本次程式碼變更（`BASE_SHA`／`HEAD_SHA` 取本工單 2 個 commit 的起訖），審查報告存 `docs/epics/epic-35-design-system-tokens/reviews/review-issue-4.md`。
- [x] 提醒：`reader_screen.dart` 剩餘 3 處寫死顏色（`_themedTtsDisabledIconColor`／`_themedTextColor` 的 `Colors.black` 候補值）已於本計劃「範圍決定」段落記錄為刻意排除，非本工單遺漏；若後續有人質疑，指向本檔案該段落即可。
