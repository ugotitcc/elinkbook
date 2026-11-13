# Windows 安裝程式「解除安裝是否刪除資料」本機驗證腳本 (epic-66 Issue 27)
# 功能：用 AppDataRootOverride／DocsRootOverride 編一個測試用安裝程式，把資料根目錄指到假資料夾，
#       以 UI Automation 實際點擊解除安裝詢問框的「否」與「是」，驗證刪除範圍。
# 安全：整個流程只碰 $WorkDir 下的假資料夾，不碰真實的 %APPDATA% 與「文件」資料夾。
#       測試用安裝程式與出貨版只差這兩個 /D 定義；出貨版不帶，使用真實路徑。

[CmdletBinding()]
param(
    [string]$StageDir,
    [string]$WorkDir = $env:TEMP
)

$ErrorActionPreference = "Stop"
$AppDir = Split-Path -Parent $PSScriptRoot
if (-not $StageDir) { $StageDir = Join-Path $AppDir "build\windows_zip\stage\elinkbook" }
if (-not (Test-Path (Join-Path $StageDir "elinkbook.exe"))) {
    Write-Host "[失敗] 引數檢查 :: 找不到暫存目錄 elinkbook.exe: $StageDir" -ForegroundColor Red; exit 1
}
$issPath = Join-Path $AppDir "windows\packaging\elinkbook.iss"
$iscc = @((Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"), (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"), (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")) |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { Write-Host "[失敗] 引數檢查 :: 找不到 ISCC.exe" -ForegroundColor Red; exit 1 }

$script:checksPassed = $true
function Record-Check([bool]$pass, [string]$name, [string]$detail) {
    if ($pass) { Write-Host "[通過] $name :: $detail" -ForegroundColor Green }
    else { Write-Host "[失敗] $name :: $detail" -ForegroundColor Red; $script:checksPassed = $false }
}

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$uninstallRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
function Get-ElinkEntries {
    return @(Get-ChildItem $uninstallRoot | Where-Object { (Get-ItemProperty $_.PSPath).DisplayName -like 'elinkBook*' })
}
if ((Get-ElinkEntries).Count -gt 0) {
    Write-Host "[失敗] 開跑前環境檢查 :: 這台機器已安裝 elinkBook，請先解除安裝再驗證" -ForegroundColor Red; exit 1
}
foreach ($lnk in @((Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\elinkBook.lnk"), (Join-Path ([Environment]::GetFolderPath("Desktop")) "elinkBook.lnk"))) {
    if (Test-Path $lnk) { Write-Host "[失敗] 開跑前環境檢查 :: 已存在同名捷徑，驗證會覆寫並刪除它，請先自行移走: $lnk" -ForegroundColor Red; exit 1 }
}

$root = Join-Path $WorkDir "含 空格 與 中文 uninstall-data-verify"
if (Test-Path $root) { Write-Host "[失敗] 引數檢查 :: 工作目錄已存在，拒絕覆寫: $root" -ForegroundColor Red; exit 1 }
New-Item -ItemType Directory -Path $root -Force | Out-Null
$fakeAppData = Join-Path $root "fake-appdata"
$fakeDocs = Join-Path $root "fake-docs"
$target = Join-Path $root "app"
$outDir = Join-Path $root "out"
$log = Join-Path $root "install.log"

# 「文件」資料夾下的 elinkbook 目錄會包含的項目（epic-66 Issue 29：已收進 elinkbook 子資料夾）
$docsFolders = @("covers", "imported_books", "cloud_import_books", "remote_books", "wifi_transfer_uploads", "update_staging")
$docsDbs = @("library.db", "dictionary.db")
# 不屬於新版的項目（含文件根目錄模擬舊版留下的同名檔案/資料夾與使用者其他檔案）：選「是」也必須原封不動
$docsDecoys = @(
    "covers\a.bin", "imported_books\b.bin", "library.db", "dictionary.db",
    "六祖壇經\x.txt", "desktop.ini", "my-library.db", "library.db.bak", "covers-backup\a.jpg", "notes.txt", "Zoom\z.txt"
)
$appDataDecoys = @("cc.ugotit\other\keep.txt")

function New-File([string]$path) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    Set-Content -LiteralPath $path -Value "x" -Encoding ASCII
}
function Seed-Data {
    foreach ($d in $docsFolders) { New-File (Join-Path $fakeDocs "elinkbook\$d\sub\a.bin") }
    foreach ($db in $docsDbs) { foreach ($suf in @("", "-wal", "-shm", "-journal")) { New-File (Join-Path $fakeDocs "elinkbook\$db$suf") } }
    foreach ($x in $docsDecoys) { New-File (Join-Path $fakeDocs $x) }
    New-File (Join-Path $fakeAppData "cc.ugotit\elinkbook\downloaded-fonts\f.ttf")
    New-File (Join-Path $fakeAppData "cc.ugotit\elinkbook\webview_data\EBWebView\x")
    foreach ($x in $appDataDecoys) { New-File (Join-Path $fakeAppData $x) }
}
function Get-Missing([string[]]$relPaths, [string]$base) {
    # 用逗號運算子保留陣列型別：空結果若被展開成 $null，兩個空結果相加會變成 1 個空元素，造成假失敗
    return ,@($relPaths | Where-Object { -not (Test-Path -LiteralPath (Join-Path $base $_)) })
}
function Get-Present([string[]]$relPaths, [string]$base) {
    return ,@($relPaths | Where-Object { Test-Path -LiteralPath (Join-Path $base $_) })
}
$docsTargets = @("elinkbook")
$appDataTargets = @("cc.ugotit\elinkbook")

function Get-UninstallerProcessIds {
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(_iu[0-9A-Za-z]*\.tmp|_unins\.tmp|unins\d{3}\.exe)$' } | ForEach-Object { [int]$_.ProcessId })
}

# 對解除安裝程式彈出的訊息框逐一回應：
#   - 含「所有資料（包含書庫）」的是我們的詢問框：按 $answer（"Yes"＝AutomationId 6、"No"＝7），並記錄預設按鈕
#   - 其他有「是」鈕的是 Inno 的「確定要移除」確認：按「是」
#   - 只有「確定」鈕的是結尾訊息：按「確定」
function Invoke-UninstallDialogs([string]$answer, [int]$timeoutSec = 120) {
    $info = @{ PromptSeen = $false; DefaultIsNo = $null; Handled = 0 }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        $ids = Get-UninstallerProcessIds
        if ($ids.Count -eq 0 -and $sw.Elapsed.TotalSeconds -gt 3) { break }
        foreach ($win in $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
            $pid2 = 0
            try { $pid2 = $win.Current.ProcessId } catch { continue }
            if ($ids -notcontains $pid2) { continue }
            $buttons = @{}
            foreach ($b in $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)))) {
                $buttons[$b.Current.AutomationId] = $b
            }
            if ($buttons.Count -eq 0) { continue }
            $texts = ($win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text))) | ForEach-Object { $_.Current.Name }) -join "`n"
            $press = $null
            if ($texts -like '*所有資料（包含書庫）*') {
                $info.PromptSeen = $true
                if ($buttons.ContainsKey('7')) { $info.DefaultIsNo = [bool]$buttons['7'].Current.HasKeyboardFocus }
                $press = if ($answer -eq "Yes") { $buttons['6'] } else { $buttons['7'] }
            } elseif ($buttons.ContainsKey('6')) { $press = $buttons['6'] }
            elseif ($buttons.ContainsKey('1')) { $press = $buttons['1'] }
            if ($press) {
                try { ([System.Windows.Automation.InvokePattern]$press.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke(); $info.Handled++ } catch { }
                Start-Sleep -Milliseconds 700
            }
        }
        Start-Sleep -Milliseconds 400
    }
    $info.Finished = ((Get-UninstallerProcessIds).Count -eq 0)
    return $info
}

function Install-TestSetup([string]$setup) {
    $p = Start-Process -FilePath $setup -ArgumentList @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/DIR=`"$target`"", "/LOG=`"$log`"") -Wait -PassThru
    return $p.ExitCode
}
function Get-UninstallExe {
    $e = Get-ElinkEntries | Select-Object -First 1
    if (-not $e) { return $null }
    $s = (Get-ItemProperty $e.PSPath).UninstallString
    if ($s -match '^"([^"]+)"') { return $Matches[1] }
    return $s
}
function Start-InteractiveUninstall([string]$answer) {
    $unins = Get-UninstallExe
    if (-not $unins) { return $null }
    # 不帶任何靜默旗標：會依序出現「確定要移除」確認、我們的詢問框、結尾訊息
    [void](Start-Process -FilePath $unins -PassThru)
    return Invoke-UninstallDialogs $answer
}

try {
    # 編譯測試用安裝程式：只多了兩個把資料根目錄指到假資料夾的 /D 定義
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    & $iscc "/DAppVersion=1.1.0" "/DVersionInfoVersion=1.1.0.3" "/DStageDir=$StageDir" "/DOutputDir=$outDir" "/DOutputBaseFilename=test-setup" "/DAppDataRootOverride=$fakeAppData" "/DDocsRootOverride=$fakeDocs" $issPath | Select-Object -Last 1 | Out-Host
    $setup = Join-Path $outDir "test-setup.exe"
    Record-Check (Test-Path $setup) "0 編譯測試用安裝程式" "資料根目錄指向 $root 下的假資料夾（不是真實的 %APPDATA% 與「文件」）"

    # ===== 情境一：選「否」 =====
    Record-Check ((Install-TestSetup $setup) -eq 0) "1a 安裝測試用安裝程式" "安裝到 $target"
    Seed-Data
    $r = Start-InteractiveUninstall "No"
    Record-Check ($r -and $r.PromptSeen) "1b 解除安裝時出現資料詢問框" "已偵測到含「所有資料（包含書庫）」的詢問框；處理訊息框 $($r.Handled) 個"
    Record-Check ($r -and $r.DefaultIsNo -eq $true) "1c 詢問框預設按鈕為「否」" "「否」鈕取得鍵盤焦點: $($r.DefaultIsNo)"
    Record-Check ($r -and $r.Finished -and -not (Test-Path (Join-Path $target "elinkbook.exe")) -and (Get-ElinkEntries).Count -eq 0) "1d 程式已移除" "解除安裝行程結束、程式檔與登錄項皆消失"
    $lost = @((Get-Missing $docsTargets $fakeDocs) + (Get-Missing $appDataTargets $fakeAppData) + (Get-Missing $docsDecoys $fakeDocs) + (Get-Missing $appDataDecoys $fakeAppData))
    Record-Check ($lost.Count -eq 0) "1e 選「否」：所有資料原封不動" "消失 $($lost.Count) 項$(if ($lost.Count) { '：' + ($lost -join '、') })"

    # ===== 情境二：選「是」 =====
    Remove-Item -LiteralPath $fakeDocs, $fakeAppData -Recurse -Force -ErrorAction SilentlyContinue
    Record-Check ((Install-TestSetup $setup) -eq 0) "2a 重新安裝測試用安裝程式" "安裝到 $target"
    Seed-Data
    $r = Start-InteractiveUninstall "Yes"
    Record-Check ($r -and $r.PromptSeen -and $r.Finished) "2b 解除安裝並選「是」" "詢問框已出現並按「是」；解除安裝行程結束: $($r -and $r.Finished)"
    $still = @((Get-Present $docsTargets $fakeDocs) + (Get-Present $appDataTargets $fakeAppData))
    Record-Check ($still.Count -eq 0) "2c 選「是」：elinkbook 兩個資料夾已刪除" "仍存在 $($still.Count) 項$(if ($still.Count) { '：' + ($still -join '、') })（fake-docs\elinkbook 與 cc.ugotit\elinkbook）"
    $lostDecoys = @((Get-Missing $docsDecoys $fakeDocs) + (Get-Missing $appDataDecoys $fakeAppData))
    Record-Check ($lostDecoys.Count -eq 0 -and (Test-Path -LiteralPath $fakeDocs)) "2d 選「是」：根目錄的舊項目與其他檔案原封不動" "消失 $($lostDecoys.Count) 項$(if ($lostDecoys.Count) { '：' + ($lostDecoys -join '、') })；文件根目錄存在: $(Test-Path -LiteralPath $fakeDocs)"
}
finally {
    foreach ($id in (Get-UninstallerProcessIds)) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    foreach ($e in (Get-ElinkEntries)) {
        $s = (Get-ItemProperty $e.PSPath).UninstallString
        if ($s -match '^"([^"]+)"') { Start-Process -FilePath $Matches[1] -ArgumentList @("/VERYSILENT", "/NORESTART") -Wait }
    }
    # 收尾被中斷時可能留下指向測試資料夾的捷徑：只刪目標在 $root 底下的那種，不動使用者自己的捷徑
    foreach ($lnk in @((Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\elinkBook.lnk"), (Join-Path ([Environment]::GetFolderPath("Desktop")) "elinkBook.lnk"))) {
        if ((Test-Path $lnk) -and ((New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath -like "$root*")) { Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Seconds 3
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:checksPassed) { Write-Host "全部檢查通過" -ForegroundColor Green; exit 0 }
else { Write-Host "有檢查失敗" -ForegroundColor Red; exit 1 }
