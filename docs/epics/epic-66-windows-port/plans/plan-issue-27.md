# Issue 27：Windows 安裝程式（Inno Setup）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用一支腳本把 Windows release 版包成 Inno Setup 安裝程式 `elinkbook-<版本>-windows-x64-setup.exe`（依使用者安裝、不需管理員、固定 AppId 覆蓋升級、開始功能表與可選桌面捷徑、解除安裝可選擇是否一併刪除 App 資料），並保留既有 zip 免安裝版。

**Architecture:** 不改產品程式。新增兩支 PowerShell 腳本、一份 Inno Setup 腳本（`.iss`）：（1）`package_windows_installer.ps1` 先呼叫既有 `package_windows_zip.ps1`（建置、組裝暫存目錄、隨附 VC DLL、依賴檢查），再用 `package_windows_zip.ps1 -CheckOnly` 對暫存目錄複檢，最後呼叫 `iscc` 編譯 `elinkbook.iss` 並產生 SHA256；（2）`verify_windows_installer.ps1` 在本機做靜默安裝、覆蓋升級、靜默解除安裝的自動驗證；GUI 解除安裝詢問框的「否／是」兩條路徑由使用者人工操作（會刪資料，須先備份）。乾淨機器與 Windows 10 1809 做不到（使用者沒有第二台機器），報告只寫本機結果。

**Tech Stack:** PowerShell 5.1／7、Inno Setup 6（`iscc.exe`，用 `winget` 安裝）、既有 `package_windows_zip.ps1`、`dumpbin`、Windows 內建 `tar`／`robocopy`。

**Spec:** `docs/epics/epic-66-windows-port/issues.md` 的「Issue 27 範圍／過關條件／單元測試要求」；`epic.md` 決策 10、30、32；[ADR 0043](../../../adr/0043-windows-installer-inno-setup-unsigned-per-user.md)。

## 已查證的事實（2026-11-13，計畫階段）

- `package_windows_zip.ps1` 的暫存目錄是 `<OutDir>/stage/elinkbook`（預設 `app/build/windows_zip/stage/elinkbook`）；腳本只在**開頭**清除並重建它（`Remove-Item $stageRootDir` 只出現一次），結束後**保留**，所以安裝程式腳本可以直接使用。`-CheckOnly <目錄>` 對任意目錄跑依賴檢查，通過 exit 0、失敗 exit 1，且要求三個 VC DLL 實體存在於目錄根。
- zip 腳本的版本規則：取 `pubspec.yaml` 的 `version:`（現為 `1.1.0+3`），把 `+` 換成 `-b`，得到 `1.1.0-b3`；檔名 `elinkbook-1.1.0-b3-windows-x64.zip`，SHA256 檔名為 `<zip 檔名>.sha256`，內容 `<大寫雜湊>  <檔名>\n`、UTF-8 無 BOM。
- 暫存目錄含 `elinkbook.exe`、三個 VC DLL、`data\`、`README.txt`；不含 `.pdb`／`.lib`／`.exp`／`.ilk`／`dartjni.dll`。
- App 資料在 `%APPDATA%\cc.ugotit\elinkbook`（zip README 與 Issue 14 驗證腳本已用此路徑）；啟動 `elinkbook.exe` 會寫入該資料夾，所以**任何啟動 App 的驗證都會動到這台機器上的真實資料**。
- 這台機器**沒有** Inno Setup（`where iscc` 找不到、`Program Files (x86)\Inno Setup 6` 不存在），有 `winget`。
- **未查證（實作時第一步就要查，不得當已知）：** `winget` 安裝後 `ISCC.exe` 的實際路徑（machine 或 user scope）；安裝目錄的 `Languages\` 下有沒有 `ChineseTraditional.isl`。

## Global Constraints

- Flutter 3.47.9；`flutter analyze` 乾淨；不新增相依（`pubspec.lock` 不得變動）；**不修改任何 `lib/`、`windows/runner/`、`windows/CMakeLists.txt`**（打包不得改產品行為）。
- 建置與啟動 App 前：先確認沒有殘留的 `elinkbook.exe`／`flutter_tester.exe`／`MSBuild.exe`、測試用 `dart`（保留 `language-server`、`daemon`）；不得與 Windows 整合測試或 Android 建置同時進行；可用記憶體不足 4 GB 就停止並回報（沿用 `package_windows_zip.ps1` 的檢查）。
- 不得 commit：`app/windows/flutter/generated_plugin_registrant.cc`、`generated_plugin_registrant.h`、`generated_plugins.cmake`、`pubspec.lock` 的任何變動；`git add` 一律明確列檔。
- 輸出放 `app/build/windows_installer/`（被 `app/.gitignore` 的 `build/` 忽略）；實驗與備份放 scratchpad，不放進專案。
- 不簽章、不上傳、不建 CI、不碰 GitHub Release（ADR 0043、決策 32）。
- 依使用者安裝到 `%LOCALAPPDATA%\Programs\elinkBook`，不需系統管理員（不跳 UAC）；`AppId` 為固定 GUID，**發佈後不可更改**。
- 解除安裝：詢問框「是否同時刪除書庫與閱讀紀錄」**預設「否」**；`/SILENT`、`/VERYSILENT` 一律不刪 `%APPDATA%\cc.ugotit\elinkbook`。
- 桌面捷徑：安裝時可選、**預設勾選**；開始功能表項目一律建立。
- 安裝程式腳本**失敗時必須以非 0 結束**，不得留下看似成功的舊 setup.exe（開頭先清除同名舊產物）。
- 報告不得外推：只有這台機器、release 版、本機 WebView2；乾淨機器（缺 VC 執行階段與 WebView2）、Windows 10 1809、SmartScreen 實際行為、他人電腦一律寫「未驗證」。
- **會改動這台機器或動到使用者資料的步驟（`winget install`、GUI 解除安裝選「是」）執行前必須向使用者確認；測「刪除資料」之前必須先備份並驗證備份。**

## Review Focus

1. 固定 `AppId` 是覆蓋升級的唯一條件：只驗「裝兩次沒壞」不夠，要用不同 `AppId` 再裝一次，證明會變成兩份並存，才算證明 `AppId` 真的在起作用。（Task 3）
2. 靜默解除安裝絕不能刪資料：腳本要比對解除安裝前後 `%APPDATA%\cc.ugotit\elinkbook` 的檔案清單完全相同，不能只看資料夾還在。（Task 3）
3. App 執行中覆蓋升級：舊行程必須被關閉、新版檔案真的取代舊版（比對 exe 的檔案版本），且不能留下兩個解除安裝項目。（Task 3）
4. 路徑含空格與中文（`/DIR` 指到「含 空格 與 中文」）：`.iss` 的路徑、捷徑目標、解除安裝項目都要正確。（Task 3）
5. 桌面捷徑兩條路徑：預設（勾選）會建立、取消勾選（`/TASKS="!desktopicon"`）不會建立；兩者都要實測，否則「預設勾選」只是文件上的說法。（Task 3）
6. 打包來源過期：只用 `-StageDir` 或 `-SkipBuild` 時，暫存目錄可能是舊版；腳本須在輸出明確印出所用暫存目錄與其中 `elinkbook.exe` 的檔案版本，並永遠先對該目錄跑 `-CheckOnly`。（Task 1）

---

### Task 1：安裝程式腳本與 `.iss`（編譯、複檢、SHA256）

**Files:**
- Create: `app/windows/packaging/elinkbook.iss`
- Create: `app/tool/package_windows_installer.ps1`
- Modify: `app/tool/README.md`（補一小節，格式比照 `package_windows_zip.ps1` 小節）

**Interfaces:**
- Consumes: `package_windows_zip.ps1 [-SkipBuild] [-OutDir <路徑>]`（成功 exit 0，暫存目錄在 `<OutDir>/stage/elinkbook`）；`package_windows_zip.ps1 -CheckOnly <目錄>`（exit 0／1）。
- Produces: `powershell -File tool/package_windows_installer.ps1 [-SkipBuild] [-StageDir <目錄>] [-Version <字串>] [-OutDir build/windows_installer]`
  - 預設流程：先呼叫 zip 腳本（`-SkipBuild` 原樣轉傳）取得 `build/windows_zip/stage/elinkbook`；給 `-StageDir` 時**不**呼叫 zip 腳本，直接用該目錄（供變異驗證與除錯）。
  - `-Version`：格式同 `pubspec.yaml` 的 `version:`（例如 `1.0.9+1`），預設讀 `pubspec.yaml`；只為了覆蓋升級驗證能產出兩個不同版本。
  - 結束碼 0＝成功；輸出 `<OutDir>/elinkbook-<版本把 + 換成 -b>-windows-x64-setup.exe` 與 `<同檔名>.sha256`（格式與 zip 的 `.sha256` 相同）。
  - `.iss` 接收的 `iscc /D` 定義：`AppVersion`（如 `1.1.0`）、`VersionInfoVersion`（如 `1.1.0.3`，四段數字）、`StageDir`、`OutputDir`、`OutputBaseFilename`、可選的 `AppIdOverride`（只給變異驗證用，未給則使用固定 GUID）。

- [x] **Step 1: 向使用者確認後安裝 Inno Setup。** 執行 `winget install --id JRSoftware.InnoSetup -e`（會改動這台機器，先問）。完成後實測並記錄：`ISCC.exe` 的實際路徑、是否需要重開終端機才找得到、`Languages\` 資料夾內有沒有 `ChineseTraditional.isl`。
- [x] **Step 2: 決定安裝程式的介面語言（決策閘門）。** 若 Step 1 找到 `ChineseTraditional.isl`，`.iss` 的 `[Languages]` 直接使用它。**若沒有，停下來回報使用者決定**：（A）自帶一份繁體中文翻譯檔進 `app/windows/packaging/`（須先確認其授權）、（B）預設英文介面，只把本專案自訂的訊息（桌面捷徑名稱、解除安裝詢問框）寫成繁體中文。不得自行挑一個。
- [x] **Step 3: 產生固定 `AppId`。** 以 PowerShell `[guid]::NewGuid()` 產生一次，寫進 `elinkbook.iss`，並在該行上方用註解寫明「發佈後不可更改，改了就無法覆蓋升級（ADR 0043）」。同時把這個 GUID 記入本計畫的「實作記錄」小節（Task 4 補），方便日後核對。**花括號跳脫：** Inno Setup 把 `{` 當常數起始，`AppId` 的**開頭花括號必須雙寫**（寫成 `{{GUID}` 才會得到 `{GUID}`；結尾的 `}` 單寫即可）。經 `AppIdOverride` 以 `/D` 傳入時同樣要帶雙寫的開頭花括號，PowerShell 呼叫時整個參數用引號包住。審查報告（review-plan-issue-27 I-3）主張結尾也要雙寫，這點**不採納為已知結論**，改以實測為準：Task 3 檢查項 1 會讀出實際登錄機碼名稱，必須是單花括號的 `{GUID}_is1`，不是就回頭修正 `.iss`。
- [x] **Step 4: 寫 `elinkbook.iss`。** 只含本 Issue 範圍內的設定，具體值如下：`PrivilegesRequired=lowest`；`DefaultDirName={localappdata}\Programs\elinkBook`；`DefaultGroupName=elinkBook`；`ArchitecturesAllowed=x64compatible` 與 `ArchitecturesInstallIn64BitMode=x64compatible`；`MinVersion=10.0.17763`；`CloseApplications=yes`、`RestartApplications=no`；`SetupIconFile` 指向 `..\runner\resources\app_icon.ico`；`UninstallDisplayIcon={app}\elinkbook.exe`；`Compression=lzma2`、`SolidCompression=yes`；`[Files]` 以 `Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs` 遞迴複製（缺 `recursesubdirs createallsubdirs` 會漏掉 `data\` 整個子目錄，App 就打不開書）；`[Icons]` 建開始功能表項目，另建桌面捷徑，後者掛在 `[Tasks]` 的 `desktopicon` 且**不加 `unchecked` 旗標**（預設勾選）。不加「安裝完成後啟動」、不加 `[UninstallDelete]`、不加任何自動更新或遙測（YAGNI）。
- [x] **Step 5: 寫 `package_windows_installer.ps1`。** 行為依序：（a）解析 `app/` 基底路徑與版本（`-Version` 或 `pubspec.yaml`；`AppVersion` 取 `+` 之前、`VersionInfoVersion` 取 `+` 之前加 `.` 與 `+` 之後的數字，沒有 `+` 時補 `.0`）；（b）開頭清除同名舊 setup.exe 與 `.sha256`；（c）找 `ISCC.exe`（用 Step 1 查到的路徑做第一候選，再試 `%LOCALAPPDATA%\Programs\Inno Setup 6`、`${env:ProgramFiles(x86)}\Inno Setup 6`、`PATH`），都找不到就以非 0 結束並印出 `winget install` 指令；（d）沒給 `-StageDir` 就呼叫 zip 腳本；（e）對暫存目錄跑 `package_windows_zip.ps1 -CheckOnly`，失敗即中止；（f）印出所用暫存目錄與 `elinkbook.exe` 的檔案版本；（g）呼叫 `iscc` 並檢查 exit code 與輸出檔存在；（h）寫 `.sha256`。
- [x] **Step 6: 實跑並驗證輸出。** `powershell -ExecutionPolicy Bypass -File tool/package_windows_installer.ps1`（完整流程，含建置）。預期：exit 0；`app/build/windows_installer/` 下有 setup.exe 與 `.sha256`；`.sha256` 內雜湊用 `Get-FileHash` 重算一致；檔名版本部分與 `pubspec.yaml` 一致。把完整輸出貼進報告。
- [x] **Step 7: 變異驗證（a）：缺 VC DLL 必須失敗。** 把暫存目錄複製到 scratchpad、刪掉 `vcruntime140_1.dll`，用 `-StageDir` 指向它執行：預期 exit 非 0、訊息指出缺該 DLL、**沒有**產出 setup.exe。驗完刪除複本。
- [x] **Step 8: 查 VC 可轉散發授權（對外發佈新增的風險）。** Issue 14 把「自用階段不構成問題，對外發佈需再確認」列為風險；本 Issue 就是對外發佈。在 Visual Studio 安裝目錄下找 `REDIST.TXT`（或可轉散發清單），確認 `msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll` 被列為可散布檔案，把路徑與原文片段記進報告；**找不到或不在清單內就停下回報使用者**，不要自行判斷。
- [x] **Step 9: 補 `app/tool/README.md` 小節並 commit。**

```bash
git add app/windows/packaging/elinkbook.iss app/tool/package_windows_installer.ps1 app/tool/README.md
git commit -m "feat(windows): Inno Setup 安裝程式打包腳本（epic-66 Issue 27 Task 1）"
```

---

### Task 2：解除安裝詢問框與說明文件

**Files:**
- Modify: `app/windows/packaging/elinkbook.iss`（新增 `[Code]` 區段）
- Modify: `app/windows/packaging/README.txt`

**Interfaces:**
- Consumes: Task 1 的 `elinkbook.iss`。
- Produces: 解除安裝行為——互動模式在解除完成後跳「是否同時刪除書庫與閱讀紀錄？」，預設按鈕為「否」；選「是」才刪除 `{userappdata}\cc.ugotit\elinkbook`（含子資料夾）；`UninstallSilent`（`/SILENT`、`/VERYSILENT`）為真時完全不跳框、不刪。

- [x] **Step 1: 在 `.iss` 加 `CurUninstallStepChanged(CurUninstallStep: TUninstallStep)`。** 只處理 `usPostUninstall`；`UninstallSilent` 為真就直接返回；否則 `MsgBox` 使用 `mbConfirmation`、`MB_YESNO or MB_DEFBUTTON2`（預設「否」），回傳 `IDYES` 才呼叫 `DelTree(ExpandConstant('{userappdata}\cc.ugotit\elinkbook'), True, True, True)`。訊息文字依 Task 1 Step 2 的語言決定，內容要寫明資料夾位置與「刪除後無法復原」。
- [x] **Step 2: 編譯確認語法。** 重跑 `package_windows_installer.ps1 -SkipBuild`，預期 exit 0。行為驗證在 Task 3（靜默）與 Task 4（GUI）。
- [x] **Step 3: 改 `README.txt`。** 新增「安裝版」章節，包含：安裝位置與不需管理員；SmartScreen 提示（沿用現有「未簽章」章節，不重複全文）；資料位置 `%APPDATA%\cc.ugotit\elinkbook`；解除安裝時的詢問框與預設「否」、靜默解除安裝不刪資料；**zip 版與安裝版共用同一份資料，不要同時開兩份**；從 zip 版轉成安裝版不需先刪 zip 版。同時把現有第四節裡「開源／自用免安裝發佈」的「自用」字樣改成不再自稱自用（Windows 版已改為對外發佈）。README 維持正體中文。
- [x] **Step 4: Commit。**

```bash
git add app/windows/packaging/elinkbook.iss app/windows/packaging/README.txt
git commit -m "feat(windows): 解除安裝可選擇是否刪除 App 資料，補安裝版說明（epic-66 Issue 27 Task 2）"
```

---

### Task 3：本機自動驗證腳本（靜默安裝、覆蓋升級、靜默解除安裝）

**Files:**
- Create: `app/tool/verify_windows_installer.ps1`
- Modify: `app/tool/README.md`（補一小節）

**Interfaces:**
- Consumes: Task 1 的 setup.exe；`package_windows_installer.ps1 -StageDir ... -Version ...`（用來產出較舊版本的 setup.exe）；既有 `verify_windows_zip.ps1` 的主視窗偵測做法（視窗類別 `FLUTTER_RUNNER_WIN32_WINDOW`；啟動小視窗類別 `ELINKBOOK_SPLASH`）——**從該檔複製所需的最小函式，不重構 zip 驗證腳本**。
- Produces: `powershell -File tool/verify_windows_installer.ps1 -Setup <setup.exe> -OlderSetup <較舊版本 setup.exe> [-WorkDir <目錄>]`；每項檢查輸出一行 `[通過]／[失敗] 名稱 :: 說明`，結束碼 0＝全部通過。**腳本內任何一步都不得刪除 `%APPDATA%\cc.ugotit\elinkbook`**。

- [x] **Step 0: 備份並驗證備份（本 Task 任何步驟啟動 App 之前；使用者同意後執行）。** 本 Task 的檢查項 4、5 會啟動 `elinkbook.exe`，會寫入這台機器上真實的 `%APPDATA%\cc.ugotit\elinkbook`，所以備份必須排在這之前（審查 I-1）。執行 `robocopy "$env:APPDATA\cc.ugotit\elinkbook" <scratchpad>\appdata-backup /MIR`；**robocopy 結束碼 0～7 都代表成功（1 表示有複製檔案），8 以上才是失敗**，不要用 `$LASTEXITCODE -ne 0` 判斷。再比對來源與備份的檔案數與總大小一致；不一致就不得進行下一步。備份在 Task 4 結束、使用者確認書庫完整之前一律保留。
- [x] **Step 1: 寫腳本。** 開跑前沿用殘留行程與記憶體檢查（只檢查不終止），並確認目前行程**不是**以系統管理員身分執行（是的話失敗，因為要驗證「不需要管理員」）。安裝目標用 `<WorkDir>\含 空格 與 中文\app`（預設 `$env:TEMP` 下），開跑前若已存在且非本腳本產生就拒絕。檢查項（每項各自輸出一行）：
  1. 靜默安裝（`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="..." /LOG=...`）exit 0、不跳 UAC；`HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\` 下出現該 `AppId` 的項目、`HKLM` 下沒有。Inno Setup 登錄的機碼名稱會在 `AppId` 後加 `_is1`（預期為 `{GUID}_is1`），比對時用 `AppId + "_is1"`，並把實際讀到的機碼名稱印出來（這也是驗證 `.iss` 的花括號跳脫是否正確）。
  2. 安裝目錄內容：有 `elinkbook.exe`、三個 VC DLL、`data\foliate\main.js`、`README.txt`；沒有 `.pdb`／`.lib`／`.exp`／`.ilk`。
  3. 開始功能表項目存在（`{autoprograms}` 下的 elinkBook 捷徑），桌面捷徑**預設存在**。
  4. 啟動 `elinkbook.exe`（`Start-Process -WorkingDirectory` 明確指定）：主視窗出現、行程存活 20 秒；再結束行程樹。
  5. **覆蓋升級（執行中）：** 先用 `-OlderSetup` 靜默安裝並啟動 App，保持執行，再靜默安裝 `-Setup` 到同一目錄：舊行程被關閉、`elinkbook.exe` 檔案版本變成新版、`Uninstall` 下仍只有**一個**該 `AppId` 項目、`DisplayVersion` 為新版。
  6. **資料保護：** 升級前後與解除安裝前後，`%APPDATA%\cc.ugotit\elinkbook` 的檔案清單（路徑加大小）逐項比對；升級與靜默解除安裝不得造成任何**既有檔案**消失（啟動 App 可能新增或改寫檔案，所以比對「升級前存在的檔案仍存在」，不要求完全相同）。
  7. **靜默解除安裝（`/VERYSILENT`）：** 呼叫解除安裝程式，exit 0。**Inno 的解除安裝程式會把自己複製到 `%TEMP%` 再啟動並讓原行程立刻結束，所以 `Start-Process -Wait` 返回時檔案還沒刪完（審查 I-2）；腳本必須改為輪詢**：每 0.5 秒檢查一次，最長等 30 秒，等到「安裝目錄的 `elinkbook.exe` 消失且 `Uninstall` 項目消失」才往下；逾時才判失敗。實作時用實測確認這個行為（記錄解除安裝實際花了幾秒）。輪詢結束後再檢查：安裝目錄的程式檔被移除、`Uninstall` 項目消失、開始功能表與桌面捷徑消失；**第 6 項的資料保護比對通過**。
  8. **桌面捷徑取消勾選：** 以 `/TASKS="!desktopicon"` 再裝一次：桌面捷徑**不存在**、開始功能表項目存在；之後靜默解除安裝收尾。
  9. 結束時檢查沒有殘留 `elinkbook.exe`／`msedgewebview2.exe` 子行程、安裝目錄已清除。
- [x] **Step 2: 產出「較舊版本」setup.exe。** 用 Task 1 的暫存目錄、`-StageDir` 與 `-Version 1.0.9+1`、`-OutDir` 指到 scratchpad，產出一個較舊版本的 setup.exe（內容相同、只有版本不同）。
- [x] **Step 3: 實跑。** 預期 9 項全部 `[通過]`、exit 0。完整輸出貼進報告。
- [x] **Step 4: 變異驗證（b）：`AppId` 不固定就會並存。** 在 scratchpad 直接用 `iscc /DAppIdOverride={另一個新 GUID} ...` 編出一個與 Task 1 產物**僅 `AppId` 不同**的較新版 setup.exe，先裝 `-OlderSetup`、再裝這個 setup：預期 `Uninstall` 下出現**兩個**項目（並存）。接著對照 Step 3 的結果（同一 `AppId` 只有一個項目）。驗完把兩份都靜默解除安裝，確認清乾淨：第二份安裝到同一目錄時，解除安裝程式很可能被命名為 `unins001.exe`（審查 M-3，未實測），所以清理時**逐一讀取兩個登錄項的 `QuietUninstallString` 各自執行**，同樣用輪詢等到兩個項目與安裝目錄都消失，不要寫死 `unins000.exe`。
- [x] **Step 5: 驗證檢查本身有效。** 對第 6 項做一次負向驗證：暫時在腳本中安裝後、解除安裝前，人為刪掉 `%APPDATA%\cc.ugotit\elinkbook` 下一個**複本資料夾裡**的檔案（不要動真實資料夾；做法是讓腳本的「資料夾位置」可由內部變數指向 scratchpad 內的假資料夾），預期第 6 項 `[失敗]`；驗完還原腳本。
- [x] **Step 6: 補 README 小節並 commit。**

```bash
git add app/tool/verify_windows_installer.ps1 app/tool/README.md
git commit -m "test(windows): 安裝程式本機驗證腳本（靜默安裝、覆蓋升級、靜默解除安裝、AppId 變異驗證）（epic-66 Issue 27 Task 3）"
```

---

### Task 4：人工驗證、報告與文件

**Files:**
- Create: `docs/epics/epic-66-windows-port/issue-27-report.md`
- Modify: `docs/epics/epic-66-windows-port/issues.md`（Issue 27 狀態）、`docs/epics/epic-66-windows-port/epic.md`（決策 32 補實作結果）、`docs/epics.md`（備註）、本檔（勾選步驟、補「實作記錄」小節）

- [x] **Step 1: 確認 Task 3 Step 0 的備份仍在且完整。** 比對備份的檔案數與總大小仍與當時記錄一致；**不要重新備份**（Task 3 已啟動過 App，重新備份可能把受影響的狀態當成基準）。備份不見或不一致就停下回報使用者。GUI 驗證前請使用者先關閉所有 elinkBook 視窗。
- [x] **Step 2: 人工 GUI 驗證（使用者操作，兩輪；實際在另一台電腦進行，因為這台機器上安裝版畫面空白、根因未查明，見報告第 6 節）。** 請使用者：（i）雙擊 setup.exe 走完安裝精靈（確認不跳 UAC、桌面捷徑選項預設已勾選），開一本 EPUB 並回報；（ii）從「設定 → 應用程式」解除安裝，詢問框選「否」，確認程式移除但資料夾與書庫保留；（iii）重新安裝，再解除安裝，這次選「是」，確認 `%APPDATA%\cc.ugotit\elinkbook` 被刪除。每一輪結果照使用者回報原文記入報告，不外推成逐項驗證。
- [x] **Step 3: 還原資料並驗證。** 以 `robocopy <scratchpad>\appdata-backup "$env:APPDATA\cc.ugotit\elinkbook" /MIR` 還原（結束碼 0～7 皆成功，8 以上才失敗；還原會把資料回到 Task 3 備份當時的狀態，Task 3 之後到現在在 App 內新增的閱讀進度會回復，先告知使用者），比對檔案數與總大小與 Task 3 Step 0 記錄一致，並請使用者開 App 確認書庫完整。**確認完整前不得刪除備份。**（未執行：「選是」刪資料的測試改由使用者在另一台電腦做，這台機器沒有刪資料，不需還原；備份保留至使用者確認，見報告第 6 節。）
- [x] **Step 4: 全套 `flutter analyze` 與 `flutter test`。** 本 Issue 不動 Dart 檔，`flutter analyze` 仍須乾淨；發 PR 前跑一次完整 `flutter test`，既有偶發失敗照實記錄，不修。
- [x] **Step 5: 寫 `issue-27-report.md`。** 內容：已查證事實與來源、Task 1～3 腳本實際輸出、兩次變異驗證輸出、REDIST 授權查證結果、人工 GUI 驗證原文、資料備份與還原記錄、「未驗證」清單（乾淨機器缺 VC 執行階段與 WebView2、Windows 10 1809、SmartScreen 實際行為、他人電腦）。固定 `AppId` 的 GUID 一併記錄。
- [x] **Step 6: 更新文件並勾選本檔步驟。** `issues.md` Issue 27 狀態改為已合併前的實際狀態（不預先寫 PR 編號）；`epic.md` 決策 32 補實作結果與語言決定；`docs/epics.md` 備註維持精簡。
- [x] **Step 7: Commit。**

```bash
git add docs/epics/epic-66-windows-port/issue-27-report.md docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/epic.md docs/epics.md docs/epics/epic-66-windows-port/plans/plan-issue-27.md
git commit -m "docs(epic-66): Issue 27 安裝程式報告與文件（Task 4）"
```

---

## 已知風險

- 本機驗證**證明不了**「乾淨機器能裝、能開」：這台機器有 VS Build Tools、VC 執行階段與 WebView2。依賴檢查只證明隨附清單齊全。
- 未簽章：安裝程式與 zip 一樣會觸發 SmartScreen；README 只能說明（ADR 0043）。
- Inno Setup 的繁體中文介面是否現成可用未查證；找不到時要使用者決定（Task 1 Step 2）。
- `AppId` 一旦隨 Release 發出就不可更改；Task 4 的報告記錄它，之後任何改動都要視為破壞性變更。
- GUI 解除安裝選「是」會真的刪資料；已用備份、備份驗證、還原驗證三道步驟保護，且每一步動手前都要使用者同意。
- `flutter build windows` 會改動 `generated_plugin*` 三個檔，容易誤 commit；每次 `git add` 明確列檔。

## 實作記錄

- AppId：`{C4E48E89-6F1B-4B77-94B9-23BCE3FCC757}`（發佈後不可更改）。
- 介面語言：Inno Setup 6.7.3 沒附繁體中文，經使用者決定自帶官方儲存庫 main 的 `ChineseTraditional.isl`（原封複製）。
- 開始功能表改用 `{autoprograms}\elinkBook` 加 `DisableProgramGroupPage=yes`，不設 `DefaultGroupName`，避免多一層同名資料夾。
- 驗證檢查 6 排除 WebView2 的 `lockfile`（只在 App 執行期間存在）。
- 計畫外新增：`package_windows_zip.ps1` 建置前清 `build/flutter_assets`、依賴檢查擋 assets 下字型與 `data/flutter_assets/test`（使用者在另一台電腦發現字型與測試 fixtures 被打包）。
- 其餘決定與數據見 `issue-27-report.md`。
- 更正（獨立審查後，2026-11-13）：上方 Task 2、Task 4 與過關條件把詢問框寫成「刪書庫與閱讀紀錄」是錯的——書庫 `library.db`、`covers`、`imported_books` 在使用者的「文件」資料夾，`%APPDATA%\cc.ugotit\elinkbook` 只有 WebView2、已下載字型、字典來源。實作已改為如實告知（選「是」只刪設定與下載資料），並登記 Issue 29 把資料收進上層目錄 `elinkbook`。審查補強的驗證見 `issue-27-report.md` 第 8 節；新增 `InitializeUninstall`（App 執行中拒絕解除安裝）。
- 再更正（2026-11-13）：使用者改變決定——解除安裝選「是」要連書庫一併刪除。已實作（`elinkbook.iss` 以固定名稱清單刪除「文件」資料夾內的書庫、字典庫、封面、匯入的書複本等），並以新腳本 `verify_windows_uninstall_data.ps1` 在假資料夾驗證；見 `issue-27-report.md` 第 9 節。
