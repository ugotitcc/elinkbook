# Epic 49 — 可下載字型：工單清單 (Issues)

依 `spec.md` 拆成 5 個工單。Issue 1、3 可以平行開發（App 端先以 `MockClient` 驗證，不需要線上服務，兩者也沒有共用檔案）；Issue 2 是人類操作的部署，完成後才能把真正的網址填進 App；Issue 4 需要 Issue 1 的字型清單、Issue 2 的網址、Issue 3 的 store，負責閱讀器套用與「字型目錄一致性測試」；Issue 5 是最後的真機驗證。Issue 6 是 Issue 4 程式審查 M-1 追加的工單（未下載字型時閱讀器改用書本字型），依賴 Issue 4，建議在 Issue 5 之前完成。

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

**Status:** completed

**依賴：** Issue 1。

**開始前準備**（工單審查 M-2）：Cloudflare 帳號必須**先綁定付款方式**（信用卡或 PayPal）才能啟用 R2；用量在免費額度內不會扣款。沒有先綁，wizard 會在啟用 R2 那一步卡住。

**What to do：** 執行 Issue 1 的部署 wizard：建立 R2 bucket、部署 Worker、上傳 5 個字型檔、執行線上驗證腳本。

**驗收標準：** 線上驗證腳本對 5 個檔案全部通過；`curl -I <Worker 網址>/v1/GuanKiapTsingKhai.ttf` 的回應帶有 `content-length: 14675776`（確認 Workers 執行環境下 HEAD 仍保留 `Content-Length`，本機單元測試無法驗證這點，Issue 1 程式審查 M-4）；把 Worker 的 `workers.dev` 網址記錄到 `epic.md`，供 Issue 4 填入 App 常數。

**Blocked by：** Issue 1。

---

## Issue 3：下載與字型管理畫面（`DownloadableFontStore`＋字型管理 UI）

**Status:** completed

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

**Status:** completed

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

**Status:** completed

**依賴：** Issue 4。

**What to do：** 在真機（至少一台一般 Android 手機＋一台電子紙閱讀器）上：
1. 安裝 App，確認字型管理畫面列出思源黑體／宋體為「未下載」並顯示大小。
2. 下載思源宋體：進度正常、完成後變成「已下載」；中途取消一次，確認回到「未下載」。在電子紙閱讀器上確認下載過程中畫面沒有明顯閃爍或卡頓。
3. 開一本書，在閱讀設定選擇思源宋體，以 `chrome://inspect` 連上 WebView，在 DevTools「Computed → Rendered Fonts」確認實際使用的是 `SourceHanSerifTC`，而不是 Noto 系統字型。直排與橫排各檢查一次。
4. 開啟飛航模式，重新開書，確認字型仍然正確。
5. 刪除思源宋體，確認該書閱讀設定顯示「使用書本字型」；重新下載後自動恢復為思源宋體。
6. 翻頁數十頁，確認沒有因字型載入造成明顯卡頓。
7. 下載思源宋體到一半時，從多工畫面把 App 滑掉；重新開啟 App 後，確認該字型仍是「未下載」，而且可以正常重新下載。
8. （Issue 4 程式審查 M-2）在最舊的目標裝置（Android 11 或電子紙閱讀器）上，以 `chrome://inspect` 的 Network 面板確認 `/downloaded-fonts/v1/*.ttf` 請求回應 200，並記錄實際的 `Content-Type`（androidx.webkit 1.12 的副檔名表沒有 `ttf`，會交給系統判斷，舊版系統可能不是 `font/ttf`）；同時確認字型確實有套用（同第 3 項）。若字型沒有套用，回報後另開工單處理。
9. （Issue 6 程式審查 M-2）找一本書本 CSS 有宣告字型的 EPUB，閱讀中先選一款已下載的內建字型，確認畫面改用該字型；再在閱讀設定改選「使用書本字型」，確認畫面立即回到書本字型，沒有殘留剛才的字型（用 DevTools「Computed → Rendered Fonts」確認）。接著旋轉螢幕一次，確認仍是書本字型。

**驗收標準：** 以上 9 項全部通過，結果記錄到 `epic.md`。

**Blocked by：** Issue 4。

---

## Issue 6：偏好指向未下載的內建字型時，閱讀器改用書本字型（Issue 4 程式審查 M-1）

**Status:** completed

**依賴：** Issue 4。

**背景：** 書籍偏好的字型是某款內建字型（例如 `SourceHanSerifTC`），但這款字型還沒下載或已被刪除時：
- 閱讀設定的字型選單顯示「使用書本字型」（Issue 4 的設計）。
- 但 `ReaderScreen` 仍把原本的偏好值傳給 `FoliateReaderView`（`reader_screen.dart` 建構閱讀器處的 `fontFamily: resolved.fontFamily`），`main.js` 會注入 `font-family: '<偏好值>' !important`。因為沒有對應的 `@font-face`，WebView 改用系統預設字型，把書本 CSS 宣告的字型蓋掉。

結果是畫面和選單說的不一致。規格使用者故事 24 允許「由書本或系統字型補位」，所以不算違規，但升級後還沒下載字型的使用者都會遇到，對內嵌字型的書影響最明顯。

**What to build：**
- `ReaderScreen` 傳給 `FoliateReaderView` 的 `fontFamily`：值是某個 `AppFont` 的 family name，但不在 `_installedFonts` 裡時，改傳 `null`（使用書本字型）。
- 只影響渲染，**不改寫**書籍偏好；重新下載該字型後自動恢復，和選單「只影響顯示」的語意一致。
- 自訂字型（`CustomFont`）與未知的 family name 行為不變。

**單元測試要求：**
- 偏好為未下載的內建字型時，`FoliateReaderView` 收到的 `fontFamily` 是 `null`；偏好值本身沒有被改寫。
- 偏好為已下載的內建字型時，照原值傳遞。
- 偏好為自訂字型時，照原值傳遞。
- 沒有傳入 `downloadableFontStore`（已下載集合為空）時的行為需明確決定並寫進計畫（沒有 store 的情境只出現在測試與舊呼叫端）。

**驗收標準：** 異動檔案的測試通過；`flutter analyze` 乾淨。完成後 Issue 5 第 5 項「刪除思源宋體」時，畫面應同時改回書本字型。

**Blocked by：** Issue 4。

---

## Issue 7：系統 WebView 太舊時不列出可下載字型（Issue 5 第 8 項失敗）

**Status:** completed

**依賴：** Issue 4。

**背景：** Issue 5 第 8 項在電子紙閱讀器（Android 12、WebView 91.0.4472.114）失敗。選「思源宋體」後，畫面退回系統字型，`adb logcat` 的 WebView console 訊息為：

```
Failed to decode downloaded font: https://appassets.androidplatform.net/downloaded-fonts/v1/SourceHanSerifTC-VF.ttf
OTS parsing error: Web font size more than 30MB
```

舊版 WebView 拒絕超過 30 MB 的網頁字型。思源宋體 57.1 MB、思源黑體 34.4 MB 都超過，所以這類裝置上兩款字型下載後都無法使用。手機 WebView 154.0.8037.49 正常。詳見 `epic.md`「2026-09-26 Issue 5 真機驗證」。

人類決定的修正方向：偵測到系統 WebView 太舊時，不列出這兩款字型。

**What to build：**
- 取得系統 WebView 版本：`InAppWebViewController.getCurrentWebViewPackage()`（`flutter_inappwebview_platform_interface` 1.3.0 已提供，底層為 `WebViewCompat.getCurrentWebViewPackage`），解析 `versionName` 的主版本號。
  > **程式審查修訂（`review-issue-7.md` I-1，人類裁定採方案 a）**：部分廠商 WebView 的 `versionName` 不是 Chromium 版本編號，會把新 WebView 誤判成舊的。改讀 `InAppWebViewController.getDefaultUserAgent()`，從 User-Agent 的 `Chrome/NN` 取 Chromium 主版本號；找不到時同樣視為讀不到版本。
- 決定門檻版本：查 Chromium 原始碼歷史，找出放寬「Web font size more than 30MB」限制的版本，寫進計畫並附來源。目前已知：91 不行、154 可以。查不到確切版本時，計畫需寫明採用的保守門檻與理由。
- 系統 WebView 低於門檻時：
  - 字型管理畫面不列出思源黑體、思源宋體。
  - 閱讀設定的字型選單不列出這兩款，即使裝置上已經有下載好的檔案。
  - 閱讀器視同這兩款「未下載」，偏好指向它們時改用書本字型（沿用 Issue 6 的 `_renderedFontFamily()` 行為），**不改寫**偏好。
- 讀不到 WebView 版本或解析失敗時的行為，計畫需明確決定並寫明理由。
- 計畫需決定：舊 WebView 裝置上已經下載的字型檔要不要提供刪除入口（檔案仍佔用儲存空間，思源宋體約 57 MB）。

**單元測試要求：**
- 版本字串解析：`91.0.4472.114`、`154.0.8037.49`、空字串、格式錯誤的字串。
- 低於門檻時：字型管理畫面不顯示兩款字型；閱讀設定選單不列出兩款字型（即使已下載）；`FoliateReaderView` 收到的 `fontFamily` 是 `null`，偏好值沒有被改寫。
- 達到門檻時：行為與現在相同（零回歸）。
- 讀不到版本時：符合計畫決定的行為。

**驗收標準：** 異動檔案的測試通過；`flutter analyze` 乾淨；l10n 檢查通過。完成後在電子紙閱讀器（WebView 91）重做 Issue 5 第 8 項：字型管理與閱讀設定都不出現這兩款字型，已選思源宋體的書改用書本字型。

**Blocked by：** Issue 4。

---

## Issue 8：恢復原俠正楷、台灣圓體、源流明體三款可下載字型

**Status:** completed

**進度（2026-09-26）：** 實作與測試已完成，真機確認待人類補測。完整 `flutter test` 2914 通過、1 跳過、0 失敗（`epic-51-wifi-transfer-test-fix` 的 WiFi 測試本次通過，見 epic.md）；`flutter analyze`乾淨；l10n 檢查兩行 PASS；debug APK 已建置。真機 6 步（手機 9491G ×3、電子紙 WAVE ×3）已通過；電子紙第 4 步第一次因啟動時讀 WebView 版本逾時而列出 5 款，改為沿用上次記住的版本後通過（見 epic.md）。

**依賴：** Issue 7。

**背景：** epic-48 把原俠正楷、台灣圓體、源流明體以 `[字型停用]` 註解停用。本 Epic 的 `spec.md` 把「恢復這 3 款」列為範圍外，只先把字型檔上傳到 R2（Issue 2 已上傳，`verify_remote.mjs` 回報 `PASS`）。Issue 7 完成後，人類決定在歸檔前追加本工單，把 3 款字型恢復為可下載字型（`spec.md` 使用者故事 34）。

3 款字型都小於 30 MB（14,675,776／21,704,488／15,976,964 bytes），依 Issue 7 的判斷，WebView 91 的電子紙也載得動。

**What to build：**
- 解除 `[字型停用]` 標記，恢復 3 個 enum 值與所有 switch 分支：
  - `app/lib/reader/app_font.dart`：enum 值、`familyName`（`GuanKiapTsingKhai`／`TaiwanPearl`／`GenRyuMinTW`）、說明註解。
  - `app/lib/reader/font_download_catalog.dart`：`fontDownloadSpecOf()` 的 3 筆下載資訊（數值已與 `spec.md` 一致，不重新計算）。
  - `app/pubspec.yaml` 第 230 行附近的 `[字型停用]` 註解，改成反映現況。
- `displayName()` 補上 3 款，新增 3 個 l10n key，4 個 arb 都要加（`app_zh_TW.arb` 含 `@` 說明）。英文名稱由計畫決定並寫明來源（例如字型檔 `name` table 的英文家族名）。
- 確認 `sqlite_library_repository.dart` 約 804 行的舊偏好對照（`'guanKiapTsingKhai': 'GuanKiapTsingKhai'` 等）與恢復後的 `familyName` 一致；不一致時計畫需決定怎麼處理。
- 確認 `app/assets/fonts/` 是否還有原俠正楷原檔（epic-48 留下的）。APK 不能打包任何字型檔（ADR 0035），計畫需決定是否刪除該檔案。
- 不改 Worker、R2、`fonts-cdn/`：檔案已上傳，發布路徑維持 `v1/`。

**單元測試要求：**
- `font_download_catalog_test.dart`：字型目錄一致性測試涵蓋 5 款，與 `fonts-cdn/fonts.json` 的大小、SHA-256、發布路徑一致。
- `AppFont.values` 為 5 款，依 enum 順序；`familyName`、`displayName()` 三語系都正確。
- 字型管理畫面：5 款都列出（WebView 107 以上）；WebView 91 時只列出 3 款新恢復的字型，思源黑體、思源宋體隱藏並顯示 Issue 7 的提示。
- 閱讀設定：已下載的新字型出現在選單，選用後 `FoliateReaderView` 收到正確的 `fontFamily`。
- 既有測試裡寫死「只有 2 款」的斷言，依新行為更新，並在計畫中列出。

**驗收標準：** 異動檔案的測試通過；完整 `flutter test` 除 `epic-51-wifi-transfer-test-fix` 的既有失敗外全部通過；`flutter analyze` 乾淨；l10n 檢查通過。真機確認：
- 手機（WebView 154）：5 款都能下載，選用後畫面字型正確。
- 電子紙（WebView 91）：只列出 3 款新字型，下載後畫面字型正確（確認 Issue 7 依大小判斷真的生效），`adb logcat` 沒有 `OTS parsing error`。

**Blocked by：** Issue 7（已完成）。
