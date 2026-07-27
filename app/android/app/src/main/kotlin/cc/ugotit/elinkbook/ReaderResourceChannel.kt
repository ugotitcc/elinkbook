package cc.ugotit.elinkbook

import android.content.Context
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 供 Dart 端 `InAppWebView.shouldInterceptRequest`（`foliate_native_bridge.dart`）
 * 讀取兩類原生端才能存取的位元組資料：
 *
 * 1. `readAndroidAsset`：`app/android/app/src/main/assets/foliate/` 底下的
 *    `foliate-js` 靜態檔案（不是 Flutter `pubspec.yaml` 宣告的資源，
 *    Dart 端 `rootBundle` 讀不到，見
 *    docs/epics/epic-18-reader-device-qa/plans/plan-issue-10.md 決策 #2）。
 * 2. `readContentUri`：本機匯入透過 SAF 取得的 `content://` URI（見
 *    docs/adr/0002-content-uri-reader-contract.md），Dart 端 `dart:io` 無法
 *    直接讀取，需要原生 `ContentResolver`。
 *
 * 取代原本 `FoliateEpubReaderView.kt` 的 `WebViewAssetLoader`／
 * `BookPathHandler`——本類別只負責「給定路徑/URI，回傳位元組」，不涉及
 * 任何 WebView 生命週期或 JS 橋接，是純粹的資源讀取轉發層。
 */
class ReaderResourceChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "elinkbook/reader_resources")

    init {
        channel.setMethodCallHandler(this)
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
            "readContentUri" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.success(null)
                    return
                }
                val bytes = try {
                    context.contentResolver.openInputStream(Uri.parse(uriString))
                        ?.use { it.readBytes() }
                } catch (e: Exception) {
                    null
                }
                result.success(bytes)
            }
            else -> result.notImplemented()
        }
    }
}
