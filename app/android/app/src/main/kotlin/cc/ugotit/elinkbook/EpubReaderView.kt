package cc.ugotit.elinkbook

import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.webkit.WebView
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
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.css.FontStyle
import org.readium.r2.navigator.epub.css.FontWeight
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.navigator.preferences.Spread
import org.readium.r2.navigator.preferences.TextAlign
import org.readium.r2.shared.publication.Layout
import org.readium.r2.shared.publication.Locator
import org.json.JSONObject
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

    /**
     * 橫向雙頁顯示觸發模式（epic-16-dual-page），對應 Dart DualPageMode 列舉
     * （`app/lib/reader/dual_page_mode.dart`）透過 Method Channel 傳來的
     * `.name` 字串（'auto'／'always'／'never'）。與 PdfReaderView.DualPageMode
     * 是各自獨立的巢狀型別，比照既有慣例（見 PdfReaderView.kt）。
     */
    internal enum class DualPageMode {
        AUTO, ALWAYS, NEVER;

        companion object {
            fun fromWireValue(value: String?): DualPageMode = when (value) {
                "always" -> ALWAYS
                "never" -> NEVER
                else -> AUTO
            }
        }
    }

    companion object {
        /** 雙頁顯示是否應該生效：`always` 一律生效；`auto` 僅橫向生效；`never`
         * 一律不生效。用於決定送給 Readium 的 `Spread` 值（見
         * [buildPreferencesFromMap]），非 Readium API 本身的邏輯。*/
        internal fun isDualPageEnabled(dualPageMode: DualPageMode, isLandscape: Boolean): Boolean =
            dualPageMode == DualPageMode.ALWAYS ||
                (dualPageMode == DualPageMode.AUTO && isLandscape)
    }

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

    /** 雙頁顯示模式（預設 AUTO），由 [applyDualPagePreferences] 更新。 */
    private var dualPageMode: DualPageMode = DualPageMode.AUTO

    /** 裝置是否為橫向，由 [applyDualPagePreferences] 更新。 */
    private var isLandscape: Boolean = false

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
                    call.argument<String>("initialLocatorJson"),
                )
                result.success(null)
            }
            "setPreferences" -> {
                @Suppress("UNCHECKED_CAST")
                setPreferences(call.arguments as? Map<String, Any?>)
                result.success(null)
            }
            "nextPage" -> {
                // 僅供 FXL 三欄熱區使用（見 Dart 端 EpubReaderView.build()）；直接呼叫
                // Readium 既有的 OverflowableNavigator.goForward()，animated=false 避免
                // 觸發滑動動畫——這正是本 issue 要繞開的「揭露未縮放內容的可見時間窗口」
                // （見 docs/epics/epic-16-dual-page/issues.md Issue 9）。EpubNavigatorFragment
                // 已實作 OverflowableNavigator，不需要自己重新判斷 spread 要跳幾頁。
                navigatorFragment?.goForward(animated = false)
                result.success(null)
            }
            "previousPage" -> {
                navigatorFragment?.goBackward(animated = false)
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
        applyDualPagePreferences(preferences)
        currentPreferences = currentPreferences.plus(buildPreferencesFromMap(preferences))
        navigatorFragment?.submitPreferences(currentPreferences)
        applyFontWeightCascade()
    }

    /**
     * 解析 [preferences] 中的 dualPageMode／isLandscape 欄位並更新對應欄位；
     * 任一欄位實際改變時使 FXL 縮放快取失效——單頁/雙頁切換或裝置旋轉時，
     * container 可用寬度的計算基準（見 applyFxlFitScale()）都會改變，沿用舊的
     * 快取值會算錯縮放比例。必須在 [buildPreferencesFromMap] 之前呼叫（後者會
     * 讀取剛更新的 dualPageMode／isLandscape 欄位來計算 spread）。
     */
    private fun applyDualPagePreferences(preferences: Map<String, Any?>) {
        var changed = false
        (preferences["dualPageMode"] as? String)?.let {
            val newValue = DualPageMode.fromWireValue(it)
            if (newValue != dualPageMode) changed = true
            dualPageMode = newValue
        }
        (preferences["isLandscape"] as? Boolean)?.let {
            if (it != isLandscape) changed = true
            isLandscape = it
        }
        if (changed) {
            cachedFxlFitScale = null
            cachedFxlFitScaleIsSpread = null
        }
    }

    /**
     * 在 View 樹中尋找所有符合型別 [T] 的 View（深度優先，回傳全部相符項目、
     * 不是只有第一個）。用於直接存取 Readium Fragment 內部、未透過
     * EpubNavigatorFragment 公開 API 暴露的原生元件（WebView），見
     * [applyFontWeightCascade]／[applyFxlFitScale] 的說明。
     *
     * 【為什麼是「全部」而不是「第一個」】真機驗證發現分頁書籍（不論固定版面或
     * 流動式）在 Readium 的 `R2ViewPager` 內部同時保留了目前頁的前後相鄰頁面（
     * `adb shell dumpsys activity --view-hierarchy` 確認同時存在 3 個
     * `R2BasicWebView` 實例，各自的 `R2FXLLayout` 父容器以左右並排、透過父層
     * ViewPager 位移捲動決定哪一個落在可視範圍內），單純找「View 樹中第一個
     * WebView」不保證是目前實際顯示的那一頁——這正是先前版本「有些頁面縮放
     * 正確、有些頁面完全沒套用」的根因。改成對「找到的每一個 WebView」都套用
     * 同一套邏輯（各自依自己的量測高度計算縮放比／各自注入 CSS），不論最終
     * 哪一個落在可視範圍內都已經處理過，不需要额外判斷「目前是哪一個」。
     * 實際遞迴委派給 [findViewsByClass]——reified inline function 不能直接
     * 遞迴呼叫自己。
     */
    private inline fun <reified T : View> findViewsByType(view: View): List<T> {
        val result = mutableListOf<View>()
        findViewsByClass(view, T::class.java, result)
        @Suppress("UNCHECKED_CAST")
        return result as List<T>
    }

    private fun findViewsByClass(view: View, clazz: Class<*>, result: MutableList<View>) {
        if (clazz.isInstance(view)) {
            result.add(view)
        }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findViewsByClass(view.getChildAt(i), clazz, result)
            }
        }
    }

    /**
     * 補強 Readium `EpubPreferences.fontWeight` 的已知缺口（見 /diagnose 對
     * readium-navigator:3.3.0 的反編譯分析）：Readium 內建機制只把換算後的
     * CSS `font-weight` 值設在 `<html>` 上（透過 inline style + `!important`），
     * 但 ReadiumCSS 本身沒有像 `--USER__fontSize` 那樣，提供一條把數值強制
     * 往下蓋到 `p`/`div`/`li` 等實際內文元素的規則——導致只要書本自己的 CSS
     * 對段落/標題有任何 `font-weight` 宣告（非常常見），就會直接蓋掉 `<html>`
     * 繼承下來的值，使用者看不到效果。這裡改用我們自己注入的 `<style>`
     * 直接以 `!important` 強制蓋到常見文字元素，僅在 `currentPreferences`
     * 有非 null 的 fontWeight 時才注入，未設定時移除先前注入的規則（避免殘留
     * 影響下一本沒有覆寫字重的書）。
     *
     * 【對「所有」WebView 套用，不是只有第一個】見 [findViewsByType] 說明——
     * Readium 的 `R2ViewPager` 會同時保留目前頁前後相鄰的頁面，各自都是獨立的
     * WebView 實例；只處理「View 樹中第一個 WebView」不保證涵蓋到使用者實際
     * 翻到、正在看的那一頁。
     */
    private fun applyFontWeightCascade() {
        val webViews = findViewsByType<WebView>(container)
        if (webViews.isEmpty()) return
        val fontWeight = currentPreferences.fontWeight
        val js = if (fontWeight != null) {
            val cssValue = (fontWeight * 400).coerceIn(1.0, 1000.0).toInt()
            """
            (function() {
                var style = document.getElementById('elinkbook-font-weight-cascade');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'elinkbook-font-weight-cascade';
                    document.head.appendChild(style);
                }
                style.textContent = 'body, p, div, li, span, td, th, blockquote, dd, dt, a, h1, h2, h3, h4, h5, h6 { font-weight: $cssValue !important; }';
            })();
            """.trimIndent()
        } else {
            """
            (function() {
                var style = document.getElementById('elinkbook-font-weight-cascade');
                if (style) style.remove();
            })();
            """.trimIndent()
        }
        webViews.forEach { webView -> webView.post { webView.evaluateJavascript(js, null) } }
    }

    /**
     * 補強固定版面（漫畫）內容仍會被系統列裁切、橫放更嚴重、不會自動縮放的問題
     * （見 /diagnose 對 readium-navigator:3.3.0 內建
     * `readium_navigator_fragment_fxllayout_single.xml`/`_double.xml` 原始碼的
     * 分析）：該版面把 WebView 設為 `layout_height="wrap_content"`，寬度以
     * `layout_weight` 對齊可用寬度，但高度只依內容本身的天然比例撐開，完全不管
     * 外層容器（已正確扣除狀態列/Taskbar）實際還剩多少高度可用——多出來的部分
     * 由外層 ScrollView 吸收成可捲動區域，而非縮小內容去符合可視範圍，因此畫面
     * 靜止時看起來就像被裁掉一截。
     *
     * Readium 官方提供 `R2FXLLayout`（本身有 `setScale()` 手勢縮放 API）包著這個
     * WebView，理論上是更「正規」的縮放入口，但該類別在 Kotlin 模組層級宣告為
     * internal（javap 看到的 `public` 只是 JVM bytecode 層級的可見度，不代表
     * Kotlin 原始碼開放給外部模組引用），我們無法在自己的模組直接參照該型別、
     * 也不方便用反射硬呼叫其 internal API。改用 `android.view.View` 本身就有的
     * `scaleX`/`scaleY`/`pivotX`/`pivotY` 屬性直接對 WebView 做等比縮放——這是
     * View 基底類別的公開屬性，不受 Readium 內部可見度限制，純視覺變形，不影響
     * WebView 自身的版面/捲動狀態。以 [container]（Flutter 已正確給定、扣除
     * 系統列的真實容器）的高度作為縮放基準，而非嘗試存取 R2FXLLayout 的高度。
     *
     * 【殘留裁切與旋轉不重算的後續修正】真機驗證發現只套用一次（`onPageLoaded()`
     * 當下）不夠：
     * 1. 套用當下畫面仍殘留一小截裁切——不是縮放計算本身的四捨五入誤差（那頂多
     *    是次像素等級，不會有肉眼可見的裁切），而是時機問題：`onPageLoaded()`
     *    觸發時，WebView `wrap_content` 高度不保證已經完全撐開到最終值（內部
     *    圖片解碼/reflow 可能還在進行），當下讀到的高度偏小，算出來的縮放比例
     *    就會偏大（縮得不夠）。
     * 2. 旋轉裝置後畫面沒有重新縮放——`MainActivity` 宣告了
     *    `configChanges="orientation|screenSize|..."`，旋轉不會重建 Activity／
     *    Fragment，`onPageLoaded()` 不會再次觸發，先前算好的縮放比例是舊方向的
     *    數值，套用在新方向的 WebView 天然高度上就會算錯。
     *
     * 兩者的共同解法是「持續監聽版面真正改變的時機、每次都重新計算」，而不是
     * 「賭一個固定時間點」。改用 `container`（穩定存在、不隨翻頁重建）的
     * `ViewTreeObserver.OnGlobalLayoutListener`：只要 View 樹的量測/版面發生變化
     * 就會觸發（包含旋轉造成 `container` 尺寸改變、WebView 內容延遲撐高、換頁
     * 換成新的 WebView 實例等），每次觸發都重新尋找目前的 WebView 並重新計算——
     * `scaleX`/`scaleY` 只是繪製階段變形、不會觸發新的 layout pass，不會造成
     * listener 自我觸發的無限迴圈。監聽器在 [dispose] 中移除。
     *
     * 【第三輪修正：同時存在多個 WebView】真機用
     * `adb shell dumpsys activity --view-hierarchy` 檢查發現：Readium 的
     * `R2ViewPager` 會同時保留目前頁的前後相鄰頁面，各自是獨立的
     * `R2FXLLayout`／`R2BasicWebView` 實例（並排放在同一個橫向捲動的內部容器
     * 裡，由 ViewPager 本身位移決定哪一個落在可視範圍）——先前版本用
     * `findViewByType`（單數、只回傳第一個）只會處理到 View 樹裡排序最前面的
     * 那一個，翻到的頁面若不是那一個就完全沒被縮放，正好對應「有些頁沒問題、
     * 翻到第 7-9 頁又出現裁切」的隨機性。改用 [findViewsByType]（複數）對
     * *每一個* 找到的 WebView 個別計算並套用縮放，不論最終哪一個落在可視範圍
     * 內都已經處理過。
     *
     * 【第四輪修正：pivot 沒有校正 Readium 既有的置中位移】真機測試某些頁面
     * 改用 `pivotX=width/2, pivotY=0` 縮放後，畫面變成頂端被裁切、底部反而多出
     * 一截空白——用 `adb shell dumpsys activity --view-hierarchy` 檢查發現，
     * Readium 內建 XML（`RelativeLayout` 包 `LinearLayout[layout_centerInParent]`
     * 包 WebView）本身就會依內容高度把 WebView 在 `RelativeLayout` 內垂直置中，
     * 因此 WebView 進入這個函式時，量測到的 `top` 早就不是 0——可能已經是負值
     * （這一頁的天然高度比 `RelativeLayout` 的可用高度更高，置中後往上位移）。
     * `pivotY=0` 是以 WebView *自己* 的（已經帶著這個位移的）左上角為錨點縮放，
     * 縮放後那個位移仍原封不動地保留在畫面上，导致縮小後的內容仍然頂端出畫面、
     * 底部反而空出「被吃掉的縮放比例」。
     *
     * 改成不依賴 pivot 的相對位移語意，而是直接用 `getLocationOnScreen()` 量出
     * WebView 與 [container] 目前實際的螢幕座標差，反推出「要讓縮放後的內容
     * 剛好水平和垂直置中在 container 裡」所需要的 `translationX`/`translationY`
     * 補償值——不論 Readium 自己的置中邏輯把 WebView 的原始 layout 位置擺在哪裡，
     * 都能算出正確的最終位置，不必去猜測/校正它的內部位移規則。
     */
    private var fxlLayoutListener: ViewTreeObserver.OnGlobalLayoutListener? = null

    /**
     * 整本固定版面書籍統一套用的縮放比例，只在第一次成功量到有效頁面尺寸時計算，
     * 之後同一本書所有頁面一律沿用這個值，不再每頁各自重算（見 Issue 10）。
     *
     * 真機用 `葬送的芙莉蓮 11.epub`（192 頁）搭配除錯日誌逐頁比對確認：绝大多數
     * 頁面的 XHTML `<meta name="viewport">` 宣告一致為 `height=1600`，但 p-185／
     * p-186 這兩頁的來源檔案本身宣告的是 `height=1606`（高了 6px）；若各頁各自
     * 依「這一頁量到的實際內容高度」獨立計算 `fitScale`，這兩頁會因為內容比其他
     * 頁「稍高」而被多縮一點（`0.93112` vs 其餘頁面的 `0.93461`），使用者翻到那
     * 兩頁時會感覺畫面明顯變小——縮放計算本身沒有錯，是來源檔案裡少數頁面宣告
     * 尺寸與全書不一致所致。改為整本書統一套用第一頁量到的縮放比例，讓少數頁面
     * 的宣告尺寸誤差不會反映成翻頁時的縮放跳動。
     */
    private var cachedFxlFitScale: Float? = null
    private var cachedFxlFitScaleIsSpread: Boolean? = null

    private fun applyFxlFitScale() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
        if (!isFixedLayout) {
            removeFxlLayoutListener()
            return
        }
        if (fxlLayoutListener != null) return
        val listener = ViewTreeObserver.OnGlobalLayoutListener {
            val allWebViews = findViewsByType<WebView>(container)
            // R2ViewPager 在單頁模式下也會同時保留前後相鄰頁面的 WebView（見本
            // 檔案類別 KDoc「為什麼是『全部』而不是『第一個』」，真機驗證確認
            // 同時存在 3 個 R2BasicWebView 實例，各自的 R2FXLLayout 以左右並排、
            // 由 ViewPager 位移決定哪一個落在可視範圍內）。量測「目前是否為雙頁
            // 並排」之前，先把所有找到的 WebView 的 translationX/Y 歸零——若不
            // 歸零，getLocationOnScreen() 量到的會是「上一輪計算殘留的位移」而非
            // 真正的原始 layout 位置，污染下面的可見性判斷與排序（pivot 固定為
            // (0,0) 時 scale 不影響量測到的左上角座標，只有 translationX/Y 需要
            // 歸零，不需要在這裡連 scale 也重置）。
            allWebViews.forEach {
                it.translationX = 0f
                it.translationY = 0f
            }
            val containerLoc = IntArray(2)
            container.getLocationOnScreen(containerLoc)

            // 只用「找到的 WebView 數量」判斷雙頁狀態會被 R2ViewPager 預載在
            // 螢幕外的相鄰頁面誤導（單頁模式下常態就有 3 個）。改為兩個條件都
            // 成立才視為雙頁並排：(1) 偏好設定本身啟用雙頁（isDualPageEnabled，
            // 排除「單頁模式下巧合抓到 ≥2 個螢幕外 WebView」的誤判），(2) 篩選出
            // 真正落在 container 可視範圍內的 WebView 且數量 ≥ 2（排除「雙頁
            // 偏好生效但目前停在封面頁（page: center），Readium 本身只給 1 個
            // WebView」的情況）。可見性篩選後依 x 座標由小到大排序，用排序後的
            // index 判斷左右 slot，而非數值閾值比較（過渡瞬間的量測誤差可能讓
            // 閾值判斷失準，見審查意見 Important #1）。
            val visibleWebViews = allWebViews.filter { webView ->
                val webViewLoc = IntArray(2)
                webView.getLocationOnScreen(webViewLoc)
                val currentLeft = webViewLoc[0] - containerLoc[0]
                val contentWidth = webView.width
                contentWidth > 0 && currentLeft + contentWidth > 0 && currentLeft < container.width
            }.sortedBy { webView ->
                val webViewLoc = IntArray(2)
                webView.getLocationOnScreen(webViewLoc)
                webViewLoc[0]
            }
            val isDualPageActive = isDualPageEnabled(dualPageMode, isLandscape)
            val isSpread = isDualPageActive && visibleWebViews.size >= 2
            if (cachedFxlFitScaleIsSpread != isSpread) {
                cachedFxlFitScale = null
                cachedFxlFitScaleIsSpread = isSpread
            }
            val availableWidth = if (isSpread) container.width / 2 else container.width
            val availableHeight = container.height
            if (availableWidth <= 0 || availableHeight <= 0) return@OnGlobalLayoutListener

            visibleWebViews.forEachIndexed { index, webView ->
                val contentWidth = webView.width
                val contentHeight = webView.height
                if (contentWidth <= 0 || contentHeight <= 0) return@forEachIndexed
                val fitScale = cachedFxlFitScale ?: EpubFxlScaler.computeFitScale(
                    availableWidth = availableWidth,
                    availableHeight = availableHeight,
                    contentWidth = contentWidth,
                    contentHeight = contentHeight,
                ).also { cachedFxlFitScale = it }

                webView.pivotX = 0f
                webView.pivotY = 0f
                webView.scaleX = fitScale
                webView.scaleY = fitScale
                val webViewLoc = IntArray(2)
                webView.getLocationOnScreen(webViewLoc)
                val currentLeft = (webViewLoc[0] - containerLoc[0]).toFloat()
                val currentTop = (webViewLoc[1] - containerLoc[1]).toFloat()

                // 雙頁模式下，右側 WebView 的置中運算必須在「它自己的半寬 slot」
                // 座標系裡進行，否則 computeCenteringTranslation 會把它往 slot 0
                // （螢幕左半邊）置中。做法：換算前先把 currentLeft 減去 slot 起點
                // （0 或 availableWidth），讓函式誤以為自己是在 slot 內部（座標
                // 原點在 slot 起點）計算——回傳值 translation.x = desiredLeft（相對
                // slot 起點）- 傳入的 currentLeft（已扣掉 slot 起點），展開後等於
                // 「絕對期望位置 - 原始 currentLeft」，本來就已經是可以直接疊加在
                // 原始位置上的正確絕對位移，不能再額外加回 slotOffsetX（那樣會把
                // 右側 WebView 多平移一個 slot 寬度、直接推出可視範圍外——這正是
                // 真機測試發現「翻頁後右側內容消失」的根因，見
                // docs/epics/epic-16-dual-page/plans/plan-issue-6.md 審查修正
                // 紀錄之後的 bugfix 說明）。slot 依排序後的 index 分配（index 0 =
                // 左，1 = 右），不使用數值閾值判斷。
                val slotOffsetX = if (isSpread && index == 1) availableWidth.toFloat() else 0f

                val translation = EpubFxlScaler.computeCenteringTranslation(
                    availableWidth = availableWidth,
                    availableHeight = availableHeight,
                    contentWidth = contentWidth,
                    contentHeight = contentHeight,
                    scale = fitScale,
                    currentLeft = currentLeft - slotOffsetX,
                    currentTop = currentTop,
                )
                webView.translationX = translation.x
                webView.translationY = translation.y
            }
        }
        fxlLayoutListener = listener
        container.viewTreeObserver.addOnGlobalLayoutListener(listener)
    }

    private fun removeFxlLayoutListener() {
        fxlLayoutListener?.let { container.viewTreeObserver.removeOnGlobalLayoutListener(it) }
        fxlLayoutListener = null
        cachedFxlFitScale = null
        cachedFxlFitScaleIsSpread = null
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
            spread = if (isDualPageEnabled(dualPageMode, isLandscape)) Spread.ALWAYS else Spread.NEVER,
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
     *
     * 【單一靜態字重字型的模擬粗體】見 /diagnose 分析：原俠正楷／台灣圓體／
     * 源流明體這 3 款字型檔案本身只有一種字重，不像思源黑體/宋體（`-VF` 結尾，
     * 真正的 Variable Font）能真的變粗。若對這 3 款也額外註冊一個指向同一份
     * 檔案的 `FontWeight.BOLD` face，瀏覽器會誤以為「已經有對應這個字重的正確
     * 字面」而**抑制**其內建的模擬粗體（synthetic bold）合成——等於字重滑桿對
     * 這 3 款完全沒有視覺效果。因此只對 [variableWeightFamilies] 中的真變數
     * 字型註冊 NORMAL+BOLD 兩個 face；其餘單一靜態字重字型只註冊一個 face，
     * 讓瀏覽器預設的 `font-synthesis` 在字重滑桿要求較粗的值時，自動套用模擬
     * 粗體。
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
        val variableWeightFamilies = setOf("SourceHanSansTC", "SourceHanSerifTC")
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
                    if (familyName in variableWeightFamilies) {
                        addFontFace {
                            addSource(lookupKey, preload = true)
                            setFontStyle(FontStyle.NORMAL)
                            setFontWeight(FontWeight.BOLD)
                        }
                    }
                }
            }
        }
    }

    private fun openBook(
        path: String?,
        initialPreferences: Map<String, Any?>?,
        initialLocatorJson: String?,
    ) {
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
                attachNavigator(openedPublication, initialPreferences, initialLocatorJson)
            } catch (e: Exception) {
                channel.invokeMethod("onError", "開啟 EPUB 檔案時發生未預期的錯誤：${e.message}")
            }
        }
    }

    private fun attachNavigator(
        openedPublication: Publication,
        initialPreferences: Map<String, Any?>?,
        initialLocatorJson: String?,
    ) {
        // commitNow 在 Activity 已經過了 onSaveInstanceState（例如解析完成前使用者恰好把
        // App 切到背景）時會丟出 IllegalStateException；containerId 若因為合成模式改變
        // 等原因無法解析到實際 View（見上方類別註解），也可能丟出 IllegalArgumentException。
        // 兩者都必須攔截並改走 onError，否則例外會發生在 scope.launch 內成為未攔截的
        // 協程例外，導致 Flutter 端卡住或整個 App 崩潰，繞過既有的錯誤回報機制。
        try {
            publication = openedPublication
            val navigatorFactory = EpubNavigatorFactory(publication = openedPublication)
            val initialLocator = initialLocatorJson?.let {
                Locator.fromJSON(JSONObject(it))
            }
            val fragmentFactory = navigatorFactory.createFragmentFactory(
                initialLocator = initialLocator,
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
            // 訂閱 currentLocator StateFlow（Navigator 介面的公開屬性），取代
            // PaginationListener.onPageChanged 作為 onLocatorChanged 的觸發來源
            // ——後者在 FXL（固定版面）書籍中不會被呼叫（Readium 內部的
            // notifyCurrentLocation() 在 FXL 頁面時 currentReflowablePageFragment
            // 為 null，會跳過 onPageChanged 呼叫），但 currentLocator 在
            // _currentLocator.setValue() 之後無條件更新，不論 FXL 或 reflowable
            // 都能正確取得最新定位（本審查修正不再覆寫 onPageChanged——interface
            // 對它有 default no-op 實作，不覆寫也能合法實作 PaginationListener）。
            //
            // 【審查修正】此處刻意不再從這裡手動呼叫 onPageLoaded()——onPageLoaded
            // 是 PaginationListener 的另一個方法，由 Readium 在每個 WebView 各自
            // 載入完成時各別呼叫（見下方 override fun onPageLoaded()），對 FXL
            // 頁面本來就會正確觸發，不受 currentReflowablePageFragment 為 null
            // 的限制（FXL 頁面內部本來就用 WebView 渲染，只是走 R2FXLPageFragment
            // 而非 R2EpubPageFragment）。先前在此手動呼叫 onPageLoaded() 會把它的
            // 觸發時機從「每個 WebView 各自載入完成」改成「currentLocator 這個
            // 經過 100ms debounce、以定位變動為單位的訊號」，導致 applyFxlFitScale()
            // 依賴的首次量測時機被打亂，造成橫排雙頁 FXL 版面計算錯誤（中間空白、
            // 頁序顛倒）。onLocatorChanged 的推送與 onPageLoaded() 是兩個獨立的
            // 訊號來源，不需要綁在一起觸發。
            navigatorFragment?.currentLocator
                ?.onEach { locator ->
                    channel.invokeMethod(
                        "onLocatorChanged",
                        mapOf(
                            "locatorJson" to locator.toJSON().toString(),
                            "progression" to locator.locations.totalProgression,
                        ),
                    )
                }
                ?.launchIn(scope)
            if (initialPreferences != null && initialPreferences.isNotEmpty()) {
                applyDualPagePreferences(initialPreferences)
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

    /**
     * epic-5-toc-pagination Issue 2 審查修正：恢復為 PaginationListener 的
     * override（原本一度被改成手動呼叫的 private 函式，見上方 attachNavigator()
     * 內的說明）。Readium 對每個 WebView（含 FXL 頁面內部的 WebView）各自載入
     * 完成時都會呼叫本方法，不受「currentReflowablePageFragment 為 null」的
     * FXL 限制影響（那個限制只影響 onPageChanged，見 PaginationListener 介面
     * 說明）。
     */
    override fun onPageLoaded() {
        if (!pageReported) {
            pageReported = true
            channel.invokeMethod("onPageRendered", null)
            reportLayoutResolved()
        }
        applyFontWeightCascade()
        applyFxlFitScale()
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
        removeFxlLayoutListener()
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
