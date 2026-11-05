# Epic 66 Issue 3 接手交接文件 (Handoff Document)

**建立時間：** 2026-11-05 09:52  
**當前分支：** `feat/epic-66-issue-3-leak-verification`  
**關聯實作計畫：** [`docs/epics/epic-66-windows-port/plans/plan-issue-3.md`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-66-windows-port/plans/plan-issue-3.md)  
**關聯審查報告：** [`docs/epics/epic-66-windows-port/reviews/review-plan-issue-3.md`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-66-windows-port/reviews/review-plan-issue-3.md)  

---

## 1. 交接原因 (Context)

在 SSH 遠端終端連線（Windows 服務 / 非互動式 Session 0）環境中執行 Flutter Windows 整合測試（`-d windows`）時，因 Windows 視窗系統（Window Station / Desktop）與 WebView2 原生合成架構限制，桌面圖形應用程式無法在非互動式環境中正常泵送 UI 訊息與完成視窗初始化，導致測試掛起。

因此將已就緒的整合測試探針交由 **Windows 本機桌面 UI 互動工作階段**（直接登入 Windows 桌面或透過遠端桌面 RDP 介面）執行。

---

## 2. 目前進度狀態 (Current State)

| 項目 | 狀態 | 說明與 Commit |
|---|:---:|---|
| **分支建立** | ✅ 完成 | 工作位於 `feat/epic-66-issue-3-leak-verification`，保護 `main` 分支。 |
| **Task 1：洩漏判定規則** | ✅ 已提交 | [`app/test/windows_leak/leak_verdict.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/test/windows_leak/leak_verdict.dart) 實作完成，單元測試 [`app/test/windows_leak/leak_verdict_test.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/test/windows_leak/leak_verdict_test.dart) 7/7 通過（commit `4fcdbb59`）。 |
| **Task 2：量測 Helper** | ✅ 已提交 | [`app/integration_test/windows_leak/leak_meter.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/integration_test/windows_leak/leak_meter.dart) 實作完成，單元測試 [`app/test/windows_leak/leak_meter_test.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/test/windows_leak/leak_meter_test.dart) 3/3 通過（commit `2aa50ad0`）。 |
| **原生建置環境** | ✅ 完成 | `nuget.exe` 已配置於 `C:\Users\fycdc\bin\nuget.exe` 並登錄至 User PATH；Flutter Windows 插件相依 DLL 皆已就緒。 |
| **Task 3：索引器迴圈** | 🟡 程式碼就緒 | [`app/integration_test/windows_leak/indexer_leak_test.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/integration_test/windows_leak/indexer_leak_test.dart) 撰寫完成，靜態分析 `flutter analyze` 乾淨，待桌面 UI 執行。 |
| **Task 4：閱讀器迴圈** | 🟡 程式碼就緒 | [`app/integration_test/windows_leak/reader_leak_test.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/integration_test/windows_leak/reader_leak_test.dart) 撰寫完成（含 `onError` Fail-Fast 與 `book_cache` 快取刪除斷言），`flutter analyze` 乾淨，待桌面 UI 執行。 |
| **Task 5：報告與停點** | ⚪ 待執行 | 待 Task 3 與 Task 4 取得量測數據後撰寫報告並依停點規則決策。 |

---

## 3. 在 Windows 桌面 UI 接手執行步驟 (Action Steps)

在 Windows 實體桌面或 RDP 視窗中開啟 **PowerShell**（`pwsh` 或 `powershell.exe`）：

### 步驟 3.1：確認路徑與環境變數

```powershell
cd C:\Users\fycdc\AI\elinkBook\app
$env:PATH = "C:\Users\fycdc\bin;" + $env:PATH
$env:MSYS2_ENV_CONV_EXCL = 'CL'
$env:CL = '/utf-8'
```

### 步驟 3.2：執行 Task 3 索引器記憶體量測

```powershell
flutter test integration_test/windows_leak/indexer_leak_test.dart -d windows 2>&1 | Tee-Object -FilePath build/leak_indexer.log
```
*預期耗時約 2～3 分鐘（暖身 1 次 + 正式量測 4 次，每次等待 6 秒冷卻）。*

### 步驟 3.3：執行 Task 4 閱讀器開關記憶體量測

```powershell
flutter test integration_test/windows_leak/reader_leak_test.dart -d windows 2>&1 | Tee-Object -FilePath build/leak_reader.log
```
*預期耗時約 2～3 分鐘（暖身 1 次 + 正式開關 4 次，每次等待 6 秒冷卻）。*

---

## 4. 輸出結果判讀與驗證 (How to Verify)

執行結束後，檢查 `app/build/leak_indexer.log` 與 `app/build/leak_reader.log`，末尾應輸出類似如下格式的結果：

```text
[leak] path=indexer iter=0 phase=before private_mb=... ws_mb=... wv2_private_mb=... wv2_count=...
[leak] path=indexer iter=0 phase=after_run private_mb=... ws_mb=... wv2_private_mb=... wv2_count=...
[leak] path=indexer iter=0 phase=after_wait private_mb=... ws_mb=... wv2_private_mb=... wv2_count=...
...（iter 1 到 4 重複輸出）
[leak-verdict] path=indexer leaked=false ratcheting=false deltas=[...] exceeded=[] threshold_mb=11.23
```

- **門檻標準：** 224.7 MB EPUB × 5% ＝ **11.23 MB**。
- **leaked = true：** 任一次迭代增量超過 11.23 MB。
- **ratcheting = true：** 第 1～4 次增量皆大於 0（持續棘輪上升）。

---

## 5. 後續處置與 Task 5 停點規則 (Next Steps)

量測數據產生後，可直接切回 Antigravity CLI 進行後續彙整：

1. **若任一路徑判定 `leaked == true`：**
   - 建立 [`docs/epics/epic-66-windows-port/issue-3-report.md`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-66-windows-port/issue-3-report.md) 寫入數據與判定。
   - **依照計畫範圍嚴格停下**，不修改 `lib/`，將數據與修法選項（如區段傳輸或啟動 `shelf` 本機伺服器備案）呈報使用者討論決定。
2. **若兩條路徑皆判定 `leaked == false`：**
   - 建立報告記錄穩定未洩漏之原因（分析生命週期差異）。
   - 在 `indexer_leak_test.dart` 與 `reader_leak_test.dart` 啟用 `expect(verdict.leaked, isFalse)` 作為長期回歸防線。
   - 更新 `epic.md` 決策 15 與 `issues.md` Issue 3 為完成狀態。
