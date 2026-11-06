# Epic 66 Issue 7：Windows 鍵盤快捷鍵與 F11 視窗全螢幕 實作計畫

> **給執行計畫的代理：** 必須使用 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans 逐 Task 執行。步驟用 `- [ ]` 追蹤，完成一步就把它改成 `- [x]`。

**Goal：** 讓 Windows 使用者用鍵盤翻頁（←／→、↑／↓、PageUp／PageDown、Space、Home／End）、用 Ctrl+F 開書內搜尋、用 F11 切換視窗全螢幕，Esc 依序處理浮層與全螢幕；Android 與其他平台零改動。

**Architecture：** 鍵盤是「熱區動作」的另一種入口：純邏輯 `readerKeyCommandFor` 把按鍵對應成 `ReaderKeyCommand`，`ReaderScreen` 在 Windows 註冊全域 `HardwareKeyboard` 處理器（先於焦點樹消費事件）後轉成既有的 `_handleZoneAction`／`ReaderSurface.jumpTo`／`_openBookSearch`。視窗全螢幕由 `WindowFullscreenController`（`window_manager` 0.5.2 實作，維護同步可讀的 `isFullscreenNow` 快取）與掛在 `MaterialApp.builder` 的 `WindowFullscreenShortcuts` 處理：F11 用全域 `HardwareKeyboard` 處理器（不依賴焦點）；Esc **不手動攔截**，而是在 builder 層以 `Actions` 覆寫 `DismissIntent`，由 Flutter 從焦點往上找第一個「啟用中」的動作——對話框的動作（`barrierDismissible` 時啟用）先於我們的「退出視窗全螢幕」動作。EPUB 在 WebView2 有焦點時按鍵是否進 Flutter，由 Task 1 實測決定走方案 A（全域處理器就夠）或方案 B（`main.js` 轉送，含去重）。

**Tech Stack：** Dart／Flutter 3.41.9、`window_manager` 0.5.2（固定版本）、`flutter_inappwebview`（既有）、foliate-js `main.js`、Windows 實機。

**Spec：** 沒有獨立 spec。權威依據是 `issues.md` 的「Issue 7 範圍／過關條件／單元測試要求」、`epic.md` 決策 3、24、26，以及 `CONTEXT.md`「鍵盤快捷鍵」「視窗全螢幕」。

## Global Constraints

- **語言：** 文件、註解、測試名稱一律正體中文；程式碼命名維持英文慣例。本 Issue 不新增任何 UI 字串（沒有說明畫面、沒有提示），因此不改 arb。
- **Flutter 3.41.9：** 不得使用此版本沒有的 API；`flutter analyze` 必須 `No issues found!`。**不得升級 Flutter 或其他既有套件版本**（升級是 Issue 6）。`window_manager` 固定 `0.5.2`，**不用 `^`**，pubspec 註解說明為何（0.6.0 要求 Flutter ≥ 3.47 且改用 `nativeapi`）。
- **`pubspec.lock` 衛生：** 本機 `pub get` 會把 `intl`、`matcher`、`meta`、`pdfrx_engine`、`test_api`、`vector_math` 降級（`pubspec.lock` 與本機 Flutter 的既有落差，留給 Issue 6）。**不得把這些降級 commit 進來**：加依賴後 `git diff app/pubspec.lock` 只允許出現 `window_manager` 與 `screen_retriever`、`screen_retriever_linux`、`screen_retriever_macos`、`screen_retriever_platform_interface`、`screen_retriever_windows`；其餘版本異動一律還原。`app/windows/flutter/generated_plugin*` 加入 `window_manager` 外掛註冊屬必要，要 commit。
- **只在 Windows 生效：** 所有新增按鍵處理器、`main.js` 轉送、Ctrl+F、搜尋畫面自動聚焦都用 `isWindowsPlatform`（`lib/platform/platform_support.dart`）閘門；非 Windows 不註冊、不掛載、不改變任何既有行為。測試以 `debugDefaultTargetPlatformOverride = TargetPlatform.windows` 切換，且必須 `addTearDown` 還原。
- **不改介面簽章：** `ReaderScreen`、`ReaderSurface`、`FoliateReaderView` 既有公開簽章不變；只允許新增選用參數或內部成員。
- **不碰 PDF 既有 `_onPagedKey`：** 全域處理器先於焦點樹消費事件，PDF 不需修改；非 Windows 的 PDF 行為逐字不變。
- **Windows 環境：** 多數原始檔是 CRLF，Edit 的定位字串不要含換行；**不要對整個既有檔案跑 `dart format`**（base 版本不一定已格式化，會產生歷史噪音；新檔可以格式化）；`git add` 一律明確列檔；不要用 `python`（本機只有 Windows 商店的空殼）。
- **Windows 實機驗證要完整重建：** 加入 `window_manager` 原生外掛後，要用 `flutter run -d windows` 重新建置（觸發 CMake 重編外掛），不可對舊的執行中行程 hot reload／hot restart。
- **測試範圍（`CLAUDE.md`）：** 單一 Task 只跑異動觸及的測試檔；完整 `flutter test` 只在最後一個 Task 跑一次，`run_in_background`。
- **提交前：** `flutter analyze` 乾淨；動到 `lib/` 的 Key 後跑 `node tool/check_integration_keys.js`；動到 `main.js` 後跑 `node tool/check_foliate_es_compat.js`。
- **Commit：** 每個 Task 一個 commit，訊息結尾附 `Co-Authored-By` 行；推送與開 PR 前由使用者確認。工作目錄是 worktree `.worktrees/epic-66-issue-7`，分支 `feat/epic-66-issue-7-keyboard`，所有指令在該 worktree 的 `app/` 下執行。

## 已決策

使用者已確認（2026-11-06 `/grill-with-docs`，Q1 到 Q11）：翻頁鍵清單；直排 ←／→ 鏡像；F11 是獨立的「視窗全螢幕」、不寫偏好、不持久化、任何畫面可用；Esc 依序關浮層→退出全螢幕→什麼都不做（不返回書架）；Ctrl+F 只在閱讀器內；輸入框或浮層時翻頁鍵暫停、F11 永遠有效；捲動模式與熱區動作一致；不加其他快捷鍵、不可自訂、無說明畫面、不處理滑鼠滾輪；「全螢幕模式」偏好項留給平台專屬功能隱藏 Issue。

我的決定（使用者沒明講的細節，請審查時確認）：

1. **全域 `HardwareKeyboard` 處理器而非 `Shortcuts` widget：** 它先於焦點樹、不依賴焦點在哪個節點；代價是必須自己檢查「路由是否最上層」與「文字輸入框是否有焦點」。
2. **Q6 的「已有搜尋面板」在程式中就是搜尋路由 `BookSearchScreen` 已疊在閱讀器上：** 此時閱讀器處理器因路由不是最上層而暫停，Ctrl+F 由 `BookSearchScreen` 自己處理。
3. **PDF 不鏡像：** 直排只存在於 EPUB；PDF 的 ←／→ 固定為上一頁／下一頁，與 PDF 熱區（沒有鏡像）一致，不隨雙頁裝訂方向改變。
4. **Home／End 在 EPUB 用整本進度 0.0／1.0**（`ReaderJumpTarget(progression:)`），在 PDF 用頁碼 0／最後一頁（`ReaderJumpTarget(pdfPageIndex:)`），並比照 `_handleZoneAction` 補 `_clearSearchJumpHighlight()` 與 `_session.recordActivity()`。
5. **不可關閉的對話框（`barrierDismissible: false`）開著時按 Esc，會退出視窗全螢幕：** 因為它的 `DismissAction` 未啟用，會落到我們的動作。已知邊界，不另外處理。
6. **Esc 的優先序靠 `DismissIntent` 覆寫，不靠手動攔截（計畫審查 C-1，查證屬實，取代原先的 `Focus(onKeyEvent:)` 方案）：** `WidgetsApp` 的 `Shortcuts`（`app.dart:1812`，把 Esc 轉成 `DismissIntent`）包在 `builder` 外層，`ModalRoute` 的 `_DismissModalAction.isEnabled` 只看 `barrierDismissible`；`builder` 層的 `Focus(onKeyEvent:)` 會搶在轉換之前吃掉 Esc，讓對話框關不掉。改成 builder 層的 `Actions({DismissIntent: …})`：Flutter 從焦點往上找第一個啟用中的動作，對話框先，我們後。
7. **Esc 與閱讀器內層狀態（計畫審查 I-3，部分採納）：** 文字選取中按 Esc → 清除選取並消費；PDF 手動裁切模式中按 Esc → **只吞掉**，不退出裁切（延續既有「返回鍵不離開裁切模式」的決策，見 `reader_screen.dart` 的 `PopScope` 註解），也不退出全螢幕。**不處理 TTS 面板**：`_cbzTtsPanelVisible`／`_ttsPanelCollapsed` 是展開收合狀態而非浮層，「Esc 關閉」語意不明，列為已知邊界。
8. **閱讀器命令的防護（計畫審查 I-2）：** `_openBookFlow.state is! OpenBookRendered`（載入中、探測中、失敗、重新連結）或 `_cropEditModeActive` 時，翻頁、Home／End、Ctrl+F 一律忽略。
9. **方案 B 的去重（計畫審查 C-3）：** 同一個按鍵若在 50 毫秒內已由另一個來源（Flutter 全域處理器 vs `main.js` 轉送）處理過，後到的忽略；同一來源的連續事件（按住不放）不去重。
10. **搜尋畫面在 Windows 開啟即聚焦輸入框（計畫審查 I-1）：** 使用者按 Ctrl+F 的期待是馬上能打字；Android 維持 `autofocus: false`（避免觸控裝置軟鍵盤自動彈出）。搜尋畫面的 Ctrl+F 用全域 `HardwareKeyboard` 處理器而非 `CallbackShortcuts`（後者在焦點節點不在其子樹時收不到事件）。

## Review Focus

1. 按住方向鍵不放（`KeyRepeatEvent`）：連續翻頁、不丟例外（Task 5）。
2. 帶修飾鍵的組合：Alt+←（瀏覽器上一頁的習慣）、Ctrl+→、Ctrl+Shift+F、Meta 組合不得誤觸發翻頁或搜尋（Task 2）。
3. 書籍尚在載入中、載入失敗、PDF 手動裁切模式時按翻頁鍵、Home／End、Ctrl+F：忽略、不崩潰、不開搜尋頁（Task 5）。
4. 離開閱讀器後按方向鍵：處理器已移除、不對已關閉的畫面動作；重新開書只有一份處理器（Task 5）。
5. 連按 F11：進行中旗標避免重入；全螢幕狀態與控制器的同步快取一致（Task 3）。
6. 視窗全螢幕時，有文字選取、PDF 裁切模式、dismissible 對話框三種內層狀態按 Esc：都不得退出全螢幕（Task 4、5）。
7. 方案 B 下 CapsLock 開啟時 `Ctrl+F` 的 `e.key` 是 `'F'`；同一按鍵同時從 Flutter 與 WebView 送達：只處理一次（Task 6）。

---

### Task 1：實測 WebView2 有焦點時的按鍵歸屬（不產出正式程式）

**Files：**
- Create: `docs/epics/epic-66-windows-port/issue-7-report.md`（只寫「實測結論」一節；其餘章節留待 Task 8）
- 暫時修改（**不得 commit**，實測後 `git checkout --` 還原）：`app/lib/reader/foliate_reader_view.dart`、`app/android/app/src/main/assets/foliate/main.js`、`app/lib/main.dart`

**Interfaces：**
- Produces: 一個明確的結論「方案 A」或「方案 B」，寫在 `issue-7-report.md` 的「實測結論」一節，後續 Task 6 依此分支。

- [x] **Step 1：加暫時探針。** (a) 在 `main.dart` 的 `main()` 內於 `runApp` 之前呼叫 `HardwareKeyboard.instance.addHandler((e) { debugPrint('[keyprobe flutter] ${e.runtimeType} ${e.logicalKey.keyLabel}'); return false; })`；(b) 在 `main.js` 暫時加 `window.addEventListener('keydown', e => console.log('[keyprobe web] ' + e.key), true)`，並讓這行 log 能被看見（`InAppWebView` 的 `onConsoleMessage` 已有 `ReaderConsoleLog` 管道，若沒有輸出則暫時把訊息 `callHandler` 給 Dart 再 `debugPrint`）。
- [x] **Step 2：實測。** `flutter run -d windows`（完整重建），開一本 EPUB 並**點一下書頁內容讓 WebView2 取得焦點**，依序送出：←、→、↑、↓、PageUp、PageDown、Space、Home、End、Ctrl+F、F11、Esc。可請使用者實際按鍵，或用 PowerShell 的 `[System.Windows.Forms.SendKeys]::SendWait(...)` 對前景視窗送鍵（需先 `Add-Type -AssemblyName System.Windows.Forms` 並確認 App 視窗在前景）。對每個按鍵記錄 `[keyprobe flutter]` 與 `[keyprobe web]` **哪一邊出現、是否兩邊都出現**。再點一下書頁以外的 Flutter 區域（例如工具列空白處）重複一次。
- [x] **Step 3：判定並記錄。** 若焦點在書頁時**每一個**按鍵（尤其是 F11 與 Esc）都出現 `[keyprobe flutter]` → 方案 A。只要有任何一個按鍵只出現 `[keyprobe web]` 或兩邊都沒出現 → 方案 B。把完整的「按鍵 × 兩種焦點位置 × 哪一邊收到（含兩邊都收到）」表格、使用的送鍵方式與判定結果寫入 `issue-7-report.md`「實測結論」；**「兩邊都收到」的按鍵要特別標出**，它們決定方案 B 去重的必要性。
- [x] **Step 4：還原探針。** `git checkout -- app/lib/main.dart app/lib/reader/foliate_reader_view.dart app/android/app/src/main/assets/foliate/main.js`，確認 `git status` 只剩 `issue-7-report.md`。
- [x] **Step 5：Commit：** `git add docs/epics/epic-66-windows-port/issue-7-report.md`，訊息 `docs(epic-66): Issue 7 實測 WebView2 按鍵歸屬並決定方案（Task 1）`。

---

### Task 2：按鍵對應的純邏輯 `readerKeyCommandFor`

**Files：**
- Create: `app/lib/reader/reader_key_command.dart`
- Test: `app/test/reader/reader_key_command_test.dart`

**Interfaces：**
- Produces:
  - `enum ReaderKeyCommand { previousPage, nextPage, firstPage, lastPage, openSearch }`
  - `ReaderKeyCommand? readerKeyCommandFor(LogicalKeyboardKey key, {bool shift = false, bool control = false, bool alt = false, bool meta = false, required bool verticalWriting})`

規則：`arrowLeft` 橫排為上一頁、`verticalWriting` 時為下一頁；`arrowRight` 相反；`arrowUp`、`pageUp` 為上一頁；`arrowDown`、`pageDown` 為下一頁；`space` 為下一頁、`shift` 為上一頁；`home` 為首頁、`end` 為末頁；`control` 且僅 `control`（無 shift／alt／meta）加 `keyF` 為 `openSearch`；其他一律 `null`。**翻頁類按鍵（含 Space、Home、End）只要 `control`、`alt`、`meta` 任一為真就回傳 `null`**；`shift` 只影響 Space，其他按鍵帶 `shift` 時照常。

- [x] **Step 1：寫失敗測試**（`verticalWriting` 兩種各跑一遍）：
  - `橫排：←／↑／PageUp／Shift+Space 為上一頁，→／↓／PageDown／Space 為下一頁`。
  - `直排：←／→ 左右鏡像，↑／↓／PageUp／PageDown／Space 不受影響`。
  - `Home 為首頁、End 為末頁（兩種書寫方向相同）`。
  - `Ctrl+F 為開啟搜尋；Ctrl+Shift+F、Ctrl+Alt+F、單獨 F 皆為 null`。
  - `Alt+←、Ctrl+→、Meta+↓、Ctrl+Space、Ctrl+Home 皆為 null`（Review Focus 2）。
  - `無關按鍵（a、Enter、Tab、F5）為 null`。
- [x] **Step 2：執行確認失敗：** `flutter test test/reader/reader_key_command_test.dart`；預期編譯失敗（檔案不存在）。
- [x] **Step 3：實作 `reader_key_command.dart`**，簽章與規則如上，附中文文件註解說明鏡像規則與修飾鍵規則。
- [x] **Step 4：執行確認通過：** 同 Step 2 指令。
- [x] **Step 5：Commit：** `git add app/lib/reader/reader_key_command.dart app/test/reader/reader_key_command_test.dart`，訊息 `feat(keyboard): 閱讀器按鍵對應純邏輯（epic-66 Issue 7 Task 2）`。

---

### Task 3：`WindowFullscreenController` 與 `window_manager` 依賴

**Files：**
- Modify: `app/pubspec.yaml`（加 `window_manager: 0.5.2` 並註解）、`app/pubspec.lock`（只留允許的異動）、`app/windows/flutter/generated_plugin_registrant.cc`、`generated_plugin_registrant.h`、`generated_plugins.cmake`（外掛註冊）
- Create: `app/lib/windows/window_fullscreen_controller.dart`
- Modify: `app/lib/main.dart`（Windows 才初始化並設定 `activeWindowFullscreenController`）
- Test: `app/test/windows/window_fullscreen_controller_test.dart`

**Interfaces：**
- Produces（皆在 `window_fullscreen_controller.dart`）：
  - `abstract class WindowFullscreenController { bool get isFullscreenNow; Future<bool> isFullscreen(); Future<void> setFullscreen(bool value); }`。**`isFullscreenNow` 是同步可讀的快取**（初始 `false`，因為 App 以一般視窗啟動），供 `Action.isEnabled` 這類必須同步回答的地方使用（計畫審查 C-2）；`isFullscreen()` 是向視窗查詢的權威值，查到後同步更新快取。
  - `class WindowManagerFullscreenController with WindowListener implements WindowFullscreenController`：建構時 `windowManager.addListener(this)`；`onWindowEnterFullScreen()`／`onWindowLeaveFullScreen()` 把快取設為 `true`／`false`（使用者以其他方式如系統快捷鍵進出全螢幕也能同步）；`setFullscreen(v)` 呼叫 `windowManager.setFullScreen(v)` 成功後更新快取，丟例外時快取維持原值並重新拋出；`isFullscreen()` 呼叫 `windowManager.isFullScreen()` 並同步快取。
  - `WindowFullscreenController? activeWindowFullscreenController`：頂層可寫變數，預設 `null`；`main()` 在 Windows 設定，供 Task 4、6 取用（比照 `foliate_native_bridge.dart` 的 `cacheBookForServing` 頂層可覆寫慣例）。
  - `Future<void> toggleWindowFullscreen(WindowFullscreenController controller)`：讀 `await controller.isFullscreen()` 後設為相反值；上一次尚未完成時直接 `return`（模組內進行中旗標）；控制器丟例外時吞掉（`debugPrint`），並確保旗標在 `finally` 還原。
  - `Future<bool> exitWindowFullscreenIfActive(WindowFullscreenController controller)`：`controller.isFullscreenNow` 為 `false` 時回傳 `false` 且不呼叫 `setFullscreen`；否則（受同一個進行中旗標保護）`setFullscreen(false)` 並回傳 `true`，例外同樣吞掉。

- [x] **Step 1：寫失敗測試**（以測試內的 `FakeWindowFullscreenController`：`setFullscreen` 會更新 `isFullscreenNow` 並記錄呼叫，可設定延遲與例外）：
  - `非全螢幕時 toggle 設為 true，全螢幕時 toggle 設為 false`。
  - `上一次 toggle 尚未完成時再呼叫會被忽略，只設定一次`（Review Focus 5：用 `Completer` 卡住 `isFullscreen`，連呼叫兩次）。
  - `控制器丟例外時 toggle 不外洩，之後仍可再次 toggle`（旗標已還原）。
  - `exitWindowFullscreenIfActive：isFullscreenNow 為 true 時呼叫 setFullscreen(false) 並回傳 true；為 false 時回傳 false 且不呼叫`。
  - `toggle 進行中呼叫 exitWindowFullscreenIfActive 會被忽略（共用旗標）`。
- [x] **Step 2：執行確認失敗：** `flutter test test/windows/window_fullscreen_controller_test.dart`；預期編譯失敗。
- [x] **Step 3：實作。** 先 `flutter pub add window_manager:0.5.2`（或手改 pubspec 再 `flutter pub get`），依 Global Constraints 檢查並還原 `pubspec.lock` 的無關降級；在 pubspec 該行上方加中文註解（固定原因、0.6.0 不可用、升級見 Issue 6）。建立 `window_fullscreen_controller.dart`。`main.dart` 在 Windows 才 `await windowManager.ensureInitialized();` 並 `activeWindowFullscreenController = WindowManagerFullscreenController();`（位置：既有 `if (isWindowsPlatform)` 區塊，`initAppWebViewEnvironment` 所在處附近）。`WindowManagerFullscreenController` 依賴真實的 `window_manager`，不在單元測試中直接實例化；真實行為由人工驗證覆蓋。
- [x] **Step 4：執行確認通過：** 同 Step 2 指令；`flutter analyze` 乾淨；`git diff app/pubspec.lock` 只含允許的異動。
- [x] **Step 5：Commit：** 明確列出 `app/pubspec.yaml`、`app/pubspec.lock`、`app/windows/flutter/generated_plugin_registrant.cc`、`app/windows/flutter/generated_plugin_registrant.h`、`app/windows/flutter/generated_plugins.cmake`、`app/lib/windows/window_fullscreen_controller.dart`、`app/lib/main.dart`、測試檔，訊息 `feat(keyboard): 視窗全螢幕控制器與 window_manager 0.5.2（epic-66 Issue 7 Task 3）`。

---

### Task 4：`WindowFullscreenShortcuts`——F11 與 Esc

**Files：**
- Create: `app/lib/windows/window_fullscreen_shortcuts.dart`
- Modify: `app/lib/main.dart`（`ElinkBookApp` 的 `MaterialApp` 加 `builder`）
- Test: `app/test/windows/window_fullscreen_shortcuts_test.dart`

**Interfaces：**
- Consumes: Task 3 的 `WindowFullscreenController`、`activeWindowFullscreenController`、`toggleWindowFullscreen`、`exitWindowFullscreenIfActive`。
- Produces: `class WindowFullscreenShortcuts extends StatefulWidget`，建構子 `WindowFullscreenShortcuts({super.key, WindowFullscreenController? controller, required Widget child})`；實際使用的控制器是 `controller ?? activeWindowFullscreenController`。
  - 控制器為 `null`（非 Windows）：`build` 直接 `return child`，不註冊任何處理器、不插入任何 widget。
  - 否則：`initState` 註冊 `HardwareKeyboard.instance.addHandler`、`dispose` 移除；處理器只處理**無任何修飾鍵**的 `KeyDownEvent` F11（忽略 `KeyRepeatEvent`）→ `toggleWindowFullscreen` 並回傳 `true`（消費），其他事件回傳 `false`。`build` 回傳 `Actions(key: const Key('window_fullscreen_dismiss_actions'), actions: {DismissIntent: _ExitFullscreenDismissAction}, child: child)`。
  - `_ExitFullscreenDismissAction extends Action<DismissIntent>`：`isEnabled(intent)` 回傳 `controller.isFullscreenNow`（同步）；`invoke` 呼叫 `exitWindowFullscreenIfActive(controller)`。Esc→`DismissIntent` 的轉換由 `MaterialApp` 內建的 `Shortcuts` 負責，**本 widget 不處理任何 Esc 按鍵事件**。

- [ ] **Step 1：寫失敗測試**（Windows 平台 override；假控制器；`MaterialApp(builder: (c, child) => WindowFullscreenShortcuts(controller: fake, child: child!), home: ...)`；`tester.sendKeyEvent(LogicalKeyboardKey.f11)`／`escape`；dialog 用 `showDialog`）：
  - `F11 在任何畫面都切換視窗全螢幕`（首頁與 push 之後的第二個路由各按一次）。
  - `F11 按住不放（KeyRepeatEvent）只切換一次`；`Alt+F11、Ctrl+F11 不切換`。
  - `視窗全螢幕且沒有浮層時按 Esc：退出全螢幕`。
  - `非全螢幕時按 Esc：不呼叫 setFullscreen`；此時有 dismissible 對話框則照常關閉。
  - `全螢幕且有 dismissible 對話框：第一次 Esc 只關對話框、全螢幕維持；第二次 Esc 才退出`（Review Focus 6，鎖定 C-1 的機制）。
  - `全螢幕且有 barrierDismissible: false 的對話框：Esc 退出全螢幕`（已知邊界，決定 5）。
  - `切換畫面（push／pop）本身不呼叫 setFullscreen`（全螢幕狀態不被重置）。
  - `非 Windows（預設平台）或控制器為 null 時：找不到 Key('window_fullscreen_dismiss_actions')，F11 不呼叫任何控制器`。
- [ ] **Step 2：執行確認失敗：** `flutter test test/windows/window_fullscreen_shortcuts_test.dart`；預期編譯失敗。
- [ ] **Step 3：實作 `window_fullscreen_shortcuts.dart`**，並在 `main.dart` 的 `MaterialApp` 加 `builder: (context, child) => WindowFullscreenShortcuts(child: child ?? const SizedBox.shrink())`（既有 `MaterialApp` 沒有 `builder`）。若測試證明 Esc 在畫面沒有任何焦點節點時到不了 `Actions`，記一筆 `Ruling` 並與使用者確認，不要退回 `Focus(onKeyEvent:)` 方案（見決定 6）。
- [ ] **Step 4：執行確認通過：** 同 Step 2 指令；再跑 `flutter test test/elinkbook_app_wiring_test.dart` 確認 App 接線測試沒壞。
- [ ] **Step 5：Commit：** `git add app/lib/windows/window_fullscreen_shortcuts.dart app/lib/main.dart app/test/windows/window_fullscreen_shortcuts_test.dart`，訊息 `feat(keyboard): F11 視窗全螢幕與 Esc 退出（epic-66 Issue 7 Task 4）`。

---

### Task 5：`ReaderScreen` 按鍵處理器

**Files：**
- Modify: `app/lib/screens/reader_screen.dart`（`initState`／`dispose` 註冊與移除；新增 `_handleReaderKeyEvent`、`_handleReaderKeyCommand`、`_isReaderKeyInputBlocked`、`_isReaderCommandBlocked`）
- Test: `app/test/screens/reader_screen_keyboard_test.dart`（沿用 `reader_screen_test.dart`／`reader_screen_surface_test.dart` 既有的建構與假依賴方式，不要另起一套假物件）

**Interfaces：**
- Consumes: Task 2 的 `readerKeyCommandFor`、`ReaderKeyCommand`；既有 `_handleZoneAction(ZoneAction)`、`_surface.jumpTo(ReaderJumpTarget)`、`_surface.clearSelection()`、`_handleSelectionCleared()`、`_openBookSearch()`、`_openBookFlow.state`（`OpenBookRendered`）、`_cropEditModeActive`、`_annotations.selection`、`_clearSearchJumpHighlight()`、`_session.recordActivity()`、`_resolved?.writingMode == WritingMode.vertical`、`_pdfPageInfo?.totalPages`、`detectBookFormat(_activeFilePath)`。
- Produces（`_ReaderScreenState` 內部）：
  - `bool _handleReaderKeyEvent(KeyEvent event)`：只處理 `KeyDownEvent` 與 `KeyRepeatEvent`。先判斷 `_isReaderKeyInputBlocked()`，為真回傳 `false`。**Esc（無修飾鍵）：** `_cropEditModeActive` 為真 → 只吞掉（回傳 `true`，不退出裁切）；`_annotations.selection != null` → 沿用既有「清除選取」路徑（`_surface.clearSelection()` 加 `_handleSelectionCleared()`，以既有程式為準）並回傳 `true`；否則回傳 `false`（交給 `WindowFullscreenShortcuts`）。**其他按鍵：** 取 `HardwareKeyboard.instance` 的 shift／control／alt／meta 呼叫 `readerKeyCommandFor`；回傳 `null` 時回傳 `false`；否則呼叫 `_handleReaderKeyCommand` 並回傳 `true`。
  - `bool _isReaderKeyInputBlocked()`：路由不是最上層（`ModalRoute.of(context)?.isCurrent != true`）或文字輸入框有焦點（`FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null`）時為真。
  - `bool _isReaderCommandBlocked()`：`_openBookFlow.state is! OpenBookRendered || _cropEditModeActive`（載入中、探測中、失敗、重新連結、裁切模式）。
  - `void _handleReaderKeyCommand(ReaderKeyCommand command)`：先 `if (_isReaderCommandBlocked()) return;`；`previousPage`／`nextPage` 對應 `ZoneAction.previousPage`／`nextPage` 呼叫 `_handleZoneAction`；`firstPage`／`lastPage`：先 `_clearSearchJumpHighlight(); _session.recordActivity();`，Foliate 格式 `_surface.jumpTo(const ReaderJumpTarget(progression: 0.0))`／`1.0`，PDF 在 `_pdfPageInfo` 為 `null` 或 `totalPages <= 0` 時忽略，否則 `pdfPageIndex: 0`／`totalPages - 1`；`openSearch` 呼叫 `_openBookSearch()`。
  - 註冊：`initState` 在 `isWindowsPlatform` 時 `HardwareKeyboard.instance.addHandler(_handleReaderKeyEvent)`；`dispose` 無條件 `removeHandler`（對未註冊的處理器安全）。

- [ ] **Step 1：寫失敗測試**（Windows 平台 override；假 `ReaderSurface` 記錄 `previousPage`／`nextPage`／`jumpTo`／`clearSelection`；`tester.sendKeyEvent` 送鍵）：
  - `橫排：→ 呼叫 nextPage、← 呼叫 previousPage`；`直排：← 為下一頁、→ 為上一頁`。
  - `Space 為下一頁、Shift+Space 為上一頁、PageDown／PageUp／↓／↑ 照對應`。
  - `Home 呼叫 jumpTo(progression: 0.0)、End 為 1.0（EPUB）；PDF 為 pdfPageIndex 0 與最後一頁；PDF 頁數資訊尚未就緒時忽略`。
  - `Home／End 會清除搜尋跳轉高亮並記錄閱讀活動`（與 `_handleZoneAction` 一致）。
  - `Ctrl+F 開啟書內搜尋（push BookSearchScreen）`。
  - `按住不放（KeyRepeatEvent）持續翻頁、不丟例外`（Review Focus 1：用 `tester.sendKeyRepeatEvent`）。
  - `書籍載入中、載入失敗：翻頁、Home／End、Ctrl+F 都被忽略、不開搜尋頁、不崩潰`；`PDF 手動裁切模式：同樣被忽略`（Review Focus 3）。
  - `路由被疊上（showDialog）時按 →：不翻頁`；`文字輸入框有焦點時按 →、Space、Home：不翻頁`。
  - `Alt+←、Ctrl+→：不翻頁`。
  - `Esc：有文字選取時清除選取並消費；PDF 裁切模式時被吞掉且裁切模式維持；兩者皆無時不消費（回傳 false）`（Review Focus 6）。
  - `離開閱讀器（pop）後按 →：surface 沒有被呼叫；再開一次書後按 → 只翻一頁（不是兩頁）`（Review Focus 4）。
  - `非 Windows 平台：按 →、Esc 都不處理`。
- [ ] **Step 2：執行確認失敗：** `flutter test test/screens/reader_screen_keyboard_test.dart`；預期失敗（按鍵沒有任何動作）。
- [ ] **Step 3：實作** 上述成員與註冊／移除，並加中文註解說明「全域處理器先於焦點樹、因此不需修改 PDF 的 `_onPagedKey`」，以及 Esc 與 TTS 面板刻意不處理的原因。若 PDF 正常開書後 `_openBookFlow.state` 不是 `OpenBookRendered`，不要放寬條件，先查清楚原因並記 `Ruling`。
- [ ] **Step 4：執行確認通過：** 同 Step 2 指令；再跑 `flutter test test/screens/reader_screen_test.dart test/screens/reader_screen_surface_test.dart test/screens/reader_screen_route_test.dart` 確認既有測試沒壞。
- [ ] **Step 5：Commit：** `git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_keyboard_test.dart`，訊息 `feat(keyboard): ReaderScreen 在 Windows 處理翻頁、搜尋與 Esc（epic-66 Issue 7 Task 5）`。

---

### Task 6：EPUB 的按鍵交付（依 Task 1 結論二選一）

**請先讀 `issue-7-report.md` 的「實測結論」。結論為方案 A 就只做 A 小節，方案 B 就只做 B 小節；選了哪個，在 commit 訊息中寫明。**

#### 方案 A（Flutter 全域處理器就夠）

**Files：**
- Test: `app/test/reader/foliate_reader_view_keyboard_test.dart`

- [ ] **Step A1：寫測試**：`FoliateReaderView` 掛載（沿用 `foliate_reader_view_test.dart` 的假 WebView 測試方式）且 Windows 平台 override 時，`tester.sendKeyEvent` 送出的 →、F11 仍被全域處理器（Task 5、Task 4）收到；`FoliateReaderView` 本身不攔截這些鍵。此測試鎖定「不需要 JS 轉送」的假設。
- [ ] **Step A2：執行：** `flutter test test/reader/foliate_reader_view_keyboard_test.dart`；若一開始就通過，在 `issue-7-report.md` 註明「方案 A，Task 6 只補回歸測試」。
- [ ] **Step A3：Commit：** `git add app/test/reader/foliate_reader_view_keyboard_test.dart docs/epics/epic-66-windows-port/issue-7-report.md`，訊息 `test(keyboard): EPUB 按鍵由全域處理器接收的回歸測試（方案 A，epic-66 Issue 7 Task 6）`。

#### 方案 B（`main.js` 轉送，含去重）

**Files：**
- Create: `app/lib/reader/desktop_key_deduper.dart`
- Modify: `app/android/app/src/main/assets/foliate/main.js`（新增 `keydown` 轉送，僅在 query 參數 `desktopKeys=1` 時啟用）
- Modify: `app/lib/reader/foliate_reader_view.dart`（`buildFoliateReaderIndexUri` 在 Windows 加 `desktopKeys=1`；新增 JS handler 與選用回呼 `onDesktopKey`）
- Modify: `app/lib/reader/foliate_bridge_handlers.dart`（新增 handler 名稱 `onDesktopKey`）
- Modify: `app/lib/screens/reader_screen.dart`（把 `onDesktopKey` 接到命令處理；Task 5 的 `HardwareKeyboard` 處理器也經同一個去重器）
- Modify: `app/lib/windows/window_fullscreen_shortcuts.dart`（F11 的 `HardwareKeyboard` 處理器也經同一個去重器）
- Test: `app/test/reader/foliate_reader_view_keyboard_test.dart`、`app/test/reader/desktop_key_deduper_test.dart`

**Interfaces：**
- Produces:
  - `enum DesktopKeySource { flutter, web }`；`class DesktopKeyDeduper { DesktopKeyDeduper({int Function()? nowMs}); bool shouldHandle(String keyId, DesktopKeySource source); }`：同一個 `keyId` 若在 50 毫秒內已由**另一個** `source` 處理過就回傳 `false`；同一 `source` 的連續呼叫（按住不放）永遠回傳 `true`；回傳 `true` 時記錄 `(keyId, source, 時間)`。另提供頂層 `final DesktopKeyDeduper desktopKeyDeduper = DesktopKeyDeduper();` 供三個處理點共用。`keyId` 一律用 `LogicalKeyboardKey.keyLabel` 的標準化小寫字串或 `logicalKeyId` 字串，Flutter 與 web 兩邊必須用同一個轉換函式。
  - `FoliateBridgeHandlers.onDesktopKey`（字串常數，值 `'onDesktopKey'`）。
  - `LogicalKeyboardKey? logicalKeyForWebKey(String key)`（純函式，`foliate_reader_view.dart` 內或獨立檔案）：`'ArrowLeft'`、`'ArrowRight'`、`'ArrowUp'`、`'ArrowDown'`、`'PageUp'`、`'PageDown'`、`' '`、`'Home'`、`'End'`、`'F11'`、`'Escape'`，以及 **`'f'` 與 `'F'` 兩者**（CapsLock 開啟時 `Ctrl+F` 的 `e.key` 是 `'F'`）都要對應；其他回傳 `null`。
  - `FoliateReaderView` 新增選用參數 `final void Function(String key, {required bool shift, required bool control, required bool alt, required bool meta})? onDesktopKey`。
  - `main.js`：`desktopKeys=1` 時對 `window` 與每個 section 文件（foliate 的 `load` 事件給的 `doc`）掛 `keydown`（capture），對上述鍵（`f` 以 `e.key.toLowerCase() === 'f'` 比對，且只在 `e.ctrlKey`）呼叫 `window.flutter_inappwebview.callHandler('onDesktopKey', {key, shiftKey, ctrlKey, altKey, metaKey})`，並對這些鍵 `preventDefault()`；其他鍵不處理。未帶 `desktopKeys=1`（Android）完全不掛。
  - `ReaderScreen` 收到 `onDesktopKey`：先 `desktopKeyDeduper.shouldHandle(...)`；F11 呼叫 `toggleWindowFullscreen(activeWindowFullscreenController!)`；Escape 先走 Task 5 的 Esc 邏輯（裁切模式吞掉、選取清除），都沒有消費才 `exitWindowFullscreenIfActive`；其餘以 `readerKeyCommandFor` 轉成命令並經 `_isReaderKeyInputBlocked` 檢查後呼叫 `_handleReaderKeyCommand`。

- [ ] **Step B1：寫失敗測試：** (a) `DesktopKeyDeduper`（注入假時鐘）：同一鍵不同來源 50 毫秒內第二次被擋、超過 50 毫秒放行、同一來源連續（按住不放）不擋、不同鍵互不影響；(b) `buildFoliateReaderIndexUri` 在 Windows 帶 `desktopKeys=1`、非 Windows 不帶；(c) `onDesktopKey` handler 收到參數後回呼 `FoliateReaderView.onDesktopKey`；(d) `ReaderScreen` 收到 `onDesktopKey('ArrowRight', …)` 呼叫 `nextPage`、收到 F11 呼叫假控制器 `setFullscreen`、收到 Escape 且為全螢幕時退出、收到 Escape 且有文字選取時只清除選取；(e) 修飾鍵（`alt: true` 的 ArrowLeft）不翻頁；(f) 同一鍵先由 Flutter 全域處理器處理，50 毫秒內又收到 `onDesktopKey`：只翻一頁、F11 只切換一次；(g) `logicalKeyForWebKey`：`'f'`、`'F'` 都回傳 `keyF`，未知鍵回傳 `null`。
- [ ] **Step B2：執行確認失敗：** `flutter test test/reader/foliate_reader_view_keyboard_test.dart test/reader/desktop_key_deduper_test.dart`。
- [ ] **Step B3：實作** 上述成員。`main.js` 的改動必須是純新增、以 `desktopKeys` 閘門，不得改動既有程式路徑；改完跑 `node tool/check_foliate_es_compat.js`。
- [ ] **Step B4：執行確認通過：** 同 Step B2 指令，再跑 `flutter test test/reader/foliate_reader_view_test.dart test/windows/window_fullscreen_shortcuts_test.dart test/screens/reader_screen_keyboard_test.dart` 確認既有與前面 Task 的測試沒壞。
- [ ] **Step B5：Commit：** `git add` 上述檔案，訊息 `feat(keyboard): foliate-js 轉送按鍵給 Dart 並去重（方案 B，epic-66 Issue 7 Task 6）`。

---

### Task 7：`BookSearchScreen` 開啟即聚焦與 Ctrl+F

**Files：**
- Modify: `app/lib/screens/book_search_screen.dart`（`initState`／`dispose` 註冊與移除全域按鍵處理器；Windows 開啟即聚焦）
- Test: `app/test/screens/book_search_screen_test.dart`（既有檔案，新增測試）

**Interfaces：**
- Consumes: 既有 `_searchFocusNode`、`_controller`（`TextEditingController`），輸入框 `Key('book_search_screen_field')`（目前 `autofocus: false`）。
- Produces（`_BookSearchScreenState` 內部）：
  - Windows 時 `initState` 以 `WidgetsBinding.instance.addPostFrameCallback` 呼叫 `_searchFocusNode.requestFocus()`（開啟即聚焦，決定 10）；非 Windows 不動，維持 `autofocus: false`。
  - Windows 時 `initState` 註冊 `HardwareKeyboard.instance.addHandler(_handleSearchKeyEvent)`、`dispose` 移除：`KeyDownEvent` 的 Ctrl+F（無 shift／alt／meta）且 `ModalRoute.of(context)?.isCurrent == true` 時，`_searchFocusNode.requestFocus()`，並在 `_controller.text` 非空時把 `selection` 設為全選（`TextSelection(baseOffset: 0, extentOffset: _controller.text.length)`），回傳 `true`；其他回傳 `false`。**不要用 `CallbackShortcuts`**：搜尋畫面沒有焦點節點在其子樹時它收不到事件。

- [ ] **Step 1：寫失敗測試**（沿用該畫面既有測試的建構方式）：Windows 平台 override 下：(a) 開啟後下一幀輸入框已取得焦點；(b) 焦點被移走後送出 Ctrl+F，輸入框重新取得焦點；(c) 輸入框已有文字時送出 Ctrl+F，文字被全選；(d) Ctrl+Shift+F、單獨 F 不處理；(e) 有對話框疊在搜尋畫面上時 Ctrl+F 不處理；(f) 畫面關閉後處理器已移除（再送 Ctrl+F 不丟例外）。預設平台（Android）下：開啟後輸入框**沒有**焦點，Ctrl+F 不處理。
- [ ] **Step 2：執行確認失敗：** `flutter test test/screens/book_search_screen_test.dart`。
- [ ] **Step 3：實作** 如上，並加中文註解說明為何用全域處理器而非 `CallbackShortcuts`。
- [ ] **Step 4：執行確認通過：** 同 Step 2 指令。
- [ ] **Step 5：Commit：** `git add app/lib/screens/book_search_screen.dart app/test/screens/book_search_screen_test.dart`，訊息 `feat(keyboard): 搜尋畫面開啟即聚焦與 Ctrl+F（epic-66 Issue 7 Task 7）`。

---

### Task 8：收尾——文件、全套測試、人工驗證清單

**Files：**
- Modify: `docs/epics/epic-66-windows-port/issue-7-report.md`（補完整報告）
- Modify: `docs/epics/epic-66-windows-port/issues.md`（Issue 7 狀態改為「🟡 實作完成，待 Windows 人工驗證」）
- 視需要 Modify: `CONTEXT.md`（若實作中發現詞條描述與實況不符）

- [ ] **Step 1：補報告。** 在 `issue-7-report.md` 加：做了什麼（含採用方案 A 或 B）、自動化測試結果、`issues.md` 過關條件 2 到 8 的**人工驗證表**，每項結果欄先留「待驗證」，**不得預先勾選**，明確標示「尚未在 Windows 實機驗證」；以及已知限制（不可關閉的對話框開著時 Esc 會退出全螢幕；TTS 面板不響應 Esc）。
- [ ] **Step 2：全套測試：** `flutter test`（`run_in_background`），預期 `All tests passed!`；記錄測試總數與 commit。
- [ ] **Step 3：靜態檢查：** `flutter analyze`（`No issues found!`）、`node tool/check_integration_keys.js`（PASS）；若動到 `main.js`（方案 B）再跑 `node tool/check_foliate_es_compat.js`（PASS）。
- [ ] **Step 4：確認依賴衛生：** `git diff origin/main -- app/pubspec.lock` 只含 `window_manager` 與 `screen_retriever` 系列；`git status` 不含無關的 `windows/flutter` 換行異動。
- [ ] **Step 5：Commit：** `git add docs/epics/epic-66-windows-port/issue-7-report.md docs/epics/epic-66-windows-port/issues.md`（若改了 `CONTEXT.md` 一併加入），訊息 `docs(epic-66): Issue 7 收尾文件與人工驗證清單`。推送與開 PR 前先請使用者確認，並請使用者在 Windows 實機（完整重建後）完成人工驗證表。
