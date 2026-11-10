# Windows 免安裝 zip 打包腳本 (epic-66 Issue 14)
# 功能：建置 Release、組裝暫存、複製 VC DLL、依賴檢查、打包 zip、產生 SHA256

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$OutDir = "build/windows_zip",
    [string]$CheckOnly
)

$ErrorActionPreference = "Stop"

# 1. 路徑基底解析（一律以腳本所在的 app/ 目錄為錨點）
$AppDir = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $AppDir "pubspec.yaml"))) {
    $AppDir = (Get-Item $PSScriptRoot).Parent.FullName
}

# 取得 dumpbin.exe 路徑
function Get-DumpbinPath {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { $vswhere = "vswhere.exe" }
    $vsPath = & $vswhere -latest -products * -property installationPath
    if (-not $vsPath -or -not (Test-Path $vsPath)) {
        throw "找不到 Visual Studio 安裝路徑"
    }

    # 編譯器工具版本讀取 Microsoft.VCToolsVersion.default.txt（不得誤用 Redist 版本號）
    $toolsVerFile = Join-Path $vsPath "VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt"
    if (Test-Path $toolsVerFile) {
        $toolsVer = (Get-Content $toolsVerFile).Trim()
        $dumpbin = Join-Path $vsPath "VC\Tools\MSVC\$toolsVer\bin\Hostx64\x64\dumpbin.exe"
        if (Test-Path $dumpbin) { return $dumpbin }
    }

    # 退而取 VC\Tools\MSVC\* 中版本最新的目錄
    $msvcDirs = Get-Item (Join-Path $vsPath "VC\Tools\MSVC\*") -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($dir in $msvcDirs) {
        $dumpbin = Join-Path $dir.FullName "bin\Hostx64\x64\dumpbin.exe"
        if (Test-Path $dumpbin) { return $dumpbin }
    }

    throw "在 Visual Studio 安裝路徑下找不到 dumpbin.exe"
}

# 依賴靜態檢查函式
function Test-StagedDependencies([string]$TargetDir) {
    if (-not (Test-Path $TargetDir)) {
        Write-Host "[錯誤] 指定檢查目錄不存在: $TargetDir" -ForegroundColor Red
        return $false
    }

    $errors = [System.Collections.Generic.List[string]]::new()

    # 防禦性斷言：msvcp140.dll、vcruntime140.dll、vcruntime140_1.dll 三個檔案必須實體存在於目錄根
    $requiredVCDlls = @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")
    foreach ($dll in $requiredVCDlls) {
        $dllPath = Join-Path $TargetDir $dll
        if (-not (Test-Path $dllPath)) {
            $errors.Add("[實體檔案缺失] 目錄根缺少必要 VC 執行階段: $dll")
        }
    }

    $dumpbin = $null
    try {
        $dumpbin = Get-DumpbinPath
    } catch {
        Write-Host "[錯誤] $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    $binaries = Get-ChildItem -Path $TargetDir -Recurse -Include "*.exe", "*.dll"
    if ($binaries.Count -eq 0) {
        Write-Host "[錯誤] 目錄內未找到任何 .exe 或 .dll 檔案: $TargetDir" -ForegroundColor Red
        return $false
    }

    $system32 = Join-Path $env:SystemRoot "System32"
    $vcDllRegex = '^(msvcp140.*|vcruntime140.*|concrt140|vccorlib140)\.dll$'

    foreach ($bin in $binaries) {
        $dumpOut = & $dumpbin /dependents $bin.FullName 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $dumpOut) {
            $errors.Add("dumpbin 執行失敗: $($bin.Name)")
            continue
        }

        # 抓取 "Image has the following dependencies:" 底下的 dll 清單
        $inDepsSection = $false
        foreach ($line in $dumpOut) {
            if ($line -match 'Image has the following dependencies:') {
                $inDepsSection = $true
                continue
            }
            if ($inDepsSection) {
                if ($line -match '^\s+Summary\s*$') {
                    $inDepsSection = $false
                    break
                }
                if ($line -match '^\s+([a-zA-Z0-9_\-\.]+\.dll)\s*$') {
                    $depDll = $Matches[1].Trim()
                    
                    # (a) api-ms-win-* 或 ext-ms-win-* 視為 Windows 內建
                    if ($depDll -match '^(api|ext)-ms-win-') {
                        continue
                    }

                    # (b) 同目錄（$TargetDir 或與二進位同目錄）內存在
                    $inTargetRoot = Test-Path (Join-Path $TargetDir $depDll)
                    $inBinDir = Test-Path (Join-Path $bin.DirectoryName $depDll)
                    if ($inTargetRoot -or $inBinDir) {
                        continue
                    }

                    # (d) 例外：VC 執行階段即使在 System32 也必須在目錄內
                    if ($depDll -match $vcDllRegex) {
                        $errors.Add("$($bin.Name) -> $depDll (VC 執行階段必須隨附在應用目錄，不可依賴系統目錄)")
                        continue
                    }

                    # (c) 存在於 System32
                    if (Test-Path (Join-Path $system32 $depDll)) {
                        continue
                    }

                    # (e) 其他找不到的依賴一律失敗
                    $errors.Add("$($bin.Name) -> $depDll (找不到相依 DLL)")
                }
            }
        }
    }

    if ($errors.Count -gt 0) {
        Write-Host "============================================================" -ForegroundColor Red
        Write-Host " 依賴靜態檢查失敗！發現 $($errors.Count) 項問題：" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host "  - $err" -ForegroundColor Yellow
        }
        Write-Host "============================================================" -ForegroundColor Red
        return $false
    }

    Write-Host "[依賴檢查通過] 已檢查 $($binaries.Count) 個二進位檔，無缺失依賴。" -ForegroundColor Green
    return $true
}

# 單獨檢查模式 (-CheckOnly <目錄>)
if ($CheckOnly) {
    $checkDir = $CheckOnly
    if (-not [System.IO.Path]::IsPathRooted($checkDir)) {
        $checkDir = Join-Path (Get-Location) $checkDir
    }
    $passed = Test-StagedDependencies $checkDir
    if ($passed) {
        exit 0
    } else {
        exit 1
    }
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

# 3. 可用記憶體量測函數 (MB)
function Get-FreeMemoryMB {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        return [math]::Round($os.FreePhysicalMemory / 1024)
    }
    return 99999
}

# 開跑前檢查殘留進程與記憶體
$initialResiduals = @(Get-ResidualProcesses)
if ($initialResiduals.Count -gt 0) {
    Write-Host "[錯誤] 偵測到下列殘留測試或建置行程，為避免記憶體耗盡或建置衝突，已中止執行：" -ForegroundColor Red
    foreach ($r in $initialResiduals) {
        Write-Host ("  - [PID: {0}] {1} (Cmd: {2})" -f $r.Id, $r.Name, $r.CommandLine) -ForegroundColor Yellow
    }
    Write-Host "請手動確認並清理上述行程後再重新執行。" -ForegroundColor Red
    exit 1
}

$freeMB = Get-FreeMemoryMB
if ($freeMB -lt 4096) {
    Write-Host "[警告] 系統可用記憶體 ($freeMB MB) 低於門檻 (4096 MB)，等待 10 秒回收..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    $freeMB = Get-FreeMemoryMB
    if ($freeMB -lt 4096) {
        Write-Host "[錯誤] 系統可用實體記憶體不足 4 GB ($freeMB MB)，中止建置。" -ForegroundColor Red
        exit 1
    }
}

# 解析版本號
$pubspecPath = Join-Path $AppDir "pubspec.yaml"
$versionLine = Get-Content $pubspecPath | Select-String -Pattern '^version:\s*([^\s]+)'
if (-not $versionLine) {
    Write-Host "[錯誤] 無法從 pubspec.yaml 解析 version" -ForegroundColor Red
    exit 1
}
$rawVersion = $versionLine.Matches.Groups[1].Value.Trim()
$cleanVersion = $rawVersion -replace '\+', '-b'
$zipBaseName = "elinkbook-$cleanVersion-windows-x64"

# 解析輸出路徑
if (-not [System.IO.Path]::IsPathRooted($OutDir)) {
    $OutDir = Join-Path $AppDir $OutDir
}
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

# 建置前先清掉上一次的正式 zip 與 .sha256，避免本次失敗時殘留看似成功的舊產物
foreach ($stale in @("$zipBaseName.zip", "$zipBaseName.zip.sha256", "$zipBaseName.tmp.zip")) {
    $stalePath = Join-Path $OutDir $stale
    if (Test-Path $stalePath) { Remove-Item $stalePath -Force }
}

# 執行 flutter build windows --release
if (-not $SkipBuild) {
    Write-Host "執行 flutter build windows --release..." -ForegroundColor Cyan
    Push-Location $AppDir
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[錯誤] flutter build windows --release 失敗 (結束碼: $LASTEXITCODE)" -ForegroundColor Red
            exit $LASTEXITCODE
        }
    } finally {
        Pop-Location
    }
}

# 準備暫存目錄
$stageRootDir = Join-Path $OutDir "stage"
$stageAppDir = Join-Path $stageRootDir "elinkbook"

if (Test-Path $stageRootDir) {
    Remove-Item $stageRootDir -Recurse -Force
}
New-Item -ItemType Directory -Path $stageAppDir -Force | Out-Null

$releaseDir = Join-Path $AppDir "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
    Write-Host "[錯誤] 找不到 Release 輸出目錄: $releaseDir" -ForegroundColor Red
    exit 1
}

Write-Host "複製 Release 輸出至暫存目錄..." -ForegroundColor Cyan
Copy-Item -Path (Join-Path $releaseDir "*") -Destination $stageAppDir -Recurse -Exclude "*.pdb","*.lib","*.exp","*.ilk","dartjni.dll"
# 防禦性清理：若仍存在 dartjni.dll 則刪除（jni 為 path_provider_android 遞移相依，Windows 端不使用且依賴不存在之 jvm.dll）
if (Test-Path "$stageAppDir\dartjni.dll") {
    Remove-Item "$stageAppDir\dartjni.dll" -Force
}

# 尋找 Visual Studio 與複製 VC DLL
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    $vswhere = "vswhere.exe"
}
$vsPath = & $vswhere -latest -products * -property installationPath
if (-not $vsPath -or -not (Test-Path $vsPath)) {
    Write-Host "[錯誤] 找不到 Visual Studio 安裝路徑" -ForegroundColor Red
    exit 1
}

$redistVerFile = Join-Path $vsPath "VC\Auxiliary\Build\Microsoft.VCRedistVersion.default.txt"
if (-not (Test-Path $redistVerFile)) {
    Write-Host "[錯誤] 找不到 VCRedistVersion.default.txt: $redistVerFile" -ForegroundColor Red
    exit 1
}
$redistVersion = (Get-Content $redistVerFile).Trim()
$crtDir = Join-Path $vsPath "VC\Redist\MSVC\$redistVersion\x64\Microsoft.VC143.CRT"
if (-not (Test-Path $crtDir)) {
    Write-Host "[錯誤] 找不到 VC CRT 目錄: $crtDir" -ForegroundColor Red
    exit 1
}

$requiredVCDlls = @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")
foreach ($dll in $requiredVCDlls) {
    $srcDll = Join-Path $crtDir $dll
    if (-not (Test-Path $srcDll)) {
        Write-Host "[錯誤] 在 Redist 目錄找不到必備 DLL: $srcDll" -ForegroundColor Red
        exit 1
    }
    Copy-Item $srcDll -Destination $stageAppDir -Force
}

# 複製 README.txt
$readmeSrc = Join-Path $AppDir "windows\packaging\README.txt"
if (-not (Test-Path $readmeSrc)) {
    Write-Host "[錯誤] 找不到 README 範本: $readmeSrc" -ForegroundColor Red
    exit 1
}
Copy-Item $readmeSrc -Destination (Join-Path $stageAppDir "README.txt") -Force

# 依賴靜態檢查（在壓縮前執行）
Write-Host "執行暫存目錄依賴靜態檢查..." -ForegroundColor Cyan
$depsPassed = Test-StagedDependencies $stageAppDir
if (-not $depsPassed) {
    Write-Host "[錯誤] 暫存目錄依賴檢查失敗，中止打包！" -ForegroundColor Red
    exit 1
}

# 壓縮為 zip（使用暫存檔名，全部驗證通過才轉為正式檔名）
# 明確調用 Windows 內建 bsdtar，避免 PATH 中 Cygwin/MSYS GNU tar 把 C: 當成遠端主機
$tarExe = Join-Path $env:SystemRoot "System32\tar.exe"
if (-not (Test-Path $tarExe)) {
    $tarExe = "tar.exe"
}

$tempZipPath = Join-Path $OutDir "$zipBaseName.tmp.zip"
$finalZipPath = Join-Path $OutDir "$zipBaseName.zip"
$finalShaPath = Join-Path $OutDir "$zipBaseName.zip.sha256"

if (Test-Path $tempZipPath) { Remove-Item $tempZipPath -Force }
if (Test-Path $finalZipPath) { Remove-Item $finalZipPath -Force }
if (Test-Path $finalShaPath) { Remove-Item $finalShaPath -Force }

Write-Host "壓縮暫存 zip: $tempZipPath..." -ForegroundColor Cyan
& $tarExe -a -c -f $tempZipPath -C $stageRootDir elinkbook
if ($LASTEXITCODE -ne 0) {
    Write-Host "[錯誤] tar 壓縮失敗 (結束碼: $LASTEXITCODE)" -ForegroundColor Red
    if (Test-Path $tempZipPath) { Remove-Item $tempZipPath -Force }
    exit 1
}

# 驗證 zip 清單
Write-Host "驗證 zip 內容清單..." -ForegroundColor Cyan
$zipEntries = & $tarExe -tf $tempZipPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "[錯誤] tar -tf 讀取失敗" -ForegroundColor Red
    if (Test-Path $tempZipPath) { Remove-Item $tempZipPath -Force }
    exit 1
}

$requiredEntries = @(
    "elinkbook/elinkbook.exe",
    "elinkbook/msvcp140.dll",
    "elinkbook/vcruntime140.dll",
    "elinkbook/vcruntime140_1.dll",
    "elinkbook/data/foliate/main.js",
    "elinkbook/README.txt"
)

foreach ($req in $requiredEntries) {
    $matched = $zipEntries | Where-Object { ($_ -replace '\\', '/') -ieq $req }
    if (-not $matched) {
        Write-Host "[錯誤] zip 缺少必要項目: $req" -ForegroundColor Red
        if (Test-Path $tempZipPath) { Remove-Item $tempZipPath -Force }
        exit 1
    }
}

$backslashEntries = $zipEntries | Where-Object { $_ -match '\\' }
if ($backslashEntries) {
    Write-Host "[錯誤] zip 包含反斜線路徑分隔符: $($backslashEntries -join ', ')" -ForegroundColor Red
    if (Test-Path $tempZipPath) { Remove-Item $tempZipPath -Force }
    exit 1
}

$pdbEntries = $zipEntries | Where-Object { $_ -match '\.pdb$' }
if ($pdbEntries) {
    Write-Host "[錯誤] zip 包含 pdb 除錯符號: $($pdbEntries -join ', ')" -ForegroundColor Red
    if (Test-Path $tempZipPath) { Remove-Item $tempZipPath -Force }
    exit 1
}

# 驗證通過，轉為正式檔名並計算 SHA256
Move-Item -Path $tempZipPath -Destination $finalZipPath -Force

function Get-Sha256Hex([string]$filePath) {
    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        return (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
    }
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $fileStream = [System.IO.File]::OpenRead($filePath)
    try {
        $hashBytes = $hasher.ComputeHash($fileStream)
        return (-join ($hashBytes | ForEach-Object { $_.ToString("X2") }))
    } finally {
        $fileStream.Close()
        $hasher.Dispose()
    }
}

$hashHex = Get-Sha256Hex $finalZipPath
$leafName = [System.IO.Path]::GetFileName($finalZipPath)
$shaContent = "$hashHex  $leafName`n"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($finalShaPath, $shaContent, $utf8NoBom)

$finalZipItem = Get-Item $finalZipPath
$fileCount = ($zipEntries | Where-Object { -not $_.EndsWith('/') }).Count
Write-Host "============================================================" -ForegroundColor Green
Write-Host " 打包成功！" -ForegroundColor Green
Write-Host " 輸出檔案: $finalZipPath" -ForegroundColor Green
Write-Host " 檔案大小: $([math]::Round($finalZipItem.Length / 1MB, 2)) MB" -ForegroundColor Green
Write-Host " 內容筆數: $fileCount 檔 ($($zipEntries.Count) 項目)" -ForegroundColor Green
Write-Host " SHA256:   $hashHex" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

exit 0

