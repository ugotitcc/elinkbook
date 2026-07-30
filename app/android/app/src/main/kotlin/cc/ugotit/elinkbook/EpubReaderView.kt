package cc.ugotit.elinkbook

import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.view.ActionMode
import android.view.Menu
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
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt
import org.readium.r2.navigator.DecorableNavigator
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.Selection
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.css.FontStyle
import org.readium.r2.navigator.epub.css.FontWeight
import org.readium.r2.navigator.html.HtmlDecorationTemplates
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.navigator.preferences.Spread
import org.readium.r2.navigator.preferences.TextAlign
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.navigator.util.BaseActionModeCallback
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Layout
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.json.JSONObject
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.ReadingProgression
import org.readium.r2.shared.publication.services.positions
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

    /**
     * 3×3 導航熱區動作（epic-7-interaction design.md 決策 #8），對應 Dart
     * `ZoneAction` 列舉（app/lib/reader/zone_action.dart）透過 Method Channel
     * 傳來的 `.name` 字串（'previousPage'/'nextPage'/'menu'/'none'）。與
     * [DualPageMode] 是各自獨立的巢狀型別，比照既有慣例。
     */
    internal enum class ZoneAction {
        PREVIOUS_PAGE, NEXT_PAGE, MENU, NONE;

        companion object {
            fun fromWireValue(value: String?): ZoneAction = when (value) {
                "previousPage" -> PREVIOUS_PAGE
                "nextPage" -> NEXT_PAGE
                "menu" -> MENU
                else -> NONE
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

        /** applyDecorations／addDecorationListener 使用的群組鍵，任取一個
         * 在整個 App 內唯一的字串即可，不需要與其他任何既有機制對應。*/
        internal const val ANNOTATIONS_DECORATION_GROUP = "elinkbook_annotations"
    }

    private val containerId = View.generateViewId()
    private val container = FrameLayout(context).apply { this.id = containerId }
    private val channel = MethodChannel(messenger, "cc.ugotit.elinkbook/epub_reader_view_$id")
    private val fragmentTag = "cc.ugotit.elinkbook.epub_reader_view_$id"
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val previousFragmentFactory = activity.supportFragmentManager.fragmentFactory
    private var installedFragmentFactory: FragmentFactory? = null
    private var publication: Publication? = null
    // 修復 Issue 16：Readium 官方元件 EpubNavigatorFragment 會獨立重新讀取
    // Publication.metadata.layout 決定渲染模式，不受本專案 publication 欄位
    // 影響（見 docs/adr/0016-fxl-metadata-override-via-publication-builder.md）。
    // effectivePublication 是傳給 EpubNavigatorFactory／FXL 判斷檢查點使用的
    // 物件；publication 欄位維持指向原始物件，確保 jumpToProgression()／
    // buildTocPayloadSafely()／computeTotalCharacterCountInBackground() 等既有
    // 呼叫端維持使用完整服務。
    private var effectivePublication: Publication? = null
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

    /**
     * 3×3 導航熱區動作對照表（epic-7-interaction Issue 6），由
     * [buildPreferencesFromMap] 解析 Dart 端送來的 `navZoneActions` 字串陣列
     * 更新此欄位，供僅流式（`isFixedLayout == false`）路徑註冊的
     * `InputListener.onTap()` 查表使用。預設全部 [ZoneAction.NONE]——尚未
     * 收到任何偏好設定時的安全預設，不會誤觸發任何動作。
     */
    private var navZoneActions: List<ZoneAction> = List(9) { ZoneAction.NONE }

    /** [attachNavigator] 註冊的熱區點擊監聽器，dispose() 時需要用同一個實例
     * 呼叫 removeInputListener，故保留參照——比照下方 [decorationListener]
     * 既有慣例。僅流式（`isFixedLayout == false`）路徑會賦值。 */
    private var navInputListener: InputListener? = null

    /** 標記點擊監聽器，dispose() 時需要用同一個實例呼叫
     * removeDecorationListener，故保留參照（見 Decoration.kt
     * addDecorationListener／removeDecorationListener 簽章）。*/
    private var decorationListener: DecorableNavigator.Listener? = null

    init {
        channel.setMethodCallHandler(this)
        ReaderViewAttachmentTracker.attach()
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
                    call.argument<Int>("totalCharacterCount"),
                )
                result.success(null)
            }
            "setPreferences" -> {
                @Suppress("UNCHECKED_CAST")
                setPreferences(call.arguments as? Map<String, Any?>)
                result.success(null)
            }
            "nextPage" -> {
                // 原僅供 FXL 三欄熱區使用（見 Dart 端 EpubReaderView.build()），現
                // epic-7-interaction Issue 7 音量鍵翻頁讓所有 EPUB 格式（含流式）
                // 共用同一條路徑——見 EpubReaderView._handleZoneAction() → Dart
                // static helper nextPage()/previousPage() → 此 method channel case。
                // 直接呼叫 Readium 既有的 OverflowableNavigator.goForward()，
                // animated=false 避免觸發滑動動畫——這正是本 issue 要繞開的「揭露
                // 未縮放內容的可見時間窗口」（見 docs/epics/epic-16-dual-page/issues.md
                // Issue 9）。EpubNavigatorFragment 已實作 OverflowableNavigator，
                // 不需要自己重新判斷 spread 要跳幾頁。
                navigatorFragment?.goForward(animated = false)
                result.success(null)
            }
            "previousPage" -> {
                navigatorFragment?.goBackward(animated = false)
                result.success(null)
            }
            "jumpToProgression" -> {
                val progression = call.argument<Double>("progression")
                if (progression != null) {
                    jumpToProgression(progression)
                }
                result.success(null)
            }
            "getTableOfContents" -> {
                scope.launch(Dispatchers.IO) {
                    val toc = buildTocPayloadSafely()
                    withContext(Dispatchers.Main) {
                        // 審查修正：比照 computeTotalCharacterCountInBackground()／
                        // jumpToProgression() 既有的 isDisposed 防護慣例——協程
                        // 完成前 View 若已被銷毀，不應再呼叫 result.success()。
                        if (!isDisposed) result.success(toc)
                    }
                }
            }
            "jumpToLocator" -> {
                val locatorJson = call.argument<String>("locatorJson")
                if (locatorJson != null) {
                    try {
                        val locator = Locator.fromJSON(JSONObject(locatorJson))
                        // fromJSON 回傳 Locator?，null 時靜默忽略（JSON 格式
                        // 缺少必要欄位）——比照本檔案既有對非致命錯誤的處理原則。
                        if (locator != null) {
                            navigatorFragment?.go(locator, animated = false)
                        }
                    } catch (e: Exception) {
                        // 無效的 locatorJson（例如 JSON 格式錯誤）靜默忽略，
                        // 比照本檔案既有對非致命錯誤的處理原則——目錄跳轉
                        // 失敗不應該讓已成功開啟的書籍畫面顯示錯誤。
                    }
                }
                result.success(null)
            }
            "setDecorations" -> {
                @Suppress("UNCHECKED_CAST")
                val list = call.argument<List<Map<String, Any?>>>("decorations") ?: emptyList()
                scope.launch {
                    applyDecorationsFromWire(list)
                    if (!isDisposed) result.success(null)
                }
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
        val isFixedLayout = effectivePublication?.metadata?.layout == Layout.FIXED
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

                // 【頁序修正，實驗性】Readium 對 FXL 雙頁的原生排版（R2FXLPageFragment
                // 的 firstWebView/secondWebView 綁定）完全不考慮書籍宣告的
                // page-progression-direction：無論書籍是 RTL 或 LTR，「較早的頁面」
                // 一律綁定 firstWebView、physically 落在螢幕左側（已用 javap 反編譯
                // EpubNavigatorFragment 的頁面配對迴圈、R2PagerAdapter.getItem()、
                // R2FXLPageFragment.Companion.newInstance()／onCreateView() 逐層確認，
                // 全程沒有任何 ReadingProgression 判斷）。對 RTL 漫畫（較早的頁面應
                // 讀者「先看到」、也就是應該落在螢幕右側）而言，這會讓雙頁順序視覺上
                // 反過來。我們自己的排序邏輯（visibleWebViews.sortedBy { x 座標 }）
                // 只是「觀察」Android 實際排出來的物理位置，並不能改變 Readium 的原生
                // 綁定，所以真正的修正點在這裡：不要直接用 sortedBy 產生的 index 決定
                // 視覺上要放哪一個 slot，而是在 RTL 時反轉——把 index 0（物理最左、
                // Readium 認定的「較早頁面」）透過 translationX 直接搬到螢幕右半的
                // slot，反之亦然。
                val isRtl = publication?.metadata?.readingProgression == ReadingProgression.RTL
                val visualSlot = if (isSpread && isRtl) 1 - index else index

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
                // 紀錄之後的 bugfix 說明）。slot 依 [visualSlot] 分配（0 = 左，
                // 1 = 右），不使用數值閾值判斷。
                val slotOffsetX = if (isSpread && visualSlot == 1) availableWidth.toFloat() else 0f

                if (isSpread) {
                    // 【中縫空白修正，實驗性】雙頁模式下不使用 EpubFxlScaler.computeCenteringTranslation
                    // 的「各自獨立置中」語意——那會讓左頁向左、右頁向右各自留出對稱邊界，
                    // 兩者加總在螢幕中線處形成一道明顯的空白縫隙。改為讓兩頁貼齊中線（book
                    // spine）：左側 slot（visualSlot 0）貼右邊界（緊靠中線），右側 slot
                    // （visualSlot 1）貼左邊界（緊靠中線），垂直方向仍維持置中。currentLeft
                    // 已在傳入前扣除 slotOffsetX（見上方既有註解），所以這裡的 desiredLeft
                    // 是「相對各自 slot 起點」的目標位置，與既有的 slotOffsetX 扣除邏輯相容。
                    val scaledWidth = contentWidth * fitScale
                    val scaledHeight = contentHeight * fitScale
                    val desiredLeft = if (visualSlot == 0) availableWidth - scaledWidth else 0f
                    val desiredTop = (availableHeight - scaledHeight) / 2f
                    webView.translationX = desiredLeft - (currentLeft - slotOffsetX)
                    webView.translationY = desiredTop - currentTop
                } else {
                    val translation = EpubFxlScaler.computeCenteringTranslation(
                        availableWidth = availableWidth,
                        availableHeight = availableHeight,
                        contentWidth = contentWidth,
                        contentHeight = contentHeight,
                        scale = fitScale,
                        currentLeft = currentLeft,
                        currentTop = currentTop,
                    )
                    webView.translationX = translation.x
                    webView.translationY = translation.y
                }
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
     * 攔截 Readium 原生選字工具列（epic-6-annotations Issue 2，design.md
     * 決策：改由 Flutter 端 `AnnotationToolbar` 接手顯示浮動工具列）。
     *
     * 【審查修正，重要】`onCreateActionMode` 必須回傳 `true`，**不能**回傳
     * `false`——這是 Android `ActionMode.Callback` 官方文件明訂的契約：
     * 回傳 `false` 代表整個 ActionMode 生命週期直接不建立，其後
     * `onDestroyActionMode` 也「不會」被呼叫（非 Readium 特有行為，是
     * Android SDK 本身的標準行為）。若回傳 `false`，`onSelectionCleared`
     * 事件永遠不會送出，Flutter 端浮動工具列會卡在畫面上收不起來。改為
     * 回傳 `true`（讓 ActionMode 正常建立、生命週期正常運作），並在
     * `menu?.clear()` 清空選單項目，讓原生 Cut/Copy/Share 等按鈕不會
     * 顯示——視覺效果與原本「不顯示原生選單」的意圖相同，但透過清空選單
     * 內容達成，而非跳過整個生命週期。
     *
     * 同時在 `onCreateActionMode` 當下呼叫 `currentSelection()`
     * （suspend）取得選取範圍的 Locator／矩形，回報給 Dart 端。
     *
     * `onDestroyActionMode` 現在能正常在使用者點擊選取範圍以外的地方
     * （原生選取被清除）時觸發，通知 Dart 端收起浮動工具列。先呼叫
     * `super.onDestroyActionMode()`——`BaseActionModeCallback` 本身可能有
     * Readium 內部需要的清理邏輯，本類別只是附加通知，不取代它。
     */
    private inner class SelectionActionModeCallback : BaseActionModeCallback() {
        override fun onCreateActionMode(mode: ActionMode?, menu: Menu?): Boolean {
            menu?.clear()
            scope.launch {
                val selection = navigatorFragment?.currentSelection() ?: return@launch
                if (!isDisposed) reportSelectionChanged(selection)
            }
            return true
        }

        override fun onDestroyActionMode(mode: ActionMode) {
            super.onDestroyActionMode(mode)
            if (!isDisposed) channel.invokeMethod("onSelectionCleared", null)
        }
    }

    /**
     * 把 [selection] 換算成相對於 [container] 寬高的百分比矩形送給 Dart
     * 端（見 Global Constraints「選取矩形座標協定」）。流式 EPUB
     * （本 Issue 範圍，FXL 排除）不像 `applyFxlFitScale()` 那樣對 WebView
     * 做額外縮放/位移變換，故 `Selection.rect` 可視為已經是相對
     * [container] 座標系的量測結果，不需要額外的座標轉換——此假設留待
     * Task 11 真機測試驗證（見 issues.md 驗收標準）。
     *
     * 【Task 9 實作階段審查修正】`Selection.rect` 的 Kotlin 宣告型別是
     * `RectF?`（可空），而非 javap 反編譯 bytecode 表面看到的
     * `RectF`——Kotlin 的可空性是編譯器層級中繼資料，不反映在 JVM
     * bytecode 的欄位型別本身，純用 javap 無法偵測到這個落差，只有真正
     * 跑 Kotlin 編譯器才會擋下非 safe-call 存取。`rect` 為 `null` 時直接
     * 靜默不回報這次選取事件（比照本檔案既有對非致命/背景訊號的處理
     * 原則，例如 `jumpToLocator` 對無效 `locatorJson` 的靜默忽略）——
     * 使用者只是這一次選取沒有觸發浮動工具列，並非致命錯誤，不需要
     * 更複雜的退回方案（例如假想一個全零矩形）。
     */
    private fun reportSelectionChanged(selection: Selection) {
        val width = container.width.toFloat()
        val height = container.height.toFloat()
        if (width <= 0 || height <= 0) return
        val rect = selection.rect ?: return
        channel.invokeMethod(
            "onSelectionChanged",
            mapOf(
                "locatorJson" to selection.locator.toJSON().toString(),
                "progression" to selection.locator.locations.totalProgression,
                "leftPct" to (rect.left / width).toDouble(),
                "topPct" to (rect.top / height).toDouble(),
                "rightPct" to (rect.right / width).toDouble(),
                "bottomPct" to (rect.bottom / height).toDouble(),
            ),
        )
    }

    /**
     * 把 Dart 端送來的完整標記清單（見
     * app/lib/reader/epub_decoration.dart `EpubDecoration.toWire()`）
     * 轉換為 Readium `Decoration` 清單並整組套用（`applyDecorations`
     * 本身是「取代目前該群組全部標記」語意，非增量新增，比照
     * `EpubPreferences` 整組送出的既有慣例）。單筆解析失敗（例如
     * locatorJson 格式錯誤）時該筆略過，不影響其餘標記，比照本檔案既有
     * 對非致命錯誤的處理原則（見 `jumpToLocator` 分支）。
     */
    private suspend fun applyDecorationsFromWire(list: List<Map<String, Any?>>) {
        val nav = navigatorFragment ?: return
        val decorations = list.mapNotNull { entry ->
            val id = entry["id"] as? String ?: return@mapNotNull null
            val locatorJson = entry["locatorJson"] as? String ?: return@mapNotNull null
            val tint = (entry["tint"] as? Number)?.toInt() ?: return@mapNotNull null
            val isUnderline = entry["isUnderline"] as? Boolean ?: false
            val locator = try {
                Locator.fromJSON(JSONObject(locatorJson))
            } catch (e: Exception) {
                null
            } ?: return@mapNotNull null
            val style: Decoration.Style = if (isUnderline) {
                Decoration.Style.Underline(tint = tint, isActive = false)
            } else {
                Decoration.Style.Highlight(tint = tint, isActive = false)
            }
            Decoration(id = id, locator = locator, style = style)
        }
        if (isDisposed) return
        nav.applyDecorations(decorations, ANNOTATIONS_DECORATION_GROUP)
    }

    /**
     * 把 Dart 端送來的偏好設定 map（openBook 的 initialPreferences，或
     * setPreferences 的參數，兩者格式相同）轉換為 EpubPreferences；未出現在
     * map 中的 key 對應到該欄位的 null（交由 currentPreferences.plus() 決定
     * 最終生效值，不覆蓋既有已設定的其他欄位）。
     */
    private fun buildPreferencesFromMap(map: Map<String, Any?>): EpubPreferences {
        (map["navZoneActions"] as? List<*>)?.let { raw ->
            navZoneActions = raw.map { ZoneAction.fromWireValue(it as? String) }
        }
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
     *
     * 【epic-6-annotations Issue 2 擴充】本函式職責已從「只登記字型」擴充
     * 為建構整個 EpubNavigatorFragment.Configuration：額外設定
     * `selectionActionModeCallback`（攔截原生選字工具列，見
     * SelectionActionModeCallback KDoc）與 `decorationTemplates`
     * （`HtmlDecorationTemplates.defaultTemplates()`，Readium 內建預設
     * 模板即可正確渲染 Highlight/Underline 兩種 built-in 樣式，不自訂
     * HtmlDecorationTemplate，見 plan-issue-2.md Global Constraints「純
     * 備註視覺簡化」）。方法名稱同步由 buildFontFamiliesConfiguration
     * 改為 buildNavigatorConfiguration，反映此擴充後的實際職責。
     */
    private fun buildNavigatorConfiguration(): EpubNavigatorFragment.Configuration {
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
            selectionActionModeCallback = SelectionActionModeCallback()
            decorationTemplates = HtmlDecorationTemplates.defaultTemplates()
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
        initialTotalCharacterCount: Int?,
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
                attachNavigator(openedPublication, initialPreferences, initialLocatorJson, initialTotalCharacterCount)
            } catch (e: Exception) {
                channel.invokeMethod("onError", "開啟 EPUB 檔案時發生未預期的錯誤：${e.message}")
            }
        }
    }

    private fun attachNavigator(
        openedPublication: Publication,
        initialPreferences: Map<String, Any?>?,
        initialLocatorJson: String?,
        initialTotalCharacterCount: Int?,
    ) {
        // commitNow 在 Activity 已經過了 onSaveInstanceState（例如解析完成前使用者恰好把
        // App 切到背景）時會丟出 IllegalStateException；containerId 若因為合成模式改變
        // 等原因無法解析到實際 View（見上方類別註解），也可能丟出 IllegalArgumentException。
        // 兩者都必須攔截並改走 onError，否則例外會發生在 scope.launch 內成為未攔截的
        // 協程例外，導致 Flutter 端卡住或整個 App 崩潰，繞過既有的錯誤回報機制。
        try {
            publication = openedPublication
            // 修復 Issue 16：Readium 官方解析器判定這本書不是 FXL 時（可能是
            // 書本 metadata 本身不規範，也可能是使用者透過「強制 FXL」（Issue 15）
            // 覆蓋了引擎分派決定，見 ADR 0016），用官方 Publication.Builder 重建
            // 一個 metadata.layout 強制為 FIXED 的物件，讓 EpubNavigatorFragment
            // 收到的 metadata 本身就是 FXL；沒有 mismatch 時原樣沿用，不重建
            // （避免對正常 FXL 書籍引入不必要的服務遺失風險，見 Issue 20）。
            @OptIn(InternalReadiumApi::class)
            val effective = if (openedPublication.metadata.layout != Layout.FIXED) {
                Publication.Builder(
                    manifest = openedPublication.manifest.copy(
                        metadata = openedPublication.manifest.metadata.copy(
                            layout = Layout.FIXED,
                        ),
                    ),
                    container = openedPublication.container,
                    servicesBuilder = Publication.ServicesBuilder(),
                ).build()
            } else {
                openedPublication
            }
            effectivePublication = effective
            val navigatorFactory = EpubNavigatorFactory(publication = effective)
            val initialLocator = initialLocatorJson?.let {
                Locator.fromJSON(JSONObject(it))
            }
            val fragmentFactory = navigatorFactory.createFragmentFactory(
                initialLocator = initialLocator,
                listener = this,
                paginationListener = this,
                configuration = buildNavigatorConfiguration(),
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
            // epic-6-annotations Issue 2：標記點擊事件（design.md 使用者
            // 流程步驟 3：「點擊既有劃線/備註 → 開啟編輯 Dialog」）。
            val listener = object : DecorableNavigator.Listener {
                override fun onDecorationActivated(
                    event: DecorableNavigator.OnActivatedEvent,
                ): Boolean {
                    channel.invokeMethod("onAnnotationActivated", event.decoration.id)
                    return true
                }
            }
            decorationListener = listener
            navigatorFragment?.addDecorationListener(ANNOTATIONS_DECORATION_GROUP, listener)
            if (initialPreferences != null && initialPreferences.isNotEmpty()) {
                applyDualPagePreferences(initialPreferences)
                currentPreferences = currentPreferences.plus(buildPreferencesFromMap(initialPreferences))
                navigatorFragment?.submitPreferences(currentPreferences)
            }
            // epic-7-interaction Issue 6：僅流式（isFixedLayout == false）路徑
            // 註冊熱區點擊監聽器——Issue 1 spike（reviews/spike-epub-inputlistener.md）
            // 已在真機驗證 3 項風險：(1) EpubNavigatorFragment 對純點擊無內建
            // 翻頁反應，不需要停用步驟；(2) onTap() 攔截可靠，goForward()/
            // goBackward() 呼叫與點擊次數嚴格 1:1，無重複觸發；(3) TapEvent.point
            // 為 publicationView 本地座標（與其寬高同一座標系，無 letterbox），
            // NavZoneHitTester.cellIndex() 不需額外轉換。FXL（isFixedLayout ==
            // true）完全不進這個分支，熱區疊加層由 Dart 端 GestureDetector
            // 處理（epic-7-interaction Issue 5）。
            // 修復後 effective.metadata.layout 恆為 Layout.FIXED（Step 3 已強制
            // 覆寫 mismatch 的情況），此條件理論上不再成立，原生端 tap 熱區監聽器
            // 不會再與 Dart 端 9 宮格 GestureDetector（epic-7-interaction Issue 5）
            // 同時作用（見 Issue 16 附帶發現的雙重輸入處理風險）；保留判斷式作為
            // 防禦層，不刪除。
            if (effective.metadata.layout != Layout.FIXED) {
                val listener = object : InputListener {
                    override fun onTap(event: TapEvent): Boolean {
                        val view = navigatorFragment?.publicationView ?: return false
                        val index = NavZoneHitTester.cellIndex(
                            dx = event.point.x,
                            dy = event.point.y,
                            width = view.width.toFloat(),
                            height = view.height.toFloat(),
                        )
                        when (navZoneActions.getOrElse(index) { ZoneAction.NONE }) {
                            ZoneAction.PREVIOUS_PAGE -> {
                                // design.md 決策 #15：捲動翻頁模式下左右熱區失效。
                                if (currentPreferences.scroll != true) {
                                    navigatorFragment?.goBackward(animated = false)
                                }
                            }
                            ZoneAction.NEXT_PAGE -> {
                                if (currentPreferences.scroll != true) {
                                    navigatorFragment?.goForward(animated = false)
                                }
                            }
                            ZoneAction.MENU ->
                                channel.invokeMethod("onZoneTapped", mapOf("cellIndex" to index))
                            ZoneAction.NONE -> {}
                        }
                        return true
                    }
                }
                navInputListener = listener
                navigatorFragment?.addInputListener(listener)
            }
            // epic-5-toc-pagination Issue 3：僅在尚無快取值時才觸發背景字元數
            // 計算，之後每次開書直接沿用 Dart 端傳入的快取值，不重新走訪全書
            // （見 spec.md「執行緒與快取」）。
            if (initialTotalCharacterCount == null) {
                computeTotalCharacterCountInBackground(openedPublication)
            }
        } catch (e: Exception) {
            // 掛載失敗時 Fragment 沒有真正附著到任何畫面上，Publication 不會再被使用，
            // 必須主動關閉釋放資源——與 openBook() 中 isDisposed 分支的做法一致。
            publication = null
            effectivePublication = null
            openedPublication.close()
            channel.invokeMethod("onError", "掛載 EPUB 閱讀畫面失敗：${e.message}")
        }
    }

    /**
     * 全書字元數背景計算（epic-5-toc-pagination Issue 3，spec.md「分頁估算
     * 模組」決策 #16）：於 Dispatchers.IO 走訪 readingOrder 逐一取得
     * resource 內容並以 EpubCharacterCounter 計算字元數後加總，避免阻塞
     * 主執行緒；僅在尚無快取值時觸發（見 attachNavigator() 呼叫處）。
     *
     * `Publication.get(link: Link): Resource?`／`Resource.read(): Try<ByteArray,
     * ReadError>`／`Resource` 需顯式 `close()` 三件事，皆已由本檔案同目錄下
     * `BookMetadataChannel.kt`（`findFallbackCoverBitmap()`，約第 350-366 行）
     * 的既有、已編譯執行的程式碼驗證過，不需要另外反編譯確認。
     * 下方寫法沿用同一組簽章與 `getOrElse { null } ?: <跳轉>` 慣例——`getOrElse`
     * 的 lambda 內不可直接寫 `continue`（Kotlin 對 inline 函式的 non-local
     * `break`/`continue` 有嚴格限制，即使是 inline function 也不允許，寫
     * `getOrElse { continue }` 會編譯失敗），須先在 lambda 內回傳 `null`，
     * 於 lambda 外再以 `?: continue` 跳出。若計算過程任何一步失敗，靜默放棄
     * 不回報 onError——這是背景增強功能，計算失敗不應該讓已成功開啟的書籍
     * 畫面跟著顯示錯誤（比照本檔案既有對「非致命背景工作」的錯誤處理原則）。
     */
    private fun computeTotalCharacterCountInBackground(publicationForCounting: Publication) {
        scope.launch(Dispatchers.IO) {
            try {
                var total = 0
                for (link in publicationForCounting.readingOrder) {
                    if (isDisposed) return@launch
                    val resource = publicationForCounting.get(link) ?: continue
                    try {
                        val bytes = resource.read().getOrElse { null } ?: continue
                        total += EpubCharacterCounter.countCharacters(bytes.toString(Charsets.UTF_8))
                    } finally {
                        // Resource 實作 Closeable，背景計算可能遍歷數十至數百個
                        // resource，不關閉會導致檔案描述符洩漏（比照
                        // BookMetadataChannel.kt findFallbackCoverBitmap() 的既有
                        // try/finally 模式）。
                        resource.close()
                    }
                }
                if (isDisposed) return@launch
                withContext(Dispatchers.Main) {
                    if (!isDisposed) channel.invokeMethod("onCharacterCountReady", total)
                }
            } catch (e: Exception) {
                // 背景估算失敗不影響已成功開啟的書籍畫面，靜默放棄（見本方法 KDoc）。
            }
        }
    }

    /**
     * 依全書進度比例（[progression]，0.0-1.0，由 Dart 端 EpubPageEstimator
     * 估算）跳轉到最接近的 Locator。沿用 Readium 既有的
     * `Publication.positions()` API（design.md 決策 #5 已確認存在）挑選最
     * 接近的 Locator 後呼叫 `Navigator.go()`——刻意不另外發明字元偏移量對應
     * Locator 的複雜機制。
     *
     * 若 Publication 尚未載入（navigatorFragment 為 null）或 positions 為空，
     * 靜默忽略——Dart 端只會在 onPageRendered 觸發之後才送出這個指令。
     */
    private fun jumpToProgression(progression: Double) {
        val nav = navigatorFragment ?: return
        val pub = publication ?: return
        scope.launch(Dispatchers.IO) {
            val positions = pub.positions()
            if (isDisposed || positions.isEmpty()) return@launch
            val index = (progression * (positions.size - 1)).roundToInt()
                .coerceIn(0, positions.size - 1)
            val locator = positions[index]
            withContext(Dispatchers.Main) {
                if (!isDisposed) nav.go(locator, animated = false)
            }
        }
    }

    /**
     * 目錄樹狀結構一次性讀取 + 序列化（epic-5-toc-pagination Issue 4，
     * spec.md「目錄模組」）：走訪 `Publication.tableOfContents`（巢狀
     * `List<Link>`），對每個節點透過 `Publication.locatorFromLink()` 建構
     * 可供 `Navigator.go()` 使用的精確 Locator（含錨點，非僅解析到
     * resource 起始位置）。
     *
     * 頁碼估算所需的全書進度比例優先取用該 Locator 本身的
     * `totalProgression`；若為 `null`（Readium 內部對 `locatorFromLink()`
     * 產生的 Locator 是否必然填入 `totalProgression` 沒有文件保證），退而
     * 求其次比對 `Publication.positions()`（`jumpToProgression()` 已建立
     * 的既有先例）中 `href` 相同的第一個位置，取其 `totalProgression`
     * 作為近似值；兩者皆查無時保持 `null`，Dart 端顯示佔位符，不視為
     * 錯誤（見 spec.md「目錄模組」載入中狀態決策）。
     *
     * 【審查修正】`positions()` 依 href 查找的部分改為先建一份
     * `Map<Url, Locator>`（`associateBy`）再以 O(1) 查表，而非對每個目錄
     * 節點各自線性掃描整個 `positionsList`（O(章節數 × 全書切分位置數)）。
     * `distinctBy { it.href }` 保留每個 href 第一次出現的位置，與原本
     * `firstOrNull { it.href == ... }` 語意等價（`distinctBy` 依走訪順序
     * 保留首個符合者）。
     *
     * 於 `Dispatchers.IO` 執行——`positions()` 本身是 suspend 函式，且
     * 巢狀走訪＋逐節點查表在章節數量極多的書籍上仍可能有感知得到的延遲，
     * 統一放背景執行緒避免阻塞主執行緒（比照
     * `computeTotalCharacterCountInBackground()` 的既有原則）。任何一步
     * 失敗（例如 `publication` 尚未成功開啟）皆回傳空清單，靜默降級，不
     * 回報 `onError`——目錄讀取失敗不應該讓已成功開啟的書籍畫面顯示錯誤。
     */
    private suspend fun buildTocPayloadSafely(): List<Map<String, Any?>> {
        val pub = publication ?: return emptyList()
        return try {
            val positionsMap = pub.positions().distinctBy { it.href }.associateBy { it.href }
            buildTocEntries(pub.tableOfContents, pub, positionsMap)
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun buildTocEntries(
        links: List<Link>,
        pub: Publication,
        positionsMap: Map<Url, Locator>,
    ): List<Map<String, Any?>> {
        return links.map { link ->
            val locator = pub.locatorFromLink(link)
            val progression = locator?.locations?.totalProgression
                ?: positionsMap[locator?.href]?.locations?.totalProgression
            mapOf(
                "title" to (link.title ?: ""),
                "locatorJson" to (locator?.toJSON()?.toString() ?: ""),
                "progression" to progression,
                "children" to buildTocEntries(link.children, pub, positionsMap),
            )
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
        val isFixedLayout = effectivePublication?.metadata?.layout == Layout.FIXED
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
        ReaderViewAttachmentTracker.detach()
        scope.cancel()
        removeFxlLayoutListener()
        decorationListener?.let { navigatorFragment?.removeDecorationListener(it) }
        navInputListener?.let { navigatorFragment?.removeInputListener(it) }
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
        effectivePublication = null
        navigatorFragment = null
    }
}
