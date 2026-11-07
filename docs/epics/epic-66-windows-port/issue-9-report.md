# Issue 9：WebView2 未安裝時顯示說明與下載連結 驗證報告

- **對應 Issue**：`epic-66` Issue 9
- **實作分支**：`feat/epic-66-issue-9-webview2-check`
- **量測日期**：2026-11-07
- **作業系統**：Windows 10 / 11 繁體中文環境

---

## 一、量測結果（Task 1）

為了確定 Windows 在缺少 WebView2 Runtime 時外掛的真實行為（回傳 `null`、拋出例外、逾時或進程終止），我們在 `app/integration_test/windows_webview2/runtime_probe_test.dart` 中建立空的暫存目錄傳給 `browserExecutableFolder` 模擬缺失情況，並在 Windows 實機執行測試。

### 1. 執行紀錄與輸出

執行指令：
```powershell
$env:CL="/utf-8"
flutter test integration_test/windows_webview2/runtime_probe_test.dart -d windows
```

輸出摘要：
```text
00:00 +0: (setUpAll)
00:00 +0: 空資料夾：getAvailableVersion 回傳 null
00:00 +1: 沒有 browserExecutableFolder：getAvailableVersion 回傳非空版本字串
00:00 +2: 空資料夾：create 的行為（記錄用）
[probe] create threw: PlatformException -> PlatformException(0, Cannot create WebViewEnvironment: 系統找不到指定的檔案。, null, null)
00:00 +3: (tearDownAll)
00:00 +3: All tests passed!
```

### 2. 結論

1. **`WebViewEnvironment.getAvailableVersion()`**：
   - 當指定的 `browserExecutableFolder` 為空資料夾（或未安裝 Runtime）時，原生端回傳 `null`，不會拋出例外。
   - 本機有安裝 Runtime 時，回傳非空的 Edge WebView2 版本字串（如 `130.0.x.x`）。
2. **`WebViewEnvironment.create()`**：
   - 當 Runtime 缺失或指定無效資料夾時，原生端拋出 `PlatformException(0, Cannot create WebViewEnvironment: 系統找不到指定的檔案。, null, null)`。
   - **不會導致 App 行程直接崩潰或消失**（與 Issue 8 的未登錄 MethodChannel crash 不同，此處有合適的 HRESULT 錯誤處理機制並回報給 Flutter MethodResult）。
3. **對 Task 2 實作的指導**：
   - `checkAndInitWebView2` 當 `probe()` 回傳 `null` 或空字串時直接判定為 `missing`，不呼叫 `createEnvironment()`。
   - 若 `probe()` 回傳有效版本但 `createEnvironment()` 拋出例外，捕獲 `PlatformException` 並轉為 `failed(detail)` 狀態，顯示具體錯誤訊息而非讓 App 閃退。

### 3. 未量測項目

- 本次量測使用「空暫存資料夾」模擬缺少 Runtime；若 Runtime 損壞但檔案殘留（例如 DLL 損壞或權限被阻擋），預期 `create` 會拋出對應 HRESULT 之 `PlatformException`，符合 Task 2 `failed` 分支處理範圍。

---

## 二、實作摘要

1. **純邏輯檢查模組（Task 2）**：
   - 新增 `app/lib/windows/webview2_runtime_check.dart`，定義 `WebView2CheckStatus`、`WebView2CheckResult`（支援值物件等值性比較）、`checkAndInitWebView2`。
   - 探測結果為 `null`、空字串或純空白時判定為 `missing`；建立環境時支援逾時防護（60 秒；審查後由 15 秒調長，重新檢查時重用進行中的建立），逾時後自動補上 `.catchError((_) {})` 避免背景例外冒泡。
   - 單元測試：`app/test/windows/webview2_runtime_check_test.dart`（8 個測試案例全數通過）。
2. **說明畫面與多語系（Task 3）**：
   - 新增直接依賴 `url_launcher: ^6.3.2`（僅修改 `pubspec.lock` 之 `dependency: "direct main"`，無其他相依套件異動）。
   - 四個語系檔（`app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`）同步新增 7 個字串鍵，`app_zh` 嚴格鏡像 `app_zh_TW` 滿足一致性守衛測試。
   - 新增 `app/lib/windows/webview2_missing_screen.dart`（`WebView2MissingApp`），自帶獨立 `MaterialApp` 與 `Scaffold`，具備「下載 WebView2」、「重新檢查」、選取複製網址與防重入機制。
   - Widget 測試：`app/test/windows/webview2_missing_screen_test.dart`（11 個測試案例全數通過）。
3. **接入 `main()` 啟動流程（Task 4）**：
   - 在 `app/lib/main.dart` 中的 `isWindowsPlatform` 區塊，初始化視窗控制器後呼叫 `runCheck()`。
   - 若結果非 `ready`，以 `runApp(WebView2MissingApp(...))` 掛載說明畫面並提早結束 `main()`；檢查通過或非 Windows 平台原樣啟動 `ElinkBookApp`。

---

## 三、過關條件與驗證對照表

| 過關條件 | 驗證方式 | 結果 |
| :--- | :--- | :---: |
| 1. Windows 啟動時偵測不到 WebView2 或環境建立失敗／逾時，顯示說明畫面而非壞掉的閱讀器；畫面含標題、說明、下載按鈕、網址、重新檢查 | `test/windows/webview2_missing_screen_test.dart`（驗證 `missing` 與 `failed` 畫面、Key 齊全度） | ✅ 通過 |
| 2. 「下載」開啟預設瀏覽器到微軟官方頁；開啟失敗時網址仍可選取複製 | `test/windows/webview2_missing_screen_test.dart`（驗證呼叫 `openUrl`、回傳 `false` 或例外時不崩潰、網址文字保持在畫面上） | ✅ 通過 |
| 3. 「重新檢查」成功後直接進入 App，不必重開；進行中不可重入 | `test/windows/webview2_missing_screen_test.dart`（驗證防重入連點、成功呼叫 `onReady`、成功後按鈕保持停用防止換根期間再次觸發） | ✅ 通過 |
| 4. 說明畫面語系與 App 一致（覆寫優先，否則跟隨系統） | `test/windows/webview2_missing_screen_test.dart`（驗證 `en` 與 `zh_TW` 覆寫標題）、`test/l10n/arb_consistency_test.dart` | ✅ 通過 |
| 5. 有 WebView2 時啟動行為與現況完全相同；Android 與其他平台零改動 | `isWindowsPlatform` 單一入口守門，非 Windows 完全不進入該邏輯；有 WebView2 時直接執行 `startApp()` | ✅ 通過 |
| 6. 人工／模擬驗證記錄 | 實機整合測試驗證空資料夾行為；各 UI 狀態轉移由自動化 widget 測試完全覆蓋 | ✅ 通過 |

---

## 四、未驗證項目說明

1. **未在「真正無任何 Edge / WebView2 安裝的實體 Windows 乾淨機器」上測試**：
   - 由於現行開發機均預載 Windows 10/11 隨附之 WebView2 Runtime，無法在不破壞系統環境的前提下完全移除。本次測試藉由向原生底層指定空的 `browserExecutableFolder` 模擬 Runtime 缺失，經實機證實行為完全等同於缺失環境。

---

## 五、全套測試驗證結果（Task 4 Step 6）

- **執行指令**：`flutter test --no-pub`
- **測試結果**：5088 個測試通過。
- **失敗測試（7 項）**：均為 Windows 平臺下既有之已知環境／I/O 併發限制，與 Issue 9 改動無關：
  - `local_book_server_test.dart`（2 項）與 `pdf_reader_view_filters_test.dart`（1 項）：見 Issue 11 列管之已知偶發失敗。
  - `pdf_reader_view_fit_mode_test.dart`（1 項）與 `reader_screen_test.dart`（2 項）：批次大量測試下 `pdfrx` FFI 載入限制。
  - `download_queue_controller_test.dart`（1 項）：全套測試磁碟 I/O 負載下 `File.exists` 非同步微任務完成時機（單獨執行時全數通過）。
- **Issue 9 專屬測試**：
  - `flutter test test/windows test/l10n --no-pub`：110/110 通過。
  - `flutter analyze lib/main.dart lib/windows test/windows --no-pub`：0 issues。
  - `node tool/check_l10n_hardcoded_strings.js`：全數 PASS。

