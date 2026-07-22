package cc.ugotit.elinkbook

/**
 * 判斷「已正規化」的請求路徑是否真的落在允許根目錄之內（含根目錄本身）。
 * 兩個參數皆須是呼叫端已對真實檔案系統路徑呼叫過 File.canonicalPath 之後
 * 的絕對路徑字串——這裡只做純字串邊界比對，不做任何檔案系統 I/O，因此可
 * 在 JVM 單元測試以純字串案例驗證，不需要真實檔案（見
 * docs/epics/epic-17-epub-render-migration/spec.md「待驗證風險」#3 的安全
 * 要求）。
 *
 * 供 FoliateEpubReaderView.kt 的自訂 WebViewAssetLoader.PathHandler 使用：
 * 開書時把待開啟的 EPUB 檔案系統路徑（[requestedCanonicalPath]）與 App
 * 私有資料目錄根（[allowedRootCanonicalPath]，即 `Context.filesDir.parentFile`，
 * 通常為 `/data/user/0/<applicationId>/`，同時涵蓋 `files/`／`cache/`／
 * `app_flutter/` 等所有 App 私有子目錄——不是單純的 `Context.filesDir`
 * 本身，也不等同 Flutter path_provider 的 `getApplicationDocumentsDirectory()`
 * 〔後者只對應 `files/` 這個子目錄〕；真機測試發現 Flutter 端常用的
 * `getTemporaryDirectory()`〔對應 `Context.cacheDir`〕與正式匯入退路
 * 複製目的地〔`getApplicationDocumentsDirectory()/imported_books/`〕分別
 * 落在 `cache/`／`files/` 兩個平行子目錄，只鎖 `filesDir` 會誤擋合法的
 * `cacheDir` 路徑，故改以兩者共同的父目錄為允許根）比對，防止 WebView
 * 內容（foliate-js 本身或惡意 EPUB 內容）藉由精心構造的請求路徑讀取
 * 允許目錄之外的檔案。
 *
 * 刻意不用單純的 requestedCanonicalPath.startsWith(allowedRootCanonicalPath)
 * ——這會誤判「同前綴但其實是不同目錄」的情況（例如 allowedRoot=
 * "/data/user/0/pkg/files"，requestedPath="/data/user/0/pkg/files_evil/x"
 * 會被單純的 startsWith 誤判為合法，即使 "files_evil" 根本是完全不同的
 * 目錄，只是字串前綴剛好相同）。必須額外要求邊界字元本身也對得上：完全
 * 相等，或者後面緊接著路徑分隔符 "/"。
 */
object FoliatePathValidator {
    fun isPathWithinRoot(
        requestedCanonicalPath: String,
        allowedRootCanonicalPath: String,
    ): Boolean {
        if (requestedCanonicalPath == allowedRootCanonicalPath) return true
        return requestedCanonicalPath.startsWith("$allowedRootCanonicalPath/")
    }
}
