# Epic 16 Issue 3 — 方向偵測基礎建設 + PDF 雙頁核心渲染 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立橫向偵測共用基礎設施（`ReaderScreen` 透過 `MediaQuery` 偵測 `isLandscape`），並實作 PDF 雙頁渲染核心管線——封面獨立配對、LTR/RTL 頁面配對、拼接、OOM 回退、翻頁步進（含 C-4 對稱規則）、頁碼回報，讓 PDF 在橫向（或 `always` 模式）下能正確顯示無縫雙頁。

**Architecture:** Dart 端沿用既有「`ResolvedPreferences`/`ReaderPrefsManagerImpl.resolve()` 集中做 Null 預設值解析」模式（`docs/superpowers/plans/2026-07-12-refactor-reader-prefs-manager.md` 已完成的重構，取代 `epic-16-dual-page/issues.md` Issue 3 原描述的 `_resolvedXxx` getter 寫法，以 `spec.md`「Null 預設值解析」段落為準）；`PdfReaderView`（Dart）新增的 4 個雙頁/橫向參數皆為 non-nullable、附帶預設值（比照既有 `cropEditModeActive = false` 慣例），`ReaderScreen` 一律傳入已解析的非 null 值。原生端 `PdfReaderView.kt` 把 `renderCurrentPage()` 更名為 `renderCurrentSpread()`，拆解為 `renderPageBitmap()`（單頁渲染核心，含裁切/縮放）＋`stitchBitmaps()`（拼接）＋`displayFinalBitmap()`（加粗/fit/濾鏡）＋`renderSingleSpread()`（單頁與 OOM 回退共用路徑）；雙頁生效判斷、配對、翻頁步進四個判斷抽成 `PdfReaderView` 的 `companion object` 純函式（無 Android 依賴），可脫離真機以 JVM 單元測試涵蓋——這是本 issue 對「技術風險最高」的因應：把純邏輯（含 C-4 對稱規則）與必須真機驗證的像素渲染（拼接/OOM）切開。

**Tech Stack:** Flutter/Dart、Kotlin（`android.graphics.pdf.PdfRenderer`）、JUnit 4（JVM 單元測試，`app/android` 既有基礎設施）。

## 開發狀態（已完成，2026-07-13）

Task 1-7 全數完成並提交，branch `epic-16/dual-page-issue3`，共 9 個 commit：

```
934623d feat(epic-16): book_reader_prefs 表升級至 version 4，新增雙頁欄位（累加式 onUpgrade 修正）— Issue 2，前置依賴
c4438b4 feat(epic-16): ResolvedPreferences/ReaderPrefsManagerImpl 新增雙頁 Null 預設值解析 — Task 1
a3ec83c feat(epic-16): PdfReaderView 新增雙頁/橫向建構參數 — Task 2
5623c63 feat(epic-16): ReaderScreen 新增 isLandscape 方向偵測並接線至 PdfReaderView — Task 3
909d447 feat(epic-16): PdfSettingsSheet 顯示分頁新增雙頁模式三態控制項 — Task 4
b9e89b5 feat(epic-16): PdfReaderView.kt 新增 DualPageMode/DualPageDirection 列舉與雙頁純函式（JVM 測試）— Task 5
694a5ad feat(epic-16): PdfReaderView.kt renderCurrentSpread() 完整雙頁演算法（拼接/OOM回退/C-4翻頁步進）— Task 6
5b61e90 test(epic-16): 新增雙頁測試 PDF fixture 與 integration_test 真機驗證 — Task 7
ff23288 fix(epic-16): renderCurrentSpread()/stitchBitmaps() OOM 回退時點陣圖洩漏修補 — 審查修正
8a63e68 test(epic-16): 整合測試改用 dynamic 呼叫 nextPage/previousPage 以繞過手勢穿透限制 — 審查修正
```

**審查歷程**：`/superpowers:requesting-code-review` 兩輪審查，皆存於 `tmp/epic-16/reviews/`：
- Round 1（`review-issue-3-integrated.md`）：1 項 Critical（Task 7 完全未實作）、2 項 Important（`renderCurrentSpread()`/`stitchBitmaps()` OOM 回退時點陣圖洩漏）。
- Round 2（`review-issue-3-integrated-round2.md`）：Round 1 三項皆修正完成並複驗通過；真機接上後另外發現 Task 7 原始 `integration_test`（`tester.drag()` 模擬手勢）在 Flutter 3.41.9 + Android 15 (API 35) 這個組合下必定失敗——診斷後確認是測試工具本身無法把合成/`adb` 觸控事件送達 `AndroidView` 疊加的手勢層（與本專案既有 `CropOverlayView` 拖曳測試限制同類），非功能性回歸（`flutter run` 手指實際滑動已確認翻頁正常）。改寫 `integration_test/pdf_dual_page_test.dart`，直接以 `(tester.state(find.byType(PdfReaderView)) as dynamic).nextPage()`/`.previousPage()` 動態呼叫繞過手勢層，複驗真機 6/6 全數通過。**最終結論：Ready to merge: Yes**。

**與計劃原文的已知落差**：下方 Task 7 Step 2 的 `integration_test/pdf_dual_page_test.dart` 程式碼區塊是撰寫計劃當下的原始設計（用 `tester.drag()` 模擬滑動手勢），實際落地程式碼已依上述審查發現改寫為 `_nextPage(tester)`/`_previousPage(tester)` 動態呼叫版本，不再依賴手勢模擬；計劃步驟本身（撰寫測試→跑測試→真機驗證→commit 的流程）仍如實對應到最終提交，僅測試「如何觸發翻頁」的實作手法有變動，行為驗證的目標（翻頁步進量、C-4 對稱規則、OOM 回退）未變。

## Global Constraints

- **前置狀態（已確認完成，非假設）**：Issue 2（`docs/epics/epic-16-dual-page/plans/plan-issue-2.md`）已完成實作並經 `/superpowers:requesting-code-review` 審查核准（Ready to merge: Yes，branch `epic-16/dual-page-prefs-storage`，commit `934623d`，無 Critical/Important 問題）——`DualPageMode`（`app/lib/reader/dual_page_mode.dart`，`auto`/`always`/`never`）、`DualPageDirection`（`app/lib/reader/dual_page_direction.dart`，`ltr`/`rtl`）、`BookReaderPrefs.dualPageMode`/`dualPageCoverAlone`/`dualPageDirection`（皆 nullable）、`book_reader_prefs` 表對應 3 欄位（schema version 4）皆已存在，本計劃可直接依賴。
- **Null 預設值解析位置**：依 `spec.md`「Null 預設值解析」段落（2026-07-12 因 `ReaderPrefsManager` 重構同步修訂），本 issue 把 3 個雙頁欄位新增到 `ResolvedPreferences`（non-nullable）與 `ReaderPrefsManagerImpl.resolve()`，**不是** `issues.md` Issue 3 原描述的 `ReaderScreen._resolvedDualPageMode` 之類 getter——`_resolvedPdfFitMode` 這類 getter 現已不存在於 `ReaderScreen` 中。
- **Method Channel 契約**：`dualPageMode`（`String`）／`dualPageCoverAlone`（`bool`）／`dualPageDirection`（`String`）／`isLandscape`（`bool`）四個欄位由 `ReaderScreen` 解析為非 null 值後傳入 `PdfReaderView`（Dart），`PdfReaderView._buildPreferencesMap()` 一律無條件把這 4 個欄位放進 `openBook`/`setPdfPreferences` 的 map（不比照其餘可選欄位的 `if (x != null)` 判斷模式）；原生端一律收到非 null 值。
- **頁碼索引慣例**：全文 0-indexed，`currentPageIndex` 從 0 起算。
- **翻頁步進 C-4 對稱規則**：前進時封面特例步進 1、其餘步進 2；後退時對稱處理——從 spread 左頁 index 1 回封面時步進 1、其餘步進 2；不得對負數 index 呼叫 `openPage()`。
- **OOM 回退**：拼接階段 `OutOfMemoryError` 時回退為只渲染 `currentPageIndex` 單頁，`onPageChanged` 依然回報 `currentPageIndex`。
- **本 issue 範圍邊界**：`dualPageCoverAlone`／`dualPageDirection` 的 UI 控制項留給 Issue 4（原生端已完整支援，本 issue 期間這兩欄位僅能透過已持久化資料或直接建構 `PdfReaderView` 觸及，`PdfSettingsSheet` 只新增「雙頁模式」三態）；手動裁切 × 雙頁互動屬 Issue 5，本 issue 只需確保既有 `cropEditModeActive` 守衛持續生效、不需異動裁切互動邏輯本身。
- **不得引入的範圍**：不新增任何新的 pure-Kotlin 模組檔案（不同於 Issue 6 的 `EpubFxlScaler`），雙頁純邏輯函式一律放在 `PdfReaderView` 自身的 `companion object`（比照既有 `PdfFitMode`/`PdfCropMode` 巢狀列舉＋`fromWireValue` 的抽離規模，避免過度設計）。

---

### Task 1：`ResolvedPreferences` + `ReaderPrefsManagerImpl.resolve()` 雙頁 Null 預設值解析

**Files:**
- Modify: `app/lib/reader/resolved_preferences.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Test: `app/test/reader/resolved_preferences_test.dart`
- Test: `app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Consumes：Issue 2 產出的 `DualPageMode`/`DualPageDirection` enum、`BookReaderPrefs.dualPageMode`/`dualPageCoverAlone`/`dualPageDirection`（皆 nullable）
- Produces：`ResolvedPreferences.dualPageMode: DualPageMode`／`dualPageCoverAlone: bool`／`dualPageDirection: DualPageDirection`（皆 non-nullable，供 Task 3 的 `ReaderScreen` 讀取）；`ReaderPrefsManagerImpl.resolve()` 對這 3 個新欄位套用 `?? DualPageMode.auto`／`?? true`／`?? DualPageDirection.ltr`

- [x] **Step 1：撰寫失敗測試——擴充 `resolved_preferences_test.dart`**

把整份檔案改為：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';

void main() {
  test('建構後各欄位保留傳入值，EPUB 欄位可為 null（無既存預設值，維持既有 pass-through 語意）',
      () {
    const resolved = ResolvedPreferences(
      writingMode: null,
      fontFamily: null,
      fontSize: null,
      fontWeight: null,
      lineHeight: null,
      paragraphSpacing: null,
      pageMargins: null,
      textAlign: null,
      publisherStyles: null,
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
      pdfFitMode: PdfFitMode.pageFit,
      pdfContrast: 0,
      pdfBrightness: 0,
      pdfBoldStrength: 0,
      pdfCropMode: PdfCropMode.none,
      pdfCropRect: null,
      dualPageMode: DualPageMode.auto,
      dualPageCoverAlone: true,
      dualPageDirection: DualPageDirection.ltr,
    );

    expect(resolved.fontSize, isNull);
    expect(resolved.textAlign, isNull);
    expect(resolved.pageTurnMode, PageTurnMode.paginated);
    expect(resolved.pdfFitMode, PdfFitMode.pageFit);
    expect(resolved.dualPageMode, DualPageMode.auto);
    expect(resolved.dualPageCoverAlone, isTrue);
    expect(resolved.dualPageDirection, DualPageDirection.ltr);
  });
}
```

- [x] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/reader/resolved_preferences_test.dart
```

Expected：FAIL——編譯錯誤，`ResolvedPreferences` 建構子沒有 `dualPageMode`/`dualPageCoverAlone`/`dualPageDirection` 具名參數。

- [x] **Step 3：修改 `resolved_preferences.dart`**

把 import 區塊（第 1-8 行）改為：

```dart
import 'app_font.dart';
import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
import 'pdf_fit_mode.dart';
import 'screen_orientation_setting.dart';
import 'writing_mode.dart';
```

在欄位宣告區塊，`final PdfCropRect? pdfCropRect; // pdfCropMode == none 時為 null，既有語意` 之後新增：

```dart

  final DualPageMode dualPageMode;
  final bool dualPageCoverAlone;
  final DualPageDirection dualPageDirection;
```

建構子在 `this.pdfCropRect,` 之後新增：

```dart
    required this.dualPageMode,
    required this.dualPageCoverAlone,
    required this.dualPageDirection,
```

（`this.pdfCropRect,` 前一行 `required this.pdfCropMode,` 維持不變；`pdfCropRect` 本身非 required，保留原樣。）

- [x] **Step 4：執行測試，確認通過**

```bash
flutter test test/reader/resolved_preferences_test.dart
```

Expected：PASS。

- [x] **Step 5：撰寫失敗測試——擴充 `reader_prefs_manager_test.dart`**

把 import 區塊（第 1-17 行）中 `import 'package:elinkbook/reader/book_reader_prefs_repository.dart';` 之後新增：

```dart
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
```

把測試 `'全部欄位皆未覆寫時，回傳的 non-null 欄位皆為既存安全預設值'` 內，`expect(resolved.pdfCropRect, isNull);` 之後新增：

```dart
      expect(resolved.dualPageMode, DualPageMode.auto);
      expect(resolved.dualPageCoverAlone, isTrue);
      expect(resolved.dualPageDirection, DualPageDirection.ltr);
```

把測試 `'單書覆寫存在時，優先套用單書覆寫，忽略全域預設'` 改為：

```dart
    test('單書覆寫存在時，優先套用單書覆寫，忽略全域預設', () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(
          pageTurnModeOverride: PageTurnMode.scroll,
          screenOrientationOverride: ScreenOrientationSetting.lock90,
          pdfFitMode: PdfFitMode.fitWidth,
          pdfContrast: 20,
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: false,
          dualPageDirection: DualPageDirection.rtl,
        ),
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.pageTurnMode, PageTurnMode.scroll);
      expect(resolved.screenOrientation, ScreenOrientationSetting.lock90);
      expect(resolved.pdfFitMode, PdfFitMode.fitWidth);
      expect(resolved.pdfContrast, 20);
      expect(resolved.dualPageMode, DualPageMode.always);
      expect(resolved.dualPageCoverAlone, isFalse);
      expect(resolved.dualPageDirection, DualPageDirection.rtl);
    });
```

- [x] **Step 6：執行測試，確認失敗**

```bash
flutter test test/reader/reader_prefs_manager_test.dart
```

Expected：FAIL——`resolved.dualPageMode` 等欄位不存在（編譯錯誤）或 `ResolvedPreferences` 建構缺少必要參數。

- [x] **Step 7：修改 `reader_prefs_manager_impl.dart`**

把 import 區塊（第 1-12 行）中 `import 'book_reader_prefs_repository.dart';` 之後新增：

```dart
import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
```

把 `resolve()` 方法尾端（原第 97-103 行）：

```dart
      pdfFitMode: book.pdfFitMode ?? PdfFitMode.pageFit,
      pdfContrast: book.pdfContrast ?? 0,
      pdfBrightness: book.pdfBrightness ?? 0,
      pdfBoldStrength: book.pdfBoldStrength ?? 0,
      pdfCropMode: book.pdfCropMode ?? PdfCropMode.none,
      pdfCropRect: book.pdfCropRect,
    );
```

改為：

```dart
      pdfFitMode: book.pdfFitMode ?? PdfFitMode.pageFit,
      pdfContrast: book.pdfContrast ?? 0,
      pdfBrightness: book.pdfBrightness ?? 0,
      pdfBoldStrength: book.pdfBoldStrength ?? 0,
      pdfCropMode: book.pdfCropMode ?? PdfCropMode.none,
      pdfCropRect: book.pdfCropRect,
      dualPageMode: book.dualPageMode ?? DualPageMode.auto,
      dualPageCoverAlone: book.dualPageCoverAlone ?? true,
      dualPageDirection: book.dualPageDirection ?? DualPageDirection.ltr,
    );
```

- [x] **Step 8：執行測試，確認通過**

```bash
flutter test test/reader/reader_prefs_manager_test.dart test/reader/resolved_preferences_test.dart
```

Expected：全數 PASS。

- [x] **Step 9：Commit**

```bash
git add app/lib/reader/resolved_preferences.dart app/lib/reader/reader_prefs_manager_impl.dart app/test/reader/resolved_preferences_test.dart app/test/reader/reader_prefs_manager_test.dart
git commit -m "feat(epic-16): ResolvedPreferences/ReaderPrefsManagerImpl 新增雙頁 Null 預設值解析"
```

---

### Task 2：`PdfReaderView`（Dart）新增雙頁/橫向建構參數

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Test: `app/test/reader/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes：Issue 2 的 `DualPageMode`/`DualPageDirection` enum
- Produces：`PdfReaderView` 建構子新增 `dualPageMode: DualPageMode`（預設 `DualPageMode.auto`）／`dualPageCoverAlone: bool`（預設 `true`）／`dualPageDirection: DualPageDirection`（預設 `DualPageDirection.ltr`）／`isLandscape: bool`（預設 `false`）四個 non-nullable 參數；`_buildPreferencesMap()` 一律包含 `dualPageMode`/`dualPageCoverAlone`/`dualPageDirection`/`isLandscape` 四個 wire key（供 Task 3 的 `ReaderScreen` 與 Task 6 的原生端消費）

- [x] **Step 1：撰寫失敗測試——更新既有 9 個 exact-map 斷言並新增雙頁測試**

在 `app/test/reader/pdf_reader_view_test.dart` 開頭 import 區塊，`import 'package:elinkbook/reader/pdf_crop_mode.dart';` 之後新增：

```dart
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
```

以下 9 處既有的 exact-map 斷言，因為 `_buildPreferencesMap()` 之後會無條件加入 4 個雙頁/橫向 key，需要逐一更新（新增的 4 個 key 皆為未顯式指定時的預設值：`dualPageMode: 'auto'`／`dualPageCoverAlone: true`／`dualPageDirection: 'ltr'`／`isLandscape: false`）：

1. 測試 `'_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含 fitMode'`，把：

```dart
    expect(openBookCall.arguments['initialPreferences'], {'fitMode': 'fitWidth'});
```

改為：

```dart
    expect(openBookCall.arguments['initialPreferences'], {
      'fitMode': 'fitWidth',
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'ltr',
      'isLandscape': false,
    });
```

2. 測試標題 `'fitMode 為 null 時，initialPreferences 為空 map（而非 null）'` 改名為 `'fitMode 為 null 時，initialPreferences 僅包含雙頁/橫向的預設值（不再是空 map）'`，內容：

```dart
  testWidgets(
      'fitMode 為 null 時，initialPreferences 僅包含雙頁/橫向的預設值（不再是空 map）',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'ltr',
      'isLandscape': false,
    });
  });
```

3. 測試 `'fitMode 變動時，didUpdateWidget 呼叫 setPdfPreferences 並帶入新值'`，把：

```dart
    expect(instanceCalls.single.arguments, {'fitMode': 'actualSize'});
```

改為：

```dart
    expect(instanceCalls.single.arguments, {
      'fitMode': 'actualSize',
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'ltr',
      'isLandscape': false,
    });
```

4. 測試 `'_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含 contrast／brightness'`，把：

```dart
    expect(openBookCall.arguments['initialPreferences'], {
      'contrast': 20.0,
      'brightness': -15.0,
    });
```

改為：

```dart
    expect(openBookCall.arguments['initialPreferences'], {
      'contrast': 20.0,
      'brightness': -15.0,
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'ltr',
      'isLandscape': false,
    });
```

5. 測試 `'contrast／brightness 變動時，didUpdateWidget 呼叫 setPdfPreferences'`，把：

```dart
    expect(instanceCalls.single.arguments, {
      'contrast': 10.0,
      'brightness': 25.0,
    });
```

改為：

```dart
    expect(instanceCalls.single.arguments, {
      'contrast': 10.0,
      'brightness': 25.0,
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'ltr',
      'isLandscape': false,
    });
```

6. 測試 `'_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含 boldStrength'`，把：

```dart
    expect(openBookCall.arguments['initialPreferences'], {'boldStrength': 0.5});
```

改為：

```dart
    expect(openBookCall.arguments['initialPreferences'], {
      'boldStrength': 0.5,
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'ltr',
      'isLandscape': false,
    });
```

7. 測試 `'boldStrength 變動時，didUpdateWidget 呼叫 setPdfPreferences'`，把：

```dart
    expect(instanceCalls.single.arguments, {'boldStrength': 0.8});
```

改為：

```dart
    expect(instanceCalls.single.arguments, {
      'boldStrength': 0.8,
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'ltr',
      'isLandscape': false,
    });
```

8. 測試 `'_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含 cropMode／cropRect'`，把：

```dart
    expect(openBookCall.arguments['initialPreferences'], {
      'cropMode': 'autoDetect',
      'cropRect': {'left': 0.05, 'top': 0.1, 'right': 0.95, 'bottom': 0.9},
    });
```

改為：

```dart
    expect(openBookCall.arguments['initialPreferences'], {
      'cropMode': 'autoDetect',
      'cropRect': {'left': 0.05, 'top': 0.1, 'right': 0.95, 'bottom': 0.9},
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'ltr',
      'isLandscape': false,
    });
```

9. 測試 `'cropMode 變動時，didUpdateWidget 呼叫 setPdfPreferences'`，把：

```dart
    expect(instanceCalls.single.arguments, {'cropMode': 'autoDetect'});
```

改為：

```dart
    expect(instanceCalls.single.arguments, {
      'cropMode': 'autoDetect',
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'ltr',
      'isLandscape': false,
    });
```

（`cropEditModeActive` 相關的 `enterCropEditMode`/`exitCropEditMode` 測試斷言的是 `instanceCalls.single.method`／`arguments isNull`，不涉及 `setPdfPreferences` 的 map 內容，不需要修改。）

新增以下 5 個測試，插入在檔案倒數第二個測試（`'收到原生端 onCropRectSelected 時，正確觸發回呼'`）之後、`}`（`main()` 結尾）之前：

```dart
  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 正確包含非預設的雙頁/橫向欄位',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
        dualPageCoverAlone: false,
        dualPageDirection: DualPageDirection.rtl,
        isLandscape: true,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {
      'dualPageMode': 'always',
      'dualPageCoverAlone': false,
      'dualPageDirection': 'rtl',
      'isLandscape': true,
    });
  });

  testWidgets('dualPageMode 變動時，didUpdateWidget 呼叫 setPdfPreferences 並帶入完整最新狀態',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {
      'dualPageMode': 'always',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'ltr',
      'isLandscape': false,
    });
  });

  testWidgets('isLandscape 變動時，didUpdateWidget 呼叫 setPdfPreferences',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        isLandscape: true, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'ltr',
      'isLandscape': true,
    });
  });

  testWidgets('dualPageCoverAlone／dualPageDirection 變動時，didUpdateWidget 呼叫 setPdfPreferences',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageCoverAlone: false, // 變動
        dualPageDirection: DualPageDirection.rtl, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {
      'dualPageMode': 'auto',
      'dualPageCoverAlone': false,
      'dualPageDirection': 'rtl',
      'isLandscape': false,
    });
  });

  testWidgets('雙頁/橫向欄位皆未變動時，didUpdateWidget 不觸發任何 setPdfPreferences 呼叫',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    final widget = const PdfReaderView(
      filePath: '/tmp/sample.pdf',
      onPageRendered: _noop,
      onError: _noopError,
      dualPageMode: DualPageMode.always,
      dualPageCoverAlone: false,
      dualPageDirection: DualPageDirection.rtl,
      isLandscape: true,
    );
    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pumpAndSettle();

    expect(instanceCalls, isEmpty);
  });
```

- [x] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/reader/pdf_reader_view_test.dart
```

Expected：FAIL——新測試因 `PdfReaderView` 沒有 `dualPageMode`/`dualPageCoverAlone`/`dualPageDirection`/`isLandscape` 具名參數而編譯失敗；既有 9 個更新過的測試因目前 `_buildPreferencesMap()` 尚未加入新 key 而斷言失敗。

- [x] **Step 3：修改 `pdf_reader_view.dart`**

把 import 區塊（第 1-6 行）改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
import 'pdf_fit_mode.dart';
```

在欄位宣告區塊，`final ValueChanged<PdfCropRect>? onCropRectSelected;` 之後新增：

```dart
  final DualPageMode dualPageMode;
  final bool dualPageCoverAlone;
  final DualPageDirection dualPageDirection;
  final bool isLandscape;
```

建構子（原第 38-55 行）改為：

```dart
  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onNextPage,
    this.onPreviousPage,
    this.onPageChanged,
    this.fitMode,
    this.contrast,
    this.brightness,
    this.boldStrength,
    this.cropMode,
    this.cropRect,
    this.onCropRectComputed,
    this.cropEditModeActive = false,
    this.onCropRectSelected,
    this.dualPageMode = DualPageMode.auto,
    this.dualPageCoverAlone = true,
    this.dualPageDirection = DualPageDirection.ltr,
    this.isLandscape = false,
  });
```

`didUpdateWidget`（原第 74-89 行）的第一個 `if` 條件改為：

```dart
  @override
  void didUpdateWidget(covariant PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fitMode != oldWidget.fitMode ||
        widget.contrast != oldWidget.contrast ||
        widget.brightness != oldWidget.brightness ||
        widget.boldStrength != oldWidget.boldStrength ||
        widget.cropMode != oldWidget.cropMode ||
        widget.dualPageMode != oldWidget.dualPageMode ||
        widget.dualPageCoverAlone != oldWidget.dualPageCoverAlone ||
        widget.dualPageDirection != oldWidget.dualPageDirection ||
        widget.isLandscape != oldWidget.isLandscape) {
      _channel?.invokeMethod('setPdfPreferences', _buildPreferencesMap());
    }
    if (widget.cropEditModeActive != oldWidget.cropEditModeActive) {
      _channel?.invokeMethod(
        widget.cropEditModeActive ? 'enterCropEditMode' : 'exitCropEditMode',
      );
    }
  }
```

`_buildPreferencesMap()`（原第 93-109 行）改為：

```dart
  Map<String, Object?> _buildPreferencesMap() {
    final map = <String, Object?>{};
    if (widget.fitMode != null) map['fitMode'] = widget.fitMode!.name;
    if (widget.contrast != null) map['contrast'] = widget.contrast;
    if (widget.brightness != null) map['brightness'] = widget.brightness;
    if (widget.boldStrength != null) map['boldStrength'] = widget.boldStrength;
    if (widget.cropMode != null) map['cropMode'] = widget.cropMode!.name;
    if (widget.cropRect != null) {
      map['cropRect'] = {
        'left': widget.cropRect!.left,
        'top': widget.cropRect!.top,
        'right': widget.cropRect!.right,
        'bottom': widget.cropRect!.bottom,
      };
    }
    // 以下 4 個欄位由 ReaderScreen 解析為非 null 值後才會建構本 widget（見
    // docs/epics/epic-16-dual-page/spec.md「Null 預設值解析」），一律無
    // 條件放入 map，不比照上方其餘可選欄位的 null 判斷模式。
    map['dualPageMode'] = widget.dualPageMode.name;
    map['dualPageCoverAlone'] = widget.dualPageCoverAlone;
    map['dualPageDirection'] = widget.dualPageDirection.name;
    map['isLandscape'] = widget.isLandscape;
    return map;
  }
```

- [x] **Step 4：執行測試，確認通過**

```bash
flutter test test/reader/pdf_reader_view_test.dart
```

Expected：全數 PASS。

- [x] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected："No issues found!"

- [x] **Step 6：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_test.dart
git commit -m "feat(epic-16): PdfReaderView 新增雙頁/橫向建構參數"
```

---

### Task 3：`ReaderScreen` 方向偵測（`isLandscape`）+ 接線至 `PdfReaderView`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `resolved.dualPageMode`/`dualPageCoverAlone`/`dualPageDirection`；Task 2 的 `PdfReaderView` 新建構參數
- Produces：`ReaderScreen.build()` 透過 `MediaQuery.of(context).orientation` 算出 `bool isLandscape`（格式無關、共用），下傳給 PDF 分支的 `PdfReaderView`（EPUB 分支消費 `isLandscape` 屬 Issue 6 範圍，本 issue 不新增）

- [x] **Step 1：撰寫失敗測試——擴充 `reader_screen_test.dart`**

在 `app/test/screens/reader_screen_test.dart` 開頭 import 區塊，`import 'package:elinkbook/reader/book_reader_prefs.dart';` 之後新增：

```dart
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
```

在檔案最後一個測試（`'onLayoutResolved 觸發後...'`）之後、`}`（`main()` 結尾）之前，新增以下 4 個測試：

```dart
  testWidgets('裝置為橫向時，isLandscape 正確下傳給 PdfReaderView 建構參數',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 400)); // 橫向

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.isLandscape, isTrue);
  });

  testWidgets('裝置為直向時，isLandscape 正確下傳為 false', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800)); // 直向

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.isLandscape, isFalse);
  });

  testWidgets('開啟該書已有的持久化雙頁偏好設定後，PdfReaderView 的雙頁參數正確載入',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(
        dualPageMode: DualPageMode.always,
        dualPageCoverAlone: false,
        dualPageDirection: DualPageDirection.rtl,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.dualPageMode, DualPageMode.always);
    expect(pdfView.dualPageCoverAlone, isFalse);
    expect(pdfView.dualPageDirection, DualPageDirection.rtl);
  });

  testWidgets(
      '尚未持久化雙頁偏好設定時，PdfReaderView 的雙頁參數採用預設值（auto／true／ltr）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.dualPageMode, DualPageMode.auto);
    expect(pdfView.dualPageCoverAlone, isTrue);
    expect(pdfView.dualPageDirection, DualPageDirection.ltr);
  });
```

- [x] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/reader_screen_test.dart
```

Expected：FAIL——`PdfReaderView.isLandscape`/`dualPageMode` 等欄位目前恆為建構參數預設值（因 `ReaderScreen` 尚未接線），前兩個橫向/直向測試會失敗（`isLandscape` 恆為 `false`，橫向測試斷言 `isTrue` 失敗）；後兩個雙頁欄位測試目前也會失敗（`ReaderScreen` 尚未把 `resolved.dualPageMode` 等傳入）。

- [x] **Step 3：修改 `reader_screen.dart`**

把 `build()`（原第 289-310 行）改為：

```dart
  @override
  Widget build(BuildContext context) {
    final format = detectBookFormat(widget.filePath);
    // 方向偵測（spec.md「方向偵測契約」）：在 build() 中統一偵測，格式無關
    // 共用，不寫死在 PDF 專屬程式碼路徑裡——EPUB 分支（Issue 6）之後會消費
    // 同一個 isLandscape 值。
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return PopScope(
      canPop: !_cropEditModeActive,
      child: Scaffold(
        appBar: _isFixedLayout
            ? null
            : AppBar(
                title: const Text('閱讀器'),
                actions: _buildAppBarActions(format),
              ),
        body: _buildBody(format, isLandscape),
      ),
    );
  }
```

把 `_buildBody`（原第 346-392 行）簽章與內部呼叫改為：

```dart
  Widget _buildBody(BookFormat format, bool isLandscape) {
    if (format == BookFormat.unknown) {
      return const Center(child: Text('不支援的檔案格式'));
    }
    if (_state == _RenderState.error) {
      return Center(
        child: Text(
          _errorMessage ?? '無法載入書籍',
          key: const Key('reader_error_text'),
        ),
      );
    }
    final body = Stack(
      children: [
        if (_resolved != null) _buildNativeView(format, isLandscape),
        if (_isFixedLayout)
          Positioned(
            top: 16,
            left: 16,
            child: ClipOval(
              child: Container(
                color: Colors.black54,
                child: IconButton(
                  key: const Key('reader_fixed_layout_back_button'),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        if (_state == _RenderState.loading)
          const Center(
            key: Key('reader_loading_indicator'),
            child: CircularProgressIndicator(),
          ),
      ],
    );

    return SafeArea(
      child: body,
    );
  }
```

（其餘內容不變，只有方法簽章與 `_buildNativeView(format)` → `_buildNativeView(format, isLandscape)` 這一處呼叫改動。）

把 `_buildNativeView`（原第 394-432 行）簽章與 PDF 分支改為：

```dart
  Widget _buildNativeView(BookFormat format, bool isLandscape) {
    final resolved = _resolved!;
    switch (format) {
      case BookFormat.epub:
        return EpubReaderView(
          filePath: widget.filePath,
          writingMode: resolved.writingMode,
          pageTurnMode: resolved.pageTurnMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
          fontFamily: resolved.fontFamily,
          fontSize: resolved.fontSize,
          fontWeight: resolved.fontWeight,
          lineHeight: resolved.lineHeight,
          paragraphSpacing: resolved.paragraphSpacing,
          pageMargins: resolved.pageMargins,
          textAlign: resolved.textAlign,
          publisherStyles: resolved.publisherStyles,
        );
      case BookFormat.pdf:
        return PdfReaderView(
          filePath: widget.filePath,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          fitMode: resolved.pdfFitMode,
          contrast: resolved.pdfContrast,
          brightness: resolved.pdfBrightness,
          boldStrength: resolved.pdfBoldStrength,
          cropMode: resolved.pdfCropMode,
          cropRect: resolved.pdfCropRect,
          onCropRectComputed: _handleCropRectComputed,
          cropEditModeActive: _cropEditModeActive,
          onCropRectSelected: _handleCropRectSelected,
          dualPageMode: resolved.dualPageMode,
          dualPageCoverAlone: resolved.dualPageCoverAlone,
          dualPageDirection: resolved.dualPageDirection,
          isLandscape: isLandscape,
        );
      case BookFormat.unknown:
        return const SizedBox.shrink();
    }
  }
```

- [x] **Step 4：執行測試，確認通過**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：全數 PASS。

- [x] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected："No issues found!"

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-16): ReaderScreen 新增 isLandscape 方向偵測並接線至 PdfReaderView"
```

---

### Task 4：`PdfSettingsSheet` 新增「雙頁模式」三態控制項

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`
- Test: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes：`BookReaderPrefs.dualPageMode`（Issue 2）
- Produces：「顯示」分頁新增「雙頁模式」三態選項（`Key('pdf_settings_dual_page_mode_auto'/'always'/'never')`），點擊觸發 `onChanged` 回傳更新後的 `BookReaderPrefs`；`dualPageCoverAlone`/`dualPageDirection` 原樣透傳（本 issue 不提供 UI 控制，UI 控制留給 Issue 4）

- [x] **Step 1：撰寫失敗測試——擴充 `pdf_settings_sheet_test.dart`**

在 `app/test/screens/pdf_settings_sheet_test.dart` 開頭 import 區塊，`import 'package:elinkbook/reader/book_reader_prefs.dart';` 之後新增：

```dart
import 'package:elinkbook/reader/dual_page_mode.dart';
```

在檔案最後一個測試（`'prefs.pdfContrast／pdfBrightness 為 null 時，滑桿顯示預設值 0'`……不，應插在最後一個 `test(...)` 區塊，即「已持久化 pdfCropRect 時，調整其他分頁的滑桿不會清空 pdfCropRect（關鍵回歸檢查）」）之後、`}`（`main()` 結尾）之前，新增以下 5 個測試：

```dart
  testWidgets('顯示分頁新增雙頁模式三個選項按鈕', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byKey(const Key('pdf_settings_dual_page_mode_auto')),
        findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_dual_page_mode_always')),
        findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_dual_page_mode_never')),
        findsOneWidget);
  });

  testWidgets('點擊永遠雙頁選項後，onChanged 帶入 dualPageMode=always',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester.tap(find.byKey(const Key('pdf_settings_dual_page_mode_always')));
    await tester.pump();

    expect(notified?.dualPageMode, DualPageMode.always);
  });

  testWidgets('點擊永遠單頁選項後，onChanged 帶入 dualPageMode=never',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(dualPageMode: DualPageMode.always),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_dual_page_mode_never')));
    await tester.pump();

    expect(notified?.dualPageMode, DualPageMode.never);
  });

  testWidgets('prefs.dualPageMode 為 null 時（未持久化過），不因為初始 build 就觸發 onChanged',
      (tester) async {
    var callCount = 0;
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) => callCount++);

    expect(callCount, 0);
  });

  testWidgets(
      '已持久化 dualPageMode 時，調整濾鏡分頁不會清空 dualPageMode（回歸檢查）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        dualPageMode: DualPageMode.always,
        pdfContrast: 0,
      ),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();

    expect(notified?.pdfContrast, greaterThan(0));
    expect(notified?.dualPageMode, DualPageMode.always); // 關鍵斷言：未被清空
  });
```

- [x] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/pdf_settings_sheet_test.dart
```

Expected：FAIL——找不到 `Key('pdf_settings_dual_page_mode_auto'/'always'/'never')`；`notified?.dualPageMode` 恆為 `null`。

- [x] **Step 3：修改 `pdf_settings_sheet.dart`**

把 import 區塊（第 1-6 行）改為：

```dart
import 'package:flutter/material.dart';

import '../reader/book_reader_prefs.dart';
import '../reader/dual_page_mode.dart';
import '../reader/pdf_fit_mode.dart';
import '../reader/pdf_crop_mode.dart';
```

在 State 欄位宣告（原第 37-42 行），`late PdfCropMode _cropMode;` 之後新增：

```dart
  late DualPageMode _dualPageMode;
```

`initState()`（原第 44-53 行）在 `_cropMode = widget.prefs.pdfCropMode ?? PdfCropMode.none;` 之後新增：

```dart
    _dualPageMode = widget.prefs.dualPageMode ?? DualPageMode.auto;
```

`_notifyChanged()`（原第 61-74 行）改為：

```dart
  void _notifyChanged() {
    widget.onChanged(BookReaderPrefs(
      pdfFitMode: _fitMode,
      pdfContrast: _contrast,
      pdfBrightness: _brightness,
      pdfBoldStrength: _boldStrength / 100,
      pdfCropMode: _cropMode,
      // pdfCropRect 由原生端計算、透過 ReaderScreen.onCropRectComputed
      // 另一條路徑寫入，本分頁不直接控制，但必須原樣帶回。
      pdfCropRect: widget.prefs.pdfCropRect,
      dualPageMode: _dualPageMode,
      // dualPageCoverAlone／dualPageDirection 的 UI 控制項留給 Issue 4
      // （見 docs/epics/epic-16-dual-page/issues.md），本分頁尚未追蹤這兩個
      // 欄位的本地狀態，原樣帶回既有值，避免使用者調整雙頁模式或其他分頁時
      // 被靜默清空。
      dualPageCoverAlone: widget.prefs.dualPageCoverAlone,
      dualPageDirection: widget.prefs.dualPageDirection,
    ));
  }
```

`_buildDisplayTab()`（原第 115-148 行）改為：

```dart
  Widget _buildDisplayTab(BuildContext context) {
    const fitOptions = [
      (PdfFitMode.pageFit, 'page_fit', Icons.fit_screen, 'Page-fit（整頁）'),
      (PdfFitMode.fitWidth, 'fit_width', Icons.swap_horiz, 'Fit Width（頁寬）'),
      (PdfFitMode.actualSize, 'actual_size', Icons.crop_original, '真實比例 1:1'),
    ];
    const dualPageOptions = [
      (DualPageMode.auto, 'auto', Icons.stay_current_landscape, '自動（橫向雙頁）'),
      (DualPageMode.always, 'always', Icons.view_column, '永遠雙頁'),
      (DualPageMode.never, 'never', Icons.crop_portrait, '永遠單頁'),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fit 模式'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: fitOptions.map((option) {
              final (mode, keySuffix, icon, tooltip) = option;
              final selected = _fitMode == mode;
              return IconButton(
                key: Key('pdf_settings_fit_mode_$keySuffix'),
                icon: Icon(icon),
                tooltip: tooltip,
                color: selected ? Theme.of(context).colorScheme.primary : null,
                onPressed: () => setState(() {
                  _fitMode = mode;
                  _notifyChanged();
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text('雙頁模式'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: dualPageOptions.map((option) {
              final (mode, keySuffix, icon, tooltip) = option;
              final selected = _dualPageMode == mode;
              return IconButton(
                key: Key('pdf_settings_dual_page_mode_$keySuffix'),
                icon: Icon(icon),
                tooltip: tooltip,
                color: selected ? Theme.of(context).colorScheme.primary : null,
                onPressed: () => setState(() {
                  _dualPageMode = mode;
                  _notifyChanged();
                }),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
```

- [x] **Step 4：執行測試，確認通過**

```bash
flutter test test/screens/pdf_settings_sheet_test.dart
```

Expected：全數 PASS。

- [x] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected："No issues found!"

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-16): PdfSettingsSheet 顯示分頁新增雙頁模式三態控制項"
```

---

### Task 5：`PdfReaderView.kt` — `DualPageMode`/`DualPageDirection` 列舉 + 純函式（JVM 單元測試）

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Test: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt`

**Interfaces:**
- Consumes：無（本 task 是原生端的起始工作）
- Produces：`PdfReaderView.DualPageMode`（`AUTO`/`ALWAYS`/`NEVER`，含 `fromWireValue`）、`PdfReaderView.DualPageDirection`（`LTR`/`RTL`，含 `fromWireValue`）；`companion object` 純函式 `isDualPageEnabled(dualPageMode, isLandscape, cropEditModeActive): Boolean`、`pairIndices(anchor, direction): Pair<Int, Int>`、`nextPageStep(currentPageIndex, dualPageEnabled, coverAlone): Int`、`previousPageStep(currentPageIndex, dualPageEnabled, coverAlone): Int`，供 Task 6 的 `renderCurrentSpread()`/`nextPage()`/`previousPage()` 呼叫

- [x] **Step 1：撰寫失敗測試——擴充 `PdfReaderViewTest.kt`**

在 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt` 檔案最後一個 `@Test` 函式（`fromWireValue 傳入未知字串時正規化為 NONE...`）之後、`}`（class 結尾）之前，新增以下測試：

```kotlin

    // ---- DualPageMode.fromWireValue ----

    @Test
    fun `DualPageMode fromWireValue 傳入 always 時回傳 ALWAYS`() {
        val mode = PdfReaderView.DualPageMode.fromWireValue("always")
        assertEquals(PdfReaderView.DualPageMode.ALWAYS, mode)
    }

    @Test
    fun `DualPageMode fromWireValue 傳入 never 時回傳 NEVER`() {
        val mode = PdfReaderView.DualPageMode.fromWireValue("never")
        assertEquals(PdfReaderView.DualPageMode.NEVER, mode)
    }

    @Test
    fun `DualPageMode fromWireValue 傳入 auto 時回傳 AUTO`() {
        val mode = PdfReaderView.DualPageMode.fromWireValue("auto")
        assertEquals(PdfReaderView.DualPageMode.AUTO, mode)
    }

    @Test
    fun `DualPageMode fromWireValue 傳入 null 時回傳預設值 AUTO`() {
        val mode = PdfReaderView.DualPageMode.fromWireValue(null)
        assertEquals(PdfReaderView.DualPageMode.AUTO, mode)
    }

    @Test
    fun `DualPageMode fromWireValue 傳入未知字串時回傳預設值 AUTO`() {
        val mode = PdfReaderView.DualPageMode.fromWireValue("unknown-garbage")
        assertEquals(PdfReaderView.DualPageMode.AUTO, mode)
    }

    // ---- DualPageDirection.fromWireValue ----

    @Test
    fun `DualPageDirection fromWireValue 傳入 rtl 時回傳 RTL`() {
        val direction = PdfReaderView.DualPageDirection.fromWireValue("rtl")
        assertEquals(PdfReaderView.DualPageDirection.RTL, direction)
    }

    @Test
    fun `DualPageDirection fromWireValue 傳入 ltr 時回傳 LTR`() {
        val direction = PdfReaderView.DualPageDirection.fromWireValue("ltr")
        assertEquals(PdfReaderView.DualPageDirection.LTR, direction)
    }

    @Test
    fun `DualPageDirection fromWireValue 傳入 null 時回傳預設值 LTR`() {
        val direction = PdfReaderView.DualPageDirection.fromWireValue(null)
        assertEquals(PdfReaderView.DualPageDirection.LTR, direction)
    }

    @Test
    fun `DualPageDirection fromWireValue 傳入未知字串時回傳預設值 LTR`() {
        val direction = PdfReaderView.DualPageDirection.fromWireValue("unknown-garbage")
        assertEquals(PdfReaderView.DualPageDirection.LTR, direction)
    }

    // ---- isDualPageEnabled ----

    @Test
    fun `isDualPageEnabled always 模式一律生效`() {
        val enabled = PdfReaderView.isDualPageEnabled(
            dualPageMode = PdfReaderView.DualPageMode.ALWAYS,
            isLandscape = false,
            cropEditModeActive = false,
        )
        assertEquals(true, enabled)
    }

    @Test
    fun `isDualPageEnabled never 模式一律不生效`() {
        val enabled = PdfReaderView.isDualPageEnabled(
            dualPageMode = PdfReaderView.DualPageMode.NEVER,
            isLandscape = true,
            cropEditModeActive = false,
        )
        assertEquals(false, enabled)
    }

    @Test
    fun `isDualPageEnabled auto 模式橫向時生效`() {
        val enabled = PdfReaderView.isDualPageEnabled(
            dualPageMode = PdfReaderView.DualPageMode.AUTO,
            isLandscape = true,
            cropEditModeActive = false,
        )
        assertEquals(true, enabled)
    }

    @Test
    fun `isDualPageEnabled auto 模式直向時不生效`() {
        val enabled = PdfReaderView.isDualPageEnabled(
            dualPageMode = PdfReaderView.DualPageMode.AUTO,
            isLandscape = false,
            cropEditModeActive = false,
        )
        assertEquals(false, enabled)
    }

    @Test
    fun `isDualPageEnabled 手動裁切編輯模式中一律強制不生效`() {
        val enabled = PdfReaderView.isDualPageEnabled(
            dualPageMode = PdfReaderView.DualPageMode.ALWAYS,
            isLandscape = true,
            cropEditModeActive = true,
        )
        assertEquals(false, enabled)
    }

    // ---- pairIndices ----

    @Test
    fun `pairIndices ltr 方向左頁為 anchor、右頁為 anchor 加 1`() {
        val (left, right) = PdfReaderView.pairIndices(3, PdfReaderView.DualPageDirection.LTR)
        assertEquals(3, left)
        assertEquals(4, right)
    }

    @Test
    fun `pairIndices rtl 方向右頁為 anchor、左頁為 anchor 加 1`() {
        val (left, right) = PdfReaderView.pairIndices(3, PdfReaderView.DualPageDirection.RTL)
        assertEquals(4, left)
        assertEquals(3, right)
    }

    // ---- nextPageStep ----

    @Test
    fun `nextPageStep 雙頁未生效時步進 1`() {
        val step = PdfReaderView.nextPageStep(
            currentPageIndex = 5,
            dualPageEnabled = false,
            coverAlone = true,
        )
        assertEquals(1, step)
    }

    @Test
    fun `nextPageStep 雙頁生效且目前在封面且封面獨立開啟時步進 1`() {
        val step = PdfReaderView.nextPageStep(
            currentPageIndex = 0,
            dualPageEnabled = true,
            coverAlone = true,
        )
        assertEquals(1, step)
    }

    @Test
    fun `nextPageStep 雙頁生效但封面獨立關閉時，index 0 也步進 2`() {
        val step = PdfReaderView.nextPageStep(
            currentPageIndex = 0,
            dualPageEnabled = true,
            coverAlone = false,
        )
        assertEquals(2, step)
    }

    @Test
    fun `nextPageStep 雙頁生效且非封面情境時步進 2`() {
        val step = PdfReaderView.nextPageStep(
            currentPageIndex = 3,
            dualPageEnabled = true,
            coverAlone = true,
        )
        assertEquals(2, step)
    }

    // ---- previousPageStep（C-4 對稱規則）----

    @Test
    fun `previousPageStep 雙頁未生效時步進 1`() {
        val step = PdfReaderView.previousPageStep(
            currentPageIndex = 5,
            dualPageEnabled = false,
            coverAlone = true,
        )
        assertEquals(1, step)
    }

    @Test
    fun `previousPageStep 雙頁生效且目前在 spread 1,2 且封面獨立開啟時步進 1（回到封面）`() {
        val step = PdfReaderView.previousPageStep(
            currentPageIndex = 1,
            dualPageEnabled = true,
            coverAlone = true,
        )
        assertEquals(1, step)
    }

    @Test
    fun `previousPageStep 雙頁生效但封面獨立關閉時，index 1 也步進 2`() {
        val step = PdfReaderView.previousPageStep(
            currentPageIndex = 1,
            dualPageEnabled = true,
            coverAlone = false,
        )
        assertEquals(2, step)
    }

    @Test
    fun `previousPageStep 雙頁生效且非回封面情境時步進 2`() {
        val step = PdfReaderView.previousPageStep(
            currentPageIndex = 5,
            dualPageEnabled = true,
            coverAlone = true,
        )
        assertEquals(2, step)
    }
```

- [x] **Step 2：執行測試，確認失敗**

```bash
cd app/android
./gradlew :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfReaderViewTest"
```

Expected：編譯失敗——`PdfReaderView.DualPageMode`/`DualPageDirection`/`isDualPageEnabled`/`pairIndices`/`nextPageStep`/`previousPageStep` 尚不存在。

- [x] **Step 3：修改 `PdfReaderView.kt`——新增列舉與 companion object 純函式**

在巢狀列舉 `PdfCropMode`（原第 121-144 行）的結尾 `}` 之後、`init {`（原第 146 行）之前，新增：

```kotlin

    /**
     * 橫向雙頁顯示觸發模式（FR-41，epic-16-dual-page），對應 Dart
     * DualPageMode 列舉（`app/lib/reader/dual_page_mode.dart`）透過
     * Method Channel 傳來的 `.name` 字串（'auto'／'always'／'never'）。
     */
    internal enum class DualPageMode {
        AUTO, ALWAYS, NEVER;

        companion object {
            /** 未知或非 String 的原始值一律正規化為 [AUTO]（預設），與
             * BookReaderPrefs.dualPageMode 為 null 時的既有語意一致。*/
            fun fromWireValue(value: String?): DualPageMode = when (value) {
                "always" -> ALWAYS
                "never" -> NEVER
                else -> AUTO
            }
        }
    }

    /**
     * PDF 雙頁顯示的頁面配對閱讀方向（FR-41），對應 Dart DualPageDirection
     * 列舉（`app/lib/reader/dual_page_direction.dart`）透過 Method Channel
     * 傳來的 `.name` 字串（'ltr'／'rtl'）。
     */
    internal enum class DualPageDirection {
        LTR, RTL;

        companion object {
            /** 未知或非 String 的原始值一律正規化為 [LTR]（預設），與
             * BookReaderPrefs.dualPageDirection 為 null 時的既有語意一致。*/
            fun fromWireValue(value: String?): DualPageDirection = when (value) {
                "rtl" -> RTL
                else -> LTR
            }
        }
    }

    companion object {
        /**
         * 雙頁顯示是否應該生效（spec.md renderCurrentSpread() 步驟 1）：
         * `always` 一律生效；`auto` 僅在橫向時生效；`never` 一律不生效；
         * 手動裁切編輯模式中一律強制視為不生效（spec.md I-8）。抽成
         * internal 純函式（不依賴任何 Android View/Bitmap），可脫離真機
         * 直接以 JVM 單元測試涵蓋——本 epic 技術風險最高的 C-4 對稱規則
         * 即靠這組純函式把邏輯與必須真機驗證的像素渲染切開。
         */
        internal fun isDualPageEnabled(
            dualPageMode: DualPageMode,
            isLandscape: Boolean,
            cropEditModeActive: Boolean,
        ): Boolean {
            if (cropEditModeActive) return false
            return dualPageMode == DualPageMode.ALWAYS ||
                (dualPageMode == DualPageMode.AUTO && isLandscape)
        }

        /**
         * 依 [direction] 決定 spread 左右頁的 index 配對（spec.md
         * renderCurrentSpread() 步驟 3）：[anchor] 是目前的
         * currentPageIndex；`ltr` 時左頁＝anchor、右頁＝anchor+1，`rtl`
         * 時左右對調。回傳 Pair(leftIndex, rightIndex)，呼叫端仍需自行
         * 檢查各 index 是否落在 `0 until totalPages` 範圍內（超出範圍的
         * 一側以白色背景留白）。
         */
        internal fun pairIndices(anchor: Int, direction: DualPageDirection): Pair<Int, Int> =
            if (direction == DualPageDirection.RTL) {
                Pair(anchor + 1, anchor)
            } else {
                Pair(anchor, anchor + 1)
            }

        /**
         * 雙頁模式生效時，`nextPage()` 的翻頁步進量（審查修正 C-4）：目前
         * 顯示第 0 頁封面且 [coverAlone] 開啟時步進 1（跳到 spread
         * `[1,2]`），其餘情境步進 2；雙頁未生效時維持既有單頁步進 1。
         */
        internal fun nextPageStep(
            currentPageIndex: Int,
            dualPageEnabled: Boolean,
            coverAlone: Boolean,
        ): Int {
            if (!dualPageEnabled) return 1
            return if (currentPageIndex == 0 && coverAlone) 1 else 2
        }

        /**
         * 雙頁模式生效時，`previousPage()` 的翻頁步進量（審查修正 C-4，
         * 後退到封面的對稱規則）：目前 spread 左頁 index 為 1 且
         * [coverAlone] 開啟時（即目前在 `[1,2]`）步進 1（回到封面
         * index 0），其餘情境步進 2；雙頁未生效時維持既有單頁步進 1。
         * 呼叫端仍須確認 `currentPageIndex - step >= 0` 才可實際翻頁，
         * 避免對負數 index 呼叫 `openPage()`。
         */
        internal fun previousPageStep(
            currentPageIndex: Int,
            dualPageEnabled: Boolean,
            coverAlone: Boolean,
        ): Int {
            if (!dualPageEnabled) return 1
            return if (currentPageIndex == 1 && coverAlone) 1 else 2
        }
    }
```

- [x] **Step 4：執行測試，確認通過**

```bash
./gradlew :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfReaderViewTest"
```

Expected：`BUILD SUCCESSFUL`，全數新增測試皆通過。

- [x] **Step 5：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt
git commit -m "feat(epic-16): PdfReaderView.kt 新增 DualPageMode/DualPageDirection 列舉與雙頁純函式（JVM 測試）"
```

---

### Task 6：`PdfReaderView.kt` — `renderCurrentSpread()` 完整演算法實作

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`

**Interfaces:**
- Consumes：Task 5 的 `DualPageMode`/`DualPageDirection`/`isDualPageEnabled`/`pairIndices`/`nextPageStep`/`previousPageStep`；Task 2 的 Method Channel 契約（`dualPageMode`/`dualPageCoverAlone`/`dualPageDirection`/`isLandscape` 皆非 null）
- Produces：`renderCurrentSpread()`（取代 `renderCurrentPage()`，5 處呼叫點同步改名）完整實作 spec.md 步驟 1-6，拼接階段 OOM 時防禦性 `recycle()` 已配置的半頁點陣圖避免記憶體洩漏；`private val dualPageEnabled` 計算屬性供 `renderCurrentSpread()`/`nextPage()`/`previousPage()` 三處共用；`nextPage()`/`previousPage()` 改用 Task 5 的步進純函式；供 Task 7 的 `integration_test` 驗證

本 task 不需要 Dart 測試（不涉及 Method Channel 契約異動，Task 2 已涵蓋），原生渲染正確性由 Task 7 的 `integration_test` 把關（比照 `PdfImageProcessor`/`EpubFxlScaler` 既有慣例：像素級渲染邏輯無法脫離真機做自動化單元測試）。

- [x] **Step 1：新增 `Bitmap` import**

把檔案開頭 import 區塊（第 1-14 行）改為：

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File
```

- [x] **Step 2：新增雙頁/橫向狀態欄位 + `dualPageEnabled` 共用計算屬性**

在 `private var cropOverlayView: CropOverlayView? = null`（原第 88 行）之後新增：

```kotlin

    // 解析自 Dart DualPageMode.name 字串，預設 AUTO，與
    // BookReaderPrefs.dualPageMode 為 null 時的語意一致（epic-16-dual-page）。
    private var dualPageMode: DualPageMode = DualPageMode.AUTO

    // 封面是否獨立單頁顯示（FR-41），預設 true，與
    // BookReaderPrefs.dualPageCoverAlone 為 null 時的語意一致。
    private var dualPageCoverAlone: Boolean = true

    // 解析自 Dart DualPageDirection.name 字串，預設 LTR，與
    // BookReaderPrefs.dualPageDirection 為 null 時的語意一致。
    private var dualPageDirection: DualPageDirection = DualPageDirection.LTR

    // 目前裝置是否為橫向（ReaderScreen 透過 MediaQuery 偵測後下傳，見
    // spec.md「方向偵測契約」），預設 false（直向）。
    private var isLandscape: Boolean = false

    // 依目前 dualPageMode／isLandscape／cropEditModeActive 三個狀態欄位算出
    // 「雙頁顯示現在是否生效」，供 renderCurrentSpread()／nextPage()／
    // previousPage() 三處共用，避免各自重複呼叫同一組參數（Task 5 的
    // companion object 函式 isDualPageEnabled(...)）。刻意取名
    // dualPageEnabled（而非與 companion 函式同名的 isDualPageEnabled）
    // ——雖然 Kotlin 允許屬性與函式同名並依呼叫語法消歧義，但同名容易讓
    // 之後的維護者誤讀，取不同名稱更清楚。
    private val dualPageEnabled: Boolean
        get() = isDualPageEnabled(dualPageMode, isLandscape, cropEditModeActive)
```

- [x] **Step 3：`setPdfPreferences()` 新增雙頁欄位解析**

把 `setPdfPreferences()`（原第 193-217 行）改為：

```kotlin
    private fun setPdfPreferences(preferences: Map<String, Any?>?) {
        if (preferences == null) return
        (preferences["fitMode"] as? String)?.let { fitMode = PdfFitMode.fromWireValue(it) }
        (preferences["contrast"] as? Number)?.let { contrast = it.toFloat() }
        (preferences["brightness"] as? Number)?.let { brightness = it.toFloat() }
        val boldChanged = (preferences["boldStrength"] as? Number)?.let {
            val newValue = it.toFloat()
            val changed = newValue != boldStrength
            boldStrength = newValue
            changed
        } ?: false
        val cropChanged = (preferences["cropMode"] as? String)?.let {
            val newValue = PdfCropMode.fromWireValue(it)
            val changed = newValue != cropMode
            cropMode = newValue
            changed
        } ?: false
        parseCropRect(preferences["cropRect"])?.let { cropRect = it }
        val dualPageChanged = applyDualPagePreferences(preferences)
        if (boldChanged || cropChanged || dualPageChanged) {
            renderCurrentSpread()
        } else {
            applyFitMode()
            applyFilters()
        }
    }

    /**
     * 解析 [preferences] 中的雙頁／橫向相關欄位並更新對應欄位，回傳是否有
     * 任一欄位實際改變（供 setPdfPreferences 判斷是否需要完整重新渲染
     * spread，而非僅重套用 fit/濾鏡顯示層）。
     */
    private fun applyDualPagePreferences(preferences: Map<String, Any?>): Boolean {
        var changed = false
        (preferences["dualPageMode"] as? String)?.let {
            val newValue = DualPageMode.fromWireValue(it)
            if (newValue != dualPageMode) changed = true
            dualPageMode = newValue
        }
        (preferences["dualPageCoverAlone"] as? Boolean)?.let {
            if (it != dualPageCoverAlone) changed = true
            dualPageCoverAlone = it
        }
        (preferences["dualPageDirection"] as? String)?.let {
            val newValue = DualPageDirection.fromWireValue(it)
            if (newValue != dualPageDirection) changed = true
            dualPageDirection = newValue
        }
        (preferences["isLandscape"] as? Boolean)?.let {
            if (it != isLandscape) changed = true
            isLandscape = it
        }
        return changed
    }
```

- [x] **Step 4：`openBook()` 解析雙頁欄位 + 改呼叫 `renderCurrentSpread()`**

把 `openBook()`（原第 231-263 行）改為：

```kotlin
    private fun openBook(path: String?, initialPreferences: Map<String, Any?>?) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = PdfFitMode.fromWireValue(it) }
        (initialPreferences?.get("contrast") as? Number)?.let { contrast = it.toFloat() }
        (initialPreferences?.get("brightness") as? Number)?.let { brightness = it.toFloat() }
        (initialPreferences?.get("boldStrength") as? Number)?.let { boldStrength = it.toFloat() }
        (initialPreferences?.get("cropMode") as? String)?.let { cropMode = PdfCropMode.fromWireValue(it) }
        parseCropRect(initialPreferences?.get("cropRect"))?.let { cropRect = it }
        if (initialPreferences != null) applyDualPagePreferences(initialPreferences)
        var pfd: ParcelFileDescriptor? = null
        try {
            pfd = openParcelFileDescriptor(path)
            if (pfd == null) {
                channel.invokeMethod("onError", "找不到檔案或檔案已損毀：$path")
                return
            }
            renderer = PdfRenderer(pfd)
            totalPages = renderer!!.pageCount
            currentPageIndex = 0
            renderCurrentSpread()
            channel.invokeMethod("onPageRendered", null)
        } catch (e: OutOfMemoryError) {
            channel.invokeMethod("onError", "記憶體不足，無法載入 PDF 檔案")
        } catch (e: Exception) {
            channel.invokeMethod("onError", e.message ?: "無法載入 PDF 檔案")
        } finally {
            // 確保任何情況下（含上方例外拋出時）原生資源都會被釋放，避免
            // 檔案描述符/渲染器洩漏。
            try { pfd?.close() } catch (ignored: Exception) {}
        }
    }
```

- [x] **Step 5：以 `renderCurrentSpread()` 及其輔助函式取代 `renderCurrentPage()`**

把整個 `renderCurrentPage()` 方法（原第 265-340 行，從 `private fun renderCurrentPage() {` 到緊接在其後、`enterCropEditMode()` 之前的結尾 `}`）替換為以下 6 個方法：

```kotlin
    /**
     * PDF 雙頁渲染的統一入口（spec.md「模組」段落 `renderCurrentSpread()`
     * 演算法步驟 1-6）：依目前雙頁生效判斷與封面獨立設定，分派到單頁
     * （[renderSingleSpread]）或雙頁拼接路徑；拼接階段 OutOfMemoryError
     * 時回退為單頁（步驟 5）。
     */
    private fun renderCurrentSpread() {
        if (renderer == null) return
        val coverAlone = dualPageCoverAlone && currentPageIndex == 0
        if (!dualPageEnabled || coverAlone) {
            renderSingleSpread(currentPageIndex)
            return
        }
        // leftBitmap／rightBitmap 宣告在 try 區塊之外（而非直接用 val 綁在
        // try 內部），是為了讓 catch 區塊也能存取到「渲染到一半、已成功
        // 配置」的半頁點陣圖——若 leftBitmap 配置成功後，緊接著渲染
        // rightBitmap 或 stitchBitmaps() 拼接才拋出 OutOfMemoryError，
        // leftBitmap 若無法在 catch 中被 recycle()，會在 Java heap 永久
        // 洩漏，使緊接著的單頁 OOM 回退因記憶體更緊繃而更容易再次失敗
        // （`/superpowers:requesting-code-review` 對本計劃的審查意見 Finding 1）。
        var leftBitmap: Bitmap? = null
        var rightBitmap: Bitmap? = null
        try {
            val (leftIndex, rightIndex) = pairIndices(currentPageIndex, dualPageDirection)
            leftBitmap = if (leftIndex in 0 until totalPages) renderPageBitmap(leftIndex) else null
            rightBitmap = if (rightIndex in 0 until totalPages) renderPageBitmap(rightIndex) else null
            val stitched = stitchBitmaps(leftBitmap, rightBitmap)
            displayFinalBitmap(stitched)
        } catch (e: OutOfMemoryError) {
            // 拼接階段記憶體不足，依 spec.md 步驟 5 回退為只渲染
            // currentPageIndex 單頁（不進行拼接），onPageChanged 仍回報
            // currentPageIndex（呼叫端 nextPage()/previousPage() 負責）。
            // 防禦性釋放任何已成功配置的半頁點陣圖，避免記憶體洩漏。
            leftBitmap?.recycle()
            rightBitmap?.recycle()
            renderSingleSpread(currentPageIndex)
        }
    }

    /**
     * 單頁渲染路徑：雙頁未生效、封面獨立顯示、或雙頁拼接 OOM 回退時皆走
     * 這條路徑。OOM 回退邏輯沿用抽離前既有行為（原始未縮放尺寸重繪），
     * 非本次新增。
     */
    private fun renderSingleSpread(pageIndex: Int) {
        try {
            val bitmap = renderPageBitmap(pageIndex)
            displayFinalBitmap(bitmap)
        } catch (e: OutOfMemoryError) {
            try {
                val page = renderer!!.openPage(pageIndex)
                val fallbackBitmap = PdfImageProcessor.createOpaqueWhiteBitmap(page.width, page.height)
                page.render(fallbackBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                page.close()
                imageView.setImageBitmap(fallbackBitmap)
                applyFitMode()
                applyFilters()
            } catch (ignored: Exception) {}
        }
    }

    /**
     * 渲染單一頁面（套用目前 [cropMode]/[cropRect] 與縮放係數），回傳未經
     * 加粗/fit/濾鏡處理的原始點陣圖——加粗/fit/濾鏡統一由
     * [displayFinalBitmap] 在拼接（或單頁）完成後套用一次（spec.md 步驟
     * 6）。智慧自動裁切偵測只在 [pageIndex] 為目前的 currentPageIndex（即
     * spread 錨點頁）時觸發一次（spec.md 步驟 1：「以單頁當前頁進行邊界
     * 偵測」），不論該頁最終落在 spread 的左側或右側。
     */
    private fun renderPageBitmap(pageIndex: Int): Bitmap {
        val page = renderer!!.openPage(pageIndex)
        try {
            if (cropMode == PdfCropMode.AUTO_DETECT && cropRect == null && pageIndex == currentPageIndex) {
                val detectBitmap = PdfImageProcessor.createOpaqueWhiteBitmap(page.width, page.height)
                page.render(detectBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                val detected = PdfImageProcessor.detectCropRect(detectBitmap)
                detectBitmap.recycle()
                cropRect = detected
                channel.invokeMethod(
                    "onCropRectComputed",
                    mapOf(
                        "left" to detected.left.toDouble(),
                        "top" to detected.top.toDouble(),
                        "right" to detected.right.toDouble(),
                        "bottom" to detected.bottom.toDouble(),
                    ),
                )
            }

            val density = context.resources.displayMetrics.density
            val scale = PdfImageProcessor.pageRenderScale(density)

            val effectiveCrop = if (cropMode != PdfCropMode.NONE) cropRect else null
            val renderLeft: Float
            val renderTop: Float
            val renderWidth: Float
            val renderHeight: Float
            if (effectiveCrop != null) {
                renderLeft = effectiveCrop.left * page.width
                renderTop = effectiveCrop.top * page.height
                renderWidth = (effectiveCrop.right - effectiveCrop.left) * page.width
                renderHeight = (effectiveCrop.bottom - effectiveCrop.top) * page.height
            } else {
                renderLeft = 0f
                renderTop = 0f
                renderWidth = page.width.toFloat()
                renderHeight = page.height.toFloat()
            }

            val width = (renderWidth * scale).toInt().coerceAtLeast(1)
            val height = (renderHeight * scale).toInt().coerceAtLeast(1)
            val bitmap = PdfImageProcessor.createOpaqueWhiteBitmap(width, height)
            val matrix = android.graphics.Matrix().apply {
                // 先把裁切區域的左上角平移到原點，再統一縮放——順序不可
                // 顛倒。effectiveCrop 為 null 時 renderLeft/renderTop 皆為
                // 0，退化為既有（無裁切）行為。
                postTranslate(-renderLeft, -renderTop)
                postScale(scale, scale)
            }
            page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            return bitmap
        } finally {
            page.close()
        }
    }

    /**
     * 把 [left]／[right] 兩個點陣圖橫向無縫拼接成一張大點陣圖（spec.md
     * 步驟 4，FR-41「不留空白」）：拼接後寬度恆等於左右兩頁寬度之和，
     * 不含任何額外留白像素。其中一側為 null 時（另一側超出總頁數，spec.md
     * 步驟 3「超出總頁數側留白」）以白色背景填充，尺寸比照有內容的一側
     * （呼叫端已保證 [left]/[right] 至少有一側非 null，因為其中一側必為
     * currentPageIndex 本身，恆落在 `0 until totalPages` 範圍內）。
     */
    private fun stitchBitmaps(left: Bitmap?, right: Bitmap?): Bitmap {
        val reference = left ?: right!!
        val leftBmp = left ?: PdfImageProcessor.createOpaqueWhiteBitmap(reference.width, reference.height)
        val rightBmp = right ?: PdfImageProcessor.createOpaqueWhiteBitmap(reference.width, reference.height)
        val width = leftBmp.width + rightBmp.width
        val height = maxOf(leftBmp.height, rightBmp.height)
        val canvasBitmap = PdfImageProcessor.createOpaqueWhiteBitmap(width, height)
        val canvas = android.graphics.Canvas(canvasBitmap)
        canvas.drawBitmap(leftBmp, 0f, 0f, null)
        canvas.drawBitmap(rightBmp, leftBmp.width.toFloat(), 0f, null)
        // 拼接完成後兩個半頁點陣圖已無用途，優先釋放以降低雙頁拼接的記憶體
        // 峰值（正是最容易觸發 OOM 的階段，見 spec.md「已知限制」）。
        leftBmp.recycle()
        rightBmp.recycle()
        return canvasBitmap
    }

    /**
     * 拼接（或單頁）完成後統一套用加粗濾鏡、imageView 的 fit 模式與
     * 對比度/亮度濾鏡（spec.md 步驟 6）。
     */
    private fun displayFinalBitmap(bitmap: Bitmap) {
        val finalBitmap = if (boldStrength > 0f) PdfImageProcessor.applyBoldEffect(bitmap, boldStrength) else bitmap
        imageView.setImageBitmap(finalBitmap)
        applyFitMode()
        applyFilters()
    }
```

- [x] **Step 6：`exitCropEditMode()` 改呼叫 `renderCurrentSpread()`**

把 `exitCropEditMode()`（原第 411-416 行）內的 `renderCurrentPage()` 改為 `renderCurrentSpread()`：

```kotlin
    private fun exitCropEditMode() {
        cropEditModeActive = false
        cropOverlayView?.let { rootView.removeView(it) }
        cropOverlayView = null
        renderCurrentSpread()
    }
```

- [x] **Step 7：`nextPage()`/`previousPage()` 改用步進純函式（C-4 對稱規則）**

把 `nextPage()`/`previousPage()`（原第 510-526 行）改為：

```kotlin
    private fun nextPage() {
        if (cropEditModeActive) return
        val step = nextPageStep(currentPageIndex, dualPageEnabled, dualPageCoverAlone)
        val newIndex = currentPageIndex + step
        if (newIndex < totalPages) {
            currentPageIndex = newIndex
            renderCurrentSpread()
            channel.invokeMethod("onPageChanged", currentPageIndex)
        }
    }

    private fun previousPage() {
        if (cropEditModeActive) return
        val step = previousPageStep(currentPageIndex, dualPageEnabled, dualPageCoverAlone)
        val newIndex = currentPageIndex - step
        if (newIndex >= 0) {
            currentPageIndex = newIndex
            renderCurrentSpread()
            channel.invokeMethod("onPageChanged", currentPageIndex)
        }
    }
```

- [x] **Step 8：JVM 單元測試回歸 + 編譯檢查**

```bash
cd app/android
./gradlew :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfReaderViewTest"
./gradlew :app:compileDebugKotlin
```

Expected：`BUILD SUCCESSFUL`（Task 5 的純函式測試不受影響；`compileDebugKotlin` 確認新增的 `renderCurrentSpread()` 等方法編譯無誤，無法在此階段以自動化測試涵蓋像素渲染正確性，留給 Task 7）。

- [x] **Step 9：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt
git commit -m "feat(epic-16): PdfReaderView.kt renderCurrentSpread() 完整雙頁演算法（拼接/OOM回退/C-4翻頁步進）"
```

---

### Task 7：雙頁測試 PDF Fixture + `integration_test` 真機驗證

**Files:**
- Create: `app/test/fixtures/sample_dual_page.pdf`
- Create: `app/integration_test/pdf_dual_page_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `PdfReaderView` 建構參數／Task 6 的 `renderCurrentSpread()`/`nextPage()`/`previousPage()` 行為
- Produces：真機可驗證的雙頁分頁行為回歸測試

**已知測試限制**：拼接後點陣圖「頁間無可見間距」（FR-41 核心驗收點）與拼接 OOM 回退的像素級正確性，無法透過 Flutter `integration_test` 直接檢視原生 `ImageView` 的 bitmap 內容（比照本專案既有慣例：PDF 裁切/濾鏡的像素級效果向來也只能透過真機肉眼確認或暫時性原生端 log 交叉核對，見 `tmp/epic-4/reviews/`／`task-6-fix-report.md` 先例，不在自動化 `integration_test` 中做 bitmap 像素比對）。本 task 的 `integration_test` 改以「結構性、可自動化驗證」的方式覆蓋 Issue 3 驗收標準：翻頁步進量（透過 `onPageChanged` 回報值序列）證明雙頁/單頁切換、封面獨立配對、C-4 對稱回退、以及最後一個 spread 落單時不越界不崩潰；FR-41「頁間無可見間距」的真機肉眼/截圖確認，留給 Issue 7（`issues.md` 已將此列為 Issue 7 自己的驗收項目）。

- [x] **Step 1：產生 6 頁測試用 PDF fixture**

以下 Python 腳本已驗證可產生 byte-exact 的 xref 偏移量（比照既有 `app/test/fixtures/sample.pdf` 的手工極簡 PDF 風格，只是頁數從 1 頁擴充為 6 頁、每頁 MediaBox 300×400pt）。在儲存庫根目錄執行：

```bash
py - <<'PYEOF'
def build_pdf(num_pages, width=300, height=400):
    objects = []
    objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    kids = " ".join(f"{3+i} 0 R" for i in range(num_pages))
    objects.append(f"<< /Type /Pages /Kids [{kids}] /Count {num_pages} >>".encode())
    for i in range(num_pages):
        objects.append(
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] /Resources << >> >>".encode()
        )

    header = b"%PDF-1.4\n"
    body = bytearray()
    offsets = [0]
    pos = len(header)
    for idx, obj in enumerate(objects, start=1):
        offsets.append(pos)
        entry = f"{idx} 0 obj\n".encode() + obj + b"\nendobj\n"
        body += entry
        pos += len(entry)

    xref_offset = len(header) + len(body)
    xref = f"xref\n0 {len(objects)+1}\n".encode()
    xref += b"0000000000 65535 f \n"
    for off in offsets[1:]:
        xref += f"{off:010d} 00000 n \n".encode()
    trailer = f"trailer\n<< /Size {len(objects)+1} /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF".encode()

    return header + bytes(body) + xref + trailer

data = build_pdf(6)
with open("app/test/fixtures/sample_dual_page.pdf", "wb") as f:
    f.write(data)
print(len(data), "bytes written")
PYEOF
```

Expected：輸出 `915 bytes written`，並在 `app/test/fixtures/sample_dual_page.pdf` 產生一個 6 頁的最小合法 PDF（每頁 300×400pt，無內容，純測試分頁邏輯用）。

**為何選 6 頁（而非字面上的「奇數」）**：`renderCurrentSpread()` 在 `dualPageCoverAlone=true`（預設）下，配對序列為封面(0) → [1,2] → [3,4] → …，currentPageIndex 錨點永遠落在奇數（1,3,5,…）。當「錨點+1」超出總頁數時才會落單——這在總頁數為**偶數**時發生（例如 6 頁：錨點序列 0,1,3,5，最後 5+1=6 超出範圍，落單）。若總頁數為奇數（例如 7 頁），錨點序列 0,1,3,5，最後 (5,6) 恰好配對整齊、不會落單。`sample_dual_page.pdf` 選用 6 頁，正是為了讓「最後一個 spread 落單」這個場景在預設封面獨立設定下真實發生並可驗證，而非拘泥於「總頁數」本身奇偶的字面敘述。

在 `app/pubspec.yaml` 的 `flutter: assets:` 清單中，確認 `test/fixtures/sample_dual_page.pdf` 是否已被既有的 glob/顯式清單涵蓋（既有 `test/fixtures/sample.pdf` 等檔案已在其中列出或透過目錄涵蓋）；若 `pubspec.yaml` 是逐檔案列出（非目錄 glob），在既有 `- test/fixtures/sample.pdf` 那一行之後新增：

```yaml
    - test/fixtures/sample_dual_page.pdf
```

- [x] **Step 2：撰寫 `integration_test/pdf_dual_page_test.dart`**

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<String> stagePath(String fileName) =>
      _stageAssetAsFile('test/fixtures/sample_dual_page.pdf', fileName);

  /// 建構 [PdfReaderView] 並等待 onPageRendered（原生端非同步開書完成），
  /// 把每次 onPageChanged 回報值收進 [pageChanges]。
  Future<void> pumpAndWaitRendered(
    WidgetTester tester,
    String path,
    List<int> pageChanges, {
    DualPageMode dualPageMode = DualPageMode.auto,
    bool dualPageCoverAlone = true,
    DualPageDirection dualPageDirection = DualPageDirection.ltr,
    bool isLandscape = false,
  }) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          filePath: path,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) => fail('不應觸發 onError：$message'),
          onPageChanged: pageChanges.add,
          dualPageMode: dualPageMode,
          dualPageCoverAlone: dualPageCoverAlone,
          dualPageDirection: dualPageDirection,
          isLandscape: isLandscape,
        ),
      ),
    );
    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('auto 模式橫向：預設封面獨立＋ltr 配對，往後翻步進符合 0→[1,2]→[3,4]',
      (tester) async {
    final path = await stagePath('sample_dual_page_auto.pdf');
    final pageChanges = <int>[];
    await pumpAndWaitRendered(tester, path, pageChanges, isLandscape: true);

    // 第 0 頁封面 -> 往後翻步進 1 到 [1,2]
    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1]);

    // [1,2] -> 再往後翻步進 2 到 [3,4]
    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1, 3]);
  });

  testWidgets('auto 模式橫向：從 [1,2] 往回翻正確回到封面（C-4 對稱規則，不崩潰）',
      (tester) async {
    final path = await stagePath('sample_dual_page_back.pdf');
    final pageChanges = <int>[];
    await pumpAndWaitRendered(tester, path, pageChanges, isLandscape: true);

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1]);

    // 從 [1,2] 往回翻 -> 回到封面 index 0
    await tester.drag(find.byType(PdfReaderView), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1, 0]);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('auto 模式橫向：最後一個 spread 落單時，繼續往後翻不越界、不崩潰',
      (tester) async {
    // sample_dual_page.pdf 共 6 頁：封面(0) -> [1,2] -> [3,4] -> [5] 落單
    // （另一側白色背景留白，見 Step 1「為何選 6 頁」說明）。
    final path = await stagePath('sample_dual_page_dangle.pdf');
    final pageChanges = <int>[];
    await pumpAndWaitRendered(tester, path, pageChanges, isLandscape: true);

    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
      await tester.pumpAndSettle();
    }
    expect(pageChanges, [1, 3, 5]); // 最後落在 index 5（落單）

    // 已達最後一個 spread，再往後翻應為 no-op（不越界、不再觸發 onPageChanged）
    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1, 3, 5]);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('always 模式：即使裝置為直向，仍一律雙頁（步進規則與橫向 auto 相同）',
      (tester) async {
    final path = await stagePath('sample_dual_page_always.pdf');
    final pageChanges = <int>[];
    await pumpAndWaitRendered(
      tester,
      path,
      pageChanges,
      dualPageMode: DualPageMode.always,
      isLandscape: false, // 直向，但 always 仍應強制雙頁
    );

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1]); // 封面 -> 步進 1，證明雙頁已生效

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1, 3]); // 步進 2，確認雙頁持續生效
  });

  testWidgets('never 模式：即使裝置為橫向，仍一律單頁（步進恆為 1）',
      (tester) async {
    final path = await stagePath('sample_dual_page_never.pdf');
    final pageChanges = <int>[];
    await pumpAndWaitRendered(
      tester,
      path,
      pageChanges,
      dualPageMode: DualPageMode.never,
      isLandscape: true, // 橫向，但 never 仍應強制單頁
    );

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1]);

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1, 2]); // 步進恆為 1，而非雙頁的 2
  });

  testWidgets(
      'auto 模式：裝置從橫向轉回直向時，恢復單頁步進（不觸發 onError，preferences 正確傳遞）',
      (tester) async {
    final path = await stagePath('sample_dual_page_rotate.pdf');
    final pageChanges = <int>[];
    final errors = <String>[];
    final completer = Completer<void>();

    Widget buildView(bool isLandscape) => MaterialApp(
          home: PdfReaderView(
            filePath: path,
            onPageRendered: () {
              if (!completer.isCompleted) completer.complete();
            },
            onError: errors.add,
            onPageChanged: pageChanges.add,
            dualPageMode: DualPageMode.auto,
            isLandscape: isLandscape,
          ),
        );

    await tester.pumpWidget(buildView(true)); // 橫向開書
    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1]); // 橫向：雙頁生效，封面步進 1

    // 轉回直向：isLandscape 由 true 變 false，透過 didUpdateWidget 觸發
    // setPdfPreferences。
    await tester.pumpWidget(buildView(false));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pageChanges, [1, 2]); // 直向：單頁步進恢復為 1（index1 -> index2）

    expect(errors, isEmpty,
        reason: '旋轉切換不應觸發 onError；PlatformView 是否因旋轉重建屬 '
            'Issue 7 的真機視覺驗證範圍，本測試只驗證 preferences 傳遞路徑不出錯');
  });
}
```

- [x] **Step 3：於真實裝置執行 integration_test**

```bash
cd app
flutter devices
flutter test integration_test/pdf_dual_page_test.dart -d <device-id>
```

Expected：全數測試通過（真實裝置，`<device-id>` 替換為 `flutter devices` 列出的實際 id）。

- [x] **Step 4：全專案回歸測試 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：`flutter test` 全數 PASS（含 Task 1-4 新增/修改的所有測試，以及既有全部測試不受影響）；`flutter analyze` "No issues found!"。

- [x] **Step 5：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/test/fixtures/sample_dual_page.pdf app/integration_test/pdf_dual_page_test.dart app/pubspec.yaml
git commit -m "test(epic-16): 新增雙頁測試 PDF fixture 與 integration_test 真機驗證"
```

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：`spec.md`「模組」段落對 `ReaderScreen`（方向偵測、Null 預設值解析）、`PdfReaderView`（Dart，4 個新參數）、`PdfReaderView.kt`（`renderCurrentSpread()` 演算法步驟 1-6、翻頁步進 C-4、頁碼回報）、`PdfSettingsSheet`（雙頁模式三態）四個模組異動，皆有對應 Task（1/3、2、5+6、4）；`spec.md`「方向偵測契約」1-3 點由 Task 3 涵蓋（第 4 點「PlatformView 不得因旋轉重建」屬既有 `AndroidManifest.xml` `configChanges` 設定與 Issue 7 真機驗證範圍，本 issue 不重複驗證）；`issues.md` Issue 3 的驗收標準（widget test 三項、`integration_test` 五項）在 Task 1-4（widget test）與 Task 7（`integration_test`）皆有對應覆蓋。
- **無佔位符掃描**：所有步驟皆附完整程式碼、確切檔案路徑與內容，PDF fixture 產生腳本已實際執行驗證 byte-exact 的 xref 偏移量（見 Task 7 Step 1），無 "TODO"/"視情況" 字樣。
- **型別/介面一致性**：`DualPageMode.auto/always/never`（Dart）↔ `DualPageMode.AUTO/ALWAYS/NEVER`（Kotlin，`fromWireValue` 對應）、`DualPageDirection.ltr/rtl` ↔ `LTR/RTL` 全文用法一致；Method Channel wire key 名稱（`dualPageMode`/`dualPageCoverAlone`/`dualPageDirection`/`isLandscape`）在 Task 2（Dart 送出）與 Task 6（Kotlin 解析）逐字一致；`renderCurrentPage()` → `renderCurrentSpread()` 改名涵蓋 spec.md 明訂的 5 處呼叫點（`openBook`／`setPdfPreferences`／`exitCropEditMode`／`nextPage`／`previousPage`，對應 Task 6 Step 4/3/6/7）。
- **額外發現並主動修正的問題**：
  1. `PdfReaderView`（Dart）新增的 4 個雙頁/橫向參數若宣告為 `required`，會導致既有 `pdf_reader_view_test.dart`／`reader_screen_test.dart` 十餘處既有 `PdfReaderView(...)` 建構呼叫全數編譯失敗；改為「non-nullable + 預設值」（比照既有 `cropEditModeActive = false` 慣例），並在 Task 2 中明確列出所有因此需要更新的既有 exact-map 斷言測試，避免遺漏。
  2. Issue 1 驗證報告已確定 EPUB 側 `Spread.AUTO` 不被 Readium 接受、需退回手動切換方案（見 `spec.md`「待驗證風險與收斂關卡」Q2），與本 issue（PDF 專屬）無直接依賴關係，故本計劃未涉及 `EpubReaderView`，符合 `issues.md` Issue 3 範圍邊界。
  3. 「奇數總頁數最後一頁落單」的驗收敘述與 `dualPageCoverAlone=true` 預設下的實際配對算式（錨點恆為奇數）交叉驗算後，落單情境實際發生在總頁數為**偶數**時；已在 Task 7 Step 1 明確記錄此算式推導與 fixture 選用 6 頁的理由，不隱藏此落差。
  4. 原 `renderCurrentPage()` 的智慧自動裁切偵測条件（`cropMode == AUTO_DETECT && cropRect == null`）在拆分出 `renderPageBitmap(pageIndex)` 後，新增 `&& pageIndex == currentPageIndex` 限制，確保雙頁模式下只對 spread 錨點頁觸發一次偵測（spec.md 步驟 1 明文要求），而非對左右兩側各觸發一次；已在 Task 6 Step 5 的程式碼註解中說明。
- **依 `/superpowers:requesting-code-review` 對本計劃的審查修正**（`tmp/epic-16/reviews/review-plan-issue-3.md`）：
  1. **Critical（已修正）**：Task 6 Step 5 `renderCurrentSpread()` 原始寫法把 `leftBitmap`/`rightBitmap` 宣告為 `try` 區塊內的 `val`——若 `leftBitmap` 已成功配置，但緊接著渲染 `rightBitmap` 或 `stitchBitmaps()` 拼接階段才拋出 `OutOfMemoryError`，`leftBitmap` 會因 `catch` 區塊存取不到而永久洩漏，使緊接著的單頁 OOM 回退因記憶體更緊繃而更容易再次失敗。已改為在 `try` 區塊外宣告 `var leftBitmap: Bitmap? = null`/`var rightBitmap: Bitmap? = null`，並在 `catch` 區塊防禦性呼叫 `recycle()`。
  2. **Minor（已採納，並調整命名）**：`isDualPageEnabled(dualPageMode, isLandscape, cropEditModeActive)` 原本在 `renderCurrentSpread()`/`nextPage()`/`previousPage()` 三處各自重複呼叫；已抽成 `private val dualPageEnabled` 計算屬性（Task 6 Step 2）供三處共用。審查建議的屬性名稱與 Task 5 的 companion 函式同名（皆為 `isDualPageEnabled`）——Kotlin 依呼叫語法（`isDualPageEnabled` 屬性讀取 vs. `isDualPageEnabled(a, b, c)` 函式呼叫）可正確消歧義、可編譯，但同名容易讓之後的維護者誤讀，故改用 `dualPageEnabled`（不含 `is` 前綴）以肉眼區分兩者。
