# Issue 4 實作計劃：直排分頁「欄位高度非行高整數倍」導致文字上下裁切——暫行方案評估

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 依 Issue 3 已驗證可行的暫行方案（`EpubPreferences(scroll = true)`），把「換頁模式（分頁 vs 捲動）」做成使用者可即時切換的偏好設定，讓直排（也適用橫排）閱讀時可以選擇捲動模式以規避 Issue 3 記錄的分頁欄位裁切風險；同時修正 Issue 1 遺留的已知技術債——`EpubReaderView.kt` 目前每次呼叫 `submitPreferences()` 都用全新建構的 `EpubPreferences` 覆蓋，一旦同時存在兩種獨立偏好設定（`verticalText`、`scroll`），若不合併就會互相蓋掉對方，本計劃引入的 `currentPreferences` 合併機制正是為此而存在。

**架構：** 沿用 Issue 1／ADR 0003 建立的「雙向即時偏好設定」契約模式，新增對稱的第二組偏好維度：Dart 端 `EpubReaderView` 新增 `pageTurnMode: PageTurnMode?` 建構參數（語意與 `writingMode` 完全對稱：`null` 表示不覆寫、沿用 Readium 預設值分頁；非 null 且變動時透過 `didUpdateWidget` 呼叫原生新增的 `setPageTurnMode`）；原生端 `EpubReaderView.kt` 改為持有 `currentPreferences: EpubPreferences` 欄位，`setWritingMode`／`setPageTurnMode` 皆改為「用 `EpubPreferences.plus()` 合併進 `currentPreferences` 後再送出」，而不是各自建構全新物件覆蓋。`ReaderScreen` 在 AppBar 新增第二顆切換按鈕（沿用 Issue 2 已建立的按鈕慣例），與橫直排切換按鈕共用同一個「書本是否已開啟」啟用條件（`_writingMode != null`）。

**技術棧：** Kotlin、Readium `readium-navigator`/`readium-shared` 3.3.0（`EpubPreferences.scroll: Boolean?`、`EpubPreferences.plus()`，已於 Issue 3 反編譯確認欄位存在）、Dart/Flutter、`integration_test`、`adb`（手動裝置驗證，沿用 Issue 3 已驗證的技巧）。

## ⚠️ 執行前環境確認事項

Task 3、4 的驗證步驟須在真實 Android 裝置/模擬器上執行——執行前請先確認 `flutter devices`（於 `app/` 目錄下）能列出至少一個 Android 裝置/模擬器。

**沿用 Issue 3 已驗證的裝置操作技巧（務必遵守，否則會重蹈 Issue 3 執行過程中遇到的問題）：**
1. **Git Bash 路徑轉換陷阱：** 所有 `adb` 指令若參數包含 `/sdcard/...` 這類路徑，須在指令前加上 `MSYS_NO_PATHCONV=1` 前綴（例如 `MSYS_NO_PATHCONV=1 adb -s <device-id> shell screencap -p /sdcard/foo.png`），否則 Git Bash 的 MSYS 路徑轉換會把它改寫成錯誤的 Windows 路徑導致指令失敗。
2. **殘留 debug 連線陷阱：** 若前一次 `flutter test integration_test/...` 被中斷，下一次執行可能出現 `Error waiting for a debug connection: The log reader stopped unexpectedly`。修復方式：先 `adb -s <device-id> shell am force-stop cc.ugotit.elinkbook`，再 `adb kill-server && adb start-server`，才重新執行。
3. **`adb shell input swipe` 在 `flutter test integration_test` 執行期間不會真正送達原生 PlatformView**：`LiveTestWidgetsFlutterBinding` 會攔截外部注入的觸控事件。若需要在暫時性 scratch 測試檔內模擬翻頁/捲動手勢，必須改用 `WidgetTester.dragFrom()`（測試框架自己送出、會正確經由 `GestureBinding` 轉發到原生 `AndroidView` 的手勢）。
4. **背景等待須設定合理逾時、逾時後直接查看 log 而非無限重試**：裝置建置（含 Gradle 冷啟動）可能需要 1-3 分鐘，暖啟動通常 30-60 秒；若等待超過 3 分鐘仍未看到預期輸出，直接 `tail` log 檔案判斷實際狀態，不要重複安排新的背景等待迴圈而不檢視具體證據。

## 全域限制條件

- `openBook(path)` → `onPageRendered()`/`onError(message)` 既有契約簽章與行為**不變**。
- 沿用既有 per-instance method channel `cc.ugotit.elinkbook/epub_reader_view_$id`，**不**新增獨立 channel。
- 直排模式的**預設換頁行為維持分頁（paginated）不變**——本 issue 不改變任何既有使用者的預設體驗，捲動模式是透過新按鈕的**選用（opt-in）**功能，不自動套用。
- 換頁模式切換**僅限當次 session 即時切換**，比照 Issue 2 橫直排切換的既有決定，不持久化（持久化與三態覆寫 UI 屬 FR-10／`epic-3-fonts-layout`）。
- **必須**修正 `EpubReaderView.kt` 現有的偏好設定覆蓋問題（改用 `currentPreferences` + `EpubPreferences.plus()` 合併）——這不是選擇性的重構，而是本 issue 引入第二種偏好維度後，若不修正就會產生「切換橫直排會把捲動設定重設回分頁」的真實回歸缺陷。
- `ReaderScreen(filePath: String)` 對外建構參數與行為**不變**。
- 換頁模式切換按鈕與橫直排切換按鈕**同樣**在 `_isFixedLayout == true`（定樣式 EPUB）時不顯示（定樣式書籍的分頁本身就是版面的一部分，捲動概念不適用）。
- 所有新增的程式碼註解維持正體中文。
- `flutter analyze` 全程必須維持 `No issues found!`。
- **已知測試限制（沿用 Issue 1 的既有慣例，非本計劃疏漏）：** `EpubReaderView` 的 per-instance method channel 只有在真實原生 `PlatformView` 建立後才會運作，一般 `flutter test`（無裝置）無法驅動、也無法透過 mock channel handler 驗證（`AndroidView` 的 channel id 是平台動態指派，需要真實 PlatformView 才能取得）——這與 Issue 1 完成後的實測結論一致（`app/test/` 底下沒有、也不會有針對 `EpubReaderView` 原生呼叫的 widget test）。因此 Task 1 的 Dart+Kotlin 契約擴充沒有獨立的自動化紅綠測試循環，改以「`flutter analyze` 乾淨＋全量 `flutter test` 無回歸」作為驗證閘門，實際的原生行為驗證留給 Task 3（widget-層級可驗證的 UI 行為）與 Task 4（裝置端真實渲染行為，含關鍵的偏好合併回歸檢查）。

---

### Task 1：`PageTurnMode` 型別 + `EpubReaderView`（Dart+Kotlin）契約擴充，含偏好合併修正

**Files:**
- Create: `app/lib/reader/page_turn_mode.dart`
- Modify: `app/lib/reader/epub_reader_view.dart`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
- Create: `docs/adr/0004-epub-reader-page-turn-mode-contract.md`

**Interfaces:**
- Consumes: Issue 1 建立的 `WritingMode`（型別對稱參考，`app/lib/reader/writing_mode.dart`）、既有 `EpubReaderView` 建構參數
- Produces: `enum PageTurnMode { paginated, scroll }`；`EpubReaderView` 新增 `pageTurnMode: PageTurnMode?` 建構參數；原生端新增 `setPageTurnMode` method channel 指令，供 Task 2（`ReaderScreen` 按鈕）使用

- [ ] **Step 1：撰寫 ADR 0004**

建立 `docs/adr/0004-epub-reader-page-turn-mode-contract.md`：

```markdown
# ADR 0004：`EpubReaderView` 契約擴充為換頁模式（分頁 vs 捲動）＋偏好設定合併修正

## 狀態

已採納

## 背景

Issue 3 的實機驗證與根因調查（見 `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md`）確認：直排（vertical-RL）閱讀模式下，Readium 內建的 `cjk-vertical` ReadiumCSS 把每一欄（頁）的高度設為 CSS `100vh`、未對齊行高整數倍，可能導致分頁模式下畫面上下緣文字被裁切，此為 Readium/CSS 多欄分頁機制在直排書寫模式下的已知上游限制（`readium/swift-toolkit#804`、`readium/readium-css#141`），並非本專案程式碼缺陷，因此無法透過本專案自行維護的 user stylesheet 覆寫徹底修復。Issue 3 Task 5 已驗證 `EpubPreferences(scroll = true)` 可行（改用連續捲動渲染，不涉及欄位高度概念，未觀察到裁切）。

同時，ADR 0003／Issue 1 建立的 `setWritingMode` 實作有一個已知、當時刻意延後處理的技術債（見 `EpubReaderView.kt` 原始碼註解）：每次呼叫都建構全新的 `EpubPreferences`，只有當時要設定的那個欄位有值，其餘欄位一律為預設 `null`。這在只有一種偏好維度（`verticalText`）時不會出問題，但本 issue 引入第二種偏好維度（`scroll`）後，若不修正，切換橫直排會把使用者已設定的捲動偏好重設回分頁（反之亦然），這是一個會實際發生的回歸缺陷，必須與換頁模式功能一併修正。

## 決策

- **Dart → 原生**：新增 `setPageTurnMode(mode: paginated | scroll)`，可在書本開啟後任何時間點呼叫，語意與 ADR 0003 的 `setWritingMode` 完全對稱。
- **原生端**：`EpubReaderView.kt` 新增 `currentPreferences: EpubPreferences` 欄位（初始為 `EpubPreferences()` 全預設值），`setWritingMode`／`setPageTurnMode` 皆改為「用 `EpubPreferences.plus()` 把新的單一欄位設定合併進 `currentPreferences`，再送出合併後的完整物件」，而不是各自建構獨立物件覆蓋。
- **初次開書**：不主動設定 `scroll`（保持 `null`），沿用 Readium 預設值（分頁），對應「不改變既有使用者預設體驗」的產品決策；`setPageTurnMode` 只在使用者手動切換時才會覆寫。
- `openBook`/`onPageRendered`/`onError`/`setWritingMode`（對外行為）既有契約簽章不變。

【未來注意，供 `epic-3-fonts-layout` 設計持久化時參考】`ReaderScreen` 的 `_pageTurnMode` 目前永遠從 `PageTurnMode.paginated` 開始，與原生端 `currentPreferences` 的預設值一致，因此 `didUpdateWidget` 的「值改變才呼叫」邏輯不會漏發送。但若未來持久化功能改成「App 啟動時直接把 `_pageTurnMode` 初始化為使用者上次選擇的值」，且該值恰好也是 `PageTurnMode.paginated`（例如使用者上次就是選分頁），仍然不會有問題；唯有當持久化值與目前寫死的初始值"剛好在某次重建間不變化"時才可能發生「初始值正確但從未真正送達原生端」的情況——這種情況目前的 `didUpdateWidget`-only 設計無法涵蓋，需要屆時額外設計「開書當下就帶入已持久化偏好」的機制（例如擴充 `openBook` 契約或在 `attachNavigator` 時代入 `initialPreferences`）。本 issue 範圍內沒有持久化功能，不需要現在解決，僅記錄於此避免日後被遺忘。

## 後果

- `EpubReaderView.kt` 的 `setWritingMode` 實作方式改變（改為合併而非覆蓋），但對外行為不變（單獨呼叫 `setWritingMode` 的效果與修正前相同）。
- 修正後，`setWritingMode` 與 `setPageTurnMode` 可以任意順序、任意次數交錯呼叫，彼此不會互相重設對方已生效的偏好——這是本次修正要達成的核心後果。
- Dart 端 `EpubReaderView` widget 新增對稱的 `pageTurnMode` 參數與 `didUpdateWidget` 檢查邏輯。
- `ReaderScreen` 新增第二顆 AppBar 切換按鈕，與橫直排切換按鈕共用同一個啟用條件（`_writingMode != null`，代表書本已成功開啟、`navigatorFragment` 已存在）。
- `PdfReaderView` 不受影響。
- 換頁模式切換**不持久化**，比照 Issue 2 的既有決定，維持在本 issue 範圍內的最小變動；持久化與三態覆寫 UI 仍留給 `epic-3-fonts-layout`（FR-10）。

## 曾考慮的替代方案

- **不修正偏好合併問題，只新增 `setPageTurnMode`**：實作最簡單，但會讓「切換橫直排」與「切換換頁模式」互相覆蓋對方的設定，是一個會實際發生、使用者可感知的回歸缺陷（例如使用者先切成捲動模式，再切橫直排，捲動設定會無預警消失），予以排除。
- **兩個偏好各自獨立呼叫 `submitPreferences()`，不合併**：`submitPreferences()` 本身是否會自動與「目前已生效的偏好」合併，取決於 Readium 內部實作，反編譯確認 `EpubPreferences` 建構子本身各欄位皆為獨立傳入、不會自動繼承先前呼叫的值，因此若不在呼叫端自行合併，效果等同上一個被排除的方案，予以排除。
```

- [ ] **Step 2：建立 `page_turn_mode.dart`**

建立 `app/lib/reader/page_turn_mode.dart`：

```dart
/// 換頁模式：分頁（paginated，Readium 預設）或連續捲動（scroll）。對應
/// Readium `EpubPreferences.scroll`（見
/// docs/adr/0004-epub-reader-page-turn-mode-contract.md）。捲動模式是
/// Issue 3 驗證過、用於規避直排分頁欄位裁切風險（`readium/swift-toolkit#804`）
/// 的暫行方案，供使用者選用，不是自動套用的預設行為。
enum PageTurnMode { paginated, scroll }
```

- [ ] **Step 3：擴充 `EpubReaderView`（Dart）**

開啟 `app/lib/reader/epub_reader_view.dart`，把 import 區塊：

```dart
import 'writing_mode.dart';
```

改為：

```dart
import 'page_turn_mode.dart';
import 'writing_mode.dart';
```

把 `class EpubReaderView extends StatefulWidget` 的欄位與建構子：

```dart
class EpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final WritingMode? writingMode;
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;

  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.writingMode,
    this.onLayoutResolved,
  });
```

改為：

```dart
class EpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final WritingMode? writingMode;
  final PageTurnMode? pageTurnMode;
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;

  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.writingMode,
    this.pageTurnMode,
    this.onLayoutResolved,
  });
```

把 `didUpdateWidget`：

```dart
  @override
  void didUpdateWidget(covariant EpubReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newMode = widget.writingMode;
    if (newMode != null && newMode != oldWidget.writingMode) {
      _channel?.invokeMethod('setWritingMode', {
        'mode': newMode == WritingMode.vertical ? 'vertical' : 'horizontal',
      });
    }
  }
```

改為：

```dart
  @override
  void didUpdateWidget(covariant EpubReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newMode = widget.writingMode;
    if (newMode != null && newMode != oldWidget.writingMode) {
      _channel?.invokeMethod('setWritingMode', {
        'mode': newMode == WritingMode.vertical ? 'vertical' : 'horizontal',
      });
    }
    final newPageTurnMode = widget.pageTurnMode;
    if (newPageTurnMode != null && newPageTurnMode != oldWidget.pageTurnMode) {
      _channel?.invokeMethod('setPageTurnMode', {
        'mode': newPageTurnMode == PageTurnMode.scroll ? 'scroll' : 'paginated',
      });
    }
  }
```

也更新檔案開頭的類別文件註解，把：

```dart
/// [writingMode] 為 null 時，開書當下不覆寫橫直排設定，交由 Readium 依書本
/// 語言／閱讀方向自動判斷（判斷結果透過 [onLayoutResolved] 回報一次）；設定
/// 為非 null 且與前次不同時，會即時呼叫原生端切換，不重新開書（見
/// docs/adr/0003-epub-reader-writing-mode-contract.md）。
```

改為：

```dart
/// [writingMode] 為 null 時，開書當下不覆寫橫直排設定，交由 Readium 依書本
/// 語言／閱讀方向自動判斷（判斷結果透過 [onLayoutResolved] 回報一次）；設定
/// 為非 null 且與前次不同時，會即時呼叫原生端切換，不重新開書（見
/// docs/adr/0003-epub-reader-writing-mode-contract.md）。
///
/// [pageTurnMode] 語意與 [writingMode] 對稱：為 null 時不覆寫換頁模式，
/// 沿用 Readium 預設值（分頁）；為非 null 且與前次不同時，即時呼叫原生端
/// 切換為分頁或捲動渲染（見 docs/adr/0004-epub-reader-page-turn-mode-contract.md）。
/// 捲動模式是 Issue 3 驗證過、用於規避直排分頁欄位裁切風險的暫行方案。
```

- [ ] **Step 4：擴充 `EpubReaderView.kt`（原生端），修正偏好合併**

開啟 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`。

把 `onMethodCall` 的 when 區塊：

```kotlin
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                openBook(call.argument<String>("path"))
                result.success(null)
            }
            "setWritingMode" -> {
                setWritingMode(call.argument<String>("mode"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
```

改為：

```kotlin
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                openBook(call.argument<String>("path"))
                result.success(null)
            }
            "setWritingMode" -> {
                setWritingMode(call.argument<String>("mode"))
                result.success(null)
            }
            "setPageTurnMode" -> {
                setPageTurnMode(call.argument<String>("mode"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
```

把類別欄位宣告區塊：

```kotlin
    private val containerId = View.generateViewId()
    private val container = FrameLayout(context).apply { this.id = containerId }
    private val channel = MethodChannel(messenger, "cc.ugotit.elinkbook/epub_reader_view_$id")
    private val fragmentTag = "cc.ugotit.elinkbook.epub_reader_view_$id"
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val previousFragmentFactory = activity.supportFragmentManager.fragmentFactory
    private var installedFragmentFactory: FragmentFactory? = null
    private var publication: Publication? = null
    private var navigatorFragment: EpubNavigatorFragment? = null
    private var pageReported = false
    private var isDisposed = false
```

改為（新增 `currentPreferences`）：

```kotlin
    private val containerId = View.generateViewId()
    private val container = FrameLayout(context).apply { this.id = containerId }
    private val channel = MethodChannel(messenger, "cc.ugotit.elinkbook/epub_reader_view_$id")
    private val fragmentTag = "cc.ugotit.elinkbook.epub_reader_view_$id"
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val previousFragmentFactory = activity.supportFragmentManager.fragmentFactory
    private var installedFragmentFactory: FragmentFactory? = null
    private var publication: Publication? = null
    private var navigatorFragment: EpubNavigatorFragment? = null
    private var pageReported = false
    private var isDisposed = false

    /**
     * 目前已生效的完整偏好設定（見 docs/adr/0004-epub-reader-page-turn-mode-contract.md）。
     * `setWritingMode`／`setPageTurnMode` 都是「合併進這個物件、再整組送出」，而不是
     * 各自建構獨立的 EpubPreferences 覆蓋——否則兩者會互相把對方剛設定好的欄位
     * 重設回預設值。這是 Issue 1 建立 setWritingMode 時就已預期、留待日後補上的合併
     * 機制，本 issue 引入第二種偏好維度時一併補齊。
     *
     * 【未來注意】目前只有使用者手動呼叫 setWritingMode/setPageTurnMode 時才會更新
     * 這個欄位並送出；openBook 完成當下不會主動代入任何已持久化的偏好設定。若未來
     * epic-3-fonts-layout 引入持久化，需要額外設計「開書當下就把已持久化偏好代入
     * currentPreferences 並送出」的機制，屆時再處理，本 issue 範圍內不需要。
     */
    private var currentPreferences = EpubPreferences()
```

把 `setWritingMode` 方法（含其上方文件註解）：

```kotlin
    /**
     * 開書後即時切換橫直排，不重新 openBook（見
     * docs/adr/0003-epub-reader-writing-mode-contract.md）。書本尚未成功
     * 開啟（navigatorFragment 仍為 null）時靜默忽略——Dart 端只會在
     * onPageRendered 觸發之後才送出這個指令，理論上不會發生。
     *
     * 【未來注意】這裡直接建構全新的 EpubPreferences，只有 verticalText 有值、
     * 其餘欄位皆為預設 null。目前專案唯一會呼叫 submitPreferences() 的地方就是
     * 這裡，所以不會有問題；但一旦 epic-3-fonts-layout 引入字型大小/行距/邊距
     * 等其他偏好設定並也需要呼叫 submitPreferences()，這裡就必須改成與「目前
     * 已生效的偏好設定」合併（EpubPreferences 有提供 plus() 運算子可用於合併），
     * 否則每次切換橫直排都會把其他偏好重設回預設值。
     */
    private fun setWritingMode(mode: String?) {
        navigatorFragment?.submitPreferences(EpubPreferences(verticalText = mode == "vertical"))
    }
```

改為：

```kotlin
    /**
     * 開書後即時切換橫直排，不重新 openBook（見
     * docs/adr/0003-epub-reader-writing-mode-contract.md）。書本尚未成功
     * 開啟（navigatorFragment 仍為 null）時靜默忽略——Dart 端只會在
     * onPageRendered 觸發之後才送出這個指令，理論上不會發生。
     *
     * 與 currentPreferences 合併後才送出（見 docs/adr/0004-epub-reader-page-turn-mode-contract.md），
     * 確保不會覆蓋 setPageTurnMode 已設定的 scroll 偏好。
     */
    private fun setWritingMode(mode: String?) {
        currentPreferences = currentPreferences.plus(EpubPreferences(verticalText = mode == "vertical"))
        navigatorFragment?.submitPreferences(currentPreferences)
    }

    /**
     * 開書後即時切換分頁／捲動換頁模式，不重新 openBook（見
     * docs/adr/0004-epub-reader-page-turn-mode-contract.md）。書本尚未成功
     * 開啟時靜默忽略，理由同 setWritingMode。與 currentPreferences 合併後
     * 才送出，確保不會覆蓋 setWritingMode 已設定的 verticalText 偏好。
     */
    private fun setPageTurnMode(mode: String?) {
        currentPreferences = currentPreferences.plus(EpubPreferences(scroll = mode == "scroll"))
        navigatorFragment?.submitPreferences(currentPreferences)
    }
```

- [ ] **Step 5：`flutter analyze` 與全量 `flutter test` 確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter test
```
Expected：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過，無回歸（依全域限制條件說明，本 task 的原生契約擴充本身沒有獨立的自動化紅綠測試循環）。

- [ ] **Step 6：Commit**

```bash
git add docs/adr/0004-epub-reader-page-turn-mode-contract.md app/lib/reader/page_turn_mode.dart app/lib/reader/epub_reader_view.dart app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git commit -m "Add page-turn mode contract with preference-merge fix"
```

---

### Task 2：`ReaderScreen` 換頁模式切換按鈕

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `PageTurnMode`（`app/lib/reader/page_turn_mode.dart`）、`EpubReaderView` 的 `pageTurnMode` 參數
- Produces: `ReaderScreen` 內部新增 `PageTurnMode _pageTurnMode` 狀態（初始值 `PageTurnMode.paginated`）；`Key('reader_page_turn_mode_toggle')` 供測試觀察

- [ ] **Step 1：寫下可離線驗證的失敗測試**

開啟 `app/test/screens/reader_screen_test.dart`，把整份內容改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_screen.dart';

// 依 spec.md「測試決策」：ReaderScreen 分派到 EpubReaderView/PdfReaderView
// 後，實際渲染內容存在於原生 PlatformView 之中，一般 flutter test（無真實
// 裝置/模擬器）無法觀察其渲染結果，因此 EPUB/PDF 兩個分支的「確實渲染出
// 內容」驗證改由 integration_test/reader_screen_test.dart 在真實裝置上
// 執行；此處只保留 flutter test 就能可靠驗證的部分：「不支援格式」分支，
// 以及橫直排切換按鈕、換頁模式切換按鈕在 onLayoutResolved 觸發前的初始
// 狀態（按鈕本身的顯示/隱藏、停用狀態不依賴原生回呼，可離線驗證）。
void main() {
  testWidgets('不支援格式顯示明確錯誤訊息', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.txt'),
      ),
    );

    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.text('不支援的檔案格式'), findsOneWidget);
  });

  testWidgets('EPUB 格式顯示橫直排切換按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.epub'),
      ),
    );

    final finder = find.byKey(const Key('reader_writing_mode_toggle'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，_writingMode 仍為 null，按鈕應為停用狀態',
    );
  });

  testWidgets('EPUB 格式顯示換頁模式切換按鈕，初始為停用狀態且提示切換為捲動',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.epub'),
      ),
    );

    final finder = find.byKey(const Key('reader_page_turn_mode_toggle'));
    expect(finder, findsOneWidget);
    final button = tester.widget<IconButton>(finder);
    expect(
      button.onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，應與橫直排切換按鈕共用同一個停用條件',
    );
    expect(
      button.tooltip,
      '切換為捲動模式',
      reason: '_pageTurnMode 初始值為 PageTurnMode.paginated，按鈕應顯示切換目標（捲動模式）',
    );
  });

  testWidgets('PDF 格式不顯示橫直排切換按鈕與換頁模式切換按鈕', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.pdf'),
      ),
    );

    expect(find.byKey(const Key('reader_writing_mode_toggle')), findsNothing);
    expect(find.byKey(const Key('reader_page_turn_mode_toggle')), findsNothing);
  });
}
```

- [ ] **Step 2：執行測試確認新案例失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/screens/reader_screen_test.dart
```
Expected：前兩項（不支援格式、橫直排切換按鈕初始狀態）通過；新增的「換頁模式切換按鈕」案例因 `Key('reader_page_turn_mode_toggle')` 尚不存在而失敗（`findsOneWidget` 斷言失敗）；最後一項因 `reader_page_turn_mode_toggle` 尚未存在，`findsNothing` 部分會通過但整體測試因換頁模式按鈕案例失敗而顯示測試套件未全數通過。

- [ ] **Step 3：實作 `ReaderScreen` 換頁模式切換按鈕**

開啟 `app/lib/screens/reader_screen.dart`，把 import 區塊：

```dart
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/epub_reader_view.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/writing_mode.dart';
```

改為：

```dart
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/epub_reader_view.dart';
import '../reader/page_turn_mode.dart';
import '../reader/pdf_reader_view.dart';
import '../reader/writing_mode.dart';
```

把 `_ReaderScreenState` 的欄位宣告：

```dart
class _ReaderScreenState extends State<ReaderScreen> {
  _RenderState _state = _RenderState.loading;
  String? _errorMessage;
  WritingMode? _writingMode;
  bool _isFixedLayout = false;
```

改為：

```dart
class _ReaderScreenState extends State<ReaderScreen> {
  _RenderState _state = _RenderState.loading;
  String? _errorMessage;
  WritingMode? _writingMode;
  PageTurnMode _pageTurnMode = PageTurnMode.paginated;
  bool _isFixedLayout = false;
```

在 `_toggleWritingMode` 方法之後新增 `_togglePageTurnMode`：

```dart
  void _toggleWritingMode() {
    setState(() {
      _writingMode = _writingMode == WritingMode.vertical
          ? WritingMode.horizontal
          : WritingMode.vertical;
    });
  }

  void _togglePageTurnMode() {
    setState(() {
      _pageTurnMode = _pageTurnMode == PageTurnMode.scroll
          ? PageTurnMode.paginated
          : PageTurnMode.scroll;
    });
  }
```

把 `_buildAppBarActions`：

```dart
  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (format != BookFormat.epub || _isFixedLayout) return null;
    return [
      IconButton(
        key: const Key('reader_writing_mode_toggle'),
        icon: Icon(
          _writingMode == WritingMode.vertical
              ? Icons.text_rotation_none
              : Icons.text_rotate_vertical,
        ),
        tooltip: _writingMode == WritingMode.vertical ? '切換為橫排' : '切換為直排',
        onPressed: _writingMode == null ? null : _toggleWritingMode,
      ),
    ];
  }
```

改為：

```dart
  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (format != BookFormat.epub || _isFixedLayout) return null;
    return [
      IconButton(
        key: const Key('reader_writing_mode_toggle'),
        icon: Icon(
          _writingMode == WritingMode.vertical
              ? Icons.text_rotation_none
              : Icons.text_rotate_vertical,
        ),
        tooltip: _writingMode == WritingMode.vertical ? '切換為橫排' : '切換為直排',
        onPressed: _writingMode == null ? null : _toggleWritingMode,
      ),
      IconButton(
        key: const Key('reader_page_turn_mode_toggle'),
        icon: Icon(
          _pageTurnMode == PageTurnMode.scroll ? Icons.menu_book : Icons.swap_vert,
        ),
        tooltip:
            _pageTurnMode == PageTurnMode.scroll ? '切換為分頁模式' : '切換為捲動模式',
        // 與橫直排切換按鈕共用同一個啟用條件：_writingMode 非 null 代表
        // onLayoutResolved 已觸發，書本已成功開啟、navigatorFragment 已存在，
        // 此時呼叫 setPageTurnMode 才有意義（見 EpubReaderView.kt 的
        // 靜默忽略邏輯說明）。
        onPressed: _writingMode == null ? null : _togglePageTurnMode,
      ),
    ];
  }
```

把 `_buildNativeView` 中建構 `EpubReaderView` 的部分：

```dart
      case BookFormat.epub:
        return EpubReaderView(
          filePath: widget.filePath,
          writingMode: _writingMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
        );
```

改為：

```dart
      case BookFormat.epub:
        return EpubReaderView(
          filePath: widget.filePath,
          writingMode: _writingMode,
          pageTurnMode: _pageTurnMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
        );
```

也更新類別文件註解，把：

```dart
/// callback 參數，避免違反 spec.md 定義的唯一對外契約。EPUB 格式下的橫直排
/// 切換按鈕（`reader_writing_mode_toggle`）同理：純屬內部狀態管理，僅限當次
/// 閱讀 session 即時切換，不持久化（見 docs/epics/epic-2-vertical-core/
/// design.md「範圍與排除項目」——持久化與三態覆寫 UI 屬 FR-10／epic-3）。
```

改為：

```dart
/// callback 參數，避免違反 spec.md 定義的唯一對外契約。EPUB 格式下的橫直排
/// 切換按鈕（`reader_writing_mode_toggle`）與換頁模式切換按鈕
/// （`reader_page_turn_mode_toggle`，Issue 4 新增）同理：純屬內部狀態管理，
/// 僅限當次閱讀 session 即時切換，不持久化（見 docs/epics/epic-2-vertical-core/
/// design.md「範圍與排除項目」——持久化與三態覆寫 UI 屬 FR-10／epic-3）。
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/screens/reader_screen_test.dart
```
Expected：`All tests passed!`（4 項測試）。

- [ ] **Step 5：全量 `flutter test` 與 `flutter analyze` 確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過（無回歸）；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "Add page-turn mode toggle button to ReaderScreen"
```

---

### Task 3：真機驗證——換頁模式切換按鈕的 UI 行為

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 完成的 `ReaderScreen`；既有 `test/fixtures/sample.epub` fixture
- Produces: 無新介面（純測試驗證）

本 task 不修改任何 production 程式碼——`ReaderScreen` 的實作已由 Task 2 完成，本 task 只新增在真實裝置上驗證「換頁模式切換按鈕點擊後行為」的 `integration_test`，比照 Issue 2 既有的橫直排切換按鈕測試手法。

- [ ] **Step 1：新增 2 項測試**

開啟 `app/integration_test/reader_screen_test.dart`，在檔案最後一個既有的 `testWidgets`（『點擊切換按鈕後，提示文字反轉且不觸發錯誤』，橫直排切換）之後、`main()` 收尾的 `}` 之前，新增：

```dart
  testWidgets('開啟範例 EPUB，換頁模式切換按鈕啟用且初始提示切換為捲動模式',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_page_turn_initial.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    await _pumpUntil(
      tester,
      () => _writingModeToggleReady(tester),
      timeout: const Duration(seconds: 10),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader_page_turn_mode_toggle')),
    );
    expect(button.onPressed, isNotNull);
    expect(button.tooltip, '切換為捲動模式');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('點擊換頁模式切換按鈕後，提示文字反轉且不觸發錯誤', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_page_turn_tap.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    await _pumpUntil(
      tester,
      () => _writingModeToggleReady(tester),
      timeout: const Duration(seconds: 10),
    );

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('reader_page_turn_mode_toggle')))
          .tooltip,
      '切換為捲動模式',
    );

    await tester.tap(find.byKey(const Key('reader_page_turn_mode_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('reader_page_turn_mode_toggle')))
          .tooltip,
      '切換為分頁模式',
    );
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
```

- [ ] **Step 2：於真實裝置/模擬器上執行測試確認全部通過**

Run（於 `app/` 目錄下；`<device-id>` 請替換為 `flutter devices` 列出的實際 Android 裝置/模擬器 ID）：
```bash
flutter test integration_test/reader_screen_test.dart -d <device-id>
```
Expected：`All tests passed!`（既有案例 + 新增 2 項皆通過）。

- [ ] **Step 3：靜態分析、建置與純 Dart 測試確認**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter build apk --debug
flutter test
```
Expected：`flutter analyze` 顯示 `No issues found!`；`flutter build apk --debug` 成功建置；`flutter test` 全數通過，無回歸。

- [ ] **Step 4：Commit**

```bash
git add app/integration_test/reader_screen_test.dart
git commit -m "Add device-verified tests for page-turn mode toggle button"
```

---

### Task 4：手動裝置驗證——捲動模式規避裁切、且偏好合併不互相重置

**Files:**
- Create: `docs/epics/epic-2-vertical-core/qa-issue-4-mitigation-verification.md`

**Interfaces:**
- Consumes: Task 1-3 完成的完整功能；Issue 3 建立的 `test/fixtures/sample_long_vertical.epub`
- Produces: 一份人工視覺 QA 紀錄，供 Task 5 收尾引用

本 task 是**人工視覺 QA 性質**，沒有自動化測試（比照 Issue 3 的驗證方法）。核心目的是驗證兩件事：(a) 捲動模式下拖曳手勢能大幅推進頁面（比照 Issue 3 Task 5 已驗證的現象），(b) **關鍵回歸檢查**：先切換捲動模式、再切換橫直排模式後，捲動偏好是否仍然生效（驗證 Task 1 的 `currentPreferences` 合併修正確實有效）。

**關於直排捲動的物理方向（避免誤判為異常）：** 直排（vertical-RL）書寫模式下，Readium 的連續捲動是**水平方向**（欄位由右至左延伸），不是視覺上直覺聯想的垂直向下捲動——這與 Issue 3 Task 5 觀察到的現象一致（`dragFrom(center, Offset(500, 0))` 這個水平拖曳手勢在捲動模式下會大幅推進內容）。執行 Step 2 判讀截圖時，看到內容以水平方向連續延伸（而非分頁模式下的離散欄位切換）即為捲動模式正常運作的表現，不是測試手勢用錯方向。

- [ ] **Step 1：建立暫時性 scratch 測試檔**

在 `app/integration_test/` 目錄下建立 `_qa_scratch_issue4.dart`（暫時性，驗證完成後刪除，不提交版控，比照 Issue 3 的既有慣例）：

```dart
// 暫時性 QA scratch 測試檔（Issue 4 手動裝置驗證）。
// 用畢即刪，未提交版控。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時（$timeout）：條件未成立');
    }
    await tester.pump(step);
  }
}

bool _writingModeToggleReady(WidgetTester tester) {
  final finder = find.byKey(const Key('reader_writing_mode_toggle'));
  if (finder.evaluate().isEmpty) return false;
  return tester.widget<IconButton>(finder).onPressed != null;
}

Future<void> _hold(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'QA scratch：切換捲動模式後再切換橫直排，驗證捲動偏好未被重置',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_long_vertical.epub', 'qa_issue4_merge.epub');

    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(filePath: samplePath)),
    );

    await _pumpUntil(tester, () => _writingModeToggleReady(tester),
        timeout: const Duration(seconds: 30));

    // 步驟 1：切換為捲動模式。
    await tester.tap(find.byKey(const Key('reader_page_turn_mode_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 步驟 2：切換橫直排（驗證重點：這個呼叫不應該把步驟 1 設定的
    // scroll=true 重設回去）。
    await tester.tap(find.byKey(const Key('reader_writing_mode_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 步驟 3：用與 Issue 3 Task 5 相同的手法，拖曳一次觀察是否仍是
    // 捲動模式的行為（一次拖曳大幅推進，而非分頁模式下幾乎不動）。
    final target = find.byType(EpubReaderView);
    final center = tester.getCenter(target);
    await tester.dragFrom(center, const Offset(500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    print('QA_READY');
    await _hold(tester, 90);
  });
}
```

- [ ] **Step 2：執行並截圖，確認捲動偏好未被橫直排切換重置**

Run（於 `app/` 目錄下；先確保裝置為直立方向並清除殘留狀態）：
```bash
adb -s <device-id> shell am force-stop cc.ugotit.elinkbook
adb -s <device-id> shell settings put system accelerometer_rotation 0
adb -s <device-id> shell settings put system user_rotation 0
flutter test integration_test/_qa_scratch_issue4.dart -d <device-id> > /tmp/qa-issue4.log 2>&1
```
等待 log 出現 `QA_READY`（首次冷建置約 1-3 分鐘，暖建置約 30-60 秒；依「⚠️ 執行前環境確認事項」的逾時原則，勿無限重試背景等待），接著截圖：
```bash
MSYS_NO_PATHCONV=1 adb -s <device-id> shell screencap -p /sdcard/qa-issue4-merge-check.png
MSYS_NO_PATHCONV=1 adb -s <device-id> pull /sdcard/qa-issue4-merge-check.png docs/epics/epic-2-vertical-core/
```

檢視截圖：**若畫面已推進到接近全書尾端（`sample_long_vertical.epub` 的最後段落，第 60 段附近），代表捲動偏好在切換橫直排之後依然生效，`currentPreferences` 合併修正有效；若畫面幾乎沒有移動（停留在開頭段落），代表合併修正未生效、`setWritingMode` 呼叫把捲動偏好重設回了分頁，這是 Task 1 的實作缺陷，必須回頭修正 Task 1 後才能繼續本 task。**

- [ ] **Step 3：清理暫時性測試檔與裝置端截圖**

```bash
rm app/integration_test/_qa_scratch_issue4.dart
adb -s <device-id> shell am force-stop cc.ugotit.elinkbook
MSYS_NO_PATHCONV=1 adb -s <device-id> shell rm /sdcard/qa-issue4-merge-check.png
git status --short
```
Expected：`_qa_scratch_issue4.dart` 不再出現於 `git status` 的追蹤/未追蹤清單中；`qa-issue-4-mitigation-verification.png`（若步驟 2 的截圖保留作為證據）以外，工作樹沒有其他暫時性殘留。

- [ ] **Step 4：撰寫驗證紀錄**

建立 `docs/epics/epic-2-vertical-core/qa-issue-4-mitigation-verification.md`：

```markdown
# Issue 4 驗證紀錄：捲動模式暫行方案與偏好合併回歸檢查

依 `docs/epics/epic-2-vertical-core/issues.md` Issue 4 與
`docs/epics/epic-2-vertical-core/plans/plan-issue-4.md` Task 4 產出。

## 測試環境

| 項目 | 值 |
| --- | --- |
| 裝置型號 | （執行時填入 `adb shell getprop ro.product.model` 的輸出） |
| Android 版本 | （執行時填入 `adb shell getprop ro.build.version.release` 的輸出） |

## 驗證項目

| # | 驗證內容 | 方法 | 結果 |
| --- | --- | --- | --- |
| 1 | 捲動模式下拖曳手勢可大幅推進頁面（比照 Issue 3 Task 5 已驗證現象） | scratch integration_test + `dragFrom` + 截圖比對段落範圍 | （執行時填入：符合／不符合＋觀察到的段落範圍） |
| 2 | **關鍵回歸檢查**：先切換捲動模式、再切換橫直排模式，捲動偏好是否仍生效（`currentPreferences` 合併修正是否有效） | 同一次 scratch 測試內先後觸發兩個切換按鈕，觀察最終拖曳行為是否仍是捲動模式特徵 | （執行時填入：合併修正有效／合併修正失效，需回頭修正 Task 1） |

## 結論

（執行時填入：兩項驗證是否皆通過；若項目 2 失敗，說明具體卡在哪個環節，並指出需要回頭修正 Task 1 的哪個部分）
```

- [ ] **Step 5：Commit**

```bash
git add docs/epics/epic-2-vertical-core/qa-issue-4-mitigation-verification.md docs/epics/epic-2-vertical-core/qa-issue4-merge-check.png
git commit -m "Document scroll-mode mitigation and preference-merge regression check for Issue 4"
```

---

### Task 5：收尾決策紀錄與 issues.md 更新

**Files:**
- Modify: `docs/epics/epic-2-vertical-core/issues.md`

**Interfaces:**
- Consumes: Task 1-4 完成的全部成果
- Produces: Issue 4 最終驗收結論

- [ ] **Step 1：更新 Issue 4 的驗收狀態**

開啟 `docs/epics/epic-2-vertical-core/issues.md`，找到 Issue 4 區塊的 `**Status:** ⚪ 未開始`，改為：

```markdown
**Status:** ✅ 已完成。已決定直排（與橫排）模式的預設換頁行為維持分頁（Readium 預設，不改變既有使用者體驗），並在 `ReaderScreen` AppBar 新增第二顆換頁模式切換按鈕（`reader_page_turn_mode_toggle`），讓使用者可選用捲動模式規避 Issue 3 記錄的分頁欄位裁切風險——技術上對應 Issue 3 Task 5 已驗證可行的 `EpubPreferences(scroll = true)`，並修正了 Issue 1 遺留的偏好設定覆蓋問題（`EpubReaderView.kt` 改用 `currentPreferences` + `EpubPreferences.plus()` 合併，見 ADR 0004），確保橫直排切換與換頁模式切換不會互相重置對方的設定。人工裝置驗證見 `qa-issue-4-mitigation-verification.md`。持久化與三態覆寫 UI（FR-10）仍留給 `epic-3-fonts-layout`。
```

- [ ] **Step 2：確認全域限制條件皆已滿足**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter test
git status --short
```
Expected：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過；`git status --short` 除了本次要 commit 的檔案外，工作樹乾淨（尤其確認 Task 4 的暫時性 scratch 測試檔已不存在）。

- [ ] **Step 3：Commit**

```bash
git add docs/epics/epic-2-vertical-core/issues.md
git commit -m "Finalize Issue 4: default to paginated, offer scroll mode toggle"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍：** Issue 4 描述的「評估並決定解決方向」對應 Task 5 的收尾決策（決定：預設維持分頁、捲動模式作為使用者可選用的暫行方案，不強制切換所有使用者的預設體驗）；「與 epic-3-fonts-layout 既有規劃的換頁模式控制項整合、不新增獨立模式切換 UI」對應 Task 2 沿用 Issue 2 已建立的 AppBar 按鈕慣例（而非設計一套全新的獨立設定頁面）；單元測試要求（`integration_test` 確認無 `onError`／`onPageRendered` 正常觸發、人工視覺 QA 確認裁切消失）對應 Task 3（自動化 UI 行為驗證）與 Task 4（人工視覺 QA，含 Issue 4 自身引入的關鍵回歸檢查）；驗收標準（決定預設渲染方式並記錄理由、測試皆通過）對應 Task 5。
- **佔位符掃描：** 所有步驟皆含完整程式碼、明確指令與預期輸出；Task 4 驗證紀錄範本中標註「執行時填入」的欄位屬於人工視覺 QA 本質上必然存在的實測數據欄位（與 Issue 3 Task 2/3/5 的先例一致），非語焉不詳的佔位符。
- **型別/命名一致性：** `PageTurnMode`／`pageTurnMode`／`setPageTurnMode`／`Key('reader_page_turn_mode_toggle')` 命名與既有 `WritingMode`／`writingMode`／`setWritingMode`／`Key('reader_writing_mode_toggle')` 對稱一致，貫穿 Task 1-4 全程未變。
- **已知、記錄在案但刻意不處理的情形：** 換頁模式切換不持久化，與 Issue 2 橫直排切換的既有決定一致，持久化留給 `epic-3-fonts-layout`（FR-10）——不在本 issue 範圍內展開。若 Task 4 的關鍵回歸檢查（`currentPreferences` 合併是否有效）失敗，計劃已明確指示須回頭修正 Task 1 而非在證據不足的情況下勉強收尾。
- **依 `review-plan-issue-4.md` 審查意見處理：** 審查提出的「拖曳方向應改為負值」一項，與 Issue 3 Task 5 已驗證合併的實測結果（`Offset(500, 0)` 在捲動模式下確實把畫面從書首推進到書尾第 60 段）直接矛盾，不予採納；已在 Task 4 補充「直排捲動為水平方向」的說明，避免誤判。「mode 三態 null 處理」一項與已合併的 `setWritingMode`（Issue 1）既有寫法不一致、且對應的呼叫路徑（Dart 端送出 null mode）本來就不存在，不予採納。「初始偏好同步」一項是本 issue 目前設計下不會發生的問題（`_pageTurnMode` 永遠從與原生端預設值一致的 `PageTurnMode.paginated` 開始），建議的契約擴充是為尚未設計的 `epic-3` 持久化功能超前部署，予以排除，改為在全域限制條件與 Kotlin 註解各補一段「未來注意」供 `epic-3` 設計時參考。「水平捲動方向說明」一項已採納，補進 Task 4。
