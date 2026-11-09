# Windows 整合測試跑測腳本 (epic-66 Issue 13)
# 行為特點：單份依序執行、行程樹逾時強制終止、開跑前殘留防護、記憶體門檻熔斷

[CmdletBinding()]
param(
    [string]$Suite = "integration_test/windows_smoke_suite.txt",
    [int]$TimeoutSec = 420,
    [int]$MinFreeMB = 4096
)

$ErrorActionPreference = "Stop"

# 1. 路徑基底解析（一律以腳本所在的 app/ 目錄為錨點）
$AppDir = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $AppDir "pubspec.yaml"))) {
    # 若 PSScriptRoot 不是 app/tool，向上尋找包含 pubspec.yaml 的 app 目錄
    $AppDir = (Get-Item $PSScriptRoot).Parent.FullName
}

$BuildSmokeDir = Join-Path $AppDir "build\windows_smoke"
if (-not (Test-Path $BuildSmokeDir)) {
    New-Item -ItemType Directory -Path $BuildSmokeDir -Force | Out-Null
}

$LockPath = Join-Path $BuildSmokeDir ".lock"

# 2. 獨佔鎖檔機制（以 .NET FileShare.None 建立系統級互斥鎖，避免 Windows PID 重用誤判）
$lockStream = $null
try {
    $lockStream = [System.IO.File]::Open(
        $LockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    $writer = [System.IO.StreamWriter]::new($lockStream)
    $writer.WriteLine("PID=$PID; StartTime=$((Get-Date).ToString('o'))")
    $writer.Flush()
} catch {
    Write-Host "[錯誤] 已有另一份跑測腳本在執行中（無法取得鎖檔: $LockPath）。" -ForegroundColor Red
    Write-Host "依專案硬性約束，Windows 整合測試一次只准一份執行，禁止並行！" -ForegroundColor Red
    exit 1
}

try {
    # 3. 殘留進程檢查函數
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

    # 4. 可用記憶體量測函數 (MB)
    function Get-FreeMemoryMB {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            return [math]::Round($os.FreePhysicalMemory / 1024)
        }
        return 99999
    }

    # 5. 開跑前殘留進程檢查（有就中止並列出，不自行終止）
    $initialResiduals = @(Get-ResidualProcesses)  # 以 @() 包成陣列：函式 return 單一元素時會被攤平成物件,.Count 會失準
    if ($initialResiduals.Count -gt 0) {
        Write-Host "[錯誤] 偵測到下列殘留測試或建置行程，為避免記憶體耗盡或測試衝突，已中止執行：" -ForegroundColor Red
        foreach ($r in $initialResiduals) {
            Write-Host ("  - [PID: {0}] {1} (Cmd: {2})" -f $r.Id, $r.Name, $r.CommandLine) -ForegroundColor Yellow
        }
        Write-Host "請手動確認並清理上述行程後再重新執行。" -ForegroundColor Red
        exit 1
    }

    # 6. 解析測試清單檔案
    $suiteFilePath = $Suite
    if (-not [System.IO.Path]::IsPathRooted($suiteFilePath)) {
        $suiteFilePath = Join-Path $AppDir $Suite
        if (-not (Test-Path $suiteFilePath)) {
            $suiteFilePath = Join-Path (Get-Location) $Suite
        }
    }

    if (-not (Test-Path $suiteFilePath)) {
        Write-Host "[錯誤] 找不到測試清單檔案: $suiteFilePath" -ForegroundColor Red
        exit 1
    }

    $rawLines = Get-Content $suiteFilePath -Encoding UTF8
    $testFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $rawLines) {
        $trimmed = $line.Trim()
        if ($trimmed -and -not $trimmed.StartsWith("#")) {
            $testFiles.Add($trimmed)
        }
    }

    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Windows 整合測試冒煙套件 (總計 $($testFiles.Count) 支測試)" -ForegroundColor Cyan
    Write-Host " 清單: $suiteFilePath" -ForegroundColor Gray
    Write-Host " 逾時: $TimeoutSec 秒 | 記憶體門檻: $MinFreeMB MB" -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Cyan

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    # 7. 逐支依序執行
    for ($i = 0; $i -lt $testFiles.Count; $i++) {
        $testFile = $testFiles[$i]
        $testName = [System.IO.Path]::GetFileNameWithoutExtension($testFile)
        $idxStr = ("[{0}/{1}]" -f ($i + 1), $testFiles.Count)

        # 記憶體檢查（低於門檻先等 10 秒緩衝，仍不足才中止）
        $freeMB = Get-FreeMemoryMB
        if ($freeMB -lt $MinFreeMB) {
            Write-Host "$idxStr 系統可用記憶體 ($freeMB MB) 低於門檻 ($MinFreeMB MB)，等待 10 秒回收..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
            $freeMB = Get-FreeMemoryMB
            if ($freeMB -lt $MinFreeMB) {
                Write-Host "[中止] 可用記憶體不足 ($freeMB MB < $MinFreeMB MB)，已停止後續測試以防系統崩潰。" -ForegroundColor Red
                $results.Add([PSCustomObject]@{
                    Name = $testFile
                    Status = "MEMORY_ABORT"
                    Detail = "可用記憶體不足: $freeMB MB"
                })
                break
            }
        }

        $logPath = Join-Path $BuildSmokeDir "$($testName).log"

        # 啟動測試子行程
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/c flutter test `"$testFile`" -d windows > `"$logPath`" 2>&1"
        $psi.WorkingDirectory = $AppDir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)

        $timedOut = $false
        $finished = $proc.WaitForExit($TimeoutSec * 1000)

        if (-not $finished) {
            $timedOut = $true
            # 逾時強制殺死整棵行程樹 (/T /F)
            taskkill.exe /PID $proc.Id /T /F 2>$null | Out-Null
            $status = "TIMEOUT"
            $lastLine = "逾時超過 $TimeoutSec 秒"
        } else {
            $exitCode = $proc.ExitCode
            $lastLine = ""
            if (Test-Path $logPath) {
                $lines = Get-Content $logPath -Encoding UTF8 -ErrorAction SilentlyContinue
                for ($k = $lines.Count - 1; $k -ge 0; $k--) {
                    $l = $lines[$k].Trim()
                    if ($l) {
                        $lastLine = $l
                        break
                    }
                }
            }

            if ($exitCode -eq 0) {
                $status = "PASS"
            } else {
                $status = "FAIL"
            }
        }

        # 等候 elinkbook.exe 退出（上限 15 秒輪詢；超時記錄警示並強制清除本測試產生的殘留）
        $waitDeadline = (Get-Date).AddSeconds(15)
        while ((Get-Process -Name "elinkbook" -ErrorAction SilentlyContinue) -and (Get-Date) -lt $waitDeadline) {
            Start-Sleep -Milliseconds 500
        }
        if (Get-Process -Name "elinkbook" -ErrorAction SilentlyContinue) {
            Write-Warning "等待 15 秒後 elinkbook.exe 仍殘留，執行強制清理..."
            taskkill.exe /IM elinkbook.exe /F 2>$null | Out-Null
        }

        # 終端輸出格式：名稱 通過/失敗/逾時 ::（最後一行進度）
        $statusDisplay = switch ($status) {
            "PASS"    { "[通過]" }
            "FAIL"    { "[失敗]" }
            "TIMEOUT" { "[逾時]" }
            Default   { "[$status]" }
        }
        $color = switch ($status) {
            "PASS"    { [ConsoleColor]::Green }
            "FAIL"    { [ConsoleColor]::Red }
            "TIMEOUT" { [ConsoleColor]::Yellow }
            Default   { [ConsoleColor]::White }
        }

        Write-Host ("{0} {1,-38} {2} :: {3}" -f $idxStr, $testFile, $statusDisplay, $lastLine) -ForegroundColor $color

        $results.Add([PSCustomObject]@{
            Name = $testFile
            Status = $status
            Detail = $lastLine
        })
    }

    # 8. 最終結果彙總
    Write-Host "------------------------------------------------------------" -ForegroundColor Gray
    $passCount = @($results | Where-Object { $_.Status -eq "PASS" }).Count
    $failCount = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
    $timeoutCount = @($results | Where-Object { $_.Status -eq "TIMEOUT" }).Count
    $abortCount = @($results | Where-Object { $_.Status -eq "MEMORY_ABORT" }).Count

    Write-Host ("測試結果彙總: 通過 {0} / 失敗 {1} / 逾時 {2} / 中止 {3} (總計 {4})" -f `
        $passCount, $failCount, $timeoutCount, $abortCount, $results.Count) -ForegroundColor `
        ($(if ($failCount -eq 0 -and $timeoutCount -eq 0 -and $abortCount -eq 0) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }))

    if ($failCount -gt 0 -or $timeoutCount -gt 0 -or $abortCount -gt 0) {
        exit 1
    } else {
        exit 0
    }
} finally {
    if ($lockStream) {
        $lockStream.Close()
        $lockStream.Dispose()
    }
}
