# Epic 7 Issue 1 — Spike：Readium `InputListener.onTap()` 可行性驗證 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在真機上驗證 `spec.md`「待驗證風險與收斂關卡」列出的 3 個未解問題，把 EPUB 流式熱區（Issue 6）的實作路線從「假設」變成「已驗證的事實」，並把結論書面化。

**Architecture:** 本 issue 不產出長期功能程式碼。以「暫時性程式碼插樁（temporary instrumentation）→ 真機觀察（`adb shell input tap` 模擬點擊 + `adb logcat` 擷取證據 + 螢幕截圖）→ 記錄證據 → 還原插樁 → 只保留書面報告（與必要時的 `spec.md` 修訂）」的節奏依序驗證 3 個問題，比照 `epic-16-dual-page` Issue 1 先例。插樁程式碼**不進版本控制**（驗證後 `git checkout --` 還原），只有 `reviews/spike-epub-inputlistener.md` 報告與（若有必要的）`spec.md` 修訂會被 commit。

**Tech Stack:** Kotlin（`EpubReaderView.kt`）、Readium `kotlin-toolkit` 3.3.0（`org.readium.r2.navigator.input.InputListener`／`TapEvent`／`VisualNavigator.addInputListener()`——已反編譯 `readium-navigator-3.3.0.aar` 的 `classes.jar` 確認下列 API 簽章，見 Global Constraints）、`adb`／真機（9491G，device id `3CEF42ECD491687`，Android 15 / API 35，螢幕解析度 1600×2400）——本計劃全程 `adb` 指令皆明確帶 `-s 3CEF42ECD491687`，若執行環境確認僅連接這一台裝置，`-s <device-id>` 參數可省略，指令行為不變。

## Global Constraints

- 3 個待驗證問題（逐字抄自 `spec.md`「待驗證風險與收斂關卡」，不得自行改寫判準）：
  1. Readium `EpubNavigatorFragment` 是否已有內建點擊翻頁行為，需要先透過 `EpubPreferences` 顯式停用，才能讓 `InputListener.onTap()` 生效
  2. `InputListener.onTap()` 回呼中呼叫 `goForward()`/`goBackward()` 是否真的能正確換頁、是否會與 Readium 自身可能存在的手勢處理重複觸發（例如同一次點擊換兩頁）
  3. `InputListener.onTap(point: PointF)` 回傳的座標系統——是相對整個 `EpubNavigatorFragment` view，還是相對可視內容區域（可能因 letterbox 或縮放置中偏移而不同）
- 已反編譯 `readium-navigator-3.3.0.aar`（`~/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/`）的 `classes.jar` 確認以下 API（`javap -p` 逐一驗證，非猜測）：
  - `VisualNavigator`（`org.readium.r2.navigator.VisualNavigator`）：`abstract fun getPublicationView(): View`（Kotlin 端即 `publicationView` 屬性）、`abstract fun addInputListener(InputListener)`、`abstract fun removeInputListener(InputListener)`
  - `OverflowableNavigator extends VisualNavigator`——`EpubNavigatorFragment implements OverflowableNavigator`，故 `navigatorFragment?.addInputListener(...)` 為既有型別 `EpubReaderView.kt` 的 `navigatorFragment: EpubNavigatorFragment?` 欄位可直接呼叫的方法，不需要額外轉型
  - `InputListener`（`org.readium.r2.navigator.input.InputListener`）：`open fun onTap(event: TapEvent): Boolean`（有預設實作，回傳 `false`——具體預設行為是否等同「不消費事件」需靠 Q2 實測確認，不接受望文生義的推測）
  - `TapEvent`（`org.readium.r2.navigator.input.TapEvent`）：`data class TapEvent(val point: PointF)`，只有這一個欄位
  - `EpubNavigatorFragment` 內部已有 `private val inputListener: CompositeInputListener` 欄位與 `R2BasicWebView.Listener.onTap(point: PointF): Boolean` 回呼——代表 WebView 內容的點擊事件本來就會透過既有的 JS bridge 機制被 Kotlin 端攔截並可轉發給任何透過 `addInputListener()` 註冊的監聽器，不是「Kotlin 端完全收不到 WebView 內部點擊」的封閉黑盒
- 過程中任何暫時性程式碼/素材，驗證完成後一律清理，不留在版本控制中（`git status` 須乾淨，只保留報告檔與必要的 `spec.md` 修訂）。
- 本 issue 不需要新增/修改任何 Dart 端程式碼或單元測試——純粹是原生端行為的真機觀察。
- 測試素材：`app/test/fixtures/sample_multi_chapter.epub`（已提交版本控制，既有 `integration_test/epub_toc_test.dart` 已使用，確認為流式、多章節、內容量足以在直向 paginated 模式下產生多頁）。
- **執行環境**：全文所有 ```bash 區塊皆假設以 POSIX 相容的 Bash 工具（Git Bash / MSYS2）執行，非 PowerShell／`cmd.exe`。已實測確認 `adb exec-out screencap -p > file.png` 在此環境下二進位輸出完整無損（`xxd` 檢查 PNG 簽章 `89 50 4e 47 0d 0a 1a 0a` 逐位元組吻合，非猜測）；若執行環境改用 PowerShell，`>` 重導向二進位串流有已知的編碼轉換風險，需改用 `adb shell screencap -p /sdcard/tmp.png` + `adb pull` 兩段式做法。

---

### Task 1：基準測試——確認未插樁前 Readium 是否已有內建點擊翻頁行為（Q1）

**Files:** 無異動（在目前 `main` 未修改狀態下觀察）

**Interfaces:**
- Consumes：無（本 issue 起始工單）
- Produces：Q1 的基準證據（螢幕截圖 + 觀察紀錄），供 Task 3 彙整進報告；若本 Task 已發現內建翻頁行為，Task 2 插樁後需與此基準比對是否重複翻頁

- [ ] **Step 1：記錄插樁前的乾淨基準**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：完全無輸出（`plans/plan-issue-1.md` 已隨本次 commit 存在於 worktree 中，不會顯示為待處理變更）。若有殘留輸出，先確認來源再繼續。

- [ ] **Step 2：建置目前（未修改）debug APK 並安裝到真機**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected：建置成功、安裝成功（`Success`）。

- [ ] **Step 3：推送測試素材並透過 App 內建匯入流程開啟**

```bash
adb -s 3CEF42ECD491687 push "U:/MyDeveloper/AI/elinkBook/app/test/fixtures/sample_multi_chapter.epub" /sdcard/Download/
```

在真機上開啟 App → 圖書庫 →「匯入書籍」→ 系統檔案選擇器 → 導覽至「下載」資料夾 → 選取 `sample_multi_chapter.epub`，等待匯入完成，點擊該書開啟閱讀畫面。確認畫面為流式（reflowable）版面（無懸浮按鈕、有正常 AppBar），非固定版面。

- [ ] **Step 4：直向、擷取第一頁畫面**

```bash
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike-q1-baseline-page1.png"
```

- [ ] **Step 5：在畫面左側、中央、右側三個位置各點擊一次，逐次擷取畫面比對是否翻頁**

```bash
# 左側（畫面寬度約 1/6 處）
adb -s 3CEF42ECD491687 shell input tap 260 1200
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike-q1-tap-left.png"

# 中央
adb -s 3CEF42ECD491687 shell input tap 800 1200
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike-q1-tap-center.png"

# 右側（畫面寬度約 5/6 處）
adb -s 3CEF42ECD491687 shell input tap 1340 1200
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike-q1-tap-right.png"
```

**Q1 判準**：逐一比對 `spike-q1-baseline-page1.png` 與三張點擊後截圖的內容文字：

- 若畫面內容（可見文字）在**任一次**點擊後改變 → Q1 結論：Readium **已有內建點擊翻頁行為**，需要先停用；具體停用方式待 Task 2 進一步確認是否能靠 `InputListener.onTap()` 回傳 `true` 抑制，或需要額外的 `EpubPreferences` 設定
- 若三次點擊畫面皆無變化 → Q1 結論：「無內建點擊翻頁行為，不需停用」

- [ ] **Step 6：記錄 logcat 是否有相關訊息（輔助判斷，非必要證據）**

```bash
adb -s 3CEF42ECD491687 logcat -d | grep -i "readium\|elinkbook" | tail -50 > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike-q1-logcat.txt"
```

---

### Task 2：插樁 `InputListener.onTap()`，驗證能否攔截並取代預設行為（Q2）+ 觀察座標系統（Q3）

**Files:**
- Modify（暫時性，驗證後還原）：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:43`（新增 import，緊接既有 `org.readium.r2.navigator.util.BaseActionModeCallback` import 之後）、`:897`（`attachNavigator()`，緊接 `navigatorFragment = activity.supportFragmentManager.findFragmentByTag(fragmentTag) as? EpubNavigatorFragment` 之後）

**Interfaces:**
- Consumes：Task 1 的基準結論（是否已有內建翻頁行為，決定插樁後是否要特別留意「同一次點擊換兩頁」的重複翻頁現象）；`EpubReaderView.kt` 既有欄位 `navigatorFragment: EpubNavigatorFragment?`（`attachNavigator()` 賦值後即可用）
- Produces：Q2／Q3 的證據（logcat 座標紀錄 + 螢幕截圖），供 Task 3 彙整進報告；若證實可行，本插樁確認的 API 呼叫方式（`addInputListener` + `TapEvent.point` + `goForward`/`goBackward`）可作為 Issue 6 實作的起點（僅供參考，Issue 6 需視 `spec.md` 規格重新正式撰寫並補測試，不可直接複製本次插樁程式碼）

- [ ] **Step 1：新增 `InputListener`／`TapEvent` import**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` 第 43 行（`import org.readium.r2.navigator.util.BaseActionModeCallback` 之後）新增兩行：

```kotlin
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.TapEvent
```

- [ ] **Step 2：在 `attachNavigator()` 內暫時註冊 `InputListener`**

修改 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`，在第 896-897 行：

```kotlin
            navigatorFragment = activity.supportFragmentManager
                .findFragmentByTag(fragmentTag) as? EpubNavigatorFragment
```

之後（緊接著，`// 訂閱 currentLocator StateFlow` 註解之前）插入：

```kotlin
            // TEMP-SPIKE(epic-7-issue-1)：驗證 InputListener.onTap() 可行性，Task 3 需移除。
            //
            // 【刻意反轉方向】點左側呼叫 goForward、點右側呼叫 goBackward——與直覺
            // 相反（審查修正）。理由：若正著對應（點右→goForward），一旦攔截失敗、
            // Readium 內建行為（若 Q1 已確認存在）剛好也是「點右→前進」，兩個呼叫
            // 疊加後，若 Readium 內部有換頁防抖鎖，畫面可能仍只前進一頁，會被誤判
            // 為「攔截成功」。反轉後，攔截失敗時兩個方向會互相打架（一個往前、一個
            // 往後），淨位移會明顯偏離「乾淨的單頁位移」，才能可靠區分成功/失敗。
            val spikeIsFixedLayout = openedPublication.metadata.layout == Layout.FIXED
            if (!spikeIsFixedLayout) {
                // 裝置螢幕寬度 1600px（見 Tech Stack），publicationView 理論上不應
                // 為 null（此時機點 Fragment 已附加），但仍給合理 fallback，避免
                // view 為 null 時 (0 / 2f = 0f) 讓 event.point.x（恆為正數）在
                // `< 0f` 判斷下永遠為假、左右分流形同失效（審查修正）。
                val fallbackWidthPx = 1600
                navigatorFragment?.addInputListener(object : InputListener {
                    override fun onTap(event: TapEvent): Boolean {
                        val view = navigatorFragment?.publicationView
                        val halfWidth = (view?.width ?: fallbackWidthPx) / 2f
                        android.util.Log.d(
                            "EPIC7_SPIKE",
                            "onTap point=${event.point} " +
                                "publicationView.width=${view?.width} " +
                                "publicationView.height=${view?.height} " +
                                "fragmentView.width=${navigatorFragment?.view?.width} " +
                                "fragmentView.height=${navigatorFragment?.view?.height}",
                        )
                        if (event.point.x < halfWidth) {
                            navigatorFragment?.goForward(animated = false)
                        } else {
                            navigatorFragment?.goBackward(animated = false)
                        }
                        return true
                    }
                })
            }
```

（此插樁刻意同時記錄 `publicationView` 與 `navigatorFragment.view`（Fragment 自身的 root view）兩組尺寸——若兩者尺寸不同，`event.point` 的座標基準需要靠比對其數值範圍才能判斷是相對哪一個 view，這正是 Q3 要驗證的內容。）

- [ ] **Step 3：重新建置並安裝**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected：建置成功（確認 `InputListener`/`TapEvent` import 路徑正確、`object : InputListener` 匿名類別編譯通過），安裝成功。

- [ ] **Step 4：清空 logcat 緩衝區，開啟同一本書**

```bash
adb -s 3CEF42ECD491687 logcat -c
```

在真機上重新開啟 `sample_multi_chapter.epub`（Task 1 已匯入，App 圖書庫內應仍有該書項目；若已被移除，重複 Task 1 Step 3 的匯入流程）。

- [ ] **Step 5：擷取插樁後第一頁畫面**

```bash
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike-q2-instrumented-page1.png"
```

- [ ] **Step 6：點擊畫面左側 3 次（插樁反轉映射：左側呼叫 `goForward`），先遠離第 1 頁邊界**

```bash
adb -s 3CEF42ECD491687 shell input tap 260 1200
adb -s 3CEF42ECD491687 shell input tap 260 1200
adb -s 3CEF42ECD491687 shell input tap 260 1200
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike-q2-after-3-left-taps.png"
```

先前進 3 頁、遠離第 1 頁邊界，是刻意安排——若在第 1 頁就直接測試「反轉後點擊是否正確後退」，`goBackward()` 在第 1 頁是無效的邊界情況（已在第一頁，退無可退），會讓後續反轉測試的判讀出現歧義（見 Step 7 判準說明）。

- [ ] **Step 7：點擊畫面右側 1 次（插樁反轉映射：右側呼叫 `goBackward`），比對是否正確後退**

```bash
adb -s 3CEF42ECD491687 shell input tap 1340 1200
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike-q2-tap-right-1.png"
```

**Q2 判準（攔截有效性，審查修正——改用反轉方向比對）**：比對 `spike-q2-after-3-left-taps.png` 與 `spike-q2-tap-right-1.png`：

- 內容**明確後退恰好一頁** → `InputListener.onTap()` 已成功攔截並取代預設行為（若 Task 1 確認 Readium 有內建翻頁行為，代表 `onTap()` 回傳 `true` 確實抑制了它；若 Task 1 確認無內建行為，此結果單純確認 `goBackward()` 呼叫本身正確生效）
- 內容**沒有後退**（停留原頁，或反而前進）→ 代表攔截失敗，`InputListener.onTap()` 與 Readium 內建行為同時生效、兩者方向相反互相打架，淨位移不是乾淨的單頁後退；記錄實際觀察到的內容變化，判定 Q2 失敗

- [ ] **Step 8：再點擊畫面右側 2 次，確認持續後退、排除巧合**

```bash
adb -s 3CEF42ECD491687 shell input tap 1340 1200
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike-q2-tap-right-2.png"
adb -s 3CEF42ECD491687 shell input tap 1340 1200
adb -s 3CEF42ECD491687 exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike-q2-tap-right-3.png"
```

**Q2 判準（一致性檢查）**：`spike-q2-tap-right-2.png`、`spike-q2-tap-right-3.png` 應相對前一張再各後退恰好一頁，與 Step 7 的判讀方向一致，排除 Step 7 是單次巧合。

- [ ] **Step 9：擷取 logcat，取出所有 `EPIC7_SPIKE` 標記的紀錄**

```bash
adb -s 3CEF42ECD491687 logcat -d | grep "EPIC7_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike-q2q3-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike-q2q3-logcat.txt"
```

**Q2 判準（重複觸發檢查，與上方「攔截有效性」判準是互補的兩件事——這裡檢查的是我方 `InputListener` 本身有沒有被同一次點擊觸發多次，上方檢查的是 Readium 內建行為是否仍與我方同時生效）**：

- 確認 Step 6-8 總共 6 次點擊（3 次左側 + 3 次右側），`logcat` 中 `onTap` 的呼叫次數也恰好是 6 次 → 通過，我方監聽器本身沒有重複觸發
- 若出現 7 次以上 → 代表同一次點擊觸發了多次 `onTap` 回呼，記錄為 Q2 失敗並描述現象

**Q3 判準**：檢視 `spike-q2q3-logcat.txt` 中每一筆記錄的 `point=`、`publicationView.width/height`、`fragmentView.width/height` 數值：

- 若 `point.x`／`point.y` 的數值範圍與 `publicationView.width`／`height` 相符（例如點擊畫面右側時 `point.x` 接近 `publicationView.width` 的數值），且 `publicationView.width/height` 與 `fragmentView.width/height` 相同 → 座標相對整個 view，且該 view 沒有 letterbox 留白，`NavZoneHitTester.cellIndex()` 不需要額外轉換
- 若 `publicationView` 與 `fragmentView` 尺寸不同，或 `point` 數值與兩者皆不完全吻合（例如座標值明顯小於兩者、暗示是相對某個更小的可視內容區域，或座標系原點不在左上角）→ 記錄實際觀察到的數值關係，供 `spec.md` 記錄所需的座標轉換公式

- [ ] **Step 10：清理真機上的匯入書籍與暫存檔**

驗證完成後，於 App 內刪除該書（圖書庫 → 長按/滑動該書 → 刪除），並清除裝置暫存：

```bash
adb -s 3CEF42ECD491687 shell rm -f /sdcard/Download/sample_multi_chapter.epub
```

---

### Task 3：彙整驗證報告、視結果更新 spec.md、還原插樁

**Files:**
- Create：`docs/epics/epic-7-interaction/reviews/spike-epub-inputlistener.md`
- Modify（僅在有問題失敗或座標系統需要轉換時）：`docs/epics/epic-7-interaction/spec.md`「待驗證風險與收斂關卡」／`EpubReaderView.kt` 模組段落
- Revert：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（還原 Task 2 的暫時性插樁）

**Interfaces:**
- Consumes：Task 1、2 產出的截圖與 logcat 證據
- Produces：本 epic 後續 Issue 6 唯一可依循的事實結論（含是否需要退回自行實作、座標轉換公式）

- [ ] **Step 1：撰寫驗證報告**

在 `docs/epics/epic-7-interaction/reviews/spike-epub-inputlistener.md` 寫入以下結構（依 Task 1-2 的實際觀察結果填入，不得照抄本範本的佔位文字）：

```markdown
# Epic 7 Issue 1 — Spike：Readium InputListener.onTap() 驗證報告

**驗證日期：** <實際日期>
**驗證裝置：** 9491G（Android 15 / API 35，device id 3CEF42ECD491687，螢幕 1600×2400）
**Readium 版本：** kotlin-toolkit 3.3.0
**測試素材：** app/test/fixtures/sample_multi_chapter.epub（流式、多章節）

## Q1：Readium 是否已有內建點擊翻頁行為

**結論：** <需要停用 / 不需要停用>
**證據：** spike-q1-baseline-page1.png、spike-q1-tap-left.png、spike-q1-tap-center.png、spike-q1-tap-right.png
<具體觀察描述：三個點擊位置各自是否觸發翻頁>

## Q2：InputListener.onTap() 是否能攔下並取代預設行為（反轉方向測試，含重複觸發檢查）

**結論：** <通過 / 失敗>
**證據：** spike-q2-after-3-left-taps.png ~ spike-q2-tap-right-3.png（共 4 張）、spike-q2q3-logcat.txt
<具體觀察描述：插樁採左→前進、右→後退的反轉映射（見 Task 2 Step 2 說明）；點擊右側 3 次是否每次都恰好乾淨後退一頁（若攔截失敗、Readium 內建行為仍生效，會與後退方向打架、淨位移不乾淨）、onTap 呼叫次數是否等於點擊次數（6 次）>

## Q3：InputListener.onTap(point) 座標系統

**結論：** <相對整個 fragment view / 相對 publicationView / 需要額外轉換，具體公式>
**證據：** spike-q2q3-logcat.txt（point 與 publicationView/fragmentView 尺寸對照）
<具體觀察描述與換算公式，供 NavZoneHitTester.cellIndex() 前處理使用>

## 對 Issue 6 的收斂結論

<綜合 3 項結論，明確寫出 Issue 6 應採用 spec.md 既有規劃的 InputListener 路線、需要哪些調整（例如停用內建行為的具體方式、座標轉換公式），或是否需要退回自行實作；若退回，具體實作方向是什麼>
```

- [ ] **Step 2：若任一問題結論與 `spec.md` 現有假設不符，更新 `spec.md`**

回到 `docs/epics/epic-7-interaction/spec.md`「待驗證風險與收斂關卡」一節，在對應項目後方補上：

```markdown
> **Issue 1 驗證結果（<日期>）：<結論摘要>**——完整證據見 `reviews/spike-epub-inputlistener.md`。<若需要額外處理，這裡寫具體作法（例如停用內建行為的 EpubPreferences 欄位、座標轉換公式）>
```

若 3 項皆與現有假設一致（不需額外處理），仍需在該節開頭補一句總結（例如：「本節 3 項風險已於 Issue 1 spike 全數驗證，見 `reviews/spike-epub-inputlistener.md`，Issue 6 可依 `spec.md` 既有規劃直接實作」），避免下一位讀者誤以為此節仍是未解狀態。若 Q3 發現座標需要轉換，同步更新 `spec.md`「模組」節 `EpubReaderView.kt` 段落，在 `NavZoneHitTester.cellIndex()` 呼叫前補上具體轉換公式的文字說明。

- [ ] **Step 3：還原 Task 2 的暫時性程式碼**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git diff --stat app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git checkout -- app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
```

Expected：`git diff --stat` 顯示 `EpubReaderView.kt` 有異動（確認插樁確實存在過），`git checkout --` 後該檔案完全還原至插樁前狀態。

- [ ] **Step 4：確認清理完整**

```bash
git status --short
```

Expected：只剩 `docs/epics/epic-7-interaction/reviews/spike-epub-inputlistener.md`（新增）與（若 Step 2 有異動）`docs/epics/epic-7-interaction/spec.md`（修改）。`plans/plan-issue-1.md` 已隨版本控制存在，不會出現在這份異動清單中；`app/android/.../EpubReaderView.kt` 也不應出現在異動清單中。

（截圖與 logcat 檔案位於 `tmp/epic-7/reviews/`，該路徑已被根目錄 `.gitignore`（`tmp/`）排除，不需手動清理即不會進版控；如需保留證據可留著，或驗證後自行刪除，皆可。）

- [ ] **Step 5：`flutter analyze` 確認未殘留任何插樁副作用**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected："No issues found!"

- [ ] **Step 6：原生端編譯驗證（審查修正，Step 4 的 `git status` 已確認檔案與 `main` 逐位元組相同，本步驟屬額外保險，確保後續 Issue 2-7 從一個確實可編譯的 `main` 開工）**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
```

Expected：建置成功，無 Kotlin 編譯錯誤。

- [ ] **Step 7：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add docs/epics/epic-7-interaction/reviews/spike-epub-inputlistener.md
git add docs/epics/epic-7-interaction/spec.md 2>/dev/null || true
git commit -m "docs(epic-7): Issue 1 spike——Readium InputListener.onTap() 可行性驗證與收斂"
```

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：`spec.md`「待驗證風險與收斂關卡」列出的 3 項問題（Task 1 涵蓋 Q1、Task 2 涵蓋 Q2/Q3）與「若驗證失敗需記錄退回方案」的要求（Task 3 Step 2）皆有對應任務；`issues.md` Issue 1 的驗收標準（3 項結論皆有證據、若與假設不符時 `spec.md` 已更新、暫時性素材已清理）三項也都對應到 Task 3 的 Step 1/2/3-4。
- **無佔位符掃描**：所有步驟皆為具體指令/程式碼；Task 3 Step 1 的報告範本本質上是待填格式（驗證結果本就要等 Task 1-2 執行後才知道，非逃避性佔位），已在旁註明「不得照抄範本佔位文字」。
- **API 簽章來源**：`InputListener`/`TapEvent`/`VisualNavigator.addInputListener` 三者的方法簽章與屬性名稱皆逐一以 `javap -p` 反編譯 `readium-navigator-3.3.0.aar` 的 `classes.jar` 驗證過（見 Global Constraints），非憑空杜撰或臆測官方文件內容；`goForward(animated: Boolean)`/`goBackward(animated: Boolean)` 沿用 `EpubReaderView.kt` 既有第 199/203 行 `nextPage`/`previousPage` method call 已驗證可行的呼叫方式，未發明新用法。
- **型別/介面一致性**：`event.point`（`PointF`）、`navigatorFragment?.publicationView`（`View`）、`goForward(animated = false)`/`goBackward(animated = false)` 全文用法一致，與既有程式碼命名（`navigatorFragment`、`fragmentTag`）不衝突。
- **測試素材選擇理由**：`sample_multi_chapter.epub` 而非 `sample.epub`／`sample_horizontal.epub`——前者已被既有 `integration_test/epub_toc_test.dart` 驗證為流式、多章節、內容量足夠在直向 paginated 模式下產生多頁，適合本次「連續點擊多次確認每次恰好換一頁」的驗證方式；避免另外引入未經驗證的新素材。
- **審查修正紀錄（`tmp/epic-7/reviews/review-plan-issue-1.md`）**：4 項 Critical 中 3 項採納——(1) Task 2 插樁改為「左→前進、右→後退」的反轉方向映射，並在 Step 6 先前進 3 頁遠離第 1 頁邊界，避免攔截失敗時被防抖鎖或邊界 clamp 巧合掩蓋成假陽性（Step 2 說明＋Step 7/8 判準已改寫）；(2) 修正 `(view?.width ?: 0) / 2f` 在 `view` 為 null 時門檻恆為 0、導致左右分流失效的邊界情況，改用裝置已知寬度 1600 的 fallback 常數；(3) Task 3 還原插樁後新增 `flutter build apk --debug` 作為 `git status` 之外的額外原生編譯保險（人類決定納入，儘管 `git checkout --` 本身已是逐位元組還原）。1 項 Critical（PowerShell 二進位重導向損壞風險）經實測 `adb exec-out screencap -p > file.png` 於 Bash 工具環境下輸出 PNG 簽章逐位元組正確，判定不成立予以駁回，改為在 Global Constraints 註記本計劃假設以 Bash 執行、非 PowerShell。格式意見：「占位」→「佔位」（查證為既有專案用字）已修正；「真機」／「黑盒」查證為既有專案壓倒性慣用字（真機 63 處 vs 實機 19 處），維持原文未採納「實機」／「黑箱」的建議；判準改條列式已在改寫 Q1/Q2 判準時一併採納。
