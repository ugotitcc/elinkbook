# Epic 66 — Issue 1 技術驗證報告（Windows 移植）

> 狀態：**部分完成**——條件 1～7 全數通過；Task 9 Step 6 存證截圖已存於 `assets/`；「大檔是否可行」的判定待使用者決定。大檔尖峰記憶體已量測（結論 1），但「對大檔是否可行」的判定待使用者決定。

## 7 項過關條件

| # | 條件 | 結果 | 證據 | 備註 |
|---|---|---|---|---|
| 1 | EPUB 在 WebView2 能開，直排與橫排都正確 | ✅ 通過 | Task 9 人工實測（使用者回報三本方向、翻頁皆正確）；`OpenBookTrace` 記錄；存證截圖 `assets/windows-horizontal-sample_horizontal.png`、`assets/windows-vertical-sample_declares_vertical.png` | 3 個 fixture 皆可開：已渲染距開書 419～996 ms。**首次實測曾逾時**，原因見「已知缺陷」第 1 項（Task 9a，`07d7a29d`）；224 MB 大檔也能開（約 4.7 秒） |
| 2 | 滑鼠拖曳能選字，並出現劃線工具列 | ✅ 通過 | Task 9 人工實測（使用者回報「選字、畫線工具好了」）；存證截圖 `assets/windows-highlight-toolbar-sample_declares_vertical.png`（直排 fixture，選字後工具列含三色、底線、複製、字典、備註） | 工具列出現已由截圖確認；曾用使用者自備商業書截圖確認，該圖含書籍內容，**不納入版控**，改以 fixture 重拍存證 |
| 3 | PDF 能開，頁數正確；`pdfrx` 算出第 0 頁封面 PNG | ✅ 通過 | `integration_test/windows_spike/pdf_cover_test.dart` | `pages=5` 與檔案 `/Count 5` 一致；`render()` → `createImage()` → `toByteData(png)` 開頭為 `89 50 4E 47` |
| 4 | `HeadlessInAppWebView` 用 foliate-js 讀出書名、作者、`identifier`、封面 | ✅ 通過（作者見備註） | `integration_test/windows_spike/headless_metadata_test.dart` | 輸出見下方 Metadata 結論；`author` 為 null 是 `sample.epub` 本身無 `dc:creator`，非解析失敗——作者欄位的實證需含作者的 fixture（可併入後續 Readium 對比 Issue） |
| 5 | 字典 MDX 的 WebView 能擋住所有外部網路 | ✅ 通過 | `integration_test/windows_spike/mdx_network_block_test.dart` | `javaScriptEnabled: false` + `shouldInterceptRequest` 全回 404：CSS／外圖／`<noscript>` 圖片全進回呼且全被擋；內嵌 `<script>` 未執行（標題未被改寫） |
| 6 | SQLite FTS5 搜尋可用 | ✅ 通過 | `integration_test/windows_spike/fts5_test.dart` | `sqflite_common_ffi` 建置含 FTS5；中文 `MATCH「直排繁體中文排版」` 命中 1 列 |
| 7 | `flutter_secure_storage` 能存取同步憑證 | ✅ 通過 | `integration_test/windows_spike/secure_storage_test.dart` | 寫入 `authToken` → 讀回相等 → 刪除後為 null |

執行方式：每支探針獨立 `flutter test integration_test/windows_spike/<檔名> -d windows`（全數 PASS）。注意：單次 `flutter test` 指定多個 integration test 檔的批次模式在 Windows 上會自第二支起報 `Error waiting for a debug connection`，需逐檔執行。

## 結論 1：送書方式

**攔截路線可行（Task 9 開書實測已確認）。** 3 個小 fixture 與 224 MB EPUB 皆經攔截供應並成功開啟，不需要 `shelf` 備案。

- `flutter_inappwebview_windows` 0.6.0 的 WebView2 `WebResourceRequested` 已接上 `shouldInterceptRequest`（計畫階段讀 C++ 原始碼確認，探針 4、5 實測證實：Dart 字串頁面、foliate 靜態資源、EPUB 檔案位元組都能由回呼供應並成功載入／解析）。
- 探針 5 證明「攔截供應書檔 + `view.js` 背景解析」整條路徑可走通——不需要 `shelf` 伺服器原型。`epic.md` 決策 15 的「攔截優先、伺服器備案」維持，備案不啟動（除非 Task 9 開書實測失敗且原因為攔截無效）。
- **大檔尖峰記憶體（Task 9 Step 4，實測）**：書為 224 MB EPUB（使用者自備），release 版（`flutter build windows --release`），取樣只計入 `elinkbook.exe` 及其子孫程序（7 個 `msedgewebview2.exe`），平均取樣間隔 0.09 秒（最大 0.68 秒）。

  | 時間點 | `elinkbook.exe` | WebView2（7 個子程序） |
  |---|---|---|
  | 開書前（基準） | 970 MB | 456 MB |
  | App 尖峰（20:53:45.43） | **3,341 MB** | 407 MB |
  | 合計尖峰（20:53:45.50） | 3,211 MB | 626 MB（合計 **3,837 MB**） |
  | WebView2 尖峰（20:53:46.13） | 1,543 MB | **1,755 MB** |
  | 回落後穩定（20:53:50 起） | 754 MB | 約 493 MB |

  - 尖峰持續約 3 秒：先 App 端升高（約 960 → 3,341 MB，約書檔的 11 倍），再轉到 WebView2 端，最後回落；開書後穩定值（754 MB）低於開書前，無明顯殘留。
  - debug 版同一本書的 App 尖峰為 3,282 MB，與 release 相近，**不是 debug 額外負擔造成**。
  - 限制：只量了 release 一次、debug 一次；沒有重複驗證尖峰是否穩定；沒有量 CBZ；機器的實體記憶體容量未記錄。
  - **「攔截對大檔是否可行」的判定：待使用者決定**（取決於要支援的最低機器規格）。若判定不可行，方向為改成分段服務或啟動 `shelf` 備案。
- 大檔注意事項（風險預告，非結論）：現行攔截實作 `readWindowsBookBytes` 是整檔讀進 `Uint8List`——200MB 檔會等量佔用 Dart heap，Task 9 的量測數字是判斷「攔截對大檔是否可行」的直接依據，若不可行需改為分段服務或啟動 `shelf` 備案。

## 結論 2：Metadata（foliate-js 輸出欄位）

探針 5 對 `test/fixtures/sample.epub` 的實際輸出（JSON，供後續 Readium 對比表使用；對比表依 `epic.md` 決策 7 留給後續 Issue）：

```json
{"title":"elinkBook 範例 EPUB","author":null,"identifier":"urn:uuid:00000000-0000-0000-0000-000000000001","layout":null,"coverType":"image/png","coverSize":73}
```

| 欄位 | 值 | 說明 |
|---|---|---|
| `title` | `elinkBook 範例 EPUB` | 對應 `dc:title`，非空 ✓ |
| `author` | `null` | `sample.epub` 無 `dc:creator`——fixture 限制，非解析缺陷；作者欄位待含作者 fixture 驗證 |
| `identifier` | `urn:uuid:00000000-0000-0000-0000-000000000001` | 對應 `dc:identifier`，非空 ✓；`book_content_fingerprint.dart` 優先使用的鍵 |
| `rendition.layout` | `null` | `sample.epub` 未宣告 `rendition` → foliate 回 null（流式預期值） |
| 封面 | `image/png`，73 bytes | `cover-image` 屬性指向 `cover.png`，`getCover()` Blob 有效（size > 0 ✓） |

foliate-js 欄位型別備忘（Task 11 對比表參考）：`metadata.title` 為 language map（`sample.epub` 單一語系時 tidy 成字串）；`metadata.creator` 單筆時為物件（`{name, sortAs, role, code}`）、多筆時為陣列；`metadata.identifier` 為字串。

## 結論 3：啟動鏈 `MissingPluginException` 與處置

以下為程式碼層面已處置、Task 3／7／8／9a 已提交的項目；Task 9 實跑補充的清單見表後。

| 來源 | 觸發時機 | 處置 | Commit |
|---|---|---|---|
| `AudioSession` / `AudioService.init()`（決策 16） | `main.dart` 啟動鏈 | Windows 分支直接跳過，不呼叫 | `a02b332` |
| `elinkbook/volume_key`（`attachReaderView`/`detachReaderView`） | 開書／離書 | Windows 早退，不呼叫 channel | `20d33a8` |
| `elinkbook/reader_resources`（`readAndroidAsset`/`readCustomFontBytes`） | 送書／字型載入 | Windows 改走 Dart 讀執行檔旁 `data/` 與本機檔案 | `20d33a8` |
| `elinkbook/book_metadata`（`extractMetadata`） | 檔案匯入 | `MissingPluginException` 與 `PlatformException` 同樣降級：標題退回檔名、無封面、不中斷匯入；EPUB 指紋退回整檔 SHA-256 | `5e591b1` |

Task 9 實跑（debug 與 release 版）記到的 `MissingPluginException`：

| 來源（channel／method） | 觸發時機 | 是否擋住開書 | 處置 |
|---|---|---|---|
| `elinkbook/book_metadata`／`detectEpubLayout` | 開尚未判斷版面的 EPUB | **是**——`ReaderScreen` 只有 `.then()` 沒接錯誤，畫面卡在載入圖示直到 30 秒逾時 | 已修（Task 9a，`07d7a29d`）：降級為流式（`false`），不寫入資料庫 |
| `flutter_inappwebview_manager`／`getDefaultUserAgent` | 啟動時讀 WebView 版本 | 否 | 未處置（只影響版本顯示） |
| `elinkbook/fullscreen`／`setEnabled` | 進入、離開閱讀畫面 | 否 | **未處置**（未捕捉的非同步例外，每次進出閱讀畫面都會記一次，記錄雜訊多） |
| `elinkbook/volume_key`／`notifyLeavingReader` | 離開閱讀畫面 | 否 | **未處置**（同上） |

## 已知缺陷（驗證期間發現）

- **Windows 首次開書逾時（已修）**：Task 9 首次實測，開 EPUB 卡在載入圖示、30 秒後 `OpenBookTrace` 記錄「開書逾時 沒有任何階段記錄」。根因是 `detectAndCacheEpubLayout()` 在 Windows 丟 `MissingPluginException` 而呼叫端未接錯誤（見結論 3 表）。這**不是攔截失效**，不需要 `shelf` 備案。Task 8 讓「匯入」對缺少 metadata 頻道降級，但漏了「開書時補判斷版面」這條路，是計畫的缺口。已由 Task 9a（`07d7a29d`，含失敗測試）修正。
- **`fullscreen.setEnabled`／`volume_key.notifyLeavingReader` 的未捕捉例外尚未處置**：目前不影響功能，但會在每次進出閱讀畫面時刷錯誤訊息。是否納入本 Issue 或後續 Issue 待決定。

- `flutter_inappwebview_windows` 0.6.0 原生端 `webview_channel_delegate.cpp:91` 的 `getTitle` 分支誤呼叫 `getUrl()`——Dart 端 `getTitle()` 回傳網址而非頁面標題。探針改用 `onTitleChanged`（`DocumentTitleChanged`，原生端正確）判斷標題。目前無需修外掛；若日後需要 `getTitle()`，需注意此缺陷。
- `flutter_inappwebview_windows` 無 `loadHtmlString`——HTML 字串一律由 `shouldInterceptRequest` 從本機網域提供（探針 4、5 的做法，與生產路徑一致）。

## 覆蓋範圍

- 條件 1、2 → Task 9（皆完成；Step 6 存證截圖已存於 `assets/`）；條件 3、4、5、6、7 → Task 10（已完成，commit `f955014`）。
- 審查修訂覆蓋見 `plans/plan-issue-1.md` 自我檢查（16→Task 3、17→Task 5、18→攔截路線不需要改、19→Task 7、20→Task 10 Step 1、23→Task 4、21→Task 8 最小版；22、24 留後續 Issue）。
