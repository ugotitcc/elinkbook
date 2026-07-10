package cc.ugotit.elinkbook

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.webkit.WebView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.commitNow
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.readium.r2.navigator.epub.EpubNavigatorFragment

class MainActivity : FlutterFragmentActivity() {
    private lateinit var bookMetadataChannel: BookMetadataChannel

    // 選擇資料夾的結果狀態（Issue 8）。registerForActivityResult 必須在
    // Activity 進入 STARTED 生命週期之前呼叫，因此以類別層級屬性初始化
    // （AndroidX 官方建議寫法），不放在 configureFlutterEngine() 內。
    private var pendingFolderPickResult: MethodChannel.Result? = null

    private val openDocumentTreeLauncher =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            val result = pendingFolderPickResult
            pendingFolderPickResult = null
            if (uri != null) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (e: Exception) {
                    // 權限持久化失敗時仍回傳 URI；BookImportServiceImpl.importFolder()
                    // 呼叫端會再嘗試一次 takePersistableUriPermission，失敗則視為
                    // 整個資料夾無法匯入（見 docs/epics/epic-1-library/spec.md）。
                }
            }
            result?.success(uri?.toString())
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 在 process death 後重建這個 Activity 時，會嘗試用已儲存的
        // FragmentManager 狀態還原先前掛載的 EpubNavigatorFragment；但它的建構子是
        // internal，且用來建立它的 EpubNavigatorFactory（綁定特定 Publication）已隨
        // 行程一起消失，若不處理，預設的 FragmentFactory 會因無法呼叫該建構子而崩潰。
        // 依 Readium 官方文件建議：先裝一個「dummy」FragmentFactory 讓還原程序本身不會
        // 崩潰；還原完成後，若真的有 EpubNavigatorFragment 被還原出來，必須在它進入
        // onResume() 之前立刻移除（dummy fragment 一旦 onResume() 就會主動拋出
        // RestorationNotSupportedException）。這裡刻意不是「整個 Activity 一律
        // finish()」——本 App 只有單一 Activity，涵蓋書架/設定等所有畫面，process
        // death 後重建時不見得有任何 EpubReaderView 曾經存在，不應該無條件關閉整個
        // App；只有在真的偵測到被還原的 EpubNavigatorFragment 時才需要處理。
        supportFragmentManager.fragmentFactory = EpubNavigatorFragment.createDummyFactory()
        super.onCreate(savedInstanceState)
        supportFragmentManager.fragments
            .filterIsInstance<EpubNavigatorFragment>()
            .forEach { restored ->
                supportFragmentManager.commitNow(allowStateLoss = true) { remove(restored) }
            }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/pdf_reader_view",
                PdfReaderViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/epub_reader_view",
                EpubReaderViewFactory(this, flutterEngine.dartExecutor.binaryMessenger),
            )
        bookMetadataChannel =
            BookMetadataChannel(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "elinkbook/folder_picker")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolder" -> {
                        // 防禦性判斷：避免使用者在系統選取器實際開啟前重複觸發
                        // pickFolder（例如快速連續點擊），導致前一次呼叫的
                        // MethodChannel.Result 被覆蓋、永遠不會被 resolve。
                        if (pendingFolderPickResult != null) {
                            result.error(
                                "already_active",
                                "選取資料夾操作已在進行中",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        pendingFolderPickResult = result
                        openDocumentTreeLauncher.launch(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "elinkbook/app_info")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSystemWebViewVersion" -> {
                        // WebView.getCurrentWebViewPackage() 從 API 26（Android 8.0）
                        // 才存在；本專案 minSdk 為 24，低於 API 26 的裝置一律回傳
                        // null，交給 Dart 端顯示「無法取得」而非讓 App 崩潰。
                        val versionName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            WebView.getCurrentWebViewPackage()?.versionName
                        } else {
                            null
                        }
                        result.success(versionName)
                    }
                    "getBuildTime" -> result.success(BuildConfig.BUILD_TIME)
                    else -> result.notImplemented()
                }
            }
    }
}
