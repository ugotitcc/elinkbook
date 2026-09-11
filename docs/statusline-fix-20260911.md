# Antigravity Statusline 修復記錄 — 2026-09-11

## 問題
- `statusline: command failed: exit status 1 (stderr: )` 反覆出現，累積 `failure 10/30` 後被停用
- 歷次 `cli-*.log` 顯示三種不同根因：
  1. `sh -c` 吃掉反斜線：`node C:\Users\...` → `C:Usersfycdc...` → `MODULE_NOT_FOUND`
  2. 引號被當字面量：`node "C:/path"` 在 Go 直接 `exec` 下變成 `"C:/path"` → `Cannot find module '...\"C:/path"'`
  3. 超時：原 Hook 跑 `3.5~11.8s`（`powershell Get-CimInstance` + `git` 多路徑掃描 + `backgroundTasks/subagents/artifacts` 掃描），超過 `agy` 約 `2~3s` 超時而被 `kill` → 空白 `stderr`

## 修正
1. **命令改為無引號正斜線**：`node C:/Users/fycdc/.gemini/antigravity-cli/hooks/wrapper.mjs`
   - 同時相容 Go 直接 `exec` 與 `sh -c`，已同步修正外掛源 `configure-statusline.mjs`（`statuslineQuotaPosix`）
2. **Hook 極速化**：`getCliMemoryMB` → `process.memoryUsage()`，移除 `powershell` 與 `backgroundTasks/subagents/artifacts` 掃描，`timeout 1000→400`，完整 17 項仍 `<0.7s`，含智慧換行（`termWidth` 自動折行 4~7 行）
3. **雙重保險 Wrapper**：`statusline-quota.mjs` 與 `wrapper.mjs` 皆為極速版，`settings.json` 指 `wrapper.mjs`，即使直接跑 `statusline-quota.mjs` 也受保護；`3500→2800→1200ms` 保底 `TIMEOUT` 內必定 `exit 0`，超時回 `? for shortcuts` 而非 `exit 1`

## 備份
- `C:/Users/fycdc/.gemini/antigravity-cli/hooks/backup-20260911/` — 三份 Hook + 兩份 settings + trusted_hooks
- `app/tool/fix-antigravity-statusline.ps1` — 一鍵重放本次全部修正
- 外掛源已 patch：`~/.gemini/config/plugins/antigravity-cli-statusline/skills/.../configure-statusline.mjs` 與 `statusline-quota.mjs`

## 下次重設後
若執行 `/antigravity-cli-statusline` 重設後又 `exit 1`：
```powershell
powershell -ExecutionPolicy Bypass -File app/tool/fix-antigravity-statusline.ps1
taskkill /F /IM agy.exe; agy
```
或手動 `taskkill /F /IM agy.exe` 重啟亦可（`settings.json` 熱更新但 `statusline_runner` 需重啟才重載）。

## 驗證
```powershell
node "C:/Users/fycdc/.gemini/antigravity-cli/hooks/statusline-quota.real.mjs" | head
# 應 0.5s 內顯示 17 項 4~7 行
cat C:/Users/fycdc/.gemini/tmp/hook_debug.log # TIMEOUT 應極少
cat C:/Users/fycdc/.gemini/antigravity-cli/log/cli-*.log | Select-String statusline # 應無新的 failure
```
