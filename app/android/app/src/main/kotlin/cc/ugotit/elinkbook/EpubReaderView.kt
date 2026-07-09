package cc.ugotit.elinkbook

import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.FragmentFactory
import androidx.fragment.app.add
import androidx.fragment.app.commitNow
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.css.FontStyle
import org.readium.r2.navigator.epub.css.FontWeight
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.navigator.preferences.TextAlign
import org.readium.r2.shared.publication.Layout
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.toAbsoluteUrl
import org.readium.r2.shared.util.toUrl
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.data.ReadError
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser
import java.io.File

/**
 * 包裝 Readium kotlin-toolkit 的原生 PlatformView。透過 MethodChannel 接收 Flutter 的
 * openBook 呼叫，成功則呼叫 onPageRendered，失敗則呼叫 onError(message)。
 *
 * EpubNavigatorFragment 的建構子是 internal（只能透過 Readium 自己的 FragmentFactory
 * 建立），因此本類別把它掛載到 Activity 層級的 supportFragmentManager，而不是自己直接
 * new 一個實例——getView() 回傳的是一個空的容器 View，Fragment 是非同步解析完
 * Publication 之後才用 FragmentTransaction 掛進這個容器的。
 *
 * `activity.supportFragmentManager.fragmentFactory` 是 Activity 層級的全域屬性，本類別
 * 在 attachNavigator() 覆寫它之前，會先保留原本的值，並在 dispose() 還原——避免影響
 * Activity 上其他 Fragment。本 App 目前的畫面設計（見 spec.md 的單一 seam）同一時間只會
 * 顯示一個原生閱讀 view，但 Flutter 的路由轉場（route transition）期間，舊畫面的
 * PlatformView 在轉場動畫播完、正式從 widget tree 移除之前，可能與新畫面的 PlatformView
 * 短暫並存（這是 Flutter Navigator 的正常行為，不是本類別自創的假設）。若單純「保留一份、
 * 還原一份」，舊畫面 dispose() 時可能把新畫面剛設定好的 fragmentFactory 覆寫掉。因此
 * dispose() 還原前會先檢查目前的 fragmentFactory 是不是仍是本實例自己安裝的那一個
 * （identity 比對，見 installedFragmentFactory）——如果轉場期間已經被另一個實例換掉，
 * 代表 factory 已經不是本實例的責任，直接放著不動，避免蓋掉另一個仍在使用中的實例。
 *
 * 【重要前提】上述整套「把 Fragment 掛進 Activity 層級 supportFragmentManager」的機制，
 * 成立的前提是 Flutter 的 AndroidView（見 lib/reader/epub_reader_view.dart）目前是以
 * Texture Layer Hybrid Composition（TLHC，近期 Flutter 版本中 AndroidView 的預設合成
 * 模式）運作——在這個模式下，PlatformView 的容器確實存在於 Activity 真正的 view 階層
 * 中，containerId 才能透過 activity.supportFragmentManager 解析到實際的 View。若未來
 * Flutter 升級或設定變動導致改用舊式的 Virtual Display 合成模式，PlatformView 的容器
 * 其實會位於獨立的 Presentation 視窗、不在 Activity 的 view 樹裡，containerId 將無法
 * 解析，attachNavigator() 中的 commitNow 會失敗（並會透過 onError 回報，而不是讓例外
 * 未被攔截導致協程崩潰）——但失敗的根本原因在當下不會有任何線索可查。由於 Flutter 並未
 * 提供乾淨的 API 可在 Kotlin 端偵測目前是哪一種合成模式，這裡無法加執行期檢查，只能留下
 * 這段說明，避免日後排查時毫無頭緒。
 */
class EpubReaderView(
    private val context: Context,
    private val activity: FragmentActivity,
    id: Int,
    messenger: BinaryMessenger,
) : PlatformView,
    MethodChannel.MethodCallHandler,
    EpubNavigatorFragment.Listener,
    EpubNavigatorFragment.PaginationListener {

    private val containerId = View.generateViewId()
    private val container = FrameLayout(context).apply { this.id = containerId }
    private val channel = MethodChannel(messenger, "cc.ugotit.elinkbook/epub_reader_view_$id")
    private val fragmentTag = "cc.ugotit.elinkbook.epub_reader_view_$id"
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val previousFragmentFactory = activity.supportFragmentManager.fragmentFactory
    private var installedFragmentFactory: FragmentFactory? = null
    private var publication: Publication? = null
    private var navigatorFragment: EpubNavigatorFragment? = null
    private var pageReported = false
    private var isDisposed = false

    /**
     * 目前已生效的完整偏好設定（見
     * docs/adr/0006-epub-reader-batch-preferences-contract.md）。setPreferences
     * 與 openBook 的 initialPreferences 套用都是「合併進這個物件、再整組送出」，
     * 而不是各自建構獨立的 EpubPreferences 覆蓋——否則後送出的欄位會把先前已
     * 設定的其他欄位重設回預設值。openBook 完成後若 initialPreferences 非空，
     * 會在 attachNavigator() 內立即合併套用一次，不需等待後續 setPreferences
     * 呼叫（解決先前版本「持久化設定在開書當下沒有真正套用」的缺口）。
     */
    private var currentPreferences = EpubPreferences()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = container

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
            else -> result.notImplemented()
        }
    }

    /**
     * 合併 [preferences] 進 currentPreferences 並整組送出，取代原本各自獨立的
     * setWritingMode／setPageTurnMode（見
     * docs/adr/0006-epub-reader-batch-preferences-contract.md）。書本尚未成功
     * 開啟（navigatorFragment 仍為 null）時靜默忽略——Dart 端只會在
     * onPageRendered 觸發之後才送出這個指令，理論上不會發生。
     */
    private fun setPreferences(preferences: Map<String, Any?>?) {
        if (preferences == null) return
        currentPreferences = currentPreferences.plus(buildPreferencesFromMap(preferences))
        navigatorFragment?.submitPreferences(currentPreferences)
    }

    /**
     * 把 Dart 端送來的偏好設定 map（openBook 的 initialPreferences，或
     * setPreferences 的參數，兩者格式相同）轉換為 EpubPreferences；未出現在
     * map 中的 key 對應到該欄位的 null（交由 currentPreferences.plus() 決定
     * 最終生效值，不覆蓋既有已設定的其他欄位）。
     */
    private fun buildPreferencesFromMap(map: Map<String, Any?>): EpubPreferences {
        return EpubPreferences(
            verticalText = (map["writingMode"] as? String)?.let { it == "vertical" },
            scroll = (map["pageTurnMode"] as? String)?.let { it == "scroll" },
            fontFamily = (map["fontFamily"] as? String)?.let { FontFamily(it) },
            fontSize = (map["fontSize"] as? Number)?.toDouble(),
            fontWeight = (map["fontWeight"] as? Number)?.toDouble(),
            lineHeight = (map["lineHeight"] as? Number)?.toDouble(),
            paragraphSpacing = (map["paragraphSpacing"] as? Number)?.toDouble(),
            pageMargins = (map["pageMargins"] as? Number)?.toDouble(),
            textAlign = (map["textAlign"] as? String)?.let { textAlignFromName(it) },
            publisherStyles = map["publisherStyles"] as? Boolean,
            textNormalization = true,
        )
    }

    private fun textAlignFromName(name: String): TextAlign? {
        return when (name) {
            "center" -> TextAlign.CENTER
            "justify" -> TextAlign.JUSTIFY
            "start" -> TextAlign.START
            "end" -> TextAlign.END
            "left" -> TextAlign.LEFT
            "right" -> TextAlign.RIGHT
            else -> null
        }
    }

    /**
     * 登記 5 款內建字型（FR-09），讓 Readium 內嵌的 WebView 能實際載入本地
     * asset 字型檔案（見 docs/epics/epic-3-fonts-layout/spec.md「自訂字型
     * 如何讓原生 WebView 實際載入」）。這 5 個 family 名稱字串須與 Dart 端
     * `AppFont.familyName`（app/lib/reader/app_font.dart）逐字一致。只需在
     * attachNavigator() 執行一次，字型集合固定、不隨後續 setPreferences
     * 呼叫變動。
     */
    private fun buildFontFamiliesConfiguration(): EpubNavigatorFragment.Configuration {
        val loader = FlutterInjector.instance().flutterLoader()
        val fontAssets = mapOf(
            "SourceHanSansTC" to "assets/fonts/SourceHanSansTC-VF.ttf",
            "SourceHanSerifTC" to "assets/fonts/SourceHanSerifTC-VF.ttf",
            "GuanKiapTsingKhai" to "assets/fonts/GuanKiapTsingKhai.ttf",
            "TaiwanPearl" to "assets/fonts/TaiwanPearl-Regular.ttf",
            "GenRyuMinTW" to "assets/fonts/GenRyuMinTW-Regular.ttf",
        )
        val lookupKeys = fontAssets.mapValues { (_, path) -> loader.getLookupKeyForAsset(path) }
        return EpubNavigatorFragment.Configuration {
            servedAssets = lookupKeys.values.toList()
            for ((familyName, lookupKey) in lookupKeys) {
                addFontFamilyDeclaration(
                    fontFamily = FontFamily(familyName),
                    alternates = listOf(FontFamily.SANS_SERIF),
                ) {
                    addFontFace {
                        addSource(lookupKey, preload = true)
                        setFontStyle(FontStyle.NORMAL)
                        setFontWeight(FontWeight.NORMAL)
                    }
                    addFontFace {
                        addSource(lookupKey, preload = true)
                        setFontStyle(FontStyle.NORMAL)
                        setFontWeight(FontWeight.BOLD)
                    }
                }
            }
        }
    }

    private fun openBook(path: String?, initialPreferences: Map<String, Any?>?) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        pageReported = false
        scope.launch {
            // 外層 try/catch 涵蓋整個開書流程（包含 AssetRetriever/DefaultPublicationParser
            // 等元件的建構與呼叫）。retrieve()/open() 各自宣告的失敗（Try.Failure）已經用
            // getOrElse 導向 onError；這裡額外攔截的是它們或周邊元件拋出的「非預期」例外
            // （例如底層建構子本身丟出的 RuntimeException），避免變成未攔截的協程例外。
            try {
                val httpClient = DefaultHttpClient()
                val assetRetriever = AssetRetriever(context.contentResolver, httpClient)
                val resolvedUrl = resolveAbsoluteUrl(path)
                if (resolvedUrl == null) {
                    channel.invokeMethod("onError", "無法解析檔案路徑或 URI：$path")
                    return@launch
                }
                val asset = assetRetriever.retrieve(resolvedUrl).getOrElse {
                    channel.invokeMethod("onError", "找不到檔案或檔案已損毀：$path")
                    return@launch
                }
                val publicationParser = DefaultPublicationParser(
                    context,
                    httpClient,
                    assetRetriever,
                    pdfFactory = null,
                )
                val publicationOpener = PublicationOpener(publicationParser)
                val openedPublication = publicationOpener.open(asset, allowUserInteraction = false).getOrElse {
                    channel.invokeMethod("onError", "無法解析 EPUB 檔案：${it.message}")
                    return@launch
                }
                // openBook 是非同步流程，Flutter 端有可能在這段 await 期間就把這個
                // PlatformView 銷毀（dispose() 已執行）。scope.cancel() 只能取消協程本身，
                // 但 attachNavigator() 內完全是同步呼叫（沒有 suspend 呼叫點），協程機制
                // 不會在這中間自動檢查取消狀態——若不手動檢查，可能會把 Fragment 掛到一個
                // 已經從畫面移除、id 已不存在於 view 樹中的容器，導致例外或資源洩漏。
                if (isDisposed) {
                    openedPublication.close()
                    return@launch
                }
                attachNavigator(openedPublication, initialPreferences)
            } catch (e: Exception) {
                channel.invokeMethod("onError", "開啟 EPUB 檔案時發生未預期的錯誤：${e.message}")
            }
        }
    }

    private fun attachNavigator(openedPublication: Publication, initialPreferences: Map<String, Any?>?) {
        // commitNow 在 Activity 已經過了 onSaveInstanceState（例如解析完成前使用者恰好把
        // App 切到背景）時會丟出 IllegalStateException；containerId 若因為合成模式改變
        // 等原因無法解析到實際 View（見上方類別註解），也可能丟出 IllegalArgumentException。
        // 兩者都必須攔截並改走 onError，否則例外會發生在 scope.launch 內成為未攔截的
        // 協程例外，導致 Flutter 端卡住或整個 App 崩潰，繞過既有的錯誤回報機制。
        try {
            publication = openedPublication
            val navigatorFactory = EpubNavigatorFactory(publication = openedPublication)
            val fragmentFactory = navigatorFactory.createFragmentFactory(
                initialLocator = null,
                listener = this,
                paginationListener = this,
                configuration = buildFontFamiliesConfiguration(),
            )
            installedFragmentFactory = fragmentFactory
            activity.supportFragmentManager.fragmentFactory = fragmentFactory
            activity.supportFragmentManager.commitNow(allowStateLoss = true) {
                add<EpubNavigatorFragment>(containerId, args = Bundle(), tag = fragmentTag)
            }
            navigatorFragment = activity.supportFragmentManager
                .findFragmentByTag(fragmentTag) as? EpubNavigatorFragment
            if (initialPreferences != null && initialPreferences.isNotEmpty()) {
                currentPreferences = currentPreferences.plus(buildPreferencesFromMap(initialPreferences))
                navigatorFragment?.submitPreferences(currentPreferences)
            }
        } catch (e: Exception) {
            // 掛載失敗時 Fragment 沒有真正附著到任何畫面上，Publication 不會再被使用，
            // 必須主動關閉釋放資源——與 openBook() 中 isDisposed 分支的做法一致。
            publication = null
            openedPublication.close()
            channel.invokeMethod("onError", "掛載 EPUB 閱讀畫面失敗：${e.message}")
        }
    }

    override fun onPageLoaded() {
        if (!pageReported) {
            pageReported = true
            channel.invokeMethod("onPageRendered", null)
            reportLayoutResolved()
        }
        applyFixedLayoutCssInjection()
    }

    private fun findWebView(view: android.view.View): android.webkit.WebView? {
        if (view is android.webkit.WebView) {
            return view
        }
        if (view is android.view.ViewGroup) {
            for (i in 0 until view.childCount) {
                val child = view.getChildAt(i)
                val result = findWebView(child)
                if (result != null) {
                    return result
                }
            }
        }
        return null
    }

    private fun applyFixedLayoutCssInjection() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
        if (!isFixedLayout) return

        val webView = findWebView(this) ?: return
        val js = """
            (function() {
                var style = document.createElement('style');
                style.innerHTML = `
                    html, body {
                        margin: 0 !important;
                        padding: 0 !important;
                        width: 100vw !important;
                        height: 100vh !important;
                        overflow: hidden !important;
                        display: flex !important;
                        justify-content: center !important;
                        align-items: center !important;
                        background-color: transparent !important;
                    }
                    svg, img, iframe {
                        max-width: 100vw !important;
                        max-height: 100vh !important;
                        width: auto !important;
                        height: auto !important;
                        object-fit: contain !important;
                    }
                `;
                document.head.appendChild(style);
            })()
        """.trimIndent()
        webView.post {
            webView.evaluateJavascript(js, null)
        }
    }

    /**
     * 開書完成後一次性回報版面資訊給 Dart 端（見
     * docs/adr/0003-epub-reader-writing-mode-contract.md）：isFixedLayout
     * 讀取 Publication 詮釋資料；writingMode 讀取 Readium 依書本語言／閱讀
     * 方向自動解析出的結果——EpubNavigatorFragment.settings 是已解析完成的
     * StateFlow，直接讀取目前值即可，不需自行呼叫 EpubSettingsResolver。
     */
    private fun reportLayoutResolved() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
        val isVertical = navigatorFragment?.settings?.value?.verticalText ?: false
        channel.invokeMethod(
            "onLayoutResolved",
            mapOf(
                "isFixedLayout" to isFixedLayout,
                "writingMode" to if (isVertical) "vertical" else "horizontal",
            ),
        )
    }

    override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {}

    override fun onExternalLinkActivated(url: AbsoluteUrl) {}

    override fun onResourceLoadFailed(href: Url, error: ReadError) {
        // 起始頁尚未成功渲染前的資源載入失敗才回報 onError；起始頁渲染成功後，使用者
        // 尚未翻到的其他頁面資源失敗不應該讓已經成功的畫面被判定為失敗。
        if (!pageReported) {
            channel.invokeMethod("onError", "頁面資源載入失敗：${error.message}")
        }
    }

    /**
     * [path] 可能是真實檔案系統路徑，也可能是 content:// 或 file:// URI 字串
     * （見 docs/adr/0002-content-uri-reader-contract.md）。含 "://" 者一律
     * 視為 URI，交給 Readium 的 Uri 解析；否則視為檔案系統路徑。
     *
     * 回傳型別為可為 null：`Uri.toAbsoluteUrl()` 本身宣告為 `AbsoluteUrl?`
     * （並非所有合法的 android.net.Uri 都能轉換成 Readium 的 AbsoluteUrl，
     * 例如缺少 scheme 的相對 URI），呼叫端需自行判斷 null 並導向 onError，
     * 與 assetRetriever.retrieve() 的 getOrElse 分支處理方式一致。
     *
     * 已知限制：`contains("://")` 是啟發式判斷，若檔案系統路徑本身恰好含有
     * 這個子字串（例如 `/sdcard/downloads/http://book.epub`）會被誤判為
     * URI 而解析失敗。此啟發式假設路徑皆為 Android 慣例格式，在正常使用情境
     * 下風險可忽略，記錄於此供未來維護者知悉。
     */
    private fun resolveAbsoluteUrl(path: String): AbsoluteUrl? {
        return if (path.contains("://")) {
            Uri.parse(path).toAbsoluteUrl()
        } else {
            File(path).toUrl(isDirectory = false)
        }
    }

    override fun dispose() {
        isDisposed = true
        scope.cancel()
        val fragment = activity.supportFragmentManager.findFragmentByTag(fragmentTag)
        if (fragment != null) {
            try {
                activity.supportFragmentManager.commitNow(allowStateLoss = true) { remove(fragment) }
            } catch (e: Exception) {
                // dispose() 沒有管道能把例外回報給 Flutter（widget 已在銷毀中，channel 的
                // 另一端未必還在聽），也絕不能讓例外從 dispose() 拋出去——那會直接讓
                // Flutter engine 端收到未預期例外。這裡只能盡力清理，失敗就放棄，不重拋。
            }
        }
        // 只有目前的 fragmentFactory 仍是本實例自己安裝的那一個時才還原（identity 比對，
        // 見上方類別註解）；若轉場期間已被另一個 EpubReaderView 覆寫，代表這個 factory
        // 已經不是本實例的責任，不能蓋掉別人還在使用中的設定。
        if (installedFragmentFactory != null &&
            activity.supportFragmentManager.fragmentFactory === installedFragmentFactory
        ) {
            activity.supportFragmentManager.fragmentFactory = previousFragmentFactory
        }
        publication?.close()
        publication = null
        navigatorFragment = null
    }
}
