# Epic 16 — 橫向雙頁顯示：工單清單 (Issues)

依 `spec.md`（搭配 `design.md`、`tmp/epic-16/reviews/review-design-spec.md` 審查修正）拆解出的細粒度垂直切片工單。Issue 1（Spike）與 Issue 2（資料層）可立即平行開始；Issue 3 依賴 Issue 2；Issue 4、5 依賴 Issue 3；Issue 6 依賴 Issue 1、2；Issue 7 為收尾工單，依賴 Issue 4、5、6 全部完成。

---

## Issue 1：Spike——Readium Spread 行為驗證與收斂關卡

**Status:** ready-for-agent

**依賴：** 無（起始工單，可與 Issue 2 平行）

**描述：**
`spec.md`「待驗證風險與收斂關卡」明訂本項驗證**必須在進入實作前完成**，不得留待實作階段才發現。本 issue 是一次性研究/驗證工作，非長期功能程式碼：

- 以最小可行方式（可用既有專案的暫時性分支、或 `prototype` skill 建立獨立驗證用 EPUB FXL 開啟流程）在真機上驗證 `spec.md` 列出的 4 個問題：
  1. Readium `Spread.AUTO`／`Spread.ALWAYS` 啟用後，頁間是否有可見間距（FR-41 硬性要求「不留空白」）
  2. `Spread.AUTO` 是否等同「橫向才雙頁」；若語意不符，EPUB 側需改為直接依 `isLandscape` 手動在 `ALWAYS`/`NEVER` 間切換，不使用 `AUTO`
  3. `page-spread-left/right` metadata 的頁面配對是否正確（至少涵蓋一般跨頁與蝴蝶頁/跨頁大圖邊界情況）
  4. `applyFxlFitScale()` 若依 `spec.md` 所述改為「container 寬度 / 2」為每個 WebView 的縮放基準，兩個 WebView 是否真的並排而不重疊
- 每項驗證需附具體證據（真機截圖、log、或量測數值），不接受「應該可行」的主觀判斷
- 若任一項驗證失敗，需在 `spec.md` 對應段落（`EpubReaderView.kt` 模組段落／已知限制／待驗證風險與收斂關卡）記錄退回方案的具體實作路線，供 Issue 6 依循

**單元測試要求：** 無（研究/驗證性質，比照 `epic-4-pdf-enhance` Issue 7 的先例；驗證過程中若產生暫時性程式碼或素材，驗證後需清理，不留在版本控制中）

**驗收標準：**
- 上述 4 項問題皆有明確結論與證據，寫入驗證報告（建議路徑：`docs/epics/epic-16-dual-page/reviews/spike-readium-spread.md`）
- 若任一項驗證失敗，`spec.md` 對應段落已更新為退回方案，Issue 6 的實作範圍需依此結論調整（若導致 Issue 6 範圍變動，需在 Issue 6 開工前更新其描述）
- 過程中的暫時性程式碼/素材已清理，`git status` 乾淨

---

## Issue 2：資料層基礎建設——雙頁偏好設定儲存

**Status:** ✅ 已完成。依 `plans/plan-issue-2.md` Task 1-2 完成實作：新增 `DualPageMode`/`DualPageDirection` 列舉、`BookReaderPrefs` 新增 3 個雙頁欄位（`toMap`/`fromMap`/`==`/`hashCode` 依既有模式平行擴充，`hashCode` 順勢改用 `Object.hashAll` 取代 `Object.hash`，避免其 20 參數上限被本次新增欄位頂到）、`book_reader_prefs` 表升級至 schema version 4（`onUpgrade` 從互斥 `if/else if` 改為累加式 `if`，確保停留在 version 2 的裝置跳級到 version 4 時，PDF 欄位與雙頁欄位兩段遷移皆會執行，並附專屬回歸測試驗證此情境）。`/superpowers:requesting-code-review` 程式碼審查核准（Ready to merge: Yes，無 Critical/Important 問題），44 個新增/相關測試＋全專案 213 個測試全數通過，`flutter analyze` 乾淨。已於 branch `epic-16/dual-page-prefs-storage`（commit `934623d`）完成，待人類合併。

**依賴：** 無（起始工單，可與 Issue 1 平行）

**描述：**
建立本 epic 全部後續 issue 共用的資料模型與持久化機制，純 Dart、不涉及原生程式碼、不需要真實裝置：

- 新增列舉型別：`DualPageMode`（`app/lib/reader/dual_page_mode.dart`，`auto`/`always`/`never` 三值）、`DualPageDirection`（`app/lib/reader/dual_page_direction.dart`，`ltr`/`rtl` 二值）
- `BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`）新增 3 個 nullable 欄位：`dualPageMode`／`dualPageCoverAlone`／`dualPageDirection`，`copyWith`/`toMap`/`fromMap`/`==`/`hashCode` 依既有模式平行擴充（見 `spec.md`「資料模型」）
- `book_reader_prefs` 表新增上述 3 欄位（見 `spec.md` 的 SQL 定義：`dual_page_mode TEXT`／`dual_page_cover_alone INTEGER`／`dual_page_direction TEXT`），依裝置狀態分兩條路徑：全新安裝走 `CREATE TABLE`（`onCreate`）一步到位；既有裝置走 `ALTER TABLE ADD COLUMN`（`onUpgrade`）逐欄補上，兩者互斥不重疊，`BookReaderPrefsRepository` 的既有 `load`/`save` 邏輯不需改動（全欄位 nullable、`Map` 驅動）
- **重要**：本 issue 只建立資料層，`ResolvedPreferences.dualPageMode`／`dualPageCoverAlone`／`dualPageDirection` 的 Null 預設值解析（`ReaderPrefsManagerImpl.resolve()`）屬於後續職責，留給 Issue 3（見 `spec.md` I-3／「Null 預設值解析」；因 `docs/superpowers/plans/2026-07-12-refactor-reader-prefs-manager.md` 已完成的 `ReaderPrefsManager` 重構，此處不再是 `ReaderScreen` 上的 `_resolvedXxx` getter，見 spec.md 該段落 2026-07-12 同步更新的說明）

**單元測試要求：**
- 純 Dart unit test：`DualPageMode`／`DualPageDirection` 為 `byName` 直接映射（無回退），比照 `BookReaderPrefs` 既有 enum 欄位（如 `PdfFitMode`／`PdfCropMode`）的既有慣例，不需要獨立測試檔
- `BookReaderPrefs`：新 3 欄位的 `toMap`/`fromMap` round-trip；驗證讀取 EPUB／PDF 資料時彼此不受影響
- `BookReaderPrefsRepository`：既有 `save()`/`load()` round-trip 測試擴充涵蓋新欄位；資料庫 migration 後既有書籍的新欄位讀回 `NULL`，不影響既有資料載入

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- 本 issue 完全不需要真實裝置即可驗收

---

## Issue 3：方向偵測基礎建設 + PDF 雙頁核心渲染

**依賴：** Issue 2

**Status:** ready-for-agent

**描述：**
建立方向偵測共用基礎設施，並實作 PDF 雙頁渲染核心管線——本 epic 技術風險最高的部分之一，因為 `renderCurrentSpread()` 的拼接／步進／OOM 回退邏輯彼此緊密耦合於同一函式，須一次到位、不可切成半成品：

- **`ReaderScreen`**（`app/lib/screens/reader_screen.dart`）：
  - 方向偵測：`build()` 中透過 `MediaQuery.of(context).orientation == Orientation.landscape` 判斷，存為 `bool isLandscape`，下傳給 `PdfReaderView`（本 issue）／`EpubReaderView`（Issue 6 消費，本 issue 只需確保偵測邏輯是共用的，不要把它寫死在 PDF 專屬程式碼路徑裡）
  - 新增 `ResolvedPreferences.dualPageMode: DualPageMode`／`dualPageCoverAlone: bool`／`dualPageDirection: DualPageDirection`（皆 non-nullable）三個欄位，並在 `ReaderPrefsManagerImpl.resolve()` 中依 `book.dualPageMode ?? DualPageMode.auto` 等既有 `pdfFitMode` 慣例解析（見 spec.md「Null 預設值解析」——`ReaderPrefsManager` 重構後，Null 合併解析邏輯已從 `ReaderScreen` 搬到 `ReaderPrefsManager` 深模組，不再是 `_resolvedXxx` getter）；`ReaderScreen` 透過 `resolved.dualPageMode` 等欄位讀取已解析值後下傳，永遠是非 null 值
- **`PdfReaderView`**（Dart，`app/lib/reader/pdf_reader_view.dart`）：建構子新增 `dualPageMode`／`dualPageCoverAlone`／`dualPageDirection`／`isLandscape` 參數（皆由 `ReaderScreen` 解析為非 null 值後傳入）；`didUpdateWidget` 偵測任一變動時透過 `setPdfPreferences` 送出
- **`PdfReaderView.kt`**：`renderCurrentPage()` 更名為 `renderCurrentSpread()`（同步改名全部 5 處呼叫點：`setPdfPreferences`／`openBook`／`exitCropEditMode`／`nextPage`／`previousPage`），完整實作 `spec.md` 演算法步驟 1-6：
  1. 雙頁啟用判斷（`always`，或 `auto` 且 `isLandscape`，且未處於裁切編輯模式）
  2. 封面獨立配對（`currentPageIndex == 0` 單頁封面／`> 0` 奇偶配對）
  3. 依 `dualPageDirection` 決定左右頁配對（`ltr`/`rtl`），超出總頁數側留白
  4. 左右頁套用同一個全書 `cropRect`（沿用既有裁切欄位，本 issue 不新增裁切互動，只需確保拼接前套用邏輯正確）後拼接成一張大點陣圖
  5. **OOM 回退**：拼接階段 `OutOfMemoryError` 時回退為只渲染 `currentPageIndex` 單頁
  6. 拼接（或回退）後統一套用加粗濾鏡／`colorFilter`／`fitMode`
  - **翻頁步進**（含 C-4 對稱規則）：前進時封面特例步進 1、其餘步進 2；**後退時對稱處理**——從 spread 左頁 index 1 回封面時步進 1，其餘步進 2，不得對負數 index 呼叫 `openPage()`
  - **頁碼回報**：`onPageChanged` 一律回報 `currentPageIndex`（spread 錨點），不使用方向相關的「較小」/「左側」描述
- **`PdfSettingsSheet`**（`app/lib/screens/pdf_settings_sheet.dart`）：「顯示」分頁新增「雙頁模式」三態選項（自動／永遠雙頁／永遠單頁）。**本 issue 只做這個控制項**——「封面獨立」與「頁面方向」欄位雖然原生端已完整支援（步驟 2-3 一次到位），但 UI 控制項留給 Issue 4，本 issue 期間這兩欄位維持預設值（封面獨立開啟、`ltr`）

**單元測試要求：**
- `PdfReaderView` widget test：`isLandscape`/`dualPageMode` 變動觸發 `setPdfPreferences`；`initialPreferences` 正確包含新欄位
- `PdfSettingsSheet` widget test：雙頁模式三態切換正確觸發 `onChanged`
- `ReaderScreen` widget test：裝置轉橫向時 `isLandscape` 正確下傳給 `PdfReaderView` 建構參數；`ResolvedPreferences` 的 3 個雙頁欄位對 null 值正確做預設合併（透過 `ReaderPrefsManagerImpl.resolve()` 驗證，而非 `ReaderScreen` 上的 getter）
- **已知測試限制**：原生端 `renderCurrentSpread()` 的拼接／OOM 回退邏輯無法透過 `flutter test` 驗證，留給本 issue 的 `integration_test`

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- `integration_test`（真實裝置）：
  - PDF 開啟後裝置轉橫向，`dualPageMode = auto` 時自動雙頁並排、頁間無可見間距（FR-41 核心驗收點）；轉回直向恢復單頁
  - `always`／`never` 明確覆寫行為正確
  - 預設（封面獨立開啟＋`ltr`）配對正確：第 0 頁單頁封面 → 往後翻步進 1 到 `[1,2]` → 再翻步進 2 到 `[3,4]`
  - 從 `[1,2]` 往回翻正確回到封面（C-4 對稱規則驗證，不得崩潰或卡在 index 1）
  - 奇數總頁數 PDF 的最後一頁正確落單、另一側白色背景留白

---

## Issue 4：PDF 封面獨立開關 + 閱讀方向（LTR/RTL）

**依賴：** Issue 3

**Status:** ready-for-agent

**描述：**
在 `PdfSettingsSheet` 補齊 Issue 3 原生端已支援、但尚未開放使用者調整的兩個控制項：

- `PdfSettingsSheet`「顯示」分頁新增「封面獨立」開關（預設開啟）與「頁面方向」二選一（左到右／右到左，預設左到右）
- 本 issue 不需異動原生端邏輯（Issue 3 已一次到位實作），純粹是 UI 曝光 + 端到端驗證這兩個既有但未被測試覆蓋的路徑

**待決設計問題（Issue 3 真機驗證時發現，記錄於此供本 issue 開始時討論）：**
`dualPageDirection` 目前預設值固定為 `ltr`，不論書籍是橫排還是直排（`WritingMode`）。但直排（vertical-RL）書籍慣例上應是右到左翻頁——也就是右頁顯示較小 index（較早）、左頁顯示較大 index（較晚），恰好對應 `rtl` 配對結果。目前規劃是使用者透過本 issue 新增的「頁面方向」控制項手動切換，每本直排書都要自己調整一次；是否應該改為依書籍偵測到的 `WritingMode` 自動預設（直排 → 預設 `rtl`，橫排 → 預設 `ltr`），而非純手動、固定預設 `ltr`，尚未決定，留待本 issue 實際開工時一併討論確認。

**已結案的審查疑慮（`tmp/epic-16/reviews/review-plan-issue-4.md` 提出，`/grill-with-docs` 已釐清，不需修正）：**
該審查將 `PdfSettingsSheet.initState()` 把 nullable 的 `dualPageCoverAlone`／`dualPageDirection`（以及既有的 `dualPageMode`／`pdfFitMode`／`pdfContrast`／`pdfBrightness`／`pdfBoldStrength`／`pdfCropMode`）用 `??` 具現化為非 null 本地狀態，列為 Standards 硬性違反（違反 `AGENTS.md`「null = 不覆寫」慣例）。經查證：
1. 這是 `PdfSettingsSheet` 從 Issue 3（甚至更早）就存在的既定寫法，8 個欄位皆同一模式，不是本 issue 新增的缺陷。
2. `ReaderSettingsSheet`（EPUB）已有可參照的既定原則：本地狀態是否該保留 nullable，取決於該欄位是否存在「全域預設值」或「書籍自動偵測值」等次要權威來源可回退——有次要來源時才保留 nullable 並提供「不覆寫」重置選項（如 `writingModeOverride`）；無次要來源、null 與具體預設值解析結果永遠相同時，具現化是安全的（如既有的字型大小/行距等滑桿欄位）。此原則已寫入 `CONTEXT.md`。
3. `docs/epics.md` 對 `epic-4-pdf-enhance` 已有明文決定：「濾鏡/裁切/Fit 模式皆單書持久化（無全域預設，不併入 epic-14）」；`epic-14-system-settings` 那一列列出的全域/單書雙層覆寫 FR 清單（FR-35/36/37/38/39/42）亦不含 FR-41（雙頁顯示）。即 PDF／雙頁相關欄位比照既有模式，明文排除於全域預設層之外，屬於第 2 點「無次要來源」的情況，null 具現化不構成語意破壞，也沒有可預見會變成問題的規劃路徑。
- **結論：不修正，不需再排程檢視。** 若未來 `epic-14` 範圍變動、真的替 PDF/雙頁欄位加上全域預設層，該工作本身就需要重新設計 `PdfSettingsSheet`（含新增「重置」UI），屆時審查會自然重新抓到這個問題，現在不需要預埋提示。

**單元測試要求：**
- `PdfSettingsSheet` widget test：「封面獨立」開關與「頁面方向」選項切換正確觸發 `onChanged`

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- `integration_test`（真實裝置）：
  - `dualPageCoverAlone = false` 時，第 0 頁與第 1 頁直接拼接並排（無獨立封面）
  - `dualPageDirection = rtl` 時，`onPageChanged` 回報值仍為 `currentPageIndex`，但畫面左右呈現對調（右側顯示較小 index）
  - 關閉重開該書後，兩個新設定值正確持久化

---

## Issue 5：PDF 手動裁切 × 雙頁互動安全

**依賴：** Issue 3

**Status:** ready-for-agent

**描述：**
整合既有裁切功能（`epic-4-pdf-enhance` 已完成的 `CropOverlayView`／`enterCropEditMode`）與雙頁模式的交互（決策 #10／`spec.md` I-8）：

- **原生端（`PdfReaderView.kt`）**：`enterCropEditMode()` 於雙頁模式生效時，強制以 `currentPageIndex`（spread 錨點）為基準切回單頁預覽渲染（沿用既有 `renderFullPageForCropPreview()`，`CropOverlayView` 本身不需改動，只處理單頁座標）；`exitCropEditMode()` 恢復雙頁渲染時，確認後更新的唯一全書 `cropRect` 套用於左右兩頁
- 確認雙頁模式下 `nextPage()`/`previousPage()` 在裁切編輯模式中依然正確暫停回應（沿用既有 `cropEditModeActive` 守衛）

**單元測試要求：**
- 本 issue 不涉及 Dart 端新建構參數或 method channel 契約異動（複用 Issue 3 與既有裁切機制），不需新增 widget test；若既有 `PdfReaderView`／`ReaderScreen` widget test 因本次原生端調整而需要新增斷言，於實作時一併補上

**驗收標準：**
- `flutter analyze` 乾淨
- `integration_test`（真實裝置）：雙頁模式下點擊「手動選區」，畫面立即強制切回單頁預覽（以 spread 錨點頁為準）；拖拉裁切框並確認後，畫面恢復雙頁模式，且左右兩頁皆正確套用新裁切矩形（同一個全書 `cropRect`）

---

## Issue 6：EPUB FXL 雙頁——Readium Spread 整合 + `FxlSettingsSheet`

**依賴：** Issue 1（Spread 驗證結論決定走 Readium 內建 `spread` 或退回自行實作）、Issue 2（資料層）

**Status:** ready-for-agent

**描述：**
實作 EPUB 固定版面（漫畫）的雙頁顯示，實作路線依 Issue 1 的驗證結論而定（預設走 `spec.md` 記載的 Readium 內建 `Spread` enum 路線；若 Issue 1 驗證失敗，改依 Issue 1 記錄的退回方案）：

- **`EpubReaderView`**（Dart，`app/lib/reader/epub_reader_view.dart`）：建構子新增 `dualPageMode`／`isLandscape` 參數，`didUpdateWidget` 偵測任一變動時送出 `setPreferences`
- **`EpubReaderView.kt`**：
  - `buildPreferencesFromMap()` 新增 `spread = spreadFromDualPageMode(...)`，將 `dualPageMode` 三態字串對應到 Readium `EpubPreferences.spread`（`org.readium.r2.navigator.preferences.Spread` enum：`"auto"→Spread.AUTO`、`"always"→Spread.ALWAYS`、`"never"→Spread.NEVER`）
  - `applyFxlFitScale()` 雙頁適配：偵測到 spread 生效（2 個以上可見 WebView）時，縮放基準 `availableWidth` 改為「container 寬度 / 2」，依 WebView 螢幕左右順序分別套用對應半寬區塊的置中位移；`cachedFxlFitScale` 快取鍵新增「是否為 spread 模式」維度，單/雙頁切換或裝置旋轉時使快取失效重算
  - **改用已抽離的 `EpubFxlScaler`，不再就地實作**：本段原描述「就地實作，不預先抽離」已被 Issue 8（2026-07-12 已完成，見該 issue）取代——`EpubFxlScaler`（`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubFxlScaler.kt`）已存在且為無狀態 pure-Kotlin 模組，本 issue 新增的雙頁縮放邏輯應在 `EpubFxlScaler` 內擴充純函式（例如新增接受「每頁可用寬度」的多載或新函式），而非退回在 `EpubReaderView.kt` 內就地擴充；`cachedFxlFitScale` 快取鍵新增「是否為 spread 模式」維度仍留在 `EpubReaderView.kt`（實例狀態，不搬入 `EpubFxlScaler`）。開工前應重新閱讀 `EpubFxlScaler.kt` 當時的函式簽章，確認擴充方式與既有 `computeFitScale`/`computeCenteringTranslation` 相容
- **`ReaderScreen`**：EPUB 且 `isFixedLayout == true` 時，於畫面右上角新增圓形半透明懸浮設定按鈕（`Key('reader_fixed_layout_settings_button')`，對稱於左上角 `Key('reader_fixed_layout_back_button')`），點擊開啟 `FxlSettingsSheet`（打破「固定版面不顯示設定齒輪」的既有慣例，因為固定版面整個 Scaffold AppBar 被隱藏）
- 新建 `FxlSettingsSheet`（`app/lib/screens/fxl_settings_sheet.dart`）：精簡版 Bottom Sheet，提供「雙頁模式」三態切換選項（僅預留 FR-42 全螢幕開關的 UI 擴充空間，本 issue **不**實作 FR-42 功能本身）

**單元測試要求：**
- `EpubReaderView` widget test：`dualPageMode`/`isLandscape` 變動觸發 `setPreferences`
- `FxlSettingsSheet` widget test：Sheet 能正常 pump 起、點擊「雙頁模式」選項正確觸發 `onChanged`
- `ReaderScreen` widget test：EPUB 固定版面開書後，畫面右上角出現 `Key('reader_fixed_layout_settings_button')`，點擊能開啟 `FxlSettingsSheet`
- **已知測試限制**：Readium `spread` 偏好生效後的實際排版結果（間距、WebView 並排）無法透過 `flutter test` 驗證，留給本 issue 的 `integration_test`

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- `integration_test`（真實裝置，使用真實漫畫 FXL EPUB 素材）：橫向狀態下 `dualPageMode = auto` 成功並排顯示兩頁、頁間無可見間距（FR-41 核心驗收點，比對方式依 Issue 1 驗證結論調整）、翻頁不崩潰
- 若 Issue 1 驗證結論為「需退回自行實作」，本 issue 的實作與驗收標準需依 Issue 1 記錄的退回方案調整，並在完成後於本工單記錄實際採用的路線

---

## Issue 7：真機驗證與收尾

**依賴：** Issue 4、Issue 5、Issue 6 全部完成

**Status:** ready-for-agent

**描述：**
比照 `epic-4-pdf-enhance` Issue 7 的既有模式，本 issue 為裝置端整合驗證與 Epic 收尾，部分項目屬人工視覺 QA 性質：

- **端到端組合驗證（人工視覺 QA）**：對同一本 PDF 依序調整雙頁模式、封面獨立、方向、（沿用既有）Fit/濾鏡/裁切設定，關閉 App、重新開啟，確認所有設定皆被正確記住並套用，且互不干擾（比照 `epic-4` Issue 7 對「地雷」模式的既有排查方式）
- **FR-41 核心驗收確認**：PDF 與 EPUB FXL 兩條路線的雙頁顯示皆以真機肉眼／截圖比對確認「頁間不留空白」
- **裝置旋轉行為確認**：`auto` 模式下裝置旋轉時，PDF／EPUB 兩條 `PlatformView` 皆不重建（無黑屏、無重新 `openBook`），比對 `spec.md`「方向偵測契約」第 4 點的要求
- 彙整驗證紀錄，更新 `docs/epics/epic-16-dual-page/issues.md` 各 issue 最終驗收狀態，並視結果更新 `docs/epics.md` 狀態列
- 若驗證中發現需要後續處理的落差，比照既有慣例另立後續 issue 追蹤，不阻塞本 epic 合併

**單元測試要求：** 無新增自動化單元測試（本 issue 以整合/裝置驗證為主）

**驗收標準：**
- 端到端組合持久化驗證產出書面紀錄（比照 `qa-issue-N-*.md` 既有慣例）
- FR-41「不留空白」於 PDF 與 EPUB FXL 兩條路線皆有明確視覺確認結論
- `flutter analyze` 乾淨、`flutter test` 全數通過
- 若有發現需要後續處理的落差，已建立對應的後續 issue 追蹤，不阻塞本 epic 合併

---

## Issue 8：技術債／架構深化——EpubReaderView.kt FXL 縮放邏輯抽離為 EpubFxlScaler（已完成）

**Status:** ✅ 已完成。依 `plans/plan-issue-8.md` Task 1-3 完成實作：新增 `EpubFxlScaler.kt`（`computeFitScale`／`computeCenteringTranslation`，7 個 JVM 單元測試全數通過）、`EpubReaderView.kt` 的 `applyFxlFitScale()` 改呼叫該模組。`/superpowers:requesting-code-review` 逐 commit 審查（範圍 `36d0279..6efd4e3`）核准，確認抽離公式與原內嵌算式逐行等價、`EpubFxlScaler` 確實無狀態、`cachedFxlFitScale` 行為未變、對外 method channel 契約未受影響（Ready to merge: With fixes，僅 Minor 文件收尾事項）。真機 `integration_test/epub_reader_view_test.dart` 回歸驗證 9/9 全數通過（含「開啟定樣式範例 EPUB，onLayoutResolved 回報 isFixedLayout 為 true」）。

**依賴：** 無（獨立技術債重構，不新增功能，不影響既有 method channel 契約，可於 Issue 6 之前或之後任何時間點執行）

**描述：**
`EpubReaderView.kt` 的 `applyFxlFitScale()`（固定版面縮放計算）目前與 `WebView`/`ViewTreeObserver` 等 Android View 型別強耦合，無法脫離真機/模擬器做 JVM 單元測試。架構審查（`tmp/epic-16/reviews/architecture-review-1783800246.html` Candidate #3，Speculative 等級）建議把其中的純數值計算部分抽離成獨立 `EpubFxlScaler` 模組；`docs/epics.md` 對應 Backlog 列與本文件 Issue 6 原描述皆記錄此抽離原本設計為「Issue 6 落地、且 `applyFxlFitScale()` 判斷已過度龐雜後才視情況執行」的順序。**本 issue 是人類明確決定提前於 Issue 6 之前執行**（不等待 Issue 6 落地才判斷是否需要），完整計劃見 `plans/plan-issue-8.md`。比照 `epic-4-pdf-enhance` Issue 8 已驗證過的抽離模式：把 `computeFitScale()`／`computeCenteringTranslation()` 兩個純數值計算函式抽到 `EpubFxlScaler`（`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubFxlScaler.kt`），`EpubReaderView.kt` 保留所有需要真實 View 環境的部分（`WebView` 量測、`ViewTreeObserver` 監聽、`scaleX`/`scaleY`/`translationX`/`translationY` 賦值、`cachedFxlFitScale` 實例狀態），只把計算結果的公式部分交給新模組。這是抽離重構，不是新功能，所有既有視覺效果與行為必須維持一致。

**對 Issue 6 的影響（重要）：** Issue 6 原描述「就地實作，不預先抽離」的順序已被本 issue 取代——Issue 6 開工時 `EpubFxlScaler` 已存在，Issue 6 新增的雙頁（spread）縮放邏輯（`cachedFxlFitScale` 快取鍵新增「是否為 spread 模式」維度、依 WebView 左右順序套用半寬區塊置中位移）應改為在 `EpubFxlScaler` 內擴充純函式（例如新增 `computeFitScale`/`computeCenteringTranslation` 的多載版本，或替換為接受 spread 相關參數的新函式簽章），而非退回在 `EpubReaderView.kt` 內就地擴充。Issue 6 實作者開工前應重新閱讀本 issue 完成後的 `EpubFxlScaler.kt`，確認新函式簽章設計。

**單元測試要求：**
- 新增 JVM 單元測試（`app/android/app/src/test/kotlin/cc/ugotit/elinkbook/EpubFxlScalerTest.kt`，沿用 `epic-4-pdf-enhance` Issue 8 已建立的 JVM 測試基礎設施，`build.gradle.kts` 已有 `testImplementation("junit:junit:4.13.2")`，不需重複新增）：`computeFitScale()`（寬/高各自為縮放瓶頸的情況、內容小於容器時不放大）、`computeCenteringTranslation()`（原始位置在原點、原始位置非原點含負值偏移的情況）
- 不新增 Dart 測試（本 issue 不涉及 Dart 端）

**驗收標準：**
- 上述 JVM 單元測試皆通過（`./gradlew testDebugUnitTest`，於 `app/android` 目錄執行）—— ✅ 已於真機連線的開發環境以 `./gradlew :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.EpubFxlScalerTest"` 實際執行，`BUILD SUCCESSFUL`，7/7 通過
- `flutter analyze` 乾淨 —— ✅ 已確認
- `integration_test`（真實裝置）：重新執行既有涵蓋定樣式 EPUB 開書的測試（`epub_reader_view_test.dart` 「開啟定樣式範例 EPUB，onLayoutResolved 回報 isFixedLayout 為 true」）—— ✅ 已在真機（`9491G`，Android 15）執行 `flutter test integration_test/epub_reader_view_test.dart`，9/9 全數通過
- 人工視覺確認固定版面書籍縮放/置中效果與抽離前一致，無回歸 —— ⚠️ **未完成，待人類補做**：曾嘗試以 `adb screencap` 自動截圖驗證（暫時性測試檔，已於驗證後刪除，未進版控），但此開發用真機（TCL 機型，`com.tcl.android.launcher`）在 `flutter test integration_test` 執行期間會被系統啟動器搶回前景焦點（`dumpsys` 確認 `mCurrentFocus`/`topResumedActivity` 為 launcher 而非測試中的 App），導致無法用 adb 截到 App 畫面本身，非本次程式改動造成的問題。由於程式碼審查已確認抽離公式與原邏輯逐行等價、且自動化整合測試（含 `isFixedLayout` 判定）無回歸，此項風險評估為低，但仍建議人類在方便時手動開啟一本固定版面（漫畫）EPUB，肉眼比對縮放/置中效果，補齊此項驗收標準
