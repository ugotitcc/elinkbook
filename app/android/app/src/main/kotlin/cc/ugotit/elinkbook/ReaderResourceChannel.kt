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
 * 取代原本 `FoliateEpubReaderView.kt` 的 `WebViewAssetLoader`／
 * `BookPathHandler`——本類別只負責「給定路徑/URI，回傳位元組或快取路徑」，
 * 不涉及任何 WebView 生命週期或 JS 橋接，是純粹的資源讀取轉發層。
 */
class ReaderResourceChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
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
     * 快取路徑為 `foliate_book_cache/<instanceId>/current.epub`，
     * 避免螢幕轉場期間兩個 `FoliateEpubReaderView` 實例並存時共用同一個可變檔案的競態。
     *
     * @param input 輸入串流（`content://` URI 或本機檔案）
     * @param instanceId Dart 端產生的實例唯一 ID，用於區隔快取子目錄
     * @return 快取檔案的絕對路徑，失敗回傳 null
     */
    private fun copyToCache(input: InputStream, instanceId: String): String? {
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
                    input?.let { copyToCache(it, instanceId) }
                } catch (e: Exception) {
                    null
                }
                result.success(cachedPath)
            }
            else -> result.notImplemented()
        }
    }
}
