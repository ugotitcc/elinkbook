# Epic 7 Issue 7 — FR-18 音量鍵翻頁 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 實作硬體音量鍵翻頁（FR-18）：原生 `MainActivity.dispatchKeyEvent()` 攔截 `KEYCODE_VOLUME_UP`/`KEYCODE_VOLUME_DOWN`，方向固定映射（不查詢熱區設定），透過新的 `elinkbook/volume_key` MethodChannel 通知 `ReaderScreen` 翻頁；離開閱讀畫面（含轉場動畫期間）後音量鍵須立即恢復系統原生音量調整。

**Architecture:** 新增純 Kotlin 單例 `ReaderViewAttachmentTracker`（`AtomicInteger` 計數器 + `suppressedUntilReattach` 旗標），由 `EpubReaderView`/`PdfReaderView` 的建構（`init`）與 `dispose()` 呼叫 `attach()`/`detach()`，讓 `MainActivity.dispatchKeyEvent()` 能依「原生端可自行觀測的真實狀態」（而非 Dart 主動通知的 async 旗標）判斷是否攔截音量鍵——這是 design.md 決策 #19 的核心：PlatformView 附加/移除是唯一無額外非同步延遲的可靠訊號。`ReaderScreen` 新增 `elinkbook/volume_key` 頻道的雙向使用：接收原生端 `onVolumeKey({"direction": "up"|"down"})` 回呼並轉呼叫既有的 `_handleZoneAction()`（Issue 4 已建立，`up` 固定對應 `previousPage`、`down` 固定對應 `nextPage`，**不查詢** `_resolved!.navZoneActions`）；既有 `PopScope` 新增 `onPopInvokedWithResult`，pop 動作**啟動當下**（早於退場轉場動畫、更早於 `dispose()`）呼叫 `notifyLeavingReader`，讓原生端立即設定 `suppressedUntilReattach = true`，不必等待 300-500ms 轉場動畫結束、`dispose()` 呼叫 `detach()` 才釋放攔截。

**Tech Stack:** Kotlin（`AtomicInteger`、`FlutterFragmentActivity.dispatchKeyEvent()`、`MethodChannel`）、Dart（`flutter/services.dart` 的 `MethodChannel`、`PopScope.onPopInvokedWithResult`）、既有 JVM 單元測試慣例（`app/android/app/src/test/kotlin`，`./gradlew :app:testDebugUnitTest`）、`flutter_test`（`TestDefaultBinaryMessengerBinding` 模擬全域 MethodChannel 雙向呼叫）、`integration_test`（真實裝置，驗證 Dart 端事件分派管線在真機原生渲染下確實生效；`dispatchKeyEvent()` 本身攔截真實硬體按鍵留給人工驗證清單，理由見 Task 5）。

## Global Constraints

- **方向固定映射，不查詢熱區設定**（design.md 決策 #19，spec.md「新增音量鍵頻道」）：`up` → `ZoneAction.previousPage`、`down` → `ZoneAction.nextPage`，一律呼叫既有的 `_handleZoneAction(ZoneAction action)`（Issue 4 已建立，`app/lib/screens/reader_screen.dart`），不新增另一套換頁邏輯。
- **攔截依據為原生端可自行觀測的真實狀態**（design.md 決策 #19 審查修正）：`ReaderViewAttachmentTracker.isAnyAttached && !ReaderViewAttachmentTracker.suppressedUntilReattach`。不得改回「由 Dart 經 MethodChannel 主動通知的 async 旗標」單獨判斷攔截與否——那存在理論上的競態窗口。
- **`ReaderViewAttachmentTracker` 假設同時最多一個原生 Reader View 附加**（spec.md「已知限制」）：目前架構下 `ReaderScreen` 同時只會掛載一個 `EpubReaderView` 或 `PdfReaderView`，計數器語意（`> 0` 即攔截）在此前提下正確，不需要處理「同時多個」情境。
- MethodChannel 名稱固定為 `elinkbook/volume_key`：
  - 原生→Dart `onVolumeKey`：`{"direction": "up" | "down"}`
  - Dart→原生 `notifyLeavingReader`：無參數
- `KeyEvent` 判斷條件：`event.keyCode` 為 `KeyEvent.KEYCODE_VOLUME_UP` 或 `KeyEvent.KEYCODE_VOLUME_DOWN`。攔截生效時（`isAnyAttached && !suppressedUntilReattach`）**`ACTION_DOWN`／`ACTION_UP` 皆消費**（回傳 `true`，不呼叫 `super`），但只在 `ACTION_DOWN` 時才透過 `onVolumeKey` 通知 Dart 翻頁——放行 `ACTION_UP` 會讓系統音量提示 UI（音量條 Toast）在部分機型上仍意外跳出，這是已知的 Android 陷阱（審查修正，偏離 issues.md 原始「僅 ACTION_DOWN」文字，經人類確認採納）。
- FR-36（音量鍵總開關）留給 `epic-14-system-settings`；本 issue 音量鍵翻頁**預設永遠啟用、無法關閉**，不新增任何設定 UI、不讀寫 `GlobalReaderPrefs`。
- 本專案 JVM 單元測試無法涵蓋任何 Android 框架類別（`Activity`/`KeyEvent` 等）——既有 `PdfReaderViewTest.kt`/`NavZoneHitTesterTest.kt` 皆只測試不依賴 Android 型別的純 Kotlin 邏輯，本專案未引入 Robolectric。`MainActivity.dispatchKeyEvent()` 本身因此不可 JVM 測試，只能編譯驗證（`flutter build apk --debug`）+ 真機 `integration_test`/人工驗證。
- Android minSdk 政策門檻為 API 30（NFR-6），實際 `minSdk` 為 24（既有相依套件疊加決定，不受本 issue 影響，不得再收緊）。
- `flutter analyze` 全程須保持乾淨。
- 套件名稱為 `elinkbook`（測試檔 import 一律 `package:elinkbook/...`）。
- Kotlin 套件名稱一律 `cc.ugotit.elinkbook`。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderViewAttachmentTracker.kt` | 新增 | 執行緒安全計數器單例：`attach()`/`detach()`/`isAnyAttached`/`suppressedUntilReattach` |
| `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/ReaderViewAttachmentTrackerTest.kt` | 新增 | Task 1 JVM 單元測試 |
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` | 修改 | `init`/`dispose()` 呼叫 `ReaderViewAttachmentTracker.attach()`/`detach()`（Task 2） |
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt` | 修改 | 同上（Task 2） |
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt` | 修改 | 新增 `elinkbook/volume_key` `MethodChannel`；覆寫 `dispatchKeyEvent()`（Task 3） |
| `app/lib/screens/reader_screen.dart` | 修改 | 新增 `_volumeKeyChannel` 監聽 `onVolumeKey`；`PopScope.onPopInvokedWithResult` 送出 `notifyLeavingReader`（Task 4） |
| `app/test/screens/reader_screen_test.dart` | 修改 | 新增 Task 4 widget test |
| `app/integration_test/volume_key_test.dart` | 新增 | 真機驗證：Dart 端事件分派管線自動化驗證＋人工驗證清單（Task 5） |

---

### Task 1：`ReaderViewAttachmentTracker` 計數器單例

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderViewAttachmentTracker.kt`
- Test: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/ReaderViewAttachmentTrackerTest.kt`

**Interfaces:**
- Consumes：無（純 Kotlin，無 Android 依賴，比照 `NavZoneHitTester`/`EpubFxlScaler` 既有抽離慣例）
- Produces：`object ReaderViewAttachmentTracker { val isAnyAttached: Boolean; var suppressedUntilReattach: Boolean; fun attach(); fun detach() }`，供 Task 2（`EpubReaderView`/`PdfReaderView`）與 Task 3（`MainActivity`）使用

- [x] **Step 1：寫失敗測試**

建立 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/ReaderViewAttachmentTrackerTest.kt`：

```kotlin
package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * ReaderViewAttachmentTracker 是頂層 object（單例），狀態會在同一個 JVM
 * 測試行程內跨測試方法殘留。每個測試案例刻意平衡自己呼叫的
 * attach()/detach() 次數，並只斷言呼叫前後的「相對」狀態變化，不假設一個
 * 全域的初始 0 基準——避免測試執行順序影響結果。
 */
class ReaderViewAttachmentTrackerTest {

    @Test
    fun `attach 後 isAnyAttached 為 true，detach 後恢復呼叫前狀態`() {
        val before = ReaderViewAttachmentTracker.isAnyAttached
        ReaderViewAttachmentTracker.attach()
        assertTrue(ReaderViewAttachmentTracker.isAnyAttached)
        ReaderViewAttachmentTracker.detach()
        assertEquals(before, ReaderViewAttachmentTracker.isAnyAttached)
    }

    @Test
    fun `多次 attach 後單次 detach 仍為 attached`() {
        ReaderViewAttachmentTracker.attach()
        ReaderViewAttachmentTracker.attach()
        assertTrue(ReaderViewAttachmentTracker.isAnyAttached)
        ReaderViewAttachmentTracker.detach()
        assertTrue(ReaderViewAttachmentTracker.isAnyAttached)
        ReaderViewAttachmentTracker.detach() // 平衡第二次 attach()，恢復測試前狀態
    }

    @Test
    fun `suppressedUntilReattach 設為 true 後，attach() 會重設回 false`() {
        ReaderViewAttachmentTracker.suppressedUntilReattach = true
        assertTrue(ReaderViewAttachmentTracker.suppressedUntilReattach)
        ReaderViewAttachmentTracker.attach()
        assertFalse(ReaderViewAttachmentTracker.suppressedUntilReattach)
        ReaderViewAttachmentTracker.detach() // 平衡呼叫，恢復測試前狀態
    }

    @Test
    fun `detach() 不會重設 suppressedUntilReattach，只有 attach() 才會`() {
        ReaderViewAttachmentTracker.attach()
        ReaderViewAttachmentTracker.suppressedUntilReattach = true
        ReaderViewAttachmentTracker.detach()
        assertTrue(ReaderViewAttachmentTracker.suppressedUntilReattach)
        ReaderViewAttachmentTracker.suppressedUntilReattach = false // 恢復測試前狀態
    }

    @Test
    fun `detach() 呼叫次數多於 attach()，計數器下限保護在 0（單次 attach 即恢復 attached）`() {
        val before = ReaderViewAttachmentTracker.isAnyAttached
        ReaderViewAttachmentTracker.detach() // 多餘的 detach()，模擬異常生命週期情境
        ReaderViewAttachmentTracker.detach() // 再一次多餘的 detach()
        ReaderViewAttachmentTracker.attach()
        assertTrue(
            "計數器應保持下限在 0，單次 attach() 後即應為 attached，不因先前多餘 detach() " +
                "累積負數而需要多次 attach() 才能恢復",
            ReaderViewAttachmentTracker.isAnyAttached,
        )
        ReaderViewAttachmentTracker.detach() // 恢復到測試前狀態
        assertEquals(before, ReaderViewAttachmentTracker.isAnyAttached)
    }
}
```

- [x] **Step 2：執行測試確認失敗**

在 `app/android` 目錄下執行：

```bash
./gradlew :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.ReaderViewAttachmentTrackerTest"
```

Expected：編譯失敗，`unresolved reference: ReaderViewAttachmentTracker`（比照 Issue 6 既有慣例，因跨磁碟機 Gradle 環境問題改用 `:app:` 範圍限定，而非全專案 `testDebugUnitTest`）。

- [x] **Step 3：寫最小實作**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderViewAttachmentTracker.kt`：

```kotlin
package cc.ugotit.elinkbook

import java.util.concurrent.atomic.AtomicInteger

/**
 * 追蹤目前是否有原生 Reader PlatformView（EpubReaderView／PdfReaderView）
 * 附加於畫面上，供 MainActivity.dispatchKeyEvent()（epic-7-interaction
 * Issue 7）判斷是否應攔截音量鍵。攔截依據刻意採用原生端可自行觀測的真實
 * 狀態，而非 Dart 端經 MethodChannel 主動通知的 async 旗標（design.md
 * 決策 #19 審查修正：async 旗標與 Flutter route 離開之間存在理論上的
 * 競態窗口，PlatformView 附加/移除是原生端唯一可靠、無額外非同步延遲的
 * 真實訊號）。
 *
 * 假設同時最多一個原生 Reader View 附加（見 spec.md「已知限制」）：目前
 * 架構下 ReaderScreen 同時只會掛載一個 EpubReaderView 或 PdfReaderView，
 * 計數器語意（>0 即攔截）在此前提下正確。
 */
object ReaderViewAttachmentTracker {
    private val count = AtomicInteger(0)

    /** 目前是否有任一 Reader PlatformView 附加。 */
    val isAnyAttached: Boolean
        get() = count.get() > 0

    /**
     * Dart 端 ReaderScreen 的 PopScope.onPopInvokedWithResult 於 pop 動作
     * 啟動當下（早於退場轉場動畫、更早於 PlatformView.dispose()）透過
     * notifyLeavingReader method channel 呼叫設為 true，讓
     * dispatchKeyEvent() 立即停止攔截音量鍵，不必等待 detach() 才釋放
     * （轉場動畫期間 PlatformView 尚未 dispose，isAnyAttached 仍為
     * true）。attach() 時重設回 false——下次真正開新書時恢復正常攔截。
     */
    @Volatile
    var suppressedUntilReattach: Boolean = false

    /** EpubReaderView／PdfReaderView 建構時（init 區塊）呼叫。 */
    fun attach() {
        count.incrementAndGet()
        suppressedUntilReattach = false
    }

    /**
     * EpubReaderView／PdfReaderView 的 dispose() 內呼叫。下限保護在 0
     * （`maxOf(0, it - 1)`，審查修正）：Flutter PlatformView 生命週期保證
     * 每個實例只會 dispose() 一次，正常路徑不會重複 detach()；但用
     * `getAndUpdate` 保護下限，避免任何未預期的重複呼叫讓計數器變負數、
     * 需要多次 attach() 才能恢復 isAnyAttached，是零成本的防禦性寫法。
     */
    fun detach() {
        count.getAndUpdate { maxOf(0, it - 1) }
    }
}
```

- [x] **Step 4：執行測試確認通過**

```bash
./gradlew :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.ReaderViewAttachmentTrackerTest"
```

Expected：`BUILD SUCCESSFUL`，5/5 測試通過。

- [x] **Step 5：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderViewAttachmentTracker.kt app/android/app/src/test/kotlin/cc/ugotit/elinkbook/ReaderViewAttachmentTrackerTest.kt
git commit -m "feat(epic-7): 新增 ReaderViewAttachmentTracker 音量鍵攔截狀態計數器"
```

---

### Task 2：`EpubReaderView`/`PdfReaderView` 佈線 `attach()`/`detach()`

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（`init` 區塊約第 205-207 行；`dispose()` 開頭約第 1238 行）
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`（`init` 區塊約第 345-347 行；`dispose()` 開頭約第 1182 行）

**Interfaces:**
- Consumes：Task 1 的 `ReaderViewAttachmentTracker.attach()`/`detach()`
- Produces：`ReaderViewAttachmentTracker.isAnyAttached` 在任一 Reader PlatformView 存在期間為 `true`，供 Task 3 使用

- [x] **Step 1：`EpubReaderView.kt` 佈線**

在 `EpubReaderView.kt` 找到現有的：

```kotlin
    init {
        channel.setMethodCallHandler(this)
    }
```

改為：

```kotlin
    init {
        channel.setMethodCallHandler(this)
        ReaderViewAttachmentTracker.attach()
    }
```

在同檔案找到 `override fun dispose() {` 的第一行 `isDisposed = true`，改為：

```kotlin
    override fun dispose() {
        isDisposed = true
        ReaderViewAttachmentTracker.detach()
        scope.cancel()
```

（其餘 `dispose()` 內容不變。）

- [x] **Step 2：`PdfReaderView.kt` 佈線**

在 `PdfReaderView.kt` 找到現有的：

```kotlin
    init {
        channel.setMethodCallHandler(this)
    }
```

改為：

```kotlin
    init {
        channel.setMethodCallHandler(this)
        ReaderViewAttachmentTracker.attach()
    }
```

在同檔案找到：

```kotlin
    override fun dispose() {
        removeHighlightSelectionOverlay()
```

改為：

```kotlin
    override fun dispose() {
        ReaderViewAttachmentTracker.detach()
        removeHighlightSelectionOverlay()
```

（其餘 `dispose()` 內容不變。）

- [x] **Step 3：執行既有測試確認無回歸**

```bash
cd app/android && ./gradlew :app:testDebugUnitTest
```

Expected：`BUILD SUCCESSFUL`，全部既有 JVM 測試（含 Task 1 新增的 4 個）皆通過——`attach()`/`detach()` 佈線純粹是計數器副作用，不改變 `EpubReaderView`/`PdfReaderView` 任何既有可觀察行為，故既有測試不需修改。

```bash
cd app && flutter analyze
```

Expected：`No issues found!`

```bash
cd app && flutter build apk --debug
```

Expected：`BUILD SUCCESSFUL`（純編譯驗證，確認 Kotlin 端改動語法正確、可成功建置；本步驟無自動化斷言，人工檢查指令結尾輸出即可）。

- [x] **Step 4：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt
git commit -m "feat(epic-7): EpubReaderView/PdfReaderView 佈線 ReaderViewAttachmentTracker"
```

---

### Task 3：`MainActivity.kt` — `elinkbook/volume_key` 頻道 + `dispatchKeyEvent()` 攔截

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`

**Interfaces:**
- Consumes：Task 1 的 `ReaderViewAttachmentTracker.isAnyAttached`/`suppressedUntilReattach`
- Produces：`elinkbook/volume_key` `MethodChannel`——原生→Dart `onVolumeKey({"direction": "up"|"down"})`；Dart→原生 `notifyLeavingReader`（設定 `suppressedUntilReattach = true`）。供 Task 4（Dart 端接收）與 Task 5（真機驗證）使用

- [x] **Step 1：新增 import 與欄位**

在 `MainActivity.kt` 現有 import 區塊：

```kotlin
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.webkit.WebView
```

新增一行 `import android.view.KeyEvent`，改為：

```kotlin
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.webkit.WebView
```

在現有的：

```kotlin
    private var pendingFolderPickResult: MethodChannel.Result? = null
```

之後新增：

```kotlin
    /**
     * 音量鍵事件通道（epic-7-interaction Issue 7）。dispatchKeyEvent()
     * 攔截音量鍵後透過此頻道呼叫 Dart 端 onVolumeKey；也接收 Dart 端於
     * PopScope pop 動作啟動當下送出的 notifyLeavingReader 呼叫，立即設定
     * ReaderViewAttachmentTracker.suppressedUntilReattach = true，停止
     * 攔截（見 ReaderViewAttachmentTracker 類別註解）。宣告為 nullable
     * （而非 lateinit，審查修正）：dispatchKeyEvent() 理論上可能在
     * configureFlutterEngine() 完成賦值前被系統呼叫，nullable + 安全呼叫
     * （`?.invokeMethod`）讓這種情況下靜默不通知，而不是拋出
     * UninitializedPropertyAccessException 讓整個 App 崩潰。
     */
    private var volumeKeyChannel: MethodChannel? = null
```

- [x] **Step 2：覆寫 `dispatchKeyEvent()`**

在現有 `override fun onCreate(savedInstanceState: Bundle?) { ... }` 方法（結尾為第 60 行 `}`）之後、`override fun configureFlutterEngine(...)`（第 62 行）之前，新增：

```kotlin
    /**
     * 攔截硬體音量鍵（FR-18），方向固定映射，不查詢熱區設定（design.md
     * 決策 #19）：僅在有任一 Reader PlatformView 附加、且未被 Dart 端
     * notifyLeavingReader 暫時抑制時消費事件；其餘情況交還系統處理，含
     * 正常音量調整。攔截生效時 ACTION_DOWN／ACTION_UP 皆消費（審查修正，
     * 偏離 issues.md 原始「僅 ACTION_DOWN」文字，經人類確認採納）：只放行
     * ACTION_DOWN、讓 ACTION_UP 穿透至 super，是已知的 Android 陷阱——
     * 部分機型即使 ACTION_DOWN 已消費，未消費的 ACTION_UP 仍會讓系統音量
     * 提示 UI（音量條 Toast）跳出。只有 ACTION_DOWN 才透過 onVolumeKey
     * 通知 Dart 翻頁，避免按一次鍵觸發兩次翻頁。
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val isVolumeKey = event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        if (isVolumeKey &&
            ReaderViewAttachmentTracker.isAnyAttached &&
            !ReaderViewAttachmentTracker.suppressedUntilReattach
        ) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                val direction = if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down"
                volumeKeyChannel?.invokeMethod("onVolumeKey", mapOf("direction" to direction))
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

```

- [x] **Step 3：`configureFlutterEngine()` 內註冊頻道**

在現有 `configureFlutterEngine()` 方法內，找到 `elinkbook/app_info` 的 `MethodChannel(...).setMethodCallHandler { ... }` 區塊（方法最後一段），在其**之後**、`configureFlutterEngine` 方法結尾的 `}` 之前，新增：

（**實作修正**：`volumeKeyChannel` 被 `dispatchKeyEvent()` 這個獨立方法內的存取捕獲，Kotlin 對可能被其他作用域讀取的可變類別屬性〔`var`〕不會套用 smart-cast，即使緊接在賦值之後也一樣，因此下方 `setMethodCallHandler` 呼叫必須用 `?.` 安全呼叫，否則編譯失敗，已依編譯器實際要求修正並經審查確認為正確、最小化的調整。）

```kotlin

        volumeKeyChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "elinkbook/volume_key")
        volumeKeyChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "notifyLeavingReader" -> {
                    ReaderViewAttachmentTracker.suppressedUntilReattach = true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
```

- [x] **Step 4：編譯驗證**

```bash
cd app && flutter analyze
```

Expected：`No issues found!`

```bash
cd app && flutter build apk --debug
```

Expected：`BUILD SUCCESSFUL`（`MainActivity.dispatchKeyEvent()` 涉及 `Activity`/`KeyEvent` 等 Android 框架類別，本專案未引入 Robolectric，無法以 JVM 單元測試驗證，見 Global Constraints；此步驟的編譯成功是本 Task 唯一可自動化的正確性訊號，實際攔截行為留給 Task 5 真機驗證）。

- [x] **Step 5：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt
git commit -m "feat(epic-7): MainActivity 新增 elinkbook/volume_key 頻道與 dispatchKeyEvent 攔截"
```

---

### Task 4：`ReaderScreen` — 接收 `onVolumeKey`、`PopScope` 送出 `notifyLeavingReader`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 3 的 `elinkbook/volume_key` 頻道契約（`onVolumeKey({"direction": "up"|"down"})`／`notifyLeavingReader`）；既有 `_handleZoneAction(ZoneAction action)`（Issue 4，`app/lib/screens/reader_screen.dart`）
- Produces：`_ReaderScreenState._handleVolumeKeyCall(MethodCall call)`（私有方法，透過 `_volumeKeyChannel.setMethodCallHandler` 掛載）

- [x] **Step 1：寫失敗測試**

在 `app/test/screens/reader_screen_test.dart`，於既有測試「PDF：真實點擊熱區「選單」格（index 1）觸發沉浸模式切換」（本檔案第 2142-2178 行左右）之後，新增以下 2 個測試：

```dart
  testWidgets(
      '音量鍵 onVolumeKey(up/down) 觸發真實換頁（PDF，模擬原生端會呼叫的全域頻道）',
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
    addTearDown(() => binaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views, null));

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

    const volumeKeyChannel = MethodChannel('elinkbook/volume_key');
    Future<void> simulateVolumeKey(String direction) async {
      final byteData = volumeKeyChannel.codec.encodeMethodCall(
        MethodCall('onVolumeKey', {'direction': direction}),
      );
      await binaryMessenger.handlePlatformMessage(
        volumeKeyChannel.name,
        byteData,
        (data) {},
      );
      await tester.pump();
    }

    await simulateVolumeKey('down');
    expect(
      instanceCalls.any((c) => c.method == 'nextPage'),
      isTrue,
      reason: 'onVolumeKey(down) 應呼叫 PdfReaderView 的 nextPage',
    );

    await simulateVolumeKey('up');
    expect(
      instanceCalls.any((c) => c.method == 'previousPage'),
      isTrue,
      reason: 'onVolumeKey(up) 應呼叫 PdfReaderView 的 previousPage',
    );
  });

  testWidgets(
      'PopScope：pop 動作啟動當下呼叫 notifyLeavingReader，及早通知原生端釋放音量鍵攔截',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const volumeKeyChannel = MethodChannel('elinkbook/volume_key');
    final outgoingCalls = <MethodCall>[];
    binaryMessenger.setMockMethodCallHandler(
      volumeKeyChannel,
      (call) async {
        outgoingCalls.add(call);
        return null;
      },
    );
    addTearDown(() =>
        binaryMessenger.setMockMethodCallHandler(volumeKeyChannel, null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open_reader'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReaderScreen(
                      filePath: 'test/fixtures/sample.pdf',
                      bookId: 'b1',
                      prefsManager: prefsManager,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    // 模擬原生端 onPageRendered，讓 _state 脫離 loading（純 flutter test
    // 環境下 AndroidView 不會真正觸發原生回呼，比照本檔案既有測試慣例）
    // ——CircularProgressIndicator 為不定長動畫，若一直停留在 loading，
    // 後續 pumpAndSettle() 永遠不會收斂而逾時（實作修正，全分支審查發現
    // 原範例的 pumpAndSettle() 會在此情境逾時，已改為手動觸發
    // onPageRendered 後再 pump，本檔案已有多處先例）。
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(outgoingCalls, isEmpty);

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(
      outgoingCalls.any((c) => c.method == 'notifyLeavingReader'),
      isTrue,
    );
  });
```

- [x] **Step 2：執行測試確認失敗**

```bash
cd app && flutter test test/screens/reader_screen_test.dart
```

Expected：新增的 2 個測試 FAIL（第 1 個因 `instanceCalls` 中找不到 `nextPage`/`previousPage`——目前沒有任何程式碼監聽 `elinkbook/volume_key` 頻道；第 2 個因 `outgoingCalls` 中找不到 `notifyLeavingReader`——目前 `PopScope` 沒有 `onPopInvokedWithResult`）。其餘既有測試維持通過。

- [x] **Step 3：實作 — 新增頻道常數與處理方法**

在 `app/lib/screens/reader_screen.dart`，於既有 import 區塊結尾（第 41 行 `import 'toc_bottom_sheet.dart';`）之後、`ReaderScreen` 類別的文件註解（第 43 行 `/// 唯一的閱讀器顯示接縫...`）之前，新增：

```dart

/// 音量鍵事件頻道（epic-7-interaction Issue 7）：原生 `MainActivity.
/// dispatchKeyEvent()` 攔截音量鍵後呼叫 `onVolumeKey`；`_handleVolumeKeyCall`
/// 轉呼叫既有的 `_handleZoneAction`。既有 `PopScope` 的
/// `onPopInvokedWithResult` 於 pop 動作啟動當下呼叫 `notifyLeavingReader`，
/// 讓原生端立即停止攔截（早於退場轉場動畫、更早於 dispose()，見
/// docs/epics/epic-7-interaction/spec.md「新增音量鍵頻道」）。
const _volumeKeyChannel = MethodChannel('elinkbook/volume_key');
```

- [x] **Step 4：實作 — `initState()`/`dispose()` 掛載與解除頻道處理器**

找到現有的：

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.prefsManager.load(widget.bookId).then((loaded) {
```

改為：

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _volumeKeyChannel.setMethodCallHandler(_handleVolumeKeyCall);
    widget.prefsManager.load(widget.bookId).then((loaded) {
```

找到現有的：

```dart
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _totalCharacterCountNotifier.dispose();
```

改為：

```dart
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _volumeKeyChannel.setMethodCallHandler(null);
    _totalCharacterCountNotifier.dispose();
```

- [x] **Step 5：實作 — 新增 `_handleVolumeKeyCall`**

在既有的 `_handleZoneAction(ZoneAction action) { ... }` 方法（檔案結尾附近，第 1472-1495 行）之前，新增：

```dart
  /// 原生端 `MainActivity.dispatchKeyEvent()` 攔截音量鍵後的回呼
  /// （epic-7-interaction Issue 7）：方向固定映射，不查詢
  /// `_resolved!.navZoneActions`（design.md 決策 #19）——`up` 一律上一頁、
  /// `down` 一律下一頁。
  Future<void> _handleVolumeKeyCall(MethodCall call) async {
    if (call.method != 'onVolumeKey') return;
    final args = call.arguments as Map<Object?, Object?>;
    switch (args['direction'] as String?) {
      case 'up':
        _handleZoneAction(ZoneAction.previousPage);
        break;
      case 'down':
        _handleZoneAction(ZoneAction.nextPage);
        break;
    }
  }

```

- [x] **Step 6：實作 — `PopScope` 新增 `onPopInvokedWithResult`**

找到現有的：

```dart
    return PopScope(
      // 手動裁切互動模式進行中時，返回鍵不應把整個 ReaderScreen 一併 pop
      // 掉——原生端裁切互動模式沒有使用者手勢可以主動觸發離開（見 spec.md
      // 第 123 行「不會主動由使用者手勢觸發」），這裡單純吞掉返回鍵手勢，
      // 讓使用者留在裁切模式，必須透過畫面上的原生確認按鈕才能離開（審查
      // 意見 2.1(b)：避免誤觸返回鍵導致整個閱讀器被意外關閉；刻意不在此
      // 新增「取消並還原」語意，維持 spec.md 已鎖定的簡化狀態機決策）。
      canPop: !_cropEditModeActive,
      child: Scaffold(
```

改為（**實作修正**：新增 `onPopInvokedWithResult` 後，Dart 會把 `PopScope<T>` 的 `T` 從隱含推論的 `dynamic` 改為 `Object`，導致既有測試 `find.byType(PopScope)`〔隱含比對 `PopScope<dynamic>`〕找不到 widget 而回歸失敗；顯式標註 `PopScope<dynamic>(...)` 還原原本的推論結果，已經審查驗證為正確、最小化的修正，純型別標註、無行為變化）：

```dart
    return PopScope<dynamic>(
      // 手動裁切互動模式進行中時，返回鍵不應把整個 ReaderScreen 一併 pop
      // 掉——原生端裁切互動模式沒有使用者手勢可以主動觸發離開（見 spec.md
      // 第 123 行「不會主動由使用者手勢觸發」），這裡單純吞掉返回鍵手勢，
      // 讓使用者留在裁切模式，必須透過畫面上的原生確認按鈕才能離開（審查
      // 意見 2.1(b)：避免誤觸返回鍵導致整個閱讀器被意外關閉；刻意不在此
      // 新增「取消並還原」語意，維持 spec.md 已鎖定的簡化狀態機決策）。
      canPop: !_cropEditModeActive,
      // pop 動作啟動當下（早於退場轉場動畫、更早於 PlatformView.dispose()）
      // 通知原生端立即停止攔截音量鍵（epic-7-interaction Issue 7，收斂
      // 轉場動畫期間的攔截延遲釋放窗口，見 ReaderViewAttachmentTracker
      // 類別註解）。canPop 為 false（裁切模式攔截返回鍵）時 didPop 為
      // false，此時閱讀器仍在使用中，不應釋放攔截，故只在 didPop 為 true
      // 時才呼叫。
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _volumeKeyChannel.invokeMethod('notifyLeavingReader');
        }
      },
      child: Scaffold(
```

- [x] **Step 7：執行測試確認通過**

```bash
cd app && flutter test test/screens/reader_screen_test.dart
```

Expected：全部測試（含 Task 4 新增的 2 個）通過。

```bash
cd app && flutter test
```

Expected：全專案測試全數通過，無回歸。

```bash
cd app && flutter analyze
```

Expected：`No issues found!`

- [x] **Step 8：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-7): ReaderScreen 接收音量鍵事件並於 pop 時通知原生端釋放攔截"
```

---

### Task 5：真機整合測試 — `volume_key_test.dart`

**Files:**
- Create: `app/integration_test/volume_key_test.dart`

**Interfaces:**
- Consumes：Task 3/4 的 `elinkbook/volume_key` 頻道契約；既有 `test/fixtures/sample_dual_page.pdf` 測試素材（`epic-4-pdf-enhance`，已提交版本控制，6 頁）
- Produces：無新公開介面（純驗證性質）

- [x] **Step 1：建立測試檔**

建立 `app/integration_test/volume_key_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _pumpUntilTextFound(WidgetTester tester, String textFragment) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.textContaining(textFragment).evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：畫面上未出現包含「$textFragment」的文字');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Epic 7 Issue 7：FR-18 音量鍵翻頁——真機整合測試。
///
/// 【真機人工驗證清單，本測試無法自動涵蓋】
/// `MainActivity.dispatchKeyEvent()` 攔截的是 Android 原生 Activity 層級
/// 的真實硬體音量鍵事件，發生在 Flutter engine 收到任何事件之前——Flutter
/// integration_test 框架的鍵盤事件模擬（`tester.sendKeyEvent` 等）只能合成
/// Flutter 端 `flutter/keyevent` channel 上的事件，不會、也不能觸達原生
/// Activity 的 dispatchKeyEvent()（兩者是完全不同的管線）。因此以下項目
/// 無法由本檔案自動化涵蓋，須由人類於真機/模擬器以下列方式之一驗證：
///   1. 實體/虛擬音量鍵直接按下，或執行 `adb shell input keyevent 24`
///      （VOLUME_UP）／`adb shell input keyevent 25`（VOLUME_DOWN）：
///      確認 ReaderScreen 內正確觸發上一頁/下一頁（PDF／EPUB FXL／EPUB
///      流式三種畫面皆須驗證）。
///   2. 按下返回鍵離開 ReaderScreen 的**當下**（轉場動畫進行中，
///      PlatformView 尚未 dispose()）立即以 adb 音量鍵指令驗證音量鍵已
///      恢復系統音量調整，而非等轉場動畫結束才恢復（驗證
///      notifyLeavingReader 即時釋放機制，design.md 決策 #19 審查修正）。
///   3. 確認音量鍵攔截並消費事件後，系統原生的音量提示 UI（音量條
///      Toast）不會意外跳出（design.md「待驗證風險」段落）。
/// 本檔案自動化的部分改為驗證「Dart 端事件分派管線」：透過模擬全域
/// `elinkbook/volume_key` 頻道送出 `onVolumeKey` MethodCall（比照
/// `epub_stream_nav_zone_test.dart` 對 onZoneTapped 的既有驗證手法），
/// 確認在真機原生渲染下 PDF 真的換頁——這條路徑不涉及硬體按鍵模擬，純粹
/// 驗證 Dart 分派邏輯 → 原生 method channel → 真機渲染結果，是
/// integration_test 可靠涵蓋的範圍；`dispatchKeyEvent()` 本身留給上述人工
/// 驗證清單。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('模擬 onVolumeKey(down/up) 真機正確換頁，且不影響沉浸模式',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_dual_page.pdf', 'volume_key_pageturn.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_volume_key',
      title: '音量鍵翻頁測試書',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_volume_key',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.textContaining('第 1/'), findsOneWidget, reason: '初始應在第 1 頁');

    const volumeKeyChannel = MethodChannel('elinkbook/volume_key');
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Future<void> simulateVolumeKey(String direction) async {
      final byteData = volumeKeyChannel.codec.encodeMethodCall(
        MethodCall('onVolumeKey', {'direction': direction}),
      );
      await binaryMessenger.handlePlatformMessage(
        volumeKeyChannel.name,
        byteData,
        (data) {},
      );
    }

    await simulateVolumeKey('down');
    await _pumpUntilTextFound(tester, '第 2/');

    expect(find.textContaining('第 2/'), findsOneWidget,
        reason: '模擬 onVolumeKey(down) 後應換到第 2 頁');
    expect(find.byType(AppBar), findsOneWidget, reason: '音量鍵翻頁不應影響沉浸模式');

    await simulateVolumeKey('up');
    await _pumpUntilTextFound(tester, '第 1/');

    expect(find.textContaining('第 1/'), findsOneWidget,
        reason: '模擬 onVolumeKey(up) 後應換回第 1 頁');
  });
}
```

- [x] **Step 2：確認可用裝置**

```bash
cd app && flutter devices
```

Expected：列出至少 1 台已連線的 Android 真機/模擬器，記下其 `<device-id>`。

- [x] **Step 3：真機執行測試**

```bash
cd app && flutter test integration_test/volume_key_test.dart -d <device-id>
```

（若執行環境確認僅連接一台裝置，`-d <device-id>` 參數可省略。）

Expected：1/1 測試 PASS。

- [x] **Step 4：Commit**

```bash
git add app/integration_test/volume_key_test.dart
git commit -m "test(epic-7): 新增音量鍵翻頁真機整合測試"
```

---

## Self-Review

**1. Spec 覆蓋度**：對照 `issues.md` Issue 7 描述逐項核對：
- `ReaderViewAttachmentTracker`（`attach`/`detach`/`isAnyAttached`）→ Task 1
- `PdfReaderView.kt`/`EpubReaderView.kt` 建構子/`dispose()` 呼叫 `attach()`/`detach()` → Task 2
- `suppressedUntilReattach`（`notifyLeavingReader` 觸發、`attach()` 重設）→ Task 1（欄位本體）+ Task 3（`notifyLeavingReader` 接收端）+ Task 4（`notifyLeavingReader` 發送端）
- `MainActivity.dispatchKeyEvent()` 覆寫（`KEYCODE_VOLUME_UP`/`DOWN`、`ACTION_DOWN`、攔截判斷、`onVolumeKey` 呼叫）→ Task 3
- `ReaderScreen` 監聽 `onVolumeKey`（固定映射 `up`→`previousPage`/`down`→`nextPage`，`initState`/`dispose` 掛載時機）→ Task 4
- `PopScope.onPopInvokedWithResult` 呼叫 `notifyLeavingReader` → Task 4
- JVM 單元測試（`ReaderViewAttachmentTracker` 計數器邏輯）→ Task 1
- `ReaderScreen` widget test（`onVolumeKey` 觸發正確分支、`PopScope` pop 觸發 `notifyLeavingReader`）→ Task 4
- `integration_test`（真實裝置，音量鍵正確翻頁、離開閱讀畫面轉場期間音量鍵即時恢復）→ Task 5（Dart 分派管線自動化 + 人工驗證清單涵蓋硬體按鍵本身，理由已在 Task 5 檔頭記錄，比照 Issue 4/6 既有先例）
所有描述項目皆有對應 Task，無遺漏。

**2. Placeholder 掃描**：全文檢查過，無 "TBD"/"待補"/"視情況處理" 等字樣；所有程式碼步驟皆附完整可執行程式碼，非片段描述。

**3. 型別一致性**：`ReaderViewAttachmentTracker.isAnyAttached`/`suppressedUntilReattach`/`attach()`/`detach()` 在 Task 1 定義、Task 2/3 使用，命名/簽章逐一核對一致；`elinkbook/volume_key` 頻道方法名稱（`onVolumeKey`/`notifyLeavingReader`）與參數格式（`{"direction": "up"|"down"}`）在 Task 3（原生端送出/接收）與 Task 4（Dart 端接收/送出）兩端逐一核對一致；`ZoneAction.previousPage`/`ZoneAction.nextPage`（既有型別，`app/lib/reader/zone_action.dart`）與既有 `_handleZoneAction` 簽章核對一致，未新增或修改該方法簽章；Task 3 的 `volumeKeyChannel` 為 `MethodChannel?`（nullable），Task 3 Step 2/3 兩處使用點（`?.invokeMethod`／賦值）皆已核對一致。

**4. 審查修訂紀錄**（`tmp/epic-7/reviews/review-plan-issue-7.md`，經人類確認後採納）：
- 採納：`volumeKeyChannel` 改 `lateinit var` 為 `MethodChannel?`（Task 3 Step 1/2）
- 採納：`ReaderViewAttachmentTracker.detach()` 計數器下限保護在 0，並補上對應 JVM 測試（Task 1 Step 1/3）
- 採納：`dispatchKeyEvent()` 攔截生效時 `ACTION_DOWN`/`ACTION_UP` 皆消費，只在 `ACTION_DOWN` 時通知 Dart（Task 3 Step 2；**此項刻意偏離 `issues.md` Issue 7 原始「僅 ACTION_DOWN」文字**，理由是已知的 Android 音量條 UI 洩漏陷阱，經人類確認採納，`issues.md` 待本 issue 完成後一併回填此行為調整）
- 不採納：`PopScope.onPopInvokedWithResult` 顯式型別標註——查證本專案 `analysis_options.yaml` 未啟用 `avoid_types_on_closure_parameters`，且 `app/lib/screens/library_screen.dart:337` 既有、已合併、`flutter analyze` 通過的程式碼即為省略型別寫法，維持與既有慣例一致
- 不採納：`ReaderViewAttachmentTracker` 增加 `attachmentCount` 供 `notifyLeavingReader` 判斷 `pushReplacement` 競態——已 `grep` 全專案確認 `pushReplacement` 從未被使用，`ReaderScreen` 僅透過 `Navigator.push()` 開啟（`library_screen.dart:284`），`spec.md`「已知限制」已明文此簡化為目前架構下故意的假設，屬 YAGNI

**5. 全部 Task 完成、全分支審查（Ready to merge: Yes）後的追加修訂**（`tmp/epic-7/reviews/code-review-issue-7.md`，經人類確認後採納）：
- 採納：`ReaderViewAttachmentTracker.suppressedUntilReattach` 加上 `@Volatile`（Task 1，commit `d73d298`）——目前所有讀寫皆在 UI Thread（`dispatchKeyEvent()`／`MethodChannel` 回呼／PlatformView 生命週期方法皆固定於主執行緒），無實質併發風險，但屬零成本防禦性修正，與先前已採納的兩項防禦性修正（nullable channel、計數器下限保護）同一類，一併採納；JVM 測試 5/5 維持通過（`@Volatile` 純屬可見性保障，不改變邏輯）
- 不採納：抽出獨立 `VolumeKeyChannel` 類別以收斂 `MainActivity` 的 Divergent Change——審查報告本身標註為「未來 Epic 重構」建議，本 issue 只新增 1 個 channel／1 個 case 分支，提前抽象化違反 YAGNI，維持現狀
