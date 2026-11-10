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
Copy-Item -Path (Join-Path $releaseDir "*") -Destination $stageAppDir -Recurse -Exclude "*.pdb","*.lib","*.exp","*.ilk"

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
[System.IO.File]::WriteAllText($finalShaPath, $shaContent, [System.Text.Encoding]::UTF8)

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

