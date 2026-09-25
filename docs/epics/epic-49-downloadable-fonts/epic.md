# `epic-49-downloadable-fonts` 可下載字型

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-49-downloadable-fonts/`
**關聯 PRD 章節：** FR-09（內建字型）、FR-35（全域字型管理）

## 背景

`epic-48` 修正內建字型清單時發現：字型檔打包進 APK 的成本太高（思源黑體 34MB、思源宋體 57MB，5 款合計約 140MB），而之前開發版沒有打包思源兩款，選用時其實是系統字型補位。使用者詢問「不打包，讓使用者點『下載』後才下載該字型」是否可行，經 2026-09-25 `/grill-with-docs` 討論後定案：5 款內建字型一律改為「可下載字型」，字型檔放在 Cloudflare R2，透過 Cloudflare Worker 對外提供下載。

`epic-48` 已先把 `pubspec.yaml` 的字型全部移出；本 Epic 完成前，選思源兩款時由系統字型補位。

決策細節見 `design.md`。

## 開發記錄

**2026-09-25 Discovery**：`/grill-with-docs` 共 4 輪、20 題，產出 `design.md`；`CONTEXT.md` 新增「可下載字型」詞條。流程依使用者選擇採完整 SDD（design → spec → issues → plan → 審查）。

**2026-09-25 Architecting**（`/to-spec`）：先把 `main`（含 epic-48 PR #275）合併進本分支，解決 `docs/epics.md` 一行衝突。與使用者確認 5 個測試切面後，產出 `spec.md`、[ADR 0035](../../adr/0035-downloadable-fonts-via-r2-worker.md)、`issues.md`（5 個工單，其中 Issue 2 部署與 Issue 5 真機驗證需人類操作）。

- 盤點時發現、改變原設計的事實：書本檔案走原生 `InternalStoragePathHandler` 串流，而字型目前是由 Dart 把整個檔案讀進記憶體再經 platform channel 傳給 WebView。思源宋體有 57MB，改為比照書本，新增 `/downloaded-fonts/` 串流處理器，並移除 Dart 讀取 Flutter asset 的攔截分支。
- 「已下載」狀態只看正式檔案是否存在（暫存檔驗證 SHA-256 後才改名），不新增資料表。
- ADR 編號：Discovery 時暫定 0024，但該編號已被使用，改為 0035。
- 5 個字型檔的大小與 SHA-256 已由 git 歷史中的原檔算出，寫入 `spec.md`。

**2026-09-25 設計審查修訂**（`reviews/review-design.md`，結論 Approved with Recommendations，0 Critical／3 Important／2 Minor）

- I-1 採納：Worker 收到 HEAD 時必須用 `bucket.head()` 只讀中繼資料，不能用 `get()` 開啟物件串流。已寫入 `spec.md` 的 Worker HTTP 介面，Issue 1 測試要求補上「HEAD 不呼叫 `get()`」。
- I-2 採納：`design.md`「需要調整的既有程式」加上 Architecting 階段更新說明，標示已改為原生 `InternalStoragePathHandler` 串流、Dart 攔截分支移除，其餘兩項也標上 spec 的定案。
- I-3 採納（依據更正）：報告引用的 `AGENTS.md` 並沒有「E-Ink 效能要求」段落，但 `CLAUDE.md`「E-Ink 友善、減少過渡動畫」支持同一結論。`DownloadableFontStore` 的進度改以整數百分比回報，只在數值改變時呼叫（一次下載最多 101 次）；節流放在 store，所有使用者都受惠，也能在 store 切面測試。
- M-1 採納：新增 `removeStaleTemporaryFiles()`，`main.dart` 啟動時呼叫一次，清掉 App 被系統終止時留下的 `.part` 檔；`download()` 開始前也先刪除同一字型的舊暫存檔。
- M-2 部分採納：`wrangler login` 是互動式瀏覽器 OAuth，不需要 API Token，所以不列入 wizard 步驟；只在 `spec.md` 註明日後在 CI 部署時需要的最小權限。

**2026-09-25 規格與工單審查修訂**（`reviews/review-spec.md`：Changes Requested，1 Critical／4 Important／3 Minor；`reviews/review-issues.md`：Changes Requested，1 Critical／3 Important／2 Minor）

- **C-1（兩份報告同一問題）採納**：已對照程式碼確認，`FoliateReaderView` 的 `_initialIndexUri` 是 `late final`（`foliate_reader_view.dart:536`），而 `ReaderScreen` 對自訂字型已經用 `_customFontsLoaded` 延後建構閱讀器（`reader_screen.dart:385`、`:2805`）。已下載字型沒有同樣的處理，所以一定會發生「下載了也不會套用」。`spec.md` 與 Issue 4 補上 `downloadableFontStore` 可選參數、`_downloadedFontsLoaded` 延後建構條件、沒有 store 或讀取失敗時不等待，並新增以 `Completer` 控制時機的回歸測試。
- 規格 I-1 採納：`FoliateReaderView` 在測試檔中被建構 79 次，新參數 `installedFonts`（預設 `const {}`）、`downloadedFontsDirectory`（預設 `null`，不為 `null` 才註冊處理器）一律可選。`ReaderSettingsSheet` 的新參數同樣可選。
- 規格 I-2／工單 I-3 部分採納：下載中時，其他列的「下載」「重試」「刪除」全部停用；store 對重疊下載拋出 `StateError`，作為第二道防線。**不採納**「停用 AppBar 上傳按鈕」：報告的理由是兩組非同步寫入會互搶，但自訂字型上傳只呼叫 `takePersistableUriPermission`，不複製檔案（ADR 0021，`font_management_screen.dart:169`），不存在互搶的情況。
- 規格 I-3（孤立 `.part`）與規格 M-1（進度節流）：設計審查修訂（M-1、I-3）已寫入 spec，報告審查的應是修訂前的版本，這次沒有新增內容。
- 規格 I-4 採納：刪除確認內文新增專屬字串 `fontManagementDownloadableDeleteConfirmMessage`（不帶參數）；標題沿用既有的 `fontManagementDeleteConfirmTitle`，它的文意與 `{fontName}` 參數對兩種字型都適用，沒有必要另開新的標題字串。
- 規格 M-2 採納：每一列的標題固定是字型名稱，大小、進度、錯誤訊息放在副標題。
- 規格 M-3 採納：把「建立存放目錄」和「清理殘留 `.part`」合併成單一的 `prepare()`（取代原本的 `removeStaleTemporaryFiles()`），App 啟動時呼叫一次。
- 工單 I-1 採納（做法不同於報告建議）：報告提出「目錄不存在就略過測試」或「Issue 3 改為依賴 Issue 1」兩種做法。改為把字型目錄一致性測試移到 Issue 4：它本來就依賴 Issue 1、3，兩邊的檔案都已存在，不需要可略過的條件式測試，Issue 1、3 也能維持平行開發。
- 工單 I-2 採納：Issue 1 要一併更新 `pubspec.yaml` 中「原俠正楷字型檔仍在 assets/fonts/」的註解。
- 工單 M-1 採納：Issue 4 明列「沒有傳入 store 時開書行為不變」的測試。
- 工單 M-2 採納：Issue 2 加上「開始前準備：先綁付款方式」。
- 另外把 spec 中的審查編號加上來源（設計審查／規格審查／工單審查），避免三份報告的 I-1、M-1 混淆；Issue 5 新增「下載到一半滑掉 App」與「電子紙裝置下載時沒有閃爍」兩項真機驗證。

**2026-09-25 撰寫實作計畫**（`/writing-plans`）：`plans/plan-issue-1.md`（5 個 Task：字型原檔與清單、Worker、上傳與驗證腳本、部署 wizard、整體驗證）、`plans/plan-issue-3.md`（7 個 Task：字型目錄、store 核心、store 進度／取消／重疊防護、在地化字串、字型管理畫面、依賴注入、整體驗證）。兩份計畫刻意與 spec 不同的地方都寫在計畫開頭：

- 錯誤原因代碼 `http` 在程式中命名為 `FontDownloadFailure.httpStatus`，避免和 `package:http` 的匯入前綴撞名。
- 檔案大小格式（「34.4 MB」）三種語系寫法相同，做成純函式 `formatFontFileSize()`，不另開在地化字串。
- Worker 接受任何 `v<N>/` 版本路徑（不只 `v1/`），字型改版時不必重新部署 Worker；路徑穿越與編碼字元一律 404。
- 授權檔由 GitHub API 取得各字型 repo 的授權檔；repo 名稱無法確認時，執行者必須停下來回報，不可自行撰寫授權文字。

**2026-09-25 Issue 1 計畫審查修訂**（`reviews/review-plan-issue-1.md`：Changes Requested，1 Critical／2 Important／2 Minor）

- C-1 採納（已實際查核）：`ButTaiwan/gktk` 不存在，原俠正楷的 repo 是 `tonyhuan/GuanKiapTsingKhai`；源流明體、台灣圓體的授權檔名為 `SIL_Open_Font_License_1.1.txt`，GitHub `/license` API 認不出來。改為直接下載四個已確認可用的 raw 網址。原俠正楷的 repo 沒有附授權檔，改用 OFL 官方全文（openfontlicense.org），開頭的著作權聲明取自字型檔 `name` table 的 nameID 0，保留名稱取自其 README，不自行撰寫。上一段「授權檔由 GitHub API 取得」的做法作廢。
- I-1 採納：改用 `git restore --source=eddcc85e^ --worktree` 直接把字型寫到磁碟，不經 shell 重導向；已實測 SHA-256 正確，且不動 index。全域限制新增「shell 指令一律在 Git Bash 執行」。
- I-2 採納：`upload.mjs` 的 HEAD 前置檢查加上 `try…catch`，連不上時列入問題清單；`test_scripts.mjs` 新增「伺服器已關閉時結束碼 1、訊息友善」的測試。
- M-1 採納：本機 `core.autocrlf=true`，所以新增 `fonts-cdn/.gitattributes`（`*.sh text eol=lf`、`*.ttf binary`），整體驗證時用 `git ls-files --eol` 確認 wizard 是 LF。
- M-2 採納（做法不同於報告建議）：計畫的指令本來就在 Git Bash 執行，不改成 Node 單行指令；改用 `git ls-files app/assets/fonts | wc -l`，檢查的是版控內容，而不是本機可能殘留的空目錄。

**2026-09-25 Issue 3 計畫審查修訂**（`reviews/review-plan-issue-3.md`：Approved with Recommendations，0 Critical／2 Important／1 Minor）

- I-1 採納：`prepare()` 刪除單一 `.part` 失敗（`FileSystemException`）時略過，繼續清理其他暫存檔。留下的 `.part` 不影響「已下載」的判斷，下載開始前 `_preparePartFile()` 也會再刪一次。檔案被占用的情況在測試環境中無法穩定重現，所以不另外寫測試。
- I-2 不需修改：計畫已經寫了。全域限制規定改完 ARB 要執行 `flutter gen-l10n`，並提交產生的檔案；Task 4 Step 3 就是 `flutter gen-l10n`，還會用 grep 確認新字串已經產生。Task 6 沒有改 ARB，不需要重新產生。
- M-1 採納：`formatFontFileSize()` 的註解補上「以 1024 × 1024 為 1 MB（實際是 MiB）」。

**2026-09-25 Issue 1 完成**（`plans/plan-issue-1.md`，5 個 Task 全數執行完畢）：

- 新增 `fonts-cdn/`：5 款字型原檔（`SourceHanSansTC-VF.ttf`、`SourceHanSerifTC-VF.ttf`、`GuanKiapTsingKhai.ttf`、`TaiwanPearl-Regular.ttf`、`GenRyuMinTW-Regular.ttf`，大小與 SHA-256 皆與 `spec.md` 一致）與 5 個 SIL OFL 授權檔、字型清單 `fonts.json`（單一事實來源）、Worker（`GET`／`HEAD /v<N>/<檔名>.ttf`，`HEAD` 只用 `bucket.head()`）、上傳腳本（含 `--dry-run` 與整批中止的前置檢查）、線上驗證腳本、部署 wizard（`deploy-wizard.sh`）、`README.md`。
- 三支 Node 測試全數通過：`check_manifest.mjs`（5/5 一致）、`test_worker.mjs`（GET／HEAD 200 與標頭、404、405、路徑穿越 404、HEAD 不呼叫 `get()`）、`test_scripts.mjs`（dry-run 列指令、key 已存在整批中止、雜湊不符中止、連線失敗友善訊息、線上驗證含竄改偵測）。
- `app/assets/fonts/` 版控中已無字型檔；`pubspec.yaml` 註解已更新；`foliate_native_bridge_test.dart`（14/14）與 `app_font_test.dart`（1/1）仍通過。

**2026-09-25 Issue 1 程式審查修訂**（`reviews/review-issue-1.md`：修正後可合併，0 Critical／1 Important／7 Minor）

- I-1（計畫層級缺口，人類裁定採方案 A）：上傳到一半失敗後，已上傳的 key 會讓每次重跑都卡在前置檢查。`upload.mjs` 改成：key 已存在時下載比對大小與 SHA-256，一致就略過，不一致仍然整批中止（永不覆蓋的原則不變）。新增 3 個測試（已存在且內容一致→略過、全部已發布→不列出指令、已存在但內容不同→中止），並做過變異檢查。wizard 與 README 補上「中斷後直接重跑」的說明；計畫審查重點 #5 加註修訂。串流雜湊抽成 `lib.mjs` 的 `digestOfResponse()`，與 `verify_remote.mjs` 共用。
- M-1 採納：上傳指令改用相對於清單目錄的 `--file` 路徑（`cwd` 設為清單目錄），Windows 上改傳整行指令字串，避免含空白路徑被拆開，也不再出現 DEP0190 警告。
- M-2 採納：本機字型檔讀不到時列入前置檢查問題清單，不再印出例外堆疊；新增測試。
- M-3 採納（只改文件）：README 註明 `--base-url` 必須是正在服務該 bucket 的 Worker 網址。
- M-4 列入 Issue 2 驗收：用 `curl -I` 確認 HEAD 回應帶有 `content-length`。
- M-5 採納：wizard 補上 `npx` 詢問是否安裝、以及 wrangler 詢問是否註冊 `workers.dev` 子網域時的回答說明。
- M-6、M-7 不修改：M-6 在正常情況不會誤判；M-7 的授權檔照上游原檔保留，著作權資訊也已經寫在字型檔本身。
- 實作時另外發現：在 Windows 上，fetch 的連線還在關閉時呼叫 `process.exit()` 會觸發 libuv 斷言而崩潰（新測試「全部已發布」重現了這個狀況）。`upload.mjs`、`verify_remote.mjs` 改為設定 `process.exitCode`，讓程式自然結束。

**2026-09-25 Issue 1 合併**：PR #276（`epic-49/issue-1-fonts-cdn` → `main`）已合併。下一步：Issue 2（由人類執行 `deploy-wizard.sh` 部署，開始前先綁定付款方式）、Issue 3（App 端下載管線與字型管理畫面，可以和 Issue 2 平行進行）。

**2026-09-25 Issue 2 部署完成**：由人類執行 `deploy-wizard.sh`，建立 R2 bucket `elinkbook-fonts`、部署 Worker、上傳 5 個字型檔。

- Worker 網址（Issue 4 填入 App 的下載服務基底網址常數）：`https://elinkbook-fonts.huthief.workers.dev`
- 線上驗證：`verify_remote.mjs` 回報 `PASS`，5 個字型線上內容與清單一致。
- 工單審查 M-4：`curl -I https://elinkbook-fonts.huthief.workers.dev/v1/GuanKiapTsingKhai.ttf` 回應 `200 OK`，帶有 `Content-Type: font/ttf` 與 `Content-Length: 14675776`。
- 上傳時發現：在 Windows 上，wrangler 上傳第 3 個字型時偶發崩潰（結束碼 `3221226505`，即 `0xC0000409`），檔案沒有寫入 R2。同一條指令重跑就成功，之後重跑 wizard 時已上傳的字型自動略過，符合 Issue 1 的「中斷後可重跑補傳」設計。
