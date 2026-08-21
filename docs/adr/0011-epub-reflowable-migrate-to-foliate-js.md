# ADR 0011：EPUB 流式（reflowable）渲染引擎由 Readium 遷移至 foliate-js（Phase 1）

## 狀態

已採納。**「頁碼估算改用 `SectionProgress.getProgress()`」該項決策裡「總頁數估算值不影響正確性」的取捨，已由 [ADR 0024](0024-flowable-pagination-density-calibration-reopen-adr-0011.md) 重新開放並補上密度校正——其餘決策項不受影響，仍為本 ADR 現行內容。**

## 背景

ADR 0001 已預留伏筆：「若 Readium 的直排支援或 Decorator 在 `epic-0-skeleton` 或 `epic-2-vertical-core` 階段被證實不足，應重新檢視本 ADR」。`epic-7-interaction` Issue 9 的真機插樁 spike（`docs/epics/epic-7-interaction/reviews/spike-vertical-pagejump.md`）診斷出直排／橫排翻頁跳頁問題根因為 Readium reflowable Navigator（`EpubNavigatorFragment.goForward()`/`goBackward()`）內部行為，非本專案 App 層缺陷；後續查證確認這對應 Readium 生態系已知、且官方已擱置的缺口（`readium/kotlin-toolkit#458`、`readium/css#141`——CSS Multicolumn 規格層級限制，Readium CSS 團隊明確表態不投入解決）。直排繁體中文排版是本產品的核心差異化（`docs/prd.md`），此缺口已構成 ADR 0001 該伏筆條款的觸發條件。

`epic-17-epub-render-migration` 完成 Discovery（`design.md`）與一個前置技術驗證 Spike（Issue 1，`reviews/spike-foliate-js-vertical.md`）：以釘定 commit 的 `readest/foliate-js` 在真機 Android WebView 上對繁體中文直排 EPUB 連續觸發 3 次「下一頁」+ 3 次「上一頁」，6 次觸發皆可視內容連續無跳過/重複、內部分頁位置皆單步變化，往返路徑截圖逐位元組比對完全對稱，依 `design.md` 判準表分類為「通過」，構成 GO 訊號。經 `/grill-with-docs` 逐項確認後續 Architecting 範圍，形成本 ADR。

## 決策

- **分階段遷移，非一次性完整替換**：Phase 1（本 ADR 涵蓋範圍）僅將**流式（reflowable）EPUB** 的渲染引擎由 Readium 換成 `readest/foliate-js`；**固定版面（FXL）EPUB 繼續留在 Readium**。分流依據是書本格式（整本書決定用哪個引擎），不是使用者當下選擇的橫排/直排排版方向——書本開啟後橫直排切換（ADR 0003）在同一個引擎內即時生效，不涉及引擎切換。
  - 理由：Spike 只驗證了流式 EPUB 直排分頁這一項；FXL、劃線/備註疊加在 `foliate-js` 上完全沒有實測證據，一次性替換等於把多個未驗證風險綁進同一次不可逆的原生層重寫。
- **新增完全獨立的原生 widget 類別**（暫定 `FoliateEpubReaderView.kt` + 對應 Factory，比照 `EpubReaderView`/`PdfReaderView` 既有對稱檔案慣例）處理流式 EPUB；**現有 `EpubReaderView.kt`（Readium）完全不修改**，繼續原樣處理 FXL。
  - 理由：完全不觸碰現有已測試、production 穩定運作的程式碼；若 Phase 1 之後發現 `foliate-js` 不適合，回退成本最低（`ReaderScreen` 判斷式改回全部用舊 widget、刪掉新檔案即可）。
- **開書前輕量格式判斷**：新增與兩套渲染引擎皆無關的原生工具函式，純粹解壓 EPUB 的 OPF 檔案讀取 `<meta property="rendition:layout">`，在 `ReaderScreen` 建構閱讀器 widget**之前**呼叫一次決定要用哪個 widget 類別；結果快取進 `books` 資料表（新增欄位），避免每次開書重新解壓確認。
  - 理由：現況 `isFixedLayout` 完全依賴 Readium 開書後才回報（`Publication.metadata.layout`），無法在「決定要用哪個引擎開書」之前就知道答案，此為必須解決的雞生蛋問題。
- **劃線/備註（`epic-6-annotations`）完整涵蓋在 Phase 1**，透過 `foliate-js` 的 `overlayer.js`（`Overlayer` 類別）對接，不做暫時性功能停用；這是刻意選擇承擔較大範圍，換取不讓流式 EPUB 使用者體驗到功能倒退。
- **既有流式書的書籤/劃線/備註/閱讀進度資料，Phase 1 上線後視為失效、不做遷移轉換**：Readium `Locator`（`href` + 全書單調遞增 `position` 整數 + `totalProgression`）與 `foliate-js` 的 CFI（`epubcfi(...)` 字串）+ 單一 section 內 `fraction` 是兩套不同的定位系統，沒有可靠的一對一換算；接受這是已知風險，不投入開發資源做轉換工具或雙軌並存。
- **直排/橫排自動判斷（FR-06）**：僅依書本自己 CSS 是否已宣告 `writing-mode`（有就照抄），判斷不出來則預設橫排；不用書本 `language` metadata 做語言猜測。原因：`foliate-js` 沒有等同 Readium `EpubSettingsResolver.resolveVerticalText()` 的內建判斷機制，需要自己實作，選擇最保守（只信任書本明確宣告）的版本。
- **3×3 導航熱區判讀**：統一沿用 FXL 現有「Dart 端 `Stack` 兄弟節點疊加 `GestureDetector`」模式（`epic-16-dual-page` 起、`epic-7-interaction` Issue 5 已驗證這個手勢仲裁技巧在 `PlatformView` 層級可靠），不在 Kotlin 原生端另外實作熱區判讀。`foliate-js` 是純 JS 函式庫，沒有原生觸控監聽 hook（不像 Readium 有 `InputListener`），沿用 Dart 端已驗證的 `hitTestZoneIndex()` 純函式比在原生端重新兜一套更單純。
- **不做執行期 fallback 開關**：專案目前無 remote config／staged rollout 基礎設施，退路是改版（`ReaderScreen` 判斷式改回全部用 Readium），不額外投入執行期切換機制的複雜度。
- **`readest/foliate-js` 版本釘定**：production 沿用 Spike 做法，把釘定 commit 的原始碼直接複製進 `app/android/app/src/main/assets/foliate/`、進版控，不引入 Node.js/npm 建置工具鏈（8 個純 ES module 檔案已證實不需要打包/轉譯即可直接執行）。升級版本＝重新走一次「下載新 commit、覆蓋、重新真機驗證」流程。
- **頁碼估算改用 `foliate-js` 內建的 `SectionProgress.getProgress()`**（`location.current`/`location.total`，以章節檔案位元組大小為代理指標），完整捨棄現有 `EpubCharacterCounter.kt`（原生背景協程字數統計）與 `EpubPageEstimator`（Dart 字元數換算頁碼）。`foliate-js` 的 `relocate` 事件已內建回傳這組資訊，不需要額外計算或快取。已知取捨：換算出的「總頁數」數字（位元組估算 vs 字元數估算）與使用者原本看到的數字可能不同，但兩者本來就都只是估算值，不影響正確性。

## 後果

- `ReaderScreen` 需要新增「開書前先問格式」的一段流程，插在既有 `detectBookFormat()`（副檔名判斷 epub/pdf/txt）與建構閱讀器 widget 之間；`books` 資料表需要 schema migration 新增欄位。
- Phase 1 上線後，流式 EPUB 與 FXL EPUB 走的是兩套完全獨立的原生 Kotlin 程式碼路徑（`FoliateEpubReaderView.kt` vs `EpubReaderView.kt`），Dart 端 `epub_reader_view.dart` 的既有公開契約（`onLayoutResolved`／`onLocatorChanged`／`onSelectionChanged`／`onAnnotationActivated`／`onZoneTapped` 等）需要對兩者皆適用，或拆出對應的新 widget 類別各自實作對稱契約——實際取捨於 `spec.md` 定義。
- `EpubCharacterCounter.kt`／`EpubPageEstimator` 兩個模組僅在 FXL 路徑（仍是 Readium）繼續視需要保留，流式路徑不再呼叫；是否連 FXL 路徑也一併清理，留待未來 Epic 評估（不阻塞本次 Phase 1）。
- 既有使用者對流式 EPUB 書籍已建立的書籤/劃線/備註/閱讀進度，App 更新後首次重開該書會偵測不到（等同以新書狀態開始）——這是本 ADR 明確接受的已知使用者體感衝擊，非疏漏，建議在該次改版的版本說明中揭露。
- 本 ADR 只涵蓋 Phase 1（流式 EPUB）；FXL 遷移、既有資料轉換工具、`readest/foliate-js` 長期維護風險（fork 若停止更新／與官方分歧擴大）等留待未來視 Phase 1 上線後的實際狀況另立 ADR 或 Epic 評估。

## 曾考慮的替代方案

- **一次性完整替換**（同時涵蓋流式、FXL、劃線備註、字數統計、3×3 熱區）：範圍最大、風險最高，多項子系統在 `foliate-js` 上完全沒有 Spike 證據，予以排除。
- **依「目前排版方向」而非「書本格式」分流引擎**：會導致使用者在閱讀中切換橫直排時，需要在同一個閱讀 session 內把整個原生渲染引擎（連同 `PlatformView`）從 Readium 換成 `foliate-js`，涉及定位系統即時轉換、捲動位置保留等更高複雜度，予以排除。
- **既有資料一次性遷移轉換工具**（用 Readium 讀出舊 Locator 對應內文位置、再用 `foliate-js` 重新定位找出對應 CFI）：技術上可行但複雜，且不保證兩套引擎的 reflow/tokenizing 演算法逐字對齊，準確性無法保證，予以排除。
- **既有資料雙軌並存**（已有 Readium 標記的書永久留在 Readium，只有新匯入的書用 `foliate-js`）：避免資料流失，但長期維護兩套引擎、且新舊書籍體驗不一致，維護成本壓過其風險降低的效益，予以排除。
- **3×3 熱區改由原生 Kotlin 判讀**（比照現有流式 EPUB 用 Readium `InputListener` 的模式）：`foliate-js` 無等同的原生觸控監聽 hook，需要額外自己攔截 WebView 觸控事件，複雜度高於沿用 Dart 端已驗證的 FXL 熱區疊加模式，予以排除。
- **執行期 fallback 開關**（remote config 或設定內藏開關）：專案規模與現有基礎設施不支撐這個投資，退版已是足夠的低成本退路，予以排除。
