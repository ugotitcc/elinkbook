package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.view.View
import android.widget.ImageView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File

/**
 * 包裝 android.graphics.pdf.PdfRenderer 的原生 PlatformView。
 * 透過 MethodChannel 接收 Flutter 的 openBook 呼叫，成功則呼叫
 * onPageRendered，失敗則呼叫 onError(message)。
 */
class PdfReaderView(
    context: Context,
    id: Int,
    messenger: BinaryMessenger,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val imageView: ImageView = ImageView(context)
    private val channel: MethodChannel =
        MethodChannel(messenger, "cc.ugotit.elinkbook/pdf_reader_view_$id")

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = imageView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                val path = call.argument<String>("path")
                openBook(path)
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
        var pfd: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        var page: PdfRenderer.Page? = null
        try {
            val file = File(path)
            pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = PdfRenderer(pfd)
            page = renderer.openPage(0)
            val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            imageView.setImageBitmap(bitmap)
            channel.invokeMethod("onPageRendered", null)
        } catch (e: OutOfMemoryError) {
            channel.invokeMethod("onError", "記憶體不足，無法載入 PDF 檔案")
        } catch (e: Exception) {
            channel.invokeMethod("onError", e.message ?: "無法載入 PDF 檔案")
        } finally {
            // 確保任何情況下（含上方例外拋出時）原生資源都會被釋放，避免
            // 檔案描述符/渲染器洩漏。
            try { page?.close() } catch (ignored: Exception) {}
            try { renderer?.close() } catch (ignored: Exception) {}
            try { pfd?.close() } catch (ignored: Exception) {}
        }
    }

    override fun dispose() {}
}
