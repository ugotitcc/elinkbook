# 流式頁次計算——架構檢視（頁碼精準化候選）

> 產出方式：`/improve-codebase-architecture` 技能，聚焦範圍由使用者指定：「針對流式頁次計算進行精進優化讓他更精準」。
> 涵蓋範圍：EPUB／TXT／MD（Foliate 格式）頁碼與進度計算管線。
> 產出日期：2026-08-21。
> 前置研究：`docs/research/foliate_js_page_calculation.md`（foliate-js 分頁機制技術研究）、`docs/zoomout/pagination-flowable-formats.md`（2026-08-20 模組地圖）。

## 事實更新

`docs/zoomout/pagination-flowable-formats.md` 記載「TOC 頁碼恆顯示佔位符『…』」的問題，已於 2026-08-21（`236cf75`，epic-26 Issue 5）解決。現況：EPUB／TXT／MD 的 `pageLabel` 直接回傳 `null`（不顯示假頁碼），`EpubPageEstimator`／`EpubCharacterCountRepository` 兩個檔案已被刪除。這條候選已解決，不列入本次清單。

## 核心問題

目前 Dart 端顯示的頁碼／總頁數（`EpubPositionInfo.pageIndex`／`totalPages`）來自 foliate-js `progress.js` 的 `SectionProgress.getProgress()`，本質是「每 1500 bytes（XHTML 原始檔位元組數，非可見文字字元數）算一個 location」的近似估算，與 `paginator.js` 實際 DOM 分欄渲染出來的視覺頁數（`View.expand()` 算出的 `contentPages`）完全脫鉤。

---

## 候選 1 · 拆開 pageIndex 與 location 的語意混用

**建議強度**：Strong（純介面重構，不改變任何現有行為，風險低）

**檔案**：`app/android/app/src/main/assets/foliate/main.js:560-575`、`app/lib/reader/epub_position_info.dart`

**Problem**：同一個 `onLocatorChanged` relocate 事件裡，「index」這個詞先後代表兩個完全不同的東西：
- 第 1 個參數（`cfiJson`）內嵌 `index: pageIndex`，實際是 `section?.current`（**章節／spine index**，`main.js:562`）；
- 第 3 個參數（Dart 端收進 `EpubPositionInfo.pageIndex`）卻是 `location?.current ?? pageIndex`（**位元組估算刻度**，`main.js:573`），只有 `location` 不存在時才退回用章節 index 頂替。

退回邏輯 `location?.current ?? pageIndex` 悄悄跨單位轉換；`EpubPositionInfo` 的欄位名稱讓 Dart 端呼叫者（`reader_footer.dart`）直覺以為拿到的是精確視覺頁碼，實際上連 JS 端自己內部都已經分不清楚該用哪個當退回值。介面（呼叫者看到的名字承諾的精度）比實作（底層真正提供的精度）更淺。

**Solution**：`EpubPositionInfo` 拆成語意誠實的欄位——`visualPageIndex`／`visualTotalPages`（真正的 `View.contentPages`，候選 2 落地前恆為 null）與 `locationIndex`／`locationTotal`（現有的 byte 估算）。`main.js` 對應拆成兩個獨立欄位送出，不再共用退回邏輯。接縫落在既有 `onLocatorChanged` 橋接點，不需新開 channel。

**Wins**：
- interface 精度誠實對應 implementation
- 退回邏輯不再跨單位隱式轉換
- 呼叫端可分辨何時可信

**ADR 衝突**：無直接牴觸。ADR 0011 只規定「用 `SectionProgress` 取代 Readium 估算」這件事本身，未規定欄位命名。

---

## 候選 2 · 用已渲染 section 的視覺頁密度校正 location 估算

**建議強度**：Strong（不需新增渲染成本，是候選 1 之後的核心工程）

**檔案**：`app/android/app/src/main/assets/foliate/progress.js:169-224`（`SectionProgress`）、`paginator.js:940`（`View.expand()`）、`paginator.js:2936-2960`（`#preloadNext`，`minPages=5`）

**Problem**：`View.expand()` 對「已渲染」的 section（目前章節＋前後預載）握有精確 `contentPages`（`Math.ceil(contentSize / columnSize)`），但這個數字從未回饋給 `SectionProgress`；`SectionProgress.getProgress()` 全書仍統一假設「1500 bytes = 1 個 location」，兩套計算永不交會。

**Solution**：`view.js` 的 `#onRelocate()` 新增 `updateDensity(index, pages)` 介面——每當某 section 完成 `expand()`，把 `{sectionIndex, contentPages, byteSize}` 回報給密度快取。`SectionProgress.getProgress()` 改吃「已知 section 用實測比例、未知 section 用最近鄰已知比例外插」，取代全書統一常數 1500。

**Wins**：
- leverage：重新使用系統裡已算出、被浪費的精確數字
- locality：精度校正邏輯集中於 `SectionProgress` 一處
- 不需要強制渲染全書

**ADR 衝突**：牴觸 `docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md`——該 ADR 已把「總頁數估算值與使用者原本看到的數字可能不同」列為已接受的取捨。此候選是在既有取捨上加一層漸進式校正（`SectionProgress` 仍是唯一頁碼引擎），非推翻整份 ADR，值得重新開放討論。

---

## 候選 3 · EpubPositionInfo 三層座標重新分層

**建議強度**：Worth exploring（依附候選 1／2，不必獨立立案）

**檔案**：`app/lib/reader/epub_position_info.dart`、`epubcfi.js`

**Problem**：目前 `EpubPositionInfo` 是扁平四欄位 DTO（`locatorJson`／`progression`／`pageIndex`／`totalPages`），把「權威定位（CFI）」「粗略比例（progression／fraction）」「近似頁碼（location）」三種完全不同精度的資料壓進同一層，呼叫端（`reader_screen.dart`）沒有機會表達「這個數字現在有多可信」。

**Solution**：候選 1／2 完成後，把「目前這組資料能提供的精度層級」變成型別的一部分（例如 `visualPageIndex` 為 `null` 時代表該 section 尚未渲染過，UI 端才知道要顯示什麼字樣、該不該顯示跳頁滑桿的絕對刻度）。

**Wins**：
- depth：一個型別誠實表達三層精度
- locality：UI 端判斷邏輯不必外部猜測

**ADR 衝突**：無。

---

## 建議優先順序

候選 1 與候選 2 必須綁在一起做：**先做候選 1**（拆分介面語意，Strong，低風險，純重構不改變行為），**再做候選 2**（接上密度校正，Strong，需與 ADR 0011 決策脈絡確認是否重開這條取捨）。候選 3 順帶完成，不必獨立立案。
