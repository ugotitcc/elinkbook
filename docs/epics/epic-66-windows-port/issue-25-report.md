# Issue 25 報告：Windows 封面型別檢查

日期：2026-11-11　分支：`fix/epic-66-issue-25-windows-cover-type`

## 1. 問題
Windows 的 `readEpubMetadataInWebView()` 在函式內自己解析探針 JSON，把 `coverBase64` 一律解碼，沒有看 `coverType`。foliate `getCover()` 若回傳 XHTML Blob（封面 manifest 項目是 XHTML 頁），XHTML 位元組會被當成封面圖片存下。Android 在 Issue 18 已有檢查（`mapProbeResult`）。

## 2. 修改
- 新增 `app/lib/library/epub_probe_result.dart`：`mapProbeResult` **原封不動**搬入（已逐字比對與原版本體相同）。
- `android_epub_metadata.dart`：改為 import 並 `export ... show mapProbeResult`（既有 import、測試不必改）；移除因搬移而無用的 `dart:convert`。
- `windows_epub_metadata.dart`：改呼叫 `mapProbeResult(resultJson)`，刪除自己的解析區塊。Windows 回傳 Map 因此多一個 `coverType` 鍵，與 Android 一致；既有消費端測試不受影響。
- 新增 fixture `test/fixtures/metadata/meta_cover_xhtml.epub`（`<meta name="cover">` 指向 XHTML manifest 項目，用 Python `zipfile` 合成，已於 `pubspec.yaml` 註冊）與 Windows 整合測試「封面為 XHTML 頁時拒收封面」。

## 3. 驗證
| 項目 | 結果 |
|---|---|
| 新整合測試修前 | 紅燈：`coverBytes` 為 `<?xml…` 的位元組（XHTML 被當封面） |
| 新整合測試修後 | 通過（`coverBytes == null`、`coverType == application/xhtml+xml`） |
| Windows 整合測試檔（原 13 份 EPUB ＋ 新案例） | 2 項全通過；原 13 份的封面有／無結果不變 |
| `android_epub_metadata_test` ＋ `windows_book_metadata_test` ＋ `windows_epub_range_test` | 32 項通過 |
| `flutter analyze` | 乾淨 |
| 全套 `flutter test` | 5167 通過、2 跳過 |

## 4. 書庫掃描與限制
- 掃描方式：複製 `Documents/library.db` 到暫存、以檔頭魔術位元組判斷每本 `coverPath`，唯讀。
- 結果：這台 Windows 書庫**只有 1 本書**（EPUB、PNG 封面、正常）。**樣本不足，無法證明 Windows 使用者沒有人中招**；人類確認沒有其他 Windows 書庫可掃。
- 本 Issue 只擋**新匯入**；若已有書存了壞封面，不會自動修正（有需要另立項目）。
- fixture 為合成案例（人類已接受，找不到真書）；真實書籍是否會觸發同樣路徑未實測。
- 接線由整合測試（真實 WebView）涵蓋，沒有純單元測試能證明 Windows 函式呼叫了 `mapProbeResult`。
