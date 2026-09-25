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
