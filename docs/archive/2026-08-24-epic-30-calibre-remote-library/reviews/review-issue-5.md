# Review — Issue 5：E-Ink 優化與真機驗收

**驗證日期：** 2026-08-19
**裝置型號：** （用戶真機）
**Android 版本：** （用戶真機）
**OPDS 伺服器：** Calibre Content Server，`https://opds.jigong.org`（HTTPS，自簽憑證，Basic 認證）

## 驗證結果

| # | 步驟 | 結果 | 備註 |
|---|------|------|------|
| 1 | 新增站點 | ✅ 通過 | URL 需含路徑 `/opds`（根路徑回傳 HTML 導致 XML 解析失敗）；Calibre 認證須設為 Basic（Auto 模式回傳 400） |
| 2 | 瀏覽目錄 | ✅ 通過 | 分類列表正常顯示（由最新、由書名、由出版社、由作者、由系列、由語言、由標籤）；下鑽後書目縮圖正常載入 |
| 3 | 下載 | ✅ 通過 | 格式選擇彈窗正常；下載佇列進度正確；下載完成後狀態顯示正確 |
| 4 | 匯入 | ✅ 通過 | 返回書架後新書自動出現（已修正：`LibraryScreen` 的遠端書庫入口 `Navigator.push` 加 `.then()` 重新載入） |
| 5 | 閱讀 | ✅ 通過 | 點擊新下載書籍正常開啟 ReaderScreen |
| 6 | 移除快取 | ✅ 通過 | 書架封面疊加雲朵角標，中繼資料保留 |
| 7 | 重新下載 | ✅ 通過 | 點擊待下載書籍跳出確認對話框，確認後重新下載成功，雲朵角標消失 |
| 8 | E-Ink 模式 | ✅ 通過 | 切換 E-Ink 高對比模式後，目錄瀏覽的「載入更多」變為「上一頁／下一頁」按鈕列；換頁後書目整批替換 |
| 9 | 刪除站點 | ✅ 通過 | 無待下載書籍時正常刪除；已下載書籍不受影響 |

## 驗證過程中發現並修正的問題

### Finding 1（已修正）：Calibre 根 OPDS feed 格式相容性

**嚴重性：** Critical
**問題：** Calibre Content Server 的根 OPDS feed 使用兩種非標準格式，Parser 無法解析：
1. 根層級 `<link rel="subsection">` 連結未被處理（只有 `<entry>` 內的 `rel="subsection"` 被處理）
2. 分類 `<entry>` 的 `<link>` 不帶 `rel` 屬性，Parser 僅找 `rel="subsection"` 導致全部跳過

**修正：** `OpdsFeedParser.parse()` 新增：
- 根層級 `<link rel="subsection">` 連結解析
- 入口 `<link>` 無 `rel` 時退回取第一個有 `href` 的 `<link>`

**影響範圍：** `app/lib/remote/opds_feed_parser.dart`，新增 2 個單元測試覆蓋

### Finding 2（已修正）：遠端下載後書架不自動刷新

**嚴重性：** Important
**問題：** 從遠端書庫下載書籍後返回書架，新書不會立即顯示，需切換檢視模式或排版才能看到

**修正：** `LibraryScreen` 的遠端書庫入口 `Navigator.push` 加 `.then((_) => _loadBooks())`，返回時自動重新載入書目清單

**影響範圍：** `app/lib/screens/library_screen.dart`，1 行變更

### Finding 3（配置問題，非程式碼缺陷）：Calibre 認證設定

**嚴重性：** N/A（使用者配置）
**問題：** Calibre Content Server 認證設定為 `Auto` 時，伺服器回傳 400 "Unsupported authentication method"
**解法：** 將 Calibre 認證設定改為 `Basic`

### Finding 4（配置問題，非程式碼缺陷）：OPDS URL 需含路徑

**嚴重性：** N/A（使用者配置）
**問題：** `https://opds.jigong.org` 回傳 HTML 入口頁（非 OPDS XML），Parser 解析失敗
**解法：** URL 需改為 `https://opds.jigong.org/opds`

## 結論

Issue 5 全部 9 個驗證步驟通過。驗證過程中發現 2 個 Critical/Important 級別的程式碼問題（Finding 1、2），已即時修正並通過測試。其餘 2 個為使用者配置問題（Finding 3、4），非程式碼缺陷。
