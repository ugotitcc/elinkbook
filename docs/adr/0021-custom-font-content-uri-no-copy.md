# 自訂字型比照 ADR 0002：不複製檔案，透過 content:// URI + 既有內建字型服務模式即時讀取

`epic-14-system-settings`（FR-35，自訂字型上傳/管理/刪除）需要決定使用者上傳的字型檔案要不要複製進 App 私有目錄。ADR 0002 已對書籍檔案本身做過同樣的權衡，並決定「不複製、直接引用原始檔案」（`takePersistableUriPermission()` + 原生端直接以 `Uri`/`ParcelFileDescriptor` 開啟），理由是避免雙倍儲存空間佔用。字型檔面臨完全相同的取捨，決定比照同一決策：

- `custom_fonts` 表的 `fontUri` 欄位存 `content://` URI（非本機複本路徑），上傳時只做 `takePersistableUriPermission()`。
- **EPUB 渲染是唯一套用自訂字型的路徑**（PDF 為原生點陣圖渲染，不套用字型設定，不受影響）。目前所有 EPUB（流式與 FXL）皆由 Dart 端 `foliate_epub_reader_view.dart` 搭配 `InAppWebView`（`flutter_inappwebview`）呈現，並無對應的原生 Kotlin `EpubReaderView`／`addFontFamilyDeclaration` 可供註冊（該路徑已隨 `epic-20-fxl-foliate-migration` 汰換）。現有 5 款內建字型的服務機制是：`foliate_native_bridge.dart` 的 `buildFontFaceCss()` 產生指向虛擬路徑（`https://appassets.androidplatform.net/assets/fonts/...`）的 `@font-face` 規則，`foliate_epub_reader_view.dart` 的 `_shouldInterceptRequest` 攔截該路徑請求，呼叫 `loadFlutterFontAsset()` 從 Flutter asset bundle 讀取位元組回傳——**每次請求即時讀取，不落地快取**。
- 自訂字型比照同一模式擴充：`buildFontFaceCss()` 新增自訂字型的 `@font-face` 規則（新虛擬路徑前綴）；`_shouldInterceptRequest` 新增對應分支，呼叫原生 `ReaderResourceChannel.kt` 新增的方法（例如 `readCustomFontBytes(uri)`），以 `ContentResolver.openInputStream(uri).use { it.readBytes() }` 一次性讀取後直接回傳，同樣不落地快取。**不使用** `WebViewAssetLoader.InternalStoragePathHandler`——該機制是 `ReaderResourceChannel.cacheBookForServing()` 專為書籍本體（可達 217MB）設計的原生檔案串流路徑，字型檔案（數十 KB 至數 MB）沿用既有的「Dart 攔截＋一次性讀取位元組」模式即可，混用書籍專用的快取型機制反而引入不必要的複雜度。

## Considered Options

- 複製進 App 私有目錄（`epic-6-annotations`／書籍封面既有模式）——實作最單純，但與 ADR 0002 對書籍檔案的既有決策精神矛盾（同一產品對「使用者選的檔案」採取兩套不一致的儲存策略），且字型檔可能不小、多款上傳一樣有雙倍空間問題，予以排除。
- 比照書籍本體使用 `WebViewAssetLoader.InternalStoragePathHandler` 落地快取——該機制是為 217MB 級大檔案設計，字型檔案量級小很多，沿用會多一層不必要的快取管理（快取失效時機、跨實例共用與否等），予以排除。

## Consequences

- 使用者事後在系統檔案管理員搬移或刪除原始字型檔會導致字型失效——與現有書籍檔案面臨的既有風險一致，非新增風險。
- 需要在 `ReaderResourceChannel.kt` 新增 `readCustomFontBytes` method，與既有 `readAndroidAsset`（同樣無快取、一次性讀取）同構；若換頁高頻重複請求同一字型造成明顯延遲，是否需要記憶體快取留待 Architecting 階段依實測評估。
