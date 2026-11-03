# 量測 elinkBook（Windows）及其 WebView2 子程序的記憶體（工作集），輸出原始時序 CSV。
#
# 只計入「App 程序及其子孫程序」，不計入系統上其他程式的 msedgewebview2.exe
# （Edge、其他 WebView2 App 也會有同名程序；全系統加總會把它們混進來，
# 見 reviews/review-issue-2.md Important 1）。
#
# 用法（在 app/，PowerShell）：
#   .\tool\measure_large_epub_memory.ps1 -Seconds 240 -OutFile build\large_epub_memory.csv
# 先執行本腳本，再啟動 App 並操作；腳本會等 App 程序出現才開始計時與取樣。
#
# 取樣：每約 0.1 秒讀已知程序的工作集；每 1 秒重掃一次子孫程序（補新生的 WebView2 程序，
# 新程序最多晚 1 秒才被納入）。CSV 欄位：ElapsedSec,AppMB,WebView2MB,TotalMB,WebView2Count。
param(
    [int]$Seconds = 240,
    [string]$OutFile = "build/large_epub_memory.csv",
    [string]$RootProcessName = "elinkbook",
    [int]$WaitForAppSeconds = 120
)

function Get-ProcessTree([int]$RootId) {
    # 以 ParentProcessId 反覆展開，回傳根程序與全部子孫程序的 PID。
    $all = Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId
    $ids = New-Object System.Collections.Generic.HashSet[int]
    [void]$ids.Add($RootId)
    do {
        $before = $ids.Count
        foreach ($p in $all) {
            if ($ids.Contains([int]$p.ParentProcessId)) { [void]$ids.Add([int]$p.ProcessId) }
        }
    } while ($ids.Count -ne $before)
    return , ([int[]]$ids)
}

Write-Host "等待 $RootProcessName 程序出現（最長 $WaitForAppSeconds 秒）..."
$deadline = (Get-Date).AddSeconds($WaitForAppSeconds)
$root = $null
while ((Get-Date) -lt $deadline -and -not $root) {
    $root = Get-Process -Name $RootProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $root) { Start-Sleep -Milliseconds 200 }
}
if (-not $root) { Write-Host "未偵測到 $RootProcessName 程序，結束。"; exit 1 }

Write-Host "開始取樣：根程序 PID $($root.Id)，共 $Seconds 秒。"
$ids = Get-ProcessTree $root.Id
$lastScan = Get-Date
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$records = New-Object System.Collections.Generic.List[object]
$maxApp = 0.0; $maxWv = 0.0; $maxTotal = 0.0

while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    if (((Get-Date) - $lastScan).TotalSeconds -ge 1) { $ids = Get-ProcessTree $root.Id; $lastScan = Get-Date }
    $procs = Get-Process -Id $ids -ErrorAction SilentlyContinue
    $app = 0.0; $wv = 0.0; $wvCount = 0
    foreach ($p in $procs) {
        if ($p.Name -eq $RootProcessName) { $app += $p.WorkingSet64 / 1MB }
        elseif ($p.Name -eq "msedgewebview2") { $wv += $p.WorkingSet64 / 1MB; $wvCount++ }
    }
    $total = $app + $wv
    if ($app -gt $maxApp) { $maxApp = $app }
    if ($wv -gt $maxWv) { $maxWv = $wv }
    if ($total -gt $maxTotal) { $maxTotal = $total }
    $records.Add([PSCustomObject]@{
        ElapsedSec    = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        AppMB         = [math]::Round($app, 1)
        WebView2MB    = [math]::Round($wv, 1)
        TotalMB       = [math]::Round($total, 1)
        WebView2Count = $wvCount
    })
    Start-Sleep -Milliseconds 20
}

$dir = Split-Path -Parent $OutFile
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$records | Export-Csv -Path $OutFile -NoTypeInformation -Encoding utf8
Write-Host "取樣結束，共 $($records.Count) 筆，已存到 $OutFile。"
Write-Host ("App 尖峰 {0:N0} MB；WebView2（App 子孫）尖峰 {1:N0} MB；同時合計尖峰 {2:N0} MB" -f $maxApp, $maxWv, $maxTotal)
