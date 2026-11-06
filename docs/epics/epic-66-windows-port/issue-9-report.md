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
