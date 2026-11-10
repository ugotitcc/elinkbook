# 由 assets/appicon_v2.jpg 產生 Windows 版圖示與啟動小視窗圖（epic-66）
# 輸出：
#   app/windows/runner/resources/app_icon.ico   多尺寸（16/24/32/48/64/128/256，PNG 壓縮）
#   app/windows/runner/resources/splash.bmp     啟動小視窗用（24 位元 BMP，由 Runner.rc 內嵌）
# 用法（在 app/ 執行）：powershell -ExecutionPolicy Bypass -File tool/generate_windows_icons.ps1
# 不需要額外安裝工具，只用 .NET System.Drawing。

[CmdletBinding()]
param(
    [string]$Source,
    [string]$OutDir
)

$ErrorActionPreference = "Stop"
# 預設值放在本體內計算（Windows PowerShell 5.1 的 param 預設值取不到 $PSScriptRoot）
$appDir = Split-Path -Parent $PSScriptRoot
if (-not $Source) { $Source = Join-Path (Split-Path -Parent $appDir) "assets\appicon_v2.jpg" }
if (-not $OutDir) { $OutDir = Join-Path $appDir "windows\runner\resources" }
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path $Source)) { throw "找不到來源圖: $Source" }
if (-not (Test-Path $OutDir)) { throw "找不到輸出資料夾: $OutDir" }

# 來源為 1024x1024、四周有一圈紙張底色。裁成「插畫外框＋少量留白」的正方形，
# 讓小尺寸圖示裡的書與樓閣盡量大（座標以來源圖像素計）
$cropX = 90; $cropY = 100; $cropSize = 840

$src = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Source))
try {
    if ($src.Width -ne 1024 -or $src.Height -ne 1024) {
        throw "來源圖尺寸應為 1024x1024，實際 $($src.Width)x$($src.Height)，請確認裁切座標後再調整腳本"
    }

    # 以高品質雙三次縮放，輸出指定邊長的 32 位元 ARGB 點陣圖
    function New-Scaled([int]$size) {
        $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $dest = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
        $g.DrawImage($src, $dest, $cropX, $cropY, $cropSize, $cropSize, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
        return $bmp
    }

    # ---- ICO：256 以下用傳統 BMP(DIB) 項，256 用 PNG 項（與 Windows 慣例一致、相容性最好） ----
    # 註：標題列曾出現警告三角形，已實測與 PNG／DIB 格式無關（兩種格式結果相同），
    # 真正原因與修法見 windows/runner/win32_window.cpp 的 hIconSm 註解。
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $pngs = @()
    foreach ($s in $sizes) {
        $bmp = New-Scaled $s
        if ($s -lt 256) {
            # DIB：BITMAPINFOHEADER（高度為 2 倍，含 AND 遮罩）＋ 由下而上的 BGRA 像素 ＋ 1bpp AND 遮罩（全 0，透明度走 alpha）
            $ms = New-Object System.IO.MemoryStream
            $w = New-Object System.IO.BinaryWriter($ms)
            $w.Write([uint32]40); $w.Write([int32]$s); $w.Write([int32]($s * 2))
            $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]0)
            $w.Write([uint32]0); $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
            for ($y = $s - 1; $y -ge 0; $y--) {
                for ($x = 0; $x -lt $s; $x++) {
                    $c = $bmp.GetPixel($x, $y)
                    $w.Write([byte]$c.B); $w.Write([byte]$c.G); $w.Write([byte]$c.R); $w.Write([byte]$c.A)
                }
            }
            $maskRowBytes = [int]([math]::Ceiling($s / 32.0) * 4)
            $w.Write((New-Object byte[] ($maskRowBytes * $s)))
            $w.Flush()
            $pngs += , $ms.ToArray()
            $w.Dispose(); $ms.Dispose()
        } else {
            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $pngs += , $ms.ToArray()
            $ms.Dispose()
        }
        $bmp.Dispose()
    }

    $icoPath = Join-Path $OutDir "app_icon.ico"
    $fs = [System.IO.File]::Create($icoPath)
    $bw = New-Object System.IO.BinaryWriter($fs)
    try {
        $bw.Write([uint16]0)               # 保留
        $bw.Write([uint16]1)               # 類型：圖示
        $bw.Write([uint16]$sizes.Count)    # 影像數
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $s = $sizes[$i]
            $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s }))   # 寬（256 以 0 表示）
            $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s }))   # 高
            $bw.Write([byte]0)             # 調色盤色數
            $bw.Write([byte]0)             # 保留
            $bw.Write([uint16]1)           # 色彩平面
            $bw.Write([uint16]32)          # 位元深度
            $bw.Write([uint32]$pngs[$i].Length)
            $bw.Write([uint32]$offset)
            $offset += $pngs[$i].Length
        }
        foreach ($p in $pngs) { $bw.Write($p) }
    } finally {
        $bw.Dispose(); $fs.Dispose()
    }
    Write-Host "已輸出 $icoPath（$((Get-Item $icoPath).Length) bytes，尺寸 $($sizes -join '/')）"

    # ---- 啟動小視窗圖：400x400 不透明 24 位元 BMP ----
    $splashSize = 400
    $sp = New-Scaled $splashSize
    $sp24 = New-Object System.Drawing.Bitmap($splashSize, $splashSize, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g2 = [System.Drawing.Graphics]::FromImage($sp24)
    $g2.DrawImage($sp, 0, 0, $splashSize, $splashSize)
    $g2.Dispose()
    $bmpPath = Join-Path $OutDir "splash.bmp"
    $sp24.Save($bmpPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $sp.Dispose(); $sp24.Dispose()
    Write-Host "已輸出 $bmpPath（$((Get-Item $bmpPath).Length) bytes，${splashSize}x${splashSize}）"
} finally {
    $src.Dispose()
}
