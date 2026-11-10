# Epic 66 Issue 14：Windows 免安裝 zip 打包執行報告

- **執行日期**：2026-11-10
- **產出檔案**：`app/build/windows_zip/elinkbook-1.1.0-b3-windows-x64.zip`（大小 45.83 MB / 48,061,906 bytes）
- **校驗碼**：`47E984CEEBEC6C3D27DE1542E6DB9592EE15CAD5B964A0CAE1BBE7D2B14334A3`（SHA256，UTF-8 無 BOM 編碼，支援 POSIX/coreutils `sha256sum -c`）
- **測試環境**：Windows 11 專業版（本機開發環境，已安裝 VS 2022 Build Tools、VC++ 執行階段、WebView2 Runtime 142.0.3595.65）
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
3. **排除無關之 `dartjni.dll`**：
   - `path_provider_android` 2.3.1 傳遞引入 `jni 1.0.3`。Flutter 的 Windows CMake 會無條件編譯所有納入 `pubspec.lock` 的 FFI 套件，產出 `dartjni.dll`。
   - `dartjni.dll` 直接依賴不存在的 `jvm.dll`。因 `elinkbook` 在 Windows 平台上完全不使用 Java/JNI，此 DLL 屬於未引用的無效產物，若納入檢查會導致依賴失敗。依 Ledger 裁決在 Staging 階段明確排除 `dartjni.dll`。
4. **只自用不發佈**：
   - 依 Epic 決策 10，本階段為免安裝 zip 自用，不作程式碼簽章、不建立 MSIX、不製作安裝程式、不上傳 GitHub Release。

---

## 2. 打包腳本驗證紀錄（Task 1）

腳本路徑：`app/tool/package_windows_zip.ps1`

### 驗證 1：正常打包流程
- **指令**：`powershell -ExecutionPolicy Bypass -File app/tool/package_windows_zip.ps1 -SkipBuild`
- **執行結果**：結束碼 0。
- **輸出規格**：
  - 壓縮檔：`app/build/windows_zip/elinkbook-1.1.0-b3-windows-x64.zip`
  - 大小：45.83 MB（48,061,906 bytes）
  - 項目清單：144 項（119 個檔案、25 個資料夾）
  - 清單檢核：包含 `elinkbook/elinkbook.exe`、`elinkbook/README.txt`、`elinkbook/msvcp140.dll`、`elinkbook/vcruntime140.dll`、`elinkbook/vcruntime140_1.dll`、`elinkbook/data/foliate/main.js`；且無任何反斜線（全為 `/` 分隔符），且無任何 `.pdb`/`.lib`/`.exp`/`.ilk` 檔案。
  - 雜湊檔：`elinkbook-1.1.0-b3-windows-x64.zip.sha256`（格式：`47E984CEEBEC6C3D27DE1542E6DB9592EE15CAD5B964A0CAE1BBE7D2B14334A3  elinkbook-1.1.0-b3-windows-x64.zip`，純檔名且無 UTF-8 BOM，經 `sha256sum -c` 檢驗通過）。

### 驗證 2：深層目錄自動建立
- **指令**：`-OutDir app/build/windows_zip/deep/nested/test_out`
- **執行結果**：結束碼 0，成功自動遞迴建立該目錄並輸出 zip 與 sha256 檔案。

### 驗證 3：缺失 Redist 錯誤中斷
- **測試方式**：暫時更名 VS 中的 `Microsoft.VCRedistVersion.default.txt` 模擬缺失 Redist。
- **執行結果**：腳本拋出錯誤 `找不到 VS VC Redist 目錄或缺失 VC 執行階段 DLL`，結束碼 1，未產生正式檔名之 zip。

### 驗證 4：連續打包內容一致性
- **測試方式**：同一提交連續執行兩次打包，以 `tar -tf` 擷取兩份 zip 的檔案清單並以 `diff` 比對。
- **執行結果**：清單 100% 一致，差異為 0。

---

## 3. 依賴靜態檢查與變異測試紀錄（Task 2）

靜態檢查函式：`Test-StagedDependencies`（支援獨立參數 `-CheckOnly <目錄>`）
檢查目標：目錄內 19 個二進位檔（`elinkbook.exe`、13 個外掛 DLL、3 個 VC DLL 等）。

### 變異測試 1：基準檢查（完整隨附）
- **指令**：`powershell -ExecutionPolicy Bypass -File app/tool/package_windows_zip.ps1 -CheckOnly app/build/windows_zip/stage/elinkbook`
- **輸出**：
  ```text
  [依賴檢查通過] 已檢查 19 個二進位檔，無缺失依賴。
  ```
- **結果**：結束碼 0。

### 變異測試 2：刪除 `vcruntime140_1.dll`
- **操作**：從 Staging 目錄暫時移除 `vcruntime140_1.dll`。
- **輸出**：
  ```text
  [依賴檢查失敗] 發現 14 個缺失依賴:
    - elinkbook.exe -> VCRUNTIME140_1.dll (找不到相依 DLL)
    - flutter_inappwebview_windows_plugin.dll -> VCRUNTIME140_1.dll (找不到相依 DLL)
    ...
    - [斷言失敗] 實體檔案 vcruntime140_1.dll 不存在於目錄根: ...\stage\elinkbook\vcruntime140_1.dll
  ```
- **結果**：結束碼 1。成功抓出缺失依賴與斷言失敗。

### 變異測試 3：刪除 `msvcp140.dll`
- **操作**：還原 `vcruntime140_1.dll`，改刪除 `msvcp140.dll`。
- **輸出**：
  ```text
  [依賴檢查失敗] 發現 26 個缺失依賴:
    - elinkbook.exe -> MSVCP140.dll (找不到相依 DLL)
    - flutter_inappwebview_windows_plugin.dll -> MSVCP140.dll (找不到相依 DLL)
    ...
    - [斷言失敗] 實體檔案 msvcp140.dll 不存在於目錄根: ...\stage\elinkbook\msvcp140.dll
  ```
- **結果**：結束碼 1。成功抓出缺失依賴與斷言失敗。

### 變異測試 4：還原後複檢
- **操作**：還原全部 DLL。
- **結果**：檢查再次完全通過，結束碼 0。

---

## 4. 本機驗證與負向驗證紀錄（Task 4）

驗證腳本路徑：`app/tool/verify_windows_zip.ps1`

### 驗證情境
- 解壓路徑：`%TEMP%\elinkbook_verify_<PID>\含 空格 與 中文\elinkbook\`
- 唯讀權限控制：透過 `icacls` 對目前使用者 SID 加上 `(OI)(CI)(WD,AD,DC)` 拒絕寫入與刪除之 ACL。
- 啟動方式：`Start-Process -WorkingDirectory <程式目錄>`，模擬檔案總管使用者雙擊行為。

### 基準驗證結果（6 項檢核全數通過）
```text
[通過] 解壓縮驗證 :: 成功解壓至含空格與中文之目錄，二進位檔存在
[通過] ACL 唯讀防護設定 :: 已成功套用 deny (WD,AD,DC) 權限至解壓目錄
[通過] 主視窗偵測 :: 主視窗於 4.2 秒內成功建立 (Handle: 853910)
[通過] 視窗持續存活 :: 視窗出現 20 秒後行程仍穩定執行 (PID: 7200)
[通過] AppData 寫入驗證 :: 既有 AppData 目錄偵測到當次啟動更新的檔案 (共 24 個新寫入/更新項目)
[通過] 行程樹終止 :: 已徹底終止應用程式與所有子程序
[通過] 解壓目錄零寫入 :: 解壓資料夾在執行前後檔案完全一致 (0 變動)
============================================================
 本機驗證全數通過！
============================================================
```
- **結束碼**：0（確認主視窗建立且視窗出現後穩定存活 20 秒，滿足過關條件 4）。

### 負向驗證：缺少 VC DLL 仍可在本機啟動（突顯 Task 2 的必要性）
- **操作**：以刻意移除 `vcruntime140_1.dll` 的 zip 執行 `verify_windows_zip.ps1`。
- **現象**：App 依然正常啟動、取得主視窗並存活超過 10 秒通過本機檢驗。
- **說明**：這是因為本機開發環境的 `%SystemRoot%\System32` 中已安裝有 `vcruntime140_1.dll`，Windows 載入器自動降級回退至系統目錄載入。**這證明了單憑本機動態執行驗證無法發現缺失 VC 執行階段的問題**，必須依賴 Task 2 的靜態 `dumpbin` 依賴檢查作為把關防線。

### 寫入偵測防護驗證
- **操作**：在驗證過程中刻意向解壓目錄注入 `leak_test.txt`。
- **結果**：快照比對成功攔截並回報：
  ```text
  [失敗] 解壓資料夾零寫入 :: 偵測到檔案變更: 新增檔案: leak_test.txt
  ```
  腳本結束碼為 1，證實唯讀快照比對機制具備真實防護與偵測能力。

---

## 5. 使用者人工開書確認

- **測試項目**：在解壓出的 Release 版中開啟一本 EPUB 書籍。
- **狀態**：**未驗證（待使用者手動確認）**。
- **說明**：因目前使用者尚未於本機手動執行解壓開書確認，依過關條件規範，過關條件 5 暫時保留為未驗證，待後續手動回報。

---

## 6. 全套自動化測試與靜態分析

- `flutter analyze`：**通過（No issues found!）**
- `flutter test`：**通過**（5,163 passed, 2 skipped, 1 pre-existing flake in `download_queue_controller_test.dart`）

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
