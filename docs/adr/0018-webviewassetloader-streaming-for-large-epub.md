# ADR 0018：EPUB 本體改由原生 `WebViewAssetLoader`（`InternalStoragePathHandler`）串流服務，取代 Dart-side `shouldInterceptRequest` 全檔載入

## 狀態

已採納

## 背景

`epic-20-fxl-foliate-migration` Issue 8：開啟約 200MB+ 的大型 EPUB（真實樣本 `tmp/膽大黨10.epub`，217MB）時，App 於原生端拋出 `OutOfMemoryError` 閃退，真機 logcat 崩潰堆疊：

```
java.lang.OutOfMemoryError: Failed to allocate a 219210408 byte allocation ...
	at java.io.ByteArrayOutputStream.toByteArray(ByteArrayOutputStream.java:211)
	at kotlin.io.ByteStreamsKt.readBytes(IOStreams.kt:152)
	at cc.ugotit.elinkbook.ReaderResourceChannel.onMethodCall(ReaderResourceChannel.kt:58)
```

根因（`docs/epics/epic-20-fxl-foliate-migration/reviews/bugfix-repro.md` 完整記錄）：`FoliateEpubReaderView` 開書時，`InAppWebView.shouldInterceptRequest`（Dart 端 callback，`foliate_epub_reader_view.dart:409-419`）攔截 `/book/current.epub` 請求，透過 `loadBookBytes()`（`foliate_native_bridge.dart:113-125`）把整份檔案內容一次性讀進單一 `Uint8List`／`ByteArray`（`content://` 來源經 `ReaderResourceChannel.kt` 的 `ContentResolver.openInputStream().readBytes()`；本機檔案來源經 Dart `File.readAsBytes()`），再包成 `WebResourceResponse(data: bytes)` 回傳。這條路徑對任何大小的 EPUB 皆一次性佔用「檔案大小」量級的記憶體，200MB+ 檔案逼近/超過 App heap 上限（`growth limit` 約 256MB）即崩潰。

已直接查證 `flutter_inappwebview`（`^6.1.5`，本專案既有依賴）Dart 端 `WebResourceResponse.data` 型別鎖死 `Uint8List?`，透過 Dart callback 這條路徑（含套件自帶的 `CustomPathHandler`）天生無法串流，問題不在 Kotlin 端讀取方式，瓶頸在跨 Dart↔Native platform channel 前 Dart 端必須先持有完整位元組陣列。

同時查證 `flutter_inappwebview` 原生端（Android）已內建 `androidx.webkit.WebViewAssetLoader` 整合（`InAppWebViewClient.java:631-644`，優先於 Dart callback 被檢查），其 `InternalStoragePathHandler`（Dart 端 `InAppWebViewSettings.webViewAssetLoader` 暴露，原生端對映 `androidx.webkit.WebViewAssetLoader.InternalStoragePathHandler(context, dir)`，見 `WebViewAssetLoaderExt.java:64-73`）完全在原生端以 `FileInputStream` 串流運作，不經過 Dart callback，天生不受 `Uint8List` 全檔材化限制，且不需要 fork/patch 套件本身。

本專案 `epic-17` 時期（commit `4bc492a`）其實用過原生 `WebViewAssetLoader`（當時 `FoliateEpubReaderView.kt` 仍是原生 `PlatformView`），後來因 ADR 0013（觸控/選字手勢限制，`AndroidView`+`android.webkit.WebView` 的觸控轉發機制無法還原長按選字→拖曳選取控點，與記憶體/串流完全無關）改用 `flutter_inappwebview` 的 `InAppWebView`；ADR 0013 本文甚至明文記載「`WebViewAssetLoader` 雙路徑掛載...大部分被 `flutter_inappwebview` 的對應 API 取代，可大幅簡化或移除」——本次決策等同「撿回」當初已知存在、但簡化實作時未採用的原生資產載入路徑，不是走回頭路撞到 ADR 0013 要解決的問題（手勢處理仍由 `flutter_inappwebview` 的 `InAppWebView` 負責，本次只換「書本本體」這一條資源載入路徑）。

人類另提供兩份外部分析報告（Anx Reader／`readest-foliate-js` 大檔處理機制）作為參考，逐項查證：報告聲稱 `zip.js` 具備 `HttpRangeReader` 支援 HTTP Range 隨需讀取——**經查證不成立**（本專案 vendored 的 `vendor/zip.js` 全檔搜尋無 `HttpRangeReader`、無任何 `Range` 字樣），與 `epic-18` Issue 21 先前已發現的「外部報告編造不存在 API」是同一種失準模式；報告聲稱 `epub.js` `Loader` 引用計數卸載機制／`fixed-layout.js` `maxLoaded`/`maxConcurrent` 頁面調度機制則查證屬實，但兩者管的是「書已開啟後逐頁閱讀期間」的記憶體，不影響「開書當下」的本次問題。獨立重新查證 `view.js` `fetchFile()`：`fetch(url)` + `await res.blob()` 為單次完整緩衝，不發 HTTP Range 請求，與既有查證結論一致。

## 決策

- **`/book/current.epub` 這一條資源請求，改由原生 `androidx.webkit.WebViewAssetLoader`（`InternalStoragePathHandler`）服務，取代現行 Dart 端 `InAppWebView.shouldInterceptRequest` 的全檔載入路徑。** 這是本 ADR 唯一的範圍——`/assets/foliate/*`（`foliate-js` 靜態資源）與 `/assets/fonts/*`（字型檔）兩條既有路徑不受影響，繼續透過既有 Dart callback 服務（皆為小檔案，非本次問題成因；原生 `WebViewAssetLoader` 對不符合已註冊 path handler 前綴的請求回傳 `null`，會自動落回 Dart callback，兩條路徑天然並存不衝突）。
- **開書前，原生端以有界記憶體的分塊串流複製**（Kotlin `InputStream.copyTo(OutputStream, bufferSize)`，逐段讀寫、任何時刻只佔用一個緩衝區大小的記憶體）**，把待開啟的 EPUB（不論來源是 `content://` URI 或本機檔案路徑）落地成 App 私有快取目錄下的固定檔名**（`<filesDir>/foliate_book_cache/<實例唯一 ID>/current.epub`，取代現行 `readContentUri`/本機 `File.readAsBytes()` 的一次性全讀。`InternalStoragePathHandler` 指向此快取子目錄，服務 `/book/` 前綴請求。**計劃審查（`tmp/epic-20/plan_issue_8_review_report.md`）發現：`ReaderScreen` 每次開書皆是 `Navigator.push` 新路由，Flutter 轉場動畫期間舊路由與新路由的 `FoliateEpubReaderView` 可能短暫並存，若共用全域固定檔名會有兩個原生複製操作同時寫入同一路徑的競態風險（安靜地顯示錯誤/損毀內容，非閃退）——因此改為每個 widget 實例各自獨立的快取子目錄，而非最初設想的單一全域固定槽位；`/book/` 這個 URL 前綴本身仍是固定的（`main.js` 硬編碼，不可變），但每個 `InAppWebView` 實例各自的 `webViewAssetLoader` 設定指向各自專屬的目錄，互不共用可變狀態。**
- **開書前的原生複製操作透過 `BinaryMessenger.makeBackgroundTaskQueue()`（Flutter engine 2.8+ API）在背景執行緒池執行，不使用預設的 Android 主執行緒。** **計劃審查發現**：`MethodChannel.setMethodCallHandler` 的 callback 預設在主執行緒執行，217MB 檔案複製即使有界記憶體、不會 OOM，仍可能耗時數秒，若阻塞主執行緒有觸發 ANR watchdog 的風險（本專案明確以 E-Ink／較舊裝置為目標族群，見 `docs/prd.md` NFR-6，儲存 I/O 可能更慢）——這不是本決策新引入的退化（現行會崩潰的 `readContentUri` 本身也在主執行緒同步執行），但既然本次重寫這段程式碼，一併改用背景 `TaskQueue` 是低成本、可直接排除此風險的選擇，一併採納。
- **`content://` 與本機檔案路徑兩種來源統一走同一套複製機制**，不特殊處理——本機檔案路徑雖然理論上可透過符號連結或直接指向來源目錄避免複製，但 `InternalStoragePathHandler` 對路徑穿越有既定的原生端安全檢查（僅接受落在註冊目錄範圍內的檔案），符號連結若指向範圍外可能被拒絕、行為不確定；統一複製雖然對本機檔案來源多一次檔案系統複製成本，但换取行為一致、可預期、不需要為兩種來源寫兩套邏輯，符合簡單優先原則。
- **快取檔案為單一固定槽位**（`current.epub`），與現行架構「`/book/current.epub` 固定 URL、一次只服務一本正在閱讀的書」的既有語意完全一致，不是新限制。開啟新書時覆蓋既有快取檔（若存在），`FoliateEpubReaderView` dispose 時視情況清理（避免累積佔用磁碟空間，但非本次崩潰問題的必要修復範圍，可視實作階段判斷）。
- **`readest/foliate-js` 釘定版本本身不修改**——`InternalStoragePathHandler` 只改變原生端「怎麼組出 `WebResourceResponse`」（從先讀滿 `ByteArray` 改成直接包一個 `FileInputStream`），WebView／JS 端收到的仍是單一完整 HTTP 回應（非 `206 Partial Content`），`main.js`／`view.js` 的 `fetch()` 呼叫行為不需要也不會改變，不涉及 HTTP Range 支援，比照 ADR 0011／ADR 0017 一貫的「不修改釘定版本」限制。
- **`ReaderResourceChannel.kt` 的 `readContentUri` 方法與 `foliate_native_bridge.dart` 的 `loadBookBytes()` 函式因本決策成為死碼，隨實作一併移除**（`readAndroidAsset` 服務的是 `/assets/foliate/*`，不受影響，保留）。
- **殘餘風險，非本 ADR 阻塞項但需在實作驗收階段確認**：即使原生端改為串流，WebView 仍會對整份回應呼叫 `res.blob()`（`fetchFile()` 內），在 WebView 渲染器行程（獨立於 App 主行程）緩衝整份回應內容。Chromium 對大型 `Blob` 通常有磁碟/共享記憶體支援的儲存策略，但這是瀏覽器引擎內部行為，本次查證範圍內無法從原始碼層級確認 217MB 檔案在這一步驟是否會觸發渲染器行程自身的 OOM（原始崩潰發生在更早的 App 主行程階段，從未真正走到這一步，沒有既有證據）。**計劃審查已查證本專案目前完全沒有任何 `onRenderProcessGone` 覆寫（全專案 `grep` 零匹配）——代表若渲染器行程真的因此 OOM，Android WebView 的預設行為會直接讓整個 App 進程被系統終止，是明顯可辨識的整個 App 崩潰，不會是安靜卡住或被 JS/Dart 端 `onError` 攔截到的情況**，實作階段真機測試時可依此判讀當下觀察到的現象是否對應此風險。實作階段務必以 `tmp/膽大黨10.epub` 在真機測試「整個開書流程」（含 WebView 端），不能只確認 `ReaderResourceChannel.kt` 這一個點不再拋錯；若渲染器行程階段仍崩潰，需另外評估（可能牽涉 `fetchFile()` 以外的路徑，屆時可能違反「不修改釘定版本」限制，需重新提交決策）。

## 後果

- `ReaderResourceChannel.kt` 新增（或擴充）分塊複製邏輯，`readContentUri`／舊有本機 `File.readAsBytes()` 呼叫點移除；`FoliateEpubReaderView.dart` 的 `_shouldInterceptRequest` 移除 `/book/current.epub` 分支；`initialSettings` 新增 `webViewAssetLoader` 設定。
- 開書流程新增一個「落地複製」前置步驟（不論書籍大小皆會發生，包含現行架構下原本不需要複製的本機檔案來源）——小型書籍（數 MB 等級）複製耗時可忽略（< 100ms 量級），大型書籍（200MB+）複製耗時取決於裝置儲存速度，可能有感知延遲，但相較於現行「無聲閃退」是可接受的取捨；若後續真機驗證發現延遲問題明顯，可在載入指示器文案上做區分（例如「正在準備書籍」），不影響本 ADR 決策本身。
- 快取目錄（`foliate_book_cache/<實例 ID>/`）成為新的磁碟空間佔用來源，且改為每實例獨立子目錄後不再有「開新書自動覆蓋」這種天然清理時機——需要 `FoliateEpubReaderView` dispose 時主動清理本實例子目錄，並在 `MainActivity.onCreate()` 新增保底清理（App 冷啟動時整個清空 `foliate_book_cache/`，處理異常結束遺留的孤兒子目錄），實作階段一併規劃。
- `content://` 授權書籍每次開啟都會觸發一次落地複製（即使之前已開過同一本書），與 `BookImportService`（ADR 0002）匯入時的落地複製是兩個獨立機制，互不取代——匯入時落地是「長期私有複本」，本次是「開書當下的暫時性快取」，職責不同，暫不合併以維持既有匯入邏輯的穩定性（後續若有需要可再評估整合，非本次範圍）。

## 曾考慮的替代方案

- **繼續用 Dart-side `shouldInterceptRequest`，只改善 Kotlin 端讀取方式（例如分批讀取、疊代式組裝）**：已排除——瓶頸不在 Kotlin 端怎麼讀，而是 Dart 端 `WebResourceResponse.data` 型別鎖死 `Uint8List?`，跨 platform channel 前終究要材化一份完整位元組陣列，任何 Kotlin 端優化都無法迴避這個 Dart 端限制。
- **設定保守的檔案大小警戒值，超過時提示使用者「檔案過大可能無法開啟」**：治標不治本，僅止住無聲閃退，未解決根本問題；本 ADR 決策的方向可徹底解決，優先採用；若實作工期考量需要短期防護，可作為過渡方案疊加，不互斥。
- **提高 App 的 `largeHeap` manifest 設定暫時緩解**：非長期解法，部分裝置仍可能不足，且無助於改善開書速度／整體記憶體使用效率，已排除為主要方向。
- **要求 `readest/foliate-js` 釘定版本支援 HTTP Range 請求（走真正的分塊/隨需讀取）**：查證確認本專案 vendored 的 `zip.js` 不具備此能力（外部分析報告聲稱的 `HttpRangeReader` 經查證不存在），且違反「不修改釘定版本」的既有限制，已排除。
