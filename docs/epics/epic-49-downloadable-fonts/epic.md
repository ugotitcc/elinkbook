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

**2026-09-25 Issue 2 合併**：PR #277（`epic-49/issue-2-deploy` → `main`）已合併。另外補一個 commit 到 `main`，把 wrangler 本機暫存資料夾 `fonts-cdn/.wrangler/` 加進 `.gitignore`。下一步：Issue 3（App 端下載管線與字型管理畫面）；Issue 4 等 Issue 3 完成後才能開始。

**2026-09-25 Issue 3 完成**（`plans/plan-issue-3.md`，7 個 Task 全數執行完畢）：

- 新增 `app/lib/reader/font_download_catalog.dart`：`kFontDownloadBaseUrl`（本 Issue 用 `https://elinkbook-fonts.invalid/`，Issue 4 換正式網址）、`FontDownloadSpec`、`fontDownloadSpecOf()`（exhaustive switch，停用 3 款沿用 `[字型停用]` 註解，數值與 `spec.md` 一致）。
- 新增 `app/lib/reader/downloadable_font_store.dart`：`DownloadableFontStore`（`prepare`／`installedFonts`／`download`／`delete`／`directory`）、`FontDownloadException`（`network`／`httpStatus`／`integrity`／`storage`／`cancelled`）、`FontDownloadCancellationToken`。下載先寫 `.part`、SHA-256 相符才改名（Windows 先刪舊檔）；進度為 0～100 整數、只在變大時回報；重疊下載拋 `StateError`。
- 字型管理畫面：注入 `downloadableFontStore`（可選，未注入時維持既有行為）後內建字型列呈現未下載／下載中／已下載／失敗四種狀態，下載互斥（AppBar 上傳不停用），刪除用專屬內文 `fontManagementDownloadableDeleteConfirmMessage`（不動書籍偏好）；`formatFontFileSize()` 純函式；`test/support/fake_downloadable_font_store.dart`（Issue 4 沿用）。
- 依賴注入：`main.dart` 建構 store（`downloaded-fonts/`，啟動呼叫 `prepare()`，失敗不擋啟動）→ `ElinkBookApp` → `LibraryReaderFeatureRepositories` → `AdaptiveShellScaffold` → `SettingsScaffold` → `FontManagementScreen`。
- 測試：`font_download_catalog_test.dart`（3/3）、`downloadable_font_store_test.dart`（21/21，含進度節流、取消、中途斷線、StateError；變異檢查各一項符合預期，另有一項記錄於執行紀錄）、`font_management_screen_test.dart`（26/26，含變異檢查）、`settings_scaffold_test.dart`（新增注入測試）。完整套件 `flutter test`：2847 通過、1 跳過（`All tests passed!`）；`flutter analyze` 乾淨；l10n 稽核兩行 PASS。

**2026-09-25 Issue 3 程式審查修訂**（`reviews/review-issue-3.md`：修正後可合併，0 Critical／3 Important／7 Minor；人類裁定 I-2 閒置逾時 30 秒，其餘依審查意見修訂）

- I-1：store 把下載過程中的所有例外統一轉成 `FontDownloadException`：已取消的一律回報 cancelled，TLS 失敗、連線中斷、逾時和其他未預期例外回報 network。畫面另外加一層兜底，萬一收到其他例外，仍顯示網路錯誤並允許重試。新增測試：送出時 `HandshakeException`、串流途中 `TlsException`；畫面遇到 `StateError` 時顯示錯誤。
- I-2：`DownloadableFontStore` 新增 `idleTimeout`（預設 30 秒）。等待伺服器回應，或兩個資料區塊之間超過這個時間，就視為網路失敗；這不是整個下載的時間上限。`FontDownloadCancellationToken` 新增 `whenCancelled`，取消會立即中斷等待回應與串流，不必等下一個資料區塊；同時以 `http.AbortableRequest` 的 `abortTrigger` 中止連線。新增 4 個測試（伺服器不回應、串流停住、停住時取消、等待回應時取消），變異檢查確認「立即取消」的測試有效。
- I-3：`finally` 第一行就重設 `_downloading`，刪除 `.part` 失敗時略過。刪除失敗在測試環境中無法穩定重現，所以沒有加測試。
- M-1：重疊下載測試改為每次請求回傳新的串流，並斷言錯誤訊息內容和只送出一次請求；變異檢查（拿掉防護）確認測試會失敗。
- M-2：每寫入 1 MB 就 `flush()` 一次，寫檔錯誤能及早發現，也有背壓。
- M-3：刪除已下載字型失敗時攔下錯誤並重新讀取已下載清單；新增測試。
- M-4：計畫檔第 3 行的說明文字改回 `- [ ]`。
- M-5：已下載清單載入完成前只顯示大小、不顯示操作按鈕；讀取失敗時視為沒有已下載的字型。新增測試。
- M-6：HTTP 非 200，或取消／逾時後才收到回應時，都會取消訂閱回應內容；新增測試。
- M-7：`FakeDownloadableFontStore.fail()` 改為接受任意例外，並新增 `deleteError`。
- 驗證：異動的 4 個測試檔共 104 個測試通過；`flutter analyze` 乾淨；l10n 檢查通過；完整 `flutter test` 2857 個測試全數通過。

**2026-09-25 Issue 3 合併**：PR #278（`epic-49/issue-3-downloadable-font-store` → `main`）已合併。下一步：Issue 4（閱讀器套用已下載字型、`kFontDownloadBaseUrl` 改為正式 Worker 網址、閱讀設定下拉選單只列已下載字型、字型目錄一致性測試），需先撰寫 `plans/plan-issue-4.md`；之後是 Issue 5 真機驗證。

**2026-09-25 撰寫 Issue 4 實作計畫**（`/writing-plans`）：`plans/plan-issue-4.md`，共 6 個 Task：正式網址與字型目錄一致性測試、`buildFontFaceCss` 只替已下載字型輸出、`FoliateReaderView` 註冊 `/downloaded-fonts/` 處理器、閱讀設定只列出已下載字型與提示、`ReaderScreen` 延後建構、整體驗證。計畫中刻意與 issues.md 不同的三點：

- 刪除 `_fontFileName()`，CSS 網址改用字型目錄的 `publishPath`，確保 CSS 網址和 store 存檔路徑一致；新增共用常數 `kDownloadedFontsPathPrefix`。
- `ReaderScreen` 內部搜尋畫面用的 `LibraryReaderFeatureRepositories` 不傳 store：從閱讀器進入搜尋時只會 `pop` 回跳轉目標，不會建構新的閱讀器。
- `CLAUDE.md` 沒有描述舊字型服務方式的段落（已用 grep 確認），不需要修改。

**2026-09-25 Issue 4 計畫審查修訂**（`reviews/review-plan-issue-4.md`：Approved with Recommendations，0 Critical／2 Important／1 Minor）

- I-1 不採納：審查建議讀取 `fonts-cdn/fonts.json` 時，加上「以 repo 根目錄為工作目錄」的回退路徑。`flutter test` 的工作目錄固定是 package 根目錄（`app/`），從 IDE 點選執行也一樣。專案裡已經有 9 個測試檔用 `File('test/fixtures/…')` 讀取檔案，依賴的也是同一個前提。只在這一個測試加回退路徑，和其他測試不一致，也沒有實際效益。
- I-2 採納：Task 5 在 `_openBookSearch` 的 `LibraryReaderFeatureRepositories` 補上 `downloadableFontStore`，和同一處其他依賴保持一致。撰寫計畫時列為「刻意不同」的「搜尋畫面不傳 store」因此取消，刻意不同的地方剩兩點。
- M-1 採納：Task 6 的殘留檢查改用 `git grep`，Git Bash 與 PowerShell 都能直接執行。

**2026-09-26 Issue 4 完成**（分支 `epic-49/issue-4-reader-downloaded-fonts`，5 個實作提交，待 PR 合併與 Issue 5 真機驗證）

- Task 1：`kFontDownloadBaseUrl` 改為正式 Worker `https://elinkbook-fonts.huthief.workers.dev/`；新增基底網址斷言與字型目錄／`fonts-cdn/fonts.json` 一致性測試。
- Task 2：`buildFontFaceCss({installedFonts, customFonts})` 只替已下載字型輸出 `@font-face`，網址為前綴 `kDownloadedFontsPathPrefix` 加上字型目錄 `publishPath`；刪除 `_fontFileName()` 與 `loadFlutterFontAsset()`，移除 `foliate_reader_view.dart` 的 `/assets/fonts/` 攔截。測試改寫並把打包斷言改為閉包形式 `() => rootBundle.load(path)`（原寫法會在 Future 建構時同步拋出、matcher 來不及捕捉）。
- Task 3：`FoliateReaderView` 新增可選參數 `installedFonts`／`downloadedFontsDirectory`，有目錄時才註冊 `/downloaded-fonts/` 的 `InternalStoragePathHandler`，初始網址的 `fontFaceCss` 只含已下載字型。新測試的 group 加 `setUp` 恢復成功的 `cacheBookForServing`，避免被前面的 `mounted guard` 失敗 mock 污染（完整套件才會觸發）。
- Task 4：新增在地化字串 `readerSettingsDownloadMoreFontsHint`（4 個 ARB，`flutter gen-l10n` 重新產生）；`ReaderSettingsSheet` 新增 `installedFonts`，只列出已下載字型，一款都沒有時顯示提示，偏好指向未下載字型時顯示「使用書本字型」。
- Task 5：`ReaderScreen` 新增 `downloadableFontStore`，`_downloadedFontsLoaded` 與 `_customFontsLoaded` 同時 gating 才建構 Foliate 閱讀器；已下載集合與目錄傳給閱讀器，集合傳給設定面板；`reader_screen_route.dart` 與 `_openBookSearch` 一併傳遞。
- 新增測試約 15 個（Task 1 +2、Task 2 淨+1、Task 3 +3、Task 4 +5、Task 5 +4），另配合新簽名改寫既有測試（`_pumpSheet` 預設視為全部已下載，既有呼叫端零修改）。
- 完整 `flutter test`：2872 通過、1 跳過（`All tests passed!`，EXIT:0）；`flutter analyze`：`No issues found!`；l10n 檢查：兩行 PASS。
- 變異檢查：暫時拿掉 `&& _downloadedFontsLoaded`，第一個已下載字型測試失敗（閘門完成前就建構閱讀器），改回後全數通過。
- 和 issues.md 刻意不同的兩點（計畫開頭，審查 I-2 採納後剩兩點）：內建字型檔名不再另外維護（刪除 `_fontFileName()`，CSS 網址直接用字型目錄 `publishPath`）；`CLAUDE.md` 沒有描述舊攔截的段落，不需修改（Task 6 已用 `git grep` 確認）。

**2026-09-26 Issue 4 程式審查修訂**（`reviews/review-issue-4.md`：可合併，0 Critical／0 Important／4 Minor；人類裁定如下）

- M-1 登錄為新工單 Issue 6：偏好指向未下載的內建字型時，選單顯示「使用書本字型」，但閱讀器仍注入原偏好值，實際由系統預設字型蓋掉書本字型。Issue 6 改為在 `ReaderScreen` 渲染時傳 `null`，不改寫偏好。
- M-2 列入 Issue 5 第 8 項：androidx.webkit 1.12 的副檔名表沒有 `ttf`，在最舊的目標裝置確認 `/downloaded-fonts/` 請求回應 200、記錄實際 `Content-Type`，並確認字型有套用。
- M-3 採納：`reader_screen_test.dart` 的 `fake_downloadable_font_store.dart` import 移到其他 `../support/` import 旁邊。
- M-4 採納：閘門測試的自訂字型 fake 改用 `loadGate` 控制，先放行自訂字型、斷言閱讀器仍未建構，再放行已下載字型，明確建立「自訂字型已載入完成」這個前提。
- 驗證：`reader_screen_test.dart` 242 個測試通過；`flutter analyze` 乾淨；l10n 檢查兩行 PASS。

**2026-09-26 Issue 4 合併**：PR #279（`epic-49/issue-4-reader-downloaded-fonts` → `main`）已合併。下一步：Issue 6（偏好指向未下載的內建字型時閱讀器改用書本字型），需先撰寫 `plans/plan-issue-6.md`，建議在 Issue 5 前完成；之後是 Issue 5 真機驗證（8 項，人類操作）。

**2026-09-26 撰寫 Issue 6 實作計畫**（`/writing-plans`）：`plans/plan-issue-6.md`，共 2 個 Task：`ReaderScreen` 新增 `_renderedFontFamily()` 並以測試驅動實作、整體驗證與進度記錄。工單要求寫進計畫的決定：沒有傳入 `downloadableFontStore` 時照原值傳遞（只出現在測試與舊呼叫端，與 Issue 4「沒有 store 時行為不變」一致）；有 store 但讀取失敗時改傳 `null`（`@font-face` 本來就不會輸出）。epic-48 停用的 3 款字型名稱不在 `AppFont.values`，依工單「不認得的名稱行為不變」照原值傳。

**2026-09-26 Issue 6 計畫審查修訂**（`reviews/review-plan-issue-6.md`：Approved with Recommendations，0 Critical／0 Important；摘要寫 2 項 Minor，內文實際列出 3 項）

- M-1 採納：`_renderedFontFamily()` 第一行改為 `fontFamily == null` 時也直接回傳。效能差異可忽略，採納是為了讓最常見的「使用書本字型」情境一眼可讀。Task 1 Step 5 的變異檢查改為只拿掉「沒有 store」的判斷。
- M-2 採納：新增測試「偏好為 null（使用書本字型）時，閱讀器收到 null」，group 共 8 個測試；它在修改前就會通過，紅燈預期改為 3 個失敗、5 個通過，其餘數字（250、2880）同步更新。
- M-3 採納：新 group 的插入位置改為約 `:6671`（Issue 4 審查修訂 M-4 使行號後移，已實際確認）。

**2026-09-26 Issue 6 完成**（分支 `epic-49/issue-6-uninstalled-font-fallback`，待 PR 合併）

- `ReaderScreen` 新增 `_renderedFontFamily()`：有 store 且偏好指向未下載的內建字型時，傳給 `FoliateReaderView` 的 `fontFamily` 改為 `null`（書本字型）；不改寫偏好。沒有 store 時照原值傳（計畫決定）；讀取已下載字型失敗時也改傳 `null`；自訂字型與不認得的名稱照原值傳。
- 新增 8 個測試（`reader_screen_test.dart` group「未下載字型改用書本字型（epic-49 Issue 6）」）。
- 變異檢查：拿掉「沒有 store」的判斷後，僅「沒有 store 時照原值傳遞」失敗（`Expected: 'SourceHanSerifTC'  Actual: <null>`），改回後 8 個全部通過。
- 完整 `flutter test`：2880 通過、1 跳過；`flutter analyze`：`No issues found!`；l10n 檢查：兩行 PASS。

**2026-09-26 Issue 6 程式審查修訂**（`reviews/review-issue-6.md`：可合併，0 Critical／0 Important／2 Minor；人類裁定如下）

- M-1 合併前修正：「自訂字型照原值傳遞」測試原本用空的自訂字型清單，`'KingHwa_OldSong'` 其實和「不認得的名稱」走同一條路徑。改為先在 `FakeCustomFontsRepository` 插入同名的 `CustomFont`，讓前提和測試名稱一致。
- M-2 補單元測試並列入 Issue 5：`foliate_reader_view_test.dart` 新增「fontFamily 由有值變成 null：`foliatePreferencesChanged` 回傳 true，且新偏好不含 `fontFamily` 鍵」；`main.js` 整包取代覆蓋 CSS 的部分單元測試驗證不到，列入 Issue 5 第 9 項真機驗證（改選「使用書本字型」後畫面立即回到書本字型、旋轉後仍正確），Issue 5 驗收標準改為 9 項。
- 驗證：`reader_screen_test.dart`＋`foliate_reader_view_test.dart` 共 367 個測試通過；`flutter analyze` 乾淨；l10n 檢查兩行 PASS。

**2026-09-26 Issue 6 合併**：PR #280（`epic-49/issue-6-uninstalled-font-fallback` → `main`）已合併。epic-49 所有 agent 工單（Issue 1、3、4、6）與人類部署（Issue 2）皆已完成，只剩 Issue 5 真機驗證（9 項，人類操作）；通過後即可歸檔。

**2026-09-26 撰寫 Issue 5 實作計畫**（`/writing-plans`）：`plans/plan-issue-5.md`，寫成人類操作的驗證手冊，共 4 個 Task：準備 APK 與驗證書（agent）、一般手機（人類，第 1～7、9 項）、電子紙閱讀器（人類，第 2 項電子紙部分、第 6 項；第 8 項在兩台中較舊的那台做）、記錄結果（agent）。查證後定下的做法：只有 debug APK 能用 `chrome://inspect`（Android 對 debuggable App 自動開啟 WebView 遠端除錯，本專案沒有另外呼叫 `setWebContentsDebuggingEnabled`），效能相關項目改用 release APK；兩者都以 debug key 簽章，可用 `adb install -r` 互相覆蓋並保留資料，計畫禁止 `adb uninstall`。現有 fixture 都沒有在 CSS 宣告字型，所以另做一本驗證書（中文 `serif`、英文 `monospace`），讓 Rendered Fonts 分得出書本字型、思源宋體、系統預設字型三種狀態。

**2026-09-26 Issue 5 計畫審查修訂**（`reviews/review-plan-issue-5.md`：Approved with Recommendations，0 Critical／2 Important／5 Minor）

- I-1 採納：Git Bash 會把 `/sdcard/...` 改寫成 Windows 路徑。`adb push` 的目的地改寫成 `//sdcard/Download/`；`adb shell` 帶裝置端絕對路徑時加 `MSYS_NO_PATHCONV=1`（`push` 不用這個前綴，因為來源 `~/...` 仍需要轉成 Windows 路徑）。另補上 `adb` 不在 PATH 時的處理（本機 Git Bash 實測確實找不到 `adb`）。
- I-2 採納（做法不同於報告建議）：報告建議推送 `sample_long_chinese_vertical.epub`，但實際檢查它只有約 2,900 字、大約 7 頁，不夠翻 30 頁。改為在驗證書加入第 2 章「翻頁測試」（80 段、約 3.5 萬字），第 6 項直接用它，不另外推送其他書。
- M-1 採納：Task 1 結束時與 Task 4 開始前都明確回到 repo 根目錄，Task 4 另外確認目前分支。
- M-2 採納：Task 4 新增可選的清理步驟（裝置端驗證書、本機 `~/elinkbook-qa`；書庫裡的驗證書需在 App 內手動移除）。
- M-3 採納：WebView 版本改用 `dumpsys webviewupdate` 查詢，不必猜套件名稱。
- M-4 採納：結果表第 6 項拆成手機、電子紙兩列。
- M-5 採納：Step 10 補一句說明，第 7 項改用思源黑體是因為思源宋體在 Step 9 已經下載完成。

**2026-09-26 Issue 5 真機驗證**（分支 `epic-49/issue-5-device-qa`）

| 裝置 | 型號 | Android | WebView |
|---|---|---|---|
| 一般手機（Wi-Fi 平板） | 9491G（Hera_Vis_WIFI） | 15 | 154.0.8037.49 |
| 電子紙閱讀器 | Allwinner WAVE（E70P24） | 12 | `com.android.webview` 91.0.4472.114 |

| # | 項目 | 裝置 | 結果 | 觀察 |
|---|---|---|---|---|
| 1 | 字型管理列出未下載與大小 | 手機 | 通過 | 兩款皆顯示「未下載」，34.4 MB／57.1 MB，兩列都有「下載」按鈕 |
| 2 | 下載進度、取消、完成 | 手機 | 通過 | 進度持續增加；取消後回到「未下載」且無錯誤；完成後變「已下載」；下載中其他列按鈕停用 |
| 2 | 電子紙下載時無明顯閃爍或卡頓 | 電子紙 | 通過 | release APK，無整頁閃爍、無殘影、操作不卡 |
| 3 | 閱讀器套用思源宋體（橫排／直排） | 手機 | 通過 | 橫排、直排的中文段與 `p.mono` 皆為 `思源宋體 VF`（自訂字型），computed `font-family` 為 `SourceHanSerifTC`；直排標點方向正常 |
| 4 | 飛航模式重新開書字型正確 | 手機 | 通過 | 關閉 Wi-Fi（此機型無行動網路）後重開 App，三段皆為 `思源宋體 VF` |
| 5 | 刪除後退回書本字型、重新下載後恢復 | 手機 | 第一次失敗，重測通過 | 見下方說明 |
| 6 | 翻頁無明顯卡頓（橫排／直排） | 手機 | 通過 | release APK，第 2 章連翻 30 頁以上，順暢 |
| 6 | 翻頁無明顯卡頓、無額外刷新 | 電子紙 | 通過 | release APK，順暢；但此裝置實際渲染的是系統字型（見第 8 項），不代表思源宋體在電子紙上的翻頁效能 |
| 7 | 下載中途滑掉 App 後為未下載、可重新下載 | 手機 | 通過 | 重開後「未下載」；資料夾內無 `SourceHanSansTC-VF.ttf` 與 `.part`；重新下載完成，36,034,016 bytes |
| 8 | 最舊裝置字型請求 200、字型有套用 | 電子紙 | **失敗** | Content-Type：無法取得（此裝置 WebView 無遠端除錯）。字型未套用，原因見下方 |
| 9 | 改回使用書本字型後立即回到書本字型、旋轉後仍正確 | 手機 | 通過 | `p.mono` 為 `Droid Sans Mono`、中文為 `Noto Serif CJK TC`，無任何 `SourceHanSerifTC` 規則；轉成直向後不變 |

**第 8 項失敗：舊版 WebView 拒絕超過 30 MB 的網頁字型**

- 現象：電子紙選「思源宋體」後，英文段由等寬變成比例字寬（書本 `monospace` 被覆蓋），但中英文字形都是系統無襯線字型，不是思源宋體；5 分鐘後重截仍相同。字型檔 `SourceHanSerifTC-VF.ttf`（59,898,316 bytes）確實在 `files/downloaded-fonts/v1/`。
- 原因：`adb logcat` 的 WebView console 訊息為 `Failed to decode downloaded font: https://appassets.androidplatform.net/downloaded-fonts/v1/SourceHanSerifTC-VF.ttf` 與 `OTS parsing error: Web font size more than 30MB`。WebView 91 的字型檢查（OTS）拒絕超過 30 MB 的網頁字型。思源宋體 57.1 MB、思源黑體 34.4 MB 都超過，所以這類裝置上兩款可下載字型都無法使用；手機的 WebView 154 沒有這個問題。
- 重現步驟：在 WebView 91 的裝置下載思源宋體 → 開任一本書 → 字型選「思源宋體」 → `adb logcat -d | grep OTS`。
- 修正方向待人類決定是否另開工單。

**第 5 項：第一次失敗、隔離重測通過、原因不明**

- 第一次：從第 4 項（飛航模式）接著做。刪除思源宋體 → 開書（正確退回書本字型，提示正常）→ 重新下載 → 開書，選單顯示「使用書本字型」、畫面也是書本字型。複製 `library.db` 查詢，這本書 `book_reader_prefs.font_family` 已是 `NULL`；第 4 項重開 App 時它仍是 `SourceHanSerifTC`。期間 App 曾重啟一次（行程編號 28718 → 29000），原因不明。人類確認過程中沒有點字型選單或其他設定。
- 隔離重測：重選思源宋體後逐步查 `library.db`，刪除字型、開書、開閱讀設定（不操作）後 `font_family` 都維持 `SourceHanSerifTC`；重新下載後開書，選單自動顯示「思源宋體」，畫面為 `思源宋體 VF`。
- 查過的程式路徑：會把 `font_family` 改成 `NULL` 的只有閱讀設定選「使用書本字型」、刪除同名自訂字型（`custom_fonts` 為空，排除）、套用版面預設集／複製到其他書籍（未操作）；刪除下載字型（`_deleteDownloadedFont`）不碰偏好；同步不包含閱讀偏好。
- 未重現的差異：從飛航模式離線狀態接續、中途 App 重啟。人類決定記為「第一次失敗、重測通過、原因不明」。

**驗證方法與計畫不同之處**

- 手機 WebView 的 DevTools 連線每個指令延遲約 6 秒，Chrome DevTools 前端會逾時斷線。改用 `adb forward` 加 Chrome DevTools Protocol 腳本直接查 `CSS.getPlatformFontsForNode`（與 Rendered Fonts 相同）和 `CSS.getMatchedStylesForNode`（與 Styles 分頁相同）。
- Rendered Fonts 顯示字型檔內建名稱 `思源宋體 VF`，不是計畫寫的 `SourceHanSerifTC`；後者是 App 在 `@font-face` 取的別名，兩者是同一個檔案。
- 電子紙 WebView 沒有遠端除錯通道，第 8 項用計畫的截圖退路，再以 `adb logcat` 找到原因。
- 兩台裝置的 `adb` 傳輸約 20 KB/s，release APK 改用 USB 檔案傳輸複製後在裝置上安裝（同簽章覆蓋更新，資料保留）。
- 驗證書的 `mimetype` 必須是 ZIP 第一個項目；計畫的 7-Zip 兩次加入會重新排序，改用 Python `zipfile` 依序打包。

第 8 項失敗，Issue 5 維持 `ready-for-human`，`docs/epics.md` 不更新。修正工單由人類決定。
