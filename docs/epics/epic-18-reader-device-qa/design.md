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
| 選取控點拖曳偵測 | 待驗證 | 需 Issue 10 整合 foliate-js 後驗證 |

### 結論

**GO** — `flutter_inappwebview` 在真機上展現的 touch handling 與 DOM 事件轉發能力，解決了標準 Android WebView + Flutter PlatformView 的根本限制。ES module 載入不踩既有 CORS/MIME 陷阱。與 anx-reader 架構一致，已有成功先例。

### 下一步

- Issue 10：整合 `flutter_inappwebview` 到 `FoliateEpubReaderView`，驗證選取控點拖曳偵測
- 保留 `flutter_inappwebview` 依賴（供 Issue 10 繼續使用）

### 報告路徑

完整報告見 `docs/epics/epic-18-reader-device-qa/reviews/spike-flutter-inappwebview-selection.md`
