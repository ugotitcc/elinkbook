package cc.ugotit.elinkbook

import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.add
import androidx.fragment.app.commitNow
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
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Url
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
 * Activity 上其他 Fragment（例如未來若同時存在其他自訂 FragmentFactory 使用者）。本
 * App 目前的畫面設計（見 spec.md 的單一 seam）同一時間只會顯示一個原生閱讀 view，因此
 * 這個「保留一份、還原一份」的簡單作法已足夠；並非要處理多個 EpubReaderView 同時存在
 * 互相覆寫的通用情境（目前用不到，YAGNI）。
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
    private var publication: Publication? = null
    private var pageReported = false
    private var isDisposed = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = container

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                openBook(call.argument<String>("path"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun openBook(path: String?) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        pageReported = false
        scope.launch {
            val httpClient = DefaultHttpClient()
            val assetRetriever = AssetRetriever(context.contentResolver, httpClient)
            val asset = assetRetriever.retrieve(File(path)).getOrElse {
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
            attachNavigator(openedPublication)
        }
    }

    private fun attachNavigator(openedPublication: Publication) {
        publication = openedPublication
        val navigatorFactory = EpubNavigatorFactory(publication = openedPublication)
        activity.supportFragmentManager.fragmentFactory =
            navigatorFactory.createFragmentFactory(
                initialLocator = null,
                listener = this,
                paginationListener = this,
            )
        activity.supportFragmentManager.commitNow {
            add<EpubNavigatorFragment>(containerId, args = Bundle(), tag = fragmentTag)
        }
    }

    override fun onPageLoaded() {
        if (!pageReported) {
            pageReported = true
            channel.invokeMethod("onPageRendered", null)
        }
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

    override fun dispose() {
        isDisposed = true
        scope.cancel()
        val fragment = activity.supportFragmentManager.findFragmentByTag(fragmentTag)
        if (fragment != null) {
            activity.supportFragmentManager.commitNow(allowStateLoss = true) { remove(fragment) }
        }
        activity.supportFragmentManager.fragmentFactory = previousFragmentFactory
        publication?.close()
        publication = null
    }
}
