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

**2026-09-27 PR #285 合併**：SOP、`design.md`、`issues.md` 與審查修訂已合併進 `main`。3 個 Issue 都還沒開始。

**2026-09-27 `plan-issue-1.md` 審查修訂**（`reviews/review-plan-issue-1.md`，2 Critical／4 Important／4 Minor）

- 採納：C-2（刪除 `<TEST_JKS>` 佔位符，測試金鑰改用固定完整路徑）、I-1（改用 UTF-8 Reader 讀 `key.properties`）、I-2（警告改用 `logger.quiet`，Flutter 非 verbose 模式會帶 `-q` 呼叫 Gradle）、I-3（第二次建置前先刪除舊 `.aab`）、I-4（改比對 `CN=`）、M-1（`storeFile`、`keyAlias` 去掉尾端空白，密碼不處理）、M-2（`isFile`）、M-3（`project.file`、`project.logger`）、M-4（新增情境 B2：整行不存在）。
- 不採納：C-1。計畫的執行者依 `CLAUDE.md` 預設是 Claude Code，它的 Bash 工具就是 Git Bash，已確認 `grep`、`bash` 都可用。只有人類指定 Antigravity 時才會在 PowerShell 環境執行，因此改在「全域限制」寫明用 `C:\Program Files\Git\bin\bash.exe` 包起來執行，不把整份計畫改寫成 PowerShell。

**2026-09-27 Issue 1 完成**：`build.gradle.kts` 讀取 `app/android/key.properties` 設定 release 簽章；檔案不存在時退回 debug 簽章並警告，欄位缺少或金鑰檔不存在時建置失敗。新增 `key.properties.example`。以測試金鑰驗證 5 個情境（A、B、B2、C、D）與完整 `.aab` 建置（測試金鑰簽章 `CN=Epic52 Test`、無 `key.properties` 時 `CN=Android Debug`）。

- 直接執行 `./gradlew` 時，Gradle 的中文訊息以系統字碼頁 cp950 輸出，用 UTF-8 字串 `grep` 會找不到，要先 `iconv -f cp950 -t utf-8`。經由 `flutter build` 時是 UTF-8，警告不需要 `-v` 就看得到。
- `flutter analyze` 乾淨。完整 `flutter test`：2930 通過、1 略過、1 失敗；失敗的是 `wifi_transfer_http_server_test.dart` 第 570 行，即已登記的 `epic-51-wifi-transfer-test-fix`，與本 Issue 無關。

**2026-09-27 Issue 1 程式審查修訂**（`reviews/review-issue-1.md`，0 Critical／0 Important／4 Minor，發布者選擇 4 條全修）

- M-1：值裡有不合法的 `\u` 時，改丟出指出 `key.properties` 路徑、提示改用正斜線的錯誤，不帶出檔案內容。
- M-2：讀檔前去掉 UTF-8 BOM，含 BOM 的檔案不再被誤判成缺少 `storePassword`。
- M-3：`storeFile` 改用 `isFile` 判斷，指向資料夾時在設定階段就失敗。
- M-4：沒有 `key.properties` 時，只有 task graph 含 release 任務（例如 `bundleRelease`）才印出警告，debug 建置不再印出。
- `key.properties.example` 補上「密碼裡的反斜線寫成兩個」與「用 UTF-8 存檔」。
- 驗證：4 條修改前都重現（紅燈），修改後都通過；原本的情境 A、B、D 重跑結果不變。警告觸發用 `./gradlew -m`（dry run）確認：`assembleDebug` 印 0 次、`bundleRelease` 印 1 次。

**2026-09-27 PR #286 合併**：Issue 1 已合併進 `main`。Issue 2、Issue 3 還沒開始。

**2026-09-27 Issue 2 實作**（發布者選擇不寫計畫，直接審閱文字）

- 實作時發現同步伺服器網址由使用者自行輸入，發布者確認 ugotit.cc 不提供同步伺服器（`design.md` Q27）。Issue 2 描述、SOP 1.7／2.2／2.3 已依此修正；SOP 2.3 的資料安全性表單改為保守申報「收集（選用）」，「傳輸時是否全部加密」改答「否」，因為使用者可以設定 `http://` 伺服器。
- `site/privacy.html` 與 `site/index.html` 內嵌政策做相同修改：第一節排除使用者自架的同步伺服器；第二節修正雲端硬碟描述與傳輸加密說明，新增「閱讀同步服務」；第三節改成符合事實的寫法；第六節補上同步資料的刪除方式；修訂日期改為 2026 年 9 月 27 日；`privacy.html` 的 `og:url` 改成 `https://www.ugotit.cc/privacy`。
- 以腳本比對，兩份政策內文一致；`ul`、`p`、`h3` 標籤都成對。

**2026-09-27 PR #287 合併**：Issue 2 已合併並部署，`https://www.ugotit.cc/privacy` 已顯示「閱讀同步服務」與新的修訂日期。剩 Issue 3。
