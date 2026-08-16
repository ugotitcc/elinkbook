# Epic 11 — 多格式閱讀擴充（KF8/CBZ/TXT/MD）：Issue 追蹤

## Issue 1：Spike——`mobi.js`／`comic-book.js`（`readest/foliate-js` 釘定 commit）能否正確開啟 KF8 (AZW3) 與 CBZ，KF8 DRM 位元組偵測可行性驗證

**Status:** `completed`（2026-08-16，GO——完整證據見 `reviews/spike-issue1-kf8-cbz-drm.md`）。

**判準分類：**
| 驗證項目 | 結果 |
|---|---|
| KF8 開書/渲染/導覽 | 通過 ✓ |
| KF8 × 直排覆蓋組合性 | 通過 ✓ |
| CBZ 開書/渲染（`pre-paginated`） | 通過 ✓ |
| CBZ 零填補頁序 | 正確 ✓ |
| CBZ 非零填補頁序 | 錯誤（預期）— 字典序排序 |
| CBZ RTL 覆蓋可行性 | 可行 ✓（僅驗證 `book.dir` 覆寫傳遞，導覽方向未驗證，見下方待落實事項 #2） |
| DRM 位元組偵測可行性 | 可行 ✓ |

**Architecting 階段待落實事項：**
1. CBZ 自然排序：需在匯入管線（Dart 端）對 CBZ 內部圖片檔名做自然排序後重新命名/重建索引
2. CBZ RTL 覆寫：需在 `main.js` 整合層依使用者偏好（PRD FR-43）於 `makeComicBook()` 之後設定 `book.dir`，**並確認 `goLeft()`/`goRight()`（或本專案既有 3×3 熱區 `ZoneAction` 分派邏輯）在 `book.dir='rtl'` 時實際回傳正確的翻頁方向**——Spike 的 Harness 熱區按鈕硬編碼呼叫 `view.prev()`/`view.next()`，並未走 `view.js` 真正處理 RTL 語意的 `goLeft()`/`goRight()`，只驗證了 `book.dir` 覆寫值能正確傳遞到 `view.book.dir`，尚未驗證使用者實際點擊熱區時 RTL 模式下翻頁方向是否正確（見 `reviews/review-issue-1-spike-execution.md` Important #1），此點在 Architecting／Issue 實作階段仍需補測
3. KF8 DRM 偵測：Dart 端直接採用 Task 5 驗證過的 offset（`ByteData.getUint16(record0Offset + 12, Endian.big)`），偵測到非 0 即拋出 `DrmProtectedException`

**測試素材補充說明**：KF8 測試未使用真實繁中直排公版書，改用 Standard Ebooks 英文公版樣本（The Time Machine）＋ CSS `transformTarget` 覆蓋模擬直排——理由是 KF8 特有風險在於容器解析（`mobi.js`），CJK 直排排版品質已由 `epic-17`/`epic-20` 用真實中文書證實、與格式來源無關，見 `plan-issue-1.md` Task 3「背景說明」。

**依賴：** 無（起始工單）。

**背景：** 見 `design.md`「Issue 1：前置驗證 Spike」。已用 GitHub API 查證本專案釘定的 `readest/foliate-js` commit（`dd71f2be356563c16a23272686189fcfb45d0b82`）確實包含 `mobi.js`／`comic-book.js`／`vendor/fflate.js` 三個檔案（production `app/android/app/src/main/assets/foliate/` 目前僅 vendor 既有 EPUB 所需的 10 個檔案，尚未包含這三個）。已逐一讀取這三個檔案原始碼，確認以下技術事實（供 Task 撰寫依據，非憑空假設）：
- `view.js` 的 `makeBook(file)` 對 KF8/MOBI／CBZ 皆為**全自動格式偵測**（KF8/MOBI 靠 magic bytes `file.slice(60,68) === 'BOOKMOBI'`，CBZ 靠副檔名/MIME `isCBZ()`），呼叫端不需要自己判斷格式。
- `mobi.js` 的 `MOBI` class 有自己獨立的 `transformTarget = new EventTarget()`（與 `epub.js` 同一機制），代表 `epic-17` Issue 1 已驗證過的「CSS 資源解析前注入 `writing-mode: vertical-rl`」技術應同樣適用於 KF8 內容。
- `comic-book.js` 的 `makeComicBook()` 對圖片檔名用**純字典序 `.sort()`**，**不是自然排序**（`design.md`/研究報告原先假設的「自然排序」並非 `comic-book.js` 內建能力）——若 CBZ 內部圖片檔名未零填補（例如 `1.jpg`…`10.jpg` 而非 `01.jpg`…`10.jpg`），頁序會出錯。
- `comic-book.js` 回傳的 `book` 物件**未設定 `book.dir`**，而 `fixed-layout.js` 的 RTL 判定完全依賴 `book.dir === 'rtl'`——代表 CBZ **沒有**任何內建/自動的 RTL 偵測，翻頁方向必須由呼叫端（我們的 `main.js`）在 `makeComicBook()` 之後、`view.open(book)` 之前手動設定 `book.dir`，不存在「讀取 CBZ 檔案本身判斷出這是日漫」這種機制。
- `mobi.js` 的 `PALMDOC_HEADER.encryption` 欄位位於 MOBI record 0 的 offset 12（2 bytes，`DataView` 未指定 `littleEndian` 引數，故為 **big-endian**），對照公開的 PalmDOC/MOBI 格式規格（0=無加密／1=舊版 Mobipocket 加密／2=Mobipocket 加密），`mobi.js` 本身**不會**因此欄位非 0 而拒絕開啟——DRM 偵測必須是我們自己獨立實作的檢查，不能依賴 `mobi.js` 拋出的例外。

**驗證範圍：**

1. **KF8 開書/渲染/導覽**：以 Standard Ebooks 提供的真實、DRM-free、公版授權 AZW3 檔案（已驗證下載連結有效，見 `plans/plan-issue-1.md` Task 2）驗證 `makeBook()` 能正確自動分派至 `mobi.js`、開書成功、`relocate` 事件正確觸發、`view.next()`/`view.prev()` 內容連續無跳過/重複（比照 `epic-17` Issue 1 判準）。
2. **KF8 × 直排 CSS 覆蓋組合性**：對 KF8 來源內容套用與 `epic-17` Issue 1 完全相同的 `transformTarget` 直排覆蓋技術，驗證能正確生效——目的是驗證「KF8 内容能否正確composed進已證實可用的直排管線」，**不是**重新驗證中文直排排版品質本身（該品質已由 `epic-17`/`epic-20` 用真實中文書籍證實，`paginator.js` 本身未因格式來源不同而有差異）。
3. **CBZ 開書/渲染/頁序**：以兩份自製 CBZ（零填補檔名 `001.jpg`…`010.jpg` 與非零填補 `1.jpg`…`10.jpg`）驗證實際頁面顯示順序，確認/推翻「純字典序排序在未零填補情境下會出錯」的既有查證結論；驗證 `book.rendition.layout === 'pre-paginated'` 確實觸發 `fixed-layout.js` 渲染路徑。
4. **CBZ RTL 覆蓋可行性**：驗證在 `makeComicBook()` 之後手動設定 `book.dir = 'rtl'`（模擬未來 `main.js` 依使用者偏好覆寫）能讓 `fixed-layout.js` 正確採用 RTL 翻頁行為。
5. **KF8 DRM 位元組偵測可行性**：以 Python 建構兩份合成的最小 PDB/MOBI 位元組緩衝區（`encryption=0` 與 `encryption=2`，**非真實/非受版權保護的書籍內容**，純粹是符合 PDB 標頭規格的最小可解析結構），驗證依 `mobi.js` 原始碼查證得出的 offset 邏輯（PDB header → 首筆 record offset → `+12` 兩位元組大端序）能正確且穩定地區分兩者。本項僅驗證位元組解析邏輯的可行性，**不驗證真實 Kindle DRM 檔案的端到端行為**（無法合法取得真實受 DRM 保護的樣本），正式 Dart 實作與真實檔案的端到端驗證留待 Architecting／後續 QA 階段。

**明確不在本 Issue 範圍**：完整遷移架構設計（`FoliateEpubReaderView` → `FoliateReaderView` 泛化重構、`Book.isFixedLayout`/`BookFileFormat` schema migration、TXT/MD 合成書籍結構匯入管線、`main.js` 正式整合 KF8/CBZ 分派邏輯）——這些留待 GO 之後的 Architecting 階段（`spec.md`）。

**GO/NO-GO 決策路徑：**
- **GO**（驗證範圍 1-4 全數通過；驗證範圍 5 的位元組解析邏輯驗證通過即可，不要求真實 DRM 檔案端到端驗證）：記錄結果，進入 Architecting 階段，`design.md`「GO 後續步驟」段落所列工作項目正式排入 Scrum Master 拆解。
- **NO-GO**（KF8 或 CBZ 開書/渲染核心判準任一失敗）：記錄具體失敗證據與根因，評估是否降級為「僅 CBZ 上線、KF8 另尋替代解析路徑」的縮小範圍方案（`design.md`「NO-GO」段落）。

**單元測試要求：** 無（研究/驗證性質，比照 `epic-17`/`epic-20` Issue 1 先例）。過程中產生的 harness 專案與素材（截圖/log/合成測試檔）驗證後需清理，不進版控（放 `tmp/`，已 gitignore）。

**驗收標準：**
- 真機以真實 KF8 樣本與自製 CBZ 樣本驗證，明確記錄各驗證項目的通過/失敗判定與依據（截圖或 log 佐證）。
- 明確記錄 CBZ 排序行為與 RTL 覆蓋可行性的實測結論（不論結果是否符合預期假設）。
- 依結果更新 `design.md`／本檔案對應狀態。

**相關佐證：**
- `docs/epics/epic-11-multi-format-reader/design.md`「問題陳述」「Issue 1：前置驗證 Spike」
- `docs/archive/2026-07-24-epic-17-epub-render-migration/plans/plan-issue-1.md`（Spike harness 既有先例，方法論參考，`transformTarget` 直排覆蓋技術原始出處）
- `app/android/app/src/main/assets/foliate/`（現有已 vendor 之 10 個檔案，本 Issue 新增 `mobi.js`／`comic-book.js`／`vendor/fflate.js` 三個）
- Readest `foliate-js` fork（`https://github.com/readest/foliate-js`），釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`：`view.js`（格式分派邏輯）、`mobi.js`（PALMDOC_HEADER／transformTarget）、`comic-book.js`（排序/RTL 行為）、`fixed-layout.js`（`book.dir` RTL 讀取點）

---

## Issue 2：KF8 (AZW3) 匯入與閱讀

**Status:** `merged`（2026-08-16，PR [#152](https://git.jigong.org/huthief/elinkBook/pulls/152) 已合併至 `main`，commit `1c42815`）。

**完成摘要：**
- `FoliateEpubReaderView` 泛化改名為 `FoliateReaderView`，服務全部 Foliate 格式
- `BookFormat.azw3`／`BookFileFormat.azw3` 新增完成，`reader_screen.dart` 格式分派擴充
- Vendor `mobi.js`／`vendor/fflate.js` 已下載至 `app/android/app/src/main/assets/foliate/`
- 純 Dart KF8 metadata／封面／DRM 擷取器實作完成（`app/lib/library/kf8_metadata.dart`）
- 匯入管線接上 KF8 metadata/DRM 擷取（`book_import_service_impl.dart`）
- `flutter test`（1305 tests）／`flutter analyze`（0 issues）全數通過

**程式碼審查發現並修復（合併前，`reviews/review-issue-2.md`／`reviews/review-issue-2-verification.md`）：** 初版「完成」宣告當時尚未經過審查即記錄於此，事後審查發現 2 項 Critical 缺陷——**C1**：`extractKf8Metadata()` 對 `content://` URI（標準 Android 檔案選擇器匯入 AZW3 的常見情況）原本只丟 `UnimplementedError`，DRM 偵測與 metadata/封面擷取全部失效；**C2**：`ReaderScreen._resolveEpubEngineDispatch()` 對 azw3 且 `isFixedLayout` 為 null 時，`_dispatchedIsFixedLayout` 永遠停留 null，`FoliateReaderView` 永遠無法建構——兩者疊加，透過標準匯入流程匯入的 AZW3 書籍在修復前**完全無法開啟**（匯入看似成功，開書必卡在載入畫面逾時後跳錯誤），比原始審查報告描述的「metadata 降級」嚴重得多。另有 2 項 Important（I1：真機整合測試繞過匯入管線與 `ReaderScreen` 分派邏輯，未能覆蓋 C1/C2 實際發生的路徑；I2：`_extractFromLocalFile()` 缺乏欄位層級錯誤隔離）一併修復。修復後新增 7 筆迴歸測試，`flutter test` 全專案 **1312 tests** 全數通過；真機整合測試（含 I1 修復新增、改走 `BookImportService`→`ReaderScreen` 的第二個測試）於裝置 `3CEF42ECD491687` 重新執行，**2/2 通過**，確認修復在真機端到端有效。

**已知殘留風險：** KF8 若透過 EXTH `fixedLayout` 標籤宣告為固定版面，其 `_dispatchedIsFixedLayout` 判斷時機與既有 EPUB FXL 邏輯共用同一套機制，但本 Issue 的驗收標準與測試 fixture（`sample.azw3`，reflowable）皆未涵蓋 KF8 FXL 這個子情境的真機驗證深度——若後續真機測試發現 KF8 FXL 書籍有分派時機問題，另立追蹤工單。

**依賴：** Issue 1（Spike GO）。

**背景：** `spec.md`「格式偵測與渲染分派」「KF8 (AZW3) 支援」。KF8 本質是 EPUB3 衍生格式，透過 `mobi.js` 解出內容後直接繼承既有 EPUB 渲染管線的直排/避頭尾/CFI/劃線/書籤/目錄/同步能力，不需要新增格式專屬的閱讀功能程式碼——本 Issue 的工作集中在「解析與匯入」這一側。

**範圍：**
1. `FoliateEpubReaderView`（`app/lib/reader/foliate_epub_reader_view.dart`）泛化重構為 `FoliateReaderView`，服務全部 Foliate 格式；`CLAUDE.md`「`ReaderScreen`」架構小節同步更新。後續 Issue 3-5 直接沿用此重構結果，不再重複改名。
2. Vendor `mobi.js`／`vendor/fflate.js` 至 `app/android/app/src/main/assets/foliate/`（已由 Issue 1 Spike 驗證存在於釘定 commit 且可正確運作）。
3. `BookFormat`（`app/lib/reader/book_format.dart`）新增 `azw3`；`BookFileFormat`（`app/lib/library/models/library_enums.dart`）新增 `azw3`（依副檔名命名慣例）；`ReaderScreen` 對 `azw3` 一律建構 `FoliateReaderView`。
4. 純 Dart KF8 metadata／封面擷取器：讀取 PDB/EXTH 標頭取得 title／author，讀取封面圖片所在 Image Record 取得封面位元組，比照現有 `extractMetadata` method channel 回傳格狀一致的介面供 `book_import_service_impl.dart` 消費。
5. KF8 DRM 位元組偵測：讀取 `PALMDOC_HEADER.encryption`（record 0 內 offset 12、2 bytes、大端序，`ByteData.getUint16(offset, Endian.big)`），非 0 即拋出 `DrmProtectedException`，匯入管線攔截、中止該書匯入、不寫入 `Book` 記錄，UI 顯示友善錯誤訊息。
6. `Book.isFixedLayout` 廣義化 KF8 分支：依書本 metadata 判斷（沿用與 EPUB 相同的 `rendition:layout` 判讀邏輯）。

**單元測試要求：** metadata／封面／DRM 擷取器以 `flutter test` 對真實 Standard Ebooks AZW3 樣本與合成 DRM 位元組緩衝區驗證（比照 `book_content_fingerprint_test.dart` 對 `computeBookContentFingerprint()` 的測試模式，直接斷言函式回傳值，`encryption=0/1/2` 三種情境皆需覆蓋）；`FoliateReaderView` widget-level 測試涵蓋建構參數傳遞與狀態機轉換（比照既有 `foliate_epub_reader_view_test.dart`）。

**驗收標準：**
- 真機 `integration_test` 匯入並開啟真實 AZW3 檔案，直排/避頭尾正確、目錄/書籤/劃線/同步皆正常運作（驗證繼承自既有 EPUB 機制、無需額外開發）。
- 合成 DRM 樣本正確觸發攔截，不建立 `Book` 記錄，UI 顯示友善錯誤訊息。
- `flutter test`／`flutter analyze` 全數通過。

**相關佐證：** `spec.md`「格式偵測與渲染分派」「KF8 (AZW3) 支援」章節、ADR 0023、`reviews/spike-issue1-kf8-cbz-drm.md`。

---

## Issue 3：CBZ 匯入與閱讀（含翻頁方向切換 RTL/LTR）

**Status:** `merged`（2026-08-16，PR [#153](https://git.jigong.org/huthief/elinkBook/pulls/153) 已合併至 `main`，commit `4b712ac`）。

**完成摘要：**
- Vendor `comic-book.js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`）
- `BookFormat`／`BookFileFormat` 新增 `cbz`，`isFoliateFormat()` 擴大涵蓋，`reader_screen.dart` 三處既有 `switch (format)` 合併 case
- 純 Dart `cbz_import.dart`：`compareNaturalOrder()` 自然排序比較器（`comic-book.js` 本身僅字典序排序）＋ `prepareCbzForImport()` 對壓縮檔內圖片重新命名重建（`page_0001.<ext>` 起算）與封面擷取；CPU 密集的解壓/排序/重建外包至 `Isolate.run()` 背景執行
- **CBZ 開書前置修復（規劃階段查證發現，先前 design.md/spec.md/issues.md 皆未記錄）**：`ReaderResourceChannel.kt`／`main.js` 原本把 WebView 書籍快取寫死為 `current.epub`，導致 `view.js` 的 `isCBZ()` 副檔名/MIME 判斷恆為 false、CBZ 開書必然被誤判為 EPUB 失敗——已修復為快取檔名反映書籍真實副檔名
- `FoliateReaderView` 新增 `isComicBookHint`／`dualPageDirection` 參數，`main.js` 於 `view.open(book)` 之前依偏好設定 `book.dir`（`fixed-layout.js` 的 `next()`/`prev()` 已正確依 `book.dir` 決定方向，不需新增任何導覽分派邏輯，明確補齊 Issue 1 Spike「未驗證導覽方向」的缺口）並覆寫虛擬頁碼目錄
- `FxlSettingsSheet` 新增翻頁方向（RTL/LTR）設定，重用既有 `DualPageDirection`（原僅 PDF 適用）
- `Book.isFixedLayout` 對 CBZ 恆為 `true`，劃線/備註入口與橫向雙頁皆透過既有 FXL 機制自動繼承，零額外程式碼
- 檔案選擇器 `allowedExtensions` 新增 `cbz`，並依人類指示一併補上 Issue 2 遺留的 `azw3` 缺口
- `flutter test`（1341 tests）／`flutter analyze`（0 issues）全數通過；真機整合測試 2/2 通過（匯入開書＋RTL 導覽方向）

**程式碼審查發現並修復（合併前，`reviews/review-issue-3-plan.md`／`reviews/review-issue-3.md`）：** 實作前計畫審查採納「大型 CBZ 記憶體佔用」（`prepareCbzForImport()` 核心運算改包 `Isolate.run()`）與「自然排序大小寫容錯」兩項建議，查證後不採納「`archive` 套件 `readBytes()` 回傳型別疑慮」（已直接讀取已安裝套件原始碼核實型別正確）。實作完成後程式碼審查發現 4 項 Important——**#1**：`ReaderScreen._resolveEpubEngineDispatch()` 缺少計畫要求的 CBZ 防禦分支，與 Issue 2 Critical C2 同一類「`isFixedLayout` 為 null 時永遠卡在載入畫面」地雷（潛伏未發作，因匯入流程已一律寫入 `true`）；**#2**：真機 RTL 導覽方向測試原本只驗證「沒有跳錯誤」，未真正斷言翻頁方向，與 issues.md 明文要求有落差；**#3**：`manual_import_acceptance_test.dart` 的 `allowedExtensions` 未依計畫同步更新；**#4**：CBZ 匯入單元測試缺少 `isFixedLayout`／`contentFingerprint` 計算來源斷言——這正是本 Issue 過程中真實發生過的回歸類型（`c7da43f`）。另有 1 項 Minor（`ReaderResourceChannel.kt` 的 `extension` 引數加白名單驗證）一併修復。全部修復後 `flutter test` 全專案 **1341 tests** 全數通過（較審查當下的 1339 增加 2 個，對應 Important #1／#4 新增的測試），Kotlin 端另以 `./gradlew compileDebugKotlin` 確認編譯成功。審查報告也記錄了一項流程面觀察：發現兩處「plan checkbox 已勾選 `[x]`，但實際 diff 找不到對應程式碼／測試」的具體案例，供後續 Issue 執行時借鏡（逐一核對 `git diff` 而非批次勾選）。

**已知殘留風險：** Important #2 修復後的 RTL 真機測試改為讀回 `ReadingPosition` 解析 locator index 斷言方向，程式碼已通過 `flutter analyze` 型別檢查，但該項變更本身因需要真機執行，未在本次修復流程中重新於真機上實測驗證（沿用先前真機驗證的整體流程結果）；Minor（CBZ 解壓無檔案大小上限）為既有已知取捨，非新發現，留待未來視情況評估。

**依賴：** Issue 2（需要已泛化的 `FoliateReaderView`）。

**背景：** `spec.md`「CBZ 支援」。`comic-book.js` 已用 Issue 1 Spike 真機驗證可正確開書並觸發 `fixed-layout.js` 渲染路徑，但**沒有**自然排序、**沒有**內建 RTL 偵測，兩者皆須由本 Issue 的匯入/整合層補上。

**範圍：**
1. Vendor `comic-book.js` 至 `app/android/app/src/main/assets/foliate/`。
2. `BookFileFormat` 新增 `cbz`。
3. `Book.isFixedLayout` 對 CBZ 恆為 `true`；復用既有 `FxlSettingsSheet`（`epic-20` 產物），新增翻頁方向設定選項（RTL/LTR）。
4. 匯入管線（Dart 端）對 CBZ 內部圖片檔名做自然排序，依排序結果重新命名/重建壓縮檔內部索引（不依賴 `comic-book.js` 內建排序）；封面固定取排序後第一張圖片。
5. 虛擬頁碼目錄（「第 1 頁」～「第 N 頁」，依自然排序後順序自動生成）。
6. `main.js` 依使用者於 `FxlSettingsSheet` 設定的翻頁方向偏好，於 `makeComicBook()` 之後、`view.open(book)` 之前設定 `book.dir`；**並確認 `goLeft()`/`goRight()`（或本專案既有 3×3 熱區 `ZoneAction` 分派邏輯）在 `book.dir='rtl'` 時對使用者實際點擊熱區回傳正確的翻頁方向**——明確補齊 Issue 1 Spike 只驗證 `book.dir` 傳遞、未驗證導覽方向這個缺口（`reviews/review-issue-1-spike-execution.md` Important #1）。
7. UI 隱藏劃線/備註相關入口（比照既有 FXL 圖像無文字節點的既定限制），不顯示後點擊無反應。
8. 橫向雙頁顯示直接復用 `epic-20` 既有的 EPUB FXL 雙頁/封面獨立顯示/`fixed-layout.js` spread 配對機制。

**單元測試要求：** CBZ metadata／自然排序以 `flutter test` 對自製 fixture（含至少一份零填補、一份非零填補檔名的變體）驗證；**RTL 導覽方向須有明確測試覆蓋，不可只驗證 `book.dir` 覆寫值傳遞**——測試須斷言使用者觸發熱區動作後的實際翻頁結果（頁碼/索引變化方向），比照既有 `ZoneAction` 相關測試模式。

**驗收標準：**
- 真機 `integration_test` 開啟自製 CBZ（含非零填補檔名樣本）頁序正確、封面正確。
- 翻頁方向切換為 RTL 後，實際點擊左/右熱區的翻頁方向正確（非僅 `book.dir` 值正確）；切回 LTR 恢復正常方向。
- 橫向雙頁模式正常；劃線/備註入口不顯示。
- `flutter test`／`flutter analyze` 全數通過。

**相關佐證：** `spec.md`「CBZ 支援」章節、`reviews/spike-issue1-kf8-cbz-drm.md`、`reviews/review-issue-1-spike-execution.md` Important #1。

---

## Issue 4：TXT 合成書籍結構與閱讀

**Status:** `ready-for-agent`

**依賴：** Issue 2（技術相依：需要已泛化的 `FoliateReaderView`）；`design.md` 決策 #12 建議待 Issue 2-3 完成後再開始（風險管理排序，非技術相依，可視團隊調度彈性處理）。

**背景：** `spec.md`「TXT／Markdown 合成書籍結構」。TXT 目前僅在圖書庫資料層存在（`BookFileFormat.txt`、`generateTxtCover()`），`app/lib/reader/book_format.dart` 的 `BookFormat` enum **完全沒有** `txt` 值，代表 TXT 目前無法被開啟閱讀——本 Issue 是 TXT 閱讀能力真正從零到有的實作，非既有功能的擴充。

**範圍：**
1. `BookFormat`（`book_format.dart`）新增 `txt`；`ReaderScreen` 對 `txt` 建構 `FoliateReaderView`。
2. TXT 編碼偵測：Big5 優先梯隊（`[utf8, big5, big5-hkscs, gbk, utf16]`），純 Dart 自建 Big5↔Unicode 對照表；編碼偵測、轉碼、分塊等運算包裝於 `Isolate.run()` 背景執行（比照 `book_content_fingerprint.dart` 既有作法）。
3. 正則章節/目錄抽取（常見「第 X 章/回/卷/節/集」、`Chapter N` 格式）。
4. 雙重分塊防護：優先依正則 TOC 切分章節，若無 TOC 或單一章節超過閾值（建議 300~500KB）依段落邊界次級分塊。
5. 匯入時落地轉換為合成書籍結構（EPUB/XHTML 相容），`Book.filePath` 指向衍生檔案，命名/存放以 book id 為鍵、獨立子目錄（比照 `book_import_service_impl.dart` 現有 `_landCover()` 以 `$bookId.png` 存於 `covers/` 子目錄的既有慣例）。
6. `contentFingerprint` 對「原始輸入檔案」計算，此計算須早於／獨立於合成轉換步驟，不可用合成後的衍生檔案路徑計算。
7. 合成檔案刪除清理：比照 `library_screen.dart` 既有 `coverPath` 刪除清理模式（`try`/`deleteSync()`、單筆失敗不中斷批次迴圈）。
8. `Book.isFixedLayout` 對 TXT 合成後恆為 `false`。

**單元測試要求：** 編碼偵測／分塊／TOC 抽取以 `flutter test` 對含 Big5 樣本的 fixture 驗證；`contentFingerprint` 計算順序須有回歸測試（斷言對原始檔案而非合成檔案計算）；刪除書籍時合成檔案清理須有對應測試（比照既有 `coverPath` 清理測試模式）。

**驗收標準：**
- 真機 `integration_test` 匯入 Big5 與 UTF-8 編碼的 TXT 檔案皆正確顯示、不亂碼。
- 大型 TXT（5MB~20MB 量級，無規範章節標記）開書流暢、不因超大 DOM section 卡頓或崩潰。
- 目錄正確產生；直排/橫排切換、劃線、書籤功能與 EPUB 一致。
- 刪除書籍後對應合成檔案從磁碟移除。
- `flutter test`／`flutter analyze` 全數通過。

**相關佐證：** `spec.md`「TXT／Markdown 合成書籍結構」章節、`app/lib/library/book_content_fingerprint.dart`、`app/lib/screens/library_screen.dart`（`coverPath` 清理模式）。

---

## Issue 5：Markdown (MD) 合成書籍結構與閱讀

**Status:** `ready-for-agent`

**依賴：** Issue 4（共用「合成書籍結構」基礎設施：檔案命名/清理模式、`contentFingerprint` 計算順序約束、匯入管線接線方式）。

**背景：** `spec.md`「TXT／Markdown 合成書籍結構」。MD 與 TXT 共用同一套「匯入時落地轉換為合成書籍結構」基礎設施，差異僅在預處理器本身（Frontmatter／標題階層 vs. 編碼偵測／正則章節）。

**範圍：**
1. `BookFormat`（`book_format.dart`）／`BookFileFormat`（`library_enums.dart`）新增 `md`；`ReaderScreen` 對 `md` 建構 `FoliateReaderView`。
2. YAML Frontmatter 解析：抽取標題／作者／封面；未指定封面時退回比照 TXT 既有的「依書名文字動態生成封面」機制。
3. 依標題階層（H1-H6）自動生成目錄。
4. `<pre><code>` 與表格強制注入 `writing-mode: horizontal-tb; direction: ltr;` 並提供橫向捲動，避免直排模式下破版。
5. 沿用 Issue 4 建立的合成書籍結構落地轉換／檔案命名／刪除清理／`contentFingerprint` 計算順序模式，不重新設計。
6. `Book.isFixedLayout` 對 MD 合成後恆為 `false`。

**明確不在本 Issue 範圍：** MD 內嵌本機相對路徑圖片（例如 `![](./img/1.png)`）的優雅降級——單檔匯入不會一併帶入該圖片資源，比照瀏覽器/WebView 對缺失圖片資源的既有預設行為（顯示破圖、不中斷分頁），不額外開發（`spec.md`「Out of Scope」）。

**單元測試要求：** Frontmatter 解析／標題階層 TOC／code-block-table CSS 隔離以 `flutter test` 對自製 `.md` fixture 驗證。

**驗收標準：**
- 真機 `integration_test` 匯入 MD 檔案正確渲染，Frontmatter 標題/封面正確顯示。
- 程式碼區塊與表格在直排模式下維持橫排、可橫向捲動閱讀。
- 標題階層目錄正確產生；直排/橫排切換、劃線、書籤功能與其他格式一致。
- 刪除書籍後對應合成檔案從磁碟移除（沿用 Issue 4 機制）。
- `flutter test`／`flutter analyze` 全數通過。

**相關佐證：** `spec.md`「TXT／Markdown 合成書籍結構」「Out of Scope」章節。
