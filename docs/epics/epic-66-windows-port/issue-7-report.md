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
