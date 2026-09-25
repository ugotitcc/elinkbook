# epic-49 可下載字型：規格（Architecting）

本文件是本 Epic 的唯一事實來源。決策背景見 `design.md`（Discovery，題號 Q1～Q20），架構取捨見 [ADR 0035](../../adr/0035-downloadable-fonts-via-r2-worker.md)。

## 問題陳述（Problem Statement）

內建字型的字型檔很大（思源黑體 34MB、思源宋體 57MB，5 款合計約 140MB），全部打包會讓 APK 大到難以散布；但完全不打包（`epic-48` 之後的現況），使用者選了思源黑體／宋體，實際看到的是系統字型補位，選思源宋體時甚至可能顯示成黑體。使用者沒辦法真正用到 App 提供的內建字型，也不知道為什麼選了沒效果。

## 解決方案（Solution）

內建字型改為「可下載字型」。字型管理畫面列出每款內建字型的狀態與檔案大小，使用者點「下載」後，App 從 elinkBook 的字型下載服務取得字型檔，驗證完整性後存在 App 私有目錄，之後完全離線使用。閱讀設定的字型選單只列出已下載的字型；一款都沒下載時，提示使用者到字型管理下載。已下載的字型可以刪除以釋放空間，刪除後書籍的字型偏好保留，重新下載就自動恢復。

## 使用者故事（User Stories）

### 瀏覽與了解狀態

1. 身為讀者，我想在字型管理畫面看到每款內建字型目前是「未下載」「下載中」還是「已下載」，這樣我知道哪些字型現在可以用。
2. 身為讀者，我想在下載前看到每款字型的檔案大小（例如「34.4 MB」），這樣我可以依網路和儲存空間決定要不要下載。
3. 身為讀者，我想看到依介面語系顯示的字型名稱，這樣切換成英文介面時也看得懂。
4. 身為讀者，我想讓內建字型和自訂字型分成兩個區塊顯示，這樣我分得清楚哪些是 App 提供的、哪些是我自己上傳的。

### 下載

5. 身為讀者，我想點某款字型旁的「下載」按鈕就開始下載，不需要其他設定步驟。
6. 身為讀者，我想在下載時看到進度條和百分比，這樣我知道還要等多久。
7. 身為讀者，我想隨時取消進行中的下載，這樣發現網路太慢或下錯字型時可以停止。
8. 身為讀者，我想在取消之後，該字型回到「未下載」狀態，不留下佔空間的半成品檔案。
9. 身為讀者，我想在下載失敗時看到簡單易懂的原因（網路中斷、伺服器錯誤、檔案損毀、儲存空間不足），並可以直接重試。
10. 身為讀者，我想讓 App 在下載完成時自動確認檔案完整，這樣我不會用到損毀或被竄改的字型檔。
11. 身為讀者，我想在一款字型下載中時，其他字型的下載按鈕暫時不能按，這樣不會多個下載同時搶頻寬、每個都很慢。
12. 身為讀者，我想在離開字型管理畫面時，進行中的下載自動取消並清掉半成品檔，這樣 App 不會在我不知情的情況下繼續用網路。
13. 身為使用電子紙閱讀器（沒有 Google Play Services）的讀者，我想正常下載字型，這樣我的裝置也能用內建字型。
14. 身為使用行動網路的讀者，我想在下載前就從檔案大小判斷流量，這樣不會被意外吃掉大量流量。

### 使用

15. 身為讀者，我想在下載完成後，閱讀設定的字型選單馬上出現這款字型。
16. 身為讀者，我想讓閱讀設定的字型選單只列出已下載的內建字型和我的自訂字型，這樣選了一定有效果。
17. 身為讀者，我想在一款內建字型都沒下載時，看到提示「到『字型管理』下載更多字型」，這樣我知道去哪裡取得字型。
18. 身為讀者，我想選了已下載的思源宋體後，書本真的用思源宋體顯示，而不是系統字型。
19. 身為讀者，我想在沒有網路的情況下，已下載的字型仍然正常顯示。
20. 身為讀者，我想在直排和橫排模式下，已下載的字型都正常顯示。
21. 身為讀者，我想讓大型字型（例如 57MB 的思源宋體）也能順暢地翻頁，不會因為載入字型而卡頓。

### 刪除

22. 身為讀者，我想刪除已下載的字型來釋放儲存空間。
23. 身為讀者，我想在刪除前看到確認對話框，避免誤刪大型字型後又要重新下載。
24. 身為讀者，我想在刪除字型後，原本設定用這款字型的書保留設定；閱讀時暫時由書本或系統字型補位，重新下載後自動恢復，這樣我不用一本一本重新設定。
25. 身為讀者，我想在刪除字型後，閱讀設定的字型選單顯示「使用書本字型」，而不是出現錯誤或空白。

### 剛安裝

26. 身為剛安裝 App 的讀者，我想在還沒下載任何字型時照常開書閱讀（使用書本字型或系統字型），不被強迫先下載。
27. 身為剛安裝 App 的讀者，我想要一個比較小的安裝檔，這樣下載和安裝都比較快。

### 維運（開發者）

28. 身為開發者，我想讓字型檔放在不必付費的託管服務上，這樣產品沒有額外的營運成本。
29. 身為開發者，我想讓已發布的字型檔永遠不被覆蓋，這樣舊版 App 寫死的雜湊值永遠有效。
30. 身為開發者，我想讓字型清單（檔名、大小、SHA-256）和 App 程式放在同一個 repo，這樣兩者不一致時一眼就能看出來。
31. 身為開發者，我想要一份 wizard 腳本，一步一步帶我建立 R2、部署 Worker、上傳字型，這樣只有在第一次或改版時才需要回想這些步驟。
32. 身為開發者，我想在部署完成後用一個指令驗證線上檔案的雜湊，這樣能確認 App 真的下載得到正確的檔案。
33. 身為開發者，我想讓字型下載服務只提供讀取、不能用來寫入或列出檔案，這樣服務不會被濫用。
34. 身為開發者，我想讓恢復停用字型（原俠正楷、台灣圓體、源流明體）時只需要解除 `[字型停用]` 標記，下載機制自動適用。

## 實作決策（Implementation Decisions）

### 字型目錄（Font Catalog）

- `AppFont` 的每個（啟用中的）列舉值都對應一筆固定的下載資訊：**發布路徑**（含版本號，例如 `v1/SourceHanSansTC-VF.ttf`）、**位元組大小**、**SHA-256**。用 exhaustive switch 實作，新增或恢復字型時少寫一項就會編譯失敗；停用的字型沿用 `[字型停用]` 註解標記。
- 目前的值（由 git 歷史中的原檔計算，`fonts-cdn/` 的字型清單必須和這裡一致）：

  | 字型 | 發布路徑 | 位元組 | SHA-256 |
  |---|---|---|---|
  | 思源黑體 | `v1/SourceHanSansTC-VF.ttf` | 36034016 | `1a273a56aa47250c7af95e461ee0c8236c60d7141e14a37bd18baccb1e851b19` |
  | 思源宋體 | `v1/SourceHanSerifTC-VF.ttf` | 59898316 | `71354ed752104c8a3cbcff18943c6110d179d01cc6eaaf1aff7ea14c4a447879` |
  | 原俠正楷（停用） | `v1/GuanKiapTsingKhai.ttf` | 14675776 | `758632243c499e431fd0c847f5e8c431acf59a9b41a26237a819466139994d38` |
  | 台灣圓體（停用） | `v1/TaiwanPearl-Regular.ttf` | 21704488 | `51b3c9a4ab1b6b45dcdad7c5ae93386aea399fd3dabb85d2ac41110dc57f211d` |
  | 源流明體（停用） | `v1/GenRyuMinTW-Regular.ttf` | 15976964 | `9178c199d633075b8bb91902216c3e1bc977a11fde12471a2c9a250434402927` |

- 下載服務的基底網址是 App 內的單一常數（Worker 的 `workers.dev` 網址，Issue 2 部署後填入）。App 不讀取遠端清單檔（manifest）。

### 可下載字型儲存（`DownloadableFontStore`，新增的核心模組）

- 建構時注入 `http.Client` 與存放目錄；正式環境的存放目錄是 App 支援目錄（`getApplicationSupportDirectory()`，非使用者可見、清除快取時不會被刪）底下的 `downloaded-fonts/`。本機路徑與發布路徑一致（`downloaded-fonts/v1/<檔名>`）。
- 介面：
  - `installedFonts()`：回傳已下載的內建字型集合。**判斷依據只有「正式檔案是否存在」**，不另外建資料表。
  - `download(font, {onProgress, cancellationToken})`：串流下載到同目錄的暫存檔（`.part`），邊下載邊計算 SHA-256；完成後比對雜湊，一致才改名為正式檔名。任何失敗或取消都會刪除暫存檔，且不影響已存在的正式檔。**已有下載進行中時再呼叫，直接拋出 `StateError`**（程式錯誤，不是使用者可見的失敗；正常情況下 UI 已經停用所有按鈕，這是第二道防線，規格審查 I-2）。
  - `delete(font)`：刪除正式檔案；不存在時不視為錯誤。
  - `prepare()`：App 啟動時呼叫一次，**建立存放目錄**（不存在時），並刪除所有殘留的 `.part` 暫存檔（見下方「啟動準備」）。
  - `directory`：存放目錄的絕對路徑，供閱讀器設定 WebView 的串流處理器。
- 失敗以單一例外型別 `FontDownloadException` 回報，帶有原因代碼：`network`（連線失敗）、`http`（非 200 狀態碼，附狀態碼）、`integrity`（SHA-256 不符）、`storage`（寫檔失敗，例如空間不足）、`cancelled`。UI 依代碼顯示在地化訊息（比照 ADR 0034「錯誤代碼在 Dart 端在地化」的精神），模組本身不產生使用者可見的文字。
- 下載成功與否的唯一標準是 SHA-256。`Content-Length` 只用來計算進度；伺服器沒回傳時，改用字型目錄中的位元組大小計算。
- **進度回報節流**（設計審查 I-3）：`onProgress` 回報的是 0～100 的整數百分比，**只在百分比數值改變時才呼叫**，一次下載最多 101 次。資料區塊可能每秒到達數十到上百次，若每個區塊都觸發 UI 重繪，電子紙裝置的重繪代價很高，會造成卡頓與殘影。節流放在 store 而不是畫面，所有使用者都自動受惠，也能在 store 的切面直接測試。
- **啟動準備**（設計審查 M-1、規格審查 M-3）：`main.dart` 在 App 啟動、建構 store 之後呼叫一次 `prepare()`（此時一定沒有進行中的下載），做兩件事：
  1. 建立存放目錄，讓閱讀器的 `InternalStoragePathHandler` 一定指向實際存在的目錄；剛安裝、還沒下載任何字型時也成立。
  2. 刪除所有殘留的 `.part` 檔。App 被使用者從多工畫面滑掉，或被系統因記憶體不足終止時，`dispose()` 與 `finally` 都不一定會執行，暫存檔（最大約 57MB）會留在存放目錄。

  此外 `download()` 開始前也會先刪除同一字型的舊暫存檔。
- 取消的做法沿用雲端下載既有的 cancellation token 模式：每收到一個資料區塊就檢查一次。

### 字型管理畫面

- 內建字型區塊的每一列，**標題固定是字型名稱**，副標題依狀態改變，右側是對應的按鈕（規格審查 M-2：任何狀態都看得出是哪一款字型）：
  - **未下載**：副標題顯示檔案大小；「下載」按鈕
  - **下載中**：副標題顯示進度條與百分比；「取消」按鈕
  - **已下載**：副標題顯示檔案大小；「刪除」按鈕
  - **失敗**：副標題顯示檔案大小與錯誤訊息；「重試」按鈕
- **同一時間只允許一個下載**（規格審查 I-2）：只要有任何字型在下載中，其他所有內建字型列的「下載」「重試」「刪除」按鈕都停用，只剩下載中那一列的「取消」可以按。store 本身也會拒絕重疊的下載（見上方 `download()`）。
  - AppBar 的「上傳自訂字型」按鈕**不停用**：自訂字型上傳只取得 `content://` 的永久存取權，不複製檔案（ADR 0021），不會和下載搶寫入或儲存空間，沒有互斥的必要。
- 刪除前顯示確認對話框（說明刪除後可重新下載，使用中的書籍會暫時改用書本或系統字型）。刪除**不會**修改 `book_reader_prefs`（與自訂字型的 `deleteAndResetUsage` 刻意不同，見 ADR 0035），所以也**不查詢**使用中的書籍數量。對話框使用專屬的在地化字串，**不可**沿用自訂字型的 `fontManagementDeleteConfirmMessage`：那個字串必須帶 `{usageCount}` 複數參數，而且文意是「會改用預設字型」，和可下載字型的行為不符（規格審查 I-4，字串名稱見「在地化字串」）。
- 離開畫面（`dispose`）時取消進行中的下載。
- 畫面建構時注入 `DownloadableFontStore`，依賴注入的方式比照 `CustomFontsRepository` 由 `main.dart` 逐層傳遞。

### 閱讀器

- **字型檔服務方式**：`FoliateReaderView` 的 `WebViewAssetLoader` 新增一個 `InternalStoragePathHandler`，把 `/downloaded-fonts/` 對應到字型存放目錄，由原生端直接串流，不經過 Dart（理由見 ADR 0035）。原本 Dart 攔截 `/assets/fonts/` 並讀取 Flutter asset 的分支，以及 `loadFlutterFontAsset()`，一併移除。
- **`@font-face` 產生**：`buildFontFaceCss()` 改為接收已下載的內建字型集合，**只替已下載的字型**輸出 `@font-face`，`src` 指向 `https://appassets.androidplatform.net/downloaded-fonts/v1/<檔名>`。未下載的字型不輸出規則，避免 WebView 發出注定失敗的請求。自訂字型的規則維持不變。
- **`FoliateReaderView` 新增的建構參數一律可選**（規格審查 I-1）：既有測試有數十處直接建構它，而且不會傳這些參數。
  - `Set<AppFont> installedFonts`，預設 `const {}`：傳給 `buildFontFaceCss()`。
  - `String? downloadedFontsDirectory`，預設 `null`：**只有在不為 `null` 時**，才在 `WebViewAssetLoader.pathHandlers` 註冊 `/downloaded-fonts/` 的 `InternalStoragePathHandler`。
- **`ReaderScreen` 必須等已下載字型載入完成才建構閱讀器**（規格審查 C-1）：
  - 背景：`FoliateReaderView` 的初始網址（`_initialIndexUri`，內含 `buildFontFaceCss()` 產生的 `@font-face`）是 `late final`，閱讀器建構後就不會再重算。`ReaderScreen` 對自訂字型已有同樣的防護（`_customFontsLoaded` 加在 `_buildBody` 的 Foliate 建構條件中）。已下載字型如果沒有同樣的防護，在沒有自訂字型的情況下，閱讀器會在字型清單讀完之前就用空集合建構，**使用者下載了字型也永遠不會套用**。
  - 做法：新增可選建構參數 `DownloadableFontStore? downloadableFontStore`（比照 `customFontsRepository` 的慣例由上層傳入）；狀態 `_downloadedFontsLoaded` 的初始值為 `downloadableFontStore == null`；`_loadDownloadedFonts()` 完成（不論成功或失敗）後設為 `true` 並 `setState`；`_buildBody` 建構 Foliate 閱讀器的條件改為同時要求 `_customFontsLoaded` 與 `_downloadedFontsLoaded`。
  - 沒有傳入 store 時（例如既有測試），已下載字型集合為空、`_downloadedFontsLoaded` 一開始就是 `true`，不需等待，行為與現在相同。讀取失敗時也視為空集合，不阻擋開書。
- **閱讀設定下拉選單**（`ReaderSettingsSheet`）：新增可選參數「已下載的內建字型」（預設 `const {}`），只列出這些字型加上自訂字型。沒有任何已下載的內建字型時，在選單下方顯示一行提示「到『字型管理』下載更多字型」。偏好值不在選項中時顯示「使用書本字型」（`epic-48` 已實作，沿用）。
- 閱讀期間字型的下載狀態不會改變（字型管理畫面不在閱讀器內），所以只在開書時載入一次。

### 字型下載服務（`fonts-cdn/`，位於 repo 根目錄）

- 目錄內容：字型原檔（`fonts/`，從 git 歷史還原，blob 不變所以不增加 repo 大小）、字型清單（檔名、大小、SHA-256，和 App 的字型目錄一致）、Worker 程式與 `wrangler` 設定、上傳腳本、部署 wizard、線上驗證腳本。`app/assets/fonts/GuanKiapTsingKhai.ttf` 移到這裡。
- **Worker 的 HTTP 介面**：
  - `GET`／`HEAD /v1/<檔名>` → 回傳 R2 中 key 為 `v1/<檔名>` 的物件；`Content-Type: font/ttf`、`Content-Length`、`ETag`、`Cache-Control: public, max-age=31536000, immutable`
  - `GET` 以 `bucket.get(key)` 取得物件並串流 body；`HEAD` **必須**改用 `bucket.head(key)` 只讀中繼資料，回傳空 body 但帶齊與 `GET` 相同的標頭，避免為了一個 HEAD 請求開啟 57MB 的物件串流（設計審查 I-1）
  - 物件不存在 → `404`
  - 其他方法 → `405`；其他路徑（包含根目錄，也就是不提供列出檔案）→ `404`
  - 不支援 `Range`（App 不做續傳）
- **發布規則**：已發布的 key 永遠不覆蓋、不刪除。上傳腳本在目標 key 已存在時直接中止。字型改版一律發布到新的版本路徑（`v2/…`）。
- 需要人類操作的步驟（Cloudflare 帳號、綁付款方式、啟用 R2、`wrangler login`、部署、上傳）由 wizard 腳本引導；完成後以驗證腳本對 5 個檔案逐一下載並比對 SHA-256。
- 驗證身分使用 `wrangler login`（互動式瀏覽器 OAuth），不需要建立 API Token。若日後改在 CI 等非互動環境部署才需要 Token，最小權限為「Workers Scripts: Edit」與「Workers R2 Storage: Edit」（設計審查 M-2，本 Epic 不實作）。

### 在地化字串（新增）

字型狀態（未下載／下載中／已下載）、檔案大小格式、下載／取消／重試／刪除按鈕、刪除確認對話框、5 種錯誤原因的訊息、閱讀設定下拉選單的提示。三種語系都要提供（zh_TW 為範本）。

刪除確認對話框（規格審查 I-4）：
- 標題沿用既有的 `fontManagementDeleteConfirmTitle`（「確定要刪除「{fontName}」嗎？」），文意和參數對兩種字型都適用。
- 內文**新增**專屬字串 `fontManagementDownloadableDeleteConfirmMessage`，不帶參數，文意為「刪除後可以隨時重新下載。使用這款字型的書會暫時改用書本或系統字型，重新下載後自動恢復。」**不可**沿用自訂字型的 `fontManagementDeleteConfirmMessage`（必須帶 `{usageCount}` 複數參數，文意是「會改用預設字型」）。

## 測試決策（Testing Decisions）

- **好的測試只驗證外部行為**：透過模組的公開介面驅動，斷言使用者看得到的結果（畫面文字、按鈕狀態、檔案是否存在、拋出的原因代碼），不斷言內部呼叫順序或私有狀態。
- **切面 1：`DownloadableFontStore`（主要切面）**。以 `package:http/testing` 的 `MockClient`（串流回應）加暫存目錄驅動。案例：下載成功後 `installedFonts` 包含該字型、進度回呼單調遞增到 100%；雜湊不符 → `integrity` 且沒有留下任何檔案；取消 → `cancelled` 且沒有留下任何檔案；HTTP 404／500 → `http`；連線例外 → `network`；已下載時重新下載失敗不影響既有檔案；`delete` 後不再列為已下載；沒有 `Content-Length` 時進度改用目錄中的大小；進度回呼只在整數百分比改變時觸發（大量小區塊時呼叫次數不超過 101 次，且數值嚴格遞增）；`prepare()` 會建立不存在的存放目錄，並刪除殘留的 `.part` 檔但不動正式檔案；下載進行中再呼叫 `download()` 會拋出 `StateError`，且不影響進行中的那一筆。參考既有做法：`google_drive_storage_client_test`。
- **切面 2：`FontManagementScreen` widget 測試**。注入假的 store（可控制進度、成功、失敗），驗證四種狀態的顯示（每種狀態標題都是字型名稱）；下載中時其他列的「下載」「重試」「刪除」全部停用、AppBar「上傳」仍可按；取消；重試；刪除確認對話框使用可下載字型專屬的文案（不顯示使用中書籍數量）；離開畫面時取消下載；英文介面的名稱與大小格式。
- **`ReaderScreen` 建構時機測試**（規格審查 C-1 的回歸測試，使用既有 `reader_screen_test` 切面）：注入 `installedFonts()` 由 `Completer` 控制的假 store，完成前不建構 `FoliateReaderView`；完成後建構，且收到的已下載字型集合正確。另驗證沒有傳入 store 時開書行為與現在相同（不等待、已下載字型集合為空）。參考既有做法：`font_management_screen_test`、`test/support/fake_custom_fonts_repository.dart`。
- **切面 3：`ReaderSettingsSheet` widget 測試**。只列出已下載的內建字型；一款都沒有時顯示提示；偏好值指向未下載字型時顯示「使用書本字型」。參考既有做法：`reader_settings_sheet_test`。
- **切面 4：`buildFontFaceCss` 純函式測試**。只替已下載字型輸出規則、網址指向 `/downloaded-fonts/v1/…`、自訂字型規則不受影響。參考既有做法：`foliate_native_bridge_test`。
- **切面 5：Worker 的 Node 單元測試**。以假的 R2 binding 呼叫 Worker 的 `fetch`，驗證 200（含標頭）、404、405、不列出檔案；HEAD 只呼叫 `head()`、完全不呼叫 `get()`（假 binding 記錄呼叫）。純 Node 內建模組，免 npm install。參考既有做法：`app/tool/` 的 Node 腳本。
- **字型目錄一致性測試**：Dart 測試讀取 `fonts-cdn/` 的字型清單，斷言與 App 字型目錄的路徑、大小、SHA-256 完全一致，避免只改其中一邊。這個測試同時需要 Issue 1 的清單與 Issue 3 的字型目錄，所以放在兩者都完成後的 Issue 4（工單審查 I-1）。
- **不寫自動化測試的部分**：R2／Worker 的實際部署與上傳（人類操作，以驗證腳本確認）；WebView 實際套用下載字型的渲染結果（真機以 `chrome://inspect` 的 Rendered Fonts 驗證，列為 Issue 驗收步驟）。
- `WebViewAssetLoader` 的處理器設定屬於 `InAppWebView` 的平台設定，widget 測試無法觀察實際串流，改由真機驗證。

## 範圍外（Out of Scope）

- 恢復原俠正楷、台灣圓體、源流明體（仍為 `[字型停用]`；恢復時只要解除標記，本 Epic 的下載機制就會自動適用，字型檔也會先上傳好）。
- 背景下載、離開畫面後繼續下載、斷點續傳（`Range`）。
- 行動網路／Wi-Fi 的區分與警告。
- 遠端字型清單（manifest）、不發新版就新增字型。
- 字型改版後的舊版本檔案清理（改版時才需要處理）。
- 把 ugotit.cc 的 DNS 搬到 Cloudflare、`fonts.ugotit.cc` 自訂網域。
- 多字重（只提供單一 Regular 檔或可變字型檔）。
- PDF（不套用字型設定）。
- 書籍字型偏好的跨裝置同步（現有同步本來就不包含）。

## 補充說明（Further Notes）

- 思源兩款是可變字型（VF），字重滑桿本來就依賴可變字型的字重軸；下載後行為和先前打包時相同。
- 5 款字型都是 SIL OFL 授權，可以自行再散布；`fonts-cdn/` 應一併放上各字型的授權檔。
- R2 的免費額度（儲存 10GB、每月 1,000 萬次讀取、不收下載流量費）與 Worker 的免費額度（每天 10 萬次請求）遠高於預期用量；啟用 R2 必須綁定付款方式。
- 本 Epic 合併前，`epic-48` 的過渡狀態（選思源字型由系統字型補位）持續存在。
