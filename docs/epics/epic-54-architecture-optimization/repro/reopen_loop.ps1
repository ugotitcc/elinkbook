# 重複「從書架開同一本書 → 等結果 → 關閉」，記錄每輪是成功還是「開書逾時」。
# 用法：.\reopen_loop.ps1 -Rounds 8 -Label mine
param([int]$Rounds = 8, [string]$Label = 'x', [string]$Device = 'TCE70P24B2202374', [switch]$ColdStart, [int]$Turns = 0)
$pkg = 'cc.ugotit.elinkbook'
function Dev { & adb.exe -s $Device @args 2>&1 }
function Dump { Dev shell "uiautomator dump /sdcard/ui.xml" | Out-Null; (Dev shell "cat /sdcard/ui.xml") -join "`n" }
function TapNode([string]$pat) {
  $m = [regex]::Match((Dump), '<node [^>]*?(?:content-desc|text)="' + $pat + '[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  if (-not $m.Success) { return $false }
  Dev shell "input tap $([int](([int]$m.Groups[1].Value+[int]$m.Groups[3].Value)/2)) $([int](([int]$m.Groups[2].Value+[int]$m.Groups[4].Value)/2))" | Out-Null; return $true
}
if ($ColdStart) {
  Dev shell "am force-stop $pkg" | Out-Null; Dev shell "input keyevent KEYCODE_HOME" | Out-Null; Start-Sleep 2
  Dev shell "am start -n $pkg/.MainActivity" | Out-Null
}
# 等書架
$t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt 150 -and -not ((Dump) -match '搜尋書名或作者')) { Start-Sleep 3 }
Start-Sleep 5
$rows = @()
for ($i = 1; $i -le $Rounds; $i++) {
  $x = Dump
  if ($x -notmatch '搜尋書名或作者') { Dev shell "input keyevent KEYCODE_BACK" | Out-Null; Start-Sleep 3 }
  $opened = TapNode '[^"]{1,40}&#10;\d+%'
  $t1 = Get-Date; $res = 'none'
  while (((Get-Date) - $t1).TotalSeconds -lt 70) {
    $d = Dump
    if ($d -match '隱藏工具列|加入此頁書籤') { $res = 'OK'; break }
    if ($d -match '開書逾時') { $res = 'TIMEOUT'; break }
    Start-Sleep 2
  }
  $sec = [math]::Round(((Get-Date) - $t1).TotalSeconds, 1)
  $rows += [pscustomobject]@{ Round = $i; Opened = $opened; Result = $res; Sec = $sec }
  Write-Output ("round {0}: opened={1} result={2} {3}s" -f $i, $opened, $res, $sec)
  if ($res -eq 'OK') { for ($k = 0; $k -lt $Turns; $k++) { Dev shell "input tap 1250 900" | Out-Null; Start-Sleep 2 }; Start-Sleep 3; Dev shell "input tap 52 146" | Out-Null; Start-Sleep 4 } else { Dev shell "input keyevent KEYCODE_BACK" | Out-Null; Start-Sleep 3 }
}
"[$Label] OK=" + ($rows | Where-Object Result -eq 'OK').Count + " TIMEOUT=" + ($rows | Where-Object Result -eq 'TIMEOUT').Count + " none=" + ($rows | Where-Object Result -eq 'none').Count
