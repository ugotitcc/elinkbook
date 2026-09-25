# Epic 49 — 可下載字型：工單清單 (Issues)

依 `spec.md` 拆成 5 個工單。Issue 1、3 可以平行開發（App 端先以 `MockClient` 驗證，不需要線上服務，兩者也沒有共用檔案）；Issue 2 是人類操作的部署，完成後才能把真正的網址填進 App；Issue 4 需要 Issue 1 的字型清單、Issue 2 的網址、Issue 3 的 store，負責閱讀器套用與「字型目錄一致性測試」；Issue 5 是最後的真機驗證。

**相依順序**：Issue 1（服務程式）→ Issue 2（部署，人類）；Issue 3（下載與字型管理畫面）與 Issue 1 平行 → Issue 4（閱讀器套用）依賴 1、2、3 → Issue 5（真機驗證，人類）依賴 4。

```
Issue 1 ──> Issue 2（人類）──┐
                             ├──> Issue 4 ──> Issue 5（人類）
Issue 3 ─────────────────────┘
```

---

## Issue 1：字型下載服務程式（`fonts-cdn/`：Worker、字型清單、上傳與驗證腳本、部署 wizard）

**Status:** completed

**依賴：** 無，可立即開始。

**What to build：**
- 在 repo 根目錄新增 `fonts-cdn/`。
- `fonts/`：5 款字型原檔。思源黑體、思源宋體、台灣圓體、源流明體從 commit `eddcc85e^` 的 `app/assets/fonts/` 還原（blob 不變，不增加 repo 大小），原俠正楷從 `app/assets/fonts/` **移過來**（移除原位置的檔案）。一併放入各字型的 SIL OFL 授權檔。
- 更新 `app/pubspec.yaml` 字型區塊的註解：原俠正楷字型檔已不在 `assets/fonts/`，5 款原檔都改放在 `fonts-cdn/fonts/`（工單審查 I-2）。
- 字型清單（JSON）：每款字型的發布路徑（`v1/<檔名>`）、位元組大小、SHA-256，數值必須和 `spec.md`「字型目錄」表格一致。
- Worker 程式與 `wrangler` 設定，HTTP 介面依 `spec.md`「字型下載服務」（GET 用 `bucket.get()`、HEAD 用 `bucket.head()`；200 含標頭、404、405、不列出檔案）。
- 上傳腳本：依字型清單逐一 `wrangler r2 object put`；目標 key 已存在時直接中止（永不覆蓋）；上傳前先比對本機檔案的 SHA-256 與清單一致。
- 線上驗證腳本：給定 Worker 網址，逐一下載 5 個檔案並比對大小與 SHA-256，全部一致才算通過。
- 部署 wizard（用 `/wizard` skill 產生）：引導建立 Cloudflare 帳號、綁付款方式、啟用 R2、建立 bucket、`wrangler login`、部署 Worker、執行上傳腳本、執行驗證腳本、把 Worker 網址回報回來。
- `fonts-cdn/README.md`：說明目錄用途、發布規則（永不覆蓋、改版用新版本路徑）、各腳本用法。

**單元測試要求：**
- Worker 的 Node 單元測試（純 Node 內建模組、免 npm install）：以假的 R2 binding 呼叫 Worker 的 `fetch`，覆蓋 GET 200（`Content-Type`、`Content-Length`、`ETag`、`Cache-Control` 標頭）、HEAD 200 無 body 且標頭與 GET 相同、HEAD 只呼叫 `head()` 完全不呼叫 `get()`（假 binding 記錄呼叫，設計審查 I-1）、物件不存在 404、根路徑與非 `v1/` 路徑 404、POST／PUT／DELETE 405。
- 字型清單自我檢查：Node 腳本比對 `fonts/` 內實際檔案的大小與 SHA-256 和清單一致。

**驗收標準：** Worker 測試全數通過；字型清單自我檢查通過；`app/assets/fonts/` 已不存在任何字型檔；`pubspec.yaml` 註解與實際檔案位置一致；`flutter test`（涉及字型 asset 的測試檔）仍通過。

**Blocked by：** 無。

---

## Issue 2：部署字型下載服務（人類操作）

**Status:** ready-for-human

**依賴：** Issue 1。

**開始前準備**（工單審查 M-2）：Cloudflare 帳號必須**先綁定付款方式**（信用卡或 PayPal）才能啟用 R2；用量在免費額度內不會扣款。沒有先綁，wizard 會在啟用 R2 那一步卡住。

**What to do：** 執行 Issue 1 的部署 wizard：建立 R2 bucket、部署 Worker、上傳 5 個字型檔、執行線上驗證腳本。

**驗收標準：** 線上驗證腳本對 5 個檔案全部通過；`curl -I <Worker 網址>/v1/GuanKiapTsingKhai.ttf` 的回應帶有 `content-length: 14675776`（確認 Workers 執行環境下 HEAD 仍保留 `Content-Length`，本機單元測試無法驗證這點，Issue 1 程式審查 M-4）；把 Worker 的 `workers.dev` 網址記錄到 `epic.md`，供 Issue 4 填入 App 常數。

**Blocked by：** Issue 1。

---

## Issue 3：下載與字型管理畫面（`DownloadableFontStore`＋字型管理 UI）

**Status:** ready-for-agent

**依賴：** 無（以 `MockClient` 開發，下載服務的基底網址先用暫定常數，Issue 4 再換成正式網址；不讀取 `fonts-cdn/`，和 Issue 1 沒有檔案相依）。

**What to build：**
- 字型目錄：`AppFont` 每個啟用中的值對應發布路徑、位元組大小、SHA-256（exhaustive switch；停用的 3 款沿用 `[字型停用]` 註解，數值照填在註解中）。下載服務基底網址為單一常數。
- `DownloadableFontStore`：依 `spec.md`「可下載字型儲存」實作：
  - `installedFonts()`、`delete()`、`directory`
  - `download()`：進度以整數百分比回報，只在數值改變時呼叫；已有下載進行中時拋出 `StateError`（規格審查 I-2）
  - `prepare()`：建立存放目錄、刪除殘留 `.part` 檔（規格審查 M-3、設計審查 M-1）
  - `FontDownloadException`（`network`／`http`／`integrity`／`storage`／`cancelled`）
- 依賴注入：`main.dart` 建構 store（存放目錄為 App 支援目錄下的 `downloaded-fonts/`），建構後呼叫一次 `prepare()`，比照 `CustomFontsRepository` 逐層傳到 `FontManagementScreen`；閱讀器端的傳遞留給 Issue 4。
- `FontManagementScreen` 內建字型區塊：
  - 每一列標題固定是字型名稱，副標題依狀態顯示大小、進度或錯誤訊息（失敗時仍顯示大小）（規格審查 M-2）。
  - **下載中的互斥**（工單審查 I-3）：只要有任何字型在下載，其他所有內建字型列的「下載」「重試」「刪除」都停用，只剩下載中那一列的「取消」可以按。AppBar「上傳自訂字型」**不停用**（上傳不複製檔案，見 `spec.md`）。
  - 刪除確認對話框：標題沿用 `fontManagementDeleteConfirmTitle`，內文用新增的 `fontManagementDownloadableDeleteConfirmMessage`（不帶參數、不查詢使用中書籍數量；規格審查 I-4）。
  - 離開畫面時取消進行中的下載。
- 三種語系的新字串（狀態、大小格式、按鈕、刪除確認內文、5 種錯誤訊息）。

**單元測試要求：**
- `DownloadableFontStore`（`MockClient` 串流回應＋暫存目錄）：
  - 下載成功後列為已下載
  - 雜湊不符 → `integrity` 且沒有留下任何檔案；取消 → `cancelled` 且沒有留下任何檔案；404／500 → `http`；連線例外 → `network`
  - 已下載時重新下載失敗，不影響既有檔案
  - `delete` 後不再列為已下載，刪除不存在的檔案不拋錯
  - 沒有 `Content-Length` 時，進度改用目錄中的大小
  - 以大量小區塊（例如 1KB × 數萬個）驗證進度回呼不超過 101 次、嚴格遞增、最後是 100（設計審查 I-3）
  - `prepare()` 會建立不存在的目錄，並刪除殘留 `.part` 檔、保留正式檔案
  - 下載進行中再呼叫 `download()` 拋出 `StateError`，進行中那一筆照常完成
- `FontManagementScreen` widget 測試（新增假的 store，放在 `test/support/`）：
  - 四種狀態的顯示，每種狀態標題都是字型名稱，失敗時仍顯示大小
  - 下載中時，其他列的「下載」「重試」「刪除」全部停用，AppBar「上傳」仍可按
  - 取消後回到未下載；失敗後重試
  - 刪除確認對話框：顯示可下載字型專屬內文；取消不刪、確認才刪
  - 離開畫面時呼叫取消
  - 英文介面的字型名稱與大小格式

**驗收標準：** 上述測試通過；`flutter analyze` 乾淨；`node tool/check_l10n_hardcoded_strings.js` 通過。

**Blocked by：** 無。

---

## Issue 4：閱讀器套用已下載字型

**Status:** ready-for-agent

**依賴：** Issue 1（字型清單）、Issue 2（正式網址）、Issue 3（store）。

**What to build：**
- 把 Issue 2 回報的 Worker 網址填入下載服務基底網址常數。
- `buildFontFaceCss()`：改為接收已下載的內建字型集合，只替已下載的字型輸出 `@font-face`，`src` 指向 `https://appassets.androidplatform.net/downloaded-fonts/v1/<檔名>`；自訂字型規則不變。
- `FoliateReaderView`（規格審查 I-1）：
  - 新增 `Set<AppFont> installedFonts`（預設 `const {}`）與 `String? downloadedFontsDirectory`（預設 `null`），兩者都是可選參數，既有的建構呼叫不必修改。
  - `downloadedFontsDirectory` 不為 `null` 時，才在 `WebViewAssetLoader` 註冊 `InternalStoragePathHandler(path: '/downloaded-fonts/', directory: <存放目錄>)`。
  - 移除 Dart 攔截 `/assets/fonts/` 的分支與 `loadFlutterFontAsset()`。
- `ReaderScreen`（工單審查 C-1、規格審查 C-1）：
  - 新增可選建構參數 `DownloadableFontStore? downloadableFontStore`，比照 `customFontsRepository` 由上層逐層傳入。
  - 新增狀態 `_downloadedFontsLoaded`，初始值為 `downloadableFontStore == null`。
  - 新增 `_loadDownloadedFonts()`（比照 `_loadCustomFonts()`）：完成時不論成功或失敗，都設 `_downloadedFontsLoaded = true` 並 `setState`；失敗時已下載字型集合為空。
  - **`_buildBody` 建構 Foliate 閱讀器的條件，必須同時要求 `_customFontsLoaded` 與 `_downloadedFontsLoaded`**。原因：`FoliateReaderView` 的初始網址（內含 `@font-face`）是 `late final`，提早建構就再也不會套用已下載的字型。
  - 把已下載字型集合與存放目錄傳給 `FoliateReaderView`，已下載字型集合也傳給 `ReaderSettingsSheet`。
- `ReaderSettingsSheet`：新增可選參數「已下載的內建字型」（預設 `const {}`），只列出這些字型；沒有任何已下載的內建字型時，在選單下方顯示「到『字型管理』下載更多字型」提示（三種語系）。
- 更新 `CLAUDE.md` 中描述字型服務方式的段落（若有），使其符合新架構。

**單元測試要求：**
- `buildFontFaceCss`：沒有已下載字型時不輸出內建字型規則；只下載思源黑體時只輸出一條且網址正確；自訂字型規則不受影響。
- `ReaderScreen` 建構時機（C-1 的回歸測試）：注入 `installedFonts()` 由 `Completer` 控制的假 store，完成前**不**建構 `FoliateReaderView`；完成後才建構，且收到正確的已下載字型集合。
- `ReaderScreen` 沒有傳入 store（工單審查 M-1）：開書不等待、正常顯示閱讀器、已下載字型集合為空，行為與現在相同。
- `ReaderSettingsSheet`：只列出已下載的內建字型；一款都沒有時顯示提示，有時不顯示；偏好值指向未下載字型時顯示「使用書本字型」。
- 字型目錄一致性（工單審查 I-1，從 Issue 3 移到這裡）：讀取 `fonts-cdn/` 的字型清單，斷言與 App 字型目錄的路徑、大小、SHA-256 完全一致。
- `ReaderScreen`／`FoliateReaderView` 既有測試：新增參數後零回歸。
- 移除 `loadFlutterFontAsset` 相關測試。

**驗收標準：** 異動檔案的測試通過；完整 `flutter test` 通過（本 Epic 最後一個 agent 工單）；`flutter analyze` 乾淨；l10n 檢查通過。

**Blocked by：** Issue 1、Issue 2、Issue 3。

---

## Issue 5：真機驗證（人類操作）

**Status:** ready-for-human

**依賴：** Issue 4。

**What to do：** 在真機（至少一台一般 Android 手機＋一台電子紙閱讀器）上：
1. 安裝 App，確認字型管理畫面列出思源黑體／宋體為「未下載」並顯示大小。
2. 下載思源宋體：進度正常、完成後變成「已下載」；中途取消一次，確認回到「未下載」。在電子紙閱讀器上確認下載過程中畫面沒有明顯閃爍或卡頓。
3. 開一本書，在閱讀設定選擇思源宋體，以 `chrome://inspect` 連上 WebView，在 DevTools「Computed → Rendered Fonts」確認實際使用的是 `SourceHanSerifTC`，而不是 Noto 系統字型。直排與橫排各檢查一次。
4. 開啟飛航模式，重新開書，確認字型仍然正確。
5. 刪除思源宋體，確認該書閱讀設定顯示「使用書本字型」；重新下載後自動恢復為思源宋體。
6. 翻頁數十頁，確認沒有因字型載入造成明顯卡頓。
7. 下載思源宋體到一半時，從多工畫面把 App 滑掉；重新開啟 App 後，確認該字型仍是「未下載」，而且可以正常重新下載。

**驗收標準：** 以上 7 項全部通過，結果記錄到 `epic.md`。

**Blocked by：** Issue 4。
