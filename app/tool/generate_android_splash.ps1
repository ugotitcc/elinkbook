# 由 assets/appicon_v2.jpg 產生 Android 啟動畫面圖（Android 12+ 系統 SplashScreen 與舊版 launch_background 共用）
# 輸出：
#   app/android/app/src/main/res/drawable-xxxhdpi/splash_icon.png   1152x1152（= 288dp @ 4x）
# 並印出建議的底色（寫進 res/values/colors.xml 的 splash_background）
# 用法（在 app/ 執行）：powershell -ExecutionPolicy Bypass -File tool/generate_android_splash.ps1
#
# 版面原則：Android 12+ 的啟動圖示若沒有 icon background，系統只顯示 288dp 畫布中央
# 直徑 192dp 的圓形（其餘被遮掉）。所以把插畫內容縮放到剛好放進這個圓，
# 圓內其餘用紙張底色填滿，讓插畫在系統允許的範圍內盡量大。

[CmdletBinding()]
param(
    [string]$Source,
    [string]$OutFile
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$appDir = Split-Path -Parent $PSScriptRoot
if (-not $Source) { $Source = Join-Path (Split-Path -Parent $appDir) "assets\appicon_v2.jpg" }
if (-not $OutFile) { $OutFile = Join-Path $appDir "android\app\src\main\res\drawable-xxxhdpi\splash_icon.png" }
if (-not (Test-Path $Source)) { throw "找不到來源圖: $Source" }

$canvas = 1152                 # 288dp @ xxxhdpi
$circleDiameter = 768          # 192dp @ xxxhdpi（系統遮罩圓）
# 來源 1024x1024 中，插畫內容（書與樓閣）的中心約 (510,515)；離中心最遠的是書的左右尖角，
# 約 416 像素（目測量得）。把「中心到最遠內容 + 少量餘裕」的半徑 420 縮放到系統圓的半徑，
# 圓內整個綠色圓盤與書角都能看到、不被遮罩切掉。
$bboxCx = 510; $bboxCy = 515
$coverRadius = 420
$scale = ($circleDiameter / 2) / $coverRadius                              # 來源像素 → 畫布像素

$src = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Source))
try {
    if ($src.Width -ne 1024 -or $src.Height -ne 1024) { throw "來源圖尺寸應為 1024x1024，實際 $($src.Width)x$($src.Height)" }

    # 底色：取來源圖四周一圈紙張像素的平均
    $r = 0; $g = 0; $b = 0; $n = 0
    foreach ($t in 0..39) {
        foreach ($x in (0..1023 | Where-Object { $_ % 8 -eq 0 })) {
            foreach ($y in @($t, (1023 - $t))) { $c = $src.GetPixel($x, $y); $r += $c.R; $g += $c.G; $b += $c.B; $n++ }
            foreach ($yy in @($x)) { $c = $src.GetPixel($t, $yy); $r += $c.R; $g += $c.G; $b += $c.B; $n++ }
        }
    }
    $paper = [System.Drawing.Color]::FromArgb(255, [int]($r / $n), [int]($g / $n), [int]($b / $n))

    $bmp = New-Object System.Drawing.Bitmap($canvas, $canvas, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.Clear($paper)
    $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    # 讓外接範圍中心對齊畫布中心
    $destSize = 1024 * $scale
    $destX = $canvas / 2 - $bboxCx * $scale
    $destY = $canvas / 2 - $bboxCy * $scale
    $gfx.DrawImage($src, [single]$destX, [single]$destY, [single]$destSize, [single]$destSize)
    $gfx.Dispose()
    $dir = Split-Path -Parent $OutFile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host ("已輸出 {0}（{1} bytes，縮放 {2:N3}）" -f $OutFile, (Get-Item $OutFile).Length, $scale)
    Write-Host ("建議底色 splash_background = #{0:X2}{1:X2}{2:X2}" -f $paper.R, $paper.G, $paper.B)
} finally {
    $src.Dispose()
}
