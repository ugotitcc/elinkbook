# Epic 16 Issue 5 — PDF 手動裁切 × 雙頁互動安全 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 驗證並補強既有裁切功能（`CropOverlayView`／`enterCropEditMode`）與雙頁模式（Issue 3/4）交互時的安全性——確認 Issue 3 既有架構已滿足 issues.md 的三項既定需求，並修補一個規劃階段新發現的裝置旋轉風險。

**Architecture:** 本 issue **不新增任何新的渲染邏輯**。深入比對 `spec.md` 決策 #10／I-8 與目前 `main` 上 `PdfReaderView.kt` 的 `enterCropEditMode()`／`exitCropEditMode()`／`renderFullPageForCropPreview()`／`nextPage()`／`previousPage()` 後確認：這些函式自 Issue 3 起就完全未被異動過（Issue 3 計劃明確排除），而它們本來就只依賴 `currentPageIndex`／`cropEditModeActive` 這兩個既有機制，因此 issues.md 描述的「裁切模式強制單頁預覽」「退出後套用同一 `cropRect`」「翻頁在裁切模式中暫停」三項需求**已經自動成立，不需要新程式碼**——本 issue 的實質工作是撰寫 `integration_test` 把這個既有保證釘死成回歸測試。

規劃階段透過程式碼分析發現一個 issues.md 未描述、但屬於同一類「裁切 × 雙頁互動安全」的真實風險（已與人類確認列入本 issue 範圍）：`setPdfPreferences()`（`PdfReaderView.kt`）收到偏好變動時，未在方法最前面檢查 `cropEditModeActive` 就直接走原本的分派邏輯。這個風險有兩個入口：(1) Issue 3 新增的 `isLandscape` 由裝置旋轉觸發、與裁切互動完全無關地送出，若在裁切編輯模式中旋轉裝置，會讓 `dualPageChanged=true` 觸發 `renderCurrentSpread()`，因 `cropEditModeActive=true` 而分派到 `renderSingleSpread()`（套用目前 `cropMode`/濾鏡、非 `FIT_CENTER`）；(2) 若三個 `*Changed` 旗標皆為 `false`（例如僅 `contrast`/`brightness` 變動），會落入 `else` 分支呼叫 `applyFitMode()`／`applyFilters()`，兩者都可能改變 `imageView` 的 `scaleType`／`colorFilter`。兩種情況都會覆蓋掉 `enterCropEditMode()` 原本設定的「全頁、未裁切、`FIT_CENTER`、無濾鏡」預覽狀態，讓 `CropOverlayView` 的座標假設與實際畫面不同步。Task 1 修補此風險（`/superpowers:requesting-code-review` 對本計劃的審查已核實並補強：第 (2) 個入口的完整分析、以及 `spec.md`「旋轉發生在手動裁切編輯模式中（審查修正 I-6）」這個既有明文要求的測試涵蓋缺口，見 Task 1／Task 2 內文標註）。

**Tech Stack:** Kotlin（`PdfReaderView.kt`）、`integration_test`（真機，本 issue 全部驗證皆需真機，無可脫離裝置的純邏輯異動）。

## Global Constraints

- **前置狀態（已確認完成，非假設）**：Issue 3、Issue 4 皆已完成並合併回 `main`（Issue 3：PR #38；Issue 4：PR #39 併入 `epic-16/dual-page-issue3` 再合併回 `main`，commit `183b7c0`）。`PdfReaderView`（Dart／Kotlin）已支援 `dualPageMode`／`dualPageCoverAlone`／`dualPageDirection`／`isLandscape`／`cropEditModeActive`／`onCropRectSelected` 完整建構參數與原生渲染邏輯，`DualPageDirection` 全域固定預設值為 `rtl`。本計劃在 `main` 上繼續開工。
- **裁切拖曳手勢的既知限制（沿用既有慣例，不重複診斷）**：`integration_test/reader_screen_test.dart` 既有的手動裁切測試已記錄：在此真機／Flutter 版本組合下，`tester.startGesture`／`dragFrom`／原始 PointerEvent 注入／adb 觸控注入皆無法保證讓 `CropOverlayView` 的控制點產生實際位移；但**確認按鈕本身是單純 `tester.tapAt()`，已證實可靠**（既有測試持續通過）。本 issue 新增的整合測試沿用相同手法與相同誠實態度：拖曳動作照樣執行（作為手勢序列的一部分，不假設它一定造成矩形改變），真正驗證的是確認按鈕點擊後的持久化結果與雙頁欄位不被覆蓋。
- **`nextPage()`/`previousPage()` 真機驗證技巧（Issue 3 建立，沿用）**：`nextPage()`/`previousPage()` 定義在 private 的 `_PdfReaderViewState` 但方法名稱本身無底線前綴，可透過 `(tester.state(find.byType(PdfReaderView)) as dynamic).nextPage()` 動態呼叫繞過既已證實不可靠的手勢注入層，直接、可靠地驅動翻頁。
- **`PdfSettingsSheet` 顯示分頁的 `SingleChildScrollView`（Issue 4 建立，沿用）**：分頁模式按鈕（`pdf_settings_dual_page_mode_$suffix`）位於捲動內容前段，既有測試證實無需 `ensureVisible()` 即可直接 `tester.tap()`；封面獨立／頁面方向控制項位置較後段才需要。本 issue 只用到雙頁模式按鈕，不需要 `ensureVisible()`。
- **像素層級正確性一律留給人類真機 QA（Issue 3/4 既定慣例，本 issue 沿用不重複造輪子）**：`integration_test` 無法檢視原生 `ImageView` 的 bitmap 內容，因此「畫面是否真的顯示單頁預覽」「裁切矩形視覺上是否正確套用到雙頁兩側」這類像素層級驗收，一律改以結構性驗證替代（`onPageChanged` 序列、`onError` 是否觸發、持久化欄位值），視覺確認留給 Issue 7 的既定收尾範圍。**例外**：`spec.md`「旋轉發生在手動裁切編輯模式中（審查修正 I-6）」明文要求驗證 `CropOverlayView.onSizeChanged()`——這個原生方法只在 View 實際被重新 layout（尺寸真的改變）時才會觸發，僅改變 Dart 端 `isLandscape` 語意旗標並不會觸發它，Task 2 的旋轉測試須同時搭配 `tester.binding.setSurfaceSize()`（比照 Issue 3 `reader_screen_test.dart` 既有的橫向/直向切換手法）才能真正觸發到這個原生方法；即便如此，仍只能驗證「不崩潰、不拋例外」，`onSizeChanged()` 內部重算結果是否像素正確仍屬人類 QA 範圍。
- **頁碼索引慣例**：全文 0-indexed，`currentPageIndex` 從 0 起算。
- **不得引入的範圍**：不新增任何新的 pure-Kotlin 模組檔案（沿用 Issue 3/4 慣例）；不修改 `CropOverlayView` 本身（`spec.md` 決策 #10 明文「`CropOverlayView` 本身不需改動，只處理單頁座標」）；不新增 per-page 裁切矩形（`cropRect` 維持全書共用單一矩形，`design.md` 決策 #10 已明文排除逐頁偵測）。

---

### Task 1：`setPdfPreferences()` 在裁切編輯模式中收到偏好變動時，改呼叫 `renderFullPageForCropPreview()`

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`

**Interfaces:**
- Consumes：既有 `cropEditModeActive: Boolean`、`renderFullPageForCropPreview()`、`renderCurrentSpread()`（皆為 Issue 3/epic-4 既有函式，本 task 不新增任何函式簽章）
- Produces：`setPdfPreferences()` 的重新渲染分派邏輯（供 Task 2 的 `integration_test` 驗證）

本 task 的效果是像素層級的（畫面顯示內容是否維持裁切預覽狀態），無法透過自動化測試直接斷言渲染結果本身，因此不採用「先寫失敗測試」的標準 TDD 順序——先做程式碼修改，Task 2 補上「不出現例外」的結構性回歸測試（弱保證，但是這類原生 View 渲染邏輯在本 epic 一貫的驗證上限，見 Global Constraints）。

- [ ] **Step 1：修改 `setPdfPreferences()`**

把 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt` 的 `setPdfPreferences()` 方法（第 325-350 行）：

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
```

改為：

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
        // 裁切編輯模式中（cropEditModeActive）畫面必須維持
        // enterCropEditMode() 設定的「全頁、未裁切、FIT_CENTER、無濾鏡」
        // 預覽狀態，不能被本次偏好變動觸發的任何重新渲染覆蓋掉——提升為
        // 整個方法最前面的守衛，不論原本會落入下方哪個分支，一律優先呼叫
        // renderFullPageForCropPreview() 並提前 return。
        //
        // 這個守衛同時堵住兩個入口：(1) isLandscape（裝置旋轉時由
        // ReaderScreen 透過 MediaQuery 偵測送出，與裁切互動完全無關）改變
        // 觸發 dualPageChanged=true 時，若呼叫 renderCurrentSpread()，
        // dualPageEnabled 會因 cropEditModeActive=true 而判定為 false，改
        // 渲染 renderSingleSpread()（套用目前 cropMode/濾鏡、非
        // FIT_CENTER）；(2) 僅 contrast/brightness 變動、三個 *Changed 旗標
        // 皆為 false 時，會落入下方 else 分支呼叫 applyFitMode()（可能把
        // scaleType 改成 MATRIX）與 applyFilters()（套用 colorFilter），兩者
        // 都會直接覆蓋 renderFullPageForCropPreview() 設定的 FIT_CENTER／
        // colorFilter=null 狀態。兩種情況都會讓 CropOverlayView 的座標假設
        // 與實際畫面不同步（epic-16-dual-page Issue 5 發現，spec.md 決策
        // #10／I-8 的安全延伸；`/superpowers:requesting-code-review` 對本
        // 計劃的審查意見 Finding 4 指出原始修法只堵了 if 分支的
        // renderCurrentSpread() 入口，遺漏了 else 分支的 applyFitMode()／
        // applyFilters()，此處改為統一在方法最前面攔截，兩個入口一次堵死）。
        if (cropEditModeActive) {
            renderFullPageForCropPreview()
            return
        }
        if (boldChanged || cropChanged || dualPageChanged) {
            renderCurrentSpread()
        } else {
            applyFitMode()
            applyFilters()
        }
    }
```

- [ ] **Step 2：編譯檢查**

```bash
cd app/android
./gradlew :app:compileDebugKotlin
```

Expected：`BUILD SUCCESSFUL`。

- [ ] **Step 3：既有 JVM 單元測試回歸**

```bash
./gradlew :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfReaderViewTest"
```

Expected：`BUILD SUCCESSFUL`，全數既有測試（34 個）不受影響（本 task 未變動任何 companion object 純函式，`setPdfPreferences()` 是 instance method，不在 JVM 測試涵蓋範圍內，維持 Issue 3 既定的「像素渲染邏輯留給 integration_test」分工）。

- [ ] **Step 4：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt
git commit -m "fix(epic-16): setPdfPreferences() 裁切編輯模式中改呼叫 renderFullPageForCropPreview()，避免裝置旋轉造成 CropOverlayView 座標不同步"
```

---

### Task 2：`integration_test/pdf_dual_page_test.dart` 新增裁切編輯模式的結構性安全驗證

**Files:**
- Modify: `app/integration_test/pdf_dual_page_test.dart`

**Interfaces:**
- Consumes：Task 1 修正後的 `setPdfPreferences()`；既有 `PdfReaderView` 建構參數 `cropEditModeActive: bool`（epic-4 既有）；既有頂層函式 `_nextPage(tester)`/`_previousPage(tester)`（Issue 3 建立）
- Produces：真機可驗證的「裁切編輯模式暫停雙頁翻頁」「裁切編輯模式中裝置旋轉（含真實 Surface 尺寸變動）不觸發例外」兩項回歸測試，對應 `issues.md` Issue 5 驗收標準第 2 點、`spec.md`「旋轉發生在手動裁切編輯模式中（審查修正 I-6）」、與 Task 1 修補的風險

**已知測試限制**：本 task 驗證的是「翻頁是否確實被暫停」「是否觸發例外」這類結構性事實，不是「畫面是否真的顯示裁切預覽」這種像素層級事實（見 Global Constraints）。

- [ ] **Step 1：撰寫失敗測試——擴充 `pdf_dual_page_test.dart`**

在 `app/integration_test/pdf_dual_page_test.dart` 檔案最後一個測試（`'auto 模式橫向：封面獨立關閉時，index 0 也步進 2（不再獨立配對，Issue 4）'`）之後、`}`（`main()` 結尾）之前，新增以下 2 個測試：

```dart
  testWidgets(
      '裁切編輯模式中，雙頁模式下的翻頁暫停回應（Issue 5，spec.md 決策 #10）',
      (tester) async {
    final path = await stagePath('sample_dual_page_crop_pause.pdf');
    final pageChanges = <int>[];
    final completer = Completer<void>();

    Widget buildView(bool cropEditModeActive) => MaterialApp(
          home: PdfReaderView(
            filePath: path,
            onPageRendered: () {
              if (!completer.isCompleted) completer.complete();
            },
            onError: (message) => fail('不應觸發 onError：$message'),
            onPageChanged: pageChanges.add,
            dualPageMode: DualPageMode.always,
            cropEditModeActive: cropEditModeActive,
          ),
        );

    await tester.pumpWidget(buildView(false));
    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 進入裁切編輯模式：cropEditModeActive false -> true 觸發原生端
    // enterCropEditMode()。
    await tester.pumpWidget(buildView(true));
    await tester.pumpAndSettle();

    // 裁切編輯模式中呼叫 nextPage()/previousPage() 應為 no-op——原生端
    // nextPage()/previousPage() 頂端的既有 cropEditModeActive 守衛，本測試
    // 針對「雙頁模式生效時」這個情境明確驗證（spec.md 決策 #10）。
    _nextPage(tester);
    await tester.pumpAndSettle();
    expect(pageChanges, isEmpty);

    _previousPage(tester);
    await tester.pumpAndSettle();
    expect(pageChanges, isEmpty);

    // 退出裁切編輯模式：恢復雙頁翻頁能力。
    await tester.pumpWidget(buildView(false));
    await tester.pumpAndSettle();

    _nextPage(tester);
    await tester.pumpAndSettle();
    expect(pageChanges, [1]); // always 模式，封面步進 1，證明翻頁已恢復
  });

  testWidgets(
      '裁切編輯模式中裝置旋轉（isLandscape 變動 + 真實 Surface 尺寸變動）不觸發例外（Issue 5，Task 1 修正，涵蓋 spec.md 審查修正 I-6）',
      (tester) async {
    // 審查修正（tmp/epic-16/reviews/review-plan-issue-5.md Finding 3）：
    // 僅改變 Dart 端 isLandscape 語意旗標不會觸發原生 CropOverlayView 的
    // onSizeChanged()（該方法只在 View 真正被重新 layout、尺寸實際改變時
    // 才會呼叫）；spec.md「旋轉發生在手動裁切編輯模式中（審查修正
    // I-6）」明文要求驗證這個既有的旋轉重算邏輯，因此本測試搭配
    // tester.binding.setSurfaceSize() 一併模擬真實尺寸變動（比照 Issue 3
    // reader_screen_test.dart 既有的橫向/直向切換手法：橫向
    // Size(800, 400)、直向 Size(400, 800)），讓 isLandscape 旗標與實際
    // Surface 尺寸同步變化，才能真正觸發到 onSizeChanged()。
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final path = await stagePath('sample_dual_page_crop_rotate.pdf');
    final pageChanges = <int>[];
    final errors = <String>[];
    final completer = Completer<void>();

    Widget buildView({
      required bool cropEditModeActive,
      required bool isLandscape,
    }) =>
        MaterialApp(
          home: PdfReaderView(
            filePath: path,
            onPageRendered: () {
              if (!completer.isCompleted) completer.complete();
            },
            onError: errors.add,
            onPageChanged: pageChanges.add,
            dualPageMode: DualPageMode.auto,
            isLandscape: isLandscape,
            cropEditModeActive: cropEditModeActive,
          ),
        );

    await tester.binding.setSurfaceSize(const Size(800, 400)); // 橫向
    await tester.pumpWidget(
        buildView(cropEditModeActive: false, isLandscape: true));
    await completer.future.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 進入裁切編輯模式（此時裝置為橫向、auto 模式下雙頁生效中）。
    await tester.pumpWidget(
        buildView(cropEditModeActive: true, isLandscape: true));
    await tester.pumpAndSettle();

    // 模擬裁切編輯模式中裝置旋轉為直向：同時改變 Surface 尺寸與
    // isLandscape 旗標，觸發 setPdfPreferences 與原生 CropOverlayView 的
    // onSizeChanged()，驗證不會拋出 onError（Task 1 修正前，setPdfPreferences
    // 會呼叫 renderCurrentSpread() 或 applyFitMode()/applyFilters() 而非
    // renderFullPageForCropPreview()，雖然本身不會直接拋錯，但會讓
    // CropOverlayView 座標假設與畫面不同步——onSizeChanged() 內部重算結果
    // 是否像素正確仍留待人類真機 QA，本測試只保證不出現例外/崩潰的結構性
    // 回歸）。
    await tester.binding.setSurfaceSize(const Size(400, 800)); // 直向
    await tester.pumpWidget(
        buildView(cropEditModeActive: true, isLandscape: false));
    await tester.pumpAndSettle();

    expect(errors, isEmpty);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 退出裁切編輯模式，確認裁切互動全程結束後畫面仍可正常運作（旋轉後
    // isLandscape=false，auto 模式應恢復單頁，步進 1）。
    await tester.pumpWidget(
        buildView(cropEditModeActive: false, isLandscape: false));
    await tester.pumpAndSettle();

    _nextPage(tester);
    await tester.pumpAndSettle();
    expect(pageChanges, [1]);
    expect(errors, isEmpty);
  });
```

- [ ] **Step 2：於真實裝置執行 integration_test，確認 Task 1 修正前會失敗**

若想先驗證測試本身有意義，可暫時 `git stash` Task 1 的修改後執行：

```bash
cd app
flutter devices
flutter test integration_test/pdf_dual_page_test.dart -d <device-id>
```

Expected（Task 1 修正前）：兩個新測試中，第一個（翻頁暫停）應仍會通過（`cropEditModeActive` 守衛本身在 Task 1 之前就存在，不受本次修正影響）；第二個（裝置旋轉）在 Task 1 修正前也不會拋出例外或斷言失敗（因為本測試只斷言「不出現例外」這個弱保證，這是像素層級限制下能做到的最強驗證，見 Global Constraints）——若已執行 `git stash`，記得 `git stash pop` 還原 Task 1 的修正再繼續。

- [ ] **Step 3：於真實裝置執行 integration_test，確認全數通過**

```bash
flutter test integration_test/pdf_dual_page_test.dart -d <device-id>
```

Expected：全數測試通過（含既有 7 個與本 task 新增的 2 個，共 9 個）。

- [ ] **Step 4：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/integration_test/pdf_dual_page_test.dart
git commit -m "test(epic-16): pdf_dual_page_test 新增裁切編輯模式的翻頁暫停與裝置旋轉安全驗證"
```

---

### Task 3：`integration_test/reader_screen_test.dart` 新增雙頁模式下的完整手動裁切確認流程驗證

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes：既有 `PdfSettingsSheet` 顯示分頁 `Key('pdf_settings_dual_page_mode_always')`（Issue 3）；既有裁切分頁 `Key('pdf_settings_crop_mode_manual')`（epic-4）；既有 `ReaderScreen`／`prefsManager`／`_stageAssetAsFile`／`_book`／`_layoutSettingsButtonReady`／`_pumpUntil` 頂層 helper
- Produces：真機可驗證的「雙頁模式下執行手動裁切確認，裁切與雙頁設定值皆正確持久化、互不清空」端到端回歸測試，對應 `issues.md` Issue 5 驗收標準第 1 點

- [ ] **Step 1：撰寫失敗測試——擴充 `reader_screen_test.dart`**

在 `app/integration_test/reader_screen_test.dart` 開頭 import 區塊，`import 'package:elinkbook/reader/dual_page_direction.dart';` 之後新增：

```dart
import 'package:elinkbook/reader/dual_page_mode.dart';
```

在檔案最後一個測試（`'PDF 調整封面獨立開關與頁面方向後關閉重開，兩個新設定值正確持久化（Issue 4）'`）之後、`}`（`main()` 結尾）之前，新增以下測試：

```dart
  testWidgets(
      'PDF 雙頁模式下執行手動裁切確認流程，裁切與雙頁設定值皆正確持久化（Issue 5）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_crop_dual_page.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_crop_dual_page';
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

    // 顯示分頁（預設分頁，不需切換）：先切到「永遠雙頁」，確保進入裁切
    // 編輯模式前雙頁已生效，才能真正驗證「裁切互動不清空雙頁設定」。
    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_mode_always')));
    await tester.pump(const Duration(milliseconds: 300));

    // 裁切分頁：進入手動選區互動模式。
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump(const Duration(seconds: 1));

    // 拖拉右下角控制點（比照既有手動裁切測試的既知限制：在此真機／
    // Flutter 版本組合下，拖曳動作不一定能讓控制點實際位移，見既有測試
    // 「PDF 手動裁切拖拉四角控制點確認後...」的既有註解），作為手勢序列
    // 的一部分執行，不假設它一定造成矩形改變。
    final pdfViewBox = tester.getRect(find.byType(PdfReaderView));
    final approxBottomRightHandle = Offset(
      pdfViewBox.left + pdfViewBox.width * 0.9,
      pdfViewBox.top + pdfViewBox.height * 0.9,
    );
    final dragGesture = await tester.startGesture(approxBottomRightHandle);
    await tester.pump(const Duration(milliseconds: 50));
    await dragGesture.moveBy(const Offset(-80, -80));
    await tester.pump(const Duration(milliseconds: 50));
    await dragGesture.up();
    await tester.pump(const Duration(seconds: 1));

    // 點擊確認按鈕：CropOverlayView 把它畫在固定右下角，確認按鈕的視覺
    // 半徑遠大於一般手指誤差，直接對區域右下角嘗試點擊即可命中。
    final approxConfirmButton = Offset(
      pdfViewBox.right - 40,
      pdfViewBox.bottom - 40,
    );
    await tester.tapAt(approxConfirmButton);
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(PdfSettingsSheet), findsOneWidget,
        reason: '確認框選後應重新開啟 PdfSettingsSheet 顯示套用結果');

    // 關鍵回歸檢查：裁切流程確認後，先前設定的雙頁模式不應被靜默清空
    // （spec.md 決策 #10——裁切與雙頁是各自獨立的欄位，互不影響）。
    final saved = (await prefsManager.load(bookId)).bookPrefs;
    expect(saved.pdfCropMode, PdfCropMode.manual);
    expect(saved.pdfCropRect, isNotNull);
    expect(saved.dualPageMode, DualPageMode.always);
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

Expected：`flutter test` 全數 PASS（含 Task 1-3 相關的所有測試，以及既有全部測試不受影響）；`flutter analyze` "No issues found!"。

- [ ] **Step 4：Commit**

```bash
cd U:\MyDeveloper\AI\elinkBook
git add app/integration_test/reader_screen_test.dart
git commit -m "test(epic-16): reader_screen_test 新增雙頁模式下手動裁切確認流程的持久化驗證"
```

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：`issues.md` Issue 5 描述的三項既有需求（裁切模式強制單頁預覽、退出後套用同一 `cropRect`、翻頁在裁切模式中暫停）皆已確認由 Issue 3 既有架構滿足，Task 2/3 的測試逐項對應驗證；規劃階段新發現、經人類確認列入範圍的裝置旋轉風險由 Task 1 修正、Task 2 第二個測試驗證。`issues.md` 驗收標準兩點分別對應 Task 3（手動裁切 + 雙頁欄位持久化）與 Task 2（翻頁暫停）。
- **與其他 issue 的邊界**：不觸碰 `CropOverlayView` 本身（`spec.md` 決策 #10 明文排除）；不新增 per-page 裁切矩形（`design.md` 決策 #10 明文排除，YAGNI）；不新增任何 Dart 端建構參數或 method channel 契約（`issues.md` 原始描述已預期本 issue 不需要，經逐一核對現有 `PdfReaderView` 建構子已完整涵蓋 `cropEditModeActive`／`onCropRectSelected`／`dualPageMode` 等本計劃需要的全部參數，確認無遺漏）。
- **無佔位符掃描**：所有步驟皆附完整程式碼、確切檔案路徑與行號範圍，無 "TODO"/"視情況" 字樣；Task 1 的 before/after 完整程式碼區塊、Task 2/3 的完整測試內容皆已逐字寫出。
- **型別/介面一致性**：`PdfReaderView` 建構參數 `cropEditModeActive`／`onCropRectSelected`／`dualPageMode`／`isLandscape` 全部沿用 Issue 3/4 既有簽章，未新增或更動任何欄位名稱；Task 2 的 `_nextPage(tester)`/`_previousPage(tester)` 呼叫沿用 `pdf_dual_page_test.dart` 檔案內既有的頂層函式，未重新定義。
- **Task 執行順序的依賴關係**：Task 1（原生端修正）必須先於 Task 2 第二個測試（裝置旋轉安全驗證）的「確認全數通過」驗收，但 Step 2 特意設計了「Task 1 修正前也能跑（弱保證）」的說明，避免 Task 2/3 完全阻塞在 Task 1 之後才能開工撰寫測試本身；Task 3 與 Task 2 彼此獨立，可平行進行。
- **依 `/superpowers:requesting-code-review` 對本計劃的審查修正**（`tmp/epic-16/reviews/review-plan-issue-5.md`）：
  1. **已採納並強化**：審查 Finding 4 指出 `setPdfPreferences()` 原始修法（只在 `if` 分支內判斷 `cropEditModeActive`）遺漏了 `else` 分支——若 `cropEditModeActive=true` 但三個 `*Changed` 旗標皆為 `false`（例如僅 `contrast`/`brightness` 變動），會落入 `else` 呼叫 `applyFitMode()`／`applyFilters()`，兩者皆可能覆蓋 `renderFullPageForCropPreview()` 設定的 `FIT_CENTER`／無濾鏡狀態。審查建議的修法只補了 `applyFitMode()` 這一處，仍遺漏 `applyFilters()`；已改為更徹底的修法——把 `cropEditModeActive` 檢查提升到整個方法最前面、提前 `return`，一次堵死 `if`／`else` 兩個入口，不留下第二個需要另外守衛的呼叫點（Task 1 Step 1）。
  2. **已採納**：Finding 3 指出 Task 2 原始的旋轉測試只改變 Dart 端 `isLandscape` 語意旗標，未實際改變測試 Surface 尺寸，不會觸發原生 `CropOverlayView.onSizeChanged()`（已查證該方法確實存在，`spec.md`「旋轉發生在手動裁切編輯模式中（審查修正 I-6）」也確實明文要求驗證它）。已在 Task 2 第二個測試補上 `tester.binding.setSurfaceSize()`（比照 Issue 3 `reader_screen_test.dart` 既有的橫向/直向切換手法），讓 `isLandscape` 旗標與實際 Surface 尺寸同步變化。
  3. **不採納**：Finding 1（抽出 `dispatchRendering()`）與 Finding 2（`cropEditModeActive` 改用 State Pattern）皆屬「主觀程式碼味道」、理由皆為假設性的未來場景（「若未來新增更多設定」「未來編輯狀態增多時」）。`setPdfPreferences()` 經 Task 1 修正後仍只有 2 層條件分支（`cropEditModeActive` 早退 + 既有 `if/else`），`cropEditModeActive` 是 epic-4 就存在的單一布林旗標、不是本 issue 新增，兩項建議皆違反 YAGNI，不在本 issue 處理。
