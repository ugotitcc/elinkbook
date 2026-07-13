# Epic 16 Issue 4 — PDF 封面獨立開關 + 閱讀方向（LTR/RTL）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `PdfSettingsSheet` 補齊 Issue 3 原生端已支援、但尚未開放使用者調整的兩個控制項（「封面獨立」開關、「頁面方向」LTR/RTL 二選一），並把 `DualPageDirection` 的全域固定預設值從 `ltr` 改為 `rtl`。

**Architecture:** 沿用 `PdfSettingsSheet` 既有的「本地 State 欄位 + `_notifyChanged()` 組回完整 `BookReaderPrefs` + Wrap/IconButton 或 SwitchListTile 選項列」模式（比照既有 Fit 模式／雙頁模式／裁切模式）。原生端（`PdfReaderView.kt`）與 Method Channel 契約在 Issue 3 已一次到位實作完成，本 issue 純粹是 UI 曝光 + 端到端驗證；唯一涉及原生端的變動是 Task 1 的預設值翻轉（更新內部 fallback 常數與其 KDoc，不影響任何既有行為路徑，因為 `openBook`/`setPdfPreferences` 的 wire map 一律無條件包含 `dualPageDirection` 欄位，原生端這個 fallback 在正常流程中不會被觸發，只在其自身的單元測試中被直接呼叫驗證）。

**Tech Stack:** Flutter/Dart、Kotlin（`PdfReaderView.kt`）、`flutter_test`／`integration_test`（真機）。

## Global Constraints

- **前置狀態（已確認完成，非假設）**：Issue 3（`docs/epics/epic-16-dual-page/plans/plan-issue-3.md`）已完成實作，branch `epic-16/dual-page-issue3`，最新 commit `8a63e68`（`test(epic-16): 整合測試改用 dynamic 呼叫 nextPage/previousPage 以繞過手勢穿透限制`）——`PdfReaderView`（Dart／Kotlin）已支援 `dualPageCoverAlone`／`dualPageDirection` 完整原生渲染邏輯，`BookReaderPrefs`／`ResolvedPreferences`／`ReaderPrefsManagerImpl` 已有對應欄位與 Null 預設值解析。本計劃在此分支（或其合併後的 `main`）上繼續開工。
- **範圍調整（相對 `issues.md` 原始描述的明確變更，已與人類確認）**：`issues.md` Issue 4 原描述「本 issue 不需異動原生端邏輯」——本計劃 **Task 1 是唯一的例外**，範圍是把 `DualPageDirection` 的全域固定預設值從 `ltr` 改為 `rtl`（人類明確決定：維持純手動控制，不新增任何「依書籍排版方向自動偵測」的機制——`WritingMode` 目前完全綁定 Readium `EpubPreferences.verticalText`，是 EPUB 專屬概念，PDF 端沒有任何直排/橫排偵測訊號來源可用，自動偵測需要全新的 PDF 版面分析功能，明顯超出本 issue 範圍）。Task 1 因此需要連動修改 `PdfReaderView.kt` 內部 fallback 常數與 2 個既有 JVM 單元測試，這是唯一觸及原生端的部分；Task 2-3（UI 曝光）與 Task 4-5（整合測試）完全不異動原生端。
- **既有整合測試技巧（Issue 3 建立，Task 4 沿用）**：真機驗證發現 `tester.drag()` 合成手勢與 `adb shell input touchscreen swipe` 真實 OS 觸控，在 Flutter 3.41.9 + Android 15 (API 35) 這個組合下皆無法讓 `AndroidView` 疊加的 `GestureDetector.onHorizontalDragEnd` 觸發（與本專案既有的 `CropOverlayView` 拖曳控制點測試限制同類，診斷過程見 `tmp/epic-16/reviews/review-issue-3-integrated-round2.md`）。`integration_test/pdf_dual_page_test.dart` 已建立繞過手法：`nextPage()`/`previousPage()` 定義在 private 的 `_PdfReaderViewState` 但方法名稱本身無底線前綴，可透過 `(tester.state(find.byType(PdfReaderView)) as dynamic).nextPage()` 動態呼叫繞過手勢層。Task 4 直接沿用該檔案既有的 `_nextPage(tester)`/`_previousPage(tester)` 頂層函式，不重新發明。
- **視覺驗證的既有限制（沿用 Issue 3 precedent，不在本 issue 重複造輪子）**：FR-41「頁間無可見間距」與「畫面左右呈現對調」這類像素/視覺層級的正確性，無法透過 `integration_test` 自動化驗證（無法用程式檢視原生 `ImageView` 的 bitmap 內容），比照 Issue 3 `plan-issue-3.md` Task 7 的既有慣例與 `issues.md` Issue 7 的既定收尾範圍，這類視覺確認留給 Issue 7 的人工真機 QA，本計劃的 `integration_test` 改以「結構性、可自動化驗證」的方式覆蓋（翻頁步進量序列、`BookReaderPrefs` 持久化欄位值）。
- **頁碼索引慣例**：全文 0-indexed（`currentPageIndex` 從 0 起算），沿用 Issue 3 慣例。
- **不得引入的範圍**：不新增任何 PDF 版面方向自動偵測邏輯；不修改 `CropOverlayView`／手動裁切互動（屬 Issue 5 範圍）；不修改 EPUB／`EpubReaderView`（`dualPageDirection` 明確為 PDF 專屬，見 `app/lib/reader/dual_page_direction.dart` 既有 doc comment：「EPUB 固定版面由 Readium 依 `page-progression-direction` metadata 自動處理」）。

---

### Task 1：`DualPageDirection` 全域固定預設值由 `ltr` 改為 `rtl`

**Files:**
- Modify: `app/lib/reader/dual_page_direction.dart`
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Modify: `docs/epics/epic-16-dual-page/spec.md`
- Test: `app/test/reader/reader_prefs_manager_test.dart`
- Test: `app/test/reader/pdf_reader_view_test.dart`
- Test: `app/test/screens/reader_screen_test.dart`
- Test: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt`

**Interfaces:**
- Consumes：Issue 3 既有的 `DualPageDirection` enum、`ReaderPrefsManagerImpl.resolve()`、`PdfReaderView`（Dart／Kotlin）
- Produces：`book.dualPageDirection` 為 `null`（未持久化過）時，`ResolvedPreferences.dualPageDirection` 與 `PdfReaderView` 建構子預設值一律解析為 `DualPageDirection.rtl`（非 `ltr`），供 Task 3 的 `PdfSettingsSheet` 初始狀態與 Task 5 的持久化測試依賴

- [ ] **Step 1：撰寫失敗測試——更新 `reader_prefs_manager_test.dart` 的預設值斷言**

把第 50 行：

```dart
      expect(resolved.dualPageDirection, DualPageDirection.ltr);
```

改為：

```dart
      expect(resolved.dualPageDirection, DualPageDirection.rtl);
```

（此行位於測試 `'全部欄位皆未覆寫時，回傳的 non-null 欄位皆為既存安全預設值'` 內，第 53 行 `'單書覆寫存在時，優先套用單書覆寫，忽略全域預設'` 測試已明確傳入 `dualPageDirection: DualPageDirection.rtl` 並斷言 `resolved.dualPageDirection == DualPageDirection.rtl`，不受本次預設值翻轉影響，不需修改。）

- [ ] **Step 2：撰寫失敗測試——更新 `pdf_reader_view_test.dart` 全部 11 處預設值斷言**

檔案中所有 `'dualPageDirection': 'ltr',`（共 11 處，皆為完全相同的字串與縮排）改為 `'dualPageDirection': 'rtl',`：

```dart
      'dualPageDirection': 'ltr',
```

改為：

```dart
      'dualPageDirection': 'rtl',
```

（`DualPageDirection.rtl` 的 3 處既有明確覆寫測試——測試 `'_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 正確包含非預設的雙頁/橫向欄位'`、`'dualPageCoverAlone／dualPageDirection 變動時，didUpdateWidget 呼叫 setPdfPreferences'`、`'雙頁/橫向欄位皆未變動時，didUpdateWidget 不觸發任何 setPdfPreferences 呼叫'`——原本就明確傳入 `dualPageDirection: DualPageDirection.rtl` 並斷言 wire 值為 `'rtl'`，不受影響、不需修改。）

- [ ] **Step 3：撰寫失敗測試——更新 `reader_screen_test.dart` 的預設值斷言與測試名稱**

把第 497-517 行：

```dart
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

改為：

```dart
  testWidgets(
      '尚未持久化雙頁偏好設定時，PdfReaderView 的雙頁參數採用預設值（auto／true／rtl）',
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
    expect(pdfView.dualPageDirection, DualPageDirection.rtl);
  });
```

（第 467-495 行的 `'開啟該書已有的持久化雙頁偏好設定後...'` 測試已明確持久化 `dualPageDirection: DualPageDirection.rtl` 並斷言讀回 `DualPageDirection.rtl`，不受影響。）

- [ ] **Step 4：執行測試，確認三個檔案的新斷言皆失敗**

```bash
cd app
flutter test test/reader/reader_prefs_manager_test.dart test/reader/pdf_reader_view_test.dart test/screens/reader_screen_test.dart
```

Expected：FAIL——三個檔案的預設值斷言皆因生產程式碼仍回傳/送出 `ltr` 而失敗。

- [ ] **Step 5：修改 `reader_prefs_manager_impl.dart`**

把 `resolve()` 方法尾端：

```dart
      dualPageDirection: book.dualPageDirection ?? DualPageDirection.ltr,
```

改為：

```dart
      dualPageDirection: book.dualPageDirection ?? DualPageDirection.rtl,
```

- [ ] **Step 6：修改 `pdf_reader_view.dart`**

把建構子中：

```dart
    this.dualPageDirection = DualPageDirection.ltr,
```

改為：

```dart
    this.dualPageDirection = DualPageDirection.rtl,
```

- [ ] **Step 7：執行測試，確認通過**

```bash
flutter test test/reader/reader_prefs_manager_test.dart test/reader/pdf_reader_view_test.dart test/screens/reader_screen_test.dart
```

Expected：全數 PASS。

- [ ] **Step 8：更新文件與註解一致性——`dual_page_direction.dart`／`book_reader_prefs.dart`**

把 `app/lib/reader/dual_page_direction.dart` 整份檔案改為：

```dart
/// PDF 雙頁顯示時的頁面配對閱讀方向（FR-41，僅 PDF 適用；EPUB 固定版面
/// 由 Readium 依 `page-progression-direction` metadata 自動處理，見
/// docs/epics/epic-16-dual-page/spec.md「資料模型」）。[ltr] 左到右；
/// [rtl] 右到左（日漫慣例，亦為 elinkBook 全域固定預設值——本專案核心
/// 差異化為直排繁體中文排版支援，見 issues.md Issue 4 的決策記錄）。
enum DualPageDirection { ltr, rtl }
```

把 `app/lib/reader/book_reader_prefs.dart` 第 41 行：

```dart
  final DualPageDirection? dualPageDirection; // null=ltr（僅 PDF 有效）
```

改為：

```dart
  final DualPageDirection? dualPageDirection; // null=rtl（僅 PDF 有效）
```

- [ ] **Step 9：`flutter analyze`，確認乾淨**

```bash
flutter analyze
```

Expected："No issues found!"

- [ ] **Step 10：撰寫失敗測試——更新 `PdfReaderViewTest.kt` 的兩個 fallback 預設值測試**

把 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt` 第 128-138 行：

```kotlin
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
```

改為：

```kotlin
    @Test
    fun `DualPageDirection fromWireValue 傳入 null 時回傳預設值 RTL`() {
        val direction = PdfReaderView.DualPageDirection.fromWireValue(null)
        assertEquals(PdfReaderView.DualPageDirection.RTL, direction)
    }

    @Test
    fun `DualPageDirection fromWireValue 傳入未知字串時回傳預設值 RTL`() {
        val direction = PdfReaderView.DualPageDirection.fromWireValue("unknown-garbage")
        assertEquals(PdfReaderView.DualPageDirection.RTL, direction)
    }
```

（`傳入 rtl 時回傳 RTL`／`傳入 ltr 時回傳 LTR` 兩個測試驗證的是明確傳入值的正確映射，與預設值無關，不需修改。）

- [ ] **Step 11：執行測試，確認失敗**

```bash
cd android
./gradlew :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfReaderViewTest"
```

Expected：兩個新斷言 FAIL（`AssertionError`，實際值仍為 `LTR`）。

- [ ] **Step 12：修改 `PdfReaderView.kt`**

把第 91-101 行：

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
```

改為：

```kotlin
    // 解析自 Dart DualPageMode.name 字串，預設 AUTO，與
    // BookReaderPrefs.dualPageMode 為 null 時的語意一致（epic-16-dual-page）。
    private var dualPageMode: DualPageMode = DualPageMode.AUTO

    // 封面是否獨立單頁顯示（FR-41），預設 true，與
    // BookReaderPrefs.dualPageCoverAlone 為 null 時的語意一致。
    private var dualPageCoverAlone: Boolean = true

    // 解析自 Dart DualPageDirection.name 字串，預設 RTL（Issue 4 決策：
    // elinkBook 全域固定預設為右到左，見 issues.md Issue 4），與
    // BookReaderPrefs.dualPageDirection 為 null 時的語意一致。此欄位在
    // 正常流程中一律被 openBook/setPdfPreferences 的 wire map（無條件
    // 包含 dualPageDirection 鍵）覆寫，此處初始值僅為型別安全起見，實務
    // 上不影響任何真實渲染路徑。
    private var dualPageDirection: DualPageDirection = DualPageDirection.RTL
```

把第 192-207 行：

```kotlin
    /**
     * PDF 雙頁顯示的頁面配對閱讀方向（FR-41），對應 Dart DualPageDirection
     * 列舉（`app/lib/reader/dual_page_direction.dart`）透過 Method Channel
     * 傳來的 `.name` 字串（'ltr'／'rtl'）。
     */
    internal enum class DualPageDirection {
        LTR, RTL;

        companion object {
            /** 未知或非 String 的原始值一律正規化為 [LTR]（預設），與
             * BookReaderPrefs.dualPageDirection 為 null 時的語意一致。*/
            fun fromWireValue(value: String?): DualPageDirection = when (value) {
                "rtl" -> RTL
                else -> LTR
            }
        }
    }
```

改為：

```kotlin
    /**
     * PDF 雙頁顯示的頁面配對閱讀方向（FR-41），對應 Dart DualPageDirection
     * 列舉（`app/lib/reader/dual_page_direction.dart`）透過 Method Channel
     * 傳來的 `.name` 字串（'ltr'／'rtl'）。
     */
    internal enum class DualPageDirection {
        LTR, RTL;

        companion object {
            /** 未知或非 String 的原始值一律正規化為 [RTL]（預設，Issue 4
             * 決策：elinkBook 全域固定預設為右到左），與
             * BookReaderPrefs.dualPageDirection 為 null 時的語意一致。*/
            fun fromWireValue(value: String?): DualPageDirection = when (value) {
                "ltr" -> LTR
                else -> RTL
            }
        }
    }
```

- [ ] **Step 13：執行測試，確認通過**

```bash
./gradlew :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfReaderViewTest"
```

Expected：`BUILD SUCCESSFUL`，全數測試（含 Task 1 修改的 2 個）通過。

- [ ] **Step 14：更新 `spec.md` 的兩處 `ltr` 預設值描述**

把 `docs/epics/epic-16-dual-page/spec.md` 第 16 行內，`並在 ReaderPrefsManagerImpl.resolve()...` 這句中的：

```
`dualPageDirection: book.dualPageDirection ?? DualPageDirection.ltr`
```

改為：

```
`dualPageDirection: book.dualPageDirection ?? DualPageDirection.rtl`（Issue 4 決策：elinkBook 全域固定預設為右到左，見 `docs/epics/epic-16-dual-page/issues.md` Issue 4）
```

把第 49 行：

```sql
ALTER TABLE book_reader_prefs ADD COLUMN dual_page_direction TEXT;      -- DualPageDirection.name，NULL = ltr（預設）
```

改為：

```sql
ALTER TABLE book_reader_prefs ADD COLUMN dual_page_direction TEXT;      -- DualPageDirection.name，NULL = rtl（Issue 4 決策後的預設，原為 ltr）
```

- [ ] **Step 15：全專案回歸測試**

```bash
cd app
flutter test
flutter analyze
```

Expected：`flutter test` 全數 PASS（含本 Task 修改的 3 個檔案與既有全部測試）；`flutter analyze` "No issues found!"。

- [ ] **Step 16：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/lib/reader/dual_page_direction.dart app/lib/reader/book_reader_prefs.dart app/lib/reader/reader_prefs_manager_impl.dart app/lib/reader/pdf_reader_view.dart app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt app/test/reader/reader_prefs_manager_test.dart app/test/reader/pdf_reader_view_test.dart app/test/screens/reader_screen_test.dart docs/epics/epic-16-dual-page/spec.md
git commit -m "feat(epic-16): DualPageDirection 全域固定預設值由 ltr 改為 rtl（Issue 4 決策）"
```

---

### Task 2：`PdfSettingsSheet` 新增「封面獨立」開關

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`
- Test: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes：`BookReaderPrefs.dualPageCoverAlone`（Issue 2，nullable，null=true）
- Produces：「顯示」分頁新增「封面獨立顯示」開關（`Key('pdf_settings_dual_page_cover_alone')`），點擊觸發 `onChanged` 回傳更新後的 `BookReaderPrefs`；`dualPageDirection` 本步驟仍原樣透傳（Task 3 才追蹤其本地狀態）

**審查修正（`tmp/epic-16/reviews/review-plan-issue-4.md`）**：外層 Bottom Sheet 固定 `height: 400`（見 `build()` 的 `SizedBox`），`_buildDisplayTab()` 原本是無捲動能力的 `Padding > Column`；Task 2 起持續在此分頁新增控制項（本 Task 的 `SwitchListTile` + Task 3 的頁面方向選單），內容總高度粗估將超出固定高度、觸發 `RenderFlex overflow` 崩潰。本 Task 一併把 `_buildDisplayTab()` 的 `Column` 包進 `SingleChildScrollView`（見 Step 5），並新增一個直接驗證不拋例外的回歸測試（見 Step 1 最後一個測試）。

- [ ] **Step 1：撰寫失敗測試——擴充 `pdf_settings_sheet_test.dart`**

在 `app/test/screens/pdf_settings_sheet_test.dart` 檔案最後一個測試（`'已持久化 dualPageMode 時，調整濾鏡分頁不會清空 dualPageMode（回歸檢查）'`）之後、`}`（`main()` 結尾）之前，新增以下 5 個測試：

```dart
  testWidgets('顯示分頁新增封面獨立開關', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byKey(const Key('pdf_settings_dual_page_cover_alone')),
        findsOneWidget);
  });

  testWidgets('封面獨立開關初始值反映 prefs（未持久化時預設開啟）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('pdf_settings_dual_page_cover_alone')))
          .value,
      isTrue,
    );
  });

  testWidgets('關閉封面獨立開關後，onChanged 帶入 dualPageCoverAlone=false',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_cover_alone')));
    await tester.pump();

    expect(notified?.dualPageCoverAlone, isFalse);
  });

  testWidgets(
      '已持久化 dualPageCoverAlone=false 時，調整雙頁模式不會清空該欄位（回歸檢查）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(dualPageCoverAlone: false),
      (prefs) => notified = prefs,
    );

    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_mode_always')));
    await tester.pump();

    expect(notified?.dualPageMode, DualPageMode.always);
    expect(notified?.dualPageCoverAlone, isFalse); // 關鍵斷言：未被清空
  });

  testWidgets(
      '顯示分頁新增控制項後仍可正常渲染，不觸發 RenderFlex overflow（審查修正）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/pdf_settings_sheet_test.dart
```

Expected：FAIL——找不到 `Key('pdf_settings_dual_page_cover_alone')`；`notified?.dualPageCoverAlone` 恆為 `null`（overflow 測試本身在此階段預期通過，因為固定高度尚未被新內容撐爆；改動 `_buildDisplayTab()` 後才會實際驗證到 Step 5 的修正）。

- [ ] **Step 3：修改 `pdf_settings_sheet.dart`——新增本地狀態欄位與 `initState`**

在 State 欄位宣告區塊，`late DualPageMode _dualPageMode;` 之後新增：

```dart
  late bool _dualPageCoverAlone;
```

`initState()` 在 `_dualPageMode = widget.prefs.dualPageMode ?? DualPageMode.auto;` 之後新增：

```dart
    _dualPageCoverAlone = widget.prefs.dualPageCoverAlone ?? true;
```

- [ ] **Step 4：修改 `_notifyChanged()`**

把：

```dart
      pdfCropRect: widget.prefs.pdfCropRect,
      dualPageMode: _dualPageMode,
      // dualPageCoverAlone／dualPageDirection 的 UI 控制項留給 Issue 4
      // （見 docs/epics/epic-16-dual-page/issues.md），本分頁尚未追蹤這兩個
      // 欄位的本地狀態，原樣帶回既有值，避免使用者調整雙頁模式或其他分頁時
      // 被靜默清空。
      dualPageCoverAlone: widget.prefs.dualPageCoverAlone,
      dualPageDirection: widget.prefs.dualPageDirection,
    ));
```

改為：

```dart
      pdfCropRect: widget.prefs.pdfCropRect,
      dualPageMode: _dualPageMode,
      dualPageCoverAlone: _dualPageCoverAlone,
      // dualPageDirection 的 UI 控制項留給 Task 3，本步驟尚未追蹤其本地
      // 狀態，原樣帶回既有值，避免調整封面獨立開關時被靜默清空。
      dualPageDirection: widget.prefs.dualPageDirection,
    ));
```

- [ ] **Step 5：修改 `_buildDisplayTab()`——包進 `SingleChildScrollView` 並新增 SwitchListTile**

把整個 `_buildDisplayTab()` 方法：

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

改為：

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
      // 外層 Bottom Sheet 是固定 height: 400（見 build() 的 SizedBox），
      // 本分頁持續新增控制項會讓內容總高度有機會超出固定高度；改用
      // SingleChildScrollView 包裹，避免觸發 RenderFlex overflow（審查
      // 修正，見 tmp/epic-16/reviews/review-plan-issue-4.md）。
      child: SingleChildScrollView(
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
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
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
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
                  onPressed: () => setState(() {
                    _dualPageMode = mode;
                    _notifyChanged();
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              key: const Key('pdf_settings_dual_page_cover_alone'),
              title: const Text('封面獨立顯示'),
              value: _dualPageCoverAlone,
              onChanged: (v) => setState(() {
                _dualPageCoverAlone = v;
                _notifyChanged();
              }),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 6：執行測試，確認通過**

```bash
flutter test test/screens/pdf_settings_sheet_test.dart
```

Expected：全數 PASS。

- [ ] **Step 7：`flutter analyze`**

```bash
flutter analyze
```

Expected："No issues found!"

- [ ] **Step 8：Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-16): PdfSettingsSheet 顯示分頁新增封面獨立開關"
```

---

### Task 3：`PdfSettingsSheet` 新增「頁面方向」LTR/RTL 二選一

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`
- Test: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes：`BookReaderPrefs.dualPageDirection`（Issue 2，nullable，Task 1 之後 null=rtl）
- Produces：「顯示」分頁新增「頁面方向」二選一（`Key('pdf_settings_dual_page_direction_ltr'/'rtl')`），點擊觸發 `onChanged` 回傳更新後的 `BookReaderPrefs`

- [ ] **Step 1：撰寫失敗測試——擴充 `pdf_settings_sheet_test.dart`**

在 `app/test/screens/pdf_settings_sheet_test.dart` 開頭 import 區塊，`import 'package:elinkbook/reader/dual_page_mode.dart';` 之後新增：

```dart
import 'package:elinkbook/reader/dual_page_direction.dart';
```

在 Task 2 新增的最後一個測試之後、`}`（`main()` 結尾）之前，新增以下 4 個測試：

```dart
  testWidgets('顯示分頁新增頁面方向兩個選項按鈕', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byKey(const Key('pdf_settings_dual_page_direction_ltr')),
        findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_dual_page_direction_rtl')),
        findsOneWidget);
  });

  testWidgets('點擊左到右選項後，onChanged 帶入 dualPageDirection=ltr', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(dualPageDirection: DualPageDirection.rtl),
      (prefs) => notified = prefs,
    );

    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_direction_ltr')));
    await tester.pump();

    expect(notified?.dualPageDirection, DualPageDirection.ltr);
  });

  testWidgets(
      '點擊右到左選項後，onChanged 帶入 dualPageDirection=rtl（未持久化時預設即為 rtl）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_direction_rtl')));
    await tester.pump();

    expect(notified?.dualPageDirection, DualPageDirection.rtl);
  });

  testWidgets(
      '已持久化 dualPageDirection=ltr 時，調整封面獨立開關不會清空該欄位（回歸檢查）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(dualPageDirection: DualPageDirection.ltr),
      (prefs) => notified = prefs,
    );

    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_cover_alone')));
    await tester.pump();

    expect(notified?.dualPageCoverAlone, isFalse);
    expect(notified?.dualPageDirection,
        DualPageDirection.ltr); // 關鍵斷言：未被清空
  });
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/screens/pdf_settings_sheet_test.dart
```

Expected：FAIL——找不到 `Key('pdf_settings_dual_page_direction_ltr'/'rtl')`；`notified?.dualPageDirection` 恆為呼叫端原樣傳回的值，未反映使用者點擊。

- [ ] **Step 3：修改 `pdf_settings_sheet.dart`——新增匯入與本地狀態欄位**

把 import 區塊：

```dart
import 'package:flutter/material.dart';

import '../reader/book_reader_prefs.dart';
import '../reader/dual_page_mode.dart';
import '../reader/pdf_fit_mode.dart';
import '../reader/pdf_crop_mode.dart';
```

改為：

```dart
import 'package:flutter/material.dart';

import '../reader/book_reader_prefs.dart';
import '../reader/dual_page_direction.dart';
import '../reader/dual_page_mode.dart';
import '../reader/pdf_fit_mode.dart';
import '../reader/pdf_crop_mode.dart';
```

在 State 欄位宣告區塊，`late bool _dualPageCoverAlone;` 之後新增：

```dart
  late DualPageDirection _dualPageDirection;
```

`initState()` 在 `_dualPageCoverAlone = widget.prefs.dualPageCoverAlone ?? true;` 之後新增：

```dart
    _dualPageDirection = widget.prefs.dualPageDirection ?? DualPageDirection.rtl;
```

- [ ] **Step 4：修改 `_notifyChanged()`**

把：

```dart
      dualPageCoverAlone: _dualPageCoverAlone,
      // dualPageDirection 的 UI 控制項留給 Task 3，本步驟尚未追蹤其本地
      // 狀態，原樣帶回既有值，避免調整封面獨立開關時被靜默清空。
      dualPageDirection: widget.prefs.dualPageDirection,
    ));
```

改為：

```dart
      dualPageCoverAlone: _dualPageCoverAlone,
      dualPageDirection: _dualPageDirection,
    ));
```

- [ ] **Step 5：修改 `_buildDisplayTab()`——新增頁面方向選項**

在 `_buildDisplayTab()` 開頭的 `const dualPageOptions = [...]` 之後新增：

```dart
    const directionOptions = [
      (
        DualPageDirection.ltr,
        'ltr',
        Icons.format_textdirection_l_to_r,
        '左到右',
      ),
      (
        DualPageDirection.rtl,
        'rtl',
        Icons.format_textdirection_r_to_l,
        '右到左（日漫慣例）',
      ),
    ];
```

把 Task 2 新增的 `SwitchListTile` 區塊尾端（Task 2 已把 `Column` 包進 `SingleChildScrollView`，注意此處縮排層級比 Task 2 之前多兩層）：

```dart
            const SizedBox(height: 16),
            SwitchListTile(
              key: const Key('pdf_settings_dual_page_cover_alone'),
              title: const Text('封面獨立顯示'),
              value: _dualPageCoverAlone,
              onChanged: (v) => setState(() {
                _dualPageCoverAlone = v;
                _notifyChanged();
              }),
            ),
          ],
        ),
      ),
    );
  }
```

改為：

```dart
            const SizedBox(height: 16),
            SwitchListTile(
              key: const Key('pdf_settings_dual_page_cover_alone'),
              title: const Text('封面獨立顯示'),
              value: _dualPageCoverAlone,
              onChanged: (v) => setState(() {
                _dualPageCoverAlone = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            const Text('頁面方向'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: directionOptions.map((option) {
                final (direction, keySuffix, icon, tooltip) = option;
                final selected = _dualPageDirection == direction;
                return IconButton(
                  key: Key('pdf_settings_dual_page_direction_$keySuffix'),
                  icon: Icon(icon),
                  tooltip: tooltip,
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
                  onPressed: () => setState(() {
                    _dualPageDirection = direction;
                    _notifyChanged();
                  }),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 6：執行測試，確認通過**

```bash
flutter test test/screens/pdf_settings_sheet_test.dart
```

Expected：全數 PASS。

- [ ] **Step 7：全專案回歸 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：`flutter test` 全數 PASS；`flutter analyze` "No issues found!"。

- [ ] **Step 8：Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-16): PdfSettingsSheet 顯示分頁新增頁面方向 LTR/RTL 二選一"
```

---

### Task 4：`integration_test/pdf_dual_page_test.dart` 新增封面獨立關閉時的翻頁步進驗證

**Files:**
- Modify: `app/integration_test/pdf_dual_page_test.dart`

**Interfaces:**
- Consumes：Task 1-3 完成後的 `PdfReaderView`／原生端行為；Issue 3 既有的 `_nextPage(tester)`／`pumpAndWaitRendered()` 頂層 helper
- Produces：真機可驗證的「`dualPageCoverAlone = false` 時，第 0 頁不再獨立配對」回歸測試

**已知測試限制**：本 task 驗證的是「封面是否被視為 spread 一部分」的結構性證據（翻頁步進量從 1 變 2），而非「畫面是否真的無縫拼接兩頁點陣圖」的像素層級正確性——後者留給 Issue 7 的真機肉眼/截圖確認（比照 Issue 3 `plan-issue-3.md` Task 7 的既有慣例）。

- [ ] **Step 1：撰寫失敗測試——擴充 `pdf_dual_page_test.dart`**

在 `app/integration_test/pdf_dual_page_test.dart` 檔案最後一個測試（`'auto 模式：裝置從橫向轉回直向時，恢復單頁步進...'`）之後、`}`（`main()` 結尾）之前，新增以下測試：

```dart
  testWidgets(
      'auto 模式橫向：封面獨立關閉時，index 0 也步進 2（不再獨立配對，Issue 4）',
      (tester) async {
    final path = await stagePath('sample_dual_page_cover_not_alone.pdf');
    final pageChanges = <int>[];
    await pumpAndWaitRendered(
      tester,
      path,
      pageChanges,
      isLandscape: true,
      dualPageCoverAlone: false,
    );

    // 封面獨立關閉：index 0 不再是獨立單頁，與 index 1 配對成 [0,1]，
    // 步進行為比照非封面情境恆為 2。
    _nextPage(tester);
    await tester.pumpAndSettle();
    expect(pageChanges, [2]); // 跳到 [2,3]，而非封面獨立開啟時的步進 1

    _nextPage(tester);
    await tester.pumpAndSettle();
    expect(pageChanges, [2, 4]); // 繼續步進 2 到 [4,5]

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
```

- [ ] **Step 2：於真實裝置執行 integration_test**

```bash
cd app
flutter devices
flutter test integration_test/pdf_dual_page_test.dart -d <device-id>
```

Expected：全數測試通過（含既有 Issue 3 的 6 個測試與本 task 新增的 1 個，共 7 個）。

- [ ] **Step 3：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/integration_test/pdf_dual_page_test.dart
git commit -m "test(epic-16): pdf_dual_page_test 新增封面獨立關閉時的翻頁步進驗證"
```

---

### Task 5：`integration_test/reader_screen_test.dart` 新增封面獨立/頁面方向 UI 互動與持久化驗證

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 2-3 的 `PdfSettingsSheet` UI（`Key('pdf_settings_dual_page_cover_alone')`／`Key('pdf_settings_dual_page_direction_ltr'/'rtl')`）；既有 `ReaderScreen`／`prefsManager`／`_stageAssetAsFile`／`_book`／`_layoutSettingsButtonReady`／`_pumpUntil`／`_loadingIndicatorGone` 頂層 helper
- Produces：真機可驗證的「調整封面獨立開關與頁面方向後關閉重開，兩個新設定值正確持久化」端到端回歸測試，對應 `issues.md` Issue 4 第三項驗收標準

- [ ] **Step 1：撰寫失敗測試——擴充 `reader_screen_test.dart`**

在 `app/integration_test/reader_screen_test.dart` 開頭 import 區塊，`import 'package:elinkbook/reader/pdf_crop_mode.dart';` 之後新增：

```dart
import 'package:elinkbook/reader/dual_page_direction.dart';
```

在檔案最後一個測試（`'PDF 依序調整 Fit 模式/對比度/亮度/加粗/裁切模式後關閉重開...'`）之後、`}`（`main()` 結尾）之前，新增以下測試：

```dart
  testWidgets(
      'PDF 調整封面獨立開關與頁面方向後關閉重開，兩個新設定值正確持久化（Issue 4）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_issue4_persist.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_issue4_persist';
    await libraryRepository
        .insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();

    // 顯示分頁預設就是開啟時的分頁，不需額外切換。關閉「封面獨立」開關、
    // 切換頁面方向為左到右（Task 1 已把全域固定預設值改為 rtl，這裡刻意
    // 切到 ltr，同時驗證「非預設值」也能正確持久化，而不只是巧合地與
    // 預設值相同）。
    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_cover_alone')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_direction_ltr')));
    await tester.pump(const Duration(milliseconds: 300));

    final beforeClose =
        tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(beforeClose.dualPageCoverAlone, isFalse);
    expect(beforeClose.dualPageDirection, DualPageDirection.ltr);

    // 從資料庫直接讀出持久化結果（不透過畫面重建，排除「畫面剛好還沒
    // rebuild」這種偽陽性）。
    final saved = (await prefsManager.load(bookId)).bookPrefs;
    expect(saved.dualPageCoverAlone, isFalse);
    expect(saved.dualPageDirection, DualPageDirection.ltr);

    // 關閉重開，驗證兩個新設定值持久化。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );
    await tester.pump(const Duration(seconds: 1));

    final afterReopen =
        tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(afterReopen.dualPageCoverAlone, beforeClose.dualPageCoverAlone,
        reason: '重開書後 dualPageCoverAlone 應與關閉前一致');
    expect(afterReopen.dualPageDirection, beforeClose.dualPageDirection,
        reason: '重開書後 dualPageDirection 應與關閉前一致');

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
```

- [ ] **Step 2：於真實裝置執行 integration_test**

```bash
cd app
flutter test integration_test/reader_screen_test.dart -d <device-id>
```

Expected：全數測試通過（含既有測試與本 task 新增的 1 個）。

- [ ] **Step 3：全專案回歸測試 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：`flutter test` 全數 PASS（含 Task 1-3 新增/修改的所有測試，以及既有全部測試不受影響）；`flutter analyze` "No issues found!"。

- [ ] **Step 4：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/integration_test/reader_screen_test.dart
git commit -m "test(epic-16): reader_screen_test 新增封面獨立/頁面方向 UI 互動與持久化驗證"
```

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：`issues.md` Issue 4 描述的兩個 UI 控制項（封面獨立開關、頁面方向二選一）分別對應 Task 2、Task 3；三項驗收標準（`dualPageCoverAlone=false` 配對行為、`dualPageDirection=rtl` 的 `onPageChanged` 回報值不受方向影響、持久化）分別對應 Task 4（配對行為的結構性驗證）與 Task 5（持久化）；「`onPageChanged` 回報值仍為 `currentPageIndex`」這項在 Issue 3 的既有測試（`ltr`/`always`/`never` 情境）已充分證明「翻頁步進與 `dualPageDirection` 無關」，Task 4 只需針對 `dualPageCoverAlone` 補一個未覆蓋的情境，不重複驗證方向無關性本身。
- **人類決策的落地**：「維持手動，改固定 rtl 預設」的決策完整體現在 Task 1（生產程式碼、既有測試、`spec.md`、Kotlin 原生端 KDoc 四處一致翻轉），且明確排除了「依 `WritingMode` 自動偵測」這個被否決的方向，未在計劃任何角落留下相關程式碼或 TODO。
- **無佔位符掃描**：所有步驟皆附完整程式碼、確切檔案路徑與行號範圍，無 "TODO"/"視情況" 字樣；Task 1 的 11 處 `pdf_reader_view_test.dart` 字串替換、Task 4/5 的完整測試內容皆已寫出逐字程式碼，非「比照上面」的簡略帶過。
- **型別/介面一致性**：`DualPageDirection.ltr/rtl`（Dart）↔ `DualPageDirection.LTR/RTL`（Kotlin，`fromWireValue` 對應）全文用法與 Issue 3 一致；`PdfSettingsSheet` 新增的 `_dualPageCoverAlone: bool`／`_dualPageDirection: DualPageDirection` 兩個 State 欄位命名與既有 `_dualPageMode`／`_fitMode`／`_cropMode` 慣例一致；`Key` 命名（`pdf_settings_dual_page_cover_alone`／`pdf_settings_dual_page_direction_ltr`/`rtl`）延續既有 `pdf_settings_dual_page_mode_$suffix`／`pdf_settings_fit_mode_$suffix` 前綴規則。
- **Task 執行順序的依賴關係**：Task 1（預設值翻轉）必須先於 Task 3（`initState()` 直接引用新預設值 `DualPageDirection.rtl`）；Task 2、3 必須先於 Task 5（UI 互動測試依賴 Task 2/3 新增的 `Key`）；Task 4 可與 Task 2/3/5 平行進行（`pdf_dual_page_test.dart` 直接建構 `PdfReaderView`，不經過 `PdfSettingsSheet`），但邏輯上列在 Task 5 之前以維持「先驗證原生渲染行為、後驗證 UI 曝光」的一致敘事順序。
- **依 `/superpowers:requesting-code-review` 對本計劃的審查修正**（`tmp/epic-16/reviews/review-plan-issue-4.md`）：
  1. **已採納**：Task 2、3 持續在固定 `height: 400` 的 Bottom Sheet「顯示」分頁新增控制項，粗估內容總高度會超出可用空間、觸發 `RenderFlex overflow`。已在 Task 2 Step 5 把 `_buildDisplayTab()` 的 `Column` 包進 `SingleChildScrollView`，並新增直接驗證 `tester.takeException()` 為 null 的回歸測試（Task 2 Step 1 最後一個測試）；Task 3 Step 5 的 before/after 程式碼區塊已同步更新縮排，反映 `SingleChildScrollView` 包裹後多出的巢狀層級。
  2. **不採納（已核實、推翻）**：審查指控 `initState()` 用 `??` 把 nullable 偏好設定轉為非 null 本地狀態、`_notifyChanged()` 無條件送出具體值，違反「null = 不覆寫」語意。查證後，這是 `PdfSettingsSheet` 從 Issue 3（甚至更早）就存在的既定寫法——`_fitMode`／`_contrast`／`_brightness`／`_boldStrength`／`_cropMode`／`_dualPageMode` 六個既有欄位全部是同一種模式，本計劃新增的 `_dualPageCoverAlone`／`_dualPageDirection` 只是延續一致性，不是新引入的缺陷。若要修正，範圍是整個 `PdfSettingsSheet`（8 個欄位一起改），只改本次新增的 2 個欄位反而會在同一個 class 內造成不一致行為，超出 Issue 4「UI 曝光」的範圍，故不在本計劃處理。
  3. **不採納（認可但延後）**：審查建議的兩個程式碼味道（`_draftPrefs.copyWith()` 取代多個 `late` 欄位、抽出共用選擇器元件）皆要求重構 Issue 3 已出貨、已審查通過的既有 6 個欄位，不是本次新增的 2 個欄位造成，不在本 issue 範圍內處理。
