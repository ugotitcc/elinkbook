package cc.ugotit.elinkbook

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream

/**
 * 包裝 readest/foliate-js（釘定 commit dd71f2be356563c16a23272686189fcfb45d0b82）
 * 的原生 PlatformView，供流式（reflowable）EPUB 使用（見
 * docs/epics/epic-17-epub-render-migration/spec.md）。固定版面（FXL）EPUB
 * 完全不受影響，繼續使用 EpubReaderView.kt（Readium）。
 *
 * 單一 android.webkit.WebView，透過 WebViewAssetLoader 提供兩組虛擬 host
 * 路徑：`/assets/` 服務 foliate-js 本身（8 個 JS 檔案 + index.html/main.js，
 * app/android/app/src/main/assets/foliate/），`/book/` 服務待開啟的 EPUB
 * 檔案本身（透過自訂 PathHandler，見 [BookPathHandler]）。
 *
 * JS→Kotlin 的回呼透過 addJavascriptInterface 暴露為 window.FoliateBridge
 * （見 [FoliateBridge]），而非解析 console.log（那是 Issue 1 Spike harness
 * 專屬的證據蒐集手法，不適合用在正式功能的通訊機制上）。
 *
 * openBook 只支援本 Issue 明確範圍：filePath／onPageRendered／onError／
 * onLayoutResolved（恆回傳 isFixedLayout: false，writingMode: "horizontal"
 * ——實際依書本 CSS 判斷的邏輯是 Issue 4 的範圍）。setPreferences／
 * nextPage／jumpToProgression／getTableOfContents／setDecorations 等契約
 * 留待 Issue 4-8 依 spec.md「介面」節逐一補上。
 */
class FoliateEpubReaderView(
    private val context: Context,
    id: Int,
    messenger: BinaryMessenger,
) : PlatformView, MethodChannel.MethodCallHandler {

    /**
     * 供 [BookPathHandler] 判斷「這次請求是不是在要求目前這本書」的固定虛擬
     * 檔名——WebView 對這個 handler 的請求只可能來自我們自己的 main.js
     * （固定字面量 URL，見 assets/foliate/main.js），不是從書本內容或任何
     * 使用者可影響的字串組出來的，因此用「是否恰好等於這個常數」當作第一道
     * 關卡即可完全阻絕任何路徑穿越嘗試——不需要對這個字面量做目錄拼接。
     */
    private val currentBookRequestPath = "current.epub"

    private val channel: MethodChannel =
        MethodChannel(messenger, "cc.ugotit.elinkbook/foliate_epub_reader_view_$id")
    private val mainHandler = Handler(Looper.getMainLooper())

    /** 目前待提供給 [BookPathHandler] 的書籍來源；openBook() 成功驗證後才賦值。
     * 兩者恰好一個非 null（見 [openBook] 的 "://" 啟發式判斷，比照
     * EpubReaderView.kt/PdfReaderView.kt 既有慣例）。 */
    private var currentBookFile: File? = null
    private var currentBookUri: Uri? = null

    /**
     * 目前已生效的完整偏好設定（比照 EpubReaderView.kt currentPreferences
     * 的合併語意，見 docs/adr/0006-epub-reader-batch-preferences-contract.md）
     * ——openBook 的 initialPreferences 與後續 setPreferences 都是「合併進
     * 這個 map、再整組序列化送給 JS」，而不是各自獨立送出，否則後送出的
     * 欄位會把先前已設定的其他欄位在 JS 端「遺忘」（JS 端 applyPreferences()
     * 每次都是用收到的完整物件重新產生 CSS，不會自己記得上一次的值）。
     */
    private val currentPreferences = mutableMapOf<String, Any?>()

    /** 5 款內建字型的 @font-face CSS 宣告，開書當下計算一次（見
     * [buildFontFaceCss]），字型檔案路徑固定不隨後續 setPreferences 呼叫
     * 變動。 */
    private var fontFaceCss: String = ""

    private var pageReported = false
    private var isDisposed = false

    private val assetLoader = WebViewAssetLoader.Builder()
        .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(context))
        .addPathHandler("/book/", BookPathHandler())
        .build()

    private val webView: WebView = WebView(context).apply {
        @Suppress("SetJavaScriptEnabled")
        settings.javaScriptEnabled = true
        addJavascriptInterface(FoliateBridge(), "FoliateBridge")
        webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest,
            ): WebResourceResponse? {
                val response = assetLoader.shouldInterceptRequest(request.url) ?: return null
                // 比照 Issue 1 Spike 已驗證的既有機制：WebViewAssetLoader 對
                // .js 副檔名的 MIME 猜測在部分 WebView 版本上不可靠，
                // <script type="module"> 收到非 text/javascript 的 MIME 會
                // 直接拒絕載入（"Expected a JavaScript-or-Wasm module
                // script" 錯誤）。
                if (request.url.path?.endsWith(".js") == true) {
                    return WebResourceResponse(
                        "text/javascript",
                        response.encoding,
                        response.data,
                    )
                }
                return response
            }
        }
    }

    init {
        channel.setMethodCallHandler(this)
        ReaderViewAttachmentTracker.attach()
    }

    override fun getView(): View = webView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                @Suppress("UNCHECKED_CAST")
                openBook(
                    call.argument<String>("path"),
                    call.argument<Map<String, Any?>>("initialPreferences"),
                )
                result.success(null)
            }
            "setPreferences" -> {
                @Suppress("UNCHECKED_CAST")
                setPreferences(call.arguments as? Map<String, Any?>)
                result.success(null)
            }
            "nextPage" -> {
                // 3×3 導航熱區完全由 Dart 端 Stack 疊加層判讀（見
                // foliate_epub_reader_view.dart，epic-17-epub-render-migration
                // Issue 5「不在原生端判讀」），本 case 純粹是換頁指令的轉發，
                // 不做任何座標/熱區判斷。
                webView.evaluateJavascript("window.nextPage()", null)
                result.success(null)
            }
            "previousPage" -> {
                webView.evaluateJavascript("window.previousPage()", null)
                result.success(null)
            }
            "jumpToProgression" -> {
                val progression = call.argument<Double>("progression")
                if (progression != null) {
                    webView.evaluateJavascript("window.jumpToFraction($progression)", null)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * [path] 可能是真實檔案系統路徑，也可能是 content:// 或 file:// URI
     * 字串（見 docs/adr/0002-content-uri-reader-contract.md），比照
     * EpubReaderView.kt/PdfReaderView.kt 既有的 "://" 啟發式判斷。
     *
     * 檔案系統路徑會先正規化（canonicalPath）並驗證是否落在 App 私有文件
     * 目錄之內（[FoliatePathValidator]，見 spec.md 待驗證風險 #3 的安全
     * 要求）——content:// URI 走 Android SAF 權限模型管控，不適用「目錄
     * 邊界」概念，故不做這項檢查，交由 ContentResolver 自身的授權機制
     * 把關（與現有 EpubReaderView/PdfReaderView 對 content:// URI 的既有
     * 信任層級一致）。
     */
    private fun openBook(path: String?, initialPreferences: Map<String, Any?>?) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        pageReported = false
        currentBookFile = null
        currentBookUri = null
        if (path.contains("://")) {
            currentBookUri = Uri.parse(path)
        } else {
            val canonicalFile = try {
                File(path).canonicalFile
            } catch (e: Exception) {
                channel.invokeMethod("onError", "無法解析檔案路徑：$path")
                return
            }
            // 允許範圍：App 私有資料目錄（含 files, cache, app_flutter 等）。
            // context.filesDir.parentFile 通常即為 /data/user/0/pkg/。
            val allowedRoot = context.filesDir.parentFile?.canonicalPath ?: context.filesDir.canonicalPath
            if (!FoliatePathValidator.isPathWithinRoot(canonicalFile.canonicalPath, allowedRoot)) {
                channel.invokeMethod("onError", "檔案路徑不在允許的目錄範圍內：$path")
                return
            }
            currentBookFile = canonicalFile
        }
        currentPreferences.clear()
        initialPreferences?.let { currentPreferences.putAll(it) }
        fontFaceCss = buildFontFaceCss()
        val prefsJson = Uri.encode(JSONObject(currentPreferences).toString())
        val fontFaceCssEncoded = Uri.encode(fontFaceCss)
        webView.loadUrl(
            "https://appassets.androidplatform.net/assets/foliate/index.html" +
                "?prefs=$prefsJson&fontFaceCss=$fontFaceCssEncoded",
        )
    }

    /**
     * 合併 [preferences] 進 [currentPreferences] 並整組序列化送給 JS（比照
     * EpubReaderView.kt setPreferences() 的合併語意，見 Global Constraints）。
     * 書本尚未成功開啟（openBook 尚未呼叫）時 currentPreferences 為空，
     * 呼叫仍會執行但 JS 端 window.applyPreferences 此時尚未定義，
     * evaluateJavascript 靜默失敗——Dart 端只會在 onPageRendered 觸發之後
     * 才送出這個指令，理論上不會發生。
     */
    private fun setPreferences(preferences: Map<String, Any?>?) {
        if (preferences == null) return
        currentPreferences.putAll(preferences)
        val prefsJson = JSONObject(currentPreferences).toString()
        webView.evaluateJavascript("window.applyPreferences($prefsJson)", null)
    }

    /**
     * 產生固定的 5 款內建字型 @font-face 宣告（FR-09），供 JS 端
     * window.applyPreferences() 的 fontFamily 選擇引用。透過 FlutterInjector
     * 取得 Flutter asset 的 AssetManager 查找鍵（比照 EpubReaderView.kt
     * buildNavigatorConfiguration() 既有做法），經既有註冊的 /assets/
     * WebViewAssetLoader.AssetsPathHandler 提供給 WebView（該 handler 服務
     * 整個 Android assets/ 目錄，不限 assets/foliate/ 子目錄，故可直接沿用，
     * 不需要額外註冊 PathHandler）。家族名稱字串須與 Dart 端
     * AppFont.familyName（app/lib/reader/app_font.dart）逐字一致。
     */
    private fun buildFontFaceCss(): String {
        val loader = FlutterInjector.instance().flutterLoader()
        val fontAssets = mapOf(
            "SourceHanSansTC" to "assets/fonts/SourceHanSansTC-VF.ttf",
            "SourceHanSerifTC" to "assets/fonts/SourceHanSerifTC-VF.ttf",
            "GuanKiapTsingKhai" to "assets/fonts/GuanKiapTsingKhai.ttf",
            "TaiwanPearl" to "assets/fonts/TaiwanPearl-Regular.ttf",
            "GenRyuMinTW" to "assets/fonts/GenRyuMinTW-Regular.ttf",
        )
        return fontAssets.entries.joinToString("\n") { (familyName, path) ->
            val lookupKey = loader.getLookupKeyForAsset(path)
            "@font-face { font-family: '$familyName'; " +
                "src: url('https://appassets.androidplatform.net/assets/$lookupKey'); }"
        }
    }

    /**
     * 服務 main.js 固定請求的虛擬書籍檔名（見 [currentBookRequestPath]），
     * 把目前 [currentBookFile]／[currentBookUri] 對應的實際內容整份讀出
     * 回傳——readest/foliate-js（釘定 commit）的 view.js makeBook() 對字串
     * URL 引數一律呼叫 fetch(url) 後 res.blob()，一次性讀取整個回應內容，
     * 不會發出 HTTP Range 請求，因此不需要支援分段內容（已直接查證 view.js
     * 原始碼確認，非臆測，見 Global Constraints）。
     */
    private inner class BookPathHandler : WebViewAssetLoader.PathHandler {
        override fun handle(path: String): WebResourceResponse? {
            if (path != currentBookRequestPath) return null
            val file = currentBookFile
            val uri = currentBookUri
            val stream = when {
                file != null -> try {
                    FileInputStream(file)
                } catch (e: Exception) {
                    null
                }
                uri != null -> try {
                    context.contentResolver.openInputStream(uri)
                } catch (e: Exception) {
                    null
                }
                else -> null
            } ?: return null
            return WebResourceResponse("application/epub+zip", null, stream)
        }
    }

    /**
     * JS→Kotlin 橋接（main.js 呼叫 window.FoliateBridge.xxx()）。
     * @JavascriptInterface 方法在 WebView 的背景執行緒被呼叫，必須切回主
     * 執行緒才能安全操作 MethodChannel／觸發 Flutter 端回呼。
     */
    private inner class FoliateBridge {
        /**
         * [writingMode] 為 main.js 判斷出的最終生效方向（"vertical"／
         * "horizontal"）——書本自己宣告的值優先，否則預設橫排，見
         * assets/foliate/main.js 的 FR-06 偵測邏輯（epic-17-epub-render-migration
         * Issue 4）。
         */
        @JavascriptInterface
        fun onPageRendered(writingMode: String) {
            mainHandler.post {
                if (isDisposed || pageReported) return@post
                pageReported = true
                channel.invokeMethod("onPageRendered", null)
                channel.invokeMethod(
                    "onLayoutResolved",
                    mapOf(
                        "isFixedLayout" to false,
                        "writingMode" to writingMode,
                    ),
                )
            }
        }

        @JavascriptInterface
        fun onError(message: String) {
            mainHandler.post {
                if (isDisposed) return@post
                channel.invokeMethod("onError", message)
            }
        }
    }

    override fun dispose() {
        isDisposed = true
        ReaderViewAttachmentTracker.detach()
        webView.destroy()
    }
}
