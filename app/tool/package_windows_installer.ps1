# Windows 安裝程式打包腳本 (epic-66 Issue 27)
# 功能：沿用 package_windows_zip.ps1 的暫存目錄，複檢依賴後以 Inno Setup 編譯安裝程式並產生 SHA256

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$StageDir,
    [string]$Version,
    [string]$OutDir = "build/windows_installer"
)

$ErrorActionPreference = "Stop"

# 1. 路徑基底（一律以腳本所在的 app/ 目錄為錨點）
$AppDir = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $AppDir "pubspec.yaml"))) {
    $AppDir = (Get-Item $PSScriptRoot).Parent.FullName
}
$zipScript = Join-Path $PSScriptRoot "package_windows_zip.ps1"
$issPath = Join-Path $AppDir "windows\packaging\elinkbook.iss"
$psExe = (Get-Process -Id $PID).Path

function Stop-Fail([string]$msg) {
    Write-Host "[錯誤] $msg" -ForegroundColor Red
    exit 1
}

# 2. 解析版本（-Version 或 pubspec.yaml；格式 主.次.修[+建置號]）
if ($Version) {
    $rawVersion = $Version.Trim()
} else {
    $versionLine = Get-Content (Join-Path $AppDir "pubspec.yaml") | Select-String -Pattern '^version:\s*([^\s]+)'
    if (-not $versionLine) { Stop-Fail "無法從 pubspec.yaml 解析 version" }
    $rawVersion = $versionLine.Matches.Groups[1].Value.Trim()
}
if ($rawVersion -notmatch '^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$') {
    Stop-Fail "版本格式不符（需為 主.次.修 或 主.次.修+建置號）: $rawVersion"
}
$appVersion = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
$buildNo = if ($Matches[4]) { $Matches[4] } else { "0" }
$versionInfo = "$appVersion.$buildNo"
$cleanVersion = $rawVersion -replace '\+', '-b'
$baseName = "elinkbook-$cleanVersion-windows-x64-setup"

# 3. 輸出目錄，並先清掉同名舊產物（失敗時不留看似成功的舊檔）
if (-not [System.IO.Path]::IsPathRooted($OutDir)) {
    $OutDir = Join-Path $AppDir $OutDir
}
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$setupPath = Join-Path $OutDir "$baseName.exe"
$shaPath = Join-Path $OutDir "$baseName.exe.sha256"
foreach ($stale in @($setupPath, $shaPath)) {
    if (Test-Path $stale) { Remove-Item $stale -Force }
}

# 4. 找 ISCC.exe
$isccCandidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { $iscc = $cmd.Source }
}
if (-not $iscc) {
    Stop-Fail "找不到 ISCC.exe。請先安裝：winget install --id JRSoftware.InnoSetup -e"
}
if (-not (Test-Path $issPath)) { Stop-Fail "找不到 Inno Setup 腳本: $issPath" }

# 5. 取得暫存目錄：給 -StageDir 就直接用，否則先跑 zip 腳本
if ($StageDir) {
    if (-not [System.IO.Path]::IsPathRooted($StageDir)) { $StageDir = Join-Path (Get-Location) $StageDir }
} else {
    $zipArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $zipScript)
    if ($SkipBuild) { $zipArgs += "-SkipBuild" }
    Write-Host "呼叫 package_windows_zip.ps1 組裝暫存目錄..." -ForegroundColor Cyan
    & $psExe @zipArgs
    if ($LASTEXITCODE -ne 0) { Stop-Fail "package_windows_zip.ps1 失敗 (結束碼: $LASTEXITCODE)" }
    $StageDir = Join-Path $AppDir "build\windows_zip\stage\elinkbook"
}
if (-not (Test-Path (Join-Path $StageDir "elinkbook.exe"))) {
    Stop-Fail "暫存目錄缺少 elinkbook.exe: $StageDir"
}

# 6. 永遠對暫存目錄複檢依賴（含三個 VC DLL）
Write-Host "複檢暫存目錄依賴..." -ForegroundColor Cyan
& $psExe -NoProfile -ExecutionPolicy Bypass -File $zipScript -CheckOnly $StageDir
if ($LASTEXITCODE -ne 0) { Stop-Fail "暫存目錄依賴檢查失敗，中止打包（不產出安裝程式）" }

# 7. 印出所用來源，避免誤用過期暫存目錄
$exeVersion = (Get-Item (Join-Path $StageDir "elinkbook.exe")).VersionInfo.FileVersion
Write-Host "暫存目錄: $StageDir" -ForegroundColor Cyan
Write-Host "elinkbook.exe 檔案版本: $exeVersion；安裝程式版本: $appVersion ($versionInfo)" -ForegroundColor Cyan

# 8. 編譯
& $iscc "/DAppVersion=$appVersion" "/DVersionInfoVersion=$versionInfo" "/DStageDir=$StageDir" "/DOutputDir=$OutDir" "/DOutputBaseFilename=$baseName" $issPath
if ($LASTEXITCODE -ne 0) { Stop-Fail "iscc 編譯失敗 (結束碼: $LASTEXITCODE)" }
if (-not (Test-Path $setupPath)) { Stop-Fail "iscc 結束碼 0 但找不到輸出檔: $setupPath" }

# 9. SHA256（格式同 zip：<大寫雜湊>  <檔名>，UTF-8 無 BOM）
# 部分環境的 PowerShell 5.1 沒有 Get-FileHash（zip 腳本同樣有此備援），改用 .NET
$hasher = [System.Security.Cryptography.SHA256]::Create()
$fileStream = [System.IO.File]::OpenRead($setupPath)
try {
    $hashHex = (-join ($hasher.ComputeHash($fileStream) | ForEach-Object { $_.ToString("X2") }))
} finally {
    $fileStream.Close()
    $hasher.Dispose()
}
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($shaPath, "$hashHex  $baseName.exe`n", $utf8NoBom)

$item = Get-Item $setupPath
Write-Host "============================================================" -ForegroundColor Green
Write-Host " 安裝程式打包成功！" -ForegroundColor Green
Write-Host " 輸出檔案: $setupPath" -ForegroundColor Green
Write-Host " 檔案大小: $([math]::Round($item.Length / 1MB, 2)) MB" -ForegroundColor Green
Write-Host " SHA256:   $hashHex" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
exit 0
