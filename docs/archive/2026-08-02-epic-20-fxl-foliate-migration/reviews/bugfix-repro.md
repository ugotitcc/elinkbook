# Issue 8：大型 EPUB OOM 閃退——修復方向可行性研究（`/diagnose`）

**日期：** 2026-07-31
**性質：** 根因已於 Issue 8 建立時確認（真機 logcat + 原始碼交叉查證，見 `issues.md` Issue 8 段落），本次 `/diagnose` 聚焦**候選修復方向 (1)（串流/分塊讀取）的技術可行性**，決定是否可行、以及若可行該怎麼做。

---

## 已知起點（不重複驗證，直接引用 Issue 8 既有結論）

```
java.lang.OutOfMemoryError: Failed to allocate a 219210408 byte allocation ...
	at java.io.ByteArrayOutputStream.toByteArray(ByteArrayOutputStream.java:211)
	at kotlin.io.ByteStreamsKt.readBytes(IOStreams.kt:152)
	at cc.ugotit.elinkbook.ReaderResourceChannel.onMethodCall(ReaderResourceChannel.kt:58)
```

`FoliateEpubReaderView` 開書時，`loadBookBytes()`（`app/lib/reader/foliate_native_bridge.dart:113-125`）依 `filePath` 是否含 `"://"` 分派：

- `content://` URI → `ReaderResourceChannel.kt:onMethodCall('readContentUri', ...)`（`:56-65`）：`context.contentResolver.openInputStream(uri).use { it.readBytes() }`，整份讀進單一 `ByteArray`——這是崩潰堆疊指向的確切位置。
- 本機檔案路徑（已查證：Dart 端 `isPathWithinRoot` 強制要求落在 `getApplicationDocumentsDirectory()` 的父目錄範圍內，即 App 私有資料目錄，見 `foliate_native_bridge.dart:107-111,121-123`）→ `File.readAsBytes()`（`:124`），同樣整份讀進單一 `Uint8List`。

兩者的位元組資料最終都經 `InAppWebView.shouldInterceptRequest`（Dart 端 `foliate_epub_reader_view.dart:409-434`）包成 `WebResourceResponse(data: bytes)` 回傳給 WebView。

## 本次要回答的具體問題

**候選方向 (1)「改為串流/分塊讀取」，issues.md 原文已列出兩個技術疑慮：**
1. `flutter_inappwebview`／Android `WebResourceResponse` API 是否支援直接接 `InputStream` 而非先讀完整個 `ByteArray`？
2. 是否會波及 `readest/foliate-js` 釘定版本「一次性 `fetch()`、不發 HTTP Range 請求」的既有假設（該專案「不修改釘定版本」，若真的需要 Range 支援，方向 (1) 可能整個不可行）？

## 調查方法：直接查證套件原始碼（非重造 harness）

`flutter_inappwebview` 是本專案已引入的正式依賴，其 Dart／原生端原始碼皆可直接在本機 pub cache 取得（`pubspec.yaml:55` 宣告 `^6.1.5`），比起另外搭 throwaway harness，直接逐層讀原始碼是取得「這個 API 到底支不支援 X」這類是非題答案最快、最可靠的方式（等同 diagnose skill「除錯器/直接檢視」優先於「印 log」的精神，這裡是「直接讀權威原始碼」優先於「憑印象猜測」）。

### 發現 1：Dart 端 `WebResourceResponse.data` 被鎖死為 `Uint8List?`，不支援串流

`flutter_inappwebview_platform_interface-1.3.0+1/lib/src/types/web_resource_response.dart:17`：

```dart
class WebResourceResponse_ {
  ...
  Uint8List? data;
  ...
}
```

**結論：** 只要是透過 Dart 端 `InAppWebView.shouldInterceptRequest` 回呼（本專案目前的既有作法）處理，回傳值就一定要先在 Dart 端把整份內容組成 `Uint8List`，天生無法串流——這條路徑本身無法解決 OOM，不管 Kotlin 端怎麼讀都一樣，因為瓶頸在「跨 Dart↔Native platform channel 前，Dart 端必須先持有完整位元組陣列」這件事本身。

### 發現 2：`flutter_inappwebview` 原生端（Android）已內建 `WebViewAssetLoader` 整合，且優先於 Dart callback 被檢查

`flutter_inappwebview_android-1.1.3/android/.../InAppWebViewClient.java:631-644`：

```java
public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequestExt request) {
  final InAppWebView webView = (InAppWebView) view;
  if (webView.webViewAssetLoaderExt != null && webView.webViewAssetLoaderExt.loader != null) {
    try {
      final Uri uri = Uri.parse(request.getUrl());
      WebResourceResponse webResourceResponse = webView.webViewAssetLoaderExt.loader.shouldInterceptRequest(uri);
      if (webResourceResponse != null) { return webResourceResponse; }
    } catch (Exception e) { ... }
  }
  if (webView.customSettings.useShouldInterceptRequest) {
    // ...走到這裡才是本專案目前使用的 Dart callback 路徑，強制 Uint8List
  }
```

也就是說，`flutter_inappwebview` 本身有一個**優先於 Dart callback 被檢查**的原生 `WebViewAssetLoader` 掛載點（`webView.webViewAssetLoaderExt`），Dart 端對應暴露為 `WebViewAssetLoader`／`PlatformPathHandler`（`flutter_inappwebview_platform_interface-1.3.0+1/lib/src/platform_webview_asset_loader.dart`），內建 4 種 Handler：`AssetsPathHandler`／`ResourcesPathHandler`／`InternalStoragePathHandler`／`CustomPathHandler`。

逐一檢視：
- `AssetsPathHandler`／`ResourcesPathHandler`：只服務打包進 APK 的靜態資源，不適用（EPUB 是使用者匯入的動態內容）。
- `CustomPathHandler`：`handle(String path) -> Future<WebResourceResponse?>`（`platform_webview_asset_loader.dart:106`）——**這個事件仍然是 Dart callback**，回傳值仍是 `WebResourceResponse`（`data: Uint8List?`），跟現行架構一樣卡在發現 1 的瓶頸，**不解決問題**。
- **`InternalStoragePathHandler`**（`platform_webview_asset_loader.dart:286-345`）：「Handler class to open files from application internal storage」——這是**唯一一個完全在原生端運作、不經過 Dart callback**的 Handler（對應 AndroidX 官方 `androidx.webkit.WebViewAssetLoader.InternalStoragePathHandler`，其原生實作以 `FileInputStream` 逐段串流讀取，從不把整個檔案內容materialize 進單一陣列）。**這個 Handler 直接解決 OOM，且不需要 fork/patch `flutter_inappwebview`。**

### 發現 3：本專案曾經用過原生 `WebViewAssetLoader`，後來因「與本次記憶體問題完全無關的理由」被換掉

```
git log --all --grep="WebViewAssetLoader"
4bc492a feat(epic-17): 新增 FoliateEpubReaderView 原生 PlatformView（WebViewAssetLoader + 自訂 PathHandler + FoliateBridge）
```

ADR 0013（`docs/adr/0013-flutter-inappwebview-for-foliate-selection.md:32`）證實：epic-17 時期的 `FoliateEpubReaderView.kt`（當時是原生 `PlatformView`）確實用過 `WebViewAssetLoader` 雙路徑掛載；後來整個原生 `PlatformView` 被拔掉、改用 `flutter_inappwebview` 的 `InAppWebView`，**理由是標準 `AndroidView`+`android.webkit.WebView` 的觸控轉發機制無法完整還原「長按選字→拖曳選取控點」手勢**（ADR 0013 本文），與記憶體/串流毫無關係；該 ADR 甚至明文寫「`WebViewAssetLoader` 雙路徑掛載...大部分被 `flutter_inappwebview` 的對應 API 取代，可大幅簡化或移除」——當時的作者已經知道 `flutter_inappwebview` 有對應的原生資產載入 API，只是簡化實作時選了更簡單的 Dart callback 版本（`ReaderResourceChannel` + `shouldInterceptRequest`），而不是當時就已知存在的原生 `InternalStoragePathHandler` 路徑。

**結論：** 改回原生 `WebViewAssetLoader`（這次用 `flutter_inappwebview` 自己暴露的版本，而非重新引入獨立 `PlatformView`）不是走回頭路撞到 ADR 0013 要解決的問題——手勢處理仍然是 `flutter_inappwebview` 的 `InAppWebView` 在管，只是資源載入這一小塊換回原生路徑，兩者不衝突。

### 發現 4：本機檔案路徑已經 100% 符合 `InternalStoragePathHandler` 的前提條件

`InternalStoragePathHandler` 只能服務 App 私有資料目錄下的檔案。查證 `foliate_native_bridge.dart:107-111,121-123` 的既有邏輯：本機檔案路徑分支**已經強制要求**（`isPathWithinRoot` 檢查）落在 `getApplicationDocumentsDirectory()` 的父目錄範圍內——這正是 App 私有資料目錄。也就是說，「本機檔案路徑」這個分支**不需要任何額外落地/複製步驟**，直接改用 `InternalStoragePathHandler` 指向該私有根目錄即可。

`content://` 分支（真正觸發 Issue 8 崩潰的那個分支）則不在 App 私有目錄下（SAF 授權的外部 URI），無法直接被 `InternalStoragePathHandler` 服務。但本專案的 `BookImportService`（`ADR 0002`）**本來就有「匯入時視權限/副檔名落地成 App 私有複本」的既有機制**——把「開書當下」的 `content://` 讀取，改成「開書前先以有界記憶體的分塊複製（`InputStream.copyTo(OutputStream, bufferSize)`，Kotlin 標準函式，逐段讀寫、任何時刻只佔用一個緩衝區大小的記憶體，不是問題 1 的 `readBytes()` 一次性全讀）落地成私有快取檔」，落地後統一走 `InternalStoragePathHandler`——不是全新概念，是既有落地機制的自然延伸。

## 對 issues.md 兩個技術疑慮的具體回答

1. **「`flutter_inappwebview`／Android `WebResourceResponse` API 是否支援直接接 `InputStream`？」** —— **支援，但只有透過 `WebViewAssetLoader.InternalStoragePathHandler` 這條原生路徑才行**；透過現行的 Dart `shouldInterceptRequest` callback（含 `CustomPathHandler`）一律不支援，Dart 端 `WebResourceResponse.data` 型別鎖死 `Uint8List?`，無法迴避。
2. **「是否會波及 `readest/foliate-js` 釘定版本『一次性 fetch』的既有假設？」** —— **不會**。`InternalStoragePathHandler` 只是改變 Android 原生端「怎麼組出 `WebResourceResponse`」（從先讀滿 `ByteArray` 改成直接包一個 `FileInputStream`），WebView 收到的仍然是單一個完整 HTTP 回應（`Content-Length` 正確，非 `206 Partial Content`），JS 端 `fetch()` 的行為完全不變，不需要 HTTP Range 支援，不牽涉 `readest/foliate-js` 本身的任何程式碼，符合「不修改釘定版本」的既有限制。

## 建議修復方向（供後續 Planning 階段參考，本次 `/diagnose` 不直接動手實作）

**方向 (1)「串流/分塊讀取」技術上完全可行，且是三個候選方向中唯一能徹底解決問題（而非治標）的選項，建議採用：**

1. 改用 `flutter_inappwebview` 的 `WebViewAssetLoader` + `InternalStoragePathHandler`（Dart 端 `InAppWebViewSettings`／`initialSettings` 設定新增資產載入器設定，指向 App 私有資料根目錄），取代現行 `InAppWebView.shouldInterceptRequest` + `foliate_native_bridge.dart` 的 `loadBookBytes()` Dart-side 位元組轉發機制（原機制若其他用途仍需要——例如讀取 `foliate-js` 靜態資源——可視情況保留，本次只需替換「書本本體」這一條路徑）。
2. `content://` 來源：開書前以 Kotlin `InputStream.copyTo(OutputStream, bufferSize)` 有界記憶體分塊複製到 App 私有快取目錄（新檔案或沿用既有 `BookImportService` 落地機制擴充），複製完成後統一以本機檔案路徑（已在私有目錄範圍內）交給 `InternalStoragePathHandler` 服務。
3. 本機檔案路徑來源：不需複製，直接受益（已在私有目錄範圍內）。
4. 需要新增/確認的驗收判準：`tmp/膽大黨10.epub`（217MB，Issue 8 原始崩潰樣本）真機開啟不再 OOM；一般大小 EPUB 開書行為（速度、成功率）無退化；`content://` 匯入來源的一次性複製不應造成使用者可感知的長時間卡頓（若檔案極大，複製本身也需要時間，可能需要載入指示器文案調整，屬於實作階段細節）。
5. 此為對現行資源載入架構的中等規模異動（新增/取代一個 Kotlin 端元件、調整 `FoliateEpubReaderView` 建構參數或初始化流程），建議走正常 SDD 流程（Architecting 階段視情況新增 ADR 記錄「resource loading 從 Dart-side callback 改回原生 WebViewAssetLoader」的決策與理由、Scrum Master 拆解工單），不建議在本次 `/diagnose` 直接動手實作。

**方向 (2)（檔案大小警戒值）／方向 (3)（`largeHeap`）** 仍可視情況作為方向 (1) 完整實作前的短期防護（例如方向 (1) 工期較長時，先擋住最糟情況的無聲閃退），但不是長期解法，不建議取代方向 (1)。

## 相關佐證

- `docs/epics/epic-20-fxl-foliate-migration/issues.md` Issue 8 段落（原始崩潰證據、根因）
- `app/lib/reader/foliate_native_bridge.dart:98-125`（`loadBookBytes()` 現行分派邏輯）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`（崩潰堆疊指向的實作）
- `app/lib/reader/foliate_epub_reader_view.dart:409-434`（`_shouldInterceptRequest` 現行 Dart callback）
- `docs/adr/0013-flutter-inappwebview-for-foliate-selection.md`（原生 `PlatformView`／`WebViewAssetLoader` 退場的真正理由——觸控手勢，與本次發現不衝突）
- `docs/adr/0002-content-uri-reader-contract.md`（`content://` 落地複本既有機制）
- 套件原始碼（本機 pub cache）：
  - `flutter_inappwebview_platform_interface-1.3.0+1/lib/src/types/web_resource_response.dart`
  - `flutter_inappwebview_platform_interface-1.3.0+1/lib/src/platform_webview_asset_loader.dart`
  - `flutter_inappwebview_android-1.1.3/android/src/main/java/.../webview/in_app_webview/InAppWebViewClient.java:631-676`

---

## 追加查證（2026-07-31）：人類提供兩份外部分析報告（Anx Reader／`readest/foliate-js` 大檔處理機制）的逐項核實

人類提供 `tmp/epic-20/anx_reader_large_file_analysis_report.md`／`foliate_large_file_analysis_report.md` 兩份外部分析報告作為 Issue 8 實作參考。比照本 Epic 已有先例（`epic-18` Issue 21：外部分析報告的具體 API「經查證不存在（`Page.CENTER` 等編造）」），對兩份報告的每一項具體技術宣稱**直接對照本專案實際 vendored 的原始碼**逐一核實，不預設報告內容為真：

### 核實結果

| 報告宣稱 | 核實方式 | 結論 |
|---|---|---|
| `zip.js` 具備 `HttpRangeReader`，可對本地 HTTP Server 發 Range 請求隨需讀取（Anx Reader 報告核心論點） | `grep -o "[A-Za-z]*Reader" vendor/zip.js`，並額外搜尋 `Range`／`HttpReader` 等變體字樣 | ❌ **不成立**。本專案 vendored 的 `vendor/zip.js` 只有 `BlobReader`／`FileReader`／`ZipReader`，全檔案搜尋 `Range` 字樣**零匹配**。與 `epic-18` Issue 21 發現的「外部報告編造不存在 API」是同一種失準模式，本次是第二次在同一個 Epic 遇到。 |
| `epub.js` 的 `Loader` 類別有 `refCount`／`unref`／`URL.revokeObjectURL()` 的引用計數卸載機制 | `grep`／直接讀取 `epub.js` 原始碼 `unref()` 函式本體，逐行比對報告附的程式碼片段 | ✅ **成立**，與本專案實際原始碼幾乎逐字相符。 |
| `fixed-layout.js` 有 `planScrollModePages`／`maxLoaded`／`maxConcurrent`（`scrollMaxLoaded`／`scrollMaxConcurrent`）的頁面調度/淘汰機制 | `grep -o` 逐一確認識別字存在 | ✅ **成立**，識別字與函式名稱皆存在。 |
| 結論「記憶體峰值控制...絕不引發 Android 系統 OOM Kill」（`foliate_large_file_analysis_report.md` 第 145 行） | 與 Issue 8 已用真機 logcat 實際確認的 OOM 崩潰紀錄直接對照 | ❌ **與本專案實測結果直接矛盾**。原因見下方分析——這句結論只在「書已開啟、逐頁閱讀」階段成立，不涵蓋「開書當下」。 |

### 為何「Loader/maxLoaded 機制確實存在」與「實際上仍然 OOM」兩者不矛盾

`Loader.unref()`／`planScrollModePages` 兩套機制都是**書本已成功開啟後、逐頁閱讀期間**的記憶體管理，管的是「哪些已解壓頁面該被淘汰」。它們完全不影響、也解決不了 Issue 8 真正的問題——**開書當下要先把整份檔案的內容送進 WebView**這個步驟本身。

直接查證 `view.js` 原始碼，找到 `main.js` 實際呼叫 `makeBook()` 的路徑（`main.js`：`makeBook('https://appassets.androidplatform.net/book/current.epub')`，字串 URL）：

```js
// view.js
const fetchFile = async url => {
    const res = await fetch(url)
    if (!res.ok) throw new ResponseError(...)
    return new File([await res.blob()], new URL(res.url).pathname)
}
export const makeBook = async file => {
    if (typeof file === 'string') file = await fetchFile(file)
    ...
```

`fetch(url)` + `await res.blob()` 是**單次、完整的整份回應緩衝**——這與既有 `foliate_native_bridge.dart:98-101` doc comment 已經記載的查證結論（「`view.js` 原始碼確認一次性讀取整份內容、不發 HTTP Range 請求」）完全吻合，且是**本次 `/diagnose` 獨立重新查證、非沿用舊結論**得到的相同答案。兩份外部報告都沒有精確描述到這一段——`makeBook()` 收到字串 URL 時，根本不會走到 `zip.js` 的任何 Reader（不管有沒有 `HttpRangeReader`），因為 `zip.js` 是在**已經拿到完整 `File`/`Blob` 之後**才登場，處理的是「這個 Blob 內部哪些 ZIP entry 要不要解壓」，不是「這個 Blob 本身該怎麼取得」。

### 對修復方向的影響：原結論不變，但新增一個尚待真機驗證的殘餘風險

`reviews/bugfix-repro.md`（本檔案）先前段落建議的原生 `WebViewAssetLoader`／`InternalStoragePathHandler` 串流方案，解決的是**目前唯一有真機崩潰證據的那個點**——`ReaderResourceChannel.kt:58` 的 `ByteArrayOutputStream.toByteArray()`（App 自身 Dalvik/ART heap）。這個結論不因兩份外部報告而改變，建議依然有效。

但深入查證 `fetchFile()` 後浮現一個先前查證未觸及的問題：即使原生端改成串流回應，WebView 內的 `fetch()` 仍然會對這個回應呼叫 `res.blob()`，在 **WebView 渲染器行程**（獨立於 App 主行程的 sandboxed process，另見 Issue 9 logcat 觀察）內把整份回應緩衝成一個 `Blob`。Chromium 對大型 `Blob` 通常有磁碟/共享記憶體支援的儲存策略、不見得會在單一連續記憶體區塊放滿全部內容，但**這是瀏覽器引擎內部行為，本次查證範圍內的 JS 原始碼或既有文件都無法確認這一步驟對 217MB 檔案是否真的不會在渲染器行程觸發自己的 OOM**——因為原始崩潰發生在更早的 App 主行程階段，从未真正走到這一步，沒有既有證據可用。

**建議：** Planning／實作階段完成原生串流修正後，務必以 `tmp/膽大黨10.epub`（217MB，原始崩潰樣本）在真機重新測試到底，確認整個開書流程（含 WebView 端 `res.blob()`）皆不再崩潰，而不是只確認 `ReaderResourceChannel.kt` 這一個點不再拋錯——若渲染器行程階段仍然崩潰，代表需要進一步處理（可能得評估改用 `res.arrayBuffer()`／串流讀取等 `fetchFile()` 以外的路徑，但這樣會違反「不修改釘定版本」的限制，屆時需要另外評估）。
