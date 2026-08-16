package cc.ugotit.elinkbook

import android.content.Context
import android.net.Uri
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

/**
 * 供 Dart 端 `InAppWebView.shouldInterceptRequest`（`foliate_native_bridge.dart`）
 * 讀取兩類原生端才能存取的位元組資料：
 *
 * 1. `readAndroidAsset`：`app/android/app/src/main/assets/foliate/` 底下的
 *    `foliate-js` 靜態檔案（不是 Flutter `pubspec.yaml` 宣告的資源，
 *    Dart 端 `rootBundle` 讀不到，見
 *    docs/epics/epic-18-reader-device-qa/plans/plan-issue-10.md 決策 #2）。
 *
 * 2. `cacheBookForServing`：將 EPUB 檔案（`content://` URI 或本機檔案路徑）
 *    分塊複製到每個 widget 實例獨立的快取子目錄（`foliate_book_cache/<instanceId>/current.epub`），
 *    供 `WebViewAssetLoader.InternalStoragePathHandler` 串流服務。
 *    此 method channel 透過 `BinaryMessenger.makeBackgroundTaskQueue()` 註冊，
 *    不阻塞 Android 主執行緒（避免 217MB 檔案複製造成 ANR）。
 *
 * 3. `readCustomFontBytes`：讀取自訂字型的 `content://` URI 位元組
 *    （epic-14-system-settings Issue 3，ADR 0021 決策：不落地快取），
 *    比照 `readAndroidAsset` 一次性讀取模式，非 `cacheBookForServing`
 *    的落地快取模式——字型檔案遠小於 217MB 書籍本體，不需要背景執行緒
 *    佇列避免 ANR。
 *
 * 4. `readContentUriAll`：將 `content://` URI 的 PDF 檔案串流複製到 App
 *    快取目錄的暫存檔（`elinkbook_pdf_tmp/doc_<nanoTime>.pdf`），
 *    回傳暫存檔路徑。Dart 端 `PdfReaderView._openContentUriDocument()`
 *    直接以 `PdfDocument.openFile()` 開啟該路徑。使用串流複製取代
 *    `readBytes()` 避免大型 PDF 佔用雙倍記憶體（epic-24 Issue 2）。
 *    暫存檔在 Dart 端 `dispose()` 時清理。
 *
 * 取代原本 `FoliateEpubReaderView.kt` 的 `WebViewAssetLoader`／
 * `BookPathHandler`——本類別只負責「給定路徑/URI，回傳位元組或快取路徑」，
 * 不涉及任何 WebView 生命週期或 JS 橋接，是純粹的資源讀取轉發層。
 */
class ReaderResourceChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        // "cacheBookForServing" 的 extension 引數白名單（epic-11 Issue 3
        // 程式碼審查 Minor #2），見該處呼叫點註解。
        private val EXTENSION_PATTERN = Regex("^[a-z0-9]{1,10}$")
    }

    private val channel = MethodChannel(messenger, "elinkbook/reader_resources")

    /**
     * 背景執行緒的 method channel，處理 `cacheBookForServing`。
     * 217MB 檔案複製可能耗時數秒，若在主執行緒同步執行會阻塞手勢/動畫/UI 更新，
     * 觸發 ANR watchdog（本專案明確以 E-Ink／較舊裝置為目標族群，儲存 I/O 可能更慢）。
     */
    private val cacheChannel = MethodChannel(
        messenger,
        "elinkbook/reader_resources_cache",
        StandardMethodCodec.INSTANCE,
        messenger.makeBackgroundTaskQueue(),
    )

    init {
        channel.setMethodCallHandler(this)
        cacheChannel.setMethodCallHandler(this)
    }

    /**
     * 將輸入串流分塊複製到每個 widget 實例獨立的快取子目錄。
     * 快取路徑為 `foliate_book_cache/<instanceId>/current.<extension>`
     * （epic-11-multi-format-reader Issue 3：extension 依來源書籍真實副
     * 檔名決定，取代原本寫死 `current.epub` 的既有行為——CBZ 需要
     * `view.js` 的 `isCBZ()` 對檔名做副檔名判斷才能正確自動分派至
     * `comic-book.js`，見該處原始碼），
     * 避免螢幕轉場期間兩個 `FoliateEpubReaderView` 實例並存時共用同一個可變檔案的競態。
     *
     * @param input 輸入串流（`content://` URI 或本機檔案）
     * @param instanceId Dart 端產生的實例唯一 ID，用於區隔快取子目錄
     * @param extension 快取檔名副檔名（不含點號），Dart 端 cacheFileExtension() 推導
     * @return 快取檔案的絕對路徑，失敗回傳 null
     */
    private fun copyToCache(input: InputStream, instanceId: String, extension: String): String? {
        val cacheDir = File(context.filesDir, "foliate_book_cache/$instanceId").apply { mkdirs() }
        val destFile = File(cacheDir, "current.$extension")
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
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readAndroidAsset" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.success(null)
                    return
                }
                val bytes = try {
                    context.assets.open(path).use { it.readBytes() }
                } catch (e: Exception) {
                    null
                }
                result.success(bytes)
            }
            "readCustomFontBytes" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.success(null)
                    return
                }
                // 比照 readAndroidAsset：一次性讀取，不落地快取（ADR 0021），
                // try/catch 吞掉例外統一回傳 null，避免 SAF 授權失效等情境
                // 讓例外冒出變成 Dart 端未預期的 PlatformException。失敗時
                // 記錄 Log.w（非 Log.d——部分裝置的客製化 ROM 會過濾 Debug
                // 等級的 logcat 輸出，見 epic-7-interaction Issue 1 spike 已
                // 記錄的既有教訓），方便日後用 adb logcat 判斷是 SAF 授權
                // 過期還是原始檔案已被使用者刪除（審查修正，見
                // tmp/epic-14/review-plan-issue-3.md Minor 1）。
                val bytes = try {
                    context.contentResolver.openInputStream(Uri.parse(uriString))
                        ?.use { it.readBytes() }
                } catch (e: Exception) {
                    Log.w("ReaderResourceChannel", "Failed to read custom font bytes for uri: $uriString", e)
                    null
                }
                result.success(bytes)
            }
            "cacheBookForServing" -> {
                val instanceId = call.argument<String>("instanceId")
                val uriString = call.argument<String>("uri")
                val filePath = call.argument<String>("filePath")
                // extension 一律由 Dart 端 cacheFileExtension() 推導（僅來自
                // 檔案自身副檔名或固定退回值 "epub"，見
                // foliate_native_bridge.dart 該函式文件註解），但這是跨
                // Platform Channel 邊界傳入、直接組進檔案路徑
                // （File(cacheDir, "current.$extension")，見 copyToCache()）
                // 的字串，加一道白名單驗證作為低成本加固（epic-11 Issue 3
                // 程式碼審查 Minor #2）——不符合格式時退回 "epub"，比照上面
                // 缺席時的既有退回值，不中止整個快取流程。
                val rawExtension = call.argument<String>("extension") ?: "epub"
                val extension = if (EXTENSION_PATTERN.matches(rawExtension)) rawExtension else "epub"
                if (instanceId == null) {
                    result.success(null)
                    return
                }
                // 整個 when 分支（含開啟輸入串流）須納入同一個 try/catch，
                // SAF 授權失效／檔案競態刪除等情境會讓例外未被捕捉地冒出，
                // 變成 Dart 端未預期的 PlatformException。
                val cachedPath = try {
                    val input: InputStream? = when {
                        uriString != null -> context.contentResolver.openInputStream(Uri.parse(uriString))
                        filePath != null -> File(filePath).inputStream()
                        else -> null
                    }
                    input?.let { copyToCache(it, instanceId, extension) }
                } catch (e: Exception) {
                    null
                }
                result.success(cachedPath)
            }
            // epic-24-pdf-engine-rebuild Issue 2：將 content:// URI 的 PDF 檔案
            // 串流複製到 App 快取目錄的暫存檔，回傳暫存檔路徑。pdfrx 的
            // PdfDocument.openCustom 雖然宣告 read callback 為 FutureOr，但
            // 內部 PDFium FFI 實作是在 native 執行緒同步呼叫該 callback，
            // 無法等待 MethodChannel 回傳的 Future（已知技術風險，見
            // plan-issue-1 Task 2），因此 Dart 端改為先透過本方法取得暫存
            // 檔路徑，再以 PdfDocument.openFile() 開啟。
            //
            // 改用串流複製（BufferedInputStream/BufferedOutputStream 8KB
            // 緩衝）取代 readBytes() 一次性載入，避免大型 PDF（數百 MB）
            // 佔用雙倍記憶體（readBytes 的位元組陣列 + writeAsBytes 的
            // 位元組陣列）。快取目錄在 Dart 端 dispose() 時清理。
            "readContentUriAll" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.success(null)
                    return
                }
                val tmpPath = try {
                    val cacheDir = File(context.cacheDir, "elinkbook_pdf_tmp").apply { mkdirs() }
                    val tmpFile = File(cacheDir, "doc_${System.nanoTime()}.pdf")
                    context.contentResolver.openInputStream(Uri.parse(uriString))
                        ?.use { input ->
                            FileOutputStream(tmpFile).use { output ->
                                input.copyTo(output)  // Kotlin 標準函式，預設 8KB 緩衝
                            }
                        }
                    tmpFile.absolutePath
                } catch (e: Exception) {
                    Log.w("ReaderResourceChannel", "Failed to stream content uri to temp file: $uriString", e)
                    null
                }
                result.success(tmpPath)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * 清理所有資源（epic-24-pdf-engine-rebuild Issue 1）。
     * 原本規劃的隨機存取 session 機制（openSessions/openContentUriForRandomAccess/
     * closeContentUriSession）最終未採用，改為 readContentUriAll 一次性讀取，
     * 因此本方法目前為 no-op。保留方法簽章供 MainActivity.onDestroy() 呼叫，
     * 日後若恢復分段讀取方案可在此實作 session 清理。
     */
    fun closeAllSessions() {
        // 目前 readContentUriAll 不維護 session 狀態，無需清理。
    }
}
