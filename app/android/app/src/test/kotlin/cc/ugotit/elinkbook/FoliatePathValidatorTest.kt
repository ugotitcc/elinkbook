package cc.ugotit.elinkbook

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FoliatePathValidatorTest {

    private val allowedRoot = "/data/user/0/cc.ugotit.elinkbook/files"

    @Test
    fun `合法路徑——請求路徑就是允許根目錄本身`() {
        assertTrue(FoliatePathValidator.isPathWithinRoot(allowedRoot, allowedRoot))
    }

    @Test
    fun `合法路徑——請求路徑是允許根目錄底下的子路徑`() {
        assertTrue(
            FoliatePathValidator.isPathWithinRoot(
                "$allowedRoot/books/novel.epub",
                allowedRoot,
            ),
        )
    }

    @Test
    fun `不合法——已正規化解析後的路徑落在允許根目錄之外（模擬穿越後的結果）`() {
        assertFalse(
            FoliatePathValidator.isPathWithinRoot(
                "/data/user/0/cc.ugotit.elinkbook/other/secret.txt",
                allowedRoot,
            ),
        )
    }

    @Test
    fun `不合法——同前綴但其實是完全不同的目錄（純 startsWith 會誤判的邊界情況）`() {
        assertFalse(
            FoliatePathValidator.isPathWithinRoot(
                "${allowedRoot}_evil/secret.txt",
                allowedRoot,
            ),
        )
    }

    @Test
    fun `不合法——符號連結指向允許目錄外，模擬 canonicalPath 解析後的絕對路徑`() {
        assertFalse(
            FoliatePathValidator.isPathWithinRoot(
                "/data/user/0/other_app/databases/secrets.db",
                allowedRoot,
            ),
        )
    }
}
