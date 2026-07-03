package cc.ugotit.elinkbook

import android.os.Bundle
import androidx.fragment.app.commitNow
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import org.readium.r2.navigator.epub.EpubNavigatorFragment

class MainActivity : FlutterFragmentActivity() {
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
    }
}
