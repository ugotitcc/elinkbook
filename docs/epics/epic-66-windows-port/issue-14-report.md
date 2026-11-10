# Epic 66 Issue 14：Windows 免安裝 zip 打包執行報告

- **執行日期**：2026-11-10
- **產出檔案**：`app/build/windows_zip/elinkbook-1.1.0-b3-windows-x64.zip`（大小 45.83 MB / 48,060,878 bytes）
- **校驗碼**：`C4824EEFE5870382CBB96E1F596D947CC5FBA8F83135C678B06AF31C8A29DE35`（SHA256，UTF-8 無 BOM 編碼，支援 POSIX/coreutils `sha256sum -c`）
- **測試環境**：Windows 11 家用版（Home，本機開發環境，已安裝 VS 2022 Build Tools、VC++ 執行階段、WebView2 Runtime 142.0.3595.65）
- **修訂說明**：本報告已依 `reviews/review-code-issue-14.md` 修正。第 2～4 節的輸出已用審查修正後的腳本重新執行並貼原文（執行日 2026-11-10，分支 `feat/epic-66-issue-14-zip`，基底 commit `2f4b5fce` 加上審查修正的未提交變更）。zip 內含時間戳，**每次打包的位元組雜湊都不同**（只有檔案清單一致），所以文中雜湊以最後一次打包為準。
- **限制說明**：本報告之所有實測與自動化驗證結果**僅代表本機開發環境與 Release 建置輸出**，未外推至乾淨機器。依據專案原則，乾淨機器（未安裝 VC++ 執行階段）、Windows 10 1809 實測、他人電腦環境、SmartScreen 實際跳出行為與 WebView2 缺失行為嚴格標記為「未驗證」，嚴禁外推。

---

## 1. 核心決策與查證事實

1. **VC++ 執行階段隨附（App-local 部署）**：
   - `dumpbin /dependents` 查證顯示：`elinkbook.exe`、`flutter_inappwebview_windows_plugin.dll`、`flutter_secure_storage_windows_plugin.dll` 等均動態依賴 `MSVCP140.dll`、`VCRUNTIME140.dll`、`VCRUNTIME140_1.dll`。若乾淨 Windows 機器未安裝 Visual C++ 可轉散發套件，啟動時將直接報錯遺失 DLL。
   - 依據 2026-11-10 使用者決策，採用 app-local 隨附部署，將三個 DLL 由 VS Build Tools 的 Redist 目錄複製到執行檔同層打包進 zip。
   - 本機 Redist 來源為 `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT\`（由 `Microsoft.VCRedistVersion.default.txt` 定位）。
2. **依賴靜態檢查（`dumpbin /dependents`）**：
   - 由於開發機器 `%SystemRoot%\System32` 已存在 VC 執行階段 DLL，單純啟動 App 無法測出打包是否缺漏 VC DLL。
   - 在打包腳本中內建 `Test-StagedDependencies` 函式，防禦性斷言三個 VC DLL 實體存在，並以 `dumpbin` 逐檔檢查每個二進位檔依賴。除 Windows 內建 UCRT（`api-ms-win-*`）與 System32 系統 DLL 外，所有非系統依賴以及 VC 執行階段 DLL 皆**必須實體存在於目錄根**。
3. **排除 `dartjni.dll`（計畫外的偏離，已記入 epic.md 決策 30）**：
   - 事實（已查證）：`jni 1.0.3` 是 `path_provider_android 2.3.1` 的相依（其 `pubspec.yaml` 第 21 行 `jni: ^1.0.0`），`pubspec.yaml` 沒有直接相依；`windows/flutter/generated_plugins.cmake` 把 `jni` 列為 FFI 外掛，所以 Windows 建置會產出 `dartjni.dll`；`dartjni.dll` 依賴本機沒有的 `jvm.dll`。`lib/` 下搜尋 `package:jni`、`jni.dart`、`JniUtils`、`dartjni` 皆無結果。
   - 推論（**未以行程監看實證**）：Windows 版執行期不載入它。支持這個推論的實測只有：排除該 DLL 的 zip 在本機啟動、視窗出現並存活 20 秒（第 4 節）。若日後發現某功能在 Windows 需要它，要重新評估。
   - 做法：打包時在暫存組裝階段排除，讓依賴靜態檢查不會被這個不會用到的 DLL 擋下。計畫與過關條件原本沒有這項排除，屬偏離。
4. **只自用不發佈**：
   - 依 Epic 決策 10，本階段為免安裝 zip 自用，不作程式碼簽章、不建立 MSIX、不製作安裝程式、不上傳 GitHub Release。

---

## 2. 打包腳本驗證紀錄（Task 1）

腳本路徑：`app/tool/package_windows_zip.ps1`

### 驗證 1：正常打包流程
- **指令**：`powershell -ExecutionPolicy Bypass -File tool/package_windows_zip.ps1 -SkipBuild`（在 `app/` 執行）
- **輸出（節錄）**：
  ```text
  [依賴檢查通過] 已檢查 19 個二進位檔，無缺失依賴。
   打包成功！
   檔案大小: 45.83 MB
   內容筆數: 119 檔 (144 項目)
   SHA256:   C4824EEFE5870382CBB96E1F596D947CC5FBA8F83135C678B06AF31C8A29DE35
  ```
- **結束碼**：0。zip 實際大小 48,060,878 bytes；`.sha256` 內容 `C4824EEF…DE35  elinkbook-1.1.0-b3-windows-x64.zip`（純檔名）。
- **清單檢核**：含 `elinkbook/elinkbook.exe`、`elinkbook/README.txt`、三個 VC DLL、`elinkbook/data/foliate/main.js`；全為 `/` 分隔；無 `.pdb`／`.lib`／`.exp`／`.ilk`、無 `dartjni.dll`。

### 驗證 2：深層目錄自動建立
- **指令**：`-SkipBuild -OutDir <scratchpad>\deep\nested\out`（目錄事先不存在）
- **結果**：結束碼 0，自動建立並輸出 zip（48,060,913 bytes）與 `.sha256`（101 bytes）。

### 驗證 3：找不到 Redist 時失敗且不留正式 zip
- **方式**：把腳本內讀取的檔名 `Microsoft.VCRedistVersion.default.txt` 暫時換成不存在的檔名（用臨時複本腳本，跑完已刪除，未動 VS 安裝）。
- **輸出**：
  ```text
  [錯誤] 找不到 VCRedistVersion.default.txt: C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\Microsoft.VCRedistVersion.NOTEXIST.txt
  ```
- **結果**：結束碼 1；`build/windows_zip/` 下**沒有任何 zip 或 `.sha256`**（腳本開頭先清掉舊的正式產物，所以即使上一次成功過也不會殘留）。

### 驗證 4：連續打包內容一致性
- **方式**：同一份建置輸出連續打包兩次，各以 `tar -tf` 取清單、排序後比對。
- **結果**：兩份都是 144 項，差異 0。位元組雜湊每次不同（zip 含時間戳），本計畫只要求清單一致。

---

## 3. 依賴靜態檢查與變異測試紀錄（Task 2）

靜態檢查函式：`Test-StagedDependencies`（支援獨立參數 `-CheckOnly <目錄>`）
檢查目標：目錄內 19 個二進位檔（`elinkbook.exe`、13 個外掛 DLL、3 個 VC DLL 等）。

### 變異測試 1：基準檢查（完整隨附）
- **指令**：`powershell -ExecutionPolicy Bypass -File tool/package_windows_zip.ps1 -CheckOnly <暫存目錄副本>`
- **輸出**：`[依賴檢查通過] 已檢查 19 個二進位檔，無缺失依賴。`　**結束碼 0**。

### 變異測試 2：刪除 `vcruntime140_1.dll`
- **輸出（節錄；其餘 11 行為其他外掛 DLL 同一模式）**：
  ```text
   依賴靜態檢查失敗！發現 14 項問題：
    - [實體檔案缺失] 目錄根缺少必要 VC 執行階段: vcruntime140_1.dll
    - connectivity_plus_plugin.dll -> VCRUNTIME140_1.dll (VC 執行階段必須隨附在應用目錄，不可依賴系統目錄)
    - elinkbook.exe -> VCRUNTIME140_1.dll (VC 執行階段必須隨附在應用目錄，不可依賴系統目錄)
    - flutter_inappwebview_windows_plugin.dll -> VCRUNTIME140_1.dll (…同上)
    - msvcp140.dll -> VCRUNTIME140_1.dll (…同上)
    ...
  ```
- **結果**：**結束碼 1**。

### 變異測試 3：還原後改刪 `msvcp140.dll`
- **輸出（節錄）**：`依賴靜態檢查失敗！發現 13 項問題：`，第一行 `[實體檔案缺失] 目錄根缺少必要 VC 執行階段: msvcp140.dll`，其後為 `elinkbook.exe -> MSVCP140.dll (VC 執行階段必須隨附在應用目錄，不可依賴系統目錄)` 等 12 行。
- **結果**：**結束碼 1**。

### 變異測試 4：還原後複檢
- **輸出**：`[依賴檢查通過] 已檢查 19 個二進位檔，無缺失依賴。`　**結束碼 0**。

---

## 4. 本機驗證與負向驗證紀錄（Task 4）

驗證腳本路徑：`app/tool/verify_windows_zip.ps1`

### 驗證情境
- 解壓路徑：`%TEMP%\含 空格 與 中文\elinkbook\`（`-WorkDir` 預設 `$env:TEMP`）。
- 唯讀權限控制：`icacls` 對目前使用者 SID 加上 `(OI)(CI)(WD,AD,DC)` 拒絕寫入、建立子資料夾與刪除。
- 啟動方式：`Start-Process -WorkingDirectory <程式目錄>`，與使用者在檔案總管雙擊的工作目錄一致。

### 基準驗證結果（8 項檢核全數通過，結束碼 0）
```text
[通過] 解壓縮驗證 :: 成功解壓至含空格與中文之目錄，二進位檔存在
[通過] ACL 唯讀防護設定 :: 已成功套用 deny (WD,AD,DC) 權限至解壓目錄
[通過] 主視窗偵測 :: 主視窗於 3.7 秒內成功建立 (Handle: 5703288)
[通過] 視窗持續存活 :: 視窗出現 20 秒後行程仍穩定執行 (PID: 15508)
[通過] AppData 寫入驗證 :: 既有 AppData 目錄偵測到當次啟動更新的檔案 (共 22 個新寫入/更新項目)
[通過] 行程樹終止 :: elinkbook.exe 已終止
[通過] WebView2 子行程終止 :: 使用本程式資料夾的 msedgewebview2.exe 殘留數: 0
[通過] 解壓目錄零寫入 :: 解壓資料夾在執行前後檔案完全一致 (0 變動)
 本機驗證全數通過！
```
- 「WebView2 子行程終止」檢查不是空轉：另以獨立指令確認 App 執行中，同一個比對條件確實抓到 6 個 `msedgewebview2.exe`，結束後為 0。
- 結論：視窗出現後存活 20 秒，滿足過關條件 4 的存活要求。

### 負向驗證：缺少 VC DLL 的 zip 在本機仍可啟動
- **操作**：把 `vcruntime140_1.dll` 從 zip 移除，以該 zip 執行 `verify_windows_zip.ps1`。
- **結果**：`[通過] 視窗持續存活 …`、`本機驗證全數通過！`，結束碼 0。
- **說明**：本機 `%SystemRoot%\System32` 有這個 DLL，Windows 載入器退回系統目錄載入。**所以本機動態驗證抓不到「zip 缺 VC DLL」**；這一關只能靠第 3 節的 `dumpbin` 依賴檢查，且它也只證明檔案依賴齊全，**不得**據此宣稱缺 DLL 的乾淨機器能開。

### 寫入偵測防護驗證
- **操作**：用臨時複本腳本，在移除 deny ACL 之後、快照比對之前，向程式資料夾寫入 `leak_test.txt`（複本已刪除）。
- **輸出**：
  ```text
  [失敗] 解壓目錄零寫入 :: 解壓資料夾偵測到檔案變動：
    新增檔案: elinkbook\leak_test.txt
   本機驗證有項目未通過！
  ```
  結束碼 1，證實比對真的會抓到寫入。

### 清理範圍保護（審查 Minor 9、修正過程中發現的缺陷）
- **操作**：`-WorkDir` 指到一個已含 `含 空格 與 中文\mine.txt` 的資料夾。
- **結果**：`[失敗] 解壓目錄檢查 :: 既有資料夾含非本腳本產生的內容，拒絕刪除…`，結束碼 1，`mine.txt` 仍在。
- **過程中發現並修正**：第一版守門雖拒絕了，但 `finally` 仍無條件清理，`mine.txt` 被刪掉。已改為只有本腳本自己建立的目錄（`$ownsExtractTarget`）才清理，修正後重跑確認 `mine.txt` 仍在。

---

## 5. 使用者人工開書確認

- **測試項目**：在解壓出的 Release 版中開啟一本 EPUB 書籍。
- **狀態**：**通過（使用者回報，2026-11-10）**。
- **使用者回報原文**：「開書測試通過」。
- **說明**：使用者以最後一次打包的 zip（SHA256 `C4824EEF…DE35`）解壓後雙擊 `elinkbook.exe` 測試。**回報沒有逐項紀錄**：實際解壓路徑、開的書名與格式、翻頁情形皆未記錄，所以只能確認「使用者認為開書成功」，不能外推到特定路徑或書籍。過關條件 5 視為達成；乾淨機器等仍為未驗證（見第 7 節）。

---

## 6. 全套自動化測試與靜態分析

- `flutter analyze`：**通過（No issues found!）**（2026-11-10，審查修正後重跑）。
- 全套 `flutter test`（審查修正後重跑）：**+5161 ~2 -3**，3 項失敗全在 `test/downloads/download_queue_controller_test.dart`（「偵測到重複且 onDuplicateConfirm 回傳 false…」、「resolveUpdate 取代／並存成功…」、「原暫存檔在進入待確認後被刪除」）。該檔**單獨連跑 3 次皆全數通過（28 項）**，整批跑時才失敗，判斷為偶發；本 Issue 沒有任何 Dart 變動，與此無關，但**根因未查**。先前報告寫「5,163 passed、1 項失敗」的數字無法佐證，已作廢，以本次實測為準。

---

## 7. 嚴格邊界與未驗證清單

依據嚴格審查與不外推原則，以下項目列為**未驗證**：
1. **乾淨機器（無 VC++ 執行階段）**：未在無 VC++ 執行階段的全新 Windows 機器或虛擬機中實測執行。
2. **Windows 10 1809 相容性**：本機為 Windows 11，未在 Windows 10 1809 實體環境中執行。
3. **SmartScreen 實際跳出行為**：未經網路下載與外部來源標記（Zone.Identifier）觸發 SmartScreen。
4. **WebView2 Runtime 缺失時行為**：本機已內建 WebView2，未實測未安裝時的跳轉下載提示。
5. **他人電腦與其他 GPU/顯示驅動環境**：未在其他硬體組態上測試。

---

## 8. 成果檔案與交付

- 打包腳本：`app/tool/package_windows_zip.ps1`
- 驗證腳本：`app/tool/verify_windows_zip.ps1`
- 免安裝 README：`app/windows/packaging/README.txt`
- 工具說明文件：`app/tool/README.md`
- 壓縮產物：`app/build/windows_zip/elinkbook-1.1.0-b3-windows-x64.zip`（與同名 `.sha256`）
