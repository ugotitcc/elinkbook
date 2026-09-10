# filter_antigravity_log.ps1 — PowerShell 包裝器
# 用法：
#   .\app\tool\filter_antigravity_log.ps1                # 過濾最新 log 並分頁顯示
#   .\app\tool\filter_antigravity_log.ps1 -Stats          # 只看統計
#   .\app\tool\filter_antigravity_log.ps1 -Follow         # 即時 tail
#   .\app\tool\filter_antigravity_log.ps1 -File "C:\path\to\cli-xxx.log"
#   .\app\tool\filter_antigravity_log.ps1 -Aggressive     # 額外過濾次要噪音
#   .\app\tool\filter_antigravity_log.ps1 -Output filtered.log

param(
    [string]$File = "",
    [string]$Output = "",
    [switch]$Stats,
    [switch]$Follow,
    [switch]$Aggressive
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PyScript = Join-Path $ScriptDir "filter_antigravity_log.py"

$Args = @()
if ($File -ne "") { $Args += @("-f", $File) }
if ($Output -ne "") { $Args += @("-o", $Output) }
if ($Stats) { $Args += "--stats" }
if ($Follow) { $Args += "--follow" }
if ($Aggressive) { $Args += "--aggressive" }

# 優先用 python，若無則試 python3
$Python = "python"
try { & python --version 2>$null | Out-Null } catch { $Python = "python3" }

& $Python $PyScript @Args
