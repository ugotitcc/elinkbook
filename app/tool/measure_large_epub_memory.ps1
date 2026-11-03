$OutputFile = "app/build/large_epub_memory.csv"
$DurationSec = 90

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$records = [System.Collections.Generic.List[PSCustomObject]]::new()
$maxApp = 0
$maxWv = 0
$maxTotal = 0

Write-Host "記憶體取樣啟動，監控中（最長 $DurationSec 秒）..."

while ($sw.Elapsed.TotalSeconds -lt $DurationSec) {
    $appProcs = Get-Process -Name "elinkbook" -ErrorAction SilentlyContinue
    $wvProcs = Get-Process -Name "msedgewebview2" -ErrorAction SilentlyContinue

    if ($appProcs -or $wvProcs) {
        $appBytes = if ($appProcs) { ($appProcs | Measure-Object -Property WorkingSet64 -Sum).Sum } else { 0 }
        $wvBytes = if ($wvProcs) { ($wvProcs | Measure-Object -Property WorkingSet64 -Sum).Sum } else { 0 }

        $appMB = [math]::Round($appBytes / 1MB, 2)
        $wvMB = [math]::Round($wvBytes / 1MB, 2)
        $totalMB = [math]::Round(($appBytes + $wvBytes) / 1MB, 2)

        if ($appMB -gt $maxApp) { $maxApp = $appMB }
        if ($wvMB -gt $maxWv) { $maxWv = $wvMB }
        if ($totalMB -gt $maxTotal) { $maxTotal = $totalMB }

        $records.Add([PSCustomObject]@{
            ElapsedSec = [math]::Round($sw.Elapsed.TotalSeconds, 2)
            AppMB = $appMB
            WebView2MB = $wvMB
            TotalMB = $totalMB
            AppCount = if ($appProcs) { ($appProcs | Measure-Object).Count } else { 0 }
            WebView2Count = if ($wvProcs) { ($wvProcs | Measure-Object).Count } else { 0 }
        })
    }
    Start-Sleep -Milliseconds 100
}

if ($records.Count -gt 0) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $records | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding utf8
    Write-Host "取樣結束，共 $($records.Count) 筆記錄。"
    Write-Host "App 尖峰: $maxApp MB | WebView2 尖峰: $maxWv MB | 合計尖峰: $maxTotal MB"
} else {
    Write-Host "未偵測到程序執行。"
}
