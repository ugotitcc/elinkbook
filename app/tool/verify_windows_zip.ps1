# Windows 免安裝 zip 本機驗證腳本 (epic-66 Issue 14 Task 4)
# 功能：解壓至含空格與中文的唯讀資料夾、啟動、驗證主視窗與行程存活、驗證解壓目錄零寫入與 AppData 寫入

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Zip,
    [string]$WorkDir = $env:TEMP,
    [switch]$KeepAppData
)

$ErrorActionPreference = "Stop"

# 1. 參數解析與驗證
if (-not [System.IO.Path]::IsPathRooted($Zip)) {
    $Zip = Join-Path (Get-Location) $Zip
}
if (-not (Test-Path $Zip)) {
    Write-Host "[失敗] 引數檢查 :: 找不到指定的 zip 檔案: $Zip" -ForegroundColor Red
    exit 1
}

# 2. 殘留進程檢查函數
function Get-ResidualProcesses {
    $residuals = [System.Collections.Generic.List[PSCustomObject]]::new()
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        $name = $p.Name
        $cmd = $p.CommandLine
        $procId = $p.ProcessId
        if ($name -match '^(elinkbook|flutter_tester|MSBuild)\.exe$' -or
            ($name -match '^dart(vm)?\.exe$' -and $cmd -match 'flutter_tools' -and $cmd -notmatch '(language-server|daemon)')) {
            $residuals.Add([PSCustomObject]@{
                Id = $procId
                Name = $name
                CommandLine = $cmd
            })
        }
    }
    return $residuals
}

function Get-FreeMemoryMB {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        return [math]::Round($os.FreePhysicalMemory / 1024)
    }
    return 99999
}

# (a) 開跑前殘留進程與記憶體檢查
$initialResiduals = @(Get-ResidualProcesses)
if ($initialResiduals.Count -gt 0) {
    Write-Host "[失敗] 開跑前環境檢查 :: 偵測到殘留行程，中止執行：" -ForegroundColor Red
    foreach ($r in $initialResiduals) {
        Write-Host ("  - [PID: {0}] {1} (Cmd: {2})" -f $r.Id, $r.Name, $r.CommandLine) -ForegroundColor Yellow
    }
    exit 1
}

$freeMB = Get-FreeMemoryMB
if ($freeMB -lt 4096) {
    Write-Host "[警告] 開跑前環境檢查 :: 系統可用記憶體 ($freeMB MB) 低於門檻 (4096 MB)，等待 10 秒回收..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    $freeMB = Get-FreeMemoryMB
    if ($freeMB -lt 4096) {
        Write-Host "[失敗] 開跑前環境檢查 :: 系統可用實體記憶體不足 4 GB ($freeMB MB)，中止測試。" -ForegroundColor Red
        exit 1
    }
}

# 記錄既有使用者資料目錄狀態與啟動時間
$appDataPath = Join-Path $env:APPDATA "cc.ugotit\elinkbook"
$appDataExistedPrior = Test-Path $appDataPath
$launchTime = Get-Date

# 準備解壓路徑：包含空格與中文字元
$extractTarget = Join-Path $WorkDir "含 空格 與 中文"
$programDir = Join-Path $extractTarget "elinkbook"
$exePath = Join-Path $programDir "elinkbook.exe"
$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

$tarExe = Join-Path $env:SystemRoot "System32\tar.exe"
if (-not (Test-Path $tarExe)) { $tarExe = "tar.exe" }

$proc = $null
$denyAclApplied = $false
$checksPassed = $true

function Record-Check([bool]$pass, [string]$name, [string]$detail) {
    if ($pass) {
        Write-Host "[通過] $name :: $detail" -ForegroundColor Green
    } else {
        Write-Host "[失敗] $name :: $detail" -ForegroundColor Red
        $script:checksPassed = $false
    }
}

function Get-DirectorySnapshot([string]$baseDir) {
    $snapshot = @{}
    if (Test-Path $baseDir) {
        $cleanBase = [System.IO.Path]::GetFullPath($baseDir).TrimEnd('\', '/') + '\'
        Get-ChildItem -Path $baseDir -Recurse -Force | ForEach-Object {
            if (-not $_.PSIsContainer) {
                $fullPath = [System.IO.Path]::GetFullPath($_.FullName)
                $relPath = if ($fullPath.StartsWith($cleanBase, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $fullPath.Substring($cleanBase.Length)
                } else {
                    $_.Name
                }
                $snapshot[$relPath] = "$($_.Length)|$($_.LastWriteTimeUtc.Ticks)"
            }
        }
    }
    return $snapshot
}

try {
    # 清理舊的解壓目錄
    if (Test-Path $extractTarget) {
        & icacls.exe $extractTarget /remove:d "*$userSid" 2>$null | Out-Null
        Remove-Item -Path $extractTarget -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $extractTarget -Force | Out-Null

    # (b) 解壓 zip
    Write-Host "解壓 zip 至: $extractTarget..." -ForegroundColor Cyan
    & $tarExe -xf $Zip -C $extractTarget
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exePath)) {
        Record-Check $false "解壓縮驗證" "解壓失敗或找不到執行檔: $exePath"
        exit 1
    }
    Record-Check $true "解壓縮驗證" "成功解壓至含空格與中文之目錄，二進位檔存在"

    # (c) 記錄執行前快照
    $preSnapshot = Get-DirectorySnapshot $extractTarget

    # (d) 施加實質唯讀 deny ACL
    Write-Host "套用 deny ACL (拒絕寫入檔案、建立子資料夾、刪除子項)..." -ForegroundColor Cyan
    $aclOut = & icacls.exe $extractTarget /deny "*${userSid}:(OI)(CI)(WD,AD,DC)" /q 2>&1
    if ($LASTEXITCODE -ne 0) {
        Record-Check $false "ACL 唯讀防護設定" "icacls 設定失敗: $aclOut"
        exit 1
    }
    $denyAclApplied = $true
    Record-Check $true "ACL 唯讀防護設定" "已成功套用 deny (WD,AD,DC) 權限至解壓目錄"

    # (e) 啟動程式（明確指定 -WorkingDirectory）
    Write-Host "啟動應用程式: $exePath (工作目錄: $programDir)..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath $exePath -WorkingDirectory $programDir -PassThru

    # (f1) 輪詢等候主視窗出現（最長 40 秒）
    $hasWindow = $false
    $detectedHandle = [System.IntPtr]::Zero
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 40) {
        if ($proc.HasExited) { break }
        $proc.Refresh()
        $handle = $proc.MainWindowHandle
        if ($handle -eq [System.IntPtr]::Zero -or $handle -eq 0) {
            $gp = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
            if ($gp) { $handle = $gp.MainWindowHandle }
        }
        if ($handle -ne [System.IntPtr]::Zero -and $handle -ne 0) {
            $hasWindow = $true
            $detectedHandle = $handle
            break
        }
        Start-Sleep -Milliseconds 500
    }

    if ($hasWindow -and (-not $proc.HasExited)) {
        Record-Check $true "主視窗偵測" "主視窗於 $([math]::Round($sw.Elapsed.TotalSeconds, 1)) 秒內成功建立 (Handle: $detectedHandle)"
    } else {
        Record-Check $false "主視窗偵測" "40 秒內未偵測到主視窗或行程提前終止 (HasExited: $($proc.HasExited))"
    }

    # (f2) 視窗出現後再等候 10 秒確認行程存活
    Write-Host "等待 10 秒以驗證視窗與執行階段穩定度..." -ForegroundColor Cyan
    Start-Sleep -Seconds 10
    $proc.Refresh()
    if (-not $proc.HasExited) {
        Record-Check $true "視窗持續存活" "視窗出現 10 秒後行程仍穩定執行 (PID: $($proc.Id))"
    } else {
        Record-Check $false "視窗持續存活" "視窗出現 10 秒內行程異常終止 (結束碼: $($proc.ExitCode))"
    }

    # (f3) 使用者資料目錄寫入驗證
    if ($appDataExistedPrior) {
        $recentFiles = Get-ChildItem -Path $appDataPath -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -ge $launchTime }
        if ($recentFiles.Count -gt 0) {
            Record-Check $true "AppData 寫入驗證" "既有 AppData 目錄偵測到當次啟動更新的檔案 (共 $($recentFiles.Count) 個新寫入/更新項目)"
        } else {
            Record-Check $false "AppData 寫入驗證" "既有 AppData 目錄在啟動後未偵測到任何更新的檔案"
        }
    } else {
        if (Test-Path $appDataPath) {
            $files = Get-ChildItem -Path $appDataPath -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer }
            if ($files.Count -gt 0) {
                Record-Check $true "AppData 寫入驗證" "成功於 AppData 目錄建立使用者資料與檔案 (共 $($files.Count) 個檔案)"
            } else {
                Record-Check $false "AppData 寫入驗證" "已建立 AppData 目錄但無任何檔案寫入"
            }
        } else {
            Record-Check $false "AppData 寫入驗證" "應用程式未於 AppData 建立使用者資料夾: $appDataPath"
        }
    }

    # (g) 結束行程樹
    Write-Host "結束應用程式行程樹 (PID: $($proc.Id))..." -ForegroundColor Cyan
    taskkill.exe /PID $proc.Id /T /F 2>$null | Out-Null
    $swWait = [System.Diagnostics.Stopwatch]::StartNew()
    while ($swWait.Elapsed.TotalSeconds -lt 15) {
        $proc.Refresh()
        if ($proc.HasExited) { break }
        Start-Sleep -Milliseconds 500
    }
    Record-Check $proc.HasExited "行程樹終止" "已徹底終止應用程式與所有子程序"

    # (h) 移除 deny ACL
    Write-Host "移除解壓目錄 deny ACL..." -ForegroundColor Cyan
    & icacls.exe $extractTarget /remove:d "*$userSid" /q 2>$null | Out-Null
    $denyAclApplied = $false

    # (i) 執行前後快照比對
    $postSnapshot = Get-DirectorySnapshot $extractTarget
    $diffs = [System.Collections.Generic.List[string]]::new()

    foreach ($key in $postSnapshot.Keys) {
        if (-not $preSnapshot.ContainsKey($key)) {
            $diffs.Add("新增檔案: $key")
        } elseif ($postSnapshot[$key] -ne $preSnapshot[$key]) {
            $diffs.Add("檔案被修改: $key")
        }
    }
    foreach ($key in $preSnapshot.Keys) {
        if (-not $postSnapshot.ContainsKey($key)) {
            $diffs.Add("檔案被刪除: $key")
        }
    }

    if ($diffs.Count -eq 0) {
        Record-Check $true "解壓目錄零寫入" "解壓資料夾在執行前後檔案完全一致 (0 變動)"
    } else {
        Record-Check $false "解壓目錄零寫入" "解壓資料夾偵測到檔案變動：`n  $($diffs -join "`n  ")"
    }

} finally {
    # 確保 deny ACL 被移除（否則後續清理會失敗）
    if ($denyAclApplied) {
        & icacls.exe $extractTarget /remove:d "*$userSid" 2>$null | Out-Null
    }

    # 確保行程被終止
    if ($proc -and (-not $proc.HasExited)) {
        taskkill.exe /PID $proc.Id /T /F 2>$null | Out-Null
    }

    # (j) 清理目錄
    if (Test-Path $extractTarget) {
        Remove-Item -Path $extractTarget -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($appDataExistedPrior) {
        Write-Host "[清理說明] 保留既有使用者 AppData 目錄（執行前已存在）: $appDataPath" -ForegroundColor Gray
    } else {
        if (-not $KeepAppData -and (Test-Path $appDataPath)) {
            Write-Host "[清理說明] 清理當次測試新建之 AppData: $appDataPath" -ForegroundColor Gray
            Remove-Item -Path $appDataPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($checksPassed) {
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " 本機驗證全數通過！" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    exit 0
} else {
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " 本機驗證有項目未通過！" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    exit 1
}



