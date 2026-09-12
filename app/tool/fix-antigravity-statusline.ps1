# fix-antigravity-statusline.ps1 — 一鍵修復 statusline 三大坑
# 用法：powershell -ExecutionPolicy Bypass -File app/tool/fix-antigravity-statusline.ps1
# 下次執行 /antigravity-cli-statusline 重設後若又出現 exit 1，直接跑此腳本即可

$ErrorActionPreference="Stop"
$homeDir=$env:USERPROFILE
$plugin="C:/Users/fycdc/.gemini/config/plugins/antigravity-cli-statusline/skills/antigravity-cli-statusline/scripts"
$hooks="C:/Users/fycdc/.gemini/antigravity-cli/hooks"
Write-Host "1. 修復外掛源 configure-statusline.mjs 為正斜線無引號..." -ForegroundColor Cyan
$cfg=Get-Content "$plugin/configure-statusline.mjs" -Raw
if($cfg -notmatch "statuslineQuotaPosix"){
  $cfg=$cfg.Replace("  settings.statusLine = {`r`n    enabled: true,`r`n    type: 'command',`r`n    command: ``node `${statuslineQuotaMjsPath}```r`n  };", "  // 使用正斜線無引號：同時相容 Go 直接 exec 與 sh -c`r`n  const statuslineQuotaPosix = statuslineQuotaMjsPath.replace(/\/g, '/');`r`n  settings.statusLine = {`r`n    enabled: true,`r`n    type: 'command',`r`n    command: ``node `${statuslineQuotaPosix}```r`n  };")
  [IO.File]::WriteAllText("$plugin/configure-statusline.mjs", $cfg, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "  已修復 configure-statusline.mjs" -ForegroundColor Green
} else { Write-Host "  已是正斜線版，跳過" -ForegroundColor Yellow }

Write-Host "2. 還原極速 17 項 Hook 到 hooks/..." -ForegroundColor Cyan
Copy-Item "$hooks/backup-20260911/statusline-quota.real.mjs" "$hooks/statusline-quota.real.mjs" -Force
Copy-Item "$hooks/backup-20260911/statusline-quota.real.mjs" "$hooks/statusline-quota.mjs" -Force
Copy-Item "$hooks/backup-20260911/statusline-quota.real.mjs" "$hooks/wrapper.mjs" -Force
Write-Host "  已還原極速版 (0.5s, 17 項含換行)" -ForegroundColor Green

Write-Host "3. 修正 settings.json 為正斜線無引號..." -ForegroundColor Cyan
foreach($p in @("$homeDir/.gemini/settings.json","$homeDir/.gemini/antigravity-cli/settings.json")){
  $j=Get-Content $p -Raw | ConvertFrom-Json
  $j.statusLine.command="node C:/Users/fycdc/.gemini/antigravity-cli/hooks/wrapper.mjs"
  $j.statusLine.enabled=$true; $j.statusLine.type="command"
  $json=$j | ConvertTo-Json -Depth 10
  [IO.File]::WriteAllText($p, $json, (New-Object System.Text.UTF8Encoding($false)))
  # 驗證無 BOM
  $b=[IO.File]::ReadAllBytes($p); if($b[0]-eq 0xEF){ [IO.File]::WriteAllBytes($p,$b[3..($b.Length-1)]); Write-Host "  已剝除 BOM: $p" -ForegroundColor Yellow }
}
Write-Host "  已修正兩份 settings.json" -ForegroundColor Green

Write-Host "4. 驗證..." -ForegroundColor Cyan
node --check "$hooks/statusline-quota.real.mjs"; if($LASTEXITCODE -eq 0){ Write-Host "  語法 OK" -ForegroundColor Green }
& node "$hooks/statusline-quota.real.mjs" | Out-Null; if($LASTEXITCODE -eq 0){ Write-Host "  執行 OK (exit 0)" -ForegroundColor Green }

Write-Host "`n✅ 修復完成！請 taskkill /F /IM agy.exe 後重啟 agy" -ForegroundColor Green
Write-Host "   備份在: $hooks/backup-20260911" -ForegroundColor Gray
