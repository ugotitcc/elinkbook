package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.readium.r2.shared.publication.services.cover
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.toAbsoluteUrl
import org.readium.r2.shared.util.toUrl
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser

/**
 * 一次性呼叫的原生 MethodChannel，供圖書庫匯入流程（Issue 4）提取詮釋資料
 * （標題/作者/封面），與 EpubReaderView/PdfReaderView 的 PlatformView 渲染
 * 契約分開（見 docs/epics/epic-1-library/spec.md）。`uri` 參數可能是真實
 * 檔案系統路徑，也可能是 content:// 或 file:// URI 字串（見 ADR 0002）；
 * 判斷規則與 EpubReaderView/PdfReaderView（Issue 3）一致但各自獨立實作。
 */
class BookMetadataChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "elinkbook/book_metadata")
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    init {
        channel.setMethodCallHandler(this)
    }

    /**
     * [path] 可能是真實檔案系統路徑，也可能是 content:// 或 file:// URI
     * 字串。含 "://" 者一律視為 URI，交給 Readium 的 Uri 解析；否則視為
     * 檔案系統路徑。
     */
    private fun resolveAbsoluteUrl(path: String): AbsoluteUrl {
        return if (path.contains("://")) {
            // Uri.toAbsoluteUrl() 實際簽章回傳 AbsoluteUrl?（uri 不是絕對路徑時為
            // null），與工單原始程式碼假設的非空簽章不符；轉為 IllegalArgumentException
            // 讓外層 try/catch 統一轉成 result.error("extraction_failed", ...)。
            Uri.parse(path).toAbsoluteUrl()
                ?: throw IllegalArgumentException("無法解析為合法的絕對 URI：$path")
        } else {
            // File.toUrl() 實際簽章需要 isDirectory 參數；此處一律處理檔案（非目錄）。
            File(path).toUrl(isDirectory = false)
        }
    }

    /**
     * [path] 含 "://" 者一律視為 URI，交給 ContentResolver 開啟；否則視為
     * 檔案系統路徑，沿用 ParcelFileDescriptor.open() 邏輯。
     */
    private fun openParcelFileDescriptor(path: String): ParcelFileDescriptor? {
        return if (path.contains("://")) {
            context.contentResolver.openFileDescriptor(Uri.parse(path), "r")
        } else {
            ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "extractMetadata" -> {
                val path = call.argument<String>("uri")
                val format = call.argument<String>("format")
                if (path == null || format == null) {
                    result.error("invalid_arguments", "缺少 uri 或 format 參數", null)
                    return
                }
                when (format) {
                    "epub" -> extractEpubMetadata(path, result)
                    "pdf" -> extractPdfMetadata(path, result)
                    else -> result.error("unsupported_format", "不支援的格式：$format", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun extractEpubMetadata(path: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                val httpClient = DefaultHttpClient()
                val assetRetriever = AssetRetriever(context.contentResolver, httpClient)
                val asset = assetRetriever.retrieve(resolveAbsoluteUrl(path)).getOrElse {
                    result.error("extraction_failed", "找不到檔案或檔案已損毀：$path", null)
                    return@launch
                }
                val publicationParser = DefaultPublicationParser(
                    context,
                    httpClient,
                    assetRetriever,
                    pdfFactory = null,
                )
                val publicationOpener = PublicationOpener(publicationParser)
                val publication =
                    publicationOpener.open(asset, allowUserInteraction = false).getOrElse {
                        // open() 失敗時 asset 不會被 publicationOpener 接手管理，
                        // 需自行關閉避免資源洩漏（例如 Issue 4 匯入流程對損毀檔案重試）。
                        asset.close()
                        result.error("extraction_failed", "無法解析 EPUB 檔案：${it.message}", null)
                        return@launch
                    }
                try {
                    val title = publication.metadata.title
                    val author = publication.metadata.authors.firstOrNull()?.name
                    // PNG 壓縮為 CPU 密集工作，移到背景執行緒避免阻塞主執行緒；
                    // withContext 返回後會自動切回 scope 的 Main dispatcher。
                    val coverBytes = withContext(Dispatchers.IO) {
                        publication.cover()?.let { bitmapToPngBytes(it) }
                    }
                    result.success(
                        mapOf(
                            "title" to title,
                            "author" to author,
                            "coverBytes" to coverBytes,
                        ),
                    )
                } finally {
                    publication.close()
                }
            } catch (e: Exception) {
                result.error(
                    "extraction_failed",
                    "提取 EPUB 詮釋資料時發生未預期的錯誤：${e.message}",
                    null,
                )
            }
        }
    }

    private fun extractPdfMetadata(path: String, result: MethodChannel.Result) {
        scope.launch {
            // PdfRenderer 開檔/渲染與 PNG 壓縮皆為阻塞/CPU 密集工作，對 PRD 要求
            // 支援的 100MB 以上 PDF 若在主執行緒執行會造成 ANR；移至 IO
            // dispatcher，withContext 返回後自動切回 scope 的 Main dispatcher
            // 再呼叫 result.success()/result.error()（MethodChannel.Result 的
            // callback 必須在平台/主執行緒呼叫）。
            try {
                val pngBytes = withContext(Dispatchers.IO) {
                    var pfd: ParcelFileDescriptor? = null
                    var renderer: PdfRenderer? = null
                    var page: PdfRenderer.Page? = null
                    try {
                        pfd = openParcelFileDescriptor(path)
                            ?: return@withContext null
                        renderer = PdfRenderer(pfd)
                        page = renderer.openPage(0)
                        // 封面只是書架縮圖，不需要頁面原始解析度；限制最大尺寸避免大型
                        // PDF（PRD 要求支援 100MB 以上檔案）造成記憶體壓力與封面檔案
                        // 過度肥大。PdfRenderer.Page.render() 在 transform 為 null 時，
                        // 會自動把整頁內容縮放以符合目標點陣圖尺寸，不需額外的矩陣運算。
                        val maxDimension = 600
                        val scale = minOf(
                            maxDimension.toFloat() / page.width,
                            maxDimension.toFloat() / page.height,
                            1f,
                        )
                        val bitmapWidth = (page.width * scale).toInt().coerceAtLeast(1)
                        val bitmapHeight = (page.height * scale).toInt().coerceAtLeast(1)
                        val bitmap =
                            Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        bitmapToPngBytes(bitmap)
                    } finally {
                        try { page?.close() } catch (ignored: Exception) {}
                        try { renderer?.close() } catch (ignored: Exception) {}
                        try { pfd?.close() } catch (ignored: Exception) {}
                    }
                }
                if (pngBytes == null) {
                    result.error("extraction_failed", "找不到檔案或檔案已損毀：$path", null)
                    return@launch
                }
                result.success(
                    mapOf(
                        "title" to null,
                        "author" to null,
                        "coverBytes" to pngBytes,
                    ),
                )
            } catch (e: OutOfMemoryError) {
                result.error("extraction_failed", "記憶體不足，無法載入 PDF 檔案", null)
            } catch (e: Exception) {
                result.error(
                    "extraction_failed",
                    "提取 PDF 封面時發生未預期的錯誤：${e.message}",
                    null,
                )
            }
        }
    }

    private fun bitmapToPngBytes(bitmap: Bitmap): ByteArray {
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }
}
