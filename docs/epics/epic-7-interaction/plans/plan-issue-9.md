# Epic 7 Issue 9 — Spike：直排／橫排翻頁跳頁問題診斷 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在真機上量測「單次觸發（點擊熱區或按音量鍵）」對應「Readium `goForward()`/`goBackward()` 實際推進的視覺頁面量」，涵蓋直排／橫排 × 熱區點擊／音量鍵共 4 種組合（含前進與後退方向），判定「直排每次都跳好幾頁、橫排偶而跳兩頁」的根因，並把結論書面化。

**Architecture:** 本 issue 不預先假設修法。以「暫時性程式碼插樁（在兩條既有的 `goForward()`/`goBackward()` 呼叫點與既有的 `currentLocator` 訂閱各自加上 `Log.i`）→ 真機單次觸發（`adb shell input tap`／`adb shell input keyevent`）→ 每次觸發後等待畫面穩定、擷取螢幕截圖 → 擷取 logcat 比對觸發次數與 `currentLocator` 實際更新次數/幅度/position → 記錄證據 → 判定根因 → 視根因風險決定是否當場修正 → 還原插樁 → 只保留書面報告（與必要的程式碼修正）」的節奏，比照本 Epic Issue 1 spike 先例（`reviews/spike-epub-inputlistener.md`）。插樁程式碼**不進版本控制**（驗證後 `git checkout --` 還原），只有 `reviews/spike-vertical-pagejump.md` 報告、`issues.md` 回填、（若當場修正）根因修法與過時註解修正會被 commit。

**Tech Stack:** Kotlin（`EpubReaderView.kt`）、Readium `kotlin-toolkit` 3.3.0（`OverflowableNavigator.goForward()`/`goBackward()`、`Navigator.currentLocator: StateFlow<Locator>`——既有程式碼已使用，非新 API）、`adb`／真機（9491G，device id `3CEF42ECD491687`，Android 15 / API 35，螢幕解析度 1600×2400，沿用 Issue 1 spike 已確認的裝置資訊；若執行環境已更換，以當下 `flutter devices` 輸出為準，後續步驟一律以 `<device-id>` 表示）。

## Global Constraints

- **4 個量測組合**（逐字對應 `issues.md` Issue 9「診斷方法」）：直排×熱區、直排×音量鍵、橫排×熱區、橫排×音量鍵（均包含前進與後退雙向測試）。
- **兩條既有呼叫路徑，皆需插樁**（`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`）：
  1. `onTap()` 內 `ZoneAction.PREVIOUS_PAGE`/`NEXT_PAGE` 分支（第 1005-1015 行）——熱區點擊觸發，不經過 Dart。
  2. `onMethodCall()` 內 `"nextPage"`/`"previousPage"` case（第 229-241 行）——音量鍵透過 Dart `_handleZoneAction` → `EpubReaderView.nextPage()`/`previousPage()` 觸發；此 case 現有註解寫「僅供 FXL 三欄熱區使用」，**已證實過時**（Issue 7 音量鍵讓所有 EPUB 格式共用同一條路徑），本 issue 驗收標準要求修正。
- **量測基準不是呼叫次數，是每次呼叫後的 `currentLocator` 實際變化**：Issue 1 spike 已驗證「點擊次數與 `onTap()` 呼叫次數 1:1」，但**未量測過「一次呼叫等於推進多少視覺頁面」**——這正是本次要補上的量測，不得重複做 Issue 1 已經做過的事。
- **控制變因**：全程熱區模式維持「右翻頁」（`navZoneMode` 預設值，design.md 決策 #9/#19 已明訂熱區模式與音量鍵映射皆不隨橫直排自動鏡像，見 `issues.md`「開發順序決議」段落），確保 4 組合之間只有「排版方向」與「觸發方式」兩個變數在變動，不受熱區模式差異干擾。
- **測試素材**：`app/test/fixtures/issue9_vertical_pagejump.epub`（已提交版本控制，人類提供的重現素材；既有 `sample_multi_chapter.epub` 等未曾觸發此問題）。
- **每次量測皆為單一、獨立的觸發動作**（1 次點擊或 1 次按鍵），觸發後等待畫面穩定（至少 2 秒）才進行下一次觸發或擷取證據——比照 Issue 1 spike「先前進 3 頁遠離邊界」「連續 3 次確認排除巧合」的方法論，同一組合至少連續觸發 3 次以排除單次偶發。
- **過程中任何暫時性程式碼/素材，驗證完成後一律清理**，不留在版本控制中（`git status` 須乾淨，只保留報告檔、`issues.md` 回填，與若有的根因修正／過時註解修正）。
- **本 issue 不需要新增/修改任何 Dart 端程式碼或單元測試**——純粹是原生端行為的真機觀察（比照 Issue 1）。
- **若根因明確且修法風險低，可在本 issue 內直接修正並如實記錄；若修法有架構影響，記錄具體退回方案供另立實作工單依循**（`issues.md` Issue 9 驗收標準原文）。
- **執行環境**：全文所有 ```bash 區塊皆假設以 POSIX 相容的 Bash 工具（Git Bash / MSYS2）執行，非 PowerShell／`cmd.exe`。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` | 修改（Task 2 暫時性插樁；Task 5 視根因決定是否保留過時註解修正／根因修法，插樁本身一律還原） | 兩條 `goForward()`/`goBackward()` 呼叫點與 `currentLocator` 訂閱的量測插樁 |
| `docs/epics/epic-7-interaction/reviews/spike-vertical-pagejump.md` | 新增 | 診斷報告（證據、結論、對 Issue 9 驗收標準的回應） |
| `docs/epics/epic-7-interaction/issues.md` | 修改 | Issue 9 完成說明 |

---

### Task 1：匯入測試素材，無插樁基準重現（4 組合視覺確認）

**Files:** 無程式碼異動（在目前 `main` 未修改狀態下觀察）

**Interfaces:**
- Consumes：無（本 issue 起始工單）
- Produces：4 組合的無插樁基準截圖，供 Task 3/4 插樁後比對是否與基準時期症狀一致（排除插樁本身改變行為的可能性）

- [x] **Step 1：確認裝置與乾淨基準**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
mkdir -p "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews"
git status --short
flutter devices
```

Expected：`mkdir -p` 建立輸出目錄；`git status --short` 無輸出；`flutter devices` 列出至少 1 台裝置，記下 `<device-id>`（預期 `3CEF42ECD491687`）。

- [x] **Step 2：建置目前（未修改）debug APK 並安裝到真機**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
adb -s <device-id> install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected：建置成功、安裝成功（`Success`）。

- [x] **Step 3：推送測試素材並透過 App 內建匯入流程開啟**

```bash
adb -s <device-id> push "U:/MyDeveloper/AI/elinkBook/app/test/fixtures/issue9_vertical_pagejump.epub" /sdcard/Download/
```

在真機上開啟 App → 圖書庫 →「匯入書籍」→ 系統檔案選擇器 → 導覽至「下載」資料夾 → 選取 `issue9_vertical_pagejump.epub`，等待匯入完成，點擊該書開啟閱讀畫面。確認畫面為流式（reflowable）版面（有正常 AppBar，非固定版面懸浮按鈕）。記錄開啟後預設偵測到的排版方向（自動偵測結果，`_autoDetectedWritingMode`）。

- [x] **Step 4：橫排基準——點擊熱區與音量鍵各觸發 1 次，擷取前後截圖**

若目前非橫排，點擊「⚙️版面」（`Key('reader_layout_settings_button')`）開啟設定，點擊「強制橫排」（`Key('reader_settings_writing_mode_horizontal')`），關閉設定面板。

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-baseline-horizontal-p0.png"
adb -s <device-id> shell input tap 1340 1200
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-baseline-horizontal-tap-p1.png"
adb -s <device-id> shell input keyevent 25
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-baseline-horizontal-key-p2.png"
```

（`1340 1200` 為畫面右側，右翻頁模板下對應「下一頁」，與 Issue 1 spike 使用的座標一致，見 Global Constraints 裝置解析度 1600×2400；`keyevent 25` 為 `KEYCODE_VOLUME_DOWN`，對應下一頁。）

肉眼比對三張截圖：記錄「點擊熱區」與「按音量鍵」這兩次單次觸發，畫面內容各自看起來推進了幾頁份量的內容（粗略目視評估即可，此步驟只是基準，非正式量測數據——正式量測在 Task 3）。

- [x] **Step 5：直排基準——重複 Step 4 的觸發方式**

點擊「⚙️版面」→「強制直排」（`Key('reader_settings_writing_mode_vertical')`）。

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-baseline-vertical-p0.png"
adb -s <device-id> shell input tap 1340 1200
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-baseline-vertical-tap-p1.png"
adb -s <device-id> shell input keyevent 25
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-baseline-vertical-key-p2.png"
```

肉眼比對，記錄粗略觀察結果（預期與人類原始回報一致：直排每次都跳好幾頁，橫排症狀較輕微或不一定每次發生）。

- [x] **Step 6：確認基準階段未變動任何程式碼**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：無 `app/` 底下的異動（本 Task 純真機操作，未修改程式碼）。

---

### Task 2：插樁兩條呼叫路徑與 `currentLocator` 訂閱

**Files:**
- Modify（暫時性，驗證後還原）：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`

**Interfaces:**
- Consumes：無新介面，插樁既有的 `onTap()`（第 994-1025 行）、`onMethodCall()` 的 `"nextPage"`/`"previousPage"` case（第 229-241 行）、`attachNavigator()` 內既有的 `currentLocator.onEach{}` 訂閱（第 957-967 行）
- Produces：Task 3/4 量測所需的 logcat 證據（`EPIC9_SPIKE` 標記）

- [x] **Step 1：插樁 `currentLocator` 訂閱**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` 找到既有的：

```kotlin
            navigatorFragment?.currentLocator
                ?.onEach { locator ->
                    channel.invokeMethod(
                        "onLocatorChanged",
                        mapOf(
                            "locatorJson" to locator.toJSON().toString(),
                            "progression" to locator.locations.totalProgression,
                        ),
                    )
                }
                ?.launchIn(scope)
```

改為（僅在 `onEach` 區塊開頭插入一行 `Log.i`，其餘不動）：

```kotlin
            navigatorFragment?.currentLocator
                ?.onEach { locator ->
                    // TEMP-SPIKE(epic-7-issue-9)：驗證後移除。
                    android.util.Log.i(
                        "EPIC9_SPIKE",
                        "LOCATOR_EMIT href=${locator.href} " +
                            "position=${locator.locations.position} " +
                            "progression=${locator.locations.totalProgression} " +
                            "time=${System.currentTimeMillis()}",
                    )
                    channel.invokeMethod(
                        "onLocatorChanged",
                        mapOf(
                            "locatorJson" to locator.toJSON().toString(),
                            "progression" to locator.locations.totalProgression,
                        ),
                    )
                }
                ?.launchIn(scope)
```

- [x] **Step 2：插樁 `onTap()` 的熱區觸發路徑**

找到既有的：

```kotlin
                        when (navZoneActions.getOrElse(index) { ZoneAction.NONE }) {
                            ZoneAction.PREVIOUS_PAGE -> {
                                // design.md 決策 #15：捲動翻頁模式下左右熱區失效。
                                if (currentPreferences.scroll != true) {
                                    navigatorFragment?.goBackward(animated = false)
                                }
                            }
                            ZoneAction.NEXT_PAGE -> {
                                if (currentPreferences.scroll != true) {
                                    navigatorFragment?.goForward(animated = false)
                                }
                            }
```

改為：

```kotlin
                        when (navZoneActions.getOrElse(index) { ZoneAction.NONE }) {
                            ZoneAction.PREVIOUS_PAGE -> {
                                // design.md 決策 #15：捲動翻頁模式下左右熱區失效。
                                if (currentPreferences.scroll != true) {
                                    // TEMP-SPIKE(epic-7-issue-9)：驗證後移除。
                                    android.util.Log.i(
                                        "EPIC9_SPIKE",
                                        "TRIGGER source=TAP direction=BACKWARD " +
                                            "before=${navigatorFragment?.currentLocator?.value?.locations?.totalProgression} " +
                                            "time=${System.currentTimeMillis()}",
                                    )
                                    navigatorFragment?.goBackward(animated = false)
                                }
                            }
                            ZoneAction.NEXT_PAGE -> {
                                if (currentPreferences.scroll != true) {
                                    // TEMP-SPIKE(epic-7-issue-9)：驗證後移除。
                                    android.util.Log.i(
                                        "EPIC9_SPIKE",
                                        "TRIGGER source=TAP direction=FORWARD " +
                                            "before=${navigatorFragment?.currentLocator?.value?.locations?.totalProgression} " +
                                            "time=${System.currentTimeMillis()}",
                                    )
                                    navigatorFragment?.goForward(animated = false)
                                }
                            }
```

- [x] **Step 3：插樁 `onMethodCall()` 的音量鍵觸發路徑**

找到既有的：

```kotlin
            "nextPage" -> {
                // 僅供 FXL 三欄熱區使用（見 Dart 端 EpubReaderView.build()）；直接呼叫
                // Readium 既有的 OverflowableNavigator.goForward()，animated=false 避免
                // 觸發滑動動畫——這正是本 issue 要繞開的「揭露未縮放內容的可見時間窗口」
                // （見 docs/epics/epic-16-dual-page/issues.md Issue 9）。EpubNavigatorFragment
                // 已實作 OverflowableNavigator，不需要自己重新判斷 spread 要跳幾頁。
                navigatorFragment?.goForward(animated = false)
                result.success(null)
            }
            "previousPage" -> {
                navigatorFragment?.goBackward(animated = false)
                result.success(null)
            }
```

改為：

```kotlin
            "nextPage" -> {
                // 僅供 FXL 三欄熱區使用（見 Dart 端 EpubReaderView.build()）；直接呼叫
                // Readium 既有的 OverflowableNavigator.goForward()，animated=false 避免
                // 觸發滑動動畫——這正是本 issue 要繞開的「揭露未縮放內容的可見時間窗口」
                // （見 docs/epics/epic-16-dual-page/issues.md Issue 9）。EpubNavigatorFragment
                // 已實作 OverflowableNavigator，不需要自己重新判斷 spread 要跳幾頁。
                // TEMP-SPIKE(epic-7-issue-9)：驗證後移除。
                android.util.Log.i(
                    "EPIC9_SPIKE",
                    "TRIGGER source=CHANNEL direction=FORWARD " +
                        "before=${navigatorFragment?.currentLocator?.value?.locations?.totalProgression} " +
                        "time=${System.currentTimeMillis()}",
                )
                navigatorFragment?.goForward(animated = false)
                result.success(null)
            }
            "previousPage" -> {
                // TEMP-SPIKE(epic-7-issue-9)：驗證後移除。
                android.util.Log.i(
                    "EPIC9_SPIKE",
                    "TRIGGER source=CHANNEL direction=BACKWARD " +
                        "before=${navigatorFragment?.currentLocator?.value?.locations?.totalProgression} " +
                        "time=${System.currentTimeMillis()}",
                )
                navigatorFragment?.goBackward(animated = false)
                result.success(null)
            }
```

- [x] **Step 4：重新建置並安裝**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
adb -s <device-id> install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected：建置成功（確認插樁語法正確、`currentLocator?.value` 存取合法），安裝成功。

---

### Task 3：橫排模式量測（熱區＋音量鍵，各雙向連測，每次間隔至少 2 秒）

**Files:** 無新增異動（沿用 Task 2 插樁）

**Interfaces:**
- Consumes：Task 2 的插樁與 logcat 標記格式
- Produces：橫排 2 個組合的量測證據，供 Task 5 彙整

- [x] **Step 1：切換橫排、清空 logcat、重新開書**

在真機上開啟「⚙️版面」→「強制橫排」（若 Task 1 結束時已是橫排可略過切換）。

```bash
adb -s <device-id> logcat -c
```

在 App 內關閉該書再重新開啟（確保從第一頁開始，狀態單純）。

- [x] **Step 2：橫排×熱區——連續 3 次單次點擊（含前進與後退），每次間隔至少 2 秒**

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-h-tap-p0.png"
adb -s <device-id> shell input tap 1340 1200
```

等待至少 2 秒，擷取截圖：

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-h-tap-p1.png"
```

重複「點擊前進熱區 `1340 1200` → 等待 2 秒 → 截圖」1 次存為 `spike9-h-tap-p2.png`，隨後點擊「後退熱區 `266 1200` → 等待 2 秒 → 截圖」1 次存為 `spike9-h-tap-p3-prev.png`。

- [x] **Step 3：橫排×音量鍵——連續 3 次單次按鍵（含音量下鍵與音量上鍵），每次間隔至少 2 秒**

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-h-key-p0.png"
adb -s <device-id> shell input keyevent 25
```

等待至少 2 秒，擷取截圖，重複「音量下鍵 (`25`) → 等待 2 秒 → 截圖」1 次存為 `p2.png`，隨後按「音量上鍵 (`24`) → 等待 2 秒 → 截圖」1 次存為 `p3-prev.png`。

- [x] **Step 4：擷取本 Task 的 logcat**

```bash
adb -s <device-id> logcat -d | grep "EPIC9_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-h-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-h-logcat.txt"
```

肉眼檢視：對每一筆 `TRIGGER` 記錄，其後、下一筆 `TRIGGER` 之前出現的 `LOCATOR_EMIT` 筆數是幾筆、`position` 與 `progression` 變化量各是多少——這是本組合「單次觸發實際推進量」的核心數據。同時比對截圖畫面內容變化是否與 logcat 數據吻合。

---

### Task 4：直排模式量測（熱區＋音量鍵，各雙向連測，每次間隔至少 2 秒）

**Files:** 無新增異動（沿用 Task 2 插樁）

**Interfaces:**
- Consumes：Task 2 的插樁與 logcat 標記格式
- Produces：直排 2 個組合的量測證據，供 Task 5 彙整

- [x] **Step 1：切換直排、清空 logcat、重新開書**

在真機上開啟「⚙️版面」→「強制直排」。

```bash
adb -s <device-id> logcat -c
```

在 App 內關閉該書再重新開啟（確保從第一頁開始）。

- [x] **Step 2：直排×熱區——連續 3 次單次點擊（含前進與後退），每次間隔至少 2 秒**

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-v-tap-p0.png"
adb -s <device-id> shell input tap 1340 1200
```

等待至少 2 秒，擷取截圖，重複「點擊前進熱區 `1340 1200` → 等待 2 秒 → 截圖」1 次存為 `spike9-v-tap-p2.png`，隨後點擊「後退熱區 `266 1200` → 等待 2 秒 → 截圖」1 次存為 `spike9-v-tap-p3-prev.png`。

- [x] **Step 3：直排×音量鍵——連續 3 次單次按鍵（含音量下鍵與音量上鍵），每次間隔至少 2 秒**

```bash
adb -s <device-id> exec-out screencap -p > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-v-key-p0.png"
adb -s <device-id> shell input keyevent 25
```

等待至少 2 秒，擷取截圖，重複「音量下鍵 (`25`) → 等待 2 秒 → 截圖」1 次存為 `p2.png`，隨後按「音量上鍵 (`24`) → 等待 2 秒 → 截圖」1 次存為 `p3-prev.png`。

- [x] **Step 4：擷取本 Task 的 logcat**

```bash
adb -s <device-id> logcat -d | grep "EPIC9_SPIKE" > "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-v-logcat.txt"
cat "U:/MyDeveloper/AI/elinkBook/tmp/epic-7/reviews/spike9-v-logcat.txt"
```

分析方式同 Task 3 Step 4。

- [x] **Step 5：清理真機上的匯入書籍與暫存檔**

```bash
adb -s <device-id> shell rm -f /sdcard/Download/issue9_vertical_pagejump.epub
```

在 App 內刪除該書（圖書庫 → 長按/滑動該書 → 刪除）。（**實作偏離**：`library_screen.dart` 目前未串接 `deleteBook()`，圖書庫畫面無刪除書籍入口——這是 `epic-1-library` 尚未實作的既有現況，非本 issue 範圍。Task 4 實際改用裝置端 `library.db` 直接刪除對應資料列達成等價效果，已驗證清理完整、其餘既有書籍不受影響。）

---

### Task 5：彙整報告、判定根因、修正過時註解、視情況修正、還原插樁

**Files:**
- Create：`docs/epics/epic-7-interaction/reviews/spike-vertical-pagejump.md`
- Modify：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（先還原 Task 2 插樁，再視需要修正過時註解／根因）

**Interfaces:**
- Consumes：Task 1-4 的截圖與 logcat 證據
- Produces：`issues.md` Issue 9 回填所需的最終結論

- [x] **Step 1：先還原 Task 2 的暫時性插樁**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git diff --stat app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git checkout -- app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
```

Expected：`git diff --stat` 顯示該檔案有異動（確認插樁確實存在過），`git checkout --` 後完全還原。**先還原再進行 Step 2 的修正**，避免插樁殘留與正式修正混在同一批未還原的變更裡難以分辨。

- [x] **Step 2：撰寫診斷報告**

在 `docs/epics/epic-7-interaction/reviews/spike-vertical-pagejump.md` 寫入以下結構（依 Task 1-4 的實際觀察結果填入，不得照抄本範本的佔位文字）：

```markdown
# Epic 7 Issue 9 — Spike：直排／橫排翻頁跳頁問題診斷報告

**驗證日期：** <實際日期>
**驗證裝置：** <實際 flutter devices 輸出>
**測試素材：** app/test/fixtures/issue9_vertical_pagejump.epub

## 無插樁基準重現（Task 1）

<記錄 4 個粗略觀察：橫排×熱區、橫排×音量鍵、直排×熱區、直排×音量鍵，是否與人類原始回報症狀一致>

## 橫排量測（Task 3）

### 橫排×熱區
<3 次觸發，每次的 LOCATOR_EMIT 筆數、position 與 progression 變化量、截圖對應的視覺頁面推進量>

### 橫排×音量鍵
<同上>

## 直排量測（Task 4）

### 直排×熱區
<同上>

### 直排×音量鍵
<同上>

## 根因判定

<明確判定：觸發端重複呼叫（若某次觸發後 LOCATOR_EMIT 筆數 > 1）／Readium 分頁計算誤差（若每次觸發皆恰好 1 筆 LOCATOR_EMIT，但 progression 變化量遠超「一頁」應有的量）／其他，並附具體證據引用（截圖檔名、logcat 行）>

## 對 Issue 9 驗收標準的回應

<是否已修正過時註解；根因是否明確且風險低到可直接修正（若是，說明修法與驗證方式）；若需另立實作工單，說明具體退回方案>
```

- [x] **Step 3：修正過時註解（不論根因為何，皆須執行）**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` 找到 `"nextPage"` case 的既有註解：

```kotlin
            "nextPage" -> {
                // 僅供 FXL 三欄熱區使用（見 Dart 端 EpubReaderView.build()）；直接呼叫
                // Readium 既有的 OverflowableNavigator.goForward()，animated=false 避免
                // 觸發滑動動畫——這正是本 issue 要繞開的「揭露未縮放內容的可見時間窗口」
                // （見 docs/epics/epic-16-dual-page/issues.md Issue 9）。EpubNavigatorFragment
                // 已實作 OverflowableNavigator，不需要自己重新判斷 spread 要跳幾頁。
                navigatorFragment?.goForward(animated = false)
                result.success(null)
            }
```

把註解第一句改為：

```kotlin
            "nextPage" -> {
                // 原僅供 FXL 三欄熱區使用（見 Dart 端 EpubReaderView.build()），現
                // epic-7-interaction Issue 7 音量鍵翻頁讓所有 EPUB 格式（含流式）
                // 共用同一條路徑——見 EpubReaderView._handleZoneAction() → Dart
                // static helper nextPage()/previousPage() → 此 method channel case。
                // 直接呼叫 Readium 既有的 OverflowableNavigator.goForward()，
                // animated=false 避免觸發滑動動畫——這正是本 issue 要繞開的「揭露
                // 未縮放內容的可見時間窗口」（見 docs/epics/epic-16-dual-page/issues.md
                // Issue 9）。EpubNavigatorFragment 已實作 OverflowableNavigator，
                // 不需要自己重新判斷 spread 要跳幾頁。
                navigatorFragment?.goForward(animated = false)
                result.success(null)
            }
```

- [x] **Step 4：視根因判定結果決定是否當場修正**（判定退回：根因為 Readium reflowable Navigator 內部行為，App 層兩條路徑逐行確認呼叫完全相同、無放大/節流，修法有架構影響，記錄退回方案於報告與 `issues.md`）

**若 Step 2 判定根因明確且修法風險低**（例如：發現送給 Readium 的 `EpubPreferences` 有某個直排相關欄位設定錯誤，或 `goForward()`/`goBackward()` 呼叫需要改用 Readium 提供的其他等效 API）：直接修正該處程式碼，並在報告的「對 Issue 9 驗收標準的回應」段落記錄修法與驗證方式（重新走一次 Task 3/4 對應組合的量測流程，確認修正後單次觸發確實只推進一頁）。

**若根因不明確、或修法需要更動架構**（例如懷疑是 Readium 函式庫本身在特定直排內容結構下的既有 bug，需要升版或繞過）：不在本 issue 內強行修正，在報告與 `issues.md` 回填段落記錄具體退回方案（例如：「建議另立實作工單，方向為 X」），供後續另立工單依循。

- [x] **Step 5：確認清理完整**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git status --short
```

Expected：只剩 `docs/epics/epic-7-interaction/reviews/spike-vertical-pagejump.md`（新增）與 `app/android/.../EpubReaderView.kt`（僅 Step 3 的註解修正，與若有 Step 4 的根因修正——皆為正式異動，非插樁殘留）。截圖與 logcat 檔案位於 `tmp/epic-7/reviews/`，已被根目錄 `.gitignore`（`tmp/`）排除。

- [x] **Step 6：`flutter analyze` 與原生端編譯驗證**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected：`No issues found!`

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter build apk --debug
```

Expected：建置成功，無 Kotlin 編譯錯誤。

- [x] **Step 7：更新 `issues.md`——回填 Issue 9 結論**

把 Issue 9 的 `**Status:**`（現為 `ready-for-agent`）改為完成狀態，比照 Issue 1 既有完成說明風格，內容需涵蓋：根因判定結論、是否已當場修正（若是，簡述修法；若否，記錄退回方案與建議的後續工單方向）、過時註解已修正、引用診斷報告路徑 `reviews/spike-vertical-pagejump.md`。

- [x] **Step 8：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add docs/epics/epic-7-interaction/reviews/spike-vertical-pagejump.md
git add docs/epics/epic-7-interaction/issues.md
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git commit -m "docs(epic-7): Issue 9 spike——直排/橫排翻頁跳頁問題診斷與收斂"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 9「描述」「診斷方法」「驗收標準」逐項對應：
- 4 種組合（含前後雙向）的量測 → Task 3（橫排 2 組合）＋ Task 4（直排 2 組合）
- 「單次觸發→實際頁面推進量」而非只數呼叫次數 → Task 2 的 `currentLocator` 訂閱插樁（`LOCATOR_EMIT` 記錄，含 `position` 與 `progression`），Task 3/4 的截圖佐證
- 「每項量測需附具體數據，不接受主觀判斷」→ Task 3/4 皆要求 logcat 數據 + 截圖雙重佐證
- 「明確判定根因，寫入驗證報告」→ Task 5 Step 2
- 「`"nextPage"`/`"previousPage"` 過時註解已修正」→ Task 5 Step 3（不論根因為何皆執行）
- 「根因明確且風險低可直接修正；否則記錄退回方案」→ Task 5 Step 4
- 「暫時性插樁程式碼已清理」→ Task 5 Step 1（先還原）＋ Step 5（確認）

**占位符掃描**：全文無 TBD/待補字樣；Task 5 Step 2 報告範本的「<記錄...>」是驗證結果本質使然（比照 Issue 1 spike Self-Review 對同類段落的既有認定），所有涉及程式碼/指令的步驟皆已提供完整可執行內容。

**型別一致性**：`currentLocator?.value?.locations?.totalProgression`／`locator.href`／`locator.locations.totalProgression`／`locator.locations.position` 皆沿用 `EpubReaderView.kt` 既有第 957-967 行、第 709 行、第 1158-1163 行已驗證可行的存取方式，未發明新用法；`System.currentTimeMillis()` 為標準 Kotlin/JVM API。插樁的 4 個 `Log.i` 呼叫點與 Task 5 Step 1 的還原範圍完全一致。

**與 Issue 1 spike 的分工邊界**：Issue 1 已驗證「點擊次數與 `onTap()` 呼叫次數 1:1、無重複觸發」，本計劃刻意不重複驗證這件事，而是延伸驗證「呼叫之後 Readium 內部實際推進了多少」——兩者是互補而非重複的量測範圍，已在 Global Constraints 明確說明。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-7-interaction/plans/plan-issue-9.md`。兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
