package cc.ugotit.elinkbook

import java.io.FileNotFoundException
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

/**
 * epic-15-storage-permission Issue 1 真機回報：資料夾匯入（tree URI）的書被刪除後，
 * ExternalStorageProvider 在另一個程序丟出 IllegalArgumentException；跨程序傳回來時
 * 只剩例外種類與訊息，cause 為 null。探測改為再問一次「匯入的資料夾本身讀得到嗎」：
 * 資料夾讀得到、書讀不到，就判定是檔案不見了。
 */
class ProbeUriAccessClassifierTest {

    // 真機 logcat 實際收到的例外形狀：cause 為 null，FileNotFoundException 只存在於訊息文字
    private val crossProcessTreeError = IllegalArgumentException(
        "Failed to determine if primary:Download/TEST/a.pdf is child of primary:Download/TEST: " +
            "java.io.FileNotFoundException: Missing file for primary:Download/TEST/a.pdf",
    )

    private val mustNotProbe: () -> String = { fail("不應探測資料夾"); "" }

    @Test
    fun securityException_isPermissionRevoked() {
        assertEquals("permissionRevoked", classifyProbeUriException(SecurityException("revoked"), mustNotProbe))
    }

    @Test
    fun fileNotFoundException_isFileNotFound() {
        assertEquals("fileNotFound", classifyProbeUriException(FileNotFoundException("missing"), mustNotProbe))
    }

    @Test
    fun illegalArgument_treeRootReadable_isFileNotFound() {
        assertEquals("fileNotFound", classifyProbeUriException(crossProcessTreeError) { "readable" })
    }

    @Test
    fun illegalArgument_treeRootPermissionRevoked_isPermissionRevoked() {
        assertEquals("permissionRevoked", classifyProbeUriException(crossProcessTreeError) { "permissionRevoked" })
    }

    @Test
    fun illegalArgument_treeRootUnreadable_isUnknownError() {
        assertEquals("unknownError", classifyProbeUriException(crossProcessTreeError) { "unknownError" })
    }

    @Test
    fun otherException_isUnknownError() {
        assertEquals("unknownError", classifyProbeUriException(IllegalStateException("boom"), mustNotProbe))
    }
}
