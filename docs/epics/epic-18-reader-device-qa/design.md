# Epic 18 — 真機 UI 精修（版面設定/工具列/書架/直排邊距）：Discovery

## 背景

2026-07-24，使用者在多款真實裝置（含 E-Ink 閱讀器 AiPaper Reader C，824×1648／150 PPI；以及 1404×1872／300 PPI 黑白、702×936／150 PPI 彩色兩款既有測試裝置）上實際使用 App 閱讀，回報 8 項問題。這些問題橫跨已歸檔的多個既有 Epic 的既有功能（`epic-1-library` 書架、`epic-3-fonts-layout` 版面設定、`epic-7-interaction` 閱讀器工具列、`epic-17-epub-render-migration` 直排 CSS/分頁），不隸屬單一既有 Epic，故另立新 Epic 統一追蹤，比照 `docs/epics.md`「任務分類」既有慣例（跨既有功能的真機發現，量級足以獨立成 Epic，非單一 Bug 修復）。

## 使用者回報的 8 項問題（原文摘要）

1. 「版面設定」畫面在 824×1648／150 PPI 裝置上變成滿版、無法退出，需要加入 X 取消按鈕；調整後需確認 1404×1872／300 PPI（黑白）與 702×936／150 PPI（彩色）兩款既有裝置仍正確顯示。
2. 上下工具列高度太高，佔用太多版面，需縮短。
3. 書架首頁封面格數：直立時應為 3 本一行、橫放時應為 4 本一行（原為固定 6 本一行），範例參考 `tmp/sample/書櫃首頁範例.png`。
4. 分類顯示應直接內嵌於書籍清單中，一個分類佔一格、格內以 2×2 拼貼顯示該分類前 4 本書封面。
5. 頁尾「進度 YY% ｜ 第 XXX/OOO 頁」文字列與拖曳進度捲軸分成上下兩列，佔用空間過多。
6. 直排模式下，畫面上緣文字被壓／裁切，版面應往下留白。
7. 本文顯示區域下緣與頁尾進度列之間空白過多（約多出一行可用空間）。
8. 切換為「直排」時，部分書籍會被拆成「上下 2 欄」，需要多一次翻頁才能看完原本一頁的內容，需要提供選項讓使用者可設定為強制單欄。

## 調查結論（人類確認前的初步定位，見 `issues.md` 各 Issue「描述」段落逐項展開）

- 項目 1、3、5 是既有 widget 的既有寫死行為（無關閉按鈕／固定格數／固定兩列版面），改動範圍侷限在單一 Dart widget 檔案，風險低。
- 項目 2（工具列高度）與項目 5（頁尾合併單行）指向同一塊「閱讀畫面上下工具列太占空間」的抱怨，且項目 5 的「合併單行」正是達成項目 2 頁尾瘦身的具體手段，兩者合併為同一個 Issue 處理（`AppBar.toolbarHeight` + `ReaderFooter` 版面重構）。
- 項目 6、7 同源：`readest/foliate-js` 的 `paginator.js` 內建 `--_margin-top`／`--_margin-bottom` 皆寫死 `48px`（`paginator.js:1232/1234`），`main.js` 的 `buildOverrideCss()`（`pageMargins` 偏好）只處理左右 `body { padding }`，從未把使用者的邊距偏好或頁尾實際佔用高度接到這兩個 CSS 自訂屬性——上緣裁切與下緣空白過多是同一個「上下邊距從未被正確計算」問題的兩種症狀，合併為同一個 Issue。
- 項目 8 根因是 `paginator.js` 內建 `--_max-column-count: 2`（`paginator.js:1238`），該行為本身不是缺陷（是 foliate-js 既有的「單頁最多幾欄」機制），但目前完全沒有接上任何使用者可調整的偏好；`attributeChangedCallback()`（`paginator.js:1545-1559`）已經原生支援 `margin-top`／`margin-bottom`／`max-column-count` 三個屬性透過 `view.renderer.setAttribute()` 外部設定，不需要修改 vendored 檔案本身。
- 項目 4（分類 2×2 拼貼方格）目前完全不存在對應 UI/查詢邏輯，量級與其餘 7 項不同（需要新 widget、新查詢、新互動設計），經人類確認後**拆出，不在本 Epic 範圍**，留待未來評估是否另立 Epic。

## 決策（人類已確認）

1. **項目 4 不在本 Epic 範圍**，另外安排。
2. **項目 2 工具列高度**：縮減至約現有高度的 **1/3**（非 1/2）。
3. **項目 8 強制單欄**：新增布林偏好，加入既有「⚙️版面設定」（`ReaderSettingsSheet`）畫面，**預設關閉**（維持 foliate-js 原有的自動判斷行為，使用者遇到問題時才手動開啟）。

## 範圍界定

- 僅涵蓋前述 7 項（項目 1/2/3/5/6/7/8），對應 `issues.md` 的 5 個工單（項目 2+5 合併、項目 6+7 合併）。
- 不修改 `readest/foliate-js` 釘定版本本身（`view.js`／`paginator.js`／`overlayer.js` 等 vendored 檔案）——項目 6/7/8 皆透過既有 `attributeChangedCallback()` 支援的外部 `setAttribute()` 機制達成，僅修改本專案自己的 `main.js` 進入點與 Dart／Kotlin 偏好傳遞管線。
- 不改變 `BookReaderPrefs` 既有欄位的既有語意，項目 8 新增欄位比照既有 `showHeader`/`showFooter` 等「單書覆寫、無全域預設層」欄位的既有慣例（見 `book_reader_prefs.dart:43-44`）。

## 測試裝置

- `3CEF42ECD491687`（9491G，Android 15／API 35）——本專案既有測試裝置。
- 使用者回報環境：AiPaper Reader C（824×1648／150 PPI）、既有測試裝置 1404×1872／300 PPI（黑白）、702×936／150 PPI（彩色）——項目 1 的驗收需在這三種尺寸/密度下確認版面設定畫面皆可正確顯示與關閉。

---

## 第二輪真機使用回報（2026-07-26，`/grill-with-docs` Discovery）

Issue 1-6 全數完成合併後，使用者持續真機使用中再回報 5 項問題，經 grilling session 逐項釐清並確認技術根因與決策，見下方。

### 使用者回報的 5 項（原文摘要，含 grilling 過程中的澄清）

1. 流式 EPUB（`FoliateEpubReaderView`）目前的選單列（AppBar 動作按鈕）應調整成跟 FXL EPUB（`EpubReaderView`）一樣，使用浮動按鈕（FAB 樣式）。
2. 「顯示頁首」改名為「顯示頁眉」，語意收斂為「只顯示閱讀中的章節名稱」這個純資訊；原本掛在 AppBar actions 上的功能性按鈕（TOC／版面設定／筆記）統一移到浮動選單列，讓「資訊顯示」與「功能操作」分離。
3. 「顯示頁尾」改為「顯示進度」：橫排時顯示在畫面最下面，直排時顯示在左下角一小塊（參考 `tmp/image/reading_process.jpg`，圖中左下角直排小字串即目前閱讀頁次）；純資訊顯示，跳頁滑桿這個「功能操作」獨立移到浮動選單列，不再與進度顯示綁在同一個元件裡。
4. 流式 EPUB 在實體機上無法長按選字建立劃線（emulator/開發過程未必能重現，真機上手勢似乎被攔截）。
5. ADR 0012 記錄的已知限制——「雙欄」模式的 `max-inline-size` 是呼叫 `applyPreferences()` 當下的一次性快照，裝置旋轉/視窗尺寸變化不會重新計算——需要補上「裝置旋轉/視窗尺寸變化時重新呼叫 `applyPreferences()`」的機制。

### 調查結論

- **項目 1+2+3 同源**：現況 streaming EPUB 用 in-flow `AppBar`（含頁眉文字＋TOC/設定/筆記 3 個 icon）+ in-flow `ReaderFooter`（頁碼＋跳頁滑桿），`reader_screen.dart:1192-1203`／`1523-1533` 既有註解明確記載頁尾 in-flow 顯示/隱藏仍會改變 body 實際高度、觸發底下 WebView 整本重新分頁的已知未解問題。FXL 完全沒這問題，因為其頁眉/按鈕/書籤全部是 `Positioned` 浮動疊加層（`Stack` 內 `ClipOval`+黑底圓鈕），`appBar: null`，body 高度恆定不變。三項合併為 Issue 7，把 streaming EPUB 的整組 chrome 全部改成跟 FXL 同款的浮動疊加層架構，順便解掉這個已知 resize 問題。
- **項目 4 根因初步假設**：`foliate_epub_reader_view.dart:364-409` 的 `build()` 在 `AndroidView`（WebView）上疊了一層全螢幕 `GestureDetector`（9 宮格熱區），`behavior: opaque` 且註冊 `onHorizontalDragStart`/`onVerticalDragStart`（空 handler）。此機制記載於 `docs/archive/2026-07-24-epic-7-interaction/design.md:115`，是**刻意**設計——目的是讓格子只認 tap、不讓底層原生（Readium／foliate-js）自己的滑動翻頁手勢跟 tap 熱區打架（ADR 0009/0010）。此機制原本只用在 FXL（`EpubReaderView`，決策 #7 排除劃線功能，不會踩到衝突），但被原樣複製到同樣需要支援劃線的 `FoliateEpubReaderView`，長按選字後「拖曳選取控點調整範圍」這個手勢很可能被這層攔截，傳不到底下 WebView。**不是**單純刪除這兩行就能解決——需要先確認拿掉後是否會讓 foliate-js 內建滑動翻頁手勢跑出來與 tap 熱區衝突（拆東牆補西牆風險）。
  - **參考研究**：`tmp/epic-18/reviews/anx_reader_foliate_js_highlighting_analysis.md`（開源專案 anx-reader 基於 foliate-js 的畫線實作分析）證實 Android 平台上「原生選取 Handle 拖拽」是真實存在、需要特別處理的獨立手勢類別——anx-reader 的做法是監聽 `pointercancel` 與 `contextmenu` 事件，避免拖拉選取控制點時誤觸自訂選單。這佐證了本專案假設的手勢競技場衝突方向是合理的，但也提醒 Issue 8 診斷時除了拿掉 no-op drag handler 外，可能還需要檢查 Android WebView 原生選取 UI（放大鏡/複製貼上泡泡選單）是否與 `main.js` 既有 `selectionchange` 監聽器（`main.js:432-462`）互相干擾，必要時比照 anx-reader 補上 `contextmenu`/`pointercancel` 的專屬處理。該報告第 6 節另建議 E-Ink 模式下劃線改用純黑白實心底線避免半透明色殘影——與本 Issue 無直接關聯，列為未來可評估項目，不在本次範圍。
- **項目 5**：`main.js` 的 `window.applyPreferences(prefs)`（`main.js:105-180`）目前無狀態（除 `currentWritingMode`），每次由 Kotlin 端帶完整 prefs 呼叫，沒有快取機制可供「resize 後重新套用」使用。

### 決策（經 grilling session 確認）

1. 5 項全部併入 `epic-18-reader-device-qa`（不另立新 Epic），依相依性拆為 3 個新 Issue：
   - **Issue 7**：流式 EPUB Chrome 重構（項目 1+2+3）
   - **Issue 8**：流式 EPUB 真機無法畫線（項目 4）
   - **Issue 9**：旋轉/視窗尺寸變化重新呼叫 `applyPreferences()`（項目 5）
2. **Issue 7 整體架構**：streaming EPUB 的 `AppBar` 整個改為 `null`（跟 FXL 一樣），頁眉文字／進度顯示／功能按鈕全部改為 `Positioned` 浮動疊加層，共用既有 `_chromeVisible` 顯示/隱藏機制。
   - 功能按鈕採**散落式個別浮動圓鈕**（比照 FXL 現有 `ClipOval`+黑底圓鈕寫法），非單一 FAB 展開選單。補齊到 6 顆：返回（左上）、TOC（右上1）、版面設定（右上2）、書籤 toggle ★（右上3，邏輯複用 FXL 既有 `_toggleFxlBookmark`，改泛用化供兩種格式共用）、筆記（右上4）、進度/跳頁（獨立第 6 顆，內含原 `ReaderFooter` 的跳頁滑桿+輸入框功能）。
   - 「顯示頁眉」章節名稱改為**純顯示、不可點擊**（點擊開 TOC 這個功能完全交給浮動 TOC 按鈕，呼應「資訊與功能分離」原則），位置：頂部置中。
   - 「顯示進度」純資訊、不可互動（拖拉跳頁功能已獨立到第 6 顆浮動鈕），跟其餘浮動元件一起隨 `_chromeVisible` 收合；內容維持現有「168/197」阿拉伯數字格式（不新增中文數字轉換），橫排置於畫面最下方，直排時用 `RotatedBox` 轉 90 度置於左下角一小塊；不額外顯示時鐘。
3. **Issue 8 執行流程**：比照本專案既有的真機 mutation test 方法論（Issue 5/6 皆用此法驗證）：(a) 真機重現現況、(b) 暫時拿掉 `onHorizontalDragStart`/`onVerticalDragStart` 兩行重測，確認畫線是否恢復、滑動翻頁是否出現 regression、(c) 視結果決定實際修法（可能全部拿掉、可能需要更精細的「有作用中選取範圍時才放行拖曳」判斷，必要時參考 anx-reader 的 `contextmenu`/`pointercancel` 處理方式）、(d) 確認 tap 熱區導覽功能未退化。先查再定修法，不預先假設單一方案。
4. **Issue 9 機制**：純 JS 端自行解決，不修改 vendored `paginator.js`（比照 ADR 0011），也不需要新增 Dart/Kotlin 橋接。`main.js` 新增模組級 `lastAppliedPrefs` 變數（`applyPreferences()` 呼叫時存一份），另掛一個本專案自建的 `ResizeObserver`（與 `paginator.js:1163` 既有的那個是兩個獨立 observer，互不干擾），resize 觸發後 debounce ~200ms 重新呼叫 `window.applyPreferences(lastAppliedPrefs)`。不特例只挑「雙欄模式」才重算——整包 prefs 全部重套用（其餘欄位重算是 idempotent、無副作用，比照專案「不特地加狀態抑制無害重複呼叫」的既有慣例）。

### 範圍界定（第二輪）

- Issue 7/8/9 皆不修改 `readest/foliate-js` 釘定版本本身（`view.js`／`paginator.js`／`overlayer.js`），只修改本專案自己的 `main.js`／Dart／Kotlin 程式碼，比照本 Epic 既有慣例（ADR 0011）。
- Issue 7 不新增任何 `BookReaderPrefs` 持久化欄位——純 UI 重構（chrome 從 in-flow 改為浮動疊加層），既有的 `showHeader`/`showFooter` 欄位語意不變，只是 UI 呈現方式與標籤文字調整。
- Issue 8 不預先鎖定修法，Issue 描述本身即「先診斷、再依診斷結果定修法」，允許實作階段依真機驗證結果調整最終方案。
- 沒有項目需要另立 ADR（皆非「難以回頭＋意外＋真權衡」的決策），也沒有新詞彙需要寫入 `CONTEXT.md`（沿用既有「沉浸模式／熱區」詞彙）。

### 相關佐證

- `tmp/image/reading_process.jpg`（項目 3 直排進度顯示位置參考）
- `tmp/epic-18/reviews/anx_reader_foliate_js_highlighting_analysis.md`（Issue 8 根因佐證與 Android 手勢處理參考）
- `docs/adr/0012-column-mode-replaces-single-column.md`「已知限制」段（Issue 9 起源）
- `docs/archive/2026-07-24-epic-7-interaction/design.md:115`（no-op drag 搶手勢競技場機制的原始設計意圖）

---

## Spike 結論：flutter_inappwebview 選取偵測驗證（2026-07-26）

### 背景

Issue 8 確認 Android WebView 原生選取完全在 native layer 運作，標準 `android.webkit.WebView` 包在 Flutter 官方 `AndroidView` 下時，所有 DOM 事件（`selectionchange`、`touchstart`、`pointerdown` 等）均不觸發，且 Flutter PlatformView 的 touch handling 攔截了所有觸控事件，導致 Kotlin 端的 `setOnTouchListener`/`setOnLongClickListener` 也不觸發。

### Spike 目的

驗證 `flutter_inappwebview` 套件能否解決上述限制，並確認其 `shouldInterceptRequest` 機制不會重新踩到既有 Kotlin `WebViewAssetLoader` 已解決的 ES module CORS/MIME 陷阱。

### 驗證結果

| 驗證項目 | 結果 | 說明 |
|----------|------|------|
| InAppWebView 真機載入 | ✅ PASS | WebView 成功載入並執行 JS |
| JS handler 註冊 | ✅ PASS | `addJavaScriptHandler` 正常運作 |
| ES module 載入 | ✅ PASS | `shouldInterceptRequest` + MIME 覆寫機制運作正常 |
| 選取控點拖曳偵測 | ✅ PASS | 真機 adb 模擬長按選取與拖曳控點，`selectionLog` 成功取得 3 筆隨拖曳動態變化的內容紀錄 |

### 結論

**GO** — `flutter_inappwebview` 在真機上展現的 touch handling 與 DOM `selectionchange` 事件轉發能力，解決了標準 Android WebView + Flutter PlatformView 的根本限制（ADR 0013）。ES module 載入亦不踩既有 CORS/MIME 陷阱。

### 下一步

- Issue 10：整合 `flutter_inappwebview` 到 `FoliateEpubReaderView`
- 保留 `flutter_inappwebview` 依賴（供 Issue 10 繼續使用）

### 報告路徑

完整報告見 `docs/epics/epic-18-reader-device-qa/reviews/spike-flutter-inappwebview-selection.md`

---

## 第三輪真機使用回報（2026-07-28，`/diagnose` Discovery）

Issue 7-10 全數完成合併後，使用者持續真機使用中再回報 4 項問題，透過 `/diagnose` 直接讀碼確認根因（皆為確定性、可從程式碼判讀的問題，不需另建真機除錯迴圈），逐項釐清後拆為 4 個新 Issue。

### 使用者回報的 4 項（原文摘要）

1. 流式 EPUB 點選進度條按鈕要拖拉進度時，進度條會被下方系統工具列蓋住（無系統工具列的機種不受影響）。
2. 流式 EPUB 的進度 FAB 按鈕，應跟其他 FAB 按鈕同時出現，不應被「顯示頁尾」開關額外限制。
3. 「顯示頁首」「顯示頁尾」開啟時，頁首/頁尾應跟電子書內文同時常駐顯示，不應該要點了選單（`_chromeVisible` 沉浸模式）才顯示。
4. 流式 EPUB 左右留白過多；現有單一「邊距」滑桿同時驅動左右留白（CSS `em` 單位、隨字級等比例放大）與直排模式下的上下邊距（`main.js` Issue 4 機制，橫排完全不受影響），使用者希望能各自獨立調整上/下/左/右四個方向。

### 調查結論

- **項目 1**：`_openFoliateProgressSheet()`（`reader_screen.dart:1836-1845`）的 `builder` 直接回傳 `_buildFoliateEpubFooter(positionInfo)`，缺少 `SafeArea` 包裹。對照同檔案內其餘 Bottom Sheet——`ReaderSettingsSheet`（`reader_settings_sheet.dart:144`）、`TocBottomSheet`（`toc_bottom_sheet.dart:114`）皆已用 `SafeArea` 包裹——確認這是遺漏，非設計如此。
- **項目 2**：`reader_foliate_progress_button` 的顯示條件（`reader_screen.dart:1618-1621`）比其餘 5 顆浮動按鈕多了 `(_resolved?.showFooter ?? true)`。這是 Issue 7 計畫階段的**刻意設計**（理由：「看不到進度就不該讓使用者以為能跳頁」的一致性考量），非缺陷；本次使用者回報後決定推翻此設計，統一比照其餘 5 顆按鈕只看 `_chromeVisible`。
- **項目 3**：全 App 既有「沉浸模式」設計（`_chromeVisible`，見上方第一輪「決策」#14）——點擊畫面中央熱區同時切換 PDF 的 AppBar/頁尾、FXL 與流式 EPUB 的所有浮動按鈕＋頁首＋進度文字。使用者回報後決定：**僅流式 EPUB**（`_dispatchedIsFixedLayout == false`）的頁首文字／進度文字，從 `_chromeVisible` 拆出來獨立（改為純綁 `showHeader`/`showFooter`），FXL（本無頁首/頁尾文字，只有按鈕）與 PDF（in-flow 頁尾，牽動既有 resize 限制，範圍外）不受影響。6 顆浮動**功能按鈕**（含項目 2 修正後的進度/跳頁鈕）仍全部跟隨 `_chromeVisible`——這次回報只拆分「資訊顯示」，不動「功能操作」的既有沉浸模式行為。
- **項目 4**：確認根因為 `buildOverrideCss()`（`main.js:92-93`）的 `body { padding: 0 ${1.5 * prefs.pageMargins}em }`——`em` 單位隨同函式內 `html { font-size: X% }` 等比例放大，字級調越大、左右留白隨之等比膨脹（本 Epic 稍早的 ViWoods Air Reader 字級診斷已將字級滑桿上限由 40 調到 80，副作用更明顯）。目前單一「邊距」滑桿同時驅動：(a) 左右 CSS padding（`buildOverrideCss()`，所有排版方向皆生效）、(b) 直排模式下的上下邊距（Issue 4 引入的 `main.js` 機制，僅直排、獨立的 px 公式，橫排永遠固定 `paginator.js` 內建 48px，完全不受這個滑桿影響）——一個滑桿橫跨兩種不同單位/不同適用範圍的機制，語意混亂。
  - **與 ADR 0005 的關係（重要）**：`BookReaderPrefs.pageMargins` 欄位註解明載「單一數值，四邊同步變動，見 ADR 0005」——該 ADR 決定不做四邊獨立邊距，理由是反編譯 Readium `EpubPreferences` 確認其原生只有單一 `pageMargins` 純量欄位，若要四邊獨立需自建 CSS 覆寫層，成本/風險太高，故 Epic 3 當時不採用。**但 ADR 0005 的調查範圍是 `EpubReaderView`（Readium 原生 kotlin-toolkit，供 FXL 使用）**，成書於 Epic 17 的 foliate-js 遷移**之前**。確認 `FxlSettingsSheet`（`app/lib/screens/fxl_settings_sheet.dart`）完全沒有邊距滑桿 UI——`pageMargins` 這個欄位在目前產品中，實際上只由流式 EPUB 專用的 `ReaderSettingsSheet` 寫入。而流式 EPUB 走的正是 Epic 17 為了 `main.js` 而自建的 CSS 覆寫層（`buildOverrideCss()`）——ADR 0005 當初認定「自建 CSS 覆寫層成本過高」的技術障礙，對流式 EPUB 這條路徑**已經不存在**（Epic 17 已經蓋好了）。故本次四邊獨立邊距的範圍**僅限流式 EPUB**（`FoliateEpubReaderView`/`main.js`），不動 `EpubReaderView`／Readium／FXL 路徑，`pageMargins` 這個既有純量欄位維持原樣（透過 `EpubReaderView.pageMargins` 屬性繼續傳遞，供 FXL 未來若要補上邊距 UI 時使用，目前 FXL 無 UI 寫入它，形同無害保留）——不是推翻 ADR 0005，而是新增一個 ADR 縮小其適用範圍：ADR 0005 的限制對 FXL/Readium 路徑依然成立，僅對流式 EPUB 這條路徑不再適用。

### 決策（人類已確認）

1. 4 項全部併入 `epic-18-reader-device-qa`（不另立新 Epic），依範圍拆為 4 個獨立新 Issue：
   - **Issue 11**：流式 EPUB 進度/跳頁 Bottom Sheet 補上 `SafeArea`（項目 1）
   - **Issue 12**：進度/跳頁浮動按鈕移除 `showFooter` 額外限制（項目 2）
   - **Issue 13**：流式 EPUB 頁首/進度文字從沉浸模式拆出、跟內文常駐顯示（項目 3）
   - **Issue 14**：流式 EPUB 邊距重新設計為上/下/左/右 4 個獨立欄位（項目 4）
2. **Issue 13 範圍**：僅流式 EPUB 的頁首/進度**文字**（純資訊顯示）獨立於 `_chromeVisible`；6 顆浮動**功能按鈕**（含 Issue 12 修正後的進度/跳頁鈕）維持跟隨 `_chromeVisible`；FXL／PDF 不受影響。
3. **Issue 14 範圍**：直接做滿 4 個獨立欄位（上/下/左/右），對應 `docs/prd.md`「版面控制項」原始需求「獨立的上/下/左/右邊距滑桿」。範圍僅限流式 EPUB（`FoliateEpubReaderView`/`main.js`），新增獨立 ADR（見 ADR 0014）縮小 ADR 0005 的適用範圍（ADR 0005 對 FXL/Readium 路徑依然有效），不修改 `EpubReaderView`/Readium 既有 `pageMargins` 傳遞路徑。

### 範圍界定（第三輪）

- Issue 11-14 皆不修改 `readest/foliate-js` 釘定版本本身（`view.js`／`paginator.js`／`overlayer.js`），比照本 Epic 既有慣例（ADR 0011）。
- Issue 14 新增 `BookReaderPrefs` 持久化欄位（上/下/左/右邊距各自獨立），需要 SQLite schema migration（目前版本見 `sqlite_library_repository.dart:30`），且需要修改 `ReaderSettingsSheet` 既有的單一「邊距」滑桿 UI；`pageMargins` 舊欄位保留、不刪除、不遷移既有值（FXL/Readium 路徑繼續使用，見 ADR 0014）。
- Issue 11/12/13 皆不新增/修改任何 `BookReaderPrefs` 欄位，純 UI 顯示條件調整。
- Issue 14 需要新增 ADR 0014（架構層面涉及持久化 schema 且與既有 ADR 0005 的適用範圍相關，屬「難以回頭＋意外＋真權衡」的決策，符合本專案 ADR 撰寫門檻）。

### 相關佐證

- `docs/adr/0005-epub-page-margins-single-value.md`（Issue 14 範圍界定的關鍵前置決策）
- `docs/adr/0014-foliate-epub-independent-margins.md`（Issue 14 新增，縮小 ADR 0005 適用範圍）
- `app/lib/reader/book_reader_prefs.dart:26`（`pageMargins` 欄位註解指向 ADR 0005）

---

## Issue 15 根因重新診斷與人工版面覆蓋功能（2026-07-30，`/grill-with-docs` Discovery）

Issue 15 原始條目（見 `issues.md`）記錄的是 2026-07-29 於 `epic-19-shelf-reading-enhance` Issue 1 程式碼審查時意外發現的「FXL 橫屏雙頁置中留白」現象，當時僅止於「初步判斷」、尚未進入正式 Discovery。使用者後續實際使用中確認：部分書檔本質上是漫畫（理應為固定版面 FXL），但「引擎分派判斷」（見 `CONTEXT.md`）誤判為流式 EPUB，導致改走 `foliate-js` 路徑後渲染異常——這才是本次要處理的根因，**取代**原始條目「雙頁置中留白」的推論方向（兩者是否為同一問題領域的殘留，留待後續有人真的遇到雙頁置中留白症狀時再另行處理，不在本次範圍內延續調查）。

### 範圍界定（本次 grilling 決策）

僅新增**人工版面覆蓋**（見 `CONTEXT.md`）救濟手段，不調查/修正「引擎分派判斷」（`extractMetadata`/`detectEpubLayout` 原生 channel）本身的誤判邏輯——那是另一個獨立的診斷工作，成本與風險評估留待未來有需要時再啟動。

### 決策（人類已確認）

1. **資料層零新增**：不新增欄位、不需要 SQLite migration。「強制 FXL」直接呼叫既有 `LibraryRepository.updateBook(book.copyWith(isFixedLayout: true))`；「恢復自動判斷」直接重新呼叫既有 `LibraryRepository.detectAndCacheEpubLayout(bookId, filePath)`（本來就會重新偵測並覆寫資料庫，語意上完全等同「回到系統原始判斷」，不需要另外保留一份「使用者是否覆蓋過」的旗標）。
2. **UI 入口**：不新增長按手勢或三點選單，沿用 `LibraryScreen` 現有多選模式（`_enterSelectionMode`/`_selectedBookIds`），在既有選取工具列（「移動到分類」旁）新增兩顆獨立按鈕：「強制 FXL」／「恢復自動判斷」。批次套用於選取集合中的所有 EPUB 書籍。
3. **非 EPUB 混選**：兩顆按鈕在選取模式下永遠顯示（比照「移動到分類」「刪除」既有慣例），若選取集合中含 PDF/TXT，執行時自動跳過非 EPUB 書籍、不報錯。
4. **不需要確認對話框**：比照「移動到分類」（僅彈目的地選擇對話框，不算確認），非「刪除」模式——理由是此操作可隨時再按另一顆按鈕復原，不像刪除書籍不可逆。
5. **不需要完成後 SnackBar**：比照「移動到分類」既有模式，執行完畢後直接退出選取模式、重新整理書架，不額外顯示提示。
6. **不新增書架視覺標記**：書籍封面/列表不顯示「已人工覆蓋」的 badge，保持最小變動。
7. **生效時機零額外處理**：`ReaderScreen._resolveEpubEngineDispatch()` 本來就是每次開書時才解析引擎，下次從書架開啟該書時自然套用新值，不需要改動 `ReaderScreen`/`FoliateEpubReaderView`/`EpubReaderView`。

**實作備註（已於程式碼審查後確認接受，見 `tmp/epic-18/review-issue-15.md` Important #2）**：實作階段真機驗證發現決策 #7 的前提不完全成立——`ReaderScreen._isFixedLayout`（驅動 FXL 懸浮 chrome 顯示的執行期狀態，見 `CONTEXT.md`「固定版面（FXL）」詞條）雖然不影響*引擎分派*，但仍會被 native view 的 `onLayoutResolved`/`onPageRendered` 異步回報覆蓋，導致「強制 FXL」後閱讀器設定表單短暫顯示流式選項而非 FXL 選項。追加 commit `97878c4` 在 `_resolveEpubEngineDispatch()`／`_handleLayoutResolved()`／`_handleFoliateLayoutResolved()` 三處新增 `widget.isFixedLayout == true` 時不允許 native 回報覆蓋 `_isFixedLayout` 的保護邏輯，此屬計畫範圍外的追加，已經人類於程式碼審查後確認接受，不需要回退。**已知殘留限制**：此修復只保護了 `ReaderScreen._isFixedLayout`，`EpubReaderView` widget 自己內部同名欄位（`app/lib/reader/epub_reader_view.dart:326`，驅動 FXL 換頁熱區疊加層顯示）與 Kotlin 原生端 `EpubReaderView.kt` 的雙頁 spread 計算（`applyFxlFitScale()`）仍完全依賴 Readium 自己對書本 metadata 的獨立判讀、不受「強制 FXL」影響——後者正是真機驗收發現「橫向雙頁模式退化成單頁」症狀的根因，已判斷超出本 Issue 範圍，另立新 Issue 追蹤（見 `issues.md`）。

### 詞彙釐清（見 `CONTEXT.md`）

grilling 過程中發現 `CONTEXT.md` 原「固定版面（Fixed-Layout, FXL）」詞條把「開書前的引擎分派判斷」與「開書後 Readium 執行期回報的 `EpubLayoutInfo.isFixedLayout`」混為一談，已拆分為「固定版面（FXL）」「引擎分派判斷」「人工版面覆蓋」三個獨立詞條。

### 相關佐證

- `docs/epics/epic-19-shelf-reading-enhance/` Issue 1 程式碼審查報告「附錄：FXL 雙頁置中問題初步判斷」（原始發現來源，已被本次根因取代）
- `app/lib/library/models/book.dart:41-50`（`Book.isFixedLayout` 既有註解）
- `app/lib/screens/reader_screen.dart:282-309`（`_resolveEpubEngineDispatch()`）
- `app/lib/library/sqlite_library_repository.dart:449-462`（`detectAndCacheEpubLayout()`）

---

## Issue 16／17 修復方向 Discovery（2026-07-30，`/grill-with-docs` Discovery）

Issue 15 程式碼審查（`tmp/epic-18/review-issue-15.md` Important #1）確認「強制 FXL 後橫向雙頁模式退化成單頁」的根因，並拆出 Issue 16 追蹤。本次 grilling 針對修復方向的架構決策展開，過程中發現審查報告本身遺漏的額外事實、以及一個無法從程式碼確認、需要真機驗證的核心不確定性。

### 查證發現（超出審查報告範圍）

1. **`EpubReaderView.kt` 實際有 3 個、非審查報告所述 2 個獨立讀取 `publication.metadata.layout` 的檢查點**：
   - `EpubReaderView.kt:501`（`applyFxlFitScale()`，雙頁 spread 位置/縮放計算，審查報告已提到）
   - `EpubReaderView.kt:1199`（回報 `onLayoutResolved` 給 Dart 端，審查報告已提到）
   - `EpubReaderView.kt:998`（**審查報告未發現**）——決定是否註冊原生端 tap 熱區監聽器（`epic-7-interaction` Issue 6，僅流式路徑用）。若「強制 FXL」的書被 Readium 判定非 FXL，這裡會同時註冊原生端 tap 監聽器，與 Dart 端已疊上的 FXL 專屬 9 宮格 `GestureDetector`（`epic-7-interaction` Issue 5）同時作用，可能造成雙重輸入處理衝突——這是額外風險，非本次修復的必要條件，僅列為 Spike 附帶驗證項目。

2. **更根本的不確定性**：上述 3 個檢查點只是本專案自己的 bookkeeping，真正決定 WebView 渲染模式（FXL 左右並排 vs. reflowable 單欄連續捲動）的是 Readium 官方元件 `EpubNavigatorFragment`（`readium-kotlin-toolkit`，非本專案程式碼）。查證 `EpubNavigatorFragment.Configuration`（`EpubReaderView.kt:819-853`，本專案唯一能設定的組態介面：字型、選字回呼、裝飾模板）**沒有任何欄位可以覆寫 `EpubNavigatorFragment` 自己對 `publication.metadata.layout` 的獨立判讀**。也就是說：即使把本專案自己的 3 個檢查點都改成信任「強制 FXL」，`EpubNavigatorFragment` 本身是否會跟著改變渲染模式**無法從程式碼確認**，需要真機實測。

見 `CONTEXT.md`「Readium 內部版面渲染決策」新詞條，區分此第三層概念與既有的「固定版面（FXL）」「引擎分派判斷」。

### 決策（人類已確認）

1. **修復架構**：3 個檢查點改為讀取單一 class 層級的典範值（例如 `effectiveIsFixedLayout`），一次計算、全部引用，取代各自獨立重算 `publication.metadata.layout == Layout.FIXED` 的現狀——避免像審查報告建議的「各自改 OR 條件」那樣容易漏改（審查報告自己就漏了第 3 個檢查點）。
2. **旗標傳遞方式**：「強制 FXL」旗標新增為 `openBook()` 的專屬參數（非塞進既有 `initialPreferences` Map）——理由是這個旗標語意上是「開書前已確定、不會在閱讀中途改變的書本事實」（同 `Book.isFixedLayout` 語意層級），不是使用者可隨時調整的版面偏好（`dualPageMode`/`pageMargins` 等透過 `initialPreferences`/`setPreferences` 動態更新的既有語意），混進同一個 Map 容易誤導成「可動態改變」。
3. **核心假設不確定，先做 Spike 驗證**（比照 ADR 0011／Issue 8 既有慣例，先驗證核心假設、GO 才進入完整實作）：
   - **範圍**：不寫完整 Dart→Kotlin 旗標傳遞管線，直接在 `EpubReaderView.kt` 的 3 個檢查點硬編碼 `true`（或臨時 debug flag）模擬「強制 FXL 已生效」，最小範圍驗證 `EpubNavigatorFragment` 是否真的跟著渲染成 FXL。硬編碼不進 `main`，僅真機臨時 build（比照 Issue 8 throwaway harness 慣例，過程素材放 `tmp/`，已 gitignore）。
   - **測試素材**：沿用 Issue 15 真機驗收時已知會誤判為流式的同一本漫畫 EPUB；測試裝置固定 `3CEF42ECD491687`。
   - **附帶驗證**：同一次真機驗證順便確認上方查證發現 #1 的 tap 熱區雙重處理風險（不影響 GO/NO-GO，僅記錄入報告）。
   - **GO**：橫向雙頁模式下，該書真的顯示兩頁並排且翻頁行為正常（非兩個單頁正常顯示、非頁碼順序錯誤）。
   - **NO-GO**：渲染結果仍是單頁、當機、或畫面損壞。
   - **報告路徑**：`docs/epics/epic-18-reader-device-qa/reviews/spike-issue16-fxl-metadata-override.md`。
4. **Issue 結構**：**保留 Issue 16 現狀**（問題描述＋根因追蹤不變），**新增 Issue 17** 作為 Spike 本身（分支 `spike/epic-18-issue-17-fxl-metadata-override`）。GO 之後再視情況新增完整實作工單（含完整 Dart→Kotlin 旗標傳遞管線），NO-GO 則回頭評估 Issue 16 的其餘替代方案（例如接受此限制、或在 UI 上提示使用者「強制 FXL 對此類書籍的雙頁排版效果有限」）。

### 範圍界定

- Spike（Issue 17）不修改 `readium-kotlin-toolkit` 本身（第三方官方 library，非本專案程式碼），比照本 Epic 對 `readest/foliate-js` 的既有態度（不修改 vendored/第三方程式碼本身）。
- Spike 不需要建立 ADR（尚未進入架構決策階段，是驗證假設）；若 GO 後的完整實作階段决定旗標傳遞的具體設計有「難以回頭＋意外＋真權衡」性質，屆時再評估是否需要 ADR。

### 相關佐證

- `tmp/epic-18/review-issue-15.md` Important #1（Issue 16 根因原始來源）
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 16／Issue 17
- `CONTEXT.md`「Readium 內部版面渲染決策」新詞條
- `docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md`（foliate-js Spike-first 既有慣例，本次比照的方法論）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:501,819-853,998,1199`

---

## Issue 17 Spike 結論：強制 FXL 覆蓋檢查點後 `EpubNavigatorFragment` 渲染行為（2026-07-30）

### 背景

Issue 16 確認「強制 FXL 後橫向雙頁模式退化成單頁」的根因，並拆出 Issue 17 作為 Spike 驗證核心假設：`EpubReaderView.kt` 有 3 個各自獨立讀取 `publication.metadata.layout == Layout.FIXED` 的檢查點，但真正決定 WebView 渲染模式的是 Readium 官方元件 `EpubNavigatorFragment`，其 `Configuration` 沒有任何欄位可以覆寫它自己對書本 metadata 的獨立判讀。

### Spike 目的

用最小範圍的硬編碼（不寫完整 Dart→Kotlin 旗標傳遞管線）覆寫本專案自己的 3 個檢查點後，觀察 `EpubNavigatorFragment` 是否真的會跟著渲染成 FXL。

### 驗證結果

| 驗證項目 | 結果 | 說明 |
|----------|------|------|
| Task 1：基準觀察（修改前） | ✅ 重現 Issue 16 症狀 | 畫面只顯示一頁（固定在左邊），翻頁行為為一頁一頁切換 |
| Task 2：硬編碼 3 個 `isFixedLayout` 檢查點後 | ❌ 畫面仍為單頁 | `EpubNavigatorFragment` 不跟隨 `EpubReaderView.kt` 的 `isFixedLayout` 標誌 |
| Task 2 附帶驗證：tap 熱區雙重處理風險 | ⏭️ 跳過 | 因主要假設已否決（NO-GO），tap 熱區風險已無意義 |

### 結論

**NO-GO** — `EpubNavigatorFragment` 不跟隨 `EpubReaderView.kt` 的 `isFixedLayout` 標誌。其渲染模式由 Readium 官方元件獨立判讀 publication metadata 決定，本專案無法透過覆寫自身檢查點來影響 `EpubNavigatorFragment` 的渲染行為。

### 下一步

- 回頭評估 Issue 16 的其餘替代方案（例如接受此限制、或在 UI 上提示使用者「強制 FXL 對此類書籍的雙頁排版效果有限」）
- 若雙頁模式為必要功能，需評估是否更換閱讀引擎（但成本極高）

### 報告路徑

完整報告見 `docs/epics/epic-18-reader-device-qa/reviews/spike-issue16-fxl-metadata-override.md`

---

## Issue 18 Spike 結論：`Publication.Builder` 重建 `metadata.layout` 後 `EpubNavigatorFragment` 渲染行為（2026-07-30）

### 背景

Issue 17 Spike 確認「硬編碼 3 個 `isFixedLayout` 檢查點」無法影響 `EpubNavigatorFragment` 的渲染模式（NO-GO）。Issue 18 改用替代方案：用 `Publication.Builder` 重建整個 `Publication` 物件，將 `metadata.layout` 強制設為 `Layout.FIXED`，讓 Readium 官方元件收到的 metadata 本身就標記為 FXL。

### Spike 目的

驗證：若重建後的 `Publication` 物件被傳入 `EpubNavigatorFactory`，`EpubNavigatorFragment` 會根據這個被修改過的 metadata 判斷為 FXL，進而渲染成雙頁並排。

### 驗證結果

| 驗證項目 | 結果 | 說明 |
|----------|------|------|
| Task 1：基準觀察（修改前） | ✅ 重現 Issue 16 症狀 | 畫面只顯示一頁（固定在左邊），翻頁行為為一頁一頁切換 |
| Task 2：`Publication.Builder` 重建 `metadata.layout = Layout.FIXED` 後 | ✅ 雙頁 FXL 並排 | 畫面呈現雙頁並排效果，翻頁正常，熱區翻頁正常 |
| Task 2 Service Loss 驗證 | ⚠️ 部分異常 | 進度條不可見、頁數呈現模式與預期不同，疑似因 `ServicesBuilder()` 空物件導致 |

### 結論

**GO** — `EpubNavigatorFragment` 會根據傳入的 `Publication` 物件的 `metadata.layout` 決定渲染模式。透過 `Publication.Builder` 重建物件並強制設定 `metadata.layout = Layout.FIXED`，可以讓 Readium 官方元件正確判斷為 FXL，進而渲染成雙頁並排。

### `Publication.Builder` API 實際簽名

Readium kotlin-toolkit 3.3.0 的 `Publication.Builder` 實際簽名為：

```kotlin
Publication.Builder(manifest: Manifest, container: Container<Resource>, servicesBuilder: ServicesBuilder)
```

- **不是** `Publication.Builder(publication, json)` — 原始假設錯誤
- `container` 標記為 `@InternalReadiumApi`，需 `@OptIn` 才能存取
- `servicesBuilder` 為 private 屬性，無法從既有 `Publication` 取得，只能新建

### Service Loss 風險

使用新建的 `ServicesBuilder()` 可能遺失原始物件的服務（如 `positions()`）。本 Spike 觀察到進度條不可見、頁數呈現模式異常，可能與此有關。正式實作時需評估是否需要複製原始的 `servicesBuilder`（但因其為 private，可能需要反射或其他方式）。

### 下一步

1. 將 `Publication.Builder` 重建邏輯納入正式實作
2. 評估 Service Loss 影響（進度條、頁數呈現）
3. 依使用者需求新增「封面獨立顯示」功能
4. 更新 Issue 16 狀態，進入正式實作

---

## Issue 19 Discovery（2026-07-30，`/grill-with-docs`）

Issue 18 GO 後，人類決定：Issue 16 結案，完整實作交由新增的 Issue 19 承接；Service Loss（進度條/頁數呈現異常）另開 Issue 20 獨立排查，不阻擋 Issue 19。本次 grilling 針對 Issue 19 文件遺留的「待確認技術問題」（是否仍需要顯式 Dart→Kotlin `isForceFxl` 旗標）與是否需要 ADR 展開。

### 查證發現

檢視 `reader_screen.dart:291-309`（`_resolveEpubEngineDispatch()`）確認：`EpubReaderView`（FXL 路徑 widget）只會在 `_dispatchedIsFixedLayout == true` 時被建構，這個條件涵蓋三種情況——(a) 使用者按「強制 FXL」、(b) `detectAndCacheEpubLayout()` 自動判斷為 FXL、(c) 未提供 `libraryRepository` 時的既有退回預設值（一律視為 FXL）。Dart 端目前不會、也不需要區分這三種情況；三者最終都應該得到同一個結果——Kotlin 端渲染成 FXL。

進一步檢視 `EpubReaderView.kt` 的 `openBook()`／`attachNavigator()`（`:856-924`）確認：`attachNavigator()` 只會在上述三種情況之一成立時才會被呼叫。也就是說，一旦程式跑到這個函式，「這本書該渲染成 FXL」在 Dart 端已經是定案——`openedPublication.metadata.layout != Layout.FIXED` 這個 Kotlin 端運行時判斷式，已完整表達「Readium 官方解析器不同意上游決定」，資訊量等同一個恆為 `true` 的顯式旗標。

檢視 `epub_reader_view.dart:326`（Issue 16「額外發現」提到的未受保護 `_isFixedLayout`）進一步確認：`reportLayoutResolved()`（`EpubReaderView.kt:1199`）修復後若統一改讀 `effectivePublication`，其回報給 Dart 端的 `isFixedLayout` 理論上將恆為 `true`（因為判斷不對時已在 Kotlin 端強制覆寫）——這個既有 bug 在正常路徑下的觸發條件會隨本次修復一併消失，但仍建議保留防禦性保護，因應 `Publication.Builder` 重建失敗等邊界情況。

### 決策（人類已確認）

1. **不做 Dart→Kotlin `isForceFxl` 旗標傳遞管線**：改用 Kotlin 端 `attachNavigator()` 內對 `openedPublication.metadata.layout != Layout.FIXED` 的運行時判斷，效果與顯式旗標完全等同，省去一條沒有額外資訊量的傳遞管線與對稱的 Dart/Kotlin 契約維護成本。**人類特別確認**：此決策不影響、不削弱使用者透過 Issue 15「強制 FXL」按鈕做出的手動決定——那個決定完整保留在 Dart 端引擎分派這一層（`Book.isFixedLayout`），不受本次 Kotlin 端內部實作方式影響。
2. **`epub_reader_view.dart:326` 降級為防禦性修法**：不再是本次修復的核心手段（核心手段是 Kotlin 端統一改讀 `effectivePublication`，理論上會讓 native 端不再回報不一致的 `false`），但仍保留這個防護，作為邊界情況（例如 `Publication.Builder` 重建拋例外、退回原始物件）的防禦層。
3. **新增 ADR 0016**：本次技術方向（重建 `Publication` 物件、繞過 Readium 官方 metadata 判讀、接受服務遺失風險換取雙頁渲染）符合 ADR 三要件——難以憑直覺理解（為何不用官方 `Configuration` 介面）、真實的權衡（`servicesBuilder` 為 private、重建必然遺失部分服務，是刻意接受的代價）、有 Issue 17 NO-GO 這個已排除的替代方案值得記錄——比照本 Epic 既有 ADR 0011／0013 慣例另立正式 ADR。

### 範圍界定

- 本次 Discovery 只收斂「旗標傳遞機制」與「是否需要 ADR」這兩個決策點；`Publication.Builder` 重建的具體程式碼結構、隔離架構（`publication` vs `effectivePublication`）已於 Issue 18 Spike 驗證，直接沿用，不重新開放討論。
- Service Loss（進度條/頁數呈現異常）本身的修復不在本次 Discovery 範圍，已另立 Issue 20。

### 相關佐證

- `docs/adr/0016-fxl-metadata-override-via-publication-builder.md`
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 15／16／17／18／19／20
- `app/lib/screens/reader_screen.dart:291-309`
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:164,501,856-924,998,1199`
- `app/lib/reader/epub_reader_view.dart:326`

### 報告路徑

完整報告見 `docs/epics/epic-18-reader-device-qa/reviews/spike-issue18-publication-builder-override.md`
