# Epic 4 — PDF 專業增強：工單清單 (Issues)

依 `spec.md`（搭配 `design.md`、`reviews/design-review.md`）拆解出的細粒度垂直切片工單。Issue 1 為起始工單；Issue 2 依賴 Issue 1；Issue 3、4、5 依賴 Issue 2，三者可平行進行；Issue 6 依賴 Issue 5（共用裁切分頁與 `PdfCropRect` 渲染套用邏輯）；Issue 7 為收尾工單，依賴 Issue 3、4、6 全部完成。

---

## Issue 1：資料層基礎建設——PDF 版面偏好設定儲存（已完成）

**Status:** ✅ 已完成。`PdfFitMode`／`PdfCropMode`／`PdfCropRect` 三個基礎型別、`BookReaderPrefs` 6 個新欄位、`book_reader_prefs` 資料庫 schema 升級至 version 3（含既有 version 2 裝置的 `ALTER TABLE` 升級路徑）、`BookReaderPrefsRepository` round-trip 驗證皆已完成。`flutter test`／`flutter analyze` 皆通過。完整計劃見 `plans/plan-issue-1.md`。

**依賴：** 無（起始工單）

**描述：**
建立本 epic 全部後續 issue 共用的資料模型與持久化機制，純 Dart、不涉及原生程式碼、不需要真實裝置：

- 新增列舉型別：`PdfFitMode`（`app/lib/reader/pdf_fit_mode.dart`，`pageFit`/`fitWidth`/`actualSize` 三值）、`PdfCropMode`（`app/lib/reader/pdf_crop_mode.dart`，`none`/`autoDetect`/`manual` 三值）
- 新增 `PdfCropRect`（`app/lib/reader/pdf_crop_rect.dart`）：不可變資料類別，`left`/`top`/`right`/`bottom` 皆為 0.0-1.0 相對座標，含 `toJson()`/`PdfCropRect.fromJson()`
- `BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`）新增 6 個 nullable 欄位：`pdfFitMode`／`pdfContrast`／`pdfBrightness`／`pdfBoldStrength`／`pdfCropMode`／`pdfCropRect`，`toMap`/`fromMap`/`==`/`hashCode` 依既有模式平行擴充（見 `spec.md`「資料模型」）
- `book_reader_prefs` 表新增上述 6 欄位（見 `spec.md` 的 SQL 定義），依裝置狀態分兩條路徑：全新安裝走 `CREATE TABLE`（`onCreate`）一步到位；既有 version 2 裝置走 `ALTER TABLE ADD COLUMN`（`onUpgrade`）逐欄補上，兩者互斥不重疊，`BookReaderPrefsRepository` 的既有 `load`/`save` 邏輯不需改動（全欄位 nullable、`Map` 驅動）

**單元測試要求：**
- 純 Dart unit test：`PdfFitMode`／`PdfCropMode` 為 `byName` 直接映射（無回退），比照 `BookReaderPrefs` 既有 5 個 enum 欄位（`AppFont`／`EpubTextAlign`／`WritingMode`／`PageTurnMode`／`ScreenOrientationSetting`）的既有慣例，不需要獨立測試檔（`byName` 失敗回退僅用於 `GlobalReaderDefaults`/`AppThemePreferences` 等 `shared_preferences` 設定，與本表無關）；`PdfCropRect` 建構、相等性、`toJson`/`fromJson` round-trip
- `BookReaderPrefs`：新 6 欄位的 `toMap`/`fromMap` round-trip；驗證 EPUB 讀取時 PDF 欄位恆為 `null`，反之亦然
- `BookReaderPrefsRepository`：既有 `save()`/`load()` round-trip 測試擴充涵蓋新欄位；資料庫 migration 後既有 EPUB 資料列不受影響（新欄位讀回 `NULL`）

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- 本 issue 完全不需要真實裝置即可驗收

---

## Issue 2：PDF 設定入口與 Fit 模式端到端（已完成）

**Status:** ✅ 已完成，但有兩項已知驗證缺口尚未補齊（見下方說明）。`PdfSettingsSheet` 三分頁骨架與顯示分頁（Fit 模式三選一）、`PdfReaderView`（Dart＋原生）的 `fitMode` 契約與三種縮放邏輯、`ReaderScreen` 齒輪按鈕擴充至 PDF 皆已完成，13 個 `integration_test`（含 3 個本 issue 新增）於真機（9491G，Android 15）全數通過，涵蓋「開啟設定→切換三種 Fit 模式→無 onError」與「切換設定→關閉重開→持久化值正確」兩類情境。刻意簡化：Fit Width／真實比例 1:1 超出畫面的部分不可捲動，留待後續 issue 評估。

**已知驗證缺口（未解決，留待後續補齊或追蹤）**：

1. **人工視覺確認完全未執行**：本次真機測試是無人值守的背景執行（headless CI 風格），計劃 `plans/plan-issue-2.md` Task 4 Step 2 要求的「人工視覺確認：Fit Width／真實比例 1:1 模式下，若 PDF 內容超出畫面，超出部分不可捲動，非崩潰或亂碼」**三種 Fit 模式皆未經肉眼確認**——13 個測試只驗證了「無 crash／無 onError／斷言通過」，沒有人實際看過畫面縮放結果是否「看起來正確」。這不只是下方冷啟動情境的問題，是三種模式的視覺結果整體都尚未經人工確認。
2. **`fitWidth` 冷啟動情境未驗證**：`PdfReaderView.kt` 的 `applyFitMode()` 在 `fitWidth` 分支依賴 `imageView.width` 於呼叫當下已完成量測；本 issue 的 3 個真機測試涵蓋的是「書本已渲染完成後才切換 fit 模式」與「重開書後檢查 Dart 端 `PdfReaderView.fitMode` 屬性值」，**並未涵蓋「開書當下 `initialPreferences` 就已經是 `fitWidth`（例如使用者上次關書前選的是 Fit Width，這次重新打開）」這個真正的冷啟動情境**——這正是原始碼註解裡標註「殘餘風險」所指的情況，本次測試設計沒有實際觸發也沒有排除它。若之後真機使用時發現「重開一本先前設定為 Fit Width 的書，第一次顯示沒有套用縮放（需要手動重新進設定才生效）」，需依原始碼註解的建議補上 `ViewTreeObserver.OnGlobalLayoutListener` 之類的重新量測機制，另立 issue 修正。

完整計劃見 `plans/plan-issue-2.md`。

**依賴：** Issue 1（需要 `PdfFitMode` 等型別供 map key 對應使用）

**描述：**
建立 PDF 專屬的設定入口與 method channel 骨架，並實作 Fit 模式（決策 #6/#7/#8）作為第一個端到端可驗證的功能：

- **Dart 端（`app/lib/reader/pdf_reader_view.dart`）**：新增 `fitMode: PdfFitMode?` 建構參數；`_onPlatformViewCreated` 把非 null 偏好參數組成 `initialPreferences` 隨 `openBook` 送出；新增 `didUpdateWidget` 偵測欄位變動、透過 `setPdfPreferences` 送出（合併語意，比照 EPUB `setPreferences` 慣例，見 `docs/archive/2026-07-10-epic-3-fonts-layout/spec.md`）
- **原生端（`PdfReaderView.kt`）**：`openBook` 新增 `initialPreferences: Map<String, Any?>?` 參數；新增 `setPdfPreferences` handler；`renderCurrentPage()` 依 `fitMode` 套用縮放邏輯——`pageFit`（明確設定等效於目前 `ImageView` 預設 `FIT_CENTER` 的行為，不再依賴隱式預設值）、`fitWidth`（頁寬滿版、可視高度不足時可捲動）、`actualSize`（1 PDF point = 1 Android dp，見 `design.md`「已知風險」的 DPI 定義）
- 新建 `PdfSettingsSheet`（`app/lib/screens/pdf_settings_sheet.dart`）骨架：三分頁結構（顯示／濾鏡／裁切），本 issue 只實作**顯示分頁**（Fit 模式三選一圖示按鈕），其餘兩分頁留空白佔位供 Issue 3-6 填入
- `ReaderScreen`（`app/lib/screens/reader_screen.dart`）：`_buildAppBarActions` 條件擴充為 `format == epub || format == pdf`；新增 `_openPdfSettings()`，依 `format` 分派開啟 `ReaderSettingsSheet`（EPUB，既有）或 `PdfSettingsSheet`（PDF，新增）；開書流程於 `format == pdf` 時載入 `BookReaderPrefs.pdfFitMode` 並傳給 `PdfReaderView`；新增 `_handlePdfPrefsChanged(BookReaderPrefs)`，`setState` 更新本地狀態並呼叫 `prefsRepository.save()`

**單元測試要求：**
- `PdfReaderView` widget test（假 `MethodChannel` handler）：`_onPlatformViewCreated` 呼叫 `openBook` 時 `initialPreferences` 正確包含 `fitMode`；`fitMode` 變動觸發 `setPdfPreferences`
- `PdfSettingsSheet` widget test：顯示分頁三選一切換正確觸發 `onChanged`
- `ReaderScreen` widget test：AppBar 齒輪按鈕於 `format == pdf` 時顯示；點擊後開啟 `PdfSettingsSheet`（非 `ReaderSettingsSheet`）
- **已知測試限制**：原生端 `setPdfPreferences`/縮放邏輯無法透過 `flutter test` 驗證，留給本 issue 的 `integration_test`

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- `integration_test`（真實裝置）：開啟 PDF、切換三種 Fit 模式，畫面依序正確反映；關閉重開該書後設定被記住

---

## Issue 3：影像濾鏡——對比度／亮度（bug 已修復並重新真機驗證）

**Status:** ✅ 真機視覺驗證發現的 bug 已診斷出根因並修復，重新完成真機視覺驗證。

**問題回顧**：Task 3 的真機人工視覺確認發現對比度/亮度濾鏡數值正確存入 UI 與資料庫，但畫面上沒有任何可辨識的視覺變化，即使推到最極端值（-100/-100，理論上應使整頁全黑）也毫無變化。

**根因（Task 4 診斷確認）**：**不是** Flutter PlatformView 合成或原生端重繪機制的問題（這條路徑經多組非對稱數值測試——如 `brightness=+100` 讓文字明顯洗白——直接證實完全正常）。真正的根因是 `PdfReaderView.kt` 的 `renderCurrentPage()` 用 `Bitmap.createBitmap()` 建立目的地 Bitmap 時預設**全透明**，而 `PdfRenderer.Page.render()` 只會畫出 PDF 內容本身有筆劃的像素，「空白背景」區域若 PDF 本身未明確畫白色矩形，會維持透明。`applyFilters()` 的 `ColorMatrixColorFilter` alpha 列是單位矩陣（保留原始 alpha），因此透明背景像素無論 contrast／brightness 設多少都不會產生視覺變化；疊加上「已經是黑色的文字像素在 -100/-100 這個特定組合下濾鏡後還是黑色」，兩者合起來造成「調到最極端值畫面卻毫無反應」的錯覺。

**修復**：在 `renderCurrentPage()` 建立 Bitmap 後、呼叫 `page.render()` 前，加入 `bitmap.eraseColor(Color.WHITE)`（正常路徑與 OOM 回退路徑皆補上）。`applyFilters()`／`setPdfPreferences()`／`openBook()` 等既有邏輯完全未變動——原本的資料流與呼叫時機本來就是對的，不需要任何「強制重繪」補丁。

**重新驗證（僅涵蓋對比度與亮度，未重測 Fit Mode）**：在真機（9491G／Android 15）上以 UI 滑桿實際操作至 -100/-100，畫面渲染為完整純黑矩形；並用像素級量化比對（基準 vs. 調整後，內容區域取樣 9120 點，7638 點／約 84% 色差顯著），確認修復有效。完整診斷過程、各假說驗證結果、迴歸測試證據見 `.superpowers/sdd/task-4-diagnose-report.md`。

**Issue 2（Fit Mode）評估**：本次根因與 Flutter 合成機制無關，屬像素 alpha 透明度問題，Fit Mode 的 `applyFitMode()` 只調整 `scaleType`／`imageMatrix`（座標變換層），不涉及像素色彩/alpha，因此不受同一根因影響，無需額外修復或重新驗證（診斷過程已間接證明重繪機制本身正常，此疑慮已排除）。

完整計劃見 `plans/plan-issue-3.md`；原始真機視覺驗證發現 bug 的記錄見 `.superpowers/sdd/task-3-report.md`；bug 診斷與修復記錄見 `.superpowers/sdd/task-4-diagnose-report.md`。

**依賴：** Issue 2（共用 `PdfSettingsSheet`／`setPdfPreferences` 骨架）；可與 Issue 4、5 平行開發

**描述：**
在 Issue 2 建立的 `PdfSettingsSheet` 濾鏡分頁新增對比度、亮度兩支控制項：

- **原生端（`PdfReaderView.kt`）**：`renderCurrentPage()` 渲染管線新增濾鏡套用階段（裁切 → fit 模式縮放 → 濾鏡，見 `spec.md`），對比度/亮度透過 `ColorMatrixColorFilter` 套用於 `imageView`
- **Dart 端**：`PdfReaderView` 新增 `contrast`／`brightness: double?` 建構參數（-100..100），納入 `initialPreferences`／`setPdfPreferences` 機制
- `PdfSettingsSheet` 濾鏡分頁新增對比度、亮度滑桿：依決策 #11，拖動時即時呼叫 `onChanged`（即時預覽），鬆手後才由 `ReaderScreen._handlePdfPrefsChanged` 寫入持久化（沿用「setState 立即反映、不 await 持久化」既有慣例）

**單元測試要求：**
- `PdfReaderView` widget test：`contrast`/`brightness` 變動觸發 `setPdfPreferences`
- `PdfSettingsSheet` widget test：兩支滑桿拖動時觸發 `onChanged`，數值正確傳遞

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- `integration_test`（真實裝置）：調整對比度/亮度後畫面持續渲染成功、無 `onError`；關閉重開後設定值正確記住
- **獨立驗證項（人工視覺 QA）**：對比度/亮度變化在真實掃描件 PDF 上的視覺效果符合預期

---

## Issue 4：影像濾鏡——加粗（已完成）

**Status:** ✅ 已完成。`PdfReaderView`（Dart＋原生）新增 `boldStrength` 契約，原生端以統一的手動像素陣列運算（縮小工作尺寸做膨脹再放大，涵蓋全部 API 24+，不分版本分支）實作型態學膨脹、`PdfSettingsSheet` 濾鏡分頁新增加粗強度滑桿皆已完成。**已知限制**：僅在 API 35 真機（9491G）驗證，未涵蓋 API 24-30 裝置（本專案目前無此範圍的可用測試裝置），但因實作本身不分 API 版本分支，風險已透過統一實作降低。真機自動化測試 17/17 通過（含新增的 2 個加粗強度測試：調整後持續渲染無 onError、關閉重開後設定正確記住）；截圖視覺比對結果——在真實直排中文 PDF（80KB 宗教願文文件）上，將加粗強度從 0 推到 100（滑動端點）後，原本清晰纖細的毛筆字筆畫在真機截圖上明顯變成大片實心黑色色塊，肉眼可見的極強烈加粗效果，確認濾鏡在真機上確實有視覺作用（不同於 Issue 3 對比度/亮度濾鏡曾出現的「零視覺效果」透明背景 bug）；拖動滑桿的主觀卡頓感受——連續快速點擊 10 次加粗強度 +10 按鈕（間隔約 200-300ms／次）後，畫面在最後一次點擊後約 200ms 內即完整渲染完成，未觀察到明顯凍結或 ANR，主觀可接受；惟原生端 `renderCurrentPage()` 在每次 `boldStrength` 變動時皆同步執行（無 debounce／背景執行緒卸載），對此次測試用的小型單頁 PDF 沒有造成明顯延遲，但對更大、更複雜的 PDF 頁面（例如 100MB+ 檔案）可能會有更明顯的延遲，尚未實測驗證，留意此為潛在後續優化點。完整計劃見 `plans/plan-issue-4.md`。

（Issue 7 收尾時再次確認：本開發環境全程僅有此台 API 35 裝置可用，無法在 epic 合併前補齊 API 24-30／其他 API 31+ 裝置的複驗，正式收斂為已知、已記錄的殘留風險，不阻塞本 epic 合併——若未來取得額外測試裝置，應優先執行此複驗。）

**依賴：** Issue 2（共用骨架）；可與 Issue 3、5 平行開發

**描述：**
在 `PdfSettingsSheet` 濾鏡分頁新增加粗（型態學膨脹）控制項。本 issue 技術風險明顯高於 Issue 3（設計審查 `reviews/design-review.md` Finding 1.1）——`minSdk = 24`，而 Android 高效能形態學運算 API `RenderEffect` 需 API 31，中間 7 個 API 版本需自行實作像素級膨脹運算，`ColorMatrix` 無法達成（僅逐像素線性色彩轉換，非空間鄰域運算）：

- 實作者需先依效能實測決定 API 24-30 的膨脹演算法（例如簡易卷積、限制在縮小取樣版本上運算等，見 `design.md`「已知風險」），並依決策 #13（NFR-1 不涵蓋濾鏡效能，允許翻頁後短暫延遲完成處理）驗證可接受度；若 API 31+ 裝置與 API 24-30 裝置需要不同實作路徑，需明確記錄於 `plans/plan-issue-4.md`
- **原生端**：`renderCurrentPage()` 濾鏡套用階段新增加粗處理（對已套用裁切/fit/對比度/亮度的最終 Bitmap 做膨脹）
- **Dart 端**：`PdfReaderView` 新增 `boldStrength: double?` 建構參數（0..1），納入既有偏好機制
- `PdfSettingsSheet` 濾鏡分頁新增加粗強度滑桿，互動模式同 Issue 3（即時預覽、鬆手持久化）

**單元測試要求：**
- `PdfReaderView` widget test：`boldStrength` 變動觸發 `setPdfPreferences`
- `PdfSettingsSheet` widget test：加粗滑桿拖動觸發 `onChanged`

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- `integration_test`（真實裝置，**至少涵蓋一台 API 24-30 裝置與一台 API 31+ 裝置**，若受限於可用測試裝置無法涵蓋兩者，需在 `plans/plan-issue-4.md` 明確記錄限制）：調整加粗強度後畫面持續渲染成功、無明顯卡頓或崩潰
- **獨立驗證項（人工視覺 QA）**：加粗效果在淡色掃描件 PDF 上是否有效改善可讀性；100MB 以上 PDF 啟用加粗後翻頁效能主觀可接受（決策 #13 寬鬆門檻，非量化門檻）

---

## Issue 5：智慧自動裁切（已完成）

**Status:** ✅ 已完成。`BookReaderPrefs.copyWith()`（回應 Issue 4 審查建議）、`PdfReaderView`（Dart＋原生）的 `cropMode`／`cropRect`／`onCropRectComputed` 契約、原生端單頁取樣邊界偵測演算法與裁切渲染管線整合（裁切 → fit 模式縮放 → 濾鏡/加粗，管線順序符合 spec.md 定案）、`PdfSettingsSheet` 裁切分頁不裁切/智慧自動二選項（手動選區停用預留 Issue 6）皆已完成。**已知限制**：僅在 API 35 真機（9491G）驗證，未涵蓋其他 API 版本裝置（同 Issue 4 已知限制，本專案目前無其他範圍的可用測試裝置）。真機自動化測試 19/19 通過（含新增的 2 個裁切測試：切換至智慧自動裁切後持續渲染無 onError、關閉重開後 `pdf_crop_rect` 不重新計算）。**截圖視覺比對**：`app/test/fixtures/sample.pdf`（既有範例）內容為完全空白頁面，無法用於裁切視覺比對，故另行產生一份僅供本次驗證用的暫時性 PDF 素材（400×560pt，四周 100pt 留白邊界＋置中黑色色塊與文字，未納入版本控制），驗證後即刪除；不裁切（基準）畫面顯示完整頁面、內容四周留有明顯白邊，切換至智慧自動裁切後畫面明顯放大填滿、白邊消失，肉眼可見裁切確實生效；切回不裁切後畫面恢復基準時的完整留白版面，未見殘留裁切痕跡。同時以原生端暫時性診斷 log（驗證後已移除，未入版控）交叉核對：偵測出的裁切矩形（left=0.24／top=0.169／right=0.7575／bottom=0.830）與素材實際留白比例（100/400=0.25、100/560≈0.179，含演算法 1% 邊距）高度吻合，裁切後渲染 bitmap（473×846，比例≈0.559）與內容區塊實際比例（200×360≈0.556）一致；「不重新計算」驗證——關閉重開該書後兩次查詢 `book_reader_prefs.pdf_crop_rect`，數值完全一致（`expect(secondRect, firstRect)` 通過）。**驗證過程曲折記錄（誠實揭露）**：驗證初期改用手刻的最小合法 PDF 作為視覺比對素材，出現「基準畫面即已呈現接近裁切後比例、看不出裁切前後差異」的異常結果；改用成熟函式庫（fpdf2）重新產生格式規範的等效測試 PDF 後，異常消失、行為與預期完全吻合，判定原異常為手刻 PDF 格式邊界情況觸發 Android `PdfRenderer` 的非預期解析行為（測試素材本身的問題，非本 issue 程式邏輯缺陷）；另外裝置在部分驗證回合中途發生螢幕自動旋轉，一度造成擷取到的截圖尺寸與畫面比例不可比對，後續已停用裝置自動旋轉排除此環境干擾因素。**尚未涵蓋的殘留風險（留意此為潛在後續觀察點）**：若使用者未來匯入的真實 PDF 存在類似非主流 PDF 產生器輸出的格式邊界情況，`PdfRenderer`（Android 系統元件）在該類檔案上的解析行為仍有不可預期的風險，非本 issue 程式碼可完全掌控；裁切偵測演算法目前僅在高對比合成素材（純黑色塊 vs 純白背景）上驗證，真實世界掃描件/照片式 PDF（灰階漸層、雜訊、輕微陰影）的偵測效果尚未實測驗證。完整計劃見 `plans/plan-issue-5.md`。

**依賴：** Issue 2（共用骨架）；可與 Issue 3、4 平行開發

**描述：**
實作裁切分頁的前兩個選項（不裁切／智慧自動），建立本 epic 的裁切渲染管線基礎，供 Issue 6（手動選區）複用：

- 實作者需依 `design.md`「已知風險」決定邊界偵測演算法（近似白/黑判斷閾值、取樣頁數）；設計審查 Finding 1.3 建議的「多頁取樣＋保守交集」為候選方案，非強制採用
- **原生端（`PdfReaderView.kt`）**：`cropMode = autoDetect` 且尚無快取矩形時，首次渲染時取樣計算，透過新增的 `onCropRectComputed` method channel（原生 → Dart）回傳；`renderCurrentPage()` 渲染管線新增裁切套用階段（依 `PdfCropRect` 調整 `PdfRenderer.Page.render()` 的 `Matrix` 平移/縮放，只渲染指定區域並放大填滿），置於 fit 模式縮放與濾鏡之前（決策已定案，見 `spec.md`）
- **Dart 端**：`PdfReaderView` 新增 `cropMode: PdfCropMode?`／`cropRect: PdfCropRect?` 建構參數、`onCropRectComputed: ValueChanged<PdfCropRect>?` callback
- `PdfSettingsSheet` 裁切分頁新增「不裁切」／「智慧自動」二選項（「手動選區」選項在 Issue 6 加入，本 issue 先不顯示或顯示為停用狀態）
- `ReaderScreen`：`onCropRectComputed` 觸發時寫入 `BookReaderPrefs.pdfCropRect`，避免下次開書重新計算

**單元測試要求：**
- `PdfReaderView` widget test：`cropMode`/`cropRect` 變動觸發 `setPdfPreferences`；收到原生端 `onCropRectComputed` 時正確觸發回呼
- `PdfSettingsSheet` widget test：裁切分頁二選項切換觸發 `onChanged`
- `ReaderScreen` widget test：`onCropRectComputed` 回呼正確寫入 `BookReaderPrefs` 並持久化

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- `integration_test`（真實裝置）：切換至智慧自動裁切，畫面正確裁切並套用；關閉重開該書，確認**不重新計算**（比對兩次 `book_reader_prefs` 查詢的 `pdf_crop_rect` 值一致）

---

## Issue 6：手動選區裁切（已完成）

**Status:** ✅ 已完成。新建 `CropOverlayView.kt`（自訂 `View`，疊加於 `PdfReaderView` 的 `imageView` 之上，`PdfReaderView.kt` 的 `getView()` 改包一層 `FrameLayout` 以支援動態疊加/移除；四角控制點拖拉、右下角固定確認按鈕，皆以 `Canvas`／`MotionEvent` 手動繪製與處理）、原生端 `enterCropEditMode`／`exitCropEditMode`／`onCropRectSelected` method channel 契約、Dart 端 `PdfReaderView.cropEditModeActive`／`onCropRectSelected` 宣告式契約、`PdfSettingsSheet` 啟用手動選區選項、`ReaderScreen` 狀態機串接（`_handleRequestManualCrop`／`_handleCropRectSelected`，皆用 `BookReaderPrefs.copyWith()` 避免地雷重演）皆已完成。計劃在實作前已依外部程式碼審查修訂：`CropOverlayView` 的 `ACTION_DOWN` 恆回傳 `true`（修復觸控事件穿透與後續拖曳丟失）、確認按鈕改黑底白勾以維持 E-Ink 灰階裝置對比度、`onSizeChanged` 補上裝置旋轉時的相對座標重新映射、`ReaderScreen` 新增 `PopScope`（`canPop: !_cropEditModeActive`）避免裁切互動模式進行中誤觸物理返回鍵導致整個閱讀器被意外關閉（刻意不新增「取消並還原」語意，維持 `spec.md` 已鎖定的簡化狀態機決策）。**已知限制**：僅在 API 35 真機（9491G）驗證，未涵蓋其他 API 版本裝置（同 Issue 3-5 已知限制）。真機自動化測試（`flutter test integration_test/reader_screen_test.dart`，19 個既有測試 + 本 issue 新增的 2 個裁切互動測試，共 21/21）通過：「進入手動裁切互動模式後對畫面做水平拖曳，確認不觸發任何確認/翻頁副作用、裁切互動模式維持進行中」與「拖拉右下角控制點縮小裁切框、點擊確認按鈕後，`pdf_crop_mode` 正確寫入為 `manual`、`pdf_crop_rect` 非空，且確認後重新開啟 `PdfSettingsSheet`」皆通過，直接證明觸控拖拉→確認→持久化的完整互動鏈路在真機上確實正確運作。**螢幕截圖視覺比對**：手動安裝 debug APK 並以 `adb` 直接操作真機時，意外取得一張真實、內容清晰的畫面截圖，完整呈現 `CropOverlayView` 的視覺元素——裁切框外的半透明暗色遮罩、白色邊框裁切框、四個白色圓形控制點、右下角黑底白勾確認按鈕，疊加於一份僅供本次驗證用的暫時性內容（置中黑色色塊＋「CROP TEST」文字，未納入版本控制，驗證後已刪除），確認原生疊加層渲染符合設計、E-Ink 對比度修正確實生效。**誠實記錄的驗證缺口**：後續嘗試以 `adb shell am start`／`monkey` 手動驅動真機重現「拖曳中」「確認後」的連續截圖序列時，遭遇裝置特定的環境問題——`adb exec-out screencap` 在脫離 Flutter `integration_test` 測試框架、改由 `adb` 直接注入 intent/觸控事件驅動時，多次回傳的是桌面/啟動器的過期快取畫面而非真正的當下畫面（`dumpsys window`／`dumpsys activity` 皆確認 App 視窗實際存在且部分時刻確實取得過焦點），研判是這台裝置（TCL 客製化 launcher）的螢幕截圖或視窗合成在此操作路徑下的既有限制，非本 issue 程式邏輯缺陷；已嘗試重新安裝、強制停止重啟、重設螢幕旋轉鎖定等排除方式仍未能穩定重現「拖曳中／確認後」的連續截圖。核心互動邏輯的正確性已由上述真機自動化測試（非僅截圖）完整證明，此為額外的、錦上添花性質但未能完整取得的補充視覺證據，如實記錄此差距而非誇大宣稱已完成。完整計劃見 `plans/plan-issue-6.md`。

**依賴：** Issue 5（共用裁切分頁與 `PdfCropRect` 渲染套用邏輯）

**承接 Issue 5 整體審查的提醒**：
- `PdfReaderView.dart` 的 `didUpdateWidget` 目前只比較 `cropMode`、刻意不比較 `cropRect`（因為 Issue 5 唯一會寫入 `cropRect` 的來源是原生端主動回呼，原生本身已持有該值，無需再送回）。本 issue 讓使用者能在 `cropMode` 已經是 `manual` 的情況下重新選取新的裁切框——此時 `cropMode` 不會變動，若沿用現有比較邏輯，`setPdfPreferences` 不會觸發、原生端收不到新矩形。需將 `cropRect` 一併納入 `didUpdateWidget` 比較（或改用其他方式強制送出）。
- 原生端 `renderCurrentPage()` 的 `effectiveCrop` 判斷式（`cropMode != "none"` 即套用 `cropRect`）已可正確處理 `manual` 模式＋已提供矩形的渲染，本 issue 主要工作在互動疊加層 UI 與 method channel 串接，渲染管線本身不需改動。
- Issue 5 驗證時發現 `detectCropRect()`（智慧自動裁切）在近乎全白的頁面上可能算出退化（極薄或反轉）的矩形，屬於已知殘留風險；雖與手動選區邏輯無直接關聯，但若本 issue 需要複用邊界偵測或矩形驗證邏輯，留意此邊界情況。

**描述：**
實作裁切分頁的第三個選項（手動選區），本 epic 技術風險最高的一塊（設計審查 Finding 1.2 的核心決策——Native 而非 Flutter 全螢幕畫面，見 `design.md` 決策 #14）：

- 新建 `CropOverlayView.kt`（`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt`）：自訂 `View`，疊加於 `PdfReaderView` 的 `imageView` 之上，繪製可拖拉四角控制點的裁切框並處理觸控事件，只在裁切互動模式下加入 View 樹
- **原生端（`PdfReaderView.kt`）**：新增 `enterCropEditMode`／`exitCropEditMode` method channel handler（進入時加入 `CropOverlayView` 並暫停 `nextPage`/`previousPage` 回應，離開時移除並恢復）；新增 `onCropRectSelected` method channel（使用者拖拉後點擊確認時觸發，回傳相對座標矩形）
- **Dart 端（`PdfReaderView`）**：新增 `cropEditModeActive: bool`（預設 `false`）宣告式建構參數，`didUpdateWidget` 偵測 `false → true` 時送出 `enterCropEditMode`、`true → false` 時送出 `exitCropEditMode`；新增 `onCropRectSelected: ValueChanged<PdfCropRect>?` callback
- `PdfSettingsSheet`：新增 `onRequestManualCrop: VoidCallback` 建構參數，裁切分頁「手動選區」選項點擊時觸發（`PdfSettingsSheet` 本身不直接操作 `PdfReaderView`，維持既有單向資料流）；啟用先前 Issue 5 顯示為停用的第三選項
- `ReaderScreen`：新增 `_handleRequestManualCrop()`（關閉 `PdfSettingsSheet`、`setState(() => _cropEditModeActive = true)`）與 `_handleCropRectSelected(PdfCropRect)`（`setState(() => _cropEditModeActive = false)`，更新 `BookReaderPrefs`（`pdfCropMode = manual`、`pdfCropRect = rect`）並持久化，重新開啟 `PdfSettingsSheet`）

**單元測試要求：**
- `PdfReaderView` widget test：`cropEditModeActive` 由 `false→true`／`true→false` 時分別觸發 `enterCropEditMode`／`exitCropEditMode`；收到 `onCropRectSelected` 時正確觸發回呼
- `PdfSettingsSheet` widget test：裁切分頁「手動選區」點擊觸發 `onRequestManualCrop`
- `ReaderScreen` widget test：`_handleRequestManualCrop`／`_handleCropRectSelected` 正確驅動 `_cropEditModeActive` 狀態機與 `BookReaderPrefs` 持久化呼叫
- **已知測試限制**：`CropOverlayView.kt` 的觸控拖拉邏輯無法透過 `flutter test` 驗證（沿用既有慣例，見 `docs/archive/2026-07-10-epic-3-fonts-layout/issues.md` Issue 2 對原生邏輯測試限制的既有處理方式），留給本 issue 的 `integration_test`

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- `integration_test`（真實裝置）：點選「手動選區」進入裁切互動模式，確認翻頁手勢暫停回應；拖拉四角控制點後點擊確認，`book_reader_prefs.pdf_crop_mode`/`pdf_crop_rect` 正確寫入，畫面套用新裁切結果並恢復正常閱讀模式（翻頁手勢恢復）

---

## Issue 7：真機驗證與收尾（已完成）

**Status:** ✅ 已完成。三項驗證皆已完成：(1) **端到端組合設定持久化**——新增真機整合測試，同一本 PDF 依序調整 Fit 模式/對比度/亮度/加粗/裁切模式（皆偏離預設值），關閉重開後 5 個欄位＋`cropRect` 全數正確記住並套用，23/23 真機測試通過，未觀察到 Issue 4/5 review 反覆抓到的「地雷」模式（某分頁 `_notifyChanged()` 靜默清空另一分頁已設定欄位）重演；另以螢幕截圖確認 Fit Width／對比度/亮度／加粗／智慧自動裁切五者同時生效時彼此不互相干擾，一項因自製測試素材字體偏小造成的視覺保留意見已誠實記錄（非演算法缺陷）。(2) **NFR-1 基礎開啟效能**——100MB+ PDF 素材由使用者親自於真機上操作驗證，確認基礎開啟（無濾鏡/無裁切）無明顯卡頓或崩潰；**已知限制**：本次未取得精確毫秒數字可對比 2000ms 門檻，僅有定性確認，若未來需要正式 NFR-1 驗收等級數字，建議另外以 `flutter build apk --release` 正式建置重新量測。(3) **Issue 4 加粗效能裝置矩陣缺口**——已正式收斂：本開發環境全程僅有 API 35（9491G）一台裝置可用，無法補齊 API 24-30／其他 API 31+ 裝置複驗，記錄為已知殘留風險並於 `docs/epics.md` 新增 Backlog 追蹤項，待未來取得額外裝置時執行。**額外發現（範圍外，已記錄供後續追蹤，不阻塞本 epic 合併）**：真實「匯入書籍」UI 流程匯入既有共用的極簡空白 PDF fixture（`test/fixtures/sample.pdf`，345 bytes、無內容流）時，書架卡片永久停在 0% 進度無法完成，疑似 `epic-1-library`（已歸檔）封面產生管線對無內容流 PDF 缺乏逾時/錯誤處理，已於 `docs/epics.md` 記錄供人類決定是否另立追蹤。完整驗證紀錄見 `reviews/qa-issue-7-e2e-perf-report.md`（本目錄未納入版本控制）。完整計劃見 `plans/plan-issue-7.md`。**至此 Epic 4（PDF 專業增強）Issue 1-7 全數完成**，是否歸檔留待人類決定。

**依賴：** Issue 3、Issue 4、Issue 6 全部完成（Issue 5 已被 Issue 6 涵蓋，Issue 1/2 為前置基礎）

**描述：**
本 issue 為裝置端整合驗證與 Epic 收尾，比照 `epic-3-fonts-layout` Issue 6 的既有模式，部分項目屬人工視覺 QA 性質：

- **端到端組合驗證（人工視覺 QA）**：對同一本 PDF 依序調整所有版面設定（Fit 模式、對比度、亮度、加粗、裁切模式），關閉 App、重新開啟，確認所有設定皆被正確記住並套用（驗證 Issue 2-6 的 `initialPreferences` 機制在多欄位組合情境下依然正確，不只是單一欄位）
- **NFR-1 基礎效能驗證**：100MB 以上 PDF 在無濾鏡/無裁切時的基礎開啟時間 < 2 秒（決策 #13 範圍，不含濾鏡/裁切的效能不強制同一門檻）
- **加粗效能風險複驗**：依 Issue 4 驗收標準的裝置矩陣（API 24-30／API 31+），確認加粗在兩種裝置上皆無明顯卡頓或崩潰，若 Issue 4 階段未能涵蓋完整裝置矩陣，本 issue 需補齊
- 彙整驗證紀錄，更新 `docs/epics/epic-4-pdf-enhance/issues.md` 各 issue 最終驗收狀態
- 若驗證中發現需要後續處理的落差，比照 `epic-3-fonts-layout` 慣例（Issue 6 發現 Issue 7/8/9），另立後續 issue 追蹤，不阻塞本 epic 合併

**單元測試要求：**
- 無新增自動化單元測試（本 issue 以整合/裝置驗證為主）

**驗收標準：**
- 端到端組合持久化驗證產出書面紀錄（比照 `qa-issue-N-*.md` 既有慣例）
- NFR-1 基礎效能驗證產出明確結論（達標／未達標，若未達標需記錄具體數字並評估是否阻塞收尾）
- `flutter analyze` 乾淨、`flutter test` 全數通過
- 若有發現需要後續處理的落差，已建立對應的後續 issue 追蹤，不阻塞本 epic 合併
