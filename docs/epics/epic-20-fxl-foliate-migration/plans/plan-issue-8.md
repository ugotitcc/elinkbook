# Epic 20 Issue 8 — 大型 EPUB OOM 閃退修復（原生 `WebViewAssetLoader` 串流服務） 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 修復開啟大型 EPUB（約 200MB+，真實樣本 `tmp/膽大黨10.epub`，217MB）時因整檔載入記憶體導致的 `OutOfMemoryError` 閃退。改用原生 `androidx.webkit.WebViewAssetLoader`（`InternalStoragePathHandler`）串流服務 `/book/current.epub` 請求，取代現行 Dart-side `shouldInterceptRequest` 的全檔一次性讀取。

**依賴：** Issue 5（已合併，`main`）。與 Issue 7（真機端到端驗證）建立相依：Issue 7 驗收應涵蓋本工單的大型檔案判準。

**架構決策：** 見 `docs/adr/0018-webviewassetloader-streaming-for-large-epub.md`（本工單即該 ADR 的實作）。完整技術可行性研究過程見 `docs/epics/epic-20-fxl-foliate-migration/reviews/bugfix-repro.md`（`/diagnose` 產出，含對兩份外部分析報告的逐項查證）。

**已查證的關鍵技術事實（ADR 0018 已完整記錄，此處摘要供實作時快速對照）：**

- **崩潰點**：`ReaderResourceChannel.kt:58`（`readContentUri`，`content://` 來源）與 `foliate_native_bridge.dart:124`（`File.readAsBytes()`，本機檔案來源），皆整份讀進單一記憶體陣列。
- **Dart 端 `WebResourceResponse.data` 型別鎖死 `Uint8List?`**（`flutter_inappwebview_platform_interface-1.3.0+1/lib/src/types/web_resource_response.dart:17`），透過 `InAppWebView.shouldInterceptRequest` Dart callback（含套件自帶 `CustomPathHandler`）這條路徑天生無法串流。
- **`flutter_inappwebview` 原生端已內建 `WebViewAssetLoader` 整合**，優先於 Dart callback 被檢查（`InAppWebViewClient.java:631-644`，本機 pub cache：`flutter_inappwebview_android-1.1.3/android/.../webview/in_app_webview/InAppWebViewClient.java`）——若 `webViewAssetLoaderExt.loader.shouldInterceptRequest(uri)` 對某 URL 回傳 `null`（無匹配的已註冊 path handler 前綴），會自動落回 Dart callback，兩條路徑天然並存不衝突。
- **Dart 端 API**：`InAppWebViewSettings(webViewAssetLoader: WebViewAssetLoader(domain: ..., pathHandlers: [InternalStoragePathHandler(path: '/book/', directory: <絕對路徑字串>)]))`（`flutter_inappwebview-6.1.5/lib/src/webview_asset_loader.dart:84-90`；官方範例：`flutter_inappwebview-6.1.5/example/integration_test/in_app_webview/webview_asset_loader.dart`）。
- **原生端對映**：`InternalStoragePathHandler` → `new File(directory)` → `new androidx.webkit.WebViewAssetLoader.InternalStoragePathHandler(context, dir)`（`WebViewAssetLoaderExt.java:64-73`）——真正原生、以 `FileInputStream` 運作，**不經過 Dart callback**，與同檔案內的 `CustomPathHandler`／`PathHandlerExt`（仍會橋接回 Dart，`:101-148`，行為與現行 Dart callback 相同、不解決本問題）明確不同，實作時不可混淆。
- **`main.js` 開書 URL 已硬編碼為 `'https://appassets.androidplatform.net/book/current.epub'`**（vendored 檔案，不可修改）。`appassets.androidplatform.net` 恰為 `WebViewAssetLoader.DEFAULT_DOMAIN`，本工單不需要、也不應該修改這個 URL 或 domain 設定，只需確保 `/book/` 前綴的請求能被新註冊的 `InternalStoragePathHandler` 正確攔截。
- **`_shouldInterceptRequest`（`foliate_epub_reader_view.dart:409-437`）目前處理三種前綴**：`/book/current.epub`（本工單要移除、改走原生）、`/assets/foliate/*`（`foliate-js` 靜態資源，小檔案，維持 Dart callback 不動）、`/assets/fonts/*`（字型檔，小檔案，維持 Dart callback 不動）。手術式異動，只碰第一種。
- **`FoliateEpubReaderView` 目前無 `initState()` override，`build()`（`:456`）直接同步建構 `InAppWebView`**，`_initialIndexUri`（`:297`）是 `late final` 同步計算欄位。本工單需要在 `InAppWebView` 真正掛載前插入一段非同步「確保書籍已落地快取」的前置步驟——比照 `ReaderScreen` 既有的載入中/錯誤狀態模式（`Key('reader_loading_indicator')`／`Key('reader_error_text')`，外層已有），`FoliateEpubReaderView` 內部在快取完成前可回傳 `SizedBox.shrink()`（不需要自己疊一層視覺載入指示器，外層 `ReaderScreen` 已負責），快取失敗時呼叫 `widget.onError(...)`（比照既有 `:344` 呼叫慣例）。
- **既有 `isPathWithinRoot` 檢查**（`foliate_native_bridge.dart:107-111,121-123`）已確認：本機檔案路徑一律落在 `getApplicationDocumentsDirectory()` 的父目錄（App 私有資料根目錄）範圍內——這個既有驗證邏輯在本工單中應該保留（新的複製流程仍需要先驗證來源路徑合法，才能決定要不要複製），只是複製「之後」的服務方式改變。
- **計劃審查發現（2026-07-31，`tmp/epic-20/plan_issue_8_review_report.md`）：單一固定快取槽位在螢幕轉場期間有競態風險**——`ReaderScreen` 每次開書皆是 `Navigator.push` 新路由，Flutter 預設轉場動畫在 pop/push 交疊期間，舊路由的 `FoliateEpubReaderView`（尚未真正 `dispose()`）與新路由的 `FoliateEpubReaderView` 可能短暫同時掛載。若兩者共用同一個固定檔名（`current.epub`），使用者快速「退出書 A → 開啟書 B」時兩個原生複製操作可能同時寫入同一路徑，導致其中一本書被覆寫或讀到寫入中途的半份檔案——不是閃退，是安靜地顯示錯誤/損毀內容。**因此改為每個 widget 實例使用獨立的快取子目錄**（而非全域共用的固定檔名），詳見下方 Task 1-3 的對應調整。
- **計劃審查發現：Kotlin 端 `MethodChannel.setMethodCallHandler` 的 callback 預設在 Android 主執行緒（UI 執行緒）執行**——217MB 檔案的分塊複製即使是有界記憶體、不會 OOM，仍可能耗時數秒，若在主執行緒同步執行會阻塞手勢/動畫/UI 更新，觸發 ANR watchdog（本專案明確以 E-Ink／較舊裝置為目標族群，儲存 I/O 可能更慢，風險不只是「感知延遲」）。**改為透過 `BinaryMessenger.makeBackgroundTaskQueue()` 讓這個 method channel 的複製呼叫在背景執行緒池執行**，詳見 Task 1 Step 2。

## Global Constraints

- **`readest/foliate-js` 釘定版本本身不修改**（`vendor/`、`view.js`、`main.js` 等，一律不動）。
- **`content://` 與本機檔案路徑統一走同一套分塊複製機制**，不特殊處理本機檔案（ADR 0018 已說明理由：`InternalStoragePathHandler` 的原生端路徑穿越安全檢查對符號連結行為不確定，統一複製換取一致性）。
- **`/assets/foliate/*`／`/assets/fonts/*` 兩條既有 Dart callback 路徑不動**，只移除 `_shouldInterceptRequest` 的 `/book/current.epub` 分支。
- **快取為每個 widget 實例獨立的子目錄**（`<filesDir>/foliate_book_cache/<實例唯一 ID>/current.epub`，見上方計劃審查發現），避免螢幕轉場期間的競態；`InternalStoragePathHandler` 的 URL 前綴固定仍是 `/book/`（`main.js` 硬編碼，不可變），但每個 `InAppWebView` 實例各自的 `webViewAssetLoader` 設定指向各自專屬的子目錄，互不共用可變狀態。
- **Kotlin 端複製操作透過 `BinaryMessenger.makeBackgroundTaskQueue()` 在背景執行緒執行**，不阻塞 Android 主執行緒（見上方計劃審查發現）。
- **測試素材**：`tmp/膽大黨10.epub`（217MB，本 Issue 原始崩潰樣本）為必要驗收樣本；`tmp/一弦定音.epub`（77MB，既有回歸基準）與 `app/test/fixtures/sample.epub`（既有小型 fixture）用於一般大小回歸；真機固定使用 `3CEF42ECD491687`。
- **殘餘風險提醒**（ADR 0018 已記錄）：真機驗收必須測試「整個開書流程」（含 WebView 端 `res.blob()` 是否也扛得住 217MB），不能只確認 Kotlin 端不再拋錯就視為通過；本專案目前無任何 `onRenderProcessGone` 覆寫（已查證全專案零匹配），若渲染器行程真的因此 OOM，預期現象是整個 App 進程被系統直接終止（明顯可辨識的崩潰），而非卡住或被 `onError` 攔截到。

---

## 檔案結構

- Modify：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`
- Modify：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`（Task 4 Step 2 保底清理）
- Modify：`app/lib/reader/foliate_native_bridge.dart`
- Modify：`app/lib/reader/foliate_epub_reader_view.dart`
- Modify：`app/test/reader/foliate_epub_reader_view_test.dart`（既有單元測試需同步調整，套用 `foliate_native_bridge_test.dart:26-42` 既有 mock 範式，見 Task 5 Step 1）
- 新增測試（視 Task 2/3 實作內容決定，見下方各 Task 說明）

---

### Task 1：Kotlin 端——分塊串流複製機制

**Files:**
- Modify：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`

**Interfaces:**
- Consumes：`content://` URI 字串、或已通過 `isPathWithinRoot` 驗證的本機檔案絕對路徑；Dart 端產生的實例唯一 ID（用於區隔快取子目錄）
- Produces：新的 method channel 方法（例如 `cacheBookForServing`），成功時回傳快取檔案的絕對路徑（供 Dart 端組出 `InternalStoragePathHandler` 的 `directory` 參數），失敗回傳 `null`；此 method channel 註冊為背景 `TaskQueue`，不阻塞 Android 主執行緒

- [ ] **Step 1：新增分塊複製 helper 函式（快取路徑改為依實例 ID 區隔子目錄）**

在 `ReaderResourceChannel.kt` 新增一個 `private fun copyToCache(input: InputStream, instanceId: String): String?`（或視實作習慣調整簽章），內部邏輯——**計劃審查發現（2026-07-31）**：快取路徑改為 `foliate_book_cache/<instanceId>/current.epub`，取代原本全域共用的固定檔名，避免螢幕轉場期間兩個 `FoliateEpubReaderView` 實例並存、共用同一個可變檔案的競態（見上方 Global Constraints）：

```kotlin
val cacheDir = File(context.filesDir, "foliate_book_cache/$instanceId").apply { mkdirs() }
val destFile = File(cacheDir, "current.epub")
try {
    input.use { source ->
        FileOutputStream(destFile).use { output ->
            source.copyTo(output)  // Kotlin 標準函式，預設 8KB 緩衝，有界記憶體
        }
    }
    return destFile.absolutePath
} catch (e: Exception) {
    destFile.delete()
    return null
}
```

- [ ] **Step 2：新增 `onMethodCall` 分支 `cacheBookForServing`，並註冊為背景 `TaskQueue`**

**計劃審查發現（2026-07-31）**：`MethodChannel.setMethodCallHandler` 的 callback 預設在 Android 主執行緒執行，217MB 檔案複製即使有界記憶體、不會 OOM，仍可能耗時數秒、阻塞 UI 造成 ANR 風險——改用 `BinaryMessenger.makeBackgroundTaskQueue()`（Flutter engine 2.8+ API）建立獨立的 `MethodChannel` 實例處理這個方法：

```kotlin
private val cacheChannel = MethodChannel(
    messenger,
    "elinkbook/reader_resources_cache",
    StandardMethodCodec.INSTANCE,
    messenger.makeBackgroundTaskQueue(),
)
// init { } 內註冊 cacheChannel.setMethodCallHandler(...)，與既有 channel（主執行緒）分開處理
```

`onMethodCall` 內新增分支，依傳入參數是 `content://` URI 或本機檔案路徑分派——**計劃審查發現（2026-07-31）：整個 `when { ... }`（含開啟輸入串流）須納入同一個 try/catch**（比照即將被取代的 `readContentUri` 既有範圍，原始草稿只把 try/catch 包在 `copyToCache` 內部、開啟串流的呼叫本身在範圍外，SAF 授權失效／檔案競態刪除等情境會讓例外未被捕捉地冒出，變成 Dart 端未預期的 `PlatformException`，而非設計中「乾淨的 `null` 回傳 → `onError(...)`」路徑）：

```kotlin
"cacheBookForServing" -> {
    val instanceId = call.argument<String>("instanceId")
    val uriString = call.argument<String>("uri")
    val filePath = call.argument<String>("filePath")
    if (instanceId == null) {
        result.success(null)
        return
    }
    val cachedPath = try {
        val input: InputStream? = when {
            uriString != null -> context.contentResolver.openInputStream(Uri.parse(uriString))
            filePath != null -> File(filePath).inputStream()
            else -> null
        }
        input?.let { copyToCache(it, instanceId) }
    } catch (e: Exception) {
        null
    }
    result.success(cachedPath)
}
```

（注意：Dart 端已經用既有 `isPathWithinRoot` 驗證過本機檔案路徑合法性才會呼叫到這裡；`content://` 分支延續現行「SAF 權限模型本身把關」的既有信任層級，不做額外路徑檢查，比照原 `readContentUri` 既有慣例。）

- [ ] **Step 3：移除已成為死碼的 `readContentUri` 分支**

`Task 2` 確認 Dart 端不再呼叫 `readContentUri` 後，移除該 `onMethodCall` 分支（`readAndroidAsset` 服務 `/assets/foliate/*`，不受影響，保留在原本的主執行緒 channel 上，不需要背景 `TaskQueue`——這些是小檔案，非本工單的效能/ANR 疑慮範圍）。

---

### Task 2：Dart 端橋接——`foliate_native_bridge.dart`

**Files:**
- Modify：`app/lib/reader/foliate_native_bridge.dart`

**Interfaces:**
- Consumes：Task 1 新增的 `cacheBookForServing` method channel 方法（背景 `TaskQueue`）
- Produces：`Future<String?> cacheBookForServing(String filePath, String instanceId)`，回傳快取檔案絕對路徑或 `null`

- [ ] **Step 1：新增 `cacheBookForServing()` 函式，接受呼叫端提供的實例唯一 ID**

比照現行 `loadBookBytes()`（`:113-125`）的 `"://"` 啟發式判斷與 `isPathWithinRoot` 驗證邏輯（**保留這段驗證，只改變驗證通過後的動作**——從「直接讀取位元組」改成「呼叫原生端分塊複製」）。**計劃審查發現（2026-07-31）：新增 `instanceId` 參數**，由呼叫端（Task 3 的 `_FoliateEpubReaderViewState`）產生並傳入，用於 Task 1 Step 1 的快取子目錄區隔（避免螢幕轉場期間的競態，見 Global Constraints）：

```dart
Future<String?> cacheBookForServing(String filePath, String instanceId) async {
  if (filePath.contains('://')) {
    return _readerResourcesChannel.invokeMethod<String>(
        'cacheBookForServing', {'uri': filePath, 'instanceId': instanceId});
  }
  final file = File(filePath);
  if (!await file.exists()) return null;
  final canonicalPath = file.resolveSymbolicLinksSync();
  final docsDir = await getApplicationDocumentsDirectory();
  final allowedRoot = Directory(docsDir.path).parent.path;
  if (!isPathWithinRoot(canonicalPath, allowedRoot)) return null;
  return _readerResourcesChannel.invokeMethod<String>('cacheBookForServing',
      {'filePath': canonicalPath, 'instanceId': instanceId});
}
```

（`instanceId` 只需在單一 App 生命週期內、同時存在的 `FoliateEpubReaderView` 實例之間不重複即可，不需要跨裝置/跨 App 安裝全域唯一——例如 Dart 端一個簡單的遞增計數器或 `identityHashCode` 皆足夠，實作時決定。）

- [ ] **Step 2：刪除已成為死碼的 `loadBookBytes()`**

確認 Task 3 完成、`foliate_epub_reader_view.dart` 不再呼叫 `loadBookBytes()` 後，刪除該函式（`:98-125`）。

---

### Task 3：`FoliateEpubReaderView` 改用原生 `WebViewAssetLoader`

**Files:**
- Modify：`app/lib/reader/foliate_epub_reader_view.dart`

**Interfaces:**
- Consumes：Task 2 的 `cacheBookForServing()`
- Produces：`InAppWebView` 建構時已設定 `webViewAssetLoader`，`/book/current.epub` 請求由原生端串流服務；快取未完成前不掛載 `InAppWebView`

- [ ] **Step 1：`_FoliateEpubReaderViewState` 新增非同步前置快取步驟（含實例 ID 產生與 `mounted` 守衛）**

新增 `initState()`（目前沒有）：
1. 產生本實例的唯一 ID（例如 `identityHashCode(this).toString()` 或一個遞增計數器），供 `cacheBookForServing()` 區隔快取子目錄。
2. 呼叫 `cacheBookForServing(widget.filePath, instanceId)`，用一個 nullable 狀態欄位（例如 `String? _bookCacheDir`）追蹤結果；成功時取 `File(cachedPath).parent.path` 作為 `InternalStoragePathHandler` 的 `directory`（`cacheBookForServing` 回傳的是**檔案**絕對路徑，`InternalStoragePathHandler` 要的是**目錄**，實作時注意這個轉換）；失敗（回傳 `null`）呼叫 `widget.onError(...)`（比照既有 `:344` 慣例的錯誤訊息風格）。
3. **計劃審查發現（2026-07-31）：`Future` 完成時呼叫 `setState()` 前必須先檢查 `if (!mounted) return;`**——217MB 檔案複製可能耗時數秒（ADR 0018 已承認），若使用者在複製完成前離開 `ReaderScreen`（本 State 已 `dispose()`），未加此守衛會直接拋出 `FlutterError: setState() called after dispose()`。這是 Flutter 非同步生命週期的標準陷阱，不得省略。

- [ ] **Step 2：`build()` 依 `_bookCacheDir` 是否就緒分派**

`_bookCacheDir == null` 時回傳 `SizedBox.shrink()`（外層 `ReaderScreen` 的 `Key('reader_loading_indicator')` 已負責視覺載入狀態，本 widget 內部不需要重複疊一層）；就緒後才建構原本的 `Stack`（`InAppWebView` + 九宮格熱區疊加層）。

- [ ] **Step 3：`InAppWebView` 的 `initialSettings` 新增 `webViewAssetLoader`**

```dart
initialSettings: InAppWebViewSettings(
  javaScriptEnabled: true,
  useShouldInterceptRequest: true,
  webViewAssetLoader: WebViewAssetLoader(
    pathHandlers: [
      InternalStoragePathHandler(path: '/book/', directory: _bookCacheDir!),
    ],
  ),
),
```

（不需要手動指定 `domain`——`main.js` 已硬編碼使用 `WebViewAssetLoader.DEFAULT_DOMAIN`，套件預設值已一致，明確指定 `domain` 反而增加一個容易與 vendored 程式碼失焦的重複來源，除非後續發現預設值不一致才需要顯式覆寫。）

- [ ] **Step 4：`_shouldInterceptRequest` 移除 `/book/current.epub` 分支**

刪除 `:414-419` 這段（`if (path == '/book/current.epub') { ... }`），`/assets/foliate/*`／`/assets/fonts/*` 兩段維持不動。

---

### Task 4：快取生命週期清理

**Files:**
- Modify：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`（Task 1 內已包含「複製前先刪除既有目的檔」，本 Task 聚焦 dispose 時機的額外清理，視實作階段判斷是否需要）

**Interfaces:**
- Consumes：Task 1-3 完成（含審查後改為「每實例獨立子目錄」的設計）
- Produces：`foliate_book_cache/` 目錄不會無限累積孤兒子目錄

- [ ] **Step 1：`FoliateEpubReaderView` dispose 時清理本實例的快取子目錄**

改為每實例獨立子目錄後（`foliate_book_cache/<instanceId>/`），不再有「開新書自動覆蓋前一本書」這種天然清理時機（因為不同實例不共用路徑）——`dispose()` 時應主動刪除 `foliate_book_cache/<instanceId>/` 整個子目錄，避免每次開書都留下一個新的孤兒子目錄。

- [ ] **Step 2：`MainActivity.onCreate()` 新增保底清理，處理異常結束的遺留**

**計劃審查建議（2026-07-31，Minor #3）**：App 異常結束（崩潰、被系統殺掉）時 Step 1 的 dispose 清理不會執行，長期可能累積孤兒子目錄。建議在 `MainActivity.onCreate()` 新增清空整個 `foliate_book_cache/` 目錄的邏輯（App 冷啟動時，不會有任何 `FoliateEpubReaderView` 實例正在使用快取，可安全整個清空，不需要精細判斷哪些子目錄是孤兒）。

---

### Task 5：測試更新、真機驗證、文件更新、送出 PR

**Files:**
- Modify：`app/test/reader/foliate_epub_reader_view_test.dart`
- Modify：`docs/epics/epic-20-fxl-foliate-migration/design.md`、`issues.md`、`docs/epics.md`、本計畫檔

**Interfaces:**
- Consumes：Task 1-4 完成
- Produces：Issue 8 結案，`tmp/膽大黨10.epub` 真機開啟不再 OOM

- [ ] **Step 1：既有單元測試盤點與調整——套用本專案既有的 `MethodChannel` mock 範式**

`foliate_epub_reader_view_test.dart` 中直接建構 `FoliateEpubReaderView` 並等待 `onPageRendered`／`onError` 的既有 widget test，因新增了非同步前置快取步驟（Task 3 Step 1-3）**會直接壞掉**——尤其是「3×3 導航熱區（`InAppWebView`）」與「ES 相容性 polyfill（診斷修正）」這兩組既有測試（目前直接 `pumpWidget` 後用 `find.byKey`／`find.byType(InAppWebView)` 斷言），在測試環境沒有 mock `elinkbook/reader_resources` channel 的情況下，`cacheBookForServing()` 的 `invokeMethod` 會拋出 `MissingPluginException`，導致 `_bookCacheDir` 永遠不會變成非 null、`build()` 永遠回傳 `SizedBox.shrink()`，這兩組測試會找不到 `InAppWebView` 而失敗。

**計劃審查發現（2026-07-31，Important #1）：本專案已有現成的 mock 範式可直接套用**，比照 `app/test/reader/foliate_native_bridge_test.dart:26-42`：

```dart
TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(
  const MethodChannel('elinkbook/reader_resources'),  // 或新的背景 channel 名稱，依 Task 1 Step 2 實際命名調整
  (call) async {
    if (call.method == 'cacheBookForServing') {
      return '/fake/cache/dir/current.epub';  // 回傳假路徑即可，測試不需要真的存在的檔案
    }
    return null;
  },
);
```

在 `foliate_epub_reader_view_test.dart` 的 `setUpAll`／各測試前置註冊此 mock handler，確保「3×3 導航熱區」「ES 相容性 polyfill」兩組既有測試在新架構下仍能通過——這一步必須在實作 Task 3 的**同時**處理，不得留到最後才確認。

- [ ] **Step 2：新增/調整 `integration_test/foliate_epub_reader_view_test.dart` 涵蓋大型檔案情境**

新增一項測試使用 `tmp/膽大黨10.epub`（或等效大小的測試 fixture，若不便長期存放 217MB 檔案於版控，考慮測試時動態產生一個大型但內容無意義的合法 EPUB／或直接引用 `tmp/` 下既有樣本並在測試註解說明其為人工放置的大型驗收樣本，非版控 fixture）驗證 `onPageRendered` 觸發、不崩潰。

- [ ] **Step 3：全套測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
flutter test
./gradlew :app:compileDebugKotlin
```

- [ ] **Step 4：建置並安裝至真機（`3CEF42ECD491687`）**

```bash
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 5：真機驗證（核心判準）**

1. **`tmp/膽大黨10.epub`（217MB）真機開啟不再 OOM**——整個開書流程（含 WebView 端）皆需確認，不能只看 Kotlin 端不再拋錯（ADR 0018 記錄的殘餘風險）。若此步驟仍然崩潰，需回頭查證是否為 WebView 渲染器行程的 `res.blob()` 導致，並依 ADR 0018「殘餘風險」段落的建議重新評估。
2. **`tmp/一弦定音.epub`（77MB，既有回歸基準）與一般小型 EPUB（`app/test/fixtures/sample.epub` 等級）開書行為與現行版本無異**——不得有速度明顯變慢或功能退化。
3. **`content://` 來源與本機檔案路徑來源皆測試過**（比照既有 `content_uri_acceptance_test.dart`／一般匯入流程）。
4. **FXL 與流式 EPUB 皆測試過**（本修復對兩者皆適用，非 FXL 專屬）。
5. **`/assets/foliate/*`／`/assets/fonts/*` 既有 Dart callback 路徑未受影響**——確認字型/直排橫排等既有功能正常（間接驗證兩條路徑並存無衝突）。
6. **（計劃審查發現，2026-07-31，Important #5）量測 `tmp/膽大黨10.epub` 分塊複製耗時，確認過程中無 ANR 對話框跳出**——複製透過背景 `TaskQueue` 執行（Task 1 Step 2）理論上不阻塞主執行緒，但仍須真機實測確認：開書期間 UI（載入指示器動畫、系統手勢）維持回應，複製完成到 `onPageRendered` 之間的總耗時記錄下來供未來參考。
7. **（計劃審查發現，Important #4）快速切換書籍測試**：真機連續操作「開啟書 A → 立即返回 → 開啟書 B」數次（利用 Flutter 轉場動畫期間新舊 `FoliateEpubReaderView` 可能短暫並存的時機），確認兩本書的內容皆正確顯示、互不污染／覆寫（驗證 Task 1-3 改為每實例獨立快取子目錄後，先前計劃審查點出的競態情境已排除）。

- [ ] **Step 6：依結果更新 `design.md`／`issues.md`／`docs/epics.md`**

- [ ] **Step 7：Commit（於獨立 feature branch，比照既有 branch 命名慣例 `feature/epic-20-issue-8-*`）**

- [ ] **Step 8：送出 code review（`superpowers:requesting-code-review`），依審查結果修正後開 PR**

---

## 相關佐證

- `docs/adr/0018-webviewassetloader-streaming-for-large-epub.md`（本工單的架構決策）
- `docs/epics/epic-20-fxl-foliate-migration/reviews/bugfix-repro.md`（`/diagnose` 完整技術可行性研究過程，含外部分析報告逐項查證）
- `docs/epics/epic-20-fxl-foliate-migration/issues.md` Issue 8 段落
- `app/lib/reader/foliate_native_bridge.dart:98-125`（現行 `loadBookBytes()`，即將移除）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`（現行崩潰點所在，需擴充）
- `app/lib/reader/foliate_epub_reader_view.dart:293-437,455-478`（`_FoliateEpubReaderViewState`／`_shouldInterceptRequest`／`InAppWebView` 建構）
- 套件原始碼（本機 pub cache）：
  - `flutter_inappwebview-6.1.5/lib/src/webview_asset_loader.dart`
  - `flutter_inappwebview-6.1.5/example/integration_test/in_app_webview/webview_asset_loader.dart`
  - `flutter_inappwebview_android-1.1.3/android/src/main/java/.../types/WebViewAssetLoaderExt.java`
  - `flutter_inappwebview_android-1.1.3/android/src/main/java/.../webview/in_app_webview/InAppWebViewClient.java`
- `app/test/reader/foliate_native_bridge_test.dart:26-42`（本專案既有的 `MethodChannel` mock 範式，Task 5 Step 1 直接套用）
- `tmp/epic-20/plan_issue_8_review_report.md`（計劃審查報告，2026-07-31，5 項 Important 發現已於本計劃逐一回應）
