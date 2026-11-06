# Epic 66 Issue 7 實測報告：Windows 鍵盤快捷鍵與全螢幕

## 實測結論（Task 1）

### 1. 測試環境與方法

- **作業系統**：Windows 11
- **應用程式環境**：`flutter run -d windows`（Debug mode，WebView2 260 字元路徑問題已透過 `W:\` worktree 映射解決）
- **書檔**：`test/fixtures/sample.epub`
- **測試方式**：
  - 由探針腳本透過 Win32 `AttachThreadInput` 附加至 elinkbook 主執行緒輸入佇列。
  - **階段 1（焦點在書頁）**：以長點擊（800ms，避開 TapZoneDetector 翻頁並確保 Win32 焦點進入 WebView2），此時前景視窗焦點落在 `CustomPlatformView` 底下的 `Chrome_WidgetWin_0`（WebView2 子視窗）。
  - **階段 2（焦點在 Flutter）**：將焦點設定在 `FLUTTER_RUNNER_WIN32_WINDOW` 底下的 `FLUTTERVIEW` 視窗。
  - 對 12 個目標按鍵分別以 Win32 鍵盤事件送鍵，觀察 `[keyprobe flutter]`（`HardwareKeyboard.instance.addHandler`）與 `[keyprobe web]`（`window.addEventListener('keydown')`）的接收紀錄。

---

### 2. 實測數據記錄表

| 按鍵名稱 | 鍵碼 / 組合 | 階段 1：焦點在書頁（WebView2） | 階段 2：焦點在 Flutter（FLUTTERVIEW） | 兩邊都收到？ | 備註 |
|---|---|---|---|:---:|---|
| **ArrowLeft (←)** | VK_LEFT (0x25) | `[keyprobe web]` 收到；Flutter **沒收到** | `[keyprobe flutter]` 收到 | 否 | 書頁焦點時被 WebView2 獨佔 |
| **ArrowRight (→)** | VK_RIGHT (0x27) | `[keyprobe web]` 收到；Flutter **沒收到** | `[keyprobe flutter]` 收到 | 否 | 書頁焦點時被 WebView2 獨佔 |
| **ArrowUp (↑)** | VK_UP (0x26) | `[keyprobe web]` 收到；Flutter **沒收到** | `[keyprobe flutter]` 收到 | 否 | 書頁焦點時被 WebView2 獨佔 |
| **ArrowDown (↓)** | VK_DOWN (0x28) | `[keyprobe web]` 收到；Flutter **沒收到** | `[keyprobe flutter]` 收到 | 否 | 書頁焦點時被 WebView2 獨佔 |
| **PageUp** | VK_PRIOR (0x21) | `[keyprobe web]` 收到；Flutter **沒收到** | `[keyprobe flutter]` 收到 | 否 | 書頁焦點時被 WebView2 獨佔 |
| **PageDown** | VK_NEXT (0x22) | `[keyprobe web]` 收到；Flutter **沒收到** | `[keyprobe flutter]` 收到 | 否 | 書頁焦點時被 WebView2 獨佔 |
| **Space** | VK_SPACE (0x20) | `[keyprobe web]` 收到；Flutter **沒收到** | `[keyprobe flutter]` 收到 | 否 | 書頁焦點時被 WebView2 獨佔 |
| **Home** | VK_HOME (0x24) | `[keyprobe web]` 收到；Flutter **沒收到** | `[keyprobe flutter]` 收到 | 否 | 書頁焦點時被 WebView2 獨佔 |
| **End** | VK_END (0x23) | `[keyprobe web]` 收到；Flutter **沒收到** | `[keyprobe flutter]` 收到 | 否 | 書頁焦點時被 WebView2 獨佔 |
| **Ctrl+F** | Ctrl + VK_F (0x46) | `[keyprobe web]` 收到；Flutter **沒收到** | `[keyprobe flutter]` 收到 | 否 | 書頁焦點時被 WebView2 獨佔 |
| **F11** | VK_F11 (0x7A) | 兩邊皆未收到 | `[keyprobe flutter]` 收到 | 否 | 兩邊都沒收到（「被 WebView2 攔截」是**推論**，見 2.1 量測限制） |
| **Escape** | VK_ESCAPE (0x1B) | 兩邊皆未收到 | `[keyprobe flutter]` 收到 | 否 | 兩邊都沒收到（「被 WebView2 攔截」是**推論**，見 2.1 量測限制） |

---

### 2.1 量測限制與可信度（程式審查 I-4）

以下限制使 F11／Esc 的結果只是**「這次量測沒收到」，不是「WebView2 一定攔截」**：

1. **送鍵方式是合成輸入**：以 Win32 `AttachThreadInput` 附加後送鍵，不是真實鍵盤，可能影響 F11／Esc 的觀察。
2. **探針只掛頂層 `window`**：沒有掛在 section iframe 的文件。實際閱讀時焦點通常在 iframe 內，而 `main.js` 實作是對 `window` 與每個 section 文件都掛轉送，這個差異沒有被量測。
3. **沒有可追溯的原始資料**：探針腳本沒有保留，本報告也沒有原始 log 摘錄，無法重現。
4. 「被 WebView2 內部攔截但未冒泡至 JS」是對「兩邊都沒收到」的**推論**。
5. 方向鍵、Space、Home、End、Ctrl+F「只進 web、Flutter 沒收到」的結果，與方案 B 的判定一致，可信度較高；但同樣是合成輸入。

因此上表 F11／Esc「兩邊皆未收到」不能當結論。**後續實機驗證（2026-11-06）：** 使用者以真實鍵盤在 Windows 實機驗證，書頁有焦點時 F11／Esc 皆可用。未保留按鍵進入哪一邊的 log。

### 3. 判定結論與架構決策

- **判定結果**：依據 `plan-issue-7.md` Step 3 判定規則，所有閱讀器翻頁按鍵與 `Ctrl+F` 在焦點位於書頁時，**只出現在 `[keyprobe web]`，Flutter 完全收不到**。因此**明確判定為方案 B**。
- **F11／Esc 的缺口**：方案 B 的判定只依據方向鍵等翻頁鍵；F11 與 Esc 在書頁有焦點時是否可用未解決（見 2.1 與已知邊界）。
- **架構影響**：
  1. Task 6 必須執行**方案 B**（包含 `desktop_key_deduper.dart`、`main.js` `desktopKeys=1` 轉送 `onDesktopKey`、`foliate_reader_view.dart` 支援 `logicalKeyForWebKey` 處理 `'f'` 與 `'F'`、`ReaderScreen` 與 `WindowFullscreenShortcuts` 接線）。
  2. 方案 A 的 Step A1–A3 略過不執行。

---

## 實作內容（方案 B 完整架構）

### 1. 架構元件與資料流

1. **純邏輯按鍵命令解析器（`reader_key_command.dart`）**：
   - 負責將鍵盤事件（`LogicalKeyboardKey` 與修飾鍵旗標）對應為內部命令 `ReaderKeyCommand`（`previousPage`、`nextPage`、`firstPage`、`lastPage`、`openSearch`）。
   - 直排模式下（`verticalWriting == true`）將左右箭頭鍵鏡像（← 為下一頁、→ 為上一頁）；橫排與 PDF 模式則 ← 為上一頁、→ 為下一頁。
   - 包含 Space（下一頁）、Shift+Space（上一頁）、PageUp/PageDown、Home/End、Ctrl+F。
   - 嚴格修飾鍵白名單：除了 Shift+Space 與 Ctrl+F 以外，任何帶 Ctrl／Alt／Meta 修飾鍵之按鍵均回傳 `null`（不誤觸翻頁）。

2. **視窗全螢幕控制器與快捷鍵（`window_fullscreen_controller.dart`、`window_fullscreen_shortcuts.dart`）**：
   - 引入 `window_manager: 0.5.2`（固定版號），實作 `WindowFullscreenController` 介面，維護同步可讀的 `isFullscreenNow` 快取。
   - 在 `MaterialApp.builder` 掛載 `WindowFullscreenShortcuts`：
     - **F11**：透過全域 `HardwareKeyboard` 監聽，觸發 `toggleWindowFullscreen`；內建防重入旗標與去重保護。
     - **Esc**：由單一決策點 `handleWindowEscape` 處理（全域 `HardwareKeyboard` 處理器；WebView 轉送的 Esc 也共用）。優先序：焦點處可關閉的浮層（路由 `barrierDismissible` 或 `DismissAction` 子類）→ 註冊式內層 Esc 消費者（閱讀器的文字選取與 PDF 裁切模式，只在閱讀器是最上層時參與）→ 視窗全螢幕時退出 → 否則不消費。**沒有**用 `MaterialApp.builder` 層的 `Actions` 覆寫 `DismissIntent`：每個路由自帶的 `DismissIntent` 動作會遮蔽它（見計畫 Ruling 1）。

3. **閱讀器快捷鍵監聽（`reader_screen.dart`）**：
   - Windows 平台專屬全域 `HardwareKeyboard` 監聽器，早於焦點樹消費事件（PDF pdfrx 焦點問題解套）。
   - 阻斷檢查：頂層路由覆蓋或文字輸入框具焦點時暫停；未載入完成或 PDF 裁切模式時忽略翻頁命令。
   - Home／End 比照熱區翻頁清除搜尋跳轉高亮並記錄閱讀活動。
   - **Esc**：閱讀器只透過 `registerEscInnerConsumer(_consumeEscForReader)` 參與，不在自己的按鍵處理器內處理 Esc（見計畫 Ruling 2）。消費者只在閱讀器是最上層路由時才動作：
     1. PDF 手動裁切模式：只吞掉 Esc，裁切模式維持，不退出全螢幕。
     2. 有文字選取：關閉選取工具列並清除選取，全螢幕維持。
     3. 其他：不消費，由決策點退出視窗全螢幕（若處於全螢幕）；非全螢幕時不消費，亦不退回書架。閱讀器被搜尋畫面等頁面蓋住時消費者不參與，Esc 直接退出全螢幕。

4. **Foliate WebView 鍵盤事件轉送與雙重交付去重（`desktop_key_deduper.dart`、`main.js`、`foliate_reader_view.dart`）**：
   - Foliate 索引頁在 Windows 帶 `desktopKeys=1`，`main.js` 於捕獲階段（capture）攔截翻頁、跳頁、搜尋、F11、Esc 並透過 `onDesktopKey` handler 轉送至 Dart 端。
   - 支援大小寫 `'f'` 與 `'F'`（CapsLock 開啟情境）。
   - 全域 `DesktopKeyDeduper`（使用 `package:clock` 量測，防範真實時鐘漂移）：同鍵不同來源（Flutter vs Web）於 50ms 內第二次送達時自動過濾（去重），同一來源長按連發（key repeat）則永遠放行。

5. **單書搜尋畫面焦點與快捷鍵（`book_search_screen.dart`）**：
   - Windows 平台在 `initState` 透過 `addPostFrameCallback` 自動聚焦於搜尋框（Android 維持不自動聚焦避免彈出軟鍵盤）。
   - Windows 下全域 `HardwareKeyboard` 監聽 Ctrl+F：重新聚焦輸入框並將既有搜尋文字全選。

---

## 自動化測試結果

| 測試檔案 | 測試數量 | 狀態 | 覆蓋重點 |
|---|:---:|:---:|---|
| `test/reader/reader_key_command_test.dart` | 11 | ✅ 通過 | 橫排/直排翻頁映射、修飾鍵阻斷、Space/Shift+Space、Home/End、Ctrl+F |
| `test/windows/window_fullscreen_controller_test.dart` | 6 | ✅ 通過 | 假控制器、同步快取、toggle 狀態切換、防重入、例外捕獲、exitWindowFullscreenIfActive |
| `test/windows/window_fullscreen_shortcuts_test.dart` | 12 | ✅ 通過 | F11 切換、Esc 單一決策點（可關閉浮層優先、內層消費者、輸入框有焦點的頁面仍退出全螢幕）、`handleWindowEscape`、修飾鍵阻斷、非 Windows 不動作 |
| `test/screens/reader_screen_keyboard_test.dart` | 15 | ✅ 通過 | 橫排/直排翻頁、Home/End、Ctrl+F、連按 KeyRepeatEvent、輸入框焦點阻斷、裁切/未就緒阻斷、全螢幕掛載真實整合 Esc 優先序、閱讀器被搜尋畫面蓋住時 Esc 退出全螢幕 |
| `test/reader/desktop_key_deduper_test.dart` | 7 | ✅ 通過 | 跨來源 50ms 去重、同來源連發放行、按鍵映射、f/F CapsLock 支援 |
| `test/reader/foliate_reader_view_keyboard_test.dart` | 6 | ✅ 通過 | Windows 帶 desktopKeys=1、main.js 靜態驗證、onDesktopKey 回呼翻頁/F11/Esc、雙重交付 50ms 去重 |
| `test/screens/book_search_screen_test.dart` (新增部分) | 7 | ✅ 通過 | Windows 開啟自動聚焦、Android 不自動聚焦、Ctrl+F 重新聚焦全選、修飾鍵與對話框阻斷、pop 移除處理器 |

- **全套 `flutter test`**（`app/` 下、`--no-pub`）：**5074 通過、2 跳過、0 失敗**，結束碼 0，跑在審查修復（I-1～I-4）完成後、commit 前的工作樹。上表各檔案的測試數是單獨執行該檔案的實際結果（`book_search_screen_test.dart` 含既有 18 個加新增 7 個）。
- **靜態分析**：`flutter analyze` 0 warning 0 error。
- **WebView 相容性**：`node tool/check_foliate_es_compat.js` 100% 通過。
- **依賴衛生**：`pubspec.lock` 僅異動 `window_manager: 0.5.2` 與 `screen_retriever` 系列。

---

## 人工驗證表（Windows 實機，2026-11-06）

> [!NOTE]
> 下列各列結果來自使用者的整體口頭回報（「步驟 1、2、3 皆通過」），未逐項留下操作細節或 log。

| 條件編號 | 驗證項目 | 測試情境與步驟 | 驗證結果 | 備註 |
|:---:|---|---|:---:|---|
| **條件 2** | 翻頁（EPUB 橫排） | 開啟橫排 EPUB，書頁有焦點（WebView2）：<br>1. 按 `→`／`↓`／`PageDown`／`Space` 翻下一頁。<br>2. 按 `←`／`↑`／`PageUp`／`Shift+Space` 翻上一頁。<br>3. 按 `Home` 回第一頁、按 `End` 跳到最後一頁。<br>4. 長按翻頁鍵，確認能連續翻頁。 | 通過 | 使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節） |
| **條件 3** | 翻頁（EPUB 直排） | 開啟直排繁體中文 EPUB：<br>1. 按 `←` 確認翻下一頁（直排向左前進）。<br>2. 按 `→` 確認翻上一頁。<br>3. 其餘按鍵（↑／↓／Space／Home／End）方向與橫排一致。 | 通過 | 使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節） |
| **條件 4** | 翻頁（PDF） | 開啟多頁 PDF 文件（分別於單頁分頁模式與連續捲動模式）：<br>1. 按翻頁鍵與 Home/End 確認翻頁與跳頁正確。<br>2. 方向鍵不鏡像。 | 通過 | 使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節） |
| **條件 5** | 暫停阻斷條件 | 1. 於閱讀器內開啟備註輸入框或搜尋框，輸入框具焦點時按翻頁鍵，確認不觸發翻頁。<br>2. 開啟目錄（TOC）或設定面板時，按翻頁鍵確認不觸發底層翻頁。 | 通過 | 使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節） |
| **條件 6** | 書內搜尋與 Ctrl+F | 1. 於閱讀器內按 `Ctrl+F`，確認開啟單書搜尋畫面。<br>2. 搜尋畫面載入後，確認游標直接在輸入框內可立即鍵入關鍵字。<br>3. 點選其他區域使輸入框失焦後，再按 `Ctrl+F`，確認游標重回輸入框並全選文字。<br>4. 在書架畫面按 `Ctrl+F` 確認無反應。 | 通過 | 使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節） |
| **條件 7** | F11 視窗全螢幕 | 1. 在書架、設定、閱讀器、搜尋各畫面按 `F11`，確認視窗切換為全螢幕。<br>2. **（最優先，必須用真實鍵盤）** 先點一下書頁讓 WebView2 取得焦點（分別試焦點在書頁文字內與空白處），再按 `F11` 確認能否切換，並同樣測 `Esc`；記錄實際結果，不可沿用 Task 1 的合成輸入結論。<br>3. 全螢幕狀態下切換畫面或退出閱讀器回到書架，確認全螢幕維持。<br>4. 連按 `F11` 確認畫面不閃爍、不崩潰。<br>5. 重啟 App 確認恢復為一般視窗（不持久化）。 | 通過 | 使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節） |
| **條件 8** | Esc 鍵層級處理 | 1. 視窗全螢幕下，開啟對話框按 `Esc`：對話框關閉，視窗全螢幕維持。<br>2. 視窗全螢幕下，劃線選取文字彈出工具列時按 `Esc`：工具列關閉選取清除，視窗全螢幕維持。<br>3. 視窗全螢幕下，PDF 處於手動裁切模式按 `Esc`：維持裁切模式與全螢幕（按鍵被吞掉）。<br>4. 視窗全螢幕下無任何浮層按 `Esc`：退出視窗全螢幕。<br>5. 非全螢幕下按 `Esc`：確認閱讀器不會退出回到書架。 | 通過 | 使用者於 2026-11-06 在 Windows 實機以真實鍵盤回報通過（未逐項留下細節） |

---

## 已知邊界與限制

1. **EPUB 書頁（WebView2）有焦點時 F11／Esc：已由實機驗證可用（2026-11-06，使用者回報）。** 先前的風險來自 Task 1 的合成輸入量測（見 2.1），已被真實鍵盤結果取代。限制：未保留 log，不知道按鍵走 `main.js` 轉送還是直接進 Flutter；`flutter_inappwebview_windows` 0.6.0 仍沒有暴露 `AreBrowserAcceleratorKeysEnabled`。
2. **疊在閱讀器上的頁面不算浮層：** 全螢幕下在搜尋畫面等頁面按 Esc，會直接退出視窗全螢幕（輸入框有焦點的頁面也一樣）。
3. **不可關閉的對話框（`barrierDismissible: false`）：** 按 Esc 會退出視窗全螢幕（對話框的 `DismissIntent` 動作未啟用，且閱讀器不是最上層而不參與）。
4. **TTS 朗讀面板：** `_cbzTtsPanelVisible`／`_ttsPanelCollapsed` 是展開收合狀態而非浮層，「Esc 關閉」語意不明，刻意不響應 Esc。
5. **滑鼠滾輪與其他功能快捷鍵：** 本 Issue 依 GRILL 決策專注於翻頁、跳頁、搜尋與視窗全螢幕，目錄、字級調整及滑鼠滾輪翻頁不在範圍內。
