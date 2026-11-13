# Epic 66 Issue 27：Windows 安裝程式（Inno Setup）執行報告

- **執行日期**：2026-11-13
- **產出檔案**（最終版，已移除內建字型與測試用 fixtures）：
  - `app/build/windows_installer/elinkbook-1.1.0-b3-windows-x64-setup.exe`（17.75 MB / 18,613,674 bytes）
  - SHA256：`68735C437AFCDBEF31639932E0BD29F417C9DA1D1E773FB73B7E77A4FDAA0232`
  - 同一份暫存目錄打出的 zip：`elinkbook-1.1.0-b3-windows-x64.zip`（22.01 MB / 23,080,372 bytes），SHA256 `14174EDBF9F95B254FBAC881940262C9B64D688E1E7699A905249679DE43C7A8`
- **固定 `AppId`**：`{C4E48E89-6F1B-4B77-94B9-23BCE3FCC757}`（寫在 `app/windows/packaging/elinkbook.iss`，**發佈後不可更改**，見 ADR 0043）。Inno 登錄機碼名稱實測為 `{C4E48E89-6F1B-4B77-94B9-23BCE3FCC757}_is1`（單花括號）。
- **測試環境**：Windows 11 家用版（本機開發機，有 VS 2022 Build Tools、VC++ 執行階段、WebView2 Runtime）；另一台電腦由使用者手動安裝、移除、開書（見第 6 節，環境細節使用者未說明）。
- **限制說明**：自動化驗證結果只代表這台本機開發機與 Release 建置輸出；另一台電腦的結果是使用者回報原文，沒有逐項紀錄，也沒有查證那台機器是否缺 VC 執行階段或 WebView2，**不外推為乾淨機器驗證**。

---

## 1. 已查證事實與決策

1. **Inno Setup**：用 `winget install --id JRSoftware.InnoSetup -e` 安裝 6.7.3（使用者同意後執行），`ISCC.exe` 在 `%LOCALAPPDATA%\Programs\Inno Setup 6\`（使用者範圍）。
2. **繁體中文介面**：6.7.3 的 `Languages\` 沒有任何中文翻譯檔。使用者選擇「自帶翻譯檔」，改取自 `jrsoftware/issrc` main 的官方 `Files/Languages/ChineseTraditional.isl`（非 Unofficial 資料夾，標頭為 6.5.0+，授權為 Inno Setup License，允許任何用途含商業、保留版權聲明下再散布），原封複製到 `app/windows/packaging/ChineseTraditional.isl`，6.7.3 編譯通過。
3. **暫存目錄沿用**：`package_windows_zip.ps1` 只在開頭清除並重建 `<OutDir>/stage/elinkbook`，結束後保留；安裝程式腳本直接使用，並永遠先對它跑 `-CheckOnly`。
4. **VC 可轉散發授權（對外發佈新增的風險，Issue 14 報告曾列為待確認）**：本機 `Licenses\1028\Redist.txt` 只是指向線上清單的連結。微軟「Visual Studio 2022 Redistribution」頁寫明：可隨程式散布 `[VisualStudioFolder]\VC\redist` 子樹的檔案（三個 DLL 位於 `VC\Redist\MSVC\<版>\x64\Microsoft.VC143.CRT`，不在不可散布的 `debug_nonredist`），**但同頁註記「僅限有授權的 Visual Studio 使用者，受其授權條款約束」**。這台機器裝的是 Build Tools，**Build Tools 是否算「有授權的 Visual Studio 使用者」未查證**——這是對外發佈前仍待使用者判斷的風險，不是已確認可行。

---

## 2. 打包腳本驗證（Task 1）

- 完整流程（含 `flutter build windows --release`）exit 0；`-SkipBuild` 重跑 exit 0。
- 輸出 `.sha256` 用 `certutil` 重算一致；檔名版本取自 `pubspec.yaml`（`1.1.0+3` → `1.1.0-b3`）。
- 第一次實跑在 SHA256 步驟失敗：這台機器的 PowerShell 5.1 沒有 `Get-FileHash`（zip 腳本同樣有 .NET 備援），已改用 .NET 計算。
- **變異驗證（a）缺 VC DLL 必須失敗**：複製暫存目錄、刪掉 `vcruntime140_1.dll`，用 `-StageDir` 指向它執行 → exit 1、訊息列出 `screen_retriever_windows_plugin.dll -> VCRUNTIME140_1.dll` 等缺依賴、輸出目錄沒有 setup.exe。

---

## 3. 本機自動驗證（Task 3）

`verify_windows_installer.ps1`，最終版共 **29 項全部通過、exit 0**（經第 8 節的獨立審查後補強；補強前為 27 項）。涵蓋：靜默安裝到「含 空格 與 中文」路徑不需管理員（1a～1c）、安裝內容必備檔與無除錯檔／字型／測試資源（2a～2d）、開始功能表與桌面捷徑（3a～3b）、主視窗與存活 20 秒（4a～4b）、執行中覆蓋升級（5a～5f）、資料保護（6a～6c）、靜默解除安裝（7a～7c，輪詢實測 2.2～3.1 秒）、取消桌面捷徑（8a～8c）、結束無殘留（9）。

- **前三次實跑 6b 失敗**：升級前存在、升級後消失的唯一檔案是 `webview_data\EBWebView\lockfile`（App 執行期間才存在，被 `CloseApplications` 關閉後自動消失；341 個真資料檔都在）。判定為 WebView2 的執行期鎖檔而不是使用者資料，比對時排除它（已記入 ledger 的 Ruling）。
- **審查 I-2 實證**：Inno 解除安裝程式確實不能只等行程結束，腳本以輪詢等程式檔與登錄項消失。
- **審查 I-3 實證**：登錄機碼名稱是單花括號 `{GUID}_is1`，只需把 `AppId` 的**開頭**花括號雙寫（`{{GUID}`）；審查報告主張結尾也要雙寫，實測不成立。
- **較舊版本 setup.exe 的做法**：複製暫存目錄、`README.txt` 改成 `OLD-VERSION`、`elinkbook.exe` 尾端加 1 個 0x00 位元組，用 `-StageDir` 與 `-Version 1.0.9+1` 編出；5f 因此能證明檔案真的被新版取代。這不是真實舊版。

### 變異驗證（b）：`AppId` 不固定就會並存

用 `/DAppIdOverride={{11111111-2222-3333-4444-555555555555}` 編出另一個 `AppId` 的 setup，先裝舊版、再裝它到同一目錄：HKCU 同時出現兩個項目（`{1111…}_is1`「elinkBook 版本 1.1.0」與 `{C4E4…}_is1`「elinkBook 版本 1.0.9」），安裝目錄同時有 `unins000.exe` 與 `unins001.exe`（審查 M-3 預測成立）。依各自的 `UninstallString` 清理後，登錄項與安裝目錄皆清除。對照第 3 節檢查 5e：同一 `AppId` 只有一個項目。

### 負向驗證：資料保護檢查本身有效

`-DataDir <假資料夾> -SimulateDataLoss` 在比對前人為刪掉一個檔案 → 6a `[失敗]`（消失 `f1.txt`），其餘 24 項通過、exit 1。

---

## 4. 打包內容問題（使用者在另一台電腦發現，已修）

1. **字型被打包**：`data\flutter_assets\assets\fonts\GuanKiapTsingKhai.ttf`（14.7 MB）。成因：`app/build/flutter_assets/assets/fonts/` 殘留 9 月舊建置的檔案（`pubspec.yaml` 未宣告，`AssetManifest`、`FontManifest` 皆無），Flutter 不清舊資源，CMake 安裝步驟卻整個目錄複製。修法：完整建置前先清 `build\flutter_assets`；依賴檢查（含 `-CheckOnly`）擋 `assets` 下的字型檔。對含字型的舊暫存目錄跑 `-CheckOnly` 先確認失敗並點名該檔，再修。
2. **測試用 fixtures 被打包**：`data\flutter_assets\test`（42 檔、36 MB，其中 `sample.ttf` 35 MB）。成因：`pubspec.yaml` 為整合測試把 `test/fixtures/` 宣告成 asset，`lib/` 沒有任何執行期引用。修法：組裝暫存目錄時移除，依賴檢查擋該資料夾；**不改 `pubspec.yaml`**（會牽動 86 個引用 fixtures 的整合測試與 Android）。
3. 兩項修法都在共用的 `package_windows_zip.ps1`（超出計畫字面，但是同一條打包鏈，且安裝程式腳本會對暫存目錄跑 `-CheckOnly`，因此 `-StageDir` 路徑也受保護）。結果：zip 46→22 MB，setup.exe 47→17.75 MB。

**相關發現（未處理，已另行登記為 Issue 28）**：`pubspec.yaml` 是共用的，Android APK 很可能也帶著這 36 MB 測試檔；未實際檢查 APK。

---

## 5. 全套測試

- `flutter analyze`：No issues found。
- 全套 `flutter test`（無參數）：`+5167 ~2: All tests passed!`（0 失敗、2 跳過）。本 Issue 沒有改任何 Dart 檔。

---

## 6. 人工驗證（使用者回報原文）

- 這台機器：使用者安裝後回報「程式開起來後畫面一片空白」。調查：安裝目錄與暫存目錄逐檔比對一致（128 檔，只多 `unins000.exe`／`.dat`）；機器空閒時，從暫存目錄（等同 zip 版）啟動同一支 `elinkbook.exe` 同樣空白——主視窗已顯示、啟動小視窗已消失、行程閒置、App 自己的 WebView2 行程存在、無崩潰事件。**結論：空白不是安裝程式造成，根因未查明**（見第 7 節）。
- 使用者改在**另一台電腦**測：「我放到另外一台電腦安裝，移除都正常。開啟不會空白畫面。」
- 使用者回報：「解除安裝詢問框選否、選是都測過，正常。」（在另一台電腦；沒有逐項紀錄，也沒有說明預設按鈕是否為「否」、桌面捷徑選項是否預設勾選。）
- 打包內容修正後，使用者回報：「新包開書正常」（另一台電腦，最終版 setup.exe）。
- **更正（見第 8 節 C-1）**：使用者回報的「選是正常」只代表 `%APPDATA%\cc.ugotit\elinkbook` 被刪除；書庫在「文件」資料夾，選「是」不會刪它。
- **資料保護**：開始自動驗證前，已備份 `%APPDATA%\cc.ugotit\elinkbook`（341 檔、57,503,876 bytes），檔案數與總大小一致。因為「選是」刪資料的測試改在另一台電腦做，這台機器沒有刪除資料，**不需要還原**。備份仍在 scratchpad，待使用者確認不需要後再刪。

---

## 7. 未驗證與未解決

**未驗證（不得外推）**：
- 乾淨機器（缺 VC 執行階段、缺 WebView2）：另一台電腦的環境沒有查證，只能視為「在使用者另一台電腦上能裝能開」。
- Windows 10 1809 與 Windows 10 其他版本。
- SmartScreen 的實際行為（兩個 setup.exe 都未簽章）。
- 兩台以外的電腦、非 125% 縮放等顯示設定。
- 解除安裝詢問框的預設按鈕是否為「否」：只有程式碼依據（`MB_DEFBUTTON2`），使用者回報沒有提到。
- 桌面捷徑選項是否「預設勾選」的 GUI 外觀：只由腳本驗證（`/VERYSILENT` 預設建立、`!desktopicon` 不建立），使用者的 GUI 回報沒有提到。
- 真實舊版升級：「舊版」是人工造出來的（見第 3 節）。

**未解決**：
- 這台開發機上安裝版與暫存目錄版皆空白，根因未查明，需要的話另立 Issue 處理。
- VC 可轉散發授權：Build Tools 是否算「有授權的 Visual Studio 使用者」未查證（見第 1 節第 4 點），對外發佈前須使用者判斷。

---

## 8. 獨立審查與修訂（2026-11-13，審查者為 fable 模型，唯讀）

審查結論原為「不建議合併」。處理如下（細節與裁決見 ledger，已不進版控）：

**Critical（已處理，需使用者決定的部分已決定）**
- **C-1 解除安裝選「是」刪不到書庫**：書庫 `library.db`、`covers`、`imported_books` 放在「文件」資料夾（`getApplicationDocumentsDirectory()`；這台機器的 `%USERPROFILE%\Documents` 下確有這三項），不在 `%APPDATA%\cc.ugotit\elinkbook`（只有 WebView2 資料、`downloaded-fonts`、`dictionaries`）。我原本把詢問框與文件寫成「刪書庫與閱讀紀錄」是錯的。**使用者決定：如實改文案，另立 Issue 搬資料位置，且應先在「文件」資料夾下有一個上層目錄 `elinkbook`，讓使用者知道這些資料夾屬於本 App**（Issue 29）。已改 `.iss` 詢問框、`README.txt`（第三節與第七節）、ADR 0043、`issues.md`、`epic.md`。第 6 節使用者回報的「選是正常」只代表 `%APPDATA%` 那個資料夾被刪掉，**不代表書庫被刪**（也不會被刪）。

**Important（已修）**
- **I-1** 檢查 5e 恆真：改為數「所有」elinkBook 解除安裝項與 `unins*.exe`，並在驗證腳本內獨立釘住預期 AppId。變異：把 `.iss` 的 GUID 改一個字元，腳本在開頭即失敗。
- **I-2** 解除安裝比對時點太早：輪詢改為同時等 `unins*.exe`／`_iu*.tmp` 行程結束；且不帶 `/SUPPRESSMSGBOXES`，讓 `UninstallSilent` 成為唯一防線。變異：拿掉防線的版本，7a 失敗。**意外發現**：該變異版指向 scratchpad 假資料夾的 `DelTree` 實際被執行、假資料夾被刪掉（原因不明：詢問框被回答或自動回應），所以變異版的刪除路徑一律指向假資料夾。
- **I-3** App 執行中解除安裝無防護：`.iss` 新增 `InitializeUninstall`（以視窗類別加標題偵測，執行中拒絕）；新檢查 10a；變異：把偵測改成 `if False` 版本，10a 失敗。README 補說明。
- **I-5** 安裝內容與暫存目錄沒有全檔比對：新檢查 2e（逐檔 SHA256，只允許多出 `unins*`），實跑 80 檔一致。
- **I-4、I-6** 文件狀態與措辭：`issues.md`、`epics.md`、`epic.md` 補上空白畫面未解（登記為 Issue 30）與「選是不刪書庫」；ADR 0043 修正「沒有另一台電腦」的說法；`epic.md` 補回「使用者回報、無逐項紀錄」限定語。驗證腳本最終 **29 項全部通過**（`/tmp/verify8.log`）。

**Minor（未處理，列為 deferred）**：資料比對只比檔名不比大小；資料夾為空時 6a～6c 會空洞通過；收尾逾時可能留孤兒登錄項；6b 對 WebView2 其他暫存檔有偶發假失敗風險；`-SkipBuild` 版本不一致只印不擋；`package_windows_installer.ps1` 參數處理不一致（`-StageDir` 相對路徑基準、結尾反斜線）；升級不清舊檔（已裝過含字型與測試資源的舊包，覆蓋升級後那些檔案仍會留在安裝目錄）；顯示版本不含建置號、無降版保護；字型防護範圍窄；`-CheckOnly` 語意改變、README 措辭；README.txt SHA256 範例不適用 setup.exe；`app/tool/README.md` 檢查項描述未列新增項。
