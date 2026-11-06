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
| **F11** | VK_F11 (0x7A) | 兩邊皆未收到 | `[keyprobe flutter]` 收到 | 否 | 書頁焦點時被 WebView2 內部攔截但未冒泡至 JS |
| **Escape** | VK_ESCAPE (0x1B) | 兩邊皆未收到 | `[keyprobe flutter]` 收到 | 否 | 書頁焦點時被 WebView2 內部攔截但未冒泡至 JS |

---

### 3. 判定結論與架構決策

- **判定結果**：依據 `plan-issue-7.md` Step 3 判定規則，所有閱讀器翻頁按鍵與 `Ctrl+F` 在焦點位於書頁時，**只出現在 `[keyprobe web]`，Flutter 完全收不到**。因此**明確判定為方案 B**。
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
     - **Esc 協作機制**：提供 `WindowFullscreenShortcuts.activeEscOverrideCount` 接管計數器。當閱讀器存在時無條件放行給 `ReaderScreen` 自行處置；非閱讀器畫面下，檢查焦點樹上是否有已啟用的浮層（如對話框），對話框優先關閉且全螢幕維持，無浮層且處於全螢幕時才退出全螢幕。

3. **閱讀器快捷鍵監聽（`reader_screen.dart`）**：
   - Windows 平台專屬全域 `HardwareKeyboard` 監聽器，早於焦點樹消費事件（PDF pdfrx 焦點問題解套）。
   - 阻斷檢查：頂層路由覆蓋或文字輸入框具焦點時暫停；未載入完成或 PDF 裁切模式時忽略翻頁命令。
   - Home／End 比照熱區翻頁清除搜尋跳轉高亮並記錄閱讀活動。
   - **Esc 優先序完整處置（過關條件 8）**：
     1. PDF 手動裁切模式：吞掉 Esc（維持裁切，全螢幕維持）。
     2. 文字選取存在：關閉選取工具列並清除選取（全螢幕維持）。
     3. 兩者皆無且處於視窗全螢幕：呼叫 `exitWindowFullscreenIfActive` 退出全螢幕。
     4. 非全螢幕且無選取/裁切：不消費按鍵，亦不退回書架。

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
| `test/windows/window_fullscreen_shortcuts_test.dart` | 8 | ✅ 通過 | F11 切換全螢幕、Esc 關對話框優先於全螢幕、非全螢幕放行、修飾鍵阻斷、非 Windows 平台不動作 |
| `test/screens/reader_screen_keyboard_test.dart` | 14 | ✅ 通過 | 橫排/直排翻頁、Home/End、Ctrl+F、連按 KeyRepeatEvent、輸入框焦點阻斷、裁切/未就緒阻斷、全螢幕掛載真實整合 Esc 優先序 |
| `test/reader/desktop_key_deduper_test.dart` | 7 | ✅ 通過 | 跨來源 50ms 去重、同來源連發放行、按鍵映射、f/F CapsLock 支援 |
| `test/reader/foliate_reader_view_keyboard_test.dart` | 6 | ✅ 通過 | Windows 帶 desktopKeys=1、main.js 靜態驗證、onDesktopKey 回呼翻頁/F11/Esc、雙重交付 50ms 去重 |
| `test/screens/book_search_screen_test.dart` (新增部分) | 7 | ✅ 通過 | Windows 開啟自動聚焦、Android 不自動聚焦、Ctrl+F 重新聚焦全選、修飾鍵與對話框阻斷、pop 移除處理器 |

- **總測試通過數**：全套既有與新增測試共 5,000+ 項測試通過（見 Task 8 完整跑表）。
- **靜態分析**：`flutter analyze` 0 warning 0 error。
- **WebView 相容性**：`node tool/check_foliate_es_compat.js` 100% 通過。
- **依賴衛生**：`pubspec.lock` 僅異動 `window_manager: 0.5.2` 與 `screen_retriever` 系列。

---

## 人工驗證表（待 Windows 實機人工驗證）

> [!IMPORTANT]
> **依據 Issue 7 過關條件 11，下列人工驗證項目尚未在 Windows 實機執行。未經實機人工測試前不得預先勾選為通過。**

| 條件編號 | 驗證項目 | 測試情境與步驟 | 驗證結果 | 備註 |
|:---:|---|---|:---:|---|
| **條件 2** | 翻頁（EPUB 橫排） | 開啟橫排 EPUB，書頁有焦點（WebView2）：<br>1. 按 `→`／`↓`／`PageDown`／`Space` 翻下一頁。<br>2. 按 `←`／`↑`／`PageUp`／`Shift+Space` 翻上一頁。<br>3. 按 `Home` 回第一頁、按 `End` 跳到最後一頁。<br>4. 長按翻頁鍵，確認能連續翻頁。 | 待驗證 | 尚未在 Windows 實機驗證 |
| **條件 3** | 翻頁（EPUB 直排） | 開啟直排繁體中文 EPUB：<br>1. 按 `←` 確認翻下一頁（直排向左前進）。<br>2. 按 `→` 確認翻上一頁。<br>3. 其餘按鍵（↑／↓／Space／Home／End）方向與橫排一致。 | 待驗證 | 尚未在 Windows 實機驗證 |
| **條件 4** | 翻頁（PDF） | 開啟多頁 PDF 文件（分別於單頁分頁模式與連續捲動模式）：<br>1. 按翻頁鍵與 Home/End 確認翻頁與跳頁正確。<br>2. 方向鍵不鏡像。 | 待驗證 | 尚未在 Windows 實機驗證 |
| **條件 5** | 暫停阻斷條件 | 1. 於閱讀器內開啟備註輸入框或搜尋框，輸入框具焦點時按翻頁鍵，確認不觸發翻頁。<br>2. 開啟目錄（TOC）或設定面板時，按翻頁鍵確認不觸發底層翻頁。 | 待驗證 | 尚未在 Windows 實機驗證 |
| **條件 6** | 書內搜尋與 Ctrl+F | 1. 於閱讀器內按 `Ctrl+F`，確認開啟單書搜尋畫面。<br>2. 搜尋畫面載入後，確認游標直接在輸入框內可立即鍵入關鍵字。<br>3. 點選其他區域使輸入框失焦後，再按 `Ctrl+F`，確認游標重回輸入框並全選文字。<br>4. 在書架畫面按 `Ctrl+F` 確認無反應。 | 待驗證 | 尚未在 Windows 實機驗證 |
| **條件 7** | F11 視窗全螢幕 | 1. 在書架、設定、閱讀器、搜尋各畫面按 `F11`，確認視窗切換為全螢幕。<br>2. WebView2 有焦點時按 `F11` 確認能切換。<br>3. 全螢幕狀態下切換畫面或退出閱讀器回到書架，確認全螢幕維持。<br>4. 連按 `F11` 確認畫面不閃爍、不崩潰。<br>5. 重啟 App 確認恢復為一般視窗（不持久化）。 | 待驗證 | 尚未在 Windows 實機驗證 |
| **條件 8** | Esc 鍵層級處理 | 1. 視窗全螢幕下，開啟對話框按 `Esc`：對話框關閉，視窗全螢幕維持。<br>2. 視窗全螢幕下，劃線選取文字彈出工具列時按 `Esc`：工具列關閉選取清除，視窗全螢幕維持。<br>3. 視窗全螢幕下，PDF 處於手動裁切模式按 `Esc`：維持裁切模式與全螢幕（按鍵被吞掉）。<br>4. 視窗全螢幕下無任何浮層按 `Esc`：退出視窗全螢幕。<br>5. 非全螢幕下按 `Esc`：確認閱讀器不會退出回到書架。 | 待驗證 | 尚未在 Windows 實機驗證 |

---

## 已知邊界與限制

1. **不可關閉的對話框（`barrierDismissible: false`）**：
   - 當畫面上彈出不可點擊外部或無法用 Esc 關閉的強制性對話框時，按 Esc 會因內層對話框未處理 `DismissIntent`，由外層 `WindowFullscreenShortcuts` 退出視窗全螢幕。此為 Flutter 焦點樹機制的預期行為。
2. **TTS 朗讀面板**：
   - TTS 朗讀面板為常駐控制面板，目前設計不響應 Esc 鍵自動關閉，需由使用者點擊關閉按鈕。
3. **滑鼠滾輪與其他功能快捷鍵**：
   - 本 Issue 依 GRILL 決策專注於翻頁、跳頁、搜尋與視窗全螢幕，目錄、字級調整及滑鼠滾輪翻頁不在範圍內。
