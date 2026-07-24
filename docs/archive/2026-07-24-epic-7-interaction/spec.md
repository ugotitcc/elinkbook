# Epic 7 — 互動控制：規格 (Spec)

這是實作 `epic-7-interaction` 的唯一事實來源。決策的完整討論過程與理由請見 `design.md`；與 PRD 字面偏離的決策見 ADR 0009、0010。

> **格子索引慣例**：全文一律 0-indexed、列優先：
> ```
> 0 1 2
> 3 4 5
> 6 7 8
> ```

## 模組 (Modules)

- **`NavZoneMode`／`ZoneAction`**（Dart，新增 `app/lib/reader/nav_zone_mode.dart`／`zone_action.dart`）—— 兩個列舉型別（定義見「資料模型」）。`NavZoneMode` 另提供 top-level 純函式 `resolveZoneActions(NavZoneMode mode, List<ZoneAction> customActions)`：3 個固定模板查表回傳對應 9 格陣列，`custom` 直接回傳 `customActions` 原樣。
- **`zone_hit_test.dart`**（Dart，新增）—— 純函式 `int hitTestZoneIndex({required double dx, required double dy, required double width, required double height})`，見「介面」節演算法定義。PDF／EPUB FXL 兩條 Flutter 端手勢路徑共用同一份實作。
- **`GlobalReaderPrefs`**（Dart，異動 `app/lib/reader/global_reader_prefs.dart`）—— 新增 3 個 non-nullable 欄位：`navZoneMode`、`navZoneCustomActions`（長度固定 9）、`showNavZoneDebugOverlay`。
- **`ReaderPrefsManagerImpl`**（Dart，異動）—— `_loadGlobalPrefs()`／`saveGlobalPrefs()` 新增上述 3 欄位的 `SharedPreferences` 讀寫（見「資料模型」的鍵名、序列化格式與缺席回退值，審查修正）。`resolve()` 內呼叫 `resolveZoneActions()` 算出最終 9 格陣列寫入 `ResolvedPreferences.navZoneActions`——`navZoneMode`／`navZoneCustomActions` 兩個原始欄位不進入 `ResolvedPreferences`（design.md 決策 #9：無單書覆寫層可合併，`ReaderScreen` 只需要解析後的 9 格陣列，不需要知道目前是哪個模板）。
- **`ResolvedPreferences`**（Dart，異動）—— 新增 `navZoneActions: List<ZoneAction>`（non-nullable，長度固定 9）與 `showNavZoneDebugOverlay: bool`（non-nullable）兩欄位。
- **`SettingsScreen`**（Dart，異動 `app/lib/screens/settings_screen.dart`）—— 新增「導航熱區」`ListTile`，導向 `NavZoneSettingsScreen`。
- **`NavZoneSettingsScreen`**（Dart，新增畫面）—— 四選一模板 `RadioListTile`（左翻頁／右翻頁／單手／自訂）；選到「自訂」時顯示 9 格自由編輯器（3×3 排列，每格點擊循環切換 4 種 `ZoneAction` 或彈出選單挑選）；獨立的「顯示熱區輔助線」`SwitchListTile`。儲存自訂設定前呼叫 `isValidCustomZoneConfig()`（見「介面」），未通過（9 格皆非 `menu`）則擋下儲存、顯示錯誤提示（design.md 決策 #7，收斂沉浸模式死鎖風險）。讀寫對象為 `GlobalReaderPrefs`（透過 `ReaderPrefsManager`），不經過 `ResolvedPreferences`（該型別只服務 `ReaderScreen` 的渲染需求，不服務設定畫面）。
- **`ReaderScreen`**（Dart，異動 `app/lib/screens/reader_screen.dart`）——
  - 既有的 FXL 專屬 `_fixedLayoutControlsVisible` 欄位改名／擴大為格式無關的 `_chromeVisible`（`bool`，初始值 `true`）：
    - AppBar 判斷式由現行 `appBar: _isFixedLayout ? null : AppBar(...)` 改為 `appBar: (_isFixedLayout || !_chromeVisible) ? null : AppBar(...)`。
    - `ReaderFooter` 顯示條件在既有 `_resolved?.showFooter ?? true` 之外，再疊加 `&& _chromeVisible`。
    - FXL 既有 4 個懸浮按鈕（返回／設定／書籤切換／筆記）目前各自的 `_isFixedLayout && _fixedLayoutControlsVisible` 判斷，`_fixedLayoutControlsVisible` 一律改讀 `_chromeVisible`（判斷邏輯不變，僅換變數名稱與適用範圍）。
  - 新增單一分派入口 `void _handleZoneAction(ZoneAction action)`：
    - `previousPage`／`nextPage`：呼叫目前格式對應的既有換頁方法（`EpubReaderView`／`PdfReaderView` 的 `nextPage()`／`previousPage()`，透過既有的 `GlobalKey` 存取模式）。
    - `menu`：`setState(() => _chromeVisible = !_chromeVisible)`。
    - `none`：不做事。
  - 新增音量鍵回呼處理：監聽 `MethodChannel('elinkbook/volume_key')` 的 `onVolumeKey` 呼叫（`direction: 'up' | 'down'`），`up` → `_handleZoneAction(ZoneAction.previousPage)`、`down` → `_handleZoneAction(ZoneAction.nextPage)`——**固定映射，不查詢 `navZoneActions`**（FR-18 方向固定，與熱區模式無關，design.md 決策 #19）。掛載時機：`ReaderScreen.initState()`／`dispose()`（畫面存在期間監聽，攔截與否的主要依據是原生端 PlatformView 附加狀態自行判斷，見 `MainActivity.kt` 段落）。
  - **既有 `PopScope`（目前用於裁切模式攔截返回鍵）新增 `onPopInvokedWithResult` 回呼**（審查修正，收斂音量鍵轉場動畫延遲攔截風險）：pop 動作**啟動當下**（早於退場轉場動畫、更早於 `dispose()`）透過新增的 `MethodChannel('elinkbook/volume_key')` 的 `notifyLeavingReader` 呼叫，主動通知原生端立即停止攔截音量鍵——作為 `ReaderViewAttachmentTracker`（見 `MainActivity.kt` 段落）之外的即時 override 訊號，不取代它，只是多一個更快觸發的訊號來源，消除 300-500ms 轉場動畫期間 PlatformView 尚未 `dispose()` 但畫面已在退場的攔截延遲釋放窗口。
  - **PDF／EPUB FXL 熱區疊加層**：`_buildNativeView()` 內、`AndroidView` 外層新增 `Positioned.fill` 的 3×3 `GestureDetector` 疊加層。每格 `key: Key('nav_zone_$index')`，`onTap` 呼叫 `hitTestZoneIndex()`（或直接以固定格子 index 建構，因為格子本身就是依 3×3 `GridView`/`Table` 排列而非動態算座標——見「介面」節釐清）換算出 index 後，查 `_resolved!.navZoneActions[index]` 並呼叫 `_handleZoneAction`。`showNavZoneDebugOverlay == true` 時，同一層額外疊加 9 個格子的邊框與動作文字標籤（比照 `prototype/index.html` 既有除錯輔助線視覺）。兩種畫面的疊加層手勢註冊方式**不同**（審查修正）：
      - **EPUB FXL**：沿用既有 3 欄疊加層「`onTap` + no-op `onHorizontalDragStart`/`onVerticalDragStart` 搶手勢競技場」機制（見既有 `EpubReaderView.dart` FXL 段落，擴充為 9 格）——底層 Readium WebView 有自己的原生滑動手勢，不搶就會漏接觸控落到 WebView。
      - **PDF**：原生層是否有觸控監聽與 `AndroidView` 是否贏得手勢競技場無關；PDF 熱區改由既有 `Listener`（`_handleAnnotationPointerDown`/`_handleAnnotationPointerUp`）手動座標判讀，正確區分點擊與既有長按拖曳劃線手勢（見 `issues.md` Issue 4 完整技術發現段落）。
    - PDF 既有的 `onHorizontalDragEnd` 滑動翻頁 handler（`pdf_reader_view.dart`）整段移除（ADR 0010）；既有長按拖曳框選維持不動，與新的 9 格 `onTap`（無 drag 註冊）共存於同一個 `GestureDetector`。
  - **EPUB 流式熱區**：`EpubReaderView` 新增建構參數 `onZoneTapped: ValueChanged<int>?`（原生端算出 cellIndex 後透過既有 method channel pattern 回呼）。`ReaderScreen` 接上後：`(index) => _handleZoneAction(_resolved!.navZoneActions[index])`。注意此路徑下 `onZoneTapped` **只在該格解析結果為 `menu` 時才會被原生端呼叫**——`previousPage`/`nextPage`/`none` 由原生端依收到的 `navZoneActions` 陣列自行判斷、自行處理，不通知 Dart（見下方 `EpubReaderView.kt` 段落）；因此此路徑收到的 index 對應的 `_resolved!.navZoneActions[index]` 恆為 `menu`，呼叫 `_handleZoneAction` 純粹是為了複用同一個分派入口，不代表 Dart 端會重新判斷 previousPage/nextPage 分支。
- **`EpubReaderView.kt`**（Kotlin，異動，僅流式路徑，`isFixedLayout == false`）——
  - `buildPreferencesFromMap()` 新增解析 `navZoneActions`（`List<String>`，9 個 `ZoneAction.name`，一律非 null）。
  - 新增純 Kotlin 物件 **`NavZoneHitTester`**（新檔案 `NavZoneHitTester.kt`，比照 `EpubFxlScaler`/`PdfImageProcessor` 抽離慣例，JVM 可測，無 Android 依賴）：`fun cellIndex(dx: Float, dy: Float, width: Float, height: Float): Int`，演算法與 Dart 端 `hitTestZoneIndex()` 一致（見「介面」節，兩份平行實作，人工保持同步，見「已知限制」）。
  - 僅在 `isFixedLayout == false` 時向 `EpubNavigatorFragment`（實作 Readium `VisualNavigator`）呼叫 `addInputListener()`；`InputListener.onTap(point)` 回呼內：
    1. `NavZoneHitTester.cellIndex()` 換算 `point` 為格子索引。
    2. 查目前持有的 `navZoneActions[index]`。
    3. 若為 `previousPage`／`nextPage`：若目前 `pageTurnMode == "scroll"`（design.md 決策 #15），忽略、不做事；否則呼叫 `navigator.goBackward()`／`goForward(animated = false)`（比照既有 FXL 三欄熱區 `animated = false` 慣例，避免縮放跳動）。
    4. 若為 `menu`：透過既有 method channel 觸發 `onZoneTapped(index)` 回呼給 Dart。
    5. 若為 `none`：不做事、不通知 Dart。
  - Readium 原生是否已有內建點擊翻頁行為需要停用、`InputListener.onTap()` 是否真能攔下並取代預設行為、`point` 座標系是否需要額外換算，三項皆為「待驗證風險與收斂關卡」節列出的 Spike 待辦，本節僅記錄設計意圖。
- **`PdfReaderView.kt`**——**本 epic 不需修改**。PDF 的熱區判讀、驗證、換頁分派完全發生在 Dart 端（見上方 `ReaderScreen` 段落），原生端既有的 `nextPage`／`previousPage` method call 與渲染管線沿用不變；移除滑動手勢純屬 Dart 端刪除程式碼。
- **`MainActivity.kt`**（Kotlin，異動）——
  - 新增小型執行緒安全計數器 **`ReaderViewAttachmentTracker`**（新檔案，object 單例）：`fun attach()`／`fun detach()`（內部以 `AtomicInteger` 遞增/遞減）、`val isAnyAttached: Boolean get() = count.get() > 0`。`PdfReaderView.kt`／`EpubReaderView.kt` 建構子中呼叫 `attach()`，既有 `override fun dispose()` 內呼叫 `detach()`。
  - 新增 `ReaderViewAttachmentTracker.suppressedUntilReattach`（`Boolean`，初始 `false`）：`MethodChannel("elinkbook/volume_key")` 收到 Dart 端 `notifyLeavingReader` 呼叫時設為 `true`；`attach()` 時重設回 `false`（下次真正開新書時恢復正常攔截）。這是「模組」節 `ReaderScreen` 段落新增之 `PopScope.onPopInvokedWithResult` 即時通知的接收端（審查修正，收斂轉場動畫延遲攔截風險）。
  - 覆寫 `dispatchKeyEvent(event: KeyEvent): Boolean`：當 `event.keyCode` 為 `KEYCODE_VOLUME_UP`／`KEYCODE_VOLUME_DOWN`、`event.action == ACTION_DOWN`、且 `ReaderViewAttachmentTracker.isAnyAttached` 為真、且 `!ReaderViewAttachmentTracker.suppressedUntilReattach` 時，消費事件（回傳 `true`，不呼叫 `super`）並透過 `MethodChannel("elinkbook/volume_key")` 呼叫 Dart 端 `onVolumeKey`（`direction: "up" | "down"`）；其餘情況呼叫 `super.dispatchKeyEvent(event)`，交還系統處理（含正常音量調整）。攔截依據以原生端可自行觀測的 PlatformView 附加狀態為主（design.md 決策 #19，審查修正），輔以 Dart 端 `PopScope` 送出的即時退場訊號提早釋放。

## 資料模型 (Data Model)

### 新增列舉型別

```dart
// app/lib/reader/nav_zone_mode.dart
enum NavZoneMode { leftFlip, rightFlip, oneHand, custom }

// app/lib/reader/zone_action.dart
enum ZoneAction { previousPage, nextPage, menu, none }
```

### 固定模板常數表（`resolveZoneActions()` 查表依據）

| 模板 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| `leftFlip`（左翻頁） | nextPage | menu | previousPage | nextPage | menu | previousPage | nextPage | menu | previousPage |
| `rightFlip`（右翻頁） | previousPage | menu | nextPage | previousPage | menu | nextPage | previousPage | menu | nextPage |
| `oneHand`（單手） | menu | none | menu | previousPage | none | previousPage | nextPage | none | nextPage |

`custom` 無常數列，直接回傳呼叫端傳入的 `navZoneCustomActions`。

### `GlobalReaderPrefs`（新增欄位）

```dart
class GlobalReaderPrefs {
  // ... 既有欄位不變 ...
  final NavZoneMode navZoneMode;               // 預設 rightFlip
  final List<ZoneAction> navZoneCustomActions; // 長度固定 9；navZoneMode != custom 時內容被忽略但仍保留（供使用者切回自訂時還原上次編輯結果）；**首次安裝（SharedPreferences 缺席）回退值為 `rightFlip` 模板的 9 格陣列**（審查修正——不可用全 `none` 陣列，會直接違反「至少 1 格 menu」的驗證規則，見「介面」節）
  final bool showNavZoneDebugOverlay;          // 預設 false
}
```

### `SharedPreferences` 鍵名與序列化（比照既有 `_pageTurnModeKey`／`_screenOrientationKey` 模式）

```
global_reader_nav_zone_mode           -> NavZoneMode.name（字串），缺席回退 rightFlip.name
global_reader_nav_zone_custom_actions -> 9 個 ZoneAction.name 以半形逗號分隔的字串，缺席或解析失敗回退 rightFlip 模板的 9 格陣列（審查修正——不可回退為全 none，會違反自訂模式「至少 1 格 menu」的驗證規則）
global_reader_nav_zone_debug_overlay  -> bool，缺席回退 false
```

### `ResolvedPreferences`（新增欄位）

```dart
class ResolvedPreferences {
  // ... 既有欄位不變 ...
  final List<ZoneAction> navZoneActions;  // 長度固定 9，resolve() 內由 resolveZoneActions() 算出
  final bool showNavZoneDebugOverlay;
}
```

## 介面 (Interfaces)

### `hitTestZoneIndex()` / `NavZoneHitTester.cellIndex()` 演算法（Dart／Kotlin 兩份平行實作，邏輯須一致）

```
輸入：dx, dy（點擊座標，像素，相對容器左上角）、width, height（容器尺寸，像素）
輸出：0-8 的整數格子索引

col = clamp(floor(dx / width * 3), 0, 2)
row = clamp(floor(dy / height * 3), 0, 2)
return row * 3 + col
```

> 釐清：PDF／EPUB FXL 的 9 格疊加層若以 `Table`/`GridView` 搭配固定 3×3 排列的個別 `GestureDetector` 實作（每個格子本身就是獨立 widget、`onTap` 不帶座標），則不需要在 Dart 端呼叫 `hitTestZoneIndex()`——格子索引由 widget 在陣列中的位置直接決定。是否採用「單一大 `GestureDetector` + 事後座標換算」或「9 個獨立小 `GestureDetector`」屬於 Scrum Master／實作階段的元件實作細節，兩者最終行為等價；`hitTestZoneIndex()` 主要服務 **`NavZoneHitTester`（Kotlin 端）**——原生端收到的是單一 `InputListener.onTap(point)` 座標回呼，沒有「9 個獨立原生 View」的等價物，必須用座標換算。

### 自訂熱區驗證契約

```dart
bool isValidCustomZoneConfig(List<ZoneAction> actions) =>
    actions.length == 9 && actions.contains(ZoneAction.menu);
```

`NavZoneSettingsScreen` 儲存前呼叫；回傳 `false` 時擋下儲存動作（design.md 決策 #7）。

### 原生 Method Channel 契約異動

#### EPUB 頻道 (`cc.ugotit.elinkbook/epub_reader_view_$id`)
- **`openBook`** / **`setPreferences`**：Map 新增 `navZoneActions: List<String>`（9 個 `ZoneAction.name`，一律非 null，`ReaderScreen` 保證傳入已解析完成的陣列）。
- 新增原生→Dart 回呼 **`onZoneTapped`**：`{ "cellIndex": Int }`，僅在該格解析結果為 `menu` 時觸發（見「模組」節 `EpubReaderView.kt` 段落）。

#### PDF 頻道 (`cc.ugotit.elinkbook/pdf_reader_view_$id`)
- 無異動——PDF 熱區完全由 Dart 端處理，既有 `nextPage`／`previousPage` method call 沿用不變。

#### 新增音量鍵頻道 (`elinkbook/volume_key`)
- 原生→Dart 回呼 **`onVolumeKey`**：`{ "direction": "up" | "down" }`。
- Dart→原生 **`notifyLeavingReader`**（審查修正，新增）：無參數。`ReaderScreen` 的 `PopScope.onPopInvokedWithResult` 於 pop 動作啟動當下呼叫，設定 `ReaderViewAttachmentTracker.suppressedUntilReattach = true`，立即停止攔截音量鍵，不等待 `dispose()`。
- 攔截判斷依據：`ReaderViewAttachmentTracker.isAnyAttached && !suppressedUntilReattach`（見「模組」節 `MainActivity.kt` 段落）。

## 待驗證風險與收斂關卡

比照 `epic-16-dual-page` 慣例，以下風險須在進入 Scrum Master 拆解前以獨立 Spike 工單驗證並回填結論，不得留待實作階段才發現：

> **Issue 1 驗證結果（2026-07-18）：本節 3 項風險已於 Issue 1 spike 全數驗證，見 `reviews/spike-epub-inputlistener.md`，Issue 6 可依本節既有規劃直接採用 `InputListener` 路線實作，不需退回自行實作方案。**三項結論摘要：(1) `EpubNavigatorFragment` 對單純點擊無內建翻頁反應，不需要停用步驟；(2) `InputListener.onTap()` 攔截可靠，`goForward()`/`goBackward()` 呼叫與點擊次數嚴格 1:1，無重複觸發；(3) `TapEvent.point` 為 `publicationView`（=`fragmentView`，兩者尺寸相同、無 letterbox）本地座標，`NavZoneHitTester.cellIndex()` 可直接使用、不需額外轉換公式。實務提醒：部分裝置（至少驗證用的 TCL 9491G）系統層會過濾 `Log.d`（Debug 等級）的 `logcat` 輸出，Issue 6 除錯插樁建議直接採用 `Log.i` 或更高等級。

1. **Readium `EpubNavigatorFragment` 既有點擊翻頁行為是否需要先停用**：若 Readium 原生已有預設的單擊翻頁手勢，需確認 `addInputListener()` 註冊後是否會與其共存、疊加，或必須先透過 `EpubPreferences` 顯式停用。
2. **`InputListener.onTap()` 回呼是否真的能攔下並取代預設行為**：驗證呼叫 `goForward()`／`goBackward()` 後，是否會與 Readium 自身可能存在的手勢處理重複觸發（例如同一次點擊換兩頁）。
3. **`InputListener` 的座標系統**：確認 `onTap(point: PointF)` 回傳的座標是相對整個 `EpubNavigatorFragment` view、還是相對可視內容區域（可能因 letterbox 或縮放置中偏移而不同），據此決定 `NavZoneHitTester.cellIndex()` 是否需要額外的座標轉換前處理。

若上述任一項驗證結果與本文件假設不符，對應段落需在 Spike 完成後更新，不得由實作者在工單執行階段自行決定退回方案。

## 測試決策 (Testing Decisions)

### 1. 單元測試 (Unit Tests，`flutter test`，無需裝置)
- `hitTestZoneIndex()`：邊界值測試（格線正上方座標、畫面四角、正中心），確認回傳 0-8 且 `clamp` 不因浮點誤差在邊界產生 index 9 或負數。
- `resolveZoneActions()`：3 個固定模板回傳的 9 格陣列與本文件常數表逐格比對；`custom` 回傳傳入陣列原樣（不重新排序/轉換）。
- `isValidCustomZoneConfig()`：全部非 `menu` → `false`；恰好 1 格 `menu` → `true`；多格 `menu` → `true`；長度不為 9 → `false`。
- `GlobalReaderPrefs` 新欄位的 `copyWith`／`==`／`hashCode`。
- `ReaderPrefsManagerImpl._loadGlobalPrefs()`／`saveGlobalPrefs()`：新 3 欄位讀寫往返（round-trip），比照既有 `pageTurnMode` 測試模式；`navZoneCustomActions` 逗號分隔字串序列化/反序列化含邊界情況（空字串、缺鍵時的預設值回退）。

### 2. JVM 單元測試 (Kotlin，`app/android` 既有 JVM test 慣例，比照 `PdfImageProcessor`/`EpubFxlScaler`)
- `NavZoneHitTester.cellIndex()`：與 Dart 端 `hitTestZoneIndex()` 相同的邊界值測試案例，確認兩端演算法輸出一致（建議測試檔內以註解交叉引用 Dart 端測試檔案位置，降低未來兩端演算法悄悄分岔的風險）。

### 3. Widget 測試 (Widget Tests，`flutter test`，無需裝置)
- `NavZoneSettingsScreen`：四選一模板切換觸發對應 `GlobalReaderPrefs` 更新；選到「自訂」後 9 格編輯器逐格點擊循環切換 4 種動作；儲存時全部非 `menu` 會被擋下（斷言錯誤提示存在、儲存回呼未被觸發）；「顯示熱區輔助線」開關觸發更新。
- `ReaderScreen` 沉浸模式：透過直接呼叫 `_handleZoneAction`（或比照既有 `PdfReaderView.jumpToPage` 強型別 static helper 模式，新增一個測試可呼叫的入口）驗證 AppBar／`ReaderFooter` 依 `_chromeVisible` 正確顯示/隱藏；驗證呼叫 `_handleZoneAction(ZoneAction.previousPage/nextPage)` 後 `_chromeVisible` 不變（design.md 決策 #14）。
- PDF／FXL 熱區疊加層：驗證 9 個 `Key('nav_zone_$index')` widget 存在且可點擊（`find.byKey`），點擊後觸發對應的 `_handleZoneAction` 分支（可透過 mock `GlobalKey`/callback 驗證）。

### 4. `integration_test`（真機/模擬器，比照專案既有兩層測試架構，`-d <device-id>`）
- EPUB 流式：Spike 驗證通過後，真機點擊左/中/右熱區驗證實際換頁與沉浸模式切換（AppBar 存在與否作為觀察點，比照既有 `Key('reader_loading_indicator')`／`Key('reader_error_text')` 慣例）。
- PDF：真機點擊 9 格熱區驗證換頁/沉浸模式，並與既有長按拖曳劃線手勢（`epic-6-annotations` Issue 3 既有 `integration_test`）交叉操作驗證不誤觸發（ADR 0008 已標記的未收斂風險，本 epic 須收斂）。
- FXL：既有 3 欄熱區 `integration_test`（`epic-16-dual-page` Issue 9 既有測試）擴充/改寫為 9 格版本，「無動作」格維持既有的觸控攔截行為驗證（不穿透到底層 WebView，design.md 決策 #17）。
- 音量鍵：真機/模擬器模擬音量鍵事件（`adb shell input keyevent`），驗證 `ReaderScreen` 內翻頁；驗證按下返回鍵觸發 pop 動作的**當下**（轉場動畫進行中，PlatformView 尚未 `dispose()`）音量鍵已恢復系統音量調整，而非等轉場動畫結束才恢復（審查修正，驗證 `notifyLeavingReader` 即時釋放機制）。

## 已知限制

- **EPUB 流式與 FXL 熱區底層機制不同、演算法各自平行實作**（design.md 決策 #18）：流式用原生 `InputListener` + `NavZoneHitTester.cellIndex()`（Kotlin）、FXL 用 Flutter `GestureDetector` 疊加層（Dart，格子索引由排版位置直接決定，非座標換算）、PDF 用 `hitTestZoneIndex()`（Dart，座標換算）。三者對「同一份 `navZoneActions` 陣列」的判讀邏輯需要人工保持一致，未來若格線定義調整（例如改為非均等三等分），須同步檢查三處。
- **PDF 手勢競技場尚未真機驗證**（延續 ADR 0008 風險，本 epic 目標收斂）：新的 9 格 `onTap` 與既有 `onLongPress*` 框選共存於同一 `GestureDetector`，本文件假設 Flutter 手勢框架能依時長/移動距離正確區分，須在 `integration_test` 真機階段確認不會互相誤觸發。
- **`ReaderViewAttachmentTracker` 假設同時最多一個原生 Reader View 附加**：目前架構下 `ReaderScreen` 同時只會掛載一個 `EpubReaderView` 或 `PdfReaderView`，計數器語意（>0 即攔截）在此前提下正確；若未來架構演化出「單畫面同時掛載兩個 Reader View」的情境（目前不支援、也不在規劃中），此計數器邏輯仍然正確但值得留意。
