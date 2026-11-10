# Issue 14：Windows 免安裝 zip 打包 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一支腳本把 Windows release 版打成免安裝 zip（含 VC++ 執行階段 DLL、README、SHA256），解壓到任何位置（含空格、中文、唯讀資料夾）雙擊 `elinkbook.exe` 就能用。先自用：不簽章、不做 MSIX、不上傳（epic 決策 10）。

**Architecture:** 不改產品程式。三支 PowerShell 腳本加一份 README 範本：
（1）`package_windows_zip.ps1`：建置 → 暫存目錄組裝 → 複製 VC DLL → 依賴靜態檢查 → 壓成 zip → SHA256；
（2）依賴靜態檢查（同檔的函式，也可單獨呼叫）：用 `dumpbin /dependents` 證明「非系統 DLL 的依賴都在目錄內」；
（3）`verify_windows_zip.ps1`：解壓到含空格與中文的唯讀資料夾、啟動、確認行程存活與主視窗、確認沒有寫入解壓資料夾。
再加一個人工步驟（使用者開書）。乾淨機器驗證做不到（使用者沒有第二台機器，2026-11-10），報告只寫本機結果。

**Tech Stack:** PowerShell 5.1／7、`flutter build windows --release`、`dumpbin`（VS Build Tools）、`vswhere`、`tar`（Windows 內建 bsdtar，用來壓 zip）。

**Spec:** `docs/epics/epic-66-windows-port/issues.md` 的「Issue 14 範圍／過關條件／單元測試要求」；`epic.md` 決策 4、10、23、28。

## 已查證的事實（2026-11-10，計畫階段；實作前不得當成已知結論以外的事）

- `dumpbin /dependents` 顯示 `elinkbook.exe`、`flutter_inappwebview_windows_plugin.dll`、`flutter_secure_storage_windows_plugin.dll` 依賴 `MSVCP140.dll`、`VCRUNTIME140.dll`、`VCRUNTIME140_1.dll`，另有 `api-ms-win-crt-*`（Windows 10 內建的 UCRT API 集，不需隨附）。`flutter_windows.dll`、`pdfium.dll`、`sqlite3.dll`、`Webview2Loader.dll` 沒有列出 VC 執行階段依賴。
- 三個 VC DLL 的來源：`C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT\`（這台機器；另有 `Tools\MSVC\14.44.35207` 為編譯器版本，兩者版本號不同，**以 Redist 目錄為準**）。
- 現有 `app/build/windows/x64/runner/Release` 是 2026-11-05 的舊輸出（缺 `desktop_drop`、`window_manager` 外掛），**不可直接使用，必須重新建置**。
- `data\foliate\main.js` 已由 CMake 放進輸出（epic 決策 17 已完成）。
- WebView2 使用者資料夾已指定到 `getApplicationSupportDirectory()`（`main.dart:500`）。`Runner.rc` 的 `CompanyName` 是 `cc.ugotit`、`ProductName` 是 `elinkbook`，預期資料夾為 `%APPDATA%\cc.ugotit\elinkbook`，**實作時以實測為準**。
- `pubspec.yaml` 版本是 `1.1.0+3`。
- 使用者決定：VC DLL **打包進 zip**；乾淨機器只在本機驗證。

## Global Constraints

- Flutter 3.47.9；`flutter analyze` 乾淨；不新增相依（`pubspec.lock` 不得變動）；**不修改任何 `lib/`、`windows/` 下的檔案**（打包不得改產品行為）。
- 建置時：先確認沒有殘留的 `elinkbook.exe`／`flutter_tester.exe`／`MSBuild.exe`、測試用 `dart`（保留 `language-server`、`daemon`）；不得與 Windows 整合測試或 Android 建置同時進行；可用記憶體不足 4 GB 就停止並回報（2026-11-09、2026-11-10 兩次因記憶體不足被系統中止）。若建置失敗在繁中字碼頁警告（C4819），先確認 `windows/CMakeLists.txt` 的 `/utf-8` 是否生效，再暫時設 `CL=/utf-8`（Git Bash 要加 `MSYS_NO_PATHCONV=1`）。
- 不得 commit：`app/windows/flutter/generated_plugin_registrant.cc`、`generated_plugin_registrant.h`、`generated_plugins.cmake`、`pubspec.lock` 的任何變動（`flutter build` 會改動它們）；`git add` 一律明確列檔。
- zip 與暫存輸出放 `app/build/windows_zip/`（已被 `app/.gitignore` 的 `build/` 忽略）；實驗輸出放 scratchpad，不放進專案。
- 不簽章、不上傳、不碰 GitHub Release（Android 的 5 檔含 `SHA256SUMS` 流程與本 Issue 無關）。
- 報告不得外推：只有本機、release 版、本機 WebView2；乾淨機器（缺 VC 執行階段）、Windows 10 1809、SmartScreen 實際行為、他人電腦一律寫「未驗證」。
- 打包腳本**失敗時必須以非 0 結束並留下明確訊息**，不得產出看似成功的半成品 zip（先寫到暫存名，全部檢查通過才改成正式檔名）。

## Review Focus

1. 依賴靜態檢查必須真的證明「VC DLL 不能缺」：只靠「檔案在 System32 就算通過」會在這台機器上永遠通過，所以三個 VC DLL 必須**明確要求在目錄內**，並以移除一個 DLL 的變異驗證證明會失敗。（Task 2）
2. zip 路徑分隔符必須是 `/`：Windows PowerShell 5.1 的 `Compress-Archive` 會產生反斜線路徑，部分解壓工具會壞；本計畫用 `tar -a` 並驗證清單。（Task 1）
3. 「解壓資料夾沒被寫入」的判斷必須比對執行前後的檔案清單（含大小與時間），不能只看「啟動成功」。唯讀要用 ACL 實際拒絕寫入，不是只設唯讀屬性（資料夾的唯讀屬性不會阻擋寫入）。（Task 4）
4. 版本號與檔名：zip 檔名的版本取自 `pubspec.yaml`，不可寫死；`+` 在檔名裡要處理。（Task 1）
5. 報告必須誠實：本機有 VS Build Tools、VC 執行階段與 WebView2，驗證不到「乾淨機器能不能開」；不得以「依賴檢查通過」代替。（Task 5）
6. 失敗路徑：建置失敗、找不到 Redist、zip 工具失敗時，腳本要以非 0 結束且不留下正式檔名的 zip。（Task 1）

---

### Task 1：打包腳本（建置、組裝、VC DLL、壓縮、SHA256）

**Files:**
- Create: `app/tool/package_windows_zip.ps1`
- Create: `app/windows/packaging/README.txt`（Task 3 內容；本 Task 先放最小佔位文字讓腳本能跑）
- Modify: `app/tool/README.md`（補一小節）

**Interfaces:**
- Produces: `powershell -File tool/package_windows_zip.ps1 [-SkipBuild] [-OutDir build/windows_zip]`；結束碼 0＝成功。成功時輸出 `build/windows_zip/elinkbook-<版本>-windows-x64.zip` 與同名 `.sha256`，並在結尾印出檔案清單筆數與 zip 大小。

- [ ] **Step 1: 寫腳本（暫存名到正式名）。** 行為：（a）路徑一律以 `$PSScriptRoot` 為基準（在倉庫根或 `app/` 執行都指向 `app/`）；（b）讀 `pubspec.yaml` 的 `version:`（例如 `1.1.0+3`），檔名版本把 `+` 換成 `-b`（`1.1.0-b3`），避免 `+` 在 URL、部分工具的問題；（c）開跑前檢查殘留行程與可用記憶體（同 `run_windows_smoke.ps1` 的規則，**只檢查不終止**）；（d）除非 `-SkipBuild`，否則在 `app/` 執行 `flutter build windows --release`，非 0 即中止；（e）清空並建立暫存目錄 `build/windows_zip/stage/elinkbook/`，複製 `build\windows\x64\runner\Release\*` 全部內容，排除 `*.pdb`、`*.lib`、`*.exp`、`*.ilk`；（f）用 `vswhere -latest -products * -property installationPath` 找 VS，讀 `VC\Auxiliary\Build\Microsoft.VCRedistVersion.default.txt` 取得 Redist 版本，從 `VC\Redist\MSVC\<版本>\x64\Microsoft.VC143.CRT\` 複製 `msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll` 到暫存目錄根（與 `elinkbook.exe` 同層）；找不到任何一個就中止；（g）複製 `windows/packaging/README.txt` 到暫存目錄根；（h）用 `tar -a -c -f <暫存名>.zip -C build/windows_zip/stage elinkbook`（Windows 內建 bsdtar；**不用 `Compress-Archive`**，其在 Windows PowerShell 5.1 會寫出反斜線路徑）；（i）驗證 zip 清單：用 `tar -tf` 列出，必須含 `elinkbook/elinkbook.exe`、三個 VC DLL、`elinkbook/data/foliate/main.js`、`elinkbook/README.txt`，且**不含**反斜線與 `.pdb`；（j）全部通過才把暫存名改為正式檔名、用 `Get-FileHash -Algorithm SHA256` 寫 `.sha256`（格式 `<雜湊>  <檔名>`）；任何一步失敗以非 0 結束，並刪除暫存 zip。
- [ ] **Step 2: 驗證腳本本身。** 實際執行：（1）正常打包一次，預期結束碼 0、產出 zip 與 `.sha256`、清單驗證通過；（2）暫時把 `-OutDir` 指到不存在的深層目錄，預期自動建立；（3）人為讓 Redist 找不到（例如暫時改腳本讀取的版本檔名為不存在的檔，驗證完還原），預期以非 0 結束且 `build/windows_zip/` 沒有正式檔名的 zip；（4）同一提交連續打包兩次，比較兩份 `tar -tf` 清單，預期一致。以這四個實際輸出為證，記入報告。
- [ ] **Step 3: `app/tool/README.md` 補說明；`flutter analyze` 不涉及（無 Dart 變動）。**
- [ ] **Step 4: Commit。**

```bash
git add app/tool/package_windows_zip.ps1 app/windows/packaging/README.txt app/tool/README.md
git commit -m "build(windows): 免安裝 zip 打包腳本（建置、VC 執行階段、README、SHA256）（epic-66 Issue 14 Task 1）"
```

---

### Task 2：依賴靜態檢查與變異驗證

**Files:**
- Modify: `app/tool/package_windows_zip.ps1`（新增 `Test-StagedDependencies` 函式，並在壓縮前呼叫；支援 `-CheckOnly <目錄>` 單獨檢查任一目錄）

**Interfaces:**
- Produces: `powershell -File tool/package_windows_zip.ps1 -CheckOnly <目錄>`；結束碼 0＝通過；失敗時列出「檔案 → 缺少的依賴」。

- [ ] **Step 1: 寫檢查。** 對目錄內每個 `.exe`／`.dll` 執行 `dumpbin /dependents`（以 `vswhere` 找到的 VS 路徑下 `VC\Tools\MSVC\<編譯器版本>\bin\Hostx64\x64\dumpbin.exe`；在 Git Bash 呼叫需設 `MSYS_NO_PATHCONV=1`，在 PowerShell 不受影響），解析依賴名稱（不分大小寫）。判定：（a）依賴名稱以 `api-ms-win-` 開頭，視為 Windows 內建；（b）依賴在同一目錄內，通過；（c）依賴存在於 `%SystemRoot%\System32`，視為系統 DLL；（d）**例外：`msvcp140*.dll`、`vcruntime140*.dll`、`concrt140.dll`、`vccorlib140.dll` 即使在 System32 也必須在目錄內**（這台機器 System32 有它們，不加這條永遠通過）；（e）其他找不到的依賴一律失敗。`dumpbin` 本身失敗要視為檢查失敗，不得當作「沒有依賴」。
- [ ] **Step 2: 變異驗證（必做）。** 在暫存目錄副本上：（1）原樣檢查，預期通過；（2）刪除 `vcruntime140_1.dll`，預期失敗並列出 `elinkbook.exe → VCRUNTIME140_1.dll`；（3）刪除 `msvcp140.dll`，預期失敗；（4）還原後預期通過。附上四個實際輸出。
- [ ] **Step 3: 把「依賴檢查通過」限制寫進報告**：它只證明「檔案依賴在目錄內」，**不證明乾淨機器能開**（還有 WebView2、顯示驅動、Windows 版本等因素）。
- [ ] **Step 4: Commit。**

```bash
git add app/tool/package_windows_zip.ps1
git commit -m "build(windows): 打包前依賴靜態檢查（VC 執行階段必須隨附）（epic-66 Issue 14 Task 2）"
```

---

### Task 3：README 範本（正體中文）

**Files:**
- Modify: `app/windows/packaging/README.txt`

- [ ] **Step 1: 先確認要寫的事實。** 資料存放位置：在本機啟動一次 release 版，查 `%APPDATA%` 下實際建立的資料夾名稱（預期 `cc.ugotit\elinkbook`，以實測為準，不照抄預期）；WebView2 的資料夾位置同理。
- [ ] **Step 2: 寫 README。** 內容只寫已查證或決策已定的事：（a）系統需求：Windows 10 1809 以上、WebView2 Runtime（未安裝時 App 會顯示說明與下載連結，epic 決策 4；「Windows 10 1809 實測」寫「未驗證」）；（b）使用方式：解壓到任何資料夾，雙擊 `elinkbook.exe`，不需要安裝、不需要系統管理員權限；（c）資料存放位置（Step 1 實測值）、刪除資料夾不會刪書籍檔案與資料、要完整移除請另外刪資料資料夾；（d）未簽章：Windows SmartScreen 可能出現「已保護您的電腦」，點「其他資訊 → 仍要執行」；若從網路下載，建議先對 zip 按右鍵 → 內容 → 勾選「解除封鎖」再解壓；（e）已知限制：雲端匯入（Google Drive／OneDrive）、音量鍵翻頁、E-Ink 模式、螢幕方向鎖定在 Windows 版不提供（epic 決策 1）；（f）版本與 SHA256 的查驗方式（`Get-FileHash`）。
- [ ] **Step 3: Commit。**

```bash
git add app/windows/packaging/README.txt
git commit -m "docs(windows): 免安裝 zip README（epic-66 Issue 14 Task 3）"
```

---

### Task 4：本機驗證腳本（解壓到含空格與中文的唯讀資料夾後啟動）

**Files:**
- Create: `app/tool/verify_windows_zip.ps1`

**Interfaces:**
- Produces: `powershell -File tool/verify_windows_zip.ps1 -Zip <zip 路徑> [-WorkDir <目錄>]`；結束碼 0＝全部通過；輸出每項檢查一行 `[通過]／[失敗] 名稱 :: 說明`。

- [ ] **Step 1: 寫腳本。** 行為：（a）開跑前殘留行程與記憶體檢查（只檢查不終止）；（b）解壓到 `<WorkDir>\含 空格 與 中文\`（預設 `$env:TEMP` 下），用 `tar -xf`；（c）記錄解壓資料夾的**檔案清單（相對路徑＋大小＋最後寫入時間）**作為「執行前快照」；（d）用 `icacls <資料夾> /deny "<目前使用者>:(OI)(CI)(WD,AD,DC)"` 拒絕寫入檔案、建立子資料夾、刪除子項（**不是設唯讀屬性**——資料夾的唯讀屬性不會阻擋寫入）；（e）啟動 `elinkbook.exe`（`Start-Process -PassThru`），等 20 秒；（f）檢查：行程仍存活；`MainWindowHandle` 不為 0（有主視窗）；`%APPDATA%` 下實測資料夾存在且有檔案；（g）結束行程樹（`taskkill /PID <pid> /T /F`，含 `msedgewebview2.exe` 子行程），等 `elinkbook.exe` 消失；（h）移除 deny ACL（`icacls … /remove:d`）；（i）取「執行後快照」與執行前比對，**必須完全相同**（沒有新增、刪除、改動任何檔）；（j）清理解壓資料夾與（可選 `-KeepAppData` 不給時）測試用的 `%APPDATA%` 資料夾——**清理前先列出將刪除的路徑；`%APPDATA%` 若在執行前已存在，則不刪，只報告**。任何失敗仍須執行（g）（h）（j）清理，不得留下 deny ACL 或殘留行程。
- [ ] **Step 2: 驗證腳本本身。** 用 Task 1 產出的 zip 實際跑一次，預期全部通過、結束碼 0。**負向驗證：** 把 `-Zip` 換成一個刻意缺少 `vcruntime140_1.dll` 的 zip，**這台機器預期仍可啟動**（System32 有該 DLL），這正好證明「本機驗證抓不到缺 VC DLL 的問題」，要原文寫進報告，**不得**據此宣稱缺 DLL 時也能開。
- [ ] **Step 3: 驗證「寫入偵測」本身有效。** 暫時在驗證腳本的啟動後步驟中人為在解壓資料夾新增一個檔（先移除 deny ACL，驗證完還原腳本），預期（i）失敗；證明比對真的會抓到。
- [ ] **Step 4: Commit。**

```bash
git add app/tool/verify_windows_zip.ps1
git commit -m "test(windows): 免安裝 zip 本機驗證腳本（含空格中文路徑、唯讀、寫入偵測）（epic-66 Issue 14 Task 4）"
```

---

### Task 5：人工開書、報告與文件

**Files:**
- Create: `docs/epics/epic-66-windows-port/issue-14-report.md`
- Modify: `docs/epics/epic-66-windows-port/issues.md`（Issue 14 狀態）、`docs/epics/epic-66-windows-port/epic.md`（決策 30）、`docs/epics.md`（備註）、本檔（勾選步驟）

- [ ] **Step 1: 人工開書（使用者）。** 腳本通過後，請使用者把 zip 解壓到含空格與中文的路徑、雙擊 `elinkbook.exe`、匯入並開一本 EPUB；**執行期間不得同時跑任何 Windows 整合測試或建置**。使用者回報的結果原文記入報告；使用者沒做就在報告寫「未驗證」，過關條件 5 不算達成。
- [ ] **Step 2: 全套 `flutter test` 與 `flutter analyze`。** 本 Issue 不動 Dart 檔，`flutter analyze` 仍須乾淨；全套 `flutter test` 在發 PR 前跑一次，既有偶發失敗照實記錄。
- [ ] **Step 3: 寫 `issue-14-report.md`。** 內容：已查證事實與來源、腳本四項實際輸出（Task 1）、依賴檢查變異驗證四項輸出（Task 2）、本機驗證結果與負向驗證說明（Task 4）、使用者開書結果（Step 1）、zip 大小與檔案清單摘要、**未驗證清單**（乾淨機器缺 VC 執行階段、Windows 10 1809、SmartScreen 實際行為、他人電腦、WebView2 缺失時的行為）、已知限制、後續項目。
- [ ] **Step 4: 更新文件並勾選本檔步驟。** `epic.md` 決策 30 寫：VC DLL 隨附（app-local）的決定與理由、乾淨機器未驗證的範圍限制。
- [ ] **Step 5: Commit。**

```bash
git add docs/epics/epic-66-windows-port/issue-14-report.md docs/epics/epic-66-windows-port/issues.md docs/epics/epic-66-windows-port/epic.md docs/epics.md docs/epics/epic-66-windows-port/plans/plan-issue-14.md
git commit -m "docs(epic-66): Issue 14 免安裝 zip 報告與文件（Task 5）"
```

---

## 已知風險

- 本機驗證**證明不了**「乾淨機器能開」：這台機器有 VS Build Tools、VC 執行階段與 WebView2。依賴靜態檢查能抓到「隨附清單漏檔」，但抓不到其他乾淨機器才會出現的問題。使用者之後若有第二台電腦或虛擬機，應補一次實測。
- 三個 VC DLL 隨附的授權依據是 Visual Studio 的可轉散發（`REDIST.TXT`，app-local 部署）；自用階段不構成問題，**若日後對外發佈，需再確認授權條款與隨附清單**。
- 未簽章的 exe 在別台電腦、從網路下載後會觸發 SmartScreen；README 只能說明，無法消除。
- release 版建置耗時與記憶體：plugin 的 C++ 編譯需要數分鐘；同時開著 Android／Gradle daemon 會讓記憶體不足（本 Epic 已發生兩次）。
- `flutter build windows` 會改動 `generated_plugin*` 三個檔，容易誤 commit；每次 `git add` 明確列檔。
- zip 約 95 MB 以上（舊輸出數字，僅供參考），壓縮率與最終大小以實測為準。
