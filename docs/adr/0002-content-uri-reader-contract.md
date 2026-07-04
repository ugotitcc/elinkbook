# ADR 0002：原生讀取契約擴充支援 content:// URI

## 狀態

已採納

## 背景

`epic-0-skeleton` 建立的 `EpubReaderView`/`PdfReaderView` 原生契約中，`openBook(path)` 只接受真實檔案系統路徑（見 `CLAUDE.md`「`ReaderScreen`：唯一的閱讀器 seam」一節）；當時的範例書籍是把 Flutter asset 複製為裝置暫存目錄中的真實檔案後才呼叫。

`epic-1-library` 需要實作本機檔案匯入（FR-02 本機部分）。在 Discovery 階段討論匯入時是否要把使用者選擇的檔案複製一份到 App 私有目錄時，考量到：

- 100MB 以上的 PDF、多本書籍匯入會造成可觀的雙倍儲存空間佔用。
- Android 11+（API 30）的範圍儲存（Scoped Storage）下，透過 SAF（Storage Access Framework）選檔取得的是 `content://` URI，而非檔案系統路徑。
- 未來雲端匯入（Google Drive/OneDrive，留給後續 Epic）本來就必須先下載到本機才能開啟，屆時複製到 App 私有目錄是必要行為，與本機匯入的情境本質不同。

因此本機匯入決定「不複製、直接引用原始檔案」，但這代表 `filePath` 契約必須能承載 `content://` URI，而不只是檔案系統路徑。

## 決策

把 `EpubReaderView`/`PdfReaderView` 的原生讀取契約，從「只接受真實檔案系統路徑」擴充為「接受檔案系統路徑或 `content://` URI 字串」：

- **EPUB**：原生端 Readium 的 `Publication.open()` 改用 Android `Uri` 開啟（Readium 原生支援以 `Uri` 開啟資源，無需先轉成檔案路徑）。
- **PDF**：原生端改用 `ContentResolver.openFileDescriptor(uri, "r")` 取得 `ParcelFileDescriptor`，餵給既有的 `android.graphics.pdf.PdfRenderer`（`PdfRenderer` 建構子本來就接受 `ParcelFileDescriptor`，不要求一定來自檔案路徑）。
- Dart 端 `ReaderScreen(filePath: String)` 與 `detectBookFormat()` 的公開介面簽章不變；`filePath` 參數的語意由「檔案系統路徑」擴充為「檔案系統路徑或 content URI 字串」，`detectBookFormat()` 依副檔名/MIME 判斷格式的邏輯不受影響（URI 路徑最後一段仍含副檔名或可查詢 MIME）。
- 匯入時透過 SAF 取得的 URI，於原生端呼叫 `ContentResolver.takePersistableUriPermission()`，讓讀取權限跨越 App 重啟仍然有效。
- 新增獨立的原生 `MethodChannel`（`elinkbook/book_metadata`）供圖書庫匯入流程一次性提取詮釋資料（標題/作者/封面），與 `openBook`/`onPageRendered`/`onError` 這組既有的 `PlatformView` 渲染契約分開，避免混淆「渲染用途」與「詮釋資料提取用途」兩種不同的原生呼叫。

## 後果

- Android 端 `EpubReaderView.kt`/`PdfReaderView.kt` 需要新增 URI 路徑判斷分支（同時保留原本檔案路徑分支，供未來雲端匯入下載後的本機複本使用）。
- 若原始檔案被使用者於系統層級移動、刪除，或 SAF 權限因故失效，`openBook` 會透過既有的 `onError(message)` 回呼失敗，`ReaderScreen` 走既有錯誤路徑（`Key('reader_error_text')`）；圖書庫 UI 需另外處理「檔案無法存取」的書架列表項目顯示（`epic-1-library` `spec.md`/issue 範疇）。
- `integration_test/` 需要新增涵蓋 content URI 路徑的渲染驗證案例，不能只測原本的檔案路徑案例。
- 這是對 `epic-0-skeleton` 已定案 seam 的擴充而非取代——原本檔案路徑的呼叫方式仍完全有效，供測試 fixture 與（未來）雲端匯入下載後的本機複本使用。

## 曾考慮的替代方案

- **一律複製到 App 私有目錄，`filePath` 契約維持只接受檔案路徑**：不需異動原生契約，實作最單純，但每本匯入書籍都會佔用雙倍儲存空間，且與「本機檔案」情境下使用者通常不希望重複佔用空間的預期不符，予以排除。
- **依賴 `file_picker` 套件預設行為（自動把選中檔案複製到 App cache 目錄並回傳快取路徑）**：不需異動原生契約，但快取檔案位於系統可隨時清除的 cache 目錄而非持久化儲存，日後可能因系統清除快取導致書籍「消失」而需重新匯入，穩定性不如「持久化複製」或「content URI + persistable permission」兩者，予以排除。
