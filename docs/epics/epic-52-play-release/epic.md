# `epic-52-play-release` 上架 Google Play 的前置工作

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-52-play-release/`
**關聯文件：** `docs/research/google_play_release_sop.md`、`docs/research/cloud_storage_oauth_setup_guide.md`

## 背景

要把 elinkBook 上架 Google Play。上架步驟寫在 `docs/research/google_play_release_sop.md`。SOP 的第 1.1 節列出三件要先改的事，這個 Epic 負責完成它們：

1. release 建置目前用 debug 金鑰簽章，Play 會拒收。
2. `site/privacy.html` 沒有寫 PocketBase 同步服務，會跟 Play 的「資料安全性」表單對不上。
3. 版本號要靠人記得加 1，也沒有版本對照表。

## 開發記錄

**2026-09-27 `/grill-with-docs` Discovery**

- 決策細節見 `design.md`。
- SOP 已寫好：`docs/research/google_play_release_sop.md`。
- 拆成 3 個 Issue，見 `issues.md`。

**2026-09-27 文件審查修訂**（`reviews/review-epic-52.md`，3 Critical／8 Important／4 Minor）

- 採納：C-1（`bump_version.js` 選 n 必定中止，改成當場重問；對照表沒有紀錄時不比較）、C-3（隱私權政策第六節補雲端資料刪除；SOP 2.3 補刪除要求網址）、I-1、I-3、I-5、I-6、I-7、I-8、M-1、M-3、M-4。
- 部分採納：C-2。repo 設定 `core.autocrlf=true`，換行符號被改掉時 git 不會顯示整檔 diff；保留換行符號的成本很低，仍寫進 Issue 3 規格與測試。
- 採納並修正方向：I-2。`app/android/.gitignore` 本來就忽略 `key.properties`、`*.jks`、`*.keystore`，所以 Issue 1 刪除「改根目錄 `.gitignore`」這一項，驗收改用 `git check-ignore -v`。
- 不採納：I-4。朗讀通知由 `audio_service` 建立，屬於媒體工作階段通知，Android 13 的通知權限規定豁免這類通知。
- 不採納：M-2。`applicationId` 的 TODO 註解與簽章無關，不在本 Epic 範圍。
- 發布者決定：隱私權政策不寫刪除資料的處理天數。
