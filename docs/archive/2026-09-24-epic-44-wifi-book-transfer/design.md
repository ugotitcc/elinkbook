# Epic 44 — WiFi 傳書：Discovery

## 背景

2026-09-17 使用者提出「新增 WiFi 傳書功能，可以上傳與下載書籍」需求，經 `/grill-with-docs`（`/grilling` ＋ `/domain-modeling`）5 輪問答完成 Discovery。

Discovery 前已核實下列事實，直接影響多個分岔的可行選項：

- 「來源」畫面（`sources_home_screen.dart`）目前聚合本機檔案/資料夾選擇、Google Drive、OneDrive、OPDS 遠端書庫（`epic-30`）四種**匯入**入口，共用同一個常駐下載佇列面板；文件註解明確寫「只聚合既有匯入入口」。
- `BookSource` enum 目前是 `{local, googleDrive, oneDrive, calibreOpds}`，每新增一個匯入管道就對應新增一個值是既有模式，但每個既有值都搭配專屬的「可重新連線/重新下載」能力（額外欄位如 `cloud_file_id`／`remote_server_id`+`remote_book_id`）。
- 專案目前**沒有**任何本機 HTTP Server／mDNS 探索相關套件依賴（`shelf`、`network_info_plus` 等皆未出現在 `pubspec.yaml`）——這是全新的技術面向，不是既有機制的延伸。
- `SourcesHomeScreen` 已有 `isMobileDataConnection` 既有 callback（`connectivity_plus` 套件，`main.dart._isMobileDataConnection()`），用於雲端下載走行動網路時示警；其判斷邏輯（`ConnectivityResult.mobile`/`wifi`）測的是「手機是否連到別人的網路」，手機自己開熱點分享時不會被判斷為「已連 WiFi」，需要額外邏輯涵蓋。
- 上傳匯入的既有慣例（`epic-29`/`epic-30` 皆遵循）是「不新增平行匯入路徑」，一律透過 `BookImportService.importFiles()` 走完整既有管線；該方法本身的重複偵測是「來源 URI 完全相同才跳過」的**靜默**機制，跟畫面層級（`CloudBrowserScreen`/`RemoteCatalogScreen`）自己另外用「書籍內容指紋」（`findByContentFingerprint()`）做的**互動式**「是否仍要新增」確認對話框是兩層不同機制。
- **關鍵發現**：TXT／MD 匯入時會落地合成一份真正合法的 EPUB3 壓縮檔，但依 `epic-11` 已查證事實 #1，這個衍生檔案的副檔名故意維持 `.txt`／`.md`（讓 `detectBookFormat()` 能正確分派給 `FoliateReaderView`），**內容其實是二進位 EPUB zip**；原始純文字內容匯入當下讀取一次後就不再保留。這件事在 App 內部完全無感，但一旦透過 WiFi 傳書把檔案原樣送出去，PC 端會收到一個叫 `書名.txt` 但用記事本打開全是亂碼的檔案。
- `Book.isDownloaded` 欄位存在（`epic-29`/`epic-30` 的「待下載」雲朵角標狀態，僅雲端紀錄、無本機實體檔案）。

## `/grilling` 決策紀錄

### 傳輸機制與生命週期

- 手機端啟動一個**前景限定**的本機 HTTP Server，隨「WiFi 傳書」畫面開啟/關閉（離開畫面即關閉，不是背景常駐服務）；對方（PC 或其他裝置）純粹用瀏覽器連線操作，**不需要安裝任何 App 或桌面端程式**。
- **網路先決條件**：手機必須真的處於 WiFi 連線狀態才能使用此功能，非 WiFi（含純行動網路）時直接停用並提示，而非讓使用者卡在連不上的畫面。此判定**涵蓋手機自己開熱點分享**這個常見情境（沒有共用路由器時的典型用法）。**（`/receiving-code-review` 審查修正，2026-09-17）** 現代 Android（8.0+）已把 `WifiManager.isWifiApEnabled()` 列為 `@hide` 內部 API，`TetheringManager` 相關查詢又需要一般 App 拿不到的系統權限 `TETHER_PRIVILEGED`——**不存在公開 API 可直接判定「目前是否開啟個人熱點」**，改採分層判定：優先用既有 `connectivity_plus` 判斷是否連到別人的 WiFi（直接取得 `wlan0` 局域網 IP）；否則列舉網路介面，用已知蜂巢式網路介面（`rmnet*`／`ccmni*`／`pdp*` 等）與 VPN 介面（`tun*`／`ppp*`）黑名單過濾，過濾後只剩電信/回環介面時判定「無可用局域網」並停用提示，找到非電信的局域網介面則視為熱點模式並顯示其 IP。因為各 Android 廠牌熱點虛擬網卡命名分歧、啟發式判斷無法保證 100% 準確，額外提供一個「我確定目前是用手機熱點」的手動確認按鈕，供偵測不明確時使用者自行覆寫繼續。
- **前景執行穩健度**：若使用者傳輸中途把 App 切到背景，接受傳輸可能因此中斷這個限制，用畫面上的文字提示告知「傳輸中請勿切換 App」，不投入 Android 前景服務（持久通知）等較重的機制去撐住背景執行。**（`/receiving-code-review` 審查修正，2026-09-17）** 螢幕鎖定另外處理：既有 `WAKE_LOCK` 權限已宣告，畫面開啟期間用 `FLAG_KEEP_SCREEN_ON`（或 `wakelock_plus`）保持螢幕常亮、離開畫面即解除，成本低廉、不是前景服務，疊加在文字提示之上；「App 被切到背景」仍維持接受限制不處理。
- **併發節流**：**（`/receiving-code-review` 審查修正，2026-09-17）** 本機 HTTP Server 限制同時活躍的上傳/下載串流數量（例如同時最多 2 個），避免低階 E-Ink 裝置（常見 2-3GB RAM）在多裝置或多檔案併發時被系統 Low Memory Killer 強制關閉；PC 端網頁多選下載採**依序**觸發（而非一次觸發全部下載連結），減輕瞬時 I/O 壓力。

### 功能形狀與入口

- **單一畫面／單一 session** 同時提供「上傳」（對方 → 手機）與「下載」（手機 → 對方）兩種能力，不是兩個各自獨立觸發的功能。
- 入口位於「來源」畫面。
- 連線資訊呈現：畫面同時顯示文字網址（IP:port）與 QR Code，供 PC（打字）或另一支手機（掃碼）取用。
- **PC 端網頁資產離線內嵌**：**（`/receiving-code-review` 審查修正，2026-09-17）** PC 端網頁（HTML/CSS/JS）須 100% 內嵌於 App 自身 assets，不依賴任何外部 CDN 資源——手機自己開熱點分享時通常沒有對外網際網路，外部 CDN 資源在這個情境下會直接讓網頁排版崩潰或卡在逾時。
- 同時允許多台裝置連線，不限制單一裝置佔用。
- 使用者若在傳輸進行中嘗試離開畫面，跳出確認對話框示警（比照 `epic-30` 站點刪除示警同樣的「零意外」精神）。

### 上傳（對方 → 手機）

- 依副檔名白名單檢查（EPUB/PDF/AZW3/CBZ/TXT/MD），不支援格式在上傳當下直接拒絕並提示，不會先收下來才在匯入階段才發現失敗。
- **上傳位元組落地路徑**：**（`/receiving-code-review` 審查修正，2026-09-17）** 必須是持久化的 App 私有文件目錄（例如 `getApplicationDocumentsDirectory()` 下的匯入書籍目錄，比照既有封面/CBZ 落地複本的既定作法），不可以是暫存/快取目錄（`getTemporaryDirectory()`）——查證 `BookImportServiceImpl._importSingleFile()` 對非 `content://` 的路徑是原樣引用寫入 `Book.filePath`、不會另外複製，若上傳端點自己把位元組寫在暫存目錄，暫存檔一旦被系統回收，書籍實體資料就永久遺失。
- 落地完成後走既有 `BookImportService.importFiles()` 完整管線（格式檢查、既有的來源 URI 靜默去重機制皆自然適用）。
- **重複匯入偵測**：額外借用「書籍內容指紋」機制，**在呼叫 `importFiles()` 之前**先對落地檔案算出內容指紋、查詢 `findByContentFingerprint()`。**（`/receiving-code-review` 審查修正，2026-09-17）** 查證 `importFiles()` 內部只有 `seenUris.add(uri)` 這種路徑字串去重、從未查詢指紋庫，若把上傳檔案直接丟給它，同一本書上傳十次會累積十筆重複記錄；命中時**刪除剛落地的檔案、不呼叫 `importFiles()`**，直接在上傳結果清單標示「已存在，已略過」；沒命中才把檔案路徑傳入 `importFiles()` 走正常登記流程。刻意不比照既有雲端匯入／遠端書庫「跳出對話框詢問是否仍要新增」的互動模式——那套模式的前提是操作者正看著手機螢幕（`CloudBrowserScreen`/`RemoteCatalogScreen` 皆是如此），但 WiFi 傳書的操作者在 PC 端，無法比照做即時互動確認。
- **書籍來源標記**：上傳成功的書籍**不新增**第 5 個 `BookSource` 值，直接歸類為 `local`——這個來源沒有「可重新連線/重新下載」的持久語意（對方裝置不是常駐伺服器），不像 `googleDrive`/`oneDrive`/`calibreOpds` 那樣搭配專屬能力，加一個沒有對應能力的值不符合既有三者的模式。

### 下載（手機 → 對方）

- PC 端瀏覽整個書架清單勾選，**僅列出 `isDownloaded == true`**（有本機實體檔案）的書；遠端書庫／雲端匯入「待下載」的雲朵角標書籍**不出現**在清單中——這個功能的定位是「搬移手機上已經有的書」，不負責代為觸發雲端/遠端下載（那是完全獨立、已有專屬 UI 的功能）。
- **`content://` 來源書籍的下載**：**（`/receiving-code-review` 審查修正，2026-09-17）** 依 ADR 0002，本機選檔匯入的書籍 `Book.filePath` 多半維持是 `content://` URI（刻意不複製），`dart:io` 的 `File` 無法直接開啟這類 URI；下載時重用既有 `ReaderResourceChannel.kt`（讀取/縮圖已在用的同一套材質化機制）把 `content://` 轉存成本機暫存檔，再串流給 PC，傳輸完成或客戶端斷線逾時後清理該暫存檔；大檔案（如 100MB+ PDF）下載前須檢查可用磁碟空間，避免同時下載多檔把手機私有空間塞爆。
- 多選下載時**逐檔各自**觸發瀏覽器下載，不在伺服器端打包成 zip——打包需要手機端額外暫存空間（可能上百 MB）與 PC 端額外解壓縮手續，換來的好處（少按幾次）不值得這個複雜度。
- **TXT／MD 來源的書籍**，下載時給的是合成後的 `.epub` 檔案（下載檔名改為 `.epub`，誠實反映實際內容——內容本來就是一份完整合法的 EPUB，章節/目錄皆為真實資料非估算），不是原始純文字；原始檔案內容匯入當下讀取一次後即不再保留，無法精確還原，嘗試「還原成純文字」是一個從匯入當下就已經放棄的目標，不在下載這一步假裝能做到。
- **中文檔名下載編碼**：**（`/receiving-code-review` 審查修正，2026-09-17）** 下載回應的 `Content-Disposition` 標頭須依 RFC 5987/6266 用 `filename*=UTF-8''<percent-encoded>` 搭配 ASCII 後備 `filename=`，本專案書庫書名常態為中文，避免主流瀏覽器解析非 ASCII 檔名產生亂碼。

### 存取控制

- 同一 WiFi 網路內任何人拿到網址即可直接操作，**不需要密碼或配對碼**（信任模型＝同一區網＝已授權，比照多看閱讀/掌閱等主流實作的預設做法）。這是可逆決定，之後若有公用 WiFi 情境的疑慮回報，可再加。

## 依賴事實（供 Architecting 階段參考，非本 Discovery 待決）

- 本機 HTTP Server 的套件選型（例如 `shelf`）留待 `spec.md` 定案。**監聽 port 策略已定案（`/receiving-code-review` 審查修正，2026-09-17）**：優先綁定慣用埠號（如 8080），遇 `SocketException`（埠號衝突）則退回系統動態分配（Port 0），兼顧使用者手動輸入網址的便利性與強韌性。
- 手機自己開熱點（AP 模式）時的偵測策略已定案（見上方「網路先決條件」：介面枚舉＋蜂巢式介面黑名單＋手動確認按鈕），`NetworkInterface.list()`（Dart）是否足夠或需要額外原生 platform channel 讀取介面資訊，具體查證留待 `spec.md`。
- PC 端網頁前端技術棧（預期純 HTML + 少量 JS，不需要引入前端框架，且須 100% 內嵌於 App assets、不依賴外部 CDN，見上方「PC 端網頁資產離線內嵌」）與上傳/下載進度顯示、上傳結果清單/下載清單的具體 UI 呈現，留待 `spec.md`。
- QR Code 產生套件選型留待 `spec.md`。
- TXT／MD 來源書籍下載時，`.epub` 副檔名替換的具體實作點（下載回應的 `Content-Disposition` 檔名 vs. 實際複製一份重新命名的暫存檔；中文檔名須依 RFC 5987/6266 編碼，見上方「中文檔名下載編碼」）留待 `spec.md`。
- 上傳/下載併發節流的具體上限數值（見上方「併發節流」，本 Discovery 只定案「需要節流」與方向，非本 Discovery 待決的是確切數字）留待 `spec.md` 依真機測試調校。

## 範圍界定

- **本 Epic 涵蓋**：本機 HTTP Server（前景限定生命週期）＋純瀏覽器操作的雙向傳書；「來源」畫面新增獨立入口；WiFi／熱點連線先決條件檢查與停用提示；連線資訊文字網址＋QR Code 呈現；多裝置同時連線；離開畫面時傳輸中示警；上傳格式白名單檢查、既有匯入管線接線、內容指紋重複匯入偵測（靜默略過）；下載清單僅列出 `isDownloaded == true` 的書籍、逐檔下載、TXT/MD 來源書籍下載為 `.epub`。
- **本 Epic 不涵蓋**（留待後續視需求評估，不在本波規劃）：斷點續傳；下載打包成 zip；PC 網頁與手機 App 之間的即時互動式重複匯入確認；WiFi 傳書專屬的 `BookSource` 標記或傳輸歷史紀錄；透過 WiFi 傳書畫面代為觸發雲端/遠端書庫的「待下載」書籍下載；Android 背景/鎖屏時的傳輸續跑保障（前景服務）；密碼/配對碼存取控制。

## `CONTEXT.md` 異動

- 新增「WiFi 傳書（WiFi Book Transfer）」詞條：定義本 Epic 的產品概念與範圍邊界。
- 更新「書籍來源（Book Source）」詞條：補上本次決議「不新增第 5 個值，WiFi 傳書上傳的書歸類為 `local`」。

## `review-epic-and-design.md` 審查後續（2026-09-17，`/receiving-code-review`）

審查結論 Changes Requested（2 Critical／4 Important／3 Minor）。逐項查證後：

- **C-1（`content://` 下載盲區）／C-2（熱點偵測平台限制）**：查證屬實，皆為 Discovery 階段遺漏的技術缺口（非後續才需要考慮的細節），已分別補進「下載」與「網路先決條件」小節——C-1 決定重用既有 `ReaderResourceChannel.kt`；C-2 改為「介面枚舉＋蜂巢式介面黑名單＋手動確認按鈕」的分層判定，且明確記錄現代 Android 不存在公開熱點狀態 API 這個平台事實。
- **I-1（上傳暫存檔死結）／I-2（指紋去重時機）**：查證屬實（`BookImportServiceImpl` 對非 `content://` 路徑原樣引用、`importFiles()` 內部只有路徑字串去重），已分別補進「上傳位元組落地路徑」與「重複匯入偵測」小節，明確定案落地目錄與呼叫順序。
- **I-3（併發節流）／I-4（離線資產＋中文檔名編碼）**：合理的工程風險與正確性要求，已補進「併發節流」「PC 端網頁資產離線內嵌」「中文檔名下載編碼」小節。
- **M-1（`CONTEXT.md` 詞條未寫入）**：**查證為誤判**，`CONTEXT.md` 當時已經寫入「WiFi 傳書」與「書籍來源」兩處異動，審查者可能查看的是異動落地前的版本。不需要任何修正。
- **M-2（Wakelock）／M-3（Port 策略）**：採納，已分別補進「前景執行穩健度」與「依賴事實」小節。

本輪修訂未變動任何既有的 `/grilling` 產品決策形狀（單一畫面雙向傳書、同區網信任模型、下載排除待下載書籍等皆維持原樣），全部是技術可行性層面的補強。
