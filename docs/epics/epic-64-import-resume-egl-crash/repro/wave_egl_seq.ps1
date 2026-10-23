# epic-64 重現腳本：WAVE 上「開過閱讀器（WebView）後，離開 App 再回來」的黑畫面／EGL_BAD_ACCESS
#
# 需求：USB 連線的 WAVE（Mobiscribe，Android 12）、debug 版 APK（要能 uiautomator dump）、PowerShell 7、adb。
# 座標是 WAVE 1404x1872 的實測值（來源按鈕 1269,147；選擇檔案 702,357；選擇器第一列 352,822）。
#
# 用法：.\wave_egl_seq.ps1 -Seq HRH -Label name
#   步驟字元：
#     R = 開一本書（優先「elinkBook 範例 EPUB」，否則書架第一本）→ 等閱讀器出現 → 關閉
#     P = 來源 →「選擇檔案」→ 選擇器選第一個檔 → 返回 App（App 內開，不是 adb 開）
#     H = 按 Home → 5 秒 → 重新帶回 App
#     F = 書架開關「排序與檢視」面板 8 次（人為製造約 16 個畫面；診斷用，修法驗證不要用）
#   判定：每步結束後看 logcat 有無 EGL_BAD_ACCESS、行程是否換掉、畫面是否全白／全黑。
#
# 已知結果（2026-10-23，WAVE，修法前）：
#   HRH → 第 3 步紅燈（2/2）；PRP → 第 3 步紅燈（1/1）；RPRP → 第 4 步紅燈（2/2）
#   HRFH → 全綠（2/2）；PP…、RP、RRRRP → 全綠
# 修法後（platform_view_frame_flush）：HRH 綠 2/2；PRP 綠 1/1；反覆「開閱讀器＋選擇器」8 輪綠 1/1。
# 輸出（截圖、log）寫到 $env:TEMP\elink_repro\<Label>。
param([string]$Seq = 'RPRP', [string]$Label = 'seq', [string]$Device = 'TCE70P24B2202374')
$pkg = 'cc.ugotit.elinkbook'
$out = Join-Path $env:TEMP "elink_repro\$Label"; New-Item -ItemType Directory -Force $out | Out-Null
Add-Type -AssemblyName System.Drawing
function Dev { & adb.exe -s $Device @args 2>&1 }
function Focus { (Dev shell "dumpsys window | grep mCurrentFocus") -join '' }
function Dump { Dev shell "uiautomator dump /sdcard/ui.xml" | Out-Null; (Dev shell "cat /sdcard/ui.xml") -join "`n" }
function Stats([string]$name) {
  $png = Join-Path $out "$name.png"; cmd /c "adb.exe -s $Device exec-out screencap -p > `"$png`""
  $b = [System.Drawing.Bitmap]::new($png); $nw = 0; $nb = 0; $n = 0
  for ($y = 100; $y -lt $b.Height; $y += 16) { for ($x = 0; $x -lt $b.Width; $x += 16) {
    $c = $b.GetPixel($x, $y); $l = 0.299*$c.R + 0.587*$c.G + 0.114*$c.B; $n++; if ($l -lt 235) { $nw++ }; if ($l -gt 20) { $nb++ } } }
  $b.Dispose(); [pscustomobject]@{ NonWhite = [math]::Round(100*$nw/$n,1); NonBlack = [math]::Round(100*$nb/$n,1) }
}
function WaitText([string]$pat, [int]$sec) { $t0 = Get-Date; while (((Get-Date)-$t0).TotalSeconds -lt $sec) { if ((Dump) -match $pat) { return $true }; Start-Sleep 2 }; return $false }
function TapNode([string]$pat) {
  $m = [regex]::Match((Dump), '<node [^>]*?(?:content-desc|text)="' + $pat + '[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  if (-not $m.Success) { return $false }
  Dev shell "input tap $([int](([int]$m.Groups[1].Value+[int]$m.Groups[3].Value)/2)) $([int](([int]$m.Groups[2].Value+[int]$m.Groups[4].Value)/2))" | Out-Null; return $true
}
function ToLibrary { for ($k = 0; $k -lt 6; $k++) { $x = Dump; if ($x -match '搜尋書名或作者') { return $true }; if ($x -match '選擇檔案') { Dev shell "input tap 1269 147" | Out-Null } else { Dev shell "input keyevent KEYCODE_BACK" | Out-Null }; Start-Sleep 4 }; return $false }

Dev shell "am force-stop $pkg" | Out-Null; Dev shell "input keyevent KEYCODE_HOME" | Out-Null; Start-Sleep 2
Dev shell "am start -n $pkg/.MainActivity" | Out-Null
$null = WaitText '書架|搜尋書名|選擇檔案|返回' 150; Start-Sleep 8
$pid0 = (Dev shell "pidof $pkg") -join ''
$rows = @(); $i = 0
foreach ($step in $Seq.ToCharArray()) {
  $i++; Dev logcat -c | Out-Null
  if ($step -eq 'R') {
    $inLib = ToLibrary
    $opened = $inLib -and ((TapNode 'elinkBook 範例 EPUB') -or (TapNode '[^"]{1,40}&#10;\d+%')); $up = $false
    if ($opened) { $up = WaitText '隱藏工具列|加入此頁書籤' 60; Start-Sleep 3; Dev shell "input tap 52 146" | Out-Null; Start-Sleep 5 }
  } elseif ($step -eq 'F') {
    $null = ToLibrary
    for ($k = 0; $k -lt 8; $k++) { Dev shell "input tap 1179 147" | Out-Null; Start-Sleep -Milliseconds 1500; Dev shell "input keyevent KEYCODE_BACK" | Out-Null; Start-Sleep -Milliseconds 1500 }
    Start-Sleep 2; $up = $true
  } elseif ($step -eq 'H') {
    Dev shell "input keyevent KEYCODE_HOME" | Out-Null; Start-Sleep 5
    Dev shell "am start -n $pkg/.MainActivity" | Out-Null
    $t1 = Get-Date; while (((Get-Date)-$t1).TotalSeconds -lt 30 -and -not ((Focus) -match $pkg)) { Start-Sleep -Milliseconds 700 }
    Start-Sleep 12; $up = $true
  } else {
    $null = ToLibrary; Dev shell "input tap 1269 147" | Out-Null; Start-Sleep 4
    Dev shell "input tap 702 357" | Out-Null
    $t0 = Get-Date; while (((Get-Date)-$t0).TotalSeconds -lt 60 -and -not ((Focus) -match 'documentsui')) { Start-Sleep -Milliseconds 700 }
    Start-Sleep 4; Dev shell "input tap 352 822" | Out-Null
    $t1 = Get-Date; while (((Get-Date)-$t1).TotalSeconds -lt 30 -and -not ((Focus) -match $pkg)) { Start-Sleep -Milliseconds 700 }
    Start-Sleep 12; $up = $true
  }
  $log = Dev logcat -d -v time; $egl = ($log | Select-String 'EGL_BAD_ACCESS').Count
  $st = Stats "step$i"; $pidNow = (Dev shell "pidof $pkg") -join ''
  $v = if ($pidNow -ne $pid0) { 'RED-proc' } elseif ($egl -gt 0) { 'RED-egl' } elseif ($st.NonWhite -lt 1 -or $st.NonBlack -lt 1) { 'RED-blank' } else { 'green' }
  $rows += [pscustomobject]@{ Step = $i; Kind = $step; Ok = $up; Egl = $egl; Verdict = $v }
  if ($v -like 'RED*') { break }
}
$rows | Format-Table -AutoSize | Out-String -Width 120
"[$Label] 序列 $Seq → " + $(if ($rows[-1].Verdict -like 'RED*') { "第 $($rows[-1].Step) 步（$($rows[-1].Kind)）紅燈" } else { '全部綠燈' })



