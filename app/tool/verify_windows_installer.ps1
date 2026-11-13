# Windows 安裝程式本機驗證腳本 (epic-66 Issue 27 Task 3)
# 功能：靜默安裝（含空格與中文路徑、不需管理員）、啟動、覆蓋升級（執行中）、靜默解除安裝、桌面捷徑兩條路徑、資料保護比對
# 注意：會實際啟動 elinkbook.exe（寫入真實的 %APPDATA%\cc.ugotit\elinkbook），執行前必須先備份該資料夾；
#       本腳本任何一步都不會刪除該資料夾。

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Setup,
    [Parameter(Mandatory = $true)]
    [string]$OlderSetup,
    [string]$WorkDir = $env:TEMP,
    # 用來比對「新版內容」的暫存目錄（預設為 package_windows_zip.ps1 的輸出）
    [string]$ExpectedStageDir,
    # 資料夾位置（預設為真實的 App 資料夾）；只給「驗證檢查本身有效」的負向驗證指向假資料夾
    [string]$DataDir = (Join-Path $env:APPDATA "cc.ugotit\elinkbook"),
    # 只給負向驗證：在資料保護比對前人為刪掉 $DataDir 內一個檔案，預期對應檢查失敗
    [switch]$SimulateDataLoss
)

$ErrorActionPreference = "Stop"
$AppDir = Split-Path -Parent $PSScriptRoot
if (-not $ExpectedStageDir) { $ExpectedStageDir = Join-Path $AppDir "build\windows_zip\stage\elinkbook" }
foreach ($p in @($Setup, $OlderSetup)) {
    if (-not (Test-Path $p)) { Write-Host "[失敗] 引數檢查 :: 找不到: $p" -ForegroundColor Red; exit 1 }
}
$Setup = (Resolve-Path $Setup).Path
$OlderSetup = (Resolve-Path $OlderSetup).Path
if (-not (Test-Path (Join-Path $ExpectedStageDir "elinkbook.exe"))) {
    Write-Host "[失敗] 引數檢查 :: 找不到新版暫存目錄 elinkbook.exe: $ExpectedStageDir" -ForegroundColor Red; exit 1
}

# 從 .iss 取出固定 AppId，推算 Inno 在 HKCU 登錄的機碼名稱（{GUID}_is1，單花括號）
$issText = Get-Content (Join-Path $AppDir "windows\packaging\elinkbook.iss") -Raw
if ($issText -notmatch '#define AppIdValue "\{(\{[0-9A-Fa-f-]+\})"') {
    Write-Host "[失敗] 引數檢查 :: 無法從 elinkbook.iss 解析 AppId" -ForegroundColor Red; exit 1
}
$issAppId = $Matches[1]
# 寫死預期的 AppId（發佈後不可更改，見 ADR 0043）。若只從 .iss 取值，.iss 被改動時期望值會跟著變，
# 檢查就抓不到；所以這裡獨立釘住，.iss 的值與它不同就直接失敗。
$pinnedAppId = "{C4E48E89-6F1B-4B77-94B9-23BCE3FCC757}"
if ($issAppId -ne $pinnedAppId) {
    Write-Host "[失敗] 引數檢查 :: elinkbook.iss 的 AppId ($issAppId) 與固定值 ($pinnedAppId) 不同；AppId 發佈後不可更改，會讓舊版使用者無法覆蓋升級" -ForegroundColor Red; exit 1
}
$expectedKeyName = "${pinnedAppId}_is1"
$uninstallRoot = "Software\Microsoft\Windows\CurrentVersion\Uninstall"
$hkcuKey = "HKCU:\$uninstallRoot\$expectedKeyName"
$hklmKey = "HKLM:\$uninstallRoot\$expectedKeyName"

$script:checksPassed = $true
function Record-Check([bool]$pass, [string]$name, [string]$detail) {
    if ($pass) { Write-Host "[通過] $name :: $detail" -ForegroundColor Green }
    else { Write-Host "[失敗] $name :: $detail" -ForegroundColor Red; $script:checksPassed = $false }
}

function Get-ResidualProcesses {
    $residuals = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($p in (Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        $name = $p.Name; $cmd = $p.CommandLine
        if ($name -match '^(elinkbook|flutter_tester|MSBuild)\.exe$' -or
            ($name -match '^dart(vm)?\.exe$' -and $cmd -match 'flutter_tools' -and $cmd -notmatch '(language-server|daemon)')) {
            $residuals.Add([PSCustomObject]@{ Id = $p.ProcessId; Name = $name; CommandLine = $cmd })
        }
    }
    return $residuals
}
function Get-FreeMemoryMB {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) { return [math]::Round($os.FreePhysicalMemory / 1024) }
    return 99999
}

# 開跑前環境檢查（只檢查不終止）
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ((New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[失敗] 開跑前環境檢查 :: 目前行程以系統管理員身分執行，無法驗證「不需要管理員」，請改用一般權限的終端機" -ForegroundColor Red
    exit 1
}
$initialResiduals = @(Get-ResidualProcesses)
if ($initialResiduals.Count -gt 0) {
    Write-Host "[失敗] 開跑前環境檢查 :: 偵測到殘留行程，中止執行：" -ForegroundColor Red
    foreach ($r in $initialResiduals) { Write-Host ("  - [PID: {0}] {1}" -f $r.Id, $r.Name) -ForegroundColor Yellow }
    exit 1
}
if ((Get-FreeMemoryMB) -lt 2048) {
    Write-Host "[失敗] 開跑前環境檢查 :: 可用記憶體不足 2 GB" -ForegroundColor Red
    exit 1
}
$existingEntries = @(Get-ChildItem "HKCU:\$uninstallRoot" | Where-Object { (Get-ItemProperty $_.PSPath).DisplayName -like 'elinkBook*' })
if ($existingEntries.Count -gt 0) {
    Write-Host "[失敗] 開跑前環境檢查 :: 這台機器已安裝 elinkBook（$(($existingEntries | ForEach-Object PSChildName) -join ', ')），請先解除安裝再驗證" -ForegroundColor Red
    exit 1
}
# 驗證會建立並移除同名捷徑；已存在（例如手動替免安裝版建的）就拒絕，避免刪掉使用者自己的東西
foreach ($lnk in @((Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\elinkBook.lnk"), (Join-Path ([Environment]::GetFolderPath("Desktop")) "elinkBook.lnk"))) {
    if (Test-Path $lnk) {
        Write-Host "[失敗] 開跑前環境檢查 :: 已存在同名捷徑，驗證會覆寫並刪除它，請先自行移走: $lnk" -ForegroundColor Red
        exit 1
    }
}
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }

# 列舉行程可見視窗（類別名稱|寬x高）：主視窗類別 FLUTTER_RUNNER_WIN32_WINDOW（沿用 verify_windows_zip.ps1 的做法）
Add-Type @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class VerifyInstWin { delegate bool CB(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumWindows(CB cb, IntPtr l);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 public static List<string> Visible(uint pid) { var l = new List<string>();
  EnumWindows((h, x) => { uint o; GetWindowThreadProcessId(h, out o);
   if (o == pid && IsWindowVisible(h)) { var sb = new StringBuilder(100); GetClassName(h, sb, 100); l.Add(sb.ToString()); }
   return true; }, IntPtr.Zero); return l; } }
"@

function Get-Snapshot([string]$dir) {
    $map = @{}
    if (Test-Path $dir) {
        $base = (Resolve-Path $dir).Path.TrimEnd('\')
        foreach ($f in (Get-ChildItem $dir -Recurse -File -Force)) {
            $rel = $f.FullName.Substring($base.Length + 1)
            # WebView2（Chromium）的 lockfile 只在 App 執行期間存在、App 結束就會自己消失，不是使用者資料，不納入比對
            if ($rel.Replace('\', '/') -eq 'webview_data/EBWebView/lockfile') { continue }
            $map[$rel] = $f.Length
        }
    }
    return $map
}
# 回傳 $before 中「現在不見了」的檔案清單
function Get-MissingFiles($before, [string]$dir) {
    $now = Get-Snapshot $dir
    return @($before.Keys | Where-Object { -not $now.ContainsKey($_) })
}

function Install-Silent([string]$setup, [string]$dir, [string[]]$extra, [string]$log) {
    $installArgs = @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/DIR=`"$dir`"", "/LOG=`"$log`"") + $extra
    $p = Start-Process -FilePath $setup -ArgumentList $installArgs -Wait -PassThru
    return $p.ExitCode
}

function Get-UninstallExe {
    if (-not (Test-Path $hkcuKey)) { return $null }
    $s = (Get-ItemProperty $hkcuKey).UninstallString
    if ($s -match '^"([^"]+)"') { return $Matches[1] }
    return $s
}

# Inno 解除安裝程式的行程：原行程（unins000.exe）與複製到 %TEMP% 的暫存副本（_iu*.tmp、_unins.tmp）
function Get-UninstallerProcesses {
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(_iu[0-9A-Za-z]*\.tmp|_unins\.tmp|unins\d{3}\.exe)$' })
}

# 靜默解除安裝。Inno 的解除安裝程式會複製自己到 %TEMP% 再啟動並讓原行程立刻結束，
# 所以 -Wait 返回時檔案還沒刪完，必須輪詢（每 0.5 秒）等程式檔、登錄項「與解除安裝行程本身」都結束；
# 刪資料的詢問發生在最後的 usPostUninstall，行程還在就不能判定「沒刪資料」。
# 刻意不帶 /SUPPRESSMSGBOXES：這樣 .iss 的 UninstallSilent 判斷是唯一擋住詢問框的防線，
# 防線失效時詢問框會卡住，輪詢逾時就會失敗。
function Uninstall-Silent([string]$installDir, [int]$timeoutSec = 30) {
    $unins = Get-UninstallExe
    if (-not $unins -or -not (Test-Path $unins)) { return @{ Exit = -1; Seconds = 0; Gone = $false } }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $unins -ArgumentList @("/VERYSILENT", "/NORESTART") -Wait -PassThru
    $gone = $false
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        if ((-not (Test-Path (Join-Path $installDir "elinkbook.exe"))) -and (-not (Test-Path $hkcuKey)) -and ((Get-UninstallerProcesses).Count -eq 0)) { $gone = $true; break }
        Start-Sleep -Milliseconds 500
    }
    return @{ Exit = $p.ExitCode; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); Gone = $gone }
}

# 目前這台機器上所有 elinkBook 的解除安裝項（不論 AppId）
function Get-ElinkEntries {
    return @(Get-ChildItem "HKCU:\$uninstallRoot" | Where-Object { (Get-ItemProperty $_.PSPath).DisplayName -like 'elinkBook*' })
}
# 目錄內每個檔案的相對路徑（小寫）→ SHA256
function Get-FileHashMap([string]$dir) {
    $map = @{}
    $base = (Resolve-Path $dir).Path.TrimEnd('\')
    foreach ($f in (Get-ChildItem $dir -Recurse -File -Force)) {
        $map[$f.FullName.Substring($base.Length + 1).ToLowerInvariant()] = Get-Sha256 $f.FullName
    }
    return $map
}

function Start-AppWithWindow([string]$installDir) {
    $exe = Join-Path $installDir "elinkbook.exe"
    $proc = Start-Process -FilePath $exe -WorkingDirectory $installDir -PassThru
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 40) {
        if ($proc.HasExited) { break }
        if ([VerifyInstWin]::Visible([uint32]$proc.Id) -contains 'FLUTTER_RUNNER_WIN32_WINDOW') {
            return @{ Proc = $proc; Window = $true; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
        }
        Start-Sleep -Milliseconds 100
    }
    return @{ Proc = $proc; Window = $false; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
}
function Stop-AppTree($proc) {
    if ($proc -and -not $proc.HasExited) {
        taskkill.exe /PID $proc.Id /T /F 2>$null | Out-Null
        $proc.WaitForExit(15000) | Out-Null
    }
}
function Get-Sha256([string]$path) {
    $h = [System.Security.Cryptography.SHA256]::Create()
    $s = [System.IO.File]::OpenRead($path)
    try { return (-join ($h.ComputeHash($s) | ForEach-Object { $_.ToString("X2") })) } finally { $s.Close(); $h.Dispose() }
}
function Get-LnkTarget([string]$lnk) {
    if (-not (Test-Path $lnk)) { return $null }
    return (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath
}

# ---------------------------------------------------------------------------
$root = Join-Path $WorkDir "含 空格 與 中文 installer-verify"
if (Test-Path $root) {
    Write-Host "[失敗] 引數檢查 :: 工作目錄已存在，拒絕覆寫（請先確認並手動移除）: $root" -ForegroundColor Red
    exit 1
}
New-Item -ItemType Directory -Path $root -Force | Out-Null
$target = Join-Path $root "app"
$log = Join-Path $root "install.log"
$startMenuLnk = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\elinkBook.lnk"
$desktopLnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "elinkBook.lnk"
$proc = $null

try {
    # ===== A. 安裝新版（預設 tasks）：檢查項 1、2、3、4 =====
    $ec = Install-Silent $Setup $target @() $log
    Record-Check ($ec -eq 0) "1a 靜默安裝" "exit $ec；安裝目錄 $target"
    $entry = if (Test-Path $hkcuKey) { Get-ItemProperty $hkcuKey } else { $null }
    Record-Check ($null -ne $entry) "1b 登錄項（HKCU）" "預期機碼名稱 $expectedKeyName；實際找到: $($null -ne $entry)"
    Record-Check (-not (Test-Path $hklmKey)) "1c 不寫 HKLM" "HKLM 下沒有同 AppId 的項目（不需要系統管理員）"

    $must = @("elinkbook.exe", "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll", "data\foliate\main.js", "README.txt")
    $missing = @($must | Where-Object { -not (Test-Path (Join-Path $target $_)) })
    Record-Check ($missing.Count -eq 0) "2a 安裝內容必備檔" "缺少: $(if ($missing.Count) { $missing -join ', ' } else { '無' })"
    $debug = @(Get-ChildItem $target -Recurse -File -Include *.pdb, *.lib, *.exp, *.ilk -ErrorAction SilentlyContinue)
    Record-Check ($debug.Count -eq 0) "2b 無除錯檔" "發現 $($debug.Count) 個 .pdb/.lib/.exp/.ilk"
    $fontDir = Join-Path $target "data\flutter_assets\assets"
    $fonts = @(Get-ChildItem $fontDir -Recurse -File -Include *.ttf, *.otf, *.ttc, *.woff, *.woff2 -ErrorAction SilentlyContinue)
    Record-Check ($fonts.Count -eq 0) "2c 無打包字型" "assets 下發現 $($fonts.Count) 個字型檔（內建字型應改走可下載字型）"
    # 2e：安裝內容與新版暫存目錄逐檔（路徑加 SHA256）一致，只允許多出解除安裝程式自己的檔案
    $stageMap = Get-FileHashMap $ExpectedStageDir
    $instMap = Get-FileHashMap $target
    $missingInInstall = @($stageMap.Keys | Where-Object { -not $instMap.ContainsKey($_) })
    $differs = @($stageMap.Keys | Where-Object { $instMap.ContainsKey($_) -and $instMap[$_] -ne $stageMap[$_] })
    $extra = @($instMap.Keys | Where-Object { -not $stageMap.ContainsKey($_) -and $_ -notmatch '^unins\d{3}\.(exe|dat|msg)$' })
    $diffNames = @($missingInInstall + $differs + $extra | Select-Object -First 5) -join '、'
    Record-Check (($missingInInstall.Count + $differs.Count + $extra.Count) -eq 0) "2e 內容與暫存目錄逐檔一致" "暫存目錄 $($stageMap.Count) 檔；安裝缺少 $($missingInInstall.Count)、內容不同 $($differs.Count)、多出 $($extra.Count)（不含 unins*）$(if ($diffNames) { '：' + $diffNames })"
    $testAssets = Join-Path $target "data\flutter_assets\test"
    Record-Check (-not (Test-Path $testAssets)) "2d 無測試用資源" "data\flutter_assets\test 存在: $(Test-Path $testAssets)（整合測試 fixtures 不應出貨）"

    $exePath = Join-Path $target "elinkbook.exe"
    Record-Check ((Get-LnkTarget $startMenuLnk) -eq $exePath) "3a 開始功能表項目" "$startMenuLnk → $(Get-LnkTarget $startMenuLnk)"
    Record-Check ((Get-LnkTarget $desktopLnk) -eq $exePath) "3b 桌面捷徑預設存在" "$desktopLnk → $(Get-LnkTarget $desktopLnk)"

    $r = Start-AppWithWindow $target
    $proc = $r.Proc
    Record-Check $r.Window "4a 主視窗偵測" "安裝版 elinkbook.exe 於 $($r.Seconds) 秒內出現主視窗"
    Start-Sleep -Seconds 20
    Record-Check (-not $proc.HasExited) "4b 行程存活 20 秒" "HasExited: $($proc.HasExited)"
    Stop-AppTree $proc; $proc = $null

    # ===== B. 靜默解除安裝：檢查項 7，並確認資料保護（6a）=====
    $dataBefore = Get-Snapshot $DataDir
    $u = Uninstall-Silent $target
    Record-Check ($u.Exit -eq 0 -and $u.Gone) "7a 靜默解除安裝" "exit $($u.Exit)；輪詢 $($u.Seconds) 秒後程式檔與登錄項消失: $($u.Gone)"
    Record-Check (-not (Test-Path $startMenuLnk) -and -not (Test-Path $desktopLnk)) "7b 捷徑移除" "開始功能表與桌面捷徑皆已消失"
    if ($SimulateDataLoss) {
        $victim = Get-ChildItem $DataDir -Recurse -File -Force | Select-Object -First 1
        if ($victim) { Remove-Item $victim.FullName -Force; Write-Host "[模擬] 已人為刪除資料檔 $($victim.FullName)" -ForegroundColor Yellow }
    }
    $lost = @(Get-MissingFiles $dataBefore $DataDir)
    Record-Check ($lost.Count -eq 0) "6a 靜默解除安裝不刪資料" "解除安裝前已存在 $($dataBefore.Count) 個資料檔；消失 $($lost.Count) 個$(if ($lost.Count) { "：" + (($lost | Select-Object -First 5) -join "、") })"

    # ===== C. 覆蓋升級（舊版執行中）：檢查項 5 =====
    $ec = Install-Silent $OlderSetup $target @() $log
    Record-Check ($ec -eq 0) "5a 安裝舊版" "exit $ec"
    $oldVersion = if (Test-Path $hkcuKey) { (Get-ItemProperty $hkcuKey).DisplayVersion } else { $null }
    $r = Start-AppWithWindow $target
    $proc = $r.Proc
    Record-Check ($r.Window -and -not $proc.HasExited) "5b 舊版啟動並保持執行" "PID $($proc.Id)；舊版 DisplayVersion=$oldVersion；主視窗 $($r.Window)"
    $dataAtUpgrade = Get-Snapshot $DataDir
    $ec = Install-Silent $Setup $target @() $log
    Record-Check ($ec -eq 0) "5c 執行中覆蓋安裝新版" "exit $ec"
    $proc.Refresh()
    Record-Check $proc.HasExited "5d 舊行程被關閉" "HasExited: $($proc.HasExited)"
    Stop-AppTree $proc; $proc = $null
    # 數「所有」elinkBook 的解除安裝項（不論機碼名稱）：AppId 若不同，新舊會並存成兩個項目、兩個 unins*.exe
    $entries = @(Get-ElinkEntries)
    $uninsFiles = @(Get-ChildItem $target -Filter 'unins*.exe' -ErrorAction SilentlyContinue)
    $newVersion = if (Test-Path $hkcuKey) { (Get-ItemProperty $hkcuKey).DisplayVersion } else { $null }
    Record-Check ($entries.Count -eq 1 -and $entries[0].PSChildName -eq $expectedKeyName -and $uninsFiles.Count -eq 1 -and $newVersion -ne $oldVersion) "5e 單一解除安裝項且版本更新" "elinkBook 解除安裝項數 $($entries.Count)（機碼 $(($entries | ForEach-Object PSChildName) -join ', ')）；unins*.exe 數 $($uninsFiles.Count)；DisplayVersion $oldVersion → $newVersion"
    $exeSame = (Get-Sha256 $exePath) -eq (Get-Sha256 (Join-Path $ExpectedStageDir "elinkbook.exe"))
    $readmeSame = (Get-Sha256 (Join-Path $target "README.txt")) -eq (Get-Sha256 (Join-Path $ExpectedStageDir "README.txt"))
    Record-Check ($exeSame -and $readmeSame) "5f 檔案已被新版取代" "elinkbook.exe 與新版相同: $exeSame；README.txt 與新版相同: $readmeSame"
    $lost = @(Get-MissingFiles $dataAtUpgrade $DataDir)
    Record-Check ($lost.Count -eq 0) "6b 覆蓋升級不刪資料" "升級前已存在 $($dataAtUpgrade.Count) 個資料檔；消失 $($lost.Count) 個$(if ($lost.Count) { "：" + (($lost | Select-Object -First 5) -join "、") })"

    # ===== D. 再次靜默解除安裝 =====
    $dataBefore = Get-Snapshot $DataDir
    $u = Uninstall-Silent $target
    Record-Check ($u.Exit -eq 0 -and $u.Gone) "7c 升級後靜默解除安裝" "exit $($u.Exit)；輪詢 $($u.Seconds) 秒後程式檔與登錄項消失: $($u.Gone)"
    $lost = @(Get-MissingFiles $dataBefore $DataDir)
    Record-Check ($lost.Count -eq 0) "6c 第二次靜默解除安裝不刪資料" "已存在 $($dataBefore.Count) 個資料檔；消失 $($lost.Count) 個$(if ($lost.Count) { "：" + (($lost | Select-Object -First 5) -join "、") })"

    # ===== E. 取消桌面捷徑：檢查項 8 =====
    $ec = Install-Silent $Setup $target @('/TASKS="!desktopicon"') $log
    Record-Check ($ec -eq 0) "8a 安裝（取消桌面捷徑）" "exit $ec"
    Record-Check ((-not (Test-Path $desktopLnk)) -and ((Get-LnkTarget $startMenuLnk) -eq $exePath)) "8b 桌面捷徑不存在、開始功能表存在" "桌面捷徑存在: $(Test-Path $desktopLnk)"
    # 10：App 執行中解除安裝必須被拒絕（檔案被鎖住刪不掉卻移除登錄項，會留下沒有移除入口的殘骸）
    $r = Start-AppWithWindow $target
    $proc = $r.Proc
    $uRefuse = Uninstall-Silent $target 10
    Record-Check ((-not $uRefuse.Gone) -and (Test-Path $hkcuKey) -and (Test-Path $exePath)) "10a App 執行中拒絕解除安裝" "主視窗 $($r.Window)；解除安裝結束碼 $($uRefuse.Exit)；程式檔與登錄項仍在: $((Test-Path $exePath) -and (Test-Path $hkcuKey))"
    Stop-AppTree $proc; $proc = $null
    Start-Sleep -Seconds 2
    $u = Uninstall-Silent $target
    Record-Check ($u.Exit -eq 0 -and $u.Gone) "8c 收尾解除安裝" "exit $($u.Exit)；輪詢 $($u.Seconds) 秒"
}
finally {
    Stop-AppTree $proc
    # 收尾：若仍有殘留安裝，靜默解除安裝；只移除本腳本建立的工作目錄，絕不動資料夾
    if (Test-Path $hkcuKey) { [void](Uninstall-Silent $target) }
    $wv = @(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match [regex]::Escape('cc.ugotit\elinkbook') })
    $left = @(Get-ResidualProcesses)
    Record-Check (($left.Count -eq 0) -and (-not (Test-Path (Join-Path $target "elinkbook.exe"))) -and (-not (Test-Path $hkcuKey))) "9 結束時無殘留" "殘留 elinkbook 等行程 $($left.Count)；WebView2 子行程 $($wv.Count)；安裝目錄 exe 存在: $(Test-Path (Join-Path $target 'elinkbook.exe'))；登錄項存在: $(Test-Path $hkcuKey)"
    if (Test-Path $root) { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:checksPassed) { Write-Host "全部檢查通過" -ForegroundColor Green; exit 0 }
else { Write-Host "有檢查失敗" -ForegroundColor Red; exit 1 }
